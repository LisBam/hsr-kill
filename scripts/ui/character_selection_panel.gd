class_name CharacterSelectionPanel
extends Control

## 选将界面组件。该组件只渲染观察者可见候选、临时高亮和确认进度，通过稳定武将 ID 发出选择请求。

## 玩家确认武将时发出的信号；参数为稳定武将配置 ID，不携带节点或配置引用。
signal character_selected(character_id: String)

## 玩家确认完整选将数据时发出的信号；包含武将 ID，可选座次、身份和 AI 调整目标，全部字段可序列化。
signal selection_submitted(selection_data: Dictionary)

## 玩家点击单张候选上方“换将”按钮时发出的信号；参数只包含被替换候选的稳定武将 ID。
signal candidate_replacement_requested(character_id: String)

## 本地修改自选座次或身份时发出的预览信号；参数始终是已经完成一号位与领袖联动后的稳定组合。
signal custom_assignment_preview_requested(seat_number: int, identity: String)

## 选将候选或公开领袖武将牌请求显示统一悬停信息时发出的转发信号。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 选将武将牌结束悬停或节点释放时发出的统一信息关闭转发信号。
signal information_dismissed

## 正式武将牌场景；五张候选牌与局内角色牌复用同一 Node2D 模型和数据渲染逻辑。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 选将标题节点的组件内相对路径；节点位于 SelectionFrame 下，不依赖场景唯一名称所有权。
const TITLE_LABEL_PATH: NodePath = NodePath("SelectionFrame/CharacterSelectionTitle")

## 选将状态文本节点的组件内相对路径；节点保留兼容但正式界面默认隐藏。
const STATUS_LABEL_PATH: NodePath = NodePath("SelectionFrame/CharacterSelectionStatus")

## 候选武将牌承载区的组件内相对路径；所有动态候选都只添加到该容器。
const CANDIDATE_AREA_PATH: NodePath = NodePath("SelectionFrame/CharacterCandidateArea")

## 候选滚动内容节点的组件内相对路径；正式武将牌和换将按钮都只添加到该节点。
const CANDIDATE_CONTENT_PATH: NodePath = NodePath("SelectionFrame/CharacterCandidateArea/CandidateScrollContent")

## 领袖武将牌承载区的组件内相对路径；领袖亮将后创建的只读牌面添加到该容器。
const LEADER_CHARACTER_AREA_PATH: NodePath = NodePath("SelectionFrame/LeaderCharacterArea")

## 领袖牌标题节点的组件内相对路径；仅在领袖牌面可见时同步显示。
const LEADER_CHARACTER_LABEL_PATH: NodePath = NodePath("SelectionFrame/LeaderCharacterLabel")

## 领袖牌与候选牌之间竖向分隔线的组件内相对路径；没有公开领袖时保持隐藏且不占候选区域。
const LEADER_DIVIDER_PATH: NodePath = NodePath("SelectionFrame/LeaderDivider")

## 旧场景缺少领袖分隔线时使用的默认矩形；2像素宽竖线位于领袖牌区与候选区之间。
const LEADER_DIVIDER_RECT: Rect2 = Rect2(200.0, 82.0, 2.0, 242.0)

## 旧场景缺少领袖分隔线时使用的暗金颜色；透明度0.72保证分隔可见但不抢占武将牌视觉层级。
const LEADER_DIVIDER_COLOR: Color = Color(0.78, 0.63, 0.34, 0.72)

## 选将确认按钮的组件内相对路径；按钮只提交稳定武将 ID。
const CONFIRM_BUTTON_PATH: NodePath = NodePath("SelectionFrame/ConfirmCharacterButton")

## 自选模式与 AI 调整模式切换全部武将列表的按钮路径。
const ALL_CHARACTERS_BUTTON_PATH: NodePath = NodePath("SelectionFrame/AllCharactersButton")

## 自选座次按钮容器路径；按钮数量按本局总座次动态创建。
const SEAT_BUTTONS_PATH: NodePath = NodePath("SelectionFrame/SeatButtons")

## 自选身份按钮容器路径；固定显示领袖、忠臣、反贼与内奸四种身份。
const IDENTITY_BUTTONS_PATH: NodePath = NodePath("SelectionFrame/IdentityButtons")

## 自选模式候选区域矩形；为多行全部武将与下方座次、身份按钮预留空间。
const CUSTOM_CANDIDATE_RECT: Rect2 = Rect2(24.0, 68.0, 992.0, 332.0)

## 全武将模式主框距离视口四边的安全边距；16像素可最大化牌面区域并避免贴边裁切。
const ALL_CHARACTERS_FRAME_MARGIN: float = 16.0

## 候选换将按钮宽度；84像素足以稳定容纳“换将”两字且不遮挡相邻牌面。
const REPLACEMENT_BUTTON_WIDTH: float = 84.0

## 候选换将按钮高度；30像素与设置紧凑按钮规格一致，悬停时不会推动牌面布局。
const REPLACEMENT_BUTTON_HEIGHT: float = 30.0

## 换将按钮与对应武将牌之间的垂直间距；6像素明确表达按钮归属并保留点击边界。
const REPLACEMENT_BUTTON_GAP: float = 6.0

## 全武将模式确认按钮上方与滚动区之间的间距；12像素保证滚动条不会贴住主要操作。
const ALL_CHARACTERS_CONFIRM_GAP: float = 12.0

## 四种身份按钮的稳定排列；显示文字与主题颜色均从该表统一解析。
const IDENTITY_OPTIONS: Array[Dictionary] = [
	{"id":"leader", "label":"领袖"},
	{"id":"loyalist", "label":"忠臣"},
	{"id":"rebel", "label":"反贼"},
	{"id":"renegade", "label":"内奸"},
]

## 候选武将牌之间的水平与垂直间距；默认8像素，让多行候选在保留原尺寸牌面的前提下更紧凑。
@export_range(0.0, 48.0, 1.0) var candidate_gap: float = 8.0

## 候选武将悬停时的放大倍数；默认1.08提供清晰反馈且不会明显遮挡相邻牌，运行时无需动态修改。
@export_range(1.0, 1.25, 0.01) var candidate_hover_scale: float = 1.08

## 候选武将悬停放大与恢复的过渡时长；默认0.14秒兼顾响应速度与缩放可见性，运行时无需动态修改。
@export_range(0.0, 0.5, 0.01) var candidate_hover_transition_seconds: float = 0.14

## 已公开领袖武将牌的显示缩放；默认0.78使其弱于可选候选并保留分隔层级，运行时无需动态修改。
@export_range(0.5, 1.0, 0.01) var leader_character_scale: float = 0.78

## 选将标题；根据领袖先选、其他玩家同时选和等待公开三个状态显示明确说明。
## 使用富文本只为身份名称应用阵营色，其余提示保持主题主文字色。
@onready var _title_label: RichTextLabel = get_node_or_null(TITLE_LABEL_PATH) as RichTextLabel

## 阶段说明文本；展示领袖已亮武将和其他玩家确认进度，不泄漏隐藏选择内容。
@onready var _status_label: Label = get_node_or_null(STATUS_LABEL_PATH) as Label

## 候选武将牌承载区域；只负责提供局部坐标，牌面根节点保持 Node2D 类型。
@onready var _candidate_area: Control = get_node_or_null(CANDIDATE_AREA_PATH) as Control

## 候选滚动内容节点；其最小高度按实际行数更新，ScrollContainer据此决定是否显示垂直滚动条。
@onready var _candidate_content: Control = get_node_or_null(CANDIDATE_CONTENT_PATH) as Control

