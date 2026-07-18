extends CardDefinition

## 【方天画戟】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "fangtian",
		"original_name": "方天画戟",
		"custom_name": "动能激发剑",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 4,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "若使用的【杀】是最后的手牌，此【杀】额外目标数上限+2。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":2.5, "equip_value":2.5},
		"ai_use_value": 5.0,
	})


## 执行【方天画戟】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 当【杀】是持有者最后一张手牌时，将最大目标数固定增加2。
func modify_maximum_target_count(actor: PlayerState, card: CardInstance, current_count: int) -> int:
	if str(GameDatabase.get_card(card.definition_id).get("effect_id", "")) == "slash" and card.zone == "hand" and actor.hand.size() == 1:
		return current_count + 2
	return current_count
