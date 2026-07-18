class_name MainMenu
extends Control

## 主菜单组件。该组件只管理启动前的模式选择、显示设置与开局请求，不直接创建或修改任何对局状态。

## 玩家确认开始身份局时发出的信号；参数为设置中确认的下一局人数，由牌桌统一调用对局控制器。
signal start_game_requested(player_count: int)

## 标准身份局允许的最少玩家人数；默认2人与身份规则支持范围一致，运行时可在检查器中调整显示范围。
@export_range(2, 10, 1) var minimum_player_count: int = 2

## 标准身份局允许的最多玩家人数；默认10人与身份规则支持范围一致，运行时可在检查器中调整显示范围。
@export_range(2, 10, 1) var maximum_player_count: int = 10

## 预览背景叠加当前主题面板色的透明度；默认0.18保证文字清晰且保留身份模式原图主体，运行时只影响视觉明暗。
@export_range(0.0, 1.0, 0.01) var preview_shade_opacity: float = 0.18

## 顶部模式导航栏；目前只承载唯一的“身份模式”选项，后续新增模式仍可复用同一容器与主题样式。
@onready var _top_navigation: PanelContainer = %MainMenuTopNavigation

## 主菜单外框；左侧模式列表与右侧模式预览共同位于此容器内，颜色始终由当前 UI 风格提供。
@onready var _main_frame: PanelContainer = %MainMenuFrame

## 左侧模式选择区域；当前只显示身份模式，后续模式可在不改变右侧开局协议的前提下追加。
@onready var _mode_list: PanelContainer = %MainMenuModeList

## 右侧身份模式预览区域；承载可裁剪的模式背景与底部操作按钮，不保存玩法状态。
@onready var _preview_panel: PanelContainer = %MainMenuPreviewPanel

## 主菜单全屏底色；使用主题外底色遮住尚未开始的牌桌静态节点，避免启动阶段呈现局内信息。
@onready var _menu_background: ColorRect = %MainMenuBackground

## 身份模式预览遮罩；只改善前景文本可读性，不负责复刻参考图中的游戏毛玻璃背景。
@onready var _preview_shade: ColorRect = %MainMenuPreviewShade

## 顶部身份模式选项；当前唯一的游戏模式入口，按下后仅重新确认身份模式为选中状态。
@onready var _top_identity_mode_button: Button = %TopIdentityModeButton

## 左侧身份模式按钮；对应参考布局中的模式选择列表，目前是唯一可选择的模式。
@onready var _identity_mode_button: Button = %IdentityModeButton

## 身份模式标题；显示当前右侧预览所代表的游戏模式，不作为规则状态来源。
@onready var _mode_title: Label = %MainMenuModeTitle

## 身份模式说明；用于在没有其他模式时明确当前可启动的是标准身份局。
@onready var _mode_description: Label = %MainMenuModeDescription

## 开始游戏按钮；点击后关闭主菜单并把人数请求交给牌桌的统一开局入口。
@onready var _start_game_button: Button = %StartGameButton

## 设置按钮；位于开始游戏按钮左侧，替代参考布局中的商店入口。
@onready var _settings_button: Button = %MainMenuSettingsButton

## 设置浮层；默认隐藏，打开后允许修改全局显示与下一局人数配置。
@onready var _settings_panel: PanelContainer = %MainMenuSettingsPanel

## 设置关闭按钮；仅关闭设置浮层并返回主菜单，不改变已选择的游戏模式或未开始的对局状态。
@onready var _settings_close_button: Button = %MainMenuSettingsCloseButton

## 卡牌名称切换按钮；文字显示当前使用的名称体系，实际设置保存于 GameSettings。
@onready var _card_name_button: Button = %MainMenuCardNameButton

## UI 风格下拉框；选项元数据保存稳定风格标识，界面只显示注册表提供的名称。
@onready var _ui_style_option: OptionButton = %MainMenuUiStyleOption

## 自动身份标记复选框；开关仅影响本地显示推测，不写入对局规则状态。
@onready var _auto_identity_marking_checkbox: CheckBox = %MainMenuAutoIdentityMarkingCheckBox

## AI 响应速度标签；显示下一次 AI 行动或响应会使用的等待秒数。
@onready var _ai_response_delay_label: Label = %MainMenuAiResponseDelayLabel

## AI 响应速度滑条；修改后立即写入全局设置，并影响之后创建的 AI 等待任务。
@onready var _ai_response_delay_slider: HSlider = %MainMenuAiResponseDelaySlider

## 游戏速度标签；显示后续阶段切换和自动响应的最小间隔秒数。
@onready var _game_speed_label: Label = %MainMenuGameSpeedLabel

## 游戏速度滑条；修改后立即写入全局设置，不重置已经开始的计时任务。
@onready var _game_speed_slider: HSlider = %MainMenuGameSpeedSlider

