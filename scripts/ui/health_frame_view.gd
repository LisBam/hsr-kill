class_name HealthFrameView
extends Control

## 武将牌体力显示的独立梯形边框组件。组件只负责外观与几何，不读取对局状态，体力内容由 PlayerTargetView 写入。

## 梯形不透明背景色；默认使用深墨绿色，与绿色体力圆点保持同一视觉体系，运行时通常无需动态修改。
@export var background_color: Color = Color("17251d")

## 梯形边框颜色；默认使用暗金色连接武将牌外框，运行时通常无需动态修改。
@export var border_color: Color = Color("c69f4f")

## 梯形边框宽度；默认1.5像素兼顾小尺寸清晰度与武将牌边框融合，运行时通常无需动态修改。
@export_range(1.0, 4.0, 0.5) var border_width: float = 1.5

## 顶边斜角的垂直落差；默认5像素形成清晰斜边且不挤压内部体力内容，运行时通常无需动态修改。
@export_range(2.0, 12.0, 1.0) var top_slope_height: float = 5.0


## 当控件尺寸变化时重绘梯形，保证体力上限改变高度后边框仍完整贴合。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## 绘制仅顶边倾斜、左右与底边保持直线的体力框。
func _draw() -> void:
	# 当前有效宽度；至少保留1像素，避免初始化零尺寸时生成无效多边形。
	var frame_width: float = maxf(size.x, 1.0)
	# 当前有效高度；动态高度由武将牌视图按体力上限写入。
	var frame_height: float = maxf(size.y, 1.0)
	# 当前斜边落差；限制在控件高度一半以内，极小体力框仍不会发生边线交叉。
	var safe_slope_height: float = minf(top_slope_height, frame_height * 0.5)
	# 梯形顶点；顶部从左上向右下倾斜，其余外边保持水平或垂直。
	var points: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(frame_width, safe_slope_height), Vector2(frame_width, frame_height), Vector2(0.0, frame_height)])
	draw_colored_polygon(points, background_color)
	# 闭合边框折线；抗锯齿用于减少小尺寸斜边的锯齿感。
	var outline_points: PackedVector2Array = points.duplicate()
	outline_points.append(points[0])
	draw_polyline(outline_points, border_color, border_width, true)
