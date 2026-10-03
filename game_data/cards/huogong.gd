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
	# 本次逻辑牌的扩展存储；视为使用【火攻】的技能可借此声明“命中即可换回的联动奖励”。
	# 实体火攻没有扩展存储，读到空字典后全部行为与原先完全一致。
	var stored_storage: Variant = resolver.host.call("get_card_virtual_storage", card.uid)
	# 扩展存储副本；端口返回非字典时退回空字典，保证任何异常都不会影响正常牌效。
	var virtual_storage: Dictionary = stored_storage if stored_storage is Dictionary else {}
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.emit_rule_timing("huogongBegin", actor_id, actor_id, target_id, {"parent_card_uid":card.uid, "card_id":card.definition_id})
		_request_shown_card(resolver, card.uid, actor_id, target_id, virtual_storage)
		if resolver.host.has_pending_card_choice():
			return "pending"
	return resolver.default_destination()


## 请求目标展示一张普通手牌；选择恢复上下文始终保留父牌 UID、使用者和目标。
## virtual_storage 由使用本牌的技能声明，其中的命中联动奖励会原样带到弃牌阶段供自伤收益判断使用。
func _request_shown_card(resolver: Object, parent_card_uid: int, actor_id: int, target_id: int, virtual_storage: Dictionary) -> void:
	# 目标手牌候选；目标本人查看时全部正面显示。
	var candidates: Array[Dictionary] = resolver.host.get_hand_candidates(target_id, target_id)
	# 展示阶段上下文；异步恢复后继续创建同花色弃牌请求。
	# card_definition_id：让统一选择评分能按稳定ID找到本牌定义，从而调用本牌的专属选牌评分。
	var context: Dictionary = {
		"kind":SHOW_CHOICE_KIND,
		"parent_card_uid":parent_card_uid,
		"actor_id":actor_id,
		"target_id":target_id,
		"card_definition_id":get_id(),
		VIRTUAL_STORAGE_HIT_REWARD_KEY:float(virtual_storage.get(VIRTUAL_STORAGE_HIT_REWARD_KEY, 0.0)),
	}
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
	# 使用者在展示等待期间阵亡时本牌已经整体失效；不再创建弃牌询问，也不会造成火焰伤害。
	if actor == null or not actor.alive:
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
	# card_definition_id：让统一选择评分能按稳定ID找到本牌定义并调用本牌的 score_ai_choice。
	# 命中联动奖励：由视为使用本牌的技能声明，决定“对自己造成伤害”是否值得支付同花色手牌。
	var discard_context: Dictionary = {
		"kind":DISCARD_CHOICE_KIND,
		"parent_card_uid":int(context.get("parent_card_uid", -1)),
		"actor_id":actor_id,
		"target_id":target_id,
		"suit":shown_card.suit,
		"private_info_safe_prompt":true,
		"card_definition_id":get_id(),
		VIRTUAL_STORAGE_HIT_REWARD_KEY:float(context.get(VIRTUAL_STORAGE_HIT_REWARD_KEY, 0.0)),
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
	if resolver.host.discard_card_from_hand(actor_id, selected_card.uid):
		# 伤害前目标状态；累计受伤次数可区分正常命中与被技能取消、减为0等未造成伤害结果。
		var target: PlayerState = resolver.state.get_player(target_id)
		# 伤害前累计受伤次数；目标不存在时使用-1并在结算后记录本次失败。
		var previous_damage_taken_count: int = target.damage_taken_count if target != null else -1
		# 来源牌上下文；制动等“此牌受到的直接响应数”效果通过父牌UID读取同一张【火攻】的无懈链。
		var source_context: Dictionary = {"card_user_id":actor_id, "parent_card_uid":int(context.get("parent_card_uid", -1)), "damage_card_target_count":1}
		resolver.host.damage(actor_id, target_id, DAMAGE_AMOUNT, "fire", "huogong", false, false, source_context)
		if target == null or target.damage_taken_count <= previous_damage_taken_count:
			resolver.host.record_failed_card_target(actor_id, get_id(), target_id)
	else:
		resolver.host.record_failed_card_target(actor_id, get_id(), target_id)


## 恢复火攻展示或弃牌选择；异步链结束后推进当前逐目标结算。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	# 选择用途；火攻只创建展示和同花色弃牌两类请求。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == SHOW_CHOICE_KIND:
		if not selected_uids.is_empty():
			_apply_shown_card(resolver, context, selected_uids[0])
		if not resolver.host.has_pending_card_choice():
			resolver.host.complete_card_target(int(context.get("parent_card_uid", -1)))
		return true
	if choice_kind == DISCARD_CHOICE_KIND:
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
## 与统一AI评估器的同名判定保持完全相同的读取口径，只使用公开稳定ID，不访问运行时技能对象。
func _snapshot_has_skill(player_snapshot: Dictionary, skill_id: String) -> bool:
	if player_snapshot.is_empty() or skill_id.is_empty():
		return false
	# 固有技能；由武将定义自动生成稳定技能ID数组。
	if (GameDatabase.get_character(str(player_snapshot.get("character_id", ""))).get("skills", []) as Array).has(skill_id):
		return true
	if (player_snapshot.get("mode_skill_ids", []) as Array).has(skill_id):
		return true
	return (player_snapshot.get("temporary_skills", {}) as Dictionary).has(skill_id) or (player_snapshot.get("acquired_skills", {}) as Dictionary).has(skill_id)
