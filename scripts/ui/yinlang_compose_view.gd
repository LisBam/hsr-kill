class_name YinlangComposeView
extends VBoxContainer

## 局内外壳样式；只组织面板与按钮层次，不改变规则语义色和内容尺寸。
const BATTLE_STYLE: Script = preload("res://scripts/ui/battle_surface_style.gd")

## 银狼【注入】的组合窗口内容视图。纯 UI 组件：只读取请求上下文里已经准备好的键列表与静态数据池，
## 不读取对局状态、不提交规则动作，也不认识「银狼」「注入」以外的任何技能。
##
## 【布局】左栏是权威随机抽出的两个「时机」按钮，右栏是同一请求里随机抽出的两个「效果」按钮，
## 两栏下方实时预览组合出来的技能正文，最下方是确定与取消。
## 【候选来源】两栏各只展示两个由权威侧随机抽取的候选，界面**不提供**展开完整池的入口：
## 候选数量本身就是平衡设计的一部分，界面若能展开就等于绕过了随机抽取；
## 池子的完整内容属于设计资料，由《内容制作指南》维护，玩家只需要在两个候选里二选一。

## 玩家确认组合时发出完整控制项；由窗口层转成统一选择动作。
signal submitted(control_id: String)

## 玩家放弃本次组合时发出；取消不产生任何技能，也不消耗任何资源。
signal cancelled

## 组合窗口控制项前缀；与控制器常量同源，保证界面拼出的控制项能被权威侧解析。
const CONTROL_PREFIX: String = MatchController.YINLANG_COMPOSE_CONTROL_PREFIX

## 组合窗口控制项的分隔符；与控制器常量同源。
const CONTROL_SEPARATOR: String = MatchController.YINLANG_CONTROL_SEPARATOR

## 左右两栏的标题文本。
const TIMING_COLUMN_TITLE: String = "时机"
const EFFECT_COLUMN_TITLE: String = "效果"

## 候选按钮的最小高度；固定值让两个候选在视觉上等重，不因文本长短而参差不齐。
const OPTION_BUTTON_HEIGHT: float = 48.0

## 确定与取消按钮文本。
const CONFIRM_TEXT: String = "确定"
const CANCEL_TEXT: String = "取消"

## 请求上下文里「候选时机键」的键名；与注入技能写入的字段保持一致。
const CONTEXT_KEY_TIMING_OFFERING: String = "timing_offering"

## 请求上下文里「候选效果键」的键名。
const CONTEXT_KEY_EFFECT_OFFERING: String = "effect_offering"

## 请求上下文里「效果池类别」的键名。
const CONTEXT_KEY_POOL_KIND: String = "pool_kind"

## 时机栏候选按钮容器；每次配置请求时清空重建，按钮数量等于权威随机抽出的候选数。
var _timing_options_box: VBoxContainer

## 效果栏候选按钮容器；每次配置请求时清空重建，按钮数量等于权威随机抽出的候选数。
var _effect_options_box: VBoxContainer

## 时机栏候选按钮；与 `_timing_offering` 下标一一对应，用于按当前选中键刷新外观。
var _timing_buttons: Array[Button] = []

## 效果栏候选按钮；与 `_effect_offering` 下标一一对应，用于按当前选中键刷新外观。
var _effect_buttons: Array[Button] = []

## 时机栏按钮组；保证同一时刻只有一个候选处于选中态，玩家无法同时选中两个时机。
var _timing_group: ButtonGroup

## 效果栏按钮组；保证同一时刻只有一个候选处于选中态，玩家无法同时选中两个效果。
var _effect_group: ButtonGroup

## 组合正文预览标签；实时显示「锁定技，<时机>，<效果>。每回合限一次。」。
var _preview_label: Label

## 确定按钮；两栏都选中后才可点击。
var _confirm_button: Button

## 取消按钮；始终可点击。
var _cancel_button: Button

## 候选时机键；来自请求上下文的权威随机结果，顺序即左栏按钮从上到下的顺序。
var _timing_offering: Array[String] = []

## 候选效果键；来自请求上下文的权威随机结果，顺序即右栏按钮从上到下的顺序。
var _effect_offering: Array[String] = []

