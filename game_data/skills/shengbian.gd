extends SkillDefinition

## 【升变】技能源码。持有者每个回合开始时选择一名角色增长或重置全场“军功”，并通过局内获得技能接口动态赋予【奇袭】。
## 本技能不是轮回技：它每次发动只做一次军功分配，自身没有轮回节与轮回数，也不受轮回通用限次约束。

## “军功”公开标记稳定ID；奇袭按相同ID读取阈值。
const MILITARY_MERIT_MARK_ID: String = "jungong"

## “军功”公开标记首次创建元数据；来源技能ID用于展示和长期追踪。
const MILITARY_MERIT_MARK_DATA: Dictionary = {"icon":"军", "name":"军功", "description":"拥有“军功”标记的角色视为拥有技能“奇袭”。", "source_skill_id":"shengbian"}

## 被“军功”动态赋予的技能稳定ID；角色失去全部军功时只撤销同来源获得记录。
const DERIVED_SKILL_ID: String = "qixi"

## 动态奇袭获得记录的来源ID；与其他技能来源区分，避免清除军功时误卸载固有或其他来源技能。
const DERIVED_SKILL_SOURCE: String = "shengbian_jungong"

## 单次发动给予目标的“军功”枚数上限；数值2来自技能原文“令其获得2枚‘军功’标记”。
## 这是本次给予量（而非持有量）的上限，实际给予量还要受目标持有总数上限约束。
const MILITARY_MERIT_GAIN_PER_ACTIVATION: int = 2

## 目标“军功”持有总数上限；数值8来自技能原文“至多获得至8枚”。
## 它截断的是目标**持有总数**：已有7枚时本次只给1枚，已有8枚时本次给0枚但仍算合法发动并写日志。
const MILITARY_MERIT_TOTAL_CAP: int = 8

## 目标选择请求的稳定种类标识；请求创建、AI评分与选择恢复共用同一键值，防止旧响应进入其他分支。
const TARGET_SELECTION_KIND: String = "shengbian_target"

## AI发动升变的固定基础收益；正值保证AI不会因目标当前收益偏低而完全放弃每回合一次的免费军功分配。
const AI_ACTIVATION_BASE_VALUE: float = 1.0

## 已有军功目标的固定增益估值；覆盖既有军功已带来的奇袭收益，仅影响AI的目标排序，不修改真实军功数量。
const AI_EXISTING_MERIT_BASE_VALUE: float = 8.0

## 无军功目标的重置分支固定增益估值；覆盖目标固定获得2枚军功与动态获得奇袭的即时价值，仅影响AI评分。
const AI_RESET_MERIT_BASE_VALUE: float = 10.0

## 目标每个“出牌阶段限一次”或“轮回技”技能带来的军功优先价值；这类技能每次发动都会推进军功积累，因此军功应先给能反复触发【奇袭】的角色。
const AI_MATCHED_SKILL_TARGET_VALUE: float = 2.5

## 军功优先价值的封顶技能条目数；超过3项后收益不再随技能数量线性增长，避免评分被技能条数完全支配。
const AI_MATCHED_SKILL_MAX_COUNT: int = 3


## 写入技能静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"shengbian",
		"name":"升变",
		"trigger":"phaseBefore",
		"ui_enabled":false,
		"description":"回合开始时，你可选择一名角色，若其没有“军功”标记，你移除场上所有的“军功”标记。然后令其获得2枚“军功”标记（至多获得至8枚）。拥有“军功”标记的角色视为拥有技能“奇袭”。",
	})


## 订阅持有者自己的回合开始时时机；普通回合与额外回合都会各自提供一次询问机会。
## 时机本身即“每回合一次”，因此本技能不再依赖轮回通用限次。
func install() -> void:
	subscribe_timing("phaseBefore", _on_turn_begin, "player")


## 回合开始时创建目标询问；持有者失效、非自身回合或场上没有合法角色时不创建无效询问。
func _on_turn_begin(_event: RuleEvent) -> void:
	if not _can_offer_activation():
		return
	request_target_selection("【升变】请选择获得军功的角色", _get_target_ids(), 1, 1, true, {"kind":TARGET_SELECTION_KIND})


## 返回当前是否开放回合开始的军功分配；死亡、离场、非自身回合都会关闭该窗口。
## 该判断同时服务询问创建与选择恢复：等待目标期间状态失效时本次发动整体放弃。
func _can_offer_activation() -> bool:
	# 技能持有者；死亡或离场角色不能发动技能。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and host.state.current_player_id == owner_player_id and not _get_target_ids().is_empty()


## 恢复目标选择；取消不产生任何标记变化。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != TARGET_SELECTION_KIND or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		_execute_shengbian(response.target_ids[0])
	return true


