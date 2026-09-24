extends SkillDefinition

## 【鸣弦】技能源码。出牌阶段限一次，为距离1以内的任意名角色分别检索一张【杀】，并赋予离手即失效的无距离手牌标记。

## 鸣弦检索的规则效果ID；普通、火与雷【杀】均通过slash效果族统一命中。
const SLASH_EFFECT_ID: String = "slash"

## 鸣弦手牌标记的稳定ID；同一张牌重复写入时只更新该标签，不会产生重复UI。
const HAND_MARK_TAG_ID: String = "mingxian"

## 鸣弦手牌标记的显示正文；全角书名号样式严格保持设计文本。
const HAND_MARK_TAG_LABEL: String = "【鸣弦】"

## 鸣弦标签在多标签行中的排序值；默认100，让既有视为标签先显示、技能标记随后显示。
const HAND_MARK_TAG_ORDER: int = 100

## AI把每名友方获得一张【杀】视作的基础资源价值；默认1.0分，严格等价一张牌。
const AI_SLASH_GAIN_VALUE: float = 1.0

## 当前出牌阶段是否已经成功发动；每次phaseUseBegin重置，额外出牌阶段独立计算。
var _used_this_play_phase: bool = false


## 写入主动技能静态信息；技能正文逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"mingxian",
		"name":"鸣弦",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可令任意名与你距离为1以内的角色从牌堆中各获得一张【杀】，这些【杀】无距离限制直到离开其手牌区。",
	})


## 订阅持有者每个出牌阶段的开始时机；额外出牌阶段会重新获得一次鸣弦次数。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_play_phase_begin, "player")


## 新出牌阶段开始时重置限一次记录。
func _on_play_phase_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 判断当前出牌阶段尚未发动、牌堆至少有一张【杀】且至少存在一名距离1以内角色。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段时不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and _count_slashes_in_draw_pile() > 0 and not _get_eligible_target_ids().is_empty()


## 发动鸣弦；网络与AI动作可直接携带完整目标数组，本地按钮则打开可多选的目标确认。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标ID；任意名至少包含1名，重复和越权目标由最终执行入口统一拒绝。
	var target_ids: Array[int] = []
	for target_id_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_id_variant))
	if not target_ids.is_empty():
		return "" if _execute_mingxian(target_ids) else "【鸣弦】目标、距离、牌堆【杀】数量或阶段次数已经失效。"
	# 合法目标ID；包含持有者自己以及当前距离1以内的其他存活在场角色。
	var eligible_target_ids: Array[int] = _get_eligible_target_ids()
	# 当前可确保分配的最大人数；每名目标都必须实际取得一张【杀】。
	var maximum_target_count: int = mini(eligible_target_ids.size(), _count_slashes_in_draw_pile())
	if maximum_target_count <= 0:
		return "当前没有可通过【鸣弦】获得的【杀】。"
	request_target_selection("【鸣弦】请选择获得【杀】的角色", eligible_target_ids, 1, maximum_target_count, true, {"kind":"mingxian_targets"})
	return ""


## 恢复鸣弦目标多选；取消不会消耗本出牌阶段次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "mingxian_targets" or response == null:
		return false
	if response.confirmed and not response.target_ids.is_empty():
		_execute_mingxian(response.target_ids)
	return true


## 最终复核目标后按行动顺序逐名获得【杀】并写入鸣弦标签；技能次数在首张牌移动前锁定，避免嵌套时机重复发动。
func _execute_mingxian(target_ids: Array[int]) -> bool:
	if _used_this_play_phase or target_ids.is_empty() or target_ids.size() > _count_slashes_in_draw_pile():
		return false
	# 当前合法目标集合；等待选择期间距离或存活状态变化会令旧目标失效。
	var eligible_target_ids: Array[int] = _get_eligible_target_ids()
	# 已提交目标集合；禁止重复目标，否则同一角色会错误获得多张牌。
	var unique_target_ids: Dictionary = {}
	for target_id: int in target_ids:
		if unique_target_ids.has(target_id) or not eligible_target_ids.has(target_id):
			return false
		unique_target_ids[target_id] = true
	_used_this_play_phase = true
	# 成功获得牌的目标ID；移动被其他规则取消时不会把未获得者写入发动收益记录。
	var gained_target_ids: Array[int] = []
	# 成功获得并被标记的实体UID；公开技能日志可据此关联移牌与后续离手清理。
	var gained_card_uids: Array[int] = []
	for ordered_player: PlayerState in host.call("get_alive_players_in_action_order", owner_player_id) as Array[PlayerState]:
		if not unique_target_ids.has(ordered_player.player_id):
			continue
		# 目标获得的最顶端【杀】实体；每次移动后重新检索，确保不同目标不会取得同一张牌。
		var gained_card: CardInstance = host.call("gain_top_draw_card_matching", ordered_player.player_id, {"effect_id":SLASH_EFFECT_ID}, get_id()) as CardInstance
		if gained_card == null:
			continue
		# 手牌标签数据；rule_overrides由卡牌规则服务读取，UI只消费label、order与source_skill_id。
		var tag_data: Dictionary = {
			"label":HAND_MARK_TAG_LABEL,
			"order":HAND_MARK_TAG_ORDER,
			"source_skill_id":get_id(),
			"rule_overrides":{"ignore_distance_limit":true},
		}
		if bool(host.call("set_hand_card_mark_tag", ordered_player.player_id, gained_card.uid, HAND_MARK_TAG_ID, tag_data)):
			gained_target_ids.append(ordered_player.player_id)
			gained_card_uids.append(gained_card.uid)
	announce_activation({"target_ids":target_ids.duplicate(), "gained_target_ids":gained_target_ids, "gained_card_uids":gained_card_uids, "hand_mark_tag":HAND_MARK_TAG_LABEL})
	observe_identity_behavior(gained_target_ids, {"target_result":AI_SLASH_GAIN_VALUE})
	return true


