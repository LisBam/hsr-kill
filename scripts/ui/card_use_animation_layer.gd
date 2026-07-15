class_name CardUseAnimationLayer
extends Control

## 卡牌使用表现层。该组件接管正式 CardView 节点播放飞牌与目标指示线，不创建任何替代牌模型或修改权威状态。

## 飞牌动画持续时间；默认0.42秒兼顾动作辨识与对局节奏，可在检查器中运行前调整。
@export_range(0.1, 1.5, 0.01) var card_flight_duration: float = 0.42

## 卡牌抵达弃牌区后的停留时间；默认0.48秒用于让玩家辨认牌面，可在运行时动态调整。
@export_range(0.0, 2.0, 0.01) var card_hold_duration: float = 0.48

## 目标指示线淡出时间；默认0.36秒，在动态延伸完成后立即平滑消失，同时作为正式卡牌收尾淡出时长。
@export_range(0.1, 1.5, 0.01) var target_line_fade_duration: float = 0.36

## 目标指示线从来源延伸到目标的时间；默认0.24秒形成清晰方向感，运行时可按整体节奏动态调整。
@export_range(0.05, 1.0, 0.01) var target_line_draw_duration: float = 0.24

## 动画牌面目标缩放倍率；默认1.0保持正式111×148实体牌模型和3:4比例不变，运行时通常无需修改。
@export_range(0.5, 1.5, 0.01) var animated_card_scale: float = 1.0

## 弃牌展示队列中相邻卡牌中心的水平间距；默认66像素可同时辨认多张牌，并允许牌面轻微重叠。
@export_range(24.0, 160.0, 1.0) var discard_queue_spacing: float = 66.0

## 队列成员增减后的重新铺开时长；默认0.18秒使卡牌补位清晰且不拖慢规则结算，可在运行时动态调整。
@export_range(0.05, 0.8, 0.01) var queue_reflow_duration: float = 0.18

## 目标指示线宽度；默认4像素，在深色桌面背景上保持清晰。
@export_range(1.0, 12.0, 0.5) var target_line_width: float = 4.0

## 目标指示线颜色；金色与当前牌桌选中反馈一致，仅影响视觉表现。
@export var target_line_color: Color = Color("e4bd67")

## 动画层绘制层级；默认30确保目标线与飞牌位于角色界面之上、菜单和选将遮罩之下，运行时通常无需修改。
@export_range(0, 100, 1) var presentation_z_index: int = 30

## 当前正在执行顺序淡出的正式卡牌节点；可能来自手牌，也可能是不可见牌的完整正式视图。
var _animated_card: CardView

## 当前仍在飞行、停留或等待淡出的正式卡牌队列；数组顺序同时决定从左到右的铺开顺序。
var _active_cards: Array[CardView] = []

## 已完成飞行与停留、等待依次淡出的卡牌队列；只有队首卡牌会进入淡出补间。
var _fade_queue: Array[CardView] = []

## 当前是否已有顺序淡出任务运行；用于避免多次播放同时启动多个消费者。
var _is_fade_worker_running: bool = false

## 最近一次弃牌展示中心；新增或移除队列成员后以该坐标重新计算横向铺开位置。
var _discard_center: Vector2 = Vector2.ZERO

## 卡牌实例 ID 到移动补间的映射；重新排队前终止旧补间，避免多个位置动画同时争用同一节点。
var _motion_tweens: Dictionary = {}

## 卡牌实例 ID 到表现序号的映射；用于在对应卡牌淡出时同步移除该次目标指示线。
var _card_sequences: Dictionary = {}

## 表现序号到目标指示线数据的映射；每次出牌拥有独立起点、目标数组和透明度，可并行显示。
var _line_presentations: Dictionary = {}

## 当前表现序号；每次播放递增，为卡牌与对应目标指示线建立稳定关联。
var _presentation_sequence: int = 0

## 当前动画代次；重新开局清空表现时递增，使上一局仍在等待的异步淡出任务安全退出。
var _presentation_generation: int = 0


