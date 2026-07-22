extends Node

## 机缘系统专项测试：校验卡池、品质权重、私有三选一、逆时针顺序、座位交换、手牌上限与技能次数。

## 正式主场景；测试复用真实MatchController、暂停服务、AI与UI绑定，避免构造缺失依赖的替代控制器。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 正式机缘卡场景；悬停测试直接复用玩家实际看到的牌面与透明输入按钮。
const OPPORTUNITY_CARD_SCENE: PackedScene = preload("res://scenes/components/opportunity_card.tscn")

## 本次测试主场景实例；完成后显式释放，避免跨测试保留暂停令牌或全局信号连接。
var _main_instance: Control

## 本次测试权威控制器；所有状态修改均通过正式公开接口执行。
var _controller: MatchController


## 运行全部断言；测试节点保持ALWAYS，使机缘选择暂停SceneTree时仍能继续提交模拟玩家选择。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main_instance = MAIN_SCENE.instantiate() as Control
	add_child(_main_instance)
	await get_tree().process_frame
	_controller = _main_instance.get_node("MatchController") as MatchController
	_setup_test_state()
	if not _test_catalog_and_weights():
		return
	if not await _test_opportunity_card_hover():
		return
	if not _test_private_choice_and_counterclockwise_order():
		return
	if not await _test_target_effect_resolution_flow():
		return
	if not await _test_new_effect_resolution_flow():
		return
	if not _test_new_opportunity_mechanisms():
		return
	if not _test_seat_swap_changes_next_player():
		return
	if not _test_hand_limit_bonus():
		return
	if not _test_acquired_skill_limits():
		return
	_finish_success()


