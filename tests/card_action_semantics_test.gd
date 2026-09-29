extends Node

## 卡牌动作语义专项回归。覆盖“使用 / 打出 / 弃置”三者的规则边界：
## 1. 成为【杀】的目标使用【闪】属于“使用”，不是“打出”，更不是“弃置”；
## 2. 【决斗】【南蛮入侵】要求打出的【杀】与【万箭齐发】要求打出的【闪】属于“打出”；
## 3. 使用与打出都必须经处理区进入弃牌堆，因此都不构成一次“弃置牌”动作，
##    都不得派发 cardsDiscardedBatchAfter，也就都不会触发【泛音】等“当你弃置牌时”类效果。

## 本测试共用的权威对局控制器；全部机制通过正式服务与卡牌源码入口执行。
var _controller: MatchController

## 捕获到的卡牌动作主体时机名序列；按派发顺序记录，用于断言“使用”与“打出”互斥。
var _captured_action_timings: Array[String] = []

## 捕获到的弃置批次数据；任何一次使用或打出都不应产生批次事件。
var _captured_batches: Array[Dictionary] = []

## 捕获到的公开日志文本；用于断言动词区分“使用了”与“打出了”。
var _captured_logs: Array[String] = []

## 捕获到的牌面表现与区域移牌统一下发顺序；用于断言表现认领严格早于处理区收尾移动。
var _presentation_timeline: Array[String] = []


## 延迟一帧开始回归，确保 GameDatabase 已完成目录扫描和静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部断言；任一失败立即以非零状态结束。
func _run() -> void:
	_create_controller()
	if not _test_action_resolution_contract():
		return
	if not _test_use_response_lifecycle():
		return
	if not _test_play_response_lifecycle():
		return
	if not _test_aoe_declares_play():
		return
	if not _test_slash_declares_use_and_skips_discard_effects():
		return
	print("CARD_ACTION_SEMANTICS_PASS use=useCard play=respond batch=0 through_processing=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器，并订阅动作时机、弃置批次与公开日志。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；动作主体时机与弃置批次共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；身份观察和目标态度查询保持正式实现。
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
	# 动作主体时机；只捕获决定“使用还是打出”的两个互斥时机。
	event_bus.subscribe("useCard", self, _on_use_card_timing)
	event_bus.subscribe("respond", self, _on_respond_timing)
	# 弃置批次时机；使用与打出都不应该出现在这里。
	event_bus.subscribe("cardsDiscardedBatchAfter", self, _on_discard_batch)
	# 牌面表现与区域移牌；两者共用一条时间线，用于锁定“认领先于收尾”的顺序约束。
	_controller.card_presentation_requested.connect(_on_card_presentation_requested)
	_controller.card_transfer_requested.connect(_on_card_transfer_requested)
	_controller.log_added.connect(_on_log_added)


## 为单项测试创建最小权威状态并重建全部规则服务；角色身份公开以获得确定AI态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "card-action-semantics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "动作语义测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	# 摸牌堆；伤害、回复与摸牌断言需要可用的实体牌。
	for card_index: int in range(20):
		_controller.state.draw_pile.append(CardInstance.new("shan", "heart", card_index % 13 + 1))
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()
	# 捕获容器；每个场景都必须从干净基线开始断言。
	_captured_action_timings.clear()
	_captured_batches.clear()
	_captured_logs.clear()
	_presentation_timeline.clear()
	# 卡牌效果调度器；【杀】与群体锦囊的牌效入口都要求它存在。
	if _controller.effect_resolver == null:
		_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)


## 把一张实体牌直接放入指定玩家的普通手牌区；测试需要绕过摸牌流程构造确定手牌。
func _give_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	var player: PlayerState = _controller.state.get_player(player_id)
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	# 持有者与区域；正式对局由移动服务在进入玩家区域时写入，测试直接入区必须补齐。
	card.owner_id = player_id
	card.zone = "hand"
	player.hand.append(card)
	return card


