extends Node

## 开局自定义专项回归。验证房主设置、全武将座次身份自选、AI武将调整与玩家/AI手气卡流程。

## 专项集成测试使用的固定玩家人数；1名真人与3名AI可覆盖剩余名额分配和AI调整。
const TEST_PLAYER_COUNT: int = 4

## 专项集成测试使用的固定随机种子；保证身份、候选与牌堆顺序可重复复现。
const TEST_RANDOM_SEED: int = 20260720

## 测试使用的权威控制器；按正式场景的事件总线、AI协调器和网络网关结构装配。
var _controller: MatchController

## 最近一次本地观察者快照；用于断言手气卡结束后的首轮技能询问不会携带过期手气卡阶段。
var _latest_state_snapshot: Dictionary = {}

## 最近一次普通选牌请求；用于取得首轮技能选择的稳定请求号并验证实际选择者。
var _latest_card_choice_request: Dictionary = {}

## 测试开始前的全武将座次身份设置；结束时原样恢复，避免影响同进程后续测试。
var _original_custom_assignment_enabled: bool = false

## 测试开始前的AI武将调整设置；结束时原样恢复。
var _original_customize_ai_enabled: bool = false

## 测试开始前的手气卡数量；结束时原样恢复。
var _original_mulligan_limit: int = 0

## 测试开始前的AI手气卡设置；结束时原样恢复。
var _original_ai_mulligan_enabled: bool = false

## 测试开始前的换将卡数量；结束时原样恢复，避免影响同进程后续开局。
var _original_character_replacement_count: int = 0

## 测试开始前的随机选将牌数；结束时原样恢复。
var _original_character_candidate_count: int = GameSettings.DEFAULT_CHARACTER_CANDIDATE_COUNT


## 延迟执行全部断言，确保自动加载数据库已经完成内容扫描。
func _ready() -> void:
	call_deferred("_run")


## 依次验证界面设置、独立规则服务和完整开局流程；任一失败立即退出。
func _run() -> void:
	_store_original_settings()
	if not await _test_settings_controls():
		return
	if not await _test_character_selection_panel_layout():
		return
	if not _test_character_selection_service():
		return
	if not _test_mulligan_ai_evaluation():
		return
	if not _test_authoritative_pre_game_flow():
		return
	_restore_original_settings()
	# 专项控制器清理；成功出口显式释放权威对局与节点，避免测试进程退出时残留ObjectDB实例诊断。
	if _controller != null and is_instance_valid(_controller):
		_controller.abandon_match()
		_controller.queue_free()
		await get_tree().process_frame
	print("PRE_GAME_CUSTOMIZATION_PASS")
	get_tree().quit(0)


## 保存当前全局开局设置；测试所有成功与失败出口都通过统一恢复入口还原。
func _store_original_settings() -> void:
	_original_custom_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_original_customize_ai_enabled = GameSettings.customize_ai_characters_enabled
	_original_mulligan_limit = GameSettings.mulligan_limit
	_original_ai_mulligan_enabled = GameSettings.ai_uses_mulligan_enabled
	_original_character_replacement_count = GameSettings.character_replacement_count
	_original_character_candidate_count = GameSettings.character_candidate_count


