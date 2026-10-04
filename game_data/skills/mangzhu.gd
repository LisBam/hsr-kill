extends SkillDefinition

## 【盲注】摸牌阶段开始时，你可以弃置任意张颜色不同的牌。若如此做，该阶段结束时：
## 若你以此法弃置的牌与你于此阶段内获得的牌有至少一种颜色相同，你获得1点护盾；
## 若有至少两种颜色相同，你摸两张牌。
##
## 三条实现要点：
## 1) **两次单选而不是一次多选**：第二张的候选集合由「颜色与第一张不同」直接构造，
##    因此「颜色不同」是候选集合的构造性质，而不是提交后校验的规则。玩家与 AI
##    都不可能选出非法组合，也就不存在「非法提交→重问」的循环。
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
## 颜色去重后的最大种数；本项目只有红、黑两色，因此两次单选即可穷尽。
const MAX_DISTINCT_COLOURS: int = 2
## 每有一种颜色重合获得的护盾点数。
const SHIELD_PER_COMMON_COLOUR: int = 1
## 两种颜色全部重合时额外摸取的张数；与护盾叠加生效，因此两种颜色都重合时总计1点护盾加2张牌。
const DRAW_ON_BOTH_COLOURS: int = 2
## 「至少两种颜色相同」的阈值；用于区分只有1种重合与2种都重合。
const BOTH_COLOURS_COMMON_COUNT: int = 2
## 第一张牌的请求种类；恢复回调据此识别步骤。
const CHOICE_KIND_FIRST: String = "mangzhu_pick_first"
## 第二张牌的请求种类；恢复回调据此识别步骤。
const CHOICE_KIND_SECOND: String = "mangzhu_pick_second"
## 请求与延迟上下文中共用的种类键名。
const CHOICE_KIND_KEY: String = "kind"
## 第一张弃置发生于嵌套结算期间时的延迟种类；嵌套选择收尾后重建第一张请求。
const DEFER_BEGIN_FIRST_PICK: String = "mangzhu_defer_first_pick"
## 第一张弃置引发嵌套结算时的延迟种类；嵌套选择收尾后再重建第二张请求。
const DEFER_BEGIN_SECOND_PICK: String = "mangzhu_defer_second_pick"
## 延迟上下文中携带「第一张牌颜色」的键名；第二张候选必须与它不同。
const FIRST_COLOUR_KEY: String = "first_colour"
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
## 第一张牌的提示文本；明确说明可以取消。
const FIRST_PROMPT: String = "你可以弃置一张牌（弃置这些牌与本次摸牌同色的部分将换取护盾与摸牌），或取消"
## 第二张牌的提示文本；说明第二张必须是另一种颜色。
const SECOND_PROMPT: String = "你可以再弃置一张颜色不同的牌，或取消"
## 确认提交的保底分；远高于任何单张牌面收益，使「是否弃牌」只由真实收益的小数部分决定。
const AI_STEP_COMMIT_REWARD: float = 100.0
## 第一张牌的建色价值；等价于「换来一次结算机会」的期望收益，约等于1点护盾。
const AI_DISCARD_SETUP_VALUE: float = 1.2
## 第二张牌的建色价值倍率；补齐两种颜色后，摸到的任意一张牌都必然与其中一种重合，
## 因此第二张牌的边际价值明显高于第一张。
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


## 摸牌阶段开始：重置本次记录，然后在存在可弃置牌时开放第一张请求。
func _on_phase_draw_begin(_event: RuleEvent) -> void:
	if _owner_ready() == null:
		return
	# 只处理持有者自己的摸牌阶段；`role="player"` 已保证阶段角色是持有者，这里再校验阶段名以排除同回合的其他阶段事件。
	if int(host.state.current_player_id) != owner_player_id or str(host.state.current_phase) != DRAW_PHASE_NAME:
		return
	_reset_phase_state()
	if _collect_discard_candidates("").is_empty():
		return
	if host.has_nested_settlement_barrier():
		defer_settlement({CHOICE_KIND_KEY:DEFER_BEGIN_FIRST_PICK})
		return
	_begin_first_pick()


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


## 恢复由本技能创建的选择；两步共用同一回调，按种类分派。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 请求种类；不是本技能的步骤时交回控制器继续查找其他技能。
	var kind: String = str(context.get(CHOICE_KIND_KEY, ""))
	if kind == CHOICE_KIND_FIRST:
		if response != null and response.confirmed:
			_apply_first_pick(response.card_ids)
		return true
	if kind == CHOICE_KIND_SECOND:
		if response != null and response.confirmed:
			_apply_second_pick(response.card_ids)
		return true
	return false


## 恢复因嵌套结算暂停的步骤；两步各自独立命名，避免恢复时走错后续步骤。
func continue_settlement(context: Dictionary) -> bool:
	# 延迟种类；未识别时交回控制器。
	var kind: String = str(context.get(CHOICE_KIND_KEY, ""))
	if kind == DEFER_BEGIN_FIRST_PICK:
		_begin_first_pick()
		return true
	if kind == DEFER_BEGIN_SECOND_PICK:
		_begin_second_pick(str(context.get(FIRST_COLOUR_KEY, "")))
		return true
	return false


