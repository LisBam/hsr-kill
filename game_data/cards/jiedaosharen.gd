extends CardDefinition

## 【借刀杀人】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "jiedao",
		"original_name": "借刀杀人",
		"custom_name": "借刃执行",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "borrow_sword",
		"nature": "normal",
		"target_mode": "weapon_holder",
		"min_targets": 2,
		"max_targets": 2,
		"distance_limit": "special",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "令一名装备武器的角色对合法目标使用【杀】，否则其将武器交给你。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【借刀杀人】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_borrow_sword(card, actor_id, target_ids)


## 结算【借刀杀人】的持刀者目标，同时保留声明时“持刀者、被杀者”的双目标语义顺序。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, _target_id: int, resolution_context: Dictionary) -> String:
	# 完整效果目标；第一项为持刀者，第二项为被要求出【杀】的目标。
	var effect_target_ids: Array[int] = []
	for target_id_variant: Variant in resolution_context.get("effect_target_ids", []) as Array:
		effect_target_ids.append(int(target_id_variant))
	return resolver.resolve_borrow_sword(card, actor_id, effect_target_ids)
