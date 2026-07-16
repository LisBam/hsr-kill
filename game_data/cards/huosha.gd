extends CardDefinition

## 【火杀】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "sha_fire",
		"original_name": "火杀",
		"custom_name": "熔火斩",
		"type": "basic",
		"subtype": "attack",
		"effect_id": "slash",
		"nature": "fire",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "attack_range",
		"play_limit": 1,
		"response_pattern": "sha",
		"recast": false,
		"delayed": false,
		"description": "【杀】的一种，造成的伤害为火焰伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "sha",
	})


## 执行【火杀】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_slash(card, actor_id, target_ids)


## 结算多目标【杀】的当前目标，并复用整张牌预先保存的酒加值、属性与无视防具状态。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	return resolver.resolve_slash_target(card, actor_id, target_id, int(resolution_context.get("slash_damage_amount", 1)), str(resolution_context.get("slash_nature", "normal")), bool(resolution_context.get("slash_ignore_armor", false)))
