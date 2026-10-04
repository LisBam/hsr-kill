class_name RuleTimingCatalog
extends RefCounted

## 无名杀兼容时机目录。这里只保存稳定事件名与主动入口，不执行任何玩法效果或持有对局状态。

## 游戏、回合与六个标准阶段的全部已知监听时机；数组顺序按规则流程排列，修改会影响文档与测试中的标准顺序。
## roundEnd 是真实轮末时机：普通回合结束且轮转回到轮锚点时派发一次，先于 roundStart，额外回合不派发。
## gameStart 的位置就是它的权威定义：起始手牌与手气卡流程全部结束之后、第一轮开始之前派发，
## 因此该时机的内容（例如往牌堆加入专属牌）不会参与任何一次手气卡重发。
const GAME_PHASE_TIMINGS: Array[String] = [
	"enterGame", "gameDrawBefore", "gameDrawBegin", "gameDrawAfter", "gameStart", "roundEnd", "roundStart",
	"phaseBefore", "phaseBeforeStart", "phaseBeforeEnd", "phaseBeginStart", "phaseBegin", "phaseChange", "phaseEnd", "phaseAfter", "phaseOver", "phaseCancelled",
	"phaseZhunbeiBefore", "phaseZhunbeiBegin", "phaseZhunbei", "phaseZhunbeiEnd", "phaseZhunbeiAfter", "phaseZhunbeiCancelled", "phaseZhunbeiSkipped",
	"phaseJudgeBefore", "phaseJudgeBegin", "phaseJudge", "phaseJudgeEnd", "phaseJudgeAfter", "phaseJudgeCancelled", "phaseJudgeSkipped",
	"phaseDrawBefore", "phaseDrawBegin", "phaseDrawBegin1", "phaseDrawBegin2", "phaseDrawEnd", "phaseDrawAfter", "phaseDrawCancelled", "phaseDrawSkipped",
	"phaseUseBefore", "phaseUseBegin", "phaseUseEnd", "phaseUseAfter", "phaseUseCancelled", "phaseUseSkipped",
	"phaseDiscardBefore", "phaseDiscardBegin", "phaseDiscardEnd", "phaseDiscardAfter", "phaseDiscardCancelled", "phaseDiscardSkipped",
	"phaseJieshuBefore", "phaseJieshuBegin", "phaseJieshu", "phaseJieshuEnd", "phaseJieshuAfter", "phaseJieshuCancelled", "phaseJieshuSkipped",
]

## 使用牌、逐目标生效、响应与内置牌专属流程时机；顺序与 CardUseEvent 和响应流水线保持一致。
const CARD_RESPONSE_TIMINGS: Array[String] = [
	"chooseToUseBefore", "chooseToUseBegin", "chooseToUseAfter",
	"chooseToRespondBefore", "chooseToRespondBegin", "chooseToRespondAfter",
	"useCardBefore", "useCardBegin", "useCard0", "useCard1", "yingbian", "useCard2", "useCard", "useCardEnd", "useCardAfter", "useCardCancelled",
	"useCardToBefore", "useCardToBegin", "useCardToEnd", "useCardToAfter", "useCardToCancelled", "useCardToOmitted", "useCardToExcluded",
	"useCardToPlayer", "useCardToPlayered", "useCardToTarget", "useCardToTargeted",
	"respondBefore", "respondBegin", "respond", "respondEnd", "respondAfter", "eventNeutralized", "yingbianZhuzhanBegin",
	"shaBefore", "shaBegin", "shaHit", "shaMiss", "shaDamage", "shaEnd", "shaAfter", "shaCancelled",
	"juedouBegin", "juedou", "juedouAfter", "huogongBegin", "taoBegin", "wuguRemained",
]

## 伤害事件从最早拦截到最终完成的全部时机；Begin1 至 Begin4 必须严格按数组顺序派发。
const DAMAGE_TIMINGS: Array[String] = [
	"damageBefore", "damageBegin", "damageBegin1", "damageBegin2", "damageBegin3", "damageBegin4",
	"damage", "damageZero", "damageSource", "damageEnd", "damageAfter", "damagePointBefore", "damagePointBegin", "damagePoint", "damagePointAfter", "damageCancelled",
]

