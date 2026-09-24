extends SkillDefinition

## 【投狭】技能源码。其他角色回合结束时判定，按本回合出牌阶段弃牌历史取得同花色牌，并令当前回合角色摸1张牌。

## 当前次数统计对应的全局轮数；默认-1表示尚未同步，额外回合继续共享本轮额度。
var _tracked_round_number: int = -1

## 当前轮是否已经确认并开始投狭判定；取消发动不消耗额度，开始判定后固定消耗一次。
var _used_this_round: bool = false

## AI 将敌方回合弃牌视为“非常需要的关键牌”的基础价值阈值；达到6分才愿意让敌方额外摸1张牌。
const AI_ENEMY_KEY_CARD_THRESHOLD: float = 6.0

## AI 对友方回合发动的固定基础收益；包含帮助友方摸1张牌与自身潜在回收收益。
const AI_FRIEND_ACTIVATION_SCORE: float = 8.0

## 敌方关键牌达到阈值后确认动作保留的最小正分余量；确保恰好命中阈值时仍优先于取消。
const AI_ENEMY_KEY_CARD_CONFIRM_MARGIN: float = 1.0

## 四种实体花色的稳定顺序；用于构造戏法的投狭花色偏好映射与确定性比较。
const SUIT_ORDER: Array[String] = ["spade", "heart", "club", "diamond"]

## 投狭完成后当前回合角色固定摸牌数；固定为1，与技能原文一致，取消获得也不会改变。
const TURN_PLAYER_DRAW_COUNT: int = 1

## 投狭有利判定对技能持有者的基础 AI 价值；表示成功命中可回收花色的资源收益方向。
const AI_JUDGMENT_OWNER_RESULT_VALUE: float = 1.0

## 投狭有利判定对当前回合角色的基础 AI 价值；表示技能最终令其摸1张牌的团队收益方向。
const AI_JUDGMENT_TURN_PLAYER_RESULT_VALUE: float = 0.5

## AI 在判定后的获得窗口放大所选公开牌价值的倍率；确保正价值候选优先于直接取消。
const AI_GAIN_CARD_VALUE_MULTIPLIER: float = 2.0

## 卡牌定义缺少可用价值字段时的基础保留值；固定为1，供关键牌阈值和花色偏好稳定比较。
const AI_DEFAULT_CARD_VALUE: float = 1.0


## 写入触发技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"touxia",
		"name":"投狭",
		"trigger":"phaseAfter",
		"ui_enabled":false,
		"description":"其他角色的回合结束时，你可进行判定，然后你可以获得弃牌堆中一张于此回合出牌阶段进入弃牌堆、且花色与判定结果相同的牌，然后当前回合的角色摸一张牌。每轮限一次。",
	})


## 订阅所有角色的回合完成时机；自己的回合不触发，轮数变化时恢复一次额度。
func install() -> void:
	subscribe_timing("phaseAfter", _on_other_turn_after, "global")


## 在其他角色回合结束时创建可取消确认；候选快照只用于 AI 判断，不限制判定后仍在弃牌堆的最终窗口。
func _on_other_turn_after(event: RuleEvent) -> void:
	_sync_round_state()
	if event == null or _used_this_round or event.player_id == owner_player_id:
		return
	# 本回合出牌阶段进入弃牌堆且仍在弃牌堆的全部花色牌；用于 AI 评估是否存在敌方关键牌。
	var candidates: Array[Dictionary] = host.call("get_turn_play_discard_candidates", owner_player_id, host.state.turn_number, event.player_id, "") as Array[Dictionary]
	# 当前候选最高基础价值；敌方回合只有达到关键牌阈值才值得承担令其摸1张牌的代价。
	var maximum_candidate_value: float = 0.0
	for candidate: Dictionary in candidates:
		maximum_candidate_value = maxf(maximum_candidate_value, _estimate_candidate_value(candidate))
	request_card_selection("投狭", "是否发动【投狭】进行判定？", [], 0, 0, true, {
		"kind":"touxia_confirm",
		"turn_number":host.state.turn_number,
		"turn_player_id":event.player_id,
		"maximum_candidate_value":maximum_candidate_value,
		"ai_allow_confirm":true,
	})


## 恢复发动确认或判定后的弃牌获得选择；无论获得或取消，最后都令当前回合角色摸1张牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；确认负责开始判定，获得步骤负责移动同花色弃牌。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "touxia_confirm":
		if response.confirmed:
			_begin_judgment(context)
		return true
	if choice_kind == "touxia_gain":
		_finish_gain_choice(context, response.card_ids if response.confirmed else [])
		return true
	return false


