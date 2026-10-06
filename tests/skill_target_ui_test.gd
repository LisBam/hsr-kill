extends Node

## 技能目标选择界面回归。验证纯目标请求与牌目标组合请求复用牌桌临时选择，不打开独立卡牌窗口。
## 目标文字选项复合请求同样复用牌桌目标状态，并在目标未选满前禁用实际效果按钮。
## 技能发动流程（选牌、选目标、文字选项）进行中时，该技能按钮必须失效且点击被忽略，
## 取消只能由操作区“取消”按钮表达；多段技能不得因再次点击而跳到下一段。

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
	# 独立目标指示器表现；技能可以在不发动、不写日志的情况下请求指向一组新目标。
	# 本用例只注入裁剪快照而没有权威对局状态，因此直接发布表现信号验证界面链路；
	# 端口侧的目标过滤与返回值由带真实对局状态的规则测试覆盖。
	# 先清空上一条发动线，避免把残留表现误判成本次新画的线段。
	animation_layer.clear_presentations()
	# 目标数组必须显式声明为 Array[int]：信号参数带类型，未类型化的字面量会因类型不符而无法送达界面。
	var indicator_targets: Array[int] = [1]
	match_controller.skill_target_indicated.emit(0, indicator_targets)
	await get_tree().process_frame
	var has_standalone_indicator: bool = false
	for standalone_key_variant: Variant in animation_layer._line_presentations.keys():
		# 当前表现键；正式动态线使用正数递增序号，负数预览键不属于本端口。
		var standalone_key: int = int(standalone_key_variant)
		var standalone_presentation: Dictionary = animation_layer._line_presentations[standalone_key] as Dictionary
		if standalone_key >= 0 and (standalone_presentation.get("target_positions", []) as Array).size() == 1:
			has_standalone_indicator = true
			break
	if not has_standalone_indicator:
		_fail("standalone_target_indicator_missing")
		return
	# 不可取消的0至2名目标请求；【好戏】等强制发动的技能用“不选任何角色”表达原文的0名目标。
	# 此时确定按钮必须可用，否则这次强制发动没有任何可提交的结果，玩家会卡在选择窗口。
	var zero_target_request: Dictionary = {
		"request_id":25,
		"chooser_id":0,
		"choice_type":"target",
		"title":"好戏",
		"prompt":"请选择0至2名其他角色各弃置一张随机手牌",
		"candidates":[],
		"target_ids":[1],
		"min_select":0,
		"max_select":2,
		"min_card_select":0,
		"max_card_select":0,
		"min_target_select":0,
		"max_target_select":2,
		"allow_cancel":false,
		"context":{"kind":"ui_zero_target_test", "skill_id":"ui_zero_target_test", "skill_owner_id":0},
	}
	main_instance.call("_on_card_choice_requested", zero_target_request)
	if target_view.is_target_selected or confirm_button.disabled or cancel_button.disabled == false:
		_fail("zero_target_confirm selected=%s confirm=%s cancel=%s" % [str(target_view.is_target_selected), str(confirm_button.disabled), str(cancel_button.disabled)])
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
	# 公共弃牌候选；投狭的候选属于弃牌堆且不属于本地手牌，必须进入独立窗口并显示正面牌面。
	var discard_candidate_card: Dictionary = material_card.duplicate(true)
	discard_candidate_card["uid"] = 802
	discard_candidate_card["zone"] = "discard_pile"
	discard_candidate_card["owner_id"] = -1
	discard_candidate_card["suit"] = "heart"
	var touxia_gain_request: Dictionary = {
		"request_id":24,
		"chooser_id":0,
		"choice_type":"card",
		"title":"投狭",
		"prompt":"请选择获得一张与判定结果花色相同的牌，或取消",
		"candidates":[{"uid":802, "owner_id":-1, "zone":"discard_pile", "slot":"", "visible":true, "card_data":discard_candidate_card}],
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"context":{"kind":"touxia_gain", "turn_number":1, "turn_player_id":1, "judgment_suit":"heart"},
	}
	main_instance.call("_on_card_choice_requested", touxia_gain_request)
	await get_tree().process_frame
	# 独立窗口内部的卡牌视图映射；漏掉 discard_pile 分区会导致该 UID不存在且玩家看不到候选。
	var discard_card_views: Dictionary = selection_panel.get("_card_views") as Dictionary
	var discard_section_labels: Array = selection_panel.get("_section_labels") as Array
	if not selection_panel.visible or not discard_card_views.has(802) or discard_section_labels.is_empty() or str((discard_section_labels[0] as Label).text) != "弃牌堆":
		_fail("touxia_discard_candidate_visible views=%s labels=%s" % [discard_card_views.keys(), discard_section_labels])
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
	# 秘策式目标文字选项复合请求；未选择目标前两个实际阶段按钮必须保持禁用，真正取消按钮仍可使用。
	var target_control_request: Dictionary = {
		"request_id":25,
		"chooser_id":0,
		"choice_type":"target_control",
		"title":"秘策",
		"prompt":"请选择一名其他角色并选择其执行的阶段",
		"candidates":[],
		"target_ids":[1],
		"control_options":[{"id":"play_phase", "label":"出牌阶段"}, {"id":"discard_phase", "label":"弃牌阶段"}],
		"min_select":1,
		"max_select":1,
		"min_card_select":0,
		"max_card_select":0,
		"min_target_select":1,
		"max_target_select":1,
		"allow_cancel":true,
		"context":{"kind":"mice_target_option", "skill_id":"mice", "skill_owner_id":0},
	}
	main_instance.call("_on_card_choice_requested", target_control_request)
	await get_tree().process_frame
	# 复合请求的真正取消按钮；与两个阶段按钮同处原操作行，但不受目标选择完成度限制。
	var target_control_cancel_button: Button = main_instance.get_node_or_null("InteractionPanel/InteractionVBox/ActionRow/InlineControlCancelButton") as Button
	if selection_panel.visible or confirm_button.text != "出牌阶段" or cancel_button.text != "弃牌阶段" or not confirm_button.disabled or not cancel_button.disabled or target_control_cancel_button == null or target_control_cancel_button.disabled or not target_view.is_legal_target or target_view.is_target_selected:
		_fail("target_control_initial")
		return
	main_instance.call("_on_target_pressed", 1)
	if confirm_button.disabled or cancel_button.disabled or not target_view.is_target_selected or not target_view.is_target_selection_active:
		_fail("target_control_selected")
		return
	if not await _test_active_skill_reclick_is_ignored(main_instance, match_controller):
		return
	if not await _test_zhuoshi_reclick_does_not_skip_stage(main_instance, match_controller):
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


