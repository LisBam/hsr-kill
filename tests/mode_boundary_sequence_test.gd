extends "res://tests/conquest_mode_test.gd"

## 真实换层在极低预算下仍等待父牌尾部；换层机缘内部的选择也由原内容自然恢复。

## 杀尾部实际进入次数；固定为1，防止恢复过程中重复发布After。
var _tail_count: int = 0

## 机缘获得后置只暂停一次，避免每张摸牌都重复打开测试选择。
var _opportunity_pause_seen: bool = false


## 复用父测试的设置隔离和正式组件树，只替换需要跨帧驱动的对局段。
func _test_full_match_replacement_flow() -> bool:
	_create_controller()
	if not _controller.start_match(2, 20260722, IdentityRules.MODE_CONQUEST) or not _controller.select_character(0, "dan_heng"):
		return _fail("boundary_start")
	for _frame_index: int in range(120):
		if _controller.state.game_over or str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	if not await _choose_safe_opportunity(0) or not _settle_pending_skill_choices():
		return _fail("boundary_opening")
	# 原玩家与敌方；清除随机武将技能，保留真实牌、濒死、死亡和模式规则。
	var player: PlayerState = _controller.state.get_player(0)
	# 原敌方代次；父牌尾部等待期间不得提前换将。
	var enemy: PlayerState = _controller.state.get_player(1)
	for participant: PlayerState in _controller.state.players:
		for skill_key: Variant in (_controller.skill_instances_by_player.get(participant.player_id, {}) as Dictionary).keys():
			_controller.remove_skill(participant.player_id, str(skill_key))
		for card: CardInstance in participant.hand.duplicate():
			_controller._move_to_discard(card)
		participant.out_of_game = false
		participant.shield = 0
	_controller._cancel_active_play_choice("boundary_setup")
	# 完整原生杀；红色避免随机防具对黑色杀的免疫干扰本专项。
	var slash: CardInstance = CardInstance.new("sha", "heart", 7)
	slash.zone = "hand"
	slash.owner_id = player.player_id
	player.hand.append(slash)
	enemy.hp = 1
	# 稳定原代次；换层必须在After及其选择完整结束后才递增。
	var generation: int = enemy.character_generation
	_controller.trigger_manager.subscribe("shaAfter", self, func(event: RuleEvent) -> void:
		if int(event.data.get("card_uid", -1)) == slash.uid:
			_tail_count += 1
			_controller.request_target_choice(0, "父牌尾部", [0], 0, 1, true, {"kind":"mode_boundary_tail"})
	)
	_controller._begin_play_choice(0)
	_controller.max_settlement_steps_per_pass = 1
	_controller.event_scheduler.max_operations_per_drain = 1
	if not _controller.submit_action(PlayerAction.new("use_card", 0, slash.uid, [1])):
		return _fail("boundary_slash_submit")
	for _frame_index: int in range(1000):
		if _choice_kind() == "mode_boundary_tail":
			break
		if _controller.has_pending_card_choice() and not _controller._has_active_play_choice():
			if not _answer_current_choice():
				return _fail("boundary_rescue_answer")
		await get_tree().process_frame
	if _choice_kind() != "mode_boundary_tail" or _tail_count != 1 or _controller._conquest_replacement_transition_active or enemy.character_generation != generation:
		return _fail("boundary_tail_missing_or_early")
	for _frame_index: int in range(3):
		await get_tree().process_frame
	if _controller._conquest_replacement_transition_active or enemy.character_generation != generation or not _controller._card_use_contexts.has(slash.uid):
		return _fail("boundary_crossed_waiting_after")
	if not _answer_current_choice():
		return _fail("boundary_tail_answer")
	for _frame_index: int in range(1000):
		if _controller.state.game_over or str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	if enemy.character_generation != generation + 1 or _tail_count != 1 or _controller._card_use_contexts.has(slash.uid) or slash.zone != "discard_pile":
		return _fail("boundary_parent_not_finished generation=%d/%d tail=%d zone=%s phase=%s transition=%s contexts=%s sequences=%s continuations=%s pauses=%s reason=%s winner=%s" % [enemy.character_generation, generation + 1, _tail_count, slash.zone, _controller.state.current_phase, _controller._conquest_replacement_transition_active, _controller._card_use_contexts, _controller._rule_sequences.keys(), _controller._rule_continuations.to_array(), _controller.event_scheduler.pause_registry.get_active_tokens(), _controller.state.end_reason, _controller.state.winner])
	# 固定合法机缘，获得After插入选择时仍须保留换层屏障和原机缘内容。
	var draw_two: Dictionary = OpportunityCatalog.get_card("green_draw_two")
	_controller.state.opportunity_state["options_by_player"] = {"0":[draw_two, OpportunityCatalog.get_card("blue_draw_three"), OpportunityCatalog.get_card("purple_draw_five")]}
	player.hp = player.max_hp - 1
	_controller.trigger_manager.subscribe("gainAfter", self, func(event: RuleEvent) -> void:
		if event.player_id == 0 and not _opportunity_pause_seen:
			_opportunity_pause_seen = true
			_controller.execute_cardless_virtual_card_use(0, "tao", [0], "", {"ignore_phase_limit":true})
	)
	_controller.trigger_manager.subscribe("recoverBefore", self, func(_event: RuleEvent) -> void:
		_controller.request_target_choice(0, "机缘子牌", [0], 0, 1, true, {"kind":"mode_boundary_opportunity"})
	)
	# 权威机缘动作；使用目录ID，不直接调用效果或释放模式暂停。
	var action: PlayerAction = PlayerAction.new("choose_opportunity", 0)
	action.payload = {"card_id":"green_draw_two"}
	if not _controller.submit_action(action):
		return _fail("boundary_opportunity_submit")
	for _frame_index: int in range(600):
		if _choice_kind() == "mode_boundary_opportunity":
			break
		await get_tree().process_frame
	if _choice_kind() != "mode_boundary_opportunity" or not _controller._conquest_replacement_transition_active:
		return _fail("boundary_opportunity_child seen=%s kind=%s phase=%s transition=%s opportunity=%s sequences=%s continuations=%s pauses=%s" % [_opportunity_pause_seen, _choice_kind(), _controller.state.current_phase, _controller._conquest_replacement_transition_active, _controller.state.opportunity_state, _controller._rule_sequences.keys(), _controller._rule_continuations.to_array(), _controller.event_scheduler.pause_registry.get_active_tokens()])
	if not _answer_current_choice():
		return _fail("boundary_opportunity_answer")
	for _frame_index: int in range(1000):
		if not _controller._conquest_replacement_transition_active and _controller.state.opportunity_state.is_empty():
			break
		await get_tree().process_frame
	if _controller._conquest_replacement_transition_active or not _controller.state.opportunity_state.is_empty() or player.hp != player.max_hp or not _controller._card_use_contexts.is_empty() or _controller.get_settlement_fault_count() != 0 or int(_controller.stall_watchdog.get_diagnostics_snapshot().hard_repair_count) != 0:
		return _fail("boundary_unfinished_or_repaired")
	print("MODE_BOUNDARY_SEQUENCE_PASS budget=1 tail_once opportunity_child faults=0 hard_repairs=0")
	return true


## 当前选择语义；仅观察权威请求，不按帧数推断子内容完成。
func _choice_kind() -> String:
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))


## 明确放弃可选响应/测试目标；不手工排空任何队列或释放暂停令牌。
func _answer_current_choice() -> bool:
	# 稳定请求快照；网络与本地入口使用同一请求身份校验。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	# 标准选择回答；无救援牌或可选目标时明确放弃。
	var action: PlayerAction = PlayerAction.new("choose_cards", int(request.get("chooser_id", -1)))
	action.payload = {"request_id":request.get("request_id", -1), "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	return _controller.submit_action(action)
