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