## 下一局人数输入框；开始游戏时读取该控件，限制为标准身份局支持的2至10人范围。
@onready var _player_count_input: SpinBox = %MainMenuPlayerCountInput


## 初始化主菜单交互与全局设置同步；主菜单进入场景后始终覆盖尚未开局的牌桌。
func _ready() -> void:
	# 当前菜单绘制与输入层；提升到同级节点最前方，确保选将遮罩和局内菜单不会遮挡启动入口。
	call_deferred("_move_to_input_front")
	_top_identity_mode_button.pressed.connect(_select_identity_mode)
	_identity_mode_button.pressed.connect(_select_identity_mode)
	_settings_button.pressed.connect(_open_settings)
	_settings_close_button.pressed.connect(_close_settings)
	_start_game_button.pressed.connect(_request_start_game)
	_card_name_button.pressed.connect(GameSettings.toggle_card_name_mode)
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 1.0
	# 当前人数输入提交策略；键入数值后立即同步 Range，防止按下开始游戏时读取焦点尚未提交的旧值。
	_player_count_input.update_on_text_changed = true
	_ai_response_delay_slider.min_value = GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.max_value = GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.step = GameSettings.AI_RESPONSE_DELAY_STEP_SECONDS
	_ai_response_delay_slider.value = GameSettings.ai_response_delay_seconds
	_ai_response_delay_slider.value_changed.connect(_on_ai_response_delay_changed)
	_game_speed_slider.min_value = GameSettings.MIN_GAME_SPEED_INTERVAL_SECONDS
	_game_speed_slider.max_value = GameSettings.MAX_GAME_SPEED_INTERVAL_SECONDS
	_game_speed_slider.step = GameSettings.GAME_SPEED_INTERVAL_STEP_SECONDS
	_game_speed_slider.value = GameSettings.game_speed_interval_seconds
	_game_speed_slider.value_changed.connect(_on_game_speed_changed)
	_populate_ui_style_options()
	_ui_style_option.item_selected.connect(_on_ui_style_selected)
	_auto_identity_marking_checkbox.set_pressed_no_signal(GameSettings.auto_identity_marking_enabled)
	_auto_identity_marking_checkbox.toggled.connect(_on_auto_identity_marking_toggled)
	GameSettings.card_name_mode_changed.connect(_refresh_card_name_text)
	GameSettings.ui_style_changed.connect(_refresh_ui_style_selection)
	GameSettings.ai_response_delay_changed.connect(_refresh_ai_response_delay_text)
	GameSettings.game_speed_changed.connect(_refresh_game_speed_text)
	GameSettings.auto_identity_marking_changed.connect(_refresh_auto_identity_marking_state)
	_settings_panel.visible = false
	_select_identity_mode()
	_refresh_card_name_text()
	_refresh_ui_style_selection(GameSettings.ui_style_id)
	_refresh_ai_response_delay_text(GameSettings.ai_response_delay_seconds)
	_refresh_game_speed_text(GameSettings.game_speed_interval_seconds)
	refresh_ui_style()


## 在父节点完成初始化后提升主菜单分支；保证启动页面的绘制顺序与真实 GUI 命中顺序一致。
func _move_to_input_front() -> void:
	move_to_front()


## 将牌桌提供的下一局人数写入主菜单设置；人数保持限制在标准身份局的有效范围。
func set_next_player_count(player_count: int) -> void:
	_player_count_input.value = clampi(player_count, minimum_player_count, maximum_player_count)


## 返回设置面板当前指定的人数；优先读取仍在编辑中的文本，避免输入框失焦前的数据丢失。
func get_next_player_count() -> int:
	# 当前手动输入文本；数值文本优先于 SpinBox 已确认值，空文本与非数字文本会安全回退。
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	# 实际人数；0不是合法标准身份局人数，因此可作为无效文本的回退标记。
	var resolved_player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	return clampi(resolved_player_count, minimum_player_count, maximum_player_count)


## 按当前活动主题刷新主菜单全部静态控件；不保存主题颜色副本，也不修改任何玩法配置。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_menu_background.color = BattleUIStyle.get_color("outer_background")
	_top_navigation.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	_main_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	_mode_list.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), 1, 6))
	_preview_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border"), 2, 6))
	_settings_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	_preview_shade.color = Color(BattleUIStyle.get_color("panel"), preview_shade_opacity)
	BattleUIStyle.apply_interaction_button(_top_identity_mode_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_identity_mode_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_settings_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_start_game_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_settings_close_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_card_name_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	_mode_title.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_mode_description.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%MainMenuModeListTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_mode_list.get_node("ModeListVBox/ModeListHint") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	(%MainMenuSettingsTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%MainMenuUiStyleLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuPlayerCountLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_ai_response_delay_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_game_speed_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_auto_identity_marking_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_ui_style_option.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_ui_style_option.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))


