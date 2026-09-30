extends Node

## 【同袍】专项测试：校验四节顺序推进、各节牌效与端口语义、空节推进，以及每节每出牌阶段限一次的额度。

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
	if not _test_tongpao_static_definition():
		return
	if not _test_tongpao_section_one_damages_self():
		return
	if not _test_tongpao_section_one_absorbed_by_shield():
		return
	if not _test_tongpao_section_two_grants_shield():
		return
	if not _test_tongpao_section_three_discards_hand_card():
		return
	if not _test_tongpao_section_four_discards_zone_card():
		return
	if not _test_tongpao_empty_section_still_advances():
		return
	if not _test_tongpao_sections_exhaust_after_four():
		return
	print("TONGPAO_MECHANICS_PASS sections=4 shield=1 self_damage=1")
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
	_controller.state.match_id = "tongpao"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "同袍测试玩家%d" % (player_id + 1))
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
	# 轮回技服务；【同袍】的每节限次与节推进都由该服务统一裁决，缺失时技能会整条失效。
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
	# 轮回技必须在权威服务登记后才能通过通用限次检查；未登记时 can_activate_reincarnation() 恒为false。
	if bool(GameDatabase.get_skill(skill_id).get("reincarnation", false)):
		_controller.register_reincarnation_skill(player_id, skill_id, GameDatabase.get_skill(skill_id))
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


## 校验【同袍】的静态定义：轮回技元数据、四节声明与玩家可见正文逐字一致。
func _test_tongpao_static_definition() -> bool:
	# 同袍运行时实例；只读取静态参数，不绑定对局。
	var tongpao: SkillDefinition = GameDatabase.create_skill("tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "轮回技，出牌阶段每个轮回节各限一次，你可以①对自己造成1点伤害，②令一名其他角色获得1点护盾，③弃置一张手牌，④弃置一名其他角色区域内的一张牌。"
	var description: String = str(GameDatabase.get_skill("tongpao").get("description", ""))
	if description != expected_description:
		return _fail("tongpao_description %s" % description)
	# 轮回技元数据；四节显式声明且每节每出牌阶段限一次，这是顺序推进的前提。
	var definition: Dictionary = GameDatabase.get_skill("tongpao")
	if not bool(definition.get("reincarnation", false)) or int(definition.get("reincarnation_section_count", 0)) != 4:
		return _fail("tongpao_reincarnation_metadata %s" % [definition])
	if not bool(definition.get("reincarnation_has_explicit_sections", false)) or not bool(definition.get("reincarnation_each_section_once_per_play_phase", false)):
		return _fail("tongpao_reincarnation_flags %s" % [definition])
	# 技能不参与欢愉体系；参演编号必须保持0，避免被误当作欢愉技排入演出顺序。
	if tongpao.is_joy_skill() or tongpao.get_performance_number() != 0:
		return _fail("tongpao_joy_params joy=%s number=%d" % [str(tongpao.is_joy_skill()), tongpao.get_performance_number()])
	return true


## 校验①：无护盾时对自己造成1点伤害，体力下降而其他角色不受影响。
func _test_tongpao_section_one_damages_self() -> bool:
	_reset_state(2)
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	# ①没有可选内容，发动即结算。
	var section1_rejection: String = tongpao.activate()
	if not section1_rejection.is_empty():
		return _fail("tongpao_section1_activate can_activate=%s rejection=%s" % [str(tongpao.can_activate()), section1_rejection])
	if _controller.state.get_player(0).hp != 3:
		return _fail("tongpao_section1_hp=%d" % _controller.state.get_player(0).hp)
	# 伤害只作用于持有者本人；其他角色必须保持满血。
	if _controller.state.get_player(1).hp != 4:
		return _fail("tongpao_section1_other_hp=%d" % _controller.state.get_player(1).hp)
	# ①完成后轮回必须推进到②。
	if tongpao.get_reincarnation_section_index() != 1:
		return _fail("tongpao_section1_index=%d" % tongpao.get_reincarnation_section_index())
	return true


## 校验①的伤害性质：原文是“造成伤害”而非“失去体力”，因此已有护盾必须先被消耗。
func _test_tongpao_section_one_absorbed_by_shield() -> bool:
	_reset_state(2)
	# 预先给持有者1点护盾；直接构造状态以隔离本项断言。
	_controller.state.get_player(0).shield = 1
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_section1_activate")
	if _controller.state.get_player(0).shield != 0 or _controller.state.get_player(0).hp != 4:
		return _fail("tongpao_section1_shield_absorb shield=%d hp=%d" % [_controller.state.get_player(0).shield, _controller.state.get_player(0).hp])
	return true


## 校验②：令指定其他角色获得1点护盾；护盾挂在目标身上而不是持有者身上。
func _test_tongpao_section_two_grants_shield() -> bool:
	_reset_state(2)
	# 持有者先承受①的自伤代价；用护盾吸收以保持体力断言简洁。
	_controller.state.get_player(0).shield = 1
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_section1_activate")
	# ②需要目标；直接动作携带目标ID时跳过选择窗口。
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section2_activate")
	if _controller.state.get_player(1).shield != 1:
		return _fail("tongpao_section2_shield=%d" % _controller.state.get_player(1).shield)
	# 护盾不能落到持有者身上；①已经消耗掉它。
	if _controller.state.get_player(0).shield != 0:
		return _fail("tongpao_section2_owner_shield=%d" % _controller.state.get_player(0).shield)
	if tongpao.get_reincarnation_section_index() != 2:
		return _fail("tongpao_section2_index=%d" % tongpao.get_reincarnation_section_index())
	return true


## 校验③：弃置自己一张手牌；装备区的牌不参与本费用的候选。
func _test_tongpao_section_three_discards_hand_card() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).shield = 1
	# 待弃置的手牌；UID用于直接动作提交。
	var discarded_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	var kept_card: CardInstance = _add_hand_card(0, "shan", "heart", 2)
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_section1_activate")
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section2_activate")
	# ③需要费用牌；直接动作携带 card_uid 时跳过选择窗口。
	if not tongpao.activate({"card_uid":discarded_card.uid}).is_empty():
		return _fail("tongpao_section3_activate")
	if _controller.state.get_player(0).hand.has(discarded_card):
		return _fail("tongpao_section3_not_discarded")
	if not _controller.state.get_player(0).hand.has(kept_card):
		return _fail("tongpao_section3_discarded_too_much")
	if tongpao.get_reincarnation_section_index() != 3:
		return _fail("tongpao_section3_index=%d" % tongpao.get_reincarnation_section_index())
	return true


