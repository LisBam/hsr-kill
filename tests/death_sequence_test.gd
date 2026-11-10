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
	_test_reward_discard_wait()
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




## 领袖杀忠臣的罚弃逐张等待，死亡End不能越过罚弃After中的选择。
func _test_reward_discard_wait() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 0
	# 首份罚弃实体；真实手牌数组在正式提交前保留。
	var first: CardInstance = CardInstance.new("sha", "club", 2)
	first.zone = "hand"
	first.owner_id = 0
	_controller.state.get_player(0).hand.append(first)
	# 第二份罚弃；首张After尚未结束时必须仍在手牌区。
	var second: CardInstance = CardInstance.new("shan", "diamond", 3)
	second.zone = "hand"
	second.owner_id = 0
	_controller.state.get_player(0).hand.append(second)
	# 已完成死亡End次数；暂停时应为空。
	var ended: Array[int] = []
	_controller.event_bus.subscribe("dieEnd", self, func(event: RuleEvent) -> void: ended.append(event.target_id))
	_controller.trigger_manager.subscribe("cardsDiscardAfter", self, func(event: RuleEvent) -> void:
		if (event.data.get("card_uids", []) as Array).has(first.uid):
			_pause_window(event)
	)
	_controller._resolve_death(2, 0)
	_check(_controller.has_pending_card_choice() and ended.is_empty() and _controller.state.get_player(0).hand.has(second), "death reward discarded/finished early")
	_submit_choice()
	_check(ended == [2] and _controller.state.get_player(0).hand.is_empty() and _controller.state.discard_pile.has(first) and _controller.state.discard_pile.has(second), "death reward lost/repeated completion")
	_check_clean("death reward batch")
