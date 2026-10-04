extends Node

## 丹恒·饮月双技能专项回归。覆盖【伏辰】的“其他角色打出【杀】后获得之”与
## 【濯世】的三段弃置流程、区域口径、阶段额度与 AI 评分。
##
## 全部断言都通过正式公开端口执行：响应回收走 `_consume_response_card_uid_patterns`，
## 主动技发动走 `activate_skill`，选择提交走标准 `choose_cards` 动作，
## AI 评分走 `NonameAIEvaluator.score_choice_action` + 技能自身的 `score_ai_choice`。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController


## 延迟一帧执行全部断言，确保 GameDatabase 已完成武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立场景顺序执行丹恒·饮月专项回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_descriptions():
		return
	if not _test_fuchen_gains_other_players_sha():
		return
	if not _test_fuchen_ignores_own_sha():
		return
	if not _test_fuchen_ignores_non_sha_response():
		return
	if not _test_fuchen_ignores_equipment_response():
		return
	if not _test_fuchen_creates_no_choice():
		return
	if not _test_zhuoshi_requires_play_phase_cost_and_target():
		return
	if not _test_zhuoshi_full_chain():
		return
	if not _test_zhuoshi_cancel_first_step_is_free():
		return
	if not _test_zhuoshi_cancel_second_step_keeps_progress():
		return
	if not _test_zhuoshi_effect_discard_zone():
		return
	if not _test_zhuoshi_ai_choice_scores():
		return
	print("DANHENG_YINYUE_PASS fuchen=4 zhuoshi=6")
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
	_controller.state.match_id = "danheng-yinyue-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "丹恒饮月测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
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
	# 新建实体；装备区实体在离开该区时会触发装备离区效果，因此归属与区域必须写全。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.owner_id = player_id
	card.zone = "equipment"
	_controller.state.get_player(player_id).equipment[slot] = card
	return card


