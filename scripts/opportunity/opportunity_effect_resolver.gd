class_name OpportunityEffectResolver
extends RefCounted

## 机缘效果解析器。该对象只负责把机缘定义转换为权威规则端口调用，选择编排与触发概率由 OpportunitySystem 管理。

## 机缘系统编排组件；效果完成或被嵌套结算阻塞时通过该对象恢复下一张机缘。
var _system: OpportunitySystem

## 当前对局权威控制器；所有体力、牌区、技能与座次变化均通过其公开接口执行。
var _host: MatchController

## 当前对局权威状态；解析器只读取角色与牌区，不直接修改数组或数值。
var _state: GameState

## “任意名角色各弃一张”尚未处理的目标队列；顺序保留玩家提交顺序。
var _pending_discard_one_target_ids: Array[int] = []

## 批量逐目标弃牌的机缘拥有者；默认-1表示当前没有该流程。
var _pending_discard_one_owner_id: int = -1

## 绑定当前机缘系统、控制器与状态；每局重新调用，避免跨局保存旧状态引用。
func configure(system: OpportunitySystem, host: MatchController, state: GameState) -> void:
	_system = system
	_host = host
	_state = state
	_pending_discard_one_target_ids.clear()
	_pending_discard_one_owner_id = -1


## 解析一张已经完成全体选择的机缘卡；异步目标请求会保留当前效果，选择返回后再通知系统完成。
func resolve_card(owner_player_id: int, card_definition: Dictionary) -> void:
	# 当前效果稳定ID；目录只声明数据，具体规则映射集中在本解析器。
	var effect_id: String = str(card_definition.get("effect", ""))
	match effect_id:
		"draw":
			_run_effect_with_completion(func() -> void:
				_host.draw(owner_player_id, int(card_definition.get("count", 0)), true, true)
			)
		"recover":
			_run_effect_with_completion(func() -> void:
				_host.recover(owner_player_id, owner_player_id, int(card_definition.get("count", 0)), "opportunity", true)
			)
		"hand_limit":
			_host.add_hand_limit_bonus(owner_player_id, int(card_definition.get("count", 0)), "opportunity", true)
			_system.complete_current_effect()
		"max_hp":
			_run_effect_with_completion(func() -> void:
				_host.change_max_hp(owner_player_id, int(card_definition.get("count", 0)), owner_player_id, "opportunity", true)
			)
		"recover_full":
			_run_effect_with_completion(func() -> void:
				# 机缘持有者；等待全体选择期间可能已经死亡或离场，无效目标只跳过本张效果。
				var recover_owner: PlayerState = _state.get_player(owner_player_id)
				if recover_owner != null:
					_host.recover(owner_player_id, owner_player_id, maxi(recover_owner.max_hp - recover_owner.hp, 0), "opportunity", true)
			)
		"grant_skill":
			_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), int(card_definition.get("per_turn_limit", 0)), int(card_definition.get("total_limit", 0)), "opportunity", true, int(card_definition.get("per_round_limit", 0)))
			_system.complete_current_effect()
		"draw_phase_bonus", "slash_play_limit_bonus", "damage_bonus", "initial_hand_bonus", "equip_distinct_subtypes":
			# 被动机缘已在全体选择完成时写入角色历史；控制器在对应规则查询点从历史汇总，无须重复修改状态。
			_system.complete_current_effect()
		"double_max_hp":
			_run_effect_with_completion(func() -> void:
				# 体力上限翻倍目标；增加量等于结算时的当前上限，后续其他修正不会回溯重算。
				var max_hp_owner: PlayerState = _state.get_player(owner_player_id)
				if max_hp_owner != null:
					_host.change_max_hp(owner_player_id, max_hp_owner.max_hp, owner_player_id, "opportunity", true)
			)
		"gain_group_cards":
			_run_effect_with_completion(func() -> void:
				_host.gain_group_cards_from_draw_or_discard(owner_player_id, str(card_definition.get("group_kind", "")), card_definition.get("groups", []) as Array, int(card_definition.get("count", 0)), "opportunity", true)
			)
		"gain_group_and_skill":
			_run_effect_with_completion(func() -> void:
				_host.gain_group_cards_from_draw_or_discard(owner_player_id, str(card_definition.get("group_kind", "")), card_definition.get("groups", []) as Array, int(card_definition.get("count", 0)), "opportunity", true)
			, func() -> void:
				_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), 0, 0, "opportunity", true)
			)
		"gain_same_name_length_and_skill":
			_run_effect_with_completion(func() -> void:
				# 同字数取牌数量；目录以4张配置，牌堆与弃牌堆合计不足时按实际可取得数量结算。
				var same_name_length_count: int = maxi(int(card_definition.get("count", 0)), 0)
				_host.gain_same_name_length_cards_from_draw_or_discard(owner_player_id, same_name_length_count, "opportunity", true)
			, func() -> void:
				_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), 0, 0, "opportunity", true)
			)
		"skip_judgment_phase", "skip_discard_phase":
			# 永久跳过阶段只写入机缘历史；控制器在每个对应阶段入口查询历史，避免保存第二份可漂移状态。
			_system.complete_current_effect()
		"refresh_opportunities":
			# 单张刷新概率；目录固定30%，仍通过定义参数读取以便回放与内容校验保持同一来源。
			var upgrade_chance: float = clampf(float(card_definition.get("upgrade_chance", 0.0)), 0.0, 1.0)
			_system.refresh_player_acquired_opportunities(owner_player_id, upgrade_chance)
			_system.complete_current_effect()
		"gain_random_unowned_opportunities":
			# 随机获得数量；组件使用本局统一随机源取得互不重复的未拥有橙色机缘，并将其排入当前角色的后续效果队列。
			var random_opportunity_count: int = maxi(int(card_definition.get("count", 0)), 0)
			_system.grant_random_unowned_opportunities(owner_player_id, str(card_definition.get("quality_id", "")), random_opportunity_count)
			_system.complete_current_effect()
		"gain_named_and_skill":
			_run_effect_with_completion(func() -> void:
				# 需要获得的同名牌数量；逐次从摸牌堆或弃牌堆顶部方向检索，缺牌时获得现存数量。
				var named_card_count: int = maxi(int(card_definition.get("count", 0)), 0)
				_host.gain_group_cards_from_draw_or_discard(owner_player_id, "definition_id", [str(card_definition.get("definition_id", ""))], named_card_count, "opportunity", true)
			, func() -> void:
				_host.grant_acquired_skill(owner_player_id, str(card_definition.get("skill_id", "")), 0, 0, "opportunity", true)
			)
		"extra_turns":
			# 额外回合数量；每次单独入队，确保三个完整回合依次执行后再恢复原本下家。
			var extra_turn_count: int = maxi(int(card_definition.get("count", 0)), 0)
			for _turn_index: int in range(extra_turn_count):
				_host.add_phase(owner_player_id, "opportunity", true)
			_system.complete_current_effect()
		"turn_over_all_others":
			# 其他角色目标；按当前座次依次翻面，死亡或离场角色不进入队列。
			var other_target_ids: Array[int] = []
			for player: PlayerState in _state.players:
				if player.player_id != owner_player_id and player.alive and not player.out_of_game:
					other_target_ids.append(player.player_id)
			_begin_turn_over_targets(other_target_ids)
		"virtual_card_use":
			_resolve_virtual_card_use(owner_player_id, card_definition)
		"gain_distinct_delayed":
			_begin_transfer_cards(owner_player_id, _host.get_distinct_delayed_trick_card_uids(int(card_definition.get("count", 0))), "opportunity_distinct_delayed")
		"view_all_hand_as":
			_host.set_all_hand_cards_view_as(owner_player_id, str(card_definition.get("definition_id", "")), "opportunity", true)
			_system.complete_current_effect()
		"gain_all_equipment":
			_begin_transfer_cards(owner_player_id, _host.get_all_global_equipment_card_uids(), "opportunity_gain_all_equipment")
		"gain_random_zone_cards_each":
			_begin_transfer_cards(owner_player_id, _host.get_random_zone_card_uids_for_each_player(owner_player_id, int(card_definition.get("count", 0))), "opportunity_random_zone_gain")
		"discard_own_zone_and_draw":
			_begin_discard_own_zone_and_draw(owner_player_id, card_definition)
		"discard_two_from_player", "damage_target", "gain_one_from_player", "link_targets", "max_hp_target", "lose_hp_target", "discard_all_hand_target", "swap_seat_target", "damage_targets", "gain_all_hand_target", "discard_one_each_target", "swap_equipment_targets", "discard_half_all_cards_target", "swap_hand_targets", "lose_half_hp_target", "remove_until_round_end_target", "reduce_half_max_hp_target", "damage_current_hp_target", "swap_character_targets", "turn_over_target":
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
		# 区域操作类型；固定弃置、获得、弃置后摸牌与目标自主弃半均复用同一候选场景。
		var zone_operation: String = str(context.get("zone_operation", ""))
		# 机缘拥有者；弃置时作为规则来源，获得时作为进入手牌的角色。
		var owner_player_id: int = int(context.get("opportunity_owner_id", -1))
		# 区域牌原持有者；等待期间牌可能离区，移动端口会逐张重新校验UID。
		var target_player_id: int = int(context.get("target_player_id", -1))
		_run_zone_operation(owner_player_id, target_player_id, zone_operation, response.card_ids if response.confirmed else [])
		return true
	if choice_kind == "opportunity_multi_discard_one":
		# 当前逐目标弃牌来源与目标；本请求只允许选择该名角色区域内的一张合法牌。
		var owner_player_id: int = int(context.get("opportunity_owner_id", -1))
		var target_player_id: int = int(context.get("target_player_id", -1))
		# 外层恢复点；所选牌的失去与装备离区后续必须完成后才进入下一名目标。
		var continuation_guard_id: int = _host.begin_opportunity_resolution_guard()
		if response.confirmed and response.card_ids.size() == 1:
			_host.discard_selected_player_cards(target_player_id, response.card_ids, owner_player_id)
		if _host.has_nested_settlement_barrier():
			return true
		_host.cancel_opportunity_resolution_guard(continuation_guard_id)
		_process_next_discard_one_target()
		return true
	return false


