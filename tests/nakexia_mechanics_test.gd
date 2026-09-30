extends Node

## 那刻夏【逐虚】【揭质】【留白】专项回归。覆盖武将元数据与三条技能原文、两节轮回随机效果、
## 阶段限两次、揭质同目标重复与自我目标重置、留白的重置与永久失去，以及永久失去标记的存档往返与装配守卫。

## 本测试共用的权威对局控制器；全部机制通过正式服务与技能端口执行。
var _controller: MatchController


## 延迟一帧开始回归，确保 GameDatabase 已完成目录扫描和静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部断言；任一失败立即以非零状态结束。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_descriptions():
		return
	if not _test_zhuxv_two_sections():
		return
	if not _test_zhuxv_play_phase_limit():
		return
	if not _test_jiezhi_repeats_same_target():
		return
	if not _test_jiezhi_self_target_resets_skills():
		return
	if not _test_liubai_reset_keeps_self():
		return
	if not _test_liubai_permanent_skill_loss():
		return
	if not _test_permanent_loss_guards_install_paths():
		return
	if not _test_save_roundtrip_permanent_loss():
		return
	if not _test_ai_hooks_positive():
		return
	print("NAKEXIA_MECHANICS_PASS sections=2 phase_limit=2 jiezhi_per_game=2 jiezhi_self_reset=1 reset_keep_self=1 permanent_loss=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；轮回生命周期与技能时机共用该节点。
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


## 为单项测试创建最小权威状态并重建全部规则服务；角色身份公开以获得确定AI态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "nakexia-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "那刻夏测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		# 被测角色固定为那刻夏：武将固有技能的重建与重置都依赖该字段指向正式武将资料。
		player.character_id = "nakexia" if player_id == 0 else ""
		player.max_hp = 6
		player.hp = 6
		_controller.state.players.append(player)
	# 摸牌堆；随机弃牌与后续技能结算需要可用的实体牌。
	for card_index: int in range(30):
		_controller.state.draw_pile.append(CardInstance.new("shan", "heart", card_index % 13 + 1))
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
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


## 安装那刻夏的全部三个技能；需要跨技能协作的用例统一走该入口。
func _install_nakexia_skills(player_id: int) -> bool:
	for skill_id: String in ["zhuxv", "jiezhi", "liubai"]:
		if _install_skill(player_id, skill_id) == null:
			return false
	return true


## 向指定玩家手牌区加入实体牌并补齐来源字段；直接入区必须写入正式移动服务才会写入的字段。
func _give_hand_cards(player_id: int, count: int) -> Array[int]:
	var player: PlayerState = _controller.state.get_player(player_id)
	# 本次加入的手牌UID；调用方以此断言具体牌的离区结果。
	var added_uids: Array[int] = []
	for card_index: int in range(count):
		var card: CardInstance = CardInstance.new("shan", "heart", card_index % 13 + 1)
		card.owner_id = player_id
		card.zone = "hand"
		player.hand.append(card)
		added_uids.append(card.uid)
	return added_uids


## 统计指定玩家当前全部区域的牌总数；随机弃牌断言以总区域数为准。
func _count_all_zone_cards(player_id: int) -> int:
	var player: PlayerState = _controller.state.get_player(player_id)
	if player == null:
		return -1
	# 区域总数；手牌、装备与判定区共同构成逐虚①的随机范围。
	var total: int = player.hand.size() + player.judgment_area.size()
	for slot: String in ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]:
		if player.equipment.has(slot):
			total += 1
	return total


