extends Node

## 技能续结算运行时专项回归。验证相同上下文循环、变化上下文无限链与唯一延后唤醒。

## 异常续结算测试技能脚本；显式预加载避免新工程首次无头启动时依赖编辑器全局类缓存。
const RUNAWAY_SETTLEMENT_TEST_SKILL_SCRIPT: Script = preload("res://tests/support/runaway_settlement_test_skill.gd")

## 本测试共用的权威对局控制器；使用正式结算管线而非伪造队列实现。
var _controller: MatchController

## 当前测试技能实例；以基类持有以保持正式技能表类型，专项计数通过Object属性接口读写。
var _skill: SkillDefinition

## 控制器发出的结算故障摘要；按发生顺序保存深拷贝供断言。
var _faults: Array[Dictionary] = []


## 延后一帧运行专项断言；确保MatchController及其动态组件已完成_ready。
func _ready() -> void:
	call_deferred("_run")


## 依次验证两种异常续结算链；任一失败立即以非0退出。
func _run() -> void:
	_create_controller()
	_configure_minimal_match_state()
	if not _test_synchronous_timing_slice_ownership():
		return
	if not await _test_identical_context_loop_guard():
		return
	if not await _test_changing_context_chain_guard():
		return
	if not await _test_resume_wakeup_liveness_after_early_return():
		return
	if not _test_rule_continuation_registration_guards():
		return
	print("SKILL_SETTLEMENT_RUNTIME_PASS faults=%d" % _faults.size())
	_controller.queue_free()
	get_tree().quit(0)


## 创建与正式场景同类型的控制器和三个必需子节点；其余组件由控制器自行按需创建。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 普通规则事件总线；技能结算故障测试仍使用正式时机服务依赖。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；最小状态不注册策略，只满足控制器_ready契约。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；测试不发送网络消息，但保留正式权威端路由。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.settlement_faulted.connect(_on_settlement_faulted)


## 建立只含一名存活玩家的最小权威状态；专用test阶段使排空后不触发正常回合游标。
func _configure_minimal_match_state() -> void:
	_controller.state = GameState.new()
	_controller.state.match_id = "skill-settlement-runtime"
	_controller.state.current_phase = "test"
	_controller.state.current_player_id = 0
	# 唯一测试玩家；默认存活在场，武将代次由PlayerState初始值提供。
	var player: PlayerState = PlayerState.new(0, "结算测试玩家")
	player.identity = "leader"
	_controller.state.players.append(player)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, _controller.state)
	_controller._configure_rule_dispatch_guards()
	_skill = RUNAWAY_SETTLEMENT_TEST_SKILL_SCRIPT.new() as SkillDefinition
	_skill.bind(_controller, 0)
	# 唯一玩家的技能实例表；动态技能ID必须通过下标写入，避免字面字典把表达式当成固定键。
	var player_skills: Dictionary = {}
	player_skills[_skill.get_id()] = _skill
	_controller.skill_instances_by_player = {0:player_skills}


## 验证纯同步父规则会在返回前排空自己的时机分片，且嵌套内层完成后才恢复外层回调。
func _test_synchronous_timing_slice_ownership() -> bool:
	_controller.max_trigger_handlers_per_slice = 2
	_controller.max_settlement_steps_per_pass = 16
	_controller._configure_rule_dispatch_guards()
	# 嵌套时机实际执行顺序；内层3个处理器会跨越2个分片，但必须完整位于外层两个处理器之间。
	var order: Array[String] = []
	_controller.trigger_manager.subscribe("sync_inner", self, func(_event: RuleEvent) -> void: order.append("inner0"))
	_controller.trigger_manager.subscribe("sync_inner", self, func(_event: RuleEvent) -> void: order.append("inner1"))
	_controller.trigger_manager.subscribe("sync_inner", self, func(_event: RuleEvent) -> void: order.append("inner2"))
	_controller.trigger_manager.subscribe("sync_outer", self, func(_event: RuleEvent) -> void:
		order.append("outer0")
		# 内层同步事件；控制器封装必须在本调用返回前排空它的无选择分片。
		var inner_event: RuleEvent = RuleEvent.new("sync_inner")
		_controller._dispatch_timing_service_event(inner_event)
		order.append("outer0_after_inner")
	)
	_controller.trigger_manager.subscribe("sync_outer", self, func(_event: RuleEvent) -> void: order.append("outer1"))
	# 外层同步事件；本次调用返回时不得留下任何触发续列。
	var outer_event: RuleEvent = RuleEvent.new("sync_outer")
	_controller._dispatch_timing_service_event(outer_event)
	if order != ["outer0", "inner0", "inner1", "inner2", "outer0_after_inner", "outer1"] or _controller.trigger_manager.has_deferred_dispatches() or outer_event.status != RuleEvent.Status.FINISHED:
		return _fail("synchronous_timing_slice order=%s outer=%s deferred=%d" % [order, outer_event.to_dict(), _controller.trigger_manager.get_deferred_dispatch_count()])
	return true


