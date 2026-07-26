class_name MatchMenu
extends Control

## 局内菜单组件。该组件只管理菜单显隐和下一局人数输入，通过信号请求桌面执行名称切换或重新开局。

## 请求设置全局卡牌名称模式时发出的信号；实际设置仍由桌面统一调用 GameSettings。
signal card_name_toggle_requested(mode: int)

## 请求重新开局时发出的信号；参数为菜单中设置的下一局玩家人数。
signal restart_requested(player_count: int)

## 请求退出当前对局并回到主菜单时发出的信号；桌面负责清理运行时状态并恢复主菜单焦点。
signal main_menu_requested

## 请求切换过关斩将临时退出预约时发出的信号；实际预约、取消与存档均由桌面调用权威控制器完成。
signal conquest_temporary_exit_toggle_requested

## 请求切换局内聊天窗口显隐时发出的信号；聊天窗口、历史与头顶气泡均由桌面统一管理，菜单只提供入口。
signal chat_toggle_requested

## 标准身份局最少玩家人数；默认2，与 IdentityRules 支持范围一致，运行时无需动态修改。
@export_range(2, 10, 1) var minimum_player_count: int = 2

## 标准身份局最多玩家人数；默认10，与 IdentityRules 支持范围一致，运行时无需动态修改。
@export_range(2, 10, 1) var maximum_player_count: int = 10

## 菜单打开按钮；右上角唯一常驻入口，文字固定为“菜单”。
@onready var _menu_button: Button = %MenuButton

## 聊天窗口切换按钮；位于“菜单”按钮正下方，对离线、房主与客户端始终可见，不属于房主权威控件组。
## 使用 get_node_or_null 防御旧场景缓存缺失该节点；缺失时聊天入口不可用但不影响其余菜单功能。
@onready var _chat_button: Button = get_node_or_null("%MatchChatButton") as Button

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

## 离线控制全部角色开关；离线对局中即时生效，局域网房主与客户端均隐藏。
@onready var _control_all_characters_checkbox: CheckBox = %ControlAllCharactersCheckBox

## 自选全武将、座次与身份开关；仅影响之后由本机或房主创建的新对局。
## 过关斩将显示为“自选武将”，只开放全部武将列表，不改变该模式固定座次与红蓝阵营。
@onready var _custom_character_assignment_checkbox: CheckBox = %CustomCharacterAssignmentCheckBox

## 房主调整全部 AI 武将开关；决定下一局初次选将后是否插入调整阶段。
@onready var _customize_ai_characters_checkbox: CheckBox = %CustomizeAiCharactersCheckBox

## 手气卡数量下拉框；选项元数据保存0至5、10或-1，显示文字不参与规则解析。
@onready var _mulligan_limit_option: OptionButton = %MulliganLimitOption

## AI 使用手气卡开关；实际可用张数仍由手气卡数量设置决定。
@onready var _ai_uses_mulligan_checkbox: CheckBox = %AiUsesMulliganCheckBox

## 换将卡数量下拉框；选项元数据保存房主下一局为每名玩家提供的换将次数。
@onready var _character_replacement_count_option: OptionButton = %CharacterReplacementCountOption

## 随机选将牌数下拉框；选项元数据保存1至20张普通随机候选数量。
@onready var _character_candidate_count_option: OptionButton = %CharacterCandidateCountOption

## 过关斩将难度下拉框；仅影响下一次重开并通过稳定数值一至五保存。
@onready var _conquest_difficulty_option: OptionButton = %ConquestDifficultyOption

## 过关斩将机缘选择方式下拉框；元数据保存vote/individual稳定ID，仅影响下一次重开的多人机缘流程。
@onready var _conquest_opportunity_choice_option: OptionButton = %ConquestOpportunityChoiceOption

## 车轮战明置候选数量输入；仅当前模式为1v1车轮战时显示并用于下一次重开。
@onready var _wheel_duel_face_up_candidate_input: SpinBox = %MatchMenuWheelDuelFaceUpCandidateInput

## 车轮战暗置候选数量输入；仅当前模式为1v1车轮战时显示并与明置数量保持合计至少10名。
@onready var _wheel_duel_face_down_candidate_input: SpinBox = %MatchMenuWheelDuelFaceDownCandidateInput

## 重新开局按钮；点击后携带当前人数设置向桌面发送请求并关闭菜单。
@onready var _restart_button: Button = %MenuRestartButton

## 过关斩将临时退出按钮；仅离线过关斩将显示，点击在“预约临时退出”和“取消预约”之间切换。
## 预约生效后对局会在当前结算完整结束的回合边界自动存档并返回主菜单。
@onready var _conquest_exit_button: Button = %MenuConquestExitButton

## 返回主菜单按钮；退出当前对局后恢复启动入口，不保留正在进行的权威状态。
@onready var _main_menu_button: Button = %MenuReturnToMainButton

