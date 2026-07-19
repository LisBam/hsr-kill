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

## 体力圆点字体尺寸；默认18像素让右下角生命信息更醒目，运行时通常无需动态修改。
@export_range(10, 28, 1) var health_pip_font_size: int = 18

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

## 武将牌固定显示尺寸；默认148.35×197.8像素与编辑器3:4场景一致，运行时通常无需动态修改。
## 当前标准尺寸为148.35×197.8像素，通过只增宽武将插画与牌框实现精确3:4比例，信息控件尺寸保持不变。
@export var card_size: Vector2 = Vector2(148.35, 197.8)

## 当前角色稳定玩家 ID；由 configure 写入，未配置时为 -1。
var player_id: int = -1

## 当前角色是否是所选牌的合法候选目标；只控制青绿色提示。
var is_legal_target: bool = false

## 当前角色是否已加入目标顺序；选中状态优先使用金色提示。
var is_target_selected: bool = false

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

## 武将牌背景面板；承载边框和纸面样式，不承担 Button 语义或规则状态。
@onready var _card_body: Panel = $CardBody

## 牌背覆盖层；默认隐藏，显示时覆盖武将插画、状态与公开区域，但保留输入区域可用。
@onready var _card_back: Panel = get_node("牌背") as Panel

## 独立输入区域；覆盖整张武将牌并负责点击、详情与悬停协议。
@onready var _input_area: PlayerTargetInputArea = $InputArea

## 武将牌上部的渐变黑色阴影；只在正式对局悬停时显示，不遮挡身份、体力或点击区域。
@onready var _hover_name_shade: TextureRect = $HoverNameShade

## 渐变阴影中的玩家显示名；名称来自公开玩家快照，不使用武将名代替。
@onready var _hover_player_name_label: Label = $HoverNameShade/HoverPlayerName

## 武将牌受伤抖动组件；只接收表现调用并恢复牌面原位，不读取当前体力或伤害来源。
@onready var _damage_shake_feedback: DamageShakeFeedback = $DamageShakeFeedback

## 初始化武将牌视觉与独立输入区域；静态几何完全由场景资源定义。
func _ready() -> void:
	_card_body.size = card_size
	_card_back.size = card_size
	_input_area.size = card_size
	_state_overlay.configure_card_size(card_size)
	_health_pip_container.add_theme_constant_override("separation", health_pip_separation)
	_input_area.activated.connect(_on_input_activated)
	_input_area.details_requested.connect(_on_input_details_requested)
	_input_area.pointer_moved.connect(_on_input_pointer_moved)
	_input_area.mouse_entered.connect(_on_input_mouse_entered)
	_input_area.mouse_exited.connect(_on_input_mouse_exited)
	_input_area.configure(is_interactable)
	_refresh_artwork()
	_refresh_decade_overlay()
	_refresh_visual_state()


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
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	_player_snapshot = snapshot.duplicate(true)
	_character_definition = character_definition.duplicate(true)
	_faction_definition = faction_definition.duplicate(true)
	player_id = int(snapshot.get("player_id", -1))
	is_current_actor = current_actor
	is_interactable = bool(snapshot.get("alive", false))
	is_face_down = bool(snapshot.get("face_down", false))
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = ""
		_input_area.configure(is_interactable)
	_refresh_artwork()
	_refresh_decade_overlay(character_definition)
	_refresh_visual_state()


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
		snapshot.get("chained", false),
		snapshot.get("face_down", false),
		snapshot.get("hand_count", 0),
		snapshot.get("equipment", {}),
		snapshot.get("judgment_area", []),
		snapshot.get("wooden_ox_storage_count", 0),
	]
	return visual_data


## 设置身份与手牌数标识是否进入正式对局显示；选将面板不调用此接口，因此保持场景默认隐藏。
func set_match_overlays_visible(visible_in_match: bool) -> void:
	_match_overlays_visible = visible_in_match
	if not _match_overlays_visible:
		_dismiss_public_equipment_information()
	if not is_node_ready():
		return
	_identity_badge_label.visible = _match_overlays_visible
	_hand_count_label.visible = _match_overlays_visible
	_refresh_hover_name_visibility()


