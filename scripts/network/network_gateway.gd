class_name NetworkGateway
extends Node

## 通用对局通信网关。该组件封装离线回环、局域网 ENet 会话与远程适配器边界，不参与任何卡牌或胜负结算。

signal command_received(command_data: Dictionary)
signal snapshot_received(snapshot_data: Dictionary)
signal packet_ready_for_transport(packet: Dictionary)
signal connection_state_changed(connected: bool, message: String)

## 权威端选择请求接收信号；远端客户端收到裁剪后的选择字典后重建本地选择界面。
signal choice_request_received(request_data: Dictionary)

## 选择结果接收信号；权威端必须再校验 request_id、event_id、actor_id 和候选合法性。
signal choice_response_received(response_data: Dictionary)

## 局域网大厅状态变化信号；快照只包含成员显示名、主机标记、连接人数和是否已经开局。
signal lan_lobby_changed(lobby_snapshot: Dictionary)

## 局域网对局开始信号；客户端据此绑定自己的稳定玩家 ID，并在后续快照到达前关闭大厅。
signal lan_match_started(local_player_id: int, player_count: int)

## 局域网会话结束信号；客户端用于清理远端快照并返回主菜单，房主主动关闭时也会本地触发。
signal lan_session_closed(message: String)

## 对局中远端成员掉线信号；权威端可将对应稳定玩家 ID 交给 AI 托管，而不终止其他玩家的对局。
signal lan_match_peer_disconnected(player_id: int, display_name: String)

## 权威表现事件接收信号；日志、公开卡牌动画和技能提示通过该只读通道同步，不修改客户端规则状态。
signal game_event_received(event_type: String, event_payload: Dictionary)

## 通信模式；OFFLINE 本地回环，LAN 使用内置 ENet，REMOTE 交由外部传输适配器发送。
enum Mode {
	OFFLINE,
	LAN,
	REMOTE,
}

## 局域网会话角色；NONE 表示未连接，HOST 保存权威状态，CLIENT 只发送动作并消费裁剪快照。
enum LanRole {
	NONE,
	HOST,
	CLIENT,
}

## 当前封包协议版本；版本2使用 leader 身份值与 leader_player_id/leader_character_id 选将字段，不兼容旧 lord 字段。
const PROTOCOL_VERSION: int = 2

## Godot ENet 服务器固定使用的网络对等体 ID；客户端所有上行封包只能发送给该 ID。
const SERVER_PEER_ID: int = 1

## 标准身份局允许的最大总人数；局域网房间成员和 AI 补位总数都不能超过该值。
const MAX_MATCH_PLAYER_COUNT: int = 10

## 玩家显示名允许的最大 Unicode 字符数；默认20可保持大厅成员列表紧凑，运行时不应动态修改。
const MAX_DISPLAY_NAME_LENGTH: int = 20

## 局域网默认端口；7000避开系统保留端口并方便开发环境记忆，可在创建或加入房间时覆盖。
@export_range(1024, 65535, 1) var default_lan_port: int = 7000

## 局域网服务器允许的最大远端客户端数量；默认9与“1名房主+9名客户端=10人局”一致，运行时无需动态修改。
@export_range(1, 9, 1) var maximum_lan_clients: int = 9

## 当前通信模式；默认离线，创建或加入局域网房间时切换为 LAN。
var mode: Mode = Mode.OFFLINE

## 当前连接状态；离线模式始终视为已连接，LAN 客户端在 ENet 握手成功后变为 true。
var connected: bool = true

## 本地发送序号；每个封包递增，用于接收端去重，重新创建会话时归零。
var outgoing_sequence: int = 0

## 当前局域网角色；房主、客户端和未连接状态由此互斥表达。
var lan_role: LanRole = LanRole.NONE

## 当前 ENet 对等体；未建立局域网会话时为 null，离开会话后立即关闭并释放端口。
var _enet_peer: ENetMultiplayerPeer

## 本地大厅显示名；创建或加入房间时完成裁剪和空值回退，不写入全局账号数据。
var _local_display_name: String = "玩家"

## 当前大厅成员映射；键为 ENet peer_id，值为只含显示名、主机标记和加入序号的可序列化字典。
var _lobby_members: Dictionary = {}

## 已登记成员的加入序号；每接受一名客户端递增，确保成员列表不依赖字典遍历顺序。
var _join_sequence: int = 0

## 网络 peer_id 到稳定玩家 ID 的映射；仅房主在开局前随机生成，掉线时精确定位需要托管的角色。
var _peer_to_player_id: Dictionary = {}

