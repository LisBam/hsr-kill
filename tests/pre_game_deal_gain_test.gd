extends Node

## 开局前起始手牌分发的获得口径回归。
##
## 覆盖三条口径：
## 1) 开局前分发起始手牌**不是**对局内的「获得牌」：整段分发不派发 `cardsGainedBatchAfter`，
##    因此【风口】不会在手气卡阶段之前建立询问，手气卡阶段不会被卡住。
## 2) 手气卡阶段本身可以正常刷新，且刷新后依然没有询问。
## 3) `gameStart` 时机之后的技能摸牌照常构成获得批次：【筹码】摸到的牌必须能触发【风口】第一段，
##    而回答该询问之后首回合必须真正开始（不卡死）。
##
## 本用例必须跑真实开局：起始手牌分发发生在选将完成与手气卡之间，只有完整开局才能复现该时序。

## 本场景的玩家数量；三个座位足够覆盖「真人 + 内置AI」的手气卡推进。
const TEST_PLAYER_COUNT: int = 3
## 固定随机种子；保证选将、发牌与手气卡结果可复现。
const TEST_RANDOM_SEED: int = 20261004
## 本场景使用的手气卡张数；至少一次刷新才能验证「刷新期间同样不产生询问」。
const TEST_MULLIGAN_LIMIT: int = 1
## 隔离用的临时设置文件；手气卡张数会写盘，必须避免污染开发者本机设置。
const TEST_SETTINGS_FILE_PATH: String = "user://pre_game_deal_gain_test_settings.cfg"
## 起始手牌标准张数；与正式默认值一致，用于断言分发数量。
const EXPECTED_STARTING_HAND: int = 4
## 触发【风口】第一段所需的最小批次张数；【筹码】的 X 取体力上限，必须不小于该值才能验证联动。
const MIN_TRIGGERING_BATCH: int = 2
## 看门狗秒数；超时以失败结束，避免流程停滞时测试进程永远挂起。
const WATCHDOG_SECONDS: float = 60.0
## 提交询问回答后，等待一次阶段推进被执行的最长墙钟时间；阶段节奏默认0.3秒，因此留出数倍余量。
const TRANSITION_PROGRESS_TIMEOUT_SECONDS: float = 6.0

## 被测控制器；本用例会替换为整局控制器以跑真实开局。
var _controller: MatchController
## 是否已经失败；防止看门狗与失败出口重复退出。
var _failed: bool = false
## 记录 gameDrawBefore 时机是否已经用于安装技能。
var _skills_installed_for_deal: bool = false
## 设置写盘路径是否已隔离。
var _settings_isolated: bool = false
## 原始设置写盘路径；退出时恢复。
var _original_settings_file_path: String = ""
## 提交询问回答之后被执行到的阶段推进次数；只用于证明首回合没有停在原阶段。
var _executed_transition_count: int = 0


## 延迟一帧执行断言，确保 GameDatabase 完成目录扫描；同时安装看门狗兜底。
func _ready() -> void:
	call_deferred("_run")
	# 看门狗计时器；只用于把停滞变成可见的失败而不是挂起。
	var watchdog: SceneTreeTimer = get_tree().create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(_on_watchdog_timeout)


## 看门狗超时出口；输出可定位的失败标记并以1结束进程。
func _on_watchdog_timeout() -> void:
	if _failed:
		return
	_failed = true
	printerr("PRE_GAME_DEAL_FAIL watchdog_timeout")
	get_tree().quit(1)


## 执行完整开局回归；两种回答方式（确认 / 取消）都必须让首回合继续推进，任一断言失败立即停止。
func _run() -> void:
	_begin_settings_isolation()
	# 关闭全部自选与改将入口，只保留随机选将与真人手气卡两条路径。
	GameSettings.set_control_all_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(TEST_MULLIGAN_LIMIT)
	# 确认路径与取消路径各自重开一局；两条路径在询问结束时都会把阶段恢复成 resume_phase，
	# 因此都必须由同一条阶段推进继续推动，不能只覆盖其中一条。
	for confirmed: bool in [true, false]:
		if not await _run_pre_game_scenario(confirmed):
			return
	print("PRE_GAME_DEAL_PASS deal=no_batch mulligan=clean chouma=4 fengkou=triggered confirm=progress cancel=progress")
	_restore_settings()
	get_tree().quit(0)


