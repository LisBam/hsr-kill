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
	if not _test_abort_choice_scope():
		return
	if not _test_composite_choice_request():
		return
	if not _test_held_root_accepts_children():
		return
	if not _test_terminal_states():
		return
	if not _test_trigger_order():
		return
	if not _test_cancel_superseded_trigger_dispatch():
		return
	if not _test_nested_trigger_resume_order():
		return
	if not _test_rule_continuation_stack():
		return
	if not _test_modifier_pipeline():
		return
	if not _test_card_movement_and_virtual_card():
		return
	print("EVENT_RUNTIME_PASS order=%s history=%d" % [_execution_order, _scheduler.get_event_history().size()])
	get_tree().quit(0)


## 验证选牌与选目标可以写入同一 ChoiceResponse，并支持组合映射、备份恢复与序列化重建。
func _test_composite_choice_request() -> bool:
	# 组合选择请求；模拟“选择一张牌并选择该牌允许的一名目标”的主动技能。
	var request: ChoiceRequest = ChoiceRequest.new(90, 0, "card_target", "请选择一张牌和一名目标")
	request.request_id = 12
	request.card_ids = [101, 102]
	request.target_ids = [1, 2]
	request.min_card_count = 1
	request.max_card_count = 1
	request.min_target_count = 1
	request.max_target_count = 1
	request.base_context = {"kind":"skill_choice", "target_ids_by_card_id":{"101":[2], "102":[1, 2]}}
	request.active_context = request.base_context.duplicate(true)
	# 合法组合；卡牌101只能指定目标2。
	var valid_response: ChoiceResponse = ChoiceResponse.new(12, 90, 0, true)
	valid_response.card_ids = [101]
	valid_response.target_ids = [2]
	if not request.validate_response(valid_response).is_empty():
		return _fail("composite_valid_rejected")
	# 非法组合；卡牌与目标分别属于候选，但组合映射不允许101指定目标1。
	var invalid_response: ChoiceResponse = ChoiceResponse.new(12, 90, 0, true)
	invalid_response.card_ids = [101]
	invalid_response.target_ids = [1]
	if request.validate_response(invalid_response).is_empty():
		return _fail("composite_invalid_accepted")
	# 技能备份上下文；临时切换映射后恢复基础选择，已选牌和目标必须同时清空。
	request.selected_card_ids = [101]
	request.selected_target_ids = [2]
	request.backup_context("test_backup", {"definition_id":"sha"}, {"target_ids_by_card_id":{"101":[1]}}, {"cards":[1, 1], "targets":[1, 1]})
	request.restore_context()
	if request.active_context != request.base_context or not request.selected_card_ids.is_empty() or not request.selected_target_ids.is_empty():
		return _fail("composite_restore=%s" % request.to_dict())
	# 网络重建；四个独立数量范围和目标候选必须完整保留。
	var restored_request: ChoiceRequest = ChoiceRequest.from_dict(request.to_dict())
	if restored_request.choice_type != "card_target" or restored_request.card_ids != [101, 102] or restored_request.target_ids != [1, 2] or restored_request.min_card_count != 1 or restored_request.max_target_count != 1:
		return _fail("composite_roundtrip=%s" % restored_request.to_dict())
	return true


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


