extends SkillDefinition

## 【传冲】技能源码。四种花色分别把一张普通手牌转化为四种指定锦囊牌。

## 花色到虚拟锦囊定义ID的固定映射；顺序与技能原文中的花色及牌名一一对应。
const TRICK_BY_SUIT: Dictionary = {"heart":"shunshou", "diamond":"wuzhong", "spade":"guohe", "club":"jiedao"}

## AI计算材料机会成本时的保留价值权重；默认0.45兼顾锦囊收益与关键手牌保留。
const AI_MATERIAL_COST_WEIGHT: float = 0.45

## 当前出牌阶段是否已经成功发动；普通与额外出牌阶段各自限一次。
var _used_current_play_phase: bool = false


## 写入主动技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"chuanchong",
		"name":"传冲",
		"trigger":"active",
		"enable":["phaseUse"],
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可将一张红桃/方块/黑桃/梅花手牌当【顺手牵羊】/【无中生有】/【过河拆桥】/【借刀杀人】使用。",
	})


## 每个出牌阶段开始时恢复一次发动额度；额外出牌阶段同样派发该时机。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player", 100)


## 清空本阶段发动标记。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_current_play_phase = false


## 仅在自己的出牌阶段、仍有额度且至少存在一个完整合法的材料目标组合时开放技能。
func can_activate(_context: Dictionary = {}) -> bool:
	if host == null or _used_current_play_phase or host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 当前材料与完整目标组合数据；只有至少一张材料能够转化并完整使用时才点亮技能。
	var selection_data: Dictionary = _build_material_target_selection_data()
	return not (selection_data.get("candidates", []) as Array).is_empty()


## 发动传冲；AI可直接携带材料与目标，玩家通过单个牌目标请求完成与【罡风】一致的转化使用。
func activate(context: Dictionary = {}) -> String:
	# 动作指定的材料UID；负数表示需要创建玩家选牌请求。
	var material_uid: int = int(context.get("material_card_uid", -1))
	# 动作指定的目标数组；借刀杀人保留“持刀者、被杀者”的顺序。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if material_uid >= 0 and not target_ids.is_empty():
		return "" if _execute_conversion(material_uid, target_ids) else "【传冲】材料或目标已不合法。"
	# 当前材料与目标组合数据；每张材料独立保存其花色转化后允许的有序目标数组。
	var selection_data: Dictionary = _build_material_target_selection_data()
	# 实际可转化的普通手牌候选；无合法目标的材料不进入本次内联选择，避免玩家选中后没有可指定目标。
	var candidates: Array[Dictionary] = selection_data.get("candidates", []) as Array[Dictionary]
	# 全部材料目标并集；材料尚未选中时供界面预览，选中后由组合映射缩小候选。
	var legal_target_ids: Array[int] = selection_data.get("target_ids", []) as Array[int]
	if candidates.is_empty() or legal_target_ids.is_empty():
		return "当前没有可用于【传冲】的手牌或转化锦囊目标。"
	request_card_target_selection("传冲", "请选择一张手牌，并指定其转化锦囊的目标", candidates, legal_target_ids, 1, 1, 1, 2, true, {"kind":"chuanchong_use", "target_combinations_by_card_id":selection_data.get("target_combinations_by_card_id", {}), "auto_target_ids_by_card_id":selection_data.get("auto_target_ids_by_card_id", {})})
	return ""


## 恢复牌目标组合选择；提交前后的材料仍需留在普通手牌区并保持原花色。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "chuanchong_use":
		if response.confirmed and response.card_ids.size() == 1 and response.target_ids.size() in [1, 2]:
			_execute_conversion(response.card_ids[0], response.target_ids)
		return true
	return false


## 权威复核材料花色与完整目标组合，成功后通过统一虚拟牌入口移动材料并记录次数。
func _execute_conversion(material_uid: int, target_ids: Array[int]) -> bool:
	if _used_current_play_phase:
		return false
	var material: CardInstance = _get_hand_card(material_uid)
	if material == null:
		return false
	var trick_id: String = str(TRICK_BY_SUIT.get(material.suit, ""))
	if trick_id.is_empty() or validate_virtual_use_for_material(trick_id, material, target_ids) != "":
		return false
	var material_uids: Array[int] = [material_uid]
	if not bool(host.call("execute_virtual_card_use", owner_player_id, trick_id, material_uids, target_ids, "")):
		return false
	_used_current_play_phase = true
	announce_activation({"material_card_uid":material_uid, "target_ids":target_ids.duplicate(), "virtual_card_id":trick_id})
	return true


## 返回技能持有者普通手牌候选；四种实体花色均有映射，none虚拟花色会被排除。
func _get_hand_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		var material: CardInstance = _get_hand_card(int(candidate.get("uid", -1)))
		if material != null and TRICK_BY_SUIT.has(material.suit):
			result.append(candidate)
	return result