## 隔离上一次界面断言留下的控制器状态；技能专项对局必须从空闲出牌请求开始。
## 界面断言只注入快照，不经过开局流程，因此这里必须手动清理可能残留的请求与否定询问。
func _prepare_isolated_match(match_controller: MatchController) -> void:
	match_controller.event_scheduler.reset()
	match_controller._pending_card_choice.clear()
	match_controller._pending_negation_choices.clear()
	match_controller._deferred_skill_settlements.clear()
	match_controller._play_choice_request_id = -1
	match_controller._play_choice_event_id = -1
	match_controller._play_choice_actor_id = -1
	match_controller._play_choice_match_id = ""


## 返回当前内联请求上下文；空字典表示此刻没有内联询问。
func _inline_context(main_instance: Control) -> Dictionary:
	# 当前内联请求快照；界面只读保存控制器刚下发的同一份数据。
	var inline_choice: Dictionary = main_instance.get("_inline_card_choice") as Dictionary
	return inline_choice.get("context", {}) as Dictionary


## 返回当前内联请求的权威序号；-1表示没有内联询问。
func _inline_request_id(main_instance: Control) -> int:
	var inline_choice: Dictionary = main_instance.get("_inline_card_choice") as Dictionary
	return int(inline_choice.get("request_id", -1))


