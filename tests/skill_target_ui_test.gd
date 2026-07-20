extends Node

## 技能目标选择界面回归。验证纯目标请求与牌目标组合请求复用牌桌临时选择，不打开独立卡牌窗口。

## 正式主场景初始化等待帧数；保证武将视图和中央按钮已经完成绑定。
const SETTLE_FRAME_COUNT: int = 4


## 延迟运行界面断言，避免主场景就绪流程与测试快照同时写入。
func _ready() -> void:
	call_deferred("_run")


## 注入两名玩家与一张本地手牌，依次验证选目标和牌目标组合的高亮、选择与确认状态。
func _run() -> void:
	# 正式牌桌；技能目标必须复用真实玩家视图与操作按钮。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 正式桌面实例；测试只注入裁剪后的只读快照。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 对局控制器；非法1人配置阻止自动身份局干扰测试快照。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	match_controller.local_human_player_id = 0
	match_controller.randomize_local_human_seat = false
	# 主场景稳定帧；逐帧等待动态玩家视图和操作组件完成初始化。
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 本地组合选择材料牌；只用于界面候选和选中状态。
	var material_card: Dictionary = {"uid":801, "definition_id":"shan", "suit":"heart", "rank":2, "zone":"hand", "owner_id":0}
	match_controller.state_changed.emit(_make_snapshot(material_card, 21))
	await get_tree().process_frame
	# 纯目标请求；没有卡牌候选时仍应使用内联目标交互。
	var target_request: Dictionary = {
		"request_id":21,
		"chooser_id":0,
		"choice_type":"target",
		"title":"选择目标",
		"prompt":"请选择一名目标",
		"candidates":[],
		"target_ids":[1],
		"min_select":1,
		"max_select":1,
		"min_card_select":0,
		"max_card_select":0,
		"min_target_select":1,
		"max_target_select":1,
		"allow_cancel":true,
		"context":{"kind":"ui_target_test", "skill_id":"ui_target_test", "skill_owner_id":0},
	}
	main_instance.call("_on_card_choice_requested", target_request)
	await get_tree().process_frame
	# 独立卡牌选择面板；纯目标请求期间必须保持关闭。
	var selection_panel: CardSelectionPanel = main_instance.get_node("CardSelectionPanel") as CardSelectionPanel
	# 中央确认按钮；选择目标前禁用，选择完成后启用。
	var confirm_button: Button = main_instance.get_node("%UseButton") as Button
	# 原取消按钮；文字选项询问会直接复用该位置展示第二个实际选项。
	var cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	# 当前全部玩家视图；按稳定玩家 ID 定位目标组件。
	var player_views: Dictionary = main_instance.get("_player_views") as Dictionary
	# 1号目标玩家视图；用于验证合法目标和已选目标描边状态。
	var target_view: PlayerTargetView = player_views.get(1) as PlayerTargetView
	# 本地玩家武将牌；纯目标请求中不属于合法候选，应使用统一非法目标暗色。
	var local_player_view: PlayerTargetView = main_instance.get("local_player_card") as PlayerTargetView
	# 牌桌目标指示线层；技能尚未选中目标时不能提前出现指示线。
	var animation_layer: CardUseAnimationLayer = main_instance.get_node("%CardUseAnimationLayer") as CardUseAnimationLayer
	if selection_panel.visible or confirm_button.disabled == false or target_view == null or local_player_view == null or animation_layer == null or not target_view.is_legal_target or target_view.is_target_selected or not target_view.is_target_selection_active or not local_player_view.is_target_selection_active or local_player_view.is_legal_target or local_player_view.modulate.r >= target_view.modulate.r or animation_layer._line_presentations.has(CardUseAnimationLayer.TARGET_PREVIEW_PRESENTATION_KEY):
		_fail("target_initial")
		return
	main_instance.call("_on_target_pressed", 1)
	# 技能选择期间只保留目标描边，不能再显示尚未确认发动的静态预览线。
	if confirm_button.disabled or not target_view.is_target_selected or animation_layer._line_presentations.has(CardUseAnimationLayer.TARGET_PREVIEW_PRESENTATION_KEY):
		_fail("target_selected")
		return
	# 技能实际发动后才生成与卡牌相同的动态指示线；技能上下文的确认目标决定唯一线段终点。
	match_controller.skill_activated.emit(0, "选择测试", {"target_id":1})
	await get_tree().process_frame
	var has_activation_target_indicator: bool = false
	for presentation_key_variant: Variant in animation_layer._line_presentations.keys():
		# 当前表现键；负数预览键不属于实际发动表现，正式动态线使用正数递增序号。
		var presentation_key: int = int(presentation_key_variant)
		var presentation: Dictionary = animation_layer._line_presentations[presentation_key] as Dictionary
		if presentation_key >= 0 and (presentation.get("target_positions", []) as Array).size() == 1:
			has_activation_target_indicator = true
			break
	if not has_activation_target_indicator:
		_fail("target_activation_indicator")
		return
	# 牌目标组合请求；选择材料后目标仍由同一武将牌交互，并满足两个维度后才允许确认。
	# 本地材料候选；保持与正式 card_choice_requested 快照结构一致。
	var candidate: Dictionary = {"uid":801, "owner_id":0, "zone":"hand", "slot":"", "visible":true, "card_data":material_card.duplicate(true)}
	# 组合请求快照；分别要求1张牌和1名目标，并声明牌801只能选择目标1。
	var combined_request: Dictionary = {
		"request_id":22,
		"chooser_id":0,
		"choice_type":"card_target",
		"title":"选择牌和目标",
		"prompt":"请选择一张牌和一名目标",
		"candidates":[candidate],
		"target_ids":[1],
		"min_select":1,
		"max_select":1,
		"min_card_select":1,
		"max_card_select":1,
		"min_target_select":1,
		"max_target_select":1,
		"allow_cancel":true,
		"context":{"kind":"ui_card_target_test", "target_ids_by_card_id":{"801":[1]}},
	}
	main_instance.call("_on_card_choice_requested", combined_request)
	main_instance.call("_on_card_pressed", 801)
	if not confirm_button.disabled or not target_view.is_legal_target or animation_layer._line_presentations.has(CardUseAnimationLayer.TARGET_PREVIEW_PRESENTATION_KEY):
		_fail("combined_card_only")
		return
	main_instance.call("_on_target_pressed", 1)
	if confirm_button.disabled or not target_view.is_target_selected:
		_fail("combined_complete")
		return
	# 冰封文字选项；必须直接使用手牌上方操作区，前两项占用原确定与取消位置，真正放弃使用同一行追加按钮。
	var bingfeng_control_request: Dictionary = {
		"request_id":23,
		"chooser_id":0,
		"choice_type":"control",
		"title":"冰封",
		"prompt":"是否对唯一目标发动【冰封】？",
		"candidates":[],
		"control_options":[{"id":"straighten_target", "label":"1.竖直目标武将牌"}, {"id":"discard_hand", "label":"2.弃置目标手牌"}],
		"allow_cancel":true,
		"context":{"kind":"bingfeng_option", "skill_id":"bingfeng", "skill_owner_id":0, "target_id":1},
	}
	main_instance.call("_on_card_choice_requested", bingfeng_control_request)
	await get_tree().process_frame
	# 同一操作行中的追加取消按钮；control询问不得重新打开中央 CardSelectionPanel。
	var inline_cancel_button: Button = main_instance.get_node_or_null("InteractionPanel/InteractionVBox/ActionRow/InlineControlCancelButton") as Button
	var interaction_panel: Control = main_instance.get_node("InteractionPanel") as Control
	if selection_panel.visible or not interaction_panel.visible or confirm_button.text != "1.竖直目标武将牌" or cancel_button.text != "2.弃置目标手牌" or inline_cancel_button == null or not inline_cancel_button.visible or local_player_view.is_target_selection_active or not local_player_view.modulate.is_equal_approx(Color.WHITE):
		_fail("bingfeng_inline_control")
		return
	if not await _test_active_skill_second_click_cancels(main_instance, match_controller):
		return
	# 对局记录与局内菜单同时展开；未被控件消费的左键代表点击牌桌空白，应一次收起两个浮层。
	var match_log_panel: MatchLogPanel = main_instance.get_node("LogPanel") as MatchLogPanel
	var match_menu: MatchMenu = main_instance.get_node("MatchMenu") as MatchMenu
	match_log_panel.set_expanded(true)
	match_menu.set_menu_open(true)
	var blank_click_event: InputEventMouseButton = InputEventMouseButton.new()
	blank_click_event.button_index = MOUSE_BUTTON_LEFT
	blank_click_event.pressed = true
	main_instance.call("_unhandled_input", blank_click_event)
	if match_log_panel.is_expanded() or match_menu.is_menu_open():
		_fail("blank_click_overlay_close")
		return
	print("SKILL_TARGET_UI_PASS")
	get_tree().quit(0)


