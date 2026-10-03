extends SkillDefinition

## 【独弈】技能源码。锁定技，两段效果：
## ①持有者不可使用或打出手牌中的基本牌与锦囊牌；非手牌牌源（例如木牛流马“粮”）不受限制。
## ②弃牌阶段开始时，持有者随机保留每种花色的手牌各一张并弃置其余手牌，然后跳过该弃牌阶段。

## 允许参与“每种花色保留一张”的实体花色；无花色牌不属于任何花色，因此全部进入弃置集合。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 禁止使用或打出的卡牌大类；装备牌不在原文限制范围内，仍可正常使用。
const FORBIDDEN_CARD_TYPES: Array[String] = ["basic", "trick"]

## 被禁止卡牌大类的中文名称；仅用于生成统一拒绝原因文本，不参与任何规则判定。
const CARD_TYPE_NAMES: Dictionary = {"basic":"基本牌", "trick":"锦囊牌"}

## 随机保留的历史类别；每个花色各写入一条随机历史，便于固定种子回放复核。
const HISTORY_KIND: String = "duyi_keep_suit"

## 跳过弃牌阶段的延迟收尾类别；弃置可能触发嵌套询问，必须等全部结算完成再跳过阶段。
const CONTINUATION_SKIP: String = "duyi_skip_discard"

## 弃牌阶段的稳定阶段名；与核心层阶段名保持一致，避免内容层出现拼写差异。
const DISCARD_PHASE_NAME: String = "discard"

## AI估值放大系数；持有者无法打出手牌【闪】，【杀】的实际命中率接近100%。
## 取值必须严格大于1，使敌对目标的攻击收益与友方目标的误伤代价同时被放大；默认1.4约等于“必定命中”相对基础估值的溢价。
const AI_NO_RESPONSE_MULTIPLIER: float = 1.4


## 写入锁定技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"duyi",
		"name":"独弈",
		"trigger":"passive/phaseDiscardBegin",
		"lock":true,
		"ui_enabled":false,
		"description":"锁定技，你不可使用或打出手牌中的基本牌和锦囊牌。弃牌阶段开始时，你随机保留每种花色的手牌各一张并弃置其余的牌，然后跳过该阶段。",
	})


## 订阅弃牌阶段开始时机；role 为 player 时只有持有者本人的弃牌阶段才会回调。
func install() -> void:
	subscribe_timing("phaseDiscardBegin", _on_discard_phase_begin, "player")


## 校验持有者能否使用或打出一张实体牌；只约束手牌区中的基本牌与锦囊牌。
##
## 本入口是核心层“这张牌本身能不能用”的统一查询点，因此覆盖直接使用、响应打出、目标枚举、
## 界面候选与 AI 合法动作；装备牌、非手牌牌源与其他动作（例如重铸）都不受影响。
## 纯查询约束：不消费次数、不移动牌、不写日志，也不读取任何运行时成员变量。
func validate_card_action_permission(card: CardInstance, card_definition: Dictionary, card_action: String) -> String:
	if card == null or card.zone != "hand":
		return ""
	if card_action != CardDefinition.CARD_ACTION_USE and card_action != CardDefinition.CARD_ACTION_PLAY:
		return ""
	# 当前实体牌大类；只有基本牌与锦囊牌落入原文限制范围。
	var card_type: String = str(card_definition.get("type", ""))
	if not FORBIDDEN_CARD_TYPES.has(card_type):
		return ""
	# 被拦下的具体动作名；区分“使用”与“打出”，让玩家知道是哪种操作被锁定技阻止。
	var action_name: String = "使用" if card_action == CardDefinition.CARD_ACTION_USE else "打出"
	return "【独弈】：你不能%s手牌中的%s。" % [action_name, str(CARD_TYPE_NAMES.get(card_type, card_type))]


