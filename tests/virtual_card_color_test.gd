extends "res://tests/new_character_mechanics_test.gd"

## 多材料转化牌聚合花色与颜色专项回归。
## 覆盖三条稳定规律：全部材料同花色时虚拟牌视为该花色；花色不同但颜色一致时保留该颜色并视为无花色；
## 颜色不一致或存在无花色材料时视为无色牌。同时验证聚合颜色会照常进入使用牌的目标过滤链，
## 使两张黑色牌转化的【杀】无法指定拥有【琥珀】的角色，而红色与无色转化牌不受影响。


## 按独立场景顺序执行聚合规则、山倾、丈八蛇矛与虚拟代理牌颜色断言；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_material_aggregate_rules():
		return
	if not await _test_shanqing_material_color_target_filter():
		return
	if not _test_zhangba_material_color_target_filter():
		return
	if not await _test_multi_material_proxy_color():
		return
	print("VIRTUAL_CARD_COLOR_PASS aggregate shanqing zhangba proxy")
	get_tree().quit(0)


## 等待权威选择请求出现；事件调度按帧预算推进时同步断言会误判为流程缺失。
func _wait_for_pending_choice(max_frames: int = 120) -> bool:
	for _frame_index: int in range(max_frames):
		if _controller.has_pending_card_choice():
			return true
		await get_tree().process_frame
	return false


## 记录首个失败原因并以本专项标记结束进程；复用父类状态位以便调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("VIRTUAL_CARD_COLOR_FAIL %s" % message)
	get_tree().quit(1)
	return false


## 验证纯数据层的材料花色聚合与代理牌颜色覆写；不依赖任何对局状态。
func _test_material_aggregate_rules() -> bool:
	# 两张同花色材料；虚拟牌视为该花色，颜色由花色推导。
	var same_suit_aggregate: Dictionary = VirtualCard.resolve_suit_aggregate(["spade", "spade"])
	if str(same_suit_aggregate.get("suit", "")) != "spade" or str(same_suit_aggregate.get("color", "")) != "black":
		return _fail("aggregate_same_suit=%s" % [same_suit_aggregate])
	# 同色不同花色材料；保留黑色但必须视为无花色。
	var mixed_black_aggregate: Dictionary = VirtualCard.resolve_suit_aggregate(["spade", "club"])
	if str(mixed_black_aggregate.get("suit", "")) != "none" or str(mixed_black_aggregate.get("color", "")) != "black":
		return _fail("aggregate_mixed_black=%s" % [mixed_black_aggregate])
	# 同色不同花色红牌；保留红色且无花色。
	var mixed_red_aggregate: Dictionary = VirtualCard.resolve_suit_aggregate(["heart", "diamond"])
	if str(mixed_red_aggregate.get("suit", "")) != "none" or str(mixed_red_aggregate.get("color", "")) != "red":
		return _fail("aggregate_mixed_red=%s" % [mixed_red_aggregate])
	# 一黑一红材料；整张虚拟牌无色。
	var opposite_aggregate: Dictionary = VirtualCard.resolve_suit_aggregate(["spade", "heart"])
	if str(opposite_aggregate.get("suit", "")) != "none" or str(opposite_aggregate.get("color", "")) != "none":
		return _fail("aggregate_opposite=%s" % [opposite_aggregate])
	# 含无花色材料；不能猜测为其余材料的颜色。
	var colorless_aggregate: Dictionary = VirtualCard.resolve_suit_aggregate(["spade", "none"])
	if str(colorless_aggregate.get("suit", "")) != "none" or str(colorless_aggregate.get("color", "")) != "none":
		return _fail("aggregate_colorless=%s" % [colorless_aggregate])
	# 材料实体集合聚合；结果必须与等价花色序列完全一致。
	var material_cards: Array[CardInstance] = [CardInstance.new("sha", "club", 3), CardInstance.new("shan", "spade", 9)]
	var material_aggregate: Dictionary = VirtualCard.resolve_material_aggregate(material_cards)
	if str(material_aggregate.get("suit", "")) != "none" or str(material_aggregate.get("color", "")) != "black":
		return _fail("aggregate_material_cards=%s" % [material_aggregate])
	# 无花色代理牌颜色覆写；序列化与反序列化后颜色语义都不能丢失。
	var proxy_card: CardInstance = CardInstance.new("sha", "none", 0)
	proxy_card.color_override = "black"
	var restored_card: CardInstance = CardInstance.from_dict(proxy_card.to_dict())
	if proxy_card.get_color() != "black" or restored_card.get_color() != "black" or str(restored_card.to_dict().get("suit", "")) != "none" or str(restored_card.to_dict().get("color_override", "")) != "black":
		return _fail("proxy_color_restore=%s" % [restored_card.to_dict()])
	return true


