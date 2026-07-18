extends Node

## 无名杀兼容时机回归测试。验证220个目录名称、四主动入口、四角色过滤及核心生命周期的真实派发顺序。

## 测试使用的权威控制器；按正式依赖结构装配，规则调用不会绕过统一时机服务。
var _controller: MatchController

## 当前测试使用的长期根事件 ID；阶段、伤害、移动与用牌摘要均挂在该根节点下。
var _root_event_id: int = -1

## 当前用例捕获的标准时机名称；每个独立断言开始前清空并重新订阅所需名称。
var _captured_timings: Array[String] = []


## 延迟一帧运行测试，确保自动加载内容数据库和控制器子节点已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行全部时机断言；任意失败立即以非0退出码结束无头测试。
func _run() -> void:
	await get_tree().process_frame
	_create_controller()
	_install_state()
	if not _test_catalog_and_active_entries():
		return
	if not _test_trigger_roles():
		return
	if not _test_damage_order():
		return
	if not _test_draw_and_move_order():
		return
	if not _test_phase_lifecycle_order():
		return
	if not _test_card_use_lifecycle_order():
		return
	print("RULE_TIMING_PASS catalog=220 active=4 roles=4 damage=10 move=20 card=12")
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


## 安装三人权威状态和长期根事件；玩家均保持存活，避免代表性伤害触发濒死或终局。
func _install_state() -> void:
	# 本测试权威状态；空对局 ID 令规则保持同步且不创建网络等待。
	var game_state: GameState = GameState.new()
	game_state.match_id = ""
	# 三名测试玩家；身份同时包含领袖、忠臣和反贼，普通1点伤害不会满足终局条件。
	var identities: Array[String] = ["leader", "loyalist", "rebel"]
	for player_id: int in range(3):
		# 当前测试玩家；基础体力固定4，所有角色保持正面、存活和已亮将状态。
		var player: PlayerState = PlayerState.new(player_id, "时机测试玩家%d" % (player_id + 1))
		player.identity = identities[player_id]
		player.character_id = "trailblazer"
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
	var root_event: GameEvent = _controller.event_scheduler.create_event("RuleTimingRoot", "root", [], {"match_id":"rule-timing-test"})
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
	_controller._pending_damage_finalizations.clear()
	_controller._started_phase_lifecycles.clear()


## 验证目录严格包含220个不重复事件，且主动技能只接受四种标准发动入口。
func _test_catalog_and_active_entries() -> bool:
	# 完整时机名称；目录函数必须返回可安全修改的新数组。
	var timing_names: Array[String] = RuleTimingCatalog.get_all_timing_names()
	# 已出现事件名集合；用于检查重复值而不依赖数组排序。
	var unique_names: Dictionary = {}
	for timing_name: String in timing_names:
		if unique_names.has(timing_name):
			return _fail("duplicate_timing=%s" % timing_name)
		unique_names[timing_name] = true
	if timing_names.size() != 220 or unique_names.size() != 220:
		return _fail("catalog_count=%d/%d" % [timing_names.size(), unique_names.size()])
	# 各分类实际数量；严格对应制作指南逐项列出的名称。
	var category_sizes: Array[int] = [
		RuleTimingCatalog.GAME_PHASE_TIMINGS.size(),
		RuleTimingCatalog.CARD_RESPONSE_TIMINGS.size(),
		RuleTimingCatalog.DAMAGE_TIMINGS.size(),
		RuleTimingCatalog.HEALTH_STATE_TIMINGS.size(),
		RuleTimingCatalog.CARD_MOVE_TIMINGS.size(),
		RuleTimingCatalog.JUDGE_COMPARE_TIMINGS.size(),
		RuleTimingCatalog.CHOICE_TIMINGS.size(),
		RuleTimingCatalog.SKILL_TIMINGS.size(),
		RuleTimingCatalog.MODE_TIMINGS.size(),
	]
	# 各分类预期数量；总和固定为220。
	var expected_category_sizes: Array[int] = [54, 48, 12, 35, 33, 10, 14, 8, 6]
	if category_sizes != expected_category_sizes:
		return _fail("category_sizes=%s" % [category_sizes])
	# 标准主动入口顺序；内容协议按出牌、使用、响应和选牌顺序保持稳定。
	var expected_entries: Array[String] = ["phaseUse", "chooseToUse", "chooseToRespond", "chooseCard"]
	if RuleTimingCatalog.ACTIVE_ENTRIES != expected_entries:
		return _fail("active_entries=%s" % [RuleTimingCatalog.ACTIVE_ENTRIES])
	# 显式复合主动技能；无效名称和重复名称必须被过滤。
	var configured_skill: SkillDefinition = SkillDefinition.new({"id":"configured", "ui_enabled":true, "enable":["phaseUse", "chooseToRespond", "phaseUse", "invalid"]})
	# 旧主动技能；没有 enable 时继续兼容出牌阶段按钮入口。
	var legacy_skill: SkillDefinition = SkillDefinition.new({"id":"legacy", "ui_enabled":true})
	if configured_skill.get_active_entries() != ["phaseUse", "chooseToRespond"] or not configured_skill.supports_active_entry("chooseToRespond") or configured_skill.supports_active_entry("chooseCard"):
		return _fail("configured_active_entries=%s" % [configured_skill.get_active_entries()])
	if legacy_skill.get_active_entries() != ["phaseUse"]:
		return _fail("legacy_active_entries=%s" % [legacy_skill.get_active_entries()])
	return true


