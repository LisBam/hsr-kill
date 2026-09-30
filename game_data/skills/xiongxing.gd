extends SkillDefinition

## 【凶星】欢愉技源码。阿哈时刻按参演编号116强制驱动：令一名角色下次受到的伤害+1；
## 若该角色为你，则改为同时提供一次“防止下次体力上限减少”。
## 效果可叠加：层数按目标身上的总层数聚合，角标在2层及以上直接显示为“凶星N”（层数紧跟在名称后，不加任何分隔符）。
##
## 分工：层数与伤害结算由“角色持续效果”承载（game_data/effects/xiongxingshanghai.gd），因为它属于被施加的角色；
## 本技能只负责选择目标、叠加层数，以及持有者自选时提供的“防止下次体力上限减少”。
## 这样爻光阵亡、换将或被“非锁定技失效”压制都不会撤回已经挂在目标身上的伤害+1。

## 单次发动叠加的层数；固定1层，与原文“下次受到的伤害+1”一致。
const STACK_PER_PERFORMANCE: int = 1

## 持有者自选凶星时提供的“防止下次体力上限减少”剩余次数键名；只写入持有者自己的 character_form_state。
const MAX_HP_GUARD_STATE_KEY: String = "xiongxing_max_hp_guard"

## 承载凶星伤害加成的角色持续效果 ID；必须与 game_data/effects/xiongxingshanghai.gd 的 EFFECT_ID 完全一致。
const DAMAGE_EFFECT_ID: String = "xiongxingshanghai"

## 目标选择请求种类；恢复时按该值分流到结算入口。
const TARGET_CHOICE_KIND: String = "xiongxing_target"

## 目标选择数量；固定1名，原文为“一名角色”。
const TARGET_COUNT: int = 1

## 目标选择窗口是否允许取消；固定false，欢愉技强制发动且必须选定一名角色。
const ALLOW_TARGET_CANCEL: bool = false

## AI：目标威胁（集火价值）的评分权重；威胁越高越优先，对应“优先选需要集火的、嘲讽高的目标”。
const AI_THREAT_WEIGHT: float = 1.0

## AI：敌我态度权重；态度为正的友方目标按同值扣分，避免把增伤浪费在队友身上。
const AI_ATTITUDE_WEIGHT: float = 0.7

## AI：敌方目标的固定基础收益；保证即使威胁值为0也高于“不发动”。
const AI_BASE_TARGET_SCORE: float = 1.0

## AI：满足自选条件时给予自己的分数；需显著高于任何威胁分，才能在候选集合中稳定胜出。
const AI_SELF_TARGET_SCORE: float = 12.0

## AI：不满足自选条件时选择自己的分数；为负值，使AI在常规局势下不把增伤留给自己。
const AI_SELF_TARGET_FALLBACK_SCORE: float = -3.0

## AI：触发“优先选择自己”所需的体力上限；固定1，对应需求“自己体力上限为1”。
const AI_SELF_PREFER_MAX_HP: int = 1

## AI：触发“优先选择自己”所需的我方欢愉技数量领先值；固定2，对应需求“我方比敌方多2或以上”。
const AI_SELF_PREFER_JOY_ADVANTAGE: int = 2

## 写入欢愉技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"xiongxing",
		"name":"凶星",
		"trigger":"passive",
		"joy_skill":true,
		"performance_number":116,
		"description":"欢愉技，参演编号116，你令一名角色下次受到的伤害+1。若该角色为你，则当你下次体力上限减少时，防止之。",
	})


## 订阅体力上限保护与持有者自身的死亡清理。
## 补充：伤害结算订阅已移交角色持续效果实例，本技能不再响应任何伤害时机；
## 因此爻光是否存活、是否换将、是否处于“非锁定技失效”都与已经施加的层数无关。
func install() -> void:
	subscribe_timing("loseMaxHpBefore", _on_lose_max_hp_before, "target")
	# 持有者阵亡后仍要清掉自身残留的上限保护；这是纯清理动作，因此标记 maintenance，
	# 使它不受“非锁定技失效”影响，同时也不会在失效期间产生任何新收益。
	subscribe_timing("dieAfter", _on_player_died, "global", 0, false, false, Callable(), false, true)


