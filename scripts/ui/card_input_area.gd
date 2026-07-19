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

## 当前实体牌 UID；由牌面配置写入，未配置时为 -1，运行时随卡牌复用而更新。
var card_uid: int = -1

## 当前输入区域是否接受左键选牌；默认 false，桌面根据行动权限动态修改，手牌排序拖拽独立由分区字段控制。
var is_interactable: bool = false

## 当前拖拽预览创建回调；由卡牌根节点提供完整牌面副本，不参与规则状态修改。
var drag_preview_factory: Callable

## 当前牌所属的本地排序分区；空字符串表示该牌不是正式手牌，不能开始或接收排序拖拽。
var hand_reorder_zone: String = ""


## 初始化透明输入区域的鼠标语义并连接悬停信号。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(hover_started.emit)
	mouse_exited.connect(hover_finished.emit)


## 更新当前卡牌的输入参数；该方法不读取卡牌定义或对局快照。
func configure(uid: int, interactable: bool, preview_factory: Callable, reorder_zone: String = "") -> void:
	card_uid = uid
	is_interactable = interactable
	drag_preview_factory = preview_factory
	hand_reorder_zone = reorder_zone
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_interactable or not hand_reorder_zone.is_empty() else Control.CURSOR_ARROW


## 把左键释放转换为激活信号，避免牌面根节点依赖 Button 类型。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；只响应左键释放，保持与普通按钮一致的单次点击语义。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if is_interactable and mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			activated.emit()
			accept_event()


## 返回本地手牌排序拖拽数据，并使用完整牌面视觉副本作为原生拖拽预览；该数据不再包含角色目标选择语义。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if hand_reorder_zone.is_empty() or card_uid < 0:
		return null
	if drag_preview_factory.is_valid():
		# 完整牌面预览；只复制表现节点，不复制卡牌输入区域或权威状态。
		var preview: Control = drag_preview_factory.call() as Control
		if preview != null:
			set_drag_preview(preview)
	return {"drag_type":"hand_reorder", "card_uid":card_uid, "hand_reorder_zone":hand_reorder_zone}


## 只接受来自同一手牌分区的排序拖拽；木牛“粮”与普通手牌使用不同分区，禁止跨区调整顺序。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if hand_reorder_zone.is_empty() or not (data is Dictionary):
		return false
	# 拖拽来源数据；只有同分区的另一张有效实体牌才能作为排序来源。
	var drag_data: Dictionary = data as Dictionary
	return str(drag_data.get("drag_type", "")) == "hand_reorder" and str(drag_data.get("hand_reorder_zone", "")) == hand_reorder_zone and int(drag_data.get("card_uid", -1)) >= 0 and int(drag_data.get("card_uid", -1)) != card_uid


## 将同分区手牌的拖拽位置转换为插入目标前或后；实际排序由上层桌面维护，输入组件不读取卡牌或对局状态。
func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	# 拖拽来源 UID；已由_can_drop_data确认其有效且不等于当前目标牌。
	var source_card_uid: int = int((data as Dictionary).get("card_uid", -1))
	# 投放半区；落在目标牌右半边表示插入其后，左半边表示插入其前。
	var insert_after_target: bool = at_position.x >= size.x * 0.5
	hand_reorder_requested.emit(source_card_uid, card_uid, insert_after_target)
