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
	if not _test_gangfeng_jiyu_play_priority():
		return
	if not _test_ai_active_skill_progress_recovery():
		return
	if not _test_ai_choice_fallback_integrity():
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
	_controller._rule_continuations.reset()
	_controller._pending_damage_finalizations.clear()
	_controller._cards_used_this_turn_by_player.clear()
	_controller._started_phase_lifecycles.clear()
	_controller._pending_finish_turn_player_id = -1
	# 旧场景的AI策略与异步令牌；每个专项场景从无控制者、无待执行任务状态开始，避免前一断言的计时器进入新状态。
	_controller.ai_coordinator._policies.clear()
	_controller._ai_drive_token += 1
	_controller._scheduled_ai_drive_token = -1
	_controller._scheduled_ai_choice_request_id = -1
	_controller._ai_choice_submit_failures.clear()


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
		"mingchen":"锁定技，当你于回合内失去最后的手牌后，你令一名角色从牌堆或弃牌堆中获得一张【无中生有】。若该角色不为你，你令其对其造成1点雷属性伤害，并令此技能失效直到回合结束。",
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
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "guanshi_cost" or not _submit_pending_choice(0, [first_cost.uid, second_cost.uid], [], true):
		return _fail("mingchen_guanshi_cost")
	# 两张费用已弃置但伤害仍等待冥谶；栈内同时保留武器阶段与父目标收尾且目标体力尚未改变。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "mingchen_target" or target.hp != 4 or _controller._rule_continuations.size() != 2:
		return _fail("mingchen_guanshi_interrupted hp=%d continuations=%s" % [target.hp, _controller._rule_continuations.to_array()])
	if not _submit_pending_choice(0, [], [0], true):
		return false
	# 冥谶结束后先恢复贯石斧令杀命中，再完成父目标；费用、闪和杀都只移动一次。
	if target.hp != 3 or not hanya.hand.has(mingchen_gain_card) or not _controller.state.discard_pile.has(first_cost) or not _controller.state.discard_pile.has(second_cost) or not _controller.state.discard_pile.has(dodge_card) or not _controller.state.discard_pile.has(slash_card) or _controller._rule_continuations.has_pending() or _controller.has_pending_card_choice():
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
	var sefu: SkillDefinition = GameDatabase.create_skill("sefu")
	# 伤害目标的永屹实例；体力实际减少后在damageAfter创建可取消确认选择。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	if sefu == null or yongyi == null:
		return _fail("damage_timing_skills_missing")
	sefu.bind(_controller, 0)
	yongyi.bind(_controller, 1)
	_controller.skill_instances_by_player = {0:{"sefu":sefu}, 1:{"yongyi":yongyi}}
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
		return _fail("turn_start_zhenqi_first context=%s continuations=%s" % [zhenqi_choice_context, _controller._rule_continuations.to_array()])
	# 明确取消【振旗】；规则续接应继续发布剩余回合开始时机，并在准备阶段打开【加护】。
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 第二层请求上下文；只有【振旗】请求已经完整关闭后才能成为当前唯一选择。
	var jiahu_choice_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(jiahu_choice_context.get("kind", "")) != "jiahu_target" or _controller._rule_continuations.size() != 1:
		return _fail("turn_start_jiahu_second context=%s continuations=%s" % [jiahu_choice_context, _controller._rule_continuations.to_array()])
	# 选择第三名角色接受【加护】；技能结果完成后才允许准备阶段收尾并安排判定阶段。
	if not _submit_pending_choice(1, [], [2], true):
		return false
	if not support_target.chained or support_target.shield != 1 or _controller.has_pending_card_choice() or _controller._rule_continuations.has_pending() or _controller.state.current_phase != "start" or _controller.game_flow_pacer == null or not _controller.game_flow_pacer.has_pending("phase_transition"):
		return _fail("turn_start_complete chained=%s shield=%d pending=%s phase=%s transition=%s" % [support_target.chained, support_target.shield, _controller.has_pending_card_choice(), _controller.state.current_phase, _controller.game_flow_pacer.has_pending("phase_transition") if _controller.game_flow_pacer != null else false])
	_controller.game_flow_pacer.cancel_all()
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
	# 还阳正式运行时订阅；通过真实伤害流程验证标准damage时机，而非只直接调用回调函数。
	huanyang.install()
	_controller.damage(0, 1, 1, "normal", "sha")
	if xveyi_player.hp != 4 or str(huanyang.get_metadata().get("trigger", "")) != "damage":
		return _fail("huanyang_damage_timing hp=%d trigger=%s" % [xveyi_player.hp, huanyang.get_metadata().get("trigger", "")])
	# 标准伤害来源事件；【杀】规则名字数为1，目标是距离1的二号角色。
	# 兼容测试变量仍沿用原有名称；还阳的正式订阅已经由上方真实damage流程覆盖。
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
	# 永屹持有者状态；1点护盾正好满足支付额外出牌阶段费用。
	var gepard: PlayerState = _controller.state.get_player(0)
	gepard.shield = 1
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
	# 确认支付护盾；这是此前额外出牌阶段无法被安排、游戏卡死的路径。
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 阶段转换等待；额外出牌阶段不经过摸牌阶段，因此短暂等待后应稳定进入新的出牌请求。
	await get_tree().create_timer(0.10, false).timeout
	# 永屹结果与额外出牌阶段；护盾已支付、额外阶段回到结束阶段标记存在，且已打开新的正式出牌请求。
	if gepard.shield != 0 or gepard.hand.size() != hand_count_before_yongyi_draw + 1 or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)) or str(_controller._active_extra_play_phase_context.get("return_point", "")) != "finish" or _controller.state.current_phase != "play" or not _controller._has_active_play_choice():
		return _fail("yongyi_resume shield=%d hand=%d return_finish=%s phase=%s play_choice=%s" % [gepard.shield, gepard.hand.size(), _controller._extra_play_phase_returns_to_finish, _controller.state.current_phase, _controller._has_active_play_choice()])
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


