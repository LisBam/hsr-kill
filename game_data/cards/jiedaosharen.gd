extends CardDefinition

## 【借刀杀人】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "jiedao",
		"original_name": "借刀杀人",
		"custom_name": "借刃执行",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "borrow_sword",
		"nature": "normal",
		"target_mode": "weapon_holder",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "special",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "令一名装备武器的角色对合法目标使用【杀】，否则其将武器交给你。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":8.0, "value":2.0, "player_result":0.2, "target_result":-1.0, "gain":true, "use_sha":true},
	})


## 执行【借刀杀人】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.size() == 1 and not resolver.host.resolve_trick_negation(actor_id, target_ids[0], card.definition_id):
		if not resolver.is_resolution_stopped():
			_request_borrow_sword_target(resolver, card.uid, actor_id, target_ids[0])
	return resolver.default_destination()


## 结算【借刀杀人】唯一的持刀者目标；被要求使用【杀】的目标属于后续牌效选择，不进入本牌目标数组。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, _resolution_context: Dictionary) -> String:
	return resolve(resolver, card, actor_id, [target_id])


## 【借刀杀人】只有一个牌目标，不再要求规则服务保留旧版双目标顺序。
func preserves_requested_target_order() -> bool:
	return false


## 本牌不再改写共享目标上下文；CardUseEvent 的全部目标时机只处理唯一持刀者。
func configure_resolution_context(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> void:
	pass


## 校验唯一持刀者目标，并保证其至少存在一名可由后续牌效选择的【杀】目标。
func validate_target_selection(rule_service: Object, actor: PlayerState, target_id: int, all_target_ids: Array[int]) -> String:
	if all_target_ids.size() != 1:
		return ""
	# 持刀者状态；必须是装备武器的其他存活角色。
	var weapon_holder: PlayerState = rule_service.state.get_player(target_id)
	if weapon_holder == null or target_id == actor.player_id or weapon_holder.get_weapon() == null:
		return "借刀杀人的目标必须是装备武器的其他角色。"
	if _get_legal_slash_target_ids(rule_service, target_id).is_empty():
		return "借刀杀人的目标当前没有可使用【杀】的合法角色。"
	return ""


## 为基础 AI 枚举全部合法持刀者；被【杀】者在牌效目标选择中另行评分和提交。
func append_play_phase_card_actions(match_host: Object, actor_id: int, card: CardInstance, result: Array[Dictionary]) -> bool:
	for holder: PlayerState in match_host.state.players:
		# 借刀动作目标；只声明唯一持刀者，权威校验会同时确认存在后续【杀】目标。
		var requested_target_ids: Array[int] = [holder.player_id]
		match_host.append_card_action_if_legal(result, actor_id, card, requested_target_ids)
	return true


## 请求锦囊使用者指定被【杀】者；该角色只属于牌效选择，不触发【借刀杀人】的目标时机。
func _request_borrow_sword_target(resolver: Object, parent_card_uid: int, source_id: int, weapon_holder_id: int) -> void:
	# 当前可被持刀者使用【杀】的目标；按权威座次顺序生成，等待期间仍会在恢复入口重新复核。
	var target_ids: Array[int] = _get_legal_slash_target_ids(resolver.host.card_rules, weapon_holder_id)
	if target_ids.is_empty():
		resolver.host.transfer_equipment(weapon_holder_id, source_id, "weapon")
		return
	# 牌效目标选择上下文；card_definition_id 使基础 AI 使用本牌源码评分，而 parent_card_uid 用于恢复原 content。
	var context: Dictionary = {"kind":"borrow_sword_target", "parent_card_uid":parent_card_uid, "actor_id":source_id, "source_id":source_id, "weapon_holder_id":weapon_holder_id, "card_definition_id":get_id()}
	# 被【杀】者选择结果；规则要求且只允许选择一名合法角色，不允许取消造成无目标结算。
	var selected_target_ids: Array[int] = resolver.host.request_target_choice(source_id, "【借刀杀人】请选择被【杀】的角色", target_ids, 1, 1, false, context)
	if resolver.host.has_pending_card_choice() or selected_target_ids.size() != 1:
		return
	_resolve_borrow_sword(resolver, parent_card_uid, source_id, weapon_holder_id, selected_target_ids[0])


## 返回持刀者攻击范围内的全部其他存活角色；自身永远不是其【杀】的合法目标。
func _get_legal_slash_target_ids(rule_service: Object, weapon_holder_id: int) -> Array[int]:
	# 合法【杀】目标结果；规则服务无效时保持空数组，调用方会安全转入交出武器分支。
	var result: Array[int] = []
	if rule_service == null or rule_service.state == null:
		return result
	for player: PlayerState in rule_service.state.players:
		if player.alive and player.player_id != weapon_holder_id and rule_service.calculate_distance(weapon_holder_id, player.player_id) <= rule_service.get_attack_range(weapon_holder_id):
			result.append(player.player_id)
	return result


## 要求持刀者打出【杀】；拒绝或无法响应时将其武器交给锦囊使用者。
func _resolve_borrow_sword(resolver: Object, parent_card_uid: int, source_id: int, weapon_holder_id: int, victim_id: int) -> void:
	# 借刀响应上下文；父牌 UID 使异步恢复重新定位本卡牌源码。
	var response_context: Dictionary = {"kind":"borrow_sword_response", "parent_card_uid":parent_card_uid, "responder_id":weapon_holder_id, "source_id":source_id, "victim_id":victim_id, "complete_parent_target_after_response":true}
	# 持刀者实际打出的【杀】；为空表示交出武器。
	var slash: CardInstance = resolver.host.request_response_card(weapon_holder_id, "sha", "请响应借刀杀人并打出【杀】。", response_context)
	if resolver.host.has_pending_card_choice() or resolver.is_resolution_stopped():
		return
	_apply_borrow_sword_response(resolver, response_context, slash)


## 应用【借刀杀人】响应结果；实体【杀】复用牌族组件的完整武器、防具和伤害流程。
func _apply_borrow_sword_response(resolver: Object, context: Dictionary, slash: CardInstance) -> void:
	# 持刀者 ID；其酒加值只在实际打出【杀】时消耗。
	var weapon_holder_id: int = int(context.get("responder_id", -1))
	if slash == null:
		resolver.host.transfer_equipment(weapon_holder_id, int(context.get("source_id", -1)), "weapon")
		return
	# 持刀者状态；用于读取并清空本回合下一张【杀】的酒加值。
	var weapon_holder: PlayerState = resolver.state.get_player(weapon_holder_id)
	if weapon_holder == null:
		return
	# 本次借刀【杀】伤害基数；固定基础1点并叠加一次酒加值。
	var damage_amount: int = 1 + weapon_holder.wine_bonus
	weapon_holder.wine_bonus = 0
	# 持刀者当前武器定义；借刀【杀】同样读取武器源码决定是否忽略防具。
	var weapon_definition: CardDefinition = resolver.host.get_equipment_definition(weapon_holder_id, "weapon")
	SlashCardEffect.new(resolver).resolve_external_target(slash, weapon_holder_id, int(context.get("victim_id", -1)), damage_amount, str(GameDatabase.get_card(slash.definition_id).get("nature", "normal")), weapon_definition != null and weapon_definition.slash_ignores_armor(), int(context.get("parent_card_uid", -1)))


## 恢复锦囊使用者对被【杀】者的独立目标选择；完成后继续持刀者响应，或在无响应等待时收尾原目标。
func continue_selection(resolver: Object, context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "borrow_sword_target" or response == null:
		return super.continue_selection(resolver, context, response)
	# 持刀者与当前合法目标；等待期间状态变化时不信任旧请求快照。
	var weapon_holder_id: int = int(context.get("weapon_holder_id", -1))
	var legal_target_ids: Array[int] = _get_legal_slash_target_ids(resolver.host.card_rules, weapon_holder_id)
	if response.confirmed and response.target_ids.size() == 1 and legal_target_ids.has(response.target_ids[0]):
		_resolve_borrow_sword(resolver, int(context.get("parent_card_uid", -1)), int(context.get("source_id", -1)), weapon_holder_id, response.target_ids[0])
	else:
		resolver.host.transfer_equipment(weapon_holder_id, int(context.get("source_id", -1)), "weapon")
	if not resolver.host.has_pending_card_choice():
		resolver.host.complete_card_target(int(context.get("parent_card_uid", -1)))
	return true


## 恢复持刀者的【杀】响应；响应牌已由控制器完成消费和模式校验。
func continue_response(resolver: Object, context: Dictionary, response_card: CardInstance) -> bool:
	# 响应用途；借刀初始出杀由本文件处理，随后产生的【闪】和武器响应委托【杀】牌族组件。
	var response_kind: String = str(context.get("kind", ""))
	if response_kind == "borrow_sword_response":
		_apply_borrow_sword_response(resolver, context, response_card)
		return true
	return SlashCardEffect.new(resolver).continue_response(context, response_card)


## 恢复借刀【杀】内部武器创建的普通选牌请求。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	return SlashCardEffect.new(resolver).continue_choice(context, selected_uids)


## 评估被【杀】者选择；优先令持刀者攻击锦囊使用者的敌方，并兼顾低体力目标的收益。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理本牌创建的被【杀】者目标选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "borrow_sword_target":
		return 0.0
	# 已选牌效目标；强制请求正常只有一名角色。
	var selected_target_ids: Array = (action.get("payload", {}) as Dictionary).get("selected_target_ids", []) as Array
	if selected_target_ids.size() != 1:
		return -10.0
	# 锦囊使用者与被【杀】者；负态度目标优先，低体力进一步提高预期伤害价值。
	var source_id: int = int(context.get("source_id", -1))
	var victim_id: int = int(selected_target_ids[0])
	var victim: Dictionary = evaluator.get_player(authoritative_snapshot, victim_id)
	return -evaluator.get_attitude(authoritative_snapshot, source_id, victim_id) + maxf(3.0 - float(victim.get("hp", 3)), 0.0)
