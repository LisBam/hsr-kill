extends CardDefinition

## 【桃】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。
## 出牌阶段（自我回复）与濒死救援共用同一张牌，AI 的“留桃”判断只作用于出牌阶段的自我回复。

## AI：为队友留桃时视为队友的最低态度；2.0 对应无名杀【桃】target_use 中“态度大于2才算铁杆队友”的口径。
## 数值含义：态度取值为无名杀标准身份表（-10至10），越大的正值表示关系越铁。
const AI_KEEP_TAO_ALLY_ATTITUDE: float = 2.0

## AI：判定“场上有队友”所需的最低反向态度；0.0 表示只要有人把我当队友就算有队友。
## 方向与队友态度相反：无名杀 hasFriend() 读取的是“别人对我的态度”，因为愿意救我的人才决定留桃的意义。
const AI_KEEP_TAO_FRIEND_ATTITUDE: float = 0.0

## AI：队友被视为“可能需要救援”的体力上界；只有体力低于3点的队友才值得为他把桃留下。
## 满血队友下一回合前被一击打死的概率低，为满血队友留桃会让AI白白放弃本回合的回复。
const AI_KEEP_TAO_ALLY_MAX_HP: int = 3

## AI：留桃判定的初始保留分；无手牌溢出时固定2.0，对应无名杀 `keep = nd ? 0 : 2` 在 nd 为0时的取值。
## 保留分不是收益分，而是“我为什么理由留下这张桃”的权重累加器：初值越高越容易判定为留桃。
const AI_KEEP_TAO_BASE_KEEP: float = 2.0

## AI：手上【桃】的数量不超过“自己体力的一半”时使用的降级保留分，对应无名杀 `keep = 1`。
## 语义：桃相对自己的体力偏少时先顾自己，避免把唯一的救命牌留给别人而自己先倒下。
const AI_KEEP_TAO_SCARCE_KEEP: float = 1.0

## AI：友方领袖残血分支的固定保留分，对应无名杀 `if (keep === 3) return 0`。
## 该分支在桃稀缺降级之前判定，因此领袖残血时不受自己手上桃数的削弱；3.0 严格大于危险度阈值2.0，必然留桃。
const AI_KEEP_TAO_LEADER_KEEP: float = 3.0

## AI：保留分严格大于该值时判定留桃，对应无名杀 `if (keep > 2) return 0`。
const AI_KEEP_TAO_DANGER_THRESHOLD: float = 2.0

## AI：自己体力不超过该值时优先自愈；1点表示“自己已濒死，先确保自己不被击杀”。
const AI_KEEP_TAO_SELF_CRITICAL_HP: int = 1

## AI：友方领袖体力低于该值时无条件留桃；领袖阵亡直接结束对局，优先级高于任何普通队友。
const AI_KEEP_TAO_LEADER_CRITICAL_HP: int = 3

## AI：判定为留桃时对本张【桃】的扣分；取值高于通用评分上限，保证动作分被压到出牌阈值以下。
const AI_KEEP_TAO_PENALTY: float = 8.0

## AI：判定为留桃时返回的固定分；严格小于0即可让策略层放弃本动作并结束出牌阶段。
const AI_KEEP_TAO_DECLINE_SCORE: float = -0.01


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "tao",
		"original_name": "桃",
		"custom_name": "药",
		"type": "basic",
		"subtype": "recover",
		"effect_id": "peach",
		"nature": "normal",
		"target_mode": "self_wounded",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "tao",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段仅对已受伤的自己使用，回复1点体力；其他角色濒死时可在救援响应中对其使用。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "tao",
		"ai": {"order":2.0, "value":9.0, "target_result":2.0, "recover":true, "save":true, "beneficial":true},
		"ai_use_value": 8.0,
		"ai_target_attitude": "friendly",
	})


## 执行【桃】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		_begin_recovery(resolver.host, actor_id, target_id, {"card_uid":card.uid, "card_id":card.definition_id})
	return resolver.default_destination()


## 【桃】允许任意存活角色在濒死窗口中响应并救援当前目标。
func get_dying_response_pattern(_responder_id: int, _dying_player_id: int) -> String:
	return str(get_metadata().get("provided_response_pattern", ""))


