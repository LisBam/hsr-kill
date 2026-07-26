class_name MatchReplayPanel
extends Control

## 主菜单“对局回放”内容页组件。左侧列出本地已保存的 .lisbam_replay 回放并提供导入入口，
## 右侧展示所选回放的资料与播放、重命名、顶置、导出、删除操作。
## 点击“播放”只发出播放意图信号；实际回放重演由牌桌以第一视角在正式对局界面完成，
## 本组件不再内置迷你播放器，也不创建 GameState、对局运行时、网络会话或任何规则状态。

## 玩家请求关闭本内容页时发出；主菜单据此恢复模式选择页与顶部导航焦点。
signal close_requested

## 玩家请求播放所选回放时发出；file_name 为回放目录内的稳定文件名。
## 主菜单把该意图转交牌桌：牌桌载入回放并像进入一场新对局一样从头重演，本组件不接触重演过程。
signal playback_requested(file_name: String)

## 回放名称允许的最大 Unicode 字符数；与结算面板保存命名弹窗一致，保证列表条目单行可读。
const REPLAY_NAME_MAX_LENGTH: int = 60

## 顶置回放在列表条目文本中的前缀标记；纯文本星号避免依赖图标资源，主题无关。
const PINNED_ENTRY_PREFIX: String = "★ "

## 回放目录覆盖路径；自动化测试写入独立目录避免污染玩家回放，空字符串表示使用正式目录。
var replay_directory_override: String = ""

## 浏览模式根容器；列表与详情两栏。
var _browser_content: HBoxContainer = null

## 外框面板；与“所有卡牌”内容页同级的整页容器。
var _frame: PanelContainer = null

## 左侧列表标题标签；固定文本“对局回放”。
var _side_title_label: Label = null

## 导入回放按钮；打开路径输入模态，从任意本地路径复制回放进入回放目录。
var _import_button: Button = null

## 列表提示标签；显示回放数量或空列表说明。
var _list_hint_label: Label = null

## 回放条目按钮容器；每个已保存回放对应一个可选中按钮。
var _list_container: VBoxContainer = null

## 列表滚动区；条目超过可视高度时纵向滚动。
var _list_scroll: ScrollContainer = null

## 右侧详情标题标签；显示所选回放文件名。
var _detail_title_label: Label = null

## 右侧详情正文标签；逐行显示模式、人数、视角、时长、步骤数与保存时间。
var _detail_body_label: Label = null

## 播放按钮；发出播放意图，由牌桌进入第一视角整局重演。
var _play_button: Button = null

## 重命名按钮；打开名称输入模态，重命名所选回放文件。
var _rename_button: Button = null

## 顶置按钮；切换所选回放的顶置状态，顶置回放固定排在列表最前。
var _pin_button: Button = null

## 导出按钮；打开路径输入模态，把所选回放复制到玩家指定位置。
var _export_button: Button = null

## 删除按钮；删除所选回放文件并刷新列表。
var _delete_button: Button = null

## 操作结果标签；显示导入、导出、重命名、顶置、删除与播放载入的成功或失败说明。
var _operation_status_label: Label = null

## 当前选中的回放条目；含 file_name、header、file_size 与 pinned，未选中时为空字典。
var _selected_entry: Dictionary = {}

## 当前列表条目按钮；按文件名索引，用于选中态样式切换。
var _entry_buttons: Dictionary = {}

## 输入模态遮罩；打开期间阻断底层输入。
var _modal_backdrop: ColorRect = null

## 输入模态面板；导入、导出与重命名共用，按当前模态用途区分行为。
var _modal_panel: PanelContainer = null

## 输入模态标题标签；显示“导入回放”“导出回放”或“重命名回放”。
var _modal_title_label: Label = null

## 输入模态提示标签；说明期望的路径形式或名称规则。
var _modal_hint_label: Label = null

## 模态输入框；导入导出时填写完整路径，重命名时填写新名称（不含后缀）。
var _modal_path_input: LineEdit = null

## 模态确认按钮；执行导入、导出或重命名。
var _modal_confirm_button: Button = null

