extends Node

## 联机身份自动标记回归。覆盖房主公开行为广播载荷契约、非房主本地重放推断，以及广播内容不含隐藏信息与推断结果。

## 本测试共用的对局控制器；房主段与客户端段复用同一实例并切换网络角色，避免重复构建规则服务。
var _controller: MatchController


## 延迟一帧开始回归，确保 GameDatabase 已完成目录扫描与静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行联机身份标记断言；任一失败立即以非零状态退出。
func _run() -> void:
	_create_controller()
	if not _test_behavior_payload_contract():
		return
	if not _test_skill_behavior_replay_produces_mark():
		return
	if not _test_response_payload_excludes_hidden_context():
		return
	if not _test_replay_skips_local_observer():
		return
	print("LAN_IDENTITY_MARK_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；公开行为观察与身份模型共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；联机对局没有内置策略时仍由共享身份模型记录公开行为。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；测试按需要切换为局域网客户端角色以驱动重放入口。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0
	_reset_state()


## 建立最小身份局状态并重建规则服务；0号领袖身份公开，其余角色保持隐藏以便自动标记生效。
func _reset_state() -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "lan-identity-mark"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(4):
		# 当前测试角色；只有领袖公开身份，其余隐藏身份才允许自动标记产生忠反推断。
		# 1号与2号同为反贼，使“本地座位被过滤”与“其他玩家正常标记”两条断言都能用真实对齐的行为构造。
		var player: PlayerState = PlayerState.new(player_id, "联机标记测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id in [1, 2] else "loyalist")
		player.identity_revealed = player_id == 0
		player.character_id = "wandi"
		player.character_generation = 1
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()
	_controller.ai_coordinator.reset_identity_observations()


## 把网关切换为已连接的局域网客户端；重放入口只在该角色下生效，与正式客户端一致。
func _enter_lan_client_role() -> void:
	_controller.network_gateway.mode = NetworkGateway.Mode.LAN
	_controller.network_gateway.lan_role = NetworkGateway.LanRole.CLIENT
	_controller.network_gateway.connected = true


## 校验公开目标行为载荷只含行为数据；广播不得携带房主算好的身份推断结果。
func _test_behavior_payload_contract() -> bool:
	# 待广播的身份观察配置；使用技能文件为公开目标行为提供的只读 AI 配置形状。
	var source_profile: Dictionary = {"target_result":-1.0, "expose":0.4}
	# 实际公开目标数组；只包含被指定的公开目标。
	var source_target_ids: Array[int] = [0]
	var payload: Dictionary = _controller.build_identity_behavior_payload(1, source_profile, source_target_ids)
	# 载荷必须完整包含三项行为数据；任何一项缺失都会让客户端无法重放同一证据。
	if int(payload.get("actor_id", -1)) != 1 or (payload.get("ai_profile", {}) as Dictionary).is_empty() or (payload.get("target_ids", []) as Array).size() != 1:
		return _fail("behavior_payload_shape=%s" % str(payload))
	# 载荷不得出现身份标记相关键；推断结果只能由各客户端本地模型产生。
	for forbidden_key: String in ["identity_mark", "mark", "identity"]:
		if payload.has(forbidden_key):
			return _fail("behavior_payload_leaks=%s" % forbidden_key)
	# 载荷必须与来源数据解耦；广播后修改源字典不得影响已构建的内容。
	source_profile["target_result"] = 1.0
	source_target_ids.append(3)
	if not is_equal_approx(float((payload.get("ai_profile", {}) as Dictionary).get("target_result", 0.0)), -1.0) or (payload.get("target_ids", []) as Array).size() != 1:
		return _fail("behavior_payload_alias=%s" % str(payload))
	return true


## 校验非房主重放房主广播的技能公开行为后，本地身份模型产生与房主一致的忠反标记。
func _test_skill_behavior_replay_produces_mark() -> bool:
	# 公开行为使用的身份观察配置；反贼对公开领袖的负向行为会形成 rebel 标记。
	var behavior_profile: Dictionary = {"target_result":-1.0, "expose":0.4}
	# 房主本机观察；权威端直接执行技能公开行为，不经过网络。
	_controller.local_human_player_id = 0
	_controller.observe_skill_identity_behavior(1, [0], behavior_profile)
	if _controller.ai_coordinator.get_identity_mark(1) != "rebel":
		return _fail("host_mark=%s" % _controller.ai_coordinator.get_identity_mark(1))
	# 房主发出的载荷；客户端收到的内容与之一致。
	var payload: Dictionary = _controller.build_identity_behavior_payload(1, behavior_profile, [0] as Array[int])
	# 切换到客户端角色；身份模型清空后仅凭广播内容重建推断。
	_controller.ai_coordinator.reset_identity_observations()
	_controller.local_human_player_id = 2
	_controller._remote_snapshot = _controller.state.to_dict(-1, true)
	_enter_lan_client_role()
	if not _controller.ai_coordinator.get_identity_mark(1).is_empty():
		return _fail("client_pre_replay_mark=%s" % _controller.ai_coordinator.get_identity_mark(1))
	_controller._on_network_game_event_received("identity_behavior", payload)
	# 重放后客户端必须复现同一标记；这正是非房主自动标记身份的失效点。
	if _controller.ai_coordinator.get_identity_mark(1) != "rebel":
		return _fail("client_replay_mark=%s" % _controller.ai_coordinator.get_identity_mark(1))
	# 客户端在真实形态下没有本地 GameState；重放必须改读房主快照并保持同一结论。
	_controller.ai_coordinator.reset_identity_observations()
	_controller.state = null
	_controller._on_network_game_event_received("identity_behavior", payload)
	if _controller.ai_coordinator.get_identity_mark(1) != "rebel":
		return _fail("client_stateless_replay_mark=%s" % _controller.ai_coordinator.get_identity_mark(1))
	_reset_state()
	return true


## 校验公开响应牌载荷只保留身份模型读取的三个公开键，整段结算上下文不得进入网络。
func _test_response_payload_excludes_hidden_context() -> bool:
	# 完整结算上下文；额外键模拟真实无懈链条中可能出现的手牌与内部状态字段。
	var response_context: Dictionary = {
		"source_id":0,
		"target_id":1,
		"negated":true,
		"hidden_hand_uids":[11, 12],
		"internal_chain_state":{"secret":"value"},
	}
	var payload: Dictionary = _controller.build_identity_response_payload(2, "wuxie", "shunshouqianyang", response_context)
	# 载荷只允许四个顶层键；多余字段会把隐藏手牌或内部状态带入网络。
	if payload.size() != 4 or not payload.has("responder_id") or not payload.has("card_definition_id") or not payload.has("trick_id") or not payload.has("response_context"):
		return _fail("response_payload_shape=%s" % str(payload.keys()))
	# 公开上下文只保留三个身份观察键；隐藏手牌与内部状态必须被裁剪掉。
	var public_context: Dictionary = payload.get("response_context", {}) as Dictionary
	if public_context.size() != 3 or public_context.has("hidden_hand_uids") or public_context.has("internal_chain_state"):
		return _fail("response_payload_context=%s" % str(public_context))
	if int(public_context.get("source_id", -1)) != 0 or int(public_context.get("target_id", -1)) != 1 or not bool(public_context.get("negated", false)):
		return _fail("response_payload_values=%s" % str(public_context))
	return true


## 校验重放不会把本地玩家自己的公开行为标记为忠反；该语义必须与房主端一致。
func _test_replay_skips_local_observer() -> bool:
	# 当前客户端的本地座位；广播中该座位的公开行为不得形成自动标记。
	_controller.local_human_player_id = 1
	_controller.ai_coordinator.reset_identity_observations()
	_controller._remote_snapshot = _controller.state.to_dict(-1, true)
	_enter_lan_client_role()
	_controller._on_network_game_event_received("identity_behavior", _controller.build_identity_behavior_payload(1, {"target_result":-1.0, "expose":0.4}, [0] as Array[int]))
	if not _controller.ai_coordinator.get_identity_mark(1).is_empty():
		return _fail("local_observer_marked=%s" % _controller.ai_coordinator.get_identity_mark(1))
	# 其他玩家在重放中必须正常产生标记；观察者过滤只针对本地座位。
	_controller._on_network_game_event_received("identity_behavior", _controller.build_identity_behavior_payload(2, {"target_result":-1.0, "expose":0.4}, [0] as Array[int]))
	if _controller.ai_coordinator.get_identity_mark(2) != "rebel":
		return _fail("remote_observer_mark=%s" % _controller.ai_coordinator.get_identity_mark(2))
	return true


## 输出失败标记并以非零状态退出；成功路径不调用该函数。
func _fail(message: String) -> bool:
	print("LAN_IDENTITY_MARK_FAIL %s" % message)
	get_tree().quit(1)
	return false
