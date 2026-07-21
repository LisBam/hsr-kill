extends SkillDefinition

## 【弦奏】技能源码。每个主要阶段开始时可重铸一种本轮尚未使用的花色，并跳过该阶段。

## 四种实体花色的稳定集合；none虚拟花色不消耗也不能满足本技能的每轮额度。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 当前记录对应的全局轮数；默认-1表示尚未进入任何有效轮次。
var _tracked_round_number: int = -1

## 本轮已经用于发动弦奏的花色集合；键为稳定英文花色，值固定为true。
var _used_suits_this_round: Dictionary = {}


## 写入触发技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"xianzou",
		"name":"弦奏",
		"trigger":["phaseJudgeBegin", "phaseDrawBegin", "phaseUseBegin", "phaseDiscardBegin"],
		"ui_enabled":false,
		"description":"每个主要阶段开始时，你可以重铸一张手牌并跳过该阶段，若为弃牌阶段，你将手牌数调整至X。每轮每种花色限一次。（X等于你的当前体力值。）",
	})


## 订阅四个主要阶段的Begin时机；所有阶段共用同一花色额度与恢复流程。
func install() -> void:
	subscribe_timing("phaseJudgeBegin", _on_main_phase_begin.bind("judgment"), "player")
	subscribe_timing("phaseDrawBegin", _on_main_phase_begin.bind("draw"), "player")
	subscribe_timing("phaseUseBegin", _on_main_phase_begin.bind("play"), "player")
	subscribe_timing("phaseDiscardBegin", _on_main_phase_begin.bind("discard"), "player")


## 在主要阶段开始时提供本轮未使用花色的普通手牌；取消不会消耗该花色额度。
func _on_main_phase_begin(_event: RuleEvent, phase_name: String) -> void:
	_sync_round_state()
	var candidates: Array[Dictionary] = []
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	for candidate: Dictionary in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		var card: CardInstance = owner.find_hand_card(int(candidate.get("uid", -1)))
		if card != null and CARD_SUITS.has(card.suit) and not _used_suits_this_round.has(card.suit):
			candidates.append(candidate)
	if not candidates.is_empty():
		request_card_selection("弦奏", "你可以重铸一张手牌并跳过%s" % {"judgment":"判定阶段", "draw":"摸牌阶段", "play":"出牌阶段", "discard":"弃牌阶段"}.get(phase_name, phase_name), candidates, 0, 1, true, {"kind":"xianzou_recast", "phase_name":phase_name})


## 恢复重铸选择；移动前锁定花色额度，随后等待完整重铸与嵌套触发再处理阶段效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "xianzou_recast" or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != 1:
		return true
	_sync_round_state()
	var owner: PlayerState = get_owner_skill_player().get_state()
	var card: CardInstance = owner.find_hand_card(response.card_ids[0]) if owner != null else null
	if card == null or not CARD_SUITS.has(card.suit) or _used_suits_this_round.has(card.suit):
		return true
	_used_suits_this_round[card.suit] = true
	var phase_name: String = str(context.get("phase_name", ""))
	announce_activation({"card_uid":card.uid, "suit":card.suit, "phase_name":phase_name})
	if not bool(host.call("recast_hand_card", owner_player_id, card.uid)):
		_used_suits_this_round.erase(card.suit)
		return true
	var continuation: Dictionary = {"kind":"xianzou_after_recast", "phase_name":phase_name}
	if host.has_pending_card_choice():
		defer_settlement(continuation)
	else:
		_continue_after_recast(continuation)
	return true


## 恢复重铸或调整手牌数产生的嵌套选择，并进入对应阶段跳过步骤。
func continue_settlement(context: Dictionary) -> bool:
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "xianzou_after_recast":
		_continue_after_recast(context)
		return true
	if choice_kind == "xianzou_skip_phase":
		host.call("skip_current_main_phase", owner_player_id, str(context.get("phase_name", "")), get_id())
		return true
	return false


## 弃牌阶段先将手牌数调整至当前体力值，其他主要阶段直接进入跳过；所有摸弃触发均先于跳过完成。
func _continue_after_recast(context: Dictionary) -> void:
	var phase_name: String = str(context.get("phase_name", ""))
	if phase_name != "discard":
		host.call("skip_current_main_phase", owner_player_id, phase_name, get_id())
		return
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	var completion_context: Dictionary = {"kind":"xianzou_skip_phase", "phase_name":phase_name, "skill_owner_id":owner_player_id, "skill_id":get_id()}
	host.call("adjust_hand_size", owner_player_id, owner.hp, completion_context)
	if not host.has_pending_card_choice():
		host.call("skip_current_main_phase", owner_player_id, phase_name, get_id())


## 在全局轮数变化时清空四花色额度；额外回合不会增加round_number，因此继续共享本轮限制。
func _sync_round_state() -> void:
	if _tracked_round_number == host.state.round_number:
		return
	_tracked_round_number = host.state.round_number
	_used_suits_this_round.clear()


## 根据阶段收益评估是否重铸；弃牌阶段手牌不足体力时优先发动，摸牌阶段通常保留正常摸2张。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "xianzou_recast":
		return 0.0
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != 1:
		return 0.0
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	var phase_name: String = str(context.get("phase_name", ""))
	var phase_score: float = 0.2
	if phase_name == "draw":
		phase_score = -1.5
	elif phase_name == "play":
		phase_score = -0.25 if int(owner.get("hand_count", 0)) > 2 else 0.3
	elif phase_name == "discard":
		phase_score = float(int(owner.get("hp", 0)) - int(owner.get("hand_count", 0))) * 0.9 + 0.4
	elif phase_name == "judgment":
		phase_score = 1.2 if not (owner.get("judgment_area", []) as Array).is_empty() else 0.15
	return phase_score - evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id) * 0.08
