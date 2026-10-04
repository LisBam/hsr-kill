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

## 容器用于容纳卡牌、18像素选中抬升和1.06倍悬停放大的固定高度；默认175像素，运行时通常无需动态修改。
## 该高度让选中且悬停的牌面仍完整位于手牌滚动区域内，不会被手牌框或相邻界面裁剪。
@export_range(148.0, 240.0, 1.0) var content_height: float = 175.0

## 槽位变化后的整理过渡时长；默认0.18秒，与弃牌队列补位时长保持一致，运行时可由主题调整。
## 有牌离场或插入时，其余手牌在该时长内从原槽位滑向新槽位；设为极小值即退化为原来的瞬间跳位。
@export_range(0.05, 0.8, 0.01) var relayout_animation_seconds: float = 0.18

## 最近一次已应用的结构布局签名；默认-1强制首次布局，重复快照只有结构或交互状态变化时才重新计算位置。
var _layout_signature: int = -1

## 已实际执行的结构布局次数；从0开始，仅供性能诊断与回归测试读取，运行时不得手动修改。
var _layout_revision: int = 0

## 卡牌实例 ID 到上一次写入的槽位左上角的映射；槽位只由压缩步长和基础纵坐标决定，不含悬停放大补偿，
## 因此悬停一张牌不会让任何其他手牌产生整理过渡。离场卡牌的记录在同一轮布局开始时清理。
var _slot_positions: Dictionary = {}

## 卡牌实例 ID 到整理过渡补间的映射；同一张牌同时只保留一条补间，槽位再次变化时先终止旧补间。
var _relayout_tweens: Dictionary = {}

## 连接父级尺寸变化并请求首次布局；父级通常是只启用横向滚动的 ScrollContainer。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# 父级可视宽度决定手牌是完整展开、互相覆盖还是进入横向滚动。
	var parent_control: Control = get_parent() as Control
	if parent_control != null:
		parent_control.resized.connect(queue_sort)
	queue_sort()


## 退出场景树时终止全部整理过渡补间并清空槽位记录；节点即将释放，补间不得再写入已失效的位置。
func _exit_tree() -> void:
	for relayout_tween_variant: Variant in _relayout_tweens.values():
		# 当前仍有效的整理过渡补间；统一停止后再清空索引。
		var relayout_tween: Tween = relayout_tween_variant as Tween
		if relayout_tween != null and relayout_tween.is_valid():
			relayout_tween.kill()
	_relayout_tweens.clear()
	_slot_positions.clear()


## 在 Godot 容器排序通知中重新计算全部卡牌位置。
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout_cards()


## 由卡牌组件在选中状态变化后调用，确保抬升距离和绘制层级立即同步。
func refresh_card_states() -> void:
	queue_sort()


## 立即应用一次手牌布局；正式手牌入场动画在计算右侧起点前调用，以取得包含新实体牌的最终落点。
func layout_cards_now() -> void:
	_layout_cards()


## 返回有效手牌结构布局执行序号；只读诊断值可判断重复刷新是否真正触发了位置计算。
func get_layout_revision() -> int:
	return _layout_revision