## 体力、体力上限、护甲、濒死、死亡、连环和翻面时机；只定义名称，不限定具体技能效果。
const HEALTH_STATE_TIMINGS: Array[String] = [
	"changeHp",
	"recoverBefore", "recoverBegin", "recoverEnd", "recoverAfter",
	"loseHpBefore", "loseHpBegin", "loseHpEnd", "loseHpAfter",
	"gainMaxHpBefore", "gainMaxHpBegin", "gainMaxHpEnd", "gainMaxHpAfter",
	"loseMaxHpBefore", "loseMaxHpBegin", "loseMaxHpEnd", "loseMaxHpAfter",
	"changeHujiaBefore", "changeHujiaAfter",
	"dyingBefore", "dyingBegin", "dying", "dyingAfter",
	"dieBefore", "dieBegin", "die", "dieEnd", "dieAfter",
	"linkBefore", "linkBegin", "linkEnd", "linkAfter",
	"turnOverBefore", "turnOverEnd", "turnOverAfter",
]

## 实体牌获得、失去、弃置、摸取、装备和特殊区域移动时机；区域变化必须通过统一移动端口派发。
const CARD_MOVE_TIMINGS: Array[String] = [
	"gainBefore", "gainBegin", "gainEnd", "gainAfter",
	"loseBefore", "loseBegin", "loseEnd", "loseAfter", "loseAsyncEnd", "loseAsyncAfter",
	"discardBefore", "discardBegin", "discardEnd", "discardAfter", "cardsDiscardEnd", "cardsDiscardAfter", "loseToDiscardpileAfter",
	# 一次面向规则的弃置动作（弃置N张、弃至上限、技能要求弃牌）全部结算完成后派发一次；
	# 载荷 card_uids 为整批牌，供“当你弃置牌时”类技能按一次动作整批判定，避免逐张事件无法表达“这些牌”。
	"cardsDiscardedBatchAfter",
	# 一次面向规则的获得动作（摸牌、技能一次给多张、单张获得）全部结算完成后派发一次；
	# 载荷 card_uids 为整批牌、batch_size 为张数，供“当你一次性获得至少两张牌时”类技能整批判定。
	# 与 cardsDiscardedBatchAfter 对称：单张获得同样派发一次（batch_size 为1），批次边界由核心层给出而不由内容层猜测。
	"cardsGainedBatchAfter",
	"drawBefore", "drawBegin", "drawEnd", "drawAfter", "drawCancelled",
	"equipBefore", "equipEnd", "equipAfter", "disableEquipBefore", "disableEquipAfter", "enableEquipAfter",
	"addJudgeBefore", "addJudgeEnd", "addJudgeAfter", "disableJudgeBefore", "disableJudgeAfter", "enableJudgeAfter", "addToExpansionEnd", "addToExpansionAfter",
]

## 判定与拼点时机；当前未实现的玩法仍保留稳定名称供后续内容直接订阅。
const JUDGE_COMPARE_TIMINGS: Array[String] = [
	"judgeBefore", "judgeBegin", "judge", "judgeFixing", "judgeEnd", "judgeAfter",
	"chooseToCompareBegin", "chooseToCompareAfter", "compare", "compareMultipleAfter",
]

## 通用玩家选择时机；具体候选和选择结果继续由 ChoiceRequest 与 ChoiceResponse 承载。
const CHOICE_TIMINGS: Array[String] = [
	"chooseBoolBegin", "chooseButtonBegin", "chooseCardBegin", "chooseCardTargetBegin", "chooseControlBegin", "choosePlayerCardBegin", "chooseTargetBegin",
	"chooseToDiscardBegin", "chooseToGiveBegin", "chooseToMoveBegin",
	"gainPlayerCardBegin", "discardPlayerCardBegin", "rewriteDiscardResult", "rewriteGainResult",
]

