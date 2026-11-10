extends Node2D

## 武将牌的纯绘制饰面。由宿主传入几何与最终配色，不查找兄弟节点，不读取角色或规则对象。
## 放在插画之后、牌背和公开信息之前；所有绘制均在牌面内，完全不接管输入和布局。

## 内嵌金属线距外框的距离；默认2像素位于原4像素安全区内，运行时通常无需修改。
@export_range(1.0, 3.0, 0.5) var rim_inset: float = 2.0
## 内框圆角；默认4像素与原6像素外框形成同心层次，运行时通常无需修改。
@export_range(0, 8, 1) var rim_radius: int = 4
## 普通内框透明度；默认0.40形成细金属线，不替代合法或选中反馈，可运行时调整。
@export_range(0.0, 1.0, 0.05) var rim_alpha: float = 0.40
## 插画底端压暗区域高度；默认28像素衬托底边信息，不遮住武将面部，可运行时调整。
@export_range(0.0, 50.0, 1.0) var lower_shade_height: float = 28.0
## 渐层最大透明度；默认0.24只轻压插画底边，保持原图的主体亮度，可运行时调整。
@export_range(0.0, 0.5, 0.01) var shade_alpha: float = 0.24
## 悬停金属线过渡时长；默认0.18秒，有限Tween完成后不再逐帧刷新，可运行时调整。
@export_range(0.0, 0.4, 0.01) var hover_seconds: float = 0.18
## 渐层绘制分段数；默认20段避免依赖shader及额外纹理资源。
const SHADE_STEPS: int = 20
## 顶底饰线的横向安全区；默认30像素避开姓名、身份、体力与手牌角标。
const RAIL_SIDE_INSET: float = 30.0
## 金属刻线的宽度；默认0.8逻辑像素，在原生牌面尺寸下保持细致。
const RAIL_WIDTH: float = 0.8
## 悬停内框附加透明度；默认0.18，仅提升普通饰线而不改变选中边框。
const HOVER_RIM_ALPHA: float = 0.18
## 顶部刻线基础与悬停附加透明度；默认0.28与0.40形成有限高光。
const RAIL_ALPHA: Vector2 = Vector2(0.28, 0.40)
## 刻线混入主题边框色的比例；默认0.35保留主题材质色相。
const RAIL_TINT_BLEND: float = 0.35
## 底部刻线半长；默认13像素，在两侧常驻信息之间留出短刻线。
const LOWER_RAIL_HALF_WIDTH: float = 13.0
## 底部刻线透明度；默认0.60在渐层边缘保持低对比装饰。
const LOWER_RAIL_ALPHA: float = 0.60
## 渐层底色压暗比例；默认0.55用于生成透明的深色衬底。
const SHADE_DARKENING: float = 0.55
## 宿主牌面尺寸；由configure提供，默认零表示未完成初始化。
var _card_size: Vector2 = Vector2.ZERO
## 插画实际局部矩形；只用于内部渐层裁界，不修改插画本身。
var _artwork_bounds: Rect2
## 最终边框色；宿主已经处理合法、选中、行动者及禁用优先级。
var _trim_color: Color = Color.WHITE
## 渐层底色；只继承当前主题的表面色，不暴露任何角色信息。
var _surface_color: Color = Color.BLACK
## 高光颜色；由宿主传入主题文字色，单色主题不会出现额外彩光。
var _highlight_color: Color = Color.WHITE
## 插画存在标志；缺少插画时不在占位文字上叠加渐层。
var _has_artwork: bool = false
## 轻量内框样式；仅初始化一次，刷新时只更新属性。
var _rim: StyleBoxFlat = StyleBoxFlat.new()
## 悬停目标态；重复进入信号不得重启同一条动画。
var _hovered: bool = false
## 当前高光插值；0为静止，1为悬停，setter只请求重绘。
var _hover_amount: float = 0.0:
	set(value):
		_hover_amount = value
		queue_redraw()
