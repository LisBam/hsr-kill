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

## 当前封包协议版本；版本5新增机缘大乱斗模式、私有机缘候选快照与机缘选择动作。
const PROTOCOL_VERSION: int = 5

## Godot ENet 服务器固定使用的网络对等体 ID；客户端所有上行封包只能发送给该 ID。
const SERVER_PEER_ID: int = 1

## 标准身份局允许的最大总人数；局域网房间成员和 AI 补位总数都不能超过该值。
const MAX_MATCH_PLAYER_COUNT: int = 10

## 玩家显示名允许的最大 Unicode 字符数；默认20可保持大厅成员列表紧凑，运行时不应动态修改。
const MAX_DISPLAY_NAME_LENGTH: int = 20

## 房间密码允许的最大 Unicode 字符数；默认32兼顾输入自由与大厅设置面板宽度，运行时不应动态修改。
const MAX_LOBBY_PASSWORD_LENGTH: int = 32

## 单条大厅聊天允许的最大 Unicode 字符数；默认200避免超长消息占满聊天区域或产生过大封包。
const MAX_LOBBY_CHAT_LENGTH: int = 200

## 大厅聊天历史保留上限；默认100条让后来加入者获得近期上下文，同时限制公共快照体积。
const MAX_LOBBY_CHAT_HISTORY: int = 100

## 房主踢出成员后的同一远端地址重新加入冷却毫秒数；默认5000即5秒，只限制踢出流程，不影响密码错误和满员拒绝。
const KICK_REJOIN_COOLDOWN_MSEC: int = 5000

## 当前可启动的默认游戏模式稳定 ID；大厅设置与开局协调只使用稳定 ID，不依赖中文显示名。
const DEFAULT_LOBBY_GAME_MODE_ID: String = "identity"

## 当前已实现的大厅游戏模式配置；后续新增真实规则模式时可追加稳定 ID 与玩家可见名称。
const LOBBY_GAME_MODE_OPTIONS: Array[Dictionary] = [
	{"id":DEFAULT_LOBBY_GAME_MODE_ID, "display_name":"身份模式"},
	{"id":"doudizhu", "display_name":"斗地主"},
	{"id":"team2v2", "display_name":"2v2"},
	{"id":"wheel_duel", "display_name":"1v1车轮战"},
	{"id":"opportunity_brawl", "display_name":"机缘大乱斗"},
]

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

## 本地大厅联机形象的稳定武将 ID；创建或加入时完成数据库校验，只用于大厅插画展示。
var _local_avatar_character_id: String = ""

## 客户端本次加入房间提交的密码；握手后随登记包发送，完成登记或离开会话后清空。
var _pending_lobby_password: String = ""

## 当前大厅成员映射；键为 ENet peer_id，值为显示名、形象、房主标记、加入序号与大厅位置组成的可序列化字典。
var _lobby_members: Dictionary = {}

## 当前房间密码；只保存在房主本机内存，不进入发送给客户端的公共大厅快照。
var _lobby_password: String = ""

## 当前大厅快照是否标记房间存在密码；客户端只保存布尔值，不能取得房主明文密码。
var _lobby_password_enabled: bool = false

## 当前大厅配置的游戏总人数；身份模式2至10，斗地主仅3或5，空座位在正式开局时由基础 AI 补齐。
var _lobby_player_count: int = 2

## 当前大厅配置的游戏模式稳定 ID；未知值统一回退身份模式，已实现 identity 与 doudizhu。
var _lobby_game_mode_id: String = DEFAULT_LOBBY_GAME_MODE_ID

## 当前大厅公共聊天历史；每项只含递增序号、玩家名、消息与显示时间，最多保留100条。
var _lobby_chat_history: Array[Dictionary] = []

## 当前大厅聊天消息递增序号；房主每接受一条非空消息增加1，用于跨客户端稳定排序。
var _lobby_chat_sequence: int = 0

## 已由房主主动拒绝且等待底层断开的 peer ID；断开回调据此跳过重复离开广播与通用提示。
var _rejected_lobby_peer_ids: Array[int] = []

