extends "res://tests/damage_sequence_test.gd"

## 批量移牌专项；暂停、取消、嵌套、代次与结果只接收一次。


## 各窗口独立制造选择，确认第二张和整批结果不会越过第一张的未完成内容。
func _run() -> void:
	for timing_name: String in ["loseBefore", "loseBegin", "discardBefore", "discardBegin", "loseEnd", "loseAfter", "discardEnd", "discardAfter", "cardsDiscardAfter", "cardsDiscardedBatchAfter"]:
		await _test_discard_window(timing_name)
	await _test_cancel()
	await _test_gain_nested()
	await _test_generation()
	await _test_pile_cancel()
	await _test_receiver_death()
	_controller.free()
	if not _failed:
		print("CARD_BATCH_SEQUENCE_PASS windows cancellation nested_gain generation unique_result")
	get_tree().quit(1 if _failed else 0)


## 为区域测试建立两张普通手牌。
func _cards(player_id: int = 0) -> Array[int]:
	# 稳定费用清单；实体保留在源数组直到真正提交。
	var uids: Array[int] = []
	for number: int in [2, 3]:
		# 实体牌；红桃不引入额外装备或牌效。
		var card: CardInstance = CardInstance.new("tao", "heart", number)
		card.owner_id = player_id
		card.zone = "hand"
		_controller.state.get_player(player_id).hand.append(card)
		uids.append(card.uid)
	return uids


## 单牌所有窗口与整批After都必须先于结果接收。
func _test_discard_window(timing_name: String) -> void:
	_reset_controller()
	# 两张费用；后续不能抢先消费第二份。
	var uids: Array[int] = _cards()
	# 唯一结果接收；同步与异步均只调用一次。
	var received: Array[int] = []
	_controller.trigger_manager.subscribe(timing_name, self, func(event: RuleEvent) -> void:
		if _paused_event == null:
			_pause_window(event)
	)
	# 可等待结果；未完成不是支付失败。
	var resolution: RefCounted = _controller.begin_discard_cards(0, uids, ["hand"], 0, "test", func(value: int) -> void: received.append(value))
	_check(not resolution.completed and received.is_empty() and _controller.has_pending_card_choice(), timing_name + " result ran early")
	if timing_name != "cardsDiscardedBatchAfter":
		_check(_controller.state.get_player(0).find_hand_card(uids[1]) != null, timing_name + " consumed next fee")
	_submit_choice()
	await _settle_batch()
	_check(resolution.completed and resolution.count == 2 and received == [2], timing_name + " missing/repeated result")
	_check_clean(timing_name)


## 第二份费用前置取消不撤销第一份，实际数量必须是1，取消牌仍在手牌数组。
func _test_cancel() -> void:
	_reset_controller()
	# 两张费用；只取消后一张。
	var uids: Array[int] = _cards()
	_controller.trigger_manager.subscribe("discardBegin", self, func(event: RuleEvent) -> void:
		if int(event.data.card_uids[0]) == uids[1]:
			_pause_window(event)
	)
	# 最终支付结果；不会把请求张数误算为成功张数。
	var resolution: RefCounted = _controller.begin_discard_cards(0, uids, ["hand"], 0)
	_paused_event.cancel("test_cancel")
	_submit_choice()
	await _settle_batch()
	_check(resolution.completed and resolution.count == 1 and _controller.state.get_player(0).find_hand_card(uids[1]) != null, "cancelled fee was removed/count wrong")
	_check_clean("batch cancel")


