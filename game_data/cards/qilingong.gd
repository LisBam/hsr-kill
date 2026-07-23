extends CardDefinition

## 【麒麟弓】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "qilin",
		"original_name": "麒麟弓",
		"custom_name": "曲弓",
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


## 安装麒麟弓的标准造成伤害时触发；来源角色必须仍装备同一实体才能创建坐骑选择。
## 当前时机说明：订阅【杀】专属shaDamage，发生在通用伤害与实际扣减之前。
func install_runtime() -> void:
	if runtime_host != null and runtime_host.get("trigger_manager") != null:
		runtime_host.trigger_manager.subscribe("shaDamage", self, _on_owner_damage, 0, runtime_owner_player_id, "source")


## 在【杀】造成正数伤害的damage时机请求弃置目标坐骑；该时机早于damageSource、濒死尾部与damageAfter。
## 当前时机说明：回调已经前移到shaDamage，选择建立与完成时目标都尚未承受本次伤害。
func _on_owner_damage(event: RuleEvent) -> void:
	if int(event.data.get("damage_amount", 0)) <= 0 or event.target_id < 0:
		return
	# 造成伤害的牌定义；只有共享slash牌族满足麒麟弓条件。
	# 当前来源说明：shaDamage只由共享【杀】组件派发，因此无需再次读取card_id做重复牌族判断。
	# 当前武器实体；换装或失去麒麟弓后旧运行时实例不能继续触发。
	var equipment_card: CardInstance = runtime_host.get_equipment_card(runtime_owner_player_id, "weapon")
	if equipment_card == null or equipment_card.uid != runtime_card_uid:
		return
	# 麒麟弓允许选择的标准坐骑槽；目标即使即将进入濒死也在当前伤害时机按公开装备区取候选。
	var mount_slots: Array[String] = ["offensive_mount", "defensive_mount"]
	# 可弃置坐骑候选；为空时不创建没有收益的询问。
	var candidates: Array[Dictionary] = runtime_host.get_equipment_candidates(runtime_owner_player_id, event.target_id, mount_slots)
	if candidates.is_empty():
		return
	# 伤害时机选择上下文；父牌UID用于异步选择完成后恢复当前【杀】目标。
	var choice_context: Dictionary = event.data.duplicate(true)
	# 前一轮【闪】响应模式；damage继承的来源上下文不能让本次坐骑选择被误判为响应牌恢复。
	# 当前来源说明：shaDamage沿用同一【杀】上下文，仍需移除上一轮响应字段。
	choice_context.erase("response_patterns")
	# 前一轮响应者字段；麒麟弓选择者固定为伤害来源，不沿用受伤目标的响应身份。
	choice_context.erase("responder_id")
	# 前一轮响应完成标记；父【杀】目标只能在麒麟弓选择应用后由本装备显式完成。
	choice_context.erase("complete_parent_target_after_response")
	choice_context["kind"] = "qilin_damage"
	choice_context["actor_id"] = runtime_owner_player_id
	choice_context["target_id"] = event.target_id
	choice_context["equipment_definition_id"] = get_id()
	choice_context["equipment_uid"] = equipment_card.uid
	choice_context["ai_prefer_select"] = true
	# 坐骑选择；允许取消且至多选择一张，正式对局会暂停同一damage时机的后续触发器。
	# 当前时机说明：这里暂停的是shaDamage触发续列，选择结束后才继续实际伤害。
	var selected_uids: Array[int] = runtime_host.request_card_choice(runtime_owner_player_id, "麒麟弓", "是否发动【麒麟弓】弃置目标一张坐骑？", candidates, 0, 1, true, choice_context)
	if runtime_host.has_pending_card_choice():
		return
	_apply_runtime_choice(runtime_host, choice_context, selected_uids)


## 应用damage时机中的麒麟弓选择；等待期间换装或坐骑离区时安全失效。
## 当前时机说明：该兼容函数名与原注释保留，但正式调用来源为扣减前shaDamage。
func _apply_runtime_choice(match_host: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	if selected_uids.is_empty():
		return
	# 当前麒麟弓实体；必须与创建请求时的装备UID一致。
	var equipment_card: CardInstance = match_host.get_equipment_card(int(context.get("actor_id", -1)), "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return
	# 实际弃置数量；候选只允许目标进攻或防御坐骑。
	var discarded_count: int = match_host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count == 1:
		match_host.add_log("%s发动【麒麟弓】弃置目标一张坐骑。" % match_host.state.get_player(int(context.get("actor_id", -1))).display_name)


## 声明麒麟弓使用标准damage时机；共享【杀】流程不再重复调用伤害完成后兼容钩子。
## 当前时机说明：标准实现使用shaDamage前置触发，仍返回true以禁用旧伤害后钩子。
func uses_damage_timing_trigger() -> bool:
	return true


## 恢复damage时机创建的麒麟弓坐骑选择，并继续父【杀】当前目标。
## 父【杀】当前目标由统一伤害续接管线在damageSource、damageEnd与damageAfter结束后推进，本装备只应用自己的坐骑弃置结果。
## 当前恢复说明：选择现在产生于shaDamage，触发管理器恢复同一前置时机后由【杀】组件进入实际伤害；本函数不直接推进伤害。
func continue_equipment_choice(match_host: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "qilin_damage":
		return false
	_apply_runtime_choice(match_host, context, selected_uids)
	return true


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
