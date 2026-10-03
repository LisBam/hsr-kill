class_name CardView
extends Node2D

## 可复用的实体卡牌视图。根节点只代表一张卡牌，输入由独立透明组件处理，因此同一节点可在手牌、拖拽和弃牌动画之间移动。

## 卡牌被点击时发出的信号；桌面据此更新临时选择，不直接提交对局动作。
signal pressed

## 本地手牌排序请求；参数由输入组件提供，桌面只调整客户端显示顺序，不提交目标选择或规则动作。
signal hand_reorder_requested(source_card_uid: int, target_card_uid: int, insert_after_target: bool)

## 本地手牌开始直接拖动的通知；桌面只移动当前实体牌节点，不创建任何预览牌或规则实体。
signal hand_drag_started(source_card_uid: int, pointer_global_position: Vector2)

## 本地手牌直接拖动中的坐标更新；桌面依据稳定UID复核所属分区后驱动原节点跟随。
signal hand_drag_moved(source_card_uid: int, pointer_global_position: Vector2)

## 本地手牌结束直接拖动的通知；桌面根据释放位置决定同分区内的最终排序。
signal hand_drag_finished(source_card_uid: int, pointer_global_position: Vector2)

## 鼠标进入可见牌面时发出的统一信息请求；内容字典和全局目标矩形由牌桌信息框组件直接消费。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开牌面或节点退出场景树时发出的统一信息关闭请求。
signal information_dismissed

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

## 视为名称横条的固定高度；默认22像素形成贴合牌面类别色的细条，不遮挡底部实体牌名，运行时可按牌面比例调整。
## 多标签布局补充：该高度表示单个标签行高，标签组总高度会按实际非空标签数量和固定间距计算。
@export_range(16.0, 36.0, 1.0) var view_as_banner_height: float = 22.0

## 视为名称横条的文字尺寸；默认16像素低于实体牌名层级，运行时可按主题可读性调整。
@export_range(10, 26, 1) var view_as_banner_font_size: int = 16

## 视为名称横条的类别色底板不透明度；默认0.90保证小号文字清晰且仍与原牌插画融合，运行时可调整。
## 当前白色纸张底板默认完全不透明；降低该值只用于特殊主题与插画的表现融合，不改变边框和文字的视为牌语义。
@export_range(0.0, 1.0, 0.01) var view_as_banner_opacity: float = 1.0

## 当前实体牌 UID；由 configure 写入，未配置时为 -1。
var card_uid: int = -1

## 当前牌是否来自木牛流马“粮”；用于显示独立来源标记。
var is_wooden_ox_card: bool = false

## 外部组件指定的拖动排序分区；空字符串沿用正式手牌规则，非空时允许通用排序面板复用同一拖动输入。
var external_reorder_zone: String = ""

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

## 是否启用旧版非手牌绝对纵坐标恢复；默认关闭，动画层与外部容器必须始终拥有牌面位置的唯一写入权。
var _uses_legacy_non_hand_selection_position: bool = false

## 当前卡牌插画纹理；配置缺失或文件无效时为 null，并显示占位区。
var _artwork_texture: Texture2D

## 待显示的花色点数字符串；默认与场景编辑器的黑桃7预览一致，configure 会在运行时覆盖。
## 该文本始终描述**实体牌面**：复制型视为生效时读取快照中的实体花色点数，逻辑牌面只出现在视为横条上。
var _suit_rank_text: String = "♠7"

## 待显示的卡牌名称；默认使用场景编辑器示例名称，绑定实体牌后按全局名称模式覆盖。
var _display_name_text: String = "杀"

## 待显示的视为牌文本；空字符串表示实体牌没有临时视为效果，横条保持隐藏。
## 复制型视为会在牌名前缀上逻辑花色与点数（例如“♥A 桃”），普通换名视为只显示逻辑牌名。
var _view_as_display_name_text: String = ""

## 当前实体手牌的通用标记标签数组；按order与稳定ID排序，离手快照通常为空。
var _hand_mark_tags: Array[Dictionary] = []

## 待显示的类别文本；默认与场景编辑器基本牌预览一致，运行时可附加木牛“粮”来源标记。
var _card_type_text: String = "基本牌"

