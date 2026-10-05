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
## 随机座次可能包含会插入额外阶段的武将（例如【巡礼】的三段额外出牌阶段由AI逐步行动），
## 因此上限按“两遍完整开局 + 数十个AI动作”取值，仍远小于人工排查一次卡死所需的时间。
const WATCHDOG_SECONDS: float = 180.0
## 提交询问回答后，等待一次阶段推进被执行的最长墙钟时间；阶段节奏默认0.3秒，因此留出数倍余量。
## 随机座次可能让其他武将（例如【巡礼】的三段额外阶段）排在本次推进之前，因此余量按“数十个AI动作”取。
const TRANSITION_PROGRESS_TIMEOUT_SECONDS: float = 30.0
## 【风口】第一段询问的业务种类；按种类等待，避免把其他技能的询问误当成本次断言目标。
const CLAUSE1_KIND: String = "fengkou_clause1"
## 等待【风口】第一段询问出现的最长墙钟时间；需覆盖无关询问的AI响应延迟与阶段节奏。
## 【巡礼】的三段额外阶段（含AI逐步行动）会先于父序列延后条目被消费，因此这里按“数十个AI动作”取余量。
const CLAUSE1_WAIT_SECONDS: float = 60.0

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
## 本场景出现过的选择请求轨迹；失败信息据此区分「请求从未创建」与「请求已创建但被丢弃」。
var _choice_kind_history: Array[String] = []
## 本次开局额外安装【巡礼】的座次；-1表示没有可用AI座次，活跃性回归因此未覆盖。
var _xunli_barrier_seat: int = -1


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
	print("PRE_GAME_DEAL_PASS deal=no_batch mulligan=clean chouma=4 fengkou=triggered xunli=%d confirm=progress cancel=progress" % _xunli_barrier_seat)
	_restore_settings()
	get_tree().quit(0)


## 跑一遍真实开局并在【风口】第一段询问处按指定方式作答；返回false表示本场景已经报告失败。
func _run_pre_game_scenario(confirmed: bool) -> bool:
	_skills_installed_for_deal = false
	_xunli_barrier_seat = -1
	_choice_kind_history.clear()
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
	# 活跃性回归的前置条件：【巡礼】必须已经装到某个AI座次，否则本局不存在独立额外阶段，回归会静默失效。
	if _xunli_barrier_seat < 0:
		return _fail("xunli_barrier_seat_unavailable")
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
		return _fail("chouma_never_triggered_fengkou phase=%s pending=%s %s" % [str(_controller.state.current_phase), str(_controller.has_pending_card_choice()), _describe_choice_trace()])
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
	_install_xunli_for_parent_barrier()


## 在同一次开局里额外安装【巡礼】，固定覆盖「父序列延后条目 + 独立额外阶段」的活跃性回归。
##
## 该缺陷只在“外层序列登记的延后结算（本用例是【风口】在 `gameStart` 登记的条目）与独立额外出牌阶段同时存在”
## 时出现：屏障把父条目挡在子阶段之外，若父条目仍被当作「当前出牌阶段仍有未完成交互」，
## 子阶段的AI动作就永远不会被安排（延后队列恒非空、出牌窗口在、但没有任何计时任务），对局永久挂起。
## 随机选将是否抽到银枝会随武将池变化，只靠随机座次会让这条回归悄悄失去覆盖，
## 因此在**非银枝的AI座次**上显式安装【巡礼】，使该组合每次开局都成立；
## 本地真人座次（0号位）不安装，保证手气卡与手牌算术仍由真人路径驱动。
func _install_xunli_for_parent_barrier() -> void:
	for player: PlayerState in _controller.state.players:
		if player.player_id == 0 or str(player.character_id) == "yinzhi":
			continue
		if _install_single_skill(player.player_id, "xunli") != null:
			_xunli_barrier_seat = player.player_id
		return


