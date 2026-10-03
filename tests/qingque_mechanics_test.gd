extends Node

## 青雀三技能专项回归。覆盖【独弈】用牌禁令与弃牌阶段随机保留、【弃和】伤害牌抵消、
## 【自摸】虚拟手牌视为使用与出牌阶段限次改写，以及伤害牌字段与两个锁定技的AI来牌估值。
##
## 全部断言都通过正式公开端口执行：用牌校验走 CardRuleService.validate_use，
## 时机触发走 MatchController._emit_rule_timing 或真实阶段入口，选择提交走标准 choose_cards 动作。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保GameDatabase已完成武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立场景顺序执行青雀专项回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_qingque_metadata():
		return
	if not _test_damage_card_field():
		return
	if not _test_duyi_card_action_permission():
		return
	if not _test_duyi_discard_phase_keep_and_skip():
		return
	if not _test_qihe_negates_same_suit_damage_card():
		return
	if not _test_qihe_requires_same_suit():
		return
	if not _test_zimo_draw_branch_virtual_use():
		return
	if not _test_zimo_suit_branch_extends_limit():
		return
	if not _test_zimo_ai_and_locked_skill_uncertainty():
		return
	if not _test_zimo_ordered_pair_candidate_pool():
		return
	print("QINGQUE_MECHANICS_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能时机、伤害与护盾共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；本测试直接使用评估器，仍保留正式节点供身份观察使用。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；动作提交与正式单机模式保持相同来源语义。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0


## 为当前场景创建最小权威状态；一号领袖、二号反贼、三号及以后忠臣使AI态度确定。
func _reset_state(player_count: int) -> void:
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "qingque-mechanics"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；身份全部公开，避免专项AI断言受身份推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "青雀测试玩家%d" % (player_id + 1))
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
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._rule_sequences.clear()
	_controller._hand_view_as_turn_expiries.clear()
	_controller._started_phase_lifecycles.clear()
	_controller.state.random_history.clear()


## 校验青雀武将元数据与三项技能的锁定技标签、技能正文原文。
func _test_qingque_metadata() -> bool:
	var character: Dictionary = GameDatabase.get_character("qingque")
	if character.is_empty():
		return _fail("qingque_missing")
	if str(character.get("display_name", "")) != "青雀" or str(character.get("gender", "")) != "female" or str(character.get("faction", "")) != "xianzhou" or int(character.get("max_hp", 0)) != 3:
		return _fail("qingque_metadata=%s" % str(character))
	# 技能引用顺序；同时决定技能栏展示顺序，必须与设计顺序一致。
	var skills: Array = character.get("skills", []) as Array
	if skills != ["duyi", "qihe", "zimo"]:
		return _fail("qingque_skills=%s" % str(skills))
	# 两个锁定技必须显式声明lock；主动技必须开放界面入口。
	var duyi: Dictionary = GameDatabase.get_skill("duyi")
	var qihe: Dictionary = GameDatabase.get_skill("qihe")
	var zimo: Dictionary = GameDatabase.get_skill("zimo")
	if not bool(duyi.get("lock", false)) or not bool(qihe.get("lock", false)) or bool(zimo.get("lock", true)):
		return _fail("qingque_lock_flags=%s/%s/%s" % [duyi.get("lock"), qihe.get("lock"), zimo.get("lock")])
	if bool(duyi.get("ui_enabled", true)) or bool(qihe.get("ui_enabled", true)) or not bool(zimo.get("ui_enabled", false)):
		return _fail("qingque_ui_flags=%s/%s/%s" % [duyi.get("ui_enabled"), qihe.get("ui_enabled"), zimo.get("ui_enabled")])
	# 技能正文逐字校验；锁定技标签必须覆盖完整正文，禁止任何形式的改写。
	var expected_duyi: String = "锁定技，你不可使用或打出手牌中的基本牌和锦囊牌。弃牌阶段开始时，你随机保留每种花色的手牌各一张并弃置其余的牌，然后跳过该阶段。"
	var expected_qihe: String = "锁定技，当你成为其他角色使用伤害牌的目标时，若你手牌中有与此牌花色相同的牌，你随机弃置其中一张并令此牌对你无效。"
	var expected_zimo: String = "出牌阶段，若你手牌中的牌花色数少于4，你可以摸一张牌，然后你视为使用一张【杀】或任意未以此法使用过的普通锦囊牌。若你手牌中的牌花色数不少于4，你可以弃置其中一种花色的所有手牌，并令此技能改为“出牌阶段限两次”直到回合结束。"
	if str(duyi.get("description", "")) != expected_duyi or str(qihe.get("description", "")) != expected_qihe or str(zimo.get("description", "")) != expected_zimo:
		return _fail("qingque_descriptions")
	# 主动技入口配置；enable=phaseUse 保证只在出牌阶段点亮。
	if str(zimo.get("enable", "")) != "phaseUse":
		return _fail("zimo_enable=%s" % str(zimo.get("enable")))
	return true


