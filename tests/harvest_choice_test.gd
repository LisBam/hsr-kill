extends Node

## 五谷丰登选择回归。验证出牌请求占用运行时序号后，交互窗口仍能登记唯一请求并在本地点击后完整恢复结算。

## 测试使用的权威控制器；按正式场景的组件结构装配，不依赖图形界面节点。
var _controller: MatchController

## 本地玩家实际收到的五谷选择请求数量；固定应为1次，避免重复恢复同一目标。
var _local_harvest_choice_count: int = 0

## 五谷触发前仍活动的 chooseToUse 请求 ID；五谷窗口必须取得不同的全局编号。
var _active_play_request_id: int = -1

## 测试是否已经进入终态；异步回调与失败出口共用该标记防止重复退出。
var _finished: bool = false

## 是否已经在首个五谷选择请求前收到固定公共牌位；用于验证使用后立即展示窗口。
var _saw_initial_public_display: bool = false

## 是否看到本地玩家领取后仍保留原牌位并写入领取者 ID；用于验证复制虚影所需权威数据。
var _saw_taken_public_slot: bool = false

## 是否在五谷全部结算后收到公共展示清理信号；用于防止窗口永久残留到后续阶段。
var _saw_public_display_cleared: bool = false


## 延迟执行完整回归，确保自动加载数据与控制器子节点已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 创建两人对局并在活动 chooseToUse 请求存在时插入五谷选择，复现请求序号交错场景。
func _run() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；名称必须与控制器公开组件路径保持一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；用于让非本地目标同步完成后续展示牌选择。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；保留正式请求来源判断与信号连接行为。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.card_choice_requested.connect(_on_card_choice_requested)
	_controller.public_card_choice_display_changed.connect(_on_public_card_choice_display_changed)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	# 请求序号专项只验证规则恢复，关闭阶段间表现等待以同步进入首个出牌阶段。
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0
	if not _controller.start_match(2, 7):
		_fail("start_match")
		return
	# 主公候选；固定种子下本地0号玩家为当前唯一待确认的人类角色。
	var lord_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	if lord_candidates.is_empty() or not _controller.select_character(0, lord_candidates[0]):
		_fail("select_lord")
		return
	await get_tree().process_frame
	if _controller.state.current_phase != "play":
		_fail("play_phase=%s" % _controller.state.current_phase)
		return
	# 最终座次玩家名；本地真实玩家不带前缀，内置 AI 使用“[AI]玩家X”且X读取旋转后的当前座次。
	for seat_index: int in range(_controller.state.players.size()):
		# 当前座次玩家；稳定 player_id 只用于判断控制权，显示编号必须使用seat_index+1。
		var seated_player: PlayerState = _controller.state.players[seat_index]
		# 当前座次预期显示名；真实玩家无前缀，AI 玩家添加固定前缀。
		var expected_name: String = "玩家%d" % (seat_index + 1) if seated_player.player_id == _controller.local_human_player_id else "[AI]玩家%d" % (seat_index + 1)
		if seated_player.display_name != expected_name:
			_fail("player_name=%s/%s" % [seated_player.display_name, expected_name])
			return
	# 本地玩家状态；清空随机起始手牌，避免无懈可击插入另一种选择窗口干扰本用例。
	var local_player: PlayerState = _controller.state.get_player(0)
	local_player.hand.clear()
	# 原五谷实体牌；通过真实使用牌事件进入处理区，恢复结束后必须只执行一次并进入弃牌堆。
	var parent_card: CardInstance = CardInstance.new("wugu", "heart", 2)
	parent_card.zone = "hand"
	parent_card.owner_id = 0
	local_player.hand.append(parent_card)
	# 起始出牌请求在测试改写手牌前已经生成；先关闭并重建，使权威候选包含新加入的五谷实体。
	_controller._cancel_active_play_choice("harvest_test_refresh")
	_controller._begin_play_choice(0)
	_active_play_request_id = _controller._play_choice_request_id
	if _active_play_request_id < 0:
		_fail("missing_play_request")
		return
	# 标准使用牌动作；全体目标由规则层自动展开，不能直接调用卡牌 resolve 绕过真实 content 恢复链。
	var use_action: PlayerAction = PlayerAction.new("use_card", 0, parent_card.uid)
	if not _controller.submit_action(use_action):
		_fail("submit_wugu")
		return
	if not await _wait_until_harvest_finished(parent_card.uid):
		return
	if _finished:
		return
	if _controller.has_pending_card_choice():
		_fail("pending_after_choice")
		return
	if _local_harvest_choice_count != 1:
		_fail("local_choice_count=%d" % _local_harvest_choice_count)
		return
	if not _saw_initial_public_display or not _saw_taken_public_slot or not _saw_public_display_cleared:
		_fail("public_display=%s/%s/%s" % [_saw_initial_public_display, _saw_taken_public_slot, _saw_public_display_cleared])
		return
	if _controller.state.processing_area.has(parent_card) or not _controller.state.discard_pile.has(parent_card):
		_fail("parent_not_finalized")
		return
	if _controller.state.current_phase != "play":
		_fail("resume_phase=%s" % _controller.state.current_phase)
		return
	print("HARVEST_CHOICE_PASS request_count=%d phase=%s" % [_local_harvest_choice_count, _controller.state.current_phase])
	_finished = true
	get_tree().quit(0)


