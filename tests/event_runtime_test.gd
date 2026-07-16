extends Node

## 事件运行时无头回归。验证事件树、暂停选择、触发排序、修正管线、虚拟牌和统一移牌的稳定契约。

## 本次测试的事件调度器；作为节点加入场景树，信号和生命周期与正式控制器一致。
var _scheduler: EventScheduler

## 事件实际执行顺序；每个步骤追加稳定文本，用于断言父子与 after 的先后关系。
var _execution_order: Array[String] = []

## 子事件额外网络暂停 token；选择响应完成后该 token 仍应阻塞事件恢复。
var _network_pause_token: int = -1

## 当前选择请求；测试使用其稳定请求 ID 构造正确和错误响应。
var _choice_request: ChoiceRequest

## 测试根事件；子事件结果应在父事件第二步执行前写回该对象。
var _root_event: GameEvent

## 测试子事件；用于查询最终状态和确认选择后恢复了第二步骤。
var _child_event: GameEvent


## 依次执行全部独立断言；任意失败立即以非0退出码结束无头测试。
func _ready() -> void:
	if not _test_event_tree_and_pause():
		return
	if not _test_held_root_accepts_children():
		return
	if not _test_terminal_states():
		return
	if not _test_trigger_order():
		return
	if not _test_modifier_pipeline():
		return
	if not _test_card_movement_and_virtual_card():
		return
	print("EVENT_RUNTIME_PASS order=%s history=%d" % [_execution_order, _scheduler.get_event_history().size()])
	get_tree().quit(0)


## 验证长期根事件只保持生命周期而不暂停子树；新增子事件必须可以立即执行并回到根等待状态。
func _test_held_root_accepts_children() -> bool:
	# 独立调度器；避免长期根事件影响本文件其他终止态与选择用例。
	var held_scheduler: EventScheduler = EventScheduler.new()
	add_child(held_scheduler)
	# 子事件执行次数；默认0，真实进入调度栈后必须严格增加到1。
	var child_execution_count: Array[int] = [0]
	# 长期根事件；空内容用于模拟正式对局的 RootGameEvent。
	var held_root: GameEvent = held_scheduler.create_event("HeldRoot", "root")
	if not held_scheduler.begin_root(held_root.event_id, true):
		return _fail("held_root_begin")
	# 根事件下的真实子事件；内容通过引用数组记录执行结果，不依赖事件摘要伪造完成。
	var child: GameEvent = held_scheduler.create_child(held_root.event_id, "HeldChild", "rule", [func(_event: GameEvent, _runtime: EventScheduler) -> void: child_execution_count[0] += 1])
	held_scheduler.drain()
	# 子事件快照；必须完成并最终化，根事件仍保持开放且没有任何生命周期暂停 token。
	var child_snapshot: Dictionary = held_scheduler.get_event_snapshot(child.event_id)
	# 根事件快照；子树结束后回到 waiting_children，等待下一条阶段或卡牌事件。
	var root_snapshot: Dictionary = held_scheduler.get_event_snapshot(held_root.event_id)
	if child_execution_count[0] != 1 or str(child_snapshot.get("status", "")) != "finished" or not bool(child_snapshot.get("finalized", false)):
		return _fail("held_root_child=%s/%s" % [child_execution_count, child_snapshot])
	if str(root_snapshot.get("status", "")) != "waiting_children" or not bool(root_snapshot.get("held_open", false)) or held_scheduler.pause_registry.has_active():
		return _fail("held_root_state=%s" % root_snapshot)
	held_scheduler.abort_all("test_complete")
	held_scheduler.queue_free()
	return true