## 当前卡牌类别强调色；默认使用基本牌朱红色，具体实体牌会按类别或伤害属性覆盖。
var _category_color: Color = Color("737b86")

## 当前实体牌静态定义副本；用于主题切换时重绘原牌插画、类别与名称，不包含实体区域或规则状态。
var _card_definition: Dictionary = {}

## 当前视为牌静态定义副本；只用于悬停说明展示实际可用牌效，不替换实体牌的视觉定义。
var _view_as_card_definition: Dictionary = {}

## 当前是否处于鼠标悬停状态；只用于决定纸张亮度和缩放表现。
var _is_hovered: bool = false

## 禁用输入时是否同时应用深灰视觉；默认开启，公共只读展示可关闭以保留完整牌面亮度。
## 该值只影响表现，不会让只读牌重新接收点击、悬停或拖拽输入。
var _dim_when_disabled: bool = true

## 是否隐藏花色与点数；默认隐藏关闭，牌名候选等“只有牌名没有实体牌”的展示场景会开启。
## 开启时只隐藏左上角花色点数控件与说明副标题中的花色点数段，牌名、类别、插画与说明正文照常显示；
## _suit_rank_text 仍照常计算，因此红色花色配色等既有判断逻辑无需分支。
var _hide_suit_rank: bool = false

## 当前悬停缩放动画；新动画开始前会停止旧动画以避免连续进入离开产生抖动。
var _hover_tween: Tween

## 当前选中位移动画；重复点击时会从当前偏移平滑转向新目标，避免并行动画争抢节点位置。
var _selection_tween: Tween

## 当前实体手牌是否正被直接拖动；为true时手牌容器保留原节点的鼠标跟随位置，不回写常规布局坐标。
var _is_hand_dragging: bool = false

## 直接拖动开始时鼠标相对牌面左上角的全局偏移；保持原实体牌在拖动中不发生指针跳位。
var _hand_drag_pointer_offset: Vector2 = Vector2.ZERO

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

## 卡牌标签横条区域；视为牌名与通用手牌标记会在此并排居中，不阻断原有输入区域。
## 当前布局补充：为了让每个标签恢复与手牌等宽，运行时使用纵向标签组并让整组居中。
@onready var _view_as_banner: Control = $CardBody/ViewAsBanner

## 卡牌标签横向容器；动态标签之间保留固定间距，单标签和双标签都会整体居中。
## 当前容器补充：场景节点使用VBoxContainer，使每个等宽标签按纵向间距排列。
@onready var _card_tag_row: VBoxContainer = %TagRow

## 独立输入区域；负责点击、悬停和 Godot 原生拖拽协议。
@onready var _input_area: CardInputArea = $InputArea

## 悬停卡牌临时绘制层级；固定100确保重叠手牌中仍显示在最上方。
const HOVER_Z_INDEX: int = 100


