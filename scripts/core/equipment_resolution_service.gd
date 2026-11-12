extends RefCounted

## 装备安装、替换与携带附属牌的整体转移；复用逐张移牌窗口，统一持有整组提交边界。

## 当前权威宿主；只在运行期持有，不进入上下文或网络快照。
var _host: Object

## 每张成员的前置与后置游标；所有Before/Begin完成后才提交整组实体。
var _movements: Array[CardMoveResolutionService] = []

## 整组实体是否已实际提交；After可以继续产生子效果，不以此字段替代completed。
var success: bool = false

## 全部后置和完成通知是否结束；调用方在下一父步骤读取最终结果。
var completed: bool = false


## 每次请求创建独立实例；服务不拥有宿主的生命周期。
func _init(host: Object) -> void:
	_host = host


## 安装处理区装备或整体转移原装备；附件UID只来自调用时的有限快照。
func begin(player_id: int, card_uid: int, slot: String, reason: String = "equip", attachment_uids: Array[int] = [], attachment_zone: String = "") -> void:
	# 原实体位置；后续不得把别的来源或同槽新牌当作本次装备。
	var source: Dictionary = _host.get_card_location_snapshot(card_uid)
	# 原目标角色；等待期间换将使整组请求失效。
	var target: PlayerState = _host.state.get_player(player_id) if _host.state != null else null
	# 转移模式；空附件区表示普通装备安装，即使转移没有粮也要明确声明附属区。
	var transferring: bool = not attachment_zone.is_empty()
	if source.is_empty() or target == null or not target.alive or target.out_of_game or not target.is_valid_equipment_slot(slot) or target.is_equipment_slot_abolished(slot) or (not transferring and str(source.get("zone", "")) != "processing") or (transferring and (attachment_zone != "wooden_ox" or str(source.get("zone", "")) != "equipment" or int(source.get("owner_id", -1)) == player_id)):
		if not transferring:
			_set_use_destination(card_uid, false)
		completed = true
		return
	# 稳定成员顺序；装备先于附件，每份实体最多参与一次。
	var member_uids: Array[int] = [card_uid]
	for attachment_uid: int in attachment_uids:
		if not member_uids.has(attachment_uid):
			member_uids.append(attachment_uid)
	# 整组规则快照；不保存牌实体、角色对象或可变源数组。
	var data: Dictionary = {"sequence_kind":"equipment_group", "target_id":player_id, "target_generation":target.character_generation, "card_uid":card_uid, "slot":slot, "reason":reason, "source":source, "transferring":transferring, "attachment_zone":attachment_zone, "member_uids":member_uids, "event_id":_host._current_rule_parent_event_id()}
	# 前置逐张等待；换装旧牌在所有新成员前置通过后才尝试置入弃牌堆。
	var steps: Array[Callable] = []
	for member_index: int in range(member_uids.size()):
		_movements.append(CardMoveResolutionService.new(_host))
		steps.append(_prepare_member.bind(member_index))
	steps.append(_replace_old_equipment)
	steps.append(_commit_group)
	for member_index: int in range(member_uids.size()):
		steps.append(_finish_member.bind(member_index))
	steps.append(_finish)
	if _host.run_rule_sequence(steps, data) < 0:
		completed = true


## 原来源、原目标与原附属牌集合均保持有效；不在等待之后接受新增附件替换请求快照。
func _valid_group(sequence: RuleStepSequence) -> bool:
	# 原主牌位置；完整比较稳定快照中的区域、归属、槽位与角色代次。
	var current_source: Dictionary = _host.get_card_location_snapshot(int(sequence.context.card_uid))
	# 原来源字段；只比较身份事实，牌面变化由移牌窗口自行处理。
	for key: String in ["zone", "owner_id", "slot", "character_generation"]:
		if current_source.get(key) != (sequence.context.source as Dictionary).get(key):
			return false
	# 原接收者；不能覆盖死亡、离场、换将或已废除的栏位。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id))
	if target == null or not target.alive or target.out_of_game or target.character_generation != int(sequence.context.target_generation) or target.is_equipment_slot_abolished(str(sequence.context.slot)):
		return false
	if not bool(sequence.context.transferring):
		return true
	# 原装备持有者；死亡后交给死亡清理流程，不继续旧主动转移。
	var source: PlayerState = _host.state.get_player(int(sequence.context.source.owner_id))
	if source == null or not source.alive or source.out_of_game:
		return false
	# 当前附属实体；与声明成员严格相等，防止箱已走而新粮留在原角色。
	var actual_uids: Array[int] = []
	for card: CardInstance in source.wooden_ox_storage:
		actual_uids.append(card.uid)
	if actual_uids.size() != (sequence.context.member_uids as Array).size() - 1:
		return false
	for card_uid: int in actual_uids:
		if not (sequence.context.member_uids as Array).has(card_uid):
			return false
	return true