## 在伤害、失去体力或移牌插入的濒死与技能选择全部结束后恢复当前机缘效果。
func continue_after_barrier() -> bool:

	if not _pending_discard_one_target_ids.is_empty() or _pending_discard_one_owner_id >= 0:
		_process_next_discard_one_target()
		return true
	return false


## 创建目标选择；AI直接使用同一候选执行策略，人类与网络玩家通过统一ChoiceRequest提交。
func _begin_target_effect(owner_player_id: int, card_definition: Dictionary) -> void:
	# 当前效果稳定ID；决定候选范围、选择数量和AI目标倾向。
	var effect_id: String = str(card_definition.get("effect", ""))
	# 当前合法目标；只包含仍存活且未离场的角色，并按桌面座次排列。
	var target_ids: Array[int] = _get_legal_target_ids(owner_player_id, effect_id)
	# 目标上限；双角色交换固定2名，任意名与至多效果读取目录并收敛到实际候选数。
	var maximum_target_count: int = mini(int(card_definition.get("max_targets", 1)), target_ids.size())
	# 目标下限；“任意名/至多”允许0名，交换类固定选择2名，其他存在候选时必须选择1名。
	var minimum_target_count: int = 0 if effect_id in ["link_targets", "damage_targets", "discard_one_each_target"] else (2 if effect_id in ["swap_equipment_targets", "swap_hand_targets", "swap_character_targets"] else mini(1, maximum_target_count))
	if effect_id in ["swap_equipment_targets", "swap_hand_targets", "swap_character_targets"]:
		maximum_target_count = mini(2, target_ids.size())
	if maximum_target_count <= 0:
		_system.complete_current_effect()
		return
	if minimum_target_count > maximum_target_count:
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
	var context: Dictionary = {"kind":"opportunity_effect_target", "opportunity_owner_id":owner_player_id, "opportunity_card_id":str(card_definition.get("id", "")), "allow_out_of_game_chooser":true}
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
	if effect_id == "discard_one_each_target":
		_pending_discard_one_owner_id = owner_player_id
		_pending_discard_one_target_ids = target_ids.duplicate()
		_process_next_discard_one_target()
		return
	if effect_id == "discard_half_all_cards_target" and target_ids.size() == 1:
		_begin_discard_half_all_cards(owner_player_id, target_ids[0])
		return
	if effect_id == "swap_hand_targets" and target_ids.size() == 2:
		_begin_hand_swap(target_ids[0], target_ids[1])
		return
	if effect_id == "swap_equipment_targets" and target_ids.size() == 2:
		_begin_equipment_swap(target_ids[0], target_ids[1])
		return
	if effect_id == "gain_all_hand_target" and target_ids.size() == 1:
		_begin_transfer_cards(owner_player_id, _host.get_hand_card_uids(target_ids[0]), "opportunity_gain_all_hand")
		return
	if effect_id == "damage_targets":
		# 玩家选择顺序和伤害值属于同一可暂停机缘序列；每个目标的完整伤害子树结束后才进入下一名。
		var damage_context: Dictionary = {
			"sequence_kind":"opportunity_damage_targets",
			"source_id":owner_player_id,
			"amount":int(card_definition.get("count", 0)),
			"target_ids":target_ids.duplicate(),
			"target_index":0,
		}
		_host.run_rule_sequence([_resolve_sequence_damage_target], damage_context)
		return
	if effect_id == "turn_over_target" and target_ids.size() == 1:
		_begin_turn_over_targets(target_ids)
		return
	if effect_id == "discard_all_hand_target" and target_ids.size() == 1:
		_host.run_rule_sequence([
			func(_sequence: RuleStepSequence) -> void: _host.discard_all_hand_cards(target_ids[0], owner_player_id, "opportunity"),
			_complete_effect_step,
		], {"sequence_kind":"opportunity_discard_all"})
		return
	if effect_id == "link_targets":
		_begin_link_or_turn_targets(target_ids, true, owner_player_id)
		return
	if effect_id in ["max_hp_target", "lose_hp_target", "lose_half_hp_target", "reduce_half_max_hp_target"] and target_ids.size() == 1:
		_run_effect_with_completion(Callable(self, "_change_target_health").bind(effect_id, owner_player_id, target_ids[0], int(card_definition.get("count", 0))))
		return
	# 外层机缘恢复点；下列体力、伤害、弃牌和状态变化产生的内部续接必须先完成。
	var continuation_guard_id: int = _host.begin_opportunity_resolution_guard()
	if effect_id == "damage_target" and target_ids.size() == 1:
		_host.damage(owner_player_id, target_ids[0], int(card_definition.get("count", 0)), "normal", "opportunity")
	elif effect_id == "swap_seat_target" and target_ids.size() == 1:
		_host.swap_player_seats(owner_player_id, target_ids[0], "opportunity")
	elif effect_id == "remove_until_round_end_target" and target_ids.size() == 1:
		_host.remove_player_until_round_end(target_ids[0], "opportunity")
	elif effect_id == "damage_current_hp_target" and target_ids.size() == 1:
		# 伤害基数锁定为结算时目标当前体力值；护盾、防具和伤害时机仍可按普通伤害规则修改结果。
		var current_hp_target: PlayerState = _state.get_player(target_ids[0])
		if current_hp_target != null:
			_host.damage(owner_player_id, target_ids[0], maxi(current_hp_target.hp, 0), "normal", "opportunity")
	elif effect_id == "swap_character_targets" and target_ids.size() == 2:
		_host.swap_player_character_cards(target_ids[0], target_ids[1], "opportunity")
	if _host.has_nested_settlement_barrier():
		return
	_host.cancel_opportunity_resolution_guard(continuation_guard_id)
	_system.complete_current_effect()


