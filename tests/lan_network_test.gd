extends Node

## 局域网 ENet 集成测试。默认进程创建密码房并派生一个客户端进程，覆盖形象、座位、聊天、隐私、座次映射、私有快照与 actor 防伪校验。

## 测试等待上限秒数；默认12秒兼顾首次脚本加载与本机 ENet 握手，超时视为联机闭环失败。
const TEST_TIMEOUT_SECONDS: float = 12.0

## 测试对局总人数；4人包含2名真人与2名 AI 空位，验证大厅真人数与对局总人数可以不同。
const TEST_PLAYER_COUNT: int = 4

## 测试房间密码；客户端使用相同凭据登记，公共大厅快照只能暴露 has_password。
const TEST_ROOM_PASSWORD: String = "网络测试密码"

## 房主联机形象稳定 ID；房主与客户端使用不同武将，便于验证资料没有串位。
const HOST_AVATAR_CHARACTER_ID: String = "xier"

## 客户端联机形象稳定 ID；该 ID 在正式武将数据库中存在并具有插画资源。
const CLIENT_AVATAR_CHARACTER_ID: String = "himeko"

## 客户端测试换位目标；四人房初始位置0和1被占用，位置3是合法空位。
const CLIENT_TARGET_SEAT_INDEX: int = 3

## 客户端测试聊天正文；房主必须以已登记成员名称署名，客户端不能通过 payload 伪造显示名。
const CLIENT_CHAT_MESSAGE: String = "客户端大厅聊天"

## 测试通信网关；主进程与派生客户端使用完全相同的节点路径，满足 Godot RPC 路径约束。
@onready var _gateway: NetworkGateway = $NetworkGateway

## 当前进程是否为派生客户端；通过 Godot 用户参数识别，不依赖环境变量或临时文件。
var _is_client_process: bool = false

## 本次测试端口；主进程按 PID 选择非保留端口，并通过用户参数传给客户端进程。
var _port: int = 0

## 客户端由房主分配的稳定玩家 ID；收到 match_start 前为 -1，任何动作都不能提前发送。
var _local_player_id: int = -1

## 房主是否已经完成座次准备与开局广播；防止重复大厅快照启动第二局。
var _host_match_started: bool = false

## 客户端是否已经发送合法动作；伪造 actor 被拒绝后只允许补发一次正确操作。
var _client_sent_valid_command: bool = false

## 客户端是否已经发送大厅聊天与换位请求；大厅每次广播都会回调，必须保证测试动作只提交一次。
var _client_sent_lobby_actions: bool = false

## 房主是否自动派生客户端进程；默认开启，调试时可用 `--lan-no-spawn` 改为由外部命令启动客户端。
var _spawn_client_process: bool = true

## 最近一次输出的底层连接状态枚举；状态变化时打印，避免每帧重复诊断文本。
var _last_connection_status: int = -1

## 测试超时节点；使用场景树 Timer 代替悬挂协程，正常退出时随测试节点一起释放。
var _timeout_timer: Timer


## 根据用户参数启动房主或客户端测试分支，并为每个进程安装统一超时保护。
func _ready() -> void:
	_parse_user_arguments()
	_gateway.lan_lobby_changed.connect(_on_lobby_changed)
	_gateway.lan_match_started.connect(_on_match_started)
	_gateway.snapshot_received.connect(_on_snapshot_received)
	_gateway.command_received.connect(_on_command_received)
	_gateway.game_event_received.connect(_on_game_event_received)
	_gateway.lan_session_closed.connect(_on_session_closed)
	_gateway.connection_state_changed.connect(_on_connection_state_changed)
	_install_timeout_guard()
	if _is_client_process:
		_start_client()
	else:
		_start_host()


## 解析 `--lan-client` 与 `--lan-port=` 用户参数；未知参数不影响测试角色。
func _parse_user_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--lan-client":
			_is_client_process = true
		elif argument == "--lan-no-spawn":
			_spawn_client_process = false
		elif argument.begins_with("--lan-port="):
			_port = argument.trim_prefix("--lan-port=").to_int()


