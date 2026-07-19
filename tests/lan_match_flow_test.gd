extends Node

## 局域网权威对局集成测试。房主运行完整 MatchController，客户端只消费裁剪快照并通过网络提交选将动作。

## 双进程对局测试超时秒数；默认20秒覆盖数据扫描、选将、AI延迟关闭后的起始发牌与快照确认。
const TEST_TIMEOUT_SECONDS: float = 20.0

## 测试对局总人数；2名真人加2名 AI 可同时覆盖真人映射、AI选将和私有手牌裁剪。
const TEST_PLAYER_COUNT: int = 4

## 固定权威随机种子；保证身份、牌堆和候选生成可复现，客户端快照仍不得收到该数值。
const TEST_RANDOM_SEED: int = 20260719

## 完整权威或远端控制器；客户端实例不创建 GameState，只通过其网络适配入口驱动 UI 信号。
@onready var _controller: MatchController = $MatchController

## 对局控制器下的通信网关；房主建立 ENet 服务端，客户端连接并消费定向快照。
@onready var _gateway: NetworkGateway = $MatchController/NetworkGateway

## 当前进程是否为派生客户端；由 `--lan-flow-client` 用户参数决定。
var _is_client_process: bool = false

## 本次测试端口；房主按 PID 选择，客户端从用户参数读取相同数值。
var _port: int = 0

## 客户端或房主本地绑定的稳定玩家 ID；开局广播前为 -1。
var _local_player_id: int = -1

## 房主是否已经创建权威对局；防止大厅快照重入重复调用 start_match。
var _host_match_started: bool = false

## 当前进程是否已经提交自己的选将；每个真人每局只允许提交一次候选 ID。
var _character_selection_submitted: bool = false

## 客户端是否已经在收到起始手牌快照后发送确认动作；防止连续状态快照重复确认。
var _client_snapshot_acknowledged: bool = false

## 流程测试超时节点；随场景树释放，不保留等待中的异步函数状态。
var _timeout_timer: Timer


## 初始化控制器测试速度、连接信号和进程角色；所有组件先完成子节点 _ready 后再启动网络。
func _ready() -> void:
	_parse_user_arguments()
	_controller.ai_action_delay_seconds = 0.0
	_controller.game_flow_interval_seconds = 0.0
	_gateway.lan_lobby_changed.connect(_on_lobby_changed)
	_gateway.lan_match_started.connect(_on_match_started)
	_gateway.command_received.connect(_on_gateway_command_received)
	_gateway.game_event_received.connect(_on_game_event_received)
	_gateway.lan_session_closed.connect(_on_session_closed)
	_controller.character_selection_changed.connect(_on_character_selection_changed)
	_controller.card_choice_requested.connect(_on_card_choice_requested)
	_controller.state_changed.connect(_on_state_changed)
	_install_timeout_guard()
	if _is_client_process:
		_start_client()
	else:
		_start_host()


## 解析客户端角色与端口用户参数；其他 Godot 参数不进入测试业务。
func _parse_user_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--lan-flow-client":
			_is_client_process = true
		elif argument.begins_with("--lan-flow-port="):
			_port = argument.trim_prefix("--lan-flow-port=").to_int()


## 房主创建大厅并派生同版本客户端进程；客户端日志写入 .godot 缓存用于失败诊断。
func _start_host() -> void:
	_port = 29000 + (OS.get_process_id() % 9000)
	# ENet 建房结果；失败时不启动客户端，避免后续超时掩盖实际端口错误。
	var host_error: Error = _gateway.host_lan("权威房主", _port, "xier", "", TEST_PLAYER_COUNT)
	if host_error != OK:
		_fail("host_create_error=%d" % host_error)
		return
	# 当前引擎可执行路径；派生客户端必须与房主使用相同 Godot 版本。
	var executable_path: String = OS.get_executable_path()
	# 当前项目绝对路径；由 Godot 统一处理 Windows 盘符和目录分隔符。
	var project_path: String = ProjectSettings.globalize_path("res://")
	# 客户端缓存日志；不会进入 Git，失败时可独立检查远端控制器信号。
	var client_log_path: String = project_path.path_join(".godot/lan_match_flow_client.log")
	# 派生客户端参数；用户参数位于 `--` 后，避免与引擎参数冲突。
	var client_arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path",
		project_path,
		"--log-file",
		client_log_path,
		"res://tests/lan_match_flow_test.tscn",
		"--",
		"--lan-flow-client",
		"--lan-flow-port=%d" % _port,
	])
	# 客户端进程 ID；负值表示系统未能创建进程。
	var client_process_id: int = OS.create_process(executable_path, client_arguments, false)
	if client_process_id < 0:
		_fail("client_process_create_failed")


## 客户端连接本机房主；最终可操作身份由 match_start 定向封包分配。
func _start_client() -> void:
	if _port < 1024:
		_fail("client_missing_port")
		return
	# 发起客户端连接结果；OK 后继续等待异步大厅与开局信号。
	var join_error: Error = _gateway.join_lan("127.0.0.1", "远端真人", _port, "himeko")
	if join_error != OK:
		_fail("client_join_error=%d" % join_error)


