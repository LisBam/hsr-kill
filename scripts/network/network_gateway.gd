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

## 对局中远端成员携令牌重连成功信号；网关已重绑连接映射，权威端应解除该玩家离线托管并补发私有快照。
signal lan_match_peer_reconnected(player_id: int, display_name: String)

## 客户端断线自动重连状态信号；reconnecting 为 true 表示正在重试，为 false 表示重连结束，message 说明进度或结果。
signal lan_reconnect_state_changed(reconnecting: bool, message: String)

## 权威表现事件接收信号；日志、公开卡牌动画和技能提示通过该只读通道同步，不修改客户端规则状态。
signal game_event_received(event_type: String, event_payload: Dictionary)

## 对局内聊天消息到达信号；条目含递增序号、发送者稳定玩家 ID、显示名、正文与时间文本。
## 离线本机发言、LAN 房主中继与 LAN 客户端接收统一经过本信号，牌桌据此刷新聊天窗口并显示头顶气泡。
signal match_chat_received(chat_entry: Dictionary)

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

## 当前封包协议版本；版本6在版本5基础上新增对局会话令牌下发、断线座位预约与携令牌重连握手。
## 版本7在版本6基础上向大厅公共快照新增 custom_identity_enabled 自选身份开关字段。
## 版本8在版本7基础上新增对局内聊天 match_chat 消息类型（客户端上行与房主中继下行共用）。
## 版本9在版本8基础上移除大厅聊天与对局聊天条目的 time_text 字段（聊天界面不再显示时间）。
## 版本10在版本9基础上向大厅公共快照新增 fixed_seat_enabled 固定座位开关字段，并调整自选身份只绑定身份而不固定物理座位。
const PROTOCOL_VERSION: int = 10

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

## 单条对局内聊天允许的最大 Unicode 字符数；默认200与大厅聊天一致，避免超长消息撑爆聊天窗口或封包。
const MAX_MATCH_CHAT_LENGTH: int = 200

## 对局内聊天历史保留上限；默认100条覆盖整局常规交流量，同时限制聊天窗口重绘与内存开销。
const MAX_MATCH_CHAT_HISTORY: int = 100

## 房主踢出成员后的同一远端地址重新加入冷却毫秒数；默认5000即5秒，只限制踢出流程，不影响密码错误和满员拒绝。
const KICK_REJOIN_COOLDOWN_MSEC: int = 5000

## 客户端断线后相邻两次自动重连尝试的间隔秒数；默认2秒在网络抖动恢复速度与房主端连接压力之间取得平衡。
const RECONNECT_ATTEMPT_INTERVAL_SECONDS: float = 2.0

## 客户端断线后允许的最大自动重连尝试次数；默认15次，叠加单次连接超时后重试窗口约1至2分钟，用尽后按普通会话关闭返回主菜单。
const MAX_RECONNECT_ATTEMPTS: int = 15

## 对局中新连接完成携令牌重连登记的宽限秒数；默认5秒，超时仍未登记的连接会被断开，防止陌生连接长期占用房主连接槽。
const MATCH_REJOIN_HANDSHAKE_TIMEOUT_SECONDS: float = 5.0

## 会话令牌的随机字节长度；默认16字节经十六进制编码得到32字符令牌，局域网场景下不可被旁观者猜测即可满足校验需求。
const SESSION_TOKEN_RANDOM_BYTES: int = 16

## 当前可启动的默认游戏模式稳定 ID；大厅设置与开局协调只使用稳定 ID，不依赖中文显示名。
const DEFAULT_LOBBY_GAME_MODE_ID: String = "identity"

## 当前已实现的大厅游戏模式配置；后续新增真实规则模式时可追加稳定 ID 与玩家可见名称。
const LOBBY_GAME_MODE_OPTIONS: Array[Dictionary] = [
	{"id":DEFAULT_LOBBY_GAME_MODE_ID, "display_name":"身份模式"},
	{"id":"doudizhu", "display_name":"斗地主"},
	{"id":"team2v2", "display_name":"2v2"},
	{"id":"wheel_duel", "display_name":"1v1车轮战"},
	{"id":"opportunity_brawl", "display_name":"机缘大乱斗"},
	{"id":"conquest", "display_name":"过关斩将"},
]

## 局域网默认端口；7000避开系统保留端口并方便开发环境记忆，可在创建或加入房间时覆盖。
@export_range(1024, 65535, 1) var default_lan_port: int = 7000

## 局域网服务器允许的最大远端客户端数量；默认9与“1名房主+9名客户端=10人局”一致，运行时无需动态修改。
@export_range(1, 9, 1) var maximum_lan_clients: int = 9

## 自选身份下“大厅位置→规则座次”随机洗牌使用的固定种子；0表示每次开局取系统熵，非0用于回归测试与复现固定排列。
@export_range(0, 2147483647, 1) var lobby_seat_shuffle_seed: int = 0

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

## 当前房间是否开启自选身份；开启后大厅每个位置绑定固定身份、玩家通过换位自选，开局按位置身份表分配身份。
var _lobby_custom_identity_enabled: bool = false

## 当前房间是否固定绑定大厅位置与规则座次；关闭时身份仍按大厅位置绑定，但物理座位在每次开局重新随机打乱。
var _lobby_fixed_seat_enabled: bool = false

## 本次开局的座位占用者大厅位置；索引为稳定玩家ID，值为占用该座位成员的大厅位置，仅自选身份开局填充。
## 权威控制器据此把大厅位置身份写入真正占用该座位的玩家，使身份跟人走而物理座位保持随机。
var _seat_lobby_slot_indices: Array[int] = []

## 大厅位置与规则座次随机绑定使用的随机源；只在自选身份且不固定座位时参与洗牌，不接触牌堆或规则随机。
var _lobby_seat_shuffle_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 身份规则服务；网关只用其查询大厅位置身份布局、位置到规则座次映射与模式支持性，不接触对局状态。
var _identity_rules: IdentityRules = IdentityRules.new()

## 当前大厅公共聊天历史；每项只含递增序号、玩家名、消息与显示时间，最多保留100条。
var _lobby_chat_history: Array[Dictionary] = []