## 设置武将牌是否绘制公开装备横条；本地第一视角关闭后仍由左侧独立装备栏完整显示五个槽位。
func set_public_equipment_visible(visible_on_card: bool) -> void:
	if _public_equipment_visible == visible_on_card:
		return
	_public_equipment_visible = visible_on_card
	if not is_node_ready():
		return
	_refresh_equipment_rows()


## 写入当前客户端对未知身份的本地标注；身份公开时标注自动失效且不会覆盖真实身份。
func set_identity_mark(identity_mark: String) -> void:
	_identity_mark = identity_mark if identity_mark in ["loyalist", "rebel", "renegade"] else ""
	_refresh_identity_badge()


## 更新合法与选中状态；已选目标始终优先显示金色边框。
func set_target_state(legal_target: bool, selected_target: bool) -> void:
	is_legal_target = legal_target
	is_target_selected = selected_target
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
	# 当前武将全部技能文本；严格保持武将定义顺序，每项分为技能名与技能描述两行。
	var skill_information_lines: Array[String] = []
	# 当前武将结构化技能分段；统一信息框据此把技能名绘制为与右键详情一致的金色，同时保持说明文字颜色不变。
	var skill_description_sections: Array[Dictionary] = []
	for skill_id_variant: Variant in _character_definition.get("skills", []) as Array:
		# 当前技能稳定 ID；用于查询静态技能名称与说明，不读取运行时技能实例。
		var skill_id: String = str(skill_id_variant)
		# 当前技能静态定义；缺失时保留稳定 ID 与明确占位说明，避免整项静默消失。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能完整名称；信息框不截取技能按钮使用的前两个字。
		var skill_name: String = str(skill_definition.get("name", skill_id))
		# 当前技能完整描述；卡牌书名号按全局名称模式解析，其他原文保持不变。
		var skill_description: String = GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。")))
		skill_information_lines.append("【%s】\n%s" % [skill_name, skill_description])
		skill_description_sections.append({
			"title":"【%s】" % skill_name,
			"description":skill_description,
		})
	# 当前武将技能正文；无技能武将使用明确文本，避免空信息框无法判断数据状态。
	var skills_text: String = "\n\n".join(skill_information_lines) if not skill_information_lines.is_empty() else "无技能"
	# 统一武将悬停信息；标题、基础资料和全部技能沿用卡牌悬停接口的固定三个字段。
	var information: Dictionary = {
		"title":character_name,
		"title_emphasis":true,
		"subtitle":"势力：%s｜性别：%s｜体力上限：%d" % [faction_name, gender_text, maximum_health],
		"description":skills_text,
		"description_sections":skill_description_sections,
	}
	information_requested.emit(information, get_global_rect())


## 根据鼠标局部坐标识别其他玩家牌面上的公开装备横条，并请求统一卡牌信息。
func _on_input_pointer_moved(local_position: Vector2) -> void:
	_update_public_equipment_information(local_position)


## 鼠标进入武将牌后请求静态资料；只有选将候选会转发悬停状态以播放缩放反馈。
func _on_input_mouse_entered() -> void:
	_is_hovered = true
	_refresh_hover_name_visibility()
	_request_character_information()
	# 正式对局武将牌不播放选将候选的缩放反馈；只在选将等非对局展示中转发该信号。
	if not _match_overlays_visible:
		hover_changed.emit(true)
	_update_public_equipment_information(_input_area.get_local_mouse_position())


## 鼠标离开武将牌后关闭所属资料；只有选将候选会收到恢复基础尺寸的悬停状态。
func _on_input_mouse_exited() -> void:
	_is_hovered = false
	_refresh_hover_name_visibility()
	if _hovered_equipment_slot.is_empty():
		information_dismissed.emit()
	else:
		_dismiss_public_equipment_information()
	# 与鼠标进入保持对称；正式对局不触发候选牌缩放恢复，避免任何外部监听器改写武将牌尺寸。
	if not _match_overlays_visible:
		hover_changed.emit(false)


