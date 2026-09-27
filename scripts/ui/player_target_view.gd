class_name PlayerTargetView
extends Node2D

## 可复用的角色状态与目标选择组件。组件渲染公开信息、反馈合法性并转发点击，不读取规则核心。

## 武将牌被点击时发出的信号；桌面据此更新目标选择，不直接提交规则动作。
signal pressed

## 未知身份徽记被点击时发出的信号；桌面只保存本地标注，不把标注写回规则快照。
signal identity_pressed(player_id: int)

## 鼠标进入或离开武将牌时发出的信号；选将界面据此播放候选缩放，局内名称阴影由本组件自行处理。
signal hover_changed(hovered: bool)

## 正式对局武将牌被鼠标右键释放时发出的详情请求；内容只包含公开快照和静态展示定义副本。
signal details_requested(snapshot: Dictionary, character_definition: Dictionary, faction_definition: Dictionary)

## 鼠标进入武将牌静态资料或其他玩家公开装备横条时发出的统一信息请求。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开武将牌静态资料、公开装备横条或武将牌时发出的统一信息关闭请求。
signal information_dismissed

## 武将牌位于可滚动候选列表时转发的拖动位移；外部界面按自身滚动方向解释该值。
signal scroll_gesture_moved(relative: Vector2)

## 体力圆点字体尺寸；默认18像素让右下角生命信息更醒目，运行时通常无需动态修改。
@export_range(10, 28, 1) var health_pip_font_size: int = 18

## 高体力数字与护盾分数的字体尺寸；默认10像素可在固定体力框内纵向显示“当前/上限”，运行时可按牌面缩放调整。
## 当前标准字号为12像素，在保持窄体力框的同时增强数字辨识度，运行时通常无需动态修改。
@export_range(8, 24, 1) var numeric_health_font_size: int = 12

## 高体力数字与护盾分数的同色描边宽度；默认1像素用于加粗绿色或灰色文字，设为0可关闭加粗效果，运行时可按主题清晰度调整。
@export_range(0, 4, 1) var numeric_health_outline_size: int = 1

## 高体力分数三行文字的额外行间距；默认-4像素收紧当前值、斜杠与上限值，调大可增加三行之间的留白，运行时通常无需动态修改。
@export_range(-8, 8, 1) var numeric_health_line_spacing: int = -4

## 相邻体力圆点的纵向间距；默认-10像素使18像素圆点紧密排列，只影响表现密度且运行时通常无需修改。
@export_range(-16, 8, 1) var health_pip_separation: int = -10

## 单枚体力圆点的视觉直径；默认18像素，与字体尺寸一致，用于计算梯形边框宽高，运行时通常无需动态修改。
@export_range(12.0, 28.0, 1.0) var health_pip_diameter: float = 18.0

## 体力梯形框相对圆点直径增加的宽度；默认6像素使边框仅略宽于血量圆点，运行时通常无需动态修改。
@export_range(2.0, 16.0, 1.0) var health_frame_extra_width: float = 6.0

## 体力梯形框上下内容留白；默认8像素为顶边斜角和底边各预留空间，运行时通常无需动态修改。
@export_range(4.0, 20.0, 1.0) var health_frame_vertical_padding: float = 8.0

## 体力框旧斜角落差兼容参数；圆角矩形模式不再读取该值，保留字段避免旧场景资源丢失配置。
@export_range(0.0, 12.0, 1.0) var health_frame_top_slope: float = 5.0

## 体力框右下圆角半径；默认6像素与武将牌右下圆角一致，调整场景参数即可同步修改融合程度。
@export_range(0.0, 16.0, 1.0) var health_frame_bottom_right_radius: float = 6.0

## 体力框旧圆角采样段数兼容参数；当前圆角由场景内 StyleBoxFlat 直接渲染，不再读取该值。
@export_range(2, 8, 1) var health_frame_corner_segments: int = 4

## 单条装备牌信息占用的高度；默认15像素降低覆盖面积并在常规武将牌上同时叠放五个装备槽，运行时通常无需动态修改。
@export_range(12.0, 22.0, 1.0) var equipment_row_height: float = 15.0

## 牌面允许显示的装备条目上限；默认5对应武器、防具、进攻坐骑、防御坐骑和宝物五个固定槽位。
@export_range(1, 5, 1) var maximum_equipment_rows: int = 5

## 装备横条字体尺寸；默认9像素可在铺满武将插画宽度后完整显示花色、点数、牌名与木牛数量，运行时通常无需动态修改。
@export_range(7, 14, 1) var equipment_row_font_size: int = 9

## 武将名竖排的基准字数；默认4表示以四字名的整列高度作为视觉基准，更长的名字统一收紧到相近的整列高度，运行时通常无需动态修改。
@export_range(2, 12, 1) var character_name_reference_length: int = 4

## 武将名竖排开始收紧行距的字数；默认5表示四字以内保持默认行高，达到该字数后自动缩短行距，运行时通常无需动态修改。
@export_range(2, 12, 1) var character_name_compact_threshold: int = 5

## 武将名竖排允许的最小行高与字号之比；默认1.0保证行高不低于字号，且按当前字号等比换算，因此任何字数都不会被压缩到相邻字相互覆盖。
@export_range(0.6, 1.5, 0.05) var character_name_min_line_height_ratio: float = 1.0

## 武将牌固定显示尺寸；默认148.35×197.8像素与编辑器3:4场景一致，运行时通常无需动态修改。
## 当前标准尺寸为148.35×197.8像素，通过只增宽武将插画与牌框实现精确3:4比例，信息控件尺寸保持不变。
@export var card_size: Vector2 = Vector2(148.35, 197.8)

## 选目标期间非法武将牌的整体调制色；默认保留42%亮度与完整不透明度，运行时通常无需动态修改。
@export var invalid_target_modulate: Color = Color(0.42, 0.42, 0.42, 1.0)

## 移出游戏时的武将牌调制色；默认保留18%不透明度表达角色暂时不存在，仅影响表现且运行时无需动态修改。
@export var out_of_game_modulate: Color = Color(1.0, 1.0, 1.0, 0.18)

## 其他角色公开标记与武将牌左边缘的水平间距；默认1像素使标记贴近牌面，运行时通常无需动态修改。
@export_range(0.0, 16.0, 1.0) var public_marker_card_gap: float = 1.0

## 其他角色公开标记相对武将牌顶边的下移距离；默认8像素避开势力角标并保持贴近牌面，运行时通常无需动态修改。
@export_range(0.0, 48.0, 1.0) var public_marker_vertical_offset: float = 8.0

## 选目标“选中”提示的固定绿色；与太空主题合法目标色一致，不随选中金色边框变化，运行时通常无需动态修改。
const SELECTED_MARKER_COLOR: Color = Color("61c7a4")

## 选中提示字号；与桌面技能发动提示保持同级可读性，运行时通常无需动态修改。
@export_range(18, 40, 1) var selected_marker_font_size: int = 28

## 选中提示描边宽度；与技能发动黄字描边一致，保证深色插画上仍清晰，运行时通常无需动态修改。
@export_range(2, 12, 1) var selected_marker_outline_size: int = 6

## 当前角色稳定玩家 ID；由 configure 写入，未配置时为 -1。
var player_id: int = -1

## 当前角色是否是所选牌的合法候选目标；只控制青绿色提示。
var is_legal_target: bool = false

## 当前角色是否已加入目标顺序；选中状态优先使用金色提示。
var is_target_selected: bool = false

## 当前桌面是否处于需要手动选择目标的交互；启用时非法且未选中的武将牌整体变暗。
var is_target_selection_active: bool = false

## 当前角色是否正在行动；行动状态使用左侧文本标记，不影响目标合法性。
var is_current_actor: bool = false

## 当前角色是否正在处理活动规则操作；响应、选牌和其他等待输入期间由桌面按请求 actor 单独设置。
## 该状态只提供提亮与外发光，不替代当前回合角色的金色边框，也不改变输入合法性。
var is_current_operator: bool = false

## 当前武将牌是否允许交互；存活角色为 true，阵亡角色为 false，只影响输入与视觉状态。
var is_interactable: bool = false

## 当前武将牌是否显示牌背；快照的 face_down 为 true 时遮挡公开信息，不改变角色规则状态。
var is_face_down: bool = false

## 当前武将插画纹理；配置未填写或资源不存在时为 null。
var _artwork_texture: Texture2D

## 武将插画显示节点；由武将牌场景提供，固定占据角色卡左侧区域并忽略鼠标输入。
@onready var _artwork_rect: TextureRect = $Artwork

## 武将插画缺失占位标签；由武将牌场景提供，有效插画加载后自动隐藏。
@onready var _artwork_placeholder: Label = $ArtworkPlaceholder

## 武将名覆盖层；参考无名杀把角色名固定在牌面底部，避免状态文本随长度改变牌面尺寸。
## 当前参考图格式将该覆盖层调整到牌面左侧，并把武将名按单字逐行竖排显示。
@onready var _character_name_label: Label = $CharacterName

## 身份徽记覆盖层；公开身份显示在牌面右上角，未知身份使用问号徽记。
@onready var _identity_badge_label: Label = $IdentityBadge

## 手牌数量覆盖层；只显示公开数量，不暴露其他玩家的手牌内容。
@onready var _hand_count_label: Label = $HandCount

## 公开区域覆盖层；显示装备、判定区和木牛“粮”的公开数量，完整名称保留在悬停说明中。
## 当前参考图格式只在该层显示判定区与“粮”数量，公开装备改由独立横条完整显示花色、点数和牌名。
## 当前 PublicZone 已重构为判定区标记组件，木牛数量改由装备名后缀显示。
## 判定区标记组件；在武将牌底边按顺序显示判定牌菱形和首字，不读取权威实体牌。
@onready var _public_zone_label: JudgmentZoneView = $PublicZone

## 势力圆形徽记；显示势力简称并使用数据配置的主题颜色，不参与身份或胜负判断。
@onready var _faction_badge_label: Label = $FactionBadge

## 武将牌左上角通用文本组件；位于势力徽记右下侧与武将名右侧，只读取公开快照文本。
@onready var _corner_text_badge: CharacterCornerTextBadge = $CharacterCornerTextBadge

## 纵向体力圆点容器；按体力上限生成圆点，当前体力使用绿色、已损失体力使用暗色。
## 当前容器位于独立 HealthFrame 边框内，并按从上往下的方向显示已损失体力。
@onready var _health_pip_container: VBoxContainer = $HealthFrame/HealthPips

## 体力框场景容器；背景与描边节点直接位于武将牌场景内，便于在编辑器中调整颜色和层级。
@onready var _health_frame: Control = $HealthFrame

## 体力框不透明圆角矩形背景；颜色、描边与圆角均直接保存在武将牌场景 StyleBoxFlat 中。
@onready var _health_frame_background: Panel = $HealthFrame/Background

## 体力框描边折线；颜色、宽度和抗锯齿直接由武将牌场景保存，脚本只更新动态几何点。
@onready var _health_frame_border: Line2D = $HealthFrame/Border

