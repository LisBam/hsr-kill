extends SkillDefinition

## 【安可】技能源码。统计当前回合进入弃牌堆的四种花色，并在回合结束时至多每轮取得三次额外回合。

## 触发所需的实体花色数量；固定4对应黑桃、红桃、梅花与方块。
const REQUIRED_SUIT_COUNT: int = 4

## 每轮最多发动次数；固定3，与技能原文一致。
const MAX_USES_PER_ROUND: int = 3

## 花色在武将牌组件中的固定显示顺序；保证相同集合在所有客户端得到一致文本。
const SUIT_DISPLAY_ORDER: Array[String] = ["spade", "heart", "club", "diamond"]

## 稳定花色到符号的映射；无花色与虚拟牌不会进入该表。
const SUIT_SYMBOLS: Dictionary = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}

## 安可文本在左上角组合条目中的排序值；默认100让短期目标提示优先显示，单独存在时不改变原文本。
const CORNER_TEXT_ORDER: int = 100

## 当前正在统计的全局回合号；默认-1表示尚未进入有效回合。
var _tracked_turn_number: int = -1

## 当前回合已经进入弃牌堆的花色集合；键为稳定英文花色，值固定为true。
var _discarded_suits_this_turn: Dictionary = {}

## 当前次数统计对应的全局轮数；默认-1表示尚未进入有效轮次。
var _tracked_round_number: int = -1

## 当前轮已经确认发动的次数；范围0至3，额外回合与普通回合共享该值。
var _uses_this_round: int = 0


## 写入触发技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"anke",
		"name":"安可",
		"trigger":"phaseEnd",
		"ui_enabled":false,
		"description":"回合结束时，若本回合内有四种花色的牌进入过弃牌堆，你可执行一个额外的回合。每轮限三次。",
	})


## 订阅每个回合的开始、全局弃牌移动与持有者自己的回合结束；只有持有者自己的回合会开启统计与文本显示。
func install() -> void:
	subscribe_timing("phaseBefore", _on_turn_before, "global")
	subscribe_timing("cardsDiscardAfter", _on_cards_discarded, "global")
	subscribe_timing("phaseEnd", _on_turn_end, "player")


## 卸载技能时只移除安可自己的公开文本条目，其他技能共享的左上角提示继续保留。
func uninstall() -> void:
	if host != null and host.has_method("remove_character_corner_text_entry"):
		host.call("remove_character_corner_text_entry", owner_player_id, _get_corner_entry_id())
	super()


## 新回合开始时清空花色集合；只有持有者自己的回合记录有效回合号，回合外保持关闭并清除文本。
func _on_turn_before(event: RuleEvent) -> void:
	_tracked_turn_number = host.state.turn_number if event.player_id == owner_player_id else -1
	_discarded_suits_this_turn.clear()
	_refresh_corner_text()
	if _tracked_round_number != host.state.round_number:
		_tracked_round_number = host.state.round_number
		_uses_this_round = 0


## 从弃牌堆按UID读取刚进入的实体牌并记录有效花色；虚拟牌与none花色不计入。
func _on_cards_discarded(event: RuleEvent) -> void:
	if host.state.current_player_id != owner_player_id or _tracked_turn_number != host.state.turn_number:
		return
	for card_uid_variant: Variant in event.data.get("card_uids", []) as Array:
		var card: CardInstance = _find_discard_card(int(card_uid_variant))
		if card != null and card.suit in ["spade", "heart", "club", "diamond"]:
			_discarded_suits_this_turn[card.suit] = true
	_refresh_corner_text()


## 持有者自己的回合结束时满足四花色且本轮未达上限则询问；取消不会消耗次数。
func _on_turn_end(event: RuleEvent) -> void:
	if event.player_id != owner_player_id:
		return
	if _tracked_turn_number != host.state.turn_number:
		return
	if _discarded_suits_this_turn.size() < REQUIRED_SUIT_COUNT or _uses_this_round >= MAX_USES_PER_ROUND:
		return
	request_card_selection("安可", "是否发动【安可】执行一个额外的回合？", [], 0, 0, true, {"kind":"anke_confirm", "ai_allow_confirm":true})


## 恢复发动确认并加入一个额外完整回合；只有成功入队才消耗本轮次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "anke_confirm" or response == null:
		return false
	if response.confirmed and _uses_this_round < MAX_USES_PER_ROUND and get_owner_skill_player().addPhase():
		_uses_this_round += 1
		announce_activation({"round_number":host.state.round_number, "uses_this_round":_uses_this_round})
	return true


## 按UID查找当前弃牌堆实体；后置移动时机保证正常情况下能够命中。
func _find_discard_card(card_uid: int) -> CardInstance:
	for card: CardInstance in host.state.discard_pile:
		if card.uid == card_uid:
			return card
	return null


## 把本回合已出现花色写入持有者公开文本；尚无有效花色时清空组件内容。
func _refresh_corner_text() -> void:
	if host == null or not host.has_method("set_character_corner_text_entry") or not host.has_method("remove_character_corner_text_entry"):
		return
	# 按固定顺序拼接的花色符号；示例三种花色会显示为“安可：♥♣♦”。
	var suit_text: String = ""
	for suit: String in SUIT_DISPLAY_ORDER:
		if _discarded_suits_this_turn.has(suit):
			suit_text += str(SUIT_SYMBOLS.get(suit, ""))
	if suit_text.is_empty():
		host.call("remove_character_corner_text_entry", owner_player_id, _get_corner_entry_id())
	else:
		host.call("set_character_corner_text_entry", owner_player_id, _get_corner_entry_id(), "安可：%s" % suit_text, CORNER_TEXT_ORDER)


## 返回本技能实例的稳定左上角条目ID；玩家ID保证多名西露瓦之间可以独立维护文本。
func _get_corner_entry_id() -> String:
	return "anke:%d" % owner_player_id


## 额外完整回合具有高正收益，只要持有者仍存活在场基础AI就会确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "anke_confirm" or not bool((action.get("payload", {}) as Dictionary).get("confirmed", false)):
		return 0.0
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	return 6.0 + float(owner.get("hp", 0)) * 0.4 + float(owner.get("hand_count", 0)) * 0.25
