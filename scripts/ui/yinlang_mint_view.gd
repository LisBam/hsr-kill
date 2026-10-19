class_name YinlangMintView
extends VBoxContainer

## 银狼【以太】的造牌窗口内容视图。纯 UI 组件：只读取请求上下文里准备好的只读快照，
## 不读取对局状态、不调用规则层判据，最终唯一性与格式仍由造牌端口权威复核。
##
## 【四行交互】第一行输入牌名，第二行选花色，第三行选点数，第四行选要复制的牌。
## 【全部展开而不是下拉】花色、点数与可复制牌都直接铺开成可选按钮：本窗口的候选集合是固定且有限的，
## 下拉框会把「有哪些选择」藏起来，玩家必须先点开才知道能选什么，反而多一次操作。
## 【即时提示】牌名每一次变化都在本地比对上下文里的已有牌名快照并提示；超长与重名会同时禁用
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

## 可复制牌区域的固定高度；牌名按钮铺开后靠滚动容纳，不撑高窗口。
const CARD_AREA_HEIGHT: float = 168.0

## 花色、点数与牌名按钮的最小高度；统一取值让四行在视觉上等重。
const OPTION_BUTTON_HEIGHT: float = 36.0

## 牌名默认值；玩家不输入时就用这个名字，同时作为输入框的占位文本。
## 长度必须不超过 MINT_CARD_NAME_MAX_LENGTH，否则「什么都不填」会直接得到一个超长牌名。
const DEFAULT_NAME_TEXT: String = "自定义名称1"

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

## 牌名输入框；占位文本即默认牌名，玩家点击输入后占位文本自动消失。
var _name_edit: LineEdit

## 牌名提示标签；显示本地即时校验结果与「不输入时用什么名字」。
var _name_hint_label: Label

## 花色候选按钮；与 SUIT_OPTIONS 下标一一对应，用于按当前选中花色刷新外观。
var _suit_buttons: Array[Button] = []

## 花色按钮组；保证同一时刻只有一个花色处于选中态。
var _suit_group: ButtonGroup

## 点数候选按钮；与 MIN_RANK..MAX_RANK 一一对应，用于按当前选中点数刷新外观。
var _rank_buttons: Array[Button] = []

## 点数按钮组；保证同一时刻只有一个点数处于选中态。
var _rank_group: ButtonGroup

## 可复制牌滚动容器；候选数量随卡牌定义增长，必须滚动而不能撑高窗口。
var _card_scroll: ScrollContainer

## 可复制牌分组容器；每个类别一个标题加一个流式按钮区。
var _card_groups_box: VBoxContainer

## 可复制牌按钮；跨类别共用同一个按钮组，因此任意时刻最多只有一张牌处于选中态。
var _card_buttons: Array[Button] = []

## 可复制牌按钮组；跨类别互斥，避免同时选中两张牌。
var _card_group: ButtonGroup

## 确定按钮；牌名不合法（超长 / 重名）或复制目标未选时保持禁用。
var _confirm_button: Button

## 取消按钮；始终可点击。
var _cancel_button: Button

## 已有牌名快照；来自请求上下文的只读数组，用于本地即时重名提示。
var _existing_names: Array[String] = []

## 牌名长度上限；来自请求上下文，与造牌端口使用同一数值。
var _name_max_length: int = MatchController.MINT_CARD_NAME_MAX_LENGTH

## 可复制牌选项；每项含稳定定义ID、显示名与分组类别。
var _copyable_cards: Array[Dictionary] = []

## 当前选中的可复制牌定义ID；空字符串表示尚未选择。
var _selected_definition_id: String = ""

## 当前选中的花色；默认第一个花色，玩家不点选也能确定。
var _selected_suit: String = SUIT_OPTIONS[0]

## 当前选中的点数；默认第一个点数，玩家不点选也能确定。
var _selected_rank: int = MIN_RANK


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
	_selected_suit = SUIT_OPTIONS[0]
	_selected_rank = MIN_RANK
	_name_edit.max_length = _name_max_length
	_name_edit.text = ""
	_apply_suit_selection()
	_apply_rank_selection()
	_rebuild_card_options()
	_refresh_name_hint()
	_refresh_confirm_state()


