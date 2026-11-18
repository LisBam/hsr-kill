extends Node

## 标题栏窗口拖动组件；只维护本地窗口位置，不读取请求、卡牌或规则状态。

## 普通窗口距离父控件边缘的安全间隔；默认8像素保证标题与按钮可见，通常无需运行时修改。
@export_range(0.0, 32.0, 1.0) var edge_margin: float = 8.0

## 被拖动的窗口；由宿主装配，必须位于普通Control下，不能由Container直接管理位置。
var _surface: Control
## 用作拖动入口的标题栏；仅该区域接受起拖，牌面与操作按钮保持各自输入行为。
var _handle: Control
## 宿主最近一次自动布局的位置；拖动偏移相对该位置保存，快照刷新后仍可恢复。
var _layout_position: Vector2 = Vector2.ZERO
## 玩家本次打开窗口后的位移；关闭或切换到新请求时由宿主重置，不写入玩家设置。
var _drag_offset: Vector2 = Vector2.ZERO
## 鼠标按下点相对窗口左上角的位置；拖动期间保持不变，避免窗口跳到鼠标中心。
var _pointer_offset: Vector2 = Vector2.ZERO
## 是否正在接管一次左键拖动；默认关闭，仅拖动期间启用全局输入回调。
var _dragging: bool = false
## 自定义可移动范围，坐标相对窗口父控件；空矩形表示使用父控件范围及安全间隔。
var _movement_bounds: Rect2 = Rect2()


## 空闲期间不轮询输入；组件在暂停菜单中也能及时结束已有拖动。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(false)


## 绑定窗口与标题栏；由拥有窗口生命周期的组件调用一次。
func configure(surface: Control, handle: Control) -> void:
	_surface = surface
	_handle = handle
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_handle.gui_input.connect(_on_handle_input)
	_surface.visibility_changed.connect(_on_visibility_changed)
	_surface.resized.connect(_queue_keep_in_bounds)
	(_surface.get_parent() as Control).resized.connect(_queue_keep_in_bounds)


## 自动布局完成后调用；保存新的默认位置，再恢复玩家拖动量并限制窗口范围。
func apply_layout(movement_bounds: Rect2 = Rect2()) -> void:
	_movement_bounds = movement_bounds
	_layout_position = _surface.position
	_surface.position = _clamp_position(_layout_position + _drag_offset)
	_drag_offset = _surface.position - _layout_position


## 关闭或切换新窗口时清除位置记忆；不自行打开、关闭或提交任何请求。
func reset() -> void:
	_stop_dragging()
	_drag_offset = Vector2.ZERO


## 只允许标题栏左键启动拖动；其他区域的选牌、排序、滚动和按钮输入不参与窗口移动。
func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pointer_offset = _pointer_in_parent(_handle.get_global_transform_with_canvas() * event.position) - _surface.position
		_dragging = true
		set_process_input(true)
		_handle.accept_event()


## 起拖后跟踪全局移动与释放，鼠标离开标题栏仍可完成拖动；坐标转换兼容画布拉伸。
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_surface.position = _clamp_position(_pointer_in_parent(event.position) - _pointer_offset)
		_drag_offset = _surface.position - _layout_position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stop_dragging()
		get_viewport().set_input_as_handled()


## 把视口鼠标位置转换为窗口父控件坐标；不使用缩放后的屏幕像素作为布局偏移。
func _pointer_in_parent(pointer: Vector2) -> Vector2:
	return (_surface.get_parent() as Control).get_global_transform_with_canvas().affine_inverse() * pointer


## 限制整个窗口留在允许区域；公共牌池可传入询问区上方的矩形以保护响应按钮。
func _clamp_position(target: Vector2) -> Vector2:
	# 当前可移动范围；普通窗口按父控件尺寸自动计算，公共窗口使用宿主提供的安全区。
	var bounds: Rect2 = _movement_bounds
	if not bounds.has_area():
		bounds = Rect2(Vector2.ZERO, (_surface.get_parent() as Control).size).grow(-edge_margin)
	return target.clamp(bounds.position, bounds.position.max(bounds.end - _surface.size))


## 等容器与锚点完成排序后再收回越界部分，不在每帧重复处理窗口布局。
func _queue_keep_in_bounds() -> void:
	call_deferred("_keep_in_bounds")


## 分辨率或内容尺寸变化后更新参考位置；保留已有拖动量，并确保标题仍可操作。
func _keep_in_bounds() -> void:
	_layout_position = _surface.position - _drag_offset
	_surface.position = _clamp_position(_surface.position)
	_drag_offset = _surface.position - _layout_position


## 窗口隐藏时停止跟踪，防止松开鼠标后下一次打开仍跟随指针。
func _on_visibility_changed() -> void:
	if not _surface.is_visible_in_tree():
		_stop_dragging()


## 失去应用焦点时结束拖动，避免释放发生在窗口外而留下按下状态。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_stop_dragging()


## 关闭输入接管，不改变窗口当前的位置或规则操作。
func _stop_dragging() -> void:
	_dragging = false
	set_process_input(false)
