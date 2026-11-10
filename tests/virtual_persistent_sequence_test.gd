extends "res://tests/card_single_sequence_test.gd"

## 虚拟装备与延时牌的持久区域材料归属；验证实体守恒、逻辑牌名和离区回收。


## 判定测试只截获阶段最终出口，牌、判定与回收仍使用正式规则实现。
class PersistentController:
	extends MatchController

	## 已完整结束的判定阶段数量；阻止测试继续进入下一摸牌阶段。
	var phase_completions: int = 0

	func _continue_turn_after_judgment(_player_id: int) -> void:
		phase_completions += 1
		state.current_phase = "test"


## 批次接收者观察器；验证等待期间换将后不会调用旧武将的完成方法。
class BatchReceiver:
	extends SkillDefinition

	## 真实接收次数；换将后的旧接收者必须保持0次。
	var received: int = 0

	func receive(_count: int) -> void:
		received += 1


## 共用正常依赖工厂，仅替换判定阶段后继观察出口。
func _create_controller() -> MatchController:
	return PersistentController.new()


## 每类持久终点分别覆盖单材料与多材料，全部操作经正式用牌和获得入口。
func _run() -> void:
	for definition_id: String in ["bagua", "lebu"]:
		await _test_persistent_materials(definition_id, 1)
		await _test_persistent_materials(definition_id, 2)
	await _test_cancelled_persistent_install("bagua")
	await _test_cancelled_persistent_install("lebu")
	await _test_persistent_snapshot()
	await _test_virtual_equipment_loss()
	await _test_reused_equipment_materials()
	await _test_virtual_delayed_judgment()
	await _test_cardless_persistent_effect()
	await _test_cancelled_group_gain()
	await _test_group_response()
	await _test_nested_member_move()
	await _test_partial_group_cost()
	await _test_batch_receiver_generation()
	await _test_persistent_ai()
	await _test_persistent_minted_names()
	await _test_delayed_pass()
	await _test_group_transfer_and_death()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("VIRTUAL_PERSISTENT_SEQUENCE_PASS equipment judgment materials identity release")
	get_tree().quit(1 if _failed else 0)


## 持久效果持有原材料；取得该区域牌时释放原实体，不制造可进入手牌或牌堆的新代理。
func _test_persistent_materials(definition_id: String, material_count: int) -> void:
	_reset_controller()
	# 原材料身份；跨等待只按UID追踪，后续获得必须保持同一批实体。
	var material_uids: Array[int] = []
	# 原材料牌名；离开持久区域后恢复，不能把逻辑装备名永久写成实体牌名。
	var original_definitions: Dictionary = {}
	for material_index: int in range(material_count):
		# 原普通手牌；不同牌面便于验证逐个恢复而非复制第一份材料。
		var material: CardInstance = CardInstance.new("shan" if material_index == 0 else "tao", "heart" if material_index == 0 else "club", material_index + 4)
		material.zone = "hand"
		material.owner_id = 0
		_controller.state.get_player(0).hand.append(material)
		material_uids.append(material.uid)
		original_definitions[material.uid] = material.definition_id
	# 原持久区域目标；装备对本人，延时锦囊对另一名角色。
	var target_id: int = 0 if definition_id == "bagua" else 1
	_check(_controller.execute_virtual_card_use(0, definition_id, material_uids, [target_id], "", {"ignore_phase_limit":true}), "persistent use rejected " + definition_id)
	await _settle_single()
	_check(_controller.state.processing_area.is_empty(), "persistent use left processing materials " + definition_id)
	# 当前持久牌；逻辑规则仍按原虚拟牌执行，不按第一份材料的牌名执行。
	var persistent: CardInstance = _controller.state.get_player(target_id).get_armor() if definition_id == "bagua" else (_controller.state.get_player(target_id).judgment_area.back() as CardInstance if not _controller.state.get_player(target_id).judgment_area.is_empty() else null)
	_check(persistent != null and persistent.definition_id == definition_id, "persistent logical identity missing " + definition_id)
	if persistent == null:
		return
	# 正式取得区域牌的独立句柄；全部实体入手和其后置完成后才能读取。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(2, persistent.uid)
	await _settle_single()
	_check(result.completed and bool(result.result.get("success", false)), "persistent gain failed " + definition_id)
	_check(_controller.state.get_player(2).hand.size() == material_count and _controller.state.processing_area.is_empty(), "persistent release lost/created entities " + definition_id)
	for card_uid: int in material_uids:
		# 原材料入手后状态；每份UID都必须存在且恢复其自身牌面。
		var material: CardInstance = _controller.state.get_player(2).find_hand_card(card_uid)
		_check(material != null and material.definition_id == str(original_definitions[card_uid]), "persistent release changed material " + str(card_uid))
	_check(_controller.state.discard_pile.is_empty(), "persistent installation discarded owned materials " + definition_id)
	_check_clean("virtual persistent " + definition_id)


