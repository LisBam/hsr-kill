extends CardDefinition

## 【木牛流马】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "muniu",
		"original_name": "木牛流马",
		"custom_name": "自动物流机巧",
		"type": "equipment",
		"subtype": "treasure",
		"effect_id": "equip",
		"slot": "treasure",
		"attack_range": 0,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段限一次，可将一张手牌扣置为“粮”；可使用或打出“粮”，并可将此装备移动给其他角色。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":7.0, "value":7.0, "equip_value":7.0},
		"play_phase_interaction": "store_attachment",
		"play_phase_action_type": "store_wooden_ox",
		"play_phase_material_count": 1,
		"play_phase_action_card_source": "material",
		"shows_attachment_count": true,
	})


## 执行【木牛流马】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 木牛流马离开装备区时将其全部“粮”置入弃牌堆，并清空附属存储区。
func on_leave_equipment(match_host: Object, owner: PlayerState, trigger_loss_effects: bool) -> void:
	for stored_card: CardInstance in owner.wooden_ox_storage:
		match_host.discard_card_instance(stored_card)
	owner.wooden_ox_storage.clear()


## 新回合开始时重置持有者本回合的存粮发动次数。
func on_turn_started(match_host: Object, player_id: int) -> void:
	# 新回合玩家；无效角色不写入兼容状态。
	var player: PlayerState = match_host.state.get_player(player_id)
	if player != null:
		player.wooden_ox_used = false


## 木牛流马注册的出牌阶段主动存粮动作类型。
func get_play_phase_action_types() -> Array[String]:
	return ["store_wooden_ox"]


## 本阶段尚未发动且持有至少1张普通手牌时允许点击木牛流马。
func is_play_phase_action_available(match_host: Object, owner_id: int, equipment_card: CardInstance) -> bool:
	# 装备持有者；已有“粮”不能再次作为存入材料。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	return owner != null and not owner.wooden_ox_used and not owner.hand.is_empty()


## 为基础 AI 追加每张普通手牌的存粮动作；默认不主动转移宝物。
func append_play_phase_actions(match_host: Object, owner_id: int, equipment_card: CardInstance, result: Array[Dictionary]) -> void:
	# 装备持有者；本阶段已发动时不产生动作。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	if owner == null or owner.wooden_ox_used:
		return
	for hand_card: CardInstance in owner.hand:
		result.append({"action_type":"store_wooden_ox", "actor_id":owner_id, "card_uid":hand_card.uid, "target_ids":[], "card_definition_id":"muniu_store", "ai_card_definition_id":get_id()})


## 评估木牛流马存粮动作；手牌超上限时收益显著提高，并优先扣置保留价值最低的手牌。
func score_ai_play_phase_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 发动者 ID；用于读取手牌、体力与材料价值。
	var actor_id: int = int(action.get("actor_id", -1))
	# 发动者状态；不存在时不发动。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return 0.0
	# 手牌溢出量；存粮不计入弃牌阶段手牌上限，因此每张溢出牌提供明显收益。
	var overflow_count: int = maxi(int(actor.get("hand_count", 0)) - maxi(int(actor.get("hp", 0)), 0), 0)
	# 被扣置材料价值；木牛“粮”仍可使用，只施加轻微可见性与宝物丢失风险成本。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, actor_id, int(action.get("card_uid", -1)))
	return 0.8 + float(overflow_count) * 1.5 - material_value * 0.08


