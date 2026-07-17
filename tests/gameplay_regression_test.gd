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

## 同时无懈测试收到的私有请求快照；用于主动让后提交登记的玩家先响应并验证先到先结算。
var _simultaneous_negation_requests: Array[Dictionary] = []

## 同时无懈偶数链恢复后需要由过河拆桥选择的目标手牌 UID。
var _simultaneous_protected_uid: int = -1

## 当前场景需要由濒死者选择的【桃】实体 UID。
var _peach_uid: int = -1

## 当前场景需要由濒死者选择的【酒】实体 UID。
var _wine_uid: int = -1

## 当前场景需要由玩家选择发动的朱雀羽扇实体 UID。
var _zhuque_uid: int = -1

## 当前场景需要由玩家选择发动的银月枪实体 UID。
var _silver_moon_uid: int = -1

## 桃园结义恢复测试收到的无懈询问次数；两名目标各自询问一次，完成后必须恢复同一出牌阶段。
var _taoyuan_negation_request_count: int = 0

## 连续求桃测试中由同一救援者依次打出的桃 UID；数组顺序同时用于验证两次请求没有切换响应者。
var _multi_peach_uids: Array[int] = []

## 连续求桃测试收到的所需回复数量；目标从-1点开始时必须依次显示2和1。
var _dying_required_recover_history: Array[int] = []

## 连续求桃测试收到的响应者 ID；两次都应是首名实际出桃的同一角色。
var _dying_responder_history: Array[int] = []

## 测试是否已经失败；失败后延迟回调不会继续提交旧请求。
var _failed: bool = false

## 最近一次规则层牌面表现事件快照；默认空字典，判定测试用于验证 judge 的公开展示协议。
var _last_presentation: Dictionary = {}

## 最近一次进入弃牌堆的真实移动表现快照；默认空字典，用于确认判定牌只产生一次 processing -> discard 增量。
var _last_discard_transfer: Dictionary = {}

## 当前场景收到的全部牌面表现快照；按信号到达顺序保存，判定链测试据此验证延时牌与判定牌严格交替。
var _presentation_history: Array[Dictionary] = []

## 丈八蛇矛测试使用的装备实体 UID；响应处理器只能选择该公开装备入口。
var _zhangba_uid: int = -1

## 丈八蛇矛测试使用的两张普通手牌材料 UID；选择动作会把该数组写入 material_card_uids 负载。
var _zhangba_material_uids: Array[int] = []

## 丈八响应请求是否同时公开了装备候选；默认false，收到正确候选后改为true。
var _zhangba_response_has_equipment: bool = false

## 八卦阵失败回归收到的【闪】响应请求数量；首次包含八卦阵，黑色判定后第二次只保留其他合法候选。
var _bagua_response_request_count: int = 0

## 八卦阵失败回归使用的防具实体 UID；第二次请求必须排除该 UID，避免同一响应时机重复判定。
var _bagua_uid: int = -1

## 八卦阵失败回归使用的手牌【闪】实体 UID；黑色判定后必须继续出现在第二次响应请求中。
var _bagua_hand_shan_uid: int = -1

## 八卦阵失败后的第二次请求是否保留手牌【闪】；默认false，收到符合候选协议的请求后改为true。
var _bagua_retry_has_hand_shan: bool = false

## 八卦阵失败后的第二次请求是否排除已判定防具；默认false，用于防止重复发动形成无限响应循环。
var _bagua_retry_excludes_bagua: bool = false

## 麒麟弓回归收到的坐骑选择请求数量；标准流程只应创建一次公开装备选择。
var _qilin_request_count: int = 0

## 麒麟弓回归目标坐骑实体 UID；强类型槽位查询必须把该实体加入候选并允许弃置。
var _qilin_mount_uid: int = -1

## 麒麟弓回归是否在选择请求中找到目标坐骑；默认false，收到正确候选后改为true。
var _qilin_candidate_present: bool = false


## 延迟一帧执行测试，确保自动加载卡牌数据和节点依赖已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次运行独立场景；任一断言失败会立即以非0状态结束。
func _run() -> void:
	_create_controller()
	if not await _test_simultaneous_wuxie_first_response_wins():
		return
	if not await _test_wuxie_per_target_and_aoe_continuation():
		return
	if not await _test_dynamic_targets_direct_hit_and_exclusion():
		return
	if not await _test_dying_peach_and_wine_share_one_request():
		return
	if not await _test_dying_continuous_peaches_in_single_round():
		return
	if not await _test_taoyuan_restores_play_choice_after_multiple_responses():
		return
	if not _test_response_card_pattern_filter():
		return
	if not await _test_full_health_wine_use():
		return
	if not await _test_zhuque_requires_activation_choice():
		return
	if not await _test_silver_moon_requires_activation_choice():
		return
	if not await _test_zhangba_play_uses_two_materials():
		return
	if not await _test_zhangba_response_uses_two_materials():
		return
	if not await _test_bagua_failure_allows_hand_shan():
		return
	if not await _test_qilin_mount_candidate_slots():
		return
	if not _test_wooden_ox_card_cannot_recast():
		return
	if not _test_wooden_ox_storage_excluded_from_hand_limit():
		return
	if not _test_ai_delay_range():
		return
	if not _test_judgment_presentation_and_event_chain():
		return
	if not await _test_delayed_judgment_presentation_sequence():
		return
	print("GAMEPLAY_REGRESSION_PASS wuxie=%d aoe=%d dying=%d taoyuan=%d zhuque=%d yinyue=%d zhangba=2 judge=2" % [_wuxie_request_count, _aoe_request_count, _dying_request_count, _taoyuan_negation_request_count, _zhuque_request_count, _silver_moon_request_count])
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
	_controller.card_presentation_requested.connect(_on_card_presentation_requested)
	_controller.card_transfer_requested.connect(_on_card_transfer_requested)


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
	_controller.trigger_manager = TriggerManager.new()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._negation_round_sequence = 0
	_controller._resolved_card_choice_uids.clear()
	_controller._resolved_equipment_material_uids.clear()
	_controller._negation_resume_results.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._queued_equipment_triggers.clear()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller._judgment_flow_token += 1
	_controller._judgment_flow_in_progress = false
	_controller._judgment_resume_needs_result_pause = false
	_controller.ai_coordinator._policies.clear()
	_presentation_history.clear()
	_simultaneous_negation_requests.clear()
	_simultaneous_protected_uid = -1
	_bagua_response_request_count = 0
	_bagua_uid = -1
	_bagua_hand_shan_uid = -1
	_bagua_retry_has_hand_shan = false
	_bagua_retry_excludes_bagua = false
	_qilin_request_count = 0
	_qilin_mount_uid = -1
	_qilin_candidate_present = false


