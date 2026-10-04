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
	if not _test_bagua_red_judgment_declares_action():
		return
	if not _test_recast_is_neither_discard_nor_play():
		return
	if not _test_target_legality_query_contract():
		return
	print("CARD_ACTION_SEMANTICS_PASS use=useCard play=respond batch=0 through_processing=1 bagua=red recast=none")
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
	# 动态调用的类型上下文；内容层通常以 Object 形参持有控制器，此时 GDScript 无法为字面量数组推断元素类型，
	# 运行时收到的是无类型 Array。此处显式复现该调用形态，防止核心端口再次把形参收紧为 Array[String] 而在玩家侧崩溃。
	var dynamic_host: Object = _controller
	if dynamic_host.resolve_response_action({}, ["shan"]) != MatchController.CARD_ACTION_PLAY:
		return _fail("dynamic_literal_patterns")
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


## 校验【八卦阵】红色判定成功时，内容层能够直接调用核心动作解析端口并得到正确动词。
## 该路径此前是测试盲区：既有用例全部使用黑色判定，会在构造虚拟【闪】之前提前返回，
## 因此内容层那次「以字面量数组调用核心端口」的真实调用从未执行过，
## 形参与实参的数组元素类型不匹配只能在玩家真正判定出红色时才以运行时错误的形式爆发。
func _test_bagua_red_judgment_declares_action() -> bool:
	_reset_state(2)
	# 八卦阵内容层定义；直接取源码对象以调用其判定成功入口，不经过完整的询问与异步续接流程。
	var bagua_definition: CardDefinition = GameDatabase.get_card_definition("bagua")
	if bagua_definition == null:
		return _fail("bagua_definition_missing")
	# 响应者；八卦阵日志只读取显示名与存活状态，使用0号玩家即可覆盖正式分支。
	var responder: PlayerState = _controller.state.get_player(0)
	if responder == null:
		return _fail("bagua_responder_missing")
	# 红色判定牌；八卦阵只在判定为红色时构造虚拟【闪】，黑色判定会在触碰核心端口之前提前返回。
	var red_judgment_card: CardInstance = CardInstance.new("sha", "heart", 7)
	# 使用型响应窗口上下文；模拟“成为【杀】的目标”这一声明。
	var use_context: Dictionary = {"response_action":CardDefinition.CARD_ACTION_USE}
	# 使用场景的虚拟响应牌；红色判定成功必须返回一张【闪】而不是 null。
	var use_virtual_shan: CardInstance = bagua_definition._build_bagua_response(_controller, responder.player_id, red_judgment_card, use_context)
	if use_virtual_shan == null or use_virtual_shan.definition_id != "shan":
		return _fail("bagua_red_use_response=%s" % [use_virtual_shan])
	if not _test_logged_with_verb("视为使用【闪】"):
		return false
	# 打出场景的日志基线；清空后单独断言，避免使用场景的记录掩盖动词错误。
	_captured_logs.clear()
	# 打出型响应窗口上下文；同一防具在同一张红色判定牌下必须改写成“打出”。
	var play_context: Dictionary = {"response_action":CardDefinition.CARD_ACTION_PLAY}
	# 打出场景的虚拟响应牌；判定结果与使用场景完全相同，只有日志动词不同。
	var play_virtual_shan: CardInstance = bagua_definition._build_bagua_response(_controller, responder.player_id, red_judgment_card, play_context)
	if play_virtual_shan == null or play_virtual_shan.definition_id != "shan":
		return _fail("bagua_red_play_response=%s" % [play_virtual_shan])
	if not _test_logged_with_verb("视为打出【闪】"):
		return false
	return true


