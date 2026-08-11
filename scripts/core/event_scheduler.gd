class_name EventScheduler
extends Node

## GameEvent 主循环。它只负责事件栈、子事件、after 队列、暂停恢复和选择结果传递，不执行具体卡牌效果。

## 已结束事件摘要热索引容量；4096项覆盖近期父子关联与规则查询，旧摘要仍可从完整事件历史按需恢复。
const FINALIZED_EVENT_SNAPSHOT_CACHE_CAPACITY: int = 4096

## 单次 drain 最多执行的调度操作数；默认256兼顾同步小事件的即时完成与复杂事件树的分帧让步，可在检查器中调整但通常无需运行时修改。
@export_range(16, 4096, 16) var max_operations_per_drain: int = 256

## 同一事件步骤在没有子事件、暂停或游标变化时允许连续重跑的最大次数；默认2048远高于合法目标遍历规模，用于熔断扩展内容的无等待死循环。
@export_range(32, 65536, 32) var max_repeated_step_executions: int = 2048

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

## 事件运行时检测到无等待死循环时发送；参数包含事件摘要、稳定原因与重复次数，控制器可记录日志但不得重新执行故障步骤。
signal event_faulted(fault_data: Dictionary)

## 下一条事件稳定 ID；从1开始，避免0与未登记值混淆。
var _next_event_id: int = 1

## 下一条选择请求稳定 ID；事件与请求分别编号，便于网络日志定位。
var _next_request_id: int = 1

## 尚未结束的完整事件对象索引；只有调度器内部持有可变引用，外部使用get_event_snapshot查询活动或归档摘要。
var _events: Dictionary = {}

## 已结束事件ID到最终只读摘要的轻量索引；摘要与完成历史共享字典引用，不保留Callable、运行时上下文对象或完整GameEvent实例。
## 该索引只保存最近4096项；完整历史仍永久保留全部摘要，冷事件查询通过低频回退扫描恢复。
var _finalized_event_snapshots: Dictionary = {}

## 已结束事件热索引的固定容量环形ID槽位；填满后覆盖最旧ID，避免数组头部删除产生整体搬移。
var _finalized_event_snapshot_id_ring: Array[int] = []

## 下一次覆盖的已结束事件环形槽位；范围0至4095，重置调度器时归零。
var _finalized_event_snapshot_id_ring_cursor: int = 0

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

## 是否已经登记下一空闲帧继续排空；达到单次预算时为true，暂停、终局或显式排空都会使旧回调安全失效。
var _deferred_drain_pending: bool = false

## 延迟排空回调的单调令牌；每次登记或失效都会递增，旧帧回调不能接管较新的事件树状态。
var _deferred_drain_token: int = 0

## 最近一次无等待重跑的事件ID；-1表示当前没有连续重复步骤，事件或步骤变化时立即重置。
var _repeated_step_event_id: int = -1

## 最近一次无等待重跑的步骤下标；与事件ID共同组成熔断键，默认-1表示未记录。
var _repeated_step_index: int = -1

## 当前熔断键已经连续执行的次数；只有步骤游标不变且没有子事件或暂停时累加。
var _repeated_step_execution_count: int = 0

## 最近一次运行时故障的可序列化摘要；空字典表示本局尚未触发熔断，只供诊断与测试读取。
var _last_fault: Dictionary = {}

## 是否要求下一轮排空时停止；对局结束会设置该标志并中断未完成事件。
var _stop_requested: bool = false

## 当前事件历史序号；每一条开始、步骤、完成记录都使用单调序号。
var _history_sequence: int = 0

## 根事件生命周期暂停 token；大于0时保持长生命周期 phaseLoop 根事件，直到对局结束或显式 release_root。
## 兼容说明：长期根事件现由 GameEvent.held_open 表达且不会阻塞子事件，该字段只保留旧快照与调试读取边界。
var _root_lifecycle_token: int = -1


## 创建事件并关联parent_id；活动父事件接收next/after队列，归档父事件仅保留语义关系，返回对象供调用方补充上下文。
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
			# 已归档父事件仍可作为外部选择或迁移记录的语义父级；它不再拥有待执行队列，子事件由调用方独立完成。
			if not _has_finalized_event_snapshot(parent_id):
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


