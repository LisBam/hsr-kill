extends SkillDefinition

## 【濯世】技能源码。出牌阶段限一次，持有者按三段流程弃置基本牌，依次换取拆牌与雷电伤害。
##
## 三段结构严格对应原文的三句：
## ①「你可以弃置一张基本牌并选择一名其他角色，你弃置其一张手牌」——必付1张基本牌，效果恒定发生；
## ②「然后你可再次弃置一张基本牌并弃置其一张牌」——可选整段，费用与效果成对结算；
## ③「最后你可再次弃置一张基本牌并对其造成1点雷电伤害」——可选整段，费用与效果成对结算。
## 只有第①段的弃置真实完成后才消费「出牌阶段限一次」额度；中途取消不留任何痕迹。

## 「出牌阶段限一次」的阶段额度上限；固定1，与技能原文一致。
const PLAY_PHASE_LIMIT: int = 1

## 第一段需要弃置的基本牌数量；固定1张。
const COST_CARD_COUNT: int = 1

## 第二段第一步需要弃置的基本牌数量；固定1张。
const SECOND_COST_CARD_COUNT: int = 1

## 第三段需要弃置的基本牌数量；固定1张。
const THIRD_COST_CARD_COUNT: int = 1

## 第二段第二步的效果弃置数量；固定1张牌。
const EFFECT_DISCARD_COUNT: int = 1

## 基本牌的卡牌类型字面量；与卡牌静态元数据 type 字段的取值域一致。
const CARD_TYPE_BASIC: String = "basic"

## 第三段造成的雷电伤害点数；固定1点。
const THUNDER_DAMAGE: int = 1

## 雷电属性字面量；与核心伤害端口 nature 参数的取值域一致。
const NATURE_THUNDER: String = "thunder"

## 可支付费用的候选区域限制；只接受普通手牌。
## 这是必须的限制而不是偏好：本技能的费用统一经 discard_selected_hand_cards 支付，该端口只从
## PlayerState.hand 取牌，而木牛「粮」存放在 wooden_ox_storage、装备牌存放在 equipment，
## 底层 _find_player_zone_card 也不覆盖木牛附属区。若把「粮」列进候选，就会出现
## 「界面可选但提交被拒」的假候选，因此费用口径固定为普通手牌。
const COST_ZONE_HAND: String = "hand"

## 第一段「弃一张基本牌并选一名其他角色」的选择种类。
const CHOICE_COST_AND_TARGET: String = "zhuoshi_cost_and_target"

## 第二段第一步「弃置其一张手牌」的选择种类；该步骤必选，不允许取消。
const CHOICE_DISCARD_TARGET_HAND: String = "zhuoshi_discard_target_hand"

## 第二段第二步「弃置其一张牌」的选择种类；该步骤在费用已支付后必选，不允许取消。
const CHOICE_DISCARD_TARGET_ANY: String = "zhuoshi_discard_target_any"

## 第二段费用「再次弃置一张基本牌」的选择种类；取消表示放弃整段第二段。
const CHOICE_SECOND_COST: String = "zhuoshi_second_cost"

## 第三段费用「再次弃置一张基本牌」的选择种类；取消表示放弃整段第三段。
const CHOICE_THIRD_COST: String = "zhuoshi_third_cost"

## 第一段费用弃置完成后的延迟结算种类；弃置自己费用牌可能触发「当你弃置牌时」类嵌套技能。
const DEFER_AFTER_FIRST_COST: String = "zhuoshi_defer_after_first_cost"

## 第二段第一步效果弃置完成后的延迟结算种类。
const DEFER_AFTER_TARGET_HAND_DISCARD: String = "zhuoshi_defer_after_target_hand_discard"

## 第二段费用弃置完成后的延迟结算种类；与上一步骤必须区分，否则恢复时会走错后续步骤。
const DEFER_AFTER_SECOND_COST: String = "zhuoshi_defer_after_second_cost"

## 第二段第二步效果弃置完成后的延迟结算种类。
const DEFER_AFTER_TARGET_ANY_DISCARD: String = "zhuoshi_defer_after_target_any_discard"

## 第三段费用弃置完成后的延迟结算种类。
const DEFER_AFTER_THIRD_COST: String = "zhuoshi_defer_after_third_cost"

