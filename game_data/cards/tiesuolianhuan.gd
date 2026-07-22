extends CardDefinition

## 【铁索连环】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## AI把本次连环切换判定为不利时的固定惩罚；0.75分会压过纯出牌顺序，仍允许多目标组合以更高收益覆盖。
const AI_UNFAVORABLE_CHAIN_TARGET_PENALTY: float = 0.75

## AI使用效果必须至少比同一张牌的重铸收益高出的最小分差；避免微弱出牌顺序压过真实的换牌收益。
const AI_RECAST_USE_ADVANTAGE_MARGIN: float = 0.15


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tiesuo",
		"original_name": "铁索连环",
		"custom_name": "命运连结",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "chain",
		"nature": "normal",
		"target_mode": "one_or_two",
		"min_targets": 1,
		"max_targets": 2,
		"allow_self_target": true,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": true,
		"delayed": false,
		"description": "令一至两名角色横置或重置；也可重铸并摸一张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":7.3, "value":4.0, "target_result":-0.5, "multitarget":true},
		"ai_use_value": 1.0,
	})


## 执行【铁索连环】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		# 当前目标状态；每次生效都通过统一连环端口在横置与重置之间切换一次。
		var target: PlayerState = resolver.state.get_player(target_id)
		if target == null:
			continue
		resolver.host.toggle_player_linked(target_id, actor_id, card.definition_id)
		resolver.host.add_log("%s%s。" % [target.display_name, "进入连环状态" if target.chained else "解除连环状态"])
	return resolver.default_destination()


## 返回【铁索连环】当前目标的动态身份观察牌效；施加横置为负，解除横置为等量正收益。
func get_identity_observation_target_result(authoritative_snapshot: Dictionary, _actor_id: int, target_id: int, current_result: float) -> float:
	# 基础牌效绝对值；静态配置为-0.5，取绝对值后可按目标当前状态反转方向。
	var result_magnitude: float = absf(current_result)
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前目标快照；已横置表示本次效果将解除连环，因此由负面转为正面。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == target_id:
			return result_magnitude if bool(player.get("chained", false)) else -result_magnitude
	return current_result


## 为基础 AI 枚举一目标与二目标的全部合法组合；玩家与 AI 共用同一权威目标校验。
func append_play_phase_card_actions(match_host: Object, actor_id: int, card: CardInstance, result: Array[Dictionary]) -> bool:
	# 当前全部合法单目标；包含使用者本人，因为【铁索连环】允许选择自己。
	var legal_target_ids: Array[int] = match_host.card_rules.list_legal_targets(actor_id, card)
	for first_index: int in range(legal_target_ids.size()):
		# 单目标动作；保留规则允许只横置或重置一名角色的用法。
		var single_target_ids: Array[int] = [legal_target_ids[first_index]]
		match_host.append_card_action_if_legal(result, actor_id, card, single_target_ids)
		for second_index: int in range(first_index + 1, legal_target_ids.size()):
			# 双目标动作；组合只生成一次，最终结算顺序仍由规则服务按行动座次规范化。
			var double_target_ids: Array[int] = [legal_target_ids[first_index], legal_target_ids[second_index]]
			match_host.append_card_action_if_legal(result, actor_id, card, double_target_ids)
	return true


## 修正铁索连环切换状态的动作价值；解除横置与施加横置的收益方向必须相反。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 修正后评分；逐目标检查当前是否已经横置。
	var score: float = current_score
	# 本次使用是否至少有一名实际受益目标；没有时同牌重铸一定优先，不能让出牌顺序形成伪收益。
	var has_positive_target_effect: bool = false
	for target_id_variant: Variant in action.get("target_ids", []) as Array:
		# 当前目标 ID；用于读取连环状态与身份态度。
		var target_id: int = int(target_id_variant)
		# 当前目标快照；未横置时通用负面目标评分已经正确。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty():
			continue
		# 通用评分把横置视为-0.5目标效果；当前目标若已横置，本次会解除连环并反转该分量。
		var original_target_score: float = -0.5 * evaluator.get_attitude(authoritative_snapshot, int(action.get("actor_id", -1)), target_id) / 5.0
		# 本次切换后的实际目标收益；未横置沿用原分量，已横置则使用反向后的解除收益。
		var resolved_target_score: float = original_target_score
		if bool(target.get("chained", false)):
			score -= original_target_score * 2.0
			resolved_target_score = -original_target_score
		if resolved_target_score > 0.0:
			has_positive_target_effect = true
		# 敌方已横置时解除连环属于帮助，不得再被出牌顺序的微弱正分驱动为无脑使用。
		# 友方未横置时强行施加连环同样是不利目标；多目标动作只有整体收益足够高才会保留。
		if resolved_target_score < 0.0:
			score -= AI_UNFAVORABLE_CHAIN_TARGET_PENALTY
	# 同一实体牌始终同时提供重铸合法动作；使用效果没有明显高于换牌收益时，明确把本动作压到重铸之后。
	var recast_action: Dictionary = {
		"action_type":"recast_card",
		"actor_id":int(action.get("actor_id", -1)),
		"card_uid":int(action.get("card_uid", -1)),
		"card_definition_id":get_id(),
	}
	# 同一张牌的未知摸牌收益；评估器复用全局卡牌价值与重铸资源价值，避免卡牌文件复制估值常量。
	var recast_score: float = evaluator.score_action(authoritative_snapshot, recast_action, int(action.get("actor_id", -1)))
	if not has_positive_target_effect:
		return recast_score - AI_RECAST_USE_ADVANTAGE_MARGIN
	if score <= recast_score + AI_RECAST_USE_ADVANTAGE_MARGIN:
		return recast_score - AI_RECAST_USE_ADVANTAGE_MARGIN
	return score
