extends Node

## 主演机制与新武将专项回归。覆盖主演唯一性与顶替、座次相邻查询、白露【悬壶】【生息】与刃【万死】【支离】的核心规则。

## 每个机制场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 技能目标指示器请求记录；每项为 {"source_player_id": int, "target_player_ids": Array[int]}。
## 只保存已经发布的公开ID，用于断言【支离】改写后确实重新指示了真实目标。
var _indicator_requests: Array[Dictionary] = []


## 延迟一帧执行全部断言，确保GameDatabase已完成新武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行主演与两名新武将的机制回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_starring_role_uniqueness():
		return
	if not _test_starring_role_death_cleanup():
		return
	if not _test_seat_neighbor_queries():
		return
	if not _test_bailu_metadata():
		return
	if not _test_xuanhu_hand_limit_exemption():
		return
	if not _test_xuanhu_peach_gain_on_death():
		return
	if not _test_shengxi_choice_and_accumulation():
		return
	if not _test_ren_metadata():
		return
	if not _test_zhili_self_target_rules():
		return
	if not _test_zhili_target_rewrite():
		return
	if not _test_zhili_hp_cost_after_resolution():
		return
	if not _test_zhili_rewrite_hits_owner():
		return
	if not _test_wansi_extra_turn():
		return
	if not _test_starring_slash_recovery():
		return
	if not _test_validation_clean():
		return
	if not _test_ai_no_idle_loop():
		return
	print("ZHUYAN_ZHILI_PASS")
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
	# 目标指示器表现监听；技能改写目标后必须重新请求指向新目标，界面才不会再显示改写前的旧箭头。
	_controller.skill_target_indicated.connect(_on_skill_target_indicated)


## 记录一次技能目标指示器请求；只保存来源与目标稳定ID，供改写顺序与来源断言读取。
func _on_skill_target_indicated(source_player_id: int, target_player_ids: Array[int]) -> void:
	_indicator_requests.append({"source_player_id":source_player_id, "target_player_ids":target_player_ids.duplicate()})


## 为当前单项测试创建最小权威状态；一号领袖、二号反贼、三号及以后忠臣使AI态度确定。
func _reset_state(player_count: int) -> void:
	# 专项场景隔离：取消上一场景残留的流程延时与出牌请求标记。
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "zhuyan-zhili"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	# 按场景需要创建最少角色；体力上限统一4点，避免濒死流程干扰规则断言。
	for player_id: int in range(player_count):
		var player: PlayerState = PlayerState.new(player_id, "主演测试玩家%d" % (player_id + 1))
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
	# 主演服务；专项场景不经过开局入口，因此在此按正式配置方式重建。
	_controller.starring_role_service = StarringRoleService.new()
	_controller.starring_role_service.configure(_controller)
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._rule_sequences.clear()
	_controller._hand_view_as_turn_expiries.clear()
	_controller._active_extra_discard_phase.clear()
	_controller._active_independent_play_phase.clear()
	# 专项场景之间清空额外回合队列与恢复栈，避免前一技能登记的回合在后一场景收尾时被消费。
	_controller._extra_turn_queue.clear()
	_controller._extra_turn_resume_player_ids.clear()
	_controller._current_turn_is_extra = false
	_controller._extra_play_phase_counts.clear()
	_controller._extra_play_phase_returns_to_finish.clear()
	_controller._extra_play_phase_return_points.clear()
	_controller._active_extra_play_phase_context.clear()
	_controller._main_phase_play_conversions.clear()
	_controller._active_converted_play_phase_context.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._rule_continuations.reset()
	_controller._cards_used_this_turn_by_player.clear()
	_controller._started_phase_lifecycles.clear()
	_controller._clear_pending_judgment_request()
	_controller._judgment_flow_in_progress = false
	_controller._judgment_resume_needs_result_pause = false
	_controller.ai_coordinator._policies.clear()
	_controller._ai_drive_token += 1
	_controller._scheduled_ai_drive_token = -1
	_controller._scheduled_ai_choice_request_id = -1
	_controller._ai_choice_submit_failures.clear()
	# 固定流程间隔为0；本测试全部同步推进，不依赖墙钟等待。
	_controller.game_flow_interval_seconds = 0.0


## 主演唯一性：第二名角色成为主演时，原主演的主演条目必须被立即移除。
func _test_starring_role_uniqueness() -> bool:
	_reset_state(3)
	if not _controller.set_starring_role(0):
		return _fail("starring_set_first_rejected")
	# 首次成为主演；角标文本、条目ID与排序档位必须与【酩酊】同级。
	var first_player: PlayerState = _controller.state.get_player(0)
	var first_entry: Dictionary = first_player.character_corner_text_entries.get("zhuyan", {}) as Dictionary
	if _controller.get_starring_role_player_id() != 0 or first_player.character_corner_text != "主演" or str(first_entry.get("text", "")) != "主演" or int(first_entry.get("order", -1)) != 50:
		return _fail("starring_first text=%s entry=%s" % [first_player.character_corner_text, first_entry])
	# 幂等重复设置；不应产生第二名主演，也不应移除任何条目。
	if not _controller.set_starring_role(0) or _controller.get_starring_role_player_id() != 0:
		return _fail("starring_idempotent_rejected")
	# 顶替：1号成为主演后原主演条目被移除，全场主演条目数恒为1。
	if not _controller.set_starring_role(1) or _controller.get_starring_role_player_id() != 1:
		return _fail("starring_replace_rejected")
	if not first_player.character_corner_text_entries.is_empty() or first_player.character_corner_text != "":
		return _fail("starring_previous_not_cleared entries=%s text=%s" % [first_player.character_corner_text_entries, first_player.character_corner_text])
	if _count_starring_entries() != 1:
		return _fail("starring_count=%d" % _count_starring_entries())
	# 非主演查询；纯查询端口不得因调用改变任何状态。
	if _controller.is_starring_role(0) or not _controller.is_starring_role(1):
		return _fail("starring_query_mismatch")
	# 无效角色不能成为主演。
	if _controller.set_starring_role(99):
		return _fail("starring_invalid_player_accepted")
	return true