## 验证主菜单与局内菜单使用同一设置源，并且局域网客户端会隐藏全部房主权威控件。
func _test_settings_controls() -> bool:
	# 正式主场景资源；设置测试必须读取玩家实际使用的两个菜单，而不是构造替代控件。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("main_scene_load")
	# 正式主场景实例；进入场景树后两个菜单会订阅同一GameSettings信号。
	var main_instance: Control = main_scene.instantiate() as Control
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.size = Vector2(1152.0, 648.0)
	add_child(main_instance)
	for _frame_index: int in range(4):
		await get_tree().process_frame
	# 主菜单自选开关；切换后局内同名开关必须同步。
	var main_custom_checkbox: CheckBox = main_instance.get_node("%MainMenuCustomCharacterAssignmentCheckBox") as CheckBox
	# 局内菜单自选开关；非房主模式下应整项隐藏。
	var match_custom_checkbox: CheckBox = main_instance.get_node("%CustomCharacterAssignmentCheckBox") as CheckBox
	# 主菜单自动身份标记开关；它与全部设置开关共用独立主题指示器。
	var main_auto_identity_checkbox: CheckBox = main_instance.get_node("%MainMenuAutoIdentityMarkingCheckBox") as CheckBox
	# 局内自动身份标记开关；作为统一复选框视觉规格的基准项。
	var match_auto_identity_checkbox: CheckBox = main_instance.get_node("%AutoIdentityMarkingCheckBox") as CheckBox
	# 主菜单AI改将开关；与局内控件共享持久设置。
	var main_ai_checkbox: CheckBox = main_instance.get_node("%MainMenuCustomizeAiCharactersCheckBox") as CheckBox
	# 局内菜单AI改将开关；只允许离线玩家或房主查看。
	var match_ai_checkbox: CheckBox = main_instance.get_node("%CustomizeAiCharactersCheckBox") as CheckBox
	# 主菜单手气卡下拉框；必须完整展示关闭、1至5次和无限次共7项。
	var main_mulligan_option: OptionButton = main_instance.get_node("%MainMenuMulliganLimitOption") as OptionButton
	# 局内菜单手气卡下拉框；选择结果必须即时同步回主菜单。
	var match_mulligan_option: OptionButton = main_instance.get_node("%MulliganLimitOption") as OptionButton
	# 主菜单AI手气卡开关；只决定下一局AI是否评估。
	var main_ai_mulligan_checkbox: CheckBox = main_instance.get_node("%MainMenuAiUsesMulliganCheckBox") as CheckBox
	# 局内菜单AI手气卡开关；局域网客户端不可见。
	var match_ai_mulligan_checkbox: CheckBox = main_instance.get_node("%AiUsesMulliganCheckBox") as CheckBox
	# 主菜单换将卡数量；必须完整展示关闭、3、5、8、10、20张六档。
	var main_replacement_option: OptionButton = main_instance.get_node("%MainMenuCharacterReplacementCountOption") as OptionButton
	# 局内菜单换将卡数量；选择结果必须同步到主菜单与全局设置。
	var match_replacement_option: OptionButton = main_instance.get_node("%CharacterReplacementCountOption") as OptionButton
	# 主菜单随机选将牌数；必须完整展示一至二十张。
	var main_candidate_count_option: OptionButton = main_instance.get_node("%MainMenuCharacterCandidateCountOption") as OptionButton
	# 局内菜单随机选将牌数；局域网客户端不可见。
	var match_candidate_count_option: OptionButton = main_instance.get_node("%CharacterCandidateCountOption") as OptionButton
	# 正式局内菜单组件；公开权限入口必须统一隐藏四项新设置。
	var match_menu: MatchMenu = main_instance.get_node("%MatchMenu") as MatchMenu
	# 右上菜单常驻按钮；展开面板必须从其下缘开始，不能重叠遮挡入口。
	var menu_button: Button = main_instance.get_node("%MenuButton") as Button
	# 主菜单设置面板与内容列；新增两行后全部控件仍必须位于面板高度内。
	var main_settings_panel: PanelContainer = main_instance.get_node("%MainMenuSettingsPanel") as PanelContainer
	# 主菜单设置内容列；实际高度用于检查新增选项没有溢出面板。
	var main_settings_content: VBoxContainer = main_settings_panel.get_node("SettingsVBox") as VBoxContainer
	# 局内设置面板与内容列；房主权威选项不得溢出屏幕或覆盖返回按钮。
	var match_settings_panel: PanelContainer = main_instance.get_node("%MenuPanel") as PanelContainer
	# 局内菜单内容列；实际高度必须小于等于房主菜单面板高度。
	var match_settings_content: VBoxContainer = match_settings_panel.get_node("MenuVBox") as VBoxContainer
	if main_custom_checkbox == null or match_custom_checkbox == null or main_auto_identity_checkbox == null or match_auto_identity_checkbox == null or main_ai_checkbox == null or match_ai_checkbox == null or main_mulligan_option == null or match_mulligan_option == null or main_ai_mulligan_checkbox == null or match_ai_mulligan_checkbox == null or main_replacement_option == null or match_replacement_option == null or main_candidate_count_option == null or match_candidate_count_option == null or match_menu == null or menu_button == null:
		main_instance.queue_free()
		return _fail("settings_controls_missing")
	# 紧凑客户区矩形；两套设置面板都必须完整位于1152×648范围内。
	var compact_viewport_rect: Rect2 = Rect2(Vector2.ZERO, main_instance.size)
	if main_settings_content.size.y > main_settings_panel.size.y or match_settings_content.size.y > match_settings_panel.size.y or not compact_viewport_rect.encloses(Rect2(main_settings_panel.position, main_settings_panel.size)) or not compact_viewport_rect.encloses(Rect2(match_settings_panel.position, match_settings_panel.size)):
		main_instance.queue_free()
		return _fail("settings_content_overflow main=%s/%s rect=%s match=%s/%s rect=%s viewport=%s" % [main_settings_content.size.y, main_settings_panel.size.y, Rect2(main_settings_panel.position, main_settings_panel.size), match_settings_content.size.y, match_settings_panel.size.y, Rect2(match_settings_panel.position, match_settings_panel.size), compact_viewport_rect])
	# 两个设置入口的全部二元选项；每项都必须覆盖默认勾选图标并使用同一主题化指示器。
	var settings_checkboxes: Array[CheckBox] = [main_auto_identity_checkbox, match_auto_identity_checkbox, main_custom_checkbox, match_custom_checkbox, main_ai_checkbox, match_ai_checkbox, main_ai_mulligan_checkbox, match_ai_mulligan_checkbox]
	for settings_checkbox: CheckBox in settings_checkboxes:
		# 当前开关的独立指示器；子节点只负责重绘，不接收鼠标输入或改写设置状态。
		var indicator: IdentityMarkingIndicator = settings_checkbox.get_node_or_null("SettingsCheckBoxIndicator") as IdentityMarkingIndicator
		# 自动身份标记是原有基准项，保留其历史节点名；其余开关统一使用通用节点名。
		if indicator == null:
			indicator = settings_checkbox.get_node_or_null("IdentityMarkingIndicator") as IdentityMarkingIndicator
		if indicator == null or not indicator.position.is_equal_approx(Vector2(2.0, 5.0)) or not indicator.size.is_equal_approx(Vector2(20.0, 20.0)) or indicator.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			main_instance.queue_free()
			return _fail("settings_checkbox_indicator:%s" % settings_checkbox.name)
	if main_mulligan_option.item_count != 7 or match_mulligan_option.item_count != 7 or main_mulligan_option.get_item_text(0) != "关闭" or main_mulligan_option.get_item_text(6) != "无限次":
		main_instance.queue_free()
		return _fail("mulligan_options")
	if main_replacement_option.item_count != 6 or match_replacement_option.item_count != 6 or main_replacement_option.get_item_text(0) != "关闭" or main_replacement_option.get_item_text(5) != "二十张":
		main_instance.queue_free()
		return _fail("replacement_options")
	if main_candidate_count_option.item_count != 20 or match_candidate_count_option.item_count != 20 or main_candidate_count_option.get_item_text(0) != "一张" or main_candidate_count_option.get_item_text(19) != "二十张":
		main_instance.queue_free()
		return _fail("candidate_count_options")
	main_custom_checkbox.toggled.emit(true)
	main_ai_checkbox.toggled.emit(true)
	main_ai_mulligan_checkbox.toggled.emit(true)
	match_mulligan_option.item_selected.emit(2)
	match_replacement_option.item_selected.emit(3)
	match_candidate_count_option.item_selected.emit(19)
	await get_tree().process_frame
	if not match_custom_checkbox.button_pressed or not match_ai_checkbox.button_pressed or not match_ai_mulligan_checkbox.button_pressed or GameSettings.mulligan_limit != 2 or main_mulligan_option.selected != 2 or GameSettings.character_replacement_count != 8 or main_replacement_option.selected != 3 or GameSettings.character_candidate_count != 20 or main_candidate_count_option.selected != 19:
		main_instance.queue_free()
		return _fail("settings_cross_menu_sync")
	# 展开局内菜单；面板顶部必须紧贴常驻菜单按钮的下缘，避免覆盖并阻断收起入口。
	match_menu.set_menu_open(true)
	await get_tree().process_frame
	if match_settings_panel.position.y < menu_button.position.y + menu_button.size.y:
		main_instance.queue_free()
		return _fail("menu_panel_overlaps_menu_button panel=%s button=%s" % [match_settings_panel.get_rect(), menu_button.get_rect()])
	match_menu.set_menu_open(false)
	match_menu.set_authority_controls_visible(false)
	if match_custom_checkbox.visible or match_ai_checkbox.visible or match_mulligan_option.get_parent().visible or match_ai_mulligan_checkbox.visible or match_replacement_option.get_parent().visible or match_candidate_count_option.get_parent().visible:
		main_instance.queue_free()
		return _fail("client_authority_visibility")
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 验证多张随机候选使用原尺寸垂直滚动、换将按钮悬停出现、全武将铺屏和座次身份选中配色。
func _test_character_selection_panel_layout() -> bool:
	# 正式主场景实例；布局验证直接使用玩家实际看到的选将组件与场景几何。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 正式主场景运行实例；加入场景树后等待布局完成再读取尺寸。
	var main_instance: Control = main_scene.instantiate() as Control
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.size = Vector2(1152.0, 648.0)
	add_child(main_instance)
	for _frame_index: int in range(3):
		await get_tree().process_frame
	# 当前全部武将ID；普通候选数量超过单行容量，用于验证垂直滚动内容高度。
	var character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		character_ids.append(str(character_id_variant))
	# 非领袖身份的自选快照；领袖技武将不应被额外锁定，是否属于领袖由服务专项覆盖。
	var locked_candidate_ids: Array[String] = []
	# 自选私有快照；保留首次反贼身份与公开领袖武将，并开放全部座次身份及换将入口。
	var snapshot: Dictionary = {
		"phase":CharacterSelectionService.PHASE_CUSTOM,
		"selection_kind":"initial",
		"can_select":true,
		"local_identity":"rebel",
		"local_candidates":character_ids.duplicate(),
		"all_character_ids":character_ids.duplicate(),
		"locked_candidate_ids":locked_candidate_ids,
		"replaceable_candidate_ids":[],
		"replacement_cards_remaining":3,
		"leader_character_id":character_ids[1],
		"leader_player_id":1,
		"allow_all_characters":true,
		"allow_custom_assignment":true,
		"player_count":4,
		"seat_options":[1, 2, 3, 4],
		"identity_options":["leader", "loyalist", "rebel", "renegade"],
		"initial_seat_number":2,
		"initial_identity":"rebel",
		"preview_seat_number":2,
		"preview_identity":"rebel",
	}
	# 正式选将组件与关键稳定节点；确认按钮必须是滚动区的兄弟而不是后代。
	var selection_panel: CharacterSelectionPanel = main_instance.get_node("%CharacterSelectionPanel") as CharacterSelectionPanel
	selection_panel.bind_snapshot(snapshot)
	await get_tree().process_frame
	# 初始随机分配的座次与身份；进入自选阶段时必须立即高亮，而不是要求玩家重新点击相同选项。
	if int(selection_panel.get("_selected_seat_number")) != 2 or str(selection_panel.get("_selected_identity")) != "rebel":
		main_instance.queue_free()
		return _fail("initial_assignment_button_selection")
	# 候选滚动容器；多行内容高度超过其视口时提供垂直滚动。
	var candidate_scroll: ScrollContainer = selection_panel.get_node("SelectionFrame/CharacterCandidateArea") as ScrollContainer
	# 候选滚动内容；最小高度由原尺寸牌面行数计算。
	var candidate_content: Control = selection_panel.get_node("SelectionFrame/CharacterCandidateArea/CandidateScrollContent") as Control
	# 固定确认按钮；必须始终属于SelectionFrame而不是滚动内容。
	var confirm_button: Button = selection_panel.get_node("SelectionFrame/ConfirmCharacterButton") as Button
	if candidate_content.custom_minimum_size.y <= candidate_scroll.size.y or candidate_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_ALWAYS or candidate_scroll.is_ancestor_of(confirm_button) or not confirm_button.visible:
		main_instance.queue_free()
		return _fail("candidate_scroll_or_sticky_confirm")
	# 候选滚动位置；直接调用统一滚动入口后必须能进入第二行，滚轮与拖动手势都复用该入口。
	candidate_scroll.scroll_vertical = 0
	selection_panel.call("_scroll_candidate_area_by", 120.0)
	await get_tree().process_frame
	if candidate_scroll.scroll_vertical <= 0:
		main_instance.queue_free()
		return _fail("candidate_scroll_input")
	# 可换普通候选；悬停后牌面底部按钮必须可见，非领袖身份中的领袖技武将也不额外锁定。
	var replacement_buttons: Dictionary = selection_panel.get("_replacement_buttons") as Dictionary
	# 当前候选牌视图映射；用于触发真实牌面悬停入口。
	var candidate_views: Dictionary = selection_panel.get("_candidate_views") as Dictionary
	# 本次悬停的普通候选ID；快照没有锁定项，因此首张也必须获得换将入口。
	var replaceable_character_id: String = character_ids[0]
	(candidate_views[replaceable_character_id] as PlayerTargetView).call("_on_input_mouse_entered")
	await get_tree().process_frame
	# 本次换将按钮与对应牌面；按钮必须覆盖在牌面底部，不增加当前候选行高度。
	var replacement_button: Button = replacement_buttons.get(replaceable_character_id) as Button
	var replaceable_character_view: PlayerTargetView = candidate_views.get(replaceable_character_id) as PlayerTargetView
	if not replacement_buttons.has(replaceable_character_id) or replacement_button == null or replaceable_character_view == null or not replacement_button.visible or replacement_button.text != "换将（3）" or not replacement_button.tooltip_text.is_empty() or replacement_button.position.y < replaceable_character_view.position.y + replaceable_character_view.card_size.y - replacement_button.size.y - CharacterSelectionPanel.REPLACEMENT_BUTTON_BOTTOM_INSET:
		main_instance.queue_free()
		return _fail("replacement_hover_button")
	# 从非领袖切换到领袖；座次必须自动联动为一号位，标题也要立即同步为领袖。
	selection_panel.call("_select_identity", "leader")
	if int(selection_panel.get("_selected_seat_number")) != 1 or not selection_panel.get_title_plain_text().contains("领袖"):
		main_instance.queue_free()
		return _fail("identity_to_leader_assignment_completion")
	# 从领袖切换到反贼；座次必须自动随机补全为非一号位，不能留下半成品选择。
	selection_panel.call("_select_identity", "rebel")
	if int(selection_panel.get("_selected_seat_number")) == 1 or str(selection_panel.get("_selected_identity")) == "leader" or not selection_panel.get_title_plain_text().contains("反贼"):
		main_instance.queue_free()
		return _fail("identity_from_leader_assignment_completion")
	# 从二号位切换到一号位再离开；身份必须分别自动成为领袖和随机非领袖，不能要求玩家二次点击。
	selection_panel.call("_select_seat", 1)
	if str(selection_panel.get("_selected_identity")) != "leader":
		main_instance.queue_free()
		return _fail("seat_to_leader_assignment_completion")
	selection_panel.call("_select_seat", 2)
	if str(selection_panel.get("_selected_identity")) == "leader" or str(selection_panel.get("_selected_identity")).is_empty():
		main_instance.queue_free()
		return _fail("seat_from_leader_assignment_completion")
	# 自选模式候选可视高度；关闭座次身份自选后，候选区应释放原控件占位并扩展到确认按钮上方。
	var custom_candidate_height: float = candidate_scroll.size.y
	# 二号位与反贼按钮；选中后字体必须切换为各自边框语义色，形成明确反馈。
	selection_panel.call("_select_seat", 2)
	selection_panel.call("_select_identity", "rebel")
	# 动态座次按钮映射；二号位按钮应使用主题强调色。
	var seat_buttons: Dictionary = selection_panel.get("_seat_button_views") as Dictionary
	# 动态身份按钮映射；反贼按钮应使用绿色身份语义色。
	var identity_buttons: Dictionary = selection_panel.get("_identity_button_views") as Dictionary
	if (seat_buttons[2] as Button).get_theme_color("font_color") != BattleUIStyle.get_color("accent") or (identity_buttons["rebel"] as Button).get_theme_color("font_color") != BattleUIStyle.get_color("identity_rebel"):
		main_instance.queue_free()
		return _fail("assignment_selected_feedback")
	# 全武将模式；主框扩展到视口安全边距，座次身份控件隐藏，全部牌面仍保持1倍原尺寸。
	selection_panel.call("_toggle_all_characters")
	await get_tree().process_frame
	# 全武将主框；宽度应扩展到当前视口安全边距内。
	var selection_frame: Panel = selection_panel.get_node("SelectionFrame") as Panel
	# 座次行标题；全武将模式必须隐藏且不占候选列表操作入口。
	var seat_label: Label = selection_panel.get_node("SelectionFrame/SeatSelectionLabel") as Label
	# 身份行标题；与座次标题同步隐藏。
	var identity_label: Label = selection_panel.get_node("SelectionFrame/IdentitySelectionLabel") as Label
	# 公开领袖区域；全武将模式必须完全隐藏，不能在全屏候选列表下残留背景牌面。
	var leader_character_area: Control = selection_panel.get_node("SelectionFrame/LeaderCharacterArea") as Control
	for candidate_view_variant: Variant in (selection_panel.get("_candidate_views") as Dictionary).values():
		if not (candidate_view_variant as PlayerTargetView).scale.is_equal_approx(Vector2.ONE):
			main_instance.queue_free()
			return _fail("all_characters_card_scaled")
	if selection_frame.size.x < main_instance.size.x - 40.0 or seat_label.visible or identity_label.visible or leader_character_area.visible or candidate_scroll.is_ancestor_of(confirm_button) or confirm_button.position.y < candidate_scroll.position.y + candidate_scroll.size.y:
		main_instance.queue_free()
		return _fail("all_characters_fullscreen_controls_or_confirm")
	# 退出全武将模式后关闭座次身份自选；隐藏控件不得继续占据候选滚动区的下方高度。
	selection_panel.call("_toggle_all_characters")
	var no_custom_snapshot: Dictionary = snapshot.duplicate(true)
	no_custom_snapshot["allow_custom_assignment"] = false
	no_custom_snapshot["allow_all_characters"] = false
	selection_panel.bind_snapshot(no_custom_snapshot)
	await get_tree().process_frame
	if seat_label.visible or identity_label.visible or candidate_scroll.size.y <= custom_candidate_height or candidate_scroll.position.y + candidate_scroll.size.y > confirm_button.position.y:
		main_instance.queue_free()
		return _fail("non_custom_candidate_area_not_released")
	selection_panel.close()
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 验证自选服务的全武将提交、座次唯一、身份名额和一号位/领袖双向联动。
func _test_character_selection_service() -> bool:
	# 四名测试玩家；身份分布与标准四人局一致，用于生成身份可选名额。
	var players: Array[PlayerState] = []
	# 标准身份顺序；服务只统计数量，不依赖输入顺序决定最终座次。
	var identities: Array[String] = ["leader", "loyalist", "rebel", "rebel"]
	for player_id: int in range(TEST_PLAYER_COUNT):
		# 当前测试玩家；稳定ID与初始数组位置分离，后续提交自行选择座次。
		var player: PlayerState = PlayerState.new(player_id, "自选测试玩家%d" % (player_id + 1))
		player.identity = identities[player_id]
		players.append(player)
	# 全部武将ID；数量远大于随机候选数，可验证“所有武将”提交不受本次候选限制。
	var character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		character_ids.append(str(character_id_variant))
	# 固定随机源；候选生成可重复，但服务规则不依赖具体候选顺序。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = TEST_RANDOM_SEED
	# 自选规则服务；候选数固定2，便于找到候选外武将验证全量入口。
	var service: CharacterSelectionService = CharacterSelectionService.new()
	# 领袖技武将ID；专项测试按正式元数据扫描，确保固定候选规则不依赖硬编码角色名。
	var leader_skill_character_ids: Array[String] = []
	for character_id: String in character_ids:
		# 当前测试武将定义；任一技能声明leader_skill即可进入固定候选。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		for skill_id_variant: Variant in character_definition.get("skills", []) as Array:
			if bool(GameDatabase.get_skill(str(skill_id_variant)).get("leader_skill", false)):
				leader_skill_character_ids.append(character_id)
				break
	if leader_skill_character_ids.is_empty() or not service.begin(players, character_ids, 2, rng, true, 3, leader_skill_character_ids).is_empty():
		return _fail("custom_service_begin")
	# 首任领袖初始候选；全部领袖技武将必须位于前缀、不占两张普通随机候选并全部锁定。
	var initial_leader_candidates: Array[String] = service.get_candidates(0)
	if service.phase != CharacterSelectionService.PHASE_LEADER or initial_leader_candidates.slice(0, leader_skill_character_ids.size()) != leader_skill_character_ids or service.get_locked_candidate_ids(0) != leader_skill_character_ids or initial_leader_candidates.size() != mini(character_ids.size(), 2 + leader_skill_character_ids.size()):
		return _fail("leader_skill_candidates")
	# 锁定领袖技候选；换将请求必须拒绝且不能消耗次数。
	if service.replace_candidate(0, leader_skill_character_ids[0]).is_empty() or service.get_replacement_cards_remaining(0) != 3:
		return _fail("locked_leader_candidate_replaced")
	# 首张普通随机候选；成功换将后只替换该位置并消耗一张换将卡。
	var replaceable_character_id: String = initial_leader_candidates[leader_skill_character_ids.size()]
	if not service.replace_candidate(0, replaceable_character_id).is_empty() or service.get_replacement_cards_remaining(0) != 2 or service.get_candidates(0).has(replaceable_character_id):
		return _fail("candidate_replacement")
	# 首任领袖选择；自选模式仍须先完成该公开步骤，之后才进入全员重新分配阶段。
	var initial_leader_character_id: String = leader_skill_character_ids[0]
	if not service.select_character(0, initial_leader_character_id).is_empty() or service.phase != CharacterSelectionService.PHASE_CUSTOM:
		return _fail("initial_leader_selection")
	# 二号玩家自选快照；必须继续显示首次忠臣身份与首任领袖武将，同时提供最终座次身份按钮。
	var custom_snapshot: Dictionary = service.to_dict(1)
	if str(custom_snapshot.get("local_identity", "")) != "loyalist" or str(custom_snapshot.get("leader_character_id", "")) != initial_leader_character_id or not bool(custom_snapshot.get("allow_custom_assignment", false)):
		return _fail("custom_snapshot_initial_identity_or_leader")
	# 最终自选候选；每名玩家严格只收到设置的两张随机武将，不再附加领袖技固定前缀或错误锁定。
	if service.get_candidates(1).size() != 2 or not service.get_locked_candidate_ids(1).is_empty():
		return _fail("custom_candidate_count_or_leader_lock")
	# 非领袖身份候选中的领袖技武将；该身份必须允许换将，避免把首任领袖阶段的固定限制错误扩散给其他角色。
	var non_leader_companion_character_id: String = ""
	for character_id: String in character_ids:
		if character_id != leader_skill_character_ids[0]:
			non_leader_companion_character_id = character_id
			break
	if non_leader_companion_character_id.is_empty():
		return _fail("non_leader_replacement_candidate_missing")
	service._candidates_by_player[1] = [leader_skill_character_ids[0], non_leader_companion_character_id]
	service._locked_candidates_by_player[1] = []
	if service.get_locked_candidate_ids(1).has(leader_skill_character_ids[0]) or not service.replace_candidate(1, leader_skill_character_ids[0]).is_empty():
		return _fail("non_leader_leader_skill_replacement")
	# 一号玩家候选外武将；开启自选后仍必须允许提交。
	var outside_candidate_id: String = ""
	for character_id: String in character_ids:
		if not service.get_candidates(0).has(character_id):
			outside_candidate_id = character_id
			break
	if outside_candidate_id.is_empty() or not service.select_character(0, outside_candidate_id, 1, "rebel").is_empty():
		return _fail("all_character_or_seat_leader_link")
	if service.get_selected_seat_number(0) != 1 or service.get_selected_identity(0) != "leader":
		return _fail("seat_one_forces_leader")
	# 二号玩家的合法未占用武将；后续座次与身份断言必须排除“重复武将”这一更早的拒绝原因。
	var second_character_id: String = ""
	for character_id: String in character_ids:
		if character_id != outside_candidate_id:
			second_character_id = character_id
			break
	if second_character_id.is_empty() or service.select_character(1, outside_candidate_id, 2, "loyalist").is_empty():
		return _fail("duplicate_character_allowed")
	# 二号玩家尝试重复一号位；即使请求普通身份也会先联动领袖并因座次占用被拒绝。
	var duplicate_seat_error: String = service.select_character(1, second_character_id, 1, "loyalist")
	if duplicate_seat_error.is_empty():
		return _fail("duplicate_seat_allowed")
	# 二号玩家选择领袖但请求三号位；服务应自动切换为一号位并继续因名额占用拒绝。
	var duplicate_leader_error: String = service.select_character(1, second_character_id, 3, "leader")
	if duplicate_leader_error.is_empty():
		return _fail("leader_forces_seat_one")
	if not service.select_character(1, second_character_id, 2, "loyalist").is_empty():
		return _fail("valid_second_assignment")
	# 三号玩家的合法未占用武将；用于确认拒绝原因来自忠臣名额而不是武将重复。
	var third_character_id: String = ""
	for character_id: String in character_ids:
		if character_id != outside_candidate_id and character_id != second_character_id:
			third_character_id = character_id
			break
	# 三号玩家重复忠臣名额；四人局只有1名忠臣，必须被服务拒绝。
	var duplicate_identity_error: String = service.select_character(2, third_character_id, 3, "loyalist")
	if duplicate_identity_error.is_empty():
		return _fail("identity_limit_allowed")
	return true