## 按当前活动 UI 风格刷新全部控件配色；科技黑蓝语义只用于本窗口，不污染其他界面。
func refresh_ui_style() -> void:
	# 候选按钮的统一底色与描边；选中态在下方单独覆盖，因此这里只处理未选中时的常规外观。
	for button: Button in _suit_buttons + _rank_buttons + _card_buttons:
		BattleUIStyle.apply_interaction_button(button, BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), false)
	# 选中态样式；亮青描边 + 网格底，让「已选中的那一个」在一排按钮里一眼可辨。
	var selected_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_grid"), BattleUIStyle.get_color("tech_accent"), 2, 6)
	for button: Button in _suit_buttons + _rank_buttons + _card_buttons:
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("tech_accent"))
	# 可复制牌区域背景；与候选按钮的底色一致，形成一块「牌名池」面板。
	_card_scroll.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), 1, 6))
	# 输入框样式；深蓝底与蓝青描边，聚焦时描边换成强调色。
	_name_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), 1, 4))
	_name_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_accent"), 2, 4))
	_name_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	_name_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("tech_accent"))
	_name_edit.add_theme_color_override("font_placeholder_color", BattleUIStyle.get_color("text_muted"))
	for button: Button in [_confirm_button, _cancel_button]:
		BattleUIStyle.apply_interaction_button(button, BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_border"), button == _confirm_button)
	_confirm_button.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	_refresh_name_hint()


## 建立牌名输入行；输入变化时立即刷新本地提示。
func _build_name_row() -> void:
	# 行容器；标签在左、输入框在右。
	var row: HBoxContainer = _build_row("牌名")
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 输入框上限先按默认口径设好；configure() 会用上下文里的上限再覆盖一次。
	# 之所以在构建时就设：即使将来有调用方忘记调 configure()，输入框也不会退化成「不限长度」，
	# 本地判据与权威端口仍然会拒绝超长牌名，界面不会出现「能输入但提交必然被拒」的错觉。
	_name_edit.max_length = _name_max_length
	# 占位文本就是默认牌名：玩家不输入时按这个名字造牌，开始输入后占位文本自然消失。
	_name_edit.placeholder_text = DEFAULT_NAME_TEXT
	_name_edit.text_changed.connect(_on_name_changed)
	row.add_child(_name_edit)
	# 提示标签；单独一行显示，避免长提示挤压输入框。
	_name_hint_label = Label.new()
	_name_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_hint_label.add_theme_font_size_override("font_size", 15)
	add_child(_name_hint_label)


## 建立花色选择行；四个花色全部铺开成互斥按钮，不需要先点开下拉框。
func _build_suit_row() -> void:
	# 行容器；标签在左、花色按钮在右。
	var row: HBoxContainer = _build_row("花色")
	_suit_group = ButtonGroup.new()
	for suit: String in SUIT_OPTIONS:
		# 当前花色按钮；文本同时给出符号与中文名，避免只靠符号区分红黑。
		var button: Button = Button.new()
		button.text = "%s %s" % [str(SUIT_SYMBOLS.get(suit, "?")), str(SUIT_NAMES.get(suit, suit))]
		button.toggle_mode = true
		button.button_group = _suit_group
		button.custom_minimum_size = Vector2(0.0, OPTION_BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(_on_suit_toggled.bind(suit))
		row.add_child(button)
		_suit_buttons.append(button)


## 建立点数选择行；13 个点数全部铺开成互斥按钮，一行内均匀分配宽度。
func _build_rank_row() -> void:
	# 行容器；标签在左、点数按钮在右。
	var row: HBoxContainer = _build_row("点数")
	_rank_group = ButtonGroup.new()
	for rank: int in range(MIN_RANK, MAX_RANK + 1):
		# 当前点数按钮；文本用牌面字符，13 个按钮共享一行，因此字号小于其它行。
		var button: Button = Button.new()
		button.text = _rank_text(rank)
		button.toggle_mode = true
		button.button_group = _rank_group
		button.custom_minimum_size = Vector2(0.0, OPTION_BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.toggled.connect(_on_rank_toggled.bind(rank))
		row.add_child(button)
		_rank_buttons.append(button)


## 建立可复制牌选择行；按「基本牌 → 锦囊牌 → 装备牌」分组，组内牌名全部铺开成按钮。
func _build_card_row() -> void:
	# 行容器；标签在左、牌名按钮区在右。
	var row: HBoxContainer = _build_row("效果")
	_card_scroll = ScrollContainer.new()
	_card_scroll.custom_minimum_size = Vector2(0.0, CARD_AREA_HEIGHT)
	_card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_card_scroll)
	_card_groups_box = VBoxContainer.new()
	_card_groups_box.add_theme_constant_override("separation", 6)
	_card_groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_scroll.add_child(_card_groups_box)


## 建立底部操作区；确定在牌名与复制目标都有效前保持禁用。
## 牌名有默认值，因此「确定」的可用性只取决于默认名是否可用与是否已选复制目标。
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


## 重建可复制牌按钮区；每个类别一个标题加一个流式按钮区，牌名逐张铺开供玩家点选。
## 全部按钮共用同一个按钮组，因此跨类别也只能选中一张牌。
func _rebuild_card_options() -> void:
	for child: Node in _card_groups_box.get_children():
		_card_groups_box.remove_child(child)
		child.queue_free()
	_card_buttons.clear()
	_card_group = ButtonGroup.new()
	for type_key: String in ["basic", "trick", "equipment"]:
		# 当前类别的候选牌；为空时不插入分组标题，避免出现空分组。
		var type_cards: Array[Dictionary] = []
		for card: Dictionary in _copyable_cards:
			if str(card.get("type", "")) == type_key:
				type_cards.append(card)
		if type_cards.is_empty():
			continue
		# 分组标题标签；只做分组提示，不参与交互。
		var group_label: Label = Label.new()
		group_label.text = "— %s —" % str(TYPE_GROUP_TITLES.get(type_key, type_key))
		group_label.add_theme_font_size_override("font_size", 15)
		_card_groups_box.add_child(group_label)
		# 流式按钮容器；牌名按钮自动换行铺开，窗口宽度变化时不需要改动这里的代码。
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		_card_groups_box.add_child(flow)
		for card: Dictionary in type_cards:
			# 当前被复制牌按钮；点击即在「效果」一栏里选中这张牌。
			var card_id: String = str(card.get("id", ""))
			var button: Button = Button.new()
			button.text = str(card.get("name", card_id))
			button.toggle_mode = true
			button.button_group = _card_group
			button.custom_minimum_size = Vector2(0.0, OPTION_BUTTON_HEIGHT)
			button.toggled.connect(_on_card_toggled.bind(card_id))
			flow.add_child(button)
			_card_buttons.append(button)


## 按当前花色刷新按钮选中态；默认第一个花色，玩家不点选也能确定。
func _apply_suit_selection() -> void:
	# 当前花色在选项表里的下标；越界时按第一个处理，保证始终有一个花色处于选中态。
	var selected_index: int = maxi(SUIT_OPTIONS.find(_selected_suit), 0)
	for index: int in range(_suit_buttons.size()):
		_suit_buttons[index].set_pressed_no_signal(index == selected_index)


## 按当前点数刷新按钮选中态；默认第一个点数，玩家不点选也能确定。
func _apply_rank_selection() -> void:
	# 当前点数在按钮数组里的下标；与 MIN_RANK 的偏移在此处还原。
	var selected_index: int = clampi(_selected_rank - MIN_RANK, 0, _rank_buttons.size() - 1)
	for index: int in range(_rank_buttons.size()):
		_rank_buttons[index].set_pressed_no_signal(index == selected_index)


## 刷新牌名提示；本地即时提示与权威判据使用同一套规则。
## 提示文案与确定按钮的禁用条件共用 `_name_rejection_reason()`，因此不会出现「提示说重名、按钮却能点」的不一致。
func _refresh_name_hint() -> void:
	# 本地判据给出的拒绝原因；空字符串表示当前牌名可用。
	var rejection_reason: String = _name_rejection_reason()
	if rejection_reason.is_empty():
		_name_hint_label.text = "牌名可用。" if not _is_using_default_name() else "不输入牌名时使用默认牌名「%s」。" % DEFAULT_NAME_TEXT
		_name_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
		return
	# 空输入不再是错误状态：牌名有默认值，此时提示的是「默认牌名为什么不可用」，用危险色。
	_name_hint_label.text = rejection_reason
	_name_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger"))


## 判断当前是否处于「玩家没有输入、将使用默认牌名」的状态。
func _is_using_default_name() -> bool:
	return _name_edit == null or _name_edit.text.strip_edges().is_empty()


## 返回本次造牌实际会提交的牌名；玩家没有输入时回落到默认牌名。
## 界面与造牌端口共用这一个口径，避免「提示用的是默认名、提交的却是空名」。
func _effective_name() -> String:
	if _is_using_default_name():
		return DEFAULT_NAME_TEXT
	return _name_edit.text.strip_edges()


## 本地牌名判据；返回空字符串表示可用，否则返回面向玩家的拒绝原因。
## 判据顺序与造牌端口完全一致（长度 → 重名），因此界面提示与权威拒绝理由不会互相矛盾。
## **这只是提前告知**：最终唯一性仍由造牌端口在提交时权威复核，界面不构成第二套判定标准。
func _name_rejection_reason() -> String:
	# 本次实际会提交的牌名；空输入已经回落到默认牌名，因此这里不再需要「不能为空」分支。
	var normalized_name: String = _effective_name()
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


## 记录花色变化；花色不影响确定按钮可用状态，只影响最终提交的参数。
func _on_suit_toggled(toggled_on: bool, suit: String) -> void:
	if not toggled_on:
		return
	_selected_suit = suit


## 记录点数变化；点数不影响确定按钮可用状态，只影响最终提交的参数。
func _on_rank_toggled(toggled_on: bool, rank: int) -> void:
	if not toggled_on:
		return
	_selected_rank = rank


## 记录被复制牌的选择；跨类别共用一个按钮组，因此点选新牌会自动取消上一张。
func _on_card_toggled(toggled_on: bool, definition_id: String) -> void:
	if not toggled_on:
		return
	_selected_definition_id = definition_id
	_refresh_confirm_state()


## 提交造牌结果；控制项格式与权威侧解析规则严格一致。
func _on_confirm_pressed() -> void:
	# 实际提交的牌名；空输入使用默认牌名，与提示文案共用同一个口径。
	var submitted_name: String = _effective_name()
	if submitted_name.is_empty() or _selected_definition_id.is_empty():
		return
	submitted.emit("%s%s%s%s%s%d%s%s" % [CONTROL_PREFIX, submitted_name, CONTROL_SEPARATOR, _selected_suit, CONTROL_SEPARATOR, _selected_rank, CONTROL_SEPARATOR, _selected_definition_id])


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