## 主演本人死亡后其主演角标随既有死亡清理一并消失。
func _test_starring_role_death_cleanup() -> bool:
	_reset_state(3)
	if not _controller.set_starring_role(1):
		return _fail("starring_death_setup")
	# 直接把体力压到1点后造成1点伤害，走完整伤害与死亡流程。
	var target: PlayerState = _controller.state.get_player(1)
	target.hp = 1
	_controller.damage(0, 1, 1, "normal", "sha")
	if not target.dying:
		return _fail("starring_death_not_dying hp=%d" % target.hp)
	if not _resolve_dying_to_death(1):
		return _fail("starring_death_unresolved hp=%d alive=%s pending=%s" % [target.hp, target.alive, _controller._pending_card_choice])
	if not target.character_corner_text_entries.is_empty() or _controller.get_starring_role_player_id() != -1:
		return _fail("starring_death_cleanup entries=%s current=%d" % [target.character_corner_text_entries, _controller.get_starring_role_player_id()])
	return true


## 座次相邻查询：8人局一号位相邻八号与二号，死亡角色被跳过，2人局左右邻居去重。
func _test_seat_neighbor_queries() -> bool:
	_reset_state(8)
	if _controller.state.get_seat_neighbor_player_ids(0) != [1, 7]:
		return _fail("neighbor_seat_one=%s" % [_controller.state.get_seat_neighbor_player_ids(0)])
	if _controller.state.get_seat_neighbor_player_ids(3) != [4, 2]:
		return _fail("neighbor_seat_four=%s" % [_controller.state.get_seat_neighbor_player_ids(3)])
	# 二号位死亡后，一号位的下家顺延到三号位，上家仍为八号位。
	_controller.state.get_player(1).alive = false
	if _controller.state.get_seat_neighbor_player_ids(0) != [2, 7]:
		return _fail("neighbor_skip_dead=%s" % [_controller.state.get_seat_neighbor_player_ids(0)])
	# 死亡角色自身没有任何相邻关系。
	if not _controller.state.get_seat_neighbor_player_ids(1).is_empty():
		return _fail("neighbor_dead_target=%s" % [_controller.state.get_seat_neighbor_player_ids(1)])
	# 2人局左右邻居指向同一名角色，去重后只返回一个ID。
	_reset_state(2)
	if _controller.state.get_seat_neighbor_player_ids(0) != [1]:
		return _fail("neighbor_two_players=%s" % [_controller.state.get_seat_neighbor_player_ids(0)])
	# 全场仅一人时没有任何相邻关系。
	_controller.state.get_player(1).alive = false
	if not _controller.state.get_seat_neighbor_player_ids(0).is_empty():
		return _fail("neighbor_single_alive=%s" % [_controller.state.get_seat_neighbor_player_ids(0)])
	return true


## 白露静态资料、技能顺序与四段玩家可见技能原文保持稳定。
func _test_bailu_metadata() -> bool:
	var bailu: Dictionary = GameDatabase.get_character("bailu")
	if str(bailu.get("display_name", "")) != "白露" or str(bailu.get("gender", "")) != "female" or str(bailu.get("faction", "")) != "xianzhou" or int(bailu.get("max_hp", 0)) != 3 or (bailu.get("skills", []) as Array) != ["xuanhu", "shengxi"]:
		return _fail("bailu_metadata=%s" % bailu)
	# 【悬壶】与【生息】原文；逐字锁定全角括号、数值与语句顺序。
	if str(GameDatabase.get_skill("xuanhu").get("description", "")) != "锁定技，你的【桃】不计入手牌上限。当一名角色死亡后，你从牌堆中获得一张【桃】。":
		return _fail("xuanhu_description=%s" % GameDatabase.get_skill("xuanhu").get("description", ""))
	if str(GameDatabase.get_skill("shengxi").get("description", "")) != "每回合限X次，当你使用基本牌时，你可摸1张牌，或令本回合结束后X+1。（X初始为1）":
		return _fail("shengxi_description=%s" % GameDatabase.get_skill("shengxi").get("description", ""))
	# 锁定技不得提供主动按钮。
	if GameDatabase.get_skill("xuanhu").get("lock", false) != true or not (GameDatabase.get_skill("xuanhu").get("enable", []) as Array).is_empty():
		return _fail("xuanhu_lock=%s" % GameDatabase.get_skill("xuanhu"))
	return true


