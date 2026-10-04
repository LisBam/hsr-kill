extends SkillDefinition

## 【盲注】摸牌阶段开始时，你可以弃置任意张颜色不同的牌。若如此做，该阶段结束时：
## 若你以此法弃置的牌与你于此阶段内获得的牌有至少一种颜色相同，你获得1点护盾；
## 若有至少两种颜色相同，你摸两张牌。
##
## 三条实现要点：
## 1) **一次多选，颜色互斥由权威组合表表达**：本技能把「所有单张」与「所有异色两张组合」
##    预先枚举进 `context.valid_card_combinations`，玩家因此可以一次点选两张牌，
##    而界面上会依据同一张表把「与已选牌同色」的候选项压暗并停止接收点击；
##    控制器提交时再用同一张表复核。因此「颜色不同」既不需要分两次操作，也不可能被绕过。
## 2) **获得的颜色只在摸牌阶段内累计**：用 `turn_number` + `current_phase == "draw"`
##    双条件过滤 `gainAfter`。获得类时机的 `player_id` 就是获得方，配合 `role="player"`
##    天然只命中砂金自己的获得，无需再按玩家 ID 过滤。
## 3) **结算点在 `phaseDrawEnd`**：此时摸牌主体已完成，护盾与摸牌都不会打断摸牌阶段
##    本身的推进；`phaseDrawSkipped` / `phaseDrawCancelled` 只清空本次记录，不结算。

## 阶段名称；只有真正的摸牌阶段才累计获得的颜色，其他阶段（如额外出牌阶段内的摸牌）不计入。
const DRAW_PHASE_NAME: String = "draw"
## 手牌区域名；只有落入该区域的获得才计入颜色，进入装备区或判定区的移动不计。
const HAND_ZONE_NAME: String = "hand"
## 无色牌的稳定标识；无色牌既不能作为费用，也不能让颜色重合，因此两侧都跳过。
const COLORLESS: String = "colorless"
## 颜色去重后的最大种数；本项目只有红、黑两色，因此一次最多点选两张异色牌即可穷尽。
const MAX_DISTINCT_COLOURS: int = 2
## 每有一种颜色重合获得的护盾点数。
const SHIELD_PER_COMMON_COLOUR: int = 1
## 两种颜色全部重合时额外摸取的张数；与护盾叠加生效，因此两种颜色都重合时总计1点护盾加2张牌。
const DRAW_ON_BOTH_COLOURS: int = 2
## 「至少两种颜色相同」的阈值；用于区分只有1种重合与2种都重合。
const BOTH_COLOURS_COMMON_COUNT: int = 2
## 本次弃牌请求的种类；恢复回调据此识别步骤。
const CHOICE_KIND_PICK: String = "mangzhu_pick"
## 请求与延迟上下文中共用的种类键名。
const CHOICE_KIND_KEY: String = "kind"
## 摸牌阶段开始时的选择窗口遇到嵌套结算时的延迟种类；嵌套收尾后重建同一条请求。
const DEFER_BEGIN_PICK: String = "mangzhu_defer_begin_pick"
## 权威合法组合表在请求上下文中的键名；核心的界面与提交校验都读取该键。
const VALID_COMBINATIONS_KEY: String = "valid_card_combinations"
## 请求允许的最小选择张数；0表示允许「什么都不选就确认」，该确认按未发动处理（可取消窗口用取消表示放弃）。
const MIN_SELECT: int = 0
## 发动公告中「重合颜色」的键名；取值为颜色字符串数组，便于界面与回放展示。
const ACTIVATION_COMMON_KEY: String = "common_colours"
## 发动公告中「护盾点数」的键名。
const ACTIVATION_SHIELD_KEY: String = "shield"
## 发动公告中「额外摸牌张数」的键名；两种颜色都重合时为 DRAW_ON_BOTH_COLOURS，否则为0。
const ACTIVATION_DRAW_KEY: String = "draw_count"
## 尚未绑定到任何摸牌阶段的回合号；与真实回合号（从1开始）不冲突，用于拒绝迟到事件。
const UNBOUND_TURN_NUMBER: int = -1
## 持有者手牌与装备区的装备槽顺序；与核心的候选顺序保持一致，避免同一份区域出现两套遍历顺序。
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]
## 玩家选择的标题；与技能名一致，便于在同一界面里区分多个技能请求。
const SKILL_TITLE: String = "盲注"
## 选择窗口的提示文本；说明一次可以选最多两张异色牌，也可以取消放弃本次机会。
const PICK_PROMPT: String = "你可以一次选出一至两张颜色不同的牌弃置（与本次摸牌同色的部分将换取护盾与摸牌），或取消"
## 确认提交的保底分；远高于任何单张牌面收益，使「是否弃牌」只由真实收益的小数部分决定。
const AI_STEP_COMMIT_REWARD: float = 100.0
## 弃置一种颜色的建色价值；等价于「换来一次结算机会」的期望收益，约等于1点护盾。
const AI_DISCARD_SETUP_VALUE: float = 1.2
## 弃置两种颜色的建色价值倍率；补齐两种颜色后，摸到的任意一张牌都必然与其中一种重合，
## 因此第二种颜色的边际价值明显高于第一种。
const AI_SECOND_COLOUR_BONUS: float = 2.0
## 费用牌保留价值的权重；避免为了小额收益弃置关键的【桃】或【闪】。
const AI_COST_WEIGHT: float = 0.35
## 应当放弃本次弃置时的负分；通用评分给「取消」的基准是0.0，因此必须给出严格负分才能让取消成为最优解。
const AI_DECLINE_PENALTY: float = 5.0

