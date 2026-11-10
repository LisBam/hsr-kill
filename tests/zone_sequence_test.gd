extends "res://tests/virtual_persistent_sequence_test.gd"

## 区域变化的可插入边界；验证前置、整组牌前置、装备副作用、恢复与自身换形态后继。


func _run() -> void:
	for judgment: bool in [false, true]:
		await _test_zone_before(judgment, false)
		await _test_zone_before(judgment, true)
	await _test_group_card_cancel()
	await _test_zone_generation()
	await _test_equipment_loss_wait()
	await _test_region_after_cancel()
	await _test_restore_after()
	await _test_lunhui_wait()
	await _test_yongjie_wait()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("ZONE_SEQUENCE_PASS before cancellation group generation equipment recovery transform")
	get_tree().quit(1 if _failed else 0)


## 构造一件真正装备；持续实例按正常装备定义创建。
func _zone_equipment(definition_id: String, slot: String) -> CardInstance:
	# 原装备实体；所有实际离区仍通过正式移动服务。
	var card: CardInstance = CardInstance.new(definition_id, "club", 6)
	card.zone = "equipment"
	card.owner_id = 0
	_controller.state.get_player(0).equipment[slot] = card
	_controller._install_card_runtime(card, 0)
	return card


## 区域Before选择期间不得改变标志或移动实体，取消后不发布After。
func _test_zone_before(judgment: bool, cancel_change: bool) -> void:
	_reset_controller()
	# 本次原区域实体；判断取消时是否悬空。
	var card: CardInstance = CardInstance.new("lebu", "club", 6) if judgment else _zone_equipment("bagua", "armor")
	if judgment:
		card.zone = "judgment"
		card.owner_id = 0
		_controller.state.get_player(0).judgment_area.append(card)
	# 区域After次数；取消不应生成成功通知。
	var after: Array[int] = []
	_controller.trigger_manager.subscribe("disableJudgeBefore" if judgment else "disableEquipBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("disableJudgeAfter" if judgment else "disableEquipAfter", self, func(_event: RuleEvent) -> void: after.append(1))
	# 独立区域结果；不能把结果对象非空误判为已经改变。
	var result: RefCounted = _controller.set_player_judgment_area_abolished(0, true) if judgment else _controller.set_player_equipment_slots_abolished(0, ["armor"], true)
	_check(not result.completed and not result.success and card.zone == ("judgment" if judgment else "equipment") and not _controller.state.get_player(0).is_equipment_slot_abolished("armor") and not _controller.state.get_player(0).judgment_area_abolished, "zone committed before full Before")
	if cancel_change:
		_paused_event.cancel("test_zone_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.success != cancel_change and (card.zone == "discard_pile") != cancel_change and after.size() == (0 if cancel_change else 1), "zone cancellation/final result")
	_check_clean("zone Before")


## 第二件装备的移牌前置取消时，第一件也尚未移动，区域标志与实例保持原状。
func _test_group_card_cancel() -> void:
	_reset_controller()
	# 第一件原装备；其前置先通过，但不提前落入弃牌堆。
	var weapon: CardInstance = _zone_equipment("zhuge", "weapon")
	# 第二件原装备；取消只导致本区域请求明确失败，不依靠回滚。
	var armor: CardInstance = _zone_equipment("bagua", "armor")
	_controller.trigger_manager.subscribe("discardBegin", self, func(event: RuleEvent) -> void:
		if (event.data.get("card_uids", []) as Array).has(armor.uid):
			_pause_window(event)
	)
	# 全部装备区域请求；目标栏位和实体必须保持一致。
	var result: RefCounted = _controller.set_player_equipment_slots_abolished(0, ["weapon", "armor"], true)
	_check(not result.completed and weapon.zone == "equipment" and armor.zone == "equipment", "zone partially discarded during preflight")
	_paused_event.cancel("test_zone_second_card_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and not result.success and weapon.zone == "equipment" and armor.zone == "equipment" and _controller.state.get_player(0).get_abolished_equipment_slot_ids().is_empty() and _controller.card_runtime_instances.has(weapon.uid) and _controller.card_runtime_instances.has(armor.uid), "zone group cancellation lost state/runtime")
	_check_clean("zone member cancellation")


## Before等待期间换将只终止原请求，不修改同座位新角色的区域或牌。
func _test_zone_generation() -> void:
	_reset_controller()
	# 原装备；用于证明未发生实际离区。
	var card: CardInstance = _zone_equipment("bagua", "armor")
	_controller.trigger_manager.subscribe("disableEquipBefore", self, _pause_window)
	# 原代次区域请求；换将后明确失败。
	var result: RefCounted = _controller.set_player_equipment_slots_abolished(0, ["armor"], true)
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(result.completed and not result.success and card.zone == "equipment" and not _controller.state.get_player(0).is_equipment_slot_abolished("armor"), "zone changed replacement character")
	_check_clean("zone generation")


## 复合装备的离区回复先结束，再发布区域After，不能丢失第二份材料或重复回复。
func _test_equipment_loss_wait() -> void:
	# 双材料防具；原材料数与区域条目数不同。
	var card: CardInstance = await _install_persistent("baiyin")
	if card == null:
		return
	_controller.state.get_player(0).hp = 18
	# 区域After中的事实观察；应看到完整回复和原材料弃置。
	var after: Array[int] = []
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("disableEquipAfter", self, func(_event: RuleEvent) -> void: after.append(_controller.state.get_player(0).hp))
	# 真实废除结果；字段count表示一个栏位，不是两张实体。
	var result: RefCounted = _controller.set_player_equipment_slots_abolished(0, ["armor"], true)
	_check(not result.completed and result.success and after.is_empty() and card.zone == "discard_pile" and _controller.state.discard_pile.size() == 2 and not _controller.card_runtime_instances.has(card.uid), "zone After skipped equipment child")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 1 and after == [19] and (result.result.card_uids as Array).size() == 2, "zone equipment loss repeated/lost facts")
	_check_clean("zone equipment loss")


## 装备区After取消不撤销既成事实，也不能被下一判定区误读成它的Before取消。
func _test_region_after_cancel() -> void:
	_reset_controller()
	_controller.trigger_manager.subscribe("disableEquipAfter", self, _pause_window)
	# 连续两区域操作；后置不得污染下一项前置状态。
	var result: RefCounted = _controller.set_player_zones_abolished(0, true, true)
	_paused_event.cancel("test_zone_after_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.success and _controller.state.get_player(0).equipment_area_abolished and _controller.state.get_player(0).judgment_area_abolished, "zone After cancellation aborted next region")
	_check_clean("zone After cancellation")


## 区域恢复After中的选择也先结束，整次结果才完成，不重新生成旧牌。
func _test_restore_after() -> void:
	_reset_controller()
	_controller.set_player_zones_abolished(0, true, true)
	await _settle_single()
	_controller.trigger_manager.subscribe("enableEquipAfter", self, _pause_window)
	# 两区域恢复；第一个After等待期间不能提前恢复第二个区域。
	var result: RefCounted = _controller.set_player_zones_abolished(0, false, false)
	_check(not result.completed and not _controller.state.get_player(0).equipment_area_abolished and _controller.state.get_player(0).judgment_area_abolished, "zone restore skipped After boundary")
	_submit_choice()
	await _settle_single()
	_check(result.completed and not _controller.state.get_player(0).judgment_area_abolished and _controller.state.get_player(0).equipment.is_empty(), "zone restore returned cards or failed")
	_check_clean("zone restore")


## 轮回废除后置尚未结束时不换将或加入额外回合；自身换形后原内容继续回复与排队。
func _test_lunhui_wait() -> void:
	_reset_controller()
	_controller.player_mark_service = PlayerMarkService.new(_controller.state)
	_controller.state.get_player(0).character_id = "baie"
	_controller.state.get_player(0).max_hp = 4
	_controller.state.get_player(0).hp = 2
	# 正式觉醒实例；区域前置与后置走真实触发链。
	var skill: SkillDefinition = GameDatabase.create_skill("lunhui")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"lunhui":skill}
	skill.install()
	_controller.change_player_mark_count(0, "huozhong", 12)
	_controller.trigger_manager.subscribe("disableJudgeAfter", self, _pause_window)
	_controller.emit_rule_timing("phaseAfter", 1, 1, 1)
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(0).character_id == "baie" and _controller._extra_turn_queue.is_empty(), "lunhui transformed before zone After")
	_submit_choice()
	await _settle_single()
	_check(_controller.state.get_player(0).character_id == "kaesilanna" and _controller.state.get_player(0).hp == _controller.state.get_player(0).max_hp and _controller._extra_turn_queue.has(0), "lunhui lost post-transform continuation")
	_check_clean("lunhui zone wait")


## 永劫先等待回复，再等待恢复区域After；自身卸载后仍完成白厄与友方返场链。
func _test_yongjie_wait() -> void:
	_reset_controller()
	_controller.state.get_player(0).character_id = "kaesilanna"
	_controller.state.get_player(0).max_hp = 5
	_controller.state.get_player(0).hp = 0
	_controller.set_player_zones_abolished(0, true, true)
	await _settle_single()
	_controller.state.get_player(2).out_of_game = true
	# 正式返生实例；友方列表通过原持久状态保存。
	var skill: SkillDefinition = GameDatabase.create_skill("yongjie")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"yongjie":skill}
	skill.install()
	_controller.state.get_player(0).character_form_state["baie_removed_ally_ids"] = [2]
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("enableEquipAfter", self, _pause_window)
	_controller.emit_rule_timing("dyingBegin", 0, -1, 0)
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(0).hp == 0 and _controller.state.get_player(0).equipment_area_abolished, "yongjie restored before recovery")
	_submit_choice()
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(0).hp == 2 and _controller.state.get_player(0).character_id == "kaesilanna" and _controller.state.get_player(2).out_of_game, "yongjie skipped restore After")
	_submit_choice()
	await _settle_single()
	_check(_controller.state.get_player(0).character_id == "baie" and not _controller.state.get_player(0).judgment_area_abolished and not _controller.state.get_player(2).out_of_game and _controller.get_skill_instance(0, "lunhui") != null, "yongjie lost self-transform tail")
	_check_clean("yongjie zone wait")
