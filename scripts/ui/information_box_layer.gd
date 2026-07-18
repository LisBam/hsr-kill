class_name InformationBoxLayer
extends Control

## 牌桌统一信息框组件。组件集中管理目标旁悬浮信息与居中武将详情，不读取或修改任何权威对局状态。

## 居中武将详情显示状态变化信号；牌桌据此在离线模式申请或释放独立暂停令牌。
signal character_details_visibility_changed(visible: bool)

## 目标旁信息框固定宽度；默认340像素可完整容纳常见卡牌和技能说明，运行时通常无需动态修改。
@export_range(240.0, 520.0, 1.0) var hover_panel_width: float = 340.0

## 目标旁信息框与悬停目标之间的间距；默认10像素避免浮层遮挡当前目标，运行时通常无需动态修改。
@export_range(4.0, 32.0, 1.0) var hover_target_gap: float = 10.0

## 鼠标持续悬停后显示统一信息框前的等待时长；默认0.5秒可避免手牌、装备、技能与武将牌快速掠过时产生干扰，运行时通常无需动态修改。
@export_range(0.0, 3.0, 0.05) var hover_display_delay_seconds: float = 0.5

## 信息框与视口边缘之间的安全距离；默认12像素保证描边与阴影不会被窗口裁切，运行时通常无需动态修改。
@export_range(4.0, 48.0, 1.0) var viewport_margin: float = 12.0

## 居中武将详情面板的最大尺寸；默认760×440像素，宽度固定而高度会按技能内容收紧，超出440像素时保持滚动查看，运行时通常无需动态修改。
@export var character_panel_size: Vector2 = Vector2(760.0, 440.0)

## 居中武将详情面板的最小高度；默认226像素可容纳标题和0.78倍武将牌，短技能内容不会保留旧440像素大面积空白，运行时通常无需动态修改。
@export_range(180.0, 440.0, 1.0) var character_panel_minimum_height: float = 226.0

## 武将详情左侧牌面的缩放倍率；默认0.78与选将界面公开领袖武将牌一致，运行时通常无需动态修改。
@export_range(0.5, 1.0, 0.01) var character_card_scale: float = 0.78

## 武将详情左侧牌面区域宽度；默认180像素让缩小牌面居中且不挤压技能说明，运行时通常无需动态修改。
@export_range(140.0, 260.0, 1.0) var character_card_area_width: float = 180.0

## 武将详情标题栏固定高度；默认42像素容纳标题与关闭按钮，运行时通常无需动态修改。
@export_range(34.0, 64.0, 1.0) var character_header_height: float = 42.0

## 武将详情技能条目之间的垂直间距；默认12像素明确分隔技能名与下一项技能，运行时通常无需动态修改。
@export_range(4, 28, 1) var skill_entry_separation: int = 12

## 武将牌正式场景；详情框复用与牌桌和选将界面相同的牌面结构，避免维护第二套武将牌 UI。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 当前目标旁信息框对应的来源节点实例 ID；-1表示没有活动来源，旧来源离开时不能关闭新来源的信息。
var _hover_source_id: int = -1

## 当前目标旁信息框内容副本；主题切换时保留文字并只重绘样式，不重新查询业务数据。
var _hover_information: Dictionary = {}

## 正在等待显示的统一信息框来源节点实例 ID；-1表示当前没有延迟中的悬停请求。
var _pending_hover_source_id: int = -1

## 正在等待显示的统一信息框内容副本；延迟结束前不写入可见面板，避免快速掠过目标时闪现旧信息。
var _pending_hover_information: Dictionary = {}

## 正在等待显示的统一信息框锚点矩形；延迟结束后仍按原目标位置计算翻转与视口边界。
var _pending_hover_anchor_rect: Rect2 = Rect2()

## 统一信息框的单次延迟计时器；所有悬停来源共用该计时器，新的目标会替换尚未显示的旧请求。
var _hover_delay_timer: Timer

## 当前武将详情使用的公开玩家快照副本；只用于重绘详情牌面，不持有可修改的规则对象。
var _character_snapshot: Dictionary = {}

## 当前武将详情使用的静态武将定义副本；技能列表和插画路径都从该只读副本解析。
var _character_definition: Dictionary = {}

## 当前武将详情使用的势力定义副本；只提供牌面简称、完整名称与颜色。
var _faction_definition: Dictionary = {}

