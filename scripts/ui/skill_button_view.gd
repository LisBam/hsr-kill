class_name SkillButtonView
extends Button

## 可复用的武将技能按钮。组件只展示技能元数据和可用状态，并通过信号请求桌面处理，不直接执行技能效果。

## 技能按钮点击信号；参数为全项目稳定技能 ID。
signal skill_requested(skill_id: String)

## 技能按钮最小宽度；默认118像素可容纳四字技能名与状态，运行时通常无需修改。
@export_range(92.0, 220.0, 1.0) var button_width: float = 118.0

## 技能按钮最小高度；默认44像素形成接近无名杀的紧凑技能控制条，运行时通常无需修改。
@export_range(36.0, 80.0, 1.0) var button_height: float = 44.0

## 当前技能 ID；由 configure 写入，空字符串表示尚未配置。
var skill_id: String = ""

## 当前技能是否已经接入可执行规则；false 时按钮仍可点击查看说明，但不会提交动作。
var is_skill_available: bool = false

## 当前技能是否处于界面选中状态；预留给需要选牌或选目标的主动技能流程。
var is_skill_selected: bool = false

## 当前技能说明文本；用于工具提示和桌面状态提示。
var skill_description: String = ""


## 初始化按钮尺寸、焦点、字体和点击信号。
func _ready() -> void:
	custom_minimum_size = Vector2(button_width, button_height)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_theme_font_size_override("font_size", 14)
	pressed.connect(_on_pressed)
	_refresh_visual_state()


## 写入技能定义和运行时可用状态；技能定义来自 GameDatabase 的深拷贝。
func configure(definition: Dictionary, available: bool = false) -> void:
	skill_id = str(definition.get("id", ""))
	is_skill_available = available
	skill_description = str(definition.get("description", "暂无技能说明。"))
	# 技能名称；缺失时使用稳定 ID，便于发现不完整配置。
	var skill_name: String = str(definition.get("name", skill_id))
	# 状态文本；已接入技能显示“可发动”，预留技能明确标注“预留”。
	var state_text: String = "可发动" if is_skill_available else "预留"
	text = "%s  ·  %s" % [skill_name, state_text]
	tooltip_text = "【%s】\n%s\n\n状态：%s" % [skill_name, skill_description, "已接入规则" if is_skill_available else "界面已预留，规则尚未接入"]
	_refresh_visual_state()


## 更新技能选中状态；后续主动技能进入选牌或选目标流程时可复用该视觉。
func set_selected_state(selected: bool) -> void:
	is_skill_selected = selected
	_refresh_visual_state()


## 将按钮点击转换为稳定技能 ID 信号，具体处理由桌面或未来技能交互控制器决定。
func _on_pressed() -> void:
	if not skill_id.is_empty():
		skill_requested.emit(skill_id)


## 根据可用、预留与选中状态刷新按钮颜色；预留按钮保持可点击以允许查看说明。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 技能背景色；可发动技能使用青绿色，预留技能使用低饱和木褐色。
	var background_color: Color = Color("315d51") if is_skill_available else Color("413931")
	# 技能边框色；选中状态优先使用金色，否则按可用状态区分。
	var border_color: Color = BattleUIStyle.ACCENT_COLOR if is_skill_selected else (BattleUIStyle.LEGAL_TARGET_COLOR if is_skill_available else Color("81715d"))
	# 技能描边宽度；选中时使用3像素，普通状态使用1像素。
	var border_width: int = 3 if is_skill_selected else 1
	add_theme_color_override("font_color", Color("f0e5d1") if is_skill_available else Color("c2b5a3"))
	add_theme_color_override("font_hover_color", Color("fff2d2"))
	add_theme_stylebox_override("normal", BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("hover", BattleUIStyle.make_button(background_color.lightened(0.09), border_color.lightened(0.12), maxi(border_width, 2), 9))
	add_theme_stylebox_override("pressed", BattleUIStyle.make_button(background_color.darkened(0.07), BattleUIStyle.ACCENT_COLOR, 3, 9))