## 等待【风口】第一段的延后询问出现；本技能一律把询问推迟到结算边界，因此必须让出进程帧。
##
## 本用例的座次武将是随机候选，因此同一时刻可能先出现**其他武将的无关询问**（例如【巡礼】在任意角色
## 回合开始时的发动确认）。它们与【风口】共用同一个待处理选择槽，且本用例刻意保留正式阶段节奏，
## 因此这里必须按请求种类等待，而不是见到任意待处理选择就返回。
## 属于本地真人坐席的无关询问题按取消作答：本用例只关心【风口】的批次口径，不希望其他技能的三段额外
## 阶段改变手牌数量，从而让断言四的手牌算术保持稳定。
func _await_clause1_choice() -> bool:
	# 已等待的墙钟时间；按真实时间而不是固定帧数等待，兼容AI响应延迟与阶段节奏。
	var waited: float = 0.0
	while waited < CLAUSE1_WAIT_SECONDS:
		if _controller.has_pending_card_choice():
			if _get_pending_choice_kind() == CLAUSE1_KIND:
				return true
			if int(_controller._pending_card_choice.get("chooser_id", -1)) == 0:
				_cancel_local_pending_choice()
		waited += get_process_delta_time()
		await get_tree().process_frame
	return _get_pending_choice_kind() == CLAUSE1_KIND


## 汇总等待期间的请求轨迹与结算队列状态；只在失败信息里使用，便于直接定位是“没创建”还是“被丢弃”。
func _describe_choice_trace() -> String:
	# 规则续接栈类型列表；栈顶即当前被屏障或子阶段挡住的外层续接。
	var continuation_types: Array[String] = []
	for item: Dictionary in _controller._rule_continuations.to_array():
		continuation_types.append(str(item.get("continuation_type", "")))
	# 延后结算队列摘要；用于确认【风口】的条目是否仍在队列里等待。
	var deferred_summary: Array[String] = []
	for item: Dictionary in _controller._deferred_skill_settlements:
		deferred_summary.append("%s:%s" % [str(item.get("skill_id", "")), str((item.get("context", {}) as Dictionary).get("kind", ""))])
	# 座次摘要；确认随机选将结果与手牌数量。
	var seats: Array[String] = []
	for player: PlayerState in _controller.state.players:
		seats.append("%d=%s/hp%d/hand%d" % [player.player_id, str(player.character_id), player.hp, player.hand.size()])
	return "history=%s deferred=%s cont=%s depth=%d indep_play=%s cur=%d/%s play_interaction=%s active_play_choice=%s pacer_any=%s ai_ctl=%s seats=%s" % [
		str(_choice_kind_history),
		str(deferred_summary),
		str(continuation_types),
		_controller._rule_sequence_execution_depth,
		str(_controller._active_independent_play_phase.get("phase_id", -1)),
		_controller.state.current_player_id,
		str(_controller.state.current_phase),
		str(_controller.has_pending_play_interaction()),
		str(_controller._has_active_play_choice()),
		str(_controller.game_flow_pacer.has_any_pending()) if _controller.game_flow_pacer != null else "no_pacer",
		str(_controller.ai_coordinator.is_ai_controlled(2)),
		str(seats),
	]


## 记录一条选择请求轨迹；每名玩家每次决策都会经过 card_choice_requested。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	_choice_kind_history.append("%s@%d" % [str((choice_data.get("context", {}) as Dictionary).get("kind", "")), int(choice_data.get("chooser_id", -1))])


## 返回当前待处理选择的业务种类；没有待处理选择时返回空串。
func _get_pending_choice_kind() -> String:
	if not _controller.has_pending_card_choice():
		return ""
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))


## 以本地真人身份取消当前待处理选择；取消只用于放行被占用的选择槽，不改变任何规则数值。
func _cancel_local_pending_choice() -> void:
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(_controller._pending_card_choice.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	_controller.submit_action(action)


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
	# 请求轨迹；失败信息用它定位「请求从未创建」与「请求已创建但被丢弃」两类不同缺陷。
	_controller.card_choice_requested.connect(_on_card_choice_requested)
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
