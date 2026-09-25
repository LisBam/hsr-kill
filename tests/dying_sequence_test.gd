extends "res://tests/damage_sequence_test.gd"

## 濒死窗口回归；使用正式选择制造暂停，验证原事件回写及救援完成顺序。


## 每个用例隔离权威状态；错误聚合后以非零退出。
func _run() -> void:
	_test_before_result()
	_test_registered_windows()
	_test_rescue_completion()
	_test_damage_rescue_tail()
	_test_replaced_target()
	_test_already_dead_target()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("DYING_SEQUENCE_PASS final_data registered_windows completion damage_tail generation")
	get_tree().quit(1 if _failed else 0)


## Before选择后修改原事件，Begin应读取最终值，回复后不再开放求桃。
func _test_before_result() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 0
	# 下一窗口实际收到的字段；空值表示提前复制了旧数据。
	var observed: Array[String] = []
	_controller.trigger_manager.subscribe("dyingBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("dyingBegin", self, func(event: RuleEvent) -> void:
		observed.append(str(event.data.get("test_marker", "")))
		_controller.state.get_player(1).hp = 1)
	_controller._resolve_dying(1, 0)
	_check(_controller.has_pending_card_choice() and observed.is_empty(), "dyingBefore failed to wait")
	_paused_event.data["test_marker"] = "after_choice"
	_submit_choice()
	_check(observed == ["after_choice"], "dyingBegin read stale Before data: " + str(observed))
	_check(not _controller.state.get_player(1).dying and _controller.state.dying_queue.is_empty(), "recovered before registration still dying")
	_check_clean("dyingBefore final data")


## 注册通知和旧兼容通知之间也要等待；已回复角色仍需完成本次濒死的After。
func _test_registered_windows() -> void:
	# 各暂停位置；回复发生在已登记濒死之后。
	for timing: String in ["dying", "dying_begin"]:
		_reset_controller()
		_controller.state.get_player(1).hp = 0
		# 实际通知顺序；后续通知不能在选择待答时发生。
		var order: Array[String] = []
		for name: String in ["dying", "dying_begin", "dyingAfter", "dying_end"]:
			_controller.event_bus.subscribe(name, self, func(event: RuleEvent) -> void: order.append(event.name))
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller._resolve_dying(1, 0)
		_check(order == (["dying"] if timing == "dying" else ["dying", "dying_begin"]), timing + " crossed next window: " + str(order))
		_controller.state.get_player(1).hp = 1
		_submit_choice()
		_check(order.count("dyingAfter") == 1 and order.count("dying_end") == 1, timing + " lost rescue completion: " + str(order))
		_check(_controller.state.dying_queue.is_empty() and not _controller.state.get_player(1).dying, timing + " leaked dying state")
		_check_clean(timing)


## After尚有选择时，旧完成通知和父伤害尾部都必须保持未执行。
func _test_rescue_completion() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 1
	_controller.state.get_player(1).dying = true
	_controller.state.dying_queue.append(1)
	# 完成通知顺序；状态先提交，通知依次等候子内容。
	var order: Array[String] = []
	for name: String in ["dyingAfter", "dying_end"]:
		_controller.event_bus.subscribe(name, self, func(event: RuleEvent) -> void: order.append(event.name))
	_controller.trigger_manager.subscribe("dyingAfter", self, _pause_window)
	_controller._finish_dying_rescue(1)
	_check(order == ["dyingAfter"], "rescue completion crossed After choice: " + str(order))
	_check(not _controller.state.get_player(1).dying, "rescue state not committed before After")
	_submit_choice()
	_check(order == ["dyingAfter", "dying_end"], "rescue completion order mismatch: " + str(order))
	_check_clean("rescue completion")


## 真实伤害的求桃应答后，dyingAfter中的选择必须先于damageAfter，重复完成调用保持幂等。
func _test_damage_rescue_tail() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 1
	# 唯一可救援实体；通过正式响应消费，不能直接设置体力替代救援。
	var peach: CardInstance = CardInstance.new("tao", "heart", 3)
	_controller.state.get_player(0).hand.append(peach)
	# 伤害尾部次数；救援通知全部结束之前必须为0。
	var after_count: Array[int] = [0]
	_controller.event_bus.subscribe("damageAfter", self, func(_event: RuleEvent) -> void: after_count[0] += 1)
	_controller.trigger_manager.subscribe("dyingAfter", self, _pause_window)
	_controller.damage(0, 2, 1)
	_check(str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "dying_response", "missing real rescue request")
	# 正式应答动作；只提交当前请求ID与已持有的桃，不直接调用回复入口。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":_controller._pending_card_choice.get("request_id", -1), "selected_card_uids":[peach.uid], "selected_target_ids":[], "confirmed":true}
	_check(_controller._submit_card_choice(action), "rescue response rejected")
	_check(_controller.has_pending_card_choice() and _paused_event != null and _paused_event.name == "dyingAfter", "rescue After failed to pause")
	_check(_controller.state.get_player(2).hp == 1 and after_count[0] == 0, "damage tail crossed rescue After")
	_controller._finish_dying_rescue(2)
	_submit_choice()
	_check(after_count[0] == 1 and _controller._rule_sequences.is_empty(), "rescue lost or repeated damage tail")
	_check_clean("damage rescue tail")


## 开始窗口等待期间换将，旧伤害可收尾，但不能向新武将继续求桃。
func _test_replaced_target() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 1
	_controller.trigger_manager.subscribe("dyingBefore", self, _pause_window)
	_controller.damage(0, 2, 1)
	_controller.state.get_player(2).character_generation += 1
	_controller.state.get_player(2).hp = 5
	_submit_choice()
	_check(_controller.state.get_player(2).hp == 5 and _controller.state.dying_queue.is_empty(), "old dying flow reached replacement")
	_check(_controller._rule_sequences.is_empty(), "replacement left original damage tail")
	_check_clean("dying generation")


## 伤害通知已使目标死亡时仍要完成伤害事实，不能依赖“没有选择就收尾”的补偿分支。
func _test_already_dead_target() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 1
	_controller.trigger_manager.subscribe("damage", self, func(_event: RuleEvent) -> void: _controller.state.get_player(2).alive = false)
	# 伤害尾部次数；死亡目标不再求桃，但原伤害事实必须正常结束一次。
	var after_count: Array[int] = [0]
	_controller.event_bus.subscribe("damageAfter", self, func(_event: RuleEvent) -> void: after_count[0] += 1)
	_controller.damage(0, 2, 1)
	_check(after_count[0] == 1 and _controller._rule_sequences.is_empty(), "dead target left damage continuation")
	_check_clean("dead target")
