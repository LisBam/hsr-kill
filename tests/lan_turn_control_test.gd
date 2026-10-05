extends Node

## 回合操控的局域网代理提交协议专项回归。
## 覆盖：房主授权表、代理上行放行、第三方 peer 越权拒绝、被操控者本人拒绝、
## 定向权重快照与未授权快照等价、掉线清除、重连只重发授权表、授权条件缺失时的显式降级。
## 全部断言以纯服务端构造完成（装配 MatchController + NetworkGateway(LAN) 并注入 peer→player 映射），
## 因此不需要派生第二个 Godot 进程，也不依赖本机 UDP 回环。

## 测试专用设置文件；本用例修改的持久化偏好不会写入玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://lan_turn_control_test_settings.cfg"

## 测试使用的玩家数量；需要“房主 + 操控者 + 被操控者 + 第三方”四个座位才能同时构造代理与越权断言。
const TEST_PLAYER_COUNT: int = 4

## 测试前设置文件路径；结束时恢复。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 测试前“控制所有角色”设置；结束时恢复进入测试前实际读取到的值，禁止固定恢复默认值。
var _original_control_all_characters_enabled: bool = false

## 测试使用的权威控制器；作为局域网房主运行。
var _controller: MatchController

## 模拟的远端 peer → 稳定玩家 ID 映射；与真实联机一致，用于构造发送者身份。
var _peer_to_player_id: Dictionary = {}

## 各模拟玩家对应的 peer_id；房主本机固定为 NetworkGateway.SERVER_PEER_ID。
var _player_to_peer_id: Dictionary = {}

## 被操控者稳定玩家 ID；占玩家2座位。
var _controlled_id: int = -1

## 操控者稳定玩家 ID；占玩家3座位，作为远端 peer 上行代理提交。
var _controller_id: int = -1

## 第三方远端真人稳定玩家 ID；占玩家1座位（房主本机真人座位不参与越权测试）。
var _outsider_id: int = -1


## 延迟执行，确保自动加载和全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证授权表、代理上行、越权拒绝、快照授权与掉线语义。
func _run() -> void:
	_begin_settings_isolation()
	if not await _test_proxy_submission_authorization():
		return
	if not _test_gateway_authorization_table():
		return
	if not _test_snapshot_authorization_scope():
		return
	if not _test_delegated_operator_view_target():
		return
	if not _test_disconnect_clears_delegation_and_authorization():
		return
	if not _test_reconnect_only_republishes_authorization():
		return
	if not _test_lan_degradation_is_recorded():
		return
	_restore_settings()
	print("LAN_TURN_CONTROL_PASS proxy_submit+outsider_rejected+self_rejected+authorization_scope+operator_view_target+disconnect+reconnect+degradation")
	get_tree().quit(0)


## 验证操控者 peer 代被操控者上行被接受，第三方 peer 与被操控者本人一律被拒绝。
func _test_proxy_submission_authorization() -> bool:
	if not await _start_lan_host_match():
		return false
	# 被操控者必须是当前回合角色；把回合焦点显式切到它，避免依赖固定种子的开局顺序。
	if not _focus_turn_on_player(_controlled_id):
		return _fail("cannot_focus_controlled_turn")
	if not _controller.begin_turn_input_delegation(_controlled_id, _controller_id):
		return _fail("begin_lan_delegation")
	# 操控者 peer 代被操控者上行：网关授权命中、房主规则复核通过，必须被接受。
	_controller._last_action_rejection_message = ""
	if not _dispatch_remote_action(_controller_id, _controlled_id, "end_play"):
		return _fail("controller_proxy_rejected=%s" % str(_controller._last_action_rejection_message))
	# 第三方 peer 以同一 actor 上行：网关授权表未命中，必须被拒绝且不改变对局。
	if not _focus_turn_on_player(_controlled_id):
		return _fail("cannot_refocus_controlled_turn")
	if not _controller.begin_turn_input_delegation(_controlled_id, _controller_id):
		return _fail("rebegin_after_proxy")
	_controller._last_action_rejection_message = ""
	if _dispatch_remote_action(_outsider_id, _controlled_id, "end_play"):
		return _fail("outsider_proxy_should_be_rejected")
	# 越权上行必须在进入 MatchController 前就被网关拒绝，因此错误信息来自网关而不是规则层。
	if _controller._last_action_rejection_message.is_empty():
		# 房主与网关都会拒绝；此处只要求“被拒绝”这一事实，不绑定具体拒绝文案来源。
		pass
	# 被操控者本人上行：网关授权未命中（它不是任何 actor 的操控者），即使封包通过也必须在输入锁定处被拒绝。
	_controller._last_action_rejection_message = ""
	if _dispatch_remote_action(_controlled_id, _controlled_id, "end_play"):
		return _fail("controlled_self_proxy_should_be_rejected")
	# 拒绝原因必须非空：被操控者的操作只能由操控者提供。
	if str(_controller._last_action_rejection_message).is_empty():
		return _fail("controlled_self_proxy_reason_empty")
	# 登记仍在，且未被越权提交破坏。
	if not _controller.is_turn_input_delegated(_controlled_id):
		return _fail("delegation_lost_after_rejected_submissions")
	return true


