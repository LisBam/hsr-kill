extends Node

## 安卓适配回归测试。验证APK预设、横屏等比缩放、原生触控输入和系统返回键组件保持可用。

## 长按测试等待秒数；0.3秒略高于测试组件设置的0.25秒阈值，避免帧调度误差。
const TOUCH_HOLD_TEST_WAIT_SECONDS: float = 0.3


## 延迟执行安卓适配测试；保证自动加载与场景树已完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证项目配置、导出配置、正式场景组件和两类核心触摸手势。
func _run() -> void:
	if not _validate_project_settings():
		return
	if not _validate_export_preset():
		return
	if not _validate_exported_content_discovery():
		return
	if not (await _validate_main_scene()):
		return
	if not (await _validate_card_touch_input()):
		return
	if not (await _validate_player_touch_input()):
		return
	print("ANDROID_ADAPTATION_TEST_OK")
	get_tree().quit()


## 验证逻辑画布、横屏旋转、等比缩放和原生触摸路径；这些设置共同保证不同安卓分辨率不拉伸界面。
func _validate_project_settings() -> bool:
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) != 1280:
		return _fail("viewport_width")
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) != 720:
		return _fail("viewport_height")
	if str(ProjectSettings.get_setting("display/window/stretch/mode", "")) != "canvas_items":
		return _fail("stretch_mode")
	if str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) != "keep":
		return _fail("stretch_aspect")
	if int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) != 0:
		return _fail("handheld_orientation")
	if int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", -1)) != 1:
		return _fail("vsync_mode")
	if str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "")) != "mobile":
		return _fail("mobile_renderer")
	if str(ProjectSettings.get_setting("rendering/rendering_device/driver.android", "")) != "vulkan":
		return _fail("android_rendering_driver")
	if not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false)):
		return _fail("standard_gui_touch_pointer_path")
	if bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)):
		return _fail("android_back_quit")
	return true


## 验证Android PCK中的编译脚本和remap目录项能够恢复成原始脚本路径，保证卡牌、技能和武将自动发现不为空。
func _validate_exported_content_discovery() -> bool:
	if GameDatabase._resolve_gd_script_file_name("huosha.gdc") != "huosha.gd":
		return _fail("exported_card_script_discovery")
	if GameDatabase._resolve_gd_script_file_name("xinghuo.gdc") != "xinghuo.gd":
		return _fail("exported_skill_script_discovery")
	if GameDatabase._resolve_gd_script_file_name("jizi.gdc") != "jizi.gd":
		return _fail("exported_character_script_discovery")
	if GameDatabase._resolve_gd_script_file_name("jizi.gd.remap") != "jizi.gd":
		return _fail("exported_script_remap_discovery")
	return true


## 验证Android导出项使用可安装应用身份、ARM64架构与联网权限；保存位置由导出对话框决定，不作为工程回归条件。
func _validate_export_preset() -> bool:
	# Android导出预设配置；ConfigFile直接读取正式文件，避免测试复制另一份期望配置。
	var export_config: ConfigFile = ConfigFile.new()
	if export_config.load("res://export_presets.cfg") != OK:
		return _fail("export_preset_load")
	if str(export_config.get_value("preset.0", "platform", "")) != "Android":
		return _fail("export_platform")
	# Android包名；允许主公自行维护正式命名，但不得为空或继续使用Godot示例包名前缀。
	var package_name: String = str(export_config.get_value("preset.0.options", "package/unique_name", ""))
	if package_name.is_empty() or package_name.begins_with("com.example"):
		return _fail("package_name")
	if not bool(export_config.get_value("preset.0.options", "architectures/arm64-v8a", false)):
		return _fail("arm64_architecture")
	if not bool(export_config.get_value("preset.0.options", "permissions/internet", false)):
		return _fail("internet_permission")
	return true


