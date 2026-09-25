extends RefCounted

## 回复内容组件；原子体力写入与可交互通知分离，避免救援窗口提前判定死亡。

## 规则宿主；步骤只保存稳定角色信息。
var _host: Object


func _init(host: Object) -> void:
	_host = host


## 回复请求使用原有数值规则；每个窗口等待其子效果完成。
func recover(source_id: int, target_id: int, amount: int, reason: String, allow_out_of_game: bool) -> void:
	# 当前合法回复目标；原武将代次用于恢复时复核。
	var target: PlayerState = _host.state.get_player(target_id)
	if target == null or not target.alive or (target.out_of_game and not allow_out_of_game) or amount <= 0 or target.hp >= target.max_hp:
		return
	# 共享窗口数据；实际回复值由提交步骤写回。
	var context: Dictionary = {"source_id":source_id, "target_id":target_id, "generation":target.character_generation, "reason":reason, "allow_out_of_game":allow_out_of_game, "data":{"amount":amount, "reason":reason, "hp":target.hp, "max_hp":target.max_hp}}
	var steps: Array[Callable] = [_before.bind("recoverBefore"), _before.bind("recoverBegin"), _commit, _notify.bind("changeHp"), _notify.bind("recoverEnd"), _notify.bind("recoverAfter"), _notify.bind("recover_after")]
	_host.run_rule_sequence(steps, context)


## 回读最终窗口数据并复核原武将；取消不产生任何回复事实。
func _validate(sequence: RuleStepSequence) -> PlayerState:
	if sequence.waiting_event != null:
		sequence.context.data = sequence.waiting_event.data.duplicate(true)
		if sequence.waiting_event.cancelled or sequence.waiting_event.neutralized:
			sequence.finish()
			return null
		sequence.waiting_event = null
	# 等待后的实体；出局与换将使原回复请求失效。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id))
	if target == null or not target.alive or target.character_generation != int(sequence.context.generation) or (target.out_of_game and not bool(sequence.context.allow_out_of_game)):
		sequence.finish()
		return null
	return target


func _before(sequence: RuleStepSequence, timing_name: String) -> void:
	if _validate(sequence) != null:
		_notify(sequence, timing_name)


## 只在两个前置窗口全部完成后写入体力、统计、日志与事实快照。
func _commit(sequence: RuleStepSequence) -> void:
	# 当前目标；原子块内不发布玩法触发。
	var target: PlayerState = _validate(sequence)
	if target == null:
		return
	# 稳定来源与目标；允许来源在等待期间已经死亡，事实仍归属原来源。
	var source_id: int = int(sequence.context.source_id)
	var target_id: int = int(sequence.context.target_id)
	var reason: String = str(sequence.context.reason)
	# 最终回复请求值；非正数表示触发器已经把本次回复降为无效果。
	var final_amount: int = maxi(int(sequence.context.data.get("amount", 0)), 0)
	if final_amount <= 0:
		sequence.finish()
		return
	# 回复前体力；用于计算实际回复量并记录准确数值。
	var previous_hp: int = target.hp
	target.hp = mini(target.max_hp, target.hp + final_amount)
	# 实际回复量；体力接近上限时小于请求值，结算统计和事件均必须使用这一数值。
	var recovered_amount: int = target.hp - previous_hp
	# 回复效果音；体力已满或被上限截断为0的无效回复不发声。
	if recovered_amount > 0:
		_host.request_effect_voice(target_id, MatchController.EFFECT_RECOVER)
	# 回复来源角色；来源为自身时同样累计，来源缺失的系统回复不归属任何角色。
	var recovery_source: PlayerState = _host.state.get_player(source_id) if source_id >= 0 else null
	if recovery_source != null and recovered_amount > 0:
		recovery_source.total_healing_done += recovered_amount
	_host._record_runtime_event("recover", "recover", {"source_id":source_id, "target_id":target_id, "requested_amount":final_amount, "reason":reason}, {"amount":recovered_amount, "hp":target.hp})
	_host.add_log("%s回复%d点体力（%d/%d）。" % [_host.format_player_state_log_name(target), recovered_amount, target.hp, target.max_hp])
	# 体力值实际变化时机；回复、伤害与失去体力共用 changeHp，并通过 change_type 区分来源。
	var result_data: Dictionary = {"amount":recovered_amount, "hp":target.hp, "max_hp":target.max_hp, "reason":reason, "change_type":"recover"}
	sequence.context.data = result_data


## 结果通知使用提交快照；取消结果通知不撤销已发生的回复。
func _notify(sequence: RuleStepSequence, timing_name: String) -> void:
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.target_id), int(sequence.context.source_id), int(sequence.context.target_id), sequence.context.data)
