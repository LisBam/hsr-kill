extends CardDefinition

## 【借刀杀人】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "jiedao",
		"original_name": "借刀杀人",
		"custom_name": "借刀杀人",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "borrow_sword",
		"nature": "normal",
		"target_mode": "weapon_holder",
		"min_targets": 2,
		"max_targets": 2,
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
	# 旧的整牌结算入口仅兼容已完整声明的两个目标；常规 per_target 流程由 resolve_target() 读取结算上下文，绝不能在此补开第二次选目标。
	if target_ids.size() >= 1 and not resolver.host.resolve_trick_negation(actor_id, target_ids[0], card.definition_id):
		if not resolver.is_resolution_stopped():
			# 第一名声明角色；其为实际进入本牌目标时机的持刀者。
			var weapon_holder_id: int = target_ids[0]
			# 第二名声明角色；仅供持刀者响应【杀】使用，不属于本牌目标。
			var victim_id: int = target_ids[1] if target_ids.size() >= 2 else -1
			if _get_legal_slash_target_ids(resolver.host.card_rules, weapon_holder_id).has(victim_id):
				_resolve_borrow_sword(resolver, card.uid, actor_id, weapon_holder_id, victim_id)
			else:
				resolver.host.transfer_equipment(weapon_holder_id, actor_id, "weapon")
	return resolver.default_destination()


## 结算【借刀杀人】唯一的持刀者目标；被【杀】者已在使用牌时指定并保存在共享上下文，不再创建第二次目标选择。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	if not resolver.host.resolve_trick_negation(actor_id, target_id, card.definition_id) and not resolver.is_resolution_stopped():
		# 使用时已指定的被【杀】者；上下文缺失时安全转入交出武器，避免旧存档或无效动作卡死。
		var victim_id: int = int(resolution_context.get("borrow_sword_victim_id", -1))
		if _get_legal_slash_target_ids(resolver.host.card_rules, target_id).has(victim_id):
			_resolve_borrow_sword(resolver, card.uid, actor_id, target_id, victim_id)
		else:
			resolver.host.transfer_equipment(target_id, actor_id, "weapon")
	return resolver.default_destination()


## 【借刀杀人】保留“持刀者、被【杀】者”的玩家点击顺序；实际用牌时机与目标数组只保留首名持刀者。
func preserves_requested_target_order() -> bool:
	return true


## 返回真正进入【借刀杀人】目标时机的唯一持刀者；第二名角色只作为强制【杀】的已声明对象保存。
func get_resolution_target_ids(requested_target_ids: Array[int]) -> Array[int]:
	# 实际结算目标；显式构造强类型数组，避免条件表达式推断为无类型 Array 后违反返回值契约。
	var result: Array[int] = []
	if requested_target_ids.size() >= 1:
		result.append(requested_target_ids[0])
	return result


## 将第二名已声明角色写入共享上下文；后续牌效直接要求持刀者对其使用【杀】，不再弹出二次选目标窗口。
func configure_requested_target_context(_match_host: Object, _card: CardInstance, _actor_id: int, requested_target_ids: Array[int], resolution_context: Dictionary) -> void:
	if requested_target_ids.size() == 2:
		resolution_context["borrow_sword_victim_id"] = requested_target_ids[1]


## 本牌不再改写共享目标上下文；CardUseEvent 的全部目标时机只处理唯一持刀者。
func configure_resolution_context(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> void:
	pass


## 校验已声明的持刀者与被【杀】者；第一名必须持武器，第二名必须是其攻击范围内的其他存活角色。
func validate_target_selection(rule_service: Object, actor: PlayerState, target_id: int, all_target_ids: Array[int]) -> String:
	if all_target_ids.is_empty():
		return ""
	# 持刀者状态；第一名必须是装备武器的其他存活角色。
	var weapon_holder_id: int = int(all_target_ids[0])
	var weapon_holder: PlayerState = rule_service.state.get_player(weapon_holder_id)
	if weapon_holder == null or weapon_holder_id == actor.player_id or weapon_holder.get_weapon() == null:
		return "借刀杀人的目标必须是装备武器的其他角色。"
	if _get_legal_slash_target_ids(rule_service, weapon_holder_id).is_empty():
		return "借刀杀人的目标当前没有可使用【杀】的合法角色。"
	if all_target_ids.size() >= 2:
		# 被【杀】者；第二名必须由第一名持刀者合法攻击，不能用锦囊使用者的距离替代。
		var victim_id: int = int(all_target_ids[1])
		if victim_id == weapon_holder_id or not _get_legal_slash_target_ids(rule_service, weapon_holder_id).has(victim_id):
			return "借刀杀人的第二个目标必须在持刀者的攻击范围内。"
	return ""


## 为基础 AI 枚举“持刀者、被【杀】者”的完整合法组合；使用时已同时声明两个目标，不再等待牌效内二次选择。
func append_play_phase_card_actions(match_host: Object, actor_id: int, card: CardInstance, result: Array[Dictionary]) -> bool:
	for holder: PlayerState in match_host.state.players:
		# 当前持刀者可攻击角色；每名合法受害者都与持刀者组成一条完整标准出牌动作。
		for victim_id: int in _get_legal_slash_target_ids(match_host.card_rules, holder.player_id):
			var requested_target_ids: Array[int] = [holder.player_id, victim_id]
			match_host.append_card_action_if_legal(result, actor_id, card, requested_target_ids)
	return true


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
