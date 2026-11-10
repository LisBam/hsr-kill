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
## 返回独立结果；装备区全部后置完成后才进入判定区，不同步读取待结算的bool。
func set_zones_abolished(player_id: int, equipment_abolished: bool, judgment_abolished: bool, reason: String = "", source_player_id: int = -1) -> RefCounted:
	# 装备区是否实际改变；单栏服务会自行跳过已处于目标状态的栏位。
	# 判定区是否实际改变；与装备栏事件相互独立，任一改变即算本次调用成功。
	var operations: Array[Dictionary] = [{"kind":"equipment", "slots":PlayerState.EQUIPMENT_SLOT_ORDER.duplicate(), "abolished":equipment_abolished}, {"kind":"judgment", "abolished":judgment_abolished}]
	return _request(player_id, operations, reason, source_player_id)


## 废除或恢复指定装备栏；废除前可被disableEquipBefore取消，生效后派发对应After时机。
func set_equipment_slots_abolished(player_id: int, slots: Array[String], abolished: bool, reason: String = "", source_player_id: int = -1) -> RefCounted:
	# 参数中的合法栏位；去重并按固定顺序输出，避免日志与回放受调用方数组顺序影响。
	var normalized_slots: Array[String] = _normalize_equipment_slots(slots)
	# 单区域请求；空集合由独立内容按幂等处理。
	var operations: Array[Dictionary] = [{"kind":"equipment", "slots":normalized_slots, "abolished":abolished}]
	return _request(player_id, operations, reason, source_player_id)


## 废除或恢复判定区；废除时既有延时锦囊通过标准弃牌移动离区。
func set_judgment_area_abolished(player_id: int, abolished: bool, reason: String = "", source_player_id: int = -1) -> RefCounted:
	# 判定区操作与装备区采用相同完成协议；实体清理由唯一移动服务执行。
	var operations: Array[Dictionary] = [{"kind":"judgment", "abolished":abolished}]
	return _request(player_id, operations, reason, source_player_id)


## 每个请求创建独立内容与结果；共享组件只保留静态规则和宿主，不共享异步游标。
func _request(player_id: int, operations: Array[Dictionary], reason: String, source_player_id: int) -> RefCounted:
	# 本次废除的来源角色；未指定时以区域所属玩家作为稳定回退。
	var resolved_source_player_id: int = _resolve_source_player_id(player_id, source_player_id)
	# 原请求的唯一结果；嵌套区域变化不会覆盖外层。
	var resolution: RefCounted = preload("res://scripts/core/zone_change_resolution_service.gd").new(_host, self)
	resolution.begin(player_id, operations, reason, resolved_source_player_id)
	return resolution


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
