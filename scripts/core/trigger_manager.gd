class_name TriggerManager
extends RefCounted

## 事件化触发器管理器。它只收集、排序和执行触发器，不负责创建卡牌、修改体力或移动实体牌。

## 触发器注册序号；同优先级、同座次时按注册顺序稳定执行。
var _next_registration_id: int = 1

## 以稳定事件名为键的触发器数组；数组内容通过 arrange 按角色座次重新排序。
var _handlers: Dictionary = {}


## 注册一个触发器。role 可取 player、source、target、global；first_do/last_do 控制分组顺序。
func subscribe(event_name: String, owner: Object, callback: Callable, priority: int = 0, owner_player_id: int = -1, role: String = "global", first_do: bool = false, last_do: bool = false, condition: Callable = Callable()) -> int:
	if event_name.is_empty() or not callback.is_valid():
		return -1
	# 当前触发器记录；不保存事件或控制器引用，只保存可解绑 owner 和行为回调。
	var entry: Dictionary = {
		"registration_id": _next_registration_id,
		"owner": owner,
		"callback": callback,
		"priority": priority,
		"owner_player_id": owner_player_id,
		"role": role,
		"first_do": first_do,
		"last_do": last_do,
		"condition": condition,
	}
	_next_registration_id += 1
	if not _handlers.has(event_name):
		_handlers[event_name] = []
	(_handlers[event_name] as Array).append(entry)
	return int(entry["registration_id"])


## 注销一个所有者的全部触发器；角色、技能或场景卸载都必须调用该方法。
func unsubscribe_owner(owner: Object) -> void:
	for event_name_variant: Variant in _handlers.keys():
		# 当前事件名；过滤掉属于待卸载 owner 的处理器。
		var event_name: String = str(event_name_variant)
		var retained: Array = []
		for entry_variant: Variant in _handlers[event_name] as Array:
			# 当前触发器记录；无效 owner 也不再继续保留，防止长期累积。
			var entry: Dictionary = entry_variant as Dictionary
			if entry.get("owner") == owner or not is_instance_valid(entry.get("owner") as Object):
				continue
			retained.append(entry)
		_handlers[event_name] = retained


## 按起始座次、firstDo/lastDo、优先级与注册序号排列可执行触发器。
func arrange(event_name: String, start_player_id: int, seat_order: Array[int], event: RuleEvent = null) -> Array[Dictionary]:
	# 当前事件处理器快照；复制后本次排列不会受回调中注册/注销影响。
	var entries: Array = (_handlers.get(event_name, []) as Array).duplicate()
	var filtered: Array[Dictionary] = []
	for entry_variant: Variant in entries:
		# 当前候选触发器；执行前检查 owner、角色归属和动态 condition。
		var entry: Dictionary = entry_variant as Dictionary
		var owner: Object = entry.get("owner") as Object
		if owner != null and not is_instance_valid(owner):
			continue
		var condition: Callable = entry.get("condition", Callable()) as Callable
		if condition.is_valid() and event != null and not bool(condition.call(event)):
			continue
		filtered.append(entry)
	filtered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_group: int = 0 if bool(left.get("first_do", false)) else (2 if bool(left.get("last_do", false)) else 1)
			var right_group: int = 0 if bool(right.get("first_do", false)) else (2 if bool(right.get("last_do", false)) else 1)
			if left_group != right_group:
				return left_group < right_group
			if int(left.get("priority", 0)) != int(right.get("priority", 0)):
				return int(left.get("priority", 0)) > int(right.get("priority", 0))
			var left_seat: int = _seat_distance(start_player_id, int(left.get("owner_player_id", -1)), seat_order)
			var right_seat: int = _seat_distance(start_player_id, int(right.get("owner_player_id", -1)), seat_order)
			if left_seat != right_seat:
				return left_seat < right_seat
			return int(left.get("registration_id", 0)) < int(right.get("registration_id", 0)))
	return filtered


## 执行已经排列的触发器；每个回调前重新检查 condition，支持前一项修改事件后停止后续触发。
func dispatch(event: RuleEvent, start_player_id: int, seat_order: Array[int]) -> RuleEvent:
	var arranged: Array[Dictionary] = arrange(event.name, start_player_id, seat_order, event)
	for entry: Dictionary in arranged:
		if event.is_terminal():
			break
		var condition: Callable = entry.get("condition", Callable()) as Callable
		if condition.is_valid() and not bool(condition.call(event)):
			continue
		var callback: Callable = entry.get("callback", Callable()) as Callable
		if callback.is_valid():
			callback.call(event)
	return event


## 返回指定玩家相对起点的环形距离；未知玩家和 global 触发器排在所有角色之后。
func _seat_distance(start_player_id: int, player_id: int, seat_order: Array[int]) -> int:
	if player_id < 0 or seat_order.is_empty():
		return seat_order.size() + 1
	var start_index: int = seat_order.find(start_player_id)
	var target_index: int = seat_order.find(player_id)
	if start_index < 0 or target_index < 0:
		return seat_order.size() + 1
	return posmod(target_index - start_index, seat_order.size())