## 初始化卡牌尺寸、视觉内容与独立输入信号。
func _ready() -> void:
	_card_body.size = get_card_size()
	_card_back.size = get_card_size()
	_input_area.size = get_card_size()
	_configure_view_as_banner_geometry()
	_input_area.activated.connect(pressed.emit)
	_input_area.hover_started.connect(_on_mouse_entered)
	_input_area.hover_finished.connect(_on_mouse_exited)
	_input_area.hand_reorder_requested.connect(hand_reorder_requested.emit)
	_input_area.hand_drag_started.connect(_on_hand_drag_started)
	_input_area.hand_drag_moved.connect(_on_hand_drag_moved)
	_input_area.hand_drag_finished.connect(_on_hand_drag_finished)
	_input_area.configure(card_uid, is_interactable, _get_hand_reorder_zone())
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
func configure(card: Dictionary, definition: Dictionary, wooden_ox_card: bool, interactable: bool, dim_when_disabled: bool = true, hide_suit_rank: bool = false) -> void:
	# 本次完整配置签名；包含全局名称模式，切换牌名后即使实体状态不变也会正确刷新。
	# hide_suit_rank 必须并入签名：同一个 CardView 实例在“实体牌面”与“仅牌名”之间复用时，
	# 签名不变会命中缓存而保留上一次的花色点数显示，这是不报错的隐蔽缺陷。
	var next_configuration_signature: int = hash([card, definition, wooden_ox_card, interactable, dim_when_disabled, hide_suit_rank, GameSettings.card_name_mode, GameSettings.ui_style_id])
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	card_uid = int(card.get("uid", -1))
	is_wooden_ox_card = wooden_ox_card
	is_interactable = interactable
	_dim_when_disabled = dim_when_disabled
	_hide_suit_rank = hide_suit_rank
	is_face_down = false
	# 当前实体牌的展示原始定义 ID；手牌视为状态与离手后的弃牌展示都通过该字段保留真实牌面。
	var original_definition_id: String = str(card.get("presentation_original_definition_id", card.get("original_definition_id", "")))
	# 当前实体牌的展示视为定义 ID；离手后实体定义已经恢复原牌，因此必须从独立展示字段读取本次逻辑牌名。
	var view_as_definition_id: String = str(card.get("view_as_definition_id", ""))
	# 当前实体牌的视觉定义；视为状态必须保留原牌插画、类别和底部名称，不把原实体牌改画成逻辑牌。
	var visual_definition: Dictionary = definition.duplicate(true)
	# 当前视为名称；空字符串表示普通实体牌无需额外覆盖层。
	_view_as_display_name_text = ""
	_view_as_card_definition.clear()
	# 当前通用手牌标签；复制后排序，禁止UI修改权威快照中的原始字典。
	_hand_mark_tags = []
	for tag_data_variant: Variant in (card.get("hand_mark_tags", {}) as Dictionary).values():
		# 当前标签数据；空标签或无显示文本的异常记录不会占用牌面空间。
		var tag_data: Dictionary = (tag_data_variant as Dictionary).duplicate(true)
		if not str(tag_data.get("label", "")).is_empty():
			_hand_mark_tags.append(tag_data)
	_hand_mark_tags.sort_custom(_sort_hand_mark_tags)
	if not original_definition_id.is_empty():
		# 原实体牌定义；快照异常或扩展缺失时安全回退到逻辑牌定义，避免空白牌面。
		var original_definition: Dictionary = GameDatabase.get_card(original_definition_id)
		if not original_definition.is_empty():
			visual_definition = original_definition
			# 视为逻辑定义；手牌中的旧快照缺失独立字段时回退当前 definition，兼容既有网络与回放数据。
			var view_as_definition: Dictionary = GameDatabase.get_card(view_as_definition_id) if not view_as_definition_id.is_empty() else definition
			_view_as_display_name_text = GameSettings.resolve_card_display_name(view_as_definition)
			_view_as_card_definition = view_as_definition.duplicate(true)
			# 视为逻辑花色；只有“连同花色点数一起视为”的复制型视为才非空，普通换名视为保持空值。
			var view_as_suit: String = str(card.get("view_as_suit", ""))
			if not view_as_suit.is_empty():
				# 横条文本；按“花色＋点数＋视为牌名”输出，让玩家一眼看出该牌当前被当作哪张实体牌使用。
				_view_as_display_name_text = "%s%s %s" % [_suit_symbol(view_as_suit), _rank_text(int(card.get("view_as_rank", 0))), _view_as_display_name_text]
	_card_definition = visual_definition
	if _view_as_card_definition.is_empty():
		_view_as_card_definition = definition.duplicate(true)
	# 实体牌面花色；复制型视为生效时角标必须保持实体原值，为空表示当前没有牌面复制。
	var presentation_suit: String = str(card.get("presentation_original_suit", ""))
	# 实体牌面点数；与实体牌面花色成对出现，牌面复制缺失时回退当前快照点数。
	var presentation_rank: int = int(card.get("presentation_original_rank", 0))
	# 花色文本；红色花色使用单独字体色，黑色花色保持深褐色。
	var suit_text: String = _suit_symbol(presentation_suit if not presentation_suit.is_empty() else str(card.get("suit", "")))
	# 点数文本；A、J、Q、K使用标准牌面字符。
	var rank_text: String = _rank_text(presentation_rank if not presentation_suit.is_empty() else int(card.get("rank", 0)))
	# 卡牌显示名；统一通过全局名称模式解析，禁止组件自行维护双名称分支。
	var display_name: String = GameSettings.resolve_card_display_name(visual_definition)
	# 卡牌类别文本；装备牌继续按槽位子类型细分为武器、防具、坐骑和宝物。
	# 专属锦囊牌额外带上「专属」前缀：它不属于任何牌堆，牌面必须能直接看出这一点。
	var type_text: String = _type_text(str(visual_definition.get("type", "")), str(visual_definition.get("subtype", "")), bool(visual_definition.get("exclusive", false)))
	_suit_rank_text = "%s%s" % [suit_text, rank_text]
	_display_name_text = display_name
	_card_type_text = "%s%s" % ["粮 · " if is_wooden_ox_card else "", type_text]
	_category_color = _resolve_category_color(visual_definition)
	_artwork_texture = ArtworkLoader.load_from_definition(visual_definition, ArtworkLoader.CARD_ART_FIELD)
	if is_node_ready():
		_input_area.tooltip_text = ""
		_input_area.configure(card_uid, is_interactable, _get_hand_reorder_zone())
	_refresh_card_content()
	_refresh_visual_state()


