extends Node

## 性能与流程节奏专项回归。验证全局速度边界、阶段延时、事件历史同步、机缘增量汇总、完成事件压缩和武将牌视觉缓存。
## 界面性能同时验证相同对手座位绑定不会重复执行位置与缩放布局。
## 长局压力同时验证折叠日志零正文排版、牌面表现有界去重、机缘快照复用、事件热索引上限和出牌阶段弃牌索引。

## 阶段间隔测试秒数；0.10秒是正式设置允许的最小值，足以观察到到期前后的状态边界。
const TEST_FLOW_INTERVAL_SECONDS: float = 0.10

## 到期后观察秒数；大于阶段间隔并留出无头模式首帧资源加载与计时调度余量。
const POST_DEADLINE_OBSERVATION_SECONDS: float = 0.18

## 长局机缘历史压力条目数；4096项足以暴露全量重复汇总，同时不会让无头回归产生过长等待。
const LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT: int = 4096

## 已结束事件压缩压力条目数；8192条同步事件超过4096条热索引容量，用于验证完整GameEvent对象与快速索引都不会随历史长度增长。
const FINALIZED_EVENT_COMPACTION_COUNT: int = 8192

## 牌面表现去重压力条目数；8192个单调ID超过4096项窗口容量，用于验证重复包保护不会随对局时长永久增长。
const PRESENTATION_DEDUPLICATION_STRESS_COUNT: int = 8192

## 长局折叠日志压力条目数；4096条足以确认隐藏正文不会随完整日志长度保留排版文档。
const LONG_MATCH_LOG_ENTRY_COUNT: int = 4096

## 长局移牌历史压力条目数；8192条无关记录用于确认本回合弃牌查询只访问对应索引桶。
const LONG_CARD_MOVE_HISTORY_ENTRY_COUNT: int = 8192

## 性能回归专用设置文件；速度边界测试的所有持久化写入均与玩家正式设置隔离。
const TEST_SETTINGS_FILE_PATH: String = "user://performance_and_pacing_test_settings.cfg"

## 专项测试使用的权威控制器；子组件与正式场景保持相同名称和职责边界。
var _controller: MatchController

## 阶段延时回调是否已经执行；默认false，用于区分同步调用与计时到期。
var _phase_transition_executed: bool = false

## 人类响应牌提示是否已经发布；默认false，用于验证权威请求可先暂停而界面提示遵守流程间隔。
var _response_prompt_published: bool = false

## 测试开始前的游戏速度；测试结束恢复该原值，不再固定写回0.30秒。
var _original_game_speed_interval_seconds: float = 0.30

## 测试开始前的正式设置文件路径；测试结束后恢复供同进程其他模块继续使用。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 延迟一帧运行专项断言，保证自动加载数据库与全局类注册已经完成。
func _ready() -> void:
	call_deferred("_run")


## 依次验证设置、节奏、历史与视觉缓存；任一失败立即以非零状态退出。
func _run() -> void:
	_begin_settings_isolation()
	if not _test_game_speed_setting():
		return
	if not _test_static_text_resolution_cache():
		return
	if not await _test_collapsed_match_log_rendering():
		return
	if not _test_bounded_presentation_deduplication():
		return
	_create_controller()
	if not await _test_phase_transition_pacing():
		return
	if not await _test_response_prompt_pacing():
		return
	if not _test_incremental_event_history():
		return
	if not _test_incremental_opportunity_effect_cache():
		return
	if not _test_finalized_event_runtime_compaction():
		return
	if not _test_indexed_turn_play_discard_history():
		return
	if not await _test_repeated_opponent_layout_binding():
		return
	if not await _test_repeated_hand_layout():
		return
	if not await _test_player_visual_signature():
		return
	_restore_original_settings()
	print("PERFORMANCE_AND_PACING_PASS")
	get_tree().quit(0)