## 【悬壶】效果一：【桃】不计入手牌上限，且该豁免只减少弃牌阶段的溢出张数。
func _test_xuanhu_hand_limit_exemption() -> bool:
	_reset_state(2)
	var bailu: PlayerState = _controller.state.get_player(0)
	bailu.character_id = "bailu"
	bailu.max_hp = 3
	bailu.hp = 3
	# 三张非桃手牌；体力3点使手牌上限为3。
	_add_hand_card(0, "shan", "heart", 2)
	_add_hand_card(0, "sha", "spade", 5)
	_add_hand_card(0, "jiu", "club", 7)
	# 两张【桃】；未安装技能时它们照常计入上限。
	var first_peach: CardInstance = _add_hand_card(0, "tao", "heart", 9)
	var second_peach: CardInstance = _add_hand_card(0, "tao", "diamond", 4)
	var xuanhu: SkillDefinition = _install_single_skill(0, "xuanhu")
	if xuanhu == null:
		return _fail("xuanhu_missing")
	if _controller.count_hand_limit_exempt_cards(0) != 2:
		return _fail("xuanhu_exempt_count=%d" % _controller.count_hand_limit_exempt_cards(0))
	# 手牌5张、上限3点，溢出2张；两张【桃】被豁免后实际需要弃置的张数必须为0。
	var exempt_overflow: int = maxi(maxi(bailu.hand.size() - _controller.count_hand_limit_exempt_cards(0), 0) - bailu.get_hand_limit(), 0)
	if exempt_overflow != 0:
		return _fail("xuanhu_discard_count=%d hand=%d limit=%d" % [exempt_overflow, bailu.hand.size(), bailu.get_hand_limit()])
	# 手牌上限数值本身不被技能改写；豁免只作用于“实际需要弃置的张数”。
	if bailu.get_hand_limit() != 3:
		return _fail("xuanhu_hand_limit_changed=%d" % bailu.get_hand_limit())
	# 卸载技能后豁免立即消失，确认豁免完全由技能钩子提供。
	xuanhu.uninstall()
	_controller.skill_instances_by_player.clear()
	if _controller.count_hand_limit_exempt_cards(0) != 0 or not bailu.hand.has(first_peach) or not bailu.hand.has(second_peach):
		return _fail("xuanhu_exempt_after_uninstall=%d" % _controller.count_hand_limit_exempt_cards(0))
	return true


## 【悬壶】效果二：任意角色死亡后从牌堆取得第一张【桃】；牌堆无桃时不获得任何牌。
func _test_xuanhu_peach_gain_on_death() -> bool:
	_reset_state(3)
	# 牌堆顺序：先两张非桃，再一张【桃】；技能必须取第一张【桃】而不是牌堆顶。
	var top_card: CardInstance = _add_draw_pile_card("shan", "spade", 3)
	var middle_card: CardInstance = _add_draw_pile_card("sha", "club", 6)
	var bottom_peach: CardInstance = _add_draw_pile_card("tao", "heart", 8)
	_install_single_skill(0, "xuanhu")
	var bailu: PlayerState = _controller.state.get_player(0)
	var hand_count_before: int = bailu.hand.size()
	# 二号角色死亡；【悬壶】从句牌堆取得那张【桃】。
	var victim: PlayerState = _controller.state.get_player(2)
	victim.hp = 1
	_controller.damage(0, 2, 1, "normal", "sha")
	if not _resolve_dying_to_death(2):
		return _fail("xuanhu_death_unresolved hp=%d alive=%s pending=%s" % [victim.hp, victim.alive, _controller._pending_card_choice])
	if bailu.hand.size() != hand_count_before + 1 or not bailu.hand.has(bottom_peach):
		return _fail("xuanhu_peach_gain hand=%s" % bailu.hand.map(func(card: CardInstance) -> int: return card.uid))
	if not _controller.state.draw_pile.has(top_card) or not _controller.state.draw_pile.has(middle_card):
		return _fail("xuanhu_draw_pile_disturbed=%s" % _controller.state.draw_pile.map(func(card: CardInstance) -> int: return card.uid))
	# 牌堆已无【桃】；再次有人死亡时手牌数不变且不报错。
	_controller.state.get_player(1).hp = 1
	_controller.damage(0, 1, 1, "normal", "sha")
	if not _resolve_dying_to_death(1):
		return _fail("xuanhu_second_death_unresolved")
	if bailu.hand.size() != hand_count_before + 1:
		return _fail("xuanhu_no_peach_hand=%d" % bailu.hand.size())
	return true


