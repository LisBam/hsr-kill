class_name RuleEvent
extends RefCounted

## 可拦截的规则事件。技能、装备与模式规则通过事件订阅扩展结算，而无需反向依赖对局控制器。

## 事件名称；建议采用 phase_before、card_targeted、damage_before 等稳定语义。
var name: String = ""

## 事件发起者玩家 ID；无来源事件使用 -1。
var source_id: int = -1

## 事件主要目标玩家 ID；无单一目标时使用 -1，其他目标可放入 data。
var target_id: int = -1

## 事件上下文数据；允许处理器读取或修改伤害值、牌 UID 与标记。
var data: Dictionary = {}

## 事件是否被取消；规则层应在关键步骤读取该值并终止对应效果。
var cancelled: bool = false


## 创建规则事件并复制上下文，避免外部字典在事件结束后继续影响结果。
func _init(event_name: String = "", source: int = -1, target: int = -1, context: Dictionary = {}) -> void:
	name = event_name
	source_id = source
	target_id = target
	data = context.duplicate(true)


## 将事件标记为取消；高优先级处理器可阻止后续默认结算。
func cancel() -> void:
	cancelled = true