## 被房主踢出的远端地址到冷却结束单调毫秒数映射；连接 peer ID 会在重连时变化，因此不能作为限制键。
var _kick_rejoin_expiry_msec_by_address: Dictionary = {}

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
	# 网络收发在规则弹窗暂停场景树时仍需继续轮询，保证联机玩家可以完成机缘等全体选择。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_multiplayer_signals()


## 切换通信模式并重置连接状态；REMOTE 仍需要外部适配器随后确认连接。
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	connected = mode == Mode.OFFLINE
	connection_state_changed.emit(connected, "离线模式已就绪" if connected else "等待传输适配器连接")


## 创建局域网 ENet 房间；成功后本机成为大厅房主，并应用联机形象、密码、人数与模式初始配置。
func host_lan(display_name: String, port: int = -1, avatar_character_id: String = "", room_password: String = "", player_count: int = 2, game_mode_id: String = DEFAULT_LOBBY_GAME_MODE_ID) -> Error:
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
	_local_avatar_character_id = _sanitize_avatar_character_id(avatar_character_id)
	_lobby_password = _sanitize_lobby_password(room_password)
	_lobby_password_enabled = not _lobby_password.is_empty()
	_lobby_game_mode_id = _normalize_lobby_game_mode_id(game_mode_id)
	_lobby_player_count = _normalize_lobby_player_count(player_count, _lobby_game_mode_id)
	_lobby_members[SERVER_PEER_ID] = _make_lobby_member(SERVER_PEER_ID, _local_display_name, _local_avatar_character_id, true, 0, 0)
	connection_state_changed.emit(true, "局域网房间已创建，等待其他玩家加入。")
	_emit_lobby_state()
	return OK


## 加入指定局域网地址；联机形象与密码在握手成功后随大厅登记包提交给房主校验。
func join_lan(address: String, display_name: String, port: int = -1, avatar_character_id: String = "", room_password: String = "") -> Error:
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
	_local_avatar_character_id = _sanitize_avatar_character_id(avatar_character_id)
	_pending_lobby_password = _sanitize_lobby_password(room_password)
	connection_state_changed.emit(false, "正在连接局域网房主……")
	return OK


## 主动离开当前局域网会话；房主调用会关闭房间，客户端调用只断开自身并恢复离线网关状态。
func leave_lan(message: String = "已离开局域网房间。") -> void:
	# 离开前角色；用于判断是否需要向本地界面报告一个真实会话关闭事件。
	var previous_role: LanRole = lan_role
	_release_lan_peer()
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


## 返回当前大厅只读快照；公共结果不含明文密码，房主本地可按参数额外取得密码用于设置面板。
func get_lan_lobby_snapshot(include_host_private_settings: bool = false) -> Dictionary:
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
	# 当前本机网络 peer ID；只帮助大厅界面区分本人、房主与可踢成员，不参与规则玩家 ID 分配。
	var local_peer_id: int = multiplayer.get_unique_id() if multiplayer != null else SERVER_PEER_ID
	# 当前可序列化大厅快照；聊天、座位和房间设置均为公开大厅信息，明文密码默认排除。
	var snapshot: Dictionary = {
		"role":LanRole.keys()[lan_role].to_lower(),
		"local_peer_id":local_peer_id,
		"members":members,
		"member_count":members.size(),
		"match_active":_lan_match_active,
		"player_count":_lan_match_player_count if _lan_match_active else _lobby_player_count,
		"game_mode_id":_lobby_game_mode_id,
		"has_password":_lobby_password_enabled,
		"chat_history":_lobby_chat_history.duplicate(true),
	}
	if include_host_private_settings and lan_role == LanRole.HOST:
		snapshot["room_password"] = _lobby_password
	return snapshot


