extends SkillDefinition

## 【全垒】技能源码。出牌阶段限一次，将一张普通手牌当最多两个目标的雷【杀】使用。

## 全垒生成的雷【杀】定义ID；单材料虚拟牌继承手牌花色与点数。
const THUNDER_SLASH_DEFINITION_ID: String = "sha_thunder"

## 全垒令雷【杀】基础目标上限增加1；基础1名目标因此最多指定2名。
const VIRTUAL_RULE_OVERRIDES: Dictionary = {"maximum_target_count_bonus":1}

## AI消耗材料保留价值的扣分权重；默认0.45平衡多目标进攻与关键牌保留。
const AI_MATERIAL_COST_WEIGHT: float = 0.45

## AI使用【杀】牌族作为材料且同时指定2名正收益目标时的额外奖励；固定4.0分确保目标数+1的技能优势不会被单目标实体【杀】评分覆盖。
const AI_SLASH_MATERIAL_MULTI_TARGET_BONUS: float = 4.0

## 当前出牌阶段是否已经成功发动；phaseUseBegin重置，使普通与额外出牌阶段分别拥有1次额度。
var _used_current_play_phase: bool = false


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id": "quanlei",
		"name": "全垒",
		"trigger": "active",
		"enable": ["phaseUse"],
		"ui_enabled": true,
		"description": "出牌阶段限一次，你可将一张手牌当目标上限+1的雷【杀】使用。",
	})


## 安装每个出牌阶段的次数重置；额外出牌阶段同样派发phaseUseBegin。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player", 100)


## 新的普通或额外出牌阶段开始时恢复1次发动额度。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_current_play_phase = false


## 仅在自己的出牌阶段、当前阶段未发动且存在手牌与合法雷【杀】目标时开放技能。
func can_activate(_context: Dictionary = {}) -> bool:
	if host == null or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or _used_current_play_phase:
		return false
	# 当前普通手牌材料；每张材料的真实颜色都必须参与雷【杀】目标免疫判断。
	var candidates: Array[Dictionary] = _get_hand_candidates()
	if candidates.is_empty():
		return false
	# 材料与目标组合数据；目标预览不校验次数，因此下方必须再走完整校验。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 逐材料合法目标映射；键为材料UID字符串。
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前材料UID；仅普通手牌可作全垒材料。
		var material_card_uid: int = int(candidate.get("uid", -1))
		# 当前材料实体；找不到时跳过，避免候选快照与权威区域短暂不一致。
		var material_card: CardInstance = get_owned_conversion_material_card(material_card_uid)
		if material_card == null:
			continue
		# 当前材料合法目标；至少一组合法完整虚拟使用时按钮才亮起。
		var legal_target_ids: Array[int] = []
		legal_target_ids.assign(target_ids_by_card_id.get(str(material_card_uid), []) as Array)
		for first_index: int in range(legal_target_ids.size()):
			# 当前首目标；单目标组合先完整校验阶段【杀】次数与目标规则。
			var first_target_id: int = legal_target_ids[first_index]
			if validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, [first_target_id], VIRTUAL_RULE_OVERRIDES).is_empty():
				return true
			for second_index: int in range(first_index + 1, legal_target_ids.size()):
				# 当前双目标组合；目标上限+1 时也必须通过同一套完整校验。
				var combined_target_ids: Array[int] = [first_target_id, legal_target_ids[second_index]]
				if validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, combined_target_ids, VIRTUAL_RULE_OVERRIDES).is_empty():
					return true
	return false


