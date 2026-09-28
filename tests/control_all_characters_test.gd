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


## 验证离线选将仍由原真人与AI分别处理，进入对局后全角色控制可实时切换第一视角与控制权。
func _test_offline_controls_every_player() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_control_all_characters_enabled(true)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(3, 20260722, IdentityRules.MODE_IDENTITY):
		return _fail("offline_start")
	var initial_ai_count: int = 0
	for player: PlayerState in _controller.state.players:
		if _controller.ai_coordinator.is_ai_controlled(player.player_id):
			initial_ai_count += 1
	if initial_ai_count != 2:
		return _fail("selection_should_keep_ai_count=%d" % initial_ai_count)
	var safety: int = 0
	while _controller.state.current_phase == "character_selection" and safety < 12:
		safety += 1
		_controller.call("_emit_state")
		if _controller.local_human_player_id != 0:
			return _fail("selection_view_should_remain_primary=%d" % _controller.local_human_player_id)
		if _controller.character_selection.get_pending_player_ids().has(0):
			var candidates: Array[String] = _controller.character_selection.get_candidates(0)
			if candidates.is_empty() or not _controller.select_character(0, candidates[0]):
				return _fail("selection_submit_primary")
		await get_tree().process_frame
	if _controller.state.current_phase == "character_selection":
		return _fail("selection_stuck")
	_controller.call("_emit_state")
	# 部分武将的“游戏开始时”技能会立刻创建付费或指定目标的待处理选择（例如【铁壁】的费用目标）；
	# 此时视角跟随该选择的回答者是全角色控制的设计行为，必须先逐一取消这些开局选择，
	# 才能验证“视角交还给当前回合角色”这条规则本身。固定种子选将会随武将池变化而换人，因此不能假设开局没有技能选择。
	var opening_settle_safety: int = 0
	while not _controller._pending_card_choice.is_empty() and opening_settle_safety < 12:
		opening_settle_safety += 1
		if not _cancel_pending_choice():
			# 开局选择上下文；取消失败时列出技能来源，便于定位不可取消的请求。
			var stuck_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
			return _fail("opening_choice_settle kind=%s chooser=%d" % [str(stuck_context.get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1))])
		_controller.call("_emit_state")
	if _controller.state.current_player_id >= 0 and _controller.local_human_player_id != _controller.state.current_player_id:
		# 本局实际登场的武将；固定种子选将结果会随武将池变化，列出后便于定位差异来源。
		var lineup: Array[String] = []
		for lineup_player: PlayerState in _controller.state.players:
			lineup.append("%d=%s" % [lineup_player.player_id, lineup_player.character_id])
		return _fail("turn_view local=%d current=%d phase=%s turn=%d lineup=%s" % [_controller.local_human_player_id, _controller.state.current_player_id, str(_controller.state.current_phase), _controller.state.turn_number, str(lineup)])
	# 构造另一名角色的技能/响应选择；显式请求发布前应立即切换到该角色视角。
	var requested_player_id: int = _controller.state.players[1].player_id
	if requested_player_id == _controller.local_human_player_id:
		requested_player_id = _controller.state.players[2].player_id
	if not bool(_controller.call("_prepare_offline_controlled_view", requested_player_id)) or _controller.local_human_player_id != requested_player_id:
		return _fail("explicit_choice_view")
	if _controller.ai_coordinator.is_ai_controlled(requested_player_id):
		return _fail("explicit_choice_ai_not_released")
	# 关闭后立即恢复最初真人视角，并把临时接管的非主角色交还基础AI。
	GameSettings.set_control_all_characters_enabled(false)
	if _controller.local_human_player_id != 0 or not _controller.ai_coordinator.is_ai_controlled(requested_player_id):
		return _fail("runtime_disable_restore")
	# 再次开启无需重新开局；控制器应立刻接管当前回合或活动请求角色。
	GameSettings.set_control_all_characters_enabled(true)
	if not bool(_controller.get("_control_all_characters_enabled")):
		return _fail("runtime_enable")
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


## 取消当前待处理选择；仅用于清理开局技能产生的临时请求，必须绑定创建时的请求编号与回答者，否则会被权威入口拒绝。
func _cancel_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	# 当前请求的稳定编号与回答者；同步续接可能立刻创建下一请求，提交必须锁定该编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	# 标准选择动作；取消时不携带任何牌或目标，仅声明不发动该技能。
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	return _controller.submit_action(action)


## 失败出口；恢复设置后输出稳定错误标记并退出非零状态。
func _fail(reason: String) -> bool:
	_restore_settings()
	printerr("CONTROL_ALL_CHARACTERS_FAIL %s" % reason)
	get_tree().quit(1)
	return false
