extends CardDefinition

## 【桃】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tao",
		"original_name": "桃",
		"custom_name": "药",
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
		"ai": {"order":2.0, "value":9.0, "target_result":2.0, "recover":true, "save":true, "beneficial":true},
		"ai_use_value": 8.0,
		"ai_target_attitude": "friendly",
	})


## 执行【桃】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		_begin_recovery(resolver.host, actor_id, target_id, {"card_uid":card.uid, "card_id":card.definition_id})
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
	_begin_recovery(match_host, responder_id, dying_player_id, {"card_id":get_id(), "dying_response":true})
	match_host.add_log("%s对%s使用【桃】。" % [responder.display_name, target.display_name])
	return true


## 普通使用与求桃共用两步内容；taoBegin结束前不修改体力。
func _begin_recovery(match_host: Object, actor_id: int, target_id: int, data: Dictionary) -> void:
	# 原目标代次；等待中的换将不能把旧桃效果交给新武将。
	var target: PlayerState = match_host.state.get_player(target_id)
	if target == null:
		return
	# 每个可交互效果独占一步；回复内部仍由统一回复组件编排。
	var steps: Array[Callable] = [_begin_timing.bind(match_host), _apply_recovery.bind(match_host)]
	match_host.run_rule_sequence(steps, {"actor_id":actor_id, "target_id":target_id, "generation":target.character_generation, "data":data})


## 保存原始时机对象；异步取消需要在后续步骤读取最终状态。
func _begin_timing(sequence: RuleStepSequence, match_host: Object) -> void:
	match_host.emit_sequence_timing(sequence, "taoBegin", int(sequence.context.actor_id), int(sequence.context.actor_id), int(sequence.context.target_id), sequence.context.data)


## 前置取消只阻止效果，不撤销已使用的桃；合法目标固定回复1点。
func _apply_recovery(sequence: RuleStepSequence, match_host: Object) -> void:
	if sequence.waiting_event != null and (sequence.waiting_event.cancelled or sequence.waiting_event.neutralized):
		return
	# 重新读取目标实体；来源可已死亡，但效果不能作用于替换后的目标。
	var target: PlayerState = match_host.state.get_player(int(sequence.context.target_id))
	if target != null and target.character_generation == int(sequence.context.generation):
		match_host.recover(int(sequence.context.actor_id), target.player_id, 1, get_id())
