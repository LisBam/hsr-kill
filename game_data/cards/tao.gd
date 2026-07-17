extends CardDefinition

## 【桃】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tao",
		"original_name": "桃",
		"custom_name": "丰饶露",
		"type": "basic",
		"subtype": "recover",
		"effect_id": "peach",
		"nature": "normal",
		"target_mode": "self_wounded",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "tao",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段仅对已受伤的自己使用，回复1点体力；其他角色濒死时可在救援响应中对其使用。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "tao",
		"ai_use_value": 8.0,
		"ai_target_attitude": "friendly",
	})


## 执行【桃】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		resolver.host.emit_rule_timing("taoBegin", actor_id, actor_id, target_id, {"card_uid":card.uid, "card_id":card.definition_id})
		resolver.host.recover(actor_id, target_id, 1, card.definition_id)
	return resolver.default_destination()


## 【桃】允许任意存活角色在濒死窗口中响应并救援当前目标。
func get_dying_response_pattern(_responder_id: int, _dying_player_id: int) -> String:
	return str(get_metadata().get("provided_response_pattern", ""))


## 应用【桃】的濒死救援效果；固定回复1点体力并记录使用者与目标。
func resolve_dying_response(match_host: Object, responder_id: int, dying_player_id: int, _card: CardInstance) -> bool:
	# 救援者与濒死目标；任一无效时不修改状态。
	var responder: PlayerState = match_host.state.get_player(responder_id)
	var target: PlayerState = match_host.state.get_player(dying_player_id)
	if responder == null or target == null or not responder.alive or not target.alive:
		return false
	match_host.emit_rule_timing("taoBegin", responder_id, responder_id, dying_player_id, {"card_id":get_id(), "dying_response":true})
	match_host.recover(responder_id, dying_player_id, 1, get_id())
	match_host.add_log("%s对%s使用【桃】。" % [responder.display_name, target.display_name])
	return true
