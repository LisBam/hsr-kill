extends SkillDefinition

## 【凌霜】技能源码。当你使用【杀】指定目标时，你可以将你的武将牌翻面；
## 若你因此翻至背面向上，你弃置目标角色两张手牌且令此【杀】不计入出牌阶段使用限制。

## 翻面确认请求种类；恢复时按该值分流。
const TURN_OVER_CHOICE_KIND: String = "lingshuang_turn_over"

## 与【杀】共享的牌效果ID；普通、火、雷【杀】与技能视为的【杀】统一命中。
const SLASH_EFFECT_ID: String = "slash"

## 附加效果弃置的手牌张数；数值2来自技能原文，目标手牌不足时弃置其全部手牌。
const DISCARD_HAND_COUNT: int = 2

## 已经完成过次数豁免的牌UID；保证同一张【杀】只豁免一次。
var _exempted_card_uids: Array[int] = []

## AI：原文提示的敌方手牌阈值；目标手牌数不小于该值且态度为负时无条件发动。
const AI_BLIND_DISCARD_HAND_THRESHOLD: int = 2

## AI：由正面翻至背面会跳过持有者下一个完整回合的机会成本。
const AI_TURN_OVER_COST: float = 2.2

## AI：此【杀】不计入出牌阶段使用限制的价值；等价于多出一次用牌机会。
const AI_FREE_SLASH_VALUE: float = 1.0

## AI：已是背面时本次只翻回正面，属于解除自身翻面，收益固定为正。
const AI_UNFLIP_VALUE: float = 1.0

## AI：持有者体力不高于该值时，被翻面跳过回合会无法自救，返回强负分。
const AI_CRITICAL_HP_THRESHOLD: int = 1


## 写入触发型技能静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"lingshuang",
		"name":"凌霜",
		"trigger":"useCardToTargeted",
		"ui_enabled":false,
		"description":"当你使用【杀】指定目标时，你可以将你的武将牌翻面。若你因此翻至背面向上，你弃置目标角色两张手牌且令此【杀】不计入出牌阶段使用限制。",
	})


## 订阅使用者视角的逐目标时机；该时机属于会写回用牌上下文的四组 useCardTo* 之一。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_card_targeted, "source")


## 持有者使用【杀】指定目标时创建翻面确认；一张【杀】的每个目标都会各自触发一次。
func _on_card_targeted(event: RuleEvent) -> void:
	if host == null:
		return
	# 牌定义；只有【杀】族触发本技能，其他牌指定目标时不询问。
	var definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(definition.get("effect_id", "")) != SLASH_EFFECT_ID:
		return
	# 持有者状态；死亡或离场后不再提供翻面选项。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 目标角色；已死亡或已离场的目标不再询问，避免翻面后无牌可弃。
	var target: PlayerState = get_skill_player(event.target_id).get_state()
	if target == null or not target.alive or target.out_of_game:
		return
	request_card_selection("凌霜", "是否发动【凌霜】将你的武将牌翻面？", [], 0, 0, true, {"kind":TURN_OVER_CHOICE_KIND, "card_uid":int(event.data.get("card_uid", -1)), "target_id":event.target_id, "card_definition_id":str(event.data.get("card_id", "")), "ai_allow_confirm":true})


## 恢复翻面确认；确认后翻转持有者，并只在本次由正面翻至背面时附加弃牌与次数豁免。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if str(context.get("kind", "")) != TURN_OVER_CHOICE_KIND:
		return false
	if not response.confirmed:
		return true
	# 持有者状态；翻面端口只做切换，因此必须先记录翻转前的朝向。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return true
	var was_face_down: bool = owner.face_down
	if not bool(host.call("turn_over_player", owner_player_id, owner_player_id, get_id())):
		return true
	# 翻转后的朝向；由端口切换保证与翻转前相反。
	var is_face_down_now: bool = not was_face_down
	# 目标与牌信息；都在询问时固定，避免结算期间被其他技能改动。
	var target_id: int = int(context.get("target_id", -1))
	var card_uid: int = int(context.get("card_uid", -1))
	var card_definition_id: String = str(context.get("card_definition_id", ""))
	# 附加效果只在“本次由正面翻至背面”时成立，与原文条件逐字对应。
	var discarded_count: int = 0
	var limit_exempted: bool = false
	if is_face_down_now:
		discarded_count = _discard_target_hand_cards(target_id)
		limit_exempted = _exempt_card_use_limit(card_uid, card_definition_id)
	announce_activation({"target_id":target_id, "face_down":is_face_down_now, "discarded_count":discarded_count, "limit_exempted":limit_exempted})
	return true


