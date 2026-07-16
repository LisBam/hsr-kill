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
		"play_limit_group": "wine",
		"play_limit_message": "本回合已经使用过【酒】。",
		"response_pattern": "jiu",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段限一次，仅对已受伤的自己使用；本回合下一张【杀】伤害基数+1。濒死时也只能对自己使用，回复1点体力。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "jiu",
		"ai_use_value": 2.0,
		"ai_target_attitude": "self_boost",
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


## 【酒】只允许濒死角色本人在救援窗口中作为自救响应。
func get_dying_response_pattern(responder_id: int, dying_player_id: int) -> String:
	return str(get_metadata().get("provided_response_pattern", "")) if responder_id == dying_player_id else ""


## 应用【酒】的濒死自救效果；固定回复本人1点体力。
func resolve_dying_response(match_host: Object, responder_id: int, dying_player_id: int, _card: CardInstance) -> bool:
	if responder_id != dying_player_id:
		return false
	# 濒死角色；无效或已经死亡时不能自救。
	var target: PlayerState = match_host.state.get_player(dying_player_id)
	if target == null or not target.alive:
		return false
	match_host.recover(responder_id, dying_player_id, 1, get_id())
	match_host.add_log("%s在濒死时使用【酒】自救。" % target.display_name)
	return true


## 新回合开始时重置该玩家的【酒】使用标记与未消耗伤害加值。
func on_turn_started(match_host: Object, player_id: int) -> void:
	# 新回合玩家；不存在时不写入任何状态。
	var player: PlayerState = match_host.state.get_player(player_id)
	if player != null:
		player.wine_used = false
		player.wine_bonus = 0


## 任意回合结束或中断时清除全部未消耗酒加值，保持原有持续时间规则。
func on_turn_ended(match_host: Object, _player_id: int, _interrupted: bool) -> void:
	for player: PlayerState in match_host.state.players:
		player.wine_bonus = 0
