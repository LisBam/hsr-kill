class_name AICoordinator
extends Node

## AI 调度层。它管理玩家到策略的映射，但不掌握回合推进、规则校验或卡牌结算。

## 公开行为导致忠反推断变化时发出的只读通知；界面可刷新本地徽记，但不能据此写入权威身份。
signal identity_mark_changed(player_id: int, identity_mark: String)

## 以玩家 ID 为键的 AI 策略实例；未登记的玩家由人类或网络客户端控制。
var _policies: Dictionary = {}

## 全部基础 AI 共享的身份关系模型；同一公开行为对不同 AI 产生一致的身份暴露信息。
var _identity_model: IdentityAIModel = IdentityAIModel.new()


## 为指定玩家安装基础策略；后续可传入实现相同 choose_action 接口的自定义策略。
func register_basic_ai(player_id: int) -> void:
	_policies[player_id] = BasicAIPolicy.new(player_id, _identity_model)


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
	# AI 返回的标准动作数据；空字典表示该玩家没有可用策略或合法确认结果。
	var action_data: Dictionary = request_card_choice(player_id, authoritative_snapshot, presentation_request, legal_actions)
	if action_data.is_empty():
		return null
	# 动作负载；选择的实体牌、目标和确认状态均从统一 payload 恢复。
	var payload: Dictionary = action_data.get("payload", {}) as Dictionary
	# 标准选择响应；事件与请求 ID 保持原值，便于核心验证响应归属。
	var response: ChoiceResponse = ChoiceResponse.new(request.request_id, request.event_id, player_id, true)
	for card_uid_variant: Variant in payload.get("selected_card_uids", []) as Array:
		response.card_ids.append(int(card_uid_variant))
	for target_id_variant: Variant in payload.get("selected_target_ids", []) as Array:
		response.target_ids.append(int(target_id_variant))
	response.confirmed = bool(payload.get("confirmed", not response.card_ids.is_empty() or not response.target_ids.is_empty() or request.min_count > 0))
	response.client_sequence = int(action_data.get("client_sequence", 0))
	response.source = "ai"
	return response


## 向全部基础 AI 广播一次公开使用牌行为；只更新身份观察数据，不改变任何规则状态。
func observe_card_use(authoritative_snapshot: Dictionary, actor_id: int, card_definition: Dictionary, target_ids: Array[int]) -> void:
	# 行为前身份标记；观察完成后只在推断实际改变时通知表现层。
	var previous_identity_mark: String = _identity_model.get_identity_mark(actor_id)
	# 已通知策略对象；共享身份模型只需由任意一个基础策略更新一次，避免多名 AI 重复累计暴露度。
	var notified: bool = false
	for policy_variant: Variant in _policies.values():
		# 当前基础策略；未来自定义策略没有观察接口时安全跳过。
		var policy: BasicAIPolicy = policy_variant as BasicAIPolicy
		if policy != null:
			policy.observe_card_use(authoritative_snapshot, actor_id, card_definition, target_ids)
			notified = true
			break
	if not notified:
		# 没有内置 AI 的联机对局仍需记录公开行为，供本地自动身份标记使用；观察模型不会替玩家执行动作。
		_identity_model.observe_card_use(authoritative_snapshot, actor_id, card_definition, target_ids)
	# 行为后身份标记；只允许无名杀式模型产生的忠反临时标记进入通知。
	var current_identity_mark: String = _identity_model.get_identity_mark(actor_id)
	if current_identity_mark != previous_identity_mark:
		identity_mark_changed.emit(actor_id, current_identity_mark)


## 返回指定玩家当前由公开行为形成的忠反标记；空字符串表示线索不足，不公开真实隐藏身份。
func get_identity_mark(player_id: int) -> String:
	# 当前共享身份标记；协调器只暴露临时推断，不返回身份模型或可变观察字典。
	var identity_mark: String = _identity_model.get_identity_mark(player_id)
	return identity_mark if identity_mark in ["loyalist", "rebel"] else ""


## 返回指定 AI 是否愿意在当前奇偶状态使用【无懈可击】；未登记玩家保持保守不响应。
func should_negate(player_id: int, authoritative_snapshot: Dictionary, context: Dictionary) -> bool:
	# 指定玩家策略；人类和网络玩家必须自行提交选择，协调器不能替其决策。
	var policy: BasicAIPolicy = _policies.get(player_id) as BasicAIPolicy
	return policy.should_negate(authoritative_snapshot, context) if policy != null else false


## 为装备虚拟响应选择最低保留价值材料；返回值仍需由对应装备文件复核实体与数量。
func choose_low_value_card_uids(player_id: int, authoritative_snapshot: Dictionary, candidate_uids: Array[int], required_count: int) -> Array[int]:
	# 指定玩家策略；未登记 AI 时不替人类或网络玩家选择材料。
	var policy: BasicAIPolicy = _policies.get(player_id) as BasicAIPolicy
	return policy.choose_low_value_card_uids(authoritative_snapshot, candidate_uids, required_count) if policy != null else []


## 清空身份观察数据；开始新对局时可显式调用，快照 match_id 变化也会自动触发清理。
func reset_identity_observations() -> void:
	_identity_model.reset()
