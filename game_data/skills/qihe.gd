extends SkillDefinition

## 【弃和】技能源码。锁定技：当持有者成为其他角色使用伤害牌的目标时，
## 若持有者手牌中有与该伤害牌花色相同的牌，则随机弃置其中一张，并令此牌对持有者无效。

## 允许参与“同花色弃置”的实体花色；无花色（none）虚拟牌不与任何手牌花色相同。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## “其他角色”的比较基准；使用者为持有者本人或无效使用者时不满足原文条件。
const SELF_ACTOR_ID: int = -1

## 随机弃牌历史类别；每次发动写入一条随机历史，便于固定种子回放复核。
const HISTORY_KIND: String = "qihe_random_discard"

## 令牌对持有者无效的延迟收尾类别；弃置可能触发嵌套询问，必须等全部结算完成再置为无效。
const CONTINUATION_EXCLUDE: String = "qihe_exclude_target"

## 每1张未知手牌与来牌同花色的概率；手牌花色对外不可见，AI只能按均匀分布估计。
const SUIT_MATCH_CHANCE_PER_CARD: float = 0.25

## AI估值中“命中即完全无效”的折算系数；取1.0表示命中时整张牌对该目标的价值归零。
const AI_NEGATE_CERTAINTY: float = 1.0

## 已处理过的使用牌 UID；同一张牌即使在同一时机被派发多次，也只弃置一张手牌。
var _handled_card_uids: Dictionary = {}


## 写入锁定技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"qihe",
		"name":"弃和",
		"trigger":"passive/useCardToTargeted",
		"lock":true,
		"ui_enabled":false,
		"description":"锁定技，当你成为其他角色使用伤害牌的目标时，若你手牌中有与此牌花色相同的牌，你随机弃置其中一张并令此牌对你无效。",
	})


## 订阅“成为牌的目标”时机；role 为 target 时只有持有者本人被指定才会回调。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_become_card_target, "target")


## 持有者成为其他角色使用的伤害牌目标时，按花色随机弃牌并令此牌对持有者无效。
func _on_become_card_target(event: RuleEvent) -> void:
	if event == null:
		return
	# 技能持有者；死亡或已离场的角色不再触发锁定技。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 当前目标 ID；逐目标时机优先读取时机数据中的稳定字段，其次回退到事件目标。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	if target_id != owner_player_id:
		return
	# 使用者必须是其他角色；自己使用的伤害牌不能对自己触发【弃和】。
	var actor_id: int = int(event.source_id)
	if actor_id <= SELF_ACTOR_ID or actor_id == owner_player_id:
		return
	# 当前使用牌稳定 UID；只有仍处于使用生命周期中的牌才能被标记为对本目标无效。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if card_uid < 0 or _handled_card_uids.has(card_uid):
		return
	# 是否为伤害牌；字段由卡牌定义显式声明，技能内不维护任何牌名白名单。
	var card_definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if not bool(card_definition.get("is_damage", false)):
		return
	# 来牌花色；由核心层在使用牌时机数据中下发。无花色虚拟牌不与任何手牌花色相同。
	var card_suit: String = str(event.data.get("card_suit", "none"))
	if not CARD_SUITS.has(card_suit):
		return
	# 同花色手牌 UID；没有同花色手牌时条件不成立，不弃牌也不令此牌无效。
	var same_suit_uids: Array[int] = _collect_same_suit_hand_uids(owner, card_suit)
	if same_suit_uids.is_empty():
		return
	# 随机弃置其中一张；原文明确为“随机”，因此不使用玩家选择，索引由权威随机流产生并写入随机历史。
	var picked_index: int = int(host.call("pick_random_candidate_index", same_suit_uids.size(), HISTORY_KIND, {"skill_id":get_id(), "card_uid":card_uid, "card_suit":card_suit}))
	if picked_index < 0:
		return
	_handled_card_uids[card_uid] = true
	var discarded_uid: int = same_suit_uids[picked_index]
	if not bool(host.call("discard_card_from_hand", owner_player_id, discarded_uid)):
		_handled_card_uids.erase(card_uid)
		return
	announce_activation({"card_uid":card_uid, "card_suit":card_suit, "discarded_card_uid":discarded_uid, "target_id":owner_player_id})
	# 原文顺序：先随机弃置一张，再令此牌对持有者无效。
	# 弃置可能触发其他技能的嵌套询问；此时延迟到嵌套结算完成后再置为无效，避免使用中的牌被提前改写状态。
	var continuation: Dictionary = {"kind":CONTINUATION_EXCLUDE, "card_uid":card_uid}
	if host.has_pending_card_choice():
		defer_settlement(continuation)
		return
	host.call("exclude_card_target", card_uid, owner_player_id, get_id())


## 恢复弃置产生的嵌套结算；全部结算完成后令此牌对持有者无效。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != CONTINUATION_EXCLUDE:
		return false
	host.call("exclude_card_target", int(context.get("card_uid", -1)), owner_player_id, get_id())
	return true


## 收集持有者手牌中与指定花色相同的牌 UID；顺序沿用权威手牌顺序，保证随机结果可复现。
func _collect_same_suit_hand_uids(owner: PlayerState, card_suit: String) -> Array[int]:
	# 同花色手牌 UID 结果；只读取手牌区，装备区与木牛流马“粮”都不参与本技能。
	var result: Array[int] = []
	for card: CardInstance in owner.hand:
		if card.suit == card_suit:
			result.append(card.uid)
	return result


## 修正其他角色对持有者的来牌估值：伤害牌可能被【弃和】完全抵消，因此攻击价值按命中概率衰减。
##
## 手牌花色属于隐藏信息，估值只能按“每张未知手牌有 1/4 概率与来牌同花色”的均匀分布推算：
## 手牌 N 张时至少存在一张同花色牌的概率为 1-(1-1/4)^N，命中时整张牌对该目标无效。
func modify_ai_incoming_card_effect(authoritative_snapshot: Dictionary, _actor_id: int, target_id: int, definition: Dictionary, _ai_profile: Dictionary, _target_result: float, _expected_damage_amount: int, current_score: float, evaluator: Object) -> float:
	if target_id != owner_player_id:
		return current_score
	# 只有伤害牌会被【弃和】取消；其余牌不进入本段估值。
	if not bool(definition.get("is_damage", false)):
		return current_score
	# 持有者手牌数；公开信息，任何AI都能读取。没有手牌时条件不成立，估值不变。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	var hand_count: int = int(target.get("hand_count", 0))
	if hand_count <= 0:
		return current_score
	# 至少一张手牌与来牌同花色的概率；随手牌数增加而单调上升，收敛到1。
	var match_chance: float = 1.0 - pow(1.0 - SUIT_MATCH_CHANCE_PER_CARD, float(hand_count))
	return current_score * (1.0 - match_chance * AI_NEGATE_CERTAINTY)