## 是否显示仅属于正式对局的身份与手牌数标识；编辑器预览和选将候选默认关闭。
var _match_overlays_visible: bool = false

## 当前是否允许在武将牌中绘制公开装备横条；第一视角本地牌关闭，其他玩家与通用候选保持开启。
var _public_equipment_visible: bool = true

## 当前是否允许在武将牌底边绘制公开延时锦囊；第一视角本地牌关闭后改由手牌区上方的独立判定区显示。
var _public_judgment_visible: bool = true

## 当前是否允许在武将牌左侧绘制公开标记；第一视角关闭后由手牌栏上方的独立横排组件显示。
var _public_markers_visible: bool = true

## 武将牌左侧公开标记纵排组件；运行时创建以保持选将候选场景不需要额外空节点。
var _public_markers_view: PlayerMarkersView

## 当前客户端为未知身份添加的本地标注；空字符串表示保持问号，不参与规则、AI、网络或回放。
var _identity_mark: String = ""

## 鼠标当前是否停留在武将牌输入区域；只用于控制玩家名称阴影可见性。
var _is_hovered: bool = false

## 装备条目承载层；公开装备以参考图中的浅色横条从牌面下部向上叠放。
@onready var _equipment_layer: Control = $EquipmentLayer

## 状态覆盖层；显示行动中、横置或死亡等桌面状态。
## 原 Status 文本节点已经移除，当前状态由边框与独立 PlayerStateOverlay 表达。
## 阵亡与横置状态覆盖组件；负责黑白滤镜、阵亡文字和中心链条，不参与规则判断。
@onready var _state_overlay: PlayerStateOverlay = $StateOverlay

## 托管状态文字；读取公开快照在武将牌底部显示手动托管或离线托管，不参与目标点击与规则计算。
@onready var _auto_managed_label: Label = $AutoManagedLabel

## 当前已创建的装备条目控件；每次快照更新时整体重建，最多包含五个固定装备槽。
var _equipment_rows: Array[RichTextLabel] = []

## 当前装备条目对应的固定槽位 ID；索引与 _equipment_rows 一一对应，用于让空槽保留纵向位置而不自动补位。
var _equipment_row_slots: Array[String] = []

## 当前武将所属势力的展示元数据；仅保存配置深拷贝，不持有全局数据索引的可修改引用。
var _faction_definition: Dictionary = {}

## 当前武将静态定义副本；只供右键详情与主题刷新读取技能列表、名称和插画路径。
var _character_definition: Dictionary = {}

## 装备槽的固定显示顺序；保证武器、防具、进攻坐骑、防御坐骑和宝物在所有客户端一致排列。
const EQUIPMENT_SLOT_ORDER: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]

## 装备槽中文名称；统一信息框使用该映射说明当前悬停装备所属区域。
const EQUIPMENT_SLOT_NAMES: Dictionary = {
	"weapon":"武器",
	"armor":"防具",
	"offensive_mount":"进攻坐骑",
	"defensive_mount":"防御坐骑",
	"treasure":"宝物",
}

## 当前角色公开快照；仅用于刷新视觉层，不保留任何可修改的规则对象引用。
var _player_snapshot: Dictionary = {}

## 最近一次公开快照配置签名；默认-1表示从未配置，未变化的角色不会重复加载立绘、重建体力圆点、装备横条或判定标记。
var _configuration_signature: int = -1

## 当前鼠标命中的公开装备槽位；空字符串表示鼠标不在装备横条上或该牌不显示公开装备。
var _hovered_equipment_slot: String = ""

## 当前鼠标命中的公开延时锦囊索引；-1表示未命中，索引与公开判定区快照顺序一致。
var _hovered_judgment_index: int = -1

## 当前武将牌是否允许把拖动手势转交外层滚动容器；选将候选启用，局内武将牌保持关闭。
var _scroll_gesture_enabled: bool = false

## 武将牌背景面板；承载边框和纸面样式，不承担 Button 语义或规则状态。
@onready var _card_body: Panel = $CardBody

## 牌背插画层；默认隐藏，显示时替代武将插画，但身份、体力、装备、判定区、标记、状态与输入UI继续保留。
@onready var _card_back: Panel = get_node("牌背") as Panel

## 独立输入区域；覆盖整张武将牌并负责点击、详情与悬停协议。
@onready var _input_area: PlayerTargetInputArea = $InputArea

## 武将牌上部的渐变黑色阴影；只在正式对局悬停时显示，不遮挡身份、体力或点击区域。
@onready var _hover_name_shade: TextureRect = $HoverNameShade

## 渐变阴影中的玩家显示名；名称来自公开玩家快照，不使用武将名代替。
@onready var _hover_player_name_label: Label = $HoverNameShade/HoverPlayerName

## 武将牌受伤抖动组件；只接收表现调用并恢复牌面原位，不读取当前体力或伤害来源。
@onready var _damage_shake_feedback: DamageShakeFeedback = $DamageShakeFeedback

## 选目标期间的“选中”提示；常驻至取消选中，不读取规则状态，仅跟随 set_target_state。
var _selected_marker_label: Label

## 外部模式写入的中央状态提示；车轮战候选归属等只读表现复用该标签，不改变牌面交互与规则状态。
var _center_status_marker_label: Label

## 初始化武将牌视觉与独立输入区域；静态几何完全由场景资源定义。
func _ready() -> void:
	_ensure_selected_marker_label()
	_ensure_public_markers_view()
	_card_body.size = card_size
	_card_back.size = card_size
	_refresh_input_area_size()
	_state_overlay.configure_card_size(card_size)
	_health_pip_container.add_theme_constant_override("separation", health_pip_separation)
	_input_area.activated.connect(_on_input_activated)
	_input_area.details_requested.connect(_on_input_details_requested)
	_input_area.information_requested.connect(_on_input_information_requested)
	_input_area.information_dismissed.connect(_on_input_information_dismissed)
	_input_area.pointer_moved.connect(_on_input_pointer_moved)
	_input_area.scroll_gesture_moved.connect(_on_input_scroll_gesture_moved)
	_input_area.mouse_entered.connect(_on_input_mouse_entered)
	_input_area.mouse_exited.connect(_on_input_mouse_exited)
	_input_area.configure(is_interactable)
	_input_area.set_scroll_gesture_enabled(_scroll_gesture_enabled)
	_refresh_artwork()
	_refresh_decade_overlay()
	_refresh_visual_state()


## 确保公开标记纵排组件存在并连接统一信息协议；首次创建后随武将牌复用。
func _ensure_public_markers_view() -> void:
	if _public_markers_view != null and is_instance_valid(_public_markers_view):
		return
	_public_markers_view = PlayerMarkersView.new()
	_public_markers_view.name = "PublicMarkers"
	_public_markers_view.z_index = 30
	_public_markers_view.position = Vector2(-36.0, 0.0)
	add_child(_public_markers_view)
	_public_markers_view.information_requested.connect(_on_public_marker_information_requested)
	_public_markers_view.information_dismissed.connect(_on_public_marker_information_dismissed)


## 把标记悬停信息转发给武将牌既有统一信息出口；外层牌桌不需要识别子组件类型。
func _on_public_marker_information_requested(information: Dictionary, anchor_rect: Rect2) -> void:
	information_requested.emit(information, anchor_rect)


## 把标记悬停关闭请求转发给武将牌既有统一信息出口。
func _on_public_marker_information_dismissed() -> void:
	information_dismissed.emit()


## 设置候选牌是否把拖动手势交由外层滚动列表；正式对局不调用该接口，保持原有点选行为。
func set_scroll_gesture_enabled(enabled: bool) -> void:
	_scroll_gesture_enabled = enabled
	if _input_area != null:
		_input_area.set_scroll_gesture_enabled(enabled)


## 设置牌面是否允许点击；用于保留但禁用的公共候选槽，不修改快照中的存活或离场状态。
func set_interactable(enabled: bool) -> void:
	is_interactable = enabled
	if _input_area != null:
		_input_area.configure(is_interactable)
	_refresh_visual_state()


## 设置中央状态提示文本与颜色；空文本隐藏，非空文本使用黑色描边保证牌背和插画上均可读。
func set_center_status_marker(marker_text: String, marker_color: Color) -> void:
	if _center_status_marker_label == null or not is_instance_valid(_center_status_marker_label):
		_center_status_marker_label = Label.new()
		_center_status_marker_label.name = "CenterStatusMarker"
		_center_status_marker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_center_status_marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_center_status_marker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_center_status_marker_label.z_index = 21
		_center_status_marker_label.add_theme_font_size_override("font_size", 20)
		_center_status_marker_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_center_status_marker_label.add_theme_constant_override("outline_size", 5)
		add_child(_center_status_marker_label)
	_center_status_marker_label.position = Vector2.ZERO
	_center_status_marker_label.size = card_size
	_center_status_marker_label.text = marker_text
	_center_status_marker_label.add_theme_color_override("font_color", marker_color)
	_center_status_marker_label.visible = not marker_text.is_empty()


## 转发输入区域已经判定的列表拖动；本组件不读取或修改外层选将滚动位置。
func _on_input_scroll_gesture_moved(relative: Vector2) -> void:
	scroll_gesture_moved.emit(relative)


## 返回武将牌在全局画布中的矩形；卡牌动画通过该接口取得角色中心点。
func get_global_rect() -> Rect2:
	# 牌面四角的全局坐标；候选牌悬停缩放与父节点变换都需通过global_transform取得实际范围。
	var global_corners: Array[Vector2] = [global_transform * Vector2.ZERO, global_transform * Vector2(card_size.x, 0.0), global_transform * card_size, global_transform * Vector2(0.0, card_size.y)]
	# 全局包围矩形左上角；逐角取最小值以兼容候选悬停缩放与父节点变换。
	var minimum_point: Vector2 = global_corners[0]
	# 全局包围矩形右下角；逐角取最大值供动画和信息框取得牌面实际边界。
	var maximum_point: Vector2 = global_corners[0]
	for corner: Vector2 in global_corners:
		minimum_point = minimum_point.min(corner)
		maximum_point = maximum_point.max(corner)
	return Rect2(minimum_point, maximum_point - minimum_point)


## 播放一次武将牌受伤反馈；桌面在确认公开快照体力下降后调用，同一组件可被本地与其他玩家复用。
func play_damage_feedback() -> void:
	if _damage_shake_feedback != null:
		_damage_shake_feedback.play(self)


## 返回受伤反馈累计播放次数；只供界面回归与调试验证，不参与规则状态。
func get_damage_feedback_playback_count() -> int:
	return _damage_shake_feedback.get_playback_count() if _damage_shake_feedback != null else 0


