class_name SkillButtonView
extends Button

## 可复用的武将技能按钮。组件只展示技能元数据和可用状态，并通过信号请求桌面处理，不直接执行技能效果。

## 技能按钮点击信号；参数为全项目稳定技能 ID。
signal skill_requested(skill_id: String)

## 技能按钮最小宽度；默认118像素可容纳四字技能名与状态，运行时通常无需修改。
## 当前牌桌只显示技能名前两个字，因此默认宽度收紧为62像素；该参数只改变按钮命中与排版尺寸，不影响技能规则。
@export_range(48.0, 220.0, 1.0) var button_width: float = 62.0

## 技能按钮最小高度；默认44像素形成接近无名杀的紧凑技能控制条，运行时通常无需修改。
@export_range(36.0, 80.0, 1.0) var button_height: float = 44.0

## 当前技能 ID；由 configure 写入，空字符串表示尚未配置。
var skill_id: String = ""

## 当前技能是否可以从按钮主动发动；false 时按钮禁用并仅通过工具提示展示说明，不提交任何动作。
var is_skill_available: bool = false

## 当前技能是否处于界面选中状态；预留给需要选牌或选目标的主动技能流程。
var is_skill_selected: bool = false

## 当前技能说明文本；用于工具提示和桌面状态提示。
var skill_description: String = ""


## 初始化按钮尺寸、焦点、字体和点击信号。
func _ready() -> void:
	custom_minimum_size = Vector2(button_width, button_height)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_skill_available else Control.CURSOR_ARROW
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
	# 技能触发类型；sample_only 表示仅保留数据接口，其他值代表规则代码已经接入。
	var trigger_type: String = str(definition.get("trigger", "sample_only"))
	# 技能是否配置主动按钮；false 的正式技能按被动技能展示，不错误标记为预留。
	var ui_enabled: bool = bool(definition.get("ui_enabled", false))
	# 技能是否为锁定技；锁定技满足条件时自动执行，不应显示为可点击主动按钮。
	var lock: bool = bool(definition.get("lock", false))
	# 技能按钮短名称；固定截取前两个字符，完整名称继续保留在工具提示中供长期查阅。
	var short_skill_name: String = skill_name.substr(0, mini(2, skill_name.length()))
	# 工具提示状态；完整说明当前技能属于预留、被动、可发动或暂不满足条件。
	var tooltip_status: String = "界面已预留，规则尚未接入" if trigger_type == "sample_only" else ("锁定技已接入规则" if lock else (("当前可发动" if is_skill_available else "当前不满足发动条件") if ui_enabled else "被动技能已接入规则"))
	text = short_skill_name
	tooltip_text = "【%s】\n%s\n\n状态：%s" % [skill_name, skill_description, tooltip_status]
	disabled = not is_skill_available
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_skill_available else Control.CURSOR_ARROW
	_refresh_visual_state()


## 更新技能选中状态；后续主动技能进入选牌或选目标流程时可复用该视觉。
func set_selected_state(selected: bool) -> void:
	is_skill_selected = selected
	_refresh_visual_state()


## 将按钮点击转换为稳定技能 ID 信号，具体处理由桌面或未来技能交互控制器决定。
func _on_pressed() -> void:
	if is_skill_available and not skill_id.is_empty():
		skill_requested.emit(skill_id)


## 根据可用、禁用与选中状态刷新按钮颜色；不可发动按钮保持静态灰显且不响应点击。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 技能背景色；可发动技能使用主题强调底色，不可发动技能统一使用更暗的中性灰。
	var background_color: Color = BattleUIStyle.get_color("skill_available_background") if is_skill_available else BattleUIStyle.get_color("disabled_button")
	# 技能边框色；选中状态优先使用金色，否则按可用状态区分。
	var border_color: Color = BattleUIStyle.get_color("accent") if is_skill_selected else (BattleUIStyle.get_color("legal_target") if is_skill_available else BattleUIStyle.get_color("disabled_button_border"))
	# 技能描边宽度；选中时使用3像素，普通状态使用1像素。
	var border_width: int = 3 if is_skill_selected else 1
	add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary") if is_skill_available else BattleUIStyle.get_color("disabled_button_font"))
	add_theme_color_override("font_hover_color", BattleUIStyle.get_color("button_hover_font") if is_skill_available else BattleUIStyle.get_color("disabled_button_font"))
	add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("button_pressed_font") if is_skill_available else BattleUIStyle.get_color("disabled_button_font"))
	add_theme_color_override("font_disabled_color", BattleUIStyle.get_color("disabled_button_font"))
	add_theme_stylebox_override("normal", BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("hover", BattleUIStyle.make_button(background_color.lightened(0.09), border_color.lightened(0.12), maxi(border_width, 2), 9) if is_skill_available else BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("pressed", BattleUIStyle.make_button(background_color.darkened(0.07), BattleUIStyle.get_color("accent"), 3, 9) if is_skill_available else BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("disabled", BattleUIStyle.make_button(background_color, border_color, border_width, 9))


## 按当前活动 UI 风格重绘技能按钮；技能定义、可发动状态与选中状态保持不变。
func refresh_ui_style() -> void:
	_refresh_visual_state()
