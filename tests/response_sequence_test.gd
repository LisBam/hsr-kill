extends "res://tests/damage_sequence_test.gd"

## 响应生命周期专项；结果对象只能在全部消费窗口和子内容结束后完成。


## 普通、装备多材料、救援与同时无懈分别覆盖独立的父内容等待边界。
func _run() -> void:
	for timing_name: String in ["respondBefore", "respondBegin", "loseBefore", "loseBegin", "loseEnd", "loseAfter", "discardBefore", "discardBegin", "cardsDiscardAfter", "respond", "respondEnd", "respondAfter"]:
		_test_response_window(timing_name)
	for timing_name: String in ["respondBefore", "respondBegin", "loseBefore", "loseBegin"]:
		_test_cancel_response(timing_name)
	_test_nested_damage()
	_test_equipment_materials()
	_test_rescue_after()
	_test_rescue_nested_damage()
	_test_simultaneous_negation_after()
	_test_step_response()
	_test_preview_negation_after()
	await _test_preview_negation_budget()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("RESPONSE_SEQUENCE_PASS windows=12 cancellation nested equipment rescue simultaneous_negation step_result preview")
	get_tree().quit(1 if _failed else 0)


## 每个窗口暂停时保持最终结果未完成；响应历史只在费用完成后提交一次。
func _test_response_window(timing_name: String) -> void:
	_reset_controller()
	# 普通闪材料；使用打出语义以覆盖respond主体、End和After。
	var card: CardInstance = _add_response_card(0, "shan")
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 响应结果对象；false表示等待，不能与明确放弃混同。
	var resolution: RefCounted = _controller.begin_response_resolution(0, card.uid, ["shan"], [], "", {"response_action":"play"})
	_check(_controller.has_pending_card_choice() and not resolution.completed, timing_name + " returned early")
	if timing_name in ["respondBefore", "respondBegin", "loseBefore", "loseBegin"]:
		_check(card.zone == "hand" and _controller.state.get_player(0).response_history.is_empty(), timing_name + " consumed before completion")
	elif timing_name in ["loseEnd", "loseAfter", "discardBefore", "discardBegin"]:
		_check(card.zone == "processing", timing_name + " discarded before completion")
	_submit_choice()
	_check(resolution.completed and resolution.result == card and card.zone == "discard_pile", timing_name + " lost result or card")
	_check(_controller.state.get_player(0).response_history.size() == 1, timing_name + " repeated history")
	_check_clean(timing_name)


## 异步取消respond或失牌前置时不能消费实体，也不能生成成功响应历史。
func _test_cancel_response(timing_name: String) -> void:
	_reset_controller()
	# 未支付的响应牌；取消后须仍由原持有者拥有。
	var card: CardInstance = _add_response_card(0, "shan")
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 本次可中断的结果；完成后null明确表示取消。
	var resolution: RefCounted = _controller.begin_response_resolution(0, card.uid, ["shan"])
	if _paused_event != null:
		_paused_event.cancel("test_response_cancel")
	_submit_choice()
	_check(resolution.completed and resolution.result == null and card.zone == "hand", timing_name + " cancelled response consumed")
	_check(_controller.state.get_player(0).response_history.is_empty(), timing_name + " cancelled response counted")
	_check_clean(timing_name + " cancellation")


