extends CardDefinition

## 【赤兔】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "chitu",
		"original_name": "赤兔",
		"custom_name": "赤焰驰轮",
		"type": "equipment",
		"subtype": "offensive_mount",
		"effect_id": "equip",
		"slot": "offensive_mount",
		"distance_modifier": -1,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "锁定技，你计算与其他角色的距离-1。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":3.0, "equip_value":3.0},
	})


## 执行【赤兔】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"