## 校验“是否为伤害牌”字段：恰好标记设计指定的9张牌，并与既有 ai.damage 集合互为交叉验证。
func _test_damage_card_field() -> bool:
	# 设计指定的伤害牌集合；延时锦囊【闪电】同样标记为伤害牌。
	var expected_ids: Array[String] = ["sha", "sha_fire", "sha_thunder", "juedou", "nanman", "wanjian", "huogong", "shuiyanqijun", "shandian"]
	expected_ids.sort()
	# 实际标记集合与评测层伤害集合；两者必须完全一致，避免规则与AI对“伤害牌”的理解出现分歧。
	var marked_ids: Array[String] = []
	var ai_damage_ids: Array[String] = []
	for card_id_variant: Variant in GameDatabase.cards.keys():
		# 当前卡牌定义；只读取静态字段，不构造运行时实体。
		var card_id: String = str(card_id_variant)
		var definition: Dictionary = GameDatabase.get_card(card_id)
		if bool(definition.get("is_damage", false)):
			marked_ids.append(card_id)
		if bool((definition.get("ai", {}) as Dictionary).get("damage", false)):
			ai_damage_ids.append(card_id)
	marked_ids.sort()
	ai_damage_ids.sort()
	if marked_ids != expected_ids:
		return _fail("damage_field=%s" % str(marked_ids))
	if ai_damage_ids != expected_ids:
		return _fail("ai_damage_field=%s" % str(ai_damage_ids))
	# 卡牌定义对象的公开查询入口必须与元数据字段一致；装备与【桃】等非伤害牌保持false。
	var slash_definition: CardDefinition = GameDatabase.get_card_definition("sha")
	var peach_definition: CardDefinition = GameDatabase.get_card_definition("tao")
	var armor_definition: CardDefinition = GameDatabase.get_card_definition("bagua")
	if slash_definition == null or not slash_definition.is_damage_card() or peach_definition == null or peach_definition.is_damage_card() or armor_definition == null or armor_definition.is_damage_card():
		return _fail("damage_card_query")
	return true


## 校验【独弈】只禁止手牌区的基本牌与锦囊牌：使用与打出都受限，装备牌与木牛流马“粮”不受影响。
func _test_duyi_card_action_permission() -> bool:
	_reset_state(2)
	if _install_skill(0, "duyi") == null:
		return _fail("duyi_install")
	# 手牌【杀】：使用被拒绝，拒绝原因必须来自【独弈】。
	var slash: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	var slash_error: String = _controller.card_rules.validate_use(0, slash, [1])
	if not slash_error.contains("独弈"):
		return _fail("duyi_use_error=%s" % slash_error)
	# 打出路径直接查询技能钩子；响应窗口与直接使用共用同一个纯查询入口。
	var duyi: SkillDefinition = _controller.get_skill_instance(0, "duyi")
	var play_error: String = duyi.validate_card_action_permission(slash, GameDatabase.get_card("sha"), CardDefinition.CARD_ACTION_PLAY)
	if not play_error.contains("独弈"):
		return _fail("duyi_play_error=%s" % play_error)
	# 锦囊牌同样被禁止。
	var trick: CardInstance = _add_hand_card(0, "wuzhong", "heart", 8)
	if not _controller.card_rules.validate_use(0, trick, []).contains("独弈"):
		return _fail("duyi_trick_allowed")
	# 装备牌不在原文限制范围内；这里只要求拒绝原因与【独弈】无关。
	var armor: CardInstance = _add_hand_card(0, "bagua", "club", 2)
	if _controller.card_rules.validate_use(0, armor, []).contains("独弈"):
		return _fail("duyi_equipment_blocked")
	# 木牛流马“粮”属于非手牌牌源，不在“手牌中的”范围内。
	var stored: CardInstance = CardInstance.new("sha", "heart", 5)
	stored.zone = "wooden_ox"
	stored.owner_id = 0
	_controller.state.get_player(0).wooden_ox_storage.append(stored)
	if _controller.card_rules.validate_use(0, stored, [1]).contains("独弈"):
		return _fail("duyi_wooden_ox_blocked")
	# 目标列表同样是禁令的一部分：不可使用的牌必须一张目标都不提供，
	# 否则界面会先高亮可点击的目标，玩家选完才发现无法确认，表现成“不可使用却仍能指定目标”。
	var tied_card: CardInstance = _add_hand_card(0, "tiesuo", "club", 9)
	if not _controller.card_rules.list_legal_targets(0, tied_card).is_empty():
		return _fail("duyi_targets_not_blocked=%s" % str(_controller.card_rules.list_legal_targets(0, tied_card)))
	# 对照：同一张【铁索连环】在不被禁令限制时必须有合法目标，证明上面的空数组来自禁令而不是牌本身无目标。
	var unrestrained_card: CardInstance = _add_hand_card(1, "tiesuo", "club", 10)
	if _controller.card_rules.list_legal_targets(1, unrestrained_card).is_empty():
		return _fail("duyi_targets_control_empty")
	return true


