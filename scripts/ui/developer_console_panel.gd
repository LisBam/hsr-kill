class_name DeveloperConsolePanel
extends Control

## 开发者菜单窗口（离线调试特权表面）。
##
## 职责边界：本组件只发意图信号并读取**静态定义**（`GameDatabase` / `GameSettings`），
## 不读取 `GameState` / `MatchController`，也不改写任何规则状态——与项目「UI 层不得触碰规则权威」的
## 单向依赖约定一致（`.trellis/spec/ui/index.md`）。目标列表与摸牌堆牌面由桌面从快照投影后注入。
##
## 使用方式：桌面创建本组件并连接四个意图信号；`open_console()` / `close_console()` 控制显隐；
## 每次对局快照刷新后调用 `set_target_candidates()`，效果执行结果经 `set_status_text()` 回填。

## 请求关闭开发者菜单；桌面负责隐藏、归还焦点并清理第二层视图。
signal close_requested

## 请求执行一条数值效果；协调器转交控制器统一排队。
## effect_kind 为稳定协议字符串，target_player_id 为当前选中目标，amount 为当前输入数值。
signal effect_requested(effect_kind: String, target_player_id: int, amount: int)

## 请求从摸牌堆获得指定实体牌；uids 为所选实体牌 UID 列表。
signal draw_pile_gain_requested(target_player_id: int, uids: Array[int])

## 请求更换指定目标的武将。
signal character_replace_requested(target_player_id: int, character_id: String)

## 请求桌面注入摸牌堆牌面候选；桌面经控制器只读端口取得后调用 set_draw_pile_candidates()。
## 面板不自行读取牌堆，因此必须由桌面在进入该视图时按需注入，而不是每次快照刷新都全量投影。
signal draw_pile_candidates_requested

## 窗口绘制层级；高于局内菜单 500、低于回放覆盖层 620，落在 docs/界面与交互.md 已定义的层级之间。
const CONSOLE_Z_INDEX: int = 520

## 数值效果滑条下限；与需求「滑条范围 1-10」一致。
const AMOUNT_SLIDER_MIN: int = 1

## 数值效果滑条上限；输入框不设上限，滑条只提供常用区间。
const AMOUNT_SLIDER_MAX: int = 10

## 数值效果滑条步长；整数步长避免出现小数张数或小数点数。
const AMOUNT_SLIDER_STEP: int = 1

## 数值输入框最小可接受值；任何更小的输入都会被钳制到该下限。
const AMOUNT_INPUT_MIN: int = 1

## 效果按钮固定宽度；保证左侧效果名成列对齐，右侧滑条与输入框形成稳定网格。
const EFFECT_BUTTON_WIDTH: float = 168.0

## 数值输入框固定宽度；足够显示四位数，同时不挤压滑条。
const AMOUNT_INPUT_WIDTH: float = 72.0

## 行内标签固定宽度；与效果按钮同宽，使目标行与效果行左边界对齐。
const ROW_LABEL_WIDTH: float = 168.0

## 摸牌堆候选网格列数；按按钮固定宽度换算，约等于窗口内容宽度的均分结果。
const DRAW_PILE_GRID_COLUMNS: int = 3

## 换将候选网格列数；武将名较短，可比牌面多一列。
const CHARACTER_GRID_COLUMNS: int = 4

## 摸牌堆候选按钮最小宽度；保证牌名加花色点数可完整显示。
const CARD_BUTTON_WIDTH: float = 240.0

## 换将候选按钮最小宽度；只需容纳武将名。
const CHARACTER_BUTTON_WIDTH: float = 150.0

## 第二层视图滚动区高度；保证主视图与第二层视图切换时窗口总高度稳定。
const SUB_VIEW_SCROLL_HEIGHT: float = 316.0

## 状态行默认文案；无执行结果时显示，明确提示效果会在「当前结算完毕后的空闲时间」执行。
const DEFAULT_STATUS_TEXT: String = "选择目标与数值后按下效果按钮；效果将在当前结算完毕后的空闲时间执行。"

## 花色稳定 ID 到显示符号的映射；仅用于开发者界面的牌面标注，未知花色原样回退。
const SUIT_SYMBOLS: Dictionary = {
	"spade":"♠",
	"heart":"♥",
	"club":"♣",
	"diamond":"♦",
	"none":"◇",
}