## AI响应速度整行容器；仅离线玩家与权威房主可见，客户端本地修改不会影响房主结算。
@onready var _ai_response_delay_row: Control = _ai_response_delay_slider.get_parent() as Control

## 游戏速度整行容器；仅离线玩家与权威房主可见，客户端不能调整房主阶段节奏。
@onready var _game_speed_row: Control = _game_speed_slider.get_parent() as Control

## 下一局人数整行容器；仅实际拥有重新开局权限的离线玩家与房主可见。
@onready var _player_count_row: Control = _player_count_input.get_parent() as Control

## 自选武将座次身份控件；局域网客户端不可修改房主权威开局规则，因此整项隐藏。
@onready var _custom_character_assignment_row: Control = _custom_character_assignment_checkbox

## AI 武将调整控件；仅离线玩家与房主可见，避免客户端产生无法生效的本地配置。
@onready var _customize_ai_characters_row: Control = _customize_ai_characters_checkbox

## 手气卡数量整行容器；下一局规则由房主锁定，局域网客户端不显示该设置。
@onready var _mulligan_limit_row: Control = _mulligan_limit_option.get_parent() as Control

## AI 手气卡控件；仅房主可决定下一局 AI 是否自动刷新起始手牌。
@onready var _ai_uses_mulligan_row: Control = _ai_uses_mulligan_checkbox

## 换将卡数量整行容器；属于房主权威规则，局域网客户端必须整行隐藏。
@onready var _character_replacement_count_row: Control = _character_replacement_count_option.get_parent() as Control

## 随机选将牌数整行容器；属于房主权威规则，局域网客户端必须整行隐藏。
@onready var _character_candidate_count_row: Control = _character_candidate_count_option.get_parent() as Control

## 过关斩将难度整行容器；仅在当前对局为过关斩将且拥有重开权限时显示。
@onready var _conquest_difficulty_row: Control = _conquest_difficulty_option.get_parent() as Control

## 过关斩将机缘选择方式整行容器；与难度设置共享“过关斩将+权威权限”的显示条件。
@onready var _conquest_opportunity_choice_row: Control = _conquest_opportunity_choice_option.get_parent() as Control

## 车轮战明置候选整行容器；普通模式隐藏，车轮战模式按权威权限显示。
@onready var _wheel_duel_face_up_candidate_row: Control = _wheel_duel_face_up_candidate_input.get_parent() as Control

## 车轮战暗置候选整行容器；与明置候选共同组成车轮战专属设置。
@onready var _wheel_duel_face_down_candidate_row: Control = _wheel_duel_face_down_candidate_input.get_parent() as Control

## 当前权威控件是否允许显示；默认true兼容离线对局，局域网客户端由牌桌协调器关闭。
var _authority_controls_visible: bool = true

## 当前是否处于纯离线模式；false时控制全部角色选项无条件隐藏。
var _offline_controls_visible: bool = true

## 当前正在进行的对局模式；局内菜单只展示该模式的专属设置，不跟随隐藏主菜单的待选模式漂移。
var _active_match_mode: String = "identity"

## 当前是否已经预约过关斩将临时退出；由桌面按权威控制器状态回写，仅决定按钮显示文字。
var _conquest_exit_armed: bool = false


