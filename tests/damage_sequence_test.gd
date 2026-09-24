extends Node

## 可暂停伤害与步骤内容专项回归；每个用例重建权威状态，不依赖看门狗自动纠错。

## 当前被测控制器；每个场景替换一次，避免旧触发器污染新用例。
var _controller: MatchController

## 正在等待选择的原修改窗口；测试模拟技能在应答后修改或取消该事件。
var _paused_event: RuleEvent

## 所有断言的失败状态；任何失败都以非零退出，成功信息仅在全部完成后打印。
var _failed: bool = false


## 延迟启动以完成自动加载初始化。
func _ready() -> void:
	call_deferred("_run")


## 覆盖全部前置窗口、护盾、提交后窗口、嵌套顺序及通用内容结果传递。
func _run() -> void:
	# 前置时机名；每个窗口都必须在修改提交之前完成本时机其余处理器。
	for timing_name: String in ["damageBefore", "damageBegin", "damageBegin1", "damageBegin2", "damageBegin3", "damageBegin4", "damage_before"]:
		_reset_controller()
		_controller.trigger_manager.subscribe(timing_name, self, _pause_window, 10)
		_controller.trigger_manager.subscribe(timing_name, self, func(event: RuleEvent) -> void: event.data["amount"] = int(event.data.get("amount", 0)) + 1)
		_controller.damage(0, 1, 1)
		_check(_controller.has_pending_card_choice() and _controller.state.get_player(1).hp == 20, timing_name + " applied before choice")
		_paused_event.data["amount"] = 2
		_submit_choice()
		_check(_controller.state.get_player(1).hp == 17 and _controller.state.get_player(1).damage_taken_count == 1, timing_name + " lost final modification or repeated damage")
		_check_clean(timing_name)
	_test_cancelled_damage()
	_test_shield_and_result_windows()
	_test_nested_damage_order()
	_test_sequence_choice_result()
	_test_changed_target_generation()
	_test_judgment_parent_wait()
	await _test_sequence_frame_budget()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("DAMAGE_SEQUENCE_PASS windows=7 cancellation shield result nested choice generation judgment frame_budget")
	get_tree().quit(1 if _failed else 0)


