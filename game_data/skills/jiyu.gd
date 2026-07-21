extends SkillDefinition

## 【疾雨】技能源码。持有者使用任意【杀】指定目标时，可令目标调整至横置状态，再由目标在不可使用【闪】与令持有者横置范围内另一名角色之间选择。

## 目标不可使用【闪】响应的稳定选项ID；通过当前使用牌的direct_hit_target_ids实现。
const DIRECT_HIT_OPTION_ID: String = "direct_hit"

## 令丹恒横置攻击范围内另一名角色的稳定选项ID；没有合法角色时不展示该项。
const REDIRECT_LINK_OPTION_ID: String = "link_other"

## AI对令一名未横置角色调整至横置状态的基础估值；应与【冰封】的状态估值保持同一量级。
const AI_LINK_VALUE: float = 1.5

## AI在目标没有已知【闪】时选择不可响应的优先分；高于通用取消与普通选项分。
const AI_PREFERRED_OPTION_SCORE: float = 6.0

## AI使用任意【杀】触发疾雨的主动优先分；只提高已有【杀】动作价值，不再诱导雷【杀】转换。
const AI_SLASH_PRIORITY_BONUS: float = 4.0


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "jiyu",
		"name": "疾雨",
		"trigger": "useCardToTargeted",
		"ui_enabled": false,
		"description": "当你使用【杀】指定目标时，你可令目标角色调整至横置状态，然后令目标角色选择：1.其不可使用【闪】响应此【杀】；2.令你横置你攻击范围内的另一名角色。",
	})


## 订阅持有者使用牌的指定目标后时机；普通、火与雷【杀】均通过共享slash牌效识别。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_slash_targeted, "source")


## 任意【杀】指定一名存活目标后请求丹恒确认发动；取消不改变横置或响应状态。
func _on_slash_targeted(event: RuleEvent) -> void:
	# 当前使用牌定义；三种【杀】共享slash牌效，其他基本牌与锦囊不会触发。
	var definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(definition.get("effect_id", "")) != "slash":
		return
	# 当前目标ID；死亡或离场目标不再触发可选效果。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	# 当前目标状态；只用于发动前存活与离场复核。
	var target: PlayerState = host.state.get_player(target_id) as PlayerState
	if target == null or not target.alive or target.out_of_game:
		return
	request_card_selection("疾雨", "是否对%s发动【疾雨】？" % target.display_name, [], 0, 0, true, {"kind":"jiyu_confirm", "target_id":target_id, "card_uid":int(event.data.get("card_uid", -1)), "ai_allow_confirm":true})


## 恢复疾雨的发动确认、目标分支选择与丹恒的另一名角色选择。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；三个步骤分别由丹恒、【杀】目标、丹恒作出决定。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "jiyu_confirm":
		return _continue_confirm(context, response)
	if choice_kind == "jiyu_target_option":
		return _continue_target_option(context, response)
	if choice_kind == "jiyu_link_other_target":
		return _continue_link_other_target(context, response)
	return false


