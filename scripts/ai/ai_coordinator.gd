class_name AICoordinator
extends Node

## AI 调度层。它管理玩家到策略的映射，但不掌握回合推进、规则校验或卡牌结算。

## 以玩家 ID 为键的 AI 策略实例；未登记的玩家由人类或网络客户端控制。
var _policies: Dictionary = {}


## 为指定玩家安装基础策略；后续可传入实现相同 choose_action 接口的自定义策略。
func register_basic_ai(player_id: int) -> void:
	_policies[player_id] = BasicAIPolicy.new(player_id)


## 移除指定玩家的 AI 控制权，通常在玩家接管或断线重连时调用。
func unregister_ai(player_id: int) -> void:
	_policies.erase(player_id)


## 返回指定玩家是否由内置 AI 控制。
func is_ai_controlled(player_id: int) -> bool:
	return _policies.has(player_id)


## 请求 AI 从合法动作中选择一项；始终返回可序列化字典。
func request_action(player_id: int, authoritative_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	# 指定玩家的策略对象；不存在时直接返回结束阶段，避免核心停滞。
	var policy: BasicAIPolicy = _policies.get(player_id) as BasicAIPolicy
	if policy == null:
		return {"action_type": "end_play", "actor_id": player_id}
	return policy.choose_action(authoritative_snapshot, legal_actions)


## 把规则层选择请求交给对应 AI 策略；返回值仍是标准 PlayerAction 字典并需由控制器再次校验。
func request_card_choice(player_id: int, authoritative_snapshot: Dictionary, choice_request: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	# 指定玩家策略；不存在策略表示该玩家应由本地或网络界面响应，不能替其作出选择。
	var policy: BasicAIPolicy = _policies.get(player_id) as BasicAIPolicy
	if policy == null:
		return {}
	return policy.choose_card_choice(authoritative_snapshot, choice_request, legal_actions)


## 把通用 ChoiceRequest 交给 AI，并把策略的兼容动作结果转换为标准 ChoiceResponse。
func request_choice(player_id: int, authoritative_snapshot: Dictionary, request: ChoiceRequest, presentation_request: Dictionary, legal_actions: Array[Dictionary]) -> ChoiceResponse:
	if request == null:
		return null
	var action_data: Dictionary = request_card_choice(player_id, authoritative_snapshot, presentation_request, legal_actions)
	if action_data.is_empty():
		return null
	var payload: Dictionary = action_data.get("payload", {}) as Dictionary
	var response: ChoiceResponse = ChoiceResponse.new(request.request_id, request.event_id, player_id, true)
	for card_uid_variant: Variant in payload.get("selected_card_uids", []) as Array:
		response.card_ids.append(int(card_uid_variant))
	response.confirmed = not response.card_ids.is_empty() or request.min_count > 0
	response.client_sequence = int(action_data.get("client_sequence", 0))
	response.source = "ai"
	return response
