class_name MatchMenu
extends Control

## 局内菜单组件。该组件只管理菜单显隐和下一局人数输入，通过信号请求桌面执行名称切换或重新开局。

## 请求设置全局卡牌名称模式时发出的信号；实际设置仍由桌面统一调用 GameSettings。
signal card_name_toggle_requested(mode: int)

## 请求重新开局时发出的信号；参数为菜单中设置的下一局玩家人数。
signal restart_requested(player_count: int)

## 请求退出当前对局并回到主菜单时发出的信号；桌面负责清理运行时状态并恢复主菜单焦点。
signal main_menu_requested

## 标准身份局最少玩家人数；默认2，与 IdentityRules 支持范围一致，运行时无需动态修改。
@export_range(2, 10, 1) var minimum_player_count: int = 2

## 标准身份局最多玩家人数；默认10，与 IdentityRules 支持范围一致，运行时无需动态修改。
@export_range(2, 10, 1) var maximum_player_count: int = 10

## 菜单打开按钮；右上角唯一常驻入口，文字固定为“菜单”。
@onready var _menu_button: Button = %MenuButton

## 菜单内容面板；默认隐藏，点击菜单按钮后切换可见性。
@onready var _menu_panel: PanelContainer = %MenuPanel

## 卡牌名称下拉框；选项元数据保存全局名称模式枚举，界面只显示玩家可见名称。
@onready var _card_name_option: OptionButton = %MenuCardNameOption

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

## 自动身份标记复选框；勾选状态直接映射全局设置，只影响其他角色的本地推测徽记。
@onready var _auto_identity_marking_checkbox: CheckBox = %AutoIdentityMarkingCheckBox

## 重新开局按钮；点击后携带当前人数设置向桌面发送请求并关闭菜单。
@onready var _restart_button: Button = %MenuRestartButton

## 返回主菜单按钮；退出当前对局后恢复启动入口，不保留正在进行的权威状态。
@onready var _main_menu_button: Button = %MenuReturnToMainButton

## AI响应速度整行容器；仅离线玩家与权威房主可见，客户端本地修改不会影响房主结算。
@onready var _ai_response_delay_row: Control = _ai_response_delay_slider.get_parent() as Control

## 游戏速度整行容器；仅离线玩家与权威房主可见，客户端不能调整房主阶段节奏。
@onready var _game_speed_row: Control = _game_speed_slider.get_parent() as Control

## 下一局人数整行容器；仅实际拥有重新开局权限的离线玩家与房主可见。
@onready var _player_count_row: Control = _player_count_input.get_parent() as Control

## 当前权威控件是否允许显示；默认true兼容离线对局，局域网客户端由牌桌协调器关闭。
var _authority_controls_visible: bool = true


## 初始化菜单信号、人数范围和默认关闭状态。
func _ready() -> void:
	# 菜单分支移动到同级节点末尾，使展开面板的输入优先于运行时创建的武将牌和选将遮罩；根节点仍忽略空白区域鼠标。
	call_deferred("_move_to_input_front")
	_menu_button.pressed.connect(_toggle_menu)
	_restart_button.pressed.connect(_request_restart)
	_main_menu_button.pressed.connect(_request_main_menu)
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 1.0
	_player_count_input.value = GameSettings.next_match_player_count
	# 人数输入在键入时立即同步 Range 数值，避免玩家直接输入后立刻点击重开时仍读取旧值。
	_player_count_input.update_on_text_changed = true
	_player_count_input.value_changed.connect(_on_next_player_count_changed)
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
	_populate_card_name_options()
	_card_name_option.item_selected.connect(_on_card_name_selected)
	GameSettings.card_name_mode_changed.connect(_refresh_card_name_selection)
	_populate_ui_style_options()
	_ui_style_option.item_selected.connect(_on_ui_style_selected)
	GameSettings.ui_style_changed.connect(_refresh_ui_style_selection)
	_auto_identity_marking_checkbox.set_pressed_no_signal(GameSettings.auto_identity_marking_enabled)
	_auto_identity_marking_checkbox.toggled.connect(_on_auto_identity_marking_toggled)
	GameSettings.auto_identity_marking_changed.connect(_refresh_auto_identity_marking_state)
	GameSettings.next_match_player_count_changed.connect(set_next_player_count)
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
	# 当前菜单允许的人数；范围以组件导出的身份局限制为准，避免未来调整检查器范围时写入无效存档。
	var clamped_player_count: int = clampi(player_count, minimum_player_count, maximum_player_count)
	_player_count_input.value = clamped_player_count
	GameSettings.set_next_match_player_count(clamped_player_count)


## 返回菜单中设置的下一局人数；始终限制在标准身份局2至10人范围。
func get_next_player_count() -> int:
	# 输入框当前文本；优先读取尚未因焦点切换而提交的键入内容，保证鼠标点击重开时人数准确。
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	# 有效人数；空文本或非数字文本回退到 SpinBox 已确认值，并始终限制在标准身份局范围内。
	var resolved_player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	return clampi(resolved_player_count, minimum_player_count, maximum_player_count)


## 返回局内菜单面板当前是否展开；平台适配层通过该只读接口决定返回键是打开还是关闭菜单。
func is_menu_open() -> bool:
	return _menu_panel.visible