## 房主更新大厅游戏模式、总人数与密码；人数不得少于当前真人数，成功后立即广播全员。
func update_lan_lobby_settings(game_mode_id: String, player_count: int, room_password: String) -> String:
	if not is_lan_host() or _lan_match_active:
		return "当前不是可修改设置的局域网房主。"
	# 规范化后的游戏模式 ID；当前未知模式回退身份模式，保证开始按钮不会请求不存在的规则。
	var normalized_game_mode_id: String = _normalize_lobby_game_mode_id(game_mode_id)
	# 按模式规范化人数；身份 2–10，斗地主仅 3/5，且不得少于当前真人数。
	var normalized_player_count: int = _normalize_lobby_player_count(player_count, normalized_game_mode_id)
	if normalized_player_count < _lobby_members.size():
		return "游戏总人数不能少于当前真人数量。"
	_lobby_game_mode_id = normalized_game_mode_id
	_lobby_player_count = normalized_player_count
	_lobby_password = _sanitize_lobby_password(room_password)
	_lobby_password_enabled = not _lobby_password.is_empty()
	_normalize_lobby_member_seats()
	_emit_lobby_state()
	return ""


## 请求把本地大厅成员移动到指定空位；房主直接校验，客户端向房主发送稳定座位索引。
func request_lan_lobby_seat_change(seat_index: int) -> void:
	if mode != Mode.LAN or _lan_match_active:
		return
	if lan_role == LanRole.HOST:
		_apply_lobby_seat_change(SERVER_PEER_ID, seat_index)
	elif lan_role == LanRole.CLIENT and connected:
		_send_packet_to_peer(_build_packet("lobby_seat", {"seat_index":seat_index}), SERVER_PEER_ID)


## 发送一条大厅聊天消息；房主直接写入公共历史，客户端可靠上行后由房主署名并广播。
func send_lan_lobby_chat_message(message: String) -> void:
	# 标准化后的聊天正文；空白消息不创建历史记录或网络封包。
	var sanitized_message: String = _sanitize_lobby_chat_message(message)
	if sanitized_message.is_empty() or mode != Mode.LAN or _lan_match_active:
		return
	if lan_role == LanRole.HOST:
		_append_lobby_chat_message(SERVER_PEER_ID, sanitized_message)
	elif lan_role == LanRole.CLIENT and connected:
		_send_packet_to_peer(_build_packet("lobby_chat", {"message":sanitized_message}), SERVER_PEER_ID)


## 房主踢出指定远端大厅成员；房主本人、未知成员和已开始对局中的成员均不能通过该入口移除。
func kick_lan_lobby_member(peer_id: int) -> String:
	if not is_lan_host() or _lan_match_active:
		return "当前不是可管理成员的局域网房主。"
	if peer_id <= SERVER_PEER_ID or not _lobby_members.has(peer_id):
		return "无法移除该大厅成员。"
	_reject_lobby_peer(peer_id, "你已被房主移出房间。", true)
	return ""


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


