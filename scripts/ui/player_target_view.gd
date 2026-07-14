class_name PlayerTargetView
extends Button

## 可复用的角色状态与目标选择组件。组件渲染公开信息、反馈合法性，并接收卡牌拖放，不读取规则核心。

## 卡牌拖放到角色后的请求信号；桌面统一更新选牌与目标顺序。
signal card_dropped(card_uid: int, player_id: int)

## 角色卡默认宽度；默认172像素用于环桌武将牌布局，运行时可按玩家人数调整。
## 参考图纵版布局由座次组件覆盖为118像素或104像素，本地玩家使用150像素；该默认值仅供独立实例化回退。
@export_range(150.0, 360.0, 1.0) var panel_width: float = 172.0

## 角色卡默认高度；默认126像素容纳武将插画、体力、手牌、装备与判定信息。
## 参考图纵版布局由座次组件覆盖为172像素或156像素，本地玩家使用240像素；该默认值仅供独立实例化回退。
@export_range(110.0, 280.0, 1.0) var panel_height: float = 126.0

## 牌面底部为中文座次号保留的高度；默认18像素接近参考图外置金色座次标记，运行时通常无需动态修改。
@export_range(14.0, 30.0, 1.0) var seat_label_height: float = 18.0

## 单条装备牌信息占用的高度；默认18像素可在常规武将牌上同时叠放五个装备槽，运行时通常无需动态修改。
@export_range(14.0, 26.0, 1.0) var equipment_row_height: float = 18.0

## 牌面允许显示的装备条目上限；默认5对应武器、防具、进攻坐骑、防御坐骑和宝物五个固定槽位。
@export_range(1, 5, 1) var maximum_equipment_rows: int = 5

## 当前角色稳定玩家 ID；由 configure 写入，未配置时为 -1。
var player_id: int = -1

## 当前角色是否是所选牌的合法候选目标；只控制青绿色提示。
var is_legal_target: bool = false

## 当前角色是否已加入目标顺序；选中状态优先使用金色提示。
var is_target_selected: bool = false

## 当前角色是否正在行动；行动状态使用左侧文本标记，不影响目标合法性。
var is_current_actor: bool = false

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

## 体力覆盖层；使用实心与空心心形表达当前体力和上限。
## 当前参考图格式保留该旧覆盖层为隐藏兼容节点，实际体力由右侧 `_health_pip_container` 圆点列显示。
@onready var _hp_label: Label = $LegacyHp

## 手牌数量覆盖层；只显示公开数量，不暴露其他玩家的手牌内容。
@onready var _hand_count_label: Label = $HandCount

## 状态覆盖层；显示行动中、横置或死亡等桌面状态。
@onready var _status_label: Label = $Status

## 公开区域覆盖层；显示装备、判定区和木牛“粮”的公开数量，完整名称保留在悬停说明中。
## 当前参考图格式只在该层显示判定区与“粮”数量，公开装备改由独立横条完整显示花色、点数和牌名。
@onready var _public_zone_label: Label = $PublicZone

## 势力圆形徽记；显示势力简称并使用数据配置的主题颜色，不参与身份或胜负判断。
@onready var _faction_badge_label: Label = $FactionBadge

## 座次号覆盖层；位于武将牌底边外侧并把从0开始的玩家 ID 转换为中文序号。
@onready var _seat_label: Label = $Seat

## 纵向体力圆点容器；按体力上限生成圆点，当前体力使用绿色、已损失体力使用暗色。
@onready var _health_pip_container: VBoxContainer = $HealthPips

## 装备条目承载层；公开装备以参考图中的浅色横条从牌面下部向上叠放。
@onready var _equipment_layer: Control = $EquipmentLayer

## 当前已创建的装备条目控件；每次快照更新时整体重建，最多包含五个固定装备槽。
var _equipment_rows: Array[RichTextLabel] = []

## 当前武将所属势力的展示元数据；仅保存配置深拷贝，不持有全局数据索引的可修改引用。
var _faction_definition: Dictionary = {}

## 装备槽的固定显示顺序；保证武器、防具、进攻坐骑、防御坐骑和宝物在所有客户端一致排列。
const EQUIPMENT_SLOT_ORDER: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]

## 当前角色公开快照；仅用于刷新视觉层，不保留任何可修改的规则对象引用。
var _player_snapshot: Dictionary = {}


## 初始化角色卡尺寸、文本布局和指针反馈。
func _ready() -> void:
	custom_minimum_size = Vector2(panel_width, panel_height)
	focus_mode = Control.FOCUS_NONE
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 12)
	_refresh_artwork()
	_refresh_decade_overlay()
	_refresh_visual_state()


