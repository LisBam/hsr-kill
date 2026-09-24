extends SkillDefinition

## 【戏法】技能源码。任意角色判定前可观看牌堆顶两张牌，并通过通用双行界面重排至牌堆顶或牌堆底。

## 每次观看的牌堆顶牌数；固定为2，与技能原文一致，牌堆不足时按实际数量展示。
const VIEW_CARD_COUNT: int = 2

## AI 固定确认收益；高分保证技能只要能够发动就不会选择取消。
const AI_ALWAYS_ACTIVATE_SCORE: float = 100.0

## 通用判定条件支持的四种实体花色；用于拒绝 none 等无花色逻辑牌进入匹配结果。
const STANDARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 投狭等多花色目标的花色收益优先倍率；确保先比较可回收牌价值，再以判定牌自身价值处理同分。
const AI_PREFERRED_SUIT_PRIORITY_MULTIPLIER: float = 100.0

## 卡牌定义缺少可用价值字段时的基础保留值；固定为1，避免未知定义在同条件排序中产生零值偏差。
const AI_DEFAULT_CARD_VALUE: float = 1.0


## 写入触发技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"xifa",
		"name":"戏法",
		"trigger":"judgeBefore",
		"ui_enabled":false,
		"description":"一名角色进行判定前，你可观看牌堆顶的两张牌，然后将这些牌以任意顺序放回牌堆顶与牌堆底。",
	})


## 订阅全局判定前时机；多个【戏法】持有者按座次依次确认并观看前一名调整后的最新牌堆顶。
func install() -> void:
	subscribe_timing("judgeBefore", _on_judge_before, "global")


## 创建可取消发动确认；牌面只在确认后进入持有者私有排序请求，取消时不会观看任何牌。
func _on_judge_before(event: RuleEvent) -> void:
	if event == null or host.state.draw_pile.is_empty() and host.state.discard_pile.is_empty():
		return
	# 判定请求上下文；保留判定者、原因与调用方提供的有利/不利 AI 数据。
	var judgment_context: Dictionary = {
		"kind":"xifa_confirm",
		"judgment_player_id":event.player_id,
		"reason":str(event.data.get("reason", "判定")),
		"judgment_ai_context":((event.data.get("judgment_ai_context", {}) as Dictionary).duplicate(true)),
		"ai_allow_confirm":true,
	}
	request_card_selection("戏法", "是否发动【戏法】观看并调整牌堆顶两张牌？", [], 0, 0, true, judgment_context)


## 恢复发动确认或最终双行排序；排序响应的 control_id 表示顶行牌数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；确认后读取最新牌堆顶，排序后执行唯一权威重排端口。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "xifa_confirm":
		if response.confirmed:
			_begin_arrangement(context)
		return true
	if choice_kind == "xifa_arrangement":
		# 顶行牌数；0表示全部置底，全部候选数表示全部按提交顺序置顶。
		var top_count: int = int(response.control_id.trim_prefix("top_count_")) if response.control_id.begins_with("top_count_") else -1
		host.call("arrange_draw_pile_cards", response.card_ids.duplicate(), top_count, get_id())
		return true
	return false


## 观看当前牌堆顶至多两张牌并建立不可取消的双行排序；AI建议直接写入请求上下文并继续接受权威提交校验。
func _begin_arrangement(context: Dictionary) -> void:
	# 私有观看候选；候选仍留在牌堆中，其他玩家与公共快照不会得到具体牌面。
	var candidates: Array[Dictionary] = host.call("get_top_draw_card_candidates", owner_player_id, VIEW_CARD_COUNT) as Array[Dictionary]
	if candidates.is_empty():
		return
	announce_activation({"judgment_player_id":int(context.get("judgment_player_id", -1)), "view_count":candidates.size()})
	# AI排序计划；人类界面可完全忽略该建议并自由拖动两行顺序。
	var ai_plan: Dictionary = _build_ai_arrangement(candidates, context.get("judgment_ai_context", {}) as Dictionary, int(context.get("judgment_player_id", -1)))
	request_pile_arrangement("戏法", "请将观看到的牌以任意顺序放回牌堆顶与牌堆底", candidates, {
		"kind":"xifa_arrangement",
		"judgment_player_id":int(context.get("judgment_player_id", -1)),
		"judgment_ai_context":((context.get("judgment_ai_context", {}) as Dictionary).duplicate(true)),
		"ai_ordered_card_uids":(ai_plan.get("ordered_card_uids", []) as Array).duplicate(),
		"ai_top_count":int(ai_plan.get("top_count", 0)),
	})