## 构造两份原手牌并正式安装；后续专项只从真实持久区域取回主实体。
func _install_persistent(definition_id: String, minted_materials: bool = false) -> CardInstance:
	_reset_controller()
	# 原材料UID；主材料和附属材料都保持各自实体身份。
	var material_uids: Array[int] = []
	for index: int in range(2):
		# 具有不同原牌面的实体，检测拆组后是否错误复制同一牌面。
		var card: CardInstance = CardInstance.new("shan" if index == 0 else "tao", "heart" if index == 0 else "club", index + 4)
		card.zone = "hand"
		card.owner_id = 0
		if minted_materials:
			card.custom_display_name = "持久材料%d" % index
			card.minted_skill_id = "test_mint"
		_controller.state.get_player(0).hand.append(card)
		material_uids.append(card.uid)
	# 原持久目标；装备归本人，延时牌归另一名角色。
	var target_id: int = 1 if definition_id == "lebu" else 0
	_check(_controller.execute_virtual_card_use(0, definition_id, material_uids, [target_id], "", {"ignore_phase_limit":true}), "persistent helper rejected")
	await _settle_single()
	# 真正安装的主实体；调用者必须在使用前判断本断言是否成立。
	var persistent: CardInstance = _controller.state.get_player(target_id).judgment_area.back() as CardInstance if definition_id in ["lebu", "shandian"] and not _controller.state.get_player(target_id).judgment_area.is_empty() else _controller.state.get_player(0).get_armor()
	_check(persistent != null and persistent.get_physical_card_uids() == material_uids, "persistent helper lost physical identities")
	return persistent


## 持久安装前置取消时不绑定或改原牌面；原生父牌只回收原实体，不生成新代理牌。
func _test_cancelled_persistent_install(definition_id: String) -> void:
	_reset_controller()
	# 原材料；单份也必须经相同安装边界。
	var material: CardInstance = _add_single_card()
	_controller.trigger_manager.subscribe("equipBefore" if definition_id == "bagua" else "addJudgeBefore", self, _pause_window)
	_check(_controller.execute_virtual_card_use(0, definition_id, [material.uid], [0 if definition_id == "bagua" else 1], "", {"ignore_phase_limit":true}), "cancel install request rejected")
	_check(_controller.has_pending_card_choice() and material.zone == "processing" and material.persistent_view_as.is_empty(), "persistent bound before window completed")
	if _paused_event != null:
		_paused_event.cancel("test_persistent_install_cancel")
	_submit_choice()
	await _settle_single()
	_check(material.zone == "discard_pile" and material.definition_id == "shan" and _controller.state.discard_pile == [material] and _controller.state.processing_area.is_empty(), "cancelled persistent install changed/created entity")
	_check(_controller.state.get_player(0).equipment.is_empty() and _controller.state.get_player(1).judgment_area.is_empty(), "cancelled persistent install left region state")
	_check_clean("persistent cancelled install")


