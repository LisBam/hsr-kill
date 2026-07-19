extends Node

## 局域网踢出冷却集成测试。以两个真实 ENet 进程验证同一地址被踢后立即重连被拒绝，5秒后可以再次进入大厅。

## 整个踢出重连流程的超时秒数；默认14秒覆盖两次握手、5秒冷却和可靠拒绝消息。
const TEST_TIMEOUT_SECONDS: float = 14.0

## 冷却结束后的额外等待秒数；默认0.25秒避免单调时钟刚好处于5秒边界时产生偶发失败。
const COOLDOWN_SETTLE_SECONDS: float = 0.25

## 房主大厅密码；两次客户端连接都使用相同密码，确保第二次拒绝只能来自踢出冷却。
const ROOM_PASSWORD: String = "kick-rejoin-test"

## 测试使用的局域网网关；主进程创建房间，派生进程按用户参数作为客户端运行。
@onready var _gateway: NetworkGateway = $NetworkGateway

## 当前进程是否为派生客户端；由用户参数区分，避免共享临时文件或环境变量。
var _is_client_process: bool = false

## 本次 ENet 监听端口；房主按进程 ID 选择，客户端从启动参数读取。
var _port: int = 0

## 房主是否已对首次加入的远端成员执行踢出；防止大厅快照重入重复踢出。
var _kick_sent: bool = false

## 客户端是否已经尝试过立即重连；第二次会话关闭必须是带剩余秒数的冷却拒绝。
var _immediate_rejoin_sent: bool = false

## 客户端是否已经收到踢出冷却拒绝；只有此标记成立后再次进入大厅才算验证完成。
var _cooldown_rejected: bool = false

## 测试流程的超时计时器；正常完成前一直保留，任一步卡住都会输出稳定失败原因。
var _timeout_timer: Timer


## 初始化角色、信号与超时保护，然后启动房主或客户端流程。
func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--lan-kick-rejoin-client":
			_is_client_process = true
		elif argument.begins_with("--lan-kick-rejoin-port="):
			_port = argument.trim_prefix("--lan-kick-rejoin-port=").to_int()
	_gateway.lan_lobby_changed.connect(_on_lobby_changed)
	_gateway.lan_session_closed.connect(_on_session_closed)
	_install_timeout()
	if _is_client_process:
		_start_client()
	else:
		_start_host()


## 创建房主房间并派生同版本无头客户端；RPC 节点路径在两个进程中保持一致。
func _start_host() -> void:
	# 当前端口；高位端口降低与开发服务或其他并行测试冲突的概率。
	_port = 44000 + (OS.get_process_id() % 9000)
	if _gateway.host_lan("踢出测试房主", _port, "xier", ROOM_PASSWORD, 2) != OK:
		_fail("host_create")
		return
	# 当前 Godot 可执行路径；派生进程使用同一引擎，避免 ENet 或脚本版本差异。
	var executable_path: String = OS.get_executable_path()
	# 当前项目物理路径；传入 --path 后客户端可以加载同一份测试场景。
	var project_path: String = ProjectSettings.globalize_path("res://")
	# 客户端启动参数；-- 后参数只由本测试脚本解析，不传给 Godot 引擎。
	var client_arguments: PackedStringArray = PackedStringArray(["--headless", "--path", project_path, "res://tests/lan_kick_rejoin_test.tscn", "--", "--lan-kick-rejoin-client", "--lan-kick-rejoin-port=%d" % _port])
	if OS.create_process(executable_path, client_arguments, false) < 0:
		_fail("client_spawn")


## 使用房主端口发起首次客户端连接；登记成功后由房主触发正式踢出。
func _start_client() -> void:
	if _port < 1024 or _gateway.join_lan("127.0.0.1", "踢出测试客户端", _port, "himeko", ROOM_PASSWORD) != OK:
		_fail("client_first_join")


## 处理大厅快照：房主踢出首次成员并验证冷却后的再次加入，客户端仅在已收到冷却拒绝后确认成功。
func _on_lobby_changed(lobby_snapshot: Dictionary) -> void:
	if _is_client_process:
		if _cooldown_rejected and int(lobby_snapshot.get("member_count", 0)) == 2:
			print("LAN_KICK_REJOIN_CLIENT_PASS")
			_gateway.leave_lan("")
			await get_tree().process_frame
			get_tree().quit(0)
		return
	if int(lobby_snapshot.get("member_count", 0)) < 2:
		return
	if not _kick_sent:
		# 当前远端成员 peer；房主固定为1，找到首个大于1的成员后执行一次真实踢出。
		var remote_peer_id: int = 0
		for member_variant: Variant in lobby_snapshot.get("members", []) as Array:
			# 当前公共大厅成员；仅 peer ID 用于房主踢出入口，不读取或伪造其他网络映射。
			var member: Dictionary = member_variant as Dictionary
			var peer_id: int = int(member.get("peer_id", 0))
			if peer_id > NetworkGateway.SERVER_PEER_ID:
				remote_peer_id = peer_id
				break
		if remote_peer_id <= NetworkGateway.SERVER_PEER_ID or not _gateway.kick_lan_lobby_member(remote_peer_id).is_empty():
			_fail("host_kick")
			return
		_kick_sent = true
		return
	print("LAN_KICK_REJOIN_HOST_PASS")
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit(0)


## 处理客户端被房主拒绝后的两个阶段：第一次立即重连，第二次验证冷却提示后等待5秒再重连。
func _on_session_closed(message: String) -> void:
	if not _is_client_process:
		return
	if not _immediate_rejoin_sent:
		_immediate_rejoin_sent = true
		_rejoin_immediately.call_deferred()
		return
	if not message.contains("请在") or not message.contains("秒后再加入"):
		_fail("missing_cooldown_message=%s" % message)
		return
	_cooldown_rejected = true
	_rejoin_after_cooldown()


## 在本帧会话关闭回调结束后立即发起重连；该连接必须被房主按地址冷却拒绝。
func _rejoin_immediately() -> void:
	if _gateway.join_lan("127.0.0.1", "踢出测试客户端", _port, "himeko", ROOM_PASSWORD) != OK:
		_fail("immediate_rejoin_transport")


## 等待完整5秒加测试余量后再次连接；此时房主应删除过期地址记录并正常登记成员。
func _rejoin_after_cooldown() -> void:
	await get_tree().create_timer(float(NetworkGateway.KICK_REJOIN_COOLDOWN_MSEC) / 1000.0 + COOLDOWN_SETTLE_SECONDS).timeout
	if _gateway.join_lan("127.0.0.1", "踢出测试客户端", _port, "himeko", ROOM_PASSWORD) != OK:
		_fail("delayed_rejoin_transport")


## 安装流程超时保护；两个进程任一未在预期窗口结束时都会输出角色与阶段无关的失败标识。
func _install_timeout() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = TEST_TIMEOUT_SECONDS
	_timeout_timer.timeout.connect(func() -> void: _fail("timeout"))
	add_child(_timeout_timer)
	_timeout_timer.start()


## 释放当前会话并以非零状态结束；房主和客户端均可独立失败，不依赖对方进程收尾。
func _fail(reason: String) -> void:
	printerr("LAN_KICK_REJOIN_FAIL role=%s %s" % ["client" if _is_client_process else "host", reason])
	_gateway.leave_lan("")
	get_tree().quit(1)