## 验证无懈可击同时询问全部存活玩家、公共高亮不泄露候选，并由最先提交合法牌的玩家取得结算权。
func _test_simultaneous_wuxie_first_response_wins() -> bool:
	_scenario = "simultaneous_wuxie"
	_reset_state(3)
	# 目标武将 ID；询问文本必须显示“丹恒”，不能显示测试玩家名或 AI 控制权前缀。
	_controller.state.get_player(1).character_id = "dan_heng"
	# 一号玩家无懈；虽然请求更早登记，但本测试故意让三号玩家先提交。
	var earlier_counter: CardInstance = _add_hand_card(0, "wuxie", "spade", 11)
	# 三号玩家无懈；其提交先到达后应立即关闭同轮其他请求并成为唯一响应者。
	var winning_counter: CardInstance = _add_hand_card(2, "wuxie", "club", 12)
	# 目标手牌；若原过河拆桥被成功抵消，该实体必须继续留在目标手中。
	var protected_card: CardInstance = _add_hand_card(1, "shan", "heart", 2)
	_simultaneous_protected_uid = protected_card.uid
	# 原锦囊实体；通过真实 CardUseEvent 建立逐目标无懈链。
	var trick_card: CardInstance = _add_hand_card(0, "guohe", "spade", 3)
	_controller._execute_card_use(0, trick_card, [1])
	# 本轮公共高亮名单；没有无懈的二号玩家也必须与两名持牌玩家一起高亮。
	var public_responder_ids: Array = (_controller.state.simultaneous_response_display.get("responder_ids", []) as Array).duplicate()
	if public_responder_ids != [0, 1, 2] or _controller._pending_negation_choices.size() != 2 or _simultaneous_negation_requests.size() != 2:
		return _fail("simultaneous_wuxie_open=%s:%d:%d" % [public_responder_ids, _controller._pending_negation_choices.size(), _simultaneous_negation_requests.size()])
	# 三号玩家当前请求；按 chooser_id 定位，不能依赖请求登记顺序作为结算优先级。
	var winning_request: Dictionary = {}
	# 一号玩家旧请求 ID；成功响应后该请求必须立即失效。
	var earlier_request_id: int = -1
	for request_data: Dictionary in _simultaneous_negation_requests:
		if str(request_data.get("prompt", "")).contains("测试玩家2") or not str(request_data.get("prompt", "")).contains("丹恒"):
			return _fail("simultaneous_wuxie_prompt=%s" % request_data.get("prompt", ""))
		if int(request_data.get("chooser_id", -1)) == 2:
			winning_request = request_data
		elif int(request_data.get("chooser_id", -1)) == 0:
			earlier_request_id = int(request_data.get("request_id", -1))
	if winning_request.is_empty() or earlier_request_id < 0:
		return _fail("simultaneous_wuxie_requests=%s" % [_simultaneous_negation_requests])
	# 先提交三号玩家的合法无懈；同轮一号玩家即使更早收到请求也不能再覆盖本次结果。
	var winning_action: PlayerAction = PlayerAction.new("choose_cards", 2)
	winning_action.payload = {"request_id":int(winning_request.get("request_id", -1)), "selected_card_uids":[winning_counter.uid]}
	if not _controller.submit_action(winning_action) or _controller._pending_negation_choices.has(earlier_request_id):
		return _fail("simultaneous_wuxie_first_submit")
	if _controller.state.get_player(2).find_hand_card(winning_counter.uid) != null or _controller.state.get_player(0).find_hand_card(earlier_counter.uid) == null:
		return _fail("simultaneous_wuxie_consumption")
	# 下一轮只有仍持有无懈的一号玩家需要私有请求；其再次响应形成偶数链并恢复原锦囊。
	var counter_round_request: Dictionary = {}
	for request_variant: Variant in _controller._pending_negation_choices.values():
		var request_data: Dictionary = request_variant as Dictionary
		if int(request_data.get("chooser_id", -1)) == 0:
			counter_round_request = request_data
			break
	if counter_round_request.is_empty():
		return _fail("simultaneous_wuxie_counter_round")
	# 第二张无懈动作；成功后下一轮已无候选，控制器必须立即完成链并恢复过河拆桥选牌。
	var counter_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	counter_action.payload = {"request_id":int(counter_round_request.get("request_id", -1)), "selected_card_uids":[earlier_counter.uid]}
	if not _controller.submit_action(counter_action):
		return _fail("simultaneous_wuxie_counter_submit")
	if not await _wait_until_card_finalized(trick_card.uid):
		return _fail("simultaneous_wuxie_finalize")
	if _controller.state.get_player(1).find_hand_card(protected_card.uid) != null or not _controller.state.discard_pile.has(earlier_counter) or not _controller.state.discard_pile.has(winning_counter) or not _controller.state.discard_pile.has(protected_card) or not _controller.state.discard_pile.has(trick_card):
		return _fail("simultaneous_wuxie_result")
	return true


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
	# 逐目标触发历史；无名杀先让全部目标经过同名阶段，再进入下一个阶段，不能按单目标连续写完四个时机。
	var target_stage_order: Array[String] = []
	for history_record_variant: Variant in _controller.event_scheduler.get_event_history():
		# 当前历史事件摘要；只筛选四个 useCardTo 阶段并保留目标 ID 形成稳定顺序断言。
		# 当前历史记录；真实子事件拥有 start/step/finish 三类记录，顺序断言只读取每个事件唯一的 start。
		var history_record: Dictionary = history_record_variant as Dictionary
		if str(history_record.get("kind", "")) != "start":
			continue
		# 当前事件摘要；只筛选四个 useCardTo 阶段并保留目标 ID 形成稳定顺序断言。
		var event_data: Dictionary = history_record.get("event", {}) as Dictionary
		# 当前事件稳定名称；仅四组逐目标时机进入顺序数组。
		var event_name: String = str(event_data.get("name", ""))
		if event_name in ["useCardToPlayer", "useCardToTarget", "useCardToPlayered", "useCardToTargeted"]:
			target_stage_order.append("%s:%d" % [event_name, int((event_data.get("context", {}) as Dictionary).get("target_id", -1))])
	var expected_target_stage_order: Array[String] = ["useCardToPlayer:1", "useCardToPlayer:2", "useCardToTarget:1", "useCardToTarget:2", "useCardToPlayered:1", "useCardToPlayered:2", "useCardToTargeted:1", "useCardToTargeted:2"]
	if target_stage_order != expected_target_stage_order:
		return _fail("use_card_target_stage_order=%s" % [target_stage_order])
	if not _assert_real_card_use_event_tree():
		return false
	return true


