extends Node

## 阶段恢复回归。验证延时锦囊、阶段跳过、翻面与濒死取消经过异步选择后都能继续到唯一合法阶段。

## 测试控制器；按正式组件结构装配，所有选择仍经过 EventScheduler 与 MatchController 权威校验。
var _controller: MatchController

## 最近一次属于本地玩家的统一选牌请求；用于模拟界面点击确定或取消。
var _local_choice_request: Dictionary = {}

## 测试状态安装序号；每次重建权威状态时生成不同 match_id，避免旧请求命中新场景。
var _state_sequence: int = 0

## 测试是否已经结束；失败与成功出口共用该标记，防止异步 AI 计时器重复退出。
var _finished: bool = false


## 延迟运行回归，确保自动加载数据与控制器子节点均已完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证跳过摸牌、跳过出牌、翻面跳回合和救援取消四条阶段恢复路径。
func _run() -> void:
	_create_controller()
	_test_skip_draw_after_deferred_negation()
	if _finished:
		return
	_test_skip_play_after_deferred_negation()
	if _finished:
		return
	_test_face_down_turn_progression()
	if _finished:
		return
	await _test_dying_cancel_progression()
	if _finished:
		return
	# 失效 AI 任务令牌；让各场景已创建的短计时器自然结束后再释放控制器，避免测试退出时残留对象。
	_controller._ai_drive_token += 1
	await get_tree().create_timer(0.03).timeout
	remove_child(_controller)
	_controller.free()
	print("PHASE_PROGRESSION_PASS")
	_finished = true
	get_tree().quit(0)


## 创建正式依赖结构；一号和二号非本地玩家由基础 AI 同步完成选择，避免测试等待不存在的客户端。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；名称与正式控制器的节点依赖保持一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；非本地救援者与下一回合角色使用基础策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；选择来源与正式单机对局保持一致。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.ai_action_delay_seconds = 0.01
	_controller.ai_coordinator.register_basic_ai(1)
	_controller.ai_coordinator.register_basic_ai(2)
	_controller.card_choice_requested.connect(_on_card_choice_requested)


## 安装一份三人权威状态并重置运行时；主公、忠臣、反贼并存可避免单次死亡立即结束对局。
func _install_state() -> GameState:
	_state_sequence += 1
	# 新权威状态；非空 match_id 令0号玩家的选择走真实延迟提交路径。
	var game_state: GameState = GameState.new()
	game_state.match_id = "phase-progression-%d" % _state_sequence
	for player_id: int in range(3):
		# 当前测试玩家；身份顺序保证0号忠臣死亡后对局仍继续。
		var player: PlayerState = PlayerState.new(player_id, "测试玩家%d" % (player_id + 1))
		player.identity = ["loyalist", "lord", "rebel"][player_id]
		player.character_id = "trailblazer"
		player.character_revealed = true
		game_state.players.append(player)
	_controller.event_scheduler.reset()
	# 长生命周期根事件；阶段、选择和卡牌事件全部挂在该根节点下。
	var root_event: GameEvent = _controller.event_scheduler.create_event("RootGameEvent", "root", [], {"match_id":game_state.match_id})
	_controller.event_scheduler.begin_root(root_event.event_id, true)
	_controller._runtime_root_event_id = root_event.event_id
	_controller._current_turn_event_id = -1
	_controller._pending_card_choice.clear()
	_controller._resolved_card_choice_uids.clear()
	_controller._negation_resume_results.clear()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller._scheduled_ai_drive_token = -1
	_controller._scheduled_ai_choice_request_id = -1
	_controller._ai_drive_token += 1
	_controller.state = game_state
	_controller.card_rules = CardRuleService.new(game_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, game_state)
	_controller.card_movement = CardMovementService.new(game_state)
	_controller.modifier_pipeline = RuleModifierPipeline.new()
	_controller.rule_query = RuleQuery.new(game_state, _controller.card_rules, _controller.modifier_pipeline)
	_local_choice_request.clear()
	return game_state


