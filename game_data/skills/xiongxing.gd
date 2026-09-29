extends SkillDefinition

## 【凶星】欢愉技源码。阿哈时刻按参演编号116强制驱动：令一名角色下次受到的伤害+1；
## 若该角色为持有者本人，则改为同时提供一次“防止下次体力上限减少”。
## 效果可叠加：层数按目标身上的总层数聚合，角标在2层及以上显示为“凶星xN”。

## 目标身上“下次受伤+N”累计层数在 character_form_state 中的稳定键名。
## 该字段随权威存档往返、不进入公开快照；改名会使旧存档中的层数失效，必须保持稳定。
const DAMAGE_STACK_STATE_KEY: String = "xiongxing_damage_stacks"

## 持有者自选凶星时提供的“防止下次体力上限减少”剩余次数键名；只写入持有者自己的 character_form_state。
const MAX_HP_GUARD_STATE_KEY: String = "xiongxing_max_hp_guard"

## 单次发动叠加的层数；固定1层，与原文“下次受到的伤害+1”一致。
const STACK_PER_PERFORMANCE: int = 1

## 单层凶星提供的伤害加成；固定1点，多层时累加为“下次受到的伤害+N”。
const DAMAGE_BONUS_PER_STACK: int = 1

## 目标身上“已预留加成、尚未结算”的伤害事件ID键名。
## 该标记按目标存放而不是写进伤害事件的 data：伤害各修改窗口的 data 不保证是同一份字典，
## 而按目标存放还能让多名义光共享同一份预留状态，避免同一伤害被重复加成。
const RESERVED_EVENT_STATE_KEY: String = "xiongxing_reserved_damage_event_id"

## 角标条目ID；不带来源玩家后缀，因为层数已按目标聚合，同一目标只需要一条凶星文本。
const CORNER_ENTRY_ID: String = "xiongxing"

## 角标基础文本；1层时显示该文本。
const CORNER_TEXT_BASE: String = "凶星"

## 角标多层后缀前缀；达到多层阈值后显示为“凶星xN”。
const CORNER_TEXT_STACK_PREFIX: String = "x"

## 角标显示层数后缀的最小层数；固定2，对应“大于等于2层时才显示x”。
const CORNER_TEXT_STACK_DISPLAY_MIN: int = 2

## 凶星文本在武将牌左上角组合条目中的排序值；50与【酩酊】【追歼】同档，使短期受击提示优先于回合统计文本。
const CORNER_TEXT_ORDER: int = 50

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


## 订阅伤害修改、伤害结果、体力上限减少与死亡清理；层数只由 character_form_state 与武将牌角标表达。
func install() -> void:
	subscribe_timing("damageBegin3", _on_damage_begin_three, "global")
	subscribe_timing("damage", _on_damage_happened, "global")
	subscribe_timing("damageCancelled", _on_damage_not_happened, "global")
	subscribe_timing("damageZero", _on_damage_not_happened, "global")
	subscribe_timing("loseMaxHpBefore", _on_lose_max_hp_before, "target")
	subscribe_timing("dieAfter", _on_player_died, "global")
	# 读档或技能重装后按权威层数自愈本人角标；目标身上的角标随存档恢复，无需在此重建。
	_refresh_corner_text(owner_player_id, _get_damage_stacks(owner_player_id))


## 卸载技能时按当前真实层数刷新本人角标，不误删其他爻光施加在同一角色上的层数提示。
func uninstall() -> void:
	_refresh_corner_text(owner_player_id, _get_damage_stacks(owner_player_id))
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
	# 叠加后的层数；先读后写，保证多名爻光施加同一目标时层数正确累加而不是互相覆盖。
	var next_stacks: int = _get_damage_stacks(target_id) + STACK_PER_PERFORMANCE
	_set_damage_stacks(target_id, next_stacks)
	# 自选附加效果提供的上限保护次数；只有目标为持有者本人时累加，其他角色不获得该保护。
	var guard_count: int = 0
	if target_id == owner_player_id:
		guard_count = _get_max_hp_guard() + STACK_PER_PERFORMANCE
		_set_max_hp_guard(guard_count)
	announce_activation({"target_id":target_id, "stacks":next_stacks, "max_hp_guard_count":guard_count})
	finish_joy_skill_performance()