## 写入角色公开快照与已经格式化的状态文本；组件不持有可修改的 PlayerState 引用。
func configure(id: int, formatted_text: String, alive: bool, current_actor: bool, character_definition: Dictionary = {}) -> void:
	player_id = id
	is_current_actor = current_actor
	is_interactable = alive
	is_face_down = false
	_character_definition = character_definition.duplicate(true)
	# 兼容格式化文本；旧调用方仍可传入摘要，该内容只作为无障碍悬停说明，不绘制按钮正文。
	var accessibility_summary: String = ("◆ 行动中\n" if is_current_actor else "") + formatted_text
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = ""
		_input_area.configure(is_interactable)
	_refresh_artwork()
	_refresh_visual_state()


## 写入公开角色快照并刷新十周年牌面覆盖层；调用方传入的是裁剪后的 Dictionary 副本。
func configure_snapshot(snapshot: Dictionary, character_definition: Dictionary = {}, current_actor: bool = false, faction_definition: Dictionary = {}) -> void:
	# 本次视觉配置签名；排除用牌、响应和技能历史等非视觉字段，避免每次动作都重建体力点与装备节点。
	var next_configuration_signature: int = hash([_get_visual_snapshot_data(snapshot), character_definition, current_actor, faction_definition, GameSettings.card_name_mode, GameSettings.ui_style_id])
	# 是否需要重建武将牌视觉；资料快照即使不改画面也必须先更新，确保新获得技能能立即进入悬停与右键详情。
	var visual_configuration_changed: bool = _configuration_signature != next_configuration_signature
	# 桌面传入的序列化快照在本广播周期内只读；浅复制顶层即可隔离字段增删，并复用长机缘历史等嵌套只读数据。
	_player_snapshot = snapshot.duplicate()
	# 静态定义来自数据库或牌桌缓存且调用方只读；浅复制避免每次出牌刷新都递归复制不变的技能与素材元数据。
	_character_definition = character_definition.duplicate()
	# 势力定义同样只包含静态展示数据；顶层副本足以防止组件意外增删字段。
	_faction_definition = faction_definition.duplicate()
	player_id = int(snapshot.get("player_id", -1))
	is_current_actor = current_actor
	is_interactable = bool(snapshot.get("alive", false)) and not bool(snapshot.get("out_of_game", false))
	is_face_down = bool(snapshot.get("face_down", false))
	if not visual_configuration_changed:
		# 当前正悬停武将资料；公开技能变化后原来源立即重发新内容，同一来源不会重新等待0.5秒。
		if is_node_ready() and _is_hovered and _hovered_equipment_slot.is_empty() and _hovered_judgment_index < 0:
			_request_character_information()
		return
	_configuration_signature = next_configuration_signature
	# 旧判定牌索引；公开判定区更新后必须重新命中，不能复用同一索引显示已经离开的延时锦囊信息。
	_hovered_judgment_index = -1
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = ""
		_input_area.configure(is_interactable)
	_refresh_artwork()
	_refresh_decade_overlay(character_definition)
	_refresh_visual_state()
	if _is_hovered and _hovered_equipment_slot.is_empty() and _hovered_judgment_index < 0:
		_request_character_information()


## 提取武将牌真正消费的公开字段；返回值只用于哈希，不会作为新的状态副本长期保存。
func _get_visual_snapshot_data(snapshot: Dictionary) -> Array:
	# 视觉字段数组；固定顺序保证相同画面得到稳定签名，嵌套装备与判定区仍按内容参与变更检测。
	var visual_data: Array = [
		snapshot.get("player_id", -1),
		snapshot.get("display_name", ""),
		snapshot.get("character_id", ""),
		snapshot.get("identity", "hidden"),
		snapshot.get("hp", 0),
		snapshot.get("max_hp", 0),
		snapshot.get("shield", 0),
		snapshot.get("alive", false),
		snapshot.get("out_of_game", false),
		snapshot.get("chained", false),
		snapshot.get("face_down", false),
		snapshot.get("character_corner_text", ""),
		snapshot.get("public_marks", {}),
		snapshot.get("auto_managed", false),
		snapshot.get("auto_managed_offline", false),
		snapshot.get("hand_count", 0),
		snapshot.get("equipment", {}),
		snapshot.get("equipment_area_abolished", false),
		snapshot.get("abolished_equipment_slots", {}),
		snapshot.get("judgment_area", []),
		snapshot.get("judgment_area_abolished", false),
		snapshot.get("wooden_ox_storage_count", 0),
	]
	return visual_data


## 设置身份与手牌数标识是否进入正式对局显示；选将面板不调用此接口，因此保持场景默认隐藏。
func set_match_overlays_visible(visible_in_match: bool) -> void:
	_match_overlays_visible = visible_in_match
	if not _match_overlays_visible:
		_dismiss_public_equipment_information()
		_dismiss_public_judgment_information()
	if not is_node_ready():
		return
	_refresh_input_area_size()
	_identity_badge_label.visible = _match_overlays_visible
	_hand_count_label.visible = _match_overlays_visible
	_public_zone_label.visible = _public_judgment_visible and _match_overlays_visible
	_refresh_auto_managed_label()
	_refresh_hover_name_visibility()
	_refresh_public_markers()


## 按当前展示用途同步透明输入区域；正式对局覆盖延时锦囊标记，选将候选保持标准牌面高度避免相邻行输入重叠。
func _refresh_input_area_size() -> void:
	if _input_area == null or _public_zone_label == null:
		return
	# 当前输入高度；只有正式对局的延时锦囊需要扩展到牌面底边之外，选将候选继续严格占用自身牌面矩形。
	var input_height: float = maxf(card_size.y, _public_zone_label.position.y + _public_zone_label.size.y) if _match_overlays_visible and _public_judgment_visible else card_size.y
	_input_area.size = Vector2(card_size.x, input_height)


## 设置武将牌是否绘制公开装备横条；本地第一视角关闭后仍由左侧独立装备栏完整显示五个槽位。
func set_public_equipment_visible(visible_on_card: bool) -> void:
	if _public_equipment_visible == visible_on_card:
		return
	_public_equipment_visible = visible_on_card
	if not is_node_ready():
		return
	_refresh_equipment_rows()


## 设置武将牌底边是否显示公开延时锦囊；本地第一视角关闭后由桌面独立区域承担相同公开信息。
func set_public_judgment_visible(visible_on_card: bool) -> void:
	if _public_judgment_visible == visible_on_card:
		return
	_public_judgment_visible = visible_on_card
	if not is_node_ready():
		return
	_public_zone_label.visible = _public_judgment_visible and _match_overlays_visible
	_refresh_input_area_size()


## 设置武将牌左侧是否显示公开标记；第一视角关闭后由牌桌独立横排组件承担相同信息与悬停说明。
func set_public_markers_visible(visible_on_card: bool) -> void:
	_public_markers_visible = visible_on_card
	if not is_node_ready():
		return
	_ensure_public_markers_view()
	_refresh_public_markers()


## 写入当前客户端对未知身份的本地标注；身份公开时标注自动失效且不会覆盖真实身份。
func set_identity_mark(identity_mark: String) -> void:
	_identity_mark = identity_mark if identity_mark in ["loyalist", "rebel", "renegade"] else ""
	_refresh_identity_badge()


## 更新合法与选中状态；已选目标始终优先显示金色边框。
## 第三个参数标记当前是否正在手动选目标，非法且未选中的武将牌仅在该状态下变暗。
func set_target_state(legal_target: bool, selected_target: bool, target_selection_active: bool = false) -> void:
	is_legal_target = legal_target
	is_target_selected = selected_target
	is_target_selection_active = target_selection_active
	if is_node_ready():
		_input_area.configure(is_interactable)
	_refresh_visual_state()


## 更新当前操作角色高亮；同一角色同时属于当前回合时仍保留金色回合边框。
func set_operation_state(current_operator: bool) -> void:
	if is_current_operator == current_operator:
		return
	is_current_operator = current_operator
	_refresh_visual_state()


## 按当前活动 UI 风格重绘武将牌；公开快照与规则交互状态保持不变。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_configuration_signature = -1
	# 当前武将定义；从稳定角色 ID 重新取得只读配置，避免组件为主题刷新长期保存额外对象引用。
	var character_definition: Dictionary = GameDatabase.get_character(str(_player_snapshot.get("character_id", "")))
	_public_zone_label.refresh_ui_style()
	if _public_markers_view != null:
		_public_markers_view.refresh_ui_style()
	_refresh_decade_overlay(character_definition)
	_refresh_visual_state()


## 区分身份徽记点击与普通武将牌点击；只有正式对局中的未知身份允许打开本地标注菜单。
func _on_input_activated(local_position: Vector2) -> void:
	# 当前公开身份；hidden 表示该观察者尚未获得真实身份信息。
	var identity: String = str(_player_snapshot.get("identity", "hidden"))
	# 身份徽记局部矩形；直接读取场景节点几何，后续编辑器调整位置无需同步硬编码命中范围。
	var identity_badge_rect: Rect2 = Rect2(_identity_badge_label.position, _identity_badge_label.size)
	if _match_overlays_visible and identity == "hidden" and identity_badge_rect.has_point(local_position):
		identity_pressed.emit(player_id)
		return
	pressed.emit()


## 把正式对局武将牌的右键请求转换为只读详情数据；选将候选不显示对局角标，因此不会发送详情请求。
func _on_input_details_requested() -> void:
	if not _match_overlays_visible or _player_snapshot.is_empty() or _character_definition.is_empty():
		return
	details_requested.emit(_player_snapshot.duplicate(true), _character_definition.duplicate(true), _faction_definition.duplicate(true))


## 处理触屏或模拟触摸的长按信息请求；命中公开装备或延时锦囊时优先显示该牌，否则显示武将静态资料。
func _on_input_information_requested(local_position: Vector2) -> void:
	if _player_snapshot.is_empty() or _character_definition.is_empty():
		return
	_is_hovered = true
	_refresh_hover_name_visibility()
	_request_character_information()
	_update_public_equipment_information(local_position)
	_update_public_judgment_information(local_position)


## 结束触屏或模拟触摸的长按信息；清理本次命中状态并关闭当前武将牌来源的信息框。
func _on_input_information_dismissed() -> void:
	_is_hovered = false
	_refresh_hover_name_visibility()
	_dismiss_public_equipment_information()
	_dismiss_public_judgment_information()
	if _hovered_equipment_slot.is_empty() and _hovered_judgment_index < 0:
		information_dismissed.emit()