## 选将主框；普通模式保持场景几何，全武将模式临时扩展到视口安全边距内。
@onready var _selection_frame: Panel = get_node_or_null("SelectionFrame") as Panel

## 领袖武将牌承载区域；领袖确认后固定显示在选将框左侧，不参与候选点击或提交。
@onready var _leader_character_area: Control = get_node_or_null(LEADER_CHARACTER_AREA_PATH) as Control

## 领袖武将牌标题；仅在领袖已经亮将时显示，用于说明左侧只读牌面归属。
@onready var _leader_character_label: Label = get_node_or_null(LEADER_CHARACTER_LABEL_PATH) as Label

## 领袖牌与候选牌之间的竖向分隔线；只在领袖武将已经公开时显示。
@onready var _leader_divider: ColorRect = get_node_or_null(LEADER_DIVIDER_PATH) as ColorRect

## 选将确认按钮；只有已临时选中候选且规则快照允许选择时才可用。
@onready var _confirm_button: Button = get_node_or_null(CONFIRM_BUTTON_PATH) as Button

## “所有武将”按钮；仅房主权威选项允许时显示，切换只改变本地候选展示范围。
@onready var _all_characters_button: Button = get_node_or_null(ALL_CHARACTERS_BUTTON_PATH) as Button

## 座次按钮容器；自选模式按当前总人数生成一号位至末号位按钮。
@onready var _seat_buttons: HBoxContainer = get_node_or_null(SEAT_BUTTONS_PATH) as HBoxContainer

## 身份按钮容器；自选模式固定生成四种身份按钮并按剩余名额禁用。
@onready var _identity_buttons: HBoxContainer = get_node_or_null(IDENTITY_BUTTONS_PATH) as HBoxContainer

## 座次行标题；与按钮容器同时显隐。
@onready var _seat_selection_label: Label = get_node_or_null("SelectionFrame/SeatSelectionLabel") as Label

## 身份行标题；与按钮容器同时显隐。
@onready var _identity_selection_label: Label = get_node_or_null("SelectionFrame/IdentitySelectionLabel") as Label

## 最近一次选将快照；只包含本地可见候选和公开确认状态，用于重绘界面。
var _snapshot: Dictionary = {}

## 本地临时选中的武将 ID；点击确认前不会发送规则动作或改变公开状态。
var _selected_character_id: String = ""

## 当前候选武将 ID 到正式武将牌视图的映射；只用于同步金色选中边框。
var _candidate_views: Dictionary = {}

## 当前左侧领袖武将牌视图；领袖尚未确认或选将界面关闭时为 null。
var _leader_character_view: PlayerTargetView

## 候选武将 ID 到未缩放基础位置的映射；悬停补间始终相对该位置居中放大并恢复。
var _candidate_base_positions: Dictionary = {}

## 候选武将 ID 到基础缩放的映射；全部武将多行布局会缩小牌面，悬停仍相对该比例放大。
var _candidate_base_scales: Dictionary = {}

## 候选武将 ID 到当前缩放补间的映射；重复进入或离开时停止旧补间，避免多个动画同时写入同一节点。
var _candidate_hover_tweens: Dictionary = {}

## 候选武将 ID 到换将按钮的映射；只有仍可消耗换将卡的普通随机候选会创建按钮。
var _replacement_buttons: Dictionary = {}

## 候选区域存在领袖时的原始左边界；从场景保存几何读取，避免脚本重复硬编码布局坐标。
var _candidate_area_with_leader_left: float = 0.0

## 候选区域不存在领袖时的左边界；与领袖只读区域左边缘对齐，使候选直接占用空出的空间。
var _candidate_area_without_leader_left: float = 0.0

## 候选区域固定右边界；切换领袖占位时只改变左边界，不影响确认按钮或选将框宽度。
var _candidate_area_right: float = 0.0

## 场景保存的普通候选区域位置；退出全部武将多行布局时恢复，不硬编码重复几何。
var _candidate_default_position: Vector2 = Vector2.ZERO

## 场景保存的普通候选区域尺寸；退出全部武将多行布局时恢复。
var _candidate_default_size: Vector2 = Vector2.ZERO

## 必需场景节点是否已经完整绑定；为 false 时组件保持隐藏并拒绝渲染，避免产生连续空实例报错。
var _required_nodes_ready: bool = false

## 当前标题中身份文字实际使用的颜色；用于主题切换后重绘与自动化验证，不参与身份规则判断。
var _rendered_identity_color: Color = Color.WHITE

## 当前是否显示全部武将；只属于本地选将界面，不写入权威状态。
var _showing_all_characters: bool = false

## 当前临时选中的座次号；-1表示尚未选择，确认前不占用权威名额。
var _selected_seat_number: int = -1

## 当前临时选中的身份 ID；空字符串表示尚未选择。
var _selected_identity: String = ""

## 当前动态座次按钮映射；键为从1开始的座次号，值为主题按钮节点。
var _seat_button_views: Dictionary = {}

## 当前动态身份按钮映射；键为稳定身份 ID，值为主题按钮节点。
var _identity_button_views: Dictionary = {}

## 普通选将布局的节点矩形缓存；退出全武将模式时原样恢复，避免重复硬编码场景坐标。
var _default_layout_rects: Dictionary = {}


## 初始化确认信号并保持选将遮罩默认隐藏，直到收到规则核心快照。
func _ready() -> void:
	_ensure_leader_divider()
	_required_nodes_ready = _validate_required_nodes()
	if not _required_nodes_ready:
		visible = false
		return
	BattleUIStyle.apply_interaction_button(_confirm_button)
	_confirm_button.pressed.connect(_confirm_selection)
	BattleUIStyle.apply_interaction_button(_all_characters_button)
	_all_characters_button.pressed.connect(_toggle_all_characters)
	# 候选区只允许垂直滚动；横向始终由自适应列数完整容纳，避免左右滑动寻找牌面。
	var candidate_scroll: ScrollContainer = _candidate_area as ScrollContainer
	if candidate_scroll != null:
		candidate_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		candidate_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_status_label.visible = false
	_leader_character_label.visible = false
	_leader_character_area.visible = false
	_leader_divider.visible = false
	_all_characters_button.visible = false
	_seat_buttons.visible = false
	_identity_buttons.visible = false
	_seat_selection_label.visible = false
	_identity_selection_label.visible = false
	_candidate_area_with_leader_left = _candidate_area.position.x
	_candidate_area_without_leader_left = _leader_character_area.position.x
	_candidate_area_right = _candidate_area.position.x + _candidate_area.size.x
	_candidate_default_position = _candidate_area.position
	_candidate_default_size = _candidate_area.size
	_capture_default_layout()
	refresh_ui_style()
	visible = false