## 校验木牛存粮动作；材料必须为普通手牌，转移目标至多1名其他存活角色。
func validate_play_phase_action(match_host: Object, action: PlayerAction) -> String:
	if action.action_type != "store_wooden_ox":
		return "木牛流马不支持该动作。"
	# 装备持有者；必须处于自己的出牌阶段且本阶段尚未发动。
	var owner: PlayerState = match_host.state.get_player(action.actor_id)
	if owner == null or match_host.state.current_phase != "play" or match_host.state.current_player_id != action.actor_id:
		return "当前不能发动木牛流马。"
	# 当前宝物实体；必须仍为木牛流马。
	var equipment_card: CardInstance = match_host.get_equipment_card(action.actor_id, "treasure")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return "玩家未装备木牛流马。"
	if owner.wooden_ox_used:
		return "本阶段已经发动过木牛流马。"
	if owner.find_hand_card(action.card_uid) == null:
		return "木牛流马只能扣置一张普通手牌。"
	if action.target_ids.size() > 1:
		return "木牛流马最多转移给一名其他角色。"
	if action.target_ids.size() == 1:
		# 转移目标；必须是另一名存活角色。
		var target: PlayerState = match_host.state.get_player(action.target_ids[0])
		if target == null or not target.alive or target.player_id == action.actor_id:
			return "木牛流马转移目标不合法。"
	return ""


## 执行木牛存粮，并按玩家选择把宝物与全部“粮”转移给另一名角色。
func execute_play_phase_action(match_host: Object, action: PlayerAction) -> bool:
	# 权威校验结果；失败时不移动任何实体牌。
	var validation_error: String = validate_play_phase_action(match_host, action)
	if not validation_error.is_empty():
		return false
	# 装备持有者；用于状态标记、附属牌集合与日志。
	var owner: PlayerState = match_host.state.get_player(action.actor_id)
	# 被扣置手牌；成功后进入 wooden_ox 附属区域。
	var stored_card: CardInstance = match_host.move_hand_card_to_equipment_attachment(action.actor_id, action.card_uid, "wooden_ox")
	if stored_card == null:
		return false
	owner.wooden_ox_used = true
	match_host.add_log("%s将一张手牌扣置于【木牛流马】下。" % owner.display_name)
	if action.target_ids.is_empty():
		return true
	# 转移目标；校验阶段已保证存在且为其他存活角色。
	var target: PlayerState = match_host.state.get_player(action.target_ids[0])
	# 转移前附属牌快照；包含本次新存入的手牌与原有全部“粮”。
	var attachment_cards: Array[CardInstance] = owner.wooden_ox_storage.duplicate()
	if not match_host.transfer_equipment_with_attachments(action.actor_id, target.player_id, "treasure", attachment_cards, "wooden_ox"):
		return false
	owner.wooden_ox_storage.clear()
	match_host.add_log("%s将【木牛流马】及其下的“粮”转移给%s。" % [owner.display_name, target.display_name])
	return true


## 返回木牛存粮与可选转移目标预览；不选择目标表示宝物留在原角色装备区。
func get_play_phase_action_preview(match_host: Object, owner_id: int, equipment_uid: int, payload: Dictionary, selected_target_ids: Array[int]) -> Dictionary:
	# 当前材料 UID；UI 使用数组统一承载不同装备的材料选择。
	var material_card_uids: Array = payload.get("material_card_uids", []) as Array
	# 可转移目标；所有其他存活角色均可接收木牛及全部“粮”。
	var legal_target_ids: Array[int] = []
	for player: PlayerState in match_host.state.players:
		if player.alive and player.player_id != owner_id:
			legal_target_ids.append(player.player_id)
	# 预览动作；材料存在时把首张普通手牌作为动作 card_uid。
	var action: PlayerAction = PlayerAction.new("store_wooden_ox", owner_id, int(material_card_uids[0]) if not material_card_uids.is_empty() else -1, selected_target_ids)
	# 当前校验结果；材料未选时保持明确提示。
	var validation_error: String = "请选择一张要存入木牛流马的手牌。" if material_card_uids.is_empty() else validate_play_phase_action(match_host, action)
	return {
		"card_found":not material_card_uids.is_empty(),
		"can_submit":validation_error.is_empty(),
		"validation_error":validation_error,
		"legal_target_ids":legal_target_ids,
		"normalized_target_ids":selected_target_ids.duplicate(),
		"target_mode":"optional_single_other",
		"min_targets":0,
		"max_targets":1,
		"description":str(get_metadata().get("description", "")),
	}