## 请求通过统一目标旁信息框显示武将静态资料；本地、其他玩家与选将候选共用相同内容结构。
func _request_character_information() -> void:
	if _player_snapshot.is_empty() or _character_definition.is_empty():
		return
	# 当前武将显示名；只读取武将静态定义，缺失时使用数据库统一中文回退文本。
	var character_name: String = str(_character_definition.get("display_name", GameDatabase.resolve_character_name(str(_player_snapshot.get("character_id", "")))))
	# 当前势力完整名称；选将与局内牌面都复用势力定义的公开显示名。
	var faction_name: String = str(_faction_definition.get("display_name", _character_definition.get("faction", "未知势力")))
	# 当前武将性别文本；未知或未登记值统一显示“未知”，不参与任何规则判断。
	var gender_text: String = str({"male":"男", "female":"女", "unknown":"未知"}.get(str(_character_definition.get("gender", "unknown")), "未知"))
	# 当前武将静态体力上限；优先使用武将定义，避免领袖加成或运行时效果改变内容资料。
	var maximum_health: int = maxi(int(_character_definition.get("max_hp", _player_snapshot.get("max_hp", 0))), 0)
	# 当前武将全部可见技能ID；固有技能 → 模式技能 → 运行时临时技能，均不重复。
	var visible_skill_ids: Array = (_character_definition.get("skills", []) as Array).duplicate()
	for mode_skill_id_variant: Variant in (_player_snapshot.get("mode_skill_ids", []) as Array):
		var mode_skill_id: String = str(mode_skill_id_variant)
		if not mode_skill_id.is_empty() and not visible_skill_ids.has(mode_skill_id):
			visible_skill_ids.append(mode_skill_id)
	for temporary_skill_id_variant: Variant in (_player_snapshot.get("temporary_skills", {}) as Dictionary).keys():
		# 当前临时技能ID；已是固有技能时不重复显示。
		var temporary_skill_id: String = str(temporary_skill_id_variant)
		if not visible_skill_ids.has(temporary_skill_id):
			visible_skill_ids.append(temporary_skill_id)
	for acquired_skill_id_variant: Variant in (_player_snapshot.get("acquired_skills", {}) as Dictionary).keys():
		# 当前局内永久获得技能ID；与固有、模式或临时技能同名时不重复显示。
		var acquired_skill_id: String = str(acquired_skill_id_variant)
		if not visible_skill_ids.has(acquired_skill_id):
			visible_skill_ids.append(acquired_skill_id)
	# 当前武将全部技能文本；严格保持固有技能顺序，临时技能按运行时授予顺序追加。
	var skill_information_lines: Array[String] = []
	# 当前武将结构化技能分段；统一信息框据此把技能名绘制为与右键详情一致的金色，同时保持说明文字颜色不变。
	var skill_description_sections: Array[Dictionary] = []
	# 已经释放固有额度的限定技与觉醒技集合；分段据此标记该技能需要整块变淡，界面不自行推断释放状态。
	# 该字段在 used_limited_skill_ids 基础上额外包含觉醒技，因此觉醒技释放后同样进入变淡表现。
	var intrinsic_use_consumed_ids: Array = _player_snapshot.get("used_intrinsic_use_skill_ids", []) as Array
	for skill_id_variant: Variant in visible_skill_ids:
		# 当前技能稳定 ID；用于查询静态技能名称与说明，不读取运行时技能实例。
		var skill_id: String = str(skill_id_variant)
		# 当前技能静态定义；缺失时保留稳定 ID 与明确占位说明，避免整项静默消失。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能完整名称；信息框不截取技能按钮使用的前两个字。
		var skill_name: String = str(skill_definition.get("name", skill_id))
		# 当前技能资料标题；受限的局内获得技能在技能名后追加完整次数文案，技能描述原文不插入次数状态。
		var skill_information_title: String = _get_skill_information_title(skill_id, skill_name)
		# 当前技能完整描述；卡牌书名号按全局名称模式解析，其他原文保持不变。
		var skill_description: String = GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。")))
		# 当前技能轮回状态；公开快照是局内轮回节高亮的唯一数据来源，静态牌面缺失时回退①。
		var reincarnation_state: Dictionary = (_player_snapshot.get("reincarnation_skills", {}) as Dictionary).get(skill_id, {}) as Dictionary
		skill_information_lines.append("%s\n%s" % [skill_information_title, skill_description])
		skill_description_sections.append({
			"title":skill_information_title,
			"description":skill_description,
			"reincarnation":bool(skill_definition.get("reincarnation", false)),
			"reincarnation_section_index":maxi(int(reincarnation_state.get("section_index", 0)), 0),
			"reincarnation_round_count":maxi(int(reincarnation_state.get("round_count", 1)), 1),
			"intrinsic_use_consumed":intrinsic_use_consumed_ids.has(skill_id),
		})
	# 当前武将技能正文；无技能武将使用明确文本，避免空信息框无法判断数据状态。
	var skills_text: String = "\n\n".join(skill_information_lines) if not skill_information_lines.is_empty() else "无技能"
	# 统一武将悬停信息；标题、基础资料和全部技能沿用卡牌悬停接口的固定三个字段。
	var information: Dictionary = {
		"title":character_name,
		"title_emphasis":true,
		"refresh_subject":"character:%d" % player_id,
		"subtitle":"势力：%s｜性别：%s｜体力上限：%d" % [faction_name, gender_text, maximum_health],
		"description":skills_text,
		"description_sections":skill_description_sections,
	}
	information_requested.emit(information, get_global_rect())


## 返回武将资料中的技能标题；轮回技先标注轮回数，局内获得的受限技能再显示完整次数文案，避免改写技能原文。
func _get_skill_information_title(skill_id: String, skill_name: String) -> String:
	# 默认技能资料标题；所有技能均使用统一书名号样式，保证悬停与右键详情视觉一致。
	var skill_information_title: String = "【%s】" % skill_name
	# 技能名后的补充说明片段；轮回技固定先标注已轮回次数，次数文案始终排在其后，与技能按钮悬停标题保持一致。
	var title_suffix_parts: Array[String] = []
	# 技能静态定义；只用于判断该技能是否为轮回技，不读取技能的运行时实例。
	var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
	if bool(skill_definition.get("reincarnation", false)):
		# 当前技能轮回状态；与轮回节高亮共用同一公开快照字段，不新增数据来源。
		var reincarnation_state: Dictionary = (_player_snapshot.get("reincarnation_skills", {}) as Dictionary).get(skill_id, {}) as Dictionary
		# 当前轮回数；下限1保证未登记的轮回技仍显示稳定文本。
		var reincarnation_round_count: int = maxi(int(reincarnation_state.get("round_count", 1)), 1)
		title_suffix_parts.append("本技能已轮回%d次" % reincarnation_round_count)
	# 当前快照内的受限技能次数映射；该字段由 MatchTable 从权威获得技能记录生成，视图不自行计算或扣减次数。
	var remaining_uses_by_skill: Dictionary = _player_snapshot.get("acquired_skill_remaining_uses", {}) as Dictionary
	# 当前技能完整次数文案；没有限制或不是局内获得技能时保持空字符串。
	var remaining_uses_description: String = str(remaining_uses_by_skill.get(skill_id, ""))
	if not remaining_uses_description.is_empty():
		title_suffix_parts.append(remaining_uses_description)
	if not title_suffix_parts.is_empty():
		skill_information_title += "（%s）" % "；".join(title_suffix_parts)
	return skill_information_title


## 根据鼠标局部坐标识别其他玩家牌面上的公开装备横条，并请求统一卡牌信息。
func _on_input_pointer_moved(local_position: Vector2) -> void:
	_update_public_equipment_information(local_position)
	_update_public_judgment_information(local_position)


## 鼠标进入武将牌后请求静态资料；只有选将候选会转发悬停状态以播放缩放反馈。
func _on_input_mouse_entered() -> void:
	_is_hovered = true
	_refresh_hover_name_visibility()
	_request_character_information()
	# 正式对局武将牌不播放选将候选的缩放反馈；只在选将等非对局展示中转发该信号。
	if not _match_overlays_visible:
		hover_changed.emit(true)
	_update_public_equipment_information(_input_area.get_local_mouse_position())
	_update_public_judgment_information(_input_area.get_local_mouse_position())


## 鼠标离开武将牌后关闭所属资料；只有选将候选会收到恢复基础尺寸的悬停状态。
func _on_input_mouse_exited() -> void:
	_is_hovered = false
	_refresh_hover_name_visibility()
	if _hovered_equipment_slot.is_empty() and _hovered_judgment_index < 0:
		information_dismissed.emit()
	else:
		_dismiss_public_equipment_information()
		_dismiss_public_judgment_information()
	# 与鼠标进入保持对称；正式对局不触发候选牌缩放恢复，避免任何外部监听器改写武将牌尺寸。
	if not _match_overlays_visible:
		hover_changed.emit(false)


## 根据默认、合法、选中与禁用状态刷新角色卡样式。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 武将牌整体亮度；只有正在手动选目标且当前角色非法时变暗，普通浏览、公开全体目标和已选目标保持原亮度。
	# 武将牌整体透明度；移出游戏优先于目标选择暗置，避免临时不存在的角色仍被误认为可指定目标。
	var is_out_of_game: bool = bool(_player_snapshot.get("out_of_game", false))
	modulate = out_of_game_modulate if is_out_of_game else (invalid_target_modulate if is_target_selection_active and not is_legal_target and not is_target_selected else Color.WHITE)
	# 角色卡背景；当前行动者略微提亮，帮助玩家定位回合归属。
	var background_color: Color = BattleUIStyle.get_color("player_background") if not is_current_actor else BattleUIStyle.get_color("player_current_background")
	if is_current_operator:
		background_color = BattleUIStyle.get_color("player_operator_background")
	# 角色卡边框；选中金色优先，其次合法青绿，最后使用统一暗金边框。
	var border_color: Color = BattleUIStyle.get_color("border")
	# 角色卡描边宽度；已选目标使用3像素金边，合法目标使用较细2像素绿边，普通状态使用1像素。
	var border_width: int = 1
	if is_target_selected:
		border_color = BattleUIStyle.get_color("accent")
		border_width = 3
	elif is_legal_target:
		border_color = BattleUIStyle.get_color("legal_target")
		border_width = 2
	elif is_current_actor:
		border_color = BattleUIStyle.get_color("accent")
		border_width = 3
	elif is_current_operator:
		border_color = BattleUIStyle.get_color("legal_target").lightened(0.12)
		border_width = 2
	if not is_interactable:
		background_color = BattleUIStyle.get_color("player_disabled_background")
		border_color = BattleUIStyle.get_color("player_disabled_border")
		border_width = 1
	# 角色卡最终样式；合法但未选中的目标附加细绿光，选中后立即切换为金色描边而不保留绿光。
	var player_style: StyleBoxFlat = _make_player_style(background_color, border_color, border_width)
	if is_legal_target and not is_target_selected and is_interactable:
		player_style.shadow_color = Color(BattleUIStyle.get_color("legal_target"), 0.42)
		player_style.shadow_size = 4
		player_style.shadow_offset = Vector2.ZERO
	_card_body.add_theme_stylebox_override("panel", player_style)
	_refresh_card_back_style()
	_card_back.visible = is_face_down
	# 快照存活状态；不能用输入权限替代，离场角色仍存活但应保持透明武将牌而非显示阵亡文字。
	var snapshot_alive: bool = bool(_player_snapshot.get("alive", false))
	# 快照离场状态；只影响状态覆盖层是否绘制死亡滤镜，透明度与输入仍由本视图统一处理。
	var snapshot_out_of_game: bool = bool(_player_snapshot.get("out_of_game", false))
	_state_overlay.configure(snapshot_alive, bool(_player_snapshot.get("chained", false)), int(_player_snapshot.get("wine_bonus", 0)) > 0, snapshot_out_of_game)
	_refresh_selected_marker()
	_corner_text_badge.set_display_text(str(_player_snapshot.get("character_corner_text", "")))
	_refresh_public_markers()