## 按当前活动 UI 风格重绘选将框与候选武将牌；候选集合、临时选择和悬停补间保持不变。
func refresh_ui_style() -> void:
	if not _required_nodes_ready or not is_node_ready():
		return
	# 选将背景遮罩；保持阻断牌桌输入的行为，只更新主题透明色。
	var selection_shade: ColorRect = get_node_or_null("SelectionShade") as ColorRect
	if selection_shade != null:
		selection_shade.color = BattleUIStyle.get_color("shade")
	# 选将主框；统一使用主题选择面板与边框语义。
	var selection_frame: Panel = get_node_or_null("SelectionFrame") as Panel
	if selection_frame != null:
		selection_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("selection_panel"), BattleUIStyle.get_color("border"), 2, 6))
	_title_label.add_theme_color_override("default_color", BattleUIStyle.get_color("text_primary"))
	_title_label.add_theme_font_size_override("normal_font_size", 24)
	_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_leader_character_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_leader_divider.color = Color(BattleUIStyle.get_color("border"), 0.72)
	BattleUIStyle.apply_interaction_button(_confirm_button)
	BattleUIStyle.apply_interaction_button(_all_characters_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), _showing_all_characters)
	_seat_selection_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_identity_selection_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	for seat_button_variant: Variant in _seat_button_views.values():
		# 当前座次按钮；选中项使用强调边框，禁用项继续保留低对比度主题。
		var seat_button: Button = seat_button_variant as Button
		if seat_button != null:
			_apply_assignment_button_style(seat_button, BattleUIStyle.get_color("accent"), int(seat_button.get_meta("seat_number", -1)) == _selected_seat_number)
	for identity_variant: Variant in _identity_button_views.keys():
		# 当前身份按钮；边框使用身份语义色，使选择结果与局内身份徽记一致。
		var identity: String = str(identity_variant)
		var identity_button: Button = _identity_button_views[identity] as Button
		if identity_button != null:
			_apply_assignment_button_style(identity_button, BattleUIStyle.get_color("identity_%s" % identity, BattleUIStyle.get_color("accent")), identity == _selected_identity)
	for replacement_button_variant: Variant in _replacement_buttons.values():
		# 当前换将按钮；主题切换只重绘颜色，不改变剩余次数、悬停显隐或候选内容。
		var replacement_button: Button = replacement_button_variant as Button
		if replacement_button != null:
			BattleUIStyle.apply_interaction_button(replacement_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), true)
	if _leader_character_view != null and is_instance_valid(_leader_character_view):
		_leader_character_view.refresh_ui_style()
	for candidate_view_variant: Variant in _candidate_views.values():
		# 当前候选武将牌；只更新配色，不改变选中状态或基础位置。
		var candidate_view: PlayerTargetView = candidate_view_variant as PlayerTargetView
		if candidate_view != null and is_instance_valid(candidate_view):
			candidate_view.refresh_ui_style()
	# 当前身份标题；富文本颜色不会自动继承后续主题变化，需要按保存的本人身份重新写入。
	if visible and not _snapshot.is_empty():
		_render_header()


## 为仍在编辑器内存中的旧主场景补建领袖分隔线；新节点继续使用稳定相对路径参与统一校验和显隐。
func _ensure_leader_divider() -> void:
	if _leader_divider != null:
		return
	# 选将主框；旧场景只有在该稳定父节点存在时才能安全补建分隔线。
	var selection_frame: Control = get_node_or_null("SelectionFrame") as Control
	if selection_frame == null:
		return
	# 运行时领袖分隔线；几何和颜色与正式场景资源保持一致，编辑器重新载入场景后不会产生视觉差异。
	var runtime_leader_divider: ColorRect = ColorRect.new()
	runtime_leader_divider.name = StringName(LEADER_DIVIDER_PATH.get_name(LEADER_DIVIDER_PATH.get_name_count() - 1))
	runtime_leader_divider.position = LEADER_DIVIDER_RECT.position
	runtime_leader_divider.size = LEADER_DIVIDER_RECT.size
	runtime_leader_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	runtime_leader_divider.color = LEADER_DIVIDER_COLOR
	runtime_leader_divider.visible = false
	selection_frame.add_child(runtime_leader_divider)
	_leader_divider = runtime_leader_divider


## 接收裁剪后的选将快照并重建候选牌；任何隐藏选择都不会进入该组件。
func bind_snapshot(snapshot: Dictionary) -> void:
	if not _required_nodes_ready:
		return
	# 当前滚动位置；同一选将上下文内换将或名额刷新后恢复，避免下方候选突然跳回列表顶部。
	var candidate_scroll: ScrollContainer = _candidate_area as ScrollContainer
	# 上一份快照的垂直滚动值；新阶段不恢复，同一阶段刷新时延迟写回。
	var previous_scroll_vertical: int = candidate_scroll.scroll_vertical if candidate_scroll != null else 0
	# 是否延续同一私有选将上下文；阶段或AI目标变化时必须清除全部临时选择。
	var preserves_local_context: bool = visible and str(_snapshot.get("phase", "")) == str(snapshot.get("phase", "")) and int(_snapshot.get("target_player_id", -1)) == int(snapshot.get("target_player_id", -1))
	_snapshot = snapshot.duplicate(true)
	if not preserves_local_context:
		_selected_character_id = ""
		# 首次进入最终自选阶段时，座次和身份按钮默认高亮首次随机分配的结果；普通选将不保留这些临时值。
		_selected_seat_number = int(snapshot.get("preview_seat_number", snapshot.get("initial_seat_number", -1))) if str(snapshot.get("phase", "")) == CharacterSelectionService.PHASE_CUSTOM else -1
		_selected_identity = str(snapshot.get("preview_identity", snapshot.get("initial_identity", ""))) if str(snapshot.get("phase", "")) == CharacterSelectionService.PHASE_CUSTOM else ""
		_showing_all_characters = false
		_apply_all_characters_layout(false)
	elif str(snapshot.get("phase", "")) == CharacterSelectionService.PHASE_CUSTOM:
		# 权威预览回包；联机或其他输入源改变座次身份后以房主规范化结果覆盖本地临时状态。
		_selected_seat_number = int(snapshot.get("preview_seat_number", _selected_seat_number))
		_selected_identity = str(snapshot.get("preview_identity", _selected_identity))
	# 已确认、尚未轮到本地或仅等待其他玩家的阶段不显示空选将框，避免首任领袖确认后再次弹出无候选遮罩。
	visible = bool(_snapshot.get("can_select", false)) and not str(_snapshot.get("phase", "")).is_empty() and str(_snapshot.get("phase", "")) != CharacterSelectionService.PHASE_COMPLETE
	if not visible:
		return
	_render_header()
	_render_leader_character()
	_render_custom_assignment_controls()
	_render_candidates()
	if not _get_displayed_candidate_ids().has(_selected_character_id):
		_selected_character_id = ""
	_update_confirm_state()
	if preserves_local_context and candidate_scroll != null:
		candidate_scroll.set_deferred("scroll_vertical", previous_scroll_vertical)


## 在正式对局开始后隐藏选将遮罩并清理动态候选牌。
func close() -> void:
	visible = false
	_apply_all_characters_layout(false)
	if not _required_nodes_ready:
		_snapshot.clear()
		_selected_character_id = ""
		_selected_seat_number = -1
		_selected_identity = ""
		_showing_all_characters = false
		return
	_clear_candidates()
	_clear_leader_character()
	_snapshot.clear()
	_selected_character_id = ""
	_selected_seat_number = -1
	_selected_identity = ""
	_showing_all_characters = false
	_clear_custom_assignment_buttons()


## 渲染阶段标题、公开领袖武将与其他玩家完成数量。
## 当前界面只保留阶段标题；公开领袖武将由左侧正式牌面表达，确认进度文本保持隐藏。
func _render_header() -> void:
	# 当前选将阶段；决定本地是领袖选择、其他玩家同时选择还是等待全员完成。
	var phase: String = str(_snapshot.get("phase", ""))
	# 当前选将用途；AI调整使用相同牌面组件但不显示本人身份、座次或身份按钮。
	var selection_kind: String = str(_snapshot.get("selection_kind", "initial"))
	# 本地是否可以选择；已经确认的玩家只看到等待提示，不再显示候选内容。
	var can_select: bool = bool(_snapshot.get("can_select", false))
	if selection_kind == "ai_adjustment":
		_title_label.clear()
		_title_label.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
		_title_label.append_text("请为%s选择武将" % str(_snapshot.get("target_display_name", "AI角色")))
		_title_label.pop()
		_status_label.text = ""
		return
	if bool(_snapshot.get("allow_custom_assignment", false)):
		# 首次分配身份；自选阶段继续明确展示，最终座次身份只在全员确认后刷新到权威玩家状态。
		var initial_identity: String = str(_snapshot.get("local_identity", "hidden"))
		_set_identity_title(initial_identity, "请重新选择武将、座次与身份" if can_select else "请等待其他玩家完成自选")
		_status_label.text = ""
		return
	# 本地真实身份；选将服务只把该字段发送给本人，旧快照在领袖阶段使用领袖身份作为兼容回退。
	var local_identity: String = str(_snapshot.get("local_identity", "leader" if phase == CharacterSelectionService.PHASE_LEADER else "hidden"))
	_set_identity_title(local_identity, "请选择武将" if can_select else "请等待其他玩家选将")
	_status_label.text = ""


