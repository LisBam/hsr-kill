extends "res://tests/card_single_sequence_test.gd"

## 角色状态变化的每个前后窗口独立等待；取消、修改、换将、嵌套与结果不能越过提交边界。


func _run() -> void:
	# 各类状态的真实窗口；兼容名称也必须完整等待。
	var windows: Dictionary = {"lose_hp":["loseHpBefore", "lose_hp_before", "loseHpBegin", "lose_hp_after", "changeHp", "loseHpEnd", "loseHpAfter", "hp_reduced"], "shield":["changeHujiaBefore", "shield_after", "changeHujiaAfter"], "shield_loss":["changeHujiaBefore", "changeHujiaAfter"], "max_hp":["gainMaxHpBefore", "gainMaxHpBegin", "gainMaxHpEnd", "gainMaxHpAfter"], "max_hp_loss":["loseMaxHpBefore", "loseMaxHpBegin", "loseMaxHpEnd", "loseMaxHpAfter", "changeHp"], "link":["linkBefore", "linkBegin", "linkEnd", "linkAfter"], "turn_over":["turnOverBefore", "turnOverEnd", "turnOverAfter"]}
	for kind: String in windows:
		for timing_name: String in windows[kind]:
			await _test_state_window(kind, timing_name, false)
		await _test_state_window(kind, str(windows[kind][0]), true)
	await _test_final_modification()
	await _test_state_generation()
	await _test_nested_hp_loss()
	await _test_after_child_recovery()
	await _test_cardless_hp_cost(false)
	await _test_cardless_hp_cost(true)
	if _controller != null:
		_controller.free()
	if not _failed:
		print("PLAYER_STATE_SEQUENCE_PASS windows cancellation final_data generation nested response_cost")
	get_tree().quit(1 if _failed else 0)


## 各请求均使用公开状态API；同步函数只提交结果，不读取尚未完成的数量。
func _request_state(kind: String) -> RefCounted:
	match kind:
		"lose_hp":
			return _controller.lose_hp(0, 1, 2, "state_test")
		"shield":
			return _controller.shield(1, 2, 0, "state_test")
		"shield_loss":
			return _controller.change_hujia(1, -2, 0, "state_test")
		"max_hp":
			return _controller.change_max_hp(1, 2, 0, "state_test")
		"max_hp_loss":
			return _controller.change_max_hp(1, -2, 0, "state_test")
		"link":
			return _controller.set_player_linked(1, true, 0, "state_test")
	return _controller.turn_over_player(1, 0, "state_test")


## 唯一状态观察值；各类请求都产生与初值不同的可比较结果。
func _state_value(kind: String) -> int:
	# 当前固定目标；测试只读取，不越过公开API写入实际效果。
	var target: PlayerState = _controller.state.get_player(1)
	if kind == "lose_hp":
		return target.hp
	if kind in ["shield", "shield_loss"]:
		return target.shield
	if kind in ["max_hp", "max_hp_loss"]:
		return target.max_hp
	return int(target.chained) if kind == "link" else int(target.face_down)


## 每个窗口都暂停；前置状态尚未提交，后置已提交但结果仍未完整完成。
func _test_state_window(kind: String, timing_name: String, cancel_change: bool) -> void:
	_reset_controller()
	_controller.state.get_player(1).shield = 3
	# 原状态标量；用实际状态判断提交位置，不能用回调次数代替。
	var original: int = _state_value(kind)
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 完整独立结果；真实前置和后置等待期间都应pending。
	var resolution: RefCounted = _request_state(kind)
	_check(_controller.has_pending_card_choice() and not resolution.completed, "state did not await " + kind + timing_name)
	_check((_state_value(kind) == original) == (timing_name.ends_with("Before") or timing_name.ends_with("Begin") or timing_name == "lose_hp_before"), "state crossed commit " + kind + timing_name)
	if cancel_change:
		_paused_event.cancel("test_cancel_state_change")
	_submit_choice()
	await _settle_single()
	_check(resolution.completed and resolution.success != cancel_change and (_state_value(kind) == original) == cancel_change, "state final result " + kind + timing_name)
	_check(resolution.count == (0 if cancel_change else (1 if kind in ["link", "turn_over"] else 2)), "state count " + kind + timing_name)
	_check_clean("state " + kind + timing_name)


