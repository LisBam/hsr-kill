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

## AI：留桃判定是否按真实阵营关系识别队友；true 表示采用无名杀 get.realAttitude 口径。
## 依据：留牌与弃牌不产生任何可被真人观察到的行为，读取权威真实身份不会让隐藏身份的AI显得“未卜先知”；
## 而身份模式开局只有领袖公开，暴露度态度恒为0，严格照搬暴露度口径会让“为队友留桃”变成永不触发的规则。
## 目标选择、伤害与救援去向等可见决策仍严格使用暴露度态度，完全不受本开关影响。
const AI_KEEP_TAO_TRUST_TRUE_IDENTITY_FOR_ALLY: bool = true

## AI：判定“珍贵牌”的价值公式基数，对应无名杀 `min = 8.1 - 4.5 * hp / maxHp`。
## 语义：手牌中价值不低于该门槛的牌被视为“本回合不想丢的牌”，用于计算手牌溢出数量。
const AI_KEEP_TAO_PRECIOUS_VALUE_BASE: float = 8.1

## AI：判定“珍贵牌”的价值公式体力系数；自己体力比例越高，门槛越低，珍贵牌判定越宽松。
const AI_KEEP_TAO_PRECIOUS_VALUE_HP_SCALE: float = 4.5

## AI：手牌溢出数量严格大于该值时直接吃掉【桃】，对应无名杀 `if (nd > 2) return 2`。
const AI_KEEP_TAO_OVERFLOW_DECLINE_THRESHOLD: int = 2

## AI：手牌已经有溢出时使用的初始保留分，对应无名杀 `keep = nd ? 0 : 2` 的0分支。
## 语义：反正要弃牌时“留牌”的边际收益下降，保留分从0起步，只有队友危险度足够高才重新超过阈值。
const AI_KEEP_TAO_OVERFLOW_BASE_KEEP: float = 0.0

## AI：手上【桃】多于一张且已经出现手牌溢出时的判定门槛，对应无名杀 `taos.length > 1 && nd > 1`。
const AI_KEEP_TAO_MULTI_TAO_OVERFLOW_THRESHOLD: int = 1

## AI：动态保留价值里“可能要被我这张桃救到”的体力上界，对应无名杀 ai.basic.useful 的 `current.hp <= 2`。
const AI_TAO_HOLD_RESCUE_MAX_HP: int = 2

## AI：动态保留价值里“濒死待救”的体力上界；体力不超过该值累加 needs。
const AI_TAO_HOLD_NEEDS_MAX_HP: int = 1

## AI：动态保留价值里“受伤待救”的精确体力；体力正好等于该值时累加 damaged。
const AI_TAO_HOLD_DAMAGED_HP: int = 2

## AI：动态保留价值里判定“这算我的人”的态度下界；无名杀使用严格大于0，因此0.0表示必须为正态度。
const AI_TAO_HOLD_ALLY_ATTITUDE: float = 0.0

## AI：同时存在濒死与受伤待救对象时每个 needs 的权重，对应无名杀 `5 * needs + 3 * damaged`。
const AI_TAO_HOLD_NEEDS_WEIGHT: float = 5.0

## AI：同时存在濒死与受伤待救对象时每个 damaged 的权重。
const AI_TAO_HOLD_DAMAGED_WEIGHT: float = 3.0

## AI：多名对象等待救援（或无濒死、只有多人受伤）时的保留价值，对应无名杀 `return 8`。
const AI_TAO_HOLD_MULTI_DANGER: float = 8.0

## AI：没有人等待救援、但自己体力比例偏低时的保留价值基数，对应无名杀 `7 + |hp/maxHp - 0.5|`。
const AI_TAO_HOLD_SELF_WOUNDED_BASE: float = 7.0

## AI：自己体力比例的判定线；低于该比例时按自身危险度抬高这张桃的保留价值。
const AI_TAO_HOLD_SELF_WOUNDED_RATIO: float = 0.7

## AI：上面公式中的比例偏移量；体力比例越远离该值，说明自己越危险，留牌价值越高。
const AI_TAO_HOLD_SELF_WOUNDED_RATIO_OFFSET: float = 0.5

