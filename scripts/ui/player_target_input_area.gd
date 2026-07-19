class_name PlayerTargetInputArea
extends Control

## 武将牌输入区域。该组件只处理点击与详情请求，不负责武将牌渲染或目标规则判断。

## 鼠标左键激活武将牌时发出的信号；武将牌根节点会携带玩家 ID 向桌面转发。
## 参数为武将牌局部坐标，根组件可据此区分身份徽记与普通牌面点击。
signal activated(local_position: Vector2)

## 鼠标右键释放武将牌时发出的详情请求信号；该入口不受角色存活或目标可选状态限制。
signal details_requested

## 鼠标在武将牌内移动时发出的局部坐标信号；武将牌组件据此识别公开装备横条悬停目标。
signal pointer_moved(local_position: Vector2)

## 触屏长按多久后打开武将详情；默认0.5秒可与快速点选目标清晰区分，运行时通常无需动态修改。
@export_range(0.25, 1.0, 0.05) var touch_details_hold_seconds: float = 0.5

## 触屏长按允许的最大抖动距离；默认18像素适应手指自然晃动，超过后不再打开详情，运行时通常无需动态修改。
@export_range(4.0, 48.0, 1.0) var touch_hold_movement_tolerance: float = 18.0

## 当前武将牌是否允许点击；默认 false，由公开存活状态动态修改。
var is_interactable: bool = false

## 当前由本组件追踪的触点索引；默认-1表示没有触摸，只接管首个落下的单指。
var _active_touch_index: int = -1

## 当前触点按下时的全局画布坐标；用于区分稳定长按与滑动手势。
var _touch_press_global_position: Vector2 = Vector2.ZERO

## 当前触点最近一次全局画布坐标；长按计时结束时通过该值复核移动距离。
var _touch_current_global_position: Vector2 = Vector2.ZERO

## 当前触摸是否已经打开武将详情；为true时松手不会再执行目标选择。
var _touch_details_requested: bool = false

## 当前触摸序列编号；每次按下或结束都会递增，使旧的异步长按计时自动失效。
var _touch_sequence_id: int = 0


## 初始化覆盖整张武将牌的透明输入区域。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 更新武将牌输入权限；该方法不保存玩家快照或访问规则服务。
func configure(interactable: bool) -> void:
	is_interactable = interactable
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactable else Control.CURSOR_ARROW


## 把左键释放转换为武将牌激活信号。
## 右键按下与释放会被本组件消费，并在释放时转换为不依赖存活状态的详情请求。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 当前鼠标移动事件；局部坐标只供武将牌表现组件识别公开装备横条，不进入规则状态。
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		pointer_moved.emit(motion_event.position)
		return
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；只响应左键释放，避免一次点击产生重复目标切换。
		# 右键详情优先处理并在释放时只触发一次，随后不再进入左键目标选择分支。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if not mouse_event.pressed:
				details_requested.emit()
			accept_event()
			return
		if not is_interactable:
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			activated.emit(mouse_event.position)
			accept_event()
		return
	if event is InputEventScreenTouch:
		# 当前触屏按下事件；释放统一由全局输入处理，保证手指移出武将牌后仍能安全结束手势。
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.pressed and _active_touch_index < 0:
			_active_touch_index = touch_event.index
			_touch_press_global_position = touch_event.position
			_touch_current_global_position = touch_event.position
			_touch_details_requested = false
			_touch_sequence_id += 1
			_start_touch_details_timer(_touch_sequence_id, touch_event.index)
			accept_event()


## 跟踪武将牌上的触屏拖动与释放；桌面鼠标路径保持由_gui_input独立处理。
func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		# 当前触屏拖动事件；只响应本组件记录的触点，并把位置转换为武将牌局部坐标供装备横条识别。
		var touch_drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		if touch_drag_event.index != _active_touch_index:
			return
		_touch_current_global_position = touch_drag_event.position
		pointer_moved.emit(_global_canvas_to_local(touch_drag_event.position))
		get_viewport().set_input_as_handled()
		return
	if event is not InputEventScreenTouch:
		return
	# 当前触屏释放事件；只有匹配的活动触点会结束手势，第二根手指不会干扰目标选择。
	var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
	if touch_event.index != _active_touch_index or touch_event.pressed:
		return
	_touch_current_global_position = touch_event.position
	# 本次触摸是否已用于打开详情；保存后立即清理状态，避免详情回调刷新节点时读到陈旧触点。
	var completed_details_request: bool = _touch_details_requested
	# 当前释放位置的武将牌局部坐标；与桌面左键激活信号使用相同坐标语义。
	var local_release_position: Vector2 = _global_canvas_to_local(touch_event.position)
	_active_touch_index = -1
	_touch_details_requested = false
	_touch_sequence_id += 1
	if not completed_details_request and is_interactable:
		activated.emit(local_release_position)
	get_viewport().set_input_as_handled()


## 等待长按阈值后打开武将详情；触点移动、释放或被新手势替换时不会触发旧请求。
func _start_touch_details_timer(sequence_id: int, touch_index: int) -> void:
	await get_tree().create_timer(touch_details_hold_seconds).timeout
	if not is_inside_tree() or sequence_id != _touch_sequence_id or touch_index != _active_touch_index:
		return
	if _touch_current_global_position.distance_to(_touch_press_global_position) > touch_hold_movement_tolerance:
		return
	_touch_details_requested = true
	details_requested.emit()


## 把视口触点坐标转换为武将牌局部坐标；画布缩放和安卓等比留边都由节点变换统一消化。
func _global_canvas_to_local(global_canvas_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_canvas_position