## 效果声明表：kind 为与 `DeveloperEffectService` 共享的稳定协议字符串，
## label 为按钮文字，uses_amount 决定是否渲染滑条与数值输入框。
## 新增效果只需追加一项声明，并在 `DeveloperEffectService._execute()` 内补一个 match 分支。
const EFFECT_DECLARATIONS: Array[Dictionary] = [
	{"kind":DeveloperEffectService.EFFECT_DRAW, "label":"摸牌", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_DISCARD, "label":"弃牌", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_RECOVER, "label":"回复体力", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_LOSE_HP, "label":"失去体力", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_DAMAGE, "label":"受到伤害", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_GAIN_MAX_HP, "label":"增加体力上限", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_LOSE_MAX_HP, "label":"减少体力上限", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_GAIN_SHIELD, "label":"获得护盾", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_LOSE_SHIELD, "label":"失去护盾", "uses_amount":true},
	{"kind":DeveloperEffectService.EFFECT_GAIN_DRAW_PILE_CARD, "label":"获得牌堆中的指定牌", "uses_amount":false},
	{"kind":DeveloperEffectService.EFFECT_REPLACE_CHARACTER, "label":"更换武将", "uses_amount":false},
]

## 内容区最大宽度；默认 900 像素，居中显示以避免超宽屏把设置行拉伸成难以阅读的长条。
## 运行时无需动态修改。
@export var panel_max_width: float = 900.0

## 内容区最大高度；默认 560 像素，必须小于最小支持客户区高度（648），
## 保证在 1152×648 客户区下窗口完整可见。运行时无需动态修改。
@export var panel_max_height: float = 560.0

## 当前第二层视图；第二层在同一个遮罩内替换内容，不叠加第二层全屏遮罩，避免层级与 Esc 优先级复杂化。
enum View { MAIN, DRAW_PILE, CHARACTER }

## 当前视图标识；关闭窗口时复位为 MAIN，保证下次打开总是回到主视图。
var _view: View = View.MAIN

## 目标候选；每项含 player_id / display_text / is_local，由桌面从对局快照投影后注入。
var _target_candidates: Array[Dictionary] = []

## 当前选中的目标座次；-1 表示尚无可用目标，此时所有效果按钮只提示而不发信号。
var _selected_target_id: int = -1

## 摸牌堆全量牌面候选；由桌面经控制器只读端口取得后注入，本组件不自行访问牌堆。
var _draw_pile_candidates: Array[Dictionary] = []

## 摸牌堆视图中已勾选的实体牌 UID 集合；以 UID 为键，使网格重建后仍能恢复勾选状态。
var _draw_pile_selected_uids: Dictionary = {}

## 换将视图中当前选中的武将 ID；空字符串表示尚未选择，此时确认按钮只提示。
var _selected_character_id: String = ""

## 效果行控件索引；kind -> {button, slider, input}，uses_amount 为 false 时 slider 与 input 均为 null。
var _effect_rows: Dictionary = {}

## 全屏遮罩；拦截鼠标，避免点击穿透到牌桌并误触出牌或目标选择。
var _shade: ColorRect

## 内容外框；承载滚动区，使用统一内嵌面板样式。
var _frame: PanelContainer

## 内容滚动容器；窗口内容超出高度时滚动，避免在紧凑客户区溢出屏幕。
var _scroll: ScrollContainer

## 内容列；三个视图共用的父节点。
var _content: VBoxContainer

## 主视图；标题、目标选择、效果行与状态行。
var _main_view: VBoxContainer

## 摸牌堆第二层视图。
var _draw_pile_view: VBoxContainer

## 换将第二层视图。
var _character_view: VBoxContainer

## 目标下拉框；选项元数据保存稳定 player_id，显示文字不参与规则解析。
var _target_option: OptionButton

## 状态行标签；显示最近一次效果的执行结果或未生效原因。
var _status_label: Label

## 排队计数标签；显示当前待执行效果数量，使「排队中」与「无响应」可区分。
var _pending_label: Label

## 摸牌堆候选网格。
var _draw_pile_grid: GridContainer

## 摸牌堆视图提示标签；显示已载入牌数与当前勾选数。
var _draw_pile_hint: Label

## 换将候选网格。
var _character_grid: GridContainer

## 换将视图筛选输入框；按武将名过滤，避免在近两百名武将中手动查找。
var _character_filter: LineEdit


## 构建界面并初始化为隐藏；窗口只在桌面显式调用 open_console() 后出现。
func _ready() -> void:
	z_index = CONSOLE_Z_INDEX
	# 始终处理输入：窗口打开后即使对局因其他原因被暂停，Esc 与返回也必须可用，避免把玩家困在模态窗口里。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	refresh_ui_style()


