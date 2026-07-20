extends SkillDefinition

## 【罡风】技能源码。持有者可把任意当前拥有的黑色牌当雷【杀】使用或打出，材料保留实体花色与点数。

## 罡风生成的虚拟雷【杀】定义ID；规则牌名为【杀】，界面显示仍为两字“雷杀”。
const THUNDER_SLASH_DEFINITION_ID: String = "sha_thunder"

## 罡风材料必须满足的颜色；黑桃与梅花实体牌的CardInstance.get_color()均返回black。
const REQUIRED_COLOR: String = "black"

## AI对消耗材料牌保留价值的扣分权重；数值越高越保留高价值黑色牌。
const AI_MATERIAL_COST_WEIGHT: float = 0.45

## 技能元数据中的雷【杀】联动优先分字段；罡风读取所有已拥有技能的数据，不硬编码疾雨ID。
const AI_THUNDER_PRIORITY_METADATA_KEY: String = "ai_thunder_slash_priority_bonus"


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "gangfeng",
		"name": "罡风",
		"trigger": "active",
		"enable": ["phaseUse", "chooseToRespond"],
		"ui_enabled": true,
		"description": "你可将黑色牌当雷【杀】使用或打出。",
	})


## 只有在自身出牌阶段、存在黑色材料且至少有一名合法雷【杀】目标时可主动发动。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非本人出牌阶段时不能主动转化。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	# 响应入口；只有明确需要打出【杀】且存在黑色材料时技能按钮亮起，材料不会自动视为【杀】。
	if str(_context.get("active_entry", "")) == "chooseToRespond":
		return (_context.get("response_patterns", []) as Array).has("sha") and not _get_black_material_candidates().is_empty()
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 当前黑色材料候选；目标合法性必须同时读取每张材料的真实颜色，不能先按无色雷【杀】枚举。
	var candidates: Array[Dictionary] = _get_black_material_candidates()
	if candidates.is_empty():
		return false
	# 材料与目标组合数据；黑色材料会在此排除拥有【琥珀】的角色。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates)
	if not (selection_data.get("target_ids", []) as Array).is_empty():
		# 单目标数组；虚拟使用还需复核阶段【杀】次数、距离与目标组合。
		# 当前可用性只确认存在至少一个逐材料合法目标，具体单目标数组在动作枚举和提交阶段继续完整复核。
		return true
	return false


## 主动发动罡风；AI动作可直接携带材料和目标，玩家按钮则进入统一牌目标组合选择。
func activate(context: Dictionary = {}) -> String:
	# 动作指定的材料UID；负数表示界面尚未选材料。
	var material_card_uid: int = int(context.get("material_card_uid", -1))
	# 动作指定的目标数组；标准雷【杀】要求恰好一名其他角色。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if material_card_uid >= 0 and target_ids.size() == 1:
		return "" if _execute_conversion(material_card_uid, target_ids) else "【罡风】材料或目标已不合法。"
	# 黑色材料候选；包含手牌、木牛“粮”与装备区实体。
	var candidates: Array[Dictionary] = _get_black_material_candidates()
	# 虚拟雷【杀】目标；距离与存活状态由CardRuleService统一计算。
	# 材料与目标组合数据；每张材料独立参与虚拟雷【杀】目标判断。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates)
	# 虚拟雷【杀】目标并集；材料选中后界面会按映射缩小为该牌自己的合法目标。
	var legal_target_ids: Array[int] = []
	legal_target_ids.assign(selection_data.get("target_ids", []) as Array)
	if candidates.is_empty() or legal_target_ids.is_empty():
		return "当前没有可用的黑色牌或雷【杀】目标。"
	request_card_target_selection("罡风", "请选择一张黑色牌和一名雷【杀】目标", candidates, legal_target_ids, 1, 1, 1, 1, true, {"kind":"gangfeng_use", "target_ids_by_card_id":selection_data.get("target_ids_by_card_id", {})})
	return ""


## 恢复罡风的材料与目标组合选择；等待期间任一条件失效时直接跳过本次效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "gangfeng_use" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 1 and response.target_ids.size() == 1:
		_execute_conversion(response.card_ids[0], response.target_ids)
	return true


