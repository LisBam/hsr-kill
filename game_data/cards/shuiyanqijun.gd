extends CardDefinition

## 【水淹七军】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "shuiyanqijun",
		"original_name": "水淹七军",
		"custom_name": "水淹七军",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "flood",
		"nature": "normal",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "目标选择弃置装备区所有牌，或受到你造成的1点伤害。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
		"ai": {"order":6.0, "value":5.0, "target_result":-1.5, "damage":true, "lose_card":true},
		"ai_target_attitude": "hostile",
	})


## 执行【水淹七军】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		_request_equipment_choice(resolver, card.uid, actor_id, target_id)
		if resolver.host.has_pending_card_choice():
			return "pending"
	return resolver.default_destination()


## 请求目标选择弃置装备区全部牌或承受1点普通伤害；无装备时直接造成伤害。
func _request_equipment_choice(resolver: Object, parent_card_uid: int, actor_id: int, target_id: int) -> void:
	# 当前目标状态；不存在时不创建选择。
	var target: PlayerState = resolver.state.get_player(target_id)
	if target == null:
		return
	if target.equipment.is_empty():
		resolver.host.damage(actor_id, target_id, 1, "normal", "shuiyanqijun")
		return
	# 装备区公开候选；必须整组选满才视为选择弃置全部装备。
	var candidates: Array[Dictionary] = resolver.host.get_equipment_candidates(target_id, target_id)
	# 选择恢复上下文；equipment_count 保存创建请求时的完整装备数量供界面校验。
	var context: Dictionary = {"kind":"flood_equipment", "parent_card_uid":parent_card_uid, "actor_id":actor_id, "target_id":target_id, "equipment_count":candidates.size(), "ai_prefer_select":true, "ai_full_selection_only":true}
	# 目标选择结果；允许选择0张或完整装备区数量。
	var selected_uids: Array[int] = resolver.host.request_card_choice(target_id, "水淹七军", "请选择是否弃置全部装备", candidates, 0, candidates.size(), true, context)
	if resolver.host.has_pending_card_choice():
		return
	_apply_choice(resolver, context, selected_uids)


## 应用目标选择；按最新装备区数量判断是否完整支付，防止等待期间装备变化导致错误弃置。
func _apply_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> void:
	# 目标角色 ID；用于读取最新装备区和承受伤害。
	var target_id: int = int(context.get("target_id", -1))
	# 使用者 ID；未弃置装备时作为伤害来源。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前目标状态；等待期间离场时停止效果。
	var target: PlayerState = resolver.state.get_player(target_id)
	if target == null:
		return
	if not selected_uids.is_empty() and selected_uids.size() == target.equipment.size():
		# 当前装备 UID 集合；所选组必须与最新装备区完全一致。
		var equipment_uids: Array[int] = []
		for equipment_variant: Variant in target.equipment.values():
			# 当前装备实体；只保存稳定 UID 用于集合校验。
			var equipment_card: CardInstance = equipment_variant as CardInstance
			equipment_uids.append(equipment_card.uid)
		for selected_uid: int in selected_uids:
			if not equipment_uids.has(selected_uid):
				resolver.host.damage(actor_id, target_id, 1, "normal", "shuiyanqijun")
				return
		resolver.host.discard_all_equipment(target_id, true)
	else:
		resolver.host.damage(actor_id, target_id, 1, "normal", "shuiyanqijun")


## 恢复弃置全部装备选择；应用结果后完成当前逐目标结算。
func continue_choice(resolver: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "flood_equipment":
		return false
	_apply_choice(resolver, context, selected_uids)
	resolver.host.complete_card_target(int(context.get("parent_card_uid", -1)))
	return true