## 目标旁信息框面板；只显示当前悬停卡牌、装备或技能的名称与说明。
var _hover_panel: PanelContainer

## 目标旁信息框标题；显示当前目标名称并使用主题主文字色。
var _hover_title_label: Label

## 目标旁信息框副标题；显示花色点数、牌型、装备槽位或技能状态。
var _hover_subtitle_label: Label

## 目标旁信息框说明；自动换行展示完整规则文本。
var _hover_description_label: Label

## 武将详情全屏遮罩；拦截详情框之外的输入，并允许点击空白区域关闭详情。
var _character_shade: ColorRect

## 武将详情居中面板；固定承载标题栏、缩小武将牌和技能滚动区。
var _character_panel: PanelContainer

## 武将详情固定标题；显示“武将详情”且不随具体武将变化。
var _character_title_label: Label

## 武将详情关闭按钮；使用熟悉的叉号命令并在暂停状态下继续接收输入。
var _character_close_button: Button

## 武将详情左侧牌面区域；实际武将牌按0.78默认倍率在该区域居中。
var _character_card_area: Control

## 武将详情右侧技能滚动框；鼠标滚轮与右侧拖条共用该标准滚动入口。
var _character_skill_scroll: ScrollContainer

## 武将详情技能条目容器；每项按技能名一行、技能描述一段的顺序纵向排列。
var _character_skill_list: VBoxContainer

## 武将详情整体纵向内容容器；自动高度计算读取其标题与主体之间的实际主题间距。
var _character_content: VBoxContainer

## 当前详情左侧复用的正式武将牌；关闭或切换目标时释放并重新按快照构建。
var _character_card_view: PlayerTargetView

## 当前详情右侧已经创建的技能条目数量；只供界面回归与调试读取，不参与技能规则。
var _character_skill_entry_count: int = 0


## 初始化两类信息框节点；组件始终处理输入，确保离线暂停后仍能滚动和关闭详情。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hover_panel()
	_build_hover_delay_timer()
	_build_character_panel()
	refresh_ui_style()


## 在目标附近延迟显示统一悬浮信息；来源 ID 用于防止旧节点的离开信号关闭新目标信息。
func show_hover_information(information: Dictionary, anchor_rect: Rect2, source_id: int) -> void:
	if information.is_empty() or source_id < 0 or _character_shade.visible:
		return
	_cancel_pending_hover_information()
	# 已显示的旧目标信息必须立即退场；新的目标会在完整0.5秒悬停后再显示，避免内容跨目标残留。
	if _hover_panel.visible:
		_hover_source_id = -1
		_hover_information.clear()
		_hover_panel.visible = false
	_pending_hover_source_id = source_id
	_pending_hover_information = information.duplicate(true)
	_pending_hover_anchor_rect = anchor_rect
	if hover_display_delay_seconds <= 0.0:
		_show_pending_hover_information()
		return
	_hover_delay_timer.wait_time = hover_display_delay_seconds
	_hover_delay_timer.start()


## 关闭指定来源拥有的目标旁信息框；来源不匹配时保持当前新目标信息不变。
func hide_hover_information(source_id: int) -> void:
	if source_id == _pending_hover_source_id:
		_cancel_pending_hover_information()
	if source_id != _hover_source_id:
		return
	_hover_source_id = -1
	_hover_information.clear()
	_hover_panel.visible = false


## 在桌面中心显示指定角色的武将详情；左侧复用正式牌面，右侧只读取武将静态技能元数据。
func show_character_details(snapshot: Dictionary, character_definition: Dictionary, faction_definition: Dictionary = {}) -> void:
	if snapshot.is_empty() or character_definition.is_empty():
		return
	# 详情框打开前的可见状态；重复右键切换目标时不能重复申请离线暂停令牌。
	var was_visible: bool = _character_shade.visible
	_character_snapshot = snapshot.duplicate(true)
	_character_definition = character_definition.duplicate(true)
	_faction_definition = faction_definition.duplicate(true)
	_cancel_pending_hover_information()
	_hover_source_id = -1
	_hover_information.clear()
	_hover_panel.visible = false
	_character_shade.visible = true
	_character_panel.visible = true
	_render_character_card()
	_render_character_skills()
	_character_skill_scroll.scroll_vertical = 0
	_character_close_button.grab_focus()
	call_deferred("_resize_character_panel_to_content")
	if not was_visible:
		character_details_visibility_changed.emit(true)


