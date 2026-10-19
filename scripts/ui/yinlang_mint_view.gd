class_name YinlangMintView
extends VBoxContainer

## 银狼【以太】的造牌窗口内容视图。纯 UI 组件：只读取请求上下文里准备好的只读快照，
## 不读取对局状态、不调用规则层判据，最终唯一性与格式仍由造牌端口权威复核。
##
## 【四行交互】第一行输入牌名，第二行选花色，第三行选点数，第四行选要复制的牌。
## 【即时提示】牌名每一次变化都在本地比对上下文里的已有牌名快照并提示；空名、超长与重名会同时禁用
## 「确定」，玩家不必靠「点了确定被拒绝」才知道牌名不可用。界面判据与权威判据顺序一致，
## 但**最终唯一性仍由造牌端口在提交时权威复核**，界面不构成第二套判定标准。

## 玩家确认造牌时发出完整控制项；由窗口层转成统一选择动作。
signal submitted(control_id: String)

## 玩家放弃造牌时发出；取消不消耗限定技额度。
signal cancelled

## 造牌窗口控制项前缀；与控制器常量同源，保证界面拼出的控制项能被权威侧解析。
const CONTROL_PREFIX: String = MatchController.YINLANG_MINT_CONTROL_PREFIX

## 造牌窗口控制项的分隔符；与控制器常量同源。
const CONTROL_SEPARATOR: String = MatchController.YINLANG_CONTROL_SEPARATOR

## 可复制的牌列表高度；固定值让长列表滚动而不撑高窗口。
const CARD_LIST_HEIGHT: int = 150

## 花色选项顺序；与牌面符号表的常见顺序一致，界面与文档都不会出现两种排列。
const SUIT_OPTIONS: Array[String] = ["spade", "heart", "club", "diamond"]

## 花色符号；用于把稳定花色 ID 渲染成玩家可辨认的符号。
const SUIT_SYMBOLS: Dictionary = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}

## 花色中文名；与符号同时显示，避免只靠符号区分红黑。
const SUIT_NAMES: Dictionary = {"spade":"黑桃", "heart":"红桃", "club":"梅花", "diamond":"方块"}

## 点数最小值；与 CardInstance.is_valid_rank 的下界一致。
const MIN_RANK: int = 1

## 点数最大值；与 CardInstance.is_valid_rank 的上界一致。
const MAX_RANK: int = 13

## 可复制牌的分组标题；与卡牌类别顺序一致，不得调整。
const TYPE_GROUP_TITLES: Dictionary = {"basic":"基本牌", "trick":"锦囊牌", "equipment":"装备牌"}

## 请求上下文里「已有牌名快照」的键名；与以太技能写入的字段保持一致。
const CONTEXT_KEY_EXISTING_NAMES: String = "existing_card_names"

## 请求上下文里「牌名长度上限」的键名。
const CONTEXT_KEY_NAME_MAX_LENGTH: String = "card_name_max_length"

## 请求上下文里「可选被复制牌」的键名。
const CONTEXT_KEY_COPYABLE_CARDS: String = "copyable_cards"

## 确定与取消按钮文本。
const CONFIRM_TEXT: String = "确定"
const CANCEL_TEXT: String = "取消"

## 牌名输入框。
var _name_edit: LineEdit

## 牌名提示标签；显示本地即时校验结果。
var _name_hint_label: Label

## 花色选择按钮。
var _suit_option: OptionButton

## 点数选择按钮。
var _rank_option: OptionButton

## 可复制牌列表；按类别分组展示，组标题不可选。
var _card_list: ItemList

## 确定按钮；牌名不合法（空名 / 超长 / 重名）或复制目标未选时保持禁用。
var _confirm_button: Button

## 取消按钮；始终可点击。
var _cancel_button: Button

## 已有牌名快照；来自请求上下文的只读数组，用于本地即时重名提示。
var _existing_names: Array[String] = []

## 牌名长度上限；来自请求上下文，与造牌端口使用同一数值。
var _name_max_length: int = MatchController.MINT_CARD_NAME_MAX_LENGTH

## 可复制牌选项；每项含稳定定义ID、显示名与分组类别。
var _copyable_cards: Array[Dictionary] = []

## 列表下标到可复制牌定义ID的映射；组标题占用下标但不写入映射，因此标题行不会被选中提交。
var _card_id_by_index: Dictionary = {}

## 当前选中的可复制牌定义ID；空字符串表示尚未选择。
var _selected_definition_id: String = ""


## 构建完整界面；节点结构在代码中一次性建立，避免为纯代码视图维护一份场景文件。
func _init() -> void:
	add_theme_constant_override("separation", 10)
	_build_name_row()
	_build_suit_row()
	_build_rank_row()
	_build_card_row()
	_build_actions()


