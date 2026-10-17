extends SkillDefinition

## 【天坠】技能源码。出牌阶段可弃置一张锦囊牌，或在自身横置时重置自身，然后造成1点火属性伤害。

## 【天坠】对目标的身份观察牌效；负1表示成功发动是一次明确伤害行为，不改变实际伤害数值。
const IDENTITY_TARGET_RESULT: float = -1.0

## 【天坠】成功结算时造成的火属性伤害值；默认1点，修改后必须同步技能描述与玩法数值文档。
const DAMAGE_AMOUNT: int = 1

## 请求上下文声明键；声明后本次选择确认的收益已由 score_ai_choice 完整表达，
## 通用层不得再按“自己选中的牌即为自己支付的费用”重复扣一次牌值。
const AI_CHOICE_SKILL_SCORED_KEY: String = "ai_choice_skill_scored"

## 自身横置时的费用替代收益；用“竖置自身”代替弃牌，因此免除材料成本并获得状态恢复收益。
const AI_SELF_RESET_VALUE: float = 0.8

## 零张牌费用（竖置自身）在选择步骤的收益；必须严格大于动作层的 AI_SELF_RESET_VALUE，
## 使“动作层愿意发动”必然对应“选择层愿意确认”。
const AI_ZERO_COST_RESET_VALUE: float = 4.0

## 未横置时零张牌费用的惩罚分；该组合此时不成立，必须让确认动作远低于取消动作的0分。
const AI_ZERO_COST_INVALID_PENALTY: float = -20.0

## 选择动作缺少唯一目标时的评分；必须远低于取消动作的0分。
const AI_INVALID_CHOICE_SCORE: float = -10.0

## 未横置且没有任何锦囊牌时的评分；此时本技能不可能发动，动作层必须给严格负分而不是0费用。
const AI_UNPAYABLE_ACTION_SCORE: float = -100.0

## 当前出牌阶段是否已经发动；每次 phaseUseBegin 重置，费用完整支付后设为 true。
var _used_this_play_phase: bool = false


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "tianzhui",
		"name": "天坠",
		"trigger": "active",
		"enable": "phaseUse",
		"ui_enabled": true,
		"description": "出牌阶段限一次，你可以弃置一张锦囊牌或将自身横置的武将牌竖置，然后对一名横置的角色造成1点火属性伤害。",
	})


## 订阅每个自身出牌阶段的开始时机，用于重置独立的阶段次数。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 仅在自己的出牌阶段、尚未发动且同时存在费用与横置目标时允许点击技能按钮。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者状态；自身横置时可不选择锦囊牌，否则必须有普通手牌区中的锦囊牌。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or _used_this_play_phase or host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	return not _get_linked_target_ids().is_empty() and (owner.chained or not _get_trick_hand_candidates().is_empty())


## 创建可选锦囊牌与必选横置目标的组合请求；自身横置时允许零张牌，否则恢复时拒绝零材料提交。
func activate(_context: Dictionary = {}) -> String:
	# 可弃置锦囊牌候选；只包含普通手牌，不允许用装备区、判定区或木牛“粮”支付。
	var candidates: Array[Dictionary] = _get_trick_hand_candidates()
	# 横置目标 ID；包括技能持有者自己，只要该角色当前处于连环状态。
	var target_ids: Array[int] = _get_linked_target_ids()
	request_card_target_selection("天坠", "请选择一张锦囊牌和一名横置角色；自身横置时可不选牌", candidates, target_ids, 0, 1, 1, 1, true, {"kind":"tianzhui_cost_target", AI_CHOICE_SKILL_SCORED_KEY:true})
	return ""