## 当前大厅聊天消息递增序号；房主每接受一条非空消息增加1，用于跨客户端稳定排序。
var _lobby_chat_sequence: int = 0

## 当前对局内聊天历史；每项含递增序号、发送者稳定玩家 ID、显示名、正文与时间文本，最多保留100条。
## 房主保存权威历史，客户端与离线模式保存本机接收到的同构条目；新开一局时清空。
var _match_chat_history: Array[Dictionary] = []

## 当前对局内聊天消息递增序号；房主（或离线本机）每接受一条非空消息增加1，用于聊天窗口稳定排序。
var _match_chat_sequence: int = 0

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

## 房主为每名远端真人签发的稳定玩家 ID 到会话令牌映射；令牌在正式开局时生成，同一房间存续期间保持不变。
var _lan_session_tokens_by_player: Dictionary = {}

## 断线座位预约表；键为会话令牌，值为掉线成员的玩家 ID、显示名、形象与座位资料，重连成功、对局结束或重开新局时移除。
var _reserved_lan_players: Dictionary = {}

## 客户端持有的本机会话令牌；由房主随 match_start 私发，断线自动重连时作为身份凭证原样上行，仅保存在内存不落盘。
var _local_session_token: String = ""

## 客户端是否处于断线自动重连流程；期间保留对局绑定、成员表与令牌，不触发普通会话关闭清理。
var _reconnecting: bool = false

## 剩余自动重连尝试次数；每次发起连接前递减，归零后放弃重连并按普通会话关闭返回主菜单。
var _reconnect_attempts_remaining: int = 0

## 最近一次加入房间使用的房主地址；断线自动重连直接复用，不要求玩家重新输入。
var _last_join_address: String = ""

## 最近一次加入房间使用的房主端口；与地址一同保存供断线自动重连重拨。
var _last_join_port: int = 0

## 当前房间配置的对局总人数；包含所有真人成员与由房主补齐的 AI 座位，未开局时为0。
var _lan_match_player_count: int = 0


## 初始化 SceneMultiplayer 连接信号；网关不自动创建网络端口，必须由大厅入口显式调用。
func _ready() -> void:
	# 网络收发在规则弹窗暂停场景树时仍需继续轮询，保证联机玩家可以完成机缘等全体选择。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 座位洗牌随机源；固定种子用于回归测试复现排列，0表示每次开局重新取系统熵。
	if lobby_seat_shuffle_seed != 0:
		_lobby_seat_shuffle_rng.seed = lobby_seat_shuffle_seed
	else:
		_lobby_seat_shuffle_rng.randomize()
	_bind_multiplayer_signals()


## 切换通信模式并重置连接状态；REMOTE 仍需要外部适配器随后确认连接。
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	connected = mode == Mode.OFFLINE
	connection_state_changed.emit(connected, "离线模式已就绪" if connected else "等待传输适配器连接")


## 创建局域网 ENet 房间；成功后本机成为大厅房主，并应用联机形象、密码、人数与模式初始配置。
func host_lan(display_name: String, port: int = -1, avatar_character_id: String = "", room_password: String = "", player_count: int = 2, game_mode_id: String = DEFAULT_LOBBY_GAME_MODE_ID, custom_identity_enabled: bool = false, fixed_seat_enabled: bool = false) -> Error:
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
	# 房间初始自选身份开关；不支持自选身份的模式（过关斩将）强制关闭，避免快照携带无效布局。
	_lobby_custom_identity_enabled = custom_identity_enabled and _identity_rules.supports_lobby_custom_identity(_lobby_game_mode_id)
	# 房间初始固定座位开关；只影响自选身份下的座位是否随开局随机，关闭后身份仍按大厅位置绑定。
	_lobby_fixed_seat_enabled = fixed_seat_enabled
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
	# 保存本次房主地址与端口；对局中意外断线时自动重连沿用同一目标，不要求玩家重新输入。
	_last_join_address = resolved_address
	_last_join_port = resolved_port
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
		"custom_identity_enabled":_lobby_custom_identity_enabled,
		"fixed_seat_enabled":_lobby_fixed_seat_enabled,
		"has_password":_lobby_password_enabled,
		"chat_history":_lobby_chat_history.duplicate(true),
	}
	if include_host_private_settings and lan_role == LanRole.HOST:
		snapshot["room_password"] = _lobby_password
	return snapshot


## 返回稳定模式ID当前是否可从大厅实际开局；牌桌开始入口与网关内部开局校验共用同一判定，避免两份模式白名单漂移。
func is_game_mode_playable(game_mode_id: String) -> bool:
	return _is_lobby_game_mode_playable(game_mode_id)


## 返回当前局域网房间是否实际启用自选身份；只有支持位置身份布局的模式返回 true，供开局座次绑定与权威身份分配读取。
func is_lan_custom_identity_enabled() -> bool:
	return mode == Mode.LAN and _lobby_custom_identity_enabled and _identity_rules.supports_lobby_custom_identity(_lobby_game_mode_id)


## 返回当前局域网房间是否固定绑定大厅位置与规则座次；关闭时身份仍按大厅位置绑定，但物理座位每局随机打乱。
func is_lan_fixed_seat_enabled() -> bool:
	return mode == Mode.LAN and _lobby_fixed_seat_enabled


## 返回本次开局的座位到大厅位置映射；索引为稳定玩家ID，值为占用该座位成员的大厅位置，未映射座位为-1。
## 只有自选身份开局会填充该映射，权威控制器据此把大厅位置身份写入真正占用该座位的玩家。
func get_lan_seat_lobby_slots() -> Array[int]:
	return _seat_lobby_slot_indices.duplicate()


