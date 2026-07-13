class_name RuleEventBus
extends Node

## 通用规则触发总线。订阅者按优先级执行，彼此只共享 RuleEvent，不直接持有模块引用。

## 以事件名为键的处理器数组；每项含 owner、priority 与 callback。
var _handlers: Dictionary = {}


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


## 按当前优先级同步派发事件；已释放的所有者会被自动跳过。
func dispatch(event: RuleEvent) -> RuleEvent:
	# 当前事件的处理器快照；复制后允许处理器在回调中安全注册或注销。
	var handlers: Array = (_handlers.get(event.name, []) as Array).duplicate()
	for entry_variant: Variant in handlers:
		# 当前处理器记录；包含所有者、优先级与回调。
		var entry: Dictionary = entry_variant as Dictionary
		# 当前处理器所有者；无效实例不会执行回调。
		var owner: Object = entry.get("owner") as Object
		# 当前处理器回调；必须保持可调用状态。
		var callback: Callable = entry.get("callback", Callable()) as Callable
		if is_instance_valid(owner) and callback.is_valid():
			callback.call(event)
	return event


## 处理器排序函数；优先级高的规则先获得修改或取消事件的机会。
func _sort_by_priority(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("priority", 0)) > int(right.get("priority", 0))
