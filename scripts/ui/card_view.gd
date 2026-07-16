class_name CardView
extends Node2D

## 可复用的实体卡牌视图。根节点只代表一张卡牌，输入由独立透明组件处理，因此同一节点可在手牌、拖拽和弃牌动画之间移动。

## 卡牌被点击时发出的信号；桌面据此更新临时选择，不直接提交对局动作。
signal pressed

## 拖拽开始信号；参数为稳定卡牌 UID，桌面可据此同步当前选择。
signal card_drag_started(card_uid: int)

## 卡牌宽度；默认108像素适合1280×720牌桌，运行时无需动态修改。
## 标准牌面使用111×148像素，对应精确3:4宽高比；宽度只增大不缩小高度，运行时通常无需动态修改。
@export_range(88.0, 180.0, 1.0) var card_width: float = 111.0

## 卡牌高度；默认148像素保持实体牌比例，运行时无需动态修改。
@export_range(120.0, 240.0, 1.0) var card_height: float = 148.0

## 选中后向上抬升的像素数；默认14像素提供明确反馈，普通容器可在运行时调整。
@export_range(0.0, 36.0, 1.0) var selected_lift: float = 14.0

## 手牌选中与取消选中时的纵向位移动画时长；默认0.025秒提供即时但可感知的抬起反馈，运行时通常无需动态修改。
@export_range(0.0, 0.2, 0.005) var selection_animation_seconds: float = 0.025

## 鼠标悬停时的缩放倍率；默认1.06提供轻量实体牌靠近反馈，运行时可动态调整。
@export_range(1.0, 1.2, 0.01) var hover_scale: float = 1.06

## 悬停缩放动画时长；默认0.12秒保证反馈迅速且不过度跳动，运行时可调整。
@export_range(0.05, 0.4, 0.01) var hover_animation_seconds: float = 0.12

## 禁用牌面纸张的压暗比例；默认0.38形成明确深灰反馈，仅影响表现，可在运行时按主题调整。
@export_range(0.0, 0.8, 0.01) var disabled_darkening: float = 0.38

## 禁用牌面内容的灰度调制色；默认保留45%亮度，使插画与文字明显弱于可选卡牌，仅影响表现。
@export var disabled_content_modulate: Color = Color(0.45, 0.45, 0.45, 1.0)

## 当前实体牌 UID；由 configure 写入，未配置时为 -1。
var card_uid: int = -1

## 当前牌是否来自木牛流马“粮”；用于显示独立来源标记。
var is_wooden_ox_card: bool = false

## 当前牌是否被桌面选中；只影响视觉状态，不代表规则合法。
var is_card_selected: bool = false

## 当前牌是否可在本地出牌阶段交互；禁用时仍展示完整牌面信息。
var is_interactable: bool = false

## 当前是否显示统一牌背；隐藏手牌候选和牌堆摸牌动画使用该状态，不携带任何牌面信息。
var is_face_down: bool = false

## 正式手牌节点的运行时入场偏移；默认零向量，获得牌动画从右侧偏移补间归零，布局刷新时会保留当前值。
var hand_entry_offset: Vector2 = Vector2.ZERO:
	set(value):
		position += value - hand_entry_offset
		hand_entry_offset = value

## 正式手牌的选中动画偏移；负值表示向上移动，属性写入时只应用差值以兼容容器持续重排。
var hand_selection_offset: Vector2 = Vector2.ZERO:
	set(value):
		position += value - hand_selection_offset
		hand_selection_offset = value

## 卡牌未选中时的原始布局纵坐标；非手牌容器使用它恢复选择抬升。
var _base_position_y: float = 0.0

## 当前卡牌插画纹理；配置缺失或文件无效时为 null，并显示占位区。
var _artwork_texture: Texture2D

## 待显示的花色点数字符串；默认与场景编辑器的黑桃7预览一致，configure 会在运行时覆盖。
var _suit_rank_text: String = "♠7"

## 待显示的卡牌名称；默认使用场景编辑器示例名称，绑定实体牌后按全局名称模式覆盖。
var _display_name_text: String = "星穹斩"

