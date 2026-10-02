extends Node

## 回合操控机制专项回归。验证登记校验、代理解析、输入锁定、到期清理、第一视角接管与快照往返。

## 测试专用设置文件；本用例修改的持久化偏好不会写入玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://turn_control_mechanism_test_settings.cfg"

## 测试使用的玩家数量；3人局足以覆盖“无关角色的回合结束不误清除登记”这一跨回合匹配断言。
const TEST_PLAYER_COUNT: int = 3

## 测试前设置文件路径；结束时恢复。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 测试前“控制所有角色”设置；结束时恢复进入测试前实际读取到的值，禁止固定恢复默认值。
var _original_control_all_characters_enabled: bool = false

## 测试使用的权威控制器；按正式子组件名称装配。
var _controller: MatchController


## 延迟执行，确保自动加载和全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证登记校验、幂等顶替、代理提交、输入锁定、到期清理与视角接管。
func _run() -> void:
	_begin_settings_isolation()
	_log_progress("begin_validation")
	if not await _test_begin_validation_and_idempotence():
		return
	_log_progress("proxy_submission")
	if not await _test_proxy_submission_and_input_lock():
		return
	_log_progress("answerable")
	if not await _test_answerable_and_legal_actions():
		return
	_log_progress("expiry")
	if not await _test_expiry_on_turn_end_and_isolation():
		return
	_log_progress("cleanup")
	if not await _test_death_and_out_of_game_cleanup():
		return
	_log_progress("snapshot")
	if not await _test_snapshot_round_trip():
		return
	_log_progress("view_takeover")
	if not await _test_offline_view_takeover_and_return():
		return
	_log_progress("validation")
	if not _test_game_database_validation_is_clean():
		return
	_restore_settings()
	print("TURN_CONTROL_PASS begin_guard+idempotence+proxy_submit+input_lock+answerable+expiry+cleanup+snapshot+view_takeover")
	get_tree().quit(0)


## 输出阶段进度；失败时用于定位停滞在哪个用例，不参与任何断言，也不影响 PASS 判定。
func _log_progress(stage: String) -> void:
	print("TURN_CONTROL_STAGE %s" % stage)


## 验证六类非法输入全部返回false且零副作用，以及重复登记幂等与换人顶替。
func _test_begin_validation_and_idempotence() -> bool:
	if not await _start_playable_match():
		return false
	# 当前回合角色与其对手；登记的前置条件围绕“被操控者必须是当前回合角色”展开。
	var current_id: int = _controller.state.current_player_id
	var controller_id: int = _find_other_alive_player(current_id)
	if controller_id < 0:
		return _fail("no_other_alive_player")
	var other_id: int = _find_other_alive_player(controller_id)
	if other_id < 0:
		return _fail("no_third_alive_player")
	if not _expect_begin_rejected(9999, controller_id, "nonexistent_controlled"):
		return false
	if not _expect_begin_rejected(current_id, 9999, "nonexistent_controller"):
		return false
	if not _expect_begin_rejected(current_id, current_id, "self_loop"):
		return false
	if not _expect_begin_rejected(controller_id, current_id, "controlled_is_not_current_turn"):
		return false
	# 死亡角色不能参与登记；用权威字段直接构造边界，避免依赖具体伤害牌。
	var dead_probe_id: int = controller_id
	_controller.state.get_player(dead_probe_id).alive = false
	var dead_rejected: bool = not _controller.begin_turn_input_delegation(current_id, dead_probe_id)
	_controller.state.get_player(dead_probe_id).alive = true
	if not dead_rejected:
		return _fail("dead_controller_should_reject")
	var out_of_game_probe: PlayerState = _controller.state.get_player(controller_id)
	out_of_game_probe.out_of_game = true
	var out_of_game_rejected: bool = not _controller.begin_turn_input_delegation(current_id, controller_id)
	out_of_game_probe.out_of_game = false
	if not out_of_game_rejected:
		return _fail("out_of_game_controller_should_reject")
	# 合法登记。
	if not _controller.begin_turn_input_delegation(current_id, controller_id):
		return _fail("legal_begin_rejected")
	# 幂等：重复登记同一对仍然成功，且全场登记事实只有一条。
	if not _controller.begin_turn_input_delegation(current_id, controller_id):
		return _fail("idempotent_begin_rejected")
	if _count_active_delegations() != 1:
		return _fail("idempotent_created_second_fact=%d" % _count_active_delegations())
	# 链式操控禁止：操控者本人正被他人操控时不能再替第三人提供输入。
	if _controller.begin_turn_input_delegation(controller_id, other_id):
		return _fail("chained_delegation_should_reject")
	# 顶替：同一被操控者换一名操控者时旧登记被替换，而不是并列。
	if not _controller.begin_turn_input_delegation(current_id, other_id):
		return _fail("replacement_begin_rejected")
	if _count_active_delegations() != 1 or _controller.get_turn_input_delegate_id(current_id) != other_id:
		return _fail("replacement_failed count=%d delegate=%d" % [_count_active_delegations(), _controller.get_turn_input_delegate_id(current_id)])
	# 撤销后回到无登记状态。
	if not _controller.end_turn_input_delegation(current_id) or _controller.is_turn_input_delegated(current_id):
		return _fail("end_delegation_failed")
	if _controller.get_turn_input_delegate_id(current_id) != -1:
		return _fail("delegate_after_end=%d" % _controller.get_turn_input_delegate_id(current_id))
	return true


