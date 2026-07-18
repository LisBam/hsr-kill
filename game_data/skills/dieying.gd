extends SkillDefinition

## 【蝶影】技能源码。技能统计持有者本回合内所有进入弃牌堆的【杀】，并在回合结束时执行等量换牌。

## 摸牌与弃牌数量上限；固定为5，修改后会同步改变技能的最大换牌规模。
const MAX_SLASH_COUNT: int = 5

## 当前是否正在统计持有者的回合；从 phaseBefore 开始，到 phaseEnd 创建发动询问时结束。
var _counting_owner_turn: bool = false

## 当前统计到的【杀】数量；范围0至5，超过上限的弃牌移动不再增加。
var _slash_count: int = 0


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "dieying",
		"name": "蝶影",
		"trigger": "phaseEnd",
		"ui_enabled": false,
		"description": "回合结束时，你可以摸X张牌，然后弃置等量的牌。（X为本阶段内进入弃牌堆的【杀】数，X至多为5。）",
	})


## 订阅持有者回合边界与全局弃牌堆移动；统计依据唯一移牌时机，不区分进入弃牌堆的原因。
func install() -> void:
	subscribe_timing("phaseBefore", _on_owner_turn_before, "player")
	subscribe_timing("cardsDiscardAfter", _on_card_entered_discard, "global")
	subscribe_timing("phaseEnd", _on_owner_phase_end, "player")


## 持有者新回合开始时清空统计并开启记录。
func _on_owner_turn_before(_event: RuleEvent) -> void:
	_counting_owner_turn = true
	_slash_count = 0


## 任意实体牌进入弃牌堆后检查其牌族；使用结算、主动弃置、响应、判定与区域清理全部计入。
func _on_card_entered_discard(event: RuleEvent) -> void:
	if not _counting_owner_turn or _slash_count >= MAX_SLASH_COUNT:
		return
	for card_uid_variant: Variant in event.data.get("card_uids", []) as Array:
		# 已进入弃牌堆的实体牌；后置时机保证可以从权威弃牌堆按 UID 查回定义。
		var discarded_card: CardInstance = _find_discard_card(int(card_uid_variant))
		if discarded_card == null:
			continue
		# 当前实体的逻辑定义；普通、火和雷【杀】统一通过 effect_id=slash 计数。
		var definition: Dictionary = GameDatabase.get_card(discarded_card.definition_id)
		if str(definition.get("effect_id", "")) == "slash":
			_slash_count = mini(_slash_count + 1, MAX_SLASH_COUNT)


## 回合结束时关闭统计并询问是否发动；X快照写入上下文，后续弃牌移动不会改写本次结算值。
func _on_owner_phase_end(_event: RuleEvent) -> void:
	_counting_owner_turn = false
	if _slash_count <= 0:
		return
	request_card_selection("蝶影", "是否发动【蝶影】摸%d张牌并弃置等量的牌？" % _slash_count, [], 0, 0, true, {"kind":"dieying_confirm", "draw_count":_slash_count, "ai_allow_confirm":true})


## 恢复发动确认或后续弃牌选择；确认后先摸X张，再强制弃置等量的手牌或装备牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 当前恢复步骤；确认和弃牌使用不同 kind，防止旧选择误进入新一轮结算。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "dieying_confirm":
		if response != null and response.confirmed:
			# 本次固定换牌数；范围在创建请求时已经限制为1至5。
			var draw_count: int = clampi(int(context.get("draw_count", 0)), 0, MAX_SLASH_COUNT)
			host.call("draw", owner_player_id, draw_count)
			if host.state.game_over:
				return true
			# 摸牌后候选；至少包含刚摸到的牌，装备也可作为“牌”支付弃置数量。
			var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
			var required_count: int = mini(draw_count, candidates.size())
			request_card_selection("蝶影", "请弃置%d张牌" % required_count, candidates, required_count, required_count, false, {"kind":"dieying_discard"})
		return true
	if choice_kind == "dieying_discard":
		if response != null:
			host.call("discard_selected_hand_equipment", owner_player_id, response.card_ids)
		return true
	return false


## 按 UID 查找当前弃牌堆中的实体牌；只读查询不修改区域数组或牌面状态。
func _find_discard_card(card_uid: int) -> CardInstance:
	for card: CardInstance in host.state.discard_pile:
		if card.uid == card_uid:
			return card
	return null


## 为【蝶影】确认与弃牌步骤评分；换牌数量越多越值得发动，强制弃牌仍优先选择最低价值组合。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；确认和弃牌使用不同 kind。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 当前选择步骤；未知步骤不修改通用评分。
	var choice_kind: String = str(context.get("kind", ""))
	# 标准选择负载；confirmed 区分发动与取消。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if choice_kind == "dieying_confirm":
		# 固定换牌数；每张新牌按约0.8分信息与手牌质量提升估值。
		var draw_count: int = clampi(int(context.get("draw_count", 0)), 0, MAX_SLASH_COUNT)
		return float(draw_count) * 0.8 if bool(payload.get("confirmed", false)) else 0.0
	if choice_kind == "dieying_discard":
		# 弃置总价值；返回负值后与通用强制弃牌评分共同保证选择最低价值牌组。
		var discarded_value: float = 0.0
		for card_uid_variant: Variant in payload.get("selected_card_uids", []) as Array:
			discarded_value += evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(card_uid_variant), owner_player_id)
		return -discarded_value
	return 0.0
