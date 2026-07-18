extends CardDefinition

## 【仁王盾】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "renwang",
		"original_name": "仁王盾",
		"custom_name": "仁王盾",
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
		"description": "锁定技，黑色【杀】对你无效。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":7.5, "equip_value":7.5},
		"ai_use_value": 5.0,
	})


## 执行【仁王盾】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 仁王盾令黑色实体【杀】无效；无颜色的虚拟【杀】不满足条件。
func blocks_slash(card: CardInstance, nature: String) -> bool:
	return card.get_color() == "black"
