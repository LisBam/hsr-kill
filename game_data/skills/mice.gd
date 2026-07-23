extends SkillDefinition

## 【秘策】技能源码。回合结束时同时选择一名其他角色与其先执行的阶段，阶段完成后由佩拉执行另一项。

## “额外出牌阶段”文字选项稳定ID；界面标签与规则分支分离，网络只提交该ID。
const PLAY_PHASE_OPTION_ID: String = "play_phase"

## “摸一张牌并执行额外弃牌阶段”文字选项稳定ID；与出牌阶段选项共同组成一步式目标控制请求。
const DISCARD_PHASE_OPTION_ID: String = "discard_phase"

## 弃牌阶段前固定摸牌数；固定1张，与技能原文和玩法数值文档保持一致。
const DRAW_BEFORE_DISCARD_COUNT: int = 1

## AI对额外出牌阶段中每张公开手牌行动空间的基础估值；只影响决策，不修改任何牌效。
const AI_PLAY_HAND_VALUE: float = 0.65

## AI对一张已知可主动使用手牌的额外行动估值；佩拉自身完整手牌可据此提高额外出牌收益。
const AI_KNOWN_PLAYABLE_CARD_VALUE: float = 0.9

## AI对友方低于手牌上限的每点空余容量奖励；空余越多，摸1张且无需弃置的收益越稳定。
const AI_FRIENDLY_HAND_DEFICIT_VALUE: float = 0.15


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"mice",
		"name":"秘策",
		"trigger":"phaseEnd",
		"ui_enabled":false,
		"description":"回合结束时，你可令一名其他角色执行一项：1.获得一个额外的出牌阶段；2.摸一张牌并获得一个额外的弃牌阶段。该阶段结束后，你执行另一项。",
	})


## 订阅持有者自己的回合结束时机；额外阶段完成流程由控制器通过continue_extra_phase交回。
func install() -> void:
	subscribe_timing("phaseEnd", _on_phase_end, "player")


## 回合结束时创建目标与按钮同时确认的选择；没有其他存活角色时直接跳过。
func _on_phase_end(_event: RuleEvent) -> void:
	# 其他存活角色；秘策不能把第一项交给佩拉本人。
	var target_ids: Array[int] = host.call("get_other_alive_player_ids", owner_player_id) as Array[int]
	if target_ids.is_empty():
		return
	# 两项实际按钮；显示文本严格使用主公指定的“出牌阶段”“弃牌阶段”。
	var options: Array[Dictionary] = [
		{"id":PLAY_PHASE_OPTION_ID, "label":"出牌阶段"},
		{"id":DISCARD_PHASE_OPTION_ID, "label":"弃牌阶段"},
	]
	request_target_control_selection("秘策", "请选择一名其他角色并选择其执行的阶段", target_ids, options, true, {"kind":"mice_target_option"})


## 恢复目标与阶段分支；取消不产生任何摸牌、阶段或发动记录。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "mice_target_option" or response == null:
		return false
	if not response.confirmed or response.target_ids.size() != 1 or response.control_id not in [PLAY_PHASE_OPTION_ID, DISCARD_PHASE_OPTION_ID]:
		return true
	# 最终目标ID；等待期间死亡、离场或变为佩拉本人时本次发动失效。
	var target_id: int = response.target_ids[0]
	if not (host.call("get_other_alive_player_ids", owner_player_id) as Array[int]).has(target_id):
		return true
	announce_activation({"target_id":target_id, "first_option":response.control_id})
	if response.control_id == PLAY_PHASE_OPTION_ID:
		observe_identity_behavior([target_id], {"target_result":1.0})
		_request_play_phase(target_id, "mice_target_play_complete", target_id)
		return true
	# 目标先摸1张；摸牌产生的触发选择全部结束后才建立其额外弃牌阶段。
	host.draw(target_id, DRAW_BEFORE_DISCARD_COUNT)
	if bool(host.call("has_nested_settlement_barrier")):
		defer_settlement({"kind":"mice_start_target_discard", "target_id":target_id})
	else:
		_request_discard_phase(target_id, "mice_target_discard_complete", target_id)
	return true


## 在摸牌触发的嵌套结算结束后开始对应额外弃牌阶段。
func continue_settlement(context: Dictionary) -> bool:
	# 当前延后步骤；目标与佩拉摸牌后的弃牌阶段使用不同稳定kind。
	var settlement_kind: String = str(context.get("kind", ""))
	if settlement_kind == "mice_start_target_discard":
		_request_discard_phase(int(context.get("target_id", -1)), "mice_target_discard_complete", int(context.get("target_id", -1)))
		return true
	if settlement_kind == "mice_start_owner_discard":
		_request_discard_phase(owner_player_id, "mice_owner_discard_complete", int(context.get("first_target_id", -1)))
		return true
	return false