## 技能声明、执行和触发器询问时机；主动技能与被动技能共用这些稳定事件名。
const SKILL_TIMINGS: Array[String] = [
	"logSkillBegin", "logSkill", "useSkillBegin", "useSkill", "useSkillAfter", "skillAfter", "triggerInvisible", "triggerAfter",
]

## 轮回技进入与离开轮回、轮回节的标准生命周期时机；轮回服务统一派发，具体技能不得另造同义事件名。
const REINCARNATION_TIMINGS: Array[String] = [
	"reincarnationStart", "reincarnationEnd", "reincarnationSectionStart", "reincarnationSectionEnd",
]

## 武将技能变化、移除武将牌、明置手牌、领袖状态和洗牌时机；没有对应规则时不会凭空派发。
const MODE_TIMINGS: Array[String] = [
	"changeSkillsAfter", "removeCharacterBefore", "removeCharacterEnd", "hideShownCardsAfter", "zhuUpdate", "washCard",
]

## 主动技能可声明的四种发动入口；数组顺序按常见主动使用、用牌询问、响应询问和普通选牌排列。
const ACTIVE_ENTRIES: Array[String] = ["phaseUse", "chooseToUse", "chooseToRespond", "chooseCard"]

## 主要阶段的稳定内部名称；技能按此集合识别判定、摸牌、出牌与弃牌阶段，避免重复维护字符串白名单。
const MAIN_PHASES: Array[String] = ["judgment", "draw", "play", "discard"]

## 主要阶段内部名称到标准时机前缀的唯一映射；阶段流程、跳过逻辑与内容脚本不得分别拼写另一份同义表。
const MAIN_PHASE_TIMING_PREFIXES: Dictionary = {
	"judgment": "phaseJudge",
	"draw": "phaseDraw",
	"play": "phaseUse",
	"discard": "phaseDiscard",
}


## 返回全部标准监听时机的新数组；调用方修改返回值不会污染静态目录。
static func get_all_timing_names() -> Array[String]:
	# 完整时机结果；按分类顺序拼接，测试会校验总数和重复项。
	var result: Array[String] = []
	result.append_array(GAME_PHASE_TIMINGS)
	result.append_array(CARD_RESPONSE_TIMINGS)
	result.append_array(DAMAGE_TIMINGS)
	result.append_array(HEALTH_STATE_TIMINGS)
	result.append_array(CARD_MOVE_TIMINGS)
	result.append_array(JUDGE_COMPARE_TIMINGS)
	result.append_array(CHOICE_TIMINGS)
	result.append_array(SKILL_TIMINGS)
	result.append_array(REINCARNATION_TIMINGS)
	result.append_array(MODE_TIMINGS)
	return result


## 返回事件名是否属于标准监听时机；空字符串和未登记自定义事件返回 false。
static func has_timing(event_name: String) -> bool:
	return not event_name.is_empty() and get_all_timing_names().has(event_name)


## 返回名称是否属于四种主动技能发动入口；用于技能元数据校验与选择请求候选生成。
static func has_active_entry(entry_name: String) -> bool:
	return ACTIVE_ENTRIES.has(entry_name)


## 判断内部阶段名是否属于主要阶段；空值、准备阶段与结束阶段均返回 false。
static func is_main_phase(phase_name: String) -> bool:
	return MAIN_PHASES.has(phase_name)


## 返回主要阶段指定生命周期节点的标准时机名；未知阶段返回空字符串，suffix 通常为 Before、Begin、End、After 或 Skipped。
static func get_main_phase_timing_name(phase_name: String, suffix: String) -> String:
	# 当前阶段对应的稳定前缀；空值表示调用方传入了非主要阶段，不能构造伪时机。
	var timing_prefix: String = str(MAIN_PHASE_TIMING_PREFIXES.get(phase_name, ""))
	if timing_prefix.is_empty():
		return ""
	return "%s%s" % [timing_prefix, suffix]