## 关闭居中武将详情并释放其只读内容副本；牌桌收到状态信号后只释放详情框自己的暂停令牌。
func close_character_details() -> void:
	if not _character_shade.visible:
		return
	_character_shade.visible = false
	_character_panel.visible = false
	_character_snapshot.clear()
	_character_definition.clear()
	_faction_definition.clear()
	_clear_character_card()
	_clear_skill_entries()
	character_details_visibility_changed.emit(false)


## 返回目标旁信息框当前是否可见；供界面回归与调试验证统一悬停接口。
func is_hover_information_visible() -> bool:
	return _hover_panel != null and _hover_panel.visible


## 返回目标旁信息框当前标题；供界面回归确认显示内容来自实际悬停目标。
func get_hover_title_text() -> String:
	return _hover_title_label.text if _hover_title_label != null else ""


## 返回目标旁信息框当前副标题；供界面回归验证武将势力、性别与体力上限完整显示。
func get_hover_subtitle_text() -> String:
	return _hover_subtitle_label.text if _hover_subtitle_label != null else ""


## 返回目标旁信息框当前说明正文；供界面回归验证武将全部技能名称与描述。
func get_hover_description_text() -> String:
	return _hover_description_label.text if _hover_description_label != null else ""


## 返回居中武将详情当前是否可见；牌桌不应通过该查询推断暂停所有权。
func is_character_details_visible() -> bool:
	return _character_shade != null and _character_shade.visible


## 返回武将详情标题文本；固定值用于确认界面没有把玩家名或武将名误作窗口标题。
func get_character_title_text() -> String:
	return _character_title_label.text if _character_title_label != null else ""


## 返回武将详情标题标签；供界面回归验证标题文字相对整个详情面板严格居中。
func get_character_title_label() -> Label:
	return _character_title_label


## 返回武将详情实际创建的技能条目数量；数量仅对应静态武将技能列表。
func get_character_skill_entry_count() -> int:
	return _character_skill_entry_count


## 返回武将详情技能分隔线数量；正常数量应等于技能条目数减一。
func get_character_skill_separator_count() -> int:
	# 当前分隔线数量；只统计带稳定元数据标识的横线，不把技能条目或空状态文本计入。
	var separator_count: int = 0
	for child: Node in _character_skill_list.get_children():
		if child is HSeparator and child.has_meta("information_box_skill_separator"):
			separator_count += 1
	return separator_count


## 返回武将详情技能列表容器；供界面回归验证短内容的整体垂直居中位置。
func get_character_skill_list() -> VBoxContainer:
	return _character_skill_list


## 返回详情左侧武将牌当前缩放；没有活动详情时返回零向量，便于诊断牌面是否正确创建。
func get_character_card_scale() -> Vector2:
	return _character_card_view.scale if _character_card_view != null and is_instance_valid(_character_card_view) else Vector2.ZERO


## 返回武将技能滚动条；调用方可验证滚轮与可拖动条都由同一标准 ScrollContainer 提供。
func get_character_skill_scroll_bar() -> VScrollBar:
	return _character_skill_scroll.get_v_scroll_bar() if _character_skill_scroll != null else null


## 返回武将详情关闭按钮；供界面回归验证离线暂停时仍能通过真实 GUI 输入关闭详情。
func get_character_close_button() -> Button:
	return _character_close_button


## 按当前活动 UI 风格重绘信息框、文字、关闭按钮与滚动条；可见内容和滚动位置保持不变。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_character_shade.color = BattleUIStyle.get_color("shade", Color(0.0, 0.0, 0.0, 0.82))
	_hover_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 2, 6))
	_character_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("selection_panel"), BattleUIStyle.get_color("border"), 2, 6))
	_hover_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_hover_subtitle_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_hover_description_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_character_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_character_close_button.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_character_close_button.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("button_hover_font"))
	_character_close_button.add_theme_stylebox_override("normal", BattleUIStyle.make_button(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 1, 4))
	_character_close_button.add_theme_stylebox_override("hover", BattleUIStyle.make_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), 1, 4))
	_character_close_button.add_theme_stylebox_override("pressed", BattleUIStyle.make_button(BattleUIStyle.get_color("action_button").darkened(0.12), BattleUIStyle.get_color("accent"), 1, 4))
	_apply_scroll_bar_style(_character_skill_scroll.get_v_scroll_bar())
	if _character_card_view != null and is_instance_valid(_character_card_view):
		_character_card_view.refresh_ui_style()
	_refresh_skill_entry_styles()
	call_deferred("_resize_character_panel_to_content")