## 结束指定卡牌的整理过渡并把其过渡偏移归零；卡牌即将离开本容器、由动画层接管时调用。
## 残留的过渡偏移与仍在运行的补间都会继续写入 position，若不在此收尾，飞牌起点会偏离槽位并与其他补间争用坐标。
func end_card_relayout_transition(card: CardView) -> void:
	if card == null or not is_instance_valid(card):
		return
	_kill_relayout_tween(card.get_instance_id())
	card.hand_layout_offset = Vector2.ZERO


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
	# 本次布局签名数据；只包含决定基准位置、缩放补偿和绘制层级的稳定字段，不保存节点或对局快照。
	var layout_signature_data: Array = [available_width, card_size, horizontal_padding, preferred_card_gap, minimum_visible_width, selected_lift, content_height]
	# 当前写入签名的卡牌节点；节点身份、顺序和交互状态共同决定现有结构布局能否继续复用。
	for card: CardView in cards:
		layout_signature_data.append([card.get_instance_id(), card.is_card_selected, card.is_hovered_in_hand(), card.is_hand_dragging(), card.hover_scale])
	# 本次结构布局签名；相同结果表示现有位置仍有效，入场与选中 Tween 会通过自身偏移属性继续移动原节点。
	var next_layout_signature: int = hash(layout_signature_data)
	if _layout_signature == next_layout_signature:
		return
	_layout_signature = next_layout_signature
	_layout_revision += 1
	# 本轮实际参与摆放的卡牌实例 ID 集合；在任何槽位读取之前先清理已经离场或隐藏卡牌的槽位记录与补间，
	# 避免节点释放后实例 ID 被新卡牌复用时继承到不属于自己的残留过渡量。
	var present_card_ids: Dictionary = {}
	for present_card: CardView in cards:
		present_card_ids[present_card.get_instance_id()] = true
	_clear_departed_card_layout_records(present_card_ids)
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
	# 紧凑手牌栏以普通牌底边对齐为基准；选中与悬停位移会在写入位置时限制到容器顶部以内。
	var base_y: float = maxf(content_height - card_size.y, 0.0)
	# 当前卡牌横坐标；从左侧安全边距开始，逐张累加固定的当前压缩步长，悬停不会修改任何牌间距。
	var current_card_x: float = horizontal_padding
	for card_index: int in range(cards.size()):
		# 当前卡牌节点；Node2D 根只表达实体牌本身，透明输入组件跟随其整体移动。
		var card: CardView = cards[card_index]
		# 当前实体牌是否正由鼠标直接拖动；拖动期间保留原节点位置与最高层级，其他牌仍按常规顺序即时布局。
		var hand_dragging: bool = card.is_hand_dragging()
		# 当前卡牌是否处于选中状态；只影响位置和绘制层级，不代表规则合法。
		var selected: bool = card.is_card_selected
		# 当前卡牌是否悬停；悬停牌只补偿缩放后的宽高并提高层级，不移动任何其他手牌。
		var hovered: bool = card_index == hovered_card_index
		# 悬停缩放额外占用的水平尺寸；左右各补偿一半，使放大围绕牌面中心发生。
		var hover_width_compensation: float = card_size.x * (card.hover_scale - 1.0) * 0.5 if hovered else 0.0
		# 悬停缩放额外占用的垂直尺寸；整体向上补偿，使放大后的牌底仍与普通手牌对齐。
		var hover_height_compensation: float = card_size.y * (card.hover_scale - 1.0) if hovered else 0.0
		# 当前期望纵坐标；悬停补偿由容器即时计算，选中抬升由 CardView 的0.025秒独立偏移动画负责。
		var desired_card_y: float = base_y - hover_height_compensation
		# 当前卡牌的稳定槽位左上角；只由压缩步长与基础纵坐标决定，不含悬停放大补偿，
		# 因此悬停一张牌不会让其他手牌误判为发生了槽位变化而产生整理过渡。
		var slot_position: Vector2 = Vector2(current_card_x, maxf(base_y, 0.0))
		# 上一次记录的槽位；缺失表示该牌本轮才加入容器，应交给获得入场动画决定起点而不是整理过渡。
		var previous_slot: Variant = _slot_positions.get(card.get_instance_id())
		if hand_dragging or previous_slot == null:
			# 新加入的牌与正在拖动的牌不参与整理过渡：前者由获得入场动画独占位置，后者位置由鼠标唯一决定。
			_kill_relayout_tween(card.get_instance_id())
			if not card.hand_layout_offset.is_zero_approx():
				# 拖动中的牌不能被整理过渡改写位置；归零偏移后立即反向补偿，保持鼠标跟随完全不受影响。
				var dragged_residual: Vector2 = card.hand_layout_offset
				card.hand_layout_offset = Vector2.ZERO
				card.position -= dragged_residual
		elif not (previous_slot as Vector2).is_equal_approx(slot_position):
			# 槽位发生变化：先把该牌视觉上留在原槽位，再把偏移补间归零，形成“其余手牌滑向新槽位”的整理表现。
			_start_relayout_transition(card, previous_slot as Vector2, slot_position)
		_slot_positions[card.get_instance_id()] = slot_position
		# 当前卡牌位置；布局位置叠加入场偏移、选中动画偏移和整理过渡偏移，重排不会打断任一独立表现。
		if not hand_dragging:
			card.position = Vector2(current_card_x - hover_width_compensation, maxf(desired_card_y, 0.0)) + card.hand_entry_offset + card.hand_selection_offset + card.hand_layout_offset
			card.z_index = CardView.HOVER_Z_INDEX if hovered else (cards.size() + card_index if selected else card_index)
		current_card_x += card_step


## 启动一次整理过渡；偏移按差值累加写入，因此连续两次布局不会丢失尚未播完的过渡量。
## 传入的是不含悬停补偿的槽位坐标，保证悬停与整理两种表现互不干扰。
func _start_relayout_transition(card: CardView, previous_slot: Vector2, next_slot: Vector2) -> void:
	card.hand_layout_offset += previous_slot - next_slot
	_kill_relayout_tween(card.get_instance_id())
	# 整理过渡补间；与入场、选中补间同构，只驱动本属性归零，槽位真值仍由每次布局绝对写入。
	var relayout_tween: Tween = create_tween()
	relayout_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	relayout_tween.tween_property(card, "hand_layout_offset", Vector2.ZERO, relayout_animation_seconds)
	_relayout_tweens[card.get_instance_id()] = relayout_tween


## 终止指定实例的整理过渡补间；补间自然结束后对象可能仍有效，因此统一按 is_valid() 判断后再终止。
func _kill_relayout_tween(card_instance_id: int) -> void:
	# 当前实例的整理过渡补间；终止后立即从索引移除，防止旧补间继续写入新槽位。
	var relayout_tween: Tween = _relayout_tweens.get(card_instance_id) as Tween
	if relayout_tween != null and relayout_tween.is_valid():
		relayout_tween.kill()
	_relayout_tweens.erase(card_instance_id)


## 清理已经离开容器的卡牌遗留的槽位记录与整理补间；传入本轮实际参与布局的实例 ID 集合。
func _clear_departed_card_layout_records(present_card_ids: Dictionary) -> void:
	for card_instance_id_variant: Variant in _slot_positions.keys():
		# 当前槽位记录对应的卡牌实例 ID；不在本轮布局集合中的实例已经离场或被隐藏。
		var card_instance_id: int = int(card_instance_id_variant)
		if present_card_ids.has(card_instance_id):
			continue
		_slot_positions.erase(card_instance_id)
		_kill_relayout_tween(card_instance_id)