## 建立一组按座次或玩家选择顺序结算的翻面目标；空目标直接完成本张机缘。
func _begin_turn_over_targets(target_ids: Array[int]) -> void:
	_begin_link_or_turn_targets(target_ids, false, -1)


## 每名目标状态完整结束后再执行下一名；移除逐目标手工恢复数组，最终完成通知归父内容持有。
func _begin_link_or_turn_targets(target_ids: Array[int], link: bool, source_id: int) -> void:
	# 有限目标步骤；稳定ID绑定到回调，不共享循环中的可变目标引用。
	var steps: Array[Callable] = []
	for target_id: int in target_ids:
		steps.append(_change_target_orientation.bind(target_id, link, source_id))
	steps.append(_complete_effect_step)
	_host.run_rule_sequence(steps, {"sequence_kind":"opportunity_orientation"})


## 调用统一状态结果；直接规则父子归属保证预算让帧与After子内容也完整等待。
func _change_target_orientation(_sequence: RuleStepSequence, target_id: int, link: bool, source_id: int) -> void:
	if link:
		_host.set_player_linked(target_id, true, source_id, "opportunity")
	else:
		_host.turn_over_player(target_id, source_id, "opportunity")


## 以无实体材料的完整卡牌流程结算机缘“视为使用”；群体目标、响应与无懈均由卡牌规则层自动建立。
func _resolve_virtual_card_use(owner_player_id: int, card_definition: Dictionary) -> void:
	# 虚拟牌定义ID；当前支持南蛮入侵与万箭齐发，目录可继续复用本效果类型登记其他牌。
	var definition_id: String = str(card_definition.get("definition_id", ""))
	# 机缘虚拟牌规则覆写；忽略当前阶段、次数以及离场拥有者限制，但不跳过目标合法性、响应或防具。
	var rule_overrides: Dictionary = {"ignore_phase_limit":true, "ignore_play_count_limit":true, "allow_out_of_game_actor":true}
	# 当前合法目标；全体牌最终仍由normalize_targets按行动顺序重新展开。
	var target_ids: Array[int] = _host.card_rules.list_legal_virtual_targets(owner_player_id, definition_id, rule_overrides)
	# 玩家可见日志；牌名使用当前名称模式，不修改机缘卡原文。
	var log_message: String = "%s因机缘视为使用%s。" % [_host.format_player_log_name(owner_player_id), _host.format_card_definition_log_name(definition_id)]
	# 外层机缘恢复点；必须先于虚拟牌内部响应/无懈续接入栈，保证父牌完整结束后才推进下一张机缘。
	var continuation_guard_id: int = _host.begin_opportunity_resolution_guard()
	_host.execute_cardless_virtual_card_use(owner_player_id, definition_id, target_ids, log_message, rule_overrides)
	if _host.has_nested_settlement_barrier():
		return
	_host.cancel_opportunity_resolution_guard(continuation_guard_id)
	_system.complete_current_effect()


