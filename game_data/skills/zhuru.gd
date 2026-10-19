extends SkillDefinition

## 【注入】技能源码。开局可组合并获得一项【进程】；此后每轮准备阶段可为一名角色组合一项组合技能。
##
## 【玩法定位】银狼的核心机制：她没有固定牌效，强度来自「按当前形势现场组合」。
## 同一个角色可以累积多份同名组合技能，每份实例的每回合额度独立计算（依赖技能实例键底座）。
##
## 【两条入口的差别】开局那次**只给自己**、**只给进程**（原文「你可组合并获得一项技能“进程”」）；
## 准备阶段那次可以选择任意角色，并且**按目标是否为主演**决定组合成进程还是缺陷。
##
## 【可选发动】两处都允许取消：取消即不获得任何技能，也不消耗任何资源。
## 组合窗口本身也是可取消的，因此「选了目标又反悔」不会产生半成品状态。

## 准备阶段目标选择的业务类型；与组合窗口分开，便于恢复时判断当前处于哪一步。
const CHOICE_KIND_TARGET: String = "zhuru_target"

## 组合窗口的业务类型；上下文里同时带着类别池与获得者，恢复时无需重新推导。
const CHOICE_KIND_COMPOSE: String = "zhuru_compose"

## 组合窗口每栏默认展示的候选数量；与需求补全口径一致（两栏各默认 2 个候选，可展开完整池）。
const OFFERING_SIZE: int = 2

## 组合窗口控制项前缀；与控制器常量同源，避免两侧各写一份字面量后失配。
const COMPOSE_CONTROL_PREFIX: String = MatchController.YINLANG_COMPOSE_CONTROL_PREFIX

## 组合窗口控制项的分隔符；与控制器常量同源。
const CONTROL_SEPARATOR: String = MatchController.YINLANG_CONTROL_SEPARATOR

## 组合窗口控制项的分段数量：前缀两段 + 时机键 + 效果键。
const COMPOSE_CONTROL_FIELD_COUNT: int = 4

## AI 短名单长度上限；与控制器常量同源，避免技能给出的名单被控制器静默截断。
const AI_CANDIDATE_LIMIT: int = MatchController.YINLANG_AI_CANDIDATE_LIMIT

## 组合窗口随机提供项的随机历史种类；随机抽取必须记账，否则回放与联机无法复现同一批候选。
const OFFERING_HISTORY_KIND: String = "zhuru_compose_offering"

## 组合技能的授予来源标记；进入额度记录，便于诊断「这份技能是从哪来的」。
const COMPOSE_GRANT_SOURCE: String = "zhuru"

## 组合技能的每回合发动额度；与组合后正文「每回合限一次」严格对应，且按实例分别计算。
const COMPOSE_PER_TURN_LIMIT: int = 1

## AI 短名单里「进程」组合的基准价值；进程是纯收益池，因此基准为正。
const AI_JINCHENG_BASE_VALUE: float = 6.0

## AI 短名单里「缺陷」组合的基准价值；缺陷是纯代价池，因此基准为负。
const AI_QUEXIAN_BASE_VALUE: float = -6.0

## AI 对「失去本技能」类效果的额外折价；这类效果一次性消耗掉组合技能本身。
const AI_LOSES_SKILL_PENALTY: float = -3.0

## AI 对「需要选择目标或选牌」的效果的轻微折价；多一步交互意味着更多被响应/被反制的机会。
const AI_NEEDS_CHOICE_PENALTY: float = -0.5

## 本局是否已经结算过开局组合；防止重开、读档恢复或纯规则测试重复派发 gameStart 时多发一份技能。
var _applied_game_start: bool = false


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"zhuru",
		"name":"注入",
		"trigger":"",
		"ui_enabled":false,
		"description":"游戏开始时，你可组合并获得一项技能“进程”。准备阶段，你可选择一名角色，若该角色为“主演”，你组合一项技能“进程”并令其获得之；否则，你组合一项技能“缺陷”并令其获得之。",
	})


## 订阅开局与准备阶段两个入口。
## gameStart 的玩家、来源与目标三项 ID 全部为 -1，因此只能以 global 角色监听任意角色开局；
## phaseZhunbeiBegin 是本人回合的阶段时机，用 player 角色限定为「银狼自己的准备阶段」。
func install() -> void:
	subscribe_timing("gameStart", _on_game_start, "global")
	subscribe_timing("phaseZhunbeiBegin", _on_phase_zhunbei_begin, "player")


