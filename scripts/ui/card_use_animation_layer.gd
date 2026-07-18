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

## 兼容未归入批次的区域转移时相邻牌面的堆叠偏移；默认向右18像素、向上3像素，避免同一锚点的多个临时牌面完全重合。
@export var draw_stack_offset: Vector2 = Vector2(18.0, -3.0)

## 同一次摸牌中相邻牌面中心的水平间距；默认42像素让整组可辨认且以目标锚点为中心，运行时可按主题调整。
@export_range(20.0, 100.0, 1.0) var draw_batch_card_spacing: float = 42.0

## 每秒包含的毫秒数；用于计算卡牌从开始飞行到规则响应完成之间已经经过的真实时间。
const MILLISECONDS_PER_SECOND: float = 1000.0

## 当前正在执行顺序淡出的正式卡牌节点；可能来自手牌，也可能是不可见牌的完整正式视图。
var _animated_card: CardView

## 当前仍在飞行、停留或等待淡出的正式卡牌队列；数组顺序同时决定从左到右的铺开顺序。
var _active_cards: Array[CardView] = []

## 已完成飞行与停留、等待依次淡出的卡牌队列；只有队首卡牌会进入淡出补间。
var _fade_queue: Array[CardView] = []

## 当前是否已有顺序淡出任务运行；用于避免多次播放同时启动多个消费者。
var _is_fade_worker_running: bool = false

## 当前是否已安排下一帧启动淡出消费者；同一帧完成停留的牌会在消费者启动前组成完整批次。
var _is_fade_worker_scheduled: bool = false

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

## 当前动画代次；重新开局清空表现时递增，使上一局仍在等待的飞牌、淡出和区域转移任务安全退出。
var _presentation_generation: int = 0

## 正在执行普通区域转移动画的实例 ID 到牌面节点映射；稳定整数键保证节点释放后仍能安全清理索引。
var _transfer_cards: Dictionary = {}

## 摸牌堆叠键到牌面实例 ID 数组的映射；不保存对象引用，重开释放节点后仍可安全清空与去重。
var _draw_transfer_stacks: Dictionary = {}

## 普通区域转移牌面实例 ID 到补间的映射；重新开局时清空所有权索引，旧协程依靠动画代次安全退出。
var _transfer_tweens: Dictionary = {}

## 摸牌表现批次递增序号；每次 draw() 都取得独立 ID，使多个玩家或同一玩家的连续摸牌可立即并行播放。
var _draw_transfer_batch_sequence: int = 0

## 当前摸牌批次 ID 到正在执行补间的映射；重开时统一终止全部批次，避免旧局协程继续访问新桌面节点。
var _draw_transfer_batch_tweens: Dictionary = {}

## 使用、展示与判定牌实例 ID 到生命周期补间的映射；单一补间替代逐牌飞行和停留计时器，重开时可统一终止。
var _card_lifecycle_tweens: Dictionary = {}

## 接管弃牌移动的实体 UID 到中央牌面实例 ID 的映射；规则响应完成并发生最终移牌前不会安排该牌淡出。
var _discard_claim_card_instance_ids: Dictionary = {}

## 中央牌面实例 ID 到开始表现毫秒时间的映射；最终移牌到达时据此补足尚未完成的飞行时间和完整停留时间。
var _card_presentation_started_msec: Dictionary = {}

## 已由牌面表现接管后续弃牌动画的实体 UID 集合；键为UID、值固定为true，纯展示牌不会进入该集合。
var _discard_transfer_claims: Dictionary = {}

## 已消费弃牌认领的实体 UID 集合；重复移动与迟到表现继续视为已接管，直到权威移牌确认该 UID 进入非弃牌新区域。
## 普通弃牌首次显示时也会登记到该集合，使无预先认领的重复增量沿用相同幂等生命周期。
var _consumed_discard_transfer_claims: Dictionary = {}

## 本局已经接收的表现 ID 集合；键为单调 presentation_id，值固定为true，用于拒绝网络重发或重复信号。
var _seen_presentation_ids: Dictionary = {}


## 进入场景树时应用检查器配置的稳定绘制层级，独立实例与正式场景保持一致。
func _ready() -> void:
	z_index = presentation_z_index


