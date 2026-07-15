class_name GameEvent
extends RefCounted

## 可暂停、可嵌套的规则事件。事件只保存状态与内容步骤，队列调度由 EventScheduler 统一负责。

## 事件生命周期状态；终止态分开保存正常完成、取消、中立化与对局级中断语义。
enum Status {
	CREATED,
	RUNNING,
	WAITING_CHILDREN,
	PAUSED,
	FINISHED,
	CANCELLED,
	NEUTRALIZED,
	ABORTED,
}

## 事件在当前对局中的稳定 ID；由 EventScheduler 单调递增分配，默认 -1 表示尚未登记。
var event_id: int = -1

## 父事件稳定 ID；根事件使用 -1，运行时禁止外部直接改写父子关系。
var parent_id: int = -1

## 事件稳定名称；使用 phaseUse、useCard、damage 等可长期用于触发器和回放的名称。
var name: String = ""

## 事件类别；用于调试器区分模式、阶段、卡牌、选择、移动、伤害与系统事件。
var event_type: String = "rule"

## 当前内容步骤游标；默认从 0 开始，只能通过调度器推进或 goto/redo 修改下一步位置。
var step: int = 0

## 当前生命周期状态；新事件默认为 CREATED，由 EventScheduler 启动后变为 RUNNING。
var status: Status = Status.CREATED

## 子事件或玩家选择写回的结果；始终使用可序列化字典，便于网络传输和确定性回放。
var result: Dictionary = {}

## 事件创建时的只读语义上下文副本；规则步骤可以修改自身副本，但不会反向污染调用方字典。
var context: Dictionary = {}

## 当前事件主体期间依次执行的子事件 ID；父事件必须等待该队列完全结束后才能继续步骤。
var next_event_ids: Array[int] = []

## 当前事件主体终止后依次执行的后置事件 ID；正常完成、取消和中立化都保留该收尾队列。
var after_event_ids: Array[int] = []

## 事件内容步骤数组；每项 Callable 接收当前 GameEvent 与 EventScheduler 两个参数。
var content_steps: Array[Callable] = []

## 事件涉及的主要行动角色 ID；无主要角色时为 -1。
var player_id: int = -1

## 事件来源角色 ID；无来源伤害、系统事件或摸牌事件使用 -1。
var source_id: int = -1

## 事件当前主要目标角色 ID；多目标事件仍可在 target_ids 中保留完整目标顺序。
var target_id: int = -1

## 事件全部目标角色 ID；数组顺序必须是权威行动顺序，默认没有目标。
var target_ids: Array[int] = []

## 事件逻辑牌描述；包含虚拟牌 ID、牌名、属性与实体材料牌 UID，不保存 CardInstance 引用。
var card: Dictionary = {}

## 事件实体材料牌 UID；真实牌、视为牌与多材料牌均通过稳定 UID 关联移动历史。
var card_uids: Array[int] = []

## 事件终止原因；正常结束可为空，取消、中立化和中断必须保存可回放的稳定原因。
var termination_reason: String = ""

## 是否允许死亡或离场角色继续执行该事件；默认 false，特殊死亡触发可显式开启。
var allow_out_of_game: bool = false

## 事件主体是否已结束；与 after 队列是否完成分离，确保 finish 后仍能稳定执行收尾事件。
var body_finished: bool = false

## 是否已经把终态写入事件历史；仅供 EventScheduler 防止重复完成和重复复制结果。
var finalized: bool = false

## 下一次步骤推进的显式目标；-1 表示按正常顺序增加，goto 会覆盖该值。
var _next_step_override: int = -1

## 是否要求重新执行当前步骤；redo 只影响下一次调度，不会递归调用当前 Callable。
var _redo_requested: bool = false


## 创建一个未登记事件；调度器登记时再写入稳定 ID 与父事件 ID。
func _init(event_name: String = "", steps: Array[Callable] = [], event_context: Dictionary = {}) -> void:
	name = event_name
	content_steps = steps.duplicate()
	context = event_context.duplicate(true)


## 正常结束事件主体；仍允许调度器执行已登记的 after 队列。
func finish(reason: String = "") -> void:
	if is_terminal():
		return
	status = Status.FINISHED
	body_finished = true
	termination_reason = reason


