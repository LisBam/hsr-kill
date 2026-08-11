class_name TriggerManager
extends RefCounted

## 事件化触发器管理器。它只收集、排序和执行触发器，不负责创建卡牌、修改体力或移动实体牌。

## 触发派发局部熔断信号；数据只含稳定事件字段与计数，不对外泄漏回调或所有者引用。
signal dispatch_faulted(fault_data: Dictionary)

## 高级触发器允许的角色关系；无效字符串会在注册阶段被拒绝，避免静默变成全局触发。
const VALID_ROLES: Array[String] = ["player", "source", "target", "global"]

## 每个同步分片最多检查的有序触发器数；默认64在常规技能数量下保持同步，大型扩展时通过续列让出流程控制权。
var max_handlers_per_slice: int = 64

## 同一调用栈允许的嵌套规则时机深度；默认32允许正常伤害与响应嵌套，超限时只取消新的内层事件。
var max_nested_dispatch_depth: int = 32

## 触发器注册序号；同优先级、同座次时按注册顺序稳定执行。
var _next_registration_id: int = 1

## 以稳定事件名为键的触发器数组；数组内容通过 arrange 按角色座次重新排序。
var _handlers: Dictionary = {}

## 因可选技能询问、嵌套子时机或单分片预算而暂停的有序触发续列；每项保存原事件、已排序处理器和下一项索引，确保同一时机按座次逐项询问。
## 数组尾部是最内层时机，确保嵌套触发完成后再恢复外层座次询问。
var _deferred_dispatches: Array[Dictionary] = []

## 当前同步调用栈内正在派发的规则事件；用于流程边界立即终止尚未返回的旧时机，不承担事件排序或玩法状态职责。
var _active_dispatch_events: Array[RuleEvent] = []

## 当前有序触发派发的同步嵌套深度；最外层为1，全部返回后必须回到0。
var _dispatch_depth: int = 0

## 最近一次触发器局部熔断摘要；空字典表示当前实例尚未发生派发故障。
var _last_fault: Dictionary = {}

## 当前管理器累计触发器故障数；仅用于测试、日志与停滞诊断，不参与技能判定。
var _fault_count: int = 0


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
		# 当前触发器所有者；释放后的节点与空所有者都不再进入本次快照。
		var owner: Object = entry.get("owner") as Object
		if not is_instance_valid(owner):
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
	if event == null:
		return null
	# 同一RuleEvent对象在自身回调返回前不得再次派发，否则同一技能会无限重入。
	if _active_dispatch_events.has(event):
		event.cancel("trigger_reentrant_event")
		_record_dispatch_fault("trigger_reentrant_event", event)
		return event
	# 新建RuleEvent也可能通过技能回调不断相互触发；深度超限时只终止尚未入栈的内层事件。
	if _dispatch_depth >= maxi(max_nested_dispatch_depth, 1):
		event.cancel("trigger_recursion_limit")
		_record_dispatch_fault("trigger_recursion_limit", event)
		return event
	# 本次事件的稳定排序快照；订阅变化不得影响已经开始的同一时机。
	var arranged: Array[Dictionary] = arrange(event.name, start_player_id, seat_order, event)
	_execute_arranged_slice(event, arranged, 0, pause_condition)
	return event


## 在活动事件栈内执行一个排序分片；初次派发与选择后续接共用同一重入边界。
func _execute_arranged_slice(event: RuleEvent, arranged: Array[Dictionary], start_index: int, pause_condition: Callable) -> bool:
	# 恢复回调也可能重新派发同一事件对象；这与初次回调重入使用相同局部熔断。
	if _active_dispatch_events.has(event):
		event.cancel("trigger_reentrant_event")
		_record_dispatch_fault("trigger_reentrant_event", event)
		return false
	# 分片恢复时仍可创建新内层时机；每次进入都必须受同一深度上限约束。
	if _dispatch_depth >= maxi(max_nested_dispatch_depth, 1):
		event.cancel("trigger_recursion_limit")
		_record_dispatch_fault("trigger_recursion_limit", event)
		return false
	_dispatch_depth += 1
	_active_dispatch_events.append(event)
	# 本分片是否仍有未完成续列；离开活动栈后由调用方决定是否终结事件。
	var deferred_again: bool = _dispatch_arranged(event, arranged, start_index, pause_condition)
	_active_dispatch_events.erase(event)
	_dispatch_depth = maxi(_dispatch_depth - 1, 0)
	return deferred_again