## 启动测试房主并派生客户端 Godot 进程；派生失败会立即以非零状态结束。
func _start_host() -> void:
	if _port == 0:
		_port = 18000 + (OS.get_process_id() % 10000)
	# 房主建房结果；端口冲突或 ENet 初始化错误均不继续派生客户端。
	var host_error: Error = _gateway.host_lan("房主测试", _port, HOST_AVATAR_CHARACTER_ID, TEST_ROOM_PASSWORD, TEST_PLAYER_COUNT)
	if host_error != OK:
		_fail("host_create_error=%d" % host_error)
		return
	print("LAN_NETWORK_HOST_READY port=%d spawn_client=%s" % [_port, _spawn_client_process])
	if not _spawn_client_process:
		return
	# 当前 Godot 可执行文件；派生进程必须使用相同引擎版本，避免 RPC 注解或协议实现差异。
	var executable_path: String = OS.get_executable_path()
	# 当前项目绝对路径；Windows 与 Linux 环境均由 Godot 自身规范化，不手工拼接分隔符。
	var project_path: String = ProjectSettings.globalize_path("res://")
	# 派生客户端日志路径；写入项目缓存目录，便于房主超时时定位客户端 RPC 或脚本错误且不会进入版本控制。
	var client_log_path: String = project_path.path_join(".godot/lan_client_test.log")
	# 客户端参数；`--` 后内容只进入用户参数，测试脚本可稳定识别角色与端口。
	var client_arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path",
		project_path,
		"--log-file",
		client_log_path,
		"res://tests/lan_network_test.tscn",
		"--",
		"--lan-client",
		"--lan-port=%d" % _port,
	])
	# 派生客户端进程 ID；负值表示系统拒绝创建进程。
	var client_process_id: int = OS.create_process(executable_path, client_arguments, false)
	print("LAN_NETWORK_CLIENT_SPAWN pid=%d executable=%s project=%s" % [client_process_id, executable_path, project_path])
	if client_process_id < 0:
		_fail("client_process_create_failed")


## 启动测试客户端并连接本机房主；空闲端口由主进程参数传入。
func _start_client() -> void:
	if _port < NetworkGateway.SERVER_PEER_ID:
		_fail("client_missing_port")
		return
	# 客户端发起连接结果；最终成功仍需等待大厅快照与开局绑定。
	var join_error: Error = _gateway.join_lan("127.0.0.1", "客户端测试", _port, CLIENT_AVATAR_CHARACTER_ID, TEST_ROOM_PASSWORD)
	print("LAN_NETWORK_CLIENT_CONNECT port=%d error=%d" % [_port, join_error])
	if join_error != OK:
		_fail("client_join_error=%d" % join_error)


## 客户端登记后发送聊天与换位；房主确认两项权威结果、资料与密码隐私后才开始测试对局。
func _on_lobby_changed(lobby_snapshot: Dictionary) -> void:
	print("LAN_NETWORK_LOBBY role=%s count=%d active=%s" % ["client" if _is_client_process else "host", int(lobby_snapshot.get("member_count", -1)), bool(lobby_snapshot.get("match_active", false))])
	if int(lobby_snapshot.get("member_count", 0)) < 2:
		return
	if _is_client_process:
		_validate_client_lobby_and_send_actions(lobby_snapshot)
		return
	if _host_match_started or not _host_lobby_features_are_ready(lobby_snapshot):
		return
	# 真人玩家映射错误；测试要求2名真人按大厅位置进入4人总座位并留下2个 AI 空位。
	var assignment_error: String = _gateway.prepare_lan_match_assignments(TEST_PLAYER_COUNT)
	if not assignment_error.is_empty():
		_fail("assignment_error=%s" % assignment_error)
		return
	_host_match_started = true
	_gateway.begin_prepared_lan_match()
	# 远端映射；测试只有一个客户端，因此必须恰好存在一项。
	var remote_assignments: Dictionary = _gateway.get_remote_player_assignments()
	if remote_assignments.size() != 1:
		_fail("remote_assignment_count=%d" % remote_assignments.size())
		return
	# 客户端 peer_id；定向快照只能发给该连接，不能使用广播接口。
	var client_peer_id: int = int(remote_assignments.keys()[0])
	# 客户端稳定玩家 ID；写入快照供客户端核对观察者裁剪是否与开局绑定一致。
	var client_player_id: int = int(remote_assignments.get(client_peer_id, -1))
	_gateway.send_snapshot_to_peer({"viewer_id":client_player_id, "private_marker":"client_only"}, client_peer_id)