## 写入角色公开快照与已经格式化的状态文本；组件不持有可修改的 PlayerState 引用。
func configure(id: int, formatted_text: String, alive: bool, current_actor: bool, character_definition: Dictionary = {}) -> void:
	player_id = id
	is_current_actor = current_actor
	text = ("◆ 行动中\n" if is_current_actor else "") + formatted_text
	disabled = not alive
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	_refresh_artwork()
	_refresh_visual_state()


## 写入公开角色快照并刷新十周年牌面覆盖层；调用方传入的是裁剪后的 Dictionary 副本。
func configure_snapshot(snapshot: Dictionary, character_definition: Dictionary = {}, current_actor: bool = false, faction_definition: Dictionary = {}) -> void:
	_player_snapshot = snapshot.duplicate(true)
	_faction_definition = faction_definition.duplicate(true)
	player_id = int(snapshot.get("player_id", -1))
	is_current_actor = current_actor
	disabled = not bool(snapshot.get("alive", false))
	text = ""
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	tooltip_text = _format_snapshot_tooltip(snapshot, character_definition)
	_refresh_artwork()
	_refresh_decade_overlay(character_definition)
	_refresh_visual_state()


## 同步布局组件分配的武将牌尺寸；紧凑多人模板会通过该入口更新全部覆盖层几何信息。
func apply_panel_size(target_size: Vector2) -> void:
	panel_width = target_size.x
	panel_height = target_size.y
	custom_minimum_size = target_size
	size = target_size
	if _artwork_rect == null:
		return
	_artwork_rect.position = Vector2(4.0, 4.0)
	_artwork_rect.size = Vector2(target_size.x - 8.0, maxf(target_size.y - seat_label_height - 8.0, 1.0))
	_artwork_placeholder.position = Vector2(4.0, 4.0)
	_artwork_placeholder.size = Vector2(target_size.x - 8.0, maxf(target_size.y - seat_label_height - 8.0, 1.0))
	_layout_reference_overlay()


## 更新合法与选中状态；已选目标始终优先显示金色边框。
func set_target_state(legal_target: bool, selected_target: bool) -> void:
	is_legal_target = legal_target
	is_target_selected = selected_target
	_refresh_visual_state()


## 仅接受战斗卡牌组件提供的拖放字典；死亡角色和非法目标不会接收。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return not disabled and is_legal_target and data is Dictionary and str((data as Dictionary).get("drag_type", "")) == "battle_card"


## 将拖放转换为桌面层信号；组件不直接改变选择集合或提交动作。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# 卡牌 UID；来源于 CardView 的稳定拖放数据。
	var dropped_card_uid: int = int((data as Dictionary).get("card_uid", -1))
	if dropped_card_uid >= 0:
		card_dropped.emit(dropped_card_uid, player_id)


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
	add_theme_color_override("font_color", Color("f3e7d0"))
	add_theme_color_override("font_hover_color", Color("fff0c7"))
	add_theme_color_override("font_disabled_color", Color("80766c"))
	add_theme_stylebox_override("normal", _make_player_style(background_color, border_color, border_width))
	add_theme_stylebox_override("hover", _make_player_style(background_color.lightened(0.08), border_color.lightened(0.12), maxi(border_width, 2)))
	add_theme_stylebox_override("pressed", _make_player_style(background_color.darkened(0.06), BattleUIStyle.ACCENT_COLOR, 3))
	add_theme_stylebox_override("disabled", _make_player_style(Color("292724"), Color("544f49"), 1))
	if _status_label != null:
		_status_label.modulate = Color(1.0, 1.0, 1.0, 0.52 if disabled else 1.0)