## 【生息】二选一、X 永久累加与每回合额度。
func _test_shengxi_choice_and_accumulation() -> bool:
	_reset_state(2)
	var bailu: PlayerState = _controller.state.get_player(0)
	bailu.character_id = "bailu"
	var shengxi: SkillDefinition = _install_single_skill(0, "shengxi")
	if shengxi == null:
		return _fail("shengxi_missing")
	# 武将牌角标；【生息】安装当刻就必须显示当前X，与【酩酊】【逐风】共用同一条公开文本通道。
	# 条目ID固定为“shengxi:持有者ID”，保证多名持有者各自维护独立角标。
	if str((bailu.character_corner_text_entries.get("shengxi:0", {}) as Dictionary).get("text", "")) != "生息 1":
		return _fail("shengxi_corner_initial=%s" % bailu.character_corner_text_entries)
	# 摸牌候选；使用基本牌后技能创建二选一。
	var basic_card: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	var draw_card: CardInstance = _add_draw_pile_card("shan", "heart", 2)
	var hand_count_before: int = bailu.hand.size()
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":basic_card.uid, "card_id":"sha", "target_ids":[1]})
	if not _controller.has_pending_card_choice():
		return _fail("shengxi_choice_missing")
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "shengxi_option":
		return _fail("shengxi_choice_kind=%s" % _controller._pending_card_choice)
	# 选择“令本回合结束后X+1”；当次不摸牌。
	if not _submit_pending_choice(0, [], [], true, "shengxi_increase"):
		return false
	if bailu.hand.size() != hand_count_before or not _controller.state.draw_pile.has(draw_card):
		return _fail("shengxi_increase_drew_card hand=%d" % bailu.hand.size())
	if int(bailu.character_form_state.get("shengxi_accumulated_x", 1)) != 1:
		return _fail("shengxi_x_changed_in_turn=%d" % int(bailu.character_form_state.get("shengxi_accumulated_x", 1)))
	# 本回合额度为1次，已消耗；再次使用基本牌不得创建新的选择。
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":basic_card.uid, "card_id":"sha", "target_ids":[1]})
	if _controller.has_pending_card_choice():
		return _fail("shengxi_quota_exceeded=%s" % _controller._pending_card_choice)
	# 本回合结束后兑现X+1：X由1变为2，且本回合已消耗的额度不返还。
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	if int(bailu.character_form_state.get("shengxi_accumulated_x", 1)) != 2:
		return _fail("shengxi_x_not_accumulated=%d" % int(bailu.character_form_state.get("shengxi_accumulated_x", 1)))
	# 角标必须随X累加同步刷新，不能停在上一个轮回的旧文本。
	if str((bailu.character_corner_text_entries.get("shengxi:0", {}) as Dictionary).get("text", "")) != "生息 2":
		return _fail("shengxi_corner_accumulated=%s" % bailu.character_corner_text_entries)
	if int(bailu.character_form_state.get("shengxi_uses_this_turn", 0)) != 1:
		return _fail("shengxi_uses_reset=%d" % int(bailu.character_form_state.get("shengxi_uses_this_turn", 0)))
	# 新回合额度刷新为2次；第一次发动选择“摸一张牌”应立即摸到牌堆顶。
	_controller.state.turn_number += 1
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":basic_card.uid, "card_id":"sha", "target_ids":[1]})
	if not _controller.has_pending_card_choice():
		return _fail("shengxi_new_turn_choice_missing")
	hand_count_before = bailu.hand.size()
	if not _submit_pending_choice(0, [], [], true, "shengxi_draw"):
		return false
	if bailu.hand.size() != hand_count_before + 1 or not bailu.hand.has(draw_card):
		return _fail("shengxi_draw_option hand=%s" % bailu.hand.map(func(card: CardInstance) -> int: return card.uid))
	if int(bailu.character_form_state.get("shengxi_accumulated_x", 1)) != 2:
		return _fail("shengxi_x_changed_by_draw=%d" % int(bailu.character_form_state.get("shengxi_accumulated_x", 1)))
	# 取消不消耗额度；本回合仍可再发动一次。
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":basic_card.uid, "card_id":"sha", "target_ids":[1]})
	if not _submit_pending_choice(0, [], [], false):
		return false
	if int(bailu.character_form_state.get("shengxi_uses_this_turn", 0)) != 1:
		return _fail("shengxi_cancel_consumed_quota=%d" % int(bailu.character_form_state.get("shengxi_uses_this_turn", 0)))
	# 非基本牌不触发本技能。
	_controller._emit_rule_timing("useCard", 0, 1, -1, {"card_uid":-1, "card_id":"wuxie", "target_ids":[0]})
	if _controller.has_pending_card_choice():
		return _fail("shengxi_non_basic_triggered=%s" % _controller._pending_card_choice)
	# 他人回合里打出的基本牌：登记必须绑定“使用基本牌时所在的那个回合”，
	# 因此那笔X+1要在**那个回合**结束时兑现，而不是被推迟到白露自己的回合结束。
	_controller.state.turn_number += 1
	_controller.state.current_player_id = 1
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":basic_card.uid, "card_id":"shan", "target_ids":[]})
	if not _controller.has_pending_card_choice():
		return _fail("shengxi_other_turn_choice_missing")
	if not _submit_pending_choice(0, [], [], true, "shengxi_increase"):
		return false
	if int(bailu.character_form_state.get("shengxi_accumulated_x", 1)) != 2:
		return _fail("shengxi_other_turn_x_changed_early=%d" % int(bailu.character_form_state.get("shengxi_accumulated_x", 1)))
	# 持有者自己的回合结束不兑现他人回合的登记：两笔待累加按回合角色分桶，互不串台、也不会被提前吃掉。
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	if int(bailu.character_form_state.get("shengxi_accumulated_x", 1)) != 2:
		return _fail("shengxi_other_turn_settled_by_owner=%d" % int(bailu.character_form_state.get("shengxi_accumulated_x", 1)))
	# 登记所属的1号回合结束：X 在这里才从2变为3。
	_controller._emit_rule_timing("phaseAfter", 1, 1, 1, {"turn_number":_controller.state.turn_number})
	if int(bailu.character_form_state.get("shengxi_accumulated_x", 1)) != 3:
		return _fail("shengxi_other_turn_not_accumulated=%d" % int(bailu.character_form_state.get("shengxi_accumulated_x", 1)))
	return true


## 刃静态资料、技能顺序与两段玩家可见技能原文保持稳定。
func _test_ren_metadata() -> bool:
	var ren: Dictionary = GameDatabase.get_character("ren")
	if str(ren.get("display_name", "")) != "刃" or str(ren.get("gender", "")) != "male" or str(ren.get("faction", "")) != "xinghelieshou" or int(ren.get("max_hp", 0)) != 5 or (ren.get("skills", []) as Array) != ["wansi", "zhili"]:
		return _fail("ren_metadata=%s" % ren)
	# 星核猎手势力配色；本次需求把主题色改为黑紫色。
	if str(GameDatabase.get_faction("xinghelieshou").get("color", "")) != "5b3a7d" or str(GameDatabase.get_faction("xinghelieshou").get("short_name", "")) != "猎":
		return _fail("xinghelieshou_faction=%s" % GameDatabase.get_faction("xinghelieshou"))
	if str(GameDatabase.get_skill("wansi").get("description", "")) != "每回合限一次，当你受到伤害后，若你的体力值为1，你可于本回合结束后成为“主演”并执行一个额外的回合。":
		return _fail("wansi_description=%s" % GameDatabase.get_skill("wansi").get("description", ""))
	if str(GameDatabase.get_skill("zhili").get("description", "")) != "锁定技，你是你自己使用【杀】的合法目标。当“主演”使用【杀】造成伤害时，其回复1点体力。当你使用【杀】指定唯一目标时，你令此【杀】的目标改为与目标角色相邻的角色，此【杀】结算完毕后，你失去1点体力。":
		return _fail("zhili_description=%s" % GameDatabase.get_skill("zhili").get("description", ""))
	if GameDatabase.get_skill("zhili").get("lock", false) != true:
		return _fail("zhili_not_lock=%s" % GameDatabase.get_skill("zhili"))
	return true


