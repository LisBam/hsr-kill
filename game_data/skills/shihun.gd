extends "res://game_data/sequential_virtual_skill_definition.gd"

## 【弑魂】技能源码。①令所选其他角色依次对持有者使用火【杀】，②由持有者以一张火【杀】固定反击上次所选目标。

## 其他角色依次对持有者使用火【杀】所在的①轮回节零基索引。
const INCOMING_FIRE_SLASH_SECTION_INDEX: int = 0

## 持有者反击上次目标所在的②轮回节零基索引。
const RETALIATION_FIRE_SLASH_SECTION_INDEX: int = 1

## 火【杀】稳定定义ID；普通与多目标反击均进入标准【杀】响应和伤害流程。
const FIRE_SLASH_DEFINITION_ID: String = "sha_fire"

## 上一次实际发动弑魂所指定的目标ID；默认空数组，①完成后保存，②使用时目标保持不变。
var _last_selected_target_ids: Array[int] = []


## 写入两轮回节主动技能静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"shihun",
		"name":"弑魂",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"reincarnation":true,
		"reincarnation_section_count":2,
		"reincarnation_has_explicit_sections":true,
		"description":"轮回技，出牌阶段，你可①令任意名其他角色依次视为对你使用一张火【杀】；②视为使用一张目标为上次发动此技能所指定目标的火【杀】。",
	})


## 安装连续虚拟牌结束监听；弑魂没有额外被动时机。
func install() -> void:
	install_virtual_card_sequence_listener()


## 按当前轮回节检查阶段、通用额度与固定火【杀】目标组合是否合法。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or not can_activate_reincarnation():
		return false
	if get_reincarnation_section_index() == INCOMING_FIRE_SLASH_SECTION_INDEX:
		return not _get_incoming_slash_actor_ids().is_empty()
	return _is_retaliation_target_set_legal(_last_selected_target_ids)


## ①读取动作目标或创建任意多目标选择，②直接按上次目标执行固定反击。
func activate(context: Dictionary = {}) -> String:
	if not can_activate():
		return "【弑魂】当前轮回节没有合法的火【杀】角色或固定目标。"
	# 当前轮回节；①动作可携带目标，②不允许改写上次目标集合。
	var section_index: int = get_reincarnation_section_index()
	if section_index == RETALIATION_FIRE_SLASH_SECTION_INDEX:
		return "" if _start_shihun_sequence(section_index, _last_selected_target_ids) else "【弑魂】上次指定目标已不合法。"
	# 已提交①目标；奇袭额外发动会沿用原目标数组。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if not target_ids.is_empty():
		return "" if _start_shihun_sequence(section_index, target_ids) else "【弑魂】所选使用者已经失效。"
	# 可令其视为用火杀的其他角色；直接效果忽略其当前阶段、次数与距离限制。
	var actor_ids: Array[int] = _get_incoming_slash_actor_ids()
	request_target_selection("【弑魂】请选择火杀使用者", actor_ids, 1, actor_ids.size(), true, {"kind":"shihun_incoming_actors"})
	return ""


## 恢复①任意多目标选择；取消不建立队列也不推进轮回。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "shihun_incoming_actors" or response == null:
		return false
	if response.confirmed and not response.target_ids.is_empty():
		_start_shihun_sequence(INCOMING_FIRE_SLASH_SECTION_INDEX, response.target_ids)
	return true


## 优先处理连续虚拟牌恢复；其他上下文不是弑魂结算。
func continue_settlement(context: Dictionary) -> bool:
	return continue_virtual_card_sequence_settlement(context)


## 根据轮回节建立①多张独立火【杀】或②一张固定多目标火【杀】。
func _start_shihun_sequence(section_index: int, target_ids: Array[int]) -> bool:
	if section_index != get_reincarnation_section_index() or not _validate_section_targets(section_index, target_ids) or not begin_reincarnation_activation():
		return false
	# 连续虚拟牌队列；①每名所选角色分别作为使用者，②由持有者使用单张多目标火杀。
	var entries: Array[Dictionary] = []
	if section_index == INCOMING_FIRE_SLASH_SECTION_INDEX:
		for actor_id: int in target_ids:
			entries.append({
				"actor_id":actor_id,
				"definition_id":FIRE_SLASH_DEFINITION_ID,
				"target_ids":[owner_player_id],
				"rule_overrides":{"ignore_phase_limit":true, "ignore_play_count_limit":true, "ignore_distance_limit":true},
				"virtual_storage":{"source_skill_id":get_id(), "shihun_section":section_index},
			})
	else:
		entries.append({
			"actor_id":owner_player_id,
			"definition_id":FIRE_SLASH_DEFINITION_ID,
			"target_ids":target_ids.duplicate(),
			"rule_overrides":{"maximum_target_count_bonus":maxi(target_ids.size() - 1, 0)},
			"virtual_storage":{"source_skill_id":get_id(), "shihun_section":section_index},
		})
	# 完成上下文；无论个别卡牌随后因状态变化跳过，整次技能仍按最初合法指定推进。
	var completion_context: Dictionary = {"section_index":section_index, "round_count":get_reincarnation_round_count(), "target_ids":target_ids.duplicate(), "virtual_card_count":entries.size()}
	return start_cardless_virtual_card_sequence(entries, completion_context)


