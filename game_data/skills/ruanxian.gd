extends SkillDefinition

## 【阮弦】技能源码。结束阶段：重铸一张锦囊牌（每种花色限一次），
## 然后令所有拥有技能“梅绽”的**其他**角色各摸一张牌。
##
## “每种花色限一次”与【灵赋】的“每种类别限一次”同为**整局**额度，记录在持有者的 `character_form_state` 中；
## 项目不会在读档、复原武将牌或换将时清空该字段，因此失去技能后重新获得也不会复活额度。
##
## “其他角色”按项目既有口径固定表示排除技能持有者本人：阮梅自己**不会**因本技能摸牌，
## 即使她固有拥有“梅绽”。这与【梅绽】明确包含自己形成对照，两者都必须保持。
##
## 结束阶段可能在外层技能效果内部被同步派发，此时直接创建选择会被控制器静默丢弃；
## 因此按规范两段式处理：先复核条件，再判嵌套屏障，屏障为真时登记重建步骤而不是创建请求。
##
## 结束阶段创建的选择不会吞掉回合推进：控制器会暂停回合尾部，
## 待本技能产生的全部连续选择完成后再派发 phaseAfter 并推进回合，因此本技能不需要自行处理回合推进。

## 本技能稳定ID；日志与失去技能都按该 ID 判定。
const RUANXIAN_SKILL_ID: String = "ruanxian"

## 被检查的目标技能稳定ID。
const MEIZHAN_SKILL_ID: String = "meizhan"

## 选牌请求的业务键；continue_selection 按它分流。
const CHOICE_KIND: String = "ruanxian_recast_trick"

## 重建入口业务键；结束阶段存在嵌套屏障时登记它，等屏障解除后重新创建同一条请求。
const REBUILD_KIND: String = "ruanxian_rebuild_entry"

## 全局限次记录在 PlayerState.character_form_state 中的稳定键名；值类型为 Array[String]。
const USED_SUITS_KEY: String = "ruanxian_used_suits"

## 四种花色；与 CardInstance.is_valid_suit() 的取值一一对应，也是“每种花色限一次”的全部取值范围。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]

## 可重铸的牌类别；原文限定为锦囊牌，与 CardDefinition 的 type 取值一致。
const TRICK_CARD_TYPE: String = "trick"

## 每名其他“梅绽”持有者获得的摸牌数；修改后必须同步技能描述与玩法数值文档。
const DRAW_COUNT: int = 1

## 重铸一张牌的机会成本系数；沿用【连戏】的既有口径，使不同重铸技能的 AI 代价可比。
const AI_RECAST_COST_RATIO: float = 0.35

## 每名受益队友摸一张牌的价值；按统一资源尺度计价。
const AI_BENEFICIARY_VALUE: float = NonameAIEvaluator.CARD_RESOURCE_VALUE

## 本技能此刻不可能产生收益时的动作评分（没有队友受益者）；
## 必须严格为负，否则会与“结束阶段无动作”的 0 分打平而让 AI 白重铸一张锦囊。
const AI_UNPAYABLE_ACTION_SCORE: float = -100.0

## 选择动作缺少唯一材料时的评分；必须远低于取消动作的 0 分。
const AI_INVALID_CHOICE_SCORE: float = -10.0


## 写入结束阶段技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": RUANXIAN_SKILL_ID,
		"name": "阮弦",
		"trigger": "phaseEnd",
		"ui_enabled": false,
		"description": "结束阶段，你可以重铸一张锦囊牌（每种花色限一次），然后令所有拥有技能“梅绽”的其他角色各摸一张牌。",
	})


## 订阅持有者每个回合的结束阶段；其他角色的结束阶段不触发。
func install() -> void:
	subscribe_timing("phaseEnd", _on_owner_phase_end, "player")


## 返回本局已被【阮弦】重铸过的花色集合；字段缺失或类型异常时按空集合处理，避免旧存档阻断技能。
func _get_used_suits() -> Array[String]:
	# 技能持有者；实例始终绑定持有者，取不到状态时按空集合处理。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return []
	return _to_string_array(owner.character_form_state.get(USED_SUITS_KEY, []) as Array)


