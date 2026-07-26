class_name MatchReplayOverlay
extends Control

## 对局回放重演覆盖层。回放重演期间铺满整个牌桌：透明输入屏障吞掉全部指向底层桌面的
## 鼠标操作（重演不可操作），悬浮控制条提供回放名展示、速度选择与“退出回放”按钮。
## 控制条支持按住空白区域自由拖动并钳制在画面内，避免固定位置遮挡玩家想观察的牌桌区域；
## 组件只发出速度与退出意图，不读取回放步骤、不访问规则状态，重演推进由驱动器负责。

## 玩家选择新的速度倍率时发出；倍率仅允许加速档位，由牌桌转交回放驱动器。
signal speed_selected(speed_multiplier: float)

## 玩家请求退出回放时发出；牌桌据此结束重演会话并返回主菜单“对局回放”页。
signal exit_requested

## 覆盖层绘制层级；高于局内菜单（500）与结算面板（220），重演控制条必须始终可见可点。
const OVERLAY_Z_INDEX: int = 620

## 速度倍率档位；回放只允许加速，1倍为按录制节奏原速重演，不提供减速或暂停。
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 4.0]

## 控制条默认距客户区上边界的像素；未拖动过时的初始纵坐标，避开牌桌顶栏轮次与时长文本。
@export var control_bar_top_margin: float = 10.0

## 控制条拖动钳制的画面安全边距像素；默认4保证条体任何时候都完整留在客户区内可再次拖回。
@export var bar_boundary_margin: float = 4.0

## 输入屏障；透明全屏矩形吞掉鼠标事件，使重演期间底层牌桌不可操作。
var _input_barrier: ColorRect = null

## 悬浮控制条面板；承载拖动手柄、回放名、速度选择与退出按钮，可整体拖动。
var _control_bar: PanelContainer = null

## 拖动手柄标签；固定“≡”符号提示控制条可拖动，本身忽略鼠标，拖动由条体背景统一处理。
var _drag_handle_label: Label = null

## 回放名与状态标签；显示“回放重演：名称”，播放完毕后追加完成提示。
var _title_label: Label = null

## 速度选择下拉框；选项元数据保存倍率浮点值。
var _speed_option: OptionButton = null

## 退出回放按钮；发出退出意图，实际清理由牌桌执行。
var _exit_button: Button = null

## 当前展示的回放名；播放完毕更新标签时复用，不依赖标签文本反解。
var _replay_display_name: String = ""

## 是否正在拖动控制条；按下条体空白区域置真，松开左键或收起覆盖层置假。
var _dragging_control_bar: bool = false

## 玩家是否已经手动拖动过控制条；已拖动时后续打开保留上次位置，未拖动时每次打开回到默认顶部居中。
var _has_custom_bar_position: bool = false


## 构建覆盖层节点树；默认隐藏，重演开始时由牌桌打开。
func _ready() -> void:
	# 覆盖层必须在任何暂停状态下保持可交互；退出回放与调速不依赖对局帧推进。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = OVERLAY_Z_INDEX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_overlay_resized)
	_input_barrier = ColorRect.new()
	_input_barrier.name = "ReplayInputBarrier"
	_input_barrier.color = Color(0.0, 0.0, 0.0, 0.0)
	_input_barrier.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_barrier.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_input_barrier)
	_control_bar = PanelContainer.new()
	_control_bar.name = "ReplayControlBar"
	# 控制条使用左上角自由定位以支持拖动；默认顶部居中位置在打开时按实际条宽计算。
	_control_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_control_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_control_bar.gui_input.connect(_on_control_bar_gui_input)
	_control_bar.resized.connect(_on_control_bar_resized)
	add_child(_control_bar)
	# 控制条横向布局；拖动手柄、回放名、速度选择与退出按钮从左到右排列。
	var bar_row: HBoxContainer = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 14)
	_control_bar.add_child(bar_row)
	_drag_handle_label = Label.new()
	_drag_handle_label.name = "ReplayOverlayDragHandle"
	_drag_handle_label.text = "≡"
	_drag_handle_label.add_theme_font_size_override("font_size", 18)
	_drag_handle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_drag_handle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_drag_handle_label)
	_title_label = Label.new()
	_title_label.name = "ReplayOverlayTitle"
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_title_label)
	_speed_option = OptionButton.new()
	_speed_option.name = "ReplayOverlaySpeedOption"
	_speed_option.custom_minimum_size = Vector2(88.0, 34.0)
	_speed_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for speed_value: float in SPEED_OPTIONS:
		_speed_option.add_item("%d×" % int(speed_value))
		_speed_option.set_item_metadata(_speed_option.item_count - 1, speed_value)
	_speed_option.select(0)
	_speed_option.item_selected.connect(_on_speed_item_selected)
	bar_row.add_child(_speed_option)
	_exit_button = Button.new()
	_exit_button.name = "ReplayOverlayExitButton"
	_exit_button.text = "退出回放"
	_exit_button.custom_minimum_size = Vector2(104.0, 34.0)
	_exit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	bar_row.add_child(_exit_button)
	refresh_ui_style()