## 接收任一额外阶段完整结束通知，并按“另一项”规则创建后续阶段。
func continue_extra_phase(context: Dictionary) -> bool:
	# 完成步骤；四种阶段分别表示目标出牌、目标弃牌、佩拉弃牌与佩拉出牌。
	var completion_kind: String = str(context.get("kind", ""))
	# 第一名目标ID；只用于回放与后续完成上下文，不参与第二阶段目标合法性。
	var first_target_id: int = int(context.get("first_target_id", -1))
	if completion_kind == "mice_target_play_complete":
		# 目标完成额外出牌阶段后，佩拉摸1张并执行额外弃牌阶段。
		host.draw(owner_player_id, DRAW_BEFORE_DISCARD_COUNT)
		if bool(host.call("has_nested_settlement_barrier")):
			defer_settlement({"kind":"mice_start_owner_discard", "first_target_id":first_target_id})
		else:
			_request_discard_phase(owner_player_id, "mice_owner_discard_complete", first_target_id)
		return true
	if completion_kind == "mice_target_discard_complete":
		# 目标完成额外弃牌阶段后，佩拉执行额外出牌阶段且不额外摸牌。
		_request_play_phase(owner_player_id, "mice_owner_play_complete", first_target_id)
		return true
	if completion_kind in ["mice_owner_discard_complete", "mice_owner_play_complete"]:
		return true
	return false


## 请求指定角色执行独立额外出牌阶段；完成上下文始终绑定当前佩拉技能实例与武将代次。
func _request_play_phase(player_id: int, completion_kind: String, first_target_id: int) -> bool:
	# 阶段完成上下文；控制器只保存基础值并在阶段End、After完成后回调。
	var completion_context: Dictionary = _build_extra_phase_completion_context(completion_kind, first_target_id)
	return bool(host.call("request_extra_play_phase", player_id, owner_player_id, get_id(), completion_context))


## 请求指定角色执行额外弃牌阶段；阶段主体统一按手牌数超过手牌上限的差额弃置。
func _request_discard_phase(player_id: int, completion_kind: String, first_target_id: int) -> bool:
	# 阶段完成上下文；摸牌已经在调用前完成，本端口只负责完整阶段生命周期。
	var completion_context: Dictionary = _build_extra_phase_completion_context(completion_kind, first_target_id)
	return bool(host.call("request_extra_discard_phase", player_id, owner_player_id, get_id(), completion_context))


## 构建额外阶段完成回调的稳定上下文；技能归属字段不能由具体分支遗漏。
func _build_extra_phase_completion_context(completion_kind: String, first_target_id: int) -> Dictionary:
	return {
		"kind":completion_kind,
		"first_target_id":first_target_id,
		"skill_owner_id":owner_player_id,
		"skill_id":get_id(),
		"skill_character_generation":get_bound_character_generation(),
	}


## 评估所有“目标×阶段”组合的净收益；取消保持0分，AI只在总收益为正时发动。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非秘策复合选择不提供额外评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "mice_target_option":
		return 0.0
	# 选择负载；目标或选项缺失时视为取消或非法组合。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	var selected_control_id: String = str(payload.get("selected_control_id", ""))
	if not bool(payload.get("confirmed", false)) or selected_targets.size() != 1 or selected_control_id not in [PLAY_PHASE_OPTION_ID, DISCARD_PHASE_OPTION_ID]:
		return 0.0
	# 第一阶段目标；秘策所有候选均为佩拉以外角色。
	var target_id: int = int(selected_targets[0])
	if selected_control_id == PLAY_PHASE_OPTION_ID:
		# 目标获得出牌阶段，佩拉获得摸1张后的弃牌阶段。
		return _estimate_extra_play_phase_value(authoritative_snapshot, target_id, evaluator) + _estimate_draw_discard_phase_value(authoritative_snapshot, owner_player_id, evaluator)
	# 目标获得摸1张后的弃牌阶段，佩拉获得额外出牌阶段。
	return _estimate_draw_discard_phase_value(authoritative_snapshot, target_id, evaluator) + _estimate_extra_play_phase_value(authoritative_snapshot, owner_player_id, evaluator)


