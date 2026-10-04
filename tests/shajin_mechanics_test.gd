extends Node

## 砂金三技能专项回归。覆盖【筹码】的开局结算与幂等、【盲注】的两步颜色弃置与阶段结算、
## 【风口】的整批弃置计数与「连续获得后失去技能」。
##
## 全部断言都通过正式端口执行：开局与阶段时机走 `_emit_rule_timing()`，
## 主动技发动走 `activate_skill()`，选择提交走标准 `choose_cards` 动作，
## 真实批量获得走权威摸牌端口 `draw()`，AI 评分走 `NonameAIEvaluator.score_choice_action` 与技能自身的评分入口。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController


## 延迟一帧执行全部断言，确保 GameDatabase 已完成武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立场景顺序执行砂金专项回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_descriptions():
		return
	if not _test_chouma_game_start_and_idempotence():
		return
	if not _test_chouma_reads_max_hp():
		return
	if not _test_mangzhu_two_colours_shield_and_draw():
		return
	if not _test_mangzhu_rejects_same_colour_pair():
		return
	if not _test_mangzhu_single_colour_shield_only():
		return
	if not _test_mangzhu_no_common_colour():
		return
	if not _test_mangzhu_cancel_first_pick_is_free():
		return
	if not await _test_fengkou_triggers_from_chouma_game_start_draw():
		return
	if not await _test_fengkou_clause1_discards_whole_batch():
		return
	if not _test_fengkou_clause1_ignores_single_gain():
		return
	if not await _test_fengkou_clause1_triggers_in_game_start_window():
		return
	if not await _test_fengkou_clause2_repeats_and_loses_skill():
		return
	if not _test_fengkou_clause2_cancel_keeps_skill():
		return
	if not _test_fengkou_ai_scores():
		return
	print("SHAJIN_PASS metadata=1 chouma=2 mangzhu=5 fengkou=6")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能时机、伤害与护盾共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；身份观察与目标态度查询保持正式实现。
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


## 为单项测试创建最小权威状态并重建全部规则服务；身份全部公开以获得确定 AI 态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "shajin-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "砂金测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 3
		player.hp = 3
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()


## 安装指定技能并返回独立运行时实例；与正式固有技能安装使用同一 bind/install 顺序。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 待安装技能实例；数据库必须能按稳定ID创建独立对象。
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