## 验证目标时机可动态追加目标、directHit 会跳过响应、取消目标只排除该目标且其他目标继续。
func _test_dynamic_targets_direct_hit_and_exclusion() -> bool:
	_scenario = "dynamic_targets"
	_reset_state(3)
	# 动态目标触发器；useCardToPlayer 为原目标追加二号目标，后续四组时机会重新读取最新数组。
	_controller.trigger_manager.subscribe("useCardToPlayer", self, _append_dynamic_card_target, 0, -1, "global")
	# 目标后段触发器；一号目标获得直击，二号目标被取消并进入 excluded 集合。
	_controller.trigger_manager.subscribe("useCardToTargeted", self, _apply_dynamic_target_flags, 0, -1, "global")
	# 测试【杀】；初始只声明一号目标，二号目标完全由真实目标时机动态加入。
	var slash: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	_controller._execute_card_use(0, slash, [1])
	if not await _wait_until_card_finalized(slash.uid):
		return _fail("dynamic_targets_timeout")
	# 一号目标因直击不能响应并受到1点伤害；二号目标被排除且保持4点体力。
	if _controller.state.get_player(1).hp != 3 or _controller.state.get_player(2).hp != 4:
		return _fail("dynamic_target_hp=%d:%d" % [_controller.state.get_player(1).hp, _controller.state.get_player(2).hp])
	# 实际 content 数量；只有未排除的一号目标进入牌效，二号目标不能伪造 content 历史。
	var content_start_count: int = 0
	# 二号目标完整时机计数；动态加入后必须经历四组 useCardTo 时机，再由最后一组取消。
	var added_target_timing_count: int = 0
	for record: Dictionary in _controller.event_scheduler.get_event_history():
		if str(record.get("kind", "")) != "start":
			continue
		# 当前事件摘要；只读取稳定名称和可序列化目标 ID。
		var event_data: Dictionary = record.get("event", {}) as Dictionary
		# 当前事件稳定名称；只统计 content 与四组目标时机。
		var event_name: String = str(event_data.get("name", ""))
		if event_name == "content":
			content_start_count += 1
		if event_name in CardUseEventService.TARGET_TIMING_NAMES and int((event_data.get("context", {}) as Dictionary).get("target_id", -1)) == 2:
			added_target_timing_count += 1
	if content_start_count != 1 or added_target_timing_count != 4:
		return _fail("dynamic_target_events=%d:%d" % [content_start_count, added_target_timing_count])
	return true


## 在第一组逐目标时机为当前牌追加二号目标；重复执行时保持目标数组去重。
func _append_dynamic_card_target(event: RuleEvent) -> void:
	if event.target_id != 1:
		return
	# 当前目标数组；修改 RuleEvent 数据后会写回 CardUseEvent 共享上下文并供下一次 redo 读取。
	var target_ids: Array = event.data.get("target_ids", []) as Array
	if not target_ids.has(2):
		target_ids.append(2)
	event.data["target_ids"] = target_ids


## 在 useCardToTargeted 为一号目标写入直击，并取消二号目标以验证 excluded 只影响对应 content。
func _apply_dynamic_target_flags(event: RuleEvent) -> void:
	if event.target_id == 1:
		# 当前直击目标集合；加入一号目标后【杀】跳过【闪】询问但继续防具与伤害流程。
		var direct_hit_target_ids: Array = event.data.get("direct_hit_target_ids", []) as Array
		if not direct_hit_target_ids.has(1):
			direct_hit_target_ids.append(1)
		event.data["direct_hit_target_ids"] = direct_hit_target_ids
	elif event.target_id == 2:
		event.cancel()


## 验证使用牌各时机、逐目标内容、响应选择和 ordering 回收都属于真实可暂停事件树，而非迁移期摘要。
func _assert_real_card_use_event_tree() -> bool:
	# 完整运行时历史；本场景只有一张主动使用的南蛮入侵，响应牌通过 respond 子流程记录。
	var history: Array[Dictionary] = _controller.event_scheduler.get_event_history()
	# 原 CardUseEvent ID；所有源码级时机和 contentAfter 必须直接关联该父事件。
	var card_use_event_id: int = -1
	# 实际进入效果的 content 子事件 ID；被无懈的目标和继续结算的目标各有一条。
	var content_event_ids: Array[int] = []
	# 唯一 contentAfter 数量；多目标与多次响应都不能重复创建。
	var content_after_count: int = 0
	# orderingDiscard 事件 ID；必须位于 CardUseEvent 的 after 队列并成为 cardsDiscard 的直接父事件。
	var ordering_discard_event_id: int = -1
	# 是否找到直接挂在目标 content 下的响应选择；证明选择暂停归属真实牌效位置。
	var found_nested_response_choice: bool = false
	# 响应选择启动标记；选择请求即使立即暂停，也必须拥有真实 start 历史而不是只有 choice_requested 摘要。
	var found_started_nested_response_choice: bool = false
	# cardsDiscard 开始历史序号；用于确认实体回收发生在 contentAfter 之后、CardUseEvent 最终化之前。
	var cards_discard_start_sequence: int = -1
	# contentAfter 开始历史序号；本用例必须严格早于 cardsDiscard。
	var content_after_start_sequence: int = -1
	# CardUseEvent 最终完成历史序号；after 子树未完成前不得写入。
	var card_use_finish_sequence: int = -1
	for record: Dictionary in history:
		# 当前事件摘要；所有断言只读取可序列化历史，不访问调度器内部事件对象。
		var event_data: Dictionary = record.get("event", {}) as Dictionary
		# 当前历史类型；start 用于唯一事件计数，finish 用于验证 after 队列完成时机。
		var record_kind: String = str(record.get("kind", ""))
		# 当前事件稳定名称；与无名杀源码时机保持一致。
		var event_name: String = str(event_data.get("name", ""))
		if record_kind == "start" and event_name == "CardUseEvent":
			card_use_event_id = int(event_data.get("event_id", -1))
		if record_kind == "start" and event_name == "content":
			content_event_ids.append(int(event_data.get("event_id", -1)))
		if record_kind == "start" and event_name == "contentAfter":
			content_after_count += 1
			content_after_start_sequence = int(record.get("sequence", -1))
		if record_kind == "start" and event_name == "orderingDiscard":
			ordering_discard_event_id = int(event_data.get("event_id", -1))
		if record_kind == "start" and event_name == "cardsDiscard":
			cards_discard_start_sequence = int(record.get("sequence", -1))
		if record_kind == "finish" and event_name == "CardUseEvent":
			card_use_finish_sequence = int(record.get("sequence", -1))
	if card_use_event_id < 0 or content_event_ids.size() != 2 or content_after_count != 1 or ordering_discard_event_id < 0:
		return _fail("real_card_use_counts=%d/%s/%d/%d" % [card_use_event_id, content_event_ids, content_after_count, ordering_discard_event_id])
	for record: Dictionary in history:
		# 当前事件摘要；第二轮检查在父事件 ID 已知后验证全部结构关系。
		var event_data: Dictionary = record.get("event", {}) as Dictionary
		# 当前历史记录类型；父子关系只在事件开始或请求登记时读取。
		var record_kind: String = str(record.get("kind", ""))
		# 当前事件稳定名称；用于按拓扑节点类型选择断言。
		var event_name: String = str(event_data.get("name", ""))
		if record_kind == "start" and event_name in CardUseEventService.USE_TIMING_NAMES + CardUseEventService.TARGET_TIMING_NAMES + ["contentBefore", "content", "contentAfter", "orderingDiscard"] and int(event_data.get("parent_id", -2)) != card_use_event_id:
			return _fail("card_use_child_parent=%s:%s" % [event_name, event_data.get("parent_id", -2)])
		if record_kind == "choice_requested" and event_name == "chooseToRespond" and content_event_ids.has(int(event_data.get("parent_id", -1))):
			found_nested_response_choice = true
		if record_kind == "start" and event_name == "chooseToRespond" and content_event_ids.has(int(event_data.get("parent_id", -1))):
			found_started_nested_response_choice = true
		if record_kind == "start" and event_name == "cardsDiscard" and int(event_data.get("parent_id", -2)) != ordering_discard_event_id:
			return _fail("cards_discard_parent=%s" % event_data.get("parent_id", -2))
	if not found_nested_response_choice or not found_started_nested_response_choice:
		return _fail("response_choice_not_nested_in_content=%s/%s" % [found_nested_response_choice, found_started_nested_response_choice])
	if content_after_start_sequence < 0 or cards_discard_start_sequence <= content_after_start_sequence or card_use_finish_sequence <= cards_discard_start_sequence:
		return _fail("card_use_after_order=%d/%d/%d" % [content_after_start_sequence, cards_discard_start_sequence, card_use_finish_sequence])
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