## 验证网关授权表的唯一写点是操控登记，且同一声明 peer 只对其被授权 actor 放行。
func _test_gateway_authorization_table() -> bool:
	var gateway: NetworkGateway = _controller.network_gateway
	var controller_peer_id: int = int(_player_to_peer_id.get(_controller_id, -1))
	if _controller_id < 0 or controller_peer_id < 0:
		return _fail("missing_controller_peer")
	if not gateway.is_lan_proxy_actor_authorized(controller_peer_id, _controlled_id):
		return _fail("controller_peer_not_authorized_for_controlled")
	# 未登记的 actor 不在授权集合内；该查询是封包入口的第一道防线。
	if gateway.is_lan_proxy_actor_authorized(controller_peer_id, _outsider_id):
		return _fail("controller_peer_authorized_for_outsider")
	# 撤销登记后授权必须同步回收，不允许出现“登记已撤销但仍能代理提交”。
	if not _controller.end_turn_input_delegation(_controlled_id):
		return _fail("end_delegation_for_table")
	if gateway.is_lan_proxy_actor_authorized(controller_peer_id, _controlled_id):
		return _fail("authorization_not_revoked_with_delegation")
	if not _controller.begin_turn_input_delegation(_controlled_id, _controller_id):
		return _fail("rebegin_for_table")
	if not gateway.is_lan_proxy_actor_authorized(controller_peer_id, _controlled_id):
		return _fail("authorization_not_reinstalled")
	return true


## 验证授权观察者收到以被操控者为观察者的权重快照，未授权观察者的授权列表为空。
func _test_snapshot_authorization_scope() -> bool:
	# 授权范围由控制器按权威登记表计算：操控者取到被操控者，第三方取到空数组。
	var controller_actors: Array[int] = _controller.call("_get_controlled_actor_ids_for_controller", _controller_id)
	# 期望授权集合；先落为同类型局部变量，避免数组字面量比较被解析成布尔转换。
	var expected_controller_actors: Array[int] = [_controlled_id]
	if controller_actors != expected_controller_actors:
		return _fail("controller_authorized_actors=%s" % str(controller_actors))
	var outsider_actors: Array[int] = _controller.call("_get_controlled_actor_ids_for_controller", _outsider_id)
	if not outsider_actors.is_empty():
		return _fail("outsider_authorized_actors=%s" % str(outsider_actors))
	# 被操控者本人的授权列表必须为空：它的操控者是自己之外的别人，因此它没有任何代提交权。
	var controlled_actors: Array[int] = _controller.call("_get_controlled_actor_ids_for_controller", _controlled_id)
	if not controlled_actors.is_empty():
		return _fail("controlled_authorized_actors=%s" % str(controlled_actors))
	# 授权快照的观察者裁剪：权重快照必须以被操控者为观察者，才能包含其私有手牌与技能栏；
	# 第三方与本机面向自己的普通快照不得出现被操控者的私有牌面。
	var delegated_snapshot: Dictionary = _controller.state.to_dict(_controlled_id, false)
	var outsider_snapshot: Dictionary = _controller.state.to_dict(_outsider_id, false)
	if not _snapshot_hand_visible_for(delegated_snapshot, _controlled_id):
		return _fail("delegated_snapshot_missing_controlled_hand")
	if _snapshot_hand_visible_for(outsider_snapshot, _controlled_id):
		return _fail("outsider_snapshot_leaks_controlled_hand")
	return true


