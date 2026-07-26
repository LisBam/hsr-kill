class_name MatchReplayPanel
extends Control

## 主菜单“对局回放”内容页组件。左侧列出本地已保存的 .lisbam_replay 回放并提供导入入口，
## 右侧展示所选回放的资料与播放、导出、删除操作；进入播放后整页切换为回放播放器：
## 上方以正式 PlayerTargetView 逐步重现各座位公开状态，下方提供时间轴、步进、自动播放与日志正文。
## 组件只读取回放文件与静态武将定义，不创建 GameState、对局运行时、网络会话或任何规则状态。

## 玩家请求关闭本内容页时发出；主菜单据此恢复模式选择页与顶部导航焦点。
signal close_requested

## 正式武将牌场景；播放器为每名玩家实例化只读牌面，复用对局同款公开状态渲染。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 播放器座位缩放比例；0.62倍使10人局能以每行5座两行完整放入内容页上半区。
@export var playback_seat_scale: float = 0.62

## 播放器每行座位数；固定5与联机形象候选布局一致，2至10人均可两行内呈现。
@export var playback_seats_per_row: int = 5

## 自动播放时相邻步骤的最大等待毫秒数；录制间隔超过该值时按上限播放，跳过真实对局中的长思考停顿。
@export var playback_maximum_step_gap_msec: int = 2000

## 自动播放速度倍率选项；元数据保存倍率浮点值，默认1.0倍。
const PLAYBACK_SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0, 4.0]

## 回放目录覆盖路径；自动化测试写入独立目录避免污染玩家回放，空字符串表示使用正式目录。
var replay_directory_override: String = ""

## 浏览模式根容器；列表与详情两栏，进入播放时整体隐藏。
var _browser_content: HBoxContainer = null

## 播放模式根容器；座位、时间轴与日志，默认隐藏。
var _playback_content: VBoxContainer = null

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

## 播放按钮；载入所选回放并切换到播放模式。
var _play_button: Button = null

## 导出按钮；打开路径输入模态，把所选回放复制到玩家指定位置。
var _export_button: Button = null

## 删除按钮；删除所选回放文件并刷新列表。
var _delete_button: Button = null

## 操作结果标签；显示导入、导出、删除与载入的成功或失败说明。
var _operation_status_label: Label = null

## 当前选中的回放条目；含 file_name、header 与 file_size，未选中时为空字典。
var _selected_entry: Dictionary = {}

## 当前列表条目按钮；按文件名索引，用于选中态样式切换。
var _entry_buttons: Dictionary = {}

## 播放器顶部信息标签；显示当前轮次、阶段与步骤进度。
var _playback_info_label: Label = null

## 返回列表按钮；退出播放模式并回到浏览列表。
var _back_button: Button = null

## 播放器座位网格；按玩家数生成固定槽位，逐快照刷新公开状态。
var _seats_grid: GridContainer = null

## 播放器按玩家 ID 索引的武将牌组件；整个播放期间复用，不逐步重建。
var _playback_seat_views: Dictionary = {}

## 上一步按钮；回退到上一份快照步骤。
var _step_back_button: Button = null

## 播放/暂停按钮；切换自动播放状态。
var _play_pause_button: Button = null

## 下一步按钮；前进到下一份快照步骤。
var _step_forward_button: Button = null

## 播放速度下拉框；选项元数据保存倍率浮点值。
var _speed_option: OptionButton = null

## 时间轴滑条；值为步骤索引，拖动可任意定位。
var _timeline_slider: HSlider = null

## 播放器日志正文；显示当前步骤之前的全部对局日志。
var _playback_log_view: RichTextLabel = null

## 当前载入回放的全部步骤；播放期间常驻内存以支持时间轴任意拖动。
var _steps: Array[Dictionary] = []

## 当前载入回放的回放头；提供玩家资料与总步骤数。
var _playback_header: Dictionary = {}

## 当前已应用的步骤索引；-1 表示尚未应用任何步骤。
var _step_index: int = -1

## 是否处于自动播放中；由播放/暂停按钮切换，播放到末尾自动停止。
var _playing: bool = false

