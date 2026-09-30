extends SkillDefinition

## 【岳峙】技能源码。限定技：当一张牌指定多名角色为目标时，可成为该牌的唯一目标，并令该牌的效果对自身结算X次；
## 该牌结算期间，首次之后的伤害与回复全部被防止。（X为该牌原本的目标数）

## 成为唯一目标的确认请求种类；恢复时按该值分流。
const BECOME_SOLE_TARGET_CHOICE_KIND: String = "yuezhi_become_sole_target"

## 「指定多名角色」所需的最小目标数；数值2来自技能原文，1名目标不触发本技能。
const MINIMUM_TARGET_COUNT: int = 2

## 结算期防止伤害与回复时使用的取消原因标签；便于日志与调试区分防止来源。
const GUARD_CANCEL_REASON: String = "yuezhi_guard"

## 正在被结算期守卫保护的牌UID；-1表示当前没有牌处于守卫之下。
var _guard_card_uid: int = -1

## 结算期守卫是否生效；为true时只放行首次伤害与首次回复，其后全部防止。
var _guard_active: bool = false

## 本张牌结算期间是否已经放过一次伤害；为true时后续伤害全部被防止。
var _damage_resolved: bool = false

## 本张牌结算期间是否已经放过一次回复；为true时后续回复全部被防止。
var _recover_resolved: bool = false

## AI：接管伤害牌时要求自身保有的最低体力；不高于该值时接管会把自己推向濒死。
const AI_SELF_MIN_HP: int = 1

## AI：需要被解救的队友残血阈值；需求给出的AI提示指向“队友残血”。
const AI_ALLY_LOW_HP_THRESHOLD: int = 2

## AI：守卫只放行首次伤害，因此接管伤害牌时自身固定承受的伤害量。
const AI_SELF_DAMAGE_TAKEN: int = 1

## AI：替队友挡伤的价值折算系数；略低于纯体力收益，体现主动挡伤的战术价值。
const AI_BODYGUARD_RATIO: float = 0.9

## AI：正收益多目标牌的收益折算系数；剥夺敌方收益的同时自己还会重复获得X次。
const AI_BENEFICIAL_RATIO: float = 0.8

## 【五谷丰登】卡牌稳定定义ID；任意角色使用该牌时 AI 都无条件发动接管，不受使用者阵营限制。
## 注意：该 ID 取自卡牌文件的 id 字段（"wugu"），与文件名 wugufengdeng.gd 不同，改动前必须核对卡牌资料。
const WUGU_CARD_ID: String = "wugu"

## 询问上下文中的“牌的使用者”字段名；AI 据此判断该牌是否由队友使用。
## 该字段在创建询问时写入，使 AI 评分不必回查对局状态即可还原使用者阵营。
const CONTEXT_SOURCE_ID: String = "source_id"

## 无脑发动【五谷丰登】接管时的固定高分；确保该分支不受其他可选动作影响而必然被选中。
const AI_UNCONDITIONAL_CONFIRM_SCORE: float = 100.0


## 写入限定技静态信息；技能描述逐字保持需求提供的原文。
## 正文含“限定技”，基类据此自动标记 limited，无需额外声明。
func _init() -> void:
	super({
		"id":"yuezhi",
		"name":"岳峙",
		"trigger":"useCard",
		"ui_enabled":false,
		"limited":true,
		"description":"限定技，当一张牌指定多名角色为目标时，你可成为该牌的唯一目标，且此牌的效果对你结算X次，此牌结算期间你受到伤害/回复体力后，防止你受到伤害/回复体力直到该牌结算完毕。（X为此牌原目标数）",
	})


## 订阅整牌时机、结算期守卫窗口与死亡清理。
## useCard 属于会写回用牌上下文的整牌时机，因此在这里改写目标数组才能真正生效；
## useCardBefore / useCardBegin 等窗口不写回上下文，改写会被静默丢弃。
func install() -> void:
	subscribe_timing("useCard", _on_card_used, "global")
	subscribe_timing("damageBegin4", _on_damage_begin_four, "target")
	subscribe_timing("recoverBegin", _on_recover_begin, "target")
	subscribe_timing("useCardAfter", _on_card_after, "global")
	subscribe_timing("dieAfter", _on_player_died, "global")


## 卸载技能时解除守卫，避免状态泄漏到后续的牌。
func uninstall() -> void:
	_clear_guard()
	super()