## 多步交互中「确认」动作的保底分；远高于任何单张牌面收益，
## 使「是否继续」只由真实收益的小数部分决定，不被通用手牌费用评分翻转。
const AI_STEP_COMMIT_REWARD: float = 100.0

## 发动入口的基础期望分；只有目标侧净收益为正时才会叠加，避免AI对纯友方目标空放。
const AI_ACTIVATION_BASE: float = 2.0

## 目标侧收益在两段效果上的叠加权重；保持为1使其与统一资源口径的数值同量纲。
const AI_TARGET_VALUE_WEIGHT: float = 1.0

## 费用牌自身保留价值的扣减权重；与【追歼】等同类费用技能保持一致的0.35量级，
## 避免为了小额收益弃置关键的【桃】或【闪】。
const AI_COST_WEIGHT: float = 0.35

## 一套完整流程预期支付的基本牌张数；第一段必付1张，第二、三段各1张，取2作为期望费用。
const AI_ESTIMATED_COST_CARDS: int = 2

## 「应当放弃该步骤」时的负分；通用评分给「确认」的兜底分是正数、给「取消」是0.0，
## 因此必须给出严格负分，取消才会成为真正的最优解。
const AI_DECLINE_PENALTY: float = 5.0

## 当前出牌阶段已发动次数；进入每个出牌阶段复原，实现原文“出牌阶段限一次”。
var _used_this_play_phase: int = 0


## 写入主动技静态信息；技能正文逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"zhuoshi",
		"name":"濯世",
		"trigger":"active/phaseUse",
		"enable":"phaseUse",
		"ui_enabled":true,
		"description":"出牌阶段限一次，你可以弃置一张基本牌并选择一名其他角色，你弃置其一张手牌，然后你可再次弃置一张基本牌并弃置其一张牌，最后你可再次弃置一张基本牌并对其造成1点雷电伤害。",
	})


## 订阅出牌阶段开始以复原阶段额度；普通与额外出牌阶段一视同仁。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 每个出牌阶段复原“限一次”额度。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = 0


## 检查出牌阶段归属、阶段额度、可支付的基本牌与可选的合法目标。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；阵亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	if _used_this_play_phase >= PLAY_PHASE_LIMIT:
		return false
	# 已存在待处理选择时不再开放入口；控制器会拒绝第二个请求，提前拦下可避免按钮空点。
	# 该检查同时保证“选择过程中取消”之后按钮立即恢复可用。
	if host.has_pending_card_choice():
		return false
	# 费用与目标任一维度为空都不开放入口，避免发出必然无法完成的询问。
	if _get_basic_cost_candidates().is_empty():
		return false
	return not _get_cost_target_ids().is_empty()


## 询问第一段的费用基本牌与目标角色；后续两段在恢复回调中逐个推进。
func activate(_context: Dictionary = {}) -> String:
	if not can_activate():
		return "【濯世】当前不满足发动条件。"
	request_card_target_selection("濯世", "请弃置一张基本牌并选择一名其他角色", _get_basic_cost_candidates(), _get_cost_target_ids(), COST_CARD_COUNT, COST_CARD_COUNT, 1, 1, true, {"kind":CHOICE_COST_AND_TARGET})
	return ""


