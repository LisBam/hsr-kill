extends SkillDefinition

## 【咬它】技能源码。星与穹共用的普通技能：回合开始前可弃置一张手牌，令一名角色发动其欢愉技；
## 若其没有可发动的欢愉技，则改为令其执行一个额外的出牌阶段。每种花色整局限一次。

## 四种实体花色的稳定集合；none虚拟花色不消耗也不能满足本技能额度。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 费用牌数量；固定1张，原文为“弃置一张手牌”。
const COST_CARD_COUNT: int = 1

## 目标数量；固定1名，原文为“一名角色”。
const TARGET_COUNT: int = 1

## 组合选择请求种类；恢复时按该值分流到结算入口。
const CHOICE_KIND: String = "yaota_cost_target"

## 欢愉技演出完成回调的种类；与额外阶段完成回调分开，便于日后扩展不同收益。
const JOY_COMPLETION_KIND: String = "yaota_joy_complete"

## 额外出牌阶段完成回调的种类。
const EXTRA_PHASE_COMPLETION_KIND: String = "yaota_extra_play_complete"

## 费用结算后“分流到欢愉技或额外出牌阶段”这一延后步骤的稳定标识；供 continue_settlement 识别。
const DISPATCH_SETTLEMENT_KIND: String = "yaota_dispatch_effect"

## AI：队友手牌数达到该值时取得最高目标优先级；固定8，来自需求给出的AI口径。
const AI_ALLY_MANY_CARDS_THRESHOLD: int = 8

## AI：队友手牌数达到该值时取得第三档优先级；固定5，来自需求给出的AI口径。
const AI_ALLY_SOME_CARDS_THRESHOLD: int = 5

## AI：最高优先级目标分值；对应需求第一档“手牌数≥8的队友”。
const AI_TARGET_ALLY_MANY_CARDS_PRIORITY: float = 8.0

## AI：第二档目标分值；对应需求“有欢愉技的队友”。
const AI_TARGET_ALLY_JOY_SKILL_PRIORITY: float = 6.0

## AI：第三档目标分值；对应需求“手牌数≥5的队友”。
const AI_TARGET_ALLY_SOME_CARDS_PRIORITY: float = 4.0

## AI：最低档目标分值；对应需求“自己”，此时才需要额外比较费用牌价值。
const AI_TARGET_SELF_PRIORITY: float = 2.0

## AI：非队友目标的优先级；负值使AI不去强化敌方或中立方。
const AI_TARGET_HOSTILE_PRIORITY: float = -6.0

## AI：非法目标的评分；低于任何合法动作。
const AI_TARGET_INVALID_SCORE: float = -20.0

## AI：费用牌价值的折算权重；弃置费用按统一牌价值计入负收益，权重越高越珍惜手牌。
const AI_COST_VALUE_WEIGHT: float = 0.5

## AI：最优先目标为自己时允许支付的费用牌价值上限；超过该值则放弃发动，避免浪费关键牌。
const AI_SELF_TARGET_MAX_COST_VALUE: float = 2.0

## 整局已经消耗的花色集合；键为稳定英文花色，值固定为true。
## 该字典有意不随回合或轮次清空，对应原文“每种花色限一次”的整局额度。
var _used_suits: Dictionary = {}


## 写入技能静态信息；技能描述严格保持需求提供的原文，星与穹共用本文件。
func _init() -> void:
	super({
		"id":"yaota",
		"name":"咬它",
		"trigger":"phaseBefore",
		"ui_enabled":false,
		"description":"每种花色限一次，你的回合开始前，你可以弃置一张手牌，然后令一名角色发动其欢愉技。若其没有欢愉技，则令其执行一个额外的出牌阶段。",
	})


## 订阅持有者回合开始时询问；本技能是可选普通技能，因此窗口允许取消。
func install() -> void:
	subscribe_timing("phaseBefore", _on_owner_turn_before, "player")


