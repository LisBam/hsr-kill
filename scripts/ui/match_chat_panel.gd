class_name MatchChatPanel
extends Control

## 局内聊天窗口组件。窗口由“菜单”按钮下方的“聊天”按钮切换显隐，提供历史消息浏览与消息发送输入。
## 组件全部节点在代码中构建（与 InformationBoxLayer 的运行时创建方式一致），只发出纯文本聊天意图；
## 消息的权威登记、署名与广播由 NetworkGateway 负责，头顶气泡由牌桌负责，本组件不访问规则状态或网络。

## 玩家提交一条聊天正文时发出；桌面转交给 NetworkGateway.send_match_chat_message 统一处理。
signal chat_submitted(message: String)

## 玩家点击右上角关闭按钮时发出；桌面据此收起窗口并把焦点交还牌桌。
signal close_requested

## 聊天窗口绘制层级；高于“记录”日志面板（35）与头顶气泡，低于主菜单（60）与局内菜单（500）。
const PANEL_Z_INDEX: int = 45

## 聊天窗口宽度像素；与局内菜单展开面板同级的右侧竖窗宽度，容纳署名与短正文同行不换行。
@export var panel_width: float = 340.0

## 聊天窗口高度像素；默认400在1280×720逻辑画布下不遮挡底部手牌区。
@export var panel_height: float = 400.0

## 聊天窗口距客户区右边界的像素；与“菜单”按钮右缘（18像素）对齐。
@export var panel_right_margin: float = 18.0

## 聊天窗口距客户区上边界的像素；默认100位于“聊天”按钮（92像素底边）下方留8像素间隔。
@export var panel_top_margin: float = 100.0

## 窗口外框面板；承载标题行、历史区与输入行，主题变化时重绘背景与描边。
var _frame: PanelContainer = null

## 窗口标题标签；固定文本“聊天”，使用主题主要文字色。
var _title_label: Label = null

## 右上角关闭按钮；只发出关闭意图，不清空历史。
var _close_button: Button = null

## 历史消息正文；纯文本渲染（不启用BBCode），防止聊天内容注入富文本标记。
var _history_view: RichTextLabel = null

## 消息输入框；最大长度与网关对局聊天上限一致，回车与发送按钮共用提交入口。
var _input_field: LineEdit = null

## 发送按钮；提交后清空输入框并在焦点结算完成的下一帧恢复输入焦点，支持连续输入。
var _send_button: Button = null


## 构建窗口节点树并应用初始主题；窗口默认隐藏，等待“聊天”按钮切换。
func _ready() -> void:
	# 终局或离线暂停期间聊天仍需可用；窗口不推进任何规则状态，常时处理是安全的。
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = PANEL_Z_INDEX
	visible = false
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -panel_right_margin - panel_width
	offset_right = -panel_right_margin
	offset_top = panel_top_margin
	offset_bottom = panel_top_margin + panel_height
	_build_interface()
	refresh_ui_style()


## 创建窗口内部控件；仅在 _ready 调用一次，后续主题切换只重绘样式不重建节点。
func _build_interface() -> void:
	_frame = PanelContainer.new()
	_frame.name = "MatchChatFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	# 内容纵向容器；标题行、可扩展历史区与输入行按固定顺序排列。
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_frame.add_child(content)
	# 标题行容器；左侧标题与右侧关闭按钮之间以弹性占位分隔。
	var title_row: HBoxContainer = HBoxContainer.new()
	content.add_child(title_row)
	_title_label = Label.new()
	_title_label.name = "MatchChatTitle"
	_title_label.text = "聊天"
	_title_label.add_theme_font_size_override("font_size", 18)
	title_row.add_child(_title_label)
	# 标题行弹性占位；把关闭按钮推到右缘。
	var title_spacer: Control = Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_spacer)
	_close_button = Button.new()
	_close_button.name = "MatchChatCloseButton"
	_close_button.text = "关闭"
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.pressed.connect(_on_close_pressed)
	title_row.add_child(_close_button)
	_history_view = RichTextLabel.new()
	_history_view.name = "MatchChatHistory"
	_history_view.bbcode_enabled = false
	_history_view.scroll_active = true
	_history_view.scroll_following = true
	_history_view.selection_enabled = true
	_history_view.focus_mode = Control.FOCUS_NONE
	_history_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_history_view)
	# 输入行容器；输入框占满剩余宽度，发送按钮固定在右侧。
	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	content.add_child(input_row)
	_input_field = LineEdit.new()
	_input_field.name = "MatchChatInput"
	_input_field.max_length = NetworkGateway.MAX_MATCH_CHAT_LENGTH
	_input_field.placeholder_text = "输入聊天内容…"
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.text_submitted.connect(_on_input_text_submitted)
	input_row.add_child(_input_field)
	_send_button = Button.new()
	_send_button.name = "MatchChatSendButton"
	_send_button.text = "发送"
	_send_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_send_button.pressed.connect(_submit_chat_message)
	input_row.add_child(_send_button)


