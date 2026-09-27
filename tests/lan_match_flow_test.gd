extends Node

## 局域网权威对局集成测试。房主运行完整 MatchController，客户端只消费裁剪快照并通过网络提交选将动作。

## 双进程对局测试超时秒数；默认30秒覆盖数据扫描、选将、AI延迟关闭后的起始发牌、快照确认，
## 以及同一房间内重开新对局后客户端重新选将并再次确认快照的完整往返。
const TEST_TIMEOUT_SECONDS: float = 30.0

## 测试对局总人数；2名真人加2名 AI 可同时覆盖真人映射、AI选将和私有手牌裁剪。
const TEST_PLAYER_COUNT: int = 4

## 固定权威随机种子；保证身份、牌堆和候选生成可复现，客户端快照仍不得收到该数值。
const TEST_RANDOM_SEED: int = 20260719

## 首次开局的客户端快照确认动作类型；房主据此进入“同房重开”验证步骤。
const INITIAL_ACK_ACTION_TYPE: String = "lan_snapshot_ack"

## 同房重开后的客户端快照确认动作类型；房主收到即证明重播的开局绑定已经到达客户端。
const RESTART_ACK_ACTION_TYPE: String = "lan_restart_ack"

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

## 最近一次已经提交的选将阶段；阶段从领袖先选切换到最终自选后允许同一真人再次提交。
## 真人首任领袖现在一次性确认且不会再次提交；阶段记录仍用于普通真人在不同开局阶段收到新权限时去重。
var _last_submitted_character_selection_phase: String = ""

## 客户端是否已经在收到起始手牌快照后发送确认动作；防止连续状态快照重复确认。
var _client_snapshot_acknowledged: bool = false

## 客户端已经确认过的对局 ID；仅用于诊断输出，不作为确认去重依据。
var _client_acknowledged_match_id: String = ""

## 客户端已经确认过的开局绑定序号；同房重开即使在同一秒内生成相同对局 ID 也能重新获得一次确认机会。
var _acknowledged_match_start_count: int = 0

## 客户端收到的开局绑定次数；同房重开必须让该计数从1增加到2，用于断言房主确实重播了开局绑定。
var _match_start_count: int = 0

## 房主触发同房重开后的新对局 ID；客户端确认该对局即证明重播发生在权威重开之后。
var _host_restarted_match_id: String = ""

## 房主是否已经发起过一次同房重开；防止确认链在重开后重复触发新的权威对局。
var _host_restart_requested: bool = false

## 流程测试超时节点；随场景树释放，不保留等待中的异步函数状态。
var _timeout_timer: Timer


## 初始化控制器测试速度、连接信号和进程角色；所有组件先完成子节点 _ready 后再启动网络。
func _ready() -> void:
	_parse_user_arguments()
	# 本测试不包含房主人工调整AI的桌面入口；仅覆盖联网选将和私有手牌，因此直接关闭进程内该阶段且不写入玩家设置文件。
	GameSettings.customize_ai_characters_enabled = false
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
	# 本次开局绑定序号；同房重开时房主会重播开局绑定，客户端必须收到第二次且保持同一稳定玩家 ID。
	_match_start_count += 1
	if _match_start_count > 1 and local_player_id != _local_player_id:
		_fail("restart_assignment_changed first=%d second=%d" % [_local_player_id, local_player_id])
		return
	_local_player_id = local_player_id
	# 同房重开进入新的选将阶段；复位提交去重状态，使两名真人能在第二局重新各提交一次候选。
	_character_selection_submitted = false
	_last_submitted_character_selection_phase = ""
	if _is_client_process:
		_controller.local_human_player_id = local_player_id