## 模态取消按钮；关闭模态不执行操作。
var _modal_cancel_button: Button = null

## 当前模态用途；"import"、"export" 或 "rename"，空字符串表示模态未打开。
var _modal_mode: String = ""


## 初始化内容页；构建浏览界面与共享输入模态，默认隐藏等待主菜单打开。
func _ready() -> void:
	visible = false
	_build_interface()
	refresh_ui_style()
	if GameSettings != null:
		GameSettings.ui_style_changed.connect(_on_ui_style_changed)


## 打开内容页；刷新回放列表并聚焦主控件，与其他主菜单内容页保持同一打开契约。
func open_panel() -> void:
	visible = true
	move_to_front()
	refresh_replay_list()
	refresh_ui_style()
	call_deferred("_focus_primary_control")


## 关闭内容页；共享模态一并收起，选中状态保留供下次打开恢复详情。
func close_panel() -> void:
	_close_path_modal()
	visible = false


## 在操作结果标签上显示一条说明；牌桌回放载入失败时经主菜单转发到本入口。
func show_operation_status(message: String) -> void:
	if _operation_status_label != null:
		_operation_status_label.text = message


## 刷新已保存回放列表；重建左侧条目按钮并保持右侧详情与选中态一致。
func refresh_replay_list() -> void:
	for child: Node in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	# 当前目录内全部可解析回放；顶置条目在前，组内按保存时间倒序排列。
	var entries: Array[Dictionary] = MatchReplayStore.list_replays(_get_replay_directory())
	_list_hint_label.text = "共 %d 份回放" % entries.size() if not entries.is_empty() else "暂无已保存回放。战斗结束后在结算界面点击“保存回放”，或使用上方“导入回放”。"
	# 现存文件名集合；用于校正已选条目被删除或导入刷新后的选中状态。
	var available_file_names: Array[String] = []
	for entry: Dictionary in entries:
		# 当前回放条目；按钮正文显示可读名称与关键资料，稳定文件名保存在元数据中。
		var file_name: String = str(entry.get("file_name", ""))
		available_file_names.append(file_name)
		var entry_button: Button = Button.new()
		entry_button.text = _format_entry_button_text(entry)
		entry_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry_button.custom_minimum_size = Vector2(0.0, 44.0)
		entry_button.clip_text = true
		entry_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		entry_button.set_meta("replay_entry", entry)
		entry_button.pressed.connect(_on_entry_button_pressed.bind(entry_button))
		_list_container.add_child(entry_button)
		_entry_buttons[file_name] = entry_button
	if not available_file_names.has(str(_selected_entry.get("file_name", ""))):
		_selected_entry = {}
	elif not entries.is_empty():
		# 已选文件仍存在时刷新为最新头数据，保证详情与文件实际内容一致。
		for entry: Dictionary in entries:
			if str(entry.get("file_name", "")) == str(_selected_entry.get("file_name", "")):
				_selected_entry = entry
	_refresh_detail_section()
	refresh_ui_style()


