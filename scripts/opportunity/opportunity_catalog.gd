class_name OpportunityCatalog
extends RefCounted

## 机缘卡静态目录。卡牌正文严格保存设计原文，运行时只通过稳定ID、品质与效果参数读取，不持有对局状态。

## 可随机抽取的品质从低到高的稳定顺序；灰色关卡专属机缘不在本数组中，因此永远不会进入三选一。
const QUALITY_ORDER: Array[String] = ["green", "blue", "purple", "orange", "red"]

## 品质稳定ID到玩家可见名称的映射；界面不自行拼接“卡”字，避免不同入口显示不一致。
const QUALITY_NAMES: Dictionary = {
	"gray":"灰卡",
	"green":"绿卡",
	"blue":"蓝卡",
	"purple":"紫卡",
	"orange":"橙卡",
	"red":"红卡",
}

## 全部机缘卡定义；description字段逐字保留主公给出的原文，effect与参数只服务权威结算。
const CARD_DEFINITIONS: Array[Dictionary] = [
	# 灰色机缘仅由过关斩将关卡授予；不在QUALITY_ORDER中，所以权重抽取与全零权重回退都不会选中。
	# 补充：难度配置也可按稳定ID直接授予灰色机缘，但仍不会让其进入随机三选一。
	{"id":"gray_initial_hand_four", "quality":"gray", "description":"初始手牌数+4", "effect":"initial_hand_bonus", "count":4},
	{"id":"gray_equip_distinct_four", "quality":"gray", "description":"进入战斗后随机使用牌堆或弃牌堆中的4张不同子类别的装备牌", "effect":"equip_distinct_subtypes", "count":4},
	{"id":"gray_initial_hand_one", "quality":"gray", "description":"初始手牌数+1", "effect":"initial_hand_bonus", "count":1},
	{"id":"gray_initial_hand_two", "quality":"gray", "description":"初始手牌数+2", "effect":"initial_hand_bonus", "count":2},
	{"id":"gray_revive_one", "quality":"gray", "description":"复活次数+1", "effect":"revive_count", "count":1},

	{"id":"green_draw_two", "quality":"green", "description":"摸两张牌。", "effect":"draw", "count":2},
	{"id":"green_recover_one", "quality":"green", "description":"回复1点体力。", "effect":"recover", "count":1},
	{"id":"green_discard_two", "quality":"green", "description":"弃置一名角色区域内的两张牌。", "effect":"discard_two_from_player"},
	{"id":"green_damage_one", "quality":"green", "description":"对一名角色造成1点伤害。", "effect":"damage_target", "count":1},
	{"id":"green_gain_one", "quality":"green", "description":"获得一名角色区域内的一张牌。", "effect":"gain_one_from_player"},
	{"id":"green_link_three", "quality":"green", "description":"将至多三名角色的武将牌横置。", "effect":"link_targets", "max_targets":3},
	{"id":"green_hand_limit_one", "quality":"green", "description":"手牌上限+1", "effect":"hand_limit", "count":1},
	{"id":"green_slash_play_limit_one", "quality":"green", "description":"出牌阶段使用【杀】的次数上限+1", "effect":"slash_play_limit_bonus", "count":1},
	{"id":"green_discard_one_each", "quality":"green", "description":"弃置任意名角色区域内各一张牌", "effect":"discard_one_each_target", "max_targets":10},
	{"id":"green_virtual_nanman", "quality":"green", "description":"视为使用一张【南蛮入侵】", "effect":"virtual_card_use", "definition_id":"nanman"},
	{"id":"green_virtual_wanjian", "quality":"green", "description":"视为使用一张【万箭齐发】", "effect":"virtual_card_use", "definition_id":"wanjian"},
	{"id":"green_discard_draw", "quality":"green", "description":"弃置区域内任意张牌并摸等量的牌", "effect":"discard_own_zone_and_draw"},
	{"id":"green_swap_equipment", "quality":"green", "description":"令两名角色交换装备区内的所有牌", "effect":"swap_equipment_targets", "max_targets":2},
	{"id":"green_discard_half_all", "quality":"green", "description":"令一名角色弃置X张牌（X为其所有牌数的一半，向上取整）", "effect":"discard_half_all_cards_target"},
	{"id":"green_skill_zhuijian", "quality":"green", "description":"获得技能“追歼”", "effect":"grant_skill", "skill_id":"zhuijian"},
	{"id":"green_skill_bingfeng", "quality":"green", "description":"获得技能“冰封”", "effect":"grant_skill", "skill_id":"bingfeng"},
	{"id":"green_skill_xinghuo", "quality":"green", "description":"获得技能“星火”", "effect":"grant_skill", "skill_id":"xinghuo"},
	{"id":"green_skill_xifa", "quality":"green", "description":"获得技能“戏法”", "effect":"grant_skill", "skill_id":"xifa"},

	{"id":"blue_draw_three", "quality":"blue", "description":"摸三张牌。", "effect":"draw", "count":3},
	{"id":"blue_max_hp_one", "quality":"blue", "description":"增加1点体力上限。", "effect":"max_hp", "count":1},
	{"id":"blue_hand_limit_two", "quality":"blue", "description":"手牌上限+2", "effect":"hand_limit", "count":2},
	{"id":"blue_draw_phase_one", "quality":"blue", "description":"摸牌阶段额外摸一张牌", "effect":"draw_phase_bonus", "count":1},
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
	{"id":"blue_skill_jiyu", "quality":"blue", "description":"获得技能“疾雨”", "effect":"grant_skill", "skill_id":"jiyu"},
	{"id":"blue_skill_tianzhui", "quality":"blue", "description":"获得技能“天坠”", "effect":"grant_skill", "skill_id":"tianzhui"},
	{"id":"blue_skill_anda", "quality":"blue", "description":"获得技能“安打”", "effect":"grant_skill", "skill_id":"anda"},
	{"id":"blue_skill_touxia", "quality":"blue", "description":"获得技能“投狭”", "effect":"grant_skill", "skill_id":"touxia"},
	{"id":"blue_skill_qiusheng", "quality":"blue", "description":"获得技能“求生”", "effect":"grant_skill", "skill_id":"qiusheng"},
	{"id":"blue_skill_quanlei", "quality":"blue", "description":"获得技能“全垒”", "effect":"grant_skill", "skill_id":"quanlei"},
	{"id":"blue_skill_jianshi", "quality":"blue", "description":"获得技能“剑势”", "effect":"grant_skill", "skill_id":"jianshi"},
	{"id":"blue_skill_shanqing", "quality":"blue", "description":"获得每回合能发动三次的技能“山倾”", "effect":"grant_skill", "skill_id":"shanqing", "per_turn_limit":3},

	{"id":"purple_reduce_max_hp", "quality":"purple", "description":"令一名角色减少1点体力上限。", "effect":"max_hp_target", "count":-1},
	{"id":"purple_draw_five", "quality":"purple", "description":"摸五张牌。", "effect":"draw", "count":5},
	{"id":"purple_max_hp_two", "quality":"purple", "description":"增加2点体力上限。", "effect":"max_hp", "count":2},
	{"id":"purple_lose_hp_two", "quality":"purple", "description":"令一名角色失去2点体力。", "effect":"lose_hp_target", "count":2},
	{"id":"purple_discard_all_hand", "quality":"purple", "description":"令一名角色弃置所有手牌。", "effect":"discard_all_hand_target"},
	{"id":"purple_recover_full", "quality":"purple", "description":"将体力值回复至体力上限", "effect":"recover_full"},
	{"id":"purple_skill_hupo", "quality":"purple", "description":"获得技能“琥珀”", "effect":"grant_skill", "skill_id":"hupo"},
	{"id":"purple_skill_yaoli", "quality":"purple", "description":"获得技能“药理”", "effect":"grant_skill", "skill_id":"yaoli"},
	{"id":"purple_skill_zhishi", "quality":"purple", "description":"获得每回合能发动三次的技能“智识”", "effect":"grant_skill", "skill_id":"zhishi", "per_turn_limit":3},
	{"id":"purple_skill_chuanchong", "quality":"purple", "description":"获得技能“传冲”", "effect":"grant_skill", "skill_id":"chuanchong"},
	{"id":"purple_skill_qianggong", "quality":"purple", "description":"获得每回合能发动三次的技能“强攻”", "effect":"grant_skill", "skill_id":"qianggong", "per_turn_limit":3},
	{"id":"purple_skill_dieying", "quality":"purple", "description":"获得技能“蝶影”", "effect":"grant_skill", "skill_id":"dieying"},
	{"id":"purple_skill_sefu", "quality":"purple", "description":"获得技能“慑伏”", "effect":"grant_skill", "skill_id":"shefu"},
	{"id":"purple_skill_xingluo", "quality":"purple", "description":"获得技能“星落”", "effect":"grant_skill", "skill_id":"xingluo"},
	{"id":"purple_gain_distinct_delayed_three", "quality":"purple", "description":"从牌堆或弃牌堆中获得三张牌名不同的延时锦囊牌", "effect":"gain_distinct_delayed", "count":3},
	{"id":"purple_remove_until_round_end", "quality":"purple", "description":"令一名角色离场直到本轮结束", "effect":"remove_until_round_end_target"},
	{"id":"purple_skill_huanfa", "quality":"purple", "description":"获得技能“焕发”", "effect":"grant_skill", "skill_id":"huanfa"},
	{"id":"purple_skill_kance", "quality":"purple", "description":"获得技能“勘测”", "effect":"grant_skill", "skill_id":"kance"},
	{"id":"purple_skill_xingqi", "quality":"purple", "description":"获得技能“星祈”", "effect":"grant_skill", "skill_id":"xingqi"},
	{"id":"purple_skip_judgment_phase", "quality":"purple", "description":"永远跳过你的判定阶段", "effect":"skip_judgment_phase", "count":1},

	{"id":"orange_draw_seven", "quality":"orange", "description":"摸七张牌。", "effect":"draw", "count":7},
	{"id":"orange_draw_phase_one", "quality":"orange", "description":"摸牌阶段额外摸一张牌", "effect":"draw_phase_bonus", "count":1},
	{"id":"orange_damage_one", "quality":"orange", "description":"造成的伤害+1", "effect":"damage_bonus", "count":1},
	{"id":"orange_skill_yongyi", "quality":"orange", "description":"获得技能“永屹”", "effect":"grant_skill", "skill_id":"yongyi"},
	{"id":"orange_skill_junshi", "quality":"orange", "description":"获得技能“军势”", "effect":"grant_skill", "skill_id":"junshi"},
	{"id":"orange_swap_seat", "quality":"orange", "description":"选择一名其他角色，你与其交换座位。", "effect":"swap_seat_target"},
	{"id":"orange_damage_three", "quality":"orange", "description":"对至多三名角色依次造成2点伤害。", "effect":"damage_targets", "count":2, "max_targets":3},
	{"id":"orange_gain_all_hand", "quality":"orange", "description":"获得一名其他角色的所有手牌。", "effect":"gain_all_hand_target"},
	{"id":"orange_reduce_half_max_hp", "quality":"orange", "description":"令一名角色减少X点体力上限（X为其体力上限的一半，向上取整）", "effect":"reduce_half_max_hp_target"},
	{"id":"orange_damage_current_hp", "quality":"orange", "description":"对一名角色造成X点伤害（X为其当前体力值）", "effect":"damage_current_hp_target"},
	{"id":"orange_swap_characters", "quality":"orange", "description":"令两名角色交换武将牌", "effect":"swap_character_targets", "max_targets":2},
	{"id":"orange_skill_mice", "quality":"orange", "description":"获得技能“秘策”", "effect":"grant_skill", "skill_id":"mice"},
	{"id":"orange_skill_mingchen", "quality":"orange", "description":"获得每回合能发动三次的技能“冥谶”", "effect":"grant_skill", "skill_id":"mingchen", "per_turn_limit":3},
	{"id":"orange_skill_xianzou", "quality":"orange", "description":"获得技能“弦奏”", "effect":"grant_skill", "skill_id":"xianzou"},
	{"id":"orange_skip_discard_phase", "quality":"orange", "description":"永远跳过你的弃牌阶段", "effect":"skip_discard_phase", "count":1},

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
	{"id":"red_gain_same_name_length_lushi", "quality":"red", "description":"从牌堆或弃牌堆中获得四张牌名字数相同的牌并获得技能“录事”", "effect":"gain_same_name_length_and_skill", "count":4, "skill_id":"lushi"},
	{"id":"red_gain_suits_anke", "quality":"red", "description":"从牌堆或弃牌堆中获得每种花色的牌各一张并获得技能“安可”", "effect":"gain_group_and_skill", "group_kind":"suit", "groups":["spade", "heart", "club", "diamond"], "count":1, "skill_id":"anke"},
	{"id":"red_refresh_opportunities", "quality":"red", "description":"将你的所有机缘刷新为同品质的新机缘，每个机缘有30%的概率刷新为更高级的机缘。", "description_font_size":19, "effect":"refresh_opportunities", "upgrade_chance":0.3},
	{"id":"red_gain_three_unowned_orange", "quality":"red", "description":"随机获得三项你未拥有的橙色机缘", "effect":"gain_random_unowned_opportunities", "quality_id":"orange", "count":3},
]

