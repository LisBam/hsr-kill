extends Node

## 开局自定义专项回归。验证房主设置、全武将座次身份自选、AI武将调整与玩家/AI手气卡流程。

## 专项集成测试使用的固定玩家人数；1名真人与3名AI可覆盖剩余名额分配和AI调整。
const TEST_PLAYER_COUNT: int = 4

## 专项集成测试使用的固定随机种子；保证身份、候选与牌堆顺序可重复复现。
const TEST_RANDOM_SEED: int = 20260720

## 测试使用的权威控制器；按正式场景的事件总线、AI协调器和网络网关结构装配。
var _controller: MatchController

## 测试开始前的全武将座次身份设置；结束时原样恢复，避免影响同进程后续测试。
var _original_custom_assignment_enabled: bool = false

## 测试开始前的AI武将调整设置；结束时原样恢复。
var _original_customize_ai_enabled: bool = false

## 测试开始前的手气卡数量；结束时原样恢复。
var _original_mulligan_limit: int = 0

## 测试开始前的AI手气卡设置；结束时原样恢复。
var _original_ai_mulligan_enabled: bool = false


## 延迟执行全部断言，确保自动加载数据库已经完成内容扫描。
func _ready() -> void:
	call_deferred("_run")


## 依次验证界面设置、独立规则服务和完整开局流程；任一失败立即退出。
func _run() -> void:
	_store_original_settings()
	if not await _test_settings_controls():
		return
	if not _test_character_selection_service():
		return
	if not _test_mulligan_ai_evaluation():
		return
	if not _test_authoritative_pre_game_flow():
		return
	_restore_original_settings()
	print("PRE_GAME_CUSTOMIZATION_PASS")
	get_tree().quit(0)


## 保存当前全局开局设置；测试所有成功与失败出口都通过统一恢复入口还原。
func _store_original_settings() -> void:
	_original_custom_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_original_customize_ai_enabled = GameSettings.customize_ai_characters_enabled
	_original_mulligan_limit = GameSettings.mulligan_limit
	_original_ai_mulligan_enabled = GameSettings.ai_uses_mulligan_enabled


## 验证主菜单与局内菜单使用同一设置源，并且局域网客户端会隐藏全部房主权威控件。
func _test_settings_controls() -> bool:
	# 正式主场景资源；设置测试必须读取玩家实际使用的两个菜单，而不是构造替代控件。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("main_scene_load")
	# 正式主场景实例；进入场景树后两个菜单会订阅同一GameSettings信号。
	var main_instance: Control = main_scene.instantiate() as Control
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
	# 正式局内菜单组件；公开权限入口必须统一隐藏四项新设置。
	var match_menu: MatchMenu = main_instance.get_node("%MatchMenu") as MatchMenu
	if main_custom_checkbox == null or match_custom_checkbox == null or main_auto_identity_checkbox == null or match_auto_identity_checkbox == null or main_ai_checkbox == null or match_ai_checkbox == null or main_mulligan_option == null or match_mulligan_option == null or main_ai_mulligan_checkbox == null or match_ai_mulligan_checkbox == null or match_menu == null:
		main_instance.queue_free()
		return _fail("settings_controls_missing")
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
	main_custom_checkbox.toggled.emit(true)
	main_ai_checkbox.toggled.emit(true)
	main_ai_mulligan_checkbox.toggled.emit(true)
	match_mulligan_option.item_selected.emit(2)
	await get_tree().process_frame
	if not match_custom_checkbox.button_pressed or not match_ai_checkbox.button_pressed or not match_ai_mulligan_checkbox.button_pressed or GameSettings.mulligan_limit != 2 or main_mulligan_option.selected != 2:
		main_instance.queue_free()
		return _fail("settings_cross_menu_sync")
	match_menu.set_authority_controls_visible(false)
	if match_custom_checkbox.visible or match_ai_checkbox.visible or match_mulligan_option.get_parent().visible or match_ai_mulligan_checkbox.visible:
		main_instance.queue_free()
		return _fail("client_authority_visibility")
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
	if not service.begin(players, character_ids, 2, rng, true).is_empty():
		return _fail("custom_service_begin")
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
	# 二号玩家尝试重复一号位；即使请求普通身份也会先联动领袖并因座次占用被拒绝。
	var duplicate_seat_error: String = service.select_character(1, character_ids[0], 1, "loyalist")
	if duplicate_seat_error.is_empty():
		return _fail("duplicate_seat_allowed")
	# 二号玩家选择领袖但请求三号位；服务应自动切换为一号位并继续因名额占用拒绝。
	var duplicate_leader_error: String = service.select_character(1, character_ids[0], 3, "leader")
	if duplicate_leader_error.is_empty():
		return _fail("leader_forces_seat_one")
	if not service.select_character(1, character_ids[0], 2, "loyalist").is_empty():
		return _fail("valid_second_assignment")
	# 三号玩家重复忠臣名额；四人局只有1名忠臣，必须被服务拒绝。
	var duplicate_identity_error: String = service.select_character(2, character_ids[0], 3, "loyalist")
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
	_create_controller()
	if not _controller.start_match(TEST_PLAYER_COUNT, TEST_RANDOM_SEED):
		return _fail("authoritative_start")
	if _controller.state.current_phase != "character_selection" or not bool(_controller.state.match_options.get("custom_character_assignment_enabled", false)) or int(_controller.state.match_options.get("mulligan_limit", 0)) != 2:
		return _fail("locked_match_options")
	# 本地真人随机候选；完整自选测试改从全武将列表挑选候选外武将。
	var local_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	# 本地选择的候选外武将；证明控制器同样接受服务开放的全部武将。
	var selected_character_id: String = ""
	for character_id_variant: Variant in GameDatabase.characters.keys():
		# 当前武将ID；避开本次随机候选后作为全量入口提交。
		var character_id: String = str(character_id_variant)
		if not local_candidates.has(character_id):
			selected_character_id = character_id
			break
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
	# 真人确认保留；所有AI已完成，因此本动作后必须离开手气卡阶段并开始领袖首回合。
	var finish_mulligan_action: PlayerAction = PlayerAction.new("mulligan_finish", 0)
	if not _controller.submit_action(finish_mulligan_action):
		return _fail("finish_mulligan")
	# 最终领袖；首回合当前玩家ID必须与一号位领袖一致，不能仍停留在开局设置阶段。
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


## 恢复测试开始前的四项全局设置；成功和失败出口都必须调用。
func _restore_original_settings() -> void:
	GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment_enabled)
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai_enabled)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.set_ai_uses_mulligan_enabled(_original_ai_mulligan_enabled)


## 输出稳定失败标识、恢复全局设置并以非零状态结束测试。
func _fail(reason: String) -> bool:
	_restore_original_settings()
	printerr("PRE_GAME_CUSTOMIZATION_FAIL %s" % reason)
	get_tree().quit(1)
	return false
