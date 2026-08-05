class_name InformationBoxLayer
extends Control

## 牌桌统一信息框组件。组件集中管理目标旁悬浮信息与居中武将详情，不读取或修改任何权威对局状态。

## 居中武将详情显示状态变化信号；牌桌据此在离线模式申请或释放独立暂停令牌。
signal character_details_visibility_changed(visible: bool)

## 目标旁信息框的内容测量基准宽度；默认340像素用于估算文字换行后的所需高度，最终宽度会按4:3目标比例自动收缩或扩展，运行时通常无需动态修改。
@export_range(240.0, 520.0, 1.0) var hover_panel_width: float = 340.0

## 目标旁信息框的最小宽度；默认240像素让短说明保持紧凑，同时给标题、副标题和正文保留可读换行宽度，运行时通常无需动态修改。
@export_range(160.0, 420.0, 1.0) var hover_panel_minimum_width: float = 240.0

## 目标旁信息框的最大宽度；默认520像素限制长技能说明横向扩张，超出时优先增加高度以保留完整文字，运行时通常无需动态修改。
@export_range(280.0, 720.0, 1.0) var hover_panel_maximum_width: float = 520.0

## 目标旁信息框优先保持的宽高比例；默认4:3使短中等长度说明呈稳定长方形，正文超过比例高度时以完整显示内容为优先，运行时通常无需动态修改。
@export_range(1.0, 3.0, 0.01) var hover_panel_aspect_ratio: float = 4.0 / 3.0

## 目标旁信息框允许的最小宽高比；默认0.8避免长说明在尚有横向空间时变成过窄高条，运行时通常无需动态修改。
@export_range(0.4, 1.5, 0.01) var hover_panel_minimum_aspect_ratio: float = 0.8

## 目标旁信息框允许的最大宽高比；默认2.2避免短说明只占一条过宽面板，运行时通常无需动态修改。
@export_range(1.2, 4.0, 0.01) var hover_panel_maximum_aspect_ratio: float = 2.2

## 目标旁信息框比例搜索的单次宽度步长；默认20像素在测量稳定性与尺寸精度之间取平衡，运行时通常无需动态修改。
@export_range(4.0, 80.0, 1.0) var hover_panel_width_adjustment_step: float = 20.0

## 目标旁信息框保持最小宽度时允许的可见字符总数；默认24个字符让短说明保持紧凑，运行时通常无需动态修改。
@export_range(8, 80, 1) var hover_panel_compact_text_character_count: int = 24

## 超出紧凑字符数后每个字符增加的目标宽度；默认1像素用于补偿RichTextLabel富文本高度延迟更新，运行时通常无需动态修改。
@export_range(0.1, 4.0, 0.1) var hover_panel_width_per_extra_text_character: float = 1.0

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

## 武将详情右侧技能区到面板右边框的额外留白；默认24像素使滚动条与文字不贴近边缘，运行时可通过检查器调整。
@export_range(0.0, 64.0, 1.0) var character_skill_right_margin: float = 24.0

## 武将详情标题栏固定高度；默认42像素容纳标题与关闭按钮，运行时通常无需动态修改。
@export_range(34.0, 64.0, 1.0) var character_header_height: float = 42.0

## 武将详情技能条目之间的垂直间距；默认12像素明确分隔技能名与下一项技能，运行时通常无需动态修改。
@export_range(4, 28, 1) var skill_entry_separation: int = 12

## 顶部提醒横幅的默认停留秒数；默认4秒足够阅读一句提醒，调用方可为单条提醒传入独立时长。
@export_range(1.0, 15.0, 0.5) var notice_hold_seconds: float = 4.0

## 顶部提醒横幅的淡出时长；默认0.5秒平滑消失，横幅补间始终以始终处理模式运行以兼容对局暂停。
@export_range(0.1, 2.0, 0.05) var notice_fade_seconds: float = 0.5

## 顶部提醒横幅与视口上边缘的距离；默认56像素避开顶部信息条，运行时通常无需动态修改。
@export_range(8.0, 200.0, 1.0) var notice_top_margin: float = 56.0

## 武将牌正式场景；详情框复用与牌桌和选将界面相同的牌面结构，避免维护第二套武将牌 UI。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 单次信息框宽度搜索的最大迭代数；32次足以覆盖默认240至520像素范围，并防止异常检查器参数导致无界布局计算。
const MAX_HOVER_WIDTH_SEARCH_ITERATIONS: int = 32

## 当前目标旁信息框对应的来源节点实例 ID；-1表示没有活动来源，旧来源离开时不能关闭新来源的信息。
var _hover_source_id: int = -1

## 当前目标旁信息框内容副本；主题切换时保留文字并只重绘样式，不重新查询业务数据。
var _hover_information: Dictionary = {}

## 当前已显示信息框的来源锚点矩形；名称模式改变文字长度后复用该矩形重新测量和定位。
var _hover_anchor_rect: Rect2 = Rect2()

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

## 目标旁信息框说明；自动换行展示完整规则文本，并支持轮回节分段字体颜色。
var _hover_description_label: SkillDescriptionView

## 目标旁信息框说明容器；普通说明使用单个标签，武将资料可按技能拆分为强调名称与普通描述。
var _hover_description_container: VBoxContainer

## 当前武将悬停资料创建的技能名称标签；统一使用与右键详情技能名相同的主题强调色。
var _hover_skill_name_labels: Array[Label] = []

## 当前武将悬停资料创建的技能说明视图；主题切换时保留轮回节高亮状态并重绘颜色。
var _hover_skill_description_labels: Array[SkillDescriptionView] = []

## 当前悬停内容异步布局的代次；每次替换或关闭内容都会递增，旧布局协程不得显示新请求或旧位置。
var _hover_layout_generation: int = 0

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

## 武将详情右侧技能区外层边距容器；只负责保留可配置的右侧内边距，不参与滚动内容或技能数据。
var _character_skill_margin: MarginContainer

## 武将详情技能条目容器；每项按技能名一行、技能描述一段的顺序纵向排列。
var _character_skill_list: VBoxContainer

## 武将详情技能列表底部对称留白；高度由标题栏、主体间距和面板上下边距动态推导，不写入玩法数据。
var _character_skill_bottom_spacer: Control

