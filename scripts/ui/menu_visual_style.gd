extends RefCounted

## 局外界面的视觉工厂。保留 BattleUIStyle 的主题来源与内容边距，独立控制柔和边界、圆角和主次操作层级。
## 仅首页及其子页面引用本类，正式牌面、战斗菜单和规则界面继续使用 BattleUIStyle。
## 通用表面补充：战斗外壳经battle_surface_style适配器复用本工厂的按钮与边距；正式牌面仍使用原语义工厂。

## 缺省颜色标记；负通道表示使用活动主题，显式透明色不会被替换。
const UNSET_COLOR: Color = Color(-1.0, -1.0, -1.0, -1.0)
## 面板描边透明度；0至1，默认0.30避免多重金框争夺注意力，运行时无需修改。
const PANEL_BORDER_OPACITY: float = 0.30
## 普通按钮描边透明度；0至1，默认0.48区分按钮与不可点击的内容面板。
const BUTTON_BORDER_OPACITY: float = 0.48
## 局外面板圆角下限；默认12逻辑像素，按钮使用独立的10像素圆角。
const PANEL_RADIUS: int = 12
## 按钮圆角；默认10逻辑像素，所有按钮状态保持相同几何以避免抖动。
const BUTTON_RADIUS: int = 10
## 外框阴影半径；默认18逻辑像素，仅外层保留阴影，内层可沿用调用方的去阴影策略。
const PANEL_SHADOW_SIZE: int = 18


## 创建局外内容面板；参数与通用工厂一致，保持既有布局边距及背景透明度。
static func make_panel(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 1, corner_radius: int = 10) -> StyleBoxFlat:
	# 独立样式副本；不修改战斗控件持有的资源。
	var style: StyleBoxFlat = BattleUIStyle.make_panel(background_color, border_color, mini(border_width, 1), maxi(corner_radius, PANEL_RADIUS))
	style.border_color.a *= PANEL_BORDER_OPACITY
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = PANEL_SHADOW_SIZE
	style.shadow_offset = Vector2(0.0, 6.0)
	style.anti_aliasing = true
	return style


## 创建局外页面框架或模态；保留原9/7像素内边距，避免改变设置表单和列表的可用高度。
static func make_inset_panel(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 2, corner_radius: int = 6) -> StyleBoxFlat:
	# 默认金属背景；外部传入的面板和透明背景原样保留。
	var background: Color = BattleUIStyle.get_color("metal_panel") if background_color == UNSET_COLOR else background_color
	# 当前页面框架；边距与 BattleUIStyle.make_inset_panel 一致。
	var style: StyleBoxFlat = make_panel(background, border_color, border_width, corner_radius)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


## 创建尺寸稳定的按钮或输入框状态；emphasized仅决定边框强度，不会自行改变调用方的选中底色。
static func make_decade_button(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, emphasized: bool = false) -> StyleBoxFlat:
	# 基础按钮样式；沿用13/6像素内容边距，避免输入框和固定高度按钮增高。
	var style: StyleBoxFlat = BattleUIStyle.make_decade_button(background_color, border_color, emphasized)
	style.set_border_width_all(1)
	style.set_corner_radius_all(BUTTON_RADIUS)
	style.border_color.a *= 0.90 if emphasized else BUTTON_BORDER_OPACITY
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	style.anti_aliasing = true
	return style


## 配置局外按钮完整状态；主要命令使用强调色实底，切页/模式等toggle按钮继续使用深色选中面。
static func apply_interaction_button(button: Button, background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, emphasized: bool = true) -> void:
	if button == null:
		return
	# 输入背景与描边；颜色始终来自当前主题或调用方显式危险色。
	var background: Color = BattleUIStyle.get_color("action_button") if background_color == UNSET_COLOR else background_color
	# 命令强调色；删除、踢出等调用方可传入危险色。
	var border: Color = BattleUIStyle.get_color("accent") if border_color == UNSET_COLOR else border_color
	# 主按钮资格；导航、复选框和下拉框不使用实心强调底，避免所有控件都像确认按钮。
	var is_primary: bool = emphasized and not button.toggle_mode and not button is OptionButton
	if is_primary:
		background = border
	button.begin_bulk_theme_override()
	button.add_theme_stylebox_override("normal", make_decade_button(background, border, emphasized))
	button.add_theme_stylebox_override("hover", make_decade_button(background.lightened(0.12), border.lightened(0.12), true))
	button.add_theme_stylebox_override("pressed", make_decade_button(background.darkened(0.10), border, true))
	button.add_theme_stylebox_override("hover_pressed", make_decade_button(background.darkened(0.04), border.lightened(0.12), true))
	# 焦点只描边；透明底防止Godot叠加focus样式遮住hover/pressed状态。
	var focus_style: StyleBoxFlat = make_decade_button(Color.TRANSPARENT, BattleUIStyle.get_color("text_primary"), true)
	focus_style.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("disabled", make_decade_button(BattleUIStyle.get_color("disabled_button"), BattleUIStyle.get_color("disabled_button_border")))
	# 主要按钮使用深字以保持金色实底上的对比度，普通按钮使用主题文字语义。
	var text_color: Color = BattleUIStyle.get_color("outer_background") if is_primary else BattleUIStyle.get_color("button_font")
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color if is_primary else BattleUIStyle.get_color("button_hover_font"))
	button.add_theme_color_override("font_pressed_color", text_color if is_primary else BattleUIStyle.get_color("button_pressed_font"))
	button.add_theme_color_override("font_hover_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", BattleUIStyle.get_color("disabled_button_font"))
	button.end_bulk_theme_override()
