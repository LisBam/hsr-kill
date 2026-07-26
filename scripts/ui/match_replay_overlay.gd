class_name MatchReplayOverlay
extends Control

## 对局回放重演覆盖层。回放重演期间铺满整个牌桌：透明输入屏障吞掉全部指向底层桌面的
## 鼠标操作（重演不可操作），顶部控制条提供回放名展示、速度选择与“退出回放”按钮。
## 组件只发出速度与退出意图，不读取回放步骤、不访问规则状态，重演推进由驱动器负责。

## 玩家选择新的速度倍率时发出；倍率仅允许加速档位，由牌桌转交回放驱动器。
signal speed_selected(speed_multiplier: float)

## 玩家请求退出回放时发出；牌桌据此结束重演会话并返回主菜单“对局回放”页。
signal exit_requested

## 覆盖层绘制层级；高于局内菜单（500）与结算面板（220），重演控制条必须始终可见可点。
const OVERLAY_Z_INDEX: int = 620

## 速度倍率档位；回放只允许加速，1倍为按录制节奏原速重演，不提供减速或暂停。
const SPEED_OPTIONS: Array[float] = [1.0, 2.0, 4.0]

## 顶部控制条距客户区上边界的像素；避开牌桌顶栏轮次与时长文本。
@export var control_bar_top_margin: float = 10.0

## 输入屏障；透明全屏矩形吞掉鼠标事件，使重演期间底层牌桌不可操作。
var _input_barrier: ColorRect = null

## 顶部控制条面板；承载回放名、速度选择与退出按钮。
var _control_bar: PanelContainer = null

## 回放名与状态标签；显示“回放重演：名称”，播放完毕后追加完成提示。
var _title_label: Label = null

## 速度选择下拉框；选项元数据保存倍率浮点值。
var _speed_option: OptionButton = null

## 退出回放按钮；发出退出意图，实际清理由牌桌执行。
var _exit_button: Button = null

## 当前展示的回放名；播放完毕更新标签时复用，不依赖标签文本反解。
var _replay_display_name: String = ""


## 构建覆盖层节点树；默认隐藏，重演开始时由牌桌打开。
func _ready() -> void:
	# 覆盖层必须在任何暂停状态下保持可交互；退出回放与调速不依赖对局帧推进。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = OVERLAY_Z_INDEX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_barrier = ColorRect.new()
	_input_barrier.name = "ReplayInputBarrier"
	_input_barrier.color = Color(0.0, 0.0, 0.0, 0.0)
	_input_barrier.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_barrier.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_input_barrier)
	_control_bar = PanelContainer.new()
	_control_bar.name = "ReplayControlBar"
	_control_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_control_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_control_bar.offset_top = control_bar_top_margin
	add_child(_control_bar)
	# 控制条横向布局；回放名、速度选择与退出按钮从左到右排列。
	var bar_row: HBoxContainer = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 14)
	_control_bar.add_child(bar_row)
	_title_label = Label.new()
	_title_label.name = "ReplayOverlayTitle"
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
func open_overlay(display_name: String) -> void:
	_replay_display_name = display_name
	_title_label.text = "回放重演：%s" % _replay_display_name
	_speed_option.select(0)
	visible = true
	move_to_front()


## 收起覆盖层；重演结束或退出时由牌桌调用，速度选择在下次打开时重置。
func close_overlay() -> void:
	visible = false


## 覆盖层当前是否展开；牌桌据此判定重演输入封锁是否生效。
func is_open() -> bool:
	return visible


## 标记回放已播放完毕；标题追加完成提示，玩家可继续查看终局画面或退出。
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
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	# OptionButton 继承 Button；复用交互按钮样式统一常态、悬停与按下外观。
	BattleUIStyle.apply_interaction_button(_speed_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_exit_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)


## 速度选择回调；把选项元数据中的倍率转交牌桌，元数据缺失时回退原速。
func _on_speed_item_selected(item_index: int) -> void:
	# 选中项元数据；构建时写入倍率浮点值。
	var speed_metadata: Variant = _speed_option.get_item_metadata(item_index)
	speed_selected.emit(float(speed_metadata) if speed_metadata != null else 1.0)
