class_name CardSelectionPanel
extends Control

## 通用卡牌选择面板。响应、弃牌、目标区域选牌和展示牌选择都向该组件传入序列化请求。

## 用户确认选牌时发出请求序号与稳定实体牌 UID；组件不直接修改规则状态。
signal choice_submitted(request_id: int, selected_card_uids: Array[int])

## 用户在允许放弃的请求中取消选择时发出；桌面会转换为空 UID 的 choose_cards 动作。
signal choice_cancelled(request_id: int)

## 用户选择文字控制项时发出请求序号与稳定选项 ID；组件不解释该选项对应的技能效果。
signal control_submitted(request_id: int, control_id: String)

## 用户确认牌堆双行排序时发出完整UID顺序与牌堆顶行数量；组件不直接改写权威牌堆。
signal arrangement_submitted(request_id: int, ordered_card_uids: Array[int], top_count: int)

## 鼠标进入选择窗口内的明置牌时转发统一卡牌信息；内容与锚点完全来自正式 CardView。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开选择窗口内的牌面或窗口关闭时请求关闭统一信息框。
signal information_dismissed

## 正式卡牌视图场景；正面候选和牌背候选都复用同一111×148像素组件。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 通用模态选择层级；固定150高于手牌悬停100与拖拽101，保证五谷等窗口不会被底部牌面遮挡。
const MODAL_Z_INDEX: int = 150

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

## 目标武将名在区域选牌提示中的强调颜色；固定暖金色使目标归属在所有主题下保持可辨认，运行时通常无需动态修改。
const TARGET_CHARACTER_NAME_COLOR: Color = Color("e4c84f")

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

## 请求说明富文本标签；显示本次所需选择数量与操作目的，并可独立强调公开目标武将名。
var _prompt_label: RichTextLabel

## 分区内容容器；固定按手牌区、装备区、判定区和展示区顺序重建。
var _zone_container: VBoxContainer

## 分区滚动容器；普通卡牌选择请求共用纵向滚动，牌数较多时保持固定窗口尺寸。
var _zone_scroll: ScrollContainer

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

## 公共牌实体 UID 到领取者标签的映射；五谷后续领取更新只改写对应标签，不重复实例化整组牌面节点。
var _owner_labels_by_card_uid: Dictionary = {}

## 当前文字选项按钮集合；只用于主题刷新，请求切换或关闭时随动态内容一并清空。
var _control_option_buttons: Array[Button] = []

## 当前公共牌阵结构签名；牌位 UID 与牌面数据不变时复用现有节点，避免重复状态广播造成集中释放与重建。
var _public_layout_signature: int = 0

## 当前公共展示对应的本地请求 ID；同一请求重复刷新时保留玩家临时选择，切换选择者时恢复为空选择。
var _public_request_id: int = -1

## 牌堆排序请求中的牌堆顶行UID；数组顺序对应界面从左到右，也对应更早到更晚的摸牌顺序。
var _arrangement_top_uids: Array[int] = []

## 牌堆排序请求中的牌堆底行UID；数组顺序同样从左到右表示由更上方到更下方。
var _arrangement_bottom_uids: Array[int] = []

## 牌堆排序请求的候选快照映射；重建两行时按稳定UID恢复原牌面，不读取规则状态。
var _arrangement_candidates_by_uid: Dictionary = {}

## 当前牌堆顶排序行容器；拖动释放时只读取其全局矩形判断目标行，不保存任何规则对象。
var _arrangement_top_row: HFlowContainer

## 当前牌堆底排序行容器；与顶行共同提供跨行拖动的纯表现落点。
var _arrangement_bottom_row: HFlowContainer


