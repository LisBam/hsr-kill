extends Node

## 安卓适配回归测试。验证APK预设、横屏等比缩放、原生触控输入和系统返回键组件保持可用。

## 测试触摸使用的固定触点索引；单指索引0与真实安卓首个触点一致。
const TEST_TOUCH_INDEX: int = 0

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
	if bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)):
		return _fail("native_touch_path")
	if bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)):
		return _fail("android_back_quit")
	return true


## 验证Android导出项使用可安装应用身份、ARM64架构、联网权限，并允许导出时自行选择APK保存位置。
func _validate_export_preset() -> bool:
	# Android导出预设配置；ConfigFile直接读取正式文件，避免测试复制另一份期望配置。
	var export_config: ConfigFile = ConfigFile.new()
	if export_config.load("res://export_presets.cfg") != OK:
		return _fail("export_preset_load")
	if str(export_config.get_value("preset.0", "platform", "")) != "Android":
		return _fail("export_platform")
	if not str(export_config.get_value("preset.0", "export_path", "")).is_empty():
		return _fail("export_path_should_be_selected_manually")
	if str(export_config.get_value("preset.0.options", "package/unique_name", "")) != "com.hsrkill.game":
		return _fail("package_name")
	if not bool(export_config.get_value("preset.0.options", "package/show_as_launcher_app", false)):
		return _fail("launcher_entry")
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
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 验证卡牌原生触摸轻点会激活，且不会依赖鼠标事件模拟。
func _validate_card_touch_input() -> bool:
	# 测试卡牌输入组件；只验证输入信号，不创建规则卡牌或对局状态。
	var card_input_area: CardInputArea = CardInputArea.new()
	card_input_area.size = Vector2(111.0, 148.0)
	add_child(card_input_area)
	card_input_area.configure(1001, true)
	# 卡牌激活次数；轻点触摸应且只能发出一次activated。
	var activated_count: Array[int] = [0]
	card_input_area.activated.connect(func() -> void: activated_count[0] += 1)
	# 卡牌触摸按下事件；位置位于组件内部并使用首个触点索引。
	var press_event: InputEventScreenTouch = InputEventScreenTouch.new()
	press_event.index = TEST_TOUCH_INDEX
	press_event.position = Vector2(40.0, 60.0)
	press_event.pressed = true
	card_input_area._gui_input(press_event)
	# 卡牌触摸释放事件；全局输入路径保证手指移出原区域时仍能结束手势。
	var release_event: InputEventScreenTouch = InputEventScreenTouch.new()
	release_event.index = TEST_TOUCH_INDEX
	release_event.position = press_event.position
	release_event.pressed = false
	card_input_area._input(release_event)
	await get_tree().process_frame
	card_input_area.queue_free()
	if activated_count[0] != 1:
		return _fail("card_touch_activation")
	return true


## 验证武将牌原生触摸长按打开详情，并抑制同一次手势的目标激活。
func _validate_player_touch_input() -> bool:
	# 测试武将输入组件；长按阈值调到允许范围下限以缩短自动回归耗时。
	var player_input_area: PlayerTargetInputArea = PlayerTargetInputArea.new()
	player_input_area.size = Vector2(148.35, 197.8)
	player_input_area.touch_details_hold_seconds = 0.25
	add_child(player_input_area)
	player_input_area.configure(true)
	# 武将详情请求次数；稳定长按应且只能发出一次details_requested。
	var details_count: Array[int] = [0]
	# 武将目标激活次数；同一次长按释放不得再额外选择目标。
	var activated_count: Array[int] = [0]
	player_input_area.details_requested.connect(func() -> void: details_count[0] += 1)
	player_input_area.activated.connect(func(_local_position: Vector2) -> void: activated_count[0] += 1)
	# 武将牌触摸按下事件；位置位于组件内部并保持不移动以满足长按语义。
	var press_event: InputEventScreenTouch = InputEventScreenTouch.new()
	press_event.index = TEST_TOUCH_INDEX
	press_event.position = Vector2(70.0, 90.0)
	press_event.pressed = true
	player_input_area._gui_input(press_event)
	await get_tree().create_timer(TOUCH_HOLD_TEST_WAIT_SECONDS).timeout
	# 武将牌触摸释放事件；详情已打开时释放只结束手势，不提交目标选择。
	var release_event: InputEventScreenTouch = InputEventScreenTouch.new()
	release_event.index = TEST_TOUCH_INDEX
	release_event.position = press_event.position
	release_event.pressed = false
	player_input_area._input(release_event)
	await get_tree().process_frame
	player_input_area.queue_free()
	if details_count[0] != 1 or activated_count[0] != 0:
		return _fail("player_touch_hold")
	return true


## 输出失败项并以非零状态退出；返回false便于调用方立即终止后续断言。
func _fail(message: String) -> bool:
	printerr("ANDROID_ADAPTATION_TEST_FAIL %s" % message)
	get_tree().quit(1)
	return false
