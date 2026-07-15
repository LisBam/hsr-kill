class_name CardMoveEvent
extends RefCounted

## 统一实体牌移动记录。所有区域变化都携带来源、目的、可见性和关联规则事件。

## 移牌事件稳定 ID；由 CardMovementService 单调递增分配。
var move_id: int = -1

## 关联规则事件 ID；无运行时上下文时使用 -1。
var event_id: int = -1

## 关联父移牌事件 ID；连续移动没有父事件时使用 -1。
var parent_move_id: int = -1

## 本次移动的实体牌 UID 数组；数组顺序表示处理区和材料牌的稳定顺序。
var card_ids: Array[int] = []

## 移动前区域；支持 draw_pile、hand、equipment、judgment、processing、wooden_ox、discard_pile、void。
var from_zone: String = ""

## 移动后区域；同一套稳定区域名称用于查询、快照与回放。
var to_zone: String = ""

## 移动前持有者玩家 ID；公共区域使用 -1。
var source_player_id: int = -1

## 移动后持有者玩家 ID；公共区域使用 -1。
var target_player_id: int = -1

## 允许看到牌面的玩家 ID；空数组表示按实体牌公开/私密字段推断。
var visible_to: Array[int] = []

## 移牌原因；use、respond、gain、discard、equip、judge、wash 等使用稳定字符串。
var reason: String = ""

## 目标装备槽；非装备移动为空字符串。
var target_slot: String = ""

## 创建一条只保存基础数据的移牌记录；实际区域修改由 CardMovementService 完成。
func _init(card_uid_list: Array[int] = [], old_zone: String = "", new_zone: String = "", old_owner: int = -1, new_owner: int = -1, move_reason: String = "") -> void:
	card_ids = card_uid_list.duplicate()
	from_zone = old_zone
	to_zone = new_zone
	source_player_id = old_owner
	target_player_id = new_owner
	reason = move_reason


## 生成可写入 GameState、网络和回放的移牌快照。
func to_dict() -> Dictionary:
	return {
		"move_id": move_id,
		"event_id": event_id,
		"parent_move_id": parent_move_id,
		"card_ids": card_ids.duplicate(),
		"from_zone": from_zone,
		"to_zone": to_zone,
		"source_player_id": source_player_id,
		"target_player_id": target_player_id,
		"visible_to": visible_to.duplicate(),
		"reason": reason,
		"target_slot": target_slot,
	}
