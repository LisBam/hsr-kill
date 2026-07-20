extends Node

## 主菜单回归测试。验证游戏启动先进入主菜单，设置与开始游戏共用标准身份局的统一开局入口。

## 主菜单与牌桌完成信号连接、主题刷新及开局状态广播前等待的帧数；默认6帧覆盖无头模式下的延迟布局。
const SETTLE_FRAME_COUNT: int = 6

## 开局失败回归使用的临时校验错误；测试结束前会从自动加载数据库移除，不污染后续成功开局。
const START_FAILURE_TEST_ERROR: String = "主菜单失败回退测试"


## 延迟执行主菜单测试；保证本测试根节点与正式主场景均已进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 验证启动页面、设置浮层和身份局开始请求；任一断言失败后以非零状态退出。
func _run() -> void:
	# 正式主场景资源；测试必须使用玩家实际启动的场景而非构造替代界面。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；主菜单和牌桌信号在同一节点树中完成连接。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 主菜单组件；启动前必须可见并且不得已经创建对局状态。
	var main_menu: MainMenu = main_instance.get_node("%MainMenu") as MainMenu
	# 对局控制器；点击开始游戏后由主菜单信号驱动其创建标准身份局。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 设置按钮；替代参考布局中的商店入口，点击后展示配置浮层。
	var settings_button: Button = main_instance.get_node("%MainMenuSettingsButton") as Button
	# 顶部联机设置按钮；必须位于模式选择右侧并对等切换主菜单客户区资料页。
	var online_settings_button: Button = main_instance.get_node("%MainMenuOnlineSettingsButton") as Button
	# 开始按钮；文字固定为“开始游戏”，点击后关闭主菜单并开始身份局。
	var start_game_button: Button = main_instance.get_node("%StartGameButton") as Button
	# 局内菜单入口；成功开局后用于验证重新开局失败能显式返回主菜单，而不是停留在旧牌桌。
	var match_menu_button: Button = main_instance.get_node("%MenuButton") as Button
	# 局内重新开局按钮；以真实鼠标事件触发与主菜单共用的统一开局入口。
	var match_restart_button: Button = main_instance.get_node("%MenuRestartButton") as Button
	# 局内菜单面板；前置重开校验失败时必须重新展开，让旧对局继续且允许玩家修正配置。
	var match_menu_panel: PanelContainer = main_instance.get_node("%MenuPanel") as PanelContainer
	# 局内错误标签；用于确认前置重开失败仍显示控制器提供的同一拒绝原因。
	var match_error_label: Label = main_instance.get_node("%ErrorLabel") as Label
	# 局内日志入口；主菜单可见期间应与局内菜单一起停止获取键盘焦点，进入对局后恢复。
	var log_toggle_button: Button = main_instance.get_node("%LogToggleButton") as Button
	# 设置浮层；默认隐藏，按下设置按钮后可修改下一局人数。
	var settings_panel: PanelContainer = main_instance.get_node("%MainMenuSettingsPanel") as PanelContainer
	# 联机资料设置组件；名称与武将形象只写入全局资料，不创建局域网会话。
	var online_settings_panel: OnlineSettingsPanel = main_instance.get_node("%OnlineSettingsPanel") as OnlineSettingsPanel
	# 联机玩家名称输入；保存时必须去除首尾空白并遵守20字符上限。
	var online_player_name_input: LineEdit = online_settings_panel.get_node("%OnlinePlayerNameInput") as LineEdit
	# 联机武将形象承载区；动态候选数量必须覆盖数据库中的全部现有武将牌。
	var online_avatar_content: Control = online_settings_panel.get_node("%OnlineAvatarContent") as Control
	# 联机资料保存按钮；提交当前名称与稳定武将 ID 后返回默认主菜单内容页。
	var online_settings_save_button: Button = online_settings_panel.get_node("%OnlineSettingsSaveButton") as Button
	# 游戏人数输入框；2至10范围内的值会作为主菜单开局请求参数。
	var player_count_input: SpinBox = main_instance.get_node("%MainMenuPlayerCountInput") as SpinBox
	# 顶部模式栏；主题切换后其边框必须从统一注册表即时更新。
	var top_navigation: PanelContainer = main_instance.get_node("%MainMenuTopNavigation") as PanelContainer
	# 主菜单外框；紧凑客户区下必须始终位于顶部模式栏下方，不能发生标题或按钮重叠。
	var main_frame: PanelContainer = main_instance.get_node("%MainMenuFrame") as PanelContainer
	# 设置模态遮罩；设置打开时覆盖完整主菜单并阻止底层开始按钮接收真实鼠标输入。
	var settings_backdrop: ColorRect = main_instance.get_node("%MainMenuSettingsBackdrop") as ColorRect
	# 设置返回按钮；关闭后面板与模态遮罩必须同步隐藏。
	var settings_close_button: Button = main_instance.get_node("%MainMenuSettingsCloseButton") as Button
	# 身份模式背景；必须继续使用指定原画并采用覆盖裁剪，禁止拉伸破坏原图比例。
	var mode_background: TextureRect = main_instance.get_node("MainMenu/MainMenuFrame/MainMenuContent/MainMenuPreviewPanel/MainMenuPreviewContent/MainMenuModeBackground") as TextureRect
	# 顶部身份模式按钮；顶部选项栏目前只能存在这一项。
	var top_identity_mode_button: Button = main_instance.get_node("%TopIdentityModeButton") as Button
	# 左侧身份模式按钮；左侧模式列表目前只能存在这一项。
	var identity_mode_button: Button = main_instance.get_node("%IdentityModeButton") as Button
	# 左侧身份模式标题；必须独立于按钮文本呈现，以便标题可使用更大的主题字号。
	var identity_mode_name: Label = main_instance.get_node("%IdentityModeName") as Label
	# 左侧身份模式人数说明；仅展示可选人数范围，不重复标准身份局描述。
	var identity_mode_player_count: Label = main_instance.get_node("%IdentityModePlayerCount") as Label
	# 右侧模式规则提示；当前只保留随机身份和阵营对抗两项核心玩法说明。
	var mode_rule_hint: Label = main_instance.get_node("%MainMenuModeRuleHint") as Label
	# 左侧模式面板；用于确认其中没有隐藏的第二个模式按钮。
	var mode_list: PanelContainer = main_instance.get_node("%MainMenuModeList") as PanelContainer
	# 预览底部操作栏；主题切换后其描边必须使用当前主题强调色。
	var action_panel: PanelContainer = main_instance.get_node("%MainMenuActionPanel") as PanelContainer
	# 主菜单状态文字；开局失败时必须展示控制器返回的具体拒绝原因。
	var menu_status_label: Label = main_instance.get_node("%MainMenuStatusLabel") as Label
	# 主菜单全屏底色；必须停止未被前景面板覆盖区域的鼠标输入，避免误触局内隐藏控件。
	var menu_background: ColorRect = main_instance.get_node("%MainMenuBackground") as ColorRect
	# AI速度滑条；用于验证设置控件轨道也跟随当前主题，不保留默认 Godot 配色。
	var ai_response_slider: HSlider = main_instance.get_node("%MainMenuAiResponseDelaySlider") as HSlider
	# 游戏人数文本框；用于验证 SpinBox 编辑区的焦点与常态边框来自当前主题。
	var player_count_line_edit: LineEdit = player_count_input.get_line_edit()
	# 主菜单卡牌名称下拉框；必须与UI风格保持标签加下拉框的统一设置格式。
	var main_menu_card_name_option: OptionButton = main_instance.get_node("%MainMenuCardNameOption") as OptionButton
	# 局内卡牌名称下拉框；应使用与主菜单相同的两项稳定名称模式配置。
	var match_menu_card_name_option: OptionButton = main_instance.get_node("%MenuCardNameOption") as OptionButton
	# 手牌区上方原确定按钮；终局时复用为“重新开始”。
	var interaction_use_button: Button = main_instance.get_node("%UseButton") as Button
	# 手牌区上方原取消按钮；终局时复用为“返回主菜单”。
	var interaction_cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	if main_menu == null or not main_menu.visible or match_controller.state != null or settings_button.text != "设置" or online_settings_button.text != "联机设置" or start_game_button.text != "开始游戏" or settings_panel.visible or online_settings_panel.visible or settings_backdrop.visible or menu_background.mouse_filter != Control.MOUSE_FILTER_STOP or menu_status_label.visible or not menu_status_label.text.is_empty() or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
		_fail("startup_state")
		return
	if main_menu_card_name_option == null or match_menu_card_name_option == null or main_menu_card_name_option.item_count != 2 or match_menu_card_name_option.item_count != 2 or main_menu_card_name_option.get_item_text(0) != "崩铁杀" or main_menu_card_name_option.get_item_text(1) != "三国杀":
		_fail("card_name_option_layout")
		return
	# 主菜单名称模式选择；通过实际下拉信号写入全局设置并同步到局内同构下拉框。
	main_menu_card_name_option.item_selected.emit(1)
	await get_tree().process_frame
	if GameSettings.card_name_mode != GameSettings.NameMode.ORIGINAL or match_menu_card_name_option.selected != 1:
		_fail("main_menu_card_name_selection")
		return
	# 局内名称模式选择；恢复默认自定义名称，避免后续测试依赖错误的牌面名称模式。
	match_menu_card_name_option.item_selected.emit(0)
	await get_tree().process_frame
	if GameSettings.card_name_mode != GameSettings.NameMode.CUSTOM or main_menu_card_name_option.selected != 0:
		_fail("match_menu_card_name_selection")
		return
	if mode_background.texture == null or mode_background.texture.resource_path != "res://assets/art/身份模式主菜单背景.png" or mode_background.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		_fail("mode_preview")
		return
	# 顶部按钮顺序；“联机设置”必须紧跟在“模式选择”右侧，左侧游戏模式列表仍只有身份模式一项。
	var top_navigation_buttons: Array[Node] = top_navigation.find_children("*", "Button", true, false)
	if not top_identity_mode_button.button_pressed or not identity_mode_button.button_pressed or top_navigation_buttons.size() != 2 or top_navigation_buttons[0] != top_identity_mode_button or top_navigation_buttons[1] != online_settings_button or mode_list.find_children("*", "Button", true, false).size() != 1:
		_fail("top_navigation_entries")
		return
	if top_identity_mode_button.text != "模式选择" or identity_mode_name.text != "身份模式" or identity_mode_name.get_theme_font_size("font_size") != 27 or identity_mode_player_count.text != "2-10人" or mode_rule_hint.text != "随机身份 · 阵营对抗":
		_fail("identity_mode_copy")
		return
	# 默认客户区矩形；打开联机设置前记录，用于断言资料页与模式预览使用同一客户区，而不是全屏弹层。
	var mode_page_rect: Rect2 = main_frame.get_global_rect()
	await _click_control(online_settings_button)
	await get_tree().process_frame
	# 动态联机形象牌；每个数据库武将都必须对应一张正式 PlayerTargetView 候选。
	var online_avatar_views: Array[Node] = online_avatar_content.find_children("*", "PlayerTargetView", true, false)
	# 联机设置页矩形；必须贴合原主菜单客户区，顶部导航仍可聚焦并可对等切回模式选择。
	var online_settings_rect: Rect2 = online_settings_panel.get_global_rect()
	if not online_settings_panel.visible or main_frame.visible or online_player_name_input.max_length != GameSettings.MAX_ONLINE_PLAYER_NAME_LENGTH or online_avatar_views.size() != GameDatabase.characters.size() or start_game_button.focus_mode != Control.FOCUS_NONE or top_identity_mode_button.focus_mode == Control.FOCUS_NONE or online_settings_button.focus_mode == Control.FOCUS_NONE or not online_settings_button.button_pressed or top_identity_mode_button.button_pressed or not (main_instance.get_node("%TopOnlineSettingsIndicator") as ColorRect).visible or (main_instance.get_node("%TopIdentityModeIndicator") as ColorRect).visible or absf(online_settings_rect.position.x - mode_page_rect.position.x) > 0.5 or absf(online_settings_rect.position.y - mode_page_rect.position.y) > 0.5 or absf(online_settings_rect.size.x - mode_page_rect.size.x) > 0.5 or absf(online_settings_rect.size.y - mode_page_rect.size.y) > 0.5:
		_fail("online_settings_open")
		return
	# 测试选择的武将牌；读取组件内部的只读预览快照，仅用于确认点击保存的是稳定武将 ID。
	var selected_avatar_view: PlayerTargetView = online_avatar_views[online_avatar_views.size() - 1] as PlayerTargetView
	# 测试武将快照；资料面板不会创建真实玩家，因此这里只消费 character_id 展示字段。
	var selected_avatar_snapshot: Dictionary = selected_avatar_view.get("_player_snapshot") as Dictionary
	# 测试目标武将 ID；保存后必须原样写入全局联机形象配置。
	var selected_avatar_character_id: String = str(selected_avatar_snapshot.get("character_id", ""))
	# 测试武将牌输入区域；使用真实鼠标事件验证滚动内容中的正式牌面可以被点击选择。
	var selected_avatar_input_area: Control = selected_avatar_view.get_node("InputArea") as Control
	online_player_name_input.text = "  联机测试玩家  "
	await _click_control(selected_avatar_input_area)
	await _click_control(online_settings_save_button)
	await get_tree().process_frame
	if online_settings_panel.visible or not main_frame.visible or GameSettings.online_player_name != "联机测试玩家" or GameSettings.online_avatar_character_id != selected_avatar_character_id or online_settings_button.focus_mode == Control.FOCUS_NONE or not top_identity_mode_button.button_pressed or online_settings_button.button_pressed:
		_fail("online_settings_save")
		return
	# 顶部导航对等切页；再次进入联机设置后点击“模式选择”必须直接切回默认内容，而不是依赖保存/取消弹窗。
	await _click_control(online_settings_button)
	await get_tree().process_frame
	if not online_settings_panel.visible or main_frame.visible or not online_settings_button.button_pressed or top_identity_mode_button.button_pressed or top_identity_mode_button.focus_mode == Control.FOCUS_NONE:
		_fail("online_settings_reopen_page")
		return
	await _click_control(top_identity_mode_button)
	await get_tree().process_frame
	if online_settings_panel.visible or not main_frame.visible or not top_identity_mode_button.button_pressed or online_settings_button.button_pressed:
		_fail("online_settings_switch_to_mode_page")
		return
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.position = Vector2.ZERO
	main_instance.size = Vector2(1152.0, 648.0)
	await get_tree().process_frame
	await get_tree().process_frame
	if top_navigation.get_rect().end.y > main_frame.get_rect().position.y:
		_fail("compact_navigation_overlap")
		return
	# 普通主菜单焦点循环索引；12次正向导航覆盖当前入口并跨越首尾，隐藏设置与牌桌控件均不得进入焦点链。
	for _main_menu_focus_index: int in range(12):
		await _press_action("ui_focus_next")
		# 当前普通主菜单焦点；只允许落在可见主菜单且不属于隐藏设置面板的控件上。
		var main_menu_focus_owner: Control = get_viewport().gui_get_focus_owner()
		if main_menu_focus_owner == null or not main_menu.is_ancestor_of(main_menu_focus_owner) or settings_panel.is_ancestor_of(main_menu_focus_owner):
			_fail("main_menu_focus_boundary")
			return
	GameDatabase.validation_errors.append(START_FAILURE_TEST_ERROR)
	await _click_control(start_game_button)
	await get_tree().process_frame
	if not main_menu.visible or match_controller.state != null or not menu_status_label.text.contains(START_FAILURE_TEST_ERROR) or start_game_button.disabled:
		GameDatabase.validation_errors.erase(START_FAILURE_TEST_ERROR)
		_fail("start_failure_recovery")
		return
	GameDatabase.validation_errors.erase(START_FAILURE_TEST_ERROR)
	# 原始武将元数据；临时清空用于触发选将服务的后置初始化失败，随后原样恢复供成功开局使用。
	var original_characters: Dictionary = GameDatabase.characters
	GameDatabase.characters = {}
	await _click_control(start_game_button)
	await get_tree().process_frame
	if not main_menu.visible or match_controller.state != null or not menu_status_label.text.contains("没有可用于选将的武将配置") or start_game_button.disabled:
		GameDatabase.characters = original_characters
		_fail("post_initialization_failure_recovery")
		return
	if not _is_failed_match_runtime_discarded(match_controller):
		GameDatabase.characters = original_characters
		_fail("post_initialization_runtime_cleanup")
		return
	GameDatabase.characters = original_characters
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_DECADE_WOOD)
	await get_tree().process_frame
	if not (top_navigation.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "border")):
		_fail("theme_refresh")
		return
	if not (action_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "accent")) or not (ai_response_slider.get_theme_stylebox("grabber_area") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "accent")) or not (player_count_line_edit.get_theme_stylebox("normal") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "border")):
		_fail("settings_theme_refresh")
		return
	GameSettings.set_ui_style(UIStyleRegistry.DEFAULT_STYLE_ID)
	await get_tree().process_frame
	await _click_control(settings_button)
	if not settings_panel.visible or not settings_backdrop.visible or settings_backdrop.z_index <= main_frame.z_index or not settings_backdrop.get_global_rect().has_point(start_game_button.get_global_rect().get_center()):
		_fail("settings_open")
		return
	if start_game_button.focus_mode != Control.FOCUS_NONE or settings_button.focus_mode != Control.FOCUS_NONE or online_settings_button.focus_mode != Control.FOCUS_NONE or top_identity_mode_button.focus_mode != Control.FOCUS_NONE or identity_mode_button.focus_mode != Control.FOCUS_NONE or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
		_fail("settings_background_focus_suspension")
		return
	# 正向焦点循环索引；12次导航覆盖设置面板当前全部控件并再次跨越首尾边界，默认值不影响业务配置。
	for _focus_next_index: int in range(12):
		await _press_action("ui_focus_next")
		# 当前正向导航焦点；每次 Tab 后都必须仍属于设置面板，不能落到底层模式、设置或开始按钮。
		var next_focus_owner: Control = get_viewport().gui_get_focus_owner()
		if next_focus_owner == null or not settings_panel.is_ancestor_of(next_focus_owner):
			_fail("settings_focus_next_trap")
			return
	# 反向焦点循环索引；使用相同次数验证 Shift+Tab 与手柄反向导航不会从另一端逃逸。
	for _focus_previous_index: int in range(12):
		await _press_action("ui_focus_prev")
		# 当前反向导航焦点；Shift+Tab 与手柄反向导航必须遵循和正向导航相同的模态边界。
		var previous_focus_owner: Control = get_viewport().gui_get_focus_owner()
		if previous_focus_owner == null or not settings_panel.is_ancestor_of(previous_focus_owner):
			_fail("settings_focus_previous_trap")
			return
	await _click_control(start_game_button)
	if settings_panel.visible or settings_backdrop.visible or match_controller.state != null or not main_menu.visible:
		_fail("settings_modal_input")
		return
	if start_game_button.focus_mode == Control.FOCUS_NONE or settings_button.focus_mode == Control.FOCUS_NONE or online_settings_button.focus_mode == Control.FOCUS_NONE or top_identity_mode_button.focus_mode == Control.FOCUS_NONE or identity_mode_button.focus_mode == Control.FOCUS_NONE or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
		_fail("settings_background_focus_restore")
		return
	await _click_control(settings_button)
	await _click_control(settings_close_button)
	if settings_panel.visible or settings_backdrop.visible:
		_fail("settings_close")
		return
	await _click_control(settings_button)
	# 模拟玩家仍在编辑框内输入人数；开始按钮必须优先读取这份尚未失焦的文本。
	player_count_input.get_line_edit().text = "6"
	await _click_control(settings_close_button)
	await _click_control(start_game_button)
	for _start_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if main_menu.visible or settings_panel.visible or match_controller.state == null or match_controller.state.players.size() != 6 or match_controller.default_player_count != 6:
		_fail("start_identity_match")
		return
	if match_menu_button.focus_mode == Control.FOCUS_NONE or log_toggle_button.focus_mode == Control.FOCUS_NONE:
		_fail("match_focus_restore")
		return
	# 前置重开失败前的权威状态实例；数据校验拒绝不能替换、清空或在主菜单背后继续另一份半成品状态。
	var running_match_state: GameState = match_controller.state
	GameDatabase.validation_errors.append(START_FAILURE_TEST_ERROR)
	await _click_control(match_menu_button)
	await _click_control(match_restart_button)
	# 前置失败稳定帧索引；等待拒绝信号与局内菜单恢复完成，同时允许检测旧状态实例是否仍保持有效。
	for _preflight_failure_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if main_menu.visible or match_controller.state != running_match_state or not match_menu_panel.visible or not match_error_label.text.contains(START_FAILURE_TEST_ERROR):
		GameDatabase.validation_errors.erase(START_FAILURE_TEST_ERROR)
		_fail("in_match_preflight_failure_preserves_match")
		return
	GameDatabase.validation_errors.erase(START_FAILURE_TEST_ERROR)
	GameDatabase.characters = {}
	await _click_control(match_restart_button)
	# 局内失败稳定帧索引；等待菜单恢复、焦点延迟与错误提示完成，不推进或修改任何规则数值。
	for _restart_failure_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if not main_menu.visible or match_controller.state != null or not menu_status_label.text.contains("没有可用于选将的武将配置") or start_game_button.disabled or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
		GameDatabase.characters = original_characters
		_fail("in_match_restart_failure_recovery")
		return
	if not _is_failed_match_runtime_discarded(match_controller):
		GameDatabase.characters = original_characters
		_fail("in_match_restart_runtime_cleanup")
		return
	# 重开后置失败焦点循环索引；恢复后的主菜单必须重新建立和首次启动相同的键盘边界。
	for _restored_menu_focus_index: int in range(12):
		await _press_action("ui_focus_next")
		# 当前恢复主菜单焦点；不允许进入隐藏设置或仍存在于场景树中的局内控件。
		var restored_menu_focus_owner: Control = get_viewport().gui_get_focus_owner()
		if restored_menu_focus_owner == null or not main_menu.is_ancestor_of(restored_menu_focus_owner) or settings_panel.is_ancestor_of(restored_menu_focus_owner):
			GameDatabase.characters = original_characters
			_fail("restored_main_menu_focus_boundary")
			return
	GameDatabase.characters = original_characters
	await _click_control(start_game_button)
	# 失败后重试稳定帧索引；覆盖新对局状态广播与菜单关闭，次数沿用统一测试等待常量。
	for _restart_recovery_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if main_menu.visible or match_controller.state == null or match_controller.state.players.size() != 6 or match_menu_button.focus_mode == Control.FOCUS_NONE or log_toggle_button.focus_mode == Control.FOCUS_NONE:
		_fail("in_match_restart_retry")
		return
	# 终局快照；只改客户端快照终局标记，验证操作区按钮无需等待额外阶段或真实胜负动画。
	var terminal_snapshot: Dictionary = match_controller.state.to_dict(match_controller.local_human_player_id, true)
	terminal_snapshot["game_over"] = true
	terminal_snapshot["current_phase"] = "end"
	terminal_snapshot["winner"] = "draw"
	match_controller.state_changed.emit(terminal_snapshot)
	await get_tree().process_frame
	var interaction_guide_label: Label = main_instance.get_node("%InteractionGuideLabel") as Label
	if interaction_use_button.text != "重新开始" or interaction_cancel_button.text != "返回主菜单" or interaction_guide_label.text != "对局结算，游戏平局" or interaction_use_button.disabled or interaction_cancel_button.disabled:
		_fail("post_match_actions")
		return
	# 点击终局返回按钮；必须释放当前权威状态并恢复主菜单，而不是保留一个不可继续的旧对局。
	await _click_control(interaction_cancel_button)
	for _return_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if not main_menu.visible or match_controller.state != null:
		_fail("post_match_return_main_menu visible=%s state=%s use=%s cancel=%s" % [main_menu.visible, match_controller.state, interaction_use_button.text, interaction_cancel_button.text])
		return
	print("MAIN_MENU_PASS post_match_return=true")
	main_instance.queue_free()
	get_tree().quit()