## 本次记录绑定的回合号；用于拒绝上一个摸牌阶段的迟到事件。
var _turn_number: int = UNBOUND_TURN_NUMBER
## 本次摸牌阶段是否已真实弃置至少一张牌；为假时不累计获得的颜色，也不结算。
var _active: bool = false
## 以此法弃置的牌的颜色（去重，最多 MAX_DISTINCT_COLOURS 项）。
var _discarded_colours: Array[String] = []
## 本阶段内持有者获得的、落入手牌的牌的颜色（去重，最多 MAX_DISTINCT_COLOURS 项）。
var _gained_colours: Array[String] = []


func _init() -> void:
	super({
		"id": "mangzhu",
		"name": "盲注",
		"trigger": "phaseDrawBegin",
		"ui_enabled": false,
		"description": "摸牌阶段开始时，你可以弃置任意张颜色不同的牌。若如此做，该阶段结束时，若你以此法弃置的牌与你于此阶段内获得的牌有至少一种颜色相同，你获得1点护盾；若有至少两种颜色相同，你摸两张牌。",
	})


func install() -> void:
	subscribe_timing("phaseDrawBegin", _on_phase_draw_begin, "player")
	subscribe_timing("gainAfter", _on_gain_after, "player")
	subscribe_timing("phaseDrawEnd", _on_phase_draw_end, "player")
	subscribe_timing("phaseDrawSkipped", _on_phase_draw_aborted, "player")
	subscribe_timing("phaseDrawCancelled", _on_phase_draw_aborted, "player")


## 摸牌阶段开始：重置本次记录，然后在存在可弃置牌时开放选择窗口。
func _on_phase_draw_begin(_event: RuleEvent) -> void:
	if _owner_ready() == null:
		return
	# 只处理持有者自己的摸牌阶段；`role="player"` 已保证阶段角色是持有者，这里再校验阶段名以排除同回合的其他阶段事件。
	if int(host.state.current_player_id) != owner_player_id or str(host.state.current_phase) != DRAW_PHASE_NAME:
		return
	_reset_phase_state()
	if _collect_discard_candidates().is_empty():
		return
	if host.has_nested_settlement_barrier():
		defer_settlement({CHOICE_KIND_KEY:DEFER_BEGIN_PICK})
		return
	_begin_pick()


## 累计本阶段内获得的颜色；只有真实弃置过、且仍在同一回合的摸牌阶段内才记录。
func _on_gain_after(event: RuleEvent) -> void:
	if not _active or host == null:
		return
	if str(event.data.get("to_zone", "")) != HAND_ZONE_NAME:
		return
	if int(host.state.turn_number) != _turn_number or str(host.state.current_phase) != DRAW_PHASE_NAME:
		return
	# 技能持有者权威状态；用于把手牌 UID 解析成实体并读取颜色。
	var owner: PlayerState = _owner_ready()
	if owner == null:
		return
	for uid_variant: Variant in event.data.get("card_uids", []) as Array:
		# 本次入手的具体实体；已经被其他效果移出手牌时跳过，不把未知颜色计入记录。
		var card: CardInstance = owner.find_hand_card(int(uid_variant))
		if card == null:
			continue
		# 实体当前颜色；临时视为牌会读取自己的颜色覆盖值，因此这里不能按月色花色反推。
		var colour: String = card.get_color()
		if colour.is_empty() or colour == COLORLESS:
			continue
		if not _gained_colours.has(colour):
			_gained_colours.append(colour)