## 房主在权威开局前按大厅位置顺序绑定真人成员与稳定玩家 ID；空余 ID 由 MatchController 注册为 AI。
func prepare_lan_match_assignments(player_count: int) -> String:
	if not is_lan_host() or _lan_match_active:
		return "当前不是可开始对局的局域网房主。"
	# 已登记真人成员数；尚未发送显示名的半连接 peer 不进入正式座次。
	var human_count: int = _lobby_members.size()
	if human_count < 2:
		return "至少需要2名真人玩家才能开始局域网对局。"
	if player_count < human_count:
		return "游戏总人数不能少于当前真人数量。"
	if player_count != _normalize_lobby_player_count(player_count, _lobby_game_mode_id):
		return "当前模式的游戏总人数不合法。"
	if player_count != _lobby_player_count:
		return "开局人数必须与大厅当前对局设置一致。"
	if not _is_lobby_game_mode_playable(_lobby_game_mode_id):
		return "当前游戏模式尚未实现。"
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_player_display_names.clear()
	# 可分配稳定玩家 ID；大厅真人座位按玩家主动选择的0起始位置映射，空余 ID 由 AI 使用。
	var available_player_ids: Array[int] = []
	for player_id: int in range(player_count):
		available_player_ids.append(player_id)
	# 大厅成员顺序；快照先提供稳定成员副本，再按玩家主动选择的位置排序，不依赖哈希顺序。
	var lobby_snapshot: Dictionary = get_lan_lobby_snapshot()
	# 大厅成员数组；成员顺序已经由快照固定，数量应与当前真人数量一致。
	var members: Array = lobby_snapshot.get("members", []) as Array
	members.sort_custom(func(first_member_variant: Variant, second_member_variant: Variant) -> bool:
		# 两名大厅成员；换位只影响这里的初始真人映射顺序，不改变身份洗牌或领袖座次旋转。
		var first_member: Dictionary = first_member_variant as Dictionary
		var second_member: Dictionary = second_member_variant as Dictionary
		return int(first_member.get("seat_index", 0)) < int(second_member.get("seat_index", 0))
	)
	for member_index: int in range(members.size()):
		# 当前大厅成员；显示名只用于权威玩家状态和日志，不参与网络权限判断。
		var member: Dictionary = members[member_index] as Dictionary
		# 当前成员网络连接 ID；用于建立连接到稳定玩家 ID 的权威映射。
		var peer_id: int = int(member.get("peer_id", 0))
		# 当前成员稳定玩家 ID；按大厅位置从前到后映射到真人 ID，2人房的第三个视觉位置不会越过规则人数范围。
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
	if _rejected_lobby_peer_ids.has(peer_id):
		_rejected_lobby_peer_ids.erase(peer_id)
		_last_incoming_sequence_by_peer.erase(peer_id)
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
	_send_packet_to_peer(_build_packet("lobby_join", {"display_name":_local_display_name, "avatar_character_id":_local_avatar_character_id, "room_password":_pending_lobby_password}), SERVER_PEER_ID)


## 客户端连接失败回调；释放 ENet 资源并返回可重试的离线状态。
func _on_connection_failed() -> void:
	if lan_role != LanRole.CLIENT:
		return
	_release_lan_peer()
	_set_offline_state()
	connection_state_changed.emit(false, "连接局域网房主失败，请检查 IP、端口和防火墙。")
	lan_session_closed.emit("连接局域网房主失败，请检查 IP、端口和防火墙。")


## 客户端失去房主回调；局域网模式不执行主机迁移，当前对局立即结束并返回主菜单。
func _on_server_disconnected() -> void:
	if lan_role != LanRole.CLIENT:
		return
	_release_lan_peer()
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
			_register_lobby_member(sender_peer_id, str(payload.get("display_name", "玩家")), str(payload.get("avatar_character_id", "")), str(payload.get("room_password", "")))
			return
		if not _lobby_members.has(sender_peer_id):
			return
		if message_type == "lobby_seat":
			if not _lan_match_active:
				_apply_lobby_seat_change(sender_peer_id, int(payload.get("seat_index", -1)))
			return
		if message_type == "lobby_chat":
			if not _lan_match_active:
				_append_lobby_chat_message(sender_peer_id, str(payload.get("message", "")))
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
		elif message_type == "lobby_rejected":
			_apply_lobby_rejection(str(payload.get("message", "无法进入局域网房间。")))
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