## 构建统一信息框的单次延迟计时器；计时器始终处理，离线暂停时仍能按真实悬停时长显示或取消信息。
func _build_hover_delay_timer() -> void:
	_hover_delay_timer = Timer.new()
	_hover_delay_timer.name = "HoverInformationDelayTimer"
	_hover_delay_timer.one_shot = true
	_hover_delay_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_hover_delay_timer.timeout.connect(_show_pending_hover_information)
	add_child(_hover_delay_timer)


## 取消尚未显示的悬停请求；来源离开、切换到新目标或打开武将详情时都会调用，避免旧计时器晚到后显示错误内容。
func _cancel_pending_hover_information() -> void:
	if _hover_delay_timer != null and is_instance_valid(_hover_delay_timer):
		_hover_delay_timer.stop()
	_pending_hover_source_id = -1
	_pending_hover_information.clear()
	_pending_hover_anchor_rect = Rect2()


## 把已完成等待的悬停请求写入可见面板；计时器只保存最后一次请求，因此此处不会显示已经离开的旧目标。
func _show_pending_hover_information() -> void:
	if _pending_hover_source_id < 0 or _pending_hover_information.is_empty() or _character_shade.visible:
		_cancel_pending_hover_information()
		return
	# 当前延迟请求的来源、内容与锚点；先复制再清空挂起状态，允许显示后的离开事件正常匹配活动来源。
	var source_id: int = _pending_hover_source_id
	var information: Dictionary = _pending_hover_information.duplicate(true)
	var anchor_rect: Rect2 = _pending_hover_anchor_rect
	_cancel_pending_hover_information()
	_hover_source_id = source_id
	_hover_information = information
	_hover_title_label.text = str(_hover_information.get("title", "信息"))
	_hover_subtitle_label.text = str(_hover_information.get("subtitle", ""))
	_hover_subtitle_label.visible = not _hover_subtitle_label.text.is_empty()
	_hover_description_label.text = str(_hover_information.get("description", "暂无说明。"))
	_hover_panel.visible = true
	_hover_panel.size = Vector2(hover_panel_width, 0.0)
	_hover_panel.reset_size()
	# 首次自动换行必须等待一个完整界面布局帧；此时 Label 已取得固定面板宽度，再测量高度不会把每个字符误当作独立行。
	_place_hover_panel_after_layout(anchor_rect, source_id)


## 等待自动换行标签取得固定宽度后再测量并放置信息框；来源已经离开时由后续来源校验安全忽略。
func _place_hover_panel_after_layout(anchor_rect: Rect2, source_id: int) -> void:
	await get_tree().process_frame
	_place_hover_panel(anchor_rect, source_id)


## 构建目标旁悬浮信息节点；所有输入保持穿透，浮层不会抢走原目标的鼠标离开判定。
func _build_hover_panel() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.name = "HoverInformationPanel"
	_hover_panel.visible = false
	_hover_panel.z_index = 100
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.custom_minimum_size = Vector2(hover_panel_width, 0.0)
	add_child(_hover_panel)
	# 悬浮信息纵向内容；固定顺序为标题、副标题和完整说明。
	var hover_content: VBoxContainer = VBoxContainer.new()
	hover_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_content.add_theme_constant_override("separation", 5)
	_hover_panel.add_child(hover_content)
	_hover_title_label = Label.new()
	_hover_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_title_label.add_theme_font_size_override("font_size", 17)
	_hover_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hover_content.add_child(_hover_title_label)
	_hover_subtitle_label = Label.new()
	_hover_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_subtitle_label.add_theme_font_size_override("font_size", 12)
	_hover_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_content.add_child(_hover_subtitle_label)
	_hover_description_label = Label.new()
	_hover_description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_description_label.add_theme_font_size_override("font_size", 14)
	_hover_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_content.add_child(_hover_description_label)


