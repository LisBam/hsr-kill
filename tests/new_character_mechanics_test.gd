extends Node

## 新武将机制专项回归。覆盖规则牌名、武将引用、额外阶段恢复、临时牌名、嵌套技能结算及新技能的核心AI分支。

## 武将牌可复用场景；用真实场景结构验证横置灰白线状态不会改变牌面变换或全局包围矩形。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 通用选牌面板场景；用真实卡牌输入节点验证暗置候选与牌堆排序拖拽释放均不会绕过交互边界。
const CARD_SELECTION_PANEL_SCENE: PackedScene = preload("res://scenes/components/card_selection_panel.tscn")

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
	if not _test_sushang_guinaifen_metadata():
		return
	if not _test_metadata_and_rule_names():
		return
	if not _test_expanded_character_metadata():
		return
	if not _test_feiyan_preparation_phase_virtual_use():
		return
	if not await _test_feiyan_main_phase_conversion():
		return
	if not _test_named_card_gain_and_hand_view_as():
		return
	if not _test_lushi_mingchen_deferred_settlement():
		return
	if not _test_mingchen_turn_window_and_lockout():
		return
	if not _test_mingchen_dying_peach_continuation():
		return
	if not _test_mingchen_last_hand_response_continuation():
		return
	if not _test_mingchen_guanshi_cost_continuation():
		return
	if not _test_mingchen_recast_continuation():
		return
	if not _test_damage_timing_choice_continuation():
		return
	if not _test_turn_start_nested_skill_continuation():
		return
	if not _test_huanyang_and_sefu():
		return
	if not _test_huanfa_extra_play_phase_completion():
		return
	if not _test_dead_huanfa_owner_cannot_trigger():
		return
	if not await _test_character_card_link_overlay():
		return
	if not _test_jiahu_and_bingfeng():
		return
	if not await _test_deferred_phase_choice_resumption():
		return
	if not _test_gangfeng_response():
		return
	if not _test_conversion_material_target_rules():
		return
	if not _test_jiyu_branches():
		return
	if not _test_jiyu_all_slash_ai_priority():
		return
	if not _test_gangfeng_respects_slash_play_limit():
		return
	if not _test_ai_active_skill_progress_recovery():
		return
	if not _test_ai_choice_fallback_integrity():
		return
	if not _test_himeko_card_use_linghang_choice_resumption():
		return
	if not _test_yongyi_and_shield_semantics():
		return
	if not _test_new_skill_ai_rules():
		return
	if not _test_hsr_character_metadata_and_rule_catalog():
		return
	if not await _test_out_of_game_pile_arrangement_and_ui():
		return
	if not await _test_card_selection_panel_disabled_cards_and_arrangement_drag():
		return
	if not await _test_target_zone_prompt_highlight():
		return
	if not _test_misha_and_alan_skills():
		return
	if not await _test_aisida_heita_xiluwa_skills():
		return
	if not await _test_moze_marks_and_out_of_game_skills():
		return
	if not _test_shanqing_suit_effects():
		return
	if not _test_jianshi_xifa_judgment_continuation():
		return
	if not _test_bagua_xifa_async_response_continuation():
		return
	if not _test_delayed_trick_xifa_async_judgment():
		return
	if not _test_xifa_partial_draw_pile_replenishment_and_opposing_ai():
		return
	if not _test_touxia_turn_discard_history():
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
	# 专项场景隔离：取消上一场景残留的流程延时与出牌请求标记；不改动 game_flow_interval_seconds，由各场景自行设置。
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
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
	_controller._active_extra_discard_phase.clear()
	_controller._extra_play_phase_counts.clear()
	_controller._extra_play_phase_returns_to_finish.clear()
	_controller._extra_play_phase_return_points.clear()
	_controller._active_extra_play_phase_context.clear()
	_controller._main_phase_play_conversions.clear()
	_controller._active_converted_play_phase_context.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._rule_continuations.reset()
	_controller._pending_damage_finalizations.clear()
	_controller._cards_used_this_turn_by_player.clear()
	_controller._started_phase_lifecycles.clear()
	_controller._pending_finish_turn_player_id = -1
	_controller._clear_pending_judgment_request()
	_controller._judgment_flow_in_progress = false
	_controller._judgment_resume_needs_result_pause = false
	# 旧场景的AI策略与异步令牌；每个专项场景从无控制者、无待执行任务状态开始，避免前一断言的计时器进入新状态。
	_controller.ai_coordinator._policies.clear()
	_controller._ai_drive_token += 1
	_controller._scheduled_ai_drive_token = -1
	_controller._scheduled_ai_choice_request_id = -1
	_controller._ai_choice_submit_failures.clear()


