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
	})


## 执行【借刀杀人】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.size() == 2 and not resolver.host.resolve_trick_negation(actor_id, target_ids[0], card.definition_id):
		if not resolver.is_resolution_stopped():
			_resolve_borrow_sword(resolver, card.uid, actor_id, target_ids[0], target_ids[1])
	return resolver.default_destination()


## 结算【借刀杀人】的持刀者目标，同时保留声明时“持刀者、被杀者”的双目标语义顺序。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, _target_id: int, resolution_context: Dictionary) -> String:
	# 完整效果目标；第一项为持刀者，第二项为被要求出【杀】的目标。
	var effect_target_ids: Array[int] = []
	for target_id_variant: Variant in resolution_context.get("effect_target_ids", []) as Array:
		effect_target_ids.append(int(target_id_variant))
	return resolve(resolver, card, actor_id, effect_target_ids)


## 借刀双目标分别表示持刀者与被要求攻击的角色，必须保留玩家声明顺序。
func preserves_requested_target_order() -> bool:
	return true


## 将逐目标事件缩减为持刀者一个内容节点，同时保留完整双目标数组供效果源码读取。
func configure_resolution_context(_match_host: Object, _card: CardInstance, _actor_id: int, resolution_context: Dictionary) -> void:
	# 完整效果目标；第一项为持刀者，第二项为被要求响应【杀】的目标。
	var effect_target_ids: Array = resolution_context.get("effect_target_ids", []) as Array
	if effect_target_ids.size() == 2:
		resolution_context["target_ids"] = [int(effect_target_ids[0])]


## 校验“持刀者、被杀者”的角色关系与持刀者攻击范围，避免规则服务包含具体卡牌分支。
func validate_target_selection(rule_service: Object, actor: PlayerState, target_id: int, all_target_ids: Array[int]) -> String:
	if all_target_ids.size() != 2:
		return ""
	# 持刀者 ID；目标数组第一项始终保留这一角色语义。
	var weapon_holder_id: int = all_target_ids[0]
	if target_id == weapon_holder_id:
		# 持刀者状态；必须是装备武器的其他存活角色。
		var weapon_holder: PlayerState = rule_service.state.get_player(weapon_holder_id)
		if weapon_holder == null or weapon_holder_id == actor.player_id or weapon_holder.get_weapon() == null:
			return "借刀杀人的第一目标必须是装备武器的其他角色。"
		return ""
	if target_id == all_target_ids[1]:
		if target_id == weapon_holder_id:
			return "被借刀者不能攻击自己。"
		if rule_service.calculate_distance(weapon_holder_id, target_id) > rule_service.get_attack_range(weapon_holder_id):
			return "第二目标不在被借刀者的攻击范围内。"
		return ""
	return "借刀杀人的目标组合不合法。"


## 为基础 AI 枚举全部合法“持刀者、被杀者”组合；提交前仍复用统一权威校验。
func append_play_phase_card_actions(match_host: Object, actor_id: int, card: CardInstance, result: Array[Dictionary]) -> bool:
	for holder: PlayerState in match_host.state.players:
		if not holder.alive or holder.player_id == actor_id or holder.get_weapon() == null:
			continue
		for victim: PlayerState in match_host.state.players:
			if not victim.alive or victim.player_id == holder.player_id:
				continue
			# 借刀动作目标；显式声明为整数类型，确保通过 Object 动态调用时满足控制器的 Array[int] 参数契约。
			var requested_target_ids: Array[int] = [holder.player_id, victim.player_id]
			match_host.append_card_action_if_legal(result, actor_id, card, requested_target_ids)
	return true


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
