extends Node

## 卡厄斯兰那三技能实战回归。覆盖换形态往返后的轮回复位、轮回节无合法内容时的空过推进，以及致命自伤/必中火【杀】的AI否决。

## 本测试共用的权威对局控制器；每项用例通过正式规则服务和技能实例执行。
var _controller: MatchController


## 延迟一帧开始回归，确保GameDatabase已完成目录扫描与静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部卡厄斯兰那实战断言；任一失败立即以非零状态退出。
func _run() -> void:
	_create_controller()
	if not _test_transform_roundtrip_resets_reincarnation():
		return
	if not _test_tiancai_empty_section_advances():
		return
	if not _test_shihun_stale_target_advances():
		return
	if not _test_shihun_retaliation_after_slash_used():
		return
	if not _test_shihun_retaliation_beyond_attack_range():
		return
	if not _test_shihun_retaliation_ignores_dead_target():
		return
	if not _test_lethal_self_harm_ai_veto():
		return
	if not _test_lethal_incoming_slash_ai_veto():
		return
	print("KAESILANNA_COMBAT_PASS roundtrip+empty_section+stale_target+retaliation_limits+skip_dead_target+ai_veto")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器和离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0


## 建立最小身份局状态并重建规则服务；0号领袖、1号反贼、其余忠臣，全部角色初始无手牌。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = ""
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		var player: PlayerState = PlayerState.new(player_id, "卡厄斯兰那回归玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.character_id = "wandi"
		player.character_generation = 1
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()


## 安装指定技能并返回独立运行时实例；绑定与安装顺序和正式武将技能一致。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 校验白厄→卡厄斯兰那→永劫返生→再次觉醒后，弑魂必须重新从①与轮回数1开始且可以发动。
## 回归目标：轮回节曾停留在②，而记录“上次指定目标”的运行时字段随旧实例销毁，导致技能永久不可发动。
func _test_transform_roundtrip_resets_reincarnation() -> bool:
	_reset_state(3)
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "baie"
	owner.max_hp = 4
	owner.hp = 4
	_controller._replace_native_character_skills(owner, [] as Array, ["fuhuo", "lunhui"] as Array)
	if not _controller.replace_player_character_card(0, "kaesilanna", "kaesilanna_roundtrip_in", true):
		return _fail("roundtrip_transform_in")
	var shihun: SkillDefinition = _controller.get_skill_instance(0, "shihun")
	if shihun == null or shihun.activate({"target_ids":[1]}) != "":
		return _fail("roundtrip_section_one_activate")
	# ①建立的火【杀】属于连续结算队列；排空统一管线后轮回节才会推进。
	_controller.resume_settlement_pipeline()
	if shihun.get_reincarnation_section_index() != 1:
		return _fail("roundtrip_section_one=%s" % shihun.get_reincarnation_state())
	# 体力归零触发【永劫】返生；换回白厄时旧形态的轮回登记必须一并清除。
	owner.hp = 0
	_controller.emit_rule_timing("dyingBegin", 0, -1, 0, {"hp":0, "required_recover":1})
	if owner.character_id != "baie" or not _controller.get_reincarnation_skill_state(0, "shihun").is_empty() or not _controller.get_reincarnation_skill_state(0, "tiancai").is_empty() or not _controller.get_reincarnation_skill_state(0, "yongjie").is_empty():
		return _fail("roundtrip_return=%s/%s" % [owner.character_id, _controller.get_reincarnation_skill_state(0, "shihun")])
	# 再次觉醒；弑魂必须回到①、轮回数1并重新开放发动。
	if not _controller.replace_player_character_card(0, "kaesilanna", "kaesilanna_roundtrip_again", true):
		return _fail("roundtrip_transform_back")
	var shihun_again: SkillDefinition = _controller.get_skill_instance(0, "shihun")
	if shihun_again == null or shihun_again.get_reincarnation_section_index() != 0 or shihun_again.get_reincarnation_round_count() != 1 or not shihun_again.can_activate():
		return _fail("roundtrip_second=%s" % (shihun_again.get_reincarnation_state() if shihun_again != null else "missing"))
	return true


## 校验【天裁】②在没有任何合法火攻目标时仍可发动，并直接完成该节推进到③。
## 回归目标：火攻要求目标拥有手牌，全场无手牌时该节曾永久不可发动，轮回停滞。
func _test_tiancai_empty_section_advances() -> bool:
	_reset_state(3)
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	var tiancai: SkillDefinition = _install_skill(0, "tiancai")
	if tiancai == null or tiancai.activate({}) != "" or tiancai.get_reincarnation_section_index() != 1:
		return _fail("tiancai_empty_section_one=%s" % (tiancai.get_reincarnation_state() if tiancai != null else "missing"))
	# 全场（含持有者自己）没有手牌，②不存在合法火攻目标。
	if not tiancai.can_activate() or tiancai.activate({}) != "" or tiancai.get_reincarnation_section_index() != 2:
		return _fail("tiancai_empty_section_two=%s" % tiancai.get_reincarnation_state())
	# X=1时③使用0张火攻，直接完成并进入下一轮回的①。
	if tiancai.activate({}) != "" or tiancai.get_reincarnation_section_index() != 0 or tiancai.get_reincarnation_round_count() != 2:
		return _fail("tiancai_empty_section_three=%s" % tiancai.get_reincarnation_state())
	return true


## 校验【弑魂】②在①指定的目标全部失效时仍可发动，并直接完成该节进入下一轮回。
## 回归目标：目标死亡、离场、超出距离或次数用尽都会让②永久不可发动。
## 补充：目标死亡与离场属于永久失效，②按本节无内容直接推进；
## 而“本阶段【杀】次数”与“到目标距离”是可由技能自身覆写解除的临时限制，
## 现已由②的 rule_overrides 忽略，并由下面两个用例固定其行为。
func _test_shihun_stale_target_advances() -> bool:
	_reset_state(3)
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	var shihun: SkillDefinition = _install_skill(0, "shihun")
	if shihun == null or shihun.activate({"target_ids":[1]}) != "":
		return _fail("shihun_stale_section_one_activate")
	# ①建立的火【杀】属于连续结算队列；排空统一管线后轮回节才会推进。
	_controller.resume_settlement_pipeline()
	if shihun.get_reincarnation_section_index() != 1:
		return _fail("shihun_stale_section_one=%s" % shihun.get_reincarnation_state())
	# ①指定的角色死亡；②的固定目标不再合法。
	_controller.state.get_player(1).alive = false
	if not shihun.can_activate() or shihun.activate({}) != "" or shihun.get_reincarnation_section_index() != 0 or shihun.get_reincarnation_round_count() != 2:
		return _fail("shihun_stale_section_two=%s" % shihun.get_reincarnation_state())
	return true


## 校验【弑魂】②在本阶段【杀】次数已用尽时仍能打出火【杀】。
## 回归目标：【永劫】持续把持有者手牌视为火【杀】，玩家因此每阶段都会用掉【杀】基础次数；
## 若②沿用标准【杀】的次数限制，②会在每一回合都只空推轮回节，界面上表现为“点击后没有任何效果”。
func _test_shihun_retaliation_after_slash_used() -> bool:
	_reset_state(3)
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	# 本阶段已使用一张同组【杀】；与 _get_grouped_play_count 读取的阶段历史保持一致。
	owner.play_phase_card_use_history["sha_fire"] = 1
	var shihun: SkillDefinition = _install_skill(0, "shihun")
	if shihun == null or shihun.activate({"target_ids":[1]}) != "":
		return _fail("shihun_slash_used_section_one_activate")
	# ①建立的火【杀】属于连续结算队列；排空统一管线后轮回节才会推进。
	_controller.resume_settlement_pipeline()
	if shihun.get_reincarnation_section_index() != 1:
		return _fail("shihun_slash_used_section_one=%s" % shihun.get_reincarnation_state())
	# ②的固定目标；必须真实承受反击火【杀】的1点火焰伤害。
	var target: PlayerState = _controller.state.get_player(1)
	if not shihun.can_activate() or shihun.activate({}) != "":
		return _fail("shihun_slash_used_section_two_activate")
	_controller.resume_settlement_pipeline()
	if target.hp != 4 or shihun.get_reincarnation_section_index() != 0 or shihun.get_reincarnation_round_count() != 2:
		return _fail("shihun_slash_used_section_two=%d/%s" % [target.hp, shihun.get_reincarnation_state()])
	return true


## 校验【弑魂】②能对①指定过的远距离目标使用火【杀】。
## 回归目标：①忽略距离，②若沿用标准【杀】的攻击范围限制，
## ①指定的远处角色必然让②在同一回合内静默失效，与①的合法选择自相矛盾。
func _test_shihun_retaliation_beyond_attack_range() -> bool:
	_reset_state(4)
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	var shihun: SkillDefinition = _install_skill(0, "shihun")
	# 2号与0号之间隔一名角色，距离为2，超出默认攻击范围1。
	if shihun == null or shihun.activate({"target_ids":[2]}) != "":
		return _fail("shihun_far_target_section_one_activate")
	_controller.resume_settlement_pipeline()
	if shihun.get_reincarnation_section_index() != 1:
		return _fail("shihun_far_target_section_one=%s" % shihun.get_reincarnation_state())
	# ②的固定目标；远距离目标同样必须承受1点火焰伤害。
	var target: PlayerState = _controller.state.get_player(2)
	if not shihun.can_activate() or shihun.activate({}) != "":
		return _fail("shihun_far_target_section_two_activate")
	_controller.resume_settlement_pipeline()
	if target.hp != 4 or shihun.get_reincarnation_section_index() != 0:
		return _fail("shihun_far_target_section_two=%d/%s" % [target.hp, shihun.get_reincarnation_state()])
	return true


## 校验【弑魂】②在①指定的一部分目标阵亡后，忽略该目标并对剩余目标使用火【杀】。
## 回归目标：②原先要求整批目标同时合法，任一目标死亡就整节落到空节分支，
## 玩家侧表现为“上次指定过两个人，其中一个死了，②就再也打不出反击”。
func _test_shihun_retaliation_ignores_dead_target() -> bool:
	_reset_state(4)
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	var shihun: SkillDefinition = _install_skill(0, "shihun")
	# ①指定两名使用者；②的记录因此为[1, 2]，本次仅其中一名会失效。
	if shihun == null or shihun.activate({"target_ids":[1, 2]}) != "":
		return _fail("shihun_skip_dead_section_one_activate")
	# ①建立的火【杀】属于连续结算队列；排空统一管线后轮回节才会推进。
	_controller.resume_settlement_pipeline()
	if shihun.get_reincarnation_section_index() != 1:
		return _fail("shihun_skip_dead_section_one=%s" % shihun.get_reincarnation_state())
	# ①指定的2号使用者阵亡；②必须忽略它并继续对仍存活的1号反击。
	_controller.state.get_player(2).alive = false
	# 仍然存活的②目标；必须真实承受反击火【杀】的1点火焰伤害。
	var live_target: PlayerState = _controller.state.get_player(1)
	# 反击前体力；用于确认伤害确实来自②打出的火【杀】而不是其他结算。
	var live_hp_before: int = live_target.hp
	if not shihun.can_activate() or shihun.activate({}) != "":
		return _fail("shihun_skip_dead_section_two_activate")
	_controller.resume_settlement_pipeline()
	if live_target.hp != live_hp_before - 1:
		return _fail("shihun_skip_dead_section_two=%d/%d" % [live_target.hp, live_hp_before])
	if shihun.get_reincarnation_section_index() != 0 or shihun.get_reincarnation_round_count() != 2:
		return _fail("shihun_skip_dead_advance=%s" % shihun.get_reincarnation_state())
	return true


## 构造AI评分使用的权威快照；只保留态度与体力判定所需字段。
func _build_ai_snapshot(owner_hp: int) -> Dictionary:
	return {"players":[
		{"player_id":0, "hp":owner_hp, "max_hp":5, "alive":true, "identity":"leader", "identity_revealed":true, "hand":[], "hand_count":0, "equipment":{}, "character_id":"kaesilanna", "mark_counts":{}, "judgment_area":[], "equipment_area_abolished":false, "judgment_area_abolished":false},
		{"player_id":1, "hp":4, "max_hp":4, "alive":true, "identity":"rebel", "identity_revealed":true, "hand":[], "hand_count":0, "equipment":{}, "character_id":"wandi", "mark_counts":{}, "judgment_area":[], "equipment_area_abolished":false, "judgment_area_abolished":false},
	]}


## 校验【天裁】①的自伤点数达到当前体力时，AI会给该动作否决级惩罚，避免以濒死返生为代价推进轮回。
func _test_lethal_self_harm_ai_veto() -> bool:
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	var tiancai: SkillDefinition = GameDatabase.create_skill("tiancai")
	if tiancai == null:
		return _fail("lethal_self_harm_missing_skill")
	# 无宿主绑定使轮回读取回退到①与轮回数1，本用例只校验1点自伤在两种体力下的评分差异。
	tiancai.bind(null, 0)
	var lethal_score: float = tiancai.score_ai_action(_build_ai_snapshot(1), {}, evaluator)
	var safe_score: float = tiancai.score_ai_action(_build_ai_snapshot(5), {}, evaluator)
	if lethal_score >= safe_score:
		return _fail("lethal_self_harm_ai lethal=%.3f safe=%.3f" % [lethal_score, safe_score])
	return true


## 校验【弑魂】①承受的必中火【杀】数量达到当前体力时，AI会给该动作否决级惩罚。
func _test_lethal_incoming_slash_ai_veto() -> bool:
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	var shihun: SkillDefinition = GameDatabase.create_skill("shihun")
	if shihun == null:
		return _fail("lethal_incoming_slash_missing_skill")
	# 无宿主绑定使轮回读取回退到①；本用例只校验1名使用者是否足以致命。
	shihun.bind(null, 0)
	var lethal_score: float = shihun.score_ai_action(_build_ai_snapshot(1), {"target_ids":[1]}, evaluator)
	var safe_score: float = shihun.score_ai_action(_build_ai_snapshot(5), {"target_ids":[1]}, evaluator)
	if lethal_score >= safe_score:
		return _fail("lethal_incoming_slash_ai lethal=%.3f safe=%.3f" % [lethal_score, safe_score])
	return true


## 输出失败原因并以非零状态退出；返回false便于调用方立即终止后续断言。
func _fail(message: String) -> bool:
	printerr("KAESILANNA_COMBAT_FAIL %s" % message)
	get_tree().quit(1)
	return false