## 待显示的类别文本；默认与场景编辑器基本牌预览一致，运行时可附加木牛“粮”来源标记。
var _card_type_text: String = "基本牌"

## 当前卡牌类别强调色；默认使用基本牌朱红色，具体实体牌会按类别或伤害属性覆盖。
var _category_color: Color = Color("a44e43")

## 当前是否处于鼠标悬停状态；只用于决定纸张亮度和缩放表现。
var _is_hovered: bool = false

## 禁用输入时是否同时应用深灰视觉；默认开启，公共只读展示可关闭以保留完整牌面亮度。
## 该值只影响表现，不会让只读牌重新接收点击、悬停或拖拽输入。
var _dim_when_disabled: bool = true

## 当前悬停缩放动画；新动画开始前会停止旧动画以避免连续进入离开产生抖动。
var _hover_tween: Tween

## 当前选中位移动画；重复点击时会从当前偏移平滑转向新目标，避免并行动画争抢节点位置。
var _selection_tween: Tween

## 最近一次牌面配置签名；默认-1表示从未配置，相同快照、定义、交互状态和名称模式不会重复加载插画或重建样式。
var _configuration_signature: int = -1

## 卡牌纸张面板；承载完整视觉样式，不承担鼠标按钮语义。
@onready var _card_body: Panel = $CardBody

## 牌背覆盖层；默认隐藏，显示时遮挡完整牌面内容但不拦截独立输入区域。
@onready var _card_back: Panel = get_node("牌背") as Panel

## 牌面插画显示节点；固定占据卡牌中部，不参与鼠标输入。
@onready var _artwork_rect: TextureRect = $CardBody/Artwork

## 插画缺失占位标签；后期配置有效 art_path 后自动隐藏。
@onready var _artwork_placeholder: Label = $CardBody/ArtworkPlaceholder

## 左上角花色点数标签；独立于插画区域，保证任何图片亮度下都清晰可读。
@onready var _corner_label: Label = $CardBody/Corner

## 卡牌名称标签；固定显示在插画下方，统一使用全局名称模式。
@onready var _name_label: Label = $CardBody/Name

## 卡牌类别与木牛来源标签；固定显示在牌面底部。
@onready var _type_label: Label = $CardBody/Type

## 牌面顶部类别色条；只表达视觉分类，不参与卡牌规则判断。
@onready var _accent_bar: ColorRect = $CardBody/AccentBar

## 独立输入区域；负责点击、悬停和 Godot 原生拖拽协议。
@onready var _input_area: CardInputArea = $InputArea

## 悬停卡牌临时绘制层级；固定100确保重叠手牌中仍显示在最上方。
const HOVER_Z_INDEX: int = 100


## 初始化卡牌尺寸、视觉内容与独立输入信号。
func _ready() -> void:
	_card_body.size = get_card_size()
	_card_back.size = get_card_size()
	_input_area.size = get_card_size()
	_input_area.activated.connect(pressed.emit)
	_input_area.hover_started.connect(_on_mouse_entered)
	_input_area.hover_finished.connect(_on_mouse_exited)
	_input_area.drag_started.connect(card_drag_started.emit)
	_input_area.configure(card_uid, is_interactable, create_drag_preview)
	_refresh_card_content()
	_refresh_visual_state()


## 返回卡牌统一布局尺寸；容器和动画层通过该接口读取，不依赖 Control 根节点。
func get_card_size() -> Vector2:
	return Vector2(card_width, card_height)


## 返回牌面在全局画布中的矩形；目标线和飞牌动画通过该接口取得中心点。
func get_global_rect() -> Rect2:
	return Rect2(global_position, get_card_size() * global_scale)


## 返回当前手牌是否处于鼠标悬停状态；布局容器通过该只读接口保持放大牌底边对齐并设置顶层绘制顺序。
func is_hovered_in_hand() -> bool:
	return _is_hovered


