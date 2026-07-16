extends CardDefinition

## 【寒冰剑】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "hanbing",
		"original_name": "寒冰剑",
		"custom_name": "霜晶剑",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 2,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "【杀】将造成伤害时，若目标手牌区或装备区有牌，可防止伤害并依次弃置其至多两张牌。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai_use_value": 4.0,
	})


## 执行【寒冰剑】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 【杀】即将造成伤害时，可防止伤害并弃置目标手牌区或装备区至多2张牌。
func on_slash_before_damage(slash_effect: Object, context: Dictionary) -> bool:
	# 攻击者 ID；负责选择目标区域牌。
	var actor_id: int = int(context.get("actor_id", -1))
	# 目标 ID；其手牌区和装备区必须至少有1张牌。
	var target_id: int = int(context.get("target_id", -1))
	if slash_effect.host.get_hand_equipment_card_count(target_id) < 1:
		return false
	# 当前武器实体；UID 用于等待期间验证仍装备同一张寒冰剑。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return false
	# 目标区域候选；只包含普通手牌与装备，不包含判定区。
	var candidates: Array[Dictionary] = slash_effect.host.get_hand_equipment_candidates(actor_id, target_id)
	# 选牌恢复上下文；保存原【杀】全部伤害参数与武器实体 UID。
	var choice_context: Dictionary = context.duplicate(true)
	choice_context["kind"] = "hanbing_cards"
	choice_context["equipment_definition_id"] = get_id()
	choice_context["equipment_uid"] = equipment_card.uid
	# 目标当前状态；基础 AI 在目标体力大于1时倾向发动替代伤害。
	var target: PlayerState = slash_effect.state.get_player(target_id)
	choice_context["ai_prefer_select"] = target != null and target.hp > 1
	# 弃牌选择；允许取消，选择1至2张才防止伤害。
	var selected_uids: Array[int] = slash_effect.host.request_card_choice(actor_id, "寒冰剑", "是否发动【寒冰剑】并弃置目标至多两张牌？", candidates, 0, mini(2, candidates.size()), true, choice_context)
	if slash_effect.host.has_pending_card_choice():
		return true
	return _apply_choice(slash_effect, choice_context, selected_uids)


## 应用寒冰剑选择；成功弃置至少1张时返回 true 表示伤害已被防止。
func _apply_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	# 攻击者 ID；用于复核当前武器实体和记录日志。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前武器实体；换装后旧选择自动失效并正常造成伤害。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return false
	# 实际弃置数量；至少成功弃置1张才防止伤害。
	var discarded_count: int = slash_effect.host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count <= 0:
		return false
	slash_effect.host.add_log("%s发动【寒冰剑】防止伤害并弃置目标至多两张牌。" % slash_effect.state.get_player(actor_id).display_name)
	return true


## 恢复寒冰剑选牌；发动失败时回到通用【杀】伤害步骤。
func continue_slash_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "hanbing_cards":
		return false
	if not _apply_choice(slash_effect, context, selected_uids):
		slash_effect.continue_slash_damage(context)
	return true