## 验证【山倾】两张黑色材料转化的【杀】无法指定拥有【琥珀】的角色，红色材料仍可正常指定。
func _test_shanqing_material_color_target_filter() -> bool:
	_reset_state(3)
	_controller.game_flow_interval_seconds = 0.0
	# 一号角色获得临时【琥珀】；其不能成为黑色【杀】的目标。
	if _install_single_skill(1, "hupo") == null:
		return _fail("shanqing_hupo_missing")
	# 山倾持有者；缺少技能实例代表目录或武将引用配置错误。
	var shanqing: SkillDefinition = _install_single_skill(0, "shanqing")
	if shanqing == null:
		return _fail("shanqing_missing")
	# 黑色材料组合；黑桃与梅花花色不同但颜色一致，聚合结果必须是黑色无花色。
	var spade_material: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	var club_material: CardInstance = _add_hand_card(0, "shan", "club", 4)
	var black_material_cards: Array[CardInstance] = [spade_material, club_material]
	var black_overrides: Dictionary = _controller.card_rules.build_material_rule_overrides(black_material_cards)
	if str(black_overrides.get("card_color", "")) != "black":
		return _fail("shanqing_black_overrides=%s" % [black_overrides])
	# 黑色材料的合法目标；一号拥有【琥珀】必须被排除，二号仍应保留。
	var black_target_ids: Array[int] = _controller.card_rules.list_legal_virtual_targets(0, "sha", black_overrides)
	if black_target_ids.has(1) or not black_target_ids.has(2):
		return _fail("shanqing_black_targets=%s" % [black_target_ids])
	# 权威校验与目标枚举必须同源；伪造黑色材料指向一号会得到明确拒绝原因。
	if _controller.card_rules.validate_virtual_use(0, "sha", [1], black_overrides).is_empty():
		return _fail("shanqing_black_validation_accepted")
	# 端到端发动；黑色材料指向一号必须失败且不消耗额度、不移动材料。
	var black_error: String = shanqing.activate({"material_card_uids":[spade_material.uid, club_material.uid], "target_ids":[1]})
	if black_error.is_empty() or not _controller.state.get_player(0).hand.has(spade_material) or not _controller.state.get_player(0).hand.has(club_material):
		return _fail("shanqing_black_activate error=%s hand=%s" % [black_error, _controller.state.get_player(0).hand])
	# 红色材料组合；红桃与方块聚合为红色无花色，仍可指定拥有【琥珀】的角色。
	# 方块效果在使用时必须摸1张牌，牌堆因此需要至少一张实体牌。
	_add_draw_pile_card("shan", "club", 4)
	var heart_material: CardInstance = _add_hand_card(0, "tao", "heart", 5)
	var diamond_material: CardInstance = _add_hand_card(0, "shan", "diamond", 6)
	var red_material_cards: Array[CardInstance] = [heart_material, diamond_material]
	var red_overrides: Dictionary = _controller.card_rules.build_material_rule_overrides(red_material_cards)
	if str(red_overrides.get("card_color", "")) != "red":
		return _fail("shanqing_red_overrides=%s" % [red_overrides])
	if not _controller.card_rules.list_legal_virtual_targets(0, "sha", red_overrides).has(1):
		return _fail("shanqing_red_targets_missing_amber_owner")
	# 红色材料端到端发动；一号应正常成为目标并进入【闪】响应窗口。
	var red_error: String = shanqing.activate({"material_card_uids":[heart_material.uid, diamond_material.uid], "target_ids":[1]})
	if not red_error.is_empty() or not await _wait_for_pending_choice() or int(_controller._pending_card_choice.get("chooser_id", -1)) != 1:
		return _fail("shanqing_red_activate error=%s pending=%s" % [red_error, _controller._pending_card_choice])
	if not _submit_pending_choice(1, [], [], false):
		return false
	return true