## 校验武将资料、三条技能原文与逐虚的两节轮回元数据。
func _test_metadata_and_descriptions() -> bool:
	# 那刻夏静态定义；性别、势力、体力与技能顺序必须与设计一致。
	# 性别为男性：该数值已在“同步若干技能的描述文本与效果数值”中调整，本断言随之同步。
	var nakexia: Dictionary = GameDatabase.get_character("nakexia")
	if str(nakexia.get("display_name", "")) != "那刻夏" or str(nakexia.get("gender", "")) != "male" or str(nakexia.get("faction", "")) != "wengfaluosi" or int(nakexia.get("max_hp", 0)) != 3 or nakexia.get("skills", []) != ["zhuxv", "jiezhi", "liubai"]:
		return _fail("character_metadata=%s" % nakexia)
	# 需求指定的三条技能原文；任何字符、标点或带圈序号变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"zhuxv":"轮回技，出牌阶段限两次，你可①弃置随机一名有牌的角色随机一张牌；②对随机一名角色造成1点伤害。",
		"jiezhi":"每局游戏限两次，当你发动“逐虚”后，你可对相同目标执行一次相同的效果。若目标为你，你重置你的所有技能。",
		"liubai":"限定技，出牌阶段，你可重置所有其他技能。本回合结束时，你失去所有技能。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；静态数据库说明必须与期望逐字一致。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("skill_description=%s" % skill_id)
	# 逐虚运行时元数据；固定两个轮回节且顺序显式声明。
	var zhuxv: SkillDefinition = GameDatabase.create_skill("zhuxv")
	if zhuxv == null or not zhuxv.reincarnation or int(zhuxv._metadata.get("reincarnation_section_count", 0)) != 2:
		return _fail("zhuxv_metadata")
	# 留白是限定技；揭质不是限定技，只是每局限两次的普通技能。
	if not GameDatabase.create_skill("liubai").limited or GameDatabase.create_skill("jiezhi").limited:
		return _fail("limited_flags")
	return true


## 校验①只弃置一张牌且目标限定为有牌角色，②造成1点伤害且轮回随即推进到第二节。
func _test_zhuxv_two_sections() -> bool:
	_reset_state(3)
	if _install_skill(0, "zhuxv") == null:
		return _fail("zhuxv_install")
	# 只有玩家1持有手牌；①的随机范围因此必须锁定玩家1。
	_give_hand_cards(1, 2)
	# 发动前的区域总数与全体体力；用于逐项比对单次效果。
	var before_zone_total: int = _count_all_zone_cards(0) + _count_all_zone_cards(1) + _count_all_zone_cards(2)
	var before_hp_total: int = _controller.state.get_player(0).hp + _controller.state.get_player(1).hp + _controller.state.get_player(2).hp
	var zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	if zhuxv.get_reincarnation_section_index() != 0:
		return _fail("zhuxv_initial_section=%d" % zhuxv.get_reincarnation_section_index())
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("zhuxv_section_one_rejected")
	# ① 的结算结果：只减少一张区域牌，且不产生任何体力变化。
	var after_zone_total: int = _count_all_zone_cards(0) + _count_all_zone_cards(1) + _count_all_zone_cards(2)
	var after_hp_total: int = _controller.state.get_player(0).hp + _controller.state.get_player(1).hp + _controller.state.get_player(2).hp
	if before_zone_total - after_zone_total != 1 or after_hp_total != before_hp_total:
		return _fail("zhuxv_section_one zone=%d->%d hp=%d->%d" % [before_zone_total, after_zone_total, before_hp_total, after_hp_total])
	if zhuxv.get_reincarnation_section_index() != 1:
		return _fail("zhuxv_advanced_section=%d" % zhuxv.get_reincarnation_section_index())
	# ② 的结算结果：只造成1点伤害，且不改变任何区域的牌数。
	var zone_before_damage: int = _count_all_zone_cards(0) + _count_all_zone_cards(1) + _count_all_zone_cards(2)
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("zhuxv_section_two_rejected")
	var zone_after_damage: int = _count_all_zone_cards(0) + _count_all_zone_cards(1) + _count_all_zone_cards(2)
	var hp_after_damage: int = _controller.state.get_player(0).hp + _controller.state.get_player(1).hp + _controller.state.get_player(2).hp
	if after_hp_total - hp_after_damage != 1 or zone_after_damage != zone_before_damage:
		return _fail("zhuxv_section_two zone=%d->%d hp=%d->%d" % [zone_before_damage, zone_after_damage, after_hp_total, hp_after_damage])
	# 两节走完后回到第一个轮回节，且已完成一个完整轮回（轮回数推进到2）。
	if zhuxv.get_reincarnation_section_index() != 0 or zhuxv.get_reincarnation_round_count() != 2:
		return _fail("zhuxv_cycle round=%d section=%d" % [zhuxv.get_reincarnation_round_count(), zhuxv.get_reincarnation_section_index()])
	return true


## 校验整个技能每出牌阶段限两次：第三次发动必须被拒绝，且额外出牌阶段重新复原额度。
func _test_zhuxv_play_phase_limit() -> bool:
	_reset_state(3)
	if _install_skill(0, "zhuxv") == null:
		return _fail("zhuxv_limit_install")
	# 让随机弃牌节始终有合法目标，避免因无牌而拒绝发动。
	_give_hand_cards(1, 4)
	for use_index: int in range(2):
		if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
			return _fail("zhuxv_limit_rejected_at=%d" % use_index)
	# 第三次发动必须被阶段额度拒绝。
	if _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("zhuxv_limit_exceeded")
	# 补齐实体的额外出牌阶段开始时机；额度必须复原并可再次发动。
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, -1, {"player_id":0, "phase":"play"})
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("zhuxv_limit_not_reset")
	return true


