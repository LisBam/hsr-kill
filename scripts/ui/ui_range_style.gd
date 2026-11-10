extends RefCounted

## 原生滑条与滚动条的主题外观；保留数值、步长、方向与输入行为，不使用假按钮替代原生Range。

## 滑条圆形手柄直径；默认16像素，仅纹理尺寸，不改变Slider的触摸区域。
const THUMB_SIZE: int = 16
## 轨道厚度；默认6像素，始终低于现有滑条行高。
const TRACK_SIZE: float = 6.0
## 主题手柄缓存；按RGBA缓存，三个主题切换不重复分配同色纹理。
static var _thumb_cache: Dictionary = {}


## 按控件类型设置完整交互态；调用方负责在主题切换时重入。
static func apply(control: Control) -> void:
	# 主题轨道颜色；所有状态从相同语义生成，不覆盖调用方字体或尺寸。
	var base: Color = BattleUIStyle.get_color("text_primary")
	# 当前强调色；用于已选范围、悬停与焦点反馈。
	var accent: Color = BattleUIStyle.get_color("accent")
	control.begin_bulk_theme_override()
	if control is Slider:
		control.add_theme_stylebox_override("slider", _track(Color(base, 0.12)))
		control.add_theme_stylebox_override("grabber_area", _track(Color(accent, 0.64)))
		control.add_theme_stylebox_override("grabber_area_highlight", _track(Color(accent, 0.90)))
		control.add_theme_icon_override("grabber", _thumb(accent))
		control.add_theme_icon_override("grabber_highlight", _thumb(accent.lightened(0.18)))
		control.add_theme_icon_override("grabber_disabled", _thumb(BattleUIStyle.get_color("disabled_button_font")))
	elif control is ScrollBar:
		for state: String in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			# 原滚动条内容边距；保留原生最小尺寸与末端可达范围，装饰不能缩短滚动距离。
			var original: StyleBox = control.get_theme_stylebox(state)
			# 当前状态颜色；轨道弱化，拖块和交互态逐步增强。
			var color: Color = Color(base, 0.08) if state.begins_with("scroll") else Color(accent, 0.48 if state == "grabber" else 0.82)
			# 独立轨道样式；各边距从宿主原样复制，避免新增空白槽位。
			var style: StyleBoxFlat = _track(color)
			for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				style.set_content_margin(side, original.get_content_margin(side))
			control.add_theme_stylebox_override(state, style)
	control.end_bulk_theme_override()


## 创建无阴影的圆角轨道；边距定义稳定厚度，不影响数值区间。
static func _track(color: Color) -> StyleBoxFlat:
	# 当前状态的独立样式；在主题刷新时创建，鼠标移动只由原生控件切换样式引用。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.content_margin_top = TRACK_SIZE * 0.5
	style.content_margin_bottom = TRACK_SIZE * 0.5
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	return style


## 用径向渐变生成抗锯齿圆形手柄；不依赖外部图片或游戏随机源。
static func _thumb(color: Color) -> Texture2D:
	# 缓存键；包含透明度，禁用态不会误复用高亮纹理。
	var key: String = color.to_html(true)
	if _thumb_cache.has(key):
		return _thumb_cache[key] as Texture2D
	# 径向颜色曲线；大部分半径不透明，最后一小段柔化边缘。
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.78, 0.96, 1.0])
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0), Color(color, 0.0)])
	# 生成纹理；中心到右侧边缘定义半径，横纵使用同样尺寸。
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = THUMB_SIZE
	texture.height = THUMB_SIZE
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_thumb_cache[key] = texture
	return texture
