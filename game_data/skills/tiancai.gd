extends "res://game_data/sequential_virtual_skill_definition.gd"

## 【天裁】技能源码。三个轮回节依次执行无来源火焰自伤、多目标逐张火攻或同目标连续火攻。

## 无来源火焰自伤所在的①轮回节零基索引；固定0对应玩家可见的①。
const SELF_FIRE_DAMAGE_SECTION_INDEX: int = 0

## 至多X名角色各一张火攻所在的②轮回节零基索引；固定1对应玩家可见的②。
const MULTI_FIRE_ATTACK_SECTION_INDEX: int = 1

## 对同一角色依次X-1张火攻所在的③轮回节零基索引；固定2对应玩家可见的③。
const REPEATED_FIRE_ATTACK_SECTION_INDEX: int = 2

## 【火攻】卡牌稳定定义ID；全部视为使用均进入标准卡牌生命周期与响应流程。
const FIRE_ATTACK_DEFINITION_ID: String = "huogong"


## 写入三轮回节主动技能静态信息；技能描述逐字保持主公提供的原文。
func _init() -> void:
	super({
		"id":"tiancai",
		"name":"天裁",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"reincarnation":true,
		"reincarnation_section_count":3,
		"reincarnation_has_explicit_sections":true,
		"description":"轮回技，出牌阶段，你可①受到无伤害来源的X点火焰伤害；②视为对至多X名角色各使用一张【火攻】。③视为对一名角色依次使用X-1张【火攻】。（X为此技能的轮回数）",
	})


## 安装连续虚拟牌结束监听；天裁没有额外被动时机。
func install() -> void:
	install_virtual_card_sequence_listener()


## 按当前轮回节检查阶段、通用轮回额度及火攻合法目标。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or not can_activate_reincarnation():
		return false
	# 当前轮回节与轮回数；③在X=1时使用0张火攻，仍可发动并正常推进轮回。
	var section_index: int = get_reincarnation_section_index()
	if section_index == SELF_FIRE_DAMAGE_SECTION_INDEX:
		return true
	if section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX and get_reincarnation_round_count() <= 1:
		return true
	return not _get_fire_attack_target_ids().is_empty()


## 根据当前轮回节直接执行自伤、读取动作目标或创建目标选择。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "【天裁】当前轮回节没有合法目标或发动条件。"
	# 当前轮回节；决定自伤、多目标火攻或同目标连续火攻分支。
	var section_index: int = get_reincarnation_section_index()
	# 当前轮回数X快照；连续卡牌结束前该数值保持不变。
	var round_count: int = get_reincarnation_round_count()
	if section_index == SELF_FIRE_DAMAGE_SECTION_INDEX:
		return "" if _execute_self_fire_damage(round_count) else "【天裁】的轮回状态已经失效。"
	if section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX and round_count <= 1:
		return "" if _complete_zero_fire_attack_section(round_count) else "【天裁】的轮回状态已经失效。"
	# 已提交目标数组；②允许1至X名，③必须恰好1名。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if not target_ids.is_empty():
		return "" if _execute_fire_attack_section(section_index, round_count, target_ids) else "【天裁】的火攻目标已经失效。"
	# 当前合法火攻目标；要求目标拥有手牌并通过标准来牌限制。
	var legal_target_ids: Array[int] = _get_fire_attack_target_ids()
	if section_index == MULTI_FIRE_ATTACK_SECTION_INDEX:
		request_target_selection("【天裁】请选择火攻目标", legal_target_ids, 1, mini(round_count, legal_target_ids.size()), true, {"kind":"tiancai_targets", "section_index":section_index, "round_count":round_count})
	else:
		request_target_selection("【天裁】请选择连续火攻目标", legal_target_ids, 1, 1, true, {"kind":"tiancai_targets", "section_index":section_index, "round_count":round_count})
	return ""


## 恢复目标选择或连续虚拟牌队列；取消目标选择不推进轮回。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "tiancai_targets" or response == null:
		return false
	if response.confirmed:
		_execute_fire_attack_section(int(context.get("section_index", -1)), int(context.get("round_count", 1)), response.target_ids)
	return true


