class_name SkillButtonView
extends Button

## 可复用的武将技能按钮。组件只展示技能元数据和可用状态，并通过信号请求桌面处理，不直接执行技能效果。

## 限定技尚未满足发动条件时相对可发动红色的加深比例；默认0.18只表达暂时不可用，不与已发动状态混淆。
const LIMITED_SKILL_UNAVAILABLE_DARKENING: float = 0.18

## 限定技已经发动后相对通用禁用底色的加深比例；默认0.42形成明显深灰且仍保留按钮轮廓。
const LIMITED_SKILL_USED_BACKGROUND_DARKENING: float = 0.42

## 限定技已经发动后相对通用禁用描边的加深比例；默认0.25让深灰边框弱于未发动状态。
const LIMITED_SKILL_USED_BORDER_DARKENING: float = 0.25

## 技能按钮点击信号；参数为全项目稳定技能 ID。
signal skill_requested(skill_id: String)

## 鼠标进入技能按钮时发出的统一信息请求；内容字典与按钮全局矩形由牌桌信息框组件消费。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开技能按钮或节点退出场景树时发出的统一信息关闭请求。
signal information_dismissed

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

## 当前技能受限次数完整说明；空字符串表示此技能没有局内总共、每回合或每轮次数限制。
var skill_limit_description: String = ""

## 当前技能完整显示名副本；按钮正文只显示前两个字，统一信息框使用该字段显示完整名称。
var _skill_display_name: String = ""

## 当前技能是否为轮回技；悬浮信息框据此决定是否按轮回节切换字体颜色。
var _is_reincarnation_skill: bool = false

## 当前轮回节零基索引；局内从玩家公开快照读取，局外或状态缺失时默认为①对应的0。
var _reincarnation_section_index: int = 0

## 当前轮回技已完成并进入的轮回数；局内从玩家公开快照读取，局外或状态缺失时默认为初始值1。
var _reincarnation_round_count: int = 1

## 当前技能是否为限定技；true时按钮使用红色可发动、深红暂不可发动和深灰已发动三态视觉。
var _is_limited_skill: bool = false

## 当前限定技是否已经消耗固有发动额度；普通技能始终为false，不改变原有可用与禁用样式。
var _is_limited_skill_used: bool = false


## 初始化按钮尺寸、焦点、字体和点击信号。
func _ready() -> void:
	custom_minimum_size = Vector2(button_width, button_height)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_skill_available else Control.CURSOR_ARROW
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_theme_font_size_override("font_size", 14)
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_information_mouse_entered)
	mouse_exited.connect(_on_information_mouse_exited)
	_refresh_visual_state()


## 写入技能定义和运行时可用状态；技能定义来自 GameDatabase 的深拷贝。
## 剩余次数由可选参数传入，局内获得且受限的技能会在按钮第二行显示简写。
## 当前界面规范不在技能按钮正文展示次数；完整次数说明仅用于悬停标题，避免压缩文字影响按钮识别。
func configure(definition: Dictionary, available: bool = false, remaining_uses_description: String = "", reincarnation_state: Dictionary = {}, limited_skill_used: bool = false) -> void:
	skill_id = str(definition.get("id", ""))
	is_skill_available = available
	skill_description = GameDatabase.resolve_card_names_in_text(str(definition.get("description", "暂无技能说明。")))
	skill_limit_description = remaining_uses_description
	_is_reincarnation_skill = bool(definition.get("reincarnation", false))
	_reincarnation_section_index = maxi(int(reincarnation_state.get("section_index", 0)), 0)
	_reincarnation_round_count = maxi(int(reincarnation_state.get("round_count", 1)), 1)
	_is_limited_skill = bool(definition.get("limited", false))
	_is_limited_skill_used = _is_limited_skill and limited_skill_used
	# 技能名称；缺失时使用稳定 ID，便于发现不完整配置。
	var skill_name: String = str(definition.get("name", skill_id))
	# 技能按钮短名称；固定截取前两个字符，完整名称改由统一信息框标题展示。
	var short_skill_name: String = skill_name.substr(0, mini(2, skill_name.length()))
	_skill_display_name = skill_name
	# 当前界面规范不在技能按钮正文展示次数；按钮始终维持稳定的两字名称与14像素字号。
	text = short_skill_name
	add_theme_font_size_override("font_size", 14)
	tooltip_text = ""
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


