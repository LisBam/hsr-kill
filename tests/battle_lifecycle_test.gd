extends Node

## 战斗事件所有权回归；直接验证取消、迟到响应、结果发布和真正跨帧让步，不依赖看门狗修复状态。

## 本轮测试失败标志；初始false，任何断言失败后以非零退出，避免后续成功信息掩盖失败。
var _failed: bool = false


## 在场景初始化后运行回归，使调度器分帧回调拥有真实SceneTree。
func _ready() -> void:
	call_deferred("_run")


## 依次检查相互独立的生命周期契约；每个用例拥有独立调度器与事件树。
func _run() -> void:
	_test_cancel_owned_subtree()
	_test_finish_publication()
	_test_reset_rejects_old_choice()
	_test_reject_terminal_timeout()
	_test_missing_parent()
	_test_rescheduled_frame_ownership()
	await _test_frame_budget()
	if not _failed:
		print("BATTLE_LIFECYCLE_PASS cancellation publication stale_response frame_budget")
	get_tree().quit(1 if _failed else 0)


## 取消父事件必须终止普通子树、释放其全部暂停并保留after；全局网络暂停仍由网络所有者释放。
func _test_cancel_owned_subtree() -> void:
	# 独立运行时；测试结束立即释放，避免测试自身留下信号或节点。
	var scheduler: EventScheduler = EventScheduler.new()
	add_child(scheduler)
	# 根事件；主动取消发生在子选择等待期间，after仍须运行一次。
	var parent: GameEvent = scheduler.create_event("parent")
	# 尚未结束的选择子事件；取消后旧响应必须被拒绝。
	var child: GameEvent = scheduler.create_child(parent.event_id, "choice")
	# 收尾执行次数；引用数组用于在无捕获对象循环的回调中记数。
	var cleanup_count: Array[int] = [0]
	scheduler.create_child(parent.event_id, "cleanup", "test", [func(_event: GameEvent, _runtime: EventScheduler) -> void: cleanup_count[0] += 1], {}, "after")
	# 子选择请求；零材料可取消请求用于隔离区域和牌面规则。
	var request: ChoiceRequest = ChoiceRequest.new(child.event_id, 0, "bool", "continue")
	scheduler.request_choice(request)
	# 子事件另一独立暂停；取消所有权必须同时清理选择和内容暂停。
	scheduler.pause("content", "child work", child.event_id)
	scheduler.start(parent.event_id)
	# 外部全局暂停；父事件取消不可替网络释放它。
	var network_token: int = scheduler.pause_global("network", "connection")
	parent.cancel("test_cancel")
	scheduler.drain()
	_check(scheduler.get_pending_choice_requests().is_empty(), "cancel leaves pending choice")
	_check(child.finalized and child.status == GameEvent.Status.ABORTED, "cancel leaves live child")
	_check(scheduler.pause_registry.get_active_tokens().size() == 1, "cancel releases wrong token owners")
	_check(not scheduler.submit_choice(ChoiceResponse.new(request.request_id, child.event_id, 0, true)), "cancel accepts old response")
	scheduler.resume(network_token)
	_check(cleanup_count[0] == 1 and parent.finalized and parent.status == GameEvent.Status.CANCELLED, "cancel loses terminal state or after")
	_check(scheduler.get_live_event_count() == 0, "cancel leaks events")
	scheduler.free()


## 完成信号观察到的是已提交状态；监听者不得看见仍占栈的已结束子事件或父事件旧结果。
func _test_finish_publication() -> void:
	# 独立运行时；父事件在子事件完成时仍处于事件栈。
	var scheduler: EventScheduler = EventScheduler.new()
	add_child(scheduler)
	# 父事件；无步骤即可验证子结果回写顺序。
	var parent: GameEvent = scheduler.create_event("parent")
	# 子事件；结果必须先交给父事件再向外发布完成信号。
	var child: GameEvent = scheduler.create_child(parent.event_id, "child", "test", [func(event: GameEvent, _runtime: EventScheduler) -> void: event.result = {"value":7}])
	# 原子发布观察结果；默认false，只有子完成信号才写入。
	var committed: Array[bool] = [false]
	scheduler.event_finished.connect(func(snapshot: Dictionary) -> void:
		if int(snapshot.get("event_id", -1)) == child.event_id:
			committed[0] = parent.result.get("value") == 7 and scheduler.get_current_event_id() == parent.event_id
	)
	scheduler.start(parent.event_id)
	_check(committed[0], "finish signal precedes state commit")
	scheduler.free()


## 同一运行时重开不能复用请求身份；之前的网络应答不得通过新局相同座位的选择校验。
func _test_reset_rejects_old_choice() -> void:
	# 独立运行时；reset模拟控制器重开对局。
	var scheduler: EventScheduler = EventScheduler.new()
	add_child(scheduler)
	# 旧事件与旧请求；两局角色相同，仅运行时身份用于区分。
	var old_event: GameEvent = scheduler.create_event("old")
	# 旧局请求；不依赖请求候选，排除内容校验偶然拒绝的干扰。
	var old_request: ChoiceRequest = ChoiceRequest.new(old_event.event_id, 0, "bool", "old")
	scheduler.request_choice(old_request)
	# 迟到响应；重置后仍保留它的旧请求与事件ID。
	var old_response: ChoiceResponse = ChoiceResponse.new(old_request.request_id, old_event.event_id, 0, false)
	scheduler.reset()
	# 新局事件；即使名称、角色、候选相同也必须获得全新身份。
	var new_event: GameEvent = scheduler.create_event("new")
	# 新局请求；始终保持待答，不能被旧响应消费。
	var new_request: ChoiceRequest = ChoiceRequest.new(new_event.event_id, 0, "bool", "new")
	scheduler.request_choice(new_request)
	_check(not scheduler.submit_choice(old_response), "reset accepts previous match response")
	scheduler.abort_all()
	_check(scheduler.get_live_event_count() == 0, "abort_all retains live event objects")
	scheduler.free()