## 验证游戏速度会限制到0.1至1.0秒并按0.1秒步长对齐。
## 当前速度设置补充：AI响应速度和游戏速度均从0.10至1.00秒取值，并按0.50秒步长相对最小值对齐。
func _test_game_speed_setting() -> bool:
	if not is_equal_approx(GameSettings.MIN_GAME_SPEED_INTERVAL_SECONDS, 0.10) or not is_equal_approx(GameSettings.MAX_GAME_SPEED_INTERVAL_SECONDS, 1.00) or not is_equal_approx(GameSettings.GAME_SPEED_INTERVAL_STEP_SECONDS, 0.50):
		return _fail("game_speed_contract")
	GameSettings.set_game_speed_interval_seconds(0.01)
	if not is_equal_approx(GameSettings.game_speed_interval_seconds, 0.10):
		return _fail("game_speed_min:%s" % GameSettings.game_speed_interval_seconds)
	GameSettings.set_game_speed_interval_seconds(2.00)
	if not is_equal_approx(GameSettings.game_speed_interval_seconds, 1.00):
		return _fail("game_speed_max:%s" % GameSettings.game_speed_interval_seconds)
	GameSettings.set_game_speed_interval_seconds(0.64)
	if not is_equal_approx(GameSettings.game_speed_interval_seconds, 0.60):
		return _fail("game_speed_step:%s" % GameSettings.game_speed_interval_seconds)
	return true


## 验证静态牌名说明按名称模式缓存，并通过显示名索引直接命中卡牌定义。
func _test_static_text_resolution_cache() -> bool:
	# 当前名称模式缓存总表；测试只清理本用例专用文本，不影响其他静态说明已经建立的缓存。
	var cache_by_mode: Dictionary = GameDatabase.get("_resolved_card_text_cache_by_mode") as Dictionary
	# 当前名称模式稳定整数；原版与项目名必须维护互不污染的独立缓存。
	var mode_key: int = int(GameSettings.card_name_mode)
	# 当前模式缓存；不存在时使用新字典，并在清理测试文本后写回总表。
	var mode_cache: Dictionary = cache_by_mode.get(mode_key, {}) as Dictionary
	# 本用例专用原始说明；包含两个已登记牌名，保证解析器实际经过完整书名号查找。
	var source_text: String = "性能缓存验证：【桃】与【无懈可击】。"
	mode_cache.erase(source_text)
	cache_by_mode[mode_key] = mode_cache
	# 首次解析前缓存数量；首次调用应只新增当前完整原文一个条目。
	var initial_cache_size: int = mode_cache.size()
	# 首次解析结果；具体显示名随当前模式变化，但不能为空或丢失普通正文。
	var first_result: String = GameDatabase.resolve_card_names_in_text(source_text)
	# 首次解析后的模式缓存；用于验证条目实际被写入统一仓库。
	var first_mode_cache: Dictionary = (GameDatabase.get("_resolved_card_text_cache_by_mode") as Dictionary).get(mode_key, {}) as Dictionary
	# 重复解析结果；应直接命中缓存并保持字节级一致。
	var repeated_result: String = GameDatabase.resolve_card_names_in_text(source_text)
	# 重复解析后的缓存；相同原文不能继续增长条目数量。
	var repeated_mode_cache: Dictionary = (GameDatabase.get("_resolved_card_text_cache_by_mode") as Dictionary).get(mode_key, {}) as Dictionary
	# 原版显示名索引结果；静态名称查找必须直接返回已登记卡牌定义。
	var indexed_card_definition: Dictionary = GameDatabase.call("_find_card_by_display_name", "桃") as Dictionary
	if first_result.is_empty() or first_result != repeated_result or first_mode_cache.size() != initial_cache_size + 1 or repeated_mode_cache.size() != first_mode_cache.size() or indexed_card_definition.is_empty():
		return _fail("static_text_cache first=%s repeated=%s sizes=%d/%d/%d indexed=%s" % [first_result, repeated_result, initial_cache_size, first_mode_cache.size(), repeated_mode_cache.size(), not indexed_card_definition.is_empty()])
	return true


