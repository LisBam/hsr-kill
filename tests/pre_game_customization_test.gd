extends Node

## 开局自定义专项回归。验证房主设置、全武将座次身份自选、AI武将调整与玩家/AI手气卡流程。

## 专项集成测试使用的固定玩家人数；1名真人与3名AI可覆盖剩余名额分配和AI调整。
const TEST_PLAYER_COUNT: int = 4

## 本地首任领袖真实场景回归使用的玩家人数；五人局可同时验证领袖武将锁定与额外1点体力上限。
const LOCAL_INITIAL_LEADER_TEST_PLAYER_COUNT: int = 5

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
	if not await _test_local_initial_leader_flow():
		return
	if not _test_ai_initial_leader_character_variation():
		return
	if not _test_ai_initial_leader_retains_default_leader_assignment():
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
	# 主菜单手气卡下拉框；必须完整展示关闭、一至五张、十张与无限张共8项。
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
	if main_mulligan_option.item_count != 8 or match_mulligan_option.item_count != 8 or main_mulligan_option.get_item_text(0) != "关闭" or main_mulligan_option.get_item_text(6) != "十张" or main_mulligan_option.get_item_text(7) != "无限张":
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
	match_mulligan_option.item_selected.emit(6)
	match_replacement_option.item_selected.emit(3)
	match_candidate_count_option.item_selected.emit(19)
	await get_tree().process_frame
	if not match_custom_checkbox.button_pressed or not match_ai_checkbox.button_pressed or not match_ai_mulligan_checkbox.button_pressed or GameSettings.mulligan_limit != 10 or main_mulligan_option.selected != 6 or GameSettings.character_replacement_count != 8 or main_replacement_option.selected != 3 or GameSettings.character_candidate_count != 20 or main_candidate_count_option.selected != 19:
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
	# 首任领袖公开选将快照；自选设置尚未进入最终阶段时，座次身份控件必须隐藏且不能阻止领袖确认候选。
	# 当前一次性协议覆盖旧隐藏规则：开启自选时必须在这份首任真人领袖快照直接显示两组控件。
	var initial_leader_snapshot: Dictionary = snapshot.duplicate(true)
	initial_leader_snapshot["phase"] = CharacterSelectionService.PHASE_LEADER
	initial_leader_snapshot["local_identity"] = "leader"
	initial_leader_snapshot["leader_character_id"] = ""
	initial_leader_snapshot["all_character_ids"] = []
	initial_leader_snapshot["allow_all_characters"] = false
	# 一次性领袖自选；首任领袖第一次看到候选时便拥有真实座次身份控件，不再依赖确认武将后的第二份面板。
	initial_leader_snapshot["allow_custom_assignment"] = true
	initial_leader_snapshot["initial_seat_number"] = 1
	initial_leader_snapshot["initial_identity"] = "leader"
	initial_leader_snapshot["preview_seat_number"] = 1
	initial_leader_snapshot["preview_identity"] = "leader"
	selection_panel.bind_snapshot(initial_leader_snapshot)
	await get_tree().process_frame
	selection_panel.call("_select_candidate", character_ids[0])
	var initial_leader_confirm_button: Button = selection_panel.get_node("SelectionFrame/ConfirmCharacterButton") as Button
	var initial_leader_seat_buttons: HBoxContainer = selection_panel.get_node("SelectionFrame/SeatButtons") as HBoxContainer
	var initial_leader_identity_buttons: HBoxContainer = selection_panel.get_node("SelectionFrame/IdentityButtons") as HBoxContainer
	if initial_leader_confirm_button.disabled or not initial_leader_seat_buttons.visible or not initial_leader_identity_buttons.visible:
		main_instance.queue_free()
		return _fail("initial_leader_selection_controls")
	# 首任领袖确认后进入最终自选；即使本地第一次身份就是领袖，也必须重新显示座次与身份按钮。
	# 当前回归把后续快照改为不可操作，用于确认上述旧式重新显示不会再发生。
	var leader_custom_snapshot: Dictionary = snapshot.duplicate(true)
	leader_custom_snapshot["local_identity"] = "leader"
	# 首任领袖已经公开的武将会保留为最终武将；该阶段只显示座次身份控件和确认按钮，不再生成第二组选将牌。
	leader_custom_snapshot["local_candidates"] = []
	leader_custom_snapshot["all_character_ids"] = []
	leader_custom_snapshot["allow_all_characters"] = false
	leader_custom_snapshot["local_selected_character_id"] = character_ids[0]
	leader_custom_snapshot["initial_seat_number"] = 1
	leader_custom_snapshot["initial_identity"] = "leader"
	leader_custom_snapshot["preview_seat_number"] = 1
	leader_custom_snapshot["preview_identity"] = "leader"
	# 首任领袖已经一次性确认；后续阶段快照明确关闭本地权限，面板不得再次弹出。
	leader_custom_snapshot["can_select"] = false
	leader_custom_snapshot["allow_custom_assignment"] = false
	leader_custom_snapshot["retains_selected_character"] = false
	selection_panel.bind_snapshot(leader_custom_snapshot)
	await get_tree().process_frame
	if selection_panel.visible:
		main_instance.queue_free()
		return _fail("initial_leader_custom_assignment_controls")
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
	# ScrollContainer 在内容最小尺寸变化后需要额外一帧同步滚动条页高；真实界面进入后同样已经完成此布局。
	await get_tree().process_frame
	# 候选滚动位置；直接调用统一滚动入口后必须能进入第二行，滚轮与拖动手势都复用该入口。
	candidate_scroll.scroll_vertical = 0
	selection_panel.call("_scroll_candidate_area_by", 120.0)
	await get_tree().process_frame
	if candidate_content.position.y >= 0.0 or candidate_scroll.get_v_scroll_bar().value <= 0.0:
		main_instance.queue_free()
		return _fail("candidate_scroll_input_or_scrollbar_sync")
	# 候选区空白拖动；不命中任一武将牌时仍必须驱动同一个垂直滚动入口，方便移动端滑动卡牌间空白位置。
	candidate_content.position.y = 0.0
	selection_panel.call("_refresh_candidate_scroll_bar_range")
	# 空白拖动按下事件；使用候选区中心位置模拟不由武将牌输入区域消费的开始手势。
	var blank_drag_press: InputEventMouseButton = InputEventMouseButton.new()
	blank_drag_press.button_index = MOUSE_BUTTON_LEFT
	blank_drag_press.pressed = true
	blank_drag_press.position = candidate_scroll.get_global_rect().get_center()
	candidate_content.gui_input.emit(blank_drag_press)
	# 空白拖动位移事件；向上96像素必须进入候选区的向下滚动方向。
	var blank_drag_motion: InputEventMouseMotion = InputEventMouseMotion.new()
	blank_drag_motion.position = blank_drag_press.position + Vector2(0.0, -96.0)
	blank_drag_motion.relative = Vector2(0.0, -96.0)
	candidate_content.gui_input.emit(blank_drag_motion)
	if candidate_content.position.y >= 0.0 or candidate_scroll.get_v_scroll_bar().value <= 0.0:
		main_instance.queue_free()
		return _fail("candidate_blank_drag_scrollbar_sync")
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
	if not replacement_buttons.has(replaceable_character_id) or replacement_button == null or replaceable_character_view == null or not replacement_button.visible or replacement_button.text != "换将 3" or not replacement_button.tooltip_text.is_empty() or replacement_button.position.y < replaceable_character_view.position.y + replaceable_character_view.card_size.y - replacement_button.size.y - CharacterSelectionPanel.REPLACEMENT_BUTTON_BOTTOM_INSET:
		main_instance.queue_free()
		return _fail("replacement_hover_button")
	# 首行候选悬停放大；顶部必须保留安全留白，不能被标题所在的上方UI或滚动裁切区域切掉。
	candidate_scroll.scroll_vertical = 0
	(candidate_views[replaceable_character_id] as PlayerTargetView).call("_on_input_mouse_entered")
	await get_tree().create_timer(selection_panel.candidate_hover_transition_seconds + 0.02).timeout
	if replaceable_character_view.position.y < 0.0:
		main_instance.queue_free()
		return _fail("candidate_hover_top_clipped")
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
	# 全武将返回按钮；必须位于常驻菜单按钮左侧，避免菜单遮挡或拦截返回操作。
	var all_characters_button: Button = selection_panel.get_node("SelectionFrame/AllCharactersButton") as Button
	var menu_button: Button = main_instance.get_node("%MenuButton") as Button
	for candidate_view_variant: Variant in (selection_panel.get("_candidate_views") as Dictionary).values():
		if not (candidate_view_variant as PlayerTargetView).scale.is_equal_approx(Vector2.ONE):
			main_instance.queue_free()
			return _fail("all_characters_card_scaled")
	if selection_frame.size.x < main_instance.size.x - 40.0 or seat_label.visible or identity_label.visible or leader_character_area.visible or all_characters_button.text != "返回" or all_characters_button.get_global_rect().intersects(menu_button.get_global_rect()) or candidate_scroll.is_ancestor_of(confirm_button) or confirm_button.position.y < candidate_scroll.position.y + candidate_scroll.size.y:
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
	var initial_leader_snapshot: Dictionary = service.to_dict(0)
	if service.phase != CharacterSelectionService.PHASE_LEADER or bool(initial_leader_snapshot.get("allow_all_characters", true)) or not bool(initial_leader_snapshot.get("allow_custom_assignment", false)) or service.get_pending_player_ids() != [0] or initial_leader_candidates.slice(0, leader_skill_character_ids.size()) != leader_skill_character_ids or service.get_locked_candidate_ids(0) != leader_skill_character_ids or initial_leader_candidates.size() != mini(character_ids.size(), 2 + leader_skill_character_ids.size()):
		return _fail("leader_skill_candidates")
	# 锁定领袖技候选；换将请求必须拒绝且不能消耗次数。
	if service.replace_candidate(0, leader_skill_character_ids[0]).is_empty() or service.get_replacement_cards_remaining(0) != 3:
		return _fail("locked_leader_candidate_replaced")
	# 首张普通随机候选；成功换将后只替换该位置并消耗一张换将卡。
	var replaceable_character_id: String = initial_leader_candidates[leader_skill_character_ids.size()]
	if not service.replace_candidate(0, replaceable_character_id).is_empty() or service.get_replacement_cards_remaining(0) != 2 or service.get_candidates(0).has(replaceable_character_id):
		return _fail("candidate_replacement")
	# 首任领袖选择；自选模式仍须先完成该公开步骤，之后才进入全员最终确认阶段。
	var initial_leader_character_id: String = leader_skill_character_ids[0]
	# 首任领袖一次性提交；默认一号位与领袖身份和武将使用同一权威动作落定。
	if not service.select_character(0, initial_leader_character_id, 1, "leader").is_empty() or service.phase != CharacterSelectionService.PHASE_CUSTOM:
		return _fail("initial_leader_selection")
	# 首任领袖的公开武将就是最终武将；候选必须清空但座次身份控件仍保持可确认，避免再次弹出选将框。
	# 真人首任领袖当前已经完成座次身份确认，因此候选清空时本地权限和整个面板也必须同步关闭。
	var leader_custom_snapshot: Dictionary = service.to_dict(0)
	# 首任领袖确认后必须彻底退出待选集合；快照不再开启本地控件或保留第二次提交协议。
	if service.can_player_select(0) or not service.get_candidates(0).is_empty() or str(leader_custom_snapshot.get("local_selected_character_id", "")) != initial_leader_character_id or bool(leader_custom_snapshot.get("retains_selected_character", true)) or bool(leader_custom_snapshot.get("allow_all_characters", true)) or bool(leader_custom_snapshot.get("allow_custom_assignment", true)) or service.get_pending_player_ids().has(0):
		return _fail("initial_leader_retained_character_assignment")
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
	# 首任领袖只确认座次与身份并复用公开武将；请求新武将必须被拒绝，一号位会自动联动领袖身份。
	# 该断言现在验证任何第二次提交都被拒绝，不再执行真人保留武将补交路径。
	var different_character_id: String = ""
	for character_id: String in character_ids:
		if character_id != initial_leader_character_id:
			different_character_id = character_id
			break
	# 重复提交无论沿用原武将还是换成其他武将都必须被拒绝，防止后续普通玩家流程再次包含首任领袖。
	if different_character_id.is_empty() or service.select_character(0, different_character_id, 1, "rebel").is_empty() or service.select_character(0, initial_leader_character_id, 1, "rebel").is_empty():
		return _fail("initial_leader_retained_character_submit")
	if service.get_selected_seat_number(0) != 1 or service.get_selected_identity(0) != "leader":
		return _fail("seat_one_forces_leader")
	# 二号玩家候选外武将；开启自选后仍必须允许提交。
	var outside_candidate_id: String = ""
	for character_id: String in character_ids:
		if character_id != initial_leader_character_id and not service.get_candidates(1).has(character_id):
			outside_candidate_id = character_id
			break
	if outside_candidate_id.is_empty() or not service.select_character(1, outside_candidate_id, 2, "loyalist").is_empty():
		return _fail("all_character_or_seat_leader_link")
	# 三号玩家的合法未占用武将；后续座次与身份断言必须排除“重复武将”这一更早的拒绝原因。
	var second_character_id: String = ""
	for character_id: String in character_ids:
		if character_id != initial_leader_character_id and character_id != outside_candidate_id:
			second_character_id = character_id
			break
	if second_character_id.is_empty() or service.select_character(2, outside_candidate_id, 3, "rebel").is_empty():
		return _fail("duplicate_character_allowed")
	# 三号玩家尝试重复一号位；即使请求普通身份也会先联动领袖并因座次占用被拒绝。
	var duplicate_seat_error: String = service.select_character(2, second_character_id, 1, "loyalist")
	if duplicate_seat_error.is_empty():
		return _fail("duplicate_seat_allowed")
	# 三号玩家选择领袖但请求三号位；服务应自动切换为一号位并继续因名额占用拒绝。
	var duplicate_leader_error: String = service.select_character(2, second_character_id, 3, "leader")
	if duplicate_leader_error.is_empty():
		return _fail("leader_forces_seat_one")
	if not service.select_character(2, second_character_id, 3, "rebel").is_empty():
		return _fail("valid_second_assignment")
	# 四号玩家的合法未占用武将；用于确认拒绝原因来自忠臣名额而不是武将重复。
	var third_character_id: String = ""
	for character_id: String in character_ids:
		if character_id != initial_leader_character_id and character_id != outside_candidate_id and character_id != second_character_id:
			third_character_id = character_id
			break
	# 四号玩家重复忠臣名额；四人局只有1名忠臣，必须被服务拒绝。
	var duplicate_identity_error: String = service.select_character(3, third_character_id, 4, "loyalist")
	if duplicate_identity_error.is_empty():
		return _fail("identity_limit_allowed")
	# 普通选将随机源；独立实例保证待选集合回归不受上方自选历史消耗影响。
	var standard_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	standard_rng.seed = TEST_RANDOM_SEED
	# 普通选将服务；用于验证领袖与其他玩家阶段都能返回完整待选玩家，供AI调度逐阶段推进。
	var standard_service: CharacterSelectionService = CharacterSelectionService.new()
	if not standard_service.begin(players, character_ids, 2, standard_rng, false, 0, leader_skill_character_ids).is_empty():
		return _fail("standard_service_begin")
	# 普通首任领袖候选；确认后应只把其余三名玩家留在待选集合。
	var standard_leader_candidates: Array[String] = standard_service.get_candidates(0)
	if standard_leader_candidates.is_empty() or standard_service.get_pending_player_ids() != [0] or not standard_service.select_character(0, standard_leader_candidates[0]).is_empty() or standard_service.phase != CharacterSelectionService.PHASE_OTHERS or standard_service.get_pending_player_ids() != [1, 2, 3]:
		return _fail("standard_pending_player_ids")
	return true