## 武将详情整体纵向内容容器；自动高度计算读取其标题与主体之间的实际主题间距。
var _character_content: VBoxContainer

## 当前详情左侧复用的正式武将牌；关闭或切换目标时释放并重新按快照构建。
var _character_card_view: PlayerTargetView

## 当前详情右侧已经创建的技能条目数量；只供界面回归与调试读取，不参与技能规则。
var _character_skill_entry_count: int = 0

## 当前详情右侧已经创建的机缘历史条目数量；只供界面回归与调试读取，不参与机缘规则。
var _character_opportunity_entry_count: int = 0

## 顶部提醒横幅面板；自动修复等全局提醒复用同一节点，不遮挡任何输入。
var _notice_panel: PanelContainer

## 顶部提醒横幅文字标签；多条提醒直接覆盖文本并重置停留计时。
var _notice_label: Label

## 顶部提醒横幅当前活动补间；新提醒到来时先终止旧补间，避免旧淡出提前隐藏新提醒。
var _notice_tween: Tween


## 初始化两类信息框节点；组件始终处理输入，确保离线暂停后仍能滚动和关闭详情。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hover_panel()
	_build_hover_delay_timer()
	_build_character_panel()
	_build_notice_banner()
	refresh_ui_style()


## 在目标附近延迟显示统一悬浮信息；来源 ID 用于防止旧节点的离开信号关闭新目标信息。
func show_hover_information(information: Dictionary, anchor_rect: Rect2, source_id: int) -> void:
	if information.is_empty() or source_id < 0 or _character_shade.visible:
		return
	# 当前请求内容副本；后续幂等比较和延迟显示都只使用副本，避免来源在等待期间修改原字典。
	# 名称解析同样基于新副本执行，不会回写来源持有的数据。
	# 当前请求内容副本；先按当前名称模式解析括号牌名，再用于幂等比较和延迟显示。
	var information_copy: Dictionary = _resolve_information_card_names(information)
	if source_id == _pending_hover_source_id and _pending_hover_information == information_copy:
		# 同一来源在等待期间重复发送相同资料时只更新锚点，不重启0.5秒计时器。
		_pending_hover_anchor_rect = anchor_rect
		return
	if source_id == _hover_source_id and _hover_information == information_copy and _hover_panel.visible:
		_hover_anchor_rect = anchor_rect
		# 公开快照刷新会重复发送相同武将资料；完成首帧布局后只校正位置，测量期间则保持透明等待原布局收尾。
		# 补充：稳定内容只读取既有宽高并重新定位，不再进入会改变自动换行边界的测量函数。
		if _hover_panel.modulate.a > 0.0:
			_reposition_hover_panel(anchor_rect, source_id, _hover_layout_generation)
		return
	# 同一逻辑资料主题；只有显式稳定主题一致时允许跳过悬停延迟，装备与武将资料切换仍按新目标重新等待。
	var current_refresh_subject: String = str(_hover_information.get("refresh_subject", ""))
	var incoming_refresh_subject: String = str(information_copy.get("refresh_subject", ""))
	if source_id == _hover_source_id and _hover_panel.visible and not current_refresh_subject.is_empty() and current_refresh_subject == incoming_refresh_subject:
		# 同一悬停来源的公开资料发生变化；已获得技能等更新必须原位立即替换内容，不重新等待0.5秒。
		_cancel_pending_hover_information()
		_hover_layout_generation += 1
		# 当前刷新布局代次；新状态再次到达时会使旧的异步测量安全失效。
		var refresh_layout_generation: int = _hover_layout_generation
		_hover_information = information_copy
		_hover_anchor_rect = anchor_rect
		_hover_title_label.text = str(_hover_information.get("title", "信息"))
		_hover_subtitle_label.text = str(_hover_information.get("subtitle", ""))
		_hover_subtitle_label.visible = not _hover_subtitle_label.text.is_empty()
		_render_hover_description()
		_refresh_hover_text_styles()
		# 内容先在原位置即时更新，再异步重测最终宽高；不会隐藏旧面板或闪回默认位置。
		_hover_panel.custom_minimum_size = Vector2(hover_panel_width, 0.0)
		_hover_panel.size = Vector2(hover_panel_width, 0.0)
		_hover_panel.reset_size()
		_place_hover_panel_after_layout(anchor_rect, source_id, refresh_layout_generation)
		return
	_cancel_pending_hover_information()
	# 已显示的旧目标信息必须立即退场；新的目标会在完整0.5秒悬停后再显示，避免内容跨目标残留。
	if _hover_panel.visible:
		_hover_layout_generation += 1
		_hover_source_id = -1
		_hover_information.clear()
		_hover_anchor_rect = Rect2()
		_hover_panel.visible = false
		_hover_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_pending_hover_source_id = source_id
	_pending_hover_information = information_copy
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
	_hover_anchor_rect = Rect2()
	_hover_layout_generation += 1
	_hover_panel.visible = false
	_hover_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)


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
	_hover_anchor_rect = Rect2()
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


## 使用最新公开快照原位刷新已经打开的同一角色详情；不会重复开关面板或改变离线暂停令牌所有权。
func refresh_character_details(snapshot: Dictionary, character_definition: Dictionary, faction_definition: Dictionary = {}) -> void:
	if not is_character_details_visible() or snapshot.is_empty() or character_definition.is_empty():
		return
	# 当前详情角色与新快照角色；稳定ID不同表示详情仍属于另一名角色，状态广播不能擅自切换目标。
	var current_player_id: int = int(_character_snapshot.get("player_id", -1))
	var refreshed_player_id: int = int(snapshot.get("player_id", -2))
	if current_player_id != refreshed_player_id:
		return
	if _character_snapshot == snapshot and _character_definition == character_definition and _faction_definition == faction_definition:
		return
	# 当前滚动位置；技能或机缘内容变化后尽量保持阅读位置，最终仍由标准滚动范围自动夹紧。
	var previous_scroll_vertical: int = _character_skill_scroll.scroll_vertical
	_character_snapshot = snapshot.duplicate(true)
	_character_definition = character_definition.duplicate(true)
	_faction_definition = faction_definition.duplicate(true)
	_render_character_card()
	_render_character_skills()
	_character_skill_scroll.scroll_vertical = previous_scroll_vertical
	call_deferred("_resize_character_panel_to_content")


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
	return _hover_panel != null and _hover_panel.visible and _hover_panel.modulate.a > 0.0


