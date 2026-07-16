extends CardDefinition

## 【五谷丰登】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "wugu",
		"original_name": "五谷丰登",
		"custom_name": "星海赐福",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "harvest",
		"nature": "normal",
		"target_mode": "all_players",
		"min_targets": 1,
		"max_targets": 99,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "亮出等同目标数的牌，每名目标依次获得其中一张，剩余牌置入弃牌堆。",
		"resolution_mode": "whole",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【五谷丰登】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_harvest(card, actor_id, target_ids)
