class_name VirtualCard
extends RefCounted

## 逻辑牌描述。虚拟牌只表达视为牌的规则属性，实体材料牌仍由 CardInstance UID 独立记录。

## 虚拟牌稳定 ID；同一张逻辑牌在嵌套事件和回放中保持一致，默认 -1 表示未登记。
var virtual_id: int = -1

## 逻辑牌配置或视为牌名称；不一定对应一张真实牌堆配置。
var name: String = ""

## 逻辑牌花色；无花色虚拟牌使用 none。
var suit: String = "none"

## 逻辑牌点数；无点数虚拟牌使用0，不能当作实体牌点数参与判定。
var rank: int = 0

## 逻辑牌伤害属性；普通牌使用 normal，无属性视为牌使用空字符串。
var nature: String = ""

## 组成该逻辑牌的实体材料 UID；顺序保留玩家选择和失去牌历史。
var material_card_uids: Array[int] = []

## 技能或卡牌内容的扩展存储；必须是基础类型字典，禁止写入节点和 Callable。
var storage: Dictionary = {}


## 创建逻辑牌并复制实体材料数组；不创建或移动实体牌。
func _init(card_name: String = "", card_suit: String = "none", card_rank: int = 0, card_nature: String = "") -> void:
	name = card_name
	suit = card_suit
	rank = card_rank
	nature = card_nature


## 添加一张实体材料牌 UID；重复 UID 会被忽略，避免同一实体牌被虚拟牌重复引用。
func add_material(card_uid: int) -> void:
	if card_uid >= 0 and not material_card_uids.has(card_uid):
		material_card_uids.append(card_uid)


## 生成可序列化逻辑牌快照；实体材料只输出 UID，不泄露 CardInstance 对象。
func to_dict() -> Dictionary:
	return {
		"virtual_id": virtual_id,
		"name": name,
		"suit": suit,
		"rank": rank,
		"nature": nature,
		"material_card_uids": material_card_uids.duplicate(),
		"storage": storage.duplicate(true),
	}