## 使用阵营语义色写入“你的身份为：身份，提示”标题；身份只来自观察者自己的裁剪选将快照。
func _set_identity_title(identity: String, action_text: String) -> void:
	# 玩家可见身份名称；未知旧快照使用“未知”保持标题完整，不推断其他角色身份。
	var identity_name: String = {"leader":"领袖", "loyalist":"忠臣", "rebel":"反贼", "renegade":"内奸"}.get(identity, "未知")
	# 当前身份语义色；四种身份分别固定使用红、黄、绿、蓝，未知身份回退主题次级文字色。
	_rendered_identity_color = BattleUIStyle.get_color("identity_%s" % identity, BattleUIStyle.get_color("text_secondary"))
	_title_label.clear()
	_title_label.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_title_label.append_text("你的身份为：")
	_title_label.push_color(_rendered_identity_color)
	_title_label.append_text(identity_name)
	_title_label.pop()
	_title_label.append_text("，%s" % action_text)
	_title_label.pop()


## 返回选将标题的纯文本内容；测试与无障碍适配可读取该值，不解析富文本控制代码。
func get_title_plain_text() -> String:
	return _title_label.get_parsed_text() if _title_label != null else ""


## 返回当前标题身份片段的阵营色；只读接口不允许调用方修改主题或身份。
func get_title_identity_color() -> Color:
	return _rendered_identity_color


## 在选将框左侧渲染已经公开的领袖武将牌；领袖阶段尚未确认时保持该区域隐藏。
func _render_leader_character() -> void:
	_clear_leader_character()
	# 自选阶段继续显示首次身份分配产生的公开领袖武将，只有AI调整用途不显示该只读区域。
	if str(_snapshot.get("selection_kind", "initial")) == "ai_adjustment":
		_update_leader_partition(false)
		return
	# 已公开领袖武将 ID；空字符串表示领袖尚未完成选择，不创建占位牌。
	var leader_character_id: String = str(_snapshot.get("leader_character_id", ""))
	if leader_character_id.is_empty():
		_update_leader_partition(false)
		return
	# 领袖武将定义；用于左侧正式牌面的体力、势力、名称与插画。
	var character_definition: Dictionary = GameDatabase.get_character(leader_character_id)
	# 领袖势力定义；只提供牌面主题，不参与身份或阵营判定。
	var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
	_leader_character_view = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	_leader_character_area.add_child(_leader_character_view)
	_leader_character_view.information_requested.connect(information_requested.emit)
	_leader_character_view.information_dismissed.connect(information_dismissed.emit)
	# 领袖只读牌面快照；不显示手牌数与对局装备，只表达已公开的武将选择。
	var leader_snapshot: Dictionary = {
		"player_id":int(_snapshot.get("leader_player_id", -1)),
		"display_name":"领袖",
		"character_id":leader_character_id,
		"character_revealed":true,
		"identity":"leader",
		"hp":int(character_definition.get("max_hp", 4)),
		"max_hp":int(character_definition.get("max_hp", 4)),
		"alive":true,
		"chained":false,
		"hand_count":0,
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage_count":0,
	}
	_leader_character_view.configure_snapshot(leader_snapshot, character_definition, false, faction_definition)
	_leader_character_view.set_operation_state(false)
	_leader_character_view.scale = Vector2.ONE * leader_character_scale
	_leader_character_view.position = (_leader_character_area.size - _leader_character_view.card_size * leader_character_scale) * 0.5
	_leader_character_area.visible = true
	_leader_character_label.visible = true
	_update_leader_partition(true)


