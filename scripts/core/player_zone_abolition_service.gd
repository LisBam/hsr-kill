class_name PlayerZoneAbolitionService
extends RefCounted

## 玩家区域废除权威服务。组件统一编排单装备栏、整个装备区与判定区的时机、状态、弃牌、日志和历史。

## 五种装备栏的中文显示名；日志按PlayerState的稳定栏位顺序输出。
const EQUIPMENT_SLOT_DISPLAY_NAMES: Dictionary = {
	"weapon":"武器栏",
	"armor":"防具栏",
	"offensive_mount":"进攻坐骑栏",
	"defensive_mount":"防御坐骑栏",
	"treasure":"宝物栏",
}

## 当前绑定的对局控制器；服务只通过稳定规则端口移牌和派发时机，不访问界面节点。
var _host: Object


## 绑定当前对局控制器；新局重建服务时替换状态来源。
func configure(match_host: Object) -> void:
	_host = match_host


## 同步设置整个装备区与判定区；整个装备区等价于同时设置全部五个基础装备栏。
func set_zones_abolished(player_id: int, equipment_abolished: bool, judgment_abolished: bool, reason: String = "", source_player_id: int = -1) -> bool:
	# 装备区是否实际改变；单栏服务会自行跳过已处于目标状态的栏位。
	var equipment_changed: bool = set_equipment_slots_abolished(player_id, PlayerState.EQUIPMENT_SLOT_ORDER, equipment_abolished, reason, source_player_id)
	# 判定区是否实际改变；与装备栏事件相互独立，任一改变即算本次调用成功。
	var judgment_changed: bool = set_judgment_area_abolished(player_id, judgment_abolished, reason, source_player_id)
	return equipment_changed or judgment_changed


## 废除或恢复指定装备栏；废除前可被disableEquipBefore取消，生效后派发对应After时机。
func set_equipment_slots_abolished(player_id: int, slots: Array[String], abolished: bool, reason: String = "", source_player_id: int = -1) -> bool:
	# 区域所属玩家；死亡或无效玩家不建立新的栏位状态。
	var player: PlayerState = _get_player(player_id)
	if player == null or not player.alive:
		return false
	# 参数中的合法栏位；去重并按固定顺序输出，避免日志与回放受调用方数组顺序影响。
	var normalized_slots: Array[String] = _normalize_equipment_slots(slots)
	# 本次确实要改变的栏位；重复废除或重复恢复幂等无事发生。
	var changed_slots: Array[String] = []
	for slot: String in normalized_slots:
		if player.is_equipment_slot_abolished(slot) != abolished:
			changed_slots.append(slot)
	if changed_slots.is_empty():
		return false
	# 本次废除的来源角色；未指定时以区域所属玩家作为稳定回退。
	var resolved_source_player_id: int = _resolve_source_player_id(player_id, source_player_id)
	# 废除时将离开装备区的实体UID；恢复栏位时固定为空数组且不找回旧牌。
	var discarded_card_uids: Array[int] = []
	if abolished:
		for slot: String in changed_slots:
			if player.equipment.has(slot):
				discarded_card_uids.append((player.equipment[slot] as CardInstance).uid)
	# 装备栏事件公开上下文；只保存基础可序列化数据，供技能、联机和回放共用。
	var timing_data: Dictionary = {
		"slots":changed_slots.duplicate(),
		"abolished":abolished,
		"reason":reason,
		"source_player_id":resolved_source_player_id,
		"card_uids":discarded_card_uids.duplicate(),
	}
	if abolished:
		# 装备栏废除前时机；取消或无效化时不改状态、不弃牌也不记录历史。
		var before_event: RuleEvent = _host.call("emit_rule_timing", "disableEquipBefore", player_id, resolved_source_player_id, player_id, timing_data) as RuleEvent
		if before_event != null and (before_event.cancelled or before_event.neutralized):
			return false
	for slot: String in changed_slots:
		player.set_equipment_slot_abolished(slot, abolished)
	if abolished:
		for slot: String in changed_slots:
			_host.call("discard_equipment_slot", player_id, slot, true)
		_host.call("emit_rule_timing", "disableEquipAfter", player_id, resolved_source_player_id, player_id, timing_data)
	else:
		_host.call("emit_rule_timing", "enableEquipAfter", player_id, resolved_source_player_id, player_id, timing_data)
	_append_equipment_history(player, changed_slots, abolished, reason, resolved_source_player_id, discarded_card_uids)
	_host.call("add_log", "%s%s了%s。" % [_host.call("format_player_state_log_name", player), "废除" if abolished else "恢复", _format_equipment_slot_names(changed_slots)])
	return true