## 估算指定角色执行额外出牌阶段对佩拉的价值；手牌越多、已知可用牌越多，行动收益越高。
func _estimate_extra_play_phase_value(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标快照；无效、死亡或离场角色没有阶段收益。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
		return -20.0
	# 佩拉对目标的当前态度；友方行动为正收益，敌方行动为负收益。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 公开手牌行动空间；上限限制高牌量角色不会无限放大单个阶段估值。
	var hand_space_value: float = minf(float(maxi(int(target.get("hand_count", 0)), 0)) * AI_PLAY_HAND_VALUE, 5.0)
	# 已知可主动使用牌数量；权威AI快照可完整读取佩拉本人手牌，其他角色牌面缺失时安全得到0。
	var known_playable_count: int = _count_known_playable_cards(authoritative_snapshot, target)
	# 阶段基础值只在至少存在手牌或已知可发动行动时产生，空手角色不会凭空获得收益。
	var phase_value: float = hand_space_value + float(known_playable_count) * AI_KNOWN_PLAYABLE_CARD_VALUE
	return attitude / 5.0 * phase_value


## 估算“摸1张并执行额外弃牌阶段”的牌差价值；敌方超限越多越有利，友方越缺牌越有利。
func _estimate_draw_discard_phase_value(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标快照；无效角色无法摸牌或执行阶段。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
		return -20.0
	# 当前手牌数；额外摸牌发生后再按最新手牌上限计算弃置数量。
	var hand_count: int = maxi(int(target.get("hand_count", 0)), 0)
	# 当前手牌上限；与PlayerState.get_hand_limit保持体力、技能与模式加成一致，最低为0。
	var hand_limit: int = maxi(int(target.get("hp", 0)) + int(target.get("hand_limit_bonus", 0)) + int(target.get("mode_hand_limit_bonus", 0)), 0)
	# 摸牌后的强制弃置数量；敌人原本超限越多，该值越大。
	var discard_count: int = maxi(hand_count + DRAW_BEFORE_DISCARD_COUNT - hand_limit, 0)
	# 最终牌差；先摸1张再弃discard_count张，负值表示目标净失去手牌。
	var net_card_change: int = DRAW_BEFORE_DISCARD_COUNT - discard_count
	# 统一资源价值；友方得牌与敌方失牌都会从佩拉视角形成正收益。
	var result: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, net_card_change, 0)
	# 友方当前低于上限的空余容量；越缺牌，摸到的新牌越不易被弃置且即时选择空间越大。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	var hand_deficit: int = maxi(hand_limit - hand_count, 0)
	if attitude > 0.0 and hand_deficit > 0:
		result += attitude / 5.0 * float(hand_deficit) * AI_FRIENDLY_HAND_DEFICIT_VALUE
	return result


## 统计快照中明确可在出牌阶段主动使用的手牌；响应专用牌与当前不可用的回复牌不计入。
func _count_known_playable_cards(authoritative_snapshot: Dictionary, target: Dictionary) -> int:
	# 可用牌数量；只读取已经序列化的完整牌面，不猜测未知手牌具体类型。
	var result: int = 0
	for card_variant: Variant in target.get("hand", []) as Array:
		# 当前手牌快照；定义ID决定目标模式和特殊基础限制。
		var card: Dictionary = card_variant as Dictionary
		# 当前牌定义；异常空定义不会提供行动机会。
		var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		if definition.is_empty() or str(definition.get("target_mode", "")) == "response_only":
			continue
		if str(definition.get("id", "")) == "tao" and int(target.get("hp", 0)) >= int(target.get("max_hp", 0)):
			continue
		if str(definition.get("id", "")) == "jiu" and bool(target.get("wine_used", false)):
			continue
		# 至少存在一名其他存活角色时，常规目标牌具有潜在使用机会；无目标、自身与装备牌始终可由规则继续复核。
		var target_mode: String = str(definition.get("target_mode", ""))
		if target_mode in ["none", "self", "self_wounded", "all_players", "all_others", "equipment"] or _snapshot_has_other_alive_player(authoritative_snapshot, int(target.get("player_id", -1))):
			result += 1
	return result


## 判断快照中是否存在目标以外的存活在场角色；只用于估算常规目标牌的潜在行动空间。
func _snapshot_has_other_alive_player(authoritative_snapshot: Dictionary, target_id: int) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前候选角色；死亡、离场或目标本人均不能提供“其他角色”目标机会。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) != target_id and bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			return true
	return false
