extends RefCounted

## 濒死开始与获救收尾的内容组件；逐窗口等待子结算，求桃座次仍由现有响应接口负责。

## 权威宿主；本组件不保存跨步骤的角色对象，也不建立第二条恢复队列。
var _host: Object


## 绑定本局控制器；规则步骤持有服务直到其内容结束。
func _init(host: Object) -> void:
	_host = host


## 从dyingBefore开始建立一次濒死；各窗口保留原事件，选择之后读取最终数据。
func begin(context: Dictionary) -> void:
	# 当前目标；入口的身份快照用于拒绝等待期间换将后的旧结算。
	var target: PlayerState = _host.state.get_player(int(context.get("target_id", -1)))
	if target == null:
		return
	# 濒死上下文；只保存稳定编号、角色代次及可序列化的时机字段。
	var flow_context: Dictionary = context.duplicate(true)
	flow_context["sequence_kind"] = "dying_start"
	flow_context["target_character_generation"] = target.character_generation
	# 固定开始步骤；注册、通知、求桃入口之间分别保留子内容边界。
	var steps: Array[Callable] = [_emit_start.bind("dyingBefore"), _emit_start.bind("dyingBegin"), _register, _emit_start.bind("dying"), _emit_compat_begin, _begin_rescue]
	_host.run_rule_sequence(steps, flow_context)


## 当前目标必须仍为同一武将；窗口取消本身不修正体力，沿用须实际回复才能脱离濒死的规则。
func _get_dying_target(sequence: RuleStepSequence) -> PlayerState:
	# 濒死目标稳定ID；每一步重新读取实体，不让新武将继承旧求桃请求。
	var target_id: int = int(sequence.context.target_id)
	# 当前目标；死亡或换将只结束当前内容，不改动新实例状态。
	var target: PlayerState = _host.state.get_player(target_id)
	if target == null or not target.alive or target.character_generation != int(sequence.context.target_character_generation):
		sequence.finish()
		return null
	if target.hp > 0:
		sequence.finish()
		if target.dying or _host.state.dying_queue.has(target_id):
			_host._finish_dying_rescue(target_id)
		return null
	return target


## 下一窗口只接收前一窗口的最终数据；原RuleEvent一直由步骤保存到触发完整结束。
func _emit_start(sequence: RuleStepSequence, timing_name: String) -> void:
	if _get_dying_target(sequence) == null:
		return
	if sequence.waiting_event != null:
		sequence.context["event_data"] = sequence.waiting_event.data.duplicate(true)
		sequence.waiting_event = null
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.target_id), int(sequence.context.killer_id), int(sequence.context.target_id), sequence.context.event_data, int(sequence.context.get("dying_event_id", -2)))


## 全部Begin内容结束且目标仍需救援时才提交濒死事实；登记过程中不派发可暂停通知。
func _register(sequence: RuleStepSequence) -> void:
	# 当前濒死角色；回复、死亡或换将会在此停止注册。
	var target: PlayerState = _get_dying_target(sequence)
	if target == null:
		return
	# 濒死父事件ID；回放、标准通知和救援请求共享同一个事实。
	var dying_event_id: int = _host._record_runtime_event("dying", "dying", {"target_id":target.player_id, "source_id":int(sequence.context.killer_id)})
	if not _host.state.dying_queue.has(target.player_id):
		_host.state.dying_queue.append(target.player_id)
	target.dying = true
	_host._record_runtime_event("_save", "choice", {"target_id":target.player_id, "source_id":int(sequence.context.killer_id)}, {}, dying_event_id)
	sequence.context["dying_event_id"] = dying_event_id
	sequence.context["event_data"] = {"hp":target.hp, "required_recover":1 - target.hp, "dying_event_id":dying_event_id}
	sequence.waiting_event = null


## 旧兼容通知同样独占步骤，不能越过dying中尚未完成的选择。
func _emit_compat_begin(sequence: RuleStepSequence) -> void:
	# 当前仍需救援的角色；dying技能已救起时改走完整获救收尾。
	var target: PlayerState = _get_dying_target(sequence)
	if target == null:
		return
	_host.add_log("%s进入濒死状态，需要回复至1点体力。" % _host.format_player_state_log_name(target))
	_host.emit_sequence_timing(sequence, "dying_begin", target.player_id, int(sequence.context.killer_id), target.player_id, {"required_recover":1 - target.hp}, int(sequence.context.dying_event_id))