## 验证同一技能以完全相同上下文无限自我入队时，在第5次登记前熔断且清空队列。
func _test_identical_context_loop_guard() -> bool:
	_controller.max_repeated_skill_settlement_steps = 4
	_controller.max_skill_settlement_chain_steps = 64
	_controller.max_settlement_steps_per_pass = 16
	_skill.set("resume_count", 0)
	_faults.clear()
	if not _skill.defer_settlement({"kind":"identical_loop"}):
		return _fail("identical_loop_initial_defer")
	# 首条登记应只建立一个延后唤醒；直接重驱管线不会叠加第二个任务。
	if not _controller._settlement_resume_scheduled:
		return _fail("identical_loop_resume_not_scheduled")
	_controller.resume_settlement_pipeline()
	# 最终故障摘要；应精确记录第5次相同上下文尝试，不应另外产生未识别上下文故障。
	var fault: Dictionary = _controller.get_last_settlement_fault()
	if int(_skill.get("resume_count")) != 4 or not _controller._deferred_skill_settlements.is_empty() or str(fault.get("reason", "")) != "skill_settlement_repeat_limit" or int(fault.get("repeat_count", -1)) != 5 or _faults.size() != 1:
		return _fail("identical_loop_guard count=%d queue=%s fault=%s signals=%s" % [int(_skill.get("resume_count")), _controller._deferred_skill_settlements, fault, _faults])
	# 等待初始登记的唯一延后任务到期；队列已空时必须无副作用地清除已调度标记。
	await get_tree().process_frame
	if _controller._settlement_resume_scheduled or int(_skill.get("resume_count")) != 4:
		return _fail("identical_loop_stale_resume scheduled=%s count=%d" % [_controller._settlement_resume_scheduled, int(_skill.get("resume_count"))])
	return true


## 验证异常技能每次改写上下文时，语义键去重之外的因果链总步数仍能在有限次数内终止。
func _test_changing_context_chain_guard() -> bool:
	_controller._reset_settlement_runtime_guard()
	_controller.max_repeated_skill_settlement_steps = 64
	_controller.max_skill_settlement_chain_steps = 4
	_controller.max_settlement_steps_per_pass = 16
	_skill.set("resume_count", 0)
	_faults.clear()
	if not _skill.defer_settlement({"kind":"changing_loop", "step":0}):
		return _fail("changing_loop_initial_defer")
	_controller.resume_settlement_pipeline()
	# 链长故障摘要；第5次尝试应在入队前被拒绝，因此技能回调仍只执行4次。
	var fault: Dictionary = _controller.get_last_settlement_fault()
	if int(_skill.get("resume_count")) != 4 or not _controller._deferred_skill_settlements.is_empty() or str(fault.get("reason", "")) != "skill_settlement_chain_limit" or int(fault.get("chain_step_count", -1)) != 5 or _faults.size() != 1:
		return _fail("changing_loop_guard count=%d queue=%s fault=%s signals=%s" % [int(_skill.get("resume_count")), _controller._deferred_skill_settlements, fault, _faults])
	await get_tree().process_frame
	if _controller._settlement_resume_scheduled or int(_skill.get("resume_count")) != 4:
		return _fail("changing_loop_stale_resume scheduled=%s count=%d" % [_controller._settlement_resume_scheduled, int(_skill.get("resume_count"))])
	return true


## 验证统一结算管线的唤醒活跃性保证：入口作废旧唤醒后，若同步排空没有消费任何待办，必须重新登记唯一唤醒。
##
## 真实危险组合是“技能在管线运行中登记“然后”步骤（此时按设计不自行登记唤醒）+ 本次同步排空提前返回”，
## 本用例用规则序列深度门控复现“提前返回且一项都没消费”这一步，从而只校验兜底本身是否生效。
func _test_resume_wakeup_liveness_after_early_return() -> bool:
	_controller._reset_settlement_runtime_guard()
	_controller.max_settlement_steps_per_pass = 16
	_skill.set("resume_count", 0)
	_faults.clear()
	# 首条登记发生在管线之外，技能因此自行登记了唯一唤醒。
	if not _skill.defer_settlement({"kind":"liveness_gate"}):
		return _fail("liveness_initial_defer")
	if not _controller._settlement_resume_scheduled:
		return _fail("liveness_initial_schedule_missing")
	# 模拟入口次序：先作废旧唤醒，再同步排空；深度门控让本次排空在消费前立即返回。
	_controller._invalidate_scheduled_settlement_resume()
	_controller._rule_sequence_execution_depth += 1
	_controller.resume_settlement_pipeline()
	_controller._rule_sequence_execution_depth -= 1
	# 队列仍有待办且当前没有任何门控在等待外部输入，因此必须重新登记唯一唤醒。
	if _controller._deferred_skill_settlements.is_empty():
		return _fail("liveness_queue_unexpectedly_drained")
	if not _controller._settlement_resume_scheduled:
		return _fail("liveness_wakeup_missing deferred=%s" % [_controller._deferred_skill_settlements])
	# 放行后唯一唤醒必须真正把队列排空，且不留下陈旧的已调度标记。
	await get_tree().process_frame
	if not _controller._deferred_skill_settlements.is_empty() or _controller._settlement_resume_scheduled:
		return _fail("liveness_not_drained deferred=%s scheduled=%s" % [_controller._deferred_skill_settlements, _controller._settlement_resume_scheduled])
	return true


