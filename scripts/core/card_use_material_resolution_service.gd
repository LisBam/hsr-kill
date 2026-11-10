extends RefCounted

## 使用牌材料编排；真实牌、虚拟牌共用逐张移牌和最终处理区回收协议。

## 权威宿主；只在当前序列存活期间持有，不写入事件快照。
var _host: Object

## 所属 lose 或 cardsDiscard 子事件；由其暂停令牌阻止父用牌提前推进。
var _event: GameEvent

## 当前单张移牌服务；完成后读取结果，再处理下一张材料。
var _movement: CardMoveResolutionService


## 绑定权威宿主，所有实际区域修改仍由 CardMovementService 提交。
func _init(host: Object) -> void:
	_host = host


## loss=false 表示用牌结束回收；loss=true 表示声明前消费材料。
func resolve(event: GameEvent, loss: bool) -> void:
	_event = event
	# 材料清单；真实牌使用自身UID，虚拟牌只移动实体费用，不把逻辑代理当材料。
	var material_uids: Array[int] = _host._int_array(event.context.get("material_card_uids", []))
	if not bool(event.context.get("virtual_proxy", false)):
		material_uids = [int(event.context.get("card_uid", -1))]
	# 事件独占的暂停；只在全部移牌通知和装备离区效果结束后释放。
	var pause_token_id: int = _host.event_scheduler.pause_registry.acquire("card_move", event.event_id, "card_use_materials", false)
	# 稳定游标；任何暂停后重取材料，未提交的材料不能被提前消费。
	var context: Dictionary = {"sequence_kind":"card_use_materials", "event_id":event.event_id, "loss":loss, "material_uids":material_uids, "index":0, "moved_uids":[], "move_ids":[], "failed":false, "pause_token_id":pause_token_id}
	# 强类型步骤数组；通过动态宿主调用时仍保持公开接口的Array[Callable]契约。
	var steps: Array[Callable] = [_validate, _next, _complete, _release]
	if _host.run_rule_sequence(steps, context) < 0:
		_host.event_scheduler.pause_registry.resolve(pause_token_id, "card_move_sequence_unavailable")


## 消费前一次校验整份清单；重复UID或失效材料不能开始一次部分有效的用牌。
func _validate(sequence: RuleStepSequence) -> void:
	if not bool(sequence.context.loss):
		return
	if not _valid_actor():
		sequence.context["failed"] = true
		return
	# 已校验集合；同一实体不能承担两份费用。
	var seen: Array[int] = []
	for card_uid: int in sequence.context.material_uids:
		if seen.has(card_uid) or not _owns_material(card_uid):
			sequence.context["failed"] = true
			return
		seen.append(card_uid)


## 消费费用始终属于创建用牌时的角色；等待中死亡、离场或换将不能继续声明旧牌。
func _valid_actor() -> bool:
	# 当前座位角色；只读取稳定身份，每个费用步骤重新取得。
	var actor: PlayerState = _host.state.get_player(int(_event.context.actor_id))
	return not _event.is_terminal() and actor != null and actor.alive and not actor.out_of_game and actor.character_generation == int(_event.context.get("actor_character_generation", actor.character_generation))


## 真实用牌只接受既有可用牌源；装备材料仍须由虚拟用牌入口显式声明。
func _owns_material(card_uid: int) -> bool:
	if bool(_event.context.get("virtual_proxy", false)):
		return _host._find_owned_virtual_material(int(_event.context.actor_id), card_uid) != null
	# 当前真实牌使用者；保留hand和wooden_ox的正式材料来源约束。
	var actor: PlayerState = _host.state.get_player(int(_event.context.actor_id))
	return actor != null and actor.find_playable_card(card_uid) != null