## 稳定玩家 ID 到网络 peer_id 的反向映射；用于定向发送私有快照与选择请求。
var _player_to_peer_id: Dictionary = {}

## 稳定玩家 ID 到大厅显示名的映射；权威控制器创建 PlayerState 时读取，不依赖界面节点。
var _player_display_names: Dictionary = {}

## 每个远端 peer 最近一次已接收封包序号；小于或等于记录值的重复包会被静默丢弃。
var _last_incoming_sequence_by_peer: Dictionary = {}

## 当前正在同步分发封包的远端 peer_id；控制器可在 command_received 回调栈内读取以定向返回拒绝原因。
var _current_incoming_peer_id: int = 0

## 当前局域网房间是否已经进入对局；开局后拒绝新成员加入，已有成员掉线则交给规则层托管。
var _lan_match_active: bool = false

## 当前房间配置的对局总人数；包含所有真人成员与由房主补齐的 AI 座位，未开局时为0。
var _lan_match_player_count: int = 0


## 初始化 SceneMultiplayer 连接信号；网关不自动创建网络端口，必须由大厅入口显式调用。
func _ready() -> void:
	_bind_multiplayer_signals()


## 切换通信模式并重置连接状态；REMOTE 仍需要外部适配器随后确认连接。
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	connected = mode == Mode.OFFLINE
	connection_state_changed.emit(connected, "离线模式已就绪" if connected else "等待传输适配器连接")


## 创建局域网 ENet 房间；成功后本机成为大厅房主，返回值使用 Godot Error 枚举供 UI 显示稳定错误。
func host_lan(display_name: String, port: int = -1) -> Error:
	leave_lan("")
	_bind_multiplayer_signals()
	# 实际监听端口；无效输入回退检查器默认值，避免 ENet 接收越界端口。
	var resolved_port: int = default_lan_port if port < 0 else clampi(port, 1024, 65535)
	# 新 ENet 服务端；最大连接数只计算远端客户端，房主自身使用固定 peer_id=1。
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	# ENet 建服结果；端口占用或底层网络错误会原样返回，失败时不留下半连接模式。
	var create_error: Error = peer.create_server(resolved_port, maximum_lan_clients)
	if create_error != OK:
		_set_offline_state()
		connection_state_changed.emit(false, "创建局域网房间失败，端口可能已被占用。")
		return create_error
	_enet_peer = peer
	multiplayer.multiplayer_peer = _enet_peer
	mode = Mode.LAN
	lan_role = LanRole.HOST
	connected = true
	outgoing_sequence = 0
	_local_display_name = _sanitize_display_name(display_name)
	_lobby_members[SERVER_PEER_ID] = _make_lobby_member(SERVER_PEER_ID, _local_display_name, true, 0)
	connection_state_changed.emit(true, "局域网房间已创建，等待其他玩家加入。")
	_emit_lobby_state()
	return OK


## 加入指定局域网地址；连接过程异步完成，成功或失败通过 connection_state_changed 与 lan_session_closed 返回。
func join_lan(address: String, display_name: String, port: int = -1) -> Error:
	leave_lan("")
	_bind_multiplayer_signals()
	# 实际服务器地址；空值回退本机，便于同一设备启动两个实例进行开发测试。
	var resolved_address: String = address.strip_edges()
	if resolved_address.is_empty():
		resolved_address = "127.0.0.1"
	# 实际目标端口；限制到非系统保留端口范围，避免错误文本被直接交给 ENet。
	var resolved_port: int = default_lan_port if port < 0 else clampi(port, 1024, 65535)
	# 新 ENet 客户端；每次加入都使用独立实例，旧会话已在函数开头完整释放。
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	# ENet 客户端创建结果；这里只表示开始连接是否成功，最终握手结果由 SceneMultiplayer 信号通知。
	var create_error: Error = peer.create_client(resolved_address, resolved_port)
	if create_error != OK:
		_set_offline_state()
		connection_state_changed.emit(false, "无法发起局域网连接，请检查地址与端口。")
		return create_error
	_enet_peer = peer
	multiplayer.multiplayer_peer = _enet_peer
	mode = Mode.LAN
	lan_role = LanRole.CLIENT
	connected = false
	outgoing_sequence = 0
	_local_display_name = _sanitize_display_name(display_name)
	connection_state_changed.emit(false, "正在连接局域网房主……")
	return OK