## 返回窗口当前是否展开；桌面据此实现“聊天”按钮的切换语义。
func is_open() -> bool:
	return visible


## 展开聊天窗口并重建历史正文；entries 为网关聊天历史的只读副本。
func open_panel(entries: Array[Dictionary]) -> void:
	set_history(entries)
	visible = true


## 收起聊天窗口；历史内容保留在网关中，再次展开时重建正文。
func close_panel() -> void:
	visible = false


## 用完整历史重建聊天正文；条目格式与 NetworkGateway 的对局聊天条目一致。
func set_history(entries: Array[Dictionary]) -> void:
	# 历史文本行集合；逐条格式化后一次性写入，避免逐条追加造成的多次排版。
	var lines: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		lines.append(_format_entry(entry))
	_history_view.text = "\n".join(lines)
	call_deferred("_scroll_history_to_bottom")


## 追加单条聊天条目到正文末尾；窗口收起时也保持正文同步，展开后无需整体重建。
func append_entry(entry: Dictionary) -> void:
	if _history_view.text.is_empty():
		_history_view.text = _format_entry(entry)
	else:
		_history_view.text += "\n" + _format_entry(entry)
	call_deferred("_scroll_history_to_bottom")


## 清空聊天正文；新一局开始时由桌面调用，与网关历史清空保持一致。
func clear_history() -> void:
	_history_view.text = ""


## 刷新活动 UI 风格；窗口背景、标题、正文、输入框与按钮统一读取当前主题语义色。
func refresh_ui_style() -> void:
	if _frame == null:
		return
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 2, 8))
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_history_view.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	BattleUIStyle.apply_interaction_button(_close_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_send_button)
	_input_field.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_input_field.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))


## 把单条聊天条目格式化为纯文本行；固定“玩家名：消息”结构，与联机大厅聊天一致，不显示时间。
func _format_entry(entry: Dictionary) -> String:
	return "%s：%s" % [str(entry.get("display_name", "玩家")), str(entry.get("message", ""))]


## 提交当前输入框内容；空白消息不发出信号，成功提交后清空输入并恢复焦点便于连续聊天。
func _submit_chat_message() -> void:
	# 待提交正文；首尾空白由网关统一标准化，此处只拦截纯空白提交。
	var message: String = _input_field.text
	if message.strip_edges().is_empty():
		return
	chat_submitted.emit(message)
	_input_field.clear()
	call_deferred("_restore_input_focus_after_submit")


## 回车提交入口；与发送按钮共用同一提交实现。
func _on_input_text_submitted(_text: String) -> void:
	_submit_chat_message()


## 发送后的焦点恢复；按钮焦点结算完成的下一帧把焦点还给输入框，窗口已收起时不抢占焦点。
func _restore_input_focus_after_submit() -> void:
	if visible and _input_field != null:
		_input_field.grab_focus()


## 关闭按钮响应；收起窗口并通知桌面归还焦点。
func _on_close_pressed() -> void:
	close_panel()
	close_requested.emit()


## 滚动历史区到底部；延迟到排版完成后的空闲帧执行，保证新消息立即可见。
func _scroll_history_to_bottom() -> void:
	if _history_view != null:
		_history_view.scroll_to_line(maxi(_history_view.get_line_count() - 1, 0))
