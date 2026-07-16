extends CardDefinition

## 【顺手牵羊】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "shunshou",
		"original_name": "顺手牵羊",
		"custom_name": "奇物巧取",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "steal_target",
		"nature": "normal",
		"target_mode": "single_other_with_cards",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "one",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "获得距离为1的一名其他角色区域里的一张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【顺手牵羊】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_steal_target(card, actor_id, target_ids)