## 返回目标旁信息框当前标题；供界面回归确认显示内容来自实际悬停目标。
func get_hover_title_text() -> String:
	return _hover_title_label.text if _hover_title_label != null else ""


## 返回目标旁信息框当前副标题；供界面回归验证武将势力、性别与体力上限完整显示。
func get_hover_subtitle_text() -> String:
	return _hover_subtitle_label.text if _hover_subtitle_label != null else ""


## 返回目标旁信息框当前说明正文；供界面回归验证武将全部技能名称与描述。
func get_hover_description_text() -> String:
	return _hover_description_label.get_plain_description() if _hover_description_label != null else ""


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


## 返回武将详情实际创建的已获得机缘条目数量；非机缘模式固定为0。
func get_character_opportunity_entry_count() -> int:
	return _character_opportunity_entry_count


## 返回当前打开详情对应的稳定玩家ID；未打开时返回-1，牌桌只用它查找最新公开快照。
func get_character_details_player_id() -> int:
	return int(_character_snapshot.get("player_id", -1)) if is_character_details_visible() else -1


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


## 在视口顶部居中显示一条全局提醒横幅；自动修复与待办提醒复用本入口，横幅不拦截任何鼠标输入。
## hold_seconds 传入0或负数时使用检查器默认停留时长；对局暂停期间横幅仍会正常显示与淡出。
func show_notice(message: String, hold_seconds: float = -1.0) -> void:
	if not is_node_ready() or message.is_empty():
		return
	# 本条提醒实际停留时长；调用方未指定时回退检查器默认值。
	var resolved_hold_seconds: float = hold_seconds if hold_seconds > 0.0 else notice_hold_seconds
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_label.text = message
	_notice_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_notice_panel.visible = true
	# 提醒淡出补间；始终处理模式保证机缘选择或日志暂停冻结场景树时提醒仍能按时消失。
	_notice_tween = create_tween()
	_notice_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_notice_tween.tween_interval(resolved_hold_seconds)
	_notice_tween.tween_property(_notice_panel, "modulate:a", 0.0, notice_fade_seconds)
	_notice_tween.tween_callback(func() -> void: _notice_panel.visible = false)


## 返回顶部提醒横幅当前是否可见；供界面回归测试断言提醒确实展示，不暴露内部节点结构。
func is_notice_visible() -> bool:
	return _notice_panel != null and is_instance_valid(_notice_panel) and _notice_panel.visible


## 返回顶部提醒横幅当前文字；供界面回归测试断言提醒内容，空字符串表示尚未显示过提醒。
func get_notice_text() -> String:
	return _notice_label.text if _notice_label != null and is_instance_valid(_notice_label) else ""


## 创建顶部提醒横幅节点；横幅默认隐藏，位于全部信息框之上且不参与命中测试。
func _build_notice_banner() -> void:
	_notice_panel = PanelContainer.new()
	_notice_panel.name = "NoticeBanner"
	_notice_panel.visible = false
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶部居中锚点；面板尺寸随文字自适应并向两侧均匀扩展。
	_notice_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice_panel.position.y = notice_top_margin
	add_child(_notice_panel)
	_notice_label = Label.new()
	_notice_label.name = "NoticeLabel"
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_panel.add_child(_notice_label)


## 按当前活动 UI 风格重绘信息框、文字、关闭按钮与滚动条；可见内容和滚动位置保持不变。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_character_shade.color = BattleUIStyle.get_color("shade", Color(0.0, 0.0, 0.0, 0.82))
	_hover_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 2, 6))
	_character_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("selection_panel"), BattleUIStyle.get_color("border"), 2, 6))
	if _notice_panel != null and is_instance_valid(_notice_panel):
		_notice_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("selection_panel"), BattleUIStyle.get_color("accent"), 2, 6))
		_notice_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_refresh_hover_text_styles()
	_character_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_character_close_button.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_character_close_button.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("button_hover_font"))
	_character_close_button.add_theme_stylebox_override("normal", BattleUIStyle.make_button(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 1, 4))
	_character_close_button.add_theme_stylebox_override("hover", BattleUIStyle.make_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), 1, 4))
	_character_close_button.add_theme_stylebox_override("pressed", BattleUIStyle.make_button(BattleUIStyle.get_color("action_button").darkened(0.12), BattleUIStyle.get_color("accent"), 1, 4))
	_apply_scroll_bar_style(_character_skill_scroll.get_v_scroll_bar())
	_apply_character_skill_right_margin()
	if _character_card_view != null and is_instance_valid(_character_card_view):
		_character_card_view.refresh_ui_style()
	_refresh_skill_entry_styles()
	call_deferred("_resize_character_panel_to_content")


## 响应卡牌名称模式变化并原位刷新当前悬停说明与武将详情；不要求玩家移开鼠标或重新打开详情。
func refresh_card_name_mode() -> void:
	if not is_node_ready():
		return
	if not _pending_hover_information.is_empty():
		_pending_hover_information = _resolve_information_card_names(_pending_hover_information)
	if not _hover_information.is_empty() and _hover_panel.visible:
		_hover_information = _resolve_information_card_names(_hover_information)
		_hover_title_label.text = str(_hover_information.get("title", "信息"))
		_hover_subtitle_label.text = str(_hover_information.get("subtitle", ""))
		_hover_subtitle_label.visible = not _hover_subtitle_label.text.is_empty()
		_render_hover_description()
		_refresh_hover_text_styles()
		# 当前锚点在模式切换时保持不变；下一布局帧重新测量文本，避免牌名长度变化后面板尺寸失真。
		_hover_layout_generation += 1
		var layout_generation: int = _hover_layout_generation
		_hover_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_hover_panel.custom_minimum_size = Vector2(hover_panel_width, 0.0)
		_hover_panel.size = Vector2(hover_panel_width, 0.0)
		_hover_panel.reset_size()
		_place_hover_panel_after_layout(_hover_anchor_rect, _hover_source_id, layout_generation)
	if _character_shade.visible:
		_render_character_skills()
		call_deferred("_resize_character_panel_to_content")


