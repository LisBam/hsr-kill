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
	return not _get_legal_target_ids().is_empty()


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
	var legal_target_ids: Array[int] = _get_legal_target_ids()
	if candidates.is_empty() or legal_target_ids.is_empty():
		return "当前没有可用的牌或火【杀】目标。"
	request_card_target_selection("安打", "请选择一张牌和一名火【杀】目标", candidates, legal_target_ids, 1, 1, 1, 1, true, {"kind":"anda_use"})
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
	var rule_overrides: Dictionary = VIRTUAL_RULE_OVERRIDES.duplicate(true)
	rule_overrides["card_color"] = material_card.get_color()
	if host.card_rules.validate_virtual_use(owner_player_id, FIRE_SLASH_DEFINITION_ID, target_ids, rule_overrides) != "":
		return false
	# 单材料数组；显式类型保证动态控制器端口收到稳定整数数组。
	var material_card_uids: Array[int] = [material_card_uid]
	# 技能持有者；仅用于长期语义日志，不直接修改其牌区。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not bool(host.call("execute_virtual_card_use", owner_player_id, FIRE_SLASH_DEFINITION_ID, material_card_uids, target_ids, "%s发动【安打】，将一张牌当火【杀】使用。" % owner.display_name)):
		return false
	_used_turn_number = host.state.turn_number
	announce_activation({"material_card_uid":material_card_uid, "target_ids":target_ids.duplicate(), "virtual_card_id":FIRE_SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":-1.5, "damage":true, "respond_shan":true, "nature_damage":true})
	return true


## 返回安打主动使用时的全部合法无距离目标。
func _get_legal_target_ids() -> Array[int]:
	return host.card_rules.list_legal_virtual_targets(owner_player_id, FIRE_SLASH_DEFINITION_ID, VIRTUAL_RULE_OVERRIDES)


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
	for candidate: Dictionary in _get_material_candidates():
		# 当前材料UID；用于权威提交和材料价值评估。
		var material_card_uid: int = int(candidate.get("uid", -1))
		for target_id: int in _get_legal_target_ids():
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "material_card_uid":material_card_uid, "target_ids":[target_id]}})


## 复用火【杀】标准收益并扣除真实材料价值，使AI优先消耗低价值牌攻击敌方。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 技能动作负载；保存材料UID与目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 火【杀】代理动作；通用评估器负责敌我、闪、藤甲和属性连环收益。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":FIRE_SLASH_DEFINITION_ID, "target_ids":(action.get("target_ids", payload.get("target_ids", [])) as Array).duplicate()}
	# 火【杀】基础收益；不包含材料机会成本。
	var score: float = evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id)
	# 材料牌保留价值；桃、闪与关键装备会获得更高保留权重。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	return score - material_value * AI_MATERIAL_COST_WEIGHT
