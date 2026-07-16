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


## 要求持刀者打出【杀】；拒绝或无法响应时将其武器交给锦囊使用者。
func _resolve_borrow_sword(resolver: Object, parent_card_uid: int, source_id: int, weapon_holder_id: int, victim_id: int) -> void:
	# 借刀响应上下文；父牌 UID 使异步恢复重新定位本卡牌源码。
	var response_context: Dictionary = {"kind":"borrow_sword_response", "parent_card_uid":parent_card_uid, "responder_id":weapon_holder_id, "source_id":source_id, "victim_id":victim_id}
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
	SlashCardEffect.new(resolver).resolve_external_target(slash, weapon_holder_id, int(context.get("victim_id", -1)), damage_amount, str(GameDatabase.get_card(slash.definition_id).get("nature", "normal")), weapon_definition != null and weapon_definition.slash_ignores_armor())


## 恢复持刀者的【杀】响应；响应牌已由控制器完成消费和模式校验。
func continue_response(resolver: Object, context: Dictionary, response_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "borrow_sword_response":
		return false
	_apply_borrow_sword_response(resolver, context, response_card)
	return true