## 为每张普通手牌计算对应虚拟锦囊的完整目标组合；返回值同时供玩家筛选、AI动作与权威提交复用。
func _build_material_target_selection_data() -> Dictionary:
	# 实际可进入选择的材料候选；没有完整合法使用的手牌不会泄露为可点击入口。
	var valid_candidates: Array[Dictionary] = []
	# 材料UID到有序目标组合的映射；【借刀杀人】保留“持刀者、被杀者”的顺序。
	var target_combinations_by_card_id: Dictionary = {}
	# 全部材料目标并集；材料尚未选中时用于武将牌目标预览。
	var all_target_ids: Array[int] = []
	# 材料UID到自动目标数组的映射；只记录规则已唯一确定的自身目标，不替代权威完整组合校验。
	var auto_target_ids_by_card_id: Dictionary = {}
	for candidate: Dictionary in _get_hand_candidates():
		# 当前普通手牌材料；只有仍在手牌区的实体才能按其真实花色转化。
		var material: CardInstance = _get_hand_card(int(candidate.get("uid", -1)))
		# 当前花色对应的虚拟锦囊定义；无映射花色不会进入正式候选。
		var trick_id: String = str(TRICK_BY_SUIT.get(material.suit, "")) if material != null else ""
		# 当前材料完整合法目标组合；单目标、【无中生有】自身目标与借刀双目标都统一保存为数组。
		var target_combinations: Array = _get_valid_target_combinations(trick_id, material)
		if target_combinations.is_empty():
			continue
		# 当前材料UID；字符串键可在网络序列化后稳定读取。
		var material_uid: int = material.uid
		valid_candidates.append(candidate)
		target_combinations_by_card_id[str(material_uid)] = target_combinations.duplicate(true)
		# 【无中生有】等自身目标虚拟牌不应要求玩家再点击自身；只有定义声明self且唯一合法组合正好为持有者时才预填。
		var virtual_definition: Dictionary = GameDatabase.get_card(trick_id)
		if str(virtual_definition.get("target_mode", "")) == "self" and target_combinations.size() == 1:
			var unique_target_combination: Array = target_combinations[0] as Array
			if unique_target_combination.size() == 1 and int(unique_target_combination[0]) == owner_player_id:
				auto_target_ids_by_card_id[str(material_uid)] = [owner_player_id]
		for target_combination_variant: Variant in target_combinations:
			# 当前有序目标组合；只汇总目标预览，不改变原组合顺序。
			var target_combination: Array = target_combination_variant as Array
			for target_variant: Variant in target_combination:
				# 当前目标ID；去重后保持首次出现顺序，界面选择后仍由完整组合映射收紧。
				var target_id: int = int(target_variant)
				if not all_target_ids.has(target_id):
					all_target_ids.append(target_id)
	return {"candidates":valid_candidates, "target_ids":all_target_ids, "target_combinations_by_card_id":target_combinations_by_card_id, "auto_target_ids_by_card_id":auto_target_ids_by_card_id}


## 按UID返回仍位于技能持有者普通手牌区的实体。
func _get_hand_card(card_uid: int) -> CardInstance:
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner.find_hand_card(card_uid) if owner != null else null


## 枚举指定虚拟锦囊的全部合法完整目标组合；借刀杀人按有序双目标枚举，其余牌保持单目标。
func _get_valid_target_combinations(trick_id: String, material: CardInstance) -> Array:
	var result: Array = []
	if trick_id.is_empty() or material == null:
		return result
	var definition: Dictionary = GameDatabase.get_card(trick_id)
	var required_count: int = int(definition.get("min_targets", 1))
	if required_count == 1:
		for target: PlayerState in host.state.players:
			var target_ids: Array[int] = [target.player_id]
			if validate_virtual_use_for_material(trick_id, material, target_ids).is_empty():
				result.append(target_ids)
		return result
	for first_target: PlayerState in host.state.players:
		for second_target: PlayerState in host.state.players:
			if first_target.player_id == second_target.player_id:
				continue
			var target_ids: Array[int] = [first_target.player_id, second_target.player_id]
			if validate_virtual_use_for_material(trick_id, material, target_ids).is_empty():
				result.append(target_ids)
	return result


## 为AI枚举每张手牌对应锦囊的全部合法目标组合。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for candidate: Dictionary in _get_hand_candidates():
		var material_uid: int = int(candidate.get("uid", -1))
		var material: CardInstance = _get_hand_card(material_uid)
		var trick_id: String = str(TRICK_BY_SUIT.get(material.suit, "")) if material != null else ""
		for target_ids_variant: Variant in _get_valid_target_combinations(trick_id, material):
			var target_ids: Array = target_ids_variant as Array
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "material_card_uid":material_uid, "target_ids":target_ids.duplicate()}})


## 使用对应锦囊的标准牌效估值并扣除材料保留价值，使AI自然选择收益最高的花色分支。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var material_uid: int = int(payload.get("material_card_uid", -1))
	var trick_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	return evaluator.score_action(authoritative_snapshot, trick_action, owner_player_id) - evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, material_uid) * AI_MATERIAL_COST_WEIGHT


## 构造传冲按材料花色实际生成的锦囊代理动作；星火等“使用锦囊”联动由基础AI统一补入。
func build_ai_virtual_card_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> Dictionary:
	# 技能动作负载；保存材料UID和当前花色分支的完整目标数组。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 材料牌快照；花色决定顺手牵羊、无中生有、过河拆桥或借刀杀人。
	var material_data: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	# 实际虚拟锦囊定义ID；异常花色返回空值并由评估器给出0分。
	var trick_id: String = str(TRICK_BY_SUIT.get(str(material_data.get("suit", "")), ""))
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":trick_id, "card_color":str(material_data.get("color", "")), "target_ids":(payload.get("target_ids", []) as Array).duplicate()}