## 真人收到自己的裁剪选将快照后选择首张候选；房主与客户端都通过统一 PlayerAction 提交。
func _on_character_selection_changed(selection_snapshot: Dictionary) -> void:
	# 当前选将阶段；同一阶段只提交一次，阶段推进后恢复一次新的合法提交机会。
	var selection_phase: String = str(selection_snapshot.get("phase", ""))
	if (_character_selection_submitted and _last_submitted_character_selection_phase == selection_phase) or not bool(selection_snapshot.get("can_select", false)):
		return
	# 当前真人私有候选；普通玩家至少有1项，首任领袖最终自选则以显式保留字段复用已公开武将。
	# 保留字段只兼容房主内部AI延后分配；联网真人首任领袖的首次快照已经携带完整座次身份按钮。
	var local_candidates: Array = selection_snapshot.get("local_candidates", []) as Array
	# 本次提交武将ID；首任领袖只补交座次身份时读取已锁定结果，其他玩家继续选择首张私有候选。
	var selected_character_id: String = str(selection_snapshot.get("local_selected_character_id", "")) if bool(selection_snapshot.get("retains_selected_character", false)) else (str(local_candidates[0]) if not local_candidates.is_empty() else "")
	if selected_character_id.is_empty():
		_fail("missing_private_character_candidates")
		return
	_character_selection_submitted = true
	_last_submitted_character_selection_phase = selection_phase
	# 选将动作；客户端 submit_action 只上行，房主 submit_action 直接进入同一权威校验。
	var action: PlayerAction = PlayerAction.new("select_character", int(selection_snapshot.get("local_player_id", _controller.local_human_player_id)))
	action.payload = {"character_id":selected_character_id}
	if bool(selection_snapshot.get("allow_custom_assignment", false)):
		# 当前真人稳定ID、首任领袖ID与首次身份；按ID顺序映射到除一号位外的座次，领袖仍固定一号位。
		var local_player_id: int = int(selection_snapshot.get("local_player_id", _controller.local_human_player_id))
		# 首任领袖稳定ID；第一次身份在最终自选中保持不变时仍对应最终一号位。
		var leader_player_id: int = int(selection_snapshot.get("leader_player_id", -1))
		# 本地第一次身份；测试按原身份提交可覆盖完整名额且不会产生身份冲突。
		var local_identity: String = str(selection_snapshot.get("local_identity", ""))
		# 本地最终座次；非领袖按稳定ID跳过一号位后顺序映射到2号位及以后。
		var selected_seat_number: int = 1 if local_identity == "leader" else local_player_id + 2 if local_player_id < leader_player_id else local_player_id + 1
		action.payload["seat_number"] = selected_seat_number
		action.payload["identity"] = local_identity
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
	# 当前对局 ID；仅用于诊断输出，确认去重改用开局绑定序号，避免同一秒内重开得到相同对局 ID 时漏发确认。
	var snapshot_match_id: String = str(snapshot.get("match_id", ""))
	if not _is_client_process or _local_player_id < 0 or str(snapshot.get("current_phase", "")) == "character_selection" or _match_start_count <= _acknowledged_match_start_count:
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
	_client_acknowledged_match_id = snapshot_match_id
	_acknowledged_match_start_count = _match_start_count
	# 快照确认动作；属于测试专用未知动作，权威规则会拒绝，但网关应先验证 actor 并让测试观察者收到同一上行包。
	# 同房重开使用独立动作类型，房主据此区分首次开局确认与重开后开局绑定重播确认。
	var acknowledgement: PlayerAction = PlayerAction.new(RESTART_ACK_ACTION_TYPE if _match_start_count > 1 else INITIAL_ACK_ACTION_TYPE, _local_player_id)
	acknowledgement.payload = {"hand_count":private_hand_count}
	# 延迟到状态快照 RPC 回调结束后上行，避免嵌套 RPC 在同一调用栈中被 SceneMultiplayer 丢弃。
	_submit_snapshot_acknowledgement.call_deferred(acknowledgement)


## 在客户端完成本帧状态信号分发后提交快照确认动作；真实 UI 输入同样发生在后续输入帧。
func _submit_snapshot_acknowledgement(acknowledgement: PlayerAction) -> void:
	_controller.submit_action(acknowledgement)