## 验证本地真人首次随机成为领袖时，正式界面只补交座次身份，并在开局后保留首次公开武将。
func _test_local_initial_leader_flow() -> bool:
	GameSettings.set_custom_character_assignment_enabled(true)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	# 正式主场景；测试复用玩家实际使用的控制器、牌桌信号连接与选将面板，不手工拼接中间快照。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("local_initial_leader_main_scene_load")
	# 正式主场景实例；固定逻辑视口尺寸保证座次身份控件使用与实机相同的布局路径。
	var main_instance: Control = main_scene.instantiate() as Control
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.size = Vector2(1280.0, 720.0)
	add_child(main_instance)
	for _frame_index: int in range(4):
		await get_tree().process_frame
	# 正式权威控制器；保持默认随机本地座次，覆盖玩家ID先随机再分配身份的实际离线开局路径。
	var controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 正式选将面板；其提交信号已经由牌桌连接到同一控制器。
	var selection_panel: CharacterSelectionPanel = main_instance.get_node("CharacterSelectionPanel") as CharacterSelectionPanel
	controller.local_human_player_id = 0
	controller.randomize_local_human_seat = true
	controller.game_flow_interval_seconds = 0.0
	controller.ai_action_delay_seconds = 0.0
	# 能让随机座次后的本地玩家首次成为领袖的种子；从小整数稳定扫描，避免测试依赖随机算法之外的硬编码身份排列。
	var local_leader_seed: int = -1
	# 当前种子实际分配的本地玩家ID；后续所有界面提交和状态断言都必须使用同一稳定值。
	var local_player_id: int = -1
	for candidate_seed: int in range(1, 65):
		if not controller.start_match(LOCAL_INITIAL_LEADER_TEST_PLAYER_COUNT, candidate_seed):
			main_instance.queue_free()
			await get_tree().process_frame
			return _fail("local_initial_leader_start")
		if controller.character_selection.get_initial_identity(controller.local_human_player_id) == "leader":
			local_leader_seed = candidate_seed
			local_player_id = controller.local_human_player_id
			break
	if local_leader_seed < 0 or local_player_id < 0 or controller.character_selection.phase != CharacterSelectionService.PHASE_LEADER:
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_seed")
	# 首次领袖候选；点击并确认后，该稳定武将ID必须同时成为公开预览和最终保留结果。
	var initial_leader_candidates: Array[String] = controller.character_selection.get_candidates(local_player_id)
	if initial_leader_candidates.is_empty():
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_candidates")
	# 首次选将座次控件；首任领袖第一次选择武将时必须已经可见，不等待第二份快照。
	var seat_buttons: HBoxContainer = selection_panel.get_node("SelectionFrame/SeatButtons") as HBoxContainer
	# 首次选将身份控件；默认高亮领袖并与一号位组成同一次提交。
	var identity_buttons: HBoxContainer = selection_panel.get_node("SelectionFrame/IdentityButtons") as HBoxContainer
	# 固定确认按钮；选择武将前保持禁用，座次身份默认值不能单独触发提交。
	var confirm_button: Button = selection_panel.get_node("SelectionFrame/ConfirmCharacterButton") as Button
	if not selection_panel.visible or not seat_buttons.visible or not identity_buttons.visible or int(selection_panel.get("_selected_seat_number")) != 1 or str(selection_panel.get("_selected_identity")) != "leader":
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_assignment_controls")
	# 首次领袖选择；使用面板私有入口模拟正式牌面短按，再走确认按钮信号提交标准动作。
	# 布洛妮娅稳定ID；优先复现实机报告，若内容库变体未提供该ID才回退首张合法候选。
	var initial_leader_character_id: String = "bronya" if initial_leader_candidates.has("bronya") else initial_leader_candidates[0]
	selection_panel.call("_select_candidate", initial_leader_character_id)
	if confirm_button.disabled:
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_single_confirm_disabled")
	selection_panel.call("_confirm_selection")
	await get_tree().process_frame
	# 最终自选阶段控件；本地首任领袖不得获得第二批候选，但必须保留座次、身份和可用确认按钮。
	# 最终自选身份控件；与座次控件同时显示，初始领袖默认高亮一号位和领袖身份。
	# 固定确认按钮；首任领袖复用首次武将，因此无需再次点击候选即可确认座次身份。
	# 上述三行描述旧式二次面板；当前断言要求一次提交后面板完全关闭且该玩家不在待选集合中。
	# 当前流程不再进入上述第二次确认状态；一次提交后服务完成其余AI选择，选将面板必须保持关闭。
	if controller.character_selection.phase != CharacterSelectionService.PHASE_COMPLETE or selection_panel.visible or controller.character_selection.can_player_select(local_player_id) or controller.character_selection.get_pending_player_ids().has(local_player_id) or not controller.character_selection.get_candidates(local_player_id).is_empty():
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_reopened_selection")
	# 本地首任领袖提交次数；随机历史必须只有一条该玩家的选将记录，防止普通玩家阶段再次处理领袖。
	var local_character_selection_count: int = 0
	for history_variant: Variant in controller.state.random_history:
		# 当前随机历史记录；只统计稳定玩家ID对应的正式选将动作，不把预览或候选生成计入。
		var history_entry: Dictionary = history_variant as Dictionary
		if str(history_entry.get("kind", "")) == "character_selection" and int(history_entry.get("player_id", -1)) == local_player_id:
			local_character_selection_count += 1
	if local_character_selection_count != 1:
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_selection_count=%d" % local_character_selection_count)
	# 开局后的本地玩家；稳定ID不随最终座次重排，武将必须与首次公开选择完全一致。
	var final_local_player: PlayerState = controller.state.get_player(local_player_id)
	# 首次选择武将的基础体力上限；五人局最终领袖应在该配置上准确增加1点，不能因重复应用武将产生其他结果。
	var initial_character_base_max_hp: int = int(GameDatabase.get_character(initial_leader_character_id).get("max_hp", 4))
	if final_local_player == null or final_local_player.character_id != initial_leader_character_id or final_local_player.max_hp != initial_character_base_max_hp + 1 or controller.state.players[0].player_id != local_player_id or controller.state.players[0].identity != "leader":
		main_instance.queue_free()
		await get_tree().process_frame
		return _fail("local_initial_leader_character_retained")
	controller.abandon_match()
	main_instance.queue_free()
	await get_tree().process_frame
	return true


