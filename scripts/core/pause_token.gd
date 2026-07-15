class_name PauseToken
extends RefCounted

## 可序列化暂停 token 数据类。PauseRegistry 内部仍集中管理生命周期，外部不直接释放 token。

## token 稳定 ID；0 表示未登记。
var token_id: int = 0

## 暂停通道；choice、network、animation、lifecycle 和 over 使用独立名称。
var channel: String = ""

## 所属事件 ID；-1 表示全局暂停。
var owner_event_id: int = -1

## 面向调试和回放的暂停原因。
var reason: String = ""

## 是否已经解决；解决后不能再次恢复事件。
var resolved: bool = false

## 解决结果文本；用于区分正常恢复、超时、断线托管和对局终止。
var resolution: String = ""


## 创建 token 数据对象；实际注册仍由 PauseRegistry.acquire 负责。
func _init(id: int = 0, token_channel: String = "", event_id: int = -1, token_reason: String = "") -> void:
	token_id = id
	channel = token_channel
	owner_event_id = event_id
	reason = token_reason


## 生成可写入暂停历史和网络调试器的基础字典。
func to_dict() -> Dictionary:
	return {"token_id":token_id, "channel":channel, "owner_event_id":owner_event_id, "reason":reason, "resolved":resolved, "resolution":resolution}