## 废除或恢复判定区；废除时既有延时锦囊通过标准弃牌移动离区。
func set_judgment_area_abolished(player_id: int, abolished: bool, reason: String = "", source_player_id: int = -1) -> bool:
	# 判定区所属玩家；死亡或无效玩家不修改区域状态。
	var player: PlayerState = _get_player(player_id)
	if player == null or not player.alive or player.judgment_area_abolished == abolished:
		return false
	# 本次判定区变化的来源玩家；未指定时稳定回退为区域所属者。
	var resolved_source_player_id: int = _resolve_source_player_id(player_id, source_player_id)
	# 废除时将离开判定区的实体UID；恢复时为空且不返还旧牌。
	var discarded_card_uids: Array[int] = []
	if abolished:
		for card: CardInstance in player.judgment_area:
			discarded_card_uids.append(card.uid)
	# 判定区事件公开上下文；与装备栏使用相同的来源、原因和实体UID字段。
	var timing_data: Dictionary = {
		"abolished":abolished,
		"reason":reason,
		"source_player_id":resolved_source_player_id,
		"card_uids":discarded_card_uids.duplicate(),
	}
	if abolished:
		# 判定区废除前时机；取消或无效化时保留全部延时锦囊与原区域状态。
		var before_event: RuleEvent = _host.call("emit_rule_timing", "disableJudgeBefore", player_id, resolved_source_player_id, player_id, timing_data) as RuleEvent
		if before_event != null and (before_event.cancelled or before_event.neutralized):
			return false
	player.judgment_area_abolished = abolished
	if abolished:
		_host.call("discard_all_judgment_area_cards", player_id)
		_host.call("emit_rule_timing", "disableJudgeAfter", player_id, resolved_source_player_id, player_id, timing_data)
	else:
		_host.call("emit_rule_timing", "enableJudgeAfter", player_id, resolved_source_player_id, player_id, timing_data)
	_append_judgment_history(player, abolished, reason, resolved_source_player_id, discarded_card_uids)
	_host.call("add_log", "%s%s了判定区。" % [_host.call("format_player_state_log_name", player), "废除" if abolished else "恢复"])
	return true


## 返回当前可操作的玩家状态；无对局、已结束或ID不存在时返回null。
func _get_player(player_id: int) -> PlayerState:
	if _host == null or _host.get("state") == null or bool(_host.state.game_over):
		return null
	return _host.state.get_player(player_id) as PlayerState


## 去重并按标准顺序返回合法装备栏ID；未知栏位被忽略而不注入状态。
func _normalize_equipment_slots(slots: Array[String]) -> Array[String]:
	# 规范栏位结果；遍历标准顺序自然实现去重与稳定排序。
	var result: Array[String] = []
	for slot: String in PlayerState.EQUIPMENT_SLOT_ORDER:
		if slots.has(slot):
			result.append(slot)
	return result


## 解析事件来源玩家；显式非负ID优先，否则使用区域所属者。
func _resolve_source_player_id(player_id: int, source_player_id: int) -> int:
	return source_player_id if source_player_id >= 0 else player_id


## 把装备栏ID数组转为可读中文列表；空数组使用“装备栏”安全回退。
func _format_equipment_slot_names(slots: Array[String]) -> String:
	# 栏位中文名数组；与权威栏位顺序一致。
	var display_names: Array[String] = []
	for slot: String in slots:
		display_names.append(str(EQUIPMENT_SLOT_DISPLAY_NAMES.get(slot, "装备栏")))
	return "、".join(display_names) if not display_names.is_empty() else "装备栏"


## 记录一次单栏或整区装备栏变化；记录包含最终已废除集合供回放诊断。
func _append_equipment_history(player: PlayerState, changed_slots: Array[String], abolished: bool, reason: String, source_player_id: int, discarded_card_uids: Array[int]) -> void:
	_host.state.random_history.append({
		"kind":"equipment_slots_abolition",
		"player_id":player.player_id,
		"source_player_id":source_player_id,
		"abolished":abolished,
		"changed_slots":changed_slots.duplicate(),
		"abolished_equipment_slots":player.abolished_equipment_slots.duplicate(true),
		"equipment_area_abolished":player.equipment_area_abolished,
		"discarded_card_uids":discarded_card_uids.duplicate(),
		"reason":reason,
	})


## 记录一次判定区废除或恢复；离区卡牌UID供回放与问题定位追溯。
func _append_judgment_history(player: PlayerState, abolished: bool, reason: String, source_player_id: int, discarded_card_uids: Array[int]) -> void:
	_host.state.random_history.append({
		"kind":"judgment_area_abolition",
		"player_id":player.player_id,
		"source_player_id":source_player_id,
		"abolished":abolished,
		"discarded_card_uids":discarded_card_uids.duplicate(),
		"reason":reason,
	})