## 房主观察通过连接绑定校验的测试确认动作，并核对权威端确有同样数量的客户端手牌。
## 首次确认后房主在同一房间内重开新对局，只有客户端再次确认新对局才视为开局绑定重播成功。
func _on_gateway_command_received(command_data: Dictionary) -> void:
	# 当前上行动作类型；首次开局确认与同房重开确认共用绑定与手牌校验，但推进不同步骤。
	var action_type: String = str(command_data.get("action_type", ""))
	if _is_client_process or (action_type != INITIAL_ACK_ACTION_TYPE and action_type != RESTART_ACK_ACTION_TYPE):
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
	if action_type == INITIAL_ACK_ACTION_TYPE:
		# 首次确认完成后触发同一 ENet 房间内的重开；重开必须重新广播开局绑定，使客户端重置表现幂等窗口。
		if _host_restart_requested:
			return
		_host_restart_requested = true
		if not _controller.start_match(TEST_PLAYER_COUNT, TEST_RANDOM_SEED):
			_fail("host_restart_start_failed")
			return
		if _controller.state == null or str(_controller.state.current_phase) != "character_selection":
			_fail("host_restart_phase=%s" % [str(_controller.state.current_phase) if _controller.state != null else "none"])
			return
		_host_restarted_match_id = str(_controller.state.match_id)
		_controller.replicate_current_state()
		print("LAN_MATCH_FLOW_RESTART_SENT match_id=%s" % _host_restarted_match_id)
		return
	# 重开确认必须来自重开后的新对局；对局 ID 缺失说明房主并未真正重建权威对局。
	if _host_restarted_match_id.is_empty() or str(_controller.state.match_id) != _host_restarted_match_id:
		_fail("restart_ack_match_mismatch expected=%s actual=%s" % [_host_restarted_match_id, str(_controller.state.match_id)])
		return
	_gateway.send_game_event_to_peer("lan_match_flow_complete", {"actor_id":actor_id, "hand_count":acknowledged_hand_count, "match_start_count":_match_start_count}, sender_peer_id)
	print("LAN_MATCH_FLOW_PASS actor=%d hand_count=%d phase=%s restart_match_id=%s" % [actor_id, acknowledged_hand_count, _controller.state.current_phase, _host_restarted_match_id])
	_finish_host_after_delay()


## 客户端收到房主完成事件后核对自身 actor 与手牌数量，并正常关闭 ENet 会话。
func _on_game_event_received(event_type: String, event_payload: Dictionary) -> void:
	if not _is_client_process or event_type != "lan_match_flow_complete":
		return
	if int(event_payload.get("actor_id", -1)) != _local_player_id or int(event_payload.get("hand_count", -1)) < 4:
		_fail("client_complete_mismatch=%s" % [event_payload])
		return
	# 房主记录的开局绑定次数；客户端必须同样收到两次，才能证明同房重开时开局绑定被重播。
	var host_match_start_count: int = int(event_payload.get("match_start_count", -1))
	if _match_start_count != 2 or host_match_start_count != _match_start_count:
		_fail("client_restart_binding_missing client=%d host=%d" % [_match_start_count, host_match_start_count])
		return
	print("LAN_MATCH_FLOW_CLIENT_PASS actor=%d match_start_count=%d" % [_local_player_id, _match_start_count])
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
	# 当前权威阶段与选将待确认者；双进程失败时保留最小诊断，避免只能看到无上下文超时。
	var current_phase: String = str(_controller.state.current_phase) if _controller.state != null else "none"
	# 当前选将子阶段；无活动服务时使用none，便于区分开局与对局阶段超时。
	var selection_phase: String = _controller.character_selection.phase if _controller.character_selection != null else "none"
	# 当前尚未确认玩家；只在测试失败输出，不修改服务内部数组。
	# 客户端进程没有权威 GameState 与选将服务，服务端返回的是无类型数组，因此这里使用无类型容器接收，避免超时诊断自身抛出类型错误。
	var pending_player_ids: Array = _controller.character_selection.get_pending_player_ids() if _controller.character_selection != null else []
	_fail("timeout role=%s phase=%s selection=%s pending=%s" % ["client" if _is_client_process else "host", current_phase, selection_phase, pending_player_ids])


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
