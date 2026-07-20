extends Node

## 空白点击关闭浮层专项回归测试。使用正式主场景验证离线日志暂停后，真实未处理左键仍能同时关闭记录和局内菜单。

## 主场景完成子节点初始化所需的等待帧数；默认2帧足以建立日志、菜单与牌桌信号连接。
const SETTLE_FRAME_COUNT: int = 2


## 以始终处理模式运行测试驱动，确保日志展开暂停场景树后仍可发送输入和完成断言。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 构建正式牌桌，打开离线日志和菜单后向空白区域发送真实左键，验证两个浮层与暂停令牌都被收起。
func _run() -> void:
	# 正式主场景资源；专项测试必须验证与玩家运行一致的节点层级与输入传播。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；作为测试根节点子节点运行，使日志和菜单完成真实信号连接。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 启动主菜单；测试不进入正式对局，因此隐藏启动遮罩以允许牌桌关闭入口处理空白点击。
	var main_menu: MainMenu = main_instance.get_node("MainMenu") as MainMenu
	main_menu.visible = false
	# 对局记录组件；它在离线暂停后仍以始终处理模式接收未被 GUI 消费的输入。
	var log_panel: MatchLogPanel = main_instance.get_node("LogPanel") as MatchLogPanel
	# 局内菜单组件；直接展开后应由与记录相同的关闭入口同步收起。
	var match_menu: MatchMenu = main_instance.get_node("MatchMenu") as MatchMenu
	# 权威控制器；只读取其暂停服务状态，确认日志关闭时令牌完整释放。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	log_panel.set_expanded(true)
	match_menu.set_menu_open(true)
	if not log_panel.is_expanded() or not match_menu.is_menu_open() or not get_tree().paused or not match_controller.is_gameplay_paused():
		_fail("overlay_setup expanded=%s menu=%s paused=%s gameplay=%s" % [log_panel.is_expanded(), match_menu.is_menu_open(), get_tree().paused, match_controller.is_gameplay_paused()])
		return
	# 空白区域左键；坐标位于默认视口中央，不命中左下日志、右上菜单或其他可交互控件。
	var blank_click_event: InputEventMouseButton = InputEventMouseButton.new()
	blank_click_event.button_index = MOUSE_BUTTON_LEFT
	blank_click_event.pressed = true
	blank_click_event.position = Vector2(576.0, 324.0)
	Input.parse_input_event(blank_click_event)
	await get_tree().process_frame
	if log_panel.is_expanded() or match_menu.is_menu_open() or get_tree().paused or match_controller.is_gameplay_paused():
		_fail("overlay_blank_close expanded=%s menu=%s paused=%s gameplay=%s" % [log_panel.is_expanded(), match_menu.is_menu_open(), get_tree().paused, match_controller.is_gameplay_paused()])
		return
	# 仅展开局内菜单；不暂停时由牌桌本体接收同一空白输入，验证主根忽略鼠标后事件能进入未处理回调。
	match_menu.set_menu_open(true)
	Input.parse_input_event(blank_click_event)
	await get_tree().process_frame
	if match_menu.is_menu_open():
		_fail("menu_only_blank_close menu=%s" % match_menu.is_menu_open())
		return
	print("OVERLAY_BLANK_CLOSE_PASS")
	get_tree().quit(0)


## 输出首个失败原因并结束测试进程，防止后续异步回调覆盖定位信息。
func _fail(message: String) -> void:
	printerr("OVERLAY_BLANK_CLOSE_FAIL %s" % message)
	get_tree().quit(1)