## 验证目标需要两张桃时由同一救援者连续收到2次、1次提示，成功后不会重新询问已经完成的其他角色。
func _test_dying_continuous_peaches_in_single_round() -> bool:
	_scenario = "dying_multiple"
	_dying_required_recover_history.clear()
	_dying_responder_history.clear()
	_multi_peach_uids.clear()
	_reset_state(3)
	# 第一张救援桃；0号玩家在目标体力为-1时先打出，使目标回复至0。
	var first_peach: CardInstance = _add_hand_card(0, "tao", "heart", 4)
	# 第二张救援桃；同一玩家应在紧接着的下一次询问中打出，使目标回复至1。
	var second_peach: CardInstance = _add_hand_card(0, "tao", "diamond", 4)
	_multi_peach_uids.assign([first_peach.uid, second_peach.uid])
	_controller.damage(2, 1, 5, "normal", "sha")
	if not await _wait_until_no_card_choice():
		return _fail("dying_multiple_timeout")
	# 获救目标；固定从4点受到5点伤害到-1，再由两张桃回复到1。
	var target: PlayerState = _controller.state.get_player(1)
	if _dying_required_recover_history != [2, 1] or _dying_responder_history != [0, 0]:
		return _fail("dying_multiple_prompts=%s:%s" % [_dying_required_recover_history, _dying_responder_history])
	if target.hp != 1 or target.dying or not target.alive or not _controller.state.discard_pile.has(first_peach) or not _controller.state.discard_pile.has(second_peach):
		return _fail("dying_multiple_result=%d:%s:%s" % [target.hp, target.dying, target.alive])
	return true


## 验证桃园结义的逐目标无懈询问全部结束后才发布新出牌请求，剩余合法手牌不会因快照被覆盖而全部灰显。
func _test_taoyuan_restores_play_choice_after_multiple_responses() -> bool:
	_scenario = "taoyuan_resume"
	_taoyuan_negation_request_count = 0
	_reset_state(2)
	_controller.state.get_player(0).hp = 3
	_controller.state.get_player(1).hp = 3
	# 桃园结义实体；通过真实 chooseToUse 动作提交，覆盖玩家实际触发卡死的完整入口。
	var taoyuan: CardInstance = _add_hand_card(0, "taoyuan", "heart", 1)
	# 本地无懈可击；玩家对桃园的两个目标都明确取消，因此会连续产生两次异步响应窗口。
	var wuxie: CardInstance = _add_hand_card(0, "wuxie", "spade", 11)
	# 结算后应继续可用的杀；新的 chooseToUse 必须把该 UID 重新公开给界面。
	var slash: CardInstance = _add_hand_card(0, "sha", "club", 7)
	# 长期规则根事件；真实出牌请求和桃园 CardUseEvent 都必须挂在同一对局事件树下。
	var root_event: GameEvent = _controller.event_scheduler.create_event("RootGameEvent", "root", [], {"scenario":"taoyuan_resume"})
	_controller._runtime_root_event_id = root_event.event_id
	_controller.event_scheduler.begin_root(root_event.event_id, true)
	_controller.state.current_event_id = root_event.event_id
	_controller._begin_play_choice(0)
	# 桃园使用动作；全体目标由规则层自动展开，不由测试伪造目标数组。
	var use_action: PlayerAction = PlayerAction.new("use_card", 0, taoyuan.uid)
	if not _controller.submit_action(use_action):
		return _fail("taoyuan_submit")
	if not await _wait_until_card_finalized(taoyuan.uid):
		return _fail("taoyuan_finalize_timeout")
	# 最新出牌请求；必须是结算完成后新建的活动请求，并包含仍可使用的杀。
	var play_request: Dictionary = _controller.state.current_choice_request
	var play_card_ids: Array = play_request.get("card_ids", []) as Array
	if _taoyuan_negation_request_count != 2 or not _controller._has_active_play_choice() or int(play_request.get("request_id", -1)) != _controller._play_choice_request_id or str(play_request.get("choice_type", "")) != "use" or not play_card_ids.has(slash.uid):
		return _fail("taoyuan_play_choice=%d:%s:%s" % [_taoyuan_negation_request_count, _controller._has_active_play_choice(), play_request])
	if _controller.state.get_player(0).hp != 4 or _controller.state.get_player(1).hp != 4 or _controller.state.get_player(0).find_hand_card(wuxie.uid) == null:
		return _fail("taoyuan_resolution_state")
	return true


