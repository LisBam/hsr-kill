extends SkillDefinition

## 【再现】技能源码。持有者每个出牌阶段可在【杀】指定目标后弃置一张牌，造成伤害后获得收益。

## 当前出牌阶段是否已发动；每次 phaseUseBegin 重置，成功弃牌后设为 true。
var _used_this_play_phase: bool = false

## 当前被强化的【杀】实体 UID；默认-1表示没有等待伤害结果的牌。
var _tracked_slash_uid: int = -1

## 当前被强化的【杀】逻辑卡牌 ID；用于关联伤害事件中的普通、火或雷【杀】。
var _tracked_slash_card_id: String = ""

## 当前被强化的【杀】是否已经造成至少一次伤害；伤害值大于0即视为造成伤害。
var _tracked_slash_dealt_damage: bool = false


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "zaixian",
		"name": "再现",
		"trigger": "useCardToTargeted",
		"ui_enabled": false,
		"description": "出牌阶段限一次，当你使用【杀】指定目标后，你可弃置一张牌；若此【杀】造成伤害，你摸一张牌并于本阶段结束后执行一个额外的出牌阶段。",
	})


## 订阅阶段重置、【杀】指定目标、伤害来源与【杀】结算结束时机。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")
	subscribe_timing("useCardToTargeted", _on_owner_slash_targeted, "source")
	subscribe_timing("damageSource", _on_owner_damage_source, "source")
	subscribe_timing("shaAfter", _on_owner_slash_after, "source")


## 每个出牌阶段恢复发动次数，并清理未完成的旧【杀】关联状态。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false
	_clear_tracked_slash()


## 持有者的【杀】指定目标后询问弃置一张手牌或装备牌；成功支付后才消耗阶段次数。
func _on_owner_slash_targeted(event: RuleEvent) -> void:
	if _used_this_play_phase or host.state.current_phase != "play":
		return
	# 当前逻辑牌定义；三种【杀】共享 effect_id=slash，避免依赖具体稳定 ID。
	var card_definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(card_definition.get("effect_id", "")) != "slash":
		return
	# 可弃置材料；“一张牌”允许从自己的手牌区或装备区选择，不包含判定区与木牛“粮”。
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	request_card_selection("再现", "你可以弃置一张牌发动【再现】", candidates, 0, 1, true, {"kind":"zaixian_discard", "slash_uid":int(event.data.get("card_uid", -1)), "slash_card_id":str(event.data.get("card_id", "")), "slash_target_id":event.target_id})


## 恢复弃牌选择；支付成功后开始跟踪本张【杀】是否造成伤害。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "zaixian_discard" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 1:
		# 实际弃置数量；等待期间材料离区时不消耗技能次数，也不建立错误的伤害关联。
		var discarded_count: int = int(host.call("discard_selected_hand_equipment", owner_player_id, response.card_ids))
		if discarded_count == 1:
			_used_this_play_phase = true
			announce_activation({"slash_uid":int(context.get("slash_uid", -1))})
			_tracked_slash_uid = int(context.get("slash_uid", -1))
			_tracked_slash_card_id = str(context.get("slash_card_id", ""))
			_tracked_slash_dealt_damage = false
	return true


## 被强化【杀】作为来源造成伤害时记录成立；护盾完整吸收仍属于造成伤害。
## 时机说明：本回调订阅扣减与濒死处理后的damageSource，只记录“已经造成伤害”的事实，不属于规则术语中的前置“造成伤害时”。
func _on_owner_damage_source(event: RuleEvent) -> void:
	if _tracked_slash_uid < 0 or str(event.data.get("card_id", "")) != _tracked_slash_card_id:
		return
	if int(event.data.get("amount", 0)) > 0:
		_tracked_slash_dealt_damage = true


## 被强化【杀】完成目标结算后发放摸牌，并用额外出牌阶段队列等待当前阶段完整结束。
func _on_owner_slash_after(event: RuleEvent) -> void:
	if int(event.data.get("card_uid", -1)) != _tracked_slash_uid:
		return
	if _tracked_slash_dealt_damage:
		host.call("draw", owner_player_id, 1)
		get_owner_skill_player().addPlayPhase()
	_clear_tracked_slash()


## 清理当前强化【杀】的临时关联，避免后续同名牌伤害错误触发收益。
func _clear_tracked_slash() -> void:
	_tracked_slash_uid = -1
	_tracked_slash_card_id = ""
	_tracked_slash_dealt_damage = false


## 评估弃置一张牌强化当前【杀】的收益；敌方低体力目标更值得投入，费用优先选择最低价值牌。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理再现弃牌步骤。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "zaixian_discard":
		return 0.0
	# 动作负载；取消不支付费用也不获得后续收益。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 已选费用牌；再现确认时必须恰好一张。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != 1:
		return 0.0
	# 当前【杀】目标 ID；用于估算命中价值与额外阶段收益是否值得投资。
	var target_id: int = int(context.get("slash_target_id", -1))
	# 目标状态；低体力和少手牌提高【杀】造成伤害的概率。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return -10.0
	# 命中收益；对敌方目标取正，目标体力越低额外奖励越高。
	var hit_value: float = -evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if int(target.get("hp", 0)) <= 2:
		hit_value += 2.0
	if int(target.get("hand_count", 0)) == 0:
		hit_value += 2.0
	# 弃牌费用；低价值牌更适合作为再现成本。
	var cost_value: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
	return hit_value + 3.0 - cost_value