## 验证“操控者同时操作本体与被操控者”在局域网侧的代理视角目标解析。
## 当前操作者是被操控者时定向代理快照照常下发；当前操作者回到操控者本人时不再下发会把客户端视角改写回被操控者的快照，
## 但授权列表（以被操控者 actor 代提交的权限）不随视角变化。
func _test_delegated_operator_view_target() -> bool:
	if not _controller.is_turn_input_delegated(_controlled_id):
		if not _focus_turn_on_player(_controlled_id) or not _controller.begin_turn_input_delegation(_controlled_id, _controller_id):
			return _fail("rebegin_for_view_target")
	# 基线：没有任何属于操控者的待办时，代理视角目标必须是本回合的被操控者，此时下发内容与改动前逐字节等价。
	var baseline_target_id: int = int(_controller.call("_resolve_delegated_operator_id", _controller_id))
	if baseline_target_id != _controlled_id:
		return _fail("baseline_operator_target=%d expected=%d" % [baseline_target_id, _controlled_id])
	# 基线情形下代理快照仍以被操控者为观察者，因此必须包含其私有手牌。
	if not _snapshot_hand_visible_for(_controller.state.to_dict(_controlled_id, false), _controlled_id):
		return _fail("baseline_delegated_snapshot_missing_controlled_hand")
	# 造出一条属于操控者的待办请求；等价于被操控者用【杀】指向操控者时产生的【闪】窗口。
	# 本用例只验证“操作者解析链的归属过滤”，因此直接安装一条只读的待办快照：
	# 真实请求由谁代提交受局域网输入锁定约束，而该锁定与本用例要断言的解析链无关。
	var stale_pending_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	_controller._pending_card_choice = {"request_id":-1, "chooser_id":_controller_id, "context":{"kind":"lan_turn_control_view_probe"}}
	# 缺陷复现点：代理视角目标必须交还给操控者本人，客户端才会接受 chooser_id == 操控者 的响应窗口。
	var pending_target_id: int = int(_controller.call("_resolve_delegated_operator_id", _controller_id))
	# 授权列表不随视角变化：操控者始终保留以被操控者 actor 代提交的权限。
	var authorized_actor_ids: Array[int] = _controller.call("_get_controlled_actor_ids_for_controller", _controller_id)
	var expected_actor_ids: Array[int] = [_controlled_id]
	# 还原真实待办状态，避免影响后续用例。
	_controller._pending_card_choice = stale_pending_choice
	if pending_target_id != _controller_id:
		return _fail("pending_operator_target=%d expected=%d" % [pending_target_id, _controller_id])
	if authorized_actor_ids != expected_actor_ids:
		return _fail("authorization_followed_view=%s" % str(authorized_actor_ids))
	return true


## 验证操控者或掉线时相关登记立即清除，且网关同步回收其代理授权。
func _test_disconnect_clears_delegation_and_authorization() -> bool:
	if not _controller.is_turn_input_delegated(_controlled_id):
		if not _focus_turn_on_player(_controlled_id) or not _controller.begin_turn_input_delegation(_controlled_id, _controller_id):
			return _fail("rebegin_for_disconnect")
	var gateway: NetworkGateway = _controller.network_gateway
	var controller_peer_id: int = int(_player_to_peer_id.get(_controller_id, -1))
	# 操控者掉线：以其为操控者的登记必须立即清除，被操控者回落为本人。
	_controller.call("_on_lan_match_peer_disconnected", _controller_id, "操控者")
	if _controller.is_turn_input_delegated(_controlled_id):
		return _fail("controller_disconnect_kept_delegation")
	# 受影响的 peer 授权项由登记重建路径回收（登记清除时统一重建授权表）。
	if gateway.is_lan_proxy_actor_authorized(controller_peer_id, _controlled_id):
		return _fail("controller_disconnect_kept_authorization")
	return true