## 分步恢复【濯世】的全部选择步骤。
## 每一段都重新复核持有者、目标与候选：异步等待期间任何一步前提失效都立即终止整条流程，
## 不再创建后续请求，也不追回已经支付并生效的费用。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	var context_kind: String = str(context.get("kind", ""))
	# 技能持有者；权威状态在异步选择期间可能变化。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return true
	if context_kind == CHOICE_COST_AND_TARGET:
		# 第一段取消：整次发动放弃，不消费阶段额度、不产生任何效果。
		if not response.confirmed or response.card_ids.size() != COST_CARD_COUNT or response.target_ids.size() != 1:
			return true
		# 最终目标；等待期间死亡、离场或变为持有者自己时本次发动失效。
		var target_id: int = int(response.target_ids[0])
		if not _is_valid_target(target_id):
			return true
		# 第一段费用；权威端口只接受仍在持有者手牌区中的所选实体。
		var cost_uids: Array[int] = [int(response.card_ids[0])]
		if int(host.call("discard_selected_hand_cards", owner_player_id, cost_uids)) != COST_CARD_COUNT:
			return true
		# 阶段额度只在第一段费用真实进入弃牌堆后才消费；此前的任何取消都不占额度。
		_used_this_play_phase += 1
		announce_activation({"target_id":target_id, "card_uid":int(response.card_ids[0])})
		# 雷电属性时机的身份行为上报口径与【追歼】一致：本技能确实造成了属性伤害。
		observe_identity_behavior([target_id], {"target_result":-1.0, "damage":true, "nature_damage":true})
		_continue_after_first_cost(target_id)
		return true
	if context_kind == CHOICE_DISCARD_TARGET_HAND:
		# 该步骤创建时 min_select 为1且候选非空，正常路径不会取消；异常响应按“未完成该步骤”终止流程。
		if not response.confirmed or response.card_ids.size() != EFFECT_DISCARD_COUNT:
			return true
		var hand_target_id: int = int(context.get("target_id", -1))
		if not _is_valid_target(hand_target_id):
			return true
		var hand_uids: Array[int] = [int(response.card_ids[0])]
		host.call("discard_selected_player_cards", hand_target_id, hand_uids, owner_player_id)
		_continue_after_target_discard(DEFER_AFTER_TARGET_HAND_DISCARD, hand_target_id)
		return true
	if context_kind == CHOICE_SECOND_COST:
		# 第二段费用取消：放弃整段第二段，直接进入第三段。
		if not response.confirmed or response.card_ids.size() != SECOND_COST_CARD_COUNT:
			_begin_third_cost(int(context.get("target_id", -1)))
			return true
		var second_target_id: int = int(context.get("target_id", -1))
		if not _is_valid_target(second_target_id):
			return true
		var second_cost_uids: Array[int] = [int(response.card_ids[0])]
		if int(host.call("discard_selected_hand_cards", owner_player_id, second_cost_uids)) != SECOND_COST_CARD_COUNT:
			_begin_third_cost(second_target_id)
			return true
		_continue_after_second_cost(second_target_id)
		return true
	if context_kind == CHOICE_DISCARD_TARGET_ANY:
		# 费用已经支付，该步骤按必选处理；异常响应同样终止流程，不回退已弃置的费用。
		if not response.confirmed or response.card_ids.size() != EFFECT_DISCARD_COUNT:
			return true
		var any_target_id: int = int(context.get("target_id", -1))
		if not _is_valid_target(any_target_id):
			return true
		var any_uids: Array[int] = [int(response.card_ids[0])]
		host.call("discard_selected_player_cards", any_target_id, any_uids, owner_player_id)
		_continue_after_target_discard(DEFER_AFTER_TARGET_ANY_DISCARD, any_target_id)
		return true
	if context_kind == CHOICE_THIRD_COST:
		# 第三段费用取消：只有第三段不发生，前面的拆牌效果全部保留。
		if not response.confirmed or response.card_ids.size() != THIRD_COST_CARD_COUNT:
			return true
		var third_target_id: int = int(context.get("target_id", -1))
		if not _is_valid_target(third_target_id):
			return true
		var third_cost_uids: Array[int] = [int(response.card_ids[0])]
		if int(host.call("discard_selected_hand_cards", owner_player_id, third_cost_uids)) != THIRD_COST_CARD_COUNT:
			return true
		_continue_after_third_cost(third_target_id)
		return true
	return false


## 恢复延迟结算步骤；弃置与伤害都可能触发嵌套技能，必须等嵌套结算全部收尾后再创建下一个请求。
func continue_settlement(context: Dictionary) -> bool:
	var context_kind: String = str(context.get("kind", ""))
	if context_kind == DEFER_AFTER_FIRST_COST:
		_begin_target_hand_discard(int(context.get("target_id", -1)))
		return true
	if context_kind == DEFER_AFTER_TARGET_HAND_DISCARD:
		_begin_second_cost(int(context.get("target_id", -1)))
		return true
	if context_kind == DEFER_AFTER_SECOND_COST:
		_begin_second_cost_effect(int(context.get("target_id", -1)))
		return true
	if context_kind == DEFER_AFTER_TARGET_ANY_DISCARD:
		_begin_third_cost(int(context.get("target_id", -1)))
		return true
	if context_kind == DEFER_AFTER_THIRD_COST:
		_resolve_thunder_damage(int(context.get("target_id", -1)))
		return true
	return false