## 房主更新大厅游戏模式、总人数、密码、自选身份与固定座位开关；人数不得少于当前真人数，成功后立即广播全员。
func update_lan_lobby_settings(game_mode_id: String, player_count: int, room_password: String, custom_identity_enabled: bool = false, fixed_seat_enabled: bool = false) -> String:
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
	# 自选身份开关随设置一并更新；不支持自选身份的模式强制关闭，保证位置身份表始终可解析。
	_lobby_custom_identity_enabled = custom_identity_enabled and _identity_rules.supports_lobby_custom_identity(_lobby_game_mode_id)
	# 固定座位开关随设置一并更新；关闭时身份仍按位置绑定，物理座位在开局随机，2v2 由模式规则单独强制固定。
	_lobby_fixed_seat_enabled = fixed_seat_enabled
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


## 发送一条对局内聊天消息；离线模式立即本地回环，LAN 房主直接登记并中继，LAN 客户端可靠上行给房主。
## offline_sender_player_id 与 offline_sender_name 仅在离线模式使用：网关不持有离线对局的玩家信息，
## 由牌桌传入本机第一视角玩家的稳定 ID 与显示名；LAN 模式忽略这两个参数并以连接绑定为准，客户端无法伪造署名。
func send_match_chat_message(message: String, offline_sender_player_id: int = -1, offline_sender_name: String = "玩家") -> void:
	# 标准化后的聊天正文；空白消息不创建历史记录或网络封包。
	var sanitized_message: String = _sanitize_match_chat_message(message)
	if sanitized_message.is_empty():
		return
	if mode == Mode.OFFLINE:
		_match_chat_sequence += 1
		_append_match_chat_entry(_make_match_chat_entry(_match_chat_sequence, offline_sender_player_id, offline_sender_name, sanitized_message))
		return
	if mode != Mode.LAN or not _lan_match_active:
		return
	if lan_role == LanRole.HOST:
		_append_match_chat_message(SERVER_PEER_ID, sanitized_message)
	elif lan_role == LanRole.CLIENT and connected:
		_send_packet_to_peer(_build_packet("match_chat", {"message":sanitized_message}), SERVER_PEER_ID)


## 返回当前对局内聊天历史的深拷贝；聊天窗口重建正文时使用，调用方不能修改网关内部记录。
func get_match_chat_history() -> Array[Dictionary]:
	# 历史副本；逐条深拷贝，保证界面持有的字典与网关权威记录互不影响。
	var history_copy: Array[Dictionary] = []
	for entry: Dictionary in _match_chat_history:
		history_copy.append(entry.duplicate(true))
	return history_copy


## 清空对局内聊天历史与序号；离线新开一局由牌桌调用，LAN 开局与会话结束由网关内部调用。
func clear_match_chat_history() -> void:
	_match_chat_history.clear()
	_match_chat_sequence = 0


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
	# 过关斩将的真人只占偶数玩家座位（0、2、4、6），奇数敌方座位固定由权威控制器注册内置 AI。
	var available_player_ids: Array[int] = build_match_seat_player_ids(_lobby_game_mode_id, player_count)
	# 本次开局是否按自选身份绑定座次；开启时大厅位置决定身份，座位是否固定由固定座位开关与模式规则决定。
	var custom_identity_active: bool = is_lan_custom_identity_enabled()
	# 大厅位置到规则座次映射；仅自选身份使用，2v2 把“上蓝下红”布局换算回一/四与二/三成队座次。
	var lobby_slot_match_seats: Array[int] = []
	if custom_identity_active:
		lobby_slot_match_seats = _identity_rules.get_lobby_slot_match_seats(_lobby_game_mode_id, player_count)
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
	# 本次开局实际使用的位置到座次映射；自选身份且不固定座位时替换为随机双射，其余情况保持模式标准映射。
	var lobby_slot_seat_binding: Array[int] = lobby_slot_match_seats
	if custom_identity_active and _should_shuffle_lobby_seat_binding():
		lobby_slot_seat_binding = _build_shuffled_lobby_slot_binding(members, lobby_slot_match_seats)
	# 座位占用者的大厅位置；仅供权威控制器把位置身份写入实际占用该座位的玩家，非自选身份开局保持空数组。
	_seat_lobby_slot_indices.clear()
	if custom_identity_active:
		_seat_lobby_slot_indices.resize(get_match_role_count_for_mode(_lobby_game_mode_id, player_count))
		_seat_lobby_slot_indices.fill(-1)
	for member_index: int in range(members.size()):
		# 当前大厅成员；显示名只用于权威玩家状态和日志，不参与网络权限判断。
		var member: Dictionary = members[member_index] as Dictionary
		# 当前成员网络连接 ID；用于建立连接到稳定玩家 ID 的权威映射。
		var peer_id: int = int(member.get("peer_id", 0))
		# 当前成员稳定玩家 ID；按大厅位置从前到后映射到真人 ID，2人房的第三个视觉位置不会越过规则人数范围。
		var player_id: int = available_player_ids[member_index]
		# 当前成员的大厅位置；自选身份下位置即身份，必须按位置取座次而不能按先后顺序压缩。
		var member_seat_index: int = int(member.get("seat_index", member_index))
		if custom_identity_active:
			# 自选身份下成员的实际大厅位置；位置即身份，必须直接绑定该位置对应的规则座次而不能按先后顺序压缩。
			if member_seat_index >= 0 and member_seat_index < lobby_slot_seat_binding.size():
				player_id = lobby_slot_seat_binding[member_seat_index]
			# 记录座位与大厅位置的反向映射；随机座位时只有它能让身份继续跟着大厅位置走。
			if player_id >= 0 and player_id < _seat_lobby_slot_indices.size() and member_seat_index >= 0:
				_seat_lobby_slot_indices[player_id] = member_seat_index
		_peer_to_player_id[peer_id] = player_id
		_player_to_peer_id[player_id] = peer_id
		_player_display_names[player_id] = str(member.get("display_name", "玩家"))
	# 正式对局的规则角色总数；过关斩将为玩家数的两倍（每名玩家配一名敌方AI），其他模式与大厅人数一致。
	_lan_match_player_count = get_match_role_count_for_mode(_lobby_game_mode_id, player_count)
	return ""