## 写入牌面快照和定义；该方法不保存完整对局状态，可在每次快照重建时安全调用。
func configure(card: Dictionary, definition: Dictionary, wooden_ox_card: bool, interactable: bool, dim_when_disabled: bool = true) -> void:
	# 本次完整配置签名；包含全局名称模式，切换牌名后即使实体状态不变也会正确刷新。
	var next_configuration_signature: int = hash([card, definition, wooden_ox_card, interactable, dim_when_disabled, GameSettings.card_name_mode])
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	card_uid = int(card.get("uid", -1))
	is_wooden_ox_card = wooden_ox_card
	is_interactable = interactable
	_dim_when_disabled = dim_when_disabled
	is_face_down = false
	# 花色文本；红色花色使用单独字体色，黑色花色保持深褐色。
	var suit_text: String = _suit_symbol(str(card.get("suit", "")))
	# 点数文本；A、J、Q、K使用标准牌面字符。
	var rank_text: String = _rank_text(int(card.get("rank", 0)))
	# 卡牌显示名；统一通过全局名称模式解析，禁止组件自行维护双名称分支。
	var display_name: String = GameSettings.resolve_card_name(definition)
	# 卡牌类别文本；帮助玩家快速区分基本牌、锦囊牌与装备牌。
	var type_text: String = _type_text(str(definition.get("type", "")))
	_suit_rank_text = "%s%s" % [suit_text, rank_text]
	_display_name_text = display_name
	_card_type_text = "%s%s" % ["粮 · " if is_wooden_ox_card else "", type_text]
	_category_color = _resolve_category_color(definition)
	_artwork_texture = ArtworkLoader.load_from_definition(definition, ArtworkLoader.CARD_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = "%s\n%s" % [display_name, str(definition.get("description", ""))]
		_input_area.configure(card_uid, is_interactable, create_drag_preview)
	_refresh_card_content()
	_refresh_visual_state()


## 把当前视图配置为不可见手牌的统一牌背；只保留稳定 UID 供选择提交，不显示任何牌面信息。
func configure_back(entity_uid: int, interactable: bool) -> void:
	# 牌背配置签名；隐藏牌只依赖实体 UID 与交互状态，不读取或缓存任何牌面定义。
	var next_configuration_signature: int = hash(["card_back", entity_uid, interactable])
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	card_uid = entity_uid
	is_wooden_ox_card = false
	is_interactable = interactable
	_dim_when_disabled = true
	is_face_down = true
	if is_node_ready():
		_input_area.tooltip_text = "不可见手牌"
		_input_area.configure(card_uid, is_interactable, create_drag_preview)
	_refresh_visual_state()


## 切换选中视觉；桌面在选择变化后调用，组件不自行维护业务选择集合。
func set_selected_state(selected: bool) -> void:
	if is_card_selected == selected:
		return
	is_card_selected = selected
	_refresh_visual_state()
	# 重叠手牌容器负责统一计算纵向抬升和绘制层级。
	var hand_layout: DecadeHandContainer = get_parent() as DecadeHandContainer
	if hand_layout != null:
		hand_layout.refresh_card_states()
		_start_selection_tween(Vector2(0.0, -hand_layout.selected_lift if selected else 0.0))


## 启动手牌选中或取消选中的位移动画；非手牌展示区域继续沿用原有即时位置逻辑。
func _start_selection_tween(target_offset: Vector2) -> void:
	if _selection_tween != null and _selection_tween.is_valid():
		_selection_tween.kill()
	if selection_animation_seconds <= 0.0:
		hand_selection_offset = target_offset
		return
	_selection_tween = create_tween()
	_selection_tween.set_trans(Tween.TRANS_QUAD)
	_selection_tween.set_ease(Tween.EASE_OUT)
	_selection_tween.tween_property(self, "hand_selection_offset", target_offset, selection_animation_seconds)


## 创建完整牌面的只读拖拽预览；复制的是视觉树，不包含输入区域或业务选择状态。
func create_drag_preview() -> Control:
	# 预览容器；尺寸与原牌一致，并忽略全部鼠标输入。
	var preview: Control = Control.new()
	preview.custom_minimum_size = get_card_size()
	preview.size = get_card_size()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 牌面视觉副本；保持插画、文字、边框和实体牌比例不变。
	var body_preview: Panel = _card_body.duplicate() as Panel
	body_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(body_preview)
	# 牌背覆盖层副本；隐藏手牌拖拽时仍保持信息完全遮挡。
	var card_back_preview: Panel = _card_back.duplicate() as Panel
	card_back_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(card_back_preview)
	return preview


## 根据选中、悬停与默认状态刷新同一张牌的纸张样式。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 默认纸张颜色；木牛“粮”使用偏青纸色作为来源提示。
	var paper_color: Color = Color("e8dcc3") if not is_wooden_ox_card else Color("d8e4d4")
	if _is_hovered and is_interactable:
		paper_color = paper_color.lightened(0.08)
	# 默认边框颜色；选中时改为高亮金色并增加描边宽度。
	var border_color: Color = BattleUIStyle.ACCENT_COLOR if is_card_selected else _category_color
	# 选中描边宽度；3像素在高分辨率下仍清晰，普通状态保持1像素。
	var border_width: int = 3 if is_card_selected else (2 if _is_hovered and is_interactable else 1)
	# 内容调制色；禁用牌会统一压暗插画、占位图和文字，避免只有纸张边缘发生轻微变化。
	var content_modulate: Color = Color.WHITE
	if not is_interactable and _dim_when_disabled:
		paper_color = paper_color.darkened(disabled_darkening)
		border_color = Color("655b50")
		content_modulate = disabled_content_modulate
	_card_body.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(paper_color, border_color, border_width, 6))
	if not (get_parent() is DecadeHandContainer):
		position.y = _base_position_y - selected_lift if is_card_selected else _base_position_y
	_accent_bar.color = _category_color.darkened(disabled_darkening) if not is_interactable and _dim_when_disabled else _category_color
	_artwork_rect.modulate = content_modulate
	_artwork_placeholder.modulate = content_modulate
	_corner_label.modulate = content_modulate
	_name_label.modulate = content_modulate
	_type_label.modulate = content_modulate
	_card_back.visible = is_face_down