## AI：只有濒死对象等待救援时的保留价值，对应无名杀 `if (needs) return 7`。
const AI_TAO_HOLD_NEEDS_ONLY: float = 7.0

## AI：只有受伤对象等待救援时的保留价值基数，对应无名杀 `Math.max(3, 7.8 - i)`。
const AI_TAO_HOLD_DAMAGED_ONLY_BASE: float = 7.8

## AI：只有受伤对象等待救援时的价值下界。
const AI_TAO_HOLD_DAMAGED_ONLY_MIN: float = 3.0

## AI：没有任何人需要救援时的保留价值基数，对应无名杀 `Math.max(1, 7.2 - i)`。
const AI_TAO_HOLD_IDLE_BASE: float = 7.2

## AI：动态保留价值的取值下界；连自己都满体力且无人受伤时，这张桃只值最低分。
const AI_TAO_HOLD_MIN: float = 1.0

## AI：手上第2张及以后同名【桃】的价值衰减步长，对应无名杀 `- i` 中的同名牌序号。
const AI_TAO_HOLD_DUPLICATE_DECAY: float = 1.0

## AI：动态保留价值的取值上界；同名牌公式在极端场面会超过10分，这里截断到全项目通用的十档分。
const AI_TAO_HOLD_MAX: float = 10.0


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
## 补充：弃牌阶段反正要丢掉这张桃（手牌已超过上限）与手牌溢出两张以上珍贵牌同样归入“先吃掉”，对应无名杀提前返回的两个分支。
func _should_keep_tao_for_ally(authoritative_snapshot: Dictionary, actor_id: int, evaluator: Object) -> bool:
	# 行动者快照；缺失时不做任何留牌判断，保持通用评分以兼容异常调用。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return false
	# 行动者体力；自保分支、稀缺降级与危险度累加都要读取同一个权威数值。
	var actor_hp: int = int(actor.get("hp", 0))
	# 当前手牌上限；等于体力加各类上限加成，是判断“这张桃本回合是否留得住”的规则依据。
	var hand_limit: int = _get_hand_limit(actor)
	# 自己手上【桃】的数量；自己手牌对本人完全可见，因此这里是精确值而不是估算值。
	var own_tao_count: int = _count_own_tao_cards(actor)
	# 手上的【桃】已经超过手牌上限；弃牌阶段必然要丢掉其中一张，此时留桃等于白留，先吃掉更划算。
	# 对应无名杀 `needsToDiscard(0, i => !canIgnoreHandcard(i) && taos.includes(i))` 的提前返回。
	if own_tao_count > hand_limit:
		return false
	# 当前手牌溢出数量；含义是本回合弃牌阶段必须放弃的珍贵牌张数，对应无名杀 needsToDiscard 的 nd。
	var overflow_count: int = _count_hand_overflow_cards(authoritative_snapshot, actor_id, evaluator, hand_limit)
	# 手牌溢出过多；必须弃掉两张以上珍贵牌时，把这张桃换成体力比留着更实际，对应无名杀 `if (nd > 2) return 2`。
	if overflow_count > AI_KEEP_TAO_OVERFLOW_DECLINE_THRESHOLD:
		return false
	# 手上不止一张【桃】且已经出现溢出；多张桃的救援价值已经由溢出抵消，先自愈。
	if own_tao_count > 1 and overflow_count > AI_KEEP_TAO_MULTI_TAO_OVERFLOW_THRESHOLD:
		return false
	# 手上不止一张【桃】且体力已经撑不住溢出张数；对应无名杀 `nd && player.hp < 1 + taos.length`。
	if own_tao_count > 1 and overflow_count > 0 and actor_hp < 1 + own_tao_count:
		return false
	# 自己是领袖且已经受伤；领袖阵亡直接结束对局，因此把桃用在自己身上优先于支援队友。
	# 补充：手牌已经装不下救命牌（溢出大于0）时同样先自愈，对应无名杀 `target.identity === "zhu" && (nd || target.hp < 3)`。
	if str(actor.get("identity", "")) == "leader" and (overflow_count > 0 or actor_hp < AI_KEEP_TAO_LEADER_CRITICAL_HP):
		return false
	# 场上没有任何把我当队友的存活角色；没有救援对象时留桃没有任何意义。
	if not _has_friendly_teammate(authoritative_snapshot, actor_id, evaluator):
		return false
	# 保留分初值；对应无名杀无手牌溢出时的 `keep = 2`。
	# 补充：已经出现溢出时改用无名杀 `keep = nd ? 0 : 2` 的0分支，从0起步等待队友危险度把它推回阈值以上。
	var keep_score: float = AI_KEEP_TAO_OVERFLOW_BASE_KEEP if overflow_count > 0 else AI_KEEP_TAO_BASE_KEEP
	# 友方领袖残血；此时任何队友都可能在下一次伤害中直接终局，按固定保留分留桃且不参与稀缺降级。
	# 补充：该分支在无名杀里位于“溢出两张或自己体力低于2”之前，因此领袖残血时仍会留桃给领袖。
	var endangered_leader: bool = _has_endangered_leader(authoritative_snapshot, actor_id, evaluator)
	if endangered_leader:
		keep_score = AI_KEEP_TAO_LEADER_KEEP
	# 自己体力已经极低；此时先保证自己不被击杀，与无名杀“hp 低于2先吃桃”的自保分支一致。
	# 补充：没有残血友方领袖时，溢出正好两张同样先自愈，对应无名杀 `if (nd === 2 || player.hp < 2) return 2`。
	elif overflow_count == 2 or actor_hp <= AI_KEEP_TAO_SELF_CRITICAL_HP:
		return false
	# 必须弃两张珍贵牌且自己已经濒危；此时留桃既救不了领袖也救不了自己，先自愈。
	# 对应无名杀 `if (nd === 2 && player.hp <= 1) return 2`，它排在领袖分支之后但排在“保留分为3直接留桃”之前。
	if overflow_count == 2 and actor_hp <= AI_KEEP_TAO_SELF_CRITICAL_HP:
		return false
	# 领袖残血分支直接判定留桃；该分支不受自己手上桃数影响，因为领袖阵亡会让留牌收益全部失效。
	if endangered_leader:
		return true
	# 桃相对自己体力偏少；按无名杀口径降级保留分，让AI在自己也可能被打死时优先自愈。
	if own_tao_count * 2 <= actor_hp:
		keep_score = AI_KEEP_TAO_SCARCE_KEEP
	# 队友危险度累加；只有关系够铁、体力低于3点、并且比我更危险的队友才按体力差累加保留分。
	# 补充：无名杀把该循环写在 `if (keep && …)` 之内，因此保留分为0（本回合反正要弃牌且桃并不稀缺）时会**完全跳过**
	# 该循环并直接吃掉这张桃；这里保持同一行为，避免“反正要弃牌却仍为队友留桃”的反直觉结论。
	if keep_score > 0.0:
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
			if _get_keep_tao_attitude(authoritative_snapshot, actor_id, ally_id, evaluator) <= AI_KEEP_TAO_ALLY_ATTITUDE:
				continue
			keep_score += float(actor_hp - ally_hp)
	return keep_score > AI_KEEP_TAO_DANGER_THRESHOLD