## 验证兵粮寸断的无懈询问暂停判定，取消后完成判定并跳过固定2张摸牌，再进入唯一出牌请求。
func _test_skip_draw_after_deferred_negation() -> void:
	# 本场状态；0号玩家持有无懈并成为兵粮寸断目标。
	var game_state: GameState = _install_state()
	# 本地无懈可击；确保判定阶段产生可取消的人类响应请求。
	var counter_card: CardInstance = _add_card(game_state.players[0], "wuxie", "spade", 11, "hand")
	# 兵粮寸断实体；进入0号玩家判定区等待本回合结算。
	var supply_shortage: CardInstance = _add_card(game_state.players[0], "bingliang", "spade", 10, "judgment")
	# 两张保留牌堆牌；跳过摸牌成功时它们不会进入玩家手牌。
	var first_draw_card: CardInstance = _add_draw_card(game_state, "sha", "club", 3)
	# 第二张保留牌堆牌；与第一张共同验证基础摸牌数固定为2且本次完全跳过。
	var second_draw_card: CardInstance = _add_draw_card(game_state, "shan", "diamond", 4)
	# 兵粮判定牌；红桃不是梅花，因此取消无懈后必须记录跳过摸牌阶段。
	var supply_judgment: CardInstance = _add_draw_card(game_state, "tao", "heart", 6)
	_controller._start_turn(0)
	if game_state.current_phase != "choice" or not _controller.has_pending_card_choice() or _controller._has_active_play_choice() or str((_local_choice_request.get("context", {}) as Dictionary).get("kind", "")) != "trick_negation":
		_fail("skip_draw_not_paused phase=%s" % game_state.current_phase)
		return
	if not _submit_local_cancel(_local_choice_request):
		return
	if game_state.current_phase != "play" or not _controller._has_active_play_choice() or _controller.has_pending_card_choice() or not bool(game_state.players[0].skipped_phases.get("draw", false)) or game_state.players[0].hand.size() != 1 or game_state.draw_pile.size() != 2 or not game_state.draw_pile.has(first_draw_card) or not game_state.draw_pile.has(second_draw_card) or not game_state.discard_pile.has(supply_judgment) or not game_state.discard_pile.has(supply_shortage) or game_state.players[0].find_hand_card(counter_card.uid) == null:
		_fail("skip_draw_resume phase=%s hand=%d draw=%d" % [game_state.current_phase, game_state.players[0].hand.size(), game_state.draw_pile.size()])


