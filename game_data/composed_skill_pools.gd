class_name ComposedSkillPools
extends RefCounted

## 组合技能池数据：把「注入」组合出的【进程】与【缺陷】所需要的「时机池」与「效果池」集中在一处。
##
## 【为什么必须集中】池内文本是需求钦定的**不可变原文**，它同时出现在三个地方：组合窗口的选项文字、
## 组合后写入实例的动态技能正文、以及回归测试的逐字断言。若三处各存一份，任何一次改动都会造成
## 「窗口显示的和实际生效的不是同一句」这种最难发现的偏差。因此本文件是池文本的**唯一来源**。
##
## 【稳定键与原文分离】每个条目都有 ASCII 稳定键（`key`）与中文原文（`text`）。
## 稳定键用于：写入实例配置（进存档）、分发效果实现、AI 评分与回归断言。
## 原文用于：界面显示与技能正文拼装。
## 两者分离的原因：原文可能被要求逐字修正，而存档里已经写入的配置必须继续可读；键一旦发布不得改动。
##
## 【纯数据、无副作用】本文件只提供静态查询，不访问 GameState、不订阅任何时机、不产生随机数。
## 因此它可以被界面、技能脚本与测试同时安全调用。


## 时机池条目的字段名常量；拼写错误会在运行时静默取到默认值，因此统一用常量避免手写字符串。
const KEY_FIELD: String = "key"
const TEXT_FIELD: String = "text"
const TIMING_FIELD: String = "timing"
const ROLE_FIELD: String = "role"
const CONDITION_FIELD: String = "condition"
const EXTRA_TIMINGS_FIELD: String = "extra_timings"
const NEEDS_CHOICE_FIELD: String = "needs_choice"
const LOSES_SKILL_FIELD: String = "loses_skill"

## 效果池类别标识：注入的目标为主演时组合【进程】，否则组合【缺陷】。
const KIND_JINCHENG: String = "jincheng"
const KIND_QUEXIAN: String = "quexian"

## 时机角色标识：与 TriggerManager 的 role 取值完全一致，禁止另起别名。
const ROLE_GLOBAL: String = "global"
const ROLE_PLAYER: String = "player"
const ROLE_SOURCE: String = "source"
const ROLE_TARGET: String = "target"

## 时机条件种类：技能脚本按该值对事件做进一步筛选。
## `none` 无条件；`elemental` 只接受火/雷属性伤害；`slash` 只接受【杀】；
## `outside_turn` 只在持有者不是当前回合角色时成立；`turn_over` 需要按事件字段判定角色，故在运行时决定。
const CONDITION_NONE: String = "none"
const CONDITION_ELEMENTAL: String = "elemental"
const CONDITION_SLASH: String = "slash"
const CONDITION_OUTSIDE_TURN: String = "outside_turn"
const CONDITION_TURN_OVER: String = "turn_over"

## 属性伤害允许的伤害属性；与项目既有的 fire / thunder 命名保持一致。
const ELEMENTAL_NATURES: Array[String] = ["fire", "thunder"]

## 组合后正文的固定前缀与后缀；正文严格等于 前缀 + 时机原文 + 分隔 + 效果原文 + 后缀。
const DESCRIPTION_PREFIX: String = "锁定技，"
const DESCRIPTION_SEPARATOR: String = "，"
const DESCRIPTION_SUFFIX: String = "。每回合限一次。"