## 通过标准 choose_cards 动作提交当前请求；与桌面按钮走完全相同的权威校验入口。
func _submit_choice(match_controller: MatchController, card_uids: Array[int], target_ids: Array[int], confirmed: bool) -> bool:
	# 当前权威请求序号；与待处理请求不一致的提交会被规则层拒绝。
	var request_id: int = int(match_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；负载字段与桌面端 _on_card_choice_submitted 完全一致。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":request_id, "selected_card_uids":card_uids.duplicate(), "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	return match_controller.submit_action(action)


## 建立真实【药理】主动流程并再次点击同一技能按钮；按钮必须失效且点击被完全忽略。
## 取消出口改由操作区“取消”按钮承担，取消后材料仍在原手牌且出牌请求重新开放。
func _test_active_skill_reclick_is_ignored(main_instance: Control, match_controller: MatchController) -> bool:
	# 启动菜单在专项对局期间隐藏；空白点击与技能栏均按正式局内输入层级工作。
	var main_menu: MainMenu = main_instance.get_node("MainMenu") as MainMenu
	main_menu.visible = false
	_prepare_isolated_match(match_controller)
	# 真实权威状态；娜塔莎持有一张红色手牌，满足【药理】主动发动和后续可取消组合选择条件。
	var game_state: GameState = GameState.new()
	game_state.match_id = "skill-reclick-lock"
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.phase_index = 3
	var local_player: PlayerState = PlayerState.new(0, "本地玩家")
	local_player.character_id = "natasha"
	local_player.identity = "leader"
	local_player.identity_revealed = true
	local_player.max_hp = 3
	local_player.hp = 3
	# 【药理】红色材料；点击被忽略后该实体必须仍位于持有者手牌区。
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
	# 初次技能按钮；未发动时应保持可用。
	var skill_views: Dictionary = main_instance.get("_skill_views") as Dictionary
	var yaoli_button: SkillButtonView = skill_views.get("yaoli") as SkillButtonView
	if yaoli_button == null or yaoli_button.disabled:
		return _fail_bool("yaoli_button_unavailable")
	main_instance.call("_on_skill_requested", "yaoli")
	await get_tree().process_frame
	yaoli_button = (main_instance.get("_skill_views") as Dictionary).get("yaoli") as SkillButtonView
	var inline_choice: Dictionary = main_instance.get("_inline_card_choice") as Dictionary
	# 发动流程进行中：按钮必须禁用，但仍保留金色选中描边表示这条流程属于该技能。
	if yaoli_button == null or not yaoli_button.disabled or not yaoli_button.is_skill_selected or str((inline_choice.get("context", {}) as Dictionary).get("skill_id", "")) != "yaoli":
		return _fail_bool("yaoli_release_button_not_locked")
	# 记录点击前的权威请求；再次点击后必须仍是同一个请求，且不产生任何新提交。
	var request_id_before: int = _inline_request_id(main_instance)
	main_instance.call("_on_skill_requested", "yaoli")
	await get_tree().process_frame
	if not match_controller.has_pending_card_choice() or _inline_request_id(main_instance) != request_id_before or str(_inline_context(main_instance).get("kind", "")) != "yaoli_gift" or local_player.find_hand_card(red_material_card.uid) == null:
		return _fail_bool("yaoli_reclick_submitted")
	# 取消出口仍然存在：操作区“取消”按钮提交与旧按钮二次点击完全相同的 confirmed=false。
	var cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	if cancel_button == null or not cancel_button.visible or cancel_button.disabled:
		return _fail_bool("yaoli_cancel_button_unavailable")
	cancel_button.emit_signal("pressed")
	await get_tree().process_frame
	if match_controller.has_pending_card_choice() or local_player.find_hand_card(red_material_card.uid) == null or not bool(match_controller.call("_has_active_play_choice")) or not (main_instance.get("_inline_card_choice") as Dictionary).is_empty():
		return _fail_bool("yaoli_cancel_button_failed")
	return true


## 多段主动技【濯世】的第二段费用询问期间点击技能按钮：必须停留在第二段，不得跳到第三段。
## 该用例直接对应玩家报告的现象（“点一下按钮就直接进入下个阶段”）。
func _test_zhuoshi_reclick_does_not_skip_stage(main_instance: Control, match_controller: MatchController) -> bool:
	_prepare_isolated_match(match_controller)
	# 真实权威状态；本地玩家使用丹恒·饮月，技能栏同时出现【伏辰】与【濯世】。
	var game_state: GameState = GameState.new()
	game_state.match_id = "skill-reclick-zhuoshi"
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.phase_index = 3
	var local_player: PlayerState = PlayerState.new(0, "本地玩家")
	local_player.character_id = "danheng_yinyue"
	local_player.identity = "leader"
	local_player.identity_revealed = true
	local_player.max_hp = 4
	local_player.hp = 4
	# 三张基本牌费用；第一段与第二段各需要一张，第三段费用请求才具备候选。
	var cost_first: CardInstance = CardInstance.new("sha", "spade", 7)
	var cost_second: CardInstance = CardInstance.new("shan", "heart", 3)
	var cost_third: CardInstance = CardInstance.new("sha", "club", 9)
	for cost_card: CardInstance in [cost_first, cost_second, cost_third]:
		cost_card.zone = "hand"
		cost_card.owner_id = 0
		local_player.hand.append(cost_card)
	# 目标两张手牌；第二段“弃置其一张牌”需要目标侧仍有候选才会建立费用请求。
	var target_player: PlayerState = PlayerState.new(1, "目标玩家")
	target_player.character_id = "xier"
	target_player.identity = "rebel"
	target_player.identity_revealed = true
	var victim_first: CardInstance = CardInstance.new("shan", "diamond", 11)
	var victim_second: CardInstance = CardInstance.new("sha", "heart", 5)
	for victim_card: CardInstance in [victim_first, victim_second]:
		victim_card.zone = "hand"
		victim_card.owner_id = 1
		target_player.hand.append(victim_card)
	game_state.players.append(local_player)
	game_state.players.append(target_player)
	match_controller.state = game_state
	match_controller.card_rules = CardRuleService.new(game_state, match_controller)
	match_controller.effect_resolver = CardEffectResolver.new(match_controller, game_state)
	match_controller.card_movement = CardMovementService.new(game_state)
	match_controller.trigger_manager = TriggerManager.new()
	match_controller.timing_service = RuleTimingService.new(match_controller.event_bus, match_controller.trigger_manager, game_state)
	# 【濯世】与【伏辰】独立运行时实例；与正式开局相同地绑定、安装并登记到玩家技能表。
	# 两者都必须安装：快照的 installed_skill_ids 会裁掉未安装的技能按钮。
	var zhuoshi: SkillDefinition = GameDatabase.create_skill("zhuoshi")
	if zhuoshi == null:
		return _fail_bool("zhuoshi_missing")
	var fuchen: SkillDefinition = GameDatabase.create_skill("fuchen")
	if fuchen == null:
		return _fail_bool("fuchen_missing")
	fuchen.bind(match_controller, 0)
	fuchen.install()
	zhuoshi.bind(match_controller, 0)
	zhuoshi.install()
	match_controller.skill_instances_by_player = {0:{"fuchen":fuchen, "zhuoshi":zhuoshi}}
	match_controller.call("_begin_play_choice", 0)
	match_controller.call("_emit_state")
	await get_tree().process_frame
	# 【伏辰】是 ui_enabled=false 的完整锁定技：按钮恒禁用，点击不产生任何动作。
	var fuchen_button: SkillButtonView = (main_instance.get("_skill_views") as Dictionary).get("fuchen") as SkillButtonView
	if fuchen_button == null or not fuchen_button.disabled:
		return _fail_bool("fuchen_button_should_be_disabled")
	# 第一段：点击【濯世】按钮进入“弃一张基本牌并选择一名其他角色”。
	main_instance.call("_on_skill_requested", "zhuoshi")
	await get_tree().process_frame
	if str(_inline_context(main_instance).get("kind", "")) != "zhuoshi_cost_and_target":
		return _fail_bool("zhuoshi_step1_missing")
	if not _submit_choice(match_controller, [cost_first.uid], [1], true):
		return _fail_bool("zhuoshi_step1_submit")
	await get_tree().process_frame
	# 第二段第一步：弃置目标一张手牌（必选，请求本身不可取消）。
	if not _submit_choice(match_controller, [victim_first.uid], [], true):
		return _fail_bool("zhuoshi_step2_hand_submit")
	await get_tree().process_frame
	# 第二段费用询问：可取消；此刻技能按钮必须禁用且仍为选中态。
	var second_cost_request_id: int = _inline_request_id(main_instance)
	if str(_inline_context(main_instance).get("kind", "")) != "zhuoshi_second_cost":
		return _fail_bool("zhuoshi_second_cost_missing")
	var zhuoshi_button: SkillButtonView = (main_instance.get("_skill_views") as Dictionary).get("zhuoshi") as SkillButtonView
	if zhuoshi_button == null or not zhuoshi_button.disabled or not zhuoshi_button.is_skill_selected:
		return _fail_bool("zhuoshi_release_button_not_locked")
	# 再次点击技能按钮：必须仍停留在第二段费用询问，不得跳到第三段。
	main_instance.call("_on_skill_requested", "zhuoshi")
	await get_tree().process_frame
	if str(_inline_context(main_instance).get("kind", "")) != "zhuoshi_second_cost" or _inline_request_id(main_instance) != second_cost_request_id or not match_controller.has_pending_card_choice():
		return _fail_bool("zhuoshi_reclick_skipped_stage")
	# 持有者仍持有第二、三张费用牌，目标仍只剩未指定的第二张牌：点击没有支付任何费用。
	if local_player.hand.size() != 2 or local_player.find_hand_card(cost_second.uid) == null or local_player.find_hand_card(cost_third.uid) == null:
		return _fail_bool("zhuoshi_reclick_consumed_cost")
	if target_player.find_hand_card(victim_second.uid) == null:
		return _fail_bool("zhuoshi_reclick_consumed_target_card")
	# 取消出口仍可用：操作区“取消”按钮保持可见且可点。
	var cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	if cancel_button == null or not cancel_button.visible or cancel_button.disabled:
		return _fail_bool("zhuoshi_cancel_button_unavailable")
	# 用标准取消响应放弃第二段；按原文应进入第三段费用询问，证明流程本身未被本次改动破坏。
	if not _submit_choice(match_controller, [], [], false):
		return _fail_bool("zhuoshi_second_cost_cancel_submit")
	await get_tree().process_frame
	if str(_inline_context(main_instance).get("kind", "")) != "zhuoshi_third_cost":
		return _fail_bool("zhuoshi_third_cost_missing")
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
