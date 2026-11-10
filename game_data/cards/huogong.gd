extends CardDefinition

## 【火攻】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## 命中后造成的火焰伤害点数；固定1，与牌面说明“造成1点火焰伤害”保持一致。
const DAMAGE_AMOUNT: int = 1

## 展示阶段的选择种类；异步恢复与AI评分共用该稳定标识。
const SHOW_CHOICE_KIND: String = "fire_attack_show"

## 弃牌阶段的选择种类；异步恢复与AI评分共用该稳定标识。
const DISCARD_CHOICE_KIND: String = "fire_attack_discard"

## virtual_storage 中“命中联动奖励”的稳定键名；视为使用【火攻】的技能按同一键名写入本次命中能换回的收益。
## 两处必须保持一致，否则本牌在“使用者对自己使用火攻”时读不到联动收益，只会看到统一评分的自伤惩罚。
const VIRTUAL_STORAGE_HIT_REWARD_KEY: String = "hit_reward_value"

## 能把自身所受伤害回复回来的技能ID；当前唯一来源是【无邪】（造成伤害后可令受伤角色回复1点体力）。
## 使用者对自己使用【火攻】时该技能会把自己回复回来，使本次自伤的体力成本归零。
const SELF_DAMAGE_RECOVERY_SKILL_ID: String = "wuxie_2"

## AI：自伤1点体力的统一资源价值；与全局体力资源尺度（1点体力=2张牌）保持同一口径。
const AI_SELF_DAMAGE_HP_COST: float = DAMAGE_AMOUNT * NonameAIEvaluator.HP_RESOURCE_VALUE


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
## requires_actor_choice=true：目标展示手牌后必须由使用者本人决定是否弃置一张同花色手牌，
## 使用者在结算前阵亡后无法代理该选择，本牌整体失效，展示与火焰伤害都不再发生。
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
		"is_damage": true,
		"description": "目标展示一张手牌，你可弃置一张同花色手牌并对其造成1点火焰伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"requires_actor_choice": true,
		"provided_response_pattern": "",
		"ai": {"order":9.2, "value":[3.0, 1.0], "target_result":-1.15, "damage":true, "fire_damage":true, "nature_damage":true},
		"ai_target_attitude": "hostile",
	})


## 执行【火攻】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	# 本次逻辑牌的扩展存储；自伤联动奖励只参与AI评分，不改变牌效数值。
	var virtual_storage: Dictionary = resolver.host.get_card_virtual_storage(card.uid)
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		# 原使用者；展示和费用等待之后仍须是同一武将。
		var actor: PlayerState = resolver.state.get_player(actor_id)
		# 原目标；换将后不向新武将继续展示、扣费或伤害。
		var target: PlayerState = resolver.state.get_player(target_id)
		if actor == null or target == null:
			continue
		# 单目标完整内容；原生父牌等待展示、费用、伤害和其After后再收尾目标。
		var data: Dictionary = {"sequence_kind":"fire_attack", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "actor_generation":actor.character_generation, "target_generation":target.character_generation, "card_definition_id":get_id(), VIRTUAL_STORAGE_HIT_REWARD_KEY:float(virtual_storage.get(VIRTUAL_STORAGE_HIT_REWARD_KEY, 0.0))}
		resolver.host.run_rule_sequence([_begin_fire_attack.bind(resolver), _choose_shown_card.bind(resolver), _show_and_choose_cost.bind(resolver), _pay_selected_cost.bind(resolver), _finish_fire_attack.bind(resolver)] as Array[Callable], data)
		return "pending"
	return resolver.default_destination()


## 独立开始时机也允许插入子效果；下一步读取最终取消状态。
func _begin_fire_attack(sequence: RuleStepSequence, resolver: Object) -> void:
	sequence.wait_for_timing(resolver.host.emit_sequence_timing(sequence, "huogongBegin", int(sequence.context.actor_id), int(sequence.context.actor_id), int(sequence.context.target_id), {"parent_card_uid":int(sequence.context.parent_card_uid), "card_id":get_id()}))


