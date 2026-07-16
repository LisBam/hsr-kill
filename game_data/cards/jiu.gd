extends CardDefinition

## 【酒】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "jiu",
		"original_name": "酒",
		"custom_name": "激能剂",
		"type": "basic",
		"subtype": "boost",
		"effect_id": "wine",
		"nature": "normal",
		"target_mode": "self_wounded",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 1,
		"response_pattern": "jiu",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段限一次，仅对已受伤的自己使用；本回合下一张【杀】伤害基数+1。濒死时也只能对自己使用，回复1点体力。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "jiu",
	})


## 执行【酒】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_wine(card, actor_id, target_ids)