## 把当前视图配置为不可见手牌的统一牌背；只保留稳定 UID 供选择提交，不显示任何牌面信息。
func configure_back(entity_uid: int, interactable: bool) -> void:
	# 牌背配置签名；隐藏牌只依赖实体 UID 与交互状态，不读取或缓存任何牌面定义。
	var next_configuration_signature: int = hash(["card_back", entity_uid, interactable, GameSettings.ui_style_id])
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	card_uid = entity_uid
	is_wooden_ox_card = false
	is_interactable = interactable
	_dim_when_disabled = true
	is_face_down = true
	_card_definition.clear()
	_view_as_card_definition.clear()
	_view_as_display_name_text = ""
	_hand_mark_tags.clear()
	if is_node_ready():
		_input_area.tooltip_text = ""
		_input_area.configure(card_uid, is_interactable, _get_hand_reorder_zone())
	_refresh_visual_state()


## 按当前活动 UI 风格重绘卡牌纸张、类别条与状态边框；实体 UID、选中状态和输入权限保持不变。
func refresh_ui_style() -> void:
	if not _card_definition.is_empty():
		_category_color = _resolve_category_color(_card_definition)
	_refresh_card_content()
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


## 动态切换牌面的本地交互权限；条件组合选牌可在不重建节点的情况下压暗并禁用不兼容候选。
func set_interactable_state(interactable: bool) -> void:
	if is_interactable == interactable:
		return
	is_interactable = interactable
	if is_node_ready():
		_input_area.configure(card_uid, is_interactable, _get_hand_reorder_zone())
	_refresh_visual_state()


## 配置非手牌组件的拖动排序分区；只改变输入信号，不修改实体牌区域或本地选择状态。
func set_external_reorder_zone(reorder_zone: String) -> void:
	external_reorder_zone = reorder_zone
	if is_node_ready():
		_input_area.configure(card_uid, is_interactable, _get_hand_reorder_zone())


## 返回当前正式手牌所属的可排序分区；木牛“粮”与普通手牌严格分离，其他区域卡牌不参与任何拖拽排序。
func _get_hand_reorder_zone() -> String:
	if not external_reorder_zone.is_empty():
		return external_reorder_zone
	if not (get_parent() is DecadeHandContainer):
		return ""
	return "wooden_ox" if is_wooden_ox_card else "hand"


## 返回当前原实体手牌是否正在直接拖动；手牌容器据此保留其鼠标跟随位置并继续布局其他卡牌。
func is_hand_dragging() -> bool:
	return _is_hand_dragging


## 开始直接移动当前实体手牌；只记录鼠标相对偏移并提升绘制层级，不复制牌面或变更权威实体。
func begin_hand_drag(pointer_global_position: Vector2) -> void:
	if _get_hand_reorder_zone().is_empty():
		return
	_is_hand_dragging = true
	_hand_drag_pointer_offset = pointer_global_position - global_position
	z_index = HOVER_Z_INDEX + 1