## 执行丹恒的发动确认；先令原目标调整至横置状态，再由目标选择响应限制或横置另一名角色。
func _continue_confirm(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed:
		return true
	# 原【杀】目标ID；等待期间已死亡或离场时直接跳过整个后续效果。
	var target_id: int = int(context.get("target_id", -1))
	# 原目标状态；还存活在场时才能作为后续选项的决定者。
	var target: PlayerState = host.state.get_player(target_id) as PlayerState
	if target == null or not target.alive or target.out_of_game:
		return true
	announce_activation({"target_id":target_id, "card_uid":int(context.get("card_uid", -1))})
	host.call("set_player_linked", target_id, true, owner_player_id, get_id())
	_request_target_option(context)
	return true


## 请求【杀】目标选择后续分支；丹恒范围内无另一名角色时只保留不可响应选项。
func _request_target_option(context: Dictionary) -> void:
	# 原【杀】目标ID；不可作为“另一名角色”的后续候选。
	var target_id: int = int(context.get("target_id", -1))
	# 攻击范围查询的排除目标；显式Array[int]类型保证动态调用与权威端口一致。
	var excluded_target_ids: Array[int] = [target_id]
	# 丹恒攻击范围内的另一名角色；函数自动排除丹恒自身，这里再排除原目标。
	var redirect_target_ids: Array[int] = host.call("get_players_in_attack_range", owner_player_id, excluded_target_ids) as Array[int]
	# 玩家可见文字选项；标签严格使用指定文本并保持顺序。
	var options: Array[Dictionary] = [{"id":DIRECT_HIT_OPTION_ID, "label":"1.不可响应此【杀】"}]
	if not redirect_target_ids.is_empty():
		options.append({"id":REDIRECT_LINK_OPTION_ID, "label":"2.令其横置一名角色"})
	# 后续分支上下文；候选ID快照只用于AI估值，实际选中后会重新计算攻击范围。
	var option_context: Dictionary = context.duplicate(true)
	option_context["kind"] = "jiyu_target_option"
	option_context["redirect_target_ids"] = redirect_target_ids.duplicate()
	request_control_selection_for_player(target_id, "疾雨", "请选择【疾雨】的后续效果", options, false, option_context)


## 执行【杀】目标选定的分支；第二项在范围内无合法角色时直接跳过。
func _continue_target_option(context: Dictionary, response: ChoiceResponse) -> bool:
	# 原【杀】目标ID；直击标记只能写入该牌声明过的目标。
	var target_id: int = int(context.get("target_id", -1))
	if response.control_id == DIRECT_HIT_OPTION_ID:
		host.call("add_card_direct_hit_target", int(context.get("card_uid", -1)), target_id, get_id())
		return true
	if response.control_id != REDIRECT_LINK_OPTION_ID:
		return true
	# 攻击范围查询的排除目标；原雷【杀】目标不属于“另一名角色”。
	var excluded_target_ids: Array[int] = [target_id]
	# 提交时重新计算丹恒攻击范围；装备、坐骑或存活座次变化后不沿用旧候选。
	var redirect_target_ids: Array[int] = host.call("get_players_in_attack_range", owner_player_id, excluded_target_ids) as Array[int]
	if redirect_target_ids.is_empty():
		return true
	# 横置目标选择上下文；保留原牌与目标数据便于AI、网络与回放追溯。
	var link_context: Dictionary = context.duplicate(true)
	link_context["kind"] = "jiyu_link_other_target"
	request_target_selection("【疾雨】请选择攻击范围内的另一名角色", redirect_target_ids, 1, 1, false, link_context)
	return true


## 执行丹恒选定的横置切换；等待期间目标离开范围时跳过该效果。
func _continue_link_other_target(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed or response.target_ids.size() != 1:
		return true
	# 攻击范围查询的排除目标；使用强类型数组避免动态调用参数类型不匹配。
	var excluded_target_ids: Array[int] = [int(context.get("target_id", -1))]
	# 当前合法候选；每次恢复都以实时攻击范围复核。
	var legal_target_ids: Array[int] = host.call("get_players_in_attack_range", owner_player_id, excluded_target_ids) as Array[int]
	# 已选另一名角色ID；不在实时候选中时不改变任何状态。
	var selected_target_id: int = response.target_ids[0]
	if legal_target_ids.has(selected_target_id):
		host.call("toggle_player_linked", selected_target_id, owner_player_id, get_id())
	return true


## 提高全部【杀】主动动作的评分，使AI在合法且有利时优先触发疾雨。
func modify_ai_card_action_score(_authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, _evaluator: Object) -> float:
	if str(action.get("action_type", "")) != "use_card":
		return current_score
	# 当前逻辑牌定义；普通、火与雷【杀】通过共享slash牌效识别，不绑定实体牌UID。
	var definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	if str(definition.get("effect_id", "")) != "slash":
		return current_score
	return current_score + AI_SLASH_PRIORITY_BONUS


## 评估疾雨的发动确认、目标分支与丹恒的横置目标；完整实现指定的【闪】判断与队友优先规则。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；三个选择步骤共用原【杀】目标ID。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 选择动作负载；文字选项、目标ID与确认状态均在该字典中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前选择步骤；非疾雨请求不附加任何评分。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "jiyu_confirm":
		if not bool(payload.get("confirmed", false)):
			return 0.0
		# 原【杀】目标ID；对敌方发动通常有利，对友方使用控制效果通常不利。
		var target_id: int = int(context.get("target_id", -1))
		# 原目标快照；已横置时首次效果不再改变状态，仍可继续选择后续控制分支。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		# 丹恒对目标的态度；敌方负态度使不可响应或横置其他角色的控制收益为正。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		# 后续控制分支基础收益；即使原目标已经横置，AI仍会考虑不可响应或第二目标效果。
		var control_value: float = -attitude / 5.0 * AI_PREFERRED_OPTION_SCORE
		if not bool(target.get("chained", false)):
			control_value += -attitude / 5.0 * AI_LINK_VALUE
		return control_value
	if choice_kind == "jiyu_target_option":
		# 目标选定的文字分支ID；两个选项均不可取消。
		var option_id: String = str(payload.get("selected_control_id", ""))
		# 原【杀】目标ID；用于检查其已知【闪】数量。
		var target_id: int = int(context.get("target_id", -1))
		# 丹恒攻击范围内的另一名角色候选；只用触发时的稳定快照判断“只有丹恒队友”。
		var redirect_target_ids: Array = context.get("redirect_target_ids", []) as Array
		# 候选是否全为丹恒队友；非空且每名角色对丹恒均为正态度时成立。
		var only_owner_allies: bool = not redirect_target_ids.is_empty()
		for redirect_target_variant: Variant in redirect_target_ids:
			if evaluator.get_attitude(authoritative_snapshot, owner_player_id, int(redirect_target_variant)) <= 0.0:
				only_owner_allies = false
				break
		if only_owner_allies:
			return AI_PREFERRED_OPTION_SCORE if option_id == REDIRECT_LINK_OPTION_ID else 0.0
		# 范围内敌对角色是否至少存在一名；空集合不能被“全部横置”的逻辑误判为成立。
		var has_hostile_redirect_target: bool = false
		# 范围内敌对角色是否全部处于横置状态；成立时优先选择横置分支，避免担心把未横置敌人新增为连环目标。
		var all_hostile_redirect_targets_chained: bool = true
		for redirect_target_variant: Variant in redirect_target_ids:
			# 当前范围候选ID；用于读取态度与横置状态。
			var redirect_target_id: int = int(redirect_target_variant)
			if evaluator.get_attitude(authoritative_snapshot, owner_player_id, redirect_target_id) >= 0.0:
				continue
			has_hostile_redirect_target = true
			# 当前敌对候选快照；任一敌对角色未横置就不满足统一优先条件。
			var redirect_target: Dictionary = evaluator.get_player(authoritative_snapshot, redirect_target_id)
			if not bool(redirect_target.get("chained", false)):
				all_hostile_redirect_targets_chained = false
				break
		if has_hostile_redirect_target and all_hostile_redirect_targets_chained:
			return AI_PREFERRED_OPTION_SCORE if option_id == REDIRECT_LINK_OPTION_ID else 0.0
		# 目标已知【闪】数量；无【闪】选第1项，有【闪】选第2项。
		var known_shan_count: int = evaluator.get_known_response_count(authoritative_snapshot, target_id, "shan")
		if known_shan_count <= 0:
			return AI_PREFERRED_OPTION_SCORE if option_id == DIRECT_HIT_OPTION_ID else 0.0
		return AI_PREFERRED_OPTION_SCORE if option_id == REDIRECT_LINK_OPTION_ID else 0.0
	if choice_kind == "jiyu_link_other_target":
		# 已选另一名角色；本步骤必须恰好一名目标。
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.size() != 1:
			return -100.0
		# 已选目标ID；切换方向由其当前横置状态决定。
		var selected_target_id: int = int(selected_targets[0])
		# 已选目标快照；缺失状态时不应赋予高分。
		var selected_target: Dictionary = evaluator.get_player(authoritative_snapshot, selected_target_id)
		# 丹恒对已选目标的态度；横置敌方或竖置已横置友方为正收益。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, selected_target_id)
		return attitude / 5.0 * AI_LINK_VALUE if bool(selected_target.get("chained", false)) else -attitude / 5.0 * AI_LINK_VALUE
	return 0.0
