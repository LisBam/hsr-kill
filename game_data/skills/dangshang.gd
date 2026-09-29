extends SkillDefinition

## 【当赏】欢愉技源码。阿哈时刻按参演编号120强制驱动：令一名角色摸一张牌。
## 本技能与【好活】共用参演编号120，这是需求给定的原始编号；两者的先后由阿哈时刻既有的座位顺序规则决定。

## 目标摸牌数；固定1张，原文为“摸一张牌”。
const DRAW_COUNT: int = 1

## 目标数量；固定1名，原文为“一名角色”。
const TARGET_COUNT: int = 1

## 目标选择请求种类；恢复时按该值分流到结算入口。
const TARGET_CHOICE_KIND: String = "dangshang_target"

## 目标选择窗口是否允许取消；固定false，欢愉技强制发动且必须选定一名角色。
const ALLOW_TARGET_CANCEL: bool = false

## AI：友方目标的基础收益；保证摸牌优先落在自己人身上。
const AI_ALLY_BASE_SCORE: float = 4.0

## AI：目标态度权重；态度越高越优先，使收益按阵营关系倾斜。
const AI_ATTITUDE_WEIGHT: float = 0.5

## AI：目标手牌数权重；手牌越少摸牌的边际价值越高，因此按负值计入。
const AI_LOW_HAND_COUNT_WEIGHT: float = 0.3

## AI：敌方与中立目标的评分；负值使AI不去给对手补牌。
const AI_HOSTILE_TARGET_SCORE: float = -6.0

## AI：非法目标的评分；低于任何合法动作。
const AI_INVALID_TARGET_SCORE: float = -20.0


## 写入欢愉技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"dangshang",
		"name":"当赏",
		"trigger":"passive",
		"joy_skill":true,
		"performance_number":120,
		"description":"欢愉技，参演编号120，你令一名角色摸一张牌。",
	})


## 阿哈时刻的唯一执行入口：选择一名角色（含持有者本人）并令其摸一张牌。
func perform_joy_skill(context: Dictionary) -> void:
	# 直接动作目标；由调试或回放入口显式给出时跳过选择窗口，正常演出路径不携带该字段。
	if context.has("target_ids"):
		# 显式目标列表；本技能只取第一名合法角色，多余目标由结算阶段忽略。
		var direct_target_ids: Array[int] = []
		for target_variant: Variant in context.get("target_ids", []) as Array:
			direct_target_ids.append(int(target_variant))
		_execute_dangshang(direct_target_ids)
		return
	# 候选目标；含持有者本人，因为原文只说“一名角色”。
	var candidate_target_ids: Array[int] = _get_all_alive_player_ids()
	if candidate_target_ids.is_empty():
		# 场上没有合法候选时仍必须回报演出结束，否则阿哈时刻队列会停在当前项。
		finish_joy_skill_performance()
		return
	request_target_selection("【当赏】请选择一名角色，令其摸一张牌", candidate_target_ids, TARGET_COUNT, TARGET_COUNT, ALLOW_TARGET_CANCEL, {"kind":TARGET_CHOICE_KIND})


## 恢复目标选择；窗口不可取消，异常输入按没有目标处理，本次演出空过但仍回报结束。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return false
	# 已确认目标；未确认只可能来自异常提交或旧回放，按空列表结算不会中断演出。
	var selected_target_ids: Array[int] = response.target_ids if response.confirmed else []
	_execute_dangshang(selected_target_ids)
	return true


## 结算当赏：令第一名合法目标摸一张牌，然后回报欢愉技演出结束。
func _execute_dangshang(selected_target_ids: Array[int]) -> void:
	# 实际生效目标；等待期间死亡或离场的候选被剔除，只取第一名。
	var target_id: int = -1
	for candidate_id: int in selected_target_ids:
		# 当前候选角色；必须仍是存活且未离场角色。
		var candidate: PlayerState = _get_player(candidate_id)
		if candidate == null or not candidate.alive or candidate.out_of_game:
			continue
		target_id = candidate_id
		break
	if target_id < 0:
		finish_joy_skill_performance()
		return
	announce_activation({"target_id":target_id, "draw_count":DRAW_COUNT})
	host.call("draw", target_id, DRAW_COUNT)
	finish_joy_skill_performance()


## 返回全部存活且未离场角色的稳定玩家ID；含持有者本人，顺序保持权威座次。
func _get_all_alive_player_ids() -> Array[int]:
	# 候选结果；按权威座次顺序，界面、AI与回放据此稳定复现。
	var player_ids: Array[int] = []
	if host == null or host.get("state") == null:
		return player_ids
	for player: PlayerState in host.state.players:
		if player != null and player.alive and not player.out_of_game:
			player_ids.append(player.player_id)
	return player_ids


## 返回指定角色的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_player(player_id: int) -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(player_id)


## 为AI评估当赏的目标选择；优先给友方中手牌较少者补牌，不给敌方补牌。
##
## 需求未给出当赏的AI口径，本函数按正面效果技能的通用估值补全：
## 阵营关系决定是否值得给牌，手牌数量决定边际收益，二者共同构成连续分值。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理当赏的目标选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return 0.0
	# 动作负载；当赏必须选定一名角色，未确认或数量不符由权威端拒绝。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；数量不等于1时判为无效动作。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() != TARGET_COUNT:
		return AI_INVALID_TARGET_SCORE
	# 目标快照；不存在时判为无效目标。
	var target_id: int = int(selected_targets[0])
	var target: Dictionary = _snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return AI_INVALID_TARGET_SCORE
	# 目标手牌数；公开计数，手牌越少摸牌边际价值越高。
	var hand_count: int = int(target.get("hand_count", 0))
	# 自己恒为可接受目标；态度查询不适用于自身，因此直接按我方基准分计算。
	if target_id == owner_player_id:
		return AI_ALLY_BASE_SCORE - hand_count * AI_LOW_HAND_COUNT_WEIGHT
	# 目标对持有者的态度；非正值表示敌方或中立，不值得给其补牌。
	var attitude: float = float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id))
	if attitude <= 0.0:
		return AI_HOSTILE_TARGET_SCORE
	return AI_ALLY_BASE_SCORE + attitude * AI_ATTITUDE_WEIGHT - hand_count * AI_LOW_HAND_COUNT_WEIGHT


## 从权威快照读取指定玩家；不存在时返回空字典。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后原样返回只读字典。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