## 构建全屏武将详情节点；遮罩、面板与滚动框都使用始终处理模式支持离线暂停。
func _build_character_panel() -> void:
	_character_shade = ColorRect.new()
	_character_shade.name = "CharacterDetailsShade"
	_character_shade.visible = false
	_character_shade.z_index = 110
	_character_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_character_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_shade.gui_input.connect(_on_character_shade_gui_input)
	add_child(_character_shade)
	_character_panel = PanelContainer.new()
	_character_panel.name = "CharacterDetailsPanel"
	_character_panel.visible = false
	_character_panel.z_index = 111
	_character_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 详情框初始使用最小高度；打开后会根据实际技能条目自动收紧或增长到最大高度，避免首帧保留固定大空白。
	var initial_character_panel_size: Vector2 = Vector2(character_panel_size.x, minf(character_panel_minimum_height, character_panel_size.y))
	_character_panel.custom_minimum_size = initial_character_panel_size
	_character_panel.set_anchors_preset(Control.PRESET_CENTER)
	_character_panel.position = -initial_character_panel_size * 0.5
	_character_panel.size = initial_character_panel_size
	add_child(_character_panel)
	# 武将详情整体纵向内容；标题栏固定在上方，牌面与技能滚动区占据剩余高度。
	_character_content = VBoxContainer.new()
	_character_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_content.add_theme_constant_override("separation", 8)
	_character_panel.add_child(_character_content)
	# 武将详情标题行；标题扩展占据左侧空间，关闭按钮固定在最右侧。
	var character_header: HBoxContainer = HBoxContainer.new()
	character_header.name = "CharacterHeader"
	character_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_header.custom_minimum_size.y = character_header_height
	_character_content.add_child(character_header)
	# 标题栏左侧对称占位；宽度与右侧关闭按钮一致，保证标题中心与整个详情面板中心重合。
	var character_header_spacer: Control = Control.new()
	character_header_spacer.name = "LeadingSpacer"
	character_header_spacer.custom_minimum_size = Vector2(character_header_height, character_header_height)
	character_header_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_header.add_child(character_header_spacer)
	_character_title_label = Label.new()
	_character_title_label.name = "Title"
	_character_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_title_label.text = "武将详情"
	_character_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_character_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_character_title_label.add_theme_font_size_override("font_size", 22)
	character_header.add_child(_character_title_label)
	_character_close_button = Button.new()
	_character_close_button.name = "CloseButton"
	_character_close_button.text = "X"
	_character_close_button.tooltip_text = ""
	_character_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_character_close_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_character_close_button.focus_mode = Control.FOCUS_ALL
	_character_close_button.custom_minimum_size = Vector2(character_header_height, character_header_height)
	_character_close_button.pressed.connect(close_character_details)
	character_header.add_child(_character_close_button)
	# 武将详情主体横向内容；左侧只读牌面与右侧滚动技能区互不嵌套业务逻辑。
	var character_body: HBoxContainer = HBoxContainer.new()
	character_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_body.add_theme_constant_override("separation", 14)
	_character_content.add_child(character_body)
	_character_card_area = Control.new()
	_character_card_area.name = "CharacterCardArea"
	# 左侧区域高度稍后按缩放后的正式武将牌计算；不能继续使用固定440像素主体高度，否则短技能详情会留下大量空白。
	_character_card_area.custom_minimum_size = Vector2(character_card_area_width, 0.0)
	_character_card_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_body.add_child(_character_card_area)
	_character_skill_scroll = ScrollContainer.new()
	_character_skill_scroll.name = "SkillScroll"
	_character_skill_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_skill_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	character_body.add_child(_character_skill_scroll)
	_character_skill_list = VBoxContainer.new()
	_character_skill_list.name = "SkillList"
	_character_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_skill_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_skill_list.add_theme_constant_override("separation", skill_entry_separation)
	_character_skill_scroll.add_child(_character_skill_list)


