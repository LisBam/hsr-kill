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

## 当前武将牌是否允许点击；默认 false，由公开存活状态动态修改。
var is_interactable: bool = false


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
