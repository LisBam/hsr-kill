class_name CardSelectionPanel
extends Control

## 通用卡牌选择面板。响应、弃牌、目标区域选牌和展示牌选择都向该组件传入序列化请求。

## 用户确认选牌时发出请求序号与稳定实体牌 UID；组件不直接修改规则状态。
signal choice_submitted(request_id: int, selected_card_uids: Array[int])

## 用户在允许放弃的请求中取消选择时发出；桌面会转换为空 UID 的 choose_cards 动作。
signal choice_cancelled(request_id: int)

## 用户选择文字控制项时发出请求序号与稳定选项 ID；组件不解释该选项对应的技能效果。
signal control_submitted(request_id: int, control_id: String)

## 正式卡牌视图场景；正面候选和牌背候选都复用同一111×148像素组件。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 选择面板最大宽度；默认920像素可同时容纳多个牌面，运行时通常无需修改。
@export_range(520.0, 1180.0, 1.0) var panel_max_width: float = 920.0

## 选择面板最大高度；默认590像素确保1280×720视口仍保留外侧边距，运行时通常无需修改。
@export_range(360.0, 680.0, 1.0) var panel_max_height: float = 590.0

## 全屏背景滤镜颜色；默认沿用深色强遮罩，正式主场景可在检查器中覆盖为更浅透明度。
@export var shade_color: Color = Color("010205dc")

## 已领取公共牌的复制虚影调制色；默认保留48%透明度，确保原始牌面仍可辨认但不会与剩余候选混淆。
@export var taken_card_ghost_modulate: Color = Color(0.72, 0.72, 0.72, 0.48)

## 已领取牌底部武将名标签背景色；默认使用高不透明暖黑色保证浅色牌面上的文字可读。
@export var taken_card_label_background_color: Color = Color("11151de8")

## 已领取牌底部武将名标签矩形；固定贴合111×148像素牌面的下沿，不改变牌位尺寸或换行结果。
const TAKEN_CARD_LABEL_RECT: Rect2 = Rect2(4.0, 118.0, 103.0, 26.0)

## 五谷丰登公共展示每行固定牌数；默认4张，更多牌自动进入下一行且不改变固定牌位顺序。
const PUBLIC_CARD_COLUMNS: int = 4

## 公共展示正式牌面尺寸；与 CardView 的111×148像素规格一致，用于计算紧凑窗口宽高。
const PUBLIC_CARD_SIZE: Vector2 = Vector2(111.0, 148.0)

## 公共展示牌位的水平与垂直间距；默认8像素与普通选择牌列保持一致。
const PUBLIC_CARD_GAP: float = 8.0

## 公共展示窗口除牌阵外的标题、提示、按钮与边距预留高度；默认142像素保证三行牌仍完整可见。
const PUBLIC_PANEL_CHROME_HEIGHT: float = 142.0

## 公共展示窗口的最小宽度；默认360像素保证“五谷丰登”标题与当前选择者提示不会被过度压缩。
const PUBLIC_PANEL_MIN_WIDTH: float = 360.0

## 公共展示窗口牌阵两侧总留白；默认36像素只保留面板边距，不在右侧留下旧固定宽度的大块空白。
const PUBLIC_PANEL_HORIZONTAL_PADDING: float = 36.0

## 公共展示窗口允许的最大高度；默认620像素可完整容纳最多10人时的三行牌，运行时通常无需修改。
@export_range(360.0, 680.0, 1.0) var public_panel_max_height: float = 620.0

## 当前请求只读快照；空字典表示面板已关闭。
var _choice_request: Dictionary = {}

## 当前按点击顺序选择的实体牌 UID；提交前只存在于界面临时状态。
var _selected_card_uids: Array[int] = []

## 实体牌 UID 到正式卡牌视图的映射；用于同步金色选中描边。
var _card_views: Dictionary = {}

## 当前允许本地点击的实体牌 UID；公共展示中的复制虚影和旁观牌位不会进入该集合。
var _selectable_card_uids: Array[int] = []