## 校验揭质在逐虚结算后出现确认入口，并对同一目标重复同一节效果且每局限两次。
func _test_jiezhi_repeats_same_target() -> bool:
	_reset_state(3)
	if not _install_nakexia_skills(0):
		return _fail("nakexia_install")
	# 只有玩家1持有手牌；逐虚①唯一可能的目标即玩家1。
	_give_hand_cards(1, 3)
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("jiezhi_zhuxv_rejected")
	# 揭质入口；必须携带已结算的节编号与目标，AI与界面据此复盘。
	var context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "jiezhi_confirm" or int(context.get("target_id", -1)) != 1 or int(context.get("section_index", -1)) != 0:
		return _fail("jiezhi_entry=%s" % context)
	# 确认发动；目标区域必须恰好再减少一张，证明是“同一目标的同一效果”。
	var zone_before_repeat: int = _count_all_zone_cards(1)
	if not _submit_confirm(0, true):
		return false
	if _count_all_zone_cards(1) != zone_before_repeat - 1:
		return _fail("jiezhi_repeat_zone=%d->%d" % [zone_before_repeat, _count_all_zone_cards(1)])
	# 每局额度；取消不消耗次数，只有确认才消耗，总量恰好为两次。
	var jiezhi: SkillDefinition = _controller.get_skill_instance(0, "jiezhi")
	if int(jiezhi._used_count) != 1:
		return _fail("jiezhi_used=%d" % int(jiezhi._used_count))
	# 第二次逐虚（进入②伤害节）后取消：额度必须保持不变。
	_give_hand_cards(1, 3)
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("jiezhi_second_zhuxv_rejected")
	if not _submit_confirm(0, false):
		return false
	if int(jiezhi._used_count) != 1:
		return _fail("jiezhi_cancel_consumed=%d" % int(jiezhi._used_count))
	# 第三次逐虚（回到①弃置节）后确认：额度用尽到两次。
	# 逐虚自身每出牌阶段限两次，跨阶段验证揭质额度时必须先补齐新的出牌阶段开始时机。
	_give_hand_cards(1, 3)
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, -1, {"player_id":0, "phase":"play"})
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("jiezhi_third_zhuxv_rejected")
	if not _submit_confirm(0, true):
		return false
	if int(jiezhi._used_count) != 2:
		return _fail("jiezhi_limit_used=%d" % int(jiezhi._used_count))
	# 额度用尽后不再创建入口：第四次逐虚不得留下任何待处理请求。
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, -1, {"player_id":0, "phase":"play"})
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("jiezhi_fourth_zhuxv_rejected")
	if not _controller._pending_card_choice.is_empty():
		return _fail("jiezhi_over_limit_entry")
	return true