## 验证AI后置位防御阈值、关闭开关和无限次数语义。
func _test_mulligan_ai_evaluation() -> bool:
	# AI测试玩家；手牌仅有1分防御但总牌值充足，使前置位保留、末位刷新。
	var player: PlayerState = PlayerState.new(7, "手气卡AI")
	# 测试手牌定义；【闪】提供1分防御，其余高价值牌保证不会因平均价值不足触发刷新。
	var definition_ids: Array[String] = ["shan", "wuzhong", "shunshou", "guohe"]
	for definition_index: int in range(definition_ids.size()):
		# 当前评估实体牌；只需要定义ID，花色和点数不参与起手估值。
		var card: CardInstance = CardInstance.new(definition_ids[definition_index], "spade", definition_index + 1)
		card.zone = "hand"
		card.owner_id = player.player_id
		player.hand.append(card)
	# 单人参与数组；服务次数与完成状态按稳定玩家ID保存。
	var player_ids: Array[int] = [player.player_id]
	# 开启AI评估的有限次数服务；同一手牌在一号位应保留，在四号位应刷新。
	var enabled_service: StartingHandMulliganService = StartingHandMulliganService.new()
	enabled_service.begin(player_ids, 2, true)
	if enabled_service.should_ai_refresh(player, 1, 4) or not enabled_service.should_ai_refresh(player, 4, 4):
		return _fail("late_position_defense_requirement")
	# 关闭AI评估的服务；即使后置位防御不足也必须直接保留。
	var disabled_service: StartingHandMulliganService = StartingHandMulliganService.new()
	disabled_service.begin(player_ids, 2, false)
	if disabled_service.should_ai_refresh(player, 4, 4):
		return _fail("disabled_ai_mulligan")
	# 无限次数服务；连续消费不会递减私有快照中的-1。
	var unlimited_service: StartingHandMulliganService = StartingHandMulliganService.new()
	unlimited_service.begin(player_ids, -1, false)
	for _attempt_index: int in range(7):
		if not unlimited_service.consume_refresh(player.player_id):
			return _fail("unlimited_consume")
	if int(unlimited_service.to_dict(player.player_id).get("remaining", 0)) != -1:
		return _fail("unlimited_remaining")
	return true


