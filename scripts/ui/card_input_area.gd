class_name CardInputArea
extends Control

## 卡牌输入区域。该组件只把鼠标点击、悬停和拖拽转换为信号，不保存牌面数据或提交规则动作。

## 鼠标左键激活卡牌时发出的信号；卡牌根节点据此通知桌面更新临时选择。
signal activated

## 鼠标进入卡牌区域时发出的信号；只用于刷新牌面悬停表现。
signal hover_started

## 鼠标离开卡牌区域时发出的信号；只用于恢复牌面默认表现。
signal hover_finished

## 手排拖拽落到另一张同分区牌面时发出的排序请求；参数依次为来源UID、目标UID与是否插入目标后方。
signal hand_reorder_requested(source_card_uid: int, target_card_uid: int, insert_after_target: bool)

## 实体手牌开始直接拖动时发出的信号；参数为来源UID与按下位置的全局画布坐标。
signal hand_drag_started(source_card_uid: int, pointer_global_position: Vector2)

## 实体手牌在直接拖动期间跟随鼠标时发出的信号；参数为来源UID与当前全局画布坐标。
signal hand_drag_moved(source_card_uid: int, pointer_global_position: Vector2)

## 实体手牌结束直接拖动时发出的信号；参数为来源UID与释放位置的全局画布坐标。
signal hand_drag_finished(source_card_uid: int, pointer_global_position: Vector2)

## 鼠标按下后移动超过该距离才开始排序拖动；默认8像素避免普通点击被误判为拖动，运行时通常无需修改。
const HAND_DRAG_START_DISTANCE: float = 8.0

## 触屏长按多久后显示卡牌说明；默认0.45秒兼顾快速选牌与主动查阅，运行时通常无需动态修改。
@export_range(0.25, 1.0, 0.05) var touch_information_hold_seconds: float = 0.45

## 触屏按住期间允许的最大抖动距离；默认18像素适应手机手指轻微移动，超过后会转入拖牌或普通滑动判定，运行时通常无需动态修改。
@export_range(4.0, 48.0, 1.0) var touch_hold_movement_tolerance: float = 18.0

## 当前实体牌 UID；由牌面配置写入，未配置时为 -1，运行时随卡牌复用而更新。
var card_uid: int = -1

## 当前输入区域是否接受左键选牌；默认 false，桌面根据行动权限动态修改，手牌排序拖拽独立由分区字段控制。
var is_interactable: bool = false

## 当前牌所属的本地排序分区；空字符串表示该牌不是正式手牌，不能开始或接收排序拖拽。
var hand_reorder_zone: String = ""

## 当前左键是否仍处于按下状态；只在正式手牌排序分区内允许进入直接拖动流程。
var _pointer_pressed: bool = false

## 左键按下时的全局画布坐标；用于与当前鼠标位置比较并过滤普通点击的微小抖动。
var _pointer_press_global_position: Vector2 = Vector2.ZERO

## 当前是否已进入实体手牌直接拖动；进入后释放鼠标只提交排序，不再触发牌面选中。
var _is_hand_dragging: bool = false

## 当前由本组件追踪的触点索引；默认-1表示没有触摸，组件只处理首个落下的单指以避免多指误操作。
var _active_touch_index: int = -1

## 当前触点按下时的全局画布坐标；用于判断长按抖动与手牌拖动阈值。
var _touch_press_global_position: Vector2 = Vector2.ZERO

## 当前触点最近一次全局画布坐标；长按异步检查通过该值确认手指没有明显移动。
var _touch_current_global_position: Vector2 = Vector2.ZERO

## 当前触摸是否已经触发卡牌说明；为true时松手只关闭说明，不再额外选中卡牌。
var _touch_information_active: bool = false

## 当前触摸序列编号；每次按下或结束都会递增，使旧的异步长按计时安全失效。
var _touch_sequence_id: int = 0


## 初始化透明输入区域的鼠标语义并连接悬停信号。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(hover_started.emit)
	mouse_exited.connect(hover_finished.emit)


## 更新当前卡牌的输入参数；该方法不读取卡牌定义或对局快照。
func configure(uid: int, interactable: bool, reorder_zone: String = "") -> void:
	card_uid = uid
	is_interactable = interactable
	hand_reorder_zone = reorder_zone
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactable or not hand_reorder_zone.is_empty() else Control.CURSOR_ARROW


