extends CardDefinition

## 【决斗】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "juedou",
		"original_name": "决斗",
		"custom_name": "模拟对决",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "duel",
		"nature": "normal",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "目标与你轮流打出【杀】，首先未打出者受到另一方造成的1点伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【决斗】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_duel(card, actor_id, target_ids)