## 登记一次牌面表现并原子取得弃牌动画所有权；返回false表示相同表现或实体使用已经处理，调用方不得再次创建节点。
func claim_presentation(presentation_id: int, card_uid: int, owns_discard_transfer: bool) -> bool:
	if presentation_id >= 0 and _seen_presentation_ids.has(presentation_id):
		return false
	if presentation_id >= 0:
		_seen_presentation_ids[presentation_id] = true
	if not owns_discard_transfer or card_uid < 0:
		return true
	# 同一实体仍有待消费或已消费认领时，新的不同表现 ID 也视为迟到重复；只有权威非弃牌移牌才能开始下一生命周期。
	if _discard_transfer_claims.has(card_uid) or _consumed_discard_transfer_claims.has(card_uid):
		return false
	# 新一轮真实使用；权威移牌已经清理旧生命周期，此处只登记本轮待到达的最终弃牌移动。
	_discard_transfer_claims[card_uid] = presentation_id
	return true


## 播放一次卡牌使用表现；传入节点始终是正式 CardView，所有位置使用本组件局部坐标。
## owns_discard_transfer 仅供真实处理区牌和判定牌开启，仍留在手牌区的 showCards 表现必须保持false。
func play_card(card_view: CardView, start_position: Vector2, discard_position: Vector2, target_positions: Array[Vector2], owns_discard_transfer: bool = false) -> void:
	if card_view == null:
		return
	if owns_discard_transfer and card_view.card_uid >= 0 and not _discard_transfer_claims.has(card_view.card_uid):
		# 组件独立调用兼容入口；正式桌面已在节点创建前通过 claim_presentation 原子登记，此分支只补齐直接调用的所有权。
		_consumed_discard_transfer_claims.erase(card_view.card_uid)
		_discard_transfer_claims[card_view.card_uid] = -1
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
	# 新实例在完成父级、坐标和外观初始化后才显示，避免场景树插入瞬间以默认原点闪现一帧。
	presented_card.visible = true
	_discard_center = discard_position
	_active_cards.append(presented_card)
	# 当前表现牌实例 ID；移动、生命周期和清理映射统一使用该稳定整数。
	var presented_card_instance_id: int = presented_card.get_instance_id()
	_card_sequences[presented_card_instance_id] = sequence
	_card_presentation_started_msec[presented_card_instance_id] = Time.get_ticks_msec()
	if owns_discard_transfer and presented_card.card_uid >= 0:
		# 当前由规则响应生命周期持有的中央牌面；只有最终弃牌或进入其他权威区域后才开始停留与淡出。
		_discard_claim_card_instance_ids[presented_card.card_uid] = presented_card_instance_id
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
	# 当前改由一个生命周期补间覆盖飞行与停留，避免每张牌创建两个 SceneTreeTimer 和一个挂起协程。
	# 接管最终弃牌移动的牌由规则完成信号启动收尾，纯展示与普通弃牌继续使用固定飞行加停留时长。
	if not owns_discard_transfer or presented_card.card_uid < 0:
		_schedule_card_fade(presented_card_instance_id, card_flight_duration + card_hold_duration)