## 主动离开当前局域网会话；房主调用会关闭房间，客户端调用只断开自身并恢复离线网关状态。
func leave_lan(message: String = "已离开局域网房间。") -> void:
	# 离开前角色；用于判断是否需要向本地界面报告一个真实会话关闭事件。
	var previous_role: LanRole = lan_role
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_offline_state()
	if previous_role != LanRole.NONE and not message.is_empty():
		connection_state_changed.emit(true, message)
		lan_session_closed.emit(message)


## 返回当前是否为已建立的局域网房主；仅该角色有权启动对局和发送权威快照。
func is_lan_host() -> bool:
	return mode == Mode.LAN and lan_role == LanRole.HOST and connected


## 返回当前是否为已连接的局域网客户端；客户端没有本地权威 GameState。
func is_lan_client() -> bool:
	return mode == Mode.LAN and lan_role == LanRole.CLIENT and connected


## 返回局域网房间是否已经进入对局；大厅阶段与游戏阶段共用同一 ENet 连接但权限不同。
func is_lan_match_active() -> bool:
	return _lan_match_active


## 返回当前正在投递命令的远端 peer_id；只能在 command_received 或 choice_response_received 同步回调内使用。
func get_current_incoming_peer_id() -> int:
	return _current_incoming_peer_id


## 返回当前大厅只读快照；成员按加入顺序排列，UI 不得修改返回数组或成员字典。
func get_lan_lobby_snapshot() -> Dictionary:
	# 成员 peer_id 列表；先按网络 ID 排序，再由稳定加入序号二次排序。
	var peer_ids: Array[int] = []
	for peer_id_variant: Variant in _lobby_members.keys():
		peer_ids.append(int(peer_id_variant))
	peer_ids.sort_custom(func(first_peer_id: int, second_peer_id: int) -> bool:
		# 第一个待比较成员；缺失时使用空字典并回退 peer_id，保证排序函数始终可执行。
		var first_member: Dictionary = _lobby_members.get(first_peer_id, {}) as Dictionary
		# 第二个待比较成员；与第一个成员采用相同回退规则，维持比较关系稳定。
		var second_member: Dictionary = _lobby_members.get(second_peer_id, {}) as Dictionary
		return int(first_member.get("join_order", first_peer_id)) < int(second_member.get("join_order", second_peer_id))
	)
	# 可序列化成员数组；深拷贝保证大厅组件不会反向修改网关成员表。
	var members: Array[Dictionary] = []
	for peer_id: int in peer_ids:
		members.append((_lobby_members.get(peer_id, {}) as Dictionary).duplicate(true))
	return {
		"role":LanRole.keys()[lan_role].to_lower(),
		"members":members,
		"member_count":members.size(),
		"match_active":_lan_match_active,
		"player_count":_lan_match_player_count,
	}


## 返回本机可用于局域网直连的 IPv4 地址；过滤回环、IPv6 与链路本地地址，空结果时回退127.0.0.1。
func get_lan_ipv4_addresses() -> Array[String]:
	# 可展示地址；逐项去重，避免多网络接口别名生成重复文本。
	var result: Array[String] = []
	for address_variant: Variant in IP.get_local_addresses():
		# 当前系统地址；仅保留点分十进制 IPv4。
		var address: String = str(address_variant)
		if not address.contains(".") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if not result.has(address):
			result.append(address)
	if result.is_empty():
		result.append("127.0.0.1")
	return result


## 房主在权威开局前随机绑定真人成员与稳定玩家 ID；空余 ID 由 MatchController 注册为 AI。
func prepare_lan_match_assignments(player_count: int) -> String:
	if not is_lan_host() or _lan_match_active:
		return "当前不是可开始对局的局域网房主。"
	# 已登记真人成员数；尚未发送显示名的半连接 peer 不进入正式座次。
	var human_count: int = _lobby_members.size()
	if human_count < 2:
		return "至少需要2名真人玩家才能开始局域网对局。"
	if player_count < human_count or player_count > MAX_MATCH_PLAYER_COUNT:
		return "游戏总人数必须介于当前真人数量与10人之间。"
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_player_display_names.clear()
	# 可分配稳定玩家 ID；使用独立随机源打乱，避免真人总是占据前几个稳定 ID。
	var available_player_ids: Array[int] = []
	for player_id: int in range(player_count):
		available_player_ids.append(player_id)
	# 座次随机源；只决定真人与稳定 ID 的绑定，身份、牌堆与选将仍由权威对局随机源独立记录。
	var assignment_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	assignment_rng.randomize()
	for index: int in range(available_player_ids.size() - 1, 0, -1):
		# 当前交换位置；Fisher-Yates 保证每个稳定玩家 ID 等概率分配给真人成员。
		var swap_index: int = assignment_rng.randi_range(0, index)
		# 当前索引原玩家 ID；交换期间暂存，修改仅影响本次随机座次结果。
		var temporary_player_id: int = available_player_ids[index]
		available_player_ids[index] = available_player_ids[swap_index]
		available_player_ids[swap_index] = temporary_player_id
	# 大厅成员顺序；房主与客户端均按稳定加入顺序消费随机后的玩家 ID，不依赖哈希顺序。
	var lobby_snapshot: Dictionary = get_lan_lobby_snapshot()
	# 大厅成员数组；成员顺序已经由快照固定，数量应与当前真人数量一致。
	var members: Array = lobby_snapshot.get("members", []) as Array
	for member_index: int in range(members.size()):
		# 当前大厅成员；显示名只用于权威玩家状态和日志，不参与网络权限判断。
		var member: Dictionary = members[member_index] as Dictionary
		# 当前成员网络连接 ID；用于建立连接到稳定玩家 ID 的权威映射。
		var peer_id: int = int(member.get("peer_id", 0))
		# 当前成员随机获得的稳定玩家 ID；对局期间不会因座次显示或掉线而改变。
		var player_id: int = available_player_ids[member_index]
		_peer_to_player_id[peer_id] = player_id
		_player_to_peer_id[player_id] = peer_id
		_player_display_names[player_id] = str(member.get("display_name", "玩家"))
	_lan_match_player_count = player_count
	return ""


