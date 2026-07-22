class_name OpportunityCardView
extends PanelContainer

## 机缘卡牌面组件。牌面不使用插画，只显示规则正文，并用背景与边框颜色表达绿、蓝、紫、橙、红五种品质。

## 玩家点击可选机缘卡时发出稳定卡牌ID；组件不解释或执行任何效果。
signal card_selected(card_id: String)

## 正式机缘卡固定尺寸；宽高参考武将牌比例，三张并列时适配1280×720战斗视口。
@export var card_size: Vector2 = Vector2(180.0, 240.0)

## 当前机缘卡稳定ID；空字符串表示尚未配置，点击不会发出选择。
var _card_id: String = ""

## 当前是否允许点击；等待其他玩家时牌面可保持显示但不会提交动作。
var _interactive: bool = false

## 卡面规则正文；只显示主公提供的机缘描述，不添加插画、标题或额外规则改写。
@onready var _description_label: Label = %DescriptionLabel

## 覆盖整张牌面的透明按钮；输入与视觉分离，正文标签保持纯展示职责。
@onready var _input_button: Button = %InputButton


## 初始化透明输入并应用默认不可交互状态。
func _ready() -> void:
	custom_minimum_size = card_size
	_input_button.pressed.connect(_on_pressed)
	_input_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_interaction_state()


## 配置机缘卡静态快照；card_definition必须来自权威快照或OpportunityCatalog深拷贝。
func configure(card_definition: Dictionary, interactive: bool = true) -> void:
	_card_id = str(card_definition.get("id", ""))
	_interactive = interactive and not _card_id.is_empty()
	_description_label.text = str(card_definition.get("description", ""))
	_apply_quality_style(str(card_definition.get("quality", "green")))
	_refresh_interaction_state()


## 设置当前牌面是否允许提交选择；权威回包前可立即禁用内部按钮，避免快速连点产生重复动作。
func set_interactive(interactive: bool) -> void:
	_interactive = interactive and not _card_id.is_empty()
	_refresh_interaction_state()


## 根据品质应用整张卡面颜色；颜色仅表达稀有度，不改变正文与规则数值。
func _apply_quality_style(quality_id: String) -> void:
	# 品质主色；五种颜色在深色牌桌上保持足够亮度并与武将牌金属边框风格协调。
	var quality_color: Color = {
		"green":Color("3f8f58"),
		"blue":Color("356fa8"),
		"purple":Color("7550a8"),
		"orange":Color("b66a2f"),
		"red":Color("a9363f"),
	}.get(quality_id, Color("3f8f58")) as Color
	# 卡面样式；深色品质底面承托白色正文，亮色边框模拟武将牌的正式轮廓。
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = quality_color.darkened(0.42)
	panel_style.border_color = quality_color.lightened(0.30)
	panel_style.set_border_width_all(4)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.shadow_size = 10
	panel_style.shadow_offset = Vector2(0.0, 5.0)
	add_theme_stylebox_override("panel", panel_style)
	_description_label.add_theme_color_override("font_color", Color("fff8e8"))
	_description_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.92))
	_description_label.add_theme_constant_override("outline_size", 4)


## 同步透明按钮禁用状态与牌面明暗；等待状态仍可阅读正文但不会产生悬停误导。
func _refresh_interaction_state() -> void:
	if _input_button == null:
		return
	_input_button.disabled = not _interactive
	modulate = Color.WHITE if _interactive else Color(0.72, 0.72, 0.72, 1.0)


## 提交当前稳定卡牌ID；空ID与禁用状态由配置层和按钮共同防御。
func _on_pressed() -> void:
	if _interactive and not _card_id.is_empty():
		card_selected.emit(_card_id)
