class_name ReferenceBackdrop
extends TextureRect

## 十周年风格牌桌背景组件。组件只绘制可缩放的桌面、木质包边与金色装饰，不读取对局状态，也不依赖参考扩展目录中的外部资源。

## 牌桌主体相对控件边缘的留白；默认18像素用于露出外层木质框，运行时无需动态修改。
@export_range(0.0, 80.0, 1.0) var table_inset: float = 18.0

## 外层木质框宽度；默认14像素形成十周年界面的厚重桌框，运行时无需动态修改。
@export_range(4.0, 40.0, 1.0) var rail_width: float = 14.0

## 桌面圆角半径；默认30像素弱化矩形屏幕边缘，运行时无需动态修改。
@export_range(0.0, 80.0, 1.0) var table_corner_radius: float = 30.0

## 中央装饰环的半径；默认150像素用于限定视觉焦点，运行时无需动态修改。
@export_range(60.0, 280.0, 1.0) var center_ornament_radius: float = 150.0

## 装饰线透明度；默认0.16保证纹样可见但不干扰卡牌，运行时可在检查器中微调。
@export_range(0.0, 0.5, 0.01) var ornament_opacity: float = 0.16

## 太空风格网格间距；默认64像素形成低密度导航网格，仅在风格注册表启用时绘制，运行时无需动态修改。
@export_range(24.0, 160.0, 1.0) var space_grid_spacing: float = 64.0

## 太空风格网格线宽；默认1像素保持辅助层次，不遮挡角色、卡牌或中央动画。
@export_range(0.5, 3.0, 0.5) var space_grid_line_width: float = 1.0

## 背景最深层颜色；默认使用近黑暖褐色衬托桌面与金边，运行时无需动态修改。
## 当前默认风格改为黑白太空，进入场景后会由统一主题语义覆盖该字段。
@export var outer_background_color: Color = Color("020306")

## 桌面主体颜色；默认使用低明度墨青色延续《崩铁杀》的深青视觉语言，运行时无需动态修改。
@export var table_surface_color: Color = Color("0b0f16")

## 桌面内层颜色；默认比主体更暗，用于制造皮革桌垫的纵深，运行时无需动态修改。
@export var table_inner_color: Color = Color("05070c")

## 木质框主色；默认使用深胡桃木色模拟十周年 UI 的实木包边，运行时无需动态修改。
@export var wood_color: Color = Color("11151d")

## 木质框高光色；默认使用暖棕色表现上沿受光，运行时无需动态修改。
@export var wood_highlight_color: Color = Color("586170")

## 金属装饰颜色；默认使用低饱和古金色绘制内框和中央纹样，运行时无需动态修改。
@export var gold_color: Color = Color("c9d1dc")

## 远景天幕颜色；默认使用近黑蓝灰色，运行时由当前 UI 风格统一刷新。
@export var sky_color: Color = Color("0c111b")

## 远景星点颜色；默认使用银白色，透明度在绘制时单独控制。
@export var star_color: Color = Color("eef3ff")

## 远景山脊颜色；默认使用比桌面更深的黑灰色，仅承担空间层次。
@export var mountain_color: Color = Color("090c12")

## 远景建筑剪影颜色；默认接近纯黑，避免与中央牌面动画争夺对比度。
@export var building_color: Color = Color("04060a")

## 太空导航网格颜色；透明度包含在颜色本身中，由主题注册表统一覆盖。
@export var space_grid_color: Color = Color("6ccfe033")

## 当前主题是否启用太空导航网格；只影响背景装饰，不改变牌桌几何或输入。
var _uses_space_grid: bool = false

## 天幕地平线比例；默认把远景压在牌桌中央下方，保留无名杀式的宽阔中空区域。
const SKYLINE_RATIO: float = 0.64

## 远景星点数量；固定数量保证每帧绘制成本稳定，修改后只改变背景表现。
const STAR_COUNT: int = 26


## 节点进入场景树后启用重绘；背景忽略鼠标，避免阻断任何卡牌交互。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	apply_ui_style(BattleUIStyle.get_active_style_id())
	queue_redraw()