## 当前公共选牌展示只读快照；空字典表示使用普通一次性选择窗口。
var _public_display: Dictionary = {}

## 半透明全屏遮罩；阻止请求期间点击牌桌的其他操作。
var _shade: ColorRect

## 居中选择框；承载标题、分区牌列和确认操作。
var _frame: PanelContainer

## 请求标题标签；显示“响应询问”“弃牌阶段”等永久规则语义。
var _title_label: Label

## 请求说明标签；显示本次所需选择数量与操作目的。
var _prompt_label: Label

## 分区内容容器；固定按手牌区、装备区、判定区和展示区顺序重建。
var _zone_container: VBoxContainer

## 确认按钮；仅在当前选择数量满足请求约束时可用。
var _confirm_button: Button

## 放弃按钮；只有请求允许0张牌或明确允许取消时显示。
var _cancel_button: Button

## 底部操作行；公共展示对非选择者保持隐藏，避免只读窗口出现无效按钮占位。
var _action_row: HBoxContainer

## 当前动态区域标题标签；主题切换时只重绘颜色，不重建候选牌或清空玩家选择。
var _section_labels: Array[Label] = []

## 当前公共牌领取者标签；主题切换时同步文字与背景描边，固定牌位和归属数据保持不变。
var _owner_labels: Array[Label] = []

## 当前文字选项按钮集合；只用于主题刷新，请求切换或关闭时随动态内容一并清空。
var _control_option_buttons: Array[Button] = []


## 创建可复用选择框的稳定节点结构；具体候选只在收到请求时动态生成。
func _ready() -> void:
	z_index = 45
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = BattleUIStyle.get_color("shade", shade_color)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_frame = PanelContainer.new()
	_set_frame_size(Vector2(panel_max_width, panel_max_height))
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("selection_panel"), BattleUIStyle.get_color("border"), 2, 6))
	add_child(_frame)
	# 选择框主列；标题、提示、滚动分区和操作按钮从上到下排列。
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_frame.add_child(content)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_title_label)
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_prompt_label)
	# 候选滚动区；牌数较多时保持面板尺寸稳定并允许纵向查看全部区域。
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_zone_container = VBoxContainer.new()
	_zone_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_container.add_theme_constant_override("separation", 12)
	scroll.add_child(_zone_container)
	# 底部操作行；确定和放弃始终位于固定位置，不随候选数量移动。
	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 10)
	content.add_child(_action_row)
	_confirm_button = Button.new()
	_confirm_button.text = "确定"
	_confirm_button.custom_minimum_size = Vector2(132.0, 40.0)
	BattleUIStyle.apply_interaction_button(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_action_row.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = "不选择"
	_cancel_button.custom_minimum_size = Vector2(96.0, 40.0)
	BattleUIStyle.apply_interaction_button(_cancel_button)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_action_row.add_child(_cancel_button)
	visible = false


## 按当前活动 UI 风格重绘选择窗口；请求、候选、固定牌位和临时选中顺序保持不变。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	shade_color = BattleUIStyle.get_color("shade", shade_color)
	taken_card_label_background_color = BattleUIStyle.get_color("taken_label_background", taken_card_label_background_color)
	_shade.color = shade_color
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("selection_panel"), BattleUIStyle.get_color("border"), 2, 6))
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_prompt_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	BattleUIStyle.apply_interaction_button(_confirm_button)
	BattleUIStyle.apply_interaction_button(_cancel_button)
	for section_label: Label in _section_labels:
		if section_label != null and is_instance_valid(section_label):
			section_label.add_theme_color_override("font_color", BattleUIStyle.get_color("selection_section"))
	for owner_label: Label in _owner_labels:
		if owner_label != null and is_instance_valid(owner_label):
			_apply_owner_label_style(owner_label)
	for option_button: Button in _control_option_buttons:
		if option_button != null and is_instance_valid(option_button):
			BattleUIStyle.apply_interaction_button(option_button)
	for card_view_variant: Variant in _card_views.values():
		# 当前候选牌面；只刷新主题色，不改变是否可选或复制虚影状态。
		var card_view: CardView = card_view_variant as CardView
		if card_view != null and is_instance_valid(card_view):
			card_view.refresh_ui_style()