## 返回本次开局是否需要随机打乱“大厅位置 → 规则座次”的绑定。
## 固定座位开关开启时保持标准映射；2v2 等需要成队几何的模式由身份规则强制固定，避免队友被随机成相邻座位。
func _should_shuffle_lobby_seat_binding() -> bool:
	if _lobby_fixed_seat_enabled:
		return false
	return not _identity_rules.requires_fixed_lobby_seat(_lobby_game_mode_id)


## 为自选身份且不固定座位的开局构造随机双射，使身份继续跟随大厅位置而物理座位每局重新洗牌。
## 只有真人实际占用的位置参与洗牌，补位 AI 占用的规则座次集合因此保持不变；标准映射中未被占用的位置原样保留。
func _build_shuffled_lobby_slot_binding(members: Array, lobby_slot_match_seats: Array[int]) -> Array[int]:
	# 结果映射；先复制模式标准映射，再仅覆盖参与洗牌的真人位置。
	var binding: Array[int] = lobby_slot_match_seats.duplicate()
	# 真人占用的大厅位置列表；与占用的规则座次列表一一对应，洗牌后仍构成双射。
	var occupied_slots: Array[int] = []
	# 真人占用位置对应的规则座次列表；洗牌的就是这一份，因此不会把真人挤进 AI 补位座位。
	var occupied_seats: Array[int] = []
	for member_variant: Variant in members:
		# 当前大厅成员；只读取位置字段，其余字段与座位分配无关。
		var member: Dictionary = member_variant as Dictionary
		# 当前成员的大厅位置；越界或重复位置直接跳过，避免破坏双射。
		var member_seat_index: int = int(member.get("seat_index", -1))
		if member_seat_index < 0 or member_seat_index >= lobby_slot_match_seats.size():
			continue
		if occupied_slots.has(member_seat_index):
			continue
		occupied_slots.append(member_seat_index)
		occupied_seats.append(lobby_slot_match_seats[member_seat_index])
	# 少于两名真人时没有可交换的座位，保持标准绑定，避免“洗牌”结果与不洗牌完全等价却消耗随机源。
	if occupied_slots.size() < 2:
		return binding
	# 洗牌真人占用的规则座次；使用网关私有随机源，不消耗对局随机序列，因而不影响牌堆与身份洗牌的既有可复现性。
	for shuffle_index: int in range(occupied_seats.size() - 1, 0, -1):
		# 本次交换目标下标；包含自身，保证每个排列等概率。
		var swap_index: int = _lobby_seat_shuffle_rng.randi_range(0, shuffle_index)
		var carried_seat: int = occupied_seats[shuffle_index]
		occupied_seats[shuffle_index] = occupied_seats[swap_index]
		occupied_seats[swap_index] = carried_seat
	for index: int in range(occupied_slots.size()):
		binding[occupied_slots[index]] = occupied_seats[index]
	return binding


## 返回指定模式与大厅人数下真人可占用的稳定玩家 ID 序列；顺序即大厅位置从前到后的映射顺序。
## 过关斩将返回偶数座位（0、2、4……），保证“玩家1、敌人1、玩家2、敌人2”的交替行动座次；其他模式返回连续 ID。
static func build_match_seat_player_ids(game_mode_id: String, player_count: int) -> Array[int]:
	# 真人可用稳定 ID 结果；调用方按大厅位置顺序逐个取用。
	var result: Array[int] = []
	if game_mode_id == "conquest":
		for seat_ordinal: int in range(player_count):
			result.append(seat_ordinal * 2)
		return result
	for player_id: int in range(player_count):
		result.append(player_id)
	return result


## 返回指定模式与大厅人数对应的规则角色总数；过关斩将为玩家数两倍，其他模式人数即角色数。
static func get_match_role_count_for_mode(game_mode_id: String, player_count: int) -> int:
	if game_mode_id == "conquest":
		return player_count * 2
	return player_count


## 房主在权威控制器成功创建对局后通知全部客户端绑定玩家 ID；此后新连接会被拒绝。
## broadcast_lobby_state 为 false 时只发送开局绑定，不重发大厅成员表，供同一房间内的重开复用。
func begin_prepared_lan_match(broadcast_lobby_state: bool = true) -> void:
	if not is_lan_host() or _peer_to_player_id.is_empty() or _lan_match_player_count < 2:
		return
	_lan_match_active = true
	# 新对局开始时清空上一局的对局内聊天；大厅聊天历史保持不变，返回大厅仍可见。
	clear_match_chat_history()
	for peer_id_variant: Variant in _peer_to_player_id.keys():
		# 当前真人 peer；房主本地直接发出开始信号，远端通过可靠封包接收自己的私有玩家 ID。
		var peer_id: int = int(peer_id_variant)
		# 当前 peer 被分配的稳定玩家 ID；无效映射使用 -1 并由接收端拒绝开局数据。
		var assigned_player_id: int = int(_peer_to_player_id.get(peer_id, -1))
		if peer_id == SERVER_PEER_ID:
			lan_match_started.emit(assigned_player_id, _lan_match_player_count)
		else:
			# 该远端玩家的会话令牌；断线重连时作为身份凭证，同一房间重开对局继续复用首次签发的令牌。
			var session_token: String = _ensure_lan_session_token(assigned_player_id)
			_send_packet_to_peer(_build_packet("match_start", {"local_player_id":assigned_player_id, "player_count":_lan_match_player_count, "session_token":session_token}), peer_id)
	if broadcast_lobby_state:
		_emit_lobby_state()


## 房主在同一 ENet 房间内重开对局时重新广播开局绑定封包。
## 真人稳定玩家 ID 与大厅位置映射保持不变，会话令牌继续复用首次签发值，因此在线连接与断线重连身份都不受影响；
## 该重播只复用 begin_prepared_lan_match 的发送逻辑而不重发大厅成员表，避免对局进行中把客户端切回大厅界面。
func rebroadcast_prepared_lan_match() -> void:
	if not is_lan_host() or not _lan_match_active:
		return
	begin_prepared_lan_match(false)


## 放弃尚未正式广播的座次映射；权威开局校验失败时调用，客户端仍停留在同一大厅中等待重试。
func cancel_prepared_lan_match() -> void:
	if _lan_match_active:
		return
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_player_display_names.clear()
	# 座位到大厅位置映射属于被放弃的这次开局；同时清空，避免下一次开局读到最后一次准备时的陈旧位置。
	_seat_lobby_slot_indices.clear()
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


