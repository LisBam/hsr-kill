extends CardDefinition

## 【火攻】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "huogong",
		"original_name": "火攻",
		"custom_name": "熔核攻势",
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
	})


## 执行【火攻】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
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
	var discard_context: Dictionary = {"kind":"fire_attack_discard", "parent_card_uid":int(context.get("parent_card_uid", -1)), "actor_id":actor_id, "target_id":target_id, "suit":shown_card.suit}
	# 使用者选择结果；允许取消且至多弃置一张同花色手牌。
	var selected_uids: Array[int] = resolver.host.request_card_choice(actor_id, "火攻弃牌", "是否弃置一张同花色手牌？", discard_candidates, 0, 1, true, discard_context)
	if resolver.host.has_pending_card_choice():
		return
	_apply_discard(resolver, discard_context, selected_uids)


## 应用同花色弃牌；只有费用仍合法且成功弃置时造成1点火焰伤害。
func _apply_discard(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	if selected_uids.is_empty():
		return
	# 火攻使用者 ID；所选费用必须仍位于其普通手牌区。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前所选手牌；等待期间移动或花色不符时支付失败。
	var selected_card: CardInstance = resolver.state.get_player(actor_id).find_hand_card(selected_uids[0]) if resolver.state.get_player(actor_id) != null else null
	if selected_card == null or selected_card.suit != str(context.get("suit", "")):
		return
	if resolver.host.discard_card_from_hand(actor_id, selected_card.uid):
		resolver.host.damage(actor_id, int(context.get("target_id", -1)), 1, "fire", "huogong")


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