## 获得第一张时插入独立获得批次；各批次UID隔离，外层第二张等待内层。
func _test_gain_nested() -> void:
	_reset_controller()
	# 外层来自角色1的两张手牌。
	var uids: Array[int] = _cards(1)
	# 内层来源不同，禁止串入外层的批次清单。
	var nested_uids: Array[int] = _cards(2)
	# 观察到的最终批次集合。
	var batches: Array[Array] = []
	_controller.event_bus.subscribe("cardsGainedBatchAfter", self, func(event: RuleEvent) -> void: batches.append((event.data.card_uids as Array).duplicate()))
	_controller.trigger_manager.subscribe("gainAfter", self, func(event: RuleEvent) -> void:
		if int(event.data.card_uids[0]) == uids[0]:
			_controller.begin_gain_cards(0, 2, nested_uids, ["hand"])
		elif int(event.data.card_uids[0]) == nested_uids[0]:
			_pause_window(event)
	)
	# 外层结果；内层暂停时尚不能完成。
	var resolution: RefCounted = _controller.begin_gain_cards(0, 1, uids, ["hand"])
	_check(not resolution.completed and _controller.state.get_player(1).find_hand_card(uids[1]) != null, "gain crossed nested boundary")
	_submit_choice()
	await _settle_batch()
	_check(resolution.completed and resolution.count == 2 and batches == [nested_uids, uids], "gain batch ownership mixed " + str(batches))
	_check_clean("nested gain")


## 换将使旧费用清单失效；新武将不会继续支付旧选择。
func _test_generation() -> void:
	_reset_controller()
	# 原费用实体；代次变化不能把它当作新角色选择。
	var uids: Array[int] = _cards()
	_controller.trigger_manager.subscribe("loseBefore", self, _pause_window)
	# 旧结果；完成为零而不是永久等待。
	var resolution: RefCounted = _controller.begin_discard_cards(0, uids, ["hand"], 0)
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_batch()
	_check(resolution.completed and resolution.count == 0 and _controller.state.get_player(0).hand.size() == 2, "batch generation consumed old fees")
	_check_clean("batch generation")


## 只推动正式管线；不使用清空队列或看门狗补偿。
func _settle_batch() -> void:
	for attempt: int in range(100):
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller._rule_sequences.is_empty():
			return
		await get_tree().process_frame
	_check(false, "batch did not settle")


## 公共牌堆批量获得取消一张后继续有限清单，不重复检索同一张被取消牌。
func _test_pile_cancel() -> void:
	_reset_controller()
	# 公共牌堆实体；取消时知识和原区域均须保留。
	var first: CardInstance = CardInstance.new("sha", "club", 4)
	first.zone = "draw_pile"
	first.known_to = [1]
	_controller.state.draw_pile.append(first)
	# 第二个合法实体；只它实际进入获得批次。
	var second: CardInstance = CardInstance.new("shan", "heart", 5)
	second.zone = "draw_pile"
	_controller.state.draw_pile.append(second)
	_controller.trigger_manager.subscribe("gainBefore", self, func(event: RuleEvent) -> void:
		if (event.data.card_uids as Array).has(first.uid):
			_pause_window(event)
	)
	# 有限批次；取消不以成功数量为while条件重新选牌。
	var resolution: RefCounted = _controller.begin_gain_cards(0, -1, [first.uid, second.uid], ["draw_pile"])
	_paused_event.cancel("test_cancel_gain")
	_submit_choice()
	await _settle_batch()
	_check(resolution.completed and resolution.count == 1 and _controller.state.draw_pile.has(first) and first.known_to == [1] and _controller.state.get_player(0).hand.has(second), "pile gain cancellation mutated source or repeated")
	_check_clean("pile cancel")


## 目标在gain前置中死亡时，旧获得不能把牌送进死者手牌。
func _test_receiver_death() -> void:
	_reset_controller()
	# 来源区域两张牌；死亡只使获得失效，不提前移除来源。
	var uids: Array[int] = _cards(1)
	_controller.trigger_manager.subscribe("gainBefore", self, _pause_window)
	# 原获得结果；预期正常完成但实际数量为零。
	var resolution: RefCounted = _controller.begin_gain_cards(0, 1, uids, ["hand"])
	_controller.state.get_player(0).alive = false
	_submit_choice()
	await _settle_batch()
	_check(resolution.completed and resolution.count == 0 and _controller.state.get_player(1).hand.size() == 2, "dead receiver obtained cards")
	_check_clean("dead receiver")