## 连续火【杀】全部结束后保存上次目标、记录整次发动并推进轮回节。
func on_virtual_card_sequence_completed(context: Dictionary) -> void:
	# 实际指定目标副本；①保存使用者，②保持同一固定集合供下一次记录与奇袭重放。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	_last_selected_target_ids = target_ids.duplicate()
	announce_activation({"section_number":int(context.get("section_index", 0)) + 1, "round_count":int(context.get("round_count", 1)), "target_ids":target_ids.duplicate(), "virtual_card_count":int(context.get("virtual_card_count", 0))})
	complete_reincarnation_activation()


## 复核①使用者互不重复且仍可对持有者视为用火杀，或②目标完全等于上次集合并通过标准火杀规则。
func _validate_section_targets(section_index: int, target_ids: Array[int]) -> bool:
	if section_index == INCOMING_FIRE_SLASH_SECTION_INDEX:
		if target_ids.is_empty():
			return false
		# 当前合法使用者集合；忽略阶段、次数与距离，但仍复核存活、离场及目标技能限制。
		var legal_actor_ids: Array[int] = _get_incoming_slash_actor_ids()
		# 已遍历使用者集合；键为稳定玩家ID，用于拒绝同一角色被重复指定。
		var seen_actor_ids: Dictionary = {}
		for actor_id: int in target_ids:
			if seen_actor_ids.has(actor_id) or not legal_actor_ids.has(actor_id):
				return false
			seen_actor_ids[actor_id] = true
		return true
	return section_index == RETALIATION_FIRE_SLASH_SECTION_INDEX and target_ids == _last_selected_target_ids and _is_retaliation_target_set_legal(target_ids)


## 返回当前可被①指定的其他角色；每名角色均以忽略阶段、次数与距离的无材料火杀单独复核。
func _get_incoming_slash_actor_ids() -> Array[int]:
	# 合法使用者结果；保持权威座次顺序，结算也依照所选顺序逐张执行。
	var result: Array[int] = []
	# ①专属覆写；“令其视为使用”不要求处于其出牌阶段，也不受其本阶段杀次数或到持有者距离阻挡。
	var rule_overrides: Dictionary = {"ignore_phase_limit":true, "ignore_play_count_limit":true, "ignore_distance_limit":true}
	# 火【杀】固定目标；显式收窄为整数数组，与卡牌规则服务的强类型参数保持一致。
	var owner_target_ids: Array[int] = [owner_player_id]
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game and host.card_rules.validate_virtual_use(player.player_id, FIRE_SLASH_DEFINITION_ID, owner_target_ids, rule_overrides).is_empty():
			result.append(player.player_id)
	return result


## 判断②的固定目标集合能否作为持有者本阶段一张标准多目标火【杀】使用。
func _is_retaliation_target_set_legal(target_ids: Array[int]) -> bool:
	if target_ids.is_empty():
		return false
	# 多目标上限加成；只扩展目标数量，不解除阶段次数、距离或目标技能限制。
	var rule_overrides: Dictionary = {"maximum_target_count_bonus":maxi(target_ids.size() - 1, 0)}
	return host.card_rules.validate_virtual_use(owner_player_id, FIRE_SLASH_DEFINITION_ID, target_ids, rule_overrides).is_empty()


## 为AI枚举①全部非空使用者组合；②固定目标仅产生一条动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	if get_reincarnation_section_index() == RETALIATION_FIRE_SLASH_SECTION_INDEX:
		result.append(_make_skill_action(_last_selected_target_ids))
		return
	# ①合法使用者；全部非空组合允许AI在承受伤害风险与后续反击收益间选择人数。
	var actor_ids: Array[int] = _get_incoming_slash_actor_ids()
	# ①的全部非空使用者组合；默认空数组，递归枚举后转换为AI动作。
	var combinations: Array = []
	_append_actor_combinations(actor_ids, 0, [], combinations)
	for combination_variant: Variant in combinations:
		result.append(_make_skill_action(_int_array(combination_variant as Array)))


## 递归生成①使用者的全部非空组合；只按座次递增选择以避免排列重复。
func _append_actor_combinations(source_ids: Array[int], start_index: int, current: Array[int], result: Array) -> void:
	if not current.is_empty():
		result.append(current.duplicate())
	for source_index: int in range(start_index, source_ids.size()):
		current.append(source_ids[source_index])
		_append_actor_combinations(source_ids, source_index + 1, current, result)
		current.pop_back()


## 构造一条弑魂AI动作；顶层与payload同时保存目标，便于统一身份和资源评分读取。
func _make_skill_action(target_ids: Array[int]) -> Dictionary:
	return {"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "target_ids":target_ids.duplicate()}}


## AI在①综合自身可能承受的火杀风险与下节反击价值，②按标准火杀逐目标收益评分。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作目标；①表示火杀使用者，②表示固定反击目标。
	var target_ids: Array = action.get("target_ids", (action.get("payload", {}) as Dictionary).get("target_ids", [])) as Array
	if target_ids.is_empty():
		return -100.0
	# 评分结果；①每多一名使用者增加自身风险，但敌方会成为下轮反击目标。
	var score: float = 0.0
	if get_reincarnation_section_index() == INCOMING_FIRE_SLASH_SECTION_INDEX:
		for target_id_variant: Variant in target_ids:
			# 当前使用者；敌对目标的后续反击价值抵消部分当前风险，友方不会被无脑拉入伤害链。
			var target_id: int = int(target_id_variant)
			score -= 4.0
			score -= evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) * 0.8
		return score + 2.0
	for target_id_variant: Variant in target_ids:
		score += evaluator.score_resource_change(authoritative_snapshot, owner_player_id, int(target_id_variant), 0, -1)
	return score + 2.0


## 把弱类型数组收敛为整数数组；动作、网络与回放输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留所选座次顺序供①连续结算与②固定目标使用。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result