## 验证正式主场景挂载独立返回键组件；平台逻辑不得塞入主菜单或规则控制器。
func _validate_main_scene() -> bool:
	# 正式主场景资源；测试使用玩家实际运行的场景验证组件装配。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("main_scene_load")
	# 正式主场景实例；加入树后唯一名称索引和onready引用才会完整生效。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	await get_tree().process_frame
	# 安卓返回键组件；必须独立挂载并保持默认标准取消动作。
	var android_back_adapter: AndroidBackAdapter = main_instance.get_node("%AndroidBackAdapter") as AndroidBackAdapter
	# 安卓显示稳定组件；默认60帧与垂直同步用于避免高刷新率设备交换链节奏抖动。
	var android_display_stability: AndroidDisplayStability = main_instance.get_node("%AndroidDisplayStability") as AndroidDisplayStability
	if android_back_adapter == null or android_back_adapter.cancel_action_name != &"ui_cancel" or android_display_stability == null or android_display_stability.target_fps != 60 or not android_display_stability.force_vsync:
		main_instance.queue_free()
		return _fail("android_platform_components")
	# 联机资料面板；打开后名称光标应位于已保存文本末尾，且不使用强制全选破坏触摸定位。
	var online_settings_panel: OnlineSettingsPanel = main_instance.get_node("%OnlineSettingsPanel") as OnlineSettingsPanel
	online_settings_panel.open_panel()
	# 联机名称输入框；Android主动点击后可删除、追加或移动光标，打开面板本身不会锁定文本选择。
	var online_name_input: LineEdit = online_settings_panel.get_node("%OnlinePlayerNameInput") as LineEdit
	if online_name_input.select_all_on_focus or online_name_input.caret_column != online_name_input.text.length():
		main_instance.queue_free()
		return _fail("online_name_touch_editing")
	online_settings_panel.visible = false
	# 局域网连接入口；IP、端口、密码和两个连接按钮必须保持可编辑可点击。
	var lan_lobby_panel: LanLobbyPanel = main_instance.get_node("%LanLobbyPanel") as LanLobbyPanel
	lan_lobby_panel.open_panel(8, 7000)
	# 房主地址输入框；触摸后应允许系统键盘写入和移动光标。
	var lan_address_input: LineEdit = lan_lobby_panel.get_node("%LanAddressInput") as LineEdit
	# 端口输入框；SpinBox内部LineEdit必须可编辑，上下按钮由标准鼠标模拟路径驱动。
	var lan_port_input: SpinBox = lan_lobby_panel.get_node("%LanPortInput") as SpinBox
	# 房间密码输入框；触摸后应允许安全文本输入。
	var lan_password_input: LineEdit = lan_lobby_panel.get_node("%LanRoomPasswordInput") as LineEdit
	# 创建与加入按钮；联网权限与参数校验由后续协调器负责，入口不能因平台禁用。
	var lan_host_button: Button = lan_lobby_panel.get_node("%LanHostButton") as Button
	var lan_join_button: Button = lan_lobby_panel.get_node("%LanJoinButton") as Button
	if not lan_address_input.editable or not lan_port_input.editable or not lan_port_input.get_line_edit().editable or not lan_password_input.editable or lan_host_button.disabled or lan_join_button.disabled:
		main_instance.queue_free()
		return _fail("lan_touch_controls")
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 验证Android触摸转换后的标准鼠标轻点只激活一次，且自定义卡牌组件不会重复处理原始触点。
func _validate_card_touch_input() -> bool:
	# 测试卡牌输入组件；只验证输入信号，不创建规则卡牌或对局状态。
	var card_input_area: CardInputArea = CardInputArea.new()
	card_input_area.size = Vector2(111.0, 148.0)
	add_child(card_input_area)
	card_input_area.configure(1001, true)
	# 卡牌激活次数；轻点触摸应且只能发出一次activated。
	var activated_count: Array[int] = [0]
	card_input_area.activated.connect(func() -> void: activated_count[0] += 1)
	# 原始触点按下事件；触摸模拟鼠标开启时必须被自定义卡牌组件忽略，等待标准模拟鼠标事件处理。
	var raw_touch_press_event: InputEventScreenTouch = InputEventScreenTouch.new()
	raw_touch_press_event.index = 0
	raw_touch_press_event.position = Vector2(40.0, 60.0)
	raw_touch_press_event.pressed = true
	card_input_area._gui_input(raw_touch_press_event)
	# 原始触点释放事件；同一手势不能在模拟鼠标到达前提前激活卡牌。
	var raw_touch_release_event: InputEventScreenTouch = InputEventScreenTouch.new()
	raw_touch_release_event.index = 0
	raw_touch_release_event.position = raw_touch_press_event.position
	raw_touch_release_event.pressed = false
	card_input_area._input(raw_touch_release_event)
	if activated_count[0] != 0:
		card_input_area.queue_free()
		return _fail("card_raw_touch_should_be_ignored")
	# 卡牌模拟鼠标按下事件；Android标准GUI与自定义卡牌共用该指针协议。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.position = Vector2(40.0, 60.0)
	press_event.pressed = true
	card_input_area._gui_input(press_event)
	# 卡牌模拟鼠标释放事件；全局输入路径保证手指移出原区域时仍能结束手势。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.position = press_event.position
	release_event.pressed = false
	card_input_area._input(release_event)
	await get_tree().process_frame
	card_input_area.queue_free()
	if activated_count[0] != 1:
		return _fail("card_touch_activation")
	return true