## 验证【丈八蛇矛】黑色材料组合的预览、权威校验与 AI 动作枚举都不会指向拥有【琥珀】的角色。
func _test_zhangba_material_color_target_filter() -> bool:
	_reset_state(3)
	_controller.game_flow_interval_seconds = 0.0
	if _install_single_skill(1, "hupo") == null:
		return _fail("zhangba_hupo_missing")
	# 丈八蛇矛实体；主动装备入口必须以真实装备 UID 提交与预览。
	var zhangba: CardInstance = CardInstance.new("zhangba", "spade", 12)
	zhangba.zone = "equipment"
	zhangba.owner_id = 0
	_controller.state.get_player(0).equipment["weapon"] = zhangba
	# 丈八蛇矛卡牌源码；预览与校验必须复用正式入口而非测试内复制规则。
	var zhangba_definition: CardDefinition = GameDatabase.get_card_definition("zhangba")
	if zhangba_definition == null:
		return _fail("zhangba_definition_missing")
	# 黑色材料组合；两张牌各自不是黑桃就是梅花，聚合结果一定是黑色。
	var spade_material: CardInstance = _add_hand_card(0, "sha", "spade", 3)
	var club_material: CardInstance = _add_hand_card(0, "shan", "club", 4)
	var black_material_uids: Array[int] = [spade_material.uid, club_material.uid]
	# 预览结果；黑色组合不能提交到一号，仍应把二号列为合法目标并给出琥珀拒绝原因。
	var black_preview: Dictionary = zhangba_definition.get_play_phase_action_preview(_controller, 0, zhangba.uid, {"material_card_uids":black_material_uids.duplicate()}, [1])
	var black_legal_target_ids: Array = black_preview.get("legal_target_ids", []) as Array
	if bool(black_preview.get("can_submit", false)) or black_legal_target_ids.has(1) or not black_legal_target_ids.has(2) or str(black_preview.get("validation_error", "")).is_empty():
		return _fail("zhangba_black_preview=%s" % [black_preview])
	# 权威提交校验；伪造黑色材料指向一号的主动动作必须被拒绝。
	var black_action: PlayerAction = PlayerAction.new("use_zhangba", 0, zhangba.uid, [1])
	black_action.payload = {"material_card_uids":black_material_uids.duplicate()}
	if zhangba_definition.validate_play_phase_action(_controller, black_action).is_empty():
		return _fail("zhangba_black_action_accepted")
	# 红色材料组合；聚合颜色为红色，仍可指定拥有【琥珀】的角色。
	var heart_material: CardInstance = _add_hand_card(0, "tao", "heart", 7)
	var diamond_material: CardInstance = _add_hand_card(0, "shan", "diamond", 8)
	var red_material_uids: Array[int] = [heart_material.uid, diamond_material.uid]
	var red_preview: Dictionary = zhangba_definition.get_play_phase_action_preview(_controller, 0, zhangba.uid, {"material_card_uids":red_material_uids.duplicate()}, [1])
	if not bool(red_preview.get("can_submit", false)) or not (red_preview.get("legal_target_ids", []) as Array).has(1):
		return _fail("zhangba_red_preview=%s" % [red_preview])
	# AI 动作枚举；每个动作的目标必须与其材料聚合颜色一致，黑色组合不得包含一号。
	var ai_actions: Array[Dictionary] = []
	zhangba_definition.append_play_phase_actions(_controller, 0, zhangba, ai_actions)
	if ai_actions.is_empty():
		return _fail("zhangba_ai_actions_empty")
	for action_data: Dictionary in ai_actions:
		# 当前动作的两张材料实体；按 UID 从发动者手牌读取真实花色。
		var action_material_cards: Array[CardInstance] = []
		for uid_variant: Variant in (action_data.get("payload", {}) as Dictionary).get("material_card_uids", []) as Array:
			# 当前材料实体；缺失代表动作负载与手牌不同步。
			var material_card: CardInstance = _controller.state.get_player(0).find_hand_card(int(uid_variant))
			if material_card != null:
				action_material_cards.append(material_card)
		# 当前动作聚合颜色；黑色组合把一号放进目标列表即为非法预知动作。
		var action_color: String = str(VirtualCard.resolve_material_aggregate(action_material_cards).get("color", "none"))
		if action_color == "black" and (action_data.get("target_ids", []) as Array).has(1):
			return _fail("zhangba_ai_black_action=%s" % [action_data])
	return true