## 修正出牌阶段【桃】的动作评分；只决定“现在回自己血”还是“把这张桃留给队友”。
##
## 设计口径参考无名杀 standard.js 中【桃】的 ai.result.target_use：
## 它返回 2 表示可以使用（吃掉）、返回 0 表示不要使用（留牌），因此留桃不是一条独立规则，
## 而是【桃】自身对“本回合回复”与“后续救援队友”的机会成本比较。本方法把该判定移植为纯粹的评分扣减，
## 判定为留桃时把动作分压到策略层的接受阈值以下，AI 便会主动结束出牌阶段而不是浪费这张桃。
##
## 只影响 AI 决策：不改变回复量、目标范围、濒死救援顺序与任何规则状态。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	if _should_keep_tao_for_ally(authoritative_snapshot, int(action.get("actor_id", -1)), evaluator):
		# 留桃分数；扣分后再 clamp 到严格负值，避免高收益场景下扣分不足而仍然吃掉这张桃。
		return minf(current_score - AI_KEEP_TAO_PENALTY, AI_KEEP_TAO_DECLINE_SCORE)
	return current_score


## 判断AI是否应当保留这张【桃】而不在本回合回复自己；返回 true 表示留桃。
## 判定顺序与无名杀一致：先排除“没有队友”“自己更危险”“自己是领袖”“领袖残血”的分支，再按保留分累计队友危险度。
func _should_keep_tao_for_ally(authoritative_snapshot: Dictionary, actor_id: int, evaluator: Object) -> bool:
	# 行动者快照；缺失时不做任何留牌判断，保持通用评分以兼容异常调用。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return false
	# 行动者体力；自保分支、稀缺降级与危险度累加都要读取同一个权威数值。
	var actor_hp: int = int(actor.get("hp", 0))
	# 自己体力已经极低；此时先保证自己不被击杀，与无名杀“hp 低于2先吃桃”的自保分支一致。
	if actor_hp <= AI_KEEP_TAO_SELF_CRITICAL_HP:
		return false
	# 自己是领袖且已经受伤；领袖阵亡直接结束对局，因此把桃用在自己身上优先于支援队友。
	if str(actor.get("identity", "")) == "leader" and actor_hp < AI_KEEP_TAO_LEADER_CRITICAL_HP:
		return false
	# 场上没有任何把我当队友的存活角色；没有救援对象时留桃没有任何意义。
	if not _has_friendly_teammate(authoritative_snapshot, actor_id, evaluator):
		return false
	# 友方领袖残血；此时任何队友都可能在下一次伤害中直接终局，按固定保留分留桃且不参与稀缺降级。
	if _has_endangered_leader(authoritative_snapshot, actor_id, evaluator):
		return AI_KEEP_TAO_LEADER_KEEP > AI_KEEP_TAO_DANGER_THRESHOLD
	# 保留分初值；对应无名杀无手牌溢出时的 `keep = 2`。
	var keep_score: float = AI_KEEP_TAO_BASE_KEEP
	# 自己手上【桃】的数量；自己手牌对本人完全可见，因此这里是精确值而不是估算值。
	var own_tao_count: int = _count_own_tao_cards(actor)
	# 桃相对自己体力偏少；按无名杀口径降级保留分，让AI在自己也可能被打死时优先自愈。
	if own_tao_count * 2 <= actor_hp:
		keep_score = AI_KEEP_TAO_SCARCE_KEEP
	# 队友危险度累加；只有关系够铁、体力低于3点、并且比我更危险的队友才按体力差累加保留分。
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前队友快照；保持权威座次顺序，判定与顺序无关。
		var ally: Dictionary = player_variant as Dictionary
		# 当前队友ID；跳过自己与已阵亡、已离场的角色。
		var ally_id: int = int(ally.get("player_id", -1))
		if ally_id == actor_id or not bool(ally.get("alive", false)) or bool(ally.get("out_of_game", false)):
			continue
		# 当前队友体力；满血或只差1点的队友不值得为他放弃本回合回复。
		var ally_hp: int = int(ally.get("hp", 0))
		if ally_hp >= AI_KEEP_TAO_ALLY_MAX_HP:
			continue
		# 队友并不比我更危险；我已受伤时优先照顾自己。
		if ally_hp >= actor_hp:
			continue
		# 我对该角色的态度；态度不够铁时不为他保留救命牌，避免把桃浪费在路人或敌人身上。
		if float(evaluator.get_attitude(authoritative_snapshot, actor_id, ally_id)) <= AI_KEEP_TAO_ALLY_ATTITUDE:
			continue
		keep_score += float(actor_hp - ally_hp)
	return keep_score > AI_KEEP_TAO_DANGER_THRESHOLD


