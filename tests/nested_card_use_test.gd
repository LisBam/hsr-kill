extends "res://tests/damage_sequence_test.gd"

## 原生用牌子树等待；父时机剩余处理器和技能下一步都必须等待子牌完整结束。


## 覆盖材料、使用主体、使用After、响应After、步骤内容、取消和跨帧执行预算。
func _run() -> void:
	# 被测窗口；分别验证材料、使用主体和使用收尾的子牌等待。
	for timing_name: String in ["loseAfter", "useCard", "useCardAfter"]:
		await _test_timing_child(timing_name, false)
	await _test_timing_child("useCard", true)
	await _test_step_child(false)
	await _test_step_child(true)
	await _test_response_child()
	await _test_resumed_handler_child()
	await _test_sequential_cards()
	await _test_terminal_window_child()
	_test_pause_scope()
	_controller.free()
	if not _failed:
		print("NESTED_CARD_USE_PASS materials timing after response steps cancellation budget")
	get_tree().quit(1 if _failed else 0)


## 外层酒的材料与时机必须保留，内层桃结束后才执行同一窗口剩余处理器。
func _test_timing_child(timing_name: String, cancel_inner: bool) -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	# 外层费用；始终使用正式材料入口，不手工移动实体。
	var material: CardInstance = _add_material()
	# 父时机下一处理器观察到的内层回复结果。
	var observed: Array[int] = []
	# 实际原生父ID和新牌父ID；必须相同，不能只验证最终数值。
	var parent_ids: Array[int] = []
	_controller.trigger_manager.subscribe(timing_name, self, func(event: RuleEvent) -> void:
		if _is_outer(event, material.uid):
			parent_ids.append(_controller.event_scheduler.get_current_event_id())
			_controller.execute_cardless_virtual_card_use(1, "tao", [1], "", {"ignore_phase_limit":true})
	, 10)
	_controller.trigger_manager.subscribe(timing_name, self, func(event: RuleEvent) -> void:
		if _is_outer(event, material.uid):
			observed.append(_controller.state.get_player(1).hp)
	)
	_controller.trigger_manager.subscribe("useCardBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "tao":
			# 此刻原生栈顶是子牌；从其parent_id核对真实归属。
			var child: GameEvent = _controller.event_scheduler.get_current_event()
			parent_ids.append(child.parent_id)
			_pause_window(event)
	)
	_controller.execute_virtual_card_use(0, "jiu", [material.uid], [], "", {"ignore_phase_limit":true})
	await _wait_for_choice()
	_check(observed.is_empty(), timing_name + " parent handler ran before child")
	_check(parent_ids.size() == 2 and parent_ids[0] == parent_ids[1], timing_name + " child attached to root " + str(parent_ids))
	_check(_controller._card_use_contexts.size() == 2, timing_name + " outer use finalized before child")
	if cancel_inner and _paused_event != null:
		_check(not _paused_event.is_terminal(), "inner Before already finished before answer " + str(_paused_event.to_dict()))
		_paused_event.cancel("test_cancel_inner")
	_submit_choice()
	await _settle_nested()
	_check(observed == [19 if cancel_inner else 20], timing_name + " parent lost final child result " + str(observed))
	_check(_controller.state.get_player(0).wine_bonus == 1 and material.zone == "discard_pile", timing_name + " outer effect or fee repeated")
	_check_clean(timing_name + " native child")


## 区分父牌时机与子桃，避免测试用例自行递归生成无限用牌。
func _is_outer(event: RuleEvent, material_uid: int) -> bool:
	return str(event.data.get("card_id", "")) == "jiu" or (event.name == "loseAfter" and (event.data.get("card_uids", []) as Array).has(material_uid))


## 步骤中的原生用牌可跨选择或执行预算；下一步不能在子牌主体前读取体力。
func _test_step_child(low_budget: bool) -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	if low_budget:
		_controller.max_settlement_steps_per_pass = 2
	# 父步骤最终结果；尚未完成子牌时应为空。
	var observed: Array[int] = []
	_controller.trigger_manager.subscribe("useCardBefore", self, _pause_window)
	_controller.run_rule_sequence([
		func(_sequence: RuleStepSequence) -> void: _controller.execute_cardless_virtual_card_use(1, "tao", [1], "", {"ignore_phase_limit":true}),
		func(_sequence: RuleStepSequence) -> void: observed.append(_controller.state.get_player(1).hp),
	])
	await _wait_for_choice()
	_check(observed.is_empty(), "step skipped native child")
	_submit_choice()
	await _settle_nested()
	_check(observed == [20], "step read unfinished use " + str(observed))
	_check_clean("step native child")