## 把一个花色写入全局已用集合；重复写入不产生第二条记录。
func _mark_used_suit(suit: String) -> void:
	# 技能持有者；取不到状态时不写入任何记录。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or suit.is_empty():
		return
	# 追加后的花色数组；先取副本再整体写回，保持 character_form_state 只保存纯数据。
	var used_suits: Array[String] = _get_used_suits()
	if used_suits.has(suit):
		return
	used_suits.append(suit)
	owner.character_form_state[USED_SUITS_KEY] = used_suits


## 把任意数组安全转换为字符串数组；读档或旧数据可能保存未标注元素类型的数组。
func _to_string_array(source: Array) -> Array[String]:
	# 转换结果；非字符串元素按字符串语义取值，避免异常写入阻断技能。
	var result: Array[String] = []
	for entry: Variant in source:
		result.append(str(entry))
	return result


## 返回指定牌名所属的牌类别；取不到定义时返回空字符串，调用方按“不可重铸”处理。
func _get_card_category(definition_id: String) -> String:
	return str(GameDatabase.get_card(definition_id).get("type", ""))


## 判断指定牌此刻是否仍有全局花色额度；这是候选枚举与提交复核共用的唯一额度判定入口。
func _has_suit_quota(definition_id: String, suit: String) -> bool:
	# 花色必须属于四种标准花色，且该牌必须是锦囊牌。
	if not CARD_SUITS.has(suit) or _get_card_category(definition_id) != TRICK_CARD_TYPE:
		return false
	return not _get_used_suits().has(suit)


## 返回本次仍可重铸的锦囊牌候选；已用尽额度的花色整体不出现在候选里，因此 AI 无需再判额度。
## 本人手牌对本人可见，因此按花色过滤不违反隐藏信息规则（与【天坠】按牌类别过滤同类）。
func _get_recast_candidates() -> Array[Dictionary]:
	# 全部普通手牌候选；由控制器统一序列化，界面、AI 与网络使用同一份牌面数据。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 过滤后的候选；保持原手牌顺序，使界面列表顺序与手牌完全一致。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		# 当前候选的牌面数据；花色与牌名都必须可读。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if _has_suit_quota(str(card_data.get("definition_id", "")), str(card_data.get("suit", ""))):
			result.append(candidate)
	return result


## 返回所有“其他”拥有“梅绽”的角色ID；**排除技能持有者本人**，与【梅绽】包含自己形成对照。
func _get_other_meizhan_holder_ids() -> Array[int]:
	# 受益者ID列表；按座次顺序收集，保证摸牌日志顺序与回放结果稳定。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		# “其他角色”固定表示排除技能持有者；死亡或离场者不会摸牌。
		if player.player_id == owner_player_id or not player.alive or player.out_of_game:
			continue
		# 拥有判定走项目唯一入口；被【灵赋】授予或被【留白】类效果剥夺都会如实反映。
		if not bool(host.call("has_skill", player.player_id, MEIZHAN_SKILL_ID)):
			continue
		result.append(player.player_id)
	return result


## 判断此刻是否值得创建选择窗口：持有者存活在场 + 有可重铸锦囊 + 至少一名其他受益者。
## 三者缺一就不创建任何请求，避免出现“点了也没有收益”的空窗口。
func _can_offer() -> bool:
	# 技能持有者；死亡或离场时结束阶段不再询问。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	return not _get_recast_candidates().is_empty() and not _get_other_meizhan_holder_ids().is_empty()


## 持有者回合结束阶段：先复核条件，再判嵌套屏障，最后创建重铸选牌请求。
func _on_owner_phase_end(_event: RuleEvent) -> void:
	if not _can_offer():
		return
	# 嵌套屏障：本时机由外层技能效果同步派发时，直接创建的选择会被静默丢弃，
	# 因此登记一个重建步骤，等屏障解除后由 continue_settlement 重新复核并创建同一条请求。
	if bool(host.call("has_nested_settlement_barrier")):
		defer_settlement({"kind":REBUILD_KIND})
		return
	_request_recast_selection()


