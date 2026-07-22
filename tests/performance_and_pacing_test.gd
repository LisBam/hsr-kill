extends Node

## 性能与流程节奏专项回归。验证全局速度边界、阶段延时、历史增量同步和武将牌视觉缓存。
## 界面性能同时验证相同对手座位绑定不会重复执行位置与缩放布局。

## 阶段间隔测试秒数；0.10秒是正式设置允许的最小值，足以观察到到期前后的状态边界。
const TEST_FLOW_INTERVAL_SECONDS: float = 0.10

## 到期后观察秒数；大于阶段间隔并留出无头模式首帧资源加载与计时调度余量。
const POST_DEADLINE_OBSERVATION_SECONDS: float = 0.18

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
	_create_controller()
	if not await _test_phase_transition_pacing():
		return
	if not await _test_response_prompt_pacing():
		return
	if not _test_incremental_event_history():
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
func _test_game_speed_setting() -> bool:
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
