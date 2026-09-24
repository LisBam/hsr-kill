extends Node

## 轮回技与相关机制专项回归。覆盖状态推进、永劫、复原、两类【杀】次数语义、万敌、赛飞儿、AI和局内外文本高亮。

## 本测试共用的权威对局控制器；所有机制通过正式服务与技能端口执行。
var _controller: MatchController

## 单节轮回测试捕获的生命周期事件名；用于验证开始、节开始、节结束与轮回结束的严格顺序。
var _reincarnation_lifecycle_events: Array[String] = []

## 弑神真实用牌测试捕获的关键时机顺序；用于确认濒死完整插入在【杀】目标与牌效结算之间。
var _shishen_resolution_order: Array[String] = []

## 弑神真实用牌进入shaBefore时读取到的当前目标伤害加值；默认0可识别CardUseEvent回写覆盖回归。
var _shishen_damage_bonus_at_sha_before: int = 0


## 延迟一帧开始回归，确保GameDatabase已完成目录扫描和静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部轮回机制断言；任一失败立即以非零状态结束。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_special_character_pool():
		return
	if not _test_awakening_and_one_section_reincarnation():
		return
	if not _test_xvechou_shishen_and_restore():
		return
	if not _test_play_limit_semantics():
		return
	if not _test_jvkou_huanri_and_ai():
		return
	if not await _test_reincarnation_description_highlight():
		return
	print("REINCARNATION_MECHANICS_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；轮回生命周期与技能触发共用该节点。
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


## 为单项测试创建最小权威状态并重建全部规则服务；角色身份公开以获得确定AI态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "reincarnation-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "轮回测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._pending_damage_finalizations.clear()
	_controller._pending_dying_start_contexts.clear()
	_controller._deferred_skill_settlements.clear()


## 安装指定技能并返回独立运行时实例；测试与正式固有技能安装使用同一bind/install顺序。
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


## 校验两名武将、四项技能原文与翁法罗斯资料，并验证特殊武将不会进入普通抽取池。
func _test_metadata_and_special_character_pool() -> bool:
	# 万敌静态定义；性别、势力、体力与技能顺序必须与设计一致。
	var wandi: Dictionary = GameDatabase.get_character("wandi")
	# 赛飞儿静态定义；性别、势力、体力与技能顺序必须与设计一致。
	var saifeier: Dictionary = GameDatabase.get_character("saifeier")
	if str(wandi.get("display_name", "")) != "万敌" or str(wandi.get("gender", "")) != "male" or str(wandi.get("faction", "")) != "wengfaluosi" or int(wandi.get("max_hp", 0)) != 5 or wandi.get("skills", []) != ["xvechou", "shishen"]:
		return _fail("wandi_metadata=%s" % wandi)
	if str(saifeier.get("display_name", "")) != "赛飞儿" or str(saifeier.get("gender", "")) != "female" or str(saifeier.get("faction", "")) != "wengfaluosi" or int(saifeier.get("max_hp", 0)) != 3 or saifeier.get("skills", []) != ["jvkou", "huanri"]:
		return _fail("saifeier_metadata=%s" % saifeier)
	# 需求指定的四项技能原文；任何字符、标点或X说明变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"xvechou":"轮回技，锁定技，当你进入濒死状态时，①你回复X点体力；②你减少1点体力上限并摸X张牌。（X为本技能的轮回数）",
		"shishen":"锁定技，出牌阶段，你使用的前X张【杀】无距离与次数限制。当你使用【杀】指定目标时，你失去1点体力并令此【杀】伤害+1。",
		"jvkou":"轮回技，一名角色于其回合内首次造成伤害后，其可令你①摸一张牌；②获得一枚“币”标记。你每有一枚“币”标记，你的手牌上限便+1。",
		"huanri":"出牌阶段限一次，你可移除你的所有“币”并对一名其他角色造成等量点伤害。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；静态数据库说明必须与期望逐字一致。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("skill_description=%s" % skill_id)
	# 临时把万敌标记为特殊武将；测试结束前恢复原定义，验证中央抽取过滤而不新增虚构角色数据。
	var original_wandi: Dictionary = (GameDatabase.characters.get("wandi", {}) as Dictionary).duplicate(true)
	var special_wandi: Dictionary = original_wandi.duplicate(true)
	special_wandi["special"] = true
	GameDatabase.characters["wandi"] = special_wandi
	# 普通与显式特殊角色池；前者必须排除，后者必须包含。
	var normal_pool: Array[String] = GameDatabase.get_selectable_character_ids()
	# 显式特殊池；仅特定规则可请求include_special=true。
	var explicit_pool: Array[String] = GameDatabase.get_selectable_character_ids(true)
	GameDatabase.characters["wandi"] = original_wandi
	if normal_pool.has("wandi") or not explicit_pool.has("wandi"):
		return _fail("special_character_pool")
	return true


## 校验觉醒技等价锁定+限定，并验证无显式①②的轮回技每次发动直接增加轮回数。
func _test_awakening_and_one_section_reincarnation() -> bool:
	# 觉醒技测试定义；只提供正文标签，基类必须自动补齐锁定与限定元数据。
	var awakening_skill: SkillDefinition = SkillDefinition.new({"id":"awakening_test", "description":"觉醒技，达到条件后发动。"})
	if not awakening_skill.awakening or not awakening_skill.limited or not awakening_skill.lock or not awakening_skill.has_available_intrinsic_use():
		return _fail("awakening_semantics")
	awakening_skill.consume_intrinsic_use()
	if awakening_skill.has_available_intrinsic_use():
		return _fail("awakening_limited_use")
	awakening_skill.restore_intrinsic_use()
	if not awakening_skill.has_available_intrinsic_use():
		return _fail("awakening_restore")
	_reset_state(2)
	_reincarnation_lifecycle_events.clear()
	for lifecycle_event_name: String in ["reincarnationStart", "reincarnationEnd", "reincarnationSectionStart", "reincarnationSectionEnd"]:
		_controller.event_bus.subscribe(lifecycle_event_name, self, _capture_reincarnation_lifecycle)
	# 单轮回节测试技能；没有带圈序号，仍登记为一个轮回节并从轮回数1开始。
	var one_section_skill: SkillDefinition = SkillDefinition.new({"id":"one_section_test", "reincarnation":true, "description":"轮回技，当你造成伤害时，你摸一张牌。"})
	one_section_skill.bind(_controller, 0)
	if not one_section_skill.begin_reincarnation_activation() or not one_section_skill.complete_reincarnation_activation() or one_section_skill.get_reincarnation_round_count() != 2:
		return _fail("one_section_first_activation=%s" % one_section_skill.get_reincarnation_state())
	# 首次单节发动顺序：初始轮回与①开始，随后①结束、轮回结束，再立刻开始新轮回与①。
	var expected_first_lifecycle: Array[String] = ["reincarnationStart", "reincarnationSectionStart", "reincarnationSectionEnd", "reincarnationEnd", "reincarnationStart", "reincarnationSectionStart"]
	if _reincarnation_lifecycle_events != expected_first_lifecycle:
		return _fail("one_section_lifecycle=%s" % _reincarnation_lifecycle_events)
	if not one_section_skill.begin_reincarnation_activation() or not one_section_skill.complete_reincarnation_activation() or one_section_skill.get_reincarnation_round_count() != 3:
		return _fail("one_section_second_activation=%s" % one_section_skill.get_reincarnation_state())
	# 每轮回节阶段限次测试技能；①与②在同一出牌阶段各可完成一次，回到已用过的①后必须被拒绝。
	var section_limited_skill: SkillDefinition = SkillDefinition.new({"id":"section_limited_test", "reincarnation":true, "reincarnation_section_count":2, "reincarnation_has_explicit_sections":true, "reincarnation_each_section_once_per_play_phase":true, "description":"轮回技，出牌阶段每个轮回节限一次，①你摸一张牌；②你摸一张牌。"})
	section_limited_skill.bind(_controller, 0)
	if not section_limited_skill.begin_reincarnation_activation() or not section_limited_skill.complete_reincarnation_activation() or not section_limited_skill.can_activate_reincarnation():
		return _fail("section_limit_first_section=%s" % section_limited_skill.get_reincarnation_state())
	if not section_limited_skill.begin_reincarnation_activation() or not section_limited_skill.complete_reincarnation_activation() or section_limited_skill.can_activate_reincarnation():
		return _fail("section_limit_same_play_phase=%s" % section_limited_skill.get_reincarnation_state())
	_controller.reincarnation_skill_service.on_play_phase_started(0)
	if not section_limited_skill.can_activate_reincarnation():
		return _fail("section_limit_next_play_phase=%s" % section_limited_skill.get_reincarnation_state())
	return true


## 记录正式轮回生命周期事件名；回调不修改事件，保证测试只观察服务派发顺序。
func _capture_reincarnation_lifecycle(event: RuleEvent) -> void:
	_reincarnation_lifecycle_events.append(event.name)


## 记录弑神真实【杀】的目标、濒死与牌效时机；shaBefore额外读取控制器共享伤害参数。
func _capture_shishen_resolution_timing(event: RuleEvent) -> void:
	_shishen_resolution_order.append(event.name)
	if event.name == "shaBefore":
		# 当前真实【杀】UID；由牌效时机数据提供，用于确认弑神增伤已经保留到内容结算前。
		var card_uid: int = int(event.data.get("card_uid", -1))
		_shishen_damage_bonus_at_sha_before = _controller.get_card_target_damage_bonus(card_uid, event.target_id)


## 校验血仇两节、弑神前X张规则、逐目标失去体力增伤、永劫限次及完整技能复原。
func _test_xvechou_shishen_and_restore() -> bool:
	_reset_state(2)
	# 万敌状态；正式基础上限为5，当前置于濒死范围以直接派发dyingBegin。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "wandi"
	owner.max_hp = 5
	owner.hp = 0
	# 测试摸牌堆；②最多摸当前轮回数1张，额外牌防止牌堆耗尽终局。
	for card_index: int in range(4):
		# 当前测试牌；定义使用【闪】且保持公共摸牌堆归属。
		var draw_card: CardInstance = CardInstance.new("shan", "heart", card_index + 1)
		draw_card.zone = "draw_pile"
		_controller.state.draw_pile.append(draw_card)
	# 血仇与弑神实例；两者通过轮回状态稳定ID解耦协作。
	var xvechou: SkillDefinition = _install_skill(0, "xvechou")
	# 弑神实例；用于次数、距离、目标增伤与AI规则查询。
	var shishen: SkillDefinition = _install_skill(0, "shishen")
	if xvechou == null or shishen == null:
		return _fail("wandi_skill_install")
	_controller.emit_rule_timing("dyingBegin", 0, -1, 0, {"hp":0, "required_recover":1})
	# ①以X=1回复1点，随后进入②但轮回数仍为1。
	var first_state: Dictionary = _controller.get_reincarnation_skill_state(0, "xvechou")
	if owner.hp != 1 or int(first_state.get("round_count", 0)) != 1 or int(first_state.get("section_index", -1)) != 1:
		return _fail("xvechou_section_one=%s/%s" % [owner.hp, first_state])
	owner.hp = 0
	# ②减少1点上限并摸X=1张，随后回到①且轮回数增加到2；不得递归进入第二条濒死流程。
	_controller.emit_rule_timing("dyingBegin", 0, -1, 0, {"hp":0, "required_recover":1})
	var second_state: Dictionary = _controller.get_reincarnation_skill_state(0, "xvechou")
	if owner.max_hp != 4 or owner.hand.size() != 1 or int(second_state.get("round_count", 0)) != 2 or int(second_state.get("section_index", -1)) != 0:
		return _fail("xvechou_section_two=%s/%s/%s" % [owner.max_hp, owner.hand.size(), second_state])
	# X=2时前两张【杀】均解除距离与次数限制，第三张开始恢复基础规则。
	var slash_definition: Dictionary = GameDatabase.get_card("sha")
	owner.play_phase_card_use_history.clear()
	if not shishen.ignores_play_count_limit(slash_definition) or not shishen.ignores_card_distance_limit(slash_definition):
		return _fail("shishen_first_slash")
	owner.play_phase_card_use_history["sha"] = 1
	if not shishen.ignores_play_count_limit(slash_definition):
		return _fail("shishen_second_slash")
	owner.play_phase_card_use_history["sha"] = 2
	if shishen.ignores_play_count_limit(slash_definition) or shishen.ignores_card_distance_limit(slash_definition):
		return _fail("shishen_third_slash")
	# 即使前两张【杀】因其他效果不计入阶段上限，它们仍是实际使用的前两张，第三张不再获得弑神解除。
	owner.play_phase_card_use_limit_exempt_history["sha"] = 2
	if shishen.ignores_play_count_limit(slash_definition) or shishen.ignores_card_distance_limit(slash_definition):
		return _fail("shishen_actual_slash_order")
	# 构造仍在使用生命周期中的【杀】上下文；逐目标时机应失去1点体力并为当前目标增加1点伤害。
	owner.hp = 4
	_controller._card_use_contexts[900] = {"target_ids":[1], "custom_args":{}}
	_controller.emit_rule_timing("useCardToTargeted", 1, 0, 1, {"card_id":"sha", "card_uid":900, "target_id":1, "target_ids":[1]})
	if owner.hp != 3 or _controller.get_card_target_damage_bonus(900, 1) != 1:
		return _fail("shishen_target_effect=%d/%d" % [owner.hp, _controller.get_card_target_damage_bonus(900, 1)])
	_controller._card_use_contexts.erase(900)
	# 永劫锁定当前①并设置每回合限一次；进入前的既有发动不计入额度。
	if not _controller.enter_eternal_reincarnation_state(0, "xvechou", 1) or not xvechou.begin_reincarnation_activation() or not xvechou.complete_reincarnation_activation():
		return _fail("eternal_enter")
	var eternal_state: Dictionary = xvechou.get_reincarnation_state()
	if int(eternal_state.get("section_index", -1)) != 0 or int(eternal_state.get("round_count", 0)) != 3 or xvechou.can_activate_reincarnation() or _controller.enter_eternal_reincarnation_state(0, "xvechou", 1):
		return _fail("eternal_limit=%s" % eternal_state)
	_controller.state.turn_number = 2
	if not xvechou.can_activate_reincarnation():
		return _fail("eternal_next_turn")
	# 复原武将牌技能会重建本地次数并把轮回重置为1、①，同时解除永劫。
	if not _controller.restore_character_card_skills(0, "test_restore"):
		return _fail("restore_character_skills")
	var restored_state: Dictionary = _controller.get_reincarnation_skill_state(0, "xvechou")
	if int(restored_state.get("round_count", 0)) != 1 or int(restored_state.get("section_index", -1)) != 0 or bool(restored_state.get("eternal", true)):
		return _fail("restored_reincarnation=%s" % restored_state)
	# 空对局ID使无人持有救援牌时同步跳过响应界面；弑神失去体力触发的血仇濒死仍完整结算。
	_controller.state.match_id = ""
	owner.hp = 1
	owner.play_phase_card_use_history.clear()
	owner.play_phase_card_use_limit_exempt_history.clear()
	# 弑神真实用牌目标；无【闪】时应承受基础1点与弑神1点，共2点伤害。
	var slash_target: PlayerState = _controller.state.get_player(1)
	# 真实【杀】实体；必须经过submit_action与CardUseEvent，才能覆盖事件参数回写的历史缺陷。
	var real_slash: CardInstance = CardInstance.new("sha", "spade", 7)
	real_slash.zone = "hand"
	real_slash.owner_id = 0
	owner.hand.append(real_slash)
	_shishen_resolution_order.clear()
	_shishen_damage_bonus_at_sha_before = 0
	for timing_name: String in ["useCardToTargeted", "dyingBegin", "shaBefore"]:
		_controller.event_bus.subscribe(timing_name, self, _capture_shishen_resolution_timing)
	# 真实标准用牌动作；弑神须在指定目标时先写入增伤，再失去体力并插入濒死，最后返回本【杀】结算。
	var use_slash_action: PlayerAction = PlayerAction.new("use_card", 0, real_slash.uid, [1])
	if not _controller.submit_action(use_slash_action):
		return _fail("shishen_real_card_rejected")
	# 三个关键时机的稳定索引；严格递增表示濒死确实位于目标指定与shaBefore之间完成。
	var targeted_index: int = _shishen_resolution_order.find("useCardToTargeted")
	# 濒死开始时机索引；血仇①在该时机把0点体力回复至1点。
	var dying_index: int = _shishen_resolution_order.find("dyingBegin")
	# 【杀】牌效开始前索引；此时必须仍读取到当前目标的1点弑神加值。
	var sha_before_index: int = _shishen_resolution_order.find("shaBefore")
	_controller.event_bus.unsubscribe_owner(self)
	if owner.hp != 1 or slash_target.hp != 3 or _shishen_damage_bonus_at_sha_before != 1 or targeted_index < 0 or dying_index <= targeted_index or sha_before_index <= dying_index:
		return _fail("shishen_real_card=%d/%d/%d/%s" % [owner.hp, slash_target.hp, _shishen_damage_bonus_at_sha_before, _shishen_resolution_order])
	return true


## 校验“无次数限制”与“不计入次数限制”的差异：后者不能在使用前已经达到上限时越权。
func _test_play_limit_semantics() -> bool:
	_reset_state(2)
	# 使用者与标准【杀】定义；虚拟使用只测试阶段、次数与目标，不需要实体手牌。
	var actor: PlayerState = _controller.state.get_player(0)
	# 【杀】静态定义；play_limit_scope为phase且所有属性【杀】共享slash组。
	var slash_definition: Dictionary = GameDatabase.get_card("sha")
	# 已经达到基础上限且没有豁免历史时，普通“不计入”语义不能帮助本次使用前校验通过。
	actor.play_phase_card_use_history["sha"] = 1
	actor.play_phase_card_use_limit_exempt_history.clear()
	if _controller.card_rules.validate_virtual_use(0, "sha", [1]).is_empty():
		return _fail("not_counting_cannot_bypass_reached_limit")
	# 同一张既有【杀】若被记录为不计入限制，则计数回到0，下一张【杀】可以正常使用。
	actor.play_phase_card_use_limit_exempt_history["sha"] = 1
	if not _controller.card_rules.validate_virtual_use(0, "sha", [1]).is_empty() or _controller.card_rules.get_grouped_play_count(0, slash_definition) != 0:
		return _fail("not_counting_exempt_history")
	# 不计入限制只改变上限计数，不抹除“实际使用过一张【杀】”的事实序号。
	if _controller.card_rules.get_grouped_actual_play_count(0, slash_definition) != 1:
		return _fail("not_counting_preserves_actual_history")
	# 无次数限制语义仍保留完整实际历史；弑神/王牌只绕过校验，不会写入豁免表。
	actor.play_phase_card_use_history["sha"] = 3
	actor.play_phase_card_use_limit_exempt_history.clear()
	if _controller.card_rules.get_grouped_play_count(0, slash_definition) != 3:
		return _fail("unlimited_still_counts")
	return true


## 校验聚寇两节、币与手牌上限同步、换日伤害以及友方确认和敌方目标AI。
func _test_jvkou_huanri_and_ai() -> bool:
	_reset_state(3)
	# 赛飞儿状态；正式基础上限为3，技能状态与公开标记从空值开始。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "saifeier"
	owner.max_hp = 3
	owner.hp = 3
	# 聚寇摸牌测试牌；保留两张避免后续流程因牌堆耗尽终局。
	for card_index: int in range(2):
		# 当前测试牌；定义使用【闪】并置于公共摸牌堆。
		var draw_card: CardInstance = CardInstance.new("shan", "diamond", card_index + 1)
		draw_card.zone = "draw_pile"
		_controller.state.draw_pile.append(draw_card)
	# 聚寇运行时实例；直接恢复确认可精确测试效果而不依赖选择界面。
	var jvkou: SkillDefinition = _install_skill(0, "jvkou")
	# 换日运行时实例；用于主动伤害与AI目标估值。
	var huanri: SkillDefinition = _install_skill(0, "huanri")
	if jvkou == null or huanri == null:
		return _fail("saifeier_skill_install")
	# 忠臣队友在自己的回合首次造成伤害；确认聚寇①后赛飞儿摸1张并进入②。
	var ally: PlayerState = _controller.state.get_player(2)
	_controller.state.current_player_id = 2
	ally.damage_history = [{"event_id":101, "source_id":2, "target_id":1, "amount":1}]
	var confirm_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 2, true)
	jvkou.continue_selection({"kind":"jvkou_confirm", "damage_source_id":2}, confirm_response)
	if owner.hand.size() != 1 or int(jvkou.get_reincarnation_state().get("section_index", -1)) != 1:
		return _fail("jvkou_draw_section=%s" % jvkou.get_reincarnation_state())
	# 下一次独立回合首次伤害确认②后获得1枚币、手牌上限+1并进入下一轮回①。
	_controller.state.turn_number = 2
	ally.damage_history = [{"event_id":102, "source_id":2, "target_id":1, "amount":1}]
	jvkou.continue_selection({"kind":"jvkou_confirm", "damage_source_id":2}, confirm_response)
	var coin_mark: Dictionary = _controller.get_player_mark(0, "bi")
	if int(coin_mark.get("count", 0)) != 1 or owner.hand_limit_bonus != 1 or int(jvkou.get_reincarnation_state().get("round_count", 0)) != 2 or int(jvkou.get_reincarnation_state().get("section_index", -1)) != 0:
		return _fail("jvkou_coin_section=%s/%s" % [coin_mark, jvkou.get_reincarnation_state()])
	# AI确认评分；队友无条件为正，敌方无条件为负。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 权威完整快照；公开身份使忠反关系无需额外推断。
	var snapshot: Dictionary = _controller.state.to_dict(-1, true)
	# 标准确认动作；零材料选择只通过confirmed字段表达发动。
	var confirm_action: Dictionary = {"payload":{"confirmed":true}}
	var ally_score: float = jvkou.score_ai_choice(snapshot, {"context":{"kind":"jvkou_confirm", "damage_source_id":2}}, confirm_action, evaluator)
	var enemy_score: float = jvkou.score_ai_choice(snapshot, {"context":{"kind":"jvkou_confirm", "damage_source_id":1}}, confirm_action, evaluator)
	if ally_score <= 0.0 or enemy_score >= 0.0:
		return _fail("jvkou_ai=%s/%s" % [ally_score, enemy_score])
	# 换日前比较目标评分；敌方应为正，忠臣队友应为负。
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	var enemy_action: Dictionary = {"target_ids":[1]}
	var ally_action: Dictionary = {"target_ids":[2]}
	if huanri.score_ai_action(snapshot, enemy_action, evaluator) <= huanri.score_ai_action(snapshot, ally_action, evaluator):
		return _fail("huanri_ai_target")
	# 发动换日移除全部1枚币与对应手牌上限，并对反贼造成1点伤害。
	var enemy: PlayerState = _controller.state.get_player(1)
	var enemy_hp_before: int = enemy.hp
	if huanri.activate({"target_ids":[1]}) != "" or enemy.hp != enemy_hp_before - 1 or not _controller.get_player_mark(0, "bi").is_empty() or owner.hand_limit_bonus != 0:
		return _fail("huanri_effect=%d/%s/%d" % [enemy.hp, _controller.get_player_mark(0, "bi"), owner.hand_limit_bonus])
	if huanri.can_activate():
		return _fail("huanri_phase_limit")
	return true