## 把缓存的牌面文本与插画写入子节点；可在 configure 早于 _ready 时安全重复调用。
func _refresh_card_content() -> void:
	if not is_node_ready():
		return
	_artwork_rect.texture = _artwork_texture
	_artwork_rect.visible = _artwork_texture != null
	_artwork_placeholder.visible = _artwork_texture == null
	_artwork_placeholder.text = "◇\n插画预留"
	_corner_label.text = _suit_rank_text
	_name_label.text = _display_name_text
	_type_label.text = _card_type_text
	# 红色花色使用朱红文字，其他花色使用深褐文字。
	var content_color: Color = Color("a63631") if _suit_rank_text.begins_with("♥") or _suit_rank_text.begins_with("♦") else Color("553e31")
	_corner_label.add_theme_color_override("font_color", content_color)
	_name_label.add_theme_color_override("font_color", content_color)


## 鼠标进入可交互卡牌时播放轻量放大动画，并提高绘制层级。
func _on_mouse_entered() -> void:
	if not is_interactable:
		return
	_is_hovered = true
	z_index = HOVER_Z_INDEX
	_refresh_visual_state()
	# 手牌容器需要同步悬停牌的位置补偿与绘制层级；其他展示容器只保留原有放大反馈。
	var hand_layout: DecadeHandContainer = get_parent() as DecadeHandContainer
	if hand_layout != null:
		hand_layout.refresh_card_states()
	_start_hover_tween(Vector2.ONE * hover_scale)


## 鼠标离开卡牌时恢复原始缩放和容器计算的绘制层级。
func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh_visual_state()
	# 无名杀式手牌恢复由容器计算的顺序；其他父级回到默认层级。
	var hand_layout: DecadeHandContainer = get_parent() as DecadeHandContainer
	if hand_layout != null:
		hand_layout.refresh_card_states()
	else:
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


## 将配置类别转换为简短中文标签，帮助玩家快速识别用途。
func _type_text(card_type: String) -> String:
	return {"basic":"基本牌", "trick":"锦囊牌", "equipment":"装备牌"}.get(card_type, "卡牌")