## 创建最小正式依赖；非出牌测试阶段避免用例结束后自动建立chooseToUse。
func _reset_controller() -> void:
	if _controller != null:
		_controller.free()
	_controller = MatchController.new()
	# 总线；沿用正式规则订阅入口。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI组件；不注册策略，以真人请求稳定制造异步边界。
	var coordinator: AICoordinator = AICoordinator.new()
	coordinator.name = "AICoordinator"
	_controller.add_child(coordinator)
	# 通信组件；离线模式仍使用统一动作校验。
	var gateway: NetworkGateway = NetworkGateway.new()
	gateway.name = "NetworkGateway"
	_controller.add_child(gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.state = GameState.new()
	_controller.state.match_id = "damage-sequence-test"
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "test"
	# 测试角色；20点体力隔离濒死规则，各用例只测时序与所有权。
	for player_id: int in range(3):
		# 当前角色；稳定身份与正常武将代次用于换将保护断言。
		var player: PlayerState = PlayerState.new(player_id, "测试%d" % player_id)
		player.hp = 20
		player.max_hp = 20
		player.identity = ["leader", "rebel", "loyalist"][player_id]
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller._ensure_timing_service()
	# 长期根；可供选择事件挂接，仍保持整个事件树受同一调度器管理。
	var root: GameEvent = _controller.event_scheduler.create_event("test_root")
	_controller.event_scheduler.begin_root(root.event_id)
	_controller._runtime_root_event_id = root.event_id
	_paused_event = null


## 在任意规则窗口创建真人选择；保存原RuleEvent供测试验证异步回写而不是局部副本。
func _pause_window(event: RuleEvent) -> void:
	_paused_event = event
	_controller.request_target_choice(0, "暂停窗口", [0], 0, 1, true, {"kind":"test_window", "test_timing_name":event.name})


## 通过正式动作接口结束当前选择，不直接释放暂停令牌。
func _submit_choice(target_ids: Array[int] = []) -> void:
	# 当前权威请求副本；提交稳定请求ID，确保测试同时覆盖旧响应保护。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	_check(not request.is_empty(), "missing choice before submit")
	if request.is_empty():
		return
	# 合法选择动作；零目标表示明确放弃可选步骤，指定目标时表示确认。
	var action: PlayerAction = PlayerAction.new("choose_cards", int(request.get("chooser_id", 0)))
	action.payload = {"request_id":request.get("request_id", -1), "selected_card_uids":[], "selected_target_ids":target_ids, "confirmed":not target_ids.is_empty()}
	_check(_controller._submit_card_choice(action), "choice rejected")
	_controller._resume_settlement_pipeline()


## 修改窗口取消必须阻止扣血，取消通知只发出一次。
func _test_cancelled_damage() -> void:
	_reset_controller()
	# 取消事实次数；共享数组用于纯回调计数。
	var cancelled_count: Array[int] = [0]
	_controller.trigger_manager.subscribe("damageBegin3", self, _pause_window)
	_controller.event_bus.subscribe("damageCancelled", self, func(_event: RuleEvent) -> void: cancelled_count[0] += 1)
	_controller.damage(0, 1, 3)
	_paused_event.cancel("test_cancel")
	_submit_choice()
	_check(_controller.state.get_player(1).hp == 20 and cancelled_count[0] == 1, "cancel applied damage or repeated cancellation")
	_check_clean("cancel")


## 护盾前窗口与提交后各窗口均可等待；已提交体力不重复扣减，后续时机不能抢跑。
func _test_shield_and_result_windows() -> void:
	# 待验证窗口；护盾减少前与三个结果边界分别独立暂停一次。
	for timing_name: String in ["changeHujiaBefore", "changeHujiaAfter", "changeHp", "damage"]:
		_reset_controller()
		_controller.state.get_player(1).shield = 1
		_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
		# 伤害尾部次数；窗口等待时不得已经发布damageAfter。
		var after_count: Array[int] = [0]
		_controller.event_bus.subscribe("damageAfter", self, func(_event: RuleEvent) -> void: after_count[0] += 1)
		_controller.damage(0, 1, 3)
		_check(after_count[0] == 0, timing_name + " skipped child wait")
		if timing_name == "changeHujiaBefore":
			_check(_controller.state.get_player(1).hp == 20 and _controller.state.get_player(1).shield == 1, "shield committed before choice")
		_submit_choice()
		_check(_controller.state.get_player(1).hp == 18 and _controller.state.get_player(1).shield == 0 and after_count[0] == 1, timing_name + " incorrect result")
		_check_clean(timing_name)


## 一个外层时机处理器造成异步伤害后，另一个外层处理器必须看到已经完成的子伤害。
func _test_nested_damage_order() -> void:
	_reset_controller()
	# 外层观察结果；正确值19表示完整子伤害先于外层下一处理器。
	var observed_hp: Array[int] = []
	_controller.trigger_manager.subscribe("damageBegin4", self, _pause_window)
	_controller.trigger_manager.subscribe("test_outer", self, func(_event: RuleEvent) -> void: _controller.damage(0, 1, 1), 10)
	_controller.trigger_manager.subscribe("test_outer", self, func(_event: RuleEvent) -> void: observed_hp.append(_controller.state.get_player(1).hp))
	_controller.emit_rule_timing("test_outer", 0, 0, 1)
	_submit_choice()
	_check(observed_hp == [19], "outer handlers resumed before child damage")
	_check_clean("nested")


## 通用步骤选择把应答写入所属内容；费用步骤只执行一次，取消与确认均不重复进入第一步。
func _test_sequence_choice_result() -> void:
	_reset_controller()
	# 执行记录；每条代表一个内容步骤，不允许因恢复重复追加。
	var order: Array[String] = []
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void:
			order.append("choose")
			_controller.request_target_choice(0, "sequence", [1], 1, 1, true, {"kind":"test_sequence", "rule_sequence_id":sequence.sequence_id}),
		func(sequence: RuleStepSequence) -> void:
			_check(sequence.choice_response != null and sequence.choice_response.target_ids == [1], "sequence lost choice result")
			order.append("apply"),
	])
	_check(order == ["choose"], "sequence skipped choice")
	_submit_choice([1])
	_check(order == ["choose", "apply"], "sequence repeated step")
	_check_clean("sequence choice")