## 注入目标候选；保留当前选择，仅当原目标已不在新列表中时才回退到 preferred_player_id。
func set_target_candidates(candidates: Array[Dictionary], preferred_player_id: int) -> void:
	_target_candidates = candidates.duplicate(true)
	if _target_option == null:
		return
	# 期望选中的目标座次；先沿用当前选择，失效时才回退，避免每次快照刷新都把玩家选择重置。
	var desired_player_id: int = _selected_target_id
	# 新列表中的全部座次；用于判断当前选择是否仍然有效。
	var available_ids: Array[int] = []
	for candidate: Dictionary in _target_candidates:
		available_ids.append(int(candidate.get("player_id", -1)))
	if not available_ids.has(desired_player_id):
		desired_player_id = preferred_player_id
	_target_option.clear()
	# 期望目标在新列表中的下标；-1 表示该目标不可用。
	var selected_index: int = -1
	for index: int in range(_target_candidates.size()):
		# 当前候选项；player_id 写入选项元数据，显示文字只用于呈现。
		var candidate: Dictionary = _target_candidates[index]
		_target_option.add_item(str(candidate.get("display_text", "玩家")))
		_target_option.set_item_metadata(index, int(candidate.get("player_id", -1)))
		if int(candidate.get("player_id", -1)) == desired_player_id:
			selected_index = index
	if selected_index >= 0:
		_target_option.select(selected_index)
		_selected_target_id = desired_player_id
	elif _target_option.item_count > 0:
		_target_option.select(0)
		_selected_target_id = int(_target_option.get_item_metadata(0))
	else:
		_selected_target_id = -1


## 注入摸牌堆全量牌面候选；每次注入都会清空勾选，避免把上一局的牌 UID 带入新一次请求。
func set_draw_pile_candidates(candidates: Array[Dictionary]) -> void:
	_draw_pile_candidates = candidates.duplicate(true)
	_draw_pile_selected_uids.clear()
	_rebuild_draw_pile_grid()


## 更新排队计数；窗口未打开时也照常记录，保证打开瞬间就显示正确数量。
func set_pending_count(pending_count: int) -> void:
	if _pending_label == null:
		return
	_pending_label.text = "已排队 %d 项" % maxi(pending_count, 0)


## 更新状态行文本；空文本回退为默认引导语，避免状态行看起来像坏掉了。
func set_status_text(status_text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = status_text if not status_text.strip_edges().is_empty() else DEFAULT_STATUS_TEXT


## 打开窗口并复位到主视图；由桌面在菜单入口被点击后调用。
func open_console() -> void:
	_apply_view(View.MAIN)
	visible = true
	_refresh_view_content()
	# 焦点落在第一个效果按钮上，保证键盘用户无需鼠标即可开始操作。
	var first_button: Button = _first_effect_button()
	if first_button != null:
		first_button.grab_focus()


## 关闭窗口并归还焦点；第二层视图一并复位，避免下次打开残留上一次的子视图。
func close_console() -> void:
	visible = false
	_apply_view(View.MAIN)
	release_focus()


## 返回窗口是否可见；桌面据此判断 Esc 与返回键该关闭窗口还是继续向下传递。
func is_console_open() -> bool:
	return visible


## 按当前 UI 风格重绘全部样式；主题切换时由桌面统一调用。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	if _shade != null:
		_shade.color = BattleUIStyle.get_color("shade")
	if _frame != null:
		_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	if _scroll != null:
		BattleUIStyle.apply_main_menu_scroll_bar_style(_scroll.get_v_scroll_bar())
	# 标题与提示文字统一使用主题色；Label 必须显式覆盖 font_color，否则会回退场景默认白字。
	for label: Label in _collect_theme_labels():
		label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	# 效果行按钮与滑条、输入框逐行重绘。
	for row_variant: Variant in _effect_rows.values():
		# 当前效果行的控件组；uses_amount 为 false 时后两项为 null。
		var row: Dictionary = row_variant as Dictionary
		BattleUIStyle.apply_interaction_button(row.get("button") as Button)
		_apply_slider_style(row.get("slider") as HSlider)
		_apply_line_edit_style(row.get("input") as LineEdit)
	_apply_line_edit_style(_character_filter)
	_apply_action_button_styles()
	# 第二层候选按钮是运行时创建的，必须一并重绘，否则主题切换后仍是旧配色。
	for grid: GridContainer in [_draw_pile_grid, _character_grid]:
		if grid == null:
			continue
		for child: Node in grid.get_children():
			BattleUIStyle.apply_interaction_button(child as Button)


## 构建整棵界面树；全部节点在代码中创建，场景文件只声明根 Control 与可调参数。
func _build_ui() -> void:
	# 全屏遮罩；拦截鼠标，防止点击穿透到牌桌。
	_shade = ColorRect.new()
	_shade.name = "ConsoleShade"
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	# 居中容器；只负责把外框摆在屏幕中央，自身不拦截鼠标。
	var center: CenterContainer = CenterContainer.new()
	center.name = "ConsoleCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# 内容外框；固定最小尺寸使窗口在三个视图间切换时保持稳定的整体高度。
	_frame = PanelContainer.new()
	_frame.name = "ConsoleFrame"
	_frame.custom_minimum_size = Vector2(panel_max_width, panel_max_height)
	center.add_child(_frame)
	# 滚动容器；内容超出外框高度时滚动，保证紧凑客户区下不溢出屏幕。
	_scroll = ScrollContainer.new()
	_scroll.name = "ConsoleScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(_scroll)
	# 内容列；三个视图共用同一父节点，通过显隐切换而不是叠加第二层遮罩。
	_content = VBoxContainer.new()
	_content.name = "ConsoleContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)
	_main_view = _build_main_view()
	_draw_pile_view = _build_draw_pile_view()
	_character_view = _build_character_view()
	_content.add_child(_main_view)
	_content.add_child(_draw_pile_view)
	_content.add_child(_character_view)
	_apply_view(View.MAIN)


## 构建主视图：标题、目标选择行、九个数值效果行、两个纯按钮行与状态行。
func _build_main_view() -> VBoxContainer:
	# 主视图容器；所有行按声明顺序纵向排列。
	var view: VBoxContainer = VBoxContainer.new()
	view.name = "MainView"
	view.add_theme_constant_override("separation", 6)
	view.add_child(_make_label("开发者菜单（仅单机可用）", "ConsoleTitle"))
	# 目标选择行；所有效果统一作用于该目标，默认为本机玩家。
	var target_row: HBoxContainer = HBoxContainer.new()
	target_row.name = "TargetRow"
	target_row.add_theme_constant_override("separation", 6)
	target_row.add_child(_make_label("目标", "TargetLabel", ROW_LABEL_WIDTH))
	_target_option = OptionButton.new()
	_target_option.name = "TargetOption"
	_target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_option.item_selected.connect(_on_target_selected)
	target_row.add_child(_target_option)
	view.add_child(target_row)
	view.add_child(_make_separator("TargetSeparator"))
	# 九个数值效果行；每行「按钮 → 滑条 → 输入框」。
	for declaration: Dictionary in EFFECT_DECLARATIONS:
		if bool(declaration.get("uses_amount", true)):
			view.add_child(_build_effect_row(declaration))
	view.add_child(_make_separator("PureActionSeparator"))
	# 两个纯按钮行；点击后打开各自的第二层视图。
	for declaration: Dictionary in EFFECT_DECLARATIONS:
		if not bool(declaration.get("uses_amount", true)):
			view.add_child(_build_effect_row(declaration))
	view.add_child(_make_separator("StatusSeparator"))
	# 状态行；左侧显示最近一次执行结果，右侧显示排队数量。
	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.add_theme_constant_override("separation", 6)
	_status_label = _make_label(DEFAULT_STATUS_TEXT, "StatusLabel")
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status_label)
	_pending_label = _make_label("已排队 0 项", "PendingLabel")
	status_row.add_child(_pending_label)
	view.add_child(status_row)
	# 关闭按钮；与 Esc 等价，保证纯鼠标用户也能退出。
	var close_row: HBoxContainer = HBoxContainer.new()
	close_row.name = "CloseRow"
	close_row.alignment = BoxContainer.ALIGNMENT_END
	var close_button: Button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(120.0, 0.0)
	close_button.pressed.connect(_on_close_pressed)
	close_row.add_child(close_button)
	view.add_child(close_row)
	return view


