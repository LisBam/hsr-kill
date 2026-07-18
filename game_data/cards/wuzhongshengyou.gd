extends CardDefinition

## 【无中生有】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "wuzhong",
		"original_name": "无中生有",
		"custom_name": "无中生有",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "draw_two",
		"nature": "normal",
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段仅对自己使用，摸两张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":7.0, "value":9.2, "target_result":2.0, "draw":2.0, "beneficial":true},
		"ai_use_value": 9.0,
		"ai_target_attitude": "friendly",
		"ai_beneficial": true,
	})


## 执行【无中生有】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.draw(target_id, 2)
	return resolver.default_destination()
