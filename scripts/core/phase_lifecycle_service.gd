extends RefCounted

## 标准阶段生命周期编排；Before、Begin、主体入口、End、After都通过既有规则步骤等待。

## 权威宿主；仅调用已有阶段、状态和触发接口，不创建另一套时钟。
var _host: Object

## 开始成功或结束完成后执行的回调；仅保存在本局服务中，不进入网络或存档。
var _on_completed: Callable

## 前置窗口取消后的后继；取消通知结算完成后才调用。
var _on_cancelled: Callable


## 注入权威控制器；服务随所属步骤结束释放。
func _init(host: Object) -> void:
	_host = host


## 创建唯一阶段实例；返回值表示请求被受理，异步取消结果与主体开放必须通过后继回调接收。
func begin(base_name: String, player_id: int, event_data: Dictionary, parent_event_id: int, on_started: Callable, on_cancelled: Callable, instance_scope: String = "", source_id: int = -1) -> bool:
	_on_completed = on_started
	_on_cancelled = on_cancelled
	# 活动生命周期键；实例ID防止旧窗口恢复后覆盖同名新阶段。
	var lifecycle_key: String = "%d:%s%s" % [player_id, base_name, instance_scope]
	# 阶段实例；下一序列ID单调递增，即使重开也不会复用旧身份。
	var lifecycle_context: Dictionary = {"status":"starting", "event_data":event_data.duplicate(true), "parent_event_id":parent_event_id, "lifecycle_id":int(_host._next_rule_sequence_id), "lifecycle_key":lifecycle_key, "source_id":player_id if source_id < 0 else source_id}
	_host._started_phase_lifecycles[lifecycle_key] = lifecycle_context
	# 内容上下文；回调单独保留在服务中，context仅包含可序列化规则数据。
	var context: Dictionary = _context(base_name, player_id, lifecycle_context)
	# 标准前置步骤；读取前一窗口最终结果后才能发布下一窗口。
	var steps: Array[Callable] = [_emit_begin_window.bind("Before"), _emit_begin_window.bind("Begin"), _complete_begin, _invoke_begin_callback]
	_host.run_rule_sequence(steps, context)
	# 同步主体可能已经完成整个阶段；ending同样说明请求已受理，不能误报启动失败。
	return str(lifecycle_context.get("status", "")) != "cancelled"


## 结束成功进入的阶段；重复调用只观察同一个ending状态，不再重复派发结束窗口。
func complete(base_name: String, player_id: int, event_data: Dictionary, parent_event_id: int, on_completed: Callable, instance_scope: String = "") -> void:
	_on_completed = on_completed
	# 活动生命周期键；取消或跳过的阶段没有收尾窗口。
	var lifecycle_key: String = "%d:%s%s" % [player_id, base_name, instance_scope]
	# 原生命周期记录；旧布尔记录仅用于兼容已经保存的测试状态。
	var lifecycle_variant: Variant = _host._started_phase_lifecycles.get(lifecycle_key, {})
	# 实际字典；没有记录时只调用已确认的后继，不能补造Begin或End。
	var lifecycle_context: Dictionary = lifecycle_variant as Dictionary if lifecycle_variant is Dictionary else {"status":"body", "event_data":event_data.duplicate(true), "parent_event_id":parent_event_id}
	if lifecycle_context.is_empty():
		if _on_completed.is_valid():
			_on_completed.call()
		return
	if str(lifecycle_context.get("status", "body")) != "body":
		return
	lifecycle_context["status"] = "ending"
	lifecycle_context["lifecycle_id"] = int(_host._next_rule_sequence_id)
	lifecycle_context["event_data"] = (lifecycle_context.get("event_data", {}) as Dictionary).duplicate(true)
	lifecycle_context.event_data.merge(event_data, true)
	_host._started_phase_lifecycles[lifecycle_key] = lifecycle_context
	# 完成步骤；End全部子流程结束后才进入After，最后一次性移除生命周期。
	var steps: Array[Callable] = [_emit_end_window.bind("End"), _emit_end_window.bind("After"), _complete_end]
	_host.run_rule_sequence(steps, _context(base_name, player_id, lifecycle_context))


## 生成稳定阶段身份；同一玩家的同名新阶段不能继承旧选择的恢复回调。
func _context(base_name: String, player_id: int, lifecycle_context: Dictionary) -> Dictionary:
	return {"base_name":base_name, "player_id":player_id, "lifecycle_key":str(lifecycle_context.get("lifecycle_key", "%d:%s" % [player_id, base_name])), "source_id":int(lifecycle_context.get("source_id", player_id)), "lifecycle_id":int(lifecycle_context.get("lifecycle_id", -1)), "event_data":(lifecycle_context.get("event_data", {}) as Dictionary).duplicate(true), "parent_event_id":int(lifecycle_context.get("parent_event_id", -1)), "cancelled":false}


## 只由仍拥有当前记录的序列推进；跳过、重开或替换阶段会撤销旧所有权。
func _owns_lifecycle(sequence: RuleStepSequence) -> bool:
	# 当前登记记录；实例不一致时旧内容局部结束。
	var lifecycle_context: Dictionary = _host._started_phase_lifecycles.get(str(sequence.context.lifecycle_key), {}) as Dictionary
	if int(lifecycle_context.get("lifecycle_id", -2)) != int(sequence.context.lifecycle_id):
		sequence.finish()
		return false
	return true


## 读取原事件的最终可修改字段；取消只影响前置窗口，完成窗口只报告已经成立的事实。
func _read_window(sequence: RuleStepSequence, allow_cancel: bool) -> void:
	if sequence.waiting_event == null:
		return
	sequence.context["event_data"] = sequence.waiting_event.data.duplicate(true)
	if allow_cancel and (sequence.waiting_event.cancelled or sequence.waiting_event.neutralized):
		sequence.context["cancelled"] = true
	sequence.waiting_event = null