## 验证折叠日志只保存轻量字符串历史，展开时一次恢复完整正文，重新折叠后立即释放排版内容。
func _test_collapsed_match_log_rendering() -> bool:
	# 独立日志组件；最小子树只提供正式脚本要求的按钮、正文面板与RichTextLabel。
	var log_panel: MatchLogPanel = MatchLogPanel.new()
	log_panel.name = "PerformanceMatchLogPanel"
	# 展开按钮；唯一名称与正式场景一致，使组件无需测试专用分支即可完成ready绑定。
	var toggle_button: Button = Button.new()
	toggle_button.name = "LogToggleButton"
	toggle_button.unique_name_in_owner = true
	log_panel.add_child(toggle_button)
	toggle_button.owner = log_panel
	# 正文容器；折叠状态由组件直接控制其visible属性。
	var content_panel: PanelContainer = PanelContainer.new()
	content_panel.name = "LogContentPanel"
	content_panel.unique_name_in_owner = true
	log_panel.add_child(content_panel)
	content_panel.owner = log_panel
	# 日志正文；压力测试检查折叠后解析文本为空，而完整条目仍保留在组件数组。
	var log_view: RichTextLabel = RichTextLabel.new()
	log_view.name = "LogView"
	log_view.unique_name_in_owner = true
	content_panel.add_child(log_view)
	log_view.owner = log_panel
	add_child(log_panel)
	await get_tree().process_frame
	# 压力日志序号；每项生成不同文本以避免正文控件通过重复字符串偶然复用布局。
	for entry_index: int in range(LONG_MATCH_LOG_ENTRY_COUNT):
		log_panel.append_entry("长局日志性能记录%d" % entry_index)
	if log_panel.get_entry_count() != LONG_MATCH_LOG_ENTRY_COUNT or log_panel.get_rendered_character_count() != 0:
		log_panel.queue_free()
		return _fail("collapsed_log retained=%d rendered=%d" % [log_panel.get_entry_count(), log_panel.get_rendered_character_count()])
	log_panel.set_expanded(true)
	if log_panel.get_entry_count() != LONG_MATCH_LOG_ENTRY_COUNT or log_panel.get_rendered_character_count() <= LONG_MATCH_LOG_ENTRY_COUNT:
		log_panel.queue_free()
		return _fail("expanded_log retained=%d rendered=%d" % [log_panel.get_entry_count(), log_panel.get_rendered_character_count()])
	log_panel.append_entry("同帧批量追加甲")
	log_panel.append_entry("同帧批量追加乙")
	await get_tree().process_frame
	# 展开后的完整文本；两条同帧日志必须在一次延迟刷新后保持原到达顺序。
	var expanded_text: String = log_view.get_parsed_text()
	if not expanded_text.ends_with("同帧批量追加甲\n同帧批量追加乙\n"):
		log_panel.queue_free()
		return _fail("expanded_log_batch_tail")
	log_panel.set_expanded(false)
	if log_panel.get_entry_count() != LONG_MATCH_LOG_ENTRY_COUNT + 2 or log_panel.get_rendered_character_count() != 0:
		log_panel.queue_free()
		return _fail("collapsed_log_release retained=%d rendered=%d" % [log_panel.get_entry_count(), log_panel.get_rendered_character_count()])
	log_panel.queue_free()
	return true


## 验证表现ID只保留固定最近窗口，同时继续拒绝窗口内重复ID与已经淘汰的远古重发ID。
func _test_bounded_presentation_deduplication() -> bool:
	# 独立牌面表现组件；本用例只测试表现包幂等登记，不创建任何CardView或补间。
	var animation_layer: CardUseAnimationLayer = CardUseAnimationLayer.new()
	# 单调表现ID；从1写至8192，保证固定窗口至少完成一次覆盖并保留稳定最高序号。
	for presentation_id: int in range(1, PRESENTATION_DEDUPLICATION_STRESS_COUNT + 1):
		if not animation_layer.claim_presentation(presentation_id, -1, false):
			animation_layer.free()
			return _fail("presentation_dedup_initial id=%d" % presentation_id)
	# 当前窗口条目数；超过容量的旧ID必须已经从字典与环形槽位共同淘汰。
	var remembered_count: int = animation_layer.get_remembered_presentation_id_count()
	if remembered_count != CardUseAnimationLayer.PRESENTATION_DEDUPLICATION_CAPACITY:
		animation_layer.free()
		return _fail("presentation_dedup_capacity count=%d" % remembered_count)
	if animation_layer.claim_presentation(PRESENTATION_DEDUPLICATION_STRESS_COUNT, -1, false):
		animation_layer.free()
		return _fail("presentation_dedup_recent_duplicate")
	if animation_layer.claim_presentation(1, -1, false):
		animation_layer.free()
		return _fail("presentation_dedup_stale_duplicate")
	animation_layer.clear_presentations()
	if animation_layer.get_remembered_presentation_id_count() != 0 or not animation_layer.claim_presentation(1, -1, false):
		animation_layer.free()
		return _fail("presentation_dedup_reset")
	animation_layer.free()
	return true


## 创建最小控制器组件树；规则状态由各用例显式注入，避免启动完整身份局引入随机因素。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；控制器初始化时要求该稳定子节点名称。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；本组只查询有效等待时间，不执行策略动作。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网络网关；状态广播保持本地只读路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.game_flow_interval_seconds = TEST_FLOW_INTERVAL_SECONDS
	_controller.ai_action_delay_seconds = 0.05
	_controller.card_choice_requested.connect(_on_card_choice_requested)