## 房主在权威控制器成功创建对局后通知全部客户端绑定玩家 ID；此后新连接会被拒绝。
func begin_prepared_lan_match() -> void:
	if not is_lan_host() or _peer_to_player_id.is_empty() or _lan_match_player_count < 2:
		return
	_lan_match_active = true
	for peer_id_variant: Variant in _peer_to_player_id.keys():
		# 当前真人 peer；房主本地直接发出开始信号，远端通过可靠封包接收自己的私有玩家 ID。
		var peer_id: int = int(peer_id_variant)
		# 当前 peer 被分配的稳定玩家 ID；无效映射使用 -1 并由接收端拒绝开局数据。
		var assigned_player_id: int = int(_peer_to_player_id.get(peer_id, -1))
		if peer_id == SERVER_PEER_ID:
			lan_match_started.emit(assigned_player_id, _lan_match_player_count)
		else:
			_send_packet_to_peer(_build_packet("match_start", {"local_player_id":assigned_player_id, "player_count":_lan_match_player_count}), peer_id)
	_emit_lobby_state()


## 放弃尚未正式广播的座次映射；权威开局校验失败时调用，客户端仍停留在同一大厅中等待重试。
func cancel_prepared_lan_match() -> void:
	if _lan_match_active:
		return
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_player_display_names.clear()
	_lan_match_player_count = 0


## 返回房主本地绑定的稳定玩家 ID；未准备座次时返回 -1。
func get_local_lan_player_id() -> int:
	if lan_role == LanRole.HOST:
		return int(_peer_to_player_id.get(SERVER_PEER_ID, -1))
	return int(_peer_to_player_id.get(multiplayer.get_unique_id(), -1)) if multiplayer != null else -1


## 返回全部仍在线真人的稳定玩家 ID；掉线玩家会从映射中移除并由权威控制器接管为 AI。
func get_lan_human_player_ids() -> Array[int]:
	# 真人玩家结果；排序仅保证测试、日志和快照构建顺序稳定，不代表物理座次。
	var result: Array[int] = []
	for player_id_variant: Variant in _player_to_peer_id.keys():
		result.append(int(player_id_variant))
	result.sort()
	return result


## 返回指定稳定玩家 ID 对应的大厅显示名；不存在时回退标准座次名称。
func get_lan_player_display_name(player_id: int) -> String:
	return str(_player_display_names.get(player_id, "玩家%d" % (player_id + 1)))


## 返回指定稳定玩家 ID 对应的远端 peer_id；本地房主、AI 或已掉线玩家返回0或1供调用方自行区分。
func get_peer_id_for_player(player_id: int) -> int:
	return int(_player_to_peer_id.get(player_id, 0))


## 返回当前全部在线远端真人的“peer_id→player_id”副本；私有快照广播只遍历该结果。
func get_remote_player_assignments() -> Dictionary:
	# 远端映射副本；排除房主自身，调用方不能修改网关权限表。
	var result: Dictionary = {}
	for peer_id_variant: Variant in _peer_to_player_id.keys():
		# 当前映射中的网络 peer；房主 peer 会被排除，仅向调用方暴露远端真人。
		var peer_id: int = int(peer_id_variant)
		if peer_id != SERVER_PEER_ID:
			result[peer_id] = int(_peer_to_player_id.get(peer_id, -1))
	return result


