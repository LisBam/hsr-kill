extends CardDefinition

## 【火杀】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "sha_fire",
		"rule_name": "杀",
		"original_name": "火杀",
		"custom_name": "火杀",
		"type": "basic",
		"subtype": "attack",
		"effect_id": "slash",
		"nature": "fire",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "attack_range",
		"play_limit": 1,
		"play_limit_group": "slash",
		"play_limit_scope": "phase",
		"play_limit_message": "本阶段使用【杀】的基础次数已用尽。",
		"response_pattern": "sha",
		"recast": false,
		"delayed": false,
		"description": "【杀】的一种，造成的伤害为火焰伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "sha",
		"ai": {"order":3.2, "value":[5.0, 3.0, 1.0], "target_result":-1.5, "damage":true, "respond_shan":true, "fire_damage":true, "nature_damage":true},
		"ai_target_attitude": "hostile",
	})


## 执行【火杀】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return SlashCardEffect.new(resolver).resolve(card, actor_id, target_ids)


## 结算多目标【杀】的当前目标，并复用整张牌预先保存的酒加值、属性与无视防具状态。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	return SlashCardEffect.new(resolver).resolve_target(card, actor_id, target_id, int(resolution_context.get("slash_damage_amount", 1)), str(resolution_context.get("slash_nature", "normal")), bool(resolution_context.get("slash_ignore_armor", false)))


## 写入整张火【杀】共享的酒加值、火焰属性与无视防具状态。
func configure_resolution_context(match_host: Object, card: CardInstance, actor_id: int, resolution_context: Dictionary) -> void:
	SlashCardEffect.configure_shared_resolution_context(match_host, card, actor_id, resolution_context)


## 执行武器对整张火【杀】的准备钩子；创建选择时暂停目标结算。
func on_resolution_started(match_host: Object, card: CardInstance, actor_id: int, resolution_context: Dictionary) -> bool:
	return SlashCardEffect.begin_shared_resolution(match_host, card, actor_id, resolution_context)


## 记录兼容统计中的本回合【杀】使用次数；普通、火与雷【杀】共享同一配置分组。
func on_card_declared(_match_host: Object, actor: PlayerState, _card: CardInstance) -> void:
	actor.slash_count += 1


## 恢复【杀】流程中的武器选牌；具体阶段由共享牌族组件根据 kind 识别。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	return SlashCardEffect.new(resolver).continue_choice(context, selected_uids)


## 恢复【闪】或青龙偃月刀追加【杀】响应；响应牌已由控制器完成合法消费。
func continue_response(resolver: Object, context: Dictionary, response_card: CardInstance) -> bool:
	return SlashCardEffect.new(resolver).continue_response(context, response_card)
