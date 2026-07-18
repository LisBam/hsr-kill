class_name NetworkGateway
extends Node

## 通用对局通信网关。当前提供离线、局域网与远程模式分支及消息封装，不包含房间或匹配业务。

signal command_received(command_data: Dictionary)
signal snapshot_received(snapshot_data: Dictionary)
signal packet_ready_for_transport(packet: Dictionary)
signal connection_state_changed(connected: bool, message: String)

## 权威端选择请求接收信号；远端客户端收到裁剪后的 ChoiceRequest 字典后重建选择界面。
signal choice_request_received(request_data: Dictionary)

## 选择结果接收信号；权威端必须再校验 request_id、event_id、actor_id 和候选合法性。
signal choice_response_received(response_data: Dictionary)

## 通信模式；OFFLINE 本地回环，LAN 与 REMOTE 交由外部传输适配器发送。
enum Mode {
	OFFLINE,
	LAN,
	REMOTE,
}

## 当前封包协议版本；版本2使用 leader 身份值与 leader_player_id/leader_character_id 选将字段，不兼容旧 lord 字段。
const PROTOCOL_VERSION: int = 2

## 当前通信模式；默认离线，切换模式不会自动建立网络连接。
var mode: Mode = Mode.OFFLINE

## 当前连接状态；离线模式始终视为已连接。
var connected: bool = true

## 本地发送序号；每个封包递增，用于接收端去重与排序。
var outgoing_sequence: int = 0


## 切换通信模式并重置连接状态；LAN/REMOTE 需要外部适配器随后确认连接。
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	connected = mode == Mode.OFFLINE
	connection_state_changed.emit(connected, "离线模式已就绪" if connected else "等待传输适配器连接")


## 发送标准化玩家指令。离线模式直接回环，网络模式发出待传输封包信号。
func send_command(action: PlayerAction) -> void:
	# 待发送封包；payload 仅含可序列化行为字典。
	var packet: Dictionary = _build_packet("command", action.to_dict())
	if mode == Mode.OFFLINE:
		command_received.emit(packet["payload"] as Dictionary)
	else:
		packet_ready_for_transport.emit(packet)


## 发送权威状态快照；服务器或房主可按观察者裁剪私有数据后调用。
func send_snapshot(snapshot: Dictionary) -> void:
	# 待发送快照封包；payload 在构建时深拷贝，避免发送期间被核心修改。
	var packet: Dictionary = _build_packet("snapshot", snapshot)
	if mode == Mode.OFFLINE:
		snapshot_received.emit(packet["payload"] as Dictionary)
	else:
		packet_ready_for_transport.emit(packet)


## 发送通用选择请求；离线模式直接回环给本地适配器，联网模式交由传输层发送。
func send_choice_request(request: ChoiceRequest) -> void:
	if request == null:
		return
	var packet: Dictionary = _build_packet("choice_request", request.to_dict())
	if mode == Mode.OFFLINE:
		choice_request_received.emit(packet["payload"] as Dictionary)
	else:
		packet_ready_for_transport.emit(packet)


## 发送通用选择响应；所有输入来源使用 ChoiceResponse，不上传或覆盖权威 GameState。
func send_choice_response(response: ChoiceResponse) -> void:
	if response == null:
		return
	var packet: Dictionary = _build_packet("choice_response", response.to_dict())
	if mode == Mode.OFFLINE:
		choice_response_received.emit(packet["payload"] as Dictionary)
	else:
		packet_ready_for_transport.emit(packet)


## 接收外部传输适配器交付的封包，并按消息类型分发到统一信号。
func receive_transport_packet(packet: Dictionary) -> void:
	# 封包协议版本；只接收当前完整字段结构，旧版本必须由外部适配器显式迁移后再提交。
	var protocol_version: int = int(packet.get("protocol_version", 0))
	if protocol_version != PROTOCOL_VERSION:
		return
	# 封包消息类型；决定 payload 的解析入口。
	var message_type: String = str(packet.get("message_type", ""))
	# 封包负载；在分发前深拷贝，隔离传输层缓存。
	var payload: Dictionary = (packet.get("payload", {}) as Dictionary).duplicate(true)
	if message_type == "command":
		command_received.emit(payload)
	elif message_type == "snapshot":
		snapshot_received.emit(payload)
	elif message_type == "choice_request":
		choice_request_received.emit(payload)
	elif message_type == "choice_response":
		choice_response_received.emit(payload)


## 构建带版本、模式与递增序号的通用消息封包。
func _build_packet(message_type: String, payload: Dictionary) -> Dictionary:
	outgoing_sequence += 1
	return {
		"protocol_version":PROTOCOL_VERSION,
		"message_type": message_type,
		"transport_mode": Mode.keys()[mode].to_lower(),
		"sequence": outgoing_sequence,
		"payload": payload.duplicate(true),
	}