## 显示一条规则层选择请求；重复调用会完整替换旧候选和本地临时选择。
func show_request(choice_request: Dictionary) -> void:
	_choice_request = choice_request.duplicate(true)
	_public_display.clear()
	_selected_card_uids.clear()
	_card_views.clear()
	_selectable_card_uids.clear()
	_section_labels.clear()
	_owner_labels.clear()
	_control_option_buttons.clear()
	_clear_container(_zone_container)
	_set_frame_size(Vector2(panel_max_width, panel_max_height))
	_title_label.text = str(_choice_request.get("title", "选择卡牌"))
	_prompt_label.text = str(_choice_request.get("prompt", "请选择卡牌"))
	# 文字控制项请求；每个选项直接以独立按钮提交，底部确定按钮不重复制造二次确认。
	if str(_choice_request.get("choice_type", "card")) in ["control", "bool"]:
		_add_control_options(_choice_request.get("control_options", []) as Array)
		_confirm_button.visible = false
		_cancel_button.visible = bool(_choice_request.get("allow_cancel", false))
		_action_row.visible = _cancel_button.visible
		visible = true
		return
	_confirm_button.visible = true
	# 按区域聚合候选；字典数组保持请求原始顺序，手牌牌背仍可逐张选择。
	var candidates_by_zone: Dictionary = {"hand":[], "equipment":[], "judgment":[], "processing":[]}
	for candidate_variant: Variant in _choice_request.get("candidates", []):
		var candidate: Dictionary = candidate_variant as Dictionary
		# 当前候选实体 UID；有效值会加入本地可选集合并用于点击校验。
		var candidate_uid: int = int(candidate.get("uid", -1))
		if candidate_uid >= 0 and not _selectable_card_uids.has(candidate_uid):
			_selectable_card_uids.append(candidate_uid)
		var zone: String = str(candidate.get("zone", "processing"))
		if not candidates_by_zone.has(zone):
			candidates_by_zone[zone] = []
		(candidates_by_zone[zone] as Array).append(candidate)
	for zone: String in ["hand", "equipment", "judgment", "processing"]:
		_add_zone_row(zone, candidates_by_zone.get(zone, []) as Array)
	_cancel_button.visible = bool(_choice_request.get("allow_cancel", false)) or int(_choice_request.get("min_select", 0)) == 0
	_action_row.visible = true
	_refresh_selection_state()
	visible = true


