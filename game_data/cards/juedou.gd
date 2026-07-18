extends CardDefinition

## 【决斗】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "juedou",
		"original_name": "决斗",
		"custom_name": "决斗",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "duel",
		"nature": "normal",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "目标与你轮流打出【杀】，首先未打出者受到另一方造成的1点伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":5.0, "value":5.5, "target_result":-1.5, "damage":true, "respond_sha":true},
		"ai_target_attitude": "hostile",
	})


## 执行【决斗】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.emit_rule_timing("juedouBegin", actor_id, actor_id, target_id, {"parent_card_uid":card.uid, "card_id":card.definition_id})
		_continue_exchange(resolver, card.uid, target_id, actor_id)
	return resolver.default_destination()


## 从指定响应者继续【决斗】轮换；每轮都通过统一响应端口请求一张实体【杀】。
func _continue_exchange(resolver: Object, parent_card_uid: int, responder_id: int, opponent_id: int) -> void:
	# 安全轮次计数；实体牌有限，设置上限用于防止扩展技能制造无限响应。
	var exchange_count: int = 0
	while exchange_count < 100 and not resolver.is_resolution_stopped():
		exchange_count += 1
		resolver.host.emit_rule_timing("juedou", responder_id, opponent_id, responder_id, {"parent_card_uid":parent_card_uid, "responder_id":responder_id, "opponent_id":opponent_id, "exchange_count":exchange_count})
		# 当前轮响应上下文；成功响应后交换双方，放弃时由对手造成伤害。
		var response_context: Dictionary = {"kind":"duel_response", "parent_card_uid":parent_card_uid, "responder_id":responder_id, "opponent_id":opponent_id, "complete_parent_target_after_response":true}
		# 当前轮实体【杀】；为空表示放弃或没有合法响应牌。
		var response_card: CardInstance = resolver.host.request_response_card(responder_id, "sha", "请响应决斗并打出【杀】。", response_context)
		if resolver.host.has_pending_card_choice():
			return
		if response_card == null:
			resolver.host.damage(opponent_id, responder_id, 1, "normal", "juedou")
			resolver.host.emit_rule_timing("juedouAfter", opponent_id, opponent_id, responder_id, {"parent_card_uid":parent_card_uid, "loser_id":responder_id})
			return
		# 上一轮响应者；交换后由其对手成为下一轮响应者。
		var previous_responder_id: int = responder_id
		responder_id = opponent_id
		opponent_id = previous_responder_id


## 恢复【决斗】的一轮【杀】响应；卡牌源码直接决定继续轮换或造成1点伤害。
func continue_response(resolver: Object, context: Dictionary, response_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "duel_response":
		return false
	# 当前响应者 ID；未响应时成为伤害目标。
	var responder_id: int = int(context.get("responder_id", -1))
	# 当前对手 ID；未响应时成为伤害来源，成功时成为下一响应者。
	var opponent_id: int = int(context.get("opponent_id", -1))
	if response_card == null:
		resolver.host.damage(opponent_id, responder_id, 1, "normal", "juedou")
		resolver.host.emit_rule_timing("juedouAfter", opponent_id, opponent_id, responder_id, {"parent_card_uid":int(context.get("parent_card_uid", -1)), "loser_id":responder_id})
	else:
		_continue_exchange(resolver, int(context.get("parent_card_uid", -1)), opponent_id, responder_id)
	return true