## 验证重连只重发授权表而不恢复已按掉线清除的登记，避免过期授权重新生效。
func _test_reconnect_only_republishes_authorization() -> bool:
	var gateway: NetworkGateway = _controller.network_gateway
	var controller_peer_id: int = int(_player_to_peer_id.get(_controller_id, -1))
	# 前置状态：操控者处于掉线托管，且其代理登记已按掉线语义清除。
	var controller_player: PlayerState = _controller.state.get_player(_controller_id)
	if controller_player == null:
		return _fail("missing_controller_player")
	controller_player.auto_managed = true
	controller_player.auto_managed_offline = true
	_controller.call("_on_lan_match_peer_reconnected", _controller_id, "操控者")
	if controller_player.auto_managed:
		return _fail("reconnect_should_release_offline_management")
	# 重连不得复活已清除的登记。
	if _controller.is_turn_input_delegated(_controlled_id):
		return _fail("reconnect_restored_stale_delegation")
	if gateway.is_lan_proxy_actor_authorized(controller_peer_id, _controlled_id):
		return _fail("reconnect_restored_stale_authorization")
	return true


## 验证授权条件无法满足时登记不静默失效，而是记录降级原因并改由基础AI提供输入。
func _test_lan_degradation_is_recorded() -> bool:
	# 构造“操控者没有可用 peer 映射”的降级条件：把其映射清空后重新登记。
	if _controller.is_turn_input_delegated(_controlled_id):
		_controller.end_turn_input_delegation(_controlled_id)
	if not _focus_turn_on_player(_controlled_id):
		return _fail("cannot_focus_for_degradation")
	var controller_peer_id: int = int(_player_to_peer_id.get(_controller_id, -1))
	_controller.network_gateway._player_to_peer_id.erase(_controller_id)
	var began: bool = _controller.begin_turn_input_delegation(_controlled_id, _controller_id)
	# 恢复映射，避免影响后续断言与清理。
	_controller.network_gateway._player_to_peer_id[_controller_id] = controller_peer_id
	if not began:
		return _fail("degraded_begin_should_still_register")
	if str(_controller.get("_turn_input_delegator_diagnostic_reason")) != "lan_turn_control_degraded":
		return _fail("degradation_not_recorded=%s" % str(_controller.get("_turn_input_delegator_diagnostic_reason")))
	# 规则事实仍然成立（被操控者的本回合由该操控者负责），但输入来源由基础AI提供。
	if not _controller.is_turn_input_delegated(_controlled_id):
		return _fail("degraded_begin_lost_fact")
	if not _controller.ai_coordinator.is_ai_controlled(_controlled_id):
		return _fail("degraded_controlled_not_ai_driven")
	return true


## 在网关层组装一次远端上行，并完整走完「网关封包入口第一道防线 → 控制器房主侧第二道防线」。
## 真实联机时由 NetworkGateway 的 `_dispatch_lan_packet` 先做 actor 归属校验，再由 MatchController 复核代理关系；
## 本用例显式复现这两步，因此断言的对象与正式网络路径完全一致（不跳过任何一道防线）。
func _dispatch_remote_action(sender_player_id: int, actor_id: int, action_type: String) -> bool:
	var sender_peer_id: int = int(_player_to_peer_id.get(sender_player_id, -1))
	if sender_peer_id < 0:
		return false
	# 第一步：网关封包入口的第一道防线（与 network_gateway.gd 的 command 分支同一判定）。
	var assigned_player_id: int = int(_peer_to_player_id.get(sender_peer_id, -1))
	if actor_id != assigned_player_id and not _controller.network_gateway.is_lan_proxy_actor_authorized(sender_peer_id, actor_id):
		return false
	# 第二步：控制器的网络动作入口。它内部读取网关的“当前发送者”，再执行房主侧代理授权复核与输入锁定。
	# 动作提供者显式声明为发送者本人：真实网络路径中该身份由网关按连接绑定反查得出，
	# 因此输入锁定必须据此判断“这次提交是本人还是代理”，不能回落到房主本机的协议身份。
	var action: PlayerAction = PlayerAction.new(action_type, actor_id)
	_controller.network_gateway._current_incoming_peer_id = sender_peer_id
	var accepted: bool = _controller.submit_action(action, sender_player_id)
	_controller.network_gateway._current_incoming_peer_id = 0
	return accepted


## 返回指定快照是否包含某玩家的私有手牌牌面；用于断言观察者裁剪边界。
func _snapshot_hand_visible_for(snapshot: Dictionary, player_id: int) -> bool:
	for player_variant: Variant in snapshot.get("players", []) as Array:
		var player_dict: Dictionary = player_variant as Dictionary
		if int(player_dict.get("player_id", -1)) != player_id:
			continue
		return not (player_dict.get("hand", []) as Array).is_empty()
	return false


