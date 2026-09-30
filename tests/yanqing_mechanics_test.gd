extends Node

## 【遥击】与【凌霜】专项测试：校验遥击只对最远角色放宽【杀】的距离限制、且不影响其他距离敏感牌；
## 校验凌霜在正面翻至背面时弃置目标两张手牌并豁免次数、背面翻回正面时只有翻面本身。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保 GameDatabase 已完成新技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行断言；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_yaoji_static_definition():
		return
	if not _test_yaoji_releases_slash_distance_only():
		return
	if not _test_lingshuang_static_definition():
		return
	if not _test_lingshuang_front_to_back_applies_effects():
		return
	if not _test_lingshuang_back_to_front_has_no_extra():
		return
	print("YANQING_MECHANICS_PASS yaoji=farthest_only lingshuang=discard2+exempt")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器并装配必需子节点；不加载界面，保持规则断言隔离。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；伤害、技能时机与弃置批次共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保留正式节点供身份观察使用。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；动作提交与正式单机模式保持相同来源语义。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0


## 为当前单项测试创建最小权威状态；一号领袖、二号反贼使AI态度确定。
func _reset_state(player_count: int) -> void:
	# 专项场景隔离：取消上一场景残留的流程延时与出牌请求标记。
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "yanqing"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "彦卿测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	_controller.player_mark_service = PlayerMarkService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, _controller.state)
	# 轮回技服务；本组技能都不是轮回技，但控制器内部多处会访问该字段。
	_controller.reincarnation_skill_service = ReincarnationSkillService.new()
	_controller.reincarnation_skill_service.configure(_controller)
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._rule_sequences.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._rule_continuations.reset()
	_controller._started_phase_lifecycles.clear()
	_controller.ai_coordinator._policies.clear()
	_controller._ai_drive_token += 1


## 向指定玩家手牌区加入一张实体牌；测试需要绕过摸牌流程构造确定手牌。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 为指定玩家安装一个运行时技能实例；通过真实 install() 复现时机订阅。
func _install_single_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 技能实例；技能目录缺失时返回null并交由调用方报告具体场景。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家已安装技能表；同一场景可连续追加多个技能。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 为当前统一选择请求提交目标、牌或确认结果；使用正式 PlayerAction 入口。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool, selected_control_id: String = "") -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；目标、牌与确认状态均显式填写。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s pending=%s" % [actor_id, request_id, action.payload, _controller._pending_card_choice])
	return true


## 判断当前等待窗口是否为【凌霜】的翻面确认。
func _has_lingshuang_prompt() -> bool:
	if _controller._pending_card_choice.is_empty():
		return false
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "lingshuang_turn_over"


## 校验【遥击】的静态定义：锁定技标记与玩家可见正文逐字一致。
func _test_yaoji_static_definition() -> bool:
	# 遥击运行时实例；只读取静态参数，不绑定对局。
	var yaoji: SkillDefinition = GameDatabase.create_skill("yaoji")
	if yaoji == null:
		return _fail("yaoji_missing")
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "锁定技，你对距离与你最远的角色使用【杀】没有距离限制。"
	var description: String = str(GameDatabase.get_skill("yaoji").get("description", ""))
	if description != expected_description:
		return _fail("yaoji_description %s" % description)
	# 锁定技由正文自动识别；缺失会让非锁定技禁用类效果失效。
	if not yaoji.lock or not yaoji.can_use_effect():
		return _fail("yaoji_lock lock=%s" % str(yaoji.lock))
	return true


## 校验【遥击】只放宽【杀】对最远角色的距离限制，其他牌与其他目标完全不受影响。
func _test_yaoji_releases_slash_distance_only() -> bool:
	# 六人局的座次距离为 0→3 为3（最远）、0→2 为2（非最远）、0→1 为1，可同时覆盖放行与不放行两侧。
	_reset_state(6)
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	# 顺手牵羊的距离限制为one；用于确认遥击不会连带放宽其他距离敏感牌。
	var shunshou_card: CardInstance = _add_hand_card(0, "shunshou", "diamond", 4)
	# 目标玩家2必须先有牌，否则顺手牵羊会因“目标区域内没有牌”这一更早的检查被拒，走不到距离判定。
	_add_hand_card(2, "shan", "club", 6)
	var yaoji: SkillDefinition = _install_single_skill(0, "yaoji")
	if yaoji == null:
		return _fail("yaoji_missing")
	# 场景前置：最远距离必须确实超出默认攻击范围，否则本用例无法区分放行与基线。
	var farthest_distance: int = _controller.card_rules.calculate_distance(0, 3)
	if farthest_distance <= 1:
		return _fail("yaoji_distance_setup dist=%d" % farthest_distance)
	# 对距离最远的角色使用【杀】必须放行。
	var farthest_rejection: String = _controller.card_rules.validate_use(0, slash_card, [3])
	if not farthest_rejection.is_empty():
		return _fail("yaoji_farthest_not_released \"%s\"" % farthest_rejection)
	# 非最远角色继续受距离限制：严格按描述只在“距离最远”时解限。
	var nearer_rejection: String = _controller.card_rules.validate_use(0, slash_card, [2])
	if nearer_rejection.is_empty():
		return _fail("yaoji_nearer_target_released")
	# 其他距离敏感牌必须与未安装技能时完全一致：遥击不得影响任何非【杀】牌。
	var shunshou_rejection: String = _controller.card_rules.validate_use(0, shunshou_card, [2])
	if not shunshou_rejection.contains("距离"):
		return _fail("yaoji_shunshou_baseline \"%s\"" % shunshou_rejection)
	return true


