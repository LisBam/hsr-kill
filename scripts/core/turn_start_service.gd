extends RefCounted

## 回合开始编排；轮开始、回合前、翻面跳过和准备阶段都在内容步骤之间等待子结算。

## 权威宿主；只调用已有回合事实与阶段入口，不管理第二套恢复队列。
var _host: Object


## 绑定当前对局控制器；服务由序列回调强引用至内容完成。
func _init(host: Object) -> void:
	_host = host


## 每个固定窗口独占一步；取消分支只终止未发生的回合内容，不重复初始化或输出日志。
func resolve(context: Dictionary) -> void:
	# 回合内容；轮开始只在真实新轮执行，其余步骤沿用当前玩法顺序。
	var steps: Array[Callable] = [_restore_round_players, _emit_round_start, _initialize, _log_begin, _emit_turn_window.bind("phaseBefore"), _check_face_down, _emit_turn_window.bind("phaseBeforeStart"), _emit_turn_window.bind("phaseBeforeEnd"), _emit_turn_window.bind("phaseBeginStart"), _emit_turn_window.bind("phaseBegin"), _begin_preparation]
	_host.run_rule_sequence(steps, context)


## 每次副作用前重新按稳定ID读取回合角色；子技能使其死亡或离场时不再开启后续阶段。
func _valid(sequence: RuleStepSequence) -> bool:
	if _host.state == null or _host.state.game_over:
		sequence.finish()
		return false
	# 当前回合玩家；等待期间不能保留旧角色引用。
	var player: PlayerState = _host.state.get_player(int(sequence.context.get("player_id", -1)))
	if player == null or not player.alive or player.out_of_game or _host.state.current_player_id != player.player_id:
		sequence.finish()
		return false
	return true


## 新轮限时离场恢复先于roundStart；其子技能结束后才通知全场轮开始。
func _restore_round_players(sequence: RuleStepSequence) -> void:
	if _valid(sequence) and bool(sequence.context.get("starts_new_round", false)):
		_host._restore_round_limited_out_of_game_players(_host.state.round_number)


## 临时技能到期先于新轮技能；事件原对象用于等待完整触发批次。
func _emit_round_start(sequence: RuleStepSequence) -> void:
	if not _valid(sequence) or not bool(sequence.context.get("starts_new_round", false)):
		return
	_host._expire_temporary_skills_for_round(_host.state.round_number)
	_emit(sequence, "roundStart", {"round_number":_host.state.round_number})


## 新回合事实只初始化一次；与可暂停通知分离，避免恢复重复清空技能历史。
func _initialize(sequence: RuleStepSequence) -> void:
	if _valid(sequence):
		_host._initialize_turn_context(sequence.context)


## 回合开始日志必须先于所有回合开始技能与准备阶段日志。
func _log_begin(sequence: RuleStepSequence) -> void:
	if not _valid(sequence):
		return
	_host.add_log("————————")
	_host.add_log("%s的回合开始。" % _host.format_player_state_log_name(_host.state.get_player(int(sequence.context.player_id))))
	_emit(sequence, "phase_start", {})


## 回读已完成回合前置窗口；取消后的回合不再进入准备阶段，取消通知也有独立等待边界。
func _read_turn_window(sequence: RuleStepSequence) -> bool:
	if not _valid(sequence):
		return false
	# 原始修改窗口；选择返回后才能读取取消结果。
	var previous_event: RuleEvent = sequence.waiting_event
	sequence.waiting_event = null
	if previous_event == null or not previous_event.name.begins_with("phaseB") or not (previous_event.cancelled or previous_event.neutralized):
		return true
	sequence.context["cancel_reason"] = previous_event.name
	# 取消后继；通知结束后复用原完整回合尾部规则。
	var steps: Array[Callable] = [_emit_cancelled, _finish_cancelled]
	_host.run_rule_sequence(steps, sequence.context)
	sequence.finish()
	return false


## 回合前置时机的固定窗口；各窗口最终结果在下一步统一回读。
func _emit_turn_window(sequence: RuleStepSequence, timing_name: String) -> void:
	if not _read_turn_window(sequence):
		return
	if timing_name in ["phaseBefore", "phaseBegin"]:
		_host._record_runtime_event(timing_name, "phase", {"player_id":int(sequence.context.player_id)}, {}, int(sequence.context.get("turn_event_id", -1)))
	_emit(sequence, timing_name, {"turn_number":_host.state.turn_number, "round_number":_host.state.round_number})