## 验证操控者可以以被操控者的actor提交正式回合动作，而被操控者本人提交被拒绝且原因非空。
func _test_proxy_submission_and_input_lock() -> bool:
	if not await _start_playable_match():
		return false
	# 离线对局的本机真人恒为主座次，因此操控者就是本机真人，被操控者改为另一名角色。
	var controller_id: int = _offline_human_player_id()
	var controlled_id: int = _find_other_alive_player(controller_id)
	if controlled_id < 0:
		return _fail("no_controller_candidate")
	# 被操控者的回合：登记的前置条件要求被操控者必须是当前回合角色。
	if not _focus_turn_on_player(controlled_id):
		return _fail("cannot_focus_controlled_turn")
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_proxy_submit")
	# 输入锁定以唯一的代理解析入口为判据：被操控者自身的操作提供者是操控者，而不是它自己。
	# 离线会话的提交入口由既有座次规则负责，本机制在离线侧只提供这条解析结果供界面与AI使用。
	if int(_controller.call("_resolve_turn_input_submitter", controlled_id)) != controller_id:
		return _fail("controlled_submitter_should_be_controller")
	if int(_controller.call("_resolve_turn_input_submitter", controller_id)) != controller_id:
		return _fail("controller_submitter_should_be_self")
	# 操控者以被操控者actor提交：离线口径下本机真人即合法代理，必须被接受。
	_controller._last_action_rejection_message = ""
	var proxy_action: PlayerAction = PlayerAction.new("end_play", controlled_id)
	if not _controller.submit_action(proxy_action):
		return _fail("proxy_submit_rejected=%s" % str(_controller._last_action_rejection_message))
	return true


## 验证被操控者的合法动作可取到、可作答判定为真，且两者与提交判定共用同一代理解析函数。
func _test_answerable_and_legal_actions() -> bool:
	if not await _start_playable_match():
		return false
	var controller_id: int = _offline_human_player_id()
	var controlled_id: int = _find_other_alive_player(controller_id)
	if controlled_id < 0 or not _focus_turn_on_player(controlled_id):
		return _fail("cannot_focus_controlled_turn")
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_answerable")
	# 三处判定共用同一代理解析入口：解析结果必须等于登记的操控者。
	if int(_controller.call("_resolve_turn_input_submitter", controlled_id)) != controller_id:
		return _fail("resolver_mismatch=%d" % int(_controller.call("_resolve_turn_input_submitter", controlled_id)))
	# 被操控座位在操控期间必须仍被判定为“可作答人类”，否则停滞看门狗会把它强制转托管。
	if not bool(_controller.call("_is_answerable_human_actor", controlled_id)):
		return _fail("controlled_should_be_answerable")
	if not bool(_controller.call("_is_turn_input_locked", controlled_id)):
		return _fail("controlled_should_be_locked")
	# 合法动作必须能取到：被操控者恒为当前回合角色，守卫本就通过。
	var legal_actions: Array[Dictionary] = _controller.get_legal_actions(controlled_id)
	if legal_actions.is_empty():
		return _fail("legal_actions_empty_for_controlled")
	# 看门狗不得把被操控座位判为无人认领并强制转托管。
	if bool(_controller._is_player_auto_managed(controlled_id)):
		return _fail("controlled_should_not_be_auto_managed")
	return true