## 播放一次牌区转移表现；可选堆叠键只调整临时牌面落点，所有调用均立即开始飞行。
func play_transfer(card_view: CardView, start_position: Vector2, target_position: Vector2, draw_stack_key: String = "") -> void:
	if card_view == null:
		return
	# 转移牌面；始终由动画层持有，完成后释放而不返回任何界面容器。
	var transfer_card: CardView = card_view
	# 转移牌面实例 ID；数组和补间索引只保存该稳定整数，不使用可能在重开时失效的对象作为删除参数。
	var transfer_card_instance_id: int = transfer_card.get_instance_id()
	# 本次区域转移所属动画代次；重新开局后旧协程必须在访问牌面前立即退出。
	var transfer_generation: int = _presentation_generation
	if transfer_card.get_parent() != self:
		transfer_card.reparent(self)
	transfer_card.position = start_position - transfer_card.get_card_size() * 0.5
	transfer_card.rotation = 0.0
	transfer_card.scale = Vector2.ONE * 0.82
	transfer_card.modulate = Color.WHITE
	# 转移牌同样在最终起点写入后才显示，不能以新节点默认坐标参与任何一帧绘制。
	transfer_card.visible = true
	_transfer_cards[transfer_card_instance_id] = transfer_card
	# 当前堆叠索引；普通转移保持0，同一玩家连续摸牌按到达顺序递增。
	var stack_index: int = 0
	if not draw_stack_key.is_empty():
		# 当前摸牌堆叠实例 ID 数组；顺序仅用于计算偏移和层级，不持有牌面节点。
		var draw_stack: Array = _draw_transfer_stacks.get(draw_stack_key, []) as Array
		stack_index = draw_stack.size()
		draw_stack.append(transfer_card_instance_id)
		_draw_transfer_stacks[draw_stack_key] = draw_stack
	transfer_card.z_index = 80 + stack_index if not draw_stack_key.is_empty() else 80 + _transfer_cards.size()
	# 最终堆叠位置；第一张落在玩家锚点，后续牌按固定向量依次压叠显示。
	var stacked_target_position: Vector2 = target_position - transfer_card.get_card_size() * 0.5 + draw_stack_offset * float(stack_index)
	# 移动补间；无论是否存在同组转移牌都立即开始，避免没有批次信号的摸牌退化为逐张等待。
	var transfer_tween: Tween = create_tween()
	transfer_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transfer_tween.tween_property(transfer_card, "position", stacked_target_position, card_flight_duration)
	transfer_tween.parallel().tween_property(transfer_card, "scale", Vector2.ONE * animated_card_scale, card_flight_duration)
	transfer_tween.tween_interval(minf(card_hold_duration, 0.24))
	transfer_tween.tween_property(transfer_card, "modulate:a", 0.0, target_line_fade_duration)
	_transfer_tweens[transfer_card_instance_id] = transfer_tween
	await transfer_tween.finished
	if transfer_generation != _presentation_generation:
		# 旧局转移牌面；清场时已隐藏，补间正常结束后才在此释放，避免补间写入已释放节点。
		if is_instance_valid(transfer_card):
			transfer_card.queue_free()
		return
	_transfer_tweens.erase(transfer_card_instance_id)
	_transfer_cards.erase(transfer_card_instance_id)
	_remove_draw_transfer_card(draw_stack_key, transfer_card_instance_id)
	if is_instance_valid(transfer_card):
		transfer_card.queue_free()


## 立即播放一次完整摸牌批次；同批牌从同一牌堆起点同时飞向以目标锚点为中心的横向组合，不等待其他玩家或其他 draw() 调用的批次结束。
func play_draw_transfer_batch(card_views: Array[CardView], start_position: Vector2, target_position: Vector2) -> void:
	# 当前可播放的正式牌面；空、已释放节点不创建无内容动画任务。
	var valid_card_views: Array[CardView] = []
	for card_view: CardView in card_views:
		if card_view == null or not is_instance_valid(card_view):
			continue
		if card_view.get_parent() != self:
			add_child(card_view)
		# 批次启动前保持隐藏；下面的独立批次协程会在本帧同步完成起点写入后显示全部成员。
		card_view.visible = false
		_transfer_cards[card_view.get_instance_id()] = card_view
		valid_card_views.append(card_view)
	if valid_card_views.is_empty():
		return
	# 当前批次 ID；仅用于表现补间管理，绝不写入权威实体、快照或回放。
	_draw_transfer_batch_sequence += 1
	_play_draw_transfer_batch(_draw_transfer_batch_sequence, valid_card_views, start_position, target_position)