## 第一段费用弃置完成后推进到“弃置其一张手牌”。
## 弃置自己费用牌后可能触发嵌套技能结算（例如【泛音】等“当你弃置牌时”类效果）。
## 统一请求槽被嵌套选择占用时立刻创建下一个请求会被控制器拒绝并静默中断整条流程，
## 因此必须先登记延迟步骤，等嵌套结算全部收尾后再继续。
func _continue_after_first_cost(target_id: int) -> void:
	if _defer_if_barrier(DEFER_AFTER_FIRST_COST, target_id):
		return
	_begin_target_hand_discard(target_id)


## 第二段费用弃置完成后推进到“弃置其一张牌”。
func _continue_after_second_cost(target_id: int) -> void:
	if _defer_if_barrier(DEFER_AFTER_SECOND_COST, target_id):
		return
	_begin_second_cost_effect(target_id)


## 效果弃置完成后按传入的延迟种类决定后续步骤；两个效果弃置共用同一套屏障判断。
func _continue_after_target_discard(defer_kind: String, target_id: int) -> void:
	if _defer_if_barrier(defer_kind, target_id):
		return
	if defer_kind == DEFER_AFTER_TARGET_HAND_DISCARD:
		_begin_second_cost(target_id)
		return
	_begin_third_cost(target_id)


## 第三段费用弃置完成后结算雷电伤害。
func _continue_after_third_cost(target_id: int) -> void:
	if _defer_if_barrier(DEFER_AFTER_THIRD_COST, target_id):
		return
	_resolve_thunder_damage(target_id)


## 存在嵌套结算屏障时登记延迟步骤并返回真；调用方据此提前返回，避免与嵌套选择争抢统一请求槽。
func _defer_if_barrier(defer_kind: String, target_id: int) -> bool:
	if not bool(host.call("has_nested_settlement_barrier")):
		return false
	defer_settlement({"kind":defer_kind, "target_id":target_id})
	return true


## 建立“弃置其一张手牌”请求；候选为空时跳过该步骤继续推进，绝不创建没有候选的必选请求。
func _begin_target_hand_discard(target_id: int) -> void:
	if not _is_valid_target(target_id):
		return
	# 目标手牌候选；隐藏手牌按牌背呈现，选择结果仍由权威端口复核。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
	# 「你弃置其一张手牌」在原文里没有“没有手牌就不结算”的写法，因此候选为空时跳过本步骤
	# 而不是结束整条流程：第一段已经生效，后续可选的第二、三段仍应正常开放。
	if candidates.is_empty():
		_begin_second_cost(target_id)
		return
	request_card_selection("濯世", "请弃置该角色的一张手牌", candidates, EFFECT_DISCARD_COUNT, EFFECT_DISCARD_COUNT, false, {"kind":CHOICE_DISCARD_TARGET_HAND, "target_id":target_id})


## 建立第二段费用请求；费用与目标侧候选任一不可用都跳过整段第二段。
func _begin_second_cost(target_id: int) -> void:
	if not _is_valid_target(target_id):
		return
	# 第二段的费用牌；没有可支付的基本牌时整段不成立。
	var candidates: Array[Dictionary] = _get_basic_cost_candidates()
	if candidates.is_empty():
		_begin_third_cost(target_id)
		return
	# 第二段的效果目标侧候选；目标已无牌可弃时整段不成立，避免白付一张基本牌。
	if (host.call("get_hand_equipment_candidates", owner_player_id, target_id) as Array[Dictionary]).is_empty():
		_begin_third_cost(target_id)
		return
	request_card_selection("濯世", "是否再次弃置一张基本牌并弃置其一张牌？", candidates, SECOND_COST_CARD_COUNT, SECOND_COST_CARD_COUNT, true, {"kind":CHOICE_SECOND_COST, "target_id":target_id})


## 建立“弃置其一张牌”请求；“一张牌”的口径固定为手牌区与装备区，不含判定区。
func _begin_second_cost_effect(target_id: int) -> void:
	if not _is_valid_target(target_id):
		return
	# 效果候选；第二段费用已经支付，这里只复核目标侧是否仍有可选实体。
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, target_id) as Array[Dictionary]
	# 费用已付但等待期间目标已无牌可弃：规则结果就是本次第二段只支付了费用，直接进入第三段。
	if candidates.is_empty():
		_begin_third_cost(target_id)
		return
	request_card_selection("濯世", "请弃置该角色的一张牌", candidates, EFFECT_DISCARD_COUNT, EFFECT_DISCARD_COUNT, false, {"kind":CHOICE_DISCARD_TARGET_ANY, "target_id":target_id})