## 发送标准化玩家指令。离线模式直接回环，LAN 客户端可靠上行至房主，REMOTE 交给外部适配器。
func send_command(action: PlayerAction) -> void:
	if action == null:
		return
	# 待发送封包；payload 仅含可序列化行为字典。
	var packet: Dictionary = _build_packet("command", action.to_dict())
	if mode == Mode.OFFLINE:
		command_received.emit(packet["payload"] as Dictionary)
	elif mode == Mode.LAN and lan_role == LanRole.CLIENT and connected:
		_send_packet_to_peer(packet, SERVER_PEER_ID)
	else:
		packet_ready_for_transport.emit(packet)


## 发送权威状态快照；离线模式回环，REMOTE 交给外部适配器，LAN 必须使用定向接口避免私有信息广播。
func send_snapshot(snapshot: Dictionary) -> void:
	# 待发送快照封包；payload 在构建时深拷贝，避免发送期间被核心修改。
	var packet: Dictionary = _build_packet("snapshot", snapshot)
	if mode == Mode.OFFLINE:
		snapshot_received.emit(packet["payload"] as Dictionary)
	elif mode == Mode.REMOTE:
		packet_ready_for_transport.emit(packet)


## 房主向一名远端玩家发送已经按其稳定玩家 ID 裁剪的私有快照；其他角色无法收到该 payload。
func send_snapshot_to_peer(snapshot: Dictionary, peer_id: int) -> void:
	if not is_lan_host() or not _lan_match_active or peer_id <= SERVER_PEER_ID:
		return
	_send_packet_to_peer(_build_packet("snapshot", snapshot), peer_id)


## 发送通用选择请求；离线模式直接回环，REMOTE 保留原适配器接口，LAN 业务使用带 UI 数据的定向方法。
func send_choice_request(request: ChoiceRequest) -> void:
	if request == null:
		return
	# 待发送选择请求封包；只包含 ChoiceRequest 的可序列化字段，不携带运行时回调。
	var packet: Dictionary = _build_packet("choice_request", request.to_dict())
	if mode == Mode.OFFLINE:
		choice_request_received.emit(packet["payload"] as Dictionary)
	elif mode == Mode.REMOTE:
		packet_ready_for_transport.emit(packet)


## 房主向实际选择者发送完整但仅属于该玩家的 UI 请求快照；候选牌面不得向其他 peer 广播。
func send_choice_request_to_peer(request_data: Dictionary, peer_id: int) -> void:
	if not is_lan_host() or not _lan_match_active or peer_id <= SERVER_PEER_ID:
		return
	_send_packet_to_peer(_build_packet("choice_request", request_data), peer_id)


## 发送通用选择响应；所有输入来源使用 ChoiceResponse，不上传或覆盖权威 GameState。
func send_choice_response(response: ChoiceResponse) -> void:
	if response == null:
		return
	# 待发送选择响应封包；由房主结合当前请求再次验证选择者、内容与时序。
	var packet: Dictionary = _build_packet("choice_response", response.to_dict())
	if mode == Mode.OFFLINE:
		choice_response_received.emit(packet["payload"] as Dictionary)
	elif mode == Mode.LAN and lan_role == LanRole.CLIENT and connected:
		_send_packet_to_peer(packet, SERVER_PEER_ID)
	else:
		packet_ready_for_transport.emit(packet)


## 房主向一名客户端发送只读表现或错误事件；事件类型由 MatchController 白名单分发。
func send_game_event_to_peer(event_type: String, event_payload: Dictionary, peer_id: int) -> void:
	if not is_lan_host() or not _lan_match_active or event_type.is_empty() or peer_id <= SERVER_PEER_ID:
		return
	_send_packet_to_peer(_build_packet("game_event", {"event_type":event_type, "event_payload":event_payload.duplicate(true)}), peer_id)


## 房主向全部在线远端真人广播同一只读表现事件；私有卡牌事件应由调用方逐观察者裁剪后使用定向接口。
func broadcast_game_event(event_type: String, event_payload: Dictionary) -> void:
	for peer_id_variant: Variant in get_remote_player_assignments().keys():
		send_game_event_to_peer(event_type, event_payload, int(peer_id_variant))


## 接收外部传输适配器交付的封包，并按消息类型分发到统一信号；LAN 内置 RPC 会额外执行发送者权限校验。
func receive_transport_packet(packet: Dictionary) -> void:
	_dispatch_game_packet(packet, 0)


