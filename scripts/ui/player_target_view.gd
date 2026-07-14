class_name PlayerTargetView
extends Button

## 可复用的角色状态与目标选择组件。组件渲染公开信息、反馈合法性，并接收卡牌拖放，不读取规则核心。

## 卡牌拖放到角色后的请求信号；桌面统一更新选牌与目标顺序。
signal card_dropped(card_uid: int, player_id: int)

## 角色卡默认宽度；默认172像素用于环桌武将牌布局，运行时可按玩家人数调整。
@export_range(150.0, 360.0, 1.0) var panel_width: float = 172.0

## 角色卡默认高度；默认126像素容纳武将插画、体力、手牌、装备与判定信息。
@export_range(110.0, 220.0, 1.0) var panel_height: float = 126.0

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

## 武将插画显示节点；固定占据角色卡左侧区域并忽略鼠标输入。
var _artwork_rect: TextureRect

## 武将插画缺失占位标签；有效插画加载后自动隐藏。
var _artwork_placeholder: Label

## 武将名覆盖层；参考无名杀把角色名固定在牌面底部，避免状态文本随长度改变牌面尺寸。
var _character_name_label: Label

## 身份徽记覆盖层；公开身份显示在牌面右上角，未知身份使用问号徽记。
var _identity_badge_label: Label

## 体力覆盖层；使用实心与空心心形表达当前体力和上限。
var _hp_label: Label

## 手牌数量覆盖层；只显示公开数量，不暴露其他玩家的手牌内容。
var _hand_count_label: Label

## 状态覆盖层；显示行动中、横置或死亡等桌面状态。
var _status_label: Label

## 公开区域覆盖层；显示装备、判定区和木牛“粮”的公开数量，完整名称保留在悬停说明中。
var _public_zone_label: Label

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
	_create_artwork_slot()
	_create_decade_overlay()
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
func configure_snapshot(snapshot: Dictionary, character_definition: Dictionary = {}, current_actor: bool = false) -> void:
	_player_snapshot = snapshot.duplicate(true)
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
	_artwork_rect.size = target_size - Vector2(8.0, 8.0)
	_artwork_placeholder.position = Vector2(4.0, 4.0)
	_artwork_placeholder.size = target_size - Vector2(8.0, 8.0)
	_character_name_label.position = Vector2(6.0, panel_height - 30.0)
	_character_name_label.size = Vector2(panel_width - 12.0, 24.0)
	_identity_badge_label.position = Vector2(panel_width - 38.0, 6.0)
	_hp_label.size = Vector2(panel_width - 48.0, 24.0)
	_hand_count_label.position = Vector2(panel_width - 52.0, panel_height - 54.0)
	_status_label.position = Vector2(6.0, panel_height - 52.0)
	_status_label.size = Vector2(panel_width - 64.0, 20.0)
	_public_zone_label.size = Vector2(panel_width - 12.0, 22.0)


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


## 创建角色卡左侧插画槽；占位层与纹理层不拦截点击或卡牌拖放。
## 十周年纵版布局会把该槽扩展为接近全牌面的立绘区域，名称和状态改由独立覆盖层承载。
func _create_artwork_slot() -> void:
	_artwork_rect = TextureRect.new()
	_artwork_rect.position = Vector2(4.0, 4.0)
	_artwork_rect.size = Vector2(panel_width - 8.0, panel_height - 8.0)
	_artwork_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_artwork_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_artwork_rect)
	_artwork_placeholder = Label.new()
	_artwork_placeholder.position = Vector2(4.0, 4.0)
	_artwork_placeholder.size = Vector2(panel_width - 8.0, panel_height - 8.0)
	_artwork_placeholder.text = "◇\n武将插画预留"
	_artwork_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artwork_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_artwork_placeholder.add_theme_font_size_override("font_size", 11)
	_artwork_placeholder.add_theme_color_override("font_color", Color("a8977f"))
	_artwork_placeholder.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(Color("75664d44"), Color("77664e"), 1, 6))
	_artwork_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_artwork_placeholder)