## 前置窗口取消后不再发布下一个前置窗口；选择结果由下一步骤统一回读。
func _emit_begin_window(sequence: RuleStepSequence, suffix: String) -> void:
	if not _owns_lifecycle(sequence):
		return
	_read_window(sequence, true)
	if not bool(sequence.context.cancelled):
		_emit(sequence, suffix)


## Before和Begin全部完成后才开放阶段主体；取消通知本身也支持子技能与选择。
func _complete_begin(sequence: RuleStepSequence) -> void:
	if not _owns_lifecycle(sequence):
		return
	_read_window(sequence, true)
	if bool(sequence.context.cancelled):
		_host._started_phase_lifecycles[str(sequence.context.lifecycle_key)]["status"] = "cancelled"
		_host._started_phase_lifecycles.erase(str(sequence.context.lifecycle_key))
		_emit(sequence, "Cancelled")
		return
	# 活动生命周期上下文；status=body表示Before与Begin已经完成，阶段主体尚可执行。
	var lifecycle_context: Dictionary = _host._started_phase_lifecycles[str(sequence.context.lifecycle_key)] as Dictionary
	lifecycle_context["status"] = "body"
	lifecycle_context["event_data"] = (sequence.context.event_data as Dictionary).duplicate(true)
	_host.log_phase_begin(str(sequence.context.base_name), bool(sequence.context.event_data.get("extra_phase", false)))


## 开始后继只执行一次；旧同步bool接口仍可用于无需等待的查询和兼容测试。
func _invoke_begin_callback(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.cancelled):
		if _on_cancelled.is_valid():
			_on_cancelled.call()
	elif _owns_lifecycle(sequence) and _on_completed.is_valid():
		_on_completed.call()


## 结束窗口保留最终扩展数据；一个窗口的所有技能完成后才能发布下一个。
func _emit_end_window(sequence: RuleStepSequence, suffix: String) -> void:
	if not _owns_lifecycle(sequence):
		return
	_read_window(sequence, false)
	_emit(sequence, suffix)


## 移除实例后再调用后继，重复恢复不能再结束相同阶段。
func _complete_end(sequence: RuleStepSequence) -> void:
	if not _owns_lifecycle(sequence):
		return
	_read_window(sequence, false)
	_host._started_phase_lifecycles.erase(str(sequence.context.lifecycle_key))
	_host.log_phase_end(str(sequence.context.base_name), bool(sequence.context.event_data.get("extra_phase", false)))
	if _on_completed.is_valid():
		_on_completed.call()


## 目录是合法时机的唯一来源；每个窗口保留其原始事件，交给统一管线判断完成。
func _emit(sequence: RuleStepSequence, suffix: String) -> void:
	# 完整时机名；缺少对应窗口时不自行造名。
	var timing_name: String = "%s%s" % [str(sequence.context.base_name), suffix]
	if RuleTimingCatalog.has_timing(timing_name):
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), int(sequence.context.source_id), int(sequence.context.player_id), sequence.context.event_data, int(sequence.context.parent_event_id)))


## 摸牌数量窗口继承Before和Begin最终数据；各窗口修改完成后才执行唯一一次摸牌。
func draw_phase(player_id: int, on_completed: Callable) -> void:
	_on_completed = on_completed
	# 当前阶段记录；旧恢复入口重复调用时不再启动第二条摸牌序列。
	var lifecycle_context: Dictionary = _host._started_phase_lifecycles.get("%d:phaseDraw" % player_id, {}) as Dictionary
	if str(lifecycle_context.get("status", "")) != "body" or bool(lifecycle_context.get("body_started", false)):
		return
	lifecycle_context["body_started"] = true
	# 摸牌内容步骤；前置取消表示本次摸牌数量为0，仍正常结束已进入的阶段。
	var steps: Array[Callable] = [_emit_begin_window.bind("Begin1"), _emit_begin_window.bind("Begin2"), _commit_draw, _complete_draw]
	_host.run_rule_sequence(steps, _context("phaseDraw", player_id, lifecycle_context))


## 扣除窗口取消并钳制非负数量；主体完成标记与真实摸牌只写入一次。
func _commit_draw(sequence: RuleStepSequence) -> void:
	if not _owns_lifecycle(sequence):
		return
	_read_window(sequence, true)
	# 最终摸牌数量；正式基础值来自阶段上下文，取消仅将本次数量降为0。
	var draw_count: int = 0 if bool(sequence.context.cancelled) else maxi(int(sequence.context.event_data.get("draw_count", 0)), 0)
	sequence.context.event_data["draw_count"] = draw_count
	# 当前记录；阶段主体开始后不得再次按公开阶段重建摸牌操作。
	var lifecycle_context: Dictionary = _host._started_phase_lifecycles[str(sequence.context.lifecycle_key)] as Dictionary
	lifecycle_context["body_complete"] = true
	lifecycle_context["resolved_draw_count"] = draw_count
	lifecycle_context["event_data"] = (sequence.context.event_data as Dictionary).duplicate(true)
	_host.draw(int(sequence.context.player_id), draw_count)


## 摸牌产生的获得牌技能完成后才关闭阶段；结束回调沿用显式后继。
func _complete_draw(sequence: RuleStepSequence) -> void:
	if _owns_lifecycle(sequence):
		_host._finish_phase_lifecycle("phaseDraw", int(sequence.context.player_id), sequence.context.event_data, int(sequence.context.parent_event_id), _on_completed)
