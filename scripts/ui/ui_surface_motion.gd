extends Node

## 面板的有限入场组件。关闭仍由宿主同步执行，不等待动画、不持有业务回调，不阻塞权威结算。
## 可挂于任何Control；只使用visual-only偏移，不写布局位置、尺寸、层级或输入权限。

## 入场时长；默认0.22秒，暂停期间也完成，可运行时调整。
@export_range(0.0, 0.6, 0.01) var duration: float = 0.22
## 入场移动距离；默认10逻辑像素，不改变点击区域，可运行时调整。
@export_range(0.0, 30.0, 1.0) var travel: float = 10.0
## 入场种类；modal轻缩放，page侧滑，fade仅淡入，运行时可调整。
@export_enum("modal", "page", "fade") var kind: String = "modal"
## 自动入场开关；默认开启，需等待异步测量的信息框关闭后由布局完成入口显式reveal。
@export var automatic: bool = true
## 宿主控件；默认空，由直接父节点取得，组件不依赖牌桌。
var _surface: Control
## 唯一动画轨道；重开、隐藏和释放都会取消。
var _tween: Tween
## 当前动画开始前的调制色；结束后精确恢复，保留宿主的自定义透明度。
var _base_modulate: Color = Color.WHITE
## 是否正在占用调制色；避免未播放时覆盖宿主的新状态。
var _active: bool = false


## 幂等装配；即使主题刷新或窗口复用也只有一个组件。
static func attach(surface: Control, motion_kind: String = "modal", automatic_reveal: bool = true) -> void:
	if surface == null or surface.has_node("SurfaceMotion"):
		return
	# 独立组件；生命周期跟随面板，不在全局保存引用。
	var motion: Node = load("res://scripts/ui/ui_surface_motion.gd").new()
	motion.name = "SurfaceMotion"
	motion.set("kind", motion_kind)
	motion.set("automatic", automatic_reveal)
	surface.add_child(motion)


## 可见性切换是唯一自动触发源；快照刷新不重播，暂停菜单也能完成入场。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = get_parent() as Control
	if _surface == null:
		return
	_surface.visibility_changed.connect(_on_visibility_changed)
	_surface.offset_transform_enabled = true
	_surface.offset_transform_visual_only = true
	_on_visibility_changed()


## 显示时播放，隐藏时立即复位；不延迟原来的close与提交信号。
func _on_visibility_changed() -> void:
	if _surface.is_visible_in_tree():
		if automatic:
			reveal()
	else:
		cancel()


## 从最终布局上的视觉偏移进入；可以显式用于同一窗口中的子页切换。
func reveal() -> void:
	cancel()
	if not is_instance_valid(_surface) or not _surface.is_visible_in_tree() or duration <= 0.0:
		return
	_base_modulate = _surface.modulate
	_active = true
	_surface.modulate.a = 0.0
	_surface.offset_transform_position = Vector2(travel, 0.0) if kind == "page" else Vector2(0.0, travel)
	_surface.offset_transform_scale = Vector2.ONE * (0.985 if kind == "modal" else 1.0)
	if kind == "fade":
		_surface.offset_transform_position = Vector2.ZERO
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_surface, "modulate:a", _base_modulate.a, duration)
	_tween.tween_property(_surface, "offset_transform_position", Vector2.ZERO, duration)
	_tween.tween_property(_surface, "offset_transform_scale", Vector2.ONE, duration)
	_tween.finished.connect(cancel)


## 立即清理轨道；不会让上一窗口的残余回调影响新请求。
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _active and is_instance_valid(_surface):
		_surface.modulate = _base_modulate
		_surface.offset_transform_position = Vector2.ZERO
		_surface.offset_transform_scale = Vector2.ONE
	_active = false


## 释放宿主时只回收自己的Tween，不修改外部对局状态。
func _exit_tree() -> void:
	cancel()