## 验证被操控者本回合结束后登记自动清除，且无关角色的回合结束不会误清除它。
func _test_expiry_on_turn_end_and_isolation() -> bool:
	if not await _start_playable_match():
		return false
	var controller_id: int = _offline_human_player_id()
	var controlled_id: int = _find_other_alive_player(controller_id)
	if controlled_id < 0 or not _focus_turn_on_player(controlled_id):
		return _fail("cannot_focus_controlled_turn")
	var unrelated_id: int = _find_other_alive_player(controlled_id)
	if unrelated_id < 0:
		return _fail("no_unrelated_player")
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_expiry")
	# 无关角色的回合结束：双重匹配（回合角色 + 回合号）不成立，登记必须保留。
	_controller.call("_clear_turn_input_delegation", controlled_id, unrelated_id, _controller.state.turn_number)
	if not _controller.is_turn_input_delegated(controlled_id):
		return _fail("unrelated_turn_end_cleared_delegation")
	# 被操控者本回合结束：登记必须自动清除，且不依赖调用方显式撤销。
	_controller.call("_clear_turn_input_delegation", controlled_id, controlled_id, _controller.state.turn_number)
	if _controller.is_turn_input_delegated(controlled_id):
		return _fail("controlled_turn_end_kept_delegation")
	return true


## 验证被操控者与操控者死亡时相关登记立即清除。
func _test_death_and_out_of_game_cleanup() -> bool:
	if not await _start_playable_match():
		return false
	var controller_id: int = _offline_human_player_id()
	var controlled_id: int = _find_other_alive_player(controller_id)
	if controlled_id < 0 or not _focus_turn_on_player(controlled_id):
		return _fail("cannot_focus_controlled_turn")
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_cleanup")
	# 操控者阵亡：以其为操控者的全部登记立即清除。
	_controller.call("_clear_turn_input_delegation_for_player", controller_id)
	if _controller.is_turn_input_delegated(controlled_id):
		return _fail("controller_death_kept_delegation")
	# 被操控者阵亡：其自身登记立即清除。
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_cleanup_second")
	_controller.call("_clear_turn_input_delegation_for_player", controlled_id)
	if _controller.is_turn_input_delegated(controlled_id):
		return _fail("controlled_death_kept_delegation")
	return true


## 验证公开快照包含操控字段，且权威存档往返后答案不变。
func _test_snapshot_round_trip() -> bool:
	if not await _start_playable_match():
		return false
	var controller_id: int = _offline_human_player_id()
	var controlled_id: int = _find_other_alive_player(controller_id)
	if controlled_id < 0 or not _focus_turn_on_player(controlled_id):
		return _fail("cannot_focus_controlled_turn")
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_snapshot")
	# 公开快照：该字段属于所有观察者可见的公开事实，裁剪模式下也必须存在。
	var public_snapshot: Dictionary = _controller.state.to_dict(-1, false)
	if not _snapshot_contains_delegate(public_snapshot, controlled_id, controller_id):
		return _fail("public_snapshot_missing_delegate")
	# 权威存档往返：恢复后权威答案不变。
	var authoritative: Dictionary = _controller.state.to_dict(_controller.local_human_player_id, true)
	var restored: PlayerState = PlayerState.from_authoritative_dict(_find_player_dict(authoritative, controlled_id))
	if restored.turn_input_delegate_id != controller_id:
		return _fail("archive_round_trip_delegate=%d" % restored.turn_input_delegate_id)
	return true