## 建立第一张牌的请求；候选为持有者手牌与装备区中所有有颜色的牌。
func _begin_first_pick() -> void:
	var candidates: Array[Dictionary] = _collect_discard_candidates("")
	if candidates.is_empty():
		return
	var selected: Array[int] = request_card_selection(SKILL_TITLE, FIRST_PROMPT, candidates, 1, 1, true, {CHOICE_KIND_KEY:CHOICE_KIND_FIRST})
	# 无正式对局 ID 的同步规则测试不会通过 continue_selection 回调，需在此直接应用返回结果。
	if not host.has_pending_card_choice():
		_apply_first_pick(selected)


## 处理第一张牌的选择结果：弃置成功后记录颜色，并在还有另一种颜色可弃时建立第二张请求。
func _apply_first_pick(selected_uids: Array[int]) -> void:
	if selected_uids.size() != 1:
		return
	# 实际弃置的牌的颜色；弃置失败（牌已离开区域）时为空，本次不产生记录。
	var colour: String = _discard_one_card(selected_uids[0])
	if colour.is_empty():
		return
	_active = true
	if not _discarded_colours.has(colour):
		_discarded_colours.append(colour)
	# 弃置可能触发「当你弃置牌时」类技能并创建嵌套选择；此时不能立刻占用统一请求槽。
	if host.has_nested_settlement_barrier():
		defer_settlement({CHOICE_KIND_KEY:DEFER_BEGIN_SECOND_PICK, FIRST_COLOUR_KEY:colour})
		return
	_begin_second_pick(colour)


## 建立第二张牌的请求；候选只保留颜色与第一张不同的牌，使「颜色不同」成为候选集合的构造性质。
func _begin_second_pick(first_colour: String) -> void:
	if _discarded_colours.size() >= MAX_DISTINCT_COLOURS:
		return
	var candidates: Array[Dictionary] = _collect_discard_candidates(first_colour)
	if candidates.is_empty():
		return
	var selected: Array[int] = request_card_selection(SKILL_TITLE, SECOND_PROMPT, candidates, 1, 1, true, {CHOICE_KIND_KEY:CHOICE_KIND_SECOND, FIRST_COLOUR_KEY:first_colour})
	# 同步规则测试路径：没有待处理请求说明结果已经同步返回。
	if not host.has_pending_card_choice():
		_apply_second_pick(selected)


## 处理第二张牌的选择结果；取消或不合法时保留「只弃置了一张」的记录。
func _apply_second_pick(selected_uids: Array[int]) -> void:
	if selected_uids.size() != 1:
		return
	# 实际弃置的牌的颜色；空值表示牌已离开区域。
	var colour: String = _discard_one_card(selected_uids[0])
	if colour.is_empty():
		return
	if not _discarded_colours.has(colour):
		_discarded_colours.append(colour)


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


## 收集可以作为费用的候选；excluded_colour 非空时排除该颜色的牌，用于构造「颜色不同」的第二张候选。
func _collect_discard_candidates(excluded_colour: String) -> Array[Dictionary]:
	# 最终候选；顺序沿用核心的手牌区、装备区顺序。
	var result: Array[Dictionary] = []
	if host == null:
		return result
	# 持有者自己的手牌与装备区；本技能只弃置自己的牌，因此查看者与目标都是持有者。
	var raw_candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	for candidate: Dictionary in raw_candidates:
		# 当前候选的颜色；无色牌不能参与「颜色不同」的构造，因此直接跳过。
		var colour: String = _candidate_colour(candidate)
		if colour.is_empty() or colour == COLORLESS:
			continue
		if not excluded_colour.is_empty() and colour == excluded_colour:
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
	# 请求种类；只有本技能的两个步骤参与评分，其他请求交回通用评分。
	var kind: String = str((choice_request.get("context", {}) as Dictionary).get(CHOICE_KIND_KEY, ""))
	if kind != CHOICE_KIND_FIRST and kind != CHOICE_KIND_SECOND:
		return 0.0
	# 动作载荷；取消是合法选择，按0分交回通用比较。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 本次选中的牌；数量恒为1，空数组表示协议异常，按不发动处理。
	var selected_uids: Array = payload.get("selected_card_uids", []) as Array
	if selected_uids.is_empty():
		return 0.0
	# 本步弃置的牌对持有者的保留价值总和。
	var cost_value: float = 0.0
	for uid_variant: Variant in selected_uids:
		cost_value += float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(uid_variant), owner_player_id))
	# 本步的建色价值；第二张牌补齐两种颜色后，摸到的任意一张牌都必然与其中一种重合，因此价值更高。
	var setup_value: float = AI_DISCARD_SETUP_VALUE if kind == CHOICE_KIND_FIRST else AI_DISCARD_SETUP_VALUE * AI_SECOND_COLOUR_BONUS
	# 净收益；为负说明这张牌比本次建色价值更贵，应当取消。
	var net_value: float = setup_value - cost_value * AI_COST_WEIGHT
	if net_value <= 0.0:
		return -AI_DECLINE_PENALTY
	return AI_STEP_COMMIT_REWARD + net_value


## 计算基础 AI 对一次结算的价值；本技能是被动触发，没有主动入口，因此主动动作恒为0分。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0