## JSON存档往返保留全部原材料UID与原牌面；恢复后仍可按正常获得入口完整拆组。
func _test_persistent_snapshot() -> void:
	# 原双材料装备；恢复前记录原物理成员身份。
	var persistent: CardInstance = await _install_persistent("bagua")
	if persistent == null:
		return
	# 原物理UID副本；恢复不能分配新UID代替旧材料。
	var material_uids: Array[int] = persistent.get_physical_card_uids()
	# JSON后的纯字典；覆盖实际存档的数据形状，不能依赖内存对象共享。
	var data: Dictionary = JSON.parse_string(JSON.stringify(persistent.to_dict())) as Dictionary
	# 真实恢复实体；替换旧实例并按正常持续实例安装路径恢复。
	var restored: CardInstance = CardInstance.from_dict(data)
	_controller._uninstall_card_runtime(persistent.uid)
	_controller.state.get_player(0).equipment["armor"] = restored
	_controller._install_card_runtime(restored, 0)
	_check(restored.definition_id == "bagua" and restored.get_physical_card_uids() == material_uids, "persistent JSON lost material metadata")
	_controller.gain_card_to_hand_by_uid(2, restored.uid)
	await _settle_single()
	_check(_controller.state.get_player(2).hand.size() == 2 and _controller.state.get_player(2).find_hand_card(material_uids[0]).definition_id == "shan" and _controller.state.get_player(2).find_hand_card(material_uids[1]).definition_id == "tao", "persistent JSON release lost original faces")
	_check_clean("persistent snapshot")


## 多材料白银狮子离区仅回复一次，gainAfter等待回复，获得批次报告全部原实体。
func _test_virtual_equipment_loss() -> void:
	# 原白银狮子主实体；离区后将恢复第一份材料原名。
	var persistent: CardInstance = await _install_persistent("baiyin")
	if persistent == null:
		return
	_controller.state.get_player(0).hp = 18
	# 完整获得后的事实观察；回复与两份入手材料均应已经完成。
	var after_counts: Array[int] = []
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("gainAfter", self, func(_event: RuleEvent) -> void: after_counts.append(_controller.state.get_player(0).hp))
	# 整组取得结果；费用前置、离区回复和获得后置共用一个父子边界。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(2, persistent.uid)
	_check(_controller.has_pending_card_choice() and result.count == 0 and _controller.state.get_player(2).hand.size() == 2 and persistent.definition_id == "shan" and not _controller.card_runtime_instances.has(persistent.uid) and after_counts.is_empty(), "virtual equipment loss skipped recovery or lost group")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 2 and result.card_uids.size() == 2 and after_counts == [19], "virtual equipment recovered multiple times or lost physical count")
	_check_clean("persistent equipment loss")


## 持久装备再次作为虚拟用牌材料时，全部原实体都归新父牌消费与回收。
func _test_reused_equipment_materials() -> void:
	# 原双材料装备；新虚拟桃只选择此区域主实体。
	var persistent: CardInstance = await _install_persistent("bagua")
	if persistent == null:
		return
	# 原物理成员；新用牌最终回收必须覆盖附属成员。
	var material_uids: Array[int] = persistent.get_physical_card_uids()
	_controller.state.get_player(0).hp = 19
	_check(_controller.execute_virtual_card_use(0, "tao", [persistent.uid], [0], "", {"ignore_phase_limit":true}), "persistent material reuse rejected")
	await _settle_single()
	_check(_controller.state.get_player(0).hp == 20 and _controller.state.processing_area.is_empty() and _controller.state.discard_pile.size() == 2, "persistent material reuse leaked or repeated effect")
	for card_uid: int in material_uids:
		_check(str(_controller.get_card_location_snapshot(card_uid).get("zone", "")) == "discard_pile", "persistent reused member not reclaimed")
	_check_clean("persistent material reuse")


## 虚拟延时牌完整判定后恢复并回收原材料；判定处理区停留期间不丢失逻辑牌身份。
func _test_virtual_delayed_judgment() -> void:
	# 原双材料乐不思蜀；判定后应与判定牌一起回收。
	var persistent: CardInstance = await _install_persistent("lebu")
	if persistent == null:
		return
	# 原物理成员身份；判定结果不新增或替换这些材料。
	var material_uids: Array[int] = persistent.get_physical_card_uids()
	# 红桃判定牌；乐不思蜀不会跳过出牌阶段。
	var judgment: CardInstance = CardInstance.new("sha", "heart", 8)
	judgment.zone = "draw_pile"
	_controller.state.draw_pile.append(judgment)
	_controller.state.current_player_id = 1
	_controller.state.current_phase = "judgment"
	_controller.delayed_judgment_preview_seconds = 0.0
	_controller.delayed_judgment_result_pause_seconds = 0.0
	_controller._process_judgment_area(1)
	await _settle_single()
	_check((_controller as PersistentController).phase_completions == 1 and _controller.state.get_player(1).judgment_area.is_empty() and _controller.state.processing_area.is_empty() and _controller.state.discard_pile.size() == 3, "virtual delayed judgment did not complete/reclaim group")
	for card_uid: int in material_uids:
		_check(str(_controller.get_card_location_snapshot(card_uid).get("zone", "")) == "discard_pile", "virtual delayed judgment lost physical member")
	_check_clean("persistent delayed judgment")


