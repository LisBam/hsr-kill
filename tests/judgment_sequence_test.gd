extends "res://tests/damage_sequence_test.gd"

## 判定专项：窗口暂停、异步取消、结果回收及调用者只能收到一次完成结果。

class JudgmentController extends MatchController:
	## 本测试收到的判定结果；null以-1记录，用于断言回调不早于judgeAfter。
	var received_uids: Array[int] = []
	## 判定阶段唯一后继次数；测试隔离后续摸牌阶段。
	var phase_completions: int = 0

	## 记录兼容接收边界；真实技能与装备接收由新武将集成测试覆盖。
	func _dispatch_judgment_continuation(_continuation: Dictionary, card: CardInstance) -> void:
		if str(_continuation.get("receiver_type", "")) in ["card", "skill"]:
			super._dispatch_judgment_continuation(_continuation, card)
			return
		received_uids.append(card.uid if card != null else -1)

	## 只记录判定阶段完成，避免测试创建正常摸牌与出牌请求。
	func _continue_turn_after_judgment(_player_id: int) -> void:
		phase_completions += 1
		state.current_phase = "test"


## 测试控制器只替换结果接收者，所有判定和选择仍使用生产实现。
func _create_controller() -> MatchController:
	return JudgmentController.new()


## 每个窗口独立验证，不能用其它窗口的暂停掩盖抢跑。
func _run() -> void:
	for timing_name: String in ["judgeBefore", "judgeBegin", "judge", "judgeFixing", "discardBefore", "discardBegin", "cardsDiscardAfter", "judgeEnd", "judgeAfter"]:
		await _test_window(timing_name)
	await _test_cancel_before()
	await _test_generation_change()
	await _test_generation_after_reveal()
	_test_synchronous_result()
	await _test_request_cancelled()
	_test_nested_synchronous()
	await _test_nested_before(false)
	await _test_nested_before(true)
	await _test_three_nested_judgments()
	await _test_nested_result_damage()
	_test_nested_equipment_response()
	for timing_name: String in ["phaseJudge", "loseBefore", "judgeFixing", "cardsDiscardAfter"]:
		await _test_judgment_area_window(timing_name)
	await _test_lightning_returns_once()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("JUDGMENT_SEQUENCE_PASS windows cancellation generation synchronous continuation nested equipment")
	get_tree().quit(1 if _failed else 0)


## 任一窗口的选择结束前不得派发其后窗口或通知原调用者。
func _test_window(timing_name: String) -> void:
	_reset_controller()
	# 唯一判定牌；无洗牌随机性，退出时必须仍是同一实体。
	var card: CardInstance = _add_judgment_card()
	# 实际通知顺序；结果和处理区回收必须按无名杀式内容步骤逐个发生。
	var observed: Array[String] = []
	for name: String in ["judgeBefore", "judgeBegin", "judge", "judgeFixing", "discardBefore", "discardBegin", "cardsDiscardAfter", "judgeEnd", "judgeAfter"]:
		_controller.event_bus.subscribe(name, self, func(event: RuleEvent) -> void: observed.append(event.name))
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	_check(_controller.request_judgment(0, "窗口测试") == null, timing_name + " returned unfinished result")
	_check(_controller.has_pending_card_choice() and _controller.has_pending_judgment_request(), timing_name + " missing pause")
	_check(not observed.is_empty() and observed.back() == timing_name, timing_name + " skipped to " + str(observed))
	_check((_controller as JudgmentController).received_uids.is_empty(), timing_name + " callback before child completion")
	if timing_name in ["judgeBefore", "judgeBegin"]:
		_check(_controller.state.draw_pile.has(card), timing_name + " consumed deck early")
	elif timing_name in ["judge", "judgeFixing", "discardBefore", "discardBegin"]:
		_check(_controller.state.processing_area.has(card), timing_name + " discarded result early")
	_submit_choice()
	await _settle_judgment()
	_check((_controller as JudgmentController).received_uids == [card.uid], timing_name + " missing or repeated completion")
	_check(_controller.state.discard_pile.has(card) and _controller.state.processing_area.is_empty(), timing_name + " stranded card")
	_check_clean(timing_name)


## judgeBegin异步取消保留牌堆，并以空结果完成一次原请求。
func _test_cancel_before() -> void:
	_reset_controller()
	# 未消费的牌堆实体；取消不能触发亮牌或弃牌。
	var card: CardInstance = _add_judgment_card()
	_controller.trigger_manager.subscribe("judgeBegin", self, _pause_window)
	_controller.request_judgment(0, "取消判定")
	if _paused_event != null:
		_paused_event.cancel("test_cancel")
	_submit_choice()
	await _settle_judgment()
	_check(_controller.state.draw_pile.has(card) and (_controller as JudgmentController).received_uids == [-1], "cancelled judgment consumed card or repeated")
	_check_clean("cancelled judgment")