## 自动播放累计毫秒；乘以速度倍率后与下一步的录制间隔比较。
var _playback_accumulated_msec: float = 0.0

## 时间轴是否正在由代码回写；抑制 value_changed 回调造成的重复定位。
var _updating_timeline: bool = false

## 路径输入模态遮罩；打开期间阻断底层输入。
var _modal_backdrop: ColorRect = null

## 路径输入模态面板；导入与导出共用，按当前模态用途区分行为。
var _modal_panel: PanelContainer = null

## 路径输入模态标题标签；显示“导入回放”或“导出回放”。
var _modal_title_label: Label = null

## 路径输入模态提示标签；说明期望的路径形式与文件后缀。
var _modal_hint_label: Label = null

## 路径输入框；导入时填写源文件完整路径，导出时填写目标完整路径。
var _modal_path_input: LineEdit = null

## 路径模态确认按钮；执行导入或导出。
var _modal_confirm_button: Button = null

## 路径模态取消按钮；关闭模态不执行操作。
var _modal_cancel_button: Button = null

## 当前路径模态用途；"import" 或 "export"，空字符串表示模态未打开。
var _modal_mode: String = ""


## 初始化内容页；构建浏览与播放两套界面并默认显示浏览列表。
func _ready() -> void:
	visible = false
	_build_interface()
	refresh_ui_style()
	set_process(false)
	if GameSettings != null:
		GameSettings.ui_style_changed.connect(_on_ui_style_changed)


## 打开内容页；刷新回放列表并聚焦主控件，与其他主菜单内容页保持同一打开契约。
func open_panel() -> void:
	visible = true
	move_to_front()
	_exit_playback()
	refresh_replay_list()
	refresh_ui_style()
	call_deferred("_focus_primary_control")


## 关闭内容页前的收尾；停止播放并释放已载入的步骤内存。
func close_panel() -> void:
	_exit_playback()
	visible = false


## 刷新已保存回放列表；重建左侧条目按钮并保持右侧详情与选中态一致。
func refresh_replay_list() -> void:
	for child: Node in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	# 当前目录内全部可解析回放；按保存时间倒序排列。
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


