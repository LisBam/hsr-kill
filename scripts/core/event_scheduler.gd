class_name EventScheduler
extends Node

## GameEvent 主循环。它只负责事件栈、子事件、after 队列、暂停恢复和选择结果传递，不执行具体卡牌效果。

## 事件开始信号；参数是只读摘要，UI、调试器和回放可以订阅而不会获得可变事件引用。
signal event_started(event_data: Dictionary)

## 事件步骤执行信号；每完成一个内容步骤发送一次，便于定位选择前后的步骤游标。
signal event_step_executed(event_data: Dictionary)

## 事件完成信号；终态仍区分 finished、cancelled、neutralized 与 aborted。
signal event_finished(event_data: Dictionary)

## 统一选择请求信号；本地 UI、AI 和网络适配层只监听该请求并提交 ChoiceResponse。
signal choice_requested(request_data: Dictionary)

## 选择结果写回信号；响应已经通过权威校验并恢复事件后才发送。
signal choice_resolved(request_data: Dictionary, response_data: Dictionary)

## 运行时进入无可执行事件且没有暂停 token 时发送；对局循环可用它安排下一阶段。
signal scheduler_idle()

## 因对局结束或重置中断事件时发送；所有仍等待的请求会先被标记为 aborted。
signal scheduler_aborted(reason: String)

## 下一条事件稳定 ID；从1开始，避免0与未登记值混淆。
var _next_event_id: int = 1

## 下一条选择请求稳定 ID；事件与请求分别编号，便于网络日志定位。
var _next_request_id: int = 1

## 全部事件对象索引；只有调度器内部持有可变引用，外部使用 get_event_snapshot 查询。
var _events: Dictionary = {}

## 当前事件栈；数组末尾是正在执行的事件，父事件必须留在栈中等待子事件。
var _event_stack: Array[int] = []

## 当前根事件 ID；每局只能有一个根事件，重置时清空。
var root_event_id: int = -1

## 当前等待中的选择请求索引；请求完成或中断后立即移除，防止旧响应重复恢复。
var _choice_requests: Dictionary = {}

## 事件历史摘要；只保存可序列化结果，不保存 Callable 或节点引用。
var _event_history: Array[Dictionary] = []

## 多通道暂停 token 注册表；动画、网络、选择和终局中断相互独立。
var pause_registry: PauseRegistry = PauseRegistry.new()

## 当前是否正在排空事件栈；防止内容步骤内重复调用 drain 造成递归推进。
var _draining: bool = false

## 是否要求下一轮排空时停止；对局结束会设置该标志并中断未完成事件。
var _stop_requested: bool = false

## 当前事件历史序号；每一条开始、步骤、完成记录都使用单调序号。
var _history_sequence: int = 0

## 根事件生命周期暂停 token；大于0时保持长生命周期 phaseLoop 根事件，直到对局结束或显式 release_root。
## 兼容说明：长期根事件现由 GameEvent.held_open 表达且不会阻塞子事件，该字段只保留旧快照与调试读取边界。
var _root_lifecycle_token: int = -1


## 创建事件并按 parent_id 放入 next 或 after 队列；返回事件对象供调用方补充上下文。
func create_event(event_name: String, event_type: String = "rule", steps: Array[Callable] = [], event_context: Dictionary = {}, parent_id: int = -1, queue: String = "next") -> GameEvent:
	# 新建事件对象；构造时不执行内容，只有 start 或 drain 才会推进。
	var event: GameEvent = GameEvent.new(event_name, steps, event_context)
	event.event_id = _next_event_id
	_next_event_id += 1
	event.parent_id = parent_id
	event.event_type = event_type
	_events[event.event_id] = event
	if parent_id >= 0:
		# 父事件对象；未知父事件表示调用顺序错误，事件不会静默脱离事件树。
		var parent: GameEvent = _events.get(parent_id) as GameEvent
		if parent == null:
			event.abort("missing_parent")
		else:
			if queue == "after":
				parent.insert_after(event.event_id)
			else:
				parent.insert(event.event_id)
	return event


## 创建并登记一个父事件的子事件；默认进入 next 队列，after 事件必须显式指定 queue=after。
func create_child(parent_id: int, event_name: String, event_type: String = "rule", steps: Array[Callable] = [], event_context: Dictionary = {}, queue: String = "next") -> GameEvent:
	return create_event(event_name, event_type, steps, event_context, parent_id, queue)