## 验证无解选择的中断只终止所属子事件、释放自己的暂停令牌，并允许父事件继续完成。
func _test_abort_choice_scope() -> bool:
	# 独立调度器；该用例会主动中断选择，不与正常响应测试共享历史或事件栈。
	var abort_scheduler: EventScheduler = EventScheduler.new()
	add_child(abort_scheduler)
	# 执行顺序记录；中断后子事件第二步不得执行，父事件第二步必须继续。
	var execution_order: Array[String] = []
	# 选择请求引用容器；子事件创建请求后供测试主体读取真实全局请求ID。
	var request_holder: Array = [null]
	# 子事件引用容器；中断完成后用于确认其终态严格为aborted。
	var child_holder: Array = [null]
	# 测试根事件；第一步创建选择子事件，第二步证明父流程没有被扩大中断。
	var root_event: GameEvent = abort_scheduler.create_event("AbortRoot", "root", [
		func(event: GameEvent, runtime: EventScheduler) -> void:
			execution_order.append("root0")
			child_holder[0] = runtime.create_child(event.event_id, "AbortChoiceChild", "choice", [
				func(child_event: GameEvent, child_runtime: EventScheduler) -> void:
					execution_order.append("child0")
					# 强制单牌请求；保持等待直到测试主体调用abort_choice最终保护入口。
					var request: ChoiceRequest = ChoiceRequest.new(child_event.event_id, 0, "card", "请选择一张测试牌")
					request.card_ids = [201]
					request.min_count = 1
					request.max_count = 1
					request.forced = true
					request.can_cancel = false
					request_holder[0] = child_runtime.request_choice(request),
				func(_child_event: GameEvent, _child_runtime: EventScheduler) -> void:
					execution_order.append("child1"),
			]),
		func(event: GameEvent, _runtime: EventScheduler) -> void:
			execution_order.append("root1")
			event.finish(),
	])
	if not abort_scheduler.start(root_event.event_id) or execution_order != ["root0", "child0"]:
		return _fail("abort_choice_start order=%s" % [execution_order])
	# 当前真实请求；必须已经登记并持有唯一choice暂停令牌。
	var pending_request: ChoiceRequest = request_holder[0] as ChoiceRequest
	if pending_request == null or abort_scheduler.pause_registry.get_active_tokens().size() != 1:
		return _fail("abort_choice_pending")
	if not abort_scheduler.abort_choice(pending_request.request_id, "test_unresolvable"):
		return _fail("abort_choice_rejected")
	# 已中断子事件；父根应继续第二步并正常完成，调度器不再保留任何请求或暂停。
	var aborted_child: GameEvent = child_holder[0] as GameEvent
	if execution_order != ["root0", "child0", "root1"] or aborted_child == null or aborted_child.status != GameEvent.Status.ABORTED or root_event.status != GameEvent.Status.FINISHED or not root_event.finalized or abort_scheduler.pause_registry.has_active() or not abort_scheduler.get_pending_choice_requests().is_empty():
		return _fail("abort_choice_scope order=%s child=%s root=%s" % [execution_order, aborted_child.to_dict() if aborted_child != null else {}, root_event.to_dict()])
	# 迟到响应；请求索引已清除，不能恢复中断事件或再次推进父流程。
	var stale_response: ChoiceResponse = ChoiceResponse.new(pending_request.request_id, pending_request.event_id, 0, true)
	stale_response.card_ids = [201]
	if abort_scheduler.submit_choice(stale_response):
		return _fail("abort_choice_stale_response")
	abort_scheduler.queue_free()
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


## 验证流程边界可以终止已暂停的旧时机，使剩余处理器不会在新阶段中恢复执行。
func _test_cancel_superseded_trigger_dispatch() -> bool:
	# 独立触发器管理器；本用例只验证事件失效边界，不依赖对局控制器状态。
	var manager: TriggerManager = TriggerManager.new()
	# 是否暂停当前派发；首个处理器执行后模拟可选技能建立等待窗口。
	var paused: Array[bool] = [false]
	# 实际执行顺序；被取消的第二处理器不得写入本数组。
	var order: Array[String] = []
	manager.subscribe("phaseJudgeBegin", self, func(_event: RuleEvent) -> void:
		order.append("xianzou")
		paused[0] = true
	)
	manager.subscribe("phaseJudgeBegin", self, func(_event: RuleEvent) -> void: order.append("feiyang"))
	# 判定阶段开始事件；player_id为0，用于验证角色范围不会误取消其他角色的同名时机。
	var phase_event: RuleEvent = RuleEvent.new("phaseJudgeBegin", 0, 0, {}, 0)
	manager.dispatch(phase_event, 0, [0], func() -> bool: return paused[0])
	if order != ["xianzou"] or not manager.has_deferred_dispatches():
		return _fail("superseded_trigger_not_paused=%s" % [order])
	if manager.cancel_matching_dispatches("phaseJudgeBegin", 0, "phase_skipped") != 1 or phase_event.termination_reason != "phase_skipped":
		return _fail("superseded_trigger_not_cancelled")
	paused[0] = false
	manager.resume_deferred(func() -> bool: return paused[0])
	if order != ["xianzou"] or manager.has_deferred_dispatches():
		return _fail("superseded_trigger_resumed=%s" % [order])
	# 同步活动事件管理器；用于覆盖无需选择、直接在Begin回调内跳过阶段的锁定效果路径。
	var active_manager: TriggerManager = TriggerManager.new()
	# 同步活动事件执行顺序；首个回调终止事件后第二处理器不得执行。
	var active_order: Array[String] = []
	# 核心边界返回的取消数量；同一活动事件必须只计数一次。
	var active_cancelled_count: Array[int] = [0]
	active_manager.subscribe("phaseDrawBegin", self, func(_event: RuleEvent) -> void:
		active_order.append("skip")
		active_cancelled_count[0] = active_manager.cancel_matching_dispatches("phaseDrawBegin", 0, "phase_skipped")
	)
	active_manager.subscribe("phaseDrawBegin", self, func(_event: RuleEvent) -> void: active_order.append("stale"))
	# 同步摸牌阶段开始事件；不创建暂停请求，完全依赖活动派发栈完成失效。
	var active_phase_event: RuleEvent = RuleEvent.new("phaseDrawBegin", 0, 0, {}, 0)
	active_manager.dispatch(active_phase_event, 0, [0])
	if active_order != ["skip"] or active_cancelled_count[0] != 1 or active_phase_event.termination_reason != "phase_skipped":
		return _fail("active_superseded_trigger=%s count=%d" % [active_order, active_cancelled_count[0]])
	return true


