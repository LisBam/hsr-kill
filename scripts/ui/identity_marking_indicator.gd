class_name IdentityMarkingIndicator
extends Control

## 自动身份标记复选框的独立可视指示器。它覆盖主题默认图标，保证关闭时仍有清晰边框，开启时显示主题色对勾。

## 指示框边框宽度；默认2像素使深色主题中未勾选状态也能稳定辨认，运行时通常无需修改。
@export_range(1.0, 4.0, 1.0) var border_width: float = 2.0

## 对勾线条宽度；默认2.5像素兼顾720逻辑视口下的清晰度与紧凑设置行高度，运行时通常无需修改。
@export_range(1.0, 5.0, 0.5) var checkmark_width: float = 2.5

## 关联的复选框；进入场景后从父节点取得，只读取其勾选状态而不保存任何游戏设置。
var _check_box: CheckBox


## 连接父复选框和全局主题变化；两类变化都只触发重绘，不修改复选框事件或配置值。
func _ready() -> void:
	_check_box = get_parent() as CheckBox
	if _check_box != null:
		_check_box.toggled.connect(_on_check_box_toggled)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	queue_redraw()


## 绘制固定尺寸的未选边框与已选对勾；子节点绘制层高于 Godot 默认图标，避免默认主题图标在深色背景中消失。
func _draw() -> void:
	# 当前指示框矩形；四边各保留1像素，避免2像素描边在控件边缘被裁剪。
	var indicator_rect: Rect2 = Rect2(Vector2.ONE, size - Vector2.ONE * 2.0)
	# 当前主题边框颜色；未勾选仍使用强调色，保证开关状态切换后始终保留明确点击目标。
	var border_color: Color = BattleUIStyle.get_color("accent")
	# 当前是否已启用自动标记；父复选框不存在时安全按未勾选绘制。
	var is_checked: bool = _check_box != null and _check_box.button_pressed
	# 已选背景色；保持高不透明度以遮住默认主题的淡色勾选图标，同时不影响右侧文字可读性。
	var fill_color: Color = Color(BattleUIStyle.get_color("action_button"), 0.96) if is_checked else Color(BattleUIStyle.get_color("panel"), 0.94)
	# 指示框样式；窄圆角与主题边框确保两套风格下的未选状态都清晰可见。
	var indicator_style: StyleBoxFlat = BattleUIStyle.make_panel(fill_color, border_color, int(border_width), 3)
	indicator_style.shadow_size = 0
	indicator_style.content_margin_left = 0.0
	indicator_style.content_margin_top = 0.0
	indicator_style.content_margin_right = 0.0
	indicator_style.content_margin_bottom = 0.0
	draw_style_box(indicator_style, indicator_rect)
	if not is_checked:
		return
	# 对勾三点；使用主题主文字色形成高对比度，点位随控件尺寸缩放且不依赖位图资源。
	var checkmark_points: PackedVector2Array = PackedVector2Array([
		Vector2(size.x * 0.22, size.y * 0.53),
		Vector2(size.x * 0.43, size.y * 0.73),
		Vector2(size.x * 0.78, size.y * 0.30),
	])
	draw_polyline(checkmark_points, BattleUIStyle.get_color("button_font"), checkmark_width, true)


## 父复选框状态改变后重绘；逻辑设置仍由原 CheckBox 的 toggled 回调写入 GameSettings。
func _on_check_box_toggled(_enabled: bool) -> void:
	queue_redraw()


## 主题变化后重绘当前状态；不需要等待设置面板重建，已展开菜单可即时看到新配色。
func _on_ui_style_changed(_style_id: String) -> void:
	queue_redraw()
