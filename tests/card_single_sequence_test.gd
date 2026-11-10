extends "res://tests/damage_sequence_test.gd"

## 单牌获得的可暂停结果与调用方边界；只通过正式选择、规则步骤和原生用牌推进。

## 单牌最长观察帧；覆盖低预算让帧，超限即失败，不能用强制排空掩盖问题。
const MAX_SETTLE_OBSERVATION_FRAMES: int = 180

## 观察机缘效果的唯一完成通知；其他规则与移动仍使用正式组件。
class TransferProbe:
	extends OpportunitySystem

	## 收到的完整效果通知数；等待期间必须为0，结束后必须恰好为1。
	var completion_count: int = 0

	## 本测试只检查当前效果完成边界，不启动下一轮随机机缘。
	func complete_current_effect() -> void:
		completion_count += 1


## 每个前后窗口都单独等待；取消、角色代次与嵌套子内容不能越过完成结果。
func _run() -> void:
	# 当前窗口；前四项在提交之前，后五项在提交之后。
	for timing_name: String in ["loseBefore", "gainBefore", "loseBegin", "gainBegin", "loseEnd", "gainEnd", "loseAfter", "gainAfter", "cardsGainedBatchAfter"]:
		await _test_gain_window(timing_name, false)
	await _test_gain_window("gainBegin", true)
	await _test_changed_generation()
	await _test_native_child()
	await _test_budget_handler()
	await _test_receiver_death()
	await _test_equipment_loss(true)
	await _test_equipment_loss(false)
	await _test_gift_skill("yaoli", false)
	await _test_gift_skill("yaoli", true)
	await _test_gift_skill("qinniang", false)
	await _test_gift_skill("qinniang", true)
	await _test_hand_swap(false)
	await _test_hand_swap(true)
	await _test_mingchen_followup(false)
	await _test_mingchen_followup(true)
	await _test_sefu_followup()
	await _test_xingqi_cancelled_gain()
	await _test_turn_discard_filter()
	# 弃牌窗口；单张费用同样必须等待前置、逐张后置和整批后置。
	for timing_name: String in ["loseBefore", "discardBefore", "loseBegin", "discardBegin", "loseEnd", "discardEnd", "loseAfter", "discardAfter", "cardsDiscardEnd", "cardsDiscardAfter", "loseToDiscardpileAfter", "cardsDiscardedBatchAfter"]:
		await _test_discard_window(timing_name, false)
	await _test_discard_window("discardBegin", true)
	await _test_last_step_child()
	await _test_recast_window("loseBefore", true)
	await _test_recast_window("gainAfter", false)
	for timing_name: String in ["recastingLose", "recastingLost", "recast", "recastingGain", "recastingGained"]:
		await _test_recast_specific_window(timing_name, false)
	await _test_recast_specific_window("recastingLose", true)
	await _test_recast_specific_window("recastingGain", true)
	await _test_equipment_install("equipBefore", true)
	await _test_equipment_install("equipBefore", false)
	await _test_equipment_install("recoverBefore", false)
	await _test_equipment_install("equipAfter", false)
	await _test_equipment_transfer(true)
	await _test_equipment_transfer(false)
	await _test_delayed_placement(true)
	await _test_delayed_placement(false)
	await _test_harvest_gain(true)
	await _test_harvest_gain(false)
	await _test_fire_attack_cost(true)
	await _test_fire_attack_cost(false)
	_controller.free()
	if not _failed:
		print("CARD_SINGLE_SEQUENCE_PASS gain windows cancellation generation native budget")
	get_tree().quit(1 if _failed else 0)


## 前置选择期间仍在原手牌，后置选择期间已经移动但结果尚未完整完成。
func _test_gain_window(timing_name: String, cancel_move: bool) -> void:
	_reset_controller()
	# 本次唯一实体；前置取消不得留下区域数组之外的悬空牌。
	var card: CardInstance = _add_single_card()
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 独立完成句柄；与尚未完成、明确失败、实际成功三种状态区分。
	var result: Variant = _controller.gain_card_to_hand_by_uid(1, card.uid, "test_single_gain")
	_check(result is RefCounted, timing_name + " returned synchronous result")
	_check(_controller.has_pending_card_choice(), timing_name + " did not pause")
	_check(not _completed(result), timing_name + " reported complete before child choice")
	# 本次窗口是否发生在提交之前；Before与Begin必须读取未移动的实体。
	var before_commit: bool = timing_name.ends_with("Before") or timing_name.ends_with("Begin")
	_check(_controller.state.get_player(0).hand.has(card) == before_commit and _controller.state.get_player(1).hand.has(card) != before_commit, timing_name + " crossed commit boundary")
	if cancel_move and _paused_event != null:
		_paused_event.cancel("test_single_cancel")
	_submit_choice()
	await _settle_single()
	_check(_completed(result) and _success(result) != cancel_move, timing_name + " lost final result")
	_check(_controller.state.get_player(0).hand.has(card) == cancel_move and _controller.state.get_player(1).hand.has(card) != cancel_move, timing_name + " lost source or repeated movement")
	_check_clean("single " + timing_name)