## 验证权威控制器从真人自选、AI剩余分配、房主改将到手气卡确认的完整阶段顺序。
func _test_authoritative_pre_game_flow() -> bool:
	GameSettings.set_custom_character_assignment_enabled(true)
	GameSettings.set_customize_ai_characters_enabled(true)
	GameSettings.set_mulligan_limit(2)
	GameSettings.set_ai_uses_mulligan_enabled(true)
	GameSettings.set_character_replacement_count(3)
	GameSettings.set_character_candidate_count(7)
	_create_controller()
	if not _controller.start_match(TEST_PLAYER_COUNT, TEST_RANDOM_SEED):
		return _fail("authoritative_start")
	if _controller.state.current_phase != "character_selection" or not bool(_controller.state.match_options.get("custom_character_assignment_enabled", false)) or int(_controller.state.match_options.get("mulligan_limit", 0)) != 2 or int(_controller.state.match_options.get("character_replacement_count", 0)) != 3 or int(_controller.state.match_options.get("character_candidate_count", 0)) != 7:
		return _fail("locked_match_options")
	# 首次身份分配中的领袖ID；自选阶段开始后仍用于验证公开亮将没有提前被最终座次覆盖。
	var initial_leader_player_id: int = _controller.character_selection.leader_player_id
	# 本地玩家首次身份；自选私有快照必须继续展示该值。
	var initial_local_identity: String = _controller.state.get_player(0).identity
	if _controller.character_selection.phase == CharacterSelectionService.PHASE_LEADER:
		# 本地玩家恰好是首任领袖；先从权威候选中确认亮将，不能直接携带最终座次身份跳过该阶段。
		var initial_candidates: Array[String] = _controller.character_selection.get_candidates(0)
		if initial_leader_player_id != 0 or initial_candidates.is_empty() or not _controller.select_character(0, initial_candidates[0]):
			return _fail("local_initial_leader_selection")
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_CUSTOM:
		return _fail("custom_phase_after_initial_leader")
	# 首任领袖公开武将；AI领袖由开局驱动自动确认，本地领袖则由上方标准动作确认。
	var initial_leader_character_id: String = _controller.state.get_player(initial_leader_player_id).character_id
	# 首任领袖武将是否拥有领袖技；控制器自动扫描成功时，候选首项必定来自固定前缀。
	var initial_leader_has_leader_skill: bool = false
	for skill_id_variant: Variant in GameDatabase.get_character(initial_leader_character_id).get("skills", []) as Array:
		if bool(GameDatabase.get_skill(str(skill_id_variant)).get("leader_skill", false)):
			initial_leader_has_leader_skill = true
			break
	if not initial_leader_has_leader_skill:
		return _fail("controller_leader_skill_candidate_prefix")
	# 本地自选快照；必须同时保留第一次分配的身份和首任领袖选将。
	var local_custom_snapshot: Dictionary = _controller.character_selection.to_dict(0)
	if str(local_custom_snapshot.get("local_identity", "")) != initial_local_identity or str(local_custom_snapshot.get("leader_character_id", "")) != initial_leader_character_id:
		return _fail("authoritative_initial_identity_or_leader_snapshot")
	# 真人将自身预览为一号位领袖；不确认武将也必须立刻重排牌桌、更新身份，并为全部AI展示不同的候选武将。
	if not _controller.preview_custom_assignment(0, 1, "leader"):
		return _fail("custom_assignment_preview_submit")
	# 预览后的本地真人；一号位与领袖身份由服务规范化后必须立即投射到权威玩家数组。
	var previewed_local_player: PlayerState = _controller.state.players[0]
	# 预览中的其他AI；座次身份预览相当于重新进入选将，不能在背景提前亮出全部AI武将。
	if previewed_local_player.player_id != 0 or previewed_local_player.identity != "leader":
		return _fail("custom_assignment_preview_seat_or_identity")
	for previewed_player: PlayerState in _controller.state.players:
		if not _controller.ai_coordinator.is_ai_controlled(previewed_player.player_id):
			continue
		if not previewed_player.character_id.is_empty() or previewed_player.character_revealed:
			return _fail("custom_assignment_preview_revealed_ai=%s" % previewed_player.character_id)
	# 再把真人预览为二号位反贼；此时一号位必为AI，选将快照必须把公开领袖牌同步为该AI的即时重选武将。
	if not _controller.preview_custom_assignment(0, 2, "rebel"):
		return _fail("custom_assignment_preview_ai_leader_submit")
	# 当前预览领袖；二号位已经固定给本地真人，因此一号位必须由AI补位。
	var previewed_ai_leader: PlayerState = _controller.state.players[0]
	# 当前选将快照；读取控制器入口以验证公开领袖牌使用的是预览结果，而不是服务中保留的首任旧结果。
	var previewed_selection_snapshot: Dictionary = _controller._get_character_selection_snapshot(0)
	if not _controller.ai_coordinator.is_ai_controlled(previewed_ai_leader.player_id) or previewed_ai_leader.character_id.is_empty() or int(previewed_selection_snapshot.get("leader_player_id", -1)) != previewed_ai_leader.player_id or str(previewed_selection_snapshot.get("leader_character_id", "")) != previewed_ai_leader.character_id:
		return _fail("custom_assignment_preview_ai_leader_snapshot")
	for previewed_player: PlayerState in _controller.state.players.slice(1):
		if _controller.ai_coordinator.is_ai_controlled(previewed_player.player_id) and (not previewed_player.character_id.is_empty() or previewed_player.character_revealed):
			return _fail("custom_assignment_preview_other_ai_revealed=%s" % previewed_player.character_id)
	# 本地真人选定【铁壁】持有者；用于在首个roundStart建立真实的可取消技能选择。
	# 本地选择武将ID；自选模式允许直接提交已登记武将，无需受随机候选限制。
	var selected_character_id: String = "xing_cunhu"
	if not GameDatabase.characters.has(selected_character_id):
		return _fail("missing_round_start_choice_character")
	if selected_character_id.is_empty() or not _controller.select_character(0, selected_character_id, 2, "rebel"):
		return _fail("human_custom_selection")
	# 真人确认后AI应立即使用剩余座次与身份完成自选，并停在房主调整阶段。
	if _controller.state.current_phase != "ai_character_adjustment" or _controller.state.players[1].player_id != 0 or _controller.state.players[1].identity != "rebel" or _controller.state.players[0].identity != "leader":
		return _fail("ai_remaining_assignments phase=%s" % _controller.state.current_phase)
	# 可调整AI列表；必须排除本地真人并按最终座次提供稳定玩家ID。
	var adjustable_ai_ids: Array[int] = _controller.ai_character_adjustment.get_ai_player_ids()
	if adjustable_ai_ids.size() != TEST_PLAYER_COUNT - 1 or adjustable_ai_ids.has(0):
		return _fail("adjustable_ai_targets")
	# 非房主提交动作；服务必须拒绝，不能仅依赖界面隐藏按钮。
	var unauthorized_action: PlayerAction = PlayerAction.new("select_ai_adjustment_target", adjustable_ai_ids[0])
	unauthorized_action.payload = {"target_player_id":adjustable_ai_ids[0]}
	if _controller.submit_action(unauthorized_action):
		return _fail("non_host_ai_adjustment")
	# 房主选择AI目标；每次点击都生成私有候选并打开共用选将框。
	var target_action: PlayerAction = PlayerAction.new("select_ai_adjustment_target", 0)
	target_action.payload = {"target_player_id":adjustable_ai_ids[0]}
	if not _controller.submit_action(target_action):
		return _fail("host_select_ai_target")
	# 房主私有调整快照；启用全武将自选时包含全量入口，但明确不允许修改身份与座次。
	var adjustment_snapshot: Dictionary = _controller.ai_character_adjustment.to_selection_dict(0)
	if adjustment_snapshot.is_empty() or not bool(adjustment_snapshot.get("allow_all_characters", false)) or bool(adjustment_snapshot.get("allow_custom_assignment", true)):
		return _fail("ai_adjustment_snapshot")
	# 调整目标当前武将；测试选择一个不同武将以确认权威玩家状态被实际替换。
	var target_player: PlayerState = _controller.state.get_player(adjustable_ai_ids[0])
	# 房主选择的新武将；全量模式允许提交不在本次随机候选中的任意已登记武将。
	var replacement_character_id: String = ""
	for character_id_variant: Variant in GameDatabase.characters.keys():
		# 当前替换候选ID；必须不同于AI当前武将。
		var character_id: String = str(character_id_variant)
		if character_id != target_player.character_id:
			replacement_character_id = character_id
			break
	# 房主改将动作；只携带目标与新武将，不提供座次或身份字段。
	var replace_action: PlayerAction = PlayerAction.new("set_ai_character", 0)
	replace_action.payload = {"target_player_id":target_player.player_id, "character_id":replacement_character_id}
	if replacement_character_id.is_empty() or not _controller.submit_action(replace_action) or target_player.character_id != replacement_character_id:
		return _fail("replace_ai_character")
	# 房主结束调整；随后应发放起始手牌并停在真人手气卡询问阶段。
	var finish_adjustment_action: PlayerAction = PlayerAction.new("finish_ai_character_adjustment", 0)
	if not _controller.submit_action(finish_adjustment_action) or _controller.state.current_phase != "starting_hand_mulligan":
		return _fail("begin_mulligan_phase=%s" % _controller.state.current_phase)
	# 本地真人初始手牌；标准牌数为4，AI已自动评估并完成自己的确认。
	var local_player: PlayerState = _controller.state.get_player(0)
	# 本地真人实际起始手牌数；刷新后必须保持完全相同。
	var initial_hand_count: int = local_player.hand.size()
	if initial_hand_count != 4 or int(_controller.starting_hand_mulligan.to_dict(0).get("remaining", 0)) != 2:
		return _fail("initial_mulligan_state")
	# 刷新前移牌历史长度；新增记录必须包含等量洗回与重发，且不进入弃牌堆。
	var move_history_start: int = _controller.state.card_move_history.size()
	var refresh_action: PlayerAction = PlayerAction.new("mulligan_refresh", 0)
	if not _controller.submit_action(refresh_action) or local_player.hand.size() != initial_hand_count or int(_controller.starting_hand_mulligan.to_dict(0).get("remaining", 0)) != 1:
		return _fail("player_mulligan_refresh")
	# 洗回牌堆记录数；每张旧手牌必须恰好产生一次mulligan_return。
	var return_move_count: int = 0
	# 重新发牌记录数；每张新手牌必须恰好产生一次mulligan_deal。
	var deal_move_count: int = 0
	for history_index: int in range(move_history_start, _controller.state.card_move_history.size()):
		# 当前新增移牌记录；只读取原因和目标玩家，不修改权威历史。
		var move_record: Dictionary = _controller.state.card_move_history[history_index] as Dictionary
		if str(move_record.get("reason", "")) == "mulligan_return":
			return_move_count += 1
		elif str(move_record.get("reason", "")) == "mulligan_deal":
			deal_move_count += 1
	if return_move_count != initial_hand_count or deal_move_count != initial_hand_count or not _controller.state.discard_pile.is_empty():
		return _fail("mulligan_card_movement return=%d deal=%d" % [return_move_count, deal_move_count])
	# 真人确认保留；所有AI已完成，因此本动作后必须离开手气卡阶段并建立首轮roundStart的【铁壁】选择。
	var finish_mulligan_action: PlayerAction = PlayerAction.new("mulligan_finish", 0)
	if not _controller.submit_action(finish_mulligan_action):
		return _fail("finish_mulligan")
	# 首轮选择请求；权威状态进入choice表示询问已建立，选择前保存的界面快照则必须已是roundStart。
	var round_start_choice_request: Dictionary = _latest_card_choice_request
	if _controller.state.current_phase != "choice" or not _controller.has_pending_card_choice() or int(round_start_choice_request.get("chooser_id", -1)) != 0:
		return _fail("round_start_choice_after_mulligan phase=%s chooser=%d" % [_controller.state.current_phase, int(round_start_choice_request.get("chooser_id", -1))])
	# 最近界面快照；手气卡私有字段必须随阶段结束清空，避免界面停留在等待其他玩家确认的提示。
	if str(_latest_state_snapshot.get("current_phase", "")) != "round_start" or not (_latest_state_snapshot.get("starting_hand_mulligan", {}) as Dictionary).is_empty():
		return _fail("round_start_snapshot_kept_mulligan")
	# 放弃首轮可选技能；以标准选择动作验证暂停续列能离开roundStart并进入首回合。
	var cancel_round_start_choice_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	cancel_round_start_choice_action.payload = {
		"request_id":int(round_start_choice_request.get("request_id", -1)),
		"selected_card_uids":[],
		"selected_target_ids":[],
		"selected_button_ids":[],
		"selected_control_id":"",
		"confirmed":false,
	}
	if not _controller.submit_action(cancel_round_start_choice_action):
		return _fail("cancel_round_start_choice")
	# 最终领袖；首回合当前玩家ID必须与一号位领袖一致，不能仍停留在任何开局设置阶段。
	var leader: PlayerState = _controller.state.players[0]
	if _controller.state.current_phase in ["character_selection", "ai_character_adjustment", "starting_hand_mulligan"] or _controller.state.current_player_id != leader.player_id or leader.identity != "leader":
		return _fail("pre_game_completion phase=%s current=%d leader=%d" % [_controller.state.current_phase, _controller.state.current_player_id, leader.player_id])
	return true