## 验证乐不思蜀的异步无懈取消后跳过出牌，自动完成弃牌与结束阶段并转交下一回合。
func _test_skip_play_after_deferred_negation() -> void:
	# 本场状态；0号玩家持有无懈并成为乐不思蜀目标。
	var game_state: GameState = _install_state()
	# 本地无懈可击；用于暂停乐不思蜀判定并模拟玩家取消。
	var counter_card: CardInstance = _add_card(game_state.players[0], "wuxie", "club", 12, "hand")
	# 乐不思蜀实体；判定未被抵消时将设置跳过出牌阶段。
	var indulgence: CardInstance = _add_card(game_state.players[0], "lebu", "heart", 6, "judgment")
	# 下一回合第一张摸牌；确保转交到1号玩家后牌堆仍足够完成固定摸2张。
	var next_draw_one: CardInstance = _add_draw_card(game_state, "sha", "club", 5)
	# 下一回合第二张摸牌；与前一张共同防止牌堆耗尽触发平局。
	var next_draw_two: CardInstance = _add_draw_card(game_state, "shan", "heart", 8)
	# 当前回合第一张摸牌；乐不思蜀只跳过出牌，不会跳过本回合固定摸2张。
	var current_draw_one: CardInstance = _add_draw_card(game_state, "sha", "diamond", 5)
	# 当前回合第二张摸牌；位于判定牌下方并在0号玩家摸牌阶段进入其手牌。
	var current_draw_two: CardInstance = _add_draw_card(game_state, "shan", "club", 8)
	# 乐不思蜀判定牌；黑桃不是红桃，因此取消无懈后必须跳过出牌阶段。
	var indulgence_judgment: CardInstance = _add_draw_card(game_state, "tao", "spade", 9)
	_controller._start_turn(0)
	if game_state.current_phase != "choice" or _local_choice_request.is_empty():
		_fail("skip_play_not_paused")
		return
	if not _submit_local_cancel(_local_choice_request):
		return
	if game_state.current_player_id != 1 or game_state.current_phase != "play" or game_state.turn_number != 2 or not bool(game_state.players[0].skipped_phases.get("play", false)) or not _controller._has_active_play_choice() or _controller.has_pending_card_choice() or game_state.players[0].find_hand_card(counter_card.uid) == null or game_state.players[0].find_hand_card(current_draw_one.uid) == null or game_state.players[0].find_hand_card(current_draw_two.uid) == null or not game_state.discard_pile.has(indulgence) or not game_state.discard_pile.has(indulgence_judgment) or game_state.players[1].find_hand_card(next_draw_one.uid) == null or game_state.players[1].find_hand_card(next_draw_two.uid) == null:
		_fail("skip_play_resume current=%d phase=%s turn=%d skipped=%s active=%s pending=%s" % [game_state.current_player_id, game_state.current_phase, game_state.turn_number, game_state.players[0].skipped_phases, _controller._has_active_play_choice(), _controller.has_pending_card_choice()])


## 验证翻面角色翻回正面后跳过整回合，并直接为下一名存活角色建立出牌请求。
func _test_face_down_turn_progression() -> void:
	# 本场状态；0号玩家以背面状态开始回合。
	var game_state: GameState = _install_state()
	game_state.players[0].face_down = true
	# 下一回合第一张摸牌；保证1号玩家正常完成摸牌阶段。
	var next_draw_one: CardInstance = _add_draw_card(game_state, "sha", "spade", 2)
	# 下一回合第二张摸牌；保证阶段推进不会因空牌堆提前终局。
	var next_draw_two: CardInstance = _add_draw_card(game_state, "shan", "heart", 2)
	_controller._start_turn(0)
	if game_state.players[0].face_down or game_state.current_player_id != 1 or game_state.current_phase != "play" or game_state.turn_number != 2 or not _controller._has_active_play_choice() or game_state.players[1].find_hand_card(next_draw_one.uid) == null or game_state.players[1].find_hand_card(next_draw_two.uid) == null:
		_fail("face_down_resume current=%d phase=%s" % [game_state.current_player_id, game_state.current_phase])