## 设置根事件并立即运行；根事件不能挂在其他事件下，重复 start 会返回 false。
func start(event_id: int) -> bool:
	if root_event_id >= 0 or not _events.has(event_id):
		return false
	var event: GameEvent = _events[event_id] as GameEvent
	if event.parent_id >= 0:
		return false
	root_event_id = event_id
	_event_stack.append(event_id)
	_stop_requested = false
	drain()
	return true


## 把一个已经登记的根事件压入空栈；用于在对局日志中建立新的事件树入口。
func push_root(event_id: int) -> bool:
	if root_event_id >= 0 or not _events.has(event_id):
		return false
	root_event_id = event_id
	_event_stack.append(event_id)
	return true


## 启动一个长期根事件并用独立生命周期 token 保持栈；子事件响应不会让空内容根事件提前完成。
## 当前实现使用 held_open 保持栈；保持开放只阻止根事件自动完成，不会像暂停 token 一样阻塞其子事件。
func begin_root(event_id: int, hold_open: bool = true) -> bool:
	if not push_root(event_id):
		return false
	var event: GameEvent = _events[event_id] as GameEvent
	event.status = GameEvent.Status.RUNNING
	event.held_open = hold_open
	_record_history("start", event)
	event_started.emit(event.to_dict())
	if hold_open:
		# 长期根事件当前没有待执行内容；等待状态仍允许 create_child 后由 drain 压入新的真实子树。
		event.status = GameEvent.Status.WAITING_CHILDREN
	else:
		drain()
	return true


## 释放长期根事件并允许它正常完成；身份模式通常只在明确终局前使用 abort_all，而不单独调用。
func release_root(reason: String = "root_complete") -> bool:
	if root_event_id < 0:
		return false
	# 当前根事件；只有尚未终止且确实保持开放的根事件可以释放。
	var root_event: GameEvent = _events.get(root_event_id) as GameEvent
	if root_event == null or root_event.finalized or not root_event.held_open:
		return false
	root_event.held_open = false
	root_event.status = GameEvent.Status.RUNNING
	root_event.termination_reason = reason
	drain()
	return true


## 排空事件栈直到全部结束、存在暂停 token 或遇到对局终止；内容步骤不会跨暂停推进。
func drain() -> void:
	if _draining:
		return
	_draining = true
	while not _event_stack.is_empty() and not _stop_requested:
		# 当前事件 ID；栈末尾永远是唯一允许执行内容的事件。
		var current_event_id: int = _event_stack.back()
		var event: GameEvent = _events.get(current_event_id) as GameEvent
		if event == null:
			_event_stack.pop_back()
			continue
		if pause_registry.has_active_for_stack(_event_stack):
			event.status = GameEvent.Status.PAUSED
			break
		# 长期根事件没有待执行子事件时保持在栈底等待；该状态不是暂停，因此后续新建子事件仍可正常排空。
		if event.held_open and event.next_event_ids.is_empty() and event.after_event_ids.is_empty() and event.step >= event.content_steps.size():
			event.status = GameEvent.Status.WAITING_CHILDREN
			break
		_process_event(event)
	_draining = false
	if _event_stack.is_empty() and not _stop_requested:
		scheduler_idle.emit()


## 单帧调度别名；外部主循环可以使用 tick，语义与 drain 相同且不会跨暂停推进事件。
func tick() -> void:
	drain()