## 使用正式 Node2D 武将牌横向排列本地候选；候选数量由快照决定，可从默认5张继续扩展。
func _render_candidates() -> void:
	_clear_candidates()
	# 本地可见候选数组；未轮到本地或已经确认时为空，不创建占位按钮。
	# 自选与AI调整开启全部武将入口时，服务快照会显式提供额外全量合法集合，界面仍不自行扫描或伪造规则候选。
	# 当前玩家候选数组；具体选择必须来自服务生成的五张候选牌。
	# “五张”是历史默认值；实际快照可包含1至20张普通随机候选及额外领袖技固定候选。
	var candidate_ids: Array = _get_displayed_candidate_ids()
	if candidate_ids.is_empty():
		_confirm_button.visible = false
		return
	_confirm_button.visible = true
	_confirm_button.text = "请选择武将牌"
	# 本人剩余换将卡；按钮只在随机候选视图、次数大于0且候选未锁定时创建。
	var replacement_cards_remaining: int = int(_snapshot.get("replacement_cards_remaining", 0))
	# 不可换将候选；领袖技固定武将由权威服务放入该集合，界面不自行识别技能。
	var locked_candidate_ids: Array = _snapshot.get("locked_candidate_ids", []) as Array
	for candidate_index: int in range(candidate_ids.size()):
		# 当前候选武将 ID；点击与确认只使用该稳定 ID。
		var character_id: String = str(candidate_ids[candidate_index])
		# 当前武将定义；用于体力、势力、技能说明和正式牌面插画渲染。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		# 当前势力定义；候选牌与局内角色牌共用同一圆徽配色来源。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
		# 正式武将牌节点；根类型为 Node2D，透明输入区域负责点击。
		var character_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
		_candidate_content.add_child(character_view)
		character_view.information_requested.connect(information_requested.emit)
		character_view.information_dismissed.connect(information_dismissed.emit)
		# 候选牌快照；只包含表现所需字段，不伪造玩家规则状态或加入对局玩家数组。
		var candidate_snapshot: Dictionary = {
			"player_id":candidate_index,
			"display_name":"候选武将",
			"character_id":character_id,
			"character_revealed":true,
			"identity":"hidden",
			"hp":int(character_definition.get("max_hp", 4)),
			"max_hp":int(character_definition.get("max_hp", 4)),
			"alive":true,
			"chained":false,
			"hand_count":0,
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage_count":0,
		}
		character_view.configure_snapshot(candidate_snapshot, character_definition, false, faction_definition)
		character_view.pressed.connect(_select_candidate.bind(character_id))
		character_view.hover_changed.connect(_on_candidate_hover_changed.bind(character_id))
		_candidate_views[character_id] = character_view
		if not _showing_all_characters and replacement_cards_remaining > 0 and not locked_candidate_ids.has(character_id):
			# 单张候选换将按钮；默认隐藏，只有鼠标停留在对应牌面或按钮自身上方时显示。
			var replacement_button: Button = Button.new()
			replacement_button.custom_minimum_size = Vector2(REPLACEMENT_BUTTON_WIDTH, REPLACEMENT_BUTTON_HEIGHT)
			replacement_button.size = replacement_button.custom_minimum_size
			replacement_button.text = "换将"
			replacement_button.tooltip_text = "剩余换将卡：%d" % replacement_cards_remaining
			replacement_button.visible = false
			replacement_button.z_index = 20
			replacement_button.mouse_filter = Control.MOUSE_FILTER_STOP
			BattleUIStyle.apply_interaction_button(replacement_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), true)
			replacement_button.pressed.connect(_request_candidate_replacement.bind(character_id))
			replacement_button.mouse_entered.connect(_show_replacement_button.bind(character_id))
			replacement_button.mouse_exited.connect(_queue_replacement_button_visibility_refresh.bind(character_id))
			_candidate_content.add_child(replacement_button)
			_replacement_buttons[character_id] = replacement_button
	# 当前是否使用全部武将多行布局；随机候选超出一行时同样使用原尺寸垂直滚动。
	var uses_all_character_layout: bool = _showing_all_characters
	# 普通布局左边界；存在公开领袖时保留左侧牌位，否则使用无领袖的扩展区域。
	var normal_candidate_left: float = _candidate_area_with_leader_left if not str(_snapshot.get("leader_character_id", "")).is_empty() else _candidate_area_without_leader_left
	if not uses_all_character_layout:
		_candidate_area.position = Vector2(normal_candidate_left, _candidate_default_position.y)
		_candidate_area.size = Vector2(maxf(_candidate_area_right - normal_candidate_left, 0.0), _candidate_default_size.y)
	# 第一张正式候选牌；其场景尺寸是全部候选布局的唯一牌宽来源，避免桌面脚本重复保存几何常量。
	var first_character_view: PlayerTargetView = _candidate_views[str(candidate_ids[0])] as PlayerTargetView
	# 单张武将牌宽度；直接读取正式3:4牌面，不创建选将专用尺寸或硬编码副本。
	var card_width: float = first_character_view.card_size.x
	# 单张武将牌高度；多行全部武将布局同时使用该正式尺寸计算缩放。
	var card_height: float = first_character_view.card_size.y
	# 当前列数；按原尺寸牌面和区域宽度自动铺满，任何模式都不会为容纳更多候选缩小武将牌。
	var usable_width: float = maxf(_candidate_area.size.x - 16.0, card_width)
	# 当前区域最多可容纳列数；预留16像素给纵向滚动条及其安全间距。
	var maximum_column_count: int = maxi(int(floor((usable_width + candidate_gap) / (card_width + candidate_gap))), 1)
	# 实际列数；候选不足一整行时按实际数量收紧并保持整行居中。
	var column_count: int = mini(maximum_column_count, candidate_ids.size())
	# 当前行数；超过一行时由候选区垂直滚动，确认按钮始终位于滚动区外。
	var row_count: int = ceili(float(candidate_ids.size()) / float(maxi(column_count, 1)))
	# 单行或单行宽度；每一行独立居中，最后一行不足列数时不会偏向左侧。
	var scaled_card_width: float = card_width
	# 原尺寸牌高；候选滚动只增加内容高度，不缩放牌面。
	var scaled_card_height: float = card_height
	# 每行换将按钮预留高度；全武将入口和已用尽次数时为0，牌面直接从行首开始。
	var replacement_strip_height: float = REPLACEMENT_BUTTON_HEIGHT + REPLACEMENT_BUTTON_GAP if not _showing_all_characters and not _replacement_buttons.is_empty() else 0.0
	# 单行槽位高度；按钮与牌面属于同一固定槽位，悬停显隐不会造成后续行位移。
	var row_slot_height: float = replacement_strip_height + scaled_card_height
	# 全部候选占用宽度；用于在候选区域中水平居中，并支持后续调整候选数量。
	# 多行布局中该值表示完整行的最大宽度；普通单行布局继续等于全部候选的实际占用宽度。
	var total_width: float = scaled_card_width * float(column_count) + candidate_gap * float(maxi(column_count - 1, 0))
	# 首张候选横坐标；区域宽度不足时从0开始，避免产生负坐标裁切。
	# 最后一行数量不足时会在循环内重新计算该行起点，其余完整行复用此值。
	var start_x: float = maxf((_candidate_area.size.x - total_width) * 0.5, 0.0)
	for candidate_index: int in range(candidate_ids.size()):
		# 当前候选武将 ID；用于按快照顺序取回已经创建的正式武将牌视图。
		var character_id: String = str(candidate_ids[candidate_index])
		# 当前候选武将牌；只更新布局位置，不重复配置数据或信号。
		# 全部武将模式额外更新同一节点的基础缩放，仍不重复配置牌面数据或连接信号。
		var character_view: PlayerTargetView = _candidate_views[character_id] as PlayerTargetView
		# 当前行列索引；全部武将按多行排列，普通候选行索引始终为0。
		var row_index: int = candidate_index / maxi(column_count, 1)
		# 当前列索引；每行从0开始并按原尺寸牌宽与间距递增。
		var column_index: int = candidate_index % maxi(column_count, 1)
		# 当前行实际卡牌数量；最后一行可能少于最大列数，需要单独计算居中起点。
		var row_item_count: int = mini(column_count, candidate_ids.size() - row_index * column_count)
		# 当前行实际宽度；用于让不满列的末行独立居中。
		var row_width: float = scaled_card_width * float(row_item_count) + candidate_gap * float(maxi(row_item_count - 1, 0))
		# 当前行起点；完整行沿用统一start_x，最后一行按实际牌数单独居中。
		var row_start_x: float = start_x if row_item_count == column_count else maxf((_candidate_area.size.x - row_width) * 0.5, 0.0)
		# 当前行顶部；行间只使用统一候选间距，不因某张牌是否锁定而改变高度。
		var row_top: float = float(row_index) * (row_slot_height + candidate_gap)
		# 当前牌面基础位置；换将按钮预留条位于其正上方且不参与悬停缩放中心。
		var base_position: Vector2 = Vector2(row_start_x + float(column_index) * (scaled_card_width + candidate_gap), row_top + replacement_strip_height)
		character_view.scale = Vector2.ONE
		character_view.position = base_position
		_candidate_base_positions[character_id] = base_position
		_candidate_base_scales[character_id] = 1.0
		# 当前候选换将按钮；水平居中位于牌面正上方，锁定候选不创建按钮但仍保留同一行顶部空间。
		var replacement_button: Button = _replacement_buttons.get(character_id) as Button
		if replacement_button != null:
			replacement_button.position = Vector2(base_position.x + (card_width - REPLACEMENT_BUTTON_WIDTH) * 0.5, row_top)
	# 滚动内容尺寸；至少等于可视区域，超出时ScrollContainer自动启用垂直滚动条。
	var content_height: float = row_slot_height * float(row_count) + candidate_gap * float(maxi(row_count - 1, 0))
	_candidate_content.custom_minimum_size = Vector2(maxf(_candidate_area.size.x - 16.0, 0.0), maxf(content_height, _candidate_area.size.y))
	_candidate_content.size = _candidate_content.custom_minimum_size


## 返回当前需要展示的候选武将；“所有武将”开启时使用静态全量列表，否则使用本次随机候选。
func _get_displayed_candidate_ids() -> Array:
	if _showing_all_characters and bool(_snapshot.get("allow_all_characters", false)):
		return (_snapshot.get("all_character_ids", []) as Array).duplicate()
	return (_snapshot.get("local_candidates", []) as Array).duplicate()