## 当前选中的时机键；空字符串表示尚未选择。
var _selected_timing_key: String = ""

## 当前选中的效果键；空字符串表示尚未选择。
var _selected_effect_key: String = ""

## 效果池类别；进程或缺陷，决定右栏读取哪个效果池。
var _pool_kind: String = ""


## 构建完整界面；节点结构在代码中一次性建立，避免为纯代码视图维护一份场景文件。
func _init() -> void:
	add_theme_constant_override("separation", 10)
	_build_columns()
	_build_preview()
	_build_actions()


## 按请求上下文初始化候选；上下文缺失字段时按空池处理，界面仍可取消。
func configure(context: Dictionary) -> void:
	_pool_kind = str(context.get(CONTEXT_KEY_POOL_KIND, ""))
	_timing_offering = _to_string_array(context.get(CONTEXT_KEY_TIMING_OFFERING, []))
	_effect_offering = _to_string_array(context.get(CONTEXT_KEY_EFFECT_OFFERING, []))
	_selected_timing_key = ""
	_selected_effect_key = ""
	_rebuild_timing_options()
	_rebuild_effect_options()
	_refresh_preview()


## 按当前活动 UI 风格刷新全部控件配色；科技黑蓝语义只用于本窗口，不污染其他界面。
func refresh_ui_style() -> void:
	# 候选按钮的统一底色与描边；选中态在下方单独覆盖，因此这里只处理未选中时的常规外观。
	for button: Button in _timing_buttons + _effect_buttons:
		BATTLE_STYLE.apply_interaction_button(button, BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), false)
	# 选中态样式；亮青描边 + 网格底，让「已选中的那一个」在四个按钮里一眼可辨。
	var selected_style: StyleBoxFlat = BATTLE_STYLE.make_panel(BattleUIStyle.get_color("tech_grid"), BattleUIStyle.get_color("tech_accent"), 2, 6)
	for button: Button in _timing_buttons + _effect_buttons:
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("tech_accent"))
	_preview_label.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	for button: Button in [_confirm_button, _cancel_button]:
		BATTLE_STYLE.apply_interaction_button(button, BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), button == _confirm_button)
	_confirm_button.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))


## 建立左右两栏；每栏由标题与纵向排列的候选按钮组成。
func _build_columns() -> void:
	# 两栏横排容器；左右等宽，保证时机与效果在视觉上同等重要。
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	# 时机栏；左侧，承载两个随机时机候选。
	var timing_column: VBoxContainer = _build_column(TIMING_COLUMN_TITLE)
	columns.add_child(timing_column)
	_timing_options_box = VBoxContainer.new()
	_timing_options_box.add_theme_constant_override("separation", 8)
	timing_column.add_child(_timing_options_box)
	# 效果栏；右侧，承载两个随机效果候选。
	var effect_column: VBoxContainer = _build_column(EFFECT_COLUMN_TITLE)
	columns.add_child(effect_column)
	_effect_options_box = VBoxContainer.new()
	_effect_options_box.add_theme_constant_override("separation", 8)
	effect_column.add_child(_effect_options_box)


## 建立一个栏容器；标题在上，候选按钮区占据剩余高度。
func _build_column(title: String) -> VBoxContainer:
	# 栏容器；横向扩展填满一半宽度。
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 栏标题标签；只做分组提示，不参与交互。
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	column.add_child(title_label)
	return column


## 建立正文预览；组合结果实时可见，避免玩家在确认前无法预判技能正文。
func _build_preview() -> void:
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.add_theme_font_size_override("font_size", 17)
	add_child(_preview_label)


## 建立底部操作区；确定在两项都选中前保持禁用。
func _build_actions() -> void:
	# 操作行；确定与取消并排居中。
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	add_child(actions)
	_confirm_button = Button.new()
	_confirm_button.text = CONFIRM_TEXT
	_confirm_button.disabled = true
	_confirm_button.pressed.connect(_on_confirm_pressed)
	actions.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = CANCEL_TEXT
	_cancel_button.pressed.connect(_on_cancel_pressed)
	actions.add_child(_cancel_button)