## 深复制一份统一信息并解析其中全部【牌名】字段；已解析为另一模式的名称也能再次切换。
func _resolve_information_card_names(information: Dictionary) -> Dictionary:
	# 可写信息副本；来源组件持有的数据不会因信息框动态切换而被改写。
	var resolved_information: Dictionary = information.duplicate(true)
	for text_key: String in ["title", "subtitle", "description"]:
		if resolved_information.has(text_key):
			resolved_information[text_key] = GameDatabase.resolve_card_names_in_text(str(resolved_information.get(text_key, "")))
	# 结构化技能说明；每个条目继续保留标题和其他扩展字段，只动态解析文本内容。
	var description_sections: Array = resolved_information.get("description_sections", []) as Array
	for section_index: int in range(description_sections.size()):
		# 当前技能分段；深复制已保证修改不会回写来源字典。
		var section: Dictionary = description_sections[section_index] as Dictionary
		if section.has("title"):
			section["title"] = GameDatabase.resolve_card_names_in_text(str(section.get("title", "")))
		if section.has("description"):
			section["description"] = GameDatabase.resolve_card_names_in_text(str(section.get("description", "")))
		description_sections[section_index] = section
	resolved_information["description_sections"] = description_sections
	return resolved_information


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
	_hover_layout_generation += 1
	# 当前布局代次；异步等待一帧期间如果来源关闭或内容被替换，旧代次不得让面板重新显形。
	var layout_generation: int = _hover_layout_generation
	_hover_source_id = source_id
	_hover_information = information
	_hover_anchor_rect = anchor_rect
	_hover_title_label.text = str(_hover_information.get("title", "信息"))
	_hover_subtitle_label.text = str(_hover_information.get("subtitle", ""))
	_hover_subtitle_label.visible = not _hover_subtitle_label.text.is_empty()
	_render_hover_description()
	_refresh_hover_text_styles()
	# 面板需要进入布局树才能取得自动换行后的真实尺寸；测量完成前保持透明，防止默认位置或旧尺寸闪现一帧。
	_hover_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_hover_panel.visible = true
	_hover_panel.custom_minimum_size = Vector2(hover_panel_width, 0.0)
	_hover_panel.size = Vector2(hover_panel_width, 0.0)
	_hover_panel.reset_size()
	# 首次自动换行必须等待一个完整界面布局帧；此时 Label 已取得固定面板宽度，再测量高度不会把每个字符误当作独立行。
	_place_hover_panel_after_layout(anchor_rect, source_id, layout_generation)


## 等待自动换行标签取得固定宽度后再测量并放置信息框；来源已经离开时由后续来源校验安全忽略。
func _place_hover_panel_after_layout(anchor_rect: Rect2, source_id: int, layout_generation: int) -> void:
	await get_tree().process_frame
	_place_hover_panel(anchor_rect, source_id, layout_generation)


## 构建目标旁悬浮信息节点；所有输入保持穿透，浮层不会抢走原目标的鼠标离开判定。
func _build_hover_panel() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.name = "HoverInformationPanel"
	_hover_panel.visible = false
	_hover_panel.z_index = 100
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 使用可继承的 modulate 统一隐藏背景与全部文字子节点；self_modulate 不会作用于子节点，会造成文字在布局前闪现。
	_hover_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_hover_panel.custom_minimum_size = Vector2(hover_panel_width, 0.0)
	add_child(_hover_panel)
	# 悬浮信息纵向内容；固定顺序为标题、副标题和完整说明。
	var hover_content: VBoxContainer = VBoxContainer.new()
	hover_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_content.alignment = BoxContainer.ALIGNMENT_BEGIN
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
	_hover_description_container = VBoxContainer.new()
	_hover_description_container.name = "DescriptionContainer"
	_hover_description_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_description_container.add_theme_constant_override("separation", 9)
	hover_content.add_child(_hover_description_container)
	_hover_description_label = SkillDescriptionView.new()
	_hover_description_label.name = "Description"
	_hover_description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_description_label.add_theme_font_size_override("normal_font_size", 14)
	_hover_description_container.add_child(_hover_description_label)


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
	# 左侧牌面区域随右侧技能区或详情窗口高度填充；_center_character_card 会据此把缩放后的武将牌始终放在可用区域正中。
	_character_card_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_card_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_card_area.resized.connect(_center_character_card)
	character_body.add_child(_character_card_area)
	_character_skill_margin = MarginContainer.new()
	_character_skill_margin.name = "SkillRightMargin"
	_character_skill_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_skill_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_skill_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_body.add_child(_character_skill_margin)
	_character_skill_scroll = ScrollContainer.new()
	_character_skill_scroll.name = "SkillScroll"
	_character_skill_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_skill_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_character_skill_margin.add_child(_character_skill_scroll)
	_character_skill_list = VBoxContainer.new()
	_character_skill_list.name = "SkillList"
	_character_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_skill_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_skill_list.add_theme_constant_override("separation", skill_entry_separation)
	_character_skill_scroll.add_child(_character_skill_list)