## 初始化菜单信号、人数范围和默认关闭状态。
func _ready() -> void:
	# 菜单分支移动到同级节点末尾，使展开面板的输入优先于运行时创建的武将牌和选将遮罩；根节点仍忽略空白区域鼠标。
	call_deferred("_move_to_input_front")
	_menu_button.pressed.connect(_toggle_menu)
	if _chat_button != null:
		_chat_button.pressed.connect(_request_chat_toggle)
	_restart_button.pressed.connect(_request_restart)
	_conquest_exit_button.pressed.connect(_request_conquest_exit_toggle)
	_main_menu_button.pressed.connect(_request_main_menu)
	_apply_player_count_limits_for_mode(GameSettings.next_match_mode if GameSettings != null else "identity")
	_player_count_input.set_value_no_signal(float(GameSettings.next_match_player_count if GameSettings != null else minimum_player_count))
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
	_control_all_characters_checkbox.set_pressed_no_signal(GameSettings.control_all_characters_enabled)
	_control_all_characters_checkbox.toggled.connect(GameSettings.set_control_all_characters_enabled)
	GameSettings.control_all_characters_changed.connect(_control_all_characters_checkbox.set_pressed_no_signal)
	_custom_character_assignment_checkbox.set_pressed_no_signal(GameSettings.custom_character_assignment_enabled)
	_custom_character_assignment_checkbox.toggled.connect(GameSettings.set_custom_character_assignment_enabled)
	GameSettings.custom_character_assignment_changed.connect(_custom_character_assignment_checkbox.set_pressed_no_signal)
	_customize_ai_characters_checkbox.set_pressed_no_signal(GameSettings.customize_ai_characters_enabled)
	_customize_ai_characters_checkbox.toggled.connect(GameSettings.set_customize_ai_characters_enabled)
	GameSettings.customize_ai_characters_changed.connect(_customize_ai_characters_checkbox.set_pressed_no_signal)
	_populate_mulligan_limit_options()
	_mulligan_limit_option.item_selected.connect(_on_mulligan_limit_selected)
	GameSettings.mulligan_limit_changed.connect(_refresh_mulligan_limit_selection)
	_ai_uses_mulligan_checkbox.set_pressed_no_signal(GameSettings.ai_uses_mulligan_enabled)
	_ai_uses_mulligan_checkbox.toggled.connect(GameSettings.set_ai_uses_mulligan_enabled)
	GameSettings.ai_uses_mulligan_changed.connect(_ai_uses_mulligan_checkbox.set_pressed_no_signal)
	_populate_character_replacement_count_options()
	_character_replacement_count_option.item_selected.connect(_on_character_replacement_count_selected)
	GameSettings.character_replacement_count_changed.connect(_refresh_active_character_replacement_count_selection)
	GameSettings.conquest_character_replacement_count_changed.connect(_refresh_active_character_replacement_count_selection)
	_populate_character_candidate_count_options()
	_character_candidate_count_option.item_selected.connect(_on_character_candidate_count_selected)
	GameSettings.character_candidate_count_changed.connect(_refresh_active_character_candidate_count_selection)
	GameSettings.conquest_character_candidate_count_changed.connect(_refresh_active_character_candidate_count_selection)
	_populate_conquest_difficulty_options()
	_conquest_difficulty_option.item_selected.connect(_on_conquest_difficulty_selected)
	GameSettings.conquest_difficulty_changed.connect(_refresh_conquest_difficulty_selection)
	_populate_conquest_opportunity_choice_options()
	_conquest_opportunity_choice_option.item_selected.connect(_on_conquest_opportunity_choice_selected)
	GameSettings.conquest_opportunity_choice_mode_changed.connect(_refresh_conquest_opportunity_choice_selection)
	_wheel_duel_face_up_candidate_input.set_value_no_signal(GameSettings.wheel_duel_face_up_candidate_count)
	_wheel_duel_face_up_candidate_input.value_changed.connect(_on_wheel_duel_face_up_candidate_count_changed)
	_wheel_duel_face_down_candidate_input.set_value_no_signal(GameSettings.wheel_duel_face_down_candidate_count)
	_wheel_duel_face_down_candidate_input.value_changed.connect(_on_wheel_duel_face_down_candidate_count_changed)
	GameSettings.wheel_duel_face_up_candidate_count_changed.connect(_wheel_duel_face_up_candidate_input.set_value_no_signal)
	GameSettings.wheel_duel_face_down_candidate_count_changed.connect(_wheel_duel_face_down_candidate_input.set_value_no_signal)
	GameSettings.next_match_player_count_changed.connect(set_next_player_count)
	GameSettings.next_match_mode_changed.connect(_on_next_match_mode_changed)
	_apply_player_count_limits_for_mode(GameSettings.next_match_mode)
	_menu_panel.visible = false
	refresh_card_name_text()
	_refresh_ai_response_delay_text(GameSettings.ai_response_delay_seconds)
	_refresh_game_speed_text(GameSettings.game_speed_interval_seconds)
	_refresh_ui_style_selection(GameSettings.ui_style_id)
	_refresh_mulligan_limit_selection(GameSettings.mulligan_limit)
	_refresh_active_character_replacement_count_selection()
	_refresh_active_character_candidate_count_selection()
	_refresh_conquest_difficulty_selection(GameSettings.conquest_difficulty)
	_refresh_conquest_opportunity_choice_selection(GameSettings.conquest_opportunity_choice_mode)
	set_match_mode(GameSettings.next_match_mode)
	refresh_ui_style()


## 在父节点完成子节点初始化后提升菜单分支顺序；绘制层级与真实 GUI 命中顺序由同一入口保持一致。
func _move_to_input_front() -> void:
	move_to_front()
	# 展开的菜单面板从常驻入口下缘开始；按钮仍位于面板前方，保证随时可再次点击收起。
	_menu_panel.move_to_front()
	_menu_button.move_to_front()


