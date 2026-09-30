extends Node

## 【断界】专项测试：校验四项操作的前置状态判定、每次发动删除最后一项、选项用尽后技能熄灭，
## 以及「复原武将牌上的技能」能复原已删除的选项、而单项复原限定额度不能复原选项列表。

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
	if not _test_duanjie_static_definition():
		return
	if not _test_duanjie_dynamic_description():
		return
	if not _test_duanjie_first_activation_removes_last_option():
		return
	if not _test_duanjie_options_exhaust_after_four_activations():
		return
	if not _test_duanjie_restored_by_character_card_restore():
		return
	if not _test_duanjie_limited_use_restore_keeps_options():
		return
	print("DUANJIE_MECHANICS_PASS options=4 face_down=true restorable=true")
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
	_controller.state.match_id = "duanjie"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "断界测试玩家%d" % (player_id + 1))
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
	# 轮回技服务；本技能不是轮回技，但控制器内部多处会访问该字段。
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


## 派发一次出牌阶段开始时机，恢复「出牌阶段限一次」额度；用于在同一场景内模拟连续多个出牌阶段。
func _begin_new_play_phase() -> void:
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, 0, {"turn_number":_controller.state.turn_number, "player_id":0, "phase":"play"})


## 派发一次武将牌技能变更时机；change_type 决定本技能是否应该清空已删除的选项。
func _emit_change_skills(change_type: String, skill_ids: Array) -> void:
	_controller._emit_rule_timing("changeSkillsAfter", 0, 0, 0, {"change_type":change_type, "skill_ids":skill_ids.duplicate()})


## 校验【断界】的删除进度会同步到技能的显示描述：被删除的选项原文带删除线标记，
## 未删除的选项与其余原文逐字保持静态原文，复原后覆盖被清除并回到完整四项。
## 同时校验显示视图把标记解析成删除线，而不是把标记本身当成普通文字画出来。
func _test_duanjie_dynamic_description() -> bool:
	_reset_state(3)
	var duanjie: SkillDefinition = _install_single_skill(0, "duanjie")
	if duanjie == null:
		return _fail("duanjie_missing")
	# 未删除任何选项时不写入覆盖，快照保持“没有动态描述”的初始形态。
	if not (_controller.state.get_player(0).dynamic_skill_descriptions as Dictionary).is_empty():
		return _fail("duanjie_initial_override=%s" % _controller.state.get_player(0).dynamic_skill_descriptions)
	# 首次发动删除④：④的原文片段应被删除线标记包住，①到③原样保留。
	if not duanjie.activate({"option_id":"4", "target_ids":[1]}).is_empty():
		return _fail("duanjie_dynamic_activate_option4")
	var dynamic_description: String = str((_controller.state.get_player(0).dynamic_skill_descriptions as Dictionary).get("duanjie", ""))
	if not dynamic_description.contains("[s]4.将一名武将牌正面向上的角色翻至背面[/s]。"):
		return _fail("duanjie_dynamic_strike_missing=%s" % dynamic_description)
	if not dynamic_description.contains("3.将一名武将牌背面向上的角色翻至正面；"):
		return _fail("duanjie_dynamic_kept_option_missing=%s" % dynamic_description)
	# 公开快照是界面唯一数据来源：悬停资料、右键详情与技能按钮都只读该字段。
	var snapshot: Dictionary = _controller.state.get_player(0).to_dict(-1, false)
	if str((snapshot.get("dynamic_skill_descriptions", {}) as Dictionary).get("duanjie", "")) != dynamic_description:
		return _fail("duanjie_dynamic_snapshot_missing=%s" % [snapshot.get("dynamic_skill_descriptions", {})])
	# 显示视图必须解析标记：可见纯文本里不能残留标记字面量，同时被划掉的选项文字仍然可见。
	var description_view: SkillDescriptionView = SkillDescriptionView.new()
	add_child(description_view)
	description_view.configure_description(dynamic_description)
	var visible_text: String = description_view.get_rendered_visible_text()
	if visible_text.contains("[s]") or visible_text.contains("[/s]"):
		return _fail("duanjie_dynamic_view_leaked_marker=%s" % visible_text)
	if not visible_text.contains("4.将一名武将牌正面向上的角色翻至背面"):
		return _fail("duanjie_dynamic_view_text_missing=%s" % visible_text)
	description_view.queue_free()
	# 复原武将牌后清除覆盖，资料回到完整四项原文。
	_emit_change_skills("restore_character_card_skills", ["duanjie"])
	if not (_controller.state.get_player(0).dynamic_skill_descriptions as Dictionary).is_empty():
		return _fail("duanjie_restore_override_leaked=%s" % _controller.state.get_player(0).dynamic_skill_descriptions)
	return true


