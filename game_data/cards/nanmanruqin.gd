extends CardDefinition

## 【南蛮入侵】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "nanman",
		"original_name": "南蛮入侵",
		"custom_name": "裂界侵袭",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "aoe_slash",
		"nature": "normal",
		"target_mode": "all_others",
		"min_targets": 1,
		"max_targets": 99,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "所有其他角色依次打出【杀】，否则受到你造成的1点伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【南蛮入侵】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return _resolve_aoe(resolver, card, actor_id, target_ids, "sha")


## 逐名要求目标响应【杀】；藤甲或无懈抵消时跳过当前目标。
func _resolve_aoe(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int], response_pattern: String) -> String:
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		# 当前目标状态；死亡或离场目标不再创建响应窗口。
		var target: PlayerState = resolver.state.get_player(target_id)
		if target == null or not target.alive or resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		# 目标防具定义；是否免疫当前群体锦囊由防具卡牌源码判断。
		var armor_definition: CardDefinition = resolver.host.get_equipment_definition(target_id, "armor")
		if armor_definition != null and armor_definition.blocks_aoe(card.definition_id):
			resolver.host.add_log("%s的防具令锦囊无效。" % target.display_name)
			continue
		# 群体响应上下文；异步选择通过父牌 UID 回到本卡牌源码。
		var response_context: Dictionary = {"kind":"aoe_response", "responder_id":target_id, "actor_id":actor_id, "pattern":response_pattern, "card_definition_id":card.definition_id, "parent_card_uid":card.uid}
		# 目标响应实体；为空时承受固定1点普通伤害。
		var response_card: CardInstance = resolver.host.request_response_card(target_id, response_pattern, "请选择是否响应群体锦囊。", response_context)
		if resolver.host.has_pending_card_choice():
			return "pending"
		if response_card == null and not resolver.is_resolution_stopped():
			resolver.host.damage(actor_id, target_id, 1, "normal", card.definition_id)
	return resolver.default_destination()


## 恢复当前目标的【杀】响应；未响应时由【南蛮入侵】造成1点普通伤害。
func continue_response(resolver: Object, context: Dictionary, response_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "aoe_response":
		return false
	if response_card == null:
		resolver.host.damage(int(context.get("actor_id", -1)), int(context.get("responder_id", -1)), 1, "normal", "nanman")
	return true
