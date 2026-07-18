class_name MatchMenu
extends Control

## 局内菜单组件。该组件只管理菜单显隐和下一局人数输入，通过信号请求桌面执行名称切换或重新开局。

## 请求切换全局卡牌名称模式时发出的信号；实际设置仍由桌面统一调用 GameSettings。
signal card_name_toggle_requested

## 请求重新开局时发出的信号；参数为菜单中设置的下一局玩家人数。
signal restart_requested(player_count: int)

## 标准身份局最少玩家人数；默认2，与 IdentityRules 支持范围一致，运行时无需动态修改。
@export_range(2, 10, 1) var minimum_player_count: int = 2

## 标准身份局最多玩家人数；默认10，与 IdentityRules 支持范围一致，运行时无需动态修改。
@export_range(2, 10, 1) var maximum_player_count: int = 10

## 菜单打开按钮；右上角唯一常驻入口，文字固定为“菜单”。
@onready var _menu_button: Button = %MenuButton

## 菜单内容面板；默认隐藏，点击菜单按钮后切换可见性。
@onready var _menu_panel: PanelContainer = %MenuPanel

## 卡牌名称切换按钮；文字显示当前使用的名称体系。
@onready var _card_name_button: Button = %MenuCardNameButton

## 下一局人数输入框；只保存未来重开参数，不修改当前对局座次。
@onready var _player_count_input: SpinBox = %NextPlayerCountInput

## AI 响应时间滑条；修改全局设置后会立即影响后续 AI 行动与选牌响应，不重开当前对局。
@onready var _ai_response_delay_slider: HSlider = %AiResponseDelaySlider

## AI 响应时间标签；同步显示当前滑条的实际秒数，避免“速度”设置缺少可预期的时间含义。
@onready var _ai_response_delay_label: Label = %AiResponseDelayLabel

## 游戏速度滑条；修改后立即影响后续阶段切换与自动响应的最小等待时间，不重开当前对局。
@onready var _game_speed_slider: HSlider = %GameSpeedSlider

## 游戏速度标签；显示实际流程间隔秒数，明确数值越小则对局推进越快。
@onready var _game_speed_label: Label = %GameSpeedLabel

## UI 风格下拉框；选项来自统一注册表，元数据保存稳定风格标识而不是显示文字。
@onready var _ui_style_option: OptionButton = %UiStyleOption

## 重新开局按钮；点击后携带当前人数设置向桌面发送请求并关闭菜单。
@onready var _restart_button: Button = %MenuRestartButton


## 初始化菜单信号、人数范围和默认关闭状态。
func _ready() -> void:
	# 菜单分支移动到同级节点末尾，使展开面板的输入优先于运行时创建的武将牌和选将遮罩；根节点仍忽略空白区域鼠标。
	call_deferred("_move_to_input_front")
	_menu_button.pressed.connect(_toggle_menu)
	_card_name_button.pressed.connect(card_name_toggle_requested.emit)
	_restart_button.pressed.connect(_request_restart)
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 1.0
	# 人数输入在键入时立即同步 Range 数值，避免玩家直接输入后立刻点击重开时仍读取旧值。
	_player_count_input.update_on_text_changed = true
	_ai_response_delay_slider.min_value = GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.max_value = GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.step = GameSettings.AI_RESPONSE_DELAY_STEP_SECONDS
	_ai_response_delay_slider.value = GameSettings.ai_response_delay_seconds
	_ai_response_delay_slider.value_changed.connect(_on_ai_response_delay_changed)
	GameSettings.ai_response_delay_changed.connect(_refresh_ai_response_delay_text)
	_game_speed_slider.min_value = GameSettings.MIN_GAME_SPEED_INTERVAL_SECONDS
	_game_speed_slider.max_value = GameSettings.MAX_GAME_SPEED_INTERVAL_SECONDS
	_game_speed_slider.step = GameSettings.GAME_SPEED_INTERVAL_STEP_SECONDS
	_game_speed_slider.value = GameSettings.game_speed_interval_seconds
	_game_speed_slider.value_changed.connect(_on_game_speed_changed)
	GameSettings.game_speed_changed.connect(_refresh_game_speed_text)
	_populate_ui_style_options()
	_ui_style_option.item_selected.connect(_on_ui_style_selected)
	GameSettings.ui_style_changed.connect(_refresh_ui_style_selection)
	_menu_panel.visible = false
	refresh_card_name_text()
	_refresh_ai_response_delay_text(GameSettings.ai_response_delay_seconds)
	_refresh_game_speed_text(GameSettings.game_speed_interval_seconds)
	_refresh_ui_style_selection(GameSettings.ui_style_id)
	refresh_ui_style()


## 在父节点完成子节点初始化后提升菜单分支顺序；绘制层级与真实 GUI 命中顺序由同一入口保持一致。
func _move_to_input_front() -> void:
	move_to_front()