## 锁定一批实体牌并逐张交入同一角色手牌；每张移动后检查嵌套结算屏障。
func _begin_transfer_cards(receiver_id: int, card_uids: Array[int], reason: String) -> void:
	# 原牌身份条目；构造后由同一规则序列逐张处理，不另设恢复队列。
	var entries: Array[Dictionary] = []
	# 本次实体UID；只处理最初选定牌，不临时补取替代实体。
	for card_uid: int in card_uids:
		entries.append({"card_uid":card_uid, "receiver_id":receiver_id, "reason":reason})
	_start_transfer_steps(entries)


## 逐张获得实体牌；来源位置、双方代次与完成通知都归本次步骤内容所有。
func _start_transfer_steps(entries: Array[Dictionary]) -> void:
	# 本次内容；每张移动完整After后再进入下一张，最终完成机缘效果。
	var steps: Array[Callable] = []
	# 当前声明条目；稳定快照在首张移动前一次性锁定。
	for entry: Dictionary in entries:
		# 来源快照不含实体引用；同牌已经离区或换将时，本条目明确失败而不是获得新来源牌。
		var source_snapshot: Dictionary = _host.get_card_location_snapshot(int(entry.get("card_uid", -1)))
		# 接收角色；后续换将不得把本机缘交给的新牌塞入新武将区域。
		var receiver: PlayerState = _state.get_player(int(entry.get("receiver_id", -1)))
		source_snapshot["receiver_character_generation"] = receiver.character_generation if receiver != null else -1
		steps.append(_transfer_card_step.bind(entry.duplicate(true), source_snapshot))
	steps.append(_complete_effect_step)
	_host.run_rule_sequence(steps, {"sequence_kind":"opportunity_transfer"})