## 原使用者与目标均保持有效；本判断只读，不创建选择或消费费用。
func _is_original_fire_attack_valid(sequence: RuleStepSequence, resolver: Object) -> bool:
	# 原使用者的当前状态；死亡、离场或换将后不继续本人决策。
	var actor: PlayerState = resolver.state.get_player(int(sequence.context.actor_id))
	# 原目标的当前状态；同座位新武将不继承旧牌效。
	var target: PlayerState = resolver.state.get_player(int(sequence.context.target_id))
	return actor != null and target != null and actor.alive and target.alive and not actor.out_of_game and not target.out_of_game and actor.character_generation == int(sequence.context.actor_generation) and target.character_generation == int(sequence.context.target_generation)


## 展示选择结果直接归本序列；没有手牌或开始被取消时仍进入唯一目标收尾。
func _choose_shown_card(sequence: RuleStepSequence, resolver: Object) -> void:
	sequence.choice_response = null
	if not _is_original_fire_attack_valid(sequence, resolver) or (sequence.waiting_event != null and (sequence.waiting_event.cancelled or sequence.waiting_event.neutralized)):
		return
	# 原目标普通手牌；展示不移动实体。
	var candidates: Array[Dictionary] = resolver.host.get_hand_candidates(int(sequence.context.target_id), int(sequence.context.target_id))
	if candidates.is_empty():
		return
	# 原选择语义与结果归属；保留牌效AI依赖的奖励与稳定ID。
	var context: Dictionary = sequence.context.duplicate(true)
	context["kind"] = SHOW_CHOICE_KIND
	context["rule_sequence_id"] = sequence.sequence_id
	context["choice_chooser_id"] = int(sequence.context.target_id)
	resolver.host.request_card_choice(int(sequence.context.target_id), "火攻展示", "请选择一张手牌展示", candidates, 1, 1, false, context)


## 公开实际选定手牌后询问同花色费用；两次选择不会通过手工续接重复收尾目标。
func _show_and_choose_cost(sequence: RuleStepSequence, resolver: Object) -> void:
	# 原展示结果；下一请求前清空结果槽，取消时不会沿用上一张展示牌。
	var response: ChoiceResponse = sequence.choice_response
	sequence.choice_response = null
	if response == null or response.card_ids.size() != 1 or not _is_original_fire_attack_valid(sequence, resolver):
		return
	# 当前原展示实体；等待期间离手则本次费用询问失效。
	var shown_card: CardInstance = resolver.host.reveal_hand_card(int(sequence.context.target_id), response.card_ids[0], "fire_attack")
	if shown_card == null:
		return
	sequence.context["suit"] = shown_card.suit
	# 当前使用者；只允许同花色普通手牌，木牛粮与装备不作为火攻费用。
	var actor: PlayerState = resolver.state.get_player(int(sequence.context.actor_id))
	# 费用候选；即使没有同花色牌也建立可取消询问，避免泄露隐藏手牌。
	var candidates: Array[Dictionary] = []
	for candidate: Dictionary in resolver.host.get_hand_candidates(actor.player_id, actor.player_id):
		# 当前候选实体；不以旧牌面或候选展示副本作为支付凭据。
		var candidate_card: CardInstance = actor.find_hand_card(int(candidate.get("uid", -1)))
		if candidate_card != null and candidate_card.suit == shown_card.suit:
			candidates.append(candidate)
	# 费用请求保留AI语义；结果写回同一个规则序列。
	var context: Dictionary = sequence.context.duplicate(true)
	context["kind"] = DISCARD_CHOICE_KIND
	context["rule_sequence_id"] = sequence.sequence_id
	context["choice_chooser_id"] = actor.player_id
	resolver.host.request_card_choice(actor.player_id, "火攻弃牌", "是否弃置一张同花色手牌？", candidates, 0, 1, true, context)


