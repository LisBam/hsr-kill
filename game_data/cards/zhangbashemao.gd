extends CardDefinition

## 【丈八蛇矛】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "zhangba",
		"original_name": "丈八蛇矛",
		"custom_name": "银河球棒",
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
		"description": "你可将两张手牌当【杀】使用或打出。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":3.5, "equip_value":3.5, "view_as_sha":true},
		"ai_use_value": 4.0,
		"response_material_count": 2,
		"play_phase_interaction": "virtual_card_materials",
		"play_phase_action_type": "use_zhangba",
		"play_phase_material_count": 2,
		"play_phase_action_card_source": "equipment",
	})


## 执行【丈八蛇矛】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 丈八蛇矛在需要响应【杀】且持有至少2张普通手牌时提供装备入口。
func can_offer_equipment_response(match_host: Object, player_id: int, response_patterns: Array[String]) -> bool:
	# 响应玩家状态；木牛“粮”不计入丈八材料数量。
	var player: PlayerState = match_host.state.get_player(player_id)
	return response_patterns.has("sha") and player != null and player.hand.size() >= 2


## 丈八蛇矛响应固定消耗2张不同的普通手牌。
func get_equipment_response_material_count() -> int:
	return 2


## 校验丈八响应材料；装备必须是当前实体，材料必须为两张不同普通手牌。
func validate_equipment_response_materials(match_host: Object, player_id: int, equipment_uid: int, material_card_uids: Array[int]) -> String:
	# 当前丈八蛇矛实体；等待期间换装时旧入口失效。
	var equipment_card: CardInstance = match_host.get_equipment_card(player_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id() or equipment_card.uid != equipment_uid:
		return "玩家当前未装备所选择的丈八蛇矛。"
	if material_card_uids.size() != 2 or material_card_uids[0] == material_card_uids[1]:
		return "丈八蛇矛必须选择两张不同的手牌。"
	# 响应玩家状态；每张材料都必须仍位于普通手牌区。
	var player: PlayerState = match_host.state.get_player(player_id)
	if player == null:
		return "丈八蛇矛的发动者不存在或已经死亡。"
	for material_card_uid: int in material_card_uids:
		if player.find_hand_card(material_card_uid) == null:
			return "丈八蛇矛的材料必须是当前仍在手牌区的实体牌。"
	return ""


## 消耗两张丈八材料并返回一张无花色、无点数、无颜色的虚拟【杀】。
func consume_equipment_response(match_host: Object, player_id: int, equipment_uid: int, response_patterns: Array[String], material_card_uids: Array[int]) -> CardInstance:
	if not response_patterns.has("sha"):
		return null
	# 材料校验结果；等待期间任一材料移动都会拒绝消费。
	var material_error: String = validate_equipment_response_materials(match_host, player_id, equipment_uid, material_card_uids)
	if not material_error.is_empty():
		return null
	# 响应玩家状态；用于生成永久语义日志。
	var player: PlayerState = match_host.state.get_player(player_id)
	return match_host.consume_virtual_equipment_response(player_id, equipment_uid, material_card_uids, "sha", "sha", "%s发动【丈八蛇矛】，将两张手牌当【杀】打出。" % player.display_name)


## 丈八蛇矛注册的出牌阶段主动动作类型。
func get_play_phase_action_types() -> Array[String]:
	return ["use_zhangba"]


## 至少有2张普通手牌且存在合法【杀】目标时允许点击丈八蛇矛。
func is_play_phase_action_available(match_host: Object, owner_id: int, equipment_card: CardInstance) -> bool:
	# 装备持有者；木牛“粮”不计入两张材料。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	if owner == null or owner.hand.size() < 2:
		return false
	for target_id: int in match_host.card_rules.list_legal_virtual_targets(owner_id, "sha"):
		# 单目标数组；显式类型用于满足规则服务的 Array[int] 边界。
		var target_ids: Array[int] = [target_id]
		if match_host.card_rules.validate_virtual_use(owner_id, "sha", target_ids).is_empty():
			return true
	return false


## 为基础 AI 追加使用前两张普通手牌发动丈八蛇矛的合法动作。
func append_play_phase_actions(match_host: Object, owner_id: int, equipment_card: CardInstance, result: Array[Dictionary]) -> void:
	# 装备持有者；不足2张普通手牌时没有候选动作。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	if owner == null or owner.hand.size() < 2:
		return
	for first_index: int in range(owner.hand.size() - 1):
		for second_index: int in range(first_index + 1, owner.hand.size()):
			# 当前两张材料 UID；枚举全部不同组合，使 AI 能保留桃、闪等高价值牌。
			var material_card_uids: Array[int] = [owner.hand[first_index].uid, owner.hand[second_index].uid]
			for target_id: int in match_host.card_rules.list_legal_virtual_targets(owner_id, "sha"):
				# 单目标虚拟【杀】；不应用方天画戟最后手牌修正。
				var target_ids: Array[int] = [target_id]
				# AI 动作；card_uid 指向丈八蛇矛实体，payload 保存两张材料。
				var action: PlayerAction = PlayerAction.new("use_zhangba", owner_id, equipment_card.uid, target_ids)
				action.payload = {"material_card_uids":material_card_uids.duplicate()}
				if validate_play_phase_action(match_host, action).is_empty():
					var action_data: Dictionary = action.to_dict()
					action_data["ai_card_definition_id"] = get_id()
					result.append(action_data)


## 评估丈八蛇矛虚拟【杀】；复用【杀】目标效用并扣除两张材料牌的保留价值。
func score_ai_play_phase_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 发动者 ID；用于身份态度和材料估值。
	var actor_id: int = int(action.get("actor_id", -1))
	# 虚拟【杀】动作；只向评估器提供合法目标与【杀】定义，不伪造实体 UID。
	var slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	# 虚拟【杀】基础收益；包含目标体力、手牌与身份态度。
	var score: float = evaluator.score_action(authoritative_snapshot, slash_action, actor_id)
	for material_uid_variant: Variant in (action.get("payload", {}) as Dictionary).get("material_card_uids", []) as Array:
		# 当前材料牌价值；两张材料都会在结算后进入弃牌堆。
		var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, actor_id, int(material_uid_variant))
		score -= material_value * 0.45
	return score