## 设置下一局默认人数；桌面初始化时传入控制器检查器配置，之后由玩家在菜单中修改。
func set_next_player_count(player_count: int) -> void:
	# 按当前下一局模式规范化；无信号写 SpinBox，切断 value_changed → set_next → value 的无限递归。
	var mode_id: String = GameSettings.next_match_mode if GameSettings != null else "identity"
	var clamped_player_count: int = GameSettings.normalize_player_count_for_mode(mode_id, player_count) if GameSettings != null else clampi(player_count, minimum_player_count, maximum_player_count)
	_apply_player_count_limits_for_mode(mode_id)
	if int(_player_count_input.value) != clamped_player_count:
		_player_count_input.set_value_no_signal(float(clamped_player_count))
	if GameSettings != null:
		GameSettings.set_next_match_player_count(clamped_player_count)


## 返回菜单中设置的下一局人数；始终限制在标准身份局2至10人范围。
func get_next_player_count() -> int:
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	var resolved_player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	var mode_id: String = GameSettings.next_match_mode if GameSettings != null else "identity"
	if GameSettings != null:
		return GameSettings.normalize_player_count_for_mode(mode_id, resolved_player_count)
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


## 控制自动身份标记开关是否显示；斗地主全明置时隐藏，避免无效设置干扰。
func set_auto_identity_marking_visible(controls_visible: bool) -> void:
	if _auto_identity_marking_checkbox == null:
		return
	_auto_identity_marking_checkbox.visible = controls_visible
	if not controls_visible:
		# 隐藏时若焦点落在该开关上则释放，避免键盘导航停在不可见控件。
		var focus_owner: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
		if focus_owner == _auto_identity_marking_checkbox:
			_auto_identity_marking_checkbox.release_focus()


## 统一控制所有依赖房主权威的局内设置；后续新增同类功能必须加入本入口，避免非房主看到无法生效的控件。
func set_authority_controls_visible(controls_visible: bool) -> void:
	_authority_controls_visible = controls_visible
	if not is_node_ready():
		return
	_ai_response_delay_row.visible = controls_visible
	_game_speed_row.visible = controls_visible
	_player_count_row.visible = controls_visible
	_apply_mode_specific_settings_visibility()
	_mulligan_limit_row.visible = controls_visible
	_ai_uses_mulligan_row.visible = controls_visible
	_restart_button.visible = controls_visible
	_control_all_characters_checkbox.visible = controls_visible and _offline_controls_visible
	# 当前焦点若位于刚隐藏的权威控件中，转交给始终可用的返回主菜单按钮，保证键盘导航不会停在不可见节点。
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if not controls_visible and focus_owner != null and (focus_owner == _restart_button or focus_owner == _control_all_characters_checkbox or _ai_response_delay_row.is_ancestor_of(focus_owner) or _game_speed_row.is_ancestor_of(focus_owner) or _player_count_row.is_ancestor_of(focus_owner) or focus_owner == _custom_character_assignment_checkbox or focus_owner == _customize_ai_characters_checkbox or _mulligan_limit_row.is_ancestor_of(focus_owner) or focus_owner == _ai_uses_mulligan_checkbox or _character_replacement_count_row.is_ancestor_of(focus_owner) or _character_candidate_count_row.is_ancestor_of(focus_owner)):
		_main_menu_button.grab_focus()


## 局内重新开局在破坏旧局前被拒绝时重新展开菜单；原对局保持运行，玩家可修正设置后再次提交。
func restore_after_restart_failure() -> void:
	_menu_panel.visible = true
	_restart_button.grab_focus()


## 设置离线专属控件是否可见；联机房主虽然拥有权威设置权限，也不能启用控制全部角色。
func set_offline_controls_visible(controls_visible: bool) -> void:
	_offline_controls_visible = controls_visible
	_control_all_characters_checkbox.visible = _authority_controls_visible and _offline_controls_visible
	if not _control_all_characters_checkbox.visible and _control_all_characters_checkbox.has_focus():
		_control_all_characters_checkbox.release_focus()


## 设置局内菜单绑定的当前对局模式；人数限制与模式专属设置均以该值为准。
func set_match_mode(mode_id: String) -> void:
	_active_match_mode = GameSettings.normalize_match_mode(mode_id) if GameSettings != null else mode_id
	_apply_player_count_limits_for_mode(_active_match_mode)
	_apply_mode_specific_settings_visibility()


