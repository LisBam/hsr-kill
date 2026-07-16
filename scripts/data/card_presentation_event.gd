class_name CardPresentationEvent
extends RefCounted

## 可序列化的牌面表现事件。规则层只描述牌、来源、目标与后续移牌所有权，界面自行决定具体动画。

## 本次表现的稳定递增编号；每局从1开始，用于调试、回放和客户端去重。
var presentation_id: int = -1

## 关联规则事件 ID；使用牌、展示牌和判定牌分别关联各自父事件，无上下文时为-1。
var event_id: int = -1

## 对应无名杀事件名称；当前支持 useCard、showCards 和 judge，扩展表现应使用新的稳定名称。
var event_name: String = ""

## 被展示实体牌的只读快照；包含 UID、定义、花色、点数和发出表现时的权威区域。
var card_data: Dictionary = {}

## 牌面表现的来源玩家 ID；公共牌没有自然来源时使用-1。
var actor_id: int = -1

## 本次使用牌指定的目标玩家 ID 数组；纯展示与判定通常为空数组。
var target_ids: Array[int] = []

## 表现开始时的权威来源区域；用于区分真实处理区牌与仍留在手牌区的纯展示副本。
var source_zone: String = ""

## 是否由本次表现接管该实体随后进入弃牌堆的动画；纯展示必须为false，防止吞掉未来真实弃牌表现。
var owns_discard_transfer: bool = false


## 创建一条牌面表现数据；所有集合均复制，调用方后续修改目标或牌快照不会污染已发出的事件。
func _init(presentation_sequence: int = -1, related_event_id: int = -1, related_event_name: String = "", serialized_card: Dictionary = {}, source_actor_id: int = -1, related_target_ids: Array[int] = [], discard_transfer_owned: bool = false) -> void:
	presentation_id = presentation_sequence
	event_id = related_event_id
	event_name = related_event_name
	card_data = serialized_card.duplicate(true)
	actor_id = source_actor_id
	target_ids = related_target_ids.duplicate()
	source_zone = str(card_data.get("zone", ""))
	owns_discard_transfer = discard_transfer_owned


## 返回网络、回放与界面均可安全消费的深拷贝字典，不暴露 CardInstance 或 GameEvent 引用。
func to_dict() -> Dictionary:
	return {
		"presentation_id":presentation_id,
		"event_id":event_id,
		"event_name":event_name,
		"card_data":card_data.duplicate(true),
		"actor_id":actor_id,
		"target_ids":target_ids.duplicate(),
		"source_zone":source_zone,
		"owns_discard_transfer":owns_discard_transfer,
	}
