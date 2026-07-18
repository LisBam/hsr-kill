class_name CardInstance
extends RefCounted

## 单张实体牌的运行时结构。配置定义与实体状态分离，同名牌可拥有不同花色、点数与位置。

## 下一张实体牌的递增序号；只用于本地运行时生成稳定唯一 ID。
static var _next_uid: int = 1

## 当前实体牌的唯一 ID；状态同步与操作指令必须使用此值而非数组下标。
var uid: int = 0

## 当前实体牌引用的配置 ID；效果与显示名称均通过该 ID 查询。
var definition_id: String = ""

## 当前实体牌的花色；可取 spade、heart、club、diamond。
## 多张实体牌组成的无花色虚拟牌使用 none，避免错误继承任一材料牌颜色。
var suit: String = "spade"

## 当前实体牌的点数；范围为1至13，其中1、11、12、13对应A、J、Q、K。
## 无点数虚拟牌使用0；规则判断不得把0视为任何实体牌点数。
var rank: int = 1

## 当前实体牌所在区域；默认在牌堆，移动逻辑会维护该字段。
var zone: String = "draw_pile"

## 当前实体牌的所属玩家 ID；公共区域使用 -1。
var owner_id: int = -1

## 已知该实体牌完整牌面的玩家 ID 集合；手牌移动和公开展示由移牌服务维护。
var known_to: Array[int] = []

## 是否已经发生公开展示；公开牌面不会因后续进入公共区域而重新变为未知。
var shown: bool = false

## 仅对某一持有者私密可见的玩家 ID；公开牌或公共区域使用 -1。
var private_owner_id: int = -1

## 当前手牌视为效果生效前的原始卡牌定义ID；空字符串表示实体没有临时手牌牌名，离开手牌区时恢复该定义。
var hand_view_as_original_definition_id: String = ""

## 赋予当前手牌视为效果的技能ID；只用于规则追踪与清理，不改变技能归属或实体所有者。
var hand_view_as_source_skill_id: String = ""


## 创建实体牌并分配唯一 ID；调用方需提供已校验的配置 ID、花色与点数。
func _init(card_definition_id: String = "", card_suit: String = "spade", card_rank: int = 1) -> void:
	uid = _next_uid
	_next_uid += 1
	definition_id = card_definition_id
	suit = card_suit
	rank = card_rank


## 返回牌的颜色；红桃与方块为红色，黑桃与梅花为黑色，无花色虚拟牌返回 none。
func get_color() -> String:
	if suit == "heart" or suit == "diamond":
		return "red"
	if suit == "spade" or suit == "club":
		return "black"
	return "none"


## 将当前手牌临时视为指定逻辑牌；重复赋予时始终保留最初的实体定义，避免连续转移覆盖真实牌名。
func set_hand_view_as(view_as_definition_id: String, source_skill_id: String) -> bool:
	if zone != "hand" or view_as_definition_id.is_empty() or definition_id == view_as_definition_id:
		return false
	if hand_view_as_original_definition_id.is_empty():
		hand_view_as_original_definition_id = definition_id
	definition_id = view_as_definition_id
	hand_view_as_source_skill_id = source_skill_id
	return true


## 清除当前实体的手牌视为效果并恢复原始定义；返回清除前实际使用的逻辑牌ID。
func clear_hand_view_as() -> String:
	# 清除前逻辑牌ID；响应与虚拟使用流程可据此继续结算已经声明的牌效。
	var previous_view_as_definition_id: String = definition_id
	if not hand_view_as_original_definition_id.is_empty():
		definition_id = hand_view_as_original_definition_id
	hand_view_as_original_definition_id = ""
	hand_view_as_source_skill_id = ""
	return previous_view_as_definition_id


## 返回当前实体是否拥有尚未清理的手牌视为效果；区域移动组件只通过本查询决定是否恢复真实牌名。
func has_hand_view_as() -> bool:
	return not hand_view_as_original_definition_id.is_empty()


## 序列化为网络安全字典；不包含任何对象引用或可执行回调。
func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"definition_id": definition_id,
		"suit": suit,
		"rank": rank,
		"color": get_color(),
		"zone": zone,
		"owner_id": owner_id,
		"known_to": known_to.duplicate(),
		"shown": shown,
		"private_owner_id": private_owner_id,
	}
