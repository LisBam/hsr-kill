extends Node

## 批量获得时机（cardsGainedBatchAfter）回归测试。
## 验证「一次面向规则的获得动作只派发一次整批事件」这一原子语义：批次边界由核心层给出，
## 单张获得同样成批、多张摸牌合成一批、非获得移动不派发、取消不留残留、嵌套获得各自成批。

## 测试使用的权威控制器；按正式依赖结构装配，规则调用不会绕过统一时机服务。
var _controller: MatchController

## 当前测试使用的长期根事件 ID；所有移牌与派发均挂在该根节点下。
var _root_event_id: int = -1

## 捕获到的全部被订阅时机名称；按真实派发顺序追加，用于断言事件先后关系。
var _captured_names: Array[String] = []

## 捕获到的全部事件载荷；每项形如 {name, data}，data 为派发时的纯数据副本。
var _captured_events: Array[Dictionary] = []

## 嵌套回归开关；为真时允许在批次事件回调内再触发一次获得动作。
var _nested_trigger_armed: bool = false

## 嵌套回归是否已经触发过；保证递归只发生一层，避免无限自触发。
var _nested_trigger_done: bool = false


## 延迟一帧运行测试，确保自动加载内容数据库和控制器子节点已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行全部批量获得断言；任意失败立即以非0退出码结束无头测试。
func _run() -> void:
	await get_tree().process_frame
	_create_controller()
	_install_state()
	if not _test_single_card_gain_forms_batch():
		return
	if not _test_multi_draw_forms_single_batch():
		return
	if not _test_event_order_is_gain_after_then_batch():
		return
	if not _test_non_gain_move_dispatches_nothing():
		return
	if not _test_bulk_gain_port_forms_single_batch():
		return
	if not _test_empty_bulk_gain_dispatches_nothing():
		return
	if not _test_cancelled_gain_leaves_no_batch():
		return
	if not _test_nested_gain_forms_own_batch():
		return
	print("BATCH_GAIN_PASS single=1 draw=1 order=1 no_gain=1 bulk=1 empty=1 cancel=1 nested=1")
	get_tree().quit(0)


## 创建与正式对局一致的控制器依赖节点；测试不注册 AI，也不创建界面表现组件。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；用于捕获控制器真实派发的标准时机。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；本测试全部为同步规则调用，不需要安装任何玩家策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；保持控制器节点结构与正式主场景一致。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = -1
	_controller.randomize_local_human_seat = false
	_controller.ai_action_delay_seconds = 0.01


## 安装三人权威状态和长期根事件；玩家均保持存活，避免获得牌触发濒死或终局。
func _install_state() -> void:
	# 本测试权威状态；空对局 ID 令规则保持同步且不创建网络等待。
	var game_state: GameState = GameState.new()
	game_state.match_id = ""
	# 三名测试玩家；身份包含领袖、忠臣和反贼，普通获得动作不会满足终局条件。
	var identities: Array[String] = ["leader", "loyalist", "rebel"]
	for player_id: int in range(3):
		# 当前测试玩家；基础体力固定4，所有角色保持正面、存活和已亮将状态。
		var player: PlayerState = PlayerState.new(player_id, "批量获得测试玩家%d" % (player_id + 1))
		player.identity = identities[player_id]
		player.character_id = "gepard"
		player.character_revealed = true
		player.max_hp = 4
		player.hp = 4
		game_state.players.append(player)
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.round_number = 1
	game_state.turn_number = 1
	_controller.event_scheduler.reset()
	# 长期根事件；同步规则摘要可以持续作为其子事件写入历史。
	var root_event: GameEvent = _controller.event_scheduler.create_event("BatchGainRoot", "root", [], {"match_id":"batch-gain-test"})
	_controller.event_scheduler.begin_root(root_event.event_id, true)
	_root_event_id = root_event.event_id
	_controller._runtime_root_event_id = root_event.event_id
	_controller._current_turn_event_id = root_event.event_id
	_controller.state = game_state
	game_state.current_event_id = root_event.event_id
	_controller.card_rules = CardRuleService.new(game_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, game_state)
	_controller.card_movement = CardMovementService.new(game_state)
	_controller.modifier_pipeline = RuleModifierPipeline.new()
	_controller.rule_query = RuleQuery.new(game_state, _controller.card_rules, _controller.modifier_pipeline)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, game_state)
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._started_phase_lifecycles.clear()
	# 批次栈必须从空开始：上一局或上一个用例留下的残留会让“隐式批次”判定全部失真。
	_controller._gain_batch_stack.clear()