## 构建单个效果行：按钮固定宽度，数值类追加滑条与无上限输入框。
func _build_effect_row(declaration: Dictionary) -> HBoxContainer:
	# 效果键；作为稳定协议字符串在信号中回传，界面不解释其语义。
	var effect_kind: String = str(declaration.get("kind", ""))
	# 是否使用数值；false 的两项渲染为纯按钮，点击后打开第二层视图。
	var uses_amount: bool = bool(declaration.get("uses_amount", true))
	# 效果行容器；按钮、滑条与输入框在同一行内。
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "EffectRow_%s" % effect_kind
	row.add_theme_constant_override("separation", 6)
	# 效果按钮；按下即提交当前数值，纯按钮项则打开第二层视图。
	var button: Button = Button.new()
	button.name = "EffectButton"
	button.text = str(declaration.get("label", effect_kind))
	button.custom_minimum_size = Vector2(EFFECT_BUTTON_WIDTH, 0.0)
	button.pressed.connect(_on_effect_pressed.bind(effect_kind))
	row.add_child(button)
	# 数值滑条与输入框；仅数值类效果创建，纯按钮项保持为 null。
	var slider: HSlider = null
	var input: LineEdit = null
	if uses_amount:
		slider = HSlider.new()
		slider.name = "EffectSlider"
		slider.min_value = AMOUNT_SLIDER_MIN
		slider.max_value = AMOUNT_SLIDER_MAX
		slider.step = AMOUNT_SLIDER_STEP
		slider.value = AMOUNT_SLIDER_MIN
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 滑条垂直居中：HSlider 的 size_flags_vertical 默认是 SIZE_SHRINK_BEGIN（顶部收缩），
		# 而效果行高度由按钮撑到 35 像素，滑条自身只有 16 像素高，顶部对齐会让拖条明显偏上。
		# 设为居中后滑条中心与按钮中心重合，视觉上拖条正好落在按钮中间。
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)
		input = LineEdit.new()
		input.name = "EffectInput"
		input.text = str(AMOUNT_SLIDER_MIN)
		input.custom_minimum_size = Vector2(AMOUNT_INPUT_WIDTH, 0.0)
		row.add_child(input)
		# 滑条单向驱动输入框文本：输入框始终持有真实数值，滑条不反向读取，避免两者互相触发的回环。
		slider.value_changed.connect(_on_effect_slider_changed.bind(input))
	_effect_rows[effect_kind] = {"button":button, "slider":slider, "input":input}
	return row