## 等待期间换将必须让原请求失败；不能读取新武将区域完成旧请求。
func _test_changed_generation() -> void:
	_reset_controller()
	# 原来源手牌；代次变化后仍由原数组持有。
	var card: CardInstance = _add_single_card()
	_controller.trigger_manager.subscribe("gainBegin", self, _pause_window)
	# 原请求结果；失败也是明确完成，不能永久停在pending。
	var result: Variant = _controller.gain_card_to_hand_by_uid(1, card.uid)
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(_completed(result) and not _success(result) and _controller.state.get_player(0).hand.has(card), "single gain consumed changed generation")
	_check_clean("single generation")


## 获得After插入虚拟桃；剩余处理器和外层步骤都等完整子牌结束。
func _test_native_child() -> void:
	_reset_controller()
	_controller.state.get_player(2).hp = 19
	# 父操作实体；子回复不改变它的最终接收者。
	var card: CardInstance = _add_single_card()
	# 后续处理器和步骤的体力观察；两个都应为完整回复后的20。
	var observed: Array[int] = []
	_controller.trigger_manager.subscribe("gainAfter", self, func(_event: RuleEvent) -> void: _controller.execute_cardless_virtual_card_use(2, "tao", [2], "", {"ignore_phase_limit":true}), 10)
	_controller.trigger_manager.subscribe("gainAfter", self, func(_event: RuleEvent) -> void: observed.append(_controller.state.get_player(2).hp))
	_controller.trigger_manager.subscribe("useCardBefore", self, _pause_window)
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: sequence.effect_result = _controller.gain_card_to_hand_by_uid(1, card.uid),
		func(sequence: RuleStepSequence) -> void:
			_check(sequence.effect_result != null and sequence.effect_result.completed and int(sequence.effect_result.result.get("card_uid", -1)) == card.uid, "child effect overwrote parent result slot")
			observed.append(_controller.state.get_player(2).hp),
	])
	_check(_controller.has_pending_card_choice() and observed.is_empty(), "gain After skipped native child")
	_submit_choice()
	await _settle_single()
	_check(observed == [20, 20], "gain After lost native completion: " + str(observed))
	_check_clean("single native child")


## 没有选择的低预算子序列同样属于触发器内容，不能让外层下一处理器抢跑。
func _test_budget_handler() -> void:
	_reset_controller()
	_controller.max_settlement_steps_per_pass = 2
	# 预算让帧下仍需实际进入目标手牌的实体。
	var card: CardInstance = _add_single_card()
	# 外层剩余处理器的事实观察；不能读取尚未提交的区域。
	var observed: Array[bool] = []
	_controller.trigger_manager.subscribe("test_single_outer", self, func(_event: RuleEvent) -> void: _controller.gain_card_to_hand_by_uid(1, card.uid), 10)
	_controller.trigger_manager.subscribe("test_single_outer", self, func(_event: RuleEvent) -> void: observed.append(_controller.state.get_player(1).hand.has(card)))
	_controller.emit_rule_timing("test_single_outer", 0, 0, 1)
	await _settle_single()
	_check(observed == [true], "outer handler skipped budgeted movement: " + str(observed))
	_check_clean("single budget")


## 创建一张普通实体手牌；当前规则牌名不影响本组移牌窗口。
func _add_single_card() -> CardInstance:
	# 稳定牌实体；来源为0号角色普通手牌。
	var card: CardInstance = CardInstance.new("shan", "heart", 6)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	return card


## 只接受明确的完成句柄；不能把bool或候选实体当作结算完成。
func _completed(result: Variant) -> bool:
	return result is RefCounted and bool(result.get("completed"))


## 读取实际提交事实；失败结果和pending均不算成功。
func _success(result: Variant) -> bool:
	return _completed(result) and bool((result.get("result") as Dictionary).get("success", false))


## 有限帧观察正式出口；不清空队列、不代替系统释放令牌。
func _settle_single() -> void:
	# 本组最大观察帧；低预算最长移动应远少于此值。
	for attempt: int in range(MAX_SETTLE_OBSERVATION_FRAMES):
		_controller.resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller._rule_sequences.is_empty() and _controller._card_use_contexts.is_empty() and not _controller._rule_continuations.has_pending() and not _controller.trigger_manager.has_deferred_dispatches():
			return
		await get_tree().process_frame
	_check(false, "single movement did not settle")


## 接收者在前置窗口死亡，来源与私有牌面知识都保持原状。
func _test_receiver_death() -> void:
	_reset_controller()
	# 牌堆实体的旧知识；取消时不能提前改为接收者私有。
	var card: CardInstance = CardInstance.new("shan", "spade", 9)
	card.zone = "draw_pile"
	card.known_to.assign([0, 1, 2])
	_controller.state.draw_pile.append(card)
	_controller.trigger_manager.subscribe("gainBefore", self, _pause_window)
	# 原请求结果；死亡后为完成失败。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(1, card.uid)
	_check(card.known_to == [0, 1, 2], "single gain revealed or hid card before commit")
	_controller.state.get_player(1).alive = false
	_submit_choice()
	await _settle_single()
	_check(result.completed and not bool(result.result.get("success", false)) and _controller.state.draw_pile.has(card) and card.known_to == [0, 1, 2], "dead receiver changed source or knowledge")
	_check_clean("single dead receiver")