## 执行栈顶事件的一小步；子事件、步骤和 after 队列的优先顺序固定在这里。
func _process_event(event: GameEvent) -> void:
	if event.status == GameEvent.Status.CREATED:
		event.status = GameEvent.Status.RUNNING
		_record_history("start", event)
		event_started.emit(event.to_dict())
	if pause_registry.has_active_for_stack(_event_stack):
		event.status = GameEvent.Status.PAUSED
		return
	# 主体期间插入的子事件优先于后续内容步骤。
	if not event.next_event_ids.is_empty():
		# 当前子事件 ID；弹出后压入栈顶，父事件保持 WAITING_CHILDREN 状态。
		var child_id: int = event.next_event_ids.pop_front()
		var child: GameEvent = _events.get(child_id) as GameEvent
		if child == null or child.finalized:
			return
		event.status = GameEvent.Status.WAITING_CHILDREN
		_event_stack.append(child_id)
		return
	# 主体未结束时执行一个步骤；超出长度会自动 finish。
	if not event.body_finished:
		if event.step >= event.content_steps.size():
			event.finish()
		else:
			# 当前步骤编号；调用结束后由事件处理 goto/redo/顺序推进。
			var executed_step: int = event.step
			var content: Callable = event.content_steps[executed_step]
			if content.is_valid():
				content.call(event, self)
			if event.status == GameEvent.Status.CREATED:
				event.status = GameEvent.Status.RUNNING
			if not event.body_finished:
				event.consume_step_transition(executed_step)
			_record_history("step", event)
			event_step_executed.emit(event.to_dict())
			return
	# 事件主体已终止，after 队列仍按声明顺序运行。
	if not event.after_event_ids.is_empty() and event.status != GameEvent.Status.ABORTED:
		# 当前后置事件 ID；父事件保持终态，子事件完成后才最终出栈。
		var after_id: int = event.after_event_ids.pop_front()
		var after_event: GameEvent = _events.get(after_id) as GameEvent
		if after_event == null or after_event.finalized:
			return
		_event_stack.append(after_id)
		return
	_finalize_event(event)


## 完成栈顶事件并把结果深拷贝回父事件；只在 after 队列已经清空时调用。
func _finalize_event(event: GameEvent) -> void:
	if event.finalized:
		return
	event.finalized = true
	_record_history("finish", event)
	event_finished.emit(event.to_dict())
	if not _event_stack.is_empty() and _event_stack.back() == event.event_id:
		_event_stack.pop_back()
	if event.parent_id >= 0:
		# 父事件对象；子事件结果通过标准字段复制，避免暴露子对象引用。
		var parent: GameEvent = _events.get(event.parent_id) as GameEvent
		if parent != null:
			parent.result = event.result.duplicate(true)
			if parent.status == GameEvent.Status.WAITING_CHILDREN:
				parent.status = GameEvent.Status.RUNNING


## 创建并登记暂停 token；owner_event_id 默认使用当前事件，外部系统可传 -1 创建全局暂停。
func pause(channel: String, reason: String, owner_event_id: int = -1) -> int:
	var resolved_owner: int = owner_event_id
	if resolved_owner < 0 and not _event_stack.is_empty():
		resolved_owner = int(_event_stack.back())
	return pause_registry.acquire(channel, resolved_owner, reason)


## 解决暂停 token 并尝试恢复事件；未解决的其他通道仍会继续阻塞事件栈。
func resume(token_id: int, resolution: String = "completed") -> bool:
	if not pause_registry.resolve(token_id, resolution):
		return false
	if not _event_stack.is_empty():
		var event: GameEvent = _events.get(_event_stack.back()) as GameEvent
		if event != null and event.status == GameEvent.Status.PAUSED and not pause_registry.has_active_for_stack(_event_stack):
			event.status = GameEvent.Status.RUNNING
	drain()
	return true


## 登记一个 ChoiceRequest 并暂停所属事件；请求信号发出后由外部提交 ChoiceResponse。
func request_choice(request: ChoiceRequest) -> ChoiceRequest:
	if request == null or request.event_id < 0 or not _events.has(request.event_id):
		return null
	if request.request_id < 0:
		request.request_id = _next_request_id
		_next_request_id += 1
	else:
		_next_request_id = maxi(_next_request_id, request.request_id + 1)
	if _choice_requests.has(request.request_id):
		return null
	# 所属事件；请求只能在未终止事件上创建，防止结束后的迟到 UI 请求。
	var event: GameEvent = _events[request.event_id] as GameEvent
	if event == null or event.finalized or event.is_terminal():
		return null
	if event.status == GameEvent.Status.CREATED:
		# 新建选择事件从请求登记时正式开始；即使随后立即被选择 token 暂停，历史仍保留完整 start -> choice_requested -> finish 链。
		event.status = GameEvent.Status.RUNNING
		_record_history("start", event)
		event_started.emit(event.to_dict())
	request.pause_token_id = pause("choice", "choice_request:%d" % request.request_id, request.event_id)
	event.status = GameEvent.Status.PAUSED
	_choice_requests[request.request_id] = request
	_record_history("choice_requested", event, {"request": request.to_dict()})
	choice_requested.emit(request.to_dict())
	return request