## 验证阶段切换在间隔到期前保持原阶段，并且自动响应实际等待不会快于全局游戏速度。
func _test_phase_transition_pacing() -> bool:
	# 最小权威状态；单名玩家足以验证控制器的对局、角色和阶段失效保护。
	var game_state: GameState = GameState.new()
	game_state.match_id = "performance-pacing"
	game_state.current_player_id = 0
	game_state.current_phase = "start"
	# 当前测试玩家；阶段保护只读取稳定玩家 ID，体力使用标准默认值。
	var player: PlayerState = PlayerState.new(0, "节奏测试玩家")
	game_state.players.append(player)
	_controller.state = game_state
	_phase_transition_executed = false
	_controller._schedule_phase_transition(0, "start", Callable(self, "_mark_phase_transition").bind(_controller))
	if _phase_transition_executed or game_state.current_phase != "start" or not _controller.game_flow_pacer.has_pending("phase_transition"):
		return _fail("phase_transition_started_early")
	await get_tree().create_timer(POST_DEADLINE_OBSERVATION_SECONDS).timeout
	if not _phase_transition_executed or game_state.current_phase != "judgment" or _controller.game_flow_pacer.has_pending("phase_transition"):
		return _fail("phase_transition_not_completed")
	# 自动响应有效等待；AI独立值更小时仍必须使用全局流程间隔作为下限。
	var effective_ai_delay: float = float(_controller.call("_get_effective_ai_response_delay_seconds"))
	if not is_equal_approx(effective_ai_delay, TEST_FLOW_INTERVAL_SECONDS):
		return _fail("effective_ai_delay:%s" % effective_ai_delay)
	return true


## 阶段测试回调；只修改测试状态，用于确认节奏组件没有承担任何规则决策。
func _mark_phase_transition(controller: MatchController) -> void:
	_phase_transition_executed = true
	controller.state.current_phase = "judgment"


## 验证人类响应请求先暂停规则流程，并在游戏速度间隔到期后才向界面发布。
func _test_response_prompt_pacing() -> bool:
	_controller.event_scheduler.reset()
	_controller.state.current_phase = "play"
	_controller.state.current_choice_request.clear()
	_controller._pending_card_choice.clear()
	_response_prompt_published = false
	# 响应上下文；非空响应模式会把普通选牌规范化为 chooseToRespond 窗口。
	var response_context: Dictionary = {"kind":"pacing_response", "response_patterns":["shan"]}
	_controller.request_card_choice(0, "响应询问", "是否响应？", [], 0, 1, true, response_context)
	if not _controller.has_pending_card_choice() or _response_prompt_published:
		return _fail("response_prompt_started_early")
	await get_tree().create_timer(POST_DEADLINE_OBSERVATION_SECONDS).timeout
	if not _response_prompt_published:
		return _fail("response_prompt_not_published")
	_controller.game_flow_pacer.cancel_all()
	_controller._pending_card_choice.clear()
	_controller.event_scheduler.reset()
	return true


## 记录界面兼容选择请求；本专项只创建一条人类响应请求，不需要区分请求类型。
func _on_card_choice_requested(_choice_data: Dictionary) -> void:
	_response_prompt_published = true


## 验证事件历史在条目数一致时不被整段替换，失配时仍能通过全量校准恢复正确数据。
func _test_incremental_event_history() -> bool:
	_controller.event_scheduler.reset()
	_controller.state.event_history.clear()
	_controller._record_runtime_event("performance_probe", "test", {"value":1})
	if _controller.state.event_history.size() != _controller.event_scheduler.get_event_history_count():
		return _fail("history_incremental_count")
	# 广播前历史引用；追加探针可验证计数一致路径没有用深拷贝替换整个数组。
	var history_reference: Array[Dictionary] = _controller.state.event_history
	_controller._emit_state()
	# 引用探针记录；只存在于测试状态，验证后立即删除，不进入事件调度器历史。
	var reference_probe: Dictionary = {"sequence":999999, "kind":"reference_probe"}
	history_reference.append(reference_probe)
	if _controller.state.event_history.size() != _controller.event_scheduler.get_event_history_count() + 1:
		return _fail("history_reference_replaced")
	history_reference.pop_back()
	_controller.state.event_history.clear()
	_controller._emit_state()
	if _controller.state.event_history.size() != _controller.event_scheduler.get_event_history_count():
		return _fail("history_reconciliation")
	return true