## 根据通用有利/不利条件或【投狭】花色价值选择下一张判定牌；没有已知合适牌时把两张牌全部置底尝试未知牌。
func _build_ai_arrangement(candidates: Array[Dictionary], judgment_ai_context: Dictionary, judgment_player_id: int) -> Dictionary:
	# 【投狭】等非二元判定提供的花色价值；键为标准花色，值越高越希望成为判定结果。
	var preferred_suit_values: Dictionary = judgment_ai_context.get("preferred_suit_values", {}) as Dictionary
	# 最佳候选 UID；负数表示两张已知牌都不满足当前目标，应全部放到牌堆底。
	var selected_uid: int = -1
	# 最佳候选收益；仅在找到合法目标牌后参与同花色或同条件之间的牌值比较。
	var selected_score: float = -INF
	if not preferred_suit_values.is_empty():
		# 戏法持有者是否希望多花色收益成立；同阵营帮助投狭命中高价值花色，敌对阵营则优先制造无可回收花色。
		var wants_preferred_suit_result: bool = _wants_favorable_result(judgment_ai_context, judgment_player_id)
		for candidate: Dictionary in candidates:
			# 当前候选牌面；戏法持有者观看后能够读取真实花色与基础牌值。
			var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
			# 当前候选花色；本机制只接受四种实体花色。
			var suit: String = str(card_data.get("suit", "none"))
			# 当前花色是否能命中来源技能声明的收益；敌对改判定者只在存在不命中花色时把它保留在顶端。
			var matches_preferred_suit: bool = preferred_suit_values.has(suit)
			if wants_preferred_suit_result != matches_preferred_suit:
				continue
			# 友方先比较花色收益，敌方非命中候选只按牌值排序；牌值始终仅作为同方向结果的确定性次级条件。
			var candidate_score: float = float(preferred_suit_values.get(suit, 0.0)) * AI_PREFERRED_SUIT_PRIORITY_MULTIPLIER + _estimate_card_value(candidate) if wants_preferred_suit_result else _estimate_card_value(candidate)
			if candidate_score > selected_score:
				selected_score = candidate_score
				selected_uid = int(candidate.get("uid", -1))
	else:
		# 当前阵营希望的二元结果；true选择 favorable_condition，false选择 unfavorable_condition。
		var wants_favorable: bool = _wants_favorable_result(judgment_ai_context, judgment_player_id)
		# 目标条件；调用方未提供对应分支时回退到另一分支的递归 not，避免简单判定遗漏补集定义。
		var desired_condition: Dictionary = (judgment_ai_context.get("favorable_condition" if wants_favorable else "unfavorable_condition", {}) as Dictionary).duplicate(true)
		if desired_condition.is_empty():
			# 另一侧条件；存在时取逻辑补集，双方都缺失则无法判断已知牌优劣。
			var opposite_condition: Dictionary = (judgment_ai_context.get("unfavorable_condition" if wants_favorable else "favorable_condition", {}) as Dictionary).duplicate(true)
			if not opposite_condition.is_empty():
				desired_condition = {"not":opposite_condition}
		for candidate: Dictionary in candidates:
			if desired_condition.is_empty() or not _matches_judgment_condition(candidate.get("card_data", {}) as Dictionary, desired_condition):
				continue
			# 同样满足期望条件时优先保留高价值牌在牌堆顶，减少把关键牌无谓送入牌堆底的机会成本。
			var candidate_score: float = _estimate_card_value(candidate)
			if candidate_score > selected_score:
				selected_score = candidate_score
				selected_uid = int(candidate.get("uid", -1))
	# 稳定候选 UID 顺序；选中的判定牌位于顶行最左侧，其余牌按观看顺序置于底行。
	var ordered_uids: Array[int] = []
	if selected_uid >= 0:
		ordered_uids.append(selected_uid)
	for candidate: Dictionary in candidates:
		# 当前候选 UID；已作为牌堆顶判定牌的实体不再重复追加。
		var card_uid: int = int(candidate.get("uid", -1))
		if card_uid != selected_uid:
			ordered_uids.append(card_uid)
	return {"ordered_card_uids":ordered_uids, "top_count":1 if selected_uid >= 0 else 0}