## 验证普通锦囊的受无懈字段不能让其作为无懈牌打出，只有 negate 牌效能提供 wuxie 响应模式。
func _test_response_card_pattern_filter() -> bool:
	_scenario = "response_pattern_filter"
	_reset_state(2)
	# 顺手牵羊实体；它可被无懈响应，但自身不能作为无懈响应牌消耗。
	var snatch: CardInstance = _add_hand_card(0, "shunshou", "spade", 3)
	# 真正的无懈可击实体；用于确认过滤没有误伤合法响应牌。
	var wuxie: CardInstance = _add_hand_card(0, "wuxie", "club", 12)
	if not _controller._get_provided_response_pattern(GameDatabase.get_card("shunshou")).is_empty() or _controller._get_provided_response_pattern(GameDatabase.get_card("wuxie")) != "wuxie":
		return _fail("response_pattern_mapping")
	if _controller._consume_response_card_uid(0, snatch.uid, "wuxie") != null or _controller.state.get_player(0).find_hand_card(snatch.uid) == null:
		return _fail("snatch_consumed_as_wuxie")
	if _controller._consume_response_card_uid(0, wuxie.uid, "wuxie") != wuxie or not _controller.state.discard_pile.has(wuxie):
		return _fail("wuxie_response_rejected")
	return true


## 验证满体力角色仍可在出牌阶段对自己使用【酒】，并获得本回合下一张【杀】固定+1伤害加值。
func _test_full_health_wine_use() -> bool:
	_scenario = "full_health_wine"
	_reset_state(2)
	# 满体力使用者的【酒】实体；初始4/4体力不得阻止正常增益用途。
	var wine: CardInstance = _add_hand_card(0, "jiu", "diamond", 9)
	# 满体力【酒】使用校验结果；空字符串表示规则层接受唯一自身目标。
	var validation_error: String = _controller.card_rules.validate_use(0, wine, [0])
	if not validation_error.is_empty():
		return _fail("full_health_wine_validation=%s" % validation_error)
	_controller._execute_card_use(0, wine, [0])
	if not await _wait_until_card_finalized(wine.uid):
		return _fail("full_health_wine_timeout")
	# 满体力使用者最终状态；体力保持4，酒次数与下一杀加值都已写入，实体进入弃牌堆。
	var player: PlayerState = _controller.state.get_player(0)
	if player.hp != 4 or not player.wine_used or player.wine_bonus != 1 or not _controller.state.discard_pile.has(wine):
		return _fail("full_health_wine_result=%d:%s:%d" % [player.hp, player.wine_used, player.wine_bonus])
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
	_controller._notify_equipment_card_consumed(1, used_black_card, true)
	_controller.process_next_equipment_trigger()
	if not await _wait_until_no_card_choice():
		return _fail("silver_moon_timeout")
	# 当前回合0号角色是银月枪持有者的敌方目标；未打出闪后受到固定1点普通伤害。
	var target: PlayerState = _controller.state.get_player(0)
	if _silver_moon_request_count != 1 or target.hp != 3:
		return _fail("silver_moon_result=%d:%d" % [_silver_moon_request_count, target.hp])
	return true


## 验证出牌阶段点击丈八蛇矛后可以选择两张普通手牌生成无花色虚拟【杀】，材料弃置且装备留在原槽位。
func _test_zhangba_play_uses_two_materials() -> bool:
	_scenario = "zhangba_play"
	_reset_state(2)
	# 攻击者装备的丈八蛇矛；动作 card_uid 必须引用该实体而不是任一材料。
	var zhangba: CardInstance = CardInstance.new("zhangba", "spade", 12)
	zhangba.zone = "equipment"
	zhangba.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = zhangba
	_zhangba_uid = zhangba.uid
	# 第一张丈八材料；任意牌名均可作为普通手牌费用。
	var first_material: CardInstance = _add_hand_card(0, "shan", "heart", 2)
	# 第二张丈八材料；与第一张共同组成无花色、无点数的虚拟杀。
	var second_material: CardInstance = _add_hand_card(0, "tao", "diamond", 3)
	_zhangba_material_uids.assign([first_material.uid, second_material.uid])
	_controller._begin_play_choice(0)
	# 丈八装备候选；当前有两张普通手牌且存在合法杀目标，应进入 chooseToUse 的 card_ids。
	if not _controller.get_play_phase_equipment_action_uids(0).has(zhangba.uid):
		return _fail("zhangba_play_equipment_not_available")
	# 丈八标准动作；材料和目标都由核心再次校验，不能依赖界面预览。
	var action: PlayerAction = PlayerAction.new("use_zhangba", 0, zhangba.uid, [1])
	action.payload = {"material_card_uids":_zhangba_material_uids.duplicate()}
	if not _controller.submit_action(action):
		return _fail("zhangba_play_submit")
	if not await _wait_until_no_card_choice():
		return _fail("zhangba_play_timeout")
	# 虚拟杀结果；目标受到1点伤害，两张材料进入弃牌堆，丈八本身和处理区代理均保持正确终点。
	var virtual_card_data: Dictionary = _last_presentation.get("card_data", {}) as Dictionary
	if _controller.state.get_player(1).hp != 3 or not _controller.state.discard_pile.has(first_material) or not _controller.state.discard_pile.has(second_material) or _controller.state.get_player(0).equipment.get("weapon") != zhangba or not _controller.state.processing_area.is_empty() or str(virtual_card_data.get("definition_id", "")) != "sha" or str(virtual_card_data.get("suit", "")) != "none" or int(virtual_card_data.get("rank", -1)) != 0:
		return _fail("zhangba_play_result=%d/%s/%s" % [_controller.state.get_player(1).hp, _controller.state.processing_area, virtual_card_data])
	return true