## 游戏开始时可选发动：只为自己组合一项【进程】。
func _on_game_start(_event: RuleEvent) -> void:
	if host == null or host.get("state") == null or host.state.game_over:
		return
	# 幂等标记；无法读取持有者时不写入，保证后续重复派发仍有结算机会。
	if _applied_game_start:
		return
	# 技能持有者权威状态；死亡或离场时开局组合不再发生。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or owner.out_of_game:
		return
	_applied_game_start = true
	_open_compose_window(ComposedSkillPools.KIND_JINCHENG, owner_player_id)


## 准备阶段可选发动：先选一名角色，再按该角色是否为主演决定组合类别。
func _on_phase_zhunbei_begin(_event: RuleEvent) -> void:
	if host == null or host.get("state") == null or host.state.game_over:
		return
	# 技能持有者权威状态；死亡或离场时不再创建选择。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 候选目标；存活且未离场的角色（含自己），按权威座次排列，界面与AI据此得到相同顺序。
	var target_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player != null and player.alive and not player.out_of_game:
			target_ids.append(player.player_id)
	if target_ids.is_empty():
		return
	request_target_selection("选择一名角色获得组合技能（可取消）", target_ids, 1, 1, true, {"kind":CHOICE_KIND_TARGET})


## 恢复注入的两段式选择；返回 true 表示本请求由注入消费。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 当前步骤业务类型；空值或非注入类型不接管。
	var kind: String = str(context.get("kind", ""))
	if kind != CHOICE_KIND_TARGET and kind != CHOICE_KIND_COMPOSE:
		return false
	if response == null:
		return false
	# 取消：准备阶段取消表示不发动；组合窗口取消表示本次组合作废（不产生任何技能）。
	if not response.confirmed:
		return true
	if kind == CHOICE_KIND_TARGET:
		_continue_target_step(response)
		return true
	_continue_compose_step(context, response)
	return true


## 准备阶段第二步：按目标是否为主演打开对应类别的组合窗口。
func _continue_target_step(response: ChoiceResponse) -> void:
	if response.target_ids.is_empty():
		return
	# 已选目标角色；主演判定走权威端口，界面标记不参与规则。
	var target_id: int = int(response.target_ids[0])
	# 组合类别；目标为主演时给收益池（进程），否则给代价池（缺陷）。
	var pool_kind: String = ComposedSkillPools.KIND_JINCHENG if bool(host.call("is_starring_role", target_id)) else ComposedSkillPools.KIND_QUEXIAN
	_open_compose_window(pool_kind, target_id)


## 组合窗口第二步：解析组合结果并把新技能授予目标角色。
func _continue_compose_step(context: Dictionary, response: ChoiceResponse) -> void:
	# 组合窗口的控制项；格式为 yinlang|compose|<时机键>|<效果键>，合法性已由权威侧结构校验复核。
	var control_id: String = str(response.control_id)
	if not control_id.begins_with(COMPOSE_CONTROL_PREFIX):
		return
	# 分段结果；前缀两段固定，随后是时机键与效果键。
	var segments: PackedStringArray = control_id.split(CONTROL_SEPARATOR)
	if segments.size() != COMPOSE_CONTROL_FIELD_COUNT:
		return
	_grant_composed_skill(int(context.get("grant_target_id", -1)), str(context.get("pool_kind", "")), segments[2], segments[3])


## 打开组合窗口；每栏按权威随机源抽取 OFFERING_SIZE 个候选，同时把完整池交给界面供「展开全部」使用。
##
## 【随机为什么必须走控制器】随机提供项会改变玩家可选内容，直接调用 randi() 会让回放与联机无法复现。
## `pick_random_distinct_keys` 每次抽取都写入 random_history，读档重放时按同一顺序重放即可得到同一批候选。
func _open_compose_window(pool_kind: String, grant_target_id: int) -> void:
	if pool_kind.is_empty() or grant_target_id < 0:
		return
	# 时机池全部键；顺序即数据池声明顺序，界面展开全部时保持同一顺序。
	var timing_keys: Array[String] = []
	for entry: Dictionary in ComposedSkillPools.get_timing_entries():
		timing_keys.append(str(entry.get(ComposedSkillPools.KEY_FIELD, "")))
	# 效果池全部键；类别由本次组合决定（进程 / 缺陷）。
	var effect_keys: Array[String] = []
	for entry: Dictionary in ComposedSkillPools.get_effects(pool_kind):
		effect_keys.append(str(entry.get(ComposedSkillPools.KEY_FIELD, "")))
	# 本次随机提供项；两次抽取各自记账，且池不同因此历史数据天然区分。
	var timing_offering: Array[String] = host.call("pick_random_distinct_keys", timing_keys, OFFERING_SIZE, OFFERING_HISTORY_KIND, {"pool":"timing", "pool_kind":pool_kind}) as Array[String]
	var effect_offering: Array[String] = host.call("pick_random_distinct_keys", effect_keys, OFFERING_SIZE, OFFERING_HISTORY_KIND, {"pool":"effect", "pool_kind":pool_kind}) as Array[String]
	# 请求上下文；只放可序列化值，界面据此渲染，AI 短名单由本技能给出。
	var compose_context: Dictionary = {
		"kind":CHOICE_KIND_COMPOSE,
		MatchController.YINLANG_WINDOW_CONTEXT_KEY:MatchController.YINLANG_WINDOW_INJECT,
		"pool_kind":pool_kind,
		"grant_target_id":grant_target_id,
		"timing_offering":timing_offering,
		"effect_offering":effect_offering,
		"ai_candidate_control_ids":_build_ai_shortlist(pool_kind, timing_offering, effect_offering),
	}
	request_free_control_selection("【注入】组合技能", "左栏选择时机、右栏选择效果，确认后由目标角色获得该技能", MatchController.YINLANG_COMPOSE_CHOICE_TYPE, true, compose_context)