## 校验【断界】的静态定义：玩家可见正文逐字一致且是出牌阶段主动技能。
func _test_duanjie_static_definition() -> bool:
	# 断界运行时实例；只读取静态参数，不绑定对局。
	var duanjie: SkillDefinition = GameDatabase.create_skill("duanjie")
	if duanjie == null:
		return _fail("duanjie_missing")
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "出牌阶段限一次，你可以选择：1.将一名武将牌竖置的角色横置；2.将一名武将牌横置的角色竖置；3.将一名武将牌背面向上的角色翻至正面；4.将一名武将牌正面向上的角色翻至背面。选择完毕后，你删除最后一项。"
	var description: String = str(GameDatabase.get_skill("duanjie").get("description", ""))
	if description != expected_description:
		return _fail("duanjie_description %s" % description)
	# 非限定技、非轮回技；避免被其他机制误接管。
	if duanjie.limited or bool(GameDatabase.get_skill("duanjie").get("reincarnation", false)):
		return _fail("duanjie_unexpected_flags")
	return true


## 校验首次发动：初始仅①与④有合法目标，发动④后列表末尾被删除，技能朝向状态真正落地。
func _test_duanjie_first_activation_removes_last_option() -> bool:
	_reset_state(3)
	var duanjie: SkillDefinition = _install_single_skill(0, "duanjie")
	if duanjie == null:
		return _fail("duanjie_missing")
	# 初始状态：全员未横置且正面向上，因此可用的只有①（横置）与④（翻至背面）。
	if duanjie._collect_available_options() != ["1", "4"]:
		return _fail("duanjie_initial_options %s" % [duanjie._collect_available_options()])
	if not duanjie.can_activate():
		return _fail("duanjie_cannot_activate")
	# 发动④：把玩家1翻至背面（初始正面向上）。
	var rejection: String = duanjie.activate({"option_id":"4", "target_ids":[1]})
	if not rejection.is_empty():
		return _fail("duanjie_activate_option4 %s" % rejection)
	if not _controller.state.get_player(1).face_down:
		return _fail("duanjie_face_down_not_applied")
	# 删除的是列表最后一项：④消失，剩余为①②③。
	if duanjie._get_remaining_options() != ["1", "2", "3"]:
		return _fail("duanjie_remaining_after_first %s" % [duanjie._get_remaining_options()])
	# 「出牌阶段限一次」：同一阶段不能再次发动。
	if duanjie.can_activate():
		return _fail("duanjie_second_activation_same_phase")
	return true