## 根据当前对局模式显示独立设置；车轮战显示专属候选数量，过关斩将只显示专属随机选将牌数。
func _apply_mode_specific_settings_visibility() -> void:
	if not is_node_ready():
		return
	var is_wheel_duel: bool = _active_match_mode == GameSettings.MATCH_MODE_WHEEL_DUEL
	var is_conquest: bool = _active_match_mode == GameSettings.MATCH_MODE_CONQUEST
	var show_normal_selection_settings: bool = _authority_controls_visible and not is_wheel_duel and not is_conquest
	_custom_character_assignment_row.visible = _authority_controls_visible and not is_wheel_duel
	_custom_character_assignment_checkbox.text = "自选武将" if is_conquest else "自选全武将、座次与身份"
	_customize_ai_characters_row.visible = show_normal_selection_settings
	_character_replacement_count_row.visible = _authority_controls_visible and not is_wheel_duel
	_character_candidate_count_row.visible = _authority_controls_visible and not is_wheel_duel
	_conquest_difficulty_row.visible = _authority_controls_visible and is_conquest
	_conquest_opportunity_choice_row.visible = _authority_controls_visible and is_conquest
	# 临时退出按钮只属于离线过关斩将；该模式本身拒绝局域网，因此权威可见性即等价于离线可见性。
	_conquest_exit_button.visible = _authority_controls_visible and is_conquest
	_wheel_duel_face_up_candidate_row.visible = _authority_controls_visible and is_wheel_duel
	_wheel_duel_face_down_candidate_row.visible = _authority_controls_visible and is_wheel_duel
	_auto_identity_marking_checkbox.visible = not is_wheel_duel and not is_conquest
	_player_count_row.visible = _authority_controls_visible and not is_wheel_duel and not is_conquest
	_refresh_active_character_replacement_count_selection()
	_refresh_active_character_candidate_count_selection()


## 按全局名称模式刷新菜单下拉选择，不创建第二份名称状态。
func refresh_card_name_text() -> void:
	_refresh_card_name_selection(GameSettings.card_name_mode)


## 使用当前活动主题刷新菜单面板、按钮与文字；该组件不保存任何颜色副本。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_menu_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	BattleUIStyle.apply_interaction_button(_menu_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	if _chat_button != null:
		BattleUIStyle.apply_interaction_button(_chat_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_restart_button)
	BattleUIStyle.apply_interaction_button(_conquest_exit_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_main_menu_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	(_menu_panel.get_node("MenuVBox/MenuTitle") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_ai_response_delay_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_game_speed_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_auto_identity_marking_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_control_all_characters_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_custom_character_assignment_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_customize_ai_characters_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_ai_uses_mulligan_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/CardNameRow/CardNameLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/UiStyleRow/UiStyleLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/MulliganLimitRow/MulliganLimitLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/CharacterReplacementCountRow/CharacterReplacementCountLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/CharacterCandidateCountRow/CharacterCandidateCountLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/ConquestDifficultyRow/ConquestDifficultyLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(_menu_panel.get_node("MenuVBox/ConquestOpportunityChoiceRow/ConquestOpportunityChoiceLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	# 车轮战候选标签与内部输入框都指定同一回退字体，保证局内重开菜单的中文显示与主菜单一致。
	# 明置候选标签；旧局内菜单场景可能未同步该行，缺失时不得妨碍其他设置刷新。
	var wheel_duel_face_up_candidate_label: Label = _menu_panel.get_node_or_null("MenuVBox/WheelDuelFaceUpCandidateRow/WheelDuelFaceUpCandidateLabel") as Label
	if wheel_duel_face_up_candidate_label != null:
		wheel_duel_face_up_candidate_label.add_theme_font_override("font", ThemeDB.fallback_font)
		wheel_duel_face_up_candidate_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		wheel_duel_face_up_candidate_label.add_theme_color_override("font_shadow_color", BattleUIStyle.get_color("outer_background"))
	# 暗置候选标签；单独容错可兼容增量缓存，同时正式场景始终覆盖字体与文字色。
	var wheel_duel_face_down_candidate_label: Label = _menu_panel.get_node_or_null("MenuVBox/WheelDuelFaceDownCandidateRow/WheelDuelFaceDownCandidateLabel") as Label
	if wheel_duel_face_down_candidate_label != null:
		wheel_duel_face_down_candidate_label.add_theme_font_override("font", ThemeDB.fallback_font)
		wheel_duel_face_down_candidate_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		wheel_duel_face_down_candidate_label.add_theme_color_override("font_shadow_color", BattleUIStyle.get_color("outer_background"))
	(_menu_panel.get_node("MenuVBox/PlayerCountRow/PlayerCountLabel") as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_apply_option_button_style(_card_name_option)
	_apply_option_button_style(_ui_style_option)
	_apply_option_button_style(_mulligan_limit_option)
	_apply_option_button_style(_character_replacement_count_option)
	_apply_option_button_style(_character_candidate_count_option)
	_apply_option_button_style(_conquest_difficulty_option)
	_apply_option_button_style(_conquest_opportunity_choice_option)
	_apply_spin_box_style(_wheel_duel_face_up_candidate_input)
	_apply_spin_box_style(_wheel_duel_face_down_candidate_input)


## 为车轮战候选数量输入应用主题样式；SpinBox内部编辑框与增减按钮保持菜单统一配色。
func _apply_spin_box_style(spin_box: SpinBox) -> void:
	if spin_box == null:
		return
	var line_edit: LineEdit = spin_box.get_line_edit()
	# 局内重开设置与主菜单共用全局回退字体，避免车轮战候选数量输入在主题刷新后使用不同的默认字形。
	line_edit.add_theme_font_override("font", ThemeDB.fallback_font)
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_selected_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_uneditable_color", BattleUIStyle.get_color("text_secondary"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 为局内设置下拉框及其弹出列表应用完整交互状态主题；悬停、按下和焦点状态不得回退Godot默认皮肤。
func _apply_option_button_style(option_button: OptionButton) -> void:
	if option_button == null:
		return
	option_button.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	option_button.add_theme_stylebox_override("hover", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), false))
	option_button.add_theme_stylebox_override("pressed", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button").darkened(0.12), BattleUIStyle.get_color("accent"), true))
	option_button.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), true))
	option_button.add_theme_stylebox_override("disabled", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("disabled_button"), BattleUIStyle.get_color("disabled_button_border"), false))
	option_button.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	option_button.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("button_hover_font"))
	option_button.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("button_pressed_font"))
	option_button.add_theme_color_override("font_focus_color", BattleUIStyle.get_color("text_primary"))
	option_button.add_theme_color_override("font_disabled_color", BattleUIStyle.get_color("disabled_button_font"))
	# 下拉弹出列表；OptionButton内部PopupMenu必须单独覆盖，否则列表悬停仍会使用引擎默认主题。
	var popup: PopupMenu = option_button.get_popup()
	popup.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	popup.add_theme_stylebox_override("hover", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), false))
	popup.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	popup.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	popup.add_theme_color_override("font_disabled_color", BattleUIStyle.get_color("disabled_button_font"))


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