## 验证武将牌的Android模拟鼠标长按显示信息、双击打开详情，并抑制长按手势的目标激活。
func _validate_player_touch_input() -> bool:
	# 测试武将输入组件；长按阈值调到允许范围下限以缩短自动回归耗时。
	var player_input_area: PlayerTargetInputArea = PlayerTargetInputArea.new()
	player_input_area.size = Vector2(148.35, 197.8)
	player_input_area.touch_details_hold_seconds = 0.25
	add_child(player_input_area)
	player_input_area.configure(true)
	# 武将详情请求次数；连续双击应且只能发出一次details_requested。
	var details_count: Array[int] = [0]
	# 武将信息请求次数；稳定长按应且只能发出一次information_requested。
	var information_count: Array[int] = [0]
	# 武将目标激活次数；同一次长按释放不得再额外选择目标。
	var activated_count: Array[int] = [0]
	player_input_area.details_requested.connect(func() -> void: details_count[0] += 1)
	player_input_area.information_requested.connect(func(_local_position: Vector2) -> void: information_count[0] += 1)
	player_input_area.activated.connect(func(_local_position: Vector2) -> void: activated_count[0] += 1)
	# 武将牌模拟鼠标按下事件；位置位于组件内部并保持不移动以满足长按语义。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.position = Vector2(70.0, 90.0)
	press_event.pressed = true
	player_input_area._gui_input(press_event)
	await get_tree().create_timer(TOUCH_HOLD_TEST_WAIT_SECONDS).timeout
	# 武将牌模拟鼠标释放事件；信息已打开时释放只结束手势，不提交目标选择。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.position = press_event.position
	release_event.pressed = false
	player_input_area._gui_input(release_event)
	await get_tree().process_frame
	if information_count[0] != 1 or details_count[0] != 0 or activated_count[0] != 0:
		return _fail("player_touch_hold")
	# 首次双击按下；快速轻触仍走标准鼠标模拟路径，不使用原始触屏事件避免重复处理。
	var first_double_press_event: InputEventMouseButton = InputEventMouseButton.new()
	first_double_press_event.button_index = MOUSE_BUTTON_LEFT
	first_double_press_event.position = Vector2(70.0, 90.0)
	first_double_press_event.pressed = true
	player_input_area._gui_input(first_double_press_event)
	var first_double_release_event: InputEventMouseButton = InputEventMouseButton.new()
	first_double_release_event.button_index = MOUSE_BUTTON_LEFT
	first_double_release_event.position = first_double_press_event.position
	first_double_release_event.pressed = false
	player_input_area._gui_input(first_double_release_event)
	# 第二次轻触；间隔小于组件导出的0.32秒窗口后必须转为资料请求。
	var second_double_press_event: InputEventMouseButton = InputEventMouseButton.new()
	second_double_press_event.button_index = MOUSE_BUTTON_LEFT
	second_double_press_event.position = first_double_press_event.position
	second_double_press_event.pressed = true
	player_input_area._gui_input(second_double_press_event)
	var second_double_release_event: InputEventMouseButton = InputEventMouseButton.new()
	second_double_release_event.button_index = MOUSE_BUTTON_LEFT
	second_double_release_event.position = second_double_press_event.position
	second_double_release_event.pressed = false
	player_input_area._gui_input(second_double_release_event)
	await get_tree().process_frame
	player_input_area.queue_free()
	if details_count[0] != 1:
		return _fail("player_touch_double_tap")
	return true


## 输出失败项并以非零状态退出；返回false便于调用方立即终止后续断言。
func _fail(message: String) -> bool:
	printerr("ANDROID_ADAPTATION_TEST_FAIL %s" % message)
	get_tree().quit(1)
	return false
