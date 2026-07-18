extends CardDefinition

## 【麒麟弓】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "qilin",
		"original_name": "麒麟弓",
		"custom_name": "逐星弓",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 5,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "【杀】造成伤害时，可弃置目标装备区的一张坐骑牌。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":3.0, "equip_value":3.0},
		"ai_use_value": 4.0,
	})


## 执行【麒麟弓】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 【杀】造成伤害且目标仍存活后，可选择弃置目标装备区的一张坐骑牌。
func on_slash_damage_finished(slash_effect: Object, context: Dictionary) -> bool:
	# 攻击者 ID；负责选择并弃置目标坐骑。
	var actor_id: int = int(context.get("actor_id", -1))
	# 目标 ID；其进攻或防御坐骑构成本次候选。
	var target_id: int = int(context.get("target_id", -1))
	# 当前武器实体；等待期间必须保持同一张麒麟弓。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return false
	# 麒麟弓允许选择的标准坐骑槽；强类型数组与控制器公开查询签名保持一致，避免未定型字面量触发运行时参数错误。
	var mount_slots: Array[String] = ["offensive_mount", "defensive_mount"]
	# 可弃置坐骑候选；槽位列表由麒麟弓源码声明，通用控制器只负责序列化公开装备。
	var candidates: Array[Dictionary] = slash_effect.host.get_equipment_candidates(actor_id, target_id, mount_slots)
	if candidates.is_empty():
		return false
	# 坐骑选择上下文；装备定义 ID 与 UID 用于异步恢复和换装复核。
	var choice_context: Dictionary = context.duplicate(true)
	choice_context["kind"] = "qilin_mount"
	choice_context["equipment_definition_id"] = get_id()
	choice_context["equipment_uid"] = equipment_card.uid
	choice_context["ai_prefer_select"] = true
	# 坐骑选择；允许取消且至多选择1张。
	var selected_uids: Array[int] = slash_effect.host.request_card_choice(actor_id, "麒麟弓", "是否发动【麒麟弓】弃置目标一张坐骑？", candidates, 0, 1, true, choice_context)
	if slash_effect.host.has_pending_card_choice():
		return true
	_apply_choice(slash_effect, choice_context, selected_uids)
	return false


## 应用麒麟弓坐骑选择；只弃置明确选择且仍位于目标装备区的实体牌。
func _apply_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	if selected_uids.is_empty():
		return
	# 攻击者 ID；用于复核当前麒麟弓实体。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前武器实体；已经换装时旧选择自动失效。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return
	# 实际弃置数量；候选只允许目标进攻或防御坐骑。
	var discarded_count: int = slash_effect.host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count == 1:
		slash_effect.host.add_log("%s发动【麒麟弓】弃置目标一张坐骑。" % slash_effect.state.get_player(actor_id).display_name)


## 恢复麒麟弓坐骑选择；伤害已经结算完成，无需再次推进伤害流程。
func continue_slash_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "qilin_mount":
		return false
	_apply_choice(slash_effect, context, selected_uids)
	return true
