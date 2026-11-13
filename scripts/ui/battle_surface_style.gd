extends RefCounted

## 战斗外壳样式适配器：复用菜单的主题、按钮状态与边距契约，以更紧凑的圆角组织局内信息层级。
## 实体牌、体力、品质色和限定技三态仍由原组件拥有；本类只供面板、表单和操作区使用。

## 通用表面工厂；共享细描边和按钮对比度计算，避免两套实现逐渐偏离。
const SURFACE_STYLE: Script = preload("res://scripts/ui/menu_visual_style.gd")
## 未传色的哨兵；与共享工厂一致，透明色仍可显式传入。
const UNSET_COLOR: Color = Color(-1.0, -1.0, -1.0, -1.0)
## 战斗面板圆角；默认10像素适合密集牌桌，布局边距保持原规格。
const PANEL_RADIUS: int = 10
## 战斗表面边缘透明度；默认0.42，比局外略强以区分悬浮窗和底部牌桌。
const BORDER_ALPHA: float = 0.42


## 只解析战斗语义，不改变全局活动主题；没有专用键的旧主题按原值回退。
static func get_color(key: String, fallback: Color = Color.WHITE) -> Color:
	return UIStyleRegistry.get_color(BattleUIStyle.get_active_style_id(), "battle_" + key, BattleUIStyle.get_color(key, fallback))


## 构造悬浮面板；颜色由活动主题提供，不修改注册表或传入资源。
static func make_panel(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 1, corner_radius: int = 10) -> StyleBoxFlat:
	# 复用的独立样式；这里只改变绘制属性，不改变最小尺寸或内容边距。
	var style: StyleBoxFlat = SURFACE_STYLE.make_panel(get_color("panel") if background_color == UNSET_COLOR else background_color, border_color, border_width, corner_radius)
	style.set_corner_radius_all(maxi(corner_radius, PANEL_RADIUS))
	# 显式透明边框必须继续透明；叠乘透明度而不是覆盖调用方的alpha。
	var border: Color = BattleUIStyle.get_color("border") if border_color == UNSET_COLOR else border_color
	border.a *= BORDER_ALPHA
	style.border_color = border
	return style


## 构造内嵌外壳；与原接口的9/7像素边距完全一致。
static func make_inset_panel(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 2, corner_radius: int = 6) -> StyleBoxFlat:
	# 默认材质来自主题；调用方仍能传入选牌、科技或透明背景。
	var background: Color = get_color("metal_panel") if background_color == UNSET_COLOR else background_color
	# 仅当前控件持有的样式；不触碰卡牌框架的共享资源。
	var style: StyleBoxFlat = make_panel(background, border_color, border_width, corner_radius)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


## 长条按钮、下拉与输入框共用同一几何；各态只变颜色，不引起表单跳动。
static func make_decade_button(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, emphasized: bool = false) -> StyleBoxFlat:
	return SURFACE_STYLE.make_decade_button(get_color("action_button") if background_color == UNSET_COLOR else background_color, border_color, emphasized)


## 普通按钮样式；保留原12/8像素内容边距，用于非长条按钮的自定义状态。
static func make_button(background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, border_width: int = 1, corner_radius: int = 8) -> StyleBoxFlat:
	# 独立按钮样式；技能和实体牌不通过本方法替换自己的语义色。
	var style: StyleBoxFlat = BattleUIStyle.make_button(get_color("action_button") if background_color == UNSET_COLOR else background_color, border_color, border_width, corner_radius)
	style.shadow_size = 0
	style.border_color.a *= 0.68
	style.anti_aliasing = true
	return style


## 配置全部原生按钮态；主要命令实色强调，toggle和下拉保留自己的选中语义。
static func apply_interaction_button(button: Button, background_color: Color = UNSET_COLOR, border_color: Color = UNSET_COLOR, emphasized: bool = true) -> void:
	if button == null:
		return
	# 普通局内按钮使用深石墨底，主要操作沿用金色；由共享工厂按实际底色计算文字对比度。
	var background: Color = get_color("action_button") if background_color == UNSET_COLOR else background_color
	# 语义描边保留身份、危险等既有色彩；主要命令使用独立暗金底。
	var border: Color = get_color("accent") if border_color == UNSET_COLOR else border_color
	if emphasized and not button.toggle_mode and not button is OptionButton:
		background = get_color("primary_button", border) if border.is_equal_approx(get_color("accent")) else border
	# 先安装共享交互状态，再覆盖战斗的主色、禁用态与对应字色，避免局外工厂读取战斗上下文。
	SURFACE_STYLE.apply_interaction_button(button, background, border, false)
	button.begin_bulk_theme_override()
	button.add_theme_stylebox_override("normal", make_decade_button(background, border, emphasized))
	button.add_theme_stylebox_override("hover", make_decade_button(background.lightened(0.12), border.lightened(0.12), true))
	button.add_theme_stylebox_override("pressed", make_decade_button(background.darkened(0.10), border, true))
	button.add_theme_stylebox_override("hover_pressed", make_decade_button(background.darkened(0.04), border.lightened(0.12), true))
	button.add_theme_stylebox_override("disabled", make_decade_button(get_color("disabled_button"), get_color("disabled_button_border")))
	button.add_theme_color_override("font_disabled_color", get_color("disabled_button_font"))
	# 焦点只绘制亮色细边，不给键盘焦点叠加浅色背景。
	var focus: StyleBoxFlat = make_decade_button(Color.TRANSPARENT, get_color("accent"), true)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.end_bulk_theme_override()
