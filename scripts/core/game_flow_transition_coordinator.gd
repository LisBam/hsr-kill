class_name GameFlowTransitionCoordinator
extends Node

## 阶段转换协调组件。它只管理“当前唯一有效的阶段切换意图”，不读取或修改GameState，也不执行任何玩法规则。
## MatchController为每次转换提供即时/到期校验器；迟到恢复、重复回调和旧对局任务因此不能覆盖仍有效的阶段推进。

## 阶段转换在流程节奏组件中使用的唯一业务键；其他技能与响应任务继续使用各自独立键。
const PHASE_TRANSITION_TASK_KEY: String = "phase_transition"

## 有效阶段转换完成登记时发送；参数不包含Callable，可供调试器与回归测试安全读取。
signal transition_scheduled(transition_data: Dictionary)

## 无效、重复或冲突转换被拒绝时发送；拒绝只保护现有流程，不直接修改游戏状态。
signal transition_rejected(rejection_data: Dictionary)

## 转换计时到期且上下文仍有效时发送；信号先于业务回调发出，便于诊断实际执行顺序。
signal transition_executed(transition_data: Dictionary)

## 被协调的流程节奏组件；由控制器在装配阶段注入，未绑定时仅允许同步零延时回退。
var _game_flow_pacer: GameFlowPacer = null

## 当前待执行转换的运行时记录；包含校验与业务Callable，公开快照会主动剔除这些不可序列化字段。
var _pending_transition: Dictionary = {}

## 下一条转换的稳定序号；从1开始，旧计时回调通过序号无法接管新意图。
var _next_transition_id: int = 1

## 本次绑定期间累计拒绝数量；用于诊断迟到恢复是否频繁发生，不参与玩法结果。
var _rejected_transition_count: int = 0


## 绑定流程节奏组件；重新绑定前会取消旧组件中的阶段任务，防止场景重组遗留回调。
func bind(game_flow_pacer: GameFlowPacer) -> void:
	if _game_flow_pacer != null and _game_flow_pacer != game_flow_pacer:
		_game_flow_pacer.cancel(PHASE_TRANSITION_TASK_KEY)
	_game_flow_pacer = game_flow_pacer
	_pending_transition.clear()
	_next_transition_id = 1
	_rejected_transition_count = 0


## 登记一次阶段转换；只有登记时上下文有效且没有另一条仍有效转换时才会占用唯一阶段任务。
## transition_key由对局、回合、角色、阶段与回调名组成，仅用于幂等诊断；validity_guard在登记与到期时都会执行。
func schedule_transition(transition_key: String, delay_seconds: float, validity_guard: Callable, callback: Callable) -> bool:
	if transition_key.is_empty() or not validity_guard.is_valid() or not callback.is_valid():
		_reject_transition("invalid_transition_request", transition_key)
		return false
	# 节奏任务可能被对局清理入口直接取消；若业务键已不存在，同步清除协调器中的旧元数据。
	_discard_missing_pacer_task()
	if not bool(validity_guard.call()):
		_reject_transition("stale_transition_context", transition_key)
		return false
	if not _pending_transition.is_empty():
		# 现有转换校验器；仍有效时必须保留最早已经承诺的推进，后来的重复恢复不能以同键覆盖它。
		var pending_guard: Callable = _pending_transition.get("validity_guard", Callable())
		if pending_guard.is_valid() and bool(pending_guard.call()):
			# 现有转换语义键；用于区分完全重复恢复与同一阶段的不同出口争用。
			var pending_key: String = str(_pending_transition.get("transition_key", ""))
			_reject_transition("duplicate_transition" if pending_key == transition_key else "conflicting_transition", transition_key, pending_key)
			return pending_key == transition_key
		_cancel_pending_transition("stale_pending_transition")
	# 当前转换序号；登记后立即递增，后续任务永远不会复用同一个ID。
	var transition_id: int = _next_transition_id
	_next_transition_id += 1
	_pending_transition = {
		"transition_id": transition_id,
		"transition_key": transition_key,
		"validity_guard": validity_guard,
		"callback": callback,
	}
	# 新登记转换的纯数据摘要；信号订阅者不会获得内部校验器或业务回调。
	var transition_snapshot: Dictionary = _build_pending_snapshot()
	transition_scheduled.emit(transition_snapshot.duplicate(true))
	if _game_flow_pacer == null or delay_seconds <= 0.0:
		_execute_transition(transition_id)
		return true
	# 延时回调只携带稳定ID；具体Callable保留在当前唯一记录中，不进入计时器业务键或状态快照。
	_game_flow_pacer.schedule(PHASE_TRANSITION_TASK_KEY, delay_seconds, Callable(self, "_execute_transition").bind(transition_id))
	return true


