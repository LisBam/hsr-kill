class_name BattleUIStyle
extends RefCounted

## 战斗界面的统一样式工厂。所有动态 UI 组件通过该类复用颜色、圆角、描边与阴影，避免各组件散落视觉魔法数字。
## 当前实现进一步使用语义键选择活动风格，原有圆角、描边与阴影职责保持不变。

## 可选颜色参数的未设置标记；负通道不会与正常 UI 颜色混淆，样式工厂据此读取当前主题默认值。
const UNSET_COLOR: Color = Color(-1.0, -1.0, -1.0, -1.0)

## 桌面最深层背景色；默认使用低明度青黑色以衬托木色面板，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；新组件必须通过语义键读取活动风格，不得把该常量作为当前主题颜色。
const TABLE_BACKGROUND_COLOR: Color = Color("101b1d")

## 桌面中央区域颜色；默认使用墨绿色模拟无名杀牌桌，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；主题背景由 `UIStyleRegistry` 决定。
const TABLE_SURFACE_COLOR: Color = Color("173b35")

## 面板基础颜色；默认使用半透明深褐色形成木质层次，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时面板应调用 `get_color("panel")`。
const PANEL_COLOR: Color = Color("342b25e8")

## 面板描边颜色；默认使用低饱和金色统一界面边界，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时描边应调用 `get_color("border")`。
const GOLD_BORDER_COLOR: Color = Color("a8834f")

## 主要交互高亮色；默认使用明亮金色指示已选择与可确认状态，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时强调色应调用 `get_color("accent")`。
const ACCENT_COLOR: Color = Color("efc76d")

## 合法目标高亮色；默认使用青绿色与选中金色区分，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时合法目标色应调用 `get_color("legal_target")`。
const LEGAL_TARGET_COLOR: Color = Color("61c7a4")

## 危险与错误提示色；默认使用柔和朱红色以保持深色背景可读性，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时危险色应调用 `get_color("danger")`。
const DANGER_COLOR: Color = Color("e96b63")

## 十周年风格的深色玉石面板；默认用于交互区和技能区，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时应读取 `jade_panel` 语义。
const JADE_PANEL_COLOR: Color = Color("172b27ed")

## 十周年风格的暖黑金属色；默认用于武将框、装备框与顶部信息框，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时应读取 `metal_panel` 语义。
const METAL_PANEL_COLOR: Color = Color("211b18f2")

## 可用主操作按钮的暖金背景色；用于确定、取消和选将确认等同级命令，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时应读取 `action_button` 语义。
const ACTION_BUTTON_COLOR: Color = Color("76521f")

## 禁用操作按钮的深灰背景色；固定低亮度让不可提交状态不再沿用可交互高亮，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时应读取 `disabled_button` 语义。
const DISABLED_BUTTON_COLOR: Color = Color("242321")

## 禁用操作按钮的低对比度边框色；与深灰背景共同表达不可点击状态，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时应读取 `disabled_button_border` 语义。
const DISABLED_BUTTON_BORDER_COLOR: Color = Color("514c45")

## 禁用操作按钮的文字颜色；默认保留足够可读性但明显弱于可用按钮，运行时无需修改。
## 兼容旧调用方的暖木静态回退值；运行时应读取 `disabled_button_font` 语义。
const DISABLED_BUTTON_FONT_COLOR: Color = Color("77736c")

## 主菜单浏览型纵向滚动条的默认宽度；模式列表、卡牌图鉴和资料滚动区共用该几何规格。
const MAIN_MENU_SCROLL_BAR_WIDTH: float = 12.0

## 当前生效的 UI 风格标识；由桌面在初始化和设置变化时写入，组件不直接读取设置菜单节点。
static var _active_style_id: String = UIStyleRegistry.DEFAULT_STYLE_ID


## 切换样式工厂使用的活动风格；该方法只更新配色来源，具体节点由各组件的刷新入口重绘。
static func set_active_style(style_id: String) -> void:
	_active_style_id = UIStyleRegistry.normalize_style_id(style_id)


## 返回当前活动风格标识；配置签名可使用该值确保风格切换时重新构建视觉状态。
static func get_active_style_id() -> String:
	return _active_style_id


## 按稳定语义键返回当前风格颜色；缺失键使用调用方回退色，避免组件因主题数据不完整而无法显示。
static func get_color(key: String, fallback: Color = Color.WHITE) -> Color:
	return UIStyleRegistry.get_color(_active_style_id, key, fallback)


## 返回当前风格是否采用黑白单色化装饰；体力警告等玩法语义色不受该标记影响。
static func is_monochrome() -> bool:
	return UIStyleRegistry.is_monochrome(_active_style_id)


## 创建通用圆角面板样式；调用方可覆盖背景色、描边色、描边宽度与圆角半径。
## 未传入背景或描边时分别使用当前主题的基础面板色与边框色。
static func make_panel(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 1, corner_radius: int = 10) -> StyleBoxFlat:
	# 实际面板背景色；未设置参数通过语义键解析，调用方显式传入的透明色会原样保留。
	var resolved_background_color: Color = get_color("panel") if background_color == UNSET_COLOR else background_color
	# 实际面板描边色；统一使用主题边框语义，避免动态组件保存旧风格常量。
	var resolved_border_color: Color = get_color("border") if border_color == UNSET_COLOR else border_color
	# 新建的扁平样式；返回后由控件持有并可独立修改。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = resolved_background_color
	style.border_color = resolved_border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style