## 根据公开快照刷新武将牌左侧纵排标记；选将候选、本地第一视角或空集合均不占用画面。
func _refresh_public_markers() -> void:
	if not is_node_ready():
		return
	_ensure_public_markers_view()
	# 当前公开标记；全部字段已经由PlayerState按观察者统一序列化，不包含隐藏信息。
	var public_marks: Dictionary = _player_snapshot.get("public_marks", {}) as Dictionary
	_public_markers_view.configure(public_marks, false)
	_public_markers_view.position = Vector2(-_public_markers_view.size.x - public_marker_card_gap, public_marker_vertical_offset)
	_public_markers_view.visible = _match_overlays_visible and _public_markers_visible and not public_marks.is_empty()



## 确保选中提示标签存在；首次创建后复用，不随 configure 重建以免丢失布局。
func _ensure_selected_marker_label() -> void:
	if _selected_marker_label != null and is_instance_valid(_selected_marker_label):
		return
	# 中央“选中”字；格式对齐技能发动黄字，颜色固定为绿色，生命周期跟随 is_target_selected。
	_selected_marker_label = Label.new()
	_selected_marker_label.name = "SelectedTargetMarker"
	_selected_marker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_marker_label.text = "选中"
	_selected_marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_marker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selected_marker_label.z_index = 20
	_selected_marker_label.visible = false
	_selected_marker_label.add_theme_font_size_override("font_size", selected_marker_font_size)
	_selected_marker_label.add_theme_color_override("font_color", SELECTED_MARKER_COLOR)
	_selected_marker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_selected_marker_label.add_theme_constant_override("outline_size", selected_marker_outline_size)
	add_child(_selected_marker_label)
	_layout_selected_marker()


## 将“选中”提示铺满当前武将牌矩形；card_size 或布局变化后由刷新路径重入。
func _layout_selected_marker() -> void:
	if _selected_marker_label == null or not is_instance_valid(_selected_marker_label):
		return
	_selected_marker_label.position = Vector2.ZERO
	_selected_marker_label.size = card_size


## 按 set_target_state 结果显示或隐藏绿色“选中”字；仅表现层，不读取规则引擎。
func _refresh_selected_marker() -> void:
	_ensure_selected_marker_label()
	_layout_selected_marker()
	_selected_marker_label.add_theme_font_size_override("font_size", selected_marker_font_size)
	_selected_marker_label.add_theme_color_override("font_color", SELECTED_MARKER_COLOR)
	_selected_marker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_selected_marker_label.add_theme_constant_override("outline_size", selected_marker_outline_size)
	_selected_marker_label.visible = is_target_selected

## 根据场景中名称、体力和公开区节点的实际位置排列动态装备横条；静态牌面节点绝不由脚本重排。
## 当前横条几何改为直接读取静态插画槽，完整铺满武将插画宽度。
func _layout_equipment_rows() -> void:
	if _equipment_rows.is_empty():
		return
	# 装备条目左边界；由场景内名称竖条右侧推导，编辑器调整名称位置后会自动随之适配。
	# 当前需求改为直接读取插画槽左边缘，不再以名称竖条限制横条长度。
	var row_left: float = _artwork_rect.position.x
	# 装备条目右边界；由场景内体力列左侧推导，避免与可视体力圆点重叠。
	# 当前装备条允许位于信息覆盖层下方，因此体力列不再缩短装备条。
	# 装备条目可用宽度；由场景内公开区提示宽度推导，使静态场景继续作为信息层几何的唯一来源。
	# 当前可用宽度严格等于武将插画宽度。
	var row_width: float = _artwork_rect.size.x
	# 当前参与布局的固定槽位数；武器至防御坐骑始终保留4个位置，宝物只在实际装备后加入第五个位置。
	var visible_slot_count: int = 5 if (_player_snapshot.get("equipment", {}) as Dictionary).has("treasure") else 4
	# 全部固定槽位总高度；相邻横条轻微覆盖1像素，空槽不绘制横条但继续占用对应位置。
	var rows_height: float = equipment_row_height + float(visible_slot_count - 1) * (equipment_row_height - 1.0)
	# 第一条装备的纵坐标；由场景内公开区域上沿推导，从牌面下部向上展开。
	# 当前公开区移至牌面底边之外，因此装备条改为从插画底边向上展开。
	var start_y: float = maxf(_artwork_rect.position.y + _artwork_rect.size.y - rows_height, _artwork_rect.position.y)
	for row_index: int in range(_equipment_rows.size()):
		# 当前装备横条；只更新几何信息，不改变其装备数据或显示文本。
		var equipment_row: RichTextLabel = _equipment_rows[row_index]
		# 当前装备固定槽位索引；空槽不创建节点，因此必须按对应槽位而不是数组紧凑索引定位。
		var slot_index: int = EQUIPMENT_SLOT_ORDER.find(_equipment_row_slots[row_index])
		equipment_row.position = Vector2(row_left, start_y + float(slot_index) * (equipment_row_height - 1.0))
		equipment_row.size = Vector2(row_width, equipment_row_height)


## 返回武将名竖排使用的行距；基准字数以内沿用主题默认，更长的名字按比例收紧且不低于可读下限。
func _resolve_character_name_line_spacing(name_length: int, default_line_spacing: int) -> int:
	if _character_name_label == null:
		return default_line_spacing
	# 当前字体资源；从标签主题读取，替换主题或字体后仍按真实字体计算行高。
	var font: Font = _character_name_label.get_theme_font("font")
	# 当前字号；缺失或非法时不做任何收紧，保持主题默认行距。
	var font_size: int = _character_name_label.get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return default_line_spacing
	# 自然行高；字体在零额外行距下占用的像素高度，是行高换算的基准。
	var natural_line_height: float = float(font.get_height(font_size))
	# 最小行高；行高不得低于该值，保证相邻字形的绘制区域不会被压到重叠。
	var min_line_height: float = float(font_size) * character_name_min_line_height_ratio
	# 可收紧余量；主题默认行高与最小行高的差值决定最多能收紧多少像素。
	var allowed_reduction: float = natural_line_height + float(default_line_spacing) - min_line_height
	# 未超过基准字数或没有可收紧余量时沿用主题默认行距。
	if name_length < character_name_compact_threshold or allowed_reduction <= 0.0:
		return default_line_spacing
	# 基准整列高度；按主题默认行距计算基准字数的整列高度，作为长名收紧的目标长度。
	var reference_column_height: float = float(character_name_reference_length) * (natural_line_height + float(default_line_spacing))
	# 目标行高；把当前字数的整列高度压到基准整列高度，字数越多收紧越多。
	var target_line_height: float = reference_column_height / float(name_length)
	# 实际行高；夹在最小行高与主题默认行高之间，确保只收紧不放大且不会覆盖。
	var resolved_line_height: float = clampf(target_line_height, min_line_height, natural_line_height + float(default_line_spacing))
	# 行距；Label 的 line_spacing 以像素为单位叠加在自然行高上，负数表示收紧。
	return int(round(resolved_line_height - natural_line_height))