## 统计行动者普通手牌中的【桃】数量；只读取本人完全可见的手牌，不使用任何推测性的隐藏信息。
func _count_own_tao_cards(actor: Dictionary) -> int:
	# 计数结果；手牌缺失或不是数组时返回0，按“没有桃”处理。
	var tao_count: int = 0
	for card_variant: Variant in actor.get("hand", []) as Array:
		# 当前手牌实体快照；逻辑牌名由 definition_id 表示，手牌视为时已写入视为后的定义。
		var card: Dictionary = card_variant as Dictionary
		if str(card.get("definition_id", "")) == get_id():
			tao_count += 1
	return tao_count


## 判断场上是否存在把我当队友的存活角色；方向与“我认为谁是队友”相反，沿用无名杀 hasFriend() 的口径，
## 因为只有愿意救援我的角色才会让我产生“留桃救人”的价值判断。
func _has_friendly_teammate(authoritative_snapshot: Dictionary, actor_id: int, evaluator: Object) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；跳过自己与已阵亡、已离场的角色。
		var other: Dictionary = player_variant as Dictionary
		# 当前角色ID；用于查询“他对我的态度”。
		var other_id: int = int(other.get("player_id", -1))
		if other_id == actor_id or not bool(other.get("alive", false)) or bool(other.get("out_of_game", false)):
			continue
		if float(evaluator.get_attitude(authoritative_snapshot, other_id, actor_id)) > AI_KEEP_TAO_FRIEND_ATTITUDE:
			return true
	return false


## 判断是否存在残血的友方领袖；领袖倒下即终局，因此它的危险度不能被普通队友危险度覆盖。
func _has_endangered_leader(authoritative_snapshot: Dictionary, actor_id: int, evaluator: Object) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；跳过自己与已阵亡、已离场的角色。
		var leader: Dictionary = player_variant as Dictionary
		# 当前角色ID；用于查询我对其态度与是否为我方领袖。
		var leader_id: int = int(leader.get("player_id", -1))
		if leader_id == actor_id or not bool(leader.get("alive", false)) or bool(leader.get("out_of_game", false)):
			continue
		if str(leader.get("identity", "")) != "leader":
			continue
		if int(leader.get("hp", 0)) >= AI_KEEP_TAO_LEADER_CRITICAL_HP:
			continue
		if float(evaluator.get_attitude(authoritative_snapshot, actor_id, leader_id)) > AI_KEEP_TAO_FRIEND_ATTITUDE:
			return true
	return false


## 应用【桃】的濒死救援效果；固定回复1点体力并记录使用者与目标。
func resolve_dying_response(match_host: Object, responder_id: int, dying_player_id: int, _card: CardInstance) -> bool:
	# 救援者与濒死目标；任一无效时不修改状态。
	var responder: PlayerState = match_host.state.get_player(responder_id)
	var target: PlayerState = match_host.state.get_player(dying_player_id)
	if responder == null or target == null or not responder.alive or not target.alive:
		return false
	_begin_recovery(match_host, responder_id, dying_player_id, {"card_id":get_id(), "dying_response":true})
	match_host.add_log("%s对%s使用【桃】。" % [responder.display_name, target.display_name])
	return true


## 普通使用与求桃共用两步内容；taoBegin结束前不修改体力。
func _begin_recovery(match_host: Object, actor_id: int, target_id: int, data: Dictionary) -> void:
	# 原目标代次；等待中的换将不能把旧桃效果交给新武将。
	var target: PlayerState = match_host.state.get_player(target_id)
	if target == null:
		return
	# 每个可交互效果独占一步；回复内部仍由统一回复组件编排。
	var steps: Array[Callable] = [_begin_timing.bind(match_host), _apply_recovery.bind(match_host)]
	match_host.run_rule_sequence(steps, {"actor_id":actor_id, "target_id":target_id, "generation":target.character_generation, "data":data})


## 保存原始时机对象；异步取消需要在后续步骤读取最终状态。
func _begin_timing(sequence: RuleStepSequence, match_host: Object) -> void:
	match_host.emit_sequence_timing(sequence, "taoBegin", int(sequence.context.actor_id), int(sequence.context.actor_id), int(sequence.context.target_id), sequence.context.data)


## 前置取消只阻止效果，不撤销已使用的桃；合法目标固定回复1点。
func _apply_recovery(sequence: RuleStepSequence, match_host: Object) -> void:
	if sequence.waiting_event != null and (sequence.waiting_event.cancelled or sequence.waiting_event.neutralized):
		return
	# 重新读取目标实体；来源可已死亡，但效果不能作用于替换后的目标。
	var target: PlayerState = match_host.state.get_player(int(sequence.context.target_id))
	if target != null and target.character_generation == int(sequence.context.generation):
		match_host.recover(int(sequence.context.actor_id), target.player_id, 1, get_id())
