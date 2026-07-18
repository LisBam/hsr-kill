extends SkillDefinition

## 【录事】技能源码。持有者可反复弃置两张原版牌名字数相同的手牌或装备牌并摸一张牌。

## 录事每次成功结算摸牌数；固定1张。
const DRAW_COUNT: int = 1


## 写入技能静态信息；技能没有阶段次数限制，每次发动都会净减少一张区域牌。
func _init() -> void:
	super({
		"id": "lushi",
		"name": "录事",
		"trigger": "active",
		"enable": "phaseUse",
		"ui_enabled": true,
		"ai_extra_play_phase_value": 1.8,
		"description": "出牌阶段，你可弃置两张牌名字字数相同的牌，然后摸一张牌。",
	})


## 判断当前出牌阶段是否存在至少一组名字数相同的两张牌。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者状态；必须存活在场并处于自己的出牌阶段。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" and not _get_valid_pairs().is_empty()


## 发动录事；AI直接提交两张牌，玩家按钮使用带固定合法组合的统一多选请求。
func activate(context: Dictionary = {}) -> String:
	# 直接动作所选UID；必须恰好两张且仍属于合法同字数组合。
	var selected_uids: Array[int] = []
	for uid_variant: Variant in context.get("card_uids", context.get("selected_card_uids", [])) as Array:
		selected_uids.append(int(uid_variant))
	if selected_uids.size() == 2:
		return "" if _execute_discard_and_draw(selected_uids) else "【录事】所选牌已经失效或牌名字数不同。"
	# 当前牌候选；“两张牌”允许手牌与装备牌，不包含判定区和木牛“粮”。
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 合法组合；提交时由核心再次按UID集合校验，AI也只枚举这些组合。
	var valid_pairs: Array = _get_valid_pairs()
	if valid_pairs.is_empty():
		return "当前没有两张牌名字数相同的牌。"
	request_card_selection("录事", "请选择两张牌名字数相同的牌", candidates, 2, 2, true, {"kind":"lushi_cards", "valid_card_combinations":valid_pairs})
	return ""


## 恢复录事选牌；取消不移动任何牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "lushi_cards" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 2:
		_execute_discard_and_draw(response.card_ids)
	return true


## 在嵌套冥谶等触发选择完成后继续录事的摸牌步骤。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "lushi_draw":
		return false
	host.call("draw", owner_player_id, DRAW_COUNT)
	return true


## 弃置合法牌组并摸牌；装备先于手牌支付，使“失去最后手牌”在本次两牌费用完整移动后触发。
func _execute_discard_and_draw(selected_uids: Array[int]) -> bool:
	if not _pair_is_currently_valid(selected_uids):
		return false
	# 支付顺序；装备牌在前、普通手牌在后，保证最后手牌的loseAfter位于本次费用尾部。
	var ordered_uids: Array[int] = selected_uids.duplicate()
	ordered_uids.sort_custom(func(left_uid: int, right_uid: int) -> bool:
		# 技能持有者当前状态；排序时只读取两张费用是否仍在普通手牌区。
		var owner: PlayerState = get_owner_skill_player().get_state()
		# 左侧费用是否为手牌；true应排在装备之后以延后最后手牌触发。
		var left_is_hand: bool = owner != null and owner.find_hand_card(left_uid) != null
		# 右侧费用是否为手牌；与左侧共同形成装备优先排序。
		var right_is_hand: bool = owner != null and owner.find_hand_card(right_uid) != null
		return int(left_is_hand) < int(right_is_hand)
	)
	if int(host.call("discard_selected_hand_equipment", owner_player_id, ordered_uids)) != 2:
		return false
	announce_activation({"card_uids":selected_uids.duplicate()})
	# 失去最后手牌可能创建冥谶目标选择；录事的“然后摸一张牌”必须等待嵌套技能完整结算。
	if host.has_pending_card_choice():
		defer_settlement({"kind":"lushi_draw"})
	else:
		host.call("draw", owner_player_id, DRAW_COUNT)
	return true


