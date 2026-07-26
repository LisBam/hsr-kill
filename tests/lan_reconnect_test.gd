extends Node

## 局域网断线重连集成测试。以两个真实 ENet 进程验证：客户端在对局中意外断线后房主立即离线托管并登记座位预约，
## 客户端携会话令牌自动重连成功后恢复原稳定玩家 ID、解除离线托管，并重新收到私有裁剪快照。

## 双进程重连测试超时秒数；默认30秒覆盖建房、开局、断线感知、自动重连与快照回发全流程。
const TEST_TIMEOUT_SECONDS: float = 30.0

## 测试对局总人数；2名真人直接进入身份局，覆盖断线托管与重连交还的最小完整闭环。
const TEST_PLAYER_COUNT: int = 2

## 固定权威随机种子；保证选将候选与牌堆可复现，测试关注网络恢复流程而非规则内容。
const TEST_RANDOM_SEED: int = 20260726

## 客户端收到首份快照后到主动模拟断线的延迟秒数；默认0.3秒让开局信号与界面数据完整落地。
const CLIENT_DROP_DELAY_SECONDS: float = 0.3

## 房主完成全部断言后到退出进程的延迟秒数；默认0.5秒保证最后一批可靠封包完整刷出到客户端。
const HOST_FINISH_DELAY_SECONDS: float = 0.5

## 完整权威或远端控制器；客户端实例不创建 GameState，仅通过网络适配入口消费裁剪快照。
@onready var _controller: MatchController = $MatchController

## 对局控制器下的通信网关；房主建立 ENet 服务端，客户端连接、断线并携令牌自动重连。
@onready var _gateway: NetworkGateway = $MatchController/NetworkGateway

## 当前进程是否为派生客户端；由 `--lan-reconnect-client` 用户参数决定。
var _is_client_process: bool = false

## 本次测试端口；房主按 PID 选择，客户端从用户参数读取相同数值。
var _port: int = 0

## 客户端本地绑定的稳定玩家 ID；开局广播前为 -1，重连后必须恢复同一数值。
var _local_player_id: int = -1

## 房主是否已经创建权威对局；防止大厅快照重入重复调用 start_match。
var _host_match_started: bool = false

## 房主观察到的掉线玩家稳定 ID；断线信号触发前为 -1，重连断言必须针对同一玩家。
var _disconnected_player_id: int = -1

## 房主是否已经验证断线后的离线托管与座位预约；重连断言只有在该阶段完成后才有效。
var _host_disconnect_verified: bool = false

## 客户端是否已经触发过模拟断线；防止重连后的快照再次进入断线流程形成死循环。
var _client_drop_triggered: bool = false

## 客户端是否已经收到重连进行中的状态信号；成功信号必须发生在该标记之后才算完整流程。
var _client_reconnect_started: bool = false

## 客户端是否已经通过带 rejoined 标记的开局绑定包完成重连；此后第一份快照用于最终断言。
var _client_rejoined: bool = false

## 当前进程是否已经完成全部断言；完成后忽略会话关闭信号，避免对端正常收尾被误判为失败。
var _completed: bool = false

## 流程测试超时节点；随场景树释放，不保留等待中的异步函数状态。
var _timeout_timer: Timer


## 初始化控制器测试速度、连接信号和进程角色；所有组件先完成子节点 _ready 后再启动网络。
func _ready() -> void:
	_parse_user_arguments()
	# 本测试不包含房主人工调整AI的桌面入口；进程内关闭该阶段且不写入玩家设置文件。
	GameSettings.customize_ai_characters_enabled = false
	_controller.ai_action_delay_seconds = 0.0
	_controller.game_flow_interval_seconds = 0.0
	_gateway.lan_lobby_changed.connect(_on_lobby_changed)
	_gateway.lan_match_started.connect(_on_match_started)
	_gateway.lan_match_peer_disconnected.connect(_on_peer_disconnected_observed)
	_gateway.lan_match_peer_reconnected.connect(_on_peer_reconnected_observed)
	_gateway.lan_reconnect_state_changed.connect(_on_reconnect_state_changed)
	_gateway.snapshot_received.connect(_on_snapshot_received)
	_gateway.lan_session_closed.connect(_on_session_closed)
	_install_timeout_guard()
	if _is_client_process:
		_start_client()
	else:
		_start_host()


## 解析客户端角色与端口用户参数；其他 Godot 参数不进入测试业务。
func _parse_user_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--lan-reconnect-client":
			_is_client_process = true
		elif argument.begins_with("--lan-reconnect-port="):
			_port = argument.trim_prefix("--lan-reconnect-port=").to_int()


