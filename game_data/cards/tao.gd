extends CardDefinition

## 【桃】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tao",
		"original_name": "桃",
		"custom_name": "丰饶露",
		"type": "basic",
		"subtype": "recover",
		"effect_id": "peach",
		"nature": "normal",
		"target_mode": "self_wounded",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "tao",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段仅对已受伤的自己使用，回复1点体力；其他角色濒死时可在救援响应中对其使用。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "tao",
	})


## 执行【桃】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		resolver.host.recover(actor_id, target_id, 1, card.definition_id)
	return resolver.default_destination()
