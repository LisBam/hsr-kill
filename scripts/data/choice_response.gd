class_name ChoiceResponse
extends RefCounted

## 通用选择结果。UI、AI、网络托管与回放都提交同一结构，由 EventScheduler 进行请求归属和数量校验。

## 对应 ChoiceRequest 的稳定请求 ID；默认 -1 表示无效响应。
var request_id: int = -1

## 创建请求的事件 ID；用于拒绝旧事件残留结果和跨事件伪造响应。
var event_id: int = -1

## 实际作出选择的玩家 ID；必须与请求 actor_id 完全一致。
var actor_id: int = -1

## 是否确认当前选择；false 表示取消或放弃，强制请求通常不允许该值。
var confirmed: bool = false

## 所选实体牌 UID；顺序保留玩家操作语义，权威规则可在结算前再次规范化。
var card_ids: Array[int] = []

## 所选目标玩家 ID；顺序保留借刀杀人等具有位置语义的多目标选择。
var target_ids: Array[int] = []

## 所选按钮稳定 ID；技能按钮、五谷牌面按钮与其他候选统一使用字符串 ID。
var button_ids: Array[String] = []

## 所选控制项稳定 ID；单选控制没有结果时为空字符串。
var control_id: String = ""

## 客户端递增序号；网络层用于去重，离线 UI 与 AI 可以保持 0。
var client_sequence: int = 0

## 响应来源；可取 local、ai、network、timeout 或 replay，只用于审计，不改变规则结果。
var source: String = "local"


## 创建一个最小通用响应；复杂选择随后填写卡牌、目标、按钮或控制项数组。
func _init(choice_request_id: int = -1, owner_event_id: int = -1, responder_id: int = -1, is_confirmed: bool = false) -> void:
	request_id = choice_request_id
	event_id = owner_event_id
	actor_id = responder_id
	confirmed = is_confirmed


## 把响应转换为仅含基础类型的深拷贝字典，供通信、日志和回放长期保存。
func to_dict() -> Dictionary:
	return {
		"request_id": request_id,
		"event_id": event_id,
		"actor_id": actor_id,
		"confirmed": confirmed,
		"card_ids": card_ids.duplicate(),
		"target_ids": target_ids.duplicate(),
		"button_ids": button_ids.duplicate(),
		"control_id": control_id,
		"client_sequence": client_sequence,
		"source": source,
	}


## 从不可信字典恢复响应；所有数组逐项转换类型，最终合法性仍由权威 ChoiceRequest 校验。
static func from_dict(data: Dictionary) -> ChoiceResponse:
	# 新建响应；字段缺失时保持无效默认值，避免不完整消息意外命中当前请求。
	var response: ChoiceResponse = ChoiceResponse.new()
	response.request_id = int(data.get("request_id", -1))
	response.event_id = int(data.get("event_id", -1))
	response.actor_id = int(data.get("actor_id", -1))
	response.confirmed = bool(data.get("confirmed", false))
	for card_id_variant: Variant in data.get("card_ids", []) as Array:
		response.card_ids.append(int(card_id_variant))
	for target_id_variant: Variant in data.get("target_ids", []) as Array:
		response.target_ids.append(int(target_id_variant))
	for button_id_variant: Variant in data.get("button_ids", []) as Array:
		response.button_ids.append(str(button_id_variant))
	response.control_id = str(data.get("control_id", ""))
	response.client_sequence = int(data.get("client_sequence", 0))
	response.source = str(data.get("source", "network"))
	return response