## 卸载技能时不再刷新或清除本人角标：层数与角标已由角色持续效果实例独立维护，
## 换将或失去技能都不会撤回已经施加的凶星。
## 原实现在此按本人当前层数刷新角标以避免误删其他爻光的提示，该职责现已随层数一并移交效果实例。
func uninstall() -> void:
	super()


## 阿哈时刻的唯一执行入口：选择一名角色（含持有者本人）并叠加一层凶星。
func perform_joy_skill(context: Dictionary) -> void:
	# 直接动作目标；由调试或回放入口显式给出时跳过选择窗口，正常演出路径不携带该字段。
	if context.has("target_ids"):
		# 显式目标列表；本技能只取第一名合法角色，多余目标由结算阶段忽略。
		var direct_target_ids: Array[int] = []
		for target_variant: Variant in context.get("target_ids", []) as Array:
			direct_target_ids.append(int(target_variant))
		_execute_xiongxing(direct_target_ids)
		return
	# 候选目标；含持有者本人，因为原文允许“该角色为你”并据此提供体力上限保护。
	var candidate_target_ids: Array[int] = _get_all_alive_player_ids()
	if candidate_target_ids.is_empty():
		# 场上没有合法候选时仍必须回报演出结束，否则阿哈时刻队列会停在当前项。
		finish_joy_skill_performance()
		return
	request_target_selection("【凶星】请选择一名角色，其下次受到的伤害+1", candidate_target_ids, TARGET_COUNT, TARGET_COUNT, ALLOW_TARGET_CANCEL, {"kind":TARGET_CHOICE_KIND})


## 恢复目标选择；窗口不可取消，异常输入按没有目标处理，本次演出空过但仍回报结束。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return false
	# 已确认目标；未确认只可能来自异常提交或旧回放，按空列表结算不会中断演出。
	var selected_target_ids: Array[int] = response.target_ids if response.confirmed else []
	_execute_xiongxing(selected_target_ids)
	return true


## 结算凶星：为第一名合法目标叠加一层伤害加成，目标为持有者本人时同时提供一层上限保护。
func _execute_xiongxing(selected_target_ids: Array[int]) -> void:
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
	# 凶星层数由角色持续效果实例承载：先确保目标身上存在该效果，再交给它叠加层数。
	# 该实例的生命周期只取决于目标，因此持有者随后阵亡、换将或被“非锁定技失效”压制都不会让层数停止结算。
	var damage_effect: PlayerEffect = null
	if host != null and host.has_method("install_player_effect"):
		damage_effect = host.call("install_player_effect", target_id, DAMAGE_EFFECT_ID) as PlayerEffect
	# 叠加后的层数；由效果实例统一读写，保证多名爻光施加同一目标时层数正确累加而不是互相覆盖。
	var next_stacks: int = 0
	if damage_effect != null:
		next_stacks = damage_effect.add_stacks(STACK_PER_PERFORMANCE)
	# 自选附加效果提供的上限保护次数；只有目标为持有者本人时累加，其他角色不获得该保护。
	var guard_count: int = 0
	if target_id == owner_player_id:
		guard_count = _get_max_hp_guard() + STACK_PER_PERFORMANCE
		_set_max_hp_guard(guard_count)
	announce_activation({"target_id":target_id, "stacks":next_stacks, "max_hp_guard_count":guard_count})
	finish_joy_skill_performance()


## 在体力上限减少的最早窗口防止之；只对持有者本人生效，并消耗全部保护次数。
func _on_lose_max_hp_before(event: RuleEvent) -> void:
	if event.target_id != owner_player_id:
		return
	if _get_max_hp_guard() <= 0:
		return
	# 保护次数归零；原文为“下次体力上限减少时防止之”，因此一次减少即消耗全部额度。
	_set_max_hp_guard(0)
	announce_activation({"target_id":owner_player_id, "prevented_max_hp_loss":true})
	event.cancel("xiongxing_max_hp_guard")