## 输出稳定失败标识并以非零状态结束测试；避免后续异步对局逻辑掩盖首个断言错误。
func _fail(reason: String) -> void:
	printerr("MAIN_MENU_FAIL %s" % reason)
	get_tree().quit(1)


## 返回控件在视口屏幕坐标中的矩形；真实鼠标事件必须使用画布变换后的坐标才能命中缩放界面。
func _screen_rect(control: Control) -> Rect2:
	# 控件当前屏幕变换；包含项目画布缩放、父节点位置和控件自身布局变换。
	var screen_transform: Transform2D = control.get_screen_transform()
	# 控件左上角屏幕坐标；局部原点经完整屏幕变换得到。
	var top_left: Vector2 = screen_transform * Vector2.ZERO
	# 控件右下角屏幕坐标；局部尺寸经同一变换后与左上角共同构成命中矩形。
	var bottom_right: Vector2 = screen_transform * control.size
	return Rect2(top_left, bottom_right - top_left)


## 向控件中心发送完整鼠标移动、按下与释放序列；验证真实GUI命中、遮罩层级和按钮可交互状态。
func _click_control(control: Control) -> void:
	# 控件屏幕中心；事件坐标与真实窗口输入使用同一坐标空间。
	var click_position: Vector2 = _screen_rect(control).get_center()
	# 鼠标移动事件；先建立当前悬停目标，保证按钮和模态遮罩按正常GUI路径处理按键。
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.position = click_position
	get_viewport().push_input(motion_event, true)
	await get_tree().process_frame
	# 鼠标按下事件；使用左键并交给视口分发，不直接发射 pressed 信号。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.position = click_position
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	get_viewport().push_input(press_event, true)
	await get_tree().process_frame
	# 鼠标释放事件；完整点击序列完成后，实际命中的 Button 才能发出 pressed。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.position = click_position
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	get_viewport().push_input(release_event, true)
	await get_tree().process_frame