## 弃牌阶段开始时随机保留每种花色各一张手牌，弃置其余手牌，然后跳过该阶段。
func _on_discard_phase_begin(_event: RuleEvent) -> void:
	# 技能持有者；死亡或已离场的角色不再处理弃牌阶段。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 弃置前的手牌总数；保留张数按弃置结果反推，避免依赖弃置端口是否立即改写手牌。
	var hand_size_before: int = owner.hand.size()
	var discard_uids: Array[int] = _collect_random_discard_uids(owner)
	if not discard_uids.is_empty():
		host.call("discard_selected_hand_cards", owner_player_id, discard_uids)
	announce_activation({"discarded_count":discard_uids.size(), "kept_count":maxi(hand_size_before - discard_uids.size(), 0)})
	# 原文顺序：先随机保留与弃置，再跳过该阶段。
	# 弃置本身可能触发其他技能的嵌套询问；此时必须等嵌套结算结束再跳过，否则会出现阶段提前结束的时序错乱。
	var continuation: Dictionary = {"kind":CONTINUATION_SKIP}
	if host.has_pending_card_choice():
		defer_settlement(continuation)
		return
	host.call("skip_current_main_phase", owner_player_id, DISCARD_PHASE_NAME, get_id())


## 恢复弃置产生的嵌套结算；全部结算完成后执行跳过弃牌阶段。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != CONTINUATION_SKIP:
		return false
	host.call("skip_current_main_phase", owner_player_id, DISCARD_PHASE_NAME, get_id())
	return true


## 计算本次需要弃置的手牌 UID 集合；每种出现过的花色各随机保留一张，其余手牌全部弃置。
func _collect_random_discard_uids(owner: PlayerState) -> Array[int]:
	# 花色到该花色手牌 UID 的映射；按固定花色顺序遍历，保证相同随机种子得到相同结果。
	var uids_by_suit: Dictionary = {}
	# 无花色手牌；它们不属于任何花色，因此不受“每种花色保留一张”的保护。
	var suitless_uids: Array[int] = []
	for card: CardInstance in owner.hand:
		if not CARD_SUITS.has(card.suit):
			suitless_uids.append(card.uid)
			continue
		# 首次遇到该花色时建立 UID 列表；数组在字典中按引用共享，后续追加即可。
		if not uids_by_suit.has(card.suit):
			uids_by_suit[card.suit] = []
		(uids_by_suit[card.suit] as Array).append(card.uid)
	# 待弃置手牌 UID；顺序为花色顺序加无花色牌，与界面展示无关，只影响结算顺序。
	var discard_uids: Array[int] = []
	for suit: String in CARD_SUITS:
		var suit_uids: Array = uids_by_suit.get(suit, []) as Array
		if suit_uids.is_empty():
			continue
		# 本花色保留索引；由权威随机流产生并写入随机历史，因此可复现、可复盘。
		var keep_index: int = int(host.call("pick_random_candidate_index", suit_uids.size(), HISTORY_KIND, {"skill_id":get_id(), "suit":suit}))
		if keep_index < 0:
			# 随机流异常时保守保留该花色全部手牌：宁可少弃牌，也不能凭空销毁玩家手牌。
			continue
		for card_index: int in range(suit_uids.size()):
			if card_index != keep_index:
				discard_uids.append(int(suit_uids[card_index]))
	discard_uids.append_array(suitless_uids)
	return discard_uids


## 修正其他角色对持有者的来牌估值：持有者无法打出手牌【闪】，【杀】类牌因此更难被响应。
##
## 只放大同一方向上已有的收益或损失：对敌对目标提高攻击价值，对友方目标同样放大误伤代价，
## 因此不需要在此判断敌我态度，也不会把“对友军出杀”错误地变成正收益。
func modify_ai_incoming_card_effect(_authoritative_snapshot: Dictionary, _actor_id: int, target_id: int, _definition: Dictionary, ai_profile: Dictionary, _target_result: float, _expected_damage_amount: int, current_score: float, _evaluator: Object) -> float:
	if target_id != owner_player_id:
		return current_score
	# 只有需要目标打出【闪】的牌会因无法响应而增值；其余牌的结算与本段限制无关。
	if not bool(ai_profile.get("respond_shan", false)):
		return current_score
	return current_score * AI_NO_RESPONSE_MULTIPLIER