## 装备前置取消不卸载持续实例或回复；成功离区后先完成回复子内容，再发布获得After。
func _test_equipment_loss(cancel_move: bool) -> void:
	_reset_controller()
	_controller.state.get_player(0).hp = 18
	# 白银狮子实体；持续实例和离区回复都经正式卡牌源码执行。
	var card: CardInstance = CardInstance.new("baiyin", "club", 1)
	card.owner_id = 0
	card.zone = "equipment"
	_controller.state.get_player(0).equipment["armor"] = card
	_controller._install_card_runtime(card, 0)
	# 后置时机观察；回复等待期间不得开始gainAfter。
	var after_hp: Array[int] = []
	_controller.trigger_manager.subscribe("gainBegin", self, _pause_window)
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	_controller.trigger_manager.subscribe("gainAfter", self, func(_event: RuleEvent) -> void: after_hp.append(_controller.state.get_player(0).hp))
	# 独立获得结果；前置暂停时既未成功也未完成。
	var result: CardMoveResolutionService = _controller.gain_card_to_hand_by_uid(1, card.uid)
	_check(_controller.card_runtime_instances.has(card.uid) and _controller.state.get_player(0).hp == 18 and card.zone == "equipment", "equipment loss occurred before commit")
	if cancel_move:
		_paused_event.cancel("test_equipment_cancel")
	_submit_choice()
	if not cancel_move:
		_check(_controller.has_pending_card_choice() and _paused_event.name == "recoverBefore" and _controller.state.get_player(1).hand.has(card) and not _controller.card_runtime_instances.has(card.uid), "equipment side effect did not follow actual movement")
		_check(after_hp.is_empty() and not result.completed, "gain After skipped equipment child recovery")
		_submit_choice()
	await _settle_single()
	_check(result.completed and bool(result.result.get("success", false)) != cancel_move, "equipment result mismatch")
	_check(_controller.state.get_player(0).hp == (18 if cancel_move else 19) and _controller.card_runtime_instances.has(card.uid) == cancel_move, "equipment loss repeated or applied on cancellation")
	_check(after_hp.is_empty() if cancel_move else after_hp == [19], "equipment After read incomplete recovery")
	_check_clean("single equipment")


## 药理、亲酿只在实际交牌完整结束后消费次数；前置取消保留实体和原牌名。
func _test_gift_skill(skill_id: String, cancel_move: bool) -> void:
	_reset_controller()
	_controller.state.current_phase = "play"
	# 对应技能要求的颜色；药理为红色，亲酿为黑色。
	var card: CardInstance = _add_single_card()
	card.suit = "heart" if skill_id == "yaoli" else "spade"
	# 正式技能实例；步骤执行保留持有者与武将代次校验。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	_check(skill != null, "missing gift skill: " + skill_id)
	if skill == null:
		return
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {skill_id:skill}
	skill.install()
	_controller.trigger_manager.subscribe("gainBefore" if cancel_move else "gainAfter", self, _pause_window)
	_check(skill.activate({"card_uid":card.uid, "target_ids":[1]}).is_empty(), "gift skill request rejected")
	_check(_controller.has_pending_card_choice() and not bool(skill.get("_used_this_play_phase")), "gift skill consumed count before complete movement")
	if cancel_move:
		_paused_event.cancel("test_gift_cancel")
	_submit_choice()
	await _settle_single()
	_check(bool(skill.get("_used_this_play_phase")) != cancel_move and _controller.state.get_player(0).hand.has(card) == cancel_move, "gift skill count or source mismatch")
	_check(card.definition_id == ("shan" if cancel_move else ("tao" if skill_id == "yaoli" else "jiu")), "gift skill applied view-as at wrong boundary")
	_check_clean("single gift " + skill_id)


## 机缘交换先快照双方原牌；After完成前不交第二张，换将后不把原效果交入新武将手牌。
func _test_hand_swap(change_receiver_generation: bool) -> void:
	_reset_controller()
	# 第一方原牌；它的获得After制造一次真实选择。
	var first: CardInstance = _add_single_card()
	# 第二方原牌；必须先快照，不能把第一方刚收到的牌再交回。
	var second: CardInstance = CardInstance.new("sha", "club", 7)
	second.zone = "hand"
	second.owner_id = 1
	_controller.state.get_player(1).hand.append(second)
	# 机缘完成观察器；只替代下一轮随机调度，不替代当前效果实现。
	var system: TransferProbe = TransferProbe.new()
	# 正式机缘解析组件；通过实际交换入口建立步骤内容。
	var resolver: OpportunityEffectResolver = OpportunityEffectResolver.new()
	resolver.configure(system, _controller, _controller.state)
	_controller.trigger_manager.subscribe("gainAfter", self, func(event: RuleEvent) -> void:
		if (event.data.get("card_uids", []) as Array).has(first.uid):
			_pause_window(event)
	)
	resolver._begin_hand_swap(0, 1)
	_check(_controller.has_pending_card_choice() and system.completion_count == 0 and second.owner_id == 1 and first.owner_id == 1, "hand swap skipped first After")
	if change_receiver_generation:
		_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(system.completion_count == 1 and first.owner_id == 1 and second.owner_id == (1 if change_receiver_generation else 0), "hand swap lost snapshot, generation or completion boundary")
	_check_clean("single hand swap")
	system.free()