## 单条移牌在公共服务中产生独立结果；父步骤自然等待，不根据全局是否存在选择推测完成。
func _transfer_card_step(_sequence: RuleStepSequence, entry: Dictionary, source_snapshot: Dictionary) -> void:
	_host.gain_card_to_hand_by_uid(int(entry.get("receiver_id", -1)), int(entry.get("card_uid", -1)), str(entry.get("reason", "opportunity")), true, source_snapshot)


## 区域操作先完成实际移牌及其子内容，再统一通知机缘效果完成。
func _run_zone_operation(owner_player_id: int, target_player_id: int, operation: String, selected_uids: Array[int]) -> void:
	_host.run_rule_sequence([_apply_zone_operation_step, _complete_effect_step], {"sequence_kind":"opportunity_zone_move", "owner_player_id":owner_player_id, "target_player_id":target_player_id, "operation":operation, "selected_uids":selected_uids.duplicate()})


## 应用一次已接受的区域选择；费用回调产生的摸牌仍由同一父内容等待。
func _apply_zone_operation_step(sequence: RuleStepSequence) -> void:
	# 原机缘拥有者；获得与弃后摸牌均归此角色。
	var owner_player_id: int = int(sequence.context.owner_player_id)
	# 原目标；所选实体与区域由实际移动服务重新校验。
	var target_player_id: int = int(sequence.context.target_player_id)
	# 已接受实体身份；不遍历变化中的源区域数组。
	var selected_uids: Array[int] = []
	selected_uids.assign(sequence.context.selected_uids as Array)
	match str(sequence.context.operation):
		"discard_two", "discard_half_all":
			_host.discard_selected_player_cards(target_player_id, selected_uids, owner_player_id)
		"gain_one":
			if selected_uids.size() == 1:
				_host.take_selected_player_card(owner_player_id, target_player_id, selected_uids[0])
		"discard_and_draw":
			_host.discard_selected_player_cards(target_player_id, selected_uids, owner_player_id, func(discarded_count: int) -> void: _host.draw(owner_player_id, discarded_count, true, true))


## 全部原牌已处理后通知机缘系统；取消单张移动不跳过剩余实体。
func _complete_effect_step(_sequence: RuleStepSequence) -> void:
	_system.complete_current_effect()


## 锁定双方当前全部普通手牌并建立双向转移队列；之后获得的新牌不参与本次交换。
func _begin_hand_swap(first_player_id: int, second_player_id: int) -> void:
	# 双方原手牌快照；交牌内容只拥有这些UID，不遍历移动中的可变数组。
	var entries: Array[Dictionary] = []
	# 第一方原手牌身份；接收者固定为第二方。
	for card_uid: int in _host.get_hand_card_uids(first_player_id):
		entries.append({"card_uid":card_uid, "receiver_id":second_player_id, "reason":"opportunity_hand_swap"})
	# 第二方原手牌身份；首张移动前即锁定，避免把刚收到的牌再次交回。
	for card_uid: int in _host.get_hand_card_uids(second_player_id):
		entries.append({"card_uid":card_uid, "receiver_id":first_player_id, "reason":"opportunity_hand_swap"})
	_host.add_log("%s与%s交换所有手牌。" % [_host.format_player_log_name(first_player_id), _host.format_player_log_name(second_player_id)])
	_start_transfer_steps(entries)


