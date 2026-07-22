class_name OpportunityCatalog
extends RefCounted

## 机缘卡静态目录。卡牌正文严格保存设计原文，运行时只通过稳定ID、品质与效果参数读取，不持有对局状态。

## 品质从低到高的稳定顺序；抽取权重、颜色和文档均以该数组为唯一顺序来源。
const QUALITY_ORDER: Array[String] = ["green", "blue", "purple", "orange", "red"]

## 品质稳定ID到玩家可见名称的映射；界面不自行拼接“卡”字，避免不同入口显示不一致。
const QUALITY_NAMES: Dictionary = {
	"green":"绿卡",
	"blue":"蓝卡",
	"purple":"紫卡",
	"orange":"橙卡",
	"red":"红卡",
}

## 全部机缘卡定义；description字段逐字保留主公给出的原文，effect与参数只服务权威结算。
const CARD_DEFINITIONS: Array[Dictionary] = [
	{"id":"green_draw_two", "quality":"green", "description":"摸两张牌。", "effect":"draw", "count":2},
	{"id":"green_recover_one", "quality":"green", "description":"回复1点体力。", "effect":"recover", "count":1},
	{"id":"green_discard_two", "quality":"green", "description":"弃置一名角色区域内的两张牌。", "effect":"discard_two_from_player"},
	{"id":"green_damage_one", "quality":"green", "description":"对一名角色造成1点伤害。", "effect":"damage_target", "count":1},
	{"id":"green_gain_one", "quality":"green", "description":"获得一名角色区域内的一张牌。", "effect":"gain_one_from_player"},
	{"id":"green_link_three", "quality":"green", "description":"将至多三名角色的武将牌横置。", "effect":"link_targets", "max_targets":3},
	{"id":"green_hand_limit_one", "quality":"green", "description":"手牌上限+1", "effect":"hand_limit", "count":1},
	{"id":"green_discard_one_each", "quality":"green", "description":"弃置任意名角色区域内各一张牌", "effect":"discard_one_each_target", "max_targets":10},
	{"id":"green_virtual_nanman", "quality":"green", "description":"视为使用一张【南蛮入侵】", "effect":"virtual_card_use", "definition_id":"nanman"},
	{"id":"green_virtual_wanjian", "quality":"green", "description":"视为使用一张【万箭齐发】", "effect":"virtual_card_use", "definition_id":"wanjian"},
	{"id":"green_discard_draw", "quality":"green", "description":"弃置区域内任意张牌并摸等量的牌", "effect":"discard_own_zone_and_draw"},
	{"id":"green_swap_equipment", "quality":"green", "description":"令两名角色交换装备区内的所有牌", "effect":"swap_equipment_targets", "max_targets":2},
	{"id":"green_discard_half_all", "quality":"green", "description":"令一名角色弃置X张牌（X为其所有牌数的一半，向上取整）", "effect":"discard_half_all_cards_target"},

	{"id":"blue_draw_three", "quality":"blue", "description":"摸三张牌。", "effect":"draw", "count":3},
	{"id":"blue_max_hp_one", "quality":"blue", "description":"增加1点体力上限。", "effect":"max_hp", "count":1},
	{"id":"blue_hand_limit_two", "quality":"blue", "description":"手牌上限+2", "effect":"hand_limit", "count":2},
	{"id":"blue_skill_jiqiao", "quality":"blue", "description":"获得技能“机巧”", "effect":"grant_skill", "skill_id":"jiqiao"},
	{"id":"blue_skill_huanyang", "quality":"blue", "description":"获得每回合能发动三次的技能“还阳”", "effect":"grant_skill", "skill_id":"huanyang", "per_turn_limit":3},
	{"id":"blue_skill_jiahu", "quality":"blue", "description":"获得技能“加护”", "effect":"grant_skill", "skill_id":"jiahu"},
	{"id":"blue_skill_wuxie", "quality":"blue", "description":"获得每回合能发动三次的技能“无邪”", "effect":"grant_skill", "skill_id":"wuxie_2", "per_turn_limit":3},
	{"id":"blue_skill_qingli", "quality":"blue", "description":"获得每回合能发动三次的技能“倾力”", "effect":"grant_skill", "skill_id":"qingli", "per_turn_limit":3},
	{"id":"blue_skill_gangfeng", "quality":"blue", "description":"获得每回合能发动三次的技能“罡风”", "effect":"grant_skill", "skill_id":"gangfeng", "per_turn_limit":3},
	{"id":"blue_skill_huanying", "quality":"blue", "description":"获得技能“幻影”", "effect":"grant_skill", "skill_id":"huanying"},
	{"id":"blue_skill_wangpai", "quality":"blue", "description":"获得技能“王牌”", "effect":"grant_skill", "skill_id":"wangpai"},
	{"id":"blue_gain_wuxie_two", "quality":"blue", "description":"从牌堆或弃牌堆中获得两张【无懈可击】", "effect":"gain_group_cards", "group_kind":"definition_id", "groups":["wuxie"], "count":2},
	{"id":"blue_swap_hands", "quality":"blue", "description":"令两名角色交换所有手牌", "effect":"swap_hand_targets", "max_targets":2},
	{"id":"blue_lose_half_hp", "quality":"blue", "description":"令一名角色失去X点体力（X为其当前体力值的一半，向上取整）", "effect":"lose_half_hp_target"},

	{"id":"purple_reduce_max_hp", "quality":"purple", "description":"令一名角色减少1点体力上限。", "effect":"max_hp_target", "count":-1},
	{"id":"purple_draw_five", "quality":"purple", "description":"摸五张牌。", "effect":"draw", "count":5},
	{"id":"purple_lose_hp_two", "quality":"purple", "description":"令一名角色失去2点体力。", "effect":"lose_hp_target", "count":2},
	{"id":"purple_discard_all_hand", "quality":"purple", "description":"令一名角色弃置所有手牌。", "effect":"discard_all_hand_target"},
	{"id":"purple_recover_full", "quality":"purple", "description":"将体力值回复至体力上限", "effect":"recover_full"},
	{"id":"purple_skill_hupo", "quality":"purple", "description":"获得技能“琥珀”", "effect":"grant_skill", "skill_id":"hupo"},
	{"id":"purple_skill_yaoli", "quality":"purple", "description":"获得技能“药理”", "effect":"grant_skill", "skill_id":"yaoli"},
	{"id":"purple_skill_zhishi", "quality":"purple", "description":"获得每回合能发动三次的技能“智识”", "effect":"grant_skill", "skill_id":"zhishi", "per_turn_limit":3},
	{"id":"purple_skill_chuanchong", "quality":"purple", "description":"获得技能“传冲”", "effect":"grant_skill", "skill_id":"chuanchong"},
	{"id":"purple_skill_qianggong", "quality":"purple", "description":"获得每回合能发动三次的技能“强攻”", "effect":"grant_skill", "skill_id":"qianggong", "per_turn_limit":3},
	{"id":"purple_skill_dieying", "quality":"purple", "description":"获得技能“蝶影”", "effect":"grant_skill", "skill_id":"dieying"},
	{"id":"purple_skill_sefu", "quality":"purple", "description":"获得技能“慑伏”", "effect":"grant_skill", "skill_id":"sefu"},
	{"id":"purple_skill_xingluo", "quality":"purple", "description":"获得技能“星落”", "effect":"grant_skill", "skill_id":"xingluo"},
	{"id":"purple_gain_distinct_delayed_three", "quality":"purple", "description":"从牌堆或弃牌堆中获得三张牌名不同的延时锦囊牌", "effect":"gain_distinct_delayed", "count":3},
	{"id":"purple_remove_until_round_end", "quality":"purple", "description":"令一名角色离场直到本轮结束", "effect":"remove_until_round_end_target"},

	{"id":"orange_draw_seven", "quality":"orange", "description":"摸七张牌。", "effect":"draw", "count":7},
	{"id":"orange_skill_yongyi", "quality":"orange", "description":"获得技能“永屹”", "effect":"grant_skill", "skill_id":"yongyi"},
	{"id":"orange_skill_junshi", "quality":"orange", "description":"获得技能“军势”", "effect":"grant_skill", "skill_id":"junshi"},
	{"id":"orange_swap_seat", "quality":"orange", "description":"选择一名其他角色，你与其交换座位。", "effect":"swap_seat_target"},
	{"id":"orange_damage_three", "quality":"orange", "description":"对至多三名角色依次造成2点伤害。", "effect":"damage_targets", "count":2, "max_targets":3},
	{"id":"orange_gain_all_hand", "quality":"orange", "description":"获得一名其他角色的所有手牌。", "effect":"gain_all_hand_target"},
	{"id":"orange_reduce_half_max_hp", "quality":"orange", "description":"令一名角色减少X点体力上限（X为其体力上限的一半，向上取整）", "effect":"reduce_half_max_hp_target"},
	{"id":"orange_damage_current_hp", "quality":"orange", "description":"对一名角色造成X点伤害（X为其当前体力值）", "effect":"damage_current_hp_target"},
	{"id":"orange_swap_characters", "quality":"orange", "description":"令两名角色交换武将牌", "effect":"swap_character_targets", "max_targets":2},

	{"id":"red_gain_types", "quality":"red", "description":"从牌堆或弃牌堆中获得所有类型的牌各4张。（基本牌、锦囊牌、装备牌）", "effect":"gain_group_cards", "group_kind":"type", "groups":["basic", "trick", "equipment"], "count":4},
	{"id":"red_gain_suits_three", "quality":"red", "description":"从牌堆或弃牌堆中获得所有花色的牌各3张。", "effect":"gain_group_cards", "group_kind":"suit", "groups":["spade", "heart", "club", "diamond"], "count":3},
	{"id":"red_double_max_hp", "quality":"red", "description":"你的体力上限翻倍。", "effect":"double_max_hp"},
	{"id":"red_gain_suits_feiyan", "quality":"red", "description":"从牌堆或弃牌堆中获得每种花色的牌各一张并获得技能“飞焰”", "effect":"gain_group_and_skill", "group_kind":"suit", "groups":["spade", "heart", "club", "diamond"], "count":1, "skill_id":"feiyan"},
	{"id":"red_gain_sha_zaixian", "quality":"red", "description":"从牌堆或弃牌堆中获得三张【杀】并获得获得技能“再现”", "effect":"gain_group_and_skill", "group_kind":"rule_name", "groups":["杀"], "count":3, "skill_id":"zaixian"},
	{"id":"red_gain_sha_pofeng", "quality":"red", "description":"从牌堆或弃牌堆中获得三张【杀】并获得获得技能“破风”", "effect":"gain_group_and_skill", "group_kind":"rule_name", "groups":["杀"], "count":3, "skill_id":"pofeng"},
	{"id":"red_three_extra_turns", "quality":"red", "description":"本回合结束后获得三个额外回合。", "effect":"extra_turns", "count":3},
	{"id":"red_all_hand_view_as_wuzhong", "quality":"red", "description":"所有手牌视为【无中生有】直到离开你的手牌区", "effect":"view_all_hand_as", "definition_id":"wuzhong"},
	{"id":"red_gain_all_equipment", "quality":"red", "description":"获得牌堆与弃牌堆与场上的所有装备牌", "effect":"gain_all_equipment"},
	{"id":"red_gain_random_three_each", "quality":"red", "description":"获得每名角色区域内的随机三张牌", "effect":"gain_random_zone_cards_each", "count":3},
]