## 校验【独弈】弃牌阶段：每种花色随机保留一张、弃置其余，并通过统一跳过入口跳过该阶段。
func _test_duyi_discard_phase_keep_and_skip() -> bool:
	_reset_state(2)
	# 体力值设为3：普通弃牌阶段会把手牌调整到3张，而【独弈】应保留四种花色共4张，两者可明确区分。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.max_hp = 3
	owner.hp = 3
	if _install_skill(0, "duyi") == null:
		return _fail("duyi_discard_install")
	# 六张手牌覆盖四种花色，其中红桃与方块各两张。
	_add_hand_card(0, "sha", "spade", 1)
	_add_hand_card(0, "shan", "heart", 2)
	_add_hand_card(0, "tao", "heart", 3)
	_add_hand_card(0, "jiu", "club", 4)
	_add_hand_card(0, "wuxie", "diamond", 5)
	_add_hand_card(0, "juedou", "diamond", 6)
	# 走真实弃牌阶段入口：Begin窗口派发phaseDiscardBegin，主体回调负责普通弃牌。
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller._enter_discard_phase(0, true)
	if owner.hand.size() != 4:
		return _fail("duyi_hand_size=%d" % owner.hand.size())
	# 每种花色恰好保留一张；顺序与具体选中牌由权威随机流决定。
	var kept_suits: Dictionary = {}
	for card: CardInstance in owner.hand:
		kept_suits[card.suit] = int(kept_suits.get(card.suit, 0)) + 1
	if kept_suits.size() != 4 or int(kept_suits.get("spade", 0)) != 1 or int(kept_suits.get("heart", 0)) != 1 or int(kept_suits.get("club", 0)) != 1 or int(kept_suits.get("diamond", 0)) != 1:
		return _fail("duyi_kept_suits=%s" % str(kept_suits))
	# 随机历史必须为每种花色各留下一条记录，保证结果可复现、可复盘。
	var keep_history_count: int = 0
	for history_variant: Variant in _controller.state.random_history:
		if str((history_variant as Dictionary).get("kind", "")) == "duyi_keep_suit":
			keep_history_count += 1
	if keep_history_count != 4:
		return _fail("duyi_history=%d" % keep_history_count)
	# 阶段已跳过：手牌没有被调整到体力值3，且阶段不再是本人的弃牌阶段。
	if _controller.state.current_phase == "discard" and _controller.state.current_player_id == 0:
		return _fail("duyi_phase_not_skipped")
	return true


## 校验【弃和】：成为其他角色伤害牌目标时，随机弃置一张同花色手牌并令此牌对本人无效。
func _test_qihe_negates_same_suit_damage_card() -> bool:
	_reset_state(3)
	if _install_skill(0, "qihe") == null:
		return _fail("qihe_install")
	# 手牌：一张红桃（与来牌同花色）与一张黑桃（不同花色）；只有红桃可以被随机弃置。
	var heart_card: CardInstance = _add_hand_card(0, "shan", "heart", 6)
	var spade_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	# 玩家1对玩家0使用红桃【杀】；处理区实体与用牌上下文按正式结构手工装配。
	var slash: CardInstance = CardInstance.new("sha", "heart", 9)
	slash.zone = "processing"
	slash.owner_id = -1
	_controller.state.processing_area.append(slash)
	_controller._card_use_contexts[slash.uid] = {"actor_id":1, "card_definition_id":"sha", "target_ids":[0], "excluded_target_ids":[], "direct_hit_target_ids":[], "custom_args":{}, "virtual_storage":{}}
	_controller._emit_rule_timing("useCardToTargeted", 0, 1, 0, {"timing_name":"useCardToTargeted", "card_uid":slash.uid, "card_id":"sha", "card_suit":"heart", "target_id":0})
	# 只有同花色的红桃被弃置；黑桃必须留在手中。
	var holder: PlayerState = _controller.state.get_player(0)
	if holder.hand.size() != 1 or holder.hand[0].uid != spade_card.uid:
		return _fail("qihe_discarded=%s" % str(holder.hand.map(func(card: CardInstance) -> int: return card.uid)))
	_controller.state.processing_area.erase(heart_card)
	# 该牌对持有者本人无效；其他目标不受影响。
	var excluded: Array = (_controller._card_use_contexts.get(slash.uid, {}) as Dictionary).get("excluded_target_ids", []) as Array
	if excluded != [0]:
		return _fail("qihe_excluded=%s" % str(excluded))
	# 同一张使用牌重复派发同一时机时不得再次弃牌。
	_controller._emit_rule_timing("useCardToTargeted", 0, 1, 0, {"timing_name":"useCardToTargeted", "card_uid":slash.uid, "card_id":"sha", "card_suit":"heart", "target_id":0})
	if holder.hand.size() != 1:
		return _fail("qihe_reentry=%d" % holder.hand.size())
	_controller.state.processing_area.erase(slash)
	_controller._card_use_contexts.erase(slash.uid)
	return true