## 取消事件主体；清空尚未开始的普通子事件并保留 after 收尾队列和取消原因。
func cancel(reason: String = "cancelled") -> void:
	if is_terminal():
		return
	status = Status.CANCELLED
	body_finished = true
	termination_reason = reason
	next_event_ids.clear()


## 中立化事件效果；事件发生事实和 after 收尾仍会进入历史，供无懈链与回放区分取消。
func neutralize(reason: String = "neutralized") -> void:
	if is_terminal():
		return
	status = Status.NEUTRALIZED
	body_finished = true
	termination_reason = reason
	next_event_ids.clear()


## 解除尚未最终入栈的中立化状态；主要供无懈可击的偶数次翻转恢复原效果。
func unneutralize() -> bool:
	if status != Status.NEUTRALIZED or finalized:
		return false
	status = Status.RUNNING
	body_finished = false
	termination_reason = ""
	return true


## 因对局结束、运行时重置或不可恢复错误中断事件；中断态不会继续普通子事件或 after 队列。
func abort(reason: String = "aborted") -> void:
	if finalized:
		return
	status = Status.ABORTED
	body_finished = true
	termination_reason = reason
	next_event_ids.clear()
	after_event_ids.clear()


## 把下一次执行位置改为指定步骤；负数会被限制为 0，超出内容长度会自然结束事件主体。
func goto(next_step: int) -> void:
	_next_step_override = maxi(next_step, 0)
	_redo_requested = false


## 要求调度器下一次重新执行当前步骤；不会立即递归，避免规则步骤形成不可控调用栈。
func redo() -> void:
	_redo_requested = true
	_next_step_override = -1


## 将子事件 ID 插入当前主体队列末尾；EventScheduler 会在登记关系前校验事件归属。
func insert(child_event_id: int) -> void:
	if child_event_id >= 0:
		next_event_ids.append(child_event_id)


## 将后置事件 ID 插入收尾队列末尾；主体进入终态后才会开始执行该事件。
func insert_after(after_event_id: int) -> void:
	if after_event_id >= 0:
		after_event_ids.append(after_event_id)


## 在当前事件下创建并插入一个触发子事件；规则内容通过该方法保持父子关系，不直接替换全局 current_event。
func trigger(scheduler: EventScheduler, event_name: String, event_type: String = "trigger", steps: Array[Callable] = [], event_context: Dictionary = {}) -> GameEvent:
	if scheduler == null or event_id < 0:
		return null
	return scheduler.create_child(event_id, event_name, event_type, steps, event_context)


## 返回事件是否处于任意终止态；终态仍可能等待 after 队列完成后才 finalized。
func is_terminal() -> bool:
	return status in [Status.FINISHED, Status.CANCELLED, Status.NEUTRALIZED, Status.ABORTED]


## 返回事件是否正在等待外部恢复；用于 UI、网络和调试快照显示统一暂停状态。
func is_paused() -> bool:
	return status == Status.PAUSED


## 应用一次内容步骤结束后的游标变化；该方法仅由 EventScheduler 调用。
func consume_step_transition(executed_step: int) -> void:
	if _redo_requested:
		step = executed_step
		_redo_requested = false
		return
	if _next_step_override >= 0:
		step = _next_step_override
		_next_step_override = -1
		return
	step = executed_step + 1


## 生成不包含 Callable 和可变对象引用的事件摘要；普通客户端可使用该结构展示当前事件。
func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"parent_id": parent_id,
		"name": name,
		"event_type": event_type,
		"step": step,
		"status": Status.keys()[status].to_lower(),
		"result": result.duplicate(true),
		"context": context.duplicate(true),
		"next_event_ids": next_event_ids.duplicate(),
		"after_event_ids": after_event_ids.duplicate(),
		"player_id": player_id,
		"source_id": source_id,
		"target_id": target_id,
		"target_ids": target_ids.duplicate(),
		"card": card.duplicate(true),
		"card_uids": card_uids.duplicate(),
		"termination_reason": termination_reason,
		"body_finished": body_finished,
		"finalized": finalized,
	}
