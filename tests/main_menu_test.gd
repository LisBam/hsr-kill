extends Node

## 主菜单回归测试。验证游戏启动先进入主菜单，设置与开始游戏共用标准身份局的统一开局入口。

## 主菜单与牌桌完成信号连接、主题刷新及开局状态广播前等待的帧数；默认6帧覆盖无头模式下的延迟布局。
const SETTLE_FRAME_COUNT: int = 6


## 延迟执行主菜单测试；保证本测试根节点与正式主场景均已进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 验证启动页面、设置浮层和身份局开始请求；任一断言失败后以非零状态退出。
func _run() -> void:
	# 正式主场景资源；测试必须使用玩家实际启动的场景而非构造替代界面。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；主菜单和牌桌信号在同一节点树中完成连接。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 主菜单组件；启动前必须可见并且不得已经创建对局状态。
	var main_menu: MainMenu = main_instance.get_node("%MainMenu") as MainMenu
	# 对局控制器；点击开始游戏后由主菜单信号驱动其创建标准身份局。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 设置按钮；替代参考布局中的商店入口，点击后展示配置浮层。
	var settings_button: Button = main_instance.get_node("%MainMenuSettingsButton") as Button
	# 开始按钮；文字固定为“开始游戏”，点击后关闭主菜单并开始身份局。
	var start_game_button: Button = main_instance.get_node("%StartGameButton") as Button
	# 设置浮层；默认隐藏，按下设置按钮后可修改下一局人数。
	var settings_panel: PanelContainer = main_instance.get_node("%MainMenuSettingsPanel") as PanelContainer
	# 游戏人数输入框；2至10范围内的值会作为主菜单开局请求参数。
	var player_count_input: SpinBox = main_instance.get_node("%MainMenuPlayerCountInput") as SpinBox
	# 顶部模式栏；主题切换后其边框必须从统一注册表即时更新。
	var top_navigation: PanelContainer = main_instance.get_node("%MainMenuTopNavigation") as PanelContainer
	if main_menu == null or not main_menu.visible or match_controller.state != null or settings_button.text != "设置" or start_game_button.text != "开始游戏" or settings_panel.visible:
		_fail("startup_state")
		return
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_DECADE_WOOD)
	await get_tree().process_frame
	if not (top_navigation.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "border")):
		_fail("theme_refresh")
		return
	GameSettings.set_ui_style(UIStyleRegistry.DEFAULT_STYLE_ID)
	await get_tree().process_frame
	settings_button.pressed.emit()
	await get_tree().process_frame
	if not settings_panel.visible:
		_fail("settings_open")
		return
	# 模拟玩家仍在编辑框内输入人数；开始按钮必须优先读取这份尚未失焦的文本。
	player_count_input.get_line_edit().text = "6"
	start_game_button.pressed.emit()
	for _start_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if main_menu.visible or settings_panel.visible or match_controller.state == null or match_controller.state.players.size() != 6 or match_controller.default_player_count != 6:
		_fail("start_identity_match")
		return
	print("MAIN_MENU_PASS players=%d" % match_controller.state.players.size())
	main_instance.queue_free()
	get_tree().quit()


## 输出稳定失败标识并以非零状态结束测试；避免后续异步对局逻辑掩盖首个断言错误。
func _fail(reason: String) -> void:
	printerr("MAIN_MENU_FAIL %s" % reason)
	get_tree().quit(1)
