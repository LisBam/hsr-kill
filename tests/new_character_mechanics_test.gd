extends Node

## 新武将机制专项回归。覆盖规则牌名、武将引用、额外阶段恢复、临时牌名、嵌套技能结算及新技能的核心AI分支。

## 武将牌可复用场景；用真实场景结构验证横置灰白线状态不会改变牌面变换或全局包围矩形。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 每个机制场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保GameDatabase已完成新武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行新机制回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_rule_names():
		return
	if not _test_expanded_character_metadata():
		return
	if not _test_named_card_gain_and_hand_view_as():
		return
	if not _test_lushi_mingchen_deferred_settlement():
		return
	if not _test_huanyang_and_sefu():
		return
	if not _test_huanfa_extra_play_phase_completion():
		return
	if not await _test_character_card_link_overlay():
		return
	if not _test_jiahu_and_bingfeng():
		return
	if not await _test_deferred_phase_choice_resumption():
		return
	if not _test_gangfeng_response():
		return
	if not _test_jiyu_branches():
		return
	if not _test_yongyi_and_shield_semantics():
		return
	if not _test_new_skill_ai_rules():
		return
	print("NEW_CHARACTER_MECHANICS_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；护盾、伤害和技能时机共用该节点。
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


## 为当前单项测试创建最小权威状态；一号领袖、二号反贼、三号及以后忠臣使AI态度确定。
func _reset_state(player_count: int) -> void:
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "new-character-mechanics"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "新武将玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, _controller.state)
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._active_extra_discard_phase.clear()
	_controller._extra_play_phase_counts.clear()
	_controller._extra_play_phase_returns_to_finish.clear()
	_controller._extra_play_phase_return_points.clear()
	_controller._active_extra_play_phase_context.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._cards_used_this_turn_by_player.clear()
	_controller._started_phase_lifecycles.clear()
	_controller._pending_finish_turn_player_id = -1


## 验证属性【杀】的规则名与显示名分离，并核对三名武将的体力、势力和技能引用。
func _test_metadata_and_rule_names() -> bool:
	# 火【杀】与雷【杀】定义；rule_name用于规则称呼，original_name与custom_name继续提供两字牌面。
	var fire_slash: Dictionary = GameDatabase.get_card("sha_fire")
	# 雷【杀】定义；与火【杀】共同校验规则名和牌面显示名分离。
	var thunder_slash: Dictionary = GameDatabase.get_card("sha_thunder")
	if str(fire_slash.get("rule_name", "")) != "杀" or str(thunder_slash.get("rule_name", "")) != "杀" or str(fire_slash.get("original_name", "")) != "火杀" or str(thunder_slash.get("custom_name", "")) != "雷杀":
		return _fail("attribute_slash_names fire=%s thunder=%s" % [fire_slash, thunder_slash])
	# 三名新武将定义；技能数组顺序就是面板与运行时安装顺序。
	var march: Dictionary = GameDatabase.get_character("march_7th")
	# 杰帕德武将定义；验证势力、性别、体力与【永屹】引用。
	var gepard: Dictionary = GameDatabase.get_character("gepard")
	# 丹恒武将定义；验证势力、性别、体力与【罡风】【疾雨】引用。
	var dan_heng: Dictionary = GameDatabase.get_character("dan_heng")
	if int(march.get("max_hp", 0)) != 3 or str(march.get("gender", "")) != "female" or str(march.get("faction", "")) != "xingqionglieche" or (march.get("skills", []) as Array) != ["jiahu", "bingfeng"]:
		return _fail("march_metadata=%s" % march)
	if int(gepard.get("max_hp", 0)) != 4 or str(gepard.get("gender", "")) != "male" or str(gepard.get("faction", "")) != "beiluoboge" or (gepard.get("skills", []) as Array) != ["yongyi"]:
		return _fail("gepard_metadata=%s" % gepard)
	if int(dan_heng.get("max_hp", 0)) != 4 or str(dan_heng.get("faction", "")) != "xingqionglieche" or (dan_heng.get("skills", []) as Array) != ["gangfeng", "jiyu"]:
		return _fail("dan_heng_metadata=%s" % dan_heng)
	if not GameDatabase.get_skill("six_phased_ice_sample").is_empty() or not GameDatabase.get_skill("cloud_piercer_sample").is_empty():
		return _fail("placeholder_skills_still_registered")
	return true


## 核对娜塔莎、寒鸦、雪衣的稳定资料与技能原文，并确认三个旧占位武将已经退出自动索引。
func _test_expanded_character_metadata() -> bool:
	# 娜塔莎定义；贝洛伯格女性、3点体力与双技能顺序必须保持稳定。
	var natasha: Dictionary = GameDatabase.get_character("natasha")
	# 寒鸦定义；仙舟联盟女性、3点体力与双技能顺序必须保持稳定。
	var hanya: Dictionary = GameDatabase.get_character("hanya")
	# 雪衣定义；内部ID按设计固定为xveyi，基础体力为4。
	var xveyi: Dictionary = GameDatabase.get_character("xveyi")
	if str(natasha.get("gender", "")) != "female" or str(natasha.get("faction", "")) != "beiluoboge" or int(natasha.get("max_hp", 0)) != 3 or (natasha.get("skills", []) as Array) != ["yaoli", "huanfa"]:
		return _fail("natasha_metadata=%s" % natasha)
	if str(hanya.get("gender", "")) != "female" or str(hanya.get("faction", "")) != "xianzhou" or int(hanya.get("max_hp", 0)) != 3 or (hanya.get("skills", []) as Array) != ["mingchen", "lushi"]:
		return _fail("hanya_metadata=%s" % hanya)
	if str(xveyi.get("display_name", "")) != "雪衣" or str(xveyi.get("gender", "")) != "female" or str(xveyi.get("faction", "")) != "xianzhou" or int(xveyi.get("max_hp", 0)) != 4 or (xveyi.get("skills", []) as Array) != ["huanyang", "sefu"]:
		return _fail("xveyi_metadata=%s" % xveyi)
	# 六项技能说明；玩家可见文本必须逐字保持机制设计原文。
	var expected_descriptions: Dictionary = {
		"yaoli":"出牌阶段限一次，你可交给一名角色一张红色手牌，然后此牌视为【药】直到离开其手牌区。",
		"huanfa":"一名角色的回合结束时，若本回合内其使用过【药】，你可令其执行一个额外的出牌阶段。每轮限一次。",
		"mingchen":"锁定技，当你失去最后的手牌后，你令一名角色从牌堆或弃牌堆中获得一张【无中生有】。若该角色不为你，你令其对其造成1点雷属性伤害。",
		"lushi":"出牌阶段，你可弃置两张牌名字字数相同的牌，然后摸一张牌。",
		"huanyang":"锁定技，当你对距离为1以内的角色造成伤害时，你回复1点体力。",
		"sefu":"锁定技，当你于回合内首次使用牌造成伤害后，你令一名角色从牌堆中获得一张牌名字数与此牌相同的牌。若该角色为目标角色，你弃置其装备区内的一张牌。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能ID；用于自动索引中读取对应说明。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("expanded_skill_description=%s" % skill_id)
	if not GameDatabase.get_character("jingyuan").is_empty() or not GameDatabase.get_character("kafka").is_empty() or not GameDatabase.get_character("welt").is_empty():
		return _fail("removed_placeholder_character_registered")
	return true


## 验证指定牌先检索牌堆、缺失后检索弃牌堆的顶部匹配顺序，并验证【药】在离开手牌区时恢复原牌名。
func _test_named_card_gain_and_hand_view_as() -> bool:
	_reset_state(2)
	# 牌堆中的【无中生有】；即使其上方有其他牌，也应优先于弃牌堆中的同名牌被获得。
	var draw_wuzhong: CardInstance = _add_draw_pile_card("wuzhong", "heart", 7)
	# 牌堆顶非匹配牌；检索指定牌时保持在原位。
	var draw_top_other: CardInstance = _add_draw_pile_card("shan", "club", 8)
	# 弃牌堆较低的匹配牌；仅用于证明倒序检索会选择更靠近弃牌堆顶的实体。
	var discard_lower_wuzhong: CardInstance = _add_discard_pile_card("wuzhong", "diamond", 9)
	# 弃牌堆中的间隔牌；不会因指定牌检索改变相对顺序。
	var discard_middle_other: CardInstance = _add_discard_pile_card("sha", "spade", 10)
	# 弃牌堆最顶层匹配牌；牌堆已无指定牌时应成为第二次获得结果。
	var discard_top_wuzhong: CardInstance = _add_discard_pile_card("wuzhong", "club", 11)
	# 第一次获得结果；来源必须是牌堆中的唯一匹配牌。
	var first_gain: CardInstance = _controller.gain_top_named_card_from_draw_or_discard(0, "wuzhong", "test_named_gain")
	# 第二次获得结果；牌堆无匹配牌后必须回退到弃牌堆最顶层匹配牌。
	var second_gain: CardInstance = _controller.gain_top_named_card_from_draw_or_discard(0, "wuzhong", "test_named_gain")
	if first_gain != draw_wuzhong or second_gain != discard_top_wuzhong or not _controller.state.draw_pile.has(draw_top_other) or not _controller.state.discard_pile.has(discard_lower_wuzhong) or not _controller.state.discard_pile.has(discard_middle_other):
		return _fail("named_gain_order first=%s second=%s" % [first_gain.uid if first_gain != null else -1, second_gain.uid if second_gain != null else -1])
	# 交给其他角色的红色实体；进入目标手牌后临时视为【桃/药】。
	var gifted_card: CardInstance = _add_hand_card(0, "sha", "heart", 5)
	if not _controller.transfer_hand_card_as(0, 1, gifted_card.uid, "tao", "yaoli") or gifted_card.definition_id != "tao" or gifted_card.hand_view_as_original_definition_id != "sha" or _controller.state.get_player(1).find_hand_card(gifted_card.uid) == null:
		return _fail("hand_view_as_gift=%s" % gifted_card.to_dict())
	if not _controller.discard_card_from_hand(1, gifted_card.uid) or gifted_card.definition_id != "sha" or gifted_card.has_hand_view_as() or not _controller.state.discard_pile.has(gifted_card):
		return _fail("hand_view_as_leave_restore=%s" % gifted_card.to_dict())
	# 交给自己的红色实体；同区域操作不产生无效移动，但仍建立相同临时牌名。
	var self_gifted_card: CardInstance = _add_hand_card(0, "shan", "diamond", 6)
	if not _controller.transfer_hand_card_as(0, 0, self_gifted_card.uid, "tao", "yaoli") or self_gifted_card.definition_id != "tao":
		return _fail("hand_view_as_self=%s" % self_gifted_card.to_dict())
	# 药的使用者受伤状态；使用视为【药】后应固定回复1点体力。
	var medicine_user: PlayerState = _controller.state.get_player(0)
	medicine_user.hp = 3
	# 标准出牌请求；正式对局必须先建立 chooseToUse 窗口，测试也通过同一调度入口提交动作。
	_controller._begin_play_choice(0)
	# 视为【药】的标准使用动作；逻辑牌按桃结算，持久实体离开手牌时恢复为原【闪】。
	var medicine_action: PlayerAction = PlayerAction.new("use_card", 0, self_gifted_card.uid, [0])
	if not _controller.submit_action(medicine_action) or medicine_user.hp != 4 or self_gifted_card.definition_id != "shan" or self_gifted_card.has_hand_view_as() or not _controller.state.discard_pile.has(self_gifted_card):
		return _fail("hand_view_as_use hp=%d card=%s" % [medicine_user.hp, self_gifted_card.to_dict()])
	return true


## 验证录事弃空手牌触发冥谶时先完成目标选择，再恢复录事摸牌，整个嵌套结算不会停滞或丢失后续步骤。
func _test_lushi_mingchen_deferred_settlement() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "hanya"
	# 寒鸦的冥谶实例；负责失去最后手牌后的强制目标选择。
	var mingchen: SkillDefinition = GameDatabase.create_skill("mingchen")
	# 寒鸦的录事实例；负责同字数双牌费用与延迟摸牌步骤。
	var lushi: SkillDefinition = GameDatabase.create_skill("lushi")
	mingchen.bind(_controller, 0)
	lushi.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"mingchen":mingchen, "lushi":lushi}}
	mingchen.install()
	lushi.install()
	# 活动出牌阶段生命周期；选择恢复后必须返回原出牌请求，而不是误判为阶段已经结束。
	_controller._started_phase_lifecycles["0:phaseUse"] = {"status":"body", "event_data":{"turn_number":1}, "parent_event_id":-1}
	# 第一张一字手牌；与【闪】共同构成录事合法组合。
	var first_cost: CardInstance = _add_hand_card(0, "sha", "club", 3)
	# 第二张一字手牌；弃置后寒鸦失去最后手牌并触发冥谶。
	var second_cost: CardInstance = _add_hand_card(0, "shan", "spade", 4)
	# 录事后续摸到的牌；位于【无中生有】下方，冥谶先取走顶牌后才会被摸取。
	var lushi_draw_card: CardInstance = _add_draw_pile_card("tao", "heart", 2)
	# 冥谶指定获得牌；位于当前牌堆顶。
	var mingchen_gain_card: CardInstance = _add_draw_pile_card("wuzhong", "diamond", 12)
	# 主动技能错误信息；空字符串表示两张费用已经成功弃置并进入嵌套选择。
	var activation_error: String = lushi.activate({"card_uids":[first_cost.uid, second_cost.uid]})
	if not activation_error.is_empty() or not _controller.has_pending_card_choice() or _controller._deferred_skill_settlements.size() != 1:
		return _fail("lushi_nested_start error=%s pending=%s deferred=%s" % [activation_error, _controller.has_pending_card_choice(), _controller._deferred_skill_settlements])
	if not _submit_pending_choice(0, [], [0], true):
		return false
	# 结算完成后的寒鸦手牌；应同时包含冥谶取得的【无中生有】与录事最后摸到的【桃】。
	var hanya_hand: Array[CardInstance] = _controller.state.get_player(0).hand
	if not hanya_hand.has(mingchen_gain_card) or not hanya_hand.has(lushi_draw_card) or not _controller._deferred_skill_settlements.is_empty() or _controller.has_pending_card_choice():
		return _fail("lushi_nested_complete hand=%d deferred=%s pending=%s" % [hanya_hand.size(), _controller._deferred_skill_settlements, _controller.has_pending_card_choice()])
	return true