## 校验动作类别解析契约：显式声明优先，模式推导只覆盖唯一合法动作的牌。
func _test_action_resolution_contract() -> bool:
	_reset_state(2)
	# 模式推导；【无懈可击】【桃】【酒】只有“使用”一种合法动作。
	for use_pattern: String in ["wuxie", "tao", "jiu"]:
		if _controller.resolve_response_action({}, [use_pattern]) != MatchController.CARD_ACTION_USE:
			return _fail("pattern_default_use=%s" % use_pattern)
	# 模式推导；【杀】与【闪】既可被使用也可被打出，缺省必须回落到“打出”。
	for play_pattern: String in ["sha", "shan"]:
		if _controller.resolve_response_action({}, [play_pattern]) != MatchController.CARD_ACTION_PLAY:
			return _fail("pattern_default_play=%s" % play_pattern)
	# 显式声明优先于模式推导：同一个【闪】响应窗口可以被声明为“使用”。
	if _controller.resolve_response_action({"response_action":"use"}, ["shan"]) != MatchController.CARD_ACTION_USE:
		return _fail("declared_use_wins")
	# 非法声明值不得被猜测为某个动作；必须回落到模式推导结果。
	if _controller.resolve_response_action({"response_action":"bogus"}, ["wuxie"]) != MatchController.CARD_ACTION_USE:
		return _fail("invalid_declaration_falls_back")
	# 多模式窗口；【桃】与【酒】共享救援时机，两者同为“使用”时结果保持“使用”。
	if _controller.resolve_response_action({}, ["tao", "jiu"]) != MatchController.CARD_ACTION_USE:
		return _fail("multi_pattern_use")
	# 空模式集合没有可推导依据，必须回落到“打出”而不是空字符串。
	if _controller.resolve_response_action({}, []) != MatchController.CARD_ACTION_PLAY:
		return _fail("empty_patterns")
	return true


## 校验“使用”型响应的完整生命周期：走 useCard、不进弃置批次、经处理区回收、日志用“使用了”。
func _test_use_response_lifecycle() -> bool:
	_reset_state(2)
	var shan: CardInstance = _give_hand_card(0, "shan", "heart", 5)
	# 使用型响应；显式声明为“使用”，与成为【杀】目标时的语义一致。
	var response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, shan.uid, ["shan"], [], "", {"response_action":MatchController.CARD_ACTION_USE, "responder_id":0, "response_pattern":"shan"})
	if response_card == null:
		return _fail("use_response_missing")
	if _captured_action_timings != ["useCard"]:
		return _fail("use_timings=%s" % [_captured_action_timings])
	if not _test_card_recycled_through_processing(shan.uid):
		return false
	if not _test_presentation_claim_before_recycle(shan.uid):
		return false
	if not _test_logged_with_verb("使用了"):
		return false
	if not _test_response_history_action(0, MatchController.CARD_ACTION_USE):
		return false
	# 弃置批次；使用一张牌绝不能被算作一次“弃置牌”动作。
	if not _captured_batches.is_empty():
		return _fail("use_generated_discard_batch=%s" % [_captured_batches])
	return true


## 校验“打出”型响应的完整生命周期：走 respond、同样不进弃置批次、同样经处理区回收。
func _test_play_response_lifecycle() -> bool:
	_reset_state(2)
	var sha: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	# 打出型响应；显式声明为“打出”，与响应【决斗】【南蛮入侵】时的语义一致。
	var response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, sha.uid, ["sha"], [], "", {"response_action":MatchController.CARD_ACTION_PLAY, "responder_id":0, "response_pattern":"sha"})
	if response_card == null:
		return _fail("play_response_missing")
	if _captured_action_timings != ["respond"]:
		return _fail("play_timings=%s" % [_captured_action_timings])
	if not _test_card_recycled_through_processing(sha.uid):
		return false
	if not _test_presentation_claim_before_recycle(sha.uid):
		return false
	if not _test_logged_with_verb("打出了"):
		return false
	if not _test_response_history_action(0, MatchController.CARD_ACTION_PLAY):
		return false
	# 弃置批次；打出一张牌同样不能被算作一次“弃置牌”动作。
	if not _captured_batches.is_empty():
		return _fail("play_generated_discard_batch=%s" % [_captured_batches])
	return true


## 校验【万箭齐发】的真实响应窗口声明“打出”，提交【闪】后同样不触发弃置批次。
func _test_aoe_declares_play() -> bool:
	_reset_state(2)
	var shan: CardInstance = _give_hand_card(0, "shan", "club", 9)
	# 【万箭齐发】实体；放入处理区以模拟正在结算的锦囊。
	var aoe_card: CardInstance = CardInstance.new("wanjian", "heart", 3)
	aoe_card.zone = "processing"
	_controller.state.processing_area.append(aoe_card)
	var aoe_definition: CardDefinition = GameDatabase.get_card_definition("wanjian")
	if aoe_definition == null:
		return _fail("wanjian_definition_missing")
	# 玩家0 是人类，响应窗口会进入等待；玩家1 是施放者。
	aoe_definition.resolve(_controller.effect_resolver, aoe_card, 1, [0])
	if not _controller.has_pending_card_choice():
		return _fail("wanjian_response_window_missing")
	if not _test_pending_context_action(MatchController.CARD_ACTION_PLAY):
		return false
	if not _submit_card_choice(0, [shan.uid], true):
		return false
	if _captured_action_timings != ["respond"]:
		return _fail("wanjian_timings=%s" % [_captured_action_timings])
	if not _captured_batches.is_empty():
		return _fail("wanjian_generated_discard_batch=%s" % [_captured_batches])
	return true