## 客户端校验公共大厅没有密码明文泄漏，确认双方形象后发送一次聊天与换位请求。
func _validate_client_lobby_and_send_actions(lobby_snapshot: Dictionary) -> void:
	if _client_sent_lobby_actions:
		return
	if str(lobby_snapshot.get("role", "")) != "client" or lobby_snapshot.has("room_password") or not bool(lobby_snapshot.get("has_password", false)) or int(lobby_snapshot.get("player_count", 0)) != TEST_PLAYER_COUNT:
		_fail("client_lobby_privacy=%s" % lobby_snapshot)
		return
	# 客户端收到的成员资料；公开字段应包含双方稳定形象 ID 与唯一大厅位置。
	var members: Array = lobby_snapshot.get("members", []) as Array
	# 按显示名索引的成员资料；测试不依赖 ENet 为客户端分配的动态 peer ID。
	var members_by_name: Dictionary = {}
	for member_variant: Variant in members:
		# 当前大厅成员；只读取协议公开资料，不保存字典引用到后续异步阶段。
		var member: Dictionary = member_variant as Dictionary
		members_by_name[str(member.get("display_name", ""))] = member.duplicate(true)
	if str((members_by_name.get("房主测试", {}) as Dictionary).get("avatar_character_id", "")) != HOST_AVATAR_CHARACTER_ID or str((members_by_name.get("客户端测试", {}) as Dictionary).get("avatar_character_id", "")) != CLIENT_AVATAR_CHARACTER_ID:
		_fail("client_avatar_snapshot=%s" % members)
		return
	_client_sent_lobby_actions = true
	_gateway.send_lan_lobby_chat_message(CLIENT_CHAT_MESSAGE)
	_gateway.request_lan_lobby_seat_change(CLIENT_TARGET_SEAT_INDEX)


## 房主确认密码私有值、客户端聊天署名和换位结果全部到达；未完成时继续等待下一份大厅快照。
func _host_lobby_features_are_ready(lobby_snapshot: Dictionary) -> bool:
	if lobby_snapshot.has("room_password") or not bool(lobby_snapshot.get("has_password", false)) or int(lobby_snapshot.get("player_count", 0)) != TEST_PLAYER_COUNT:
		_fail("host_public_lobby_privacy=%s" % lobby_snapshot)
		return false
	# 房主私有快照；只有显式请求且本机为房主时才允许包含密码明文。
	var private_snapshot: Dictionary = _gateway.get_lan_lobby_snapshot(true)
	if str(private_snapshot.get("room_password", "")) != TEST_ROOM_PASSWORD:
		_fail("host_private_password=%s" % private_snapshot)
		return false
	# 客户端成员；通过显示名查找，验证稳定形象 ID 与权威换位目标。
	var client_member: Dictionary = {}
	for member_variant: Variant in lobby_snapshot.get("members", []) as Array:
		# 当前成员资料；房主快照必须包含双方形象与唯一座位。
		var member: Dictionary = member_variant as Dictionary
		if str(member.get("display_name", "")) == "客户端测试":
			client_member = member
			break
	if client_member.is_empty() or str(client_member.get("avatar_character_id", "")) != CLIENT_AVATAR_CHARACTER_ID:
		_fail("host_client_avatar=%s" % lobby_snapshot.get("members", []))
		return false
	# 客户端聊天是否已经由房主权威署名；未到达时继续等待，不提前开局关闭大厅协议。
	var chat_received: bool = false
	for chat_variant: Variant in lobby_snapshot.get("chat_history", []) as Array:
		# 当前聊天记录；显示名来自成员表，正文已经由网关裁剪与换行清理。
		var chat_entry: Dictionary = chat_variant as Dictionary
		if str(chat_entry.get("display_name", "")) == "客户端测试" and str(chat_entry.get("message", "")) == CLIENT_CHAT_MESSAGE:
			chat_received = true
			break
	return chat_received and int(client_member.get("seat_index", -1)) == CLIENT_TARGET_SEAT_INDEX


## 客户端接收开局绑定；先保存稳定玩家 ID，等待后续私有快照验证后再发送测试动作。
func _on_match_started(local_player_id: int, player_count: int) -> void:
	if not _is_client_process:
		return
	if player_count != TEST_PLAYER_COUNT or local_player_id < 0 or local_player_id >= TEST_PLAYER_COUNT:
		_fail("invalid_match_assignment player_id=%d count=%d" % [local_player_id, player_count])
		return
	_local_player_id = local_player_id


## 客户端核对定向快照观察者后先发送伪造 actor；房主网关必须拒绝并返回 action_rejected 事件。
func _on_snapshot_received(snapshot: Dictionary) -> void:
	if not _is_client_process or _local_player_id < 0:
		return
	if int(snapshot.get("viewer_id", -1)) != _local_player_id or str(snapshot.get("private_marker", "")) != "client_only":
		_fail("private_snapshot_mismatch=%s" % [snapshot])
		return
	# 伪造玩家动作；选择一个与本地绑定不同但仍在4人范围内的 actor_id，验证网关在控制器前拦截。
	var spoofed_player_id: int = (_local_player_id + 1) % TEST_PLAYER_COUNT
	# 延迟一帧发送伪造动作；避免在 RPC 回调内部立即嵌套回传时被 SceneMultiplayer 丢弃。
	_send_spoofed_command.call_deferred(spoofed_player_id)