## 【支离】效果一：【杀】可以指定自己为目标，其他单目标牌仍然不能。
func _test_zhili_self_target_rules() -> bool:
	_reset_state(3)
	# 未安装【支离】时，普通【杀】不能以自己为目标。
	var plain_slash: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	if _controller.card_rules.validate_use(0, plain_slash, [0]).is_empty():
		return _fail("slash_self_target_allowed_without_skill")
	if _controller.card_rules.list_legal_targets(0, plain_slash).has(0):
		return _fail("slash_self_target_listed_without_skill")
	# 安装【支离】后，【杀】的合法目标包含持有者自己。
	_install_single_skill(0, "zhili")
	if not _controller.card_rules.validate_use(0, plain_slash, [0]).is_empty():
		return _fail("slash_self_target_rejected=%s" % _controller.card_rules.validate_use(0, plain_slash, [0]))
	if not _controller.card_rules.list_legal_targets(0, plain_slash).has(0):
		return _fail("slash_self_target_not_listed=%s" % _controller.card_rules.list_legal_targets(0, plain_slash))
	# 其他“不能以自己为目标”的牌不受本技能影响。
	var steal_card: CardInstance = _add_hand_card(0, "shunshou", "heart", 3)
	if _controller.card_rules.validate_use(0, steal_card, [0]).is_empty() or _controller.card_rules.list_legal_targets(0, steal_card).has(0):
		return _fail("other_card_self_target_leaked")
	return true


## 【支离】效果三：使用【杀】指定唯一目标时，目标整体改写为该目标的相邻角色。
func _test_zhili_target_rewrite() -> bool:
	_reset_state(4)
	var zhili: SkillDefinition = _install_single_skill(0, "zhili")
	if zhili == null:
		return _fail("zhili_missing")
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	# 在权威层登记一次用牌上下文；整牌 useCard 时机经该UID定位到改写对象。
	var card_uid: int = slash_card.uid
	_controller._card_use_contexts[card_uid] = {"actor_id":0, "card_definition_id":"sha", "target_ids":[1]}
	# 清空上一场景遗留的指示器记录，确保下面读取到的是本次改写产生的请求。
	_indicator_requests.clear()
	# 唯一目标为1号位；其存活环相邻角色集合为{2号位, 0号位}（2号位是1号位的下家，0号位是其上家，即持有者自己）。
	# 结算顺序以使用者为起点，因此改写结果按行动顺序重排为[0号位, 2号位]，持有者自己的伤害先结算。
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":card_uid, "card_id":"sha", "target_ids":[1]})
	var rewritten_targets: Array = (_controller._card_use_contexts[card_uid] as Dictionary).get("target_ids", []) as Array
	if rewritten_targets != [0, 2]:
		return _fail("zhili_rewrite=%s" % [rewritten_targets])
	if str((_controller._card_use_contexts[card_uid] as Dictionary).get("targets_replaced_reason", "")) != "zhili":
		return _fail("zhili_rewrite_reason=%s" % (_controller._card_use_contexts[card_uid] as Dictionary))
	# 改写后必须重新请求目标指示器；出牌时播放的原始箭头指向的是旧目标1号位，不重新指示会与实际结算对象不一致。
	if _indicator_requests.size() != 1:
		return _fail("zhili_indicator_count=%s" % [_indicator_requests])
	# 本次指示器请求；来源是持有者本人，目标是改写后的真实结算目标。
	var indicator_request: Dictionary = _indicator_requests[0]
	if (indicator_request.get("target_player_ids", []) as Array) != [0, 2] or int(indicator_request.get("source_player_id", -1)) != 0:
		return _fail("zhili_indicator_request=%s" % [indicator_request])
	# 目标全部无效时端口不发布表现；否则联机端会收到一条没有终点的空指示线。
	if _controller.show_skill_target_indicator(0, [99]):
		return _fail("zhili_indicator_invalid_target")
	if not _controller.show_skill_target_indicator(0, [2]):
		return _fail("zhili_indicator_valid_target")
	# 改写后的目标集合包含持有者自己；原文明确允许该情形。
	if not rewritten_targets.has(0):
		return _fail("zhili_rewrite_self_missing=%s" % [rewritten_targets])
	# 多目标【杀】不触发改写。
	var multi_card: CardInstance = _add_hand_card(0, "sha", "club", 9)
	_controller._card_use_contexts[multi_card.uid] = {"actor_id":0, "card_definition_id":"sha", "target_ids":[1, 2]}
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":multi_card.uid, "card_id":"sha", "target_ids":[1, 2]})
	if ((_controller._card_use_contexts[multi_card.uid] as Dictionary).get("target_ids", []) as Array) != [1, 2]:
		return _fail("zhili_rewrite_multi=%s" % (_controller._card_use_contexts[multi_card.uid] as Dictionary))
	# 非【杀】牌不触发改写。
	var trick_card: CardInstance = _add_hand_card(0, "shunshou", "heart", 3)
	_controller._card_use_contexts[trick_card.uid] = {"actor_id":0, "card_definition_id":"shunshou", "target_ids":[1]}
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":trick_card.uid, "card_id":"shunshou", "target_ids":[1]})
	if ((_controller._card_use_contexts[trick_card.uid] as Dictionary).get("target_ids", []) as Array) != [1]:
		return _fail("zhili_rewrite_non_slash=%s" % (_controller._card_use_contexts[trick_card.uid] as Dictionary))
	# 界面预览提交口径：改写后的目标只是结算目标，不改变玩家选择的目标数量。
	# 【杀】的 max_targets 为1，若用改写结果（这里是两名相邻角色）反向校验玩家选择，
	# 确认按钮会因“目标数量不符合卡牌规则”而永久不可点击，表现为【刃】点【杀】后选谁都点不了确定。
	var rewrite_preview: Dictionary = _controller.get_card_use_preview(0, slash_card.uid, [1])
	if not bool(rewrite_preview.get("can_submit", false)) or not str(rewrite_preview.get("validation_error", "")).is_empty():
		return _fail("zhili_preview_submit=%s" % rewrite_preview)
	# 确认按钮可用的同时，预览仍必须把改写后的真实结算目标交给界面显示。
	if ((rewrite_preview.get("normalized_target_ids", []) as Array)) != [0, 2]:
		return _fail("zhili_preview_targets=%s" % rewrite_preview)
	return true