## 稳定机缘ID到静态定义的运行时索引；首次查询时一次性构建，之后高频规则查询保持常数时间。
static var _card_definitions_by_id: Dictionary = {}

## 品质ID到稳定机缘ID数组的运行时索引；数组顺序严格沿用CARD_DEFINITIONS，保证固定种子结果不变。
static var _card_ids_by_quality: Dictionary = {}

## 静态目录索引是否已经完成构建；默认false，首次公开查询后变为true且不需要运行时动态修改。
static var _catalog_indexes_initialized: bool = false


## 延迟建立静态目录索引；目录只读且整局不变化，因此一次构建即可供机缘抽取、效果查询与详情展示复用。
static func _ensure_catalog_indexes() -> void:
	if _catalog_indexes_initialized:
		return
	# 新的ID索引；先在局部完整构建，再一次性替换静态字段，避免初始化中途暴露不完整结果。
	var definitions_by_id: Dictionary = {}
	# 新的品质索引；包含灰色关卡机缘，随机抽取端仍只遍历QUALITY_ORDER中的五种品质。
	var ids_by_quality: Dictionary = {}
	for card_definition: Dictionary in CARD_DEFINITIONS:
		# 当前机缘稳定ID；空ID不会进入索引，但仍会由目录专项测试暴露配置错误。
		var card_id: String = str(card_definition.get("id", ""))
		# 当前机缘品质ID；未知品质仍建立独立索引，便于内容维护工具读取并诊断。
		var quality_id: String = str(card_definition.get("quality", ""))
		if card_id.is_empty():
			continue
		definitions_by_id[card_id] = card_definition
		# 当前品质已有ID数组；数组只保存字符串，不复制正文、效果参数或嵌套分组。
		var quality_card_ids: Array = ids_by_quality.get(quality_id, []) as Array
		quality_card_ids.append(card_id)
		ids_by_quality[quality_id] = quality_card_ids
	_card_definitions_by_id = definitions_by_id
	_card_ids_by_quality = ids_by_quality
	_catalog_indexes_initialized = true