## 让当前实体手牌按鼠标位置直接跟随；全局坐标写入会自动适配手牌容器、滚动视口与画布变换。
func move_hand_drag(pointer_global_position: Vector2) -> void:
	if not _is_hand_dragging:
		return
	global_position = pointer_global_position - _hand_drag_pointer_offset


## 结束当前实体手牌直接拖动；桌面随后会重排同分区视图，故本方法不自行推断最终插入位置。
func end_hand_drag() -> void:
	if not _is_hand_dragging:
		return
	_is_hand_dragging = false
	_hand_drag_pointer_offset = Vector2.ZERO
	var hand_layout: DecadeHandContainer = get_parent() as DecadeHandContainer
	if hand_layout != null:
		hand_layout.refresh_card_states()


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


## 根据选中、悬停与默认状态刷新同一张牌的纸张样式。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 默认纸张颜色；木牛“粮”使用偏青纸色作为来源提示。
	var paper_color: Color = BattleUIStyle.get_color("card_paper") if not is_wooden_ox_card else BattleUIStyle.get_color("card_wooden_ox_paper")
	if _is_hovered and is_interactable:
		paper_color = paper_color.lightened(0.08)
	# 默认边框颜色；选中时改为高亮金色并增加描边宽度。
	var border_color: Color = BattleUIStyle.get_color("accent") if is_card_selected else _category_color
	# 选中描边宽度；3像素在高分辨率下仍清晰，普通状态保持1像素。
	var border_width: int = 3 if is_card_selected else (2 if _is_hovered and is_interactable else 1)
	# 内容调制色；禁用牌会统一压暗插画、占位图和文字，避免只有纸张边缘发生轻微变化。
	var content_modulate: Color = Color.WHITE
	if not is_interactable and _dim_when_disabled:
		paper_color = paper_color.darkened(disabled_darkening)
		border_color = BattleUIStyle.get_color("card_disabled_border")
		content_modulate = disabled_content_modulate
	_card_body.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(paper_color, border_color, border_width, 6))
	# 动画牌、选择窗口牌和其他外部布局牌不能在悬停结束或样式刷新时把纵坐标重置为0；旧行为仅保留显式兼容开关。
	if _uses_legacy_non_hand_selection_position and not (get_parent() is DecadeHandContainer):
		position.y = _base_position_y - selected_lift if is_card_selected else _base_position_y
	_accent_bar.color = _category_color.darkened(disabled_darkening) if not is_interactable and _dim_when_disabled else _category_color
	_artwork_rect.modulate = content_modulate
	_artwork_placeholder.modulate = content_modulate
	_corner_label.modulate = content_modulate
	_name_label.modulate = content_modulate
	_type_label.modulate = content_modulate
	_view_as_banner.modulate = content_modulate
	_refresh_view_as_banner_style()
	_refresh_card_back_style()
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
	_corner_label.visible = not _hide_suit_rank
	_name_label.text = _display_name_text
	_type_label.text = _card_type_text
	_configure_view_as_banner_geometry()
	_view_as_banner.visible = not is_face_down and (not _view_as_display_name_text.is_empty() or not _hand_mark_tags.is_empty())
	_rebuild_card_tag_banners()
	# 红色花色使用朱红文字，其他花色使用深褐文字。
	var content_color: Color = BattleUIStyle.get_color("card_red_suit") if _suit_rank_text.begins_with("♥") or _suit_rank_text.begins_with("♦") else BattleUIStyle.get_color("card_text")
	_corner_label.add_theme_color_override("font_color", content_color)
	_name_label.add_theme_color_override("font_color", content_color)
	_type_label.add_theme_color_override("font_color", BattleUIStyle.get_color("card_text"))
	_artwork_placeholder.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))


