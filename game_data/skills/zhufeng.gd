extends SkillDefinition

## 【逐风】技能源码。每次受到或造成伤害后永久缩短自己到其他角色的距离；已经全部为1时改为摸一张牌。

## 逐风在全体距离已经为1时改为摸取的牌数；固定1张。
const FULL_DISTANCE_DRAW_COUNT: int = 1

## 逐风每次正常发动减少的距离值；固定1点，并由距离规则服务保证最终距离最低为1。
const DISTANCE_REDUCTION_PER_USE: int = 1

## 逐风文本在武将牌左上角组合条目中的排序值；默认100，与安可的长期统计提示保持同层级。
const CORNER_TEXT_ORDER: int = 100

## 已实际缩短距离的逐风发动次数；默认0时不显示武将牌文本，摸牌分支不会增加该值。
var _distance_reduction_count: int = 0


## 写入锁定技静态信息；技能正文逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"zhufeng",
		"name":"逐风",
		"trigger":"damageEnd",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，当你受到或造成伤害后，你计算与其他角色的距离-1，若此时你与所有角色距离均为1，则改为摸一张牌。",
	})


## 订阅全局伤害结束时机；来源或目标任一为持有者时只结算一次。
func install() -> void:
	subscribe_timing("damageEnd", _on_damage_end, "global")


## 卸载技能时移除逐风自己的公开文本条目，不影响同一武将牌上的其他技能提示。
func uninstall() -> void:
	if host != null and host.has_method("remove_character_corner_text_entry"):
		host.call("remove_character_corner_text_entry", owner_player_id, _get_corner_entry_id())
	super()


## 受到或造成正数伤害后结算；当前已与所有其他角色距离为1时摸牌，否则累计一次距离缩短。
func _on_damage_end(event: RuleEvent) -> void:
	if event.source_id != owner_player_id and event.target_id != owner_player_id:
		return
	if int(event.data.get("amount", 0)) <= 0:
		return
	if _is_distance_one_to_every_other_player():
		announce_activation({"draw_count":FULL_DISTANCE_DRAW_COUNT, "distance_reduction_count":_distance_reduction_count})
		host.call("draw", owner_player_id, FULL_DISTANCE_DRAW_COUNT)
		return
	_distance_reduction_count += DISTANCE_REDUCTION_PER_USE
	_refresh_corner_text()
	announce_activation({"distance_reduction":DISTANCE_REDUCTION_PER_USE, "distance_reduction_count":_distance_reduction_count})


## 将持有者到任意其他角色的距离按累计次数减少；目标不存在时由上层距离服务负责返回安全值。
func modify_distance_to_target(target_id: int, current_distance: int) -> int:
	if target_id == owner_player_id:
		return current_distance
	return maxi(current_distance - _distance_reduction_count, 1)


## 判断持有者与每名其他存活在场角色的当前最终距离是否均为1；没有其他角色时不触发摸牌替代。
func _is_distance_one_to_every_other_player() -> bool:
	# 是否存在至少一名其他角色；避免单人异常状态把“所有角色”空集合误判为满足。
	var has_other_player: bool = false
	for player: PlayerState in host.state.players:
		if player.player_id == owner_player_id or not player.alive or player.out_of_game:
			continue
		has_other_player = true
		if host.card_rules.calculate_distance(owner_player_id, player.player_id) != 1:
			return false
	return has_other_player


## 按累计次数刷新武将牌左上角文本；0次保持隐藏，正数严格显示为“逐风 X”。
func _refresh_corner_text() -> void:
	if host == null or not host.has_method("set_character_corner_text_entry") or not host.has_method("remove_character_corner_text_entry"):
		return
	if _distance_reduction_count <= 0:
		host.call("remove_character_corner_text_entry", owner_player_id, _get_corner_entry_id())
	else:
		host.call("set_character_corner_text_entry", owner_player_id, _get_corner_entry_id(), "逐风 %d" % _distance_reduction_count, CORNER_TEXT_ORDER)


## 返回本技能实例的稳定武将牌文本条目ID；玩家ID让多名驭空各自维护独立计数。
func _get_corner_entry_id() -> String:
	return "zhufeng:%d" % owner_player_id