## 创建覆盖在立绘上的名称、身份、体力和手牌徽记；所有子节点忽略鼠标输入，点击仍由按钮本体处理。
func _create_decade_overlay() -> void:
	_character_name_label = _make_overlay_label(Vector2(6.0, panel_height - 30.0), Vector2(panel_width - 12.0, 24.0), 14)
	_character_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_character_name_label)
	_identity_badge_label = _make_overlay_label(Vector2(panel_width - 38.0, 6.0), Vector2(32.0, 24.0), 12)
	_identity_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_identity_badge_label)
	_hp_label = _make_overlay_label(Vector2(6.0, 6.0), Vector2(panel_width - 48.0, 24.0), 13)
	add_child(_hp_label)
	_hand_count_label = _make_overlay_label(Vector2(panel_width - 52.0, panel_height - 54.0), Vector2(46.0, 20.0), 11)
	_hand_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hand_count_label)
	_status_label = _make_overlay_label(Vector2(6.0, panel_height - 52.0), Vector2(panel_width - 64.0, 20.0), 10)
	add_child(_status_label)
	_public_zone_label = _make_overlay_label(Vector2(6.0, 34.0), Vector2(panel_width - 12.0, 22.0), 9)
	_public_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_public_zone_label)


## 创建统一的牌面覆盖文字控件；背景和边框使用十周年风格的半透明金属色。
func _make_overlay_label(label_position: Vector2, label_size: Vector2, font_size: int) -> Label:
	# 新建的覆盖文字节点；返回后由角色卡持有并在尺寸变化时更新位置。
	var label: Label = Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff1c8"))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	# 覆盖文字背景；使用极小内容边距，确保身份徽记等窄控件仍能完整显示单字。
	var overlay_style: StyleBoxFlat = BattleUIStyle.make_panel(Color("17120fb8"), Color("8c744888"), 1, 3)
	overlay_style.content_margin_left = 2.0
	overlay_style.content_margin_top = 1.0
	overlay_style.content_margin_right = 2.0
	overlay_style.content_margin_bottom = 1.0
	label.add_theme_stylebox_override("normal", overlay_style)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 根据公开快照更新牌面覆盖文字；缺少角色配置时仍保留稳定玩家名称与体力信息。
func _refresh_decade_overlay(character_definition: Dictionary = {}) -> void:
	if _character_name_label == null:
		return
	# 武将显示名；优先读取静态配置，配置缺失时回退到稳定角色 ID。
	var character_name: String = str(character_definition.get("display_name", _player_snapshot.get("character_id", "未选武将")))
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
	_character_name_label.text = character_name
	_identity_badge_label.text = identity_text
	_hp_label.text = "♥".repeat(safe_hp) + "♡".repeat(max_hp - safe_hp)
	_hand_count_label.text = "手牌 %d" % int(_player_snapshot.get("hand_count", 0))
	_status_label.text = "行动中" if is_current_actor else ("已死亡" if disabled else ("横置" if bool(_player_snapshot.get("chained", false)) else ""))
	_public_zone_label.text = "装%d　判%d　粮%d" % [
		(_player_snapshot.get("equipment", {}) as Dictionary).size(),
		(_player_snapshot.get("judgment_area", []) as Array).size(),
		int(_player_snapshot.get("wooden_ox_storage_count", 0)),
	]
	_identity_badge_label.add_theme_color_override("font_color", BattleUIStyle.ACCENT_COLOR if identity != "hidden" else Color("d8c8a8"))


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
	return "%s｜%s\n体力 %d/%d｜手牌 %d｜粮 %d\n装备：%s\n判定：%s" % [
		str(snapshot.get("display_name", "玩家")),
		str(character_definition.get("display_name", snapshot.get("character_id", "未选武将"))),
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
	var style: StyleBoxFlat = BattleUIStyle.make_inset_panel(background_color, border_color, border_width, 6)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style