## 建立双方全部装备的两阶段交换；先把原装备全部移入处理区，再装入对方对应槽位。
func _begin_equipment_swap(first_player_id: int, second_player_id: int) -> void:
	# 原装备身份与双方代次；分阶段移动不接纳等待期间出现的替代牌。
	var entries: Array[Dictionary] = _host.get_equipment_swap_entries(first_player_id, second_player_id)
	# 有限交换步骤；全部离区完成后才逐张安装，后置结束后只通知一次。
	var steps: Array[Callable] = []
	for entry: Dictionary in entries:
		entry["source_generation"] = _state.get_player(int(entry.source_player_id)).character_generation
		entry["target_generation"] = _state.get_player(int(entry.target_player_id)).character_generation
		steps.append(_evacuate_equipment_step.bind(entry.duplicate(true)))
		steps.append(_record_equipment_evacuation.bind(int(entry.card_uid)))
	for entry: Dictionary in entries:
		steps.append(_install_swapped_equipment_step.bind(entry.duplicate(true)))
		steps.append(_finish_swapped_equipment_step.bind(int(entry.card_uid)))
	steps.append(_complete_effect_step)
	_host.add_log("%s与%s交换装备区内的所有牌。" % [_host.format_player_log_name(first_player_id), _host.format_player_log_name(second_player_id)])
	_host.run_rule_sequence(steps, {"sequence_kind":"opportunity_equipment_swap", "evacuated_uids":[]})


## 原来源代次保持一致时才尝试离区；白银狮子回复和木牛清粮由移牌子内容等待。
func _evacuate_equipment_step(sequence: RuleStepSequence, entry: Dictionary) -> void:
	sequence.effect_result = null
	# 原装备持有者；换将时不能处理其新武将区域。
	var source: PlayerState = _state.get_player(int(entry.source_player_id))
	if source != null and source.character_generation == int(entry.source_generation):
		sequence.effect_result = _host.move_equipment_card_to_processing(source.player_id, int(entry.card_uid), "opportunity_equipment_swap")


## 只记录真实移入处理区且完整结束的成员；被取消的源装备不进入安装列表。
func _record_equipment_evacuation(sequence: RuleStepSequence, card_uid: int) -> void:
	if sequence.effect_result != null and sequence.effect_result.count == 1:
		(sequence.context.evacuated_uids as Array).append(card_uid)


## 原目标代次与处理区身份都有效时安装；占用或废除的栏位不覆盖现有实体。
func _install_swapped_equipment_step(sequence: RuleStepSequence, entry: Dictionary) -> void:
	sequence.effect_result = null
	if not (sequence.context.evacuated_uids as Array).has(int(entry.card_uid)):
		return
	# 原接收者；死亡、离场和代次由移动服务继续校验。
	var target: PlayerState = _state.get_player(int(entry.target_player_id))
	if target != null and target.character_generation == int(entry.target_generation):
		sequence.effect_result = _host.move_processing_card_to_equipment(target.player_id, int(entry.card_uid), str(entry.slot), "opportunity_equipment_swap")


## 已离区而未装入的成员按普通处理区回收结算；不强制搬牌或清空原角色数组。
func _finish_swapped_equipment_step(sequence: RuleStepSequence, card_uid: int) -> void:
	if not (sequence.context.evacuated_uids as Array).has(card_uid):
		return
	# 成员当前区域；After中被技能取得的牌不再回收。
	var location: Dictionary = _host.get_card_location_snapshot(card_uid)
	if str(location.get("zone", "")) == "processing":
		_host._begin_single_discard(card_uid, -1, ["processing"], -2, "equipment_swap_discard")



## 让机缘拥有者选择自己区域内任意张可弃置牌，实际弃置后摸等量牌。
func _begin_discard_own_zone_and_draw(owner_player_id: int, card_definition: Dictionary) -> void:
	# 自己区域候选；包含普通手牌、装备和判定区，并应用最终弃置保护规则。
	var candidates: Array[Dictionary] = _host.get_opportunity_discard_candidates(owner_player_id, owner_player_id)
	if _is_ai_controlled(owner_player_id):
		# AI优先弃置自己判定区内的负担牌；没有公开负担时保留资源，不为换牌盲目弃置高价值手牌。
		var selected_uids: Array[int] = []
		for candidate: Dictionary in candidates:
			if str(candidate.get("zone", "")) == "judgment":
				selected_uids.append(int(candidate.get("uid", -1)))
		# 外层恢复点；AI弃牌与等量摸牌使用和真人提交完全相同的嵌套顺序。
		var continuation_guard_id: int = _host.begin_opportunity_resolution_guard()
		_host.discard_selected_player_cards(owner_player_id, selected_uids, owner_player_id, func(discarded_count: int) -> void:
			_host.draw(owner_player_id, discarded_count, true, true)
		)
		if _host.has_nested_settlement_barrier():
			return
		_host.cancel_opportunity_resolution_guard(continuation_guard_id)
		_system.complete_current_effect()
		return
	# 可取消任意数量选择；0张合法表示主动不弃置也不摸牌。
	var context: Dictionary = {"kind":"opportunity_zone_cards", "zone_operation":"discard_and_draw", "opportunity_owner_id":owner_player_id, "target_player_id":owner_player_id, "opportunity_card_id":str(card_definition.get("id", "")), "allow_out_of_game_chooser":true}
	_host.request_card_choice(owner_player_id, "选择弃置牌", str(card_definition.get("description", "请选择要弃置的牌。")), candidates, 0, candidates.size(), true, context)