## 登记客户端大厅资料并广播最新成员表；密码错误时定向拒绝，重复登记保留原加入顺序与座位。
func _register_lobby_member(peer_id: int, display_name: String, avatar_character_id: String, room_password: String) -> void:
	if lan_role != LanRole.HOST or _lan_match_active or peer_id <= SERVER_PEER_ID:
		return
	# 当前加入者的剩余冷却；只有被房主踢出的远端地址会命中，密码或人数拒绝不会建立此记录。
	var cooldown_remaining_msec: int = _get_kick_rejoin_cooldown_remaining_msec(peer_id)
	if cooldown_remaining_msec > 0:
		# 当前剩余等待整秒；向上取整保证提示的5秒不会在边界提前显示为0秒。
		var cooldown_remaining_seconds: int = ceili(float(cooldown_remaining_msec) / 1000.0)
		_reject_lobby_peer(peer_id, "你刚被房主移出房间，请在%d秒后再加入。" % cooldown_remaining_seconds)
		return
	if _sanitize_lobby_password(room_password) != _lobby_password:
		_reject_lobby_peer(peer_id, "房间密码错误。")
		return
	# 已有成员；同一连接重复发送 hello 时保留原加入顺序，避免列表位置闪动。
	var existing_member: Dictionary = _lobby_members.get(peer_id, {}) as Dictionary
	if existing_member.is_empty() and _lobby_members.size() >= _lobby_player_count:
		_reject_lobby_peer(peer_id, "房间当前没有空余位置。")
		return
	# 已有加入序号；-1表示首次登记，需要分配新的单调递增序号。
	var join_order: int = int(existing_member.get("join_order", -1))
	if join_order < 0:
		_join_sequence += 1
		join_order = _join_sequence
	# 当前大厅座位；重复登记保留旧座位，首次加入分配从0开始的最小空位。
	var seat_index: int = int(existing_member.get("seat_index", _find_first_available_lobby_seat()))
	_lobby_members[peer_id] = _make_lobby_member(peer_id, _sanitize_display_name(display_name), _sanitize_avatar_character_id(avatar_character_id), false, join_order, seat_index)
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
	_lobby_game_mode_id = _normalize_lobby_game_mode_id(str(snapshot.get("game_mode_id", DEFAULT_LOBBY_GAME_MODE_ID)))
	_lobby_player_count = _normalize_lobby_player_count(int(snapshot.get("player_count", 2)), _lobby_game_mode_id)
	_lobby_password_enabled = bool(snapshot.get("has_password", false))
	_lobby_chat_history.clear()
	for chat_variant: Variant in snapshot.get("chat_history", []) as Array:
		_lobby_chat_history.append((chat_variant as Dictionary).duplicate(true))
	_lan_match_active = bool(snapshot.get("match_active", false))
	connected = true
	_pending_lobby_password = ""
	lan_lobby_changed.emit(get_lan_lobby_snapshot())
	connection_state_changed.emit(true, "已进入局域网房间。")


## 客户端应用房主开局通知；只保存自身按大厅位置分配的玩家映射，不接收其他玩家与 peer 的对应关系。
func _apply_remote_match_start(payload: Dictionary) -> void:
	# 本地稳定玩家 ID；房主已按大厅位置顺序分配，客户端后续所有动作必须使用该值。
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


## 创建单个可序列化大厅成员；名称、形象与座位均已标准化，加入序号只用于成员列表稳定排序。
func _make_lobby_member(peer_id: int, display_name: String, avatar_character_id: String, is_host: bool, join_order: int, seat_index: int) -> Dictionary:
	return {
		"peer_id":peer_id,
		"display_name":display_name,
		"avatar_character_id":avatar_character_id,
		"is_host":is_host,
		"join_order":join_order,
		"seat_index":seat_index,
	}


## 应用大厅成员换位请求；只接受当前人数范围内未被占用的位置，成功后广播完整公共快照。
func _apply_lobby_seat_change(peer_id: int, seat_index: int) -> void:
	if lan_role != LanRole.HOST or _lan_match_active or not _lobby_members.has(peer_id):
		return
	if seat_index < 0 or seat_index >= _get_lobby_display_slot_count():
		return
	for member_variant: Variant in _lobby_members.values():
		# 当前大厅成员；目标位置已被任何玩家占用时拒绝，不执行两人交换。
		var member: Dictionary = member_variant as Dictionary
		if int(member.get("seat_index", -1)) == seat_index:
			return
	# 待移动成员；复制后写回，避免把字典引用变更传播到正在生成的旧快照。
	var moved_member: Dictionary = (_lobby_members.get(peer_id, {}) as Dictionary).duplicate(true)
	moved_member["seat_index"] = seat_index
	_lobby_members[peer_id] = moved_member
	_emit_lobby_state()