## 校验④：弃置一名其他角色区域内的一张牌；两步交互先选角色再选牌。
func _test_tongpao_section_four_discards_zone_card() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).shield = 1
	# ③的费用牌与④的目标牌必须分开构造，避免③把④要弃的牌消耗掉。
	var cost_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	var enemy_card: CardInstance = _add_hand_card(1, "wuxie", "club", 9)
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_section1_activate")
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section2_activate")
	if not tongpao.activate({"card_uid":cost_card.uid}).is_empty():
		return _fail("tongpao_section3_activate")
	# ④第一步：选定角色后必须进入区域选牌窗口，而不是立即结算。
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section4_target_activate")
	# 第二步请求上下文；必须携带第一步选定的角色ID。
	var zone_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(zone_context.get("kind", "")) != "tongpao_zone_card" or int(zone_context.get("target_id", -1)) != 1:
		return _fail("tongpao_section4_window %s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [enemy_card.uid], [], true):
		return false
	if _controller.state.get_player(1).hand.has(enemy_card):
		return _fail("tongpao_section4_not_discarded")
	return true


## 校验空节推进：③在持有者没有任何手牌时仍必须可发动，并直接把轮回推进到④。
## 若此处返回false，玩家的④将永远无法到达，轮回会永久停在本节。
func _test_tongpao_empty_section_still_advances() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).shield = 1
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_section1_activate")
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section2_activate")
	# 持有者没有任何手牌：③客观上没有可执行内容。
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("tongpao_empty_section_hand_not_empty")
	if not tongpao.can_activate():
		return _fail("tongpao_empty_section3_can_activate")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_empty_section3_activate")
	if tongpao.get_reincarnation_section_index() != 3:
		return _fail("tongpao_empty_section3_not_advanced index=%d" % tongpao.get_reincarnation_section_index())
	# 空节不得产生任何牌效：目标护盾与体力都必须保持原值。
	if _controller.state.get_player(1).shield != 1 or _controller.state.get_player(0).hp != 4:
		return _fail("tongpao_empty_section_side_effect shield=%d hp=%d" % [_controller.state.get_player(1).shield, _controller.state.get_player(0).hp])
	return true


## 校验四节用尽后技能关闭：每节每出牌阶段限一次，四个节全部完成后不能再发动。
func _test_tongpao_sections_exhaust_after_four() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).shield = 1
	var cost_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	var enemy_card: CardInstance = _add_hand_card(1, "wuxie", "club", 9)
	var tongpao: SkillDefinition = _install_single_skill(0, "tongpao")
	if tongpao == null:
		return _fail("tongpao_missing")
	if not tongpao.activate().is_empty():
		return _fail("tongpao_section1_activate")
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section2_activate")
	if not tongpao.activate({"card_uid":cost_card.uid}).is_empty():
		return _fail("tongpao_section3_activate")
	if not tongpao.activate({"target_ids":[1]}).is_empty():
		return _fail("tongpao_section4_target_activate")
	if not _submit_pending_choice(0, [enemy_card.uid], [], true):
		return false
	# 四个轮回节全部用尽；本出牌阶段不再有任何合法发动。
	if tongpao.can_activate():
		return _fail("tongpao_exhausted_still_activatable index=%d" % tongpao.get_reincarnation_section_index())
	# 额度用尽后必须显式拒绝，而不是静默接受一次空发动。
	if tongpao.activate().is_empty():
		return _fail("tongpao_exhausted_activate_accepted")
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(reason: String) -> bool:
	if not _failed:
		_failed = true
		printerr("TONGPAO_MECHANICS_FAIL %s" % reason)
		get_tree().quit(1)
	return false