## 验证 player、source、target、global 只命中正确持有者，并拒绝无效角色字符串。
func _test_trigger_roles() -> bool:
	# 独立触发器管理器；与控制器订阅隔离，便于精确验证角色过滤。
	var manager: TriggerManager = TriggerManager.new()
	# 实际命中标签；错误角色若执行会追加 wrong 并直接导致数组不匹配。
	var matches: Array[String] = []
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("player"), 0, 0, "player")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("source"), 0, 1, "source")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("target"), 0, 2, "target")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("global"), 0, -1, "global")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("wrong"), 0, 2, "player")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("wrong"), 0, 0, "source")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("wrong"), 0, 1, "target")
	manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("wrong"), 0, -1, "target")
	# 无效角色注册结果；必须在登记阶段明确失败，不能静默退化为全局触发。
	var invalid_registration_id: int = manager.subscribe("roleProbe", self, func(_event: RuleEvent) -> void: matches.append("wrong"), 0, 0, "invalid")
	# 测试事件；player为0、source为1、target为2，正好覆盖四种关系。
	var probe_event: RuleEvent = RuleEvent.new("roleProbe", 1, 2, {}, 0)
	manager.dispatch(probe_event, 0, [0, 1, 2])
	# 预期命中顺序；同优先级先按当前回合起点的座次，global 排在有效玩家之后。
	var expected_matches: Array[String] = ["player", "source", "target", "global"]
	if invalid_registration_id != -1 or matches != expected_matches:
		return _fail("trigger_roles=%s invalid=%d" % [matches, invalid_registration_id])
	return true


## 验证伤害从最早窗口到来源与后置窗口严格按无名杀顺序派发。
func _test_damage_order() -> bool:
	# 伤害标准顺序；damageZero 和 damageCancelled 属于互斥分支，不应出现在本次有效伤害中。
	var expected_order: Array[String] = ["damageBefore", "damageBegin", "damageBegin1", "damageBegin2", "damageBegin3", "damageBegin4", "damage", "damageSource", "damageEnd", "damageAfter"]
	_subscribe_capture(expected_order)
	_controller.damage(0, 1, 1, "normal", "rule_timing_test")
	# 受伤目标；有效1点伤害后体力应从4降至3，不触发濒死流程。
	var target: PlayerState = _controller.state.get_player(1)
	if _captured_timings != expected_order or target == null or target.hp != 3:
		return _fail("damage_order=%s hp=%s" % [_captured_timings, target.hp if target != null else -1])
	_controller.event_bus.unsubscribe_owner(self)
	return true


