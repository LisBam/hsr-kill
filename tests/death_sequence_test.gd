extends "res://tests/damage_sequence_test.gd"

## 死亡可中断性与同目标嵌套伤害回归，所有等待均使用正式请求。

## 验证死亡时机、异步取消、嵌套伤害和回合交接。
func _run() -> void:
	for timing: String in ["dieBefore", "dieBegin", "die", "dieEnd", "dieAfter"]:
		_reset_controller()
		_controller.state.get_player(2).hp = 0
		# 记录窗口次序；待答期间后一个窗口不得出现。
		var order: Array[String] = []
		for name: String in ["dieBefore", "dieBegin", "die", "dieEnd", "dieAfter"]:
			_controller.event_bus.subscribe(name, self, func(event: RuleEvent) -> void: order.append(event.name))
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller._resolve_death(2, 1)
		_check(_controller.has_pending_card_choice() and order.back() == timing, timing + " crossed pending choice: " + str(order))
		_submit_choice()
		_check(order == ["dieBefore", "dieBegin", "die", "dieEnd", "dieAfter"], timing + " wrong death order: " + str(order))
		_check(not _controller.state.get_player(2).alive, "death not committed")
		_check_clean(timing)
	for timing: String in ["dieBefore", "dieBegin"]:
		_reset_controller()
		_controller.state.get_player(2).hp = 0
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller._resolve_death(2, 0)
		_paused_event.cancel("test_save")
		_controller.state.get_player(2).hp = 1
		_submit_choice()
		_check(_controller.state.get_player(2).alive and _controller.state.get_player(0).total_kill_count == 0, timing + " ignored asynchronous cancellation")
		_check_clean(timing + " cancelled")
	_test_nested_damage()
	_controller.free()
	if not _failed:
		print("DEATH_SEQUENCE_PASS windows cancellation nested_damage")
	get_tree().quit(1 if _failed else 0)


## 获救通知中再受同目标伤害时，两次伤害都必须各自收尾且子伤害在前。
func _test_nested_damage() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 1
	# 第一次濒死直接救起，保持正式注册及获救窗口路径。
	_controller.trigger_manager.subscribe("dying", self, func(event: RuleEvent) -> void: _controller.state.get_player(event.target_id).hp = 1)
	# 只插入一次嵌套伤害，避免测试构造无穷递归。
	var nested: Array[bool] = [false]
	var amounts: Array[int] = []
	_controller.trigger_manager.subscribe("dyingAfter", self, func(_event: RuleEvent) -> void:
		if not nested[0]:
			nested[0] = true
			_controller.damage(0, 2, 2))
	_controller.event_bus.subscribe("damageAfter", self, func(event: RuleEvent) -> void: amounts.append(int(event.data.amount)))
	_controller.trigger_manager.subscribe("damagePointAfter", self, _pause_window)
	_controller.damage(0, 2, 1)
	# 有限真实应答；三点通知分别完成，不能靠看门狗或清空队列。
	for index: int in range(3):
		if _controller.has_pending_card_choice():
			_submit_choice()
	_check(amounts == [2, 1], "nested damage lost/reordered tail: " + str(amounts))
	_check_clean("same target nested damage")


