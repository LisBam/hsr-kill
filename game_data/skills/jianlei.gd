extends SkillDefinition

## 【坚垒】技能源码。距离1的其他角色成为黑色【杀】目标时，可弃【闪】横置该角色并令本目标无效。


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id": "jianlei",
		"name": "坚垒",
		"trigger": "useCardToPlayer",
		"ui_enabled": false,
		"description": "当一名距离为1的其他角色成为黑色【杀】的目标时，你可弃置一张【闪】并横置该角色，然后令此【杀】无效。",
	})


## 全局监听每名角色成为目标的最早时机；发动确认后只排除当前角色，不影响同牌其他目标。
func install() -> void:
	subscribe_timing("useCardToPlayer", _on_any_targeted, "global", 50)


## 检查其他距离1角色、黑色【杀】和【闪】费用，满足时询问技能持有者。
func _on_any_targeted(event: RuleEvent) -> void:
	# 当前目标ID；持有者自己不满足“一名其他角色”。
	var target_id: int = event.target_id
	if target_id == owner_player_id or host.card_rules.calculate_distance(owner_player_id, target_id) != 1:
		return
	# 当前使用牌UID；处理区实体同时提供逻辑牌族与真实颜色。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if not bool(host.call("is_processing_black_slash", card_uid)):
		return
	# 普通手牌区【闪】候选；没有费用时不创建只能取消的窗口。
	var shan_candidates: Array[Dictionary] = _get_hand_shan_candidates()
	if shan_candidates.is_empty():
		return
	request_card_selection("坚垒", "是否弃置一张【闪】保护该角色？", shan_candidates, 0, 1, true, {"kind":"jianlei_cost", "target_id":target_id, "card_uid":card_uid})


## 恢复坚垒费用选择；等待期间距离、目标、牌色或费用失效时不执行任何效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "jianlei_cost" or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != 1:
		return true
	# 当前目标ID；必须仍为其他存活在场且距离1的角色。
	var target_id: int = int(context.get("target_id", -1))
	# 当前目标状态；无效、死亡或离场时不消费费用。
	var target: PlayerState = host.state.get_player(target_id) as PlayerState
	if target == null or not target.alive or target.out_of_game or target_id == owner_player_id or host.card_rules.calculate_distance(owner_player_id, target_id) != 1:
		return true
	# 当前父牌UID；必须仍是处理区中的黑色【杀】且目标尚未被其他效果排除。
	var card_uid: int = int(context.get("card_uid", -1))
	if not bool(host.call("is_processing_black_slash", card_uid)):
		return true
	# 当前费用UID；仅接受普通手牌区中的【闪】。
	var shan_uid: int = response.card_ids[0]
	if not _is_hand_shan(shan_uid) or not bool(host.call("discard_card_from_hand", owner_player_id, shan_uid)):
		return true
	host.call("set_player_linked", target_id, true, owner_player_id, get_id())
	host.call("exclude_card_target", card_uid, target_id, get_id())
	announce_activation({"card_uid":card_uid, "cost_card_uid":shan_uid, "target_id":target_id})
	observe_identity_behavior([target_id], {"target_result":1.0})
	return true


## 返回普通手牌区中的全部【闪】候选。
func _get_hand_shan_candidates() -> Array[Dictionary]:
	# 过滤结果；保持原手牌顺序稳定展示。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		# 当前牌面数据；自身手牌对本人完全可见。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(card_data.get("definition_id", "")) == "shan":
			result.append(candidate)
	return result


## 判断指定UID是否仍为持有者普通手牌区中的【闪】。
func _is_hand_shan(card_uid: int) -> bool:
	# 技能持有者；无效角色没有合法弃置费用。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 当前手牌实体；木牛“粮”不会命中该查询。
	var card: CardInstance = owner.find_hand_card(card_uid) if owner != null else null
	return card != null and card.definition_id == "shan"


## AI仅在保护友方的收益高于弃【闪】与横置风险时发动，对敌方目标默认放弃。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非坚垒费用询问不改变通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "jianlei_cost":
		return 0.0
	# 取消动作保持0分；确认需要实际选中一张【闪】。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 被保护目标；友方濒危时防止1点【杀】伤害价值显著提高。
	var target_id: int = int(context.get("target_id", -1))
	# 当前目标快照；用于读取体力，缺失时按普通状态处理。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	# 费用实体；高价值【闪】会提高机会成本。
	var selected_card_uids: Array = payload.get("selected_card_uids", []) as Array
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(selected_card_uids[0])) if selected_card_uids.size() == 1 else 8.0
	# 防护收益；1体力友方额外获得濒死规避价值，横置风险固定扣1分。
	var rescue_bonus: float = 4.0 if int(target.get("hp", 4)) <= 1 else 0.0
	return evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) * 1.4 + rescue_bonus - material_value * 0.55 - 1.0