## 渲染“所有武将”入口以及自选座次、身份按钮；AI 调整选将只显示全部武将入口。
func _render_custom_assignment_controls() -> void:
	_clear_custom_assignment_buttons()
	# 是否允许展开全部武将；初次自选与启用联动设置后的 AI 调整都可显示。
	var allow_all_characters: bool = bool(_snapshot.get("allow_all_characters", false))
	_all_characters_button.visible = allow_all_characters and bool(_snapshot.get("can_select", false))
	_all_characters_button.text = "随机候选" if _showing_all_characters else "所有武将"
	# 是否允许选择座次与身份；AI 调整阶段明确关闭这两组控件。
	var allow_custom_assignment: bool = bool(_snapshot.get("allow_custom_assignment", false)) and bool(_snapshot.get("can_select", false)) and str(_snapshot.get("phase", "")) == CharacterSelectionService.PHASE_CUSTOM and not _showing_all_characters
	_seat_buttons.visible = allow_custom_assignment
	_identity_buttons.visible = allow_custom_assignment
	_seat_selection_label.visible = allow_custom_assignment
	_identity_selection_label.visible = allow_custom_assignment
	if not allow_custom_assignment:
		refresh_ui_style()
		return
	# 当前仍可提交的座次；已被其他玩家确认的按钮仍显示，但处于禁用状态。
	var available_seats: Array = _snapshot.get("seat_options", []) as Array
	# 本局总座次数；按钮数量必须等于场上总玩家数。
	var player_count: int = int(_snapshot.get("player_count", available_seats.size()))
	for seat_number: int in range(1, player_count + 1):
		# 当前座次按钮；使用元数据保存数字，不从中文文本反向解析。
		var seat_button: Button = Button.new()
		seat_button.custom_minimum_size = Vector2(58.0, 34.0)
		seat_button.text = "%d号位" % seat_number
		seat_button.disabled = not available_seats.has(seat_number)
		seat_button.set_meta("seat_number", seat_number)
		seat_button.pressed.connect(_select_seat.bind(seat_number))
		_seat_buttons.add_child(seat_button)
		_seat_button_views[seat_number] = seat_button
	# 当前仍有名额的身份；四种身份始终显示，名额耗尽时禁用。
	var available_identities: Array = _snapshot.get("identity_options", []) as Array
	for identity_option: Dictionary in IDENTITY_OPTIONS:
		# 当前身份稳定 ID 与显示名；按钮颜色由主题身份语义色决定。
		var identity: String = str(identity_option.get("id", ""))
		var identity_button: Button = Button.new()
		identity_button.custom_minimum_size = Vector2(112.0, 34.0)
		identity_button.text = str(identity_option.get("label", identity))
		identity_button.disabled = not available_identities.has(identity)
		identity_button.pressed.connect(_select_identity.bind(identity))
		_identity_buttons.add_child(identity_button)
		_identity_button_views[identity] = identity_button
	refresh_ui_style()


## 切换随机候选与全部武将列表；临时座次和身份选择保持不变。
func _toggle_all_characters() -> void:
	if not bool(_snapshot.get("allow_all_characters", false)):
		return
	_showing_all_characters = not _showing_all_characters
	_apply_all_characters_layout(_showing_all_characters)
	_all_characters_button.text = "随机候选" if _showing_all_characters else "所有武将"
	# 当前武将若不在切换后的展示列表中，清除临时选择防止确认不可见牌面。
	var displayed_candidates: Array = _get_displayed_candidate_ids()
	if not displayed_candidates.has(_selected_character_id):
		_selected_character_id = ""
	_render_custom_assignment_controls()
	_render_candidates()
	_update_confirm_state()
	refresh_ui_style()


## 选择一个临时座次；一号位自动联动领袖，离开一号位时清除仍残留的领袖身份。
func _select_seat(seat_number: int) -> void:
	_selected_seat_number = seat_number
	if seat_number == 1:
		_selected_identity = "leader"
	elif _selected_identity == "leader":
		_selected_identity = ""
	_update_custom_button_states()
	_update_confirm_state()
	_request_custom_assignment_preview()


## 选择一个临时身份；领袖自动联动一号位，选择其他身份时清除仍残留的一号位。
func _select_identity(identity: String) -> void:
	_selected_identity = identity
	if identity == "leader":
		_selected_seat_number = 1
	elif _selected_seat_number == 1:
		_selected_seat_number = -1
	_update_custom_button_states()
	_update_confirm_state()
	_request_custom_assignment_preview()


## 向牌桌请求当前有效座次身份组合的权威预览；未完成领袖联动的半成品不提前改写所有角色展示。
func _request_custom_assignment_preview() -> void:
	if str(_snapshot.get("phase", "")) != CharacterSelectionService.PHASE_CUSTOM or _selected_seat_number < 1 or _selected_identity.is_empty():
		return
	custom_assignment_preview_requested.emit(_selected_seat_number, _selected_identity)


## 同步动态座次与身份按钮的选中主题；禁用状态保持服务快照提供的名额结果。
func _update_custom_button_states() -> void:
	for seat_number_variant: Variant in _seat_button_views.keys():
		# 当前座次按钮；选中项使用强调状态。
		var seat_number: int = int(seat_number_variant)
		var seat_button: Button = _seat_button_views[seat_number] as Button
		_apply_assignment_button_style(seat_button, BattleUIStyle.get_color("accent"), seat_number == _selected_seat_number)
	for identity_variant: Variant in _identity_button_views.keys():
		# 当前身份按钮；使用对应身份语义色作为边框。
		var identity: String = str(identity_variant)
		var identity_button: Button = _identity_button_views[identity] as Button
		_apply_assignment_button_style(identity_button, BattleUIStyle.get_color("identity_%s" % identity, BattleUIStyle.get_color("accent")), identity == _selected_identity)


## 为座次与身份按钮应用明确选中反馈；选中项同时改变背景、边框和字体色，未选项保持普通操作色。
func _apply_assignment_button_style(button: Button, border_color: Color, selected: bool) -> void:
	# 选中背景色；从主题操作底色向语义边框色混合，保持文字可读且在两套主题中都有明显变化。
	var background_color: Color = BattleUIStyle.get_color("action_button").lerp(border_color, 0.34) if selected else BattleUIStyle.get_color("action_button")
	BattleUIStyle.apply_interaction_button(button, background_color, border_color, selected)
	if selected:
		button.add_theme_color_override("font_color", border_color)
		button.add_theme_color_override("font_hover_color", border_color.lightened(0.12))
		button.add_theme_color_override("font_pressed_color", border_color.lightened(0.18))
		button.add_theme_color_override("font_focus_color", border_color)
	else:
		button.add_theme_color_override("font_focus_color", BattleUIStyle.get_color("button_font"))


## 清理动态座次与身份按钮；每次私有快照变化后按最新可用名额重建。
func _clear_custom_assignment_buttons() -> void:
	_seat_button_views.clear()
	_identity_button_views.clear()
	if _seat_buttons != null:
		for child: Node in _seat_buttons.get_children():
			_seat_buttons.remove_child(child)
			child.queue_free()
	if _identity_buttons != null:
		for child: Node in _identity_buttons.get_children():
			_identity_buttons.remove_child(child)
			child.queue_free()


## 更新本地临时选择和候选牌边框；规则状态在确认按钮点击前保持不变。
func _select_candidate(character_id: String) -> void:
	_selected_character_id = character_id
	for candidate_id_variant: Variant in _candidate_views.keys():
		# 当前候选 ID；与临时选择相同时显示金色选中边框。
		var candidate_id: String = str(candidate_id_variant)
		# 当前候选牌视图；映射只在本次候选重绘期间有效。
		var candidate_view: PlayerTargetView = _candidate_views[candidate_id] as PlayerTargetView
		candidate_view.set_target_state(false, candidate_id == _selected_character_id)
	_update_confirm_state()