## 任意角色使用牌指定多名目标时询问是否接管；持有者不必原本是目标之一，原文是主动成为唯一目标。
func _on_card_used(event: RuleEvent) -> void:
	if host == null or not has_available_intrinsic_use():
		return
	# 技能持有者；死亡或离场后不再提供接管选项。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 目标数组；原文限定“指定多名角色为目标”，单目标牌不触发。
	var target_ids: Array = event.data.get("target_ids", []) as Array
	if target_ids.size() < MINIMUM_TARGET_COUNT:
		return
	# 牌UID；缺失时无法定位改写对象，也不具备防重入凭据。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if card_uid < 0:
		return
	# 防重入：同一张牌已经处于本技能守卫之下时不再询问，否则目标数组会被反复改写而膨胀。
	if _guard_active and _guard_card_uid == card_uid:
		return
	# 目标已经是“持有者本人重复X次”，说明改写已经生效，不需要再次询问。
	if _is_sole_owner_targets(target_ids):
		return
	request_card_selection("岳峙", "是否发动【岳峙】成为该牌的唯一目标？", [], 0, 0, true, {"kind":BECOME_SOLE_TARGET_CHOICE_KIND, "card_uid":card_uid, "original_target_count":target_ids.size(), "original_target_ids":_int_array(target_ids), "card_definition_id":str(event.data.get("card_id", "")), CONTEXT_SOURCE_ID:event.source_id, "ai_allow_confirm":true})


## 恢复接管确认；确认后把目标数组整体替换为持有者的X次重复并开启结算期守卫。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if str(context.get("kind", "")) != BECOME_SOLE_TARGET_CHOICE_KIND:
		return false
	if not response.confirmed:
		return true
	# 牌UID；询问时固定，取消或非法时直接结束本次恢复。
	var card_uid: int = int(context.get("card_uid", -1))
	if card_uid < 0:
		return true
	# 结算次数X；取改写前的原目标数，含持有者自己若原本在列。
	var resolve_times: int = maxi(int(context.get("original_target_count", 0)), MINIMUM_TARGET_COUNT)
	# 改写后的目标数组：持有者本人重复X次，使该牌对本人结算X次。
	var new_target_ids: Array[int] = []
	for _index: int in range(resolve_times):
		new_target_ids.append(owner_player_id)
	# 目标改写必须走专用端口：它在结果提交后重新写回用牌上下文，直接改共享上下文会被覆盖。
	if not bool(host.call("replace_card_use_targets", card_uid, new_target_ids, get_id())):
		return true
	if not consume_intrinsic_use():
		return true
	# 开启结算期守卫；首次伤害与首次回复放行，其后全部防止。
	_guard_card_uid = card_uid
	_guard_active = true
	_damage_resolved = false
	_recover_resolved = false
	announce_activation({"target_id":owner_player_id, "resolve_times":resolve_times, "card_uid":card_uid})
	return true


## 结算期伤害守卫：放行首次伤害，其后每一次伤害都被防止。
## damageBegin4 位于最终伤害数值确定之后、护盾与体力扣减之前，取消该窗口即完全阻止本次伤害。
func _on_damage_begin_four(event: RuleEvent) -> void:
	if not _guard_active or event.target_id != owner_player_id:
		return
	# 伤害为0的事件不构成“受到伤害”，因此不占用唯一的放行名额。
	if int(event.data.get("amount", 0)) <= 0:
		return
	if _damage_resolved:
		event.cancel(GUARD_CANCEL_REASON)
		return
	_damage_resolved = true


## 结算期回复守卫：放行首次回复，其后每一次回复都被防止；与伤害守卫各自独立计数。
func _on_recover_begin(event: RuleEvent) -> void:
	if not _guard_active or event.target_id != owner_player_id:
		return
	if int(event.data.get("amount", 0)) <= 0:
		return
	if _recover_resolved:
		event.cancel(GUARD_CANCEL_REASON)
		return
	_recover_resolved = true


## 该牌整牌结算完毕时解除守卫；只有与守卫牌UID一致的尾时机才会命中。
func _on_card_after(event: RuleEvent) -> void:
	if not _guard_active:
		return
	if int(event.data.get("card_uid", -1)) != _guard_card_uid:
		return
	_clear_guard()


## 持有者死亡后解除守卫；死亡角色不会再成为任何牌的伤害目标，残留守卫已无意义。
func _on_player_died(event: RuleEvent) -> void:
	if event.player_id == owner_player_id:
		_clear_guard()


## 解除结算期守卫并清空全部标记；uninstall 与持有者死亡共用本入口。
func _clear_guard() -> void:
	_guard_card_uid = -1
	_guard_active = false
	_damage_resolved = false
	_recover_resolved = false


## 判断目标数组是否已经是“持有者本人的X次重复”；用于避免对同一张牌重复询问与重复改写。
func _is_sole_owner_targets(target_ids: Array) -> bool:
	if target_ids.is_empty():
		return false
	for target_variant: Variant in target_ids:
		if int(target_variant) != owner_player_id:
			return false
	return true


## 把弱类型数组收敛为整数数组；询问上下文与动作输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序，由技能规则判断数量。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result


