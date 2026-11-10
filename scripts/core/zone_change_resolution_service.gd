extends RefCounted

## 区域废除的单次内容；前置与卡牌前置完整通过后提交，所有离区子效果结束后才发布区域After。

## 权威宿主；运行时持有，不进入稳定上下文。
var _host: Object

## 区域规则组件；复用栏位标准化、日志与历史，不保存第二份区域状态。
var _service: Object

## 当前区域的逐牌移动游标；每次请求独立持有，嵌套废除不会覆盖。
var _movements: Array[CardMoveResolutionService] = []

## 本次规则内容身份；完成直接取决于宿主是否仍持有该内容。
var _sequence_id: int = -1

## 是否至少改变一个区域或栏位；取消与幂等请求保持false。
var success: bool = false

## 实际改变的栏位及判定区数量；判定区视为1个区域，不是弃牌数。
var count: int = 0

## 本次已提交事实；原始实体UID只出现一次，后置中的其他移动不会改写它。
var result: Dictionary = {"success":false, "card_uids":[], "changed_slots":[], "judgment_changed":false}

## 所有区域、移牌与后置子内容是否结束；终局或撤销也不会留下独立恢复状态。
var completed: bool:
	get:
		return _sequence_id < 0 or not _host.is_rule_sequence_pending(_sequence_id)


func _init(host: Object, service: Object) -> void:
	_host = host
	_service = service


## operations只包含equipment/judgment、目标状态和标准栏位；整个区域请求依次完整等待装备区、判定区。
func begin(player_id: int, operations: Array[Dictionary], reason: String, source_id: int) -> void:
	# 原角色；区域变化允许仍存活的离场角色，代次必须贯穿完整请求。
	var player: PlayerState = _service._get_player(player_id)
	if player == null or not player.alive:
		return
	# 稳定内容；不把实体、服务或回调写入上下文。
	var context: Dictionary = {"sequence_kind":"zone_change", "player_id":player_id, "generation":player.character_generation, "operations":operations.duplicate(true), "reason":reason, "source_id":source_id, "event_id":_host._current_rule_parent_event_id()}
	# 每个区域各自拥有可取消前置和完整后置；取消装备区不吞掉独立判定区请求。
	var steps: Array[Callable] = []
	for operation_index: int in range(operations.size()):
		steps.append(_prepare.bind(operation_index))
		steps.append(_before.bind(operation_index))
		steps.append(_read_before.bind(operation_index))
	_sequence_id = _host.run_rule_sequence(steps, context)


## 每个提交边界重新按稳定ID读取原武将；死亡或换将不能套用旧区域请求。
func _player(sequence: RuleStepSequence) -> PlayerState:
	# 当前原角色；后置已经换将时仍保留本次事实，但停止下一项区域操作。
	var player: PlayerState = _service._get_player(int(sequence.context.player_id))
	return player if player != null and player.alive and player.character_generation == int(sequence.context.generation) else null


## 来源区域根对象的稳定快照；复合材料内部不另外占用栏位或判定条目。
func _members(player: PlayerState, operation: Dictionary) -> Array[Dictionary]:
	# 按标准区域顺序记录的根实体；包括逻辑定义和全部原材料以校验异步期间是否被替换。
	var members: Array[Dictionary] = []
	if not bool(operation.abolished):
		return members
	if str(operation.kind) == "equipment":
		for slot: String in operation.changed_slots as Array:
			# 当前栏位实体；空栏位没有任何牌要支付。
			var card: CardInstance = player.equipment.get(slot) as CardInstance
			if card != null:
				members.append({"uid":card.uid, "definition_id":card.definition_id, "slot":slot, "physical_uids":card.get_physical_card_uids()})
	else:
		for card: CardInstance in player.judgment_area:
			members.append({"uid":card.uid, "definition_id":card.definition_id, "slot":"", "physical_uids":card.get_physical_card_uids()})
	return members


## 幂等项不创建窗口；前置锁定真实待改变栏位与原区域成员，禁止取出后再等待。
func _prepare(sequence: RuleStepSequence, operation_index: int) -> void:
	_movements.clear()
	sequence.waiting_event = null
	# 当前区域操作；仅本内容持有的可序列化字典。
	var operation: Dictionary = sequence.context.operations[operation_index]
	operation["active"] = false
	operation["committed"] = false
	# 区域所属玩家；死亡或无效玩家不建立新的栏位状态。
	var player: PlayerState = _player(sequence)
	if player == null:
		return
	# 本次确实要改变的栏位；重复废除或重复恢复幂等无事发生。
	var changed_slots: Array[String] = []
	if str(operation.kind) == "equipment":
		for slot: String in operation.slots as Array:
			if player.is_equipment_slot_abolished(slot) != bool(operation.abolished):
				changed_slots.append(slot)
		if changed_slots.is_empty():
			return
	elif player.judgment_area_abolished == bool(operation.abolished):
		return
	operation["active"] = true
	operation["changed_slots"] = changed_slots
	operation["members"] = _members(player, operation)
	# 废除时将离开区域的实体UID；恢复时固定为空数组且不找回旧牌。
	var discarded_card_uids: Array[int] = []
	for member: Dictionary in operation.members as Array:
		discarded_card_uids.append_array(_host._int_array(member.physical_uids))
	# 区域公开上下文；只保存基础可序列化数据，供技能、联机和回放共用。
	var timing_data: Dictionary = {"slots":changed_slots.duplicate(), "abolished":bool(operation.abolished), "reason":str(sequence.context.reason), "source_player_id":int(sequence.context.source_id), "card_uids":discarded_card_uids}
	operation["data"] = timing_data