## 建立四名在场角色的最小权威状态；技能与机缘组件继续使用主场景中真实运行时服务。
func _setup_test_state() -> void:
	# 测试对局状态；固定模式、轮数与当前角色便于验证逆时针顺序和技能回合次数。
	var state: GameState = GameState.new()
	state.match_id = "opportunity-test"
	state.match_mode = IdentityRules.MODE_OPPORTUNITY_BRAWL
	state.current_phase = "start"
	state.current_player_id = 0
	state.round_number = 1
	state.turn_number = 1
	for player_id: int in range(4):
		# 测试角色；身份交替设置，保证AI友敌查询存在稳定关系。
		var player: PlayerState = PlayerState.new(player_id, "玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("loyalist" if player_id == 2 else "rebel")
		player.identity_revealed = player_id == 0
		player.character_id = ""
		player.character_revealed = true
		state.players.append(player)
	_controller.state = state
	_controller.card_rules = CardRuleService.new(state, _controller)
	_controller.effect_resolver = CardEffectResolver.new(_controller, state)
	_controller.skill_instances_by_player = {0:{}, 1:{}, 2:{}, 3:{}}
	# 固定随机源；候选内容可复现，但测试只依赖数量、合法ID与隐私裁剪。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260722
	_controller.opportunity_system.configure(_controller, state, rng, true)


## 校验五档权重、红色补全值与全部设计卡正文均已登记。
func _test_catalog_and_weights() -> bool:
	# 模式规则；机缘大乱斗必须独立保留稳定ID并支持身份模式相同的2至10人范围。
	var identity_rules: IdentityRules = IdentityRules.new()
	if identity_rules.normalize_mode(IdentityRules.MODE_OPPORTUNITY_BRAWL) != IdentityRules.MODE_OPPORTUNITY_BRAWL or not identity_rules.supports_player_count(IdentityRules.MODE_OPPORTUNITY_BRAWL, 2) or not identity_rules.supports_player_count(IdentityRules.MODE_OPPORTUNITY_BRAWL, 10) or identity_rules.supports_player_count(IdentityRules.MODE_OPPORTUNITY_BRAWL, 11):
		return _fail("mode_support")
	# 当前权重快照；顺序由静态品质表定义，字典仅按稳定键断言。
	var weights: Dictionary = _controller.opportunity_system.get_quality_weights()
	if weights != {"green":100, "blue":80, "purple":60, "orange":30, "red":10}:
		return _fail("quality_weights %s" % str(weights))
	# 全部机缘卡目录；原45张加本批17张共62张，任何遗漏都会改变三选一内容范围。
	var cards: Array[Dictionary] = _controller.opportunity_system.get_card_catalog()
	if cards.size() != 62:
		return _fail("catalog_count %d" % cards.size())
	# 关键原文卡；重复“获得获得”属于主公钦定正文，测试确保实现不会擅自润色。
	var preserved_card: Dictionary = OpportunityCatalog.get_card("red_gain_sha_zaixian")
	if str(preserved_card.get("description", "")) != "从牌堆或弃牌堆中获得三张【杀】并获得获得技能“再现”":
		return _fail("preserved_description")
	# 本批新增卡原文；逐项精确校验，防止自动补标点或改写主公定义。
	var new_descriptions: Dictionary = {
		"green_discard_one_each":"弃置任意名角色区域内各一张牌",
		"green_virtual_nanman":"视为使用一张【南蛮入侵】",
		"green_virtual_wanjian":"视为使用一张【万箭齐发】",
		"green_discard_draw":"弃置区域内任意张牌并摸等量的牌",
		"green_swap_equipment":"令两名角色交换装备区内的所有牌",
		"green_discard_half_all":"令一名角色弃置X张牌（X为其所有牌数的一半，向上取整）",
		"blue_gain_wuxie_two":"从牌堆或弃牌堆中获得两张【无懈可击】",
		"blue_swap_hands":"令两名角色交换所有手牌",
		"blue_lose_half_hp":"令一名角色失去X点体力（X为其当前体力值的一半，向上取整）",
		"purple_gain_distinct_delayed_three":"从牌堆或弃牌堆中获得三张牌名不同的延时锦囊牌",
		"purple_remove_until_round_end":"令一名角色离场直到本轮结束",
		"orange_reduce_half_max_hp":"令一名角色减少X点体力上限（X为其体力上限的一半，向上取整）",
		"orange_damage_current_hp":"对一名角色造成X点伤害（X为其当前体力值）",
		"orange_swap_characters":"令两名角色交换武将牌",
		"red_all_hand_view_as_wuzhong":"所有手牌视为【无中生有】直到离开你的手牌区",
		"red_gain_all_equipment":"获得牌堆与弃牌堆与场上的所有装备牌",
		"red_gain_random_three_each":"获得每名角色区域内的随机三张牌",
	}
	for card_id_variant: Variant in new_descriptions.keys():
		# 当前新增卡ID与精确原文；目录缺失同样会得到空字符串并失败。
		var card_id: String = str(card_id_variant)
		if str(OpportunityCatalog.get_card(card_id).get("description", "")) != str(new_descriptions[card_id]):
			return _fail("new_description_%s" % card_id)
	return true


## 校验机缘卡在暂停选择期间复用正式卡牌的1.06缩放、0.12秒补间、提亮边框和顶层绘制反馈。
func _test_opportunity_card_hover() -> bool:
	# 测试机缘卡；使用绿色摸牌定义，视觉断言不依赖随机候选内容。
	var card_view: OpportunityCardView = OPPORTUNITY_CARD_SCENE.instantiate() as OpportunityCardView
	add_child(card_view)
	card_view.configure(OpportunityCatalog.get_card("green_draw_two"), true)
	await get_tree().process_frame
	# 机缘卡透明输入按钮；正式悬停信号由该覆盖按钮发出。
	var input_button: Button = card_view.get_node("%InputButton") as Button
	# 普通状态样式；用于确认悬停后背景确实提亮而不是只缩放节点。
	var normal_style: StyleBoxFlat = card_view.get_theme_stylebox("panel") as StyleBoxFlat
	# 普通状态背景色；保存独立值避免后续样式覆盖影响比较。
	var normal_background_color: Color = normal_style.bg_color if normal_style != null else Color.BLACK
	get_tree().paused = true
	input_button.mouse_entered.emit()
	await get_tree().create_timer(card_view.hover_animation_seconds + 0.04, true).timeout
	# 悬停状态样式；边框宽度应从4增加到5，背景按正式卡牌默认比例提亮。
	var hovered_style: StyleBoxFlat = card_view.get_theme_stylebox("panel") as StyleBoxFlat
	if not card_view.scale.is_equal_approx(Vector2.ONE * 1.06) or card_view.z_index != OpportunityCardView.HOVER_Z_INDEX or hovered_style == null or hovered_style.border_width_left != 5 or hovered_style.bg_color == normal_background_color or not card_view.pivot_offset.is_equal_approx(card_view.card_size * 0.5):
		get_tree().paused = false
		card_view.queue_free()
		return _fail("opportunity_card_hover scale=%s z=%d border=%s" % [str(card_view.scale), card_view.z_index, str(hovered_style.border_width_left if hovered_style != null else -1)])
	input_button.mouse_exited.emit()
	await get_tree().create_timer(card_view.hover_animation_seconds + 0.04, true).timeout
	if not card_view.scale.is_equal_approx(Vector2.ONE) or card_view.z_index != 0:
		get_tree().paused = false
		card_view.queue_free()
		return _fail("opportunity_card_hover_restore scale=%s z=%d" % [str(card_view.scale), card_view.z_index])
	input_button.mouse_entered.emit()
	await get_tree().create_timer(0.04, true).timeout
	card_view.set_interactive(false)
	await get_tree().create_timer(card_view.hover_animation_seconds + 0.04, true).timeout
	if not input_button.disabled or not card_view.scale.is_equal_approx(Vector2.ONE) or card_view.z_index != 0:
		get_tree().paused = false
		card_view.queue_free()
		return _fail("opportunity_card_hover_disable")
	# 技能机缘悬停资料；只有定义包含skill_id时才应发出对应技能名称与完整说明。
	var skill_information: Array[Dictionary] = []
	var skill_information_dismissed: Array[bool] = []
	card_view.information_requested.connect(func(information: Dictionary, _anchor_rect: Rect2) -> void: skill_information.append(information.duplicate(true)))
	card_view.information_dismissed.connect(func() -> void: skill_information_dismissed.append(true))
	card_view.configure(OpportunityCatalog.get_card("blue_skill_jiqiao"), true)
	input_button.mouse_entered.emit()
	if skill_information.is_empty() or str(skill_information[0].get("title", "")) != "【机巧】" or not str(skill_information[0].get("description", "")).contains(str(GameDatabase.get_skill("jiqiao").get("description", ""))):
		get_tree().paused = false
		card_view.queue_free()
		return _fail("opportunity_skill_hover=%s" % [skill_information])
	input_button.mouse_exited.emit()
	if skill_information_dismissed.is_empty():
		get_tree().paused = false
		card_view.queue_free()
		return _fail("opportunity_skill_hover_dismiss")
	get_tree().paused = false
	card_view.queue_free()
	await get_tree().process_frame
	return true


## 校验候选只向本人公开、每人三张不重复，并且参与者顺序从当前角色起逆时针排列。
func _test_private_choice_and_counterclockwise_order() -> bool:
	# 四号角色处于离场状态；机缘属于模式级全体选择，仍必须参与候选、提交与获得历史。
	_controller.state.get_player(3).out_of_game = true
	if not _controller.opportunity_system.force_trigger(0, "manual", {}):
		return _fail("force_trigger")
	# 权威参与顺序；四人座次0、1、2、3的逆时针结果应为0、3、2、1。
	var participant_ids: Array = _controller.state.opportunity_state.get("participant_ids", []) as Array
	if participant_ids != [0, 3, 2, 1]:
		return _fail("counterclockwise_order %s" % str(participant_ids))
	# 权威全体候选；每名角色固定三张且同一角色内ID不重复。
	var options_by_player: Dictionary = _controller.state.opportunity_state.get("options_by_player", {}) as Dictionary
	for player_id: int in range(4):
		# 当前角色三张候选；权威端使用字符串键保存，兼容网络JSON字典。
		var options: Array = options_by_player.get(str(player_id), []) as Array
		if options.size() != 3:
			return _fail("option_count player=%d size=%d" % [player_id, options.size()])
		# 当前候选ID集合；重复ID表示无放回抽取失效。
		var option_ids: Array[String] = []
		for option_variant: Variant in options:
			var option_id: String = str((option_variant as Dictionary).get("id", ""))
			if option_id.is_empty() or option_ids.has(option_id):
				return _fail("duplicate_option player=%d" % player_id)
			option_ids.append(option_id)
	# 一号观察者快照；只能包含自己的三张候选，不能读取其他角色卡面或权威已选内容。
	var viewer_snapshot: Dictionary = _controller.state.to_dict(0, false)
	var viewer_opportunity: Dictionary = viewer_snapshot.get("opportunity_state", {}) as Dictionary
	var viewer_options_by_player: Dictionary = viewer_opportunity.get("options_by_player", {}) as Dictionary
	if viewer_options_by_player.size() != 1 or not viewer_options_by_player.has("0") or viewer_opportunity.has("selected_cards_by_player"):
		return _fail("private_options %s" % str(viewer_opportunity))
	# 依次模拟当前选择者提交其第一张合法候选；最后一次提交后状态进入resolving，但效果尚未在延迟帧执行。
	while str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
		var chooser_id: int = int(_controller.state.opportunity_state.get("current_chooser_id", -1))
		var chooser_options: Array = (options_by_player.get(str(chooser_id), []) as Array)
		# 统一机缘动作；离场角色也必须通过MatchController提交入口，而不是只在组件内部绕过动作状态校验。
		var choice_action: PlayerAction = PlayerAction.new("choose_opportunity", chooser_id)
		choice_action.payload = {"card_id":str((chooser_options[0] as Dictionary).get("id", ""))} if not chooser_options.is_empty() else {}
		if chooser_options.is_empty() or not _controller.submit_action(choice_action):
			return _fail("submit_choice player=%d" % chooser_id)
	if str(_controller.state.opportunity_state.get("stage", "")) != "resolving":
		return _fail("all_choices_not_resolving")
	if _controller.state.get_player(3).acquired_opportunity_ids.size() != 1:
		return _fail("out_of_game_opportunity_history=%s" % [_controller.state.get_player(3).acquired_opportunity_ids])
	_controller.opportunity_system.shutdown()
	_controller.state.get_player(3).out_of_game = false
	_controller.state.current_phase = "start"
	# 重新启用同一局组件；shutdown用于中断随机效果，下一项测试需要新的固定候选流程。
	var next_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	next_rng.seed = 20260723
	_controller.opportunity_system.configure(_controller, _controller.state, next_rng, true)
	return true


## 使用固定候选跑通“全体选完→当前角色选目标→交换座位→其余效果逆时针继续”的真实异步流程。
func _test_target_effect_resolution_flow() -> bool:
	if not _controller.opportunity_system.force_trigger(0, "manual", {}):
		return _fail("target_flow_force_trigger")
	# 固定候选模板；每名角色仍保留三张不同合法卡，第一张是本测试要求提交的效果。
	var fallback_blue: Dictionary = OpportunityCatalog.get_card("blue_draw_three")
	# 第二张安全候选；不会被选择，只用于保持正式三选一结构。
	var fallback_purple: Dictionary = OpportunityCatalog.get_card("purple_draw_five")
	# 各角色指定选择：当前角色交换座位，随后三名角色各获得1点额外手牌上限。
	var selected_card_ids: Dictionary = {0:"orange_swap_seat", 3:"green_hand_limit_one", 2:"green_hand_limit_one", 1:"green_hand_limit_one"}
	# 权威候选映射；测试在提交前替换随机候选，但所有卡仍从静态目录读取完整定义。
	var options_by_player: Dictionary = {}
	for participant_id_variant: Variant in _controller.state.opportunity_state.get("participant_ids", []) as Array:
		var participant_id: int = int(participant_id_variant)
		options_by_player[str(participant_id)] = [OpportunityCatalog.get_card(str(selected_card_ids.get(participant_id, "green_hand_limit_one"))), fallback_blue.duplicate(true), fallback_purple.duplicate(true)]
	_controller.state.opportunity_state["options_by_player"] = options_by_player
	# 按当前选择者顺序提交指定第一张机缘；效果必须继续等到最后一人提交后才开始。
	while str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
		var chooser_id: int = int(_controller.state.opportunity_state.get("current_chooser_id", -1))
		if not _controller.opportunity_system.submit_choice(chooser_id, str(selected_card_ids.get(chooser_id, ""))):
			return _fail("target_flow_submit player=%d" % chooser_id)
	for _wait_request_frame: int in range(12):
		if not _controller.state.current_choice_request.is_empty():
			break
		await get_tree().process_frame
	# 当前角色的交换座位机缘应先创建单目标选择；其他三名角色的手牌上限此时尚未生效。
	var choice_request: Dictionary = _controller.state.current_choice_request
	if str(choice_request.get("choice_type", "")) != "target" or int(choice_request.get("actor_id", -1)) != 0:
		return _fail("target_flow_request %s" % str(choice_request))
	for untouched_player_id: int in [1, 2, 3]:
		if _controller.state.get_player(untouched_player_id).hand_limit_bonus != 0:
			return _fail("effect_started_before_target")
	# 选择原三号位角色2交换；通过统一choose_cards动作验证控制器能把opportunity上下文路由回独立解析器。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(choice_request.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":[2], "confirmed":true}
	if not _controller.submit_action(action):
		return _fail("target_flow_choice_rejected")
	# 等待其余三张同步手牌上限机缘依逆时针顺序完成并清空机缘状态。
	for _wait_frame: int in range(12):
		if _controller.state.opportunity_state.is_empty():
			break
		await get_tree().process_frame
	if not _controller.state.opportunity_state.is_empty():
		return _fail("target_flow_not_finished")
	# 座次数组与三名后续角色的效果结果；当前角色自身没有选择手牌上限卡。
	var seat_ids: Array[int] = []
	for player: PlayerState in _controller.state.players:
		seat_ids.append(player.player_id)
	if seat_ids != [2, 1, 0, 3] or _controller.state.get_player(1).hand_limit_bonus != 1 or _controller.state.get_player(2).hand_limit_bonus != 1 or _controller.state.get_player(3).hand_limit_bonus != 1 or _controller.state.get_player(0).hand_limit_bonus != 0:
		return _fail("target_flow_result seats=%s" % str(seat_ids))
	# 恢复座次与手牌上限，后续独立测试从标准四人状态开始。
	_controller.swap_player_seats(0, 2, "target_flow_restore")
	for reset_player_id: int in [1, 2, 3]:
		_controller.state.get_player(reset_player_id).hand_limit_bonus = 0
	_controller.state.current_phase = "start"
	return true


## 通过完整机缘选择流程校验“两名角色交换所有手牌”的双目标请求、UID锁定与逆时针后续恢复。
func _test_new_effect_resolution_flow() -> bool:
	# 双方原始手牌；交换结果按稳定UID确认，避免同名牌造成误判。
	var first_original_card: CardInstance = _add_test_card("sha", "hand", 0)
	var second_original_card_a: CardInstance = _add_test_card("shan", "hand", 1)
	var second_original_card_b: CardInstance = _add_test_card("tao", "hand", 1)
	if not _controller.opportunity_system.force_trigger(0, "manual", {}):
		return _fail("new_effect_force_trigger")
	# 其余角色使用无目标安全机缘，确保交换手牌完成后机缘队列能够继续并正常清空。
	var selected_card_ids: Dictionary = {0:"blue_swap_hands", 3:"green_hand_limit_one", 2:"green_hand_limit_one", 1:"green_hand_limit_one"}
	var options_by_player: Dictionary = {}
	for participant_id_variant: Variant in _controller.state.opportunity_state.get("participant_ids", []) as Array:
		var participant_id: int = int(participant_id_variant)
		options_by_player[str(participant_id)] = [OpportunityCatalog.get_card(str(selected_card_ids.get(participant_id, "green_hand_limit_one"))), OpportunityCatalog.get_card("blue_draw_three"), OpportunityCatalog.get_card("purple_draw_five")]
	_controller.state.opportunity_state["options_by_player"] = options_by_player
	while str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
		var chooser_id: int = int(_controller.state.opportunity_state.get("current_chooser_id", -1))
		if not _controller.opportunity_system.submit_choice(chooser_id, str(selected_card_ids.get(chooser_id, ""))):
			return _fail("new_effect_submit_%d" % chooser_id)
	for _wait_request_frame: int in range(12):
		if not _controller.state.current_choice_request.is_empty():
			break
		await get_tree().process_frame
	# 双目标请求；允许选择机缘拥有者本人和另一名角色。
	var choice_request: Dictionary = _controller.state.current_choice_request
	if str(choice_request.get("choice_type", "")) != "target" or int(choice_request.get("min_count", -1)) != 2 or int(choice_request.get("max_count", -1)) != 2:
		return _fail("new_effect_target_request=%s" % [choice_request])
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(choice_request.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":[0, 1], "confirmed":true}
	if not _controller.submit_action(action):
		return _fail("new_effect_target_submit")
	for _wait_frame: int in range(20):
		if _controller.state.opportunity_state.is_empty():
			break
		await get_tree().process_frame
	if not _controller.state.opportunity_state.is_empty():
		return _fail("new_effect_not_finished")
	# 一号角色得到二号原两张手牌，二号角色得到一号原一张手牌。
	if _controller.state.get_player(0).find_hand_card(second_original_card_a.uid) == null or _controller.state.get_player(0).find_hand_card(second_original_card_b.uid) == null or _controller.state.get_player(1).find_hand_card(first_original_card.uid) == null:
		return _fail("new_effect_hand_swap_result")
	# 清理测试手牌和其余角色手牌上限，后续公共机制测试保持独立初始条件。
	_controller.discard_all_hand_cards(0, -1, "test_cleanup")
	_controller.discard_all_hand_cards(1, -1, "test_cleanup")
	for reset_player_id: int in [1, 2, 3]:
		_controller.state.get_player(reset_player_id).hand_limit_bonus = 0
	_controller.state.current_phase = "start"
	# 再以完整机缘流程验证无实体【南蛮入侵】进入群体牌结算，三名其他角色各受到1点普通伤害。
	if not _controller.opportunity_system.force_trigger(0, "manual", {}):
		return _fail("virtual_aoe_force_trigger")
	var virtual_selected_card_ids: Dictionary = {0:"green_virtual_nanman", 3:"green_hand_limit_one", 2:"green_hand_limit_one", 1:"green_hand_limit_one"}
	var virtual_options_by_player: Dictionary = {}
	for participant_id_variant: Variant in _controller.state.opportunity_state.get("participant_ids", []) as Array:
		# 当前参与者候选；第一项固定为本轮需要结算的卡，其余保持合法三选一结构。
		var participant_id: int = int(participant_id_variant)
		virtual_options_by_player[str(participant_id)] = [OpportunityCatalog.get_card(str(virtual_selected_card_ids.get(participant_id, "green_hand_limit_one"))), OpportunityCatalog.get_card("blue_draw_three"), OpportunityCatalog.get_card("purple_draw_five")]
	_controller.state.opportunity_state["options_by_player"] = virtual_options_by_player
	while str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
		var chooser_id: int = int(_controller.state.opportunity_state.get("current_chooser_id", -1))
		if not _controller.opportunity_system.submit_choice(chooser_id, str(virtual_selected_card_ids.get(chooser_id, ""))):
			return _fail("virtual_aoe_submit_%d" % chooser_id)
	for _wait_virtual_frame: int in range(40):
		if _controller.state.opportunity_state.is_empty():
			break
		# 测试状态没有为其他角色注册正式AI；遇到群体锦囊响应请求时按标准动作明确放弃。
		var response_request: Dictionary = _controller.state.current_choice_request
		if str(response_request.get("choice_type", "")) == "respond":
			var pass_action: PlayerAction = PlayerAction.new("choose_cards", int(response_request.get("actor_id", -1)))
			pass_action.payload = {"request_id":int(response_request.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
			_controller.submit_action(pass_action)
		await get_tree().create_timer(0.05).timeout
	if not _controller.state.opportunity_state.is_empty():
		return _fail("virtual_aoe_not_finished")
	for damaged_player_id: int in [1, 2, 3]:
		if _controller.state.get_player(damaged_player_id).hp != 3:
			return _fail("virtual_aoe_damage_%d=%d" % [damaged_player_id, _controller.state.get_player(damaged_player_id).hp])
		_controller.state.get_player(damaged_player_id).hp = 4
		_controller.state.get_player(damaged_player_id).hand_limit_bonus = 0
	_controller.state.current_phase = "start"
	return true


## 校验武将牌交换、轮末离场、手牌视为、不同名延时锦囊检索与装备双向交换公共端口。
func _test_new_opportunity_mechanisms() -> bool:
	# 双方测试武将；三月七与丹恒拥有不同体力上限和固有技能，便于确认交换边界。
	var first_player: PlayerState = _controller.state.get_player(0)
	var second_player: PlayerState = _controller.state.get_player(1)
	first_player.character_id = "march_7th"
	first_player.max_hp = 3
	first_player.hp = 3
	second_player.character_id = "dan_heng"
	second_player.max_hp = 4
	second_player.hp = 4
	_controller._reinstall_character_skills_for_player(first_player)
	_controller._reinstall_character_skills_for_player(second_player)
	# 局内获得技能；交换武将牌后必须仍归原角色且保留实例。
	if not _controller.grant_acquired_skill(0, "huanyang", 3, 0, "test"):
		return _fail("character_swap_grant_runtime")
	if not _controller.swap_player_character_cards(0, 1, "test"):
		return _fail("character_swap_rejected")
	# 新旧固有技能ID；用于确认只移动武将牌技能，不移动局内获得技能。
	var march_skill_ids: Array = GameDatabase.get_character("march_7th").get("skills", []) as Array
	var dan_heng_skill_ids: Array = GameDatabase.get_character("dan_heng").get("skills", []) as Array
	var first_skills: Dictionary = _controller.skill_instances_by_player.get(0, {}) as Dictionary
	var second_skills: Dictionary = _controller.skill_instances_by_player.get(1, {}) as Dictionary
	if first_player.character_id != "dan_heng" or first_player.max_hp != 4 or second_player.character_id != "march_7th" or second_player.max_hp != 3 or not first_skills.has("huanyang"):
		return _fail("character_swap_state")
	for skill_id_variant: Variant in dan_heng_skill_ids:
		if not first_skills.has(str(skill_id_variant)):
			return _fail("character_swap_first_native_%s" % str(skill_id_variant))
	for skill_id_variant: Variant in march_skill_ids:
		if not second_skills.has(str(skill_id_variant)):
			return _fail("character_swap_second_native_%s" % str(skill_id_variant))
	# 换回原武将并移除测试获得技能，避免影响后续机缘技能次数断言。
	_controller.swap_player_character_cards(0, 1, "test_restore")
	_controller.remove_acquired_skill(0, "huanyang")
	first_player.max_hp = 4
	first_player.hp = 4
	second_player.max_hp = 4
	second_player.hp = 4
	# 当前手牌实体；视为无中生有后保留原定义，离开手牌区时自动恢复为杀。
	var view_as_card: CardInstance = _add_test_card("sha", "hand", 0)
	if _controller.set_all_hand_cards_view_as(0, "wuzhong", "test") != 1 or view_as_card.definition_id != "wuzhong" or view_as_card.hand_view_as_original_definition_id != "sha":
		return _fail("view_all_hand_as")
	if not _controller.discard_card_from_hand(0, view_as_card.uid) or view_as_card.definition_id != "sha" or view_as_card.has_hand_view_as():
		return _fail("view_as_leave_hand")
	# 三种不同延时锦囊与一张重复乐不思蜀；检索结果必须只取三个不同稳定定义ID。
	_add_test_card("lebu", "draw_pile")
	_add_test_card("bingliang", "draw_pile")
	_add_test_card("shandian", "discard_pile")
	_add_test_card("lebu", "discard_pile")
	var delayed_uids: Array[int] = _controller.get_distinct_delayed_trick_card_uids(3)
	var delayed_definition_ids: Dictionary = {}
	for delayed_uid: int in delayed_uids:
		# 当前延时锦囊位置；测试通过公开UID获得端口读取并移动到手牌后确认定义。
		if not _controller.gain_card_to_hand_by_uid(0, delayed_uid, "test"):
			return _fail("distinct_delayed_gain")
		var gained_card: CardInstance = first_player.find_hand_card(delayed_uid)
		delayed_definition_ids[gained_card.definition_id] = true
	if delayed_uids.size() != 3 or delayed_definition_ids.size() != 3:
		return _fail("distinct_delayed=%s" % [delayed_definition_ids.keys()])
	# 两张不同槽位装备；先统一移入处理区再装入对方，不能因同槽覆盖丢失实体。
	var weapon_card: CardInstance = _add_test_card("qinggang", "equipment", 0, "weapon")
	var armor_card: CardInstance = _add_test_card("baiyin", "equipment", 1, "armor")
	_controller._install_card_runtime(weapon_card, 0)
	_controller._install_card_runtime(armor_card, 1)
	var equipment_entries: Array[Dictionary] = _controller.get_equipment_swap_entries(0, 1)
	for entry: Dictionary in equipment_entries:
		if not _controller.move_equipment_card_to_processing(int(entry.get("source_player_id", -1)), int(entry.get("card_uid", -1)), "test"):
			return _fail("equipment_swap_evacuation")
	for entry: Dictionary in equipment_entries:
		if not _controller.move_processing_card_to_equipment(int(entry.get("target_player_id", -1)), int(entry.get("card_uid", -1)), str(entry.get("slot", "")), "test"):
			return _fail("equipment_swap_install")
	if first_player.get_armor() != armor_card or second_player.get_weapon() != weapon_card:
		return _fail("equipment_swap_result")
	# 限时离场标记；新轮边界恢复后清空标记并重新进入游戏。
	var round_limited_player: PlayerState = _controller.state.get_player(2)
	if not _controller.remove_player_until_round_end(2, "test") or not round_limited_player.out_of_game or round_limited_player.out_of_game_until_round != _controller.state.round_number:
		return _fail("round_limited_remove")
	if _controller._restore_round_limited_out_of_game_players(_controller.state.round_number + 1) != 1 or round_limited_player.out_of_game or round_limited_player.out_of_game_until_round != -1:
		return _fail("round_limited_restore")
	return true


## 向测试状态指定区域加入一张真实实体牌；仅用于公共机制端口的最小权威数据准备。
func _add_test_card(definition_id: String, zone: String, owner_id: int = -1, slot: String = "") -> CardInstance:
	# 测试实体牌；固定黑桃7只为提供完整花色点数，不影响本批机制断言。
	var card: CardInstance = CardInstance.new(definition_id, "spade", 7)
	card.zone = zone
	card.owner_id = owner_id
	if zone == "draw_pile":
		_controller.state.draw_pile.append(card)
	elif zone == "discard_pile":
		_controller.state.discard_pile.append(card)
	elif zone == "hand":
		_controller.state.get_player(owner_id).hand.append(card)
	elif zone == "equipment":
		_controller.state.get_player(owner_id).equipment[slot] = card
	elif zone == "judgment":
		_controller.state.get_player(owner_id).judgment_area.append(card)
	return card


## 校验交换一号与三号位后，当前一号位角色的正常下家变为原四号位角色。
func _test_seat_swap_changes_next_player() -> bool:
	if not _controller.swap_player_seats(0, 2, "test"):
		return _fail("seat_swap_rejected")
	# 交换后座次数组；角色0移动到三号位，角色2移动到一号位。
	var seat_player_ids: Array[int] = []
	for player: PlayerState in _controller.state.players:
		seat_player_ids.append(player.player_id)
	# 当前角色0位于三号位，其顺时针下家应是原四号位角色3，完全匹配主公给出的示例。
	var next_player: PlayerState = _controller.state.get_next_alive_player(0)
	if seat_player_ids != [2, 1, 0, 3] or next_player == null or next_player.player_id != 3:
		return _fail("seat_swap_order seats=%s next=%s" % [str(seat_player_ids), str(next_player.player_id if next_player != null else -1)])
	# 恢复原座次，避免后续技能测试日志使用交换后的座位产生无关差异。
	_controller.swap_player_seats(0, 2, "restore")
	return true


## 校验额外手牌上限与体力基础值累加，连续获得+1与+2后从4变为7。
func _test_hand_limit_bonus() -> bool:
	# 测试角色；默认体力与上限均为4，额外手牌上限初始0。
	var player: PlayerState = _controller.state.get_player(0)
	if _controller.add_hand_limit_bonus(0, 1, "test") != 1 or _controller.add_hand_limit_bonus(0, 2, "test") != 2 or player.get_hand_limit() != 7:
		return _fail("hand_limit %d" % player.get_hand_limit())
	return true


## 校验每回合三次在新全局回合自动恢复，以及行军第五次成功发动后失去技能。
func _test_acquired_skill_limits() -> bool:
	if not _controller.grant_acquired_skill(0, "huanyang", 3, 0, "test"):
		return _fail("grant_huanyang")
	for _use_index: int in range(3):
		if not _controller.consume_acquired_skill_use(0, "huanyang"):
			return _fail("huanyang_consume")
	if _controller.can_use_acquired_skill(0, "huanyang"):
		return _fail("huanyang_turn_limit")
	_controller.state.turn_number = 2
	if not _controller.can_use_acquired_skill(0, "huanyang"):
		return _fail("huanyang_turn_reset")
	_controller.remove_acquired_skill(0, "huanyang")
	if not _controller.grant_acquired_skill(0, "xingjun", 0, 5, "test"):
		return _fail("grant_xingjun")
	for use_index: int in range(5):
		if not _controller.consume_acquired_skill_use(0, "xingjun"):
			return _fail("xingjun_consume_%d" % use_index)
	if (_controller.skill_instances_by_player.get(0, {}) as Dictionary).has("xingjun") or _controller.state.get_player(0).acquired_skills.has("xingjun"):
		return _fail("xingjun_not_removed")
	return true


## 输出失败原因并退出；返回false便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	_controller.opportunity_system.shutdown()
	print("OPPORTUNITY_SYSTEM_FAIL %s" % reason)
	get_tree().quit(1)
	return false


## 清理主场景并输出成功标记；CI通过进程退出码与固定文本共同确认结果。
func _finish_success() -> void:
	_controller.opportunity_system.shutdown()
	_main_instance.queue_free()
	await get_tree().process_frame
	print("OPPORTUNITY_SYSTEM_PASS cards=62 private=true reverse=true seat_swap=true character_swap=true limits=true hover=true")
	get_tree().quit(0)