## 确认后消耗本轮额度并建立判定；戏法获得各花色弃牌最高价值，以优先命中关键牌花色。
func _begin_judgment(context: Dictionary) -> void:
	_sync_round_state()
	if _used_this_round:
		return
	# 原回合编号；等待期间下一回合不得替代本次投狭的弃牌统计范围。
	var turn_number: int = int(context.get("turn_number", host.state.turn_number))
	# 原当前回合角色；判定完成后固定令该角色摸1张牌。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	_used_this_round = true
	announce_activation({"turn_number":turn_number, "turn_player_id":turn_player_id, "round_number":host.state.round_number})
	# 当前仍有效的全部弃牌候选；每种花色只记录其中最高价值，供戏法选择判定牌。
	var candidates: Array[Dictionary] = host.call("get_turn_play_discard_candidates", owner_player_id, turn_number, turn_player_id, "") as Array[Dictionary]
	# 花色偏好价值；不存在某花色时戏法会把不匹配的两张已知牌置底，尽量避免判定落空。
	var preferred_suit_values: Dictionary = _build_preferred_suit_values(candidates)
	# 异步判定接收者；换将后旧技能代次不会取得弃牌或令角色摸牌。
	var continuation: Dictionary = {
		"receiver_type":"skill",
		"skill_owner_id":owner_player_id,
		"skill_id":get_id(),
		"skill_character_generation":get_bound_character_generation(),
		"context":{"kind":"touxia_judgment", "turn_number":turn_number, "turn_player_id":turn_player_id},
	}
	# 投狭没有简单二元成败；preferred_suit_values 直接表达各花色当前可回收牌的最高价值。
	var judgment_ai_context: Dictionary = {"preferred_suit_values":preferred_suit_values, "favorable_result_player_values":{str(owner_player_id):AI_JUDGMENT_OWNER_RESULT_VALUE, str(turn_player_id):AI_JUDGMENT_TURN_PLAYER_RESULT_VALUE}}
	# 最终判定牌；没有判定前交互时同步返回，有【戏法】时由 continue_judgment 恢复。
	var judgment_card: CardInstance = host.call("request_judgment", owner_player_id, "【投狭】", continuation, judgment_ai_context) as CardInstance
	if not bool(host.call("has_pending_judgment_request")):
		_handle_judgment_result(turn_number, turn_player_id, judgment_card)