## 校验【弃和】的发动前提：没有同花色手牌、自己使用、非伤害牌都不弃牌也不令牌无效。
func _test_qihe_requires_same_suit() -> bool:
	_reset_state(3)
	if _install_skill(0, "qihe") == null:
		return _fail("qihe_precondition_install")
	# 前提一：手牌只有黑桃，红桃【杀】找不到同花色牌。
	var spade_card: CardInstance = _add_hand_card(0, "shan", "spade", 6)
	var heart_slash: CardInstance = _build_use_context(1, "sha", "heart", [0])
	_controller._emit_rule_timing("useCardToTargeted", 0, 1, 0, {"timing_name":"useCardToTargeted", "card_uid":heart_slash.uid, "card_id":"sha", "card_suit":"heart", "target_id":0})
	var holder: PlayerState = _controller.state.get_player(0)
	if holder.hand.size() != 1 or not (_controller._card_use_contexts.get(heart_slash.uid, {}) as Dictionary).get("excluded_target_ids", []).is_empty():
		return _fail("qihe_no_same_suit")
	_erase_use_context(heart_slash)
	# 前提二：非伤害牌（锦囊）即使同花色也不触发。
	var spade_trick: CardInstance = _build_use_context(1, "guohe", "spade", [0])
	_controller._emit_rule_timing("useCardToTargeted", 0, 1, 0, {"timing_name":"useCardToTargeted", "card_uid":spade_trick.uid, "card_id":"guohe", "card_suit":"spade", "target_id":0})
	if holder.hand.size() != 1 or not (_controller._card_use_contexts.get(spade_trick.uid, {}) as Dictionary).get("excluded_target_ids", []).is_empty():
		return _fail("qihe_non_damage_card")
	_erase_use_context(spade_trick)
	# 前提三：自己使用的伤害牌不能对自己触发锁定技。
	var self_slash: CardInstance = _build_use_context(0, "sha", "spade", [0])
	_controller._emit_rule_timing("useCardToTargeted", 0, 0, 0, {"timing_name":"useCardToTargeted", "card_uid":self_slash.uid, "card_id":"sha", "card_suit":"spade", "target_id":0})
	if holder.hand.size() != 1 or not (_controller._card_use_contexts.get(self_slash.uid, {}) as Dictionary).get("excluded_target_ids", []).is_empty():
		return _fail("qihe_self_actor")
	_erase_use_context(self_slash)
	# 前提四：无花色虚拟伤害牌不与任何手牌花色相同。
	var virtual_slash: CardInstance = _build_use_context(1, "sha", "none", [0])
	_controller._emit_rule_timing("useCardToTargeted", 0, 1, 0, {"timing_name":"useCardToTargeted", "card_uid":virtual_slash.uid, "card_id":"sha", "card_suit":"none", "target_id":0})
	if holder.hand.size() != 1 or not (_controller._card_use_contexts.get(virtual_slash.uid, {}) as Dictionary).get("excluded_target_ids", []).is_empty():
		return _fail("qihe_suitless_card")
	_erase_use_context(virtual_slash)
	if spade_card == null:
		return _fail("qihe_precondition_card_missing")
	return true