## 向指定角色手牌区加入一张实体牌并返回该实体；正式对局由移动服务补齐区域与归属。
func _add_hand(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新建实体；UID 由 CardInstance 自身分配，测试只读取它作为稳定标识。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.owner_id = player_id
	card.zone = "hand"
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向指定角色装备区加入一张实体牌并返回该实体。
func _add_equipment(player_id: int, slot: String, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新建实体；装备区实体在候选里同样可见，用于验证【盲注】的费用区域覆盖。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.owner_id = player_id
	card.zone = "equipment"
	_controller.state.get_player(player_id).equipment[slot] = card
	return card


## 向摸牌堆压入指定数量的实体牌；权威摸牌端口需要非空牌堆。
func _fill_draw_pile(count: int) -> void:
	for index: int in range(count):
		_controller.state.draw_pile.append(CardInstance.new("shan", "heart", index % 13 + 1))


## 派发一次摸牌阶段结束时机的空载荷事件；本技能只读取控制器状态，不读取该事件数据。
func _emit_draw_phase_end() -> void:
	_controller._emit_rule_timing("phaseDrawEnd", 0, -1, 0, {}, -1)


## 把「刚获得的一张手牌」登记进状态并派发 gainAfter；用于模拟摸牌阶段内获得的牌。
func _simulate_gain(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 先入区再派发：技能在 gainAfter 期间按 UID 从手牌区解析实体，因此顺序不能颠倒。
	var card: CardInstance = _add_hand(player_id, definition_id, suit, rank)
	_controller._emit_rule_timing("gainAfter", player_id, -1, player_id, {"to_zone":"hand", "card_uids":[card.uid], "target_player_id":player_id}, -1)
	return card


## 等待【风口】第一段的延后询问出现。
## 本技能一律把询问推迟到下一个结算边界（见 `fengkou.gd` 的说明），因此批次事件之后请求不会同步出现，
## 必须让出进程帧让控制器的延后结算管线恢复。返回 false 表示等待上限内仍然没有请求。
func _await_clause1_choice() -> bool:
	for _attempt: int in range(8):
		if not _controller._pending_card_choice.is_empty():
			return true
		await get_tree().process_frame
	return not _controller._pending_card_choice.is_empty()


## 读取当前待处理请求的种类；无请求时返回空串。
func _pending_kind() -> String:
	if _controller._pending_card_choice.is_empty():
		return ""
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))


## 校验武将静态资料、三条技能原文与锁定/主动元数据。
func _test_metadata_and_descriptions() -> bool:
	# 砂金静态定义；性别、势力、体力与技能顺序必须与设计一致。
	var character: Dictionary = GameDatabase.get_character("shajin")
	if character.is_empty():
		return _fail("character_missing")
	if str(character.get("display_name", "")) != "砂金" or str(character.get("gender", "")) != "male" or str(character.get("faction", "")) != "xingjihepinggongsi" or int(character.get("max_hp", 0)) != 3:
		return _fail("character_metadata=%s" % str(character))
	if (character.get("skills", []) as Array) != ["chouma", "mangzhu", "fengkou"]:
		return _fail("character_skills=%s" % str(character.get("skills", [])))
	# 需求指定的三条技能原文；任何字符、标点变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"chouma":"锁定技，游戏开始时，你摸X张牌，你的手牌上限+X。（X为你的体力上限）",
		"mangzhu":"摸牌阶段开始时，你可以弃置任意张颜色不同的牌。若如此做，该阶段结束时，若你以此法弃置的牌与你于此阶段内获得的牌有至少一种颜色相同，你获得1点护盾；若有至少两种颜色相同，你摸两张牌。",
		"fengkou":"当你一次性获得至少两张牌时，你可以弃置这些牌。出牌阶段，你可以获得一名其他角色的随机一张手牌，你此前每发动一次该技能便重复一次该流程，然后你失去该技能。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；静态数据库说明必须与期望逐字一致。
		var skill_id: String = str(skill_id_variant)
		var definition: Dictionary = GameDatabase.get_skill(skill_id)
		if str(definition.get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("description_%s=%s" % [skill_id, str(definition.get("description", ""))])
	# 【筹码】必须是锁定技且不开放主动入口；【盲注】是被动触发；【风口】是出牌阶段主动技。
	var chouma: Dictionary = GameDatabase.get_skill("chouma")
	var mangzhu: Dictionary = GameDatabase.get_skill("mangzhu")
	var fengkou: Dictionary = GameDatabase.get_skill("fengkou")
	if not bool(chouma.get("lock", false)) or bool(chouma.get("ui_enabled", true)):
		return _fail("chouma_flags=%s/%s" % [chouma.get("lock"), chouma.get("ui_enabled")])
	if bool(mangzhu.get("ui_enabled", true)):
		return _fail("mangzhu_ui_enabled")
	if bool(fengkou.get("lock", true)) or not bool(fengkou.get("ui_enabled", false)) or str(fengkou.get("enable", "")) != "phaseUse":
		return _fail("fengkou_flags=%s/%s/%s" % [fengkou.get("lock"), fengkou.get("ui_enabled"), fengkou.get("enable")])
	return true


## 【筹码】开局摸X张并提升手牌上限X；重复派发同一时机不得叠加。
func _test_chouma_game_start_and_idempotence() -> bool:
	_reset_state(2)
	if _install_skill(0, "chouma") == null:
		return _fail("chouma_install")
	# 摸牌堆必须非空，否则权威摸牌端口无法给出实体牌。
	_fill_draw_pile(10)
	# 持有者体力上限为3，因此X=3。
	var limit_before: int = _controller.state.get_player(0).get_hand_limit()
	_controller._emit_rule_timing("gameStart", -1, -1, -1, {}, -1)
	if _controller.state.get_player(0).hand.size() != 3:
		return _fail("chouma_draw=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(0).get_hand_limit() != limit_before + 3:
		return _fail("chouma_limit=%d" % _controller.state.get_player(0).get_hand_limit())
	# 重复派发：幂等标记必须挡住整条效果。
	_controller._emit_rule_timing("gameStart", -1, -1, -1, {}, -1)
	if _controller.state.get_player(0).hand.size() != 3 or _controller.state.get_player(0).get_hand_limit() != limit_before + 3:
		return _fail("chouma_not_idempotent hand=%d limit=%d" % [_controller.state.get_player(0).hand.size(), _controller.state.get_player(0).get_hand_limit()])
	return true


## 【筹码】的X随持有者体力上限变化：体力上限为5时摸5张并把上限提升5。
func _test_chouma_reads_max_hp() -> bool:
	_reset_state(2)
	if _install_skill(0, "chouma") == null:
		return _fail("chouma_hp_install")
	# 抬高体力上限与当前体力；X 必须读取权威状态的最终体力上限而不是固定常量。
	_controller.state.get_player(0).max_hp = 5
	_controller.state.get_player(0).hp = 5
	_fill_draw_pile(10)
	_controller._emit_rule_timing("gameStart", -1, -1, -1, {}, -1)
	if _controller.state.get_player(0).hand.size() != 5:
		return _fail("chouma_hp_draw=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(0).get_hand_limit() != 10:
		return _fail("chouma_hp_limit=%d" % _controller.state.get_player(0).get_hand_limit())
	return true


## 【盲注】两种颜色都弃置且两种颜色都摸到：获得1点护盾并额外摸两张牌。
## 一次请求内点选两张异色牌，因此这里连续提交两张牌的 UID。
func _test_mangzhu_two_colours_shield_and_draw() -> bool:
	_reset_state(2)
	if _install_skill(0, "mangzhu") == null:
		return _fail("mangzhu_install")
	# 费用：手牌两张红色、两张黑色，装备区一张黑色；一次多选最多两张且必须异色。
	var red_hand: CardInstance = _add_hand(0, "sha", "heart", 3)
	var black_hand: CardInstance = _add_hand(0, "sha", "spade", 7)
	_add_hand(0, "shan", "diamond", 5)
	_add_hand(0, "shan", "club", 9)
	var black_armor: CardInstance = _add_equipment(0, "armor", "bagua", "spade", 2)
	# 摸牌堆用于阶段结束时的「摸两张牌」。
	_fill_draw_pile(6)
	# 进入持有者自己的摸牌阶段。
	_controller.state.current_phase = "draw"
	_controller.state.current_player_id = 0
	_controller._emit_rule_timing("phaseDrawBegin", 0, -1, 0, {}, -1)
	if _pending_kind() != "mangzhu_pick":
		return _fail("mangzhu_pick_kind=%s" % _pending_kind())
	# 一次提交两张异色牌：一红一黑。
	if not _submit_choice(0, [red_hand.uid, black_hand.uid], [], true):
		return false
	if _controller.state.get_player(0).find_hand_card(red_hand.uid) != null:
		return _fail("mangzhu_first_not_discarded")
	if _controller.state.get_player(0).find_hand_card(black_hand.uid) != null:
		return _fail("mangzhu_second_not_discarded")
	# 未点选的异色牌与装备区牌都必须留在原处。
	if _controller.state.get_player(0).equipment.get("armor", null) != black_armor:
		return _fail("mangzhu_equipment_moved")
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("mangzhu_cost_hand=%d" % _controller.state.get_player(0).hand.size())
	# 本阶段内摸到红、黑各一张；两张都必须在结算前落入手牌区。
	_simulate_gain(0, "sha", "heart", 11)
	_simulate_gain(0, "sha", "club", 12)
	_emit_draw_phase_end()
	if _controller.state.get_player(0).shield != 1:
		return _fail("mangzhu_shield=%d" % _controller.state.get_player(0).shield)
	# 结算后手牌：初始4张去掉弃置的2张，再加入获得的2张与【盲注】额外摸到的2张。
	if _controller.state.get_player(0).hand.size() != 6:
		return _fail("mangzhu_draw_hand=%d" % _controller.state.get_player(0).hand.size())
	return true


## 【盲注】一次多选的颜色互斥由权威组合表表达：同色两张不构成合法组合，异色两张才合法。
func _test_mangzhu_rejects_same_colour_pair() -> bool:
	_reset_state(2)
	if _install_skill(0, "mangzhu") == null:
		return _fail("mangzhu_candidate_install")
	# 两张红色与两张黑色；组合表里只允许「单张」与「一红一黑」。
	var red_first: CardInstance = _add_hand(0, "sha", "heart", 3)
	var red_second: CardInstance = _add_hand(0, "shan", "diamond", 5)
	var black_first: CardInstance = _add_hand(0, "sha", "spade", 7)
	var black_second: CardInstance = _add_hand(0, "shan", "club", 9)
	# UID 到颜色映射；用于独立校验权威组合表里的两张组合确实异色。
	var colour_by_uid: Dictionary = {
		red_first.uid:"red", red_second.uid:"red",
		black_first.uid:"black", black_second.uid:"black",
	}
	_controller.state.current_phase = "draw"
	_controller.state.current_player_id = 0
	_controller._emit_rule_timing("phaseDrawBegin", 0, -1, 0, {}, -1)
	if _pending_kind() != "mangzhu_pick":
		return _fail("mangzhu_combo_kind=%s" % _pending_kind())
	# 候选必须包含全部四张有颜色的牌，且请求允许一次选两张。
	if (_controller._pending_card_choice.get("candidates", []) as Array).size() != 4:
		return _fail("mangzhu_combo_candidates=%d" % (_controller._pending_card_choice.get("candidates", []) as Array).size())
	if int(_controller._pending_card_choice.get("max_card_select", 0)) != 2:
		return _fail("mangzhu_combo_max=%d" % int(_controller._pending_card_choice.get("max_card_select", 0)))
	# 权威组合表：1个空组合 + 4个单张 + 4个异色两张（两张红 × 两张黑）；界面据此压暗同色候选。
	var valid_combinations: Array = (_controller._pending_card_choice.get("context", {}) as Dictionary).get("valid_card_combinations", []) as Array
	if valid_combinations.size() != 9:
		return _fail("mangzhu_combo_table=%d" % valid_combinations.size())
	for combination_variant: Variant in valid_combinations:
		# 当前组合；两张时必须异色，一张时必须是有颜色的候选。
		var combination: Array = combination_variant as Array
		if combination.size() == 2:
			var first_colour: String = str(colour_by_uid.get(int(combination[0]), ""))
			var second_colour: String = str(colour_by_uid.get(int(combination[1]), ""))
			if first_colour.is_empty() or second_colour.is_empty() or first_colour == second_colour:
				return _fail("mangzhu_combo_pair=%s" % str(combination))
		elif combination.size() > 2:
			return _fail("mangzhu_combo_size=%d" % combination.size())
	# 同色两张必须被权威校验拒绝，且请求保持未决（等待重新提交）。
	if _try_submit_choice(0, [red_first.uid, red_second.uid], [], true):
		return _fail("mangzhu_combo_accepted_same_colour")
	if _pending_kind() != "mangzhu_pick":
		return _fail("mangzhu_combo_lost_request=%s" % _pending_kind())
	# 单张仍然合法；提交后按已发动处理。
	if not _submit_choice(0, [red_first.uid], [], true):
		return false
	if _controller.state.get_player(0).find_hand_card(red_first.uid) != null:
		return _fail("mangzhu_combo_single_not_discarded")
	# 收尾：本阶段内没有获得同色牌，结算不产生任何效果。
	_emit_draw_phase_end()
	if _controller.state.get_player(0).shield != 0:
		return _fail("mangzhu_combo_shield=%d" % _controller.state.get_player(0).shield)
	# 本场景共加入4张牌，只弃置了1张。
	if _controller.state.get_player(0).hand.size() != 3:
		return _fail("mangzhu_combo_hand=%d" % _controller.state.get_player(0).hand.size())
	return true


## 【盲注】只有一种颜色重合：只获得1点护盾，不额外摸牌。
func _test_mangzhu_single_colour_shield_only() -> bool:
	_reset_state(2)
	if _install_skill(0, "mangzhu") == null:
		return _fail("mangzhu_single_install")
	var red_card: CardInstance = _add_hand(0, "sha", "heart", 3)
	_add_hand(0, "sha", "spade", 7)
	_fill_draw_pile(6)
	_controller.state.current_phase = "draw"
	_controller.state.current_player_id = 0
	_controller._emit_rule_timing("phaseDrawBegin", 0, -1, 0, {}, -1)
	if not _submit_choice(0, [red_card.uid], [], true):
		return false
	if not _controller._pending_card_choice.is_empty():
		return _fail("mangzhu_single_pending_left")
	# 只摸到红色。
	_simulate_gain(0, "sha", "diamond", 11)
	# 结算前手牌：初始2张去掉1张，再加入1张。
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("mangzhu_single_pre_hand=%d" % _controller.state.get_player(0).hand.size())
	_emit_draw_phase_end()
	if _controller.state.get_player(0).shield != 1:
		return _fail("mangzhu_single_shield=%d" % _controller.state.get_player(0).shield)
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("mangzhu_single_draw_hand=%d" % _controller.state.get_player(0).hand.size())
	return true


## 【盲注】弃置的颜色与阶段内获得的颜色完全不重合：护盾与摸牌都不发生。
func _test_mangzhu_no_common_colour() -> bool:
	_reset_state(2)
	if _install_skill(0, "mangzhu") == null:
		return _fail("mangzhu_none_install")
	var red_card: CardInstance = _add_hand(0, "sha", "heart", 3)
	_add_hand(0, "sha", "spade", 7)
	_fill_draw_pile(6)
	_controller.state.current_phase = "draw"
	_controller.state.current_player_id = 0
	_controller._emit_rule_timing("phaseDrawBegin", 0, -1, 0, {}, -1)
	# 只弃置红色一张；黑色那张留在手里作为对照。
	if not _submit_choice(0, [red_card.uid], [], true):
		return false
	# 只摸到黑色，与弃置的红色不重合。
	_simulate_gain(0, "sha", "club", 11)
	_emit_draw_phase_end()
	if _controller.state.get_player(0).shield != 0:
		return _fail("mangzhu_none_shield=%d" % _controller.state.get_player(0).shield)
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("mangzhu_none_hand=%d" % _controller.state.get_player(0).hand.size())
	return true


## 【盲注】直接取消：不弃置任何牌、不产生记录，阶段结束也没有任何效果。
func _test_mangzhu_cancel_first_pick_is_free() -> bool:
	_reset_state(2)
	if _install_skill(0, "mangzhu") == null:
		return _fail("mangzhu_cancel_install")
	# 只放一张牌，便于断言手牌完全没有变化。
	var only_card: CardInstance = _add_hand(0, "sha", "heart", 3)
	_fill_draw_pile(6)
	_controller.state.current_phase = "draw"
	_controller.state.current_player_id = 0
	_controller._emit_rule_timing("phaseDrawBegin", 0, -1, 0, {}, -1)
	if _pending_kind() != "mangzhu_pick":
		return _fail("mangzhu_cancel_kind=%s" % _pending_kind())
	if not _submit_choice(0, [], [], false):
		return false
	if not _controller._pending_card_choice.is_empty():
		return _fail("mangzhu_cancel_pending_left")
	if _controller.state.get_player(0).find_hand_card(only_card.uid) == null:
		return _fail("mangzhu_cancel_discarded")
	# 没有真实弃置，因此即使摸到同色也不结算。
	_simulate_gain(0, "sha", "heart", 11)
	_emit_draw_phase_end()
	if _controller.state.get_player(0).shield != 0 or _controller.state.get_player(0).hand.size() != 2:
		return _fail("mangzhu_cancel_effect shield=%d hand=%d" % [_controller.state.get_player(0).shield, _controller.state.get_player(0).hand.size()])
	return true


## 【风口】与【筹码】联动：开局锁定技的摸X张牌同样是一次性获得，必须能触发第一段。
func _test_fengkou_triggers_from_chouma_game_start_draw() -> bool:
	_reset_state(2)
	if _install_skill(0, "chouma") == null:
		return _fail("fengkou_chouma_chouma_install")
	if _install_skill(0, "fengkou") == null:
		return _fail("fengkou_chouma_fengkou_install")
	_fill_draw_pile(12)
	# 开局配置阶段派发 gameStart：【筹码】摸 3 张（X == 体力上限3），构成 batch_size == 3 的批次。
	_controller.state.current_phase = "game_start"
	_controller._emit_rule_timing("gameStart", -1, -1, -1, {}, -1)
	if _controller.state.get_player(0).hand.size() != 3:
		return _fail("fengkou_chouma_draw=%d" % _controller.state.get_player(0).hand.size())
	if not await _await_clause1_choice():
		return _fail("fengkou_chouma_missing")
	if _pending_kind() != "fengkou_clause1":
		return _fail("fengkou_chouma_kind=%s" % _pending_kind())
	# 批次候选必须精确等于【筹码】刚摸到的三张牌。
	if (_controller._pending_card_choice.get("candidates", []) as Array).size() != 3:
		return _fail("fengkou_chouma_candidates=%d" % (_controller._pending_card_choice.get("candidates", []) as Array).size())
	if not _submit_choice(0, [], [], true):
		return false
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("fengkou_chouma_hand=%d" % _controller.state.get_player(0).hand.size())
	if int(_controller.state.get_player(0).character_form_state.get("fengkou_clause1_count", 0)) != 1:
		return _fail("fengkou_chouma_count")
	return true


## 【风口】第一段：一次获得两张牌时可以选择弃置整批；点确认即整批进弃牌堆并累加一次计数。
## 请求本身是零选择确认：min == max == 0，玩家不需要（也不能）逐张挑选。
func _test_fengkou_clause1_discards_whole_batch() -> bool:
	_reset_state(2)
	if _install_skill(0, "fengkou") == null:
		return _fail("fengkou_clause1_install")
	_fill_draw_pile(6)
	# 真实批量获得：权威摸牌端口一次发两张，核心据此派发 batch_size == 2 的批次事件。
	_controller.draw(0, 2)
	if not await _await_clause1_choice():
		return _fail("fengkou_clause1_missing")
	if _pending_kind() != "fengkou_clause1":
		return _fail("fengkou_clause1_kind=%s" % _pending_kind())
	# 候选必须精确等于本批次的两张牌，且 min == max == 0，玩家只需点确认。
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if candidates.size() != 2:
		return _fail("fengkou_clause1_candidates=%d" % candidates.size())
	if int(_controller._pending_card_choice.get("min_card_select", -1)) != 0 or int(_controller._pending_card_choice.get("max_card_select", -1)) != 0:
		return _fail("fengkou_clause1_bounds=%d/%d" % [int(_controller._pending_card_choice.get("min_card_select", -1)), int(_controller._pending_card_choice.get("max_card_select", -1))])
	# 两张牌都必须仍在持有者手牌中，证明候选来自本批次而不是其他手牌。
	var batch_uids: Array[int] = []
	for candidate_variant: Variant in candidates:
		batch_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	for card_uid: int in batch_uids:
		if _controller.state.get_player(0).find_hand_card(card_uid) == null:
			return _fail("fengkou_clause1_candidate_not_in_hand uid=%d" % card_uid)
	# 零选择确认：不带任何选牌提交。
	if not _submit_choice(0, [], [], true):
		return false
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("fengkou_clause1_hand=%d" % _controller.state.get_player(0).hand.size())
	if int(_controller.state.get_player(0).character_form_state.get("fengkou_clause1_count", 0)) != 1:
		return _fail("fengkou_clause1_count=%d" % int(_controller.state.get_player(0).character_form_state.get("fengkou_clause1_count", 0)))
	return true


## 【风口】第一段：单张获得不构成「一次性获得至少两张牌」，不创建请求。
func _test_fengkou_clause1_ignores_single_gain() -> bool:
	_reset_state(2)
	if _install_skill(0, "fengkou") == null:
		return _fail("fengkou_single_install")
	_fill_draw_pile(6)
	# 一次只摸一张；批次大小为1，第一段不介入。
	_controller.draw(0, 1)
	if not _controller._pending_card_choice.is_empty():
		return _fail("fengkou_single_pending=%s" % _pending_kind())
	if int(_controller.state.get_player(0).character_form_state.get("fengkou_clause1_count", 0)) != 0:
		return _fail("fengkou_single_count")
	# 直接获得一张普通手牌同样不触发（走 gainAfter 而不是批量获得时机）。
	_simulate_gain(0, "sha", "spade", 7)
	if not _controller._pending_card_choice.is_empty():
		return _fail("fengkou_single_gain_pending=%s" % _pending_kind())
	return true


## 【风口】第一段：开局配置阶段的批量获得同样触发，因为【筹码】的开局摸牌也是「一次性获得至少两张牌」。
func _test_fengkou_clause1_triggers_in_game_start_window() -> bool:
	_reset_state(2)
	if _install_skill(0, "fengkou") == null:
		return _fail("fengkou_game_start_install")
	_fill_draw_pile(6)
	# 开局配置阶段：只有【筹码】的锁定技摸牌会发生在这里，它同样是一次性获得，必须开放本次机会。
	_controller.state.current_phase = "game_start"
	_controller.draw(0, 2)
	if not await _await_clause1_choice():
		return _fail("fengkou_game_start_missing")
	if _pending_kind() != "fengkou_clause1":
		return _fail("fengkou_game_start_kind=%s" % _pending_kind())
	# 零选择确认：整批两张都进弃牌堆并累加一次计数。
	if not _submit_choice(0, [], [], true):
		return false
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("fengkou_game_start_hand=%d" % _controller.state.get_player(0).hand.size())
	if int(_controller.state.get_player(0).character_form_state.get("fengkou_clause1_count", 0)) != 1:
		return _fail("fengkou_game_start_count")
	# 取消时不产生任何记录，证明这次机会是可选的而不是强制的。
	_controller.draw(0, 2)
	if not await _await_clause1_choice():
		return _fail("fengkou_game_start_cancel_missing")
	if not _submit_choice(0, [], [], false):
		return false
	if int(_controller.state.get_player(0).character_form_state.get("fengkou_clause1_count", 0)) != 1:
		return _fail("fengkou_game_start_cancel_count")
	return true


## 【风口】第二段：按「1 + 第一段发动次数」连续获得随机手牌，随后永久失去本技能。
func _test_fengkou_clause2_repeats_and_loses_skill() -> bool:
	_reset_state(2)
	if _install_skill(0, "fengkou") == null:
		return _fail("fengkou_clause2_install")
	_fill_draw_pile(6)
	# 先真实发动一次第一段，使计数为1，第二段的重复次数因此为2。
	_controller.draw(0, 2)
	if not await _await_clause1_choice():
		return _fail("fengkou_clause2_setup_missing")
	if _pending_kind() != "fengkou_clause1":
		return _fail("fengkou_clause2_setup_kind=%s" % _pending_kind())
	var setup_uids: Array[int] = []
	for candidate_variant: Variant in _controller._pending_card_choice.get("candidates", []) as Array:
		setup_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	if setup_uids.size() != 2:
		return _fail("fengkou_clause2_setup_candidates=%d" % setup_uids.size())
	# 零选择确认：不带任何选牌提交，整批两张都进弃牌堆。
	if not _submit_choice(0, [], [], true):
		return false
	# 目标准备三张手牌；重复2次后应剩1张。
	_add_hand(1, "sha", "spade", 2)
	_add_hand(1, "shan", "heart", 4)
	_add_hand(1, "shan", "club", 6)
	# 进入持有者自己的出牌阶段。
	_controller.state.current_phase = "play"
	_controller.state.current_player_id = 0
	# 技能实例存在才能验证「然后你失去该技能」。
	if _controller.get_skill_instance(0, "fengkou") == null:
		return _fail("fengkou_missing_before_use")
	if not _controller.activate_skill(0, "fengkou"):
		return _fail("fengkou_activate_rejected")
	if _pending_kind() != "fengkou_clause2_target":
		return _fail("fengkou_clause2_kind=%s" % _pending_kind())
	if int((_controller._pending_card_choice.get("context", {}) as Dictionary).get("repeat_total", -1)) != 2:
		return _fail("fengkou_repeat_total=%d" % int((_controller._pending_card_choice.get("context", {}) as Dictionary).get("repeat_total", -1)))
	if not _submit_choice(0, [], [1], true):
		return false
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("fengkou_gained=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(1).hand.size() != 1:
		return _fail("fengkou_target_hand=%d" % _controller.state.get_player(1).hand.size())
	# 发动后永久失去本技能。
	if _controller.get_skill_instance(0, "fengkou") != null:
		return _fail("fengkou_not_removed")
	if (_controller.skill_instances_by_player.get(0, {}) as Dictionary).has("fengkou"):
		return _fail("fengkou_still_installed")
	if not _controller._pending_card_choice.is_empty():
		return _fail("fengkou_clause2_pending_left")
	return true


## 【风口】第二段：在目标选择处取消，不获得任何牌，也不失去技能。
func _test_fengkou_clause2_cancel_keeps_skill() -> bool:
	_reset_state(2)
	if _install_skill(0, "fengkou") == null:
		return _fail("fengkou_cancel_install")
	_add_hand(1, "sha", "spade", 2)
	_controller.state.current_phase = "play"
	_controller.state.current_player_id = 0
	if not _controller.activate_skill(0, "fengkou"):
		return _fail("fengkou_cancel_activate_rejected")
	if _pending_kind() != "fengkou_clause2_target":
		return _fail("fengkou_cancel_kind=%s" % _pending_kind())
	if not _submit_choice(0, [], [], false):
		return false
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("fengkou_cancel_gained=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(1).hand.size() != 1:
		return _fail("fengkou_cancel_target_hand=%d" % _controller.state.get_player(1).hand.size())
	if _controller.get_skill_instance(0, "fengkou") == null:
		return _fail("fengkou_cancel_lost_skill")
	# 取消后入口必须立即恢复可用。
	if not _controller.activate_skill(0, "fengkou"):
		return _fail("fengkou_cancel_not_reactivatable")
	if not _submit_choice(0, [], [], false):
		return false
	return true


## 【风口】AI 评分：第一段的整批价值越高越应放弃；第二段对敌方为正、对友方为负，累计不足时不发动。
func _test_fengkou_ai_scores() -> bool:
	_reset_state(3)
	var fengkou: SkillDefinition = _install_skill(0, "fengkou")
	if fengkou == null:
		return _fail("fengkou_ai_install")
	# 评分用样本牌：一张低价值【杀】与三张高价值手牌（用于制造「整批太贵」的场景）。
	var cheap_slash: CardInstance = _add_hand(0, "sha", "spade", 7)
	_add_hand(1, "shan", "club", 4)
	_add_hand(2, "shan", "diamond", 5)
	# 评分用权威快照与评估器；与基础AI读取同一套公开字段。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	# 第一段请求；candidates 必须给出，否则 get_choice_card_value 会退回未知资源的固定值，评分口径与实战不一致。
	# 批次成员由 context.batch_uids 提供：真实请求是零选择确认，提交里没有选牌。
	var cheap_context: Dictionary = {"kind":"fengkou_clause1", "batch_uids":[cheap_slash.uid]}
	var clause1_request: Dictionary = {"candidates":_controller.get_hand_candidates(0, 0), "min_card_select":0, "max_card_select":0, "context":cheap_context}
	var cheap_action: Dictionary = {"payload":{"confirmed":true}}
	# 便宜的单张批次：积累一次次数的价值高于弃置这张牌，判为应当确认。
	if fengkou.score_ai_choice(snapshot, clause1_request, cheap_action, evaluator) <= 0.0:
		return _fail("fengkou_ai_clause1_cheap=%f" % fengkou.score_ai_choice(snapshot, clause1_request, cheap_action, evaluator))
	# 取消必须是0分基准，不能为负，否则AI会拒绝一切可选的第一段。
	if not is_zero_approx(fengkou.score_ai_choice(snapshot, clause1_request, {"payload":{"confirmed":false}}, evaluator)):
		return _fail("fengkou_ai_clause1_cancel")
	# 整批都很贵时应放弃：把批次换成两张高价值手牌后重新评分。
	var expensive_uid: int = _add_hand(0, "sha", "heart", 1).uid
	var expensive_context: Dictionary = {"kind":"fengkou_clause1", "batch_uids":[cheap_slash.uid, expensive_uid]}
	var expensive_request: Dictionary = {"candidates":_controller.get_hand_candidates(0, 0), "min_card_select":0, "max_card_select":0, "context":expensive_context}
	# 单张批次仍可能为正（1.75 点资源略低于 2.0）；改用两张批次验证「批次越大越容易放弃」的边界。
	if fengkou.score_ai_choice(snapshot, expensive_request, {"payload":{"confirmed":true}}, evaluator) >= 0.0:
		return _fail("fengkou_ai_clause1_batch=%f" % fengkou.score_ai_choice(snapshot, expensive_request, {"payload":{"confirmed":true}}, evaluator))
	# 第二段：累计不足 AI_MIN_REPEAT_COUNT 时发动入口为0分，避免为一张牌永久失去技能。
	_controller.state.get_player(0).character_form_state["fengkou_clause1_count"] = 0
	_controller.state.current_phase = "play"
	_controller.state.current_player_id = 0
	if not is_zero_approx(fengkou.score_ai_action(snapshot, {}, evaluator)):
		return _fail("fengkou_ai_action_early=%f" % fengkou.score_ai_action(snapshot, {}, evaluator))
	# 累计到2次后：对敌方（一号位反贼）为正分。
	_controller.state.get_player(0).character_form_state["fengkou_clause1_count"] = 1
	if fengkou.score_ai_action(snapshot, {}, evaluator) <= 0.0:
		return _fail("fengkou_ai_action_enemy=%f" % fengkou.score_ai_action(snapshot, {}, evaluator))
	# 第二段选目标的评分：敌方为正、友方为严格负分。
	var clause2_request: Dictionary = {"context":{"kind":"fengkou_clause2_target", "repeat_total":2}}
	if fengkou.score_ai_choice(snapshot, clause2_request, {"payload":{"confirmed":true, "selected_target_ids":[1]}}, evaluator) <= 0.0:
		return _fail("fengkou_ai_clause2_enemy")
	if fengkou.score_ai_choice(snapshot, clause2_request, {"payload":{"confirmed":true, "selected_target_ids":[2]}}, evaluator) >= 0.0:
		return _fail("fengkou_ai_clause2_ally")
	if not is_zero_approx(fengkou.score_ai_choice(snapshot, clause2_request, {"payload":{"confirmed":false}}, evaluator)):
		return _fail("fengkou_ai_clause2_cancel")
	return true


## 为当前选择请求提交牌与目标；选择动作必须绑定创建时的同一请求编号。
func _submit_choice(actor_id: int, card_uids: Array[int], target_ids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_choice")
	# 当前请求稳定编号；同步恢复可能立刻创建下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":card_uids.duplicate(), "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected kind=%s" % _pending_kind())
	return true


## 提交一个预期会被权威校验拒绝的选择，返回控制器的实际接受结果；不产生失败标记，供「非法提交必须被拒」的场景使用。
func _try_submit_choice(actor_id: int, card_uids: Array[int], target_ids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return false
	# 当前请求稳定编号；被拒绝时请求保持未决，编号不变。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":card_uids.duplicate(), "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	return _controller.submit_action(action)


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("SHAJIN_FAIL %s" % reason)
	get_tree().quit(1)
	return false