## 取消所有符合名称与角色的活动或暂停派发；用于阶段跳过等流程边界使旧时机立即失效，返回实际终止的唯一事件数量。
func cancel_matching_dispatches(event_name: String, player_id: int = -1, reason: String = "cancelled") -> int:
	# 已取消事件集合；同一事件会同时短暂存在于活动栈和暂停续列时，只统计并取消一次。
	var cancelled_events: Array[RuleEvent] = []
	for active_event: RuleEvent in _active_dispatch_events:
		if active_event == null or active_event.is_terminal() or active_event.name != event_name:
			continue
		if player_id >= 0 and active_event.player_id != player_id:
			continue
		active_event.cancel(reason)
		cancelled_events.append(active_event)
	for deferred_dispatch: Dictionary in _deferred_dispatches:
		# 暂停续列持有的原事件；事件终止后恢复器会安全丢弃其剩余处理器，不再创建过期选择。
		var deferred_event: RuleEvent = deferred_dispatch.get("event") as RuleEvent
		if deferred_event == null or deferred_event.is_terminal() or cancelled_events.has(deferred_event) or deferred_event.name != event_name:
			continue
		if player_id >= 0 and deferred_event.player_id != player_id:
			continue
		deferred_event.cancel(reason)
		cancelled_events.append(deferred_event)
	return cancelled_events.size()


## 从指定索引继续执行一组已排序触发器；某一触发器创建选择请求后保存后续项，避免后续技能被单一选择窗口静默吞掉。
func _dispatch_arranged(event: RuleEvent, arranged: Array[Dictionary], start_index: int, pause_condition: Callable) -> bool:
	# 本分片已检查处理器数；包含条件失效项，防止大量过期订阅同样长时间占用主线程。
	var inspected_handler_count: int = 0
	# 本分片的实际检查上限；外部误设为0或负数时仍至少处理1项以保证可达。
	var handler_budget: int = maxi(max_handlers_per_slice, 1)
	for entry_index: int in range(start_index, arranged.size()):
		if event.is_terminal():
			return false
		# 达到分片上限时从当前索引续接，不把尚未执行的技能误记为已处理。
		if inspected_handler_count >= handler_budget:
			_store_deferred_dispatch(event, arranged, entry_index, _deferred_dispatches.size(), "budget")
			return true
		inspected_handler_count += 1
		# 当前触发器记录；恢复时继续使用初次派发已经确定的座次与优先级顺序。
		var entry: Dictionary = arranged[entry_index]
		# 当前处理器所有者；选择窗口期间卸载或释放后安全跳过过期快照。
		var owner: Object = entry.get("owner") as Object
		if not is_instance_valid(owner):
			continue
		# 当前动态条件；前一项效果可能已经改变状态，因此恢复前仍需重新校验。
		var condition: Callable = entry.get("condition", Callable()) as Callable
		if condition.is_valid() and not bool(condition.call(event)):
			continue
		# 当前实际回调；只有有效回调会获得本次时机的可写 RuleEvent。
		var callback: Callable = entry.get("callback", Callable()) as Callable
		# 回调前已有续列数量；若回调内部创建了更深层暂停时机，当前外层续列必须插在这些内层记录下方。
		var deferred_count_before_callback: int = _deferred_dispatches.size()
		if callback.is_valid():
			callback.call(event)
		# 当前回调是否创建了尚未完成的内层时机；即使它只是分片暂停而没有选择，外层也必须先保存后续。
		var nested_dispatch_deferred: bool = _deferred_dispatches.size() > deferred_count_before_callback
		# 当前回调是否创建了新选择；选择与内层续列都必须先完成，再询问外层下一个技能。
		var choice_deferred: bool = not event.is_terminal() and pause_condition.is_valid() and bool(pause_condition.call())
		if not event.is_terminal() and (choice_deferred or nested_dispatch_deferred):
			_store_deferred_dispatch(event, arranged, entry_index + 1, deferred_count_before_callback, "choice" if choice_deferred else "nested")
			return true
	return false


## 保存一条可恢复触发续列；内层时机在回调内建立时，外层记录会插入其下方以维持后进先出。
func _store_deferred_dispatch(event: RuleEvent, arranged: Array[Dictionary], next_index: int, insertion_index: int, pause_reason: String) -> void:
	event.data["_trigger_dispatch_deferred"] = true
	# 待续接记录；只保存原事件、稳定排序快照、下一索引和诊断原因。
	var deferred_entry: Dictionary = {
		"event":event,
		"entries":arranged,
		"next_index":next_index,
		"pause_reason":pause_reason,
	}
	# 实际插入位置；限定到当前数组范围，避免异常扩展传入过期索引。
	var safe_insertion_index: int = clampi(insertion_index, 0, _deferred_dispatches.size())
	if safe_insertion_index < _deferred_dispatches.size():
		_deferred_dispatches.insert(safe_insertion_index, deferred_entry)
	else:
		_deferred_dispatches.append(deferred_entry)