## 显示一份跨多名玩家持续存在的公共选牌快照；只有传入有效本地请求时开放牌面与确认按钮。
func show_public_display(display_data: Dictionary, choice_request: Dictionary = {}) -> void:
	_public_display = display_data.duplicate(true)
	_choice_request = choice_request.duplicate(true)
	_selected_card_uids.clear()
	_card_views.clear()
	_selectable_card_uids.clear()
	_section_labels.clear()
	_owner_labels.clear()
	_control_option_buttons.clear()
	_clear_container(_zone_container)
	# 公共固定牌位数量；窗口宽度最多容纳4张，牌数增加时只向下扩展新行。
	var display_slot_count: int = (_public_display.get("slots", []) as Array).size()
	# 当前实际列数；不足4张时按真实牌数收紧，但保留最小标题宽度。
	var column_count: int = mini(maxi(display_slot_count, 1), PUBLIC_CARD_COLUMNS)
	# 当前实际行数；空展示保留1行最小窗口，正常五谷按4张一行向上取整。
	var row_count: int = maxi(ceili(float(display_slot_count) / float(PUBLIC_CARD_COLUMNS)), 1)
	# 当前公共牌阵宽度；四列时固定为468像素。
	var public_cards_width: float = PUBLIC_CARD_SIZE.x * float(column_count) + PUBLIC_CARD_GAP * float(maxi(column_count - 1, 0))
	# 当前公共牌阵高度；最多10名玩家时为3行共460像素。
	var public_cards_height: float = PUBLIC_CARD_SIZE.y * float(row_count) + PUBLIC_CARD_GAP * float(maxi(row_count - 1, 0))
	_set_frame_size(Vector2(maxf(PUBLIC_PANEL_MIN_WIDTH, public_cards_width + PUBLIC_PANEL_HORIZONTAL_PADDING), minf(public_panel_max_height, public_cards_height + PUBLIC_PANEL_CHROME_HEIGHT)))
	_title_label.text = str(_public_display.get("title", "公共选牌"))
	_prompt_label.text = str(_public_display.get("prompt", "等待当前角色选择"))
	# 当前本地可选候选；只取有效 UID，公共牌位仍由完整 slots 数组决定固定顺序。
	for candidate_variant: Variant in _choice_request.get("candidates", []) as Array:
		# 当前规则候选；已被其他角色取得的牌不会出现在该请求中。
		var candidate: Dictionary = candidate_variant as Dictionary
		# 当前规则候选实体 UID；只开放本次权威请求明确允许的固定牌位。
		var candidate_uid: int = int(candidate.get("uid", -1))
		if candidate_uid >= 0 and not _selectable_card_uids.has(candidate_uid):
			_selectable_card_uids.append(candidate_uid)
	_add_public_card_row(_public_display.get("slots", []) as Array)
	# 是否存在本地交互请求；旁观其他角色选择时只保留公共牌位，不显示确定或取消按钮。
	var has_interactive_request: bool = int(_choice_request.get("request_id", -1)) >= 0
	_action_row.visible = has_interactive_request
	_confirm_button.visible = true
	_cancel_button.visible = has_interactive_request and (bool(_choice_request.get("allow_cancel", false)) or int(_choice_request.get("min_select", 0)) == 0)
	_refresh_selection_state()
	visible = true


## 关闭并清理当前选择请求；规则层提交成功或重新开局时调用。
func close() -> void:
	visible = false
	_choice_request.clear()
	_public_display.clear()
	_selected_card_uids.clear()
	_card_views.clear()
	_selectable_card_uids.clear()
	_control_option_buttons.clear()
	_clear_container(_zone_container)
	_confirm_button.visible = true


## 为一个非空区域创建标题与横向牌列；空区域不占用布局空间。
func _add_zone_row(zone: String, candidates: Array) -> void:
	if candidates.is_empty():
		return
	# 当前区域容器；标题在上、牌列在下，符合从上到下的区域阅读顺序。
	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	_zone_container.add_child(section)
	# 区域标题；使用规则区名称而不是技术字符串。
	var zone_label: Label = Label.new()
	zone_label.text = {"hand":"手牌区", "equipment":"装备区", "judgment":"判定区", "processing":"展示区"}.get(zone, zone)
	zone_label.add_theme_color_override("font_color", BattleUIStyle.get_color("selection_section"))
	zone_label.add_theme_font_size_override("font_size", 16)
	section.add_child(zone_label)
	_section_labels.append(zone_label)
	# 横向牌列；每张 Node2D 牌面由固定尺寸 Control 包装，避免动态内容改变布局。
	var card_row: HFlowContainer = HFlowContainer.new()
	card_row.add_theme_constant_override("h_separation", 8)
	card_row.add_theme_constant_override("v_separation", 8)
	section.add_child(card_row)
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		_add_card_slot(card_row, candidate, _selectable_card_uids.has(int(candidate.get("uid", -1))), false, "")


