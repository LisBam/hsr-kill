extends SkillDefinition

## 【安打】技能源码。持有者每回合可把一张自有牌当无距离限制的火【杀】使用或打出。

## 安打生成的火【杀】定义ID；单材料虚拟牌继承原实体花色与点数。
const FIRE_SLASH_DEFINITION_ID: String = "sha_fire"

## 虚拟火【杀】忽略攻击范围的规则覆写；只影响本技能主动使用的目标合法性。
const VIRTUAL_RULE_OVERRIDES: Dictionary = {"ignore_distance_limit":true}

## AI消耗材料保留价值的扣分权重；默认0.45避免为低收益攻击浪费关键牌。
const AI_MATERIAL_COST_WEIGHT: float = 0.45

## 最近一次成功发动所在回合号；默认-1表示本局尚未发动，比较state.turn_number实现每回合限一次。
var _used_turn_number: int = -1


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id": "anda",
		"name": "安打",
		"trigger": "active",
		"enable": ["phaseUse", "chooseToRespond"],
		"ui_enabled": true,
		"description": "你可将一张牌当无距离限制的火【杀】使用或打出，每回合限一次。",
	})


## 判断当前回合是否仍有额度，并分别校验主动使用与【杀】响应入口。
func can_activate(context: Dictionary = {}) -> bool:
	if host == null or _used_turn_number == host.state.turn_number or _get_material_candidates().is_empty():
		return false
	# 当前主动入口；响应时只要求窗口接受【杀】，不检查距离或目标。
	var active_entry: String = str(context.get("active_entry", ""))
	if active_entry == "chooseToRespond":
		return (context.get("response_patterns", []) as Array).has("sha")
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 材料候选；按钮可用性必须与虚拟火【杀】完整校验一致，包括本阶段【杀】次数。
	var candidates: Array[Dictionary] = _get_material_candidates()
	# 材料与目标组合数据；目标预览不校验次数，因此下方必须再走完整校验。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 逐材料合法目标映射；键为材料UID字符串。
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前材料UID；手牌、木牛“粮”与装备共用同一实体标识。
		var material_card_uid: int = int(candidate.get("uid", -1))
		# 当前材料实体；找不到时跳过，避免候选快照与权威区域短暂不一致。
		var material_card: CardInstance = _find_owned_material_card(material_card_uid)
		if material_card == null:
			continue
		for target_id_variant: Variant in target_ids_by_card_id.get(str(material_card_uid), []) as Array:
			# 当前单目标数组；validate_virtual_use_for_material 会复核阶段次数、存活状态与目标模式。
			var target_ids: Array[int] = [int(target_id_variant)]
			if validate_virtual_use_for_material(FIRE_SLASH_DEFINITION_ID, material_card, target_ids, VIRTUAL_RULE_OVERRIDES).is_empty():
				return true
	return false


## 主动发动安打；AI可直接提交材料与目标，玩家按钮进入统一牌目标组合选择。
func activate(context: Dictionary = {}) -> String:
	# 动作指定材料UID；负数表示需要创建玩家选择。
	var material_card_uid: int = int(context.get("material_card_uid", -1))
	# 动作指定目标数组；火【杀】基础目标数固定为1。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if material_card_uid >= 0 and target_ids.size() == 1:
		return "" if _execute_conversion(material_card_uid, target_ids) else "【安打】材料或目标已不合法。"
	# 当前全部自有材料；可来自手牌、木牛“粮”或装备区。
	var candidates: Array[Dictionary] = _get_material_candidates()
	# 当前无距离火【杀】目标；提交时仍会完整复核次数、存活状态和目标模式。
	# 材料与目标组合数据；黑色材料转换的火【杀】同样受【琥珀】目标限制，红色材料不受影响。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 当前无距离火【杀】目标并集；提交时仍会完整复核次数、存活状态、材料颜色和目标模式。
	var legal_target_ids: Array[int] = []
	legal_target_ids.assign(selection_data.get("target_ids", []) as Array)
	if candidates.is_empty() or legal_target_ids.is_empty():
		return "当前没有可用的牌或火【杀】目标。"
	request_card_target_selection("安打", "请选择一张牌和一名火【杀】目标", candidates, legal_target_ids, 1, 1, 1, 1, true, {"kind":"anda_use", "target_ids_by_card_id":selection_data.get("target_ids_by_card_id", {})})
	return ""


## 恢复安打的牌与目标组合选择；取消不会消耗每回合额度。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "anda_use" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 1 and response.target_ids.size() == 1:
		_execute_conversion(response.card_ids[0], response.target_ids)
	return true


