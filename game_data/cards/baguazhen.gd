extends CardDefinition

## 【八卦阵】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "bagua",
		"original_name": "八卦阵",
		"custom_name": "卜算阵列",
		"type": "equipment",
		"subtype": "armor",
		"effect_id": "equip",
		"slot": "armor",
		"attack_range": 0,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "需要使用或打出【闪】时，可判定；若结果为红色，视为使用或打出一张【闪】。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai_use_value": 5.0,
	})


## 执行【八卦阵】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 八卦阵在需要响应【闪】时提供装备发动入口，不需要额外手牌材料。
func can_offer_equipment_response(match_host: Object, player_id: int, response_patterns: Array[String]) -> bool:
	return response_patterns.has("shan")


## 选择八卦阵后执行判定；红色视为打出虚拟【闪】，黑色表示响应失败。
func consume_equipment_response(match_host: Object, player_id: int, equipment_uid: int, response_patterns: Array[String], material_card_uids: Array[int]) -> CardInstance:
	if not response_patterns.has("shan"):
		return null
	# 当前八卦阵实体；等待期间换装时旧入口失效。
	var equipment_card: CardInstance = match_host.get_equipment_card(player_id, "armor")
	if equipment_card == null or equipment_card.definition_id != get_id() or equipment_card.uid != equipment_uid:
		return null
	# 八卦阵判定牌；只有红色结果视为成功响应【闪】。
	var judgment_card: CardInstance = match_host.perform_judgment(player_id, "八卦阵")
	if judgment_card == null or judgment_card.get_color() != "red":
		return null
	match_host.add_log("%s的【八卦阵】判定为红色，视为打出【闪】。" % match_host.state.get_player(player_id).display_name)
	return CardInstance.new("shan", judgment_card.suit, judgment_card.rank)