## 创建文字控制项按钮列；选项标签由规则请求提供，稳定 ID 只随按钮信号返回而不显示技术字段。
func _add_control_options(options: Array) -> void:
	# 选项按钮列；固定宽度与间距避免不同文本长度改变窗口或相邻按钮位置。
	var option_column: VBoxContainer = VBoxContainer.new()
	option_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	option_column.add_theme_constant_override("separation", 10)
	_zone_container.add_child(option_column)
	for option_variant: Variant in options:
		# 当前文字选项；缺失稳定 ID 或标签的异常数据不生成不可提交按钮。
		var option: Dictionary = option_variant as Dictionary
		var option_id: String = str(option.get("id", ""))
		var option_label: String = str(option.get("label", ""))
		if option_id.is_empty() or option_label.is_empty():
			continue
		# 当前选项按钮；固定280×44像素，长文本按控件宽度截断并保留完整工具提示。
		var option_button: Button = Button.new()
		option_button.text = option_label
		option_button.tooltip_text = option_label
		option_button.custom_minimum_size = Vector2(280.0, 44.0)
		option_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		BattleUIStyle.apply_interaction_button(option_button)
		option_button.pressed.connect(_on_control_option_pressed.bind(option_id))
		option_column.add_child(option_button)
		_control_option_buttons.append(option_button)


## 为公共选牌展示创建固定牌位；已领取牌继续显示复制虚影，并在牌底标明领取者武将名。
func _add_public_card_row(display_slots: Array) -> void:
	if display_slots.is_empty():
		return
	# 固定四列牌阵；每行严格4张，已领取牌只改变虚影与标签，不删除或补位。
	var card_row: GridContainer = GridContainer.new()
	card_row.columns = PUBLIC_CARD_COLUMNS
	card_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_row.add_theme_constant_override("h_separation", int(PUBLIC_CARD_GAP))
	card_row.add_theme_constant_override("v_separation", int(PUBLIC_CARD_GAP))
	_zone_container.add_child(card_row)
	for slot_variant: Variant in display_slots:
		# 当前固定牌位；牌面来自最初公开快照，领取者只改变虚影和底部标签。
		var display_slot: Dictionary = slot_variant as Dictionary
		# 当前固定牌位实体 UID；用于匹配本地可选集合并建立视图索引。
		var card_uid: int = int(display_slot.get("uid", -1))
		# 当前领取者玩家 ID；-1表示仍未被取得，非负值表示显示复制虚影。
		var taken_by_player_id: int = int(display_slot.get("taken_by_player_id", -1))
		# 当前牌位候选表现数据；公共牌全部正面可见，但交互性由请求 UID 单独决定。
		var candidate: Dictionary = {
			"uid":card_uid,
			"visible":true,
			"card_data":display_slot.get("card_data", {}) as Dictionary,
		}
		_add_card_slot(card_row, candidate, _selectable_card_uids.has(card_uid) and taken_by_player_id < 0, taken_by_player_id >= 0, str(display_slot.get("taken_by_character_name", "")))


## 创建一个正式卡牌牌位；可选牌连接输入，只读牌保留完整亮度，已领取牌叠加复制虚影与武将名。
func _add_card_slot(card_row: Container, candidate: Dictionary, selectable: bool, taken: bool, taken_by_character_name: String) -> void:
	# 固定牌位包装器；尺寸始终等于正式111×148像素牌面，领取标签覆盖牌底而不改变换行计算。
	var wrapper: Control = Control.new()
	wrapper.custom_minimum_size = Vector2(111.0, 148.0)
	card_row.add_child(wrapper)
	# 正式卡牌视图；正面、牌背、公共只读牌和复制虚影都复用同一场景。
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 当前牌位实体 UID；用于连接点击信号并维护牌面映射。
	var card_uid: int = int(candidate.get("uid", -1))
	if bool(candidate.get("visible", false)):
		# 当前公开牌面数据；定义只用于名称、类别与插画表现，不参与选择合法性。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		# 当前卡牌静态定义；名称模式、类别颜色与插画均从该只读配置解析。
		var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
		card_view.configure(card_data, definition, false, selectable, taken)
	else:
		card_view.configure_back(card_uid, selectable)
	if selectable:
		card_view.pressed.connect(_on_card_pressed.bind(card_uid))
	if taken:
		card_view.modulate = taken_card_ghost_modulate
	wrapper.add_child(card_view)
	_card_views[card_uid] = card_view
	if not taken:
		return
	# 领取者武将名标签；空名称使用稳定占位，避免配置缺失时牌底完全没有归属提示。
	var owner_label: Label = Label.new()
	owner_label.position = TAKEN_CARD_LABEL_RECT.position
	owner_label.size = TAKEN_CARD_LABEL_RECT.size
	owner_label.z_index = 10
	owner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_label.text = taken_by_character_name if not taken_by_character_name.is_empty() else "已领取"
	owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	owner_label.add_theme_font_size_override("font_size", 13)
	_apply_owner_label_style(owner_label)
	wrapper.add_child(owner_label)
	_owner_labels.append(owner_label)