## 返回全部机缘卡定义的深拷贝；调用方可安全排序或筛选，不会改写静态目录。
static func get_all_cards() -> Array[Dictionary]:
	# 全部卡牌副本；逐项深复制保证嵌套数组参数同样与常量隔离。
	var result: Array[Dictionary] = []
	for card_definition: Dictionary in CARD_DEFINITIONS:
		result.append(card_definition.duplicate(true))
	return result


## 返回指定品质的全部机缘卡；未知品质返回空数组。
static func get_cards_by_quality(quality_id: String) -> Array[Dictionary]:
	# 品质卡牌结果；顺序沿用设计清单，固定随机种子下抽取结果可稳定复现。
	var result: Array[Dictionary] = []
	for card_definition: Dictionary in CARD_DEFINITIONS:
		if str(card_definition.get("quality", "")) == quality_id:
			result.append(card_definition.duplicate(true))
	return result


## 按稳定ID返回机缘卡定义；不存在时返回空字典。
static func get_card(card_id: String) -> Dictionary:
	for card_definition: Dictionary in CARD_DEFINITIONS:
		if str(card_definition.get("id", "")) == card_id:
			return card_definition.duplicate(true)
	return {}


## 返回品质玩家可见名称；未知品质回退稳定ID，便于诊断内容配置错误。
static func get_quality_name(quality_id: String) -> String:
	return str(QUALITY_NAMES.get(quality_id, quality_id))