## 进入场景树时应用检查器配置的稳定绘制层级，独立实例与正式场景保持一致。
func _ready() -> void:
	z_index = presentation_z_index


## 播放一次卡牌使用表现；传入节点始终是正式 CardView，所有位置使用本组件局部坐标。
func play_card(card_view: CardView, start_position: Vector2, discard_position: Vector2, target_positions: Array[Vector2]) -> void:
	if card_view == null:
		return
	_presentation_sequence += 1
	# 本次表现序号；用于关联当前卡牌、目标指示线与后续顺序淡出清理。
	var sequence: int = _presentation_sequence
	# 本次目标指示线初始透明度；无目标卡牌不创建可见线条，但仍保留统一表现数据结构。
	var line_alpha: float = 1.0 if not target_positions.is_empty() else 0.0
	_line_presentations[sequence] = {
		"start_position":start_position,
		"target_positions":target_positions.duplicate(),
		"alpha":line_alpha,
		"progress":0.0,
	}
	queue_redraw()
	if not target_positions.is_empty():
		# 指示线生长与淡出补间；线条沿来源到目标逐渐延伸，完整到达后立即连续渐隐，不等待飞牌停留或弃牌队列。
		var line_draw_tween: Tween = create_tween()
		line_draw_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		line_draw_tween.tween_method(_set_line_progress.bind(sequence), 0.0, 1.0, target_line_draw_duration)
		line_draw_tween.tween_method(_set_line_alpha.bind(sequence), line_alpha, 0.0, target_line_fade_duration)
		line_draw_tween.tween_callback(_remove_line_presentation.bind(sequence))
	# 当前进入动画层的正式卡牌；每张牌独立加入队列，不会清除仍在展示的前一张牌。
	var presented_card: CardView = card_view
	# 原卡牌的全局变换；重新挂载到动画层后恢复该变换，保证动画从屏幕中原位置连续开始。
	var original_global_transform: Transform2D = presented_card.global_transform
	if presented_card.get_parent() != self:
		presented_card.reparent(self)
	presented_card.global_transform = original_global_transform
	presented_card.set_selected_state(false)
	# 清除选中状态可能恢复普通容器纵坐标，因此再次恢复接管前变换，保证飞牌起点连续。
	presented_card.global_transform = original_global_transform
	presented_card.z_index = _active_cards.size() + 1
	presented_card.rotation = 0.0
	presented_card.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_discard_center = discard_position
	_active_cards.append(presented_card)
	_card_sequences[presented_card.get_instance_id()] = sequence
	# 飞牌补间；新牌从使用者位置进入弃牌队列，已有牌同步横向补位且全程保持水平不倾斜。
	_start_card_motion(presented_card, _queue_card_position(_active_cards.size() - 1), card_flight_duration)
	# 飞牌外观补间；与可被队列重排替换的位置补间分离，确保缩放和透明度不会被补位操作中断。
	var appearance_tween: Tween = create_tween().set_parallel(true)
	appearance_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	appearance_tween.tween_property(presented_card, "scale", Vector2.ONE * animated_card_scale, card_flight_duration)
	appearance_tween.tween_property(presented_card, "rotation", 0.0, card_flight_duration)
	appearance_tween.tween_property(presented_card, "modulate", Color.WHITE, card_flight_duration)
	_reflow_active_cards(card_flight_duration, presented_card)
	# 飞行等待计时器；队列重排可能替换位置补间，独立计时可保证该牌仍会进入后续停留与淡出流程。
	await get_tree().create_timer(card_flight_duration).timeout
	if not is_instance_valid(presented_card) or not _active_cards.has(presented_card):
		return
	await get_tree().create_timer(card_hold_duration).timeout
	if not is_instance_valid(presented_card) or not _active_cards.has(presented_card):
		return
	_fade_queue.append(presented_card)
	_drain_fade_queue()