## 冥谶的获牌After完全结束才造成自伤；换将会终止原目标的伤害后续。
func _test_mingchen_followup(change_generation: bool) -> void:
	_reset_controller()
	# 指定的无中生有；牌堆检索不能绕过获得窗口。
	var card: CardInstance = CardInstance.new("wuzhong", "heart", 5)
	card.zone = "draw_pile"
	_controller.state.draw_pile.append(card)
	# 冥谶实例；真实选择恢复路径继续验证技能代次。
	var skill: SkillDefinition = _install_single_skill("mingchen")
	if skill == null:
		return
	# 已接受的合法目标选择；不伪造移牌或伤害结果。
	var response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	response.target_ids = [1]
	_controller.trigger_manager.subscribe("gainAfter", self, _pause_window)
	_check(skill.continue_selection({"kind":"mingchen_target"}, response), "mingchen selection rejected")
	_check(_controller.has_pending_card_choice() and _controller.state.get_player(1).hp == 20, "mingchen damaged before gain After")
	if change_generation:
		_controller.state.get_player(1).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(_controller.state.get_player(1).hp == (20 if change_generation else 19), "mingchen lost gain or generation boundary")
	_check_clean("single mingchen followup")


## 摄伏在获得After中的选择结束后才询问装备；装备费用由正式动作消费。
func _test_sefu_followup() -> void:
	_reset_controller()
	# 原名一字的杀；满足名字数检索，不依赖牌堆其他随机牌。
	var card: CardInstance = CardInstance.new("sha", "heart", 4)
	card.zone = "draw_pile"
	_controller.state.draw_pile.append(card)
	# 待弃装备；只有获牌完成后才进入该选择。
	var equipment: CardInstance = CardInstance.new("cixiong", "club", 7)
	equipment.zone = "equipment"
	equipment.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = equipment
	# 摄伏实例；采用真实选择恢复入口。
	var skill: SkillDefinition = _install_single_skill("shefu")
	if skill == null:
		return
	# 已接受的获牌目标；也是原伤害目标。
	var response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	response.target_ids = [1]
	_controller.trigger_manager.subscribe("gainAfter", self, _pause_window)
	skill.continue_selection({"kind":"sefu_gain_target", "damage_target_id":1, "name_length":1}, response)
	_check(str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "test_window" and equipment.zone == "equipment", "sefu equipment request overwrote gain child choice")
	_submit_choice()
	_check(str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "sefu_discard_equipment", "sefu did not resume equipment request")
	_submit_single_cards([equipment.uid])
	await _settle_single()
	_check(equipment.zone == "discard_pile" and _controller.state.get_player(1).hand.has(card), "sefu lost final movement")
	_check_clean("single sefu followup")


## 星祈获牌被取消时，原牌仍参与剩余排列；不丢失实体或提前覆盖获得前置选择。
func _test_xingqi_cancelled_gain() -> void:
	_reset_controller()
	# 被选择的锦囊；获得取消后仍留在牌堆，必须进入排列候选。
	var card: CardInstance = CardInstance.new("wuzhong", "heart", 5)
	card.zone = "draw_pile"
	# 另一张原观看牌；与取消的牌共同组成原观看范围。
	var other: CardInstance = CardInstance.new("shan", "spade", 9)
	other.zone = "draw_pile"
	_controller.state.draw_pile.assign([other, card])
	# 星祈实例；使用实际接收者恢复入口。
	var skill: SkillDefinition = _install_single_skill("xingqi")
	if skill == null:
		return
	# 原接收者选择；所选卡牌与观看UID由前一请求保存。
	var response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	response.target_ids = [1]
	_controller.trigger_manager.subscribe("gainBefore", self, _pause_window)
	skill.continue_selection({"kind":"xingqi_recipient", "selected_card_uid":card.uid, "viewed_card_uids":[card.uid, other.uid]}, response)
	_check(_controller.has_pending_card_choice() and _paused_event != null, "xingqi lost gain Before")
	if _paused_event != null:
		_paused_event.cancel("test_xingqi_gain_cancel")
	_submit_choice()
	_check(str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "xingqi_arrangement", "xingqi lost arrangement after failed gain")
	_submit_single_cards([card.uid, other.uid], "top_count_2")
	await _settle_single()
	_check(card.zone == "draw_pile" and other.zone == "draw_pile" and _controller.state.get_player(1).hand.is_empty(), "xingqi cancellation lost or gained viewed card")
	_check_clean("single xingqi followup")