## 优先处理连续虚拟牌恢复；其他上下文不是天裁结算。
func continue_settlement(context: Dictionary) -> bool:
	return continue_virtual_card_sequence_settlement(context)


## ①受到X点无来源火焰伤害；source_id=-1确保不会触发“造成伤害”的来源技能。
func _execute_self_fire_damage(round_count: int) -> bool:
	if get_reincarnation_section_index() != SELF_FIRE_DAMAGE_SECTION_INDEX or get_reincarnation_round_count() != round_count or not begin_reincarnation_activation():
		return false
	announce_activation({"section_number":SELF_FIRE_DAMAGE_SECTION_INDEX + 1, "round_count":round_count, "fire_damage":round_count, "damage_source_id":-1})
	host.call("damage", -1, owner_player_id, round_count, "fire", get_id())
	complete_reincarnation_activation()
	return true


## ③在X=1时使用X-1即0张火攻；记录一次实际发动并直接推进到下一轮回。
func _complete_zero_fire_attack_section(round_count: int) -> bool:
	if get_reincarnation_section_index() != REPEATED_FIRE_ATTACK_SECTION_INDEX or round_count > 1 or not begin_reincarnation_activation():
		return false
	announce_activation({"section_number":REPEATED_FIRE_ATTACK_SECTION_INDEX + 1, "round_count":round_count, "target_ids":[], "fire_attack_count":0})
	complete_reincarnation_activation()
	return true


## 建立②或③的标准火攻队列；每一张均为独立CardUseEvent并等待上一张完成。
func _execute_fire_attack_section(section_index: int, round_count: int, target_ids: Array[int]) -> bool:
	if section_index != get_reincarnation_section_index() or round_count != get_reincarnation_round_count() or not _validate_section_targets(section_index, round_count, target_ids) or not begin_reincarnation_activation():
		return false
	# 连续火攻条目；②每个目标一张，③同一目标重复X-1张。
	var entries: Array[Dictionary] = []
	if section_index == MULTI_FIRE_ATTACK_SECTION_INDEX:
		for target_id: int in target_ids:
			entries.append(_build_fire_attack_entry(target_id))
	else:
		for _attack_index: int in range(maxi(round_count - 1, 0)):
			entries.append(_build_fire_attack_entry(target_ids[0]))
	# 完成上下文；目标副本供公开发动日志、奇袭目标保持与轮回推进使用。
	var completion_context: Dictionary = {"section_index":section_index, "round_count":round_count, "target_ids":target_ids.duplicate(), "fire_attack_count":entries.size()}
	return start_cardless_virtual_card_sequence(entries, completion_context)


## 连续火攻全部结束或后续目标失效被跳过时，记录整次技能并推进轮回节。
func on_virtual_card_sequence_completed(context: Dictionary) -> void:
	announce_activation({"section_number":int(context.get("section_index", 0)) + 1, "round_count":int(context.get("round_count", 1)), "target_ids":(context.get("target_ids", []) as Array).duplicate(), "fire_attack_count":int(context.get("fire_attack_count", 0))})
	complete_reincarnation_activation()


## 构造一张无材料【火攻】队列条目；目标与标准火攻合法性均由控制器再次复核。
func _build_fire_attack_entry(target_id: int) -> Dictionary:
	return {"actor_id":owner_player_id, "definition_id":FIRE_ATTACK_DEFINITION_ID, "target_ids":[target_id], "rule_overrides":{}, "virtual_storage":{"source_skill_id":get_id()}}


## 复核②目标不重复且数量1至X，③目标唯一；每名目标必须当前可被标准火攻击中。
func _validate_section_targets(section_index: int, round_count: int, target_ids: Array[int]) -> bool:
	# 当前火攻合法目标；目标手牌、存活、离场与技能免疫均已统一过滤。
	var legal_target_ids: Array[int] = _get_fire_attack_target_ids()
	if section_index == MULTI_FIRE_ATTACK_SECTION_INDEX:
		if target_ids.is_empty() or target_ids.size() > round_count:
			return false
		# 已检查目标集合；禁止同一角色在②被重复指定。
		var seen_target_ids: Dictionary = {}
		for target_id: int in target_ids:
			if seen_target_ids.has(target_id) or not legal_target_ids.has(target_id):
				return false
			seen_target_ids[target_id] = true
		return true
	return section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX and target_ids.size() == 1 and legal_target_ids.has(target_ids[0]) and round_count > 1