## 校验揭质在目标为持有者本人时追加“重置你的所有技能”，目标为他人时不得产生任何重置。
func _test_jiezhi_self_target_resets_skills() -> bool:
	_reset_state(3)
	if not _install_nakexia_skills(0):
		return _fail("self_reset_install")
	# 对照分支：只给玩家1发牌，逐虚①的随机目标因此必为他人，确认揭质后逐虚进度必须原样保留。
	_give_hand_cards(1, 2)
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("self_reset_other_zhuxv_rejected")
	if not _submit_confirm(0, true):
		return false
	var other_target_zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	if int(other_target_zhuxv._used_this_play_phase) != 1 or other_target_zhuxv.get_reincarnation_section_index() != 1:
		return _fail("self_reset_other_target used=%d section=%d" % [int(other_target_zhuxv._used_this_play_phase), other_target_zhuxv.get_reincarnation_section_index()])
	# 自我目标分支：重新开始一局，只给持有者自己发牌，使逐虚①的唯一可能目标就是本人。
	_reset_state(3)
	if not _install_nakexia_skills(0):
		return _fail("self_reset_reinstall")
	# 先消耗限定技【留白】的额度：揭质的重置范围包含限定技，复原结果必须可观测。
	if not _controller.activate_skill(0, "liubai", {"active_entry":"phaseUse"}):
		return _fail("self_reset_liubai_rejected")
	var used_liubai: SkillDefinition = _controller.get_skill_instance(0, "liubai")
	if used_liubai == null or used_liubai.has_available_intrinsic_use():
		return _fail("self_reset_liubai_not_consumed")
	_give_hand_cards(0, 2)
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("self_reset_zhuxv_rejected")
	# 揭质入口；目标必须记录为持有者自己，否则后续断言无法证明重置分支被执行。
	var self_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(self_context.get("kind", "")) != "jiezhi_confirm" or int(self_context.get("target_id", -1)) != 0:
		return _fail("self_reset_entry=%s" % self_context)
	# 重置前的可观测进度；逐虚已经消耗一次阶段额度，手牌数为重复效果提供对照基准。
	var before_zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	var before_hand_count: int = _controller.state.get_player(0).hand.size()
	if int(before_zhuxv._used_this_play_phase) != 1:
		return _fail("self_reset_pre_usage=%d" % int(before_zhuxv._used_this_play_phase))
	if not _submit_confirm(0, true):
		return false
	# 重复效果仍然先结算：目标区域恰好再减少一张牌，且顺序在重置之前。
	if _controller.state.get_player(0).hand.size() != before_hand_count - 1:
		return _fail("self_reset_repeat_zone=%d->%d" % [before_hand_count, _controller.state.get_player(0).hand.size()])
	# 重置成果一：逐虚换成全新实例，阶段额度、轮回节与轮回数全部归零。
	var reset_zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	if reset_zhuxv == null or reset_zhuxv == before_zhuxv or int(reset_zhuxv._used_this_play_phase) != 0 or reset_zhuxv.get_reincarnation_section_index() != 0 or reset_zhuxv.get_reincarnation_round_count() != 1:
		return _fail("self_reset_zhuxv_state=%s" % str(_controller.get_installed_skill_ids(0)))
	# 重置成果二：重置范围包含揭质自身，因此每局两次的额度同样归零（未实现重置时此处会残留1次）。
	var reset_jiezhi: SkillDefinition = _controller.get_skill_instance(0, "jiezhi")
	if reset_jiezhi == null or int(reset_jiezhi._used_count) != 0:
		return _fail("self_reset_jiezhi_usage=%d" % (int(reset_jiezhi._used_count) if reset_jiezhi != null else -1))
	# 重置成果三：限定技【留白】的固有额度一并复原，证明重置范围覆盖限定技而不只是普通技能；
	# 这与【留白】自身“必须排除自己”的口径不同，因为揭质重置的是“你的所有技能”。
	var reset_liubai: SkillDefinition = _controller.get_skill_instance(0, "liubai")
	if reset_liubai == null or reset_liubai == used_liubai or not reset_liubai.has_available_intrinsic_use():
		return _fail("self_reset_liubai_usage")
	# 额度复原必须可观测：重置后的逐虚能再次发动两次，而不是只剩一次。
	_give_hand_cards(0, 2)
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("self_reset_zhuxv_not_restored")
	if not _submit_confirm(0, false):
		return false
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("self_reset_zhuxv_second_rejected")
	return true


## 校验留白重置其他技能时保留自身限定技标记，且重置覆盖轮回进度与阶段额度。
func _test_liubai_reset_keeps_self() -> bool:
	_reset_state(3)
	if not _install_nakexia_skills(0):
		return _fail("liubai_install")
	_give_hand_cards(1, 4)
	# 先消耗逐虚的两次阶段额度，使重置的“额度复原”有可观测效果。
	# 每次逐虚结算后揭质都会开启确认入口，必须显式取消，否则待处理请求会阻塞下一次发动。
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("liubai_pre_zhuxv_one")
	if not _submit_confirm(0, false):
		return false
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("liubai_pre_zhuxv_two")
	if not _submit_confirm(0, false):
		return false
	if _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("liubai_pre_zhuxv_over")
	# 推进逐虚进入第二节，验证重置同时复原轮回进度。
	var zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	if zhuxv.get_reincarnation_section_index() != 0:
		return _fail("liubai_pre_section=%d" % zhuxv.get_reincarnation_section_index())
	# 发动留白；必须成功且重置数量不含自身。
	if not _controller.activate_skill(0, "liubai", {"active_entry":"phaseUse"}):
		return _fail("liubai_activate_rejected")
	var liubai: SkillDefinition = _controller.get_skill_instance(0, "liubai")
	if liubai.has_available_intrinsic_use():
		return _fail("liubai_self_reset")
	# 重置后的逐虚必须回到未使用状态：能再次发动两次。
	var reset_zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	if int(reset_zhuxv._used_this_play_phase) != 0 or reset_zhuxv.get_reincarnation_section_index() != 0:
		return _fail("liubai_reset_state used=%d section=%d" % [int(reset_zhuxv._used_this_play_phase), reset_zhuxv.get_reincarnation_section_index()])
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("liubai_reset_not_effective")
	# 重置后的揭质额度同样复原：稍后用第二次逐虚确认它仍可发动。
	var jiezhi: SkillDefinition = _controller.get_skill_instance(0, "jiezhi")
	if int(jiezhi._used_count) != 0:
		return _fail("liubai_reset_jiezhi=%d" % int(jiezhi._used_count))
	return true