## 创建最小权威控制器；三个子组件名称与正式主场景路径保持一致。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；武将技能和开局时机通过该节点派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；除0号真人外全部玩家注册为内置AI。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网络网关；保留与正式控制器相同的动作来源和权限分支。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0
	_controller.state_changed.connect(_on_state_changed)
	_controller.card_choice_requested.connect(_on_card_choice_requested)


## 记录本地观察者最终收到的状态快照；测试不修改快照，避免影响控制器或网络网关的正式状态。
func _on_state_changed(snapshot: Dictionary) -> void:
	_latest_state_snapshot = snapshot.duplicate(true)


## 记录最近发布的普通选择请求；请求副本只用于构造测试提交，测试不会改变权威候选或上下文。
func _on_card_choice_requested(choice_request: Dictionary) -> void:
	_latest_card_choice_request = choice_request.duplicate(true)


## 恢复测试开始前的四项全局设置；成功和失败出口都必须调用。
func _restore_original_settings() -> void:
	GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment_enabled)
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai_enabled)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.set_ai_uses_mulligan_enabled(_original_ai_mulligan_enabled)
	GameSettings.set_character_replacement_count(_original_character_replacement_count)
	GameSettings.set_character_candidate_count(_original_character_candidate_count)


## 输出稳定失败标识、恢复全局设置并以非零状态结束测试。
func _fail(reason: String) -> bool:
	_restore_original_settings()
	printerr("PRE_GAME_CUSTOMIZATION_FAIL %s" % reason)
	get_tree().quit(1)
	return false