## 立即清空全部飞牌、弃牌队列和目标线；重新开局时调用，避免上一局异步表现残留到新桌面。
func clear_presentations() -> void:
	_presentation_generation += 1
	for motion_tween_variant: Variant in _motion_tweens.values():
		# 当前仍存活的移动补间；清场时主动终止，避免继续访问已经排队释放的牌面节点。
		var motion_tween: Tween = motion_tween_variant as Tween
		if motion_tween != null and motion_tween.is_valid():
			motion_tween.kill()
	for active_card: CardView in _active_cards:
		if active_card != null and is_instance_valid(active_card):
			active_card.queue_free()
	_active_cards.clear()
	_fade_queue.clear()
	_motion_tweens.clear()
	_card_sequences.clear()
	_line_presentations.clear()
	_animated_card = null
	_is_fade_worker_running = false
	queue_redraw()


## 顺序淡出所有已经完成停留的卡牌；队列只运行一个消费者，保证多张牌逐个消失。
func _drain_fade_queue() -> void:
	if _is_fade_worker_running:
		return
	_is_fade_worker_running = true
	# 当前淡出任务代次；重新开局会递增全局代次，使本任务在下次等待结束后立即退出。
	var worker_generation: int = _presentation_generation
	while not _fade_queue.is_empty():
		_animated_card = _fade_queue.pop_front()
		if _animated_card == null or not is_instance_valid(_animated_card) or not _active_cards.has(_animated_card):
			continue
		# 当前淡出卡牌的表现序号；用于把该牌对应的目标线与牌面同时淡出并清理。
		var sequence: int = int(_card_sequences.get(_animated_card.get_instance_id(), -1))
		# 收尾补间；正式卡牌保持水平并淡出消失，目标指示线通常已在延伸后独立完成渐隐。
		var fade_tween: Tween = create_tween().set_parallel(true)
		fade_tween.tween_property(_animated_card, "modulate:a", 0.0, target_line_fade_duration)
		if sequence >= 0 and _line_presentations.has(sequence):
			# 当前目标线透明度；防御性收尾仅处理尚未完成独立渐隐的异常或极短飞牌配置。
			var current_line_alpha: float = float((_line_presentations[sequence] as Dictionary).get("alpha", 1.0))
			fade_tween.tween_method(_set_line_alpha.bind(sequence), current_line_alpha, 0.0, target_line_fade_duration)
		await fade_tween.finished
		if worker_generation != _presentation_generation:
			return
		if sequence >= 0:
			_line_presentations.erase(sequence)
		_remove_animated_card()
		_reflow_active_cards(queue_reflow_duration)
		queue_redraw()
	_is_fade_worker_running = false
	_animated_card = null


## 为一张卡牌启动到队列目标位置的移动补间；同一卡牌旧补间会先终止，避免位置争用。
func _start_card_motion(card_view: CardView, target_position: Vector2, duration: float) -> Tween:
	# 卡牌实例 ID；作为移动补间映射的稳定键，节点释放后同时清理。
	var card_instance_id: int = card_view.get_instance_id()
	# 已存在的移动补间；队列重排时旧目标已经失效，应立即停止。
	var previous_tween: Tween = _motion_tweens.get(card_instance_id) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	# 新位置补间；统一使用二次缓出，使飞入和补位都在接近目标时自然减速。
	var motion_tween: Tween = create_tween()
	motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion_tween.tween_property(card_view, "position", target_position, duration)
	_motion_tweens[card_instance_id] = motion_tween
	return motion_tween


## 根据当前队列成员数量重新计算全部横向位置；可排除正在使用专属飞行补间的新牌。
func _reflow_active_cards(duration: float, excluded_card: CardView = null) -> void:
	for card_index: int in range(_active_cards.size()):
		# 当前队列卡牌；无效节点会在淡出或清理流程中移除，不参与本次补位。
		var active_card: CardView = _active_cards[card_index]
		if active_card == null or not is_instance_valid(active_card) or active_card == excluded_card:
			continue
		active_card.z_index = card_index + 1
		_start_card_motion(active_card, _queue_card_position(card_index), duration)