## 建立真实【药理】主动流程并再次点击同一技能按钮；取消后材料仍在原手牌且出牌请求重新开放。
func _test_active_skill_second_click_cancels(main_instance: Control, match_controller: MatchController) -> bool:
	# 启动菜单在专项对局期间隐藏；空白点击与技能栏均按正式局内输入层级工作。
	var main_menu: MainMenu = main_instance.get_node("MainMenu") as MainMenu
	main_menu.visible = false
	match_controller.event_scheduler.reset()
	match_controller._pending_card_choice.clear()
	match_controller._pending_negation_choices.clear()
	match_controller._play_choice_request_id = -1
	match_controller._play_choice_event_id = -1
	match_controller._play_choice_actor_id = -1
	match_controller._play_choice_match_id = ""
	# 真实权威状态；娜塔莎持有一张红色手牌，满足【药理】主动发动和后续可取消组合选择条件。
	var game_state: GameState = GameState.new()
	game_state.match_id = "skill-second-click-cancel"
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.phase_index = 3
	var local_player: PlayerState = PlayerState.new(0, "本地玩家")
	local_player.character_id = "natasha"
	local_player.identity = "leader"
	local_player.identity_revealed = true
	local_player.max_hp = 3
	local_player.hp = 3
	# 【药理】红色材料；取消技能后该实体必须仍位于持有者手牌区。
	var red_material_card: CardInstance = CardInstance.new("shan", "heart", 2)
	red_material_card.zone = "hand"
	red_material_card.owner_id = 0
	local_player.hand.append(red_material_card)
	var target_player: PlayerState = PlayerState.new(1, "目标玩家")
	target_player.character_id = "xier"
	target_player.identity = "rebel"
	target_player.identity_revealed = true
	game_state.players.append(local_player)
	game_state.players.append(target_player)
	match_controller.state = game_state
	match_controller.card_rules = CardRuleService.new(game_state, match_controller)
	match_controller.effect_resolver = CardEffectResolver.new(match_controller, game_state)
	match_controller.card_movement = CardMovementService.new(game_state)
	match_controller.trigger_manager = TriggerManager.new()
	match_controller.timing_service = RuleTimingService.new(match_controller.event_bus, match_controller.trigger_manager, game_state)
	# 【药理】独立运行时实例；与正式开局相同地绑定、安装并登记到玩家技能表。
	var yaoli: SkillDefinition = GameDatabase.create_skill("yaoli")
	if yaoli == null:
		return _fail_bool("yaoli_missing")
	yaoli.bind(match_controller, 0)
	yaoli.install()
	match_controller.skill_instances_by_player = {0:{"yaoli":yaoli}}
	match_controller.call("_begin_play_choice", 0)
	match_controller.call("_emit_state")
	await get_tree().process_frame
	# 初次技能按钮；发动后应保持选中且仍可点击，以承担第二次点击取消语义。
	var skill_views: Dictionary = main_instance.get("_skill_views") as Dictionary
	var yaoli_button: SkillButtonView = skill_views.get("yaoli") as SkillButtonView
	if yaoli_button == null or yaoli_button.disabled:
		return _fail_bool("yaoli_button_unavailable")
	main_instance.call("_on_skill_requested", "yaoli")
	await get_tree().process_frame
	yaoli_button = (main_instance.get("_skill_views") as Dictionary).get("yaoli") as SkillButtonView
	var inline_choice: Dictionary = main_instance.get("_inline_card_choice") as Dictionary
	if yaoli_button == null or yaoli_button.disabled or not yaoli_button.is_skill_selected or str((inline_choice.get("context", {}) as Dictionary).get("skill_id", "")) != "yaoli":
		return _fail_bool("yaoli_release_not_selected")
	main_instance.call("_on_skill_requested", "yaoli")
	await get_tree().process_frame
	if match_controller.has_pending_card_choice() or local_player.find_hand_card(red_material_card.uid) == null or not bool(match_controller.call("_has_active_play_choice")) or not (main_instance.get("_inline_card_choice") as Dictionary).is_empty():
		return _fail_bool("yaoli_second_click_cancel")
	return true