## 【支离】效果四：被改写的【杀】结算完毕后持有者无条件失去1点体力；无相邻角色时同样支付。
func _test_zhili_hp_cost_after_resolution() -> bool:
	_reset_state(4)
	_install_single_skill(0, "zhili")
	var owner: PlayerState = _controller.state.get_player(0)
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	var card_uid: int = slash_card.uid
	_controller._card_use_contexts[card_uid] = {"actor_id":0, "card_definition_id":"sha", "target_ids":[1]}
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":card_uid, "card_id":"sha", "target_ids":[1]})
	var hp_before: int = owner.hp
	_controller._emit_rule_timing("useCardAfter", 0, 0, -1, {"card_uid":card_uid, "card_id":"sha", "target_ids":[2, 0]})
	if owner.hp != hp_before - 1:
		return _fail("zhili_hp_cost=%d/%d" % [owner.hp, hp_before])
	# 同一张牌重复派发结算完毕时机不会重复扣体力。
	_controller._emit_rule_timing("useCardAfter", 0, 0, -1, {"card_uid":card_uid, "card_id":"sha", "target_ids":[2, 0]})
	if owner.hp != hp_before - 1:
		return _fail("zhili_hp_cost_repeated=%d" % owner.hp)
	# 没有合法相邻角色时保留原目标，代价照付。
	_reset_state(2)
	_install_single_skill(0, "zhili")
	var lone_owner: PlayerState = _controller.state.get_player(0)
	_controller.state.get_player(1).alive = false
	var lone_card: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	_controller._card_use_contexts[lone_card.uid] = {"actor_id":0, "card_definition_id":"sha", "target_ids":[1]}
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":lone_card.uid, "card_id":"sha", "target_ids":[1]})
	if ((_controller._card_use_contexts[lone_card.uid] as Dictionary).get("target_ids", []) as Array) != [1]:
		return _fail("zhili_no_neighbor_rewrite=%s" % (_controller._card_use_contexts[lone_card.uid] as Dictionary))
	var lone_hp_before: int = lone_owner.hp
	_controller._emit_rule_timing("useCardAfter", 0, 0, -1, {"card_uid":lone_card.uid, "card_id":"sha", "target_ids":[1]})
	if lone_owner.hp != lone_hp_before - 1:
		return _fail("zhili_no_neighbor_hp_cost=%d" % lone_owner.hp)
	return true


## 【支离】改写路径：2人局相邻去重后只剩持有者自己，改写必须真实生效且命中自己。
func _test_zhili_rewrite_hits_owner() -> bool:
	_reset_state(2)
	_install_single_skill(0, "zhili")
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	var card_uid: int = slash_card.uid
	_controller._card_use_contexts[card_uid] = {"actor_id":0, "card_definition_id":"sha", "target_ids":[1]}
	_controller._emit_rule_timing("useCard", 0, 0, -1, {"card_uid":card_uid, "card_id":"sha", "target_ids":[1]})
	# 2人局：1号位的左右相邻者是同一个人（0号位），去重后目标数组长度为1且等于持有者自己。
	if ((_controller._card_use_contexts[card_uid] as Dictionary).get("target_ids", []) as Array) != [0]:
		return _fail("zhili_two_player_rewrite=%s" % (_controller._card_use_contexts[card_uid] as Dictionary))
	return true


