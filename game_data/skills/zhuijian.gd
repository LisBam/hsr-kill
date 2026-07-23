extends SkillDefinition

## 【追歼】技能源码。准备阶段弃置一张自有牌并标记一名其他角色，使其下一次实际受到的属性伤害增加1点。

## 属性伤害增加值；固定1点，与技能原文和玩法数值文档保持一致。
const DAMAGE_BONUS_AMOUNT: int = 1

## 追歼文本在武将牌左上角组合条目中的排序值；较小值使短期受击提示优先于回合统计文本。
const CORNER_TEXT_ORDER: int = 50

## 当前被追歼标记的目标玩家ID；默认-1表示没有持续效果。
var _marked_target_id: int = -1

## 已经在damageBegin3预留本效果的伤害事件ID；默认-1，防止同一外层伤害中的嵌套伤害重复获得加成。
var _reserved_damage_event_id: int = -1


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"zhuijian",
		"name":"追歼",
		"trigger":"phaseZhunbeiBegin/damageBegin3",
		"ui_enabled":false,
		"description":"准备阶段，你可以弃置一张牌并选择一名其他角色，其下次受到的属性伤害+1直到你的下个回合开始。",
	})


## 订阅准备阶段、回合开始、伤害修改与伤害结果时机；持续标记由本技能实例独立维护。
func install() -> void:
	subscribe_timing("phaseZhunbeiBegin", _on_preparation_phase_begin, "player")
	subscribe_timing("phaseBefore", _on_owner_turn_before, "player")
	subscribe_timing("damageBegin3", _on_damage_begin_three, "global")
	subscribe_timing("damage", _on_damage_happened, "global")
	subscribe_timing("damageCancelled", _on_damage_not_happened, "global")
	subscribe_timing("damageZero", _on_damage_not_happened, "global")
	subscribe_timing("dieAfter", _on_player_died, "global")


## 卸载技能时清除仍存在的目标提示，再释放基类管理的全部订阅。
func uninstall() -> void:
	_clear_mark()
	super()


## 准备阶段同时请求一张手牌或装备牌与一名其他角色；没有任一维度候选时不创建空询问。
func _on_preparation_phase_begin(_event: RuleEvent) -> void:
	# 可弃置自有牌；“一张牌”包含普通手牌与装备区，不包含判定区和木牛“粮”。
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 其他存活角色；目标必须在场且不为技能持有者。
	var target_ids: Array[int] = host.call("get_other_alive_player_ids", owner_player_id) as Array[int]
	if candidates.is_empty() or target_ids.is_empty():
		return
	request_card_target_selection("追歼", "请弃置一张牌并选择一名其他角色", candidates, target_ids, 1, 1, 1, 1, true, {"kind":"zhuijian_cost_target"})


## 持有者下个回合开始时令尚未触发的追歼失效；该时机早于新的准备阶段发动窗口。
func _on_owner_turn_before(_event: RuleEvent) -> void:
	_clear_mark()


## 在第三伤害修改窗口为预留的下一次火焰或雷属性伤害增加1点。
func _on_damage_begin_three(event: RuleEvent) -> void:
	if _marked_target_id < 0 or event.target_id != _marked_target_id:
		return
	# 当前伤害属性；normal不属于属性伤害，只有fire与thunder可以消费追歼。
	var nature: String = str(event.data.get("nature", "normal"))
	if nature not in ["fire", "thunder"]:
		return
	# 当前伤害事件ID；外层伤害一旦预留，嵌套产生的不同伤害必须等待外层实际结果后再判断。
	var damage_event_id: int = int(event.data.get("damage_event_id", -1))
	if damage_event_id < 0 or (_reserved_damage_event_id >= 0 and _reserved_damage_event_id != damage_event_id):
		return
	_reserved_damage_event_id = damage_event_id
	event.data["amount"] = maxi(int(event.data.get("amount", 0)), 0) + DAMAGE_BONUS_AMOUNT


## 预留伤害实际成立时消费追歼；即使伤害全部由护盾吸收，仍属于“受到属性伤害”。
func _on_damage_happened(event: RuleEvent) -> void:
	if int(event.data.get("damage_event_id", -1)) == _reserved_damage_event_id and event.target_id == _marked_target_id:
		_clear_mark()