## 验证救援桃请求可以取消，且取消后不会重新询问同一张桃；后续 AI 救援会经过延迟响应，当前角色死亡后才转交回合。
func _test_dying_cancel_progression() -> void:
	# 本场状态；0号忠臣在自己的出牌阶段进入濒死，死亡后身份局仍继续。
	var game_state: GameState = _install_state()
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.players[0].hp = 0
	# 本地桃实体；救援请求必须把它列为候选，同时仍允许玩家点击取消。
	var peach_card: CardInstance = _add_card(game_state.players[0], "tao", "heart", 3, "hand")
	# 下一回合第一张摸牌；当前角色死亡后供1号玩家正常摸牌。
	var next_draw_one: CardInstance = _add_draw_card(game_state, "sha", "club", 7)
	# 下一回合第二张摸牌；避免死亡转交后因牌堆不足结束对局。
	var next_draw_two: CardInstance = _add_draw_card(game_state, "shan", "diamond", 7)
	_controller._resolve_dying(0, -1)
	# 首次桃请求；必须允许取消且包含唯一桃候选。
	var peach_request: Dictionary = _local_choice_request.duplicate(true)
	if peach_request.is_empty() or not bool(peach_request.get("allow_cancel", false)) or (peach_request.get("candidates", []) as Array).size() != 1 or str((peach_request.get("context", {}) as Dictionary).get("response_pattern", "")) != "tao":
		_fail("dying_peach_request")
		return
	if not _submit_local_cancel(peach_request):
		return
	# 桃取消后的自救酒请求；请求 ID 必须变化，证明旧桃请求已被真正关闭而非重复弹出。
	var wine_request: Dictionary = _local_choice_request.duplicate(true)
	if wine_request.is_empty() or int(wine_request.get("request_id", -1)) == int(peach_request.get("request_id", -1)) or str((wine_request.get("context", {}) as Dictionary).get("response_pattern", "")) != "jiu":
		_fail("dying_peach_cancel_not_advanced")
		return
	if not _submit_local_cancel(wine_request):
		return
	# 濒死取消后的 AI 救援完成标记；两个 AI 都需要经过统一响应延迟后明确放弃，不能同步跳过询问。
	var dying_resume_completed: bool = false
	for _wait_frame_index: int in range(20):
		await get_tree().process_frame
		if not game_state.players[0].alive and game_state.current_player_id == 1 and game_state.current_phase == "play":
			dying_resume_completed = true
			# 下一回合 AI 的普通出牌计时器；救援恢复完成后立即失效，避免干扰本用例的阶段断言。
			_controller._ai_drive_token += 1
			break
	if not dying_resume_completed:
		_fail("dying_ai_response_timeout phase=%s pending=%s" % [game_state.current_phase, _controller.has_pending_card_choice()])
		return
	if game_state.players[0].alive or game_state.players[0].find_hand_card(peach_card.uid) != null or game_state.current_player_id != 1 or game_state.current_phase != "play" or game_state.turn_number != 1 or _controller.has_pending_card_choice() or not _controller._has_active_play_choice() or game_state.players[1].find_hand_card(next_draw_one.uid) == null or game_state.players[1].find_hand_card(next_draw_two.uid) == null:
		_fail("dying_cancel_resume alive=%s current=%d phase=%s" % [game_state.players[0].alive, game_state.current_player_id, game_state.current_phase])


## 向指定玩家区域加入一张实体牌；测试只使用 hand 与 judgment 两种公开稳定区域。
func _add_card(player: PlayerState, definition_id: String, suit: String, rank: int, zone: String) -> CardInstance:
	# 新实体牌；所有权与区域在加入数组前完整写入，避免选择候选读取到默认牌堆状态。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = zone
	card.owner_id = player.player_id
	if zone == "hand":
		player.hand.append(card)
	else:
		player.judgment_area.append(card)
	return card


## 向牌堆顶部加入一张实体牌；GameState 使用数组末尾作为牌堆顶。
func _add_draw_card(game_state: GameState, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新牌堆实体牌；公共牌堆没有所属玩家。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	game_state.draw_pile.append(card)
	return card


## 提交当前本地请求的空选择；返回 false 表示权威运行时拒绝了取消动作。
func _submit_local_cancel(choice_request: Dictionary) -> bool:
	# 标准取消动作；空 UID 数组只能在请求 allow_cancel=true 时通过。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(choice_request.get("request_id", -1)), "selected_card_uids":[]}
	if _controller.submit_action(action):
		return true
	_fail("cancel_rejected request=%d" % int(choice_request.get("request_id", -1)))
	return false


## 捕获属于0号本地玩家的统一选择请求；AI 请求不会覆盖等待断言的本地上下文。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	if int(choice_data.get("chooser_id", -1)) == 0:
		_local_choice_request = choice_data.duplicate(true)


## 输出稳定失败原因并以非0状态退出，便于命令行定位具体阶段恢复断言。
func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	printerr("PHASE_PROGRESSION_FAIL %s" % reason)
	get_tree().quit(1)
