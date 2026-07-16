extends CardDefinition

## 【桃园结义】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "taoyuan",
		"original_name": "桃园结义",
		"custom_name": "丰饶共鸣",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "heal_all",
		"nature": "normal",
		"target_mode": "all_players",
		"min_targets": 1,
		"max_targets": 99,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "所有已受伤角色依次回复1点体力。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai_use_value": 4.0,
		"ai_beneficial": true,
	})


## 执行【桃园结义】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.recover(actor_id, target_id, 1, card.definition_id)
	return resolver.default_destination()