## 校验【自摸】分支A：摸一张牌后以虚拟手牌选择视为使用的牌，取消只重新选牌，普通锦囊进入整局使用记录。
func _test_zimo_draw_branch_virtual_use() -> bool:
	_reset_state(2)
	# 手牌只有两种花色（少于4），因此必然进入分支A。
	var spade_card: CardInstance = _add_hand_card(0, "sha", "spade", 1)
	var heart_card: CardInstance = _add_hand_card(0, "shan", "heart", 2)
	if _install_skill(0, "zimo") == null:
		return _fail("zimo_install")
	var zimo: SkillDefinition = _controller.get_skill_instance(0, "zimo")
	# 牌堆：分支A摸一张，【无中生有】再摸两张。
	_add_draw_pile_card("tao", "club", 3)
	_add_draw_pile_card("tao", "club", 4)
	_add_draw_pile_card("tao", "club", 5)
	if not zimo.can_activate():
		return _fail("zimo_branch_a_blocked")
	if not _activate_skill(0, "zimo"):
		return false
	var owner: PlayerState = _controller.state.get_player(0)
	if owner.hand.size() != 3:
		return _fail("zimo_branch_a_draw=%d" % owner.hand.size())
	# 请求必须是虚拟手牌选牌请求：候选位于virtual_hand区、无花色、无点数。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(request.get("choice_type", "")) != "card_target":
		return _fail("zimo_choice_type=%s" % str(request.get("choice_type", "")))
	var context: Dictionary = request.get("context", {}) as Dictionary
	if not bool(context.get("virtual_hand", false)):
		return _fail("zimo_virtual_flag")
	var candidates: Array = request.get("candidates", []) as Array
	if candidates.size() < 2:
		return _fail("zimo_candidates=%d" % candidates.size())
	for candidate_variant: Variant in candidates:
		# 当前虚拟候选；区域、标记与牌面快照都必须声明为虚拟牌。
		var candidate: Dictionary = candidate_variant as Dictionary
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(candidate.get("zone", "")) != "virtual_hand" or not bool(candidate.get("virtual_hand", false)):
			return _fail("zimo_candidate_zone=%s" % str(candidate))
		if str(card_data.get("suit", "spade")) != "none" or int(card_data.get("rank", -1)) != 0:
			return _fail("zimo_candidate_suit_rank=%s" % str(card_data))
		if int(candidate.get("uid", -1)) < SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE:
			return _fail("zimo_candidate_uid=%d" % int(candidate.get("uid", -1)))
	# 取消：不重新摸牌，但会重新建立选牌请求。
	if not _submit_pending_choice(0, [], [], false):
		return false
	if owner.hand.size() != 3:
		return _fail("zimo_cancel_redraw=%d" % owner.hand.size())
	if not _controller.has_pending_card_choice():
		return _fail("zimo_cancel_reopen")
	# 第二次请求中选出【无中生有】并提交自身目标；视为使用应真实结算摸两张。
	var wuzhong_uid: int = _find_virtual_candidate_uid(_controller._pending_card_choice, "wuzhong")
	if wuzhong_uid < 0:
		return _fail("zimo_wuzhong_missing")
	if not _submit_pending_choice(0, [wuzhong_uid], [0], true):
		return false
	if owner.hand.size() != 5:
		return _fail("zimo_virtual_use_draw=%d" % owner.hand.size())
	# 整局使用记录：普通锦囊写入名单，【杀】不写入。
	var used_names: Array = _controller.get_skill_used_card_names(0, "zimo") as Array
	if used_names != ["wuzhong"]:
		return _fail("zimo_used_names=%s" % str(used_names))
	# 原文没有“出牌阶段限一次”表述：基础状态不限次（-1），因此第一次视为使用之后仍可继续发动。
	if int(zimo.call("_get_play_phase_limit")) != -1:
		return _fail("zimo_base_limit=%d" % int(zimo.call("_get_play_phase_limit")))
	if not zimo.can_activate():
		return _fail("zimo_unlimited_blocked")
	var effect_ids: Array = zimo.call("_get_effect_definition_ids") as Array
	if effect_ids.has("wuzhong") or not effect_ids.has("sha"):
		return _fail("zimo_effect_ids=%s" % str(effect_ids))
	if spade_card == null or heart_card == null:
		return _fail("zimo_branch_a_cards")
	return true


## 校验【自摸】分支B：弃置一种花色的全部手牌并把上限改写为“出牌阶段限两次”，且仅在本回合内有效。
func _test_zimo_suit_branch_extends_limit() -> bool:
	_reset_state(2)
	# 手牌覆盖四种花色（不少于4），因此必然进入分支B。
	_add_hand_card(0, "sha", "spade", 1)
	_add_hand_card(0, "shan", "heart", 2)
	_add_hand_card(0, "tao", "heart", 3)
	_add_hand_card(0, "jiu", "club", 4)
	_add_hand_card(0, "wuxie", "diamond", 5)
	if _install_skill(0, "zimo") == null:
		return _fail("zimo_suit_install")
	var zimo: SkillDefinition = _controller.get_skill_instance(0, "zimo")
	if int(zimo.call("_get_play_phase_limit")) != -1:
		return _fail("zimo_base_limit=%d" % int(zimo.call("_get_play_phase_limit")))
	if not _activate_skill(0, "zimo"):
		return false
	# 请求必须是四种花色的内联选项。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(request.get("choice_type", "")) != "control":
		return _fail("zimo_suit_choice_type=%s" % str(request.get("choice_type", "")))
	var options: Array = request.get("control_options", []) as Array
	if options.size() != 4:
		return _fail("zimo_suit_options=%d" % options.size())
	var owner: PlayerState = _controller.state.get_player(0)
	if not _submit_pending_choice(0, [], [], true, "heart"):
		return false
	# 红桃全部被弃置；其它花色保留。
	for card: CardInstance in owner.hand:
		if card.suit == "heart":
			return _fail("zimo_heart_kept=%d" % card.uid)
	if owner.hand.size() != 3:
		return _fail("zimo_suit_hand=%d" % owner.hand.size())
	# 上限已扩展为2：同一回合内还能再发动一次；此时花色数降到3，走分支A。
	if int(zimo.call("_get_play_phase_limit")) != 2:
		return _fail("zimo_extended_limit=%d" % int(zimo.call("_get_play_phase_limit")))
	_add_draw_pile_card("tao", "club", 6)
	_add_draw_pile_card("tao", "club", 7)
	_add_draw_pile_card("tao", "club", 8)
	if not zimo.can_activate():
		return _fail("zimo_extended_blocked")
	if not _activate_skill(0, "zimo"):
		return false
	var wuzhong_uid: int = _find_virtual_candidate_uid(_controller._pending_card_choice, "wuzhong")
	if wuzhong_uid < 0:
		return _fail("zimo_extended_wuzhong_missing")
	if not _submit_pending_choice(0, [wuzhong_uid], [0], true):
		return false
	# 选择窗口期间控制器把当前阶段临时显示为 choice；恢复出牌阶段后再断言额度语义。
	_controller.state.current_phase = "play"
	# 两次额度用尽（分支B 1 次 + 分支A 1 次 = 改写后的 2 次），这里是真正的额度拦截。
	if zimo.can_activate():
		return _fail("zimo_extended_limit_exhausted used=%d" % int(zimo.get("_used_this_play_phase")))
	_controller.state.turn_number += 1
	if int(zimo.call("_get_play_phase_limit")) != -1:
		return _fail("zimo_limit_survives_turn=%d" % int(zimo.call("_get_play_phase_limit")))
	if not zimo.can_activate():
		return _fail("zimo_limit_not_expired phase=%s cur=%d suits=%d effects=%s used=%d" % [str(_controller.state.current_phase), int(_controller.state.current_player_id), int(zimo.call("get_hand_suit_count", _controller.state.get_player(0))), str(zimo.call("_get_effect_definition_ids")), int(zimo.get("_used_this_play_phase"))])
	return true