## 返回当前可成为无材料【火攻】目标的角色；标准目标规则要求其至少有一张手牌。
func _get_fire_attack_target_ids() -> Array[int]:
	return host.card_rules.list_legal_virtual_targets(owner_player_id, FIRE_ATTACK_DEFINITION_ID)


## 为AI枚举①固定动作、②全部合法目标组合与③每名单目标。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 当前轮回节；用于确定AI应枚举无目标、单目标或多目标动作。
	var section_index: int = get_reincarnation_section_index()
	# 当前轮回数X；限制②的目标数与③的火攻张数。
	var round_count: int = get_reincarnation_round_count()
	if section_index == SELF_FIRE_DAMAGE_SECTION_INDEX or section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX and round_count <= 1:
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})
		return
	# 当前合法目标；②组合上限为X，③逐一枚举唯一目标。
	var legal_target_ids: Array[int] = _get_fire_attack_target_ids()
	if section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX:
		for target_id: int in legal_target_ids:
			result.append(_make_skill_action([target_id]))
		return
	# ②全部非空组合；最多10人桌面时组合总量有明确上界，不会造成不可控动作膨胀。
	var combinations: Array[Array] = []
	_append_target_combinations(legal_target_ids, 0, mini(round_count, legal_target_ids.size()), [], combinations)
	for target_ids: Array in combinations:
		result.append(_make_skill_action(_int_array(target_ids)))


## 递归生成至多max_count名目标的全部非空组合；只按座次递增选择，因此不会产生排列重复。
func _append_target_combinations(source_ids: Array[int], start_index: int, max_count: int, current: Array[int], result: Array[Array]) -> void:
	if not current.is_empty():
		result.append(current.duplicate())
	if current.size() >= max_count:
		return
	for source_index: int in range(start_index, source_ids.size()):
		current.append(source_ids[source_index])
		_append_target_combinations(source_ids, source_index + 1, max_count, current, result)
		current.pop_back()


## 构造一条带目标的天裁AI动作；顶层与payload同时保存目标以兼容评分入口。
func _make_skill_action(target_ids: Array[int]) -> Dictionary:
	return {"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "target_ids":target_ids.duplicate()}}


## AI按标准【火攻】价值评估②/③，并把①无来源自伤作为体力成本同时保留轮回推进小额收益。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 当前轮回节；评分只读取快照，不提交任何虚拟牌。
	var section_index: int = get_reincarnation_section_index()
	# 动作中的目标数组；优先读顶层字段，缺失时兼容payload中的权威副本。
	var target_ids: Array = action.get("target_ids", (action.get("payload", {}) as Dictionary).get("target_ids", [])) as Array
	if section_index == SELF_FIRE_DAMAGE_SECTION_INDEX:
		return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, 0, -get_reincarnation_round_count()) + 2.0
	if section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX and get_reincarnation_round_count() <= 1:
		return 1.0
	# 标准火攻动作基础值；②各目标各算一张，③对同一目标乘以X-1次。
	var score: float = 0.0
	for target_id_variant: Variant in target_ids:
		# 单张无色虚拟火攻动作；通用评估器负责敌我、手牌、属性伤害与技能联动。
		var fire_attack_action: Dictionary = {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":FIRE_ATTACK_DEFINITION_ID, "card_color":"none", "target_ids":[int(target_id_variant)]}
		score += evaluator.score_action(authoritative_snapshot, fire_attack_action, owner_player_id)
	if section_index == REPEATED_FIRE_ATTACK_SECTION_INDEX:
		score *= float(maxi(get_reincarnation_round_count() - 1, 0))
	return score + 1.0


## 把弱类型数组收敛为整数数组；动作、网络与回放输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序供②座次规范化与③单目标复核。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result
