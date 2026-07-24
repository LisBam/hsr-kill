class_name GameSettlementPanel
extends Control

## 对局结算面板。组件只读取终局快照中的累计统计并渲染列表，不访问或修改权威对局状态。

## 玩家点击右上角唯一关闭按钮时发出；牌桌保留终局快照，以便终局操作区再次打开本面板。
signal close_requested

## 结算面板绘制层级；高于机缘选择与普通选牌层，低于局内菜单和主菜单。
const MODAL_Z_INDEX: int = 220

## 结算表角色列的最小宽度；保留显示名与武将名，窄窗口由外层滚动区域承接。
## 当前标题布局补充：已公开武将名在前、玩家显示名置于全角括号内，二者固定使用同一行文本。
const ROLE_COLUMN_MINIMUM_WIDTH: float = 230.0

## 每项累计统计列的最小宽度；五列保持同宽，避免不同角色行的数值错位。
const STAT_COLUMN_MINIMUM_WIDTH: float = 96.0

## 结算数据行的最小高度；默认38像素，保证多行角色列表在滚动时仍易于辨识。
const STAT_ROW_MINIMUM_HEIGHT: float = 38.0

## 全屏遮罩；阻止面板显示期间误触桌面，但不承担关闭交互。
@onready var _shade: ColorRect = %Shade

## 居中结算框；承载标题、表头、可滚动角色列表与右上角关闭按钮。
@onready var _frame: PanelContainer = %Frame

## 终局标题；标题只描述当前面板，不重复判定胜负文案。
@onready var _title_label: Label = %TitleLabel

## 右上角唯一关闭按钮；只隐藏面板，不清理终局累计数据。
@onready var _close_button: Button = %SettlementCloseButton

## 结算表头容器；角色列与五个统计列的顺序固定，动态行依此顺序创建。
@onready var _header_row: HBoxContainer = %HeaderRow

## 结算角色行容器；每份终局快照重建一次，避免上局角色或统计残留。
@onready var _rows_container: VBoxContainer = %RowsContainer


## 初始化暂停可用的模态面板；终局时规则已停止，但关闭与重开操作仍必须接收输入。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = MODAL_Z_INDEX
	visible = false
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(_on_close_button_pressed)
	refresh_ui_style()


## 根据终局快照显示所有角色的累计战绩；快照缺失玩家时显示空列表而不猜测规则状态。
func show_settlement(snapshot: Dictionary) -> void:
	_render_rows(snapshot)
	visible = true
	move_to_front()


## 隐藏结算面板但保留已渲染数据；再次打开时由最新终局快照重新校正列表。
func hide_settlement() -> void:
	visible = false


## 刷新活动 UI 风格；动态数据行与静态表头都使用同一组主题颜色和按钮样式。
func refresh_ui_style() -> void:
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("accent"), 2, 10))
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_close_button.add_theme_color_override("font_color", BattleUIStyle.get_color("button_font"))
	BattleUIStyle.apply_interaction_button(_close_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), false)
	for header_variant: Variant in _header_row.get_children():
		# 当前表头标签；缺失或替换为非标签节点时忽略，保持组件可嵌入旧场景测试。
		var header_label: Label = header_variant as Label
		if header_label != null:
			header_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
	for row_variant: Variant in _rows_container.get_children():
		# 当前结算行；其面板背景和内部文字都需随主题即时刷新。
		var row: HBoxContainer = row_variant as HBoxContainer
		if row == null:
			continue
		for cell_variant: Variant in row.get_children():
			# 当前结算单元格；所有数据均为公开终局统计，统一使用主要文字色。
			var cell_label: Label = cell_variant as Label
			if cell_label != null:
				cell_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))


## 清空旧行并从玩家快照创建终局统计列表；座次顺序已经由GameState快照稳定排序。
func _render_rows(snapshot: Dictionary) -> void:
	for child: Node in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	for player_variant: Variant in snapshot.get("players", []) as Array:
		# 当前角色终局快照；累计统计由规则层在真实结算点写入，UI只负责显示。
		var player: Dictionary = player_variant as Dictionary
		if player.is_empty():
			continue
		_rows_container.add_child(_create_stat_row(player))
	refresh_ui_style()


## 创建一行角色终局统计；列顺序必须与静态表头一致，不能依赖字典遍历顺序。
func _create_stat_row(player: Dictionary) -> HBoxContainer:
	# 新建统计行；行本身保持透明，边界和层次由列表容器与结算框统一提供。
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, STAT_ROW_MINIMUM_HEIGHT)
	row.add_theme_constant_override("separation", 6)
	# 角色显示名；终局已公开武将，缺失时仍以玩家名保证列表完整。
	var display_name: String = str(player.get("display_name", "玩家"))
	# 武将稳定ID；用于将快照转换为终局时可读的武将名称。
	var character_id: String = str(player.get("character_id", ""))
	# 武将显示名；未知或旧快照缺失时不在角色名后追加无意义占位符。
	var character_name: String = GameDatabase.resolve_character_name(character_id) if not character_id.is_empty() else ""
	# 角色列正文；使用换行显示玩家与武将，使所有角色都能在窄窗口中被识别。
	# 当前排版补充：武将名与玩家名同一行展示，武将名在前，玩家名以全角括号附注，便于逐行比较战绩。
	var role_text: String = "%s（%s）" % [character_name, display_name] if not character_name.is_empty() else display_name
	row.add_child(_create_cell(role_text, ROLE_COLUMN_MINIMUM_WIDTH, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_create_cell(str(int(player.get("total_damage_dealt", 0))), STAT_COLUMN_MINIMUM_WIDTH))
	row.add_child(_create_cell(str(int(player.get("total_damage_received", 0))), STAT_COLUMN_MINIMUM_WIDTH))
	row.add_child(_create_cell(str(int(player.get("total_healing_done", 0))), STAT_COLUMN_MINIMUM_WIDTH))
	row.add_child(_create_cell(str(int(player.get("total_cards_drawn", 0))), STAT_COLUMN_MINIMUM_WIDTH))
	row.add_child(_create_cell(str(int(player.get("total_kill_count", 0))), STAT_COLUMN_MINIMUM_WIDTH))
	return row


## 创建单个不可交互统计单元格；角色列允许左对齐，数值列默认居中以便纵向比较。
func _create_cell(text_value: String, minimum_width: float, alignment: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	# 新建单元格标签；单元格只展示快照数据，不接收鼠标或键盘焦点。
	var cell: Label = Label.new()
	cell.custom_minimum_size = Vector2(minimum_width, STAT_ROW_MINIMUM_HEIGHT)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.text = text_value
	cell.horizontal_alignment = alignment
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.autowrap_mode = TextServer.AUTOWRAP_OFF
	cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cell


## 响应右上角唯一关闭按钮；只关闭本组件，终局操作区会继续保留“结算界面”再次打开入口。
func _on_close_button_pressed() -> void:
	hide_settlement()
	close_requested.emit()