## 取消当前阶段转换并清空运行时Callable；重新开局、失败开局和终局清理共用本入口。
func cancel_pending(reason: String = "cancelled") -> void:
	_cancel_pending_transition(reason)


## 返回当前是否存在节奏任务与协调元数据一致的待执行转换；缺失的外部任务会在查询时自动清理。
func has_pending() -> bool:
	_discard_missing_pacer_task()
	return not _pending_transition.is_empty()


## 返回不含Callable的当前转换摘要；界面、看门狗和测试只能观察稳定ID与语义键。
func get_pending_snapshot() -> Dictionary:
	_discard_missing_pacer_task()
	return _build_pending_snapshot()


## 返回累计拒绝数量；数值只用于诊断和回归测试，重新绑定时归零。
func get_rejected_transition_count() -> int:
	return _rejected_transition_count


## 执行仍为当前版本且到期校验通过的转换；先清空待办再调用业务逻辑，业务回调可安全登记下一阶段。
func _execute_transition(transition_id: int) -> void:
	if int(_pending_transition.get("transition_id", -1)) != transition_id:
		return
	# 当前转换运行时记录；先保存局部引用再清空共享状态，避免业务回调重入时覆盖新登记。
	var transition: Dictionary = _pending_transition
	# 当前转换纯数据摘要；清空共享状态前生成，确保信号仍能报告准确ID与语义键。
	var transition_snapshot: Dictionary = _build_pending_snapshot()
	_pending_transition = {}
	# 到期上下文校验器；失效时只拒绝旧转换，不执行任何玩法回调。
	var validity_guard: Callable = transition.get("validity_guard", Callable())
	if not validity_guard.is_valid() or not bool(validity_guard.call()):
		_reject_transition("expired_transition_context", str(transition.get("transition_key", "")))
		return
	transition_executed.emit(transition_snapshot.duplicate(true))
	# 阶段业务回调；协调状态已先清空，因此回调可以安全登记下一阶段转换。
	var callback: Callable = transition.get("callback", Callable())
	if callback.is_valid():
		callback.call()


## 当流程节奏组件已没有阶段业务键时清除残留元数据；这兼容旧调用方直接执行GameFlowPacer.cancel_all()的清理方式。
func _discard_missing_pacer_task() -> void:
	if _pending_transition.is_empty() or _game_flow_pacer == null:
		return
	if not _game_flow_pacer.has_pending(PHASE_TRANSITION_TASK_KEY):
		_pending_transition.clear()


## 取消当前转换的节奏任务并释放Callable；reason只进入拒绝诊断，不影响任何玩法状态。
func _cancel_pending_transition(reason: String) -> void:
	if _pending_transition.is_empty():
		if _game_flow_pacer != null:
			_game_flow_pacer.cancel(PHASE_TRANSITION_TASK_KEY)
		return
	var cancelled_key: String = str(_pending_transition.get("transition_key", ""))
	if _game_flow_pacer != null:
		_game_flow_pacer.cancel(PHASE_TRANSITION_TASK_KEY)
	_pending_transition.clear()
	if not reason.is_empty() and reason != "cancelled":
		_reject_transition(reason, cancelled_key)


## 记录一次被拒绝的转换；现有转换键帮助诊断是重复恢复还是不同分支争用同一阶段出口。
func _reject_transition(reason: String, transition_key: String, existing_transition_key: String = "") -> void:
	_rejected_transition_count += 1
	transition_rejected.emit({
		"reason": reason,
		"transition_key": transition_key,
		"existing_transition_key": existing_transition_key,
		"rejected_count": _rejected_transition_count,
	})


## 构造当前待办的纯数据摘要；空待办返回空字典，Callable永远不会离开组件边界。
func _build_pending_snapshot() -> Dictionary:
	if _pending_transition.is_empty():
		return {}
	return {
		"transition_id": int(_pending_transition.get("transition_id", -1)),
		"transition_key": str(_pending_transition.get("transition_key", "")),
	}
