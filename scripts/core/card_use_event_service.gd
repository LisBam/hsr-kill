class_name CardUseEventService
extends RefCounted

## 使用牌事件树构建组件。它只声明无名杀式事件拓扑，不读取对局状态、不执行牌效，也不持有实体牌对象。

## 使用牌声明后的五组全局时机；数组顺序与 noname-v1.10.16 的 useCard 内容步骤一致。
const USE_TIMING_NAMES: Array[String] = ["useCard0", "useCard1", "yingbian", "useCard2", "useCard"]

## 进入牌内容前的四组逐目标时机；每组必须遍历全部目标后才能进入下一组。
const TARGET_TIMING_NAMES: Array[String] = ["useCardToPlayer", "useCardToTarget", "useCardToPlayered", "useCardToTargeted"]


## 创建一条真实 CardUseEvent；内容步骤由权威控制器提供，组件只写入可序列化牌与目标字段。
func create_use_event(scheduler: EventScheduler, parent_id: int, event_context: Dictionary, content_steps: Array[Callable]) -> GameEvent:
	if scheduler == null:
		return null
	# 使用牌父事件；父 ID 小于0时作为独立测试根事件创建，正式对局始终挂在长期 RootGameEvent 下。
	var use_event: GameEvent = scheduler.create_event("CardUseEvent", "card_use", content_steps, event_context, parent_id)
	use_event.player_id = int(event_context.get("actor_id", -1))
	use_event.source_id = use_event.player_id
	for target_id_variant: Variant in event_context.get("target_ids", []) as Array:
		use_event.target_ids.append(int(target_id_variant))
	use_event.card = (event_context.get("virtual_card", {}) as Dictionary).duplicate(true)
	for card_uid_variant: Variant in event_context.get("material_card_uids", []) as Array:
		use_event.card_uids.append(int(card_uid_variant))
	return use_event


## 按源码顺序把五组使用牌时机加入父事件 next 队列；每个时机都是可进入调度栈的真实子事件。
func enqueue_use_timings(scheduler: EventScheduler, use_event: GameEvent, timing_step: Callable) -> void:
	if scheduler == null or use_event == null:
		return
	for timing_name: String in USE_TIMING_NAMES:
		# 当前使用牌时机上下文；完整目标数组保留给触发器读取和修改共享规则标记。
		var timing_context: Dictionary = _base_child_context(use_event)
		timing_context["timing_name"] = timing_name
		scheduler.create_child(use_event.event_id, timing_name, "trigger", [timing_step], timing_context)


## 加入一个指定阶段与目标的真实时机；父事件使用已处理目标集合逐次调用，以支持触发器动态增删目标。
func enqueue_target_timing(scheduler: EventScheduler, use_event: GameEvent, timing_name: String, target_id: int, timing_step: Callable) -> GameEvent:
	if scheduler == null or use_event == null or not TARGET_TIMING_NAMES.has(timing_name):
		return null
	# 当前动态逐目标时机上下文；完整目标数组取父事件最新快照，当前目标使用独立稳定 ID。
	var timing_context: Dictionary = _base_child_context(use_event)
	timing_context["timing_name"] = timing_name
	timing_context["target_id"] = target_id
	return scheduler.create_child(use_event.event_id, timing_name, "trigger", [timing_step], timing_context)


## 创建唯一 contentBefore 子事件；即使具体卡牌没有自定义前置内容，稳定时机仍进入事件历史。
func enqueue_content_before(scheduler: EventScheduler, use_event: GameEvent, content_step: Callable) -> GameEvent:
	if scheduler == null or use_event == null:
		return null
	return scheduler.create_child(use_event.event_id, "contentBefore", "card_content", [content_step], _base_child_context(use_event))


## 为当前目标创建一条 content 子事件；目标效果中的选择会暂停这一事件并从原步骤恢复。
func enqueue_target_content(scheduler: EventScheduler, use_event: GameEvent, target_id: int, content_step: Callable) -> GameEvent:
	if scheduler == null or use_event == null:
		return null
	# 当前目标内容上下文；目标 ID 小于0时表示五谷等必须一次读取完整目标数组的整牌内容。
	var content_context: Dictionary = _base_child_context(use_event)
	content_context["target_id"] = target_id
	return scheduler.create_child(use_event.event_id, "content", "card_content", [content_step], content_context)


## 创建唯一 contentAfter 子事件；它只能在全部同步效果和暂停选择恢复完成后加入父事件。
func enqueue_content_after(scheduler: EventScheduler, use_event: GameEvent, content_step: Callable, destination: String) -> GameEvent:
	if scheduler == null or use_event == null:
		return null
	# 卡牌最终区域语义；discard、equipment、judgment 或 consumed 均由规则层确定后写入。
	var content_context: Dictionary = _base_child_context(use_event)
	content_context["destination"] = destination
	return scheduler.create_child(use_event.event_id, "contentAfter", "card_content", [content_step], content_context)


## 把 orderingDiscard 加入 CardUseEvent 的 after 队列；实体牌只在该收尾事件内创建 cardsDiscard 并离开处理区。
func enqueue_ordering_discard(scheduler: EventScheduler, use_event: GameEvent, ordering_step: Callable) -> GameEvent:
	if scheduler == null or use_event == null:
		return null
	return scheduler.create_child(use_event.event_id, "orderingDiscard", "card_move", [ordering_step], _base_child_context(use_event), "after")


## 返回供子事件继承的基础可序列化上下文；不会复制父事件步骤、队列或可变对象引用。
func _base_child_context(use_event: GameEvent) -> Dictionary:
	return {
		"card_use_event_id":use_event.event_id,
		"actor_id":use_event.player_id,
		"target_ids":use_event.target_ids.duplicate(),
		"card_uid":int(use_event.context.get("card_uid", use_event.card_uids[0] if not use_event.card_uids.is_empty() else -1)),
		"virtual_card":use_event.card.duplicate(true),
		"material_card_uids":use_event.card_uids.duplicate(),
		"virtual_proxy":bool(use_event.context.get("virtual_proxy", false)),
	}