## 摸牌阶段正常结束：先按重合颜色结算，再清空本次记录。
func _on_phase_draw_end(_event: RuleEvent) -> void:
	_resolve_phase_result()
	_reset_phase_state()


## 摸牌阶段被跳过或取消：本次没有获得牌，直接清空记录，不产生任何效果。
func _on_phase_draw_aborted(_event: RuleEvent) -> void:
	_reset_phase_state()


## 恢复由本技能创建的选择；本技能只有一个选择窗口，按种类分派。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 请求种类；不是本技能的步骤时交回控制器继续查找其他技能。
	var kind: String = str(context.get(CHOICE_KIND_KEY, ""))
	if kind == CHOICE_KIND_PICK:
		if response != null and response.confirmed:
			_apply_pick(response.card_ids)
		return true
	return false


## 恢复因嵌套结算暂停的步骤；重新建立同一条选择窗口。
func continue_settlement(context: Dictionary) -> bool:
	# 延迟种类；未识别时交回控制器。
	var kind: String = str(context.get(CHOICE_KIND_KEY, ""))
	if kind == DEFER_BEGIN_PICK:
		_begin_pick()
		return true
	return false


## 建立本次选择窗口；候选为持有者手牌与装备区中所有有颜色的牌，一次最多选两张异色牌。
func _begin_pick() -> void:
	# 全部可弃置候选；顺序沿用核心的手牌区、装备区顺序。
	var candidates: Array[Dictionary] = _collect_discard_candidates()
	if candidates.is_empty():
		return
	# 权威合法组合表；界面据此压暗同色候选，控制器据此复核提交。
	var valid_combinations: Array = _build_valid_combinations(candidates)
	var selected: Array[int] = request_card_selection(SKILL_TITLE, PICK_PROMPT, candidates, MIN_SELECT, MAX_DISTINCT_COLOURS, true, {CHOICE_KIND_KEY:CHOICE_KIND_PICK, VALID_COMBINATIONS_KEY:valid_combinations})
	# 无正式对局 ID 的同步规则测试不会通过 continue_selection 回调，需在此直接应用返回结果。
	if not host.has_pending_card_choice():
		_apply_pick(selected)


## 处理本次选择结果：按点选顺序逐张弃置并记录实际弃置成功的颜色。
## 一张都没选（空确认）或全部弃置失败时按未发动处理，不产生任何记录。
func _apply_pick(selected_uids: Array[int]) -> void:
	if selected_uids.is_empty() or host == null:
		return
	# 实际弃置成功的颜色；单张失败不影响其余牌，因此逐张调用统一弃置端口。
	var discarded_colours: Array[String] = []
	for card_uid: int in selected_uids:
		# 本张牌的颜色；弃置失败时为空串，不写入记录。
		var colour: String = _discard_one_card(card_uid)
		if colour.is_empty():
			continue
		if not discarded_colours.has(colour):
			discarded_colours.append(colour)
	if discarded_colours.is_empty():
		return
	_active = true
	for colour: String in discarded_colours:
		if not _discarded_colours.has(colour):
			_discarded_colours.append(colour)