## 验证子事件阻塞、选择请求、旧响应拒绝、多 token 暂停、结果回传和 after 队列。
func _test_event_tree_and_pause() -> bool:
	_scheduler = EventScheduler.new()
	_scheduler.name = "EventScheduler"
	add_child(_scheduler)
	_root_event = _scheduler.create_event("Root", "root", [Callable(self, "_root_step_zero"), Callable(self, "_root_step_one")])
	if not _scheduler.start(_root_event.event_id):
		return _fail("scheduler_start")
	if _execution_order != ["root0", "child0"]:
		return _fail("pause_order=%s" % [_execution_order])
	var pending_requests: Array[Dictionary] = _scheduler.get_pending_choice_requests()
	if pending_requests.size() != 1 or _scheduler.pause_registry.get_active_tokens().size() != 2:
		return _fail("pause_tokens requests=%d tokens=%d" % [pending_requests.size(), _scheduler.pause_registry.get_active_tokens().size()])
	# 错误响应者；必须被拒绝且不能改变事件步骤或释放任意暂停 token。
	var invalid_response: ChoiceResponse = ChoiceResponse.new(_choice_request.request_id, _choice_request.event_id, 9, true)
	invalid_response.card_ids = [101]
	if _scheduler.submit_choice(invalid_response):
		return _fail("invalid_response_accepted")
	# 正确选择响应；只释放 choice token，独立 network token 仍保持事件暂停。
	var response: ChoiceResponse = ChoiceResponse.new(_choice_request.request_id, _choice_request.event_id, 0, true)
	response.card_ids = [101]
	response.source = "ai"
	if not _scheduler.submit_choice(response) or _execution_order != ["root0", "child0"]:
		return _fail("choice_resumed_other_channel order=%s" % [_execution_order])
	if not _scheduler.resume(_network_pause_token, "network_ready"):
		return _fail("network_resume")
	if _execution_order != ["root0", "child0", "child1", "root1", "after0"]:
		return _fail("final_order=%s" % [_execution_order])
	if not _root_event.finalized or not _child_event.finalized or _root_event.status != GameEvent.Status.FINISHED:
		return _fail("event_finalization root=%s child=%s" % [_root_event.to_dict(), _child_event.to_dict()])
	# 同一请求已经从活动索引移除，迟到结果不能再次恢复或覆盖父事件结果。
	if _scheduler.submit_choice(response):
		return _fail("stale_response_accepted")
	return true


## 根事件第一步；创建普通子事件和主体结束后执行的 after 事件。
func _root_step_zero(event: GameEvent, scheduler: EventScheduler) -> void:
	_execution_order.append("root0")
	_child_event = scheduler.create_child(event.event_id, "Child", "choice", [Callable(self, "_child_step_zero"), Callable(self, "_child_step_one")])
	scheduler.create_child(event.event_id, "After", "card_move", [Callable(self, "_after_step")], {}, "after")


## 根事件第二步；子事件结果必须已经复制到父事件，随后正常结束主体。
func _root_step_one(event: GameEvent, _scheduler_instance: EventScheduler) -> void:
	_execution_order.append("root1")
	if int(event.result.get("value", -1)) != 7:
		_fail("child_result_not_propagated=%s" % event.result)
	event.finish()


## 子事件第一步；同时创建网络暂停和选择暂停，验证两个通道必须分别释放。
func _child_step_zero(event: GameEvent, scheduler: EventScheduler) -> void:
	_execution_order.append("child0")
	_network_pause_token = scheduler.pause("network", "remote_wait", event.event_id)
	_choice_request = ChoiceRequest.new(event.event_id, 0, "card", "请选择一张测试牌")
	_choice_request.card_ids = [101]
	_choice_request.min_count = 1
	_choice_request.max_count = 1
	_choice_request.forced = true
	_choice_request.can_cancel = false
	scheduler.request_choice(_choice_request)


## 子事件恢复步骤；写入结构化结果并正常结束，父事件随后才能继续。
func _child_step_one(event: GameEvent, _scheduler_instance: EventScheduler) -> void:
	_execution_order.append("child1")
	event.result = {"value":7}
	event.finish()


## after 事件内容；只有根事件主体 finish 后才能执行。
func _after_step(event: GameEvent, _scheduler_instance: EventScheduler) -> void:
	_execution_order.append("after0")
	event.finish()