## 在单次操作预算内排空事件栈；全部结束、存在暂停 token 或遇到对局终止时立即停止，达到预算则延后一帧继续。
## 小型同步事件通常在一次调用内完成；复杂事件树主动把执行权还给主循环，使输入、网络和停滞看门狗始终有运行机会。
func drain() -> void:
	if _draining:
		return
	# 显式排空接管当前工作；先让已经排队的旧帧回调失效，避免同一批事件被重复驱动。
	_invalidate_deferred_drain()
	_draining = true
	# 本次已执行操作数；每次处理一个栈状态或事件步骤计1次，达到配置上限后让步到下一空闲帧。
	var operation_count: int = 0
	# 本次操作预算；运行时脚本异常写入0或负数时仍至少执行1次，保证调度器可以自恢复。
	var operation_budget: int = maxi(max_operations_per_drain, 1)
	while not _event_stack.is_empty() and not _stop_requested and operation_count < operation_budget:
		# 当前事件 ID；栈末尾永远是唯一允许执行内容的事件。
		var current_event_id: int = _event_stack.back()
		var event: GameEvent = _events.get(current_event_id) as GameEvent
		if event == null:
			_event_stack.pop_back()
			operation_count += 1
			continue
		if pause_registry.has_active_for_stack(_event_stack):
			event.status = GameEvent.Status.PAUSED
			break
		# 长期根事件没有待执行子事件时保持在栈底等待；该状态不是暂停，因此后续新建子事件仍可正常排空。
		if event.held_open and event.next_event_ids.is_empty() and event.after_event_ids.is_empty() and event.step >= event.content_steps.size():
			event.status = GameEvent.Status.WAITING_CHILDREN
			break
		_process_event(event)
		operation_count += 1
	_draining = false
	# 仍有可立即执行内容时只登记一次空闲帧续跑；暂停事件和空闲长期根不会制造无意义回调。
	if _has_immediately_executable_work():
		_schedule_deferred_drain()
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
			# 无等待地停留在同一步会在旧同步循环中永久占住主线程；累计到上限后只中断当前故障事件，让父事件继续正常收尾。
			_update_repeated_step_guard(event, executed_step)
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


## 更新同一步无等待重跑计数；合法的子事件、选择暂停、终态或游标前进都会清零，只有真正的同步自旋才会触发熔断。
func _update_repeated_step_guard(event: GameEvent, executed_step: int) -> void:
	if event == null:
		_reset_repeated_step_guard()
		return
	# 当前步骤是否在没有任何外部等待点的情况下再次指向自身；这是可形成单帧死循环的唯一计数条件。
	var repeats_without_wait: bool = not event.body_finished \
		and event.step == executed_step \
		and event.next_event_ids.is_empty() \
		and not pause_registry.has_active_for_event(event.event_id)
	if not repeats_without_wait:
		_reset_repeated_step_guard()
		return
	if _repeated_step_event_id == event.event_id and _repeated_step_index == executed_step:
		_repeated_step_execution_count += 1
	else:
		_repeated_step_event_id = event.event_id
		_repeated_step_index = executed_step
		_repeated_step_execution_count = 1
	if _repeated_step_execution_count <= maxi(max_repeated_step_executions, 1):
		return
	# 故障摘要；先写入事件结果并终止主体，再记录独立fault历史，保证回放和诊断都能定位具体事件与步骤。
	var fault_reason: String = "runaway_step"
	event.result["runtime_fault"] = {
		"reason": fault_reason,
		"step": executed_step,
		"repeat_count": _repeated_step_execution_count,
	}
	event.abort(fault_reason)
	_last_fault = {
		"reason": fault_reason,
		"event_id": event.event_id,
		"event_name": event.name,
		"step": executed_step,
		"repeat_count": _repeated_step_execution_count,
		"event": event.to_dict(),
	}
	_record_history("fault", event, {"fault":_last_fault.duplicate(true)})
	event_faulted.emit(_last_fault.duplicate(true))
	_reset_repeated_step_guard()


## 清空同步自旋熔断键；下一次执行从新的事件步骤重新计数。
func _reset_repeated_step_guard() -> void:
	_repeated_step_event_id = -1
	_repeated_step_index = -1
	_repeated_step_execution_count = 0