## 刷新活动 UI 风格；全部静态文本、按钮与面板统一读取当前主题语义色。
func refresh_ui_style() -> void:
	if _frame == null:
		return
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), 2, 10))
	_side_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_list_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_detail_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_detail_body_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_operation_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_modal_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_modal_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_modal_path_input.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_modal_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("accent"), 2, 10))
	BattleUIStyle.apply_interaction_button(_import_button)
	BattleUIStyle.apply_interaction_button(_play_button)
	BattleUIStyle.apply_interaction_button(_rename_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_pin_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_export_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_delete_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("danger"), false)
	BattleUIStyle.apply_interaction_button(_modal_confirm_button)
	BattleUIStyle.apply_interaction_button(_modal_cancel_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	for entry_button_variant: Variant in _entry_buttons.values():
		# 当前列表条目按钮；选中条目使用强调描边，普通条目使用面板底色。
		var entry_button: Button = entry_button_variant as Button
		if entry_button == null:
			continue
		# 该按钮是否为当前选中条目；决定描边强调色。
		var is_selected: bool = str((entry_button.get_meta("replay_entry", {}) as Dictionary).get("file_name", "")) == str(_selected_entry.get("file_name", ""))
		BattleUIStyle.apply_interaction_button(entry_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent") if is_selected else BattleUIStyle.get_color("border"), is_selected)


## Esc 关闭链；优先关闭输入模态，其次交还整页关闭意图。
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if not _modal_mode.is_empty():
		_close_path_modal()
		accept_event()
		return
	accept_event()
	close_requested.emit()


## 构建整页界面；仅在 _ready 调用一次，浏览两栏与共享输入模态都在此创建。
func _build_interface() -> void:
	_frame = PanelContainer.new()
	_frame.name = "MatchReplayFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_build_browser_content()
	_build_path_modal()


## 构建浏览模式两栏；左侧列表栏宽度与其他内容页侧栏一致。
func _build_browser_content() -> void:
	_browser_content = HBoxContainer.new()
	_browser_content.name = "ReplayBrowserContent"
	_browser_content.add_theme_constant_override("separation", 14)
	_frame.add_child(_browser_content)
	# 左侧列表面板；固定286像素宽与“所有卡牌”侧栏对齐。
	var side_panel: PanelContainer = PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(286.0, 0.0)
	_browser_content.add_child(side_panel)
	# 左侧纵向布局；标题、导入按钮、数量提示与滚动列表。
	var side_vbox: VBoxContainer = VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 12)
	side_panel.add_child(side_vbox)
	_side_title_label = Label.new()
	_side_title_label.name = "ReplaySideTitle"
	_side_title_label.custom_minimum_size = Vector2(0.0, 48.0)
	_side_title_label.add_theme_font_size_override("font_size", 19)
	_side_title_label.text = "对局回放"
	_side_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	side_vbox.add_child(_side_title_label)
	_import_button = Button.new()
	_import_button.name = "ReplayImportButton"
	_import_button.text = "导入回放"
	_import_button.custom_minimum_size = Vector2(0.0, 40.0)
	_import_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_import_button.pressed.connect(_on_import_button_pressed)
	side_vbox.add_child(_import_button)
	_list_hint_label = Label.new()
	_list_hint_label.name = "ReplayListHint"
	_list_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_hint_label.add_theme_font_size_override("font_size", 13)
	side_vbox.add_child(_list_hint_label)
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_vbox.add_child(_list_scroll)
	_list_container = VBoxContainer.new()
	_list_container.name = "ReplayListContainer"
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 6)
	_list_scroll.add_child(_list_container)
	# 右侧详情纵向布局；标题、正文、操作行与结果提示。
	var detail_vbox: VBoxContainer = VBoxContainer.new()
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 12)
	_browser_content.add_child(detail_vbox)
	_detail_title_label = Label.new()
	_detail_title_label.name = "ReplayDetailTitle"
	_detail_title_label.custom_minimum_size = Vector2(0.0, 48.0)
	_detail_title_label.add_theme_font_size_override("font_size", 19)
	_detail_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail_vbox.add_child(_detail_title_label)
	_detail_body_label = Label.new()
	_detail_body_label.name = "ReplayDetailBody"
	_detail_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_vbox.add_child(_detail_body_label)
	# 操作按钮行；播放为主操作，重命名、顶置、导出为次级操作，删除使用危险描边。
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	detail_vbox.add_child(action_row)
	_play_button = Button.new()
	_play_button.name = "ReplayPlayButton"
	_play_button.text = "播放"
	_play_button.custom_minimum_size = Vector2(146.0, 42.0)
	_play_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_play_button.pressed.connect(_on_play_button_pressed)
	action_row.add_child(_play_button)
	_rename_button = Button.new()
	_rename_button.name = "ReplayRenameButton"
	_rename_button.text = "重命名"
	_rename_button.custom_minimum_size = Vector2(108.0, 42.0)
	_rename_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rename_button.pressed.connect(_on_rename_button_pressed)
	action_row.add_child(_rename_button)
	_pin_button = Button.new()
	_pin_button.name = "ReplayPinButton"
	_pin_button.text = "顶置回放"
	_pin_button.custom_minimum_size = Vector2(108.0, 42.0)
	_pin_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pin_button.pressed.connect(_on_pin_button_pressed)
	action_row.add_child(_pin_button)
	_export_button = Button.new()
	_export_button.name = "ReplayExportButton"
	_export_button.text = "导出回放"
	_export_button.custom_minimum_size = Vector2(108.0, 42.0)
	_export_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_export_button.pressed.connect(_on_export_button_pressed)
	action_row.add_child(_export_button)
	_delete_button = Button.new()
	_delete_button.name = "ReplayDeleteButton"
	_delete_button.text = "删除回放"
	_delete_button.custom_minimum_size = Vector2(108.0, 42.0)
	_delete_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_delete_button.pressed.connect(_on_delete_button_pressed)
	action_row.add_child(_delete_button)
	_operation_status_label = Label.new()
	_operation_status_label.name = "ReplayOperationStatus"
	_operation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_operation_status_label.add_theme_font_size_override("font_size", 13)
	detail_vbox.add_child(_operation_status_label)