## 核对素裳、桂乃芬的稳定资料、技能顺序与四段玩家可见技能原文。
func _test_sushang_guinaifen_metadata() -> bool:
	# 素裳定义；仙舟联盟女性、4点体力与双技能顺序必须保持稳定。
	var sushang: Dictionary = GameDatabase.get_character("sushang")
	# 桂乃芬定义；仙舟联盟女性、3点体力与双技能顺序必须保持稳定。
	var guinaifen: Dictionary = GameDatabase.get_character("guinaifen")
	if str(sushang.get("display_name", "")) != "素裳" or str(sushang.get("gender", "")) != "female" or str(sushang.get("faction", "")) != "xianzhou" or int(sushang.get("max_hp", 0)) != 4 or (sushang.get("skills", []) as Array) != ["jianshi", "shanqing"]:
		return _fail("sushang_metadata=%s" % sushang)
	if str(guinaifen.get("display_name", "")) != "桂乃芬" or str(guinaifen.get("gender", "")) != "female" or str(guinaifen.get("faction", "")) != "xianzhou" or int(guinaifen.get("max_hp", 0)) != 3 or (guinaifen.get("skills", []) as Array) != ["xifa", "touxia"]:
		return _fail("guinaifen_metadata=%s" % guinaifen)
	# 技能原文映射；任何标点、数值、花色顺序或语句顺序变化都应由专项测试立即报告。
	var expected_descriptions: Dictionary = {
		"jianshi":"当你使用【杀】造成伤害时，你可进行判定：若判定结果为红色，此伤害+1。",
		"shanqing":"你可将两张牌当【杀】使用，这些牌中的每种花色使此【杀】获得对应效果：红桃，造成伤害后回复等量的体力值；方块，使用时你摸一张牌；黑桃，此【杀】无距离限制；梅花，使用时你弃置目标的一张牌。每回合限一次。",
		"xifa":"一名角色进行判定前，你可观看牌堆顶的两张牌，然后将这些牌以任意顺序放回牌堆顶与牌堆底。",
		"touxia":"其他角色的回合结束时，你可进行判定，然后你可以获得弃牌堆中一张于此回合出牌阶段进入弃牌堆、且花色与判定结果相同的牌，然后当前回合的角色摸一张牌。每轮限一次。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能 ID；自动目录索引必须返回完整静态说明。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("sushang_guinaifen_description=%s" % skill_id)
	return true


## 验证属性【杀】的规则名与显示名分离，并核对三名武将的体力、势力和技能引用。
func _test_metadata_and_rule_names() -> bool:
	# 火【杀】与雷【杀】定义；rule_name用于规则称呼，original_name与custom_name继续提供两字牌面。
	var fire_slash: Dictionary = GameDatabase.get_card("sha_fire")
	# 雷【杀】定义；与火【杀】共同校验规则名和牌面显示名分离。
	var thunder_slash: Dictionary = GameDatabase.get_card("sha_thunder")
	if str(fire_slash.get("rule_name", "")) != "杀" or str(thunder_slash.get("rule_name", "")) != "杀" or str(fire_slash.get("original_name", "")) != "火杀" or str(thunder_slash.get("custom_name", "")) != "雷杀":
		return _fail("attribute_slash_names fire=%s thunder=%s" % [fire_slash, thunder_slash])
	# 寒鸦牌名字数规则；属性【杀】虽然牌面显示两个字，实际规则牌名仍只有一个字。
	if _controller.get_card_original_name_length("sha_fire") != 1 or _controller.get_card_original_name_length("sha_thunder") != 1:
		return _fail("attribute_slash_rule_length")
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
	if not GameDatabase.get_skill("six_phased_ice_sample").is_empty() or not GameDatabase.get_skill("cloud_piercer_sample").is_empty() or not GameDatabase.get_skill("trailblaze_sample").is_empty() or not GameDatabase.get_character("trailblazer").is_empty():
		return _fail("placeholder_content_still_registered")
	return true


## 核对娜塔莎、寒鸦、雪衣的稳定资料与技能原文，并确认三个旧占位武将已经退出自动索引。
func _test_expanded_character_metadata() -> bool:
	# 娜塔莎定义；贝洛伯格女性、3点体力与双技能顺序必须保持稳定。
	var natasha: Dictionary = GameDatabase.get_character("natasha")
	# 寒鸦定义；仙舟联盟女性、3点体力与双技能顺序必须保持稳定。
	var hanya: Dictionary = GameDatabase.get_character("hanya")
	# 雪衣定义；内部ID按设计固定为xveyi，基础体力为4。
	var xveyi: Dictionary = GameDatabase.get_character("xveyi")
	# 虎克定义；贝洛伯格女性、3点体力与双技能顺序必须保持稳定。
	var huke: Dictionary = GameDatabase.get_character("huke")
	# 貊泽定义；仙舟联盟男性、2点体力与三项离场技顺序必须保持稳定。
	var moze: Dictionary = GameDatabase.get_character("moze")
	if str(natasha.get("gender", "")) != "female" or str(natasha.get("faction", "")) != "beiluoboge" or int(natasha.get("max_hp", 0)) != 3 or (natasha.get("skills", []) as Array) != ["yaoli", "huanfa"]:
		return _fail("natasha_metadata=%s" % natasha)
	if str(hanya.get("gender", "")) != "female" or str(hanya.get("faction", "")) != "xianzhou" or int(hanya.get("max_hp", 0)) != 3 or (hanya.get("skills", []) as Array) != ["mingchen", "lushi"]:
		return _fail("hanya_metadata=%s" % hanya)
	if str(xveyi.get("display_name", "")) != "雪衣" or str(xveyi.get("gender", "")) != "female" or str(xveyi.get("faction", "")) != "xianzhou" or int(xveyi.get("max_hp", 0)) != 4 or (xveyi.get("skills", []) as Array) != ["huanyang", "shefu"]:
		return _fail("xveyi_metadata=%s" % xveyi)
	if str(huke.get("display_name", "")) != "虎克" or str(huke.get("gender", "")) != "female" or str(huke.get("faction", "")) != "beiluoboge" or int(huke.get("max_hp", 0)) != 3 or (huke.get("skills", []) as Array) != ["wuxie_2", "feiyan"]:
		return _fail("huke_metadata=%s" % huke)
	if str(moze.get("display_name", "")) != "貊泽" or str(moze.get("gender", "")) != "male" or str(moze.get("faction", "")) != "xianzhou" or int(moze.get("max_hp", 0)) != 2 or (moze.get("skills", []) as Array) != ["youfeng", "lvexi", "yingchu"]:
		return _fail("moze_metadata=%s" % moze)
	# 六项技能说明；玩家可见文本必须逐字保持机制设计原文。
	var expected_descriptions: Dictionary = {
		"yaoli":"出牌阶段限一次，你可交给一名角色一张红色手牌，然后此牌视为【药】直到离开其手牌区。",
		"huanfa":"一名角色的回合结束时，若本回合内其使用过【药】，你可令其执行一个额外的出牌阶段。每轮限一次。",
		"mingchen":"锁定技，当你于回合内失去最后的手牌后，你令一名角色从牌堆或弃牌堆中获得一张【无中生有】。若该角色不为你，你令其对其造成1点雷属性伤害，并令此技能失效直到回合结束。",
		"lushi":"出牌阶段，你可弃置两张牌名字数相同的牌，然后摸一张牌。",
		"huanyang":"锁定技，当你对距离为1以内的角色造成伤害时，你回复1点体力。",
		"shefu":"锁定技，当你于一回合内首次使用牌造成伤害后，你令一名角色从牌堆中获得一张牌名字数与此牌相同的牌。若该角色为目标角色，你弃置其装备区内的一张牌。",
		"wuxie_2":"当你造成伤害后，你可令受到伤害的角色回复1点体力。",
		"feiyan":"准备阶段，你可以视为使用一张【火攻】，若此牌造成伤害，你摸三张牌，且本回合内你的所有主要阶段都变为出牌阶段。",
		"youfeng":"离场技，锁定技，每轮开始时，你弃置一名其他角色的一张牌并令其获得“猎物”标记，然后若你未处于离场状态，你离场；若你已处于离场状态，你失去1点体力。",
		"lvexi":"离场技，锁定技，你计算与拥有“猎物”标记的角色距离为1，且其不可响应你使用的牌。当拥有“猎物”标记的角色受到伤害后，若你处于离场状态，你返场并对其造成1点伤害。当拥有“猎物”标记的角色死亡时，你摸两张牌并返场。",
		"yingchu":"离场技，锁定技，当你上家的回合结束时，若你处于离场状态，你返场；该回合结束时，你再次离场。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能ID；用于自动索引中读取对应说明。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("expanded_skill_description=%s" % skill_id)
	if not GameDatabase.get_character("jingyuan").is_empty() or not GameDatabase.get_character("kafka").is_empty() or not GameDatabase.get_character("welt").is_empty():
		return _fail("removed_placeholder_character_registered")
	return true


## 验证飞焰在准备阶段能够枚举火攻目标并通过最终虚拟牌校验，不会被出牌阶段限制提前拦截。
func _test_feiyan_preparation_phase_virtual_use() -> bool:
	_reset_state(2)
	_controller.state.current_phase = "preparation"
	_controller.state.current_player_id = 0
	# 火攻目标手牌；目标至少拥有一张手牌才符合【火攻】的标准目标规则。
	var target_hand_card: CardInstance = CardInstance.new("sha", "heart", 7)
	target_hand_card.owner_id = 1
	target_hand_card.zone = "hand"
	_controller.state.players[1].hand.append(target_hand_card)
	# 飞焰准备阶段覆写；只解除阶段限制，目标模式与其他卡牌规则仍由统一服务校验。
	var rule_overrides: Dictionary = {"ignore_phase_limit":true}
	# 准备阶段合法目标；敌方拥有手牌时必须出现在询问候选中。
	var legal_target_ids: Array[int] = _controller.card_rules.list_legal_virtual_targets(0, "huogong", rule_overrides)
	if not legal_target_ids.has(1):
		return _fail("feiyan_preparation_targets=%s" % [legal_target_ids])
	if not _controller.card_rules.validate_virtual_use(0, "huogong", [1], rule_overrides).is_empty():
		return _fail("feiyan_preparation_virtual_validation")
	# 飞焰技能实例；直接恢复已确认目标以实际覆盖Object.call到Array[int]端口的运行时类型检查。
	var feiyan: SkillDefinition = GameDatabase.create_skill("feiyan")
	feiyan.bind(_controller, 0)
	# 已确认的单目标响应；目标数组字段本身是标准强类型Array[int]。
	var response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	response.target_ids = [1]
	if not feiyan.continue_selection({"kind":"feiyan_target"}, response):
		return _fail("feiyan_runtime_virtual_use_not_consumed")
	if not _controller.has_pending_card_choice():
		return _fail("feiyan_runtime_virtual_use_did_not_start_huogong")
	return true


## 验证飞焰把判定、摸牌、正常出牌与弃牌四个主要阶段直接依次转换为普通出牌阶段，不产生跳过或额外阶段日志。
func _test_feiyan_main_phase_conversion() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "start"
	_controller.state.phase_index = 0
	# 本次阶段日志；用于确认转换流程只出现四次普通出牌阶段，不出现额外阶段或弃牌阶段。
	var phase_logs: Array[String] = []
	var log_callback: Callable = func(message: String) -> void: phase_logs.append(message)
	_controller.log_added.connect(log_callback)
	if not _controller.convert_current_turn_main_phases_to_play(0, "test_feiyan"):
		_controller.log_added.disconnect(log_callback)
		return _fail("feiyan_conversion_registration")
	# 第一段原判定阶段；应直接进入普通phaseUse，且没有任何额外阶段排队或跳过标记。
	_controller._enter_judgment_phase(0)
	if _controller.state.current_phase != "play" or str(_controller._active_converted_play_phase_context.get("original_phase", "")) != "judgment" or not _controller._extra_play_phase_counts.is_empty() or not _controller.state.get_player(0).skipped_phases.is_empty():
		_controller.log_added.disconnect(log_callback)
		return _fail("feiyan_judgment_conversion context=%s extra=%s skipped=%s" % [_controller._active_converted_play_phase_context, _controller._extra_play_phase_counts, _controller.state.get_player(0).skipped_phases])
	# 依次结束原判定与原摸牌转换段；每段转场后都应建立新的普通出牌阶段生命周期。
	_controller._cancel_active_play_choice("feiyan_test_judgment")
	_controller._end_play_phase(0)
	await get_tree().process_frame
	if str(_controller._active_converted_play_phase_context.get("original_phase", "")) != "draw":
		_controller.log_added.disconnect(log_callback)
		return _fail("feiyan_draw_conversion=%s" % [_controller._active_converted_play_phase_context])
	_controller._cancel_active_play_choice("feiyan_test_draw")
	_controller._end_play_phase(0)
	await get_tree().process_frame
	# 第三段本来就是正常出牌阶段，因此没有转换上下文，但仍是四段序列中的独立普通阶段。
	if _controller.state.current_phase != "play" or not _controller._active_converted_play_phase_context.is_empty():
		_controller.log_added.disconnect(log_callback)
		return _fail("feiyan_normal_play_phase=%s/%s" % [_controller.state.current_phase, _controller._active_converted_play_phase_context])
	_controller._cancel_active_play_choice("feiyan_test_play")
	_controller._end_play_phase(0)
	await get_tree().process_frame
	# 第四段原弃牌阶段；应再次作为普通出牌阶段开始，证明不会进入实际弃牌主体。
	if str(_controller._active_converted_play_phase_context.get("original_phase", "")) != "discard":
		_controller.log_added.disconnect(log_callback)
		return _fail("feiyan_discard_conversion=%s" % [_controller._active_converted_play_phase_context])
	# 阶段日志语义；四段都叫“出牌阶段”，不能出现“额外”“跳过”或真实弃牌阶段开始。
	var play_begin_count: int = phase_logs.count("出牌阶段开始。")
	for log_message: String in phase_logs:
		if log_message.contains("额外出牌阶段") or log_message.contains("跳过判定阶段") or log_message.contains("跳过摸牌阶段") or log_message.contains("跳过弃牌阶段") or log_message == "弃牌阶段开始。":
			_controller.log_added.disconnect(log_callback)
			return _fail("feiyan_phase_log=%s" % [phase_logs])
	_controller._cancel_active_play_choice("feiyan_test_cleanup")
	_controller.log_added.disconnect(log_callback)
	if play_begin_count != 4:
		return _fail("feiyan_play_phase_count=%d logs=%s" % [play_begin_count, phase_logs])
	return true


## 验证指定牌先检索牌堆、缺失后检索弃牌堆的顶部匹配顺序，并验证【药】在离开手牌区时恢复原牌名。
func _test_named_card_gain_and_hand_view_as() -> bool:
	_reset_state(2)
	# 本项测试捕获的公开日志；仅用于确认定向获得牌时不会泄露具体牌名。
	var emitted_logs: Array[String] = []
	_controller.log_added.connect(func(message: String) -> void: emitted_logs.append(message))
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
	# 定向获得后的隐藏信息；弃牌堆公开知识也必须重置为仅获得者知晓，日志不得包含具体牌名。
	if first_gain.shown or second_gain.shown or first_gain.known_to != [0] or second_gain.known_to != [0] or emitted_logs.any(func(log_line: String) -> bool: return log_line.contains("无中生有")):
		return _fail("named_gain_visibility first=%s second=%s logs=%s" % [first_gain.to_dict(), second_gain.to_dict(), emitted_logs])
	# 交给其他角色的红色实体；进入目标手牌后临时视为【桃/药】。
	var gifted_card: CardInstance = _add_hand_card(0, "sha", "heart", 5)
	if not _controller.transfer_hand_card_as(0, 1, gifted_card.uid, "tao", "yaoli") or gifted_card.definition_id != "tao" or gifted_card.hand_view_as_original_definition_id != "sha" or _controller.state.get_player(1).find_hand_card(gifted_card.uid) == null:
		return _fail("hand_view_as_gift=%s" % gifted_card.to_dict())
	# 视为牌快照；表现层必须得到原牌定义 ID，才能在不改变逻辑牌结算的前提下保留实体牌面名称。
	var gifted_snapshot: Dictionary = gifted_card.to_dict()
	if str(gifted_snapshot.get("original_definition_id", "")) != "sha":
		return _fail("hand_view_as_snapshot=%s" % gifted_snapshot)
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


## 验证冥谶只在持有者自己的回合内触发，选择其他角色后本回合失效，并会在回合结束后恢复触发资格。
func _test_mingchen_turn_window_and_lockout() -> bool:
	_reset_state(2)
	# 冥谶持有者；通过真实失去普通手牌事件验证回合归属与临时失效，而非直接改写技能内部标记。
	var hanya: PlayerState = _controller.state.get_player(0)
	hanya.character_id = "hanya"
	var mingchen: SkillDefinition = _install_single_skill(0, "mingchen")
	# 回合外最后手牌；当前行动者为另一名角色时不得建立冥谶目标选择。
	_controller.state.current_player_id = 1
	var out_of_turn_card: CardInstance = _add_hand_card(0, "shan", "spade", 2)
	if mingchen == null or not _controller.discard_card_from_hand(0, out_of_turn_card.uid) or _controller.has_pending_card_choice():
		return _fail("mingchen_out_of_turn_trigger skill=%s pending=%s" % [mingchen, _controller._pending_card_choice])
	# 回到寒鸦自己的回合；失去最后手牌后必须创建强制目标选择。
	_controller.state.current_player_id = 0
	var in_turn_card: CardInstance = _add_hand_card(0, "tao", "heart", 3)
	_add_draw_pile_card("wuzhong", "diamond", 12)
	if not _controller.discard_card_from_hand(0, in_turn_card.uid) or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target":
		return _fail("mingchen_in_turn_trigger pending=%s" % [_controller._pending_card_choice])
	# 选择其他角色；该角色获得无中生有并对自身造成1点雷属性伤害，冥谶立即失效至回合结束。
	if not _submit_pending_choice(0, [], [1], true) or _controller.state.get_player(1).hp != 3 or not bool(mingchen.get("_invalid_until_turn_end")):
		return _fail("mingchen_other_target_lockout hp=%d invalid=%s" % [_controller.state.get_player(1).hp, mingchen.get("_invalid_until_turn_end")])
	# 同一回合再次失去最后手牌；临时失效期间不能重复创建目标选择。
	var locked_out_card: CardInstance = _add_hand_card(0, "shan", "club", 4)
	if not _controller.discard_card_from_hand(0, locked_out_card.uid) or _controller.has_pending_card_choice():
		return _fail("mingchen_lockout_retrigger pending=%s" % [_controller._pending_card_choice])
	# 持有者回合完整结束后临时失效清除；再次失去最后手牌应重新建立同一锁定技选择。
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	var next_turn_card: CardInstance = _add_hand_card(0, "shan", "club", 5)
	if bool(mingchen.get("_invalid_until_turn_end")) or not _controller.discard_card_from_hand(0, next_turn_card.uid) or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target":
		return _fail("mingchen_lockout_reset invalid=%s pending=%s" % [mingchen.get("_invalid_until_turn_end"), _controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [0], true):
		return false
	return true


## 验证救援者用最后一张【桃】触发冥谶时先完成技能选择，再从已消费响应准确恢复桃与濒死结算。
func _test_mingchen_dying_peach_continuation() -> bool:
	_reset_state(3)
	# 冥谶持有者；当前回合从0号开始询问，使其成为首名实际救援者。
	var hanya: PlayerState = _controller.state.get_player(0)
	hanya.character_id = "hanya"
	# 待救目标；0点体力且仍存活，进入求桃流程后必须保持濒死直至桃真正恢复。
	var dying_target: PlayerState = _controller.state.get_player(1)
	dying_target.hp = 0
	# 冥谶异己目标；技能选择完成时先获得牌并对自己造成固定1点雷属性伤害，再允许外层桃继续救援。
	var mingchen_target: PlayerState = _controller.state.get_player(2)
	# 冥谶实例；通过真实loseAfter时机复现最后手牌响应产生的嵌套目标选择。
	var mingchen: SkillDefinition = _install_single_skill(0, "mingchen")
	# 唯一救援手牌；消费后普通手牌归零并触发冥谶。
	var peach: CardInstance = _add_hand_card(0, "tao", "heart", 3)
	# 冥谶取得的指定牌；位于牌堆顶，技能目标选择完成后先于桃后续结算进入手牌。
	var mingchen_gain_card: CardInstance = _add_draw_pile_card("wuzhong", "diamond", 12)
	if mingchen == null:
		return _fail("mingchen_dying_skill_missing")
	_controller._resolve_dying(1, -1)
	# 初始救援请求；必须属于0号玩家并包含唯一桃实体。
	var dying_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((dying_choice.get("context", {}) as Dictionary).get("kind", "")) != "dying_response" or int(dying_choice.get("chooser_id", -1)) != 0:
		return _fail("mingchen_dying_initial_choice=%s" % dying_choice)
	if not _submit_pending_choice(0, [peach.uid], [], true):
		return false
	# 桃实体已经消费，但回复必须等待冥谶完成；续接栈精确保留一次救援后半段。
	var mingchen_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((mingchen_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target" or dying_target.hp != 0 or not dying_target.dying or _controller._rule_continuations.size() != 1 or not _controller.state.discard_pile.has(peach):
		return _fail("mingchen_dying_interrupted hp=%d dying=%s continuations=%s" % [dying_target.hp, dying_target.dying, _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(0, [], [2], true):
		return false
	# 冥谶先让异己获得无中生有并受到1点自伤，随后原桃只应用一次并令目标脱离濒死；所有普通续接必须完全排空。
	if dying_target.hp != 1 or dying_target.dying or _controller.state.dying_queue.has(1) or mingchen_target.hp != 3 or not mingchen_target.hand.has(mingchen_gain_card) or _controller._rule_continuations.has_pending() or _controller.has_pending_card_choice():
		return _fail("mingchen_dying_complete hp=%d dying=%s mingchen_target_hp=%d hand=%d continuations=%s" % [dying_target.hp, dying_target.dying, mingchen_target.hp, mingchen_target.hand.size(), _controller._rule_continuations.to_array()])
	return true


## 验证目标打出最后一张【闪】触发冥谶时，杀响应结果在技能完成后继续且不会错误受到伤害。
func _test_mingchen_last_hand_response_continuation() -> bool:
	_reset_state(3)
	_controller.state.current_player_id = 0
	# 冥谶持有者与【杀】目标；等待期间保持4点体力用于判断闪是否真正生效。
	var hanya: PlayerState = _controller.state.get_player(0)
	hanya.character_id = "hanya"
	# 真实冥谶实例；由最后一张闪离开手牌区时创建强制目标选择。
	var mingchen: SkillDefinition = _install_single_skill(0, "mingchen")
	# 唯一响应手牌；提交后实体进入弃牌堆，但父杀必须等待冥谶选择再读取成功结果。
	var dodge_card: CardInstance = _add_hand_card(0, "shan", "diamond", 2)
	# 攻击者使用的普通杀；通过完整CardUseEvent创建标准slash_response请求。
	var slash_card: CardInstance = _add_hand_card(1, "sha", "spade", 7)
	# 冥谶取得的无中生有；响应插入完成后进入技能持有者手牌。
	var mingchen_gain_card: CardInstance = _add_draw_pile_card("wuzhong", "club", 6)
	if mingchen == null:
		return _fail("mingchen_response_skill_missing")
	_controller._execute_card_use(1, slash_card, [0])
	# 初始闪响应；必须属于0号目标且使用标准杀响应kind。
	var response_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((response_choice.get("context", {}) as Dictionary).get("kind", "")) != "slash_response" or int(response_choice.get("chooser_id", -1)) != 0:
		return _fail("mingchen_response_initial_choice=%s" % response_choice)
	if not _submit_pending_choice(0, [dodge_card.uid], [], true):
		return false
	# 闪已移动但父杀尚未读取结果；冥谶选择和一条卡牌响应续接必须同时存在。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target" or hanya.hp != 4 or _controller._rule_continuations.size() != 1:
		return _fail("mingchen_response_interrupted hp=%d continuations=%s" % [hanya.hp, _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(0, [], [0], true):
		return false
	# 冥谶完成后闪结果只恢复一次，杀进入弃牌堆且目标不受伤；全部续接与普通请求均已排空。
	if hanya.hp != 4 or not hanya.hand.has(mingchen_gain_card) or not _controller.state.discard_pile.has(dodge_card) or not _controller.state.discard_pile.has(slash_card) or _controller._rule_continuations.has_pending() or _controller.has_pending_card_choice():
		return _fail("mingchen_response_complete hp=%d hand=%d continuations=%s" % [hanya.hp, hanya.hand.size(), _controller._rule_continuations.to_array()])
	return true


## 验证贯石斧弃置最后两张手牌触发冥谶时，武器费用完成后仍能恢复原【闪】结果并继续造成伤害。
func _test_mingchen_guanshi_cost_continuation() -> bool:
	_reset_state(3)
	# 贯石斧持有者与冥谶持有者；支付两张费用后普通手牌归零。
	var hanya: PlayerState = _controller.state.get_player(0)
	hanya.character_id = "hanya"
	# 目标角色；先打出闪保持4点体力，贯石斧续接完成后应受到固定1点普通伤害。
	var target: PlayerState = _controller.state.get_player(1)
	# 冥谶实例；由贯石斧第二张费用离开手牌区时创建目标选择。
	var mingchen: SkillDefinition = _install_single_skill(0, "mingchen")
	# 贯石斧实体；装备区本身不属于两张手牌费用，不会因发动而离区。
	var guanshi_card: CardInstance = CardInstance.new("guanshi", "diamond", 5)
	guanshi_card.zone = "equipment"
	guanshi_card.owner_id = 0
	hanya.equipment["weapon"] = guanshi_card
	# 贯石斧第一张费用；两张费用都来自普通手牌并在同一选择中提交。
	var first_cost: CardInstance = _add_hand_card(0, "tao", "heart", 4)
	# 贯石斧第二张费用；消费后触发失去最后手牌时机。
	var second_cost: CardInstance = _add_hand_card(0, "wuxie", "spade", 11)
	# 目标实际打出的闪；先令原杀进入被闪抵消后的贯石斧费用步骤。
	var dodge_card: CardInstance = _add_hand_card(1, "shan", "diamond", 2)
	# 攻击者使用的杀；离开手牌后只剩上方两张费用牌。
	var slash_card: CardInstance = _add_hand_card(0, "sha", "club", 7)
	# 冥谶取得的无中生有；技能选择完成后再恢复贯石斧伤害。
	var mingchen_gain_card: CardInstance = _add_draw_pile_card("wuzhong", "heart", 12)
	if mingchen == null:
		return _fail("mingchen_guanshi_skill_missing")
	_controller._execute_card_use(0, slash_card, [1])
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "slash_response" or not _submit_pending_choice(1, [dodge_card.uid], [], true):
		return _fail("mingchen_guanshi_dodge")
	# 贯石斧费用请求；当前武器本体不能进入候选，界面因此也不会将它自动选为第一张弃牌费用。
	var guanshi_cost_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	# 费用候选UID；应且只应包含两张普通手牌。
	var guanshi_cost_candidate_uids: Array[int] = []
	# 当前候选快照；测试只提取稳定UID，不依赖牌面文本或区域排序。
	for candidate_variant: Variant in guanshi_cost_choice.get("candidates", []) as Array:
		guanshi_cost_candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	guanshi_cost_candidate_uids.sort()
	# 期望候选UID；排序后比较可避免候选区域枚举顺序影响规则断言。
	var expected_guanshi_cost_uids: Array[int] = [first_cost.uid, second_cost.uid]
	expected_guanshi_cost_uids.sort()
	if str((guanshi_cost_choice.get("context", {}) as Dictionary).get("kind", "")) != "guanshi_cost" or guanshi_cost_candidate_uids != expected_guanshi_cost_uids or guanshi_cost_candidate_uids.has(guanshi_card.uid):
		return _fail("mingchen_guanshi_candidates=%s weapon=%d" % [guanshi_cost_candidate_uids, guanshi_card.uid])
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "guanshi_cost" or not _submit_pending_choice(0, [first_cost.uid, second_cost.uid], [], true):
		return _fail("mingchen_guanshi_cost")
	# 两张费用已弃置但伤害仍等待冥谶；栈内同时保留武器阶段与父目标收尾且目标体力尚未改变。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target" or target.hp != 4 or _controller._rule_continuations.size() != 2:
		return _fail("mingchen_guanshi_interrupted hp=%d continuations=%s" % [target.hp, _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(0, [], [0], true):
		return false
	# 冥谶结束后先恢复贯石斧令杀命中，再完成父目标；费用、闪和杀都只移动一次。
	if target.hp != 3 or hanya.get_weapon() != guanshi_card or not hanya.hand.has(mingchen_gain_card) or not _controller.state.discard_pile.has(first_cost) or not _controller.state.discard_pile.has(second_cost) or not _controller.state.discard_pile.has(dodge_card) or not _controller.state.discard_pile.has(slash_card) or _controller._rule_continuations.has_pending() or _controller.has_pending_card_choice():
		return _fail("mingchen_guanshi_complete hp=%d continuations=%s" % [target.hp, _controller._rule_continuations.to_array()])
	return true


## 验证重铸最后手牌触发冥谶时，固定摸1张牌会在技能完整结算后继续且不会越过牌堆顶顺序。
func _test_mingchen_recast_continuation() -> bool:
	_reset_state(2)
	# 冥谶持有者；只有一张可重铸手牌，离区后必然满足最后手牌条件。
	var hanya: PlayerState = _controller.state.get_player(0)
	hanya.character_id = "hanya"
	# 真实冥谶实例；重铸使用公开通用端口，不依赖录事的专用延后逻辑。
	var mingchen: SkillDefinition = _install_single_skill(0, "mingchen")
	# 被重铸的铁索连环；重铸规则本身仍保持弃1摸1。
	var recast_card: CardInstance = _add_hand_card(0, "tiesuo", "club", 12)
	# 重铸后续摸牌；先放入牌堆，使其位于冥谶目标牌下方。
	var recast_draw_card: CardInstance = _add_draw_pile_card("shan", "heart", 6)
	# 冥谶优先取得的无中生有；当前位于牌堆最顶层。
	var mingchen_gain_card: CardInstance = _add_draw_pile_card("wuzhong", "diamond", 9)
	if mingchen == null or not _controller.recast_hand_card(0, recast_card.uid):
		return _fail("mingchen_recast_start")
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target" or not hanya.hand.is_empty() or _controller._rule_continuations.size() != 1:
		return _fail("mingchen_recast_interrupted hand=%d continuations=%s" % [hanya.hand.size(), _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(0, [], [0], true):
		return false
	# 技能先取得牌堆顶无中生有，重铸续接随后摸到下一张闪；重铸实体保持在弃牌堆。
	if not hanya.hand.has(mingchen_gain_card) or not hanya.hand.has(recast_draw_card) or not _controller.state.discard_pile.has(recast_card) or _controller._rule_continuations.has_pending() or _controller.has_pending_card_choice():
		return _fail("mingchen_recast_complete hand=%d continuations=%s" % [hanya.hand.size(), _controller._rule_continuations.to_array()])
	return true


## 验证damageSource中的摄伏多步选择完成后才进入damageAfter中的永屹选择，两个时机不会互相覆盖。
func _test_damage_timing_choice_continuation() -> bool:
	_reset_state(3)
	# 伤害来源的摄伏实例；首次使用牌造成伤害后创建强制获牌目标选择。
	var sefu: SkillDefinition = GameDatabase.create_skill("shefu")
	# 伤害目标的永屹实例；体力实际减少后在damageAfter创建可取消确认选择。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	if sefu == null or yongyi == null:
		return _fail("damage_timing_skills_missing")
	sefu.bind(_controller, 0)
	yongyi.bind(_controller, 1)
	_controller.skill_instances_by_player = {0:{"shefu":sefu}, 1:{"yongyi":yongyi}}
	sefu.install()
	yongyi.install()
	# 摄伏按一字【杀】取得的牌；选择安全的三号角色可避免额外装备弃置步骤干扰时机顺序断言。
	var sefu_gain_card: CardInstance = _add_draw_pile_card("shan", "heart", 8)
	_controller.damage(0, 1, 1, "normal", "sha")
	# 第一窗口必须仍是来源时机的摄伏；永屹尚未发布，伤害尾部只保留一条从damageEnd开始的续接。
	var source_timing_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((source_timing_choice.get("context", {}) as Dictionary).get("kind", "")) != "sefu_gain_target" or _controller.state.get_player(1).hp != 3 or _controller._rule_continuations.size() != 1:
		return _fail("damage_source_timing=%s continuations=%s" % [source_timing_choice, _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(0, [], [2], true):
		return false
	# 摄伏完成并恢复damageEnd后才允许damageAfter发布永屹确认；来源选择不能使目标技能静默丢失。
	var after_timing_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((after_timing_choice.get("context", {}) as Dictionary).get("kind", "")) != "yongyi_damage_confirm" or not _controller.state.get_player(2).hand.has(sefu_gain_card) or _controller._rule_continuations.size() != 1:
		return _fail("damage_after_timing=%s continuations=%s" % [after_timing_choice, _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 取消永屹只结束该技能，伤害尾部与全部触发续列仍必须正常排空。
	if _controller.has_pending_card_choice() or _controller._rule_continuations.has_pending() or _controller.trigger_manager.has_deferred_dispatches():
		return _fail("damage_timing_not_drained continuations=%s" % [_controller._rule_continuations.to_array()])
	return true


## 验证回合前【振旗】与准备阶段【加护】严格依次询问，前一选择不会被后一阶段覆盖或使阶段提前推进。
func _test_turn_start_nested_skill_continuation() -> bool:
	_reset_state(3)
	# 阶段节奏；选择全部完成后只登记判定阶段转换，测试结束前不会真的进入后续阶段。
	_controller.game_flow_interval_seconds = 0.05
	# 回合开始日志顺序；分隔与回合开始必须先于phaseBefore技能询问和准备阶段开始。
	var turn_logs: Array[String] = []
	var turn_log_callback: Callable = func(message: String) -> void: turn_logs.append(message)
	_controller.log_added.connect(turn_log_callback)
	# 领袖技持有者；设置为贝洛伯格角色，使其也能成为【振旗】的合法受益者。
	var leader: PlayerState = _controller.state.get_player(0)
	leader.character_id = "natasha"
	# 新回合角色；贝洛伯格势力满足【振旗】触发条件，同时持有准备阶段技能【加护】。
	var turn_player: PlayerState = _controller.state.get_player(1)
	turn_player.character_id = "gepard"
	# 另一名贝洛伯格角色；作为【振旗】与【加护】都可选择的稳定目标。
	var support_target: PlayerState = _controller.state.get_player(2)
	support_target.character_id = "natasha"
	# 真实【振旗】实例；由领袖全局监听新回合角色的phaseBefore时机。
	var zhenqi: SkillDefinition = _install_single_skill(0, "zhenqi")
	# 真实【加护】实例；只有回合前选择完成并进入phaseZhunbeiBegin后才允许创建其请求。
	var jiahu: SkillDefinition = _install_single_skill(1, "jiahu")
	_controller._start_turn(1)
	# 第一层请求上下文；必须仍是【振旗】费用选择，证明准备阶段尚未越过回合前屏障。
	var zhenqi_choice_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if zhenqi == null or jiahu == null or str(zhenqi_choice_context.get("kind", "")) != "zhenqi_cost_option" or _controller._rule_continuations.size() != 1:
		_controller.log_added.disconnect(turn_log_callback)
		return _fail("turn_start_zhenqi_first context=%s continuations=%s" % [zhenqi_choice_context, _controller._rule_continuations.to_array()])
	# 明确取消【振旗】；规则续接应继续发布剩余回合开始时机，并在准备阶段打开【加护】。
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 第二层请求上下文；只有【振旗】请求已经完整关闭后才能成为当前唯一选择。
	var jiahu_choice_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(jiahu_choice_context.get("kind", "")) != "jiahu_target" or _controller._rule_continuations.size() != 1:
		_controller.log_added.disconnect(turn_log_callback)
		return _fail("turn_start_jiahu_second context=%s continuations=%s" % [jiahu_choice_context, _controller._rule_continuations.to_array()])
	# 选择第三名角色接受【加护】；技能结果完成后才允许准备阶段收尾并安排判定阶段。
	if not _submit_pending_choice(1, [], [2], true):
		return false
	if not support_target.chained or support_target.shield != 1 or _controller.has_pending_card_choice() or _controller._rule_continuations.has_pending() or _controller.state.current_phase != "start" or _controller.game_flow_pacer == null or not _controller.game_flow_pacer.has_pending("phase_transition"):
		_controller.log_added.disconnect(turn_log_callback)
		return _fail("turn_start_complete chained=%s shield=%d pending=%s phase=%s transition=%s" % [support_target.chained, support_target.shield, _controller.has_pending_card_choice(), _controller.state.current_phase, _controller.game_flow_pacer.has_pending("phase_transition") if _controller.game_flow_pacer != null else false])
	# 日志索引；准备阶段开始必须位于回合开始之后，且回合分隔线紧邻并先于回合开始。
	var turn_begin_log: String = "%s的回合开始。" % _controller.format_player_state_log_name(turn_player)
	var turn_begin_index: int = turn_logs.find(turn_begin_log)
	var preparation_begin_index: int = turn_logs.find("准备阶段开始。")
	if turn_begin_index <= 0 or preparation_begin_index <= turn_begin_index or turn_logs[turn_begin_index - 1] != "————————":
		_controller.log_added.disconnect(turn_log_callback)
		return _fail("turn_start_log_order=%s" % [turn_logs])
	_controller.game_flow_pacer.cancel_all()
	_controller.log_added.disconnect(turn_log_callback)
	return true


## 验证还阳按当前距离回复，以及摄伏按伤害牌名字数获牌并在选择原伤害目标时弃置其装备。
func _test_huanyang_and_sefu() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "xveyi"
	# 还阳实例；直接消费标准damageSource事件。
	var huanyang: SkillDefinition = GameDatabase.create_skill("huanyang")
	# 摄伏实例；维护本回合首次伤害额度并创建两段选择。
	var sefu: SkillDefinition = GameDatabase.create_skill("shefu")
	huanyang.bind(_controller, 0)
	sefu.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"huanyang":huanyang, "shefu":sefu}}
	# 雪衣受伤状态；满足还阳时应从3点回复至4点。
	var xveyi_player: PlayerState = _controller.state.get_player(0)
	xveyi_player.hp = 3
	# 还阳正式运行时订阅；通过真实伤害流程验证标准damage时机，而非只直接调用回调函数。
	huanyang.install()
	_controller.damage(0, 1, 1, "normal", "sha")
	if xveyi_player.hp != 4 or str(huanyang.get_metadata().get("trigger", "")) != "damage":
		return _fail("huanyang_damage_timing hp=%d trigger=%s" % [xveyi_player.hp, huanyang.get_metadata().get("trigger", "")])
	# 标准伤害来源事件；【杀】规则名字数为1，目标是距离1的二号角色。
	# 兼容测试变量仍沿用原有名称；还阳的正式订阅已经由上方真实damage流程覆盖。
	var damage_source_event: RuleEvent = RuleEvent.new("damageSource", 0, 1, {"amount":1, "card_id":"sha", "card_user_id":0})
	huanyang.call("_on_owner_damage_source", damage_source_event)
	if xveyi_player.hp != 4:
		return _fail("huanyang_recover=%d" % xveyi_player.hp)
	# 他人使用【决斗】时，持有者即使成为最终伤害来源也没有使用该牌，摄伏不得创建获牌请求。
	var foreign_card_user_event: RuleEvent = RuleEvent.new("damageSource", 0, 1, {"amount":1, "card_id":"sha", "card_user_id":1})
	sefu.call("_on_owner_damage_source", foreign_card_user_event)
	if _controller.has_pending_card_choice():
		return _fail("sefu_foreign_card_user_triggered")
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
	# 濒死目标被【桃】救回后，damageSource 只在救援流程完成时派发；还阳必须仍能回复雪衣1点体力。
	_reset_state(2)
	var rescued_xveyi: PlayerState = _controller.state.get_player(0)
	# 还阳持有者受伤；从3点回复到4点可证明尾部时机没有因目标濒死而丢失。
	rescued_xveyi.hp = 3
	# 濒死目标；先降至1点体力，再受到1点伤害以创建标准求桃窗口。
	var rescued_target: PlayerState = _controller.state.get_player(1)
	rescued_target.hp = 1
	# 自救桃；使用后目标会恢复至1点体力并继续伤害来源尾部。
	var rescue_peach: CardInstance = _add_hand_card(1, "tao", "heart", 9)
	var rescued_huanyang: SkillDefinition = _install_single_skill(0, "huanyang")
	if rescued_huanyang == null:
		return _fail("huanyang_dying_skill_missing")
	_controller.damage(0, 1, 1, "normal", "sha")
	if not _controller.has_pending_card_choice() or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "dying_response":
		return _fail("huanyang_dying_prompt=%s" % _controller._pending_card_choice)
	# 救援顺序从当前回合角色开始；雪衣没有【桃】时先明确放弃，再由濒死目标使用自己的【桃】。
	if not _submit_pending_choice(0, [], [], false):
		return false
	if not _controller.has_pending_card_choice() or int(_controller._pending_card_choice.get("chooser_id", -1)) != 1:
		return _fail("huanyang_dying_self_rescue_prompt=%s" % _controller._pending_card_choice)
	if not _submit_pending_choice(1, [rescue_peach.uid], [], true):
		return false
	if rescued_target.hp != 1 or rescued_xveyi.hp != 4:
		return _fail("huanyang_after_dying_rescue target=%d owner=%d" % [rescued_target.hp, rescued_xveyi.hp])
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


## 验证死亡或离场的【焕发】持有者不会继续响应全局phaseEnd时机并创建新的发动询问。
func _test_dead_huanfa_owner_cannot_trigger() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "natasha"
	_controller.state.current_player_id = 1
	_controller.state.current_phase = "finish"
	_controller.state.phase_index = 5
	# 焕发运行时实例；全局订阅仍保留，用于复现持有者死亡后错误弹出技能询问的问题。
	var huanfa: SkillDefinition = _install_single_skill(0, "huanfa")
	if huanfa == null:
		return _fail("dead_huanfa_missing")
	# 当前回合角色的用药事实；若没有持有者状态保护，本次phaseEnd会满足焕发全部其他条件。
	_controller._cards_used_this_turn_by_player[1] = {"tao":true}
	_controller.state.get_player(0).alive = false
	_controller._emit_rule_timing("phaseEnd", 1, 1, 1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("dead_huanfa_prompt=%s" % [_controller._pending_card_choice])
	# 离场状态与死亡状态使用同一基类保护；即使alive异常保留true也不能继续发动技能。
	_controller.state.get_player(0).alive = true
	_controller.state.get_player(0).out_of_game = true
	_controller._emit_rule_timing("phaseEnd", 1, 1, 1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("absent_huanfa_prompt=%s" % [_controller._pending_card_choice])
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
	# 弃置分支使用独立最小场景；避免同一回合目标限次掩盖第二段选牌请求。
	_reset_state(2)
	var discard_bingfeng: SkillDefinition = GameDatabase.create_skill("bingfeng")
	discard_bingfeng.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"bingfeng":discard_bingfeng}}
	# 目标手牌；用于验证选择“弃置目标手牌”后立刻出现实体弃置选择，而不是重新询问文字分支。
	var target_hand_card: CardInstance = _add_hand_card(1, "shan", "heart", 8)
	_controller._card_use_contexts[9003] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	# 冰封第一段文字询问；通过正式统一请求接口写入技能归属和稳定上下文。
	discard_bingfeng.request_control_selection("冰封", "是否对唯一目标发动【冰封】？", [{"id":"discard_target_hand", "label":"弃置目标手牌"}], true, {"kind":"bingfeng_option", "target_id":1, "card_uid":9003, "card_id":"sha"})
	if not _submit_pending_choice(0, [], [], true, "discard_target_hand"):
		return false
	# 第二段请求；必须保留同一技能上下文并直接列出目标手牌实体。
	var discard_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((discard_choice.get("context", {}) as Dictionary).get("kind", "")) != "bingfeng_discard_card" or str(discard_choice.get("title", "")) != "冰封" or (discard_choice.get("candidates", []) as Array).is_empty():
		return _fail("bingfeng_discard_request=%s" % [discard_choice])
	if not _submit_pending_choice(0, [target_hand_card.uid], [], true):
		return false
	# 选择完成后；目标手牌进入弃牌堆，原牌对目标无效，且不留下重复的冰封文字询问。
	var discard_card_context: Dictionary = _controller._card_use_contexts[9003] as Dictionary
	if _controller.state.get_player(1).find_hand_card(target_hand_card.uid) != null or not _controller.state.discard_pile.has(target_hand_card) or not (discard_card_context.get("excluded_target_ids", []) as Array).has(1) or _controller.has_pending_card_choice():
		return _fail("bingfeng_discard_result hand=%s discard=%s context=%s pending=%s" % [_controller.state.get_player(1).hand, _controller.state.discard_pile.has(target_hand_card), discard_card_context, _controller.has_pending_card_choice()])
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
	# 永屹持有者状态；0点护盾确保第二段1点伤害实际扣减体力并触发伤害后分支。
	var gepard: PlayerState = _controller.state.get_player(0)
	gepard.shield = 0
	# 永屹自伤前体力；用于验证确认后准确受到1点普通伤害。
	var hp_before_yongyi_damage: int = gepard.hp
	# 可用于额外出牌阶段的实体【杀】；本段验证有牌时的阶段恢复，空手牌仍会创建确认请求并在后续独立断言。
	_add_hand_card(0, "sha", "spade", 7)
	# 永屹第二段的固定摸牌来源；避免空牌堆提前结束对局而掩盖额外出牌阶段的恢复结果。
	_add_draw_pile_card("shan", "heart", 9)
	# 确认前手牌数；确认后应因第二段固定摸1张牌而增加1。
	var hand_count_before_yongyi_draw: int = gepard.hand.size()
	# 永屹运行时技能；安装真实弃牌阶段Begin订阅，确保确认响应经过统一恢复入口。
	var yongyi: SkillDefinition = _install_single_skill(0, "yongyi")
	# 弃牌阶段生命周期；永屹应在Begin创建确认选择并暂停当前弃牌阶段。
	var discard_started: bool = _controller._begin_phase_lifecycle("phaseDiscard", 0, {"turn_number":_controller.state.turn_number}, -1)
	if yongyi == null or not discard_started or not _controller.has_pending_card_choice() or _controller.state.current_phase != "choice":
		return _fail("yongyi_begin_choice skill=%s started=%s pending=%s phase=%s" % [yongyi, discard_started, _controller.has_pending_card_choice(), _controller.state.current_phase])
	# 确认发动第二段；自伤产生的伤害后分支必须先创建嵌套确认，不能提前摸牌或恢复阶段。
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 嵌套伤害后确认；后续摸牌和额外出牌阶段仍在技能结算队列中等待。
	var nested_damage_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if gepard.hp != hp_before_yongyi_damage - 1 or gepard.hand.size() != hand_count_before_yongyi_draw or str(nested_damage_context.get("kind", "")) != "yongyi_damage_confirm":
		return _fail("yongyi_nested_damage hp=%d hand=%d context=%s" % [gepard.hp, gepard.hand.size(), nested_damage_context])
	# 取消自伤再次触发的第一段；完整伤害尾部排空后才允许第二段继续摸牌和登记阶段。
	if not _submit_pending_choice(0, [], [], false):
		return false
	# 阶段转换等待；额外出牌阶段不经过摸牌阶段，因此短暂等待后应稳定进入新的出牌请求。
	await get_tree().create_timer(0.10, false).timeout
	# 永屹结果与额外出牌阶段；体力减少1、护盾保持0、固定摸1张牌，且额外阶段已进入正式出牌请求。
	if gepard.hp != hp_before_yongyi_damage - 1 or gepard.shield != 0 or gepard.hand.size() != hand_count_before_yongyi_draw + 1 or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)) or str(_controller._active_extra_play_phase_context.get("return_point", "")) != "finish" or _controller.state.current_phase != "play" or not _controller._has_active_play_choice():
		return _fail("yongyi_resume hp=%d shield=%d hand=%d return_finish=%s phase=%s play_choice=%s" % [gepard.hp, gepard.shield, gepard.hand.size(), _controller._extra_play_phase_returns_to_finish, _controller.state.current_phase, _controller._has_active_play_choice()])

	# 再建一局确认嵌套伤害后的额外弃牌阶段；该分支完成后必须继续恢复原第二段的摸牌与额外出牌阶段。
	_controller.game_flow_pacer.cancel_all()
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.05
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "discard"
	_controller.state.phase_index = 4
	# 需要额外弃置的杰帕德；自伤后体力为3，四张手牌会在额外弃牌阶段强制弃置1张。
	var confirmed_gepard: PlayerState = _controller.state.get_player(0)
	confirmed_gepard.shield = 0
	var confirmed_discard_card: CardInstance = _add_hand_card(0, "shan", "club", 2)
	# 普通弃牌阶段继续使用的第二张费用牌；证明嵌套询问结束后原阶段主体仍会完成，再进入额外出牌阶段。
	var confirmed_normal_discard_card: CardInstance = _add_hand_card(0, "sha", "spade", 3)
	_add_hand_card(0, "wuxie", "club", 4)
	_add_hand_card(0, "tao", "heart", 5)
	# 原第二段固定摸牌；额外弃牌结束后恢复技能后续时必须进入手牌。
	var confirmed_draw_card: CardInstance = _add_draw_pile_card("shan", "diamond", 6)
	# 初始手牌数；完成额外弃1张并固定摸1张后应回到相同数量。
	var confirmed_hand_count_before: int = confirmed_gepard.hand.size()
	# 真实永屹实例；弃牌阶段Begin首先创建第二段确认。
	var confirmed_yongyi: SkillDefinition = _install_single_skill(0, "yongyi")
	if confirmed_yongyi == null or not _controller._begin_phase_lifecycle("phaseDiscard", 0, {"turn_number":_controller.state.turn_number}, -1):
		return _fail("yongyi_confirmed_nested_setup")
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 自伤触发的第一段询问；本次确认执行真实额外弃牌阶段，而不是取消后直接恢复。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "yongyi_damage_confirm" or not _submit_pending_choice(0, [], [], true):
		return _fail("yongyi_confirmed_damage_prompt=%s" % [_controller._pending_card_choice])
	# 额外弃牌阶段请求；确认第一段后应要求按当前3点体力弃置正好1张手牌。
	var extra_discard_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(extra_discard_context.get("kind", "")) != "extra_discard_phase" or int(extra_discard_context.get("discard_count", 0)) != 1:
		return _fail("yongyi_confirmed_extra_discard=%s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [confirmed_discard_card.uid], [], true):
		return false
	# 原普通弃牌阶段仍需按摸牌后的实际手牌上限弃置1张；该请求不能吞掉已经登记的额外出牌阶段。
	await get_tree().process_frame
	var normal_discard_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(normal_discard_context.get("kind", "")) != "discard_phase" or int(normal_discard_context.get("discard_count", 0)) != 1:
		return _fail("yongyi_confirmed_normal_discard=%s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [confirmed_normal_discard_card.uid], [], true):
		return false
	# 阶段恢复使用延后一帧继续排空新暴露的技能后续；等待流程间隔后应进入唯一额外出牌阶段。
	await get_tree().create_timer(0.12, false).timeout
	if confirmed_gepard.hp != 3 or confirmed_gepard.shield != 1 or confirmed_gepard.hand.size() != confirmed_hand_count_before - 1 or confirmed_gepard.find_hand_card(confirmed_draw_card.uid) == null or confirmed_gepard.find_hand_card(confirmed_discard_card.uid) != null or confirmed_gepard.find_hand_card(confirmed_normal_discard_card.uid) != null or _controller.state.current_phase != "play" or not _controller._has_active_play_choice():
		return _fail("yongyi_confirmed_resume hp=%d shield=%d hand=%d phase=%s play_choice=%s counts=%s returns=%s active=%s" % [confirmed_gepard.hp, confirmed_gepard.shield, confirmed_gepard.hand.size(), _controller.state.current_phase, _controller._has_active_play_choice(), _controller._extra_play_phase_counts, _controller._extra_play_phase_return_points, _controller._active_extra_play_phase_context])
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
	# 借刀杀人要求打出【杀】的响应窗口；候选必须公开罡风材料、所需技能ID和可点击技能入口，不能只在普通决斗等场景生效。
	_controller.request_response_card(0, "sha", "请响应借刀杀人并打出【杀】。", {"kind":"borrow_sword_response", "parent_card_uid":-1, "responder_id":0, "source_id":1, "victim_id":1})
	var borrow_sword_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var borrow_sword_context: Dictionary = borrow_sword_choice.get("context", {}) as Dictionary
	var has_gangfeng_material: bool = false
	for candidate_variant: Variant in borrow_sword_choice.get("candidates", []) as Array:
		# 当前借刀响应候选；黑色材料必须明确绑定罡风，而非被静默视为普通【杀】。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == material.uid and str(candidate.get("required_response_skill_id", "")) == "gangfeng":
			has_gangfeng_material = true
			break
	if str(borrow_sword_context.get("kind", "")) != "borrow_sword_response" or not has_gangfeng_material or not (borrow_sword_context.get("active_skill_ids", []) as Array).has("gangfeng") or not (borrow_sword_context.get("response_conversion_skill_ids", []) as Array).has("gangfeng"):
		return _fail("gangfeng_borrow_sword_response choice=%s" % borrow_sword_choice)
	# 本段只验证借刀响应候选与技能入口协议，明确取消后继续验证实际材料消费语义。
	if not _submit_pending_choice(0, [], [], false):
		return false
	# 未明确点击罡风的响应消费；黑色材料不能自动视为【杀】且必须继续留在手牌区。
	var implicit_response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, material.uid, ["sha"])
	if implicit_response_card != null or _controller.state.get_player(0).find_hand_card(material.uid) == null:
		return _fail("gangfeng_implicit_response")
	# 转化后响应牌；定义ID必须为sha_thunder，但实体UID不替代真实材料记录。
	var response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, material.uid, ["sha"], [], "gangfeng")
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
	var equipment_response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, armor_material.uid, ["sha"], [], "gangfeng")
	if equipment_response_card == null or equipment_response_card.definition_id != "sha_thunder" or response_owner.equipment.has("armor") or _controller.card_runtime_instances.has(armor_material.uid) or response_owner.hp != 4 or not _controller.state.discard_pile.has(armor_material):
		return _fail("gangfeng_equipment_response hp=%d equipment=%s runtime=%s discard=%s" % [response_owner.hp, response_owner.equipment, _controller.card_runtime_instances.has(armor_material.uid), _controller.state.discard_pile.has(armor_material)])
	return true


## 验证转化牌目标枚举按每张材料的真实颜色执行，【全垒】AI不会用黑色材料指定拥有【琥珀】的角色。
func _test_conversion_material_target_rules() -> bool:
	_reset_state(3)
	# 黑色与红色普通手牌；两张牌都满足【全垒】材料条件，但只有黑色牌会触发【琥珀】免疫。
	var black_material: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	var red_material: CardInstance = _add_hand_card(0, "sha", "heart", 8)
	# 全垒与琥珀运行时实例；目标规则服务通过控制器统一汇总双方技能限制。
	var quanlei: SkillDefinition = GameDatabase.create_skill("quanlei")
	var hupo: SkillDefinition = GameDatabase.create_skill("hupo")
	quanlei.bind(_controller, 0)
	hupo.bind(_controller, 1)
	_controller.skill_instances_by_player = {0:{"quanlei":quanlei}, 1:{"hupo":hupo}}
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	# 材料到目标映射；1号拥有琥珀，2号没有来牌限制。
	var candidates: Array[Dictionary] = _controller.get_hand_candidates(0, 0)
	var selection_data: Dictionary = quanlei.build_virtual_target_selection_data("sha_thunder", candidates, {"maximum_target_count_bonus":1})
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	var black_target_ids: Array = target_ids_by_card_id.get(str(black_material.uid), []) as Array
	var red_target_ids: Array = target_ids_by_card_id.get(str(red_material.uid), []) as Array
	if black_target_ids.has(1) or not black_target_ids.has(2) or not red_target_ids.has(1) or not red_target_ids.has(2):
		return _fail("conversion_target_mapping black=%s red=%s" % [black_target_ids, red_target_ids])
	# AI合法动作；任何黑色材料指定琥珀目标的动作都属于预览阶段应排除的非法组合。
	var actions: Array[Dictionary] = []
	quanlei.append_play_phase_actions(actions)
	var has_black_hupo_action: bool = false
	var has_red_hupo_action: bool = false
	for action: Dictionary in actions:
		# 当前技能动作负载；保存实际材料UID与目标集合。
		var payload: Dictionary = action.get("payload", {}) as Dictionary
		# 当前材料UID；用于区分黑色与红色转化组合。
		var material_card_uid: int = int(payload.get("material_card_uid", -1))
		# 当前目标集合；全垒支持一至两名目标，任意包含1号都视为指定琥珀角色。
		var target_ids: Array = payload.get("target_ids", []) as Array
		if material_card_uid == black_material.uid and target_ids.has(1):
			has_black_hupo_action = true
		if material_card_uid == red_material.uid and target_ids.has(1):
			has_red_hupo_action = true
	if has_black_hupo_action or not has_red_hupo_action:
		return _fail("conversion_ai_actions black_hupo=%s red_hupo=%s actions=%s" % [has_black_hupo_action, has_red_hupo_action, actions])
	# 控制器最终入口；即使调用方绕过技能预览，黑色材料目标仍会在移动牌前被拒绝。
	var black_material_uids: Array[int] = [black_material.uid]
	if bool(_controller.execute_virtual_card_use(0, "sha_thunder", black_material_uids, [1], "", {"maximum_target_count_bonus":1})) or not _controller.state.get_player(0).hand.has(black_material):
		return _fail("conversion_final_validation")
	# 单材料转化牌表现历史；控制器应把材料原牌面与转化后逻辑牌名同时写入useCard表现快照。
	var conversion_presentations: Array[Dictionary] = []
	_controller.card_presentation_requested.connect(func(presentation_data: Dictionary) -> void: conversion_presentations.append(presentation_data.duplicate(true)))
	# 红色材料转化使用；目标2没有琥珀限制，可进入正式虚拟牌生命周期并立即发布牌面表现。
	var red_material_uids: Array[int] = [red_material.uid]
	if not bool(_controller.execute_virtual_card_use(0, "sha_thunder", red_material_uids, [2], "", {"maximum_target_count_bonus":1})) or conversion_presentations.is_empty():
		return _fail("conversion_presentation_missing")
	# 最新使用牌表现数据；definition_id保持逻辑牌，原材料定义和横条定义分别供CardView绘制原牌与转化标签。
	var conversion_card_data: Dictionary = (conversion_presentations.back() as Dictionary).get("card_data", {}) as Dictionary
	if str(conversion_card_data.get("definition_id", "")) != "sha_thunder" or str(conversion_card_data.get("presentation_original_definition_id", "")) != "sha" or str(conversion_card_data.get("view_as_definition_id", "")) != "sha_thunder":
		return _fail("conversion_presentation_data=%s" % [conversion_card_data])
	return true


## 验证普通【杀】可触发疾雨、原目标只调整至横置，并验证两个后续分支的实际效果。
func _test_jiyu_branches() -> bool:
	_reset_state(3)
	# 疾雨运行时技能；安装真实指定目标时机并登记到技能表以经过统一选择恢复入口。
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	jiyu.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"jiyu":jiyu}}
	jiyu.install()
	_controller._card_use_contexts[9101] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	# 原目标预先横置；“调整至横置状态”必须保持该状态，不能按旧切换语义翻回竖直。
	_controller.state.get_player(1).chained = true
	# 普通【杀】指定目标时机；三种【杀】共享slash牌效，不能再限定雷【杀】定义ID。
	_controller._emit_rule_timing("useCardToTargeted", 0, 0, 1, {"card_id":"sha", "card_uid":9101, "target_id":1})
	# 疾雨发动确认；普通【杀】同样必须创建持有者确认请求。
	var confirm_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(confirm_context.get("kind", "")) != "jiyu_confirm":
		return _fail("jiyu_normal_slash_trigger context=%s" % [confirm_context])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 发动后原目标仍为横置，且后续选择权准确交给该【杀】目标。
	var target_option_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if not _controller.state.get_player(1).chained or str(target_option_context.get("kind", "")) != "jiyu_target_option" or int(_controller._pending_card_choice.get("chooser_id", -1)) != 1:
		return _fail("jiyu_adjust_chained chained=%s choice=%s" % [_controller.state.get_player(1).chained, _controller._pending_card_choice])
	# 疾雨第1项响应；目标明确选择不可响应此【杀】。
	if not _submit_pending_choice(1, [], [], true, "direct_hit"):
		return false
	# 普通【杀】使用上下文；二号玩家应成为唯一直击目标。
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


## 验证疾雨为普通、火与雷【杀】提供相同AI优先值，不再额外诱导罡风转换雷【杀】。
func _test_jiyu_all_slash_ai_priority() -> bool:
	_reset_state(2)
	# 疾雨静态AI实例；动作修正只读取逻辑牌定义，无需连接权威控制器。
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	jiyu.bind(null, 0)
	# 权威AI快照；疾雨只需要牌定义，本测试仍传入完整结构以保持接口契约。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 通用AI评估器；动作修正当前不读取其状态，但调用参数必须使用正式类型。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	for slash_definition_id: String in ["sha", "sha_fire", "sha_thunder"]:
		# 当前【杀】动作；三种定义共享slash牌效并应获得完全相同的4.0分增益。
		var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_definition_id":slash_definition_id, "target_ids":[1]}
		# 当前【杀】修正结果；与固定基础分之差必须准确等于技能声明值。
		var modified_score: float = jiyu.modify_ai_card_action_score(snapshot, slash_action, 3.0, evaluator)
		if not is_equal_approx(modified_score, 7.0):
			return _fail("jiyu_slash_priority id=%s score=%s" % [slash_definition_id, modified_score])
	# 非【杀】动作；不能因疾雨获得任何额外分数。
	var non_slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_definition_id":"wuzhong", "target_ids":[0]}
	if not is_equal_approx(jiyu.modify_ai_card_action_score(snapshot, non_slash_action, 3.0, evaluator), 3.0):
		return _fail("jiyu_non_slash_priority")
	# 技能静态元数据；旧雷【杀】联动字段必须移除，避免基础策略继续偏向罡风转换。
	if GameDatabase.get_skill("jiyu").has("ai_thunder_slash_priority_bonus"):
		return _fail("jiyu_obsolete_thunder_priority_metadata")
	return true


## 验证本阶段【杀】次数用尽后【罡风】不可主动发动，按钮可用性与动作枚举同时关闭。
func _test_gangfeng_respects_slash_play_limit() -> bool:
	_reset_state(2)
	# 罡风运行时实例；本测试不需要疾雨联动。
	var gangfeng: SkillDefinition = GameDatabase.create_skill("gangfeng")
	gangfeng.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"gangfeng":gangfeng}}
	# 黑色材料；目标规则与次数校验都必须在 can_activate 阶段生效。
	_add_hand_card(0, "sha", "club", 5)
	# 行动者进入自己的出牌阶段，并已使用本阶段唯一一次【杀】。
	var actor: PlayerState = _controller.state.get_player(0)
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	# 阶段作用域用牌历史；validate_virtual_use 与 can_activate 均读取该字段而不是旧 slash_count。
	actor.play_phase_card_use_history["sha"] = 1
	actor.card_use_history["sha"] = 1
	actor.slash_count = 1
	if gangfeng.can_activate():
		return _fail("gangfeng_available_after_slash_limit history=%s" % actor.play_phase_card_use_history)
	# 合法动作列表；次数用尽时不得再出现罡风主动动作。
	var has_gangfeng_action: bool = false
	for action: Dictionary in _controller.get_legal_actions(0):
		if str(action.get("action_type", "")) == "use_skill" and str(action.get("skill_id", (action.get("payload", {}) as Dictionary).get("skill_id", ""))) == "gangfeng":
			has_gangfeng_action = true
			break
	if has_gangfeng_action:
		return _fail("gangfeng_action_after_slash_limit")
	# 恢复阶段历史后必须重新可发动，证明灰显只来自次数而不是材料或目标缺失。
	actor.play_phase_card_use_history.clear()
	actor.card_use_history.clear()
	actor.slash_count = 0
	if not gangfeng.can_activate():
		return _fail("gangfeng_unavailable_with_remaining_slash")
	return true


## 验证AI同步发动录事后会重新安排下一动作；该场景不触发冥谶，专门覆盖主动技能早退导致的停滞缺口。
func _test_ai_active_skill_progress_recovery() -> bool:
	_reset_state(2)
	# 寒鸦武将状态；三张同名【杀】允许录事弃置其中两张，同时保留1张手牌避免触发冥谶子选择。
	var hanya: PlayerState = _controller.state.get_player(0)
	hanya.character_id = "hanya"
	# 寒鸦技能实例；冥谶仍真实安装，用剩余手牌证明本次同步技能不会依赖子选择恢复AI。
	var mingchen: SkillDefinition = GameDatabase.create_skill("mingchen")
	var lushi: SkillDefinition = GameDatabase.create_skill("lushi")
	mingchen.bind(_controller, 0)
	lushi.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"mingchen":mingchen, "lushi":lushi}}
	mingchen.install()
	lushi.install()
	# 三张规则名相同的普通手牌；录事支付前两张后仍保留最后一张，不创建冥谶请求。
	var first_cost: CardInstance = _add_hand_card(0, "sha", "spade", 2)
	var second_cost: CardInstance = _add_hand_card(0, "sha", "club", 3)
	_add_hand_card(0, "sha", "spade", 4)
	# 录事固定摸牌来源；同步效果完成后手牌恢复为2张。
	_add_draw_pile_card("shan", "heart", 6)
	# 当前玩家交由内置AI控制；等待设置调高到1秒，使断言可在下一动作真正执行前检查调度状态。
	_controller.ai_coordinator.register_basic_ai(0)
	_controller.ai_action_delay_seconds = 1.0
	_controller._begin_play_choice(0)
	# 标准主动技能动作；提交会先完成旧chooseToUse，再同步弃牌摸牌并建立新的chooseToUse。
	var skill_action: PlayerAction = PlayerAction.new("use_skill", 0)
	skill_action.payload = {"skill_id":"lushi", "card_uids":[first_cost.uid, second_cost.uid]}
	if not _controller.submit_action(skill_action):
		return _fail("hanya_ai_skill_submit")
	if _controller.has_pending_card_choice() or not _controller._has_active_play_choice() or _controller._scheduled_ai_drive_token != _controller._ai_drive_token or hanya.hand.size() != 2:
		return _fail("hanya_ai_skill_resume pending=%s active=%s scheduled=%d token=%d hand=%d" % [_controller.has_pending_card_choice(), _controller._has_active_play_choice(), _controller._scheduled_ai_drive_token, _controller._ai_drive_token, hanya.hand.size()])
	# 使本测试创建的延时任务失效；后续专项状态不能接收本场旧AI动作。
	_controller._ai_drive_token += 1
	_controller._scheduled_ai_drive_token = -1
	return true


## 验证姬子在自己出牌阶段以唯一目标【杀】触发【星火】后，【领航】的确认与重铸选择会完整恢复原使用牌事件。
func _test_himeko_card_use_linghang_choice_resumption() -> bool:
	_reset_state(2)
	# 姬子角色状态；领袖身份使其实际拥有【领航】，并作为【星火】横置事件的星穹列车来源。
	var himeko: PlayerState = _controller.state.get_player(0)
	himeko.character_id = "himeko"
	# 被指定角色；只需保留存活在场状态，使唯一目标【杀】满足【星火】与正式响应流程。
	var target: PlayerState = _controller.state.get_player(1)
	target.character_id = "dan_heng"
	# 星火与领航运行时实例；两项均通过正式有序触发器订阅，不能以直接方法调用替代。
	var xinghuo: SkillDefinition = _install_single_skill(0, "xinghuo")
	var linghang: SkillDefinition = _install_single_skill(0, "linghang")
	# 姬子本次实际使用的唯一目标【杀】；进入真实CardUseEvent后才会触发星火的useCardToTargeted时机。
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	# 领航重铸候选；保留第二张手牌确保确认发动后一定会创建第二层选择。
	var recast_card: CardInstance = _add_hand_card(0, "shan", "heart", 8)
	# 重铸摸牌来源；取消重铸时该牌必须仍留在牌堆，防止测试把取消路径误判成成功重铸。
	var draw_card: CardInstance = _add_draw_pile_card("tao", "club", 9)
	if xinghuo == null or linghang == null:
		return _fail("himeko_linghang_skill_missing")
	# 正式出牌阶段请求；必须先消费chooseToUse再执行卡牌，覆盖真人点击技能或卡牌时使用的完整事件树。
	_controller._begin_play_choice(0)
	if not _controller.call("_has_active_play_choice"):
		return _fail("himeko_missing_play_choice")
	# 玩家实际使用【杀】动作；目标由标准PlayerAction提交，不能绕过出牌请求直接进入内部结算函数。
	var use_slash_action: PlayerAction = PlayerAction.new("use_card", 0, slash_card.uid)
	use_slash_action.target_ids = [1]
	if not _controller.submit_action(use_slash_action):
		return _fail("himeko_submit_slash")
	# 领航第一层确认；触发者是姬子本人，选择上下文必须仍附着在未收尾的【杀】事件树上。
	var confirm_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var confirm_context: Dictionary = confirm_choice.get("context", {}) as Dictionary
	if str(confirm_context.get("kind", "")) != "linghang_confirm" or int(confirm_choice.get("chooser_id", -1)) != 0 or not _controller._card_use_contexts.has(slash_card.uid):
		return _fail("himeko_linghang_confirm choice=%s contexts=%s" % [confirm_choice, _controller._card_use_contexts])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 领航第二层重铸；确认后原选择已清理，新选择必须由同一使用牌事件继续承载而非停在孤立窗口。
	var recast_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var recast_context: Dictionary = recast_choice.get("context", {}) as Dictionary
	# 原卡牌时机事件；连续选择必须都挂在该事件下，不能让重铸成为确认选择事件的子节点。
	var card_timing_event_id: int = int(confirm_context.get("choice_parent_event_id", -1))
	# 重铸选择事件摘要；父事件关系是卡牌流程能在第二段选择结束后继续的必要条件。
	var recast_event: Dictionary = _controller.event_scheduler.get_event_snapshot(int(recast_choice.get("runtime_event_id", -1)))
	if str(recast_context.get("kind", "")) != "linghang_recast" or int(recast_choice.get("chooser_id", -1)) != 0 or int(recast_event.get("parent_id", -1)) != card_timing_event_id or not _controller._card_use_contexts.has(slash_card.uid):
		return _fail("himeko_linghang_recast choice=%s contexts=%s" % [recast_choice, _controller._card_use_contexts])
	if not _submit_pending_choice(0, [recast_card.uid], [], true):
		return false
	# 重铸完成后原【杀】必须恢复到目标响应步骤；若仍停在领航选择或没有后续事件，出牌阶段将无法继续。
	var slash_response_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var slash_response_context: Dictionary = slash_response_choice.get("context", {}) as Dictionary
	if str(slash_response_context.get("kind", "")) != "slash_response" or int(slash_response_choice.get("chooser_id", -1)) != 1:
		return _fail("himeko_linghang_missing_slash_response choice=%s contexts=%s" % [slash_response_choice, _controller._card_use_contexts])
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 目标放弃响应后原【杀】必须完成处理区收尾并恢复下一次出牌选择；重铸牌与使用牌均进入弃牌堆，摸牌进入手牌。
	if _controller.has_pending_card_choice() or _controller._card_use_contexts.has(slash_card.uid) or not _controller.call("_has_active_play_choice") or _controller.state.get_player(0).hand.has(recast_card) or not _controller.state.get_player(0).hand.has(draw_card) or not _controller.state.discard_pile.has(recast_card) or not _controller.state.discard_pile.has(slash_card):
		return _fail("himeko_linghang_resume pending=%s contexts=%s active=%s hand=%s discard=%s" % [_controller.has_pending_card_choice(), _controller._card_use_contexts, _controller.call("_has_active_play_choice"), _controller.state.get_player(0).hand, _controller.state.discard_pile])
	return true


## 验证AI异常回退直接复用完整合法动作，固定组合与响应转化技能ID都不会被“前N张候选”逻辑破坏。
func _test_ai_choice_fallback_integrity() -> bool:
	_reset_state(2)
	# 固定双牌组合请求；只有UID 12与13的组合合法，候选前两张11与12必须被过滤。
	var combination_request: Dictionary = {
		"request_id":701,
		"chooser_id":0,
		"choice_type":"card",
		"allow_cancel":false,
		"min_select":2,
		"max_select":2,
		"min_card_select":2,
		"max_card_select":2,
		"candidates":[{"uid":11}, {"uid":12}, {"uid":13}],
		"target_ids":[],
		"context":{"valid_card_combinations":[[12, 13]]},
	}
	# 固定组合回退动作；必须保存规则枚举确认过的完整双牌组。
	var combination_fallback: Dictionary = _controller._build_ai_choice_fallback_action(combination_request)
	# 固定组合负载；最终提交字段与普通AI策略动作使用同一结构。
	var combination_payload: Dictionary = combination_fallback.get("payload", {}) as Dictionary
	if combination_payload.get("selected_card_uids", []) != [12, 13] or not bool(combination_payload.get("confirmed", false)):
		return _fail("ai_fallback_combination action=%s" % [combination_fallback])
	# 响应技能材料请求；候选声明必须显式携带罡风技能ID，不能把黑色材料误当成原生响应牌。
	var response_request: Dictionary = {
		"request_id":702,
		"chooser_id":0,
		"choice_type":"respond",
		"allow_cancel":false,
		"min_select":1,
		"max_select":1,
		"min_card_select":1,
		"max_card_select":1,
		"candidates":[{"uid":21, "required_response_skill_id":"gangfeng"}],
		"target_ids":[],
		"context":{},
	}
	# 响应技能回退动作；response_skill_id是消费材料前权威复核转换技能的必要字段。
	var response_fallback: Dictionary = _controller._build_ai_choice_fallback_action(response_request)
	# 响应回退负载；除材料UID外还必须保留准确的技能ID。
	var response_payload: Dictionary = response_fallback.get("payload", {}) as Dictionary
	if response_payload.get("selected_card_uids", []) != [21] or str(response_payload.get("response_skill_id", "")) != "gangfeng":
		return _fail("ai_fallback_response_skill action=%s" % [response_fallback])
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
	# 第二段测试不保留第一段所得护盾；确保1点普通自伤穿透并写入真实伤害历史。
	gepard.shield = 0
	# 额外出牌阶段可用实体牌；用于验证固定摸牌后仍会正常登记额外出牌阶段。
	_add_hand_card(0, "sha", "club", 6)
	# 永屹固定摸牌来源；数组末尾为牌堆顶，确认后应移入杰帕德手牌。
	var extra_play_draw_card: CardInstance = _add_draw_pile_card("shan", "diamond", 8)
	# 确认前手牌数；用于断言第二段准确摸取1张牌。
	var hand_count_before_extra_play_draw: int = gepard.hand.size()
	# 第二段自伤前体力；固定1点普通伤害应使该值准确减少1。
	var hp_before_extra_play_damage: int = gepard.hp
	# 第二段自伤前伤害历史数；用于证明新费用属于伤害而不是失去护盾或失去体力。
	var history_before_extra_play_damage: int = gepard.damage_history.size()
	# 永屹弃牌阶段确认响应；直接调用技能会先造成伤害并把摸牌、额外阶段登记为延迟技能后续。
	var extra_play_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	yongyi.continue_selection({"kind":"yongyi_play_phase_confirm"}, extra_play_response)
	if gepard.hp != hp_before_extra_play_damage - 1 or gepard.damage_history.size() != history_before_extra_play_damage + 1 or gepard.hand.size() != hand_count_before_extra_play_draw or _controller._deferred_skill_settlements.size() != 1:
		return _fail("yongyi_self_damage hp=%d history=%d hand=%d deferred=%s" % [gepard.hp, gepard.damage_history.size(), gepard.hand.size(), _controller._deferred_skill_settlements])
	# 直接技能调用绕过选择提交入口；手动排空统一结算管线以恢复摸牌和额外阶段登记。
	_controller._resume_settlement_pipeline()
	if gepard.shield != 0 or gepard.hand.size() != hand_count_before_extra_play_draw + 1 or gepard.find_hand_card(extra_play_draw_card.uid) == null or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)):
		return _fail("yongyi_extra_play hp=%d shield=%d hand=%d return_finish=%s" % [gepard.hp, gepard.shield, gepard.hand.size(), _controller._extra_play_phase_returns_to_finish])
	# 无手牌场景；【永屹】仍须向玩家提供自伤确认窗口，只有AI评分会根据收益与生存风险倾向取消。
	_reset_state(2)
	# 空手牌杰帕德；无护盾且处于弃牌阶段，但不额外加入可使用牌。
	var empty_hand_gepard: PlayerState = _controller.state.get_player(0)
	empty_hand_gepard.shield = 0
	# 空手牌场景自伤前体力；用于验证嵌套询问出现时伤害已实际成立。
	var empty_hand_hp_before: int = empty_hand_gepard.hp
	# 空手牌场景的固定摸牌来源；确认后必须由永屹将该实体移入手牌。
	var empty_hand_draw_card: CardInstance = _add_draw_pile_card("tao", "heart", 5)
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "discard"
	_controller.state.phase_index = 4
	# 真实运行时永屹技能；订阅弃牌阶段时机并生成标准确认请求。
	var empty_hand_yongyi: SkillDefinition = _install_single_skill(0, "yongyi")
	# 空手牌弃牌阶段生命周期；原文条件满足时仍要暂停并等待玩家确认。
	var empty_hand_discard_started: bool = _controller._begin_phase_lifecycle("phaseDiscard", 0, {"turn_number":_controller.state.turn_number}, -1)
	if empty_hand_yongyi == null or not empty_hand_discard_started or not _controller.has_pending_card_choice():
		return _fail("yongyi_empty_hand_choice skill=%s started=%s pending=%s" % [empty_hand_yongyi, empty_hand_discard_started, _controller.has_pending_card_choice()])
	# 玩家明确确认；无可用牌不应阻止技能造成自伤，但后续摸牌必须等待伤害流程完成。
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 自伤再次触发永屹第一段；此时尚未摸牌，也未登记额外出牌阶段。
	var nested_damage_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if empty_hand_gepard.hp != empty_hand_hp_before - 1 or not empty_hand_gepard.hand.is_empty() or str(nested_damage_context.get("kind", "")) != "yongyi_damage_confirm":
		return _fail("yongyi_empty_hand_nested hp=%d hand=%d context=%s" % [empty_hand_gepard.hp, empty_hand_gepard.hand.size(), nested_damage_context])
	# 取消本次自伤触发的额外弃牌阶段；随后统一管线继续原第二段后续。
	if not _submit_pending_choice(0, [], [], false):
		return false
	# 空手牌额外出牌阶段可能同步完成并消耗队列计数；自伤、摸到指定实体与返回结束阶段标记共同证明结算顺序正确。
	if empty_hand_gepard.hp != empty_hand_hp_before - 1 or empty_hand_gepard.shield != 0 or empty_hand_gepard.hand.size() != 1 or empty_hand_gepard.find_hand_card(empty_hand_draw_card.uid) == null or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)):
		return _fail("yongyi_empty_hand_confirm hp=%d shield=%d hand=%d return_finish=%s" % [empty_hand_gepard.hp, empty_hand_gepard.shield, empty_hand_gepard.hand.size(), _controller._extra_play_phase_returns_to_finish])

	# 第二段每回合限一次：同一技能实例确认发动后，同回合再次触发弃牌阶段Begin不得询问。
	_reset_state(2)
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "discard"
	_controller.state.phase_index = 4
	_controller.state.turn_number = 3
	# 固定摸牌来源；第一次成功发动后会摸入1张，用于证明首次自伤后续完整执行。
	var once_draw_card: CardInstance = _add_draw_pile_card("shan", "club", 3)
	# 同一永屹实例；直接走技能确认入口，避免依赖阶段生命周期的中间清理细节。
	var once_per_turn_yongyi: SkillDefinition = _install_single_skill(0, "yongyi")
	if once_per_turn_yongyi == null:
		return _fail("yongyi_once_missing_skill")
	# 第一次弃牌阶段Begin；应正常创建第二段确认请求。
	once_per_turn_yongyi.call("_on_discard_phase_begin", RuleEvent.new("phaseDiscardBegin", 0, -1, {"turn_number":_controller.state.turn_number}))
	if not _controller.has_pending_card_choice() or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "yongyi_play_phase_confirm":
		return _fail("yongyi_once_first_prompt pending=%s" % [_controller._pending_card_choice])
	# 确认前体力；成功发动后应减少1点，且第二次Begin不得再次改变。
	var once_hp_before: int = _controller.state.get_player(0).hp
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 自伤可能嵌套第一段确认；取消后继续排空第二段后续。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "yongyi_damage_confirm":
		if not _submit_pending_choice(0, [], [], false):
			return false
	_controller._resume_settlement_pipeline()
	var once_owner: PlayerState = _controller.state.get_player(0)
	if once_owner.hp != once_hp_before - 1 or once_owner.find_hand_card(once_draw_card.uid) == null or once_per_turn_yongyi._used_play_branch_turn_number != 3:
		return _fail("yongyi_once_first_effect hp=%d hand=%d used_turn=%s" % [once_owner.hp, once_owner.hand.size(), once_per_turn_yongyi._used_play_branch_turn_number])
	# 同回合第二次Begin；额度已消耗，不得创建新的第二段确认。
	_controller._pending_card_choice.clear()
	once_per_turn_yongyi.call("_on_discard_phase_begin", RuleEvent.new("phaseDiscardBegin", 0, -1, {"turn_number":_controller.state.turn_number}))
	if _controller.has_pending_card_choice() or once_owner.hp != once_hp_before - 1:
		return _fail("yongyi_once_second_blocked pending=%s hp=%d" % [_controller.has_pending_card_choice(), once_owner.hp])
	# 下一全局回合应重新允许第二段询问。
	_controller.state.turn_number = 4
	once_per_turn_yongyi.call("_on_discard_phase_begin", RuleEvent.new("phaseDiscardBegin", 0, -1, {"turn_number":_controller.state.turn_number}))
	if not _controller.has_pending_card_choice() or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "yongyi_play_phase_confirm":
		return _fail("yongyi_once_next_turn pending=%s" % [_controller._pending_card_choice])
	return true



## 验证统一体力牌差比例、冰封联动、疾雨选项与永屹收益判断。
func _test_new_skill_ai_rules() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "march_7th"
	_controller.state.get_player(2).chained = true
	# 权威AI快照；对本地策略包含完整手牌与公开技能历史。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 无名杀式AI评估器；使用公开身份得到稳定忠反态度。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 自身获得1张牌与回复1点体力的统一收益；后者必须严格等于前者的2倍。
	var one_card_value: float = evaluator.score_resource_change(snapshot, 0, 0, 1, 0)
	var one_hp_value: float = evaluator.score_resource_change(snapshot, 0, 0, 0, 1)
	if not is_equal_approx(one_hp_value, one_card_value * 2.0):
		return _fail("ai_resource_ratio card=%.2f hp=%.2f" % [one_card_value, one_hp_value])
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
	# 范围内唯一敌对角色已经横置；疾雨应优先选择横置分支，不再担心新增未横置敌方连环目标。
	_controller.state.get_player(1).chained = true
	# 更新后的权威快照；横置状态必须在评分前重新序列化。
	var chained_enemy_snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 全敌对候选横置请求；使用反贼作为唯一范围候选。
	var chained_enemy_request: Dictionary = {"context":{"kind":"jiyu_target_option", "target_id":2, "redirect_target_ids":[1]}}
	if jiyu.score_ai_choice(chained_enemy_snapshot, chained_enemy_request, redirect_action, evaluator) <= jiyu.score_ai_choice(chained_enemy_snapshot, chained_enemy_request, direct_action, evaluator):
		return _fail("jiyu_ai_all_hostiles_chained")
	# 永屹静态AI技能；可命中敌方的【杀】应使额外出牌收益高于1点自伤代价。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	yongyi.bind(null, 0)
	# 永屹额外出牌确认请求；显式写入1张可用牌与可命中敌方【杀】。
	var play_request: Dictionary = {"context":{"kind":"yongyi_play_phase_confirm", "usable_card_count":1, "enemy_slash_available":true}}
	# 零牌确认动作；只有技能计算的净收益决定是否发动。
	var confirm_action: Dictionary = {"payload":{"confirmed":true}}
	if yongyi.score_ai_choice(snapshot, play_request, confirm_action, evaluator) <= 0.0:
		return _fail("yongyi_ai_extra_play")
	# 4体力且无护盾时，固定摸1张牌与实际失去1点体力的基础资源值相抵，不应压过取消动作。
	var draw_only_play_request: Dictionary = {"context":{"kind":"yongyi_play_phase_confirm", "usable_card_count":0, "enemy_slash_available":false}}
	if yongyi.score_ai_choice(snapshot, draw_only_play_request, confirm_action, evaluator) > 0.0:
		return _fail("yongyi_ai_draw_only")
	# 1体力无护盾快照；确认会因1点自伤进入濒死，必须获得稳定的强负分。
	_controller.state.get_player(0).hp = 1
	# 致命自伤AI快照；重新序列化确保评分读取最新体力与护盾。
	var lethal_self_damage_snapshot: Dictionary = _controller.state.to_dict(0, true)
	if yongyi.score_ai_choice(lethal_self_damage_snapshot, play_request, confirm_action, evaluator) > -50.0:
		return _fail("yongyi_ai_lethal_self_damage")
	# 焕发静态AI；娜塔莎只有黑色【闪】时没有可用手牌，也不满足药理的红色材料条件。
	_reset_state(3)
	_controller.state.get_player(0).character_id = "natasha"
	_add_hand_card(0, "shan", "spade", 2)
	var huanfa: SkillDefinition = GameDatabase.create_skill("huanfa")
	huanfa.bind(null, 0)
	var huanfa_confirm_request: Dictionary = {"context":{"kind":"huanfa_confirm", "target_id":0}}
	var no_opportunity_snapshot: Dictionary = _controller.state.to_dict(0, true)
	if huanfa.score_ai_choice(no_opportunity_snapshot, huanfa_confirm_request, confirm_action, evaluator) >= 0.0:
		return _fail("huanfa_ai_self_without_usable_card")
	# 焕发正式选择策略；通用选择评分会额外提供微弱基础分，因此必须验证技能负分能让AI真正提交取消。
	var huanfa_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	# 焕发取消动作；confirmed=false表示保留本轮技能次数。
	var huanfa_pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":7301, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 焕发确认动作；零材料选择依靠confirmed=true区分发动。
	var huanfa_policy_confirm_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":7301, "selected_card_uids":[], "selected_target_ids":[], "confirmed":true}}
	# 自身无行动机会请求；完整技能归属字段使基础策略加载焕发专属评分器。
	var huanfa_self_policy_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":0, "candidates":[], "context":{"kind":"huanfa_confirm", "target_id":0, "skill_id":"huanfa", "skill_owner_id":0, "ai_allow_confirm":true}}
	var huanfa_self_policy_choice: Dictionary = huanfa_policy.choose_card_choice(no_opportunity_snapshot, huanfa_self_policy_request, [huanfa_pass_action, huanfa_policy_confirm_action])
	if bool((huanfa_self_policy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("huanfa_policy_self_without_usable_card=%s" % [huanfa_self_policy_choice])
	# 敌方持有可用【杀】；即使额外阶段本身有行动空间，娜塔莎也不能把每轮一次技能交给敌方。
	_add_hand_card(1, "sha", "spade", 9)
	var enemy_opportunity_snapshot: Dictionary = _controller.state.to_dict(0, true)
	var huanfa_enemy_policy_request: Dictionary = huanfa_self_policy_request.duplicate(true)
	(huanfa_enemy_policy_request.get("context", {}) as Dictionary)["target_id"] = 1
	var huanfa_enemy_policy_choice: Dictionary = huanfa_policy.choose_card_choice(enemy_opportunity_snapshot, huanfa_enemy_policy_request, [huanfa_pass_action, huanfa_policy_confirm_action])
	if bool((huanfa_enemy_policy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("huanfa_policy_enemy=%s" % [huanfa_enemy_policy_choice])
	# 忠臣空手时不应凭空获得额外阶段收益；加入一张可使用【杀】后才恢复正向发动价值。
	huanfa_confirm_request["context"] = {"kind":"huanfa_confirm", "target_id":2}
	if huanfa.score_ai_choice(no_opportunity_snapshot, huanfa_confirm_request, confirm_action, evaluator) > 0.0:
		return _fail("huanfa_ai_empty_friend")
	_add_hand_card(2, "sha", "spade", 7)
	var friend_with_playable_card_snapshot: Dictionary = _controller.state.to_dict(0, true)
	if huanfa.score_ai_choice(friend_with_playable_card_snapshot, huanfa_confirm_request, confirm_action, evaluator) <= 0.0:
		return _fail("huanfa_ai_friend_with_playable_card")
	# 冥谶静态AI；选择自身会保留同回合再次失去最后手牌后的发动空间，选择敌方会使技能失效至回合结束。
	_reset_state(3)
	var mingchen: SkillDefinition = GameDatabase.create_skill("mingchen")
	mingchen.bind(null, 0)
	var mingchen_snapshot: Dictionary = _controller.state.to_dict(0, true)
	var mingchen_request: Dictionary = {"context":{"kind":"mingchen_target"}}
	var mingchen_self_action: Dictionary = {"payload":{"confirmed":true, "selected_target_ids":[0]}}
	var mingchen_enemy_action: Dictionary = {"payload":{"confirmed":true, "selected_target_ids":[1]}}
	if mingchen.score_ai_choice(mingchen_snapshot, mingchen_request, mingchen_self_action, evaluator) <= mingchen.score_ai_choice(mingchen_snapshot, mingchen_request, mingchen_enemy_action, evaluator):
		return _fail("mingchen_ai_preserve_retrigger self=%.2f enemy=%.2f" % [mingchen.score_ai_choice(mingchen_snapshot, mingchen_request, mingchen_self_action, evaluator), mingchen.score_ai_choice(mingchen_snapshot, mingchen_request, mingchen_enemy_action, evaluator)])
	return true


## 验证五名新武将、十项技能和三项势力的静态资料，同时校验主要阶段目录保持固定顺序。
func _test_hsr_character_metadata_and_rule_catalog() -> bool:
	# 新武将元数据期望；顺序同时决定技能栏展示与运行时安装次序。
	var expected_characters: Dictionary = {
		"misha":["pinuokangni", "male", 3, ["huanying", "chuanchong"]],
		"alan":["xingjianhuanyv", "male", 4, ["qingli", "qianggong"]],
		"aisida":["yinhexvezhe", "female", 3, ["xingqi", "xingluo"]],
		"heita":["yinhexvezhe", "female", 3, ["zhishi", "jiqiao"]],
		"xiluwa":["beiluoboge", "female", 3, ["xianzou", "anke"]],
		"moze":["xianzhou", "male", 2, ["youfeng", "lvexi", "yingchu"]],
	}
	for character_id_variant: Variant in expected_characters.keys():
		# 当前武将稳定ID；字典键转换为字符串后读取自动索引定义。
		var character_id: String = str(character_id_variant)
		# 当前武将期望数组；依次保存势力、性别、体力和技能ID数组。
		var expectation: Array = expected_characters[character_id] as Array
		# 当前武将静态定义；数据库必须已扫描对应GD文件并保留全部字段。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		if str(character_definition.get("faction", "")) != str(expectation[0]) or str(character_definition.get("gender", "")) != str(expectation[1]) or int(character_definition.get("max_hp", 0)) != int(expectation[2]) or (character_definition.get("skills", []) as Array) != (expectation[3] as Array):
			return _fail("hsr_character_metadata id=%s definition=%s" % [character_id, character_definition])
	# 新势力展示资料期望；颜色固定为主公指定的金、淡灰与紫色十六进制值。
	var expected_factions: Dictionary = {
		"pinuokangni":["匹诺康尼", "匹", "d6ad45"],
		"xingjianhuanyv":["星间寰宇", "星", "c7c9ce"],
		"yinhexvezhe":["银河学者", "学", "8a63b8"],
	}
	for faction_id_variant: Variant in expected_factions.keys():
		# 当前势力稳定ID；与武将faction字段一一对应。
		var faction_id: String = str(faction_id_variant)
		# 当前势力期望数组；依次保存全称、简称与无井号颜色值。
		var faction_expectation: Array = expected_factions[faction_id] as Array
		# 当前势力定义；由factions.json自动载入。
		var faction_definition: Dictionary = GameDatabase.get_faction(faction_id)
		if str(faction_definition.get("display_name", "")) != str(faction_expectation[0]) or str(faction_definition.get("short_name", "")) != str(faction_expectation[1]) or str(faction_definition.get("color", "")) != str(faction_expectation[2]):
			return _fail("hsr_faction_metadata id=%s definition=%s" % [faction_id, faction_definition])
	# 主公钦定的技能原文；逐项精确比较，防止玩家面板文字在后续重构中被改写。
	var expected_descriptions: Dictionary = {
		"huanying":"锁定技，你的回合外，当你受到伤害后，你移出游戏直到本回合结束。",
		"chuanchong":"出牌阶段限一次，你可将一张红桃/方块/黑桃/梅花手牌当【顺手牵羊】/【无中生有】/【过河拆桥】/【借刀杀人】使用。",
		"qingli":"你可以失去1点体力并视为使用或打出一张雷【杀】。",
		"qianggong":"当你使用【杀】指定目标时，你可以弃置一张牌，若此牌为红色，此【杀】不可被【闪】响应；若此牌为黑色，此【杀】伤害+1；若此牌为武器牌，则以上两项均执行。",
		"xingqi":"准备阶段，你可以观看牌堆顶的X张牌，然后令一名角色获得其中一张锦囊牌，并将其余的牌以任意顺序放回牌堆顶或牌堆底。（X为场上存活角色数，且至多为5。）",
		"xingluo":"出牌阶段限一次，你可以重铸你与至多两名其他角色各一张手牌。若这些牌：类型均为锦囊牌，你摸两张牌；颜色均为红色，你摸一张牌。",
		"zhishi":"当你使用锦囊牌时，你可以摸一张牌。",
		"jiqiao":"锁定技，你使用锦囊牌没有距离限制。其他角色不可弃置你装备区内的防具牌与宝物牌。",
		"xianzou":"每个主要阶段开始时，你可以重铸一张手牌并跳过该阶段，若为弃牌阶段，你将手牌数调整至X。每轮每种花色限一次。（X等于你的当前体力值。）",
		"anke":"回合结束时，若本回合内有四种花色的牌进入过弃牌堆，你可执行一个额外的回合。每轮限三次。",
		"youfeng":"离场技，锁定技，每轮开始时，你弃置一名其他角色的一张牌并令其获得“猎物”标记，然后若你未处于离场状态，你离场；若你已处于离场状态，你失去1点体力。",
		"lvexi":"离场技，锁定技，你计算与拥有“猎物”标记的角色距离为1，且其不可响应你使用的牌。当拥有“猎物”标记的角色受到伤害后，若你处于离场状态，你返场并对其造成1点伤害。当拥有“猎物”标记的角色死亡时，你摸两张牌并返场。",
		"yingchu":"离场技，锁定技，当你上家的回合结束时，若你处于离场状态，你返场；该回合结束时，你再次离场。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；用于读取数据目录自动注册的说明文本。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("hsr_skill_description id=%s" % skill_id)
	if RuleTimingCatalog.MAIN_PHASES != ["judgment", "draw", "play", "discard"] or RuleTimingCatalog.is_main_phase("start") or not RuleTimingCatalog.is_main_phase("discard"):
		return _fail("main_phase_catalog=%s" % [RuleTimingCatalog.MAIN_PHASES])
	return true


## 验证离场角色不参与规则与输入，并验证双行牌堆排序和调整手牌数均按公开端口执行。
func _test_out_of_game_pile_arrangement_and_ui() -> bool:
	_reset_state(3)
	# 当前攻击牌；用于确认移出游戏的角色不能再成为实体牌的合法目标。
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	# 离场角色手牌计数；离场后执行摸牌必须保持该数量不变。
	var removed_player: PlayerState = _controller.state.get_player(1)
	# 为离场摸牌断言预置的牌堆顶实体；其不能被离场角色取得。
	var guarded_draw_card: CardInstance = _add_draw_pile_card("shan", "heart", 8)
	if not _controller.remove_player_from_game(1, "new_character_test") or not removed_player.out_of_game:
		return _fail("remove_player_from_game")
	if _controller.card_rules.validate_use(0, slash_card, [1]).is_empty() or _controller.state.get_alive_players().size() != 2:
		return _fail("out_of_game_targeting")
	var removed_hand_count: int = removed_player.hand.size()
	_controller.draw(1, 1)
	if removed_player.hand.size() != removed_hand_count or not _controller.state.draw_pile.has(guarded_draw_card):
		return _fail("out_of_game_draw hand=%d/%d" % [removed_player.hand.size(), removed_hand_count])
	# 正式武将牌场景；以真实输入组件验证离场表现既透明又不可点击。
	var removed_player_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	add_child(removed_player_view)
	await get_tree().process_frame
	# 离场公开快照；字段与正式网络快照保持一致。
	var removed_snapshot: Dictionary = {"player_id":1, "display_name":"离场测试", "character_id":"misha", "identity":"rebel", "hp":3, "max_hp":3, "shield":0, "alive":true, "out_of_game":true, "chained":false, "face_down":false, "hand_count":0, "equipment":{}, "judgment_area":[], "wooden_ox_storage_count":0}
	removed_player_view.configure_snapshot(removed_snapshot, GameDatabase.get_character("misha"))
	if removed_player_view.is_interactable or not is_equal_approx(removed_player_view.modulate.a, removed_player_view.out_of_game_modulate.a):
		removed_player_view.queue_free()
		return _fail("out_of_game_view interactable=%s alpha=%s" % [removed_player_view.is_interactable, removed_player_view.modulate.a])
	# 离场武将牌状态文字；离场仍是存活角色，不能把透明表现误画为真实阵亡。
	var removed_death_label: Label = removed_player_view.get_node("StateOverlay/DeathLabel") as Label
	if removed_death_label == null or removed_death_label.visible:
		removed_player_view.queue_free()
		return _fail("out_of_game_death_label visible=%s" % [removed_death_label.visible if removed_death_label != null else true])
	removed_player_view.queue_free()
	if not _controller.restore_player_to_game(1, "new_character_test") or removed_player.out_of_game:
		return _fail("restore_player_to_game")
	_reset_state(2)
	# 未参与排序的原牌堆底部实体；排序后必须保持在四张观看牌之间的相对位置。
	var untouched_card: CardInstance = _add_draw_pile_card("tao", "heart", 3)
	# 牌堆底行左侧实体；最终应比右侧实体更靠近牌堆顶。
	var bottom_left_card: CardInstance = _add_draw_pile_card("shan", "club", 4)
	# 牌堆底行右侧实体；最终应成为四张观看牌中最底部的实体。
	var bottom_right_card: CardInstance = _add_draw_pile_card("sha", "spade", 5)
	# 牌堆顶行右侧实体；最终位于顶行左侧实体之下。
	var top_right_card: CardInstance = _add_draw_pile_card("wuzhong", "diamond", 6)
	# 牌堆顶行左侧实体；最终必须成为实际牌堆顶。
	var top_left_card: CardInstance = _add_draw_pile_card("guohe", "spade", 7)
	var ordered_uids: Array[int] = [top_left_card.uid, top_right_card.uid, bottom_left_card.uid, bottom_right_card.uid]
	if not _controller.arrange_draw_pile_cards(ordered_uids, 2, "new_character_test"):
		return _fail("pile_arrangement_rejected")
	# 牌堆真实数组UID顺序；数组末尾是实际牌堆顶。
	var arranged_uids: Array[int] = []
	for draw_card: CardInstance in _controller.state.draw_pile:
		arranged_uids.append(draw_card.uid)
	var expected_arranged_uids: Array[int] = [bottom_right_card.uid, bottom_left_card.uid, untouched_card.uid, top_right_card.uid, top_left_card.uid]
	if arranged_uids != expected_arranged_uids:
		return _fail("pile_arrangement_order actual=%s expected=%s" % [arranged_uids, expected_arranged_uids])
	# 调整手牌前的唯一手牌；后续先补足到三张，再通过统一选择弃至一张。
	var initial_hand_card: CardInstance = _add_hand_card(0, "shan", "heart", 9)
	if not _controller.adjust_hand_size(0, 3) or _controller.state.get_player(0).hand.size() != 3:
		return _fail("adjust_hand_size_draw hand=%d" % _controller.state.get_player(0).hand.size())
	var discard_uids: Array[int] = [initial_hand_card.uid, _controller.state.get_player(0).hand[1].uid]
	if not _controller.adjust_hand_size(0, 1) or not _submit_pending_choice(0, discard_uids, [], true):
		return false
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("adjust_hand_size_discard hand=%d" % _controller.state.get_player(0).hand.size())
	return true


## 验证私有观看的不可选牌保持可见暗置，受保护牌展示遵循同一机制，且排序拖拽重建节点后安全结束输入。
func _test_card_selection_panel_disabled_cards_and_arrangement_drag() -> bool:
	# 正式通用选牌面板；必须挂入场景树才能让CardView和CardInputArea完成输入节点初始化。
	var card_selection_panel: CardSelectionPanel = CARD_SELECTION_PANEL_SCENE.instantiate() as CardSelectionPanel
	add_child(card_selection_panel)
	await get_tree().process_frame
	# 星祈观看到的非锦囊牌；需要展示但不得进入本次权威选择候选。
	var xingqi_non_trick_candidate: Dictionary = {"uid":99001, "owner_id":-1, "zone":"processing", "visible":true, "card_data":{"uid":99001, "definition_id":"shan", "suit":"club", "rank":4}}
	# 星祈观看到的锦囊牌；本次唯一可选择的候选。
	var xingqi_trick_candidate: Dictionary = {"uid":99002, "owner_id":-1, "zone":"processing", "visible":true, "card_data":{"uid":99002, "definition_id":"wuzhong", "suit":"heart", "rank":5}}
	# 私有观看请求；display_candidates完整显示两张牌，candidates只授予锦囊牌权威选择权。
	var xingqi_choice_request: Dictionary = {"request_id":990, "title":"星祈", "prompt":"请选择其中一张锦囊牌", "choice_type":"card", "candidates":[xingqi_trick_candidate], "min_select":1, "max_select":1, "allow_cancel":true, "context":{"kind":"xingqi_trick", "display_candidates":[xingqi_non_trick_candidate, xingqi_trick_candidate]}}
	card_selection_panel.show_request(xingqi_choice_request)
	await get_tree().process_frame
	# 非锦囊正式牌面；不可交互状态会由CardView统一压暗插画、纸张与文字。
	var xingqi_non_trick_view: CardView = card_selection_panel._card_views.get(99001) as CardView
	# 锦囊正式牌面；应保持可点选，证明展示候选没有误把全部牌暗置。
	var xingqi_trick_view: CardView = card_selection_panel._card_views.get(99002) as CardView
	if xingqi_non_trick_view == null or xingqi_non_trick_view.is_interactable or not bool(xingqi_non_trick_view.get("_dim_when_disabled")) or xingqi_trick_view == null or not xingqi_trick_view.is_interactable:
		card_selection_panel.queue_free()
		return _fail("xingqi_disabled_presentation non_trick=%s trick=%s" % [xingqi_non_trick_view.is_interactable if xingqi_non_trick_view != null else true, xingqi_trick_view.is_interactable if xingqi_trick_view != null else false])
	# 机巧受保护防具；与可弃置武器共同展示时必须保持可见但不可选。
	var protected_armor_candidate: Dictionary = {"uid":99003, "owner_id":1, "zone":"equipment", "slot":"armor", "visible":true, "card_data":{"uid":99003, "definition_id":"bagua", "suit":"club", "rank":9}}
	# 同一装备区的普通武器；作为权威候选保留可点击状态。
	var discardable_weapon_candidate: Dictionary = {"uid":99004, "owner_id":1, "zone":"equipment", "slot":"weapon", "visible":true, "card_data":{"uid":99004, "definition_id":"qinggang", "suit":"spade", "rank":10}}
	# 外部弃置请求；只有武器进入candidates，防具仅通过display_candidates展示暗置状态。
	var discard_choice_request: Dictionary = {"request_id":991, "title":"选择弃置牌", "prompt":"请选择目标区域内的一张牌", "choice_type":"card", "candidates":[discardable_weapon_candidate], "min_select":1, "max_select":1, "allow_cancel":false, "context":{"kind":"discard_target", "display_candidates":[protected_armor_candidate, discardable_weapon_candidate]}}
	card_selection_panel.show_request(discard_choice_request)
	await get_tree().process_frame
	# 受保护防具与可弃置武器的正式牌面；暗置不能只依赖实际点击校验，必须在视觉上可辨认。
	var protected_armor_view: CardView = card_selection_panel._card_views.get(99003) as CardView
	var discardable_weapon_view: CardView = card_selection_panel._card_views.get(99004) as CardView
	if protected_armor_view == null or protected_armor_view.is_interactable or not bool(protected_armor_view.get("_dim_when_disabled")) or discardable_weapon_view == null or not discardable_weapon_view.is_interactable:
		card_selection_panel.queue_free()
		return _fail("jiqiao_disabled_presentation armor=%s weapon=%s" % [protected_armor_view.is_interactable if protected_armor_view != null else true, discardable_weapon_view.is_interactable if discardable_weapon_view != null else false])
	# 双行排序请求；两张牌均为正式可拖动候选，确保释放回调会重建其所在行。
	var arrangement_choice_request: Dictionary = {"request_id":992, "title":"排序", "prompt":"请调整牌堆", "choice_type":"arrange", "candidates":[xingqi_non_trick_candidate, xingqi_trick_candidate], "min_select":2, "max_select":2, "allow_cancel":false, "context":{"kind":"test_arrangement"}}
	card_selection_panel.show_request(arrangement_choice_request)
	await get_tree().process_frame
	# 当前排序牌面；取其真实输入区模拟一次已经开始的鼠标拖拽释放。
	var arrangement_card_view: CardView = card_selection_panel._card_views.get(99001) as CardView
	var arrangement_input_area: CardInputArea = arrangement_card_view.get_node("InputArea") as CardInputArea if arrangement_card_view != null else null
	if arrangement_input_area == null:
		card_selection_panel.queue_free()
		return _fail("arrangement_input_missing")
	# 鼠标释放事件；在hand_drag_finished同步重建旧CardView后，旧输入节点不再拥有视口也不能报错。
	var drag_release_event: InputEventMouseButton = InputEventMouseButton.new()
	drag_release_event.button_index = MOUSE_BUTTON_LEFT
	drag_release_event.pressed = false
	arrangement_input_area._pointer_pressed = true
	arrangement_input_area._is_hand_dragging = true
	arrangement_input_area._input(drag_release_event)
	await get_tree().process_frame
	if card_selection_panel._arrangement_top_uids.size() + card_selection_panel._arrangement_bottom_uids.size() != 2:
		card_selection_panel.queue_free()
		return _fail("arrangement_drag_release rows=%s/%s" % [card_selection_panel._arrangement_top_uids, card_selection_panel._arrangement_bottom_uids])
	card_selection_panel.queue_free()
	return true


## 验证目标区域选牌提示以金色富文本强调公开武将名，不影响请求的普通文字或选择协议。
func _test_target_zone_prompt_highlight() -> bool:
	# 正式选择面板实例；必须从运行时场景取得富文本标签，避免仅测试格式化字符串而漏掉渲染配置。
	var card_selection_panel: CardSelectionPanel = CARD_SELECTION_PANEL_SCENE.instantiate() as CardSelectionPanel
	add_child(card_selection_panel)
	await get_tree().process_frame
	# 目标区域展示请求；候选为空即可验证提示渲染，选择资格仍由其他专项场景覆盖。
	var target_zone_request: Dictionary = {"request_id":95001, "title":"选择获得牌", "prompt":"请选择“丹恒”区域内的一张牌", "prompt_highlight":"丹恒", "candidates":[], "min_select":0, "max_select":0, "allow_cancel":true}
	card_selection_panel.show_request(target_zone_request)
	await get_tree().process_frame
	# 实际富文本提示标签；颜色标签必须使用统一金色，名称外的文本保持普通提示内容。
	var prompt_label: RichTextLabel = card_selection_panel.get("_prompt_label") as RichTextLabel
	if prompt_label == null or not prompt_label.text.contains("[color=#e4c84f]丹恒[/color]") or not prompt_label.text.contains("请选择"):
		card_selection_panel.queue_free()
		return _fail("target_zone_prompt_highlight:%s" % [prompt_label.text if prompt_label != null else "missing"])
	card_selection_panel.queue_free()
	return true


## 验证【幻影】的离场回归、【倾力】的无材料雷杀和【强攻】的红黑武器三种强化分支。
func _test_misha_and_alan_skills() -> bool:
	_reset_state(2)
	# 幻影持有者；二号位在一号位回合内受伤后应暂时离场。
	var huanying: SkillDefinition = _install_single_skill(1, "huanying")
	if huanying == null:
		return _fail("huanying_missing")
	_controller.damage(0, 1, 1, "normal", "sha")
	if not _controller.state.get_player(1).out_of_game:
		return _fail("huanying_remove")
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	if _controller.state.get_player(1).out_of_game:
		return _fail("huanying_restore")
	_reset_state(2)
	# 遗漏结束边界的异常流程；下一回合开始必须作为兜底让仍在场外的幻影持有者返场。
	huanying = _install_single_skill(1, "huanying")
	if huanying == null:
		return _fail("huanying_fallback_missing")
	_controller.damage(0, 1, 1, "normal", "sha")
	if not _controller.state.get_player(1).out_of_game:
		return _fail("huanying_fallback_remove")
	_controller._emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":_controller.state.turn_number + 1})
	if _controller.state.get_player(1).out_of_game:
		return _fail("huanying_phase_before_fallback")
	_reset_state(2)
	# 方块传冲材料；点击技能后应直接创建牌目标组合请求，并把实体牌按【无中生有】规则对自身使用。
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	var chuanchong_material: CardInstance = _add_hand_card(0, "shan", "diamond", 6)
	_add_draw_pile_card("sha", "heart", 7)
	_add_draw_pile_card("shan", "club", 8)
	var chuanchong: SkillDefinition = _install_single_skill(0, "chuanchong")
	if chuanchong == null or not chuanchong.activate().is_empty():
		return _fail("chuanchong_activate")
	var chuanchong_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var chuanchong_context: Dictionary = chuanchong_choice.get("context", {}) as Dictionary
	var chuanchong_target_combinations: Dictionary = chuanchong_context.get("target_combinations_by_card_id", {}) as Dictionary
	var chuanchong_material_combinations: Array = chuanchong_target_combinations.get(str(chuanchong_material.uid), []) as Array
	# 方块材料的自身目标预填；界面读取此映射后无需玩家额外点击自己。
	var chuanchong_auto_targets: Array = ((chuanchong_context.get("auto_target_ids_by_card_id", {}) as Dictionary).get(str(chuanchong_material.uid), []) as Array)
	if str(chuanchong_choice.get("choice_type", "")) != "card_target" or str(chuanchong_context.get("kind", "")) != "chuanchong_use" or chuanchong_material_combinations != [[0]] or chuanchong_auto_targets != [0]:
		return _fail("chuanchong_card_target_choice choice=%s" % [chuanchong_choice])
	if not _submit_pending_choice(0, [chuanchong_material.uid], [0], true):
		return false
	if _controller.state.get_player(0).hand.has(chuanchong_material) or not bool(chuanchong.get("_used_current_play_phase")):
		return _fail("chuanchong_virtual_use hand=%s used=%s" % [_controller.state.get_player(0).hand, chuanchong.get("_used_current_play_phase")])
	_reset_state(3)
	# 梅花传冲材料；转化【借刀杀人】时必须按“持刀者、被杀者”保存有序双目标组合。
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	var borrow_sword_material: CardInstance = _add_hand_card(0, "shan", "club", 9)
	# 借刀持刀者的武器实体；二号位装备后才可成为借刀第一目标。
	var borrow_sword_weapon: CardInstance = CardInstance.new("qinggang", "spade", 10)
	borrow_sword_weapon.zone = "equipment"
	borrow_sword_weapon.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = borrow_sword_weapon
	var borrow_sword_chuanchong: SkillDefinition = _install_single_skill(0, "chuanchong")
	if borrow_sword_chuanchong == null or not borrow_sword_chuanchong.activate().is_empty():
		return _fail("chuanchong_borrow_sword_activate")
	var borrow_sword_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var borrow_sword_context: Dictionary = borrow_sword_choice.get("context", {}) as Dictionary
	var borrow_sword_combinations: Array = ((borrow_sword_context.get("target_combinations_by_card_id", {}) as Dictionary).get(str(borrow_sword_material.uid), []) as Array)
	if borrow_sword_combinations.is_empty() or not borrow_sword_combinations.has([1, 2]):
		return _fail("chuanchong_borrow_sword_combinations=%s" % [borrow_sword_combinations])
	# 伪造的反向顺序；第一名不是持刀者时必须由材料专属完整组合校验拒绝，且原请求保持等待。
	var invalid_borrow_sword_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	invalid_borrow_sword_action.payload = {"request_id":int(borrow_sword_choice.get("request_id", -1)), "selected_card_uids":[borrow_sword_material.uid], "selected_target_ids":[2, 1], "confirmed":true}
	if _controller.submit_action(invalid_borrow_sword_action) or _controller._pending_card_choice.is_empty():
		return _fail("chuanchong_borrow_sword_order_validation")
	if not _submit_pending_choice(0, [], [], false):
		return false
	_reset_state(2)
	# 倾力测试前的正式规则服务；技能距离和次数查询应经过控制器钩子。
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	# 倾力持有者；主动雷杀会失去一点体力并对无响应目标造成一点雷属性伤害。
	var qingli: SkillDefinition = GameDatabase.create_skill("qingli")
	qingli.bind(_controller, 0)
	var qingli_result: String = qingli.activate({"target_ids":[1]})
	if _controller.has_pending_card_choice() and not _submit_pending_choice(1, [], [], false):
		return false
	if not qingli_result.is_empty() or _controller.state.get_player(0).hp != 3 or _controller.state.get_player(1).hp != 3:
		return _fail("qingli_virtual_slash result=%s hp=%d/%d" % [qingli_result, _controller.state.get_player(0).hp, _controller.state.get_player(1).hp])
	# 仅剩1点体力时仍允许在响应窗口发动；失去体力后的濒死与父响应恢复交由统一续接处理。
	_controller.state.get_player(0).hp = 1
	if not qingli.can_activate({"active_entry":"chooseToRespond", "response_patterns":["sha"]}):
		return _fail("qingli_one_hp_response_disabled")
	_reset_state(2)
	# 红色强攻费用；应只写入不可响应的直击目标。
	var qianggong_red: SkillDefinition = GameDatabase.create_skill("qianggong")
	qianggong_red.bind(_controller, 0)
	var red_cost: CardInstance = _add_hand_card(0, "shan", "heart", 10)
	_controller._card_use_contexts[9101] = {"target_ids":[1], "direct_hit_target_ids":[], "custom_args":{}}
	var red_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	red_response.card_ids = [red_cost.uid]
	qianggong_red.continue_selection({"kind":"qianggong_cost", "card_uid":9101, "target_id":1}, red_response)
	var red_context: Dictionary = _controller._card_use_contexts[9101] as Dictionary
	if not (red_context.get("direct_hit_target_ids", []) as Array).has(1) or _controller.get_card_target_damage_bonus(9101, 1) != 0:
		return _fail("qianggong_red context=%s" % [red_context])
	_reset_state(2)
	# 黑色强攻费用；应只为该目标增加一点伤害。
	var qianggong_black: SkillDefinition = GameDatabase.create_skill("qianggong")
	qianggong_black.bind(_controller, 0)
	var black_cost: CardInstance = _add_hand_card(0, "shan", "spade", 11)
	_controller._card_use_contexts[9102] = {"target_ids":[1], "direct_hit_target_ids":[], "custom_args":{}}
	var black_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	black_response.card_ids = [black_cost.uid]
	qianggong_black.continue_selection({"kind":"qianggong_cost", "card_uid":9102, "target_id":1}, black_response)
	var black_context: Dictionary = _controller._card_use_contexts[9102] as Dictionary
	if (black_context.get("direct_hit_target_ids", []) as Array).has(1) or _controller.get_card_target_damage_bonus(9102, 1) != 1:
		return _fail("qianggong_black context=%s" % [black_context])
	_reset_state(2)
	# 武器强攻费用；武器自身颜色不影响“直击与增伤同时执行”的专属规则。
	var qianggong_weapon: SkillDefinition = GameDatabase.create_skill("qianggong")
	qianggong_weapon.bind(_controller, 0)
	var weapon_cost: CardInstance = CardInstance.new("qinggang", "spade", 12)
	weapon_cost.zone = "equipment"
	weapon_cost.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = weapon_cost
	_controller._card_use_contexts[9103] = {"target_ids":[1], "direct_hit_target_ids":[], "custom_args":{}}
	var weapon_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	weapon_response.card_ids = [weapon_cost.uid]
	qianggong_weapon.continue_selection({"kind":"qianggong_cost", "card_uid":9103, "target_id":1}, weapon_response)
	var weapon_context: Dictionary = _controller._card_use_contexts[9103] as Dictionary
	if not (weapon_context.get("direct_hit_target_ids", []) as Array).has(1) or _controller.get_card_target_damage_bonus(9103, 1) != 1:
		return _fail("qianggong_weapon context=%s" % [weapon_context])
	return true


## 验证艾丝妲、黑塔与希露瓦的私有选牌、重铸奖励、装备保护、主要阶段跳过和额外回合确认。
func _test_aisida_heita_xiluwa_skills() -> bool:
	_reset_state(3)
	# 星祈观看的非锦囊余牌；在锦囊分配后进入双行牌堆排序请求。
	var xingqi_remaining_card: CardInstance = _add_draw_pile_card("shan", "club", 4)
	# 星祈观看的锦囊牌；本测试将其交给二号角色。
	var xingqi_trick_card: CardInstance = _add_draw_pile_card("wuzhong", "heart", 5)
	var xingqi: SkillDefinition = _install_single_skill(0, "xingqi")
	if xingqi == null:
		return _fail("xingqi_missing")
	_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	# 星祈首段私有请求；非锦囊牌必须留在展示候选中但不能进入权威可选集合。
	var xingqi_initial_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var xingqi_selectable_candidates: Array = xingqi_initial_choice.get("candidates", []) as Array
	var xingqi_display_candidates: Array = (xingqi_initial_choice.get("context", {}) as Dictionary).get("display_candidates", []) as Array
	if xingqi_selectable_candidates.size() != 1 or int((xingqi_selectable_candidates[0] as Dictionary).get("uid", -1)) != xingqi_trick_card.uid or xingqi_display_candidates.size() != 2:
		return _fail("xingqi_display_candidates selectable=%s display=%s" % [xingqi_selectable_candidates, xingqi_display_candidates])
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [xingqi_trick_card.uid], [], true):
		return _fail("xingqi_trick_choice")
	if not _submit_pending_choice(0, [], [1], true):
		return false
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [xingqi_remaining_card.uid], [], true, "top_count_1"):
		return _fail("xingqi_arrangement_choice")
	if not _controller.state.get_player(1).hand.has(xingqi_trick_card) or _controller.state.draw_pile.back() != xingqi_remaining_card:
		return _fail("xingqi_result target_hand=%s top=%s" % [_controller.state.get_player(1).hand, _controller.state.draw_pile.back().uid if not _controller.state.draw_pile.is_empty() else -1])
	_reset_state(3)
	# 星落相邻选牌必须使用非零流程间隔，才能复现空窗期误开 chooseToUse 的卡死路径。
	_controller.game_flow_interval_seconds = 0.05
	# 星落自身与其他角色的红色锦囊；两项条件同时满足时持有者累计摸三张。
	var xingluo_self_card: CardInstance = _add_hand_card(0, "wuzhong", "heart", 6)
	var xingluo_first_other_card: CardInstance = _add_hand_card(1, "guohe", "diamond", 7)
	var xingluo_second_other_card: CardInstance = _add_hand_card(2, "shunshou", "heart", 8)
	for draw_rank: int in range(1, 7):
		_add_draw_pile_card("shan", "club", draw_rank)
	var xingluo: SkillDefinition = _install_single_skill(0, "xingluo")
	if xingluo == null or not xingluo.activate({"target_ids":[1, 2]}).is_empty():
		return _fail("xingluo_activate")
	if not _submit_pending_choice(0, [xingluo_self_card.uid], [], true):
		return false
	# 相邻重铸选择必须经过全局流程间隔，避免自身与其他角色的选牌弹窗在同一帧无缝替换。
	if _controller.has_pending_card_choice():
		return _fail("xingluo_missing_prompt_interval")
	# 间隔空窗期不得提前打开出牌请求，否则下一段选牌会与孤儿 chooseToUse 冲突并卡住。
	if _controller.call("_has_active_play_choice") or not _controller.has_pending_play_interaction():
		return _fail("xingluo_interval_opened_play_choice")
	await get_tree().create_timer(_controller.game_flow_interval_seconds + 0.05).timeout
	var xingluo_first_other_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if int((xingluo_first_other_choice.get("context", {}) as Dictionary).get("current_player_id", -1)) != 1 or not _submit_pending_choice(0, [xingluo_first_other_card.uid], [], true):
		return _fail("xingluo_first_other_choice")
	# 两名其他角色都重铸时，每一段相邻弹窗都使用同一节奏器间隔。
	if _controller.has_pending_card_choice():
		return _fail("xingluo_second_missing_prompt_interval")
	await get_tree().create_timer(_controller.game_flow_interval_seconds + 0.05).timeout
	var xingluo_second_other_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if int((xingluo_second_other_choice.get("context", {}) as Dictionary).get("current_player_id", -1)) != 2 or not _submit_pending_choice(0, [xingluo_second_other_card.uid], [], true):
		return _fail("xingluo_second_other_choice")
	if _controller.state.get_player(0).hand.size() != 4 or _controller.state.get_player(1).hand.size() != 1 or _controller.state.get_player(2).hand.size() != 1:
		return _fail("xingluo_rewards hand=%d/%d/%d" % [_controller.state.get_player(0).hand.size(), _controller.state.get_player(1).hand.size(), _controller.state.get_player(2).hand.size()])
	# 星落整段结束后必须恢复正式出牌窗口，否则出牌阶段会卡在无 chooseToUse 的状态。
	if not _controller.call("_has_active_play_choice") or _controller.has_pending_card_choice() or _controller.has_pending_play_interaction():
		return _fail("xingluo_play_choice_resume active=%s pending=%s interaction=%s" % [_controller.call("_has_active_play_choice"), _controller.has_pending_card_choice(), _controller.has_pending_play_interaction()])
	_reset_state(2)
	# 智识补牌来源；使用锦囊后的确认应只摸一张并保留可取消选择协议。
	var zhishi_draw_card: CardInstance = _add_draw_pile_card("sha", "spade", 8)
	var zhishi: SkillDefinition = _install_single_skill(0, "zhishi")
	if zhishi == null:
		return _fail("zhishi_missing")
	_controller._emit_rule_timing("useCard", 0, 0, 1, {"card_id":"wuzhong", "card_uid":9201})
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [], [], true):
		return _fail("zhishi_choice")
	if not _controller.state.get_player(0).hand.has(zhishi_draw_card):
		return _fail("zhishi_draw")
	# 无懈可击响应实体；该牌属于锦囊，但通过respond而不是useCard生命周期打出。
	var zhishi_wuxie_card: CardInstance = _add_hand_card(0, "wuxie", "club", 12)
	# 无懈可击触发智识后的补牌；响应成功后应恰好进入技能持有者手牌。
	var zhishi_wuxie_draw_card: CardInstance = _add_draw_pile_card("shan", "heart", 9)
	# 实际响应结果；必须由正式响应消费入口移动实体并派发respond时机。
	var consumed_wuxie_card: CardInstance = _controller._consume_response_card_uid(0, zhishi_wuxie_card.uid, "wuxie")
	if consumed_wuxie_card == null or not _controller.has_pending_card_choice() or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "zhishi_confirm":
		return _fail("zhishi_wuxie_trigger response=%s pending=%s" % [consumed_wuxie_card, _controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], true):
		return false
	if not _controller.state.get_player(0).hand.has(zhishi_wuxie_draw_card) or _controller.state.get_player(0).find_hand_card(zhishi_wuxie_card.uid) != null or not _controller.state.discard_pile.has(zhishi_wuxie_card):
		return _fail("zhishi_wuxie_draw hand=%s discard=%s" % [_controller.state.get_player(0).hand, _controller.state.discard_pile])
	_reset_state(4)
	# 机巧规则测试使用真实控制器提供者；距离和弃置保护均需遍历运行时技能表。
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	var jiqiao: SkillDefinition = _install_single_skill(0, "jiqiao")
	# 受保护防具实体；其他角色不得通过权威弃置入口移走。
	var armor_card: CardInstance = CardInstance.new("bagua", "club", 9)
	armor_card.zone = "equipment"
	armor_card.owner_id = 0
	_controller.state.get_player(0).equipment["armor"] = armor_card
	# 受保护宝物实体；与防具共享机巧的外部弃置限制。
	var treasure_card: CardInstance = CardInstance.new("muniu", "diamond", 10)
	treasure_card.zone = "equipment"
	treasure_card.owner_id = 0
	_controller.state.get_player(0).equipment["treasure"] = treasure_card
	# 可弃置武器实体；用于验证受保护防具、宝物仍出现在展示候选中，但只有武器进入权威选择集合。
	var discardable_weapon_card: CardInstance = CardInstance.new("qinggang", "spade", 11)
	discardable_weapon_card.zone = "equipment"
	discardable_weapon_card.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = discardable_weapon_card
	# 距离2的目标手牌；用于验证【顺手牵羊】因机巧解除距离限制仍可合法指定。
	_add_hand_card(2, "shan", "heart", 11)
	if jiqiao == null or _controller.can_discard_player_card(1, 0, armor_card, "equipment", "armor") or _controller.can_discard_player_card(1, 0, treasure_card, "equipment", "treasure") or _controller._discard_selected_player_card(0, armor_card.uid, 1):
		return _fail("jiqiao_protection")
	if _controller.card_rules.validate_virtual_use(0, "shunshou", [2]) != "":
		return _fail("jiqiao_distance")
	# 外部弃置操作改由一号以外的本地选择者发起；请求必须公开三张装备，却只允许提交武器UID。
	_controller.local_human_player_id = 1
	_controller.discard_one_from_player(1, 0)
	var jiqiao_discard_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var jiqiao_display_candidates: Array = (jiqiao_discard_choice.get("context", {}) as Dictionary).get("display_candidates", []) as Array
	var jiqiao_selectable_candidates: Array = jiqiao_discard_choice.get("candidates", []) as Array
	if jiqiao_display_candidates.size() != 3 or jiqiao_selectable_candidates.size() != 1 or int((jiqiao_selectable_candidates[0] as Dictionary).get("uid", -1)) != discardable_weapon_card.uid:
		_controller.local_human_player_id = 0
		return _fail("jiqiao_discard_presentation display=%s selectable=%s" % [jiqiao_display_candidates, jiqiao_selectable_candidates])
	if not _submit_pending_choice(1, [discardable_weapon_card.uid], [], true):
		_controller.local_human_player_id = 0
		return false
	_controller.local_human_player_id = 0
	_reset_state(2)
	# 弦奏用于出牌阶段的梅花手牌；重铸完成后必须写入跳过状态并进入阶段转场。
	var xianzou_cost_card: CardInstance = _add_hand_card(0, "shan", "club", 12)
	_add_draw_pile_card("sha", "heart", 13)
	var xianzou: SkillDefinition = _install_single_skill(0, "xianzou")
	if xianzou == null:
		return _fail("xianzou_missing")
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [xianzou_cost_card.uid], [], true):
		return _fail("xianzou_choice")
	if _controller.state.current_phase != "play_skipped" or not _controller.state.get_player(0).skipped_phases.get("play", false):
		return _fail("xianzou_skip phase=%s skipped=%s" % [_controller.state.current_phase, _controller.state.get_player(0).skipped_phases])
	_controller.game_flow_pacer.cancel_all()
	_reset_state(2)
	# 无可重铸手牌的弦奏；仍必须由玩家亲自取消，禁止以不建立请求的方式泄露当前手牌花色。
	var xianzou_empty: SkillDefinition = _install_single_skill(0, "xianzou")
	if xianzou_empty == null:
		return _fail("xianzou_empty_missing")
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	var xianzou_empty_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if xianzou_empty_choice.is_empty() or not (xianzou_empty_choice.get("candidates", []) as Array).is_empty() or not bool((xianzou_empty_choice.get("context", {}) as Dictionary).get("private_info_safe_prompt", false)):
		return _fail("xianzou_private_empty_prompt choice=%s" % [xianzou_empty_choice])
	if not _submit_pending_choice(0, [], [], false) or _controller.state.get_player(0).skipped_phases.get("play", false):
		return _fail("xianzou_private_empty_cancel")
	_reset_state(2)
	# 安可四花色弃牌记录；满足条件后的确认应消耗本轮第一次额外回合额度。
	var anke: SkillDefinition = _install_single_skill(0, "anke")
	if anke == null:
		return _fail("anke_missing")
	# 其他角色回合；即使四种花色进入弃牌堆，也不能计算或显示安可文本标记。
	_controller.state.current_player_id = 1
	_controller.state.turn_number = 2
	anke.call("_on_turn_before", RuleEvent.new("phaseBefore", 1, 1, {"turn_number":_controller.state.turn_number}))
	var off_turn_anke_cards: Array[CardInstance] = [
		_add_discard_pile_card("sha", "spade", 5),
		_add_discard_pile_card("shan", "heart", 6),
		_add_discard_pile_card("tao", "club", 7),
		_add_discard_pile_card("wuzhong", "diamond", 8),
	]
	var off_turn_anke_uids: Array[int] = []
	for off_turn_card: CardInstance in off_turn_anke_cards:
		off_turn_anke_uids.append(off_turn_card.uid)
	anke.call("_on_cards_discarded", RuleEvent.new("cardsDiscardAfter", -1, -1, {"card_uids":off_turn_anke_uids}))
	if not _controller.state.get_player(0).character_corner_text.is_empty():
		return _fail("anke_off_turn_corner_text=%s" % _controller.state.get_player(0).character_corner_text)
	# 希露瓦自己的新回合；重新开启花色统计并按固定顺序显示文本。
	_controller.state.current_player_id = 0
	_controller.state.turn_number = 3
	anke.call("_on_turn_before", RuleEvent.new("phaseBefore", 0, 0, {"turn_number":_controller.state.turn_number}))
	var anke_cards: Array[CardInstance] = [
		_add_discard_pile_card("sha", "spade", 1),
		_add_discard_pile_card("shan", "heart", 2),
		_add_discard_pile_card("tao", "club", 3),
		_add_discard_pile_card("wuzhong", "diamond", 4),
	]
	var anke_uids: Array[int] = []
	for anke_card: CardInstance in anke_cards:
		anke_uids.append(anke_card.uid)
	anke.call("_on_cards_discarded", RuleEvent.new("cardsDiscardAfter", -1, -1, {"card_uids":anke_uids}))
	if _controller.state.get_player(0).character_corner_text != "安可：♠♥♣♦" or str(_controller.state.get_player(0).to_dict(0, false).get("character_corner_text", "")) != "安可：♠♥♣♦":
		return _fail("anke_corner_text=%s" % _controller.state.get_player(0).character_corner_text)
	# 其他角色回合结束不能触发“回合结束时”的安可；只有技能持有者自己的回合结束才会询问。
	anke.call("_on_turn_end", RuleEvent.new("phaseEnd", 1, 1, {"turn_number":_controller.state.turn_number}))
	if _controller.has_pending_card_choice():
		return _fail("anke_other_player_turn_end")
	anke.call("_on_turn_end", RuleEvent.new("phaseEnd", 0, 0, {"turn_number":_controller.state.turn_number}))
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [], [], true):
		return _fail("anke_choice")
	if int(anke.get("_uses_this_round")) != 1:
		return _fail("anke_extra_turn_count=%s" % anke.get("_uses_this_round"))
	return true


## 验证貊泽三项离场技、全场唯一猎物标记、上家查询、距离直击、返场追击、死亡收益与标记UI排列。
func _test_moze_marks_and_out_of_game_skills() -> bool:
	_reset_state(4)
	# 貊泽基础状态；专项重置默认4点体力，此处按武将定义改为2点。
	var moze_player: PlayerState = _controller.state.get_player(0)
	moze_player.character_id = "moze"
	moze_player.max_hp = 2
	moze_player.hp = 2
	# 第一名猎物候选手牌；幽锋必须先弃置该实体再写入标记。
	var first_hunt_card: CardInstance = _add_hand_card(1, "shan", "heart", 4)
	# 第二名猎物候选手牌；下一轮用于验证标记转移和离场失去1点体力。
	var second_hunt_card: CardInstance = _add_hand_card(2, "sha", "spade", 9)
	# 貊泽三项运行时技能；连续安装验证同一武将技能表不会互相覆盖。
	var youfeng: SkillDefinition = _install_single_skill(0, "youfeng")
	var lvexi: SkillDefinition = _install_single_skill(0, "lvexi")
	var yingchu: SkillDefinition = _install_single_skill(0, "yingchu")
	if youfeng == null or lvexi == null or yingchu == null:
		return _fail("moze_skill_missing")
	# 第一轮由四号位作为当前角色触发，避免貊泽离场中断本测试的阶段调度。
	_controller.state.current_player_id = 3
	_controller._emit_rule_timing("roundStart", 3, 3, 3, {"round_number":1})
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [], [1], true):
		return _fail("youfeng_first_target_choice")
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [first_hunt_card.uid], [], true):
		return _fail("youfeng_first_discard_choice")
	# 第一轮结果；一号目标获得来源属于貊泽的唯一猎物标记，实体进入弃牌堆且貊泽离场。
	var first_mark: Dictionary = _controller.get_player_mark(1, "liewu")
	if not moze_player.out_of_game or int(first_mark.get("count", 0)) != 1 or int(first_mark.get("source_player_id", -1)) != 0 or not _controller.state.discard_pile.has(first_hunt_card):
		return _fail("youfeng_first_result owner_out=%s mark=%s discarded=%s" % [moze_player.out_of_game, first_mark, _controller.state.discard_pile.has(first_hunt_card)])
	# 第二轮离场技仍须正常触发；标记转移给三号位，原目标失去标记，貊泽失去固定1点体力。
	# 专项测试没有正式回合父事件；重置独立事件运行时，使第二个模拟轮开始拥有新的根级选择上下文。
	_controller.event_scheduler.reset()
	_controller.state.current_event_id = -1
	# 离场接收能力由技能元数据统一校验；随后直接进入回调，避免专项测试复用上一轮TriggerManager暂停栈。
	var second_round_event: RuleEvent = RuleEvent.new("roundStart", 3, 3, {"round_number":2})
	if not youfeng.out_of_game_skill or not bool(youfeng.call("_can_receive_timing_event", second_round_event, Callable())):
		return _fail("youfeng_out_of_game_metadata")
	youfeng.call("_on_round_start", second_round_event)
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [], [2], true):
		return _fail("youfeng_second_target_choice")
	if not _controller.has_pending_card_choice() or not _submit_pending_choice(0, [second_hunt_card.uid], [], true):
		return _fail("youfeng_second_discard_choice")
	var second_mark: Dictionary = _controller.get_player_mark(2, "liewu")
	if not _controller.get_player_mark(1, "liewu").is_empty() or int(second_mark.get("source_player_id", -1)) != 0 or moze_player.hp != 1 or not moze_player.out_of_game:
		return _fail("youfeng_second_result old=%s new=%s hp=%d out=%s" % [_controller.get_player_mark(1, "liewu"), second_mark, moze_player.hp, moze_player.out_of_game])
	# 掠袭距离；貊泽返场后无论座次和坐骑基础距离如何，到猎物最终固定为1。
	_controller.restore_player_to_game(0, "moze_test")
	if _controller.card_rules.calculate_distance(0, 2) != 1:
		return _fail("lvexi_distance=%d" % _controller.card_rules.calculate_distance(0, 2))
	# 掠袭直击；活动用牌指定猎物后必须写入目标直击集合，使其无法响应本牌。
	var direct_hit_card: CardInstance = CardInstance.new("sha", "club", 7)
	_controller._card_use_contexts[direct_hit_card.uid] = {"target_ids":[2], "direct_hit_target_ids":[]}
	lvexi.call("_on_card_targeted", RuleEvent.new("useCardToTargeted", 0, 2, {"card_uid":direct_hit_card.uid, "target_id":2, "card_id":"sha"}))
	if not _controller.is_card_target_direct_hit(direct_hit_card.uid, 2):
		return _fail("lvexi_direct_hit")
	# 掠袭直击响应过滤；猎物即使持有对应牌也不能收到【闪】或【杀】响应选择窗口。
	var hunt_response_shan: CardInstance = _add_hand_card(2, "shan", "diamond", 6)
	var hunt_response_sha: CardInstance = _add_hand_card(2, "sha", "heart", 7)
	var direct_hit_response_context: Dictionary = {"parent_card_uid":direct_hit_card.uid}
	if _controller.request_response_card(2, "shan", "猎物不应收到闪响应。", direct_hit_response_context) != null or _controller.has_pending_card_choice() or _controller.request_response_card(2, "sha", "猎物不应收到杀响应。", direct_hit_response_context) != null or _controller.has_pending_card_choice() or not _controller.state.get_player(2).hand.has(hunt_response_shan) or not _controller.state.get_player(2).hand.has(hunt_response_sha):
		return _fail("lvexi_direct_hit_response_patterns")
	# 掠袭锦囊无懈过滤；目标持有无懈时不进入本次无懈响应名单，也不创建空询问。
	var direct_hit_trick: CardInstance = CardInstance.new("juedou", "club", 8)
	direct_hit_trick.zone = "processing"
	direct_hit_trick.owner_id = -1
	_controller.state.processing_area.append(direct_hit_trick)
	_controller._card_use_contexts[direct_hit_trick.uid] = {"target_ids":[2], "direct_hit_target_ids":[2]}
	var hunt_response_wuxie: CardInstance = _add_hand_card(2, "wuxie", "spade", 9)
	_controller.resolve_trick_negation(0, 2, "juedou", {"parent_card_uid":direct_hit_trick.uid})
	if _controller.has_pending_card_choice() or not _controller._pending_negation_choices.is_empty() or (_controller.state.simultaneous_response_display.get("responder_ids", []) as Array).has(2) or not _controller.state.get_player(2).hand.has(hunt_response_wuxie):
		return _fail("lvexi_direct_hit_wuxie")
	_controller.state.processing_area.erase(direct_hit_trick)
	_controller._card_use_contexts.erase(direct_hit_trick.uid)
	# 猎物受伤追击；貊泽离场时，任意来源的1点伤害会令其返场并再造成固定1点伤害。
	_controller.remove_player_from_game(0, "moze_test")
	var hunt_hp_before_damage: int = _controller.state.get_player(2).hp
	_controller.damage(3, 2, 1, "normal", "")
	if moze_player.out_of_game or _controller.state.get_player(2).hp != hunt_hp_before_damage - 2:
		return _fail("lvexi_follow_up owner_out=%s hp=%d/%d" % [moze_player.out_of_game, _controller.state.get_player(2).hp, hunt_hp_before_damage])
	# 猎物死亡收益；离场中的貊泽可以先摸2张牌再返场，死亡目标的猎物标记随之清理。
	_controller.remove_player_from_game(0, "moze_test")
	var death_draw_one: CardInstance = _add_draw_pile_card("shan", "diamond", 10)
	var death_draw_two: CardInstance = _add_draw_pile_card("tao", "heart", 11)
	_controller.state.get_player(2).alive = false
	var hand_count_before_death_reward: int = moze_player.hand.size()
	_controller._emit_rule_timing("dieAfter", 2, 3, 2, {"death_event_id":901})
	if moze_player.out_of_game or moze_player.hand.size() != hand_count_before_death_reward + 2 or not moze_player.hand.has(death_draw_one) or not moze_player.hand.has(death_draw_two) or not _controller.get_player_mark(2, "liewu").is_empty():
		return _fail("lvexi_death_reward out=%s hand=%d/%d mark=%s" % [moze_player.out_of_game, moze_player.hand.size(), hand_count_before_death_reward, _controller.get_player_mark(2, "liewu")])

	# 影出与上家；四号位离场后，貊泽的有效上家应跳过四号位并取三号位。
	_reset_state(4)
	moze_player = _controller.state.get_player(0)
	moze_player.character_id = "moze"
	moze_player.max_hp = 2
	moze_player.hp = 2
	moze_player.out_of_game = true
	_controller.state.get_player(3).out_of_game = true
	_controller.state.current_player_id = 2
	yingchu = _install_single_skill(0, "yingchu")
	var previous_player: PlayerState = _controller.state.get_previous_alive_player(0)
	if previous_player == null or previous_player.player_id != 2:
		return _fail("previous_alive_player=%s" % [previous_player.player_id if previous_player != null else -1])
	_controller._emit_rule_timing("phaseEnd", 2, 2, 2, {"turn_number":2})
	if moze_player.out_of_game or not bool(yingchu.get("_waiting_owner_turn_end")):
		return _fail("yingchu_return")
	_controller._emit_rule_timing("phaseAfter", 2, 2, 2, {"turn_number":2})
	if moze_player.out_of_game:
		return _fail("yingchu_removed_on_previous_phase_after")
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "finish"
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":3})
	if not moze_player.out_of_game or bool(yingchu.get("_waiting_owner_turn_end")) or _controller.state.current_phase != "finish":
		return _fail("yingchu_leave_again")

	# 幽锋AI；敌方低生存角色必须高于友方角色，体现主公指定的脆皮和易受伤目标优先级。
	_reset_state(3)
	_controller.state.get_player(0).character_id = "moze"
	_controller.state.get_player(1).hp = 1
	youfeng = GameDatabase.create_skill("youfeng")
	youfeng.bind(_controller, 0)
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var ai_snapshot: Dictionary = _controller.state.to_dict(0, true)
	var target_request: Dictionary = {"context":{"kind":"youfeng_target"}}
	var enemy_action: Dictionary = {"payload":{"selected_target_ids":[1], "confirmed":true}}
	var friend_action: Dictionary = {"payload":{"selected_target_ids":[2], "confirmed":true}}
	if youfeng.score_ai_choice(ai_snapshot, target_request, enemy_action, evaluator) <= youfeng.score_ai_choice(ai_snapshot, target_request, friend_action, evaluator):
		return _fail("youfeng_ai_target_priority")

	# 标记快照与武将牌纵排UI；两个标记按order纵向排列，图标内显示单字且右下角显示数量。
	_controller.player_mark_service.set_mark(1, "liewu", {"icon":"猎", "name":"猎物标记", "description":"猎物详细说明", "count":1, "source_player_id":0, "order":0}, true)
	_controller.player_mark_service.set_mark(1, "test_mark", {"icon":"测", "name":"测试标记", "description":"测试详细说明", "count":2, "source_player_id":-1, "order":1})
	var marked_snapshot: Dictionary = _controller.state.get_player(1).to_dict(0, false)
	if (marked_snapshot.get("public_marks", {}) as Dictionary).size() != 2:
		return _fail("public_mark_snapshot=%s" % marked_snapshot.get("public_marks", {}))
	var marked_player_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	add_child(marked_player_view)
	await get_tree().process_frame
	marked_player_view.set_match_overlays_visible(true)
	marked_snapshot["character_id"] = "moze"
	marked_snapshot["identity"] = "rebel"
	marked_snapshot["hand_count"] = 0
	marked_snapshot["equipment"] = {}
	marked_snapshot["judgment_area"] = []
	marked_snapshot["wooden_ox_storage_count"] = 0
	marked_player_view.configure_snapshot(marked_snapshot, GameDatabase.get_character("moze"))
	await get_tree().process_frame
	var vertical_markers: PlayerMarkersView = marked_player_view.get_node("PublicMarkers") as PlayerMarkersView
	if vertical_markers == null or vertical_markers.get_child_count() != 2 or vertical_markers.horizontal:
		marked_player_view.queue_free()
		return _fail("vertical_markers count=%s horizontal=%s" % [vertical_markers.get_child_count() if vertical_markers != null else -1, vertical_markers.horizontal if vertical_markers != null else true])
	var first_badge: PlayerMarkerBadge = vertical_markers.get_child(0) as PlayerMarkerBadge
	var second_badge: PlayerMarkerBadge = vertical_markers.get_child(1) as PlayerMarkerBadge
	if first_badge.position.y >= second_badge.position.y or not is_equal_approx(first_badge.badge_diameter, 20.0) or first_badge.icon_font_size != 12 or not is_equal_approx(first_badge.count_diameter, 13.0) or first_badge.count_font_size != 10 or not is_equal_approx(vertical_markers.marker_gap, 1.0) or (first_badge.get_node("Icon") as Label).text != "猎" or (second_badge.get_node("Count") as Label).text != "2":
		marked_player_view.queue_free()
		return _fail("vertical_marker_layout first=%s second=%s" % [first_badge.position, second_badge.position])
	# 标记悬停详细信息；武将牌必须把子组件请求转发到统一信息出口。
	var marker_information: Array[Dictionary] = []
	marked_player_view.information_requested.connect(func(information: Dictionary, _anchor_rect: Rect2) -> void: marker_information.append(information.duplicate(true)))
	first_badge.call("_on_mouse_entered")
	if marker_information.is_empty() or str(marker_information[0].get("title", "")) != "猎物标记" or not str(marker_information[0].get("description", "")).contains("猎物详细说明"):
		marked_player_view.queue_free()
		return _fail("marker_hover_information=%s" % [marker_information])
	marked_player_view.queue_free()
	# 第一视角横排UI；复用相同标记数据后第二枚图标必须只向右移动，不产生纵向堆叠。
	var horizontal_markers: PlayerMarkersView = PlayerMarkersView.new()
	add_child(horizontal_markers)
	horizontal_markers.configure(marked_snapshot.get("public_marks", {}) as Dictionary, true)
	await get_tree().process_frame
	if horizontal_markers.get_child_count() != 2 or not horizontal_markers.horizontal:
		horizontal_markers.queue_free()
		return _fail("horizontal_markers count=%d horizontal=%s" % [horizontal_markers.get_child_count(), horizontal_markers.horizontal])
	first_badge = horizontal_markers.get_child(0) as PlayerMarkerBadge
	second_badge = horizontal_markers.get_child(1) as PlayerMarkerBadge
	if first_badge.position.x >= second_badge.position.x or not is_equal_approx(first_badge.position.y, second_badge.position.y):
		horizontal_markers.queue_free()
		return _fail("horizontal_marker_layout first=%s second=%s" % [first_badge.position, second_badge.position])
	horizontal_markers.queue_free()
	return true


