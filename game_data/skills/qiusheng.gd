extends SkillDefinition

## 【求生】技能源码。进入濒死时若有手牌且其中没有【桃】或【酒】，强制弃置全部手牌并将体力回复至1点。

## 求生最终体力值；固定1点，与技能原文和濒死脱离规则保持一致。
const RECOVERY_TARGET_HP: int = 1


## 写入锁定技静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"qiusheng",
		"name":"求生",
		"trigger":"dyingBegin",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，当你进入濒死状态时，若你有手牌，且手牌中没有【桃】或【酒】，你弃置所有手牌并将体力值回复至1点。",
	})


## 订阅持有者进入濒死的Begin时机；锁定技满足条件时不创建确认窗口。
func install() -> void:
	subscribe_timing("dyingBegin", _on_dying_begin, "player")


## 检查手牌条件并执行全部弃置；失牌触发完成后再精确回复至1点。
func _on_dying_begin(_event: RuleEvent) -> void:
	# 技能持有者；必须仍存活、在场且确实处于非正体力状态。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or owner.hp > 0 or owner.hand.is_empty() or _hand_contains_survival_card(owner):
		return
	announce_activation({"discard_count":owner.hand.size(), "target_hp":RECOVERY_TARGET_HP})
	host.call("discard_all_hand_cards", owner_player_id, owner_player_id, get_id())
	# 弃牌产生的失牌技能、装备或选择必须先完整结算，再执行技能原文中的回复步骤。
	if bool(host.call("has_nested_settlement_barrier")):
		defer_settlement({"kind":"qiusheng_recover"})
	else:
		_recover_to_one()


## 在弃牌产生的全部嵌套结算结束后恢复求生的回复步骤。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "qiusheng_recover":
		return false
	_recover_to_one()
	return true


## 将仍存活的技能持有者精确回复至1点；等待期间已经被其他效果救起时不会降低其体力。
func _recover_to_one() -> void:
	# 最新技能持有者状态；弃牌触发期间可能已经死亡、离场或被其他效果回复。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 实际回复量；体力已达到1点以上时为0，求生绝不反向降低体力。
	var recover_amount: int = maxi(RECOVERY_TARGET_HP - owner.hp, 0)
	if recover_amount > 0:
		host.recover(owner_player_id, owner_player_id, recover_amount, get_id())


## 判断当前普通手牌中是否存在可提供【桃】或【酒】响应的牌；临时视为牌同样读取当前逻辑定义。
func _hand_contains_survival_card(owner: PlayerState) -> bool:
	for hand_card: CardInstance in owner.hand:
		# 当前手牌定义；provided_response_pattern是救援协议的统一稳定字段。
		var definition: Dictionary = GameDatabase.get_card(hand_card.definition_id)
		if str(definition.get("provided_response_pattern", "")) in ["tao", "jiu"]:
			return true
	return false


## 修正预计致命来牌的AI估值；满足求生条件时用“存活至1血并失去全部手牌”替代普通击杀收益。
func modify_ai_incoming_card_effect(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, _definition: Dictionary, ai_profile: Dictionary, target_result: float, expected_damage_amount: int, current_score: float, evaluator: Object) -> float:
	if target_id != owner_player_id or not bool(ai_profile.get("damage", false)):
		return current_score
	# 玲可快照；权威AI视角应包含完整手牌，缺失牌面时保守维持普通估值而不臆测求生必定发动。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or int(target.get("hand_count", 0)) <= 0 or int(target.get("hp", 0)) + int(target.get("shield", 0)) > expected_damage_amount:
		return current_score
	# 已知完整手牌；数量与hand_count不一致表示观察者没有获得全部私有牌面，不能确认技能条件。
	var hand_cards: Array = target.get("hand", []) as Array
	if hand_cards.size() != int(target.get("hand_count", 0)):
		return current_score
	for card_variant: Variant in hand_cards:
		# 当前已知手牌；任一【桃】或【酒】都会阻止求生发动。
		var card: Dictionary = card_variant as Dictionary
		var card_definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		if str(card_definition.get("provided_response_pattern", "")) in ["tao", "jiu"]:
			return current_score
	# 非致死伤害基础收益；不再套用普通击杀倍率与身份死亡奖惩。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, actor_id, target_id)
	var direct_damage_score: float = target_result * attitude / NonameAIEvaluator.ATTITUDE_SCALE
	# 全部手牌弃置的资源变化；敌方失牌为正收益，友方失牌为负收益。
	var discarded_hand_score: float = evaluator.score_resource_change(authoritative_snapshot, actor_id, target_id, -hand_cards.size(), 0)
	return direct_damage_score + discarded_hand_score
