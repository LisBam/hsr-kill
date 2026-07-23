extends CardDefinition

## 【八卦阵】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## 红色判定成功对响应角色的基础 AI 价值；供改判定技能按阵营决定是否保留红色牌在牌堆顶。
const AI_SUCCESS_RESULT_VALUE: float = 2.0


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "bagua",
		"original_name": "八卦阵",
		"custom_name": "穷观阵",
		"type": "equipment",
		"subtype": "armor",
		"effect_id": "equip",
		"slot": "armor",
		"attack_range": 0,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "需要使用或打出【闪】时，可判定；若结果为红色，视为使用或打出一张【闪】。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":7.5, "equip_value":7.5, "response":true},
		"ai_use_value": 5.0,
	})


## 执行【八卦阵】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 八卦阵在需要响应【闪】时提供装备发动入口，不需要额外手牌材料。
func can_offer_equipment_response(match_host: Object, player_id: int, response_patterns: Array[String]) -> bool:
	return response_patterns.has("shan")


## 八卦阵必须在需要使用或打出【闪】的时机优先独立询问，取消或判定失败后才进入普通响应牌选择。
func uses_immediate_equipment_response_prompt() -> bool:
	return true


## 返回八卦阵的独立发动询问；提示只表达是否发动，不混入后续手牌响应说明。
func get_immediate_equipment_response_prompt() -> String:
	return "是否发动【八卦阵】？"


## 选择八卦阵后执行判定；红色视为打出虚拟【闪】，黑色表示响应失败。
func consume_equipment_response(match_host: Object, player_id: int, equipment_uid: int, response_patterns: Array[String], material_card_uids: Array[int], response_context: Dictionary = {}) -> CardInstance:
	if not response_patterns.has("shan"):
		return null
	# 当前八卦阵实体；等待期间换装时旧入口失效。
	var equipment_card: CardInstance = match_host.get_equipment_card(player_id, "armor")
	if equipment_card == null or equipment_card.definition_id != get_id() or equipment_card.uid != equipment_uid:
		return null
	match_host.record_equipment_activation(player_id, get_id())
	# 八卦阵判定牌；只有红色结果视为成功响应【闪】。
	# 异步判定接收上下文；原响应请求完整保留，判定失败后才能排除八卦阵并重开其余【闪】候选。
	var judgment_continuation: Dictionary = {
		"receiver_type":"card",
		"card_definition_id":get_id(),
		"context":{
			"kind":"bagua_response_judgment",
			"player_id":player_id,
			"equipment_uid":equipment_uid,
			"response_context":response_context.duplicate(true),
		},
	}
	# 判定 AI 上下文；红色对响应者有利，黑色不利，改判定角色可结合阵营决定牌堆顶顺序。
	var judgment_ai_context: Dictionary = {
		"favorable_condition":{"colors":["red"]},
		"unfavorable_condition":{"colors":["black"]},
		"favorable_result_player_values":{str(player_id):AI_SUCCESS_RESULT_VALUE},
	}
	# 八卦阵判定牌；没有判定前交互时同步返回，出现【戏法】等选择时由 continue_judgment 恢复原响应。
	var judgment_card: CardInstance = match_host.request_judgment(player_id, "八卦阵", judgment_continuation, judgment_ai_context)
	if match_host.has_pending_judgment_request():
		return null
	return _build_bagua_response(match_host, player_id, judgment_card)


## 恢复曾被判定前技能暂停的八卦阵结果，并把成功或失败交回原响应流程。
func continue_judgment(match_host: Object, context: Dictionary, judgment_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "bagua_response_judgment":
		return false
	# 原响应上下文；包含父牌、响应者、排除列表与技能归属，核心据此恢复正确路线。
	var response_context: Dictionary = (context.get("response_context", {}) as Dictionary).duplicate(true)
	# 判定成功时生成虚拟【闪】，失败时保持 null 并让核心重新开放其余响应候选。
	var response_card: CardInstance = _build_bagua_response(match_host, int(context.get("player_id", -1)), judgment_card)
	match_host.continue_async_equipment_judgment_response(response_context, response_card, int(context.get("equipment_uid", -1)))
	return true


## 根据判定牌构造八卦阵的虚拟【闪】；非红色、取消判定或无效玩家均返回 null。
func _build_bagua_response(match_host: Object, player_id: int, judgment_card: CardInstance) -> CardInstance:
	if judgment_card == null or judgment_card.get_color() != "red":
		return null
	# 当前响应者；日志使用最新角色显示名，异常失效时不再伪造成功响应。
	var player: PlayerState = match_host.state.get_player(player_id)
	if player == null or not player.alive:
		return null
	match_host.add_log("%s的【八卦阵】判定为红色，视为打出【闪】。" % player.display_name)
	return CardInstance.new("shan", judgment_card.suit, judgment_card.rank)
