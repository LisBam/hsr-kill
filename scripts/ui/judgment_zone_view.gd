class_name JudgmentZoneView
extends Control

## 武将牌底边上的判定区标记组件。组件只渲染调用方传入的牌名，不读取玩家状态或卡牌实体。

## 单个判定标记占用的正方形尺寸；默认22像素让菱形中心恰好落在武将牌底线上，运行时通常无需动态修改。
@export_range(14.0, 32.0, 1.0) var marker_size: float = 22.0

## 第一张判定牌距离武将牌左边缘的距离；默认28像素避让左下角手牌数，运行时可由牌面主题调整。
@export_range(0.0, 80.0, 1.0) var first_marker_left_margin: float = 28.0

## 相邻判定菱形边缘之间的距离；默认6像素保证多张判定牌从左到右清晰分隔，运行时可由牌面主题调整。
@export_range(0.0, 24.0, 1.0) var marker_gap: float = 6.0

## 判定牌首字的字体尺寸；默认12像素适配22像素菱形，运行时通常无需动态修改。
@export_range(8, 20, 1) var marker_font_size: int = 12

## 判定菱形的底色；默认使用暖黑色维持牌桌高对比度，仅影响表现。
@export var marker_background_color: Color = Color("2d2924f2")

## 判定菱形的边框颜色；默认使用亮金色标识公开判定牌，仅影响表现。
@export var marker_border_color: Color = Color("d4aa54")

## 判定牌首字颜色；默认使用浅金色保证深色菱形上的可读性，仅影响表现。
@export var marker_text_color: Color = Color("fff0c8")

## 当前按判定顺序显示的牌名副本；数组顺序决定标记从左到右的排列顺序。
var _card_names: Array[String] = []


## 初始化透明输入和编辑器预览；组件不会遮断武将牌底部的目标点击。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_markers()


## 写入按结算顺序排列的判定牌显示名，并重建全部菱形标记。
func configure(card_names: Array[String]) -> void:
	_card_names = card_names.duplicate()
	_refresh_markers()


## 清理旧标记并按固定左边距与间距从左到右创建新的菱形和首字标签。
func _refresh_markers() -> void:
	if not is_node_ready():
		return
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for card_index: int in range(_card_names.size()):
		# 当前标记的左上角横坐标；牌名数组顺序直接对应从左到右的公开判定顺序。
		var marker_x: float = first_marker_left_margin + float(card_index) * (marker_size + marker_gap)
		# 当前菱形背景；正方形绕中心旋转45度后形成不会随文字长度变化的稳定标记。
		var diamond_panel: Panel = Panel.new()
		# 构成目标菱形的正方形边长；除以根号二后，旋转包围盒恰好等于 marker_size。
		var diamond_side: float = marker_size / sqrt(2.0)
		diamond_panel.position = Vector2(marker_x + (marker_size - diamond_side) * 0.5, (marker_size - diamond_side) * 0.5)
		diamond_panel.size = Vector2.ONE * diamond_side
		diamond_panel.pivot_offset = diamond_panel.size * 0.5
		diamond_panel.rotation = PI * 0.25
		diamond_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 当前菱形样式；内边距清零，避免旋转后的外框尺寸被主题默认值扩大。
		var diamond_style: StyleBoxFlat = BattleUIStyle.make_panel(marker_background_color, marker_border_color, 1, 1)
		diamond_style.content_margin_left = 0.0
		diamond_style.content_margin_top = 0.0
		diamond_style.content_margin_right = 0.0
		diamond_style.content_margin_bottom = 0.0
		diamond_panel.add_theme_stylebox_override("panel", diamond_style)
		add_child(diamond_panel)
		# 当前判定牌首字标签；文字保持水平，不随背景菱形旋转。
		var initial_label: Label = Label.new()
		initial_label.position = Vector2(marker_x, 0.0)
		initial_label.size = Vector2.ONE * marker_size
		initial_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		initial_label.text = _first_character(_card_names[card_index])
		initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial_label.add_theme_font_size_override("font_size", marker_font_size)
		initial_label.add_theme_color_override("font_color", marker_text_color)
		initial_label.add_theme_color_override("font_shadow_color", Color("120e0b"))
		initial_label.add_theme_constant_override("shadow_offset_x", 1)
		initial_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(initial_label)
	visible = not _card_names.is_empty()


## 返回牌名的首个字符；空名称使用问号，确保异常配置仍保留稳定标记尺寸。
func _first_character(card_name: String) -> String:
	if card_name.is_empty():
		return "?"
	return card_name.substr(0, 1)
