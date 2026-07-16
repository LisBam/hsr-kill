class_name PlayerTargetView
extends Node2D

## 可复用的角色状态与目标选择组件。组件渲染公开信息、反馈合法性，并接收卡牌拖放，不读取规则核心。

## 武将牌被点击时发出的信号；桌面据此更新目标选择，不直接提交规则动作。
signal pressed

## 卡牌拖放到角色后的请求信号；桌面统一更新选牌与目标顺序。
signal card_dropped(card_uid: int, player_id: int)

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

## 装备槽的固定显示顺序；保证武器、防具、进攻坐骑、防御坐骑和宝物在所有客户端一致排列。
const EQUIPMENT_SLOT_ORDER: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]

## 当前角色公开快照；仅用于刷新视觉层，不保留任何可修改的规则对象引用。
var _player_snapshot: Dictionary = {}

## 最近一次公开快照配置签名；默认-1表示从未配置，未变化的角色不会重复加载立绘、重建体力圆点、装备横条或判定标记。
var _configuration_signature: int = -1

## 武将牌背景面板；承载边框和纸面样式，不承担 Button 语义或规则状态。
@onready var _card_body: Panel = $CardBody

## 牌背覆盖层；默认隐藏，显示时覆盖武将插画、状态与公开区域，但保留输入区域可用。
@onready var _card_back: Panel = get_node("牌背") as Panel

## 独立输入区域；覆盖整张武将牌并负责点击与卡牌拖放协议。
@onready var _input_area: PlayerTargetInputArea = $InputArea


## 初始化武将牌视觉与独立输入区域；静态几何完全由场景资源定义。
func _ready() -> void:
	_card_body.size = card_size
	_card_back.size = card_size
	_input_area.size = card_size
	_health_pip_container.add_theme_constant_override("separation", health_pip_separation)
	_input_area.activated.connect(pressed.emit)
	_input_area.card_dropped.connect(_on_input_card_dropped)
	_input_area.configure(is_interactable, is_legal_target)
	_refresh_artwork()
	_refresh_decade_overlay()
	_refresh_visual_state()


## 返回武将牌在全局画布中的矩形；卡牌动画通过该接口取得角色中心点。
func get_global_rect() -> Rect2:
	return Rect2(global_position, card_size * global_scale)


## 写入角色公开快照与已经格式化的状态文本；组件不持有可修改的 PlayerState 引用。
func configure(id: int, formatted_text: String, alive: bool, current_actor: bool, character_definition: Dictionary = {}) -> void:
	player_id = id
	is_current_actor = current_actor
	is_interactable = alive
	is_face_down = false
	# 兼容格式化文本；旧调用方仍可传入摘要，该内容只作为无障碍悬停说明，不绘制按钮正文。
	var accessibility_summary: String = ("◆ 行动中\n" if is_current_actor else "") + formatted_text
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = accessibility_summary
		_input_area.configure(is_interactable, is_legal_target)
	_refresh_artwork()
	_refresh_visual_state()


## 写入公开角色快照并刷新十周年牌面覆盖层；调用方传入的是裁剪后的 Dictionary 副本。
func configure_snapshot(snapshot: Dictionary, character_definition: Dictionary = {}, current_actor: bool = false, faction_definition: Dictionary = {}) -> void:
	# 本次完整配置签名；名称模式影响装备与悬停文本，因此必须参与缓存失效判断。
	var next_configuration_signature: int = hash([snapshot, character_definition, current_actor, faction_definition, GameSettings.card_name_mode])
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	_player_snapshot = snapshot.duplicate(true)
	_faction_definition = faction_definition.duplicate(true)
	player_id = int(snapshot.get("player_id", -1))
	is_current_actor = current_actor
	is_interactable = bool(snapshot.get("alive", false))
	is_face_down = bool(snapshot.get("face_down", false))
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = _format_snapshot_tooltip(snapshot, character_definition)
		_input_area.configure(is_interactable, is_legal_target)
	_refresh_artwork()
	_refresh_decade_overlay(character_definition)
	_refresh_visual_state()


## 设置身份与手牌数标识是否进入正式对局显示；选将面板不调用此接口，因此保持场景默认隐藏。
func set_match_overlays_visible(visible_in_match: bool) -> void:
	_match_overlays_visible = visible_in_match
	if not is_node_ready():
		return
	_identity_badge_label.visible = _match_overlays_visible
	_hand_count_label.visible = _match_overlays_visible


## 更新合法与选中状态；已选目标始终优先显示金色边框。
func set_target_state(legal_target: bool, selected_target: bool) -> void:
	is_legal_target = legal_target
	is_target_selected = selected_target
	if is_node_ready():
		_input_area.configure(is_interactable, is_legal_target)
	_refresh_visual_state()


## 转发独立输入区域的合法卡牌拖放结果，并补充当前稳定玩家 ID。
func _on_input_card_dropped(card_uid: int) -> void:
	card_dropped.emit(card_uid, player_id)


