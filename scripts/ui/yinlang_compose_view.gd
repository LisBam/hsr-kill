class_name YinlangComposeView
extends VBoxContainer

## 银狼【注入】的组合窗口内容视图。纯 UI 组件：只读取请求上下文里已经准备好的键列表与静态数据池，
## 不读取对局状态、不提交规则动作，也不认识「银狼」「注入」以外的任何技能。
##
## 【布局】左栏选时机、右栏选效果，底部实时预览组合出来的技能正文，最下方是确定与取消。
## 【候选来源】每栏默认只展示权威随机抽取的若干项，点击「展开全部」后展示该池的完整候选；
## 展开只影响可见数量，不改变任何规则判定，也不重新抽取随机项。

## 玩家确认组合时发出完整控制项；由窗口层转成统一选择动作。
signal submitted(control_id: String)

## 玩家放弃本次组合时发出；取消不产生任何技能，也不消耗任何资源。
signal cancelled

## 两栏候选列表的高度；固定值让「展开全部」只增加滚动内容而不撑高窗口。
const OPTION_LIST_HEIGHT: int = 148

## 组合窗口控制项前缀；与控制器常量同源，保证界面拼出的控制项能被权威侧解析。
const CONTROL_PREFIX: String = MatchController.YINLANG_COMPOSE_CONTROL_PREFIX

## 组合窗口控制项的分隔符；与控制器常量同源。
const CONTROL_SEPARATOR: String = MatchController.YINLANG_CONTROL_SEPARATOR

## 左右两栏的标题文本。
const TIMING_COLUMN_TITLE: String = "时机"
const EFFECT_COLUMN_TITLE: String = "效果"

## 「展开全部」与「收起候选」的按钮文本。
const EXPAND_TEXT: String = "展开全部候选"
const COLLAPSE_TEXT: String = "收起为默认候选"

## 确定与取消按钮文本。
const CONFIRM_TEXT: String = "确定"
const CANCEL_TEXT: String = "取消"

## 请求上下文里「默认候选时机键」的键名；与注入技能写入的字段保持一致。
const CONTEXT_KEY_TIMING_OFFERING: String = "timing_offering"

## 请求上下文里「默认候选效果键」的键名。
const CONTEXT_KEY_EFFECT_OFFERING: String = "effect_offering"

## 请求上下文里「效果池类别」的键名。
const CONTEXT_KEY_POOL_KIND: String = "pool_kind"

## 时机栏候选列表；展示时机键对应的玩家可见文本。
var _timing_list: ItemList

## 效果栏候选列表；展示效果键对应的玩家可见文本。
var _effect_list: ItemList

## 时机栏展开按钮；在默认候选与完整池之间切换。
var _timing_expand_button: Button

## 效果栏展开按钮；在默认候选与完整池之间切换。
var _effect_expand_button: Button

## 组合正文预览标签；实时显示「锁定技，<时机>，<效果>。每回合限一次。」。
var _preview_label: Label

## 确定按钮；两栏都选中后才可点击。
var _confirm_button: Button

## 取消按钮；始终可点击。
var _cancel_button: Button

## 默认候选时机键；来自请求上下文的权威随机结果。
var _timing_offering: Array[String] = []

## 默认候选效果键；来自请求上下文的权威随机结果。
var _effect_offering: Array[String] = []

## 当前是否已展开时机栏完整池。
var _timing_expanded: bool = false

## 当前是否已展开效果栏完整池。
var _effect_expanded: bool = false

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
	_timing_expanded = false
	_effect_expanded = false
	_selected_timing_key = ""
	_selected_effect_key = ""
	_rebuild_timing_list()
	_rebuild_effect_list()
	_refresh_preview()


## 按当前活动 UI 风格刷新全部控件配色；科技黑蓝语义只用于本窗口，不污染其他界面。
func refresh_ui_style() -> void:
	# 列表与预览的背景、描边与文字色；全部走 tech_* 语义键。
	var list_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), 1, 6)
	_timing_list.add_theme_stylebox_override("panel", list_style)
	_effect_list.add_theme_stylebox_override("panel", list_style)
	_timing_list.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_effect_list.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_timing_list.add_theme_color_override("font_selected_color", BattleUIStyle.get_color("tech_accent"))
	_effect_list.add_theme_color_override("font_selected_color", BattleUIStyle.get_color("tech_accent"))
	_timing_list.add_theme_stylebox_override("selected", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_grid"), BattleUIStyle.get_color("tech_accent"), 1, 4))
	_effect_list.add_theme_stylebox_override("selected", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_grid"), BattleUIStyle.get_color("tech_accent"), 1, 4))
	_preview_label.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	for button: Button in [_timing_expand_button, _effect_expand_button, _confirm_button, _cancel_button]:
		BattleUIStyle.apply_interaction_button(button, BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), button == _confirm_button)
	_confirm_button.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))


## 建立左右两栏；每栏由标题、候选列表与展开按钮组成。
func _build_columns() -> void:
	# 两栏横排容器；左右等宽，保证时机与效果在视觉上同等重要。
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	# 时机栏；左侧，承载时机池候选。
	var timing_column: VBoxContainer = _build_column(TIMING_COLUMN_TITLE)
	columns.add_child(timing_column)
	_timing_list = _create_option_list()
	_timing_list.item_selected.connect(_on_timing_selected)
	timing_column.add_child(_timing_list)
	_timing_expand_button = _create_expand_button(_on_timing_expand_pressed)
	timing_column.add_child(_timing_expand_button)
	# 效果栏；右侧，承载当前类别池候选。
	var effect_column: VBoxContainer = _build_column(EFFECT_COLUMN_TITLE)
	columns.add_child(effect_column)
	_effect_list = _create_option_list()
	_effect_list.item_selected.connect(_on_effect_selected)
	effect_column.add_child(_effect_list)
	_effect_expand_button = _create_expand_button(_on_effect_expand_pressed)
	effect_column.add_child(_effect_expand_button)


