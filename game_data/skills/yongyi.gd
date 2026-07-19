extends SkillDefinition

## 【永屹】技能源码。持有者的体力值实际因伤害减少后可执行额外弃牌阶段并获得护盾，也可在弃牌阶段以护盾换取额外出牌阶段。

## 额外弃牌阶段完成后获得的护盾数；默认1点，修改后必须同步技能原文与玩法数值文档。
const SHIELD_GAIN_AMOUNT: int = 1

## 获得额外出牌阶段需要失去的护盾数；默认1点，不会触发失去体力或受到伤害。
const SHIELD_PLAY_PHASE_COST: int = 1

## 第二段确认支付护盾后固定摸取的牌数；默认1张，摸牌须在登记额外出牌阶段前完成。
const EXTRA_PLAY_DRAW_COUNT: int = 1

## AI对1点护盾的防御资源估值；两个发动分支都以此作为收益或机会成本基准。
const AI_SHIELD_VALUE: float = 2.5

## AI对第二段固定摸取1张未知牌的预期收益；只用于确认决策，不改变实际摸牌数量。
const AI_EXTRA_PLAY_DRAW_VALUE: float = 2.0

## AI对弃牌阶段弃置牌面价值的折算权重；不修改实际弃牌数量。
const AI_DISCARD_COST_WEIGHT: float = 0.55

## AI对额外出牌阶段中每张可主动使用手牌的通用收益；用于补充可命中敌方【杀】的显式收益。
const AI_USABLE_CARD_VALUE: float = 0.8

## AI对额外出牌阶段中一张可命中敌方【杀】的攻击收益；应高于1点护盾代价。
const AI_ENEMY_SLASH_VALUE: float = 4.0


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "yongyi",
		"name": "永屹",
		"trigger": "damageAfter/phaseDiscardBegin",
		"ui_enabled": false,
		"description": "当你的体力值受到伤害后，你可以进行一个额外的弃牌阶段，然后获得1点护盾。弃牌阶段开始时，若你有护盾，你可以失去1点护盾并摸一张牌，然后进行一个额外的出牌阶段。",
	})


## 订阅持有者的伤害后与弃牌阶段Begin时机；护盾完全抵消的伤害会在回调内被hp_lost过滤。
func install() -> void:
	subscribe_timing("damageAfter", _on_damage_after, "target")
	subscribe_timing("phaseDiscardBegin", _on_discard_phase_begin, "player")


## 体力实际因伤害减少后请求额外弃牌阶段；只扣护盾或失去体力不会进入本分支。
func _on_damage_after(event: RuleEvent) -> void:
	# 伤害造成的实际体力减少量；0表示伤害已被护盾完全抵消。
	var hp_lost: int = int(event.data.get("hp_lost", 0))
	# 技能持有者状态；伤害结算后已死亡或离场时不再创建阶段。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if hp_lost <= 0 or owner == null or not owner.alive or owner.out_of_game:
		return
	request_card_selection("永屹", "是否发动【永屹】执行一个额外的弃牌阶段？", [], 0, 0, true, {"kind":"yongyi_damage_confirm", "damage_source_id":event.source_id, "hp_lost":hp_lost, "ai_allow_confirm":true})


## 弃牌阶段开始时在护盾充足且能排队额外出牌阶段时请求支付。
func _on_discard_phase_begin(_event: RuleEvent) -> void:
	# 技能持有者状态；护盾不足、死亡或离场时该效果不可触发并直接跳过。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or owner.shield < SHIELD_PLAY_PHASE_COST or not bool(host.call("can_add_play_phase", owner_player_id)):
		return
	# AI快照所需的实时可用牌估计；这些字段只影响确认决策，提交后仍由权威阶段端口复核。
	var play_estimate: Dictionary = _estimate_extra_play_phase()
	request_card_selection("永屹", "是否失去1点护盾，摸1张牌并进行一个额外的出牌阶段？", [], 0, 0, true, {"kind":"yongyi_play_phase_confirm", "usable_card_count":int(play_estimate.get("usable_card_count", 0)), "enemy_slash_available":bool(play_estimate.get("enemy_slash_available", false)), "ai_allow_confirm":true})


## 恢复永屹的伤害后确认或弃牌阶段支付确认；取消不产生任何资源变化。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；两个独立触发分支使用稳定kind分流。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "yongyi_damage_confirm":
		if not response.confirmed:
			return true
		# 额外弃牌阶段完成上下文；技能回调会在End与After后据此获得护盾。
		var completion_context: Dictionary = {"kind":"yongyi_extra_discard_complete", "skill_owner_id":owner_player_id, "skill_id":get_id()}
		if bool(host.call("request_extra_discard_phase", owner_player_id, int(context.get("damage_source_id", -1)), get_id(), completion_context)):
			announce_activation({"hp_lost":int(context.get("hp_lost", 0)), "branch":"extra_discard"})
		return true
	if choice_kind == "yongyi_play_phase_confirm":
		if not response.confirmed or not bool(host.call("can_add_play_phase", owner_player_id)):
			return true
		if get_owner_skill_player().loseShield(SHIELD_PLAY_PHASE_COST, get_owner_skill_player()) < SHIELD_PLAY_PHASE_COST:
			return true
		# 第二段固定资源收益；护盾支付成功后立即摸牌，使新增手牌可用于随后登记的额外出牌阶段。
		host.draw(owner_player_id, EXTRA_PLAY_DRAW_COUNT)
		if get_owner_skill_player().addPlayPhase():
			announce_activation({"branch":"extra_play", "draw_count":EXTRA_PLAY_DRAW_COUNT})
		return true
	return false