## 把聊天正文登记为房主权威公共历史；发送者名称由成员表解析，客户端不能伪造署名。
func _append_lobby_chat_message(peer_id: int, message: String) -> void:
	if lan_role != LanRole.HOST or _lan_match_active or not _lobby_members.has(peer_id):
		return
	# 标准化后的消息；空字符串不会进入历史或触发大厅重绘。
	var sanitized_message: String = _sanitize_lobby_chat_message(message)
	if sanitized_message.is_empty():
		return
	# 发送者大厅资料；只读取房主已经校验的显示名，不相信上行 payload 自报身份。
	var member: Dictionary = _lobby_members.get(peer_id, {}) as Dictionary
	_lobby_chat_sequence += 1
	_lobby_chat_history.append({
		"sequence":_lobby_chat_sequence,
		"display_name":str(member.get("display_name", "玩家")),
		"message":sanitized_message,
		"time_text":Time.get_time_string_from_system(),
	})
	while _lobby_chat_history.size() > MAX_LOBBY_CHAT_HISTORY:
		_lobby_chat_history.pop_front()
	_emit_lobby_state()


## 计算从0开始的最小空大厅座位；全部位置占满时返回当前人数上限作为无效标记。
func _find_first_available_lobby_seat() -> int:
	for seat_index: int in range(_get_lobby_display_slot_count()):
		# 当前座位是否已被成员占用；仅大厅公共 seat_index 参与判断。
		var is_occupied: bool = false
		for member_variant: Variant in _lobby_members.values():
			if int((member_variant as Dictionary).get("seat_index", -1)) == seat_index:
				is_occupied = true
				break
		if not is_occupied:
			return seat_index
	return _get_lobby_display_slot_count()


## 在房间人数缩小时重新规范化成员座位；保留仍合法且不重复的位置，其余成员依次填入空位。
func _normalize_lobby_member_seats() -> void:
	# 已占用座位；按稳定加入顺序处理成员，优先保留房主与先加入玩家的合法位置。
	var occupied_seats: Array[int] = []
	var snapshot: Dictionary = get_lan_lobby_snapshot()
	for member_variant: Variant in snapshot.get("members", []) as Array:
		# 当前大厅成员副本；非法或重复位置会在下面分配首个空位。
		var member: Dictionary = (member_variant as Dictionary).duplicate(true)
		# 当前候选座位；必须位于新人数范围内且没有被先前成员占用。
		var seat_index: int = int(member.get("seat_index", -1))
		if seat_index < 0 or seat_index >= _get_lobby_display_slot_count() or occupied_seats.has(seat_index):
			seat_index = 0
			while occupied_seats.has(seat_index) and seat_index < _get_lobby_display_slot_count():
				seat_index += 1
		member["seat_index"] = seat_index
		occupied_seats.append(seat_index)
		_lobby_members[int(member.get("peer_id", 0))] = member


## 定向拒绝或踢出大厅客户端；可靠原因包先发送，再延迟断开底层 peer 以提高提示到达概率。
## starts_kick_rejoin_cooldown 为 true 时只在房主主动踢出路径记录远端地址，其他拒绝不会阻止玩家再次尝试。
func _reject_lobby_peer(peer_id: int, message: String, starts_kick_rejoin_cooldown: bool = false) -> void:
	if lan_role != LanRole.HOST or peer_id <= SERVER_PEER_ID:
		return
	if starts_kick_rejoin_cooldown:
		# 当前被踢连接的远端地址；ENet 重连会更换 peer ID，地址才是5秒限制的稳定网络标识。
		var remote_address: String = _get_remote_address_for_peer(peer_id)
		if not remote_address.is_empty():
			_kick_rejoin_expiry_msec_by_address[remote_address] = Time.get_ticks_msec() + KICK_REJOIN_COOLDOWN_MSEC
	_send_packet_to_peer(_build_packet("lobby_rejected", {"message":message}), peer_id)
	_lobby_members.erase(peer_id)
	if not _rejected_lobby_peer_ids.has(peer_id):
		_rejected_lobby_peer_ids.append(peer_id)
	_emit_lobby_state()
	# 短暂延迟断开；可靠拒绝包先获得一个网络刷新窗口，客户端才能显示准确密码或踢出原因。
	get_tree().create_timer(0.15).timeout.connect(_disconnect_rejected_lobby_peer.bind(peer_id))