## 组合并授予一项技能实例；写入运行时配置与动态正文，使新实例立刻按组合结果生效。
func _grant_composed_skill(grant_target_id: int, pool_kind: String, timing_key: String, effect_key: String) -> void:
	if host == null or grant_target_id < 0 or pool_kind.is_empty():
		return
	# 双重复核；权威侧已校验过一次，这里再校验是因为本函数也可能被内部调用（例如测试直接构造组合结果）。
	if not ComposedSkillPools.is_valid_timing_key(timing_key) or not ComposedSkillPools.is_valid_effect_key(pool_kind, effect_key):
		push_error("注入组合结果非法：pool=%s timing=%s effect=%s" % [pool_kind, timing_key, effect_key])
		host.call("add_log", "【注入】的组合结果无效，本次未获得技能。")
		return
	# 授予前已安装的实例键集合；授予后做差集即可精确定位新实例。
	var keys_before: Array = host.call("get_installed_skill_keys", grant_target_id) as Array
	# 新实例的运行时配置；必须在授予时一并写入，否则安装阶段读不到配置（会订阅不到任何时机）。
	var runtime_data: Dictionary = {ComposedSkillBase.RUNTIME_KEY_TIMING:timing_key, ComposedSkillBase.RUNTIME_KEY_EFFECT:effect_key}
	# 实例键；由控制器在同一处完成「分配实例键 → 写配置 → 安装」，因此这里拿到的一定是已生效的实例。
	var instance_key: String = str(host.call("grant_configured_skill", grant_target_id, pool_kind, runtime_data, COMPOSE_PER_TURN_LIMIT, COMPOSE_GRANT_SOURCE, true))
	if instance_key.is_empty() or keys_before.has(instance_key):
		push_error("注入授予组合技能失败：target=%d pool=%s" % [grant_target_id, pool_kind])
		host.call("add_log", "【注入】未能授予组合技能。")
		return
	# 动态正文；严格等于「锁定技，<时机>，<效果>。每回合限一次。」，按实例键写入以便多份实例各自显示。
	host.call("set_skill_display_description", grant_target_id, instance_key, ComposedSkillPools.compose_description(_timing_text(timing_key), _effect_text(pool_kind, effect_key)))
	announce_activation({"grant_target_id":grant_target_id, "pool_kind":pool_kind, "timing_key":timing_key, "effect_key":effect_key, "instance_key":instance_key})


## 返回时机键对应的玩家可见文本；键非法时回落到键本身，保证正文永远可读而不是空字符串。
func _timing_text(timing_key: String) -> String:
	var entry: Dictionary = ComposedSkillPools.get_timing_entry(timing_key)
	if entry.is_empty():
		return timing_key
	return str(entry.get(ComposedSkillPools.TEXT_FIELD, timing_key))


## 返回效果键对应的玩家可见文本；键非法时回落到键本身。
func _effect_text(pool_kind: String, effect_key: String) -> String:
	var entry: Dictionary = ComposedSkillPools.get_effect_entry(pool_kind, effect_key)
	if entry.is_empty():
		return effect_key
	return str(entry.get(ComposedSkillPools.TEXT_FIELD, effect_key))


