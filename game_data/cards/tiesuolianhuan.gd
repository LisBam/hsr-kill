extends CardDefinition

## 【铁索连环】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tiesuo",
		"original_name": "铁索连环",
		"custom_name": "命途连结",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "chain",
		"nature": "normal",
		"target_mode": "one_or_two",
		"min_targets": 1,
		"max_targets": 2,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": true,
		"delayed": false,
		"description": "令一至两名角色横置或重置；也可重铸并摸一张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 执行【铁索连环】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		# 当前目标状态；每次生效都在横置与重置之间切换一次。
		var target: PlayerState = resolver.state.get_player(target_id)
		if target == null:
			continue
		target.chained = not target.chained
		resolver.host.add_log("%s%s。" % [target.display_name, "进入连环状态" if target.chained else "解除连环状态"])
	return resolver.default_destination()