## 按请求上下文初始化四行选择；上下文缺失字段时使用安全默认值，界面仍可取消。
func configure(context: Dictionary) -> void:
	_existing_names = _to_string_array(context.get(CONTEXT_KEY_EXISTING_NAMES, []))
	_name_max_length = maxi(int(context.get(CONTEXT_KEY_NAME_MAX_LENGTH, MatchController.MINT_CARD_NAME_MAX_LENGTH)), 1)
	_copyable_cards = _to_dictionary_array(context.get(CONTEXT_KEY_COPYABLE_CARDS, []))
	_selected_definition_id = ""
	_name_edit.max_length = _name_max_length
	_name_edit.text = ""
	_suit_option.select(0)
	_rank_option.select(0)
	_rebuild_card_list()
	_refresh_name_hint()
	_refresh_confirm_state()


## 按当前活动 UI 风格刷新全部控件配色；科技黑蓝语义只用于本窗口，不污染其他界面。
func refresh_ui_style() -> void:
	# 列表背景、描边与文字色；全部走 tech_* 语义键。
	_card_list.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), 1, 6))
	_card_list.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_card_list.add_theme_color_override("font_selected_color", BattleUIStyle.get_color("tech_accent"))
	_card_list.add_theme_stylebox_override("selected", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_grid"), BattleUIStyle.get_color("tech_accent"), 1, 4))
	# 输入框样式；深蓝底与蓝青描边，聚焦时描边换成强调色。
	_name_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), 1, 4))
	_name_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_accent"), 2, 4))
	_name_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	_name_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("tech_accent"))
	for button: Button in [_suit_option, _rank_option, _confirm_button, _cancel_button]:
		BattleUIStyle.apply_interaction_button(button, BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), button == _confirm_button)
	_confirm_button.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	_refresh_name_hint()


## 建立牌名输入行；输入变化时立即刷新本地提示。
func _build_name_row() -> void:
	# 行容器；标签在左、输入框在右。
	var row: HBoxContainer = _build_row("牌名")
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "输入新牌名（不可与已有牌同名）"
	_name_edit.text_changed.connect(_on_name_changed)
	row.add_child(_name_edit)
	# 提示标签；单独一行显示，避免长提示挤压输入框。
	_name_hint_label = Label.new()
	_name_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_hint_label.add_theme_font_size_override("font_size", 15)
	add_child(_name_hint_label)


## 建立花色选择行。
func _build_suit_row() -> void:
	# 行容器；标签在左、下拉框在右。
	var row: HBoxContainer = _build_row("花色")
	_suit_option = OptionButton.new()
	for suit: String in SUIT_OPTIONS:
		_suit_option.add_item("%s %s" % [str(SUIT_SYMBOLS.get(suit, "?")), str(SUIT_NAMES.get(suit, suit))])
	_suit_option.item_selected.connect(_on_suit_selected)
	row.add_child(_suit_option)


## 建立点数选择行。
func _build_rank_row() -> void:
	# 行容器；标签在左、下拉框在右。
	var row: HBoxContainer = _build_row("点数")
	_rank_option = OptionButton.new()
	for rank: int in range(MIN_RANK, MAX_RANK + 1):
		_rank_option.add_item(_rank_text(rank))
	_rank_option.item_selected.connect(_on_rank_selected)
	row.add_child(_rank_option)


## 建立可复制牌选择行；按「基本牌 → 锦囊牌 → 装备牌」分组，组标题为不可选项。
func _build_card_row() -> void:
	# 行容器；标签在左、列表在右。
	var row: HBoxContainer = _build_row("复制")
	_card_list = ItemList.new()
	_card_list.custom_minimum_size = Vector2(0.0, float(CARD_LIST_HEIGHT))
	_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_list.select_mode = ItemList.SELECT_SINGLE
	_card_list.auto_height = false
	_card_list.item_selected.connect(_on_card_selected)
	row.add_child(_card_list)


## 建立底部操作区；确定在牌名与复制目标都有效前保持禁用。
## 初始牌名为空，因此「确定」在玩家开始输入前就是禁用态。
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


## 建立一个「标签 + 控件」行；返回的行容器已加入本视图。
func _build_row(title: String) -> HBoxContainer:
	# 行容器；标签固定宽度使四行左侧对齐。
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	# 行标签；固定宽度保证四个输入控件左边缘对齐。
	var title_label: Label = Label.new()
	title_label.text = title
	title_label.custom_minimum_size = Vector2(64.0, 0.0)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_label)
	return row


## 重建可复制牌列表；每个类别先插入一条不可选的组标题，再插入该类别的牌。
func _rebuild_card_list() -> void:
	_card_list.clear()
	_card_id_by_index.clear()
	for type_key: String in ["basic", "trick", "equipment"]:
		# 当前类别的候选牌；为空时不插入组标题，避免出现空分组。
		var type_cards: Array[Dictionary] = []
		for card: Dictionary in _copyable_cards:
			if str(card.get("type", "")) == type_key:
				type_cards.append(card)
		if type_cards.is_empty():
			continue
		_card_list.add_item("— %s —" % str(TYPE_GROUP_TITLES.get(type_key, type_key)))
		# 组标题不可选；ItemList 通过禁用项实现，点击它不会改变选中项。
		_card_list.set_item_disabled(_card_list.item_count - 1, true)
		for card: Dictionary in type_cards:
			_card_list.add_item(str(card.get("name", card.get("id", ""))))
			_card_id_by_index[_card_list.item_count - 1] = str(card.get("id", ""))