## 根据来源矩形把悬浮信息放到目标右侧；右侧空间不足时翻转到左侧并限制在视口安全区内。
func _place_hover_panel(anchor_rect: Rect2, source_id: int, layout_generation: int) -> void:
	if source_id != _hover_source_id or layout_generation != _hover_layout_generation or not _hover_panel.visible:
		return
	# 当前布局可用尺寸；组件尚保留旧逻辑画布尺寸时，以已缩小的父Control客户区作为更严格上限。
	var layout_size: Vector2 = size
	# 父级布局控件；仅Control具有可直接比较的客户区尺寸，其他父节点保持本组件自身尺寸。
	var parent_control: Control = get_parent() as Control
	if parent_control != null:
		layout_size = Vector2(minf(layout_size.x, parent_control.size.x), minf(layout_size.y, parent_control.size.y))
	# 当前组件可用视口矩形；根控件与牌桌共享逻辑画布坐标。
	var available_rect: Rect2 = Rect2(Vector2(viewport_margin, viewport_margin), layout_size - Vector2.ONE * viewport_margin * 2.0)
	# 可用宽度范围；检查器配置与当前视口都可能收紧上限，最小值始终不会超过实际可显示宽度。
	var available_width: float = maxf(available_rect.size.x, 1.0)
	var minimum_width: float = minf(maxf(hover_panel_minimum_width, 1.0), available_width)
	var maximum_width: float = clampf(hover_panel_maximum_width, minimum_width, available_width)
	# 先以基准宽度测量正文；此时自动换行已经在上一帧取得有效宽度，不会再把字符误算成单独行。
	var measuring_width: float = clampf(hover_panel_width, minimum_width, maximum_width)
	var measuring_height: float = _measure_hover_panel_content_height(measuring_width)
	# 按目标4:3比例反推适合当前内容的宽度；短内容取最小宽度，长内容扩展到最大宽度后再自然增高。
	# 首选宽高比；只用于根据估算内容面积选择起始宽度，不再强制最终面板精确保持该比例。
	var preferred_aspect_ratio: float = maxf(hover_panel_aspect_ratio, 0.01)
	# 最小允许比例；异常配置时与最大比例自动排序，不把检查器输入传播成布局错误。
	var minimum_aspect_ratio: float = minf(hover_panel_minimum_aspect_ratio, hover_panel_maximum_aspect_ratio)
	# 最大允许比例；始终不小于最小值，后续可安全用于高度下限计算。
	var maximum_aspect_ratio: float = maxf(hover_panel_minimum_aspect_ratio, hover_panel_maximum_aspect_ratio)
	# 估算内容面积；基准宽高乘积能同时反映文本长度和当前换行情况。
	var estimated_content_area: float = maxf(measuring_width * measuring_height, 1.0)
	# 初始目标宽度；以面积和首选比例开平方反推，使短、中、长说明自然获得不同宽度。
	var desired_width: float = clampf(sqrt(estimated_content_area * preferred_aspect_ratio), minimum_width, maximum_width)
	# 当前可见文本字符总数；富文本高度会延迟到下一布局帧更新，因此同时作为确定性的宽度下限输入。
	var visible_text_character_count: int = _get_hover_visible_text_character_count()
	# 超出紧凑阈值的字符数；短说明保持0，长说明按配置逐步扩宽。
	var extra_text_character_count: int = maxi(visible_text_character_count - hover_panel_compact_text_character_count, 0)
	# 基于字符量的目标宽度下限；仅补偿富文本延迟测量，不越过当前视口允许的最大宽度。
	var text_length_width_floor: float = clampf(minimum_width + float(extra_text_character_count) * hover_panel_width_per_extra_text_character, minimum_width, maximum_width)
	desired_width = maxf(desired_width, text_length_width_floor)
	var content_height: float = _measure_hover_panel_content_height(desired_width)
	# 宽度搜索步长；至少为1像素，避免检查器或旧场景异常值使循环停滞。
	var width_step: float = maxf(hover_panel_width_adjustment_step, 1.0)
	# 当前宽高比；真实内容高度为0时使用1像素作安全分母。
	var current_aspect_ratio: float = desired_width / maxf(content_height, 1.0)
	# 当前搜索迭代数；增宽与缩宽共享上限，保证单次悬停布局耗时可控。
	var search_iteration_count: int = 0
	while current_aspect_ratio < minimum_aspect_ratio and desired_width < maximum_width and search_iteration_count < MAX_HOVER_WIDTH_SEARCH_ITERATIONS:
		desired_width = minf(desired_width + width_step, maximum_width)
		content_height = _measure_hover_panel_content_height(desired_width)
		current_aspect_ratio = desired_width / maxf(content_height, 1.0)
		search_iteration_count += 1
	while current_aspect_ratio > maximum_aspect_ratio and desired_width > minimum_width and search_iteration_count < MAX_HOVER_WIDTH_SEARCH_ITERATIONS:
		desired_width = maxf(desired_width - width_step, minimum_width)
		content_height = _measure_hover_panel_content_height(desired_width)
		current_aspect_ratio = desired_width / maxf(content_height, 1.0)
		search_iteration_count += 1
	# 最终高度同时满足完整文字与4:3目标比例；正文特别长时允许高于比例，避免裁切技能或卡牌说明。
	# 最终高度；优先容纳全部文字，短内容过宽时只补足到最大比例下限，不再补齐固定4:3空白。
	var desired_height: float = maxf(content_height, desired_width / maximum_aspect_ratio)
	_hover_panel.custom_minimum_size = Vector2(desired_width, desired_height)
	_hover_panel.size = Vector2(desired_width, desired_height)
	# 当前信息框实际尺寸；完成内容与比例测量后使用该值进行视口边界计算。
	# 默认信息框位置；优先显示在目标右侧并与目标顶边对齐。
	# 补充：实际尺寸读取和目标位置计算已委托给纯定位入口，避免相同资料重复触发宽度测量。
	# 初次使用当前测量尺寸定位，但继续保持透明；最终宽度下的自动换行高度将在下一帧稳定。
	_reposition_hover_panel(anchor_rect, source_id, layout_generation)
	# 位置与最终尺寸都稳定后再显示；这一步也是当前布局代次唯一允许恢复不透明度的入口。
	# 容器的自动换行高度会在最终宽度写入后的下一帧稳定；实际显示和边界收紧交由二次布局入口完成。
	_finalize_hover_panel_after_layout(anchor_rect, source_id, layout_generation)


## 等待最终宽度下的自动换行高度稳定，再按真实面板尺寸收紧位置并恢复不透明度。
func _finalize_hover_panel_after_layout(anchor_rect: Rect2, source_id: int, layout_generation: int) -> void:
	await get_tree().process_frame
	if source_id != _hover_source_id or layout_generation != _hover_layout_generation or not _hover_panel.visible:
		return
	_reposition_hover_panel(anchor_rect, source_id, layout_generation)
	_hover_panel.modulate = Color.WHITE


