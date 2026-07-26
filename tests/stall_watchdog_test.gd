extends Node

## 对局停滞自修复看门狗回归测试。验证孤儿暂停令牌清扫、软修复重排停滞AI、人类等待不误修复但收到提醒、
## 硬修复把无人认领座位转入托管，以及修复提醒横幅与信号确实到达界面层。

## 正式主场景资源路径；测试直接运行玩家实际使用的节点组合、看门狗与信息层。
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

## 测试使用的AI等待时间；0.10秒让正常流程快速推进，与看门狗阈值拉开数量级。
const TEST_AI_DELAY_SECONDS: float = 0.10

## 测试使用的流程间隔；0.10秒保证正常安静间隙远小于停滞判定阈值，避免误触发干扰断言。
const TEST_FLOW_INTERVAL_SECONDS: float = 0.10

## 看门狗检测间隔；0.20秒加快测试节奏，正式对局默认仍为1秒。
const TEST_CHECK_INTERVAL_SECONDS: float = 0.20

## 软修复停滞阈值；0.9秒明显大于测试AI等待与流程间隔，正常运行不会误判。
const TEST_SOFT_REPAIR_SECONDS: float = 0.9

## 硬修复停滞阈值；1.8秒给软修复留出一个完整生效窗口。
const TEST_HARD_REPAIR_SECONDS: float = 1.8

## 人类待办提醒阈值；1.0秒便于在短测试窗口内验证提醒重发。
const TEST_HUMAN_REMINDER_SECONDS: float = 1.0

## 纯AI完成选将并进入出牌阶段的最长等待毫秒数；4人局覆盖完整选将与首回合准备链。
const SETUP_TIMEOUT_MILLISECONDS: int = 20000

## 单个场景断言的默认等待毫秒数；覆盖检测间隔、修复动作与后续AI恢复的完整链路。
const SCENARIO_TIMEOUT_MILLISECONDS: int = 8000

## 权威对局控制器；全部场景共用同一实例，直接读取其公开诊断与内部停滞状态。
var _match_controller: MatchController

## 停滞看门狗组件；由控制器装配，测试只调整阈值并读取诊断快照。
var _watchdog: StallWatchdogService

## 主场景根节点；用于读取信息层横幅状态，验证修复提醒确实到达界面。
var _main_instance: Control

## 收到的自修复报告列表；连接控制器信号后追加，供各场景断言修复级别。
var _repair_reports: Array[Dictionary] = []

## 收到的对局日志列表；用于断言自动修复日志确实写入玩家可见的对局记录。
var _log_messages: Array[String] = []


## 延迟开始测试，保证测试根节点已经进入场景树；根节点始终处理以便在对局暂停期间继续断言。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次执行全部看门狗场景；任一失败立即输出稳定原因并以非零码退出。
func _run() -> void:
	# 正式主场景资源；加载失败时直接终止测试。
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	_main_instance = main_scene.instantiate() as Control
	add_child(_main_instance)
	_match_controller = _main_instance.get_node("MatchController") as MatchController
	_match_controller.default_player_count = 4
	_match_controller.local_human_player_id = -1
	_match_controller.randomize_local_human_seat = false
	_match_controller.ai_action_delay_seconds = TEST_AI_DELAY_SECONDS
	_match_controller.game_flow_interval_seconds = TEST_FLOW_INTERVAL_SECONDS
	_watchdog = _match_controller.stall_watchdog
	if _watchdog == null:
		_fail("watchdog_not_installed")
		return
	_watchdog.check_interval_seconds = TEST_CHECK_INTERVAL_SECONDS
	_watchdog.soft_repair_seconds = TEST_SOFT_REPAIR_SECONDS
	_watchdog.hard_repair_seconds = TEST_HARD_REPAIR_SECONDS
	_watchdog.hard_repair_repeat_seconds = TEST_HARD_REPAIR_SECONDS
	_watchdog.human_prompt_reminder_seconds = TEST_HUMAN_REMINDER_SECONDS
	_match_controller.self_repair_performed.connect(func(report: Dictionary) -> void: _repair_reports.append(report.duplicate(true)))
	_match_controller.log_added.connect(func(message: String) -> void: _log_messages.append(message))
	# 显式指定标准身份局；避免沿用本机玩家设置中保存的下一局模式导致人数校验失败。
	if not _match_controller.start_match(4, 19, "identity"):
		_fail("start_ai_match")
		return
	# 等待纯AI完成选将并进入首个出牌阶段；上限仅防御场景初始化异常。
	if not await _wait_until(func() -> bool: return _match_controller.state != null and _match_controller.state.current_phase == "play", SETUP_TIMEOUT_MILLISECONDS):
		_fail("ai_match_not_ready")
		return
	if not _match_controller.get_stall_diagnostics().get("monitorable", false):
		_fail("diagnostics_not_monitorable")
		return
	await _run_orphan_token_sweep_scenario()
	await _run_soft_repair_scenario()
	await _run_human_wait_scenario()
	await _run_hard_repair_orphan_seat_scenario()
	print("STALL_WATCHDOG_PASS soft=%d hard=%d reminder=%d reports=%d" % [int(_watchdog.get_diagnostics_snapshot().get("soft_repair_count", 0)), int(_watchdog.get_diagnostics_snapshot().get("hard_repair_count", 0)), int(_watchdog.get_diagnostics_snapshot().get("human_reminder_count", 0)), _repair_reports.size()])
	get_tree().quit(0)