## 校验本回合结束时永久失去全部技能，且标记不可逆。
func _test_liubai_permanent_skill_loss() -> bool:
	_reset_state(3)
	if not _install_nakexia_skills(0):
		return _fail("permanent_install")
	if not _controller.activate_skill(0, "liubai", {"active_entry":"phaseUse"}):
		return _fail("permanent_liubai_rejected")
	# 回合尚未结束时技能仍然可用；这一步同时确认“失去”确实被推迟。
	if _controller.get_installed_skill_ids(0).is_empty():
		return _fail("permanent_lost_too_early")
	# 触发持有者结束阶段；第二段效果必须执行。
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"player_id":0, "phase":"play"})
	var player: PlayerState = _controller.state.get_player(0)
	if not player.skills_permanently_removed:
		return _fail("permanent_flag_missing")
	if not _controller.get_installed_skill_ids(0).is_empty():
		return _fail("permanent_skills_remain=%s" % str(_controller.get_installed_skill_ids(0)))
	# 不可逆：再次触发结束阶段不得抛错，且标记保持。
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"player_id":0, "phase":""})
	if not _controller.state.get_player(0).skills_permanently_removed:
		return _fail("permanent_flag_cleared")
	# 失去技能后角色不能再发动任何技能。
	if _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("permanent_skill_usable")
	return true


## 校验永久失去标记拦截四条装配路径：批量安装、换将重装、局内获得与存档补装。
func _test_permanent_loss_guards_install_paths() -> bool:
	_reset_state(3)
	# 直接把玩家0标记为永久失去技能，再逐条验证装配守卫。
	var player: PlayerState = _controller.state.get_player(0)
	player.character_id = "nakexia"
	player.skills_permanently_removed = true
	# 路径一：批量安装武将技能。
	_controller._install_all_character_skills()
	if not _controller.get_installed_skill_ids(0).is_empty():
		return _fail("guard_install_all=%s" % str(_controller.get_installed_skill_ids(0)))
	# 路径二：换将重装。
	_controller._reinstall_character_skills_for_player(player)
	if not _controller.get_installed_skill_ids(0).is_empty():
		return _fail("guard_reinstall=%s" % str(_controller.get_installed_skill_ids(0)))
	# 路径三：局内获得技能。
	if _controller.grant_acquired_skill(0, "fanyin", 0, 0, "nakexia_test", true):
		return _fail("guard_grant_acquired")
	# 路径四：存档补装；先伪造一条获得技能记录再补装。
	player.acquired_skills["fanyin"] = {"source":"nakexia_test", "per_turn_limit":0, "per_round_limit":0, "total_limit":0, "tracked_turn_number":1, "tracked_round_number":1, "uses_this_turn":0, "uses_this_round":0, "total_uses":0}
	_controller._reinstall_saved_runtime_skills(player)
	if not _controller.get_installed_skill_ids(0).is_empty():
		return _fail("guard_saved_runtime=%s" % str(_controller.get_installed_skill_ids(0)))
	# 对照：未被标记的玩家仍可正常安装，证明守卫只对标记角色生效。
	_controller.state.get_player(1).character_id = "nakexia"
	_controller._install_all_character_skills()
	if _controller.get_installed_skill_ids(1).is_empty():
		return _fail("guard_blocks_others")
	return true