## 计算戏法持有者是否希望调用方定义的“有利结果”出现；角色价值按友方同号、敌方反号累计。
func _wants_favorable_result(judgment_ai_context: Dictionary, judgment_player_id: int) -> bool:
	# 有利结果对各角色的原始价值；正数表示帮助该角色，负数表示伤害或限制该角色。
	var player_values: Dictionary = judgment_ai_context.get("favorable_result_player_values", {}) as Dictionary
	# 戏法持有者视角的总效用；友方保留原符号，敌方反转符号。
	var total_utility: float = 0.0
	for player_id_variant: Variant in player_values.keys():
		# 当前受影响角色 ID；字符串键兼容网络与字典序列化。
		var player_id: int = int(player_id_variant)
		# 当前阵营关系系数；自己和友方为1，敌方为-1。
		var relation_sign: float = 1.0 if bool(host.call("is_friendly", owner_player_id, player_id)) else -1.0
		total_utility += float(player_values[player_id_variant]) * relation_sign
	if not is_zero_approx(total_utility):
		return total_utility > 0.0
	# 缺少明确价值或总效用相抵时，以判定角色是否为友方作为稳定回退。
	return bool(host.call("is_friendly", owner_player_id, judgment_player_id))


## 判断一张牌是否满足通用判定条件；支持 colors、suits、点数区间及递归 not 组合。
func _matches_judgment_condition(card_data: Dictionary, condition: Dictionary) -> bool:
	if condition.has("not"):
		return not _matches_judgment_condition(card_data, condition.get("not", {}) as Dictionary)
	# 当前实体花色；none 不属于任何标准花色集合。
	var suit: String = str(card_data.get("suit", "none"))
	# 当前牌色；红桃方块为 red，黑桃梅花为 black。
	var color: String = str(card_data.get("color", "none"))
	if color == "none" and suit in STANDARD_SUITS:
		color = "red" if suit in ["heart", "diamond"] else "black"
	# 当前点数；范围1至13，异常值不会命中显式区间。
	var rank: int = int(card_data.get("rank", 0))
	if condition.has("colors") and not (condition.get("colors", []) as Array).has(color):
		return false
	if condition.has("suits") and not (condition.get("suits", []) as Array).has(suit):
		return false
	if condition.has("rank_min") and rank < int(condition.get("rank_min", 1)):
		return false
	if condition.has("rank_max") and rank > int(condition.get("rank_max", 13)):
		return false
	return true


## 返回观看牌的基础保留价值；优先读取 ai_use_value，再回退 ai.value 首项或常数1。
func _estimate_card_value(candidate: Dictionary) -> float:
	# 当前候选牌面；定义 ID 对戏法持有者可见。
	var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
	# 当前卡牌静态定义；AI 数值只用于同等判定结果下的排序。
	var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
	if definition.has("ai_use_value"):
		return float(definition.get("ai_use_value", AI_DEFAULT_CARD_VALUE))
	# 卡牌 AI 配置；value 可为单值或按持有数量递减的数组。
	var ai_profile: Dictionary = definition.get("ai", {}) as Dictionary
	# 基础牌值；数组读取首项，空数组与缺失字段均回退1。
	var value: Variant = ai_profile.get("value", AI_DEFAULT_CARD_VALUE)
	return float((value as Array)[0]) if value is Array and not (value as Array).is_empty() else float(value)


## AI 对戏法确认动作固定给出高正分；排序请求只有一个合法确认动作，无需额外评分。
func score_ai_choice(_authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, _evaluator: Object) -> float:
	# 请求上下文；只识别戏法的发动确认，不影响其他技能或最终排序动作。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 选择负载；取消保持0分，确认固定为高正收益。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if str(context.get("kind", "")) == "xifa_confirm" and bool(payload.get("confirmed", false)):
		return AI_ALWAYS_ACTIVATE_SCORE
	return 0.0