## 从全局标准配置生成手气卡数量选项；稳定数值写入元数据，显示文字不承担规则含义。
func _populate_mulligan_limit_options() -> void:
	_mulligan_limit_option.clear()
	for limit_option: Dictionary in GameSettings.MULLIGAN_LIMIT_OPTIONS:
		# 当前手气卡选项索引；保存0至5、10或-1，保证菜单与持久化配置使用同一数值协议。
		var option_index: int = _mulligan_limit_option.item_count
		_mulligan_limit_option.add_item(str(limit_option.get("label", "关闭")))
		_mulligan_limit_option.set_item_metadata(option_index, int(limit_option.get("value", 0)))


## 从全局标准配置生成换将卡数量选项；稳定次数写入元数据，中文量词只负责显示。
func _populate_character_replacement_count_options() -> void:
	_character_replacement_count_option.clear()
	for count_option: Dictionary in GameSettings.CHARACTER_REPLACEMENT_COUNT_OPTIONS:
		# 当前换将卡选项索引；保存0、3、5、8、10或20供两个菜单同步。
		var option_index: int = _character_replacement_count_option.item_count
		_character_replacement_count_option.add_item(str(count_option.get("label", "关闭")))
		_character_replacement_count_option.set_item_metadata(option_index, int(count_option.get("value", 0)))


## 从全局标准配置生成一至二十张随机选将牌选项；规则不依赖显示文字解析数量。
func _populate_character_candidate_count_options() -> void:
	_character_candidate_count_option.clear()
	for count_option: Dictionary in GameSettings.CHARACTER_CANDIDATE_COUNT_OPTIONS:
		# 当前随机候选选项索引；稳定数值直接作为下一局选将服务参数。
		var option_index: int = _character_candidate_count_option.item_count
		_character_candidate_count_option.add_item(str(count_option.get("label", "五张")))
		_character_candidate_count_option.set_item_metadata(option_index, int(count_option.get("value", GameSettings.DEFAULT_CHARACTER_CANDIDATE_COUNT)))


## 从全局标准配置生成过关斩将难度一至五；稳定数值写入元数据，显示文本只负责界面表达。
func _populate_conquest_difficulty_options() -> void:
	_conquest_difficulty_option.clear()
	for difficulty_option: Dictionary in GameSettings.CONQUEST_DIFFICULTY_OPTIONS:
		# 当前难度选项索引；元数据直接作为下一局关卡服务参数。
		var option_index: int = _conquest_difficulty_option.item_count
		_conquest_difficulty_option.add_item(str(difficulty_option.get("label", "难度五")))
		_conquest_difficulty_option.set_item_metadata(option_index, int(difficulty_option.get("value", GameSettings.DEFAULT_CONQUEST_DIFFICULTY)))


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


## 按全局设置同步手气卡下拉框；无信号选择避免外部设置变化形成重复保存。
func _refresh_mulligan_limit_selection(limit: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_mulligan_limit_option.item_count):
		if int(_mulligan_limit_option.get_item_metadata(option_index)) == limit:
			_mulligan_limit_option.select(option_index)
			return