## 返回客户端当前是否处于断线自动重连流程；界面与测试据此展示或断言重连状态，不暴露内部重试计数。
func is_lan_reconnecting() -> bool:
	return _reconnecting


## 返回客户端是否已持有房主签发的会话令牌；令牌存在时对局中断线会先尝试自动重连而非直接结束会话。
func has_lan_session_token() -> bool:
	return not _local_session_token.is_empty()


## 返回当前等待重连的掉线座位数量；供权威端诊断与自动化测试断言预约表状态，不暴露令牌内容。
func get_reserved_lan_seat_count() -> int:
	return _reserved_lan_players.size()


## 清空全部断线座位预约；权威控制器在对局结束或重开新局时调用，使旧对局的重连凭证立即失效。
## 已在线玩家的会话令牌保持不变，他们在后续对局中掉线仍可用同一令牌重连。
func clear_lan_seat_reservations() -> void:
	_reserved_lan_players.clear()


## 模拟一次客户端意外断线（测试与诊断用途）；关闭底层 ENet 后走与真实断线完全相同的客户端处理路径。
func simulate_lan_connection_drop() -> void:
	if mode != Mode.LAN or lan_role != LanRole.CLIENT:
		return
	_release_lan_peer()
	_on_server_disconnected()


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


## SceneMultiplayer 远端连接回调；开局中的房间仅在存在掉线预约时给予携令牌重连的登记宽限，否则立即拒绝新成员。
func _on_peer_connected(peer_id: int) -> void:
	if lan_role != LanRole.HOST:
		return
	if _lan_match_active:
		if _reserved_lan_players.is_empty() and _lan_session_tokens_by_player.is_empty():
			# 房间内不存在任何可重连身份；对局中的陌生新连接立即断开，保持开局后拒绝新成员的既有规则。
			if _enet_peer != null:
				_enet_peer.disconnect_peer(peer_id)
			return
		# 存在可重连身份时等待其提交携令牌的 lobby_join；双端断线感知有时差，掉线预约可能晚于重连方到达，
		# 因此只要签发过会话令牌就开放登记宽限，令牌校验失败或宽限到期仍未登记的连接都会被断开。
		get_tree().create_timer(MATCH_REJOIN_HANDSHAKE_TIMEOUT_SECONDS).timeout.connect(_disconnect_unverified_match_peer.bind(peer_id))
		return
	connection_state_changed.emit(true, "检测到新玩家，正在登记大厅信息……")


## 断开在宽限期内未完成携令牌重连登记的对局中连接；已登记成员与已自行离开的连接不受影响。
func _disconnect_unverified_match_peer(peer_id: int) -> void:
	if lan_role != LanRole.HOST or _enet_peer == null or _lobby_members.has(peer_id):
		return
	# 当前底层 ENet 对端；宽限期内主动离开或已被拒绝断开的连接返回 null，不再重复断开。
	var enet_packet_peer: ENetPacketPeer = _enet_peer.get_peer(peer_id)
	if enet_packet_peer == null:
		return
	_enet_peer.disconnect_peer(peer_id)


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
		# 掉线座位按会话令牌登记重连预约；同一玩家携令牌回归时可恢复原稳定玩家 ID 与大厅资料。
		_reserve_lan_seat_for_reconnect(player_id, member)
		lan_match_peer_disconnected.emit(player_id, display_name)
	else:
		_emit_lobby_state()
	connection_state_changed.emit(true, "%s已离开房间。" % display_name)


## 为对局中掉线的真人按会话令牌登记座位预约；未签发令牌的连接没有可恢复的对局身份，不建立预约。
func _reserve_lan_seat_for_reconnect(player_id: int, member: Dictionary) -> void:
	# 掉线玩家的会话令牌；正式开局时随 match_start 签发，同一房间存续期间稳定不变。
	var session_token: String = str(_lan_session_tokens_by_player.get(player_id, ""))
	if session_token.is_empty():
		return
	_reserved_lan_players[session_token] = {
		"player_id":player_id,
		"display_name":str(member.get("display_name", "玩家")),
		"avatar_character_id":str(member.get("avatar_character_id", "")),
		"join_order":int(member.get("join_order", 0)),
		"seat_index":int(member.get("seat_index", 0)),
	}


## 返回指定稳定玩家 ID 的会话令牌；缺失时使用加密随机源签发32字符十六进制令牌并登记。
func _ensure_lan_session_token(player_id: int) -> String:
	# 已签发令牌；同一房间内令牌保持稳定，重开对局与多次断线重连共用同一凭证。
	var existing_token: String = str(_lan_session_tokens_by_player.get(player_id, ""))
	if not existing_token.is_empty():
		return existing_token
	# 加密随机字节；ENet 通道本身无加密，令牌只需不可被旁观者按规律猜测即可满足局域网重连校验。
	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(SESSION_TOKEN_RANDOM_BYTES)
	# 新签发令牌；十六进制字符串属于可序列化封包允许的基础类型。
	var session_token: String = random_bytes.hex_encode()
	_lan_session_tokens_by_player[player_id] = session_token
	return session_token


## 客户端完成 ENet 握手后向房主发送登记包；普通加入携带密码，断线自动重连改为携带会话令牌恢复原座位。
func _on_connected_to_server() -> void:
	if lan_role != LanRole.CLIENT:
		return
	connected = true
	if _reconnecting:
		# 重连握手上行；会话令牌是身份凭证，房主命中座位预约后回发带 rejoined 标记的开局绑定包。
		connection_state_changed.emit(true, "已连接房主，正在恢复对局……")
		_send_packet_to_peer(_build_packet("lobby_join", {"display_name":_local_display_name, "avatar_character_id":_local_avatar_character_id, "rejoin_token":_local_session_token}), SERVER_PEER_ID)
		return
	connection_state_changed.emit(true, "已连接房主，正在进入大厅……")
	_send_packet_to_peer(_build_packet("lobby_join", {"display_name":_local_display_name, "avatar_character_id":_local_avatar_character_id, "room_password":_pending_lobby_password}), SERVER_PEER_ID)


