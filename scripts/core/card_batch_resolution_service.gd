extends RefCounted

## 批量区域移牌；每张完整等待，批次结果归本对象所有，不借用跨异步边界的全局栈。

## 当前权威宿主；不写入快照。
var _host: Object

## 最近一张的移牌服务；后续步骤读取最终提交结果。
var _movement: CardMoveResolutionService

## 实际提交成功的牌数；completed为true后才是最终费用或收益。
var count: int = 0

## 实际成功支付的选中区域条目数；复合持久牌包含多份物理材料，费用必须用本字段核对选择是否全部成功。
var selected_count: int = 0

## 完整结束标志；批次After及其子内容结束后置true。
var completed: bool = false

## 成功移动的实体UID；不包含取消、重复或失效的选择。
var card_uids: Array[int] = []

## 构成弃置动作的成功实体；判定区置入弃牌堆不加入弃置批次。
var _discard_action_uids: Array[int] = []

## 可选费用接收者；只调用一次，接收实际提交数量，产生的子内容仍由本序列等待。
var _on_complete: Callable


## 绑定当前对局宿主。
func _init(host: Object) -> void:
	_host = host


## mode为discard或gain；zones限定来源区域，target_id是原持有者，receiver_id仅用于获得。
func begin(target_id: int, selected_uids: Array[int], mode: String, zones: Array[String], source_id: int = -1, receiver_id: int = -1, reason: String = "batch_move", on_complete: Callable = Callable(), allow_out_of_game: bool = false, trigger_loss_effects: bool = true) -> void:
	_on_complete = on_complete
	# 来源角色；换将后不能继续支付旧选择的费用。
	var target: PlayerState = _host.state.get_player(target_id)
	# 接收角色；获得操作必须保留原代次。
	var receiver: PlayerState = _host.state.get_player(receiver_id)
	# 本批次身份；复用现有单调计数器，不建立全局异步栈帧。
	var batch_id: int = int(_host._next_discard_batch_id) if mode == "discard" else int(_host._next_gain_batch_id)
	if mode == "discard":
		_host._next_discard_batch_id += 1
	else:
		_host._next_gain_batch_id += 1
	# 稳定批次上下文；逐张查回实体，等待时不保留区域数组引用。
	var data: Dictionary = {"sequence_kind":"card_batch", "target_id":target_id, "generation":target.character_generation if target != null else -1, "receiver_id":receiver_id, "receiver_generation":receiver.character_generation if receiver != null else -1, "source_id":source_id, "mode":mode, "zones":zones.duplicate(), "reason":reason, "batch_id":batch_id, "event_id":_host._current_rule_parent_event_id(), "allow_out_of_game":allow_out_of_game, "trigger_loss_effects":trigger_loss_effects}
	# 每份选择最多移动一次；按玩家选择顺序执行。
	var seen: Array[int] = []
	# 批次内容；先完整移动再登记结果，最后统一发送批次时机。
	var steps: Array[Callable] = []
	for card_uid: int in selected_uids:
		if not seen.has(card_uid):
			seen.append(card_uid)
			steps.append(_move.bind(card_uid))
			steps.append(_record.bind(card_uid))
	steps.append(_batch_after)
	steps.append(_notify)
	steps.append(_complete)
	if _host.run_rule_sequence(steps, data) < 0:
		_on_complete = Callable()
		completed = true


## 重查区域、代次与弃置保护；不预先从手牌或判定数组移除实体。
func _move(sequence: RuleStepSequence, card_uid: int) -> void:
	_movement = null
	# 原持有者；其存活状态由调用规则决定，死亡清理也允许移动原区域。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id))
	if int(sequence.context.target_id) >= 0 and (target == null or target.character_generation != int(sequence.context.generation)):
		return
	# 实时位置；旧候选已经离区则跳过。
	var location: Dictionary = _host._find_card_location_by_uid(card_uid)
	# 当前实体；不使用候选快照构造新牌。
	var card: CardInstance = location.get("card") as CardInstance
	if card == null or int(location.get("owner_id", -1)) != int(sequence.context.target_id) or not (sequence.context.zones as Array).has(str(location.get("zone", ""))):
		return
	if str(sequence.context.mode) == "discard" and not _host.can_discard_player_card(int(sequence.context.source_id), target.player_id, card, card.zone, str(location.get("slot", ""))):
		return
	if str(sequence.context.mode) == "gain":
		# 真实获得者；等待期间死亡、离场或换将则旧批次失效。
		var receiver: PlayerState = _host.state.get_player(int(sequence.context.receiver_id))
		if receiver == null or not receiver.alive or (receiver.out_of_game and not bool(sequence.context.allow_out_of_game)) or receiver.character_generation != int(sequence.context.receiver_generation):
			return
	sequence.insert_steps([_commit_move.bind(card_uid)])