## 播放一个独立摸牌批次；本方法可被多个调用并行执行，每个批次只管理自己的卡牌与补间。
func _play_draw_transfer_batch(batch_id: int, draw_cards: Array[CardView], batch_start_position: Vector2, batch_target_position: Vector2) -> void:
	# 当前动画代次；重开清场后旧协程不再访问或启动新局的任何表现任务。
	var batch_generation: int = _presentation_generation
	# 同批飞行补间；所有牌的位置与缩放并行开始，绝不使用逐张延时。
	var flight_tween: Tween = create_tween().set_parallel(true)
	_draw_transfer_batch_tweens[batch_id] = flight_tween
	for card_index: int in range(draw_cards.size()):
		# 当前正式牌面；每张维持牌背、水平旋转与独立层级，避免同位置遮挡导致只看到一张。
		var draw_card: CardView = draw_cards[card_index]
		var draw_card_size: Vector2 = draw_card.get_card_size()
		# 当前牌相对整组中心的横向偏移；首尾绝对值相等，保证二张及以上时整体仍严格居中。
		var centered_offset_x: float = (float(card_index) - float(draw_cards.size() - 1) * 0.5) * draw_batch_card_spacing
		draw_card.position = batch_start_position - draw_card_size * 0.5
		draw_card.rotation = 0.0
		draw_card.scale = Vector2.ONE * 0.82
		draw_card.modulate = Color.WHITE
		draw_card.z_index = 90 + card_index
		draw_card.visible = true
		flight_tween.tween_property(draw_card, "position", batch_target_position + Vector2(centered_offset_x, 0.0) - draw_card_size * 0.5, card_flight_duration)
		flight_tween.tween_property(draw_card, "scale", Vector2.ONE * animated_card_scale, card_flight_duration)
	await flight_tween.finished
	if batch_generation != _presentation_generation:
		return
	# 同批停留补间；整组同时停留，确保玩家能辨认这是一次多张摸牌而不是多次独立摸牌。
	var hold_tween: Tween = create_tween()
	_draw_transfer_batch_tweens[batch_id] = hold_tween
	hold_tween.tween_interval(minf(card_hold_duration, 0.24))
	await hold_tween.finished
	if batch_generation != _presentation_generation:
		return
	# 同批淡出补间；其他批次可以同时飞行、停留或淡出，不因本批仍在展示而延迟。
	var fade_tween: Tween = create_tween().set_parallel(true)
	_draw_transfer_batch_tweens[batch_id] = fade_tween
	for draw_card: CardView in draw_cards:
		if draw_card != null and is_instance_valid(draw_card):
			fade_tween.tween_property(draw_card, "modulate:a", 0.0, target_line_fade_duration)
	await fade_tween.finished
	if batch_generation != _presentation_generation:
		return
	for draw_card: CardView in draw_cards:
		if draw_card == null or not is_instance_valid(draw_card):
			continue
		_transfer_cards.erase(draw_card.get_instance_id())
		draw_card.queue_free()
	_draw_transfer_batch_tweens.erase(batch_id)


## 从摸牌堆叠组移除已完成牌面的实例 ID；最后一张结束后删除空键，避免后续批次继承旧索引。
func _remove_draw_transfer_card(draw_stack_key: String, transfer_card_instance_id: int) -> void:
	if draw_stack_key.is_empty() or not _draw_transfer_stacks.has(draw_stack_key):
		return
	# 当前摸牌堆叠实例 ID 数组；只移除表现索引，不修改玩家手牌或牌堆。
	var draw_stack: Array = _draw_transfer_stacks[draw_stack_key] as Array
	draw_stack.erase(transfer_card_instance_id)
	if draw_stack.is_empty():
		_draw_transfer_stacks.erase(draw_stack_key)
	else:
		_draw_transfer_stacks[draw_stack_key] = draw_stack


## 返回指定实体 UID 是否已经由使用牌队列接管；区域移动层据此避免同一牌重复实例化到目标处。
func has_active_card_uid(card_uid: int) -> bool:
	for active_card: CardView in _active_cards:
		if active_card != null and is_instance_valid(active_card) and active_card.card_uid == card_uid:
			return true
	return false


## 消费一次由使用或判定表现接管的真实弃牌移动；返回true时调用方不得再创建第二张转移牌。
func consume_discard_transfer_claim(card_uid: int) -> bool:
	if _discard_transfer_claims.has(card_uid):
		_discard_transfer_claims.erase(card_uid)
		_consumed_discard_transfer_claims[card_uid] = true
		_finish_claimed_card_presentation(card_uid)
		return true
	# 已消费状态保留到实体进入新区域；同一真实移动被重复转发时仍保持幂等，不重新生成中央牌面。
	return _consumed_discard_transfer_claims.has(card_uid)