## 【万死】受到伤害后体力为1时确认发动，并在本回合结束后成为主演且进入额外回合。
func _test_wansi_extra_turn() -> bool:
	_reset_state(2)
	var ren: PlayerState = _controller.state.get_player(0)
	ren.character_id = "ren"
	var wansi: SkillDefinition = _install_single_skill(0, "wansi")
	if wansi == null:
		return _fail("wansi_missing")
	# 体力为3时受到1点伤害后变为2点，不等于1；不创建任何选择。
	ren.hp = 3
	_controller.damage(1, 0, 1, "normal", "sha")
	if _controller.has_pending_card_choice() or ren.hp != 2:
		return _fail("wansi_not_hp_one hp=%d pending=%s" % [ren.hp, _controller._pending_card_choice])
	# 再次受到1点伤害后体力恰为1，触发发动确认。
	_controller.damage(1, 0, 1, "normal", "sha")
	if ren.hp != 1 or not _controller.has_pending_card_choice():
		return _fail("wansi_confirm_missing hp=%d pending=%s" % [ren.hp, _controller._pending_card_choice])
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "wansi_confirm":
		return _fail("wansi_confirm_kind=%s" % _controller._pending_card_choice)
	# 取消不发动；不登记任何待执行效果，也不消耗本回合额度。
	if not _submit_pending_choice(0, [], [], false):
		return false
	if _controller.get_starring_role_player_id() != -1 or not _controller._extra_turn_queue.is_empty():
		return _fail("wansi_cancel_effect starring=%d" % _controller.get_starring_role_player_id())
	# 用护盾吸收一次伤害：体力仍为1且再次触发确认，证明取消没有消耗本回合额度。
	ren.shield = 3
	_controller.damage(1, 0, 1, "normal", "sha")
	if ren.hp != 1 or not _controller.has_pending_card_choice():
		return _fail("wansi_shielded_confirm hp=%d shield=%d pending=%s" % [ren.hp, ren.shield, _controller._pending_card_choice])
	# 确认发动；伤害当刻不执行任何效果，只登记待执行的回合号。
	if not _submit_pending_choice(0, [], [], true, "wansi_confirm_yes"):
		return false
	if _controller.get_starring_role_player_id() != -1 or not _controller._extra_turn_queue.is_empty():
		return _fail("wansi_immediate_effect starring=%d queue=%s" % [_controller.get_starring_role_player_id(), _controller._extra_turn_queue])
	# 本回合结束后兑现两段效果：先成为主演，再登记一个额外回合。
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	if _controller.get_starring_role_player_id() != 0:
		return _fail("wansi_not_starring=%d" % _controller.get_starring_role_player_id())
	if not _controller._extra_turn_queue.has(0):
		return _fail("wansi_no_extra_turn queue=%s" % _controller._extra_turn_queue)
	# 同一个回合号只兑现一次；重复派发本回合结束时机不会再次登记额外回合。
	_controller._extra_turn_queue.clear()
	_controller._emit_rule_timing("phaseAfter", 0, 0, 0, {"turn_number":_controller.state.turn_number})
	if not _controller._extra_turn_queue.is_empty():
		return _fail("wansi_double_settlement queue=%s" % _controller._extra_turn_queue)
	# 他人回合受伤：这是本技能最常见的触发方式（被对手打到1点体力）。
	# 登记必须绑定“受伤所在的那个回合”，因此该回合结束时同样要兑现两段效果；
	# 若只订阅持有者自己的回合，这里的登记在对手回合结束收不到时机、等到自己回合时回合号又已变化，永远不会兑现。
	_reset_state(3)
	var other_turn_ren: PlayerState = _controller.state.get_player(0)
	other_turn_ren.character_id = "ren"
	# 体力先设为2：本次1点伤害把它打到恰好1点，既满足触发条件又不会进入濒死询问。
	other_turn_ren.hp = 2
	_install_single_skill(0, "wansi")
	# 当前回合角色改为1号，模拟“对手的回合里刃被打到1点体力”。
	_controller.state.current_player_id = 1
	_controller.damage(1, 0, 1, "normal", "sha")
	if other_turn_ren.hp != 1 or not _controller.has_pending_card_choice():
		return _fail("wansi_other_turn_confirm_missing hp=%d pending=%s" % [other_turn_ren.hp, _controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], true, "wansi_confirm_yes"):
		return false
	# 与登记回合无关的第三个角色回合结束时不兑现，避免退化成“随便谁的回合结束都生效”。
	_controller._emit_rule_timing("phaseAfter", 2, 2, 2, {"turn_number":_controller.state.turn_number})
	if _controller.get_starring_role_player_id() != -1 or not _controller._extra_turn_queue.is_empty():
		return _fail("wansi_unrelated_turn_settled starring=%d queue=%s" % [_controller.get_starring_role_player_id(), _controller._extra_turn_queue])
	# 该登记所属的1号回合结束：必须在这里兑现，而不是等到0号自己的回合。
	_controller._emit_rule_timing("phaseAfter", 1, 1, 1, {"turn_number":_controller.state.turn_number})
	if _controller.get_starring_role_player_id() != 0:
		return _fail("wansi_other_turn_not_starring=%d" % _controller.get_starring_role_player_id())
	if not _controller._extra_turn_queue.has(0):
		return _fail("wansi_other_turn_no_extra_turn queue=%s" % _controller._extra_turn_queue)
	return true


## 【支离】效果二：任意主演使用【杀】造成伤害时回复1点体力，非主演不回复。
func _test_starring_slash_recovery() -> bool:
	_reset_state(3)
	_install_single_skill(0, "zhili")
	# 1号成为主演并已受伤；其使用【杀】造成伤害时应回复1点体力。
	_controller.set_starring_role(1)
	var starring: PlayerState = _controller.state.get_player(1)
	starring.hp = 2
	_controller.damage(1, 2, 1, "normal", "sha")
	if starring.hp != 3:
		return _fail("starring_slash_recover=%d" % starring.hp)
	# 非主演造成【杀】伤害不回复。
	var plain: PlayerState = _controller.state.get_player(2)
	plain.hp = 2
	_controller.damage(2, 0, 1, "normal", "sha")
	if plain.hp != 2:
		return _fail("non_starring_slash_recover=%d" % plain.hp)
	# 主演造成非【杀】伤害同样不回复；效果只认【杀】牌族。
	starring.hp = 2
	_controller.damage(1, 0, 1, "normal", "shunshou")
	if starring.hp != 2:
		return _fail("non_slash_source_recover=%d" % starring.hp)
	# 体力已满时回复被上限截断；回复收益不得溢出体力上限。
	starring.hp = starring.max_hp
	_controller.damage(1, 0, 1, "normal", "sha")
	if starring.hp != starring.max_hp:
		return _fail("recover_over_max_hp=%d/%d" % [starring.hp, starring.max_hp])
	return true


## 内容校验：新增武将与技能必须通过 GameDatabase 的双向校验；任一条验证错误都会阻止对局开始。
func _test_validation_clean() -> bool:
	# 全局内容校验错误清单；非空即表示本次新增的武将或技能不合法。
	var validation_errors: Array = GameDatabase.validation_errors
	if not validation_errors.is_empty():
		return _fail("validation_errors=%s" % [validation_errors])
	return true


