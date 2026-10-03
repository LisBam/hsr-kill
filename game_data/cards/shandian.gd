extends CardDefinition

## 【闪电】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## 避免黑桃2至9伤害对判定角色的基础 AI 价值；供改判定技能按阵营选择安全或命中结果。
const AI_SAFE_RESULT_VALUE: float = 6.0


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "shandian",
		"original_name": "闪电",
		"custom_name": "天谴",
		"type": "trick",
		"subtype": "delayed",
		"effect_id": "lightning",
		"nature": "thunder",
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": true,
		"is_damage": true,
		"description": "判定结果为黑桃2至9时受到3点无来源雷电伤害，否则移动到下一名合法角色的判定区。",
		"resolution_mode": "whole",
		"final_zone": "judgment",
		"provided_response_pattern": "",
		"ai": {"order":1.0, "value":0.0, "target_result":-1.0, "damage":true, "thunder_damage":true, "nature_damage":true},
	})


## 执行【闪电】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	resolver.host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 依据身份局势修正【闪电】的使用价值；优势方通常不愿引入随机伤害，劣势方与内奸更愿意制造变量。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 使用者 ID；闪电只能置入自己的判定区。
	var actor_id: int = int(action.get("actor_id", -1))
	# 使用者状态；身份决定局势方向偏好。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return current_score
	# 领忠方局势；正值领忠优势，负值反贼优势。
	var situation: int = evaluator.get_situation(authoritative_snapshot)
	# 使用者身份；内奸始终偏好适度随机性，其他阵营仅在自身阵营明显劣势时使用。
	var identity: String = str(actor.get("identity", ""))
	if identity == "renegade":
		return 1.0
	if identity == "rebel":
		return 1.0 if situation > 1 else -1.0
	if identity in ["leader", "loyalist"]:
		return 1.0 if situation < -1 else -1.0
	return current_score


## 结算【闪电】判定；黑桃2至9造成3点无来源雷电伤害，否则向下一名无闪电角色传递。
func resolve_delayed_judgment(match_host: Object, player_id: int, card: CardInstance, negated: bool) -> void:
	if negated:
		match_host.pass_delayed_card(player_id, card)
		return
	# 【闪电】判定牌；只有黑桃2至9命中，其他结果均执行传递。
	# 判定恢复上下文；延时牌 UID 用于等待期间确认原牌仍位于处理区。
	var continuation: Dictionary = {"receiver_type":"card", "card_definition_id":get_id(), "context":{"kind":"shandian_delayed_judgment", "player_id":player_id, "delayed_card_uid":card.uid}}
	# 非黑桃2至9属于目标角色的有利安全结果；命中区间为造成3点雷电伤害的不利结果。
	var harmful_condition: Dictionary = {"suits":["spade"], "rank_min":2, "rank_max":9}
	# 判定 AI 上下文；递归 not 条件允许通用改判定 AI 直接识别安全结果。
	var judgment_ai_context: Dictionary = {"favorable_condition":{"not":harmful_condition.duplicate(true)}, "unfavorable_condition":harmful_condition, "favorable_result_player_values":{str(player_id):AI_SAFE_RESULT_VALUE}}
	# 【闪电】判定牌；判定前存在选择时由 continue_judgment 恢复，不提前传递原延时牌。
	var judgment_card: CardInstance = match_host.request_judgment(player_id, "【闪电】", continuation, judgment_ai_context)
	if match_host.has_pending_judgment_request():
		return
	_apply_delayed_result(match_host, player_id, card, judgment_card)


## 恢复【闪电】异步判定，并在原延时牌仍有效时应用伤害或传递结果。
func continue_judgment(match_host: Object, context: Dictionary, judgment_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "shandian_delayed_judgment":
		return false
	# 原延时牌；等待期间已经离开处理区时旧判定结果不再造成伤害或传递。
	var delayed_card: CardInstance = _find_processing_card(match_host, int(context.get("delayed_card_uid", -1)))
	if delayed_card != null:
		_apply_delayed_result(match_host, int(context.get("player_id", -1)), delayed_card, judgment_card)
	return true


## 应用【闪电】最终判定；黑桃2至9造成3点无来源雷电伤害，其他或空结果均执行传递。
func _apply_delayed_result(match_host: Object, player_id: int, card: CardInstance, judgment_card: CardInstance) -> void:
	if judgment_card != null and judgment_card.suit == "spade" and judgment_card.rank >= 2 and judgment_card.rank <= 9:
		match_host.discard_delayed_card(card)
		match_host.damage(-1, player_id, 3, "thunder", "shandian")
	else:
		match_host.pass_delayed_card(player_id, card)


## 按 UID 查找仍在公共处理区的原延时牌；异步恢复不依赖同名牌或数组位置。
func _find_processing_card(match_host: Object, card_uid: int) -> CardInstance:
	for processing_card: CardInstance in match_host.state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	return null
