extends SkillDefinition

## 【星祈】技能源码。准备阶段观看牌堆顶牌、分配一张锦囊，并通过通用双行界面重排其余牌。

## 单次观看牌数上限；固定为5，与技能原文一致。
const MAX_VIEW_COUNT: int = 5

## AI在没有判定区时优先置于牌堆顶的摸牌数量；默认2对应基础摸牌阶段。
const AI_BASE_DRAW_COUNT: int = 2

## AI确认发动星祈的固定收益；100分保证任意可选锦囊都不会因通用选牌成本而被取消，仅影响AI决策。
## 补充：此值提高到10000分，确保后续通用评分或其他技能收益增长时，仍不会压过星祈的无脑确认策略。
const AI_ALWAYS_ACTIVATE_SCORE: float = 10000.0


## 写入触发技能静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"xingqi",
		"name":"星祈",
		"trigger":"phaseZhunbeiBegin",
		"ui_enabled":false,
		"description":"准备阶段，你可以观看牌堆顶的X张牌，然后令一名角色获得其中一张锦囊牌，并将其余的牌以任意顺序放回牌堆顶或牌堆底。（X为场上存活角色数，且至多为5。）",
	})


## 订阅持有者准备阶段开始；同一回合只由标准阶段时机创建一次观看请求。
func install() -> void:
	subscribe_timing("phaseZhunbeiBegin", _on_preparation_begin, "player")


## 构造私有观看候选；所有牌都显示，只有锦囊牌可在第一步选中获得。
func _on_preparation_begin(_event: RuleEvent) -> void:
	var view_count: int = mini(host.state.get_alive_players().size(), MAX_VIEW_COUNT)
	var viewed_candidates: Array[Dictionary] = host.call("get_top_draw_card_candidates", owner_player_id, view_count) as Array[Dictionary]
	if viewed_candidates.is_empty():
		return
	var trick_candidates: Array[Dictionary] = []
	var viewed_uids: Array[int] = []
	for candidate: Dictionary in viewed_candidates:
		var card_uid: int = int(candidate.get("uid", -1))
		viewed_uids.append(card_uid)
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(GameDatabase.get_card(str(card_data.get("definition_id", ""))).get("type", "")) == "trick":
			trick_candidates.append(candidate)
	# 观看牌中没有任何锦囊时，跳过选锦囊与选受益角色，直接进入牌堆顶底排布，避免空候选弹窗后卡死。
	if trick_candidates.is_empty():
		_begin_arrangement(viewed_uids)
		return
	request_card_selection("星祈", "请选择其中一张锦囊牌", trick_candidates, 1, 1, true, {"kind":"xingqi_trick", "viewed_card_uids":viewed_uids, "display_candidates":viewed_candidates})


## 恢复锦囊、受益目标或最终牌堆排序选择。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "xingqi_trick":
		if not response.confirmed:
			return true
		var viewed_uids: Array[int] = _int_values(context.get("viewed_card_uids", []) as Array)
		if response.card_ids.size() == 1:
			var target_ids: Array[int] = []
			for player: PlayerState in host.state.players:
				if player.alive and not player.out_of_game:
					target_ids.append(player.player_id)
			request_target_selection("【星祈】请选择获得锦囊牌的角色", target_ids, 1, 1, false, {"kind":"xingqi_recipient", "selected_card_uid":response.card_ids[0], "viewed_card_uids":viewed_uids})
		else:
			_begin_arrangement(viewed_uids)
		return true
	if choice_kind == "xingqi_recipient":
		if response.confirmed and response.target_ids.size() == 1:
			var selected_uid: int = int(context.get("selected_card_uid", -1))
			var recipient_id: int = response.target_ids[0]
			var gained_card: CardInstance = host.call("gain_draw_pile_card_by_uid", recipient_id, selected_uid, get_id()) as CardInstance
			if gained_card != null:
				announce_activation({"target_id":recipient_id, "card_uid":selected_uid})
				observe_identity_behavior([recipient_id], {"target_result":1.0, "gain":true})
			var remaining_uids: Array[int] = _int_values(context.get("viewed_card_uids", []) as Array)
			remaining_uids.erase(selected_uid)
			if host.has_pending_card_choice():
				defer_settlement({"kind":"xingqi_begin_arrangement", "remaining_card_uids":remaining_uids})
			else:
				_begin_arrangement(remaining_uids)
		return true
	if choice_kind == "xingqi_arrangement":
		var ordered_uids: Array[int] = response.card_ids.duplicate()
		var top_count: int = int(response.control_id.trim_prefix("top_count_")) if response.control_id.begins_with("top_count_") else -1
		host.call("arrange_draw_pile_cards", ordered_uids, top_count, get_id())
		return true
	return false


## 恢复获得牌移动触发后的牌堆排序步骤。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "xingqi_begin_arrangement":
		return false
	_begin_arrangement(_int_values(context.get("remaining_card_uids", []) as Array))
	return true