## 返回指定连接仍需等待的踢出冷却毫秒数；过期条目在读取时清理，避免长期开房积累旧地址。
func _get_kick_rejoin_cooldown_remaining_msec(peer_id: int) -> int:
	# 当前连接远端地址；无法获取时不对未知地址做限制，避免误伤合法玩家。
	var remote_address: String = _get_remote_address_for_peer(peer_id)
	if remote_address.is_empty():
		return 0
	# 当前地址冷却结束时间；不存在时返回0表示可正常登记。
	var expiry_msec: int = int(_kick_rejoin_expiry_msec_by_address.get(remote_address, 0))
	# 当前单调时间；不受系统日期修改影响，适合短暂会话冷却。
	var current_msec: int = Time.get_ticks_msec()
	if expiry_msec <= current_msec:
		_kick_rejoin_expiry_msec_by_address.erase(remote_address)
		return 0
	return expiry_msec - current_msec


## 返回 ENet peer 的远端网络地址；仅房主在对端仍连接时调用，失败时返回空字符串而不建立冷却。
func _get_remote_address_for_peer(peer_id: int) -> String:
	if _enet_peer == null or peer_id <= SERVER_PEER_ID:
		return ""
	# 当前底层 ENet 对端；peer 已关闭或不存在时返回 null，不能继续读取地址。
	var enet_packet_peer: ENetPacketPeer = _enet_peer.get_peer(peer_id)
	if enet_packet_peer == null:
		return ""
	return enet_packet_peer.get_remote_address().strip_edges()


## 执行已经发送拒绝原因的底层断开；peer 可能已主动离开，因此调用前再次检查 ENet 实例。
func _disconnect_rejected_lobby_peer(peer_id: int) -> void:
	if _enet_peer == null or not _rejected_lobby_peer_ids.has(peer_id):
		return
	# 当前 peer 仍在拒绝列表中，说明断开回调尚未移除它；若客户端已主动关闭，_on_peer_disconnected 会先清理该标记并使此延迟任务静默返回。
	_enet_peer.disconnect_peer(peer_id)


## 客户端处理房主的大厅拒绝原因；立即释放本地 ENet 并返回可重试的离线入口。
func _apply_lobby_rejection(message: String) -> void:
	if lan_role != LanRole.CLIENT:
		return
	_release_lan_peer()
	_set_offline_state()
	connection_state_changed.emit(false, message)
	lan_session_closed.emit(message)


## 标准化玩家显示名；移除首尾空白、限制长度，并为空值提供稳定“玩家”回退。
func _sanitize_display_name(display_name: String) -> String:
	# 去除首尾空白后的名称；内部空格保留，允许玩家使用自然昵称。
	var sanitized_name: String = display_name.strip_edges()
	if sanitized_name.is_empty():
		sanitized_name = "玩家"
	if sanitized_name.length() > MAX_DISPLAY_NAME_LENGTH:
		sanitized_name = sanitized_name.left(MAX_DISPLAY_NAME_LENGTH)
	return sanitized_name


## 标准化联机形象武将 ID；只接受数据库已登记武将，缺失或过期配置回退首个稳定 ID。
func _sanitize_avatar_character_id(character_id: String) -> String:
	# 去除首尾空白后的稳定武将 ID；大厅只传字符串，不传纹理或节点。
	var sanitized_character_id: String = character_id.strip_edges()
	if GameDatabase.characters.has(sanitized_character_id):
		return sanitized_character_id
	# 可用武将 ID；排序后回退首项，保证不同机器相同内容库得到同一默认形象。
	var character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		character_ids.append(str(character_id_variant))
	character_ids.sort()
	return character_ids[0] if not character_ids.is_empty() else ""