## 前置等待期间换将使旧请求失效，新角色不能接收旧判定牌。
func _test_generation_change() -> void:
	_reset_controller()
	# 换将前尚未取走的判定牌；检查原子提交前的代次保护。
	var card: CardInstance = _add_judgment_card()
	_controller.trigger_manager.subscribe("judgeBefore", self, _pause_window)
	_controller.request_judgment(0, "换将判定")
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_judgment()
	_check(_controller.state.draw_pile.has(card) and (_controller as JudgmentController).received_uids == [-1], "old generation consumed judgment")
	_check_clean("judgment generation")


## 判定牌已亮出后换将仍需完整回收，原调用者只能取得一次失效结果。
func _test_generation_after_reveal() -> void:
	_reset_controller()
	# 已经翻开的判定牌；换将不能使它永久遗留处理区。
	var card: CardInstance = _add_judgment_card()
	_controller.trigger_manager.subscribe("judgeFixing", self, _pause_window)
	_controller.request_judgment(0, "亮牌后换将")
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_judgment()
	_check(_controller.state.discard_pile.has(card) and (_controller as JudgmentController).received_uids == [-1], "revealed old judgment stranded or delivered to new generation")
	_check_clean("judgment generation after reveal")


## 没有任何等待时仍兼容返回实体，异步接收者不能被重复调用。
func _test_synchronous_result() -> void:
	_reset_controller()
	# 原判定实体；返回身份与最终区域均须保持一致。
	var card: CardInstance = _add_judgment_card()
	_check(_controller.request_judgment(0, "同步判定") == card, "synchronous judgment lost result")
	_check((_controller as JudgmentController).received_uids.is_empty(), "synchronous judgment invoked async callback")
	_check_clean("synchronous judgment")


## 内层同步完成时，外层仍活动不等于内层尚未完成；结果对象必须保持独立。
func _test_nested_synchronous() -> void:
	_reset_controller()
	# 先入牌堆底的外层牌；内层先取走随后压入的牌堆顶。
	var outer_card: CardInstance = _add_judgment_card()
	# 内层判定牌；稳定身份保证不会重复取同一张实体。
	var inner_card: CardInstance = _add_judgment_card()
	# 保存内层结果对象，外层回调结束后仍能验证其完成状态。
	var inner: Array[RefCounted] = []
	_controller.trigger_manager.subscribe("judgeBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("reason", "")) == "outer_sync":
			inner.append(_controller.begin_judgment_resolution(1, "inner_sync"))
	)
	# 外层结果对象；全部同步结束，不应额外通知异步接收者。
	var outer: RefCounted = _controller.begin_judgment_resolution(0, "outer_sync")
	_check(inner.size() == 1 and inner[0].completed and inner[0].result == inner_card, "nested sync inner result")
	_check(outer.completed and outer.result == outer_card and not _controller.has_pending_judgment_request(), "nested sync outer result")
	_check((_controller as JudgmentController).received_uids.is_empty(), "nested sync duplicated callback")
	_check_clean("nested sync")


## 内层前置可暂停或取消；内层结束前外层不翻牌，完成后只移除自己的请求。
func _test_nested_before(cancel_inner: bool) -> void:
	_reset_controller()
	# 外层原定牌；取消内层时它应继续留在牌堆底。
	var outer_card: CardInstance = _add_judgment_card()
	# 当前牌堆顶；正常由内层取，取消内层后由外层取。
	var inner_card: CardInstance = _add_judgment_card()
	# 内层结果；无需全局单请求字段判断等待。
	var inner: Array[RefCounted] = []
	_controller.trigger_manager.subscribe("judgeBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("reason", "")) == "outer_async":
			inner.append(_controller.begin_judgment_resolution(1, "inner_async"))
		elif str(event.data.get("reason", "")) == "inner_async":
			_pause_window(event)
	)
	# 外层结果；必须与内层共同保持未完成。
	var outer: RefCounted = _controller.begin_judgment_resolution(0, "outer_async")
	_check(not outer.completed and inner.size() == 1 and not inner[0].completed and _controller._pending_judgment_request.size() == 2, "nested requests overwritten")
	_check(_controller.state.draw_pile.size() == 2, "outer revealed while inner waiting")
	if cancel_inner and _paused_event != null:
		_paused_event.cancel("cancel_nested")
	_submit_choice()
	await _settle_judgment()
	_check(inner[0].completed and inner[0].result == (null if cancel_inner else inner_card), "nested async inner result")
	_check(outer.completed and outer.result == (inner_card if cancel_inner else outer_card), "nested async outer result")
	_check((_controller as JudgmentController).received_uids == ([-1, inner_card.uid] if cancel_inner else [inner_card.uid, outer_card.uid]), "nested callbacks out of order")
	_check_clean("nested cancellation" if cancel_inner else "nested async")