## 验证AI首任领袖只在领袖技固定候选中使用本局随机源选择，连续固定种子不能总是同一名武将。
func _test_ai_initial_leader_character_variation() -> bool:
	GameSettings.set_custom_character_assignment_enabled(true)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	_create_controller()
	# 当前拥有至少一个领袖技的武将集合；内容库拥有多名时，AI首任领袖必须能产生多个稳定武将ID。
	var leader_skill_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		# 当前武将定义；技能数组只读，用于确认该武将是否属于领袖技固定候选。
		var character_id: String = str(character_id_variant)
		# 当前武将技能ID；任一技能带领袖技标记即可加入固定候选集合。
		var skill_ids: Array = GameDatabase.get_character(character_id).get("skills", []) as Array
		for skill_id_variant: Variant in skill_ids:
			if bool(GameDatabase.get_skill(str(skill_id_variant)).get("leader_skill", false)):
				leader_skill_character_ids.append(character_id)
				break
	# 多个固定种子下实际由AI首任领袖选中的武将ID；字典键去重避免依赖随机生成顺序。
	var observed_initial_leader_character_ids: Dictionary = {}
	for candidate_seed: int in range(1, 65):
		if not _controller.start_match(LOCAL_INITIAL_LEADER_TEST_PLAYER_COUNT, candidate_seed):
			return _fail("ai_initial_leader_variation_start")
		# 当前首任领袖稳定玩家ID；本地真人成为首任领袖时不会进入AI自动选择，跳过该种子。
		var initial_leader_player_id: int = _controller.character_selection.leader_player_id
		if initial_leader_player_id == _controller.local_human_player_id:
			continue
		# 当前首任AI领袖公开武将；服务已经把自动选择写入权威状态，空值表示阶段推进失败。
		var initial_leader_character_id: String = _controller.state.get_player(initial_leader_player_id).character_id
		if initial_leader_character_id.is_empty():
			return _fail("ai_initial_leader_variation_missing_character")
		observed_initial_leader_character_ids[initial_leader_character_id] = true
	# 当前内容库拥有两名或以上领袖技武将时，固定种子覆盖必须至少观测到两种结果，防止退化为恒取候选首张。
	if leader_skill_character_ids.size() >= 2 and observed_initial_leader_character_ids.size() < 2:
		return _fail("ai_initial_leader_variation=%s" % str(observed_initial_leader_character_ids.keys()))
	_controller.abandon_match()
	_controller.queue_free()
	_controller = null
	return true