## 验证山倾的方块摸牌、红桃等量回复、黑桃远距离、梅花单次弃牌、同花色去重与每回合限次。
func _test_shanqing_suit_effects() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	# 山倾持有者；预先失去2点体力，用于验证红桃伤害后回复实际伤害量。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.hp = 2
	# 方块效果摸到的牌；放在牌堆顶并在 useCard 时进入持有者手牌。
	var diamond_draw_card: CardInstance = _add_draw_pile_card("shan", "club", 4)
	# 红桃与方块材料；两种花色应分别产生回复与摸1张牌。
	var heart_material: CardInstance = _add_hand_card(0, "sha", "heart", 6)
	# 第二张方块材料；与红桃共同构成第一张山倾【杀】。
	var diamond_material: CardInstance = _add_hand_card(0, "shan", "diamond", 8)
	# 山倾运行时技能；缺失表示自动扫描或武将引用配置错误。
	var shanqing: SkillDefinition = _install_single_skill(0, "shanqing")
	if shanqing == null:
		return _fail("shanqing_missing")
	# 第一张山倾直接指定相邻敌方；成功后应先进入目标【闪】响应窗口。
	var first_error: String = shanqing.activate({"material_card_uids":[heart_material.uid, diamond_material.uid], "target_ids":[1]})
	if not first_error.is_empty() or not _controller.has_pending_card_choice() or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "slash_response":
		return _fail("shanqing_heart_diamond_start error=%s pending=%s" % [first_error, _controller._pending_card_choice])
	if not owner.hand.has(diamond_draw_card):
		return _fail("shanqing_diamond_draw hand=%s" % owner.hand.map(func(card: CardInstance) -> int: return card.uid))
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 普通【杀】造成1点伤害后，红桃效果应令持有者回复1点体力。
	if _controller.state.get_player(1).hp != 3 or owner.hp != 3 or shanqing.can_activate():
		return _fail("shanqing_heart_damage target_hp=%d owner_hp=%d reusable=%s" % [_controller.state.get_player(1).hp, owner.hp, shanqing.can_activate()])

	_reset_state(4)
	_controller.game_flow_interval_seconds = 0.0
	# 两张同为黑桃的材料；同花色只记录一次，但仍应在指定目标阶段解除距离限制。
	var first_spade: CardInstance = _add_hand_card(0, "shan", "spade", 2)
	# 第二张黑桃材料；用于验证重复花色不会产生重复效果或阻止发动。
	var second_spade: CardInstance = _add_hand_card(0, "tao", "spade", 9)
	shanqing = _install_single_skill(0, "shanqing")
	# 四人局0号到2号基础距离为2，普通无武器【杀】不可指定；黑桃山倾应合法进入2号响应窗口。
	var spade_error: String = shanqing.activate({"material_card_uids":[first_spade.uid, second_spade.uid], "target_ids":[2]})
	if not spade_error.is_empty() or not _controller.has_pending_card_choice() or int(_controller._pending_card_choice.get("chooser_id", -1)) != 2:
		return _fail("shanqing_spade_distance error=%s pending=%s" % [spade_error, _controller._pending_card_choice])
	if not _submit_pending_choice(2, [], [], false):
		return false

	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	# 目标两张区域牌；双梅花材料只允许弹出一次弃牌窗口并弃置其中一张。
	var target_first_card: CardInstance = _add_hand_card(1, "sha", "heart", 5)
	# 目标第二张手牌；技能完成后应仍保留，证明同花色梅花没有重复生效。
	var target_second_card: CardInstance = _add_hand_card(1, "shan", "diamond", 7)
	# 第一张梅花材料；两张材料都来自普通手牌。
	var first_club: CardInstance = _add_hand_card(0, "tao", "club", 3)
	# 第二张梅花材料；重复花色应在虚拟存储中去重。
	var second_club: CardInstance = _add_hand_card(0, "jiu", "club", 11)
	shanqing = _install_single_skill(0, "shanqing")
	# 双梅花山倾发动结果；成功后应只创建一次目标区域弃牌选择。
	var club_error: String = shanqing.activate({"material_card_uids":[first_club.uid, second_club.uid], "target_ids":[1]})
	if not club_error.is_empty() or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "shanqing_club_discard":
		return _fail("shanqing_club_prompt error=%s pending=%s" % [club_error, _controller._pending_card_choice])
	if not _submit_pending_choice(0, [target_first_card.uid], [], true):
		return false
	if not _controller.state.discard_pile.has(target_first_card) or not _controller.state.get_player(1).hand.has(target_second_card) or str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "slash_response":
		return _fail("shanqing_club_once discard=%s target_hand=%s pending=%s" % [_controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid), _controller.state.get_player(1).hand.map(func(card: CardInstance) -> int: return card.uid), _controller._pending_card_choice])
	if not _submit_pending_choice(1, [], [], false):
		return false
	return true