## 区域废除前窗口只发一次；恢复没有对应Before目录，直接进入实际提交。
func _before(sequence: RuleStepSequence, operation_index: int) -> void:
	# 原操作；无实际变化时不派发冗余事件。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if bool(operation.active) and bool(operation.abolished) and _player(sequence) != null:
		_host.emit_sequence_timing(sequence, "disableEquipBefore" if str(operation.kind) == "equipment" else "disableJudgeBefore", int(sequence.context.player_id), int(sequence.context.source_id), int(sequence.context.player_id), operation.data, int(sequence.context.event_id))


## 全部前置完成后才能准备实体移牌；任何取消都保留原标志、实体及持续实例。
func _read_before(sequence: RuleStepSequence, operation_index: int) -> void:
	# 当前操作；该字段只属于原区域请求。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if sequence.waiting_event != null:
		if sequence.waiting_event.cancelled or sequence.waiting_event.neutralized:
			operation.active = false
		sequence.waiting_event = null
	if not _valid(sequence, operation):
		return
	# 区域内各牌前置先完整通过；不使用失败后的恢复或强制清空。
	var steps: Array[Callable] = []
	for member_index: int in range((operation.members as Array).size()):
		_movements.append(CardMoveResolutionService.new(_host))
		steps.append(_prepare_member.bind(operation_index, member_index))
	steps.append(_commit.bind(operation_index))
	for member_index: int in range((operation.members as Array).size()):
		steps.append(_loss_effect.bind(operation_index, member_index))
		steps.append(_finish_member.bind(operation_index, member_index))
		steps.append(_member_batch.bind(operation_index, member_index))
	steps.append(_after.bind(operation_index))
	sequence.insert_steps(steps)


## 等待期间角色、区域标志或卡集合改变时原请求失效，不清理后来进入区域的新牌。
func _valid(sequence: RuleStepSequence, operation: Dictionary) -> bool:
	if not bool(operation.get("active", false)):
		return false
	# 当前原角色；以准备时的区域集合为准，不使用同座位的新武将。
	var player: PlayerState = _player(sequence)
	if player == null:
		return false
	if str(operation.kind) == "equipment":
		for slot: String in operation.changed_slots as Array:
			if player.is_equipment_slot_abolished(slot) == bool(operation.abolished):
				return false
	elif player.judgment_area_abolished == bool(operation.abolished):
		return false
	return _members(player, operation) == operation.members


## 每张lose/discard前置可插入并取消；所有牌都保持原区域，直到整组校验通过。
func _prepare_member(sequence: RuleStepSequence, operation_index: int, member_index: int) -> void:
	# 原区域操作；任一早先材料不通过时不继续后面的前置。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if not _valid(sequence, operation):
		return
	for previous_index: int in range(member_index):
		if not _movements[previous_index].prepared:
			return
	# 当前根实体；处理复合材料仍由唯一CardMove服务负责。
	var member: Dictionary = operation.members[member_index]
	# 每张移牌仍关联cardsDiscard历史；区域废除不绕开既有实体回收记录。
	var event_id: int = _host._record_runtime_event("cardsDiscard", "card_move", {"card_uids":(member.physical_uids as Array).duplicate(), "reason":"zone_abolition"}, {}, int(sequence.context.event_id))
	_movements[member_index].begin(sequence, int(member.uid), "discard_pile", -1, "zone_abolition", event_id, "", [] as Array[int], false, false, -2, false, true, true)