## 根据当前武将、座次与身份临时值更新确认按钮；AI 调整模式只要求选择武将。
func _update_confirm_state() -> void:
	# 自选模式完整性；普通选将与 AI 调整不要求座次和身份字段。
	var requires_assignment: bool = bool(_snapshot.get("allow_custom_assignment", false))
	var assignment_complete: bool = not requires_assignment or (_selected_seat_number >= 1 and not _selected_identity.is_empty())
	_confirm_button.disabled = _selected_character_id.is_empty() or not assignment_complete
	if _selected_character_id.is_empty():
		_confirm_button.text = "请选择武将牌"
	elif requires_assignment and not assignment_complete:
		_confirm_button.text = "请选择座次与身份"
	else:
		_confirm_button.text = "确认选择：%s" % GameDatabase.resolve_character_name(_selected_character_id)


## 发出稳定武将 ID 选择请求；权威服务仍会再次校验阶段、玩家和候选列表。
func _confirm_selection() -> void:
	if _selected_character_id.is_empty() or not bool(_snapshot.get("can_select", false)) or _confirm_button.disabled:
		return
	_confirm_button.disabled = true
	# 完整选将数据；普通模式的座次为-1、身份为空，AI调整模式额外携带目标玩家 ID。
	var selection_data: Dictionary = {
		"selection_kind":str(_snapshot.get("selection_kind", "initial")),
		"character_id":_selected_character_id,
		"seat_number":_selected_seat_number,
		"identity":_selected_identity,
		"target_player_id":int(_snapshot.get("target_player_id", -1)),
	}
	selection_submitted.emit(selection_data)
	character_selected.emit(_selected_character_id)


## 清理所有动态候选牌；每次阶段快照重建，避免保留旧输入连接或高亮状态。
func _clear_candidates() -> void:
	for hover_tween_variant: Variant in _candidate_hover_tweens.values():
		# 当前候选缩放补间；候选节点释放前先停止，避免结束回调继续访问旧节点。
		var hover_tween: Tween = hover_tween_variant as Tween
		if hover_tween != null and hover_tween.is_valid():
			hover_tween.kill()
	_candidate_hover_tweens.clear()
	_candidate_base_positions.clear()
	_candidate_base_scales.clear()
	_candidate_views.clear()
	_replacement_buttons.clear()
	for child: Node in _candidate_content.get_children():
		_candidate_content.remove_child(child)
		child.queue_free()
	_candidate_content.custom_minimum_size = Vector2.ZERO


## 清理左侧领袖武将牌；阶段切换和重新开局时不会保留旧局节点。
func _clear_leader_character() -> void:
	_leader_character_view = null
	_leader_character_area.visible = false
	_leader_character_label.visible = false
	_leader_divider.visible = false
	for child: Node in _leader_character_area.get_children():
		_leader_character_area.remove_child(child)
		child.queue_free()


## 根据领袖是否已公开调整候选区域与分隔线；没有领袖时候选直接从原领袖区域左边缘开始排列。
func _update_leader_partition(has_public_leader: bool) -> void:
	if _candidate_area == null or _leader_divider == null:
		return
	# 当前候选区域左边界；有领袖时保留只读牌与竖线，没有领袖时直接占用全部横向空间。
	var candidate_left: float = _candidate_area_with_leader_left if has_public_leader else _candidate_area_without_leader_left
	_candidate_area.position.x = candidate_left
	_candidate_area.size.x = maxf(_candidate_area_right - candidate_left, 0.0)
	_leader_divider.visible = has_public_leader


## 播放候选武将居中缩放；鼠标移走时使用相同时长平滑恢复基础位置与1倍尺寸。
func _on_candidate_hover_changed(hovered: bool, character_id: String) -> void:
	# 当前候选武将牌；快照重建后旧悬停信号可能迟到，无有效节点时直接忽略。
	var character_view: PlayerTargetView = _candidate_views.get(character_id) as PlayerTargetView
	if character_view == null or not is_instance_valid(character_view) or not _candidate_base_positions.has(character_id) or not _candidate_base_scales.has(character_id):
		return
	if hovered:
		_show_replacement_button(character_id)
	else:
		_queue_replacement_button_visibility_refresh(character_id)
	# 当前候选已有补间；新的进入或离开状态应从实时变换继续，不叠加第二个写入者。
	var previous_tween: Tween = _candidate_hover_tweens.get(character_id) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	# 当前目标缩放；离开时固定恢复1倍，进入时使用检查器配置倍数。
	# 普通候选继续遵循上述1倍语义；多行全武将候选则以自动计算的基础比例替代1倍。
	# 当前基础缩放；普通候选为1，全部武将多行布局会按区域自动缩小。
	var base_scale_value: float = float(_candidate_base_scales.get(character_id, 1.0))
	# 当前目标缩放；离开时恢复基础比例，进入时相对基础比例应用悬停倍数。
	var target_scale_value: float = base_scale_value * (candidate_hover_scale if hovered else 1.0)
	# 当前基础位置；缩放时向左上补偿半个尺寸差，使武将牌围绕视觉中心放大。
	var base_position: Vector2 = _candidate_base_positions[character_id]
	# 当前目标位置；Node2D 默认以左上角为原点，因此需要显式中心补偿。
	var target_position: Vector2 = base_position - character_view.card_size * (target_scale_value - base_scale_value) * 0.5
	character_view.z_index = 10 if hovered else 0
	if candidate_hover_transition_seconds <= 0.0:
		character_view.scale = Vector2.ONE * target_scale_value
		character_view.position = target_position
		return
	# 当前悬停补间；位置与缩放并行使用二次缓出，进入和恢复都保持一致节奏。
	var hover_tween: Tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(character_view, "scale", Vector2.ONE * target_scale_value, candidate_hover_transition_seconds)
	hover_tween.tween_property(character_view, "position", target_position, candidate_hover_transition_seconds)
	_candidate_hover_tweens[character_id] = hover_tween
	hover_tween.finished.connect(_on_candidate_hover_tween_finished.bind(character_id, hover_tween))


## 清理已经完成的候选悬停补间索引；只有映射仍指向同一补间时才删除。
func _on_candidate_hover_tween_finished(character_id: String, hover_tween: Tween) -> void:
	if _candidate_hover_tweens.get(character_id) == hover_tween:
		_candidate_hover_tweens.erase(character_id)


## 直接显示指定候选的换将按钮；锁定候选或次数用尽时映射中不存在按钮，因此保持无入口状态。
func _show_replacement_button(character_id: String) -> void:
	# 当前候选换将按钮；只有权威快照允许的普通候选才会创建。
	var replacement_button: Button = _replacement_buttons.get(character_id) as Button
	if replacement_button != null and is_instance_valid(replacement_button):
		replacement_button.visible = true


## 延迟检查鼠标是否仍位于牌面或按钮；从牌面移动到上方按钮时不会在两者交界处闪退。
func _queue_replacement_button_visibility_refresh(character_id: String) -> void:
	call_deferred("_refresh_replacement_button_visibility", character_id)