## 在当前快照 RPC 完成后发送伪造 actor 动作；房主必须拒绝并返回 action_rejected。
func _send_spoofed_command(spoofed_player_id: int) -> void:
	_gateway.send_command(PlayerAction.new("lan_test", spoofed_player_id))


## 房主只应收到 actor 已通过连接绑定校验的合法动作；收到后向客户端发送完成事件并输出通过标识。
func _on_command_received(command_data: Dictionary) -> void:
	if _is_client_process:
		return
	# 当前正确客户端玩家 ID；从同步回调中的发送者 peer_id 查询权威映射。
	var sender_peer_id: int = _gateway.get_current_incoming_peer_id()
	# 当前发送者绑定的稳定玩家 ID；用于确认合法动作未被 actor 防伪逻辑误拒绝。
	var expected_player_id: int = int(_gateway.get_remote_player_assignments().get(sender_peer_id, -1))
	if str(command_data.get("action_type", "")) != "lan_test" or int(command_data.get("actor_id", -1)) != expected_player_id:
		_fail("host_received_invalid_command=%s expected=%d" % [command_data, expected_player_id])
		return
	_gateway.send_game_event_to_peer("test_complete", {"actor_id":expected_player_id}, sender_peer_id)
	print("LAN_NETWORK_PASS host_actor=%d player_count=%d" % [expected_player_id, TEST_PLAYER_COUNT])
	_finish_after_delay()


## 客户端处理房主事件；防伪拒绝到达后发送正确 actor，完成事件到达后正常退出。
func _on_game_event_received(event_type: String, event_payload: Dictionary) -> void:
	if not _is_client_process:
		return
	if event_type == "action_rejected" and not _client_sent_valid_command:
		_client_sent_valid_command = true
		# 合法动作同样延迟到拒绝事件 RPC 结束后上行，保持测试与真实输入事件一致的异步边界。
		_send_valid_command.call_deferred()
		return
	if event_type == "test_complete":
		if int(event_payload.get("actor_id", -1)) != _local_player_id or not _client_sent_valid_command:
			_fail("client_complete_mismatch=%s" % [event_payload])
			return
		print("LAN_NETWORK_CLIENT_PASS actor=%d" % _local_player_id)
		_finish_client_after_delay()


## 在拒绝事件 RPC 返回后发送与当前连接绑定一致的合法 actor 动作。
func _send_valid_command() -> void:
	_gateway.send_command(PlayerAction.new("lan_test", _local_player_id))


## 任一测试进程意外失去会话时立即失败；正常结束由显式完成事件控制，不会触发该入口。
func _on_session_closed(message: String) -> void:
	_fail("session_closed=%s" % message)


## 输出网关连接生命周期；该诊断不参与断言，只用于区分 ENet 握手与 RPC 大厅登记失败。
func _on_connection_state_changed(is_connected: bool, message: String) -> void:
	print("LAN_NETWORK_STATE role=%s connected=%s message=%s" % ["client" if _is_client_process else "host", is_connected, message])


## 监控底层 MultiplayerPeer 连接状态变化；只打印枚举值，不主动改变会话生命周期。
func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	# 当前底层连接状态；DISCONNECTED、CONNECTING 与 CONNECTED 分别对应0、1、2。
	var connection_status: int = int(multiplayer.multiplayer_peer.get_connection_status())
	if connection_status != _last_connection_status:
		_last_connection_status = connection_status
		print("LAN_NETWORK_PEER_STATUS role=%s status=%d unique_id=%d" % ["client" if _is_client_process else "host", connection_status, multiplayer.get_unique_id()])


## 安装场景树超时节点；任何未完成握手、封包或进程派生都会在固定时间内返回非零结果。
func _install_timeout_guard() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = TEST_TIMEOUT_SECONDS
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)
	_timeout_timer.start()


## 超时节点回调；角色信息用于区分房主与派生客户端阻塞位置。
func _on_timeout() -> void:
	_fail("timeout role=%s" % ("client" if _is_client_process else "host"))


## 房主发送完成事件后短暂等待可靠包刷出，再正常退出测试场景。
func _finish_after_delay() -> void:
	await get_tree().create_timer(0.5).timeout
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit()


## 客户端完成验证后先释放 ENet，再等待一帧让 SceneMultiplayer 清理底层对象并正常退出。
func _finish_client_after_delay() -> void:
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit()


## 输出稳定失败标识并以非零状态退出；首个失败后 SceneTree 会终止后续异步任务。
func _fail(reason: String) -> void:
	printerr("LAN_NETWORK_FAIL %s" % reason)
	get_tree().quit(1)
