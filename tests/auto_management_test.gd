extends Node

## 玩家托管专项回归测试。覆盖权威托管状态、AI 注册与释放、离线文案以及手牌滤镜的输入拦截和动态文字。

## 托管文字动画的等待秒数；略高于组件默认0.45秒，确保无头环境至少发生一次省略号变化。
const DOT_ANIMATION_WAIT_SECONDS: float = 0.52

## 测试使用的权威对局控制器；子节点结构与正式场景一致，避免绕过网络和 AI 依赖。
var _controller: MatchController


## 延迟执行断言，确保自动加载数据库和组件场景已完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证托管权威状态与独立 UI 覆盖组件；任一失败立即以非零状态退出。
func _run() -> void:
	_create_controller()
	if not _test_authoritative_auto_management():
		return
	if not await _test_auto_management_ui_components():
		return
	print("AUTO_MANAGEMENT_PASS")
	get_tree().quit(0)


## 创建完整控制器依赖并注入最小二人权威状态；测试不启动真实回合或异步 AI 出牌。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；控制器 ready 时需要该节点构造时机服务。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；托管开关必须通过该正式节点注册和注销基础策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；保留正式控制器的动作协议，但不建立 ENet 会话。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.state = GameState.new()
	_controller.state.match_id = "auto-management-test"
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	# 本地玩家状态；手动托管只允许该稳定玩家 ID 通过标准动作开启或关闭。
	var local_player: PlayerState = PlayerState.new(0, "本地玩家")
	# 另一名普通玩家状态；用于验证托管快照不依赖单人对局。
	var other_player: PlayerState = PlayerState.new(1, "其他玩家")
	_controller.state.players = [local_player, other_player]


## 验证手动托管、取消托管与离线托管均修改同一份 PlayerState 并同步基础 AI 注册状态。
func _test_authoritative_auto_management() -> bool:
	# 开启托管的标准动作；真实 UI 和 LAN 客户端都使用同一个 action_type 与 enabled 字段。
	var enable_action: PlayerAction = PlayerAction.new("set_auto_managed", 0)
	enable_action.payload = {"enabled":true}
	if not _controller.submit_action(enable_action):
		return _fail("enable_action_rejected")
	# 已托管玩家状态；快照字段、控制器查询和 AI 注册必须同时成立。
	var local_player: PlayerState = _controller.state.get_player(0)
	# 本地观察者快照；所有 UI 通过此副本读取托管状态，不引用 PlayerState 实例。
	var local_snapshot: Dictionary = _controller.state.to_dict(0, false)
	# 快照中的本地玩家；二人数组按座次保存，此处显式读取第一项防止测试忽略序列化边界。
	var local_player_snapshot: Dictionary = local_snapshot.get("players", [])[0] as Dictionary
	if not local_player.auto_managed or local_player.auto_managed_offline or not _controller.is_player_auto_managed(0) or not _controller.ai_coordinator.is_ai_controlled(0) or not bool(local_player_snapshot.get("auto_managed", false)) or bool(local_player_snapshot.get("auto_managed_offline", true)):
		return _fail("manual_state=%s snapshot=%s" % [local_player.to_dict(0, true), local_player_snapshot])
	# 取消托管的标准动作；必须移除 AI，而不是只隐藏本地黑色滤镜。
	var disable_action: PlayerAction = PlayerAction.new("set_auto_managed", 0)
	disable_action.payload = {"enabled":false}
	if not _controller.submit_action(disable_action) or local_player.auto_managed or _controller.ai_coordinator.is_ai_controlled(0):
		return _fail("disable_action")
	# 模拟 LAN 掉线调用的内部状态入口；掉线托管要求显示专属文案，且玩家不能再自行关闭。
	_controller._set_player_auto_management(0, true, true)
	var offline_disable_action: PlayerAction = PlayerAction.new("set_auto_managed", 0)
	offline_disable_action.payload = {"enabled":false}
	if not local_player.auto_managed or not local_player.auto_managed_offline or _controller.submit_action(offline_disable_action):
		return _fail("offline_management_state")
	return true


## 验证手牌滤镜会拦截输入并循环省略号，且武将牌底部状态同时显示“已离线，托管中”。
func _test_auto_management_ui_components() -> bool:
	# 手牌托管覆盖场景；组件不依赖 MatchController，可作为手牌栏子节点独立复用。
	var overlay_scene: PackedScene = load("res://scenes/components/player_auto_managed_hand_overlay.tscn") as PackedScene
	if overlay_scene == null:
		return _fail("overlay_scene_missing")
	# 覆盖组件实例；加入场景树后验证真实 _ready 与始终处理动画。
	var overlay: PlayerAutoManagedHandOverlay = overlay_scene.instantiate() as PlayerAutoManagedHandOverlay
	add_child(overlay)
	await get_tree().process_frame
	overlay.configure(true)
	var first_status: String = (overlay.get_node("StatusLabel") as Label).text
	if not overlay.visible or overlay.mouse_filter != Control.MOUSE_FILTER_STOP or first_status != "托管中.":
		return _fail("overlay_enable visible=%s filter=%d text=%s" % [overlay.visible, overlay.mouse_filter, first_status])
	await get_tree().create_timer(DOT_ANIMATION_WAIT_SECONDS).timeout
	var animated_status: String = (overlay.get_node("StatusLabel") as Label).text
	if animated_status == first_status or not animated_status.begins_with("托管中"):
		return _fail("overlay_animation=%s" % animated_status)
	overlay.configure(false)
	if overlay.visible or overlay.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return _fail("overlay_disable")
	# 正式武将牌场景；托管标签必须由公开快照渲染，并携带描边配置。
	var player_view_scene: PackedScene = load("res://scenes/components/player_target_view.tscn") as PackedScene
	if player_view_scene == null:
		return _fail("player_view_scene_missing")
	var player_view: PlayerTargetView = player_view_scene.instantiate() as PlayerTargetView
	add_child(player_view)
	await get_tree().process_frame
	var offline_snapshot: Dictionary = {
		"player_id":1,
		"display_name":"离线玩家",
		"character_id":"",
		"identity":"hidden",
		"hp":4,
		"max_hp":4,
		"shield":0,
		"alive":true,
		"chained":false,
		"face_down":false,
		"auto_managed":true,
		"auto_managed_offline":true,
		"hand_count":0,
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage_count":0,
	}
	player_view.configure_snapshot(offline_snapshot)
	player_view.set_match_overlays_visible(true)
	var auto_managed_label: Label = player_view.get_node("AutoManagedLabel") as Label
	if auto_managed_label == null or not auto_managed_label.visible or auto_managed_label.text != "已离线，托管中" or auto_managed_label.get_theme_constant("outline_size") <= 0:
		return _fail("player_view_label=%s" % [auto_managed_label])
	overlay.queue_free()
	player_view.queue_free()
	return true


## 输出稳定失败标识并立即结束测试；失败后不继续执行后续异步断言。
func _fail(reason: String) -> bool:
	printerr("AUTO_MANAGEMENT_FAIL %s" % reason)
	if _controller != null and is_instance_valid(_controller):
		_controller.queue_free()
	get_tree().quit(1)
	return false