## 构建导入、导出与重命名共用的输入模态；遮罩阻断底层输入，Esc 与取消按钮关闭。
func _build_path_modal() -> void:
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.name = "ReplayPathModalBackdrop"
	_modal_backdrop.visible = false
	_modal_backdrop.color = Color(0.0, 0.0, 0.0, 0.62)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.z_index = 8
	add_child(_modal_backdrop)
	_modal_panel = PanelContainer.new()
	_modal_panel.name = "ReplayPathModalPanel"
	_modal_panel.visible = false
	_modal_panel.z_index = 9
	_modal_panel.custom_minimum_size = Vector2(560.0, 0.0)
	_modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	_modal_panel.offset_left = -280.0
	_modal_panel.offset_right = 280.0
	_modal_panel.offset_top = -110.0
	_modal_panel.offset_bottom = 110.0
	add_child(_modal_panel)
	# 模态纵向布局；标题、提示、输入与按钮行。
	var modal_vbox: VBoxContainer = VBoxContainer.new()
	modal_vbox.add_theme_constant_override("separation", 12)
	_modal_panel.add_child(modal_vbox)
	_modal_title_label = Label.new()
	_modal_title_label.name = "ReplayPathModalTitle"
	_modal_title_label.add_theme_font_size_override("font_size", 18)
	_modal_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_vbox.add_child(_modal_title_label)
	_modal_hint_label = Label.new()
	_modal_hint_label.name = "ReplayPathModalHint"
	_modal_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_hint_label.add_theme_font_size_override("font_size", 13)
	modal_vbox.add_child(_modal_hint_label)
	_modal_path_input = LineEdit.new()
	_modal_path_input.name = "ReplayPathModalInput"
	_modal_path_input.custom_minimum_size = Vector2(0.0, 36.0)
	_modal_path_input.text_submitted.connect(func(_text: String) -> void: _on_modal_confirm_pressed())
	modal_vbox.add_child(_modal_path_input)
	# 模态按钮行；确认在左、取消在右并水平居中。
	var modal_button_row: HBoxContainer = HBoxContainer.new()
	modal_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	modal_button_row.add_theme_constant_override("separation", 20)
	modal_vbox.add_child(modal_button_row)
	_modal_confirm_button = Button.new()
	_modal_confirm_button.name = "ReplayPathModalConfirm"
	_modal_confirm_button.text = "确认"
	_modal_confirm_button.custom_minimum_size = Vector2(120.0, 38.0)
	_modal_confirm_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_modal_confirm_button.pressed.connect(_on_modal_confirm_pressed)
	modal_button_row.add_child(_modal_confirm_button)
	_modal_cancel_button = Button.new()
	_modal_cancel_button.name = "ReplayPathModalCancel"
	_modal_cancel_button.text = "取消"
	_modal_cancel_button.custom_minimum_size = Vector2(120.0, 38.0)
	_modal_cancel_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_modal_cancel_button.pressed.connect(_close_path_modal)
	modal_button_row.add_child(_modal_cancel_button)


## 返回当前实际使用的回放目录；测试覆盖优先，正式运行使用存储层默认目录。
func _get_replay_directory() -> String:
	return replay_directory_override if not replay_directory_override.is_empty() else MatchReplayStore.REPLAY_DIRECTORY


