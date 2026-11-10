extends "res://tests/lan_match_flow_test.gd"

## 双进程ENet持续战斗验证；支持--soak-seconds=120，默认5秒用于全量回归。

## 默认持续秒数；完整长测通过用户参数扩大，不增加普通回归等待成本。
const DEFAULT_SOAK_SECONDS: float = 5.0

## 每次确认后间隔秒数；保持真实网络往返而不是同步模拟封包。
const CYCLE_INTERVAL_SECONDS: float = 0.1

## 测试超时；覆盖120秒持续验证及双方启动与清理。
const SOAK_TIMEOUT_SECONDS: float = 180.0

## 独立测试动作；网关仍校验peer与actor绑定。
const SOAK_ACK_ACTION: String = "lan_battle_soak_ack"

## 当前客户端可见快照；只用于核对真实裁剪结果。
var _last_snapshot: Dictionary = {}

## 测试截止时间；0表示尚未收到重开后的初始确认。
var _deadline_ms: int = 0

## 当前循环号；每次真实应答只能推进一次。
var _cycle: int = 0

## 当前远端稳定角色；沿用开局绑定，不按座次数组猜测。
var _soak_actor_id: int = -1

## 当前远端连接；只向其发送私有核对标记。
var _soak_peer_id: int = -1


## 子进程使用同一场景；完整继承选将、身份观察、同房重开与清理验证。
func _on_gateway_command_received(command_data: Dictionary) -> void:
	if not _is_client_process and str(command_data.get("action_type", "")) == RESTART_ACK_ACTION_TYPE and _deadline_ms == 0:
		_soak_peer_id = _gateway.get_current_incoming_peer_id()
		_soak_actor_id = int(command_data.get("actor_id", -1))
		if int(_gateway.get_remote_player_assignments().get(_soak_peer_id, -2)) != _soak_actor_id:
			_fail("soak actor binding")
			return
		# 本次持续时长；限制在超时以内，非法文本保持默认。
		var seconds: float = DEFAULT_SOAK_SECONDS
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--soak-seconds="):
				seconds = clampf(argument.get_slice("=", 1).to_float(), DEFAULT_SOAK_SECONDS, SOAK_TIMEOUT_SECONDS - TEST_TIMEOUT_SECONDS)
		_deadline_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
		_start_cycle()
		return
	if not _is_client_process and str(command_data.get("action_type", "")) == SOAK_ACK_ACTION:
		if _gateway.get_current_incoming_peer_id() != _soak_peer_id or int(command_data.get("actor_id", -1)) != _soak_actor_id or int((command_data.get("payload", {}) as Dictionary).get("cycle", -1)) != _cycle:
			_fail("soak stale or foreign acknowledgement")
			return
		if Time.get_ticks_msec() >= _deadline_ms:
			if _controller.get_settlement_fault_count() != 0 or int(_controller.stall_watchdog.get_diagnostics_snapshot().hard_repair_count) != 0:
				_fail("soak relied on recovery")
				return
			_gateway.send_game_event_to_peer("lan_match_flow_complete", {"actor_id":_soak_actor_id, "hand_count":_controller.state.get_player(_soak_actor_id).hand.size(), "match_start_count":_match_start_count}, _soak_peer_id)
			print("LAN_BATTLE_SOAK_PASS cycles=%d faults=0 hard_repairs=0" % _cycle)
			_finish_host_after_delay()
		else:
			get_tree().create_timer(CYCLE_INTERVAL_SECONDS).timeout.connect(_start_cycle, CONNECT_ONE_SHOT)
		return
	super._on_gateway_command_received(command_data)


## 每轮执行真实伤害、回复、摸牌和弃牌；每一步等待其完整子结算。
func _start_cycle() -> void:
	_cycle += 1
	# 本轮内容；不修改玩法伤害数值或绕过移牌服务。
	var steps: Array[Callable] = [
		func(_sequence: RuleStepSequence) -> void: _controller.damage(0, _soak_actor_id, 1),
		func(_sequence: RuleStepSequence) -> void: _controller.recover(0, _soak_actor_id, 1, "soak"),
		func(_sequence: RuleStepSequence) -> void: _controller.draw(_soak_actor_id, 1),
		func(_sequence: RuleStepSequence) -> void:
			# 新取得的末张手牌；完整摸牌后从权威区域读取。
			var player: PlayerState = _controller.state.get_player(_soak_actor_id)
			if player == null or not player.alive or player.hand.is_empty():
				_fail("soak invalid target")
				return
			_controller.begin_discard_cards(_soak_actor_id, [player.hand.back().uid], ["hand"], _soak_actor_id, "soak"),
		_publish_probe,
	]
	_controller.run_rule_sequence(steps, {"sequence_kind":"lan_soak"})


## 快照后发送核对消息；可靠通道顺序保证客户端先收到本轮规则结果。
func _publish_probe(_sequence: RuleStepSequence) -> void:
	_controller.replicate_current_state()
	# 远端实际角色状态；只发送本人允许查看的摘要。
	var player: PlayerState = _controller.state.get_player(_soak_actor_id)
	_gateway.send_game_event_to_peer("lan_battle_soak_probe", {"cycle":_cycle, "hp":player.hp, "hand_count":player.hand.size()}, _soak_peer_id)


## 保留客户端最新裁剪快照；原基类继续负责首次/重开确认。
func _on_state_changed(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot
	super._on_state_changed(snapshot)


## 客户端每轮核对真实收到的规则结果与隐私裁剪，再回传确认。
func _on_game_event_received(event_type: String, event_payload: Dictionary) -> void:
	if _is_client_process and event_type == "lan_battle_soak_probe":
		# 本人的最新可见状态；不能用服务器消息直接伪造本地结果。
		var own: Dictionary = {}
		for player: Dictionary in _last_snapshot.get("players", []):
			if int(player.get("player_id", -1)) == _local_player_id:
				own = player
			elif not (player.get("hand", []) as Array).is_empty():
				_fail("soak private hand leaked")
				return
		if int(own.get("hp", -1)) != int(event_payload.hp) or int(own.get("hand_count", -1)) != int(event_payload.hand_count) or (own.get("hand", []) as Array).size() != int(event_payload.hand_count):
			_fail("soak stale snapshot")
			return
		# 正式网关上行；请求身份由服务端连接映射校验。
		var action: PlayerAction = PlayerAction.new(SOAK_ACK_ACTION, _local_player_id)
		action.payload = {"cycle":int(event_payload.cycle)}
		_gateway.send_command(action)
		return
	super._on_game_event_received(event_type, event_payload)


## 长测使用独立超时；普通基类仍保留30秒启动规则。
func _install_timeout_guard() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = SOAK_TIMEOUT_SECONDS
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)
	_timeout_timer.start()