## 三层判定在最低步骤预算下仍按最内层优先，不能形成祖先互等或重复翻牌。
func _test_three_nested_judgments() -> void:
	_reset_controller()
	_controller.max_settlement_steps_per_pass = 2
	# 从牌堆底到顶的固定身份；完成顺序应恰好相反。
	var cards: Array[CardInstance] = [_add_judgment_card(), _add_judgment_card(), _add_judgment_card()]
	_controller.trigger_manager.subscribe("judgeBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("reason", "")) == "level_1":
			_controller.begin_judgment_resolution(1, "level_2")
		elif str(event.data.get("reason", "")) == "level_2":
			_controller.begin_judgment_resolution(2, "level_3")
	)
	_controller.begin_judgment_resolution(0, "level_1")
	await _settle_judgment()
	_check((_controller as JudgmentController).received_uids == [cards[2].uid, cards[1].uid, cards[0].uid], "three nested judgments under budget did not finish in order")
	_check(_controller.state.discard_pile.size() == 3 and _controller.state.processing_area.is_empty(), "nested budget lost physical cards")
	_check_clean("three nested budget")


## 内层判定结果时机插入可暂停伤害，内层与外层判定必须共同等待伤害完成。
func _test_nested_result_damage() -> void:
	_reset_controller()
	# 两个判定实体；外层在内层的结果伤害结束前不能消耗第二张。
	var cards: Array[CardInstance] = [_add_judgment_card(), _add_judgment_card()]
	_controller.trigger_manager.subscribe("judgeBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("reason", "")) == "outer_damage":
			_controller.begin_judgment_resolution(1, "inner_damage")
	)
	_controller.trigger_manager.subscribe("judgeFixing", self, func(event: RuleEvent) -> void:
		if str(event.data.get("reason", "")) == "inner_damage":
			_controller.damage(1, 2, 1)
	)
	_controller.trigger_manager.subscribe("damageBefore", self, _pause_window)
	# 外层结果对象；内层伤害仍在修改窗口时尚未完成。
	var outer: RefCounted = _controller.begin_judgment_resolution(0, "outer_damage")
	_check(_controller.has_pending_card_choice() and not outer.completed and _controller.state.draw_pile.has(cards[0]) and _controller.state.processing_area.has(cards[1]), "nested judgment skipped result damage")
	_submit_choice()
	await _settle_judgment()
	_check(outer.completed and _controller.state.get_player(2).hp == 19 and _controller.state.processing_area.is_empty(), "nested result damage completion")
	_check_clean("nested result damage")


## 外层judgeBefore中通过真实八卦阵发起内层判定，成功闪不能被外层全局等待状态吞掉。
func _test_nested_equipment_response() -> void:
	_reset_controller()
	# 两张红桃判定牌；八卦判定结果固定成功，不依赖随机。
	var cards: Array[CardInstance] = [_add_judgment_card(), _add_judgment_card()]
	# 正式八卦阵实体；装备定义会自行发起判定并构造响应牌。
	var armor: CardInstance = CardInstance.new("bagua", "spade", 2)
	armor.zone = "equipment"
	armor.owner_id = 1
	_controller.state.get_player(1).equipment["armor"] = armor
	# 八卦响应结果；它必须在外层仍活动时同步完成。
	var responses: Array[RefCounted] = []
	_controller.trigger_manager.subscribe("judgeBefore", self, func(event: RuleEvent) -> void:
		if str(event.data.get("reason", "")) == "outer_equipment":
			responses.append(_controller.begin_response_resolution(1, armor.uid, ["shan"]))
	)
	# 外层判定结果；八卦内部只移除自身请求，不破坏外层的后续。
	var outer: RefCounted = _controller.begin_judgment_resolution(0, "outer_equipment")
	_check(responses.size() == 1 and responses[0].completed and responses[0].result != null and responses[0].result.definition_id == "shan", "outer pending state swallowed nested bagua result")
	_check(outer.completed and outer.result == cards[0] and not _controller.has_pending_judgment_request(), "bagua nested request corrupted outer")
	_check_clean("nested equipment response")


## 填充唯一牌堆顶，角色数据与其它伤害测试夹具共用。
func _add_judgment_card() -> CardInstance:
	# 红桃判定实体；同一对象贯穿牌堆、处理区和弃牌堆。
	var card: CardInstance = CardInstance.new("tao", "heart", 6)
	card.zone = "draw_pile"
	_controller.state.draw_pile.append(card)
	return card