## 验证还阳按当前距离回复，以及摄伏按伤害牌名字数获牌并在选择原伤害目标时弃置其装备。
func _test_huanyang_and_sefu() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "xveyi"
	# 还阳实例；直接消费标准damageSource事件。
	var huanyang: SkillDefinition = GameDatabase.create_skill("huanyang")
	# 摄伏实例；维护本回合首次伤害额度并创建两段选择。
	var sefu: SkillDefinition = GameDatabase.create_skill("sefu")
	huanyang.bind(_controller, 0)
	sefu.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"huanyang":huanyang, "sefu":sefu}}
	# 雪衣受伤状态；满足还阳时应从3点回复至4点。
	var xveyi_player: PlayerState = _controller.state.get_player(0)
	xveyi_player.hp = 3
	# 标准伤害来源事件；【杀】原版名字数为1，目标是距离1的二号角色。
	var damage_source_event: RuleEvent = RuleEvent.new("damageSource", 0, 1, {"amount":1, "card_id":"sha"})
	huanyang.call("_on_owner_damage_source", damage_source_event)
	if xveyi_player.hp != 4:
		return _fail("huanyang_recover=%d" % xveyi_player.hp)
	# 二号角色测试装备；摄伏选择原伤害目标后必须建立装备弃置步骤。
	var target_equipment: CardInstance = CardInstance.new("qinggang", "spade", 6)
	target_equipment.zone = "equipment"
	target_equipment.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = target_equipment
	# 牌堆顶一字牌；摄伏按【杀】的一字原版牌名使目标获得该牌。
	var gained_same_length_card: CardInstance = _add_draw_pile_card("shan", "heart", 8)
	sefu.call("_on_owner_damage_source", damage_source_event)
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [], [1], true):
		return _fail("sefu_gain_choice")
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [target_equipment.uid], [], true):
		return _fail("sefu_equipment_choice")
	if not _controller.state.get_player(1).hand.has(gained_same_length_card) or _controller.state.get_player(1).equipment.has("weapon") or not _controller.state.discard_pile.has(target_equipment):
		return _fail("sefu_result hand=%d equipment=%s" % [_controller.state.get_player(1).hand.size(), _controller.state.get_player(1).equipment])
	return true