## 构建带版本、模式与递增序号的通用消息封包。
func _build_packet(message_type: String, payload: Dictionary) -> Dictionary:
	outgoing_sequence += 1
	return {
		"protocol_version":PROTOCOL_VERSION,
		"message_type":message_type,
		"transport_mode":Mode.keys()[mode].to_lower(),
		"sequence":outgoing_sequence,
		"payload":payload.duplicate(true),
	}


## 绑定当前 SceneMultiplayer 的连接生命周期信号；重复调用保持幂等，便于测试重新挂载网关节点。
func _bind_multiplayer_signals() -> void:
	if multiplayer == null:
		return
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


## SceneMultiplayer 远端连接回调；开局中的房间立即拒绝新成员，大厅阶段等待其发送显示名登记包。
func _on_peer_connected(peer_id: int) -> void:
	if lan_role != LanRole.HOST:
		return
	if _lan_match_active:
		if _enet_peer != null:
			_enet_peer.disconnect_peer(peer_id)
		return
	connection_state_changed.emit(true, "检测到新玩家，正在登记大厅信息……")


## SceneMultiplayer 远端断开回调；大厅移除成员，对局中额外通知权威控制器接管对应角色。
func _on_peer_disconnected(peer_id: int) -> void:
	if lan_role != LanRole.HOST:
		return
	# 断开成员快照；先保存显示名和玩家 ID，再清理所有会话映射。
	var member: Dictionary = _lobby_members.get(peer_id, {}) as Dictionary
	# 断开成员显示名；成员资料缺失时使用通用名称，保证托管日志仍可读。
	var display_name: String = str(member.get("display_name", "远端玩家"))
	# 断开成员稳定玩家 ID；未进入对局或尚未分配时为 -1，不触发角色托管。
	var player_id: int = int(_peer_to_player_id.get(peer_id, -1))
	_lobby_members.erase(peer_id)
	_last_incoming_sequence_by_peer.erase(peer_id)
	_peer_to_player_id.erase(peer_id)
	if player_id >= 0:
		_player_to_peer_id.erase(player_id)
	if _lan_match_active and player_id >= 0:
		lan_match_peer_disconnected.emit(player_id, display_name)
	else:
		_emit_lobby_state()
	connection_state_changed.emit(true, "%s已离开房间。" % display_name)


## 客户端完成 ENet 握手后向房主发送显示名；房主确认大厅快照前仍显示连接中状态。
func _on_connected_to_server() -> void:
	if lan_role != LanRole.CLIENT:
		return
	connected = true
	connection_state_changed.emit(true, "已连接房主，正在进入大厅……")
	_send_packet_to_peer(_build_packet("lobby_join", {"display_name":_local_display_name}), SERVER_PEER_ID)


## 客户端连接失败回调；释放 ENet 资源并返回可重试的离线状态。
func _on_connection_failed() -> void:
	if lan_role != LanRole.CLIENT:
		return
	_enet_peer = null
	_set_offline_state()
	connection_state_changed.emit(false, "连接局域网房主失败，请检查 IP、端口和防火墙。")
	lan_session_closed.emit("连接局域网房主失败，请检查 IP、端口和防火墙。")


## 客户端失去房主回调；局域网模式不执行主机迁移，当前对局立即结束并返回主菜单。
func _on_server_disconnected() -> void:
	if lan_role != LanRole.CLIENT:
		return
	_enet_peer = null
	_set_offline_state()
	connection_state_changed.emit(false, "与局域网房主的连接已断开。")
	lan_session_closed.emit("与局域网房主的连接已断开。")


## Godot RPC 入口；所有 LAN 封包都从同一路径进入，发送者 ID 由 SceneMultiplayer 提供而不相信 payload 自报。
@rpc("any_peer", "call_remote", "reliable")
func _receive_packet_rpc(packet: Dictionary) -> void:
	# 实际发送者 peer_id；该值不能由客户端伪造，是玩家操作权限校验的根来源。
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	_receive_lan_packet(packet, sender_peer_id)