## 在权威额外弃牌阶段完整结束后获得护盾；中途选择或弃牌未完成时不会提前结算。
func continue_extra_phase(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "yongyi_extra_discard_complete":
		return false
	get_owner_skill_player().shield(SHIELD_GAIN_AMOUNT, get_owner_skill_player())
	return true


## 估算持有者的额外出牌阶段资源；显式识别可命中敌方的【杀】与其他可主动使用牌。
func _estimate_extra_play_phase() -> Dictionary:
	# 估算结果；usable_card_count是可主动使用牌数，enemy_slash_available表示至少一张【杀】有敌方合法目标。
	var result: Dictionary = {"usable_card_count":0, "enemy_slash_available":false}
	# 技能持有者；只查询当前手牌与木牛“粮”，不猜测未来摸牌。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return result
	for card: CardInstance in owner.get_playable_cards():
		# 当前牌定义；只响应牌不能在额外出牌阶段主动使用。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if str(definition.get("target_mode", "")) == "response_only":
			continue
		# 当前牌是否至少有一个合法使用方式；无目标或自身牌按定义直接计入。
		var card_is_usable: bool = str(definition.get("target_mode", "")) in ["none", "self", "self_wounded", "all_players", "all_others", "equipment"]
		# 当前牌合法目标；距离、坐骑、武器范围与目标限制由CardRuleService统一计算。
		var legal_target_ids: Array[int] = host.card_rules.list_legal_targets(owner_player_id, card)
		if not legal_target_ids.is_empty():
			card_is_usable = true
		if card_is_usable:
			result["usable_card_count"] = int(result.get("usable_card_count", 0)) + 1
		if str(definition.get("effect_id", "")) != "slash":
			continue
		for target_id: int in legal_target_ids:
			# 杀的合法目标；只有持有者对其真实身份态度为负时记为可命中敌方。
			var target: PlayerState = host.state.get_player(target_id) as PlayerState
			if target != null and int(host.call("get_identity_attitude", owner.identity, target.identity)) < 0:
				result["enemy_slash_available"] = true
				break
	return result


## 评估永屹的两个确认选择；额外弃牌代价必须低于护盾收益，额外出牌收益必须高于护盾代价。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；包含分支种类与规则层在触发时写入的可用牌估计。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 选择动作负载；取消保持0分，确认只在净收益严格为正时被选中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前分支种类；伤害后额外弃牌与弃牌阶段额外出牌分开评估。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "yongyi_damage_confirm":
		# 技能持有者快照；伤害后的体力值决定额外弃牌阶段手牌上限。
		var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
		# 需要弃置的手牌数；只统计超过当前体力上限的部分。
		var discard_count: int = maxi(int(owner.get("hand_count", 0)) - maxi(int(owner.get("hp", 0)), 0), 0)
		# 全部手牌保留价值；权威AI快照对本人包含完整牌面。
		var hand_values: Array[float] = []
		for card_variant: Variant in owner.get("hand", []) as Array:
			# 当前手牌快照；定义ID用于读取卡牌文件声明的AI保留价值。
			var card: Dictionary = card_variant as Dictionary
			hand_values.append(evaluator.get_card_value_by_id(str(card.get("definition_id", "")), authoritative_snapshot, owner_player_id))
		hand_values.sort()
		# 额外弃牌阶段机会成本；AI会优先预计弃置价值最低的超限手牌。
		var discard_cost: float = 0.0
		for index: int in range(mini(discard_count, hand_values.size())):
			discard_cost += hand_values[index] * AI_DISCARD_COST_WEIGHT
		return AI_SHIELD_VALUE - discard_cost
	if choice_kind == "yongyi_play_phase_confirm":
		# 额外出牌阶段收益；固定摸1张未知牌提供基础收益，可命中敌方的【杀】使用显式攻击分，其余可用牌按数量提供资源分。
		var play_value: float = AI_EXTRA_PLAY_DRAW_VALUE + float(int(context.get("usable_card_count", 0))) * AI_USABLE_CARD_VALUE
		if bool(context.get("enemy_slash_available", false)):
			play_value += AI_ENEMY_SLASH_VALUE
		return play_value - AI_SHIELD_VALUE
	return 0.0