## 验证焕发在phaseEnd选择中登记额外出牌阶段，并在该阶段结束后只完成一次回合尾部而不重复弃牌或卡死。
func _test_huanfa_extra_play_phase_completion() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "natasha"
	_controller.state.current_phase = "finish"
	_controller.state.phase_index = 5
	# 焕发运行时实例；通过真实统一选择确认每轮一次的额外阶段。
	var huanfa: SkillDefinition = _install_single_skill(0, "huanfa")
	# 本回合用牌事实；逻辑定义ID为tao，无论原实体是否由药理转化都满足焕发。
	_controller._cards_used_this_turn_by_player[0] = {"tao":true}
	# 下一角色摸牌一；保证额外阶段结束后正常回合可以完整进入出牌阶段。
	var next_draw_one: CardInstance = _add_draw_pile_card("sha", "club", 7)
	# 下一角色摸牌二；与前一张共同避免空牌堆提前结束对局。
	var next_draw_two: CardInstance = _add_draw_pile_card("shan", "diamond", 7)
	# 回合结束触发事件；焕发只读取当前回合角色与本回合用牌事实。
	var phase_end_event: RuleEvent = RuleEvent.new("phaseEnd", 0, 0, {"turn_number":1})
	huanfa.call("_on_any_phase_end", phase_end_event)
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [], [], true):
		return _fail("huanfa_confirm_choice")
	# 回合结束插入阶段的后继队列；唯一合法去向是turn_complete，不能回到弃牌阶段。
	var queued_return_points: Array = _controller._extra_play_phase_return_points.get(0, []) as Array
	if int(_controller._extra_play_phase_counts.get(0, 0)) != 1 or queued_return_points != ["turn_complete"]:
		return _fail("huanfa_queue count=%s returns=%s" % [_controller._extra_play_phase_counts, queued_return_points])
	# 本用例关闭表现层阶段停顿；只验证规则后继，不等待真实动画节奏。
	_controller.game_flow_interval_seconds = 0.0
	_controller._continue_after_finish_phase_triggers(0)
	if _controller.state.current_phase != "play" or str(_controller._active_extra_play_phase_context.get("return_point", "")) != "turn_complete" or not _controller._has_active_play_choice():
		return _fail("huanfa_extra_phase_start phase=%s context=%s" % [_controller.state.current_phase, _controller._active_extra_play_phase_context])
	_controller._end_play_phase(0)
	if _controller.state.current_player_id != 1 or _controller.state.current_phase != "play" or _controller.state.turn_number != 2 or not _controller.state.get_player(1).hand.has(next_draw_one) or not _controller.state.get_player(1).hand.has(next_draw_two):
		return _fail("huanfa_extra_phase_finish current=%d phase=%s turn=%d" % [_controller.state.current_player_id, _controller.state.current_phase, _controller.state.turn_number])
	return true


