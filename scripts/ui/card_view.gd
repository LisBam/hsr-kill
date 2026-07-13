class_name CardView
extends Button

## 可复用的实体卡牌视图。组件只负责牌面显示、点击选择与 Godot 拖放数据，不提交任何对局动作。

## 拖拽开始信号；参数为稳定卡牌 UID，桌面可据此同步当前选择。
signal card_drag_started(card_uid: int)

## 卡牌宽度；默认108像素适合1440×900桌面，运行时无需动态修改。
@export_range(88.0, 180.0, 1.0) var card_width: float = 108.0

## 卡牌高度；默认148像素保持接近实体牌比例，运行时无需动态修改。
@export_range(120.0, 240.0, 1.0) var card_height: float = 148.0

## 选中后向上抬升的像素数；默认14像素提供明确反馈，运行时可由主题配置调整。
@export_range(0.0, 36.0, 1.0) var selected_lift: float = 14.0

## 鼠标悬停时的缩放倍率；默认1.06提供轻量实体牌靠近反馈，运行时可动态调整。
@export_range(1.0, 1.2, 0.01) var hover_scale: float = 1.06

## 悬停缩放动画时长；默认0.12秒保证反馈迅速且不过度跳动，运行时可调整。
@export_range(0.05, 0.4, 0.01) var hover_animation_seconds: float = 0.12

## 当前实体牌 UID；由 configure 写入，未配置时为 -1。
var card_uid: int = -1

## 当前牌是否来自木牛流马“粮”；用于显示独立来源标记。
var is_wooden_ox_card: bool = false

## 当前牌是否被桌面选中；只影响视觉状态，不代表规则合法。
var is_card_selected: bool = false

## 当前牌是否可在本地出牌阶段交互；禁用时仍展示牌面信息。
var is_interactable: bool = false

## 卡牌未选中时的原始布局位置；选择抬升只通过样式与偏移表达。
var _base_position_y: float = 0.0

## 当前卡牌插画纹理；配置缺失或文件无效时为 null，并显示占位区。
var _artwork_texture: Texture2D

## 牌面插画显示节点；固定占据卡牌中部，不参与鼠标输入。
var _artwork_rect: TextureRect

## 插画缺失占位标签；后期配置有效 art_path 后自动隐藏。
var _artwork_placeholder: Label

## 左上角花色点数标签；独立于插画区域，保证任何图片亮度下都清晰可读。
var _corner_label: Label

## 卡牌名称标签；固定显示在插画下方，统一使用全局名称模式。
var _name_label: Label

## 卡牌类别与木牛来源标签；固定显示在牌面底部。
var _type_label: Label

## 待显示的花色点数字符串；configure 可能在节点进入场景树前调用，因此先保存文本。
var _suit_rank_text: String = ""

## 待显示的卡牌名称；节点准备完成后写入名称标签。
var _display_name_text: String = ""

## 待显示的类别文本；包含可选的木牛“粮”来源标记。
var _card_type_text: String = ""

## 当前卡牌类别强调色；基本牌、锦囊牌、装备牌和属性杀使用不同色条。
var _category_color: Color = Color("765b3d")

## 牌面顶部类别色条；只表达视觉分类，不参与卡牌规则判断。
var _accent_bar: ColorRect

## 当前悬停缩放动画；新动画开始前会停止旧动画以避免连续进入离开产生抖动。
var _hover_tween: Tween


## 初始化卡牌控件的尺寸、排版、焦点与鼠标行为。
func _ready() -> void:
	custom_minimum_size = Vector2(card_width, card_height)
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = Vector2(card_width * 0.5, card_height * 0.5)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_create_card_content()
	_refresh_card_content()
	_refresh_visual_state()


