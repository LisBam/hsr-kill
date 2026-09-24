extends "res://tests/damage_sequence_test.gd"

## 卡牌生命周期异步回归；复用伤害测试的权威请求与隔离对局夹具。


## 各窗口独立等待，最终取消和卸载状态必须在后续效果前生效。
func _run() -> void:
	# 当前被测前置时机；每轮创建独立对局，避免其他取消窗口掩盖失败。
	for timing_name: String in ["useCardBefore", "useCardBegin", "useCard0", "useCard1", "yingbian", "useCard2", "useCard", "useCardToPlayer", "useCardToTarget", "useCardToPlayered", "useCardToTargeted", "useCardToBefore", "useCardToBegin", "shaBefore", "shaBegin"]:
		await _test_cancel_after_choice(timing_name)
	await _test_lifecycle_window_order()
	await _test_response_after_window()
	_test_unsubscribed_snapshot()
	_test_skill_child_wait()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("CARD_TIMING_SEQUENCE_PASS windows=15 lifecycle response subscription skill")
	get_tree().quit(1 if _failed else 0)


## 等待每个前置窗口后取消，当前目标不得受到伤害，处理区必须正常清理。
func _test_cancel_after_choice(timing_name: String) -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 实体杀；使用正式处理区移动与牌效流程验证取消不会吞材料收尾。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	_check(_controller.has_pending_card_choice() and _paused_event != null and _paused_event.name == timing_name, timing_name + " missing window")
	_check(_controller.state.get_player(1).hp == 20, timing_name + " applied while waiting")
	if _paused_event != null:
		_paused_event.cancel("test_after_choice")
	_submit_choice()
	await _settle_card()
	_check(_controller.state.get_player(1).hp == 20, timing_name + " lost asynchronous cancellation")
	_check(_controller.state.processing_area.is_empty() and _controller.state.discard_pile.has(card), timing_name + " lost ordering discard")
	_check_clean(timing_name)


## 同一牌的前后时机必须严格逐个完成；不会在End技能等待时提前发布After。
func _test_lifecycle_window_order() -> void:
	_reset_controller()
	# 按规则声明的生命周期顺序；每组使用一个暂停，恢复前只能出现这一组中的当前项。
	var timing_names: Array[String] = ["useCardBefore", "useCardBegin", "useCardToBefore", "useCardToBegin", "shaBefore", "shaBegin", "shaEnd", "shaAfter", "useCardToEnd", "useCardToAfter", "useCardEnd", "useCardAfter"]
	# 已观察时机；监听总线入口可发现后续时机在选择尚未结束时抢跑。
	var observed: Array[String] = []
	# 当前生命周期名；分别监听发布顺序并在触发处理器内制造选择暂停。
	for timing_name: String in timing_names:
		_controller.event_bus.subscribe(timing_name, self, func(event: RuleEvent) -> void: observed.append(event.name))
		_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 用于驱动完整响应和伤害的实体杀；目标无闪，普通响应放弃后命中一次。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	# 有限步进次数；覆盖生命周期12次暂停和普通响应，避免测试自身在失败时无限等待。
	for attempt: int in range(60):
		if _controller.has_pending_card_choice():
			# 当前选择种类；窗口选择必须对应刚刚开始的最后一个生命周期时机。
			var choice_kind: String = str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))
			if choice_kind == "test_window":
				_check(observed.size() <= timing_names.size() and observed.back() == str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("test_timing_name", "")), "lifecycle advanced while waiting: " + str(observed))
			_submit_choice()
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller.state.processing_area.is_empty():
			break
		await get_tree().process_frame
	_check(observed == timing_names, "lifecycle order " + str(observed))
	_check(_controller.state.get_player(1).hp == 19, "lifecycle repeated or lost damage")
	_check_clean("lifecycle")


## 响应结束时先关闭旧询问；After里的新询问必须被保留，并先于父牌效果完成。
func _test_response_after_window() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("chooseToRespondAfter", self, _pause_window)
	# 普通杀；目标放弃闪后，响应After内的新技能选择仍属于本次响应的子结算。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	_submit_choice()
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(1).hp == 20, "response After swallowed nested choice or applied damage early")
	if _controller.has_pending_card_choice():
		_submit_choice()
	await _settle_card()
	_check(_controller.state.get_player(1).hp == 19, "response result did not resume exactly once")
	_check_clean("response After")


## 已开始时机只保留排序快照，执行前重新检查订阅身份。
## 等待期间卸载并重新安装同一所有者，旧排序快照也不能重新触发该技能。
func _test_unsubscribed_snapshot() -> void:
	_reset_controller()
	# 独立订阅所有者；本对象仍存活，排除仅检查Object有效性带来的假通过。
	var owner: RefCounted = RefCounted.new()
	# 旧与新回调调用计数；第一次事件均不得运行，下一事件只执行新订阅一次。
	var invocations: Array[int] = [0, 0]
	_controller.trigger_manager.subscribe("damageBegin4", self, _pause_window, 10)
	_controller.trigger_manager.subscribe("damageBegin4", owner, func(_event: RuleEvent) -> void: invocations[0] += 1)
	_controller.damage(0, 1, 1)
	_controller.trigger_manager.unsubscribe_owner(owner)
	_controller.trigger_manager.subscribe("damageBegin4", owner, func(_event: RuleEvent) -> void: invocations[1] += 1)
	_submit_choice()
	_check(invocations == [0, 0], "uninstalled or newly installed subscription entered old snapshot")
	_controller.trigger_manager.unsubscribe_owner(self)
	_controller.damage(0, 1, 1)
	_check(invocations == [0, 1], "new event failed to collect new subscription")
	_check_clean("subscription")


## 正式加护技能使用通用步骤接口；横置的子时机尚未完成时不能抢先授予护盾。
func _test_skill_child_wait() -> void:
	_reset_controller()
	# 加护实例；按正式安装路径登记，保持技能与武将代次保护。
	var skill: SkillDefinition = GameDatabase.create_skill("jiahu")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"jiahu":skill}
	skill.install()
	_controller.trigger_manager.subscribe("linkAfter", self, _pause_window)
	_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, -1)
	_submit_choice([1])
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(1).chained and _controller.state.get_player(1).shield == 0, "skill skipped link child wait")
	_submit_choice()
	_check(_controller.state.get_player(1).shield == 1, "skill failed to grant exactly one shield")
	_check_clean("skill steps")


## 只放弃合法响应并排空当前内容，不借助看门狗推进或直接移动实体牌。
func _settle_card() -> void:
	# 最大推进次数60；有限循环失败时保留原状态，不借助看门狗修补。
	for attempt: int in range(60):
		if _controller.has_pending_card_choice():
			_submit_choice()
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller.state.processing_area.is_empty():
			return
		await get_tree().process_frame
	_check(false, "card settlement did not finish")