## 为仍位于牌堆中的剩余实体创建双行排序请求，并写入基础AI的判定与摸牌建议。
func _begin_arrangement(remaining_uids: Array[int]) -> void:
	if remaining_uids.is_empty():
		return
	var all_top_candidates: Array[Dictionary] = host.call("get_top_draw_card_candidates", owner_player_id, MAX_VIEW_COUNT) as Array[Dictionary]
	var candidates: Array[Dictionary] = []
	for candidate: Dictionary in all_top_candidates:
		if remaining_uids.has(int(candidate.get("uid", -1))):
			candidates.append(candidate)
	if candidates.is_empty():
		return
	var ai_plan: Dictionary = _build_ai_arrangement(candidates)
	request_pile_arrangement("星祈", "请调整牌堆顶与牌堆底的顺序", candidates, {"kind":"xingqi_arrangement", "ai_ordered_card_uids":ai_plan.get("ordered_card_uids", []), "ai_top_count":int(ai_plan.get("top_count", candidates.size()))})


## 根据判定区与本回合基础摸牌需求构造AI排序；无法找到安全判定牌时优先把全部已知牌置底。
func _build_ai_arrangement(candidates: Array[Dictionary]) -> Dictionary:
	var ordered_candidates: Array[Dictionary] = candidates.duplicate(true)
	ordered_candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _estimate_card_value(left) > _estimate_card_value(right)
	)
	var owner: PlayerState = get_owner_skill_player().get_state()
	var safe_judgment_uid: int = -1
	if owner != null and not owner.judgment_area.is_empty():
		var delayed_id: String = owner.judgment_area.front().definition_id
		for candidate: Dictionary in ordered_candidates:
			if _is_safe_judgment_card(candidate, delayed_id):
				safe_judgment_uid = int(candidate.get("uid", -1))
				break
		if safe_judgment_uid < 0:
			return {"ordered_card_uids":_candidate_uids(ordered_candidates), "top_count":0}
	var top_uids: Array[int] = []
	if safe_judgment_uid >= 0:
		top_uids.append(safe_judgment_uid)
	for candidate: Dictionary in ordered_candidates:
		var card_uid: int = int(candidate.get("uid", -1))
		if card_uid == safe_judgment_uid:
			continue
		if top_uids.size() < AI_BASE_DRAW_COUNT + (1 if safe_judgment_uid >= 0 else 0):
			top_uids.append(card_uid)
	var bottom_uids: Array[int] = _candidate_uids(ordered_candidates)
	for top_uid: int in top_uids:
		bottom_uids.erase(top_uid)
	var ordered_uids: Array[int] = top_uids.duplicate()
	ordered_uids.append_array(bottom_uids)
	return {"ordered_card_uids":ordered_uids, "top_count":top_uids.size()}


## 判断候选是否能令当前最先结算的延时锦囊通过判定。
func _is_safe_judgment_card(candidate: Dictionary, delayed_id: String) -> bool:
	var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
	var suit: String = str(card_data.get("suit", ""))
	var rank: int = int(card_data.get("rank", 0))
	if delayed_id == "lebu":
		return suit == "heart"
	if delayed_id == "bingliang":
		return suit == "club"
	if delayed_id == "shandian":
		return not (suit == "spade" and rank >= 2 and rank <= 9)
	return true


## 返回候选牌的基础AI价值；优先读取ai_use_value，再回退ai.value的首项或常数1。
func _estimate_card_value(candidate: Dictionary) -> float:
	var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
	var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
	if definition.has("ai_use_value"):
		return float(definition.get("ai_use_value", 1.0))
	var ai: Dictionary = definition.get("ai", {}) as Dictionary
	var value: Variant = ai.get("value", 1.0)
	return float((value as Array)[0]) if value is Array and not (value as Array).is_empty() else float(value)


## 将候选字典数组转换为稳定UID数组。
func _candidate_uids(candidates: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for candidate: Dictionary in candidates:
		result.append(int(candidate.get("uid", -1)))
	return result


## 将弱类型数组转换为稳定整数数组。
func _int_values(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


## 第一阶段优先选择高价值锦囊，受益目标阶段优先选择友方与缺牌角色。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "xingqi_trick":
		# 取消动作保持0分；确认动作固定获得必发动收益，同时继续按牌值挑选具体锦囊。
		if not bool(payload.get("confirmed", false)):
			return 0.0
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		return AI_ALWAYS_ACTIVATE_SCORE + evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id) if selected_cards.size() == 1 else AI_ALWAYS_ACTIVATE_SCORE
	if choice_kind == "xingqi_recipient":
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.size() != 1:
			return -100.0
		var target_id: int = int(selected_targets[0])
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		return evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) / 5.0 + maxf(3.0 - float(target.get("hand_count", 0)), 0.0) * 0.25
	return 0.0