## 枚举权威合法组合：任意单张，以及任意两张异色牌；额外包含空组合，使「什么都不选就确认」
## 通过提交校验并按未发动处理，而不是弹出难以理解的组合非法提示。
func _build_valid_combinations(candidates: Array[Dictionary]) -> Array:
	# 最终组合表；每项都是 UID 数组。
	var result: Array = []
	# 空组合；对应「确认但没有选择任何牌」。
	result.append([])
	# 每张候选的颜色；与候选同序，供两两组合时比较。
	var colour_by_uid: Dictionary = {}
	for candidate: Dictionary in candidates:
		# 当前候选 UID；非法 UID 不进入组合表，避免生成永远无法提交的组合。
		var card_uid: int = int(candidate.get("uid", -1))
		if card_uid < 0:
			continue
		colour_by_uid[card_uid] = _candidate_colour(candidate)
		result.append([card_uid])
	for first_index: int in range(candidates.size()):
		# 组合中的第一张候选；方向固定为「下标小的在前」，保证组合表不出现重复项。
		var first_uid: int = int((candidates[first_index] as Dictionary).get("uid", -1))
		if first_uid < 0:
			continue
		for second_index: int in range(first_index + 1, candidates.size()):
			# 组合中的第二张候选；两张颜色相同则不构成合法组合。
			var second_uid: int = int((candidates[second_index] as Dictionary).get("uid", -1))
			if second_uid < 0:
				continue
			# 两张牌的颜色；任一为空说明牌已离开区域，不生成组合。
			var first_colour: String = str(colour_by_uid.get(first_uid, ""))
			var second_colour: String = str(colour_by_uid.get(second_uid, ""))
			if first_colour.is_empty() or second_colour.is_empty() or first_colour == second_colour:
				continue
			result.append([first_uid, second_uid])
	return result


## 按重合颜色结算护盾与摸牌；没有重合颜色时本次不产生任何效果。
func _resolve_phase_result() -> void:
	if not _active or host == null:
		return
	# 与阶段内获得的牌重合的颜色集合；只有本项目真实存在的红、黑两色可能出现在这里。
	var common_colours: Array[String] = []
	for colour: String in _discarded_colours:
		if _gained_colours.has(colour):
			common_colours.append(colour)
	if common_colours.is_empty():
		return
	# 额外摸牌张数；两种颜色都重合时才成立，与护盾叠加生效。
	var draw_count: int = DRAW_ON_BOTH_COLOURS if common_colours.size() >= BOTH_COLOURS_COMMON_COUNT else 0
	announce_activation({ACTIVATION_COMMON_KEY:common_colours.duplicate(), ACTIVATION_SHIELD_KEY:SHIELD_PER_COMMON_COLOUR, ACTIVATION_DRAW_KEY:draw_count})
	host.call("shield", owner_player_id, SHIELD_PER_COMMON_COLOUR, owner_player_id, get_id())
	if draw_count > 0:
		host.call("draw", owner_player_id, draw_count)


## 清空本次摸牌阶段的记录并绑定当前回合号；每次进入摸牌阶段都会重新绑定，旧回合的迟到事件因此失效。
func _reset_phase_state() -> void:
	_turn_number = int(host.state.turn_number) if host != null and host.state != null else UNBOUND_TURN_NUMBER
	_active = false
	_discarded_colours.clear()
	_gained_colours.clear()


## 收集可以作为费用的候选；无色牌不能参与「颜色不同」的构造，因此直接跳过。
func _collect_discard_candidates() -> Array[Dictionary]:
	# 最终候选；顺序沿用核心的手牌区、装备区顺序。
	var result: Array[Dictionary] = []
	if host == null:
		return result
	# 持有者自己的手牌与装备区；本技能只弃置自己的牌，因此查看者与目标都是持有者。
	var raw_candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	for candidate: Dictionary in raw_candidates:
		# 当前候选的颜色；无色牌不参与组合枚举，也不下发为候选。
		var colour: String = _candidate_colour(candidate)
		if colour.is_empty() or colour == COLORLESS:
			continue
		result.append(candidate)
	return result


## 读取候选的颜色；通过实体本身读取以沿用临时视为牌的颜色覆盖值。
func _candidate_colour(candidate: Dictionary) -> String:
	# 候选对应的实体；已经离开区域时返回空串，调用方按不可用处理。
	var card: CardInstance = _find_owned_card(int(candidate.get("uid", -1)))
	if card == null:
		return ""
	return card.get_color()