## 向指定角色判定区加入一张实体牌并返回该实体。
func _add_judgment(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新建实体；判定区牌不属于该角色“拥有的牌”，只用于区域口径断言。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.owner_id = player_id
	card.zone = "judgment"
	_controller.state.get_player(player_id).judgment_area.append(card)
	return card


## 校验武将静态资料、两条技能原文与锁定技/主动技元数据。
func _test_metadata_and_descriptions() -> bool:
	# 丹恒·饮月静态定义；性别、势力、体力与技能顺序必须与设计一致。
	var character: Dictionary = GameDatabase.get_character("danheng_yinyue")
	if character.is_empty():
		return _fail("character_missing")
	if str(character.get("display_name", "")) != "丹恒·饮月" or str(character.get("gender", "")) != "male" or str(character.get("faction", "")) != "xianzhou" or int(character.get("max_hp", 0)) != 4:
		return _fail("character_metadata=%s" % str(character))
	# 技能引用顺序；同时决定技能栏展示顺序。
	if (character.get("skills", []) as Array) != ["fuchen", "zhuoshi"]:
		return _fail("character_skills=%s" % str(character.get("skills", [])))
	# 需求指定的两条技能原文；任何字符、标点变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"fuchen":"锁定技，当其他角色打出一张【杀】后，你获得之。",
		"zhuoshi":"出牌阶段限一次，你可以弃置一张基本牌并选择一名其他角色，你弃置其一张手牌，然后你可再次弃置一张基本牌并弃置其一张牌，最后你可再次弃置一张基本牌并对其造成1点雷电伤害。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；静态数据库说明必须与期望逐字一致。
		var skill_id: String = str(skill_id_variant)
		var definition: Dictionary = GameDatabase.get_skill(skill_id)
		if str(definition.get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("description_%s=%s" % [skill_id, str(definition.get("description", ""))])
	# 【伏辰】必须是完整锁定技且不开放主动入口；【濯世】必须是出牌阶段主动技。
	var fuchen: Dictionary = GameDatabase.get_skill("fuchen")
	var zhuoshi: Dictionary = GameDatabase.get_skill("zhuoshi")
	if not bool(fuchen.get("lock", false)) or bool(fuchen.get("ui_enabled", true)):
		return _fail("fuchen_flags=%s/%s" % [fuchen.get("lock"), fuchen.get("ui_enabled")])
	if bool(zhuoshi.get("lock", true)) or not bool(zhuoshi.get("ui_enabled", false)) or str(zhuoshi.get("enable", "")) != "phaseUse":
		return _fail("zhuoshi_flags=%s/%s/%s" % [zhuoshi.get("lock"), zhuoshi.get("ui_enabled"), zhuoshi.get("enable")])
	return true


## 其他角色打出一张【杀】时，持有者获得该实体牌，且该牌不再位于弃牌堆。
func _test_fuchen_gains_other_players_sha() -> bool:
	_reset_state(3)
	if _install_skill(0, "fuchen") == null:
		return _fail("fuchen_install")
	# 二号角色手牌中的【杀】；由其打出后进入弃牌堆。
	var played: CardInstance = _add_hand(1, "sha", "spade", 7)
	# 持有者手牌基线；获得后必须恰好增加一张。
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	var resolved: CardInstance = _play_sha_response(1, played)
	if resolved == null:
		return _fail("fuchen_response_not_consumed")
	if _controller.state.get_player(0).hand.size() != owner_hand_before + 1:
		return _fail("fuchen_hand=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(0).find_hand_card(played.uid) == null:
		return _fail("fuchen_wrong_card")
	# 实体已被取回手牌，弃牌堆不得再保留同一 UID。
	for discarded: CardInstance in _controller.state.discard_pile:
		if discarded.uid == played.uid:
			return _fail("fuchen_still_in_discard")
	return true


## 持有者自己打出的【杀】不触发【伏辰】。
func _test_fuchen_ignores_own_sha() -> bool:
	_reset_state(3)
	if _install_skill(0, "fuchen") == null:
		return _fail("fuchen_own_install")
	# 持有者自己的【杀】；打出后应停留在弃牌堆。
	var own_sha: CardInstance = _add_hand(0, "sha", "club", 9)
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	if _play_sha_response(0, own_sha) == null:
		return _fail("fuchen_own_response_not_consumed")
	if _controller.state.get_player(0).hand.size() != owner_hand_before - 1:
		return _fail("fuchen_own_hand=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(0).find_hand_card(own_sha.uid) != null:
		return _fail("fuchen_own_reacquired")
	return true


## 其他角色打出的非【杀】响应（此处为【闪】）不触发【伏辰】。
func _test_fuchen_ignores_non_sha_response() -> bool:
	_reset_state(3)
	if _install_skill(0, "fuchen") == null:
		return _fail("fuchen_non_sha_install")
	# 二号角色手牌中的【闪】；以 shan 为响应牌名打出。
	var played_shan: CardInstance = _add_hand(1, "shan", "heart", 4)
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	if _controller._consume_response_card_uid_patterns(1, played_shan.uid, ["shan"] as Array[String], [], "", {"response_action":MatchController.CARD_ACTION_PLAY, "responder_id":1, "response_pattern":"shan"}) == null:
		return _fail("fuchen_non_sha_not_consumed")
	if _controller.state.get_player(0).hand.size() != owner_hand_before:
		return _fail("fuchen_non_sha_gained")
	if _controller.state.get_player(0).find_hand_card(played_shan.uid) != null:
		return _fail("fuchen_non_sha_wrong_card")
	return true


## 装备区提供的响应没有实体牌消耗，不得被【伏辰】误取他人装备。
func _test_fuchen_ignores_equipment_response() -> bool:
	_reset_state(3)
	if _install_skill(0, "fuchen") == null:
		return _fail("fuchen_equipment_install")
	# 二号角色的防具实体；装备响应只写入 equipment_uid 与 material_card_uids。
	var armor: CardInstance = _add_equipment(1, "armor", "bagua", "spade", 2)
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	_controller._emit_rule_timing("respond", 1, 1, -1, {"player_id":1, "response_pattern":"sha", "equipment_uid":armor.uid, "material_card_uids":[armor.uid], "response_action":MatchController.CARD_ACTION_PLAY}, -1)
	if _controller.state.get_player(0).hand.size() != owner_hand_before:
		return _fail("fuchen_equipment_gained")
	if _controller.state.get_player(0).find_hand_card(armor.uid) != null:
		return _fail("fuchen_equipment_stolen")
	if _controller.state.get_player(1).equipment.get("armor", null) == null:
		return _fail("fuchen_equipment_moved")
	return true


## 【伏辰】是锁定技：触发过程不创建任何选择请求，也不占用统一请求槽。
func _test_fuchen_creates_no_choice() -> bool:
	_reset_state(2)
	if _install_skill(0, "fuchen") == null:
		return _fail("fuchen_silent_install")
	if not _controller._pending_card_choice.is_empty():
		return _fail("fuchen_pre_pending")
	var played: CardInstance = _add_hand(1, "sha", "diamond", 6)
	if _play_sha_response(1, played) == null:
		return _fail("fuchen_silent_not_consumed")
	if not _controller._pending_card_choice.is_empty():
		return _fail("fuchen_created_choice=%s" % str(_controller._pending_card_choice.get("context", {})))
	return true


## 【濯世】的入口门槛：出牌阶段归属、至少一张基本牌费用、至少一名有手牌的合法目标。
func _test_zhuoshi_requires_play_phase_cost_and_target() -> bool:
	_reset_state(2)
	if _install_skill(0, "zhuoshi") == null:
		return _fail("zhuoshi_gate_install")
	# 没有基本牌：不开放入口。
	_add_hand(1, "shan", "heart", 4)
	if _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_no_cost_activated")
	# 有基本牌但其他角色没有手牌：不开放入口。
	_add_hand(0, "sha", "spade", 7)
	_controller.state.get_player(1).hand.clear()
	if _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_no_target_activated")
	# 补齐目标后可以发动，但非持有者回合不得发动。
	_add_hand(1, "shan", "heart", 4)
	_controller.state.current_player_id = 1
	if _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_wrong_owner_activated")
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "discard"
	if _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_wrong_phase_activated")
	_controller.state.current_phase = "play"
	if not _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_legal_activate_rejected")
	return true


## 【濯世】三段完整流程：每段各弃一张基本牌，依次拆手牌、拆任意一张牌、造成1点雷电伤害。
func _test_zhuoshi_full_chain() -> bool:
	_reset_state(2)
	# 持有者三张基本牌费用与目标两张手牌。
	var zhuoshi: SkillDefinition = _install_skill(0, "zhuoshi")
	if zhuoshi == null:
		return _fail("zhuoshi_chain_install")
	var cost_first: CardInstance = _add_hand(0, "sha", "spade", 7)
	var cost_second: CardInstance = _add_hand(0, "shan", "heart", 3)
	var cost_third: CardInstance = _add_hand(0, "sha", "club", 9)
	var victim_hand_first: CardInstance = _add_hand(1, "shan", "diamond", 11)
	var victim_hand_second: CardInstance = _add_hand(1, "sha", "heart", 5)
	if not _controller._pending_card_choice.is_empty():
		return _fail("zhuoshi_chain_pre_pending")
	if not _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_chain_activate_rejected")
	# 第一段：弃一张基本牌并选择目标。
	if not _submit_choice(0, [cost_first.uid], [1], true):
		return false
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("zhuoshi_chain_step1_cost=%d" % _controller.state.get_player(0).hand.size())
	# 第二段第一步：弃置其一张手牌（必选）。
	if not _submit_choice(0, [victim_hand_first.uid], [], true):
		return false
	if _controller.state.get_player(1).hand.size() != 1:
		return _fail("zhuoshi_chain_hand_effect=%d" % _controller.state.get_player(1).hand.size())
	# 第二段费用：再次弃置一张基本牌。
	if not _submit_choice(0, [cost_second.uid], [], true):
		return false
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("zhuoshi_chain_step2_cost=%d" % _controller.state.get_player(0).hand.size())
	# 第二段第二步：弃置其一张牌。
	if not _submit_choice(0, [victim_hand_second.uid], [], true):
		return false
	if _controller.state.get_player(1).hand.size() != 0:
		return _fail("zhuoshi_chain_any_effect=%d" % _controller.state.get_player(1).hand.size())
	# 第三段费用：弃最后一张基本牌，随后造成1点雷电伤害。
	var victim_hp_before: int = _controller.state.get_player(1).hp
	if not _submit_choice(0, [cost_third.uid], [], true):
		return false
	if _controller.state.get_player(1).hp != victim_hp_before - 1:
		return _fail("zhuoshi_chain_damage=%d" % _controller.state.get_player(1).hp)
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("zhuoshi_chain_leftover_hand=%d" % _controller.state.get_player(0).hand.size())
	# 出牌阶段限一次：额度已消费，且没有遗留请求。
	if zhuoshi.can_activate():
		return _fail("zhuoshi_chain_quota_alive")
	if not _controller._pending_card_choice.is_empty():
		return _fail("zhuoshi_chain_pending_left")
	return true


## 第一段取消：整次发动放弃，不消费阶段额度、不弃置任何牌。
func _test_zhuoshi_cancel_first_step_is_free() -> bool:
	_reset_state(2)
	var zhuoshi: SkillDefinition = _install_skill(0, "zhuoshi")
	if zhuoshi == null:
		return _fail("zhuoshi_cancel_install")
	var cost: CardInstance = _add_hand(0, "sha", "spade", 7)
	_add_hand(1, "shan", "heart", 4)
	if not _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_cancel_activate_rejected")
	if not _submit_choice(0, [], [], false):
		return false
	if not zhuoshi.can_activate():
		return _fail("zhuoshi_cancel_consumed_quota")
	if _controller.state.get_player(0).hand.size() != 1 or _controller.state.get_player(0).find_hand_card(cost.uid) == null:
		return _fail("zhuoshi_cancel_lost_card")
	if not _controller._pending_card_choice.is_empty():
		return _fail("zhuoshi_cancel_pending_left")
	return true


## 第二段费用取消：只有第二段不发生，第一段的拆牌结果保留，且阶段额度已经消费。
func _test_zhuoshi_cancel_second_step_keeps_progress() -> bool:
	_reset_state(2)
	var zhuoshi: SkillDefinition = _install_skill(0, "zhuoshi")
	if zhuoshi == null:
		return _fail("zhuoshi_step2_cancel_install")
	var cost_first: CardInstance = _add_hand(0, "sha", "spade", 7)
	var cost_second: CardInstance = _add_hand(0, "shan", "heart", 3)
	var victim_hand_first: CardInstance = _add_hand(1, "shan", "diamond", 11)
	# 目标第二张牌使第二段“弃置其一张牌”具备候选，第二段费用请求才会真正建立。
	var victim_hand_second: CardInstance = _add_hand(1, "sha", "club", 9)
	# 第一段正常完成。
	if not _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_step2_cancel_activate_rejected")
	if not _submit_choice(0, [cost_first.uid], [1], true):
		return false
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("zhuoshi_step2_cancel_own_step1_cost=%d" % _controller.state.get_player(0).hand.size())
	# 第二段第一步：弃置其一张手牌（必选）；目标手牌由2张变为1张。
	if not _submit_choice(0, [victim_hand_first.uid], [], true):
		return false
	if _controller.state.get_player(1).hand.size() != 1:
		return _fail("zhuoshi_step2_cancel_hand_effect=%d" % _controller.state.get_player(1).hand.size())
	# 第二段费用请求：取消表示放弃整段第二段。
	if not _submit_choice(0, [], [], false):
		return false
	# 第三段费用请求仍然存在；取消后流程正常结束。
	if not _submit_choice(0, [], [], false):
		return false
	if not _controller._pending_card_choice.is_empty():
		return _fail("zhuoshi_step2_cancel_pending_left")
	# 阶段额度已在第一段消费，因此即使第二、三段被取消也不能再次发动。
	if zhuoshi.can_activate():
		return _fail("zhuoshi_step2_cancel_quota_alive")
	# 第二、三段都没发生：持有者只失去第一段的一张费用牌，目标只剩未指定的第二张牌。
	if _controller.state.get_player(0).hand.size() != 1 or _controller.state.get_player(0).find_hand_card(cost_second.uid) == null:
		return _fail("zhuoshi_step2_cancel_own_hand=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.get_player(1).find_hand_card(victim_hand_second.uid) == null:
		return _fail("zhuoshi_step2_cancel_victim_card")
	return true


## “弃置其一张牌”的区域口径：只含手牌区与装备区，判定区的延时锦囊不参与。
func _test_zhuoshi_effect_discard_zone() -> bool:
	_reset_state(2)
	if _install_skill(0, "zhuoshi") == null:
		return _fail("zhuoshi_zone_install")
	_add_hand(0, "sha", "spade", 7)
	# 目标只有判定区一张牌：没有手牌，不构成第一段的合法目标。
	_add_judgment(1, "shandian", "spade", 1)
	if _controller.activate_skill(0, "zhuoshi"):
		return _fail("zhuoshi_judgment_only_target")
	# 目标补一张手牌与一张装备牌：第二段第二步候选应为手牌 + 装备，且不含判定区。
	var hand_card: CardInstance = _add_hand(1, "shan", "heart", 4)
	var armor: CardInstance = _add_equipment(1, "armor", "bagua", "club", 2)
	var candidates: Array[Dictionary] = _controller.get_hand_equipment_candidates(0, 1)
	if candidates.size() != 2:
		return _fail("zhuoshi_zone_candidates=%d" % candidates.size())
	# 候选区域集合；按稳定顺序为手牌、装备。
	var zones: Array[String] = []
	# 候选 UID 集合；用于确认判定区实体没有被混入。
	var candidate_uids: Array[int] = []
	for candidate: Dictionary in candidates:
		zones.append(str(candidate.get("zone", "")))
		candidate_uids.append(int(candidate.get("uid", -1)))
	if zones != ["hand", "equipment"]:
		return _fail("zhuoshi_zone_order=%s" % str(zones))
	if not candidate_uids.has(hand_card.uid) or not candidate_uids.has(armor.uid):
		return _fail("zhuoshi_zone_members=%s" % str(candidate_uids))
	# 判定区实体不得出现在候选里。
	for judgment_card: CardInstance in _controller.state.get_player(1).judgment_area:
		if candidate_uids.has(judgment_card.uid):
			return _fail("zhuoshi_zone_includes_judgment")
	return true


## 【濯世】AI 评分：各步确认分必须严格为正，需要放弃的分支必须给出严格负分。
func _test_zhuoshi_ai_choice_scores() -> bool:
	_reset_state(3)
	var zhuoshi: SkillDefinition = _install_skill(0, "zhuoshi")
	if zhuoshi == null:
		return _fail("zhuoshi_ai_install")
	# 费用牌与两名候选目标的手牌；1号为敌方（反贼）、2号为友方（忠臣）。
	var cost: CardInstance = _add_hand(0, "sha", "spade", 7)
	_add_hand(0, "shan", "heart", 3)
	_add_hand(1, "shan", "club", 4)
	_add_hand(2, "shan", "diamond", 5)
	# 评分用权威快照与评估器；与基础AI读取同一套公开字段。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	# 第一段请求：与技能实际建立的形状保持一致（kind + 费用候选 + 费用/目标数量约束）。
	# candidates 必须给出，否则 get_choice_card_value 会退回未知资源的固定值，评分口径与实战不一致。
	var first_request: Dictionary = {"candidates":_controller.get_hand_candidates(0, 0), "min_card_select":1, "max_card_select":1, "context":{"kind":"zhuoshi_cost_and_target"}}
	# 敌方与友方两条确认提交；只有目标不同。
	var enemy_first: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[cost.uid], "selected_target_ids":[1]}}
	var ally_first: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[cost.uid], "selected_target_ids":[2]}}
	if zhuoshi.score_ai_choice(snapshot, first_request, enemy_first, evaluator) <= 0.0:
		return _fail("zhuoshi_ai_enemy_first=%f" % zhuoshi.score_ai_choice(snapshot, first_request, enemy_first, evaluator))
	# 对友方发动不值得：必须给出严格负分，让通用策略的取消（0.0）成为更优解。
	if zhuoshi.score_ai_choice(snapshot, first_request, ally_first, evaluator) >= 0.0:
		return _fail("zhuoshi_ai_ally_first=%f" % zhuoshi.score_ai_choice(snapshot, first_request, ally_first, evaluator))
	# 取消动作恒为0分，不得为负，否则AI会拒绝一切可选发动。
	if not is_zero_approx(zhuoshi.score_ai_choice(snapshot, first_request, {"payload":{"confirmed":false}}, evaluator)):
		return _fail("zhuoshi_ai_cancel")
	# 第二段第一步（必选拆手牌）：确认必须是正分。
	var hand_request: Dictionary = {"min_card_select":1, "max_card_select":1, "context":{"kind":"zhuoshi_discard_target_hand", "target_id":1}}
	var hand_confirm: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[]}}
	if zhuoshi.score_ai_choice(snapshot, hand_request, hand_confirm, evaluator) <= 0.0:
		return _fail("zhuoshi_ai_hand_step")
	# 第二段费用（可选整段）：敌方为正、友方为负。
	var second_request: Dictionary = {"min_card_select":1, "max_card_select":1, "context":{"kind":"zhuoshi_second_cost", "target_id":1}}
	if zhuoshi.score_ai_choice(snapshot, second_request, enemy_first, evaluator) <= 0.0:
		return _fail("zhuoshi_ai_enemy_second")
	var ally_second_request: Dictionary = {"min_card_select":1, "max_card_select":1, "context":{"kind":"zhuoshi_second_cost", "target_id":2}}
	if zhuoshi.score_ai_choice(snapshot, ally_second_request, {"payload":{"confirmed":true, "selected_card_uids":[cost.uid]}}, evaluator) >= 0.0:
		return _fail("zhuoshi_ai_ally_second")
	# 第三段费用（可选整段）：雷电伤害对敌方为正、对友方为负。
	var third_request: Dictionary = {"min_card_select":1, "max_card_select":1, "context":{"kind":"zhuoshi_third_cost", "target_id":1}}
	if zhuoshi.score_ai_choice(snapshot, third_request, enemy_first, evaluator) <= 0.0:
		return _fail("zhuoshi_ai_enemy_third")
	var ally_third_request: Dictionary = {"min_card_select":1, "max_card_select":1, "context":{"kind":"zhuoshi_third_cost", "target_id":2}}
	if zhuoshi.score_ai_choice(snapshot, ally_third_request, {"payload":{"confirmed":true, "selected_card_uids":[cost.uid]}}, evaluator) >= 0.0:
		return _fail("zhuoshi_ai_ally_third")
	# 发动入口：存在敌方目标时必须为正分。
	if zhuoshi.score_ai_action(snapshot, {}, evaluator) <= 0.0:
		return _fail("zhuoshi_ai_action=%f" % zhuoshi.score_ai_action(snapshot, {}, evaluator))
	return true


## 以正式响应回收端口打出一张【杀】；返回解析后的响应实体，失败返回 null。
func _play_sha_response(player_id: int, card: CardInstance) -> CardInstance:
	return _controller._consume_response_card_uid_patterns(player_id, card.uid, ["sha"] as Array[String], [], "", {"response_action":MatchController.CARD_ACTION_PLAY, "responder_id":player_id, "response_pattern":"sha"})


## 为当前选择请求提交牌与目标；选择动作必须绑定创建时的同一请求编号。
func _submit_choice(actor_id: int, card_uids: Array[int], target_ids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_choice")
	# 当前请求稳定编号；同步恢复可能立刻创建下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":card_uids.duplicate(), "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected kind=%s" % str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")))
	return true


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("DANHENG_YINYUE_FAIL %s" % reason)
	get_tree().quit(1)
	return false