## 验证横置只显示灰白横线状态，不旋转或移动武将牌；竖置时灰白横线状态必须取消。
func _test_character_card_link_overlay() -> bool:
	# 真实武将牌视图；加入场景树后验证规则状态与表现状态的分离。
	var player_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	add_child(player_view)
	await get_tree().process_frame
	# 竖置公开快照；包含武将牌视觉必需的最小字段。
	var snapshot: Dictionary = {"player_id":1, "display_name":"横置测试", "character_id":"march_7th", "identity":"rebel", "hp":3, "max_hp":3, "shield":0, "alive":true, "chained":false, "face_down":false, "hand_count":0, "equipment":{}, "judgment_area":[], "wooden_ox_storage_count":0}
	player_view.configure_snapshot(snapshot, GameDatabase.get_character("march_7th"))
	# 竖置初始位置；横置状态变化后必须保持该布局位置。
	var upright_position: Vector2 = player_view.position
	# 竖置全局矩形；横置状态变化后尺寸与位置都必须保持不变。
	var upright_rect: Rect2 = player_view.get_global_rect()
	# 灰白横线覆盖层；只消费横置布尔值，不改变武将牌节点的旋转或位置。
	var state_overlay: PlayerStateOverlay = player_view.get_node("StateOverlay") as PlayerStateOverlay
	if not is_zero_approx(player_view.rotation):
		player_view.queue_free()
		return _fail("upright_rotation=%s" % player_view.rotation)
	snapshot["chained"] = true
	player_view.configure_snapshot(snapshot, GameDatabase.get_character("march_7th"))
	# 横置全局矩形；横置只切换覆盖层，中间线以外的牌面几何保持竖直不变。
	var chained_rect: Rect2 = player_view.get_global_rect()
	if not is_zero_approx(player_view.rotation) or not player_view.position.is_equal_approx(upright_position) or not chained_rect.is_equal_approx(upright_rect) or state_overlay == null or not bool(state_overlay.get("_is_chained")):
		player_view.queue_free()
		return _fail("chained_overlay_transform rotation=%s position=%s/%s rect=%s/%s chained=%s" % [player_view.rotation, player_view.position, upright_position, chained_rect, upright_rect, bool(state_overlay.get("_is_chained")) if state_overlay != null else false])
	snapshot["chained"] = false
	player_view.configure_snapshot(snapshot, GameDatabase.get_character("march_7th"))
	if not is_zero_approx(player_view.rotation) or not player_view.position.is_equal_approx(upright_position) or bool(state_overlay.get("_is_chained")):
		player_view.queue_free()
		return _fail("upright_overlay_restore rotation=%s position=%s/%s chained=%s" % [player_view.rotation, player_view.position, upright_position, bool(state_overlay.get("_is_chained"))])
	player_view.queue_free()
	return true


