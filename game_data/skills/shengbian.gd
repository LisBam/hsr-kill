extends SkillDefinition

## 【升变】技能源码。每个出牌阶段选择一名角色增长或重置“军功”，并通过局内获得技能接口动态赋予【奇袭】。

## “军功”公开标记稳定ID；奇袭按相同ID读取阈值。
const MILITARY_MERIT_MARK_ID: String = "jungong"

## “军功”公开标记首次创建元数据；来源技能ID用于展示和长期追踪。
const MILITARY_MERIT_MARK_DATA: Dictionary = {"icon":"军", "name":"军功", "description":"拥有“军功”标记的角色视为拥有技能“奇袭”。", "source_skill_id":"shengbian"}

## 被“军功”动态赋予的技能稳定ID；角色失去全部军功时只撤销同来源获得记录。
const DERIVED_SKILL_ID: String = "qixi"

## 动态奇袭获得记录的来源ID；与其他技能来源区分，避免清除军功时误卸载固有或其他来源技能。
const DERIVED_SKILL_SOURCE: String = "shengbian_jungong"

## 无“军功”目标重置后固定获得的标记数；数值2来自技能原文。
const INITIAL_MILITARY_MERIT_COUNT: int = 2

## 轮回数X的最大有效值；数值5来自技能原文“且至多为5”。
const MAX_ROUND_GAIN: int = 5

## 当前出牌阶段是否已经成功发动；默认false，每个phaseUseBegin复原，额外发动不额外占用普通额度。
var _used_this_play_phase: bool = false


## 写入单轮回节主动技能静态信息；技能描述逐字保持主公提供的原文。
func _init() -> void:
	super({
		"id":"shengbian",
		"name":"升变",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"reincarnation":true,
		"reincarnation_section_count":1,
		"reincarnation_has_explicit_sections":false,
		"description":"轮回技，出牌阶段限一次，你可选择一名角色，若其有“军功”标记，你令其获得X枚“军功”标记；若其没有“军功”标记，你移除场上所有的“军功”标记，并令其获得2枚“军功”标记。拥有“军功”标记的角色视为拥有技能“奇袭”。（X为此技能的轮回数且至多为5）",
	})


## 订阅自身每个出牌阶段开始时机；普通、额外与转换出牌阶段均恢复一次额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 仅在自身出牌阶段、普通额度未用、轮回通用限制允许且至少存在一名场上角色时开放。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡或离场角色不能主动发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and not _used_this_play_phase and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" and can_activate_reincarnation() and not _get_target_ids().is_empty()


## 直接动作携带唯一目标时立即执行，否则创建统一单目标选择请求。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标数组；AI、网络与奇袭重放均使用相同字段。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if target_ids.size() == 1:
		return "" if _execute_shengbian(target_ids[0], bool(context.get("repeated_activation", false))) else "【升变】的目标、阶段次数或轮回状态已经失效。"
	request_target_selection("【升变】请选择获得军功的角色", _get_target_ids(), 1, 1, true, {"kind":"shengbian_target"})
	return ""


## 恢复目标选择；取消不消耗阶段额度也不推进轮回。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "shengbian_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		_execute_shengbian(response.target_ids[0], false)
	return true


## 最终复核并执行增长或全场重置分支；repeated=true时只绕过普通“限一次”，仍遵守轮回服务额度。
func _execute_shengbian(target_id: int, repeated: bool) -> bool:
	if (not repeated and not can_activate()) or (repeated and not _can_repeat_now()) or not _get_target_ids().has(target_id) or not begin_reincarnation_activation():
		return false
	# 目标当前军功数；正数进入增长分支，0进入全场重置分支。
	var target_mark_count: int = _get_military_merit_count(target_id)
	# 本次轮回数X；效果快照至多取5，推进发生后才会增加下一次使用的轮回数。
	var round_gain: int = mini(get_reincarnation_round_count(), MAX_ROUND_GAIN)
	if target_mark_count > 0:
		host.call("change_player_mark_count", target_id, MILITARY_MERIT_MARK_ID, round_gain, MILITARY_MERIT_MARK_DATA)
		_ensure_derived_skill(target_id)
	else:
		_remove_all_field_military_merit()
		host.call("change_player_mark_count", target_id, MILITARY_MERIT_MARK_ID, INITIAL_MILITARY_MERIT_COUNT, MILITARY_MERIT_MARK_DATA)
		_ensure_derived_skill(target_id)
	if not repeated:
		_used_this_play_phase = true
	announce_activation({"target_id":target_id, "target_ids":[target_id], "round_count":get_reincarnation_round_count(), "military_merit_before":target_mark_count, "military_merit_gain":round_gain if target_mark_count > 0 else INITIAL_MILITARY_MERIT_COUNT, "reset_field":target_mark_count <= 0})
	complete_reincarnation_activation()
	return true