## 设置局内菜单面板显隐；统一复用按钮切换后的焦点规则，避免平台层直接访问内部节点。
func set_menu_open(open: bool) -> void:
	_menu_panel.visible = open
	if open:
		if _authority_controls_visible:
			_restart_button.grab_focus()
		else:
			_main_menu_button.grab_focus()
	else:
		_menu_button.grab_focus()


## 统一控制所有依赖房主权威的局内设置；后续新增同类功能必须加入本入口，避免非房主看到无法生效的控件。
func set_authority_controls_visible(controls_visible: bool) -> void:
	_authority_controls_visible = controls_visible
	if not is_node_ready():
		return
	_ai_response_delay_row.visible = controls_visible
	_game_speed_row.visible = controls_visible
	_player_count_row.visible = controls_visible
	_restart_button.visible = controls_visible
	# 当前焦点若位于刚隐藏的权威控件中，转交给始终可用的返回主菜单按钮，保证键盘导航不会停在不可见节点。
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if not controls_visible and focus_owner != null and (focus_owner == _restart_button or _ai_response_delay_row.is_ancestor_of(focus_owner) or _game_speed_row.is_ancestor_of(focus_owner) or _player_count_row.is_ancestor_of(focus_owner)):
		_main_menu_button.grab_focus()


## 局内重新开局在破坏旧局前被拒绝时重新展开菜单；原对局保持运行，玩家可修正设置后再次提交。
func restore_after_restart_failure() -> void:
	_menu_panel.visible = true
	_restart_button.grab_focus()


## 按全局名称模式刷新菜单下拉选择，不创建第二份名称状态。
func refresh_card_name_text() -> void:
	_refresh_card_name_selection(GameSettings.card_name_mode)


## 使用当前活动主题刷新菜单面板、按钮与文字；该组件不保存任何颜色副本。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_menu_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	BattleUIStyle.apply_interaction_button(_menu_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_restart_button)
	BattleUIStyle.apply_interaction_button(_main_menu_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	(_menu_panel.get_node("MenuVBox/MenuTitle") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_ai_response_delay_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_game_speed_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_auto_identity_marking_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/CardNameRow/CardNameLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/UiStyleRow/UiStyleLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/PlayerCountRow/PlayerCountLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_card_name_option.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_card_name_option.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
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


## 从固定名称模式配置构建下拉选项；枚举元数据避免依赖显示文字反向判断当前模式。
func _populate_card_name_options() -> void:
	_card_name_option.clear()
	for mode_option: Dictionary in GameSettings.CARD_NAME_MODE_OPTIONS:
		# 下拉项索引；稳定模式枚举写入元数据，文本只用于界面显示。
		var option_index: int = _card_name_option.item_count
		_card_name_option.add_item(str(mode_option.get("label", "")))
		_card_name_option.set_item_metadata(option_index, mode_option.get("mode", GameSettings.NameMode.CUSTOM))


## 依据全局名称模式同步下拉框选中项；无信号更新避免界面刷新重复提交同一个设置。
func _refresh_card_name_selection(mode: GameSettings.NameMode) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_card_name_option.item_count):
		if int(_card_name_option.get_item_metadata(option_index)) == int(mode):
			_card_name_option.select(option_index)
			return


## 将玩家选择的名称模式交给桌面；桌面写入 GameSettings 并统一刷新所有已显示牌面。
func _on_card_name_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _card_name_option.item_count:
		return
	# 当前稳定名称模式；元数据缺失时回退默认自定义名称模式。
	var selected_mode: int = int(_card_name_option.get_item_metadata(option_index))
	card_name_toggle_requested.emit(selected_mode)


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


## 将复选框状态写入全局自动身份标记设置；身份观察记录继续保留，重新开启后可立即恢复当前推断。
func _on_auto_identity_marking_toggled(enabled: bool) -> void:
	GameSettings.set_auto_identity_marking_enabled(enabled)


## 按全局设置同步复选框；无信号写入避免外部设置变化触发重复回调。
func _refresh_auto_identity_marking_state(enabled: bool) -> void:
	if not is_node_ready():
		return
	_auto_identity_marking_checkbox.set_pressed_no_signal(enabled)


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
	_game_speed_label.text = "游戏速度：%.1f秒" % interval_seconds


## 将滑条值写入全局游戏速度设置；控制器只对之后创建的调度任务使用新间隔。
func _on_game_speed_changed(interval_seconds: float) -> void:
	GameSettings.set_game_speed_interval_seconds(interval_seconds)


## 切换菜单面板显隐；当前对局继续运行，不改变任何规则状态。
func _toggle_menu() -> void:
	_menu_panel.visible = not _menu_panel.visible


## 发出携带下一局人数的重开请求，并关闭菜单避免遮挡新一局选将界面。
func _request_restart() -> void:
	if not _authority_controls_visible:
		return
	# 已确认的下一局人数；先写回输入框，使界面文本、Range 数值与重开参数保持一致。
	var player_count: int = get_next_player_count()
	_player_count_input.value = player_count
	GameSettings.set_next_match_player_count(player_count)
	_menu_panel.visible = false
	restart_requested.emit(player_count)


## 下一局人数输入变化时写入全局持久化设置；该值仅用于之后的重开请求，不会改写当前对局。
func _on_next_player_count_changed(player_count: float) -> void:
	GameSettings.set_next_match_player_count(int(player_count))


## 请求退出当前对局；先收起局内菜单，避免主菜单出现后仍保留局内浮层输入。
func _request_main_menu() -> void:
	_menu_panel.visible = false
	main_menu_requested.emit()
