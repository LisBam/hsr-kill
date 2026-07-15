extends Node

## 本轮玩法回归测试。验证逐目标无懈、群体锦囊续算、濒死桃酒同窗、朱雀羽扇选择和木牛重铸边界。

## 测试使用的权威控制器；按正式依赖结构装配，所有选择仍通过标准 PlayerAction 提交。
var _controller: MatchController

## 当前测试场景名称；选择信号根据该稳定字符串生成对应玩家操作。
var _scenario: String = ""

## 当前场景收到的无懈可击请求数量；用于确认一张无懈只作用于当前目标。
var _wuxie_request_count: int = 0

## 当前场景收到的群体锦囊响应请求数量；被无懈抵消的目标不应再收到【杀】响应。
var _aoe_request_count: int = 0

## 当前场景收到的濒死救援请求数量；桃与酒必须位于同一个请求中。
var _dying_request_count: int = 0

## 濒死救援请求是否同时包含测试【桃】和【酒】实体 UID。
var _dying_request_has_both_cards: bool = false

## 当前场景收到的朱雀羽扇发动请求数量；普通【杀】不能在没有询问时自动转火。
var _zhuque_request_count: int = 0

## 当前场景收到的银月枪发动请求数量；回合外黑色牌不能直接自动产生伤害。
var _silver_moon_request_count: int = 0

## 当前场景需要由选择处理器打出的【无懈可击】实体 UID。
var _wuxie_uid: int = -1

## 当前场景需要由濒死者选择的【桃】实体 UID。
var _peach_uid: int = -1

## 当前场景需要由濒死者选择的【酒】实体 UID。
var _wine_uid: int = -1

## 当前场景需要由玩家选择发动的朱雀羽扇实体 UID。
var _zhuque_uid: int = -1

## 当前场景需要由玩家选择发动的银月枪实体 UID。
var _silver_moon_uid: int = -1

## 测试是否已经失败；失败后延迟回调不会继续提交旧请求。
var _failed: bool = false


## 延迟一帧执行测试，确保自动加载卡牌数据和节点依赖已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次运行独立场景；任一断言失败会立即以非0状态结束。
func _run() -> void:
	_create_controller()
	if not await _test_wuxie_per_target_and_aoe_continuation():
		return
	if not await _test_dying_peach_and_wine_share_one_request():
		return
	if not await _test_zhuque_requires_activation_choice():
		return
	if not await _test_silver_moon_requires_activation_choice():
		return
	if not _test_wooden_ox_card_cannot_recast():
		return
	if not _test_ai_delay_range():
		return
	print("GAMEPLAY_REGRESSION_PASS wuxie=%d aoe=%d dying=%d zhuque=%d yinyue=%d" % [_wuxie_request_count, _aoe_request_count, _dying_request_count, _zhuque_request_count, _silver_moon_request_count])
	get_tree().quit(0)


## 创建控制器及其解耦子组件；结构与正式主场景保持一致。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；伤害、回复和卡牌事件通过该节点分发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；本测试不注册 AI，使所有异步请求由测试模拟玩家提交。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；保留与正式控制器一致的选择来源协议。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.card_choice_requested.connect(_on_card_choice_requested)


## 为独立场景创建指定人数的最小权威状态，并重新绑定全部状态型服务。
func _reset_state(player_count: int) -> void:
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "gameplay-regression-%s" % _scenario
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 场景玩家；默认4点体力且存活，身份只用于基础无懈策略但不会替代测试提交。
		var player: PlayerState = PlayerState.new(player_id, "测试玩家%d" % (player_id + 1))
		player.max_hp = 4
		player.hp = 4
		player.identity = "rebel" if player_id > 0 else "lord"
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller._pending_card_choice.clear()
	_controller._resolved_card_choice_uids.clear()
	_controller._negation_resume_results.clear()
	_controller._active_card_resolutions.clear()
	_controller._queued_silver_moon_triggers.clear()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.ai_coordinator._policies.clear()


## 验证南蛮入侵逐目标结算：目标一被一张无懈抵消，目标二仍需响应并在未出杀时受到伤害。
func _test_wuxie_per_target_and_aoe_continuation() -> bool:
	_scenario = "wuxie_aoe"
	_wuxie_request_count = 0
	_aoe_request_count = 0
	_reset_state(3)
	# 目标一持有的无懈可击；选择后应进入弃牌堆且只抵消目标一。
	var wuxie: CardInstance = _add_hand_card(1, "wuxie", "spade", 11)
	_wuxie_uid = wuxie.uid
	# 来源玩家使用的南蛮入侵；完整目标顺序固定为目标一、目标二。
	var nanman: CardInstance = _add_hand_card(0, "nanman", "spade", 7)
	_controller._execute_card_use(0, nanman, [1, 2])
	if not await _wait_until_card_finalized(nanman.uid):
		return _fail("wuxie_aoe_timeout")
	# 目标一体力；被无懈抵消后保持4点。
	var first_target: PlayerState = _controller.state.get_player(1)
	# 目标二体力；没有【杀】响应时受到固定1点普通伤害。
	var second_target: PlayerState = _controller.state.get_player(2)
	if first_target.hp != 4 or second_target.hp != 3:
		return _fail("wuxie_target_hp=%d:%d" % [first_target.hp, second_target.hp])
	if _wuxie_request_count != 1 or _aoe_request_count != 1:
		return _fail("wuxie_aoe_requests=%d:%d" % [_wuxie_request_count, _aoe_request_count])
	if not _controller.state.discard_pile.has(wuxie) or not _controller.state.discard_pile.has(nanman):
		return _fail("wuxie_aoe_discard")
	return true