## 建立一个栏容器；标题在上，候选列表占据剩余高度。
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


## 创建一个候选列表；固定高度并允许滚动，展开完整池时不会撑高窗口。
func _create_option_list() -> ItemList:
	# 候选列表；单选，选中后立即刷新预览。
	var option_list: ItemList = ItemList.new()
	option_list.custom_minimum_size = Vector2(0.0, float(OPTION_LIST_HEIGHT))
	option_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	option_list.select_mode = ItemList.SELECT_SINGLE
	option_list.allow_reselect = true
	option_list.auto_height = false
	return option_list


## 创建展开按钮；点击后在默认候选与完整池之间切换。
func _create_expand_button(callback: Callable) -> Button:
	# 展开按钮；文本由刷新函数按当前状态写入。
	var button: Button = Button.new()
	button.text = EXPAND_TEXT
	button.pressed.connect(callback)
	return button


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


## 重建时机栏候选；按当前展开状态选择默认候选或完整池。
func _rebuild_timing_list() -> void:
	# 候选键；展开时使用完整池，否则使用权威随机提供的默认候选。
	var keys: Array[String] = _collect_pool_keys(ComposedSkillPools.get_timing_entries()) if _timing_expanded else _timing_offering
	_fill_option_list(_timing_list, keys, ComposedSkillPools.get_timing_entries(), _selected_timing_key)
	_timing_expand_button.text = COLLAPSE_TEXT if _timing_expanded else EXPAND_TEXT


## 重建效果栏候选；按当前展开状态选择默认候选或当前类别池。
func _rebuild_effect_list() -> void:
	# 候选键；展开时使用完整池，否则使用权威随机提供的默认候选。
	var keys: Array[String] = _collect_pool_keys(ComposedSkillPools.get_effects(_pool_kind)) if _effect_expanded else _effect_offering
	_fill_option_list(_effect_list, keys, ComposedSkillPools.get_effects(_pool_kind), _selected_effect_key)
	_effect_expand_button.text = COLLAPSE_TEXT if _effect_expanded else EXPAND_TEXT


## 从池条目数组收集全部键。
func _collect_pool_keys(entries: Array) -> Array[String]:
	# 结果键；保持数据池声明顺序，界面顺序因此与文档表格一致。
	var result: Array[String] = []
	for entry_variant: Variant in entries:
		result.append(str((entry_variant as Dictionary).get(ComposedSkillPools.KEY_FIELD, "")))
	return result


## 用键列表填充候选列表；显示文本从对应池条目读取，缺失时回落到键本身。
func _fill_option_list(option_list: ItemList, keys: Array[String], entries: Array, selected_key: String) -> void:
	option_list.clear()
	# 选中下标；-1 表示当前没有任何选中项。
	var selected_index: int = -1
	for key: String in keys:
		option_list.add_item(_resolve_entry_text(entries, key))
		if key == selected_key:
			selected_index = option_list.item_count - 1
	if selected_index >= 0:
		option_list.select(selected_index)


## 从池条目里查一个键对应的显示文本；缺失时回落到键本身，保证列表项永不为空。
func _resolve_entry_text(entries: Array, key: String) -> String:
	for entry_variant: Variant in entries:
		# 当前池条目；键匹配即返回文本。
		var entry: Dictionary = entry_variant as Dictionary
		if str(entry.get(ComposedSkillPools.KEY_FIELD, "")) == key:
			return str(entry.get(ComposedSkillPools.TEXT_FIELD, key))
	return key


## 刷新预览与确定按钮可用状态。
func _refresh_preview() -> void:
	if _selected_timing_key.is_empty() or _selected_effect_key.is_empty():
		_preview_label.text = "请分别选择时机与效果。"
		_confirm_button.disabled = true
		return
	_preview_label.text = ComposedSkillPools.compose_description(_resolve_entry_text(ComposedSkillPools.get_timing_entries(), _selected_timing_key), _resolve_entry_text(ComposedSkillPools.get_effects(_pool_kind), _selected_effect_key))
	_confirm_button.disabled = false


## 记录时机栏选中项。
func _on_timing_selected(index: int) -> void:
	# 当前可见键列表；与列表项下标一一对应。
	var keys: Array[String] = _collect_pool_keys(ComposedSkillPools.get_timing_entries()) if _timing_expanded else _timing_offering
	if index < 0 or index >= keys.size():
		return
	_selected_timing_key = keys[index]
	_refresh_preview()


## 记录效果栏选中项。
func _on_effect_selected(index: int) -> void:
	# 当前可见键列表；与列表项下标一一对应。
	var keys: Array[String] = _collect_pool_keys(ComposedSkillPools.get_effects(_pool_kind)) if _effect_expanded else _effect_offering
	if index < 0 or index >= keys.size():
		return
	_selected_effect_key = keys[index]
	_refresh_preview()


## 切换时机栏展开状态；已选中的键在重建后保持选中。
func _on_timing_expand_pressed() -> void:
	_timing_expanded = not _timing_expanded
	_rebuild_timing_list()


## 切换效果栏展开状态；已选中的键在重建后保持选中。
func _on_effect_expand_pressed() -> void:
	_effect_expanded = not _effect_expanded
	_rebuild_effect_list()


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