## 根据来源矩形把悬浮信息放到目标右侧；右侧空间不足时翻转到左侧并限制在视口安全区内。
func _place_hover_panel(anchor_rect: Rect2, source_id: int) -> void:
	if source_id != _hover_source_id or not _hover_panel.visible:
		return
	_hover_panel.custom_minimum_size.x = hover_panel_width
	_hover_panel.size.x = hover_panel_width
	# 首次写入自动换行文本时，Label 可能在当前帧仍按零宽度计算最小高度；延迟到布局完成后重新按固定宽度测量，避免手牌说明被错误撑成大量空行。
	_hover_panel.reset_size()
	_hover_panel.size.x = hover_panel_width
	# 当前信息框实际尺寸；容器完成自动换行后使用该值进行视口边界计算。
	var panel_size: Vector2 = _hover_panel.size
	# 当前组件可用视口矩形；根控件与牌桌共享逻辑画布坐标。
	var available_rect: Rect2 = Rect2(Vector2(viewport_margin, viewport_margin), size - Vector2.ONE * viewport_margin * 2.0)
	# 默认信息框位置；优先显示在目标右侧并与目标顶边对齐。
	var target_position: Vector2 = Vector2(anchor_rect.end.x + hover_target_gap, anchor_rect.position.y)
	if target_position.x + panel_size.x > available_rect.end.x:
		target_position.x = anchor_rect.position.x - panel_size.x - hover_target_gap
	target_position.x = clampf(target_position.x, available_rect.position.x, maxf(available_rect.end.x - panel_size.x, available_rect.position.x))
	target_position.y = clampf(target_position.y, available_rect.position.y, maxf(available_rect.end.y - panel_size.y, available_rect.position.y))
	_hover_panel.position = target_position


## 复用正式武将牌场景渲染详情左侧牌面；隐藏对局角标和公开装备以匹配选将领袖牌表现。
func _render_character_card() -> void:
	_clear_character_card()
	_character_card_view = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	_character_card_area.add_child(_character_card_view)
	# 详情牌面快照；翻面只影响牌桌状态表现，详情必须继续显示已经公开的武将插画与名称。
	var details_snapshot: Dictionary = _character_snapshot.duplicate(true)
	details_snapshot["face_down"] = false
	_character_card_view.configure_snapshot(details_snapshot, _character_definition, false, _faction_definition)
	_character_card_view.set_match_overlays_visible(false)
	_character_card_view.set_public_equipment_visible(false)
	_character_card_view.set_operation_state(false)
	_character_card_view.scale = Vector2.ONE * character_card_scale
	# 左侧牌面高度是详情框主体的最低可用高度；短技能内容可围绕它收紧，但不能裁切正式武将牌。
	_character_card_area.custom_minimum_size.y = _character_card_view.card_size.y * character_card_scale
	call_deferred("_center_character_card")


## 在左侧固定区域内居中缩小武将牌；使用实际区域尺寸适配不同窗口和检查器参数。
func _center_character_card() -> void:
	if _character_card_view == null or not is_instance_valid(_character_card_view):
		return
	# 缩放后的武将牌尺寸；与选将界面一样只缩放正式牌面，不创建第二套几何参数。
	var scaled_card_size: Vector2 = _character_card_view.card_size * character_card_scale
	_character_card_view.position = (_character_card_area.size - scaled_card_size) * 0.5


## 按武将定义顺序重建右侧技能条目；每项固定先显示技能名，再显示完整技能描述。
func _render_character_skills() -> void:
	_clear_skill_entries()
	# 武将静态技能 ID 数组；空数组表示该武将没有可显示技能。
	var skill_ids: Array = _character_definition.get("skills", []) as Array
	if skill_ids.is_empty():
		# 无技能占位说明；只表达静态内容为空，不推断运行时技能状态。
		var empty_label: Label = Label.new()
		empty_label.text = "该武将没有可显示的技能。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
		_character_skill_list.add_child(empty_label)
		call_deferred("_refresh_character_skill_vertical_layout")
		return
	for skill_id_variant: Variant in skill_ids:
		# 当前技能稳定 ID；用于从数据库取得只读名称与原始说明。
		var skill_id: String = str(skill_id_variant)
		# 当前技能定义；缺失时显示可诊断占位内容，不让技能列表静默缺项。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能显示名；数据库缺失时回退稳定 ID，便于内容维护者定位问题。
		var skill_name: String = str(skill_definition.get("name", skill_id))
		# 当前技能显示说明；只替换完整书名号中的卡牌名称，其他原文保持不变。
		var skill_description: String = GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。")))
		if _character_skill_entry_count > 0:
			# 技能间横向分隔线；只出现在相邻技能之间，不在列表首尾绘制多余边界。
			var skill_separator: HSeparator = HSeparator.new()
			skill_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			skill_separator.set_meta("information_box_skill_separator", true)
			_apply_skill_separator_style(skill_separator)
			_character_skill_list.add_child(skill_separator)
		# 单个技能条目；使用无边框纵向布局，避免在详情面板内嵌套装饰卡片。
		var skill_entry: VBoxContainer = VBoxContainer.new()
		skill_entry.add_theme_constant_override("separation", 4)
		skill_entry.set_meta("information_box_skill_entry", true)
		_character_skill_list.add_child(skill_entry)
		# 技能名称行；完整名称独占一行并使用主题强调色。
		var skill_name_label: Label = Label.new()
		skill_name_label.text = "【%s】" % skill_name
		skill_name_label.add_theme_font_size_override("font_size", 17)
		skill_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
		skill_entry.add_child(skill_name_label)
		# 技能描述行；长文本允许自然换行，滚动框负责查看超出面板高度的全部内容。
		var skill_description_label: Label = Label.new()
		skill_description_label.text = skill_description
		skill_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill_description_label.add_theme_font_size_override("font_size", 14)
		skill_description_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		skill_entry.add_child(skill_description_label)
		_character_skill_entry_count += 1
	call_deferred("_refresh_character_skill_vertical_layout")


