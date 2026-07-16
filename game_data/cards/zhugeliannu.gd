extends CardDefinition

## 【诸葛连弩】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "zhuge",
		"original_name": "诸葛连弩",
		"custom_name": "智械连弩",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 1,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "你使用【杀】无次数限制。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
	})


## 执行【诸葛连弩】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_equipment(card, actor_id, target_ids)