## 响应After插入用牌时，响应结果只能在子牌完整回收后交付。
func _test_response_child() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	# 普通响应材料；不依赖技能专用接收分支。
	var material: CardInstance = _add_material("shan")
	_controller.trigger_manager.subscribe("respondAfter", self, func(_event: RuleEvent) -> void:
		_controller.execute_cardless_virtual_card_use(1, "tao", [1], "", {"ignore_phase_limit":true})
	)
	_controller.trigger_manager.subscribe("useCardBefore", self, _pause_window)
	# 完整响应结果；内层选择结束前不允许完成。
	var response: RefCounted = _controller.begin_response_resolution(0, material.uid, ["shan"], [], "", {"response_action":"play"})
	await _wait_for_choice()
	_check(not response.completed, "response After returned before native child")
	_submit_choice()
	await _settle_nested()
	_check(response.completed and response.result == material and _controller.state.get_player(1).hp == 20, "response lost native child result")
	_check_clean("response native child")


## 添加普通手牌材料；实体与费用状态始终由生产服务改变。
func _add_material(definition_id: String = "sha") -> CardInstance:
	# 当前实体；所有测试只用一个UID，不构造候选副本替代费用。
	var card: CardInstance = CardInstance.new(definition_id, "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	return card


## 只等待真实管线；不能清空暂停、重建根事件或强行结束父牌。
func _wait_for_choice() -> void:
	# 有限观察帧；只驱动正式出口，不替测试释放暂停或清空规则队列。
	for attempt: int in range(120):
		_controller.resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller.has_pending_card_choice():
			return
		await get_tree().process_frame
	_check(false, "nested child did not reach choice")


## 所有本轮内容和原生父牌排空才完成；上限只是测试失败边界。
func _settle_nested() -> void:
	# 有限排空观察帧；超出范围即失败，不能通过强制结束父事件掩盖等待问题。
	for attempt: int in range(160):
		_controller.resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller._card_use_contexts.is_empty() and _controller._rule_sequences.is_empty() and not _controller._rule_continuations.has_pending():
			return
		await get_tree().process_frame
	_check(false, "nested content did not settle")


## 外层选择之后才执行的处理器也要重新登记窗口归属，不能在恢复路径失去子树等待。
func _test_resumed_handler_child() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	# 外层酒费用；所有窗口仍通过真实CardUseEvent。
	var material: CardInstance = _add_material()
	# 最后处理器的观察结果；两次应答前都应为空。
	var observed: Array[int] = []
	_controller.trigger_manager.subscribe("useCard", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "jiu":
			_pause_window(event)
	, 20)
	_controller.trigger_manager.subscribe("useCard", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "jiu":
			_controller.execute_cardless_virtual_card_use(1, "tao", [1], "", {"ignore_phase_limit":true})
	, 10)
	_controller.trigger_manager.subscribe("useCard", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "jiu":
			observed.append(_controller.state.get_player(1).hp)
	)
	_controller.trigger_manager.subscribe("useCardBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "tao":
			_pause_window(event)
	)
	_controller.execute_virtual_card_use(0, "jiu", [material.uid], [], "", {"ignore_phase_limit":true})
	await _wait_for_choice()
	_submit_choice()
	await _wait_for_choice()
	_check(observed.is_empty() and str(_paused_event.data.get("card_id", "")) == "tao", "resumed handler lost native child ownership")
	_submit_choice()
	await _settle_nested()
	_check(observed == [20], "resumed handler read early result")
	_check_clean("resumed handler")


## 内容级暂停仅阻止父主体；全局暂停和普通选择的子树阻塞不能被子事件绕过。
func _test_pause_scope() -> void:
	_reset_controller()
	# 子内容观察结果；只有全局令牌释放后才允许执行。
	var observed: Array[int] = []
	# 父内容持有的内部令牌；测试结束由其所有者明确释放。
	var holds: Array[int] = []
	# 父原生内容；先建立内部等待，再声明有限子事件。
	var steps: Array[Callable] = [func(event: GameEvent, scheduler: EventScheduler) -> void:
		holds.append(scheduler.pause_registry.acquire("rule_content", event.event_id, "test_content", false))
		scheduler.create_child(event.event_id, "test_child", "rule", [func(_event: GameEvent, _scheduler: EventScheduler) -> void: observed.append(1)])
	]
	_controller.event_scheduler.create_child(_controller.event_scheduler.root_event_id, "test_parent", "rule", steps)
	# 全局阻塞；不得被内容级子事件放行。
	var global_hold: int = _controller.event_scheduler.pause_registry.acquire("gameplay", -1, "test_global")
	_controller.event_scheduler.drain()
	_check(observed.is_empty(), "native child bypassed global pause")
	_controller.event_scheduler.resume(global_hold, "test_resume_global")
	_check(observed == [1] and holds.size() == 1 and _controller.event_scheduler.pause_registry.has_active(), "content hold blocked child or released too soon")
	if not holds.is_empty():
		_controller.event_scheduler.resume(holds[0], "test_content_done")
	_check(not _controller.event_scheduler.pause_registry.has_active(), "content pause leaked")
	_check_clean("pause scope")


## 连续虚拟牌在第一张After及回收结束后才开始第二张，整组完成前拒绝重入。
func _test_sequential_cards() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	# 连续用牌组件；直接测试公共基类，避免轮回技能自身时机掩盖组件等待边界。
	var skill: SequentialVirtualSkillDefinition = SequentialVirtualSkillDefinition.new({"id":"test_sequential"})
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"test_sequential":skill}
	# 第一张牌的原生身份；第二张Before必须看到其完整归档。
	var first_ids: Array[int] = []
	# 第二张启动时的第一张归档状态；不能只验证最终回复量。
	var first_finalized: Array[bool] = []
	_controller.trigger_manager.subscribe("useCardAfter", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "jiu":
			first_ids.append(int((_controller._card_use_contexts.get(int(event.data.card_uid), {}) as Dictionary).get("event_id", -1)))
			_pause_window(event)
	)
	_controller.trigger_manager.subscribe("useCardBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("card_id", "")) == "tao":
			first_finalized.append(first_ids.size() == 1 and not _controller.event_scheduler.is_event_pending(first_ids[0]))
	)
	# 两次独立牌使用；技能完成由最后一步决定，不依靠useCardAfter手工续接。
	var entries: Array[Dictionary] = [
		{"actor_id":0, "definition_id":"jiu", "target_ids":[], "rule_overrides":{"ignore_phase_limit":true}},
		{"actor_id":1, "definition_id":"tao", "target_ids":[1], "rule_overrides":{"ignore_phase_limit":true}},
	]
	_check(skill.start_cardless_virtual_card_sequence(entries), "sequential start rejected")
	await _wait_for_choice()
	_check(first_finalized.is_empty() and skill._virtual_card_sequence_waiting, "sequential card skipped first After")
	_check(not skill.start_cardless_virtual_card_sequence(entries), "sequential accepted duplicate activation")
	_submit_choice()
	await _settle_nested()
	_check(first_finalized == [true] and not skill._virtual_card_sequence_waiting and _controller.state.get_player(1).hp == 20, "sequential card started before full after or lost completion")
	_check_clean("sequential native cards")


## 恢复处理器终止自身窗口后创建的子牌仍须完成；终止只跳过余下处理器，不提前运行父内容下一步。
func _test_terminal_window_child() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	# 父步骤的最终观察；第二次选择之前必须为空。
	var observed: Array[int] = []
	_controller.trigger_manager.subscribe("test_terminal_window", self, _pause_window, 20)
	_controller.trigger_manager.subscribe("test_terminal_window", self, func(event: RuleEvent) -> void:
		event.cancel("test_terminal_parent")
		_controller.execute_cardless_virtual_card_use(1, "tao", [1], "", {"ignore_phase_limit":true})
	, 10)
	_controller.trigger_manager.subscribe("useCardBefore", self, _pause_window)
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: sequence.wait_for_timing(_controller.emit_rule_timing("test_terminal_window", 0, 0, 1)),
		func(_sequence: RuleStepSequence) -> void: observed.append(_controller.state.get_player(1).hp),
	])
	_submit_choice()
	await _wait_for_choice()
	_check(observed.is_empty(), "terminal window skipped pending child")
	_submit_choice()
	await _settle_nested()
	_check(observed == [20], "terminal window lost child completion")
	_check_clean("terminal native child")