## 根据默认、合法、选中与禁用状态刷新角色卡样式。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 角色卡背景；当前行动者略微提亮，帮助玩家定位回合归属。
	var background_color: Color = BattleUIStyle.get_color("player_background") if not is_current_actor else BattleUIStyle.get_color("player_current_background")
	if is_current_operator:
		background_color = BattleUIStyle.get_color("player_operator_background")
	# 角色卡边框；选中金色优先，其次合法青绿，最后使用统一暗金边框。
	var border_color: Color = BattleUIStyle.get_color("border")
	# 角色卡描边宽度；合法或选中时使用3像素，普通状态使用1像素。
	var border_width: int = 1
	if is_target_selected:
		border_color = BattleUIStyle.get_color("accent")
		border_width = 3
	elif is_current_actor:
		border_color = BattleUIStyle.get_color("accent")
		border_width = 3
	elif is_legal_target:
		border_color = BattleUIStyle.get_color("legal_target")
		border_width = 3
	elif is_current_operator:
		border_color = BattleUIStyle.get_color("legal_target").lightened(0.12)
		border_width = 2
	if not is_interactable:
		background_color = BattleUIStyle.get_color("player_disabled_background")
		border_color = BattleUIStyle.get_color("player_disabled_border")
		border_width = 1
	# 角色卡最终样式；当前回合与操作状态只改变底色和边框，不绘制彩色外发光。
	var player_style: StyleBoxFlat = _make_player_style(background_color, border_color, border_width)
	_card_body.add_theme_stylebox_override("panel", player_style)
	_refresh_card_back_style()
	_card_back.visible = is_face_down
	_state_overlay.configure(is_interactable, bool(_player_snapshot.get("chained", false)))


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
	var identity_text: String = {"leader":"领", "loyalist":"忠", "rebel":"反", "renegade":"内", "hidden":"？"}.get(identity, "？")
	# 当前体力；允许为0或负数，牌面心形显示时会安全裁剪。
	var hp: int = int(_player_snapshot.get("hp", 0))
	# 当前体力上限；1至5使用圆点，超过5直接使用数字，因此无需裁剪规则快照中的真实数值。
	var max_hp: int = maxi(int(_player_snapshot.get("max_hp", 0)), 0)
	# 当前公开护盾值；护盾没有上限，异常负数快照在表现层按0处理但不回写规则状态。
	var shield: int = maxi(int(_player_snapshot.get("shield", 0)), 0)
	# 用于心形绘制的安全当前体力；限制在0至可视上限之间。
	var safe_hp: int = clampi(hp, 0, max_hp)
	_character_name_label.text = "\n".join(character_name.split(""))
	_character_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_identity_badge_label.text = identity_text
	_hover_player_name_label.text = str(_player_snapshot.get("display_name", "玩家"))
	_hover_player_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_hand_count_label.text = str(int(_player_snapshot.get("hand_count", 0)))
	_hand_count_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_identity_badge_label.visible = _match_overlays_visible
	_hand_count_label.visible = _match_overlays_visible
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
	_public_zone_label.configure(judgment_names)
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