## 单张获得自成一批：非批量入口移入手牌时，隐式批次同样派发一次 batch_size 为1的事件。
func _test_single_card_gain_forms_batch() -> bool:
	_reset_capture(["cardsGainedBatchAfter"])
	# 待获得的实体；先放入公共摸牌堆，再由统一移牌管线移入玩家1手牌。
	var card: CardInstance = _new_card_in_draw_pile("shan", "heart", 2)
	# 移牌结果；空值表示有效获得被错误阻止。
	var move: CardMoveEvent = _controller._move_card_with_timings(card, "hand", 1, "batch_single", _root_event_id)
	# 本用例捕获到的批次事件；单张获得必须恰好一整批。
	var batches: Array[Dictionary] = _events_named("cardsGainedBatchAfter")
	if move == null or batches.size() != 1:
		return _fail("single_batch count=%d move=%s" % [batches.size(), move != null])
	# 批次载荷；主体角色、张数与成员牌必须一致。
	var payload: Dictionary = batches[0]["data"] as Dictionary
	var batch_uids: Array = payload.get("card_uids", []) as Array
	if int(payload.get("batch_size", -1)) != 1 or int(payload.get("receiver_player_id", -1)) != 1 or not batch_uids.has(card.uid):
		return _fail("single_batch_payload=%s" % [payload])
	if int(payload.get("gain_batch_id", -1)) <= 0 or str(payload.get("reason", "")) != "batch_single":
		return _fail("single_batch_meta=%s" % [payload])
	return true


## 一次摸多张只派发一次批次事件：整次 draw 动作共享同一个批次，而不是逐张派发。
func _test_multi_draw_forms_single_batch() -> bool:
	_reset_capture(["gainAfter", "drawAfter", "cardsGainedBatchAfter"])
	# 三张摸牌实体；数组末尾是牌堆顶，一次 draw(3) 会全部移入玩家2手牌。
	var first_card: CardInstance = _new_card_in_draw_pile("sha", "spade", 7)
	_new_card_in_draw_pile("sha", "club", 8)
	_new_card_in_draw_pile("sha", "heart", 9)
	_controller.draw(2, 3, false)
	# 批次事件；一次摸牌动作只能产生一批。
	var batches: Array[Dictionary] = _events_named("cardsGainedBatchAfter")
	if batches.size() != 1:
		return _fail("multi_draw_batches=%d names=%s" % [batches.size(), _captured_names])
	var payload: Dictionary = batches[0]["data"] as Dictionary
	if int(payload.get("batch_size", -1)) != 3 or int(payload.get("receiver_player_id", -1)) != 2 or str(payload.get("reason", "")) != "draw":
		return _fail("multi_draw_payload=%s" % [payload])
	# 三张牌必须真的已经进入玩家2手牌，证明批次口径与实际移动一致。
	var receiver: PlayerState = _controller.state.get_player(2)
	if receiver == null or receiver.find_hand_card(first_card.uid) == null:
		return _fail("multi_draw_hand_missing uid=%d" % first_card.uid)
	return true