## 判断当前栈是否仍有无需等待即可推进的工作；暂停 token、终局停止和空闲长期根都返回false。
func _has_immediately_executable_work() -> bool:
	if _stop_requested or _event_stack.is_empty() or pause_registry.has_active_for_stack(_event_stack):
		return false
	# 当前栈顶事件；缺失对象仍需下一帧清理，因此视为可执行工作。
	var event: GameEvent = _events.get(_event_stack.back()) as GameEvent
	if event == null:
		return true
	# 长期根没有子事件、after或剩余内容时处于稳定空闲，不需要持续空转。
	return not (event.held_open and event.next_event_ids.is_empty() and event.after_event_ids.is_empty() and event.step >= event.content_steps.size())


## 达到本轮预算后登记唯一空闲帧续跑；令牌确保显式排空、重置或终局能让旧回调自然失效。
func _schedule_deferred_drain() -> void:
	if _deferred_drain_pending:
		return
	_deferred_drain_pending = true
	_deferred_drain_token += 1
	# 当前续跑令牌；绑定到延迟回调后不再修改，后续显式drain会递增全局令牌使其失效。
	var continuation_token: int = _deferred_drain_token
	call_deferred("_continue_deferred_drain", continuation_token)


## 执行仍为最新版本的空闲帧续跑；过期回调不读取或修改事件树。
func _continue_deferred_drain(continuation_token: int) -> void:
	if not _deferred_drain_pending or continuation_token != _deferred_drain_token:
		return
	_deferred_drain_pending = false
	drain()


## 使当前延迟排空登记失效；显式恢复、终局和重置均通过此入口避免旧回调重入。
func _invalidate_deferred_drain() -> void:
	if _deferred_drain_pending:
		_deferred_drain_token += 1
	_deferred_drain_pending = false


## 完成栈顶事件并把结果深拷贝回父事件；只在 after 队列已经清空时调用。
func _finalize_event(event: GameEvent) -> void:
	if event.finalized:
		return
	event.finalized = true
	# 完成历史记录；其中的event摘要同时作为后续按ID查询的轻量归档，避免再复制一份相同字典。
	var final_record: Dictionary = _record_history("finish", event)
	# 最终事件摘要；信号仍发送独立副本，订阅者无法反向修改历史或归档。
	var final_event_snapshot: Dictionary = final_record.get("event", {}) as Dictionary
	_cache_finalized_event_snapshot(event.event_id, final_event_snapshot)
	event_finished.emit(final_event_snapshot.duplicate(true))
	if not _event_stack.is_empty() and _event_stack.back() == event.event_id:
		_event_stack.pop_back()
	if event.parent_id >= 0:
		# 父事件对象；子事件结果通过标准字段复制，避免暴露子对象引用。
		var parent: GameEvent = _events.get(event.parent_id) as GameEvent
		if parent != null:
			parent.result = event.result.duplicate(true)
			if parent.status == GameEvent.Status.WAITING_CHILDREN:
				parent.status = GameEvent.Status.RUNNING
	# 已完成事件的可调用步骤和可变上下文不再参与任何调度；归档摘要足以支持回放历史与get_event_snapshot查询。
	_events.erase(event.event_id)


## 创建并登记暂停 token；owner_event_id 默认使用当前事件，外部系统可传 -1 创建全局暂停。
func pause(channel: String, reason: String, owner_event_id: int = -1) -> int:
	var resolved_owner: int = owner_event_id
	if resolved_owner < 0 and not _event_stack.is_empty():
		resolved_owner = int(_event_stack.back())
	return pause_registry.acquire(channel, resolved_owner, reason)


## 创建阻塞完整事件栈的全局暂停令牌；规则过渡可冻结事件推进而不暂停场景树、动画或界面输入。
func pause_global(channel: String, reason: String) -> int:
	return pause_registry.acquire(channel, -1, reason)


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
	_invalidate_deferred_drain()
	_reset_repeated_step_guard()
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
	# 同步记录事件不会进入父事件待调度队列；parent_id只保存事件树关系，避免长期根事件积累大量已经完成的空子事件ID。
	var event: GameEvent = create_event(event_name, event_type, [], event_context)
	event.parent_id = parent_id
	event.result = result.duplicate(true)
	event.finish()
	event.finalized = true
	# 记录历史中的最终摘要同时进入轻量索引，随后立即释放完整GameEvent实例。
	var record: Dictionary = _record_history("record", event)
	_cache_finalized_event_snapshot(event.event_id, record.get("event", {}) as Dictionary)
	_events.erase(event.event_id)
	return event.event_id