## 验证响应【杀】的窗口会把丈八蛇矛作为可点击装备候选，并只在提交两张普通手牌材料后视为成功打出【杀】。
func _test_zhangba_response_uses_two_materials() -> bool:
	_scenario = "zhangba_response"
	_zhangba_response_has_equipment = false
	_reset_state(2)
	# 响应者装备的丈八蛇矛；南蛮入侵要求其打出【杀】时应向右移动并允许点击。
	var zhangba: CardInstance = CardInstance.new("zhangba", "spade", 12)
	zhangba.zone = "equipment"
	zhangba.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = zhangba
	_zhangba_uid = zhangba.uid
	# 两张响应材料；均为普通手牌且自身不具有 sha 响应模式，确保本次只能通过丈八成功响应。
	var first_material: CardInstance = _add_hand_card(1, "shan", "club", 4)
	var second_material: CardInstance = _add_hand_card(1, "tao", "heart", 5)
	_zhangba_material_uids.assign([first_material.uid, second_material.uid])
	# 南蛮入侵实体；直接进入正式 CardUseEvent，目标响应完成后仍需正常收尾。
	var nanman: CardInstance = _add_hand_card(0, "nanman", "spade", 7)
	_controller._execute_card_use(0, nanman, [1])
	if not await _wait_until_card_finalized(nanman.uid):
		return _fail("zhangba_response_timeout")
	if not _zhangba_response_has_equipment or _controller.state.get_player(1).hp != 4 or not _controller.state.discard_pile.has(first_material) or not _controller.state.discard_pile.has(second_material) or _controller.state.get_player(1).equipment.get("weapon") != zhangba:
		return _fail("zhangba_response_result=%s/%d" % [_zhangba_response_has_equipment, _controller.state.get_player(1).hp])
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


## 验证木牛流马“粮”不参与弃牌阶段手牌上限计算，普通手牌未超当前体力时不会要求额外弃置粮牌。
func _test_wooden_ox_storage_excluded_from_hand_limit() -> bool:
	_scenario = "wooden_ox_hand_limit"
	_reset_state(2)
	# 当前回合玩家；1点体力对应1张普通手牌上限。
	var player: PlayerState = _controller.state.get_player(0)
	player.hp = 1
	# 唯一普通手牌；数量正好等于手牌上限，不应进入弃牌选择。
	var hand_card: CardInstance = _add_hand_card(0, "shan", "heart", 2)
	# 第一张木牛粮牌；即使与普通手牌共同显示，也不计入手牌上限。
	var first_stored_card: CardInstance = CardInstance.new("sha", "spade", 7)
	first_stored_card.zone = "wooden_ox"
	first_stored_card.owner_id = 0
	player.wooden_ox_storage.append(first_stored_card)
	# 第二张木牛粮牌；两张粮共同证明弃牌数只读取普通 hand 数组。
	var second_stored_card: CardInstance = CardInstance.new("tao", "heart", 3)
	second_stored_card.zone = "wooden_ox"
	second_stored_card.owner_id = 0
	player.wooden_ox_storage.append(second_stored_card)
	_controller._end_play_phase(0)
	if _controller.has_pending_card_choice() or player.find_hand_card(hand_card.uid) == null or player.wooden_ox_storage != [first_stored_card, second_stored_card] or _controller.state.discard_pile.has(first_stored_card) or _controller.state.discard_pile.has(second_stored_card):
		return _fail("wooden_ox_hand_limit")
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


## 验证八卦阵黑色判定只令本次装备响应失败，原【闪】响应继续开放并允许玩家改用手牌【闪】。
func _test_bagua_failure_allows_hand_shan() -> bool:
	_scenario = "bagua_retry"
	_reset_state(2)
	# 攻击者实体【杀】；通过正式使用流程建立处理区父牌与目标响应上下文。
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	# 防守者手牌【闪】；八卦阵失败后的第二次请求必须保留并最终消费该实体。
	var hand_shan: CardInstance = _add_hand_card(1, "shan", "heart", 2)
	_bagua_hand_shan_uid = hand_shan.uid
	# 防守者八卦阵；装备只作为响应入口，黑色判定后仍留在防具槽。
	var bagua_card: CardInstance = CardInstance.new("bagua", "club", 2)
	bagua_card.zone = "equipment"
	bagua_card.owner_id = 1
	_controller.state.get_player(1).equipment["armor"] = bagua_card
	_bagua_uid = bagua_card.uid
	# 八卦阵判定牌；数组末尾为牌堆顶，黑桃结果令虚拟【闪】生成失败。
	var black_judgment_card: CardInstance = CardInstance.new("tao", "spade", 9)
	black_judgment_card.zone = "draw_pile"
	_controller.state.draw_pile.append(black_judgment_card)
	_controller._execute_card_use(0, slash_card, [1])
	if not await _wait_until_card_finalized(slash_card.uid):
		return _fail("bagua_retry_timeout")
	# 防守结果；两次请求后手牌【闪】与黑色判定牌都进入弃牌堆，目标不受伤且八卦阵仍在装备区。
	var defender: PlayerState = _controller.state.get_player(1)
	if _bagua_response_request_count != 2 or not _bagua_retry_has_hand_shan or not _bagua_retry_excludes_bagua or defender.hp != defender.max_hp or defender.find_hand_card(hand_shan.uid) != null or defender.equipment.get("armor") != bagua_card or not _controller.state.discard_pile.has(hand_shan) or not _controller.state.discard_pile.has(black_judgment_card):
		return _fail("bagua_retry requests=%d hand=%s excluded=%s hp=%d discard=%s" % [_bagua_response_request_count, _bagua_retry_has_hand_shan, _bagua_retry_excludes_bagua, defender.hp, _controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid)])
	return true


## 验证麒麟弓使用强类型双坐骑槽查询，并可通过正式选择请求弃置目标坐骑。
func _test_qilin_mount_candidate_slots() -> bool:
	_scenario = "qilin_mount"
	_reset_state(2)
	# 攻击者麒麟弓；伤害后钩子会复核当前仍装备同一武器定义。
	var qilin_card: CardInstance = CardInstance.new("qilin", "heart", 5)
	qilin_card.zone = "equipment"
	qilin_card.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = qilin_card
	# 目标进攻坐骑；双槽查询必须返回该公开实体并交给标准选择协议。
	var mount_card: CardInstance = CardInstance.new("chitu", "heart", 5)
	mount_card.zone = "equipment"
	mount_card.owner_id = 1
	_controller.state.get_player(1).equipment["offensive_mount"] = mount_card
	_qilin_mount_uid = mount_card.uid
	# 仍在处理区的父【杀】；选择恢复会按该 UID 回到【杀】源码，再由通用组件交还麒麟弓。
	var parent_slash: CardInstance = CardInstance.new("sha", "spade", 7)
	parent_slash.zone = "processing"
	parent_slash.owner_id = -1
	_controller.state.processing_area.append(parent_slash)
	# 【杀】伤害后上下文；麒麟弓只读取攻击者和目标稳定 ID，不依赖界面节点。
	var damage_context: Dictionary = {"actor_id":0, "target_id":1, "parent_card_uid":parent_slash.uid}
	# 通用【杀】流程组件；用于向装备源码提供与正式结算相同的规则端口和状态引用。
	var slash_effect: SlashCardEffect = SlashCardEffect.new(_controller.effect_resolver)
	# 麒麟弓定义；直接调用伤害后公开钩子，覆盖原 get_equipment_candidates 第三个参数的运行时类型路径。
	var qilin_definition: CardDefinition = GameDatabase.get_card_definition("qilin")
	if qilin_definition == null or not qilin_definition.on_slash_damage_finished(slash_effect, damage_context):
		return _fail("qilin_choice_not_started")
	if not await _wait_until_no_card_choice():
		return _fail("qilin_choice_timeout")
	if _qilin_request_count != 1 or not _qilin_candidate_present or _controller.state.get_player(1).equipment.has("offensive_mount") or not _controller.state.discard_pile.has(mount_card):
		return _fail("qilin_choice request=%d candidate=%s equipment=%s" % [_qilin_request_count, _qilin_candidate_present, _controller.state.get_player(1).equipment])
	return true