## 将房主选中的手气卡张数写入下一局设置；当前对局继续使用创建时锁定的规则快照。
func _on_mulligan_limit_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _mulligan_limit_option.item_count:
		return
	GameSettings.set_mulligan_limit(int(_mulligan_limit_option.get_item_metadata(option_index)))


## 按传入值同步换将卡数量；无信号选择防止外部菜单变化形成重复保存。
func _refresh_character_replacement_count_selection(count: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_character_replacement_count_option.item_count):
		if int(_character_replacement_count_option.get_item_metadata(option_index)) == count:
			_character_replacement_count_option.select(option_index)
			return


## 按当前模式读取正确的换将卡数量并刷新下拉框；过关斩将不会被普通模式信号覆盖。
func _refresh_active_character_replacement_count_selection(_changed_count: int = 0) -> void:
	if GameSettings == null:
		return
	_refresh_character_replacement_count_selection(GameSettings.get_character_replacement_count_for_mode(_active_match_mode))


## 将房主选择的换将卡数量写入当前模式的独立设置；当前对局继续使用创建时锁定的规则快照。
func _on_character_replacement_count_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _character_replacement_count_option.item_count:
		return
	GameSettings.set_character_replacement_count_for_mode(_active_match_mode, int(_character_replacement_count_option.get_item_metadata(option_index)))


## 按传入值同步随机选将牌数；无信号选择保证主菜单与局内菜单显示一致。
func _refresh_character_candidate_count_selection(count: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_character_candidate_count_option.item_count):
		if int(_character_candidate_count_option.get_item_metadata(option_index)) == count:
			_character_candidate_count_option.select(option_index)
			return


## 按当前模式读取正确的随机选将牌数并刷新下拉框；过关斩将不会被普通模式信号覆盖。
func _refresh_active_character_candidate_count_selection(_changed_count: int = 0) -> void:
	if GameSettings == null:
		return
	_refresh_character_candidate_count_selection(GameSettings.get_character_candidate_count_for_mode(_active_match_mode))


## 将房主选择的随机选将牌数写入当前模式的独立设置；领袖技固定候选由规则层额外追加。
func _on_character_candidate_count_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _character_candidate_count_option.item_count:
		return
	GameSettings.set_character_candidate_count_for_mode(_active_match_mode, int(_character_candidate_count_option.get_item_metadata(option_index)))


## 按全局设置同步过关斩将难度选中项；无信号刷新防止两个设置菜单互相重复提交。
## 填充过关斩将机缘选择方式下拉；选项文本与稳定ID均来自 GameSettings 的唯一配置表。
func _populate_conquest_opportunity_choice_options() -> void:
	_conquest_opportunity_choice_option.clear()
	for choice_option: Dictionary in GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_OPTIONS:
		# 当前下拉项索引；元数据保存稳定方式ID，显示文字仅负责菜单展示。
		var option_index: int = _conquest_opportunity_choice_option.item_count
		_conquest_opportunity_choice_option.add_item(str(choice_option.get("label", "投票选择")))
		_conquest_opportunity_choice_option.set_item_metadata(option_index, str(choice_option.get("value", GameSettings.DEFAULT_CONQUEST_OPPORTUNITY_CHOICE_MODE)))


## 同步机缘选择方式下拉的当前选中项；主菜单等其他入口修改时局内菜单保持一致。
func _refresh_conquest_opportunity_choice_selection(mode_id: String) -> void:
	if _conquest_opportunity_choice_option == null:
		return
	for option_index: int in range(_conquest_opportunity_choice_option.item_count):
		if str(_conquest_opportunity_choice_option.get_item_metadata(option_index)) == mode_id:
			_conquest_opportunity_choice_option.select(option_index)
			return


## 玩家在局内菜单切换机缘选择方式；仅影响下一次重开对局，不改变进行中的机缘流程。
func _on_conquest_opportunity_choice_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _conquest_opportunity_choice_option.item_count:
		return
	GameSettings.set_conquest_opportunity_choice_mode(str(_conquest_opportunity_choice_option.get_item_metadata(option_index)))


func _refresh_conquest_difficulty_selection(difficulty: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_conquest_difficulty_option.item_count):
		if int(_conquest_difficulty_option.get_item_metadata(option_index)) == difficulty:
			_conquest_difficulty_option.select(option_index)
			return


## 将局内菜单选择的难度写入下一局设置；当前对局的难度与已授予机缘保持锁定。
func _on_conquest_difficulty_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _conquest_difficulty_option.item_count:
		return
	GameSettings.set_conquest_difficulty(int(_conquest_difficulty_option.get_item_metadata(option_index)))