## 校验【杀】目标响应窗口声明“使用”，并在端到端流程中证明【泛音】不会被该【闪】触发。
func _test_slash_declares_use_and_skips_discard_effects() -> bool:
	_reset_state(3)
	# 【泛音】持有者为玩家0；只要它被算作一次“弃置牌”，锁定后段就会创建选择请求。
	var fanyin: SkillDefinition = _install_skill(0, "fanyin")
	if fanyin == null:
		return _fail("fanyin_install")
	var shan: CardInstance = _give_hand_card(0, "shan", "diamond", 4)
	# 【杀】实体；放入处理区以模拟正在结算的杀。
	var slash_card: CardInstance = CardInstance.new("sha", "spade", 8)
	slash_card.zone = "processing"
	_controller.state.processing_area.append(slash_card)
	# 【杀】牌族共享流程组件；只走防具检查与【闪】响应这一段。
	var slash_effect: SlashCardEffect = SlashCardEffect.new(_controller.effect_resolver)
	slash_effect.continue_after_weapon_targeted({
		"slash_card_uid":slash_card.uid,
		"parent_card_uid":slash_card.uid,
		"actor_id":1,
		"target_id":0,
		"nature":"normal",
		"ignore_armor":false,
	})
	if not _controller.has_pending_card_choice():
		return _fail("slash_response_window_missing")
	if not _test_pending_context_action(MatchController.CARD_ACTION_USE):
		return false
	if not _submit_card_choice(0, [shan.uid], true):
		return false
	if _captured_action_timings != ["useCard"]:
		return _fail("slash_timings=%s" % [_captured_action_timings])
	# 弃置批次；【闪】响应【杀】不能被算作一次“弃置牌”动作。
	if not _captured_batches.is_empty():
		return _fail("slash_generated_discard_batch=%s" % [_captured_batches])
	# 【泛音】锁定后段；如果没有出现第二段选择请求，说明该【闪】没有触发任何“弃置”效果。
	if not _controller._pending_card_choice.is_empty():
		return _fail("fanyin_triggered_by_shan=%s" % [(_controller._pending_card_choice.get("context", {}) as Dictionary)])
	if not _test_logged_with_verb("使用了【闪】"):
		return false
	return true


## 校验当前等待中的选择请求声明了期望的动作类别。
func _test_pending_context_action(expected_action: String) -> bool:
	# 当前请求规则上下文；动作类别必须由发起响应的内容显式写入。
	var context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(context.get("response_action", "")) != expected_action:
		return _fail("pending_action=%s expected=%s" % [context.get("response_action", ""), expected_action])
	return true


## 校验响应牌的牌面表现认领确实发生，且严格早于处理区收尾移动。
## 表现层只承认由 useCard 表现认领过的处理区实体；认领缺失，或认领晚于 processing -> discard_pile，
## 都会让该响应牌的收尾增量被判定为“未认领的虚拟材料收尾”并创建 0 张牌面，也就是玩家看到的完全没有飞牌动画。
func _test_presentation_claim_before_recycle(card_uid: int) -> bool:
	# 表现认领条目下标；-1 表示本次响应根本没有请求过牌面表现。
	var presentation_index: int = -1
	# 处理区收尾条目下标；-1 表示实体没有经过处理区回收路径。
	var recycle_index: int = -1
	for index: int in range(_presentation_timeline.size()):
		# 当前时间线条目；由两个信号按真实下发顺序共同追加。
		var entry: String = _presentation_timeline[index]
		if entry == "present:useCard:true:%d" % card_uid:
			presentation_index = index
		if entry == "transfer:processing->discard_pile:%d" % card_uid:
			recycle_index = index
	if presentation_index < 0:
		return _fail("response_presentation_missing timeline=%s" % [_presentation_timeline])
	if recycle_index < 0:
		return _fail("response_recycle_missing timeline=%s" % [_presentation_timeline])
	if presentation_index > recycle_index:
		return _fail("presentation_after_recycle timeline=%s" % [_presentation_timeline])
	return true


