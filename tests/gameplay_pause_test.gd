extends Node

## 对局级暂停接口回归测试。验证统一令牌暂停会同时阻塞场景树、事件运行时和所有 AI 标准动作入口。

## 正式主场景资源路径；测试直接运行玩家实际使用的节点组合与日志暂停服务。
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

## 测试使用的 AI 等待时间；0.40秒为暂停申请留出稳定窗口，同时保持测试总时长较短。
const TEST_AI_DELAY_SECONDS: float = 0.40

## 暂停观察时长；大于一次 AI 等待时间，若计时器错误使用始终处理模式则动作序号必然增长。
const PAUSE_OBSERVATION_SECONDS: float = 0.65

## 恢复后最长等待时长；正常 AI 会在剩余延迟结束后通过标准动作入口推进序号。
const RESUME_TIMEOUT_SECONDS: float = 1.20

## 纯AI完成选将、准备阶段技能询问并进入出牌阶段的最长等待毫秒数；新增触发技能后使用6秒覆盖完整合法选择链。
const SETUP_TIMEOUT_MILLISECONDS: int = 6000


## 延迟开始测试，保证测试根节点已经进入场景树；根节点始终处理以便在对局暂停期间继续执行断言。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 启动两人纯 AI 对局，并验证暂停前后动作序号边界。
func _run() -> void:
	# 正式主场景资源；加载失败时直接终止测试并输出稳定错误。
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；所有 AI、事件运行时与暂停服务均来自实际场景配置。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 权威对局控制器；纯 AI 模式避免等待本地选将或操作输入。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 2
	match_controller.local_human_player_id = -1
	match_controller.randomize_local_human_seat = false
	match_controller.ai_action_delay_seconds = TEST_AI_DELAY_SECONDS
	# 主菜单启动边界不会自动创建对局；测试通过公开入口显式开始两人纯AI身份局。
	if not match_controller.start_match(2, 19):
		_fail("start_ai_match")
		return
	# 等待纯 AI 完成选将并进入首个出牌阶段；上限只防御场景初始化异常，不依赖真实对局时长。
	var setup_deadline_msec: int = Time.get_ticks_msec() + SETUP_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < setup_deadline_msec and (match_controller.state == null or match_controller.state.current_phase != "play"):
		await get_tree().process_frame
	if match_controller.state == null or match_controller.state.current_phase != "play":
		_fail("ai_match_not_ready")
		return
	# 当前 AI 行动者；首回合角色必须已由控制器登记为内置 AI。
	var ai_player_id: int = match_controller.state.current_player_id
	if not match_controller.ai_coordinator.is_ai_controlled(ai_player_id):
		_fail("current_player_not_ai")
		return
	# 暂停前动作序号；观察窗口内任何 AI 选择、出牌或结束阶段都会改变该值。
	var action_sequence_before_pause: int = match_controller.state.action_sequence
	# 测试持有的暂停令牌；只通过公开接口申请，模拟“记录”按钮的实际调用方式。
	var pause_token: int = match_controller.acquire_gameplay_pause("gameplay_pause_regression")
	if pause_token < 0 or not get_tree().paused or not match_controller.is_gameplay_paused() or int(match_controller.get("_gameplay_event_pause_token")) < 0:
		_fail("pause_interface_not_active")
		return
	# 暂停期间直接伪造的 AI 结束阶段动作；公开入口必须拒绝，不能依赖计时器碰巧尚未到期。
	var blocked_ai_action: PlayerAction = PlayerAction.new("end_play", ai_player_id)
	if match_controller.submit_action(blocked_ai_action):
		_fail("direct_ai_action_accepted_while_paused")
		return
	# 始终处理计时器只驱动测试观察；被测 AI 计时器必须使用暂停感知模式并保持动作序号不变。
	await get_tree().create_timer(PAUSE_OBSERVATION_SECONDS, true).timeout
	if match_controller.state.action_sequence != action_sequence_before_pause:
		_fail("ai_acted_while_paused:%d/%d" % [action_sequence_before_pause, match_controller.state.action_sequence])
		return
	if not match_controller.release_gameplay_pause(pause_token) or get_tree().paused or match_controller.is_gameplay_paused() or int(match_controller.get("_gameplay_event_pause_token")) >= 0:
		_fail("pause_interface_not_released")
		return
	# 恢复等待截止时间；AI 应继续原计时器剩余时长并最终通过标准动作入口推进序号。
	var resume_deadline_msec: int = Time.get_ticks_msec() + int(RESUME_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < resume_deadline_msec and match_controller.state.action_sequence == action_sequence_before_pause:
		await get_tree().process_frame
	if match_controller.state.action_sequence == action_sequence_before_pause:
		_fail("ai_did_not_resume")
		return
	# 恢复后的动作序号；释放场景实例前保存，避免测试输出访问已经释放的控制器。
	var action_sequence_after_resume: int = match_controller.state.action_sequence
	# 测试收尾状态；使仍在等待的 AI 协程到期后只走令牌失效分支，不继续创建新动作或计时器。
	match_controller.state.game_over = true
	match_controller.set("_ai_drive_token", int(match_controller.get("_ai_drive_token")) + 1)
	match_controller.event_scheduler.abort_all("gameplay_pause_test_complete")
	await get_tree().create_timer(TEST_AI_DELAY_SECONDS + 0.10, true).timeout
	remove_child(main_instance)
	main_instance.free()
	await get_tree().process_frame
	print("GAMEPLAY_PAUSE_PASS before=%d after=%d" % [action_sequence_before_pause, action_sequence_after_resume])
	get_tree().quit(0)


## 输出稳定失败原因并以非零状态退出，便于命令行与持续集成定位。
func _fail(reason: String) -> void:
	printerr("GAMEPLAY_PAUSE_FAIL %s" % reason)
	get_tree().paused = false
	get_tree().quit(1)