## 按当前牌面尺寸把卡牌标签行固定在插画中央；多个标签保留间距并作为整体居中。
## 等宽布局补充：每个标签铺满手牌宽度，多个标签纵向留缝后再按整个标签组居中。
func _configure_view_as_banner_geometry() -> void:
	if not is_node_ready():
		return
	# 当前可见标签数量；视为牌名固定在首行，每个非空手牌标记占用独立一行。
	var tag_count: int = 1 if not _view_as_display_name_text.is_empty() else 0
	# 当前待统计的手牌标记；空标签不创建可见行，因此不计入标签组高度。
	for tag_data: Dictionary in _hand_mark_tags:
		if not str(tag_data.get("label", "")).is_empty():
			tag_count += 1
	# 标签行间距；复用场景容器配置，保证场景编辑器与运行时脚本修改保持一致。
	var tag_separation: float = float(_card_tag_row.get_theme_constant("separation"))
	# 标签组高度；没有标签时保留单行高度供后续配置复用，多个标签按行高与间距精确累计。
	var banner_height: float = view_as_banner_height if tag_count <= 1 else view_as_banner_height * float(tag_count) + tag_separation * float(tag_count - 1)
	# 标签组尺寸；每一行宽度始终等于手牌宽度，避免视为与标记标签退化为文字宽度。
	_view_as_banner.size = Vector2(card_width, banner_height)
	# 标签组纵坐标；以整组高度为基准在牌面中央对称摆放。
	_view_as_banner.position = Vector2(0.0, (card_height - banner_height) * 0.5)


## 重建视为名称与通用手牌标记标签；两类标签使用同一视觉组件，并由HBox统一保留间距和整体居中。
## 当前容器补充：等宽标签改由VBoxContainer处理纵向间距，显示顺序仍然保持视为标签在前。
func _refresh_view_as_banner_style() -> void:
	if not is_node_ready():
		return
	_rebuild_card_tag_banners()


## 清空并按当前缓存创建全部牌面标签；视为标签固定在前，通用标记按数据排序随后排列。
func _rebuild_card_tag_banners() -> void:
	if not is_node_ready():
		return
	for child: Node in _card_tag_row.get_children():
		_card_tag_row.remove_child(child)
		child.queue_free()
	if is_face_down:
		return
	if not _view_as_display_name_text.is_empty():
		_card_tag_row.add_child(_create_card_tag_banner(_view_as_display_name_text, _resolve_category_color(_view_as_card_definition)))
	for tag_data: Dictionary in _hand_mark_tags:
		# 当前手牌标记文本；鸣弦数据已经包含完整“【鸣弦】”格式，UI不重复包裹符号。
		var label_text: String = str(tag_data.get("label", ""))
		if not label_text.is_empty():
			_card_tag_row.add_child(_create_card_tag_banner(label_text, _category_color))