## 恢复最早暂停的有序触发续列；返回 true 表示仍有选择、嵌套子时机或预算续列等待，调用方应再次让统一结算管线取得控制权。
## 嵌套时机中的“最早”按直接父子关系解释为最内层未完成续列；同一时机内部仍保持初次确定的座次顺序。
func resume_deferred(pause_condition: Callable = Callable()) -> bool:
	while not _deferred_dispatches.is_empty():
		# 当前续列；先进先出保证嵌套时机也遵循原始触发先后。
		# 跨嵌套层级按后进先出恢复直接子时机；同一时机内部处理器仍按原始触发先后执行。
		var deferred_dispatch: Dictionary = _deferred_dispatches.pop_back() as Dictionary
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
			_deferred_dispatches.append(deferred_dispatch)
			return true
		if _execute_arranged_slice(event, arranged, next_index, pause_condition):
			return true
		event.data.erase("_trigger_dispatch_deferred")
		if not event.is_terminal():
			event.finish()
	return false


## 只恢复最内层的一条有序触发续列；调用方可在每条续列之间优先处理其新建的判定等子流程，避免越过父时机。
## 返回 true 表示本条续列恢复期间仍存在选择、嵌套子时机或预算续列；没有续列或同步完成时返回 false。
func resume_next_deferred(pause_condition: Callable = Callable()) -> bool:
	if _deferred_dispatches.is_empty():
		return false
	# 当前最内层续列；数组尾部始终对应最近因选择暂停的直接子时机。
	var deferred_dispatch: Dictionary = _deferred_dispatches.pop_back() as Dictionary
	# 原规则事件；终止或失效事件无需恢复，直接视为本条续列完成。
	var event: RuleEvent = deferred_dispatch.get("event") as RuleEvent
	if event == null or event.is_terminal():
		return false
	# 已有新选择时不能执行任何处理器；把原续列放回栈顶等待下一次恢复。
	if pause_condition.is_valid() and bool(pause_condition.call()):
		_deferred_dispatches.append(deferred_dispatch)
		return true
	# 初次派发时已经固定的处理器顺序；恢复时不得重新排列或引入新注册项。
	var arranged: Array[Dictionary] = []
	for entry_variant: Variant in deferred_dispatch.get("entries", []) as Array:
		arranged.append(entry_variant as Dictionary)
	# 下一项处理器索引；已经完成的技能不会重复询问或再次执行。
	var next_index: int = int(deferred_dispatch.get("next_index", 0))
	if _execute_arranged_slice(event, arranged, next_index, pause_condition):
		return true
	event.data.erase("_trigger_dispatch_deferred")
	if not event.is_terminal():
		event.finish()
	return false


## 返回是否存在尚未完成的有序触发续列；流程诊断只读取布尔值，不取得事件或回调引用。
func has_deferred_dispatches() -> bool:
	return not _deferred_dispatches.is_empty()


## 返回尚未完成的触发续列数量；只读诊断不暴露事件或回调引用。
func get_deferred_dispatch_count() -> int:
	return _deferred_dispatches.size()


## 返回最近一次触发派发故障的深拷贝；调试工具修改返回值不会影响真实运行时。
func get_last_fault() -> Dictionary:
	return _last_fault.duplicate(true)


## 返回当前触发器累计熔断次数；用于长局诊断区分新故障与历史记录。
func get_fault_count() -> int:
	return _fault_count


## 终止并清理全部尚未完成的触发续列；只用于同步时机超过总分片上限的局部灾难恢复。
func abort_all_deferred_dispatches(reason: String = "trigger_dispatch_aborted") -> int:
	# 被终止的唯一规则事件列表；同一事件可以在外层与嵌套记录中出现，只计数一次。
	var aborted_events: Array[RuleEvent] = []
	for deferred_dispatch: Dictionary in _deferred_dispatches:
		# 当前续列持有的原事件；已终止或已记录对象不重复修改。
		var event: RuleEvent = deferred_dispatch.get("event") as RuleEvent
		if event == null or aborted_events.has(event):
			continue
		if not event.is_terminal():
			event.cancel(reason)
		aborted_events.append(event)
	_deferred_dispatches.clear()
	return aborted_events.size()


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


## 记录一次局部派发熔断；详情可序列化，控制器可安全写入日志与停滞诊断。
func _record_dispatch_fault(reason: String, event: RuleEvent) -> void:
	_fault_count += 1
	_last_fault = {
		"reason":reason,
		"event_name":event.name if event != null else "",
		"player_id":event.player_id if event != null else -1,
		"source_id":event.source_id if event != null else -1,
		"target_id":event.target_id if event != null else -1,
		"dispatch_depth":_dispatch_depth,
		"deferred_dispatch_count":_deferred_dispatches.size(),
		"fault_count":_fault_count,
	}
	dispatch_faulted.emit(_last_fault.duplicate(true))
