extends Node

## 1v1车轮战回归测试。验证默认设置、122221抓将、暗将隐私、三将阵容、首回合摸牌与连续换将胜负。

## 保留自动抓将和阶段流程；阵亡夹具自行驱动战斗，避免后台AI抢先打出牌。
class ReplacementController extends MatchController:
	## 开局和换将断言期间不安排普通出牌；响应与选将仍走正式入口。
	func _schedule_ai_action() -> void:
		pass

## 权威控制器；用于验证完整开局与死亡换将流程。
var _controller: MatchController

## 测试前模式；结束时恢复，避免污染后续手动开局。
var _original_mode: String = "identity"

## 测试前明置候选数量；结束时恢复。
var _original_face_up_count: int = 6

## 测试前暗置候选数量；结束时恢复。
var _original_face_down_count: int = 4


## 延迟执行以等待自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行纯服务、设置、完整开局与换将断言。
func _run() -> void:
	_original_mode = str(GameSettings.next_match_mode)
	_original_face_up_count = GameSettings.wheel_duel_face_up_candidate_count
	_original_face_down_count = GameSettings.wheel_duel_face_down_candidate_count
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(false)
	if not _test_settings_and_identity_rules():
		return
	if not _test_draft_service_and_privacy():
		return
	if not await _test_selection_panel_renders_hidden_candidates_and_lineup():
		return
	if not await _test_full_ai_match_bootstrap_and_replacement():
		return
	_restore_settings()
	print("WHEEL_DUEL_MODE_PASS settings+draft122221+privacy+lineup+bootstrap+draw_penalty+replacement+winner")
	get_tree().quit(0)


## 验证明暗默认值、固定人数与红蓝身份表。
func _test_settings_and_identity_rules() -> bool:
	if GameSettings.DEFAULT_WHEEL_DUEL_FACE_UP_CANDIDATE_COUNT != 6 or GameSettings.DEFAULT_WHEEL_DUEL_FACE_DOWN_CANDIDATE_COUNT != 4:
		return _fail("default_candidates")
	var rules: IdentityRules = IdentityRules.new()
	if not rules.supports_player_count(IdentityRules.MODE_WHEEL_DUEL, 2) or rules.supports_player_count(IdentityRules.MODE_WHEEL_DUEL, 3):
		return _fail("player_count")
	if rules.get_distribution(2, IdentityRules.MODE_WHEEL_DUEL) != ["red", "blue"]:
		return _fail("identity_distribution")
	if not rules.starts_from_first_seat(IdentityRules.MODE_WHEEL_DUEL):
		return _fail("first_seat_start")
	return true


## 验证后手开始的122221顺序、暗将不进入对手快照以及双方各自提交三将阵容。
func _test_draft_service_and_privacy() -> bool:
	var service: WheelDuelSelectionService = WheelDuelSelectionService.new()
	var players: Array[PlayerState] = [PlayerState.new(0, "先手"), PlayerState.new(1, "后手")]
	var character_ids: Array[String] = []
	for index: int in range(12):
		character_ids.append("test_character_%d" % index)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260722
	var begin_error: String = service.begin(players, character_ids, 6, 4, rng)
	if not begin_error.is_empty():
		return _fail("service_begin=%s" % begin_error)
	var expected_drafters: Array[int] = [1, 0, 0, 1, 1, 0, 0, 1, 1, 0]
	for expected_drafter: int in expected_drafters:
		if service.get_current_drafter_id() != expected_drafter:
			return _fail("draft_order expected=%d got=%d" % [expected_drafter, service.get_current_drafter_id()])
		var private_snapshot: Dictionary = service.to_dict(expected_drafter)
		var slots: Array = private_snapshot.get("pool_slots", []) as Array
		if slots.is_empty():
			return _fail("empty_pool")
		for slot_variant: Variant in slots:
			var slot: Dictionary = slot_variant as Dictionary
			if not bool(slot.get("face_up", false)) and not str(slot.get("character_id", "")).is_empty():
				return _fail("hidden_candidate_leaked")
		# 当前仍未被选择的首个槽；已选槽保留原位并通过selection_owner公开相对归属。
		var available_slot_id: int = -1
		for slot_variant: Variant in slots:
			var slot: Dictionary = slot_variant as Dictionary
			if str(slot.get("selection_owner", "")).is_empty():
				available_slot_id = int(slot.get("slot_id", -1))
				break
		if available_slot_id < 0:
			return _fail("no_available_slot")
		# 被选槽原始明暗状态；选择后必须与此值完全一致。
		var selected_slot_was_face_up: bool = bool((slots[available_slot_id] as Dictionary).get("face_up", false))
		var pick_error: String = service.pick_candidate(expected_drafter, available_slot_id)
		if not pick_error.is_empty():
			return _fail("pick=%s" % pick_error)
		var post_pick_snapshot: Dictionary = service.to_dict(expected_drafter)
		var post_pick_slots: Array = post_pick_snapshot.get("pool_slots", []) as Array
		# 被选择槽保持原始明暗状态；明置槽继续公开真实武将，暗置槽继续隐藏真实武将。
		var picked_slot: Dictionary = post_pick_slots[available_slot_id] as Dictionary
		if post_pick_slots.size() != 10 or str(picked_slot.get("selection_owner", "")) != "self" or bool(picked_slot.get("face_up", false)) != selected_slot_was_face_up:
			return _fail("picked_slot_should_preserve_visibility")
		if selected_slot_was_face_up != not str(picked_slot.get("character_id", "")).is_empty():
			return _fail("picked_slot_character_privacy")
	if service.phase != WheelDuelSelectionService.PHASE_LINEUP:
		return _fail("phase_after_draft=%s" % service.phase)
	for player_id: int in [0, 1]:
		var drafted: Array[String] = service.get_drafted_characters(player_id)
		if drafted.size() != 5:
			return _fail("drafted_count_%d=%d" % [player_id, drafted.size()])
		var lineup_error: String = service.submit_lineup(player_id, drafted.slice(0, 3))
		if not lineup_error.is_empty():
			return _fail("lineup_%d=%s" % [player_id, lineup_error])
	if service.phase != WheelDuelSelectionService.PHASE_COMPLETE:
		return _fail("lineup_not_complete")
	return true