## 创建重铸选牌请求；首次进入与屏障解除后的重建共用同一份请求构造。
func _request_recast_selection() -> void:
	request_card_selection("阮弦", "请选择一张锦囊牌重铸；确定后令所有其他拥有“梅绽”的角色各摸一张牌", _get_recast_candidates(), 1, 1, true, {"kind":CHOICE_KIND})


## 恢复重铸选牌：先复核材料，再重铸，最后登记摸牌结算。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CHOICE_KIND or response == null:
		return false
	# 取消或数量不符：不消耗任何额度，直接结束本次发动。
	if not response.confirmed or response.card_ids.size() != 1:
		return true
	# 材料复核；必须仍是本人普通手牌区中的锦囊牌，且其花色仍有全局额度。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return true
	# 被选中的费用牌；木牛“粮”、装备与判定牌都不会被 find_hand_card 返回。
	var cost_card: CardInstance = owner.find_hand_card(response.card_ids[0])
	if cost_card == null or not _has_suit_quota(cost_card.definition_id, cost_card.suit):
		return true
	# 费用稳定快照；成功后记录原花色与牌名。
	var cost_uid: int = cost_card.uid
	# 原费用花色；跨等待只保留标量。
	var cost_suit: String = cost_card.suit
	# 原费用牌名；移牌清理临时视为后仍按发动时牌面记录。
	var cost_definition_id: String = cost_card.definition_id
	run_steps([
		func(sequence: RuleStepSequence) -> void: sequence.effect_result = host.recast_hand_card(owner_player_id, cost_uid),
		func(sequence: RuleStepSequence) -> void:
			if sequence.effect_result == null or sequence.effect_result.count <= 0:
				sequence.finish()
				return
			_mark_used_suit(cost_suit)
			announce_activation({"recast_definition_id":cost_definition_id, "recast_suit":cost_suit, "beneficiary_ids":_get_other_meizhan_holder_ids()}),
		func(_sequence: RuleStepSequence) -> void: _resolve_beneficiary_draw(),
	])
	return true


## 恢复结束阶段存在外部选择时登记的重建入口；费用后续由公共步骤内容持有。
func continue_settlement(context: Dictionary) -> bool:
	# 重建入口：屏障解除后重新复核条件并重建同一条请求；期间条件已不成立则安静结束。
	if str(context.get("kind", "")) == REBUILD_KIND:
		if _can_offer():
			_request_recast_selection()
		return true
	return false


## 令所有其他“梅绽”持有者各摸一张牌；受益人集合在兑现这一刻重新计算，反映等待期间的变化。
func _resolve_beneficiary_draw() -> void:
	if host == null:
		return
	# 每名受益人的摸牌互为连续步骤，前一人的After完成后再轮到下一人。
	var steps: Array[Callable] = []
	for player_id: int in _get_other_meizhan_holder_ids():
		steps.append(func(_sequence: RuleStepSequence) -> void: host.draw(player_id, DRAW_COUNT))
	run_steps(steps)


## 返回本次重铸的机会成本；取“AI 实际会选中的最低价值候选”折算。
## 动作层与选择层共用本函数与同一系数，避免出现“提议发动后立刻取消”的死循环（【天坠】的既有教训）。
func _get_recast_cost_value(authoritative_snapshot: Dictionary, evaluator: Object) -> float:
	# 可用候选的保留价值；为空表示没有任何可重铸的锦囊牌。
	var candidate_values: Array[float] = _get_ai_candidate_values(authoritative_snapshot, evaluator)
	if candidate_values.is_empty():
		return 0.0
	# 最低保留价值；AI 在多个候选中总是选择价值最低的那张。
	var lowest_value: float = candidate_values[0]
	for value: float in candidate_values:
		lowest_value = minf(lowest_value, value)
	return lowest_value * AI_RECAST_COST_RATIO