## 提交一个选择响应；请求、事件、玩家和候选必须全部匹配后才恢复事件。
## defer_drain 用于规则控制器先应用选择结果再继续父事件，默认 false 保持独立运行时调用的即时恢复语义。
func submit_choice(response: ChoiceResponse, defer_drain: bool = false) -> bool:
	if response == null or not _choice_requests.has(response.request_id):
		return false
	# 当前请求；只允许仍处于 PENDING 的对象接受响应。
	var request: ChoiceRequest = _choice_requests[response.request_id] as ChoiceRequest
	var validation_error: String = request.validate_response(response)
	if not validation_error.is_empty():
		return false
	var event: GameEvent = _events.get(request.event_id) as GameEvent
	if event == null or event.finalized or event.status == GameEvent.Status.ABORTED:
		return false
	request.resolve(response)
	event.result = {"choice_request": request.to_dict(), "choice_response": response.to_dict()}
	# 外部兼容选择事件没有进入调度栈，响应后立即终止；栈内选择事件必须恢复后续内容步骤。
	var scheduled_event: bool = _event_stack.has(event.event_id)
	if not scheduled_event:
		if response.confirmed:
			event.finish("choice_resolved")
		else:
			event.cancel("choice_cancelled")
	_choice_requests.erase(request.request_id)
	if defer_drain:
		# 延迟排空只解决本次选择 token；调用方完成权威效果恢复后必须显式调用 drain 或解决父事件 token。
		pause_registry.resolve(request.pause_token_id, "choice_resolved")
	else:
		resume(request.pause_token_id, "choice_resolved")
	if not scheduled_event and not event.finalized:
		_finalize_event(event)
	choice_resolved.emit(request.to_dict(), response.to_dict())
	return true


## 将超时托管结果写入标准请求；source=timeout 的响应与普通 AI 具有完全相同格式。
func timeout_choice(request_id: int, response: ChoiceResponse) -> bool:
	if not _choice_requests.has(request_id) or response == null:
		return false
	# 当前请求；先按普通候选校验，避免托管绕过权威规则。
	var request: ChoiceRequest = _choice_requests[request_id] as ChoiceRequest
	var validation_error: String = request.validate_response(response)
	if not validation_error.is_empty():
		return false
	response.source = "timeout"
	request.timeout(response)
	var event: GameEvent = _events.get(request.event_id) as GameEvent
	if event == null:
		return false
	event.result = {"choice_request": request.to_dict(), "choice_response": response.to_dict()}
	var scheduled_event: bool = _event_stack.has(event.event_id)
	if not scheduled_event:
		if response.confirmed:
			event.finish("choice_timeout_resolved")
		else:
			event.cancel("choice_timeout_cancelled")
	_choice_requests.erase(request_id)
	resume(request.pause_token_id, "choice_timeout")
	if not scheduled_event and not event.finalized:
		_finalize_event(event)
	choice_resolved.emit(request.to_dict(), response.to_dict())
	return true


## 中断一条无法继续提交的选择请求；只释放该请求持有的暂停令牌，不影响其他事件或并行响应。
## 本入口用于权威控制器检测到请求与事件状态已经不可恢复时的最终保护，正常取消仍必须提交标准ChoiceResponse。
func abort_choice(request_id: int, reason: String = "choice_unresolvable") -> bool:
	if not _choice_requests.has(request_id):
		return false
	# 当前请求；先标记ABORTED再移出索引，使任何迟到响应都无法恢复旧事件。
	var request: ChoiceRequest = _choice_requests[request_id] as ChoiceRequest
	request.abort(reason)
	_choice_requests.erase(request_id)
	# 请求所属事件；无法恢复的选择子事件必须中断，父事件才能在暂停令牌释放后继续收尾。
	var event: GameEvent = _events.get(request.event_id) as GameEvent
	if event != null and not event.finalized:
		event.abort(reason)
		event.result = {"choice_request":request.to_dict(), "abort_reason":reason}
		_record_history("abort", event, {"choice_request":request.to_dict()})
	# 请求自己的暂停令牌；其他玩法、网络或动画暂停仍会继续阻止事件栈推进。
	resume(request.pause_token_id, reason)
	if event != null and not event.finalized and not _event_stack.has(event.event_id):
		_finalize_event(event)
	return true


