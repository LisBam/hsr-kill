class_name CardSelectionPanel
extends Control

## 通用卡牌选择面板。响应、弃牌、目标区域选牌和展示牌选择都向该组件传入序列化请求。

## 用户确认选牌时发出请求序号与稳定实体牌 UID；组件不直接修改规则状态。
signal choice_submitted(request_id: int, selected_card_uids: Array[int])

## 用户在允许放弃的请求中取消选择时发出；桌面会转换为空 UID 的 choose_cards 动作。
signal choice_cancelled(request_id: int)

## 正式卡牌视图场景；正面候选和牌背候选都复用同一111×148像素组件。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 选择面板最大宽度；默认920像素可同时容纳多个牌面，运行时通常无需修改。
@export_range(520.0, 1180.0, 1.0) var panel_max_width: float = 920.0

## 选择面板最大高度；默认590像素确保1280×720视口仍保留外侧边距，运行时通常无需修改。
@export_range(360.0, 680.0, 1.0) var panel_max_height: float = 590.0

## 当前请求只读快照；空字典表示面板已关闭。
var _choice_request: Dictionary = {}

## 当前按点击顺序选择的实体牌 UID；提交前只存在于界面临时状态。
var _selected_card_uids: Array[int] = []

## 实体牌 UID 到正式卡牌视图的映射；用于同步金色选中描边。
var _card_views: Dictionary = {}

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


## 创建可复用选择框的稳定节点结构；具体候选只在收到请求时动态生成。
func _ready() -> void:
	z_index = 45
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.01, 0.008, 0.006, 0.78)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_frame = PanelContainer.new()
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.position = -Vector2(panel_max_width, panel_max_height) * 0.5
	_frame.size = Vector2(panel_max_width, panel_max_height)
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(Color("201b18"), Color("c5a05a"), 2, 6))
	add_child(_frame)
	# 选择框主列；标题、提示、滚动分区和操作按钮从上到下排列。
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_frame.add_child(content)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color("efd07c"))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_title_label)
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", Color("d7d0c2"))
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
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 10)
	content.add_child(action_row)
	_confirm_button = Button.new()
	_confirm_button.text = "确定"
	_confirm_button.custom_minimum_size = Vector2(132.0, 40.0)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	action_row.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = "不选择"
	_cancel_button.custom_minimum_size = Vector2(96.0, 40.0)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	action_row.add_child(_cancel_button)
	visible = false


## 显示一条规则层选择请求；重复调用会完整替换旧候选和本地临时选择。
func show_request(choice_request: Dictionary) -> void:
	_choice_request = choice_request.duplicate(true)
	_selected_card_uids.clear()
	_card_views.clear()
	_clear_container(_zone_container)
	_title_label.text = str(_choice_request.get("title", "选择卡牌"))
	_prompt_label.text = str(_choice_request.get("prompt", "请选择卡牌"))
	# 按区域聚合候选；字典数组保持请求原始顺序，手牌牌背仍可逐张选择。
	var candidates_by_zone: Dictionary = {"hand":[], "equipment":[], "judgment":[], "processing":[]}
	for candidate_variant: Variant in _choice_request.get("candidates", []):
		var candidate: Dictionary = candidate_variant as Dictionary
		var zone: String = str(candidate.get("zone", "processing"))
		if not candidates_by_zone.has(zone):
			candidates_by_zone[zone] = []
		(candidates_by_zone[zone] as Array).append(candidate)
	for zone: String in ["hand", "equipment", "judgment", "processing"]:
		_add_zone_row(zone, candidates_by_zone.get(zone, []) as Array)
	_cancel_button.visible = bool(_choice_request.get("allow_cancel", false)) or int(_choice_request.get("min_select", 0)) == 0
	_refresh_selection_state()
	visible = true


## 关闭并清理当前选择请求；规则层提交成功或重新开局时调用。
func close() -> void:
	visible = false
	_choice_request.clear()
	_selected_card_uids.clear()
	_card_views.clear()
	_clear_container(_zone_container)


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
	zone_label.add_theme_color_override("font_color", Color("9ed3c3"))
	zone_label.add_theme_font_size_override("font_size", 16)
	section.add_child(zone_label)
	# 横向牌列；每张 Node2D 牌面由固定尺寸 Control 包装，避免动态内容改变布局。
	var card_row: HFlowContainer = HFlowContainer.new()
	card_row.add_theme_constant_override("h_separation", 8)
	card_row.add_theme_constant_override("v_separation", 8)
	section.add_child(card_row)
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		var wrapper: Control = Control.new()
		wrapper.custom_minimum_size = Vector2(111.0, 148.0)
		card_row.add_child(wrapper)
		var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		var card_uid: int = int(candidate.get("uid", -1))
		if bool(candidate.get("visible", false)):
			var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
			var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
			card_view.configure(card_data, definition, false, true)
		else:
			card_view.configure_back(card_uid, true)
		card_view.pressed.connect(_on_card_pressed.bind(card_uid))
		wrapper.add_child(card_view)
		_card_views[card_uid] = card_view


## 切换一张候选牌的本地选择状态，并遵守请求最大选择数量。
func _on_card_pressed(card_uid: int) -> void:
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


## 发出空选择作为明确放弃；组件不自行关闭，以提交成功后的状态为准。
func _on_cancel_pressed() -> void:
	choice_cancelled.emit(int(_choice_request.get("request_id", -1)))


## 删除动态区域节点；重建请求时防止旧牌面和信号继续留在树中。
func _clear_container(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