## 创建一个与视为标签同款的紧凑牌面标签；文字宽度决定自身宽度，父HBox负责双标签整体居中。
## 等宽布局补充：当前每个标签的最小宽度固定为手牌宽度，父VBox负责多标签整体居中。
func _create_card_tag_banner(label_text: String, border_color: Color) -> PanelContainer:
	# 标签底板；白色牌纸和类别色边框与现有视为标签保持一致。
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(card_width, view_as_banner_height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 标签底色；透明度由检查器参数控制，不改变文字和边框可读性。
	var background_color: Color = BattleUIStyle.get_color("card_paper")
	background_color.a = view_as_banner_opacity
	# 标签边框色；视为牌使用逻辑牌类别色，普通标记使用原实体牌类别色。
	var resolved_border_color: Color = border_color
	resolved_border_color.a = 0.96
	# 标签样式；水平内边距为3像素，让并排标签在111像素牌宽内仍能完整显示。
	# 等宽样式补充：相同内边距继续用于整张手牌宽度内的文字和边框留白。
	var panel_style: StyleBoxFlat = BattleUIStyle.make_inset_panel(background_color, resolved_border_color, 1, 2)
	panel_style.content_margin_left = 3.0
	panel_style.content_margin_right = 3.0
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	panel_style.shadow_size = 3
	panel_style.shadow_offset = Vector2(0.0, 1.0)
	panel.add_theme_stylebox_override("panel", panel_style)
	# 标签文字；红色花色沿用牌名红色，黑色花色沿用牌名深色。
	var label: Label = Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", view_as_banner_font_size)
	label.add_theme_color_override("font_color", BattleUIStyle.get_color("card_red_suit") if _suit_rank_text.begins_with("♥") or _suit_rank_text.begins_with("♦") else BattleUIStyle.get_color("card_text"))
	panel.add_child(label)
	return panel


## 比较两个通用手牌标签的稳定显示顺序；order相同则按ID排序，保证网络客户端布局一致。
func _sort_hand_mark_tags(first: Dictionary, second: Dictionary) -> bool:
	# 第一项排序值；缺失时使用0，允许普通标签自然排在高优先级技能标签之前。
	var first_order: int = int(first.get("order", 0))
	# 第二项排序值；与第一项相同类型，避免字符串数字产生字典序差异。
	var second_order: int = int(second.get("order", 0))
	if first_order != second_order:
		return first_order < second_order
	return str(first.get("id", "")) < str(second.get("id", ""))


## 将输入组件的开始拖动通知向桌面转发；实际位置与排序决策始终由持有全部手牌视图的桌面协调器负责。
func _on_hand_drag_started(source_card_uid: int, pointer_global_position: Vector2) -> void:
	hand_drag_started.emit(source_card_uid, pointer_global_position)


## 将输入组件的拖动坐标通知向桌面转发；不在卡牌组件内查询目标卡或修改显示顺序。
func _on_hand_drag_moved(source_card_uid: int, pointer_global_position: Vector2) -> void:
	hand_drag_moved.emit(source_card_uid, pointer_global_position)


## 将输入组件的结束拖动通知向桌面转发；桌面会恢复原实体牌到规范化后的分区布局。
func _on_hand_drag_finished(source_card_uid: int, pointer_global_position: Vector2) -> void:
	hand_drag_finished.emit(source_card_uid, pointer_global_position)


## 刷新统一牌背配色与选中描边；正面牌与牌背共用同一主题入口，隐藏信息状态不会暴露实体内容。
## 选中时牌背外框使用与 CardBody 相同的主题 accent 色和 3 像素宽度，使【寒冰剑】【过河拆桥】等隐藏手牌候选与五谷丰登正面选中反馈一致。
func _refresh_card_back_style() -> void:
	if not is_node_ready() or _card_back == null:
		return
	# 牌背底板色；禁用且需要压暗时与正面纸张一致降低亮度，仅影响客户端表现。
	var card_back_background: Color = BattleUIStyle.get_color("card_back_background")
	# 牌背外框色；默认使用主题统一边框，选中时切换为与正面相同的强调金色。
	var card_back_border_color: Color = BattleUIStyle.get_color("border")
	# 牌背外框宽度；默认 2 像素保持清晰外框，选中时升为 3 像素对齐正面选中描边。
	var card_back_border_width: int = 2
	if is_card_selected:
		card_back_border_color = BattleUIStyle.get_color("accent")
		card_back_border_width = 3
	elif _is_hovered and is_interactable:
		# 可点击牌背悬停反馈；略提亮边框即可，不改变默认宽度以免与选中态混淆。
		card_back_border_color = BattleUIStyle.get_color("border").lightened(0.12)
	if not is_interactable and _dim_when_disabled:
		card_back_background = card_back_background.darkened(disabled_darkening)
		card_back_border_color = BattleUIStyle.get_color("card_disabled_border")
	# 牌背外框样式；选中强调色只作用于外层 Panel，中心同心结构保持默认层次。
	var card_back_style: StyleBoxFlat = BattleUIStyle.make_inset_panel(card_back_background, card_back_border_color, card_back_border_width, 6)
	_card_back.add_theme_stylebox_override("panel", card_back_style)
	# 牌背中心面板；使用较亮一层背景形成可辨识的同心结构。
	var card_back_center: Panel = _card_back.get_node("Center") as Panel
	card_back_center.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("card_back_center"), BattleUIStyle.get_color("border"), 1, 5))
	# 牌背标题；主副标题只承担视觉识别，不包含任何实体牌信息。
	var card_back_title: Label = _card_back.get_node("Title") as Label
	card_back_title.add_theme_color_override("font_color", BattleUIStyle.get_color("card_back_title"))
	# 牌背副标题；降低对比度避免与主标题争夺视觉层级。
	var card_back_subtitle: Label = _card_back.get_node("Subtitle") as Label
	card_back_subtitle.add_theme_color_override("font_color", BattleUIStyle.get_color("card_back_subtitle"))


