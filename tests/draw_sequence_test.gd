extends "res://tests/damage_sequence_test.gd"

## 摸牌与逐张获得牌时序回归；异步窗口通过真实请求恢复。

## 覆盖修改、取消、逐张获得和结束通知暂停。
func _run() -> void:
	_test_draw_before_waits_and_reads_final_count()
	_test_gain_before_waits_before_move()
	_test_gain_cancellation_keeps_card_in_pile()
	_test_draw_end_waits_for_after()
	await _test_card_content_waits_for_nested_draw()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("DRAW_SEQUENCE_PASS draw_windows gain_windows cancellation batch")
	get_tree().quit(1 if _failed else 0)


## drawBefore选择期间不摸牌，恢复后使用最终count并逐张等待gain事件。
func _test_draw_before_waits_and_reads_final_count() -> void:
	_reset_controller()
	_add_draw_cards(2)
	_controller.trigger_manager.subscribe("drawBefore", self, _pause_window)
	var requested_counts: Array[int] = []
	_controller.event_bus.subscribe("drawEnd", self, func(event: RuleEvent) -> void: requested_counts.append(int(event.data.get("requested_count", -1))))
	_controller.draw(0, 1)
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(0).hand.is_empty(), "drawBefore moved cards early")
	_paused_event.data["count"] = 2
	_submit_choice()
	_check(_controller.state.get_player(0).hand.size() == 2, "drawBefore final count was lost")
	_check(requested_counts == [2], "drawEnd reported the original request instead of the final request: " + str(requested_counts))
	_check(_controller._rule_sequences.is_empty(), "drawBefore left draw sequence")
	_check_clean("drawBefore")


## gainBefore子选择完成之前实体仍留在牌堆，之后才进入手牌一次。
func _test_gain_before_waits_before_move() -> void:
	_reset_controller()
	var card: CardInstance = _add_draw_cards(1)[0]
	_controller.trigger_manager.subscribe("gainBefore", self, _pause_window)
	_controller.draw(0, 1)
	_check(_controller.has_pending_card_choice() and _controller.state.draw_pile.has(card), "gainBefore moved card before choice")
	_submit_choice()
	_check(_controller.state.get_player(0).hand == [card] and _controller.state.draw_pile.is_empty(), "gainBefore did not commit exactly one move")
	_check_clean("gainBefore")


## gainBegin取消只阻止当前牌移动，但仍完成drawEnd事实和后续牌流程。
func _test_gain_cancellation_keeps_card_in_pile() -> void:
	_reset_controller()
	var card: CardInstance = _add_draw_cards(1)[0]
	var result_counts: Array[int] = []
	_controller.trigger_manager.subscribe("gainBegin", self, func(event: RuleEvent) -> void: event.cancel("test_gain_cancel"))
	_controller.event_bus.subscribe("drawEnd", self, func(event: RuleEvent) -> void: result_counts.append(int(event.data.get("count", -1))))
	_controller.draw(0, 1)
	_check(_controller.state.draw_pile == [card] and _controller.state.get_player(0).hand.is_empty(), "gainBegin cancellation moved card")
	_check(result_counts == [0], "cancelled draw result was incorrect: " + str(result_counts))
	_check_clean("gainBegin cancel")


## drawEnd已提交摸牌事实，但drawAfter与表现批次必须等End选择结束。
func _test_draw_end_waits_for_after() -> void:
	_reset_controller()
	_add_draw_cards(1)
	var order: Array[String] = []
	for timing: String in ["drawEnd", "drawAfter"]:
		_controller.event_bus.subscribe(timing, self, func(event: RuleEvent) -> void: order.append(event.name))
	_controller.trigger_manager.subscribe("drawEnd", self, _pause_window)
	_controller.draw(0, 1)
	_check(_controller.state.get_player(0).hand.size() == 1 and order == ["drawEnd"], "drawEnd crossed choice or lost committed draw")
	_submit_choice()
	_check(order == ["drawEnd", "drawAfter"], "drawAfter order: " + str(order))
	_check(_controller._active_draw_presentation_batch.is_empty(), "draw presentation batch leaked")
	_check_clean("drawEnd")


## 正式用牌子事件等待牌效创建的摸牌序列后，才完成目标与用牌After。
func _test_card_content_waits_for_nested_draw() -> void:
	_reset_controller()
	_add_draw_cards(2)
	# 正式使用的无中生有；牌效只调用公开draw接口。
	var card: CardInstance = CardInstance.new("wuzhong", "club", 9)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	# 规则事实顺序；父牌After不能越过摸牌After。
	var order: Array[String] = []
	for timing: String in ["drawAfter", "useCardAfter"]:
		_controller.event_bus.subscribe(timing, self, func(event: RuleEvent) -> void: order.append(event.name))
	_controller.trigger_manager.subscribe("drawBefore", self, _pause_window)
	_controller._execute_card_use(0, card, [0])
	_check(_controller.has_pending_card_choice() and _controller.state.processing_area.has(card), "parent card completed while draw child was waiting")
	_check(order.is_empty() and _controller.state.get_player(0).hand.is_empty(), "draw child leaked results before choice")
	_submit_choice()
	await _settle_card()
	_check(order == ["drawAfter", "useCardAfter"], "parent use-card tail crossed draw: " + str(order))
	_check(_controller.state.discard_pile.has(card) and _controller.state.get_player(0).hand.size() == 2, "nested draw/card result mismatch")
	_check_clean("card content draw child")


## 只提交真实选择并排空正式用牌事件；不直接完成父牌或手工移动材料。
func _settle_card() -> void:
	for attempt: int in range(60):
		if _controller.has_pending_card_choice():
			_submit_choice()
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller.state.processing_area.is_empty():
			return
		await get_tree().process_frame
	_check(false, "card parent failed to resume after draw child")


## 向牌堆顶按规则顺序追加测试实体牌并返回副本。
func _add_draw_cards(count: int) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for index: int in range(count):
		var card: CardInstance = CardInstance.new("sha", "heart", index + 1)
		card.zone = "draw_pile"
		_controller.state.draw_pile.append(card)
		result.append(card)
	return result
