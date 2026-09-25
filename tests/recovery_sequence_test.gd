extends "res://tests/card_timing_sequence_test.gd"

## 回复及桃的异步契约回归；真实选择覆盖修改、取消、嵌套求桃和牌后续。

## 各例独立创建状态，并检查结算队列彻底释放。
func _run() -> void:
	_test_recovery_windows()
	_test_recovery_cancellation()
	_test_recovery_generation()
	_test_peach_rescue()
	await _test_peach_use(false)
	await _test_peach_use(true)
	_controller.free()
	if not _failed:
		print("RECOVERY_SEQUENCE_PASS windows cancellation generation peach_rescue peach_use")
	get_tree().quit(1 if _failed else 0)


## 六个窗口逐个暂停；前置读最终金额，结果窗口取消不撤销已提交事实。
func _test_recovery_windows() -> void:
	# 规范回复顺序；兼容recover_after也必须等待正式After完成。
	var names: Array[String] = ["recoverBefore", "recoverBegin", "changeHp", "recoverEnd", "recoverAfter", "recover_after"]
	for timing: String in names:
		_reset_controller()
		_controller.state.get_player(1).hp = 10
		# 已开始的窗口；待答期间不得越过当前项。
		var observed: Array[String] = []
		for name: String in names:
			_controller.event_bus.subscribe(name, self, func(event: RuleEvent) -> void: observed.append(event.name))
		_controller.trigger_manager.subscribe(timing, self, _pause_window, 10)
		_controller.recover(0, 1, 3, "test")
		_check(_controller.has_pending_card_choice() and observed.back() == timing, timing + " crossed choice")
		# 只有Before和Begin尚未提交；结果窗口的取消不能回滚体力。
		var before_commit: bool = names.find(timing) < 2
		_check(_controller.state.get_player(1).hp == (10 if before_commit else 13), timing + " wrong commit boundary")
		if before_commit:
			_paused_event.data["amount"] = 2
		else:
			_paused_event.cancel("result_notification")
		_submit_choice()
		_check(observed == names, timing + " notification order: " + str(observed))
		_check(_controller.state.get_player(1).hp == (12 if before_commit else 13), timing + " lost final amount")
		_check(_controller.state.get_player(0).total_healing_done == (2 if before_commit else 3), timing + " repeated healing statistics")
		_check_clean(timing)


## 异步取消前置不产生体力和统计；超上限请求只统计实际回复量。
func _test_recovery_cancellation() -> void:
	for timing: String in ["recoverBefore", "recoverBegin"]:
		_reset_controller()
		_controller.state.get_player(1).hp = 10
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller.recover(0, 1, 3)
		_paused_event.cancel("test_cancel")
		_submit_choice()
		_check(_controller.state.get_player(1).hp == 10 and _controller.state.get_player(0).total_healing_done == 0, timing + " ignored cancellation")
		_check_clean(timing + " cancel")
	_reset_controller()
	_controller.state.get_player(1).hp = 19
	_controller.recover(0, 1, 3)
	_check(_controller.state.get_player(1).hp == 20 and _controller.state.get_player(0).total_healing_done == 1, "healing clamp statistics")
	_check_clean("recover clamp")


## 等待期间换将后，旧回复请求不能作用于新武将。
func _test_recovery_generation() -> void:
	_reset_controller()
	_controller.state.get_player(1).hp = 10
	_controller.trigger_manager.subscribe("recoverBegin", self, _pause_window)
	_controller.recover(0, 1, 3)
	_controller.state.get_player(1).character_generation += 1
	_submit_choice()
	_check(_controller.state.get_player(1).hp == 10, "recovery reached replacement")
	_check_clean("recovery generation")


## 正式求桃消费后先等待taoBegin，再等待回复和濒死After；父伤害始终最后完成。
func _test_peach_rescue() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 1
	# 唯一救援材料；应只进入弃牌堆一次。
	var peach: CardInstance = CardInstance.new("tao", "heart", 3)
	_controller.state.get_player(0).hand.append(peach)
	# 整条救援链的通知记录；各窗口都会创建独立请求。
	var observed: Array[String] = []
	for timing: String in ["taoBegin", "recoverBefore", "recoverBegin", "recoverAfter", "dyingAfter"]:
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller.event_bus.subscribe(timing, self, func(event: RuleEvent) -> void: observed.append(event.name))
	_controller.event_bus.subscribe("damageAfter", self, func(event: RuleEvent) -> void: observed.append(event.name))
	_controller.damage(0, 2, 1)
	# 通过当前权威请求提交救援，保留真实的材料消费和响应规则。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":_controller._pending_card_choice.get("request_id", -1), "selected_card_uids":[peach.uid], "selected_target_ids":[], "confirmed":true}
	_check(_controller._submit_card_choice(action), "peach rescue rejected")
	_check(_paused_event != null and _paused_event.name == "taoBegin" and _controller.state.get_player(2).hp == 0, "peach crossed taoBegin")
	for index: int in range(5):
		if _controller.has_pending_card_choice():
			_submit_choice()
	_check(observed == ["taoBegin", "recoverBefore", "recoverBegin", "recoverAfter", "dyingAfter", "damageAfter"], "peach rescue order: " + str(observed))
	_check(_controller.state.get_player(2).hp == 1 and _controller.state.discard_pile.count(peach) == 1, "peach rescue repeated material or healing")
	_check_clean("peach rescue")


## 普通用桃与求桃共用前置契约；异步取消仍应正常清理处理区与父牌。
func _test_peach_use(cancelled: bool) -> void:
	_reset_controller()
	_controller.state.get_player(0).hp = 10
	_controller.trigger_manager.subscribe("taoBegin", self, _pause_window)
	# 正式使用的实体桃；手牌区域信息与玩家持有列表一致。
	var card: CardInstance = CardInstance.new("tao", "heart", 6)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [0])
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(0).hp == 10, "peach use applied before choice")
	if cancelled and _paused_event != null:
		_paused_event.cancel("test_peach")
	_submit_choice()
	await _settle_card()
	_check(_controller.state.get_player(0).hp == (10 if cancelled else 11), "peach use lost final cancellation")
	_check(_controller.state.processing_area.is_empty() and _controller.state.discard_pile.has(card), "peach use left processing card")
	_check_clean("peach use")