## 刷新牌名提示；本地即时提示与权威判据使用同一套规则。
## 提示文案与确定按钮的禁用条件共用 `_name_rejection_reason()`，因此不会出现「提示说重名、按钮却能点」的不一致。
func _refresh_name_hint() -> void:
	# 本地判据给出的拒绝原因；空字符串表示当前牌名可用。
	var rejection_reason: String = _name_rejection_reason()
	if rejection_reason.is_empty():
		_name_hint_label.text = "牌名可用。"
		_name_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
		return
	# 空名属于「还没开始输入」的中性状态，用次要文字色；其余都是需要玩家修正的错误，用危险色。
	if _name_edit.text.strip_edges().is_empty():
		_name_hint_label.text = rejection_reason
		_name_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
		return
	_name_hint_label.text = rejection_reason
	_name_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger"))


## 本地牌名判据；返回空字符串表示可用，否则返回面向玩家的拒绝原因。
## 判据顺序与造牌端口完全一致（空名 → 超长 → 重名），因此界面提示与权威拒绝理由不会互相矛盾。
## **这只是提前告知**：最终唯一性仍由造牌端口在提交时权威复核，界面不构成第二套判定标准。
func _name_rejection_reason() -> String:
	# 去首尾空白后的牌名；与造牌端口的归一化口径一致。
	var normalized_name: String = _name_edit.text.strip_edges() if _name_edit != null else ""
	if normalized_name.is_empty():
		return "牌名不能为空，最多 %d 个字。" % _name_max_length
	if normalized_name.length() > _name_max_length:
		return "牌名最多 %d 个字。" % _name_max_length
	if _existing_names.has(normalized_name):
		return "已有同名卡牌，请换一个牌名。"
	return ""


## 刷新确定按钮可用状态；牌名不合法或复制目标未选时禁用。
## 牌名合法性直接复用 `_name_rejection_reason()`，因此重名与超长同样会禁用「确定」，
## 玩家不需要靠「点了确定被拒绝」才知道牌名不可用。
func _refresh_confirm_state() -> void:
	if _confirm_button == null:
		return
	_confirm_button.disabled = not _name_rejection_reason().is_empty() or _selected_definition_id.is_empty()


## 把点数转换为牌面字符；与牌面显示口径一致。
func _rank_text(rank: int) -> String:
	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))


## 记录牌名变化并刷新提示与确定按钮。
func _on_name_changed(_new_text: String) -> void:
	_refresh_name_hint()
	_refresh_confirm_state()


## 记录花色变化；花色不影响确定按钮可用状态。
func _on_suit_selected(_index: int) -> void:
	pass


## 记录点数变化；点数不影响确定按钮可用状态。
func _on_rank_selected(_index: int) -> void:
	pass


## 记录可复制牌选择；组标题没有映射，因此点标题不会改变已选目标。
func _on_card_selected(index: int) -> void:
	if not _card_id_by_index.has(index):
		return
	_selected_definition_id = str(_card_id_by_index[index])
	_refresh_confirm_state()


## 提交造牌结果；控制项格式与权威侧解析规则严格一致。
func _on_confirm_pressed() -> void:
	# 归一化后的牌名；与造牌端口一致地去掉首尾空白。
	var normalized_name: String = _name_edit.text.strip_edges()
	if normalized_name.is_empty() or _selected_definition_id.is_empty():
		return
	# 花色与点数；下拉框下标与选项数组/数值区间的偏移在此处还原。
	var suit: String = SUIT_OPTIONS[clampi(_suit_option.selected, 0, SUIT_OPTIONS.size() - 1)]
	var rank: int = clampi(_rank_option.selected + MIN_RANK, MIN_RANK, MAX_RANK)
	submitted.emit("%s%s%s%s%s%d%s%s" % [CONTROL_PREFIX, normalized_name, CONTROL_SEPARATOR, suit, CONTROL_SEPARATOR, rank, CONTROL_SEPARATOR, _selected_definition_id])


## 放弃本次造牌。
func _on_cancel_pressed() -> void:
	cancelled.emit()


## 把任意值转成字符串数组；非数组输入返回空数组。
func _to_string_array(source: Variant) -> Array[String]:
	# 结果数组；只保留可转成字符串的项。
	var result: Array[String] = []
	if not (source is Array):
		return result
	for item_variant: Variant in source as Array:
		result.append(str(item_variant))
	return result


## 把任意值转成字典数组；非数组输入或非字典项被跳过。
func _to_dictionary_array(source: Variant) -> Array[Dictionary]:
	# 结果数组；只保留字典项。
	var result: Array[Dictionary] = []
	if not (source is Array):
		return result
	for item_variant: Variant in source as Array:
		if item_variant is Dictionary:
			result.append(item_variant as Dictionary)
	return result