## 根据公开快照更新牌面覆盖文字；缺少角色配置时仍保留稳定玩家名称与体力信息。
func _refresh_decade_overlay(character_definition: Dictionary = {}) -> void:
	if _character_name_label == null:
		return
	# 武将显示名；统一由数据仓库解析，配置缺失时保持中文占位而不展示稳定英文 ID。
	var character_name: String = GameDatabase.resolve_character_name(str(_player_snapshot.get("character_id", "")))
	# 势力完整名称；优先读取独立势力元数据，缺失时回退到武将配置中的稳定势力 ID。
	var faction_name: String = str(_faction_definition.get("display_name", character_definition.get("faction", "未知势力")))
	# 势力牌面简称；参考图使用单字圆形徽记，缺失时使用问号保持布局稳定。
	var faction_short_name: String = str(_faction_definition.get("short_name", "?"))
	# 势力主题颜色；配置无效时使用中性青灰色，避免数据错误中断牌面渲染。
	var faction_color: Color = Color.from_string(str(_faction_definition.get("color", "526b70")), Color("526b70"))
	if BattleUIStyle.is_monochrome():
		faction_color = BattleUIStyle.get_color("faction_neutral")
	# 公开身份 ID；其他玩家身份尚未公开时为 hidden。
	var identity: String = str(_player_snapshot.get("identity", "hidden"))
	# 身份徽记单字；用于在窄牌面右上角保持可读。
	var identity_text: String = {"leader":"领", "loyalist":"忠", "rebel":"反", "renegade":"内", "landlord":"地", "peasant":"农", "blue":"蓝", "red":"红", "hidden":"?"}.get(identity, "?")
	# 当前体力；允许为0或负数，牌面心形显示时会安全裁剪。
	var hp: int = int(_player_snapshot.get("hp", 0))
	# 当前体力上限；1至5使用圆点，超过5直接使用数字，因此无需裁剪规则快照中的真实数值。
	var max_hp: int = maxi(int(_player_snapshot.get("max_hp", 0)), 0)
	# 当前公开护盾值；护盾没有上限，异常负数快照在表现层按0处理但不回写规则状态。
	var shield: int = maxi(int(_player_snapshot.get("shield", 0)), 0)
	# 用于心形绘制的安全当前体力；限制在0至可视上限之间。
	var safe_hp: int = clampi(hp, 0, max_hp)
	_character_name_label.text = "\n".join(character_name.split(""))
	# 先清除上一次的覆盖以读取主题默认行距；主题切换后基准整列高度必须按当前主题重新计算。
	_character_name_label.remove_theme_constant_override("line_spacing")
	# 主题默认行距；未写入覆盖时由主题决定，短名始终沿用该值而不被本功能改动。
	var default_name_line_spacing: int = _character_name_label.get_theme_constant("line_spacing")
	# 实际行距；超过基准字数的长名按比例收紧整列高度，最小行高保证相邻字不会相互覆盖。
	var resolved_name_line_spacing: int = _resolve_character_name_line_spacing(character_name.length(), default_name_line_spacing)
	if resolved_name_line_spacing != default_name_line_spacing:
		_character_name_label.add_theme_constant_override("line_spacing", resolved_name_line_spacing)
	_character_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_identity_badge_label.text = identity_text
	_hover_player_name_label.text = str(_player_snapshot.get("display_name", "玩家"))
	_hover_player_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_hand_count_label.text = str(int(_player_snapshot.get("hand_count", 0)))
	_hand_count_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_identity_badge_label.visible = _match_overlays_visible
	_hand_count_label.visible = _match_overlays_visible
	_refresh_auto_managed_label()
	# 判定区公开数量；没有判定牌时不显示该摘要，避免覆盖装备横条和武将立绘。
	# 当前数量由菱形标记数组的长度直接表达，不再绘制“判N”摘要文本。
	var judgment_count: int = (_player_snapshot.get("judgment_area", []) as Array).size()
	# 木牛流马“粮”公开数量；没有“粮”时不显示该摘要，完整牌面仍只对所有者可见。
	# 当前数量紧跟木牛流马装备名显示；这里保留公开快照读取用于完整组件刷新。
	var wooden_ox_count: int = int(_player_snapshot.get("wooden_ox_storage_count", 0))
	# 判定牌显示名数组；快照顺序决定底边菱形从左到右的公开排列顺序。
	var judgment_names: Array[String] = []
	for judgment_variant: Variant in _player_snapshot.get("judgment_area", []):
		# 当前判定牌快照；只读取定义 ID 解析牌名，不把实体引用传入表现组件。
		var judgment_card: Dictionary = judgment_variant as Dictionary
		judgment_names.append(GameSettings.resolve_card_name(GameDatabase.get_card(str(judgment_card.get("definition_id", "")))))
	if judgment_count == 0:
		judgment_names.clear()
	# 木牛数量在装备条刷新时读取；显式访问保证公开数量字段缺失时仍使用0作为稳定回退。
	wooden_ox_count = maxi(wooden_ox_count, 0)
	_public_zone_label.configure(judgment_names, bool(_player_snapshot.get("judgment_area_abolished", false)))
	_public_zone_label.visible = _public_judgment_visible and _match_overlays_visible
	_faction_badge_label.text = faction_short_name
	_faction_badge_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_faction_badge_label.tooltip_text = ""
	# 势力徽记样式；清空通用面板的大内边距，保证紧凑圆徽中的单字完整显示。
	var faction_badge_style: StyleBoxFlat = BattleUIStyle.make_panel(faction_color.darkened(0.28), faction_color.lightened(0.36), 1, 14)
	faction_badge_style.content_margin_left = 0.0
	faction_badge_style.content_margin_top = 0.0
	faction_badge_style.content_margin_right = 0.0
	faction_badge_style.content_margin_bottom = 0.0
	_faction_badge_label.add_theme_stylebox_override("normal", faction_badge_style)
	# 武将名竖条样式；使用势力色并保留1像素内边距，让二至四字武将名保持居中。
	var name_banner_style: StyleBoxFlat = BattleUIStyle.make_panel(faction_color.darkened(0.38), faction_color.lightened(0.24), 1, 3)
	name_banner_style.content_margin_left = 1.0
	name_banner_style.content_margin_top = 1.0
	name_banner_style.content_margin_right = 1.0
	name_banner_style.content_margin_bottom = 1.0
	_character_name_label.add_theme_stylebox_override("normal", name_banner_style)
	# 身份徽记背景色；从活动主题面板色取得后强制完全不透明，旧场景中的半透明资源不能覆盖运行时规范。
	var identity_badge_background: Color = BattleUIStyle.get_color("panel")
	identity_badge_background.a = 1.0
	# 身份徽记边框色；与活动主题边框保持一致并强制Alpha为1，确保所有身份始终清晰可读。
	var identity_badge_border: Color = BattleUIStyle.get_color("border")
	identity_badge_border.a = 1.0
	# 身份徽记样式；紧凑尺寸不保留内容边距，主题切换和快照刷新都会重新应用同一不透明契约。
	var identity_badge_style: StyleBoxFlat = BattleUIStyle.make_panel(identity_badge_background, identity_badge_border, 1, 3)
	identity_badge_style.content_margin_left = 0.0
	identity_badge_style.content_margin_top = 0.0
	identity_badge_style.content_margin_right = 0.0
	identity_badge_style.content_margin_bottom = 0.0
	_identity_badge_label.add_theme_stylebox_override("normal", identity_badge_style)
	# 手牌数角标样式；朱红底与金边对应参考图左下角的高对比数字徽记。
	var hand_badge_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("hand_badge_background"), BattleUIStyle.get_color("hand_badge_border"), 1, 3)
	hand_badge_style.content_margin_left = 0.0
	hand_badge_style.content_margin_top = 0.0
	hand_badge_style.content_margin_right = 0.0
	hand_badge_style.content_margin_bottom = 0.0
	_hand_count_label.add_theme_stylebox_override("normal", hand_badge_style)
	# 体力框样式；背景与描边跟随主题，红黄绿体力圆点继续表达玩法语义。
	var health_frame_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("health_frame_background"), BattleUIStyle.get_color("health_frame_border"), 1, roundi(health_frame_bottom_right_radius))
	health_frame_style.content_margin_left = 2.0
	health_frame_style.content_margin_top = 2.0
	health_frame_style.content_margin_right = 2.0
	health_frame_style.content_margin_bottom = 2.0
	_health_frame_background.add_theme_stylebox_override("panel", health_frame_style)
	_refresh_health_pips(safe_hp, max_hp, shield)
	_refresh_equipment_rows()
	_refresh_identity_badge()
	_refresh_hover_name_visibility()


## 根据公开托管字段更新底部状态文字；手动托管与掉线托管共用描边样式，仅文案不同。
func _refresh_auto_managed_label() -> void:
	if _auto_managed_label == null:
		return
	# 当前是否正在托管；状态只来自权威快照，避免本地网络延迟或 UI 点击自行推断。
	var auto_managed: bool = bool(_player_snapshot.get("auto_managed", false))
	# 当前是否为掉线触发的托管；true 时额外提示其他观察者该玩家已不在线。
	var offline_managed: bool = bool(_player_snapshot.get("auto_managed_offline", false))
	_auto_managed_label.text = "已离线，托管中" if offline_managed else "托管中"
	_auto_managed_label.visible = _match_overlays_visible and auto_managed
	_auto_managed_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_auto_managed_label.add_theme_color_override("font_outline_color", BattleUIStyle.get_color("outer_background"))


## 按当前体力和体力上限重建右侧圆点；绿色表示现有体力，暗色表示已损失体力。
## 已损失圆点现在从容器顶部开始排列，使扣血方向固定为从上往下。
## 护盾在圆点模式下使用灰色圆点置于体力上方，体力进入数字模式后显示为灰色加粗单值。
func _refresh_health_pips(safe_hp: int, max_hp: int, shield: int) -> void:
	for child: Node in _health_pip_container.get_children():
		_health_pip_container.remove_child(child)
		child.queue_free()
	# 数字模式标志；体力上限超过5时显示“当前/上限”，避免圆点列超出武将牌。
	var uses_numeric_health: bool = max_hp > 5
	_health_pip_container.add_theme_constant_override("separation", 0 if uses_numeric_health else health_pip_separation)
	if uses_numeric_health:
		if shield > 0:
			# 数字护盾标签；与数字体力在VBox中纵向排列。护盾没有独立上限，只显示当前护盾值避免伪造分母语义。
			var shield_number: Label = Label.new()
			shield_number.text = str(shield)
			shield_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			shield_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_apply_numeric_health_label_style(shield_number, BattleUIStyle.get_color("health_shield"))
			shield_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_health_pip_container.add_child(shield_number)
		# 数字体力标签；高上限角色使用绿色加粗分数格式同时展示当前体力与体力上限，不再按残血切换黄红色。
		# 当前颜色规则补充：数字模式与圆点模式共用残血语义，体力上限大于2时2点为黄色、1点为红色。
		# 分数内容按“当前值、斜杠、上限值”分成三行，确保窄体力框内沿武将牌右侧纵向阅读。
		var health_number: Label = Label.new()
		health_number.text = "%d\n/\n%d" % [safe_hp, max_hp]
		health_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_numeric_health_label_style(health_number, _resolve_current_health_color(safe_hp, max_hp))
		health_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_pip_container.add_child(health_number)
		_layout_health_frame(true)
		return
	# 护盾圆点索引；每点护盾生成一枚相同灰色圆点，索引本身不表达独立来源。
	for _shield_index: int in range(shield):
		# 当前护盾圆点；全部使用灰色语义色并排列在体力圆点上方，伤害结算会从该区域优先扣减。
		var shield_pip: Label = Label.new()
		shield_pip.text = "●"
		shield_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shield_pip.add_theme_font_size_override("font_size", health_pip_font_size)
		shield_pip.add_theme_color_override("font_color", BattleUIStyle.get_color("health_shield"))
		shield_pip.add_theme_color_override("font_shadow_color", BattleUIStyle.get_color("health_shadow"))
		shield_pip.add_theme_constant_override("shadow_offset_x", 1)
		shield_pip.add_theme_constant_override("shadow_offset_y", 1)
		shield_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_pip_container.add_child(shield_pip)
	for pip_index: int in range(max_hp):
		# 当前体力圆点；索引小于当前体力时点亮，其余保留暗色上限占位。
		# 当前颜色判断改用顶部已损失数量，剩余圆点继续使用相同绿色与暗色。
		var health_pip: Label = Label.new()
		health_pip.text = "●"
		health_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_pip.add_theme_font_size_override("font_size", health_pip_font_size)
		health_pip.add_theme_color_override("font_color", BattleUIStyle.get_color("health_lost") if pip_index < max_hp - safe_hp else _resolve_current_health_color(safe_hp, max_hp))
		health_pip.add_theme_color_override("font_shadow_color", BattleUIStyle.get_color("health_shadow"))
		health_pip.add_theme_constant_override("shadow_offset_x", 1)
		health_pip.add_theme_constant_override("shadow_offset_y", 1)
		health_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_pip_container.add_child(health_pip)
	_layout_health_frame(false)


## 为高体力数字或护盾分数应用统一的加粗主题；同色1像素描边扩大字形轮廓，不依赖外部字体是否提供粗体字重。
func _apply_numeric_health_label_style(label: Label, text_color: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", numeric_health_font_size)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_outline_color", text_color)
	label.add_theme_constant_override("outline_size", numeric_health_outline_size)
	label.add_theme_constant_override("line_spacing", numeric_health_line_spacing)


## 返回当前剩余体力使用的语义颜色；上限1或2永久保持绿色，其他角色在2点和1点时分别转为黄色与红色。
func _resolve_current_health_color(safe_hp: int, max_hp: int, fallback_color: Color = Color.WHITE) -> Color:
	if max_hp <= 0:
		return fallback_color
	if max_hp <= 2:
		return BattleUIStyle.get_color("health_full")
	if safe_hp <= 1:
		return BattleUIStyle.get_color("health_danger")
	if safe_hp == 2:
		return BattleUIStyle.get_color("health_warning")
	return BattleUIStyle.get_color("health_full")


