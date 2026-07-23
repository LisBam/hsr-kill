extends CardDefinition

## 【火攻】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "huogong",
		"original_name": "火攻",
		"custom_name": "焚烧",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "fire_attack",
		"nature": "fire",
		"target_mode": "single_with_hand",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "目标展示一张手牌，你可弃置一张同花色手牌并对其造成1点火焰伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":9.2, "value":[3.0, 1.0], "target_result":-1.15, "damage":true, "fire_damage":true, "nature_damage":true},
		"ai_target_attitude": "hostile",
	})


## 执行【火攻】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.emit_rule_timing("huogongBegin", actor_id, actor_id, target_id, {"parent_card_uid":card.uid, "card_id":card.definition_id})
		_request_shown_card(resolver, card.uid, actor_id, target_id)
		if resolver.host.has_pending_card_choice():
			return "pending"
	return resolver.default_destination()


## 请求目标展示一张普通手牌；选择恢复上下文始终保留父牌 UID、使用者和目标。
func _request_shown_card(resolver: Object, parent_card_uid: int, actor_id: int, target_id: int) -> void:
	# 目标手牌候选；目标本人查看时全部正面显示。
	var candidates: Array[Dictionary] = resolver.host.get_hand_candidates(target_id, target_id)
	# 展示阶段上下文；异步恢复后继续创建同花色弃牌请求。
	var context: Dictionary = {"kind":"fire_attack_show", "parent_card_uid":parent_card_uid, "actor_id":actor_id, "target_id":target_id}
	# 目标选择结果；火攻要求且只允许展示一张手牌。
	var selected_uids: Array[int] = resolver.host.request_card_choice(target_id, "火攻展示", "请选择一张手牌展示", candidates, 1, 1, false, context)
	if resolver.host.has_pending_card_choice() or selected_uids.is_empty():
		return
	_apply_shown_card(resolver, context, selected_uids[0])


## 公开目标手牌并请求使用者决定是否弃置一张同花色手牌。
func _apply_shown_card(resolver: Object, context: Dictionary, shown_card_uid: int) -> void:
	# 火攻使用者 ID；负责后续弃牌和造成伤害。
	var actor_id: int = int(context.get("actor_id", -1))
	# 火攻目标 ID；展示牌必须仍属于其普通手牌区。
	var target_id: int = int(context.get("target_id", -1))
	# 被展示手牌；展示端口只公开牌面，不移动实体。
	var shown_card: CardInstance = resolver.host.reveal_hand_card(target_id, shown_card_uid, "fire_attack")
	if shown_card == null:
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
		return
	# 火攻使用者状态；用于筛选同花色普通手牌。
	var actor: PlayerState = resolver.state.get_player(actor_id)
	if actor == null:
		return
	# 同花色弃牌候选；木牛“粮”和装备不能作为火攻费用。
	var discard_candidates: Array[Dictionary] = []
	for candidate: Dictionary in resolver.host.get_hand_candidates(actor_id, actor_id):
		# 候选实体；使用 UID 回查当前手牌并读取真实花色。
		var candidate_card: CardInstance = actor.find_hand_card(int(candidate.get("uid", -1)))
		if candidate_card != null and candidate_card.suit == shown_card.suit:
			discard_candidates.append(candidate)
	# 弃牌阶段上下文；空选择表示放弃造成火焰伤害。
	# private_info_safe_prompt：同花色手牌属于隐藏信息，候选为空时仍必须完整询问并由持有者手动取消，禁止静默跳过以免泄露手牌。
	var discard_context: Dictionary = {
		"kind":"fire_attack_discard",
		"parent_card_uid":int(context.get("parent_card_uid", -1)),
		"actor_id":actor_id,
		"target_id":target_id,
		"suit":shown_card.suit,
		"private_info_safe_prompt":true,
	}
	# 使用者选择结果；允许取消且至多弃置一张同花色手牌。即使无同花色候选也不得跳过本询问。
	var selected_uids: Array[int] = resolver.host.request_card_choice(actor_id, "火攻弃牌", "是否弃置一张同花色手牌？", discard_candidates, 0, 1, true, discard_context)
	if resolver.host.has_pending_card_choice():
		return
	_apply_discard(resolver, discard_context, selected_uids)


## 应用同花色弃牌；只有费用仍合法且成功弃置时造成1点火焰伤害。
func _apply_discard(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	# 火攻使用者ID；失败目标记忆与费用复核共用该稳定来源。
	var actor_id: int = int(context.get("actor_id", -1))
	# 火攻目标ID；本回合后续AI动作会据此避开重复无效火攻。
	var target_id: int = int(context.get("target_id", -1))
	if selected_uids.is_empty():
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
		return
	# 火攻使用者 ID；所选费用必须仍位于其普通手牌区。
	# 使用者ID已在失败目标记录前读取；此处继续用于查询实体费用牌。
	# 当前所选手牌；等待期间移动或花色不符时支付失败。
	var selected_card: CardInstance = resolver.state.get_player(actor_id).find_hand_card(selected_uids[0]) if resolver.state.get_player(actor_id) != null else null
	if selected_card == null or selected_card.suit != str(context.get("suit", "")):
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
		return
	if resolver.host.discard_card_from_hand(actor_id, selected_card.uid):
		# 伤害前目标状态；累计受伤次数可区分正常命中与被技能取消、减为0等未造成伤害结果。
		var target: PlayerState = resolver.state.get_player(target_id)
		# 伤害前累计受伤次数；目标不存在时使用-1并在结算后记录本次失败。
		var previous_damage_taken_count: int = target.damage_taken_count if target != null else -1
		# 来源牌上下文；制动等“此牌受到的直接响应数”效果通过父牌UID读取同一张【火攻】的无懈链。
		var source_context: Dictionary = {"card_user_id":actor_id, "parent_card_uid":int(context.get("parent_card_uid", -1)), "damage_card_target_count":1}
		resolver.host.damage(actor_id, target_id, 1, "fire", "huogong", false, false, source_context)
		if target == null or target.damage_taken_count <= previous_damage_taken_count:
			resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
	else:
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)


## 恢复火攻展示或弃牌选择；异步链结束后推进当前逐目标结算。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	# 选择用途；火攻只创建展示和同花色弃牌两类请求。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "fire_attack_show":
		if not selected_uids.is_empty():
			_apply_shown_card(resolver, context, selected_uids[0])
		if not resolver.host.has_pending_card_choice():
			resolver.host.complete_card_target(int(context.get("parent_card_uid", -1)))
		return true
	if choice_kind == "fire_attack_discard":
		_apply_discard(resolver, context, selected_uids)
		resolver.host.complete_card_target(int(context.get("parent_card_uid", -1)))
		return true
	return false


## 火攻被无懈抵消时记住本回合失败目标，防止AI立即再次对同一角色使用火攻。
func records_failed_ai_target_when_negated() -> bool:
	return true


## 修正火攻AI目标；本回合已经火攻但未造成伤害的角色不再成为候选。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 火攻使用者快照；失败目标记忆属于自身当前回合公开行为摘要。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, int(action.get("actor_id", -1)))
	# 已失败目标数组；异常旧快照缺失时保持空数组。
	var failed_target_ids: Array = (actor.get("ai_failed_card_target_ids", {}) as Dictionary).get(get_id(), []) as Array
	for target_variant: Variant in action.get("target_ids", []) as Array:
		if failed_target_ids.has(int(target_variant)):
			return -INF
	return current_score
