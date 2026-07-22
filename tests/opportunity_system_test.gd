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
	# 全部机缘卡目录；当前设计共45张，任何遗漏都会改变三选一内容范围。
	var cards: Array[Dictionary] = _controller.opportunity_system.get_card_catalog()
	if cards.size() != 45:
		return _fail("catalog_count %d" % cards.size())
	# 关键原文卡；重复“获得获得”属于主公钦定正文，测试确保实现不会擅自润色。
	var preserved_card: Dictionary = OpportunityCatalog.get_card("red_gain_sha_zaixian")
	if str(preserved_card.get("description", "")) != "从牌堆或弃牌堆中获得三张【杀】并获得获得技能“再现”":
		return _fail("preserved_description")
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
	get_tree().paused = false
	card_view.queue_free()
	await get_tree().process_frame
	return true


## 校验候选只向本人公开、每人三张不重复，并且参与者顺序从当前角色起逆时针排列。
func _test_private_choice_and_counterclockwise_order() -> bool:
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
		if chooser_options.is_empty() or not _controller.opportunity_system.submit_choice(chooser_id, str((chooser_options[0] as Dictionary).get("id", ""))):
			return _fail("submit_choice player=%d" % chooser_id)
	if str(_controller.state.opportunity_state.get("stage", "")) != "resolving":
		return _fail("all_choices_not_resolving")
	_controller.opportunity_system.shutdown()
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
	await get_tree().process_frame
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
	print("OPPORTUNITY_SYSTEM_PASS cards=45 private=true reverse=true seat_swap=true limits=true hover=true")
	get_tree().quit(0)
