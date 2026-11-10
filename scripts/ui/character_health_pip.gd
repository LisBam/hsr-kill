extends Control

## 体力圆点的纯绘制饰面；父Label保留原有文字、字号、颜色与排版，仅隐藏其自身字形。
## 本组件继承父级调制色但不受父级self_modulate影响，因此非法目标、离场和阵亡表现仍统一生效。

## 圆点半径；默认3.8像素接近原18像素字号的实心圆字形，不改变VBox的布局步长，可运行时调整。
@export_range(2.0, 6.0, 0.1) var pip_radius: float = 3.8
## 外圈厚度；默认0.8像素形成玻璃珠边缘，空体力保留相同圆槽，可运行时调整。
@export_range(0.0, 2.0, 0.1) var bezel_width: float = 0.8
## 珠面亮点半径；默认0.7像素，避免高光覆盖红黄绿残血语义，可运行时调整。
@export_range(0.0, 1.5, 0.1) var highlight_radius: float = 0.7
## 珠体投影的下移与透明度；默认0.6像素和0.65，只提供体积感。
const SHADOW_STYLE: Vector2 = Vector2(0.6, 0.65)
## 实心边缘与空槽内芯的压暗比例；默认0.46和0.45保留体力语义色。
const BEZEL_DARKENING: Vector2 = Vector2(0.46, 0.45)
## 空槽外环提亮比例；默认0.10让失去体力的占位在深色槽中可辨。
const EMPTY_EDGE_LIGHTENING: float = 0.10
## 珠面弧光起止角相对PI的比例；默认1.08至1.88位于左上方。
const GLINT_ARC: Vector2 = Vector2(1.08, 1.88)
## 弧光的采样点数；默认12兼顾微型圆弧平滑度与绘制成本。
const GLINT_SEGMENTS: int = 12
## 弧光的提亮比例与透明度；默认0.48和0.65，不把彩色珠体洗成白色。
const GLINT_STYLE: Vector2 = Vector2(0.48, 0.65)
## 弧光线宽；默认0.8像素，与外圈形成细小高光。
const GLINT_WIDTH: float = 0.8
## 亮点相对半径的偏移；默认向左0.27、向上0.32，与弧光共用光源。
const HIGHLIGHT_OFFSET: Vector2 = Vector2(-0.27, -0.32)
## 亮点的提亮比例与透明度；默认0.72和0.82，受导出半径控制覆盖面积。
const HIGHLIGHT_STYLE: Vector2 = Vector2(0.72, 0.82)
## 调用方解析后的体力或护盾颜色；组件不判断体力阈值和护盾来源。
var _tint: Color = Color.WHITE
## 当前圆槽是否点亮；false只绘制暗槽，保留明确的体力上限占位。
var _filled: bool = true


## 挂到原Label下面并覆盖其矩形；只接收数据，不生成额外布局行或输入节点。
static func attach(label: Label, tint: Color, filled: bool = true) -> void:
	# 圆点装饰实例；父Label被释放时自动回收，无共享状态。
	var finish: Control = load("res://scripts/ui/character_health_pip.gd").new()
	finish.name = "PipFinish"
	finish.set("_tint", tint)
	finish.set("_filled", filled)
	label.add_child(finish)
	label.self_modulate.a = 0.0


## 透传所有鼠标与焦点；尺寸跟随原字形Label，不改变任何体力布局契约。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


## 已损失体力使用凹槽，当前体力和护盾使用同色玻璃珠；只在创建和尺寸变化时绘制。
func _draw() -> void:
	# 圆点中心；VBox仍按原字体高度布局，本组件只使用分配后的实际矩形。
	var center: Vector2 = size * 0.5
	draw_circle(center + Vector2(0.0, SHADOW_STYLE.x), pip_radius + bezel_width, Color(0.0, 0.0, 0.0, SHADOW_STYLE.y), true, -1.0, true)
	draw_circle(center, pip_radius, _tint.darkened(BEZEL_DARKENING.x) if _filled else _tint.lightened(EMPTY_EDGE_LIGHTENING), true, -1.0, true)
	draw_circle(center, maxf(pip_radius - bezel_width, 0.5), _tint if _filled else _tint.darkened(BEZEL_DARKENING.y), true, -1.0, true)
	if _filled:
		draw_arc(center, pip_radius - bezel_width, PI * GLINT_ARC.x, PI * GLINT_ARC.y, GLINT_SEGMENTS, Color(_tint.lightened(GLINT_STYLE.x), GLINT_STYLE.y), GLINT_WIDTH, true)
		draw_circle(center + HIGHLIGHT_OFFSET * pip_radius, highlight_radius, Color(_tint.lightened(HIGHLIGHT_STYLE.x), HIGHLIGHT_STYLE.y), true, -1.0, true)
