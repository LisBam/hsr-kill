class_name PlayerStateOverlay
extends Control

## 武将牌阵亡与横置状态覆盖组件。组件只消费布尔状态并绘制表现，不参与伤害、死亡或连环规则。

## 覆盖层固定尺寸；默认与148.35×197.8像素武将牌一致，运行时通常无需动态修改。
@export var card_size: Vector2 = Vector2(148.35, 197.8)

## 横置链条距离武将牌左右边缘的留白；默认7像素让链条完整穿过牌面中心且不越出边框。
@export_range(0.0, 24.0, 1.0) var chain_horizontal_margin: float = 7.0

## 单个链环的水平尺寸；默认22像素可在标准武将牌上连续显示多个完整链环。
@export_range(12.0, 36.0, 1.0) var chain_link_width: float = 22.0

## 单个链环的垂直尺寸；默认10像素形成窄长灰色链条，不遮挡过多武将插画。
@export_range(6.0, 20.0, 1.0) var chain_link_height: float = 10.0

## 相邻链环中心的水平步长；默认16像素使链环彼此咬合，运行时通常无需动态修改。
@export_range(8.0, 30.0, 1.0) var chain_link_step: float = 16.0

## 链环描边宽度；默认2.5像素保证缩放后仍清晰，仅影响表现。
@export_range(1.0, 6.0, 0.5) var chain_line_width: float = 2.5

## 横置中空横线的高度；默认10像素形成清晰的灰色空心长条，运行时只改变牌面状态表现。
@export_range(4.0, 24.0, 1.0) var chained_hollow_line_height: float = 10.0

## 链条颜色；默认中性灰色区别于金色目标和红色阵亡提示，仅影响表现。
@export var chain_color: Color = Color("aaa9a6e8")

## 当前角色是否阵亡；为 true 时显示黑白滤镜与红色阵亡文字并停止绘制链条。
var _is_dead: bool = false

## 当前角色是否横置；仅存活且该值为 true 时绘制穿过牌面中心的链条。
var _is_chained: bool = false

## 阵亡滤镜所需的屏幕拷贝节点；只复制当前武将牌矩形，不影响桌面其他区域。
@onready var _death_back_buffer: BackBufferCopy = $DeathBackBuffer

## 阵亡黑白滤镜层；着色器读取当前武将牌画面并转换为灰度。
@onready var _death_filter: ColorRect = $DeathFilter

## 阵亡文字标签；固定在武将牌中心并使用红色高对比字体。
@onready var _death_label: Label = $DeathLabel


## 初始化覆盖层几何与透明输入，确保状态表现不会遮断底层目标选择。
func _ready() -> void:
	size = card_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_back_buffer.rect = Rect2(Vector2.ZERO, card_size)
	_death_filter.size = card_size
	_death_label.size = card_size
	_refresh_state()


## 写入公开存活与横置状态；死亡表现优先于横置链条。
func configure(alive: bool, chained: bool) -> void:
	_is_dead = not alive
	_is_chained = chained
	_refresh_state()


## 同步阵亡子节点显隐并请求重绘横置链条。
func _refresh_state() -> void:
	if not is_node_ready():
		return
	_death_back_buffer.visible = _is_dead
	_death_filter.visible = _is_dead
	_death_label.visible = _is_dead
	queue_redraw()


## 在存活横置角色的武将牌中心绘制贯穿牌面的灰色中空横线。
func _draw() -> void:
	if _is_dead or not _is_chained:
		return
	# 中空横线可用宽度；扣除左右留白后始终贯穿武将牌主体且不会越过边框。
	var hollow_line_width: float = maxf(card_size.x - chain_horizontal_margin * 2.0, 1.0)
	# 中空横线矩形；严格以武将牌垂直中心定位，形成“铁索”贯穿牌面的明确状态提示。
	var hollow_line_rect: Rect2 = Rect2(chain_horizontal_margin, card_size.y * 0.5 - chained_hollow_line_height * 0.5, hollow_line_width, chained_hollow_line_height)
	draw_rect(hollow_line_rect, chain_color, false, chain_line_width, true)


## 构建一个闭合旋转椭圆的采样点；返回值供横置链环描边使用。
func _make_ellipse_points(center: Vector2, radius: Vector2, rotation_angle: float) -> PackedVector2Array:
	# 椭圆采样点；16段在标准武将牌尺寸下足够平滑，同时避免无意义的高密度绘制。
	var points: PackedVector2Array = PackedVector2Array()
	# 固定采样段数；末尾额外重复起点以形成闭合折线。
	var segment_count: int = 16
	for point_index: int in range(segment_count + 1):
		# 当前采样角度；按完整一周均匀分布。
		var angle: float = TAU * float(point_index) / float(segment_count)
		# 当前椭圆局部坐标；旋转后平移到链环中心。
		var local_point: Vector2 = Vector2(cos(angle) * radius.x, sin(angle) * radius.y).rotated(rotation_angle)
		points.append(center + local_point)
	return points