## 验证加护的横置护盾顺序，以及冰封的竖置、目标无效与每目标每回合限次。
func _test_jiahu_and_bingfeng() -> bool:
	_reset_state(2)
	# 加护运行时技能；直接恢复标准目标选择以验证权威效果。
	var jiahu: SkillDefinition = GameDatabase.create_skill("jiahu")
	jiahu.bind(_controller, 0)
	# 加护目标响应；确认二号玩家为唯一目标。
	var jiahu_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	jiahu_response.target_ids = [1]
	jiahu.continue_selection({"kind":"jiahu_target"}, jiahu_response)
	# 加护目标状态；应先横置再获得1点护盾。
	var protected_target: PlayerState = _controller.state.get_player(1)
	if not protected_target.chained or protected_target.shield != 1:
		return _fail("jiahu_result chained=%s shield=%d" % [protected_target.chained, protected_target.shield])
	protected_target.shield = 0
	# 冰封运行时技能；一回合内每个目标使用独立额度。
	var bingfeng: SkillDefinition = GameDatabase.create_skill("bingfeng")
	bingfeng.bind(_controller, 0)
	_controller._card_use_contexts[9001] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	# 冰封竖置分支响应；指定玩家可见选项的稳定ID。
	var straighten_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	straighten_response.control_id = "straighten_target"
	bingfeng.continue_selection({"kind":"bingfeng_option", "target_id":1, "card_uid":9001, "card_id":"sha"}, straighten_response)
	# 冰封用牌上下文；非自身目标应加入excluded_target_ids。
	var first_card_context: Dictionary = _controller._card_use_contexts[9001] as Dictionary
	if protected_target.chained or not (first_card_context.get("excluded_target_ids", []) as Array).has(1):
		return _fail("bingfeng_straighten chained=%s context=%s" % [protected_target.chained, first_card_context])
	protected_target.chained = true
	_controller._card_use_contexts[9002] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	bingfeng.continue_selection({"kind":"bingfeng_option", "target_id":1, "card_uid":9002, "card_id":"sha"}, straighten_response)
	# 第二张牌上下文；同回合同目标已用过冰封，不应再竖置或标记无效。
	var second_card_context: Dictionary = _controller._card_use_contexts[9002] as Dictionary
	if not protected_target.chained or not (second_card_context.get("excluded_target_ids", []) as Array).is_empty():
		return _fail("bingfeng_target_limit chained=%s context=%s" % [protected_target.chained, second_card_context])
	return true