## 向视口发送一次完整动作按下与释放；用于覆盖真实键盘或手柄焦点导航，不直接调用控件方法。
func _press_action(action_name: StringName) -> void:
	# 动作按下事件；动作名使用项目内置 ui_focus_next 或 ui_focus_prev 映射，交由 Godot GUI 焦点系统处理。
	var press_event: InputEventAction = InputEventAction.new()
	press_event.action = action_name
	press_event.pressed = true
	get_viewport().push_input(press_event, true)
	await get_tree().process_frame
	# 动作释放事件；完整释放避免后续测试帧继承持续按压状态并重复移动焦点。
	var release_event: InputEventAction = InputEventAction.new()
	release_event.action = action_name
	release_event.pressed = false
	get_viewport().push_input(release_event, true)
	await get_tree().process_frame


## 检查后置开局失败是否完整释放本局运行时；返回 true 表示控制器已恢复为可安全重试的空入口状态。
func _is_failed_match_runtime_discarded(match_controller: MatchController) -> bool:
	return (
		match_controller.state == null
		and match_controller.character_selection == null
		and match_controller.card_rules == null
		and match_controller.effect_resolver == null
		and match_controller.card_movement == null
		and match_controller.modifier_pipeline == null
		and match_controller.rule_query == null
		and match_controller.trigger_manager == null
		and match_controller.timing_service == null
		and match_controller.event_scheduler.root_event_id == -1
		and match_controller.event_scheduler.get_event_history_count() == 0
		and match_controller.event_scheduler.get_pending_choice_requests().is_empty()
		and match_controller.event_scheduler.pause_registry.get_active_tokens().is_empty()
		and match_controller.ai_coordinator._policies.is_empty()
	)