## 按当前牌面尺寸复刻参考图的竖名牌、右侧体力、左下手牌数、外置座次号和装备叠层布局。
func _layout_reference_overlay() -> void:
	if _character_name_label == null:
		return
	# 牌面主体高度；底部座次号使用独立区域，不覆盖武将立绘和装备条目。
	var card_body_height: float = maxf(panel_height - seat_label_height, 1.0)
	# 左侧武将名竖条宽度；按牌宽比例缩放并限制范围，兼容紧凑多人牌与本地大牌。
	var name_banner_width: float = clampf(panel_width * 0.23, 22.0, 34.0)
	# 右侧体力圆点列宽度；保持足够触点面积，同时不明显遮挡立绘主体。
	var health_column_width: float = clampf(panel_width * 0.16, 17.0, 24.0)
	# 顶部势力徽记边长；圆形徽记略宽于名称竖条，形成参考图中的外凸层级。
	var faction_badge_size: float = clampf(panel_width * 0.27, 28.0, 40.0)
	# 左下手牌角标边长；使用接近正方形的红色角标突出公开手牌数量。
	var hand_badge_size: float = clampf(panel_width * 0.27, 28.0, 40.0)
	_artwork_rect.position = Vector2(4.0, 4.0)
	_artwork_rect.size = Vector2(maxf(panel_width - 8.0, 1.0), maxf(card_body_height - 8.0, 1.0))
	_artwork_placeholder.position = Vector2(4.0, 4.0)
	_artwork_placeholder.size = _artwork_rect.size
	_faction_badge_label.position = Vector2(1.0, 0.0)
	_faction_badge_label.size = Vector2(faction_badge_size, faction_badge_size)
	_character_name_label.position = Vector2(4.0, faction_badge_size - 3.0)
	_character_name_label.size = Vector2(name_banner_width, maxf(card_body_height - faction_badge_size - hand_badge_size + 4.0, 32.0))
	_identity_badge_label.position = Vector2(panel_width - 31.0, 4.0)
	_identity_badge_label.size = Vector2(27.0, 24.0)
	_hand_count_label.position = Vector2(2.0, card_body_height - hand_badge_size - 1.0)
	_hand_count_label.size = Vector2(hand_badge_size, hand_badge_size)
	_status_label.position = Vector2(name_banner_width + 9.0, 5.0)
	_status_label.size = Vector2(maxf(panel_width - name_banner_width - 45.0, 28.0), 18.0)
	_public_zone_label.position = Vector2(name_banner_width + 8.0, card_body_height - 22.0)
	_public_zone_label.size = Vector2(maxf(panel_width - name_banner_width - health_column_width - 14.0, 30.0), 17.0)
	_seat_label.position = Vector2(0.0, card_body_height)
	_seat_label.size = Vector2(panel_width, seat_label_height)
	_health_pip_container.position = Vector2(panel_width - health_column_width - 2.0, card_body_height * 0.24)
	_health_pip_container.size = Vector2(health_column_width, card_body_height * 0.56)
	_equipment_layer.position = Vector2.ZERO
	_equipment_layer.size = Vector2(panel_width, card_body_height)
	_character_name_label.add_theme_font_size_override("font_size", 12 if panel_width >= 116.0 else 10)
	_seat_label.add_theme_font_size_override("font_size", 18 if panel_width >= 116.0 else 15)
	_layout_equipment_rows(name_banner_width, health_column_width, card_body_height)


## 根据已生成装备条目重新计算叠放位置；装备越多越向牌面中部延伸，槽位顺序保持稳定。
func _layout_equipment_rows(name_banner_width: float, health_column_width: float, card_body_height: float) -> void:
	if _equipment_rows.is_empty():
		return
	# 装备条目左边界；从竖名牌右侧开始，避免遮挡武将名和势力徽记。
	var row_left: float = name_banner_width + 9.0
	# 装备条目可用宽度；右侧为体力圆点列保留固定安全区。
	var row_width: float = maxf(panel_width - row_left - health_column_width - 5.0, 42.0)
	# 全部装备条目总高度；相邻横条轻微覆盖1像素以模拟参考图的叠牌效果。
	var rows_height: float = equipment_row_height + float(_equipment_rows.size() - 1) * (equipment_row_height - 1.0)
	# 第一条装备的纵坐标；从牌面下部向上展开，并为底部公开区域提示预留空间。
	var start_y: float = maxf(card_body_height - rows_height - 28.0, 35.0)
	for row_index: int in range(_equipment_rows.size()):
		# 当前装备横条；只更新几何信息，不改变其装备数据或显示文本。
		var equipment_row: RichTextLabel = _equipment_rows[row_index]
		equipment_row.position = Vector2(row_left, start_y + float(row_index) * (equipment_row_height - 1.0))
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
	# 当前体力上限；最多绘制10枚心形，异常更高数值仍可从悬停说明读取。
	var max_hp: int = clampi(int(_player_snapshot.get("max_hp", 0)), 0, 10)
	# 用于心形绘制的安全当前体力；限制在0至可视上限之间。
	var safe_hp: int = clampi(hp, 0, max_hp)
	_character_name_label.text = "\n".join(character_name.split(""))
	_identity_badge_label.text = identity_text
	_hand_count_label.text = str(int(_player_snapshot.get("hand_count", 0)))
	_status_label.text = "行动" if is_current_actor else ("阵亡" if disabled else ("横置" if bool(_player_snapshot.get("chained", false)) else ""))
	# 判定区公开数量；没有判定牌时不显示该摘要，避免覆盖装备横条和武将立绘。
	var judgment_count: int = (_player_snapshot.get("judgment_area", []) as Array).size()
	# 木牛流马“粮”公开数量；没有“粮”时不显示该摘要，完整牌面仍只对所有者可见。
	var wooden_ox_count: int = int(_player_snapshot.get("wooden_ox_storage_count", 0))
	_public_zone_label.text = ("判%d" % judgment_count if judgment_count > 0 else "") + (" 粮%d" % wooden_ox_count if wooden_ox_count > 0 else "")
	_public_zone_label.visible = not _public_zone_label.text.is_empty()
	_faction_badge_label.text = faction_short_name
	_faction_badge_label.tooltip_text = faction_name
	# 势力徽记样式；清空通用面板的大内边距，保证紧凑圆徽中的单字完整显示。
	var faction_badge_style: StyleBoxFlat = BattleUIStyle.make_panel(faction_color.darkened(0.28), faction_color.lightened(0.36), 2, 18)
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
	var hand_badge_style: StyleBoxFlat = BattleUIStyle.make_panel(Color("9e3528"), Color("f0ad36"), 2, 4)
	hand_badge_style.content_margin_left = 0.0
	hand_badge_style.content_margin_top = 0.0
	hand_badge_style.content_margin_right = 0.0
	hand_badge_style.content_margin_bottom = 0.0
	_hand_count_label.add_theme_stylebox_override("normal", hand_badge_style)
	_seat_label.text = _seat_text(player_id + 1)
	_refresh_health_pips(safe_hp, max_hp)
	_refresh_equipment_rows()
	_identity_badge_label.add_theme_color_override("font_color", BattleUIStyle.ACCENT_COLOR if identity != "hidden" else Color("d8c8a8"))
	_layout_reference_overlay()


