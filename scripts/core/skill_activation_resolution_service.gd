extends RefCounted

## 主动技能请求的独立生命周期；前置、技能子内容及后置均完整等待，不在派发调用栈中提前执行。

## 权威宿主；生命周期仅属于当前对局，不写入存档。
var _host: Object

## 本次内容的真实身份；无请求或参数失败为-1。
var _sequence_id: int = -1

## 技能入口是否实际受理；其选牌取消不撤销已经成立的发动请求。
var success: bool = false

## 明确拒绝原因；空值表示仍待结算或技能入口已经受理。
var error: String = ""

## 整次技能前置、效果和后置是否已结束；查询原内容寿命，不另存恢复状态。
var completed: bool:
	get:
		return _sequence_id < 0 or not _host.is_rule_sequence_pending(_sequence_id)


func _init(host: Object) -> void:
	_host = host


## 响应声明由ResponseResolutionService在原选择关闭后调用；普通主动请求使用相同内容。
func begin(player_id: int, skill_id: String, activation_context: Dictionary, invoke_body: bool = true) -> void:
	if _host.state == null or _host.state.game_over:
		_reject("当前没有可发动技能的进行中对局。")
		return
	# 当前技能运行时实例；必须由玩家所选武将直接配置并在开局时自动安装。
	var skill: SkillDefinition = _host.get_skill_instance(player_id, skill_id)
	if skill == null:
		_reject("当前武将未配置该技能。")
		return
	if not _host.can_activate_skill(player_id, skill_id, activation_context):
		_reject("该技能当前不满足发动条件。")
		return
	# 原角色；等待期间换将使旧请求失效。
	var player: PlayerState = _host.state.get_player(player_id)
	# 稳定原生关联；所有生命周期通知与子效果保留同一请求来源。
	var event_id: int = _host._record_runtime_event("SkillEvent", "skill", {"player_id":player_id, "skill_id":skill_id, "context":activation_context.duplicate(true)}, {}, _host._current_rule_parent_event_id())
	# 技能时机共享数据；全部字段均可序列化，触发器可读取但不得写入节点或运行时对象。
	var timing_data: Dictionary = {"skill_id":skill_id, "context":activation_context.duplicate(true), "source_character_generation":player.character_generation}
	# activation_skill_id有意不使用技能后续队列的skill_id字段：技能自身卸载后仍须发布本次真实After。
	var context: Dictionary = {"sequence_kind":"skill_activation", "player_id":player_id, "generation":player.character_generation, "activation_skill_id":skill_id, "activation_context":activation_context.duplicate(true), "invoke_body":invoke_body, "timing_data":timing_data, "event_id":event_id, "last_timing":"", "cancelled":false}
	# 每个通知独占一步；技能产生的选牌、费用、子牌、濒死或换形态先于后置通知完成。
	var steps: Array[Callable] = [_before.bind("logSkillBegin"), _before.bind("logSkill"), _before.bind("useSkillBegin"), _before.bind("useSkill"), _invoke, _after.bind("useSkillAfter"), _after.bind("skillAfter"), _after.bind("skill_used"), _finish]
	_sequence_id = _host.run_rule_sequence(steps, context)


## 拒绝只报告一次；异步前置取消时向原请求报告，不伪造成功历史或技能主体。
func _reject(message: String) -> void:
	if error.is_empty():
		error = message
		_host._reject(message)


## 在下一步骤读取完整前置的取消与参数修改；日志通知取消不替代useSkill前置规则。
func _read_before(sequence: RuleStepSequence) -> void:
	if sequence.waiting_event == null:
		return
	# 原前置事件；父内容已等待它的全部子内容结束。
	var before_event: RuleEvent = sequence.waiting_event
	sequence.waiting_event = null
	if str(sequence.context.last_timing) in ["useSkillBegin", "useSkill"] and (before_event.cancelled or before_event.neutralized):
		sequence.context.cancelled = true
		_reject("该技能的发动已被规则取消。")
	sequence.context.timing_data = before_event.data.duplicate(true)
	if before_event.data.get("context") is Dictionary:
		sequence.context.activation_context = (before_event.data.context as Dictionary).duplicate(true)


## 请求只属于原武将与原安装实例；执行前重新核对额度、目标及技能有效性。
func _skill(sequence: RuleStepSequence) -> SkillDefinition:
	if bool(sequence.context.cancelled):
		return null
	# 当前原角色；死亡、离场或换将时不能调用新武将的同名技能。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	# 当前原技能键；重复技能实例也保留调用时选择的稳定键。
	var skill: SkillDefinition = _host.get_skill_instance(int(sequence.context.player_id), str(sequence.context.activation_skill_id))
	if player == null or not player.alive or player.out_of_game or player.character_generation != int(sequence.context.generation) or skill == null or not skill.matches_character_generation(int(sequence.context.generation)) or not skill.can_use_effect(bool(sequence.context.activation_context.get("locked_skill_segment", false))):
		sequence.context.cancelled = true
		_reject("该技能的原角色或技能实例已经失效。")
		return null
	return skill


## 发布后返回，由父内容等待；不能在同一函数里读尚未完成的前置结果。
func _before(sequence: RuleStepSequence, timing_name: String) -> void:
	_read_before(sequence)
	if _skill(sequence) == null:
		return
	sequence.context.last_timing = timing_name
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), int(sequence.context.player_id), -1, sequence.context.timing_data, int(sequence.context.event_id))


## 技能执行错误；空字符串表示技能已通过公开规则端口成功提交效果或选择请求。
func _invoke(sequence: RuleStepSequence) -> void:
	_read_before(sequence)
	# 所有前置结束后的原技能；Before可修改参数，因此使用最终上下文复核。
	var skill: SkillDefinition = _skill(sequence)
	if skill == null:
		return
	if not _host.can_activate_skill(int(sequence.context.player_id), str(sequence.context.activation_skill_id), sequence.context.activation_context):
		_reject("该技能当前不满足发动条件。")
		return
	# 实际技能入口结果；产生的子内容归本步骤持有，下一步不会越过它们。
	var activation_error: String = skill.activate(sequence.context.activation_context) if bool(sequence.context.invoke_body) else ""
	if not activation_error.is_empty():
		_reject(activation_error)
		return
	success = true
	_host.state.action_sequence += 1
	sequence.context.timing_data["context"] = (sequence.context.activation_context as Dictionary).duplicate(true)


## 发动事实不因技能自身换将或卸载丢失；后置取消仅中断该通知，不回滚主体。
func _after(sequence: RuleStepSequence, timing_name: String) -> void:
	if not success:
		return
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), int(sequence.context.player_id), -1, sequence.context.timing_data, int(sequence.context.event_id))


## 所有效果和后置结束后刷新快照；出牌询问由统一内容边界恢复，不由技能分支强制重建。
func _finish(_sequence: RuleStepSequence) -> void:
	_host._emit_state()
