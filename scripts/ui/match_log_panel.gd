class_name MatchLogPanel
extends Control

## 可折叠对局日志组件。组件只管理日志面板的展开状态和按钮文本，不读取对局状态或提交规则动作。

## 日志展开状态改变时发出的界面信号；牌桌协调器可据此实现离线暂停等外围行为，组件自身不读取通信模式。
signal expanded_changed(expanded: bool)

## 点击未被控件消费的牌桌空白区域时发出的信号；牌桌协调器据此统一收起记录与局内菜单。
signal blank_area_pressed

## 展开按钮显示文本；默认“记录”，用于牌桌左侧常驻入口，运行时通常无需动态修改。
@export var collapsed_button_text: String = "记录"

## 收起按钮显示文本；默认“收起记录”，明确提示再次点击会隐藏日志内容，运行时通常无需动态修改。
@export var expanded_button_text: String = "收起记录"

## 日志展开按钮；始终保持可见并独立接收鼠标输入。
@onready var _toggle_button: Button = %LogToggleButton

## 日志正文面板；默认隐藏，展开后显示标题与可滚动日志文本。
@onready var _content_panel: PanelContainer = %LogContentPanel

## 日志正文控件；仅在面板展开时持有排版文本，折叠期间保持为空以消除长局隐藏文本的持续布局成本。
@onready var _log_view: RichTextLabel = %LogView

## 当前日志是否展开；仅控制界面可见性，不影响日志内容的持续追加。
var _is_expanded: bool = false

## 本局完整语义日志；每项保存一条不可变纯文本，折叠与展开不会丢失历史，重新开局时由牌桌显式清空。
var _log_entries: Array[String] = []

## 已进入完整历史但尚未批量写入正文控件的日志；只在展开状态使用，同一帧多条规则日志会合并为一次排版更新。
var _pending_render_entries: Array[String] = []

## 当前是否已经安排延迟渲染；默认false，确保一帧内无论新增多少条日志都只登记一次回调。
var _render_flush_scheduled: bool = false


## 连接展开按钮并应用默认折叠状态。
func _ready() -> void:
	# 日志按钮需要在离线对局暂停后继续接收输入，始终处理模式不会改变规则节点的暂停状态。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_toggle_button.pressed.connect(_toggle_log)
	_set_expanded(false)


## 切换日志正文显隐；隐藏期间新增日志仍由原文本节点保存，重新展开即可查看。
func _toggle_log() -> void:
	_set_expanded(not _is_expanded)


## 返回对局记录当前是否展开；牌桌用该只读状态判断空白点击是否需要收起浮层。
func is_expanded() -> bool:
	return _is_expanded


## 公开设置对局记录显隐；空白点击与按钮切换共用同一状态入口，确保暂停信号始终成对发送。
func set_expanded(expanded: bool) -> void:
	_set_expanded(expanded)


## 追加一条永久语义日志；组件始终保存完整历史，但折叠期间不会向RichTextLabel写入任何文本。
func append_entry(message: String) -> void:
	_log_entries.append(message)
	if not _is_expanded:
		return
	_pending_render_entries.append(message)
	_schedule_render_flush()


## 清空本局全部语义日志与待渲染内容；重新开局和离开联机会通过该入口释放长局文本。
func clear_entries() -> void:
	_log_entries.clear()
	_pending_render_entries.clear()
	_render_flush_scheduled = false
	if _log_view != null:
		_log_view.clear()


## 返回当前保存的完整日志条数；性能回归与调试器可读取数量，但不能修改内部历史。
func get_entry_count() -> int:
	return _log_entries.size()


## 返回当前正文控件持有的字符数；折叠状态应恒为0，用于确认隐藏面板没有保留排版文档。
func get_rendered_character_count() -> int:
	return 0 if _log_view == null else _log_view.get_parsed_text().length()


## 在离线日志暂停期间继续监听未被界面消费的左键；只上报关闭意图，不直接引用菜单或暂停服务。
func _unhandled_input(event: InputEvent) -> void:
	if not _is_expanded:
		return
	if event is InputEventMouseButton:
		# 当前鼠标事件；只有按下左键且没有被日志正文、按钮或其他控件消费时才视为点击空白区域。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			blank_area_pressed.emit()


## 统一写入展开状态、正文可见性和按钮文本，避免多个节点分别维护状态。
func _set_expanded(expanded: bool) -> void:
	# 展开状态是否实际变化；重复配置只同步视觉，不重复通知牌桌暂停协调器。
	var state_changed: bool = _is_expanded != expanded
	_is_expanded = expanded
	_content_panel.visible = _is_expanded
	_toggle_button.text = expanded_button_text if _is_expanded else collapsed_button_text
	if state_changed:
		expanded_changed.emit(_is_expanded)
	if _is_expanded:
		_render_complete_history()
	else:
		# 完整字符串历史仍由组件保留；释放隐藏RichTextLabel的行布局、滚动和字符缓存，长局主流程不再为不可见日志付费。
		_pending_render_entries.clear()
		_render_flush_scheduled = false
		_log_view.clear()


## 安排一次帧末批量追加；多条同步规则日志共享同一延迟回调，避免重复排版和滚动。
func _schedule_render_flush() -> void:
	if _render_flush_scheduled:
		return
	_render_flush_scheduled = true
	call_deferred("_flush_pending_render_entries")


## 把展开期间积累的新增日志合并为一次正文追加，并在完成后滚动至最新一行。
func _flush_pending_render_entries() -> void:
	_render_flush_scheduled = false
	if not _is_expanded or _pending_render_entries.is_empty():
		_pending_render_entries.clear()
		return
	# 本批新增文本；一次join和append_text替代逐条触发布局，末尾换行保证下一批从新行开始。
	var appended_text: String = "\n".join(_pending_render_entries) + "\n"
	_pending_render_entries.clear()
	_log_view.append_text(appended_text)
	_log_view.scroll_to_line(maxi(_log_view.get_line_count() - 1, 0))


## 展开时用一次写入恢复完整历史；离线对局会先经expanded_changed取得暂停令牌，重排不会与规则流程争用帧时间。
func _render_complete_history() -> void:
	_pending_render_entries.clear()
	_render_flush_scheduled = false
	_log_view.clear()
	if _log_entries.is_empty():
		return
	# 完整日志文本；数组顺序就是权威信号到达顺序，单次构建不会改变任何日志句式或内容。
	var complete_text: String = "\n".join(_log_entries) + "\n"
	_log_view.append_text(complete_text)
	_log_view.scroll_to_line(maxi(_log_view.get_line_count() - 1, 0))
