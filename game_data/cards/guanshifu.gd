extends CardDefinition

## 【贯石斧】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "guanshi",
		"original_name": "贯石斧",
		"custom_name": "崩星重斧",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 3,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "你的【杀】被【闪】抵消时，可弃置两张牌令此【杀】依然生效。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":4.5, "equip_value":4.5},
		"ai_use_value": 4.0,
	})


## 执行【贯石斧】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 【杀】被【闪】抵消后，可弃置正好2张手牌或装备令其继续生效。
func on_slash_dodged(slash_effect: Object, context: Dictionary) -> bool:
	if not bool(context.get("dodged", false)):
		return false
	# 攻击者 ID；费用必须来自其手牌区或装备区。
	var actor_id: int = int(context.get("actor_id", -1))
	if slash_effect.host.get_hand_equipment_card_count(actor_id) < 2:
		return false
	# 当前装备实体；UID 用于防止等待期间换装后误发动。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return false
	# 贯石斧费用候选；可选择普通手牌或任意装备。
	var candidates: Array[Dictionary] = slash_effect.host.get_hand_equipment_candidates(actor_id, actor_id)
	# 费用恢复上下文；完整保存原【杀】参数和装备实体 UID。
	var cost_context: Dictionary = context.duplicate(true)
	cost_context["kind"] = "guanshi_cost"
	cost_context["equipment_definition_id"] = get_id()
	cost_context["equipment_uid"] = equipment_card.uid
	cost_context["ai_prefer_select"] = true
	# 两张费用牌；允许取消，但确认时必须正好选择2张。
	var selected_uids: Array[int] = slash_effect.host.request_card_choice(actor_id, "贯石斧", "是否弃置两张牌发动【贯石斧】？", candidates, 2, 2, true, cost_context)
	if slash_effect.host.has_pending_card_choice():
		return true
	_apply_cost(slash_effect, cost_context, selected_uids)
	return false


## 支付贯石斧费用并改写 dodged；等待期间换装或费用不足均视为发动失败。
func _apply_cost(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	# 攻击者 ID；用于复核当前装备和支付费用。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前武器实体；必须仍是创建请求时的同一张贯石斧。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		context["dodged"] = true
		return
	# 实际弃置数量；等待期间牌已移动时支付失败。
	var discarded_count: int = slash_effect.host.discard_selected_hand_equipment(actor_id, selected_uids)
	context["dodged"] = discarded_count != 2
	if discarded_count == 2:
		slash_effect.host.add_log("%s发动【贯石斧】，令【杀】继续生效。" % slash_effect.state.get_player(actor_id).display_name)


## 恢复贯石斧费用选择并继续处理最终【闪】结果。
func continue_slash_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "guanshi_cost":
		return false
	_apply_cost(slash_effect, context, selected_uids)
	slash_effect.continue_after_weapon_dodged(context)
	return true