## 客户端连接失败回调；重连流程按一次失败尝试继续重试，普通加入失败则释放 ENet 并返回可重试的离线状态。
func _on_connection_failed() -> void:
	if lan_role != LanRole.CLIENT:
		return
	if _reconnecting:
		_handle_lan_reconnect_attempt_failure()
		return
	_release_lan_peer()
	_set_offline_state()
	connection_state_changed.emit(false, "连接局域网房主失败，请检查 IP、端口和防火墙。")
	lan_session_closed.emit("连接局域网房主失败，请检查 IP、端口和防火墙。")


## 客户端失去房主回调；持有会话令牌的进行中对局先进入自动重连流程，其余情况会话立即结束并返回主菜单。
func _on_server_disconnected() -> void:
	if lan_role != LanRole.CLIENT:
		return
	if _reconnecting:
		# 重连握手期间连接再次断开；按一次失败尝试处理，消耗剩余次数继续等待房主恢复。
		_handle_lan_reconnect_attempt_failure()
		return
	if _lan_match_active and not _local_session_token.is_empty():
		_begin_lan_reconnect_cycle()
		return
	_release_lan_peer()
	_set_offline_state()
	connection_state_changed.emit(false, "与局域网房主的连接已断开。")
	lan_session_closed.emit("与局域网房主的连接已断开。")


## 进入客户端断线自动重连流程；保留对局绑定、成员表与会话令牌，只重建底层 ENet 连接，期间不触发普通会话关闭。
func _begin_lan_reconnect_cycle() -> void:
	_release_lan_peer()
	connected = false
	_reconnecting = true
	_reconnect_attempts_remaining = MAX_RECONNECT_ATTEMPTS
	# 旧连接的入站序号记录；房主在新连接上重新计数，清空后重连首包不会被误判为重复而丢弃。
	_last_incoming_sequence_by_peer.clear()
	connection_state_changed.emit(false, "与房主连接中断，正在自动重连……")
	lan_reconnect_state_changed.emit(true, "与房主连接中断，正在自动重连……")
	# 首次拨号延迟到本帧断线信号分发结束后执行；避免在 SceneMultiplayer 回调栈内更换底层 peer。
	_attempt_lan_reconnect.call_deferred()


## 发起一次到原房主地址的重连拨号；创建失败按一次失败尝试处理，握手结果由既有连接信号回调继续推进。
func _attempt_lan_reconnect() -> void:
	if not _reconnecting or mode != Mode.LAN or lan_role != LanRole.CLIENT:
		return
	_reconnect_attempts_remaining -= 1
	_release_lan_peer()
	# 重连专用 ENet 客户端；每次尝试都使用独立实例，避免半开连接残留在 SceneMultiplayer。
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if peer.create_client(_last_join_address, _last_join_port) != OK:
		_handle_lan_reconnect_attempt_failure()
		return
	_enet_peer = peer
	multiplayer.multiplayer_peer = _enet_peer
	outgoing_sequence = 0


## 处理一次重连尝试失败；仍有剩余次数时安排下一次定时尝试，次数用尽后放弃并按普通会话关闭收尾。
func _handle_lan_reconnect_attempt_failure() -> void:
	if not _reconnecting:
		return
	_release_lan_peer()
	connected = false
	if _reconnect_attempts_remaining <= 0:
		_abort_lan_reconnect("自动重连失败，与局域网房主的对局已结束。")
		return
	lan_reconnect_state_changed.emit(true, "与房主连接中断，正在自动重连……（剩余%d次尝试）" % _reconnect_attempts_remaining)
	get_tree().create_timer(RECONNECT_ATTEMPT_INTERVAL_SECONDS).timeout.connect(_attempt_lan_reconnect)


## 放弃断线自动重连并执行完整会话收尾；界面依据 lan_session_closed 返回主菜单并展示失败原因。
func _abort_lan_reconnect(message: String) -> void:
	_reconnecting = false
	_release_lan_peer()
	_set_offline_state()
	lan_reconnect_state_changed.emit(false, message)
	connection_state_changed.emit(false, message)
	lan_session_closed.emit(message)


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
			if _lan_match_active:
				# 对局中的登记包只承担断线重连语义；令牌校验失败按普通对局中加入拒绝处理。
				_register_lan_match_rejoin(sender_peer_id, str(payload.get("rejoin_token", "")))
			else:
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
		if message_type == "match_chat":
			# 对局内聊天上行；发送者身份由连接绑定的稳定玩家 ID 反查，payload 自报字段一律不采信。
			_append_match_chat_message(sender_peer_id, str(payload.get("message", "")))
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
		elif message_type == "match_chat" and _lan_match_active:
			_apply_remote_match_chat(payload)


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


