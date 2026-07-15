class_name WuxieChainState
extends RefCounted

## 无懈可击交替链状态。它关联原卡牌事件、每次响应者与正负状态，不直接删除或取消原卡牌事件。

## 原锦囊根事件 ID；整个无懈链始终指向同一稳定事件。
var root_event_id: int = -1

## 当前被响应的来源事件 ID；无嵌套无懈时与 root_event_id 相同。
var source_event_id: int = -1

## 当前交替状态；1 表示原效果生效，-1 表示原效果被中立化，每次成功无懈乘以 -1。
var state: int = 1

## 按实际响应顺序保存玩家 ID；同一角色可以在后续轮次再次出现。
var responded_by: Array[int] = []

## 每次响应的可序列化 ChoiceResponse 或牌信息；用于回放实体材料牌和 respondTo 关系。
var response_results: Array[Dictionary] = []


## 创建一条无懈链并绑定原事件；source_event 默认与根事件一致。
func _init(root_id: int = -1, source_id: int = -1) -> void:
	root_event_id = root_id
	source_event_id = root_id if source_id < 0 else source_id


## 记录一次成功无懈并翻转状态；响应结果深拷贝，避免后续动作修改历史。
func add_response(player_id: int, response_result: Dictionary) -> int:
	state *= -1
	responded_by.append(player_id)
	response_results.append(response_result.duplicate(true))
	return state


## 返回原锦囊当前是否应被中立化；负状态表示奇数张无懈已经成功结算。
func is_neutralized() -> bool:
	return state < 0


## 生成可序列化链状态，供 CardUseEvent、网络和回放保存。
func to_dict() -> Dictionary:
	return {
		"root_event_id": root_event_id,
		"source_event_id": source_event_id,
		"state": state,
		"responded_by": responded_by.duplicate(),
		"response_results": response_results.duplicate(true),
	}