## 把回放条目格式化为列表按钮文本；显示回放名（文件基础名），顶置条目附加星号前缀。
func _format_entry_button_text(entry: Dictionary) -> String:
	# 该条目的顶置前缀；未顶置时为空字符串。
	var pin_prefix: String = PINNED_ENTRY_PREFIX if bool(entry.get("pinned", false)) else ""
	return "%s%s" % [pin_prefix, str(entry.get("file_name", "")).get_basename()]


## 把模式稳定 ID 解析为玩家可读名称；复用网关的大厅模式表，未知 ID 原样显示。
func _resolve_mode_display_name(mode_id: String) -> String:
	for mode_option: Dictionary in NetworkGateway.LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) == mode_id:
			return str(mode_option.get("display_name", mode_id))
	return mode_id


## 刷新右侧详情栏；未选中回放时显示引导文案，选中时逐行显示回放头资料。
func _refresh_detail_section() -> void:
	# 是否存在已选条目；操作按钮只在选中后可用。
	var has_selection: bool = not _selected_entry.is_empty()
	_play_button.disabled = not has_selection
	_rename_button.disabled = not has_selection
	_pin_button.disabled = not has_selection
	_export_button.disabled = not has_selection
	_delete_button.disabled = not has_selection
	_pin_button.text = "取消顶置" if bool(_selected_entry.get("pinned", false)) else "顶置回放"
	if not has_selection:
		_detail_title_label.text = "选择一份回放"
		_detail_body_label.text = "从左侧列表选择回放后，可在此播放、重命名、顶置、导出到指定路径或删除。\n播放会进入牌桌，以录制时的第一视角完整重演该对局。\n回放文件后缀为 .%s。" % MatchReplayStore.REPLAY_FILE_EXTENSION
		return
	# 已选条目的回放头；全部字段来自保存时的公开快照。
	var header: Dictionary = _selected_entry.get("header", {}) as Dictionary
	_detail_title_label.text = str(_selected_entry.get("file_name", ""))
	# 详情正文行集合；逐项列出资料后合并为多行文本。
	var lines: PackedStringArray = PackedStringArray()
	lines.append("保存时间：%s" % _format_saved_time_text(int(header.get("saved_at_unix", 0))))
	lines.append("模式：%s" % _resolve_mode_display_name(str(header.get("match_mode", ""))))
	lines.append("人数：%d" % int(header.get("player_count", 0)))
	lines.append("回放视角：%s" % _resolve_viewer_text(header))
	lines.append("对局状态：%s" % ("已结束" if bool(header.get("game_over", false)) else "未结束"))
	lines.append("时长：%s" % _format_duration_text(int(header.get("duration_msec", 0))))
	lines.append("步骤：%d（快照 %d / 日志 %d / 表现 %d）" % [int(header.get("step_count", 0)), int(header.get("snapshot_count", 0)), int(header.get("log_count", 0)), int(header.get("presentation_count", 0))])
	lines.append("文件大小：%.1f KB" % (float(int(_selected_entry.get("file_size", 0))) / 1024.0))
	if bool(_selected_entry.get("pinned", false)):
		lines.append("已顶置：该回放固定显示在列表最前。")
	if bool(header.get("truncated", false)):
		lines.append("提示：该回放超过步骤上限，尾部未完整录制。")
	# 参战角色行；逐名玩家列出显示名与已公开武将。
	lines.append("")
	lines.append("参战角色：")
	for player_variant: Variant in header.get("players", []) as Array:
		# 当前玩家回放头条目；武将未公开时只显示玩家名。
		var player: Dictionary = player_variant as Dictionary
		# 该玩家武将显示名；来自静态数据库解析，缺失时为空。
		var character_name: String = GameDatabase.resolve_character_name(str(player.get("character_id", ""))) if not str(player.get("character_id", "")).is_empty() else ""
		lines.append("  %s%s" % [str(player.get("display_name", "玩家")), "（%s）" % character_name if not character_name.is_empty() else ""])
	_detail_body_label.text = "\n".join(lines)