## 响应After中的子伤害先完成，响应结果和外层调用者才能继续。
func _test_nested_damage() -> void:
	_reset_controller()
	# 普通响应实体；子伤害不依赖其牌效。
	var card: CardInstance = _add_response_card(0, "shan")
	_controller.trigger_manager.subscribe("damageBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("respondAfter", self, func(_event: RuleEvent) -> void: _controller.damage(0, 1, 1))
	# 等待After子内容的结果对象。
	var resolution: RefCounted = _controller.begin_response_resolution(0, card.uid, ["shan"], [], "", {"response_action":"play"})
	_check(not resolution.completed and _controller.state.get_player(1).hp == 20, "response skipped child damage")
	_submit_choice()
	_check(resolution.completed and _controller.state.get_player(1).hp == 19, "response did not finish child damage once")
	_check_clean("response nested damage")


## 丈八响应两张材料逐张等待，不能在首张失牌After中提前支付第二张。
func _test_equipment_materials() -> void:
	_reset_controller()
	# 正式丈八入口；装备本身不离区，只有两张普通手牌承担费用。
	var weapon: CardInstance = CardInstance.new("zhangba", "spade", 12)
	weapon.zone = "equipment"
	weapon.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = weapon
	# 两张真实手牌费用；同色聚合保留黑色而不继承点数。
	var first: CardInstance = _add_response_card(0, "shan")
	# 第二张费用；前张子时机完成前仍须留在手牌。
	var second: CardInstance = _add_response_card(0, "tao")
	_controller.trigger_manager.subscribe("loseAfter", self, _pause_window)
	# 装备响应结果；直接走正式装备定义声明材料方案。
	var resolution: RefCounted = _controller.begin_response_resolution(0, weapon.uid, ["sha"], [first.uid, second.uid])
	_check(not resolution.completed and first.zone == "processing" and second.zone == "hand", "equipment response moved next material early")
	_submit_choice()
	_check(not resolution.completed and first.zone == "discard_pile" and second.zone == "processing", "equipment response skipped second material wait")
	_submit_choice()
	_check(resolution.completed and resolution.result != null and resolution.result.definition_id == "sha", "equipment response result missing")
	_check(first.zone == "discard_pile" and second.zone == "discard_pile" and weapon.zone == "equipment", "equipment response material zones")
	_check_clean("equipment response")


## 桃的使用After尚未结束时，救援目标不能提前回复或发布获救结果。
func _test_rescue_after() -> void:
	_reset_controller()
	# 唯一救援桃；目标0是本轮首位救援者。
	var peach: CardInstance = _add_response_card(0, "tao")
	_controller.state.get_player(0).hp = 0
	_controller.trigger_manager.subscribe("useCardAfter", self, _pause_window)
	_controller._resolve_dying(0, 1)
	_submit_response_uid(peach.uid)
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(0).hp == 0 and _controller.state.get_player(0).dying, "rescue healed before response After")
	_submit_choice()
	_check(_controller.state.get_player(0).hp == 1 and not _controller.state.get_player(0).dying and peach.zone == "discard_pile", "rescue result not applied once")
	_check_clean("rescue response After")


## 同时无懈的获胜者先关闭同轮其他窗口；其After完成前不能提前取消原锦囊目标。
func _test_simultaneous_negation_after() -> void:
	_reset_controller()
	# 被保护的目标手牌；锦囊被无懈后应保留。
	var protected: CardInstance = _add_response_card(1, "shan")
	# 唯一无懈材料；归属于0号获胜响应者。
	var counter: CardInstance = _add_response_card(0, "wuxie")
	# 原锦囊实体；完整用牌链不能在无懈After等待时结束。
	var trick: CardInstance = _add_response_card(0, "guohe")
	_controller.trigger_manager.subscribe("useCardAfter", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "wuxie":
			_pause_window(event)
	)
	_controller._execute_card_use(0, trick, [1])
	# 正式同时响应请求；只有拥有无懈候选者会进入当前轮。
	var requests: Array = _controller._pending_negation_choices.values()
	_check(not requests.is_empty(), "missing simultaneous negation request")
	if requests.is_empty():
		return
	# 获胜响应动作；请求身份仍由统一submit_action校验。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(requests[0].request_id), "selected_card_uids":[counter.uid]}
	_check(_controller.submit_action(action), "simultaneous response rejected")
	_check(_controller.has_pending_card_choice() and trick.zone == "processing" and protected.zone == "hand" and _controller._pending_negation_choices.is_empty(), "negation skipped response After or kept competing requests")
	_submit_choice()
	_controller.event_scheduler.drain()
	_check(trick.zone == "discard_pile" and counter.zone == "discard_pile" and protected.zone == "hand", "negation completion lost parent result")
	_check_clean("simultaneous response After")


## 创建测试手牌实体，所有费用仍由生产移牌入口处理。
func _add_response_card(owner_id: int, definition_id: String) -> CardInstance:
	# 原始实体；稳定UID在整个响应生命周期内保持不变。
	var card: CardInstance = CardInstance.new(definition_id, "spade", 7)
	card.owner_id = owner_id
	card.zone = "hand"
	_controller.state.get_player(owner_id).hand.append(card)
	return card


## 通过正式请求号提交响应UID，不直接移动实体或释放暂停。
func _submit_response_uid(uid: int) -> void:
	# 当前权威选择；借此验证选择者与请求身份。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	# 标准响应动作；费用在后续响应序列中才提交。
	var action: PlayerAction = PlayerAction.new("choose_cards", int(request.get("chooser_id", 0)))
	action.payload = {"request_id":request.get("request_id", -1), "selected_card_uids":[uid], "confirmed":true}
	_check(_controller._submit_card_choice(action), "response choice rejected")