## 标准化房间密码；保留内部空格，移除首尾空白并限制为32个 Unicode 字符。
func _sanitize_lobby_password(room_password: String) -> String:
	return room_password.strip_edges().left(MAX_LOBBY_PASSWORD_LENGTH)


## 标准化大厅聊天正文；移除首尾空白并限制长度，内部换行替换为空格保持单条消息紧凑。
func _sanitize_lobby_chat_message(message: String) -> String:
	return message.replace("\r", " ").replace("\n", " ").strip_edges().left(MAX_LOBBY_CHAT_LENGTH)


## 规范化大厅游戏模式稳定 ID；只有已登记选项允许保存，未知值统一回退身份模式。
func _normalize_lobby_game_mode_id(game_mode_id: String) -> String:
	for mode_option: Dictionary in LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) == game_mode_id:
			return game_mode_id
	return DEFAULT_LOBBY_GAME_MODE_ID


## 判断大厅模式是否已具备完整开局规则；当前支持标准身份局、斗地主、2v2与1v1车轮战。
func _is_lobby_game_mode_playable(game_mode_id: String) -> bool:
	var normalized_mode: String = _normalize_lobby_game_mode_id(game_mode_id)
	return normalized_mode == DEFAULT_LOBBY_GAME_MODE_ID or normalized_mode == "doudizhu" or normalized_mode == "team2v2" or normalized_mode == "wheel_duel" or normalized_mode == "opportunity_brawl"


## 按大厅模式规范化总人数；身份模式 2–10，斗地主仅 3 或 5，2v2 固定 4。
func _normalize_lobby_player_count(player_count: int, game_mode_id: String) -> int:
	var normalized_mode: String = _normalize_lobby_game_mode_id(game_mode_id)
	if GameSettings != null and GameSettings.has_method("normalize_player_count_for_mode"):
		return GameSettings.normalize_player_count_for_mode(normalized_mode, player_count)
	if normalized_mode == "doudizhu":
		if player_count == 3 or player_count == 5:
			return player_count
		return 3 if player_count < 4 else 5
	return clampi(player_count, 2, MAX_MATCH_PLAYER_COUNT)


## 返回大厅需要绘制的视觉位置数；2人局与3人局都使用3个居中位置，其余人数与设置人数一致。
func _get_lobby_display_slot_count() -> int:
	return 3 if _lobby_player_count <= 3 else _lobby_player_count


## 从 SceneMultiplayer 解除当前 ENet peer 后关闭底层套接字；先替换框架持有的 peer，才能保证同一端口可立即重新建房。
func _release_lan_peer() -> void:
	# 待释放的底层 peer；先保存局部引用，避免重置成员状态后丢失需要关闭的监听套接字。
	var peer_to_release: ENetMultiplayerPeer = _enet_peer
	_enet_peer = null
	if multiplayer != null:
		# 先移除 SceneMultiplayer 的旧引用；旧 peer 的断开事件不能继续作用于随后新建的局域网会话。
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer_to_release != null:
		peer_to_release.close()


## 清理全部 LAN 会话状态并恢复离线回环；该函数不发信号，由具体生命周期入口决定用户提示。
func _set_offline_state() -> void:
	mode = Mode.OFFLINE
	lan_role = LanRole.NONE
	connected = true
	outgoing_sequence = 0
	_lobby_members.clear()
	_lobby_password = ""
	_lobby_password_enabled = false
	_lobby_player_count = 2
	_lobby_game_mode_id = DEFAULT_LOBBY_GAME_MODE_ID
	_lobby_chat_history.clear()
	_lobby_chat_sequence = 0
	_rejected_lobby_peer_ids.clear()
	_local_avatar_character_id = ""
	_pending_lobby_password = ""
	_join_sequence = 0
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_player_display_names.clear()
	_last_incoming_sequence_by_peer.clear()
	_current_incoming_peer_id = 0
	_lan_match_active = false
	_lan_match_player_count = 0