## 验证首任AI领袖在真人按首次随机座次身份确认后，优先取得仍空缺的一号位与领袖身份并保留公开武将。
func _test_ai_initial_leader_retains_default_leader_assignment() -> bool:
	GameSettings.set_custom_character_assignment_enabled(true)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	_create_controller()
	# 当前首任AI领袖对局种子；循环避免把某次随机洗牌恰好令本地真人成为领袖误判为测试通过。
	var selected_seed: int = -1
	for candidate_seed: int in range(1, 65):
		if not _controller.start_match(LOCAL_INITIAL_LEADER_TEST_PLAYER_COUNT, candidate_seed):
			return _fail("ai_initial_leader_default_start")
		if _controller.character_selection.leader_player_id != _controller.local_human_player_id:
			selected_seed = candidate_seed
			break
	# 首任领袖稳定玩家ID；只有AI持有该ID时才覆盖本次自动优先确认规则。
	var initial_leader_player_id: int = _controller.character_selection.leader_player_id
	# 首任领袖已经公开的稳定武将ID；最终桌面的领袖必须保留该值。
	var initial_leader_character_id: String = _controller.state.get_player(initial_leader_player_id).character_id
	# 本地真人的私有随机候选；按首次随机座次身份确认其首张候选，不主动改变领袖归属。
	var local_candidates: Array[String] = _controller.character_selection.get_candidates(_controller.local_human_player_id)
	if selected_seed < 0 or _controller.character_selection.phase != CharacterSelectionService.PHASE_CUSTOM or initial_leader_character_id.is_empty() or local_candidates.is_empty():
		return _fail("ai_initial_leader_default_setup")
	# 本地真人首次随机座次；提交默认值保证测试覆盖“未抢占领袖”的常规流程。
	var local_initial_seat_number: int = _controller.character_selection.get_initial_seat_number(_controller.local_human_player_id)
	# 本地真人首次随机身份；与默认座次一起确认，不能使用预览中的临时值替代。
	var local_initial_identity: String = _controller.character_selection.get_initial_identity(_controller.local_human_player_id)
	if not _controller.select_character(_controller.local_human_player_id, local_candidates[0], local_initial_seat_number, local_initial_identity):
		return _fail("ai_initial_leader_default_submit")
	# 最终首任领袖状态；稳定玩家ID即使经过座次旋转也必须保留原武将与领袖身份。
	var final_initial_leader: PlayerState = _controller.state.get_player(initial_leader_player_id)
	# 最终一号位；身份局开局会以领袖旋转数组，因此该对象必须就是首任AI领袖。
	var table_leader: PlayerState = _controller.state.players[0] if not _controller.state.players.is_empty() else null
	if final_initial_leader == null or final_initial_leader.character_id != initial_leader_character_id or final_initial_leader.identity != "leader" or table_leader == null or table_leader.player_id != initial_leader_player_id or table_leader.character_id != initial_leader_character_id:
		return _fail("ai_initial_leader_default_retained seed=%d initial=%s final=%s identity=%s table=%d/%s" % [selected_seed, initial_leader_character_id, final_initial_leader.character_id if final_initial_leader != null else "", final_initial_leader.identity if final_initial_leader != null else "", table_leader.player_id if table_leader != null else -1, table_leader.character_id if table_leader != null else ""])
	_controller.abandon_match()
	_controller.queue_free()
	_controller = null
	return true


