extends Node

## 多张重铸专项测试：校验一次性重铸多张牌、等量补摸、实际张数回报，以及单张路径的语义零回归。

## 本次测试权威控制器；使用与正式场景同类型的实例并手动装配必需子节点。
var _controller: MatchController

## 本次捕获的公开日志文本；按写入顺序保存，用于断言重铸日志文本。
var _captured_logs: Array[String] = []


## 运行全部断言；测试节点保持 ALWAYS，避免流程暂停阻断断言推进。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_controller()
	if not _test_batch_recast_moves_and_draws_equal():
		return
	if not _test_single_card_path_unchanged():
		return
	if not _test_empty_selection_is_noop():
		return
	if not _test_invalid_uids_are_skipped():
		return
	if not _test_duplicate_uids_count_once():
		return
	if not _test_non_hand_card_skipped():
		return
	if not _test_inactive_owner_and_game_over_rejected():
		return
	print("MULTI_RECAST_PASS batch=3 equal_draw=1 single=1 skip=1 dedup=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器，并订阅公开日志；不加载界面，保持牌区与规则断言隔离。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；重铸路径的时机派发与正式实现保持一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保持正式实现，避免技能与态度查询走空分支。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；公开快照广播与正式单机模式保持相同路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0
	_controller.log_added.connect(_on_log_added)


## 为单项测试创建最小权威状态并重建全部规则服务；角色身份公开以获得确定AI态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "multi-recast"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "重铸测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	# 摸牌堆；等量补摸断言需要足够的可用实体牌。
	for card_index: int in range(20):
		_controller.state.draw_pile.append(CardInstance.new("shan", "heart", card_index % 13 + 1))
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()
	# 日志捕获容器；每个场景都必须从干净基线开始断言。
	_captured_logs.clear()


## 把一张实体牌直接放入指定玩家的普通手牌区；测试需要绕过摸牌流程构造确定手牌。
func _give_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	var player: PlayerState = _controller.state.get_player(player_id)
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	# 持有者与区域；正式对局由移动服务在进入玩家区域时写入，测试直接入区必须补齐。
	card.owner_id = player_id
	card.zone = "hand"
	player.hand.append(card)
	return card


## 校验一次性重铸多张牌：全部实体进入弃牌堆、按实际张数等量补摸、只写一条汇总日志。
func _test_batch_recast_moves_and_draws_equal() -> bool:
	_reset_state(2)
	var first_card: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var second_card: CardInstance = _give_hand_card(0, "shan", "heart", 3)
	var third_card: CardInstance = _give_hand_card(0, "tao", "club", 9)
	# 未参与重铸的手牌；重铸后必须原样留在手里。
	var kept_card: CardInstance = _give_hand_card(0, "wuxie", "diamond", 4)
	# 基线张数；手牌数在“弃3摸3”后必须保持一致。
	var hand_count_before: int = _controller.state.get_player(0).hand.size()
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	var recast_uids: Array[int] = [first_card.uid, second_card.uid, third_card.uid]
	if _controller.recast_hand_cards(0, recast_uids) != 3:
		return _fail("batch_count")
	var recast_cards: Array[CardInstance] = [first_card, second_card, third_card]
	for card: CardInstance in recast_cards:
		if not _controller.state.discard_pile.has(card):
			return _fail("batch_not_in_discard")
		if _controller.state.get_player(0).find_hand_card(card.uid) != null:
			return _fail("batch_still_in_hand")
	# 等量补摸；需求要求“置入弃牌堆然后摸等量的牌”，不是逐张各摸一张的叠加效果。
	if _controller.state.draw_pile.size() != draw_pile_count_before - 3:
		return _fail("batch_draw_pile=%d" % _controller.state.draw_pile.size())
	if _controller.state.get_player(0).hand.size() != hand_count_before:
		return _fail("batch_hand=%d" % _controller.state.get_player(0).hand.size())
	if not _controller.state.get_player(0).hand.has(kept_card):
		return _fail("batch_kept_lost")
	# 重铸只写一条汇总日志；出现“弃置了”会让玩家误判本次牌张归属。
	if not _test_logged_with_text("重铸了3张牌。"):
		return false
	for log_text: String in _captured_logs:
		if log_text.contains("弃置了"):
			return _fail("batch_discard_log=%s" % log_text)
	return true


## 校验单张重铸入口的既有语义零回归：布尔返回值、固定摸一张、单张日志文本。
func _test_single_card_path_unchanged() -> bool:
	_reset_state(2)
	# 可主动重铸的实体牌；【铁索连环】在自身卡牌定义中把 recast 标记为 true。
	var recast_card: CardInstance = _give_hand_card(0, "tiesuo", "club", 12)
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	if not _controller.recast_hand_card(0, recast_card.uid):
		return _fail("single_rejected")
	if not _controller.state.discard_pile.has(recast_card) or _controller.state.get_player(0).find_hand_card(recast_card.uid) != null:
		return _fail("single_move")
	if _controller.state.draw_pile.size() != draw_pile_count_before - 1:
		return _fail("single_draw=%d" % _controller.state.draw_pile.size())
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("single_hand=%d" % _controller.state.get_player(0).hand.size())
	if not _test_logged_with_verb("重铸了"):
		return false
	# 单张路径必须继续使用“重铸了<牌名>。”，不得退化成多张汇总文本。
	for log_text: String in _captured_logs:
		if log_text.contains("重铸了1张牌"):
			return _fail("single_log_batch_text=%s" % log_text)
	return true


## 校验空选择是完全无副作用的空操作：不移动牌、不补摸、不写日志。
func _test_empty_selection_is_noop() -> bool:
	_reset_state(2)
	var kept_card: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	var empty_uids: Array[int] = []
	if _controller.recast_hand_cards(0, empty_uids) != 0:
		return _fail("empty_count")
	if _controller.state.get_player(0).hand.size() != 1 or not _controller.state.get_player(0).hand.has(kept_card):
		return _fail("empty_mutated_hand")
	if _controller.state.draw_pile.size() != draw_pile_count_before:
		return _fail("empty_drew_card")
	if not _captured_logs.is_empty():
		return _fail("empty_logged %s" % str(_captured_logs))
	return true


## 校验无效实体 UID 被跳过，回报值与汇总日志都按实际完成张数计算。
func _test_invalid_uids_are_skipped() -> bool:
	_reset_state(2)
	var valid_card: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	var mixed_uids: Array[int] = [valid_card.uid, 999999]
	if _controller.recast_hand_cards(0, mixed_uids) != 1:
		return _fail("invalid_uid_count")
	if not _controller.state.discard_pile.has(valid_card):
		return _fail("invalid_uid_move")
	if _controller.state.draw_pile.size() != draw_pile_count_before - 1:
		return _fail("invalid_uid_draw=%d" % _controller.state.draw_pile.size())
	# 多张路径按实际张数写汇总日志；1 张也要写成汇总文本，便于技能侧读取同一种口径。
	if not _test_logged_with_text("重铸了1张牌。"):
		return false
	return true


## 校验同一实体在一批中重复出现时只重铸一次、只补摸一张。
func _test_duplicate_uids_count_once() -> bool:
	_reset_state(2)
	var card: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	var duplicated_uids: Array[int] = [card.uid, card.uid, card.uid]
	if _controller.recast_hand_cards(0, duplicated_uids) != 1:
		return _fail("duplicate_count")
	if _controller.state.draw_pile.size() != draw_pile_count_before - 1:
		return _fail("duplicate_draw=%d" % _controller.state.draw_pile.size())
	if _controller.state.discard_pile.count(card) != 1:
		return _fail("duplicate_discard_count=%d" % _controller.state.discard_pile.count(card))
	return true


## 校验已经离开手牌的实体不会被重铸，也不会带来任何补摸。
func _test_non_hand_card_skipped() -> bool:
	_reset_state(2)
	var card: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	# 先手动移出手牌并登记到弃牌堆；重铸入口只承认普通手牌区的实体。
	_controller.state.get_player(0).take_hand_card(card.uid)
	card.zone = "discard_pile"
	_controller.state.discard_pile.append(card)
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	var stale_uids: Array[int] = [card.uid]
	if _controller.recast_hand_cards(0, stale_uids) != 0:
		return _fail("non_hand_recast")
	if _controller.state.draw_pile.size() != draw_pile_count_before:
		return _fail("non_hand_drew_card")
	return true


## 校验死亡、离场、终局与无效玩家一律被拒绝，且单张入口继续保持布尔语义。
func _test_inactive_owner_and_game_over_rejected() -> bool:
	_reset_state(2)
	var card: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var single_uids: Array[int] = [card.uid]
	_controller.state.get_player(0).alive = false
	if _controller.recast_hand_cards(0, single_uids) != 0 or _controller.recast_hand_card(0, card.uid):
		return _fail("dead_recast")
	_controller.state.get_player(0).alive = true
	_controller.state.get_player(0).out_of_game = true
	if _controller.recast_hand_cards(0, single_uids) != 0 or _controller.recast_hand_card(0, card.uid):
		return _fail("out_of_game_recast")
	_controller.state.get_player(0).out_of_game = false
	_controller.state.game_over = true
	if _controller.recast_hand_cards(0, single_uids) != 0 or _controller.recast_hand_card(0, card.uid):
		return _fail("game_over_recast")
	_controller.state.game_over = false
	if _controller.recast_hand_cards(-1, single_uids) != 0 or _controller.recast_hand_card(-1, card.uid):
		return _fail("invalid_player_recast")
	# 全部非法路径之后手牌必须完好，证明拒绝发生在移牌之前。
	if not _controller.state.get_player(0).hand.has(card):
		return _fail("rejected_moved_card")
	return true


## 判断本次捕获的日志中是否存在包含指定动词的条目。
func _test_logged_with_verb(verb: String) -> bool:
	for log_text: String in _captured_logs:
		if log_text.contains(verb):
			return true
	return _fail("log_missing %s" % verb)


## 判断本次捕获的日志中是否存在包含指定文本的条目；公开日志带玩家名前缀，因此按包含匹配。
func _test_logged_with_text(expected: String) -> bool:
	for log_text: String in _captured_logs:
		if log_text.contains(expected):
			return true
	return _fail("log_text_missing %s in %s" % [expected, str(_captured_logs)])


## 记录公开日志文本；断言只读取本数组，不反向查询控制器内部状态。
func _on_log_added(message: String) -> void:
	_captured_logs.append(message)


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("MULTI_RECAST_FAIL %s" % reason)
	get_tree().quit(1)
	return false