## 伤害等待期间同座次换将，不得把旧伤害施加到新实例。
func _test_changed_target_generation() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("damageBegin1", self, _pause_window)
	_controller.damage(0, 1, 2)
	_controller.state.get_player(1).character_generation += 1
	_submit_choice()
	_check(_controller.state.get_player(1).hp == 20, "old damage hits new character")
	_check_clean("generation")


## 每条规则结束必须释放所有局部等待，不允许依靠后续动作或看门狗清理。
func _check_clean(label: String) -> void:
	_check(not _controller.has_pending_card_choice() and _controller._rule_sequences.is_empty() and not _controller._rule_continuations.has_pending() and not _controller.trigger_manager.has_deferred_dispatches(), label + " leaves pending work")
	_check(_controller.get_settlement_fault_count() == 0, label + " relies on fault guard: " + str(_controller.get_last_settlement_fault()))


## 聚合断言失败；保持原始状态供日志观察。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("DAMAGE_SEQUENCE_FAIL: " + message)


## 判定前技能是判定的子流程；不能误把创建序列时已经存在的判定当作新子判定来等待。
func _test_judgment_parent_wait() -> void:
	_reset_controller()
	# 原始底部红牌；选择后交换顺序，应成为最终判定牌。
	var red_card: CardInstance = CardInstance.new("tao", "heart", 6)
	# 初始牌堆顶黑牌；若父判定越过技能后续就会错误使用这一张。
	var black_card: CardInstance = CardInstance.new("shan", "spade", 8)
	_controller.state.draw_pile.assign([red_card, black_card])
	_controller.trigger_manager.subscribe("judgeBefore", self, func(_event: RuleEvent) -> void:
		_controller.run_rule_sequence([
			func(sequence: RuleStepSequence) -> void: _controller.request_target_choice(0, "改判定", [0], 0, 1, true, {"rule_sequence_id":sequence.sequence_id}),
			func(_sequence: RuleStepSequence) -> void: _controller.state.draw_pile.reverse(),
		])
	)
	_controller.request_judgment(0, "sequence_test")
	_check(_controller.has_pending_card_choice() and _controller.has_pending_judgment_request(), "judgment did not wait for sequence")
	_submit_choice()
	_check(_controller.state.discard_pile.has(red_card) and not _controller.has_pending_judgment_request(), "parent judgment skipped sequence result")
	_check_clean("judgment parent")


## 长步骤内容必须在真实进程帧间分批运行，保持确定顺序而不触发保护或丢失内容。
func _test_sequence_frame_budget() -> void:
	_reset_controller()
	_controller.max_settlement_steps_per_pass = 2
	# 各步骤实际执行帧；用不同帧号证明协作式让步，不以恢复回调次数代替。
	var frames: Array[int] = []
	# 有限步骤列表；12步在测试预算2下必须跨多帧完成。
	var steps: Array[Callable] = []
	# 内容步骤索引；这里只构造12个有限回调，具体断言使用实际执行帧。
	for step_index: int in range(12):
		steps.append(func(_sequence: RuleStepSequence) -> void: frames.append(Engine.get_process_frames()))
	_controller.run_rule_sequence(steps)
	# 等待帧索引；最多20帧，超出预算仍未排空时直接判为失败。
	for frame_index: int in range(20):
		if _controller._rule_sequences.is_empty():
			break
		await get_tree().process_frame
	_check(frames.size() == 12 and frames.front() != frames.back(), "sequence budget did not yield or finish")
	_check_clean("sequence frame budget")