## 无材料持久效果可以装入与移除，但离区不成为可获得的新实体牌。
func _test_cardless_persistent_effect() -> void:
	_reset_controller()
	_check(_controller.execute_cardless_virtual_card_use(0, "bagua", [0], "", {"ignore_phase_limit":true}), "cardless persistent use rejected")
	await _settle_single()
	# 无材料装备状态；逻辑存在并安装持续实例，不占用任何原实体材料。
	var persistent: CardInstance = _controller.state.get_player(0).get_armor()
	_check(persistent != null and persistent.get_physical_card_uids().is_empty(), "cardless persistent created physical card")
	if persistent == null:
		return
	# 尝试获得会移除该逻辑区域状态；没有实体牌可进入接收者手牌。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(2, persistent.uid)
	await _settle_single()
	_check(result.completed and result.count == 0 and _controller.state.get_player(2).hand.is_empty() and _controller.state.discard_pile.is_empty() and _controller.state.processing_area.is_empty() and _controller.state.get_player(0).equipment.is_empty() and not _controller.card_runtime_instances.has(persistent.uid), "cardless persistent leaked proxy into physical region")
	_check_clean("cardless persistent")


## 获得前置取消保留整组材料、逻辑装备和持续实例，不触发离区回复。
func _test_cancelled_group_gain() -> void:
	# 原复合白银狮子；取消时两份材料不能提前拆离。
	var persistent: CardInstance = await _install_persistent("baiyin")
	if persistent == null:
		return
	_controller.state.get_player(0).hp = 18
	_controller.trigger_manager.subscribe("gainBegin", self, _pause_window)
	# 原请求结果；取消必须明确完成失败。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(2, persistent.uid)
	_check(persistent.definition_id == "baiyin" and persistent.persistent_materials.size() == 1 and _controller.card_runtime_instances.has(persistent.uid), "group gain changed binding before commit")
	_paused_event.cancel("test_cancel_group_gain")
	_submit_choice()
	await _settle_single()
	_check(result.completed and not bool(result.result.get("success", false)) and persistent.definition_id == "baiyin" and persistent.persistent_materials.size() == 1 and _controller.state.get_player(0).hp == 18 and _controller.state.get_player(2).hand.is_empty(), "cancelled gain split binding or triggered loss")
	_check_clean("group gain cancellation")


## 真正转化响应消费复合装备；loseAfter等待时保留全部处理区材料，完成后一次回收。
func _test_group_response() -> void:
	# 原复合装备；安打可将任意自己的牌转化为火杀响应。
	var persistent: CardInstance = await _install_persistent("bagua")
	if persistent == null:
		return
	# 当前技能实例；所有响应合法性仍由生产技能协议验证。
	var skill: SkillDefinition = GameDatabase.create_skill("anda")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"anda":skill}
	skill.install()
	_controller.trigger_manager.subscribe("loseAfter", self, _pause_window)
	# 完整响应结果；不手工声明材料方案或直接移动实体。
	var result: RefCounted = _controller.begin_response_resolution(0, persistent.uid, ["sha"], [], "anda", {"response_action":"play"})
	_check(not result.completed and _controller.state.processing_area.size() == 2, "group response skipped material After")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.result != null and result.result.definition_id == "sha_fire" and _controller.state.processing_area.is_empty() and _controller.state.discard_pile.size() == 2 and _controller.state.get_player(0).response_history.size() == 1, "group response leaked material or repeated response")
	_check((_controller.state.get_player(0).response_history.back() as Dictionary).get("material_card_uids", []).size() == 2, "group response history omitted material")
	_check_clean("persistent response")