## 前置完整结束后的amount与朝向是唯一提交依据；不得检查修改值后继续写入旧请求。
func _test_final_modification() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("changeHujiaBefore", self, _pause_window)
	# 护甲结果；修改必须在恢复时被读取。
	var resolution: RefCounted = _controller.shield(1, 2, 0)
	_paused_event.data["amount"] = 7
	_submit_choice()
	await _settle_single()
	_check(resolution.completed and resolution.amount == 7 and _controller.state.get_player(1).shield == 7, "state lost final amount modification")
	_reset_controller()
	_controller.trigger_manager.subscribe("turnOverBefore", self, _pause_window)
	resolution = _controller.turn_over_player(1, 0)
	_paused_event.data["face_down"] = false
	_submit_choice()
	await _settle_single()
	_check(resolution.completed and not resolution.success and not _controller.state.get_player(1).face_down, "turn over ignored final intended direction")
	_check_clean("state final data")


## 修改窗口中换将使原请求明确失败；不得修改新角色标量。
func _test_state_generation() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("loseHpBegin", self, _pause_window)
	# 原武将的独立请求；替换代次后不得继续扣减。
	var resolution: RefCounted = _controller.lose_hp(0, 1, 2)
	_controller.state.get_player(1).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(resolution.completed and not resolution.success and _controller.state.get_player(1).hp == 20, "state modified replacement character")
	_check_clean("state generation")


## 同目标嵌套失去体力保留各自来源与数量；父请求等子前置结束后才提交。
func _test_nested_hp_loss() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("loseHpBefore", self, func(event: RuleEvent) -> void:
		if event.source_id == 0:
			_controller.lose_hp(2, 1, 3, "nested_state")
	)
	_controller.trigger_manager.subscribe("loseHpBegin", self, func(event: RuleEvent) -> void:
		if event.source_id == 2:
			_pause_window(event)
	)
	# 父请求；暂停时父、子均尚未提交。
	var resolution: RefCounted = _controller.lose_hp(0, 1, 2, "outer_state")
	_check(not resolution.completed and _controller.state.get_player(1).hp == 20, "outer state skipped nested before")
	_submit_choice()
	await _settle_single()
	_check(resolution.completed and resolution.amount == 2 and _controller.state.get_player(1).hp == 15 and _controller.state.get_player(1).damage_history.is_empty(), "nested state mixed amount or damage history")
	_check_clean("nested hp loss")


## 失去体力After中的子回复先完成，再判断濒死，不能提前打开求桃或判死。
func _test_after_child_recovery() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 1
	_controller.trigger_manager.subscribe("loseHpAfter", self, func(_event: RuleEvent) -> void: _controller.recover(1, 1, 1))
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	# 致濒死的父请求；其After尚有救回自己的子回复。
	var resolution: RefCounted = _controller.lose_hp(0, 1, 1)
	_check(not resolution.completed and _controller.state.get_player(1).hp == 0 and not _controller.state.get_player(1).dying, "hp loss entered dying before After child")
	_submit_choice()
	await _settle_single()
	_check(resolution.completed and _controller.state.get_player(1).hp == 1 and not _controller.state.get_player(1).dying, "hp loss did not wait child recovery")
	_check_clean("state child recovery")


## 倾力费用归响应父内容等待；前置取消不提供成功响应，也不消费体力。
func _test_cardless_hp_cost(cancel_cost: bool) -> void:
	_reset_controller()
	# 正式无材料转化技能；费用通过技能标准钩子发起。
	var skill: SkillDefinition = GameDatabase.create_skill("qingli")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"qingli":skill}
	_controller.trigger_manager.subscribe("loseHpBegin", self, _pause_window)
	# 正式响应结果；原响应选择已结束，不借用原请求槽支付费用。
	var response: RefCounted = _controller.begin_response_resolution(0, -1, ["sha"], [], "", {"selected_cardless_response_skill_id":"qingli", "selected_cardless_response_definition_id":"sha_thunder", "response_action":"play"})
	_check(not response.completed and _controller.has_pending_card_choice() and _controller.state.get_player(0).hp == 20, "cardless response skipped hp cost")
	if cancel_cost:
		_paused_event.cancel("test_cardless_cost_cancel")
	_submit_choice()
	await _settle_single()
	_check(response.completed and (response.result == null) == cancel_cost and _controller.state.get_player(0).hp == (20 if cancel_cost else 19) and _controller.state.get_player(0).response_history.size() == (0 if cancel_cost else 1), "cardless response paid cancelled/duplicate hp cost")
	_check_clean("cardless hp cost")
