class_name CardGallerySort
extends RefCounted

## 主菜单静态卡牌画廊的共享排序规则。图鉴与联机形象选择共同调用本类，避免两个界面各自维护势力顺序并逐渐产生差异。

## 主公指定的武将势力优先顺序；未列出的扩展势力统一排在这些势力之后，并继续按势力名称与稳定 ID 确定顺序。
const CHARACTER_FACTION_ORDER: Array[String] = [
	"xingqionglieche",
	"yinhexvezhe",
	"beiluoboge",
	"xianzhou",
	"pinuokangni",
]

## 游戏牌主类型顺序；未知扩展类型排在三种正式类型之后。
const GAME_CARD_TYPE_ORDER: Dictionary = {
	"basic":0,
	"trick":1,
	"equipment":2,
}

## 基本牌规则牌名顺序；火【杀】与雷【杀】通过共同的 rule_name 归入【杀】组。
const BASIC_CARD_ORDER: Dictionary = {
	"杀":0,
	"闪":1,
	"桃":2,
	"酒":3,
}

## 装备牌子类型顺序；同时兼容现有 `_mount` 与旧展示映射中的 `_horse` 命名。
const EQUIPMENT_SUBTYPE_ORDER: Dictionary = {
	"weapon":0,
	"armor":1,
	"offensive_mount":2,
	"offensive_horse":2,
	"defensive_mount":3,
	"defensive_horse":3,
	"treasure":4,
}


## 比较两个武将稳定 ID；先按指定势力顺序分组，同势力内按中文名称和稳定 ID 排序。
static func sort_character_ids(left_character_id: String, right_character_id: String) -> bool:
	# 左侧武将静态定义；只读取势力字段参与排序。
	var left_character: Dictionary = GameDatabase.get_character(left_character_id)
	# 右侧武将静态定义；只读取势力字段参与排序。
	var right_character: Dictionary = GameDatabase.get_character(right_character_id)
	# 左侧武将势力稳定 ID；未知或缺失势力会进入扩展势力兜底分组。
	var left_faction_id: String = str(left_character.get("faction", ""))
	# 右侧武将势力稳定 ID；未知或缺失势力会进入扩展势力兜底分组。
	var right_faction_id: String = str(right_character.get("faction", ""))
	# 左侧势力优先级；指定五势力使用固定位置，其他势力共享末尾优先级。
	var left_faction_rank: int = get_character_faction_rank(left_faction_id)
	# 右侧势力优先级；数值越小越靠前。
	var right_faction_rank: int = get_character_faction_rank(right_faction_id)
	if left_faction_rank != right_faction_rank:
		return left_faction_rank < right_faction_rank
	if left_faction_id != right_faction_id:
		# 左侧扩展势力名称；未登记时回退稳定 ID，保证比较仍可复现。
		var left_faction_name: String = str(GameDatabase.get_faction(left_faction_id).get("display_name", left_faction_id))
		# 右侧扩展势力名称；只有固定顺序之外的不同势力会进入本分支。
		var right_faction_name: String = str(GameDatabase.get_faction(right_faction_id).get("display_name", right_faction_id))
		if left_faction_name != right_faction_name:
			return left_faction_name < right_faction_name
		return left_faction_id < right_faction_id
	# 左侧武将中文名称；同势力内作为主要玩家可见顺序。
	var left_name: String = GameDatabase.resolve_character_name(left_character_id)
	# 右侧武将中文名称；名称相同再比较稳定 ID。
	var right_name: String = GameDatabase.resolve_character_name(right_character_id)
	if left_name == right_name:
		return left_character_id < right_character_id
	return left_name < right_name


## 返回一个势力的排序优先级；未列出的扩展势力排在固定五势力之后。
static func get_character_faction_rank(faction_id: String) -> int:
	# 势力在主公指定顺序中的索引；未命中时为 -1。
	var faction_index: int = CHARACTER_FACTION_ORDER.find(faction_id)
	return faction_index if faction_index >= 0 else CHARACTER_FACTION_ORDER.size()


## 比较两个游戏牌稳定 ID；依次按主类型、类型内细分、玩家可见名称和稳定 ID 排序。
static func sort_game_card_ids(left_card_id: String, right_card_id: String) -> bool:
	# 左侧游戏牌静态定义；类型、子类型与名称均从同一权威数据源读取。
	var left_card: Dictionary = GameDatabase.get_card(left_card_id)
	# 右侧游戏牌静态定义；不创建卡牌实体或修改牌堆。
	var right_card: Dictionary = GameDatabase.get_card(right_card_id)
	# 左侧主类型优先级；基本、锦囊、装备依次为 0、1、2。
	var left_type_rank: int = _get_game_card_type_rank(left_card)
	# 右侧主类型优先级；未知类型统一排在正式类型之后。
	var right_type_rank: int = _get_game_card_type_rank(right_card)
	if left_type_rank != right_type_rank:
		return left_type_rank < right_type_rank
	# 左侧类型内分组优先级；具体含义由基本牌名、锦囊延时状态或装备子类型决定。
	var left_group_rank: int = _get_game_card_group_rank(left_card)
	# 右侧类型内分组优先级；数值越小越靠前。
	var right_group_rank: int = _get_game_card_group_rank(right_card)
	if left_group_rank != right_group_rank:
		return left_group_rank < right_group_rank
	# 左侧当前名称模式下的牌名；同一规则分组内保持玩家可读顺序。
	var left_name: String = GameSettings.resolve_card_display_name(left_card)
	# 右侧当前名称模式下的牌名；切换名称模式后图鉴重建并重新应用排序。
	var right_name: String = GameSettings.resolve_card_display_name(right_card)
	if left_name == right_name:
		return left_card_id < right_card_id
	return left_name < right_name


## 返回游戏牌主类型优先级；未知类型使用固定末尾位置。
static func _get_game_card_type_rank(card_definition: Dictionary) -> int:
	# 当前游戏牌主类型稳定 ID；只用于读取排序映射。
	var card_type: String = str(card_definition.get("type", ""))
	return int(GAME_CARD_TYPE_ORDER.get(card_type, GAME_CARD_TYPE_ORDER.size()))


## 返回同一主类型内的分组优先级；基本牌、锦囊牌与装备牌各自遵循独立规则。
static func _get_game_card_group_rank(card_definition: Dictionary) -> int:
	# 当前游戏牌主类型稳定 ID；决定后续使用哪套细分顺序。
	var card_type: String = str(card_definition.get("type", ""))
	# 当前游戏牌子类型稳定 ID；锦囊与装备细分直接读取该字段。
	var card_subtype: String = str(card_definition.get("subtype", ""))
	if card_type == "basic":
		# 当前基本牌规则牌名；属性【杀】优先读取共同 rule_name，其余牌读取原版牌名。
		var basic_rule_name: String = str(card_definition.get("rule_name", card_definition.get("original_name", "")))
		return int(BASIC_CARD_ORDER.get(basic_rule_name, BASIC_CARD_ORDER.size()))
	if card_type == "trick":
		return 1 if card_subtype == "delayed" else 0
	if card_type == "equipment":
		return int(EQUIPMENT_SUBTYPE_ORDER.get(card_subtype, EQUIPMENT_SUBTYPE_ORDER.size()))
	return 0