## 验证 finish、cancel 和 neutralize 三态互不混淆，且中立化可在最终化前解除。
func _test_terminal_states() -> bool:
	var finished_event: GameEvent = GameEvent.new("Finish")
	finished_event.finish("normal")
	var cancelled_event: GameEvent = GameEvent.new("Cancel")
	cancelled_event.cancel("rule_cancel")
	var neutralized_event: GameEvent = GameEvent.new("Neutralize")
	neutralized_event.neutralize("wuxie")
	if finished_event.status != GameEvent.Status.FINISHED or cancelled_event.status != GameEvent.Status.CANCELLED or neutralized_event.status != GameEvent.Status.NEUTRALIZED:
		return _fail("terminal_states")
	if not neutralized_event.unneutralize() or neutralized_event.status != GameEvent.Status.RUNNING:
		return _fail("unneutralize")
	return true


## 验证 firstDo、普通优先级、座次和 lastDo 的稳定触发顺序。
func _test_trigger_order() -> bool:
	var manager: TriggerManager = TriggerManager.new()
	var owner: RefCounted = RefCounted.new()
	var order: Array[String] = []
	manager.subscribe("damage", owner, func(_event: RuleEvent) -> void: order.append("normal-seat1"), 5, 1)
	manager.subscribe("damage", owner, func(_event: RuleEvent) -> void: order.append("normal-seat0"), 5, 0)
	manager.subscribe("damage", owner, func(_event: RuleEvent) -> void: order.append("first"), -10, 2, "global", true)
	manager.subscribe("damage", owner, func(_event: RuleEvent) -> void: order.append("last"), 100, 0, "global", false, true)
	manager.dispatch(RuleEvent.new("damage"), 1, [0, 1, 2])
	if order != ["first", "normal-seat1", "normal-seat0", "last"]:
		return _fail("trigger_order=%s" % [order])
	return true


## 验证纯修正器按优先级链式接收前一项结果，且不触发任何 RuleEvent。
func _test_modifier_pipeline() -> bool:
	var pipeline: RuleModifierPipeline = RuleModifierPipeline.new()
	var owner: RefCounted = RefCounted.new()
	pipeline.register("distance", owner, func(value: Variant, _context: Dictionary) -> Variant: return int(value) + 2, 10)
	pipeline.register("distance", owner, func(value: Variant, _context: Dictionary) -> Variant: return int(value) * 3, 0)
	if int(pipeline.apply("distance", 1)) != 9:
		return _fail("modifier_pipeline")
	return true


## 验证实体牌区域变化、知识状态、移动历史与虚拟牌材料 UID 分离。
func _test_card_movement_and_virtual_card() -> bool:
	var game_state: GameState = GameState.new()
	game_state.players.append(PlayerState.new(0, "测试玩家"))
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	game_state.draw_pile.append(card)
	var movement: CardMovementService = CardMovementService.new(game_state)
	if movement.move_card(card, "hand", 0, "draw", 1, "", [0]) == null:
		return _fail("move_to_hand")
	if movement.move_card(card, "processing", -1, "use", 2) == null:
		return _fail("move_to_processing")
	if movement.move_card(card, "discard_pile", -1, "discard", 2) == null:
		return _fail("move_to_discard")
	if game_state.card_move_history.size() != 3 or not game_state.discard_pile.has(card) or not card.shown or not card.known_to.has(0):
		return _fail("move_history=%s card=%s" % [game_state.card_move_history, card.to_dict()])
	var virtual_card: VirtualCard = VirtualCard.new("sha", "none", 0, "fire")
	virtual_card.virtual_id = 1
	virtual_card.add_material(card.uid)
	virtual_card.add_material(card.uid)
	if virtual_card.material_card_uids != [card.uid]:
		return _fail("virtual_materials=%s" % [virtual_card.material_card_uids])
	var wuxie_state: WuxieChainState = WuxieChainState.new(10)
	wuxie_state.add_response(0, {"card_uid":card.uid})
	wuxie_state.add_response(1, {"card_uid":card.uid + 1})
	if wuxie_state.state != 1 or wuxie_state.is_neutralized():
		return _fail("wuxie_state=%s" % wuxie_state.to_dict())
	return true


## 输出失败原因并结束场景；返回 false 便于调用方立即停止后续断言。
func _fail(reason: String) -> bool:
	printerr("EVENT_RUNTIME_FAIL %s" % reason)
	get_tree().quit(1)
	return false