## 清理详情左侧武将牌；节点离树后不保留鼠标信号、快照或主题状态。
func _clear_character_card() -> void:
	if _character_card_view == null or not is_instance_valid(_character_card_view):
		_character_card_view = null
		return
	_character_card_area.remove_child(_character_card_view)
	_character_card_view.queue_free()
	_character_card_view = null
	_character_card_area.custom_minimum_size.y = 0.0


## 清理详情右侧技能条目并重置条目计数；滚动容器本身持续复用。
func _clear_skill_entries() -> void:
	if _character_skill_list == null:
		_character_skill_entry_count = 0
		return
	for child: Node in _character_skill_list.get_children():
		_character_skill_list.remove_child(child)
		child.queue_free()
	_character_skill_list.custom_minimum_size.y = 0.0
	_character_skill_entry_count = 0


## 刷新已经显示的技能条目颜色；节点元数据只标识布局用途，不包含任何技能业务状态。
func _refresh_skill_entry_styles() -> void:
	if _character_skill_list == null:
		return
	for entry_variant: Variant in _character_skill_list.get_children():
		# 当前技能条目或空技能标签；两种结构分别应用主题强调色和次级文字色。
		var entry_node: Node = entry_variant as Node
		if entry_node is VBoxContainer and entry_node.has_meta("information_box_skill_entry"):
			# 当前技能名称标签；条目创建顺序保证索引0始终为名称。
			var skill_name_label: Label = entry_node.get_child(0) as Label
			# 当前技能说明标签；条目创建顺序保证索引1始终为说明。
			var skill_description_label: Label = entry_node.get_child(1) as Label
			skill_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
			skill_description_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		elif entry_node is HSeparator and entry_node.has_meta("information_box_skill_separator"):
			_apply_skill_separator_style(entry_node as HSeparator)
		elif entry_node is Label:
			(entry_node as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))