## 构建摸牌堆第二层视图：提示行、候选网格与「确定获得 / 返回」动作行。
func _build_draw_pile_view() -> VBoxContainer:
	# 摸牌堆视图容器；与主视图共用同一滚动区，通过显隐切换。
	var view: VBoxContainer = VBoxContainer.new()
	view.name = "DrawPileView"
	view.add_theme_constant_override("separation", 6)
	view.add_child(_make_label("从摸牌堆获得指定牌（可多选，按确定后获得）", "DrawPileTitle"))
	_draw_pile_hint = _make_label("尚未载入牌堆。", "DrawPileHint")
	view.add_child(_draw_pile_hint)
	# 候选滚动区；固定高度使三个视图切换时窗口总高度稳定。
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "DrawPileScroll"
	scroll.custom_minimum_size = Vector2(0.0, SUB_VIEW_SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_draw_pile_grid = GridContainer.new()
	_draw_pile_grid.name = "DrawPileGrid"
	_draw_pile_grid.columns = DRAW_PILE_GRID_COLUMNS
	_draw_pile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_draw_pile_grid)
	view.add_child(scroll)
	view.add_child(_build_sub_view_action_row("确定获得", _on_draw_pile_confirm))
	return view


## 构建换将第二层视图：筛选框、候选网格与「确定更换 / 返回」动作行。
func _build_character_view() -> VBoxContainer:
	# 换将视图容器；武将池接近两百项，因此提供名称筛选。
	var view: VBoxContainer = VBoxContainer.new()
	view.name = "CharacterView"
	view.add_theme_constant_override("separation", 6)
	view.add_child(_make_label("更换目标武将（包含特殊武将）", "CharacterTitle"))
	_character_filter = LineEdit.new()
	_character_filter.name = "CharacterFilter"
	_character_filter.placeholder_text = "输入武将名筛选"
	_character_filter.text_changed.connect(_on_character_filter_changed)
	view.add_child(_character_filter)
	# 候选滚动区；与摸牌堆视图同高，保持窗口尺寸稳定。
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "CharacterScroll"
	scroll.custom_minimum_size = Vector2(0.0, SUB_VIEW_SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_grid = GridContainer.new()
	_character_grid.name = "CharacterGrid"
	_character_grid.columns = CHARACTER_GRID_COLUMNS
	_character_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_character_grid)
	view.add_child(scroll)
	view.add_child(_build_sub_view_action_row("确定更换", _on_character_confirm))
	return view


## 构建第二层视图的「确定 / 返回」动作行；返回等价于 Esc。
func _build_sub_view_action_row(confirm_text: String, confirm_callable: Callable) -> HBoxContainer:
	# 动作行容器；确定按钮靠右，返回按钮在其左侧。
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "SubViewActionRow"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	var back_button: Button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(120.0, 0.0)
	back_button.pressed.connect(_return_to_main_view)
	row.add_child(back_button)
	var confirm_button: Button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.text = confirm_text
	confirm_button.custom_minimum_size = Vector2(120.0, 0.0)
	confirm_button.pressed.connect(confirm_callable)
	row.add_child(confirm_button)
	return row


## 创建统一字体色的标签；所有 Label 都必须带 font_color 覆盖，否则会回退场景默认白字并触发字体色审计失败。
func _make_label(text: String, node_name: String, minimum_width: float = 0.0) -> Label:
	# 新标签；文本内容由调用方决定，颜色统一由 refresh_ui_style 覆盖。
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	if minimum_width > 0.0:
		label.custom_minimum_size = Vector2(minimum_width, 0.0)
	label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	return label


## 创建水平分隔线；仅用于视觉分组，不参与输入。
func _make_separator(node_name: String) -> HSeparator:
	# 新分隔线；名称用于在远程调试器中定位。
	var separator: HSeparator = HSeparator.new()
	separator.name = node_name
	return separator


## 切换当前视图；第二层视图在同一个遮罩内替换内容。
func _apply_view(next_view: View) -> void:
	_view = next_view
	if _main_view != null:
		_main_view.visible = next_view == View.MAIN
	if _draw_pile_view != null:
		_draw_pile_view.visible = next_view == View.DRAW_PILE
	if _character_view != null:
		_character_view.visible = next_view == View.CHARACTER
	# 滚动位置复位到顶部，避免进入第二层视图时停在上一层的滚动偏移。
	if _scroll != null:
		_scroll.scroll_vertical = 0