## 验证丹恒拥有疾雨时先使用实体雷【杀】，没有实体雷【杀】时把普通黑色【杀】通过罡风转为雷【杀】。
func _test_gangfeng_jiyu_play_priority() -> bool:
	_reset_state(2)
	# 丹恒武将快照；基础策略会从武将静态技能元数据读取疾雨的雷【杀】联动分。
	var dan_heng: PlayerState = _controller.state.get_player(0)
	dan_heng.character_id = "dan_heng"
	# 罡风与疾雨运行时实例；合法动作仍由控制器从真实技能实例生成。
	var gangfeng: SkillDefinition = GameDatabase.create_skill("gangfeng")
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	gangfeng.bind(_controller, 0)
	jiyu.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"gangfeng":gangfeng, "jiyu":jiyu}}
	# 实体雷【杀】；存在时应优先直接使用，避免为相同逻辑牌额外支付罡风材料成本。
	var thunder_slash: CardInstance = _add_hand_card(0, "sha_thunder", "spade", 7)
	# 普通黑色【杀】；实体雷【杀】离开后应成为罡风转换材料，而不是按普通【杀】使用。
	var black_slash: CardInstance = _add_hand_card(0, "sha", "club", 8)
	# 丹恒基础策略；公开领袖对公开反贼的态度保证两张攻击牌都具备正收益。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0)
	var chosen_action: Dictionary = policy.choose_action(_controller.state.to_dict(0, true), _controller.get_legal_actions(0))
	if str(chosen_action.get("action_type", "")) != "use_card" or int(chosen_action.get("card_uid", -1)) != thunder_slash.uid:
		return _fail("jiyu_thunder_first action=%s" % [chosen_action])
	# 移除实体雷【杀】后重新决策；普通黑色【杀】必须进入罡风主动技能动作并保留准确材料UID。
	dan_heng.take_hand_card(thunder_slash.uid)
	chosen_action = policy.choose_action(_controller.state.to_dict(0, true), _controller.get_legal_actions(0))
	var chosen_payload: Dictionary = chosen_action.get("payload", {}) as Dictionary
	if str(chosen_action.get("action_type", "")) != "use_skill" or str(chosen_payload.get("skill_id", "")) != "gangfeng" or int(chosen_payload.get("material_card_uid", -1)) != black_slash.uid:
		return _fail("jiyu_black_slash_conversion action=%s" % [chosen_action])
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
	# 额外出牌阶段可用实体牌；用于验证固定摸牌后仍会正常登记额外出牌阶段。
	_add_hand_card(0, "sha", "club", 6)
	# 永屹固定摸牌来源；数组末尾为牌堆顶，确认后应移入杰帕德手牌。
	var extra_play_draw_card: CardInstance = _add_draw_pile_card("shan", "diamond", 8)
	# 确认前手牌数；用于断言第二段准确摸取1张牌。
	var hand_count_before_extra_play_draw: int = gepard.hand.size()
	# 永屹弃牌阶段确认响应；支付1点护盾后应排队1个额外出牌阶段并标记其结束后直接进入结束阶段。
	var extra_play_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	yongyi.continue_selection({"kind":"yongyi_play_phase_confirm"}, extra_play_response)
	if gepard.shield != 0 or gepard.hand.size() != hand_count_before_extra_play_draw + 1 or gepard.find_hand_card(extra_play_draw_card.uid) == null or int(_controller._extra_play_phase_counts.get(0, 0)) != 1 or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)) or (_controller._extra_play_phase_return_points.get(0, []) as Array) != ["finish"]:
		return _fail("yongyi_extra_play shield=%d hand=%d count=%d return_finish=%s" % [gepard.shield, gepard.hand.size(), int(_controller._extra_play_phase_counts.get(0, 0)), _controller._extra_play_phase_returns_to_finish])
	# 无手牌场景；【永屹】的原始技能逻辑仍须向玩家提供支付护盾的确认窗口，只有AI评分会倾向取消。
	_reset_state(2)
	# 空手牌杰帕德；护盾与弃牌阶段条件都满足，但不额外加入可使用牌。
	var empty_hand_gepard: PlayerState = _controller.state.get_player(0)
	empty_hand_gepard.shield = 1
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
	# 玩家明确确认；无可用牌不应阻止原技能失去护盾、摸1张牌并排队额外出牌阶段。
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 空手牌额外出牌阶段可能同步完成并消耗队列计数；护盾支付、摸到指定实体与返回结束阶段标记共同证明确认按原规则成功登记。
	if empty_hand_gepard.shield != 0 or empty_hand_gepard.hand.size() != 1 or empty_hand_gepard.find_hand_card(empty_hand_draw_card.uid) == null or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)):
		return _fail("yongyi_empty_hand_confirm shield=%d hand=%d return_finish=%s" % [empty_hand_gepard.shield, empty_hand_gepard.hand.size(), _controller._extra_play_phase_returns_to_finish])
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
	# 永屹静态AI技能；可命中敌方的【杀】应使额外出牌收益高于1点护盾。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	yongyi.bind(null, 0)
	# 永屹额外出牌确认请求；显式写入1张可用牌与可命中敌方【杀】。
	var play_request: Dictionary = {"context":{"kind":"yongyi_play_phase_confirm", "usable_card_count":1, "enemy_slash_available":true}}
	# 零牌确认动作；只有技能计算的净收益决定是否发动。
	var confirm_action: Dictionary = {"payload":{"confirmed":true}}
	if yongyi.score_ai_choice(snapshot, play_request, confirm_action, evaluator) <= 0.0:
		return _fail("yongyi_ai_extra_play")
	# 永屹固定摸牌收益不足以覆盖1点护盾；AI 应保持取消，但该评分不影响玩家确认后实际摸1张牌。
	var draw_only_play_request: Dictionary = {"context":{"kind":"yongyi_play_phase_confirm", "usable_card_count":0, "enemy_slash_available":false}}
	if yongyi.score_ai_choice(snapshot, draw_only_play_request, confirm_action, evaluator) >= 0.0:
		return _fail("yongyi_ai_draw_only")
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