## 验证剑势在 shaDamage 时暂停原【杀】，戏法调整判定牌后恢复并按红色结果增加1点伤害。
func _test_jianshi_xifa_judgment_continuation() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	# 黑色判定候选；最后加入使其成为初始牌堆顶，证明戏法确实改变最终判定结果。
	var red_judgment_card: CardInstance = _add_draw_pile_card("tao", "heart", 6)
	# 初始牌堆顶黑牌；未发动戏法时剑势不会增伤。
	var black_judgment_card: CardInstance = _add_draw_pile_card("shan", "spade", 8)
	# 虚拟【杀】材料；使用统一虚拟牌入口触发完整 useCard、【闪】与 shaDamage 流程。
	var slash_material: CardInstance = _add_hand_card(0, "jiu", "club", 4)
	# 素裳的剑势实例；负责 shaDamage 确认与伤害续接。
	var jianshi: SkillDefinition = _install_single_skill(0, "jianshi")
	# 同一角色的戏法实例；用于验证通用判定前接口与排序窗口，不依赖武将组合限制。
	var xifa: SkillDefinition = _install_single_skill(0, "xifa")
	if jianshi == null or xifa == null:
		return _fail("jianshi_xifa_missing")
	# 使用单材料虚拟【杀】；第一步由目标明确放弃【闪】。
	var slash_material_uids: Array[int] = [slash_material.uid]
	if not _controller.execute_virtual_card_use(0, "sha", slash_material_uids, [1], "") or not _controller.has_pending_card_choice():
		return _fail("jianshi_slash_start pending=%s" % _controller._pending_card_choice)
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 【闪】放弃后应停在剑势确认，尚未扣减目标体力。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "jianshi_confirm" or _controller.state.get_player(1).hp != 4:
		return _fail("jianshi_confirm_pending=%s hp=%d" % [_controller._pending_card_choice, _controller.state.get_player(1).hp])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 剑势开始判定后先进入戏法确认；判定 AI 上下文必须公开红色有利和来源/目标相反价值。
	var xifa_confirm_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	# 剑势判定方向数据；红色条件与角色价值供戏法按阵营决定排序。
	var judgment_ai_context: Dictionary = xifa_confirm_context.get("judgment_ai_context", {}) as Dictionary
	if str(xifa_confirm_context.get("kind", "")) != "xifa_confirm" or (judgment_ai_context.get("favorable_condition", {}) as Dictionary).get("colors", []) != ["red"]:
		return _fail("jianshi_judgment_ai_context=%s" % xifa_confirm_context)
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 戏法排序窗口；将红牌置于顶行最左侧、黑牌置底。
	if str(_controller._pending_card_choice.get("choice_type", "")) != "arrange":
		return _fail("xifa_arrangement_missing=%s" % _controller._pending_card_choice)
	if not _submit_pending_choice(0, [red_judgment_card.uid, black_judgment_card.uid], [], true, "top_count_1"):
		return false
	# 红色剑势判定完成后原【杀】恢复并造成2点伤害；判定请求与所有选择均应清空。
	if _controller.state.get_player(1).hp != 2 or not _controller.state.discard_pile.has(red_judgment_card) or _controller.has_pending_judgment_request() or _controller.has_pending_card_choice():
		return _fail("jianshi_xifa_result hp=%d discard=%s pending_judge=%s pending_choice=%s" % [_controller.state.get_player(1).hp, _controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid), _controller.has_pending_judgment_request(), _controller._pending_card_choice])
	return true