## 费用消费自身仍为子内容；完整弃牌After与伤害尾部结束后才回到最后目标收尾。
func _pay_selected_cost(sequence: RuleStepSequence, resolver: Object) -> void:
	if not _is_original_fire_attack_valid(sequence, resolver):
		return
	# 最终确认材料；取消或未选择时按原失败目标规则记录。
	var selected_uids: Array[int] = []
	if sequence.choice_response != null and sequence.choice_response.confirmed:
		selected_uids.assign(sequence.choice_response.card_ids)
	_apply_discard(resolver, sequence.context, selected_uids)


## 展示、费用、伤害及所有子内容都结束后只收尾一次原目标。
func _finish_fire_attack(sequence: RuleStepSequence, resolver: Object) -> void:
	resolver.host.complete_card_target(int(sequence.context.parent_card_uid))


## 应用同花色弃牌；只有费用仍合法且成功弃置时造成1点火焰伤害。
func _apply_discard(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	# 火攻使用者ID；失败目标记忆与费用复核共用该稳定来源。
	var actor_id: int = int(context.get("actor_id", -1))
	# 火攻目标ID；本回合后续AI动作会据此避开重复无效火攻。
	var target_id: int = int(context.get("target_id", -1))
	if selected_uids.is_empty():
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
		return
	# 火攻使用者状态；等待弃牌选择期间阵亡时本牌已经整体失效，既不消费费用也不造成伤害。
	var actor: PlayerState = resolver.state.get_player(actor_id)
	if actor == null or not actor.alive:
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
		return
	# 火攻使用者 ID；所选费用必须仍位于其普通手牌区。
	# 使用者ID已在失败目标记录前读取；此处继续用于查询实体费用牌。
	# 当前所选手牌；等待期间移动或花色不符时支付失败。
	var selected_card: CardInstance = actor.find_hand_card(selected_uids[0])
	if selected_card == null or selected_card.suit != str(context.get("suit", "")):
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
		return
	# 原费用身份；后续只按UID查回，不保留选择前的实体引用。
	var cost_card_uid: int = selected_card.uid
	# 原目标代次；费用After中的换将不能令新武将承受原火攻。
	var target_generation: int = resolver.state.get_player(target_id).character_generation if resolver.state.get_player(target_id) != null else -1
	resolver.host.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: sequence.effect_result = resolver.host.discard_card_from_hand(actor_id, cost_card_uid),
		func(sequence: RuleStepSequence) -> void:
			if sequence.effect_result == null or sequence.effect_result.count <= 0:
				resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
				sequence.finish()
				return
			# 伤害前目标状态；累计受伤次数可区分正常命中与被技能取消、减为0等未造成伤害结果。
			var target: PlayerState = resolver.state.get_player(target_id)
			if target == null or not target.alive or target.character_generation != target_generation:
				sequence.finish()
				return
			# 伤害前累计受伤次数；目标不存在时使用-1并在结算后记录本次失败。
			sequence.context["previous_damage_taken_count"] = target.damage_taken_count
			# 来源牌上下文；制动等“此牌受到的直接响应数”效果通过父牌UID读取同一张【火攻】的无懈链。
			var source_context: Dictionary = {"card_user_id":actor_id, "parent_card_uid":int(context.get("parent_card_uid", -1)), "damage_card_target_count":1}
			resolver.host.damage(actor_id, target_id, DAMAGE_AMOUNT, "fire", "huogong", false, false, source_context),
		func(sequence: RuleStepSequence) -> void:
			# 伤害完整结束后的原目标；代次变化不对新角色写入旧目标失败记忆。
			var target: PlayerState = resolver.state.get_player(target_id)
			if target != null and target.character_generation == target_generation and target.damage_taken_count <= int(sequence.context.get("previous_damage_taken_count", -1)):
				resolver.host.record_failed_card_target(actor_id, get_id(), target_id),
	] as Array[Callable])


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


