class_name VirtualCard
extends RefCounted

## 逻辑牌描述。虚拟牌只表达视为牌的规则属性，实体材料牌仍由 CardInstance UID 独立记录。

## 被视为实体花色的合法取值；材料聚合只承认这四种花色，其余一律按无花色处理。
const SUIT_VALUES: Array[String] = ["spade", "heart", "club", "diamond"]

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

## 逻辑牌颜色；取值为 red、black 或 none，由创建方按材料聚合结果写入。
## 多张材料花色不同但颜色一致时花色为 none 而颜色仍保留，回放与表现据此还原颜色语义。
var color: String = "none"

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
	# 颜色默认按花色推导；多材料聚合牌随后由使用入口覆盖成材料聚合颜色。
	color = CardInstance.color_of_suit(card_suit)


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
		"color": color,
		"material_card_uids": material_card_uids.duplicate(),
		"storage": storage.duplicate(true),
	}


## 按多张材料牌的花色推导本次虚拟牌的花色与颜色。
## 规则：全部材料同花色时视为该花色（例如两张黑桃当【杀】视为黑桃【杀】）；
## 花色不同但颜色一致时保留颜色并视为无花色（例如红桃+方块视为红色无花色牌）；
## 颜色不一致或存在无花色材料时视为无色牌（例如一张红牌加一张黑牌）。
## 返回值固定为 {"suit":String, "color":String}，颜色只可能是 red/black/none。
static func resolve_material_aggregate(material_cards: Array[CardInstance]) -> Dictionary:
	# 材料原始花色序列；保持材料顺序，重复花色在聚合中自然去重。
	var material_suits: Array[String] = []
	for material_card: CardInstance in material_cards:
		# 当前材料实体；缺失实体无法推导花色，整体按无色处理而不是猜测。
		if material_card == null:
			return {"suit":"none", "color":"none"}
		material_suits.append(material_card.suit)
	return resolve_suit_aggregate(material_suits)


## 按材料花色序列推导聚合花色与颜色；输入允许重复花色与无效花色，顺序不影响结果。
static func resolve_suit_aggregate(material_suits: Array) -> Dictionary:
	# 默认结果；无材料或任一无花色材料时既无花色也无颜色。
	var result: Dictionary = {"suit":"none", "color":"none"}
	if material_suits.is_empty():
		return result
	# 去重后的有效花色；顺带完成合法花色校验。
	var unique_suits: Array[String] = []
	for suit_variant: Variant in material_suits:
		# 当前材料花色；非法或无花色材料使整张虚拟牌退化为无色牌。
		var material_suit: String = str(suit_variant)
		if not SUIT_VALUES.has(material_suit):
			return result
		if not unique_suits.has(material_suit):
			unique_suits.append(material_suit)
	if unique_suits.size() == 1:
		# 同花色材料；虚拟牌直接视为该花色，颜色由花色推导。
		result["suit"] = unique_suits[0]
		result["color"] = CardInstance.color_of_suit(unique_suits[0])
		return result
	# 多花色材料；只有颜色完全一致时才保留颜色，花色仍视为无花色。
	var aggregated_color: String = CardInstance.color_of_suit(unique_suits[0])
	for material_suit: String in unique_suits:
		if CardInstance.color_of_suit(material_suit) != aggregated_color:
			return result
	result["color"] = aggregated_color
	return result