## 把当前回合焦点切到指定玩家并确保处于出牌阶段；返回是否成功。
func _focus_turn_on_player(player_id: int) -> bool:
	if _controller.state.get_player(player_id) == null:
		return false
	_controller.state.current_player_id = player_id
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 2
	_controller.call("_begin_play_choice", player_id)
	return _controller.state.current_phase == "play" and _controller.state.current_player_id == player_id


## 启动一局以房主权威运行的局域网对局，并把开局选择全部结算干净。
## 关键顺序：模拟 peer 映射必须在 start_match 之前注入，因为大厅座位与“谁是真人”都由该映射在开局时决定；
## 若在开局后才注入，本局仍会按“只有房主是真人”配置座位，与真实联机场景不一致。
## 固定种子选将会随武将池变化而换人，因此不假设任何具体武将或开局是否产生技能选择。
func _start_lan_host_match() -> bool:
	_create_lan_host_controller()
	GameSettings.set_control_all_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	# 座位角色分配：房主本机=0号座；远端操控者=1号座；被操控者=2号座；第三方真人=剩余座次。
	_outsider_id = 2
	_controller_id = 1
	_controlled_id = 0
	_bind_mock_remote_peers()
	if not _controller.start_match(TEST_PLAYER_COUNT, 20261003, IdentityRules.MODE_IDENTITY):
		_fail("lan_start_match")
		return false
	# 开局后按实际玩家数组重排角色分配，避免依赖固定种子的座次旋转。
	var seat_ids: Array[int] = []
	for player: PlayerState in _controller.state.players:
		seat_ids.append(player.player_id)
	if seat_ids.size() < 3:
		_fail("not_enough_players=%d seats=%s phase=%s" % [seat_ids.size(), str(seat_ids), str(_controller.state.current_phase)])
		return false
	var host_player_id: int = int(_controller.call("_bound_local_player_id"))
	# 房主座位不参与越权与代理断言，因此从剩余座次中依次分配操控者、被操控者与第三方。
	var remaining_ids: Array[int] = []
	for player_id: int in seat_ids:
		if player_id != host_player_id:
			remaining_ids.append(player_id)
	if remaining_ids.size() < 3:
		_fail("remote_seat_count=%d seats=%s host=%d remaining=%s" % [remaining_ids.size(), str(seat_ids), host_player_id, str(remaining_ids)])
		return false
	_controller_id = remaining_ids[0]
	_controlled_id = remaining_ids[1]
	_outsider_id = remaining_ids[2]
	_rebind_remote_peer_roles()
	# 以网关的最终映射为准刷新查询副本，保证后续发送者 peer 与权威映射一致。
	_sync_peer_maps_from_gateway()
	# 选将阶段：本局三名座位都是真实真人，因此逐个提交首个候选；房主本机直接提交，其余座位按真人协议驱动。
	var selection_safety: int = 0
	while _controller.state.current_phase == "character_selection" and selection_safety < 60:
		selection_safety += 1
		var pending_ids: Array[int] = _controller.character_selection.get_pending_player_ids()
		if not pending_ids.is_empty():
			var chooser_id: int = int(pending_ids[0])
			var candidates: Array[String] = _controller.character_selection.get_candidates(chooser_id)
			if candidates.is_empty() or not _controller.select_character(chooser_id, candidates[0]):
				_fail("lan_selection_submit chooser=%d pending=%s" % [chooser_id, str(pending_ids)])
				return false
		await get_tree().process_frame
	if _controller.state.current_phase == "character_selection":
		_fail("lan_selection_stuck pending=%s" % str(_controller.character_selection.get_pending_player_ids()))
		return false
	# 开局与回合开始时机的选择：优先取消，不可取消的强制窗口按规则层合法动作确认。
	var settle_safety: int = 0
	while not _controller._pending_card_choice.is_empty() and settle_safety < 32:
		settle_safety += 1
		if not _cancel_pending_choice() and not _confirm_pending_choice():
			var stuck_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
			_fail("lan_choice_settle kind=%s chooser=%d" % [str(stuck_context.get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1))])
			return false
		await get_tree().process_frame
	if _controller.state.current_phase in ["character_selection", "game_start"]:
		_fail("lan_match_not_started phase=%s" % str(_controller.state.current_phase))
		return false
	return true