## 验证八卦阵判定被戏法暂停时不会提前判定响应失败，黑色结果完成后才排除防具并恢复手牌【闪】窗口。
func _test_bagua_xifa_async_response_continuation() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	# 防守者手牌【闪】；八卦阵最终判定失败后应重新开放该实体，并在确认后正常抵消【杀】。
	var hand_shan: CardInstance = _add_hand_card(1, "shan", "heart", 7)
	# 防守者八卦阵；判定期间始终留在防具槽，失败后只排除本次响应入口而不弃置装备。
	var bagua_card: CardInstance = CardInstance.new("bagua", "club", 2)
	bagua_card.zone = "equipment"
	bagua_card.owner_id = 1
	_controller.state.get_player(1).equipment["armor"] = bagua_card
	# 红色观看牌；戏法会把它置底，证明最终黑色结果来自玩家提交的牌堆顺序。
	var red_judgment_card: CardInstance = _add_draw_pile_card("tao", "heart", 6)
	# 黑色观看牌；排序后置于顶行最左侧，使八卦阵判定失败并进入普通响应重试。
	var black_judgment_card: CardInstance = _add_draw_pile_card("sha", "spade", 8)
	# 攻击者虚拟【杀】材料；通过完整【杀】响应链验证八卦阵的异步判定恢复路由。
	var slash_material: CardInstance = _add_hand_card(0, "jiu", "diamond", 4)
	# 防守者戏法实例；全局 judgeBefore 订阅应在八卦阵翻牌前建立确认与排序请求。
	var xifa: SkillDefinition = _install_single_skill(1, "xifa")
	if xifa == null:
		return _fail("bagua_xifa_missing")
	# 发起单目标虚拟【杀】；第一段响应必须只询问八卦阵装备本身。
	var slash_material_uids: Array[int] = [slash_material.uid]
	if not _controller.execute_virtual_card_use(0, "sha", slash_material_uids, [1], ""):
		return _fail("bagua_xifa_slash_start")
	# 首次响应候选；立即装备询问不得混入手牌【闪】，避免玩家跳过八卦阵确认协议。
	var first_response_candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if first_response_candidates.size() != 1 or int((first_response_candidates[0] as Dictionary).get("uid", -1)) != bagua_card.uid:
		return _fail("bagua_xifa_immediate_candidates=%s" % [first_response_candidates])
	if not _submit_pending_choice(1, [bagua_card.uid], [], true):
		return false
	# 八卦阵开始判定后必须先停在戏法确认，不能把尚未翻开的判定误当成失败并提前打开手牌窗口。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "xifa_confirm" or not _controller.has_pending_judgment_request():
		return _fail("bagua_xifa_confirm pending=%s judge=%s" % [_controller._pending_card_choice, _controller.has_pending_judgment_request()])
	if not _submit_pending_choice(1, [], [], true):
		return false
	# 戏法排序提交黑色牌置顶、红色牌置底；顶行牌数固定为1。
	if not _submit_pending_choice(1, [black_judgment_card.uid, red_judgment_card.uid], [], true, "top_count_1"):
		return false
	# 黑色判定完成后的第二次响应候选；手牌【闪】保留，已经判定过的八卦阵必须被排除。
	var retry_candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	# 第二次响应候选 UID；用于同时检查手牌保留与防具排除，不依赖候选排列顺序。
	var retry_candidate_uids: Array[int] = []
	for candidate_variant: Variant in retry_candidates:
		# 当前响应候选；候选字典只读取稳定实体 UID。
		var candidate: Dictionary = candidate_variant as Dictionary
		retry_candidate_uids.append(int(candidate.get("uid", -1)))
	if not retry_candidate_uids.has(hand_shan.uid) or retry_candidate_uids.has(bagua_card.uid):
		return _fail("bagua_xifa_retry_candidates=%s" % [retry_candidate_uids])
	if not _submit_pending_choice(1, [hand_shan.uid], [], true):
		return false
	# 最终响应结果；目标不受伤，黑色判定牌与手牌【闪】进入弃牌堆，防具仍留在原槽且全部异步状态清空。
	var defender: PlayerState = _controller.state.get_player(1)
	if defender.hp != defender.max_hp or defender.equipment.get("armor") != bagua_card or not _controller.state.discard_pile.has(black_judgment_card) or not _controller.state.discard_pile.has(hand_shan) or _controller.has_pending_judgment_request() or _controller.has_pending_card_choice():
		return _fail("bagua_xifa_result hp=%d armor=%s discard=%s judge=%s choice=%s" % [defender.hp, defender.equipment.get("armor"), _controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid), _controller.has_pending_judgment_request(), _controller._pending_card_choice])
	return true


