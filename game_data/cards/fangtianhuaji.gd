extends CardDefinition

## 【方天画戟】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "fangtian",
		"original_name": "方天画戟",
		"custom_name": "毁灭战戟",
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
	})


## 执行【方天画戟】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_equipment(card, actor_id, target_ids)