## 校验【自摸】的AI分支与两个锁定技的来牌估值方向。
func _test_zimo_ai_and_locked_skill_uncertainty() -> bool:
	_reset_state(3)
	# 三种花色（少于4）；同时给三号玩家一张牌，使AI态度与目标估值都有明确来源。
	var spade_card: CardInstance = _add_hand_card(0, "sha", "spade", 1)
	var heart_card: CardInstance = _add_hand_card(0, "shan", "heart", 2)
	var club_card: CardInstance = _add_hand_card(0, "tao", "club", 3)
	if _install_skill(0, "zimo") == null:
		return _fail("zimo_ai_install")
	var zimo: SkillDefinition = _controller.get_skill_instance(0, "zimo")
	# 权威快照；与正式AI入口一致，先补写限定技用量字段。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 【自摸】主动动作：满足条件时必须给出正分，使AI无脑发动。
	var zimo_actions: Array[Dictionary] = []
	zimo.append_play_phase_actions(zimo_actions)
	if zimo_actions.size() != 1:
		return _fail("zimo_ai_actions=%d" % zimo_actions.size())
	if zimo.score_ai_action(snapshot, zimo_actions[0], evaluator) <= 0.0:
		return _fail("zimo_ai_action_score")
	# 【自摸】选牌与花色选择：确认提交必须严格高于取消的0分，且张数少的花色更受偏好。
	var card_choice_request: Dictionary = {"context":{"kind":"zimo_pick_effect", "virtual_hand_definition_ids_by_uid":{str(SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE):"wuzhong"}}, "candidates":[]}
	var card_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE]}}
	var cancel_action: Dictionary = {"payload":{"confirmed":false, "selected_card_uids":[]}}
	if zimo.score_ai_choice(snapshot, card_choice_request, card_action, evaluator) <= zimo.score_ai_choice(snapshot, card_choice_request, cancel_action, evaluator):
		return _fail("zimo_ai_card_choice")
	# 【自摸】候选的目标维度：同一张【杀】打敌人必须严格优于打队友。
	# 修复前技能层只给固定常量、通用层又只按“选中牌本身的保留价值”扣分，两个目标因此恒等，
	# AI 只能取枚举顺序里的第一项，表现为一直对最友好的角色使用【杀】。
	var slash_choice_request: Dictionary = {"context":{"kind":"zimo_pick_effect", "virtual_hand_definition_ids_by_uid":{str(SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE):"sha"}}, "candidates":[]}
	# 打敌人（一号位反贼）与打队友（二号位忠臣）的两条完整提交；牌名与选中牌完全相同，只有目标不同。
	var enemy_slash_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE], "selected_target_ids":[1]}}
	var ally_slash_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE], "selected_target_ids":[2]}}
	var enemy_slash_score: float = zimo.score_ai_choice(snapshot, slash_choice_request, enemy_slash_action, evaluator)
	var ally_slash_score: float = zimo.score_ai_choice(snapshot, slash_choice_request, ally_slash_action, evaluator)
	if enemy_slash_score <= ally_slash_score:
		return _fail("zimo_ai_target_choice enemy=%f ally=%f" % [enemy_slash_score, ally_slash_score])
	# 选牌维度：同一目标下，能带来摸牌收益的【无中生有】必须优于只能造成伤害的【杀】之外的低收益牌。
	# 两条提交都保留同一张占位牌，差异只来自牌面AI配置，验证代理评分确实读取了每张牌自己的收益。
	var sha_score: float = zimo.score_ai_choice(snapshot, slash_choice_request, enemy_slash_action, evaluator)
	var wuzhong_choice_request: Dictionary = {"context":{"kind":"zimo_pick_effect", "virtual_hand_definition_ids_by_uid":{str(SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE):"wuzhong"}}, "candidates":[]}
	var wuzhong_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[SkillDefinition.VIRTUAL_HAND_CANDIDATE_UID_BASE], "selected_target_ids":[0]}}
	if zimo.score_ai_choice(snapshot, wuzhong_choice_request, wuzhong_action, evaluator) <= sha_score:
		return _fail("zimo_ai_card_choice_by_name sha=%f wuzhong=%f" % [sha_score, zimo.score_ai_choice(snapshot, wuzhong_choice_request, wuzhong_action, evaluator)])
	var suit_choice_request: Dictionary = {"context":{"kind":"zimo_pick_suit", "suit_card_counts":{"spade":1, "heart":4}}, "candidates":[]}
	var single_suit_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"spade"}}
	var many_suit_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"heart"}}
	if zimo.score_ai_choice(snapshot, suit_choice_request, single_suit_action, evaluator) <= zimo.score_ai_choice(snapshot, suit_choice_request, many_suit_action, evaluator):
		return _fail("zimo_ai_suit_choice")
	# 【弃和】使伤害牌对持有者的估值按“同花色手牌命中概率”衰减；没有手牌时估值不变。
	if _install_skill(1, "qihe") == null:
		return _fail("qihe_ai_install")
	# 弃和持有者手牌；命中概率由手牌张数决定，必须给两张才能观察到估值衰减。
	_add_hand_card(1, "shan", "spade", 11)
	_add_hand_card(1, "tao", "heart", 12)
	var qihe: SkillDefinition = _controller.get_skill_instance(1, "qihe")
	var slash_definition: Dictionary = GameDatabase.get_card("sha")
	var loaded_snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(loaded_snapshot)
	var loaded_score: float = qihe.modify_ai_incoming_card_effect(loaded_snapshot, 0, 1, slash_definition, {"damage":true}, -1.5, 1, 3.0, evaluator)
	if loaded_score >= 3.0:
		return _fail("qihe_ai_score=%f" % loaded_score)
	var empty_hand_player: PlayerState = _controller.state.get_player(1)
	var hand_backup: Array[CardInstance] = empty_hand_player.hand.duplicate()
	empty_hand_player.hand.clear()
	var empty_snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(empty_snapshot)
	if not is_equal_approx(qihe.modify_ai_incoming_card_effect(empty_snapshot, 0, 1, slash_definition, {"damage":true}, -1.5, 1, 3.0, evaluator), 3.0):
		return _fail("qihe_ai_empty_hand")
	empty_hand_player.hand.assign(hand_backup)
	# 非伤害牌不受【弃和】影响。
	if not is_equal_approx(qihe.modify_ai_incoming_card_effect(loaded_snapshot, 0, 1, GameDatabase.get_card("guohe"), {"damage":false}, -1.5, 0, 3.0, evaluator), 3.0):
		return _fail("qihe_ai_non_damage")
	# 【独弈】无法打出手牌【闪】，因此对持有者使用的【杀】估值被放大；非【杀】牌不受影响。
	if _install_skill(2, "duyi") == null:
		return _fail("duyi_ai_install")
	var duyi: SkillDefinition = _controller.get_skill_instance(2, "duyi")
	var slash_score: float = duyi.modify_ai_incoming_card_effect(snapshot, 0, 2, slash_definition, {"damage":true, "respond_shan":true}, -1.5, 1, 3.0, evaluator)
	if slash_score <= 3.0:
		return _fail("duyi_ai_score=%f" % slash_score)
	if not is_equal_approx(duyi.modify_ai_incoming_card_effect(snapshot, 0, 2, slash_definition, {"damage":true}, -1.5, 1, 3.0, evaluator), 3.0):
		return _fail("duyi_ai_non_slash")
	if not is_equal_approx(duyi.modify_ai_incoming_card_effect(snapshot, 0, 0, slash_definition, {"damage":true, "respond_shan":true}, -1.5, 1, 3.0, evaluator), 3.0):
		return _fail("duyi_ai_other_target")
	if spade_card == null or heart_card == null or club_card == null:
		return _fail("zimo_ai_cards")
	return true