## 创建可复用选择框的稳定节点结构；具体候选只在收到请求时动态生成。
func _ready() -> void:
	z_index = MODAL_Z_INDEX
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
	_prompt_label = RichTextLabel.new()
	_prompt_label.bbcode_enabled = true
	_prompt_label.scroll_active = false
	_prompt_label.custom_minimum_size = Vector2(0.0, 24.0)
	_prompt_label.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_prompt_label)
	# 候选滚动区；牌数较多时保持面板尺寸稳定并允许纵向查看全部区域。
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 可复用滚动容器引用；公共展示与普通选择切换尺寸时仍在原节点上修改，不重建选择框层级。
	_zone_scroll = scroll
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
	_prompt_label.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
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
	_owner_labels_by_card_uid.clear()
	_control_option_buttons.clear()
	_public_layout_signature = 0
	_public_request_id = -1
	_clear_container(_zone_container)
	_restore_standard_zone_scroll_behavior()
	_title_label.text = str(_choice_request.get("title", "选择卡牌"))
	_set_prompt_text(str(_choice_request.get("prompt", "请选择卡牌")), str(_choice_request.get("prompt_highlight", "")))
	if str(_choice_request.get("choice_type", "card")) == "arrange":
		_show_arrangement_request()
		visible = true
		return
	# 文字控制项请求；每个选项直接以独立按钮提交，底部确定按钮不重复制造二次确认。
	if str(_choice_request.get("choice_type", "card")) in ["control", "bool"]:
		# 控制请求可携带只读牌面；用于私下观看手牌后在同一窗口选择后续效果。
		var control_display_candidates: Array = ((_choice_request.get("context", {}) as Dictionary).get("display_candidates", []) as Array)
		_add_read_only_display_candidates(control_display_candidates)
		_add_control_options(_choice_request.get("control_options", []) as Array)
		_confirm_button.visible = false
		_cancel_button.visible = bool(_choice_request.get("allow_cancel", false))
		_action_row.visible = _cancel_button.visible
		visible = true
		return
	_confirm_button.visible = true
	# 按区域聚合候选；字典数组保持请求原始顺序，手牌牌背仍可逐张选择。
	var candidates_by_zone: Dictionary = {"hand":[], "equipment":[], "judgment":[], "processing":[], "discard_pile":[]}
	# 权威可选UID只取candidates；display_candidates可额外显示受保护或不满足类型条件的暗置牌。
	var selectable_candidate_uids: Array[int] = []
	for selectable_variant: Variant in _choice_request.get("candidates", []):
		var selectable_candidate: Dictionary = selectable_variant as Dictionary
		selectable_candidate_uids.append(int(selectable_candidate.get("uid", -1)))
	var display_candidates: Array = ((_choice_request.get("context", {}) as Dictionary).get("display_candidates", _choice_request.get("candidates", [])) as Array)
	for candidate_variant: Variant in display_candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		# 当前候选实体 UID；有效值会加入本地可选集合并用于点击校验。
		var candidate_uid: int = int(candidate.get("uid", -1))
		if candidate_uid >= 0 and selectable_candidate_uids.has(candidate_uid) and not _selectable_card_uids.has(candidate_uid):
			_selectable_card_uids.append(candidate_uid)
		var zone: String = str(candidate.get("zone", "processing"))
		if not candidates_by_zone.has(zone):
			candidates_by_zone[zone] = []
		(candidates_by_zone[zone] as Array).append(candidate)
	for zone: String in ["hand", "equipment", "judgment", "processing", "discard_pile"]:
		_add_zone_row(zone, candidates_by_zone.get(zone, []) as Array)
	_cancel_button.visible = bool(_choice_request.get("allow_cancel", false)) or int(_choice_request.get("min_select", 0)) == 0
	_action_row.visible = true
	_refresh_selection_state()
	visible = true


## 按标准区域顺序显示一组不可点击但保持完整亮度的牌面；空数组不占用窗口空间。
func _add_read_only_display_candidates(display_candidates: Array) -> void:
	# 按区域聚合的只读候选；当前私有观看主要使用hand，其他区域仍保持接口通用性。
	var candidates_by_zone: Dictionary = {"hand":[], "equipment":[], "judgment":[], "processing":[], "discard_pile":[]}
	for candidate_variant: Variant in display_candidates:
		# 当前只读候选副本；额外标记只影响本地亮度，不写回权威请求。
		var candidate: Dictionary = (candidate_variant as Dictionary).duplicate(true)
		candidate["read_only_full_brightness"] = true
		# 当前候选区域；未知区域统一归入展示区。
		var zone: String = str(candidate.get("zone", "processing"))
		if not candidates_by_zone.has(zone):
			candidates_by_zone[zone] = []
		(candidates_by_zone[zone] as Array).append(candidate)
	for zone: String in ["hand", "equipment", "judgment", "processing", "discard_pile"]:
		_add_zone_row(zone, candidates_by_zone.get(zone, []) as Array)


