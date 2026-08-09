class_name RuleEvent
extends RefCounted

## 可拦截的规则事件。技能、装备与模式规则通过事件订阅扩展结算，而无需反向依赖对局控制器。

## 同步规则事件的三态终止语义；与 GameEvent 保持一致，供现有总线和新调度器共享回放文本。
enum Status {
	RUNNING,
	FINISHED,
	CANCELLED,
	NEUTRALIZED,
}

## 规则事件稳定 ID；由事件运行时写入，旧的直接 dispatch 调用保持默认 -1。
var event_id: int = -1

## 父规则事件稳定 ID；嵌套触发没有父事件时使用 -1。
var parent_id: int = -1

## 事件名称；建议采用 phase_before、card_targeted、damage_before 等稳定语义。
var name: String = ""

## 事件主要执行者或承受者玩家 ID；player 角色触发器只在持有者与该值一致时执行，无对应角色时为-1。
var player_id: int = -1

## 事件发起者玩家 ID；无来源事件使用 -1。
var source_id: int = -1

## 事件主要目标玩家 ID；无单一目标时使用 -1，其他目标可放入 data。
var target_id: int = -1

## 事件上下文数据；允许处理器读取或修改伤害值、牌 UID 与标记。
var data: Dictionary = {}

## 事件是否被取消；规则层应在关键步骤读取该值并终止对应效果。
var cancelled: bool = false

## 当前终止状态；cancelled 字段只作为历史兼容别名，不承载中立化语义。
var status: Status = Status.RUNNING

## 事件是否已中立化；效果无效但事件事实和后置监听仍然可以被记录。
var neutralized: bool = false

## 事件结果；触发器或子选择可写入结构化数据供父事件读取。
var result: Dictionary = {}

## 终止原因；用于回放区分规则取消、无懈中立化和系统错误。
var termination_reason: String = ""


## 创建规则事件并复制上下文，避免外部字典在事件结束后继续影响结果。
func _init(event_name: String = "", source: int = -1, target: int = -1, context: Dictionary = {}, player: int = -1) -> void:
	name = event_name
	player_id = player if player >= 0 else source
	source_id = source
	target_id = target
	data = context.duplicate(true)


## 将事件标记为取消；高优先级处理器或流程边界可阻止后续默认结算，并写入稳定原因供诊断与回放使用。
func cancel(reason: String = "cancelled") -> void:
	cancelled = true
	status = Status.CANCELLED
	termination_reason = reason


## 正常结束事件；不改变取消标记，兼容旧回调只读取 cancelled 的行为。
func finish() -> void:
	if status == Status.RUNNING:
		status = Status.FINISHED


## 中立化事件效果；不把它误报为 cancelled，供无懈可击和技能回放读取。
func neutralize(reason: String = "neutralized") -> void:
	neutralized = true
	status = Status.NEUTRALIZED
	termination_reason = reason


## 解除仍未完成的中立化；用于交替无懈链恢复原锦囊效果。
func unneutralize() -> bool:
	if status != Status.NEUTRALIZED:
		return false
	neutralized = false
	status = Status.RUNNING
	termination_reason = ""
	return true


## 返回事件是否已经进入任一终态。
func is_terminal() -> bool:
	return status != Status.RUNNING


## 生成同步事件摘要；只导出基础类型，避免技能回调把节点引用泄露给网络或回放。
func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"parent_id": parent_id,
		"name": name,
		"player_id": player_id,
		"source_id": source_id,
		"target_id": target_id,
		"data": data.duplicate(true),
		"cancelled": cancelled,
		"neutralized": neutralized,
		"status": Status.keys()[status].to_lower(),
		"result": result.duplicate(true),
		"termination_reason": termination_reason,
	}
