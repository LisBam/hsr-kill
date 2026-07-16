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
	if target_ids.is_empty():
		return "discard"
	# 使用者状态；用于记录本回合已使用【酒】，继续受出牌阶段次数规则约束。
	var actor: PlayerState = resolver.state.get_player(actor_id)
	# 【酒】目标状态；正常出牌时固定为使用者本人，濒死自救由独立响应流程处理。
	var wine_target: PlayerState = resolver.state.get_player(target_ids[0])
	if actor == null or wine_target == null:
		return "discard"
	actor.wine_used = true
	wine_target.wine_bonus = 1
	resolver.host.add_log("%s使用【酒】，本回合下一张【杀】伤害+1。" % actor.display_name)
	return resolver.default_destination()