## 校验实体牌确实经过处理区再进入弃牌堆；这是“使用与打出”区别于“弃置”的唯一可靠判据。
func _test_card_recycled_through_processing(card_uid: int) -> bool:
	# 本次移动的公开历史；只读取权威记录，不猜测表现层顺序。
	var entered_processing: bool = false
	var left_processing: bool = false
	for move_variant: Variant in _controller.state.card_move_history:
		var move_data: Dictionary = move_variant as Dictionary
		if not (move_data.get("card_ids", []) as Array).has(card_uid):
			continue
		if str(move_data.get("to_zone", "")) == "processing":
			entered_processing = true
		if str(move_data.get("from_zone", "")) == "processing" and str(move_data.get("to_zone", "")) == "discard_pile":
			left_processing = true
	if not entered_processing or not left_processing:
		return _fail("processing_path=%s:%s" % [entered_processing, left_processing])
	# 弃牌堆落点；回收完成后实体必须位于公共弃牌堆且不再属于任何玩家手牌。
	var in_discard: bool = false
	for discarded_variant: Variant in _controller.state.discard_pile:
		if (discarded_variant as CardInstance).uid == card_uid:
			in_discard = true
			break
	if not in_discard:
		return _fail("not_in_discard_pile")
	return true


## 校验公开日志中存在包含指定动词的响应记录。
func _test_logged_with_verb(verb: String) -> bool:
	for log_text: String in _captured_logs:
		if log_text.contains(verb):
			return true
	return _fail("missing_log_verb=%s logs=%s" % [verb, _captured_logs])


## 校验响应历史记录了正确的动作类别，供技能与回放按“使用/打出”查询。
func _test_response_history_action(player_id: int, expected_action: String) -> bool:
	var player: PlayerState = _controller.state.get_player(player_id)
	if player == null or player.response_history.is_empty():
		return _fail("response_history_empty")
	# 最近一次响应记录；动作类别必须与本次声明完全一致。
	var latest: Dictionary = player.response_history.back() as Dictionary
	if str(latest.get("response_action", "")) != expected_action:
		return _fail("response_history_action=%s" % latest)
	return true


## 安装指定技能并返回独立运行时实例；测试与正式固有技能安装使用同一 bind/install 顺序。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家技能表；允许同一测试逐项追加同武将的多个组件。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 记录卡牌动作主体时机；只关心时机名，不读取事件内部数据。
func _on_use_card_timing(_event: RuleEvent) -> void:
	_captured_action_timings.append("useCard")


## 记录打出时机；与 useCard 互斥，同一次响应不得同时出现。
func _on_respond_timing(_event: RuleEvent) -> void:
	_captured_action_timings.append("respond")


## 记录弃置批次；任何使用或打出场景都必须保持该数组为空。
func _on_discard_batch(event: RuleEvent) -> void:
	_captured_batches.append((event.data as Dictionary).duplicate(true))


## 记录公开日志文本；只保存字符串快照。
func _on_log_added(message: String) -> void:
	_captured_logs.append(message)


## 记录牌面表现请求；只保留事件名、弃牌动画所有权与实体UID三个判定字段。
func _on_card_presentation_requested(presentation_data: Dictionary) -> void:
	# 本次表现事件名；表现层据此区分纯展示与真实处理区实体。
	var event_name: String = str(presentation_data.get("event_name", ""))
	# 本次表现是否接管后续弃牌移动；文本化后与移牌条目共用同一条可比较时间线。
	var owns_discard_transfer_text: String = "true" if bool(presentation_data.get("owns_discard_transfer", false)) else "false"
	# 本次表现对应的实体UID；取自序列化牌面快照，不持有权威对象引用。
	var presented_card_uid: int = int((presentation_data.get("card_data", {}) as Dictionary).get("uid", -1))
	_presentation_timeline.append("present:%s:%s:%d" % [event_name, owns_discard_transfer_text, presented_card_uid])


## 记录区域移牌请求；与牌面表现共用同一条时间线，从而可以断言两者的真实先后顺序。
func _on_card_transfer_requested(card_data: Dictionary, _source_player_id: int, source_zone: String, _target_player_id: int, target_zone: String) -> void:
	_presentation_timeline.append("transfer:%s->%s:%d" % [source_zone, target_zone, int(card_data.get("uid", -1))])


## 为当前选择请求提交实体牌UID；等待期间离区的牌由权威端口再次复核。
func _submit_card_choice(actor_id: int, selected_card_uids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_card_choice")
	# 当前请求稳定编号；提交绑定该稳定ID，避免同步续接后误操作下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":[], "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("card_choice_rejected")
	return true


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("CARD_ACTION_SEMANTICS_FAIL %s" % reason)
	get_tree().quit(1)
	return false