## 验证AI后置位防御阈值、关闭开关和无限张语义。
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
	# 无限张服务；连续消费不会递减私有快照中的-1。
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
	# 权威流程随机种子；本用例固定选择“首任领袖为AI、本地真人为其他身份”，以覆盖AI领袖自动一次性确认后的真人自选阶段。
	var authoritative_seed: int = -1
	for candidate_seed: int in range(TEST_RANDOM_SEED, TEST_RANDOM_SEED + 64):
		if not _controller.start_match(TEST_PLAYER_COUNT, candidate_seed):
			return _fail("authoritative_start")
		if _controller.character_selection.get_initial_identity(0) != "leader":
			authoritative_seed = candidate_seed
			break
	if authoritative_seed < 0:
		return _fail("authoritative_non_leader_seed")
	if _controller.state.current_phase != "character_selection" or not bool(_controller.state.match_options.get("custom_character_assignment_enabled", false)) or int(_controller.state.match_options.get("mulligan_limit", 0)) != 2 or int(_controller.state.match_options.get("character_replacement_count", 0)) != 3 or int(_controller.state.match_options.get("character_candidate_count", 0)) != 7:
		return _fail("locked_match_options")
	# 首次身份分配中的领袖ID；自选阶段开始后仍用于验证公开亮将没有提前被最终座次覆盖。
	var initial_leader_player_id: int = _controller.character_selection.leader_player_id
	# 本地玩家首次身份；自选私有快照必须继续展示该值。
	var initial_local_identity: String = _controller.state.get_player(0).identity
	if _controller.character_selection.phase == CharacterSelectionService.PHASE_LEADER:
		# 本地玩家恰好是首任领袖；先从权威候选中确认亮将，不能直接携带最终座次身份跳过该阶段。
		var initial_candidates: Array[String] = _controller.character_selection.get_candidates(0)
		if initial_leader_player_id != 0 or initial_candidates.is_empty() or not _controller.select_character(0, initial_candidates[0], _controller.character_selection.get_initial_seat_number(0), _controller.character_selection.get_initial_identity(0)):
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
	# 默认高亮不是纯界面效果；按首次随机的座次身份提交预览后，当前场上领袖与公开武将必须保持原状。
	# 本地首次随机座次；服务快照与当前PlayerState必须使用同一个实际分配值。
	var initial_local_seat_number: int = _controller.character_selection.get_initial_seat_number(0)
	if not _controller.preview_custom_assignment(0, initial_local_seat_number, initial_local_identity):
		return _fail("default_custom_assignment_preview_submit")
	# 默认组合预览快照；用于确认首次公开领袖牌没有被预览流程重新随机。
	var default_preview_snapshot: Dictionary = _controller._get_character_selection_snapshot(0)
	if _controller.state.players[0].player_id != initial_leader_player_id or _controller.state.players[0].identity != "leader" or str(default_preview_snapshot.get("leader_character_id", "")) != initial_leader_character_id:
		return _fail("default_custom_assignment_preserves_initial_state leader=%d/%d identity=%s character=%s/%s" % [_controller.state.players[0].player_id, initial_leader_player_id, _controller.state.players[0].identity, str(default_preview_snapshot.get("leader_character_id", "")), initial_leader_character_id])
	# 真人将自身预览为一号位领袖；不确认武将也必须立刻重排牌桌、更新身份。
	if not _controller.preview_custom_assignment(0, 1, "leader"):
		return _fail("custom_assignment_preview_submit")
	# 预览后的本地真人；一号位与领袖身份由服务规范化后必须立即投射到权威玩家数组。
	var previewed_local_player: PlayerState = _controller.state.players[0]
	# 新领袖是尚未选将的真人时，公开区域必须立即清空旧首任领袖，而不能继续显示错误的背景领袖牌。
	# 人类领袖预览快照；尚未确认武将时应主动清空旧领袖武将ID。
	var human_leader_preview_snapshot: Dictionary = _controller._get_character_selection_snapshot(0)
	# 预览中的其他AI；首任领袖的公开武将属于已确定的最终结果，其他未确认AI仍不得提前亮将。
	# 是否由另一名首任领袖切换而来；首任领袖恰为本地玩家时保留其公开牌属于正确状态。
	var expects_previous_leader_hidden: bool = initial_leader_player_id != 0
	if previewed_local_player.player_id != 0 or previewed_local_player.identity != "leader" or int(human_leader_preview_snapshot.get("leader_player_id", -1)) != 0 or (expects_previous_leader_hidden and not str(human_leader_preview_snapshot.get("leader_character_id", "fallback")).is_empty()):
		return _fail("custom_assignment_preview_seat_or_identity")
	for previewed_player: PlayerState in _controller.state.players:
		if not _controller.ai_coordinator.is_ai_controlled(previewed_player.player_id):
			continue
		if previewed_player.player_id == initial_leader_player_id:
			if previewed_player.character_id != initial_leader_character_id or not previewed_player.character_revealed:
				return _fail("custom_assignment_preview_lost_initial_leader=%s/%s" % [previewed_player.character_id, initial_leader_character_id])
			continue
		if not previewed_player.character_id.is_empty() or previewed_player.character_revealed:
			return _fail("custom_assignment_preview_revealed_ai=%s" % previewed_player.character_id)
	# 再把真人预览为二号位反贼；此时一号位必为AI，选将快照必须把公开领袖牌同步为该AI的即时重选武将。
	if not _controller.preview_custom_assignment(0, 2, "rebel"):
		return _fail("custom_assignment_preview_ai_leader_submit")
	# 当前预览领袖；二号位已经固定给本地真人，因此一号位必须由AI补位。
	var previewed_ai_leader: PlayerState = _controller.state.players[0]
	# 已公开AI领袖武将；随后最终确认必须复用该牌，而不是重新从候选池随机抽取。
	var previewed_ai_leader_character_id: String = previewed_ai_leader.character_id
	# 当前选将快照；读取控制器入口以验证公开领袖牌使用的是预览结果，而不是服务中保留的首任旧结果。
	var previewed_selection_snapshot: Dictionary = _controller._get_character_selection_snapshot(0)
	if not _controller.ai_coordinator.is_ai_controlled(previewed_ai_leader.player_id) or previewed_ai_leader.character_id.is_empty() or int(previewed_selection_snapshot.get("leader_player_id", -1)) != previewed_ai_leader.player_id or str(previewed_selection_snapshot.get("leader_character_id", "")) != previewed_ai_leader.character_id:
		return _fail("custom_assignment_preview_ai_leader_snapshot")
	for previewed_player: PlayerState in _controller.state.players.slice(1):
		if _controller.ai_coordinator.is_ai_controlled(previewed_player.player_id) and previewed_player.player_id != initial_leader_player_id and (not previewed_player.character_id.is_empty() or previewed_player.character_revealed):
			return _fail("custom_assignment_preview_other_ai_revealed=%s" % previewed_player.character_id)
	# 本地真人选定【铁壁】持有者；用于在首个roundStart建立真实的可取消技能选择。
	# 本地选择武将ID；自选模式允许直接提交已登记武将，无需受随机候选限制。
	var selected_character_id: String = "xing_cunhu"
	if not GameDatabase.characters.has(selected_character_id):
		return _fail("missing_round_start_choice_character")
	if selected_character_id.is_empty() or not _controller.select_character(0, selected_character_id, 2, "rebel"):
		return _fail("human_custom_selection")
	# 真人确认后AI应立即使用剩余座次与身份完成自选，并停在房主调整阶段。
	var final_initial_leader: PlayerState = _controller.state.get_player(initial_leader_player_id)
	if _controller.state.current_phase != "ai_character_adjustment" or _controller.state.players[1].player_id != 0 or _controller.state.players[1].identity != "rebel" or _controller.state.players[0].identity != "leader" or _controller.state.players[0].character_id != previewed_ai_leader_character_id or final_initial_leader == null or final_initial_leader.character_id != initial_leader_character_id:
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