## 鼠标进入可交互卡牌时播放轻量放大动画，并提高绘制层级。
## 可见卡牌会先请求统一信息框；不可交互状态只跳过原有放大反馈，不阻止查看说明。
func _on_mouse_entered() -> void:
	if not is_face_down and not _card_definition.is_empty():
		# 卡牌信息副标题；花色点数、木牛来源和细分类别保持与当前牌面显示一致。
		# 仅牌名展示时牌面没有花色点数，因此说明里也不出现花色点数占位字符。
		var subtitle_prefix: String = _card_type_text if _hide_suit_rank else "%s｜%s" % [_suit_rank_text, _card_type_text]
		var information_subtitle: String = subtitle_prefix
		# 视为状态提示；原牌名保留在标题，额外标明当前实际按哪张逻辑牌结算。
		if not _view_as_display_name_text.is_empty():
			information_subtitle += "｜视为【%s】" % _view_as_display_name_text
		for tag_data: Dictionary in _hand_mark_tags:
			# 通用手牌标记提示；直接追加标签原文，方便玩家在放大说明中确认鸣弦状态。
			var hand_mark_label: String = str(tag_data.get("label", ""))
			if not hand_mark_label.is_empty():
				information_subtitle += "｜标记%s" % hand_mark_label
		# 说明使用的逻辑定义；视为效果需要让玩家查看当前可实际使用或响应的牌效。
		var information_definition: Dictionary = _view_as_card_definition if not _view_as_card_definition.is_empty() else _card_definition
		# 统一卡牌信息；标题和说明直接来自当前名称模式与静态定义，不读取权威对局对象。
		var information: Dictionary = {
			"title":"【%s】" % _display_name_text,
			"subtitle":information_subtitle,
			"description":str(information_definition.get("description", "暂无卡牌说明。")),
		}
		information_requested.emit(information, get_global_rect())
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
	information_dismissed.emit()
	_is_hovered = false
	_refresh_visual_state()
	# 无名杀式手牌恢复由容器计算的顺序；其他父级回到默认层级。
	var hand_layout: DecadeHandContainer = get_parent() as DecadeHandContainer
	if hand_layout != null:
		hand_layout.refresh_card_states()
	else:
		z_index = 0
	_start_hover_tween(Vector2.ONE)


## 节点被手牌对账或动画层释放时关闭其信息框，避免鼠标离开信号缺失后残留旧内容。
func _exit_tree() -> void:
	information_dismissed.emit()


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
		return BattleUIStyle.get_color("card_fire")
	if nature == "thunder":
		return BattleUIStyle.get_color("card_thunder")
	# 卡牌类型；基本牌使用朱红、锦囊牌使用靛青、装备牌使用青铜色。
	var card_type: String = str(definition.get("type", ""))
	return {
		"basic":BattleUIStyle.get_color("card_basic"),
		"trick":BattleUIStyle.get_color("card_trick"),
		"equipment":BattleUIStyle.get_color("card_equipment"),
	}.get(card_type, BattleUIStyle.get_color("border"))


## 将花色 ID 转换为牌面符号。
func _suit_symbol(suit: String) -> String:
	return {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}.get(suit, "?")


## 将点数转换为牌面字符。
func _rank_text(rank: int) -> String:
	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))


## 将配置类别与装备子类型转换为中文标签；装备牌直接显示实际槽位类别，避免牌面底部重复显示笼统父类型。
## is_exclusive 为真时前置「专属」标识：专属牌正常情况不加入游戏，只有被技能或其他情况触发时才会加入。
func _type_text(card_type: String, card_subtype: String = "", is_exclusive: bool = false) -> String:
	# 专属前缀；非专属牌保持空字符串，因此既有牌面文本逐字不变。
	var exclusive_prefix: String = "专属 · " if is_exclusive else ""
	if card_type == "equipment":
		return "%s%s" % [exclusive_prefix, {
			"weapon":"武器牌",
			"armor":"防具牌",
			"offensive_mount":"进攻坐骑牌",
			"defensive_mount":"防御坐骑牌",
			"treasure":"宝物牌",
		}.get(card_subtype, "装备牌")]
	return "%s%s" % [exclusive_prefix, {"basic":"基本牌", "trick":"锦囊牌"}.get(card_type, "卡牌")]