## 等待真实五谷事件完成；超时通常表示整牌 content 恢复后重复执行或选择链未能继续。
func _wait_until_harvest_finished(parent_card_uid: int) -> bool:
	# 最多等待帧数；零延迟 AI 仍需要若干进程帧提交第二名角色的展示牌选择。
	var maximum_wait_frames: int = 180
	for _frame_index: int in range(maximum_wait_frames):
		await get_tree().process_frame
		if _finished:
			return false
		# 父牌已经离开处理区且没有待选请求时，真实 CardUseEvent 已完成内容与弃牌收尾。
		var parent_still_processing: bool = false
		for processing_card: CardInstance in _controller.state.processing_area:
			if processing_card.uid == parent_card_uid:
				parent_still_processing = true
				break
		if not parent_still_processing and not _controller.has_pending_card_choice():
			return true
	_fail("harvest_timeout")
	return false


## 接收本地五谷窗口并在下一空闲帧提交第一张展示牌，模拟真实 UI 点击发生在信号调用栈结束之后。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	if int(choice_data.get("chooser_id", -1)) != _controller.local_human_player_id or str(choice_data.get("title", "")) != "五谷丰登":
		return
	if int(choice_data.get("request_id", -1)) == _active_play_request_id:
		_fail("request_id_collision=%d" % _active_play_request_id)
		return
	if not _saw_initial_public_display:
		_fail("choice_before_public_display")
		return
	# 当前展示候选；五谷强制单选，因此候选不能为空。
	var candidates: Array = choice_data.get("candidates", []) as Array
	if candidates.is_empty():
		_fail("empty_candidates")
		return
	_local_harvest_choice_count += 1
	call_deferred("_submit_harvest_choice", choice_data.duplicate(true))


## 记录五谷公共展示生命周期；牌位数量固定为2，领取后只改变归属字段，不删除原牌位。
func _on_public_card_choice_display_changed(display_data: Dictionary) -> void:
	if display_data.is_empty():
		_saw_public_display_cleared = true
		return
	if str(display_data.get("kind", "")) != "harvest":
		return
	# 固定公共牌位；两人五谷从开始到结束都应保留最初亮出的2个位置。
	var display_slots: Array = display_data.get("slots", []) as Array
	if display_slots.size() != 2:
		_fail("public_slot_count=%d" % display_slots.size())
		return
	# 当前快照已领取牌位数量；初始应为0，本地选择完成后至少出现1个归属。
	var taken_count: int = 0
	for slot_variant: Variant in display_slots:
		# 当前牌位归属；初始为-1，本地领取后其中恰好一项变为0。
		var taken_by_player_id: int = int((slot_variant as Dictionary).get("taken_by_player_id", -1))
		if taken_by_player_id >= 0:
			taken_count += 1
			if taken_by_player_id == 0:
				_saw_taken_public_slot = true
	if taken_count == 0:
		_saw_initial_public_display = true


## 把模拟点击转换为标准 choose_cards 动作；返回 false 表示窗口与权威运行时请求不一致。
func _submit_harvest_choice(choice_data: Dictionary) -> void:
	# 提交时使用的展示候选副本；UID 必须仍属于收到的同一请求。
	var candidates: Array = choice_data.get("candidates", []) as Array
	# 标准选牌动作；请求 ID 与所选实体 UID 都由控制器再次校验。
	var action: PlayerAction = PlayerAction.new("choose_cards", _controller.local_human_player_id)
	action.payload = {
		"request_id":int(choice_data.get("request_id", -1)),
		"selected_card_uids":[int((candidates[0] as Dictionary).get("uid", -1))],
	}
	if not _controller.submit_action(action):
		_fail("submit_choice")


## 输出稳定失败原因并以非0状态退出，便于命令行和持续集成立即定位断言。
func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	printerr("HARVEST_CHOICE_FAIL %s" % reason)
	get_tree().quit(1)