## 验证八卦阵与延时锦囊共用的判定入口会公开展示牌面，并记录 judge、judgeResult 与 cardsDiscard 父子关系。
func _test_judgment_presentation_and_event_chain() -> bool:
	_scenario = "judgment_presentation"
	_reset_state(2)
	_last_presentation.clear()
	_last_discard_transfer.clear()
	# 牌堆顶判定牌；数组末尾作为顶部，红桃6同时覆盖八卦阵可成功读取的红色结果。
	var judgment_card: CardInstance = CardInstance.new("shan", "heart", 6)
	judgment_card.zone = "draw_pile"
	_controller.state.draw_pile.append(judgment_card)
	# 实际判定结果；必须返回同一实体，并在函数完成后位于弃牌堆。
	var resolved_card: CardInstance = _controller.perform_judgment(1, "八卦阵")
	if resolved_card != judgment_card or not _controller.state.discard_pile.has(judgment_card):
		return _fail("judgment_card_zone")
	# 判定表现；从公共弃牌锚点直接展示、没有使用牌目标，并明确接管随后到达的弃牌动画。
	var presented_card_data: Dictionary = _last_presentation.get("card_data", {}) as Dictionary
	if str(_last_presentation.get("event_name", "")) != "judge" or int(_last_presentation.get("actor_id", -2)) != -1 or not (_last_presentation.get("target_ids", []) as Array).is_empty() or not bool(_last_presentation.get("owns_discard_transfer", false)) or int(presented_card_data.get("uid", -1)) != judgment_card.uid:
		return _fail("judgment_presentation=%s" % _last_presentation)
	# 判定移牌历史；第一条进入处理区，第二条由独立 cardsDiscard 事件移入弃牌堆。
	if _controller.state.card_move_history.size() != 2:
		return _fail("judgment_move_count=%d" % _controller.state.card_move_history.size())
	var ordering_move: Dictionary = _controller.state.card_move_history[0] as Dictionary
	var discard_move: Dictionary = _controller.state.card_move_history[1] as Dictionary
	if str(ordering_move.get("from_zone", "")) != "draw_pile" or str(ordering_move.get("to_zone", "")) != "processing" or str(discard_move.get("from_zone", "")) != "processing" or str(discard_move.get("to_zone", "")) != "discard_pile":
		return _fail("judgment_move_chain=%s/%s" % [ordering_move, discard_move])
	if int(_last_discard_transfer.get("uid", -1)) != judgment_card.uid or str(_last_discard_transfer.get("source_zone", "")) != "processing":
		return _fail("judgment_transfer=%s" % _last_discard_transfer)
	# 运行时事件记录；judgeResult 与 cardsDiscard 都必须直接关联同一个 judge 父事件。
	var judgment_event_id: int = int(_last_presentation.get("event_id", -1))
	var found_judge_result: bool = false
	var found_cards_discard: bool = false
	for history_record_variant: Variant in _controller.event_scheduler.get_event_history():
		# 当前历史事件摘要；record_event 使用 kind=record 并保存完整父事件 ID。
		var event_data: Dictionary = (history_record_variant as Dictionary).get("event", {}) as Dictionary
		if str(event_data.get("name", "")) == "judgeResult" and int(event_data.get("parent_id", -2)) == judgment_event_id:
			found_judge_result = true
		if str(event_data.get("name", "")) == "cardsDiscard" and int(event_data.get("parent_id", -2)) == judgment_event_id:
			found_cards_discard = true
	if not found_judge_result or not found_cards_discard:
		return _fail("judgment_event_chain=%s/%s" % [found_judge_result, found_cards_discard])
	return true