## 只准备各成员的前置窗口，任何取消都保留原区域；附件不伪造gain手牌时机。
func _prepare_member(sequence: RuleStepSequence, member_index: int) -> void:
	if not _valid_group(sequence):
		return
	for previous_index: int in range(member_index):
		if not _movements[previous_index].prepared:
			return
	# 当前成员真实位置；附件必须仍属于原装备持有者。
	var location: Dictionary = _host.get_card_location_snapshot(int(sequence.context.member_uids[member_index]))
	if member_index > 0 and (str(location.get("zone", "")) != str(sequence.context.attachment_zone) or int(location.get("owner_id", -1)) != int(sequence.context.source.owner_id)):
		return
	_movements[member_index].begin(sequence, int(sequence.context.member_uids[member_index]), "equipment" if member_index == 0 else str(sequence.context.attachment_zone), int(sequence.context.target_id), str(sequence.context.reason) if member_index == 0 else "equipment_attachment_transfer", int(sequence.context.event_id), str(sequence.context.slot) if member_index == 0 else "", [] as Array[int], false, false, -2, false, true, true)


## 所有新成员前置通过才支付旧装备离区；其回复、清粮和End/After必须在新装备提交前完成。
func _replace_old_equipment(sequence: RuleStepSequence) -> void:
	if not _valid_group(sequence):
		return
	for movement: CardMoveResolutionService in _movements:
		if not movement.can_commit(true):
			return
	# 旧栏实体；离区被取消或子效果填入新装备时，后一步自然拒绝安装。
	var old_card: CardInstance = _host.get_equipment_card(int(sequence.context.target_id), str(sequence.context.slot))
	if old_card != null:
		_host.begin_card_move(old_card.uid, "discard_pile", -1, "equipment_replacement", {"source_player_id":int(sequence.context.target_id), "allowed_source_zones":["equipment"]})


## 无规则派发的整组提交；先验证全部成员，再一次移动装备和粮，之后安装持续实例。
func _commit_group(sequence: RuleStepSequence) -> void:
	if not _valid_group(sequence):
		return
	for movement: CardMoveResolutionService in _movements:
		if not movement.can_commit():
			return
	for movement: CardMoveResolutionService in _movements:
		if not movement.commit_prepared(sequence, false):
			_host._record_settlement_fault("equipment_group_commit_failed", {"card_uid":int(sequence.context.card_uid)})
			return
	success = true
	# 已装入目标区域的主装备；持续实例在所有成员实际移动后、后置窗口之前安装。
	var location: Dictionary = _host._find_card_location_by_uid(int(_movements[0].result.get("card_uid", sequence.context.card_uid)))
	_host._install_card_runtime(location.get("card") as CardInstance, int(sequence.context.target_id))
	if not bool(sequence.context.transferring):
		_host.request_effect_voice(int(sequence.context.target_id), _host._resolve_equipment_effect_id(str(sequence.context.slot)))


## 所有实体均已处于接收者区域后，按原成员顺序完整等待每张End/After。
func _finish_member(sequence: RuleStepSequence, member_index: int) -> void:
	_movements[member_index].finish_prepared_move(sequence)


## 完整组请求最终结果；真实用牌安装失败时让原生父牌正常回收仍在处理区的材料。
func _finish(sequence: RuleStepSequence) -> void:
	if not bool(sequence.context.transferring):
		_set_use_destination(int(sequence.context.card_uid), success)
	if success:
		if bool(sequence.context.transferring):
			_host.add_log("%s将装备及附属牌转移给%s。" % [_host.format_player_log_name(int(sequence.context.source.owner_id)), _host.format_player_log_name(int(sequence.context.target_id))])
		else:
			_host.add_log("%s装备了%s。" % [_host.format_player_log_name(int(sequence.context.target_id)), _host.format_card_log_name((_host._find_card_location_by_uid(int(_movements[0].result.get("card_uid", sequence.context.card_uid))) as Dictionary).get("card"))])
	completed = true


## 原生整牌收尾读取实际安装结果；失败后仍在处理区的材料由父用牌统一回收。
func _set_use_destination(card_uid: int, installed: bool) -> void:
	# 本次用牌内容；直接独立安装不存在此上下文。
	var use_context: Dictionary = _host._card_use_contexts.get(card_uid, {}) as Dictionary
	if not use_context.is_empty():
		use_context["destination"] = "equipment" if installed else "discard"
		use_context["content_complete"] = true