## 把已结束事件摘要写入固定容量热索引；摘要字典与完整历史共享只读引用，不再为索引额外深拷贝。
func _cache_finalized_event_snapshot(event_id: int, event_snapshot: Dictionary) -> void:
	if _finalized_event_snapshots.has(event_id):
		_finalized_event_snapshots[event_id] = event_snapshot
		return
	_finalized_event_snapshots[event_id] = event_snapshot
	if _finalized_event_snapshot_id_ring.size() < FINALIZED_EVENT_SNAPSHOT_CACHE_CAPACITY:
		_finalized_event_snapshot_id_ring.append(event_id)
		return
	# 被覆盖的最旧事件ID；摘要仍存在于完整历史，仅从常量时间热索引中释放。
	var evicted_event_id: int = _finalized_event_snapshot_id_ring[_finalized_event_snapshot_id_ring_cursor]
	_finalized_event_snapshots.erase(evicted_event_id)
	_finalized_event_snapshot_id_ring[_finalized_event_snapshot_id_ring_cursor] = event_id
	_finalized_event_snapshot_id_ring_cursor = (_finalized_event_snapshot_id_ring_cursor + 1) % FINALIZED_EVENT_SNAPSHOT_CACHE_CAPACITY


## 在完整历史中逆序查找已结束事件摘要；仅供超过热索引窗口的调试、回放或远古父事件查询。
func _find_finalized_event_snapshot_in_history(event_id: int) -> Dictionary:
	# 逆序历史下标；最新终态最先命中，范围从最后一项递减至0且空历史不会进入循环。
	for history_index: int in range(_event_history.size() - 1, -1, -1):
		# 当前历史记录；步骤与开始记录不是最终摘要，跳过可减少无意义字典读取。
		var history_record: Dictionary = _event_history[history_index] as Dictionary
		# 当前历史类型；只有同步记录和正常最终完成记录能作为归档终态。
		var history_kind: String = str(history_record.get("kind", ""))
		if history_kind != "record" and history_kind != "finish":
			continue
		# 当前历史携带的事件摘要；ID匹配时直接返回内部只读引用，由公开查询接口负责复制隔离。
		var history_event_snapshot: Dictionary = history_record.get("event", {}) as Dictionary
		if int(history_event_snapshot.get("event_id", -1)) == event_id:
			return history_event_snapshot
	return {}


## 判断已结束事件是否仍可查询；近期事件常量时间命中，超出窗口的低频父级校验回退到完整历史。
func _has_finalized_event_snapshot(event_id: int) -> bool:
	if _finalized_event_snapshots.has(event_id):
		return true
	# 冷历史查询结果；确认存在后提升回热索引，连续挂接同一旧父事件时只扫描一次完整历史。
	var recovered_snapshot: Dictionary = _find_finalized_event_snapshot_in_history(event_id)
	if recovered_snapshot.is_empty():
		return false
	_cache_finalized_event_snapshot(event_id, recovered_snapshot)
	return true


## 返回当前事件 ID；无运行中事件时为 -1，规则服务不得自行修改该值。
func get_current_event_id() -> int:
	return -1 if _event_stack.is_empty() else int(_event_stack.back())


## 返回当前可变事件仅供调度器内部和调试器使用；普通规则模块应读取 get_event_snapshot。
func get_current_event() -> GameEvent:
	return _events.get(get_current_event_id()) as GameEvent