## 返回全部机缘卡定义的深拷贝；调用方可安全排序或筛选，不会改写静态目录。
static func get_all_cards() -> Array[Dictionary]:
	# 全部卡牌副本；逐项深复制保证嵌套数组参数同样与常量隔离。
	var result: Array[Dictionary] = []
	for card_definition: Dictionary in CARD_DEFINITIONS:
		result.append(card_definition.duplicate(true))
	return result


## 返回指定品质的全部机缘卡；未知品质返回空数组。
static func get_cards_by_quality(quality_id: String) -> Array[Dictionary]:
	_ensure_catalog_indexes()
	# 品质卡牌结果；顺序沿用设计清单，固定随机种子下抽取结果可稳定复现。
	var result: Array[Dictionary] = []
	for card_id_variant: Variant in _card_ids_by_quality.get(quality_id, []) as Array:
		# 当前索引对应定义；公开接口继续深复制，调用方排序或修改参数不会污染静态目录。
		var card_definition: Dictionary = _card_definitions_by_id.get(str(card_id_variant), {}) as Dictionary
		if not card_definition.is_empty():
			result.append(card_definition.duplicate(true))
	return result


## 按稳定ID返回机缘卡定义；不存在时返回空字典。
static func get_card(card_id: String) -> Dictionary:
	_ensure_catalog_indexes()
	# 索引命中的静态定义；返回深拷贝维持原公开接口的隔离契约。
	var card_definition: Dictionary = _card_definitions_by_id.get(card_id, {}) as Dictionary
	return card_definition.duplicate(true) if not card_definition.is_empty() else {}