## 验证延时锦囊判定被戏法暂停时保留处理区原牌，排序完成后才应用判定结果并结束延时牌生命周期。
func _test_delayed_trick_xifa_async_judgment() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	# 使用独立测试阶段避免判定完成后自动推进正式回合；本项只验证延时牌与异步判定的职责边界。
	_controller.state.current_phase = "judgment_test"
	# 乐不思蜀实体；模拟其已从判定区进入公共处理区、正等待判定的标准中间状态。
	var delayed_card: CardInstance = CardInstance.new("lebu", "club", 9)
	delayed_card.zone = "processing"
	delayed_card.owner_id = -1
	_controller.state.processing_area.append(delayed_card)
	# 红桃观看牌；戏法将其置顶后应使目标保留出牌阶段。
	var heart_judgment_card: CardInstance = _add_draw_pile_card("shan", "heart", 5)
	# 黑桃初始牌堆顶；若延时牌绕过戏法同步翻牌，将错误写入跳过出牌阶段状态。
	var spade_judgment_card: CardInstance = _add_draw_pile_card("sha", "spade", 10)
	# 目标角色的戏法实例；负责在乐不思蜀 judgeBefore 时暂停并调整两张观看牌。
	var xifa: SkillDefinition = _install_single_skill(0, "xifa")
	# 乐不思蜀源码定义；延时判定与恢复均由内容文件自身处理，控制器不识别具体牌名。
	var lebu_definition: CardDefinition = GameDatabase.get_card_definition("lebu")
	if xifa == null or lebu_definition == null:
		return _fail("delayed_xifa_missing")
	lebu_definition.resolve_delayed_judgment(_controller, 0, delayed_card, false)
	# 判定暂停期间原延时牌仍在处理区，且尚未根据初始牌堆顶黑桃写入跳过阶段状态。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "xifa_confirm" or not _controller.state.processing_area.has(delayed_card) or bool(_controller.state.get_player(0).skipped_phases.get("play", false)):
		return _fail("delayed_xifa_pause processing=%s skipped=%s pending=%s" % [_controller.state.processing_area.has(delayed_card), _controller.state.get_player(0).skipped_phases, _controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 戏法把红桃置顶并把黑桃置底，使最终乐不思蜀判定通过。
	if not _submit_pending_choice(0, [heart_judgment_card.uid, spade_judgment_card.uid], [], true, "top_count_1"):
		return false
	# 最终延时结果；红桃不跳过出牌阶段，判定牌与乐不思蜀均已弃置，所有判定与选择状态清空。
	if bool(_controller.state.get_player(0).skipped_phases.get("play", false)) or _controller.state.processing_area.has(delayed_card) or not _controller.state.discard_pile.has(delayed_card) or not _controller.state.discard_pile.has(heart_judgment_card) or _controller.has_pending_judgment_request() or _controller.has_pending_card_choice():
		return _fail("delayed_xifa_result skipped=%s processing=%s discard=%s judge=%s choice=%s" % [_controller.state.get_player(0).skipped_phases, _controller.state.processing_area.map(func(card: CardInstance) -> int: return card.uid), _controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid), _controller.has_pending_judgment_request(), _controller._pending_card_choice])
	return true


## 验证戏法补看第二张牌时不会丢失原牌堆顶，并验证敌对改判定者会优先制造投狭无法回收的花色。
func _test_xifa_partial_draw_pile_replenishment_and_opposing_ai() -> bool:
	_reset_state(3)
	# 原摸牌堆唯一顶牌；弃牌堆洗入后仍必须保持为第一张观看牌和实际牌堆顶。
	var retained_top_card: CardInstance = _add_draw_pile_card("shan", "club", 4)
	# 第一张待洗回弃牌；红桃与方块保证第二张观看牌不会和原梅花顶牌同花色。
	var first_recycled_card: CardInstance = _add_discard_pile_card("tao", "heart", 6)
	# 第二张待洗回弃牌；与第一张共同验证补牌后全部实体仍在摸牌堆且没有丢失。
	var second_recycled_card: CardInstance = _add_discard_pile_card("wuzhong", "diamond", 8)
	# 私有观看候选；请求2张时应保留原顶牌，并从洗回弃牌中补足第2张。
	var viewed_candidates: Array[Dictionary] = _controller.get_top_draw_card_candidates(1, 2)
	if viewed_candidates.size() != 2 or int(viewed_candidates[0].get("uid", -1)) != retained_top_card.uid or int(viewed_candidates[1].get("uid", -1)) not in [first_recycled_card.uid, second_recycled_card.uid] or not _controller.state.discard_pile.is_empty() or _controller.state.draw_pile.size() != 3 or _controller.state.draw_pile.back() != retained_top_card or not _controller.state.draw_pile.has(first_recycled_card) or not _controller.state.draw_pile.has(second_recycled_card):
		return _fail("xifa_partial_replenishment viewed=%s draw=%s discard=%s" % [viewed_candidates, _controller.state.draw_pile.map(func(card: CardInstance) -> int: return card.uid), _controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid)])
	# 第二张观看牌的真实花色；模拟投狭当前只有该花色能够回收高价值牌。
	var preferred_suit: String = str((viewed_candidates[1].get("card_data", {}) as Dictionary).get("suit", ""))
	# 投狭判定 AI 上下文；有利结果帮助领袖持有者和忠臣当前回合角色，对反贼戏法持有者整体不利。
	var judgment_ai_context: Dictionary = {"preferred_suit_values":{preferred_suit:8.0}, "favorable_result_player_values":{"0":1.0, "2":0.5}}
	# 敌对戏法实例；二号反贼应把不匹配的梅花原顶牌保留在顶端，阻止领袖投狭命中高价值花色。
	var hostile_xifa: SkillDefinition = _install_single_skill(1, "xifa")
	if hostile_xifa == null:
		return _fail("hostile_xifa_missing")
	# 敌对排序计划；顶行应只有原梅花牌，匹配投狭的候选被放入底行。
	var hostile_plan: Dictionary = hostile_xifa._build_ai_arrangement(viewed_candidates, judgment_ai_context, 0)
	if int(hostile_plan.get("top_count", -1)) != 1 or (hostile_plan.get("ordered_card_uids", []) as Array).is_empty() or int((hostile_plan.get("ordered_card_uids", []) as Array)[0]) != retained_top_card.uid:
		return _fail("hostile_xifa_touxia_plan=%s" % hostile_plan)
	# 友方戏法实例；一号领袖应反向把可回收高价值花色置顶，保持投狭自身的指定 AI 逻辑。
	var friendly_xifa: SkillDefinition = _install_single_skill(0, "xifa")
	if friendly_xifa == null:
		return _fail("friendly_xifa_missing")
	# 友方排序计划；顶行第一张必须是拥有投狭偏好花色的第二张观看牌。
	var friendly_plan: Dictionary = friendly_xifa._build_ai_arrangement(viewed_candidates, judgment_ai_context, 0)
	if int(friendly_plan.get("top_count", -1)) != 1 or (friendly_plan.get("ordered_card_uids", []) as Array).is_empty() or int((friendly_plan.get("ordered_card_uids", []) as Array)[0]) != int(viewed_candidates[1].get("uid", -1)):
		return _fail("friendly_xifa_touxia_plan=%s" % friendly_plan)
	return true