## 把保存时刻的 Unix 时间格式化为本地“年-月-日 时:分”；仅在详情正文展示，不参与排序。
func _format_saved_time_text(saved_at_unix: int) -> String:
	# 保存时刻的本地时间字典；按系统时区偏移换算。
	var saved_time: Dictionary = Time.get_datetime_dict_from_unix_time(saved_at_unix + Time.get_time_zone_from_system().get("bias", 0) * 60)
	return "%04d-%02d-%02d %02d:%02d" % [int(saved_time.get("year", 0)), int(saved_time.get("month", 0)), int(saved_time.get("day", 0)), int(saved_time.get("hour", 0)), int(saved_time.get("minute", 0))]


## 解析回放视角文本；按录制端第一视角玩家 ID 匹配玩家显示名。
func _resolve_viewer_text(header: Dictionary) -> String:
	# 录制端第一视角玩家 ID；-1 表示录制端当时未绑定本地玩家。
	var viewer_player_id: int = int(header.get("viewer_player_id", -1))
	for player_variant: Variant in header.get("players", []) as Array:
		if int((player_variant as Dictionary).get("player_id", -1)) == viewer_player_id:
			return str((player_variant as Dictionary).get("display_name", "玩家"))
	return "旁观视角"


## 把毫秒时长格式化为“分:秒”；与牌桌左上角对局时长格式一致。
func _format_duration_text(duration_msec: int) -> String:
	# 总秒数；不足1秒的尾数舍去。
	var total_seconds: int = duration_msec / 1000
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


## 列表条目点击；更新选中条目并刷新详情与选中描边。
func _on_entry_button_pressed(entry_button: Button) -> void:
	_selected_entry = entry_button.get_meta("replay_entry", {}) as Dictionary
	_operation_status_label.text = ""
	_refresh_detail_section()
	refresh_ui_style()


## “播放”按钮；发出播放意图，由主菜单转交牌桌进入第一视角整局重演。
func _on_play_button_pressed() -> void:
	if _selected_entry.is_empty():
		return
	playback_requested.emit(str(_selected_entry.get("file_name", "")))


## “重命名”按钮；打开名称输入模态并预填当前回放基础名。
func _on_rename_button_pressed() -> void:
	if _selected_entry.is_empty():
		return
	_open_path_modal("rename")


## “顶置”按钮；切换所选回放的顶置状态并刷新列表排序。
func _on_pin_button_pressed() -> void:
	if _selected_entry.is_empty():
		return
	# 待切换文件名与目标顶置状态；顶置写入失败通常因回放目录不可写。
	var file_name: String = str(_selected_entry.get("file_name", ""))
	var next_pinned: bool = not bool(_selected_entry.get("pinned", false))
	if MatchReplayStore.set_replay_pinned(file_name, next_pinned, _get_replay_directory()):
		_operation_status_label.text = "已顶置回放 %s。" % file_name if next_pinned else "已取消顶置 %s。" % file_name
	else:
		_operation_status_label.text = "顶置状态写入失败：%s。" % file_name
	refresh_replay_list()


## “导入回放”按钮；打开路径模态等待玩家填写源文件完整路径。
func _on_import_button_pressed() -> void:
	_open_path_modal("import")


## “导出回放”按钮；打开路径模态并预填桌面目录下的同名建议路径。
func _on_export_button_pressed() -> void:
	if _selected_entry.is_empty():
		return
	_open_path_modal("export")


## “删除回放”按钮；直接删除所选文件并刷新列表，文件级操作不再二次确认。
func _on_delete_button_pressed() -> void:
	if _selected_entry.is_empty():
		return
	# 待删除文件名；删除后清空选中状态。
	var file_name: String = str(_selected_entry.get("file_name", ""))
	if MatchReplayStore.delete_replay(file_name, _get_replay_directory()):
		_operation_status_label.text = "已删除回放 %s。" % file_name
		_selected_entry = {}
	else:
		_operation_status_label.text = "删除回放失败：%s。" % file_name
	refresh_replay_list()