## 按当前体力和体力上限重建右侧圆点；绿色表示现有体力，暗色表示已损失体力。
## 已损失圆点现在从容器顶部开始排列，使扣血方向固定为从上往下。
## 护盾在圆点模式下使用灰色圆点置于体力上方，体力进入数字模式后护盾同步显示为灰色数字。
func _refresh_health_pips(safe_hp: int, max_hp: int, shield: int) -> void:
	for child: Node in _health_pip_container.get_children():
		_health_pip_container.remove_child(child)
		child.queue_free()
	# 数字模式标志；体力上限超过5时显示“当前/上限”，避免圆点列超出武将牌。
	var uses_numeric_health: bool = max_hp > 5
	_health_pip_container.add_theme_constant_override("separation", 0 if uses_numeric_health else health_pip_separation)
	if uses_numeric_health:
		if shield > 0:
			# 数字护盾标签；与数字体力上下排列，并固定使用灰色语义色区分真实体力。
			var shield_number: Label = Label.new()
			shield_number.text = "盾%d" % shield
			shield_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			shield_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			shield_number.add_theme_font_size_override("font_size", 10)
			shield_number.add_theme_color_override("font_color", BattleUIStyle.get_color("health_shield"))
			shield_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_health_pip_container.add_child(shield_number)
		# 数字体力标签；高上限角色使用分数格式同时展示当前体力与体力上限。
		var health_number: Label = Label.new()
		health_number.text = "%d/%d" % [safe_hp, max_hp]
		health_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		health_number.add_theme_font_size_override("font_size", 10)
		health_number.add_theme_color_override("font_color", _resolve_current_health_color(safe_hp, max_hp, BattleUIStyle.get_color("health_number")))
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
	for slot: String in EQUIPMENT_SLOT_ORDER:
		if not equipment.has(slot) or _equipment_rows.size() >= maximum_equipment_rows:
			continue
		# 当前槽位的公开装备实体牌；只读取序列化数据，不保留可修改的 CardInstance 引用。
		var equipment_card: Dictionary = equipment.get(slot, {}) as Dictionary
		# 当前装备定义；用于按全局名称模式解析牌名，配置缺失时回退到稳定定义 ID。
		var card_definition: Dictionary = GameDatabase.get_card(str(equipment_card.get("definition_id", "")))
		# 当前装备显示名；所有角色牌与手牌共用同一名称切换规则。
		var equipment_name: String = GameSettings.resolve_card_display_name(card_definition) if not card_definition.is_empty() else str(equipment_card.get("definition_id", "未知装备"))
		if bool(card_definition.get("shows_attachment_count", false)):
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
		equipment_row.add_theme_color_override("default_color", BattleUIStyle.get_color("equipment_text"))
		# 装备横条样式；缩小内容边距以在固定60像素条宽内完整显示花色点数与短牌名。
		# 当前横条已扩展到完整插画宽度，并在宝物名称后容纳木牛公开数量。
		var equipment_row_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("equipment_background"), BattleUIStyle.get_color("equipment_border"), 1, 3)
		equipment_row_style.content_margin_left = 2.0
		equipment_row_style.content_margin_top = 0.0
		equipment_row_style.content_margin_right = 2.0
		equipment_row_style.content_margin_bottom = 0.0
		equipment_row.add_theme_stylebox_override("normal", equipment_row_style)
		equipment_row.text = "[center][color=%s]%s%s[/color] %s[/center]" % [_suit_color(suit).to_html(false), _suit_symbol(suit), _rank_text(rank), equipment_name]
		_equipment_layer.add_child(equipment_row)
		_equipment_rows.append(equipment_row)
		_equipment_row_slots.append(slot)
	_layout_equipment_rows()
	if _is_hovered:
		_request_character_information()
		call_deferred("_update_public_equipment_information", _input_area.get_local_mouse_position())


## 根据公开身份与本地标注刷新身份徽记；真实身份始终优先，本地标注只替换未知问号。
func _refresh_identity_badge() -> void:
	if not is_node_ready() or _identity_badge_label == null:
		return
	# 当前公开身份；非 hidden 时必须直接显示权威身份，禁止本地标注覆盖。
	var identity: String = str(_player_snapshot.get("identity", "hidden"))
	# 当前徽记文本；未知身份可使用本地忠、反、内标注，否则保持问号。
	var identity_text: String = {"leader":"领", "loyalist":"忠", "rebel":"反", "renegade":"内"}.get(identity, {"loyalist":"忠", "rebel":"反", "renegade":"内"}.get(_identity_mark, "？"))
	_identity_badge_label.text = identity_text
	# 本地标注使用浅青色与真实金色身份区分，避免玩家把推测误认为公开信息。
	var identity_color: Color = BattleUIStyle.get_color("accent") if identity != "hidden" else (BattleUIStyle.get_color("legal_target") if not _identity_mark.is_empty() else BattleUIStyle.get_color("text_secondary"))
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
			_request_character_information()
		return
	if hovered_slot == _hovered_equipment_slot:
		return
	# 当前玩家公开装备字典；快照只包含对所有观察者可见的装备实体数据。
	var equipment: Dictionary = _player_snapshot.get("equipment", {}) as Dictionary
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


## 关闭当前公开装备横条拥有的信息框；重复调用保持幂等且不会影响其他来源。
func _dismiss_public_equipment_information() -> void:
	if _hovered_equipment_slot.is_empty():
		return
	_hovered_equipment_slot = ""
	information_dismissed.emit()


## 武将牌退出场景树时关闭公开装备信息，避免座位移除后残留旧浮层。
func _exit_tree() -> void:
	_dismiss_public_equipment_information()


## 刷新武将牌统一牌背配色；翻面状态只改变信息遮挡，不改变角色交互权限或规则状态。
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