## 房主在2名真人登记后准备4人映射、创建权威对局并广播当前私有选将快照。
func _on_lobby_changed(lobby_snapshot: Dictionary) -> void:
	if _is_client_process or _host_match_started or int(lobby_snapshot.get("member_count", 0)) < 2:
		return
	# 真人座次准备错误；测试要求2名真人按大厅位置进入4人局并由 AI 补齐空位。
	var assignment_error: String = _gateway.prepare_lan_match_assignments(TEST_PLAYER_COUNT)
	if not assignment_error.is_empty():
		_fail("assignment_error=%s" % assignment_error)
		return
	_host_match_started = true
	if not _controller.start_match(TEST_PLAYER_COUNT, TEST_RANDOM_SEED):
		_fail("authoritative_start_failed")
		return
	_gateway.begin_prepared_lan_match()
	_controller.replicate_current_state()


## 客户端绑定房主按大厅位置分配的稳定玩家 ID；远端控制器随后会把全部 UI 动作上行而不访问本地 state。
func _on_match_started(local_player_id: int, player_count: int) -> void:
	if player_count != TEST_PLAYER_COUNT or local_player_id < 0 or local_player_id >= TEST_PLAYER_COUNT:
		_fail("invalid_assignment player_id=%d count=%d" % [local_player_id, player_count])
		return
	_local_player_id = local_player_id
	if _is_client_process:
		_controller.local_human_player_id = local_player_id


## 真人收到自己的裁剪选将快照后选择首张候选；房主与客户端都通过统一 PlayerAction 提交。
func _on_character_selection_changed(selection_snapshot: Dictionary) -> void:
	if _character_selection_submitted or not bool(selection_snapshot.get("can_select", false)):
		return
	# 当前真人私有候选；必须至少有1项，且只有该观察者能收到具体稳定武将 ID。
	var local_candidates: Array = selection_snapshot.get("local_candidates", []) as Array
	if local_candidates.is_empty():
		_fail("missing_private_character_candidates")
		return
	_character_selection_submitted = true
	# 选将动作；客户端 submit_action 只上行，房主 submit_action 直接进入同一权威校验。
	var action: PlayerAction = PlayerAction.new("select_character", int(selection_snapshot.get("local_player_id", _controller.local_human_player_id)))
	action.payload = {"character_id":str(local_candidates[0])}
	_controller.submit_action(action)


## 自动取消测试中由随机武将触发的可选技能询问；该流程测试只验证联网状态，不测试具体技能收益选择。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	# 当前选择者；房主和客户端只处理属于各自本地真人的请求，其他真人请求由对应网络进程处理。
	var chooser_id: int = int(choice_data.get("chooser_id", choice_data.get("actor_id", -1)))
	if chooser_id != _controller.local_human_player_id or not bool(choice_data.get("allow_cancel", choice_data.get("can_cancel", false))):
		return
	# 取消选择动作；空候选与 confirmed=false 表示不发动当前可选技能，不改变测试的网络关注点。
	var cancel_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	cancel_action.payload = {
		"request_id":int(choice_data.get("request_id", -1)),
		"selected_card_uids":[],
		"selected_target_ids":[],
		"selected_button_ids":[],
		"selected_control_id":"",
		"confirmed":false,
	}
	_submit_optional_choice_cancel.call_deferred(cancel_action)


## 在选择信号分发结束后提交取消动作；避免同一规则回调栈内重入当前选择请求。
func _submit_optional_choice_cancel(cancel_action: PlayerAction) -> void:
	_controller.submit_action(cancel_action)


## 客户端在选将完成后的状态快照中验证私有手牌、他人隐藏手牌和随机种子裁剪，然后发送确认动作。
func _on_state_changed(snapshot: Dictionary) -> void:
	if not _is_client_process or _client_snapshot_acknowledged or _local_player_id < 0 or str(snapshot.get("current_phase", "")) == "character_selection":
		return
	# 本地玩家快照；必须包含与 hand_count 相等的完整牌面数组。
	var local_player_snapshot: Dictionary = {}
	for player_variant: Variant in snapshot.get("players", []) as Array:
		# 当前观察者可见的玩家快照；非本地玩家的 hand 数组必须保持为空。
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) == _local_player_id:
			local_player_snapshot = player_snapshot
		elif not (player_snapshot.get("hand", []) as Array).is_empty():
			_fail("opponent_private_hand_leaked player=%d" % int(player_snapshot.get("player_id", -1)))
			return
	if local_player_snapshot.is_empty():
		return
	# 本地完整手牌；标准身份局起始发4张，当前测试没有修改 gameDraw 数值的内容。
	var private_hand: Array = local_player_snapshot.get("hand", []) as Array
	# 快照声明的本地手牌数量；必须与实际下发的私有 hand 数组长度一致。
	var private_hand_count: int = int(local_player_snapshot.get("hand_count", -1))
	if private_hand_count < 4 or private_hand.size() != private_hand_count:
		return
	if snapshot.has("random_seed"):
		_fail("random_seed_leaked")
		return
	_client_snapshot_acknowledged = true
	# 快照确认动作；属于测试专用未知动作，权威规则会拒绝，但网关应先验证 actor 并让测试观察者收到同一上行包。
	var acknowledgement: PlayerAction = PlayerAction.new("lan_snapshot_ack", _local_player_id)
	acknowledgement.payload = {"hand_count":private_hand_count}
	# 延迟到状态快照 RPC 回调结束后上行，避免嵌套 RPC 在同一调用栈中被 SceneMultiplayer 丢弃。
	_submit_snapshot_acknowledgement.call_deferred(acknowledgement)