## 验证濒死者在一个请求中同时选择桃或酒；选择酒后桃保留且角色回复至1点。
func _test_dying_peach_and_wine_share_one_request() -> bool:
	_scenario = "dying"
	_dying_request_count = 0
	_dying_request_has_both_cards = false
	_reset_state(2)
	# 濒死者持有的桃；同窗选择酒后应继续留在手牌区。
	var peach: CardInstance = _add_hand_card(0, "tao", "heart", 3)
	_peach_uid = peach.uid
	# 濒死者持有的酒；测试处理器会在桃酒同窗中明确选择该牌。
	var wine: CardInstance = _add_hand_card(0, "jiu", "spade", 9)
	_wine_uid = wine.uid
	_controller.damage(1, 0, 4, "normal", "sha")
	if not await _wait_until_no_card_choice():
		return _fail("dying_timeout")
	# 濒死者最新状态；酒自救后应存活、退出濒死并具有1点体力。
	var target: PlayerState = _controller.state.get_player(0)
	if _dying_request_count != 1 or not _dying_request_has_both_cards:
		return _fail("dying_request=%d both=%s" % [_dying_request_count, _dying_request_has_both_cards])
	if target.hp != 1 or target.dying or not target.alive:
		return _fail("dying_state=%d:%s:%s" % [target.hp, target.dying, target.alive])
	if target.find_hand_card(peach.uid) == null or target.find_hand_card(wine.uid) != null or not _controller.state.discard_pile.has(wine):
		return _fail("dying_card_zones")
	return true


## 验证普通【杀】装备朱雀羽扇时先创建可取消发动请求，明确发动后才转换为火焰伤害。
func _test_zhuque_requires_activation_choice() -> bool:
	_scenario = "zhuque"
	_zhuque_request_count = 0
	_reset_state(2)
	# 攻击者装备的朱雀羽扇；测试处理器会选择该实体表示发动。
	var zhuque: CardInstance = CardInstance.new("zhuque", "diamond", 1)
	zhuque.zone = "equipment"
	zhuque.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = zhuque
	_zhuque_uid = zhuque.uid
	# 目标装备的藤甲；普通杀会无效，转为火杀后受到1点基础伤害与1点藤甲火伤加成。
	var tengjia: CardInstance = CardInstance.new("tengjia", "club", 2)
	tengjia.zone = "equipment"
	tengjia.owner_id = 1
	_controller.state.get_player(1).equipment["armor"] = tengjia
	# 攻击者使用的普通杀；属性转换必须发生在朱雀羽扇请求确认之后。
	var slash: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	_controller._execute_card_use(0, slash, [1])
	if not await _wait_until_card_finalized(slash.uid):
		return _fail("zhuque_timeout")
	# 目标最新体力；火杀命中藤甲后应从4点降至2点。
	var target: PlayerState = _controller.state.get_player(1)
	if _zhuque_request_count != 1 or target.hp != 2:
		return _fail("zhuque_result=%d:%d" % [_zhuque_request_count, target.hp])
	return true


## 验证银月枪在回合外黑色牌完成原响应后先创建可取消发动请求，确认后才进入目标【闪】响应与伤害。
func _test_silver_moon_requires_activation_choice() -> bool:
	_scenario = "silver_moon"
	_silver_moon_request_count = 0
	_reset_state(3)
	# 一号角色装备的银月枪；当前回合属于0号角色，因此满足回合外触发条件。
	var silver_moon: CardInstance = CardInstance.new("yinyue", "diamond", 12)
	silver_moon.zone = "equipment"
	silver_moon.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = silver_moon
	_silver_moon_uid = silver_moon.uid
	# 已完成使用或打出的黑色手牌；实体只用于触发条件与稳定 UID 记录。
	var used_black_card: CardInstance = CardInstance.new("shan", "spade", 4)
	used_black_card.zone = "discard_pile"
	_controller.state.discard_pile.append(used_black_card)
	_controller._resolve_silver_moon_trigger(1, used_black_card, true)
	_controller._process_next_silver_moon_trigger()
	if not await _wait_until_no_card_choice():
		return _fail("silver_moon_timeout")
	# 当前回合0号角色是银月枪持有者的敌方目标；未打出闪后受到固定1点普通伤害。
	var target: PlayerState = _controller.state.get_player(0)
	if _silver_moon_request_count != 1 or target.hp != 3:
		return _fail("silver_moon_result=%d:%d" % [_silver_moon_request_count, target.hp])
	return true