## 计算【桃】在当前持有者手中的动态保留价值；移植无名杀 standard.js 中【桃】的 ai.basic.useful 分档公式。
## 返回值为“这张桃留在我手上值多少分”：有人可能被我救活时价值升到7至9分，无人需要救援时只按自己体力比例估值。
## 该值同时参与留牌、弃牌与用牌机会成本，因此它是“AI 愿意为队友留桃”的通用价值来源，而不只是单条判定分支。
func modify_ai_hand_value(authoritative_snapshot: Dictionary, owner_id: int, current_value: float, evaluator: Object) -> float:
	# 持有者快照；缺失时保持静态价值，异常调用不得伪造动态价值。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_id)
	if owner.is_empty():
		return current_value
	# 濒死待救对象数量；体力不超过阈值且属于我方时累加，对应无名杀 useful 中的 needs。
	var needs_count: int = 0
	# 受伤待救对象数量；体力正好为2且属于我方时累加，对应无名杀 useful 中的 damaged。
	var damaged_count: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前待救候选；已阵亡或已离场的角色不再需要救援。
		var candidate: Dictionary = player_variant as Dictionary
		if not bool(candidate.get("alive", false)) or bool(candidate.get("out_of_game", false)):
			continue
		# 当前候选ID；用于查询“我是否愿意救他”。
		var candidate_id: int = int(candidate.get("player_id", -1))
		if candidate_id < 0:
			continue
		# 当前候选体力；高于救援上界时这张桃对他没有意义，直接跳过。
		var candidate_hp: int = int(candidate.get("hp", 0))
		if candidate_hp > AI_TAO_HOLD_RESCUE_MAX_HP:
			continue
		# 我对该候选的态度；无名杀要求严格大于0，敌人与路人不会抬高这张桃的价值。
		if _get_keep_tao_attitude(authoritative_snapshot, owner_id, candidate_id, evaluator) <= AI_TAO_HOLD_ALLY_ATTITUDE:
			continue
		if candidate_hp <= AI_TAO_HOLD_NEEDS_MAX_HP:
			needs_count += 1
		elif candidate_hp == AI_TAO_HOLD_DAMAGED_HP:
			damaged_count += 1
	# 自己的体力比例；体力上限异常为0时按1处理，避免除零并让危险度保持可计算。
	var hp_ratio: float = float(int(owner.get("hp", 0))) / float(maxi(int(owner.get("max_hp", 1)), 1))
	# 同名牌序号；手上第2张及以后的【桃】逐张衰减，表达“再留一张”的边际价值下降。
	var duplicate_index: float = float(maxi(_count_own_tao_cards(owner) - 1, 0))
	# 动态保留价值；按无名杀 useful 的判定顺序逐档取值。
	var hold_value: float = AI_TAO_HOLD_IDLE_BASE
	if needs_count > 0 and damaged_count > 0:
		# 两种待救状态同时存在；价值按权重线性叠加，对应 `5 * needs + 3 * damaged`。
		hold_value = AI_TAO_HOLD_NEEDS_WEIGHT * float(needs_count) + AI_TAO_HOLD_DAMAGED_WEIGHT * float(damaged_count)
	elif needs_count + damaged_count > 1:
		# 多人等待救援；提升到固定高档，对应 `return 8`。
		hold_value = AI_TAO_HOLD_MULTI_DANGER
	elif hp_ratio < AI_TAO_HOLD_SELF_WOUNDED_RATIO:
		# 无人待救但自己体力比例偏低；按自己离一半体力的距离抬高价值，对应 `7 + |hp/maxHp - 0.5|`。
		hold_value = AI_TAO_HOLD_SELF_WOUNDED_BASE + absf(hp_ratio - AI_TAO_HOLD_SELF_WOUNDED_RATIO_OFFSET)
	elif needs_count > 0:
		# 只有濒死对象；对应 `return 7`。
		hold_value = AI_TAO_HOLD_NEEDS_ONLY
	elif damaged_count > 0:
		# 只有受伤对象；对应 `Math.max(3, 7.8 - i)`。
		hold_value = maxf(AI_TAO_HOLD_DAMAGED_ONLY_BASE - duplicate_index * AI_TAO_HOLD_DUPLICATE_DECAY, AI_TAO_HOLD_DAMAGED_ONLY_MIN)
	else:
		# 没有任何人需要救援；对应 `Math.max(1, 7.2 - i)`，此时这张桃只是普通手牌。
		hold_value = maxf(AI_TAO_HOLD_IDLE_BASE - duplicate_index * AI_TAO_HOLD_DUPLICATE_DECAY, AI_TAO_HOLD_MIN)
	return clampf(hold_value, AI_TAO_HOLD_MIN, AI_TAO_HOLD_MAX)


