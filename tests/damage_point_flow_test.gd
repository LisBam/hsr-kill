extends "res://tests/damage_sequence_test.gd"

## 逐点修改与统一伤害尾部的行为回归；通过真实选择及帧预算制造异步边界。


## 验证逐点取消、最终事实、尾部先后关系与连环子内容，全部使用统一调度器恢复。
func _run() -> void:
	_test_point_cancellation()
	_test_point_result_waits()
	await _test_tail_dispatch_budget()
	await _test_chain_budget()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("DAMAGE_POINT_FLOW_PASS cancellation result tail_budget chain_budget")
	get_tree().quit(1 if _failed else 0)


## 暂停后取消第一个候选点，只留下第二点；护盾吸收仍计一次伤害且不丢失逐点After。
func _test_point_cancellation() -> void:
	_reset_controller()
	_controller.state.get_player(1).shield = 1
	# 各窗口顺序；包含候选索引与最终事实索引，取消点不得进入Begin或结果通知。
	var order: Array[String] = []
	_controller.trigger_manager.subscribe("damagePointBefore", self, _pause_window, 10)
	# 标准点窗口名；同一记录器验证输入候选与最终成立点的边界。
	for timing: String in ["damagePointBefore", "damagePointBegin", "damagePoint", "damagePointAfter"]:
		_controller.event_bus.subscribe(timing, self, func(event: RuleEvent) -> void: order.append("%s:%d" % [event.name, int(event.data.damage_point_index)]))
	_controller.damage(0, 1, 2)
	_check(_controller.state.get_player(1).hp == 20 and _controller.state.get_player(1).shield == 1, "point committed before response")
	_paused_event.cancel("prevent_one_point")
	_submit_choice()
	_check(_controller.has_pending_card_choice() and int(_paused_event.data.damage_point_index) == 2, "point cancellation swallowed remaining point")
	_submit_choice()
	_check(order == ["damagePointBefore:1", "damagePointBefore:2", "damagePointBegin:2", "damagePoint:1", "damagePointAfter:1"], "point order: " + str(order))
	_check(_controller.state.get_player(1).hp == 20 and _controller.state.get_player(1).shield == 0, "point cancellation or shield mismatch")
	_check(_controller.state.get_player(1).damage_taken_count == 1 and _controller.state.get_player(1).total_damage_received == 1, "point split damage statistics")
	_check_clean("point cancellation")
	_reset_controller()
	_controller.trigger_manager.subscribe("damagePointBegin", self, func(event: RuleEvent) -> void: event.data["amount"] = 0)
	_controller.damage(0, 1, 2)
	_check(_controller.state.get_player(1).hp == 20 and _controller.state.get_player(1).damage_taken_count == 0, "all prevented points counted as damage")
	_check_clean("zero accepted points")


## 每个提交后窗口都可暂停；后一个伤害点和尾部不能越过当前点的子选择。
func _test_point_result_waits() -> void:
	# 可暂停事实窗口；包括整次尾部与单点尾部，已扣血只能保持一次。
	for timing: String in ["damagePoint", "damageSource", "damageEnd", "damageAfter", "damagePointAfter"]:
		_reset_controller()
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller.damage(0, 1, 2)
		_check(_controller.has_pending_card_choice(), timing + " failed to pause")
		_check(_controller.state.get_player(1).hp == 18 and _controller.state.get_player(1).damage_taken_count == 1, timing + " repeated commit")
		_submit_choice()
		if timing in ["damagePoint", "damagePointAfter"]:
			_check(_controller.has_pending_card_choice() and int(_paused_event.data.damage_point_index) == 2, timing + " lost next point")
			_submit_choice()
		_check_clean(timing)


## 触发器仅因批次预算暂停时也必须等待；不能依赖存在真人选择才保留尾部。
func _test_tail_dispatch_budget() -> void:
	_reset_controller()
	# 处理顺序；65个来源处理器超过默认64批次，End必须观察全部来源处理器已经完成。
	var order: Array[String] = []
	# 来源处理器序号；测试只关心总数和End位置。
	for handler_index: int in range(65):
		_controller.trigger_manager.subscribe("damageSource", self, func(_event: RuleEvent) -> void: order.append("source"))
	_controller.event_bus.subscribe("damageEnd", self, func(_event: RuleEvent) -> void: order.append("end"))
	_controller.damage(0, 1, 1)
	# 帧等待上限；正常两批即可完成，额外空间容纳组件唤醒顺序。
	for frame_index: int in range(20):
		if _controller._rule_sequences.is_empty():
			break
		await get_tree().process_frame
	_check(order.size() == 66 and order.back() == "end", "tail crossed deferred source handlers: " + str(order.size()))
	_check_clean("tail dispatch budget")


## 子伤害跨帧时，主伤害续接只消费一个连环目标；不会重复传导或泄漏保险续接。
func _test_chain_budget() -> void:
	_reset_controller()
	_controller.max_settlement_steps_per_pass = 3
	_controller.state.get_player(1).chained = true
	_controller.state.get_player(2).chained = true
	_controller.damage(0, 1, 2, "fire")
	# 有界帧等待；低预算下两条完整伤害会占用多个真实帧。
	for frame_index: int in range(100):
		if _controller._rule_sequences.is_empty():
			break
		await get_tree().process_frame
	_check(_controller.state.get_player(1).hp == 18 and _controller.state.get_player(2).hp == 18, "chain lost or repeated damage")
	_check(_controller.state.get_player(2).damage_taken_count == 1, "chain split damage facts")
	_check_clean("chain budget")