## 令目标根据结算时全部区域牌数弃置一半并向上取整；目标本人负责选择具体实体牌。
func _begin_discard_half_all_cards(owner_player_id: int, target_player_id: int) -> void:
	# 目标全部区域牌数量；所有牌仅统计普通手牌、装备区和判定区，不包含木牛“粮”。
	var all_card_count: int = _host.get_discardable_count(target_player_id)
	# 理论弃置数；候选受保护导致不足时改为弃置全部当前合法候选。
	var requested_count: int = ceili(float(all_card_count) / 2.0)
	# 当前合法弃置候选；最终提交时仍按UID逐张复核。
	var candidates: Array[Dictionary] = _host.get_opportunity_discard_candidates(owner_player_id, target_player_id)
	var required_count: int = mini(requested_count, candidates.size())
	if required_count <= 0:
		_system.complete_current_effect()
		return
	if _is_ai_controlled(target_player_id):
		# AI作为被迫弃牌者按稳定候选顺序支付；所有牌面只来自自己的权威可见区域。
		var selected_uids: Array[int] = []
		for candidate_index: int in range(required_count):
			selected_uids.append(int(candidates[candidate_index].get("uid", -1)))
		# 外层恢复点；被迫弃置产生的技能和装备后续完成后才结束本张机缘。
		var continuation_guard_id: int = _host.begin_opportunity_resolution_guard()
		_host.discard_selected_player_cards(target_player_id, selected_uids, owner_player_id)
		if _host.has_nested_settlement_barrier():
			return
		_host.cancel_opportunity_resolution_guard(continuation_guard_id)
		_system.complete_current_effect()
		return
	# 目标本人选择需要弃置的准确数量；机缘拥有者只决定目标，不读取其隐藏手牌牌面。
	var context: Dictionary = {"kind":"opportunity_zone_cards", "zone_operation":"discard_half_all", "opportunity_owner_id":owner_player_id, "target_player_id":target_player_id, "allow_out_of_game_chooser":false}
	_host.request_card_choice(target_player_id, "弃置一半牌", "请选择%d张牌弃置" % required_count, candidates, required_count, required_count, false, context)


## 依次处理“任意名角色区域内各一张牌”；每名目标单独建立一次权威区域选择。
func _process_next_discard_one_target() -> void:
	while not _pending_discard_one_target_ids.is_empty():
		# 当前目标；先出队使请求恢复后自然推进下一名角色。
		var target_player_id: int = _pending_discard_one_target_ids.pop_front()
		# 当前可弃置候选；等待目标选择期间其他效果可能已清空其区域，空目标直接跳过。
		var candidates: Array[Dictionary] = _host.get_opportunity_discard_candidates(_pending_discard_one_owner_id, target_player_id)
		if candidates.is_empty():
			continue
		if _is_ai_controlled(_pending_discard_one_owner_id):
			# 外层恢复点；逐目标弃牌的嵌套结算完成后再继续剩余目标。
			var continuation_guard_id: int = _host.begin_opportunity_resolution_guard()
			_host.discard_selected_player_cards(target_player_id, [int(candidates[0].get("uid", -1))], _pending_discard_one_owner_id)
			if _host.has_nested_settlement_barrier():
				return
			_host.cancel_opportunity_resolution_guard(continuation_guard_id)
			continue
		# 机缘拥有者为当前目标选择一张牌；隐藏手牌继续只显示牌背。
		var context: Dictionary = {"kind":"opportunity_multi_discard_one", "opportunity_owner_id":_pending_discard_one_owner_id, "target_player_id":target_player_id, "allow_out_of_game_chooser":true}
		_host.request_card_choice(_pending_discard_one_owner_id, "选择弃置牌", "请选择该角色区域内的一张牌", candidates, 1, 1, false, context)
		return
	_pending_discard_one_owner_id = -1
	_system.complete_current_effect()


