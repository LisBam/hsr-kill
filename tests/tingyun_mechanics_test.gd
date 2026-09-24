extends Node

## 停云与限定技状态专项回归。覆盖静态资料、赐福首杀距离、来源死亡清理、光覆单项复原、AI目标及限定技按钮三态。

## 本测试共用的权威对局控制器；技能、标记、距离与选择均通过正式组件执行。
var _controller: MatchController


## 延迟一帧执行全部断言，确保GameDatabase已经完成停云与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部停云机制断言；任一失败立即以非零状态结束。
func _run() -> void:
	_create_controller()
	if not _test_metadata():
		return
	if not _test_xiangyin_mark_distance_and_death_cleanup():
		return
	if not _test_guangfu_restore_and_ai():
		return
	if not await _test_limited_skill_button_colors():
		return
	print("TINGYUN_MECHANICS_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；光覆回合尾与限定技变化时机共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；技能评分使用正式无名杀评估器与公开态度语义。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；状态快照与正式单机模式使用相同广播结构。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0


## 为单项测试创建四人权威状态并重建规则服务；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
func _reset_state(player_count: int = 4) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "tingyun-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试角色；身份全部公开以避免AI评分受到隐藏身份衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "停云测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._pending_damage_finalizations.clear()
	_controller._pending_dying_start_contexts.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._cards_used_this_turn_by_player.clear()


## 安装指定技能并返回独立运行时实例；绑定和订阅顺序与正式武将固有技能一致。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 待安装技能实例；数据库必须能按稳定ID创建全新的运行时对象。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家技能表；同一角色可以依次安装停云的两项独立组件。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 校验停云资料、技能顺序与需求给出的两段技能原文，任何文字或标点变化都应立即失败。
func _test_metadata() -> bool:
	# 停云静态定义；稳定ID、仙舟联盟、女性、3点体力与技能顺序必须保持一致。
	var tingyun: Dictionary = GameDatabase.get_character("tingyun")
	if str(tingyun.get("display_name", "")) != "停云" or str(tingyun.get("gender", "")) != "female" or str(tingyun.get("faction", "")) != "xianzhou" or int(tingyun.get("max_hp", 0)) != 3 or (tingyun.get("skills", []) as Array) != ["xiangyin", "guangfu"]:
		return _fail("tingyun_metadata=%s" % tingyun)
	# 技能原文映射；逐字保存需求给出的限定技描述。
	var expected_descriptions: Dictionary = {
		"xiangyin":"限定技，出牌阶段，你可令一名未拥有“赐福”标记的角色获得“赐福”标记，拥有“赐福”标记的角色于一回合内使用的第一张【杀】无距离限制。",
		"guangfu":"限定技，出牌阶段，你可令一名角色摸一张牌。本回合结束时，若其有已发动的限定技，你复原其中一项限定技。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能ID；静态数据库说明必须与期望原文完全一致。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("tingyun_skill_description=%s" % skill_id)
	return true


## 验证祥音写入来源标记、每个全局回合仅首张【杀】无距离，以及停云死亡后移除其给予其他角色的赐福。
func _test_xiangyin_mark_distance_and_death_cleanup() -> bool:
	_reset_state()
	# 停云权威角色；武将ID只用于快照与日志，技能仍通过独立组件安装。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "tingyun"
	owner.max_hp = 3
	owner.hp = 3
	# 祥音运行时技能；限定额度与赐福标记都由正式基类管理。
	var xiangyin: SkillDefinition = _install_skill(0, "xiangyin")
	if xiangyin == null or str(xiangyin.activate({"target_ids":[2]})) != "":
		return _fail("xiangyin_activation")
	# 忠臣目标的赐福标记；必须保存数量、停云来源与首杀距离规则组。
	var blessing_mark: Dictionary = _controller.get_player_mark(2, "cifu")
	if int(blessing_mark.get("count", 0)) != 1 or int(blessing_mark.get("source_player_id", -1)) != 0 or str(blessing_mark.get("first_use_each_turn_ignore_distance_group", "")) != "slash":
		return _fail("xiangyin_mark=%s" % blessing_mark)
	# 普通【杀】定义；赐福在当前全局回合尚未使用【杀】时必须解除距离限制。
	var slash_definition: Dictionary = GameDatabase.get_card("sha")
	if not _controller.skill_ignores_card_distance_limit(2, slash_definition):
		return _fail("xiangyin_first_slash_distance")
	_controller._record_card_used_this_turn(2, "sha")
	if _controller.skill_ignores_card_distance_limit(2, slash_definition):
		return _fail("xiangyin_second_slash_distance")
	_controller._cards_used_this_turn_by_player.clear()
	if not _controller.skill_ignores_card_distance_limit(2, slash_definition):
		return _fail("xiangyin_next_turn_distance")
	# 来源死亡清理；目标仍存活，但由零号停云给予的赐福必须从场上移除。
	if not _controller.player_mark_service.clear_marks_for_dead_player(0) or not _controller.get_player_mark(2, "cifu").is_empty():
		return _fail("xiangyin_source_death_cleanup")
	return true


## 验证光覆摸牌、自身与队友限定技复原、运行时快照和AI优先级。
func _test_guangfu_restore_and_ai() -> bool:
	_reset_state()
	# 停云权威角色；自身作为光覆的通常优先目标。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "tingyun"
	owner.max_hp = 3
	owner.hp = 3
	# 测试摸牌；固定1张【闪】足以验证光覆即时资源变化。
	var draw_card: CardInstance = CardInstance.new("shan", "heart", 2)
	draw_card.zone = "draw_pile"
	_controller.state.draw_pile.append(draw_card)
	# 光覆运行时技能；首次发动后应立即进入已发动限定技集合。
	var guangfu: SkillDefinition = _install_skill(0, "guangfu")
	if guangfu == null or str(guangfu.activate({"target_ids":[0]})) != "" or owner.hand.size() != 1 or guangfu.has_available_intrinsic_use():
		return _fail("guangfu_self_activation hand=%d" % owner.hand.size())
	# 运行时快照；客户端与AI都只读取稳定ID，不接触技能对象。
	var runtime_snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(runtime_snapshot)
	# 停云玩家快照；已发动限定技数组必须包含光覆。
	var owner_snapshot: Dictionary = (runtime_snapshot.get("players", []) as Array)[0] as Dictionary
	if not (owner_snapshot.get("used_limited_skill_ids", []) as Array).has("guangfu"):
		return _fail("guangfu_runtime_snapshot=%s" % owner_snapshot.get("used_limited_skill_ids", []))
	_controller.emit_rule_timing("phaseEnd", 0, 0, 0, {"turn_number":1})
	# 回合尾控制项；自身目标已经发动光覆，因此必须提供复原光覆的强制选项。
	var control_options: Array = _controller._pending_card_choice.get("control_options", []) as Array
	if control_options.is_empty() or str((control_options[0] as Dictionary).get("id", "")) != "guangfu":
		return _fail("guangfu_self_restore_options=%s" % control_options)
	# 复原选择响应；继续选择后光覆限定额度恢复，且不会重置其他技能。
	var restore_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	restore_response.control_id = "guangfu"
	guangfu.continue_selection({"kind":"guangfu_restore_limited", "recipient_id":0, "limited_skill_ids":["guangfu"]}, restore_response)
	if not guangfu.has_available_intrinsic_use():
		return _fail("guangfu_self_restore")
	# 队友复原场景；忠臣已发动的祥音应成为光覆的合法单项复原对象。
	_reset_state()
	# 队友祥音技能；直接消耗限定额度模拟其此前已经发动。
	var ally_xiangyin: SkillDefinition = _install_skill(2, "xiangyin")
	ally_xiangyin.consume_intrinsic_use()
	# 新光覆实例；目标改为队友并在回合尾复原其祥音。
	var ally_guangfu: SkillDefinition = _install_skill(0, "guangfu")
	# 队友摸牌；保持牌堆存在，避免资源流程因空牌堆产生无关终局。
	var ally_draw_card: CardInstance = CardInstance.new("shan", "diamond", 3)
	ally_draw_card.zone = "draw_pile"
	_controller.state.draw_pile.append(ally_draw_card)
	if str(ally_guangfu.activate({"target_ids":[2]})) != "":
		return _fail("guangfu_ally_activation")
	_controller.emit_rule_timing("phaseEnd", 0, 0, 0, {"turn_number":1})
	var ally_restore_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	ally_restore_response.control_id = "xiangyin"
	ally_guangfu.continue_selection({"kind":"guangfu_restore_limited", "recipient_id":2, "limited_skill_ids":["xiangyin"]}, ally_restore_response)
	if not ally_xiangyin.has_available_intrinsic_use():
		return _fail("guangfu_ally_restore")
	# 目标死亡边界；光覆发动后目标若在回合结束前死亡，不应创建必然失败的强制复原选择。
	_reset_state()
	# 死亡边界光覆实例；仍按正式主动入口选择二号友方。
	var dead_target_guangfu: SkillDefinition = _install_skill(0, "guangfu")
	# 死亡边界摸牌；光覆即时摸1张必须先正常完成，再模拟目标于本回合内死亡。
	var dead_target_draw_card: CardInstance = CardInstance.new("shan", "club", 4)
	dead_target_draw_card.zone = "draw_pile"
	_controller.state.draw_pile.append(dead_target_draw_card)
	if str(dead_target_guangfu.activate({"target_ids":[2]})) != "":
		return _fail("guangfu_dead_target_activation")
	# 死亡目标的限定技；即使其运行时实例仍保留已用状态，也不得进入回合尾候选。
	var dead_target_xiangyin: SkillDefinition = _install_skill(2, "xiangyin")
	dead_target_xiangyin.consume_intrinsic_use()
	_controller.state.get_player(2).alive = false
	_controller.emit_rule_timing("phaseEnd", 0, 0, 0, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("guangfu_dead_target_restore_choice")
	# AI快照；重新消耗队友祥音并补充公开运行时状态，比较自身、友方与敌方目标。
	_reset_state()
	# AI用队友祥音；消耗额度后进入权威公开已发动限定技列表。
	ally_xiangyin = _install_skill(2, "xiangyin")
	ally_xiangyin.consume_intrinsic_use()
	# AI用光覆实例；评分阶段不实际发动，只比较三个合法目标动作。
	ally_guangfu = _install_skill(0, "guangfu")
	var ai_snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(ai_snapshot)
	# 正式无名杀评估器；身份公开时能稳定返回领袖对忠臣为正、对反贼为负的态度。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 自身动作；通常应高于只有一项已发动限定技的队友。
	var self_action: Dictionary = {"target_ids":[0]}
	# 友方动作；应保持正收益并允许在更高复原潜力时成为目标。
	var ally_action: Dictionary = {"target_ids":[2]}
	# 敌方动作；摸牌并复原敌方限定技不得高于友方动作。
	var enemy_action: Dictionary = {"target_ids":[1]}
	var self_score: float = ally_guangfu.score_ai_action(ai_snapshot, self_action, evaluator)
	var ally_score: float = ally_guangfu.score_ai_action(ai_snapshot, ally_action, evaluator)
	var enemy_score: float = ally_guangfu.score_ai_action(ai_snapshot, enemy_action, evaluator)
	if self_score <= ally_score or ally_score <= enemy_score or ally_score <= 0.0:
		return _fail("guangfu_ai_scores=%.2f/%.2f/%.2f" % [self_score, ally_score, enemy_score])
	return true


## 验证限定技按钮的可发动红色、暂不可发动深红色与已发动深灰色三态，并确保明度逐级降低。
func _test_limited_skill_button_colors() -> bool:
	# 限定技按钮；加入场景树后才能创建主题覆盖并读取最终StyleBoxFlat。
	var button: SkillButtonView = SkillButtonView.new()
	add_child(button)
	await get_tree().process_frame
	# 祥音定义；限定技元数据由SkillDefinition基类统一登记。
	var definition: Dictionary = GameDatabase.get_skill("xiangyin")
	button.configure(definition, true, "", {}, false)
	# 可发动样式；背景必须直接使用当前主题危险红色。
	var available_style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	button.set_selected_state(true)
	# 选中样式；限定技进入交互流程后仍应保留全技能统一的主题强调描边。
	var selected_style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	button.set_selected_state(false)
	button.configure(definition, false, "", {}, false)
	# 暂不可发动样式；仍为红色系，但相对可发动状态略微加深。
	var unavailable_style: StyleBoxFlat = button.get_theme_stylebox("disabled") as StyleBoxFlat
	button.configure(definition, false, "", {}, true)
	# 已发动样式；使用大幅加深的通用深灰色，与暂不可发动的深红明确区分。
	var used_style: StyleBoxFlat = button.get_theme_stylebox("disabled") as StyleBoxFlat
	# 三态颜色副本；StyleBox在后续configure中会替换，局部值用于稳定比较。
	var available_color: Color = available_style.bg_color
	var unavailable_color: Color = unavailable_style.bg_color
	var used_color: Color = used_style.bg_color
	button.queue_free()
	if available_color != BattleUIStyle.get_color("danger") or selected_style.border_color != BattleUIStyle.get_color("accent") or unavailable_color.get_luminance() >= available_color.get_luminance() or used_color.get_luminance() >= unavailable_color.get_luminance() or used_color.s >= unavailable_color.s:
		return _fail("limited_skill_button_colors=%s/%s/%s" % [available_color, unavailable_color, used_color])
	return true


## 输出失败原因并结束无头进程；返回false便于调用方立即停止后续断言。
func _fail(reason: String) -> bool:
	push_error("TINGYUN_MECHANICS_FAIL:%s" % reason)
	get_tree().quit(1)
	return false