## 验证正式选将组件能够以牌背渲染暗置槽，并按点击顺序保存三名出场武将。
func _test_selection_panel_renders_hidden_candidates_and_lineup() -> bool:
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main_instance: Node = main_scene.instantiate()
	add_child(main_instance)
	await get_tree().process_frame
	var selection_panel: CharacterSelectionPanel = main_instance.get_node("CharacterSelectionPanel") as CharacterSelectionPanel
	var match_menu: MatchMenu = main_instance.get_node("MatchMenu") as MatchMenu
	var available_ids: Array = GameDatabase.characters.keys()
	if selection_panel == null or match_menu == null or available_ids.size() < 5:
		main_instance.queue_free()
		return _fail("selection_panel_setup")
	match_menu.set_match_mode(GameSettings.MATCH_MODE_WHEEL_DUEL)
	var face_up_row: Control = main_instance.get_node("%WheelDuelFaceUpCandidateRow") as Control
	var face_down_row: Control = main_instance.get_node("%WheelDuelFaceDownCandidateRow") as Control
	var normal_candidate_row: Control = main_instance.get_node("MatchMenu/MenuPanel/MenuVBox/CharacterCandidateCountRow") as Control
	if match_menu.z_index <= selection_panel.z_index or not face_up_row.visible or not face_down_row.visible or normal_candidate_row.visible:
		main_instance.queue_free()
		return _fail("wheel_menu_mode_or_layer")
	var pool_slots: Array[Dictionary] = []
	for slot_index: int in range(10):
		pool_slots.append({"slot_id":slot_index, "face_up":slot_index < 6, "character_id":str(available_ids[slot_index]) if slot_index < 6 else "", "selection_owner":"self" if slot_index == 0 else ("opponent" if slot_index == 1 else "")})
	selection_panel.bind_snapshot({
		"selection_kind":"wheel_duel",
		"phase":WheelDuelSelectionService.PHASE_DRAFT,
		"can_select":true,
		"local_identity":"blue",
		"pool_slots":pool_slots,
		"remaining_picks_in_batch":1,
	})
	await get_tree().process_frame
	var candidate_views: Dictionary = selection_panel.get("_candidate_views") as Dictionary
	if not selection_panel.visible or candidate_views.size() != 10 or not candidate_views.has("slot:9"):
		main_instance.queue_free()
		return _fail("hidden_candidate_render")
	var self_picked_view: PlayerTargetView = candidate_views.get("slot:0") as PlayerTargetView
	var opponent_picked_view: PlayerTargetView = candidate_views.get("slot:1") as PlayerTargetView
	if self_picked_view == null or opponent_picked_view == null or self_picked_view.is_interactable or opponent_picked_view.is_interactable or str((self_picked_view.get_node("CenterStatusMarker") as Label).text) != "我方选择" or str((opponent_picked_view.get_node("CenterStatusMarker") as Label).text) != "对方选择":
		main_instance.queue_free()
		return _fail("picked_candidate_markers")
	# 未轮到本地抓将时的共享界面；双方使用同一个候选池，面板必须常驻可见，只有尚未被选走的槽位改为不可点击。
	selection_panel.bind_snapshot({
		"selection_kind":"wheel_duel",
		"phase":WheelDuelSelectionService.PHASE_DRAFT,
		"can_select":false,
		"local_identity":"blue",
		"pool_slots":pool_slots,
		"remaining_picks_in_batch":1,
	})
	await get_tree().process_frame
	var waiting_views: Dictionary = selection_panel.get("_candidate_views") as Dictionary
	# 仍未归属任何一方的公共槽；未轮到时它保留完整牌面但不得接受点击，避免提交必然被规则层拒绝。
	var waiting_open_view: PlayerTargetView = waiting_views.get("slot:2") as PlayerTargetView
	if not selection_panel.visible or waiting_open_view == null or waiting_open_view.is_interactable or (selection_panel.get("_confirm_button") as Button).visible:
		main_instance.queue_free()
		return _fail("draft_shared_panel_waiting")
	var drafted_ids: Array[String] = []
	for index: int in range(5):
		drafted_ids.append(str(available_ids[index]))
	selection_panel.bind_snapshot({
		"selection_kind":"wheel_duel",
		"phase":WheelDuelSelectionService.PHASE_LINEUP,
		"can_select":true,
		"local_identity":"blue",
		"local_drafted_characters":drafted_ids,
	})
	selection_panel.call("_select_candidate", drafted_ids[0])
	selection_panel.call("_select_candidate", drafted_ids[1])
	selection_panel.call("_select_candidate", drafted_ids[2])
	var selected_lineup: Array[String] = selection_panel.get("_selected_wheel_duel_lineup") as Array[String]
	if selected_lineup != drafted_ids.slice(0, 3):
		main_instance.queue_free()
		return _fail("lineup_click_order")
	# 退出对局清理前置；恢复一份带归属标记的抓将快照，让“我方选择”“对方选择”文本真实存在于候选牌上。
	selection_panel.bind_snapshot({
		"selection_kind":"wheel_duel",
		"phase":WheelDuelSelectionService.PHASE_DRAFT,
		"can_select":true,
		"local_identity":"blue",
		"pool_slots":pool_slots,
		"remaining_picks_in_batch":1,
	})
	await get_tree().process_frame
	# 退出对局后的界面清理；主菜单可见时必须关闭选将遮罩并释放候选牌，否则车轮战标记文本会留在主菜单之上。
	var main_menu_node: Node = main_instance.get("main_menu") as Node
	if main_menu_node == null or not selection_panel.visible:
		main_instance.queue_free()
		return _fail("main_menu_reference")
	main_menu_node.set("visible", true)
	main_instance.call("_sync_match_menu_visibility")
	await get_tree().process_frame
	if selection_panel.visible or not (selection_panel.get("_candidate_views") as Dictionary).is_empty() or not (selection_panel.get("_snapshot") as Dictionary).is_empty():
		main_instance.queue_free()
		return _fail("selection_panel_cleared_on_return")
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 纯AI完成专属选将后进入对战，并验证前两将换将、第三将触发蓝方胜利。
func _test_full_ai_match_bootstrap_and_replacement() -> bool:
	_create_controller()
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_WHEEL_DUEL)
	GameSettings.set_wheel_duel_face_up_candidate_count(6)
	GameSettings.set_wheel_duel_face_down_candidate_count(4)
	if not _controller.start_match(2, 20260722, IdentityRules.MODE_WHEEL_DUEL):
		return _fail("start_match")
	await get_tree().process_frame
	if _controller.state.current_phase == "wheel_duel_selection":
		return _fail("ai_selection_stuck")
	var red_player: PlayerState = _controller.state.players[0]
	var blue_player: PlayerState = _controller.state.players[1]
	if red_player.identity != "red" or blue_player.identity != "blue":
		return _fail("seat_identity")
	if red_player.wheel_duel_lineup.size() != 3 or blue_player.wheel_duel_lineup.size() != 3:
		return _fail("lineup_size")
	if _controller.call("_get_phase_draw_base_count", red_player.player_id) != 1:
		return _fail("first_turn_draw_penalty")
	for defeated_index: int in range(2):
		red_player.hp = 0
		_controller.call("_resolve_death", red_player.player_id, blue_player.player_id)
		if not red_player.alive or red_player.wheel_duel_defeated_count != defeated_index + 1 or red_player.wheel_duel_lineup_index != defeated_index + 1:
			return _fail("replacement_%d" % defeated_index)
		if red_player.hp != red_player.max_hp or red_player.hand.size() < 4:
			return _fail("replacement_resources_%d" % defeated_index)
	red_player.hp = 0
	_controller.call("_resolve_death", red_player.player_id, blue_player.player_id)
	if red_player.alive or not _controller.state.game_over or _controller.state.winner != "blue_team":
		return _fail("third_death_winner=%s" % _controller.state.winner)
	return true


## 创建与正式场景一致的最小控制器组件树；本地玩家ID为-1使双方均由AI驱动。
func _create_controller() -> void:
	_controller = ReplacementController.new()
	_controller.name = "MatchController"
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = -1
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 恢复本测试修改的全局设置。
func _restore_settings() -> void:
	GameSettings.set_wheel_duel_face_up_candidate_count(_original_face_up_count)
	GameSettings.set_wheel_duel_face_down_candidate_count(_original_face_down_count)
	GameSettings.set_next_match_mode(_original_mode)


## 失败出口；输出稳定标记并以非零状态结束无头测试。
func _fail(reason: String) -> bool:
	printerr("WHEEL_DUEL_MODE_FAIL %s" % reason)
	_restore_settings()
	get_tree().quit(1)
	return false
