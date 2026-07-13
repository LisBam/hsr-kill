class_name CardUseAnimationLayer
extends Control

## 卡牌使用表现层。该组件只播放飞牌与目标指示线，不读取或修改任何权威对局状态。

## 飞牌动画持续时间；默认0.42秒兼顾动作辨识与对局节奏，可在检查器中运行前调整。
@export_range(0.1, 1.5, 0.01) var card_flight_duration: float = 0.42

## 卡牌抵达弃牌区后的停留时间；默认0.48秒用于让玩家辨认牌名，可在运行时动态调整。
@export_range(0.0, 2.0, 0.01) var card_hold_duration: float = 0.48

## 目标指示线淡出时间；默认0.36秒，使指向关系在卡牌抵达后平滑消失。
@export_range(0.1, 1.5, 0.01) var target_line_fade_duration: float = 0.36

## 飞行卡牌的显示尺寸；默认82×112像素，保证在1280×720牌桌上清晰且不遮挡目标区。
@export var flying_card_size: Vector2 = Vector2(82.0, 112.0)

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

## 当前飞牌节点；新动画开始时旧节点会先安全移除，避免快速出牌产生残留。
var _flying_card: PanelContainer

## 当前表现序号；每次播放递增，使旧异步动画不能清除较新的表现节点。
var _presentation_sequence: int = 0


## 播放一次卡牌使用表现；所有位置均使用本组件局部坐标，牌名由调用方按当前名称模式解析。
func play_card(card_name: String, card_suit: String, card_rank: int, start_position: Vector2, discard_position: Vector2, target_positions: Array[Vector2]) -> void:
	_presentation_sequence += 1
	# 本次表现序号；异步等待结束后用于确认当前动画仍是最新一次。
	var sequence: int = _presentation_sequence
	_remove_flying_card()
	_line_start = start_position
	_line_targets = target_positions.duplicate()
	_line_alpha = 1.0 if not _line_targets.is_empty() else 0.0
	queue_redraw()
	_flying_card = _create_flying_card(card_name, card_suit, card_rank)
	add_child(_flying_card)
	_flying_card.position = start_position - flying_card_size * 0.5
	_flying_card.modulate = Color(1.0, 1.0, 1.0, 0.86)
	_flying_card.scale = Vector2(0.82, 0.82)
	_flying_card.pivot_offset = flying_card_size * 0.5
	# 飞牌补间；位置、缩放、透明度和轻微旋转共同形成从角色区域打向桌面的动作感。
	var flight_tween: Tween = create_tween().set_parallel(true)
	flight_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flight_tween.tween_property(_flying_card, "position", discard_position - flying_card_size * 0.5, card_flight_duration)
	flight_tween.tween_property(_flying_card, "scale", Vector2.ONE, card_flight_duration)
	flight_tween.tween_property(_flying_card, "rotation", deg_to_rad(3.0), card_flight_duration)
	flight_tween.tween_property(_flying_card, "modulate", Color.WHITE, card_flight_duration)
	await flight_tween.finished
	if sequence != _presentation_sequence:
		return
	await get_tree().create_timer(card_hold_duration).timeout
	if sequence != _presentation_sequence:
		return
	# 收尾补间；卡牌淡入弃牌堆，目标线同时消隐。
	var fade_tween: Tween = create_tween().set_parallel(true)
	fade_tween.tween_property(self, "_line_alpha", 0.0, target_line_fade_duration)
	if _flying_card != null:
		fade_tween.tween_property(_flying_card, "modulate:a", 0.0, target_line_fade_duration)
	await fade_tween.finished
	if sequence == _presentation_sequence:
		_remove_flying_card()
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


## 创建轻量飞牌视图；只展示花色点数与牌名，避免复制可交互手牌组件。
func _create_flying_card(card_name: String, card_suit: String, card_rank: int) -> PanelContainer:
	# 飞牌根面板；鼠标穿透保证动画不会阻挡玩家操作。
	var card_panel: PanelContainer = PanelContainer.new()
	card_panel.custom_minimum_size = flying_card_size
	card_panel.size = flying_card_size
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(Color("e8dfcc"), Color("d6a84f"), 3, 10))
	# 飞牌文字；使用统一名称模式解析后的牌名和紧凑花色点数信息。
	var card_label: Label = Label.new()
	card_label.text = "%s %s\n\n%s" % [_suit_symbol(card_suit), _rank_text(card_rank), card_name]
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.add_theme_color_override("font_color", Color("2a211b"))
	card_label.add_theme_font_size_override("font_size", 15)
	card_panel.add_child(card_label)
	return card_panel


## 移除当前飞牌节点；仅处理本组件创建的临时表现对象。
func _remove_flying_card() -> void:
	if _flying_card != null and is_instance_valid(_flying_card):
		_flying_card.queue_free()
	_flying_card = null


## 将花色 ID 转换为飞牌左上角使用的符号；无花色虚拟牌显示为空心星标。
func _suit_symbol(suit: String) -> String:
	return {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦", "none":"◇"}.get(suit, "◇")


## 将点数转换为牌面字符；无点数虚拟牌不显示数字。
func _rank_text(rank: int) -> String:
	if rank <= 0:
		return ""
	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))