## 根据实时鼠标位置刷新单个换将按钮；离开牌面和按钮后隐藏，进入任一范围时保持显示。
func _refresh_replacement_button_visibility(character_id: String) -> void:
	# 当前换将按钮；候选快照重建后旧延迟调用会安全忽略无效实例。
	var replacement_button: Button = _replacement_buttons.get(character_id) as Button
	# 当前候选武将牌；用于按正式牌面矩形判断鼠标是否仍停留。
	var character_view: PlayerTargetView = _candidate_views.get(character_id) as PlayerTargetView
	if replacement_button == null or character_view == null or not is_instance_valid(replacement_button) or not is_instance_valid(character_view):
		return
	# 当前鼠标画布坐标；按钮和Node2D牌面分别使用自身全局变换判断命中。
	var mouse_position: Vector2 = get_global_mouse_position()
	# 鼠标是否位于换将按钮；从牌面进入按钮时保持入口可见。
	var over_button: bool = replacement_button.get_global_rect().has_point(mouse_position)
	# 牌面局部鼠标坐标；正式武将牌原点位于左上角，card_size提供稳定3:4命中矩形。
	var character_local_mouse_position: Vector2 = character_view.get_global_transform().affine_inverse() * mouse_position
	# 鼠标是否位于候选牌面；离开牌面和按钮后才隐藏入口。
	var over_character: bool = Rect2(Vector2.ZERO, character_view.card_size).has_point(character_local_mouse_position)
	replacement_button.visible = over_button or over_character


## 提交单张候选换将请求并暂时禁用全部换将按钮；下一份权威快照会重建剩余次数与候选。
func _request_candidate_replacement(character_id: String) -> void:
	for replacement_button_variant: Variant in _replacement_buttons.values():
		# 当前换将按钮；统一禁用可防止网络往返期间连续点击重复消耗。
		var replacement_button: Button = replacement_button_variant as Button
		if replacement_button != null:
			replacement_button.disabled = true
	candidate_replacement_requested.emit(character_id)


## 缓存普通选将模式使用的稳定节点矩形；全武将模式退出后依此恢复原布局。
func _capture_default_layout() -> void:
	if _selection_frame == null:
		return
	_default_layout_rects = {
		"frame_offsets":Rect2(Vector2(_selection_frame.offset_left, _selection_frame.offset_top), Vector2(_selection_frame.offset_right, _selection_frame.offset_bottom)),
		"title":Rect2(_title_label.position, _title_label.size),
		"all_characters_button":Rect2(_all_characters_button.position, _all_characters_button.size),
		"candidate_area":Rect2(_candidate_area.position, _candidate_area.size),
		"confirm_button":Rect2(_confirm_button.position, _confirm_button.size),
	}


## 在全部武将模式中扩展主框和滚动候选区；确认按钮固定在主框底部且始终位于滚动区外。
func _apply_all_characters_layout(enabled: bool) -> void:
	if _selection_frame == null or _default_layout_rects.is_empty():
		return
	if not enabled:
		# 普通主框锚点；场景使用中心锚定的1040×600布局，退出全武将时恢复原偏移。
		var frame_offsets: Rect2 = _default_layout_rects.get("frame_offsets", Rect2(-520.0, -300.0, 1040.0, 600.0)) as Rect2
		_selection_frame.anchor_left = 0.5
		_selection_frame.anchor_top = 0.5
		_selection_frame.anchor_right = 0.5
		_selection_frame.anchor_bottom = 0.5
		_selection_frame.offset_left = frame_offsets.position.x
		_selection_frame.offset_top = frame_offsets.position.y
		_selection_frame.offset_right = frame_offsets.size.x
		_selection_frame.offset_bottom = frame_offsets.size.y
		_restore_control_rect(_title_label, _default_layout_rects.get("title", Rect2()) as Rect2)
		_restore_control_rect(_all_characters_button, _default_layout_rects.get("all_characters_button", Rect2()) as Rect2)
		_restore_control_rect(_candidate_area, _default_layout_rects.get("candidate_area", Rect2()) as Rect2)
		_restore_control_rect(_confirm_button, _default_layout_rects.get("confirm_button", Rect2()) as Rect2)
		_render_leader_character()
		return
	# 全武将模式只展示当前全量列表；首任领袖牌与分隔线必须同时隐藏，不能残留在扩展面板背景。
	_leader_character_area.visible = false
	_leader_character_label.visible = false
	_leader_divider.visible = false
	_selection_frame.anchor_left = 0.0
	_selection_frame.anchor_top = 0.0
	_selection_frame.anchor_right = 1.0
	_selection_frame.anchor_bottom = 1.0
	_selection_frame.offset_left = ALL_CHARACTERS_FRAME_MARGIN
	_selection_frame.offset_top = ALL_CHARACTERS_FRAME_MARGIN
	_selection_frame.offset_right = -ALL_CHARACTERS_FRAME_MARGIN
	_selection_frame.offset_bottom = -ALL_CHARACTERS_FRAME_MARGIN
	# 全屏主框实际尺寸；锚点和偏移赋值后可直接用于内部稳定矩形计算。
	var frame_size: Vector2 = _selection_frame.size
	_restore_control_rect(_title_label, Rect2(24.0, 18.0, maxf(frame_size.x - 222.0, 0.0), 36.0))
	_restore_control_rect(_all_characters_button, Rect2(maxf(frame_size.x - 188.0, 24.0), 16.0, 164.0, 38.0))
	_restore_control_rect(_confirm_button, Rect2(maxf((frame_size.x - 260.0) * 0.5, 24.0), maxf(frame_size.y - 66.0, 68.0), 260.0, 48.0))
	# 候选滚动区；上方避开标题，下方停在固定确认按钮之前。
	var candidate_bottom: float = _confirm_button.position.y - ALL_CHARACTERS_CONFIRM_GAP
	_restore_control_rect(_candidate_area, Rect2(24.0, 68.0, maxf(frame_size.x - 48.0, 0.0), maxf(candidate_bottom - 68.0, 0.0)))


## 把缓存或计算得到的局部矩形写回控件；位置与尺寸同时更新，不改变节点锚点或输入行为。
func _restore_control_rect(control: Control, rect: Rect2) -> void:
	if control == null:
		return
	control.position = rect.position
	control.size = rect.size


## 校验选将组件依赖的静态节点；缺失时只输出一条包含全部节点名的长期诊断信息。
func _validate_required_nodes() -> bool:
	# 缺失节点名称数组；完整收集后一次性输出，避免每个 visible/text 赋值分别产生空实例错误。
	var missing_node_names: Array[String] = []
	if _title_label == null:
		missing_node_names.append(str(TITLE_LABEL_PATH))
	if _status_label == null:
		missing_node_names.append(str(STATUS_LABEL_PATH))
	if _candidate_area == null:
		missing_node_names.append(str(CANDIDATE_AREA_PATH))
	if _candidate_content == null:
		missing_node_names.append(str(CANDIDATE_CONTENT_PATH))
	if _selection_frame == null:
		missing_node_names.append("SelectionFrame")
	if _leader_character_area == null:
		missing_node_names.append(str(LEADER_CHARACTER_AREA_PATH))
	if _leader_character_label == null:
		missing_node_names.append(str(LEADER_CHARACTER_LABEL_PATH))
	if _leader_divider == null:
		missing_node_names.append(str(LEADER_DIVIDER_PATH))
	if _confirm_button == null:
		missing_node_names.append(str(CONFIRM_BUTTON_PATH))
	if _all_characters_button == null:
		missing_node_names.append(str(ALL_CHARACTERS_BUTTON_PATH))
	if _seat_buttons == null:
		missing_node_names.append(str(SEAT_BUTTONS_PATH))
	if _identity_buttons == null:
		missing_node_names.append(str(IDENTITY_BUTTONS_PATH))
	if _seat_selection_label == null:
		missing_node_names.append("SelectionFrame/SeatSelectionLabel")
	if _identity_selection_label == null:
		missing_node_names.append("SelectionFrame/IdentitySelectionLabel")
	if missing_node_names.is_empty():
		return true
	push_error("选将界面缺少必需节点：%s" % "、".join(missing_node_names))
	return false