## 持有者回合开始时询问是否发动；没有可支付花色的手牌或没有合法目标时不创建询问。
func _on_owner_turn_before(_event: RuleEvent) -> void:
	# 费用候选；没有尚未消耗的花色时本技能已经用完整局额度，不再询问。
	var candidates: Array[Dictionary] = _get_cost_candidates()
	if candidates.is_empty():
		return
	# 目标候选；含持有者本人，因为原文只说“一名角色”。
	var target_ids: Array[int] = _get_all_alive_player_ids()
	if target_ids.is_empty():
		return
	request_card_target_selection("咬它", "请弃置一张手牌并选择一名角色发动其欢愉技", candidates, target_ids, COST_CARD_COUNT, COST_CARD_COUNT, TARGET_COUNT, TARGET_COUNT, true, {"kind":CHOICE_KIND})


## 恢复组合选择；先锁定花色额度再支付费用，最后按目标是否有可执行欢愉技分流。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CHOICE_KIND or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != COST_CARD_COUNT or response.target_ids.size() != TARGET_COUNT:
		return true
	# 费用实体牌；提交后手牌可能已经变化，因此按UID重新查找而不是复用旧候选。
	var owner: PlayerState = get_owner_skill_player().get_state()
	var cost_card: CardInstance = owner.find_hand_card(response.card_ids[0]) if owner != null else null
	if cost_card == null or not CARD_SUITS.has(cost_card.suit) or _used_suits.has(cost_card.suit):
		return true
	# 目标角色；等待期间死亡或离场时本次发动失效，且不消耗花色额度。
	var target_id: int = response.target_ids[0]
	if not _get_all_alive_player_ids().has(target_id):
		return true
	# 先锁定额度再支付；弃置失败时回滚，保证“支付成功才算发动”。
	_used_suits[cost_card.suit] = true
	announce_activation({"card_uid":cost_card.uid, "suit":cost_card.suit, "target_id":target_id})
	# 费用UID数组；弃置走统一端口，装备离开、保护规则与动画逻辑全部沿用既有实现。
	var cost_uids: Array[int] = [cost_card.uid]
	if int(host.call("discard_selected_hand_equipment", owner_player_id, cost_uids)) <= 0:
		_used_suits.erase(cost_card.suit)
		return true
	# 分流步骤；本组合选择窗口此时仍在等待响应，控制器会拒绝“已有待响应选择”期间创建的新请求，
	# 而目标欢愉技一演出就要创建自己的目标窗口，因此必须先延后到统一结算管线清空后再分流。
	var dispatch_context: Dictionary = {"kind":DISPATCH_SETTLEMENT_KIND, "target_id":target_id}
	if host.has_pending_card_choice():
		defer_settlement(dispatch_context)
		return true
	_dispatch_yaota_effect(target_id)
	return true


## 恢复弃置结算产生的嵌套选择；结算管线清空后按目标是否有可执行欢愉技分流。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != DISPATCH_SETTLEMENT_KIND:
		return false
	_dispatch_yaota_effect(int(context.get("target_id", -1)))
	return true


## 按目标当前是否有可执行欢愉技分流：有则强制驱动其欢愉技，没有则给予一个额外出牌阶段。
##
## 判定使用“当前可执行”而非“是否拥有”：被非锁定技失效压制的欢愉技无法演出，
## 按原文的收益目的应改走额外阶段分支，否则本次发动将没有任何实际效果。
func _dispatch_yaota_effect(target_id: int) -> void:
	# 目标当前可执行的欢愉技；已按参演编号升序、技能ID字典序排列，用于判定走哪条分支。
	var joy_skill_ids: Array[String] = host.call("get_joy_skill_ids", target_id) as Array[String]
	if not joy_skill_ids.is_empty():
		# 有欢愉技分支；演出不询问是否发动，由阿哈时刻组件按同一排序口径依次驱动其全部欢愉技。
		# 「全部」而不是「排序第一项」：目标的每个欢愉技都是一次独立演出，
		# 参演编号相同的多个欢愉技也必须全部执行，否则本次发动会漏掉其中一部分收益。
		host.call("try_perform_all_owned_joy_skills", target_id, _build_completion_context(JOY_COMPLETION_KIND, target_id))
		return
	# 没有欢愉技分支；按原文令其执行一个额外的出牌阶段。
	_request_extra_play_phase(target_id)


## 请求目标执行独立额外出牌阶段；完成上下文绑定当前技能实例与武将代次。
func _request_extra_play_phase(target_id: int) -> bool:
	var completion_context: Dictionary = _build_completion_context(EXTRA_PHASE_COMPLETION_KIND, target_id)
	return bool(host.call("request_extra_play_phase", target_id, owner_player_id, get_id(), completion_context))