## 应用指定 UI 风格的背景语义色；组件只读取注册表，不保存菜单控件或全局设置引用。
func apply_ui_style(style_id: String) -> void:
	outer_background_color = UIStyleRegistry.get_color(style_id, "outer_background", outer_background_color)
	table_surface_color = UIStyleRegistry.get_color(style_id, "table_surface", table_surface_color)
	table_inner_color = UIStyleRegistry.get_color(style_id, "table_inner", table_inner_color)
	wood_color = UIStyleRegistry.get_color(style_id, "rail", wood_color)
	wood_highlight_color = UIStyleRegistry.get_color(style_id, "rail_highlight", wood_highlight_color)
	gold_color = UIStyleRegistry.get_color(style_id, "ornament", gold_color)
	sky_color = UIStyleRegistry.get_color(style_id, "sky", sky_color)
	star_color = UIStyleRegistry.get_color(style_id, "star", star_color)
	mountain_color = UIStyleRegistry.get_color(style_id, "mountain", mountain_color)
	building_color = UIStyleRegistry.get_color(style_id, "building", building_color)
	space_grid_color = UIStyleRegistry.get_color(style_id, "space_grid", space_grid_color)
	_uses_space_grid = bool(UIStyleRegistry.get_value(style_id, "uses_space_grid", false))
	queue_redraw()


