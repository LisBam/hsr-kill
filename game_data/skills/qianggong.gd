extends SkillDefinition

## 【强攻】技能源码。使用【杀】指定目标时可弃置一张牌，并按颜色或武器牌强化该目标的响应与伤害。

## 红色费用赋予的身份行为目标结果；强化对敌目标的进攻，不改变实际弃牌或伤害数值。
const IDENTITY_TARGET_RESULT: float = -0.8


## 写入触发技能静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"qianggong",
		"name":"强攻",
		"trigger":"useCardToTargeted",
		"ui_enabled":false,
		"description":"当你使用【杀】指定目标时，你可以弃置一张牌，若此牌为红色，此【杀】不可被【闪】响应；若此牌为黑色，此【杀】伤害+1；若此牌为武器牌，则以上两项均执行。",
	})


## 订阅持有者使用牌的最终指定目标时机；多目标【杀】会对每名目标分别询问并独立强化。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_owner_slash_targeted, "source")


## 仅为【杀】目标创建可取消的一牌费用请求；手牌与装备区均属于可弃置的“一张牌”。
func _on_owner_slash_targeted(event: RuleEvent) -> void:
	var definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(definition.get("effect_id", "")) != "slash":
		return
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	request_card_selection("强攻", "你可以弃置一张牌强化此【杀】", candidates, 0, 1, true, {"kind":"qianggong_cost", "card_uid":int(event.data.get("card_uid", -1)), "target_id":int(event.data.get("target_id", event.target_id))})


## 恢复费用选择并在移动前读取颜色与装备子类型；武器牌无论自身颜色都同时执行两项强化。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "qianggong_cost" or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != 1:
		return true
	var owner: PlayerState = get_owner_skill_player().get_state()
	var cost_card: CardInstance = _find_owned_card(owner, response.card_ids[0])
	if cost_card == null:
		return true
	var cost_definition: Dictionary = GameDatabase.get_card(cost_card.definition_id)
	var is_weapon: bool = str(cost_definition.get("type", "")) == "equipment" and str(cost_definition.get("subtype", "")) == "weapon"
	var cost_color: String = cost_card.get_color()
	if int(host.call("discard_selected_hand_equipment", owner_player_id, response.card_ids)) != 1:
		return true
	var parent_card_uid: int = int(context.get("card_uid", -1))
	var target_id: int = int(context.get("target_id", -1))
	if is_weapon or cost_color == "red":
		host.call("add_card_direct_hit_target", parent_card_uid, target_id, get_id())
	if is_weapon or cost_color == "black":
		host.call("add_card_target_damage_bonus", parent_card_uid, target_id, 1, get_id())
	announce_activation({"card_uid":parent_card_uid, "target_id":target_id, "cost_card_uid":cost_card.uid, "direct_hit":is_weapon or cost_color == "red", "damage_bonus":1 if is_weapon or cost_color == "black" else 0})
	observe_identity_behavior([target_id], {"target_result":IDENTITY_TARGET_RESULT, "damage":is_weapon or cost_color == "black", "respond_shan":not (is_weapon or cost_color == "red")})
	return true


## 在普通手牌和装备区中按UID查找费用牌；木牛“粮”不属于原文可直接弃置的区域牌。
func _find_owned_card(owner: PlayerState, card_uid: int) -> CardInstance:
	if owner == null:
		return null
	var hand_card: CardInstance = owner.find_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for equipment_variant: Variant in owner.equipment.values():
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card != null and equipment_card.uid == card_uid:
			return equipment_card
	return null


## 评估是否支付强攻费用；敌对目标的直击与增伤收益扣除实际费用牌保留价值。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "qianggong_cost":
		return 0.0
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != 1:
		return 0.0
	var target_id: int = int(context.get("target_id", -1))
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude >= 0.0:
		return -20.0
	var cost_card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, int(selected_cards[0]))
	var cost_definition: Dictionary = GameDatabase.get_card(str(cost_card.get("definition_id", "")))
	var is_weapon: bool = str(cost_definition.get("type", "")) == "equipment" and str(cost_definition.get("subtype", "")) == "weapon"
	var color: String = str(cost_card.get("color", ""))
	var benefit: float = 3.0 if is_weapon else (1.8 if color == "black" else 1.2)
	return benefit - evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
