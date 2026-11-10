extends Control

## 只绘制牌面外围的选择反馈。宿主拥有选中集合、尺寸和输入；本组件不移动牌、读取规则或遮盖正文。
## 使用同一份状态重复configure不会重播Tween，适合高频快照与主题重绘。

## 选中角线收拢时长；默认0.20秒，只影响表现，可运行时调整。
@export_range(0.0, 0.5, 0.01) var enter_seconds: float = 0.20
## 取消选择淡出时长；默认0.12秒，不延迟取消动作，可运行时调整。
@export_range(0.0, 0.5, 0.01) var exit_seconds: float = 0.12
## 角线长度；默认14像素，避免沿整条牌边绘制高亮粗框，运行时通常无需修改。
@export_range(6.0, 24.0, 1.0) var bracket_length: float = 14.0
## 外缘柔光范围；默认8像素，不计入宿主最小尺寸，运行时通常无需修改。
@export_range(0, 16, 1) var glow_size: int = 8
## 当前业务选中态；默认false，唯一来源是宿主configure。
var selected: bool = false
## 当前可交互悬停态；默认false，用低强度边光表达可点击性。
var _hovered: bool = false
## 当前语义色；首次configure由活动主题传入，缓存用于绘制。
var _accent: Color = Color.WHITE
## 选中插值；0至1，只在有限Tween内重绘，没有常驻_process。
var _amount: float = 0.0:
	set(value):
		_amount = value
		queue_redraw()
## 悬停插值；0至1，与选择轨道一起取消，避免快速输入累积Tween。
var _hover_amount: float = 0.0:
	set(value):
		_hover_amount = value
		queue_redraw()
## 当前唯一状态轨道；重复状态保持原轨道，隐藏和释放时回收。
var _tween: Tween
## 可复用透明轮廓样式；绘制期间只调整颜色，不反复分配资源。
var _outline: StyleBoxFlat = StyleBoxFlat.new()


## 初始化纯绘制组件；不进入布局计算或鼠标、键盘焦点链。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_outline.draw_center = false
	_outline.set_border_width_all(1)
	_outline.set_corner_radius_all(7)
	_outline.shadow_offset = Vector2.ZERO
	_outline.anti_aliasing = true
	visibility_changed.connect(_on_visibility_changed)


## 更新状态和牌面几何；尺寸或主题变化只重绘，不制造一次新的选择事件。
func configure(card_size: Vector2, is_selected: bool, accent: Color, hovered: bool = false) -> void:
	size = card_size
	_accent = accent
	if selected == is_selected and _hovered == hovered:
		queue_redraw()
		return
	selected = is_selected
	_hovered = hovered
	_stop_tween()
	if not is_inside_tree() or not is_visible_in_tree():
		_settle()
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_amount", 1.0 if selected else 0.0, enter_seconds if selected else exit_seconds)
	_tween.tween_property(self, "_hover_amount", 1.0 if hovered else 0.0, exit_seconds)


## 绘制外沿与四角锁定线；不叠加文字、图标或勾章，牌面中央与身份区域始终完整可见。
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or maxf(_amount, _hover_amount) <= 0.001:
		return
	# 轮廓强度；选中优先，悬停仅保留弱边光，避免与合法目标色混淆。
	var strength: float = maxf(_amount, _hover_amount * 0.32)
	_outline.border_color = Color(_accent, strength * 0.75)
	_outline.shadow_color = Color(_accent, strength * 0.26)
	_outline.shadow_size = glow_size
	draw_style_box(_outline, Rect2(Vector2.ONE * -1.0, size + Vector2.ONE * 2.0))
	if _amount <= 0.001:
		return
	# 角线收拢距离；从外侧6像素归拢至牌框外2像素，不改变宿主命中范围。
	var gap: float = lerpf(6.0, 2.0, _amount)
	# 当前角线颜色；淡入与淡出共同使用相同插值。
	var tint: Color = Color(_accent, _amount)
	# 四角参考矩形；没有实心底板，不遮盖牌背或武将信息。
	var rect: Rect2 = Rect2(Vector2.ONE * -gap, size + Vector2.ONE * gap * 2.0)
	for corner: Vector2 in [Vector2.ZERO, Vector2(1.0, 0.0), Vector2.ONE, Vector2(0.0, 1.0)]:
		# 当前角的坐标；用归一化角点同时适配技能按钮、手牌与武将牌。
		var point: Vector2 = rect.position + rect.size * corner
		# 指向矩形内部的方向；避免每个角复制一套绘制逻辑。
		var direction: Vector2 = Vector2.ONE - corner * 2.0
		draw_polyline(PackedVector2Array([point + Vector2(direction.x * bracket_length, 0.0), point, point + Vector2(0.0, direction.y * bracket_length)]), tint, 2.0, true)



## 隐藏即停止动画并保留最终业务态；重新显示不会继承半截淡入或旧悬停。
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_stop_tween()
		_hovered = false
		_settle()


## 同步至最终状态；只改绘制插值，不改业务选择集合。
func _settle() -> void:
	_amount = 1.0 if selected else 0.0
	_hover_amount = 1.0 if _hovered else 0.0


## 回收当前轨道；kill不发送finished，因此不存在迟到的状态覆盖。
func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


## 卡牌退树或被飞牌层复用时释放表现轨道。
func _exit_tree() -> void:
	_stop_tween()