## 中断全部事件、选择和暂停 token；对局结束后旧响应永远不能恢复已经失效的事件。
func abort_all(reason: String = "game_over") -> void:
	_stop_requested = true
	for request_variant: Variant in _choice_requests.values():
		# 当前等待请求；终止原因写回请求历史后再从索引删除。
		var request: ChoiceRequest = request_variant as ChoiceRequest
		request.abort(reason)
	for event_variant: Variant in _events.values():
		# 当前事件；根和子事件都进入 ABORTED，已完成事件保持原终态。
		var event: GameEvent = event_variant as GameEvent
		if event != null and not event.finalized and not event.is_terminal():
			event.abort(reason)
			_record_history("abort", event)
	_choice_requests.clear()
	pause_registry.resolve_all(reason)
	scheduler_aborted.emit(reason)


## 创建一条无内容的完成事件作为外部规则调用的事件记录；可用于迁移期间保留父子与回放关联。
func record_event(event_name: String, event_type: String = "rule", event_context: Dictionary = {}, parent_id: int = -1, result: Dictionary = {}) -> int:
	var event: GameEvent = create_event(event_name, event_type, [], event_context, parent_id)
	event.result = result.duplicate(true)
	event.finish()
	event.finalized = true
	_record_history("record", event)
	return event.event_id


## 返回当前事件 ID；无运行中事件时为 -1，规则服务不得自行修改该值。
func get_current_event_id() -> int:
	return -1 if _event_stack.is_empty() else int(_event_stack.back())


## 返回当前可变事件仅供调度器内部和调试器使用；普通规则模块应读取 get_event_snapshot。
func get_current_event() -> GameEvent:
	return _events.get(get_current_event_id()) as GameEvent


## 返回事件摘要快照；未知 ID 返回空字典，避免外部取得可变 GameEvent 引用。
func get_event_snapshot(event_id: int) -> Dictionary:
	var event: GameEvent = _events.get(event_id) as GameEvent
	return {} if event == null else event.to_dict()


## 返回全部事件历史深拷贝；该日志不依赖场景节点，可单独用于回放和无头测试。
func get_event_history() -> Array[Dictionary]:
	return _event_history.duplicate(true)


## 返回当前事件历史条目数；状态广播用它做常量时间一致性检查，避免反复深拷贝完整回放记录。
func get_event_history_count() -> int:
	return _event_history.size()


## 返回最新一条事件历史深拷贝；状态层可增量同步，避免每个触发时机重复复制完整日志。
func get_latest_history_record() -> Dictionary:
	return {} if _event_history.is_empty() else (_event_history.back() as Dictionary).duplicate(true)


## 返回仍等待响应的请求快照；网络重连可据此恢复 UI，而不会恢复旧事件对象。
func get_pending_choice_requests() -> Array[Dictionary]:
	# 请求快照结果；按请求 ID 排序保证固定回放顺序。
	var result: Array[Dictionary] = []
	for request_variant: Variant in _choice_requests.values():
		result.append((request_variant as ChoiceRequest).to_dict())
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.get("request_id", 0)) < int(right.get("request_id", 0)))
	return result


## 重置运行时；旧事件、请求、暂停 token 和根入口全部失效，只能在新对局开始前调用。
func reset() -> void:
	if not _events.is_empty() or not _choice_requests.is_empty():
		abort_all("runtime_reset")
	_next_event_id = 1
	_next_request_id = 1
	_events.clear()
	_event_stack.clear()
	_choice_requests.clear()
	_event_history.clear()
	root_event_id = -1
	_root_lifecycle_token = -1
	_stop_requested = false
	_history_sequence = 0
	pause_registry.reset()


## 写入一条稳定事件历史记录；extra 只允许基础类型，调用方不应传递节点或 Callable。
func _record_history(kind: String, event: GameEvent, extra: Dictionary = {}) -> void:
	_history_sequence += 1
	var record: Dictionary = {
		"sequence": _history_sequence,
		"kind": kind,
		"event": event.to_dict(),
	}
	if not extra.is_empty():
		record.merge(extra, true)
	_event_history.append(record)