## 房主创建大厅并派生同版本无头客户端；RPC 节点路径在两个进程中保持一致。
func _start_host() -> void:
	_port = 46000 + (OS.get_process_id() % 9000)
	# ENet 建房结果；失败时不启动客户端，避免后续超时掩盖实际端口错误。
	var host_error: Error = _gateway.host_lan("重连测试房主", _port, "xier", "", TEST_PLAYER_COUNT)
	if host_error != OK:
		_fail("host_create_error=%d" % host_error)
		return
	# 当前引擎可执行路径；派生客户端必须与房主使用相同 Godot 版本。
	var executable_path: String = OS.get_executable_path()
	# 当前项目绝对路径；由 Godot 统一处理 Windows 盘符和目录分隔符。
	var project_path: String = ProjectSettings.globalize_path("res://")
	# 客户端缓存日志；不会进入 Git，失败时可独立检查远端重连信号顺序。
	var client_log_path: String = project_path.path_join(".godot/lan_reconnect_client.log")
	# 派生客户端参数；用户参数位于 `--` 后，避免与引擎参数冲突。
	var client_arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path",
		project_path,
		"--log-file",
		client_log_path,
		"res://tests/lan_reconnect_test.tscn",
		"--",
		"--lan-reconnect-client",
		"--lan-reconnect-port=%d" % _port,
	])
	# 客户端进程 ID；负值表示系统未能创建进程。
	var client_process_id: int = OS.create_process(executable_path, client_arguments, false)
	if client_process_id < 0:
		_fail("client_process_create_failed")


## 客户端连接本机房主；最终可操作身份与会话令牌由 match_start 定向封包分配。
func _start_client() -> void:
	if _port < 1024:
		_fail("client_missing_port")
		return
	# 发起客户端连接结果；OK 后继续等待异步大厅与开局信号。
	var join_error: Error = _gateway.join_lan("127.0.0.1", "重连测试客户端", _port, "himeko")
	if join_error != OK:
		_fail("client_join_error=%d" % join_error)


## 房主在2名真人登记后准备映射、创建权威对局并广播当前私有快照。
func _on_lobby_changed(lobby_snapshot: Dictionary) -> void:
	if _is_client_process or _host_match_started or int(lobby_snapshot.get("member_count", 0)) < 2:
		return
	# 真人座次准备错误；测试要求2名真人按大厅位置进入2人身份局。
	var assignment_error: String = _gateway.prepare_lan_match_assignments(TEST_PLAYER_COUNT)
	if not assignment_error.is_empty():
		_fail("assignment_error=%s" % assignment_error)
		return
	_host_match_started = true
	if not _controller.start_match(TEST_PLAYER_COUNT, TEST_RANDOM_SEED, "identity"):
		_fail("authoritative_start_failed")
		return
	_gateway.begin_prepared_lan_match()
	_controller.replicate_current_state()


## 双端开局绑定回调；客户端首次开局校验令牌并预约模拟断线，重连后的第二次绑定必须恢复同一玩家 ID。
func _on_match_started(local_player_id: int, player_count: int) -> void:
	if player_count != TEST_PLAYER_COUNT or local_player_id < 0 or local_player_id >= TEST_PLAYER_COUNT:
		_fail("invalid_assignment player_id=%d count=%d" % [local_player_id, player_count])
		return
	if not _is_client_process:
		_local_player_id = local_player_id
		return
	if _local_player_id < 0:
		_local_player_id = local_player_id
		_controller.local_human_player_id = local_player_id
		if not _gateway.has_lan_session_token():
			_fail("missing_session_token")
		return
	# 重连后的第二次开局绑定；稳定玩家 ID 必须与断线前一致，否则座位预约恢复错误。
	if local_player_id != _local_player_id:
		_fail("rejoined_player_id_mismatch before=%d after=%d" % [_local_player_id, local_player_id])
		return
	_client_rejoined = true


## 房主观察对局中掉线信号；延迟一帧断言权威控制器已写入离线托管并登记座位预约。
func _on_peer_disconnected_observed(player_id: int, _display_name: String) -> void:
	if _is_client_process:
		return
	_disconnected_player_id = player_id
	_verify_host_disconnect_state.call_deferred()


## 校验断线后的权威状态；离线托管、AI 注册与令牌预约都必须在断线回调链内同步完成。
func _verify_host_disconnect_state() -> void:
	# 掉线玩家的权威状态；控制器的断线回调应已在网关信号分发时同步写入托管标记。
	var player: PlayerState = _controller.state.get_player(_disconnected_player_id) if _controller.state != null else null
	if player == null or not player.auto_managed or not player.auto_managed_offline:
		_fail("offline_management_missing player=%d" % _disconnected_player_id)
		return
	if _gateway.get_reserved_lan_seat_count() != 1:
		_fail("seat_reservation_missing count=%d" % _gateway.get_reserved_lan_seat_count())
		return
	_host_disconnect_verified = true


## 房主观察重连成功信号；延迟一帧断言托管解除、连接重绑与预约清空，然后完成房主侧测试。
func _on_peer_reconnected_observed(player_id: int, _display_name: String) -> void:
	if _is_client_process:
		return
	if not _host_disconnect_verified or player_id != _disconnected_player_id:
		_fail("unexpected_reconnect player=%d verified=%s" % [player_id, _host_disconnect_verified])
		return
	_verify_host_reconnect_state.call_deferred()