## 背面朝上跳过整个回合；翻面、取消与Over分成独立步骤，后一个通知不得抢跑。
func _check_face_down(sequence: RuleStepSequence) -> void:
	if not _read_turn_window(sequence):
		return
	# 「武将牌始终背面向上」类锁定规则的权威兜底：换将、复活或技能重装若把该角色的状态留在正面，
	# 在其自己的回合开始窗口先纠正回背面，再按既有统一规则跳过本回合。
	# 纠正必须放在背面判定之前，锁定角色的回合处理才与普通背面角色完全一致。
	_host.enforce_face_down_lock(int(sequence.context.player_id))
	if not _host.state.get_player(int(sequence.context.player_id)).face_down:
		return
	sequence.context["cancel_reason"] = "face_down"
	# 翻面跳过专属分支；不伪造六阶段主体或阶段结束通知。
	var steps: Array[Callable] = [_turn_face_up, _emit_cancelled, _emit_over, _finish_face_down]
	_host.run_rule_sequence(steps, sequence.context)
	sequence.finish()


## 翻回正面并记录跳过事实；已有翻面规则负责实际角色状态变化。
## 「武将牌始终背面向上」类锁定技会拒绝本次翻至正面，此时日志必须与事实一致，不能写成已经翻回正面。
func _turn_face_up(sequence: RuleStepSequence) -> void:
	# 本次翻面（正面→背面之外的“背面→正面”方向）是否真的发生；由统一翻面入口给出唯一结论。
	var turned_face_up: bool = _host.turn_over_player(int(sequence.context.player_id), int(sequence.context.player_id), "turn_start_skip")
	if turned_face_up:
		_host.add_log("%s翻回正面并跳过本回合。" % _host.format_player_state_log_name(_host.state.get_player(int(sequence.context.player_id))))
		return
	_host.add_log("%s的武将牌保持背面向上并跳过本回合。" % _host.format_player_state_log_name(_host.state.get_player(int(sequence.context.player_id))))


## 取消通知拥有其完整子内容；不能和phaseOver在同一个同步调用中连续派发。
func _emit_cancelled(sequence: RuleStepSequence) -> void:
	_emit(sequence, "phaseCancelled", {"reason":str(sequence.context.cancel_reason), "turn_number":_host.state.turn_number})


## 翻面跳过的完整回合通知；普通phaseBefore取消沿用既有尾部规则。
func _emit_over(sequence: RuleStepSequence) -> void:
	_emit(sequence, "phaseOver", {"reason":"face_down", "turn_number":_host.state.turn_number})


## 取消分支后继；与既有phaseBefore取消的结束阶段规则一致。
func _finish_cancelled(sequence: RuleStepSequence) -> void:
	_host._finish_turn(int(sequence.context.player_id))


## 翻面跳过后只推进回合轮转，不补造准备或结束阶段，也不派发回合尾 phaseAfter。
## 统一规则：翻面本质是跳过一整个回合，该回合没有回合开始与回合结束，因此任何“本回合结束”类清理都不得在这里发生。
func _finish_face_down(sequence: RuleStepSequence) -> void:
	_host._complete_face_down_skipped_turn(int(sequence.context.player_id))


## 回合开始全部窗口完成后才创建准备阶段实例。
func _begin_preparation(sequence: RuleStepSequence) -> void:
	if not _read_turn_window(sequence):
		return
	# 准备阶段角色；回调仅保存编号，在实际主体入口再次验证。
	var player_id: int = int(sequence.context.player_id)
	# 父回合事件；所有准备阶段窗口共享同一事件链。
	var turn_event_id: int = int(sequence.context.get("turn_event_id", -1))
	_host._record_runtime_event("phaseZhunbei", "phase", {"player_id":player_id}, {}, turn_event_id)
	_host._begin_phase_lifecycle("phaseZhunbei", player_id, {"turn_number":_host.state.turn_number}, turn_event_id, Callable(_host, "_run_preparation_phase_body").bind(player_id), Callable(_host, "_continue_turn_after_preparation_phase").bind(player_id))


## 发布保留父事件身份的通知；本服务不排序技能或管理选择令牌。
func _emit(sequence: RuleStepSequence, timing_name: String, event_data: Dictionary) -> void:
	sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), int(sequence.context.player_id), int(sequence.context.player_id), event_data, int(sequence.context.get("turn_event_id", -1))))