## 场景一：孤儿暂停令牌清扫。注入永远无法被解决的choice与gameplay令牌后，修复端口必须精确释放它们。
func _run_orphan_token_sweep_scenario() -> void:
	# 注入前活动令牌数量；清扫后必须恢复到该基线，不得误伤正常令牌。
	var baseline_active_tokens: int = _match_controller.event_scheduler.pause_registry.get_active_tokens().size()
	# 孤儿choice令牌；原因指向不存在的请求ID，任何正常提交都不会解决它。
	_match_controller.event_scheduler.pause_registry.acquire("choice", -1, "choice_request:999999")
	# 孤儿gameplay令牌；暂停服务当前并未暂停，该令牌不可能经正常恢复路径释放。
	_match_controller.event_scheduler.pause_registry.acquire("gameplay", -1, "gameplay_pause_interface")
	# 清扫结果；两个孤儿令牌都必须被识别并释放。
	var released_tokens: Array[String] = _match_controller._release_orphan_runtime_pause_tokens()
	if released_tokens.size() != 2:
		_fail("orphan_token_sweep_count:%d" % released_tokens.size())
		return
	if _match_controller.event_scheduler.pause_registry.get_active_tokens().size() != baseline_active_tokens:
		_fail("orphan_token_sweep_residual")
		return


## 场景二：软修复救活被废弃的AI驱动。令牌递增使全部飞行中的出牌计时器作废后，看门狗必须自动恢复流程。
func _run_soft_repair_scenario() -> void:
	if not await _wait_for_stable_ai_play_choice():
		_fail("soft_scenario_setup")
		return
	# 修复前软修复次数；断言只统计本场景新增的触发。
	var soft_count_before: int = int(_watchdog.get_diagnostics_snapshot().get("soft_repair_count", 0))
	# 修复前动作序号；恢复后必须继续增长。
	var action_sequence_before: int = _match_controller.state.action_sequence
	# 人为废弃全部AI等待任务；等价于确认过的令牌竞态卡死形态。
	_match_controller._ai_drive_token += 1
	_match_controller._scheduled_ai_drive_token = -1
	_match_controller._scheduled_ai_choice_request_id = -1
	if not await _wait_until(func() -> bool: return int(_watchdog.get_diagnostics_snapshot().get("soft_repair_count", 0)) > soft_count_before, SCENARIO_TIMEOUT_MILLISECONDS):
		_fail("soft_repair_not_triggered")
		return
	if not await _wait_until(func() -> bool: return _match_controller.state.action_sequence > action_sequence_before, SCENARIO_TIMEOUT_MILLISECONDS):
		_fail("soft_repair_did_not_recover")
		return


