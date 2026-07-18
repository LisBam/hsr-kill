extends Node

## 性能与流程节奏专项回归。验证全局速度边界、阶段延时、历史增量同步和武将牌视觉缓存。

## 阶段间隔测试秒数；0.10秒是正式设置允许的最小值，足以观察到到期前后的状态边界。
const TEST_FLOW_INTERVAL_SECONDS: float = 0.10

## 到期后观察秒数；大于阶段间隔并留出无头模式首帧资源加载与计时调度余量。
const POST_DEADLINE_OBSERVATION_SECONDS: float = 0.18

## 专项测试使用的权威控制器；子组件与正式场景保持相同名称和职责边界。
var _controller: MatchController

## 阶段延时回调是否已经执行；默认false，用于区分同步调用与计时到期。
var _phase_transition_executed: bool = false

## 人类响应牌提示是否已经发布；默认false，用于验证权威请求可先暂停而界面提示遵守流程间隔。
var _response_prompt_published: bool = false

## 延迟一帧运行专项断言，保证自动加载数据库与全局类注册已经完成。
func _ready() -> void:
	call_deferred("_run")


## 依次验证设置、节奏、历史与视觉缓存；任一失败立即以非零状态退出。
func _run() -> void:
	if not _test_game_speed_setting():
		return
	_create_controller()
	if not await _test_phase_transition_pacing():
		return
	if not await _test_response_prompt_pacing():
		return
	if not _test_incremental_event_history():
		return
	if not await _test_player_visual_signature():
		return
	GameSettings.set_game_speed_interval_seconds(0.30)
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
	var character_definition: Dictionary = GameDatabase.get_character("trailblazer")
	# 势力静态定义；使用武将声明的稳定势力 ID，保持与正式牌桌调用一致。
	var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
	# 基础公开快照；额外历史字段模拟每次出牌都会增长但不改变武将牌画面。
	var snapshot: Dictionary = {
		"player_id":0, "display_name":"性能测试玩家", "character_id":"trailblazer", "identity":"lord",
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
	GameSettings.set_game_speed_interval_seconds(0.30)
	get_tree().quit(1)
	return false
