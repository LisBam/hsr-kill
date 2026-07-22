extends CardDefinition

## 【酒】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## AI判定【酒】缺少真实可用且能从加伤获益的【杀】时的固定降权；-4分会抵消出牌顺序带来的微弱正值。
const AI_WINE_WITHOUT_SLASH_PENALTY: float = 4.0

## 有可获益【杀】时额外优先分；保证“先酒后杀”的收益链不被单张普通【杀】即时分压过。
const AI_WINE_BEFORE_SLASH_PRIORITY: float = 0.35


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "jiu",
		"original_name": "酒",
		"custom_name": "酒",
		"type": "basic",
		"subtype": "boost",
		"effect_id": "wine",
		"nature": "normal",
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 1,
		"play_limit_group": "wine",
		"play_limit_scope": "turn",
		"play_limit_message": "本回合已经使用过【酒】。",
		"response_pattern": "jiu",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段限一次，对自己使用；无论当前是否满体力，本回合下一张【杀】伤害基数+1。濒死时也只能对自己使用，回复1点体力。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "jiu",
		"ai": {"order":3.1, "value":[5.0, 1.0], "player_result":1.0, "save":true, "self_boost":true},
		"ai_use_value": 2.0,
		"ai_target_attitude": "self_boost",
	})


## 执行【酒】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	# 使用者状态；用于记录本回合已使用【酒】，继续受出牌阶段次数规则约束。
	var actor: PlayerState = resolver.state.get_player(actor_id)
	# 【酒】目标状态；正常出牌时固定为使用者本人，濒死自救由独立响应流程处理。
	var wine_target: PlayerState = resolver.state.get_player(target_ids[0])
	if actor == null or wine_target == null:
		return "discard"
	actor.wine_used = true
	wine_target.wine_bonus = 1
	return resolver.default_destination()


## 【酒】只允许濒死角色本人在救援窗口中作为自救响应。
func get_dying_response_pattern(responder_id: int, dying_player_id: int) -> String:
	return str(get_metadata().get("provided_response_pattern", "")) if responder_id == dying_player_id else ""


## 应用【酒】的濒死自救效果；固定回复本人1点体力。
func resolve_dying_response(match_host: Object, responder_id: int, dying_player_id: int, _card: CardInstance) -> bool:
	if responder_id != dying_player_id:
		return false
	# 濒死角色；无效或已经死亡时不能自救。
	var target: PlayerState = match_host.state.get_player(dying_player_id)
	if target == null or not target.alive:
		return false
	match_host.recover(responder_id, dying_player_id, 1, get_id())
	match_host.add_log("%s在濒死时使用【酒】自救。" % match_host.format_player_state_log_name(target))
	return true


