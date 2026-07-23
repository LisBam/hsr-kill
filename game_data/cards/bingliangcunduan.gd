extends CardDefinition

## 【兵粮寸断】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## 保留摸牌阶段对判定角色的基础 AI 价值；供改判定技能按阵营选择梅花或非梅花结果。
const AI_SAFE_RESULT_VALUE: float = 3.0


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "bingliang",
		"original_name": "兵粮寸断",
		"custom_name": "兵粮寸断",
		"type": "trick",
		"subtype": "delayed",
		"effect_id": "skip_draw",
		"nature": "normal",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "one",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": true,
		"description": "判定结果不为梅花时，跳过摸牌阶段。",
		"resolution_mode": "whole",
		"final_zone": "judgment",
		"provided_response_pattern": "",
		"ai": {"order":1.0, "value":4.0, "target_result":-2.7, "skip_draw":true},
		"ai_target_attitude": "hostile",
	})


## 执行【兵粮寸断】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	resolver.host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 结算【兵粮寸断】判定；未被无懈抵消且结果不为梅花时跳过本回合摸牌阶段。
func resolve_delayed_judgment(match_host: Object, player_id: int, card: CardInstance, negated: bool) -> void:
	if negated:
		match_host.discard_delayed_card(card)
		return
	# 【兵粮寸断】判定牌；梅花表示通过，其他三种花色均记录跳过摸牌阶段。
	# 判定恢复上下文；延时牌 UID 用于等待期间确认原牌仍位于处理区。
	var continuation: Dictionary = {"receiver_type":"card", "card_definition_id":get_id(), "context":{"kind":"bingliang_delayed_judgment", "player_id":player_id, "delayed_card_uid":card.uid}}
	# 梅花令目标保留摸牌阶段，属于目标角色的有利结果；其余花色为不利结果。
	var judgment_ai_context: Dictionary = {"favorable_condition":{"suits":["club"]}, "unfavorable_condition":{"not":{"suits":["club"]}}, "favorable_result_player_values":{str(player_id):AI_SAFE_RESULT_VALUE}}
	# 【兵粮寸断】判定牌；判定前存在选择时由 continue_judgment 恢复，不提前移动原延时牌。
	var judgment_card: CardInstance = match_host.request_judgment(player_id, "【兵粮寸断】", continuation, judgment_ai_context)
	if match_host.has_pending_judgment_request():
		return
	_apply_delayed_result(match_host, player_id, card, judgment_card)


## 恢复【兵粮寸断】异步判定，并在原延时牌仍有效时应用跳过阶段与弃置结果。
func continue_judgment(match_host: Object, context: Dictionary, judgment_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "bingliang_delayed_judgment":
		return false
	# 原延时牌；等待期间已经离开处理区时旧判定结果不再修改阶段。
	var delayed_card: CardInstance = _find_processing_card(match_host, int(context.get("delayed_card_uid", -1)))
	if delayed_card != null:
		_apply_delayed_result(match_host, int(context.get("player_id", -1)), delayed_card, judgment_card)
	return true


## 应用【兵粮寸断】最终判定；非梅花时跳过摸牌阶段，之后原延时牌进入弃牌堆。
func _apply_delayed_result(match_host: Object, player_id: int, card: CardInstance, judgment_card: CardInstance) -> void:
	if judgment_card != null and judgment_card.suit != "club":
		match_host.mark_player_phase_skipped(player_id, "draw")
	match_host.discard_delayed_card(card)


## 按 UID 查找仍在公共处理区的原延时牌；异步恢复不依赖同名牌或数组位置。
func _find_processing_card(match_host: Object, card_uid: int) -> CardInstance:
	for processing_card: CardInstance in match_host.state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	return null
