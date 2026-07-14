class_name PlayerTargetInputArea
extends Control

## 武将牌输入区域。该组件只处理点击与卡牌拖放，不负责武将牌渲染或目标规则判断。

## 鼠标左键激活武将牌时发出的信号；武将牌根节点会携带玩家 ID 向桌面转发。
signal activated

## 合法卡牌拖放完成时发出的信号；参数为稳定实体牌 UID。
signal card_dropped(card_uid: int)

## 当前武将牌是否允许点击与接收拖放；默认 false，由公开存活状态动态修改。
var is_interactable: bool = false

## 当前武将牌是否是所拖卡牌的合法目标；默认 false，由规则预览动态修改。
var accepts_card_drop: bool = false


## 初始化覆盖整张武将牌的透明输入区域。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 更新武将牌输入权限；该方法不保存玩家快照或访问规则服务。
func configure(interactable: bool, accepts_drop: bool) -> void:
	is_interactable = interactable
	accepts_card_drop = accepts_drop
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactable else Control.CURSOR_ARROW


## 把左键释放转换为武将牌激活信号。
func _gui_input(event: InputEvent) -> void:
	if not is_interactable:
		return
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；只响应左键释放，避免一次点击产生重复目标切换。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			activated.emit()
			accept_event()


## 只接受 CardView 输入区域提供的稳定战斗卡牌拖放字典。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_interactable and accepts_card_drop and data is Dictionary and str((data as Dictionary).get("drag_type", "")) == "battle_card"


## 把合法拖放转换为稳定卡牌 UID 信号，不直接修改桌面选择集合。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# 被拖放卡牌 UID；负数表示来源数据无效，不向上层发送。
	var dropped_card_uid: int = int((data as Dictionary).get("card_uid", -1))
	if dropped_card_uid >= 0:
		card_dropped.emit(dropped_card_uid)