## 持有者阵亡后清除自身的上限保护额度；上限保护是爻光自己的收益，随持有者死亡失去意义。
## 层数与预留标记不在这里处理：它们属于被施加的角色，由该角色身上的效果实例自行清理。
func _on_player_died(event: RuleEvent) -> void:
	if event.player_id == owner_player_id:
		_set_max_hp_guard(0)


## 覆盖基类的持有者有效性校验：爻光阵亡后仍需执行一次自身清理，清掉残留的上限保护额度。
## 放行范围严格限定为 dieAfter，且该回调只删除已经失效的状态、不产生任何新收益；
## 伤害结算刻意不在这里放行——它已由挂在目标身上的角色持续效果独立承担，与爻光是否存活无关，
## 因此不需要（也不应该）让死亡的爻光重新接收任何伤害时机。
func can_trigger_while_owner_inactive(event: RuleEvent) -> bool:
	if event == null:
		return false
	return event.name == "dieAfter"


## 返回持有者当前剩余的“防止下次体力上限减少”次数；未记录时返回0。
func _get_max_hp_guard() -> int:
	var owner_player: PlayerState = _get_player(owner_player_id)
	if owner_player == null:
		return 0
	return maxi(int(owner_player.character_form_state.get(MAX_HP_GUARD_STATE_KEY, 0)), 0)


## 写入持有者的上限保护次数；次数不大于0时删除键，避免存档留下无意义条目。
func _set_max_hp_guard(guard_count: int) -> void:
	var owner_player: PlayerState = _get_player(owner_player_id)
	if owner_player == null:
		return
	if maxi(guard_count, 0) <= 0:
		owner_player.character_form_state.erase(MAX_HP_GUARD_STATE_KEY)
		return
	owner_player.character_form_state[MAX_HP_GUARD_STATE_KEY] = guard_count


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


## 为AI评估凶星的目标选择；按威胁（集火价值）与敌我态度给分，并在满足条件时优先选择自己。
##
## 评分有意使用统一威胁尺度：集火价值的权重最高，因此“给最该被集火的敌人叠层”稳定优于
## 给低威胁目标叠层；满足“自身体力上限为1且我方欢愉技明显占优”时改为把分数压在自己身上，
## 因为此时自选带来的“防止上限减少”能对冲后续自减上限的代价，与需求给出的AI口径一致。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理凶星的目标选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return 0.0
	# 动作负载；凶星必须选定一名角色，未确认或数量不符由权威端拒绝，AI不应主动提交。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；数量不等于1时判为无效动作。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() != TARGET_COUNT:
		return -20.0
	# 当前目标ID；与持有者相同时走自选分支。
	var target_id: int = int(selected_targets[0])
	# 自身体力上限；只有上限恰为1时自选才有对冲价值。
	var self_max_hp: int = int(evaluator.get_player(authoritative_snapshot, owner_player_id).get("max_hp", 0))
	# 双方欢愉技数量；需求给出的自选条件之一。
	var allied_joy_count: int = int(evaluator.get_side_joy_skill_count(authoritative_snapshot, owner_player_id, true))
	var hostile_joy_count: int = int(evaluator.get_side_joy_skill_count(authoritative_snapshot, owner_player_id, false))
	# 自选条件；两个条件必须同时成立。
	var prefer_self: bool = self_max_hp == AI_SELF_PREFER_MAX_HP and allied_joy_count - hostile_joy_count >= AI_SELF_PREFER_JOY_ADVANTAGE
	if target_id == owner_player_id:
		return AI_SELF_TARGET_SCORE if prefer_self else AI_SELF_TARGET_FALLBACK_SCORE
	if prefer_self:
		return -AI_SELF_TARGET_SCORE
	# 常规评分；威胁越高越优先，友方目标按态度反向扣分。
	var threat: float = float(evaluator.get_threat(authoritative_snapshot, owner_player_id, target_id))
	var attitude: float = float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id))
	return threat * AI_THREAT_WEIGHT - attitude * AI_ATTITUDE_WEIGHT + AI_BASE_TARGET_SCORE
