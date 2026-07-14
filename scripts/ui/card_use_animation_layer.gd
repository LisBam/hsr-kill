class_name CardUseAnimationLayer
extends Control

## 卡牌使用表现层。该组件接管正式 CardView 节点播放飞牌与目标指示线，不创建任何替代牌模型或修改权威状态。

## 飞牌动画持续时间；默认0.42秒兼顾动作辨识与对局节奏，可在检查器中运行前调整。
@export_range(0.1, 1.5, 0.01) var card_flight_duration: float = 0.42

## 卡牌抵达弃牌区后的停留时间；默认0.48秒用于让玩家辨认牌面，可在运行时动态调整。
@export_range(0.0, 2.0, 0.01) var card_hold_duration: float = 0.48

## 目标指示线淡出时间；默认0.36秒，使指向关系在卡牌抵达后平滑消失。
@export_range(0.1, 1.5, 0.01) var target_line_fade_duration: float = 0.36

## 动画牌面目标缩放倍率；默认1.0保持正式108×148实体牌模型和比例不变，运行时通常无需修改。
@export_range(0.5, 1.5, 0.01) var animated_card_scale: float = 1.0

## 目标指示线宽度；默认4像素，在深色桌面背景上保持清晰。
@export_range(1.0, 12.0, 0.5) var target_line_width: float = 4.0

## 目标指示线颜色；金色与当前牌桌选中反馈一致，仅影响视觉表现。
@export var target_line_color: Color = Color("e4bd67")

## 当前指示线起点；使用本组件局部坐标，由牌桌根据使用者视图中心传入。
var _line_start: Vector2 = Vector2.ZERO

## 当前指示线终点数组；多目标牌会同时绘制多根线。
var _line_targets: Array[Vector2] = []

## 当前指示线透明度；动画期间从1渐变到0。
var _line_alpha: float = 0.0:
	set(value):
		_line_alpha = value
		queue_redraw()

## 当前被动画层接管的正式卡牌节点；可能来自手牌，也可能是不可见牌的完整正式视图。
var _animated_card: CardView

## 当前表现序号；每次播放递增，使旧异步动画不能清除较新的表现节点。
var _presentation_sequence: int = 0


## 播放一次卡牌使用表现；传入节点始终是正式 CardView，所有位置使用本组件局部坐标。
func play_card(card_view: CardView, start_position: Vector2, discard_position: Vector2, target_positions: Array[Vector2]) -> void:
	if card_view == null:
		return
	_presentation_sequence += 1
	# 本次表现序号；异步等待结束后用于确认当前动画仍是最新一次。
	var sequence: int = _presentation_sequence
	_remove_animated_card()
	_line_start = start_position
	_line_targets = target_positions.duplicate()
	_line_alpha = 1.0 if not _line_targets.is_empty() else 0.0
	queue_redraw()
	_animated_card = card_view
	# 原卡牌的全局变换；重新挂载到动画层后恢复该变换，保证动画从屏幕中原位置连续开始。
	var original_global_transform: Transform2D = _animated_card.global_transform
	if _animated_card.get_parent() != self:
		_animated_card.reparent(self)
	_animated_card.global_transform = original_global_transform
	_animated_card.set_selected_state(false)
	# 清除选中状态可能恢复普通容器纵坐标，因此再次恢复接管前变换，保证飞牌起点连续。
	_animated_card.global_transform = original_global_transform
	_animated_card.z_index = 1
	_animated_card.modulate = Color(1.0, 1.0, 1.0, 0.9)
	# 卡牌模型中心；正式牌面尺寸保持不变，只用统一中心点计算弃牌落点。
	var card_center_offset: Vector2 = _animated_card.get_card_size() * 0.5
	# 飞牌补间；位置、缩放、透明度和轻微旋转共同形成从角色区域打向桌面的动作感。
	var flight_tween: Tween = create_tween().set_parallel(true)
	flight_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flight_tween.tween_property(_animated_card, "position", discard_position - card_center_offset, card_flight_duration)
	flight_tween.tween_property(_animated_card, "scale", Vector2.ONE * animated_card_scale, card_flight_duration)
	flight_tween.tween_property(_animated_card, "rotation", deg_to_rad(3.0), card_flight_duration)
	flight_tween.tween_property(_animated_card, "modulate", Color.WHITE, card_flight_duration)
	await flight_tween.finished
	if sequence != _presentation_sequence:
		return
	await get_tree().create_timer(card_hold_duration).timeout
	if sequence != _presentation_sequence:
		return
	# 收尾补间；正式卡牌淡入弃牌堆，目标线同时消隐。
	var fade_tween: Tween = create_tween().set_parallel(true)
	fade_tween.tween_property(self, "_line_alpha", 0.0, target_line_fade_duration)
	if _animated_card != null:
		fade_tween.tween_property(_animated_card, "modulate:a", 0.0, target_line_fade_duration)
	await fade_tween.finished
	if sequence == _presentation_sequence:
		_remove_animated_card()
		_line_targets.clear()
		queue_redraw()


## 绘制带端点光晕的目标指示线；多目标牌从同一使用者位置分别指向每名目标。
func _draw() -> void:
	if _line_alpha <= 0.0:
		return
	# 当前线条颜色；透明度由补间统一控制。
	var line_color: Color = Color(target_line_color, target_line_color.a * _line_alpha)
	for target_position: Vector2 in _line_targets:
		draw_line(_line_start, target_position, line_color, target_line_width, true)
		draw_circle(target_position, target_line_width * 1.8, line_color)


## 释放当前动画牌节点；它已离开权威手牌快照，动画完成后不应回到手牌容器。
func _remove_animated_card() -> void:
	if _animated_card != null and is_instance_valid(_animated_card):
		_animated_card.queue_free()
	_animated_card = null