## 构造丈八蛇矛实际生成的普通【杀】代理动作；疾雨、星火等使用【杀】联动会由基础AI统一计入。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, action: Dictionary, _evaluator: Object) -> Dictionary:
	# 发动者ID；自定义装备动作与虚拟【杀】必须保持同一使用者。
	var actor_id: int = int(action.get("actor_id", -1))
	return {"action_type":"use_card", "actor_id":actor_id, "card_definition_id":"sha", "target_ids":(action.get("target_ids", []) as Array).duplicate()}


## 校验丈八主动使用：装备、两张材料、阶段次数、攻击范围和目标必须全部合法。
func validate_play_phase_action(match_host: Object, action: PlayerAction) -> String:
	if action.action_type != "use_zhangba":
		return "丈八蛇矛不支持该动作。"
	# 两张材料 UID；只能来自普通手牌区。
	var material_card_uids: Array[int] = []
	for uid_variant: Variant in action.payload.get("material_card_uids", []) as Array:
		material_card_uids.append(int(uid_variant))
	# 材料错误；复用响应与主动使用完全相同的装备实体校验。
	var material_error: String = validate_equipment_response_materials(match_host, action.actor_id, action.card_uid, material_card_uids)
	if not material_error.is_empty():
		return material_error
	return match_host.card_rules.validate_virtual_use(action.actor_id, "sha", action.target_ids)


## 执行丈八虚拟【杀】；逻辑代理进入处理区，两张材料在整张牌结算后弃置。
func execute_play_phase_action(match_host: Object, action: PlayerAction) -> bool:
	# 权威校验结果；空字符串才允许创建虚拟牌事件。
	var validation_error: String = validate_play_phase_action(match_host, action)
	if not validation_error.is_empty():
		return false
	# 两张材料 UID；顺序与玩家选择顺序一致。
	var material_card_uids: Array[int] = []
	for uid_variant: Variant in action.payload.get("material_card_uids", []) as Array:
		material_card_uids.append(int(uid_variant))
	# 装备持有者状态；用于永久语义日志。
	var owner: PlayerState = match_host.state.get_player(action.actor_id)
	return match_host.execute_virtual_card_use(action.actor_id, "sha", material_card_uids, action.target_ids, "%s发动【丈八蛇矛】，将两张手牌当【杀】使用。" % owner.display_name)


## 返回丈八主动使用预览；字段与普通卡牌目标预览保持一致。
func get_play_phase_action_preview(match_host: Object, owner_id: int, equipment_uid: int, payload: Dictionary, selected_target_ids: Array[int]) -> Dictionary:
	# 丈八预览结果；默认不能提交，后续按材料和目标校验更新。
	var result: Dictionary = {
		"card_found":false,
		"can_submit":false,
		"validation_error":"当前不能发动丈八蛇矛。",
		"legal_target_ids":[],
		"normalized_target_ids":selected_target_ids.duplicate(),
		"target_mode":"single_other",
		"min_targets":1,
		"max_targets":1,
		"description":str(get_metadata().get("description", "")),
	}
	# 材料 UID；预览阶段允许尚未选满，并返回明确错误。
	var material_card_uids: Array[int] = []
	for uid_variant: Variant in payload.get("material_card_uids", []) as Array:
		material_card_uids.append(int(uid_variant))
	# 材料错误；合法时继续查询目标。
	var material_error: String = validate_equipment_response_materials(match_host, owner_id, equipment_uid, material_card_uids)
	result["card_found"] = material_error.is_empty()
	if not material_error.is_empty():
		result["validation_error"] = material_error
		return result
	# 当前完整目标校验；空字符串表示可提交。
	var validation_error: String = match_host.card_rules.validate_virtual_use(owner_id, "sha", selected_target_ids)
	result["validation_error"] = validation_error
	result["can_submit"] = validation_error.is_empty()
	# 全部合法单目标候选；允许玩家直接切换目标。
	var legal_target_ids: Array[int] = []
	for target_id: int in match_host.card_rules.list_legal_virtual_targets(owner_id, "sha"):
		# 单目标数组；显式类型用于满足规则服务的 Array[int] 边界。
		var target_ids: Array[int] = [target_id]
		if match_host.card_rules.validate_virtual_use(owner_id, "sha", target_ids).is_empty():
			legal_target_ids.append(target_id)
	result["legal_target_ids"] = legal_target_ids
	return result