## 按当前控件尺寸绘制可缩放牌桌；所有图形仅承担视觉表现，不保存任何规则数据。
func _draw() -> void:
	# 当前背景尺寸；尺寸无效时跳过绘制，避免编辑器初始化阶段产生异常几何。
	var backdrop_size: Vector2 = size
	if backdrop_size.x <= 0.0 or backdrop_size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, backdrop_size), outer_background_color)
	# 外层木质框矩形；覆盖全屏并作为桌面主体的包边底色。
	var outer_rect: Rect2 = Rect2(Vector2(table_inset - rail_width, table_inset - rail_width), backdrop_size - Vector2.ONE * (table_inset - rail_width) * 2.0)
	draw_style_box(_make_rounded_box(wood_color, wood_highlight_color, 2, table_corner_radius + rail_width), outer_rect)
	# 桌面主体矩形；深青皮革区域承载全部角色卡与结算动画。
	var table_rect: Rect2 = Rect2(Vector2.ONE * table_inset, backdrop_size - Vector2.ONE * table_inset * 2.0)
	draw_style_box(_make_rounded_box(table_surface_color, gold_color.darkened(0.35), 2, table_corner_radius), table_rect)
	# 内层桌垫矩形；轻微缩进形成双层金边与桌面纵深。
	var inner_rect: Rect2 = table_rect.grow(-8.0)
	draw_style_box(_make_rounded_box(table_inner_color, gold_color.darkened(0.5), 1, table_corner_radius - 6.0), inner_rect)
	# 牌桌远景；用低对比度天幕、山脊和建筑剪影模拟参考截图的中央背景，不承载任何玩法信息。
	# 天幕基准线；所有远景绘制都围绕该比例计算，窗口拉伸时保持构图一致。
	var skyline_y: float = inner_rect.position.y + inner_rect.size.y * SKYLINE_RATIO
	# 天幕矩形；只覆盖内层桌垫的上方区域，底部仍由桌垫颜色承托手牌。
	var sky_rect: Rect2 = Rect2(inner_rect.position, Vector2(inner_rect.size.x, skyline_y - inner_rect.position.y))
	draw_rect(sky_rect, sky_color)
	if _uses_space_grid:
		# 第一条纵向网格线横坐标；从内层桌垫左边开始按统一间距铺满可视区域。
		var grid_x: float = inner_rect.position.x
		while grid_x <= inner_rect.end.x:
			draw_line(Vector2(grid_x, inner_rect.position.y), Vector2(grid_x, inner_rect.end.y), space_grid_color, space_grid_line_width, true)
			grid_x += space_grid_spacing
		# 第一条横向网格线纵坐标；与纵向网格共同形成独立于旧木桌纹样的太空导航层。
		var grid_y: float = inner_rect.position.y
		while grid_y <= inner_rect.end.y:
			draw_line(Vector2(inner_rect.position.x, grid_y), Vector2(inner_rect.end.x, grid_y), space_grid_color, space_grid_line_width, true)
			grid_y += space_grid_spacing
	# 远景星点；固定伪随机位置避免引入全局随机数或影响规则回放。
	for star_index: int in range(STAR_COUNT):
		# 当前星点横坐标；使用确定性取模实现可缩放的均匀分布。
		var star_x: float = inner_rect.position.x + fmod(float(star_index * 137), maxf(inner_rect.size.x, 1.0))
		# 当前星点纵坐标；限制在天幕矩形内，避免落入手牌操作区。
		var star_y: float = inner_rect.position.y + fmod(float(star_index * 71), maxf(sky_rect.size.y, 1.0))
		draw_circle(Vector2(star_x, star_y), 1.0 if star_index % 3 else 1.5, Color(star_color, 0.34))
	# 山脊剪影；半透明层叠制造参考界面的远景纵深，避免遮挡中央动画落点。
	var mountain_points: PackedVector2Array = PackedVector2Array([
		Vector2(inner_rect.position.x, skyline_y + 36.0),
		Vector2(inner_rect.position.x + inner_rect.size.x * 0.18, skyline_y - 18.0),
		Vector2(inner_rect.position.x + inner_rect.size.x * 0.34, skyline_y + 22.0),
		Vector2(inner_rect.position.x + inner_rect.size.x * 0.52, skyline_y - 30.0),
		Vector2(inner_rect.position.x + inner_rect.size.x * 0.72, skyline_y + 14.0),
		Vector2(inner_rect.end.x, skyline_y - 12.0),
		Vector2(inner_rect.end.x, inner_rect.end.y),
		Vector2(inner_rect.position.x, inner_rect.end.y),
	])
	draw_colored_polygon(mountain_points, Color(mountain_color, 0.72))
	# 建筑剪影；低矮矩形与屋檐折线只承担氛围表现，不覆盖玩家牌和手牌区。
	# 建筑基准线；把建筑底部固定在远景下方，窗口拉伸时保持相对高度。
	var building_base_y: float = inner_rect.position.y + inner_rect.size.y * 0.76
	for building_index: int in range(5):
		# 当前建筑横坐标；按固定比例排列五组远景剪影。
		var building_x: float = inner_rect.position.x + inner_rect.size.x * (0.24 + float(building_index) * 0.13)
		# 当前建筑高度；使用三档确定性高度形成自然错落。
		var building_height: float = 24.0 + float((building_index + 2) % 3) * 12.0
		# 当前建筑矩形；只绘制低透明度暗色剪影，不包含交互信息。
		var building_rect: Rect2 = Rect2(building_x, building_base_y - building_height, 46.0, building_height)
		draw_rect(building_rect, Color(building_color, 0.74))
		draw_colored_polygon(PackedVector2Array([
			Vector2(building_rect.position.x - 8.0, building_rect.position.y),
			Vector2(building_rect.end.x + 8.0, building_rect.position.y),
			Vector2(building_rect.position.x + building_rect.size.x * 0.5, building_rect.position.y - 10.0),
		]), Color(building_color, 0.74))
	# 桌面中心点；所有星轨和同心环围绕该点绘制。
	var center: Vector2 = inner_rect.get_center()
	# 低透明度古金色；用于中央装饰，避免与飞牌和指示线争夺视觉焦点。
	var ornament_color: Color = Color(gold_color, ornament_opacity)
	draw_arc(center, center_ornament_radius, 0.0, TAU, 96, ornament_color, 1.5, true)
	draw_arc(center, center_ornament_radius * 0.72, 0.0, TAU, 96, ornament_color.darkened(0.15), 1.0, true)
	# 星轨外圈分段数量；12段对应时钟式环桌节奏，仅用于装饰。
	var segment_count: int = 12
	for segment_index: int in range(segment_count):
		# 当前分段角度；从顶部开始均匀分布。
		var angle: float = -PI * 0.5 + TAU * float(segment_index) / float(segment_count)
		# 分段线起点；位于内环外侧。
		var line_start: Vector2 = center + Vector2.from_angle(angle) * center_ornament_radius * 0.78
		# 分段线终点；位于外环内侧。
		var line_end: Vector2 = center + Vector2.from_angle(angle) * center_ornament_radius * 0.96
		draw_line(line_start, line_end, ornament_color, 1.0, true)
	# 中央菱形半径；与圆形星轨叠加，呼应十周年界面常见的金属铭纹。
	var diamond_radius: float = center_ornament_radius * 0.42
	# 中央菱形顶点；闭合折线只作为背景纹样。
	var diamond_points: PackedVector2Array = PackedVector2Array([center + Vector2(0.0, -diamond_radius), center + Vector2(diamond_radius, 0.0), center + Vector2(0.0, diamond_radius), center + Vector2(-diamond_radius, 0.0), center + Vector2(0.0, -diamond_radius)])
	draw_polyline(diamond_points, ornament_color.darkened(0.1), 1.25, true)


## 创建背景绘制使用的圆角样式；返回值仅在当前绘制帧使用，不会注册全局主题资源。
func _make_rounded_box(background_color: Color, border_color: Color, border_width: int, corner_radius: float) -> StyleBoxFlat:
	# 圆角样式；统一设置四边描边与四角半径。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(roundi(maxf(corner_radius, 0.0)))
	return style