## 登记一次没有预先表现认领的普通弃牌增量；返回true表示该 UID 已经有中央表现，调用方不得再次创建牌面。
## 首次普通弃牌会记录 UID 但返回false，允许调用方创建唯一动画；实体进入非弃牌区域后由 release_consumed_discard_claim 清理记录。
func register_discard_transfer(card_uid: int) -> bool:
	if card_uid < 0:
		return false
	if consume_discard_transfer_claim(card_uid):
		return true
	_consumed_discard_transfer_claims[card_uid] = true
	return false


## 释放指定 UID 的待消费与已消费所有权；实体进入新区域后，旧使用生命周期不能拦截未来合法表现或弃置。
## 若该 UID 仍有等待规则完成的中央牌面，本入口会先启动正常停留与淡出，再清理普通弃牌幂等记录。
func release_consumed_discard_claim(card_uid: int) -> void:
	_finish_claimed_card_presentation(card_uid)
	_discard_transfer_claims.erase(card_uid)
	_consumed_discard_transfer_claims.erase(card_uid)


## 对局结束或规则中断时结束全部仍等待最终区域的中央牌面；只启动表现收尾，不伪造实体移牌或消费所有权。
func finish_pending_claimed_presentations() -> void:
	# 当前仍等待规则完成的实体 UID 副本；遍历副本允许收尾函数安全删除原映射。
	var pending_card_uids: Array = _discard_claim_card_instance_ids.keys().duplicate()
	for card_uid_variant: Variant in pending_card_uids:
		_finish_claimed_card_presentation(int(card_uid_variant))


## 使用权威处理区 UID 快照核对中央牌面；已不在处理区却缺少最终移牌通知的认领牌会立即进入正常收尾。
func reconcile_processing_card_uids(processing_card_uids: Array[int]) -> void:
	# 当前仍由处理区生命周期持有的实体 UID 副本；收尾函数会修改原映射，因此不能直接遍历键视图。
	var claimed_card_uids: Array = _discard_claim_card_instance_ids.keys().duplicate()
	for card_uid_variant: Variant in claimed_card_uids:
		# 当前认领实体 UID；只有权威快照已经确认离开处理区时才执行防御性收尾。
		var card_uid: int = int(card_uid_variant)
		if not processing_card_uids.has(card_uid):
			_finish_claimed_card_presentation(card_uid)


## 立即清空全部飞牌、弃牌队列和目标线；重新开局时调用，避免上一局异步表现残留到新桌面。
func clear_presentations() -> void:
	_presentation_generation += 1
	for motion_tween_variant: Variant in _motion_tweens.values():
		# 当前仍存活的移动补间；清场时主动终止，避免继续访问已经排队释放的牌面节点。
		var motion_tween: Tween = motion_tween_variant as Tween
		if motion_tween != null and motion_tween.is_valid():
			motion_tween.kill()
	for lifecycle_tween_variant: Variant in _card_lifecycle_tweens.values():
		# 当前仍存活的牌面生命周期补间；清场时终止，防止旧牌在新局继续进入淡出队列。
		var lifecycle_tween: Tween = lifecycle_tween_variant as Tween
		if lifecycle_tween != null and lifecycle_tween.is_valid():
			lifecycle_tween.kill()
	# 当前全部并行摸牌批次补间；停止后旧局各批次均不会再访问或改写新桌面节点。
	for draw_batch_tween_variant: Variant in _draw_transfer_batch_tweens.values():
		# 当前批次补间；飞行、停留或淡出阶段都必须被主动终止。
		var draw_batch_tween: Tween = draw_batch_tween_variant as Tween
		if draw_batch_tween != null and draw_batch_tween.is_valid():
			draw_batch_tween.kill()
	for active_card: CardView in _active_cards:
		if active_card != null and is_instance_valid(active_card):
			active_card.queue_free()
	for transfer_card_variant: Variant in _transfer_cards.values():
		if not is_instance_valid(transfer_card_variant):
			continue
		# 当前仍存活的区域转移牌面；立即隐藏，待其旧补间完成并通过代次分支安全释放。
		var transfer_card: CardView = transfer_card_variant as CardView
		if transfer_card != null:
			transfer_card.visible = false
	_active_cards.clear()
	_transfer_cards.clear()
	_draw_transfer_stacks.clear()
	_transfer_tweens.clear()
	_draw_transfer_batch_tweens.clear()
	_draw_transfer_batch_sequence = 0
	_fade_queue.clear()
	_motion_tweens.clear()
	_card_lifecycle_tweens.clear()
	_discard_claim_card_instance_ids.clear()
	_card_presentation_started_msec.clear()
	_discard_transfer_claims.clear()
	_consumed_discard_transfer_claims.clear()
	_seen_presentation_ids.clear()
	_card_sequences.clear()
	_line_presentations.clear()
	_animated_card = null
	_is_fade_worker_running = false
	_is_fade_worker_scheduled = false
	queue_redraw()


