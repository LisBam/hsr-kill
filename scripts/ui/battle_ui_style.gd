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

