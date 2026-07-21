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


## 仅在自己的出牌阶段、仍有额度且至少存在一个合法材料目标组合时开放技能。
func can_activate(_context: Dictionary = {}) -> bool:
	if host == null or _used_current_play_phase or host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	for candidate: Dictionary in _get_hand_candidates():
		# 当前材料实体与其花色对应锦囊；未知花色不会进入正式候选。
		var material: CardInstance = _get_hand_card(int(candidate.get("uid", -1)))
		if material != null and not _get_valid_target_combinations(str(TRICK_BY_SUIT.get(material.suit, "")), material).is_empty():
			return true
	return false


## 发动传冲；AI可直接携带材料与目标，玩家先选材料再进入对应锦囊的目标选择。
func activate(context: Dictionary = {}) -> String:
	# 动作指定的材料UID；负数表示需要创建玩家选牌请求。
	var material_uid: int = int(context.get("material_card_uid", -1))
	# 动作指定的目标数组；借刀杀人保留“持刀者、被杀者”的顺序。
	var target_ids: Array[int] = []
	for target_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_variant))
	if material_uid >= 0 and not target_ids.is_empty():
		return "" if _execute_conversion(material_uid, target_ids) else "【传冲】材料或目标已不合法。"
	var candidates: Array[Dictionary] = _get_hand_candidates()
	if candidates.is_empty():
		return "当前没有可用于【传冲】的手牌。"
	request_card_selection("传冲", "请选择一张手牌", candidates, 1, 1, true, {"kind":"chuanchong_material"})
	return ""


## 恢复材料或目标选择；材料等待期间仍需留在普通手牌区并保持原花色。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "chuanchong_material":
		if not response.confirmed or response.card_ids.size() != 1:
			return true
		var material: CardInstance = _get_hand_card(response.card_ids[0])
		var trick_id: String = str(TRICK_BY_SUIT.get(material.suit, "")) if material != null else ""
		var combinations: Array = _get_valid_target_combinations(trick_id, material)
		if combinations.is_empty():
			return true
		var target_candidates: Array[int] = []
		for combination_variant: Variant in combinations:
			for target_variant: Variant in combination_variant as Array:
				var target_id: int = int(target_variant)
				if not target_candidates.has(target_id):
					target_candidates.append(target_id)
		var required_count: int = (combinations[0] as Array).size()
		request_target_selection("【传冲】请选择目标", target_candidates, required_count, required_count, true, {"kind":"chuanchong_targets", "material_card_uid":material.uid, "valid_target_combinations":combinations})
		return true
	if choice_kind == "chuanchong_targets":
		if response.confirmed:
			_execute_conversion(int(context.get("material_card_uid", -1)), response.target_ids)
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
	var material_data: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, material_uid)
	var trick_id: String = str(TRICK_BY_SUIT.get(str(material_data.get("suit", "")), ""))
	var trick_action: Dictionary = {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":trick_id, "target_ids":(payload.get("target_ids", []) as Array).duplicate()}
	return evaluator.score_action(authoritative_snapshot, trick_action, owner_player_id) - evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, material_uid) * AI_MATERIAL_COST_WEIGHT
