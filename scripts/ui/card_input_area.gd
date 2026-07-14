class_name CardInputArea
extends Control

## 卡牌输入区域。该组件只把鼠标点击、悬停和拖拽转换为信号，不保存牌面数据或提交规则动作。

## 鼠标左键激活卡牌时发出的信号；卡牌根节点据此通知桌面更新临时选择。
signal activated

## 鼠标进入卡牌区域时发出的信号；只用于刷新牌面悬停表现。
signal hover_started

## 鼠标离开卡牌区域时发出的信号；只用于恢复牌面默认表现。
signal hover_finished

## 有效拖拽开始时发出的信号；参数为稳定实体牌 UID。
signal drag_started(card_uid: int)

## 当前实体牌 UID；由牌面配置写入，未配置时为 -1，运行时随卡牌复用而更新。
var card_uid: int = -1

## 当前输入区域是否接受点击与拖拽；默认 false，桌面根据行动权限动态修改。
var is_interactable: bool = false

## 当前拖拽预览创建回调；由卡牌根节点提供完整牌面副本，不参与规则状态修改。
var drag_preview_factory: Callable


## 初始化透明输入区域的鼠标语义并连接悬停信号。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(hover_started.emit)
	mouse_exited.connect(hover_finished.emit)


## 更新当前卡牌的输入参数；该方法不读取卡牌定义或对局快照。
func configure(uid: int, interactable: bool, preview_factory: Callable) -> void:
	card_uid = uid
	is_interactable = interactable
	drag_preview_factory = preview_factory
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactable else Control.CURSOR_ARROW


## 把左键释放转换为激活信号，避免牌面根节点依赖 Button 类型。
func _gui_input(event: InputEvent) -> void:
	if not is_interactable:
		return
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；只响应左键释放，保持与普通按钮一致的单次点击语义。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			activated.emit()
			accept_event()


## 返回稳定卡牌拖拽数据，并使用完整牌面视觉副本作为原生拖拽预览。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_interactable or card_uid < 0:
		return null
	drag_started.emit(card_uid)
	if drag_preview_factory.is_valid():
		# 完整牌面预览；只复制表现节点，不复制卡牌输入区域或权威状态。
		var preview: Control = drag_preview_factory.call() as Control
		if preview != null:
			set_drag_preview(preview)
	return {"drag_type":"battle_card", "card_uid":card_uid}