## 打开第二层视图并刷新其内容；换将候选池较大，只在进入视图时才构建。
func _open_view(next_view: View) -> void:
	if _selected_target_id < 0:
		set_status_text("请先选择目标。")
		return
	if next_view == View.DRAW_PILE:
		# 先请求桌面注入牌面；桌面在本次信号内同步回填 set_draw_pile_candidates()，随后即可显示最新候选。
		draw_pile_candidates_requested.emit()
	if next_view == View.CHARACTER:
		_rebuild_character_grid()
	_apply_view(next_view)
	_refresh_view_content()


## 返回主视图；由返回按钮与 Esc 共用。
func _return_to_main_view() -> void:
	_apply_view(View.MAIN)


## 刷新当前视图的辅助信息；主视图无需额外刷新。
func _refresh_view_content() -> void:
	if _view == View.DRAW_PILE:
		_refresh_draw_pile_hint()


## 重建摸牌堆候选网格；每张牌是一个可切换按钮，勾选状态以实体牌 UID 记录。
func _rebuild_draw_pile_grid() -> void:
	if _draw_pile_grid == null:
		return
	# 立即摘除旧子节点：仅 queue_free 会让它们在本帧内继续被 get_children 返回，导致重复叠加。
	for child: Node in _draw_pile_grid.get_children():
		_draw_pile_grid.remove_child(child)
		child.queue_free()
	for candidate: Dictionary in _draw_pile_candidates:
		# 实体牌 UID；负数表示快照异常，直接跳过而不是创建一个无法提交的按钮。
		var card_uid: int = int(candidate.get("uid", -1))
		if card_uid < 0:
			continue
		# 牌面静态定义；只读取 GameDatabase 与 GameSettings，不触碰对局状态。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		# 实体牌按钮；切换态直接表达勾选，不使用 CheckBox 以避开自定义指示器的额外约束。
		var card_button: Button = Button.new()
		card_button.name = "DrawPileCard_%d" % card_uid
		card_button.toggle_mode = true
		card_button.text = _format_card_candidate_text(card_data)
		card_button.custom_minimum_size = Vector2(CARD_BUTTON_WIDTH, 0.0)
		card_button.toggled.connect(_on_draw_pile_card_toggled.bind(card_uid))
		_draw_pile_grid.add_child(card_button)
	_refresh_draw_pile_hint()


## 重建换将候选网格；按筛选文本过滤，未选中任何武将时确认按钮只提示。
func _rebuild_character_grid() -> void:
	if _character_grid == null:
		return
	for child: Node in _character_grid.get_children():
		_character_grid.remove_child(child)
		child.queue_free()
	# 筛选关键字；空字符串表示不过滤。
	var filter_text: String = _character_filter.text.strip_edges() if _character_filter != null else ""
	# 全部可选武将；按需求包含特殊武将，与普通选将池不同。
	var character_ids: Array[String] = GameDatabase.get_selectable_character_ids(true)
	for character_id: String in character_ids:
		# 武将显示名；筛选与按钮文字共用同一来源。
		var display_name: String = GameDatabase.resolve_character_name(character_id)
		if not filter_text.is_empty() and not display_name.contains(filter_text):
			continue
		# 武将按钮；单选，选中态以 _selected_character_id 记录。
		var character_button: Button = Button.new()
		character_button.name = "CharacterCandidate_%s" % character_id
		character_button.toggle_mode = true
		character_button.text = display_name
		character_button.custom_minimum_size = Vector2(CHARACTER_BUTTON_WIDTH, 0.0)
		character_button.button_pressed = character_id == _selected_character_id
		character_button.toggled.connect(_on_character_candidate_toggled.bind(character_id))
		_character_grid.add_child(character_button)


## 刷新摸牌堆视图提示行；同时反映已载入牌数与当前勾选数。
func _refresh_draw_pile_hint() -> void:
	if _draw_pile_hint == null:
		return
	_draw_pile_hint.text = "牌堆共 %d 张，已选择 %d 张。" % [_draw_pile_candidates.size(), _draw_pile_selected_uids.size()]


## 组装一张实体牌的按钮文字；走全局名称模式解析，避免稳定 ID 泄漏到界面。
func _format_card_candidate_text(card_data: Dictionary) -> String:
	# 卡牌稳定 ID；用于读取静态定义与显示名。
	var definition_id: String = str(card_data.get("definition_id", ""))
	# 牌面显示名；与图鉴、手牌共用同一解析入口。
	var display_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card(definition_id))
	if display_name.strip_edges().is_empty():
		display_name = definition_id if not definition_id.is_empty() else "未知牌"
	# 花色符号与点数；花色未知时原样回退，保证信息不丢失。
	var suit_text: String = str(SUIT_SYMBOLS.get(str(card_data.get("suit", "")), str(card_data.get("suit", ""))))
	return "%s %s%d" % [display_name, suit_text, int(card_data.get("rank", 0))]