## 刷新活动 UI 风格；两套界面的全部静态文本、按钮与面板统一读取当前主题语义色。
func refresh_ui_style() -> void:
	if _frame == null:
		return
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), 2, 10))
	_side_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_list_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_detail_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_detail_body_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_operation_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_playback_info_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_playback_log_view.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	_modal_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_modal_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_modal_path_input.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_modal_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("accent"), 2, 10))
	BattleUIStyle.apply_interaction_button(_import_button)
	BattleUIStyle.apply_interaction_button(_play_button)
	BattleUIStyle.apply_interaction_button(_export_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_delete_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("danger"), false)
	BattleUIStyle.apply_interaction_button(_back_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_step_back_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_play_pause_button)
	BattleUIStyle.apply_interaction_button(_step_forward_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
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
	for seat_view_variant: Variant in _playback_seat_views.values():
		# 当前播放器座位牌面；主题切换时重绘正式武将牌样式。
		var seat_view: PlayerTargetView = seat_view_variant as PlayerTargetView
		if seat_view != null and is_instance_valid(seat_view):
			seat_view.refresh_ui_style()


## 自动播放帧驱动；按录制时间差与速度倍率逐步推进，播放至末尾自动暂停。
func _process(delta: float) -> void:
	if not _playing or _steps.is_empty():
		return
	_playback_accumulated_msec += delta * 1000.0 * _get_playback_speed()
	while _playing and _step_index < _steps.size() - 1:
		# 下一步与当前步的录制间隔毫秒；超过上限时按上限等待，跳过长时间思考停顿。
		var step_gap_msec: int = _get_step_gap_msec(_step_index + 1)
		if _playback_accumulated_msec < float(step_gap_msec):
			break
		_playback_accumulated_msec -= float(step_gap_msec)
		_apply_step(_step_index + 1)
	if _step_index >= _steps.size() - 1:
		_set_playing(false)


## Esc 关闭链；优先关闭路径模态，其次退出播放模式，最后交还整页关闭意图。
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if not _modal_mode.is_empty():
		_close_path_modal()
		accept_event()
		return
	if _playback_content.visible:
		_exit_playback()
		accept_event()
		return
	accept_event()
	close_requested.emit()


## 构建整页界面；仅在 _ready 调用一次，浏览、播放与路径模态三部分都在此创建。
func _build_interface() -> void:
	_frame = PanelContainer.new()
	_frame.name = "MatchReplayFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_build_browser_content()
	_build_playback_content()
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
	# 操作按钮行；播放为主操作，导出与删除为次级操作。
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
	_export_button = Button.new()
	_export_button.name = "ReplayExportButton"
	_export_button.text = "导出回放"
	_export_button.custom_minimum_size = Vector2(120.0, 42.0)
	_export_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_export_button.pressed.connect(_on_export_button_pressed)
	action_row.add_child(_export_button)
	_delete_button = Button.new()
	_delete_button.name = "ReplayDeleteButton"
	_delete_button.text = "删除回放"
	_delete_button.custom_minimum_size = Vector2(120.0, 42.0)
	_delete_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_delete_button.pressed.connect(_on_delete_button_pressed)
	action_row.add_child(_delete_button)
	_operation_status_label = Label.new()
	_operation_status_label.name = "ReplayOperationStatus"
	_operation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_operation_status_label.add_theme_font_size_override("font_size", 13)
	detail_vbox.add_child(_operation_status_label)


## 构建播放模式界面；顶部信息行、座位网格、控制行与日志正文。
func _build_playback_content() -> void:
	_playback_content = VBoxContainer.new()
	_playback_content.name = "ReplayPlaybackContent"
	_playback_content.visible = false
	_playback_content.add_theme_constant_override("separation", 8)
	_frame.add_child(_playback_content)
	# 顶部信息行；左侧轮次阶段与步骤进度，右侧返回列表。
	var info_row: HBoxContainer = HBoxContainer.new()
	_playback_content.add_child(info_row)
	_playback_info_label = Label.new()
	_playback_info_label.name = "ReplayPlaybackInfo"
	_playback_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playback_info_label.add_theme_font_size_override("font_size", 16)
	info_row.add_child(_playback_info_label)
	_back_button = Button.new()
	_back_button.name = "ReplayBackButton"
	_back_button.text = "返回列表"
	_back_button.custom_minimum_size = Vector2(108.0, 36.0)
	_back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_back_button.pressed.connect(_exit_playback)
	info_row.add_child(_back_button)
	# 座位区滚动容器；异常多座位时纵向滚动而不是溢出整页。
	var seats_scroll: ScrollContainer = ScrollContainer.new()
	seats_scroll.custom_minimum_size = Vector2(0.0, 292.0)
	seats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_playback_content.add_child(seats_scroll)
	# 座位居中包装；网格按内容宽度水平居中。
	var seats_center: CenterContainer = CenterContainer.new()
	seats_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seats_scroll.add_child(seats_center)
	_seats_grid = GridContainer.new()
	_seats_grid.name = "ReplaySeatsGrid"
	_seats_grid.columns = playback_seats_per_row
	_seats_grid.add_theme_constant_override("h_separation", 14)
	_seats_grid.add_theme_constant_override("v_separation", 10)
	seats_center.add_child(_seats_grid)
	# 播放控制行；步进、播放暂停、速度与时间轴。
	var control_row: HBoxContainer = HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 10)
	_playback_content.add_child(control_row)
	_step_back_button = Button.new()
	_step_back_button.name = "ReplayStepBackButton"
	_step_back_button.text = "上一步"
	_step_back_button.custom_minimum_size = Vector2(84.0, 36.0)
	_step_back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_step_back_button.pressed.connect(_on_step_back_pressed)
	control_row.add_child(_step_back_button)
	_play_pause_button = Button.new()
	_play_pause_button.name = "ReplayPlayPauseButton"
	_play_pause_button.text = "播放"
	_play_pause_button.custom_minimum_size = Vector2(84.0, 36.0)
	_play_pause_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_play_pause_button.pressed.connect(_on_play_pause_pressed)
	control_row.add_child(_play_pause_button)
	_step_forward_button = Button.new()
	_step_forward_button.name = "ReplayStepForwardButton"
	_step_forward_button.text = "下一步"
	_step_forward_button.custom_minimum_size = Vector2(84.0, 36.0)
	_step_forward_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_step_forward_button.pressed.connect(_on_step_forward_pressed)
	control_row.add_child(_step_forward_button)
	_speed_option = OptionButton.new()
	_speed_option.name = "ReplaySpeedOption"
	_speed_option.custom_minimum_size = Vector2(96.0, 36.0)
	for speed_value: float in PLAYBACK_SPEED_OPTIONS:
		_speed_option.add_item("%.1f×" % speed_value)
		_speed_option.set_item_metadata(_speed_option.item_count - 1, speed_value)
	_speed_option.select(1)
	control_row.add_child(_speed_option)
	_timeline_slider = HSlider.new()
	_timeline_slider.name = "ReplayTimelineSlider"
	_timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timeline_slider.min_value = 0.0
	_timeline_slider.step = 1.0
	_timeline_slider.value_changed.connect(_on_timeline_value_changed)
	control_row.add_child(_timeline_slider)
	_playback_log_view = RichTextLabel.new()
	_playback_log_view.name = "ReplayPlaybackLog"
	_playback_log_view.bbcode_enabled = false
	_playback_log_view.scroll_active = true
	_playback_log_view.scroll_following = true
	_playback_log_view.selection_enabled = true
	_playback_log_view.focus_mode = Control.FOCUS_NONE
	_playback_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_playback_content.add_child(_playback_log_view)