## 验证通用摸牌包裹获得牌时机，并验证手牌进入弃牌堆的复合 lose/discard 顺序。
func _test_draw_and_move_order() -> bool:
	# 测试摸牌实体；牌堆数组末尾是牌堆顶，初始属于公共摸牌堆。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	# 摸牌与获得牌嵌套顺序；获得牌完整结束后才派发 drawEnd 和 drawAfter。
	var expected_draw_order: Array[String] = ["drawBefore", "drawBegin", "gainBefore", "gainBegin", "gainEnd", "gainAfter", "drawEnd", "drawAfter"]
	_subscribe_capture(expected_draw_order)
	_controller.draw(1, 1, false)
	# 摸牌玩家；实体必须已经位于其手牌区并保留同一 UID。
	var drawing_player: PlayerState = _controller.state.get_player(1)
	if _captured_timings != expected_draw_order or drawing_player == null or drawing_player.find_hand_card(card.uid) == null:
		return _fail("draw_order=%s zone=%s" % [_captured_timings, card.zone])
	# 从手牌弃置的复合移动顺序；同一次移动同时属于 lose、discard 和 cardsDiscard 生命周期。
	var expected_discard_order: Array[String] = ["loseBefore", "discardBefore", "loseBegin", "discardBegin", "loseEnd", "discardEnd", "cardsDiscardEnd", "loseAfter", "discardAfter", "cardsDiscardAfter", "loseToDiscardpileAfter"]
	_subscribe_capture(expected_discard_order)
	# 弃置移动结果；空值表示前置时机或区域校验错误地阻止了有效移动。
	var discard_move: CardMoveEvent = _controller._move_card_with_timings(card, "discard_pile", -1, "rule_timing_test", _root_event_id)
	if discard_move == null or _captured_timings != expected_discard_order or not _controller.state.discard_pile.has(card):
		return _fail("discard_order=%s move=%s" % [_captured_timings, discard_move != null])
	_controller.event_bus.unsubscribe_owner(self)
	return true


## 验证阶段 Before、Begin、End、After 顺序，并确认取消前置窗口不会伪造结束时机。
func _test_phase_lifecycle_order() -> bool:
	# 正常出牌阶段生命周期；四个窗口都必须严格出现一次。
	var expected_use_phase_order: Array[String] = ["phaseUseBefore", "phaseUseBegin", "phaseUseEnd", "phaseUseAfter"]
	_subscribe_capture(expected_use_phase_order)
	_controller.event_bus.subscribe("phaseUseBefore", self, _write_phase_marker, 100)
	_controller.event_bus.subscribe("phaseUseBegin", self, _verify_phase_marker, 100)
	if not _controller._begin_phase_lifecycle("phaseUse", 0, {"turn_number":1}, _root_event_id):
		return _fail("phase_use_begin_cancelled")
	_controller._finish_phase_lifecycle("phaseUse", 0, {"turn_number":1}, _root_event_id)
	if _captured_timings != expected_use_phase_order:
		return _fail("phase_use_order=%s" % [_captured_timings])
	# 被取消弃牌阶段的可观察名称；Begin、End、After 均不得被补造。
	var discard_phase_names: Array[String] = ["phaseDiscardBefore", "phaseDiscardBegin", "phaseDiscardEnd", "phaseDiscardAfter"]
	_subscribe_capture(discard_phase_names)
	_controller.event_bus.subscribe("phaseDiscardBefore", self, _cancel_rule_event, 100)
	# 取消后的阶段开始结果；false 表示调用方应走 Cancelled 或 Skipped 分支。
	var discard_started: bool = _controller._begin_phase_lifecycle("phaseDiscard", 0, {"turn_number":1}, _root_event_id)
	_controller._finish_phase_lifecycle("phaseDiscard", 0, {"turn_number":1}, _root_event_id)
	if discard_started or _captured_timings != ["phaseDiscardBefore"]:
		return _fail("phase_cancel_order=%s started=%s" % [_captured_timings, discard_started])
	_controller.event_bus.unsubscribe_owner(self)
	return true