## 校验【自摸】分支A的候选池：有序双目标牌必须用全体角色试算组合，不能复用单目标候选列表。
##
## 【借刀杀人】两个位置的约束完全不同：第一名必须是“持武器的其他角色”，第二名必须是“该持刀者攻击范围内的角色”。
## 旧实现把 list_legal_virtual_targets 的单元素试算结果同时当作两个位置的候选，于是：
## 没有武器的角色永远进不了第二个位置（本应可以成为被【杀】者）；
## 有武器但当前找不到合法受害者的角色也永远无法成为第一名。
## 在只有一名持武器角色的局面里，这两个缺陷叠加会把候选组合直接压成空数组，
## 表现为【自摸】的候选列表里根本没有【借刀杀人】。
func _test_zimo_ordered_pair_candidate_pool() -> bool:
	_reset_state(3)
	# 持有者手牌两种花色（少于4），必然走分支A；花色数不足时不会因为没有锦囊候选而整支跳过。
	_add_hand_card(0, "sha", "spade", 1)
	_add_hand_card(0, "shan", "heart", 2)
	if _install_skill(0, "zimo") == null:
		return _fail("zimo_pool_install")
	# 一号位是全场唯一持武器角色；持有者与二号位都没有武器，只可能充当第二个位置。
	var weapon_card: CardInstance = CardInstance.new("qinggang", "spade", 3)
	weapon_card.zone = "equipment"
	weapon_card.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = weapon_card
	# 分支A先摸一张牌；牌堆留一张保证摸牌结算本身不因空堆中断。
	_add_draw_pile_card("tao", "club", 4)
	if not _activate_skill(0, "zimo"):
		return false
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	var jiedao_uid: int = _find_virtual_candidate_uid(request, "jiedao")
	if jiedao_uid < 0:
		return _fail("zimo_pool_jiedao_missing candidates=%s" % str(request.get("candidates", [])))
	# 请求声明的组合表；界面与AI读取同一份可序列化数据，断言它而不是在测试里重算，才能验证真实链路。
	var combinations: Dictionary = (request.get("context", {}) as Dictionary).get("target_combinations_by_card_id", {}) as Dictionary
	var jiedao_combinations: Array = combinations.get(str(jiedao_uid), []) as Array
	if not jiedao_combinations.has([1, 0]) or not jiedao_combinations.has([1, 2]):
		return _fail("zimo_pool_jiedao_combinations=%s" % str(jiedao_combinations))
	# 组合必须恰好两条：只有一号位能当持刀者，无武器角色不会因为自身没武器而被排除在第二个位置之外。
	if jiedao_combinations.size() != 2:
		return _fail("zimo_pool_jiedao_extra=%s" % str(jiedao_combinations))
	# 单目标牌继续使用单元素候选列表：持有者自己永远不能成为自己【杀】的目标。
	var sha_uid: int = _find_virtual_candidate_uid(request, "sha")
	if sha_uid < 0:
		return _fail("zimo_pool_sha_missing")
	var sha_combinations: Array = combinations.get(str(sha_uid), []) as Array
	if not sha_combinations.has([1]) or not sha_combinations.has([2]) or sha_combinations.has([0]):
		return _fail("zimo_pool_sha_combinations=%s" % str(sha_combinations))
	# 取消语义与界面契约：取消仍然是一个合法响应（表示重新选牌），但请求必须声明隐藏取消按钮。
	if not bool(request.get("allow_cancel", false)):
		return _fail("zimo_pool_allow_cancel=%s" % str(request.get("allow_cancel", false)))
	if not bool((request.get("context", {}) as Dictionary).get("hide_cancel_button", false)):
		return _fail("zimo_pool_hide_cancel=%s" % str(request.get("context", {})))
	if not bool((request.get("context", {}) as Dictionary).get("ai_choice_skill_scored", false)):
		return _fail("zimo_pool_skill_scored=%s" % str(request.get("context", {})))
	return true