## 为指定中央牌面安排延迟淡出；旧生命周期存在时先终止，保证每张牌始终只有一个收尾计时入口。
func _schedule_card_fade(card_instance_id: int, delay_seconds: float) -> void:
	# 当前牌面已有的生命周期补间；重复完成通知不得并行创建多个淡出回调。
	var previous_lifecycle_tween: Tween = _card_lifecycle_tweens.get(card_instance_id) as Tween
	if previous_lifecycle_tween != null and previous_lifecycle_tween.is_valid():
		previous_lifecycle_tween.kill()
	# 当前牌面新的生命周期补间；延迟时间包含尚未完成的飞行和规则完成后的完整停留时间。
	var lifecycle_tween: Tween = create_tween()
	lifecycle_tween.tween_interval(maxf(delay_seconds, 0.0))
	lifecycle_tween.tween_callback(_queue_card_for_fade.bind(card_instance_id, _presentation_generation))
	_card_lifecycle_tweens[card_instance_id] = lifecycle_tween


## 结束一张由最终区域移动接管的中央牌面；响应期间持续保留，响应结束后补足飞行并完整停留再淡出。
func _finish_claimed_card_presentation(card_uid: int) -> void:
	if not _discard_claim_card_instance_ids.has(card_uid):
		return
	# 当前实体对应的中央牌面实例 ID；映射先删除，重复移动或中断通知不会重新安排生命周期。
	var card_instance_id: int = int(_discard_claim_card_instance_ids.get(card_uid, -1))
	_discard_claim_card_instance_ids.erase(card_uid)
	if card_instance_id < 0:
		return
	# 当前牌面开始表现的毫秒时间；缺失时按刚刚开始处理，仍保证完整飞行与停留时长。
	var started_msec: int = int(_card_presentation_started_msec.get(card_instance_id, Time.get_ticks_msec()))
	# 当前牌面已经显示的秒数；响应等待时间会自然计入，不会在规则完成后重复等待已经完成的飞行部分。
	var elapsed_seconds: float = maxf(float(Time.get_ticks_msec() - started_msec) / MILLISECONDS_PER_SECOND, 0.0)
	# 当前仍需等待的时间；未完成飞行的部分加上规则完成后的完整停留时间，之后才进入统一批次淡出。
	var remaining_seconds: float = maxf(card_flight_duration - elapsed_seconds, 0.0) + card_hold_duration
	_schedule_card_fade(card_instance_id, remaining_seconds)


## 在单一生命周期补间结束后把仍有效的牌加入淡出队列；动画代次不一致时直接丢弃旧回调。
func _queue_card_for_fade(card_instance_id: int, presentation_generation: int) -> void:
	_card_lifecycle_tweens.erase(card_instance_id)
	if presentation_generation != _presentation_generation:
		return
	# 当前待淡出的正式牌面；实例已释放、已被清场或已提前移出活动队列时不再安排收尾。
	var presented_card: CardView = instance_from_id(card_instance_id) as CardView
	if presented_card == null or not is_instance_valid(presented_card) or not _active_cards.has(presented_card):
		return
	_fade_queue.append(presented_card)
	_schedule_fade_drain()


## 顺序淡出所有已经完成停留的卡牌；队列只运行一个消费者，保证多张牌逐个消失。
## 当前消费者仍保持单一顺序入口，但把同一帧完成停留的牌合并为完整批次同时淡出。
func _schedule_fade_drain() -> void:
	if _is_fade_worker_running or _is_fade_worker_scheduled:
		return
	_is_fade_worker_scheduled = true
	call_deferred("_drain_fade_queue")