## 主动发动全垒；允许选择1至2名不同目标，AI动作可直接携带材料与目标数组。
func activate(context: Dictionary = {}) -> String:
	# 动作指定材料UID；负数表示玩家尚未选择普通手牌。
	var material_card_uid: int = int(context.get("material_card_uid", -1))
	# 动作指定目标数组；合法数量为1至2。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if material_card_uid >= 0 and target_ids.size() in [1, 2]:
		return "" if _execute_conversion(material_card_uid, target_ids) else "【全垒】材料或目标已不合法。"
	# 普通手牌候选；木牛“粮”和装备牌不满足原文“一张手牌”。
	var candidates: Array[Dictionary] = _get_hand_candidates()
	# 基础单目标合法候选；组合提交时由完整虚拟牌校验复核目标数与重复目标。
	# 材料与目标组合数据；不同颜色材料可以拥有不同的合法目标集合。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 基础单目标合法候选并集；组合提交时由完整虚拟牌校验复核目标数、重复目标与材料颜色。
	var legal_target_ids: Array[int] = []
	legal_target_ids.assign(selection_data.get("target_ids", []) as Array)
	if candidates.is_empty() or legal_target_ids.is_empty():
		return "当前没有可用的手牌或雷【杀】目标。"
	request_card_target_selection("全垒", "请选择一张手牌和一至两名雷【杀】目标", candidates, legal_target_ids, 1, 1, 1, 2, true, {"kind":"quanlei_use", "target_ids_by_card_id":selection_data.get("target_ids_by_card_id", {})})
	return ""


## 恢复全垒的牌与目标组合选择；取消不消耗本阶段额度。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "quanlei_use" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 1 and response.target_ids.size() in [1, 2]:
		_execute_conversion(response.card_ids[0], response.target_ids)
	return true


## 权威复核普通手牌材料与多目标雷【杀】组合，成功后记录当前出牌阶段次数。
func _execute_conversion(material_card_uid: int, target_ids: Array[int]) -> bool:
	if _used_current_play_phase:
		return false
	# 技能持有者；材料必须仍位于普通手牌区。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 当前材料实体；同时用于区域校验和目标免疫所需的真实颜色。
	var material_card: CardInstance = owner.find_hand_card(material_card_uid) if owner != null else null
	if material_card == null:
		return false
	# 本次规则覆写；复制常量后补充材料颜色，避免污染后续候选查询。
	# 深复制与真实颜色注入由技能基类完成，技能常量仍保持只读。
	if validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, target_ids, VIRTUAL_RULE_OVERRIDES) != "":
		return false
	# 单材料数组；用于控制器统一移动、回放和最终弃牌。
	var material_card_uids: Array[int] = [material_card_uid]
	if not bool(host.call("execute_virtual_card_use", owner_player_id, THUNDER_SLASH_DEFINITION_ID, material_card_uids, target_ids, "", VIRTUAL_RULE_OVERRIDES)):
		return false
	_used_current_play_phase = true
	announce_activation({"material_card_uid":material_card_uid, "target_ids":target_ids.duplicate(), "virtual_card_id":THUNDER_SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":-1.5, "damage":true, "respond_shan":true, "nature_damage":true})
	return true


## 返回技能持有者普通手牌区的公开自选候选。
func _get_hand_candidates() -> Array[Dictionary]:
	return host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]


## 返回当前雷【杀】的全部基础合法目标；目标数量加成只影响最终组合上限。
func _get_legal_target_ids() -> Array[int]:
	# 当前全部普通手牌；合法目标返回各材料真实颜色规则下的并集。
	var candidates: Array[Dictionary] = _get_hand_candidates()
	# 当前材料选择数据；保留本函数兼容现有调用方，具体组合仍应读取映射。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 当前目标并集；显式复制为强类型整数数组。
	var target_ids: Array[int] = []
	target_ids.assign(selection_data.get("target_ids", []) as Array)
	return target_ids


## 为AI枚举每张手牌的全部单目标与不重复双目标组合。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前合法目标；双目标组合按稳定座次顺序枚举，避免重复排列。
	# 每张材料拥有独立合法目标数组，数组内部继续按规则服务的稳定座次顺序枚举。
	# 当前普通手牌材料；AI需要逐材料枚举其真实颜色允许的目标。
	var candidates: Array[Dictionary] = _get_hand_candidates()
	# 材料到目标映射；黑色材料不会包含受【琥珀】保护的角色，红色材料仍可正常选择。
	var selection_data: Dictionary = build_virtual_target_selection_data(THUNDER_SLASH_DEFINITION_ID, candidates, VIRTUAL_RULE_OVERRIDES)
	# 当前序列化映射；键为材料UID字符串。
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前手牌材料UID；每个组合都携带同一稳定材料引用。
		var material_card_uid: int = int(candidate.get("uid", -1))
		# 当前材料实体；用于最终单目标或双目标完整校验。
		var material_card: CardInstance = get_owned_conversion_material_card(material_card_uid)
		# 当前材料合法目标；双目标组合只从该集合按稳定索引枚举。
		var legal_target_ids: Array[int] = []
		legal_target_ids.assign(target_ids_by_card_id.get(str(material_card_uid), []) as Array)
		for first_index: int in range(legal_target_ids.size()):
			# 当前首目标；始终追加合法单目标动作。
			var first_target_id: int = legal_target_ids[first_index]
			if material_card != null and validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, [first_target_id], VIRTUAL_RULE_OVERRIDES).is_empty():
				_append_ai_action(result, material_card_uid, [first_target_id])
			for second_index: int in range(first_index + 1, legal_target_ids.size()):
				# 当前次目标；索引严格递增保证同一目标集合只出现一次。
				var second_target_id: int = legal_target_ids[second_index]
				# 当前双目标组合；必须再次经过目标数量、技能免疫与组合规则复核。
				var combined_target_ids: Array[int] = [first_target_id, second_target_id]
				if material_card != null and validate_virtual_use_for_material(THUNDER_SLASH_DEFINITION_ID, material_card, combined_target_ids, VIRTUAL_RULE_OVERRIDES).is_empty():
					_append_ai_action(result, material_card_uid, combined_target_ids)