## 为公共牌领取者标签应用当前主题；该入口只处理配色与边距，不读取领取者数据。
func _apply_owner_label_style(owner_label: Label) -> void:
	owner_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	# 标签背景样式；使用1像素主题强调描边把归属信息与牌面底部文字区分开。
	var owner_style: StyleBoxFlat = BattleUIStyle.make_panel(taken_card_label_background_color, BattleUIStyle.get_color("accent"), 1, 3)
	owner_style.content_margin_left = 2.0
	owner_style.content_margin_top = 0.0
	owner_style.content_margin_right = 2.0
	owner_style.content_margin_bottom = 0.0
	owner_label.add_theme_stylebox_override("normal", owner_style)


## 切换一张候选牌的本地选择状态，并遵守请求最大选择数量。
func _on_card_pressed(card_uid: int) -> void:
	if not _selectable_card_uids.has(card_uid):
		return
	if _selected_card_uids.has(card_uid):
		_selected_card_uids.erase(card_uid)
	else:
		# 最大选择数；单选请求点击新牌时直接替换旧选择，减少额外取消步骤。
		var max_select: int = int(_choice_request.get("max_select", 1))
		if max_select == 1:
			_selected_card_uids.clear()
		if _selected_card_uids.size() < max_select:
			_selected_card_uids.append(card_uid)
	_refresh_selection_state()


## 同步牌面描边与确认按钮；只有数量位于请求范围内才能提交。
func _refresh_selection_state() -> void:
	for card_uid_variant: Variant in _card_views.keys():
		var card_uid: int = int(card_uid_variant)
		(_card_views[card_uid] as CardView).set_selected_state(_selected_card_uids.has(card_uid))
	# 数量约束；允许取消不代表空选择可以通过“确定”按钮提交。
	var min_select: int = int(_choice_request.get("min_select", 0))
	var max_select: int = int(_choice_request.get("max_select", 0))
	_confirm_button.disabled = _selected_card_uids.size() < min_select or _selected_card_uids.size() > max_select


## 发出当前选择结果；实际 UID 和请求序号仍会由 MatchController 权威校验。
func _on_confirm_pressed() -> void:
	choice_submitted.emit(int(_choice_request.get("request_id", -1)), _selected_card_uids.duplicate())


## 提交一个文字控制项；请求 ID 与稳定选项 ID 会继续经过 MatchController 和 ChoiceRequest 双重校验。
func _on_control_option_pressed(control_id: String) -> void:
	control_submitted.emit(int(_choice_request.get("request_id", -1)), control_id)


## 发出空选择作为明确放弃；组件不自行关闭，以提交成功后的状态为准。
func _on_cancel_pressed() -> void:
	choice_cancelled.emit(int(_choice_request.get("request_id", -1)))


## 调整居中选择框尺寸并同步左上位置；普通请求与公共展示共用同一节点，不重建遮罩或按钮。
func _set_frame_size(frame_size: Vector2) -> void:
	if _frame == null:
		return
	# 居中锚点与四边偏移同时写入，避免动态改尺寸后沿用左上角局部坐标而移出视口。
	_frame.anchor_left = 0.5
	_frame.anchor_top = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_bottom = 0.5
	_frame.offset_left = -frame_size.x * 0.5
	_frame.offset_top = -frame_size.y * 0.5
	_frame.offset_right = frame_size.x * 0.5
	_frame.offset_bottom = frame_size.y * 0.5


## 删除动态区域节点；重建请求时防止旧牌面和信号继续留在树中。
func _clear_container(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