## 写入普通或带目标名称强调的提示文本；高亮字段只来自当前观察者已公开的武将名，不能承载规则状态。
func _set_prompt_text(prompt_text: String, highlighted_text: String = "") -> void:
	if highlighted_text.is_empty() or not prompt_text.contains(highlighted_text):
		_prompt_label.text = prompt_text
		return
	var highlighted_markup: String = "[color=#%s]%s[/color]" % [TARGET_CHARACTER_NAME_COLOR.to_html(false), highlighted_text]
	_prompt_label.text = prompt_text.replace(highlighted_text, highlighted_markup)


## 恢复普通请求的固定窗口与纵向滚动行为；公共展示关闭后和全部独立选牌请求均共用该配置。
func _restore_standard_zone_scroll_behavior() -> void:
	_set_frame_size(Vector2(panel_max_width, panel_max_height))
	if _zone_scroll == null:
		return
	_zone_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_zone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_zone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_zone_scroll.scroll_vertical = 0


## 显示一份跨多名玩家持续存在的公共选牌快照；只有传入有效本地请求时开放牌面与确认按钮。
func show_public_display(display_data: Dictionary, choice_request: Dictionary = {}) -> void:
	# 下一份公共牌阵结构签名；领取者、提示和当前请求不属于牌面结构，变化时只需原位刷新状态。
	var next_layout_signature: int = _get_public_layout_signature(display_data)
	# 下一份本地请求 ID；旁观状态使用-1，轮到本地玩家时使用权威请求序号。
	var next_request_id: int = int(choice_request.get("request_id", -1))
	if visible and not _public_display.is_empty() and _public_layout_signature == next_layout_signature and not _card_views.is_empty():
		_public_display = display_data.duplicate(true)
		_choice_request = choice_request.duplicate(true)
		if _public_request_id != next_request_id:
			_selected_card_uids.clear()
		_public_request_id = next_request_id
		_title_label.text = str(_public_display.get("title", "公共选牌"))
		_set_prompt_text(str(_public_display.get("prompt", "等待当前角色选择")))
		_refresh_public_selectable_card_uids()
		_refresh_public_slot_states(_public_display.get("slots", []) as Array)
		_refresh_public_action_row()
		_refresh_selection_state()
		return
	_public_display = display_data.duplicate(true)
	_choice_request = choice_request.duplicate(true)
	_selected_card_uids.clear()
	_card_views.clear()
	_selectable_card_uids.clear()
	_section_labels.clear()
	_owner_labels.clear()
	_owner_labels_by_card_uid.clear()
	_control_option_buttons.clear()
	_public_layout_signature = next_layout_signature
	_public_request_id = next_request_id
	_clear_container(_zone_container)
	_restore_standard_zone_scroll_behavior()
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
	_set_prompt_text(str(_public_display.get("prompt", "等待当前角色选择")))
	# 当前本地可选候选；只取有效 UID，公共牌位仍由完整 slots 数组决定固定顺序。
	_refresh_public_selectable_card_uids()
	_add_public_card_row(_public_display.get("slots", []) as Array)
	_refresh_public_slot_states(_public_display.get("slots", []) as Array)
	_refresh_public_action_row()
	_refresh_selection_state()
	visible = true


## 计算公共牌阵的稳定结构签名；只有固定牌位或原始牌面变化时才允许重建正式 CardView 节点。
func _get_public_layout_signature(display_data: Dictionary) -> int:
	# 参与结构比较的牌位数据；领取者归属与客户端补充名称只影响覆盖层状态，不改变牌面节点。
	var layout_slots: Array = []
	for slot_variant: Variant in display_data.get("slots", []) as Array:
		# 当前固定牌位；UID 与牌面快照共同决定是否可以安全复用节点。
		var display_slot: Dictionary = slot_variant as Dictionary
		layout_slots.append({"uid":int(display_slot.get("uid", -1)), "card_data":(display_slot.get("card_data", {}) as Dictionary).duplicate(true)})
	return hash([str(display_data.get("kind", "")), layout_slots, GameSettings.card_name_mode, GameSettings.ui_style_id])