## 每次只处理一个目标；伤害子序列完成后统一调度器自然恢复本序列。
func _resolve_sequence_damage_target(sequence: RuleStepSequence) -> void:
	# 选择顺序；按原数组索引推进，暂停恢复不会再次伤害已完成目标。
	var target_ids: Array = sequence.context.get("target_ids", []) as Array
	var target_index: int = int(sequence.context.get("target_index", 0))
	if target_index >= target_ids.size():
		_system.complete_current_effect()
		return
	# 当前目标稳定ID；死亡或离场角色跳过后仍依照原选择顺序继续。
	var target_id: int = int(target_ids[target_index])
	sequence.context["target_index"] = target_index + 1
	sequence.insert_steps([Callable(self, "_resolve_sequence_damage_target")])
	# 目标当前状态；伤害结算前重新检查有效性。
	var target: PlayerState = _host.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game:
		return
	_host.damage(int(sequence.context.get("source_id", -1)), target_id, int(sequence.context.get("amount", 0)), "normal", "opportunity")


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
		_run_zone_operation(owner_player_id, target_player_id, operation, selected_uids)
		return
	# 区域选择标题；明确区分弃置与获得，正文数量与机缘规则一致。
	var title: String = "选择弃置牌" if operation == "discard_two" else "选择获得牌"
	# 区域选择提示；正式CardSelectionPanel会继续按手牌、装备与判定区分组显示。
	var prompt: String = "请选择目标区域内的两张牌" if operation == "discard_two" else "请选择目标区域内的一张牌"
	# 第二段恢复上下文；不保存候选副本，提交时由权威移动端口重新校验实体位置。
	var context: Dictionary = {"kind":"opportunity_zone_cards", "zone_operation":operation, "opportunity_owner_id":owner_player_id, "target_player_id":target_player_id, "allow_out_of_game_chooser":true}
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
		if effect_id == "discard_one_each_target" and _host.get_opportunity_discard_candidates(owner_player_id, player.player_id).is_empty():
			continue
		if effect_id == "gain_one_from_player" and _host.get_player_zone_candidates(owner_player_id, player.player_id).is_empty():
			continue
		if effect_id in ["discard_all_hand_target", "gain_all_hand_target"] and player.hand.is_empty():
			continue
		if effect_id == "discard_half_all_cards_target" and _host.get_discardable_count(player.player_id) <= 0:
			continue
		if effect_id == "swap_character_targets" and player.character_id.is_empty():
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
	if effect_id in ["swap_hand_targets", "swap_equipment_targets", "swap_character_targets"]:
		# 双角色交换优先让资源较少的友方与资源较多的敌方交换，避免只交换两名敌人而没有己方收益。
		var friendly_choice: int = -1
		var hostile_choice: int = -1
		var friendly_value: int = 2147483647
		var hostile_value: int = -2147483648
		for target_id: int in fallback_targets:
			# 友方资源值；手牌、装备或体力上限分别对应三种交换内容。
			var friendly_target: PlayerState = _state.get_player(target_id)
			var friendly_resource_value: int = friendly_target.hand.size() if effect_id == "swap_hand_targets" else (friendly_target.equipment.size() if effect_id == "swap_equipment_targets" else friendly_target.max_hp)
			if friendly_resource_value < friendly_value:
				friendly_value = friendly_resource_value
				friendly_choice = target_id
		for target_id: int in hostile_targets:
			# 敌方资源值；优先选择当前对应资源更多的目标。
			var hostile_target: PlayerState = _state.get_player(target_id)
			var hostile_resource_value: int = hostile_target.hand.size() if effect_id == "swap_hand_targets" else (hostile_target.equipment.size() if effect_id == "swap_equipment_targets" else hostile_target.max_hp)
			if hostile_resource_value > hostile_value:
				hostile_value = hostile_resource_value
				hostile_choice = target_id
		if friendly_choice >= 0 and hostile_choice >= 0:
			return [friendly_choice, hostile_choice]
	# 选择结果；至多三名效果只选敌方，没有敌人时允许选择0名以避免自损。
	var result: Array[int] = []
	for target_id: int in ordered_targets:
		if effect_id in ["link_targets", "damage_targets", "discard_one_each_target"] and not hostile_targets.has(target_id):
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


## 无后续选择的机缘效果也按内容步骤等待；摸牌/获得/回复结束后才授技与推进队列。
func _run_effect_with_completion(effect: Callable, after: Callable = Callable()) -> void:
	# 明确父子边界；完成调用不再通过全局“当前有没有选牌”猜测子操作是否结束。
	var steps: Array[Callable] = [
		func(_sequence: RuleStepSequence) -> void: effect.call(),
		func(_sequence: RuleStepSequence) -> void:
			if after.is_valid():
				after.call(),
		func(_sequence: RuleStepSequence) -> void: _system.complete_current_effect(),
	]
	_host.run_rule_sequence(steps)


## 机缘的单目标体力变化；实际数值在结算时读取，统一结果负责前置取消和角色代次。
func _change_target_health(effect_id: String, source_id: int, target_id: int, count: int) -> void:
	# 当前目标；目标已死亡或不存在时通用效果自然空完成。
	var target: PlayerState = _state.get_player(target_id)
	if target == null:
		return
	match effect_id:
		"max_hp_target":
			_host.change_max_hp(target_id, count, source_id, "opportunity")
		"lose_hp_target":
			_host.lose_hp(source_id, target_id, count, "opportunity")
		"lose_half_hp_target":
			# 目标结算时当前体力的一半并向上取整；正数体力使用整数公式(hp+1)/2。
			_host.lose_hp(source_id, target_id, ceili(float(maxi(target.hp, 0)) / 2.0), "opportunity")
		"reduce_half_max_hp_target":
			# 减少值按结算时体力上限的一半向上取整，最终仍由通用端口保证体力上限最低为1。
			_host.change_max_hp(target_id, -ceili(float(maxi(target.max_hp, 0)) / 2.0), source_id, "opportunity")