## 验证长机缘历史只在首次查询时汇总，后续不同效果查询与单条新增均复用同一增量缓存。
func _test_incremental_opportunity_effect_cache() -> bool:
	# 独立权威状态；本用例只测试机缘数值查询，不进入阶段、AI或事件流程。
	var game_state: GameState = GameState.new()
	# 长局测试玩家；全部机缘记录按正式追加语义写入同一历史数组。
	var player: PlayerState = PlayerState.new(0, "机缘缓存测试玩家")
	game_state.players.append(player)
	_controller.state = game_state
	for history_index: int in range(LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT):
		# 交替写入【杀】次数与伤害加成；两个效果可验证首次查询会一次构建全部effect累计值。
		player.acquired_opportunity_ids.append("green_slash_play_limit_one" if history_index % 2 == 0 else "orange_damage_one")
	# 首次【杀】加成查询；应处理完整历史并得到一半条目对应的累计数值。
	var expected_half_count: int = LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT / 2
	var slash_bonus: int = _controller.get_acquired_opportunity_effect_total(player.player_id, "slash_play_limit_bonus")
	if slash_bonus != expected_half_count or player.opportunity_effect_cache_processed_count != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT:
		return _fail("opportunity_cache_initial total=%d processed=%d" % [slash_bonus, player.opportunity_effect_cache_processed_count])
	# 不同效果查询；首次扫描已经同时汇总全部效果，因此处理位置不得再次变化。
	var damage_bonus: int = _controller.get_acquired_opportunity_effect_total(player.player_id, "damage_bonus")
	if damage_bonus != expected_half_count or player.opportunity_effect_cache_processed_count != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT:
		return _fail("opportunity_cache_reuse total=%d processed=%d" % [damage_bonus, player.opportunity_effect_cache_processed_count])
	# 首次公开快照；长机缘历史只在源数据变化时复制一次，后续不同观察者复用同一只读数组。
	var first_player_snapshot: Dictionary = player.to_dict(player.player_id, false)
	# 第二次公开快照；历史没有变化时不得再次分配和复制4096项数组。
	var repeated_player_snapshot: Dictionary = player.to_dict(-1, false)
	if player.get_acquired_opportunity_snapshot_rebuild_count() != 1 or (first_player_snapshot.get("acquired_opportunity_ids", []) as Array).size() != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT or (repeated_player_snapshot.get("acquired_opportunity_ids", []) as Array).size() != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT:
		return _fail("opportunity_snapshot_reuse rebuilds=%d" % player.get_acquired_opportunity_snapshot_rebuild_count())
	player.acquired_opportunity_ids.append("green_slash_play_limit_one")
	# 单条追加后的结果；查询只消费新增尾项并把处理位置精确推进1。
	var appended_slash_bonus: int = _controller.get_acquired_opportunity_effect_total(player.player_id, "slash_play_limit_bonus")
	if appended_slash_bonus != expected_half_count + 1 or player.opportunity_effect_cache_processed_count != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT + 1:
		return _fail("opportunity_cache_append total=%d processed=%d" % [appended_slash_bonus, player.opportunity_effect_cache_processed_count])
	# 追加后的新快照；只重建一次新数组，已经发出的旧快照仍保持原长度，不会被原地改写。
	var appended_player_snapshot: Dictionary = player.to_dict(player.player_id, false)
	if player.get_acquired_opportunity_snapshot_rebuild_count() != 2 or (first_player_snapshot.get("acquired_opportunity_ids", []) as Array).size() != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT or (appended_player_snapshot.get("acquired_opportunity_ids", []) as Array).size() != LONG_OPPORTUNITY_HISTORY_ENTRY_COUNT + 1:
		return _fail("opportunity_snapshot_refresh rebuilds=%d" % player.get_acquired_opportunity_snapshot_rebuild_count())
	# 替换前中段ID；本次修改保持数组长度、首项和尾项不变，专门验证正式整体替换所需的显式失效端口。
	var previous_middle_id: String = player.acquired_opportunity_ids[1]
	player.acquired_opportunity_ids[1] = "green_slash_play_limit_one"
	player.invalidate_acquired_opportunity_snapshot_cache()
	# 整体替换后的公开快照；必须生成第三个新数组，而不能依赖长度或首尾哨兵误复用旧缓存。
	var replacement_player_snapshot: Dictionary = player.to_dict(player.player_id, false)
	if player.get_acquired_opportunity_snapshot_rebuild_count() != 3 or str((appended_player_snapshot.get("acquired_opportunity_ids", []) as Array)[1]) != previous_middle_id or str((replacement_player_snapshot.get("acquired_opportunity_ids", []) as Array)[1]) != "green_slash_play_limit_one":
		return _fail("opportunity_snapshot_invalidation rebuilds=%d" % player.get_acquired_opportunity_snapshot_rebuild_count())
	return true