## 验证整牌前后窗口、五个使用时机、四个指定目标时机和【杀】逐目标生命周期顺序。
func _test_card_use_lifecycle_order() -> bool:
	# 使用牌声明后的五个时机；顺序直接决定动态目标修改的先后关系。
	var expected_use_timings: Array[String] = ["useCard0", "useCard1", "yingbian", "useCard2", "useCard"]
	# 指定目标的四个分组时机；每组会遍历全部当前目标后再进入下一组。
	var expected_target_timings: Array[String] = ["useCardToPlayer", "useCardToTarget", "useCardToPlayered", "useCardToTargeted"]
	if CardUseEventService.USE_TIMING_NAMES != expected_use_timings or CardUseEventService.TARGET_TIMING_NAMES != expected_target_timings:
		return _fail("card_use_catalog=%s/%s" % [CardUseEventService.USE_TIMING_NAMES, CardUseEventService.TARGET_TIMING_NAMES])
	# 虚拟测试牌 UID；只用于索引共享上下文，不会进入任何实体牌区域。
	var card_uid: int = 99001
	_controller._card_use_contexts[card_uid] = {
		"actor_id":0,
		"card_definition_id":"sha",
		"target_ids":[1],
		"excluded_target_ids":[],
		"direct_hit_target_ids":[],
		"custom_args":{},
	}
	# 未登记的父使用牌事件；私有生命周期函数只读取其 UID、事件 ID 和上下文。
	var use_event: GameEvent = GameEvent.new("CardUseEvent", [], {"card_uid":card_uid})
	use_event.event_id = _root_event_id
	# 整牌生命周期顺序；未取消时必须完整派发 Before、Begin、End、After。
	var expected_whole_order: Array[String] = ["useCardBefore", "useCardBegin", "useCardEnd", "useCardAfter"]
	_subscribe_capture(expected_whole_order)
	_controller._card_use_step_begin_lifecycle(use_event, _controller.event_scheduler)
	_controller._card_use_step_finish_lifecycle(use_event, _controller.event_scheduler)
	if _captured_timings != expected_whole_order:
		return _fail("whole_card_order=%s" % [_captured_timings])
	_controller._active_card_resolutions[card_uid] = {"current_target_id":1, "target_lifecycle_started":false, "target_lifecycle_finished":false}
	# 【杀】嵌套目标顺序；sha 内容结束后才退出 useCardTo 生命周期。
	var expected_target_order: Array[String] = ["useCardToBefore", "useCardToBegin", "shaBefore", "shaBegin", "shaEnd", "shaAfter", "useCardToEnd", "useCardToAfter"]
	_subscribe_capture(expected_target_order)
	# 重复开始与结束调用；幂等标记必须保证每个时机只派发一次。
	var first_begin_result: bool = _controller._begin_card_target_lifecycle(card_uid, 1, _root_event_id)
	var second_begin_result: bool = _controller._begin_card_target_lifecycle(card_uid, 1, _root_event_id)
	_controller._finish_card_target_lifecycle(card_uid, 1, _root_event_id)
	_controller._finish_card_target_lifecycle(card_uid, 1, _root_event_id)
	if not first_begin_result or not second_begin_result or _captured_timings != expected_target_order:
		return _fail("target_card_order=%s begin=%s/%s" % [_captured_timings, first_begin_result, second_begin_result])
	_controller._active_card_resolutions.erase(card_uid)
	_controller._card_use_contexts.erase(card_uid)
	_controller.event_bus.unsubscribe_owner(self)
	return true


## 清理旧捕获订阅并为指定名称注册普通事件监听；只记录真实派发到总线的名称。
func _subscribe_capture(event_names: Array[String]) -> void:
	_controller.event_bus.unsubscribe_owner(self)
	_captured_timings.clear()
	for event_name: String in event_names:
		_controller.event_bus.subscribe(event_name, self, _capture_timing)


## 捕获一条标准规则时机；事件对象只在当前同步回调内使用。
func _capture_timing(event: RuleEvent) -> void:
	_captured_timings.append(event.name)


## 取消当前规则事件；阶段取消用例借此验证未开始生命周期不会产生 End 与 After。
func _cancel_rule_event(event: RuleEvent) -> void:
	event.cancel()


## 在阶段 Before 写入测试标记；Begin 回调必须读取到同一生命周期传递的数据。
func _write_phase_marker(event: RuleEvent) -> void:
	event.data["phase_marker"] = "before_applied"


## 验证阶段 Begin 收到 Before 修改；缺失时追加稳定失败标签供顺序断言报告。
func _verify_phase_marker(event: RuleEvent) -> void:
	if str(event.data.get("phase_marker", "")) != "before_applied":
		_captured_timings.append("phaseDataMissing")


## 输出稳定失败原因并以非0状态结束测试；返回 false 便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	printerr("RULE_TIMING_FAIL %s" % reason)
	get_tree().quit(1)
	return false