## 接收额外出牌阶段完整结束通知；咬它没有附加收益，只确认流程完整结束。
func continue_extra_phase(context: Dictionary) -> bool:
	return str(context.get("kind", "")) == EXTRA_PHASE_COMPLETION_KIND


## 构建完成上下文；只保存稳定ID与武将代次，控制器据此把控制权交回本技能实例。
func _build_completion_context(completion_kind: String, target_id: int) -> Dictionary:
	return {
		"kind":completion_kind,
		"target_id":target_id,
		"skill_owner_id":owner_player_id,
		"skill_id":get_id(),
		"skill_character_generation":get_bound_character_generation(),
	}


## 返回可作为费用的普通手牌候选；只保留四花色中整局尚未消耗的那些花色。
func _get_cost_candidates() -> Array[Dictionary]:
	# 费用候选结果；保持权威手牌顺序，界面、AI与回放据此稳定复现。
	var candidates: Array[Dictionary] = []
	# 持有者状态；未绑定权威端口时没有任何候选。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return candidates
	for candidate: Dictionary in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		# 当前候选实体牌；只读取花色，不改写任何区域。
		var card: CardInstance = owner.find_hand_card(int(candidate.get("uid", -1)))
		if card != null and CARD_SUITS.has(card.suit) and not _used_suits.has(card.suit):
			candidates.append(candidate)
	return candidates


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


## 为AI评估咬它的组合选择；按需求给出的四段目标优先级给分，并扣除费用牌价值。
##
## 最优先目标不是自己时，只要存在可弃置花色就应当发动，因此分值稳定为正；
## 最优先目标是自己时额外要求费用牌价值低于阈值，避免用关键牌换取一次自身额外行动。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理咬它的组合选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	# 取消动作保持0分；确认只有严格正收益时才会被基础策略选中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选牌与目标；数量不符时判为无效动作。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_cards.size() != COST_CARD_COUNT or selected_targets.size() != TARGET_COUNT:
		return AI_TARGET_INVALID_SCORE
	# 费用牌价值；使用统一选牌价值尺度，越贵越不划算。
	var cost_value: float = float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id))
	# 目标优先级；需求四段顺序折算为可比较的连续分值。
	var target_id: int = int(selected_targets[0])
	var target_priority: float = _estimate_target_priority(authoritative_snapshot, target_id, evaluator)
	# 最高优先级目标为自己时要求费用足够便宜，否则本次发动不值得。
	if target_id == owner_player_id and cost_value > AI_SELF_TARGET_MAX_COST_VALUE:
		return AI_TARGET_HOSTILE_PRIORITY
	return target_priority - cost_value * AI_COST_VALUE_WEIGHT


## 估算一名目标对咬它的发动优先级；分值越高越优先，非队友取负值。
func _estimate_target_priority(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标快照；不存在时判为无效目标。
	var target: Dictionary = _snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return AI_TARGET_INVALID_SCORE
	# 自己永远是最低档合法目标，只在没有更好的队友时选择。
	if target_id == owner_player_id:
		return AI_TARGET_SELF_PRIORITY
	# 非队友目标不获得额外行动机会；中立同样按敌方处理。
	if float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)) <= 0.0:
		return AI_TARGET_HOSTILE_PRIORITY
	# 队友手牌数；使用公开计数，不读取其他角色的隐藏手牌内容。
	var hand_count: int = int(target.get("hand_count", 0))
	if hand_count >= AI_ALLY_MANY_CARDS_THRESHOLD:
		return AI_TARGET_ALLY_MANY_CARDS_PRIORITY
	# 队友是否拥有欢愉技；静态元数据查询，未明置武将按没有处理。
	if bool(evaluator.character_has_joy_skill(str(target.get("character_id", "")))):
		return AI_TARGET_ALLY_JOY_SKILL_PRIORITY
	if hand_count >= AI_ALLY_SOME_CARDS_THRESHOLD:
		return AI_TARGET_ALLY_SOME_CARDS_PRIORITY
	return AI_TARGET_SELF_PRIORITY


## 从权威快照读取指定玩家；不存在时返回空字典。
func _snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前遍历玩家快照；匹配稳定ID后原样返回只读字典。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}