## 为异步调用方专项安装一份真实技能，不改变其正文、数值或合法性规则。
func _install_single_skill(skill_id: String) -> SkillDefinition:
	# 正式独立技能实例；绑定到0号角色并登记唯一实例表。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	_check(skill != null, "missing single-move skill: " + skill_id)
	if skill == null:
		return null
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {skill_id:skill}
	skill.install()
	return skill


## 通过正式选择动作提交实体和排序控制；失败按真实校验结果报告。
func _submit_single_cards(card_uids: Array[int], control_id: String = "") -> void:
	# 当前权威选择；只提交其原请求ID与操作者。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	# 原请求对应动作；不直接触发技能回调或释放暂停。
	var action: PlayerAction = PlayerAction.new("choose_cards", int(request.get("chooser_id", 0)))
	action.payload = {"request_id":request.get("request_id", -1), "selected_card_uids":card_uids, "selected_target_ids":[], "confirmed":true, "selected_control_id":control_id}
	_check(_controller._submit_card_choice(action), "single card choice rejected: " + str(request.get("context", {})))
	_controller.resume_settlement_pipeline()


## 取得指定回合花色弃牌时，Before/Begin内修改花色会使原请求失败，不能只复核区域。
func _test_turn_discard_filter() -> void:
	_reset_controller()
	# 原红桃实体；使用唯一移动组件建立真实play阶段弃牌历史。
	var card: CardInstance = _add_single_card()
	_controller.state.current_phase = "play"
	_controller.state.turn_number = 1
	_controller.card_movement.move_card(card, "discard_pile", -1, "test_turn_play_discard")
	_controller.state.current_phase = "test"
	_controller.trigger_manager.subscribe("gainBegin", self, _pause_window)
	# 原花色条件对应的请求；区域未改变也不能忽略新的花色。
	var result: CardMoveResolutionService = _controller.gain_turn_play_discard_card(1, card.uid, 1, 0, "heart")
	_check(_controller.has_pending_card_choice(), "turn discard did not reach gain Begin")
	card.suit = "spade"
	_submit_choice()
	await _settle_single()
	_check(result.completed and not bool(result.result.get("success", false)) and _controller.state.discard_pile.has(card), "turn discard ignored changed filter before commit")
	_check_clean("single turn discard filter")


## 单张费用在前置选择期间留在原手牌；后置选择期间实体已提交但结果仍为pending。
func _test_discard_window(timing_name: String, cancel_move: bool) -> void:
	_reset_controller()
	# 原费用实体；取消时不能只保留zone字段而从手牌数组消失。
	var card: CardInstance = _add_single_card()
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 独立费用结果；bool无法表达After仍未完成的状态。
	var result: Variant = _controller.discard_card_from_hand(0, card.uid)
	_check(result is RefCounted, timing_name + " discard returned synchronous result")
	_check(_controller.has_pending_card_choice() and not _completed(result), timing_name + " discard skipped child wait")
	# 前置窗口必须没有真实离区，后置窗口必须已经进入弃牌堆。
	var before_commit: bool = timing_name.ends_with("Before") or timing_name.ends_with("Begin")
	_check(_controller.state.get_player(0).hand.has(card) == before_commit and _controller.state.discard_pile.has(card) != before_commit, timing_name + " discard lost source boundary")
	if cancel_move and _paused_event != null:
		_paused_event.cancel("test_discard_cancel")
	_submit_choice()
	await _settle_single()
	_check(_completed(result) and _success(result) != cancel_move, timing_name + " discard lost result")
	_check(_controller.state.get_player(0).hand.has(card) == cancel_move and _controller.state.discard_pile.has(card) != cancel_move, timing_name + " discard lost or repeated entity")
	_check_clean("single discard " + timing_name)


## 父内容最后一步创建的子序列仍由父身份持有；原窗口处理器不能在子选择完成前继续。
func _test_last_step_child() -> void:
	_reset_controller()
	# 单牌材料；父序列最后一步创建其弃牌内容。
	var card: CardInstance = _add_single_card()
	# 父身份与后继处理器观察；等待期间父ID必须仍有效。
	var parent_ids: Array[int] = []
	# 原窗口下一处理器观察；子结算后恰好执行一次。
	var observed: Array[bool] = []
	_controller.trigger_manager.subscribe("last_step_parent", self, func(_event: RuleEvent) -> void:
		parent_ids.append(_controller.run_rule_sequence([
			func(_sequence: RuleStepSequence) -> void: _pause_window(RuleEvent.new()),
			func(_sequence: RuleStepSequence) -> void: _controller.discard_card_from_hand(0, card.uid),
		])), 10)
	_controller.trigger_manager.subscribe("last_step_parent", self, func(_event: RuleEvent) -> void: observed.append(_controller.state.discard_pile.has(card)))
	_controller.trigger_manager.subscribe("discardBegin", self, _pause_window)
	_controller.emit_rule_timing("last_step_parent", 0, 0, 0)
	_check(_controller.has_pending_card_choice() and observed.is_empty(), "last step parent skipped initial choice")
	_submit_choice()
	_check(_controller.has_pending_card_choice() and parent_ids.size() == 1 and _controller._rule_sequences.has(parent_ids[0]) and observed.is_empty(), "last step released parent before child")
	_submit_choice()
	await _settle_single()
	_check(observed == [true], "last step child did not finish exactly once: " + str(observed))
	_check_clean("last step child")


