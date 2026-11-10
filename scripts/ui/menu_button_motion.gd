extends Control

## 挂在BaseButton下的纯表现组件：鼠标、键盘和触屏共用按压回弹，视觉变换不改变布局或命中区域。
## 不发射pressed、不修改toggle状态，不持有任何菜单、网络或游戏规则对象。

## 悬停过渡秒数；默认0.16，运行时可以修改，较小值使反馈更利落。
@export_range(0.05, 0.5, 0.01) var hover_duration: float = 0.16
## 松开回弹秒数；默认0.20，运行时可以修改，不影响按钮业务执行时机。
@export_range(0.05, 0.5, 0.01) var release_duration: float = 0.20
## 按下缩放；默认0.975，范围0.90至1，只影响绘制，不缩小触摸命中范围。
@export_range(0.90, 1.0, 0.005) var pressed_scale: float = 0.975
## 悬停上浮距离；默认1.5逻辑像素，运行时可改为0以保留颜色反馈而关闭位移。
@export_range(0.0, 4.0, 0.5) var hover_lift: float = 1.5
## 组件总开关；默认开启，关闭时立即复位，供局外动效控制器统一管理。
var motion_enabled: bool = true:
	set(value):
		motion_enabled = value
		if is_node_ready() and not value:
			_reset()
## 宿主按钮；只绑定直接父节点，初始为空避免在入树前读取控件。
var _button: BaseButton
## 当前唯一反馈Tween；新的输入取消旧轨道，避免快速滑动积累动画。
var _tween: Tween
## 鼠标是否位于宿主；默认false，隐藏或移出后清空，触屏不制造持续悬停。
var _hovered: bool = false
## 按压是否仍在进行；默认false，独立于toggle按钮的持续选中状态。
var _pressing: bool = false
## 边缘高光强度；0至1，默认0，只有Tween更新时请求重绘。
var _glow: float = 0.0:
	set(value):
		_glow = value
		queue_redraw()


## 接入宿主的原生信号；自身忽略鼠标，不创建逐帧处理或输入代理。
func _ready() -> void:
	_button = get_parent() as BaseButton
	if _button == null:
		queue_free()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_button.offset_transform_enabled = true
	_button.offset_transform_visual_only = true
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)
	_button.button_down.connect(_on_button_down)
	_button.button_up.connect(_on_button_up)
	_button.focus_entered.connect(_refresh_feedback)
	_button.focus_exited.connect(_refresh_feedback)
	_button.visibility_changed.connect(_on_visibility_changed)
	_button.theme_changed.connect(queue_redraw)
	_button.draw.connect(_on_button_drawn)
	resized.connect(queue_redraw)


## 绘制低不透明度上沿光线；不铺色覆盖文字，且不依赖任何纹理资源。
func _draw() -> void:
	if _glow <= 0.01 or _button == null or _button.disabled:
		return
	# 当前主题高光；边缘亮度受动画强度控制，深浅主题可共用。
	var accent: Color = BattleUIStyle.get_color("accent")
	accent.a = _glow * 0.65
	draw_line(Vector2(12.0, 1.0), Vector2(maxf(12.0, size.x - 12.0), 1.0), accent, 1.0, true)


## 鼠标进入时上浮；模拟鼠标的移动端仍以按下/松开为主，不保留悬停。
func _on_mouse_entered() -> void:
	_hovered = not OS.has_feature("mobile")
	_refresh_feedback()


## 离开按钮后恢复位置，即使按压期间拖出也不会留下悬停态。
func _on_mouse_exited() -> void:
	_hovered = false
	_pressing = false
	_refresh_feedback()


## 记录物理按下状态；不读取toggle按钮的is_pressed，避免选中项永久缩小。
func _on_button_down() -> void:
	_pressing = true
	_refresh_feedback()


## 松开后回弹；业务pressed信号仍由宿主按原时机发送。
func _on_button_up() -> void:
	_pressing = false
	_refresh_feedback()


## 将最新输入状态合并到单个Tween；Godot4.7的visual-only变换不会触发容器重排。
func _refresh_feedback() -> void:
	if not motion_enabled or _button.disabled or not _button.is_visible_in_tree():
		_reset()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 当前强调状态；键盘焦点与鼠标悬停享有同等可见反馈。
	var highlighted: bool = _hovered or _button.has_focus()
	# 反馈时长；按下更快，回弹采用检查器配置。
	var duration: float = hover_duration * 0.5 if _pressing else release_duration
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_button, "offset_transform_scale", Vector2.ONE * (pressed_scale if _pressing else 1.0), duration)
	_tween.tween_property(_button, "offset_transform_position", Vector2(0.0, -hover_lift if highlighted and not _pressing else 0.0), duration)
	_tween.tween_property(self, "_glow", 1.0 if highlighted else 0.0, hover_duration)


## 隐藏即复位；返回原页面时不会继承上一次未完成的按压或半透明状态。
func _on_visibility_changed() -> void:
	if not _button.is_visible_in_tree():
		_reset()


## disabled属性没有独立变更信号；原生重绘时检查一次，避免请求处理中留下按压缩放。
func _on_button_drawn() -> void:
	if _button.disabled and (_pressing or _glow > 0.0):
		_reset()


## 取消本组件轨道并还原视觉变换；不修改按钮原有布局、scale和modulate。
func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_hovered = false
	_pressing = false
	_glow = 0.0
	if is_instance_valid(_button):
		_button.offset_transform_position = Vector2.ZERO
		_button.offset_transform_scale = Vector2.ONE
