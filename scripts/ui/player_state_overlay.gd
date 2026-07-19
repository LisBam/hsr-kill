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

## 横置外框延伸到武将牌两侧的长度；默认10像素让实体端点明确位于牌外，而中部透明区域仍与牌面等长。
@export_range(0.0, 32.0, 1.0) var chained_outer_extension: float = 10.0

## 横置外框高度；默认18像素为深灰实体端点和双层描边预留清晰层次，只影响视觉表现。
@export_range(8.0, 36.0, 1.0) var chained_outer_frame_height: float = 18.0

## 横置内框相对外框的垂直缩进；默认4像素形成稳定的深浅双层边框，不能大于外框高度的一半。
@export_range(1.0, 12.0, 1.0) var chained_inner_frame_inset: float = 4.0

## 横置深灰外边框宽度；默认3像素强调牌外实体部分，仅影响绘制表现。
@export_range(1.0, 8.0, 0.5) var chained_outer_border_width: float = 3.0

## 横置浅灰内边框宽度；默认1.5像素与深灰外框形成可辨识的双层轮廓，仅影响绘制表现。
@export_range(0.5, 6.0, 0.5) var chained_inner_border_width: float = 1.5

## 横置外框与牌外实体端点颜色；默认深灰色保证浅色和深色插画上都能辨认横置状态。
@export var chained_outer_color: Color = Color("414141f2")

## 横置内边框颜色；默认使用中灰色，在透明中段明确标出与武将牌等长的横置区域。
@export var chained_inner_color: Color = Color("a9a9a9e8")

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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_geometry()
	_refresh_state()


## 按武将牌实际尺寸重建覆盖层几何；横置框可越出牌面，阵亡滤镜仍严格只覆盖武将牌主体。
func configure_card_size(new_card_size: Vector2) -> void:
	# 新的武将牌尺寸；非法零尺寸回退为最小1像素，避免 Control 出现负尺寸。
	card_size = new_card_size.max(Vector2.ONE)
	if not is_node_ready():
		return
	_refresh_geometry()
	queue_redraw()


## 同步覆盖层、阵亡滤镜与横置外延的局部坐标；该方法只处理 UI 几何，不改变横置或死亡规则状态。
func _refresh_geometry() -> void:
	# 横置框每侧外延；非负限制保证原始卡牌坐标始终从覆盖层内部开始。
	var outer_extension: float = maxf(chained_outer_extension, 0.0)
	# 覆盖层总宽度；中段长度保持为武将牌宽度，两侧只增加横置实体端点所需空间。
	size = Vector2(card_size.x + outer_extension * 2.0, card_size.y)
	# 覆盖层原点；向左平移后，局部 x=outer_extension 恰好与武将牌左边缘重合。
	position = Vector2(-outer_extension, 0.0)
	# 阵亡滤镜矩形；阵亡状态不能覆盖横置框的牌外实体端点。
	var card_rect: Rect2 = Rect2(Vector2(outer_extension, 0.0), card_size)
	_death_back_buffer.rect = card_rect
	_death_filter.position = card_rect.position
	_death_filter.size = card_rect.size
	_death_label.position = card_rect.position
	_death_label.size = card_rect.size


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
## 横置状态使用双层边框与牌外实体端点；保留该说明以兼容旧场景参数的设计语义。
func _draw() -> void:
	if _is_dead or not _is_chained:
		return
	# 横置框每侧的牌外长度；与几何方法使用同一限制，避免检查器输入负数时绘制错位。
	var outer_extension: float = maxf(chained_outer_extension, 0.0)
	# 外框实际高度；兼容旧的中空横线高度配置，保证新框不会比旧状态提示更细。
	var outer_height: float = maxf(chained_outer_frame_height, chained_hollow_line_height)
	# 外框垂直起点；始终围绕武将牌的中线绘制。
	var outer_top: float = card_size.y * 0.5 - outer_height * 0.5
	# 深灰外框矩形；总长度略大于武将牌，实体两端位于牌面外侧。
	var outer_frame_rect: Rect2 = Rect2(Vector2(0.0, outer_top), Vector2(card_size.x + outer_extension * 2.0, outer_height))
	# 左侧实体端点；仅填充牌外区域，武将牌覆盖部分保持透明。
	var left_cap_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(outer_extension, outer_height))
	left_cap_rect.position.y = outer_top
	# 右侧实体端点；与左端对称，确保横置效果在两侧具有一致的外延。
	var right_cap_rect: Rect2 = Rect2(Vector2(card_size.x + outer_extension, outer_top), Vector2(outer_extension, outer_height))
	# 内框垂直缩进；限制在外框一半以内，避免极端配置得到负高度。
	var inner_inset: float = minf(maxf(chained_inner_frame_inset, 0.0), maxf(outer_height * 0.5 - 0.5, 0.0))
	# 内框矩形；宽度严格等于武将牌宽度，因此内框内部的透明部分与武将牌等长。
	var inner_frame_rect: Rect2 = Rect2(Vector2(outer_extension, outer_top + inner_inset), Vector2(card_size.x, maxf(outer_height - inner_inset * 2.0, 1.0)))
	# 深灰端点填充；给牌外部分明确的实体质感，同时不遮盖武将插画。
	draw_rect(left_cap_rect, chained_outer_color, true, -1.0, true)
	draw_rect(right_cap_rect, chained_outer_color, true, -1.0, true)
	# 深灰外边框；围出完整横置轮廓并连接两侧实体端点。
	draw_rect(outer_frame_rect, chained_outer_color, false, chained_outer_border_width, true)
	# 浅灰内边框；标出穿过武将牌的透明中段，与外框形成双层灰色轮廓。
	draw_rect(inner_frame_rect, chained_inner_color, false, chained_inner_border_width, true)
	# 中空横线可用宽度；扣除左右留白后始终贯穿武将牌主体且不会越过边框。
	# 旧横线配置只用于兼容既有资源；双层框不使用水平留白，确保透明中段完整覆盖武将牌宽度。


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
