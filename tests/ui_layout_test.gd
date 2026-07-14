extends Node

## 局内界面布局与鼠标命中回归测试。测试使用正式主场景，验证边缘按钮和底部区域在默认窗口内完整可见。

## 主场景完成自动开局和动态节点构建前等待的帧数；默认6帧覆盖延迟开局、快照渲染与容器排序。
const SETTLE_FRAME_COUNT: int = 6

## 模拟未应用画布拉伸时的客户区尺寸；1152×648与项目默认启动窗口一致，用于复现固定1280×720坐标越界问题。
const COMPACT_CLIENT_SIZE: Vector2 = Vector2(1152.0, 648.0)

## 菜单按钮是否通过真实视口输入收到点击；默认 false，按钮信号触发后改为 true。
var _menu_button_pressed: bool = false


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
	# 正式对局控制器；先使用非法的1人配置阻止规则对局和AI异步任务启动，随后直接注入只读十人界面快照。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	match_controller.state_changed.emit(_make_ten_player_snapshot())
	await get_tree().process_frame
	await get_tree().process_frame
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.position = Vector2.ZERO
	main_instance.size = COMPACT_CLIENT_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	# 当前模拟客户区矩形；直接使用主场景尺寸，覆盖编辑器嵌入运行未应用画布拉伸的情况。
	var viewport_rect: Rect2 = Rect2(main_instance.position, main_instance.size)
	# 右上角菜单按钮；必须完整位于视口内并能通过真实鼠标事件收到 pressed 信号。
	var menu_button: Button = main_instance.get_node("%MenuButton") as Button
	# 底部装备面板；左下区域必须完整位于窗口客户区内。
	var equipment_panel: Control = main_instance.get_node("%EquipmentPanel") as Control
	# 底部手牌面板；其底边必须随窗口底部锚定，不能继续停留在固定720坐标。
	var hand_panel: Control = main_instance.get_node("HandPanel") as Control
	# 底部技能栏；右侧区域必须完整位于本地武将牌左侧并保持可见。
	var skill_bar: Control = main_instance.get_node("SkillBar") as Control
	# 本地玩家座位容器；右下角区域必须使用右下锚点完整留在客户区内，并承载牌面下方的独立座次标签。
	var local_player_seat_slot: Control = main_instance.get_node("LocalPlayerSeatSlot") as Control
	for checked_control: Control in [menu_button, equipment_panel, hand_panel, skill_bar, local_player_seat_slot]:
		# 当前控件的屏幕矩形；`get_screen_transform()` 已包含画布拉伸和锚点换算。
		var screen_rect: Rect2 = _screen_rect(checked_control)
		if not viewport_rect.encloses(screen_rect):
			_fail("control_outside:%s:%s viewport=%s" % [checked_control.name, screen_rect, viewport_rect])
			return
	# 底部区域屏幕矩形；装备、手牌、技能和本地座位之间必须依次保留安全间隔。
	var bottom_layout_rects: Array[Rect2] = [_screen_rect(equipment_panel), _screen_rect(hand_panel), _screen_rect(skill_bar), _screen_rect(local_player_seat_slot)]
	for rect_index: int in range(bottom_layout_rects.size() - 1):
		# 当前相邻底部区域；只检查同层功能区，允许操作提示在牌桌中心使用独立纵向层级。
		var current_rect: Rect2 = bottom_layout_rects[rect_index]
		# 下一个相邻底部区域；排列顺序固定为从左到右，任何相交都说明安全边距未适配新牌宽。
		var next_rect: Rect2 = bottom_layout_rects[rect_index + 1]
		if current_rect.intersects(next_rect):
			_fail("bottom_controls_overlap:%s:%s" % [current_rect, next_rect])
			return
	# 本地完整座位屏幕尺寸；紧凑客户区未应用画布拉伸时仍应保持135.7×223.8像素规格。
	var local_seat_screen_rect: Rect2 = _screen_rect(local_player_seat_slot)
	if not local_seat_screen_rect.size.is_equal_approx(Vector2(135.7, 223.8)):
		_fail("local_seat_size:%s" % local_seat_screen_rect.size)
		return
	# 对手座位容器；十人局应创建9个对手座位，用于覆盖顶部五席和左右各两席的最拥挤布局。
	var opponent_seat_slots: Array[Control] = []
	# 全屏对手座次布局器；动态座位都是该容器的直接子节点。
	var player_grid: Control = main_instance.get_node("%PlayerGrid") as Control
	for player_grid_child: Node in player_grid.get_children():
		if player_grid_child is Control and player_grid_child.has_node("PlayerTargetView") and player_grid_child.has_node("Seat"):
			opponent_seat_slots.append(player_grid_child as Control)
	if opponent_seat_slots.size() != 9:
		_fail("opponent_seat_count:%d" % opponent_seat_slots.size())
		return
	# 已确认的对手座位屏幕矩形；逐个加入并检查相邻牌面不会重叠。
	var occupied_opponent_rects: Array[Rect2] = []
	for opponent_seat_slot: Control in opponent_seat_slots:
		# 当前对手座位屏幕矩形；必须完整留在紧凑客户区内。
		var opponent_screen_rect: Rect2 = _screen_rect(opponent_seat_slot)
		if not viewport_rect.encloses(opponent_screen_rect):
			_fail("opponent_outside:%s:%s" % [opponent_seat_slot.name, opponent_screen_rect])
			return
		for occupied_rect: Rect2 in occupied_opponent_rects:
			if opponent_screen_rect.intersects(occupied_rect):
				_fail("opponent_overlap:%s:%s" % [opponent_screen_rect, occupied_rect])
				return
		for bottom_rect: Rect2 in bottom_layout_rects:
			if opponent_screen_rect.intersects(bottom_rect):
				_fail("opponent_bottom_overlap:%s:%s" % [opponent_screen_rect, bottom_rect])
				return
		occupied_opponent_rects.append(opponent_screen_rect)
	menu_button.pressed.connect(_on_menu_button_pressed)
	await _click_control(menu_button)
	if not _menu_button_pressed:
		_fail("menu_button_input")
		return
	# 菜单打开后等待面板布局稳定，再释放正式场景实例。
	await get_tree().process_frame
	await get_tree().process_frame
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