## 根据默认、合法、选中与禁用状态刷新角色卡样式。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 角色卡背景；当前行动者略微提亮，帮助玩家定位回合归属。
	var background_color: Color = Color("211d1af2") if not is_current_actor else Color("3a3023f5")
	# 角色卡边框；选中金色优先，其次合法青绿，最后使用统一暗金边框。
	var border_color: Color = BattleUIStyle.GOLD_BORDER_COLOR
	# 角色卡描边宽度；合法或选中时使用3像素，普通状态使用1像素。
	var border_width: int = 1
	if is_target_selected:
		border_color = BattleUIStyle.ACCENT_COLOR
		border_width = 3
	elif is_legal_target:
		border_color = BattleUIStyle.LEGAL_TARGET_COLOR
		border_width = 3
	if not is_interactable:
		background_color = Color("292724")
		border_color = Color("544f49")
		border_width = 1
	_card_body.add_theme_stylebox_override("panel", _make_player_style(background_color, border_color, border_width))
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
	# 公开身份 ID；其他玩家身份尚未公开时为 hidden。
	var identity: String = str(_player_snapshot.get("identity", "hidden"))
	# 身份徽记单字；用于在窄牌面右上角保持可读。
	var identity_text: String = {"lord":"主", "loyalist":"忠", "rebel":"反", "renegade":"内", "hidden":"?"}.get(identity, "?")
	# 当前体力；允许为0或负数，牌面心形显示时会安全裁剪。
	var hp: int = int(_player_snapshot.get("hp", 0))
	# 当前体力上限；1至5使用圆点，超过5直接使用数字，因此无需裁剪规则快照中的真实数值。
	var max_hp: int = maxi(int(_player_snapshot.get("max_hp", 0)), 0)
	# 用于心形绘制的安全当前体力；限制在0至可视上限之间。
	var safe_hp: int = clampi(hp, 0, max_hp)
	_character_name_label.text = "\n".join(character_name.split(""))
	_identity_badge_label.text = identity_text
	_hand_count_label.text = str(int(_player_snapshot.get("hand_count", 0)))
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
	_faction_badge_label.tooltip_text = faction_name
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
	# 手牌数角标样式；朱红底与金边对应参考图左下角的高对比数字徽记。
	var hand_badge_style: StyleBoxFlat = BattleUIStyle.make_panel(Color("9e3528"), Color("f0ad36"), 1, 3)
	hand_badge_style.content_margin_left = 0.0
	hand_badge_style.content_margin_top = 0.0
	hand_badge_style.content_margin_right = 0.0
	hand_badge_style.content_margin_bottom = 0.0
	_hand_count_label.add_theme_stylebox_override("normal", hand_badge_style)
	_refresh_health_pips(safe_hp, max_hp)
	_refresh_equipment_rows()
	_identity_badge_label.add_theme_color_override("font_color", BattleUIStyle.ACCENT_COLOR if identity != "hidden" else Color("d8c8a8"))


## 按当前体力和体力上限重建右侧圆点；绿色表示现有体力，暗色表示已损失体力。
## 已损失圆点现在从容器顶部开始排列，使扣血方向固定为从上往下。
func _refresh_health_pips(safe_hp: int, max_hp: int) -> void:
	for child: Node in _health_pip_container.get_children():
		_health_pip_container.remove_child(child)
		child.queue_free()
	# 数字模式标志；体力上限超过5时显示“当前/上限”，避免圆点列超出武将牌。
	var uses_numeric_health: bool = max_hp > 5
	if uses_numeric_health:
		# 数字体力标签；高上限角色使用分数格式同时展示当前体力与体力上限。
		var health_number: Label = Label.new()
		health_number.text = "%d/%d" % [safe_hp, max_hp]
		health_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		health_number.add_theme_font_size_override("font_size", 10)
		health_number.add_theme_color_override("font_color", Color("e7d59b"))
		health_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_pip_container.add_child(health_number)
		_layout_health_frame(true)
		return
	for pip_index: int in range(max_hp):
		# 当前体力圆点；索引小于当前体力时点亮，其余保留暗色上限占位。
		# 当前颜色判断改用顶部已损失数量，剩余圆点继续使用相同绿色与暗色。
		var health_pip: Label = Label.new()
		health_pip.text = "●"
		health_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_pip.add_theme_font_size_override("font_size", health_pip_font_size)
		health_pip.add_theme_color_override("font_color", Color("26382c") if pip_index < max_hp - safe_hp else Color("44ca67"))
		health_pip.add_theme_color_override("font_shadow_color", Color("07140a"))
		health_pip.add_theme_constant_override("shadow_offset_x", 1)
		health_pip.add_theme_constant_override("shadow_offset_y", 1)
		health_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_pip_container.add_child(health_pip)
	_layout_health_frame(false)


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
	for equipment_row: RichTextLabel in _equipment_rows:
		if equipment_row != null and is_instance_valid(equipment_row):
			_equipment_layer.remove_child(equipment_row)
			equipment_row.queue_free()
	_equipment_rows.clear()
	_equipment_row_slots.clear()
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
		var equipment_name: String = GameSettings.resolve_card_name(card_definition) if not card_definition.is_empty() else str(equipment_card.get("definition_id", "未知装备"))
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
		equipment_row.add_theme_color_override("default_color", Color("33281e"))
		# 装备横条样式；缩小内容边距以在固定60像素条宽内完整显示花色点数与短牌名。
		# 当前横条已扩展到完整插画宽度，并在宝物名称后容纳木牛公开数量。
		var equipment_row_style: StyleBoxFlat = BattleUIStyle.make_panel(Color("dfd2adf2"), Color("8d7147"), 1, 3)
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
	return "%s｜%s｜%s\n体力 %d/%d｜手牌 %d｜粮 %d\n装备：%s\n判定：%s" % [
		str(snapshot.get("display_name", "玩家")),
		GameDatabase.resolve_character_name(str(snapshot.get("character_id", ""))),
		faction_name,
		int(snapshot.get("hp", 0)),
		int(snapshot.get("max_hp", 0)),
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