## 验证准备与弃牌阶段的技能选择提交后会续接唯一阶段流程，覆盖加护自选自身和永屹额外出牌阶段两种卡死场景。
func _test_deferred_phase_choice_resumption() -> bool:
	_reset_state(2)
	# 阶段节奏；保留极短延时以断言恢复后确实登记了下一阶段，而不是让空牌堆直接推进到终局。
	_controller.game_flow_interval_seconds = 0.05
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "start"
	_controller.state.phase_index = 0
	# 加护运行时技能；安装真实准备阶段订阅，确保测试经过与对局一致的Begin选择路径。
	var jiahu: SkillDefinition = _install_single_skill(0, "jiahu")
	# 准备阶段生命周期；加护应创建本地目标选择并把阶段临时标记为choice。
	var preparation_started: bool = _controller._begin_phase_lifecycle("phaseZhunbei", 0, {"turn_number":_controller.state.turn_number}, -1)
	if jiahu == null or not preparation_started or not _controller.has_pending_card_choice() or _controller.state.current_phase != "choice":
		return _fail("jiahu_begin_choice skill=%s started=%s pending=%s phase=%s" % [jiahu, preparation_started, _controller.has_pending_card_choice(), _controller.state.current_phase])
	# 自选自身响应；这是此前会让准备阶段无法继续、游戏卡死的路径。
	if not _submit_pending_choice(0, [], [0], true):
		return false
	# 加护结果与后续阶段计时器；护盾、横置和已登记的判定阶段切换证明没有停留在start或choice死状态。
	var march: PlayerState = _controller.state.get_player(0)
	if march == null or not march.chained or march.shield != 1 or _controller.state.current_phase != "start" or _controller.game_flow_pacer == null or not _controller.game_flow_pacer.has_pending("phase_transition"):
		return _fail("jiahu_resume chained=%s shield=%d phase=%s transition=%s" % [march.chained if march != null else false, march.shield if march != null else -1, _controller.state.current_phase, _controller.game_flow_pacer.has_pending("phase_transition") if _controller.game_flow_pacer != null else false])

	# 上一场景仍未到期的准备阶段切换；取消后再重置，防止它干扰永屹的独立弃牌阶段断言。
	_controller.game_flow_pacer.cancel_all()
	_reset_state(2)
	# 阶段节奏；使用极短延时后等待一次，直接验证额外出牌阶段实际已开始。
	_controller.game_flow_interval_seconds = 0.05
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "discard"
	_controller.state.phase_index = 4
	# 永屹持有者状态；1点护盾正好满足支付额外出牌阶段费用。
	var gepard: PlayerState = _controller.state.get_player(0)
	gepard.shield = 1
	# 永屹运行时技能；安装真实弃牌阶段Begin订阅，确保确认响应经过统一恢复入口。
	var yongyi: SkillDefinition = _install_single_skill(0, "yongyi")
	# 弃牌阶段生命周期；永屹应在Begin创建确认选择并暂停当前弃牌阶段。
	var discard_started: bool = _controller._begin_phase_lifecycle("phaseDiscard", 0, {"turn_number":_controller.state.turn_number}, -1)
	if yongyi == null or not discard_started or not _controller.has_pending_card_choice() or _controller.state.current_phase != "choice":
		return _fail("yongyi_begin_choice skill=%s started=%s pending=%s phase=%s" % [yongyi, discard_started, _controller.has_pending_card_choice(), _controller.state.current_phase])
	# 确认支付护盾；这是此前额外出牌阶段无法被安排、游戏卡死的路径。
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 阶段转换等待；额外出牌阶段不经过摸牌阶段，因此短暂等待后应稳定进入新的出牌请求。
	await get_tree().create_timer(0.10, false).timeout
	# 永屹结果与额外出牌阶段；护盾已支付、额外阶段回到结束阶段标记存在，且已打开新的正式出牌请求。
	if gepard.shield != 0 or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)) or str(_controller._active_extra_play_phase_context.get("return_point", "")) != "finish" or _controller.state.current_phase != "play" or not _controller._has_active_play_choice():
		return _fail("yongyi_resume shield=%d return_finish=%s phase=%s play_choice=%s" % [gepard.shield, _controller._extra_play_phase_returns_to_finish, _controller.state.current_phase, _controller._has_active_play_choice()])
	return true