## 仅按当前稳定尺寸重新定位信息框；相同内容的高频刷新不得重新测量宽度，否则自动换行边界会在相邻帧振荡。
func _reposition_hover_panel(anchor_rect: Rect2, source_id: int, layout_generation: int) -> void:
	if source_id != _hover_source_id or layout_generation != _hover_layout_generation or not _hover_panel.visible:
		return
	# 最终布局可用尺寸；与初次测量一样优先服从已缩小的父Control客户区。
	# 补充：本入口也用于稳定内容的重复定位，所以不执行任何文本或宽高测量。
	var layout_size: Vector2 = size
	# 父级布局控件；紧凑窗口测试会直接修改其尺寸，信息框不应继续使用旧逻辑画布边界。
	# 补充：正式运行时缩放同样服从该客户区边界。
	var parent_control: Control = get_parent() as Control
	if parent_control != null:
		layout_size = Vector2(minf(layout_size.x, parent_control.size.x), minf(layout_size.y, parent_control.size.y))
	# 最终安全矩形；保留与初次定位相同的视口边距。
	# 补充：面板大于可用空间时仍夹到左上安全边界。
	var available_rect: Rect2 = Rect2(Vector2(viewport_margin, viewport_margin), layout_size - Vector2.ONE * viewport_margin * 2.0)
	# 当前信息框实际尺寸；完成内容与比例测量后使用该值进行视口边界计算。
	# 最终面板尺寸；已包含当前宽度下全部标题、副标题和正文换行高度。
	# 补充：本函数只读取该稳定尺寸，不修改custom_minimum_size、宽度或自动换行状态。
	var panel_size: Vector2 = _hover_panel.size
	# 默认信息框位置；优先显示在目标右侧并与目标顶边对齐。
	# 最终目标位置；仍优先目标右侧，空间不足时翻转到左侧。
	# 补充：翻转后还会把位置夹入当前安全区域。
	var target_position: Vector2 = Vector2(anchor_rect.end.x + hover_target_gap, anchor_rect.position.y)
	if target_position.x + panel_size.x > available_rect.end.x:
		target_position.x = anchor_rect.position.x - panel_size.x - hover_target_gap
	target_position.x = clampf(target_position.x, available_rect.position.x, maxf(available_rect.end.x - panel_size.x, available_rect.position.x))
	target_position.y = clampf(target_position.y, available_rect.position.y, maxf(available_rect.end.y - panel_size.y, available_rect.position.y))
	_hover_panel.position = target_position


## 在指定宽度下测量悬停说明所需的最小内容高度；每次测量都重置旧比例产生的高度，保证下一份信息不会继承前一份的空白。
func _measure_hover_panel_content_height(panel_width: float) -> float:
	_hover_panel.custom_minimum_size = Vector2(panel_width, 0.0)
	_hover_panel.size = Vector2(panel_width, 0.0)
	_hover_panel.reset_size()
	return _hover_panel.size.y


## 统计当前悬停资料实际可见的标题、副标题与说明字符数；结构化武将资料只计算逐技能分段，避免重复计算隐藏的合并正文。
func _get_hover_visible_text_character_count() -> int:
	# 可见字符总数；标题始终显示，副标题与正文按当前信息结构选择性累加。
	var character_count: int = str(_hover_information.get("title", "")).length()
	# 当前副标题；空文本不会创建可见行，但累加0不会影响结果。
	var subtitle: String = str(_hover_information.get("subtitle", ""))
	character_count += subtitle.length()
	# 当前结构化技能说明；存在时普通合并正文隐藏，只统计每个实际显示的技能名称与说明。
	var description_sections: Array = _hover_information.get("description_sections", []) as Array
	if description_sections.is_empty():
		character_count += str(_hover_information.get("description", "暂无说明。")).length()
		return character_count
	for section_variant: Variant in description_sections:
		# 当前技能说明分段；异常值按空字典处理，不影响其他有效分段的布局。
		var section: Dictionary = section_variant as Dictionary
		character_count += str(section.get("title", "")).length()
		character_count += str(section.get("description", "暂无说明。")).length()
	return character_count


## 按当前信息结构重建悬停说明；武将资料将每个技能拆分为金色技能名和普通说明，其他来源继续使用单段正文。
func _render_hover_description() -> void:
	_clear_hover_description_sections()
	_hover_description_label.configure_description(str(_hover_information.get("description", "暂无说明。")), bool(_hover_information.get("reincarnation", false)), int(_hover_information.get("reincarnation_section_index", 0)))
	# 当前结构化说明分段；没有该可选字段时保持卡牌、装备与普通技能原有单标签展示。
	var description_sections: Array = _hover_information.get("description_sections", []) as Array
	_hover_description_label.visible = description_sections.is_empty()
	for section_index: int in range(description_sections.size()):
		# 当前说明分段；无效值回退为空字典，避免单项内容错误破坏整个信息框。
		var section: Dictionary = description_sections[section_index] as Dictionary
		# 当前技能说明条目；名称与描述分别建标签，颜色和换行职责互不耦合。
		var section_container: VBoxContainer = VBoxContainer.new()
		section_container.name = "DescriptionSection%d" % section_index
		section_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section_container.add_theme_constant_override("separation", 4)
		_hover_description_container.add_child(section_container)
		# 当前技能名称标签；完整名称保留武将定义原文并使用右键详情同款主题强调色。
		var section_title_label: Label = Label.new()
		section_title_label.name = "Title"
		section_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section_title_label.text = str(section.get("title", ""))
		section_title_label.add_theme_font_size_override("font_size", 17)
		section_container.add_child(section_title_label)
		_hover_skill_name_labels.append(section_title_label)
		# 当前技能描述标签；完整规则文本自然换行，颜色保持与右键详情说明一致。
		var section_description_label: SkillDescriptionView = SkillDescriptionView.new()
		section_description_label.name = "Description"
		section_description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section_description_label.configure_description(str(section.get("description", "暂无说明。")), bool(section.get("reincarnation", false)), int(section.get("reincarnation_section_index", 0)))
		section_description_label.add_theme_font_size_override("normal_font_size", 14)
		section_container.add_child(section_description_label)
		_hover_skill_description_labels.append(section_description_label)


## 清理武将悬停资料创建的结构化技能标签；普通说明标签始终保留并在下一份内容中复用。
func _clear_hover_description_sections() -> void:
	if _hover_description_container == null:
		_hover_skill_name_labels.clear()
		_hover_skill_description_labels.clear()
		return
	for child: Node in _hover_description_container.get_children():
		if child == _hover_description_label:
			continue
		_hover_description_container.remove_child(child)
		child.queue_free()
	_hover_skill_name_labels.clear()
	_hover_skill_description_labels.clear()