## 写入牌面快照和定义；该方法不保存完整对局状态，可在每次快照重建时安全调用。
func configure(card: Dictionary, definition: Dictionary, wooden_ox_card: bool, interactable: bool) -> void:
	card_uid = int(card.get("uid", -1))
	is_wooden_ox_card = wooden_ox_card
	is_interactable = interactable
	# 花色文本；红色花色使用单独字体色，黑色花色保持深褐色。
	var suit_text: String = _suit_symbol(str(card.get("suit", "")))
	# 点数文本；A、J、Q、K使用标准牌面字符。
	var rank_text: String = _rank_text(int(card.get("rank", 0)))
	# 卡牌显示名；统一通过全局名称模式解析，禁止组件自行维护双名称分支。
	var display_name: String = GameSettings.resolve_card_name(definition)
	# 卡牌类别文本；用于牌面底部帮助玩家快速区分基本牌、锦囊牌与装备牌。
	var type_text: String = _type_text(str(definition.get("type", "")))
	_suit_rank_text = "%s%s" % [suit_text, rank_text]
	_display_name_text = display_name
	_card_type_text = "%s%s" % ["粮 · " if is_wooden_ox_card else "", type_text]
	_category_color = _resolve_category_color(definition)
	_artwork_texture = ArtworkLoader.load_from_definition(definition, ArtworkLoader.CARD_ART_FIELD)
	tooltip_text = "%s\n%s" % [display_name, str(definition.get("description", ""))]
	disabled = not is_interactable
	add_theme_color_override("font_color", Color("553e31"))
	add_theme_color_override("font_disabled_color", Color("806f62"))
	add_theme_color_override("font_hover_color", Color("38271f"))
	if str(card.get("suit", "")) == "heart" or str(card.get("suit", "")) == "diamond":
		add_theme_color_override("font_color", Color("a63631"))
		add_theme_color_override("font_hover_color", Color("7c211f"))
	_refresh_card_content()
	_refresh_visual_state()


## 切换选中视觉；桌面在选择变化后调用，组件不自行维护业务选择集合。
func set_selected_state(selected: bool) -> void:
	is_card_selected = selected
	_refresh_visual_state()


## 提供 Godot 原生拖放数据；拖拽预览不会改变真实卡牌节点或权威状态。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_interactable or card_uid < 0:
		return null
	card_drag_started.emit(card_uid)
	# 拖拽预览；使用轻量标签而非复制交互节点，避免预览参与输入。
	var preview: Label = Label.new()
	preview.custom_minimum_size = Vector2(card_width, card_height)
	preview.text = "%s\n\n%s\n\n%s" % [_suit_rank_text, _display_name_text, _card_type_text]
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_theme_font_size_override("font_size", 15)
	preview.add_theme_color_override("font_color", Color("553e31"))
	preview.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(Color("f4ead5f2"), BattleUIStyle.ACCENT_COLOR, 3, 10))
	set_drag_preview(preview)
	return {"drag_type":"battle_card", "card_uid":card_uid}


## 根据选中、可交互与默认状态刷新牌面；所有状态共享同一尺寸以保持手牌稳定排列。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 默认纸张颜色；木牛“粮”使用更偏青的纸色作为来源提示。
	var paper_color: Color = Color("e8dcc3") if not is_wooden_ox_card else Color("d8e4d4")
	# 默认边框颜色；选中时改为高亮金色并增加描边宽度。
	var border_color: Color = BattleUIStyle.ACCENT_COLOR if is_card_selected else _category_color
	# 选中描边宽度；3像素在高分辨率下仍清晰，普通状态保持1像素。
	var border_width: int = 3 if is_card_selected else 1
	add_theme_stylebox_override("normal", BattleUIStyle.make_inset_panel(paper_color, border_color, border_width, 6))
	add_theme_stylebox_override("hover", BattleUIStyle.make_inset_panel(paper_color.lightened(0.08), BattleUIStyle.ACCENT_COLOR, 2, 6))
	add_theme_stylebox_override("pressed", BattleUIStyle.make_inset_panel(paper_color.darkened(0.05), BattleUIStyle.ACCENT_COLOR, 3, 6))
	add_theme_stylebox_override("disabled", BattleUIStyle.make_inset_panel(paper_color.darkened(0.12), Color("655b50"), 1, 6))
	position.y = _base_position_y - selected_lift if is_card_selected else _base_position_y
	if _accent_bar != null:
		_accent_bar.color = _category_color