## 验证投狭只统计指定回合出牌阶段弃牌、戏法按高价值花色改判、获得后固定令当前回合角色摸1张牌。
func _test_touxia_turn_discard_history() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	_controller.state.current_player_id = 1
	_controller.state.current_phase = "play"
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	# 出牌阶段进入弃牌堆的红桃关键牌；应成为投狭判定后的唯一可获得候选。
	var play_discard_card: CardInstance = _add_hand_card(1, "tao", "heart", 9)
	_controller.card_movement.move_card(play_discard_card, "discard_pile", -1, "discard", 101)
	# 弃牌阶段进入弃牌堆的梅花牌；即使仍在弃牌堆也不得进入投狭窗口。
	_controller.state.current_phase = "discard"
	# 弃牌阶段测试实体；用于确认投狭严格排除非出牌阶段移动记录。
	var discard_phase_card: CardInstance = _add_hand_card(1, "shan", "club", 7)
	_controller.card_movement.move_card(discard_phase_card, "discard_pile", -1, "discard", 102)
	# 戏法观看候选；黑桃先成为牌堆顶，玩家随后把红桃调整为投狭判定结果。
	var heart_judgment_card: CardInstance = _add_draw_pile_card("sha", "heart", 5)
	# 黑桃初始牌堆顶；投狭偏好映射应明确更希望红桃以取得关键【桃】。
	var spade_judgment_card: CardInstance = _add_draw_pile_card("shan", "spade", 10)
	_controller.state.current_phase = "finish"
	# 桂乃芬两项技能实例；戏法负责改判，投狭负责回合历史与获得流程。
	var xifa: SkillDefinition = _install_single_skill(0, "xifa")
	# 投狭运行时实例；每轮额度从当前 round_number 同步。
	var touxia: SkillDefinition = _install_single_skill(0, "touxia")
	if xifa == null or touxia == null:
		return _fail("touxia_xifa_missing")
	# 通过正式回合尾部入口派发 phaseAfter；选择与判定完成前不得提前切换到下一角色。
	_controller._complete_finish_turn(1)
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "touxia_confirm" or _controller.state.current_player_id != 1:
		return _fail("touxia_confirm_missing=%s" % _controller._pending_card_choice)
	if not _submit_pending_choice(0, [], [], true):
		return false
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "xifa_confirm":
		return _fail("touxia_xifa_confirm_missing=%s" % _controller._pending_card_choice)
	# 投狭向戏法暴露的花色偏好应包含红桃，且不包含仅在弃牌阶段进入弃牌堆的梅花。
	var touxia_judgment_ai: Dictionary = ((_controller._pending_card_choice.get("context", {}) as Dictionary).get("judgment_ai_context", {}) as Dictionary)
	# 投狭花色偏好映射；只应记录当前仍可回收牌的实体花色。
	var preferred_suits: Dictionary = touxia_judgment_ai.get("preferred_suit_values", {}) as Dictionary
	if not preferred_suits.has("heart") or preferred_suits.has("club"):
		return _fail("touxia_preferred_suits=%s" % preferred_suits)
	if not _submit_pending_choice(0, [], [], true):
		return false
	if not _submit_pending_choice(0, [heart_judgment_card.uid, spade_judgment_card.uid], [], true, "top_count_1"):
		return false
	# 零流程间隔下应立即打开同花色获得窗口，且候选只包含出牌阶段的红桃【桃】。
	var gain_candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "touxia_gain" or gain_candidates.size() != 1 or int((gain_candidates[0] as Dictionary).get("uid", -1)) != play_discard_card.uid:
		return _fail("touxia_gain_candidates=%s pending=%s" % [gain_candidates, _controller._pending_card_choice])
	if not _submit_pending_choice(0, [play_discard_card.uid], [], true):
		return false
	# 桂乃芬获得出牌阶段弃置的【桃】，当前回合角色随后从剩余牌堆摸到黑桃牌；弃牌阶段梅花仍留在弃牌堆。
	if not _controller.state.get_player(0).hand.has(play_discard_card) or not _controller.state.get_player(1).hand.has(spade_judgment_card) or _controller.state.current_player_id != 0:
		return _fail("touxia_result owner_hand=%s turn_hand=%s discard=%s current=%d" % [_controller.state.get_player(0).hand.map(func(card: CardInstance) -> int: return card.uid), _controller.state.get_player(1).hand.map(func(card: CardInstance) -> int: return card.uid), _controller.state.discard_pile.map(func(card: CardInstance) -> int: return card.uid), _controller.state.current_player_id])
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
	# 当前玩家已安装技能表；同一场景可连续追加多个技能以验证武将内技能联动。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 为当前统一选择请求提交牌、目标、文字选项或确认结果；测试通过正式PlayerAction入口覆盖事件运行时与阶段恢复链。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool, selected_control_id: String = "") -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；卡牌、目标和确认状态均显式填写，保持与真实界面提交协议一致。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s pending=%s" % [actor_id, request_id, action.payload, _controller._pending_card_choice])
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("NEW_CHARACTER_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