## 当前有限动画；隐藏和释放时取消，避免离场后残留高光。
var _hover_tween: Tween


## 初始化无填充内框；没有_process，静止武将牌不持续消耗绘制更新。
func _ready() -> void:
	_rim.draw_center = false
	_rim.set_border_width_all(1)
	visibility_changed.connect(_on_visibility_changed)


## 接收已经解析的表现数据；所有值均为副本，不保存宿主或业务对象引用。
func configure(card_size: Vector2, artwork_bounds: Rect2, trim_color: Color, surface_color: Color, highlight_color: Color, has_artwork: bool) -> void:
	_card_size = card_size
	_artwork_bounds = artwork_bounds
	_trim_color = trim_color
	_surface_color = surface_color
	_highlight_color = highlight_color
	_has_artwork = has_artwork
	queue_redraw()


## 悬停只提亮边缘刻线；不会移动牌面、放大命中区或增加新的选择图标。
func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	_stop_hover()
	if hover_seconds <= 0.0 or not is_visible_in_tree():
		_hover_amount = 1.0 if hovered else 0.0
		return
	_hover_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "_hover_amount", 1.0 if hovered else 0.0, hover_seconds)


## 仅绘制原框内的饰线和底端渐层；牌背位于本层之上，暗置候选不会泄露插画。
func _draw() -> void:
	if _card_size.x <= 0.0 or _card_size.y <= 0.0:
		return
	if _has_artwork and lower_shade_height > 0.0:
		# 实际渐层高度；不能超过插画自身高度，避免小尺寸预览时越界。
		var shade_height: float = minf(lower_shade_height, _artwork_bounds.size.y)
		for step: int in range(SHADE_STEPS):
			# 从透明到深色的渐层比例；只影响底部，不向插画中央延伸。
			var fraction: float = float(step + 1) / float(SHADE_STEPS)
			# 当前渐层窄条；严格限制在原插画矩形内。
			var band: Rect2 = Rect2(Vector2(_artwork_bounds.position.x, _artwork_bounds.end.y - shade_height + shade_height * float(step) / float(SHADE_STEPS)), Vector2(_artwork_bounds.size.x, shade_height / float(SHADE_STEPS)))
			draw_rect(band, Color(_surface_color.darkened(SHADE_DARKENING), shade_alpha * fraction * fraction))
	_rim.set_corner_radius_all(rim_radius)
	_rim.border_color = Color(_trim_color, rim_alpha + _hover_amount * HOVER_RIM_ALPHA)
	draw_style_box(_rim, Rect2(Vector2.ONE * rim_inset, _card_size - Vector2.ONE * rim_inset * 2.0))
	# 顶部细亮线；两端避开常驻角标，悬停时只改变亮度。
	var rail_color: Color = Color(_highlight_color.lerp(_trim_color, RAIL_TINT_BLEND), RAIL_ALPHA.x + _hover_amount * RAIL_ALPHA.y)
	draw_line(Vector2(RAIL_SIDE_INSET, rim_inset + 0.5), Vector2(_card_size.x - RAIL_SIDE_INSET, rim_inset + 0.5), rail_color, RAIL_WIDTH, true)
	# 底部中央短刻线；两侧留白保留原有公开区与数值信息的主次。
	var center_x: float = _card_size.x * 0.5
	draw_line(Vector2(center_x - LOWER_RAIL_HALF_WIDTH, _card_size.y - rim_inset), Vector2(center_x + LOWER_RAIL_HALF_WIDTH, _card_size.y - rim_inset), Color(_trim_color, LOWER_RAIL_ALPHA), RAIL_WIDTH, true)


## 隐藏后同步归零，重新显示时不会继承离开前的半截悬停动画。
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_stop_hover()
		_hovered = false
		_hover_amount = 0.0


## 回收组件自己创建的Tween，不干涉宿主的选将缩放或伤害反馈。
func _stop_hover() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()


## 退出场景时停止有限动画，不保留全局引用。
func _exit_tree() -> void:
	_stop_hover()