## 校验连续发动：每发动一次删除最后一项，列表用尽后技能熄灭且不再受理发动。
func _test_duanjie_options_exhaust_after_four_activations() -> bool:
	_reset_state(3)
	var duanjie: SkillDefinition = _install_single_skill(0, "duanjie")
	if duanjie == null:
		return _fail("duanjie_missing")
	# 每次发动都进入新的出牌阶段以恢复额度；删除顺序固定为从末尾向前。
	var expected_remaining: Array = [["1", "2", "3"], ["1", "2"], ["1"], []]
	for activation_index: int in range(4):
		if not duanjie.can_activate():
			return _fail("duanjie_not_activatable index=%d remaining=%s" % [activation_index, duanjie._get_remaining_options()])
		# 始终使用①把当前第一个未横置的其他角色横置，保证每轮都有合法目标。
		var target_id: int = activation_index % 2 + 1
		_controller.state.get_player(target_id).chained = false
		var rejection: String = duanjie.activate({"option_id":"1", "target_ids":[target_id]})
		if not rejection.is_empty():
			return _fail("duanjie_activate index=%d rejection=%s" % [activation_index, rejection])
		if not _controller.state.get_player(target_id).chained:
			return _fail("duanjie_chained_not_applied index=%d" % activation_index)
		if duanjie._get_remaining_options() != expected_remaining[activation_index]:
			return _fail("duanjie_remaining index=%d actual=%s" % [activation_index, duanjie._get_remaining_options()])
		_begin_new_play_phase()
	# 列表已空：即使额度恢复，技能也必须熄灭。
	if duanjie.can_activate():
		return _fail("duanjie_exhausted_still_activatable")
	if duanjie.activate({"option_id":"1", "target_ids":[1]}).is_empty():
		return _fail("duanjie_exhausted_activate_accepted")
	return true


## 校验「复原武将牌上的技能」能复原已删除的选项；这是需求明确要求的可复原行为。
func _test_duanjie_restored_by_character_card_restore() -> bool:
	_reset_state(3)
	var duanjie: SkillDefinition = _install_single_skill(0, "duanjie")
	if duanjie == null:
		return _fail("duanjie_missing")
	# 先发动一次把④删掉。
	if not duanjie.activate({"option_id":"4", "target_ids":[1]}).is_empty():
		return _fail("duanjie_activate_before_restore")
	if duanjie._get_remaining_options().size() != 3:
		return _fail("duanjie_remaining_before_restore %s" % [duanjie._get_remaining_options()])
	# 复原武将牌上的技能：已删除的选项必须全部回来。
	_emit_change_skills("restore_character_card_skills", ["duanjie"])
	if duanjie._get_remaining_options() != ["1", "2", "3", "4"]:
		return _fail("duanjie_restore_not_applied %s" % [duanjie._get_remaining_options()])
	# 复原后必须能重新发动④（目标已翻至背面，此处改用尚未翻面的玩家2）。
	_begin_new_play_phase()
	if not duanjie.can_activate():
		return _fail("duanjie_not_activatable_after_restore")
	if not duanjie.activate({"option_id":"4", "target_ids":[2]}).is_empty():
		return _fail("duanjie_activate_after_restore")
	return true


## 校验单项复原限定额度不会复原选项列表：两种变更类型共用同一时机，必须按 change_type 过滤。
func _test_duanjie_limited_use_restore_keeps_options() -> bool:
	_reset_state(3)
	var duanjie: SkillDefinition = _install_single_skill(0, "duanjie")
	if duanjie == null:
		return _fail("duanjie_missing")
	# 先发动一次把④删掉。
	if not duanjie.activate({"option_id":"4", "target_ids":[1]}).is_empty():
		return _fail("duanjie_activate_before_limited_restore")
	# 单项复原限定额度：只应恢复限定额度，绝不能让已删除的选项复活。
	_emit_change_skills("restore_limited_skill_use", ["duanjie"])
	if duanjie._get_remaining_options() != ["1", "2", "3"]:
		return _fail("duanjie_limited_restore_leaked %s" % [duanjie._get_remaining_options()])
	# 复原其他武将的技能也不得波及本技能。
	_emit_change_skills("restore_character_card_skills", ["some_other_skill"])
	if duanjie._get_remaining_options() != ["1", "2", "3"]:
		return _fail("duanjie_other_skill_restore_leaked %s" % [duanjie._get_remaining_options()])
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(reason: String) -> bool:
	if not _failed:
		_failed = true
		printerr("DUANJIE_MECHANICS_FAIL %s" % reason)
		get_tree().quit(1)
	return false