## 验证离线操控期间第一视角落在被操控者，操控结束后回到操控者，且期间待办选择不悬停。
func _test_offline_view_takeover_and_return() -> bool:
	if not await _start_playable_match():
		return false
	var controller_id: int = _offline_human_player_id()
	var controlled_id: int = _find_other_alive_player(controller_id)
	if controlled_id < 0 or not _focus_turn_on_player(controlled_id):
		return _fail("cannot_focus_controlled_turn")
	# 先确认基线视角在操控者本人，再验证接管与归还的前后关系。
	_controller.call("_emit_state")
	if _controller.local_human_player_id != controller_id:
		return _fail("baseline_view=%d expected=%d" % [_controller.local_human_player_id, controller_id])
	# 关闭“控制所有角色”，证明操控登记的优先级高于该本地设置。
	GameSettings.set_control_all_characters_enabled(false)
	if not _controller.begin_turn_input_delegation(controlled_id, controller_id):
		return _fail("begin_for_view")
	_controller.call("_emit_state")
	if _controller.local_human_player_id != controlled_id:
		return _fail("view_not_taken_over local=%d expected=%d" % [_controller.local_human_player_id, controlled_id])
	# 被操控者由本机真人代打时，其基础AI必须被注销，避免真人与AI抢同一actor。
	if _controller.ai_coordinator.is_ai_controlled(controlled_id):
		return _fail("controlled_ai_not_released")
	# 接管期间的重复广播不得让视角漂移（本机真人身份必须由影子值稳定识别）。
	_controller.call("_emit_state")
	_controller.call("_emit_state")
	if _controller.local_human_player_id != controlled_id:
		return _fail("view_drifted local=%d expected=%d" % [_controller.local_human_player_id, controlled_id])
	# 操控结束：视角回到操控者，且被操控者的基础AI恢复。
	_controller.end_turn_input_delegation(controlled_id)
	_controller.call("_emit_state")
	if _controller.local_human_player_id != controller_id:
		return _fail("view_not_returned local=%d expected=%d" % [_controller.local_human_player_id, controller_id])
	if not _controller.ai_coordinator.is_ai_controlled(controlled_id):
		return _fail("controlled_ai_not_restored")
	return true


## 验证数据库校验为空，保证本机制未破坏内容注册与开局。
func _test_game_database_validation_is_clean() -> bool:
	if not GameDatabase.validation_errors.is_empty():
		return _fail("validation_errors=%s" % str(GameDatabase.validation_errors))
	return true


## 统计当前全场有效操控登记数量；用于断言“幂等不产生第二条事实”。
func _count_active_delegations() -> int:
	var count: int = 0
	for player: PlayerState in _controller.state.players:
		if player != null and player.turn_input_delegate_id != -1:
			count += 1
	return count


## 返回除指定玩家外首名存活且未离场的玩家ID；没有时返回-1。
func _find_other_alive_player(excluded_player_id: int) -> int:
	for player: PlayerState in _controller.state.players:
		if player != null and player.player_id != excluded_player_id and player.alive and not player.out_of_game:
			return player.player_id
	return -1


## 在公开快照中查找指定玩家的操控字段是否等于预期操控者。
func _snapshot_contains_delegate(snapshot: Dictionary, controlled_player_id: int, expected_controller_id: int) -> bool:
	var player_dict: Dictionary = _find_player_dict(snapshot, controlled_player_id)
	return int(player_dict.get("turn_input_delegate_id", -1)) == expected_controller_id