## 最终复核并执行“空场重置 + 给予军功”的分支；条件在等待目标期间失效时安全放弃。
func _execute_shengbian(target_id: int) -> bool:
	if not _can_offer_activation() or not _get_target_ids().has(target_id):
		return false
	# 目标当前军功数；为0时才触发“移除场上所有的军功标记”的前置分支。
	var target_mark_count: int = _get_military_merit_count(target_id)
	# 本次是否清空了全场军功；公开日志与AI评分都按该事实区分两种分支。
	var reset_field: bool = target_mark_count <= 0
	if reset_field:
		_remove_all_field_military_merit()
	# 清场后目标的剩余军功数；清场分支下目标必然为0，非清场分支下等于原数量。
	var remaining_count: int = _get_military_merit_count(target_id)
	# 本次实际获得的军功数；“至多获得至8枚”截断的是持有总数，因此已接近上限时只给一部分甚至给0。
	var actual_gain: int = clampi(MILITARY_MERIT_TOTAL_CAP - remaining_count, 0, MILITARY_MERIT_GAIN_PER_ACTIVATION)
	if actual_gain > 0:
		host.call("change_player_mark_count", target_id, MILITARY_MERIT_MARK_ID, actual_gain, _build_military_merit_mark_data())
	_ensure_derived_skill(target_id)
	announce_activation({"target_id":target_id, "target_ids":[target_id], "military_merit_before":target_mark_count, "military_merit_gain":actual_gain, "military_merit_after":remaining_count + actual_gain, "reset_field":reset_field})
	return true


## 构造带有当前施加者归属的军功标记数据；来源死亡时通用标记服务据此清理其给予其他角色的军功。
func _build_military_merit_mark_data() -> Dictionary:
	# 军功标记数据；静态显示字段沿用常量，运行时只补充稳定来源角色ID。
	var mark_data: Dictionary = MILITARY_MERIT_MARK_DATA.duplicate(true)
	mark_data["source_player_id"] = owner_player_id
	return mark_data


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


## 评估回合开始目标选择动作；确认动作按场上军功清空损益、目标增益与奇袭触发技能价值评分，取消动作保持0分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只有升变自己的回合开始目标询问参与本技能评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TARGET_SELECTION_KIND:
		return 0.0
	# 动作负载；取消表示本次不分配军功，保持0分让通用取消价值决定。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；升变必须且只能指定一名角色。
	var target_ids: Array = payload.get("selected_target_ids", []) as Array
	if target_ids.size() != 1:
		return -100.0
	# 目标稳定ID；动作已限制为唯一目标，该ID只用于读取公开状态。
	var target_id: int = int(target_ids[0])
	# 升变持有者对目标的阵营态度；正值表示军功增益应被鼓励，负值表示应被惩罚。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 目标公开快照；AI评分实例没有规则宿主，只能从本次权威快照读取军功与技能来源。
	var target_snapshot: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	# 目标能从【奇袭】获得收益的技能价值；随阵营态度缩放，敌方因军功变强时该价值转为惩罚。
	var target_merit_value: float = _score_snapshot_merit_trigger_skills(target_snapshot)
	# 目标当前军功持有量；0进入“清空全场再给予”分支，正数进入“继续积累”分支。
	var target_mark_count: int = _get_snapshot_military_merit_count(target_snapshot)
	if target_mark_count > 0:
		# 本次实际给予量；“至多获得至8枚”截断持有总数，已持有8枚时本次给予0枚。
		var actual_gain: int = clampi(MILITARY_MERIT_TOTAL_CAP - target_mark_count, 0, MILITARY_MERIT_GAIN_PER_ACTIVATION)
		if actual_gain <= 0:
			# 已满8枚的目标本次没有任何真实收益：返回0分与“取消”持平，
			# 让严格大于阈值的确认判定自然失败，避免AI在无收益目标上反复发动升变。
			return 0.0
		# 继续积累分支：已有军功不会被清空，且目标原有军功越多离【奇袭】重置越近。
		return AI_ACTIVATION_BASE_VALUE + attitude * (AI_EXISTING_MERIT_BASE_VALUE + float(actual_gain) + target_merit_value)
	# 清场分支的全场军功净损益；移除敌方为正、移除友方为负，再叠加目标新获2枚的价值。
	var score: float = AI_ACTIVATION_BASE_VALUE + attitude * (AI_RESET_MERIT_BASE_VALUE + target_merit_value)
	for field_player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 场上角色公开快照；死亡与离场角色不属于升变清除军功的当前场面估值。
		var field_player: Dictionary = field_player_variant as Dictionary
		if bool(field_player.get("alive", false)) and not bool(field_player.get("out_of_game", false)):
			# 场上角色稳定ID；身份态度与军功损益都围绕同一公开目标计算。
			var field_player_id: int = int(field_player.get("player_id", -1))
			score -= evaluator.get_attitude(authoritative_snapshot, owner_player_id, field_player_id) * float(_get_snapshot_military_merit_count(field_player))
	return score