## 校验对局中连接提交的重连令牌并恢复其座位绑定；成功后回发带 rejoined 标记的开局绑定包并通知权威控制器。
## 令牌不透露校验细节：缺失、过期或未命中预约都返回同一对局中加入拒绝，防止探测房间内令牌状态。
func _register_lan_match_rejoin(peer_id: int, rejoin_token: String) -> void:
	if lan_role != LanRole.HOST or not _lan_match_active or peer_id <= SERVER_PEER_ID:
		return
	if rejoin_token.is_empty():
		_reject_lobby_peer(peer_id, "对局正在进行，无法加入该房间。")
		return
	# 待恢复的座位预约；只有房主已经察觉掉线的座位才有条目，重连成功后立即移除。
	var reservation: Dictionary = _reserved_lan_players.get(rejoin_token, {}) as Dictionary
	if reservation.is_empty():
		# 双端断线感知存在时差；客户端可能先于房主发现连接失效并重连，此时令牌仍绑定着旧连接，由新连接直接接管。
		reservation = _supersede_stale_lan_connection(rejoin_token)
	if reservation.is_empty():
		_reject_lobby_peer(peer_id, "对局正在进行，无法加入该房间。")
		return
	# 预约的稳定玩家 ID；重连只恢复原座位，不允许借机换位或占用其他玩家 ID。
	var player_id: int = int(reservation.get("player_id", -1))
	if player_id < 0 or _player_to_peer_id.has(player_id):
		_reject_lobby_peer(peer_id, "该座位当前无法重连。")
		return
	_reserved_lan_players.erase(rejoin_token)
	# 预约保存的显示名；重连沿用掉线前的名称，保证托管与恢复日志始终指向同一玩家。
	var display_name: String = str(reservation.get("display_name", "玩家"))
	_lobby_members[peer_id] = _make_lobby_member(peer_id, display_name, str(reservation.get("avatar_character_id", "")), false, int(reservation.get("join_order", 0)), int(reservation.get("seat_index", 0)))
	_peer_to_player_id[peer_id] = player_id
	_player_to_peer_id[player_id] = peer_id
	_last_incoming_sequence_by_peer.erase(peer_id)
	# 先回发开局绑定包再通知控制器；可靠通道保证客户端先恢复玩家 ID 绑定，随后到达的私有快照才能被接受。
	_send_packet_to_peer(_build_packet("match_start", {"local_player_id":player_id, "player_count":_lan_match_player_count, "session_token":rejoin_token, "rejoined":true}), peer_id)
	connection_state_changed.emit(true, "%s已重新连接房间。" % display_name)
	lan_match_peer_reconnected.emit(player_id, display_name)


## 用重连令牌接管房主尚未察觉掉线的旧连接；断开旧 peer 并返回其座位资料作为即时预约，令牌未命中在线座位时返回空。
## 旧连接登记为已拒绝后，其延迟到达的断开回调只做冷却清理，不会重复触发掉线托管或大厅广播。
func _supersede_stale_lan_connection(rejoin_token: String) -> Dictionary:
	for player_id_variant: Variant in _lan_session_tokens_by_player.keys():
		# 当前已签发令牌的稳定玩家；只匹配令牌完全一致的座位，不做任何模糊回退。
		var player_id: int = int(player_id_variant)
		if str(_lan_session_tokens_by_player.get(player_id, "")) != rejoin_token:
			continue
		# 旧连接 peer；令牌命中但没有在线绑定说明预约已被终局或重开清理，交由调用方按普通拒绝处理。
		var stale_peer_id: int = int(_player_to_peer_id.get(player_id, 0))
		if stale_peer_id <= SERVER_PEER_ID:
			return {}
		# 旧连接的大厅成员资料；先取出供新连接继承，再清理旧连接的全部会话映射。
		var stale_member: Dictionary = (_lobby_members.get(stale_peer_id, {}) as Dictionary).duplicate(true)
		_lobby_members.erase(stale_peer_id)
		_peer_to_player_id.erase(stale_peer_id)
		_player_to_peer_id.erase(player_id)
		_last_incoming_sequence_by_peer.erase(stale_peer_id)
		if not _rejected_lobby_peer_ids.has(stale_peer_id):
			_rejected_lobby_peer_ids.append(stale_peer_id)
		if _enet_peer != null and _enet_peer.get_peer(stale_peer_id) != null:
			_enet_peer.disconnect_peer(stale_peer_id)
		return {
			"player_id":player_id,
			"display_name":str(stale_member.get("display_name", "玩家")),
			"avatar_character_id":str(stale_member.get("avatar_character_id", "")),
			"join_order":int(stale_member.get("join_order", 0)),
			"seat_index":int(stale_member.get("seat_index", 0)),
		}
	return {}


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
	# 客户端同步房主权威自选身份开关；本地快照与位置身份徽记据此保持与房主一致。
	_lobby_custom_identity_enabled = bool(snapshot.get("custom_identity_enabled", false))
	# 客户端同步房主权威固定座位开关；只影响大厅设置摘要，座位映射仍由房主在开局时权威决定。
	_lobby_fixed_seat_enabled = bool(snapshot.get("fixed_seat_enabled", false))
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
	if not (_reconnecting and bool(payload.get("rejoined", false))):
		# 新对局开始时清空上一局的对局内聊天；断线重连回到同一局时保留既有本地聊天历史。
		clear_match_chat_history()
	# 房主签发的会话令牌；仅保存在客户端内存，断线自动重连时作为身份凭证原样上行。
	var session_token: String = str(payload.get("session_token", ""))
	if not session_token.is_empty():
		_local_session_token = session_token
	if _reconnecting and bool(payload.get("rejoined", false)):
		# 重连握手完成；结束重试循环并恢复连接状态，随后到达的私有快照会重建对局界面。
		_reconnecting = false
		_reconnect_attempts_remaining = 0
		lan_reconnect_state_changed.emit(false, "已重新连接房主，对局继续。")
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
	})
	while _lobby_chat_history.size() > MAX_LOBBY_CHAT_HISTORY:
		_lobby_chat_history.pop_front()
	_emit_lobby_state()


## 把对局内聊天登记为房主权威历史并中继给全部远端真人；发送者稳定玩家 ID 与显示名由连接绑定反查。
func _append_match_chat_message(peer_id: int, message: String) -> void:
	if lan_role != LanRole.HOST or not _lan_match_active or not _peer_to_player_id.has(peer_id):
		return
	# 标准化后的消息；空字符串不进入历史、不产生中继封包。
	var sanitized_message: String = _sanitize_match_chat_message(message)
	if sanitized_message.is_empty():
		return
	# 发送者稳定玩家 ID；由权威 peer 映射反查，保证头顶气泡定位到真实发言者。
	var sender_player_id: int = int(_peer_to_player_id.get(peer_id, -1))
	_match_chat_sequence += 1
	# 权威聊天条目；署名读取开局锁定的显示名映射，客户端不能通过 payload 伪造。
	var entry: Dictionary = _make_match_chat_entry(_match_chat_sequence, sender_player_id, get_lan_player_display_name(sender_player_id), sanitized_message)
	for remote_peer_variant: Variant in get_remote_player_assignments().keys():
		_send_packet_to_peer(_build_packet("match_chat", entry), int(remote_peer_variant))
	_append_match_chat_entry(entry)