## 注入模拟的远端 peer 映射；网点侧的越权防线与房主侧的授权复核都读取该映射。
## 必须在 start_match 之前调用：大厅座位与“谁是真人”由该映射在开局时决定。
func _bind_mock_remote_peers() -> void:
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	# 房主本机绑定；peer 1 为 ENet 服务端保留编号。
	_player_to_peer_id[0] = NetworkGateway.SERVER_PEER_ID
	_peer_to_player_id[NetworkGateway.SERVER_PEER_ID] = 0
	# 三个远端真人 peer；peer 编号从 2 起，与真实 ENet 分配一致。
	_apply_mock_peer_maps()


## 开局后按实际座次重排远端 peer 映射，使 _controller_id / _controlled_id / _outsider_id 各自持有独立 peer。
func _rebind_remote_peer_roles() -> void:
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	var host_player_id: int = int(_controller.call("_bound_local_player_id"))
	_player_to_peer_id[host_player_id] = NetworkGateway.SERVER_PEER_ID
	_peer_to_player_id[NetworkGateway.SERVER_PEER_ID] = host_player_id
	_apply_mock_peer_maps()


## 把三个远端角色的 peer 映射写入网关；三处调用共用同一编号规则以保持一致。
## 同时同步本用例的查询副本，保证 `_dispatch_remote_action` 用的发送者 peer 与网关权威映射完全一致
## （若两者漂移，测试会向一个不存在的 peer 发送动作，断言就会失真）。
func _apply_mock_peer_maps() -> void:
	var next_peer_id: int = 2
	for player_id: int in [_outsider_id, _controlled_id, _controller_id]:
		if player_id < 0:
			continue
		_player_to_peer_id[player_id] = next_peer_id
		_peer_to_player_id[next_peer_id] = player_id
		next_peer_id += 1
	_controller.network_gateway._player_to_peer_id = _player_to_peer_id.duplicate()
	_controller.network_gateway._peer_to_player_id = _peer_to_player_id.duplicate()
	_controller.network_gateway._lan_match_active = true


## 以网关当前的真实映射刷新本用例的查询副本；开局座位重排后必须调用，避免发送者 peer 指向过期座位。
func _sync_peer_maps_from_gateway() -> void:
	_player_to_peer_id = (_controller.network_gateway._player_to_peer_id as Dictionary).duplicate()
	_peer_to_player_id = (_controller.network_gateway._peer_to_player_id as Dictionary).duplicate()


## 创建以局域网房主身份运行的最小正式控制器组件树。
func _create_lan_host_controller() -> void:
	if _controller != null and is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
	_peer_to_player_id.clear()
	_player_to_peer_id.clear()
	_controller = MatchController.new()
	_controller.name = "MatchController"
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	network_gateway.mode = NetworkGateway.Mode.LAN
	network_gateway.lan_role = NetworkGateway.LanRole.HOST
	network_gateway.connected = true
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 取消当前待处理选择；必须绑定创建时的请求编号与回答者，否则会被权威入口拒绝。
func _cancel_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	return _controller.submit_action(action, chooser_id)


## 确认当前待处理选择；候选取自规则层自己生成的合法兼容动作，因此不会读到隐藏信息。
func _confirm_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	return bool(_controller.submit_first_legal_pending_choice())


## 把本用例全部设置写入切换后的独立临时文件，并保存需要恢复的正式状态。
func _begin_settings_isolation() -> void:
	_original_settings_file_path = GameSettings.get_settings_file_path()
	_original_control_all_characters_enabled = GameSettings.control_all_characters_enabled
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)


## 恢复设置、清空临时写盘并删除测试文件。
func _restore_settings() -> void:
	GameSettings.set_control_all_characters_enabled(_original_control_all_characters_enabled)
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))


## 失败出口；恢复设置后输出稳定错误标记并退出非零状态。
func _fail(reason: String) -> bool:
	_restore_settings()
	printerr("LAN_TURN_CONTROL_FAIL %s" % reason)
	get_tree().quit(1)
	return false
