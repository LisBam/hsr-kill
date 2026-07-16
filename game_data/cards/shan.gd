extends CardDefinition

## 【闪】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "shan",
		"original_name": "闪",
		"custom_name": "瞬身",
		"type": "basic",
		"subtype": "response",
		"effect_id": "dodge",
		"nature": "normal",
		"target_mode": "response_only",
		"min_targets": 0,
		"max_targets": 0,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "shan",
		"recast": false,
		"delayed": false,
		"description": "在【杀】对你生效前使用，抵消此【杀】。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "shan",
	})


## 执行【闪】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return "discard"