## 按当前体力和体力上限重建右侧圆点；绿色表示现有体力，暗色表示已损失体力。
func _refresh_health_pips(safe_hp: int, max_hp: int) -> void:
	for child: Node in _health_pip_container.get_children():
		_health_pip_container.remove_child(child)
		child.queue_free()
	for pip_index: int in range(max_hp):
		# 当前体力圆点；索引小于当前体力时点亮，其余保留暗色上限占位。
		var health_pip: Label = Label.new()
		health_pip.text = "●"
		health_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_pip.add_theme_font_size_override("font_size", 14 if panel_width >= 116.0 else 12)
		health_pip.add_theme_color_override("font_color", Color("44ca67") if pip_index < safe_hp else Color("26382c"))
		health_pip.add_theme_color_override("font_shadow_color", Color("07140a"))
		health_pip.add_theme_constant_override("shadow_offset_x", 1)
		health_pip.add_theme_constant_override("shadow_offset_y", 1)
		health_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_pip_container.add_child(health_pip)


## 按固定槽位顺序把公开装备转换为参考图中的花色点数与牌名横条。
func _refresh_equipment_rows() -> void:
	for equipment_row: RichTextLabel in _equipment_rows:
		if equipment_row != null and is_instance_valid(equipment_row):
			_equipment_layer.remove_child(equipment_row)
			equipment_row.queue_free()
	_equipment_rows.clear()
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
		equipment_row.add_theme_font_size_override("normal_font_size", 9 if panel_width >= 116.0 else 8)
		equipment_row.add_theme_color_override("default_color", Color("33281e"))
		# 装备横条样式；缩小内容边距以在紧凑牌宽内完整显示花色点数与短牌名。
		var equipment_row_style: StyleBoxFlat = BattleUIStyle.make_panel(Color("dfd2adf2"), Color("8d7147"), 1, 3)
		equipment_row_style.content_margin_left = 2.0
		equipment_row_style.content_margin_top = 0.0
		equipment_row_style.content_margin_right = 2.0
		equipment_row_style.content_margin_bottom = 0.0
		equipment_row.add_theme_stylebox_override("normal", equipment_row_style)
		equipment_row.text = "[center][color=%s]%s%s[/color] %s[/center]" % [_suit_color(suit).to_html(false), _suit_symbol(suit), _rank_text(rank), equipment_name]
		_equipment_layer.add_child(equipment_row)
		_equipment_rows.append(equipment_row)


## 返回一至十号座次的中文数字；超出当前模式上限时回退到阿拉伯数字保证扩展安全。
func _seat_text(seat_number: int) -> String:
	return {1:"一", 2:"二", 3:"三", 4:"四", 5:"五", 6:"六", 7:"七", 8:"八", 9:"九", 10:"十"}.get(seat_number, str(seat_number))


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
	for equipment_variant: Variant in (snapshot.get("equipment", {}) as Dictionary).values():
		# 当前公开装备快照；只读取定义 ID 解析显示名。
		var equipment_card: Dictionary = equipment_variant as Dictionary
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