## 事件顺序固定为 gainAfter 与 drawAfter 全部结束后才派发批次事件。
func _test_event_order_is_gain_after_then_batch() -> bool:
	_reset_capture(["gainAfter", "drawAfter", "cardsGainedBatchAfter"])
	for _index: int in range(2):
		_new_card_in_draw_pile("tao", "diamond", 3 + _index)
	_controller.draw(1, 2, false)
	# 顺序断言；每次获得都必须在批次事件之前完成。
	var last_gain_after_index: int = _captured_names.rfind("gainAfter")
	var draw_after_index: int = _captured_names.find("drawAfter")
	var batch_index: int = _captured_names.find("cardsGainedBatchAfter")
	if last_gain_after_index < 0 or draw_after_index < 0 or batch_index < 0:
		return _fail("order_missing names=%s" % [_captured_names])
	if not (last_gain_after_index < draw_after_index and draw_after_index < batch_index):
		return _fail("order_names=%s" % [_captured_names])
	return true


## 非获得移动不派发批次事件：进入弃牌堆与装备区都不属于“获得牌”。
func _test_non_gain_move_dispatches_nothing() -> bool:
	_reset_capture(["cardsGainedBatchAfter"])
	# 弃牌堆移动；不进入手牌，因此不参与获得批次。
	var discard_card: CardInstance = _new_card_in_draw_pile("shan", "spade", 4)
	_controller._move_card_with_timings(discard_card, "discard_pile", -1, "batch_no_gain", _root_event_id)
	# 装备区移动；虽然指定了目标角色，但目标区域不是手牌，同样不参与获得批次。
	var equip_card: CardInstance = _new_card_in_draw_pile("zhuge", "club", 5)
	_controller._move_card_with_timings(equip_card, "equipment", 1, "batch_no_gain", _root_event_id, "weapon")
	if not _events_named("cardsGainedBatchAfter").is_empty():
		return _fail("non_gain_batch_dispatched=%s" % [_captured_names])
	if not _controller._gain_batch_stack.is_empty():
		return _fail("non_gain_stack_not_empty=%d" % _controller._gain_batch_stack.size())
	return true


## 批量获得端口的整批语义：一次“获得其全部手牌”只派发一批，且成员为整批牌。
func _test_bulk_gain_port_forms_single_batch() -> bool:
	# 目标角色手牌；先清空前面摸牌用例留下的牌，使“全部手牌”的范围精确为下面两张。
	var target: PlayerState = _controller.state.get_player(2)
	_clear_hand_for_test(target)
	var first_uid: int = _new_card_in_hand(target, "sha", "spade", 10)
	_new_card_in_hand(target, "shan", "heart", 11)
	_reset_capture(["cardsGainedBatchAfter"])
	var gained_count: int = _controller.gain_all_hand_cards(1, 2, "batch_bulk")
	var batches: Array[Dictionary] = _events_named("cardsGainedBatchAfter")
	if gained_count != 2 or batches.size() != 1:
		return _fail("bulk_batch count=%d gained=%d" % [batches.size(), gained_count])
	var payload: Dictionary = batches[0]["data"] as Dictionary
	var batch_uids: Array = payload.get("card_uids", []) as Array
	if int(payload.get("batch_size", -1)) != 2 or not batch_uids.has(first_uid) or str(payload.get("reason", "")) != "batch_bulk":
		return _fail("bulk_batch_payload=%s" % [payload])
	return true


## 空批次不派发：没有任何牌真的进入手牌时不得产生“发动了却没牌可判定”的空事件。
func _test_empty_bulk_gain_dispatches_nothing() -> bool:
	# 上一条用例已把目标手牌清空，本次调用必须安全地得到0张且不派发任何批次。
	_reset_capture(["cardsGainedBatchAfter"])
	var gained_count: int = _controller.gain_all_hand_cards(1, 2, "batch_empty")
	if gained_count != 0:
		return _fail("empty_bulk_gained=%d" % gained_count)
	if not _events_named("cardsGainedBatchAfter").is_empty() or not _controller._gain_batch_stack.is_empty():
		return _fail("empty_bulk_dispatched=%s stack=%d" % [_captured_names, _controller._gain_batch_stack.size()])
	return true