## 获得前置中转移附属成员时，外层原材料快照失效，不能据旧数量继续拆组。
func _test_nested_member_move() -> void:
	# 外层区域牌；原材料成员在窗口开启后仍可按真实位置核对。
	var persistent: CardInstance = await _install_persistent("bagua")
	if persistent == null:
		return
	# 将被嵌套取得的材料；不创建重复实体。
	var material: CardInstance = persistent.persistent_materials[0]
	_controller.trigger_manager.subscribe("gainBefore", self, func(event: RuleEvent) -> void:
		if int(event.target_id) == 2:
			_controller.begin_card_move(material.uid, "hand", 1, "test_nested_material_move")
	)
	# 外层请求已锁定原两材料；子获得完成后必须失败而非重复获得同一成员。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(2, persistent.uid)
	await _settle_single()
	_check(result.completed and not bool(result.result.get("success", false)) and _controller.state.get_player(1).hand.has(material) and persistent.persistent_materials.is_empty() and persistent.definition_id == "bagua" and _controller.state.get_player(2).hand.is_empty(), "nested member move reused stale physical snapshot")
	# 独立伪造父UID不能授权移动孤立材料；来源必须存在于主牌容器。
	var orphan: CardInstance = CardInstance.new("sha")
	orphan.zone = "persistent_material"
	orphan.material_parent_uid = persistent.uid
	_check(_controller.card_movement.move_card(orphan, "hand", 1) == null, "orphan material passed membership validation")
	_check_clean("nested persistent member")


## 第一份费用包含两实体但第二个选中条目取消时，物理数量不能伪装成付足两份选择。
func _test_partial_group_cost() -> void:
	# 第一份选中区域牌；它拥有两份真实材料。
	var persistent: CardInstance = await _install_persistent("bagua")
	if persistent == null:
		return
	# 第二份费用；仅对此实体的前置建立取消选择。
	var second: CardInstance = _add_single_card()
	_controller.trigger_manager.subscribe("discardBefore", self, func(event: RuleEvent) -> void:
		if (event.data.get("card_uids", []) as Array).has(second.uid):
			_pause_window(event)
	)
	# 实际费用结果；count与selected_count分别对应实体与选中条目。
	var result: RefCounted = _controller.begin_discard_cards(0, [persistent.uid, second.uid], ["hand", "equipment"], 0)
	_check(not result.completed and result.count == 2 and result.selected_count == 1, "group cost collapsed physical and selection counts")
	_paused_event.cancel("test_cancel_second_group_cost")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 2 and result.selected_count == 1 and second.zone == "hand", "partial group cost reported fully paid")
	_check_clean("persistent partial cost")


## 批次After中的换将使旧武将接收者失效，但已经完成的移牌事实仍保留。
func _test_batch_receiver_generation() -> void:
	_reset_controller()
	# 正式绑定的旧武将接收者；回调对象必须可查询原代次。
	var receiver: BatchReceiver = BatchReceiver.new()
	receiver.bind(_controller, 0)
	# 唯一实际费用；After换将不会回滚它。
	var card: CardInstance = _add_single_card()
	_controller.trigger_manager.subscribe("cardsDiscardedBatchAfter", self, _pause_window)
	# 等待中的批次；完成后结果仍为一张成功实体。
	var result: RefCounted = _controller.begin_discard_cards(0, [card.uid], ["hand"], 0, "test_generation", receiver.receive)
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 1 and receiver.received == 0 and card.zone == "discard_pile", "batch invoked old character receiver")
	_check_clean("batch receiver generation")