## 无规则回调的区域与实体提交；先验证全部移动，再修改标志并移牌，不建立回滚补偿。
func _commit(sequence: RuleStepSequence, operation_index: int) -> void:
	# 当前区域操作；前置改变了集合就直接停止。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if not _valid(sequence, operation):
		return
	for movement: CardMoveResolutionService in _movements:
		if not movement.can_commit():
			return
	# 提交时原角色；本同步块内没有玩法回调，不可能再换将。
	var player: PlayerState = _player(sequence)
	if str(operation.kind) == "equipment":
		for slot: String in operation.changed_slots as Array:
			player.set_equipment_slot_abolished(slot, bool(operation.abolished))
	else:
		player.judgment_area_abolished = bool(operation.abolished)
	# 真实离区实体；每张已完成前置，复合材料一次恢复并完整移动。
	var discarded_card_uids: Array[int] = []
	for movement: CardMoveResolutionService in _movements:
		if not movement.commit_prepared(sequence, false):
			_host._record_settlement_fault("zone_group_commit_failed", {"player_id":player.player_id, "kind":str(operation.kind)})
			return
		discarded_card_uids.append_array(_host._int_array(movement.result.get("card_uids", [])))
	if str(operation.kind) == "equipment":
		for member: Dictionary in operation.members as Array:
			_host._uninstall_card_runtime(int(member.uid))
	operation.committed = true
	operation.data.card_uids = discarded_card_uids.duplicate()
	success = true
	result.success = true
	count += (operation.changed_slots as Array).size() if str(operation.kind) == "equipment" else 1
	(result.card_uids as Array).append_array(discarded_card_uids)
	if str(operation.kind) == "equipment":
		(result.changed_slots as Array).append_array(operation.changed_slots as Array)
		_service._append_equipment_history(player, _host._string_array(operation.changed_slots), bool(operation.abolished), str(sequence.context.reason), int(sequence.context.source_id), discarded_card_uids)
		_host.add_log("%s%s了%s。" % [_host.format_player_state_log_name(player), "废除" if bool(operation.abolished) else "恢复", _service._format_equipment_slot_names(_host._string_array(operation.changed_slots))])
	else:
		result.judgment_changed = true
		_service._append_judgment_history(player, bool(operation.abolished), str(sequence.context.reason), int(sequence.context.source_id), discarded_card_uids)
		_host.add_log("%s%s了判定区。" % [_host.format_player_state_log_name(player), "废除" if bool(operation.abolished) else "恢复"])


## 全部区域实体已离区后逐项执行装备自身规则；回复和清粮完成前不发布本牌后置。
func _loss_effect(sequence: RuleStepSequence, operation_index: int, member_index: int) -> void:
	# 已提交的原操作；后置通知不因随后状态变化撤销事实。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if not bool(operation.committed) or str(operation.kind) != "equipment":
		return
	# 原逻辑装备定义；材料恢复后不能按原普通牌名查离区规则。
	var member: Dictionary = operation.members[member_index]
	# 原角色仍为同一代次才执行其装备离区效果，运行时已在原子提交中卸载。
	var player: PlayerState = _player(sequence)
	if player != null:
		_host._trigger_equipment_leave_effect(player, str(member.definition_id), true)


## 每张End/After完整结束后才处理下一张；未提交的区域不产生离区事实。
func _finish_member(sequence: RuleStepSequence, operation_index: int, member_index: int) -> void:
	if bool(sequence.context.operations[operation_index].committed):
		_movements[member_index].finish_prepared_move(sequence)


## 保持单装备弃置动作的批次语义；判定牌清理不伪造主动弃置批次。
func _member_batch(sequence: RuleStepSequence, operation_index: int, member_index: int) -> void:
	# 本操作事实；只对实际装备原材料发送弃置批次。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if not bool(operation.committed) or str(operation.kind) != "equipment":
		return
	# 已成功物理成员；无材料逻辑装备不会制造弃牌批次。
	var card_uids: Array[int] = _host._int_array(_movements[member_index].result.get("card_uids", []))
	if card_uids.is_empty():
		return
	# 唯一弃置批次；与原单装备弃置端口使用同一计数器。
	var batch_id: int = int(_host._next_discard_batch_id)
	_host._next_discard_batch_id += 1
	_host.emit_sequence_timing(sequence, "cardsDiscardedBatchAfter", int(sequence.context.player_id), int(sequence.context.player_id), -1, {"card_uids":card_uids, "batch_size":card_uids.size(), "discard_batch_id":batch_id, "source_player_id":int(sequence.context.player_id), "reason":"zone_abolition"}, int(sequence.context.event_id))


## 整个区域全部后置及离区子效果结束后发布唯一After；恢复只开放区域，不返还牌。
func _after(sequence: RuleStepSequence, operation_index: int) -> void:
	# 已提交区域事实；不依据后置期间的新角色状态重写它。
	var operation: Dictionary = sequence.context.operations[operation_index]
	if not bool(operation.committed):
		return
	_host.emit_sequence_timing(sequence, ("disableEquipAfter" if bool(operation.abolished) else "enableEquipAfter") if str(operation.kind) == "equipment" else ("disableJudgeAfter" if bool(operation.abolished) else "enableJudgeAfter"), int(sequence.context.player_id), int(sequence.context.source_id), int(sequence.context.player_id), operation.data, int(sequence.context.event_id))
	_host._emit_state()