## 移动被前置时机取消时不留下残留批次，后续获得仍然能自成一批。
func _test_cancelled_gain_leaves_no_batch() -> bool:
	_reset_capture(["cardsGainedBatchAfter"])
	# 取消订阅；gainBefore 取消后牌并未进入手牌，隐式批次必须立即收尾。
	_controller.event_bus.subscribe("gainBefore", self, _cancel_rule_event, 100)
	var cancelled_card: CardInstance = _new_card_in_draw_pile("sha", "diamond", 12)
	var cancelled_move: CardMoveEvent = _controller._move_card_with_timings(cancelled_card, "hand", 1, "batch_cancelled", _root_event_id)
	var cancelled_batches: Array[Dictionary] = _events_named("cardsGainedBatchAfter")
	if cancelled_move != null or not cancelled_batches.is_empty() or not _controller._gain_batch_stack.is_empty():
		return _fail("cancel_residue move=%s batches=%d stack=%d" % [cancelled_move != null, cancelled_batches.size(), _controller._gain_batch_stack.size()])
	# 取消订阅必须只影响本次移动；后续正常获得仍然要派发一次完整批次。
	_controller.event_bus.unsubscribe_owner(self)
	_reset_capture(["cardsGainedBatchAfter"])
	var recovery_card: CardInstance = _new_card_in_draw_pile("sha", "spade", 13)
	var recovery_move: CardMoveEvent = _controller._move_card_with_timings(recovery_card, "hand", 1, "batch_recovery", _root_event_id)
	var recovery_batches: Array[Dictionary] = _events_named("cardsGainedBatchAfter")
	if recovery_move == null or recovery_batches.size() != 1 or int((recovery_batches[0]["data"] as Dictionary).get("batch_size", -1)) != 1:
		return _fail("cancel_recovery move=%s batches=%d" % [recovery_move != null, recovery_batches.size()])
	return true


## 嵌套获得各自成批：批次事件内由技能连锁产生的获得必须另起一批，且批次号互不相同。
func _test_nested_gain_forms_own_batch() -> bool:
	_reset_capture(["cardsGainedBatchAfter"])
	# 嵌套触发订阅；优先级高于捕获订阅，使内层获得在外层事件被记录之前发生。
	_nested_trigger_armed = true
	_nested_trigger_done = false
	_controller.event_bus.subscribe("cardsGainedBatchAfter", self, _trigger_nested_gain, 100)
	# 外层获得；其批次事件内部会再触发一次获得。
	var outer_card: CardInstance = _new_card_in_draw_pile("shan", "club", 14)
	var outer_move: CardMoveEvent = _controller._move_card_with_timings(outer_card, "hand", 1, "batch_nested_outer", _root_event_id)
	_nested_trigger_armed = false
	# 按 reason 定位两个批次，不依赖派发顺序，避免优先级变化导致断言脆弱。
	var outer_batch: Dictionary = _event_by_reason("cardsGainedBatchAfter", "batch_nested_outer")
	var inner_batch: Dictionary = _event_by_reason("cardsGainedBatchAfter", "batch_nested_inner")
	if outer_move == null or outer_batch.is_empty() or inner_batch.is_empty():
		return _fail("nested_missing names=%s" % [_captured_names])
	# 外层批次只能包含外层那 1 张牌，内层牌不得被计入外层。
	var outer_payload: Dictionary = outer_batch["data"] as Dictionary
	var inner_payload: Dictionary = inner_batch["data"] as Dictionary
	if int(outer_payload.get("batch_size", -1)) != 1 or int(inner_payload.get("batch_size", -1)) != 1:
		return _fail("nested_sizes outer=%s inner=%s" % [outer_payload, inner_payload])
	if int(outer_payload.get("gain_batch_id", -1)) == int(inner_payload.get("gain_batch_id", -1)):
		return _fail("nested_batch_id_reused=%s" % [outer_payload])
	if int(outer_payload.get("gain_batch_id", -1)) <= 0 or int(inner_payload.get("gain_batch_id", -1)) <= 0:
		return _fail("nested_batch_id_invalid outer=%s inner=%s" % [outer_payload, inner_payload])
	if not _controller._gain_batch_stack.is_empty():
		return _fail("nested_stack_not_empty=%d" % _controller._gain_batch_stack.size())
	return true