## AI只从快照恢复可取得的原材料，逻辑防具名不制造额外换装回复价值。
func _test_persistent_ai() -> void:
	# 两材料白银狮子；真实入手牌应为闪与桃。
	var persistent: CardInstance = await _install_persistent("baiyin")
	if persistent == null:
		return
	# 权威只读局面；评分不能改写实体或牌面。
	var snapshot: Dictionary = _controller.state.to_dict()
	# 通用估值器；不使用技能专用白名单。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 选择快照；自定义steal语义必须与常规顺手入口一致。
	var request: Dictionary = {"context":{"kind":"test_gain", "ai_choice_card_semantics":"steal_target"}, "candidates":[{"uid":persistent.uid, "owner_id":0, "zone":"equipment", "visible":true, "card_data":persistent.to_dict()}]}
	# 原材料应有牌质；与两张牌分别入手使用同一估值尺度。
	var expected: float = evaluator.get_card_value_by_id("shan", snapshot, 2) + evaluator.get_card_value_by_id("tao", snapshot, 2)
	_check(is_equal_approx(evaluator.get_choice_card_value(snapshot, request, persistent.uid, 2), expected), "AI valued logical equipment instead of acquired materials")
	_check(persistent.definition_id == "baiyin" and persistent.persistent_materials.size() == 1, "AI modified authoritative binding")
	_check_clean("persistent AI")


## 材料暂作其他逻辑牌时仍占用原造牌名，离区保留自定义名字和铸造来源。
func _test_persistent_minted_names() -> void:
	# 两张造牌材料；主实体逻辑名暂时被八卦覆盖。
	var persistent: CardInstance = await _install_persistent("bagua", true)
	if persistent == null:
		return
	_check(_controller.collect_minted_card_names().size() == 2 and not _controller.is_card_name_available("持久材料0") and not _controller.is_card_name_available("持久材料1"), "persistent binding released occupied minted name")
	_controller.gain_card_to_hand_by_uid(2, persistent.uid)
	await _settle_single()
	for material: CardInstance in _controller.state.get_player(2).hand:
		_check(material.minted_skill_id == "test_mint" and material.custom_display_name.begins_with("持久材料"), "persistent binding lost mint metadata")
	_check_clean("persistent minted names")


## 闪电未命中时整组转入下一人的判定区，逻辑身份与材料归属跨判定处理区保持一致。
func _test_delayed_pass() -> void:
	# 真正双材料闪电；本阶段判定不命中。
	var persistent: CardInstance = await _install_persistent("shandian")
	if persistent == null:
		return
	# 不命中的红桃判定牌；只回收判定牌，不回收闪电原材料。
	var judgment: CardInstance = CardInstance.new("sha", "heart", 8)
	judgment.zone = "draw_pile"
	_controller.state.draw_pile.append(judgment)
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "judgment"
	_controller.delayed_judgment_preview_seconds = 0.0
	_controller.delayed_judgment_result_pause_seconds = 0.0
	_controller._process_judgment_area(0)
	await _settle_single()
	_check((_controller as PersistentController).phase_completions == 1 and _controller.state.get_player(1).judgment_area.has(persistent) and persistent.definition_id == "shandian" and persistent.get_physical_card_uids().size() == 2 and persistent.persistent_materials[0].owner_id == 1 and _controller.state.processing_area.is_empty() and _controller.state.discard_pile == [judgment], "delayed pass split binding or lost owner")
	_check_clean("persistent delayed pass")


## 整组装备转移仍保留逻辑效果与成员归属；接收者死亡后只回收两份原实体。
func _test_group_transfer_and_death() -> void:
	# 原双材料装备；通过标准携带转移端口移动，不手工重装实例。
	var persistent: CardInstance = await _install_persistent("bagua")
	if persistent == null:
		return
	# 空附件列表；内部实体材料由绑定自身持有，与木牛粮协议独立。
	var attachments: Array[CardInstance] = []
	# 正式整组结果；保持原UID与目标持续实例。
	var result: RefCounted = _controller.transfer_equipment_with_attachments(0, 2, "armor", attachments, "wooden_ox")
	await _settle_single()
	_check(result.completed and result.success and _controller.state.get_player(2).get_armor() == persistent and persistent.persistent_materials[0].owner_id == 2 and _controller.card_runtime_instances.has(persistent.uid), "group transfer lost binding/runtime")
	_controller._resolve_death(2, 1)
	await _settle_single()
	_check(not _controller.state.get_player(2).alive and _controller.state.get_player(2).equipment.is_empty() and _controller.state.discard_pile.size() == 2 and _controller.state.processing_area.is_empty() and not _controller.card_runtime_instances.has(persistent.uid), "group death cleanup lost physical material")
	_check_clean("persistent transfer and death")