## 恢复曾被判定前技能暂停的投狭结果，并安排判定结果展示间隔后的获得窗口。
func continue_judgment(context: Dictionary, judgment_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "touxia_judgment":
		return false
	_handle_judgment_result(int(context.get("turn_number", -1)), int(context.get("turn_player_id", -1)), judgment_card)
	return true


## 保存最终判定花色并按当前游戏速度延后获得窗口；空判定结果只跳过获得，仍执行后续摸牌。
func _handle_judgment_result(turn_number: int, turn_player_id: int, judgment_card: CardInstance) -> void:
	# 最终判定花色；取消或空判定使用空字符串，后续不会列出任何获得候选。
	var judgment_suit: String = judgment_card.suit if judgment_card != null else ""
	# 延时恢复上下文；只保存原回合、原角色和公开判定花色，不持有牌对象引用。
	var result_context: Dictionary = {"kind":"touxia_open_gain", "turn_number":turn_number, "turn_player_id":turn_player_id, "judgment_suit":judgment_suit}
	# 判定结果停留回调；零速度或无节奏组件时同步进入窗口，正式对局按统一流程间隔展示。
	var resume_callback: Callable = Callable(self, "_open_gain_choice_after_interval").bind(result_context)
	if not schedule_after_flow_interval("judgment_result", resume_callback):
		_open_gain_choice_after_interval(result_context)


## 判定结果展示间隔结束后重新查询同花色弃牌；候选为空时直接执行当前回合角色摸牌并恢复外层结算。
func _open_gain_choice_after_interval(context: Dictionary) -> void:
	# 判定花色；只有四种实体花色能产生获得窗口。
	var judgment_suit: String = str(context.get("judgment_suit", ""))
	# 当前仍满足历史与区域条件的同花色牌；等待期间已离开弃牌堆的牌自动消失。
	var candidates: Array[Dictionary] = host.call("get_turn_play_discard_candidates", owner_player_id, int(context.get("turn_number", -1)), int(context.get("turn_player_id", -1)), judgment_suit) as Array[Dictionary] if judgment_suit in SUIT_ORDER else []
	if candidates.is_empty():
		_draw_turn_player_and_resume(int(context.get("turn_player_id", -1)))
		return
	# 可选获得请求；玩家可选一张并确定，也可直接取消。
	var selected_uids: Array[int] = request_card_selection("投狭", "请选择获得一张与判定结果花色相同的牌，或取消", candidates, 0, 1, true, {
		"kind":"touxia_gain",
		"turn_number":int(context.get("turn_number", -1)),
		"turn_player_id":int(context.get("turn_player_id", -1)),
		"judgment_suit":judgment_suit,
	})
	# 无正式对局 ID 的同步规则测试不会通过 continue_selection 回调，需在此直接应用返回结果。
	if not host.has_pending_card_choice():
		_finish_gain_choice(context, selected_uids)


## 处理获得或取消结果；获得牌引发嵌套选择时先登记“然后摸牌”，避免新选择覆盖外层流程。
func _finish_gain_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原当前回合角色；无论是否成功获得牌，最后都令该角色摸1张牌。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	# 是否实际获得一张仍合法的弃牌；旧 UID 或花色失效时按未获得处理。
	var gained_card: bool = false
	if selected_uids.size() == 1:
		gained_card = bool(host.call("gain_turn_play_discard_card", owner_player_id, selected_uids[0], int(context.get("turn_number", -1)), turn_player_id, str(context.get("judgment_suit", "")), get_id()))
	if gained_card and host.has_pending_card_choice():
		defer_settlement({"kind":"touxia_draw_turn_player", "turn_player_id":turn_player_id})
		return
	_draw_turn_player_and_resume(turn_player_id)


## 恢复获得牌移动产生的嵌套选择，然后执行投狭固定的当前回合角色摸1张牌。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "touxia_draw_turn_player":
		return false
	_draw_turn_player_and_resume(int(context.get("turn_player_id", -1)))
	return true


## 令原当前回合角色摸1张牌，并通知控制器继续 phaseAfter 外层续接；无效角色由通用 draw 安全忽略。
func _draw_turn_player_and_resume(turn_player_id: int) -> void:
	host.call("draw", turn_player_id, TURN_PLAYER_DRAW_COUNT)
	if host.has_method("resume_settlement_pipeline"):
		host.call("resume_settlement_pipeline")


## 汇总每种花色当前最高弃牌价值；戏法据此优先让投狭命中价值最高的可回收牌。
func _build_preferred_suit_values(candidates: Array[Dictionary]) -> Dictionary:
	# 花色到最高价值的映射；没有有效候选的花色不写入，明确表示该结果会落空。
	var result: Dictionary = {}
	for candidate: Dictionary in candidates:
		# 当前候选花色；只接受四种实体花色。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		# 当前实体花色；none 等异常值不会进入偏好映射。
		var suit: String = str(card_data.get("suit", "none"))
		if suit not in SUIT_ORDER:
			continue
		# 当前候选价值；同花色只保留最高值，确保戏法优先服务最关键的可获得牌。
		var card_value: float = _estimate_candidate_value(candidate)
		result[suit] = maxf(float(result.get(suit, 0.0)), card_value)
	return result


## 返回弃牌候选的基础 AI 价值；优先读取 ai_use_value，再回退 ai.value 首项或常数1。
func _estimate_candidate_value(candidate: Dictionary) -> float:
	# 当前公开牌面；投狭只处理弃牌堆中的公开实体。
	var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
	# 当前卡牌静态定义；基础价值用于关键牌阈值与同花色排序。
	var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
	if definition.has("ai_use_value"):
		return float(definition.get("ai_use_value", AI_DEFAULT_CARD_VALUE))
	# 卡牌 AI 配置；value 可以是单值或持有数量递减数组。
	var ai_profile: Dictionary = definition.get("ai", {}) as Dictionary
	# 基础牌值；数组读取首项，空数组与缺失字段均回退1。
	var value: Variant = ai_profile.get("value", AI_DEFAULT_CARD_VALUE)
	return float((value as Array)[0]) if value is Array and not (value as Array).is_empty() else float(value)


## 全局轮数变化时恢复一次投狭额度；额外回合不会递增 round_number，因此仍共享本轮限制。
func _sync_round_state() -> void:
	if host == null or host.state == null or _tracked_round_number == host.state.round_number:
		return
	_tracked_round_number = host.state.round_number
	_used_this_round = false


## AI 对友方回合通常发动；敌方回合仅在出现基础价值达到阈值的关键牌时确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；分别处理发动确认与判定后的获得选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 选择负载；取消动作保持0分，确认动作读取具体目标或牌 UID。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前选择步骤；投狭获得牌优先最高价值，发动确认按阵营与关键牌阈值判断。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "touxia_confirm":
		if not bool(payload.get("confirmed", false)):
			return 0.0
		# 原当前回合角色；正态度表示友方，通常发动并帮助其摸1张牌。
		var turn_player_id: int = int(context.get("turn_player_id", -1))
		if evaluator.get_attitude(authoritative_snapshot, owner_player_id, turn_player_id) > 0.0:
			return AI_FRIEND_ACTIVATION_SCORE
		# 敌方回合最高弃牌价值；达到阈值才允许关键牌收益覆盖敌方摸牌代价。
		var maximum_candidate_value: float = float(context.get("maximum_candidate_value", 0.0))
		return maximum_candidate_value - AI_ENEMY_KEY_CARD_THRESHOLD + AI_ENEMY_KEY_CARD_CONFIRM_MARGIN if maximum_candidate_value >= AI_ENEMY_KEY_CARD_THRESHOLD else -AI_FRIEND_ACTIVATION_SCORE
	if choice_kind == "touxia_gain":
		# 所选弃牌 UID；确认一张牌时按其公开价值给出正收益，取消保持0。
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		if selected_cards.size() != 1:
			return 0.0
		return evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id) * AI_GAIN_CARD_VALUE_MULTIPLIER
	return 0.0