## 重新确认身份模式为当前唯一选择；未来接入其他模式时只需在此处更新预览绑定而不改变开局信号。
func _select_identity_mode() -> void:
	_mode_title.text = "身份模式"
	_mode_description.text = "标准身份局"
	_top_identity_mode_button.button_pressed = true
	_identity_mode_button.button_pressed = true


## 打开设置浮层；模式预览保持可见，玩家可在不离开主菜单的情况下调整显示和人数配置。
func _open_settings() -> void:
	_settings_panel.visible = true


## 关闭设置浮层；已经写入 GameSettings 的配置立即保留，不需要额外确认按钮。
func _close_settings() -> void:
	_settings_panel.visible = false


## 读取有效人数并请求开始身份局；成功后的实际开局、状态清理与选将流程由牌桌统一处理。
func _request_start_game() -> void:
	# 已确认的下一局人数；写回控件使文本、Range 数值和发出的开局请求保持一致。
	var player_count: int = get_next_player_count()
	_player_count_input.value = player_count
	_settings_panel.visible = false
	visible = false
	start_game_requested.emit(player_count)


## 从注册表构建 UI 风格选项；稳定标识写入元数据，显示名称调整不会影响保存的设置值。
func _populate_ui_style_options() -> void:
	_ui_style_option.clear()
	for style_id: String in UIStyleRegistry.get_style_ids():
		# 当前选项索引；元数据保存稳定标识，后续无需通过中文名称反向匹配主题。
		var option_index: int = _ui_style_option.item_count
		_ui_style_option.add_item(UIStyleRegistry.get_display_name(style_id))
		_ui_style_option.set_item_metadata(option_index, style_id)


## 按全局风格同步下拉框与主菜单颜色；无信号选择避免界面刷新产生重复设置回调。
func _refresh_ui_style_selection(style_id: String) -> void:
	if not is_node_ready():
		return
	# 已规范化的风格标识；配置缺失时稳定回退默认主题，保证下拉框存在有效选择。
	var normalized_style_id: String = UIStyleRegistry.normalize_style_id(style_id)
	for option_index: int in range(_ui_style_option.item_count):
		if str(_ui_style_option.get_item_metadata(option_index)) == normalized_style_id:
			_ui_style_option.select(option_index)
			break
	refresh_ui_style()


## 将玩家选中的主题稳定标识写入全局设置；所有已订阅的界面会即时重绘。
func _on_ui_style_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _ui_style_option.item_count:
		return
	GameSettings.set_ui_style(str(_ui_style_option.get_item_metadata(option_index)))


## 根据全局名称模式刷新切换按钮文本；名称模式只改变前端显示，不影响任何卡牌 ID 或规则。
func _refresh_card_name_text(_mode: GameSettings.NameMode = GameSettings.NameMode.CUSTOM) -> void:
	if not is_node_ready():
		return
	_card_name_button.text = "卡牌名称：崩铁杀" if GameSettings.card_name_mode == GameSettings.NameMode.CUSTOM else "卡牌名称：三国杀"


## 更新 AI 响应速度显示；数值越小代表 AI 行动与选牌等待越短。
func _refresh_ai_response_delay_text(delay_seconds: float) -> void:
	if not is_node_ready():
		return
	_ai_response_delay_slider.set_value_no_signal(delay_seconds)
	_ai_response_delay_label.text = "AI响应速度：%.2f秒" % delay_seconds


## 将 AI 响应滑条值写入全局设置；控制器只对后续创建的等待任务采用新值。
func _on_ai_response_delay_changed(delay_seconds: float) -> void:
	GameSettings.set_ai_response_delay_seconds(delay_seconds)


## 更新游戏速度显示；数值代表后续阶段切换和自动响应的最小等待间隔。
func _refresh_game_speed_text(interval_seconds: float) -> void:
	if not is_node_ready():
		return
	_game_speed_slider.set_value_no_signal(interval_seconds)
	_game_speed_label.text = "游戏速度：%.1f秒" % interval_seconds


## 将游戏速度滑条值写入全局设置；已开始的计时任务保持原时长以避免中途跳变。
func _on_game_speed_changed(interval_seconds: float) -> void:
	GameSettings.set_game_speed_interval_seconds(interval_seconds)


## 将自动身份标记开关写入全局设置；该设置只影响客户端推测徽记显示。
func _on_auto_identity_marking_toggled(enabled: bool) -> void:
	GameSettings.set_auto_identity_marking_enabled(enabled)


## 按全局设置同步自动身份标记复选框；无信号写入避免外部刷新形成重复回调。
func _refresh_auto_identity_marking_state(enabled: bool) -> void:
	if not is_node_ready():
		return
	_auto_identity_marking_checkbox.set_pressed_no_signal(enabled)
