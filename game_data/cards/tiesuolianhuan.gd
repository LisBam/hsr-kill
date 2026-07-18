extends CardDefinition

## 【铁索连环】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tiesuo",
		"original_name": "铁索连环",
		"custom_name": "命途连结",
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
	for target_id_variant: Variant in action.get("target_ids", []) as Array:
		# 当前目标 ID；用于读取连环状态与身份态度。
		var target_id: int = int(target_id_variant)
		# 当前目标快照；未横置时通用负面目标评分已经正确。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty() or not bool(target.get("chained", false)):
			continue
		# 通用评分把横置视为-0.5目标效果；解除时反转该分量，因此减去原分量的两倍。
		var original_target_score: float = -0.5 * evaluator.get_attitude(authoritative_snapshot, int(action.get("actor_id", -1)), target_id) / 5.0
		score -= original_target_score * 2.0
	return score