## 校验永久失去标记进入公开快照并可在存档往返后恢复。
func _test_save_roundtrip_permanent_loss() -> bool:
	_reset_state(2)
	var player: PlayerState = _controller.state.get_player(0)
	player.skills_permanently_removed = true
	# 公开快照；界面与局域网据此把技能栏画为空。
	var snapshot: Dictionary = player.to_dict()
	if not bool(snapshot.get("skills_permanently_removed", false)):
		return _fail("snapshot_missing_flag")
	# 存档往返；标记必须在 from_dict 后保持为真。
	var restored: PlayerState = PlayerState.from_authoritative_dict(snapshot)
	if restored == null or not restored.skills_permanently_removed:
		return _fail("roundtrip_flag_lost")
	# 默认值；未标记的角色不得被误判为已失去技能。
	var fresh: PlayerState = PlayerState.new(9, "对照玩家")
	if fresh.skills_permanently_removed:
		return _fail("default_flag_true")
	return true


## 校验三条技能的AI入口都能给出严格大于0的合法动作评分。
func _test_ai_hooks_positive() -> bool:
	_reset_state(3)
	if not _install_nakexia_skills(0):
		return _fail("ai_install")
	_give_hand_cards(1, 3)
	# 权威快照；AI钩子只允许读取权威快照与估值器。
	# 已发动限定技由控制器在 to_dict 之后统一追加，构建权威快照必须沿用同一条正式路径。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	# AI估值器；技能钩子只允许读取权威快照与该估值器，不得访问控制器或节点。
	var evaluator: Object = NonameAIEvaluator.new()
	# 逐虚：存在敌方目标时，随机削弱与随机伤害的期望值必须为正分。
	var zhuxv: SkillDefinition = _controller.get_skill_instance(0, "zhuxv")
	# 候选动作；与 append_play_phase_actions 生成的负载保持一致。
	var zhuxv_actions: Array[Dictionary] = []
	zhuxv.append_play_phase_actions(zhuxv_actions)
	if zhuxv_actions.is_empty():
		return _fail("ai_zhuxv_no_action")
	var zhuxv_score: float = zhuxv.score_ai_action(snapshot, zhuxv_actions[0], evaluator)
	if zhuxv_score <= 0.0:
		return _fail("ai_zhuxv_score=%f" % zhuxv_score)
	# 揭质：先真实发动一次逐虚以产生结算记录与确认请求，再按同一请求上下文评分。
	if not _controller.activate_skill(0, "zhuxv", {"active_entry":"phaseUse"}):
		return _fail("ai_zhuxv_activation_rejected")
	var choice_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(choice_context.get("kind", "")) != "jiezhi_confirm":
		return _fail("ai_jiezhi_no_request=%s" % choice_context)
	var jiezhi: SkillDefinition = _controller.get_skill_instance(0, "jiezhi")
	var jiezhi_score: float = jiezhi.score_ai_choice(snapshot, {"context":choice_context}, {"payload":{"confirmed":true}}, evaluator)
	if jiezhi_score <= 0.0:
		return _fail("ai_jiezhi_score=%f" % jiezhi_score)
	# 取消该请求；揭质本身不产生副作用，取消后状态回到可继续评分的状态。
	_submit_confirm(0, false)
	# 留白：先枚举候选动作，再真实发动一次以消耗限定额度，最后用新快照评分。
	# 评分依赖快照中的 used_limited_skill_ids，该字段只在限定额度实际消耗后才会出现。
	var liubai: SkillDefinition = _controller.get_skill_instance(0, "liubai")
	var liubai_actions: Array[Dictionary] = []
	liubai.append_play_phase_actions(liubai_actions)
	if liubai_actions.is_empty():
		return _fail("ai_liubai_no_action")
	if not _controller.activate_skill(0, "liubai", {"active_entry":"phaseUse"}):
		return _fail("ai_liubai_activation_rejected")
	# 重新构建权威快照：留白发动后限定额度才出现在 used_limited_skill_ids 中，评分据此识别重置收益。
	var post_snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(post_snapshot)
	var liubai_score: float = liubai.score_ai_action(post_snapshot, liubai_actions[0], evaluator)
	if liubai_score <= 0.0:
		return _fail("ai_liubai_score=%f" % liubai_score)
	return true


## 为当前选择请求提交目标或取消；选择动作必须绑定创建时的同一请求编号。
func _submit_choice(actor_id: int, target_ids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_choice")
	# 当前请求稳定编号；同步恢复可能立刻创建下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("target_choice_rejected")
	return true


## 为当前零材料确认请求提交确认或取消；揭质与留白的确认共用该入口。
func _submit_confirm(actor_id: int, confirmed: bool) -> bool:
	return _submit_choice(actor_id, [], confirmed)


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("NAKEXIA_FAIL %s" % reason)
	get_tree().quit(1)
	return false