## 校验【凌霜】的静态定义：逐目标使用者时机与玩家可见正文逐字一致。
func _test_lingshuang_static_definition() -> bool:
	# 凌霜运行时实例；只读取静态参数，不绑定对局。
	var lingshuang: SkillDefinition = GameDatabase.create_skill("lingshuang")
	if lingshuang == null:
		return _fail("lingshuang_missing")
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "当你使用【杀】指定目标时，你可以将你的武将牌翻面。若你因此翻至背面向上，你弃置目标角色两张手牌且令此【杀】不计入出牌阶段使用限制。"
	var description: String = str(GameDatabase.get_skill("lingshuang").get("description", ""))
	if description != expected_description:
		return _fail("lingshuang_description %s" % description)
	# 必须是使用者视角的逐目标时机；该时机属于会写回用牌上下文的四组 useCardTo* 之一。
	if str(GameDatabase.get_skill("lingshuang").get("trigger", "")) != "useCardToTargeted":
		return _fail("lingshuang_trigger %s" % str(GameDatabase.get_skill("lingshuang").get("trigger", "")))
	return true


## 校验正面翻至背面时：翻面落地、弃置目标两张手牌、并成功豁免本张【杀】的次数。
func _test_lingshuang_front_to_back_applies_effects() -> bool:
	_reset_state(2)
	var lingshuang: SkillDefinition = _install_single_skill(0, "lingshuang")
	if lingshuang == null:
		return _fail("lingshuang_missing")
	# 目标两张手牌；用于验证“弃置两张”这一固定张数。
	_add_hand_card(1, "tao", "heart", 2)
	_add_hand_card(1, "tao", "heart", 3)
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	# 持有者初始正面向上，因此本次翻面会翻至背面，附加效果应当成立。
	if _controller.state.get_player(0).face_down:
		return _fail("lingshuang_setup_face_down")
	_controller._execute_card_use(0, slash_card, [1])
	if not _has_lingshuang_prompt():
		return _fail("lingshuang_no_prompt %s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 翻面必须真实落地。
	if not _controller.state.get_player(0).face_down:
		return _fail("lingshuang_not_face_down")
	# 弃置目标两张手牌：目标原本恰好两张，因此手牌区应当清空。
	if _controller.state.get_player(1).hand.size() != 0:
		return _fail("lingshuang_discard_remaining=%d" % _controller.state.get_player(1).hand.size())
	# 本张【杀】必须已被登记为次数豁免。
	if not lingshuang._exempted_card_uids.has(slash_card.uid):
		return _fail("lingshuang_limit_not_exempted %s" % [lingshuang._exempted_card_uids])
	# 幂等：同一张牌不允许重复豁免，否则每次询问都会额外放宽一次使用次数。
	if lingshuang._exempt_card_use_limit(slash_card.uid, "sha"):
		return _fail("lingshuang_double_exempt_accepted")
	return true


## 校验背面翻回正面时只有翻面本身：不弃牌、不重复豁免次数。
func _test_lingshuang_back_to_front_has_no_extra() -> bool:
	_reset_state(2)
	# 持有者预先背面向上，因此本次翻面只会翻回正面。
	_controller.state.get_player(0).face_down = true
	var lingshuang: SkillDefinition = _install_single_skill(0, "lingshuang")
	if lingshuang == null:
		return _fail("lingshuang_missing")
	# 目标两张非【闪】手牌；目标无法响应，避免响应窗口干扰断言。
	_add_hand_card(1, "tao", "heart", 2)
	_add_hand_card(1, "tao", "heart", 3)
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	_controller._execute_card_use(0, slash_card, [1])
	if not _has_lingshuang_prompt():
		return _fail("lingshuang_unflip_no_prompt %s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 翻回正面。
	if _controller.state.get_player(0).face_down:
		return _fail("lingshuang_unflip_failed")
	# 没有附加效果：目标手牌保持两张，本张【杀】也不被豁免。
	if _controller.state.get_player(1).hand.size() != 2:
		return _fail("lingshuang_unflip_discarded=%d" % _controller.state.get_player(1).hand.size())
	if lingshuang._exempted_card_uids.has(slash_card.uid):
		return _fail("lingshuang_unflip_exempted")
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(reason: String) -> bool:
	if not _failed:
		_failed = true
		printerr("YANQING_MECHANICS_FAIL %s" % reason)
		get_tree().quit(1)
	return false