## 验证同步完成事件只留下可序列化摘要，长期根事件之外不保留带Callable的完整运行时对象。
func _test_finalized_event_runtime_compaction() -> bool:
	_controller.event_scheduler.reset()
	# 长期根事件；正式对局同样只应持续保留这一完整运行时对象。
	var root_event: GameEvent = _controller.event_scheduler.create_event("PerformanceRoot", "root")
	if not _controller.event_scheduler.begin_root(root_event.event_id, true):
		return _fail("event_compaction_root")
	# 首条记录事件ID；压力结束后仍须能从轻量归档取得最终摘要。
	var first_recorded_event_id: int = -1
	for event_index: int in range(FINALIZED_EVENT_COMPACTION_COUNT):
		# 同步历史事件；上下文包含基础数据以确认归档不是空占位。
		var recorded_event_id: int = _controller.event_scheduler.record_event("performance_record_%d" % event_index, "test", {"index":event_index}, root_event.event_id)
		if first_recorded_event_id < 0:
			first_recorded_event_id = recorded_event_id
	# 首条归档摘要；即使已经移出热索引，完成状态、finalized标记和原始上下文仍必须可从完整历史恢复。
	var first_snapshot: Dictionary = _controller.event_scheduler.get_event_snapshot(first_recorded_event_id)
	if _controller.event_scheduler.get_live_event_count() != 1 or _controller.event_scheduler.get_finalized_event_snapshot_cache_count() != EventScheduler.FINALIZED_EVENT_SNAPSHOT_CACHE_CAPACITY or str(first_snapshot.get("status", "")) != "finished" or not bool(first_snapshot.get("finalized", false)) or int((first_snapshot.get("context", {}) as Dictionary).get("index", -1)) != 0:
		return _fail("event_compaction live=%d cache=%d snapshot=%s" % [_controller.event_scheduler.get_live_event_count(), _controller.event_scheduler.get_finalized_event_snapshot_cache_count(), first_snapshot])
	return true


## 验证长局移牌历史会在服务创建时建立回合索引，候选查询只读取目标回合的短UID桶。
func _test_indexed_turn_play_discard_history() -> bool:
	# 独立权威状态；无关历史记录模拟多次洗牌后的长局移动规模。
	var game_state: GameState = GameState.new()
	# 无关移牌历史序号；每项都属于摸牌阶段，不应进入任何出牌阶段弃牌索引桶。
	for history_index: int in range(LONG_CARD_MOVE_HISTORY_ENTRY_COUNT):
		game_state.card_move_history.append({
			"move_id":history_index + 1,
			"card_ids":[history_index + 1],
			"from_zone":"draw_pile",
			"to_zone":"hand",
			"turn_number":history_index + 1,
			"turn_player_id":0,
			"phase":"draw",
		})
	# 目标全局回合；与压力历史回合号分离，保证索引桶只含后方两项。
	var target_turn_number: int = LONG_CARD_MOVE_HISTORY_ENTRY_COUNT + 1
	# 第一张目标弃牌；黑桃实体用于验证无花色筛选时保持原进入顺序。
	var first_card: CardInstance = CardInstance.new("sha", "spade", 7, LONG_CARD_MOVE_HISTORY_ENTRY_COUNT + 101)
	first_card.zone = "discard_pile"
	# 第二张目标弃牌；红桃实体用于验证指定花色只过滤当前短桶。
	var second_card: CardInstance = CardInstance.new("tao", "heart", 3, LONG_CARD_MOVE_HISTORY_ENTRY_COUNT + 102)
	second_card.zone = "discard_pile"
	game_state.discard_pile = [first_card, second_card]
	game_state.card_move_history.append({
		"move_id":LONG_CARD_MOVE_HISTORY_ENTRY_COUNT + 1,
		"card_ids":[first_card.uid],
		"from_zone":"processing",
		"to_zone":"discard_pile",
		"turn_number":target_turn_number,
		"turn_player_id":0,
		"phase":"play",
	})
	game_state.card_move_history.append({
		"move_id":LONG_CARD_MOVE_HISTORY_ENTRY_COUNT + 2,
		"card_ids":[second_card.uid],
		"from_zone":"hand",
		"to_zone":"discard_pile",
		"turn_number":target_turn_number,
		"turn_player_id":0,
		"phase":"play",
	})
	_controller.state = game_state
	_controller.card_movement = CardMovementService.new(game_state)
	# 全花色候选；必须只包含目标桶中的两张牌，且顺序与历史首次进入顺序一致。
	var all_candidates: Array[Dictionary] = _controller.get_turn_play_discard_candidates(0, target_turn_number, 0)
	# 红桃候选；筛选在索引读取后执行，只保留第二张实体。
	var heart_candidates: Array[Dictionary] = _controller.get_turn_play_discard_candidates(0, target_turn_number, 0, "heart")
	if _controller.card_movement.get_turn_play_discard_indexed_count(target_turn_number, 0) != 2 \
			or int(_controller.card_movement.get("_next_move_id")) != LONG_CARD_MOVE_HISTORY_ENTRY_COUNT + 3 \
			or all_candidates.size() != 2 \
			or int(all_candidates[0].get("uid", -1)) != first_card.uid \
			or int(all_candidates[1].get("uid", -1)) != second_card.uid \
			or heart_candidates.size() != 1 \
			or int(heart_candidates[0].get("uid", -1)) != second_card.uid:
		return _fail("play_discard_index bucket=%d next_move=%d all=%s heart=%s" % [_controller.card_movement.get_turn_play_discard_indexed_count(target_turn_number, 0), int(_controller.card_movement.get("_next_move_id")), all_candidates, heart_candidates])
	return true


