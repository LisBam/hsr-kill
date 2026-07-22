class_name OpportunityEffectResolver
extends RefCounted

## 机缘效果解析器。该对象只负责把机缘定义转换为权威规则端口调用，选择编排与触发概率由 OpportunitySystem 管理。

## 机缘系统编排组件；效果完成或被嵌套结算阻塞时通过该对象恢复下一张机缘。
var _system: OpportunitySystem

## 当前对局权威控制器；所有体力、牌区、技能与座次变化均通过其公开接口执行。
var _host: MatchController

## 当前对局权威状态；解析器只读取角色与牌区，不直接修改数组或数值。
var _state: GameState

## 多目标伤害尚未结算的目标队列；顺序严格继承玩家选择顺序，空数组表示没有进行中的批量伤害。
var _pending_damage_target_ids: Array[int] = []

## 多目标伤害来源角色；默认-1，批量伤害完成后立即清空。
var _pending_damage_source_id: int = -1

## 多目标伤害单次固定点数；默认0，只有批量伤害流程活动时为正数。
var _pending_damage_amount: int = 0


## 绑定当前机缘系统、控制器与状态；每局重新调用，避免跨局保存旧状态引用。
func configure(system: OpportunitySystem, host: MatchController, state: GameState) -> void:
	_system = system
	_host = host
	_state = state
	_pending_damage_target_ids.clear()
	_pending_damage_source_id = -1
	_pending_damage_amount = 0


## 解析一张已经完成全体选择的机缘卡；异步目标请求会保留当前效果，选择返回后再通知系统完成。
func resolve_card(owner_player_id: int, card_definition: Dictionary) -> void:
	# 当前效果稳定ID；目录只声明数据，具体规则映射集中在本解析器。
	var effect_id: String = str(card_definition.get("effect", ""))
	match effect_id:
		"draw":
			_host.draw(owner_player_id, int(card_definition.get("count", 0)))
			_system.complete_current_effect()
		"recover":
			_host.recover(owner_player_id, owner_player_id, int(card_definition.get("count", 0)), "opportunity")
			_system.complete_current_effect()
		"hand_limit":
			_host.add_hand_limit_bonus(owner_player_id, int(card_definition.get("count", 0)), "opportunity")
			_system.complete_current_effect()
		"max_hp":
			_host.change_max_hp(owner_player_id, int(card_definition.get("count", 0)), owner_player_id, "opportunity")
			_system.complete_current_effect()
		"recover_full":
			# 机缘持有者；等待全体选择期间可能已经死亡或离场，无效目标只跳过本张效果。
			var recover_owner: PlayerState = _state.get_player(owner_player_id)
			if recover_owner != null:
				_host.recover(owner_player_id, owner_player_id, maxi(recover_owner.max_hp - recover_owner.hp, 0), "opportunity")
			_system.complete_current_effect()
		"grant_skill":
			_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), int(card_definition.get("per_turn_limit", 0)), int(card_definition.get("total_limit", 0)), "opportunity")
			_system.complete_current_effect()
		"double_max_hp":
			# 体力上限翻倍目标；增加量等于结算时的当前上限，后续其他修正不会回溯重算。
			var max_hp_owner: PlayerState = _state.get_player(owner_player_id)
			if max_hp_owner != null:
				_host.change_max_hp(owner_player_id, max_hp_owner.max_hp, owner_player_id, "opportunity")
			_system.complete_current_effect()
		"gain_group_cards":
			_host.gain_group_cards_from_draw_or_discard(owner_player_id, str(card_definition.get("group_kind", "")), card_definition.get("groups", []) as Array, int(card_definition.get("count", 0)), "opportunity")
			_system.complete_current_effect()
		"gain_group_and_skill":
			_host.gain_group_cards_from_draw_or_discard(owner_player_id, str(card_definition.get("group_kind", "")), card_definition.get("groups", []) as Array, int(card_definition.get("count", 0)), "opportunity")
			_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), 0, 0, "opportunity")
			_system.complete_current_effect()
		"gain_named_and_skill":
			# 需要获得的同名牌数量；逐次从摸牌堆或弃牌堆顶部方向检索，缺牌时获得现存数量。
			var named_card_count: int = maxi(int(card_definition.get("count", 0)), 0)
			for _card_index: int in range(named_card_count):
				_host.gain_top_named_card_from_draw_or_discard(owner_player_id, str(card_definition.get("definition_id", "")), "opportunity")
			_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), 0, 0, "opportunity")
			_system.complete_current_effect()
		"extra_turns":
			# 额外回合数量；每次单独入队，确保三个完整回合依次执行后再恢复原本下家。
			var extra_turn_count: int = maxi(int(card_definition.get("count", 0)), 0)
			for _turn_index: int in range(extra_turn_count):
				_host.add_phase(owner_player_id, "opportunity")
			_system.complete_current_effect()
		"discard_two_from_player", "damage_target", "gain_one_from_player", "link_targets", "max_hp_target", "lose_hp_target", "discard_all_hand_target", "swap_seat_target", "damage_targets", "gain_all_hand_target":
			_begin_target_effect(owner_player_id, card_definition)
		_:
			_host.add_log("机缘卡效果不存在：%s。" % effect_id)
			_system.complete_current_effect()