## 在客户端完成本帧状态信号分发后提交快照确认动作；真实 UI 输入同样发生在后续输入帧。
func _submit_snapshot_acknowledgement(acknowledgement: PlayerAction) -> void:
	_controller.submit_action(acknowledgement)


## 房主观察通过连接绑定校验的测试确认动作，并核对权威端确有同样数量的客户端手牌。
func _on_gateway_command_received(command_data: Dictionary) -> void:
	if _is_client_process or str(command_data.get("action_type", "")) != "lan_snapshot_ack":
		return
	# 当前远端发送者与绑定玩家；网关在发出信号前已拒绝任何 actor 不匹配包。
	var sender_peer_id: int = _gateway.get_current_incoming_peer_id()
	# 确认动作声明的稳定玩家 ID；应与当前网络 peer 的权威绑定完全一致。
	var actor_id: int = int(command_data.get("actor_id", -1))
	if int(_gateway.get_remote_player_assignments().get(sender_peer_id, -2)) != actor_id:
		_fail("ack_actor_binding_mismatch")
		return
	# 权威客户端玩家状态；手牌数量必须与客户端裁剪快照确认值一致。
	var authoritative_player: PlayerState = _controller.state.get_player(actor_id)
	# 客户端从私有快照确认的手牌数量；仅用于测试核对，不参与正式规则结算。
	var acknowledged_hand_count: int = int((command_data.get("payload", {}) as Dictionary).get("hand_count", -1))
	if authoritative_player == null or authoritative_player.hand.size() != acknowledged_hand_count:
		_fail("ack_hand_count_mismatch authoritative=%d client=%d" % [authoritative_player.hand.size() if authoritative_player != null else -1, acknowledged_hand_count])
		return
	_gateway.send_game_event_to_peer("lan_match_flow_complete", {"actor_id":actor_id, "hand_count":acknowledged_hand_count}, sender_peer_id)
	print("LAN_MATCH_FLOW_PASS actor=%d hand_count=%d phase=%s" % [actor_id, acknowledged_hand_count, _controller.state.current_phase])
	_finish_host_after_delay()


## 客户端收到房主完成事件后核对自身 actor 与手牌数量，并正常关闭 ENet 会话。
func _on_game_event_received(event_type: String, event_payload: Dictionary) -> void:
	if not _is_client_process or event_type != "lan_match_flow_complete":
		return
	if int(event_payload.get("actor_id", -1)) != _local_player_id or int(event_payload.get("hand_count", -1)) < 4:
		_fail("client_complete_mismatch=%s" % [event_payload])
		return
	print("LAN_MATCH_FLOW_CLIENT_PASS actor=%d" % _local_player_id)
	_finish_client_after_delay()


## 任一进程意外失去局域网会话时立即失败；正常测试结束会先主动 leave_lan 且不发关闭信号。
func _on_session_closed(message: String) -> void:
	_fail("session_closed=%s" % message)


## 安装固定超时节点；选择等待、快照缺失或客户端崩溃都会稳定返回非零退出码。
func _install_timeout_guard() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = TEST_TIMEOUT_SECONDS
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)
	_timeout_timer.start()


## 流程测试超时回调；输出当前进程角色后终止。
func _on_timeout() -> void:
	_fail("timeout role=%s" % ("client" if _is_client_process else "host"))


## 房主发送完成事件后等待可靠包刷出，再释放 ENet 与权威状态并正常退出。
func _finish_host_after_delay() -> void:
	await get_tree().create_timer(0.5).timeout
	_controller.abandon_match()
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit()


## 客户端完成流程后释放 ENet 并等待一帧，确保远端控制器与 SceneMultiplayer 不遗留活动对象。
func _finish_client_after_delay() -> void:
	_gateway.leave_lan("")
	await get_tree().process_frame
	get_tree().quit()


## 输出稳定失败标识并终止当前测试进程；失败路径不继续推进对局或 AI。
func _fail(reason: String) -> void:
	printerr("LAN_MATCH_FLOW_FAIL %s" % reason)
	get_tree().quit(1)