## 从当前本地权威请求刷新公共牌可点击集合；旁观状态保持空集合且不会压暗仍未领取的公开牌面。
func _refresh_public_selectable_card_uids() -> void:
	_selectable_card_uids.clear()
	for candidate_variant: Variant in _choice_request.get("candidates", []) as Array:
		# 当前规则候选；已被其他角色取得的牌不会出现在该请求中。
		var candidate: Dictionary = candidate_variant as Dictionary
		# 当前规则候选实体 UID；只开放本次权威请求明确允许的固定牌位。
		var candidate_uid: int = int(candidate.get("uid", -1))
		if candidate_uid >= 0 and not _selectable_card_uids.has(candidate_uid):
			_selectable_card_uids.append(candidate_uid)
	for selected_uid: int in _selected_card_uids.duplicate():
		if not _selectable_card_uids.has(selected_uid):
			_selected_card_uids.erase(selected_uid)


## 原位刷新公共牌的领取虚影、归属标签与输入权限；固定牌位节点在整次五谷流程中持续复用。
func _refresh_public_slot_states(display_slots: Array) -> void:
	for slot_variant: Variant in display_slots:
		# 当前固定牌位；领取状态只改变表现，不删除或移动节点。
		var display_slot: Dictionary = slot_variant as Dictionary
		# 当前实体 UID；用于定位已经实例化的正式牌面与领取者标签。
		var card_uid: int = int(display_slot.get("uid", -1))
		# 当前领取者 ID；非负值表示该牌位只保留复制虚影。
		var taken_by_player_id: int = int(display_slot.get("taken_by_player_id", -1))
		# 当前正式牌面；结构签名一致时该实例会贯穿整次公共选择流程。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view != null and is_instance_valid(card_view):
			card_view.modulate = taken_card_ghost_modulate if taken_by_player_id >= 0 else Color.WHITE
			card_view.set_interactable_state(_selectable_card_uids.has(card_uid) and taken_by_player_id < 0)
		# 当前归属标签；所有公共牌位预先创建隐藏标签，领取时只更新文本与显隐。
		var owner_label: Label = _owner_labels_by_card_uid.get(card_uid) as Label
		if owner_label != null and is_instance_valid(owner_label):
			owner_label.text = str(display_slot.get("taken_by_character_name", "已领取")) if taken_by_player_id >= 0 else ""
			if taken_by_player_id >= 0 and owner_label.text.is_empty():
				owner_label.text = "已领取"
			owner_label.visible = taken_by_player_id >= 0


## 刷新公共窗口操作行；只有轮到本地玩家时显示确认及规则允许的取消按钮。
func _refresh_public_action_row() -> void:
	# 是否存在本地交互请求；旁观其他角色选择时只保留公共牌位，不显示确定或取消按钮。
	var has_interactive_request: bool = int(_choice_request.get("request_id", -1)) >= 0
	_action_row.visible = has_interactive_request
	_confirm_button.visible = true
	_cancel_button.visible = has_interactive_request and (bool(_choice_request.get("allow_cancel", false)) or int(_choice_request.get("min_select", 0)) == 0)


## 关闭并清理当前选择请求；规则层提交成功或重新开局时调用。
func close() -> void:
	information_dismissed.emit()
	visible = false
	_choice_request.clear()
	_public_display.clear()
	_selected_card_uids.clear()
	_card_views.clear()
	_selectable_card_uids.clear()
	_section_labels.clear()
	_owner_labels.clear()
	_owner_labels_by_card_uid.clear()
	_control_option_buttons.clear()
	_public_layout_signature = 0
	_public_request_id = -1
	_arrangement_top_uids.clear()
	_arrangement_bottom_uids.clear()
	_arrangement_candidates_by_uid.clear()
	_arrangement_top_row = null
	_arrangement_bottom_row = null
	_clear_container(_zone_container)
	_confirm_button.visible = true


## 初始化牌堆双行排序界面；全部候选默认位于牌堆顶行，并保持观看时从上到下的顺序。
func _show_arrangement_request() -> void:
	_arrangement_top_uids.clear()
	_arrangement_bottom_uids.clear()
	_arrangement_candidates_by_uid.clear()
	_selectable_card_uids.clear()
	for candidate_variant: Variant in _choice_request.get("candidates", []) as Array:
		# 当前排序候选；UID同时用于界面顺序和权威提交，不保存CardInstance引用。
		var candidate: Dictionary = candidate_variant as Dictionary
		var card_uid: int = int(candidate.get("uid", -1))
		if card_uid < 0 or _arrangement_candidates_by_uid.has(card_uid):
			continue
		_arrangement_candidates_by_uid[card_uid] = candidate.duplicate(true)
		_arrangement_top_uids.append(card_uid)
		_selectable_card_uids.append(card_uid)
	_cancel_button.visible = false
	_action_row.visible = true
	_confirm_button.visible = true
	_render_arrangement_rows()