## 构建导入与导出共用的路径输入模态；遮罩阻断底层输入，Esc 与取消按钮关闭。
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
	# 模态纵向布局；标题、提示、路径输入与按钮行。
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


## 把回放条目格式化为列表按钮文本；显示保存时间、模式与人数。
func _format_entry_button_text(entry: Dictionary) -> String:
	# 回放头字典；列表条目在读取阶段已校验可解析。
	var header: Dictionary = entry.get("header", {}) as Dictionary
	# 保存时刻的本地时间字典；用于生成紧凑的“月-日 时:分”显示。
	var saved_time: Dictionary = Time.get_datetime_dict_from_unix_time(int(header.get("saved_at_unix", 0)) + Time.get_time_zone_from_system().get("bias", 0) * 60)
	return "%02d-%02d %02d:%02d · %s · %d人" % [int(saved_time.get("month", 0)), int(saved_time.get("day", 0)), int(saved_time.get("hour", 0)), int(saved_time.get("minute", 0)), _resolve_mode_display_name(str(header.get("match_mode", ""))), int(header.get("player_count", 0))]


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
	_export_button.disabled = not has_selection
	_delete_button.disabled = not has_selection
	if not has_selection:
		_detail_title_label.text = "选择一份回放"
		_detail_body_label.text = "从左侧列表选择回放后，可在此播放、导出到指定路径或删除。\n回放文件后缀为 .%s。" % MatchReplayStore.REPLAY_FILE_EXTENSION
		return
	# 已选条目的回放头；全部字段来自保存时的公开快照。
	var header: Dictionary = _selected_entry.get("header", {}) as Dictionary
	_detail_title_label.text = str(_selected_entry.get("file_name", ""))
	# 详情正文行集合；逐项列出资料后合并为多行文本。
	var lines: PackedStringArray = PackedStringArray()
	lines.append("模式：%s" % _resolve_mode_display_name(str(header.get("match_mode", ""))))
	lines.append("人数：%d" % int(header.get("player_count", 0)))
	lines.append("回放视角：%s" % _resolve_viewer_text(header))
	lines.append("对局状态：%s" % ("已结束" if bool(header.get("game_over", false)) else "未结束"))
	lines.append("时长：%s" % _format_duration_text(int(header.get("duration_msec", 0))))
	lines.append("步骤：%d（快照 %d / 日志 %d）" % [int(header.get("step_count", 0)), int(header.get("snapshot_count", 0)), int(header.get("log_count", 0))])
	lines.append("文件大小：%.1f KB" % (float(int(_selected_entry.get("file_size", 0))) / 1024.0))
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