## 收集 AI 视角下仍可重铸的候选牌保留价值。
## 额度判定与规则段共用同一常量与同一字段名，因此 AI 不会另建第二套“哪些花色还能重铸”的判断。
func _get_ai_candidate_values(authoritative_snapshot: Dictionary, evaluator: Object) -> Array[float]:
	# 持有者快照；缺失时表示没有可用材料。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return []
	# 已用花色集合；字段缺失或类型异常时按空集合处理，与规则段读取口径完全一致。
	var used_suits: Array[String] = _to_string_array(owner.get(USED_SUITS_KEY, []) as Array)
	# 候选保留价值；按手牌顺序收集。
	var values: Array[float] = []
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌快照；本人手牌对本人可见，因此定义ID与花色一定可读。
		var card: Dictionary = card_variant as Dictionary
		# 当前牌名ID与花色；只保留“锦囊牌 + 花色仍有额度”的候选。
		var definition_id: String = str(card.get("definition_id", ""))
		var suit: String = str(card.get("suit", ""))
		if _get_card_category(definition_id) != TRICK_CARD_TYPE or not CARD_SUITS.has(suit) or used_suits.has(suit):
			continue
		values.append(float(evaluator.get_card_value_by_id(definition_id, authoritative_snapshot, owner_player_id)))
	return values


## 返回 AI 视角下本次发动的受益者净数：摸牌的队友为正、摸牌的敌方为负、身份未暴露者不计入。
## 自己固定不参与（原文是“其他角色”），因此不需要像【梅绽】那样把出手方算进我方。
func _get_ai_net_beneficiary_count(authoritative_snapshot: Dictionary, evaluator: Object) -> int:
	# 受益者净计数；正数表示这次摸牌整体有利于持有者一侧。
	var net_count: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；字段缺失时按无效条目跳过。
		var player: Dictionary = player_variant as Dictionary
		# 技能持有者本人不摸牌，与规则段“其他角色”的口径完全一致。
		var player_id: int = int(player.get("player_id", -1))
		if player_id < 0 or player_id == owner_player_id:
			continue
		if not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		# 持有判定走快照侧统一入口；与规则段共用同一套来源清单与“实际安装”裁剪规则。
		if not snapshot_has_skill(player, MEIZHAN_SKILL_ID):
			continue
		# 持有者对该受益者的公开态度；只用 get_attitude，不用 get_real_attitude，避免泄露隐藏身份。
		var attitude: float = float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id))
		if attitude > 0.0:
			net_count += 1
		elif attitude < 0.0:
			net_count -= 1
	return net_count


## 评估【阮弦】的发动收益：受益队友数 × 一张牌的价值 − 重铸机会成本。
## 结束阶段虽然是“免费时机”，但仍需评估材料的机会成本，不能无脑发动。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	# 可用材料；为空时本技能不可能发动。
	if _get_ai_candidate_values(authoritative_snapshot, evaluator).is_empty():
		return AI_UNPAYABLE_ACTION_SCORE
	# 受益者净数；没有正收益时严格负分，避免白重铸一张锦囊。
	var net_beneficiary_count: int = _get_ai_net_beneficiary_count(authoritative_snapshot, evaluator)
	if net_beneficiary_count <= 0:
		return AI_UNPAYABLE_ACTION_SCORE
	return float(net_beneficiary_count) * AI_BENEFICIARY_VALUE - _get_recast_cost_value(authoritative_snapshot, evaluator)


## 评估【阮弦】选牌请求的确认动作；取消恒为0分，因此只有收益高于材料机会成本时才会确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理本技能自己的选牌请求。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	# 动作负载；取消动作表示放弃本次发动。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选材料；必须恰好一张，否则不是一次有效发动。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != 1:
		return AI_INVALID_CHOICE_SCORE
	# 材料机会成本；按被选中牌的实际保留价值折算，使 AI 优先重铸价值最低的锦囊。
	# 该式与 _get_recast_cost_value() 同源：后者取候选最小值，正好等于本式在全部候选上的最大值。
	var material_cost: float = float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)) * AI_RECAST_COST_RATIO
	return float(_get_ai_net_beneficiary_count(authoritative_snapshot, evaluator)) * AI_BENEFICIARY_VALUE - material_cost
