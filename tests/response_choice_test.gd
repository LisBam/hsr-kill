extends Node

## 延迟响应恢复回归。验证 AI 使用【杀】后，本地玩家提交【闪】能够完成原牌结算并重新安排 AI 后续行动。

## 测试使用的权威控制器；按正式场景组件结构装配，避免 UI 节点直接参与规则断言。
var _controller: MatchController

## 本地响应请求的只读快照；空字典表示尚未收到【闪】选择。
var _response_request: Dictionary = {}

## 测试用【闪】实体；提交后必须离开本地手牌并进入弃牌堆。
var _dodge_card: CardInstance

## 测试用【杀】实体；响应完成后必须从处理区收尾到弃牌堆。
var _slash_card: CardInstance

## 测试是否已经结束；异步提交与失败出口共用该标记避免重复退出。
var _finished: bool = false


## 延迟执行回归，确保自动加载数据已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 创建两人对局，强制 AI 角色对本地玩家使用【杀】，并等待下一帧模拟真实点击【闪】。
func _run() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；节点名称与正式控制器依赖路径保持一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；1号玩家通过基础策略注册为 AI，响应后应重新获得行动调度。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；保留正式选择来源与事件连接行为。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	# 响应恢复专项只验证请求与出牌阶段衔接，关闭阶段间表现等待以保持固定帧断言。
	_controller.game_flow_interval_seconds = 0.0
	# AI 延迟；留出两帧完成本地响应，并在结束前等待失效计时器自然回收。
	_controller.ai_action_delay_seconds = 0.05
	_controller.card_choice_requested.connect(_on_card_choice_requested)
	if not _controller.start_match(2, 7):
		_fail("start_match")
		return
	# 主公候选；固定种子保证本地0号玩家完成唯一的人类选将，其他角色由 AI 同步完成。
	var lord_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	if lord_candidates.is_empty() or not _controller.select_character(0, lord_candidates[0]):
		_fail("select_lord")
		return
	await get_tree().process_frame
	if _controller.state.current_phase != "play":
		_fail("initial_phase=%s" % _controller.state.current_phase)
		return
	# 本地目标状态；只保留测试【闪】，排除无懈可击和其他响应牌插入额外请求。
	var local_player: PlayerState = _controller.state.get_player(0)
	local_player.hand.clear()
	_dodge_card = CardInstance.new("shan", "heart", 2)
	_dodge_card.zone = "hand"
	_dodge_card.owner_id = local_player.player_id
	local_player.hand.append(_dodge_card)
	# AI 攻击者状态；只保留测试【杀】，随后开始其回合以创建合法 chooseToUse 请求。
	var attacker: PlayerState = _controller.state.get_player(1)
	attacker.hand.clear()
	_slash_card = CardInstance.new("sha", "spade", 7)
	_slash_card.zone = "hand"
	_slash_card.owner_id = attacker.player_id
	attacker.hand.append(_slash_card)
	_controller._start_turn(attacker.player_id)
	# 模拟原 AI 计时器已经取出本次动作；提交【杀】前清空待调度标记，响应恢复必须重新写入当前令牌。
	_controller._ai_drive_token += 1
	_controller._scheduled_ai_drive_token = -1
	if not _controller.submit_action(PlayerAction.new("use_card", attacker.player_id, _slash_card.uid, [local_player.player_id])):
		_fail("use_slash")
		return
	if _response_request.is_empty() or not _controller.has_pending_card_choice():
		_fail("missing_response_request")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished:
		return
	if _controller.has_pending_card_choice():
		_fail("response_still_pending")
		return
	if _controller.state.current_player_id != attacker.player_id or _controller.state.current_phase != "play":
		_fail("resume_state=%d:%s" % [_controller.state.current_player_id, _controller.state.current_phase])
		return
	if local_player.find_hand_card(_dodge_card.uid) != null or not _controller.state.discard_pile.has(_dodge_card):
		_fail("dodge_not_consumed")
		return
	if _controller.state.processing_area.has(_slash_card) or not _controller.state.discard_pile.has(_slash_card):
		_fail("slash_not_finalized")
		return
	if _controller._scheduled_ai_drive_token != _controller._ai_drive_token or not _controller._has_active_play_choice():
		_fail("ai_not_rescheduled")
		return
	# 已验证的恢复令牌；递增全局令牌让测试产生的两个短计时器安全失效并在退出前完成回收。
	var recovered_ai_token: int = _controller._scheduled_ai_drive_token
	_controller._ai_drive_token += 1
	await get_tree().create_timer(0.08).timeout
	print("RESPONSE_CHOICE_PASS phase=%s ai_token=%d" % [_controller.state.current_phase, recovered_ai_token])
	_finished = true
	get_tree().quit(0)


## 捕获本地【闪】请求并延迟到下一空闲帧提交，模拟玩家在窗口或手牌区完成真实操作。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	# 请求上下文；只有 slash_response 属于本用例，其他随机请求不应被误提交。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	if int(choice_data.get("chooser_id", -1)) != _controller.local_human_player_id or str(context.get("kind", "")) != "slash_response":
		return
	_response_request = choice_data.duplicate(true)
	call_deferred("_submit_dodge_response")


## 提交本地【闪】实体 UID；控制器仍会复核请求 ID、候选集合与响应模式。
func _submit_dodge_response() -> void:
	# 标准选牌动作；不直接消费卡牌或修改处理区。
	var action: PlayerAction = PlayerAction.new("choose_cards", _controller.local_human_player_id)
	action.payload = {
		"request_id":int(_response_request.get("request_id", -1)),
		"selected_card_uids":[_dodge_card.uid],
	}
	if not _controller.submit_action(action):
		_fail("submit_dodge")


## 输出稳定失败原因并以非0状态退出，便于命令行和持续集成立即定位恢复断言。
func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	printerr("RESPONSE_CHOICE_FAIL %s" % reason)
	get_tree().quit(1)