## 依据左侧牌面和右侧技能内容收紧武将详情高度；短内容不再保留固定440像素空白，长内容仍被440像素最大高度和滚动框限制。
func _resize_character_panel_to_content() -> void:
	if _character_panel == null or _character_content == null or _character_skill_list == null or _character_card_area == null:
		return
	# 技能列表先解除上一次的视口填充高度，才能取得本次武将真实技能内容高度。
	_character_skill_list.custom_minimum_size.y = 0.0
	# 左侧正式武将牌的缩放后高度；详情卡牌尚未创建时回退为零，保证本方法对销毁阶段安全。
	var card_height: float = _character_card_view.card_size.y * character_card_scale if _character_card_view != null and is_instance_valid(_character_card_view) else 0.0
	_character_card_area.custom_minimum_size.y = card_height
	# 右侧全部技能条目的自然最小高度；ScrollContainer 只在最终高度超过上限时提供滚动，不参与规则状态。
	var skill_height: float = _character_skill_list.get_combined_minimum_size().y
	# 主体区域必须同时完整容纳缩小武将牌或短技能内容中较高的一方。
	var body_height: float = maxf(card_height, skill_height)
	# 标题与主体之间的实际容器间距；直接读取主题常量，避免把8像素重复硬编码到高度计算。
	var content_separation: float = float(_character_content.get_theme_constant("separation"))
	# 面板内边距；主题样式缺失时回退为零，默认样式由 BattleUIStyle 提供上下各7像素。
	var panel_vertical_margin: float = 0.0
	var panel_style: StyleBoxFlat = _character_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style != null:
		panel_vertical_margin = panel_style.content_margin_top + panel_style.content_margin_bottom
	# 配置的高度下限与上限；非法检查器组合自动夹紧，不允许最小高度反向撑开超过最大高度的详情框。
	var maximum_height: float = maxf(character_panel_size.y, 1.0)
	var minimum_height: float = minf(maxf(character_panel_minimum_height, 1.0), maximum_height)
	# 最终详情高度；标题、内容间隔、主体和主题内边距共同决定，短技能保持紧凑，长技能最多到固定上限。
	var desired_height: float = clampf(character_header_height + content_separation + body_height + panel_vertical_margin, minimum_height, maximum_height)
	var desired_size: Vector2 = Vector2(character_panel_size.x, desired_height)
	_character_panel.custom_minimum_size = desired_size
	# 重申中心锚点并直接更新四边偏移；PanelContainer 的最小尺寸刷新不能把详情框退回父节点原点。
	_character_panel.set_anchors_preset(Control.PRESET_CENTER)
	_character_panel.offset_left = -desired_size.x * 0.5
	_character_panel.offset_top = -desired_size.y * 0.5
	_character_panel.offset_right = desired_size.x * 0.5
	_character_panel.offset_bottom = desired_size.y * 0.5
	call_deferred("_center_character_card")
	call_deferred("_refresh_character_skill_vertical_layout")


## 让技能列表至少占满滚动视口；内容不足时 VBox 的居中对齐会整体上下居中，超出时仍按真实高度滚动。
func _refresh_character_skill_vertical_layout() -> void:
	if _character_skill_list == null or _character_skill_scroll == null:
		return
	_character_skill_list.custom_minimum_size.y = _character_skill_scroll.size.y


## 为技能间横线应用当前主题边框色；横线只承担内容分组，不创建额外卡片背景。
func _apply_skill_separator_style(separator: HSeparator) -> void:
	if separator == null:
		return
	# 当前主题横线样式；1像素线条保持清晰，同时不抢夺技能名称的强调层级。
	var separator_style: StyleBoxLine = StyleBoxLine.new()
	separator_style.color = BattleUIStyle.get_color("border")
	separator_style.thickness = 1
	separator_style.vertical = false
	separator.add_theme_stylebox_override("separator", separator_style)


## 为技能滚动条应用当前主题语义色；拖条、悬停和按下状态均保持可辨识对比度。
func _apply_scroll_bar_style(scroll_bar: VScrollBar) -> void:
	if scroll_bar == null:
		return
	scroll_bar.custom_minimum_size.x = 12.0
	scroll_bar.add_theme_stylebox_override("scroll", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 1, 4))
	scroll_bar.add_theme_stylebox_override("grabber", BattleUIStyle.make_panel(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), 1, 4))
	scroll_bar.add_theme_stylebox_override("grabber_highlight", BattleUIStyle.make_panel(BattleUIStyle.get_color("action_button").lightened(0.10), BattleUIStyle.get_color("accent").lightened(0.08), 1, 4))
	scroll_bar.add_theme_stylebox_override("grabber_pressed", BattleUIStyle.make_panel(BattleUIStyle.get_color("action_button").darkened(0.10), BattleUIStyle.get_color("accent"), 1, 4))


## 点击武将详情遮罩空白区域时关闭详情；面板自身位于更高层级并会截断内部输入。
func _on_character_shade_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 当前鼠标按键事件；左键或右键释放都关闭详情，滚轮事件继续交给技能滚动框。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			close_character_details()
			accept_event()


## 处理详情框关闭快捷键；始终处理模式保证离线暂停后 Esc 与右键仍可恢复对局。
func _unhandled_input(event: InputEvent) -> void:
	if not is_character_details_visible():
		return
	if event is InputEventKey:
		# 当前键盘事件；只在首次按下 Esc 时关闭，忽略按键重复。
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			close_character_details()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		# 当前未被详情面板消费的鼠标事件；右键释放等价于点击关闭按钮。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			close_character_details()
			get_viewport().set_input_as_handled()