## 按批次淡出已经完成停留的卡牌；同一帧入队的牌保持顺序并同时完整显示、同时收尾。
func _drain_fade_queue() -> void:
	_is_fade_worker_scheduled = false
	if _is_fade_worker_running:
		return
	if _fade_queue.is_empty():
		return
	_is_fade_worker_running = true
	# 当前淡出任务代次；重新开局会递增全局代次，使本任务在下次等待结束后立即退出。
	var worker_generation: int = _presentation_generation
	while not _fade_queue.is_empty():
		# 当前待淡出的完整批次；消费者启动前进入队列的卡牌按原顺序一次性复制并清空等待队列。
		var fade_batch: Array[CardView] = []
		fade_batch.assign(_fade_queue.duplicate())
		_fade_queue.clear()
		# 当前淡出卡牌的表现序号；用于把该牌对应的目标线与牌面同时淡出并清理。
		# 当前兼容动画牌引用；指向批次首牌，仅供现有调试与清场状态观察。
		_animated_card = fade_batch[0] if not fade_batch.is_empty() else null
		# 收尾补间；正式卡牌保持水平并淡出消失，目标指示线通常已在延伸后独立完成渐隐。
		# 收尾补间；批次内所有正式牌保持水平并同时淡出，任何新入队牌留给下一轮批次。
		var fade_tween: Tween = create_tween().set_parallel(true)
		# 当前批次是否包含至少一张仍有效的动画牌；空批次无需等待无内容补间。
		var has_valid_batch_card: bool = false
		for fade_card: CardView in fade_batch:
			if fade_card == null or not is_instance_valid(fade_card) or not _active_cards.has(fade_card):
				continue
			has_valid_batch_card = true
			fade_tween.tween_property(fade_card, "modulate:a", 0.0, target_line_fade_duration)
			# 当前淡出卡牌的表现序号；用于把仍未结束的目标线与牌面同时淡出并清理。
			var sequence: int = int(_card_sequences.get(fade_card.get_instance_id(), -1))
			if sequence >= 0 and _line_presentations.has(sequence):
				# 当前目标线透明度；防御性收尾仅处理尚未完成独立渐隐的异常或极短飞牌配置。
				var current_line_alpha: float = float((_line_presentations[sequence] as Dictionary).get("alpha", 1.0))
				fade_tween.tween_method(_set_line_alpha.bind(sequence), current_line_alpha, 0.0, target_line_fade_duration)
		if not has_valid_batch_card:
			fade_tween.kill()
			continue
		await fade_tween.finished
		if worker_generation != _presentation_generation:
			return
		for fade_card: CardView in fade_batch:
			if fade_card == null or not is_instance_valid(fade_card):
				continue
			# 当前完成淡出的表现序号；批量移除前先清理对应目标线索引。
			var sequence: int = int(_card_sequences.get(fade_card.get_instance_id(), -1))
			if sequence >= 0:
				_line_presentations.erase(sequence)
			_remove_presented_card(fade_card)
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
		_remove_presented_card(_animated_card)
	_animated_card = null


## 从中央展示队列移除指定正式牌面，并同步清理移动补间与表现序号索引。
func _remove_presented_card(card_view: CardView) -> void:
	if card_view == null or not is_instance_valid(card_view):
		return
	# 当前淡出卡牌实例 ID；作为全部动画索引的稳定清理键。
	var card_instance_id: int = card_view.get_instance_id()
	# 当前牌面生命周期补间；提前移除牌面时一并终止，防止完成回调重新把失效节点加入淡出队列。
	var lifecycle_tween: Tween = _card_lifecycle_tweens.get(card_instance_id) as Tween
	if lifecycle_tween != null and lifecycle_tween.is_valid():
		lifecycle_tween.kill()
	_active_cards.erase(card_view)
	_motion_tweens.erase(card_instance_id)
	_card_lifecycle_tweens.erase(card_instance_id)
	_card_presentation_started_msec.erase(card_instance_id)
	_discard_claim_card_instance_ids.erase(card_view.card_uid)
	_card_sequences.erase(card_instance_id)
	card_view.queue_free()