## 时机池；顺序即界面展示顺序，需求钦定，不得调整。
## 条目字段：key 稳定键、text 逐字原文、timing 主时机名、role 触发角色、
## condition 事件条件种类、extra_timings 需要同时订阅的附加时机（可选，仅「体力上限变化」使用）。
const TIMING_ENTRIES: Array[Dictionary] = [
	{"key":"damage_after", "text":"当你受到伤害后", "timing":"damageAfter", "role":ROLE_TARGET, "condition":CONDITION_NONE},
	{"key":"lose_hp_after", "text":"当你失去体力后", "timing":"loseHpAfter", "role":ROLE_TARGET, "condition":CONDITION_NONE},
	{"key":"elemental_damage_after", "text":"当你受到属性伤害后", "timing":"damageAfter", "role":ROLE_TARGET, "condition":CONDITION_ELEMENTAL},
	{"key":"deal_damage_after", "text":"当你造成伤害后", "timing":"damageAfter", "role":ROLE_SOURCE, "condition":CONDITION_NONE},
	{"key":"deal_elemental_damage_after", "text":"当你造成属性伤害后", "timing":"damageAfter", "role":ROLE_SOURCE, "condition":CONDITION_ELEMENTAL},
	{"key":"recover_after", "text":"当你回复体力后", "timing":"recoverAfter", "role":ROLE_TARGET, "condition":CONDITION_NONE},
	{"key":"max_hp_changed_after", "text":"当你的体力上限发生变化后", "timing":"gainMaxHpAfter", "role":ROLE_TARGET, "condition":CONDITION_NONE, "extra_timings":["loseMaxHpAfter"]},
	{"key":"hp_changed_after", "text":"当你的体力值发生变化后", "timing":"changeHp", "role":ROLE_TARGET, "condition":CONDITION_NONE},
	{"key":"round_start", "text":"每轮开始时", "timing":"roundStart", "role":ROLE_GLOBAL, "condition":CONDITION_NONE},
	{"key":"round_end", "text":"每轮结束时", "timing":"roundEnd", "role":ROLE_GLOBAL, "condition":CONDITION_NONE},
	{"key":"turn_start", "text":"回合开始时", "timing":"phaseBegin", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"turn_end", "text":"回合结束时", "timing":"phaseEnd", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"phase_judge_begin", "text":"判定阶段开始时", "timing":"phaseJudgeBegin", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"phase_use_begin", "text":"出牌阶段开始时", "timing":"phaseUseBegin", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"phase_draw_begin", "text":"摸牌阶段开始时", "timing":"phaseDrawBegin", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"phase_discard_begin", "text":"弃牌阶段开始时", "timing":"phaseDiscardBegin", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"use_slash", "text":"当你使用【杀】时", "timing":"useCard", "role":ROLE_SOURCE, "condition":CONDITION_SLASH},
	{"key":"become_slash_target", "text":"当你成为【杀】的目标时", "timing":"useCardToTargeted", "role":ROLE_TARGET, "condition":CONDITION_SLASH},
	{"key":"turn_over", "text":"当你的武将牌翻面时", "timing":"turnOverAfter", "role":ROLE_PLAYER, "condition":CONDITION_TURN_OVER},
	{"key":"cards_discarded", "text":"当你因弃置而失去牌时", "timing":"cardsDiscardedBatchAfter", "role":ROLE_PLAYER, "condition":CONDITION_NONE},
	{"key":"lose_card_outside_turn", "text":"当你于回合外失去牌时", "timing":"loseAfter", "role":ROLE_PLAYER, "condition":CONDITION_OUTSIDE_TURN},
	{"key":"character_die", "text":"当一名角色死亡后", "timing":"dieAfter", "role":ROLE_GLOBAL, "condition":CONDITION_NONE},
	{"key":"dying_recovered", "text":"当一名角色脱离濒死状态后", "timing":"dyingAfter", "role":ROLE_GLOBAL, "condition":CONDITION_NONE},
]

