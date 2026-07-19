extends SkillDefinition

## 【冰封】技能源码。持有者使用牌指定唯一目标时，可竖置目标或弃置其一张手牌，并令非自身目标的该牌无效。

## 竖置目标选项的稳定ID；仅用于选择协议与回放，玩家可见文本由选项label提供。
const STRAIGHTEN_OPTION_ID: String = "straighten_target"

## 弃置目标手牌选项的稳定ID；等待期间目标无手牌时只跳过该弃置效果。
const DISCARD_OPTION_ID: String = "discard_target_hand"

## AI对将一名横置角色调整为竖置的基础状态估值；只影响决策，不改变规则。
const AI_STRAIGHTEN_VALUE: float = 1.5

## AI对弃置一张未知手牌的基础控制估值；复用统一单牌资源值，选定实体后会再按牌面价值排序。
const AI_DISCARD_VALUE: float = NonameAIEvaluator.CARD_RESOURCE_VALUE

## 本技能已对各目标发动的回合号；键为稳定玩家ID，值为最近发动的state.turn_number。
var _used_turn_by_target: Dictionary = {}


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "bingfeng",
		"name": "冰封",
		"trigger": "useCardToTargeted",
		"ui_enabled": false,
		"description": "当你使用牌指定唯一目标时，你可选择一项：1.将目标的武将牌调整为竖直；2.弃置目标一张手牌。然后若该角色不为你，你令此牌无效。每回合每名角色限一次。",
	})


## 订阅持有者使用牌的指定目标后时机；最终目标数组必须恰好只有一名角色。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_owner_card_targeted, "source")


## 为当前唯一目标构造可执行选项；两项都不可执行时按通用规则直接跳过本次效果。
func _on_owner_card_targeted(event: RuleEvent) -> void:
	# 最终目标数组；唯一目标以完整声明数组长度为准，不使用当前游标猜测。
	var target_ids: Array = event.data.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return
	# 唯一目标ID；运行时限次按该ID独立记录。
	var target_id: int = int(target_ids[0])
	if int(_used_turn_by_target.get(target_id, -1)) == host.state.turn_number:
		return
	# 当前目标状态；死亡或离场角色不再创建选择。
	var target: PlayerState = host.state.get_player(target_id) as PlayerState
	if target == null or not target.alive or target.out_of_game:
		return
	# 可执行文字选项；按玩家指定顺序稳定排列，不显示当前必然无效的分支。
	var options: Array[Dictionary] = []
	if target.chained:
		options.append({"id":STRAIGHTEN_OPTION_ID, "label":"1.竖直目标武将牌"})
	if not target.hand.is_empty():
		options.append({"id":DISCARD_OPTION_ID, "label":"2.弃置目标手牌"})
	if options.is_empty():
		return
	request_control_selection("冰封", "是否对唯一目标发动【冰封】？", options, true, {"kind":"bingfeng_option", "target_id":target_id, "card_uid":int(event.data.get("card_uid", -1)), "card_id":str(event.data.get("card_id", ""))})


## 恢复冰封的分支选择或后续手牌选择；发动额度在确认分支时消耗。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；文字分支与弃置实体使用不同kind避免重复消耗限次。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "bingfeng_option":
		return _continue_option(context, response)
	if choice_kind == "bingfeng_discard_card":
		return _continue_discard_card(context, response)
	return false