## 修正出牌阶段的【酒】评分；正常使用不会回复体力，只有当前合法动作中存在能从加伤取得正边际收益的【杀】才使用。
## 有可获益【杀】时，把“酒杀相对普杀的边际收益”叠加到本牌，使 AI 先喝酒再出杀；次数已尽或白银狮子封顶时均拒绝空喝。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前行动者；动作字典必须携带稳定 ID，缺失时保守拒绝消耗本牌。
	var actor_id: int = int(action.get("actor_id", -1))
	# 当前行动者快照；完整 AI 快照同时包含普通手牌与木牛“粮”中的可用【杀】。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return current_score - AI_WINE_WITHOUT_SLASH_PENALTY
	# 当前是否存在能因酒加伤获得严格正边际收益的下一张【杀】；单纯存在合法【杀】不足以支持喝酒。
	var has_profitable_boost: bool = false
	# 酒杀相对普杀的最大边际收益；仅统计仍能对敌方产生正收益的目标，避免无效酒杀抬分。
	var best_boost_margin: float = 0.0
	# 【酒】后的下一张【杀】伤害基数；本牌正常使用固定把基础1点提高到2点。
	var boosted_damage_amount: int = 2
	# 本次出牌阶段合法动作；只包含已经通过阶段次数、目标、距离、防具与技能限制的实际可执行动作。
	var legal_actions: Array[Dictionary] = evaluator.get_current_legal_actions()
	for legal_action: Dictionary in legal_actions:
		if str(legal_action.get("action_type", "")) != "use_card":
			continue
		# 当前合法【杀】定义；普通、火与雷【杀】都以 effect_id=slash 进入统一判断。
		var slash_definition: Dictionary = GameDatabase.get_card(str(legal_action.get("card_definition_id", "")))
		if str(slash_definition.get("effect_id", "")) != "slash":
			continue
		# 当前合法【杀】实体；只读快照提供颜色，供仁王盾等颜色型防具预判。
		var slash_card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, actor_id, int(legal_action.get("card_uid", -1)))
		# 当前【杀】AI配置；目标结果和响应要求由卡牌定义声明，不复制到【酒】的专属逻辑中。
		var slash_ai: Dictionary = evaluator.get_card_ai_profile(slash_definition)
		# 当前目标效果基准；缺失配置按伤害牌的负向目标效果安全回退。
		var slash_target_result: float = float(slash_ai.get("target_result", -1.0))
		# 当前实体颜色；虚拟牌没有稳定颜色时保持空值，防具钩子不得臆测。
		var slash_color: String = str(slash_card.get("color", ""))
		for target_id_variant: Variant in legal_action.get("target_ids", []) as Array:
			# 当前合法目标ID；友方或中立目标不用于支持主动喝酒。
			var target_id: int = int(target_id_variant)
			if target_id == actor_id or evaluator.get_attitude(authoritative_snapshot, actor_id, target_id) >= 0.0:
				continue
			# 普杀目标收益；用于计算喝酒后的真实边际增益，而不是只判断酒杀是否为正分。
			var plain_slash_score: float = evaluator.score_target_effect(authoritative_snapshot, actor_id, target_id, slash_definition, slash_ai, slash_target_result, slash_color, 1)
			# 酒杀目标收益；白银狮子伤害封顶、已知响应牌、濒危与连环风险均由统一评估器计算。
			var boosted_slash_score: float = evaluator.score_target_effect(authoritative_snapshot, actor_id, target_id, slash_definition, slash_ai, slash_target_result, slash_color, boosted_damage_amount)
			# 本次加伤边际；必须严格为正且酒杀本身仍为正收益，才值得预先消耗【酒】。
			var boost_margin: float = boosted_slash_score - plain_slash_score
			if boosted_slash_score > 0.0 and boost_margin > 0.0:
				has_profitable_boost = true
				best_boost_margin = maxf(best_boost_margin, boost_margin)
	if not has_profitable_boost:
		return current_score - AI_WINE_WITHOUT_SLASH_PENALTY
	# 有可获益【杀】时：基础分 + 酒杀边际收益 + 少量顺序优先分，确保先用【酒】再出【杀】。
	return current_score + best_boost_margin + AI_WINE_BEFORE_SLASH_PRIORITY


## 新回合开始时重置该玩家的【酒】使用标记与未消耗伤害加值。
func on_turn_started(match_host: Object, player_id: int) -> void:
	# 新回合玩家；不存在时不写入任何状态。
	var player: PlayerState = match_host.state.get_player(player_id)
	if player != null:
		player.wine_used = false
		player.wine_bonus = 0


## 任意回合结束或中断时清除全部未消耗酒加值，保持原有持续时间规则。
func on_turn_ended(match_host: Object, _player_id: int, _interrupted: bool) -> void:
	# 是否实际清除了至少一名角色的酒加值；只有状态变化时才额外发布快照，避免无意义重复刷新。
	var state_changed: bool = false
	for player: PlayerState in match_host.state.players:
		if player.wine_bonus > 0:
			state_changed = true
		player.wine_bonus = 0
	if state_changed:
		match_host.refresh_public_state_snapshot()
