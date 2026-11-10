extends "res://tests/virtual_persistent_sequence_test.gd"

## 秘密置牌维持隐私协议，同时完整卸载装备、等待离区子内容并延后游丝事实。


func _run() -> void:
	await _test_secret_group()
	await _test_secret_attachments()
	await _test_yousi_wait()
	await _test_budgeted_inactive_source()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("SECRET_PILE_SEQUENCE_PASS binding privacy equipment attachment skill_wait")
	get_tree().quit(1 if _failed else 0)


## 主材料保持指定第二位，其他成员在其下方；全部材料隐藏，离区回复完成前结果不完成。
func _test_secret_group() -> void:
	# 双材料白银狮子；离区前逻辑规则和原材料身份均由正式安装建立。
	var persistent: CardInstance = await _install_persistent("baiyin")
	if persistent == null:
		return
	_controller.state.get_player(0).hp = 18
	# 供第二位定位的原顶牌；其他材料不能反插到主材料上方。
	var top: CardInstance = CardInstance.new("sha", "spade", 2)
	top.zone = "draw_pile"
	_controller.state.draw_pile.append(top)
	# 公开失牌时机计数；秘密置牌本体不能产生这些窗口。
	var public_moves: Array[String] = []
	for timing: String in ["loseBefore", "loseBegin", "loseEnd", "loseAfter", "gainBefore", "gainAfter"]:
		_controller.trigger_manager.subscribe(timing, self, func(event: RuleEvent) -> void: public_moves.append(event.name))
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	# 完整私有移动结果；后续规则等待装备回复子内容。
	var result: CardMoveResolutionService = _controller.place_player_zone_card_on_draw_pile_top(0, persistent.uid, 2)
	_check(not result.completed and _controller.has_pending_card_choice() and persistent.zone == "draw_pile" and not _controller.card_runtime_instances.has(persistent.uid), "secret placement skipped equipment cleanup/recovery")
	_check(_controller.state.draw_pile.size() == 3 and _controller.state.draw_pile[1] == persistent and _controller.state.draw_pile.back() == top and public_moves.is_empty(), "secret group changed requested position or published lifecycle")
	for card: CardInstance in _controller.state.draw_pile:
		if card != top:
			_check(card.known_to.is_empty() and not card.shown, "secret group retained material knowledge")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 2 and _controller.state.get_player(0).hp == 19 and public_moves.is_empty(), "secret group result/recovery repeated")
	_check_clean("secret group")


## 木牛秘密离区仍由其源码清理粮；等待粮前置时原装备已入堆，后继不能提前执行。
func _test_secret_attachments() -> void:
	_reset_controller()
	# 真正木牛持续实例；离区钩子来自装备定义。
	var equipment: CardInstance = CardInstance.new("muniu", "diamond", 5)
	equipment.zone = "equipment"
	equipment.owner_id = 0
	_controller.state.get_player(0).equipment["treasure"] = equipment
	_controller._install_card_runtime(equipment, 0)
	# 原粮实体；正常子弃置公开，主装备的秘密位次仍不公开。
	var stored: CardInstance = CardInstance.new("shan", "club", 6)
	stored.zone = "wooden_ox"
	stored.owner_id = 0
	_controller.state.get_player(0).wooden_ox_storage.append(stored)
	_controller.trigger_manager.subscribe("discardBefore", self, _pause_window)
	# 等待原粮清理的独立结果。
	var result: CardMoveResolutionService = _controller.place_player_zone_card_on_draw_pile_top(0, equipment.uid, 1)
	_check(not result.completed and _controller.has_pending_card_choice() and equipment.zone == "draw_pile" and stored.zone == "wooden_ox" and not _controller.card_runtime_instances.has(equipment.uid), "secret attachment cleanup skipped child")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.count == 1 and stored.zone == "discard_pile" and _controller.state.get_player(0).wooden_ox_storage.is_empty(), "secret attachment cleanup did not finish once")
	_check_clean("secret attachment")


## 游丝等待实际装备离区子内容，之后再记录私有事实和一次发动。
func _test_yousi_wait() -> void:
	# 双材料防具；其离区回复用于建立真实异步子边界。
	var persistent: CardInstance = await _install_persistent("baiyin")
	if persistent == null:
		return
	_controller.state.get_player(0).hp = 18
	# 正式技能实例；不直接调用技能内部放置函数。
	var skill: SkillDefinition = GameDatabase.create_skill("yousi")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"yousi":skill}
	skill.install()
	_controller.trigger_manager.subscribe("recoverBefore", self, _pause_window)
	# 正式位次确认；选择上下文锁定原回合与原实体。
	var response: ChoiceResponse = ChoiceResponse.new(1, -1, 0, true)
	response.control_id = MatchController.PILE_SLOT_OPTION_TOP
	skill.continue_selection({"kind":"yousi_position", "card_uid":persistent.uid, "turn_player_id":1, "turn_number":1}, response)
	_check(_controller.has_pending_card_choice() and _controller.get_private_pile_placement(0).is_empty(), "yousi recorded placement before equipment child completed")
	_submit_choice()
	await _settle_single()
	_check(int(_controller.get_private_pile_placement(0).get(MatchController.PRIVATE_PLACEMENT_KEY_CARD_UID, -1)) == persistent.uid and _controller.state.get_player(0).hp == 19, "yousi lost completed private placement")
	_check(not _controller.state.get_player(0).to_dict(1, false).has("private_pile_placement"), "yousi exposed private fact")
	_check_clean("secret yousi wait")


## 无公开窗口也可能因预算让帧；提交前来源离场必须失败，不清理原牌知识或状态。
func _test_budgeted_inactive_source() -> void:
	_reset_controller()
	_controller.max_settlement_steps_per_pass = 1
	# 尚未移动的原手牌；低预算下同步返回不代表实体已提交。
	var card: CardInstance = _add_single_card()
	card.known_to.assign([0, 1])
	# 预算分帧的私有移动；调用期间还未进入牌堆。
	var result: CardMoveResolutionService = _controller.place_player_zone_card_on_draw_pile_top(0, card.uid, 1)
	_check(not result.completed and card.zone == "hand", "secret budget fixture already committed")
	_controller.state.get_player(0).out_of_game = true
	await _settle_single()
	_check(result.completed and result.count == 0 and card.zone == "hand" and card.known_to == [0, 1] and _controller.state.draw_pile.is_empty(), "secret budget moved inactive source or cleared knowledge")
	_check_clean("secret budget source")