## 场景三：人类待办永不强制修复，但超时后收到提醒。把当前回合角色交给本地真人并保持不操作。
func _run_human_wait_scenario() -> void:
	if not await _wait_for_stable_ai_play_choice():
		_fail("human_scenario_setup")
		return
	# 本场景接管的角色ID；将其从AI转为本地真人视角。
	var human_player_id: int = _match_controller.state.current_player_id
	_match_controller.ai_coordinator.unregister_ai(human_player_id)
	_match_controller.local_human_player_id = human_player_id
	# 接管时的修复计数；人类思考期间软硬修复都不允许增长。
	var soft_count_before: int = int(_watchdog.get_diagnostics_snapshot().get("soft_repair_count", 0))
	var hard_count_before: int = int(_watchdog.get_diagnostics_snapshot().get("hard_repair_count", 0))
	if not await _wait_until(func() -> bool: return int(_watchdog.get_diagnostics_snapshot().get("human_reminder_count", 0)) > 0, SCENARIO_TIMEOUT_MILLISECONDS):
		_fail("human_reminder_not_sent")
		return
	if int(_watchdog.get_diagnostics_snapshot().get("soft_repair_count", 0)) != soft_count_before or int(_watchdog.get_diagnostics_snapshot().get("hard_repair_count", 0)) != hard_count_before:
		_fail("forced_repair_during_human_wait")
		return
	# 提醒横幅；信息层由牌桌创建，提醒必须真实到达玩家可见的界面通道。
	var information_box: InformationBoxLayer = _main_instance.get("information_box") as InformationBoxLayer
	if information_box == null or not information_box.is_notice_visible():
		_fail("reminder_notice_not_visible")
		return


## 场景四：硬修复接管无人认领座位。撤销真人视角后该座位既非AI也无人操作，看门狗必须托管并恢复对局。
func _run_hard_repair_orphan_seat_scenario() -> void:
	# 场景三遗留的真人角色；撤销本地视角后其待办变为无人认领。
	var orphan_player_id: int = _match_controller.local_human_player_id
	# 修复前计数与序号；用于断言硬修复新增触发并真正恢复流程。
	var hard_count_before: int = int(_watchdog.get_diagnostics_snapshot().get("hard_repair_count", 0))
	var action_sequence_before: int = _match_controller.state.action_sequence
	_match_controller.local_human_player_id = -1
	if not await _wait_until(func() -> bool: return int(_watchdog.get_diagnostics_snapshot().get("hard_repair_count", 0)) > hard_count_before, SCENARIO_TIMEOUT_MILLISECONDS):
		_fail("hard_repair_not_triggered")
		return
	if not await _wait_until(func() -> bool: return _match_controller.is_player_auto_managed(orphan_player_id), SCENARIO_TIMEOUT_MILLISECONDS):
		_fail("orphan_seat_not_auto_managed")
		return
	if not await _wait_until(func() -> bool: return _match_controller.state.action_sequence > action_sequence_before, SCENARIO_TIMEOUT_MILLISECONDS):
		_fail("hard_repair_did_not_recover")
		return
	# 修复日志；玩家必须能从对局记录中看到自动修复发生过。
	var found_repair_log: bool = false
	for log_message: String in _log_messages:
		if log_message.contains("自动修复"):
			found_repair_log = true
			break
	if not found_repair_log:
		_fail("repair_log_missing")
		return
	# 修复报告信号；至少包含一条硬修复报告，供界面横幅与未来诊断面板使用。
	var found_hard_report: bool = false
	for report: Dictionary in _repair_reports:
		if str(report.get("kind", "")) == "hard":
			found_hard_report = true
			break
	if not found_hard_report:
		_fail("hard_repair_report_missing")


## 等待对局进入“出牌阶段+AI行动者+无兼容选择+无流程任务”的稳定观测点；wedge场景由此获得确定起点。
func _wait_for_stable_ai_play_choice() -> bool:
	return await _wait_until(func() -> bool:
		if _match_controller.state == null or _match_controller.state.game_over:
			return false
		if _match_controller.state.current_phase != "play":
			return false
		if not _match_controller.ai_coordinator.is_ai_controlled(_match_controller.state.current_player_id):
			return false
		if not _match_controller._pending_card_choice.is_empty() or not _match_controller._pending_negation_choices.is_empty():
			return false
		if _match_controller.game_flow_pacer != null and _match_controller.game_flow_pacer.has_any_pending():
			return false
		return _match_controller._has_active_play_choice(), SETUP_TIMEOUT_MILLISECONDS)


## 逐帧等待谓词成立；返回是否在超时前满足条件。
func _wait_until(predicate: Callable, timeout_milliseconds: int) -> bool:
	# 本次等待截止时刻；使用单调毫秒时钟，不受系统时间调整影响。
	var deadline_msec: int = Time.get_ticks_msec() + timeout_milliseconds
	while Time.get_ticks_msec() < deadline_msec:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


## 输出稳定失败原因并退出；非零退出码供无头测试脚本判定失败。
func _fail(reason: String) -> void:
	printerr("STALL_WATCHDOG_FAIL %s" % reason)
	print("STALL_WATCHDOG_FAIL %s" % reason)
	get_tree().quit(1)
