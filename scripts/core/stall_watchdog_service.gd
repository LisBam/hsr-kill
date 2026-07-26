class_name StallWatchdogService
extends Node

## 对局停滞自修复看门狗组件。组件只通过 MatchController 的公开诊断与修复端口工作，不直接读写事件栈、请求或玩法状态。
## 职责边界：本组件负责“何时判定停滞、何时按级别触发修复”，具体修复动作与玩家提醒文案由控制器统一执行并广播。
## 判定原则：只有在“对局既没有推进，也没有任何人类可以操作的待办”时才视为卡死；人类思考时间永远不会触发强制修复。

## 停滞修复完成信号；参数为控制器返回的修复报告副本，测试与调试面板可订阅而不必反查控制器。
signal stall_repair_attempted(repair_report: Dictionary)

## 是否启用看门狗；关闭后组件完全静默，不做任何检测或修复，可在检查器中直接调试对比。
@export var enabled: bool = true

## 相邻两次停滞检测的间隔秒数；默认1秒在性能与响应速度间平衡，无需运行时动态修改。
@export_range(0.25, 5.0, 0.25) var check_interval_seconds: float = 1.0

## 无人类待办且对局无任何进展多少秒后执行第一级软修复；软修复只重排既有异步任务，绝不改变规则结果。
## 默认8秒大于最长AI响应延迟与阶段间隔之和的数倍，正常对局节奏不会误触发。
@export_range(2.0, 60.0, 0.5) var soft_repair_seconds: float = 8.0

## 软修复后停滞仍未解除时执行第二级硬修复的累计停滞秒数；硬修复会清理孤儿暂停令牌并中断确认无法恢复的请求。
@export_range(4.0, 120.0, 0.5) var hard_repair_seconds: float = 16.0

## 硬修复后停滞仍未解除时的重复硬修复间隔秒数；对局已经卡死时按固定节奏持续尝试，直到状态出现变化。
@export_range(4.0, 120.0, 0.5) var hard_repair_repeat_seconds: float = 16.0

## 人类待办长期无操作后重发选择提示的秒数；0或负数表示关闭提醒，重发只刷新界面提示，绝不代替玩家做选择。
## 默认60秒；提醒用于修复“待办已存在但界面漏显示”的场景，玩家正常思考不受影响。
@export_range(0.0, 600.0, 5.0) var human_prompt_reminder_seconds: float = 60.0

## 被监控的权威对局控制器；由控制器在装配组件时通过 bind 注入，未绑定时组件保持静默。
var _match_controller: MatchController = null

## 距离上一次停滞检测已累计的秒数；达到检测间隔后清零并执行一次检测。
var _seconds_since_check: float = 0.0

## 最近一次观察到的对局进度指纹；指纹变化表示对局仍在推进，所有停滞计时立即清零。
var _last_fingerprint: String = ""

## 当前连续停滞秒数；仅在“无人类待办且指纹不变”期间累计，指纹变化或进入人类等待后清零。
var _stalled_seconds: float = 0.0

## 当前人类待办连续无操作秒数；仅在“存在人类待办且指纹不变”期间累计，用于界面提示重发。
var _human_waiting_seconds: float = 0.0

## 本次停滞窗口内是否已执行过软修复；指纹变化后重置，避免同一停滞反复执行低级修复。
var _soft_repair_done: bool = false

## 本次停滞窗口内是否已执行过硬修复；指纹变化后重置。
var _hard_repair_done: bool = false

## 本次停滞窗口内下一次重复硬修复的停滞秒数阈值；每次重复后按固定间隔顺延。
var _next_hard_repeat_threshold: float = 0.0

## 本次人类等待窗口内是否已重发过提示；指纹变化后重置，防止每个检测周期重复刷屏。
var _human_reminder_sent: bool = false

## 累计软修复触发次数；供回归测试与诊断读取，重新绑定控制器时清零。
var _soft_repair_count: int = 0

## 累计硬修复触发次数；供回归测试与诊断读取。
var _hard_repair_count: int = 0

## 累计人类提示重发次数；供回归测试与诊断读取。
var _human_reminder_count: int = 0

## 最近一次修复报告副本；空字典表示尚未执行过任何修复。
var _last_repair_report: Dictionary = {}