## “播放”按钮；载入所选回放全部步骤并切换到播放模式。
func _on_play_button_pressed() -> void:
	if _selected_entry.is_empty():
		return
	# 所选回放完整路径；载入失败时保持浏览模式并提示原因。
	var replay_path: String = "%s/%s" % [_get_replay_directory(), str(_selected_entry.get("file_name", ""))]
	_playback_header = MatchReplayStore.read_replay_header(replay_path)
	_steps = MatchReplayStore.read_replay_steps(replay_path)
	if _playback_header.is_empty() or _steps.is_empty():
		_operation_status_label.text = "回放载入失败：文件缺失或已损坏。"
		return
	_browser_content.visible = false
	_playback_content.visible = true
	_build_playback_seats()
	_playback_log_view.text = ""
	_step_index = -1
	_playback_accumulated_msec = 0.0
	_timeline_slider.max_value = float(_steps.size() - 1)
	_set_playing(false)
	# 打开播放器立即应用第一份快照，玩家看到开局座位而不是空白网格。
	_seek_to_step(_find_first_snapshot_index())
	set_process(true)


## 退出播放模式；停止自动播放、释放步骤内存并回到浏览列表。
func _exit_playback() -> void:
	_set_playing(false)
	set_process(false)
	_steps = []
	_playback_header = {}
	_step_index = -1
	for child: Node in _seats_grid.get_children():
		_seats_grid.remove_child(child)
		child.queue_free()
	_playback_seat_views.clear()
	if _playback_content != null:
		_playback_content.visible = false
	if _browser_content != null:
		_browser_content.visible = true


## 按回放头玩家表构建播放器座位；每名玩家一个固定槽位，播放期间整体复用。
func _build_playback_seats() -> void:
	for child: Node in _seats_grid.get_children():
		_seats_grid.remove_child(child)
		child.queue_free()
	_playback_seat_views.clear()
	for player_variant: Variant in _playback_header.get("players", []) as Array:
		# 当前玩家回放头条目；仅提供玩家 ID 建立槽位，实际状态由快照步骤刷新。
		var player: Dictionary = player_variant as Dictionary
		# 座位槽容器；为缩放后的武将牌保留固定布局尺寸。
		var seat_slot: Control = Control.new()
		seat_slot.custom_minimum_size = Vector2(148.35, 197.8) * playback_seat_scale
		seat_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_seats_grid.add_child(seat_slot)
		# 正式武将牌实例；关闭输入与滚动手势，只作只读回放渲染。
		var seat_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
		seat_slot.add_child(seat_view)
		seat_view.scale = Vector2.ONE * playback_seat_scale
		seat_view.set_interactable(false)
		seat_view.set_scroll_gesture_enabled(false)
		_playback_seat_views[int(player.get("player_id", -1))] = seat_view