## 校验重连后的权威状态；掉线玩家恢复真人控制、绑定新连接且预约表清空后输出房主通过标识。
func _verify_host_reconnect_state() -> void:
	# 重连玩家的权威状态；控制器的重连回调应已解除离线托管并注销基础 AI。
	var player: PlayerState = _controller.state.get_player(_disconnected_player_id) if _controller.state != null else null
	if player == null or player.auto_managed or player.auto_managed_offline:
		_fail("offline_management_not_restored player=%d" % _disconnected_player_id)
		return
	if _gateway.get_peer_id_for_player(_disconnected_player_id) <= NetworkGateway.SERVER_PEER_ID:
		_fail("peer_binding_not_restored")
		return
	if _gateway.get_reserved_lan_seat_count() != 0:
		_fail("seat_reservation_not_cleared count=%d" % _gateway.get_reserved_lan_seat_count())
		return
	_completed = true
	print("LAN_RECONNECT_HOST_PASS player=%d" % _disconnected_player_id)
	_finish_host_after_delay()


## 客户端跟踪断线自动重连状态信号；重连成功信号必须出现在重连进行信号之后。
func _on_reconnect_state_changed(reconnecting: bool, _message: String) -> void:
	if not _is_client_process:
		return
	if reconnecting:
		_client_reconnect_started = true
		return
	if not _client_reconnect_started:
		_fail("reconnect_finished_without_start")


## 客户端消费私有快照；首份快照触发模拟断线，重连后的首份快照断言托管解除并完成客户端测试。
func _on_snapshot_received(snapshot_data: Dictionary) -> void:
	if not _is_client_process or _completed:
		return
	if not _client_drop_triggered:
		_client_drop_triggered = true
		_schedule_client_drop()
		return
	if not _client_rejoined:
		return
	# 快照中的本地玩家条目；重连后房主已解除托管，观察者快照必须同步恢复两个托管字段。
	var local_player_snapshot: Dictionary = {}
	for player_variant: Variant in snapshot_data.get("players", []) as Array:
		# 当前观察者可见的玩家快照；只读取本地玩家的公开托管状态字段。
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) == _local_player_id:
			local_player_snapshot = player_snapshot
			break
	if local_player_snapshot.is_empty():
		_fail("rejoined_snapshot_missing_local_player")
		return
	if bool(local_player_snapshot.get("auto_managed", true)) or bool(local_player_snapshot.get("auto_managed_offline", true)):
		# 重连瞬间可能仍收到托管解除之前的快照；等待房主随托管解除动作补发的下一份快照。
		return
	if snapshot_data.has("random_seed"):
		_fail("random_seed_leaked_after_rejoin")
		return
	_completed = true
	print("LAN_RECONNECT_CLIENT_PASS player=%d" % _local_player_id)
	_finish_client_after_delay()


## 在开局数据完整落地后模拟一次意外断线；关闭底层 ENet 并进入与真实断线相同的自动重连流程。
func _schedule_client_drop() -> void:
	await get_tree().create_timer(CLIENT_DROP_DELAY_SECONDS).timeout
	_gateway.simulate_lan_connection_drop()


## 任一进程在断言完成前意外失去局域网会话即失败；正常收尾使用空消息 leave_lan 不触发该信号。
func _on_session_closed(message: String) -> void:
	if _completed:
		return
	_fail("session_closed=%s" % message)


## 安装固定超时节点；断线感知、重连重试或快照缺失卡住时稳定返回非零退出码。
func _install_timeout_guard() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = TEST_TIMEOUT_SECONDS
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)
	_timeout_timer.start()


## 流程测试超时回调；输出当前进程角色与阶段标记后终止。
func _on_timeout() -> void:
	_fail("timeout role=%s drop=%s reconnect_started=%s rejoined=%s host_disconnect=%s" % [
		"client" if _is_client_process else "host",
		_client_drop_triggered,
		_client_reconnect_started,
		_client_rejoined,
		_host_disconnect_verified,
	])


## 房主完成断言后等待可靠包刷出，再释放权威状态与 ENet 并正常退出。
func _finish_host_after_delay() -> void:
	await get_tree().create_timer(HOST_FINISH_DELAY_SECONDS).timeout
	_controller.abandon_match()
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit()


## 客户端完成断言后释放 ENet 并等待一帧，确保远端控制器与 SceneMultiplayer 不遗留活动对象。
func _finish_client_after_delay() -> void:
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit()


## 输出稳定失败标识并终止当前测试进程；失败路径不继续推进对局或重连。
func _fail(reason: String) -> void:
	printerr("LAN_RECONNECT_FAIL role=%s %s" % ["client" if _is_client_process else "host", reason])
	_gateway.leave_lan("")
	get_tree().quit(1)
