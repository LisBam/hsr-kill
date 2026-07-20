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

## 最近一次离开手牌时的原实体定义ID；仅供处理区与弃牌堆展示保留来源牌面，不参与后续规则判定。
var last_hand_view_as_original_definition_id: String = ""

## 最近一次离开手牌时的视为逻辑定义ID；仅供处理区与弃牌堆展示保留本次视为牌名，不参与后续规则判定。
var last_hand_view_as_definition_id: String = ""


## 创建实体牌并分配唯一 ID；调用方需提供已校验的配置 ID、花色与点数。
## existing_uid 仅供网络快照、回放与规则续接恢复既有实体；默认-1会生成全新递增编号，运行时通常不动态指定。
func _init(card_definition_id: String = "", card_suit: String = "spade", card_rank: int = 1, existing_uid: int = -1) -> void:
	if existing_uid >= 0:
		uid = existing_uid
		# 后续新实体的安全起点；恢复较大 UID 时只推进游标防止碰撞，不把恢复动作计作一次新编号分配。
		_next_uid = maxi(_next_uid, existing_uid + 1)
	else:
		uid = _next_uid
		_next_uid += 1
	definition_id = card_definition_id
	suit = card_suit
	rank = card_rank


## 从网络安全快照恢复一张既有实体或逻辑响应代理；不会消耗新的 UID，区域与可见性字段按基础类型重建。
static func from_dict(data: Dictionary) -> CardInstance:
	# 恢复后的实体牌；稳定 UID 防止异步规则续接把同一响应误记为另一张新牌。
	var card: CardInstance = CardInstance.new(str(data.get("definition_id", "")), str(data.get("suit", "spade")), int(data.get("rank", 1)), int(data.get("uid", -1)))
	card.zone = str(data.get("zone", "draw_pile"))
	card.owner_id = int(data.get("owner_id", -1))
	card.known_to.clear()
	for player_id_variant: Variant in data.get("known_to", []) as Array:
		# 已知者稳定玩家 ID；异常类型统一转换为整数，重复项不会改变可见性语义。
		var player_id: int = int(player_id_variant)
		if not card.known_to.has(player_id):
			card.known_to.append(player_id)
	card.shown = bool(data.get("shown", false))
	card.private_owner_id = int(data.get("private_owner_id", -1))
	card.hand_view_as_original_definition_id = str(data.get("original_definition_id", ""))
	card.hand_view_as_source_skill_id = str(data.get("hand_view_as_source_skill_id", ""))
	card.last_hand_view_as_original_definition_id = str(data.get("presentation_original_definition_id", ""))
	card.last_hand_view_as_definition_id = str(data.get("view_as_definition_id", ""))
	return card


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
	# 离手展示来源；弃牌与处理区仍需保留原实体与本次视为牌名，规则定义本身会立刻恢复。
	last_hand_view_as_original_definition_id = hand_view_as_original_definition_id
	last_hand_view_as_definition_id = previous_view_as_definition_id
	if not hand_view_as_original_definition_id.is_empty():
		definition_id = hand_view_as_original_definition_id
	hand_view_as_original_definition_id = ""
	hand_view_as_source_skill_id = ""
	return previous_view_as_definition_id


## 返回当前实体是否拥有尚未清理的手牌视为效果；区域移动组件只通过本查询决定是否恢复真实牌名。
func has_hand_view_as() -> bool:
	return not hand_view_as_original_definition_id.is_empty()


## 清理已结束的视为牌展示来源；牌进入牌堆、手牌、装备、判定或木牛区域后不再保留旧一次性视为记录。
func clear_hand_view_as_presentation() -> void:
	last_hand_view_as_original_definition_id = ""
	last_hand_view_as_definition_id = ""


## 序列化为网络安全字典；不包含任何对象引用或可执行回调。
func to_dict() -> Dictionary:
	# 原始定义 ID；手牌处于视为状态时供表现层保留实体牌面名称，空字符串表示当前没有临时视为效果。
	var original_definition_id: String = hand_view_as_original_definition_id
	# 展示原始定义 ID；已清除手牌视为状态后仍保留到本次处理或弃牌展示结束。
	var presentation_original_definition_id: String = hand_view_as_original_definition_id if not hand_view_as_original_definition_id.is_empty() else last_hand_view_as_original_definition_id
	# 展示视为定义 ID；手牌中直接使用当前逻辑定义，离手后读取最近一次已结束的视为记录。
	var view_as_definition_id: String = definition_id if not hand_view_as_original_definition_id.is_empty() else last_hand_view_as_definition_id
	return {
		"uid": uid,
		"definition_id": definition_id,
		"original_definition_id": original_definition_id,
		"suit": suit,
		"rank": rank,
		"color": get_color(),
		"zone": zone,
		"owner_id": owner_id,
		"known_to": known_to.duplicate(),
		"shown": shown,
		"private_owner_id": private_owner_id,
		"presentation_original_definition_id": presentation_original_definition_id,
		"view_as_definition_id": view_as_definition_id,
	}