## 校验局内当前轮回节高亮、其他节淡化，以及局外静态资料默认高亮①。
func _test_reincarnation_description_highlight() -> bool:
	# 血仇原始说明；测试同时确认富文本分段拼接后没有改写任何字符。
	var description: String = str(GameDatabase.get_skill("xvechou").get("description", ""))
	# 正式技能说明视图；加入场景树以应用当前主题，再写入局内②状态。
	var description_view: SkillDescriptionView = SkillDescriptionView.new()
	add_child(description_view)
	description_view.configure_description(description, true, 1)
	await get_tree().process_frame
	# 局内②状态分段；①必须淡化、②必须是唯一高亮段。
	var in_match_segments: Array[Dictionary] = description_view.get_rendered_segments()
	if not _has_section_highlight(in_match_segments, 1) or _has_section_highlight(in_match_segments, 0) or description_view.get_plain_description() != description:
		description_view.queue_free()
		return _fail("in_match_highlight=%s" % [in_match_segments])
	# 局外静态资料没有运行时快照，轮回技必须从初始①开始高亮。
	description_view.configure_description(description, true, 0)
	var out_of_match_segments: Array[Dictionary] = description_view.get_rendered_segments()
	description_view.queue_free()
	if not _has_section_highlight(out_of_match_segments, 0) or _has_section_highlight(out_of_match_segments, 1):
		return _fail("out_of_match_highlight=%s" % [out_of_match_segments])
	return true


## 返回指定轮回节是否在分段结果中被标记为当前高亮节。
func _has_section_highlight(segments: Array[Dictionary], section_index: int) -> bool:
	for segment: Dictionary in segments:
		if int(segment.get("section_index", -1)) == section_index and bool(segment.get("current", false)):
			return true
	return false


## 输出失败原因并以非零状态结束；返回false便于调用方立即中止后续断言。
func _fail(message: String) -> bool:
	printerr("REINCARNATION_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