## 验证罡风可在响应窗口将黑色实体牌转化为保留花色点数的雷【杀】，材料最终进入弃牌堆。
func _test_gangfeng_response() -> bool:
	_reset_state(2)
	# 罡风运行时技能；安装到玩家技能表后核心响应候选会自动查找该转化。
	var gangfeng: SkillDefinition = GameDatabase.create_skill("gangfeng")
	gangfeng.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"gangfeng":gangfeng}}
	# 黑色响应材料；使用梅花Q验证虚拟雷【杀】继承花色与点数。
	var material: CardInstance = _add_hand_card(0, "shan", "club", 12)
	# 转化后响应牌；定义ID必须为sha_thunder，但实体UID不替代真实材料记录。
	var response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, material.uid, ["sha"])
	if response_card == null or response_card.definition_id != "sha_thunder" or response_card.suit != "club" or response_card.rank != 12 or _controller.state.get_player(0).find_hand_card(material.uid) != null or not _controller.state.discard_pile.has(material):
		return _fail("gangfeng_response card=%s discard=%s" % [response_card.to_dict() if response_card != null else {}, _controller.state.discard_pile.has(material)])
	# 黑色装备材料；白银狮子离区应卸载装备运行时、回复1点体力并把材料送入弃牌堆。
	var response_owner: PlayerState = _controller.state.get_player(0)
	response_owner.hp = 3
	# 测试防具实体；黑桃花色使其满足罡风黑色材料条件。
	var armor_material: CardInstance = CardInstance.new("baiyin", "spade", 1)
	armor_material.zone = "equipment"
	armor_material.owner_id = 0
	response_owner.equipment["armor"] = armor_material
	_controller._install_card_runtime(armor_material, 0)
	# 装备材料转化后的响应牌；成功后装备槽、运行时索引与离区回复必须同时完成。
	var equipment_response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, armor_material.uid, ["sha"])
	if equipment_response_card == null or equipment_response_card.definition_id != "sha_thunder" or response_owner.equipment.has("armor") or _controller.card_runtime_instances.has(armor_material.uid) or response_owner.hp != 4 or not _controller.state.discard_pile.has(armor_material):
		return _fail("gangfeng_equipment_response hp=%d equipment=%s runtime=%s discard=%s" % [response_owner.hp, response_owner.equipment, _controller.card_runtime_instances.has(armor_material.uid), _controller.state.discard_pile.has(armor_material)])
	return true


## 验证疾雨第1项写入雷【杀】直击目标，并验证第2项仅横置丹恒当前攻击范围内的另一名角色。
func _test_jiyu_branches() -> bool:
	_reset_state(3)
	# 疾雨运行时技能；分支恢复使用权威卡牌上下文与攻击范围查询。
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	jiyu.bind(_controller, 0)
	_controller._card_use_contexts[9101] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	# 疾雨第1项响应；目标明确选择不可响应此【杀】。
	var direct_hit_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 1, true)
	direct_hit_response.control_id = "direct_hit"
	jiyu.continue_selection({"kind":"jiyu_target_option", "target_id":1, "card_uid":9101}, direct_hit_response)
	# 雷【杀】使用上下文；二号玩家应成为唯一直击目标。
	var card_context: Dictionary = _controller._card_use_contexts[9101] as Dictionary
	if not (card_context.get("direct_hit_target_ids", []) as Array).has(1):
		return _fail("jiyu_direct_hit=%s" % card_context)
	# 疾雨第2项目标响应；三人局基础攻击范围内的三号玩家为合法“另一名角色”。
	var link_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	link_response.target_ids = [2]
	jiyu.continue_selection({"kind":"jiyu_link_other_target", "target_id":1, "card_uid":9101}, link_response)
	if not _controller.state.get_player(2).chained:
		return _fail("jiyu_link_other_not_applied")
	return true


## 验证失去护盾不影响体力也不写入伤害历史，并验证永屹额外弃牌阶段完成后才获得1点护盾。
func _test_yongyi_and_shield_semantics() -> bool:
	_reset_state(2)
	# 杰帕德权威状态；初始1点护盾用于验证SkillPlayer.loseShield独立语义。
	var gepard: PlayerState = _controller.state.get_player(0)
	gepard.shield = 1
	# 永屹运行时技能；同时登记到技能表供额外阶段完成回调定位。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	yongyi.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"yongyi":yongyi}}
	# 失去护盾前的体力与伤害历史数；执行后必须完全不变。
	var hp_before: int = gepard.hp
	# 失去护盾前的伤害历史条目数；用于证明该动作不会产生伤害事实。
	var damage_history_count_before: int = gepard.damage_history.size()
	if yongyi.get_owner_skill_player().loseShield(1, yongyi.get_owner_skill_player()) != 1 or gepard.hp != hp_before or gepard.damage_history.size() != damage_history_count_before:
		return _fail("lose_shield_semantics hp=%d shield=%d history=%d" % [gepard.hp, gepard.shield, gepard.damage_history.size()])
	# 额外弃牌阶段完成上下文；无超限手牌时阶段会同步完成并回调永屹。
	var completion_context: Dictionary = {"kind":"yongyi_extra_discard_complete", "skill_owner_id":0, "skill_id":"yongyi"}
	if not _controller.request_extra_discard_phase(0, 1, "yongyi", completion_context) or gepard.shield != 1 or not _controller._active_extra_discard_phase.is_empty():
		return _fail("yongyi_extra_discard shield=%d active=%s" % [gepard.shield, _controller._active_extra_discard_phase])
	_controller.state.current_phase = "discard"
	# 永屹弃牌阶段确认响应；支付1点护盾后应排队1个额外出牌阶段并标记其结束后直接进入结束阶段。
	var extra_play_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	yongyi.continue_selection({"kind":"yongyi_play_phase_confirm"}, extra_play_response)
	if gepard.shield != 0 or int(_controller._extra_play_phase_counts.get(0, 0)) != 1 or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)) or (_controller._extra_play_phase_return_points.get(0, []) as Array) != ["finish"]:
		return _fail("yongyi_extra_play shield=%d count=%d return_finish=%s" % [gepard.shield, int(_controller._extra_play_phase_counts.get(0, 0)), _controller._extra_play_phase_returns_to_finish])
	return true