## 重铸先等待实际移牌，再等量补摸；取消不补摸，补摸After选择不允许提前完成。
func _test_recast_window(timing_name: String, cancel_move: bool) -> void:
	_reset_controller()
	# 被重铸的原手牌；取消必须保留在原数组。
	var card: CardInstance = _add_single_card()
	# 固定补摸实体；UID可区分重铸材料与收益。
	var drawn: CardInstance = CardInstance.new("tao", "heart", 3)
	drawn.zone = "draw_pile"
	_controller.state.draw_pile.append(drawn)
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 本次完整重铸结果；不以对象存在作为费用成功。
	var result: RefCounted = _controller.recast_hand_card(0, card.uid)
	_check(_controller.has_pending_card_choice() and not result.completed, "recast did not await " + timing_name)
	if cancel_move and _paused_event != null:
		_paused_event.cancel("test_recast_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == (0 if cancel_move else 1), "recast final count " + timing_name)
	_check(_controller.state.get_player(0).hand.has(card) == cancel_move and _controller.state.get_player(0).hand.has(drawn) != cancel_move, "recast cost/draw mismatch " + timing_name)
	_check_clean("recast " + timing_name)


## 重铸专属窗口分别等待；两个前置取消只阻止其后尚未发生的动作，不回滚已付材料。
func _test_recast_specific_window(timing_name: String, cancel_window: bool) -> void:
	_reset_controller()
	# 唯一重铸材料；最早失牌前置结束前仍须留在手牌。
	var card: CardInstance = _add_single_card()
	# 固定补摸实体；窗口结束前不能被提前获得。
	var drawn: CardInstance = CardInstance.new("tao", "heart", 3)
	drawn.zone = "draw_pile"
	_controller.state.draw_pile.append(drawn)
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 完整操作结果；最后的专属窗口结束前也必须保持pending。
	var result: RefCounted = _controller.recast_hand_card(0, card.uid)
	_check(_controller.has_pending_card_choice() and not result.completed, "recast specific did not await " + timing_name)
	_check((card.zone == "hand") == (timing_name == "recastingLose"), "recast specific cost order " + timing_name)
	_check((drawn.zone == "hand") == (timing_name == "recastingGained"), "recast specific draw order " + timing_name)
	if cancel_window:
		_paused_event.cancel("test_recast_specific_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == (0 if cancel_window and timing_name == "recastingLose" else 1), "recast specific final count " + timing_name)
	_check((drawn.zone == "hand") != cancel_window, "recast specific cancelled pending action " + timing_name)
	_check_clean("recast specific " + timing_name)


## 换装先等待新牌前置，再等待旧装备离区回复，成功后安装持续实例并等待后置。
func _test_equipment_install(timing_name: String, cancel_move: bool) -> void:
	_reset_controller()
	_controller.state.get_player(0).hp = 18
	# 原白银狮子；取消新装备前置不得提前卸载或回复。
	var old_card: CardInstance = CardInstance.new("baiyin", "club", 1)
	old_card.zone = "equipment"
	old_card.owner_id = 0
	_controller.state.get_player(0).equipment["armor"] = old_card
	_controller._install_card_runtime(old_card, 0)
	# 待安装新护甲；本组直接观察处理区安装内容。
	var new_card: CardInstance = CardInstance.new("bagua", "spade", 2)
	new_card.zone = "processing"
	_controller.state.processing_area.append(new_card)
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 整组安装结果；新牌After和旧牌回复期间均未完成。
	var result: RefCounted = _controller.equip_from_processing(0, new_card)
	_check(_controller.has_pending_card_choice() and not result.completed, "equipment install did not await " + timing_name)
	if timing_name == "equipBefore":
		_check(_controller.state.get_player(0).get_armor() == old_card and _controller.card_runtime_instances.has(old_card.uid) and _controller.state.get_player(0).hp == 18, "equipment replaced before preflight")
	elif timing_name == "recoverBefore":
		_check(old_card.zone == "discard_pile" and new_card.zone == "processing", "new equipment skipped old loss recovery")
	else:
		_check(_controller.state.get_player(0).get_armor() == new_card and _controller.card_runtime_instances.has(new_card.uid), "equipment runtime missing in After")
	if cancel_move and _paused_event != null:
		_paused_event.cancel("test_equipment_install_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.success != cancel_move, "equipment final result " + timing_name)
	_check(_controller.state.get_player(0).get_armor() == (old_card if cancel_move else new_card), "equipment slot result " + timing_name)
	_check(_controller.state.get_player(0).hp == (18 if cancel_move else 19), "equipment loss recovery result " + timing_name)
	_check_clean("equipment install " + timing_name)


## 木牛及原粮全部前置通过后原子转移；任一粮取消均保留原装备、粮与持续实例。
func _test_equipment_transfer(cancel_attachment: bool) -> void:
	_reset_controller()
	# 原木牛；转移不会触发其离区清粮效果。
	var equipment: CardInstance = CardInstance.new("muniu", "diamond", 5)
	equipment.zone = "equipment"
	equipment.owner_id = 0
	_controller.state.get_player(0).equipment["treasure"] = equipment
	_controller._install_card_runtime(equipment, 0)
	# 随行粮；原数组由底层移动服务维护。
	var stored: CardInstance = CardInstance.new("shan", "club", 6)
	stored.zone = "wooden_ox"
	stored.owner_id = 0
	_controller.state.get_player(0).wooden_ox_storage.append(stored)
	_controller.trigger_manager.subscribe("loseBegin", self, _pause_window)
	_controller.trigger_manager.subscribe("equipEnd", self, _pause_window)
	# 原附件快照；整组请求返回后不能由调用者clear源数组。
	var attachments: Array[CardInstance] = [stored]
	# 完整组结果；不得只因主装备移动而提前成功。
	var result: RefCounted = _controller.transfer_equipment_with_attachments(0, 1, "treasure", attachments, "wooden_ox")
	_check(_controller.has_pending_card_choice() and not result.completed and equipment.owner_id == 0 and stored.owner_id == 0, "transfer skipped main preflight")
	_submit_choice()
	_check(_controller.has_pending_card_choice() and equipment.owner_id == 0 and stored.owner_id == 0, "transfer committed before attachment preflight")
	if cancel_attachment and _paused_event != null:
		_paused_event.cancel("test_attachment_cancel")
	_submit_choice()
	if not cancel_attachment:
		_check(_controller.has_pending_card_choice() and equipment.owner_id == 1 and stored.owner_id == 1 and _controller.state.get_player(0).wooden_ox_storage.is_empty() and not result.completed, "transfer After observed partial group")
		_submit_choice()
	await _settle_single()
	_check(result.completed and result.success != cancel_attachment, "transfer final group result")
	_check(equipment.owner_id == (0 if cancel_attachment else 1) and stored.owner_id == equipment.owner_id, "transfer orphaned attachment")
	_check(_controller.card_runtime_instances.has(equipment.uid), "transfer lost runtime")
	_check_clean("equipment transfer")


## 延时牌安装取消保留处理区实体；成功After先等待，再报告最终结果。
func _test_delayed_placement(cancel_move: bool) -> void:
	_reset_controller()
	# 原处理区延时牌；前置取消不能提前加入判定区。
	var card: CardInstance = CardInstance.new("lebu", "heart", 7)
	card.zone = "processing"
	_controller.state.processing_area.append(card)
	_controller.trigger_manager.subscribe("addJudgeBefore" if cancel_move else "addJudgeAfter", self, _pause_window)
	# 单张安装句柄；与父牌最终回收分开观察。
	var result: CardMoveResolutionService = _controller.place_delayed_trick(1, card)
	_check(_controller.has_pending_card_choice() and not result.completed, "delayed placement skipped window")
	if cancel_move and _paused_event != null:
		_paused_event.cancel("test_add_judge_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and bool(result.result.get("success", false)) != cancel_move, "delayed placement result")
	_check(_controller.state.get_player(1).judgment_area.has(card) != cancel_move and _controller.state.processing_area.has(card) == cancel_move, "delayed placement lost source")
	_check_clean("delayed placement")


## 五谷获得取消后仍保留原展示候选；获得After结束前不得进入下一名选择或结束父用牌。
func _test_harvest_gain(cancel_move: bool) -> void:
	_reset_controller()
	# 原五谷实体；经原生用牌树消费与回收，不直接调用卡牌定义模拟完成。
	var parent: CardInstance = CardInstance.new("wugu", "heart", 2)
	parent.zone = "hand"
	parent.owner_id = 0
	_controller.state.get_player(0).hand.append(parent)
	# 固定展示实体；两名目标最多各领取一张。
	var first_card: CardInstance = CardInstance.new("shan", "club", 4)
	first_card.zone = "draw_pile"
	_controller.state.draw_pile.append(first_card)
	# 第二张展示实体；数组末端为第一张亮出。
	var second_card: CardInstance = CardInstance.new("tao", "diamond", 6)
	second_card.zone = "draw_pile"
	_controller.state.draw_pile.append(second_card)
	_controller.trigger_manager.subscribe("gainBefore" if cancel_move else "gainAfter", self, _pause_window)
	_controller._execute_card_use(0, parent, [0, 1])
	_check(str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "harvest", "harvest initial choice missing")
	_submit_card_uid(second_card.uid)
	_check(_controller.has_pending_card_choice() and _paused_event != null and _paused_event.name == ("gainBefore" if cancel_move else "gainAfter") and _controller._card_use_contexts.has(parent.uid), "harvest skipped gain child")
	_check(second_card.zone == ("processing" if cancel_move else "hand"), "harvest crossed gain commit")
	if cancel_move and _paused_event != null:
		_paused_event.cancel("test_harvest_cancel")
	_submit_choice()
	# 下一名只在完整获得后询问；取消时原牌仍可被下一名领取。
	var request: Dictionary = _controller._pending_card_choice
	_check(str((request.get("context", {}) as Dictionary).get("kind", "")) == "harvest" and int(request.get("chooser_id", -1)) == 1, "harvest next target advanced incorrectly")
	_check((request.get("candidates", []) as Array).size() == (2 if cancel_move else 1), "harvest removed cancelled candidate")
	_controller.trigger_manager.unsubscribe_owner(self)
	_submit_card_uid(second_card.uid if cancel_move else first_card.uid)
	await _settle_single()
	_check(_controller.state.get_player(1).hand.has(second_card if cancel_move else first_card), "harvest next target lost card")
	_check(_controller.state.discard_pile.has(parent) and not _controller._card_use_contexts.has(parent.uid) and _controller.state.public_card_choice_display.is_empty(), "harvest parent did not complete")
	_check(_controller.state.processing_area.is_empty(), "harvest left original remainder in processing")
	_check_clean("harvest gain")


## 通过真实请求提交展示牌UID；不改选择状态或直接移动材料。
func _submit_card_uid(card_uid: int) -> void:
	# 当前原请求；保存稳定身份防止提交时新请求覆盖读取。
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	# 标准选择动作；沿用正式提交校验与规则序列结果路由。
	var action: PlayerAction = PlayerAction.new("choose_cards", int(request.get("chooser_id", -1)))
	action.payload = {"request_id":int(request.get("request_id", -1)), "selected_card_uids":[card_uid], "selected_target_ids":[], "confirmed":true}
	_check(_controller._submit_card_choice(action), "harvest choice rejected")
	_controller._resume_settlement_pipeline()


## 火攻的目标收尾等待费用After和伤害子内容；取消费用不伤害，父牌After只发生一次。
func _test_fire_attack_cost(cancel_cost: bool) -> void:
	_reset_controller()
	# 原火攻实体；使用声明后由原生父牌持有处理区身份。
	var parent: CardInstance = CardInstance.new("huogong", "spade", 1)
	parent.zone = "hand"
	parent.owner_id = 0
	_controller.state.get_player(0).hand.append(parent)
	# 原费用手牌；与目标展示牌同为红桃。
	var cost: CardInstance = _add_single_card()
	# 目标展示手牌；本次展示不移动该实体。
	var shown: CardInstance = CardInstance.new("shan", "heart", 7)
	shown.zone = "hand"
	shown.owner_id = 1
	_controller.state.get_player(1).hand.append(shown)
	# 原牌After计数；子选择期间为0，结束后为1。
	var completed_uses: Array[int] = []
	_controller.trigger_manager.subscribe("useCardAfter", self, func(_event: RuleEvent) -> void: completed_uses.append(parent.uid))
	# 仅费用暂停的订阅归属；完成费用选择后撤销，不能再次暂停父牌正常回收。
	var cost_pause_owner: RefCounted = RefCounted.new()
	_controller.trigger_manager.subscribe("discardBegin", cost_pause_owner, _pause_window)
	_controller.trigger_manager.subscribe("damageBegin3", self, _pause_window)
	_controller._execute_card_use(0, parent, [1])
	_check(_controller.has_pending_card_choice() and int(_controller._pending_card_choice.get("chooser_id", -1)) == 1, "fire attack show choice missing")
	_submit_card_uid(shown.uid)
	_check(_controller.has_pending_card_choice() and int(_controller._pending_card_choice.get("chooser_id", -1)) == 0, "fire attack cost choice missing")
	_submit_card_uid(cost.uid)
	_check(_controller.has_pending_card_choice() and _paused_event != null and _paused_event.name == "discardBegin" and cost.zone == "hand" and completed_uses.is_empty(), "fire attack skipped fee before")
	if cancel_cost and _paused_event != null:
		_paused_event.cancel("test_fire_attack_cost_cancel")
	_controller.trigger_manager.unsubscribe_owner(cost_pause_owner)
	_submit_choice()
	if not cancel_cost:
		_check(_controller.has_pending_card_choice() and _paused_event.name == "damageBegin3" and cost.zone == "discard_pile" and completed_uses.is_empty() and _controller.state.get_player(1).hp == 20, "fire attack finished target before damage child")
		_submit_choice()
	await _settle_single()
	_check(_controller.state.get_player(1).hp == (20 if cancel_cost else 19) and (cost.zone == "hand") == cancel_cost, "fire attack applied unpaid or repeated effect")
	_check(completed_uses == [parent.uid] and _controller.state.discard_pile.has(parent) and _controller.state.get_player(1).hand.has(shown), "fire attack parent or shown card result")
	_check_clean("fire attack cost")