## 预留伤害被取消或最终归零时只释放事件占用，追歼继续等待下一次实际属性伤害。
func _on_damage_not_happened(event: RuleEvent) -> void:
	if int(event.data.get("damage_event_id", -1)) == _reserved_damage_event_id:
		_reserved_damage_event_id = -1


## 发动者或目标死亡后移除没有继续意义的持续标记与公开提示。
func _on_player_died(event: RuleEvent) -> void:
	# 死亡角色ID；死亡标准时机以player_id表达当前死亡主体。
	var dead_player_id: int = event.player_id
	if dead_player_id == owner_player_id or dead_player_id == _marked_target_id:
		_clear_mark()


## 恢复弃牌与目标组合选择；费用实际进入弃牌堆后才建立持续标记。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "zhuijian_cost_target" or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != 1 or response.target_ids.size() != 1:
		return true
	# 最终目标ID；等待期间死亡、离场或变为技能持有者时本次发动失效。
	var target_id: int = response.target_ids[0]
	if not (host.call("get_other_alive_player_ids", owner_player_id) as Array[int]).has(target_id):
		return true
	# 本次作为发动费用弃置的唯一卡牌实体ID；显式使用强类型数组以适配权威弃牌接口。
	var selected_cost_uids: Array[int] = [response.card_ids[0]]
	# 实际弃置数量；权威端口只接受仍在持有者手牌或装备区中的所选实体。
	var discarded_count: int = int(host.call("discard_selected_hand_equipment", owner_player_id, selected_cost_uids))
	if discarded_count != 1:
		return true
	announce_activation({"target_id":target_id, "card_uid":response.card_ids[0]})
	observe_identity_behavior([target_id], {"target_result":-1.0, "damage":true, "nature_damage":true})
	# 弃牌引发的失牌技能或装备询问必须先完成，随后再写入追歼标记。
	if bool(host.call("has_nested_settlement_barrier")):
		defer_settlement({"kind":"zhuijian_apply_mark", "target_id":target_id})
	else:
		_apply_mark(target_id)
	return true


## 在弃牌产生的全部嵌套结算结束后建立追歼持续效果。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "zhuijian_apply_mark":
		return false
	_apply_mark(int(context.get("target_id", -1)))
	return true


## 复核目标并写入本实例的持续标记与左上角提示；再次写入前先清理旧目标。
func _apply_mark(target_id: int) -> void:
	# 最终目标；必须仍为存活在场的其他角色。
	var target: PlayerState = host.state.get_player(target_id) if host != null and host.get("state") != null else null
	if target == null or not target.alive or target.out_of_game or target_id == owner_player_id:
		return
	_clear_mark()
	_marked_target_id = target_id
	_reserved_damage_event_id = -1
	host.call("set_character_corner_text_entry", target_id, _get_corner_entry_id(), "追歼", CORNER_TEXT_ORDER)


## 清除本实例的目标、伤害预留与公开文本；重复调用保持幂等。
func _clear_mark() -> void:
	if host != null and _marked_target_id >= 0 and host.has_method("remove_character_corner_text_entry"):
		host.call("remove_character_corner_text_entry", _marked_target_id, _get_corner_entry_id())
	_marked_target_id = -1
	_reserved_damage_event_id = -1


## 返回本技能实例的稳定左上角条目ID；玩家ID区分多名佩拉同时施加的追歼。
func _get_corner_entry_id() -> String:
	return "zhuijian:%d" % owner_player_id


## 评估追歼的费用与目标；优先低价值弃牌和更可能承受属性伤害的敌方或横置角色。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非追歼组合选择不提供额外评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "zhuijian_cost_target":
		return 0.0
	# 选择动作；取消或维度不完整保持0分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if not bool(payload.get("confirmed", false)) or selected_cards.size() != 1 or selected_targets.size() != 1:
		return 0.0
	# 目标关系；敌方负态度会转化为正收益，友方目标通常低于取消动作。
	var target_id: int = int(selected_targets[0])
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 目标状态；横置角色更可能受到属性伤害或连环传导，因此略微提高标记价值。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	var chain_bonus: float = 1.0 if bool(target.get("chained", false)) else 0.0
	# 费用牌价值；优先弃置低保留价值实体，避免用救命牌换取不确定增伤。
	var card_cost: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
	return -attitude * 0.7 + chain_bonus + 1.5 - card_cost * 0.35