## 按当前主题刷新悬停标题、技能名和说明颜色；只有武将资料明确声明强调标题时才使用金色。
func _refresh_hover_text_styles() -> void:
	if _hover_title_label == null:
		return
	# 当前标题颜色；武将名使用与右键技能名一致的强调色，其他信息标题保持主文字色。
	var title_color: Color = BattleUIStyle.get_color("accent") if bool(_hover_information.get("title_emphasis", false)) else BattleUIStyle.get_color("text_primary")
	_hover_title_label.add_theme_color_override("font_color", title_color)
	_hover_subtitle_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_hover_description_label.refresh_ui_style()
	for skill_name_label: Label in _hover_skill_name_labels:
		skill_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
	for skill_description_label: SkillDescriptionView in _hover_skill_description_labels:
		skill_description_label.refresh_ui_style()


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
	# 武将可见技能ID数组；固有技能保持定义顺序，运行时临时技能随后追加且不重复。
	var skill_ids: Array = (_character_definition.get("skills", []) as Array).duplicate()
	for temporary_skill_id_variant: Variant in (_character_snapshot.get("temporary_skills", {}) as Dictionary).keys():
		# 当前临时技能ID；与固有技能同名时只显示一次。
		var temporary_skill_id: String = str(temporary_skill_id_variant)
		if not skill_ids.has(temporary_skill_id):
			skill_ids.append(temporary_skill_id)
	for acquired_skill_id_variant: Variant in (_character_snapshot.get("acquired_skills", {}) as Dictionary).keys():
		# 当前局内永久获得技能ID；与固有或临时技能同名时只显示一次。
		var acquired_skill_id: String = str(acquired_skill_id_variant)
		if not skill_ids.has(acquired_skill_id):
			skill_ids.append(acquired_skill_id)
	if skill_ids.is_empty():
		# 无技能占位说明；只表达静态内容为空，不推断运行时技能状态。
		var empty_label: Label = Label.new()
		empty_label.text = "该武将没有可显示的技能。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
		_character_skill_list.add_child(empty_label)
		_append_character_opportunity_section()
		_append_character_skill_bottom_spacer()
		call_deferred("_refresh_character_skill_vertical_layout")
		return
	for skill_id_variant: Variant in skill_ids:
		# 当前技能稳定 ID；用于从数据库取得只读名称与原始说明。
		var skill_id: String = str(skill_id_variant)
		# 当前技能定义；缺失时显示可诊断占位内容，不让技能列表静默缺项。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能显示名；数据库缺失时回退稳定 ID，便于内容维护者定位问题。
		var skill_name: String = str(skill_definition.get("name", skill_id))
		# 当前技能详情标题；受限的局内获得技能在技能名后追加完整次数文案，技能描述原文不插入次数状态。
		var skill_information_title: String = _get_character_skill_information_title(skill_id, skill_name)
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
		skill_name_label.text = skill_information_title
		skill_name_label.add_theme_font_size_override("font_size", 17)
		skill_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
		skill_entry.add_child(skill_name_label)
		# 技能描述行；长文本允许自然换行，滚动框负责查看超出面板高度的全部内容。
		var skill_description_label: SkillDescriptionView = SkillDescriptionView.new()
		# 当前轮回状态；右键详情使用玩家公开快照，局外静态资料自然回退①。
		var reincarnation_state: Dictionary = (_character_snapshot.get("reincarnation_skills", {}) as Dictionary).get(skill_id, {}) as Dictionary
		skill_description_label.configure_description(skill_description, bool(skill_definition.get("reincarnation", false)), int(reincarnation_state.get("section_index", 0)))
		skill_description_label.add_theme_font_size_override("normal_font_size", 14)
		skill_entry.add_child(skill_description_label)
		_character_skill_entry_count += 1
	_append_character_opportunity_section()
	_append_character_skill_bottom_spacer()
	call_deferred("_refresh_character_skill_vertical_layout")


## 返回右键武将详情中的技能标题；局内获得的受限技能只在标题后显示完整次数文案，避免改写技能原文。
func _get_character_skill_information_title(skill_id: String, skill_name: String) -> String:
	# 默认技能详情标题；所有技能均使用统一书名号样式，保证右键详情与悬停资料语义一致。
	var skill_information_title: String = "【%s】" % skill_name
	# 当前详情快照内的受限技能次数映射；该字段由 MatchTable 从权威获得技能记录生成，详情组件不自行计算或扣减次数。
	var remaining_uses_by_skill: Dictionary = _character_snapshot.get("acquired_skill_remaining_uses", {}) as Dictionary
	# 当前技能完整次数文案；没有限制或不是局内获得技能时保持空字符串。
	var remaining_uses_description: String = str(remaining_uses_by_skill.get(skill_id, ""))
	if not remaining_uses_description.is_empty():
		skill_information_title += "（%s）" % remaining_uses_description
	return skill_information_title