## 每次只安排一张材料；前张的End/After和装备触发均完成后才进入下一张。
func _next(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.failed) or int(sequence.context.index) >= (sequence.context.material_uids as Array).size():
		return
	# 当前材料身份；等待期间不持有原玩家或卡牌引用。
	var card_uid: int = int(sequence.context.material_uids[int(sequence.context.index)])
	sequence.context["index"] = int(sequence.context.index) + 1
	# 当前权威位置；回收跳过已被别的效果移走的材料，消费则必须仍由原使用者拥有。
	var location: Dictionary = _host._find_card_location_by_uid(card_uid)
	if bool(sequence.context.loss):
		if not _valid_actor() or not _owns_material(card_uid):
			sequence.context["failed"] = true
			return
	elif str(location.get("zone", "")) != "processing":
		sequence.insert_steps([_next])
		return
	sequence.context["was_equipment"] = str(location.get("zone", "")) == "equipment"
	sequence.context["source_definition_id"] = str((location.get("card") as CardInstance).definition_id) if location.get("card") != null else ""
	_movement = CardMoveResolutionService.new(_host)
	sequence.insert_steps([_after_move, _next])
	_movement.begin(sequence, card_uid, "processing" if bool(sequence.context.loss) else "discard_pile", -1, "use" if bool(sequence.context.loss) else "ordering_discard", _event.event_id)


## 成功结果只登记一次；装备离区钩子拥有独立等待边界，不与下一材料并发。
func _after_move(sequence: RuleStepSequence) -> void:
	if not bool(_movement.result.get("success", false)):
		sequence.context["failed"] = bool(sequence.context.loss)
		return
	sequence.context.moved_uids.append_array(_movement.result.get("card_uids", [int(_movement.result.card_uid)]) as Array)
	sequence.context.move_ids.append(int(_movement.result.move_id))
	if bool(sequence.context.get("was_equipment", false)):
		# 装备离区时重新定位角色与已移动实体；换将后的角色不能使用旧实例引用。
		var actor: PlayerState = _host.state.get_player(int(_event.context.actor_id))
		# 处理区材料实体；只在本次同步回调内用于卸载对应装备运行时。
		var card: CardInstance = _host._find_processing_card(int(_movement.result.card_uid))
		if actor != null and card != null and _valid_actor():
			_host._on_equipment_lost(actor, card, true, str(sequence.context.source_definition_id))


## 结果由所属事件归档；失败取消牌效，已经移动的费用仍进入父用牌正常回收。
func _complete(sequence: RuleStepSequence) -> void:
	_event.result = {"card_uids":(sequence.context.moved_uids as Array).duplicate(), "move_ids":(sequence.context.move_ids as Array).duplicate(), "to_zone":"processing" if bool(sequence.context.loss) else "discard_pile"}
	if (sequence.context.move_ids as Array).size() == 1:
		_event.result["move_id"] = int(sequence.context.move_ids[0])
		_event.result["from_zone"] = str(_movement.result.get("from_zone", ""))
	if bool(sequence.context.loss):
		# 原持久装备拆组可以展开多份物理材料；父用牌最终回收必须拥有全部成功消费的实体。
		var parent_context: Dictionary = _host._card_use_contexts.get(int(_event.context.card_uid), {}) as Dictionary
		if not parent_context.is_empty():
			parent_context["material_card_uids"] = (sequence.context.moved_uids as Array).duplicate()
		if bool(sequence.context.failed) or not _valid_actor():
			# 父牌上下文；逻辑代理可能仍在处理区，不能仅取消lose而让它继续造成效果。
			var use_context: Dictionary = _host._card_use_contexts.get(int(_event.context.card_uid), {})
			use_context["cancelled"] = true
			use_context["cancel_reason"] = "material_move_failed"
			_event.cancel("material_move_failed")
		return
	# 逻辑代理只提供此次牌效身份，回收时返回void而不成为弃牌堆里的额外实体。
	var proxy: CardInstance = _host._find_processing_card(int(_event.context.card_uid))
	if bool(_event.context.get("virtual_proxy", false)) and proxy != null:
		_host.card_movement.move_card(proxy, "void", -1, "virtual_card_complete", _event.event_id)
	_host._active_card_resolutions.erase(int(_event.context.card_uid))
	_host._card_use_contexts.erase(int(_event.context.card_uid))
	_host._check_game_over()


## 最后释放子事件暂停，父CardUseEvent才能声明或结束；取消由调度器回收同一所有权。
func _release(sequence: RuleStepSequence) -> void:
	_host.event_scheduler.pause_registry.resolve(int(sequence.context.pause_token_id), "card_move_complete")