## 恢复组合选择并重新校验费用与目标；成功后先支付费用，再造成固定1点火属性伤害。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "tianzhui_cost_target" or response == null:
		return false
	if not response.confirmed or response.target_ids.size() != 1 or response.card_ids.size() > 1:
		return true
	# 当前目标；等待期间已经解除横置或死亡时不消耗费用与次数。
	var target: PlayerState = host.state.get_player(response.target_ids[0]) as PlayerState
	if target == null or not target.alive or not target.chained:
		return true
	if response.card_ids.size() == 1:
		# 选中的手牌；必须仍是普通手牌区中的锦囊牌。
		var owner: PlayerState = get_owner_skill_player().get_state()
		var cost_card: CardInstance = owner.find_hand_card(response.card_ids[0]) if owner != null else null
		if cost_card == null or str(GameDatabase.get_card(cost_card.definition_id).get("type", "")) != "trick":
			return true
		if not bool(host.call("discard_card_from_hand", owner_player_id, cost_card.uid)):
			return true
	else:
		# 零牌费用仅在自身仍横置时成立；重置失败时不发动技能。
		var owner_state: PlayerState = get_owner_skill_player().get_state()
		if owner_state == null or not owner_state.chained or not bool(host.call("set_player_linked", owner_player_id, false, owner_player_id, get_id())):
			return true
	_used_this_play_phase = true
	announce_activation({"target_id":target.player_id})
	observe_identity_behavior([target.player_id], {"target_result":IDENTITY_TARGET_RESULT})
	get_owner_skill_player().damage(DAMAGE_AMOUNT, get_skill_player(target.player_id), "fire")
	return true


## 向 AI 合法动作列表追加标准技能动作；实际牌与目标由技能选择请求统一决定。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if can_activate():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[], "payload":{"skill_id":get_id()}})


## 每个新的自身出牌阶段恢复一次发动额度，包括【再现】等效果产生的额外出牌阶段。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 返回普通手牌区中的全部锦囊牌候选；候选快照供统一选择面板与网络协议使用。
func _get_trick_hand_candidates() -> Array[Dictionary]:
	# 全部普通手牌候选；先由控制器生成标准可见快照，再按卡牌类型过滤。
	var hand_candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 锦囊牌候选结果；保持原手牌顺序，方便玩家与 AI 获得一致选项。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in hand_candidates:
		# 候选牌面位于 card_data 子字典；本人手牌为可见候选，definition_id 可安全用于规则过滤。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(GameDatabase.get_card(str(card_data.get("definition_id", ""))).get("type", "")) == "trick":
			result.append(candidate)
	return result


## 返回当前全部横置存活角色 ID；“一名横置的角色”不排除技能持有者本人。
func _get_linked_target_ids() -> Array[int]:
	# 横置目标结果；沿用座次数组顺序，保证选择面板、AI和回放顺序稳定。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and player.chained:
			result.append(player.player_id)
	return result


## 评估主动发动价值；存在敌方横置目标时优先发动，自身横置可免除弃牌费用并获得额外收益。
## 本函数在AI评估期间不持有host，因此只读取权威快照与估值接口。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	# 技能持有者状态；静态 AI 实例只能从快照读取连环与手牌信息。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return 0.0
	# 最佳横置目标毛收益；负值同样保留，避免把“只能打自己或队友”误判成中性局面。
	var best_target_score: float = _get_best_target_gross_value(authoritative_snapshot, evaluator)
	# 自身横置时通过竖置自身支付费用：不消耗手牌并获得 AI_SELF_RESET_VALUE 的状态恢复收益。
	if bool(owner.get("chained", false)):
		return best_target_score + AI_SELF_RESET_VALUE
	# 未横置时必须弃置一张锦囊牌；动作层先扣掉最便宜锦囊牌的保留价值，
	# 与选择层的真实扣费共用同一估值入口，保证“动作层可接受”时“选牌步骤必然也能接受”。
	var cheapest_trick_value: float = _get_cheapest_trick_value(authoritative_snapshot, owner, evaluator)
	if is_inf(cheapest_trick_value):
		# 没有任何锦囊牌：本技能不可能发动，动作层必须给严格负分，而不是按0费用给出可接受动作。
		return AI_UNPAYABLE_ACTION_SCORE
	return best_target_score - cheapest_trick_value


