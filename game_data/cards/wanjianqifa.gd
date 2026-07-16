extends CardDefinition

## 【万箭齐发】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "wanjian",
		"original_name": "万箭齐发",
		"custom_name": "群星齐射",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "aoe_dodge",
		"nature": "normal",
		"target_mode": "all_others",
		"min_targets": 1,
		"max_targets": 99,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "所有其他角色依次打出【闪】，否则受到你造成的1点伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【万箭齐发】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_aoe_dodge(card, actor_id, target_ids)