## 为主菜单浏览型纵向滚动条应用统一轨道、拖块与交互态；只改变外观和宽度，不修改滚动范围或当前位置。
static func apply_main_menu_scroll_bar_style(scroll_bar: VScrollBar, scroll_bar_width: float = MAIN_MENU_SCROLL_BAR_WIDTH) -> void:
	if scroll_bar == null:
		return
	scroll_bar.custom_minimum_size.x = scroll_bar_width
	scroll_bar.add_theme_stylebox_override("scroll", make_main_menu_scroll_bar_style(get_color("metal_panel"), get_color("border")))
	scroll_bar.add_theme_stylebox_override("grabber", make_main_menu_scroll_bar_style(get_color("action_button"), get_color("accent")))
	scroll_bar.add_theme_stylebox_override("grabber_highlight", make_main_menu_scroll_bar_style(get_color("action_button").lightened(0.10), get_color("accent").lightened(0.08)))
	scroll_bar.add_theme_stylebox_override("grabber_pressed", make_main_menu_scroll_bar_style(get_color("action_button").darkened(0.10), get_color("accent")))


## 创建贴合纵向轨道两端的主菜单滑条样式；零内容边距保证拖块可抵达最小值与最大值端点。
static func make_main_menu_scroll_bar_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	# 主菜单滑条样式；保留主题色、1像素描边和4像素圆角，并移除影响有效拖动范围的边距与阴影。
	var style: StyleBoxFlat = make_panel(background_color, border_color, 1, 4)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


## 创建按钮样式；不同交互状态只改变背景与描边，不改变组件尺寸。
static func make_button(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 1, corner_radius: int = 8) -> StyleBoxFlat:
	# 按钮样式；复用面板基础参数后缩小阴影，避免大量按钮产生过重层次。
	var style: StyleBoxFlat = make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


## 创建十周年风格的内嵌面板；双层边距与窄圆角适合武将框、装备栏和操作条。
## 当前实现保留相同几何规格，并把默认颜色改为活动主题的金属面板与统一边框语义。
static func make_inset_panel(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 2, corner_radius: int = 6) -> StyleBoxFlat:
	# 实际内嵌面板背景色；金属面板语义用于武将框、装备框与顶部信息框。
	var resolved_background_color: Color = get_color("metal_panel") if background_color == UNSET_COLOR else background_color
	# 实际内嵌面板描边色；沿用当前主题统一边框。
	var resolved_border_color: Color = get_color("border") if border_color == UNSET_COLOR else border_color
	# 内嵌面板样式；较硬的圆角、深阴影与紧凑边距强调金属框架感。
	# 当前主题可以改变材质色，但不会改变该层次与边距结构。
	var style: StyleBoxFlat = make_panel(resolved_background_color, resolved_border_color, border_width, corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	style.content_margin_left = 9.0
	style.content_margin_top = 7.0
	style.content_margin_right = 9.0
	style.content_margin_bottom = 7.0
	return style


## 创建十周年风格的长条操作按钮；上沿高光与窄圆角用于模拟参考扩展的金属按钮层级。
## 当前实现保留按钮比例与边距，默认颜色由活动主题提供。
static func make_decade_button(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, emphasized: bool = false) -> StyleBoxFlat:
	# 实际按钮背景色；未设置时使用当前主题的主操作按钮颜色。
	var resolved_background_color: Color = get_color("action_button") if background_color == UNSET_COLOR else background_color
	# 实际按钮描边色；未设置时使用当前主题的选择强调色。
	var resolved_border_color: Color = get_color("accent") if border_color == UNSET_COLOR else border_color
	# 按钮描边宽度；强调按钮使用2像素金边，普通按钮使用1像素边界。
	# “金边”在可切换主题中对应当前主题的强调色描边。
	var border_width: int = 2 if emphasized else 1
	# 长条按钮样式；保持紧凑内边距，适合操作区并排布局。
	var style: StyleBoxFlat = make_button(resolved_background_color, resolved_border_color, border_width, 5)
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


## 为规则交互按钮配置完整状态样式；禁用态使用唯一深灰样式，鼠标经过时不会切换到悬停或按下外观。
## 当前实现把可用态和禁用态颜色都改为活动主题语义，交互行为保持不变。
static func apply_interaction_button(button: Button, background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, emphasized: bool = true) -> void:
	if button == null:
		return
	# 实际按钮背景色；默认来自主题主操作语义，危险或特殊按钮可显式覆盖。
	var resolved_background_color: Color = get_color("action_button") if background_color == UNSET_COLOR else background_color
	# 实际按钮描边色；默认来自主题强调语义。
	var resolved_border_color: Color = get_color("accent") if border_color == UNSET_COLOR else border_color
	button.add_theme_stylebox_override("normal", make_decade_button(resolved_background_color, resolved_border_color, emphasized))
	button.add_theme_stylebox_override("hover", make_decade_button(resolved_background_color.lightened(0.10), resolved_border_color.lightened(0.08), emphasized))
	button.add_theme_stylebox_override("pressed", make_decade_button(resolved_background_color.darkened(0.12), resolved_border_color, emphasized))
	button.add_theme_stylebox_override("focus", make_decade_button(resolved_background_color, resolved_border_color, emphasized))
	button.add_theme_stylebox_override("disabled", make_decade_button(get_color("disabled_button"), get_color("disabled_button_border"), false))
	button.add_theme_color_override("font_color", get_color("button_font"))
	button.add_theme_color_override("font_hover_color", get_color("button_hover_font"))
	button.add_theme_color_override("font_pressed_color", get_color("button_pressed_font"))
	button.add_theme_color_override("font_disabled_color", get_color("disabled_button_font"))
