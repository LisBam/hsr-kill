extends CardDefinition

## 【银月枪】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "yinyue",
		"original_name": "银月枪",
		"custom_name": "击云",
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
		"description": "回合外使用或打出黑色手牌时，可令攻击范围内一名角色打出【闪】，否则对其造成1点伤害。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":3.0, "equip_value":3.0},
	})


## 执行【银月枪】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 持有者于回合外使用或打出黑色普通手牌后，将一次可选发动加入装备触发队列。
func on_owner_card_consumed(match_host: Object, owner_id: int, used_card: CardInstance, was_hand_card: bool) -> void:
	if not was_hand_card or used_card.get_color() != "black" or owner_id == match_host.state.current_player_id:
		return
	# 当前银月枪实体；必须仍位于持有者武器槽。
	var equipment_card: CardInstance = match_host.get_equipment_card(owner_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return
	match_host.queue_equipment_trigger(owner_id, equipment_card.uid, get_id(), {"used_card_uid":used_card.uid})


## 启动排队后的银月枪发动询问；等待期间仍需保持回合外、存活并装备同一实体。
func begin_queued_equipment_trigger(match_host: Object, owner_id: int, context: Dictionary) -> bool:
	# 装备持有者；死亡或进入自己回合时本次触发失效。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	if owner == null or not owner.alive or owner_id == match_host.state.current_player_id:
		return false
	# 当前武器实体；必须与队列记录的 UID 一致。
	var equipment_card: CardInstance = match_host.get_equipment_card(owner_id, "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return false
	# 发动选择上下文；不依附处理区父牌，使用装备定义 ID 直接恢复本文件。
	var trigger_context: Dictionary = context.duplicate(true)
	trigger_context["kind"] = "equipment_trigger"
	trigger_context["equipment_definition_id"] = get_id()
	# 是否发动；非锁定装备必须允许明确取消。
	var activated: bool = match_host.request_equipment_trigger(owner_id, get_id(), "银月枪", "是否发动【银月枪】？", trigger_context, true)
	if match_host.has_pending_card_choice():
		return true
	if activated:
		_activate(match_host, trigger_context)
	return true


## 确认发动后选择攻击范围内目标，并要求其响应【闪】。
func _activate(match_host: Object, context: Dictionary) -> void:
	# 银月枪持有者 ID；作为伤害来源保留。
	var owner_id: int = int(context.get("owner_id", -1))
	# 装备持有者；发动时再次校验存活与装备实体。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	# 当前银月枪实体；等待期间换装时本次发动失效。
	var equipment_card: CardInstance = match_host.get_equipment_card(owner_id, "weapon")
	if owner == null or not owner.alive or equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return
	# 攻击范围内的其他存活角色；保持持有者开始的行动顺序。
	var legal_targets: Array[PlayerState] = []
	for candidate: PlayerState in match_host.get_alive_players_in_action_order(owner_id):
		if candidate.player_id != owner_id and match_host.card_rules.calculate_distance(owner_id, candidate.player_id) <= match_host.card_rules.get_attack_range(owner_id):
			legal_targets.append(candidate)
	if legal_targets.is_empty():
		return
	# 自动目标；优先选择身份立场为敌方的首名合法角色。
	var target: PlayerState = legal_targets[0]
	for candidate: PlayerState in legal_targets:
		if match_host.get_identity_attitude(owner.identity, candidate.identity) < 0:
			target = candidate
			break
	match_host.add_log("%s发动【银月枪】，令%s响应【闪】。" % [owner.display_name, target.display_name])
	# 【闪】响应上下文；选择恢复通过装备定义 ID 回到本文件。
	var response_context: Dictionary = context.duplicate(true)
	response_context["kind"] = "equipment_response"
	response_context["responder_id"] = target.player_id
	response_context["equipment_definition_id"] = get_id()
	# 动作类别为“打出”：技能原文明确要求“打出【闪】”，该【闪】不产生抵消【杀】的牌面效果，也不属于“弃置”。
	response_context["response_action"] = CARD_ACTION_PLAY
	# 目标实际打出的【闪】；为空可能表示放弃或等待选择。
	var response_card: CardInstance = match_host.request_response_card(target.player_id, "shan", "是否打出【闪】响应银月枪？", response_context)
	if match_host.has_pending_card_choice():
		return
	_apply_response(match_host, response_context, response_card)


## 应用银月枪【闪】结果；未响应时造成固定1点普通伤害。
func _apply_response(match_host: Object, context: Dictionary, response_card: CardInstance) -> void:
	# 目标状态；用于响应成功日志。
	var target: PlayerState = match_host.state.get_player(int(context.get("responder_id", -1)))
	if target == null or match_host.state.game_over:
		return
	if response_card != null:
		match_host.add_log("%s打出【闪】抵消了【银月枪】。" % target.display_name)
	else:
		match_host.damage(int(context.get("owner_id", -1)), target.player_id, 1, "normal", get_id())


## 恢复银月枪发动选择；选中创建请求时的装备 UID 才执行效果。
func continue_equipment_choice(match_host: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != "equipment_trigger":
		return false
	if selected_uids.has(int(context.get("equipment_uid", -1))):
		_activate(match_host, context)
	if not match_host.has_pending_card_choice():
		match_host.process_next_equipment_trigger()
	return true


## 恢复银月枪目标的【闪】响应，并继续处理后续排队装备触发。
func continue_equipment_response(match_host: Object, context: Dictionary, response_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "equipment_response":
		return false
	_apply_response(match_host, context, response_card)
	match_host.process_next_equipment_trigger()
	return true
