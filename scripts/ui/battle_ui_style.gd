class_name BattleUIStyle
extends RefCounted

## 战斗界面的统一样式工厂。所有动态 UI 组件通过该类复用颜色、圆角、描边与阴影，避免各组件散落视觉魔法数字。

## 桌面最深层背景色；默认使用低明度青黑色以衬托木色面板，运行时无需修改。
const TABLE_BACKGROUND_COLOR: Color = Color("101b1d")

## 桌面中央区域颜色；默认使用墨绿色模拟无名杀牌桌，运行时无需修改。
const TABLE_SURFACE_COLOR: Color = Color("173b35")

## 面板基础颜色；默认使用半透明深褐色形成木质层次，运行时无需修改。
const PANEL_COLOR: Color = Color("342b25e8")

## 面板描边颜色；默认使用低饱和金色统一界面边界，运行时无需修改。
const GOLD_BORDER_COLOR: Color = Color("a8834f")

## 主要交互高亮色；默认使用明亮金色指示已选择与可确认状态，运行时无需修改。
const ACCENT_COLOR: Color = Color("efc76d")

## 合法目标高亮色；默认使用青绿色与选中金色区分，运行时无需修改。
const LEGAL_TARGET_COLOR: Color = Color("61c7a4")

## 危险与错误提示色；默认使用柔和朱红色以保持深色背景可读性，运行时无需修改。
const DANGER_COLOR: Color = Color("e96b63")

## 十周年风格的深色玉石面板；默认用于交互区和技能区，运行时无需修改。
const JADE_PANEL_COLOR: Color = Color("172b27ed")

## 十周年风格的暖黑金属色；默认用于武将框、装备框与顶部信息框，运行时无需修改。
const METAL_PANEL_COLOR: Color = Color("211b18f2")

## 可用主操作按钮的暖金背景色；用于确定、取消和选将确认等同级命令，运行时无需修改。
const ACTION_BUTTON_COLOR: Color = Color("76521f")

## 禁用操作按钮的深灰背景色；固定低亮度让不可提交状态不再沿用可交互高亮，运行时无需修改。
const DISABLED_BUTTON_COLOR: Color = Color("242321")

## 禁用操作按钮的低对比度边框色；与深灰背景共同表达不可点击状态，运行时无需修改。
const DISABLED_BUTTON_BORDER_COLOR: Color = Color("514c45")

## 禁用操作按钮的文字颜色；默认保留足够可读性但明显弱于可用按钮，运行时无需修改。
const DISABLED_BUTTON_FONT_COLOR: Color = Color("77736c")

## 创建通用圆角面板样式；调用方可覆盖背景色、描边色、描边宽度与圆角半径。
static func make_panel(background_color: Color = PANEL_COLOR, border_color: Color = GOLD_BORDER_COLOR, border_width: int = 1, corner_radius: int = 10) -> StyleBoxFlat:
	# 新建的扁平样式；返回后由控件持有并可独立修改。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
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


## 创建按钮样式；不同交互状态只改变背景与描边，不改变组件尺寸。
static func make_button(background_color: Color, border_color: Color, border_width: int = 1, corner_radius: int = 8) -> StyleBoxFlat:
	# 按钮样式；复用面板基础参数后缩小阴影，避免大量按钮产生过重层次。
	var style: StyleBoxFlat = make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


## 创建十周年风格的内嵌面板；双层边距与窄圆角适合武将框、装备栏和操作条。
static func make_inset_panel(background_color: Color = METAL_PANEL_COLOR, border_color: Color = GOLD_BORDER_COLOR, border_width: int = 2, corner_radius: int = 6) -> StyleBoxFlat:
	# 内嵌面板样式；较硬的圆角、深阴影与紧凑边距强调金属框架感。
	var style: StyleBoxFlat = make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	style.content_margin_left = 9.0
	style.content_margin_top = 7.0
	style.content_margin_right = 9.0
	style.content_margin_bottom = 7.0
	return style


## 创建十周年风格的长条操作按钮；上沿高光与窄圆角用于模拟参考扩展的金属按钮层级。
static func make_decade_button(background_color: Color, border_color: Color, emphasized: bool = false) -> StyleBoxFlat:
	# 按钮描边宽度；强调按钮使用2像素金边，普通按钮使用1像素边界。
	var border_width: int = 2 if emphasized else 1
	# 长条按钮样式；保持紧凑内边距，适合操作区并排布局。
	var style: StyleBoxFlat = make_button(background_color, border_color, border_width, 5)
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


## 为规则交互按钮配置完整状态样式；禁用态使用唯一深灰样式，鼠标经过时不会切换到悬停或按下外观。
static func apply_interaction_button(button: Button, background_color: Color = ACTION_BUTTON_COLOR, border_color: Color = ACCENT_COLOR, emphasized: bool = true) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", make_decade_button(background_color, border_color, emphasized))
	button.add_theme_stylebox_override("hover", make_decade_button(background_color.lightened(0.10), border_color.lightened(0.08), emphasized))
	button.add_theme_stylebox_override("pressed", make_decade_button(background_color.darkened(0.12), border_color, emphasized))
	button.add_theme_stylebox_override("focus", make_decade_button(background_color, border_color, emphasized))
	button.add_theme_stylebox_override("disabled", make_decade_button(DISABLED_BUTTON_COLOR, DISABLED_BUTTON_BORDER_COLOR, false))
	button.add_theme_color_override("font_color", Color("f5e5b7"))
	button.add_theme_color_override("font_hover_color", Color("fff2c8"))
	button.add_theme_color_override("font_pressed_color", Color("ead49d"))
	button.add_theme_color_override("font_disabled_color", DISABLED_BUTTON_FONT_COLOR)