## 验证木牛流马下的铁索连环不会被枚举为重铸动作，普通手牌中的铁索仍可重铸。
func _test_wooden_ox_card_cannot_recast() -> bool:
	_scenario = "wooden_ox_recast"
	_reset_state(2)
	# 普通手牌铁索；规则动作中必须存在其重铸入口。
	var hand_chain: CardInstance = _add_hand_card(0, "tiesuo", "club", 12)
	# 木牛流马粮牌铁索；只能使用，不能作为重铸来源。
	var stored_chain: CardInstance = CardInstance.new("tiesuo", "spade", 11)
	stored_chain.zone = "wooden_ox"
	stored_chain.owner_id = 0
	_controller.state.get_player(0).wooden_ox_storage.append(stored_chain)
	# 当前重铸动作实体 UID；从完整合法动作列表中过滤稳定动作类型。
	var recast_uids: Array[int] = []
	for action: Dictionary in _controller.get_legal_actions(0):
		if str(action.get("action_type", "")) == "recast_card":
			recast_uids.append(int(action.get("card_uid", -1)))
	if not recast_uids.has(hand_chain.uid) or recast_uids.has(stored_chain.uid):
		return _fail("wooden_ox_recast_actions=%s" % [recast_uids])
	return true


## 验证 AI 响应滑条的全局范围、步长与默认值均与菜单契约一致。
func _test_ai_delay_range() -> bool:
	if not is_equal_approx(GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS, 0.05):
		return _fail("ai_delay_min")
	if not is_equal_approx(GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS, 1.0):
		return _fail("ai_delay_max")
	if not is_equal_approx(GameSettings.AI_RESPONSE_DELAY_STEP_SECONDS, 0.05):
		return _fail("ai_delay_step")
	if not is_equal_approx(GameSettings.ai_response_delay_seconds, 0.30):
		return _fail("ai_delay_default")
	return true


## 向指定玩家普通手牌区加入一张测试实体，并返回对象供后续区域断言。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新测试实体牌；区域与所有者字段必须和玩家手牌数组保持一致。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 捕获统一选牌请求并在下一空闲帧提交对应标准动作，模拟玩家查看窗口后作出决定。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	if _failed:
		return
	# 请求规则上下文；kind 决定当前场景需要选择的实体牌或明确取消。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	# 请求用途；所有场景只处理本次实现涉及的稳定类型。
	var kind: String = str(context.get("kind", ""))
	# 本次提交的实体 UID；空数组表示玩家明确取消或不响应。
	var selected_uids: Array[int] = []
	if _scenario == "wuxie_aoe" and kind == "trick_negation":
		_wuxie_request_count += 1
		selected_uids = [_wuxie_uid]
	elif _scenario == "wuxie_aoe" and kind == "aoe_response":
		_aoe_request_count += 1
	elif _scenario == "dying" and kind == "dying_response":
		_dying_request_count += 1
		# 当前候选 UID；必须在同一请求中同时包含桃与酒。
		var candidate_uids: Array[int] = []
		for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
			candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		_dying_request_has_both_cards = candidate_uids.has(_peach_uid) and candidate_uids.has(_wine_uid)
		selected_uids = [_wine_uid]
	elif _scenario == "zhuque" and kind == "zhuque_trigger":
		_zhuque_request_count += 1
		selected_uids = [_zhuque_uid]
	elif _scenario == "zhuque" and kind == "slash_response":
		selected_uids = []
	elif _scenario == "silver_moon" and kind == "silver_moon_trigger":
		_silver_moon_request_count += 1
		selected_uids = [_silver_moon_uid]
	elif _scenario == "silver_moon" and kind == "silver_moon_response":
		selected_uids = []
	else:
		_fail("unexpected_choice=%s:%s" % [_scenario, kind])
		return
	call_deferred("_submit_choice", int(choice_data.get("request_id", -1)), int(choice_data.get("chooser_id", -1)), selected_uids)


## 提交已捕获请求的标准选牌动作；请求 ID 与选择者均沿用只读请求快照。
func _submit_choice(request_id: int, chooser_id: int, selected_uids: Array[int]) -> void:
	if _failed:
		return
	# 标准选牌动作；规则层仍会复核请求归属、候选 UID、数量与实体当前区域。
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_uids.duplicate()}
	if not _controller.submit_action(action):
		_fail("submit_choice=%s:%d" % [_scenario, request_id])


## 等待指定卡牌离开处理区且全部统一选牌请求完成；超时返回 false 防止测试永久卡住。
func _wait_until_card_finalized(card_uid: int) -> bool:
	for _frame_index: int in range(180):
		await get_tree().process_frame
		if _failed:
			return false
		if _controller._find_processing_card(card_uid) == null and not _controller.has_pending_card_choice():
			return true
	return false


## 等待当前统一选牌请求结束；用于没有原处理区卡牌的濒死流程。
func _wait_until_no_card_choice() -> bool:
	for _frame_index: int in range(180):
		await get_tree().process_frame
		if _failed:
			return false
		if not _controller.has_pending_card_choice():
			return true
	return false


## 输出稳定失败原因并以非0状态退出；返回 false 便于调用方立即停止后续场景。
func _fail(reason: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("GAMEPLAY_REGRESSION_FAIL %s" % reason)
	get_tree().quit(1)
	return false