## 解析某效果行当前应提交的数值；输入框文本优先，非法或空则回退滑条值，只钳制下限。
func _resolve_amount(effect_kind: String) -> int:
	# 当前效果行控件组；缺失时按下限提交，保证不会发出非法数值。
	var row: Dictionary = _effect_rows.get(effect_kind, {}) as Dictionary
	var slider: HSlider = row.get("slider") as HSlider
	var input: LineEdit = row.get("input") as LineEdit
	# 初始解析结果；以滑条值为基准。
	var resolved_amount: int = int(slider.value) if slider != null else AMOUNT_INPUT_MIN
	if input != null:
		# 输入框文本；允许前后空格，非法内容回退滑条值。
		var input_text: String = input.text.strip_edges()
		if input_text.is_valid_int():
			resolved_amount = input_text.to_int()
	# 只对下限钳制：输入框不设上限，满足「输入框不限数值」的需求。
	return maxi(resolved_amount, AMOUNT_INPUT_MIN)


## 返回第一个数值效果按钮；用于打开窗口时移交焦点。
func _first_effect_button() -> Button:
	for declaration: Dictionary in EFFECT_DECLARATIONS:
		# 当前声明对应的效果行；缺失时继续查找。
		var row: Dictionary = _effect_rows.get(str(declaration.get("kind", "")), {}) as Dictionary
		var button: Button = row.get("button") as Button
		if button != null:
			return button
	return null


## 收集需要统一字体色的标签；供主题刷新批量覆盖。
func _collect_theme_labels() -> Array[Label]:
	# 主题标签清单；只包含本组件创建且需要主题色的 Label。
	var labels: Array[Label] = []
	for label: Label in [_status_label, _pending_label, _draw_pile_hint]:
		if label != null:
			labels.append(label)
	# 标题类标签；通过名称前缀定位，避免额外维护一份引用清单。
	for node: Node in _find_nodes_by_prefix(self, "ConsoleTitle"):
		labels.append(node as Label)
	for node: Node in _find_nodes_by_prefix(self, "DrawPileTitle"):
		labels.append(node as Label)
	for node: Node in _find_nodes_by_prefix(self, "CharacterTitle"):
		labels.append(node as Label)
	for node: Node in _find_nodes_by_prefix(self, "TargetLabel"):
		labels.append(node as Label)
	return labels


## 按名称前缀深度优先查找节点；用于收集分散在三个视图里的标题标签。
func _find_nodes_by_prefix(root: Node, prefix: String) -> Array[Node]:
	# 命中结果；保持深度优先顺序，便于稳定重绘。
	var matches: Array[Node] = []
	for child: Node in root.get_children():
		if child.name.begins_with(prefix):
			matches.append(child)
		matches.append_array(_find_nodes_by_prefix(child, prefix))
	return matches