## 验证冰封会主动把对横置队友的负收益牌转化为正收益，且疾雨在候选只有丹恒队友时无条件选第2项。
func _test_new_skill_ai_rules() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "march_7th"
	_controller.state.get_player(2).chained = true
	# 权威AI快照；对本地策略包含完整手牌与公开技能历史。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 无名杀式AI评估器；使用公开身份得到稳定忠反态度。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 对横置队友使用【杀】的负收益动作；冰封应移除原效果并加入竖置收益。
	var harmful_ally_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_definition_id":"sha", "target_ids":[2]}
	# 原【杀】基础分；对公开忠臣造成伤害应为负。
	var base_harmful_score: float = evaluator.score_action(snapshot, harmful_ally_action, 0)
	# 冰封修正分；主动转化后应严格高于原动作且为正。
	var bingfeng: SkillDefinition = GameDatabase.create_skill("bingfeng")
	bingfeng.bind(null, 0)
	# 冰封修正后的动作评分；必须体现无效负收益牌并竖置友方的组合收益。
	var converted_score: float = bingfeng.modify_ai_card_action_score(snapshot, harmful_ally_action, base_harmful_score, evaluator)
	if converted_score <= base_harmful_score or converted_score <= 0.0:
		return _fail("bingfeng_ai_conversion base=%s converted=%s" % [base_harmful_score, converted_score])
	# 疾雨静态AI技能；选项候选只含三号忠臣，其为丹恒队友。
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	jiyu.bind(null, 0)
	# 目标文字选项请求；二号反贼即使没有【闪】，也应因候选只有丹恒队友而选第2项。
	var option_request: Dictionary = {"context":{"kind":"jiyu_target_option", "target_id":1, "redirect_target_ids":[2]}}
	# 第1项AI动作；表示不可响应此【杀】。
	var direct_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"direct_hit"}}
	# 第2项AI动作；表示令丹恒横置一名范围内角色。
	var redirect_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"link_other"}}
	if jiyu.score_ai_choice(snapshot, option_request, redirect_action, evaluator) <= jiyu.score_ai_choice(snapshot, option_request, direct_action, evaluator):
		return _fail("jiyu_ai_only_ally")
	# 永屹静态AI技能；可命中敌方的【杀】应使额外出牌收益高于1点护盾。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	yongyi.bind(null, 0)
	# 永屹额外出牌确认请求；显式写入1张可用牌与可命中敌方【杀】。
	var play_request: Dictionary = {"context":{"kind":"yongyi_play_phase_confirm", "usable_card_count":1, "enemy_slash_available":true}}
	# 零牌确认动作；只有技能计算的净收益决定是否发动。
	var confirm_action: Dictionary = {"payload":{"confirmed":true}}
	if yongyi.score_ai_choice(snapshot, play_request, confirm_action, evaluator) <= 0.0:
		return _fail("yongyi_ai_extra_play")
	return true


## 向指定玩家普通手牌区加入一张测试实体；花色、点数、区域与所有者全部显式写入。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向当前测试牌堆顶部加入一张实体；数组末尾固定表示最顶层。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新牌堆实体；公共牌堆没有所属玩家。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 向当前测试弃牌堆顶部加入一张实体；数组末尾固定表示最顶层。
func _add_discard_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新弃牌实体；弃牌堆没有所属玩家。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "discard_pile"
	card.owner_id = -1
	_controller.state.discard_pile.append(card)
	return card


## 为指定玩家安装一个运行时技能实例；测试需要通过真实时机订阅复现阶段选择与恢复流程。
func _install_single_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 新技能实例；技能目录缺失时返回null并交由调用方报告具体测试场景。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	_controller.skill_instances_by_player[player_id] = {skill_id:skill}
	skill.install()
	return skill


## 为当前统一选择请求提交目标或确认结果；测试通过正式PlayerAction入口覆盖事件运行时与阶段恢复链。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool) -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；卡牌、目标和确认状态均显式填写，保持与真实界面提交协议一致。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d" % [actor_id, request_id])
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("NEW_CHARACTER_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