## 返回持有者当前距离1以内的全部存活在场角色；自身距离为0，符合“距离为1以内”。
func _get_eligible_target_ids() -> Array[int]:
	# 合法目标结果；按权威座次排列，选择UI和AI共享相同顺序。
	var result: Array[int] = []
	if host == null or host.get("state") == null or host.get("card_rules") == null:
		return result
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game and host.card_rules.calculate_distance(owner_player_id, player.player_id) <= 1:
			result.append(player.player_id)
	return result


## 统计摸牌堆中仍可被鸣弦检索的【杀】数量；属性【杀】与普通【杀】都按slash效果族计算。
func _count_slashes_in_draw_pile() -> int:
	# 可用【杀】数量；摸牌堆为空或控制器尚未绑定时保持0。
	var result: int = 0
	if host == null or host.get("state") == null:
		return result
	for card: CardInstance in host.state.draw_pile:
		# 当前卡牌定义；effect_id统一表达普通与属性【杀】共享的规则族。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if str(definition.get("effect_id", "")) == SLASH_EFFECT_ID:
			result += 1
	return result


## 为AI枚举鸣弦允许的全部非空目标组合；通用评分会让获得牌的自己和友方形成正收益、敌方形成负收益。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	# 合法目标ID；包含自己和距离1以内的其他角色。
	var eligible_target_ids: Array[int] = _get_eligible_target_ids()
	# 最多选择人数；牌堆【杀】不足时不枚举无法完整结算的组合。
	var maximum_target_count: int = mini(eligible_target_ids.size(), _count_slashes_in_draw_pile())
	# 所有非空组合；当前人数上限沿用对局人数上限，组合数量可控。
	var target_combinations: Array[Array] = []
	_append_target_combinations(eligible_target_ids, maximum_target_count, 0, [], target_combinations)
	for target_combination: Array in target_combinations:
		# 强类型目标副本；AI动作与权威技能入口共享target_ids协议。
		var target_ids: Array[int] = []
		for target_id_variant: Variant in target_combination:
			target_ids.append(int(target_id_variant))
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids, "payload":{"skill_id":get_id(), "target_ids":target_ids.duplicate()}})


## 递归构造至多指定人数的目标组合；每个非空中间组合都对应一次可合法提交的鸣弦动作。
func _append_target_combinations(candidates: Array[int], maximum_count: int, start_index: int, current: Array[int], result: Array[Array]) -> void:
	if not current.is_empty():
		result.append(current.duplicate())
	if current.size() >= maximum_count:
		return
	for candidate_index: int in range(start_index, candidates.size()):
		# 下一层组合；使用副本避免递归分支共享可变数组。
		var next: Array[int] = current.duplicate()
		next.append(candidates[candidate_index])
		_append_target_combinations(candidates, maximum_count, candidate_index + 1, next, result)


## 评估鸣弦动作；AI会无条件累加自己和友方的一张牌收益，并因敌方获得牌的负收益自动排除敌人。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 本次鸣弦总收益；每名目标独立按一张牌计算。
	var result: float = 0.0
	for target_id_variant: Variant in action.get("target_ids", []) as Array:
		# 获得【杀】的目标ID；自己固定按一张牌计分，其他角色按阵营态度计分。
		var target_id: int = int(target_id_variant)
		result += AI_SLASH_GAIN_VALUE if target_id == owner_player_id else evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 1, 0)
	return result