## 接收一个 LAN 封包并执行版本、模式、方向、序号与玩家归属校验。
func _receive_lan_packet(packet: Dictionary, sender_peer_id: int) -> void:
	if mode != Mode.LAN or sender_peer_id <= 0:
		return
	if int(packet.get("protocol_version", 0)) != PROTOCOL_VERSION or str(packet.get("transport_mode", "")) != "lan":
		return
	# 封包递增序号；可靠通道仍可能因重放或外部测试重复投递，旧序号必须幂等丢弃。
	var sequence: int = int(packet.get("sequence", 0))
	# 该发送者最近已处理序号；默认0使缺失或非正序号封包无法进入业务层。
	var last_sequence: int = int(_last_incoming_sequence_by_peer.get(sender_peer_id, 0))
	if sequence <= last_sequence:
		return
	_last_incoming_sequence_by_peer[sender_peer_id] = sequence
	# 消息类型；方向白名单阻止客户端伪造快照、开局通知或权威表现事件。
	var message_type: String = str(packet.get("message_type", ""))
	# 消息负载；深拷贝隔离 RPC 参数缓存，后续信号接收方只能修改自己的副本。
	var payload: Dictionary = (packet.get("payload", {}) as Dictionary).duplicate(true)
	if lan_role == LanRole.HOST:
		if message_type == "lobby_join":
			_register_lobby_member(sender_peer_id, str(payload.get("display_name", "玩家")))
			return
		if not _lan_match_active or not _peer_to_player_id.has(sender_peer_id):
			return
		if message_type in ["command", "choice_response"]:
			# 权威分配的玩家 ID；任何 actor_id 不匹配的封包都在进入 MatchController 前拒绝。
			var assigned_player_id: int = int(_peer_to_player_id.get(sender_peer_id, -1))
			if int(payload.get("actor_id", -1)) != assigned_player_id:
				send_game_event_to_peer("action_rejected", {"message":"网络操作玩家与当前连接绑定不一致。"}, sender_peer_id)
				return
			_current_incoming_peer_id = sender_peer_id
			if message_type == "command":
				command_received.emit(payload)
			else:
				choice_response_received.emit(payload)
			_current_incoming_peer_id = 0
		return
	if lan_role == LanRole.CLIENT:
		if sender_peer_id != SERVER_PEER_ID:
			return
		if message_type == "lobby_state":
			_apply_remote_lobby_state(payload)
		elif message_type == "match_start":
			_apply_remote_match_start(payload)
		elif message_type == "snapshot" and _lan_match_active:
			snapshot_received.emit(payload)
		elif message_type == "choice_request" and _lan_match_active:
			choice_request_received.emit(payload)
		elif message_type == "game_event" and _lan_match_active:
			game_event_received.emit(str(payload.get("event_type", "")), (payload.get("event_payload", {}) as Dictionary).duplicate(true))


## 分发离线回环或外部 REMOTE 适配器封包；仅处理游戏协议消息，不处理 LAN 大厅控制消息。
func _dispatch_game_packet(packet: Dictionary, sender_peer_id: int) -> void:
	if int(packet.get("protocol_version", 0)) != PROTOCOL_VERSION:
		return
	# 封包消息类型；决定 payload 的解析入口。
	var message_type: String = str(packet.get("message_type", ""))
	# 封包负载；在分发前深拷贝，隔离传输层缓存。
	var payload: Dictionary = (packet.get("payload", {}) as Dictionary).duplicate(true)
	_current_incoming_peer_id = sender_peer_id
	if message_type == "command":
		command_received.emit(payload)
	elif message_type == "snapshot":
		snapshot_received.emit(payload)
	elif message_type == "choice_request":
		choice_request_received.emit(payload)
	elif message_type == "choice_response":
		choice_response_received.emit(payload)
	elif message_type == "game_event":
		game_event_received.emit(str(payload.get("event_type", "")), (payload.get("event_payload", {}) as Dictionary).duplicate(true))
	_current_incoming_peer_id = 0


## 向指定 ENet peer 可靠发送一个协议封包；网络角色和连接状态必须已经由上层方法验证。
func _send_packet_to_peer(packet: Dictionary, peer_id: int) -> void:
	if mode != Mode.LAN or _enet_peer == null or peer_id <= 0:
		return
	rpc_id(peer_id, "_receive_packet_rpc", packet.duplicate(true))


## 登记客户端大厅显示名并广播最新成员表；重复登记只更新显示名，不改变稳定加入顺序。
func _register_lobby_member(peer_id: int, display_name: String) -> void:
	if lan_role != LanRole.HOST or _lan_match_active or peer_id <= SERVER_PEER_ID:
		return
	# 已有成员；同一连接重复发送 hello 时保留原加入顺序，避免列表位置闪动。
	var existing_member: Dictionary = _lobby_members.get(peer_id, {}) as Dictionary
	# 已有加入序号；-1表示首次登记，需要分配新的单调递增序号。
	var join_order: int = int(existing_member.get("join_order", -1))
	if join_order < 0:
		_join_sequence += 1
		join_order = _join_sequence
	_lobby_members[peer_id] = _make_lobby_member(peer_id, _sanitize_display_name(display_name), false, join_order)
	connection_state_changed.emit(true, "%s已加入房间。" % str((_lobby_members[peer_id] as Dictionary).get("display_name", "玩家")))
	_emit_lobby_state()