## 通过唯一移牌服务执行所有窗口；取消不会提前剥离源区域。
func _commit_move(sequence: RuleStepSequence, card_uid: int) -> void:
	# 两个步骤之间也可能让出帧；必须继续核对最初批次的代次。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id))
	if int(sequence.context.target_id) >= 0 and (target == null or target.character_generation != int(sequence.context.generation)):
		return
	_movement = CardMoveResolutionService.new(_host)
	# 弃置有独立cardsDiscard历史；获得直接归本批次父事件。
	var event_id: int = int(sequence.context.event_id)
	if str(sequence.context.mode) == "discard":
		event_id = _host._record_runtime_event("cardsDiscard", "card_move", {"card_uids":[card_uid], "reason":str(sequence.context.reason)}, {}, event_id)
		_movement.begin(sequence, card_uid, "discard_pile", -1, str(sequence.context.reason), event_id, "", [], false, true, int(sequence.context.source_id), false, bool(sequence.context.trigger_loss_effects))
	else:
		# 公共牌堆定向检索沿用私有知识规则，角色区域转移保留已有公开知识。
		var location: Dictionary = _host._find_card_location_by_uid(card_uid)
		_movement.begin(sequence, card_uid, "hand", int(sequence.context.receiver_id), str(sequence.context.reason), event_id, "", [int(sequence.context.receiver_id)], str(location.get("zone", "")) in ["draw_pile", "discard_pile"], true, -2, bool(sequence.context.allow_out_of_game))


## 全部单牌窗口结束后只登记一次；嵌套批次由各自服务记录，不串入外层。
func _record(sequence: RuleStepSequence, card_uid: int) -> void:
	if _movement == null or not bool(_movement.result.get("success", false)):
		return
	# 实际物理成员；多材料持久牌离区会恢复并移动整组原实体。
	var moved_uids: Array[int] = _host._int_array(_movement.result.get("card_uids", [card_uid]))
	count += moved_uids.size()
	if not moved_uids.is_empty():
		selected_count += 1
	card_uids.append_array(moved_uids)
	if str(sequence.context.mode) == "discard" and str(_movement.result.get("from_zone", "")) in ["hand", "equipment", "wooden_ox"]:
		_discard_action_uids.append_array(moved_uids)
		_host.add_log("%s弃置了%s。" % [_host.format_player_log_name(int(sequence.context.target_id)), _host.format_card_log_name((_host._find_card_location_by_uid(card_uid) as Dictionary).get("card"))])


## 整批After只发送成功提交的UID；判定区置入弃牌堆不算弃置手牌/装备费用。
func _batch_after(sequence: RuleStepSequence) -> void:
	# 弃置批次排除判定区，获得批次包含全部成功牌。
	var batch_uids: Array[int] = card_uids if str(sequence.context.mode) == "gain" else _discard_action_uids
	if batch_uids.is_empty():
		return
	# 批次触发主体；获得使用接收者，弃置使用失去者。
	var player_id: int = int(sequence.context.receiver_id) if str(sequence.context.mode) == "gain" else int(sequence.context.target_id)
	# 批次事件数据；仅稳定事实进入触发器与回放。
	var data: Dictionary = {"card_uids":batch_uids.duplicate(), "reason":str(sequence.context.reason), "batch_size":batch_uids.size()}
	if str(sequence.context.mode) == "gain":
		data["gain_batch_id"] = int(sequence.context.batch_id)
		data["receiver_player_id"] = player_id
	else:
		data["discard_batch_id"] = int(sequence.context.batch_id)
		data["source_player_id"] = player_id
	_host.emit_sequence_timing(sequence, "cardsGainedBatchAfter" if str(sequence.context.mode) == "gain" else "cardsDiscardedBatchAfter", player_id, player_id, -1, data, int(sequence.context.event_id))


## 结果完成与明确空结果分离；调用方在后续规则步骤读取count。
func _complete(_sequence: RuleStepSequence) -> void:
	completed = true


## 费用接收只发生在整批After之后；调用时先取出，防止嵌套回调再次消费。
func _notify(_sequence: RuleStepSequence) -> void:
	if _on_complete.is_valid():
		# 接收者快照；释放服务对闭包的持有再进入用户内容。
		var callback: Callable = _on_complete
		_on_complete = Callable()
		if callback.get_object() is SkillDefinition and (not (callback.get_object() as SkillDefinition).matches_character_generation() or not (callback.get_object() as SkillDefinition).can_use_effect()):
			return
		callback.call(count)
