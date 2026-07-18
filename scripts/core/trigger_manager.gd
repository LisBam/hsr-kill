class_name TriggerManager
extends RefCounted

## 事件化触发器管理器。它只收集、排序和执行触发器，不负责创建卡牌、修改体力或移动实体牌。

## 高级触发器允许的角色关系；无效字符串会在注册阶段被拒绝，避免静默变成全局触发。
const VALID_ROLES: Array[String] = ["player", "source", "target", "global"]

## 触发器注册序号；同优先级、同座次时按注册顺序稳定执行。
var _next_registration_id: int = 1

## 以稳定事件名为键的触发器数组；数组内容通过 arrange 按角色座次重新排序。
var _handlers: Dictionary = {}

## 因可选技能询问而暂停的有序触发续列；每项保存原事件、已排序处理器和下一项索引，确保同一时机按座次逐项询问。
var _deferred_dispatches: Array[Dictionary] = []


## 注册一个触发器。role 可取 player、source、target、global；first_do/last_do 控制分组顺序。
func subscribe(event_name: String, owner: Object, callback: Callable, priority: int = 0, owner_player_id: int = -1, role: String = "global", first_do: bool = false, last_do: bool = false, condition: Callable = Callable()) -> int:
	if event_name.is_empty() or not callback.is_valid() or not VALID_ROLES.has(role):
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
		if event != null and not _matches_role(entry, event):
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
func dispatch(event: RuleEvent, start_player_id: int, seat_order: Array[int], pause_condition: Callable = Callable()) -> RuleEvent:
	var arranged: Array[Dictionary] = arrange(event.name, start_player_id, seat_order, event)
	_dispatch_arranged(event, arranged, 0, pause_condition)
	return event


## 从指定索引继续执行一组已排序触发器；某一触发器创建选择请求后保存后续项，避免后续技能被单一选择窗口静默吞掉。
func _dispatch_arranged(event: RuleEvent, arranged: Array[Dictionary], start_index: int, pause_condition: Callable) -> bool:
	for entry_index: int in range(start_index, arranged.size()):
		if event.is_terminal():
			return false
		# 当前触发器记录；恢复时继续使用初次派发已经确定的座次与优先级顺序。
		var entry: Dictionary = arranged[entry_index]
		# 当前动态条件；前一项效果可能已经改变状态，因此恢复前仍需重新校验。
		var condition: Callable = entry.get("condition", Callable()) as Callable
		if condition.is_valid() and not bool(condition.call(event)):
			continue
		# 当前实际回调；只有有效回调会获得本次时机的可写 RuleEvent。
		var callback: Callable = entry.get("callback", Callable()) as Callable
		if callback.is_valid():
			callback.call(event)
		# 选择请求必须先由当前技能完整恢复，再询问下一个同一时机技能。
		if not event.is_terminal() and pause_condition.is_valid() and bool(pause_condition.call()):
			event.data["_trigger_dispatch_deferred"] = true
			_deferred_dispatches.append({"event":event, "entries":arranged, "next_index":entry_index + 1})
			return true
	return false


## 恢复最早暂停的有序触发续列；返回 true 表示恢复过程中又创建了新的选择请求，调用方应等待下一次响应。
func resume_deferred(pause_condition: Callable = Callable()) -> bool:
	while not _deferred_dispatches.is_empty():
		# 当前续列；先进先出保证嵌套时机也遵循原始触发先后。
		var deferred_dispatch: Dictionary = _deferred_dispatches.pop_front() as Dictionary
		# 原规则事件；事件可能已因终局或规则取消终止，此时不再执行任何后续技能。
		var event: RuleEvent = deferred_dispatch.get("event") as RuleEvent
		if event == null or event.is_terminal():
			continue
		# 初次派发确定的处理器副本；不重新 arrange，避免选择期间新增订阅改变本时机顺序。
		var arranged: Array[Dictionary] = []
		for entry_variant: Variant in deferred_dispatch.get("entries", []) as Array:
			arranged.append(entry_variant as Dictionary)
		# 下一项索引；已经完成的技能不会在恢复后重复询问。
		var next_index: int = int(deferred_dispatch.get("next_index", 0))
		# 已有新的选择等待时保持原续列顺序，不调用任何后续技能。
		if pause_condition.is_valid() and bool(pause_condition.call()):
			_deferred_dispatches.push_front(deferred_dispatch)
			return true
		if _dispatch_arranged(event, arranged, next_index, pause_condition):
			return true
		event.data.erase("_trigger_dispatch_deferred")
		if not event.is_terminal():
			event.finish()
	return false


## 返回指定规则事件是否仍等待同一时机后续技能；RuleTimingService 据此延后终结事件状态。
func is_dispatch_deferred(event: RuleEvent) -> bool:
	if event == null:
		return false
	for deferred_dispatch: Dictionary in _deferred_dispatches:
		if deferred_dispatch.get("event") == event:
			return true
	return false


## 返回指定玩家相对起点的环形距离；未知玩家和 global 触发器排在所有角色之后。
func _seat_distance(start_player_id: int, player_id: int, seat_order: Array[int]) -> int:
	if player_id < 0 or seat_order.is_empty():
		return seat_order.size() + 1
	var start_index: int = seat_order.find(start_player_id)
	var target_index: int = seat_order.find(player_id)
	if start_index < 0 or target_index < 0:
		return seat_order.size() + 1
	return posmod(target_index - start_index, seat_order.size())


## 判断一条触发器记录是否符合当前事件的 player/source/target/global 关系；非全局触发必须绑定有效玩家 ID。
func _matches_role(entry: Dictionary, event: RuleEvent) -> bool:
	# 当前注册角色；注册入口已校验，异常历史数据按不匹配处理。
	var role: String = str(entry.get("role", ""))
	if role == "global":
		return true
	# 技能或装备所属玩家 ID；非全局角色没有有效持有者时不能触发。
	var owner_player_id: int = int(entry.get("owner_player_id", -1))
	if owner_player_id < 0:
		return false
	if role == "player":
		return owner_player_id == event.player_id
	if role == "source":
		return owner_player_id == event.source_id
	if role == "target":
		return owner_player_id == event.target_id
	return false