## 构造本地观察者快照；只包含技能目标选择需要的公开玩家与本地手牌。
func _make_snapshot(material_card: Dictionary, request_id: int) -> Dictionary:
	# 本地玩家；手牌完整可见。
	var local_player: Dictionary = {"player_id":0, "seat_number":1, "display_name":"本地玩家", "character_id":"gepard", "identity":"leader", "hp":4, "max_hp":4, "alive":true, "chained":false, "hand_count":1, "hand":[material_card.duplicate(true)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "wooden_ox_storage_count":0}
	# 目标玩家；只需要公开武将状态。
	var target_player: Dictionary = {"player_id":1, "seat_number":2, "display_name":"目标玩家", "character_id":"march7th", "identity":"rebel", "hp":4, "max_hp":4, "alive":true, "chained":false, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "wooden_ox_storage_count":0}
	return {"players":[local_player, target_player], "current_player_id":0, "current_phase":"choice", "current_choice_request":{"request_id":request_id, "actor_id":0}, "turn_number":1, "draw_pile_count":100, "discard_pile_count":0, "game_over":false}


## 输出失败原因并以非0状态结束。
func _fail(reason: String) -> void:
	printerr("SKILL_TARGET_UI_FAIL %s" % reason)
	get_tree().quit(1)


## 输出失败并返回 false；异步辅助场景可直接把结果交还主流程停止后续断言。
func _fail_bool(reason: String) -> bool:
	_fail(reason)
	return false