## 安全消费当前输入事件；拖拽完成回调可能重建并移除本输入节点，因此视口为空时只跳过消费标记。
func _mark_input_as_handled() -> void:
	# 当前所在视口；节点仍在场景树时写入输入已消费状态，重建后为空属于正常生命周期。
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## 记录左键按下位置；释放与拖动跟踪统一在_input中处理，保证鼠标离开原牌后仍由同一实体完成本次交互。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；只有左键按下会开启本次点击或直接拖动判定。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_pointer_pressed = true
			_is_hand_dragging = false
			_pointer_press_global_position = get_global_mouse_position()
			accept_event()
	elif event is InputEventScreenTouch:
		if _uses_touch_mouse_emulation():
			return
		# 当前触屏按下事件；只接管尚未被本组件追踪的首个触点，多指不会重复选择同一张牌。
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.pressed and _active_touch_index < 0:
			_active_touch_index = touch_event.index
			_touch_press_global_position = touch_event.position
			_touch_current_global_position = touch_event.position
			_touch_information_active = false
			_is_hand_dragging = false
			_touch_sequence_id += 1
			_start_touch_information_timer(_touch_sequence_id, touch_event.index)
			accept_event()


## 处理按下后的全局鼠标事件；直接移动原牌节点，不创建拖拽预览或临时卡牌实体。
func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		if _uses_touch_mouse_emulation():
			return
		# 当前触屏拖动事件；仅匹配本组件记录的触点，防止第二根手指改变选牌或排序状态。
		var touch_drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		if touch_drag_event.index != _active_touch_index:
			return
		_touch_current_global_position = touch_drag_event.position
		# 当前触点相对按下位置的移动距离；同时用于取消长按说明和启动手牌排序。
		var touch_drag_distance: float = _touch_current_global_position.distance_to(_touch_press_global_position)
		if _touch_information_active and touch_drag_distance > touch_hold_movement_tolerance:
			_touch_information_active = false
			hover_finished.emit()
		if not _is_hand_dragging and not hand_reorder_zone.is_empty() and card_uid >= 0 and touch_drag_distance >= HAND_DRAG_START_DISTANCE:
			_is_hand_dragging = true
			hand_drag_started.emit(card_uid, _touch_current_global_position)
		if _is_hand_dragging:
			hand_drag_moved.emit(card_uid, _touch_current_global_position)
		_mark_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if _uses_touch_mouse_emulation():
			return
		# 当前触屏释放事件；即使手指离开原牌区域，也由全局输入统一结束本次点击、长按或拖动。
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.index != _active_touch_index or touch_event.pressed:
			return
		_touch_current_global_position = touch_event.position
		# 本次触摸是否完成了实体手牌拖动；保存后立即清理状态，避免回调刷新牌面时读到陈旧输入。
		var completed_touch_drag: bool = _is_hand_dragging
		# 本次触摸是否已经展示过说明；长按释放只关闭说明，不能同时触发一次选牌。
		var completed_touch_information: bool = _touch_information_active
		_active_touch_index = -1
		_is_hand_dragging = false
		_touch_information_active = false
		_touch_sequence_id += 1
		if completed_touch_information:
			hover_finished.emit()
		if completed_touch_drag:
			hand_drag_finished.emit(card_uid, _touch_current_global_position)
		elif not completed_touch_information and is_interactable:
			activated.emit()
		_mark_input_as_handled()
		return
	if not _pointer_pressed:
		return
	if event is InputEventMouseMotion:
		# 当前鼠标全局坐标；同一坐标会同时驱动起拖判定与已开始拖动的实体牌跟随。
		var pointer_global_position: Vector2 = get_global_mouse_position()
		if not _is_hand_dragging and not hand_reorder_zone.is_empty() and card_uid >= 0 and pointer_global_position.distance_to(_pointer_press_global_position) >= HAND_DRAG_START_DISTANCE:
			_is_hand_dragging = true
			hand_drag_started.emit(card_uid, pointer_global_position)
		if _is_hand_dragging:
			hand_drag_moved.emit(card_uid, pointer_global_position)
		return
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；左键释放统一结束点击或直接拖动，防止离开原牌后丢失释放事件。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or mouse_event.pressed:
			return
		var release_global_position: Vector2 = get_global_mouse_position()
		var completed_hand_drag: bool = _is_hand_dragging
		_pointer_pressed = false
		_is_hand_dragging = false
		if completed_hand_drag:
			hand_drag_finished.emit(card_uid, release_global_position)
		elif is_interactable:
			activated.emit()
		_mark_input_as_handled()


## 等待触屏长按阈值后请求卡牌说明；序列号、触点和移动距离共同防止旧计时器误触发。
func _start_touch_information_timer(sequence_id: int, touch_index: int) -> void:
	await get_tree().create_timer(touch_information_hold_seconds).timeout
	if not is_inside_tree() or sequence_id != _touch_sequence_id or touch_index != _active_touch_index:
		return
	if _is_hand_dragging or _touch_current_global_position.distance_to(_touch_press_global_position) > touch_hold_movement_tolerance:
		return
	_touch_information_active = true
	hover_started.emit()


## 返回项目是否已把触点转换为鼠标事件；开启时自定义组件只处理模拟鼠标，避免同一次触摸重复激活。
func _uses_touch_mouse_emulation() -> bool:
	return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false))