## 验证节点身份、顺序和总人数均未变化时跳过座位重排，而真实顺序变化仍会触发布局。
func _test_repeated_opponent_layout_binding() -> bool:
	# 独立环桌布局组件；固定尺寸保证无头环境可以实际写入座位位置。
	var battle_layout: DecadeBattleLayout = DecadeBattleLayout.new()
	battle_layout.size = Vector2(1000.0, 600.0)
	add_child(battle_layout)
	# 第一名测试对手座位；标准尺寸只用于产生稳定布局坐标。
	var first_opponent: Control = Control.new()
	first_opponent.size = Vector2(148.0, 224.0)
	battle_layout.add_child(first_opponent)
	# 第二名测试对手座位；与首名尺寸一致以隔离绑定缓存行为。
	var second_opponent: Control = Control.new()
	second_opponent.size = Vector2(148.0, 224.0)
	battle_layout.add_child(second_opponent)
	await get_tree().process_frame
	# 初始绑定数组；顺序对应本地玩家之后的环形座次。
	var opponent_views: Array[Control] = [first_opponent, second_opponent]
	battle_layout.bind_opponent_views(opponent_views, 3)
	# 初次有效布局序号；必须至少执行一次。
	var initial_revision: int = battle_layout.get_layout_revision()
	battle_layout.bind_opponent_views(opponent_views, 3)
	# 重复绑定序号；节点集合完全相同时应保持不变。
	var repeated_revision: int = battle_layout.get_layout_revision()
	# 反向顺序数组；真实座次顺序变化必须使缓存失效并重新布局。
	var reordered_views: Array[Control] = [second_opponent, first_opponent]
	battle_layout.bind_opponent_views(reordered_views, 3)
	# 重排后的序号；应严格大于重复绑定后的值。
	var reordered_revision: int = battle_layout.get_layout_revision()
	battle_layout.queue_free()
	if initial_revision <= 0 or repeated_revision != initial_revision or reordered_revision <= repeated_revision:
		return _fail("opponent_layout_cache:%d/%d/%d" % [initial_revision, repeated_revision, reordered_revision])
	return true


## 验证手牌结构未变化时跳过重复位置计算，而可视宽度变化会让布局签名正常失效。
func _test_repeated_hand_layout() -> bool:
	# 手牌可视父节点；容器按该宽度计算展开、覆盖或滚动布局。
	var hand_parent: Control = Control.new()
	hand_parent.size = Vector2(640.0, 175.0)
	add_child(hand_parent)
	# 独立手牌容器；空手牌同样需要维护稳定最小尺寸，因此足以验证结构签名缓存。
	var hand_layout: DecadeHandContainer = DecadeHandContainer.new()
	hand_parent.add_child(hand_layout)
	await get_tree().process_frame
	hand_layout.layout_cards_now()
	# 首次有效布局序号；进入场景树后的排队布局可能已经完成，记录当前稳定值即可。
	var initial_revision: int = hand_layout.get_layout_revision()
	hand_layout.layout_cards_now()
	# 重复布局序号；没有卡牌、尺寸或配置变化时必须保持不变。
	var repeated_revision: int = hand_layout.get_layout_revision()
	hand_parent.size.x = 720.0
	hand_layout.layout_cards_now()
	# 宽度变化后的序号；可用空间属于布局输入，必须触发一次真实重新计算。
	var resized_revision: int = hand_layout.get_layout_revision()
	hand_parent.queue_free()
	if initial_revision <= 0 or repeated_revision != initial_revision or resized_revision <= repeated_revision:
		return _fail("hand_layout_cache:%d/%d/%d" % [initial_revision, repeated_revision, resized_revision])
	return true