## 广播最新大厅快照；房主本地直接发信号，客户端通过可靠定向封包接收同一公共成员表。
func _emit_lobby_state() -> void:
	if lan_role != LanRole.HOST:
		return
	# 当前公共大厅快照；不包含玩家座次映射、身份、牌堆或任何私有对局数据。
	var snapshot: Dictionary = get_lan_lobby_snapshot()
	# 先向远端发送本次不可变快照，再通知本地 UI；本地回调即使同步开始对局，也不会让旧大厅快照获得更高封包序号覆盖新状态。
	for peer_id_variant: Variant in _lobby_members.keys():
		# 当前大厅成员 peer；房主自身由本地信号更新，不通过 RPC 回送。
		var peer_id: int = int(peer_id_variant)
		if peer_id != SERVER_PEER_ID:
			_send_packet_to_peer(_build_packet("lobby_state", snapshot), peer_id)
	lan_lobby_changed.emit(snapshot.duplicate(true))


## 客户端应用房主大厅快照；成员表在本地重建，只用于 UI 展示和开局人数下限。
func _apply_remote_lobby_state(snapshot: Dictionary) -> void:
	_lobby_members.clear()
	for member_variant: Variant in snapshot.get("members", []) as Array:
		# 当前公共成员；按房主发送的稳定 peer_id 建立本地只读索引。
		var member: Dictionary = (member_variant as Dictionary).duplicate(true)
		_lobby_members[int(member.get("peer_id", 0))] = member
	_lan_match_player_count = int(snapshot.get("player_count", 0))
	_lan_match_active = bool(snapshot.get("match_active", false))
	connected = true
	lan_lobby_changed.emit(get_lan_lobby_snapshot())
	connection_state_changed.emit(true, "已进入局域网房间。")


## 客户端应用房主开局通知；只保存自身玩家映射，不接收其他玩家与 peer 的对应关系。
func _apply_remote_match_start(payload: Dictionary) -> void:
	# 本地稳定玩家 ID；房主已随机分配，客户端后续所有动作必须使用该值。
	var local_player_id: int = int(payload.get("local_player_id", -1))
	# 对局总人数；用于场景布局与基础合法范围检查，不代表大厅真人数量。
	var player_count: int = clampi(int(payload.get("player_count", 0)), 2, MAX_MATCH_PLAYER_COUNT)
	if local_player_id < 0 or local_player_id >= player_count:
		return
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	# 客户端自己的 peer_id；仅保存本地映射，避免房主向客户端泄漏其他连接标识。
	var local_peer_id: int = multiplayer.get_unique_id()
	_peer_to_player_id[local_peer_id] = local_player_id
	_player_to_peer_id[local_player_id] = local_peer_id
	_player_display_names[local_player_id] = _local_display_name
	_lan_match_player_count = player_count
	_lan_match_active = true
	lan_match_started.emit(local_player_id, player_count)


## 创建单个可序列化大厅成员；显示名已经由调用方标准化，加入序号只影响公共列表顺序。
func _make_lobby_member(peer_id: int, display_name: String, is_host: bool, join_order: int) -> Dictionary:
	return {
		"peer_id":peer_id,
		"display_name":display_name,
		"is_host":is_host,
		"join_order":join_order,
	}


## 标准化玩家显示名；移除首尾空白、限制长度，并为空值提供稳定“玩家”回退。
func _sanitize_display_name(display_name: String) -> String:
	# 去除首尾空白后的名称；内部空格保留，允许玩家使用自然昵称。
	var sanitized_name: String = display_name.strip_edges()
	if sanitized_name.is_empty():
		sanitized_name = "玩家"
	if sanitized_name.length() > MAX_DISPLAY_NAME_LENGTH:
		sanitized_name = sanitized_name.left(MAX_DISPLAY_NAME_LENGTH)
	return sanitized_name


## 清理全部 LAN 会话状态并恢复离线回环；该函数不发信号，由具体生命周期入口决定用户提示。
func _set_offline_state() -> void:
	mode = Mode.OFFLINE
	lan_role = LanRole.NONE
	connected = true
	outgoing_sequence = 0
	_lobby_members.clear()
	_join_sequence = 0
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_player_display_names.clear()
	_last_incoming_sequence_by_peer.clear()
	_current_incoming_peer_id = 0
	_lan_match_active = false
	_lan_match_player_count = 0
