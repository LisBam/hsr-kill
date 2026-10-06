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
	# 主菜单回归固定从身份模式开始；避免其他模式测试留下的持久化选择改变本测试的默认文案与六人开局断言。
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_IDENTITY)
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
	# 顶部所有卡牌按钮；必须与模式选择、联机设置同级并切换到独立图鉴客户区。
	var all_cards_button: Button = main_instance.get_node("%MainMenuAllCardsButton") as Button
	# 顶部对局回放按钮；必须位于所有卡牌右侧并对等切换到独立回放客户区。
	var match_replay_button: Button = main_instance.get_node("%MainMenuMatchReplayButton") as Button
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
	# 联机设置左侧分区列表；宽与模式选择左侧栏一致，确保两页同款左右分栏。
	var online_side_list: PanelContainer = online_settings_panel.get_node("%OnlineSettingsSideList") as PanelContainer
	# 联机设置左侧分区卡片；当前唯一“联机资料”入口，对应模式选择页的身份模式卡。
	var online_profile_section_button: Button = online_settings_panel.get_node("%OnlineProfileSectionButton") as Button
	# 联机设置底部操作栏；高度与模式选择底部操作栏一致。
	var online_action_panel: PanelContainer = online_settings_panel.get_node("%OnlineSettingsActionPanel") as PanelContainer
	# 所有卡牌内容页；只读取静态目录并提供武将、游戏牌和机缘三个子分页。
	var all_cards_panel: AllCardsPanel = main_instance.get_node("%AllCardsPanel") as AllCardsPanel
	# 所有武将子分页按钮；图鉴首次打开时必须默认选中。
	var all_characters_tab_button: Button = all_cards_panel.get_node("%AllCharactersTabButton") as Button
	# 所有武将牌子分页标题；玩家可见文案必须包含“牌”字以与另外两类卡牌保持一致。
	var all_characters_tab_name: Label = all_cards_panel.get_node("%AllCharactersTabName") as Label
	# 所有游戏牌子分页按钮；点击后展示数据库中每种游戏牌定义。
	var all_game_cards_tab_button: Button = all_cards_panel.get_node("%AllGameCardsTabButton") as Button
	# 所有机缘子分页按钮；点击后展示含灰色关卡机缘在内的完整目录。
	var all_opportunities_tab_button: Button = all_cards_panel.get_node("%AllOpportunitiesTabButton") as Button
	# 所有机缘牌子分页标题；玩家可见文案必须明确该分类展示的是机缘牌。
	var all_opportunities_tab_name: Label = all_cards_panel.get_node("%AllOpportunitiesTabName") as Label
	# 图鉴搜索输入框；当前子分页内容应随文本即时过滤。
	var all_cards_search_input: LineEdit = all_cards_panel.get_node("%AllCardsSearchInput") as LineEdit
	# 图鉴动态网格内容；用于确认每类条目复用正式牌面场景且数量完整。
	var all_cards_grid_content: Control = all_cards_panel.get_node("%AllCardsGridContent") as Control
	# 图鉴动态网格滚动区；三类卡牌共用模式选择同款纵向滑条并为最右列保留安全间距。
	var all_cards_grid_scroll: ScrollContainer = all_cards_panel.get_node("%AllCardsGridScroll") as ScrollContainer
	# 图鉴结果数量标签；搜索后必须同时显示命中数与当前分类总数。
	var all_cards_result_count_label: Label = all_cards_panel.get_node("%AllCardsResultCountLabel") as Label
	# 图鉴完整资料遮罩；点击牌面后显示规则正文并阻断底层输入。
	var all_cards_information_backdrop: ColorRect = all_cards_panel.get_node("%AllCardsInfoBackdrop") as ColorRect
	# 图鉴完整资料标题；用于确认点击的是当前类别中的真实静态定义。
	var all_cards_information_title: Label = all_cards_panel.get_node("%AllCardsInfoTitle") as Label
	# 图鉴武将详情双栏主体；武将牌详情打开时显示，其他卡牌资料使用通用正文滚动区。
	var all_cards_character_information_body: HBoxContainer = all_cards_panel.get_node("%AllCardsInfoCharacterBody") as HBoxContainer
	# 图鉴武将详情左侧牌面区域；必须承载一张正式 PlayerTargetView。
	var all_cards_character_information_card_area: Control = all_cards_panel.get_node("%AllCardsInfoCharacterCardArea") as Control
	# 图鉴通用资料滚动区；武将详情打开时隐藏，游戏牌与机缘详情打开时恢复。
	var all_cards_information_scroll: ScrollContainer = all_cards_panel.get_node("%AllCardsInfoScroll") as ScrollContainer
	# 图鉴左侧子分页列表；宽度应与模式选择和联机设置列表保持一致。
	var all_cards_side_list: PanelContainer = all_cards_panel.get_node("%AllCardsSideList") as PanelContainer
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
	# 左侧斗地主模式按钮；与身份模式共用模式卡片选中底色规范。
	var doudizhu_mode_button: Button = main_instance.get_node("%DouDizhuModeButton") as Button
	# 左侧2v2模式按钮；与另外两种模式共用模式卡片选中底色规范。
	var team2v2_mode_button: Button = main_instance.get_node("%Team2v2ModeButton") as Button
	# 左侧1v1车轮战模式按钮；与其他模式共用相同卡片样式和稳定排列。
	var wheel_duel_mode_button: Button = main_instance.get_node("%WheelDuelModeButton") as Button
	# 左侧机缘大乱斗模式按钮；排列在车轮战之后并复用同一模式卡片视觉规范。
	var opportunity_brawl_mode_button: Button = main_instance.get_node("%OpportunityBrawlModeButton") as Button
	# 左侧机缘大乱斗模式标题；新增入口必须与原版模式卡使用相同27像素标题字号。
	var opportunity_brawl_mode_name: Label = main_instance.get_node("%OpportunityBrawlModeName") as Label
	# 左侧过关斩将模式按钮；排列在机缘大乱斗之后，并固定以同一模式卡片规格呈现。
	var conquest_mode_button: Button = main_instance.get_node("%ConquestModeButton") as Button
	# 左侧过关斩将模式标题；新增入口必须与原版模式卡使用相同27像素标题字号。
	var conquest_mode_name: Label = main_instance.get_node("%ConquestModeName") as Label
	# 左侧胜者为王模式按钮；排列在过关斩将之后，并固定以同一模式卡片规格呈现。
	var winner_takes_all_mode_button: Button = main_instance.get_node("%WinnerTakesAllModeButton") as Button
	# 左侧胜者为王模式标题；新增入口必须与原版模式卡使用相同27像素标题字号。
	var winner_takes_all_mode_name: Label = main_instance.get_node("%WinnerTakesAllModeName") as Label
	# 主菜单座次补偿开关；仅胜者为王模式显示，其余模式必须隐藏该行。
	var main_seat_compensation_checkbox: CheckBox = main_instance.get_node("%MainMenuSeatCompensationCheckBox") as CheckBox
	# 左侧身份模式标题；必须独立于按钮文本呈现，以便标题可使用更大的主题字号。
	var identity_mode_name: Label = main_instance.get_node("%IdentityModeName") as Label
	# 左侧身份模式人数说明；仅展示可选人数范围，不重复标准身份局描述。
	var identity_mode_player_count: Label = main_instance.get_node("%IdentityModePlayerCount") as Label
	# 右侧模式规则提示；当前只保留随机身份和阵营对抗两项核心玩法说明。
	var mode_rule_hint: Label = main_instance.get_node("%MainMenuModeRuleHint") as Label
	# 模式预览左上角详情按钮；仅斗地主、机缘大乱斗与过关斩将显示。
	var mode_details_button: Button = main_instance.get_node("MainMenu/MainMenuFrame/MainMenuContent/MainMenuPreviewPanel/MainMenuPreviewContent/MainMenuModeDetailsButton") as Button
	# 模式详情居中面板；点击入口后显示当前模式的完整长期说明。
	var mode_details_panel: PanelContainer = main_instance.get_node("MainMenu/MainMenuModeDetailsPanel") as PanelContainer
	# 模式详情标题；用于确认弹窗内容跟随当前模式而不是残留上次说明。
	var mode_details_title: Label = mode_details_panel.get_node("ModeDetailsContent/Title") as Label
	# 模式详情正文；必须包含模式关键机制而非仅重复预览短标题。
	var mode_details_description: Label = mode_details_panel.get_node("ModeDetailsContent/DescriptionScroll/Description") as Label
	# 模式详情关闭按钮；关闭后遮罩与面板必须一起退出。
	var mode_details_close_button: Button = mode_details_panel.get_node("ModeDetailsContent/CloseButton") as Button
	# 左侧模式面板；用于确认其中没有隐藏的第二个模式按钮。
	var mode_list: PanelContainer = main_instance.get_node("%MainMenuModeList") as PanelContainer
	# 左侧模式卡滚动窗口；新增模式只能扩展滚动内容，不能压缩原有卡片尺寸。
	var mode_scroll: ScrollContainer = main_instance.get_node("%MainMenuModeScroll") as ScrollContainer
	# 左侧模式卡纵向容器；保持原版12像素间距并作为滚动范围的唯一内容节点。
	var mode_cards: VBoxContainer = main_instance.get_node("%ModeCardsVBox") as VBoxContainer
	# 左侧模式列表固定标题；不随模式卡滚动并保留原版48像素高度。
	var mode_list_title: Label = main_instance.get_node("%MainMenuModeListTitle") as Label
	# 预览底部操作栏；主题切换后其描边必须使用当前主题强调色。
	var action_panel: PanelContainer = main_instance.get_node("%MainMenuActionPanel") as PanelContainer
	# 主菜单状态文字；开局失败时必须展示控制器返回的具体拒绝原因。
	var menu_status_label: Label = main_instance.get_node("%MainMenuStatusLabel") as Label
	# 主菜单全屏底色；必须停止未被前景面板覆盖区域的鼠标输入，避免误触局内隐藏控件。
	var menu_background: ColorRect = main_instance.get_node("%MainMenuBackground") as ColorRect
	# AI速度滑条；用于验证设置控件轨道也跟随当前主题，不保留默认 Godot 配色。
	var ai_response_slider: HSlider = main_instance.get_node("%MainMenuAiResponseDelaySlider") as HSlider
	# 主菜单游戏速度滑条；与AI速度共同验证主菜单设置入口读取统一的秒数范围与步长。
	var game_speed_slider: HSlider = main_instance.get_node("%MainMenuGameSpeedSlider") as HSlider
	# 游戏人数文本框；用于验证 SpinBox 编辑区的焦点与常态边框来自当前主题。
	var player_count_line_edit: LineEdit = player_count_input.get_line_edit()
	# 主菜单卡牌名称下拉框；必须与UI风格保持标签加下拉框的统一设置格式。
	var main_menu_card_name_option: OptionButton = main_instance.get_node("%MainMenuCardNameOption") as OptionButton
	# 主菜单 UI 风格下拉框；必须按注册表顺序显示全部主题并保存稳定标识元数据。
	var main_menu_ui_style_option: OptionButton = main_instance.get_node("%MainMenuUiStyleOption") as OptionButton
	# 局内卡牌名称下拉框；应使用与主菜单相同的两项稳定名称模式配置。
	var match_menu_card_name_option: OptionButton = main_instance.get_node("%MenuCardNameOption") as OptionButton
	# 主菜单自选开关；过关斩将中必须显示为纯“自选武将”，不暴露座次身份语义。
	var main_custom_character_checkbox: CheckBox = main_instance.get_node("%MainMenuCustomCharacterAssignmentCheckBox") as CheckBox
	# 局内自选开关；当前对局为过关斩将时与主菜单使用相同纯武将文案。
	var match_custom_character_checkbox: CheckBox = main_instance.get_node("%CustomCharacterAssignmentCheckBox") as CheckBox
	# 主菜单车轮战明置候选标签；必须在车轮战设置页使用统一回退字体和主题文字色。
	var main_wheel_face_up_label: Label = main_instance.get_node("MainMenu/MainMenuSettingsPanel/SettingsVBox/WheelDuelFaceUpCandidateRow/WheelDuelFaceUpCandidateLabel") as Label
	# 主菜单车轮战暗置候选标签；与明置标签共同验证局外菜单的字体和颜色覆盖。
	var main_wheel_face_down_label: Label = main_instance.get_node("MainMenu/MainMenuSettingsPanel/SettingsVBox/WheelDuelFaceDownCandidateRow/WheelDuelFaceDownCandidateLabel") as Label
	# 主菜单车轮战明置候选输入；其内部文本框必须使用主题字体、文字色和光标色。
	var main_wheel_face_up_input: SpinBox = main_instance.get_node("%WheelDuelFaceUpCandidateInput") as SpinBox
	# 主菜单车轮战暗置候选输入；数值与局内菜单共享同一GameSettings配置。
	var main_wheel_face_down_input: SpinBox = main_instance.get_node("%WheelDuelFaceDownCandidateInput") as SpinBox
	# 局内车轮战明置候选标签；完整路径避免与主菜单同名节点混淆。
	var match_wheel_face_up_label: Label = main_instance.get_node("MatchMenu/MenuPanel/MenuVBox/WheelDuelFaceUpCandidateRow/WheelDuelFaceUpCandidateLabel") as Label
	# 局内车轮战暗置候选标签；与明置标签共同验证重开菜单的字体和颜色覆盖。
	var match_wheel_face_down_label: Label = main_instance.get_node("MatchMenu/MenuPanel/MenuVBox/WheelDuelFaceDownCandidateRow/WheelDuelFaceDownCandidateLabel") as Label
	# 局内车轮战明置候选输入；稳定唯一名用于验证局内外数值同步。
	var match_wheel_face_up_input: SpinBox = main_instance.get_node("%MatchMenuWheelDuelFaceUpCandidateInput") as SpinBox
	# 局内车轮战暗置候选输入；稳定唯一名用于验证局内外数值同步。
	var match_wheel_face_down_input: SpinBox = main_instance.get_node("%MatchMenuWheelDuelFaceDownCandidateInput") as SpinBox
	# 手牌区上方原确定按钮；终局时复用为“重新开始”。
	var interaction_use_button: Button = main_instance.get_node("%UseButton") as Button
	# 手牌区上方原取消按钮；终局时复用为“返回主菜单”。
	var interaction_cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	# 终局结算入口；关闭自动弹出的结算面板后应位于重新开始与返回主菜单之间并可再次打开。
	var interaction_settlement_button: Button = main_instance.get_node("%SettlementButton") as Button
	if main_menu == null or not main_menu.visible or match_controller.state != null or settings_button.text != "设置" or online_settings_button.text != "联机设置" or all_cards_button.text != "所有卡牌" or match_replay_button.text != "对局回放" or start_game_button.text != "开始游戏" or settings_panel.visible or online_settings_panel.visible or all_cards_panel.visible or settings_backdrop.visible or mode_details_button.visible or mode_details_panel.visible or menu_background.mouse_filter != Control.MOUSE_FILTER_STOP or menu_status_label.visible or not menu_status_label.text.is_empty() or (main_instance.get_node("MatchMenu") as MatchMenu).visible or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
		_fail("startup_state")
		return
	if main_menu_card_name_option == null or match_menu_card_name_option == null or main_menu_card_name_option.item_count != 2 or match_menu_card_name_option.item_count != 2 or main_menu_card_name_option.get_item_text(0) != "崩铁杀" or main_menu_card_name_option.get_item_text(1) != "三国杀":
		_fail("card_name_option_layout")
		return
	if main_menu_ui_style_option == null or main_menu_ui_style_option.item_count != 3 or main_menu_ui_style_option.get_item_text(0) != "崩铁风格" or main_menu_ui_style_option.get_item_text(1) != "暖木家园" or main_menu_ui_style_option.get_item_text(2) != "高级黑金" or str(main_menu_ui_style_option.get_item_metadata(2)) != UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD:
		_fail("ui_style_option_layout")
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
	# 当前主题下模式卡片的目标选中底色；读取模式卡专用底色与主题加深比例，避免与主操作按钮语义混合。
	var expected_selected_mode_background: Color = BattleUIStyle.get_color("mode_button", BattleUIStyle.get_color("action_button")).darkened(float(UIStyleRegistry.get_value(BattleUIStyle.get_active_style_id(), "mode_selected_background_darkening", main_menu.mode_selected_background_darkening)))
	# 身份模式卡片的持续选中样式；按钮保持按下时应使用主题定义的加深内部底色。
	var identity_selected_style: StyleBoxFlat = identity_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 斗地主卡片的持续选中样式；未选中时同样预先持有正确的按下态样式以供切换使用。
	var doudizhu_selected_style: StyleBoxFlat = doudizhu_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 2v2卡片的持续选中样式；三张卡片必须保持完全一致的选中颜色规则。
	var team2v2_selected_style: StyleBoxFlat = team2v2_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 1v1车轮战卡片的持续选中样式；四张模式卡片使用同一视觉规则。
	var wheel_duel_selected_style: StyleBoxFlat = wheel_duel_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 机缘大乱斗卡片的持续选中样式；第五张模式卡片仍使用完全相同的选中底色。
	var opportunity_brawl_selected_style: StyleBoxFlat = opportunity_brawl_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 过关斩将卡片的持续选中样式；第六张模式卡片必须沿用统一的主题选中底色。
	var conquest_selected_style: StyleBoxFlat = conquest_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 胜者为王卡片的持续选中样式；第七张模式卡片必须沿用统一的主题选中底色。
	var winner_takes_all_selected_style: StyleBoxFlat = winner_takes_all_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	if identity_selected_style == null or doudizhu_selected_style == null or team2v2_selected_style == null or wheel_duel_selected_style == null or opportunity_brawl_selected_style == null or conquest_selected_style == null or winner_takes_all_selected_style == null or not identity_selected_style.bg_color.is_equal_approx(expected_selected_mode_background) or not doudizhu_selected_style.bg_color.is_equal_approx(expected_selected_mode_background) or not team2v2_selected_style.bg_color.is_equal_approx(expected_selected_mode_background) or not wheel_duel_selected_style.bg_color.is_equal_approx(expected_selected_mode_background) or not opportunity_brawl_selected_style.bg_color.is_equal_approx(expected_selected_mode_background) or not conquest_selected_style.bg_color.is_equal_approx(expected_selected_mode_background) or not winner_takes_all_selected_style.bg_color.is_equal_approx(expected_selected_mode_background):
		_fail("mode_selected_background")
		return
	# 顶部按钮顺序；“联机设置”必须紧跟在“模式选择”右侧，左侧游戏模式列表仍只有身份模式一项。
	# 当前左侧游戏模式列表固定按身份模式、斗地主、2v2、1v1车轮战、机缘大乱斗、过关斩将、胜者为王排列，七项均直接可选。
	var top_navigation_buttons: Array[Node] = top_navigation.find_children("*", "Button", true, false)
	# 左侧模式按钮顺序；用于防止后续场景编辑意外改变稳定模式入口排列。
	var mode_list_buttons: Array[Node] = mode_list.find_children("*", "Button", true, false)
	if not top_identity_mode_button.button_pressed or not identity_mode_button.button_pressed or top_navigation_buttons.size() != 4 or top_navigation_buttons[0] != top_identity_mode_button or top_navigation_buttons[1] != online_settings_button or top_navigation_buttons[2] != all_cards_button or top_navigation_buttons[3] != match_replay_button or mode_list_buttons.size() != 7 or mode_list_buttons[0] != identity_mode_button or mode_list_buttons[1] != doudizhu_mode_button or mode_list_buttons[2] != team2v2_mode_button or mode_list_buttons[3] != wheel_duel_mode_button or mode_list_buttons[4] != opportunity_brawl_mode_button or mode_list_buttons[5] != conquest_mode_button or mode_list_buttons[6] != winner_takes_all_mode_button:
		_fail("top_navigation_entries top=%s modes=%s pressed=%s/%s" % [str(top_navigation_buttons), str(mode_list_buttons), top_identity_mode_button.button_pressed, identity_mode_button.button_pressed])
		return
	# 车轮战模式专属设置；局内、局外必须同时显示明置与暗置数量，并应用同一字体、文字色及全局配置值。
	main_menu.call("_select_wheel_duel_mode")
	# 局内菜单组件；用于把当前模式切为车轮战并验证对应设置行。
	var match_menu: MatchMenu = main_instance.get_node("MatchMenu") as MatchMenu
	match_menu.set_match_mode(GameSettings.MATCH_MODE_WHEEL_DUEL)
	# 车轮战设置标签期望颜色；取当前主题次级文字语义。
	var expected_menu_text_color: Color = BattleUIStyle.get_color("text_secondary")
	# 车轮战数值输入期望颜色；取当前主题主要文字语义。
	var expected_input_text_color: Color = BattleUIStyle.get_color("text_primary")
	if not main_wheel_face_up_input.get_parent().visible or not main_wheel_face_down_input.get_parent().visible or not match_wheel_face_up_input.get_parent().visible or not match_wheel_face_down_input.get_parent().visible or main_wheel_face_up_label.get_theme_font("font") != ThemeDB.fallback_font or main_wheel_face_down_label.get_theme_font("font") != ThemeDB.fallback_font or match_wheel_face_up_label.get_theme_font("font") != ThemeDB.fallback_font or match_wheel_face_down_label.get_theme_font("font") != ThemeDB.fallback_font or not main_wheel_face_up_label.get_theme_color("font_color").is_equal_approx(expected_menu_text_color) or not main_wheel_face_down_label.get_theme_color("font_color").is_equal_approx(expected_menu_text_color) or not match_wheel_face_up_label.get_theme_color("font_color").is_equal_approx(expected_menu_text_color) or not match_wheel_face_down_label.get_theme_color("font_color").is_equal_approx(expected_menu_text_color) or main_wheel_face_up_input.get_line_edit().get_theme_font("font") != ThemeDB.fallback_font or match_wheel_face_up_input.get_line_edit().get_theme_font("font") != ThemeDB.fallback_font or not main_wheel_face_up_input.get_line_edit().get_theme_color("font_color").is_equal_approx(expected_input_text_color) or not match_wheel_face_up_input.get_line_edit().get_theme_color("font_color").is_equal_approx(expected_input_text_color) or int(main_wheel_face_up_input.value) != GameSettings.wheel_duel_face_up_candidate_count or int(match_wheel_face_up_input.value) != GameSettings.wheel_duel_face_up_candidate_count or int(main_wheel_face_down_input.value) != GameSettings.wheel_duel_face_down_candidate_count or int(match_wheel_face_down_input.value) != GameSettings.wheel_duel_face_down_candidate_count:
		_fail("wheel_duel_menu_settings_style_or_sync")
		return
	# 模式卡滚动范围；七张100像素卡片加六段12像素间距必须高于可视区，确保新增入口通过滚动浏览而非缩小。
	var mode_scroll_bar: VScrollBar = mode_scroll.get_v_scroll_bar() if mode_scroll != null else null
	if mode_scroll == null or mode_cards == null or mode_list_title == null or mode_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED or mode_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_ALWAYS or absf(mode_list_title.custom_minimum_size.y - 48.0) > 0.5 or mode_cards.get_theme_constant("separation") != 12 or absf(identity_mode_button.custom_minimum_size.y - 100.0) > 0.5 or absf(doudizhu_mode_button.custom_minimum_size.y - 100.0) > 0.5 or absf(team2v2_mode_button.custom_minimum_size.y - 100.0) > 0.5 or absf(wheel_duel_mode_button.custom_minimum_size.y - 100.0) > 0.5 or absf(opportunity_brawl_mode_button.custom_minimum_size.y - 100.0) > 0.5 or absf(conquest_mode_button.custom_minimum_size.y - 100.0) > 0.5 or absf(winner_takes_all_mode_button.custom_minimum_size.y - 100.0) > 0.5 or mode_scroll_bar == null or mode_scroll_bar.max_value <= mode_scroll_bar.page:
		_fail("mode_scroll_layout title=%s cards=%s range=%s/%s" % [str(mode_list_title.custom_minimum_size if mode_list_title != null else Vector2.ZERO), str(mode_cards.get_theme_constant("separation") if mode_cards != null else -1), str(mode_scroll_bar.max_value if mode_scroll_bar != null else -1.0), str(mode_scroll_bar.page if mode_scroll_bar != null else -1.0)])
		return
	# 滑条轨道样式；上下内容边距为0才能让滑块在最小值和最大值处真正贴合轨道端点。
	var mode_scroll_track_style: StyleBoxFlat = mode_scroll_bar.get_theme_stylebox("scroll") as StyleBoxFlat
	# 滑条常态拖块样式；与轨道共用零边距几何，悬停和按下态由同一工厂生成。
	var mode_scroll_grabber_style: StyleBoxFlat = mode_scroll_bar.get_theme_stylebox("grabber") as StyleBoxFlat
	if mode_scroll_track_style == null or mode_scroll_grabber_style == null or not is_zero_approx(mode_scroll_track_style.content_margin_top) or not is_zero_approx(mode_scroll_track_style.content_margin_bottom) or not is_zero_approx(mode_scroll_grabber_style.content_margin_top) or not is_zero_approx(mode_scroll_grabber_style.content_margin_bottom):
		_fail("mode_scroll_endpoint_margins track=%s/%s grabber=%s/%s" % [str(mode_scroll_track_style.content_margin_top if mode_scroll_track_style != null else -1.0), str(mode_scroll_track_style.content_margin_bottom if mode_scroll_track_style != null else -1.0), str(mode_scroll_grabber_style.content_margin_top if mode_scroll_grabber_style != null else -1.0), str(mode_scroll_grabber_style.content_margin_bottom if mode_scroll_grabber_style != null else -1.0)])
		return
	# 滚动到底部后第七张模式卡必须完整进入视口；证明模式入口没有依赖裁切区域外的不可点击节点。
	mode_scroll.scroll_vertical = roundi(mode_scroll_bar.max_value - mode_scroll_bar.page)
	await get_tree().process_frame
	await get_tree().process_frame
	# 胜者为王模式卡全局矩形；滚动到底部后必须完整位于可视窗口内。
	var winner_takes_all_mode_rect: Rect2 = winner_takes_all_mode_button.get_global_rect()
	# 模式滚动窗口全局矩形；用于与第七张模式卡边界比较。
	var mode_scroll_rect: Rect2 = mode_scroll.get_global_rect()
	if winner_takes_all_mode_rect.position.y < mode_scroll_rect.position.y - 0.5 or winner_takes_all_mode_rect.end.y > mode_scroll_rect.end.y + 0.5:
		_fail("mode_scroll_bottom_visibility card=%s viewport=%s" % [str(winner_takes_all_mode_rect), str(mode_scroll_rect)])
		return
	# 滚轮交互；向下滚动必须改变内容位置，并让纵向滑条同步到同一值。
	main_menu.call("_set_mode_scroll_vertical", 0.0)
	# 模式滚动窗口屏幕中心；合成滚轮事件必须落在该命中区域内。
	var wheel_position: Vector2 = _screen_rect(mode_scroll).get_center()
	# 向下滚轮事件；使用一格倍率验证统一滚动入口。
	var wheel_down_event: InputEventMouseButton = InputEventMouseButton.new()
	wheel_down_event.position = wheel_position
	wheel_down_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down_event.pressed = true
	wheel_down_event.factor = 1.0
	get_viewport().push_input(wheel_down_event, true)
	await get_tree().process_frame
	# 滚轮后的内容滚动值；必须为正并与拖条值一致。
	var wheel_scroll_value: int = mode_scroll.scroll_vertical
	if wheel_scroll_value <= 0 or not is_equal_approx(mode_scroll_bar.value, wheel_scroll_value):
		_fail("mode_scroll_wheel_down scroll=%d bar=%f" % [wheel_scroll_value, mode_scroll_bar.value])
		return
	# 滚轮反向与拖条同步；向上滚动回到顶部时内容和滑条都必须归零。
	var wheel_up_event: InputEventMouseButton = InputEventMouseButton.new()
	wheel_up_event.position = wheel_position
	wheel_up_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up_event.pressed = true
	wheel_up_event.factor = 1.0
	get_viewport().push_input(wheel_up_event, true)
	await get_tree().process_frame
	if mode_scroll.scroll_vertical != 0 or not is_zero_approx(mode_scroll_bar.value):
		_fail("mode_scroll_wheel_up scroll=%d bar=%f" % [mode_scroll.scroll_vertical, mode_scroll_bar.value])
		return
	# 恢复底部视口；后续原有断言继续从第六张模式卡可见的位置验证真实点击。
	main_menu.call("_set_mode_scroll_vertical", mode_scroll_bar.max_value - mode_scroll_bar.page)
	await get_tree().process_frame
	# 通过滚动窗口内的真实鼠标点击选择第六项；模式切换不能依赖列表外部快捷入口。
	await _click_control(conquest_mode_button)
	await get_tree().process_frame
	if not conquest_mode_button.button_pressed or GameSettings.next_match_mode != GameSettings.MATCH_MODE_CONQUEST:
		_fail("mode_scroll_conquest_click")
		return
	# 过关斩将专属开局设置；换将卡与随机选将牌数均须显示，车轮战专属候选则不得误入该模式。
	# 主菜单过关斩将换将卡设置行；该模式保留普通换将配置。
	var main_conquest_replacement_row: Control = main_instance.get_node("MainMenu/MainMenuSettingsPanel/SettingsVBox/MainMenuCharacterReplacementCountRow") as Control
	# 主菜单过关斩将随机候选设置行；该模式保留普通候选数量配置。
	var main_conquest_candidate_row: Control = main_instance.get_node("MainMenu/MainMenuSettingsPanel/SettingsVBox/MainMenuCharacterCandidateCountRow") as Control
	# 主菜单过关斩将难度设置行；只在该模式显示。
	var main_conquest_difficulty_row: Control = main_instance.get_node("%MainMenuConquestDifficultyRow") as Control
	# 主菜单过关斩将难度下拉框；选项元数据与全局难度同步。
	var main_conquest_difficulty_option: OptionButton = main_instance.get_node("%MainMenuConquestDifficultyOption") as OptionButton
	# 局内菜单过关斩将换将卡设置行；应与主菜单使用相同显隐规则。
	var match_conquest_replacement_row: Control = main_instance.get_node("MatchMenu/MenuPanel/MenuVBox/CharacterReplacementCountRow") as Control
	# 局内菜单过关斩将随机候选设置行；应在该模式保持可见。
	var match_conquest_candidate_row: Control = main_instance.get_node("MatchMenu/MenuPanel/MenuVBox/CharacterCandidateCountRow") as Control
	# 局内菜单过关斩将难度设置行；只在当前对局模式适用时显示。
	var match_conquest_difficulty_row: Control = main_instance.get_node("%ConquestDifficultyRow") as Control
	# 局内菜单过关斩将难度下拉框；用于验证主菜单设置即时同步。
	var match_conquest_difficulty_option: OptionButton = main_instance.get_node("%ConquestDifficultyOption") as OptionButton
	match_menu.set_match_mode(GameSettings.MATCH_MODE_CONQUEST)
	if main_conquest_replacement_row == null or main_conquest_candidate_row == null or main_conquest_difficulty_row == null or match_menu == null or match_conquest_replacement_row == null or match_conquest_candidate_row == null or match_conquest_difficulty_row == null or main_custom_character_checkbox == null or match_custom_character_checkbox == null or not main_conquest_replacement_row.visible or not main_conquest_candidate_row.visible or not main_conquest_difficulty_row.visible or not match_conquest_replacement_row.visible or not match_conquest_candidate_row.visible or not match_conquest_difficulty_row.visible or not main_custom_character_checkbox.visible or not match_custom_character_checkbox.visible or main_custom_character_checkbox.text != "自选武将" or match_custom_character_checkbox.text != "自选武将":
		_fail("conquest_selection_settings_visible")
		return
	# 难度下拉同步；主菜单选择难度一后，局内下一局设置必须显示同一稳定选项。
	main_conquest_difficulty_option.item_selected.emit(0)
	await get_tree().process_frame
	if GameSettings.conquest_difficulty != 1 or int(match_conquest_difficulty_option.get_item_metadata(match_conquest_difficulty_option.selected)) != 1:
		_fail("conquest_difficulty_sync")
		return
	GameSettings.set_conquest_difficulty(GameSettings.DEFAULT_CONQUEST_DIFFICULTY)
	# 过关斩将人数契约：离线单人固定1名玩家对1名敌人（2个规则角色），
	# 控件显示文本必须与数值同步，且开局读取值不得被内部文本行的陈旧数字放大成联机语义的玩家数。
	if int(player_count_input.value) != GameSettings.OFFLINE_CONQUEST_ROLE_COUNT or player_count_input.get_line_edit().text != str(GameSettings.OFFLINE_CONQUEST_ROLE_COUNT) or main_menu.get_next_player_count() != GameSettings.OFFLINE_CONQUEST_ROLE_COUNT:
		_fail("conquest_offline_player_count")
		return
	# 过关斩将详情；按钮位于预览左上角，打开后正文必须包含复活与五档难度的完整开局效果。
	if not mode_details_button.visible:
		_fail("conquest_details_button_hidden")
		return
	await _click_control(mode_details_button)
	await get_tree().process_frame
	if not mode_details_panel.visible or mode_details_title.text != "过关斩将模式详情" or not mode_details_description.text.contains("复活") or not mode_details_description.text.contains("难度一：增加2点体力上限；摸牌阶段额外摸一张牌；初始手牌数+2；出牌阶段使用【杀】的次数上限+1；复活次数+1。") or not mode_details_description.text.contains("难度二：增加1点体力上限；摸牌阶段额外摸一张牌；初始手牌数+2；出牌阶段使用【杀】的次数上限+1。") or not mode_details_description.text.contains("难度三：增加1点体力上限；初始手牌数+2；出牌阶段使用【杀】的次数上限+1。") or not mode_details_description.text.contains("难度四：初始手牌数+1；出牌阶段使用【杀】的次数上限+1。") or not mode_details_description.text.contains("难度五：无额外增益。"):
		_fail("conquest_details_content")
		return
	await _click_control(mode_details_close_button)
	if mode_details_panel.visible:
		_fail("conquest_details_close")
		return
	mode_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await _click_control(identity_mode_button)
	await get_tree().process_frame
	match_menu.set_match_mode(GameSettings.MATCH_MODE_IDENTITY)
	if not identity_mode_button.button_pressed or GameSettings.next_match_mode != GameSettings.MATCH_MODE_IDENTITY or mode_details_button.visible or main_conquest_difficulty_row.visible or match_conquest_difficulty_row.visible or main_custom_character_checkbox.text != "自选全武将、座次与身份" or match_custom_character_checkbox.text != "自选全武将、座次与身份":
		_fail("mode_scroll_identity_restore")
		return
	# 另外两个开放详情的模式；斗地主说明不再保留身份局击杀奖惩文案。
	main_menu.call("_select_doudizhu_mode")
	if not mode_details_button.visible:
		_fail("doudizhu_details_button_hidden")
		return
	await _click_control(mode_details_button)
	await get_tree().process_frame
	if not mode_details_panel.visible or mode_details_title.text != "斗地主模式详情" or mode_details_description.text.contains("本模式不执行身份局击杀奖惩"):
		_fail("doudizhu_details_content")
		return
	await _click_control(mode_details_close_button)
	# 详情按钮必须低于设置遮罩；设置打开后其不会覆盖设置项或截获输入。
	if mode_details_button.z_index >= settings_backdrop.z_index:
		_fail("mode_details_button_settings_layer")
		return
	main_menu.call("_select_opportunity_brawl_mode")
	if not mode_details_button.visible:
		_fail("opportunity_brawl_details_button_hidden")
		return
	main_menu.call("_select_identity_mode")
	if top_identity_mode_button.text != "模式选择" or identity_mode_name.text != "身份模式" or identity_mode_name.get_theme_font_size("font_size") != 27 or opportunity_brawl_mode_name.get_theme_font_size("font_size") != 27 or conquest_mode_name.get_theme_font_size("font_size") != 27 or winner_takes_all_mode_name.get_theme_font_size("font_size") != 27 or identity_mode_player_count.text != "2-10人" or mode_rule_hint.text != "随机身份 · 阵营对抗":
		_fail("identity_mode_copy")
		return
	# 胜者为王详情；正文必须完整记录座次补偿的分段数值，这是该开关唯一的长期说明入口。
	main_menu.call("_select_winner_takes_all_mode")
	if not mode_details_button.visible or not winner_takes_all_mode_button.button_pressed or not main_seat_compensation_checkbox.visible or GameSettings.next_match_mode != GameSettings.MATCH_MODE_WINNER_TAKES_ALL:
		_fail("winner_takes_all_entry details=%s pressed=%s seat_row=%s mode=%s" % [str(mode_details_button.visible), str(winner_takes_all_mode_button.button_pressed), str(main_seat_compensation_checkbox.visible), str(GameSettings.next_match_mode)])
		return
	await _click_control(mode_details_button)
	await get_tree().process_frame
	if not mode_details_panel.visible or mode_details_title.text != "胜者为王模式详情" or not mode_details_description.text.contains("所有玩家的身份均为内奸") or not mode_details_description.text.contains("击杀其他角色后均摸3张牌") or not mode_details_description.text.contains("初始手牌：1号、2号、3号+0；4号、5号、6号+1；7号、8号、9号+2；10号+3。") or not mode_details_description.text.contains("体力上限：1号至4号+0；5号至8号+1；9号及以后+2。"):
		_fail("winner_takes_all_details_content")
		return
	await _click_control(mode_details_close_button)
	if mode_details_panel.visible:
		_fail("winner_takes_all_details_close")
		return
	# 座次补偿只属于胜者为王；切回其他模式后该设置行必须立即隐藏，避免被误解为通用开关。
	main_menu.call("_select_identity_mode")
	if main_seat_compensation_checkbox.visible:
		_fail("seat_compensation_row_visible_in_identity")
		return
	# 默认客户区矩形；打开联机设置前记录，用于断言资料页与模式预览使用同一客户区，而不是全屏弹层。
	var mode_page_rect: Rect2 = main_frame.get_global_rect()
	await _click_control(online_settings_button)
	await get_tree().process_frame
	# 动态联机形象牌；每个数据库武将都必须对应一张正式 PlayerTargetView 候选。
	var online_avatar_views: Array[Node] = online_avatar_content.find_children("*", "PlayerTargetView", true, false)
	# 联机形象实际武将顺序；从每张只读预览牌的快照提取稳定 ID。
	var online_avatar_character_ids: Array[String] = []
	for online_avatar_view_node: Node in online_avatar_views:
		# 当前联机形象预览牌；只读取配置快照，不修改临时选择状态。
		var online_avatar_view: PlayerTargetView = online_avatar_view_node as PlayerTargetView
		# 当前联机形象预览快照；character_id 必须按共享势力顺序连续排列。
		var online_avatar_snapshot: Dictionary = online_avatar_view.get("_player_snapshot") as Dictionary
		online_avatar_character_ids.append(str(online_avatar_snapshot.get("character_id", "")))
	# 联机形象期望武将顺序；复制数据库 ID 后用图鉴共享排序器生成。
	var expected_online_avatar_character_ids: Array[String] = []
	for online_character_id_variant: Variant in GameDatabase.characters.keys():
		expected_online_avatar_character_ids.append(str(online_character_id_variant))
	expected_online_avatar_character_ids.sort_custom(CardGallerySort.sort_character_ids)
	# 联机设置页矩形；必须贴合原主菜单客户区，顶部导航仍可聚焦并可对等切回模式选择。
	var online_settings_rect: Rect2 = online_settings_panel.get_global_rect()
	if not online_settings_panel.visible or main_frame.visible or online_player_name_input.max_length != GameSettings.MAX_ONLINE_PLAYER_NAME_LENGTH or online_avatar_views.size() != GameDatabase.characters.size() or online_avatar_character_ids != expected_online_avatar_character_ids or start_game_button.focus_mode != Control.FOCUS_NONE or top_identity_mode_button.focus_mode == Control.FOCUS_NONE or online_settings_button.focus_mode == Control.FOCUS_NONE or not online_settings_button.button_pressed or top_identity_mode_button.button_pressed or not (main_instance.get_node("%TopOnlineSettingsIndicator") as ColorRect).visible or (main_instance.get_node("%TopIdentityModeIndicator") as ColorRect).visible or absf(online_settings_rect.position.x - mode_page_rect.position.x) > 0.5 or absf(online_settings_rect.position.y - mode_page_rect.position.y) > 0.5 or absf(online_settings_rect.size.x - mode_page_rect.size.x) > 0.5 or absf(online_settings_rect.size.y - mode_page_rect.size.y) > 0.5 or absf(online_side_list.custom_minimum_size.x - mode_list.custom_minimum_size.x) > 0.5 or not online_profile_section_button.button_pressed or absf(online_action_panel.size.y - 92.0) > 1.0:
		_fail("online_settings_open")
		return
	# 测试选择的武将牌；读取组件内部的只读预览快照，仅用于确认点击保存的是稳定武将 ID。
	# 选择当前可视区首张武将牌；测试目标是验证稳定ID保存，不依赖滚动容器末项是否处于当前视口。
	var selected_avatar_view: PlayerTargetView = online_avatar_views[0] as PlayerTargetView
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
	# 打开所有卡牌对等内容页；默认子分页必须完整读取全部已登记武将且复用正式武将牌场景。
	await _click_control(all_cards_button)
	await get_tree().process_frame
	await get_tree().process_frame
	# 所有卡牌页客户区矩形；必须与模式选择页严格对齐且不覆盖顶部导航。
	var all_cards_page_rect: Rect2 = all_cards_panel.get_global_rect()
	# 所有武将正式牌面节点；数量必须等于当前数据库武将定义总数。
	var all_character_views: Array[Node] = all_cards_grid_content.find_children("*", "PlayerTargetView", true, false)
	# 图鉴武将实际稳定 ID 顺序；条目数组顺序必须与联机形象共用同一势力排序结果。
	var all_character_ids: Array[String] = []
	for all_character_entry_variant: Variant in all_cards_panel.get("_entries") as Array:
		# 当前图鉴武将条目；只读取稳定 ID 验证排列，不修改槽或搜索文本。
		var all_character_entry: Dictionary = all_character_entry_variant as Dictionary
		all_character_ids.append(str(all_character_entry.get("id", "")))
	# 图鉴纵向滚动条；外观、宽度和端点边距必须与模式选择滑条相同。
	var all_cards_scroll_bar: VScrollBar = all_cards_grid_scroll.get_v_scroll_bar()
	# 图鉴滑条轨道样式；共享样式工厂应生成与模式列表相同的颜色和零边距。
	var all_cards_scroll_track_style: StyleBoxFlat = all_cards_scroll_bar.get_theme_stylebox("scroll") as StyleBoxFlat
	# 图鉴滑条常态拖块样式；必须复用模式列表拖块的背景色与描边色。
	var all_cards_scroll_grabber_style: StyleBoxFlat = all_cards_scroll_bar.get_theme_stylebox("grabber") as StyleBoxFlat
	if not all_cards_panel.visible or main_frame.visible or online_settings_panel.visible or not all_cards_button.button_pressed or top_identity_mode_button.button_pressed or online_settings_button.button_pressed or not (main_instance.get_node("%TopAllCardsIndicator") as ColorRect).visible or (main_instance.get_node("%TopIdentityModeIndicator") as ColorRect).visible or (main_instance.get_node("%TopOnlineSettingsIndicator") as ColorRect).visible or not all_characters_tab_button.button_pressed or all_game_cards_tab_button.button_pressed or all_opportunities_tab_button.button_pressed or all_character_views.size() != GameDatabase.characters.size() or all_character_ids != expected_online_avatar_character_ids or CardGallerySort.CHARACTER_FACTION_ORDER != ["xingqionglieche", "yinhexvezhe", "beiluoboge", "xianzhou", "pinuokangni", "wengfaluosi"] or absf(all_cards_page_rect.position.x - mode_page_rect.position.x) > 0.5 or absf(all_cards_page_rect.position.y - mode_page_rect.position.y) > 0.5 or absf(all_cards_page_rect.size.x - mode_page_rect.size.x) > 0.5 or absf(all_cards_page_rect.size.y - mode_page_rect.size.y) > 0.5 or absf(all_cards_side_list.custom_minimum_size.x - mode_list.custom_minimum_size.x) > 0.5 or start_game_button.focus_mode != Control.FOCUS_NONE or all_cards_button.focus_mode == Control.FOCUS_NONE or all_cards_grid_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_ALWAYS or all_cards_scroll_bar == null or absf(all_cards_scroll_bar.custom_minimum_size.x - mode_scroll_bar.custom_minimum_size.x) > 0.5 or all_cards_scroll_track_style == null or all_cards_scroll_grabber_style == null or not all_cards_scroll_track_style.bg_color.is_equal_approx(mode_scroll_track_style.bg_color) or not all_cards_scroll_track_style.border_color.is_equal_approx(mode_scroll_track_style.border_color) or not all_cards_scroll_grabber_style.bg_color.is_equal_approx(mode_scroll_grabber_style.bg_color) or not all_cards_scroll_grabber_style.border_color.is_equal_approx(mode_scroll_grabber_style.border_color) or not is_zero_approx(all_cards_scroll_track_style.content_margin_top) or not is_zero_approx(all_cards_scroll_track_style.content_margin_bottom):
		_fail("all_cards_characters_open")
		return
	# 当前图鉴最右侧牌面边界；所有可见牌均应停在滚动条安全留白左侧。
	var all_cards_rightmost_card_edge: float = 0.0
	for visible_character_entry_variant: Variant in all_cards_panel.get("_entries") as Array:
		# 当前可见武将条目；初次打开没有过滤，因此全部槽都参与右边界计算。
		var visible_character_entry: Dictionary = visible_character_entry_variant as Dictionary
		# 当前武将槽；位置与缩放后尺寸共同确定牌面的最右边界。
		var visible_character_slot: Control = visible_character_entry.get("slot") as Control
		if visible_character_slot != null and visible_character_slot.visible:
			all_cards_rightmost_card_edge = maxf(all_cards_rightmost_card_edge, visible_character_slot.position.x + visible_character_slot.size.x)
	if all_cards_rightmost_card_edge > all_cards_grid_scroll.size.x - all_cards_panel.gallery_scroll_bar_clearance + 1.0:
		_fail("all_cards_scroll_clearance right=%f viewport=%f clearance=%f" % [all_cards_rightmost_card_edge, all_cards_grid_scroll.size.x, all_cards_panel.gallery_scroll_bar_clearance])
		return
	# 首张武将牌输入区；真实点击后详情必须切换为左牌面、右技能的双栏结构。
	var first_character_input: Control = (all_character_views[0] as PlayerTargetView).get_node("InputArea") as Control
	await _click_control(first_character_input)
	await get_tree().process_frame
	# 武将详情左侧正式牌面；动态区域内必须只存在当前武将的一张 PlayerTargetView。
	var character_information_views: Array[Node] = all_cards_character_information_card_area.find_children("*", "PlayerTargetView", true, false)
	# 武将详情黄色技能名标签；数量应与当前静态武将定义中的固有技能一致。
	var character_information_skill_names: Array[Label] = all_cards_panel.get("_information_skill_name_labels") as Array[Label]
	# 当前详情武将稳定 ID；取图鉴排序后的首项用于查询权威技能数量。
	var information_character_id: String = all_character_ids[0]
	# 当前详情武将固有技能数量；详情不得丢失或额外安装运行时技能。
	var information_character_skill_count: int = (GameDatabase.get_character(information_character_id).get("skills", []) as Array).size()
	if not all_cards_information_backdrop.visible or not all_cards_character_information_body.visible or all_cards_information_scroll.visible or character_information_views.size() != 1 or character_information_skill_names.size() != information_character_skill_count:
		_fail("all_cards_character_information_layout")
		return
	for character_skill_name_label: Label in character_information_skill_names:
		if not character_skill_name_label.get_theme_color("font_color").is_equal_approx(all_cards_panel.information_skill_name_color):
			_fail("all_cards_character_skill_name_color")
			return
	await _click_control(all_cards_panel.get_node("%AllCardsInfoCloseButton") as Button)
	await get_tree().process_frame
	# 当前武将条目数组；测试使用组件只读运行时索引计算关键词预期命中数，不修改任何条目。
	var character_entries: Array = all_cards_panel.get("_entries") as Array
	# 当前搜索关键词；使用首项稳定 ID 保证至少命中一个武将。
	var character_search_query: String = str((character_entries[0] as Dictionary).get("id", ""))
	# 当前搜索预期命中数；搜索文本由组件预先标准化，测试只验证筛选与显示数量一致。
	var expected_character_matches: int = 0
	for character_entry_variant: Variant in character_entries:
		# 当前武将测试条目；只读取搜索文本计算命中数量。
		var character_entry: Dictionary = character_entry_variant as Dictionary
		if str(character_entry.get("search_text", "")).contains(character_search_query.to_lower()):
			expected_character_matches += 1
	all_cards_search_input.text = character_search_query
	all_cards_search_input.text_changed.emit(character_search_query)
	await get_tree().process_frame
	await get_tree().process_frame
	# 当前实际可见武将槽数量；隐藏条目不应继续占用网格位置。
	var visible_character_matches: int = 0
	for character_entry_variant: Variant in all_cards_panel.get("_entries") as Array:
		# 当前筛选后武将槽；可见性必须与搜索语料命中结果相同。
		var character_entry: Dictionary = character_entry_variant as Dictionary
		# 当前武将槽控件；组件只隐藏槽，不释放静态牌面。
		var character_slot: Control = character_entry.get("slot") as Control
		if character_slot != null and character_slot.visible:
			visible_character_matches += 1
	if expected_character_matches <= 0 or visible_character_matches != expected_character_matches or not all_cards_result_count_label.text.contains("%d / %d" % [expected_character_matches, GameDatabase.characters.size()]):
		_fail("all_cards_character_search query=%s expected=%d visible=%d label=%s" % [character_search_query, expected_character_matches, visible_character_matches, all_cards_result_count_label.text])
		return
	all_cards_search_input.text = ""
	all_cards_search_input.text_changed.emit("")
	await get_tree().process_frame
	# 切换所有游戏牌；每个稳定卡牌定义只创建一张正式 CardView 代表牌面。
	await _click_control(all_game_cards_tab_button)
	await get_tree().process_frame
	await get_tree().process_frame
	# 所有游戏牌正式牌面节点；数量必须等于数据库唯一游戏牌定义总数。
	var all_game_card_views: Array[Node] = all_cards_grid_content.find_children("*", "CardView", true, false)
	# 所有游戏牌实际稳定 ID 顺序；条目应完整遵循基本、锦囊、装备及内部细分类排序。
	var all_game_card_ids: Array[String] = []
	for game_card_entry_variant: Variant in all_cards_panel.get("_entries") as Array:
		# 当前游戏牌图鉴条目；只读取稳定 ID 验证排列。
		var game_card_entry: Dictionary = game_card_entry_variant as Dictionary
		all_game_card_ids.append(str(game_card_entry.get("id", "")))
	# 所有游戏牌期望稳定 ID 顺序；权威数据库 ID 通过共享排序器生成后与实际条目逐项比较。
	var expected_game_card_ids: Array[String] = []
	for game_card_id_variant: Variant in GameDatabase.cards.keys():
		expected_game_card_ids.append(str(game_card_id_variant))
	expected_game_card_ids.sort_custom(CardGallerySort.sort_game_card_ids)
	if not all_game_cards_tab_button.button_pressed or all_characters_tab_button.button_pressed or all_game_card_views.size() != GameDatabase.cards.size() or (all_cards_panel.get("_entries") as Array).size() != GameDatabase.cards.size() or all_game_card_ids != expected_game_card_ids or int(CardGallerySort.GAME_CARD_TYPE_ORDER.get("basic", -1)) != 0 or int(CardGallerySort.GAME_CARD_TYPE_ORDER.get("trick", -1)) != 1 or int(CardGallerySort.GAME_CARD_TYPE_ORDER.get("equipment", -1)) != 2 or int(CardGallerySort.BASIC_CARD_ORDER.get("杀", -1)) != 0 or int(CardGallerySort.BASIC_CARD_ORDER.get("闪", -1)) != 1 or int(CardGallerySort.BASIC_CARD_ORDER.get("桃", -1)) != 2 or int(CardGallerySort.BASIC_CARD_ORDER.get("酒", -1)) != 3 or int(CardGallerySort.EQUIPMENT_SUBTYPE_ORDER.get("weapon", -1)) != 0 or int(CardGallerySort.EQUIPMENT_SUBTYPE_ORDER.get("armor", -1)) != 1 or int(CardGallerySort.EQUIPMENT_SUBTYPE_ORDER.get("offensive_mount", -1)) != 2 or int(CardGallerySort.EQUIPMENT_SUBTYPE_ORDER.get("defensive_mount", -1)) != 3 or int(CardGallerySort.EQUIPMENT_SUBTYPE_ORDER.get("treasure", -1)) != 4:
		_fail("all_cards_game_cards")
		return
	# 首张游戏牌透明输入区域；真实点击后应打开当前名称模式下的完整规则资料。
	var first_game_card_input: Control = (all_game_card_views[0] as CardView).get_node("InputArea") as Control
	await _click_control(first_game_card_input)
	await get_tree().process_frame
	if not all_cards_information_backdrop.visible or all_cards_information_title.text.is_empty() or all_cards_character_information_body.visible or not all_cards_information_scroll.visible:
		_fail("all_cards_game_card_information visible=%s title=%s input_rect=%s card_interactable=%s grid_pos=%s grid_size=%s scroll_pos=%s scroll_size=%s scroll=%s slot=%s" % [all_cards_information_backdrop.visible, all_cards_information_title.text, _screen_rect(first_game_card_input), (all_game_card_views[0] as CardView).is_interactable, all_cards_grid_content.global_position, all_cards_grid_content.size, (all_cards_panel.get_node("%AllCardsGridScroll") as ScrollContainer).global_position, (all_cards_panel.get_node("%AllCardsGridScroll") as ScrollContainer).size, (all_cards_panel.get_node("%AllCardsGridScroll") as ScrollContainer).scroll_horizontal, first_game_card_input.get_parent().get_parent().get_parent().position])
		return
	await _click_control(all_cards_panel.get_node("%AllCardsInfoCloseButton") as Button)
	await get_tree().process_frame
	# 切换所有机缘；完整目录包含灰色关卡机缘并全部复用正式 OpportunityCardView。
	await _click_control(all_opportunities_tab_button)
	await get_tree().process_frame
	await get_tree().process_frame
	# 所有机缘正式牌面节点；数量必须等于 OpportunityCatalog 完整目录总数。
	var all_opportunity_views: Array[Node] = all_cards_grid_content.find_children("*", "OpportunityCardView", true, false)
	if not all_opportunities_tab_button.button_pressed or all_game_cards_tab_button.button_pressed or all_opportunity_views.size() != OpportunityCatalog.get_all_cards().size() or (all_cards_panel.get("_entries") as Array).size() != OpportunityCatalog.get_all_cards().size():
		_fail("all_cards_opportunities")
		return
	# 灰卡搜索关键词；品质名称应命中所有灰色关卡机缘且不命中普通随机品质。
	var gray_opportunity_count: int = OpportunityCatalog.get_cards_by_quality("gray").size()
	all_cards_search_input.text = "灰卡"
	all_cards_search_input.text_changed.emit("灰卡")
	await get_tree().process_frame
	await get_tree().process_frame
	if gray_opportunity_count <= 0 or not all_cards_result_count_label.text.contains("%d / %d" % [gray_opportunity_count, OpportunityCatalog.get_all_cards().size()]):
		_fail("all_cards_opportunity_search")
		return
	all_cards_search_input.text = ""
	all_cards_search_input.text_changed.emit("")
	await get_tree().process_frame
	# 返回模式选择；图鉴页、资料遮罩与所有卡牌选中态必须同步退出。
	await _click_control(top_identity_mode_button)
	await get_tree().process_frame
	if all_cards_panel.visible or all_cards_information_backdrop.visible or not main_frame.visible or not top_identity_mode_button.button_pressed or all_cards_button.button_pressed:
		_fail("all_cards_switch_to_mode_page")
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
	# 切换主题前的固定主菜单文案；高级黑金只允许改变视觉，不得改写任何现有标题、按钮或模式说明。
	var preserved_main_menu_texts: Dictionary = {
		"title":(main_instance.get_node("%MainMenuTitle") as Label).text,
		"settings":settings_button.text,
		"online":online_settings_button.text,
		"cards":all_cards_button.text,
		"start":start_game_button.text,
		"mode":(main_instance.get_node("%IdentityModeName") as Label).text,
	}
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD)
	await get_tree().process_frame
	# 参考图实测核心配色；锁定蓝黑、石墨灰、暖灰棕、暗铜、橙铜和灰米六个主层级，避免主题再次漂移。
	if not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "outer_background").is_equal_approx(Color("0f1017")) or not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "table_surface").is_equal_approx(Color("181926")) or not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "mode_button").is_equal_approx(Color("252429")) or not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "action_button").is_equal_approx(Color("38302d")) or not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "border").is_equal_approx(Color("806b56")) or not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "accent").is_equal_approx(Color("d59e5a")) or not UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "text_primary").is_equal_approx(Color("d8caba")):
		_fail("premium_reference_palette")
		return
	# 高级黑金主题的模式卡片目标选中底色；石墨灰基底与主题专用加深比例共同复刻参考图层次。
	var expected_premium_selected_mode_background: Color = UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "mode_button").darkened(float(UIStyleRegistry.get_value(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "mode_selected_background_darkening", main_menu.mode_selected_background_darkening)))
	# 高级黑金主题下身份模式卡片的实际持续选中样式。
	var premium_identity_selected_style: StyleBoxFlat = identity_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 高级黑金主题下左侧模式列表样式；必须使用参考图的蓝黑内容面而不是普通按钮灰。
	var premium_mode_list_style: StyleBoxFlat = mode_list.get_theme_stylebox("panel") as StyleBoxFlat
	# 高级黑金主题下顶部选中导航样式；背景必须保持蓝黑，不能复用主操作按钮的暖灰棕。
	var premium_top_selected_style: StyleBoxFlat = top_identity_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	# 高级黑金主题下普通设置按钮样式；对应参考图中性石墨按钮层。
	var premium_settings_style: StyleBoxFlat = settings_button.get_theme_stylebox("normal") as StyleBoxFlat
	# 高级黑金主题下开始游戏按钮样式；对应参考图唯一的大面积暖灰棕主操作层。
	var premium_start_style: StyleBoxFlat = start_game_button.get_theme_stylebox("normal") as StyleBoxFlat
	# 切换后的固定主菜单文案；必须与切换前逐项完全相同。
	var refreshed_main_menu_texts: Dictionary = {
		"title":(main_instance.get_node("%MainMenuTitle") as Label).text,
		"settings":settings_button.text,
		"online":online_settings_button.text,
		"cards":all_cards_button.text,
		"start":start_game_button.text,
		"mode":(main_instance.get_node("%IdentityModeName") as Label).text,
	}
	if not menu_background.color.is_equal_approx(Color("0f1017")) or not (top_navigation.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.is_equal_approx(Color("171824")) or not (top_navigation.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "border")) or premium_mode_list_style == null or not premium_mode_list_style.bg_color.is_equal_approx(Color("1b1b26")) or premium_top_selected_style == null or not premium_top_selected_style.bg_color.is_equal_approx(Color("181924")) or premium_settings_style == null or not premium_settings_style.bg_color.is_equal_approx(Color("1f1f24")) or premium_start_style == null or not premium_start_style.bg_color.is_equal_approx(Color("38302d")) or premium_identity_selected_style == null or not premium_identity_selected_style.bg_color.is_equal_approx(expected_premium_selected_mode_background) or not identity_mode_name.get_theme_color("font_color").is_equal_approx(Color("d8caba")) or not (action_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "accent")) or not (ai_response_slider.get_theme_stylebox("grabber_area") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "accent")) or not (player_count_line_edit.get_theme_stylebox("normal") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "border")) or refreshed_main_menu_texts != preserved_main_menu_texts:
		_fail("premium_theme_refresh")
		return
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_DECADE_WOOD)
	await get_tree().process_frame
	if not (top_navigation.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "border")):
		_fail("theme_refresh")
		return
	# 暖木家园主题的模式卡片目标选中底色；主题切换后应以新的棕色基底重新计算，而非保留旧样式。
	var expected_warm_selected_mode_background: Color = UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "mode_button").darkened(float(UIStyleRegistry.get_value(UIStyleRegistry.STYLE_DECADE_WOOD, "mode_selected_background_darkening", main_menu.mode_selected_background_darkening)))
	# 暖木家园主题下身份模式卡片的实际持续选中样式。
	var warm_identity_selected_style: StyleBoxFlat = identity_mode_button.get_theme_stylebox("pressed") as StyleBoxFlat
	if warm_identity_selected_style == null or not warm_identity_selected_style.bg_color.is_equal_approx(expected_warm_selected_mode_background):
		_fail("mode_selected_background_theme_refresh")
		return
	if not is_equal_approx(ai_response_slider.min_value, 0.10) or not is_equal_approx(ai_response_slider.max_value, 1.00) or not is_equal_approx(ai_response_slider.step, 0.05) or not is_equal_approx(game_speed_slider.min_value, 0.10) or not is_equal_approx(game_speed_slider.max_value, 1.00) or not is_equal_approx(game_speed_slider.step, 0.05):
		_fail("main_menu_speed_slider_range")
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
	if start_game_button.focus_mode != Control.FOCUS_NONE or settings_button.focus_mode != Control.FOCUS_NONE or online_settings_button.focus_mode != Control.FOCUS_NONE or all_cards_button.focus_mode != Control.FOCUS_NONE or top_identity_mode_button.focus_mode != Control.FOCUS_NONE or identity_mode_button.focus_mode != Control.FOCUS_NONE or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
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
	if start_game_button.focus_mode == Control.FOCUS_NONE or settings_button.focus_mode == Control.FOCUS_NONE or online_settings_button.focus_mode == Control.FOCUS_NONE or all_cards_button.focus_mode == Control.FOCUS_NONE or top_identity_mode_button.focus_mode == Control.FOCUS_NONE or identity_mode_button.focus_mode == Control.FOCUS_NONE or match_menu_button.focus_mode != Control.FOCUS_NONE or log_toggle_button.focus_mode != Control.FOCUS_NONE:
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
	if main_menu.visible or settings_panel.visible or match_controller.state == null or match_controller.state.players.size() != 6 or match_controller.default_player_count != 6 or not (main_instance.get_node("MatchMenu") as MatchMenu).visible:
		_fail("start_identity_match")
		return
	if match_menu_button.focus_mode == Control.FOCUS_NONE or log_toggle_button.focus_mode == Control.FOCUS_NONE:
		_fail("match_focus_restore")
		return
	# 主菜单创建局的自动种子；局内重新开局必须取得另一实际种子，不能复用入口创建时的随机序列。
	var initial_automatic_match_seed: int = match_controller.state.random_seed
	# 主菜单创建局的状态实例；成功重开必须替换整个权威状态，而非只刷新旧局表现。
	var initial_automatic_match_state: GameState = match_controller.state
	await _click_control(match_menu_button)
	await _click_control(match_restart_button)
	# 成功重开稳定帧索引；等待新权威状态、选将快照与局内菜单关闭状态完成同步。
	for _successful_restart_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if main_menu.visible or match_controller.state == null or match_controller.state == initial_automatic_match_state or match_controller.state.random_seed == initial_automatic_match_seed or match_controller.state.players.size() != 6:
		_fail("in_match_successful_restart_random_seed")
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
	# 终局角色数组；仅改写显示快照首项，固定覆盖结算角色列的“武将名（玩家名）”排版。
	var terminal_players: Array = terminal_snapshot.get("players", []) as Array
	# 排版专项首名角色；使用已登记丹恒与AI玩家名，避免随机选将或本地名字影响精确文本断言。
	var settlement_title_player: Dictionary = terminal_players[0] as Dictionary if not terminal_players.is_empty() else {}
	if settlement_title_player.is_empty():
		_fail("settlement_title_test_player_missing")
		return
	settlement_title_player["character_id"] = "dan_heng"
	settlement_title_player["display_name"] = "[AI]玩家1"
	terminal_players[0] = settlement_title_player
	terminal_snapshot["players"] = terminal_players
	match_controller.state_changed.emit(terminal_snapshot)
	await get_tree().process_frame
	# 终局交互提示标签；平局快照后必须显示稳定结算文案。
	var interaction_guide_label: Label = main_instance.get_node("%InteractionGuideLabel") as Label
	# 自动弹出的结算面板；终局时必须包含全角色统计列表与右上角唯一关闭按钮。
	var settlement_panel: GameSettlementPanel = main_instance.get_node("GameSettlementPanel") as GameSettlementPanel
	# 结算面板右上角唯一关闭按钮；面板创建失败时保持空值并由后续断言统一报错。
	var settlement_close_button: Button = null
	# 结算面板主框；用于验证关闭按钮确实位于框体右半区而非旧左上角。
	var settlement_frame: PanelContainer = null
	# 结算面板动态统计行容器；行数必须等于终局快照中的全部玩家数量。
	var settlement_rows: VBoxContainer = null
	# 首行角色列标签；用于验证武将名和玩家名没有被拆成两行。
	var settlement_first_role_label: Label = null
	if settlement_panel != null:
		settlement_close_button = settlement_panel.get_node("%SettlementCloseButton") as Button
		settlement_frame = settlement_panel.get_node("%Frame") as PanelContainer
		settlement_rows = settlement_panel.get_node("%RowsContainer") as VBoxContainer
	if settlement_rows != null and settlement_rows.get_child_count() > 0:
		# 首项统计行；角色列固定为动态行的第一个单元格。
		var settlement_first_row: HBoxContainer = settlement_rows.get_child(0) as HBoxContainer
		settlement_first_role_label = settlement_first_row.get_child(0) as Label if settlement_first_row != null and settlement_first_row.get_child_count() > 0 else null
	if interaction_use_button.text != "重新开始" or interaction_settlement_button.text != "结算界面" or not interaction_settlement_button.visible or interaction_cancel_button.text != "返回主菜单" or interaction_guide_label.text != "对局结算，游戏平局" or interaction_use_button.disabled or interaction_settlement_button.disabled or interaction_cancel_button.disabled or settlement_panel == null or not settlement_panel.visible or settlement_close_button == null or settlement_frame == null or settlement_close_button.position.x <= settlement_frame.size.x * 0.5 or settlement_rows == null or settlement_rows.get_child_count() != terminal_snapshot.get("players", []).size() or settlement_first_role_label == null or settlement_first_role_label.text != "丹恒（[AI]玩家1）":
		_fail("post_match_actions close_position=%s frame_size=%s close=%s frame=%s rows=%s/%s role=%s" % [settlement_close_button.position if settlement_close_button != null else Vector2.ZERO, settlement_frame.size if settlement_frame != null else Vector2.ZERO, settlement_close_button != null, settlement_frame != null, settlement_rows.get_child_count() if settlement_rows != null else -1, terminal_snapshot.get("players", []).size(), settlement_first_role_label.text if settlement_first_role_label != null else ""])
		return
	# 右上角关闭后结算面板必须保持关闭，终局操作区的入口可再次打开同一局数据。
	await _click_control(settlement_close_button)
	await get_tree().process_frame
	if settlement_panel.visible:
		_fail("settlement_panel_close")
		return
	await _click_control(interaction_settlement_button)
	await get_tree().process_frame
	if not settlement_panel.visible:
		_fail("settlement_panel_reopen")
		return
	# 结算面板属于模态层；验证再次打开后先正常关闭，随后才能点击底层终局操作按钮。
	await _click_control(settlement_close_button)
	await get_tree().process_frame
	if settlement_panel.visible:
		_fail("settlement_panel_second_close")
		return
	await _click_control(interaction_settlement_button)
	await get_tree().process_frame
	if not settlement_panel.visible:
		_fail("settlement_panel_return_route_reopen")
		return
	# 返回流程补充：结算面板打开时直接走返回主菜单路由；离开对局必须关闭高层遮罩，不能让它覆盖已恢复的主菜单。
	main_instance._on_main_menu_requested()
	for _return_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if not main_menu.visible or match_controller.state != null or settlement_panel.visible:
		_fail("post_match_return_main_menu visible=%s state=%s settlement=%s use=%s cancel=%s" % [main_menu.visible, match_controller.state, settlement_panel.visible, interaction_use_button.text, interaction_cancel_button.text])
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
