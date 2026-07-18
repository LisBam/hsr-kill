extends CardDefinition

## 【青釭剑】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "qinggang",
		"original_name": "青釭剑",
		"custom_name": "碎星斩舰刀",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 2,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "锁定技，你使用【杀】指定目标后，无视其防具直至该目标的结算结束。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":2.0, "equip_value":2.0},
		"ai_use_value": 5.0,
	})


## 执行【青釭剑】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 青釭剑令持有者使用的【杀】在对应目标结算期间忽略防具。
func slash_ignores_armor() -> bool:
	return true