## 按体力内容的真实字体排版尺寸调整梯形；不能只用字体字号估算，否则 VBoxContainer 的行高会从底边溢出。
func _layout_health_frame(uses_numeric_health: bool) -> void:
	# 体力内容真实最小尺寸；包含字体上升部、下降部和 VBoxContainer 的负间距计算结果。
	var content_minimum_size: Vector2 = _health_pip_container.get_combined_minimum_size()
	content_minimum_size.y = maxf(content_minimum_size.y, health_pip_diameter)
	# 体力框宽度；圆点模式保持略宽于圆点，数字模式允许完整容纳“当前/上限”文本。
	var frame_width: float = maxf(34.0 if uses_numeric_health else health_pip_diameter + health_frame_extra_width, content_minimum_size.x + 4.0)
	# 体力框高度；严格使用真实内容高度并增加上下留白，确保最后一项不会越过底边。
	var frame_height: float = content_minimum_size.y + health_frame_vertical_padding
	# 动态圆角矩形尺寸；右边与底边直接对齐武将牌边缘，使两个圆角边框紧密贴合。
	var frame_size: Vector2 = Vector2(frame_width, frame_height)
	_health_frame.size = frame_size
	_health_frame.position = Vector2(card_size.x - frame_size.x, card_size.y - frame_size.y)
	_update_health_frame_geometry(frame_size)
	_health_pip_container.position = Vector2(2.0, health_frame_vertical_padding * 0.5)
	_health_pip_container.size = Vector2(frame_size.x - 4.0, content_minimum_size.y)


## 更新场景内体力框圆角矩形尺寸；StyleBoxFlat 负责连续圆角与抗锯齿，不再生成斜边多边形。
func _update_health_frame_geometry(frame_size: Vector2) -> void:
	_health_frame_background.position = Vector2.ZERO
	_health_frame_background.size = frame_size


## 按固定槽位顺序把公开装备转换为参考图中的花色点数与牌名横条。
func _refresh_equipment_rows() -> void:
	_dismiss_public_equipment_information()
	for equipment_row: RichTextLabel in _equipment_rows:
		if equipment_row != null and is_instance_valid(equipment_row):
			_equipment_layer.remove_child(equipment_row)
			equipment_row.queue_free()
	_equipment_rows.clear()
	_equipment_row_slots.clear()
	if not _public_equipment_visible:
		if _is_hovered:
			_request_character_information()
		return
	# 当前公开装备字典；快照已包含完整实体牌数据，可安全展示花色、点数和牌名。
	var equipment: Dictionary = _player_snapshot.get("equipment", {}) as Dictionary
	# 当前已废除装备栏；其占位条与实体装备共用固定槽位位置，但不伪造卡牌数据。
	var abolished_slots: Dictionary = _player_snapshot.get("abolished_equipment_slots", {}) as Dictionary
	for slot: String in EQUIPMENT_SLOT_ORDER:
		# 当前栏位是否已废除；异常快照同时含装备时仍优先显示废除事实。
		var is_abolished: bool = bool(abolished_slots.get(slot, false))
		if (not equipment.has(slot) and not is_abolished) or _equipment_rows.size() >= maximum_equipment_rows:
			continue
		# 当前槽位的公开装备实体牌；只读取序列化数据，不保留可修改的 CardInstance 引用。
		var equipment_card: Dictionary = equipment.get(slot, {}) as Dictionary
		# 当前装备定义；用于按全局名称模式解析牌名，配置缺失时回退到稳定定义 ID。
		var card_definition: Dictionary = GameDatabase.get_card(str(equipment_card.get("definition_id", "")))
		# 当前装备显示名；所有角色牌与手牌共用同一名称切换规则。
		var equipment_name: String = "已废除" if is_abolished else (GameSettings.resolve_card_display_name(card_definition) if not card_definition.is_empty() else str(equipment_card.get("definition_id", "未知装备")))
		if not is_abolished and bool(card_definition.get("shows_attachment_count", false)):
			# 装备公开附属牌数；数量紧跟装备名显示，0张时也明确保留当前容量快照。
			var wooden_ox_count: int = int(_player_snapshot.get("wooden_ox_storage_count", 0))
			equipment_name += "（%d）" % wooden_ox_count
		# 当前装备花色；用于生成参考图中的左侧花色点数标记和红黑配色。
		var suit: String = str(equipment_card.get("suit", "none"))
		# 当前装备点数；虚拟或缺失点数使用空文本，不显示无意义的0。
		var rank: int = int(equipment_card.get("rank", 0))
		# 新建装备横条；富文本允许花色点数使用红黑色而牌名保持深褐色。
		var equipment_row: RichTextLabel = RichTextLabel.new()
		equipment_row.bbcode_enabled = true
		equipment_row.fit_content = false
		equipment_row.scroll_active = false
		equipment_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		equipment_row.add_theme_font_size_override("normal_font_size", equipment_row_font_size)
		equipment_row.add_theme_color_override("default_color", BattleUIStyle.get_color("zone_abolished_text") if is_abolished else BattleUIStyle.get_color("equipment_text"))
		# 装备横条样式；缩小内容边距以在固定60像素条宽内完整显示花色点数与短牌名。
		# 当前横条已扩展到完整插画宽度，并在宝物名称后容纳木牛公开数量。
		var equipment_row_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("zone_abolished_background") if is_abolished else BattleUIStyle.get_color("equipment_background"), BattleUIStyle.get_color("zone_abolished_border") if is_abolished else BattleUIStyle.get_color("equipment_border"), 1, 3)
		equipment_row_style.content_margin_left = 2.0
		equipment_row_style.content_margin_top = 0.0
		equipment_row_style.content_margin_right = 2.0
		equipment_row_style.content_margin_bottom = 0.0
		equipment_row.add_theme_stylebox_override("normal", equipment_row_style)
		equipment_row.text = "[center]× %s[/center]" % str(EQUIPMENT_SLOT_NAMES.get(slot, "装备")) if is_abolished else "[center][color=%s]%s%s[/color] %s[/center]" % [_suit_color(suit).to_html(false), _suit_symbol(suit), _rank_text(rank), equipment_name]
		_equipment_layer.add_child(equipment_row)
		_equipment_rows.append(equipment_row)
		_equipment_row_slots.append(slot)
	_layout_equipment_rows()
	if _is_hovered:
		_request_character_information()
		call_deferred("_update_public_equipment_information", _input_area.get_local_mouse_position())
		call_deferred("_update_public_judgment_information", _input_area.get_local_mouse_position())


## 根据公开身份与本地标注刷新身份徽记；真实身份始终优先，本地标注只替换未知问号。
func _refresh_identity_badge() -> void:
	if not is_node_ready() or _identity_badge_label == null:
		return
	# 当前公开身份；非 hidden 时必须直接显示权威身份，禁止本地标注覆盖。
	var identity: String = str(_player_snapshot.get("identity", "hidden"))
	# 当前徽记文本；未知身份可使用本地忠、反、内标注，否则保持问号。
	# 徽记文本先通过 displayed_identity 统一公开身份与本地标记，再使用ASCII问号作为未知回退。
	# 当前实际显示身份；公开身份优先，未知身份才允许使用本地或自动推测标记。
	var displayed_identity: String = identity if identity != "hidden" else _identity_mark
	# 当前徽记文本；没有公开身份与本地标记时保持ASCII问号。
	var identity_text: String = {"leader":"领", "loyalist":"忠", "rebel":"反", "renegade":"内", "landlord":"地", "peasant":"农", "blue":"蓝", "red":"红"}.get(displayed_identity, "?")
	_identity_badge_label.text = identity_text
	# 本地标注使用浅青色与真实金色身份区分，避免玩家把推测误认为公开信息。
	# 当前设计改用固定身份语义色统一公开、手动与自动标记，未知状态仍使用次级文字色。
	# 当前身份字体色；公开身份、手动标记与自动标记使用同一阵营语义色，未知状态使用次级文字色。
	var identity_color: Color = BattleUIStyle.get_color("identity_%s" % displayed_identity, BattleUIStyle.get_color("text_secondary")) if not displayed_identity.is_empty() else BattleUIStyle.get_color("text_secondary")
	_identity_badge_label.add_theme_color_override("font_color", identity_color)


## 同步玩家名称阴影可见性；选将候选不显示玩家名，正式对局悬停时才显示。
func _refresh_hover_name_visibility() -> void:
	if not is_node_ready() or _hover_name_shade == null:
		return
	# 正式对局的悬停姓名阴影已经停用；选将界面继续只消费 hover_changed 播放候选缩放。
	# 正式对局只在鼠标停留于可见武将牌时显示名称；遮罩节点层级高于插画且忽略鼠标，不会阻断输入区域。
	_hover_name_shade.visible = _match_overlays_visible and _is_hovered and not is_face_down


## 更新其他玩家公开装备信息命中；装备横条本身忽略鼠标，由最上层透明输入区域统一转发坐标。
func _update_public_equipment_information(local_position: Vector2) -> void:
	if not _match_overlays_visible or not _public_equipment_visible or not _is_hovered or is_face_down:
		return
	# 当前命中的固定装备槽位；空字符串表示鼠标不在任何已绘制装备横条内。
	var hovered_slot: String = ""
	# 当前命中的装备横条；用于提供统一信息框的全局锚点矩形。
	var hovered_row: RichTextLabel
	for row_index: int in range(_equipment_rows.size()):
		# 当前公开装备横条；其局部位置与透明输入区域共享同一武将牌坐标空间。
		var equipment_row: RichTextLabel = _equipment_rows[row_index]
		if Rect2(equipment_row.position, equipment_row.size).has_point(local_position):
			hovered_slot = _equipment_row_slots[row_index]
			hovered_row = equipment_row
			break
	if hovered_slot.is_empty() or hovered_row == null:
		if not _hovered_equipment_slot.is_empty():
			_hovered_equipment_slot = ""
			# 鼠标仍停留在其他玩家武将牌内时，离开装备横条后恢复该武将全部技能资料，而非直接留下空白。
			if _hovered_judgment_index < 0:
				_request_character_information()
		return
	if hovered_slot == _hovered_equipment_slot:
		return
	# 当前玩家公开装备字典；快照只包含对所有观察者可见的装备实体数据。
	var equipment: Dictionary = _player_snapshot.get("equipment", {}) as Dictionary
	# 当前已废除装备栏快照；废除占位横条显示规则说明而不尝试解析卡牌。
	var abolished_slots: Dictionary = _player_snapshot.get("abolished_equipment_slots", {}) as Dictionary
	if bool(abolished_slots.get(hovered_slot, false)):
		# 废除栏位信息；说明该栏不能放置装备，恢复后也不返还曾离区的牌。
		var abolished_information: Dictionary = {
			"title":"【%s已废除】" % str(EQUIPMENT_SLOT_NAMES.get(hovered_slot, "装备栏")),
			"subtitle":"装备栏状态",
			"description":"当前不能向该装备栏放置装备牌；恢复栏位不会找回废除时弃置的牌。",
		}
		_hovered_equipment_slot = hovered_slot
		information_requested.emit(abolished_information, hovered_row.get_global_rect())
		return
	# 当前命中装备实体快照；槽位在横条创建后仍可能因快照刷新失效，缺失时直接停止显示。
	var equipment_card: Dictionary = equipment.get(hovered_slot, {}) as Dictionary
	if equipment_card.is_empty():
		return
	# 当前装备静态定义；名称和说明统一从数据库深拷贝读取。
	var card_definition: Dictionary = GameDatabase.get_card(str(equipment_card.get("definition_id", "")))
	# 当前装备显示名；跟随全局牌名模式，木牛流马额外显示全部观察者可见的“粮”数量。
	var equipment_name: String = GameSettings.resolve_card_display_name(card_definition) if not card_definition.is_empty() else str(equipment_card.get("definition_id", "未知装备"))
	if bool(card_definition.get("shows_attachment_count", false)):
		equipment_name += "（%d）" % int(_player_snapshot.get("wooden_ox_storage_count", 0))
	# 当前装备花色点数；与牌面横条内容一致，用于信息框副标题。
	var suit_rank_text: String = "%s%s" % [_suit_symbol(str(equipment_card.get("suit", "none"))), _rank_text(int(equipment_card.get("rank", 0)))]
	# 统一公开装备信息；只描述目标牌本身，不附带其他玩家私有手牌或权威状态。
	var information: Dictionary = {
		"title":"【%s】" % equipment_name,
		"subtitle":"%s｜%s" % [str(EQUIPMENT_SLOT_NAMES.get(hovered_slot, "装备")), suit_rank_text],
		"description":str(card_definition.get("description", "暂无卡牌说明。")),
	}
	_hovered_equipment_slot = hovered_slot
	information_requested.emit(information, hovered_row.get_global_rect())