## 更新车轮战明置候选数量；若合计不足10名则自动抬高暗置数量。
func _on_wheel_duel_face_up_candidate_count_changed(candidate_count: float) -> void:
	var normalized_count: int = clampi(int(candidate_count), GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT, GameSettings.MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	GameSettings.set_wheel_duel_face_up_candidate_count(normalized_count)
	var required_face_down_count: int = maxi(10 - normalized_count, GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT)
	if GameSettings.wheel_duel_face_down_candidate_count < required_face_down_count:
		GameSettings.set_wheel_duel_face_down_candidate_count(required_face_down_count)


## 更新车轮战暗置候选数量；若合计不足10名则自动抬高明置数量。
func _on_wheel_duel_face_down_candidate_count_changed(candidate_count: float) -> void:
	var normalized_count: int = clampi(int(candidate_count), GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT, GameSettings.MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	GameSettings.set_wheel_duel_face_down_candidate_count(normalized_count)
	var required_face_up_count: int = maxi(10 - normalized_count, GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT)
	if GameSettings.wheel_duel_face_up_candidate_count < required_face_up_count:
		GameSettings.set_wheel_duel_face_up_candidate_count(required_face_up_count)


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
	_game_speed_label.text = "游戏速度：%.2f秒" % interval_seconds


## 将滑条值写入全局游戏速度设置；控制器只对之后创建的调度任务使用新间隔。
func _on_game_speed_changed(interval_seconds: float) -> void:
	GameSettings.set_game_speed_interval_seconds(interval_seconds)


## 切换菜单面板显隐；当前对局继续运行，不改变任何规则状态。
func _toggle_menu() -> void:
	_menu_panel.visible = not _menu_panel.visible


## 发出聊天窗口切换请求；菜单不保存聊天窗口显隐状态，由桌面按当前窗口可见性切换。
func _request_chat_toggle() -> void:
	chat_toggle_requested.emit()


## 发出携带下一局人数的重开请求，并关闭菜单避免遮挡新一局选将界面。
func _request_restart() -> void:
	if not _authority_controls_visible:
		return
	# 已确认的下一局人数；先写回输入框，使界面文本、Range 数值与重开参数保持一致。
	var player_count: int = get_next_player_count()
	_player_count_input.set_value_no_signal(float(player_count))
	GameSettings.set_next_match_player_count(player_count)
	_menu_panel.visible = false
	restart_requested.emit(player_count)


## 发出过关斩将临时退出切换请求并关闭菜单；预约、取消与存档写入均由桌面协调权威控制器完成。
func _request_conquest_exit_toggle() -> void:
	if not _authority_controls_visible:
		return
	_menu_panel.visible = false
	conquest_temporary_exit_toggle_requested.emit()


## 由桌面回写当前临时退出预约状态；true 时按钮显示取消入口，提醒玩家结算结束后会自动存档退出。
func set_conquest_exit_armed(armed: bool) -> void:
	if _conquest_exit_armed == armed:
		return
	_conquest_exit_armed = armed
	if _conquest_exit_button != null:
		_conquest_exit_button.text = "取消临时退出" if armed else "临时退出"


## 下一局人数输入变化时写入全局持久化设置；该值仅用于之后的重开请求，不会改写当前对局。
func _on_next_player_count_changed(player_count: float) -> void:
	var mode_id: String = GameSettings.next_match_mode if GameSettings != null else "identity"
	var resolved_count: int = GameSettings.normalize_player_count_for_mode(mode_id, int(player_count)) if GameSettings != null else int(player_count)
	if int(_player_count_input.value) != resolved_count:
		_player_count_input.set_value_no_signal(float(resolved_count))
	if GameSettings != null:
		GameSettings.set_next_match_player_count(resolved_count)


## 根据下一局模式调整局内菜单人数 SpinBox 上下限与步长；斗地主仅 3↔5。
func _on_next_match_mode_changed(mode_id: String) -> void:
	if _active_match_mode.is_empty():
		set_match_mode(mode_id)
	if GameSettings != null:
		set_next_player_count(GameSettings.next_match_player_count)


## 应用模式人数限制到局内 SpinBox；不写 GameSettings，避免与 set_next 互相重入。
func _apply_player_count_limits_for_mode(mode_id: String) -> void:
	var normalized_mode: String = GameSettings.normalize_match_mode(mode_id) if GameSettings != null else str(mode_id)
	if normalized_mode == GameSettings.MATCH_MODE_DOUDIZHU if GameSettings != null else normalized_mode == "doudizhu":
		minimum_player_count = 3
		maximum_player_count = 5
		_player_count_input.min_value = 3
		_player_count_input.max_value = 5
		_player_count_input.step = 2.0
	else:
		minimum_player_count = 2
		maximum_player_count = 10
		_player_count_input.min_value = 2
		_player_count_input.max_value = 10
		_player_count_input.step = 1.0


## 请求退出当前对局；先收起局内菜单，避免主菜单出现后仍保留局内浮层输入。
func _request_main_menu() -> void:
	_menu_panel.visible = false
	main_menu_requested.emit()