## 在批次事件中触发一次嵌套获得；只触发一层，避免自触发无限递归。
func _trigger_nested_gain(_event: RuleEvent) -> void:
	if not _nested_trigger_armed or _nested_trigger_done:
		return
	_nested_trigger_done = true
	# 内层牌；由独立的一次移牌动作进入手牌，因此必须自成一个新批次。
	var nested_card: CardInstance = _new_card_in_draw_pile("sha", "heart", 15)
	_controller._move_card_with_timings(nested_card, "hand", 1, "batch_nested_inner", _root_event_id)


## 清空旧捕获并重新订阅指定时机；只记录真实派发到总线的事件。
func _reset_capture(event_names: Array[String]) -> void:
	_controller.event_bus.unsubscribe_owner(self)
	_captured_names.clear()
	_captured_events.clear()
	for event_name: String in event_names:
		_controller.event_bus.subscribe(event_name, self, _capture_event)


## 捕获一条标准规则时机；事件对象只在当前同步回调内使用，载荷立即深拷贝。
func _capture_event(event: RuleEvent) -> void:
	_captured_names.append(event.name)
	_captured_events.append({"name":event.name, "data":(event.data as Dictionary).duplicate(true)})


## 取消当前规则事件；获得取消用例借此验证未发生的移动不会留下批次残留。
func _cancel_rule_event(event: RuleEvent) -> void:
	event.cancel()


## 取出指定名称的全部捕获事件；顺序与真实派发顺序一致。
func _events_named(event_name: String) -> Array[Dictionary]:
	# 筛选结果；只保留名称匹配项，供计数与载荷断言使用。
	var result: Array[Dictionary] = []
	for captured: Dictionary in _captured_events:
		if str(captured.get("name", "")) == event_name:
			result.append(captured)
	return result


## 按载荷中的 reason 取出唯一事件；缺失时返回空字典，便于调用方统一判失败。
func _event_by_reason(event_name: String, reason: String) -> Dictionary:
	for captured: Dictionary in _captured_events:
		if str(captured.get("name", "")) != event_name:
			continue
		if str((captured.get("data", {}) as Dictionary).get("reason", "")) == reason:
			return captured
	return {}


## 创建一张位于公共摸牌堆的实体；数组末尾是牌堆顶，后续移牌会从该处取出。
func _new_card_in_draw_pile(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新实体；初始属于公共区域，不携带任何持有者。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 创建一张直接放入指定角色手牌的实体；用于构造“一次获得其全部手牌”等多张获得场景。
func _new_card_in_hand(player: PlayerState, definition_id: String, suit: String, rank: int) -> int:
	# 新实体；区域与持有者必须与实际所在位置一致，否则统一移牌边界的来源锚点会错位。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player.player_id
	player.hand.append(card)
	return card.uid


## 清空指定角色的手牌；通过统一移牌边界把每张牌置入弃牌堆，避免测试直接改写牌区数组。
func _clear_hand_for_test(player: PlayerState) -> void:
	if player == null:
		return
	# 手牌 UID 快照；必须先复制再移动，否则遍历期间数组会被就地修改。
	var hand_uids: Array[int] = []
	for hand_card: CardInstance in player.hand:
		hand_uids.append(hand_card.uid)
	for card_uid: int in hand_uids:
		# 当前实体；已经离开手牌区的牌安全跳过。
		var card: CardInstance = player.find_hand_card(card_uid)
		if card != null:
			_controller._move_card_with_timings(card, "discard_pile", -1, "batch_test_cleanup", _root_event_id)


## 输出稳定失败原因并以非0状态结束测试；返回 false 便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	printerr("BATCH_GAIN_FAIL %s" % reason)
	get_tree().quit(1)
	return false