## 技能步骤响应使用独立结果槽；普通选择完成不等于响应After完成。
func _test_step_response() -> void:
	_reset_controller()
	# 普通响应实体；实际消费通过公开选择入口。
	var card: CardInstance = _add_response_card(0, "shan")
	# 测试技能；仅使用通用步骤API，不增加专用continue_response实现。
	var skill: SkillDefinition = SkillDefinition.new()
	skill.bind(_controller, 0)
	# 下一步实际观察结果；空集合表示父内容仍在等待。
	var observed: Array[int] = []
	_controller.trigger_manager.subscribe("respondAfter", self, _pause_window)
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: skill.request_step_response(sequence, 0, ["shan"], "步骤响应", {"response_action":"play"}),
		func(sequence: RuleStepSequence) -> void: observed.append(sequence.response_card.uid if sequence.response_card != null else -1),
	])
	_submit_response_uid(card.uid)
	_check(observed.is_empty() and _controller.has_pending_card_choice(), "step response skipped After")
	_submit_choice()
	_check(observed == [card.uid], "step response lost or repeated result " + str(observed))
	_check_clean("step response")


## 预演链也必须等待完整响应After，不能把尚未完成的响应当作放弃。
func _test_preview_negation_after() -> void:
	_reset_controller()
	# 目标自己的无懈；有害锦囊的首轮会选择抵消。
	var card: CardInstance = _add_response_card(1, "wuxie")
	_controller.trigger_manager.subscribe("useCardAfter", self, _pause_window)
	# 预演服务结果；本用例保留正式match_id以制造真人嵌套窗口。
	var resolution: RefCounted = preload("res://scripts/core/negation_preview_resolution_service.gd").new(_controller)
	resolution.begin({"source_id":0, "target_id":1, "trick_id":"guohe", "response_order_ids":[1], "response_action":"use"})
	_check(not resolution.completed and not resolution.negated and _controller.has_pending_trick_negation(), "preview parity changed before After")
	_submit_choice()
	_check(resolution.completed and resolution.negated and card.zone == "discard_pile", "preview did not accept completed response")
	_check_clean("preview After")


## 空match_id与低预算让出帧时仍保持完整链；两张无懈按交替阵营恢复原锦囊。
func _test_preview_negation_budget() -> void:
	_reset_controller()
	_controller.state.match_id = ""
	_controller.max_settlement_steps_per_pass = 2
	_add_response_card(1, "wuxie")
	_add_response_card(0, "wuxie")
	# 预演结果；它不能在第一轮尚未消费时报告最终完成。
	var resolution: RefCounted = preload("res://scripts/core/negation_preview_resolution_service.gd").new(_controller)
	resolution.begin({"source_id":0, "target_id":1, "trick_id":"guohe", "response_order_ids":[0, 1], "response_action":"use"})
	_check(not resolution.completed and _controller.has_pending_trick_negation(), "preview budget ignored")
	for attempt: int in range(160):
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if resolution.completed and _controller._rule_sequences.is_empty():
			break
		await get_tree().process_frame
	_check(resolution.completed and not resolution.negated and _controller.state.discard_pile.size() == 2, "preview budget lost chain")
	_check_clean("preview budget")


## 求桃的使用After中再次受伤，必须先完成子伤害，再回复并继续询问同一救援者。
func _test_rescue_nested_damage() -> void:
	_reset_controller()
	# 两张救援牌；第二张不能被第一次响应的临时结果覆盖。
	var first: CardInstance = _add_response_card(0, "tao")
	# 第二份费用；用于填补After中新增的一点伤害。
	var second: CardInstance = _add_response_card(0, "tao")
	_controller.state.get_player(0).hp = 0
	# 只插入一次子伤害；防止测试人为构造递归。
	var inserted: Array[bool] = [false]
	_controller.trigger_manager.subscribe("useCardAfter", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "tao" and not inserted[0]:
			inserted[0] = true
			_controller.damage(1, 0, 1)
	)
	_controller.trigger_manager.subscribe("damageBefore", self, _pause_window)
	_controller._resolve_dying(0, 1)
	_submit_response_uid(first.uid)
	_check(_controller.state.get_player(0).hp == 0 and _controller.state.get_player(0).dying, "nested rescue healed before child damage")
	_submit_choice()
	_check(_controller.state.get_player(0).hp == 0 and _controller.state.get_player(0).alive and _controller.has_pending_card_choice(), "nested rescue advanced to death or healed twice hp=%d alive=%s choice=%s" % [_controller.state.get_player(0).hp, _controller.state.get_player(0).alive, _controller._pending_card_choice])
	_submit_response_uid(second.uid)
	_check(_controller.state.get_player(0).hp == 1 and not _controller.state.get_player(0).dying and _controller.state.dying_queue.is_empty(), "nested rescue did not finish once")
	_check_clean("rescue nested damage")
