class_name RuleModifierPipeline
extends RefCounted

## 纯查询修正管线。它模拟 checkMod 的链式输入输出，不触发时机、不移动牌、不消耗次数。

## 以修正名为键的修正器数组；每项按优先级从高到低应用。
var _modifiers: Dictionary = {}

## 修正器注册序号；同优先级时保证稳定调用顺序。
var _next_registration_id: int = 1


## 注册一个纯修正器；callback 接收当前值和上下文字典并返回修正后的值。
func register(modifier_name: String, owner: Object, callback: Callable, priority: int = 0) -> int:
	if modifier_name.is_empty() or not callback.is_valid():
		return -1
	# 当前修正器记录；上下文只能由查询调用方提供，修正器不应直接持有 GameState。
	var entry: Dictionary = {"registration_id":_next_registration_id, "owner":owner, "callback":callback, "priority":priority}
	_next_registration_id += 1
	if not _modifiers.has(modifier_name):
		_modifiers[modifier_name] = []
	(_modifiers[modifier_name] as Array).append(entry)
	(_modifiers[modifier_name] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("priority", 0)) != int(right.get("priority", 0)):
			return int(left.get("priority", 0)) > int(right.get("priority", 0))
		return int(left.get("registration_id", 0)) < int(right.get("registration_id", 0)))
	return int(entry["registration_id"])


## 移除指定 owner 的全部修正器，避免临时技能在离场后继续影响查询。
func unregister_owner(owner: Object) -> void:
	for name_variant: Variant in _modifiers.keys():
		# 当前修正名；过滤后保留仍有效的处理器。
		var modifier_name: String = str(name_variant)
		var retained: Array = []
		for entry_variant: Variant in _modifiers[modifier_name] as Array:
			# 当前修正记录；无效 owner 会在清理时一起丢弃。
			var entry: Dictionary = entry_variant as Dictionary
			if entry.get("owner") == owner or not is_instance_valid(entry.get("owner") as Object):
				continue
			retained.append(entry)
		_modifiers[modifier_name] = retained


## 按优先级链式应用修正；修正器异常返回的 null 会保留前一项值而不污染查询结果。
func apply(modifier_name: String, value: Variant, context: Dictionary = {}) -> Variant:
	# 当前管线值；每个回调只能基于前一项结果计算新值。
	var current: Variant = value
	for entry_variant: Variant in (_modifiers.get(modifier_name, []) as Array).duplicate():
		# 当前修正器；无效 owner 跳过但不影响其余修正器。
		var entry: Dictionary = entry_variant as Dictionary
		var owner: Object = entry.get("owner") as Object
		var callback: Callable = entry.get("callback", Callable()) as Callable
		if owner != null and not is_instance_valid(owner):
			continue
		if not callback.is_valid():
			continue
		var modified: Variant = callback.call(current, context.duplicate(true))
		if modified != null:
			current = modified
	return current
