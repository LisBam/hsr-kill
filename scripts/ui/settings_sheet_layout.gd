extends Node

## 设置页的纯布局组件：把已有表单节点分为规则与个人偏好两栏，不复制控件、不接管任何设置信号。
## 两栏各自滚动，底部返回按钮固定可达；新增规则行只需登记到rule_rows，其余行自动归入偏好栏。

## 弹窗期望尺寸；默认1000×560逻辑像素，运行时按可用视口收紧，修改不影响设置值。
@export var sheet_size: Vector2 = Vector2(1000.0, 560.0)
## 弹窗距视口的安全距离；默认32像素，运行时随窗口尺寸重算。
@export_range(16.0, 64.0, 1.0) var safe_margin: float = 32.0
## 两栏间距；默认28像素区分规则与个人偏好，运行时无需修改。
@export_range(12, 48, 1) var column_gap: int = 28
## 表单行间距；默认10像素，保证复选框和滑条有清晰的点击留白。
@export_range(4, 20, 1) var row_gap: int = 10
## 表单右侧滚动条安全留白；默认20像素，覆盖12像素拖条并留出8像素间隔，运行时无需修改。
@export_range(12, 32, 1) var scroll_clearance: int = 20
## 规则栏目节点名；由场景唯一名称登记，不读取任何玩法状态。
@export var rule_rows: Array[String] = ["MainMenuPlayerCountRow", "MainMenuCustomCharacterAssignmentCheckBox", "MainMenuCustomizeAiCharactersCheckBox", "MainMenuSeatCompensationCheckBox", "MainMenuMulliganLimitRow", "MainMenuAiUsesMulliganCheckBox", "MainMenuCharacterReplacementCountRow", "MainMenuCharacterCandidateCountRow", "MainMenuConquestDifficultyRow", "MainMenuConquestOpportunityChoiceRow", "WheelDuelFaceUpCandidateRow", "WheelDuelFaceDownCandidateRow"]
## 宿主面板；安装后绑定直接父节点，卸载组件不会更改玩家偏好。
var _panel: PanelContainer
## 栏目标题引用；只用于切换主题时更新文字颜色，默认空数组。
var _headings: Array[Label] = []


## 原有表单完成onready绑定之后重排；reparent保留原控件实例、唯一名称、焦点与信号。
func _ready() -> void:
	_panel = get_parent() as PanelContainer
	# 原表单主容器；名称固定用于兼容场景中的标题和关闭按钮。
	var content: VBoxContainer = _panel.get_node("SettingsVBox") as VBoxContainer
	# 原表单行快照；重新挂载时不会边遍历边修改同一数组。
	var rows: Array[Node] = content.get_children()
	# 双栏区域；只此区域占用剩余高度，标题与返回按钮始终固定。
	var columns: HBoxContainer = HBoxContainer.new()
	columns.name = "SettingsColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", column_gap)
	content.add_child(columns)
	content.move_child(columns, 3)
	# 规则表单承载区；初始为空，按登记顺序收纳原有规则行。
	var rules: VBoxContainer = _create_column(columns, "对局规则")
	# 个人偏好承载区；保留原有显示、声音和节奏设置的顺序。
	var preferences: VBoxContainer = _create_column(columns, "显示与声音")
	for row_name: String in rule_rows:
		# 原规则行；部分模式没有对应节点时跳过，不制造虚假的选项。
		var row: Node = content.get_node_or_null(NodePath(row_name))
		if row != null:
			row.reparent(rules, false)
	for row: Node in rows:
		if row.name in [&"MainMenuSettingsTitle", &"MainMenuSettingsHint", &"MainMenuSettingsDivider", &"MainMenuSettingsCloseButton"] or str(row.name) in rule_rows:
			continue
		row.reparent(preferences, false)
	# 返回按钮保持在表单之后；两栏滚到底也不会推走它。
	var close_button: Button = content.get_node("MainMenuSettingsCloseButton") as Button
	content.move_child(close_button, content.get_child_count() - 1)
	close_button.custom_minimum_size = Vector2(160.0, 44.0)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	content.add_theme_constant_override("separation", 12)
	get_viewport().size_changed.connect(_resize_sheet)
	GameSettings.ui_style_changed.connect(_on_style_changed)
	_resize_sheet()
	_refresh_style()


## 构造标题和独立滚动区域；两列使用等宽分配，长文本仅影响自身列的滚动高度。
func _create_column(columns: HBoxContainer, caption: String) -> VBoxContainer:
	# 整列布局；最小宽度保持为0，由父容器均分可用空间。
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	columns.add_child(column)
	# 栏目标题；明确区分下一局规则与即时个人偏好。
	var heading: Label = Label.new()
	heading.text = caption
	heading.add_theme_font_size_override("font_size", 22)
	column.add_child(heading)
	_headings.append(heading)
	# 原生滚动容器；不伪造滚动条，支持触摸拖动与键盘聚焦自动显露。
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	BattleUIStyle.apply_main_menu_scroll_bar_style(scroll.get_v_scroll_bar())
	# 安全内边距；禁止水平滚动时也保证下拉箭头与滑条末端不会被垂直拖条盖住。
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", scroll_clearance)
	scroll.add_child(margin)
	# 表单行容器；保留原有控件类型、数值范围及信号连接。
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", row_gap)
	margin.add_child(body)
	return body


## 视口变化后居中弹窗；高度由可用区域限制，长表单继续在内部滚动。
func _resize_sheet() -> void:
	# 允许的外壳尺寸；沿用项目1280×720逻辑视口，在宽屏上保留舒适的外部留白。
	var available: Vector2 = get_viewport().get_visible_rect().size - Vector2.ONE * safe_margin * 2.0
	# 实际面板尺寸；受目标尺寸和窗口安全区共同限制。
	var resolved: Vector2 = sheet_size.min(available)
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -resolved.x * 0.5
	_panel.offset_right = resolved.x * 0.5
	_panel.offset_top = -resolved.y * 0.5
	_panel.offset_bottom = resolved.y * 0.5


## 等活动主题刷新后再同步栏目文字。
func _on_style_changed(_style_id: String) -> void:
	call_deferred("_refresh_style")


## 栏目标题采用深金文字语义；不把用于按钮填充的浅金色直接用作纸面小字。
func _refresh_style() -> void:
	for heading: Label in _headings:
		heading.add_theme_color_override("font_color", BattleUIStyle.get_color("text_guide"))