## 验证判定区按“延时锦囊、该牌判定结果、下一张延时锦囊、下一张判定结果”逐张展示，启动调用不会瞬间结算全部牌。
func _test_delayed_judgment_presentation_sequence() -> bool:
	_scenario = "delayed_judgment_sequence"
	_reset_state(2)
	_controller.delayed_judgment_preview_seconds = 0.02
	_controller.delayed_judgment_result_pause_seconds = 0.02
	_controller.state.current_phase = "judgment"
	_controller.state.phase_index = 1
	# 第一张延时锦囊；红桃判定成功后不跳过出牌阶段。
	var indulgence: CardInstance = CardInstance.new("lebu", "heart", 6)
	indulgence.zone = "judgment"
	indulgence.owner_id = 0
	_controller.state.get_player(0).judgment_area.append(indulgence)
	# 第二张延时锦囊；梅花判定成功后不跳过摸牌阶段。
	var supply_shortage: CardInstance = CardInstance.new("bingliang", "club", 4)
	supply_shortage.zone = "judgment"
	supply_shortage.owner_id = 0
	_controller.state.get_player(0).judgment_area.append(supply_shortage)
	# 摸牌阶段的第一张保留牌；位于两张判定牌下方，判定完成后正常进入手牌。
	var draw_one: CardInstance = CardInstance.new("sha", "spade", 8)
	draw_one.zone = "draw_pile"
	_controller.state.draw_pile.append(draw_one)
	# 摸牌阶段的第二张保留牌；与第一张共同保证流程最后进入出牌阶段而非牌堆耗尽。
	var draw_two: CardInstance = CardInstance.new("shan", "diamond", 9)
	draw_two.zone = "draw_pile"
	_controller.state.draw_pile.append(draw_two)
	# 第二张延时锦囊的判定牌；梅花使兵粮寸断判定成功。
	var supply_judgment: CardInstance = CardInstance.new("tao", "club", 7)
	supply_judgment.zone = "draw_pile"
	_controller.state.draw_pile.append(supply_judgment)
	# 第一张延时锦囊的判定牌；数组末尾为牌堆顶，红桃先供乐不思蜀使用。
	var indulgence_judgment: CardInstance = CardInstance.new("tao", "heart", 6)
	indulgence_judgment.zone = "draw_pile"
	_controller.state.draw_pile.append(indulgence_judgment)
	_controller._process_judgment_area(0)
	# 启动调用只允许第一张延时锦囊进入展示；判定牌和第二张延时锦囊必须等待各自配置间隔。
	if _presentation_history.size() != 1 or str(_presentation_history[0].get("event_name", "")) != "delayedJudge" or int((_presentation_history[0].get("card_data", {}) as Dictionary).get("uid", -1)) != indulgence.uid or not _controller.state.get_player(0).judgment_area.has(supply_shortage):
		return _fail("delayed_judgment_immediate=%s" % [_presentation_history])
	# 四段0.02秒节拍加调度余量；完成后应进入正常出牌阶段并保留严格交替的四次表现。
	await get_tree().create_timer(0.12).timeout
	var presentation_keys: Array[String] = []
	for presentation: Dictionary in _presentation_history:
		# 单次表现键；稳定事件名与实体 UID 共同排除同一判定牌被重复展示。
		var card_data: Dictionary = presentation.get("card_data", {}) as Dictionary
		presentation_keys.append("%s:%d" % [str(presentation.get("event_name", "")), int(card_data.get("uid", -1))])
	var expected_keys: Array[String] = ["delayedJudge:%d" % indulgence.uid, "judge:%d" % indulgence_judgment.uid, "delayedJudge:%d" % supply_shortage.uid, "judge:%d" % supply_judgment.uid]
	if presentation_keys != expected_keys or _controller.state.current_phase != "play" or not _controller.state.get_player(0).judgment_area.is_empty() or not _controller.state.discard_pile.has(indulgence) or not _controller.state.discard_pile.has(supply_shortage):
		return _fail("delayed_judgment_sequence=%s phase=%s" % [presentation_keys, _controller.state.current_phase])
	_controller.delayed_judgment_preview_seconds = 1.00
	_controller.delayed_judgment_result_pause_seconds = 1.00
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
	# 本次装备响应材料；普通请求保持空数组，丈八蛇矛响应固定提交两张普通手牌 UID。
	var material_card_uids: Array[int] = []
	if _scenario == "simultaneous_wuxie" and kind == "trick_negation":
		_simultaneous_negation_requests.append(choice_data.duplicate(true))
		return
	elif _scenario == "simultaneous_wuxie" and kind == "discard_target":
		selected_uids = [_simultaneous_protected_uid]
	elif _scenario == "wuxie_aoe" and kind == "trick_negation":
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
	elif _scenario == "dying_multiple" and kind == "dying_response":
		_dying_required_recover_history.append(int(context.get("required_recover", -1)))
		_dying_responder_history.append(int(context.get("responder_id", -1)))
		# 当前合法桃候选；上一张被消费后，下一次询问只会命中数组中的下一张实体。
		var candidate_uids: Array[int] = []
		for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
			candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		for peach_uid: int in _multi_peach_uids:
			if candidate_uids.has(peach_uid):
				selected_uids = [peach_uid]
				break
	elif _scenario == "taoyuan_resume" and kind == "trick_negation":
		_taoyuan_negation_request_count += 1
		selected_uids = []
	elif _scenario == "zhuque" and kind == "zhuque_trigger":
		_zhuque_request_count += 1
		selected_uids = [_zhuque_uid]
	elif _scenario == "zhuque" and kind == "slash_response":
		selected_uids = []
	elif _scenario == "silver_moon" and kind == "equipment_trigger" and str(context.get("equipment_definition_id", "")) == "yinyue":
		_silver_moon_request_count += 1
		selected_uids = [_silver_moon_uid]
	elif _scenario == "silver_moon" and kind == "equipment_response" and str(context.get("equipment_definition_id", "")) == "yinyue":
		selected_uids = []
	elif _scenario == "zhangba_play" and kind == "slash_response":
		selected_uids = []
	elif _scenario == "zhangba_response" and kind == "aoe_response":
		# 当前响应候选 UID；丈八实体必须与普通响应牌共同使用统一候选协议。
		var candidate_uids: Array[int] = []
		for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
			candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		_zhangba_response_has_equipment = candidate_uids.has(_zhangba_uid)
		selected_uids = [_zhangba_uid]
		material_card_uids = _zhangba_material_uids.duplicate()
	elif _scenario == "bagua_retry" and kind == "slash_response":
		_bagua_response_request_count += 1
		# 当前八卦响应候选；首次主动选择防具，第二次验证防具被排除且手牌【闪】仍可使用。
		var candidate_uids: Array[int] = []
		for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
			candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		if _bagua_response_request_count == 1:
			selected_uids = [_bagua_uid]
		else:
			_bagua_retry_has_hand_shan = candidate_uids.has(_bagua_hand_shan_uid)
			_bagua_retry_excludes_bagua = not candidate_uids.has(_bagua_uid)
			selected_uids = [_bagua_hand_shan_uid]
	elif _scenario == "qilin_mount" and kind == "qilin_mount":
		_qilin_request_count += 1
		# 当前麒麟弓候选；目标进攻坐骑必须通过强类型槽位过滤进入请求。
		var candidate_uids: Array[int] = []
		for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
			candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		_qilin_candidate_present = candidate_uids.has(_qilin_mount_uid)
		selected_uids = [_qilin_mount_uid]
	else:
		_fail("unexpected_choice=%s:%s" % [_scenario, kind])
		return
	call_deferred("_submit_choice", int(choice_data.get("request_id", -1)), int(choice_data.get("chooser_id", -1)), selected_uids, material_card_uids)


## 捕获最新统一牌面表现事件；测试只读取深拷贝，不持有规则层可变对象。
func _on_card_presentation_requested(presentation_data: Dictionary) -> void:
	_last_presentation = presentation_data.duplicate(true)
	_presentation_history.append(presentation_data.duplicate(true))


## 捕获最新进入弃牌堆的真实区域移动；其他摸牌或获得动画不覆盖判定断言数据。
func _on_card_transfer_requested(card_data: Dictionary, _source_player_id: int, source_zone: String, _target_player_id: int, target_zone: String) -> void:
	if target_zone != "discard_pile":
		return
	_last_discard_transfer = card_data.duplicate(true)
	_last_discard_transfer["source_zone"] = source_zone


## 提交已捕获请求的标准选牌动作；请求 ID 与选择者均沿用只读请求快照。
func _submit_choice(request_id: int, chooser_id: int, selected_uids: Array[int], material_card_uids: Array[int] = []) -> void:
	if _failed:
		return
	# 标准选牌动作；规则层仍会复核请求归属、候选 UID、数量与实体当前区域。
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_uids.duplicate(), "material_card_uids":material_card_uids.duplicate()}
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