## 打开覆盖层并重置为原速播放状态；display_name 为回放的可读名称（文件基础名）。
## 玩家拖动过的控制条位置在同一次游戏运行内保留（越界时钳回画面），从未拖动则回到默认顶部居中。
func open_overlay(display_name: String) -> void:
	_replay_display_name = display_name
	_title_label.text = "回放重演：%s" % _replay_display_name
	_speed_option.select(0)
	visible = true
	move_to_front()
	# 布局完成后再定位；打开当帧条体尺寸可能尚未按新标题重新计算。
	call_deferred("_apply_bar_position_after_layout")


## 收起覆盖层；重演结束或退出时由牌桌调用，速度选择在下次打开时重置，进行中的拖动同步终止。
func close_overlay() -> void:
	_dragging_control_bar = false
	visible = false


## 覆盖层当前是否展开；牌桌据此判定重演输入封锁是否生效。
func is_open() -> bool:
	return visible


## 标记回放已播放完毕；标题追加完成提示，玩家可继续查看终局画面或退出。
## 标题变长会加宽条体；尺寸回调会自动把越界部分钳回画面。
func mark_finished() -> void:
	_title_label.text = "回放重演：%s（已播放完毕）" % _replay_display_name


## 重演期间接管取消键；Esc 与安卓返回统一表示退出回放，不允许穿透到底层牌桌快捷键。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		exit_requested.emit()


## 刷新活动 UI 风格；控制条与按钮统一读取当前主题语义色。
func refresh_ui_style() -> void:
	if _control_bar == null:
		return
	_control_bar.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("accent"), 2, 8))
	_drag_handle_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	# OptionButton 继承 Button；复用交互按钮样式统一常态、悬停与按下外观。
	BattleUIStyle.apply_interaction_button(_speed_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_exit_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)


## 速度选择回调；把选项元数据中的倍率转交牌桌，元数据缺失时回退原速。
func _on_speed_item_selected(item_index: int) -> void:
	# 选中项元数据；构建时写入倍率浮点值。
	var speed_metadata: Variant = _speed_option.get_item_metadata(item_index)
	speed_selected.emit(float(speed_metadata) if speed_metadata != null else 1.0)


## 控制条拖动输入；左键按住条体空白区域（标签与内边距）拖动，子按钮自行消费点击不触发拖动。
## Godot 在按键按住期间把后续鼠标移动事件持续派发给按下时的控件，因此快速拖出条体也不会中断。
func _on_control_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；只有左键参与拖动，按下开始、松开结束。
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_control_bar = button_event.pressed
			if button_event.pressed:
				_has_custom_bar_position = true
			accept_event()
	elif event is InputEventMouseMotion and _dragging_control_bar:
		# 拖动位移；relative 已经过 GUI 逆变换，与控制条局部坐标同尺度，逐帧累加后钳回画面。
		_control_bar.position = _clamp_bar_position(_control_bar.position + (event as InputEventMouseMotion).relative)
		accept_event()


## 布局完成后的控制条定位；保留玩家自定义位置（钳制越界），否则回到默认顶部居中。
func _apply_bar_position_after_layout() -> void:
	if _control_bar == null or not visible:
		return
	if _has_custom_bar_position:
		_control_bar.position = _clamp_bar_position(_control_bar.position)
	else:
		_control_bar.position = _clamp_bar_position(Vector2((size.x - _control_bar.size.x) * 0.5, control_bar_top_margin))


## 把候选位置钳制到画面安全范围内；条体大于画面的极端情况退化为贴靠安全边距。
func _clamp_bar_position(candidate_position: Vector2) -> Vector2:
	return Vector2(
		clampf(candidate_position.x, bar_boundary_margin, maxf(size.x - _control_bar.size.x - bar_boundary_margin, bar_boundary_margin)),
		clampf(candidate_position.y, bar_boundary_margin, maxf(size.y - _control_bar.size.y - bar_boundary_margin, bar_boundary_margin)),
	)


## 覆盖层尺寸变化（窗口缩放）回调；把控制条钳回新画面范围，未拖动时维持默认顶部居中。
func _on_overlay_resized() -> void:
	if _control_bar == null or not visible:
		return
	call_deferred("_apply_bar_position_after_layout")


## 控制条自身尺寸变化（标题加长、主题字体变化）回调；自定义位置只钳回画面，
## 默认位置按新条宽重新顶部居中，保证首次打开的延迟布局也能正确落位。
func _on_control_bar_resized() -> void:
	if _control_bar == null or not visible:
		return
	_apply_bar_position_after_layout()