## 根据公开判定区菱形标记命中延时锦囊，并请求与装备横条相同的统一卡牌信息。
func _update_public_judgment_information(local_position: Vector2) -> void:
	if not _match_overlays_visible or not _public_judgment_visible or not _is_hovered or is_face_down:
		return
	# 当前公开判定区；空数组无需进行标记命中，也不泄漏任何隐藏区域信息。
	var judgment_area: Array = _player_snapshot.get("judgment_area", []) as Array
	# 当前命中的判定牌索引；逐张读取正式标记矩形，避免依据文字宽度或首字反推位置。
	var hovered_judgment_index: int = -1
	for judgment_index: int in range(judgment_area.size()):
		# 当前判定牌标记局部矩形；由JudgmentZoneView统一计算，展示与悬停命中不会出现偏移。
		var marker_rect: Rect2 = _public_zone_label.get_marker_rect(judgment_index)
		# 当前标记在武将牌中的矩形；PublicZone与透明输入区共用武将牌局部坐标空间。
		var marker_rect_in_card: Rect2 = Rect2(_public_zone_label.position + marker_rect.position, marker_rect.size)
		if marker_rect_in_card.has_point(local_position):
			hovered_judgment_index = judgment_index
			break
	if hovered_judgment_index < 0:
		if _hovered_judgment_index >= 0:
			_hovered_judgment_index = -1
			# 离开延时锦囊但仍处于武将牌内时，恢复武将静态资料；装备信息优先时不覆盖它。
			if _hovered_equipment_slot.is_empty():
				_request_character_information()
		return
	if hovered_judgment_index == _hovered_judgment_index:
		return
	# 当前公开延时锦囊实体；快照只包含公开花色、点数与定义ID，信息框不读取任何私有牌区。
	var judgment_card: Dictionary = judgment_area[hovered_judgment_index] as Dictionary
	# 当前延时锦囊静态定义；名称与说明从数据库统一解析，配置缺失时保留稳定ID回退。
	var card_definition: Dictionary = GameDatabase.get_card(str(judgment_card.get("definition_id", "")))
	# 当前延时锦囊显示名；与装备横条一致跟随全局牌名模式。
	var judgment_name: String = GameSettings.resolve_card_display_name(card_definition) if not card_definition.is_empty() else str(judgment_card.get("definition_id", "未知延时锦囊"))
	# 当前延时锦囊花色点数；与公开实体快照保持一致。
	var suit_rank_text: String = "%s%s" % [_suit_symbol(str(judgment_card.get("suit", "none"))), _rank_text(int(judgment_card.get("rank", 0)))]
	# 当前标记局部矩形；用于计算与候选牌缩放兼容的全局信息框锚点。
	var local_marker_rect: Rect2 = _public_zone_label.get_marker_rect(hovered_judgment_index)
	# 当前标记左上与右下全局坐标；通过PublicZone变换兼容候选缩放和父级画布变换。
	var marker_global_transform: Transform2D = _public_zone_label.get_global_transform()
	var marker_global_position: Vector2 = marker_global_transform * local_marker_rect.position
	var marker_global_end: Vector2 = marker_global_transform * local_marker_rect.end
	# 统一延时锦囊信息；内容结构与公开装备横条一致，信息层继续负责悬停延时与位置避让。
	var information: Dictionary = {
		"title":"【%s】" % judgment_name,
		"subtitle":"延时锦囊｜%s" % suit_rank_text,
		"description":str(card_definition.get("description", "暂无卡牌说明。")),
	}
	_hovered_judgment_index = hovered_judgment_index
	information_requested.emit(information, Rect2(marker_global_position, marker_global_end - marker_global_position))


## 关闭当前公开装备横条拥有的信息框；重复调用保持幂等且不会影响其他来源。
func _dismiss_public_equipment_information() -> void:
	if _hovered_equipment_slot.is_empty():
		return
	_hovered_equipment_slot = ""
	if _hovered_judgment_index < 0:
		information_dismissed.emit()


## 关闭当前公开延时锦囊拥有的信息框；与装备悬停共存时只在两者均离开后关闭来源信息。
func _dismiss_public_judgment_information() -> void:
	if _hovered_judgment_index < 0:
		return
	_hovered_judgment_index = -1
	if _hovered_equipment_slot.is_empty():
		information_dismissed.emit()


## 武将牌退出场景树时关闭公开装备信息，避免座位移除后残留旧浮层。
func _exit_tree() -> void:
	_dismiss_public_equipment_information()
	_dismiss_public_judgment_information()


## 刷新武将牌统一牌背配色；翻面状态只替换插画层，不改变角色UI、交互权限或规则状态。
func _refresh_card_back_style() -> void:
	if not is_node_ready() or _card_back == null:
		return
	# 武将牌背外框；与实体卡牌牌背共享主题语义但保持武将牌自身尺寸。
	var card_back_style: StyleBoxFlat = BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("card_back_background"), BattleUIStyle.get_color("border"), 2, 6)
	_card_back.add_theme_stylebox_override("panel", card_back_style)
	# 武将牌背中心面板；通过第二层近黑灰色维持太空舷窗式层次。
	var card_back_center: Panel = _card_back.get_node("Center") as Panel
	card_back_center.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("card_back_center"), BattleUIStyle.get_color("border"), 1, 5))
	# 武将牌背主标题；保持高对比度但不显示任何角色信息。
	var card_back_title: Label = _card_back.get_node("Title") as Label
	card_back_title.add_theme_color_override("font_color", BattleUIStyle.get_color("card_back_title"))
	# 武将牌背副标题；使用次级色维持主次关系。
	var card_back_subtitle: Label = _card_back.get_node("Subtitle") as Label
	card_back_subtitle.add_theme_color_override("font_color", BattleUIStyle.get_color("card_back_subtitle"))


## 将花色 ID 转换为装备横条使用的符号；无花色牌使用空心菱形保持位置稳定。
func _suit_symbol(suit: String) -> String:
	return {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦", "none":"◇"}.get(suit, "◇")


## 将点数转换为牌面字符；无点数装备不显示数字，A、J、Q、K使用标准字符。
func _rank_text(rank: int) -> String:
	if rank <= 0:
		return ""
	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))


## 返回装备花色点数的前景色；红桃和方片使用朱红色，黑桃和梅花使用近黑色。
func _suit_color(suit: String) -> Color:
	return Color("b62d2d") if suit in ["heart", "diamond"] else Color("26211d")


## 构造角色牌悬停说明；只使用公开快照，不显示其他玩家私有手牌内容。
func _format_snapshot_tooltip(snapshot: Dictionary, character_definition: Dictionary) -> String:
	# 装备区牌名摘要；公开装备按槽位顺序读取并使用当前全局牌名模式。
	var equipment_names: Array[String] = []
	# 当前公开装备字典；悬停说明与牌面保持相同的武器至宝物固定顺序，缺少槽位时直接跳过。
	var equipment: Dictionary = snapshot.get("equipment", {}) as Dictionary
	for slot: String in EQUIPMENT_SLOT_ORDER:
		if not equipment.has(slot):
			continue
		# 当前公开装备快照；只读取定义 ID 解析显示名。
		var equipment_card: Dictionary = equipment.get(slot, {}) as Dictionary
		equipment_names.append(GameSettings.resolve_card_name(GameDatabase.get_card(str(equipment_card.get("definition_id", "")))))
	# 判定区牌名摘要；按快照顺序显示延时锦囊名称。
	var judgment_names: Array[String] = []
	for judgment_variant: Variant in snapshot.get("judgment_area", []):
		# 当前公开判定牌快照；只读取定义 ID 解析显示名。
		var judgment_card: Dictionary = judgment_variant as Dictionary
		judgment_names.append(GameSettings.resolve_card_name(GameDatabase.get_card(str(judgment_card.get("definition_id", "")))))
	# 当前武将势力名称；悬停说明使用完整名称，牌面圆形徽记只显示简称。
	var faction_name: String = str(_faction_definition.get("display_name", character_definition.get("faction", "未知势力")))
	return "%s｜%s｜%s\n体力 %d/%d｜护盾 %d｜手牌 %d｜粮 %d\n装备：%s\n判定：%s" % [
		str(snapshot.get("display_name", "玩家")),
		GameDatabase.resolve_character_name(str(snapshot.get("character_id", ""))),
		faction_name,
		int(snapshot.get("hp", 0)),
		int(snapshot.get("max_hp", 0)),
		int(snapshot.get("shield", 0)),
		int(snapshot.get("hand_count", 0)),
		int(snapshot.get("wooden_ox_storage_count", 0)),
		"、".join(equipment_names) if not equipment_names.is_empty() else "无",
		"、".join(judgment_names) if not judgment_names.is_empty() else "无",
	]


## 刷新武将插画与占位可见性；configure 和 _ready 均可安全调用。
func _refresh_artwork() -> void:
	if not is_node_ready() or _artwork_rect == null:
		return
	_artwork_rect.texture = _artwork_texture
	_artwork_rect.visible = _artwork_texture != null
	_artwork_placeholder.visible = _artwork_texture == null


## 创建为左侧插画预留内容边距的角色卡样式，避免状态文字覆盖武将图像。
## 当前纵版覆盖层不再使用按钮正文，因此内容边距收缩为4像素，只保留边框与立绘安全区。
func _make_player_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	# 角色卡样式；插画区宽66像素，加上左右间距后文字从84像素处开始。
	# 参考图纵版格式已改为全牌面立绘，该旧说明仅记录历史布局；当前实际边距统一为4像素。
	var style: StyleBoxFlat = BattleUIStyle.make_inset_panel(background_color, border_color, border_width, 6)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style