## 请求在技能按钮附近显示完整名称与技能说明；禁用按钮仍允许查看信息，不再附加“状态：...”副标题。
func _on_information_mouse_entered() -> void:
	if skill_id.is_empty():
		return
	# 统一技能信息；只展示技能名与描述原文，不展示接入状态等开发期调试文案。
	# 当前受限技能把完整次数说明附在技能名后，规则原文始终保持不变。
	# 技能名后的补充说明片段；轮回技固定先标注已轮回次数，次数限制说明始终排在其后。
	var title_suffix_parts: Array[String] = []
	if _is_reincarnation_skill:
		title_suffix_parts.append("轮回%d" % _reincarnation_round_count)
	if not skill_limit_description.is_empty():
		title_suffix_parts.append(skill_limit_description)
	var information_title: String = "【%s】" % _skill_display_name
	if not title_suffix_parts.is_empty():
		information_title += "（%s）" % "；".join(title_suffix_parts)
	var information: Dictionary = {
		"title":information_title,
		"description":skill_description,
		"reincarnation":_is_reincarnation_skill,
		"reincarnation_section_index":_reincarnation_section_index,
	}
	information_requested.emit(information, get_global_rect())


## 鼠标离开技能按钮后关闭由该按钮拥有的信息框。
func _on_information_mouse_exited() -> void:
	information_dismissed.emit()


## 技能栏重建并释放按钮时关闭旧信息，避免节点未收到鼠标离开事件后保留过期说明。
func _exit_tree() -> void:
	information_dismissed.emit()


## 根据可用、禁用与选中状态刷新按钮颜色；不可发动按钮保持静态灰显且不响应点击。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 技能背景色；可发动技能使用主题强调底色，不可发动技能统一使用更暗的中性灰。
	var background_color: Color = BattleUIStyle.get_color("skill_available_background") if is_skill_available else BattleUIStyle.get_color("disabled_button")
	# 技能边框色；选中状态优先使用金色，否则按可用状态区分。
	var border_color: Color = BattleUIStyle.get_color("accent") if is_skill_selected else (BattleUIStyle.get_color("legal_target") if is_skill_available else BattleUIStyle.get_color("disabled_button_border"))
	# 限定技禁用文字色；尚未发动仅加深红色并保持正文清晰，已经发动后改用低对比深灰文字。
	var disabled_font_color: Color = BattleUIStyle.get_color("text_primary") if _is_limited_skill and not _is_limited_skill_used else BattleUIStyle.get_color("disabled_button_font")
	if _is_limited_skill:
		if _is_limited_skill_used:
			background_color = BattleUIStyle.get_color("disabled_button").darkened(LIMITED_SKILL_USED_BACKGROUND_DARKENING)
			border_color = BattleUIStyle.get_color("disabled_button_border").darkened(LIMITED_SKILL_USED_BORDER_DARKENING)
		elif is_skill_available:
			background_color = BattleUIStyle.get_color("danger")
			border_color = BattleUIStyle.get_color("danger").lightened(LIMITED_SKILL_UNAVAILABLE_DARKENING)
		else:
			background_color = BattleUIStyle.get_color("danger").darkened(LIMITED_SKILL_UNAVAILABLE_DARKENING)
			border_color = BattleUIStyle.get_color("danger").darkened(LIMITED_SKILL_UNAVAILABLE_DARKENING)
	# 技能选中描边；限定技只替换普通状态配色，进入选牌或选目标流程后仍保留全技能统一的主题强调色。
	if is_skill_selected:
		border_color = BattleUIStyle.get_color("accent")
	# 技能描边宽度；选中时使用3像素，普通状态使用1像素。
	var border_width: int = 3 if is_skill_selected else 1
	add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary") if is_skill_available else disabled_font_color)
	add_theme_color_override("font_hover_color", BattleUIStyle.get_color("button_hover_font") if is_skill_available else disabled_font_color)
	add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("button_pressed_font") if is_skill_available else disabled_font_color)
	add_theme_color_override("font_disabled_color", disabled_font_color)
	add_theme_stylebox_override("normal", BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("hover", BattleUIStyle.make_button(background_color.lightened(0.09), border_color.lightened(0.12), maxi(border_width, 2), 9) if is_skill_available else BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("pressed", BattleUIStyle.make_button(background_color.darkened(0.07), BattleUIStyle.get_color("accent"), 3, 9) if is_skill_available else BattleUIStyle.make_button(background_color, border_color, border_width, 9))
	add_theme_stylebox_override("disabled", BattleUIStyle.make_button(background_color, border_color, border_width, 9))


## 按当前活动 UI 风格重绘技能按钮；技能定义、可发动状态与选中状态保持不变。
func refresh_ui_style() -> void:
	_refresh_visual_state()