## 权威复核并执行黑色牌转化；虚拟雷【杀】使用成功后才记录技能发动。
func _execute_conversion(material_card_uid: int, target_ids: Array[int]) -> bool:
	# 当前材料实体；必须仍由技能持有者拥有且颜色为黑色。
	var material_card: CardInstance = _find_owned_material_card(material_card_uid)
	if material_card == null or material_card.get_color() != REQUIRED_COLOR:
		return false
	if validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, target_ids) != "":
		return false
	# 技能持有者；只用于构造长期语义日志，不直接修改区域。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 单张材料UID数组；显式Array[int]类型保证动态host.call与核心端口的强类型参数一致。
	var material_card_uids: Array[int] = [material_card_uid]
	if owner == null or not bool(host.call("execute_virtual_card_use", owner_player_id, THUNDER_SLASH_DEFINITION_ID, material_card_uids, target_ids, "%s发动【罡风】，将一张黑色牌当雷【杀】使用。" % owner.display_name, {})):
		return false
	announce_activation({"material_card_uid":material_card_uid, "target_ids":target_ids.duplicate(), "virtual_card_id":THUNDER_SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":-1.5, "damage":true, "respond_shan":true, "nature_damage":true})
	return true


## 返回技能持有者的全部黑色材料候选；候选牌面均对本人可见。
func _get_black_material_candidates() -> Array[Dictionary]:
	# 所有自有材料候选；由核心端口统一包含手牌、木牛“粮”与装备。
	var all_candidates: Array[Dictionary] = host.call("get_skill_material_candidates", owner_player_id) as Array[Dictionary]
	# 黑色候选结果；保持原区域顺序以稳定UI、AI与回放。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in all_candidates:
		# 候选牌面数据；本人自有牌可见，color由CardInstance序列化统一提供。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(card_data.get("color", "none")) == REQUIRED_COLOR:
			result.append(candidate)
	return result


## 按UID查找技能持有者的手牌、木牛“粮”或装备实体；只返回当前仍在原区域的牌。
func _find_owned_material_card(card_uid: int) -> CardInstance:
	# 技能持有者；不存在时不查询任何实体区域。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return null
	# 手牌或木牛“粮”实体；PlayerState使用统一可使用牌查询。
	var playable_card: CardInstance = owner.find_playable_card(card_uid)
	if playable_card != null:
		return playable_card
	for equipment_variant: Variant in owner.equipment.values():
		# 当前装备实体；稳定UID匹配后可作为黑色转化材料。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card.uid == card_uid:
			return equipment_card
	return null


## 判断一张自有实体牌能否通过罡风转化为本次【杀】响应。
func can_convert_response_card(card: CardInstance, response_patterns: Array[String]) -> bool:
	return card != null and card.get_color() == REQUIRED_COLOR and response_patterns.has("sha")


## 返回罡风响应转化后的雷【杀】定义；提交时条件失效则返回空字符串。
func get_converted_response_definition_id(card: CardInstance, response_patterns: Array[String]) -> String:
	return THUNDER_SLASH_DEFINITION_ID if can_convert_response_card(card, response_patterns) else ""


## 向AI合法动作列表追加每个黑色材料与雷【杀】目标的合法组合。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前全部黑色材料；每张牌需要独立计算其真实颜色下的目标集合。
	var candidates: Array[Dictionary] = _get_black_material_candidates()
	# 材料到合法目标映射；AI只枚举权威预览已经确认的组合。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates)
	# 当前映射字典；字符串UID键与选择请求序列化格式保持一致。
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前材料UID；手牌、木牛“粮”与装备共用同一实体标识。
		var material_card_uid: int = int(candidate.get("uid", -1))
		# 当前材料合法目标；黑色材料不能枚举拥有【琥珀】的角色。
		var material_target_ids: Array = target_ids_by_card_id.get(str(material_card_uid), []) as Array
		for target_id_variant: Variant in material_target_ids:
			# 当前合法目标ID；从序列化数组显式转为整数。
			var target_id: int = int(target_id_variant)
			# 单目标数组；每个AI动作可直接作为权威提交再次复核。
			var target_ids: Array[int] = [target_id]
			# 当前材料实体；最终组合校验继续使用真实颜色，避免候选与提交规则漂移。
			var material_card: CardInstance = _find_owned_material_card(material_card_uid)
			if material_card != null and validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, target_ids).is_empty():
				result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "material_card_uid":material_card_uid, "target_ids":target_ids.duplicate()}})


## 评估罡风主动转化；复用雷【杀】对目标的标准收益并扣除真实材料保留价值。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 技能动作负载；保存材料UID和实际目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 虚拟雷【杀】动作；通用评估器会计算敌我态度、体力、手牌、响应与属性连环传导。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":THUNDER_SLASH_DEFINITION_ID, "target_ids":(action.get("target_ids", payload.get("target_ids", [])) as Array).duplicate()}
	# 雷【杀】基础收益；包含出牌顺序、目标效用和属性伤害。
	var score: float = evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id)
	# 雷【杀】联动技能优先分；疾雨等技能可在自身元数据声明，普通黑色【杀】因此会优先通过罡风转化。
	score += _get_thunder_slash_priority_bonus(authoritative_snapshot, evaluator)
	# 材料牌保留价值；高价值【桃】、【闪】或关键装备不会被低收益攻击轻易消耗。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	return score - material_value * AI_MATERIAL_COST_WEIGHT


## 汇总持有者技能声明的雷【杀】联动优先分；内容扩展可复用同一元数据字段而无需修改罡风源码。
func _get_thunder_slash_priority_bonus(authoritative_snapshot: Dictionary, evaluator: Object) -> float:
	# 技能持有者快照；武将定义决定实际静态技能列表，缺失角色时保持0分。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	# 技能持有者武将定义；领袖技等未声明该字段的技能自然贡献0分。
	var character: Dictionary = GameDatabase.get_character(str(owner.get("character_id", "")))
	# 汇总优先分；多个独立雷【杀】联动可以叠加，全部数值只影响AI选择。
	var result: float = 0.0
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		result += float(GameDatabase.get_skill(str(skill_id_variant)).get(AI_THUNDER_PRIORITY_METADATA_KEY, 0.0))
	return result