## 跑一遍真实开局并在【风口】第一段询问处按指定方式作答；返回false表示本场景已经报告失败。
func _run_pre_game_scenario(confirmed: bool) -> bool:
	_skills_installed_for_deal = false
	_create_controller()
	if not _controller.start_match(TEST_PLAYER_COUNT, TEST_RANDOM_SEED, IdentityRules.MODE_IDENTITY):
		return _fail("start_match")
	# 起始手牌在选将完成后立即发放，因此技能必须在发放之前就已经安装好；gameDrawBefore 是发牌前的最后时机。
	_controller.trigger_manager.subscribe("gameDrawBefore", self, func(_event: RuleEvent) -> void:
		_install_deal_window_skills(), 0, -1, "global")
	# 选将阶段：本地真人按候选顺序提交，其余座位由内置AI自动推进。
	var selection_safety: int = 0
	while _controller.state.current_phase == "character_selection" and selection_safety < 32:
		selection_safety += 1
		if _controller.character_selection.get_pending_player_ids().has(0):
			var candidates: Array[String] = _controller.character_selection.get_candidates(0)
			if candidates.is_empty() or not _controller.select_character(0, candidates[0]):
				return _fail("character_selection")
		await get_tree().process_frame
	# 断言一：起始手牌已经发完，但整段分发没有触发任何获得类询问。
	if not _skills_installed_for_deal:
		return _fail("game_draw_before_not_reached")
	if _controller.state.current_phase != "starting_hand_mulligan":
		return _fail("mulligan_phase=%s" % str(_controller.state.current_phase))
	if _controller.state.get_player(0).hand.size() != EXPECTED_STARTING_HAND:
		return _fail("starting_hand=%d" % _controller.state.get_player(0).hand.size())
	if _controller.has_pending_card_choice():
		return _fail("deal_created_choice kind=%s" % str(_controller._pending_card_choice.get("context", {}).get("kind", "")))
	# 断言二：手气卡阶段可以正常刷新，刷新用的是开局前替换通道，因此同样不产生询问。
	var refresh_action: PlayerAction = PlayerAction.new("mulligan_refresh", 0)
	if not _controller.submit_action(refresh_action):
		return _fail("mulligan_refresh_rejected phase=%s" % str(_controller.state.current_phase))
	if _controller.state.get_player(0).hand.size() != EXPECTED_STARTING_HAND:
		return _fail("mulligan_refresh_hand=%d" % _controller.state.get_player(0).hand.size())
	if _controller.has_pending_card_choice():
		return _fail("mulligan_refresh_created_choice")
	# 推进手气卡阶段：真人确认保留，AI 座位由正式驱动逻辑自行完成。
	var mulligan_safety: int = 0
	while _controller.state.current_phase == "starting_hand_mulligan" and mulligan_safety < 24:
		mulligan_safety += 1
		var local_state: Dictionary = _controller.starting_hand_mulligan.to_dict(0)
		if bool(local_state.get("can_choose", false)):
			var finish_action: PlayerAction = PlayerAction.new("mulligan_finish", 0)
			if not _controller.submit_action(finish_action):
				return _fail("mulligan_finish_rejected")
		else:
			_controller._drive_ai_starting_hand_mulligan()
		await get_tree().process_frame
	if _controller.state.current_phase == "starting_hand_mulligan":
		return _fail("mulligan_stuck")
	# 断言三：【筹码】在 gameStart 摸到 X 张（X = 持有者体力上限），构成一次性获得，因此必须触发【风口】第一段。
	# 本用例通过 gameDrawBefore 手动安装技能，座次武将是随机候选，因此 X 必须按权威体力上限读取而不是写死常量。
	var chouma_draw: int = int(_controller.state.get_player(0).max_hp)
	if chouma_draw < MIN_TRIGGERING_BATCH:
		return _fail("chouma_draw_too_small=%d" % chouma_draw)
	if _controller.state.get_player(0).hand.size() != EXPECTED_STARTING_HAND + chouma_draw:
		return _fail("chouma_hand=%d expected=%d" % [_controller.state.get_player(0).hand.size(), EXPECTED_STARTING_HAND + chouma_draw])
	if not await _await_clause1_choice():
		return _fail("chouma_never_triggered_fengkou phase=%s pending=%s" % [str(_controller.state.current_phase), str(_controller.has_pending_card_choice())])
	if str(_controller._pending_card_choice.get("context", {}).get("kind", "")) != "fengkou_clause1":
		return _fail("pending_kind=%s" % str(_controller._pending_card_choice.get("context", {}).get("kind", "")))
	# 复现真实时序：真人在询问面板上停留的时间必然长于阶段节奏间隔，因此这里必须等一次以上节奏间隔再作答。
	# 若不等，询问会在阶段推进计时到期之前就被回答，缺陷就被掩盖了。
	await get_tree().create_timer(maxf(_controller.game_flow_interval_seconds, 0.05) * 2.0).timeout
	# 断言四：回答该询问后首回合必须继续推进。
	# 只检查阶段名不够：缺陷的表现正是「阶段名被恢复成推进前的名字」而推进本身已经丢失，
	# 因此这里改为等待一次真实的阶段推进被执行（在提交回答之后才开始计数）。
	_executed_transition_count = 0
	if _controller.game_flow_transition_coordinator != null:
		_controller.game_flow_transition_coordinator.transition_executed.connect(func(_data: Dictionary) -> void:
			_executed_transition_count += 1)
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var answer_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	answer_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":confirmed}
	if not _controller.submit_action(answer_action):
		return _fail("clause1_answer_rejected confirmed=%s" % str(confirmed))
	var progress_wait: float = 0.0
	while _executed_transition_count == 0 and progress_wait < TRANSITION_PROGRESS_TIMEOUT_SECONDS:
		progress_wait += get_process_delta_time()
		await get_tree().process_frame
	if _executed_transition_count == 0:
		return _fail("turn_transition_never_executed confirmed=%s phase=%s pending=%s" % [str(confirmed), str(_controller.state.current_phase), str(_controller.has_pending_card_choice())])
	if _controller.has_pending_card_choice():
		return _fail("pending_choice_left kind=%s" % str(_controller._pending_card_choice.get("context", {}).get("kind", "")))
	# 首回合必须已经真正开始：阶段离开开局前与询问阶段，且已经确定当前行动角色。
	# 首回合角色由身份/座次规则决定，不一定是本地真人所在座次，因此只校验「已经开始」而不写死玩家 ID。
	if str(_controller.state.current_phase) in ["", "game_start", "starting_hand_mulligan", "character_selection", "choice", "round_start"]:
		return _fail("first_turn_not_started confirmed=%s phase=%s" % [str(confirmed), str(_controller.state.current_phase)])
	if _controller.state.game_over or _controller.state.current_player_id < 0 or _controller.state.turn_number < 1:
		return _fail("turn_state player=%d turn=%d over=%s" % [_controller.state.current_player_id, _controller.state.turn_number, str(_controller.state.game_over)])
	# 确认路径必须真的弃置整批（取消路径必须一张都不弃），用于区分两条回答路径确实被分别执行。
	# 本批只有【筹码】摸到的那些牌，因此确认后剩下的正是起始手牌。
	var hand_after_answer: int = _controller.state.get_player(0).hand.size()
	if confirmed and hand_after_answer != EXPECTED_STARTING_HAND:
		return _fail("clause1_confirm_hand=%d" % hand_after_answer)
	if not confirmed and hand_after_answer != EXPECTED_STARTING_HAND + chouma_draw:
		return _fail("clause1_cancel_hand=%d" % hand_after_answer)
	return true