## 验证多材料虚拟代理牌的花色、颜色与点数；处理区实体必须保留聚合结果供防具与来牌时机读取。
func _test_multi_material_proxy_color() -> bool:
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	# 两张同花色黑桃材料；代理牌视为黑桃【杀】，无点数。
	var first_spade: CardInstance = _add_hand_card(0, "shan", "spade", 2)
	var second_spade: CardInstance = _add_hand_card(0, "tao", "spade", 9)
	if not _controller.execute_virtual_card_use(0, "sha", [first_spade.uid, second_spade.uid], [1], ""):
		return _fail("proxy_same_suit_use")
	# 同名花色代理牌；花色与颜色必须同时表达黑桃与黑色。
	var same_suit_proxy: CardInstance = _first_processing_card()
	if same_suit_proxy == null or same_suit_proxy.suit != "spade" or same_suit_proxy.get_color() != "black" or same_suit_proxy.rank != 0:
		return _fail("proxy_same_suit=%s" % [same_suit_proxy.to_dict() if same_suit_proxy != null else {}])
	if not await _wait_for_pending_choice():
		return _fail("proxy_same_suit_no_response")
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 黑桃加梅花材料；花色不同但颜色一致，代理牌必须是无花色黑色牌。
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	var spade_material: CardInstance = _add_hand_card(0, "shan", "spade", 2)
	var club_material: CardInstance = _add_hand_card(0, "tao", "club", 9)
	if not _controller.execute_virtual_card_use(0, "sha", [spade_material.uid, club_material.uid], [1], ""):
		return _fail("proxy_mixed_black_use")
	# 黑色无花色代理牌；这正是【仁王盾】【琥珀】等颜色型规则必须读取的颜色事实。
	var mixed_black_proxy: CardInstance = _first_processing_card()
	if mixed_black_proxy == null or mixed_black_proxy.suit != "none" or mixed_black_proxy.get_color() != "black":
		return _fail("proxy_mixed_black=%s" % [mixed_black_proxy.to_dict() if mixed_black_proxy != null else {}])
	if not await _wait_for_pending_choice():
		return _fail("proxy_mixed_black_no_response")
	if not _submit_pending_choice(1, [], [], false):
		return false
	# 一黑一红材料；代理牌必须是无花色无色牌。
	_reset_state(2)
	_controller.game_flow_interval_seconds = 0.0
	var opposite_spade: CardInstance = _add_hand_card(0, "shan", "spade", 2)
	var opposite_heart: CardInstance = _add_hand_card(0, "tao", "heart", 9)
	if not _controller.execute_virtual_card_use(0, "sha", [opposite_spade.uid, opposite_heart.uid], [1], ""):
		return _fail("proxy_opposite_use")
	# 无色代理牌；既不是红色也不是黑色。
	var opposite_proxy: CardInstance = _first_processing_card()
	if opposite_proxy == null or opposite_proxy.suit != "none" or opposite_proxy.get_color() != "none":
		return _fail("proxy_opposite=%s" % [opposite_proxy.to_dict() if opposite_proxy != null else {}])
	if not await _wait_for_pending_choice():
		return _fail("proxy_opposite_no_response")
	if not _submit_pending_choice(1, [], [], false):
		return false
	return true


## 返回当前处理区的首张虚拟代理牌；处理区为空时返回null供调用方报告具体场景。
func _first_processing_card() -> CardInstance:
	if _controller.state.processing_area.is_empty():
		return null
	return _controller.state.processing_area[0]