## 弃置目标角色的两张手牌；不足两张时弃置其全部手牌。
## 使用他人手牌候选端口，候选经过可见性处理，玩家与AI都只能盲选，与既有盲选技能保持同一口径。
func _discard_target_hand_cards(target_id: int) -> int:
	if host == null or target_id < 0:
		return 0
	# 目标手牌候选；他人手牌以可见性受限的候选形式提供。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
	if candidates.is_empty():
		return 0
	# 实际弃置张数；目标手牌不足请求张数时取其全部。
	var discard_count: int = mini(DISCARD_HAND_COUNT, candidates.size())
	# 待弃置的牌UID数组；按候选顺序取前若干张，保证AI与玩家看到同一批候选。
	var selected_uids: Array[int] = []
	for candidate_index: int in range(discard_count):
		selected_uids.append(int((candidates[candidate_index] as Dictionary).get("uid", -1)))
	if selected_uids.is_empty():
		return 0
	return int(host.call("discard_selected_hand_cards", target_id, selected_uids))


## 令本张【杀】不计入出牌阶段使用限制；同一张牌只豁免一次，重复豁免会额外放宽该牌族的可使用次数。
func _exempt_card_use_limit(card_uid: int, card_definition_id: String) -> bool:
	if card_uid < 0 or card_definition_id.is_empty() or host == null:
		return false
	if _exempted_card_uids.has(card_uid):
		return false
	if not bool(host.call("mark_card_use_limit_exempt", owner_player_id, card_definition_id)):
		return false
	_exempted_card_uids.append(card_uid)
	return true


## 评估凌霜的发动收益：对敌人的盲选弃牌按原文提示无条件发动，其余情形按翻面成本折算。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；目标ID与牌信息都在询问时固定。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TURN_OVER_CHOICE_KIND:
		return 0.0
	if not bool((action.get("payload", {}) as Dictionary).get("confirmed", false)):
		return 0.0
	# 持有者快照；翻面会跳过其下一个完整回合，是本次发动的主要代价。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return 0.0
	# 持有者当前朝向；已是背面时本次只会翻回正面。
	var is_face_down_now: bool = bool(owner.get("face_down", false))
	# 目标快照；手牌数与敌我态度共同决定弃牌收益。
	var target_id: int = int(context.get("target_id", -1))
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 已是背面：本次只会翻回正面，属于解除自身翻面，收益固定为正。
	if is_face_down_now:
		return AI_UNFLIP_VALUE
	# 1点体力时被翻面会跳过下个回合而无法自救，返回强负分。
	if int(owner.get("hp", 0)) <= AI_CRITICAL_HP_THRESHOLD:
		return -100.0
	# 原文提示：对手牌数不小于2的敌人目标无条件发动。
	if attitude < 0.0 and int(target.get("hand_count", 0)) >= AI_BLIND_DISCARD_HAND_THRESHOLD:
		return 100.0
	# 通用分支：弃牌收益与次数豁免收益之和必须严格超过翻面代价。
	var discard_value: float = float(mini(DISCARD_HAND_COUNT, int(target.get("hand_count", 0)))) * NonameAIEvaluator.CARD_RESOURCE_VALUE
	return discard_value + AI_FREE_SLASH_VALUE - AI_TURN_OVER_COST