## 在第三伤害修改窗口把目标身上的全部凶星层数一次性计入本次伤害；层数在伤害实际成立时才消费。
func _on_damage_begin_three(event: RuleEvent) -> void:
	# 本次伤害目标；角色不存在时无从读取层数与预留状态。
	var target: PlayerState = _get_player(event.target_id)
	if target == null:
		return
	# 目标身上的层数；为0表示该目标当前没有凶星，直接跳过。
	var stacks: int = _get_damage_stacks(event.target_id)
	if stacks <= 0:
		return
	# 当前伤害事件ID；缺失时无法做幂等保护，宁可不加成也不冒重复加成的风险。
	var damage_event_id: int = int(event.data.get("damage_event_id", -1))
	if damage_event_id < 0:
		return
	# 预留幂等；目标身上已有任何未结算预留时不再加成。
	# 该判断同时覆盖两种重复来源：多名义光针对同一伤害的重复加成，以及外层伤害内部嵌套出的新伤害。
	if int(target.character_form_state.get(RESERVED_EVENT_STATE_KEY, -1)) >= 0:
		return
	target.character_form_state[RESERVED_EVENT_STATE_KEY] = damage_event_id
	event.data["amount"] = maxi(int(event.data.get("amount", 0)), 0) + stacks * DAMAGE_BONUS_PER_STACK


## 伤害实际成立时消费目标身上的全部层数；凶星的每一层都作用于“下一次”，因此一次性清空。
func _on_damage_happened(event: RuleEvent) -> void:
	# 只有本次伤害确实由凶星加成过才允许消费层数，否则会把无关伤害的层数一并清掉。
	if not _release_reservation(event.target_id, int(event.data.get("damage_event_id", -1))):
		return
	_set_damage_stacks(event.target_id, 0)


## 伤害被取消或最终归零时只释放事件占用；层数继续保留给下一次真正成立的伤害。
func _on_damage_not_happened(event: RuleEvent) -> void:
	_release_reservation(event.target_id, int(event.data.get("damage_event_id", -1)))


## 释放指定角色身上的预留标记；返回本次调用是否确实清除了与给定伤害事件对应的预留。
## 该返回值同时充当“本次伤害是否由凶星加成过”的凭据，并让多名爻光共享的消费动作只成功一次。
func _release_reservation(target_id: int, damage_event_id: int) -> bool:
	var target: PlayerState = _get_player(target_id)
	if target == null or damage_event_id < 0:
		return false
	if int(target.character_form_state.get(RESERVED_EVENT_STATE_KEY, -1)) != damage_event_id:
		return false
	target.character_form_state.erase(RESERVED_EVENT_STATE_KEY)
	return true


## 无条件清除指定角色身上的预留标记；角色死亡后残留的预留不再具有任何意义。
func _clear_reservation(target_id: int) -> void:
	var target: PlayerState = _get_player(target_id)
	if target != null:
		target.character_form_state.erase(RESERVED_EVENT_STATE_KEY)


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


## 角色死亡后清除其身上的层数与自选保护额度；层数已按目标聚合，无法也不应追溯具体来源。
func _on_player_died(event: RuleEvent) -> void:
	_set_damage_stacks(event.player_id, 0)
	# 死亡角色身上的预留标记同样失去意义；残留会让后续同名伤害事件ID被误判为已加成。
	_clear_reservation(event.player_id)
	if event.player_id == owner_player_id:
		_set_max_hp_guard(0)


## 返回目标身上当前的凶星层数；角色不存在或未记录时返回0。
func _get_damage_stacks(target_id: int) -> int:
	var target: PlayerState = _get_player(target_id)
	if target == null:
		return 0
	return maxi(int(target.character_form_state.get(DAMAGE_STACK_STATE_KEY, 0)), 0)


## 写入目标身上的凶星层数并同步刷新其角标；层数不大于0时删除键并移除角标。
func _set_damage_stacks(target_id: int, stacks: int) -> void:
	var target: PlayerState = _get_player(target_id)
	if target == null:
		return
	# 规范化层数；负数统一按0处理，避免异常输入产生“负层数”导致加伤异常。
	var normalized_stacks: int = maxi(stacks, 0)
	if normalized_stacks <= 0:
		target.character_form_state.erase(DAMAGE_STACK_STATE_KEY)
	else:
		target.character_form_state[DAMAGE_STACK_STATE_KEY] = normalized_stacks
	_refresh_corner_text(target_id, normalized_stacks)


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


## 按层数刷新指定角色武将牌左上角的凶星文本；1层显示“凶星”，多层显示“凶星xN”，0层移除条目。
func _refresh_corner_text(target_id: int, stacks: int) -> void:
	if host == null or not host.has_method("set_character_corner_text_entry") or not host.has_method("remove_character_corner_text_entry"):
		return
	if stacks <= 0:
		host.call("remove_character_corner_text_entry", target_id, CORNER_ENTRY_ID)
		return
	# 显示文本；低于多层阈值时只显示基础文本，达到阈值后追加层数后缀。
	var display_text: String = CORNER_TEXT_BASE
	if stacks >= CORNER_TEXT_STACK_DISPLAY_MIN:
		display_text = "%s%s%d" % [CORNER_TEXT_BASE, CORNER_TEXT_STACK_PREFIX, stacks]
	host.call("set_character_corner_text_entry", target_id, CORNER_ENTRY_ID, display_text, CORNER_TEXT_ORDER)


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
