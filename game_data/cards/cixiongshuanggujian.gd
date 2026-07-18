extends CardDefinition

## 【雌雄双股剑】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "cixiong",
		"original_name": "雌雄双股剑",
		"custom_name": "双生星刃",
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
		"description": "【杀】指定异性目标后，可令其弃一张手牌，否则你摸一张牌。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":2.0, "equip_value":2.0},
		"ai_use_value": 4.0,
	})


## 执行【雌雄双股剑】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 【杀】指定异性目标后询问是否发动；同步完成时返回 false 让通用流程继续。
func on_slash_targeted(slash_effect: Object, context: Dictionary) -> bool:
	# 攻击者 ID；用于读取性别、摸牌和验证当前武器。
	var actor_id: int = int(context.get("actor_id", -1))
	# 目标 ID；用于读取性别与手牌候选。
	var target_id: int = int(context.get("target_id", -1))
	# 攻击者性别；unknown 不参与异性比较。
	var actor_gender: String = slash_effect.host.get_player_gender(actor_id)
	# 目标性别；双方必须均为明确二元性别且不同。
	var target_gender: String = slash_effect.host.get_player_gender(target_id)
	if actor_gender not in ["male", "female"] or target_gender not in ["male", "female"] or actor_gender == target_gender:
		return false
	# 发动上下文；装备 ID 用于异步选择回到本文件。
	var trigger_context: Dictionary = context.duplicate(true)
	trigger_context["kind"] = "cixiong_trigger"
	trigger_context["equipment_definition_id"] = get_id()
	# 是否发动；正式玩家请求会暂停，AI或测试可能同步返回结果。
	var activated: bool = slash_effect.host.request_equipment_trigger(actor_id, get_id(), "雌雄双股剑", "是否发动【雌雄双股剑】？", trigger_context, true)
	if slash_effect.host.has_pending_card_choice():
		return true
	if not activated:
		return false
	return _apply_trigger(slash_effect, trigger_context, false)


## 应用发动结果；目标可弃一张普通手牌，否则攻击者摸一张牌。
func _apply_trigger(slash_effect: Object, context: Dictionary, resume_after: bool) -> bool:
	# 攻击者 ID；目标不弃牌时摸1张牌。
	var actor_id: int = int(context.get("actor_id", -1))
	# 目标 ID；其普通手牌构成本次弃牌候选。
	var target_id: int = int(context.get("target_id", -1))
	# 目标状态；等待期间死亡时直接停止本次武器效果。
	var target: PlayerState = slash_effect.state.get_player(target_id)
	if target == null or not target.alive:
		return true
	if target.hand.is_empty():
		slash_effect.host.draw(actor_id, 1)
		if resume_after:
			slash_effect.continue_after_weapon_targeted(context)
		return false
	# 目标普通手牌候选；木牛“粮”和装备不属于该费用。
	var candidates: Array[Dictionary] = slash_effect.host.get_hand_candidates(target_id, target_id)
	# 弃牌上下文；空选择表示拒绝弃牌并让攻击者摸1张。
	var discard_context: Dictionary = context.duplicate(true)
	discard_context["kind"] = "cixiong_discard"
	discard_context["equipment_definition_id"] = get_id()
	discard_context["ai_prefer_select"] = true
	# 目标弃牌选择；允许取消且最多选择1张。
	var selected_uids: Array[int] = slash_effect.host.request_card_choice(target_id, "雌雄双股剑", "请弃置一张手牌，否则对方摸一张牌。", candidates, 0, 1, true, discard_context)
	if slash_effect.host.has_pending_card_choice():
		return true
	_apply_discard(slash_effect, discard_context, selected_uids)
	if resume_after:
		slash_effect.continue_after_weapon_targeted(discard_context)
	return false


## 应用目标弃牌结果；弃置失败、取消或牌已移动时攻击者摸1张。
func _apply_discard(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	# 实际弃置数量；只有成功弃置1张才算支付。
	var discarded_count: int = slash_effect.host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count != 1:
		slash_effect.host.draw(int(context.get("actor_id", -1)), 1)


## 恢复雌雄双股剑发动或目标弃牌选择，并回到通用【杀】流程。
func continue_slash_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	# 选择用途；本文件只处理两种雌雄双股剑请求。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "cixiong_trigger":
		if selected_uids.is_empty():
			slash_effect.continue_after_weapon_targeted(context)
		else:
			_apply_trigger(slash_effect, context, true)
		return true
	if choice_kind == "cixiong_discard":
		_apply_discard(slash_effect, context, selected_uids)
		slash_effect.continue_after_weapon_targeted(context)
		return true
	return false