## 【进程】效果池；顺序即界面展示顺序，需求钦定，不得调整。
## 条目字段：key 稳定键、text 逐字原文、needs_choice 是否需要玩家选择牌或目标、loses_skill 是否在效果后失去本技能。
const JINCHENG_EFFECTS: Array[Dictionary] = [
	{"key":"draw_one", "text":"你摸一张牌", "needs_choice":false, "loses_skill":false},
	{"key":"gain_trick", "text":"你从牌堆中获得一张锦囊牌", "needs_choice":false, "loses_skill":false},
	{"key":"gain_basic", "text":"你从牌堆中获得一张基本牌", "needs_choice":false, "loses_skill":false},
	{"key":"gain_equipment", "text":"你从牌堆中获得一张装备牌", "needs_choice":false, "loses_skill":false},
	{"key":"gain_yitai_card", "text":"你从牌堆中获得一张“以太”牌", "needs_choice":false, "loses_skill":false},
	{"key":"gain_dodge", "text":"从牌堆中获得一张【闪】", "needs_choice":false, "loses_skill":false},
	{"key":"gain_slash", "text":"从牌堆中获得一张【杀】", "needs_choice":false, "loses_skill":false},
	{"key":"use_random_pile_equipment", "text":"你随机使用牌堆中的一张装备牌", "needs_choice":false, "loses_skill":false},
	{"key":"reset_chain", "text":"你将武将牌重置", "needs_choice":false, "loses_skill":false},
	{"key":"discard_zone_card", "text":"你弃置一名角色区域内的一张牌", "needs_choice":true, "loses_skill":false},
	{"key":"take_equipment", "text":"你获得一名角色装备区内的一张牌", "needs_choice":true, "loses_skill":false},
	{"key":"take_other_turn_player_hand", "text":"你获得不为你的当前回合角色的一张手牌", "needs_choice":true, "loses_skill":false},
	{"key":"turn_hand_limit_plus2", "text":"你的手牌上限+2直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"turn_slash_limit_plus1", "text":"你的出牌阶段使用【杀】的次数上限+1直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"turn_attack_range_plus2", "text":"你使用攻击范围+2直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"turn_distance_minus1", "text":"你计算与其他角色距离-1直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"prevent_damage_until_turn_end", "text":"防止你受到伤害直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"virtual_slash", "text":"你视为使用一张【杀】", "needs_choice":true, "loses_skill":false},
	{"key":"virtual_duel", "text":"你视为使用一张【决斗】", "needs_choice":true, "loses_skill":false},
	{"key":"virtual_shunshou", "text":"你视为使用一张【顺手牵羊】", "needs_choice":true, "loses_skill":false},
	{"key":"draw_two_lose_skill", "text":"你摸两张牌并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"recover_one_lose_skill", "text":"你回复1点体力并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"gain_max_hp_lose_skill", "text":"你增加1点体力上限并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"gain_shield_lose_skill", "text":"你获得1点护盾并失去本技能", "needs_choice":false, "loses_skill":true},
]

## 【缺陷】效果池；顺序即界面展示顺序，需求钦定，不得调整。
const QUEXIAN_EFFECTS: Array[Dictionary] = [
	{"key":"discard_one_hand", "text":"你弃置一张手牌", "needs_choice":true, "loses_skill":false},
	{"key":"random_discard_one", "text":"你随机弃置一张牌", "needs_choice":false, "loses_skill":false},
	{"key":"random_discard_equipment", "text":"你随机弃置一张装备牌", "needs_choice":false, "loses_skill":false},
	{"key":"random_discard_basic", "text":"你随机弃置一张基本牌", "needs_choice":false, "loses_skill":false},
	{"key":"random_discard_trick", "text":"你随机弃置一张锦囊牌", "needs_choice":false, "loses_skill":false},
	{"key":"turn_hand_limit_minus1", "text":"你的手牌上限-1直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"set_chain", "text":"你将武将牌调整至横置", "needs_choice":false, "loses_skill":false},
	{"key":"give_card_to_turn_player", "text":"你交给不为你的当前回合角色一张牌", "needs_choice":true, "loses_skill":false},
	{"key":"block_response_until_turn_end", "text":"你不可响应其他角色使用的牌直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"turn_distance_plus1", "text":"你计算与其他角色的距离+1直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"next_damage_plus1", "text":"本回合内你下次受到的伤害+1", "needs_choice":false, "loses_skill":false},
	{"key":"next_elemental_damage_plus1", "text":"本回合内你下次受到的属性伤害+1", "needs_choice":false, "loses_skill":false},
	{"key":"next_recover_minus1", "text":"你下次回复的体力-1直到回合结束", "needs_choice":false, "loses_skill":false},
	{"key":"lose_hp_lose_skill", "text":"你失去1点体力并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"take_damage_lose_skill", "text":"你受到1点伤害并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"take_thunder_damage_lose_skill", "text":"你受到1点雷电伤害并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"take_fire_damage_lose_skill", "text":"你受到1点火焰伤害并失去本技能", "needs_choice":false, "loses_skill":true},
	{"key":"lose_max_hp_lose_skill", "text":"你减少1点体力上限并失去本技能", "needs_choice":false, "loses_skill":true},
]


## 返回全部时机条目；调用方只读使用，不得就地修改（返回的是常量数组本体，用于界面遍历）。
static func get_timing_entries() -> Array[Dictionary]:
	return TIMING_ENTRIES


## 按稳定键返回时机条目；未登记时返回空字典，调用方按“配置非法”处理。
static func get_timing_entry(timing_key: String) -> Dictionary:
	for entry: Dictionary in TIMING_ENTRIES:
		if str(entry.get(KEY_FIELD, "")) == timing_key:
			return entry
	return {}


## 判断时机键是否已登记；实例配置读取后必须先过这一关再订阅。
static func is_valid_timing_key(timing_key: String) -> bool:
	return not get_timing_entry(timing_key).is_empty()


## 按类别返回全部效果条目；类别非法时返回空数组。
static func get_effects(kind: String) -> Array[Dictionary]:
	if kind == KIND_JINCHENG:
		return JINCHENG_EFFECTS
	if kind == KIND_QUEXIAN:
		return QUEXIAN_EFFECTS
	return []


## 按类别与稳定键返回效果条目；未登记时返回空字典。
static func get_effect_entry(kind: String, effect_key: String) -> Dictionary:
	for entry: Dictionary in get_effects(kind):
		if str(entry.get(KEY_FIELD, "")) == effect_key:
			return entry
	return {}


## 判断效果键在该类别下是否已登记。
static func is_valid_effect_key(kind: String, effect_key: String) -> bool:
	return not get_effect_entry(kind, effect_key).is_empty()


## 返回时机条目的订阅时机名列表；主时机在前，附加时机在后。
## 「体力上限发生变化后」需要同时订阅 gainMaxHpAfter 与 loseMaxHpAfter，因此本函数返回两项。
static func get_subscription_timings(timing_key: String) -> Array[String]:
	# 订阅时机结果；未登记或字段缺失时返回空数组，调用方据此判定配置非法。
	var timings: Array[String] = []
	# 当前时机条目；空字典表示配置非法。
	var entry: Dictionary = get_timing_entry(timing_key)
	if entry.is_empty():
		return timings
	timings.append(str(entry.get(TIMING_FIELD, "")))
	for extra_variant: Variant in entry.get(EXTRA_TIMINGS_FIELD, []) as Array:
		timings.append(str(extra_variant))
	return timings


## 判断指定属性伤害是否属于「属性伤害」；只接受 fire 与 thunder 两种。
static func is_elemental_nature(nature: String) -> bool:
	return ELEMENTAL_NATURES.has(nature)


## 按需求钦定模板拼装组合后正文：`锁定技，<时机>，<效果>。每回合限一次。`
## 严格逐字拼装，不做任何空白裁剪或标点替换；调用方传入的必须是池内原文。
static func compose_description(timing_text: String, effect_text: String) -> String:
	return "%s%s%s%s%s" % [DESCRIPTION_PREFIX, timing_text, DESCRIPTION_SEPARATOR, effect_text, DESCRIPTION_SUFFIX]


## 判断指定效果是否会在执行后失去本技能；未登记时返回 false。
static func effect_loses_skill(kind: String, effect_key: String) -> bool:
	return bool(get_effect_entry(kind, effect_key).get(LOSES_SKILL_FIELD, false))


## 判断指定效果是否需要玩家选择牌或目标；未登记时返回 false。
static func effect_needs_choice(kind: String, effect_key: String) -> bool:
	return bool(get_effect_entry(kind, effect_key).get(NEEDS_CHOICE_FIELD, false))


## 返回全部需要玩家选择的效果键；供界面与 AI 预先知道哪些效果会二次开窗。
static func get_choice_effect_keys(kind: String) -> Array[String]:
	# 需要选择的效果键结果；保持池内顺序。
	var keys: Array[String] = []
	for entry: Dictionary in get_effects(kind):
		if bool(entry.get(NEEDS_CHOICE_FIELD, false)):
			keys.append(str(entry.get(KEY_FIELD, "")))
	return keys