## 返回稳定ID是否对应已登记机缘；高频规则校验只读取布尔值，不为存在性判断复制完整定义。
static func has_card(card_id: String) -> bool:
	_ensure_catalog_indexes()
	return not card_id.is_empty() and _card_definitions_by_id.has(card_id)


## 返回指定机缘的效果稳定ID；结果为不可变字符串，适合长局增量汇总且不会暴露静态定义字典。
static func get_effect_id(card_id: String) -> String:
	_ensure_catalog_indexes()
	# 索引命中的静态定义；未知ID使用空字典并返回空效果，调用方可安全跳过损坏历史。
	var card_definition: Dictionary = _card_definitions_by_id.get(card_id, {}) as Dictionary
	return str(card_definition.get("effect", ""))


## 返回指定机缘的整数count参数；没有count或定义不存在时返回0，其他参数仍通过隔离的get_card接口读取。
static func get_effect_count(card_id: String) -> int:
	_ensure_catalog_indexes()
	# 索引命中的静态定义；只读取基础整数，不复制description、groups等无关字段。
	var card_definition: Dictionary = _card_definitions_by_id.get(card_id, {}) as Dictionary
	return int(card_definition.get("count", 0))


## 返回指定机缘授予的技能稳定ID；非技能机缘与未知ID返回空字符串，调用方无需复制完整定义后再筛选。
static func get_skill_id(card_id: String) -> String:
	_ensure_catalog_indexes()
	# 索引命中的静态定义；只有grant_skill效果允许被过关斩将恢复为运行时技能。
	var card_definition: Dictionary = _card_definitions_by_id.get(card_id, {}) as Dictionary
	return str(card_definition.get("skill_id", "")) if str(card_definition.get("effect", "")) == "grant_skill" else ""


## 返回指定品质的稳定机缘ID数组；结果为独立副本，适合组件按局缓存并在抽取时安全过滤。
static func get_card_ids_by_quality(quality_id: String) -> Array[String]:
	_ensure_catalog_indexes()
	# 品质ID副本；只复制短字符串数组，不复制69张机缘的正文和效果字典。
	# 补充：目录现已扩展至95张，返回路径仍只复制短字符串数组，不复制正文和效果字典。
	var result: Array[String] = []
	for card_id_variant: Variant in _card_ids_by_quality.get(quality_id, []) as Array:
		result.append(str(card_id_variant))
	return result


## 返回品质玩家可见名称；未知品质回退稳定ID，便于诊断内容配置错误。
static func get_quality_name(quality_id: String) -> String:
	return str(QUALITY_NAMES.get(quality_id, quality_id))