## 校验“重铸”既不构成使用、也不构成打出，更不构成弃置：牌只被置入弃牌堆，随后固定摸一张牌。
## 重铸的来源区域同样是手牌，所以它是“物理移动与弃置完全相同、规则语义完全不同”的第四类动作，
## 必须由调用方显式声明为非弃置动作，否则会派发 cardsDiscardedBatchAfter 并误触发【泛音】。
func _test_recast_is_neither_discard_nor_play() -> bool:
	_reset_state(2)
	# 可重铸手牌；【铁索连环】在自身卡牌定义中把 recast 标记为 true，是唯一支持主动重铸的实体牌。
	var recast_card: CardInstance = _give_hand_card(0, "tiesuo", "club", 12)
	if recast_card == null:
		return _fail("recast_card_missing")
	# 重铸前的摸牌堆张数；重铸固定补摸一张牌，用于断言摸牌确实发生。
	var draw_pile_count_before: int = _controller.state.draw_pile.size()
	if not _controller.recast_hand_card(0, recast_card.uid):
		return _fail("recast_rejected")
	if not _controller.state.discard_pile.has(recast_card):
		return _fail("recast_not_in_discard")
	if _controller.state.get_player(0).find_hand_card(recast_card.uid) != null:
		return _fail("recast_still_in_hand")
	if _controller.state.draw_pile.size() != draw_pile_count_before - 1:
		return _fail("recast_draw_pile=%d" % _controller.state.draw_pile.size())
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("recast_hand_size=%d" % _controller.state.get_player(0).hand.size())
	# 核心断言：重铸不得产生弃置批次，否则【泛音】等“当你弃置牌时”类技能会被误触发。
	if not _captured_batches.is_empty():
		return _fail("recast_discard_batch=%s" % [_captured_batches])
	# 重铸既不使用也不打出，两个主体时机都不得派发。
	if not _captured_action_timings.is_empty():
		return _fail("recast_action_timings=%s" % [_captured_action_timings])
	# 公开日志必须只出现“重铸了”；额外写入的“弃置了”会让玩家误判本次牌张归属。
	for log_text: String in _captured_logs:
		if log_text.contains("弃置了"):
			return _fail("recast_discard_log=%s" % log_text)
	if not _test_logged_with_verb("重铸了"):
		return false
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


## 校验使用牌目标资格的权威查询契约：只回答“能否作为这张牌的目标”，与出牌阶段、当前行动者、持牌区域无关。
## 这组断言锁定【借刀杀人】修复所依赖的两条核心性质：
## 1. 非当前行动者的持刀者同样能拿到真实合法目标，而整牌入口 validate_virtual_use 会因阶段闸门整体拒绝；
## 2. 真实实体牌的复核必须按单元素目标数组判定，否则【借刀杀人】使用的【杀】会因角色顺序语义短路掉全部来牌限制。
func _test_target_legality_query_contract() -> bool:
	_reset_state(3)
	# 持刀者武器；攻击范围覆盖三人局，使合法【杀】目标只剩距离与来牌限制两个变因。
	var weapon: CardInstance = CardInstance.new("qinggang", "spade", 6)
	weapon.zone = "equipment"
	weapon.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = weapon
	# 被【杀】者的【琥珀】；来牌限制只拒绝黑色【杀】，因此红色实体牌必须仍有资格。
	if _install_skill(2, "hupo") == null:
		return _fail("target_legality_install_hupo")
	# 阶段与行动者无关性；当前行动者是零号玩家，一号持刀者仍必须得到真实合法目标。
	var holder_targets: Array[int] = _controller.card_rules.list_legal_targets_for_definition(1, "sha", {"ignore_phase_limit":true, "ignore_play_count_limit":true})
	if holder_targets != [0, 2]:
		return _fail("target_legality_holder_targets=%s" % [holder_targets])
	# 对照断言；同一角色走整牌虚拟牌入口时被阶段闸门整体拒绝，这正是必须新增阶段无关查询的唯一理由。
	if _controller.card_rules.validate_virtual_use(1, "sha", [0]).is_empty():
		return _fail("target_legality_virtual_use_unexpected")
	# 单目标资格查询；未知颜色时颜色型限制按未命中处理，与“声明期只有无色的抽象【杀】”保持一致。
	if not _controller.card_rules.validate_target_only(1, "sha", 0).is_empty() or not _controller.card_rules.validate_target_only(1, "sha", 2).is_empty():
		return _fail("target_legality_only holder=%s victim=%s" % [_controller.card_rules.validate_target_only(1, "sha", 0), _controller.card_rules.validate_target_only(1, "sha", 2)])
	# 真实实体牌复核；黑色【杀】被【琥珀】拒绝、红色【杀】放行，拒绝原因必须原样透出给调用方与日志。
	var black_slash: CardInstance = _give_hand_card(1, "sha", "spade", 7)
	var red_slash: CardInstance = _give_hand_card(1, "sha", "heart", 7)
	var black_error: String = _controller.card_rules.validate_entity_card_target(1, black_slash, 2)
	if not black_error.contains("【琥珀】令该角色无法成为黑色【杀】的目标。") or not _controller.card_rules.validate_entity_card_target(1, red_slash, 2).is_empty():
		return _fail("target_legality_entity black=%s red=%s" % [black_error, _controller.card_rules.validate_entity_card_target(1, red_slash, 2)])
	# 目标模式不得因放宽阶段限制而放宽；持刀者本人仍然不是自己【杀】的合法目标。
	if _controller.card_rules.validate_entity_card_target(1, black_slash, 1).is_empty():
		return _fail("target_legality_self")
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