## 权威复核并执行单材料火【杀】转化；只有虚拟用牌成功后才消费本回合次数。
func _execute_conversion(material_card_uid: int, target_ids: Array[int]) -> bool:
	# 当前材料实体；除区域复核外还用于把真实颜色传入目标免疫规则。
	var material_card: CardInstance = _find_owned_material_card(material_card_uid)
	if _used_turn_number == host.state.turn_number or material_card == null:
		return false
	# 本次规则覆写；复制常量后补充材料颜色，避免修改共享常量字典。
	# 规则覆写由技能基类统一深复制并写入真实材料颜色，调用方不再持有可变副本。
	if validate_virtual_use_for_material(FIRE_SLASH_DEFINITION_ID, material_card, target_ids, VIRTUAL_RULE_OVERRIDES) != "":
		return false
	# 单材料数组；显式类型保证动态控制器端口收到稳定整数数组。
	var material_card_uids: Array[int] = [material_card_uid]
	# 技能持有者；仅用于长期语义日志，不直接修改其牌区。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not bool(host.call("execute_virtual_card_use", owner_player_id, FIRE_SLASH_DEFINITION_ID, material_card_uids, target_ids, "", VIRTUAL_RULE_OVERRIDES)):
		return false
	_used_turn_number = host.state.turn_number
	announce_activation({"material_card_uid":material_card_uid, "target_ids":target_ids.duplicate(), "virtual_card_id":FIRE_SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":-1.5, "damage":true, "respond_shan":true, "nature_damage":true})
	return true


## 返回安打主动使用时的全部合法无距离目标。
func _get_legal_target_ids() -> Array[int]:
	# 当前材料候选；目标并集必须包含每张材料真实颜色下至少一种合法组合。
	var candidates: Array[Dictionary] = _get_material_candidates()
	# 当前材料选择数据；用于保持主动按钮与后续组合请求采用同一规则来源。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 当前合法目标并集；调用方只能用于初步可用性判断，具体组合仍读取材料映射。
	var target_ids: Array[int] = []
	target_ids.assign(selection_data.get("target_ids", []) as Array)
	return target_ids


## 返回技能持有者当前全部自有材料候选。
func _get_material_candidates() -> Array[Dictionary]:
	return host.call("get_skill_material_candidates", owner_player_id) as Array[Dictionary]


## 按UID查询仍由技能持有者拥有的手牌、木牛“粮”或装备材料。
func _find_owned_material_card(card_uid: int) -> CardInstance:
	# 技能持有者；无效角色没有可用材料。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return null
	# 手牌或木牛“粮”；PlayerState统一查询可使用牌源。
	var playable_card: CardInstance = owner.find_playable_card(card_uid)
	if playable_card != null:
		return playable_card
	for equipment_variant: Variant in owner.equipment.values():
		# 当前装备实体；稳定UID匹配时允许作为“一张牌”的材料。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card.uid == card_uid:
			return equipment_card
	return null


## 判断一张材料能否在本回合通过安打转化为【杀】响应。
func can_convert_response_card(card: CardInstance, response_patterns: Array[String]) -> bool:
	return card != null and host != null and _used_turn_number != host.state.turn_number and response_patterns.has("sha")


## 返回安打响应转化后的火【杀】定义；等待期间额度失效则返回空字符串。
func get_converted_response_definition_id(card: CardInstance, response_patterns: Array[String]) -> String:
	return FIRE_SLASH_DEFINITION_ID if can_convert_response_card(card, response_patterns) else ""


## 响应材料被控制器实际消费后记录本回合额度；查询与预览阶段不会提前占用次数。
func on_converted_response_consumed(_card: CardInstance, _response_pattern: String, _virtual_definition_id: String) -> void:
	_used_turn_number = host.state.turn_number


## 为AI枚举全部材料与无距离目标组合。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前全部材料；目标集合根据每张实体的真实颜色分别计算。
	var candidates: Array[Dictionary] = _get_material_candidates()
	# 材料到合法目标映射；AI不会再枚举提交时必定失败的材料目标组合。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 当前映射字典；键为材料UID字符串。
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前材料UID；用于权威提交和材料价值评估。
		var material_card_uid: int = int(candidate.get("uid", -1))
		# 当前材料实体；用于最终完整虚拟牌组合校验。
		var material_card: CardInstance = _find_owned_material_card(material_card_uid)
		# 当前材料合法目标；每项已经包含无距离覆写与材料颜色限制。
		var material_target_ids: Array = target_ids_by_card_id.get(str(material_card_uid), []) as Array
		for target_id_variant: Variant in material_target_ids:
			# 当前目标ID；显式转为整数保证动作负载稳定。
			var target_id: int = int(target_id_variant)
			# 当前单目标组合；最终校验通过后才进入AI合法动作列表。
			var target_ids: Array[int] = [target_id]
			if material_card != null and validate_virtual_use_for_material(FIRE_SLASH_DEFINITION_ID, material_card, target_ids, VIRTUAL_RULE_OVERRIDES).is_empty():
				result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "material_card_uid":material_card_uid, "target_ids":target_ids.duplicate()}})


## 复用火【杀】标准收益并扣除真实材料价值，使AI优先消耗低价值牌攻击敌方。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 技能动作负载；保存材料UID与目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 火【杀】代理动作；通用评估器负责敌我、闪、藤甲和属性连环收益。
	var slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	# 火【杀】基础收益；不包含材料机会成本。
	var score: float = evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id)
	# 材料牌保留价值；桃、闪与关键装备会获得更高保留权重。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	return score - material_value * AI_MATERIAL_COST_WEIGHT


## 构造安打实际生成的火【杀】代理动作；材料颜色会继续参与仁王盾等防具的完整AI判断。
func build_ai_virtual_card_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> Dictionary:
	# 技能动作负载；保存材料UID与目标数组。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 材料牌快照；虚拟火【杀】继承该实体的真实颜色。
	var material_card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":FIRE_SLASH_DEFINITION_ID, "card_color":str(material_card.get("color", "")), "target_ids":(action.get("target_ids", payload.get("target_ids", [])) as Array).duplicate()}