## 追加一条已经枚举完成的AI技能动作。
func _append_ai_action(result: Array[Dictionary], material_card_uid: int, target_ids: Array[int]) -> void:
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "material_card_uid":material_card_uid, "target_ids":target_ids.duplicate()}})


## 累加每名雷【杀】目标的标准收益，并扣除材料牌价值，使AI仅在组合总收益为正时使用。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 技能动作负载；保存材料UID和目标集合。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 目标集合；多目标雷【杀】对每名角色独立结算1点雷属性伤害。
	var target_ids: Array = action.get("target_ids", payload.get("target_ids", [])) as Array
	# 材料牌快照；只读副本用于查询牌族和真实颜色，不参与规则状态修改。
	var material_card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	# 材料牌定义；通过effect_id识别普通、火和雷【杀】共享的slash牌族。
	var material_definition: Dictionary = GameDatabase.get_card(str(material_card.get("definition_id", "")))
	# 组合总收益；逐目标复用通用雷【杀】评估，包含闪、横置与防具预期。
	var score: float = 0.0
	# 全部目标是否均具有严格正收益；只有不会为了触发奖励而误伤友方时才优先【杀】材料双目标动作。
	var all_targets_profitable: bool = not target_ids.is_empty()
	for target_id_variant: Variant in target_ids:
		# 单目标代理动作；避免通用单目标卡牌评估器忽略第二名角色。
		var slash_action: Dictionary = {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":THUNDER_SLASH_DEFINITION_ID, "card_color":str(material_card.get("color", "")), "target_ids":[int(target_id_variant)]}
		# 当前目标收益；与总分分开保存，用于禁止双目标奖励掩盖负收益目标。
		var target_score: float = evaluator.score_action(authoritative_snapshot, slash_action, owner_player_id)
		score += target_score
		if target_score <= 0.0:
			all_targets_profitable = false
	# 材料牌保留价值；优先把低价值手牌转化为多目标进攻。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	if target_ids.size() == 2 and all_targets_profitable and str(material_definition.get("effect_id", "")) == "slash":
		score += AI_SLASH_MATERIAL_MULTI_TARGET_BONUS
	return score - material_value * AI_MATERIAL_COST_WEIGHT
