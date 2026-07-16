extends CardDefinition

## 【藤甲】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tengjia",
		"original_name": "藤甲",
		"custom_name": "丰饶藤甲",
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
		"description": "锁定技，普通【杀】、【南蛮入侵】和【万箭齐发】对你无效；受到火焰伤害时伤害+1。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
	})


## 执行【藤甲】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_equipment(card, actor_id, target_ids)
