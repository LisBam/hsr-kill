extends SkillDefinition

## 【飞扬】技能源码。判定阶段开始时，若判定区有牌，可弃置两张手牌再弃置判定区一张牌。


## 写入技能静态信息；技能描述必须与需求提供的原文完全一致。
func _init() -> void:
	super({
		"id": "feiyang",
		"name": "飞扬",
		"trigger": "phaseJudgeBegin",
		"ui_enabled": false,
		"description": "判定阶段开始时，若你的判定区内有牌，你可以弃置两张手牌，然后弃置判定区内的一张牌",
	})


## 订阅持有者判定阶段开始时机；只有成功进入 Begin 后才会派发。
func install() -> void:
	subscribe_timing("phaseJudgeBegin", _on_phase_judge_begin, "player")


## 判定阶段开始时检查判定区与手牌数量；满足费用时询问是否发动。
func _on_phase_judge_begin(_event: RuleEvent) -> void:
	# 技能持有者；死亡或离场后基类条件已过滤，此处再防御读取状态。
	var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.state != null else null
	if owner == null or not owner.alive or owner.out_of_game:
		return
	if owner.judgment_area.is_empty():
		return
	if owner.hand.size() < 2:
		return
	request_card_selection("飞扬", "是否发动【飞扬】弃置两张手牌，然后弃置判定区内的一张牌？", [], 0, 0, true, {"kind":"feiyang_confirm", "ai_allow_confirm":true})


## 恢复确认、弃手牌与弃判定区三步选择；任一步取消或费用不足时中止后续步骤。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 当前恢复步骤；确认、弃手牌、弃判定区使用不同 kind。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "feiyang_confirm":
		if response == null or not response.confirmed:
			return true
		# 确认后再次读取持有者；等待期间判定区或手牌可能变化。
		var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.state != null else null
		if owner == null or owner.judgment_area.is_empty() or owner.hand.size() < 2:
			return true
		# 手牌候选；飞扬费用限定手牌，不包含装备与木牛“粮”。
		var hand_candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
		if hand_candidates.size() < 2:
			return true
		request_card_selection("飞扬", "请弃置两张手牌", hand_candidates, 2, 2, false, {"kind":"feiyang_discard_hand"})
		return true
	if choice_kind == "feiyang_discard_hand":
		if response == null or response.card_ids.size() != 2:
			return true
		# 实际弃置数量；必须成功弃满两张才继续弃判定区。
		var discarded_count: int = int(host.call("discard_selected_hand_cards", owner_player_id, response.card_ids))
		if discarded_count < 2:
			return true
		# 判定区候选；只读当前持有者判定区实体，UID 作为唯一选择边界。
		var judgment_candidates: Array[Dictionary] = host.call("get_judgment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
		if judgment_candidates.is_empty():
			announce_activation({"hand_card_uids":response.card_ids.duplicate()})
			return true
		request_card_selection("飞扬", "请弃置判定区内的一张牌", judgment_candidates, 1, 1, false, {"kind":"feiyang_discard_judgment", "hand_card_uids":response.card_ids.duplicate()})
		return true
	if choice_kind == "feiyang_discard_judgment":
		if response != null and not response.card_ids.is_empty():
			host.call("discard_selected_judgment_card", owner_player_id, response.card_ids[0])
			announce_activation({"hand_card_uids":context.get("hand_card_uids", []), "judgment_card_uid":response.card_ids[0]})
		return true
	return false


## 为确认与弃牌步骤评分；判定区有牌且手牌足够时优先发动，弃置最低价值手牌与任意判定牌。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；确认与两类弃牌使用不同 kind。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 当前选择步骤；未知步骤不修改通用评分。
	var choice_kind: String = str(context.get("kind", ""))
	# 标准选择负载；confirmed 与 card_ids 由基础策略填充。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if choice_kind == "feiyang_confirm":
		if not bool(payload.get("confirmed", false)):
			return 0.0
		# 持有者快照；判定区为空时不值得发动。
		var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id) if evaluator != null and evaluator.has_method("get_player") else {}
		if owner.is_empty():
			for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
				var player: Dictionary = player_variant as Dictionary
				if int(player.get("player_id", -1)) == owner_player_id:
					owner = player
					break
		# 判定区数量；至少一张才构成收益。
		var judgment_count: int = (owner.get("judgment", owner.get("judgment_area", [])) as Array).size()
		if judgment_count <= 0:
			return -1.0
		# 手牌数量；不足两张时确认无意义。
		var hand_count: int = int(owner.get("hand_count", (owner.get("hand", []) as Array).size()))
		if hand_count < 2:
			return -1.0
		# 清理判定区的基础收益；延时锦囊对地主威胁较高，优先清理。
		return 2.5 + float(judgment_count) * 0.5
	if choice_kind == "feiyang_discard_hand":
		# 弃置手牌总价值；优先选择最低价值组合。
		var discarded_value: float = 0.0
		for card_uid_variant: Variant in payload.get("card_ids", []) as Array:
			discarded_value += evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(card_uid_variant), owner_player_id)
		return -discarded_value
	if choice_kind == "feiyang_discard_judgment":
		# 弃置判定区任一张即可，默认均分避免空选。
		return 1.0 if not (payload.get("card_ids", []) as Array).is_empty() else -1.0
	return 0.0