## 只在所有开始通知及其子技能结束后开放原单轮求桃入口。
func _begin_rescue(sequence: RuleStepSequence) -> void:
	if _get_dying_target(sequence) != null:
		_host._resolve_dying(int(sequence.context.target_id), int(sequence.context.killer_id))


## 先提交脱离濒死事实，再逐窗口报告；重复完成调用不会重复发布After或执行伤害尾部。
func finish(target_id: int) -> void:
	# 获救角色；未登记濒死时不伪造一次新的完成事件。
	var target: PlayerState = _host.state.get_player(target_id)
	if target == null:
		_host.state.dying_queue.erase(target_id)
		return
	if not target.dying and not _host.state.dying_queue.has(target_id):
		return
	_host.state.dying_queue.erase(target_id)
	target.dying = false
	_host._record_runtime_event("dyingAfter", "dying", {"target_id":target_id, "hp":target.hp, "rescued":true})
	# 获救事实快照；后续时机只观察本次结果，不再清理可能新建的濒死状态。
	var context: Dictionary = {"sequence_kind":"dying_finish", "target_id":target_id, "target_character_generation":target.character_generation, "event_data":{"hp":target.hp, "rescued":true}}
	# 完成窗口分别等待；原伤害尾部最后才能继续。
	var steps: Array[Callable] = [_emit_completed.bind("dyingAfter"), _emit_completed.bind("dying_end"), _complete]
	_host.run_rule_sequence(steps, context)


## 已成立的获救结果不因后续再次受伤而改写；每个通知完成后才进入下一步骤。
func _emit_completed(sequence: RuleStepSequence, timing_name: String) -> void:
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.target_id), int(sequence.context.target_id), int(sequence.context.target_id), sequence.context.event_data)


## 完成通知全部结束后交回原伤害；角色代次校验避免取走新武将的待结算内容。
func _complete(sequence: RuleStepSequence) -> void:
	# 当前目标；同一武将才输出其获救日志，换将不影响原伤害事实的收尾。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id))
	if target != null and target.character_generation == int(sequence.context.target_character_generation):
		_host.add_log("%s脱离濒死状态，求桃流程结算完成。" % _host.format_player_state_log_name(target))


## 建立唯一单轮求桃内容；每个应答者可连续使用救援牌，拒绝后不会重新询问整桌。
func rescue(target_id: int, killer_id: int, start_id: int = -1, asked_ids: Array[int] = []) -> void:
	# 原濒死角色；每个步骤再次检查其代次及当前体力。
	var target: PlayerState = _host.state.get_player(target_id)
	if target == null:
		return
	# 固定本轮起点；负值使用当前回合角色。
	var rescue_start_id: int = _host.state.current_player_id if start_id < 0 else start_id
	# 座次快照仅保存ID；应答前重读存活状态，不保留实体引用。
	var order: Array[int] = []
	for rescuer: PlayerState in _host._get_alive_players_in_action_order(rescue_start_id):
		order.append(rescuer.player_id)
	# 每个救援请求归属于自己的序列，嵌套濒死不会覆盖外层游标。
	var context: Dictionary = {"sequence_kind":"rescue", "target_id":target_id, "killer_id":killer_id, "target_character_generation":target.character_generation, "order":order, "asked_ids":asked_ids.duplicate(), "rescue_start_id":rescue_start_id}
	var steps: Array[Callable] = [_next_rescuer]
	_host.run_rule_sequence(steps, context)