## 返回步骤流中第一份快照的索引；找不到快照时返回0保证界面仍能推进。
func _find_first_snapshot_index() -> int:
	for step_index: int in range(_steps.size()):
		if str(_steps[step_index].get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
			return step_index
	return 0


## 返回指定步骤与其前一步的录制间隔毫秒；用于自动播放节奏，间隔按上限截断。
func _get_step_gap_msec(step_index: int) -> int:
	if step_index <= 0 or step_index >= _steps.size():
		return 0
	return clampi(int(_steps[step_index].get("t", 0)) - int(_steps[step_index - 1].get("t", 0)), 0, playback_maximum_step_gap_msec)


## 顺序应用下一个步骤；快照刷新座位与信息行，日志追加到正文。
func _apply_step(step_index: int) -> void:
	if step_index < 0 or step_index >= _steps.size():
		return
	_step_index = step_index
	# 当前步骤字典；k 为步骤类型，d 为快照或日志数据。
	var step: Dictionary = _steps[step_index]
	if str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
		_render_playback_snapshot(step.get("d", {}) as Dictionary)
	elif str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_LOG:
		if _playback_log_view.text.is_empty():
			_playback_log_view.text = str(step.get("d", ""))
		else:
			_playback_log_view.text += "\n" + str(step.get("d", ""))
	_refresh_playback_info()
	_sync_timeline_slider()


## 任意定位到指定步骤；应用不迟于该步骤的最新快照，并整体重建日志前缀。
func _seek_to_step(step_index: int) -> void:
	if _steps.is_empty():
		return
	_step_index = clampi(step_index, 0, _steps.size() - 1)
	_playback_accumulated_msec = 0.0
	# 不迟于目标步骤的最新快照；回放状态始终以快照为准，日志只是文字流水。
	var snapshot_to_apply: Dictionary = {}
	# 目标步骤之前（含）的全部日志行；重建正文避免拖动后日志与状态错位。
	var log_lines: PackedStringArray = PackedStringArray()
	for scan_index: int in range(_step_index + 1):
		# 当前扫描步骤；快照保留最新一份，日志按顺序累积。
		var step: Dictionary = _steps[scan_index]
		if str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
			snapshot_to_apply = step.get("d", {}) as Dictionary
		elif str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_LOG:
			log_lines.append(str(step.get("d", "")))
	if not snapshot_to_apply.is_empty():
		_render_playback_snapshot(snapshot_to_apply)
	_playback_log_view.text = "\n".join(log_lines)
	_refresh_playback_info()
	_sync_timeline_slider()


## 用一份回放快照刷新全部座位与顶部信息；渲染契约与正式牌桌的公开快照完全一致。
func _render_playback_snapshot(snapshot: Dictionary) -> void:
	# 当前行动玩家 ID；用于武将牌金边高亮，与正式对局一致。
	var current_player_id: int = int(snapshot.get("current_player_id", -1))
	for player_variant: Variant in snapshot.get("players", []) as Array:
		# 当前玩家公开快照；找不到对应座位（异常快照）时跳过。
		var player: Dictionary = player_variant as Dictionary
		# 该玩家的座位牌面组件；由回放头玩家表建立。
		var seat_view: PlayerTargetView = _playback_seat_views.get(int(player.get("player_id", -1))) as PlayerTargetView
		if seat_view == null or not is_instance_valid(seat_view):
			continue
		# 该玩家武将静态定义；未公开武将时为空字典，由牌面自行渲染牌背。
		var character_definition: Dictionary = GameDatabase.get_character(str(player.get("character_id", ""))) if not str(player.get("character_id", "")).is_empty() else {}
		# 该武将势力静态定义；武将缺失时为空字典。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", ""))) if not character_definition.is_empty() else {}
		seat_view.configure_snapshot(player, character_definition, int(player.get("player_id", -1)) == current_player_id, faction_definition)


## 刷新播放器顶部信息行；显示轮次、阶段、当前步骤与总步骤。
func _refresh_playback_info() -> void:
	# 最近一次渲染的快照轮次与阶段；从已应用步骤反查，避免另存一份快照副本。
	var latest_snapshot: Dictionary = {}
	for scan_index: int in range(_step_index, -1, -1):
		if str(_steps[scan_index].get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
			latest_snapshot = _steps[scan_index].get("d", {}) as Dictionary
			break
	_playback_info_label.text = "第%d轮 · %s · 步骤 %d / %d" % [int(latest_snapshot.get("round_number", 0)), str(latest_snapshot.get("current_phase", "")), _step_index + 1, _steps.size()]


## 把时间轴滑条回写为当前步骤索引；标记回写状态避免触发重复定位。
func _sync_timeline_slider() -> void:
	_updating_timeline = true
	_timeline_slider.value = float(_step_index)
	_updating_timeline = false


## 时间轴拖动响应；玩家拖动时定位到目标步骤，代码回写时忽略。
func _on_timeline_value_changed(value: float) -> void:
	if _updating_timeline or _steps.is_empty():
		return
	_set_playing(false)
	_seek_to_step(int(value))


## 上一步按钮；定位到前一份快照步骤，日志与状态同步回退。
func _on_step_back_pressed() -> void:
	_set_playing(false)
	for scan_index: int in range(_step_index - 1, -1, -1):
		if str(_steps[scan_index].get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
			_seek_to_step(scan_index)
			return
	_seek_to_step(0)


## 下一步按钮；前进到下一份快照步骤，途中的日志一并应用。
func _on_step_forward_pressed() -> void:
	_set_playing(false)
	for scan_index: int in range(_step_index + 1, _steps.size()):
		if str(_steps[scan_index].get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
			_seek_to_step(scan_index)
			return
	_seek_to_step(_steps.size() - 1)


## 播放/暂停按钮；到达末尾后再次点击从头开始播放。
func _on_play_pause_pressed() -> void:
	if _playing:
		_set_playing(false)
		return
	if _step_index >= _steps.size() - 1:
		_seek_to_step(_find_first_snapshot_index())
	_set_playing(true)


## 设置自动播放状态并同步按钮文字。
func _set_playing(playing: bool) -> void:
	_playing = playing
	_playback_accumulated_msec = 0.0
	if _play_pause_button != null:
		_play_pause_button.text = "暂停" if _playing else "播放"


## 返回当前速度倍率；下拉框元数据缺失时回退1.0倍。
func _get_playback_speed() -> float:
	# 当前选中项元数据；构建时写入倍率浮点值。
	var speed_metadata: Variant = _speed_option.get_selected_metadata()
	return float(speed_metadata) if speed_metadata != null else 1.0


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


## 打开路径输入模态；按用途设置标题、提示与默认路径。
func _open_path_modal(modal_mode: String) -> void:
	_modal_mode = modal_mode
	if modal_mode == "import":
		_modal_title_label.text = "导入回放"
		_modal_hint_label.text = "输入要导入的 .%s 回放文件完整路径；导入不会覆盖已有回放。" % MatchReplayStore.REPLAY_FILE_EXTENSION
		_modal_path_input.text = ""
		_modal_path_input.placeholder_text = "例如 C:/Users/你/Desktop/replay_20260727.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION
	else:
		_modal_title_label.text = "导出回放"
		_modal_hint_label.text = "输入导出目标完整路径；缺少 .%s 后缀时会自动补齐。" % MatchReplayStore.REPLAY_FILE_EXTENSION
		# 导出建议路径；默认桌面目录加所选回放同名文件，玩家可自由修改。
		var desktop_directory: String = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		_modal_path_input.text = "%s/%s" % [desktop_directory, str(_selected_entry.get("file_name", ""))] if not desktop_directory.is_empty() else str(_selected_entry.get("file_name", ""))
	_modal_backdrop.visible = true
	_modal_panel.visible = true
	_modal_path_input.grab_focus()


## 关闭路径输入模态；不执行任何文件操作。
func _close_path_modal() -> void:
	_modal_mode = ""
	_modal_backdrop.visible = false
	_modal_panel.visible = false


## 路径模态确认；按当前用途执行导入或导出并显示结果。
func _on_modal_confirm_pressed() -> void:
	# 玩家填写的路径；空路径直接忽略确认。
	var input_path: String = _modal_path_input.text.strip_edges()
	if input_path.is_empty():
		return
	if _modal_mode == "import":
		# 导入结果文件名；空字符串表示源文件缺失或不是合法回放。
		var imported_name: String = MatchReplayStore.import_replay(input_path, _get_replay_directory())
		_operation_status_label.text = "已导入回放 %s。" % imported_name if not imported_name.is_empty() else "导入失败：路径不存在或不是合法的回放文件。"
		refresh_replay_list()
	elif _modal_mode == "export":
		# 导出是否成功；失败通常因目标目录不存在或不可写。
		var export_succeeded: bool = MatchReplayStore.export_replay(str(_selected_entry.get("file_name", "")), input_path, _get_replay_directory())
		_operation_status_label.text = "已导出回放到 %s。" % input_path if export_succeeded else "导出失败：目标路径不可写或源回放缺失。"
	_close_path_modal()


## 主控件聚焦；打开内容页后把键盘焦点交给导入按钮，Android 下避免自动弹出输入法。
func _focus_primary_control() -> void:
	if _import_button != null and visible:
		_import_button.grab_focus()


## 主题变化回调；重绘全部静态文本与按钮样式。
func _on_ui_style_changed(_style_id: String) -> void:
	refresh_ui_style()