## 看门狗必须在场景树暂停期间继续运行：机缘选择与对局级暂停都会暂停场景树，而这正是需要监控的窗口。
## 是否真正处于“用户主动暂停浏览界面”由控制器诊断数据区分，组件自身不读取暂停服务内部状态。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 绑定被监控的对局控制器并复位全部检测状态；控制器在装配阶段调用一次即可。
func bind(match_controller: MatchController) -> void:
	_match_controller = match_controller
	reset_monitor_state()
	_soft_repair_count = 0
	_hard_repair_count = 0
	_human_reminder_count = 0
	_last_repair_report = {}


## 清零全部停滞计时与修复标记；新对局开始、对局结束或指纹变化时调用，不影响累计统计次数。
func reset_monitor_state() -> void:
	_last_fingerprint = ""
	_stalled_seconds = 0.0
	_human_waiting_seconds = 0.0
	_soft_repair_done = false
	_hard_repair_done = false
	_next_hard_repeat_threshold = 0.0
	_human_reminder_sent = false


## 按固定间隔累计时间并执行停滞检测；组件始终处理，暂停期间的误判由诊断数据的可监控标志排除。
func _process(delta: float) -> void:
	if not enabled or _match_controller == null:
		return
	_seconds_since_check += delta
	if _seconds_since_check < check_interval_seconds:
		return
	# 本次检测覆盖的实际时长；一次性全部计入停滞或人类等待，避免帧率波动导致计时偏慢。
	var elapsed_seconds: float = _seconds_since_check
	_seconds_since_check = 0.0
	_run_stall_check(elapsed_seconds)


## 执行一次停滞检测；根据控制器诊断数据推进计时并按级别请求修复。
func _run_stall_check(elapsed_seconds: float) -> void:
	# 当前对局诊断快照；包含可监控标志、人类待办标志与进度指纹，全部由控制器权威计算。
	var diagnostics: Dictionary = _match_controller.get_stall_diagnostics()
	if not bool(diagnostics.get("monitorable", false)):
		reset_monitor_state()
		return
	# 当前进度指纹；对局任何事件、动作、请求或阶段变化都会改变该值。
	var fingerprint: String = str(diagnostics.get("fingerprint", ""))
	if fingerprint != _last_fingerprint:
		reset_monitor_state()
		_last_fingerprint = fingerprint
		return
	if bool(diagnostics.get("waiting_for_human", false)):
		# 人类可操作期间绝不累计停滞；只在提醒开关开启时累计等待时长用于界面提示重发。
		_stalled_seconds = 0.0
		_soft_repair_done = false
		_hard_repair_done = false
		_next_hard_repeat_threshold = 0.0
		_human_waiting_seconds += elapsed_seconds
		if human_prompt_reminder_seconds > 0.0 and not _human_reminder_sent and _human_waiting_seconds >= human_prompt_reminder_seconds:
			_human_reminder_sent = true
			_human_reminder_count += 1
			_request_repair("human_reminder")
		return
	_human_waiting_seconds = 0.0
	_human_reminder_sent = false
	_stalled_seconds += elapsed_seconds
	if not _soft_repair_done and _stalled_seconds >= soft_repair_seconds:
		_soft_repair_done = true
		_soft_repair_count += 1
		_request_repair("soft")
		return
	if not _hard_repair_done and _stalled_seconds >= hard_repair_seconds:
		_hard_repair_done = true
		_next_hard_repeat_threshold = _stalled_seconds + hard_repair_repeat_seconds
		_hard_repair_count += 1
		_request_repair("hard")
		return
	if _hard_repair_done and _stalled_seconds >= _next_hard_repeat_threshold:
		_next_hard_repeat_threshold = _stalled_seconds + hard_repair_repeat_seconds
		_hard_repair_count += 1
		_request_repair("hard")


## 请求控制器执行指定级别的修复并广播报告；修复的具体动作、日志与玩家提醒全部由控制器实现。
func _request_repair(repair_kind: String) -> void:
	if _match_controller == null:
		return
	# 本次修复报告；控制器返回实际执行的动作列表，空动作表示本级修复没有可做的事。
	var repair_report: Dictionary = _match_controller.perform_stall_self_repair(repair_kind)
	if repair_report.is_empty():
		return
	_last_repair_report = repair_report.duplicate(true)
	stall_repair_attempted.emit(repair_report.duplicate(true))


## 返回看门狗诊断快照；回归测试与调试面板读取累计计数与当前计时，不能据此修改内部状态。
func get_diagnostics_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"stalled_seconds": _stalled_seconds,
		"human_waiting_seconds": _human_waiting_seconds,
		"soft_repair_count": _soft_repair_count,
		"hard_repair_count": _hard_repair_count,
		"human_reminder_count": _human_reminder_count,
		"last_repair_report": _last_repair_report.duplicate(true),
	}
