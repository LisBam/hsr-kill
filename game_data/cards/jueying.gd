extends CardDefinition

## 【绝影】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "jueying",
		"original_name": "绝影",
		"custom_name": "巡星骏影",
		"type": "equipment",
		"subtype": "defensive_mount",
		"effect_id": "equip",
		"slot": "defensive_mount",
		"distance_modifier": 1,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "锁定技，其他角色计算与你的距离+1。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":4.0, "equip_value":4.0},
	})


## 执行【绝影】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"