## 打开输入模态；按用途设置标题、提示与默认内容。
func _open_path_modal(modal_mode: String) -> void:
	_modal_mode = modal_mode
	if modal_mode == "import":
		_modal_title_label.text = "导入回放"
		_modal_hint_label.text = "输入要导入的 .%s 回放文件完整路径；导入不会覆盖已有回放。" % MatchReplayStore.REPLAY_FILE_EXTENSION
		_modal_path_input.max_length = 0
		_modal_path_input.text = ""
		_modal_path_input.placeholder_text = "例如 C:/Users/你/Desktop/replay_20260727.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION
	elif modal_mode == "rename":
		_modal_title_label.text = "重命名回放"
		_modal_hint_label.text = "输入新的回放名称（不含后缀）；与已有回放重名时自动追加序号，不覆盖既有回放。"
		_modal_path_input.max_length = REPLAY_NAME_MAX_LENGTH
		_modal_path_input.text = str(_selected_entry.get("file_name", "")).get_basename()
		_modal_path_input.placeholder_text = "新回放名称"
	else:
		_modal_title_label.text = "导出回放"
		_modal_hint_label.text = "输入导出目标完整路径；缺少 .%s 后缀时会自动补齐。" % MatchReplayStore.REPLAY_FILE_EXTENSION
		_modal_path_input.max_length = 0
		# 导出建议路径；默认桌面目录加所选回放同名文件，玩家可自由修改。
		var desktop_directory: String = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		_modal_path_input.text = "%s/%s" % [desktop_directory, str(_selected_entry.get("file_name", ""))] if not desktop_directory.is_empty() else str(_selected_entry.get("file_name", ""))
	_modal_backdrop.visible = true
	_modal_panel.visible = true
	_modal_path_input.grab_focus()


## 关闭输入模态；不执行任何文件操作。
func _close_path_modal() -> void:
	_modal_mode = ""
	if _modal_backdrop != null:
		_modal_backdrop.visible = false
	if _modal_panel != null:
		_modal_panel.visible = false


## 模态确认；按当前用途执行导入、导出或重命名并显示结果。
func _on_modal_confirm_pressed() -> void:
	# 玩家填写的路径或名称；空内容直接忽略确认。
	var input_text: String = _modal_path_input.text.strip_edges()
	if input_text.is_empty():
		return
	if _modal_mode == "import":
		# 导入结果文件名；空字符串表示源文件缺失或不是合法回放。
		var imported_name: String = MatchReplayStore.import_replay(input_text, _get_replay_directory())
		_operation_status_label.text = "已导入回放 %s。" % imported_name if not imported_name.is_empty() else "导入失败：路径不存在或不是合法的回放文件。"
		refresh_replay_list()
	elif _modal_mode == "rename":
		# 重命名结果文件名；空字符串表示名称非法或文件系统拒绝重命名。
		var renamed_file_name: String = MatchReplayStore.rename_replay(str(_selected_entry.get("file_name", "")), input_text, _get_replay_directory())
		if renamed_file_name.is_empty():
			_operation_status_label.text = "重命名失败：名称非法或文件不可写。"
		else:
			_operation_status_label.text = "已重命名为 %s。" % renamed_file_name
			# 选中条目跟随新文件名；刷新列表时按新名恢复选中态与详情。
			_selected_entry["file_name"] = renamed_file_name
		refresh_replay_list()
	elif _modal_mode == "export":
		# 导出是否成功；失败通常因目标目录不存在或不可写。
		var export_succeeded: bool = MatchReplayStore.export_replay(str(_selected_entry.get("file_name", "")), input_text, _get_replay_directory())
		_operation_status_label.text = "已导出回放到 %s。" % input_text if export_succeeded else "导出失败：目标路径不可写或源回放缺失。"
	_close_path_modal()


## 主控件聚焦；打开内容页后把键盘焦点交给导入按钮，Android 下避免自动弹出输入法。
func _focus_primary_control() -> void:
	if _import_button != null and visible:
		_import_button.grab_focus()


## 主题变化回调；重绘全部静态文本与按钮样式。
func _on_ui_style_changed(_style_id: String) -> void:
	refresh_ui_style()