## 在起始手牌发放之前安装【筹码】与【风口】；发牌窗口内安装才能复现「初始手牌触发获得」的真实时序。
func _install_deal_window_skills() -> void:
	if _skills_installed_for_deal:
		return
	_skills_installed_for_deal = true
	if _install_single_skill(0, "chouma") == null:
		return _fail("chouma_install")
	if _install_single_skill(0, "fengkou") == null:
		return _fail("fengkou_install")


## 等待【风口】第一段的延后询问出现；本技能一律把询问推迟到结算边界，因此必须让出进程帧。
func _await_clause1_choice() -> bool:
	for _attempt: int in range(12):
		if _controller.has_pending_card_choice():
			return true
		await get_tree().process_frame
	return _controller.has_pending_card_choice()


## 为指定玩家安装一个运行时技能实例；测试需要通过真实时机订阅复现完整流程。
func _install_single_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 新技能实例；技能目录缺失时返回null并交由调用方报告具体场景。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家已安装技能表；同一场景可连续追加多个技能以验证武将内技能联动。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；全部技能时机都经它派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；其余座位由内置AI推进手气卡与选将。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；动作提交与正式单机模式保持相同来源语义。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	network_gateway.mode = NetworkGateway.Mode.OFFLINE
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	# 固定本地真人座次；随机座次会让选将与手气卡提交落到 AI 身上。
	_controller.randomize_local_human_seat = false
	# 阶段节奏保持正式默认值：本用例要复现的是「阶段推进计时到期时阶段名正被询问占用」的真实卡死，
	# 把节奏归零会让阶段推进与询问创建落在同一帧，从而掩盖该缺陷。


## 把设置写盘路径指向独立临时文件；手气卡张数会写盘，必须隔离。
func _begin_settings_isolation() -> void:
	_original_settings_file_path = GameSettings.get_settings_file_path()
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)
	_settings_isolated = true


## 恢复正式设置写盘路径并删除测试文件；未隔离时安全地什么都不做。
func _restore_settings() -> void:
	if not _settings_isolated:
		return
	_settings_isolated = false
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))


## 输出失败原因、恢复设置并以非零状态结束进程。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	_restore_settings()
	printerr("PRE_GAME_DEAL_FAIL %s" % message)
	get_tree().quit(1)
	return false