## 为指定玩家安装一个运行时技能实例；返回null表示技能目录缺失。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家已安装技能表；同一场景可追加多个技能以验证技能间联动。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 通过正式技能动作入口发动主动技；需要出牌选择时先建立该选择。
func _activate_skill(player_id: int, skill_id: String) -> bool:
	if not _controller._has_active_play_choice():
		_controller._begin_play_choice(player_id)
	# 标准主动技能动作；只提交稳定技能ID，具体交互由技能自行建立。
	var action: PlayerAction = PlayerAction.new("use_skill", player_id)
	action.payload = {"skill_id":skill_id}
	if not _controller.submit_action(action):
		return _fail("skill_submit_rejected skill=%s" % skill_id)
	return true


## 从当前虚拟手牌请求中查找指定牌名的占位UID；找不到返回-1。
func _find_virtual_candidate_uid(choice_data: Dictionary, definition_id: String) -> int:
	for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
		# 当前虚拟候选；牌名来自card_data，占位UID是提交与映射的唯一身份。
		var candidate: Dictionary = candidate_variant as Dictionary
		if str((candidate.get("card_data", {}) as Dictionary).get("definition_id", "")) == definition_id:
			return int(candidate.get("uid", -1))
	return -1


## 装配一张处于使用中的实体牌及其用牌上下文；返回该实体供时机派发使用。
func _build_use_context(actor_id: int, definition_id: String, suit: String, target_ids: Array[int]) -> CardInstance:
	var card: CardInstance = CardInstance.new(definition_id, suit, 9)
	card.zone = "processing"
	card.owner_id = -1
	_controller.state.processing_area.append(card)
	_controller._card_use_contexts[card.uid] = {"actor_id":actor_id, "card_definition_id":definition_id, "target_ids":target_ids.duplicate(), "excluded_target_ids":[], "direct_hit_target_ids":[], "custom_args":{}, "virtual_storage":{}}
	return card


## 清理一张测试用牌的处理区实体与用牌上下文。
func _erase_use_context(card: CardInstance) -> void:
	_controller.state.processing_area.erase(card)
	_controller._card_use_contexts.erase(card.uid)


## 为当前统一选择请求提交牌、目标、文字选项或确认结果；覆盖事件运行时与阶段恢复链。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool, selected_control_id: String = "") -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s pending=%s" % [actor_id, request_id, action.payload, _controller._pending_card_choice])
	return true


## 向指定玩家普通手牌区加入一张测试实体；花色、点数、区域与所有者全部显式写入。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向当前测试牌堆顶部加入一张实体；数组末尾固定表示最顶层。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("QINGQUE_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