## 统计行动者普通手牌中的【桃】数量；只读取本人完全可见的手牌，不使用任何推测性的隐藏信息。
## 补充：入参既可以是行动者，也可以是任意手牌持有者（动态保留价值按持有者统计同名牌数量），因此本函数不读取身份或回合信息。
func _count_own_tao_cards(actor: Dictionary) -> int:
	# 计数结果；手牌缺失或不是数组时返回0，按“没有桃”处理。
	var tao_count: int = 0
	for card_variant: Variant in actor.get("hand", []) as Array:
		# 当前手牌实体快照；逻辑牌名由 definition_id 表示，手牌视为时已写入视为后的定义。
		var card: Dictionary = card_variant as Dictionary
		if str(card.get("definition_id", "")) == get_id():
			tao_count += 1
	return tao_count


## 返回快照口径的手牌上限；与 PlayerState.get_hand_limit() 同义，供无宿主 AI 判断手牌溢出。
func _get_hand_limit(actor: Dictionary) -> int:
	return maxi(int(actor.get("hp", 0)) + int(actor.get("hand_limit_bonus", 0)) + int(actor.get("mode_hand_limit_bonus", 0)), 0)


## 统计持有者本回合弃牌阶段必须放弃的珍贵牌张数；移植无名杀 needsToDiscard 的 nd 口径。
## 判定：手牌中保留价值不低于动态门槛（8.1 - 4.5 * 体力 / 体力上限）的牌视为珍贵牌，超出上限的部分即为溢出。
## 补充：【桃】本身无论当前价值多少都计入珍贵牌，与无名杀过滤条件 `taos.includes(i) || get.value(i) >= min` 一致。
func _count_hand_overflow_cards(authoritative_snapshot: Dictionary, owner_id: int, evaluator: Object, hand_limit: int) -> int:
	# 持有者快照；缺失时按没有溢出处理，避免异常调用放大留桃判定。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_id)
	if owner.is_empty():
		return 0
	# 持有者体力与体力上限；上限异常时按1处理，保证门槛始终可计算。
	var hp: int = int(owner.get("hp", 0))
	var max_hp: int = maxi(int(owner.get("max_hp", 1)), 1)
	# 珍贵牌门槛；自己体力比例越高门槛越低，普通手牌也会被算作“本回合不想丢”。
	var precious_threshold: float = AI_KEEP_TAO_PRECIOUS_VALUE_BASE - AI_KEEP_TAO_PRECIOUS_VALUE_HP_SCALE * float(hp) / float(max_hp)
	# 珍贵手牌数量；只统计本人完全可见的手牌，未公开牌面不会被猜测。
	var precious_count: int = 0
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌实体；价值统一由评估器按定义ID与持有者计算，包含卡牌文件提供的动态价值。
		var card: Dictionary = card_variant as Dictionary
		# 当前手牌的逻辑牌名；与 get_id() 相同说明这张牌本身就是【桃】，按无名杀口径无条件计入珍贵牌。
		var card_id: String = str(card.get("definition_id", ""))
		if card_id == get_id() or evaluator.get_card_value_by_id(card_id, authoritative_snapshot, owner_id) >= precious_threshold:
			precious_count += 1
	return maxi(precious_count - hand_limit, 0)


## 返回留桃判定使用的阵营态度；按 AI_KEEP_TAO_TRUST_TRUE_IDENTITY_FOR_ALLY 在真实态度与暴露度态度之间选择。
func _get_keep_tao_attitude(authoritative_snapshot: Dictionary, actor_id: int, other_id: int, evaluator: Object) -> float:
	if AI_KEEP_TAO_TRUST_TRUE_IDENTITY_FOR_ALLY:
		# 真实阵营态度；等于无名杀 get.realAttitude，隐藏身份时也能认出同一阵营的队友。
		return float(evaluator.get_real_attitude(authoritative_snapshot, actor_id, other_id))
	# 暴露度态度；只有被公开行为识别出的身份才提供态度，AI 表现得“装作不知道”。
	return float(evaluator.get_attitude(authoritative_snapshot, actor_id, other_id))


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
		if float(_get_keep_tao_attitude(authoritative_snapshot, other_id, actor_id, evaluator)) > AI_KEEP_TAO_FRIEND_ATTITUDE:
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
		if float(_get_keep_tao_attitude(authoritative_snapshot, actor_id, leader_id, evaluator)) > AI_KEEP_TAO_FRIEND_ATTITUDE:
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
