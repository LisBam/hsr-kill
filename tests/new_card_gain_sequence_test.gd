extends "res://tests/card_single_sequence_test.gd"

## 新实体获得与铸造来源检索的异步边界；使用正式获得内容，不提前插入处理区或手牌。


func _run() -> void:
	for mode: String in ["outside", "mint"]:
		for timing_name: String in ["gainBefore", "gainBegin", "gainEnd", "gainAfter", "cardsGainedBatchAfter"]:
			await _test_new_gain(mode, timing_name, false)
		await _test_new_gain(mode, "gainBefore", true)
		await _test_new_gain(mode, "gainBegin", true)
	await _test_changed_receiver()
	await _test_nested_name_conflict()
	await _test_gain_child()
	await _test_source_lookup(true)
	await _test_source_lookup(false)
	await _test_yitai_reservation(true)
	await _test_yitai_reservation(false)
	if _controller != null:
		_controller.free()
	if not _failed:
		print("NEW_CARD_GAIN_SEQUENCE_PASS outside mint windows cancellation nested generation quota")
	get_tree().quit(1 if _failed else 0)


## 两类造牌共用同一获得游标；前置没有新实体，后置实体已提交但完整结果仍pending。
func _test_new_gain(mode: String, timing_name: String, cancel_move: bool) -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 本次独立结果；普通专属牌和自定义造牌只在数据准备上不同。
	var result: CardMoveResolutionService = _controller.create_card_in_player_hand(0, "yanling") if mode == "outside" else _controller.mint_card_for_player(0, "sha", "窗口造牌", "heart", 8, "yitai")
	_check(_controller.has_pending_card_choice() and not result.completed, "new gain skipped " + mode + timing_name)
	_check(_controller.state.processing_area.is_empty() and _controller.state.get_player(0).hand.size() == (0 if timing_name in ["gainBefore", "gainBegin"] else 1), "new gain registered before commit " + timing_name)
	if cancel_move:
		_paused_event.cancel("test_cancel_new_gain")
	_submit_choice()
	await _settle_single()
	_check(result.completed and bool(result.result.get("success", false)) != cancel_move and result.count == (0 if cancel_move else 1), "new gain final result " + mode + timing_name)
	_check(_controller.state.get_player(0).hand.size() == (0 if cancel_move else 1) and _controller.state.processing_area.is_empty(), "new gain created/leaked entity " + mode)
	_check_clean("new gain " + mode + timing_name)


## 等待期间换将使原获得失效，不能把已准备的新实体塞给新武将。
func _test_changed_receiver() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("gainBegin", self, _pause_window)
	# 原代次请求；名字不能在失败后继续占用。
	var result: CardMoveResolutionService = _controller.mint_card_for_player(0, "sha", "代次造牌", "club", 7, "yitai")
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 0 and _controller.state.get_player(0).hand.is_empty() and _controller.is_card_name_available("代次造牌"), "new gain used changed character")
	_check_clean("new gain generation")


## 嵌套造牌先占用同名时，外层提交重新验证唯一性，只允许一张真正入手。
func _test_nested_name_conflict() -> void:
	_reset_controller()
	# 子造牌结果；持有句柄仅供事实断言，不参与调度。
	var children: Array[CardMoveResolutionService] = []
	_controller.trigger_manager.subscribe("gainBefore", self, func(event: RuleEvent) -> void:
		if event.target_id == 0:
			children.append(_controller.mint_card_for_player(1, "shan", "唯一造牌", "heart", 5, "yitai"))
	)
	# 外层先准备、后提交；子效果可合法抢先占用名字。
	var result: CardMoveResolutionService = _controller.mint_card_for_player(0, "sha", "唯一造牌", "club", 7, "yitai")
	await _settle_single()
	_check(result.completed and result.count == 0 and children.size() == 1 and children[0].completed and children[0].count == 1 and _controller.state.get_player(0).hand.is_empty() and _controller.state.get_player(1).hand.size() == 1, "nested mint duplicated occupied name")
	_check_clean("nested mint name")