## 返回当前全部合法双牌UID组合；牌名字数固定读取原版规则名，不随界面名称模式变化。
func _get_valid_pairs() -> Array:
	# 当前手牌与装备候选；每项都包含公开定义ID与稳定UID。
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 合法组合结果；两层递增索引避免重复组合和相同实体。
	var result: Array = []
	for first_index: int in range(candidates.size()):
		# 第一张候选；递增索引保证每对实体只出现一次。
		var first_candidate: Dictionary = candidates[first_index]
		# 第一张牌公开数据；包含当前定义ID与稳定UID。
		var first_data: Dictionary = first_candidate.get("card_data", {}) as Dictionary
		# 第一张牌原版名字数；0表示定义缺失并禁止组成费用。
		var first_length: int = int(host.call("get_card_original_name_length", str(first_data.get("definition_id", ""))))
		for second_index: int in range(first_index + 1, candidates.size()):
			# 第二张候选；索引严格大于第一张避免实体重复。
			var second_candidate: Dictionary = candidates[second_index]
			# 第二张牌公开数据；用于读取定义ID。
			var second_data: Dictionary = second_candidate.get("card_data", {}) as Dictionary
			# 第二张牌原版名字数；必须为正且等于第一张。
			var second_length: int = int(host.call("get_card_original_name_length", str(second_data.get("definition_id", ""))))
			if first_length > 0 and first_length == second_length:
				result.append([int(first_candidate.get("uid", -1)), int(second_candidate.get("uid", -1))])
	return result


## 复核提交UID是否仍属于当前合法组合；点击顺序不影响集合匹配。
func _pair_is_currently_valid(selected_uids: Array[int]) -> bool:
	if selected_uids.size() != 2:
		return false
	# 规范化提交UID；升序后点击顺序不影响组合合法性。
	var normalized_selected: Array[int] = selected_uids.duplicate()
	normalized_selected.sort()
	for pair_variant: Variant in _get_valid_pairs():
		# 当前合法组合的规范化UID；用于与提交集合比较。
		var normalized_pair: Array[int] = []
		for uid_variant: Variant in pair_variant as Array:
			normalized_pair.append(int(uid_variant))
		normalized_pair.sort()
		if normalized_pair == normalized_selected:
			return true
	return false


## 为AI枚举全部合法双牌组合；每次动作都会净减少一张牌，因此不会形成无资源循环。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for pair_variant: Variant in _get_valid_pairs():
		# 当前合法费用组合；副本进入动作负载后不再被候选数组修改。
		var card_uids: Array = (pair_variant as Array).duplicate()
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[], "payload":{"skill_id":get_id(), "card_uids":card_uids}})


## 评估录事动作；优先低价值牌组，能弃空全部手牌触发冥谶时获得显著联动奖励。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 主动动作负载；保存AI枚举的两张费用UID。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 所选费用UID；数量不是2时动作无效并返回最低分。
	var selected_uids: Array = payload.get("card_uids", []) as Array
	if selected_uids.size() != 2:
		return -20.0
	# 两张费用牌保留价值；摸一张未知牌使用4.5分基础价值，弃牌净损失按完整价值计算。
	var cost: float = 0.0
	for uid_variant: Variant in selected_uids:
		cost += evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(uid_variant))
	# 录事净评分；固定未知摸牌价值4.5减去完整费用保留价值。
	var score: float = 4.5 - cost
	# 冥谶联动；只有所选UID覆盖当前全部普通手牌时增加奖励，装备不计入“最后的手牌”。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if _owner_has_mingchen(authoritative_snapshot) and _selection_discards_all_hand(owner, selected_uids):
		score += 7.0
	return score


## 评估玩家交互产生的录事牌组；逻辑与直接AI动作保持一致。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；仅处理录事固定合法组合选牌。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "lushi_cards":
		return 0.0
	# 交互动作所选费用UID；转交主动动作评分复用相同逻辑。
	var selected_uids: Array = (action.get("payload", {}) as Dictionary).get("selected_card_uids", []) as Array
	return score_ai_action(authoritative_snapshot, {"payload":{"card_uids":selected_uids}}, evaluator)


## 判断寒鸦当前武将配置是否同时拥有冥谶；技能AI不通过稳定ID假设其他武将必然具备联动。
func _owner_has_mingchen(authoritative_snapshot: Dictionary) -> bool:
	# 技能持有者快照；武将定义中的技能列表决定是否存在联动。
	var owner: Dictionary = _snapshot_player(authoritative_snapshot, owner_player_id)
	return (GameDatabase.get_character(str(owner.get("character_id", ""))).get("skills", []) as Array).has("mingchen")


## 判断所选UID是否覆盖当前全部普通手牌；空手牌不视为通过录事触发最后手牌。
func _selection_discards_all_hand(owner: Dictionary, selected_uids: Array) -> bool:
	# 当前普通手牌快照；装备与木牛“粮”不计入最后手牌条件。
	var hand: Array = owner.get("hand", []) as Array
	if hand.is_empty():
		return false
	for card_variant: Variant in hand:
		if not selected_uids.has(int((card_variant as Dictionary).get("uid", -1))):
			return false
	return true


## 从权威快照读取指定玩家；不存在时返回空字典。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后返回。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
