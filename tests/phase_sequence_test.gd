extends "res://tests/damage_sequence_test.gd"

## 阶段窗口专项测试；隔离阶段间计时和下一回合，只验证正式规则时序与状态提交。

## 隔离节奏出口的权威控制器；记录后继而不自动开启下一阶段。
class PhaseController extends MatchController:
	## 最后登记的后继方法；空值表示当前阶段尚未完整结束。
	var next_phase_method: String = ""
	## 出牌入口次数；只计数，不创建与本测试无关的操作根。
	var play_body_count: int = 0

	## 阶段后继必须在所有窗口完成后才到达此出口。
	func _schedule_phase_transition(_player_id: int, _expected_phase: String, callback: Callable) -> void:
		next_phase_method = str(callback.get_method())

	## 记录主体开放次数，检验Begin暂停时不能提前开放操作。
	func _begin_play_choice(_player_id: int) -> void:
		# 已有正式请求时重复恢复应幂等；仅计入真实新建的操作窗口。
		var had_choice: bool = _has_active_play_choice()
		super._begin_play_choice(_player_id)
		if not had_choice and _has_active_play_choice():
			play_body_count += 1


## 工厂只替换流程展示与输入出口，触发、规则序列和生命期逻辑均执行正式代码。
func _create_controller() -> MatchController:
	return PhaseController.new()


## 所有失败聚合为非零退出；没有看门狗替测试推进状态。
func _run() -> void:
	_test_lifecycle_cancellation()
	_test_draw_windows()
	_test_finish_windows()
	_test_phase_change()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("PHASE_SEQUENCE_PASS lifecycle_cancel draw_windows finish_windows phase_change")
	get_tree().quit(1 if _failed else 0)


## 六阶段的Before和Begin异步取消均不得开放主体，也不得伪造End或After。
func _test_lifecycle_cancellation() -> void:
	# 标准六阶段前缀；每个都有独立的取消范围。
	for base_name: String in ["phaseZhunbei", "phaseJudge", "phaseDraw", "phaseUse", "phaseDiscard", "phaseJieshu"]:
		# 两个可取消入口；每次重建控制器避免订阅污染。
		for suffix: String in ["Before", "Begin"]:
			_reset_controller()
			# 主体和取消后继次数；取消窗口的所有子内容结束后才允许调用后继。
			var calls: Array[int] = [0, 0]
			_controller.trigger_manager.subscribe(base_name + suffix, self, _pause_window)
			_controller._begin_phase_lifecycle(base_name, 0, {"turn_number":1}, -1, func() -> void: calls[0] += 1, func() -> void: calls[1] += 1)
			_check(_controller.has_pending_card_choice() and calls == [0, 0], base_name + suffix + " opened body early")
			_paused_event.cancel("phase_test_cancel")
			_submit_choice()
			_check(calls == [0, 1] and _controller._started_phase_lifecycles.is_empty(), base_name + suffix + " lost cancellation")
			_check_clean(base_name + suffix)


## 摸牌阶段每个窗口可插入选择；前置修改最终生效，结束窗口不会再次摸牌。
func _test_draw_windows() -> void:
	# 数量窗口和完成窗口；同样的异步边界在每个位置分别测试。
	for timing: String in ["phaseDrawBefore", "phaseDrawBegin", "phaseDrawBegin1", "phaseDrawBegin2", "phaseDrawEnd", "phaseDrawAfter"]:
		_reset_controller()
		# 足量牌堆；10仅为夹具，避免补牌逻辑影响计数。
		for card_index: int in range(10):
			_controller.state.draw_pile.append(CardInstance.new("shan", "heart", card_index + 1))
		_controller.trigger_manager.subscribe(timing, self, _pause_window)
		_controller._enter_draw_phase(0)
		_check(_controller.has_pending_card_choice() and (_controller as PhaseController).next_phase_method.is_empty(), timing + " advanced early")
		# 前置窗口中的修改应在应答后回读；完成窗口只能观察已成立的2张摸牌。
		var is_before: bool = timing not in ["phaseDrawEnd", "phaseDrawAfter"]
		_check(_controller.state.get_player(0).hand.size() == (0 if is_before else 2), timing + " drew early")
		if is_before:
			_paused_event.data["draw_count"] = 3
		_submit_choice()
		_check(_controller.state.get_player(0).hand.size() == (3 if is_before else 2), timing + " lost draw count or repeated draw")
		_check((_controller as PhaseController).next_phase_method == "_enter_play_phase", timing + " lost successor")
		_check(_controller._started_phase_lifecycles.is_empty(), timing + " leaked lifecycle")
		_check_clean(timing)


## 结束阶段和回合End分开等待，后续窗口不能在前一个窗口的选择未完成时提前发布。
func _test_finish_windows() -> void:
	# 结束阶段及回合尾部时机；每次只暂停其中一个位置。
	var timings: Array[String] = ["phaseJieshuBefore", "phaseJieshuBegin", "phaseJieshu", "phaseJieshuEnd", "phaseJieshuAfter", "phaseEnd", "phase_finish", "phaseAfter"]
	# 暂停位置；完整记录真实发布顺序。
	for paused_index: int in range(timings.size()):
		_reset_controller()
		# 时机记录；订阅总线观察当前窗口已开始但后继尚未发布。
		var order: Array[String] = []
		for timing: String in timings:
			_controller.event_bus.subscribe(timing, self, func(event: RuleEvent) -> void: order.append(event.name))
		_controller.trigger_manager.subscribe(timings[paused_index], self, _pause_window)
		_controller._enter_finish_phase(0)
		_check(order == timings.slice(0, paused_index + 1), timings[paused_index] + " crossed next window: " + str(order))
		_submit_choice()
		_check(order == timings, timings[paused_index] + " missing or repeated finish window: " + str(order))
		_check_clean(timings[paused_index])


## 阶段切换通知等待时仍展示原阶段，正式Begin和操作入口都不得抢跑。
func _test_phase_change() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("phaseChange", self, _pause_window)
	_controller._enter_play_phase(0)
	_check(_controller.state.current_phase == "choice" and (_controller as PhaseController).play_body_count == 0, "phaseChange committed before child: %s/%d" % [_controller.state.current_phase, (_controller as PhaseController).play_body_count])
	_submit_choice()
	_check(_controller.state.current_phase == "play" and (_controller as PhaseController).play_body_count == 1, "phaseChange did not open one body: %s/%d" % [_controller.state.current_phase, (_controller as PhaseController).play_body_count])
	_check_clean("phaseChange")