## 在挂载机缘组件的模式中追加永久机缘历史；只读取公开稳定ID并从静态目录解析品质与原文。
func _append_character_opportunity_section() -> void:
	if not bool(_character_snapshot.get("opportunity_mode_enabled", false)):
		return
	# 技能与机缘分组线；独立元数据避免被技能分隔线计数与布局测试误认。
	var section_separator: HSeparator = HSeparator.new()
	section_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section_separator.set_meta("information_box_opportunity_separator", true)
	_apply_skill_separator_style(section_separator)
	_character_skill_list.add_child(section_separator)
	# 机缘分组标题；使用主题强调色，与技能名形成同一资料层级。
	var section_title: Label = Label.new()
	section_title.text = "机缘"
	section_title.add_theme_font_size_override("font_size", 18)
	section_title.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
	section_title.set_meta("information_box_opportunity_title", true)
	_character_skill_list.add_child(section_title)
	# 已获得机缘ID历史；数组按实际获得顺序保存且允许重复，详情不自行去重或改写卡面正文。
	var opportunity_ids: Array = _character_snapshot.get("acquired_opportunity_ids", []) as Array
	if opportunity_ids.is_empty():
		# 空历史说明；机缘模式开局即可看到稳定分组，而不是等首次获得后突然改变详情结构。
		var empty_opportunity_label: Label = Label.new()
		empty_opportunity_label.text = "尚未获得机缘。"
		empty_opportunity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_opportunity_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
		empty_opportunity_label.set_meta("information_box_opportunity_empty", true)
		_character_skill_list.add_child(empty_opportunity_label)
		return
	for opportunity_id_variant: Variant in opportunity_ids:
		# 当前机缘稳定ID；目录缺失时仍保留明确占位，便于内容维护者定位历史数据问题。
		var opportunity_id: String = str(opportunity_id_variant)
		# 当前机缘静态定义；正文保持目录中主公钦定原文，不在详情层重新解释效果。
		var opportunity_definition: Dictionary = OpportunityCatalog.get_card(opportunity_id)
		# 当前品质中文；灰色表示仅由关卡授予且不参与随机抽取，未知值只用于暴露内容配置错误。
		var quality_name: String = str({"gray":"灰色", "green":"绿色", "blue":"蓝色", "purple":"紫色", "orange":"橙色", "red":"红色"}.get(str(opportunity_definition.get("quality", "")), "未知"))
		# 单个机缘历史条目；名称与正文分行，保持长规则原文可自动换行。
		var opportunity_entry: VBoxContainer = VBoxContainer.new()
		opportunity_entry.add_theme_constant_override("separation", 4)
		opportunity_entry.set_meta("information_box_opportunity_entry", true)
		_character_skill_list.add_child(opportunity_entry)
		# 机缘品质名称；无独立卡名时使用“品质机缘”作为稳定标题。
		var opportunity_name_label: Label = Label.new()
		opportunity_name_label.text = "【%s机缘】" % quality_name
		opportunity_name_label.add_theme_font_size_override("font_size", 16)
		opportunity_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
		opportunity_entry.add_child(opportunity_name_label)
		# 机缘规则正文；技能牌、数值牌与目标牌都显示原始完整描述。
		var opportunity_description_label: Label = Label.new()
		opportunity_description_label.text = str(opportunity_definition.get("description", "机缘元数据尚未登记。"))
		opportunity_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		opportunity_description_label.add_theme_font_size_override("font_size", 14)
		opportunity_description_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		opportunity_entry.add_child(opportunity_description_label)
		_character_opportunity_entry_count += 1


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
		_character_opportunity_entry_count = 0
		return
	for child: Node in _character_skill_list.get_children():
		_character_skill_list.remove_child(child)
		child.queue_free()
	_character_skill_list.custom_minimum_size.y = 0.0
	_character_skill_bottom_spacer = null
	_character_skill_entry_count = 0
	_character_opportunity_entry_count = 0


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
			var skill_description_label: SkillDescriptionView = entry_node.get_child(1) as SkillDescriptionView
			skill_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
			if skill_description_label != null:
				skill_description_label.refresh_ui_style()
		elif entry_node is HSeparator and entry_node.has_meta("information_box_skill_separator"):
			_apply_skill_separator_style(entry_node as HSeparator)
		elif entry_node is VBoxContainer and entry_node.has_meta("information_box_opportunity_entry"):
			# 机缘历史条目；索引0为品质标题，索引1为主公钦定规则正文。
			var opportunity_name_label: Label = entry_node.get_child(0) as Label
			var opportunity_description_label: Label = entry_node.get_child(1) as Label
			opportunity_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
			opportunity_description_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		elif entry_node is HSeparator and entry_node.has_meta("information_box_opportunity_separator"):
			_apply_skill_separator_style(entry_node as HSeparator)
		elif entry_node is Label and entry_node.has_meta("information_box_opportunity_title"):
			(entry_node as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
		elif entry_node is Label:
			(entry_node as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))


## 依据左侧牌面和右侧技能内容收紧武将详情高度；短内容不再保留固定440像素空白，长内容仍被440像素最大高度和滚动框限制。
func _resize_character_panel_to_content() -> void:
	if _character_panel == null or _character_content == null or _character_skill_list == null or _character_card_area == null:
		return
	# 技能列表先解除上一次的视口填充高度，才能取得本次武将真实技能内容高度。
	_character_skill_list.custom_minimum_size.y = 0.0
	_update_character_skill_bottom_spacer()
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


## 将检查器配置的额外右边距应用到详情技能区；滚动条、技能文字与面板右边框会整体保持该距离。
func _apply_character_skill_right_margin() -> void:
	if _character_skill_margin == null:
		return
	_character_skill_margin.add_theme_constant_override("margin_right", character_skill_right_margin)


## 在技能列表末尾追加与顶部标题区域等高的留白；VBox整体居中后可保证首个技能名与最后一行文字到面板边框的距离相等。
func _append_character_skill_bottom_spacer() -> void:
	_character_skill_bottom_spacer = Control.new()
	_character_skill_bottom_spacer.name = "BottomSymmetrySpacer"
	_character_skill_bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_skill_bottom_spacer.set_meta("information_box_skill_bottom_spacer", true)
	_character_skill_list.add_child(_character_skill_bottom_spacer)
	_update_character_skill_bottom_spacer()


## 依据标题栏、主体间距和主题面板边距计算底部留白；主题切换后仍保持文字区域上下视觉对称。
func _update_character_skill_bottom_spacer() -> void:
	if _character_skill_bottom_spacer == null or not is_instance_valid(_character_skill_bottom_spacer):
		return
	# 标题与主体之间的实际间距；与面板高度计算读取同一主题常量，避免布局规则分叉。
	var content_separation: float = float(_character_content.get_theme_constant("separation"))
	# 当前面板上下内容边距；上下不一致的自定义主题也会被纳入对称距离计算。
	var panel_margin_top: float = 0.0
	var panel_margin_bottom: float = 0.0
	var panel_style: StyleBoxFlat = _character_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style != null:
		panel_margin_top = panel_style.content_margin_top
		panel_margin_bottom = panel_style.content_margin_bottom
	# 最后一项与留白控件之间由VBox自动加入的间距；从目标距离中扣除后不会重复增加底部空白。
	var list_separation: float = float(_character_skill_list.get_theme_constant("separation"))
	# 底部目标距离；与上边框到主体首行之间的标题栏、容器间距及主题边距差完全对应。
	var target_bottom_gap: float = maxf(character_header_height + content_separation + panel_margin_top - panel_margin_bottom, 0.0)
	_character_skill_bottom_spacer.custom_minimum_size.y = maxf(target_bottom_gap - list_separation, 0.0)


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