## 客户端应用房主中继的对局内聊天条目；逐字段重建，防止畸形封包污染本地历史。
func _apply_remote_match_chat(payload: Dictionary) -> void:
	# 中继正文；再次执行长度与换行标准化，空消息直接丢弃。
	var sanitized_message: String = _sanitize_match_chat_message(str(payload.get("message", "")))
	if sanitized_message.is_empty():
		return
	_append_match_chat_entry(_make_match_chat_entry(int(payload.get("sequence", 0)), int(payload.get("sender_player_id", -1)), str(payload.get("display_name", "玩家")), sanitized_message))


## 创建单个可序列化对局内聊天条目；离线本机、房主权威与客户端重建共用同一结构。
## 条目只保留序号、发送者稳定玩家 ID、署名与正文；聊天界面不显示时间，因此不携带时间字段。
func _make_match_chat_entry(sequence: int, sender_player_id: int, display_name: String, message: String) -> Dictionary:
	return {
		"sequence":sequence,
		"sender_player_id":sender_player_id,
		"display_name":display_name,
		"message":message,
	}


## 把聊天条目追加到本机历史并发出到达信号；历史超过上限时从最早一条开始丢弃。
func _append_match_chat_entry(entry: Dictionary) -> void:
	_match_chat_history.append(entry)
	while _match_chat_history.size() > MAX_MATCH_CHAT_HISTORY:
		_match_chat_history.pop_front()
	match_chat_received.emit(entry.duplicate(true))


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
	if not _lan_match_active:
		# 对局中的重连拒绝不广播大厅快照；成员表在此期间只服务对局映射，客户端大厅界面已关闭。
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


## 客户端处理房主的大厅拒绝原因；重连流程收到确定性拒绝时立即放弃重试，普通加入被拒则返回可重试的离线入口。
func _apply_lobby_rejection(message: String) -> void:
	if lan_role != LanRole.CLIENT:
		return
	if _reconnecting:
		# 房主明确拒绝了重连凭证（对局结束、座位失效等）；继续重试不可能成功，立即执行完整收尾。
		_abort_lan_reconnect(message)
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


## 标准化对局内聊天正文；规则与大厅聊天一致但使用独立上限常量，两类聊天可分别调整而互不影响。
func _sanitize_match_chat_message(message: String) -> String:
	return message.replace("\r", " ").replace("\n", " ").strip_edges().left(MAX_MATCH_CHAT_LENGTH)


## 规范化大厅游戏模式稳定 ID；只有已登记选项允许保存，未知值统一回退身份模式。
func _normalize_lobby_game_mode_id(game_mode_id: String) -> String:
	for mode_option: Dictionary in LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) == game_mode_id:
			return game_mode_id
	return DEFAULT_LOBBY_GAME_MODE_ID


## 判断大厅模式是否已具备完整开局规则；当前支持标准身份局、斗地主、2v2与1v1车轮战。
func _is_lobby_game_mode_playable(game_mode_id: String) -> bool:
	var normalized_mode: String = _normalize_lobby_game_mode_id(game_mode_id)
	return normalized_mode == DEFAULT_LOBBY_GAME_MODE_ID or normalized_mode == "doudizhu" or normalized_mode == "team2v2" or normalized_mode == "wheel_duel" or normalized_mode == "opportunity_brawl" or normalized_mode == "conquest"


## 按大厅模式规范化总人数；身份模式 2–10，斗地主仅 3 或 5，2v2 固定 4。
func _normalize_lobby_player_count(player_count: int, game_mode_id: String) -> int:
	var normalized_mode: String = _normalize_lobby_game_mode_id(game_mode_id)
	if GameSettings != null and GameSettings.has_method("normalize_player_count_for_mode"):
		return GameSettings.normalize_player_count_for_mode(normalized_mode, player_count)
	if normalized_mode == "doudizhu":
		if player_count == 3 or player_count == 5:
			return player_count
		return 3 if player_count < 4 else 5
	if normalized_mode == "conquest":
		# 过关斩将大厅人数表示“玩家数”（不含敌方AI）；联机允许2至4名玩家，规则角色总数为其两倍。
		return clampi(player_count, 2, 4)
	return clampi(player_count, 2, MAX_MATCH_PLAYER_COUNT)


## 返回大厅需要绘制的视觉位置数；房主换位校验与界面绘制共用静态规则，避免两端位置数量漂移。
func _get_lobby_display_slot_count() -> int:
	return get_lobby_display_slot_count_for(_lobby_game_mode_id, _lobby_player_count, _lobby_custom_identity_enabled)


## 计算指定模式、人数与自选身份开关下的大厅视觉位置数；网关校验与大厅界面共用该唯一规则。
## 1v1车轮战固定两名真人1v1、各自选将，不绘制多余空位；自选身份开启后位置与身份一一绑定，位置数必须等于规则人数；
## 其余情况保持2至3人绘制3个居中位置的既有设计，人数更多时与设置人数一致。
static func get_lobby_display_slot_count_for(game_mode_id: String, player_count: int, custom_identity_enabled: bool) -> int:
	if game_mode_id == "wheel_duel":
		return player_count
	if custom_identity_enabled and IdentityRules.new().supports_lobby_custom_identity(game_mode_id):
		return player_count
	return 3 if player_count <= 3 else player_count


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
	_lobby_custom_identity_enabled = false
	# 固定座位开关随会话释放复原；下一次建房由创建入口显式写入。
	_lobby_fixed_seat_enabled = false
	# 座位到大厅位置映射属于单次开局的临时数据；会话释放后清空，避免下一次开局误用旧位置。
	_seat_lobby_slot_indices.clear()
	_lobby_chat_history.clear()
	_lobby_chat_sequence = 0
	_match_chat_history.clear()
	_match_chat_sequence = 0
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
	_lan_session_tokens_by_player.clear()
	_reserved_lan_players.clear()
	_local_session_token = ""
	_reconnecting = false
	_reconnect_attempts_remaining = 0
	_last_join_address = ""
	_last_join_port = 0
