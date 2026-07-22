class_name PlayerMarkerBadge
extends Control

## 单个公开标记图标。组件只渲染公开快照并发送悬停说明，不读取规则控制器或修改标记数量。

## 鼠标进入标记时发送的详细信息；外层牌桌统一决定信息框位置与生命周期。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开标记时发送关闭请求；来源匹配由牌桌唯一信息框负责校验。
signal information_dismissed

## 标记圆形图标直径；默认32像素兼顾武将牌左侧纵排与第一视角横排，运行时通常无需动态修改。
## 当前默认值缩小为24像素，使公开标记紧贴武将牌时不遮挡牌面。
@export_range(20.0, 48.0, 1.0) var badge_diameter: float = 24.0

## 标记中央单字字号；默认18像素可在32像素圆内清晰显示，运行时通常无需动态修改。
## 当前默认值调整为14像素，对应24像素圆形主体。
@export_range(10, 28, 1) var icon_font_size: int = 14

## 右下角数量徽记直径；默认15像素用于显示1至999，运行时通常无需动态修改。
## 当前默认值调整为12像素，与缩小后的主圆保持清晰比例。
@export_range(10.0, 22.0, 1.0) var count_diameter: float = 12.0

## 数量徽记字号；默认9像素可容纳三位数，运行时通常无需动态修改。
## 当前默认值调整为8像素，仍可容纳1至999的公开数量。
@export_range(7, 13, 1) var count_font_size: int = 8

## 当前标记公开数据；包含稳定ID、单字图标、名称、说明、数量和来源角色ID。
var _mark_data: Dictionary = {}

## 圆形主体面板；背景、边框与圆角全部由当前UI风格生成。
var _circle_panel: Panel

## 圆形中央单字标签；文本只取公开标记icon字段的第一个字符。
var _icon_label: Label

## 右下角数量背景；与主圆分离以保证数量始终可读。
var _count_panel: Panel

## 右下角数量文本；显示1至999的权威标记数量。
var _count_label: Label


## 创建固定子节点并连接悬停信号；节点在后续快照刷新中复用，不重复分配。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""
	_circle_panel = Panel.new()
	_circle_panel.name = "Circle"
	_circle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_circle_panel)
	_icon_label = Label.new()
	_icon_label.name = "Icon"
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_icon_label)
	_count_panel = Panel.new()
	_count_panel.name = "CountCircle"
	_count_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_panel)
	_count_label = Label.new()
	_count_label.name = "Count"
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_count_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_layout_children()
	refresh_ui_style()
	_refresh_content()


## 写入单项公开标记快照；调用方传入副本，组件不会向外暴露可修改引用。
func configure(mark_data: Dictionary) -> void:
	_mark_data = mark_data.duplicate(true)
	_refresh_content()


## 返回当前圆形标记占用尺寸；外层排列组件据此计算纵排或横排边界。
func get_badge_size() -> Vector2:
	return Vector2(badge_diameter, badge_diameter)


## 按当前UI风格刷新主圆、数量圆与文字颜色；不改变标记数据和排列顺序。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	# 主圆样式；使用深色牌面背景、主题强调边框和完整圆角。
	var circle_style: StyleBoxFlat = StyleBoxFlat.new()
	circle_style.bg_color = BattleUIStyle.get_color("player_background")
	circle_style.border_width_left = 2
	circle_style.border_width_top = 2
	circle_style.border_width_right = 2
	circle_style.border_width_bottom = 2
	circle_style.border_color = BattleUIStyle.get_color("accent")
	circle_style.corner_radius_top_left = int(badge_diameter * 0.5)
	circle_style.corner_radius_top_right = int(badge_diameter * 0.5)
	circle_style.corner_radius_bottom_right = int(badge_diameter * 0.5)
	circle_style.corner_radius_bottom_left = int(badge_diameter * 0.5)
	circle_style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	circle_style.shadow_size = 4
	_circle_panel.add_theme_stylebox_override("panel", circle_style)
	# 数量圆样式；使用强调色背景和深色边框，与主圆右下角形成明确层级。
	var count_style: StyleBoxFlat = StyleBoxFlat.new()
	count_style.bg_color = BattleUIStyle.get_color("accent")
	count_style.border_width_left = 1
	count_style.border_width_top = 1
	count_style.border_width_right = 1
	count_style.border_width_bottom = 1
	count_style.border_color = Color.BLACK
	count_style.corner_radius_top_left = int(count_diameter * 0.5)
	count_style.corner_radius_top_right = int(count_diameter * 0.5)
	count_style.corner_radius_bottom_right = int(count_diameter * 0.5)
	count_style.corner_radius_bottom_left = int(count_diameter * 0.5)
	_count_panel.add_theme_stylebox_override("panel", count_style)
	_icon_label.add_theme_font_size_override("font_size", icon_font_size)
	_icon_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_icon_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_icon_label.add_theme_constant_override("outline_size", 3)
	_count_label.add_theme_font_size_override("font_size", count_font_size)
	_count_label.add_theme_color_override("font_color", Color.BLACK)
	_count_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.35))
	_count_label.add_theme_constant_override("outline_size", 1)


## 根据可配置直径排列主圆、单字与右下角数量；尺寸变化后由外层重新调用即可。
func _layout_children() -> void:
	custom_minimum_size = Vector2(badge_diameter, badge_diameter)
	size = custom_minimum_size
	if _circle_panel == null:
		return
	_circle_panel.position = Vector2.ZERO
	_circle_panel.size = Vector2(badge_diameter, badge_diameter)
	_icon_label.position = Vector2.ZERO
	_icon_label.size = Vector2(badge_diameter, badge_diameter)
	# 数量圆位置；略微贴出主圆右下角，仍保持在组件矩形内部避免排列额外留白。
	var count_position: Vector2 = Vector2(badge_diameter - count_diameter, badge_diameter - count_diameter)
	_count_panel.position = count_position
	_count_panel.size = Vector2(count_diameter, count_diameter)
	_count_label.position = count_position
	_count_label.size = Vector2(count_diameter, count_diameter)


## 刷新单字、数量与可见性；无有效标记时隐藏整个组件。
func _refresh_content() -> void:
	if not is_node_ready():
		return
	# 标记数量；非正数标记不应占用任何布局空间。
	var count: int = int(_mark_data.get("count", 0))
	visible = count > 0
	if not visible:
		return
	# 标记单字；规则服务已经规范化，表现层仍保留单字符防御性裁剪。
	var icon_text: String = str(_mark_data.get("icon", "?"))
	_icon_label.text = icon_text.substr(0, 1) if not icon_text.is_empty() else "?"
	_count_label.text = str(count)


## 鼠标进入时构建标记详细信息；说明文本完全来自公开快照，不查询技能实例或隐藏状态。
func _on_mouse_entered() -> void:
	if _mark_data.is_empty() or int(_mark_data.get("count", 0)) <= 0:
		return
	# 标记名称；缺失时使用稳定ID，避免空标题信息框。
	var mark_name: String = str(_mark_data.get("name", _mark_data.get("id", "标记")))
	# 标记说明；由创建标记的规则组件提供长期维护文本。
	var description: String = str(_mark_data.get("description", "暂无详细说明。"))
	# 统一信息结构；数量单独放在副标题，正文保持完整机制说明。
	var information: Dictionary = {
		"title":mark_name,
		"title_emphasis":true,
		"subtitle":"标记数：%d" % int(_mark_data.get("count", 0)),
		"description":description,
	}
	information_requested.emit(information, get_global_rect())


## 鼠标离开当前标记时请求关闭属于本来源的信息框。
func _on_mouse_exited() -> void:
	information_dismissed.emit()