## 构造 AI 作答用的组合短名单；按「池基准价值 + 效果自身修正」排序后取前若干项。
##
## 【为什么需要短名单】注入窗口的合法答案是 23 × 24 种组合，全部枚举既浪费又无法排序；
## AI 只需要看到少量高分组合即可做出合理决策，因此由技能按自身收益模型给出排序后的候选。
## 候选来源限定在**本次随机提供项**内：与人类玩家看到的默认候选完全一致，AI 不会获得额外信息。
func _build_ai_shortlist(pool_kind: String, timing_offering: Array[String], effect_offering: Array[String]) -> Array[String]:
	# 候选与分值配对；用数组而不是字典，避免同分时的顺序在不同平台上有差异。
	var scored: Array[Dictionary] = []
	for timing_key: String in timing_offering:
		for effect_key: String in effect_offering:
			scored.append({"control_id":"%s%s%s%s" % [COMPOSE_CONTROL_PREFIX, timing_key, CONTROL_SEPARATOR, effect_key], "score":_score_compose(pool_kind, timing_key, effect_key)})
	# 分值降序；同分时保持生成顺序，保证 AI 行为可复现。
	scored.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left.get("score", 0.0)) > float(right.get("score", 0.0)))
	# 短名单结果；按控制器上限截断。
	var result: Array[String] = []
	for entry: Dictionary in scored:
		if result.size() >= AI_CANDIDATE_LIMIT:
			break
		result.append(str(entry.get("control_id", "")))
	return result


## 为一种组合打分；只做方向性排序，不复刻完整收益模型。
func _score_compose(pool_kind: String, _timing_key: String, effect_key: String) -> float:
	# 基准分；进程为正、缺陷为负。
	var score: float = AI_JINCHENG_BASE_VALUE if pool_kind == ComposedSkillPools.KIND_JINCHENG else AI_QUEXIAN_BASE_VALUE
	if ComposedSkillPools.effect_loses_skill(pool_kind, effect_key):
		score += AI_LOSES_SKILL_PENALTY
	if ComposedSkillPools.effect_needs_choice(pool_kind, effect_key):
		score += AI_NEEDS_CHOICE_PENALTY
	return score


## 注入没有主动按钮；主动动作评分恒为0，不影响通用策略。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 为注入自己的选择请求评分；只处理注入创建的请求，其余请求返回0不干扰通用评分。
##
## 口径：准备阶段优先选择「主演」目标（得到收益池进程）；非主演目标只会得到代价池缺陷，
## 因此按身份态度选择一名敌方角色去承受缺陷，而不是随机选人。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非注入选择不修改通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var kind: String = str(context.get("kind", ""))
	if kind != CHOICE_KIND_TARGET and kind != CHOICE_KIND_COMPOSE:
		return 0.0
	# 标准选择负载；取消保持0分，由通用策略决定是否取消。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	if kind == CHOICE_KIND_COMPOSE:
		# 组合窗口；直接按控制项对应组合的收益打分。
		return _score_control_id(str(payload.get("selected_control_id", payload.get("control_id", ""))))
	# 目标选择；主演优先（收益池），其余按态度取敌方（代价池）。
	var best_score: float = 0.0
	for target_variant: Variant in payload.get("selected_target_ids", []) as Array:
		# 当前候选目标；主演判定走只读快照字段，AI 不读权威状态。
		var target_id: int = int(target_variant)
		if _snapshot_is_starring(authoritative_snapshot, target_id):
			best_score = maxf(best_score, AI_JINCHENG_BASE_VALUE)
		else:
			# 非主演目标会拿到缺陷；态度越敌对（负值）越适合承受代价。
			best_score = maxf(best_score, -float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)) * 0.5 + AI_QUEXIAN_BASE_VALUE * 0.5)
	return best_score


## 解析组合控制项并给出分值；格式非法时返回0。
func _score_control_id(control_id: String) -> float:
	if not control_id.begins_with(COMPOSE_CONTROL_PREFIX):
		return 0.0
	# 分段结果；前缀两段固定，随后是时机键与效果键。
	var segments: PackedStringArray = control_id.split(CONTROL_SEPARATOR)
	if segments.size() != COMPOSE_CONTROL_FIELD_COUNT:
		return 0.0
	# 类别无法从控制项本身还原，因此按两个池各算一次并取较高分：AI 只关心「这个组合值不值得选」。
	return maxf(_score_compose(ComposedSkillPools.KIND_JINCHENG, segments[2], segments[3]), _score_compose(ComposedSkillPools.KIND_QUEXIAN, segments[2], segments[3]))


## 从公开快照判断一名角色是否为主演；主演服务把条目写进公开状态的角落文字表。
func _snapshot_is_starring(authoritative_snapshot: Dictionary, player_id: int) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；按稳定玩家ID匹配。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) != player_id:
			continue
		# 角落文字条目表；键为稳定来源ID，主演服务的条目ID固定为 zhuyan。
		var entries: Dictionary = player.get("character_corner_text_entries", {}) as Dictionary
		return entries.has(StarringRoleService.CORNER_ENTRY_ID)
	return false
