extends SkillDefinition

## 【铁壁】技能源码。每轮开始可弃置一张普通手牌区【闪】，横置一名其他角色并临时授予【琥珀】。

## 被授予的临时技能稳定ID；通过数据库工厂创建独立运行时实例。
const GRANTED_SKILL_ID: String = "hupo"


## 写入技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id": "tiebi",
		"name": "铁壁",
		"trigger": "roundStart",
		"ui_enabled": false,
		"description": "每轮开始时，你可弃置一张【闪】并横置一名其他角色，其获得技能“琥珀”直到本轮结束。",
	})


## 订阅全局轮开始；每轮仅有一个roundStart，因此持有者只会获得一次询问。
func install() -> void:
	subscribe_timing("roundStart", _on_round_start, "global")


## 存在未横置其他角色时创建牌与目标组合选择；即使没有【闪】也保留可取消询问，防止旁观者从请求是否出现反推隐藏手牌。
## “横置一名角色”按状态切换解释，已经横置的其他角色同样是合法目标，再次横置会将其调整为竖直。
func _on_round_start(_event: RuleEvent) -> void:
	# 普通手牌区【闪】候选；木牛“粮”不属于手牌弃置费用。
	var shan_candidates: Array[Dictionary] = _get_hand_shan_candidates()
	# 可横置目标；排除持有者、死亡离场角色与已经横置者。
	# 私有函数名继续保留“未横置”的兼容含义，但通用横置术语按状态切换，不再排除已横置角色。
	# 可横置目标；只排除持有者、死亡与离场角色，当前已横置角色仍可被再次横置并切换为竖直。
	var target_ids: Array[int] = _get_unchained_other_target_ids()
	if target_ids.is_empty():
		return
	request_card_target_selection("铁壁", "请选择一张【闪】和一名其他角色", shan_candidates, target_ids, 1, 1, 1, 1, true, {"kind":"tiebi_cost_target"})


## 恢复铁壁费用与目标选择；任一条件失效时不弃牌、不横置也不授予技能。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "tiebi_cost_target" or response == null:
		return false
	if not response.confirmed or response.card_ids.size() != 1 or response.target_ids.size() != 1:
		return true
	# 当前目标ID；等待期间必须仍为其他存活、在场且竖置角色。
	# 当前通用术语不再要求竖置；保留的复核职责是确保目标仍为其他存活在场角色。
	# 当前目标ID；等待期间必须仍为其他存活在场角色，横置状态变化不取消本次合法选择。
	var target_id: int = response.target_ids[0]
	if not _get_unchained_other_target_ids().has(target_id):
		return true
	# 当前费用UID；等待期间必须仍为普通手牌区中的【闪】。
	var shan_uid: int = response.card_ids[0]
	if not _is_hand_shan(shan_uid) or not bool(host.call("discard_card_from_hand", owner_player_id, shan_uid)):
		return true
	# 横置状态切换；竖置目标变为横置，已经横置的目标再次横置则恢复竖直。
	host.call("toggle_player_linked", target_id, owner_player_id, get_id())
	# 到期轮数；下一次新轮roundStart触发前移除，完整覆盖当前轮剩余时间。
	var expires_at_round: int = host.state.round_number + 1
	if bool(host.call("grant_temporary_skill", target_id, GRANTED_SKILL_ID, expires_at_round)):
		announce_activation({"card_uid":shan_uid, "target_id":target_id, "granted_skill_id":GRANTED_SKILL_ID, "expires_at_round":expires_at_round})
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


## 判断指定UID当前是否仍为持有者普通手牌区中的【闪】。
func _is_hand_shan(card_uid: int) -> bool:
	# 技能持有者；无效时费用不成立。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 当前普通手牌实体；木牛“粮”不会由find_hand_card返回。
	var card: CardInstance = owner.find_hand_card(card_uid) if owner != null else null
	return card != null and card.definition_id == "shan"


## 返回当前全部未横置的其他存活在场角色。
## 为兼容既有技能私有接口保留函数名；实际返回全部其他存活在场角色，不再排除已经横置者。
func _get_unchained_other_target_ids() -> Array[int]:
	# 目标结果；沿用座次顺序保证UI、AI与回放稳定。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game:
			result.append(player.player_id)
	return result


## AI为友方横置并授予黑杀免疫；只有保护收益超过横置风险与弃闪成本时才确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非铁壁组合选择不改变通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "tiebi_cost_target":
		return 0.0
	# 取消动作保持0分；确认动作必须提供一张牌和一个目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；友方态度越高，临时防护价值越高。
	var target_ids: Array = payload.get("selected_target_ids", []) as Array
	if target_ids.size() != 1:
		return -20.0
	# 当前目标ID；用于读取其横置状态并评估本次切换方向。
	var target_id: int = int(target_ids[0])
	# 当前目标快照；已横置友方被再次横置会恢复竖直，未横置友方则承担连环风险。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	# 对目标态度；正值表示友方，负值表示敌方。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 横置切换价值；重置友方或横置敌方为正，横置友方或重置敌方为负。
	var link_state_value: float = attitude / 5.0 if bool(target.get("chained", false)) else -attitude / 5.0
	# 已选费用；【闪】具有较高防御价值，因此费用按通用持有牌价值扣除。
	var selected_card_uids: Array = payload.get("selected_card_uids", []) as Array
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(selected_card_uids[0])) if selected_card_uids.size() == 1 else 8.0
	return attitude * 1.2 - material_value * 0.55 + link_state_value