## 恢复机缘解析器创建的目标或区域选牌请求；返回true表示请求已被识别并完成或进入下一段等待。
func continue_choice(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 机缘选择步骤；目标选择和目标区域选牌使用不同稳定值，避免普通卡牌请求误入本解析器。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "opportunity_effect_target":
		# 本张机缘拥有者；效果来源始终是选择该机缘的角色，不等于被选目标。
		var owner_player_id: int = int(context.get("opportunity_owner_id", -1))
		# 机缘卡定义；从静态目录重新取得，防止网络响应修改效果参数。
		var card_definition: Dictionary = OpportunityCatalog.get_card(str(context.get("opportunity_card_id", "")))
		# 玩家提交的目标数组；最多数量已经由ChoiceRequest校验，解析器继续保留点击顺序。
		var target_ids: Array[int] = response.target_ids.duplicate()
		if not response.confirmed:
			target_ids.clear()
		_apply_target_effect(owner_player_id, card_definition, target_ids)
		return true
	if choice_kind == "opportunity_zone_cards":
		# 区域操作类型；discard_two与gain_one共用同一候选场景，但执行不同权威移动。
		var zone_operation: String = str(context.get("zone_operation", ""))
		# 机缘拥有者；弃置时作为规则来源，获得时作为进入手牌的角色。
		var owner_player_id: int = int(context.get("opportunity_owner_id", -1))
		# 区域牌原持有者；等待期间牌可能离区，移动端口会逐张重新校验UID。
		var target_player_id: int = int(context.get("target_player_id", -1))
		if zone_operation == "discard_two":
			_host.discard_selected_player_cards(target_player_id, response.card_ids, owner_player_id)
		elif zone_operation == "gain_one" and response.card_ids.size() == 1:
			_host.take_selected_player_card(owner_player_id, target_player_id, response.card_ids[0])
		_system.complete_current_effect()
		return true
	return false


## 在伤害、失去体力或移牌插入的濒死与技能选择全部结束后恢复当前机缘效果。
func continue_after_barrier() -> bool:
	if not _pending_damage_target_ids.is_empty():
		_resolve_next_pending_damage()
		return true
	return false


## 创建目标选择；AI直接使用同一候选执行策略，人类与网络玩家通过统一ChoiceRequest提交。
func _begin_target_effect(owner_player_id: int, card_definition: Dictionary) -> void:
	# 当前效果稳定ID；决定候选范围、选择数量和AI目标倾向。
	var effect_id: String = str(card_definition.get("effect", ""))
	# 当前合法目标；只包含仍存活且未离场的角色，并按桌面座次排列。
	var target_ids: Array[int] = _get_legal_target_ids(owner_player_id, effect_id)
	# 目标上限；普通单目标效果固定1，至多三名效果从目录读取且不超过实际候选数。
	var maximum_target_count: int = mini(int(card_definition.get("max_targets", 1)), target_ids.size())
	# 目标下限；“至多”效果允许0名，其他存在候选时必须选择1名。
	var minimum_target_count: int = 0 if effect_id in ["link_targets", "damage_targets"] else mini(1, maximum_target_count)
	if maximum_target_count <= 0:
		_system.complete_current_effect()
		return
	if _is_ai_controlled(owner_player_id):
		# AI选择目标；正负效果使用身份态度、牌数和体力进行基础估值，结果仍只来自权威候选。
		var ai_target_ids: Array[int] = _choose_ai_targets(owner_player_id, target_ids, effect_id, maximum_target_count, minimum_target_count)
		_apply_target_effect(owner_player_id, card_definition, ai_target_ids)
		return
	# 玩家可见提示；正文保持机缘卡原文，目标数量由统一选择组件显示。
	var prompt: String = str(card_definition.get("description", "请选择机缘目标。"))
	# 机缘恢复上下文；只保存稳定ID，返回时重新从目录读取完整定义。
	var context: Dictionary = {"kind":"opportunity_effect_target", "opportunity_owner_id":owner_player_id, "opportunity_card_id":str(card_definition.get("id", ""))}
	_host.request_target_choice(owner_player_id, prompt, target_ids, minimum_target_count, maximum_target_count, minimum_target_count == 0, context)


## 执行已经确认的目标效果；需要继续选择区域牌时创建第二段请求，其余效果完成后恢复机缘队列。
func _apply_target_effect(owner_player_id: int, card_definition: Dictionary, target_ids: Array[int]) -> void:
	# 当前效果稳定ID；所有目标在执行前仍由各权威端口重新校验存活与区域状态。
	var effect_id: String = str(card_definition.get("effect", ""))
	if effect_id == "discard_two_from_player":
		if target_ids.size() != 1:
			_system.complete_current_effect()
			return
		_begin_zone_card_choice(owner_player_id, target_ids[0], "discard_two")
		return
	if effect_id == "gain_one_from_player":
		if target_ids.size() != 1:
			_system.complete_current_effect()
			return
		_begin_zone_card_choice(owner_player_id, target_ids[0], "gain_one")
		return
	if effect_id == "damage_target" and target_ids.size() == 1:
		_host.damage(owner_player_id, target_ids[0], int(card_definition.get("count", 0)), "normal", "opportunity")
	elif effect_id == "link_targets":
		for target_id: int in target_ids:
			_host.set_player_linked(target_id, true, owner_player_id, "opportunity")
	elif effect_id == "max_hp_target" and target_ids.size() == 1:
		_host.change_max_hp(target_ids[0], int(card_definition.get("count", 0)), owner_player_id, "opportunity")
	elif effect_id == "lose_hp_target" and target_ids.size() == 1:
		_host.lose_hp(owner_player_id, target_ids[0], int(card_definition.get("count", 0)), "opportunity")
	elif effect_id == "discard_all_hand_target" and target_ids.size() == 1:
		_host.discard_all_hand_cards(target_ids[0], owner_player_id, "opportunity")
	elif effect_id == "swap_seat_target" and target_ids.size() == 1:
		_host.swap_player_seats(owner_player_id, target_ids[0], "opportunity")
	elif effect_id == "damage_targets":
		_pending_damage_source_id = owner_player_id
		_pending_damage_amount = int(card_definition.get("count", 0))
		_pending_damage_target_ids = target_ids.duplicate()
		_resolve_next_pending_damage()
		return
	elif effect_id == "gain_all_hand_target" and target_ids.size() == 1:
		_host.gain_all_hand_cards(owner_player_id, target_ids[0], "opportunity")
	_system.complete_current_effect()


## 依次处理多目标伤害；任一伤害产生濒死或技能选择时登记统一机缘续接，完成后再伤害下一名目标。
func _resolve_next_pending_damage() -> void:
	while not _pending_damage_target_ids.is_empty():
		# 当前伤害目标；从队首取出以严格保留玩家点击顺序。
		var target_id: int = _pending_damage_target_ids.pop_front()
		# 当前目标状态；已死亡或离场目标直接跳过，不改变后续目标顺序。
		var target: PlayerState = _state.get_player(target_id)
		if target == null or not target.alive or target.out_of_game:
			continue
		_host.damage(_pending_damage_source_id, target_id, _pending_damage_amount, "normal", "opportunity")
		if _host.has_nested_settlement_barrier():
			_host.defer_opportunity_resolution()
			return
	# 完成后的来源与伤害值清理；防止下一张普通机缘误认为仍在批量流程。
	_pending_damage_source_id = -1
	_pending_damage_amount = 0
	_system.complete_current_effect()


## 创建目标区域牌选择；AI直接选取稳定候选，人类通过正式卡牌选择面板查看牌背、装备与判定区。
func _begin_zone_card_choice(owner_player_id: int, target_player_id: int, operation: String) -> void:
	# 区域候选；弃置会排除受技能保护的牌，获得只要求牌仍位于目标区域。
	var candidates: Array[Dictionary] = _host.get_opportunity_discard_candidates(owner_player_id, target_player_id) if operation == "discard_two" else _host.get_player_zone_candidates(owner_player_id, target_player_id)
	# 所需数量；弃置固定2张，获得固定1张。
	var required_count: int = 2 if operation == "discard_two" else 1
	if candidates.size() < required_count:
		_system.complete_current_effect()
		return
	if _is_ai_controlled(owner_player_id):
		# AI区域牌结果；弃置优先公开装备与判定牌，获得优先未知手牌，均只使用合法候选UID。
		var selected_uids: Array[int] = []
		for candidate: Dictionary in candidates:
			selected_uids.append(int(candidate.get("uid", -1)))
			if selected_uids.size() >= required_count:
				break
		if operation == "discard_two":
			_host.discard_selected_player_cards(target_player_id, selected_uids, owner_player_id)
		else:
			_host.take_selected_player_card(owner_player_id, target_player_id, selected_uids[0])
		_system.complete_current_effect()
		return
	# 区域选择标题；明确区分弃置与获得，正文数量与机缘规则一致。
	var title: String = "选择弃置牌" if operation == "discard_two" else "选择获得牌"
	# 区域选择提示；正式CardSelectionPanel会继续按手牌、装备与判定区分组显示。
	var prompt: String = "请选择目标区域内的两张牌" if operation == "discard_two" else "请选择目标区域内的一张牌"
	# 第二段恢复上下文；不保存候选副本，提交时由权威移动端口重新校验实体位置。
	var context: Dictionary = {"kind":"opportunity_zone_cards", "zone_operation":operation, "opportunity_owner_id":owner_player_id, "target_player_id":target_player_id}
	_host.request_card_choice(owner_player_id, title, prompt, candidates, required_count, required_count, false, context)


## 返回指定效果的合法目标；特殊区域效果会在本阶段提前筛除没有足够牌的角色。
func _get_legal_target_ids(owner_player_id: int, effect_id: String) -> Array[int]:
	# 合法目标结果；顺序沿用当前座次数组，交换座位后下一次请求自然读取新顺序。
	var result: Array[int] = []
	for player: PlayerState in _state.players:
		if player == null or not player.alive or player.out_of_game:
			continue
		if effect_id in ["swap_seat_target", "gain_all_hand_target", "gain_one_from_player"] and player.player_id == owner_player_id:
			continue
		if effect_id == "discard_two_from_player" and _host.get_opportunity_discard_candidates(owner_player_id, player.player_id).size() < 2:
			continue
		if effect_id == "gain_one_from_player" and _host.get_player_zone_candidates(owner_player_id, player.player_id).is_empty():
			continue
		if effect_id in ["discard_all_hand_target", "gain_all_hand_target"] and player.hand.is_empty():
			continue
		if effect_id == "link_targets" and player.chained:
			continue
		result.append(player.player_id)
	return result


## 判断指定角色当前是否由权威AI控制；离线基础AI、托管AI与掉线AI共用该查询。
func _is_ai_controlled(player_id: int) -> bool:
	return _host != null and _host.ai_coordinator != null and _host.ai_coordinator.is_ai_controlled(player_id)


## 为AI选择机缘目标；优先处理敌对角色，强制单目标没有敌人时回退首个合法目标。
func _choose_ai_targets(owner_player_id: int, target_ids: Array[int], effect_id: String, maximum_count: int, minimum_count: int) -> Array[int]:
	# 敌对目标；负面机缘优先指向非友方，避免基础AI主动伤害队友。
	var hostile_targets: Array[int] = []
	# 友方目标；交换座位等效果没有明确正负收益时作为后备候选。
	var fallback_targets: Array[int] = []
	for target_id: int in target_ids:
		if target_id != owner_player_id and not _host.is_friendly(owner_player_id, target_id):
			hostile_targets.append(target_id)
		else:
			fallback_targets.append(target_id)
	# 候选目标优先级；按效果对体力或牌数做稳定选择，平分保持座次顺序。
	var ordered_targets: Array[int] = hostile_targets.duplicate()
	ordered_targets.append_array(fallback_targets)
	# 选择结果；至多三名效果只选敌方，没有敌人时允许选择0名以避免自损。
	var result: Array[int] = []
	for target_id: int in ordered_targets:
		if effect_id in ["link_targets", "damage_targets"] and not hostile_targets.has(target_id):
			continue
		result.append(target_id)
		if result.size() >= maximum_count:
			break
	if result.size() < minimum_count:
		for target_id: int in ordered_targets:
			if not result.has(target_id):
				result.append(target_id)
			if result.size() >= minimum_count:
				break
	return result