## 建立第三段费用请求；没有可支付的基本牌时整段不成立。
func _begin_third_cost(target_id: int) -> void:
	if not _is_valid_target(target_id):
		return
	# 第三段的费用牌；没有可支付的基本牌时整段不成立。
	var candidates: Array[Dictionary] = _get_basic_cost_candidates()
	if candidates.is_empty():
		return
	request_card_selection("濯世", "是否再次弃置一张基本牌并对其造成1点雷电伤害？", candidates, THIRD_COST_CARD_COUNT, THIRD_COST_CARD_COUNT, true, {"kind":CHOICE_THIRD_COST, "target_id":target_id})


## 结算第三段的1点雷电伤害；目标在每个步骤都已复核，这里做最后一次复核后调用权威伤害端口。
func _resolve_thunder_damage(target_id: int) -> void:
	if not _is_valid_target(target_id):
		return
	host.call("damage", owner_player_id, target_id, THUNDER_DAMAGE, NATURE_THUNDER, "", false, false, {"source_skill_id":get_id()})


## 返回持有者可作为本技能费用的基本牌候选；只包含普通手牌，木牛「粮」与装备区不参与。
func _get_basic_cost_candidates() -> Array[Dictionary]:
	# 费用候选结果；保持权威材料端口的稳定顺序，界面、AI与回放据此枚举一致。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_skill_material_candidates", owner_player_id) as Array[Dictionary]:
		# 候选所在区域；木牛「粮」无法经手牌弃置端口支付，必须排除。
		if str(candidate.get("zone", "")) != COST_ZONE_HAND:
			continue
		# 候选牌面数据；隐藏候选没有定义ID，无法判断牌型，直接跳过。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(card_data.get("definition_id", "")).is_empty():
			continue
		# 候选卡牌定义；只有基本牌可以作为本技能费用。
		var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
		if str(definition.get("type", "")) != CARD_TYPE_BASIC:
			continue
		result.append(candidate)
	return result


## 返回第一段的合法目标候选；必须是其他存活在场且至少有一张手牌的角色。
func _get_cost_target_ids() -> Array[int]:
	# 目标结果；沿用权威座次顺序，保证界面、AI与回放得到相同候选排列。
	var result: Array[int] = []
	for target_id: int in host.call("get_other_alive_player_ids", owner_player_id) as Array[int]:
		# 第一段的效果是「你弃置其一张手牌」，因此没有手牌的角色不构成合法目标。
		if (host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]).is_empty():
			continue
		result.append(target_id)
	return result


## 复核目标在异步等待期间是否仍是其他存活在场角色。
func _is_valid_target(target_id: int) -> bool:
	# 目标状态；不存在、阵亡、离场或等于持有者自己时整条流程终止。
	var target: PlayerState = host.state.get_player(target_id) if host != null and host.state != null else null
	if target == null or not target.alive or target.out_of_game or target_id == owner_player_id:
		return false
	return true


## 为AI枚举候选动作；本技能只提交一个空负载动作，具体选择交给后续选牌/选目标请求。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 评估【濯世】的发动价值：以“拆其一张牌 + 造成1点雷电伤害”的目标侧收益为准，再扣减预期费用。
## 候选目标全部为友方时净收益为负，直接返回0让AI不开入口，避免把阶段额度浪费在自己人身上。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	# 最优目标侧净收益；只统计能真正吃到第二、三段效果的其他角色。
	var best_value: float = 0.0
	# 是否存在任何合法目标；没有合法目标时AI不应发动。
	var has_target: bool = false
	for target_id: int in _get_cost_target_ids():
		if target_id == owner_player_id:
			continue
		has_target = true
		best_value = maxf(best_value, _score_target_value_for_ai(authoritative_snapshot, target_id, evaluator))
	if not has_target or best_value <= 0.0:
		return 0.0
	# 预期费用；持有者自己会失去若干张基本牌，按自身态度折算为负值。
	var expected_cost: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, -AI_ESTIMATED_COST_CARDS, 0)
	return AI_ACTIVATION_BASE + best_value + expected_cost