## 重建时机栏候选按钮；候选来自请求上下文里的权威随机结果，界面不再提供展开完整池的入口。
func _rebuild_timing_options() -> void:
	_timing_group = ButtonGroup.new()
	_timing_buttons = _fill_option_buttons(_timing_options_box, _timing_group, _timing_offering, ZhuruComposePools.get_timing_entries(), _on_timing_option_toggled)


## 重建效果栏候选按钮；候选来自请求上下文里的权威随机结果，界面不再提供展开完整池的入口。
func _rebuild_effect_options() -> void:
	_effect_group = ButtonGroup.new()
	_effect_buttons = _fill_option_buttons(_effect_options_box, _effect_group, _effect_offering, ZhuruComposePools.get_effects(_pool_kind), _on_effect_option_toggled)


## 用候选键填充一栏的按钮区；返回本次建立的按钮数组，下标与传入的键数组一一对应。
## 每个按钮都是互斥开关按钮：同一栏内只能有一个处于选中态，重复点击已选中的按钮不会取消选择。
func _fill_option_buttons(container: VBoxContainer, group: ButtonGroup, keys: Array[String], entries: Array, callback: Callable) -> Array[Button]:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
	# 本次建立的按钮；下标与 keys 一一对应，供刷新外观与回读选中键使用。
	var buttons: Array[Button] = []
	for key: String in keys:
		# 当前候选按钮；文本取池内原文，缺失时回落到稳定键本身，保证按钮文本永不为空。
		var button: Button = Button.new()
		button.text = _resolve_entry_text(entries, key)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0.0, OPTION_BUTTON_HEIGHT)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.toggled.connect(callback.bind(key))
		container.add_child(button)
		buttons.append(button)
	return buttons


## 从池条目里查一个键对应的显示文本；缺失时回落到键本身，保证按钮文本永不为空。
func _resolve_entry_text(entries: Array, key: String) -> String:
	for entry_variant: Variant in entries:
		# 当前池条目；键匹配即返回文本。
		var entry: Dictionary = entry_variant as Dictionary
		if str(entry.get(ZhuruComposePools.KEY_FIELD, "")) == key:
			return str(entry.get(ZhuruComposePools.TEXT_FIELD, key))
	return key


## 刷新预览与确定按钮可用状态。
func _refresh_preview() -> void:
	if _selected_timing_key.is_empty() or _selected_effect_key.is_empty():
		_preview_label.text = "请分别选择时机与效果。"
		_confirm_button.disabled = true
		return
	_preview_label.text = ZhuruComposePools.compose_description(_resolve_entry_text(ZhuruComposePools.get_timing_entries(), _selected_timing_key), _resolve_entry_text(ZhuruComposePools.get_effects(_pool_kind), _selected_effect_key))
	_confirm_button.disabled = false


## 记录左栏选中项；互斥按钮组只会对「被选中的那一个」发出开启事件，因此关闭事件直接忽略。
func _on_timing_option_toggled(toggled_on: bool, key: String) -> void:
	if not toggled_on:
		return
	_selected_timing_key = key
	_refresh_preview()


## 记录右栏选中项；互斥按钮组只会对「被选中的那一个」发出开启事件，因此关闭事件直接忽略。
func _on_effect_option_toggled(toggled_on: bool, key: String) -> void:
	if not toggled_on:
		return
	_selected_effect_key = key
	_refresh_preview()


## 提交组合结果；控制项格式与权威侧解析规则严格一致。
func _on_confirm_pressed() -> void:
	if _selected_timing_key.is_empty() or _selected_effect_key.is_empty():
		return
	submitted.emit("%s%s%s%s" % [CONTROL_PREFIX, _selected_timing_key, CONTROL_SEPARATOR, _selected_effect_key])


## 放弃本次组合。
func _on_cancel_pressed() -> void:
	cancelled.emit()


## 把任意值转成字符串数组；网络传输后的类型可能与本地不同，非数组输入返回空数组。
func _to_string_array(source: Variant) -> Array[String]:
	# 结果数组；只保留可转成字符串的项。
	var result: Array[String] = []
	if not (source is Array):
		return result
	for item_variant: Variant in source as Array:
		result.append(str(item_variant))
	return result