## AI评估火攻的同花色弃牌选择；只在“使用者对自己使用火攻、且本次命中带有明确联动奖励”时接管评分。
## 统一选择评分按 -get_attitude(使用者, 目标) - 所选牌价值 估算本次伤害的收益，目标是自己时该式恒得一份
## 固定的自身态度惩罚，于是弃牌自伤被判为负分而必然取消；但统一层看不到“这次伤害能换回摸牌与出牌阶段”
## 这层联动收益，也无法知道使用者自己就能把这点伤害回复回来，因此需要本牌的专属评分补上这两项。
## 以下四个前提必须同时成立，任一不成立即返回0.0：
##   ① 选择种类是弃牌阶段，且动作是确认；
##   ② 本次火攻的目标就是使用者本人（对其他角色使用时统一评分已能正确按身份态度处理）；
##   ③ 视为使用本次火攻的技能通过 virtual_storage 声明了正数命中奖励；
##   ④ 使用者承受本次伤害后体力仍大于0，不会把自己直接打入濒死。
## 因此普通火攻、他人对使用者的火攻、以及无奖励的自伤场景全部保持原有的取消行为，评分口径不变。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只有火攻自身的弃牌步骤带有本牌需要识别的字段。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != DISCARD_CHOICE_KIND:
		return 0.0
	# 动作负载；取消不造成伤害也不产生联动奖励，保持统一评分的0分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 使用者与目标；只有“对自己使用火攻”的自伤分支需要专属评分。
	var actor_id: int = int(context.get("actor_id", -1))
	if actor_id < 0 or int(context.get("target_id", -1)) != actor_id:
		return 0.0
	# 本次命中的联动奖励；由视为使用本牌的技能声明，普通火攻与无奖励场景为0。
	var hit_reward_value: float = float(context.get(VIRTUAL_STORAGE_HIT_REWARD_KEY, 0.0))
	if hit_reward_value <= 0.0:
		return 0.0
	# 使用者公开快照；AI评分只允许读取所有玩家可见的事实。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty() or not bool(actor.get("alive", false)):
		return 0.0
	# 濒死保护；自伤后体力必须仍大于0，否则本次弃牌会把使用者自己打入濒死。
	if int(actor.get("hp", 0)) <= DAMAGE_AMOUNT:
		return 0.0
	# 自伤惩罚豁免；统一层用自身态度估算“对自己造成伤害”的惩罚，而本次伤害的收益已由联动奖励如实承担，
	# 因此按同一接口读回自身态度并撤销该惩罚，避免同一份代价在统一层与本方法中被各计一次。
	var self_damage_penalty_exemption: float = evaluator.get_attitude(authoritative_snapshot, actor_id, actor_id)
	# 自伤净体力成本；这点伤害会被使用者自身的回复类技能抹平时，成本归零，本次弃牌的收益因此更高。
	var self_damage_cost: float = 0.0 if _snapshot_recovers_own_damage(actor) else AI_SELF_DAMAGE_HP_COST
	return hit_reward_value + self_damage_penalty_exemption - self_damage_cost


## 判断使用者快照能否在本次伤害后把这点体力回复回来；当前唯一来源是【无邪】。
## 满体力时回复没有实际收益，因此不视为可抵消；判定只读公开快照与静态武将定义，不访问运行时技能实例。
func _snapshot_recovers_own_damage(player_snapshot: Dictionary) -> bool:
	if player_snapshot.is_empty():
		return false
	if int(player_snapshot.get("hp", 0)) >= int(player_snapshot.get("max_hp", 0)):
		return false
	return _snapshot_has_skill(player_snapshot, SELF_DAMAGE_RECOVERY_SKILL_ID)


## 判断玩家公开快照是否持有指定固有、模式、临时或局内获得技能。
## 实现委托 SkillDefinition.snapshot_has_skill：拥有口径只有一份实现，卡牌文件不再自行枚举技能来源。
func _snapshot_has_skill(player_snapshot: Dictionary, skill_id: String) -> bool:
	return SkillDefinition.snapshot_has_skill(player_snapshot, skill_id)