## 弃置持有者的一张牌并返回其颜色；弃置失败时返回空串，调用方不得记录该颜色。
func _discard_one_card(card_uid: int) -> String:
	# 待弃置实体；必须在弃置前读取颜色，弃置后它已经离开持有者区域。
	var card: CardInstance = _find_owned_card(card_uid)
	if card == null:
		return ""
	# 实体当前颜色；弃置前读取，保证记录的是玩家实际看到的那张牌的颜色。
	var colour: String = card.get_color()
	# 弃置请求载荷；统一弃置端口按 UID 在三个区域中查找，因此手牌与装备区共用同一条路径。
	var selected_uids: Array[int] = [card_uid]
	if int(host.call("discard_selected_hand_equipment", owner_player_id, selected_uids)) != 1:
		return ""
	return colour


## 按稳定 UID 在持有者手牌区与装备区中查找实体；未找到时返回 null。
func _find_owned_card(card_uid: int) -> CardInstance:
	# 技能持有者权威状态；未就绪时没有可查询区域。
	var owner: PlayerState = _owner_ready()
	if owner == null:
		return null
	# 手牌区命中；本技能绝大多数费用来自手牌，因此优先查询。
	var hand_card: CardInstance = owner.find_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for slot: String in EQUIPMENT_SLOTS:
		var slot_card: Variant = owner.equipment.get(slot, null)
		if slot_card is CardInstance and (slot_card as CardInstance).uid == card_uid:
			return slot_card as CardInstance
	return null


## 返回可用的技能持有者状态；未安装、已阵亡或已离场时返回 null。
func _owner_ready() -> PlayerState:
	if host == null:
		return null
	# 技能持有者权威状态；技能卸载后 get_owner_skill_player() 仍可返回玩家，因此必须同时校验存活与在场。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return null
	return owner


## 计算基础 AI 对一次弃牌确认的评分；应当放弃时返回严格负分，让通用评分的「取消」基准胜出。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	# 请求种类；只有本技能的选择窗口参与评分，其他请求交回通用评分。
	var kind: String = str((choice_request.get("context", {}) as Dictionary).get(CHOICE_KIND_KEY, ""))
	if kind != CHOICE_KIND_PICK:
		return 0.0
	# 动作载荷；取消是合法选择，按0分交回通用比较。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 本次选中的牌；空数组表示「空确认」，按未发动处理并交回通用评分。
	var selected_uids: Array = payload.get("selected_card_uids", []) as Array
	if selected_uids.is_empty():
		return 0.0
	# 权威合法组合表；核心只会为合法组合生成动作，这里再校验一次以防上层伪造。
	var valid_combinations: Array = (choice_request.get("context", {}) as Dictionary).get(VALID_COMBINATIONS_KEY, []) as Array
	if not _is_valid_selection(valid_combinations, selected_uids):
		return -AI_DECLINE_PENALTY
	# 本步弃置的牌对持有者的保留价值总和。
	var cost_value: float = 0.0
	for uid_variant: Variant in selected_uids:
		cost_value += float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(uid_variant), owner_player_id))
	# 本步的建色价值；一次弃置两种颜色时摸到的牌必然与其中一种重合，因此价值更高。
	var setup_value: float = AI_DISCARD_SETUP_VALUE if selected_uids.size() < MAX_DISTINCT_COLOURS else AI_DISCARD_SETUP_VALUE * AI_SECOND_COLOUR_BONUS
	# 净收益；为负说明这些牌比本次建色价值更贵，应当取消。
	var net_value: float = setup_value - cost_value * AI_COST_WEIGHT
	if net_value <= 0.0:
		return -AI_DECLINE_PENALTY
	return AI_STEP_COMMIT_REWARD + net_value


## 判断一组提交的 UID 是否精确等于组合表中的某一项；排序后比较，点击顺序不影响结论。
func _is_valid_selection(valid_combinations: Array, selected_uids: Array) -> bool:
	# 提交集合的排序副本；与组合表逐项精确比较。
	var normalized_selected: Array[int] = []
	for uid_variant: Variant in selected_uids:
		normalized_selected.append(int(uid_variant))
	normalized_selected.sort()
	for combination_variant: Variant in valid_combinations:
		# 当前组合的排序副本；UID 数量不同时不可能相等。
		var normalized_combination: Array[int] = []
		for uid_variant: Variant in combination_variant as Array:
			normalized_combination.append(int(uid_variant))
		normalized_combination.sort()
		if normalized_combination == normalized_selected:
			return true
	return false


## 计算基础 AI 对一次结算的价值；本技能是被动触发，没有主动入口，因此主动动作恒为0分。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0
