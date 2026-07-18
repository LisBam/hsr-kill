extends CardDefinition

## 【过河拆桥】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "guohe",
		"original_name": "过河拆桥",
		"custom_name": "净除协议",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "discard_target",
		"nature": "normal",
		"target_mode": "single_other_with_cards",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "弃置一名其他角色区域里的一张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":9.0, "value":5.0, "target_result":-1.5, "lose_card":true, "discard":true},
		"ai_target_attitude": "hostile",
	})


## 执行【过河拆桥】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.discard_one_from_player(actor_id, target_id, card.uid)
		if resolver.host.has_pending_card_choice():
			return "pending"
	return resolver.default_destination()