## 设置下一局默认人数；桌面初始化时传入控制器检查器配置，之后由玩家在菜单中修改。
func set_next_player_count(player_count: int) -> void:
	_player_count_input.value = clampi(player_count, minimum_player_count, maximum_player_count)


## 返回菜单中设置的下一局人数；始终限制在标准身份局2至10人范围。
func get_next_player_count() -> int:
	# 输入框当前文本；优先读取尚未因焦点切换而提交的键入内容，保证鼠标点击重开时人数准确。
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	# 有效人数；空文本或非数字文本回退到 SpinBox 已确认值，并始终限制在标准身份局范围内。
	var resolved_player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	return clampi(resolved_player_count, minimum_player_count, maximum_player_count)


## 按全局名称模式刷新菜单按钮文字，不创建第二份名称状态。
func refresh_card_name_text() -> void:
	if not is_node_ready():
		return
	_card_name_button.text = "卡牌名称：崩铁杀" if GameSettings.card_name_mode == GameSettings.NameMode.CUSTOM else "卡牌名称：三国杀"


## 使用当前活动主题刷新菜单面板、按钮与文字；该组件不保存任何颜色副本。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_menu_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	BattleUIStyle.apply_interaction_button(_menu_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_card_name_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_restart_button)
	(_menu_panel.get_node("MenuVBox/MenuTitle") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_ai_response_delay_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_game_speed_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/UiStyleRow/UiStyleLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/PlayerCountRow/PlayerCountLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_ui_style_option.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_ui_style_option.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))


## 从注册表构建 UI 风格选项；菜单显示名称可以调整，选中行为始终依赖稳定风格标识。
func _populate_ui_style_options() -> void:
	_ui_style_option.clear()
	for style_id: String in UIStyleRegistry.get_style_ids():
		# 新选项索引；写入元数据后无需通过中文名称反向解析风格。
		var option_index: int = _ui_style_option.item_count
		_ui_style_option.add_item(UIStyleRegistry.get_display_name(style_id))
		_ui_style_option.set_item_metadata(option_index, style_id)


## 按全局设置同步下拉框选中项；使用无信号选择避免主题刷新再次写入相同设置。
func _refresh_ui_style_selection(style_id: String) -> void:
	if not is_node_ready():
		return
	# 已规范化风格标识；未知旧设置会稳定显示默认项。
	var normalized_style_id: String = UIStyleRegistry.normalize_style_id(style_id)
	for option_index: int in range(_ui_style_option.item_count):
		if str(_ui_style_option.get_item_metadata(option_index)) == normalized_style_id:
			_ui_style_option.select(option_index)
			return


## 把玩家选择的稳定风格标识写入全局设置；桌面订阅变化信号后统一刷新全部组件。
func _on_ui_style_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _ui_style_option.item_count:
		return
	GameSettings.set_ui_style(str(_ui_style_option.get_item_metadata(option_index)))


## 更新 AI 响应时间显示；该设置的数值表示每次 AI 进行行动或选择前等待的秒数，数值越小响应越快。
func _refresh_ai_response_delay_text(delay_seconds: float) -> void:
	if not is_node_ready():
		return
	_ai_response_delay_slider.set_value_no_signal(delay_seconds)
	_ai_response_delay_label.text = "AI响应速度：%.2f秒" % delay_seconds


## 将滑条值写入全局 AI 响应设置；控制器通过全局信号更新后续调度，不需要重开对局。
func _on_ai_response_delay_changed(delay_seconds: float) -> void:
	GameSettings.set_ai_response_delay_seconds(delay_seconds)


## 更新游戏速度显示；数值表示阶段切换与自动响应至少等待的秒数，数值越小推进越快。
func _refresh_game_speed_text(interval_seconds: float) -> void:
	if not is_node_ready():
		return
	_game_speed_slider.set_value_no_signal(interval_seconds)
	_game_speed_label.text = "游戏速度：%.1f秒间隔" % interval_seconds


## 将滑条值写入全局游戏速度设置；控制器只对之后创建的调度任务使用新间隔。
func _on_game_speed_changed(interval_seconds: float) -> void:
	GameSettings.set_game_speed_interval_seconds(interval_seconds)


## 切换菜单面板显隐；当前对局继续运行，不改变任何规则状态。
func _toggle_menu() -> void:
	_menu_panel.visible = not _menu_panel.visible


## 发出携带下一局人数的重开请求，并关闭菜单避免遮挡新一局选将界面。
func _request_restart() -> void:
	# 已确认的下一局人数；先写回输入框，使界面文本、Range 数值与重开参数保持一致。
	var player_count: int = get_next_player_count()
	_player_count_input.value = player_count
	_menu_panel.visible = false
	restart_requested.emit(player_count)