## 返回指定队列索引的卡牌左上角位置；整个队列以弃牌中心为轴水平对称铺开。
func _queue_card_position(card_index: int) -> Vector2:
	# 当前队列总水平跨度；单张牌跨度为0，多张牌按固定中心间距展开。
	var queue_span: float = discard_queue_spacing * float(maxi(_active_cards.size() - 1, 0))
	# 当前卡牌尺寸；正式牌面统一为3:4，仍从组件接口读取以兼容后续主题资源。
	var card_size: Vector2 = _active_cards[card_index].get_card_size()
	return Vector2(_discard_center.x - queue_span * 0.5 + discard_queue_spacing * float(card_index) - card_size.x * 0.5, _discard_center.y - card_size.y * 0.5)


## 更新某次目标指示线透明度；Tween 通过该入口驱动字典数据并请求重绘。
func _set_line_alpha(alpha: float, sequence: int) -> void:
	if not _line_presentations.has(sequence):
		return
	# 当前目标线数据；写回同一表现序号，避免字典值复制导致透明度丢失。
	var presentation: Dictionary = _line_presentations[sequence] as Dictionary
	presentation["alpha"] = alpha
	_line_presentations[sequence] = presentation
	queue_redraw()


## 更新某次目标指示线的延伸进度；0表示仅在来源点，1表示完整到达全部目标。
func _set_line_progress(progress: float, sequence: int) -> void:
	if not _line_presentations.has(sequence):
		return
	# 当前目标线数据；进度限制在0至1，避免补间边界误差造成线段越过目标。
	var presentation: Dictionary = _line_presentations[sequence] as Dictionary
	presentation["progress"] = clampf(progress, 0.0, 1.0)
	_line_presentations[sequence] = presentation
	queue_redraw()


## 移除已完成动态延伸与渐隐的目标线；卡牌队列仍保留自己的飞行、停留与淡出生命周期。
func _remove_line_presentation(sequence: int) -> void:
	_line_presentations.erase(sequence)
	queue_redraw()


## 绘制带端点光晕的目标指示线；多目标牌从同一使用者位置分别指向每名目标。
func _draw() -> void:
	for presentation_variant: Variant in _line_presentations.values():
		# 当前一次出牌的指示线数据；每张队列卡牌保留独立透明度和目标数组。
		var presentation: Dictionary = presentation_variant as Dictionary
		# 当前指示线透明度；不可见数据直接跳过，避免无意义绘制调用。
		var presentation_alpha: float = float(presentation.get("alpha", 0.0))
		if presentation_alpha <= 0.0:
			continue
		# 当前指示线起点；使用者位置在出牌时已经转换为动画层局部坐标。
		var presentation_start: Vector2 = presentation.get("start_position", Vector2.ZERO) as Vector2
		# 当前线条延伸比例；所有目标共享同一进度，从共同来源同步向外生长。
		var presentation_progress: float = float(presentation.get("progress", 1.0))
		# 当前线条颜色；每次表现独立控制透明度，多目标仍共享同一视觉语义。
		var line_color: Color = Color(target_line_color, target_line_color.a * presentation_alpha)
		for target_position_variant: Variant in presentation.get("target_positions", []):
			# 当前目标位置；来自桌面角色视图中心，不读取任何权威状态对象。
			var target_position: Vector2 = target_position_variant as Vector2
			# 当前动态端点；随补间从来源移动到真实目标，形成明确的来源到目标方向。
			var animated_target_position: Vector2 = presentation_start.lerp(target_position, presentation_progress)
			draw_line(presentation_start, animated_target_position, line_color, target_line_width, true)
			draw_circle(animated_target_position, target_line_width * 1.8, line_color)


## 释放当前动画牌节点；它已离开权威手牌快照，动画完成后不应回到手牌容器。
func _remove_animated_card() -> void:
	if _animated_card != null and is_instance_valid(_animated_card):
		# 当前淡出卡牌实例 ID；用于同步清理移动补间与表现序号映射。
		var card_instance_id: int = _animated_card.get_instance_id()
		_active_cards.erase(_animated_card)
		_motion_tweens.erase(card_instance_id)
		_card_sequences.erase(card_instance_id)
		_animated_card.queue_free()
	_animated_card = null
