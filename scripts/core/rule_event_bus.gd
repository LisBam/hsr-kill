class_name RuleEventBus
extends Node

## 通用规则触发总线。订阅者按优先级执行，彼此只共享 RuleEvent，不直接持有模块引用。

## 普通规则回调发生重入或深度超限时发出；只携带可序列化诊断字段。
signal dispatch_faulted(fault_data: Dictionary)

## 同一调用栈允许的普通规则事件嵌套深度；默认32与有序技能时机共用安全边界语义。
var max_nested_dispatch_depth: int = 32

## 以事件名为键的处理器数组；每项含 owner、priority 与 callback。
var _handlers: Dictionary = {}

## 事件化触发器排序组件；旧 subscribe/dispatch 保持兼容，复杂技能可通过 subscribe_ordered 注册。
var _ordered_triggers: TriggerManager = TriggerManager.new()

## 当前普通总线同步派发深度；最外层为1，全部回调返回后恢复为0。
var _dispatch_depth: int = 0

## 当前正在普通总线派发的规则事件对象；用于拒绝同一对象递归重入。
var _active_dispatch_events: Array[RuleEvent] = []

## 最近一次普通总线派发故障摘要；空字典表示尚未熔断过异常回调链。
var _last_fault: Dictionary = {}

## 普通总线累计熔断次数；仅供测试与运行时诊断使用。
var _fault_count: int = 0


## 注册事件处理器。owner 用于组件卸载时批量注销，priority 越大越先执行。
func subscribe(event_name: String, owner: Object, callback: Callable, priority: int = 0) -> void:
	if not _handlers.has(event_name):
		_handlers[event_name] = []
	# 新处理器记录；只保存弱生命周期所有者与可调用函数。
	var entry: Dictionary = {"owner": owner, "callback": callback, "priority": priority}
	(_handlers[event_name] as Array).append(entry)
	(_handlers[event_name] as Array).sort_custom(_sort_by_priority)


## 注销某个所有者注册的全部处理器，防止场景切换后遗留无效回调。
func unsubscribe_owner(owner: Object) -> void:
	for event_name_variant: Variant in _handlers.keys():
		# 当前事件名；用于写回过滤后的处理器数组。
		var event_name: String = str(event_name_variant)
		# 当前事件的原处理器数组；从后向前删除可避免索引移动问题。
		var handlers: Array = _handlers[event_name] as Array
		for index: int in range(handlers.size() - 1, -1, -1):
			if handlers[index].get("owner") == owner:
				handlers.remove_at(index)
	_ordered_triggers.unsubscribe_owner(owner)


## 注册带角色座次、firstDo/lastDo 和动态条件的高级触发器；普通规则继续使用 subscribe。
func subscribe_ordered(event_name: String, owner: Object, callback: Callable, priority: int = 0, owner_player_id: int = -1, role: String = "global", first_do: bool = false, last_do: bool = false, condition: Callable = Callable()) -> int:
	return _ordered_triggers.subscribe(event_name, owner, callback, priority, owner_player_id, role, first_do, last_do, condition)


## 按当前优先级同步派发事件；已释放的所有者会被自动跳过。
func dispatch(event: RuleEvent) -> RuleEvent:
	if event == null:
		return null
	# 同一规则事件对象不得在自身回调内重新进入总线，否则会在到达有序技能层之前耗尽调用栈。
	if _active_dispatch_events.has(event):
		event.cancel("rule_bus_reentrant_event")
		_record_dispatch_fault("rule_bus_reentrant_event", event)
		return event
	# 多个新事件也可能在普通回调中相互创建；超过深度时局部取消最内层事件。
	if _dispatch_depth >= maxi(max_nested_dispatch_depth, 1):
		event.cancel("rule_bus_recursion_limit")
		_record_dispatch_fault("rule_bus_recursion_limit", event)
		return event
	# 当前事件的处理器快照；复制后允许处理器在回调中安全注册或注销。
	var handlers: Array = (_handlers.get(event.name, []) as Array).duplicate()
	_dispatch_depth += 1
	_active_dispatch_events.append(event)
	for entry_variant: Variant in handlers:
		# 当前处理器记录；包含所有者、优先级与回调。
		var entry: Dictionary = entry_variant as Dictionary
		# 当前处理器所有者；无效实例不会执行回调。
		var owner: Object = entry.get("owner") as Object
		# 当前处理器回调；必须保持可调用状态。
		var callback: Callable = entry.get("callback", Callable()) as Callable
		if is_instance_valid(owner) and callback.is_valid():
			callback.call(event)
	_active_dispatch_events.erase(event)
	_dispatch_depth = maxi(_dispatch_depth - 1, 0)
	return event


## 按座次与特殊分组派发高级触发器；旧全局优先级回调由调用方显式先执行以保持迁移期顺序可见。
func dispatch_ordered(event: RuleEvent, start_player_id: int, seat_order: Array[int]) -> RuleEvent:
	return _ordered_triggers.dispatch(event, start_player_id, seat_order)


## 处理器排序函数；优先级高的规则先获得修改或取消事件的机会。
func _sort_by_priority(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("priority", 0)) > int(right.get("priority", 0))


## 返回最近一次普通总线熔断摘要的深拷贝；外部不能篡改真实诊断状态。
func get_last_fault() -> Dictionary:
	return _last_fault.duplicate(true)


## 返回当前普通总线累计熔断次数；数值不参与任何规则效果。
func get_fault_count() -> int:
	return _fault_count


## 记录一次普通总线重入故障；取消语义已由派发入口写入原RuleEvent。
func _record_dispatch_fault(reason: String, event: RuleEvent) -> void:
	_fault_count += 1
	_last_fault = {
		"reason":reason,
		"event_name":event.name if event != null else "",
		"player_id":event.player_id if event != null else -1,
		"source_id":event.source_id if event != null else -1,
		"target_id":event.target_id if event != null else -1,
		"dispatch_depth":_dispatch_depth,
		"fault_count":_fault_count,
	}
	dispatch_faulted.emit(_last_fault.duplicate(true))