## 评估【濯世】各步选择的收益；每一步的「确认」都给出保底正分以防通用费用评分把流程掰回取消，
## 需要放弃的步骤则给出严格负分，让通用策略的「取消」成为更优解。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var context_kind: String = str(context.get("kind", ""))
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	var confirmed: bool = bool(payload.get("confirmed", false))
	if context_kind == CHOICE_COST_AND_TARGET:
		# 取消不加成；确认时必须同时提供1张费用牌与1名目标。
		if not confirmed or selected_cards.size() != COST_CARD_COUNT or selected_targets.size() != 1:
			return 0.0
		var first_target_id: int = int(selected_targets[0])
		# 目标侧收益；敌方正收益、友方负收益。
		var target_value: float = _score_target_value_for_ai(authoritative_snapshot, first_target_id, evaluator)
		# 费用牌自身保留价值；优先弃置低保留价值实体，避免用救命牌换取不确定收益。
		var cost_value: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
		# 净收益不为正时给出负分，让通用策略取消本次发动，而不是强行对友方开火。
		if target_value - cost_value * AI_COST_WEIGHT <= 0.0:
			return -AI_DECLINE_PENALTY
		return AI_STEP_COMMIT_REWARD + target_value - cost_value * AI_COST_WEIGHT
	if context_kind == CHOICE_DISCARD_TARGET_HAND:
		# 必选步骤：确认即拆掉目标一张手牌，是纯正收益；不确认不会发生，按0分处理。
		if not confirmed:
			return 0.0
		return AI_STEP_COMMIT_REWARD + _score_effect_discard_for_ai(authoritative_snapshot, int(context.get("target_id", -1)), evaluator)
	if context_kind == CHOICE_SECOND_COST:
		# 可选整段：确认表示“支付一张基本牌并弃置其一张牌”，取消表示跳过整段。
		# 只有净收益为正才确认；否则给出负分让通用策略取消，避免白付一张基本牌。
		if not confirmed or selected_cards.size() != SECOND_COST_CARD_COUNT:
			return 0.0
		var second_value: float = _score_effect_discard_for_ai(authoritative_snapshot, int(context.get("target_id", -1)), evaluator)
		var second_cost: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
		var second_net: float = second_value - second_cost * AI_COST_WEIGHT
		if second_net <= 0.0:
			return -AI_DECLINE_PENALTY
		return AI_STEP_COMMIT_REWARD + second_net
	if context_kind == CHOICE_DISCARD_TARGET_ANY:
		# 必选步骤：费用已经支付，确认拆掉目标一张牌优于空过。
		if not confirmed:
			return 0.0
		return AI_STEP_COMMIT_REWARD + _score_effect_discard_for_ai(authoritative_snapshot, int(context.get("target_id", -1)), evaluator)
	if context_kind == CHOICE_THIRD_COST:
		# 可选整段：确认表示“支付一张基本牌并造成1点雷电伤害”，取消表示放弃第三段。
		# 伤害对敌方是净正收益、对友方是净负收益，因此同样只在净收益为正时确认。
		if not confirmed or selected_cards.size() != THIRD_COST_CARD_COUNT:
			return 0.0
		var damage_value: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, int(context.get("target_id", -1)), 0, -THUNDER_DAMAGE)
		var third_cost: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
		var third_net: float = damage_value - third_cost * AI_COST_WEIGHT
		if third_net <= 0.0:
			return -AI_DECLINE_PENALTY
		return AI_STEP_COMMIT_REWARD + third_net
	return 0.0


## 估算对一个目标走完整套流程的目标侧收益；拆其一张牌与造成1点雷电伤害都按统一资源口径折算。
## 这里刻意**不**扣减持有者自己的费用：费用必须在每个真正支付的步骤上单独计入，
## 否则第一步与发动入口会各扣一次预期费用，把本该发动的正收益动作算成负分。
func _score_target_value_for_ai(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	if target_id < 0 or target_id == owner_player_id:
		return 0.0
	# 拆牌收益；目标失去1张牌，敌方为正、友方为负。
	var card_gain: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, -EFFECT_DISCARD_COUNT, 0)
	# 伤害收益；目标失去1点体力，敌方为正、友方为负。
	var damage_gain: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, -THUNDER_DAMAGE)
	return (card_gain + damage_gain) * AI_TARGET_VALUE_WEIGHT


## 估算“弃置目标一张牌”这一步单独的收益；用于第二段的可选整段取舍。
func _score_effect_discard_for_ai(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	if target_id < 0 or target_id == owner_player_id:
		return 0.0
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, -EFFECT_DISCARD_COUNT, 0)
