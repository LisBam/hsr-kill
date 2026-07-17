class_name PlayerAction
extends RefCounted

## 标准化玩家行为指令。人类 UI、内置 AI 与网络客户端必须通过同一结构向核心下发操作。

## 指令类型；支持选将、出牌、技能、重铸、装备动作、结束阶段和统一 choose_cards 牌/目标选择响应。
var action_type: String = ""

## 发出指令的玩家 ID；系统指令使用 -1。
var actor_id: int = -1

## 被操作的实体牌 UID；不涉及卡牌的指令使用 -1。
var card_uid: int = -1

## 目标玩家 ID 数组；保存选择语义，借刀杀人依赖先持刀者后被杀者，其余多目标由规则层按行动顺序规范化。
var target_ids: Array[int] = []

## 可扩展参数；只允许存放可序列化基础类型，禁止传入节点或 Callable。
var payload: Dictionary = {}

## 客户端生成的动作序号；联机层可用它去重，单机模式可保持0。
var client_sequence: int = 0


## 创建一条标准化行为指令；目标数组会被复制，避免调用方后续修改。
func _init(type: String = "", player_id: int = -1, entity_uid: int = -1, targets: Array[int] = []) -> void:
	action_type = type
	actor_id = player_id
	card_uid = entity_uid
	target_ids = targets.duplicate()


## 将指令序列化为网络消息或回放记录。
func to_dict() -> Dictionary:
	return {
		"action_type": action_type,
		"actor_id": actor_id,
		"card_uid": card_uid,
		"target_ids": target_ids.duplicate(),
		"payload": payload.duplicate(true),
		"client_sequence": client_sequence,
	}


## 从网络安全字典恢复行为指令；字段缺失时使用无效默认值并交由规则层拒绝。
static func from_dict(data: Dictionary) -> PlayerAction:
	# 新建的行为指令；所有字段在返回前按输入数据覆盖。
	var action: PlayerAction = PlayerAction.new()
	action.action_type = str(data.get("action_type", ""))
	action.actor_id = int(data.get("actor_id", -1))
	action.card_uid = int(data.get("card_uid", -1))
	# 输入目标数组；逐项转换为整数，避免 JSON 数字类型差异。
	var raw_targets: Array = data.get("target_ids", []) as Array
	for target_variant: Variant in raw_targets:
		action.target_ids.append(int(target_variant))
	action.payload = (data.get("payload", {}) as Dictionary).duplicate(true)
	action.client_sequence = int(data.get("client_sequence", 0))
	return action