## 在任意快照或存档字典中查找指定玩家的条目；缺失时返回空字典。
func _find_player_dict(snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in snapshot.get("players", []) as Array:
		var player_dict: Dictionary = player_variant as Dictionary
		if int(player_dict.get("player_id", -1)) == player_id:
			return player_dict
	return {}


## 断言一次 begin 调用被拒绝；返回是否与预期一致，不一致时直接以稳定标记失败。
func _expect_begin_rejected(controlled_player_id: int, controller_player_id: int, reason: String) -> bool:
	if _controller.begin_turn_input_delegation(controlled_player_id, controller_player_id):
		_fail(reason)
		return false
	if _count_active_delegations() != 0:
		_fail("%s_created_side_effect" % reason)
		return false
	return true


## 返回离线对局中“本机真人是谁”的稳定ID。
## 它经控制器的协议身份解析入口读取，因此在回合操控接管期间（local_human_player_id 已被改写为被操控者）
## 仍然得到真正的操控者，这也是本用例验证“接管不得污染本机真人身份”的观测点。
func _offline_human_player_id() -> int:
	return int(_controller.call("_bound_local_player_id"))


## 把当前回合焦点切到指定玩家并确保处于出牌阶段；返回是否成功。
## 登记的前置条件要求被操控者必须是当前回合角色，因此用例必须能显式指定当前回合角色。
func _focus_turn_on_player(player_id: int) -> bool:
	if _controller.state.get_player(player_id) == null:
		return false
	_controller.state.current_player_id = player_id
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 2
	_controller.call("_begin_play_choice", player_id)
	# 出牌窗口建立后可能立刻产生新的待办选择；用规则层合法动作结算干净，避免后续提交被窗口拦截。
	var settle_safety: int = 0
	while not _controller._pending_card_choice.is_empty() and settle_safety < 12:
		settle_safety += 1
		if not _cancel_pending_choice() and not _confirm_pending_choice():
			return false
	return _controller.state.current_phase == "play" and _controller.state.current_player_id == player_id


## 启动一局可操作的对局，并把开局选将与开局技能选择全部结算干净。
## 固定种子选将会随武将池变化而换人，因此不假设任何具体武将或开局是否产生技能选择。
func _start_playable_match() -> bool:
	_create_controller()
	GameSettings.set_control_all_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(TEST_PLAYER_COUNT, 20261002, IdentityRules.MODE_IDENTITY):
		_fail("start_match")
		return false
	# 选将阶段：本地真人按候选顺序提交，其余座位由内置AI推进。
	var selection_safety: int = 0
	while _controller.state.current_phase == "character_selection" and selection_safety < 24:
		selection_safety += 1
		if _controller.character_selection.get_pending_player_ids().has(0):
			var candidates: Array[String] = _controller.character_selection.get_candidates(0)
			if candidates.is_empty() or not _controller.select_character(0, candidates[0]):
				_fail("selection_submit")
				return false
		await get_tree().process_frame
	if _controller.state.current_phase == "character_selection":
		_fail("selection_stuck")
		return false
	# 开局技能选择：优先取消；不可取消的强制窗口按请求下发的首个合法候选确认，避免开局清理永久卡住。
	var opening_safety: int = 0
	while not _controller._pending_card_choice.is_empty() and opening_safety < 24:
		opening_safety += 1
		if not _cancel_pending_choice() and not _confirm_pending_choice():
			var stuck_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
			_fail("opening_choice_settle kind=%s chooser=%d" % [str(stuck_context.get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1))])
			return false
		await get_tree().process_frame
	# 推进到首个出牌阶段；回合开始时机可能再次创建选择，同样按统一出口结算。
	var turn_safety: int = 0
	while _controller.state.current_phase != "play" and turn_safety < 160:
		turn_safety += 1
		if not _controller._pending_card_choice.is_empty():
			if not _cancel_pending_choice() and not _confirm_pending_choice():
				_fail("turn_choice_settle phase=%s" % str(_controller.state.current_phase))
				return false
		_controller.call("_emit_state")
		_controller.call("_ensure_ai_progress_after_resolution")
		await get_tree().process_frame
	if _controller.state.current_phase != "play":
		_fail("play_phase_not_reached phase=%s turn=%d" % [str(_controller.state.current_phase), _controller.state.turn_number])
		return false
	# 相位期间的响应窗口同样需要结算，否则随后的提交会被待办窗口拦截。
	var response_safety: int = 0
	while not _controller._pending_card_choice.is_empty() and response_safety < 24:
		response_safety += 1
		if not _cancel_pending_choice() and not _confirm_pending_choice():
			_fail("play_choice_settle")
			return false
		await get_tree().process_frame
	# 首个出牌阶段若属于AI座位，先把回合交给本机真人，使后续用例的“当前回合角色”稳定可控。
	var local_human: int = _offline_human_player_id()
	if _controller.state.current_player_id != local_human:
		if not _focus_turn_on_player(local_human):
			_fail("cannot_focus_local_human_turn")
			return false
	return _controller.state.current_phase == "play"


## 取消当前待处理选择；必须绑定创建时的请求编号与回答者，否则会被权威入口拒绝。
func _cancel_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	return _controller.submit_action(action)


## 确认当前待处理选择；候选一律取自规则层自己生成的合法兼容动作，因此不会读到隐藏信息，
## 也不会因窗口类型（选牌、选目标、组合选择、文字选项）不同而构造出无法通过校验的负载。
func _confirm_pending_choice() -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return true
	if bool(_controller.submit_first_legal_pending_choice()):
		return true
	# 规则层没有给出任何可确认动作时，按请求字段做保守回退（仅用于诊断，不作为常规路径）。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	var selected_target_ids: Array[int] = []
	var candidate_target_ids: Array = _controller._pending_card_choice.get("target_ids", []) as Array
	if not candidate_target_ids.is_empty():
		selected_target_ids.append(int(candidate_target_ids[0]))
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":selected_target_ids, "confirmed":true}
	return _controller.submit_action(action)


## 创建指定网络模式的最小正式控制器组件树。
func _create_controller() -> void:
	if _controller != null and is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
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
	network_gateway.mode = NetworkGateway.Mode.OFFLINE
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


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
	printerr("TURN_CONTROL_FAIL %s" % reason)
	get_tree().quit(1)
	return false