## 正常管线有限步进；不使用看门狗，不清空任何生产队列。
func _settle_judgment() -> void:
	for attempt: int in range(60):
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if not _controller.has_pending_judgment_request() and _controller._rule_sequences.is_empty():
			return
		await get_tree().process_frame
	_check(false, "judgment did not settle")


## 两张延时牌必须后来居上，第一张的任意子窗口暂停都不能提前处理第二张或结束阶段。
func _test_judgment_area_window(timing_name: String) -> void:
	_reset_controller()
	_controller.state.current_phase = "judgment"
	_controller.delayed_judgment_preview_seconds = 0.001
	_controller.delayed_judgment_result_pause_seconds = 0.001
	# 较早放置的乐不思蜀；需要最后处理。
	var first: CardInstance = _add_delayed_card("lebu")
	# 较晚放置的兵粮；需要首先处理。
	var second: CardInstance = _add_delayed_card("bingliang")
	_add_judgment_card()
	_add_judgment_card()
	# 外层实际处理顺序；不使用最终弃牌顺序代替时机顺序。
	var order: Array[int] = []
	_controller.event_bus.subscribe("phaseJudge", self, func(event: RuleEvent) -> void: order.append(int(event.data.card_uid)))
	_controller.trigger_manager.subscribe(timing_name, self, func(event: RuleEvent) -> void:
		if _paused_event == null:
			_pause_window(event)
	)
	_controller._process_judgment_area(0)
	for attempt: int in range(100):
		if _controller.has_pending_card_choice():
			break
		await get_tree().create_timer(0.005).timeout
	_check(_controller.has_pending_card_choice() and order == [second.uid], timing_name + " delayed next card ran early")
	_check(_controller.state.get_player(0).judgment_area.has(first) and (_controller as JudgmentController).phase_completions == 0, timing_name + " delayed phase completed early")
	_submit_choice()
	await _settle_area()
	_check(order == [second.uid, first.uid] and (_controller as JudgmentController).phase_completions == 1, timing_name + " delayed order or completion wrong")
	_check(_controller.state.processing_area.is_empty() and _controller.state.discard_pile.size() == 4, timing_name + " stranded delayed/result card")
	_check_clean(timing_name + " delayed area")


## 闪电传回本人后本阶段只判定一次，禁止同步while反复消费牌堆。
func _test_lightning_returns_once() -> void:
	_reset_controller()
	_controller.state.current_phase = "judgment"
	_controller.delayed_judgment_preview_seconds = 0.0
	_controller.delayed_judgment_result_pause_seconds = 0.0
	_controller.state.get_player(1).judgment_area_abolished = true
	_controller.state.get_player(2).judgment_area_abolished = true
	# 红桃结果不命中闪电；唯一合法传递目的地是本人。
	var card: CardInstance = _add_delayed_card("shandian")
	_add_judgment_card()
	_controller._process_judgment_area(0)
	await _settle_area()
	_check(_controller.state.get_player(0).judgment_area.has(card) and _controller.state.discard_pile.size() == 1 and (_controller as JudgmentController).phase_completions == 1, "lightning judged itself repeatedly")
	_check_clean("lightning return")


## 判定区实体始终由正式移动服务移除，不在测试中预先pop。
func _add_delayed_card(definition_id: String) -> CardInstance:
	# 当前延时牌；后追加者先结算。
	var card: CardInstance = CardInstance.new(definition_id, "spade", 5)
	card.zone = "judgment"
	card.owner_id = 0
	_controller.state.get_player(0).judgment_area.append(card)
	return card


## 等待真实表现间隔与正式结算管线；时间预算只用于测试失败，不修复运行状态。
func _settle_area() -> void:
	for attempt: int in range(100):
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller._rule_sequences.is_empty() and not _controller._judgment_flow_in_progress:
			return
		await get_tree().create_timer(0.005).timeout
	_check(false, "judgment area did not settle")


## 阶段中断清除请求身份后，旧内容只能正常结束，不能继续翻牌或通知旧接收者。
func _test_request_cancelled() -> void:
	_reset_controller()
	# 尚未翻开的原牌堆实体。
	var card: CardInstance = _add_judgment_card()
	_controller.trigger_manager.subscribe("judgeBefore", self, _pause_window)
	# 中断前的结果句柄；即使请求被清除也应完成为空结果。
	var resolution: RefCounted = _controller.begin_judgment_resolution(0, "cancel_request")
	_controller._clear_pending_judgment_request()
	_submit_choice()
	await _settle_judgment()
	_check(resolution.completed and resolution.result == null and _controller.state.draw_pile.has(card) and (_controller as JudgmentController).received_uids.is_empty(), "cancelled request continued or notified stale owner")
	_check_clean("cancelled request")