## 评估接管收益；伤害类牌替残血队友挡伤，正收益牌剥夺敌方收益，其余情况不发动。
## 使用者阵营参与决策：队友使用的非【五谷丰登】牌一律不发动，避免把队友的收益整体转移到自己身上。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；原目标与牌定义都来自询问时的快照。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != BECOME_SOLE_TARGET_CHOICE_KIND:
		return 0.0
	if not bool((action.get("payload", {}) as Dictionary).get("confirmed", false)):
		return 0.0
	# 限定技额度耗尽后不再评分，避免AI对同一张牌反复确认。
	if not has_available_intrinsic_use():
		return 0.0
	# 原目标数组与结算次数；态度判定与收益折算都以改写前的快照为准。
	var original_target_ids: Array = context.get("original_target_ids", []) as Array
	var resolve_times: int = maxi(int(context.get("original_target_count", 0)), 0)
	if resolve_times < MINIMUM_TARGET_COUNT or original_target_ids.is_empty():
		return 0.0
	# 牌定义ID；同时用于【五谷丰登】的无条件分支与牌效元数据查询。
	var card_definition_id: String = str(context.get("card_definition_id", ""))
	# 【五谷丰登】无条件发动：该牌对每名角色都是纯正收益，任意角色（含队友与自己）使用时接管都不会伤及己方。
	# 该分支位于队友保护之前，因此队友使用【五谷丰登】仍然是“无脑发动”。
	if card_definition_id == WUGU_CARD_ID:
		return AI_UNCONDITIONAL_CONFIRM_SCORE
	# 牌的使用者；缺失时视为未知来源，继续按原收益方向评分而不额外拦截。
	var card_source_id: int = int(context.get(CONTEXT_SOURCE_ID, -1))
	# 队友保护：接管会把该牌的全部效果集中到自己身上，队友原本的收益因此被剥夺；
	# 使用者是队友（态度为正）且不是本人时直接不发动。本人使用的牌仍按牌效方向正常评分。
	if card_source_id >= 0 and card_source_id != owner_player_id and evaluator.get_attitude(authoritative_snapshot, owner_player_id, card_source_id) > 0.0:
		return 0.0
	# 牌效元数据；伤害类与正收益类的收益方向完全相反，不能共用同一套折算。
	var card_definition: Dictionary = GameDatabase.get_card(card_definition_id)
	if card_definition.is_empty():
		return 0.0
	var card_ai: Dictionary = card_definition.get("ai", {}) as Dictionary
	if bool(card_ai.get("damage", false)):
		return _score_damage_card_takeover(authoritative_snapshot, original_target_ids, evaluator)
	if bool(card_ai.get("beneficial", false)):
		return _score_beneficial_card_takeover(authoritative_snapshot, original_target_ids, resolve_times, evaluator)
	return 0.0


## 敌方伤害牌的接管收益：只有原目标中存在态度为正且体力不高的残血队友时才值得替其挡伤。
func _score_damage_card_takeover(authoritative_snapshot: Dictionary, original_target_ids: Array, evaluator: Object) -> float:
	# 自身快照；1点体力时接管会导致自己濒死，直接放弃。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty() or int(owner.get("hp", 0)) <= AI_SELF_MIN_HP:
		return 0.0
	# 被解救的残血队友数量；每个这样的原目标原本都会受到这次伤害。
	var rescued_count: int = 0
	for target_variant: Variant in original_target_ids:
		var target_id: int = int(target_variant)
		if target_id == owner_player_id:
			continue
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty() or not bool(target.get("alive", false)):
			continue
		if int(target.get("hp", 0)) > AI_ALLY_LOW_HP_THRESHOLD:
			continue
		if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) <= 0.0:
			continue
		rescued_count += 1
	if rescued_count <= 0:
		return 0.0
	# 净收益；救下队友的伤害按折算价值计入，同时扣掉自己被放行的首次伤害代价。
	return float(rescued_count) * NonameAIEvaluator.HP_RESOURCE_VALUE * AI_BODYGUARD_RATIO - float(AI_SELF_DAMAGE_TAKEN) * NonameAIEvaluator.HP_RESOURCE_VALUE


## 正收益多目标牌的接管收益：剥夺敌方每人的收益，同时自己重复获得X次；只有敌方占多数时才发动。
func _score_beneficial_card_takeover(authoritative_snapshot: Dictionary, original_target_ids: Array, resolve_times: int, evaluator: Object) -> float:
	# 原目标中的敌方数量；态度为负计入敌方，自己不计入任何一方。
	var enemy_count: int = 0
	# 原目标中的我方数量；用于判断剥夺敌方收益是否划算。
	var ally_count: int = 0
	for target_variant: Variant in original_target_ids:
		var target_id: int = int(target_variant)
		if target_id == owner_player_id:
			continue
		if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) < 0.0:
			enemy_count += 1
		else:
			ally_count += 1
	if enemy_count <= ally_count:
		return 0.0
	# 净收益；敌方每人少获得一次收益，自己则重复获得X次。
	return float(enemy_count + resolve_times) * AI_BENEFICIAL_RATIO
