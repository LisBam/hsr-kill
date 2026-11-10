extends ColorRect
class_name GalleryLoadingCover

## 列表加载遮罩；只覆盖对应滚动区，不阻断页面导航和其他操作。

## 居中状态文字；提示首屏或快速跳转后的可见内容仍在准备。
var _status_label: Label


## 初始化状态文字和输入边界；样式从当前主题读取，供多个列表组件复用。
func _ready() -> void:
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_status_label = Label.new()
	_status_label.text = "正在准备内容…"
	# 首次打开之前也提供主题字体色，隐藏的加载提示不能依赖set_loading才完成视觉初始化。
	_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_status_label)
	visible = false


## 同步遮罩显隐与滚动区位置；target 和 parent 必须位于同一个画布。
func set_loading(loading: bool, target: Control) -> void:
	visible = loading
	if not loading or target == null or not is_node_ready():
		return
	# 父级控件；用于将滚动区全局位置转换到遮罩所在的本地坐标。
	var host: Control = get_parent() as Control
	if host == null:
		return
	position = host.get_global_transform().affine_inverse() * target.global_position
	size = target.size
	color = BattleUIStyle.get_color("metal_panel")
	color.a = 1.0
	_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