## 执行玩家确认的冰封分支；分支在等待期间失效时只跳过对应内容，然后继续后置无效规则。
func _continue_option(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed:
		return true
	# 唯一目标ID；每回合每目标限次会在实际确认分支前再次复核。
	var target_id: int = int(context.get("target_id", -1))
	if int(_used_turn_by_target.get(target_id, -1)) == host.state.turn_number:
		return true
	# 当前目标；必须仍存活在场才能成立技能发动。
	var target: PlayerState = host.state.get_player(target_id) as PlayerState
	if target == null or not target.alive or target.out_of_game:
		return true
	# 已选分支ID；未知或空选项不消耗发动额度。
	var option_id: String = response.control_id
	if option_id not in [STRAIGHTEN_OPTION_ID, DISCARD_OPTION_ID]:
		return true
	_used_turn_by_target[target_id] = host.state.turn_number
	announce_activation({"target_id":target_id, "card_uid":int(context.get("card_uid", -1)), "option_id":option_id})
	if option_id == STRAIGHTEN_OPTION_ID:
		# 目标已竖置时统一设置端口会返回false；该分支按通用规则跳过，不阻断后置无效。
		host.call("set_player_linked", target_id, false, owner_player_id, get_id())
		_finish_effect(context)
		return true
	# 目标当前手牌候选；三月七作为选择者只能看见牌背，但稳定UID可完成权威弃置。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
	if candidates.is_empty():
		_finish_effect(context)
		return true
	# 后续选择上下文；保留原牌UID与目标供弃置后标记该目标无效。
	var discard_context: Dictionary = context.duplicate(true)
	discard_context["kind"] = "bingfeng_discard_card"
	request_card_selection("冰封", "请弃置目标一张手牌", candidates, 1, 1, false, discard_context)
	return true


## 恢复冰封弃置手牌步骤；所选实体已离开手牌区时只跳过弃置。
func _continue_discard_card(context: Dictionary, response: ChoiceResponse) -> bool:
	if response.confirmed and response.card_ids.size() == 1:
		host.call("discard_card_from_hand", int(context.get("target_id", -1)), response.card_ids[0])
	_finish_effect(context)
	return true


## 执行冰封的后置规则；目标不是技能持有者时，仅令当前牌对该目标无效。
func _finish_effect(context: Dictionary) -> void:
	# 唯一目标ID；自身目标不执行无效标记。
	var target_id: int = int(context.get("target_id", -1))
	if target_id != owner_player_id:
		host.call("exclude_card_target", int(context.get("card_uid", -1)), target_id, get_id())


## 评估冰封的分支与弃置牌选择；敌方分支必须严格优于原牌效才会确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；用于kind、原牌与唯一目标的稳定读取。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 标准选择负载；确认状态与已选内容均从该字典取得。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前选择步骤；仅处理本技能的两段请求。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "bingfeng_discard_card":
		# 已选手牌UID；统一强制弃牌基础分为负价值，技能再加两倍价值令AI选择价值最高的目标手牌。
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		return evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), int(context.get("target_id", -1))) * 2.0 if selected_cards.size() == 1 else -100.0
	if choice_kind != "bingfeng_option" or not bool(payload.get("confirmed", false)):
		return 0.0
	# 唯一目标ID；当前分支收益与原牌效都从技能持有者视角评估。
	var target_id: int = int(context.get("target_id", -1))
	# 当前目标快照；缺失时不应支付一次限次额度。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return -100.0
	# 持有者对目标的态度；正值为友方，负值为敌方。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 原牌对该目标的当前效用；非自身目标会被冰封消除，因此取相反数作为无效收益。
	var original_effect_score: float = _score_original_card_effect(authoritative_snapshot, target_id, str(context.get("card_id", "")), evaluator)
	# 令原牌对非自身目标无效的收益；自身不执行该句，因此保持0。
	var invalidation_score: float = -original_effect_score if target_id != owner_player_id else 0.0
	# 已选文字分支ID；其他值视为无效提交。
	var option_id: String = str(payload.get("selected_control_id", ""))
	if option_id == STRAIGHTEN_OPTION_ID:
		# 竖置收益；帮助横置友方为正，竖置横置敌方为负。
		var straighten_score: float = attitude / 5.0 * AI_STRAIGHTEN_VALUE if bool(target.get("chained", false)) else 0.0
		return invalidation_score + straighten_score
	if option_id == DISCARD_OPTION_ID:
		# 弃置收益；弃敌方牌为正、弃友方牌为负，与原牌无效收益合并后必须严格大于取消的0分。
		var discard_score: float = -attitude / 5.0 * AI_DISCARD_VALUE
		return invalidation_score + discard_score
	return -100.0


## 修正持有者的出牌评分；对横置友方的负收益单目标牌可转化为竖置收益。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 最终目标数组；冰封只会处理恰好一名目标的动作。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return current_score
	# 唯一目标ID；自身目标不会令原牌无效，不属于负收益转化行为。
	var target_id: int = int(target_ids[0])
	if target_id == owner_player_id or _was_target_used_in_snapshot(authoritative_snapshot, target_id):
		return current_score
	# 目标公开状态；只有横置角色可选“竖直目标武将牌”。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("chained", false)):
		return current_score
	# 持有者对目标的态度；只主动对友方使用负收益牌完成转化。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude <= 0.0:
		return current_score
	# 原牌目标效用；只有从持有者视角为负时才是需要转化的负收益牌。
	var original_effect_score: float = _score_original_card_effect(authoritative_snapshot, target_id, str(action.get("card_definition_id", "")), evaluator)
	if original_effect_score >= 0.0:
		return current_score
	# 竖置收益；先从基础分移除原负面牌效，再加入恢复竖置的状态收益。
	var straighten_score: float = attitude / 5.0 * AI_STRAIGHTEN_VALUE
	return current_score - original_effect_score + straighten_score


## 返回一张牌对指定目标的AI效用；使用标准牌效元数据与身份战略评估。
func _score_original_card_effect(authoritative_snapshot: Dictionary, target_id: int, card_id: String, evaluator: Object) -> float:
	# 原牌定义；未知牌不猜测效果，保守0分。
	var definition: Dictionary = GameDatabase.get_card(card_id)
	if definition.is_empty():
		return 0.0
	# 原牌AI配置；兼容卡牌文件的新ai字典与旧目标方向字段。
	var ai_profile: Dictionary = evaluator.get_card_ai_profile(definition)
	# 原牌对目标的基础结果；负值代表伤害、弃牌或阶段控制。
	var target_result: float = float(ai_profile.get("target_result", 0.0))
	return evaluator.score_target_effect(authoritative_snapshot, owner_player_id, target_id, definition, ai_profile, target_result)


## 从公开技能历史判断本回合是否已对目标发动冰封；AI不读取运行时字典。
func _was_target_used_in_snapshot(authoritative_snapshot: Dictionary, target_id: int) -> bool:
	# 技能持有者快照；只读取公开技能发动历史。
	var owner: Dictionary = {}
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；稳定ID匹配后保留引用供后续只读遍历。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == owner_player_id:
			owner = player
			break
	# 当前全局回合号；与发动历史的turn_number字段精确比较。
	var current_turn_number: int = int(authoritative_snapshot.get("turn_number", -1))
	for history_variant: Variant in owner.get("skill_history", []) as Array:
		# 单次技能发动记录；技能ID、回合号与目标均匹配时才认为限次已消耗。
		var history: Dictionary = history_variant as Dictionary
		# 发动上下文；目标ID由announce_activation在确认分支时写入。
		var history_context: Dictionary = history.get("context", {}) as Dictionary
		if str(history.get("skill_id", "")) == get_id() and int(history.get("turn_number", -2)) == current_turn_number and int(history_context.get("target_id", -1)) == target_id:
			return true
	return false