## 返回事件摘要快照；未知 ID 返回空字典，避免外部取得可变 GameEvent 引用。
func get_event_snapshot(event_id: int) -> Dictionary:
	var event: GameEvent = _events.get(event_id) as GameEvent
	if event != null:
		return event.to_dict()
	# 已结束事件只保留不含Callable的最终摘要；查询继续返回独立副本，保持原公开接口的隔离契约。
	var finalized_snapshot: Dictionary = _finalized_event_snapshots.get(event_id, {}) as Dictionary
	if finalized_snapshot.is_empty():
		finalized_snapshot = _find_finalized_event_snapshot_in_history(event_id)
		if not finalized_snapshot.is_empty():
			# 冷摘要提升；后续对同一事件的规则、调试或回放查询恢复为常量时间，同时热索引仍保持固定容量。
			_cache_finalized_event_snapshot(event_id, finalized_snapshot)
	return finalized_snapshot.duplicate(true) if not finalized_snapshot.is_empty() else {}


## 返回仍持有完整GameEvent对象的数量；正式长局应只包含根事件与当前未完成事件树，供性能诊断与回归测试使用。
func get_live_event_count() -> int:
	return _events.size()


## 返回是否已经安排下一空闲帧继续排空；诊断层可据此区分“主动分帧”与真正没有推进来源的停滞。
func has_pending_drain_continuation() -> bool:
	return _deferred_drain_pending


## 返回最近一次运行时熔断摘要的深拷贝；调用方只能观察，不能修改调度器保存的故障记录。
func get_last_fault() -> Dictionary:
	return _last_fault.duplicate(true)


## 返回近期已结束事件热索引条目数；用于性能诊断，完整可查询事件数量仍由事件历史决定。
func get_finalized_event_snapshot_cache_count() -> int:
	return _finalized_event_snapshots.size()


## 返回全部事件历史深拷贝；该日志不依赖场景节点，可单独用于回放和无头测试。
func get_event_history() -> Array[Dictionary]:
	return _event_history.duplicate(true)


## 返回当前事件历史条目数；状态广播用它做常量时间一致性检查，避免反复深拷贝完整回放记录。
func get_event_history_count() -> int:
	return _event_history.size()


## 返回最新一条事件历史深拷贝；状态层可增量同步，避免每个触发时机重复复制完整日志。
func get_latest_history_record() -> Dictionary:
	return {} if _event_history.is_empty() else (_event_history.back() as Dictionary).duplicate(true)


## 把最新一条不可变历史记录共享追加到指定状态数组；仅供权威状态同步使用，调用方不得修改条目字典。
func append_latest_history_reference_to(target_history: Array[Dictionary]) -> bool:
	if _event_history.is_empty():
		return false
	# 最新不可变记录；写入历史后调度器只追加新条目，不再修改已有字典。
	var latest_record: Dictionary = _event_history.back() as Dictionary
	# 最新序号；目标已经拥有同一条记录时保持幂等，不重复占用数组条目。
	var latest_sequence: int = int(latest_record.get("sequence", -1))
	if not target_history.is_empty() and int((target_history.back() as Dictionary).get("sequence", -2)) == latest_sequence:
		return false
	target_history.append(latest_record)
	return true


## 返回共享不可变条目的独立数组；用于计数失配后的全量校准，避免把整份长局回放再深复制一遍。
func get_event_history_reference_copy() -> Array[Dictionary]:
	# 浅层数组副本；调用方可追加或清空自己的数组，内部字典作为归档记录必须保持只读。
	var result: Array[Dictionary] = []
	result.assign(_event_history)
	return result


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
	_invalidate_deferred_drain()
	_reset_repeated_step_guard()
	_next_event_id = 1
	_next_request_id = 1
	_events.clear()
	_finalized_event_snapshots.clear()
	_finalized_event_snapshot_id_ring.clear()
	_finalized_event_snapshot_id_ring_cursor = 0
	_event_stack.clear()
	_choice_requests.clear()
	_event_history.clear()
	root_event_id = -1
	_root_lifecycle_token = -1
	_stop_requested = false
	_history_sequence = 0
	_last_fault.clear()
	pause_registry.reset()


## 写入并返回一条稳定事件历史记录；extra只允许基础类型，调用方不应传递节点或Callable。
func _record_history(kind: String, event: GameEvent, extra: Dictionary = {}) -> Dictionary:
	_history_sequence += 1
	var record: Dictionary = {
		"sequence": _history_sequence,
		"kind": kind,
		"event": event.to_dict(),
	}
	if not extra.is_empty():
		record.merge(extra, true)
	_event_history.append(record)
	return record