## 按当前两个UID数组重建固定牌位；重建只发生在点击换行或拖动结束后，拖动过程中原牌节点持续跟随指针。
func _render_arrangement_rows() -> void:
	_clear_container(_zone_container)
	_card_views.clear()
	_section_labels.clear()
	_arrangement_top_row = _create_arrangement_row("牌堆顶", _arrangement_top_uids)
	_arrangement_bottom_row = _create_arrangement_row("牌堆底", _arrangement_bottom_uids)
	_refresh_selection_state()


## 创建牌堆排序中的一行；左侧牌代表该区域更上方的牌，空行仍保留可拖入高度。
func _create_arrangement_row(title: String, card_uids: Array[int]) -> HFlowContainer:
	# 单行分区；标题和牌位采用与普通选择相同的间距与主题色。
	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	section.custom_minimum_size = Vector2(0.0, 182.0)
	_zone_container.add_child(section)
	var label: Label = Label.new()
	label.text = title
	label.add_theme_color_override("font_color", BattleUIStyle.get_color("selection_section"))
	label.add_theme_font_size_override("font_size", 16)
	section.add_child(label)
	_section_labels.append(label)
	var row: HFlowContainer = HFlowContainer.new()
	row.custom_minimum_size = Vector2(0.0, 148.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	section.add_child(row)
	for card_uid: int in card_uids:
		_add_card_slot(row, _arrangement_candidates_by_uid.get(card_uid, {}) as Dictionary, true, false, "")
	return row


## 点击排序牌时在牌堆顶与牌堆底之间移动；新位置追加到目标行右侧，适合触屏快速操作。
func _toggle_arrangement_row(card_uid: int) -> void:
	if _arrangement_top_uids.has(card_uid):
		_arrangement_top_uids.erase(card_uid)
		_arrangement_bottom_uids.append(card_uid)
	elif _arrangement_bottom_uids.has(card_uid):
		_arrangement_bottom_uids.erase(card_uid)
		_arrangement_top_uids.append(card_uid)
	_render_arrangement_rows()


## 开始拖动排序牌；原CardView节点进入与手牌相同的直接跟随状态。
func _on_arrangement_drag_started(card_uid: int, pointer_global_position: Vector2) -> void:
	var card_view: CardView = _card_views.get(card_uid) as CardView
	if card_view != null and is_instance_valid(card_view):
		card_view.begin_hand_drag(pointer_global_position)


## 更新拖动排序牌的位置；布局容器中的固定包装器保持原尺寸，因此其余牌不会在拖动中跳位。
func _on_arrangement_drag_moved(card_uid: int, pointer_global_position: Vector2) -> void:
	var card_view: CardView = _card_views.get(card_uid) as CardView
	if card_view != null and is_instance_valid(card_view):
		card_view.move_hand_drag(pointer_global_position)


## 完成拖动排序；释放到任一牌面时按左右半区插入，释放到空白行时追加到该行末尾。
func _on_arrangement_drag_finished(card_uid: int, pointer_global_position: Vector2) -> void:
	var source_view: CardView = _card_views.get(card_uid) as CardView
	if source_view != null and is_instance_valid(source_view):
		source_view.end_hand_drag()
	# 命中的目标牌与插入方向；未命中时根据两行中心距离选择目标行。
	var target_uid: int = -1
	var insert_after_target: bool = true
	for candidate_uid_variant: Variant in _card_views.keys():
		var candidate_uid: int = int(candidate_uid_variant)
		if candidate_uid == card_uid:
			continue
		var candidate_view: CardView = _card_views.get(candidate_uid) as CardView
		if candidate_view != null and is_instance_valid(candidate_view) and candidate_view.get_global_rect().has_point(pointer_global_position):
			target_uid = candidate_uid
			insert_after_target = pointer_global_position.x >= candidate_view.get_global_rect().get_center().x
			break
	var destination_top: bool = _arrangement_top_uids.has(target_uid)
	if target_uid < 0:
		var top_center_y: float = _arrangement_top_row.get_global_rect().get_center().y if _arrangement_top_row != null else pointer_global_position.y
		var bottom_center_y: float = _arrangement_bottom_row.get_global_rect().get_center().y if _arrangement_bottom_row != null else pointer_global_position.y
		destination_top = absf(pointer_global_position.y - top_center_y) <= absf(pointer_global_position.y - bottom_center_y)
	_arrangement_top_uids.erase(card_uid)
	_arrangement_bottom_uids.erase(card_uid)
	var destination: Array[int] = _arrangement_top_uids if destination_top else _arrangement_bottom_uids
	if target_uid >= 0 and destination.has(target_uid):
		var insertion_index: int = destination.find(target_uid) + (1 if insert_after_target else 0)
		destination.insert(insertion_index, card_uid)
	else:
		destination.append(card_uid)
	_render_arrangement_rows()


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
	zone_label.text = {"hand":"手牌区", "equipment":"装备区", "judgment":"判定区", "processing":"展示区", "discard_pile":"弃牌堆"}.get(zone, zone)
	zone_label.add_theme_color_override("font_color", BattleUIStyle.get_color("selection_section"))
	zone_label.add_theme_font_size_override("font_size", 16)
	section.add_child(zone_label)
	_section_labels.append(zone_label)
	# 横向牌列；每张 Node2D 牌面由固定尺寸 Control 包装，避免动态内容改变布局。
	var card_row: HFlowContainer = HFlowContainer.new()
	card_row.add_theme_constant_override("h_separation", 8)
	card_row.add_theme_constant_override("v_separation", 8)
	card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		_add_card_slot(card_row, candidate, _selectable_card_uids.has(card_uid) and taken_by_player_id < 0, taken_by_player_id >= 0, str(display_slot.get("taken_by_character_name", "")), true)


## 创建一个正式卡牌牌位；可选牌连接输入，只读牌保留完整亮度，已领取牌叠加复制虚影与武将名。
## 公共牌会额外预建领取者标签，供后续状态广播原位刷新而不重建牌面。
func _add_card_slot(card_row: Container, candidate: Dictionary, selectable: bool, taken: bool, taken_by_character_name: String, create_owner_label: bool = false) -> void:
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
		# 不可选的展示牌必须传入禁用暗置；公共牌被领取时改由复制虚影表达，不能叠加禁用暗置而失去归属可读性。
		# 只读观看牌保持完整亮度；普通不可选保护牌仍使用禁用暗置，已领取公共牌继续由复制虚影表达。
		var dim_when_disabled: bool = not taken and not bool(candidate.get("read_only_full_brightness", false))
		card_view.configure(card_data, definition, false, selectable, dim_when_disabled)
	else:
		card_view.configure_back(card_uid, selectable)
	# 公共牌位即使首次以旁观状态创建，也预先连接点击信号；后续轮到本地玩家时只切换输入权限即可复用节点。
	if selectable or create_owner_label:
		card_view.pressed.connect(_on_card_pressed.bind(card_uid))
	if str(_choice_request.get("choice_type", "")) == "arrange":
		# 排序牌面开启通用拖动分区；点击可在两行间快速移动，拖动可同时改变所属行与位置。
		card_view.set_external_reorder_zone("pile_arrangement")
		card_view.hand_drag_started.connect(_on_arrangement_drag_started)
		card_view.hand_drag_moved.connect(_on_arrangement_drag_moved)
		card_view.hand_drag_finished.connect(_on_arrangement_drag_finished)
	if taken:
		card_view.modulate = taken_card_ghost_modulate
	wrapper.add_child(card_view)
	# 所有明置牌都转发统一悬停说明；只读、禁用和已领取虚影仍可查看，牌背不会由 CardView 发出信息。
	card_view.information_requested.connect(information_requested.emit)
	card_view.information_dismissed.connect(information_dismissed.emit)
	_card_views[card_uid] = card_view
	if not create_owner_label:
		return
	# 领取者武将名标签；空名称使用稳定占位，避免配置缺失时牌底完全没有归属提示。
	# 公共牌位始终预建并在未领取时隐藏，后续更新不再创建新节点。
	var owner_label: Label = Label.new()
	owner_label.position = TAKEN_CARD_LABEL_RECT.position
	owner_label.size = TAKEN_CARD_LABEL_RECT.size
	owner_label.z_index = 10
	owner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_label.text = taken_by_character_name if not taken_by_character_name.is_empty() else "已领取"
	owner_label.visible = taken
	owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	owner_label.add_theme_font_size_override("font_size", 13)
	_apply_owner_label_style(owner_label)
	wrapper.add_child(owner_label)
	_owner_labels.append(owner_label)
	_owner_labels_by_card_uid[card_uid] = owner_label


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
	if str(_choice_request.get("choice_type", "")) == "arrange":
		_toggle_arrangement_row(card_uid)
		return
	if not _get_dynamic_selectable_card_uids().has(card_uid):
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
	# 当前选择前缀下仍可组成合法完整组合的候选；不兼容牌立即压暗且停止接收输入。
	var dynamic_selectable_card_uids: Array[int] = _get_dynamic_selectable_card_uids()
	for card_uid_variant: Variant in _card_views.keys():
		# 当前牌面稳定UID；用于同时刷新选中描边与动态交互权限。
		var card_uid: int = int(card_uid_variant)
		# 当前正式牌面；公共只读虚影不在基础可选集合中，始终保持不可交互。
		var card_view: CardView = _card_views[card_uid] as CardView
		card_view.set_selected_state(_selected_card_uids.has(card_uid))
		card_view.set_interactable_state(dynamic_selectable_card_uids.has(card_uid))
	# 数量约束；允许取消不代表空选择可以通过“确定”按钮提交。
	if str(_choice_request.get("choice_type", "")) == "arrange":
		_confirm_button.disabled = _arrangement_top_uids.size() + _arrangement_bottom_uids.size() != _arrangement_candidates_by_uid.size()
		return
	var min_select: int = int(_choice_request.get("min_select", 0))
	var max_select: int = int(_choice_request.get("max_select", 0))
	_confirm_button.disabled = _selected_card_uids.size() < min_select or _selected_card_uids.size() > max_select


## 返回当前选择前缀下仍能组成至少一条权威合法组合的候选UID；单选请求保留全部候选以支持点击另一张牌直接替换选择。
func _get_dynamic_selectable_card_uids() -> Array[int]:
	# 动态可选结果；没有组合约束时与规则请求的基础候选完全一致。
	var result: Array[int] = []
	# 选择上下文；valid_card_combinations由技能规则预先枚举完整合法组合。
	var context: Dictionary = _choice_request.get("context", {}) as Dictionary
	# 完整合法组合数组；空数组表示该请求没有组合级约束。
	var valid_card_combinations: Array = context.get("valid_card_combinations", []) as Array
	# 最大选择数；单选请求例外地允许点击另一候选替换当前选择，多选请求达到上限后只保留已选牌可点击。
	var max_select: int = int(_choice_request.get("max_select", 0))
	for candidate_uid: int in _selectable_card_uids:
		if _selected_card_uids.has(candidate_uid):
			result.append(candidate_uid)
			continue
		if _selected_card_uids.size() >= max_select and max_select != 1:
			continue
		if valid_card_combinations.is_empty() or _has_compatible_card_combination(candidate_uid, valid_card_combinations, max_select == 1):
			result.append(candidate_uid)
	return result


## 判断把一张候选加入当前选择后，是否仍是某条完整合法组合的子集；单选替换时忽略旧选择。
func _has_compatible_card_combination(candidate_uid: int, valid_card_combinations: Array, replace_single_selection: bool = false) -> bool:
	# 待验证选择前缀；单选替换从空选择开始，多选保持点击顺序但组合匹配只检查成员集合。
	var tentative_selection: Array[int] = [] if replace_single_selection else _selected_card_uids.duplicate()
	tentative_selection.append(candidate_uid)
	for combination_variant: Variant in valid_card_combinations:
		# 当前完整合法组合；元素统一转换为整数UID。
		var combination: Array[int] = []
		for card_uid_variant: Variant in combination_variant as Array:
			combination.append(int(card_uid_variant))
		# 当前选择前缀是否全部包含于该完整组合；任一匹配即可继续选择。
		var contains_all_selected: bool = true
		for selected_uid: int in tentative_selection:
			if not combination.has(selected_uid):
				contains_all_selected = false
				break
		if contains_all_selected:
			return true
	return false


## 发出当前选择结果；实际 UID 和请求序号仍会由 MatchController 权威校验。
func _on_confirm_pressed() -> void:
	if str(_choice_request.get("choice_type", "")) == "arrange":
		var ordered_uids: Array[int] = _arrangement_top_uids.duplicate()
		ordered_uids.append_array(_arrangement_bottom_uids)
		arrangement_submitted.emit(int(_choice_request.get("request_id", -1)), ordered_uids, _arrangement_top_uids.size())
		return
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