## 创建牌面内部节点；所有子节点忽略鼠标，点击与拖拽始终由卡牌按钮本身处理。
func _create_card_content() -> void:
	_accent_bar = ColorRect.new()
	_accent_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_accent_bar.offset_bottom = 4.0
	_accent_bar.color = _category_color
	_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_accent_bar)
	_artwork_rect = TextureRect.new()
	_artwork_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_artwork_rect.offset_left = 9.0
	_artwork_rect.offset_top = 30.0
	_artwork_rect.offset_right = -9.0
	_artwork_rect.offset_bottom = -43.0
	_artwork_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_artwork_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_artwork_rect)
	_artwork_placeholder = Label.new()
	_artwork_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_artwork_placeholder.offset_left = 9.0
	_artwork_placeholder.offset_top = 30.0
	_artwork_placeholder.offset_right = -9.0
	_artwork_placeholder.offset_bottom = -43.0
	_artwork_placeholder.text = "◇\n插画预留"
	_artwork_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artwork_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_artwork_placeholder.add_theme_font_size_override("font_size", 12)
	_artwork_placeholder.add_theme_color_override("font_color", Color("8b7964"))
	_artwork_placeholder.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(Color("b9aa8b55"), Color("9b8665"), 1, 5))
	_artwork_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_artwork_placeholder)
	_corner_label = Label.new()
	_corner_label.position = Vector2(10.0, 7.0)
	_corner_label.size = Vector2(card_width - 20.0, 22.0)
	_corner_label.add_theme_font_size_override("font_size", 16)
	_corner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_corner_label)
	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_name_label.offset_left = 6.0
	_name_label.offset_top = -41.0
	_name_label.offset_right = -6.0
	_name_label.offset_bottom = -20.0
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	_type_label = Label.new()
	_type_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_type_label.offset_left = 6.0
	_type_label.offset_top = -21.0
	_type_label.offset_right = -6.0
	_type_label.offset_bottom = -4.0
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.add_theme_font_size_override("font_size", 11)
	_type_label.add_theme_color_override("font_color", Color("796653"))
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_type_label)


## 把缓存的牌面文本与插画写入子节点；可在 configure 早于 _ready 时安全重复调用。
func _refresh_card_content() -> void:
	if not is_node_ready() or _artwork_rect == null:
		return
	_artwork_rect.texture = _artwork_texture
	_artwork_rect.visible = _artwork_texture != null
	_artwork_placeholder.visible = _artwork_texture == null
	_corner_label.text = _suit_rank_text
	_name_label.text = _display_name_text
	_type_label.text = _card_type_text
	# 红色花色沿用卡牌按钮的红色语义，黑色花色使用深褐色。
	var content_color: Color = get_theme_color("font_color")
	_corner_label.add_theme_color_override("font_color", content_color)
	_name_label.add_theme_color_override("font_color", content_color)


## 鼠标进入可交互卡牌时播放轻量放大动画，并提高绘制层级避免被相邻手牌遮挡。
func _on_mouse_entered() -> void:
	if not is_interactable:
		return
	z_index = 20
	_start_hover_tween(Vector2.ONE * hover_scale)


## 鼠标离开卡牌时恢复原始缩放和绘制层级，选中抬升状态保持不变。
func _on_mouse_exited() -> void:
	z_index = 0
	_start_hover_tween(Vector2.ONE)


## 启动悬停缩放动画；使用并行动画保证横纵缩放同步完成。
func _start_hover_tween(target_scale: Vector2) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_QUAD)
	_hover_tween.set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target_scale, hover_animation_seconds)


## 根据卡牌类型与伤害属性返回牌面强调色；配置缺失时回退到统一木褐色。
func _resolve_category_color(definition: Dictionary) -> Color:
	# 卡牌伤害属性；火焰与雷电优先覆盖普通类型配色。
	var nature: String = str(definition.get("nature", "normal"))
	if nature == "fire":
		return Color("c65f3f")
	if nature == "thunder":
		return Color("547fc4")
	# 卡牌类型；基本牌使用朱红、锦囊牌使用靛青、装备牌使用青铜色。
	var card_type: String = str(definition.get("type", ""))
	return {"basic":Color("a44e43"), "trick":Color("4f718f"), "equipment":Color("8a7548")}.get(card_type, Color("765b3d"))


## 将花色 ID 转换为牌面符号。
func _suit_symbol(suit: String) -> String:
	return {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}.get(suit, "?")


## 将点数转换为牌面字符。
func _rank_text(rank: int) -> String:
	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))


## 将配置类别转换为简短中文标签，帮助玩家在小牌面上快速识别用途。
func _type_text(card_type: String) -> String:
	return {"basic":"基本牌", "trick":"锦囊牌", "equipment":"装备牌"}.get(card_type, "卡牌")
