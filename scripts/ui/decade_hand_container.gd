class_name DecadeHandContainer
extends Container

## 无名杀式重叠手牌容器。组件只负责卡牌位置、层级和横向滚动宽度，不读取或修改对局状态。

## 单张手牌的标准尺寸；默认111×148像素，与 CardView 的3:4基准尺寸一致，运行时通常无需动态修改。
## 当前标准尺寸为111×148像素，通过增宽实现3:4比例，容器必须与 CardView 保持一致。
@export var card_size: Vector2 = Vector2(111.0, 148.0)

## 手牌区左右安全边距；默认6像素避免首尾卡牌描边被滚动容器裁切，运行时通常无需动态修改。
@export_range(0.0, 40.0, 1.0) var horizontal_padding: float = 6.0

## 手牌完全展开时相邻卡牌之间的空隙；默认2像素还原参考实现的紧凑实体牌排列，运行时通常无需动态修改。
@export_range(0.0, 20.0, 1.0) var preferred_card_gap: float = 2.0

## 手牌折叠后相邻卡牌至少露出的宽度；默认64像素保证花色点数和牌名仍可辨认，运行时可由主题调整。
@export_range(36.0, 111.0, 1.0) var minimum_visible_width: float = 64.0

## 选中卡牌向上抬升的距离；默认18像素接近无名杀选牌反馈，运行时可由主题调整。
@export_range(0.0, 48.0, 1.0) var selected_lift: float = 18.0

## 容器用于容纳卡牌、抬升和阴影的固定高度；默认172像素，运行时通常无需动态修改。
@export_range(148.0, 240.0, 1.0) var content_height: float = 172.0

## 连接父级尺寸变化并请求首次布局；父级通常是只启用横向滚动的 ScrollContainer。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# 父级可视宽度决定手牌是完整展开、互相覆盖还是进入横向滚动。
	var parent_control: Control = get_parent() as Control
	if parent_control != null:
		parent_control.resized.connect(queue_sort)
	queue_sort()


## 在 Godot 容器排序通知中重新计算全部卡牌位置。
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout_cards()


## 由卡牌组件在选中状态变化后调用，确保抬升距离和绘制层级立即同步。
func refresh_card_states() -> void:
	queue_sort()


## 按参考实现的 updateHand 算法排列手牌：空间足够时完整展开，不足时等距覆盖，达到最小露出宽度后允许横向滚动。
func _layout_cards() -> void:
	# 当前参与布局的可见卡牌；卡牌根节点统一为 Node2D，不依赖按钮或 Control 布局属性。
	var cards: Array[CardView] = []
	for child: Node in get_children():
		if child is CardView and (child as CardView).visible:
			cards.append(child as CardView)
	# 父级滚动视口的可见宽度；初始化阶段无有效尺寸时至少按一张牌宽处理。
	var parent_control: Control = get_parent() as Control
	# 当前可用于摆放手牌的宽度；扣除两侧安全边距后计算相邻牌步长。
	var available_width: float = maxf((parent_control.size.x if parent_control != null else size.x) - horizontal_padding * 2.0, card_size.x)
	if cards.is_empty():
		custom_minimum_size = Vector2(available_width + horizontal_padding * 2.0, content_height)
		return
	# 完全展开时相邻卡牌左上角之间的距离；等于牌宽加参考实现的2像素空隙。
	var expanded_step: float = card_size.x + preferred_card_gap
	# 当前布局步长；单张牌不需要计算分母，多张牌按可用宽度自动压缩。
	var card_step: float = expanded_step
	if cards.size() > 1:
		card_step = minf(expanded_step, (available_width - card_size.x) / float(cards.size() - 1))
		card_step = maxf(card_step, minimum_visible_width)
	# 实际内容宽度；超过可视宽度时由父级 ScrollContainer 提供横向滑动。
	var content_width: float = horizontal_padding * 2.0 + card_size.x + card_step * float(cards.size() - 1)
	custom_minimum_size = Vector2(maxf(content_width, available_width + horizontal_padding * 2.0), content_height)
	# 当前悬停卡牌索引；同一时刻最多有一张牌接收鼠标悬停，用于保持放大牌底边对齐并提升绘制层级。
	var hovered_card_index: int = -1
	for card_index: int in range(cards.size()):
		if cards[card_index].is_hovered_in_hand():
			hovered_card_index = card_index
			break
	# 卡牌基础纵坐标；底部对齐并为选中抬升预留顶部空间。
	var base_y: float = maxf(content_height - card_size.y, selected_lift)
	# 当前卡牌横坐标；从左侧安全边距开始，逐张累加固定的当前压缩步长，悬停不会修改任何牌间距。
	var current_card_x: float = horizontal_padding
	for card_index: int in range(cards.size()):
		# 当前卡牌节点；Node2D 根只表达实体牌本身，透明输入组件跟随其整体移动。
		var card: CardView = cards[card_index]
		# 当前卡牌是否处于选中状态；只影响位置和绘制层级，不代表规则合法。
		var selected: bool = card.is_card_selected
		# 当前卡牌是否悬停；悬停牌只补偿缩放后的宽高并提高层级，不移动任何其他手牌。
		var hovered: bool = card_index == hovered_card_index
		# 悬停缩放额外占用的水平尺寸；左右各补偿一半，使放大围绕牌面中心发生。
		var hover_width_compensation: float = card_size.x * (card.hover_scale - 1.0) * 0.5 if hovered else 0.0
		# 悬停缩放额外占用的垂直尺寸；整体向上补偿，使放大后的牌底仍与普通手牌对齐。
		var hover_height_compensation: float = card_size.y * (card.hover_scale - 1.0) if hovered else 0.0
		# 当前卡牌位置；选中状态上移，悬停状态围绕中心放大且保持底边对齐。
		card.position = Vector2(current_card_x - hover_width_compensation, base_y - (selected_lift if selected else 0.0) - hover_height_compensation)
		card.z_index = CardView.HOVER_Z_INDEX if hovered else (cards.size() + card_index if selected else card_index)
		current_card_x += card_step
