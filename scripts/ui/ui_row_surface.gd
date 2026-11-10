extends Node

## 表格行底纹。直接订阅宿主draw，不插入参与HBox布局的Control，数值列对齐与命中范围保持不变。

## 交错底纹序号；默认0，用父列表中的稳定行号决定背景强度，主题变化时可重绘。
@export var stripe_index: int = 0
## 宿主行容器；默认空，由直接父节点取得。
var _row: Control
## 缓存的底纹；仅首次建立与主题变化时更新，不在每次draw分配资源。
var _style: StyleBoxFlat = StyleBoxFlat.new()


## 接入一次绘制和尺寸变化；不创建Process或输入代理。
func _ready() -> void:
	_row = get_parent() as Control
	_row.draw.connect(_draw_row)
	_row.resized.connect(_row.queue_redraw)
	refresh_style()


## 从活动主题生成低对比交错条；不把胜负、座次等规则含义编码进配色。
func refresh_style() -> void:
	_style.bg_color = Color(BattleUIStyle.get_color("text_primary"), 0.055 if stripe_index % 2 == 0 else 0.018)
	_style.border_color = Color(BattleUIStyle.get_color("border"), 0.12)
	_style.border_width_bottom = 1
	_style.set_corner_radius_all(4)
	if is_instance_valid(_row):
		_row.queue_redraw()


## 底纹由父容器先绘制，子标签自然处于其上方，不需要新增z_index。
func _draw_row() -> void:
	_row.draw_style_box(_style, Rect2(Vector2.ZERO, _row.size))