## 验证通用规则续接使用独立的重复、总链与类型白名单保护，异常记录不会进入正式续接栈。
func _test_rule_continuation_registration_guards() -> bool:
	_controller._reset_settlement_runtime_guard()
	_controller.max_repeated_rule_continuation_steps = 4
	_controller.max_rule_continuation_chain_steps = 64
	_faults.clear()
	# 重复测试上下文；使用白名单内的rule_sequence类型，只验证调度元数据而不执行回合业务。
	var repeat_context: Dictionary = {"player_id":0, "cursor":"repeat"}
	# 当前重复步骤语义键；与控制器正式构造逻辑完全一致。
	var repeat_key: String = _controller._build_rule_continuation_key("rule_sequence", repeat_context)
	_controller._active_rule_continuation_key = repeat_key
	# 父续接访问表；动态键写入4表示下一次相同步骤应成为第5次并被拒绝。
	var repeat_visits: Dictionary = {}
	repeat_visits[repeat_key] = 4
	_controller._active_rule_continuation_visits = repeat_visits
	_controller._active_rule_continuation_chain_steps = 4
	# 重复保护返回值；负数表示异常步骤未进入续接栈。
	var repeated_continuation_id: int = _controller._defer_rule_continuation("rule_sequence", repeat_context)
	# 重复保护故障摘要；必须精确记录第5次尝试。
	var repeat_fault: Dictionary = _controller.get_last_settlement_fault()
	if repeated_continuation_id >= 0 or _controller._rule_continuations.has_pending() or str(repeat_fault.get("reason", "")) != "rule_continuation_repeat_limit" or int(repeat_fault.get("repeat_count", -1)) != 5 or _faults.size() != 1:
		return _fail("rule_continuation_repeat_guard id=%d queue=%s fault=%s signals=%s" % [repeated_continuation_id, _controller._rule_continuations.to_array(), repeat_fault, _faults])

	_controller._reset_settlement_runtime_guard()
	_controller.max_repeated_rule_continuation_steps = 64
	_controller.max_rule_continuation_chain_steps = 4
	_faults.clear()
	_controller._active_rule_continuation_key = "parent_continuation"
	# 父续接访问表；只需保持非空父键，变化上下文应由总链步数而非重复键终止。
	var chain_visits: Dictionary = {"parent_continuation":1}
	_controller._active_rule_continuation_visits = chain_visits
	_controller._active_rule_continuation_chain_steps = 4
	# 变化上下文续接ID；第5步超过测试配置的4步总链上限。
	var chained_continuation_id: int = _controller._defer_rule_continuation("rule_sequence", {"player_id":0, "cursor":"changed"})
	# 总链保护故障摘要；异常步骤同样不能进入队列。
	var chain_fault: Dictionary = _controller.get_last_settlement_fault()
	if chained_continuation_id >= 0 or _controller._rule_continuations.has_pending() or str(chain_fault.get("reason", "")) != "rule_continuation_chain_limit" or int(chain_fault.get("chain_step_count", -1)) != 5 or _faults.size() != 1:
		return _fail("rule_continuation_chain_guard id=%d queue=%s fault=%s signals=%s" % [chained_continuation_id, _controller._rule_continuations.to_array(), chain_fault, _faults])

	_controller._reset_settlement_runtime_guard()
	_faults.clear()
	# 未登记类型续接ID；白名单应在写入队列前直接拒绝。
	var unknown_continuation_id: int = _controller._defer_rule_continuation("unknown_test_continuation", {})
	# 类型保护故障摘要；用于确认拒绝原因没有被重复或链长诊断覆盖。
	var unknown_fault: Dictionary = _controller.get_last_settlement_fault()
	if unknown_continuation_id >= 0 or _controller._rule_continuations.has_pending() or str(unknown_fault.get("reason", "")) != "unknown_rule_continuation_type" or _faults.size() != 1:
		return _fail("rule_continuation_type_guard id=%d queue=%s fault=%s signals=%s" % [unknown_continuation_id, _controller._rule_continuations.to_array(), unknown_fault, _faults])
	return true


## 收集一条结算故障信号；深复制保证后续日志或控制器改动不影响已收集断言。
func _on_settlement_faulted(fault_data: Dictionary) -> void:
	_faults.append(fault_data.duplicate(true))


## 输出失败原因并以非0状态结束场景；返回false便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	printerr("SKILL_SETTLEMENT_RUNTIME_FAIL %s" % reason)
	get_tree().quit(1)
	return false