## 构造只包含界面公开字段的十人快照；覆盖最拥挤座次布局且不启动规则核心、AI计时器或卡牌动画。
func _make_ten_player_snapshot() -> Dictionary:
	# 测试玩家数组；座次0作为本地玩家，其余9名用于顶部五席与左右各两席。
	var players: Array[Dictionary] = []
	for player_index: int in range(10):
		# 当前玩家快照；字段与正式裁剪快照保持一致，空区域避免引入无关卡牌交互。
		var player_snapshot: Dictionary = {
			"player_id":player_index,
			"display_name":"玩家%d" % (player_index + 1),
			"character_id":"trailblazer",
			"identity":"lord" if player_index == 0 else "hidden",
			"hp":4,
			"max_hp":4,
			"alive":true,
			"chained":false,
			"hand_count":4,
			"hand":[],
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage":[],
			"wooden_ox_storage_count":0,
		}
		players.append(player_snapshot)
	# 十人界面快照；准备阶段禁用出牌控件，但保留完整本地技能栏和全部公开角色信息。
	var snapshot: Dictionary = {
		"players":players,
		"current_player_id":0,
		"current_phase":"setup",
		"turn_number":1,
		"draw_pile_count":121,
		"discard_pile_count":0,
		"game_over":false,
	}
	return snapshot


## 记录右上角菜单按钮收到真实鼠标点击，供异步输入流程断言。
func _on_menu_button_pressed() -> void:
	_menu_button_pressed = true


## 输出统一失败原因并以非零状态结束测试。
func _fail(reason: String) -> void:
	printerr("UI_LAYOUT_FAIL %s" % reason)
	get_tree().quit(1)
