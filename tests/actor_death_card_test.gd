extends "res://tests/damage_sequence_test.gd"

## 牌效来源阵亡专项回归。覆盖两类规则：
## 1. 使用者在使用牌结算中途阵亡时，牌依然有效并继续结算，只是全部伤害改为“无来源”（来源ID为-1）；
## 2. 结算中必须由使用者本人选牌或指定后续的牌（【过河拆桥】【顺手牵羊】【火攻】【借刀杀人】）在使用者阵亡后整体失效。
## 每个用例重建权威对局，不依赖看门狗纠错。


## 依次执行全部用例；任一断言失败时以非零退出，全部通过才打印成功标记。
func _run() -> void:
	await _test_slash_keeps_response_window()
	await _test_slash_damage_without_source()
	await _test_slash_keeps_source_when_alive()
	_test_dependent_cards_declaration()
	await _test_dependent_card_invalidated()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("ACTOR_DEATH_CARD_PASS response_window no_source alive_source declaration invalidation")
	get_tree().quit(1 if _failed else 0)


## 使用者在【闪】询问创建前阵亡时，【杀】仍必须为目标保留完整响应窗口。
func _test_slash_keeps_response_window() -> void:
	_reset_controller()
	# 使用者阵亡时机；逐目标生命周期开始时制造死亡，模拟结算中途的来源死亡。
	_controller.trigger_manager.subscribe("shaBegin", self, func(_event: RuleEvent) -> void:
		_controller.state.get_player(0).alive = false
	)
	# 待使用的实体杀；目标无【闪】，普通响应放弃后命中一次。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	_check(_controller.has_pending_card_choice(), "slash skipped response window after actor death")
	_submit_choice()
	await _settle_card()
	_check(_controller.state.get_player(1).hp == 19, "slash lost damage after source death")
	_check_clean("slash response window")


## 使用者在【闪】响应等待期间阵亡时，命中伤害必须成为真正的无来源伤害，且不归属阵亡角色。
func _test_slash_damage_without_source() -> void:
	_reset_controller()
	# 待使用的实体杀；先建立【闪】询问再宣告使用者阵亡。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	_check(_controller.has_pending_card_choice(), "slash did not create response window")
	# 使用者阵亡事实；只改写存活标记，保持装备与手牌区域用于验证伤害归属而不是死亡清理。
	_controller.state.get_player(0).alive = false
	_submit_choice()
	await _settle_card()
	# 受伤目标；必须真实扣减1点体力并保留一条来源为空的伤害记录。
	var target: PlayerState = _controller.state.get_player(1)
	_check(target.hp == 19, "slash lost damage after actor death")
	_check(target.damage_history.size() == 1, "slash did not record exactly one damage fact")
	if target.damage_history.size() == 1:
		_check(int(target.damage_history[0].get("source_id", 0)) == -1, "slash damage source was not cleared to -1")
		_check(int(target.damage_history[0].get("amount", 0)) == 1, "slash damage amount changed")
	# 阵亡使用者；既不能累计造成伤害，也不能留下造成伤害的历史归属。
	var dead_actor: PlayerState = _controller.state.get_player(0)
	_check(dead_actor.total_damage_dealt == 0, "dead actor kept total damage credit")
	_check(dead_actor.damage_history.is_empty(), "dead actor kept damage history")
	_check_clean("slash without source")


## 使用者存活时【杀】伤害来源与统计保持原状，确认本次改动没有改变正常结算路径。
func _test_slash_keeps_source_when_alive() -> void:
	_reset_controller()
	# 待使用的实体杀；使用者全程存活，用于对照来源归属。
	var card: CardInstance = CardInstance.new("sha", "spade", 7)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	_submit_choice()
	await _settle_card()
	# 受伤目标；来源必须仍为0号使用者。
	var target: PlayerState = _controller.state.get_player(1)
	_check(target.hp == 19, "normal slash lost damage")
	_check(target.damage_history.size() == 1 and int(target.damage_history[0].get("source_id", -1)) == 0, "normal slash lost its source")
	_check(_controller.state.get_player(0).total_damage_dealt == 1, "living actor lost damage credit")
	_check_clean("slash with source")


## 四张依赖使用者的牌必须显式声明 requires_actor_choice，避免后续新增同族牌遗漏登记。
func _test_dependent_cards_declaration() -> void:
	# 需要使用者本人在结算中选牌或指定后续的牌；与本次规则清单严格一致。
	for card_id: String in ["guohe", "shunshou", "huogong", "jiedao"]:
		# 当前卡牌定义；必须存在且声明依赖使用者。
		var definition: CardDefinition = GameDatabase.get_card_definition(card_id)
		_check(definition != null and definition.requires_actor_choice(), card_id + " did not declare requires_actor_choice")
	# 普通牌必须保持不声明，确保它们仍按无来源继续结算。
	for card_id: String in ["sha", "nanman", "wanjian", "juedou"]:
		var definition: CardDefinition = GameDatabase.get_card_definition(card_id)
		_check(definition != null and not definition.requires_actor_choice(), card_id + " incorrectly requires actor choice")


## 使用者阵亡后【过河拆桥】必须整体失效：不创建选牌请求、不移动目标区域的牌，实体仍正常进弃牌堆。
func _test_dependent_card_invalidated() -> void:
	_reset_controller()
	# 目标手牌；失效后必须原样留在目标手牌区。
	var target_card: CardInstance = CardInstance.new("tao", "heart", 6)
	target_card.owner_id = 1
	target_card.zone = "hand"
	_controller.state.get_player(1).hand.append(target_card)
	# 使用者阵亡时机；逐目标生命周期开始时制造死亡。
	_controller.trigger_manager.subscribe("useCardToBegin", self, func(_event: RuleEvent) -> void:
		_controller.state.get_player(0).alive = false
	)
	# 待使用的过河拆桥；目标区域内存在可弃置的牌。
	var card: CardInstance = CardInstance.new("guohe", "club", 3)
	card.owner_id = 0
	card.zone = "hand"
	_controller.state.get_player(0).hand.append(card)
	_controller._execute_card_use(0, card, [1])
	_check(not _controller.has_pending_card_choice(), "invalidated card still created a choice request")
	await _settle_card()
	_check(_controller.state.get_player(1).hand.has(target_card), "invalidated card moved a card out of the target")
	_check(_controller.state.discard_pile.has(card), "invalidated card did not reach the discard pile")
	_check_clean("dependent invalidation")


## 只放弃合法响应并排空当前内容，不借助看门狗推进或直接移动实体牌。
func _settle_card() -> void:
	# 最大推进次数60；有限循环失败时保留原状态，不借助看门狗修补。
	for attempt: int in range(60):
		if _controller.has_pending_card_choice():
			_submit_choice()
		_controller._resume_settlement_pipeline()
		_controller.event_scheduler.drain()
		if _controller.state.processing_area.is_empty():
			return
		await get_tree().process_frame
	_check(false, "card settlement did not finish")
