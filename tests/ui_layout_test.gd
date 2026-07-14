extends Node

## 局内界面布局与鼠标命中回归测试。测试使用正式主场景，验证边缘按钮和底部区域在默认窗口内完整可见。

## 主场景完成自动开局和动态节点构建前等待的帧数；默认6帧覆盖延迟开局、快照渲染与容器排序。
const SETTLE_FRAME_COUNT: int = 6

## 模拟未应用画布拉伸时的客户区尺寸；1152×648与项目默认启动窗口一致，用于复现固定1280×720坐标越界问题。
const COMPACT_CLIENT_SIZE: Vector2 = Vector2(1152.0, 648.0)

## 名称模式按钮是否通过真实视口输入收到点击；默认 false，按钮信号触发后改为 true。
var _name_button_pressed: bool = false

## 重开按钮是否通过真实视口输入收到点击；默认 false，按钮信号触发后改为 true。
var _restart_button_pressed: bool = false


## 延迟执行正式场景检查，保证测试根节点已经进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 检查默认窗口中的可视范围、按钮鼠标命中与底部安全区。
func _run() -> void:
	# 正式主场景资源；测试必须覆盖与玩家运行完全相同的节点结构和脚本连接。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；作为测试根节点子节点运行完整界面初始化流程。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 正式对局控制器；测试使用非法的1人配置阻止自动开局，仅保留完整界面节点和按钮输入连接。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.position = Vector2.ZERO
	main_instance.size = COMPACT_CLIENT_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	# 当前模拟客户区矩形；直接使用主场景尺寸，覆盖编辑器嵌入运行未应用画布拉伸的情况。
	var viewport_rect: Rect2 = Rect2(main_instance.position, main_instance.size)
	# 牌名切换按钮；必须完整位于视口内并能通过真实鼠标事件收到 pressed 信号。
	var name_button: Button = main_instance.get_node("%NameModeButton") as Button
	# 重新开局按钮；必须完整位于视口内并能通过真实鼠标事件收到 pressed 信号。
	var restart_button: Button = main_instance.get_node("%RestartButton") as Button
	# 底部装备面板；左下区域必须完整位于窗口客户区内。
	var equipment_panel: Control = main_instance.get_node("%EquipmentPanel") as Control
	# 底部手牌面板；其底边必须随窗口底部锚定，不能继续停留在固定720坐标。
	var hand_panel: Control = main_instance.get_node("HandPanel") as Control
	# 底部技能栏；右侧区域必须完整位于本地武将牌左侧并保持可见。
	var skill_bar: Control = main_instance.get_node("SkillBar") as Control
	# 本地武将牌；右下角区域必须使用右下锚点完整留在客户区内。
	var local_player_card: Control = main_instance.get_node("LocalPlayerCard") as Control
	for checked_control: Control in [name_button, restart_button, equipment_panel, hand_panel, skill_bar, local_player_card]:
		# 当前控件的屏幕矩形；`get_screen_transform()` 已包含画布拉伸和锚点换算。
		var screen_rect: Rect2 = _screen_rect(checked_control)
		if not viewport_rect.encloses(screen_rect):
			_fail("control_outside:%s:%s viewport=%s" % [checked_control.name, screen_rect, viewport_rect])
			return
	name_button.pressed.connect(_on_name_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	await _click_control(name_button)
	if not _name_button_pressed:
		_fail("name_button_input")
		return
	await _click_control(restart_button)
	if not _restart_button_pressed:
		_fail("restart_button_input")
		return
	remove_child(main_instance)
	main_instance.free()
	await get_tree().process_frame
	print("UI_LAYOUT_PASS viewport=%s" % viewport_rect.size)
	get_tree().quit(0)


## 把控件本地矩形转换为实际视口屏幕坐标，包含画布缩放与窗口拉伸。
func _screen_rect(control: Control) -> Rect2:
	# 控件到屏幕坐标的完整变换；场景没有旋转，但仍按四角计算以避免缩放假设。
	var screen_transform: Transform2D = control.get_screen_transform()
	# 屏幕坐标下的左上角；由控件局部原点经过完整变换得到。
	var top_left: Vector2 = screen_transform * Vector2.ZERO
	# 屏幕坐标下的右下角；由控件局部尺寸经过完整变换得到。
	var bottom_right: Vector2 = screen_transform * control.size
	return Rect2(top_left, bottom_right - top_left)


## 向控件中心发送鼠标移动、按下和释放事件，验证真实 GUI 命中链而非直接调用按钮方法。
func _click_control(control: Control) -> void:
	# 当前控件屏幕中心；所有输入事件使用与视口可见矩形相同的坐标空间。
	var click_position: Vector2 = _screen_rect(control).get_center()
	# 鼠标移动事件；先更新悬停目标，确保后续按钮事件走正常 GUI 分发路径。
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.position = click_position
	get_viewport().push_input(motion_event, true)
	await get_tree().process_frame
	# 鼠标按下事件；使用左键且不直接发射 pressed 信号。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.position = click_position
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	get_viewport().push_input(press_event, true)
	await get_tree().process_frame
	# 鼠标释放事件；Button 在正常按下与释放序列完成后发出 pressed。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.position = click_position
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	get_viewport().push_input(release_event, true)
	await get_tree().process_frame


## 记录名称模式按钮收到真实鼠标点击，供异步输入流程断言。
func _on_name_button_pressed() -> void:
	_name_button_pressed = true


## 记录重开按钮收到真实鼠标点击，供异步输入流程断言。
func _on_restart_button_pressed() -> void:
	_restart_button_pressed = true


## 输出统一失败原因并以非零状态结束测试。
func _fail(reason: String) -> void:
	printerr("UI_LAYOUT_FAIL %s" % reason)
	get_tree().quit(1)