## 新实体获得After插入伤害，调用方下一步必须等待子伤害完整结束。
func _test_gain_child() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("gainAfter", self, func(_event: RuleEvent) -> void: _controller.damage(0, 1, 1))
	_controller.trigger_manager.subscribe("damageBefore", self, _pause_window)
	# 父序列后继观察值；暂停期间不得提前写入。
	var observed: Array[int] = []
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: sequence.effect_result = _controller.create_card_in_player_hand(0, "yanling"),
		func(_sequence: RuleStepSequence) -> void: observed.append(_controller.state.get_player(1).hp),
	])
	_check(_controller.has_pending_card_choice() and observed.is_empty() and _controller.state.get_player(1).hp == 20, "new gain skipped child damage")
	_submit_choice()
	await _settle_single()
	_check(observed == [19], "new gain resumed parent before child")
	_check_clean("new gain child")


## 铸造来源检索沿用通用获得窗口与私有知识，不允许取消后仍从原堆取走。
func _test_source_lookup(cancel_move: bool) -> void:
	_reset_controller()
	# 来源匹配的真实牌堆实体；保留公开知识以验证取消不重置。
	var card: CardInstance = CardInstance.new("shan", "club", 6)
	card.minted_skill_id = "yitai"
	card.custom_display_name = "来源造牌"
	card.zone = "draw_pile"
	card.known_to.assign([0, 1, 2])
	_controller.state.draw_pile.append(card)
	_controller.trigger_manager.subscribe("gainBegin", self, _pause_window)
	# 来源检索结果；仅锁定原第一候选，不在取消后自动改取下一张。
	var result: CardMoveResolutionService = _controller.gain_top_minted_card_from_draw_or_discard(0, "yitai")
	_check(not result.completed and card.zone == "draw_pile", "mint source gained before window")
	if cancel_move:
		_paused_event.cancel("test_source_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == (0 if cancel_move else 1) and card.zone == ("draw_pile" if cancel_move else "hand") and card.known_to == ([0, 1, 2] if cancel_move else [0]), "mint source moved/reset knowledge on cancellation")
	_check_clean("mint source lookup")


## 以太进行中的内容身份阻止重复响应；获得取消保留额度，成功After结束才消耗限定次数。
func _test_yitai_reservation(cancel_move: bool) -> void:
	_reset_controller()
	# 正式技能实例；限定次数由技能公共接口维护。
	var skill: SkillDefinition = GameDatabase.create_skill("yitai")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"yitai":skill}
	skill.install()
	_controller.trigger_manager.subscribe("gainBegin" if cancel_move else "gainAfter", self, _pause_window)
	# 第一条正式确认响应；控制项与界面提交使用相同格式。
	var response: ChoiceResponse = ChoiceResponse.new(1, -1, 0, true)
	response.control_id = MatchController.YINLANG_MINT_CONTROL_PREFIX + "额度造牌|heart|8|sha"
	skill.continue_selection({"kind":"yitai_mint"}, response)
	_check(_controller.has_pending_card_choice() and skill.has_available_intrinsic_use(), "yitai quota committed before complete gain")
	# 重放另一名字也不能重复生成；本轮请求仍由原规则内容持有。
	var replay: ChoiceResponse = ChoiceResponse.new(2, -1, 0, true)
	replay.control_id = MatchController.YINLANG_MINT_CONTROL_PREFIX + "重放造牌|club|9|shan"
	skill.continue_selection({"kind":"yitai_mint"}, replay)
	if cancel_move:
		_paused_event.cancel("test_yitai_cancel")
	_submit_choice()
	await _settle_single()
	_check(skill.has_available_intrinsic_use() == cancel_move and _controller.state.get_player(0).hand.size() == (0 if cancel_move else 1) and _controller.is_card_name_available("重放造牌"), "yitai duplicated creation or consumed cancelled quota")
	_check_clean("yitai pending quota")