## 验证回调内部暂停的嵌套时机会先恢复内层剩余触发，再回到外层后续处理器。
func _test_nested_trigger_resume_order() -> bool:
	# 独立触发器管理器；同一实例同时保存外层与内层暂停续列。
	var manager: TriggerManager = TriggerManager.new()
	# 订阅所有者；全部回调使用同一生命周期对象，避免测试结束前被自动清理。
	var owner: RefCounted = RefCounted.new()
	# 实际执行顺序；内层后半段必须严格位于外层后半段之前。
	var order: Array[String] = []
	# 模拟选择暂停状态；数组引用允许匿名回调与测试主体共享可变布尔值。
	var paused: Array[bool] = [false]
	manager.subscribe("inner", owner, func(_event: RuleEvent) -> void:
		order.append("inner0")
		paused[0] = true
	)
	manager.subscribe("inner", owner, func(_event: RuleEvent) -> void: order.append("inner1"))
	manager.subscribe("outer", owner, func(_event: RuleEvent) -> void:
		order.append("outer0")
		manager.dispatch(RuleEvent.new("inner"), -1, [], func() -> bool: return paused[0])
	)
	manager.subscribe("outer", owner, func(_event: RuleEvent) -> void: order.append("outer1"))
	manager.dispatch(RuleEvent.new("outer"), -1, [], func() -> bool: return paused[0])
	if order != ["outer0", "inner0"] or not manager.has_deferred_dispatches():
		return _fail("nested_trigger_pause=%s" % [order])
	paused[0] = false
	manager.resume_deferred(func() -> bool: return paused[0])
	if order != ["outer0", "inner0", "inner1", "outer1"] or manager.has_deferred_dispatches():
		return _fail("nested_trigger_resume=%s" % [order])
	return true


## 验证通用规则续接按最内层优先恢复，且登记与读取都不会泄露可修改的上下文引用。
func _test_rule_continuation_stack() -> bool:
	# 独立续接栈；本用例只验证纯数据组件，不依赖控制器或场景树生命周期。
	var continuation_queue: RuleContinuationQueue = RuleContinuationQueue.new()
	# 外层登记上下文；压栈后修改原字典不能污染队列快照。
	var outer_context: Dictionary = {"step":"outer", "values":[1]}
	if continuation_queue.push("outer", outer_context) < 0:
		return _fail("continuation_push_outer")
	outer_context["step"] = "mutated"
	if continuation_queue.push("inner", {"step":"inner"}) < 0 or continuation_queue.size() != 2:
		return _fail("continuation_push_inner=%s" % [continuation_queue.to_array()])
	# 最内层续接；必须先弹出inner，证明嵌套响应不会被外层阶段越过。
	var inner_continuation: Dictionary = continuation_queue.pop()
	# 外层续接；登记快照必须仍保留outer，而不是调用方后续写入的mutated。
	var outer_continuation: Dictionary = continuation_queue.pop()
	if str(inner_continuation.get("continuation_type", "")) != "inner" or str((inner_continuation.get("context", {}) as Dictionary).get("step", "")) != "inner":
		return _fail("continuation_inner=%s" % [inner_continuation])
	if str(outer_continuation.get("continuation_type", "")) != "outer" or str((outer_continuation.get("context", {}) as Dictionary).get("step", "")) != "outer" or continuation_queue.has_pending():
		return _fail("continuation_outer=%s" % [outer_continuation])
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
	# 重复弃牌请求的信号计数；同区域同持有者移动被拒绝后不应再通知任何表现层订阅者。
	var redundant_move_signal_count: Array[int] = [0]
	movement.card_moved.connect(func(_move_data: Dictionary, _card_data: Dictionary) -> void: redundant_move_signal_count[0] += 1)
	# 重复 discard_pile -> discard_pile 请求；它不能改变历史、区域或动画增量数量。
	if movement.move_card(card, "discard_pile", -1, "duplicate_discard", 2) != null or game_state.card_move_history.size() != 3 or redundant_move_signal_count[0] != 0:
		return _fail("duplicate_discard_move history=%d signals=%d" % [game_state.card_move_history.size(), redundant_move_signal_count[0]])
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