## 返回【天坠】对指定目标的毛收益；不含费用，供主动动作评分与费用目标选择评分共用。
##
## 该函数是“动作层认为值得发动”与“选择层愿意确认”保持同一口径的唯一来源：
## 两处都用本值减去同一份费用，因此不会出现“提议发动却立刻取消”的自相矛盾，
## 也就不会让AI在同一出牌阶段反复进入本技能再取消，从而避免回合推进停滞。
func _get_target_gross_value(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, -DAMAGE_AMOUNT)


## 返回当前全部横置存活角色中的最高毛收益；没有任何横置角色时返回0.0。
## 这里不得把负收益截断为0.0：动作层若把“只能打自己或队友”当成中性，选择层仍会按真实负值取消，
## 两处口径不一致正是“发动→取消”死循环的成因。
func _get_best_target_gross_value(authoritative_snapshot: Dictionary, evaluator: Object) -> float:
	# 当前最高毛收益；初始为负无穷，使首个横置目标直接成为比较基准。
	var best_score: float = -INF
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前目标快照；仅横置存活角色可成为【天坠】目标。
		var target: Dictionary = player_variant as Dictionary
		if not bool(target.get("alive", false)) or not bool(target.get("chained", false)):
			continue
		best_score = maxf(best_score, _get_target_gross_value(authoritative_snapshot, int(target.get("player_id", -1)), evaluator))
	return 0.0 if is_inf(best_score) else best_score


## 返回持有者手牌中锦囊牌的最低保留价值；没有任何锦囊牌时返回正无穷 INF。
## 该值与选择步骤的 get_choice_card_value 使用同一牌值入口，因此动作层的费用扣减与选择层的真实扣费一致。
func _get_cheapest_trick_value(authoritative_snapshot: Dictionary, owner: Dictionary, evaluator: Object) -> float:
	# 当前最低费用牌价值；初始为正无穷，使首张锦囊牌直接成为比较基准。
	var cheapest_value: float = INF
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌快照；只有普通手牌区中的锦囊牌可作为【天坠】费用。
		var card: Dictionary = card_variant as Dictionary
		# 当前牌定义 ID；类型判定与牌值估值共用同一静态数据来源。
		var definition_id: String = str(card.get("definition_id", ""))
		if str(GameDatabase.get_card(definition_id).get("type", "")) != "trick":
			continue
		cheapest_value = minf(cheapest_value, evaluator.get_card_value_by_id(definition_id, authoritative_snapshot, owner_player_id))
	return cheapest_value


## 评估【天坠】费用与目标组合；优先免牌费用、最低价值锦囊和敌方横置目标。
## 请求已声明 AI_CHOICE_SKILL_SCORED_KEY，因此本函数返回值就是该确认动作的总分，
## 且与 score_ai_action 共用 _get_target_gross_value 与同一份费用口径。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理天坠的牌目标组合步骤。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "tianzhui_cost_target":
		return 0.0
	# 标准动作负载；必须包含一名目标，牌费用可为0或1张。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 取消动作由通用层按0分基准处理，本函数只负责确认动作的完整收益。
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；无目标动作不构成有效发动。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() != 1:
		return AI_INVALID_CHOICE_SCORE
	# 目标毛收益；与动作层共用 _get_target_gross_value，两处口径完全一致。
	var score: float = _get_target_gross_value(authoritative_snapshot, int(selected_targets[0]), evaluator)
	# 已选费用牌；选择最低价值锦囊，零牌费用用竖置自身支付。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.is_empty():
		# 零张牌只在自身仍横置时成立；成立时按竖置自身计入收益，否则给严格负分。
		var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
		if bool(owner.get("chained", false)):
			return score + AI_ZERO_COST_RESET_VALUE
		return score + AI_ZERO_COST_INVALID_PENALTY
	return score - evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
