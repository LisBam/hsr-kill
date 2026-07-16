extends CardDefinition

## 【无懈可击】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "wuxie",
		"original_name": "无懈可击",
		"custom_name": "反制协议",
		"type": "trick",
		"subtype": "counter",
		"effect_id": "negate",
		"nature": "normal",
		"target_mode": "response_only",
		"min_targets": 0,
		"max_targets": 0,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "一张锦囊牌对一个目标生效前使用，抵消此锦囊牌；可继续被【无懈可击】响应。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "wuxie",
	})


## 执行【无懈可击】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return "discard"