## 选择下一名应答者；没有剩余座位才进入死亡，体力已正则经过正式获救尾部。
func _next_rescuer(sequence: RuleStepSequence) -> void:
	# 当前目标；之前回复、换将或死亡会在共同入口结束内容。
	var target: PlayerState = _get_dying_target(sequence)
	if target == null:
		return
	if target.out_of_game:
		_host._resolve_death(target.player_id, int(sequence.context.killer_id))
		return
	for responder_id: int in sequence.context.order:
		if (sequence.context.asked_ids as Array).has(responder_id):
			continue
		# 本轮仍在场的应答者；此前技能可能已让其死亡或离场。
		var rescuer: PlayerState = _host.state.get_player(responder_id)
		if rescuer == null or not rescuer.alive or rescuer.out_of_game:
			continue
		sequence.context.asked_ids.append(responder_id)
		sequence.context["responder_id"] = responder_id
		sequence.context["responder_generation"] = rescuer.character_generation
		sequence.context["selected_uids"] = []
		sequence.context["response_card"] = {}
		# 卡牌源码声明可用模式，主流程不硬编码桃或酒。
		var response_patterns: Array[String] = []
		var response_names: Array[String] = []
		for option: Dictionary in _host._get_dying_response_options(responder_id, target.player_id):
			response_patterns.append(str(option.get("pattern", "")))
			response_names.append("【%s】" % str(option.get("name", "救援牌")))
		var rescue_context: Dictionary = {"kind":"dying_response", "rescue_sequence_id":sequence.sequence_id, "responder_id":responder_id, "target_id":target.player_id, "killer_id":sequence.context.killer_id, "rescue_start_id":sequence.context.rescue_start_id, "response_patterns":response_patterns, "asked_rescuer_ids":sequence.context.asked_ids.duplicate(), "required_recover":1 - target.hp, "response_action":"use"}
		sequence.context["response_context"] = rescue_context
		# 顺序固定为询问、消费、回复、再检查；失牌和回复的触发分别等待。
		var steps: Array[Callable] = [_consume_rescue, _apply_rescue, _after_rescue, _next_rescuer]
		sequence.insert_steps(steps)
		var prompt: String = "%s当前还需要回复%d点体力至1点，请选择是否使用%s。" % [_host._player_character_name(target), 1 - target.hp, "、".join(response_names) if not response_names.is_empty() else "救援牌"]
		var rescue_card: CardInstance = _host.request_response_card_patterns(responder_id, response_patterns, prompt, rescue_context)
		if rescue_card != null:
			sequence.context.response_card = _host._serialize_optional_response_card(rescue_card)
		return
	_host._resolve_death(target.player_id, int(sequence.context.killer_id))


## 消费只发生一次；目标或应答者已经换将时旧窗口不能花费新武将的牌。
func _consume_rescue(sequence: RuleStepSequence) -> void:
	if _get_dying_target(sequence) == null or not (sequence.context.response_card as Dictionary).is_empty():
		return
	# 当前救援者；代次必须与发起窗口时一致。
	var rescuer: PlayerState = _host.state.get_player(int(sequence.context.responder_id))
	if rescuer == null or not rescuer.alive or rescuer.character_generation != int(sequence.context.responder_generation):
		return
	var selected_uids: Array[int] = _host._int_array(sequence.context.selected_uids)
	if selected_uids.is_empty():
		return
	var response_patterns: Array[String] = _host._string_array(sequence.context.response_context.get("response_patterns", []))
	var response_card: CardInstance = _host._consume_response_card_uid_patterns(rescuer.player_id, selected_uids[0], response_patterns, _host._int_array(sequence.context.get("material_uids", [])), str(sequence.context.get("response_skill_id", "")), sequence.context.response_context)
	sequence.context.response_card = _host._serialize_optional_response_card(response_card)


## 失牌子内容完成后应用一次救援；回复的Before和After仍是本步骤的子内容。
func _apply_rescue(sequence: RuleStepSequence) -> void:
	if _get_dying_target(sequence) == null:
		return
	# 已经消费的逻辑救援牌；不再次从任何区域取得实体牌。
	var response_card: CardInstance = _host._deserialize_optional_response_card(sequence.context.response_card)
	if response_card != null:
		_host._apply_dying_response_card(int(sequence.context.responder_id), int(sequence.context.target_id), response_card)


## 回复子内容全部结束后决定是否允许同一应答者继续；取消保持其已询问状态。
func _after_rescue(sequence: RuleStepSequence) -> void:
	if _get_dying_target(sequence) == null:
		return
	if not (sequence.context.response_card as Dictionary).is_empty():
		sequence.context.asked_ids.erase(int(sequence.context.responder_id))