## 判断奇袭额外发动时仍处于自身出牌阶段且轮回通用额度可用；普通阶段限次由额外发动明确绕过。
func _can_repeat_now() -> bool:
	# 技能持有者；额外发动也不能跨越死亡、离场或阶段结束边界。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" and can_activate_reincarnation()


## 清除所有仍在场角色的军功，并只撤销由升变军功来源动态赋予的奇袭。
func _remove_all_field_military_merit() -> void:
	for field_player: PlayerState in host.state.players:
		if field_player == null or not field_player.alive or field_player.out_of_game:
			continue
		# 当前角色军功数量；没有标记时无需发送移除快照。
		var mark_count: int = _get_military_merit_count(field_player.player_id)
		if mark_count <= 0:
			continue
		host.call("change_player_mark_count", field_player.player_id, MILITARY_MERIT_MARK_ID, -mark_count)
		# 奇袭获得记录；固有技能、临时技能或其他来源不得因军功清空而被卸载。
		var acquired_usage: Dictionary = field_player.acquired_skills.get(DERIVED_SKILL_ID, {}) as Dictionary
		if str(acquired_usage.get("source", "")) == DERIVED_SKILL_SOURCE:
			host.call("remove_acquired_skill", field_player.player_id, DERIVED_SKILL_ID)


## 保证拥有军功的角色视为拥有奇袭；已经由固有或其他来源持有时不重复安装。
func _ensure_derived_skill(target_id: int) -> void:
	if _get_military_merit_count(target_id) > 0:
		host.call("grant_acquired_skill", target_id, DERIVED_SKILL_ID, 0, 0, DERIVED_SKILL_SOURCE)


## 返回全部仍存活在场角色；升变允许选择自己。
func _get_target_ids() -> Array[int]:
	# 目标结果；保持权威座次顺序供UI、AI与回放共用。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			result.append(player.player_id)
	return result


## 返回指定角色当前军功数量；标记不存在时按0处理。
func _get_military_merit_count(player_id: int) -> int:
	return maxi(int((host.call("get_player_mark", player_id, MILITARY_MERIT_MARK_ID) as Dictionary).get("count", 0)), 0)


## 每个新的自身出牌阶段恢复普通发动额度。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 为AI逐一枚举全部合法角色，允许评分器优先选择已有军功的友方。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_target_ids():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## AI优先强化已有军功的友方；无标记分支会综合全场军功清空损益后再选择新持有者。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作目标；升变必须且只能指定一名角色。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return -100.0
	# 目标稳定ID；动作已限制为唯一目标，该ID只用于读取公开状态。
	var target_id: int = int(target_ids[0])
	# 升变持有者对目标的阵营态度；正值表示军功增益应被鼓励，负值表示应被惩罚。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 已有军功目标享受明确优先级；X随轮回增长但最多按5枚估值。
	var target_mark_count: int = _get_military_merit_count(target_id)
	if target_mark_count > 0:
		return attitude * (8.0 + float(mini(get_reincarnation_round_count(), MAX_ROUND_GAIN)))
	# 重置分支的全场军功净损益；移除敌方为正、移除友方为负，再叠加目标新获2枚的价值。
	var score: float = attitude * 10.0
	for field_player: PlayerState in host.state.players:
		if field_player.alive and not field_player.out_of_game:
			score -= evaluator.get_attitude(authoritative_snapshot, owner_player_id, field_player.player_id) * float(_get_military_merit_count(field_player.player_id))
	return score


## 把弱类型数组收敛为整数目标数组；动作、网络与回放输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序且不去重，最终执行仍按唯一目标要求复核。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result