## 验证仅用牌历史变化不会重建武将牌体力节点，而真实体力变化仍会正确刷新视觉签名。
func _test_player_visual_signature() -> bool:
	# 正式武将牌场景；专项测试直接检查持续节点身份，不依赖牌桌的其他区域。
	var player_view_scene: PackedScene = load("res://scenes/components/player_target_view.tscn") as PackedScene
	if player_view_scene == null:
		return _fail("player_view_scene_load")
	# 武将牌实例；进入场景树后体力点与装备层均按正式逻辑创建。
	var player_view: PlayerTargetView = player_view_scene.instantiate() as PlayerTargetView
	add_child(player_view)
	await get_tree().process_frame
	# 武将静态定义；视觉签名必须保留该配置与主题、名称模式的缓存失效能力。
	var character_definition: Dictionary = GameDatabase.get_character("gepard")
	# 势力静态定义；使用武将声明的稳定势力 ID，保持与正式牌桌调用一致。
	var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
	# 基础公开快照；额外历史字段模拟每次出牌都会增长但不改变武将牌画面。
	var snapshot: Dictionary = {
		"player_id":0, "display_name":"性能测试玩家", "character_id":"gepard", "identity":"leader",
		"hp":4, "max_hp":4, "shield":0, "alive":true, "chained":false, "face_down":false,
		"hand_count":4, "equipment":{}, "judgment_area":[], "wooden_ox_storage_count":0,
		"card_use_history":[], "play_phase_card_use_history":[], "response_history_count":0,
	}
	player_view.configure_snapshot(snapshot, character_definition, false, faction_definition)
	# 初始视觉签名；历史变化后应保持完全一致。
	var initial_signature: int = int(player_view.get("_configuration_signature"))
	# 初始体力点节点；同一画面刷新必须持续复用该实例，不能排队释放后重新创建。
	var health_pips: VBoxContainer = player_view.get_node("HealthFrame/HealthPips") as VBoxContainer
	var initial_pip: Node = health_pips.get_child(0)
	# 只有非视觉历史发生变化的新快照；公开画面字段与静态定义保持不变。
	var history_only_snapshot: Dictionary = snapshot.duplicate(true)
	history_only_snapshot["card_use_history"] = [{"definition_id":"sha"}]
	history_only_snapshot["play_phase_card_use_history"] = [{"definition_id":"sha"}]
	player_view.configure_snapshot(history_only_snapshot, character_definition, false, faction_definition)
	if int(player_view.get("_configuration_signature")) != initial_signature or health_pips.get_child(0) != initial_pip:
		return _fail("non_visual_history_rebuilt_player")
	# 真实体力变化快照；必须改变签名并创建符合新体力值的视觉节点。
	var damaged_snapshot: Dictionary = history_only_snapshot.duplicate(true)
	damaged_snapshot["hp"] = 3
	player_view.configure_snapshot(damaged_snapshot, character_definition, false, faction_definition)
	if int(player_view.get("_configuration_signature")) == initial_signature or health_pips.get_child(0) == initial_pip:
		return _fail("visual_change_not_refreshed")
	player_view.queue_free()
	return true


## 输出稳定失败原因并以非零状态退出；返回false便于调用方立即停止后续断言。
func _fail(reason: String) -> bool:
	printerr("PERFORMANCE_AND_PACING_FAIL %s" % reason)
	_restore_original_settings()
	get_tree().quit(1)
	return false


## 保存玩家原设置并把测试写盘路径切换到独立文件；即使中途失败也不会覆盖正式配置。
func _begin_settings_isolation() -> void:
	if GameSettings == null:
		return
	_original_game_speed_interval_seconds = GameSettings.game_speed_interval_seconds
	_original_settings_file_path = GameSettings.get_settings_file_path()
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)


## 恢复测试前速度、刷新临时文件并删除它；正式设置路径只在全部待保存变化清空后恢复。
func _restore_original_settings() -> void:
	if GameSettings == null:
		return
	GameSettings.set_game_speed_interval_seconds(_original_game_speed_interval_seconds)
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))