## AI 空转防护：四项技能都不提供出牌阶段主动按钮，因此不存在“反复发动→取消”的入口；
## 仅有的两个可取消窗口必须保证“可发动时的最优选项严格高于取消的0分”，否则AI会持续取消并与请求重建形成空转。
func _test_ai_no_idle_loop() -> bool:
	# 主动按钮检查；任何一项为true都会重新引入“发动→取消”这条路径。
	for skill_id: String in ["xuanhu", "shengxi", "wansi", "zhili"]:
		if bool(GameDatabase.get_skill(skill_id).get("ui_enabled", false)):
			return _fail("ai_active_button skill=%s" % skill_id)
	_reset_state(2)
	# 生息技能实例；本场景只使用它的离线评分入口，不做真实结算。
	var shengxi: SkillDefinition = _install_single_skill(0, "shengxi")
	if shengxi == null:
		return _fail("ai_shengxi_missing")
	# 评分用权威快照与评估器；与基础AI读取同一套公开字段，不访问运行时宿主。
	var evaluator: Object = NonameAIEvaluator.new()
	# 生息请求上下文；X直接由上下文给出，保证AI与规则读到同一个数值。
	var shengxi_request: Dictionary = {"context":{"kind":"shengxi_option", "accumulated_x":1}}
	# 生息摸牌选项的负载；选项ID必须与技能内的稳定ID一致。
	var shengxi_draw_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"shengxi_draw"}}
	# 生息累加选项的负载；与摸牌选项互斥。
	var shengxi_increase_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"shengxi_increase"}}
	# 场景一：X 大于手牌数（空手牌）时摸牌分支必须严格为正、累加分支必须为0。
	var empty_hand_snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 空手牌下的两个选项分；两者必须恰有一个严格大于0，另一个为0。
	var draw_when_empty: float = shengxi.score_ai_choice(empty_hand_snapshot, shengxi_request, shengxi_draw_action, evaluator)
	var increase_when_empty: float = shengxi.score_ai_choice(empty_hand_snapshot, shengxi_request, shengxi_increase_action, evaluator)
	if draw_when_empty <= 0.0 or increase_when_empty != 0.0:
		return _fail("ai_shengxi_draw_branch draw=%f increase=%f" % [draw_when_empty, increase_when_empty])
	# 场景二：X 不大于手牌数时累加分支必须严格为正、摸牌分支必须为0，方向与场景一完全相反。
	for hand_index: int in range(5):
		_add_hand_card(0, "sha", "spade", hand_index + 1)
	var loaded_hand_snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 满载手牌下的两个选项分；两分支取值恒不相等，因此不存在0分平局导致的来回摇摆。
	var draw_when_loaded: float = shengxi.score_ai_choice(loaded_hand_snapshot, shengxi_request, shengxi_draw_action, evaluator)
	var increase_when_loaded: float = shengxi.score_ai_choice(loaded_hand_snapshot, shengxi_request, shengxi_increase_action, evaluator)
	if increase_when_loaded <= 0.0 or draw_when_loaded != 0.0:
		return _fail("ai_shengxi_increase_branch draw=%f increase=%f" % [draw_when_loaded, increase_when_loaded])
	# 万死技能实例与持有者；确认分必须只在体力恰为1时为正。
	var wansi: SkillDefinition = _install_single_skill(1, "wansi")
	if wansi == null:
		return _fail("ai_wansi_missing")
	var wansi_owner: PlayerState = _controller.state.get_player(1)
	# 万死请求上下文与确认负载；选项ID必须与技能内的稳定ID一致。
	var wansi_request: Dictionary = {"context":{"kind":"wansi_confirm"}}
	var wansi_confirm_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"wansi_confirm_yes"}}
	wansi_owner.hp = 1
	# 体力恰为1时的确认分；必须严格大于取消的0分，否则AI永远不会发动这次登记。
	var ready_snapshot: Dictionary = _controller.state.to_dict(0, true)
	var confirm_when_ready: float = wansi.score_ai_choice(ready_snapshot, wansi_request, wansi_confirm_action, evaluator)
	if confirm_when_ready <= 0.0:
		return _fail("ai_wansi_ready_score=%f" % confirm_when_ready)
	# 体力已变化时的确认分；必须为负，避免AI提交一个条件已经失效的登记并让回合尾部空转。
	wansi_owner.hp = 2
	var stale_snapshot: Dictionary = _controller.state.to_dict(0, true)
	var confirm_when_stale: float = wansi.score_ai_choice(stale_snapshot, wansi_request, wansi_confirm_action, evaluator)
	if confirm_when_stale >= 0.0:
		return _fail("ai_wansi_stale_score=%f" % confirm_when_stale)
	return true


## 统计全场携带主演条目的角色数量；用于确认主演唯一性不变量。
func _count_starring_entries() -> int:
	var count: int = 0
	for player: PlayerState in _controller.state.players:
		if player.character_corner_text_entries.has("zhuyan"):
			count += 1
	return count


## 推进濒死结算直到目标角色真正死亡；所有救援请求一律以放弃应答。
## 濒死处理会按行动顺序依次询问存活角色是否使用【桃】，每次应答都可能创建下一名角色的请求，
## 因此需要逐个放弃；迭代上限用于防御异常状态下的死循环，同时允许在无请求时直接推进濒死收尾。
func _resolve_dying_to_death(target_id: int) -> bool:
	var player: PlayerState = _controller.state.get_player(target_id)
	var guard: int = 0
	while player.alive and guard < 16:
		guard += 1
		if not _controller.has_pending_card_choice():
			# 无待应答请求时直接推进濒死收尾；该端口是濒死流程的正式公共入口。
			_controller._finish_dying_rescue(target_id)
			continue
		var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
		if chooser_id < 0:
			return false
		if not _submit_pending_choice(chooser_id, [], [], false):
			return false
	return not player.alive


## 向指定玩家普通手牌区加入一张测试实体；花色、点数、区域与所有者全部显式写入。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向当前测试牌堆底部加入一张实体；数组末尾固定表示最顶层，因此连续追加即自上而下排列。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新牌堆实体；公共牌堆没有所属玩家。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
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
	printerr("ZHUYAN_ZHILI_FAIL %s" % message)
	get_tree().quit(1)
	return false