## 为第二层视图与关闭按钮上色；这些按钮在三个视图中分散存在，统一在此处理。
func _apply_action_button_styles() -> void:
	for node: Node in _find_nodes_by_prefix(self, "BackButton"):
		BattleUIStyle.apply_interaction_button(node as Button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	for node: Node in _find_nodes_by_prefix(self, "ConfirmButton"):
		BattleUIStyle.apply_interaction_button(node as Button)
	for node: Node in _find_nodes_by_prefix(self, "CloseButton"):
		BattleUIStyle.apply_interaction_button(node as Button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)


## 为滑条应用主题轨道与已选区域；数值范围由效果声明决定，不在此修改。
func _apply_slider_style(slider: HSlider) -> void:
	if slider == null:
		return
	# 未选择区域轨道；低对比度细边保证在两套深色主题下都清晰可见。
	var track_style: StyleBoxFlat = _make_flat_inner_panel(BattleUIStyle.get_color("disabled_button"), BattleUIStyle.get_color("disabled_button_border"), 1, 4)
	track_style.content_margin_top = 3.0
	track_style.content_margin_bottom = 3.0
	# 已选择区域轨道；主题强调色半透明填充表达当前数值，不引入固定配色。
	var filled_style: StyleBoxFlat = _make_flat_inner_panel(Color(BattleUIStyle.get_color("accent"), 0.72), BattleUIStyle.get_color("accent"), 1, 4)
	filled_style.content_margin_top = 3.0
	filled_style.content_margin_bottom = 3.0
	slider.add_theme_stylebox_override("slider", track_style)
	slider.add_theme_stylebox_override("grabber_area", filled_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled_style)


## 为数值输入框应用当前主题常态与焦点样式；文本选择区使用半透明强调色。
func _apply_line_edit_style(line_edit: LineEdit) -> void:
	if line_edit == null:
		return
	line_edit.add_theme_font_override("font", ThemeDB.fallback_font)
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_placeholder_color", BattleUIStyle.get_color("text_muted"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 创建没有重复阴影的内层面板；滑条轨道复用统一面板工厂后移除阴影。
func _make_flat_inner_panel(background_color: Color, border_color: Color, border_width: int = 1, corner_radius: int = 5) -> StyleBoxFlat:
	# 内层样式；复用主题工厂保证配色跟随当前风格。
	var style: StyleBoxFlat = BattleUIStyle.make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


## 处理 Esc 与安卓返回；第二层视图优先返回上一层，主视图才请求关闭窗口。
func _unhandled_input(event: InputEvent) -> void:
	# 窗口隐藏时不参与输入，避免在不可见状态下吞掉牌桌的取消与返回操作。
	if not visible:
		return
	# 取消输入判定；同时接受 ui_cancel 动作与原始 Esc 键，
	# 与桌面既有「按 keycode 直接判断 Esc」的写法保持一致，避免项目自定义输入映射后失效。
	var is_cancel_input: bool = event.is_action_pressed("ui_cancel")
	if not is_cancel_input and event is InputEventKey:
		# 当前键盘事件；忽略自动重复，避免长按 Esc 连续弹层。
		var key_event: InputEventKey = event as InputEventKey
		is_cancel_input = key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE
	if not is_cancel_input:
		return
	if _view != View.MAIN:
		_return_to_main_view()
	else:
		close_requested.emit()
	get_viewport().set_input_as_handled()


## 目标选择变化；只记录稳定座次，效果提交时再一并发出。
func _on_target_selected(index: int) -> void:
	if _target_option == null or index < 0 or index >= _target_option.item_count:
		return
	_selected_target_id = int(_target_option.get_item_metadata(index))


## 滑条数值变化；单向写入输入框文本，输入框始终持有真实数值。
func _on_effect_slider_changed(value: float, input: LineEdit) -> void:
	if input == null:
		return
	input.text = str(int(value))


## 效果按钮按下；数值类直接提交，载荷类先打开第二层视图。
func _on_effect_pressed(effect_kind: String) -> void:
	if effect_kind == DeveloperEffectService.EFFECT_GAIN_DRAW_PILE_CARD:
		_open_view(View.DRAW_PILE)
		return
	if effect_kind == DeveloperEffectService.EFFECT_REPLACE_CHARACTER:
		_open_view(View.CHARACTER)
		return
	if _selected_target_id < 0:
		set_status_text("请先选择目标。")
		return
	effect_requested.emit(effect_kind, _selected_target_id, _resolve_amount(effect_kind))


## 摸牌堆候选勾选变化；以实体牌 UID 记录，便于网格重建后恢复。
func _on_draw_pile_card_toggled(pressed: bool, card_uid: int) -> void:
	if pressed:
		_draw_pile_selected_uids[card_uid] = true
	else:
		_draw_pile_selected_uids.erase(card_uid)
	_refresh_draw_pile_hint()


## 确认从摸牌堆获得勾选的牌；未勾选任何牌时只提示。
func _on_draw_pile_confirm() -> void:
	if _selected_target_id < 0:
		set_status_text("请先选择目标。")
		return
	if _draw_pile_selected_uids.is_empty():
		set_status_text("请至少选择一张牌。")
		return
	# 待获得的实体牌 UID 列表；按选择顺序稳定输出。
	var selected_uids: Array[int] = []
	for uid_variant: Variant in _draw_pile_selected_uids.keys():
		selected_uids.append(int(uid_variant))
	draw_pile_gain_requested.emit(_selected_target_id, selected_uids)
	_draw_pile_selected_uids.clear()
	_rebuild_draw_pile_grid()
	_return_to_main_view()


## 换将候选选中变化；单选语义，取消勾选等价于清空选择。
func _on_character_candidate_toggled(pressed: bool, character_id: String) -> void:
	if not pressed:
		if _selected_character_id == character_id:
			_selected_character_id = ""
		return
	_selected_character_id = character_id
	# 单选：取消其他候选的勾选态，避免界面出现多个高亮。
	if _character_grid == null:
		return
	for child: Node in _character_grid.get_children():
		# 当前候选按钮；跳过刚被勾选的那一个。
		var candidate_button: Button = child as Button
		if candidate_button == null or candidate_button.name == "CharacterCandidate_%s" % character_id:
			continue
		candidate_button.set_pressed_no_signal(false)


## 筛选文本变化；重建候选网格，使输入即时生效。
func _on_character_filter_changed(_new_text: String) -> void:
	_rebuild_character_grid()


## 确认更换武将；未选择任何武将时只提示。
func _on_character_confirm() -> void:
	if _selected_target_id < 0:
		set_status_text("请先选择目标。")
		return
	if _selected_character_id.is_empty():
		set_status_text("请选择一名武将。")
		return
	character_replace_requested.emit(_selected_target_id, _selected_character_id)
	_return_to_main_view()


## 关闭按钮按下；与 Esc 等价。
func _on_close_pressed() -> void:
	close_requested.emit()