## 超时回调与普通响应遵循同一终态校验；取消后尚未排空的事件也不能被托管重新写入。
func _test_reject_terminal_timeout() -> void:
	# 独立运行时；直接取消后不先drain，以覆盖超时和取消发生在同一调用栈的边界。
	var scheduler: EventScheduler = EventScheduler.new()
	add_child(scheduler)
	# 待选择事件；取消仅设置终态，清理仍由调度器完成。
	var event: GameEvent = scheduler.create_event("timeout_owner")
	# 权威请求；布尔选择不引入候选筛选，让测试只验证终态所有权。
	var request: ChoiceRequest = ChoiceRequest.new(event.event_id, 0, "bool", "timeout")
	scheduler.request_choice(request)
	# 合法迟到应答；即使候选与角色合法，也不能恢复已经取消的事件。
	var response: ChoiceResponse = ChoiceResponse.new(request.request_id, event.event_id, 0, false)
	event.cancel("test_terminal")
	_check(not scheduler.timeout_choice(request.request_id, response), "timeout revives terminal event")
	_check(event.result.is_empty(), "rejected timeout writes result")
	scheduler.abort_all()
	_check(scheduler.pause_registry.get_active_tokens().is_empty(), "timeout cleanup leaks token")
	scheduler.free()


## 不存在的父事件无法拥有新内容；失败创建应立即归档，不在live索引中留下孤儿。
func _test_missing_parent() -> void:
	# 独立运行时；空索引使指定父ID确定不存在。
	var scheduler: EventScheduler = EventScheduler.new()
	add_child(scheduler)
	# 孤儿子事件；已终止摘要仍可供诊断，实际可执行对象不得被运行时保留。
	var orphan: GameEvent = scheduler.create_child(999, "orphan")
	_check(orphan.finalized and orphan.status == GameEvent.Status.ABORTED, "missing parent leaves active child")
	_check(scheduler.get_live_event_count() == 0, "missing parent leaks live object")
	scheduler.free()


## 同帧多次直接接管排空时，旧信号必须释放；reset不能留下等待下一帧才失效的连接。
func _test_rescheduled_frame_ownership() -> void:
	# 小预算运行时；重复步骤确保每次手工接管后仍有下一帧工作。
	var scheduler: EventScheduler = EventScheduler.new()
	scheduler.max_operations_per_drain = 4
	add_child(scheduler)
	# 可中断任务；测试只检查调度所有权，随后reset主动结束，不触发自旋上限。
	var event: GameEvent = scheduler.create_event("reschedule", "test", [func(current: GameEvent, _runtime: EventScheduler) -> void: current.redo()])
	scheduler.start(event.event_id)
	scheduler.drain()
	scheduler.drain()
	# 属于当前调度器的活动帧连接数；任意多次直接接管后应始终只有1条。
	var connection_count: int = 0
	# 当前帧连接快照；按所属对象统计，忽略场景中其他合法连接。
	for connection: Dictionary in get_tree().process_frame.get_connections():
		if (connection["callable"] as Callable).get_object() == scheduler:
			connection_count += 1
	_check(connection_count == 1, "explicit drain retains obsolete frame connections")
	scheduler.reset()
	connection_count = 0
	# 当前帧连接快照；按所属对象统计，忽略场景中其他合法连接。
	for connection: Dictionary in get_tree().process_frame.get_connections():
		if (connection["callable"] as Callable).get_object() == scheduler:
			connection_count += 1
	_check(connection_count == 0, "reset retains scheduler frame connection")
	scheduler.free()


## 多轮预算不能在同一空闲帧无限call_deferred；用真实帧号而非回调次数证明让步。
func _test_frame_budget() -> void:
	# 小预算运行时；每帧4次调度操作使12次合法redo至少跨越3批。
	var scheduler: EventScheduler = EventScheduler.new()
	scheduler.max_operations_per_drain = 4
	add_child(scheduler)
	# 每次执行所在的真实进程帧；默认空，用于验证分批确实让出主循环。
	var execution_frames: Array[int] = []
	# 有限任务；合法12次执行不应触发任何熔断。
	var event: GameEvent = scheduler.create_event("finite", "test", [func(current: GameEvent, _runtime: EventScheduler) -> void:
		execution_frames.append(Engine.get_process_frames())
		if execution_frames.size() < 12:
			current.redo()
	])
	scheduler.start(event.event_id)
	# 等待帧索引；最多10帧足够完成3个预算批次并收尾，不使用墙钟超时掩盖死循环。
	for wait_frame: int in range(10):
		if event.finalized:
			break
		await get_tree().process_frame
	_check(event.finalized and execution_frames.size() == 12, "finite work fails to complete")
	_check(execution_frames.size() == 12 and execution_frames[4] != execution_frames[8], "deferred drains consume same frame")
	scheduler.free()


## 记录全部失败，便于一次运行定位独立根因；不自动修正被测状态。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("BATTLE_LIFECYCLE_FAIL: " + message)