## 评估目标角色因拥有“出牌阶段限一次”或“轮回技”技能而配得上优先获得军功的程度。
## 轮回技只读技能源码声明的标签，“出牌阶段限一次”按正文声明识别，与【奇袭】的规则层判定完全同源。
func _score_snapshot_merit_trigger_skills(target_snapshot: Dictionary) -> float:
	# 目标当前实际安装的技能ID；失去技能（如【留白】）会卸载实例，因此这里天然只统计“现在还在身上”的技能。
	# 快照缺少该字段时不做裁剪（旧快照与手动构造的测试快照保持完整技能列表）。
	var installed_skill_ids: Array = target_snapshot.get("installed_skill_ids", []) as Array
	# 是否按实际安装集合裁剪；只有权威快照会下发该字段。
	var filter_by_installed: bool = target_snapshot.has("installed_skill_ids")
	# 目标全部技能ID；顺序与基础AI其他估值入口一致：固有、模式、临时、局内获得，并按稳定ID去重。
	var skill_ids: Array[String] = []
	for skill_id_variant: Variant in (GameDatabase.get_character(str(target_snapshot.get("character_id", ""))).get("skills", []) as Array):
		# 当前固有技能ID；空值、已被失去与重复项不进入统计。
		var native_skill_id: String = str(skill_id_variant)
		if native_skill_id.is_empty() or skill_ids.has(native_skill_id):
			continue
		if filter_by_installed and not installed_skill_ids.has(native_skill_id):
			continue
		skill_ids.append(native_skill_id)
	for mode_skill_id_variant: Variant in target_snapshot.get("mode_skill_ids", []) as Array:
		# 当前模式技能ID；飞扬、跋扈等模式技能同样可能声明两类标签。
		var mode_skill_id: String = str(mode_skill_id_variant)
		if mode_skill_id.is_empty() or skill_ids.has(mode_skill_id):
			continue
		if filter_by_installed and not installed_skill_ids.has(mode_skill_id):
			continue
		skill_ids.append(mode_skill_id)
	for runtime_skill_map_variant: Variant in [target_snapshot.get("temporary_skills", {}), target_snapshot.get("acquired_skills", {})]:
		# 当前运行时技能映射；键为稳定技能ID，值只保存来源与次数状态。
		var runtime_skill_map: Dictionary = runtime_skill_map_variant as Dictionary
		for skill_id_variant: Variant in runtime_skill_map.keys():
			# 当前运行时技能ID；与固有技能同名时只统计一次。
			var runtime_skill_id: String = str(skill_id_variant)
			if not runtime_skill_id.is_empty() and not skill_ids.has(runtime_skill_id):
				skill_ids.append(runtime_skill_id)
	# 命中两类标签的技能条目数；达到封顶后立即停止查询，避免多余的内容库访问。
	var matched_count: int = 0
	for skill_id: String in skill_ids:
		# 当前技能静态元数据；未登记技能不参与统计。
		var skill_metadata: Dictionary = GameDatabase.get_skill(skill_id)
		if skill_metadata.is_empty():
			continue
		# 当前技能正文；“出牌阶段限一次”按正文声明识别，引号内提及不计入。
		var description: String = str(skill_metadata.get("description", ""))
		# 当前技能是否为轮回技；只读技能源码声明的轮回技标签，与【奇袭】的规则层判定口径一致。
		var is_reincarnation_skill: bool = bool(skill_metadata.get("reincarnation", false))
		if description_declares_tag(description, PLAY_PHASE_ONCE_TAG) or is_reincarnation_skill:
			matched_count += 1
			if matched_count >= AI_MATCHED_SKILL_MAX_COUNT:
				break
	return float(matched_count) * AI_MATCHED_SKILL_TARGET_VALUE


## 从AI权威玩家快照读取军功数量；该纯函数不访问运行时技能宿主，可安全用于策略临时实例。
func _get_snapshot_military_merit_count(player_snapshot: Dictionary) -> int:
	# 玩家全部公开标记；军功不存在时按空字典处理。
	var public_marks: Dictionary = player_snapshot.get("public_marks", {}) as Dictionary
	# 军功公开标记数据；数量始终收敛到非负整数。
	var military_merit_mark: Dictionary = public_marks.get(MILITARY_MERIT_MARK_ID, {}) as Dictionary
	return maxi(int(military_merit_mark.get("count", 0)), 0)
