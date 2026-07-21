extends Node

## 离线全角色控制与配套界面回归。验证控制权切换、联机隐藏、判定区避让和八卦阵默认选中。

## 测试专用设置文件；本用例修改的控制权偏好不会写入玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://control_all_characters_test_settings.cfg"

## 测试前设置文件路径；结束时恢复。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 测试前控制全部角色设置；结束时恢复实际原值。
var _original_control_all_characters_enabled: bool = false

## 测试使用的权威控制器；按正式子组件名称装配。
var _controller: MatchController


## 延迟执行，确保自动加载和全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证离线控制权、联机禁用与三项界面行为。
func _run() -> void:
	_begin_settings_isolation()
	if not await _test_offline_controls_every_player():
		return
	if not _test_lan_ignores_control_all_setting():
		return
	if not await _test_ui_visibility_judgment_offset_and_bagua_selection():
		return
	_restore_settings()
	print("CONTROL_ALL_CHARACTERS_PASS offline_views+lan_hidden+judgment_offset+bagua_preselect")
	get_tree().quit(0)


## 验证离线开局不注册任何AI，并在每次选将确认后自动切换到下一名待操作角色。
func _test_offline_controls_every_player() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_control_all_characters_enabled(true)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(3, 20260722, IdentityRules.MODE_IDENTITY):
		return _fail("offline_start")
	for player: PlayerState in _controller.state.players:
		if _controller.ai_coordinator.is_ai_controlled(player.player_id):
			return _fail("offline_player_registered_ai_%d" % player.player_id)
	var safety: int = 0
	while _controller.state.current_phase == "character_selection" and safety < 12:
		safety += 1
		var pending_player_ids: Array[int] = _controller.character_selection.get_pending_player_ids()
		if pending_player_ids.is_empty():
			break
		var expected_player_id: int = pending_player_ids[0]
		_controller.call("_emit_state")
		if _controller.local_human_player_id != expected_player_id:
			return _fail("selection_view expected=%d got=%d" % [expected_player_id, _controller.local_human_player_id])
		var candidates: Array[String] = _controller.character_selection.get_candidates(expected_player_id)
		if candidates.is_empty() or not _controller.select_character(expected_player_id, candidates[0]):
			return _fail("selection_submit_%d" % expected_player_id)
		await get_tree().process_frame
	if _controller.state.current_phase == "character_selection":
		return _fail("selection_stuck")
	_controller.call("_emit_state")
	if _controller.state.current_player_id >= 0 and _controller.local_human_player_id != _controller.state.current_player_id:
		return _fail("turn_view")
	# 构造另一名角色的技能/响应选择；显式请求发布前应立即切换到该角色视角。
	var requested_player_id: int = _controller.state.players[1].player_id
	if requested_player_id == _controller.local_human_player_id:
		requested_player_id = _controller.state.players[2].player_id
	if not bool(_controller.call("_prepare_offline_controlled_view", requested_player_id)) or _controller.local_human_player_id != requested_player_id:
		return _fail("explicit_choice_view")
	_controller.abandon_match()
	return true


## 验证任何LAN模式都会忽略全角色控制设置，并继续仅把实际本地座位视为真人。
func _test_lan_ignores_control_all_setting() -> bool:
	_create_controller(NetworkGateway.Mode.LAN)
	GameSettings.set_control_all_characters_enabled(true)
	if not _controller.start_match(2, 20260723, IdentityRules.MODE_IDENTITY):
		return _fail("lan_start")
	if bool(_controller.state.match_options.get("control_all_characters_enabled", true)):
		return _fail("lan_setting_not_ignored")
	var ai_player_count: int = 0
	for player: PlayerState in _controller.state.players:
		if _controller.ai_coordinator.is_ai_controlled(player.player_id):
			ai_player_count += 1
	if ai_player_count != 1:
		return _fail("lan_ai_count=%d" % ai_player_count)
	_controller.abandon_match()
	return true


## 验证联机时两个设置入口隐藏、本地判定区右移，以及八卦阵独立询问自动预选装备UID。
func _test_ui_visibility_judgment_offset_and_bagua_selection() -> bool:
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	await get_tree().process_frame
	var main_checkbox: CheckBox = main_instance.get_node("%MainMenuControlAllCharactersCheckBox") as CheckBox
	var match_checkbox: CheckBox = main_instance.get_node("%ControlAllCharactersCheckBox") as CheckBox
	if main_checkbox == null or match_checkbox == null or not main_checkbox.visible or not match_checkbox.visible:
		main_instance.queue_free()
		return _fail("offline_checkbox_visibility")
	main_instance.match_controller.network_gateway.mode = NetworkGateway.Mode.LAN
	main_instance.call("_refresh_match_menu_authority_controls")
	if main_checkbox.visible or match_checkbox.visible:
		main_instance.queue_free()
		return _fail("lan_checkbox_visibility")
	main_instance.match_controller.network_gateway.mode = NetworkGateway.Mode.OFFLINE
	main_instance.call("_refresh_match_menu_authority_controls")
	main_instance.call("_layout_local_judgment_zone")
	var hand_panel: Control = main_instance.get_node("HandPanel") as Control
	var judgment_zone: JudgmentZoneView = main_instance.get("local_judgment_zone") as JudgmentZoneView
	var expected_offset: float = minf(main_instance.local_judgment_zone_left_offset, maxf(hand_panel.size.x - 1.0, 0.0))
	if judgment_zone == null or not is_equal_approx(judgment_zone.position.x, hand_panel.position.x + expected_offset):
		main_instance.queue_free()
		return _fail("judgment_offset")
	main_instance.match_controller.local_human_player_id = 0
	var bagua_uid: int = 88001
	# 八卦阵独立响应请求；候选属于当前第一视角装备区，界面应直接写入内联临时选择。
	var bagua_choice: Dictionary = {
		"request_id":99001,
		"chooser_id":0,
		"choice_type":"respond",
		"title":"八卦阵",
		"prompt":"是否发动【八卦阵】？",
		"candidates":[{"uid":bagua_uid, "owner_id":0, "zone":"equipment", "slot":"armor", "visible":true, "card_data":{"uid":bagua_uid, "definition_id":"bagua", "suit":"club", "rank":2}}],
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"context":{"immediate_response_equipment_uid":bagua_uid},
	}
	main_instance.call("_on_card_choice_requested", bagua_choice)
	var inline_selected_uids: Array[int] = main_instance.get("_inline_selected_card_uids") as Array[int]
	if inline_selected_uids != [bagua_uid]:
		main_instance.queue_free()
		return _fail("bagua_preselect=%s" % str(inline_selected_uids))
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 创建指定网络模式的最小正式控制器组件树。
func _create_controller(network_mode: NetworkGateway.Mode) -> void:
	if _controller != null and is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
	_controller = MatchController.new()
	_controller.name = "MatchController"
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	network_gateway.mode = network_mode
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 把本用例全部设置写入切换到独立临时文件，并保存需要恢复的正式状态。
func _begin_settings_isolation() -> void:
	_original_settings_file_path = GameSettings.get_settings_file_path()
	_original_control_all_characters_enabled = GameSettings.control_all_characters_enabled
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)


## 恢复设置、清空临时写盘并删除测试文件。
func _restore_settings() -> void:
	GameSettings.set_control_all_characters_enabled(_original_control_all_characters_enabled)
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))


## 失败出口；恢复设置后输出稳定错误标记并退出非零状态。
func _fail(reason: String) -> bool:
	_restore_settings()
	printerr("CONTROL_ALL_CHARACTERS_FAIL %s" % reason)
	get_tree().quit(1)
	return false
