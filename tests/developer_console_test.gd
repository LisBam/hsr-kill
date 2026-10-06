extends Node

## 开发者调试效果专项回归。验证纯数据队列语义、空闲边界消费、顺序保持与活跃性兜底。
##
## 设计意图：开发者效果必须是「排队后由统一结算管线在空闲边界消费」，
## 因此本用例不伪造队列，而是使用正式 MatchController 与正式结算管线，
## 只断言「入队 → 未同步生效 → 排空后生效」这一时序契约。

## 本测试共用的权威对局控制器；使用正式结算管线而非伪造实现。
var _controller: MatchController

## 控制器广播的开发者效果执行结果；按发生顺序保存深拷贝供断言。
var _results: Array[Dictionary] = []

## 本测试共用的开发者菜单窗口；直接实例化正式场景，验证结构与交互契约。
## 窗口不依赖 MatchController，因此可以在同一个用例里独立驱动。
var _panel: DeveloperConsolePanel

## 测试用效果载荷上限副本；用于校验队列上限而无需真的排空 64 条。
const MAX_PENDING: int = 64

## 开发者菜单窗口场景；与桌面 preload 同一路径，保证测试验证的就是正式装配件。
const DEVELOPER_CONSOLE_PANEL_SCENE: PackedScene = preload("res://scenes/components/developer_console_panel.tscn")


## 延后一帧运行专项断言；确保 MatchController 及其动态组件已完成 _ready。
func _ready() -> void:
	call_deferred("_run")


## 依次验证队列语义、管线时序与活跃性兜底；任一失败立即以非 0 退出。
func _run() -> void:
	_create_controller()
	_configure_minimal_match_state()
	if not _test_queue_validation_guards():
		return
	if not _test_fifo_order_and_reset():
		return
	if not _test_effect_deferred_to_idle_boundary():
		return
	if not _test_effect_order_preserved():
		return
	if not _test_stale_match_and_dead_target_discarded():
		return
	if not _test_async_port_reports_submitted():
		return
	if not _test_recover_full_hp_reports_ineffective():
		return
	if not _test_discard_empty_hand_reports_ineffective():
		return
	if not await _test_liveness_hook_after_early_return():
		return
	if not await _test_idle_submission_wakes_pipeline():
		return
	if not _test_reset_hook_clears_queue():
		return
	_create_panel()
	if not _test_panel_structure_and_theme():
		return
	if not _test_panel_amount_resolution():
		return
	if not _test_panel_target_selection():
		return
	if not _test_panel_sub_view_navigation_and_signals():
		return
	print("DEVELOPER_CONSOLE_PASS results=%d" % _results.size())
	_controller.queue_free()
	_panel.queue_free()
	get_tree().quit(0)


## 创建与正式场景同类型的控制器和三个必需子节点；其余组件由控制器自行按需创建。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 普通规则事件总线；开发者效果测试仍使用正式时机服务依赖。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；最小状态不注册策略，只满足控制器 _ready 契约。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；测试不发送网络消息，但保留正式权威端路由。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.developer_effect_resolved.connect(_on_developer_effect_resolved)


## 建立两名存活玩家的最小权威状态；专用 test 阶段使排空后不触发正常回合游标。
func _configure_minimal_match_state() -> void:
	_controller.state = GameState.new()
	_controller.state.match_id = "developer-console"
	_controller.state.current_phase = "test"
	_controller.state.current_player_id = 0
	# 调试目标；固定体力便于断言回复与上限变化。
	var target: PlayerState = PlayerState.new(0, "调试目标")
	target.identity = "leader"
	target.max_hp = 4
	target.hp = 4
	# 旁观者；仅用于验证「目标已不在场」的丢弃分支，保持领袖存活以免提前判定胜负。
	var bystander: PlayerState = PlayerState.new(1, "旁观者")
	bystander.identity = "loyalist"
	bystander.max_hp = 4
	bystander.hp = 4
	_controller.state.players.append(target)
	_controller.state.players.append(bystander)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, _controller.state)
	_controller._configure_rule_dispatch_guards()


## 每个子用例开始前清空队列与已收集结果；避免前一个用例的残留影响断言。
func _reset_case() -> void:
	_controller._get_developer_effects().reset()
	_results.clear()


## 验证入队校验：未知效果键、数值与载荷语义混用、越界目标与队列上限都必须被拒绝。
func _test_queue_validation_guards() -> bool:
	_reset_case()
	# 未知效果键；界面拼写错误不能被静默接受。
	if _controller.request_developer_effect("not_a_real_effect", 0, 1):
		return _fail("validation_unknown_kind_accepted")
	# 数值类效果缺少正数；0 与负数都必须被拒绝，避免产生无意义条目。
	if _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 0):
		return _fail("validation_zero_amount_accepted")
	if _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, -3):
		return _fail("validation_negative_amount_accepted")
	# 载荷类效果携带数值；两种语义混用会让日志无法诊断，必须拒绝。
	if _controller.request_developer_effect(DeveloperEffectService.EFFECT_REPLACE_CHARACTER, 0, 5, {"character_id":"march_7th"}):
		return _fail("validation_payload_kind_with_amount_accepted")
	# 不存在的目标座次；不能把效果落到空座上。
	if _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 99, 1):
		return _fail("validation_unknown_target_accepted")
	# 合法请求必须被接受，且计数立即反映排队状态。
	if not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1) or _controller.get_developer_effect_pending_count() != 1:
		return _fail("validation_valid_request_rejected count=%d" % _controller.get_developer_effect_pending_count())
	# 队列上限；填满后第 65 条必须被拒绝，避免脚本误循环把队列撑成无界内存。
	_reset_case()
	for fill_index: int in range(MAX_PENDING):
		if not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1):
			return _fail("validation_fill_rejected_at=%d" % fill_index)
	if _controller.get_developer_effect_pending_count() != MAX_PENDING:
		return _fail("validation_fill_count=%d" % _controller.get_developer_effect_pending_count())
	if _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1):
		return _fail("validation_overflow_accepted")
	_reset_case()
	# 离线特权表面：联机（含房主）必须被控制器端口直接拒绝，而不是只靠界面入口隐藏。
	# 这是纵深防御的断言——绕过界面直接调用端口时，联机对局同样不得受理调试效果。
	_controller.network_gateway.mode = NetworkGateway.Mode.LAN
	if _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1):
		_controller.network_gateway.mode = NetworkGateway.Mode.OFFLINE
		return _fail("validation_lan_accepted")
	if _controller.get_developer_effect_pending_count() != 0:
		_controller.network_gateway.mode = NetworkGateway.Mode.OFFLINE
		return _fail("validation_lan_enqueued=%d" % _controller.get_developer_effect_pending_count())
	_controller.network_gateway.mode = NetworkGateway.Mode.OFFLINE
	# 复位后必须重新受理，证明上面的拒绝来自联机判定而不是端口整体失效。
	if not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1):
		return _fail("validation_offline_restore_rejected")
	_reset_case()
	return true


## 验证队列是先进先出且 reset 与 drain_discarded 语义正确。
func _test_fifo_order_and_reset() -> bool:
	_reset_case()
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1)
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 1, 2)
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 3)
	# 队列快照顺序；必须与提交顺序一致，保证界面点击顺序就是结算顺序。
	var queued: Array[Dictionary] = _controller._get_developer_effects().to_array()
	# 各条目标座次与数值；逐项校验而不是只比较长度。
	var observed: Array = []
	for entry: Dictionary in queued:
		observed.append([int(entry.get("target_player_id", -1)), int(entry.get("amount", -1))])
	if observed != [[0, 1], [1, 2], [0, 3]]:
		return _fail("fifo_order=%s" % [observed])
	# 丢弃计数必须等于当前待办数，且丢弃后队列为空。
	if _controller._get_developer_effects().drain_discarded() != 3 or _controller.get_developer_effect_pending_count() != 0:
		return _fail("drain_discarded count=%d" % _controller.get_developer_effect_pending_count())
	# reset 必须同时清空队列并让服务回到可继续入队的干净状态。
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1)
	_controller._get_developer_effects().reset()
	if _controller.get_developer_effect_pending_count() != 0 or not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1):
		return _fail("reset_then_enqueue_rejected")
	_reset_case()
	return true


## 验证效果「入队不同步生效、排空后才生效」；这是本功能的核心时序契约。
func _test_effect_deferred_to_idle_boundary() -> bool:
	_reset_case()
	# 目标初始护盾；用于对比入队前后的同步状态。
	var shield_before: int = _controller.state.get_player(0).shield
	if not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 3):
		return _fail("deferred_enqueue_rejected")
	# 入队后同步读取：效果尚未执行，护盾不得变化。
	if _controller.state.get_player(0).shield != shield_before:
		return _fail("deferred_applied_synchronously shield=%d" % _controller.state.get_player(0).shield)
	if _controller.get_developer_effect_pending_count() != 1:
		return _fail("deferred_pending_count=%d" % _controller.get_developer_effect_pending_count())
	# 驱动正式结算管线；空闲边界应消费该条目并真正结算。
	_controller.resume_settlement_pipeline()
	if _controller.state.get_player(0).shield != shield_before + 3:
		return _fail("deferred_not_applied shield=%d expected=%d" % [_controller.state.get_player(0).shield, shield_before + 3])
	if _controller.get_developer_effect_pending_count() != 0:
		return _fail("deferred_queue_not_drained=%d" % _controller.get_developer_effect_pending_count())
	# 执行结果必须通过信号广播，且标记为已生效。
	if _results.size() != 1 or not bool(_results[0].get("ok", false)):
		return _fail("deferred_result=%s" % [_results])
	return true


## 验证多条效果按提交顺序逐条结算，而不是被合并或逆序执行。
func _test_effect_order_preserved() -> bool:
	_reset_case()
	# 目标体力；用两条失去体力验证顺序与累加效果。
	var hp_before: int = _controller.state.get_player(0).hp
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_LOSE_HP, 0, 1)
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_LOSE_HP, 0, 2)
	_controller.resume_settlement_pipeline()
	if _controller.state.get_player(0).hp != hp_before - 3:
		return _fail("order_total hp=%d expected=%d" % [_controller.state.get_player(0).hp, hp_before - 3])
	# 结果顺序；第一条必须是 1 点，第二条必须是 2 点。
	var amounts: Array = []
	for result: Dictionary in _results:
		amounts.append(str(result.get("text", "")))
	if _results.size() != 2 or not amounts[0].contains("1 点体力") and not amounts[0].contains("1点体力"):
		return _fail("order_results=%s" % [amounts])
	if not amounts[1].contains("2点体力"):
		return _fail("order_second=%s" % [amounts])
	return true


## 验证上一局遗留条目与已失效目标都会被丢弃且给出可读结果，绝不静默丢失。
func _test_stale_match_and_dead_target_discarded() -> bool:
	_reset_case()
	# 直接以错误对局标识入队，模拟上一局遗留的待办。
	if not _controller._get_developer_effects().enqueue(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 5, "another-match"):
		return _fail("stale_enqueue_rejected")
	# 目标护盾；作废条目不得产生任何数值变化。
	var shield_before: int = _controller.state.get_player(0).shield
	_controller.resume_settlement_pipeline()
	if _controller.state.get_player(0).shield != shield_before:
		return _fail("stale_match_applied shield=%d" % _controller.state.get_player(0).shield)
	if _results.size() != 1 or bool(_results[0].get("ok", true)):
		return _fail("stale_match_result=%s" % [_results])

	_reset_case()
	# 目标阵亡后再排空；条目必须被丢弃而不是落到无效角色上。
	if not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 1, 4):
		return _fail("dead_target_enqueue_rejected")
	_controller.state.get_player(1).alive = false
	_controller.resume_settlement_pipeline()
	if _controller.state.get_player(1).shield != 0:
		return _fail("dead_target_applied shield=%d" % _controller.state.get_player(1).shield)
	if _results.size() != 1 or bool(_results[0].get("ok", true)):
		return _fail("dead_target_result=%s" % [_results])
	# 复位旁观者，避免影响后续用例。
	_controller.state.get_player(1).alive = true
	return true


## 验证异步端口（摸牌 / 受到伤害）只报「已提交」，不会因为同步状态未变而误报「未生效」。
func _test_async_port_reports_submitted() -> bool:
	_reset_case()
	# 摸牌堆准备；保证摸牌有实体可取。
	for draw_index: int in range(5):
		_controller.state.draw_pile.append(CardInstance.new("sha", "spade", draw_index + 1))
	var hand_before: int = _controller.state.get_player(0).hand.size()
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_DRAW, 0, 2)
	_controller.resume_settlement_pipeline()
	if _results.size() != 1 or not bool(_results[0].get("ok", false)):
		return _fail("async_draw_result=%s" % [_results])
	# 异步端口必须报告「已提交」，而不是把同步未变化误判成失败。
	if not str(_results[0].get("text", "")).contains("已提交"):
		return _fail("async_draw_text=%s" % str(_results[0].get("text", "")))
	# 摸牌序列在同一轮排空中提交；手牌应增加，若未增加则说明管线未推进该序列。
	if _controller.state.get_player(0).hand.size() <= hand_before:
		return _fail("async_draw_not_settled hand=%d before=%d" % [_controller.state.get_player(0).hand.size(), hand_before])

	_reset_case()
	# 无来源伤害；只验证「已提交」与不崩溃，具体扣血由伤害时机链完成。
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_DAMAGE, 0, 1)
	_controller.resume_settlement_pipeline()
	if _results.size() != 1 or not bool(_results[0].get("ok", false)) or not str(_results[0].get("text", "")).contains("已提交"):
		return _fail("async_damage_result=%s" % [_results])
	return true


## 验证满体力时的回复被如实报告为未生效，而不是让开发者误以为功能损坏。
func _test_recover_full_hp_reports_ineffective() -> bool:
	_reset_case()
	# 满体力前提；权威回复服务在满体力时会静默早退，服务层必须据此给出可读结果。
	var target: PlayerState = _controller.state.get_player(0)
	target.hp = target.max_hp
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_RECOVER, 0, 2)
	_controller.resume_settlement_pipeline()
	if _results.size() != 1 or bool(_results[0].get("ok", true)):
		return _fail("recover_full_result=%s" % [_results])
	if not str(_results[0].get("text", "")).contains("体力已满"):
		return _fail("recover_full_text=%s" % str(_results[0].get("text", "")))
	# 受伤后的回复必须真正生效，验证前一条并非因为功能整体失效而通过。
	_reset_case()
	target.hp = target.max_hp - 1
	var hp_before: int = target.hp
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_RECOVER, 0, 1)
	_controller.resume_settlement_pipeline()
	if target.hp != hp_before + 1:
		return _fail("recover_wounded_hp=%d expected=%d" % [target.hp, hp_before + 1])
	return true


## 验证空手牌时的弃牌请求被如实报告，而不是创建一个无法完成的待办选择。
func _test_discard_empty_hand_reports_ineffective() -> bool:
	_reset_case()
	# 目标手牌清空；权威端没有可弃置的候选，服务层必须在提交前收敛为可读结果。
	var target: PlayerState = _controller.state.get_player(0)
	target.hand.clear()
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_DISCARD, 0, 2)
	_controller.resume_settlement_pipeline()
	if _results.size() != 1 or bool(_results[0].get("ok", true)):
		return _fail("discard_empty_result=%s" % [_results])
	if not str(_results[0].get("text", "")).contains("没有手牌"):
		return _fail("discard_empty_text=%s" % str(_results[0].get("text", "")))
	# 不得留下待办选择，否则管线会被永久挡住。
	if _controller.has_pending_card_choice():
		return _fail("discard_empty_left_pending_choice")
	return true


## 验证活跃性兜底：入口作废旧唤醒后若本次排空零消费，开发者队列必须让控制器重新登记唤醒。
##
## 这是本功能最容易踩的结构性陷阱：开发者队列自身不登记唤醒，
## 若不计入 `_has_unresolved_settlement_work()`，就会形成永久滞留。
func _test_liveness_hook_after_early_return() -> bool:
	_reset_case()
	_controller._reset_settlement_runtime_guard()
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1)
	# 模拟入口次序：先作废旧唤醒，再用规则序列深度门控让本次排空在消费前立即返回。
	_controller._invalidate_scheduled_settlement_resume()
	_controller._rule_sequence_execution_depth += 1
	_controller.resume_settlement_pipeline()
	_controller._rule_sequence_execution_depth -= 1
	# 队列仍有待办且没有等待外部输入，因此必须重新登记唯一唤醒。
	if _controller.get_developer_effect_pending_count() != 1:
		return _fail("liveness_queue_unexpectedly_drained=%d" % _controller.get_developer_effect_pending_count())
	if not _controller._settlement_resume_scheduled:
		return _fail("liveness_wakeup_missing pending=%d" % _controller.get_developer_effect_pending_count())
	# 放行后唯一唤醒必须真正把队列排空。
	await get_tree().process_frame
	if _controller.get_developer_effect_pending_count() != 0:
		return _fail("liveness_not_drained=%d" % _controller.get_developer_effect_pending_count())
	return true


## 验证对局静止（管线空闲）时提交的效果仍会被唯一延后唤醒自动执行。
##
## 这是「按下按钮后效果在空闲时间执行」最直接的证据：本用例**不手工驱动管线**，
## 只提交请求并等待一帧，唤醒必须自行把队列排空。若登记时漏掉唤醒，
## 条目会一直躺在队列里等到下一次无关的结算推进，对局静止时表现为「点了没反应」。
func _test_idle_submission_wakes_pipeline() -> bool:
	_reset_case()
	_controller._reset_settlement_runtime_guard()
	# 目标护盾；用于对比唤醒前后的同步状态。
	var shield_before: int = _controller.state.get_player(0).shield
	if not _controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 2):
		return _fail("idle_enqueue_rejected")
	# 入队后同步状态不得改变：效果必须等到管线空闲边界才执行。
	if _controller.state.get_player(0).shield != shield_before:
		return _fail("idle_applied_synchronously shield=%d" % _controller.state.get_player(0).shield)
	# 唯一延后唤醒通过 process_frame 跨帧执行；本用例不调用 resume_settlement_pipeline()。
	await get_tree().process_frame
	if _controller.state.get_player(0).shield != shield_before + 2:
		return _fail("idle_wakeup_missing shield=%d expected=%d" % [_controller.state.get_player(0).shield, shield_before + 2])
	if _controller.get_developer_effect_pending_count() != 0:
		return _fail("idle_not_drained=%d" % _controller.get_developer_effect_pending_count())
	return true


## 验证每局重置入口会清空开发者队列；避免上一局待办落到新一局角色身上。
func _test_reset_hook_clears_queue() -> bool:
	_reset_case()
	_controller.request_developer_effect(DeveloperEffectService.EFFECT_GAIN_SHIELD, 0, 1)
	if _controller.get_developer_effect_pending_count() != 1:
		return _fail("reset_hook_precondition=%d" % _controller.get_developer_effect_pending_count())
	# 正式每局重置入口；开发者队列必须与规则续接队列一起被清空。
	_controller._reset_per_match_progress_state()
	if _controller.get_developer_effect_pending_count() != 0:
		return _fail("reset_hook_not_cleared=%d" % _controller.get_developer_effect_pending_count())
	return true


## 收集一条开发者效果执行结果；深复制保证后续改动不影响已收集断言。
func _on_developer_effect_resolved(result_data: Dictionary) -> void:
	_results.append(result_data.duplicate(true))


## 创建并挂载开发者菜单窗口；窗口自身不读取规则状态，可脱离控制器独立验证。
func _create_panel() -> void:
	_panel = DEVELOPER_CONSOLE_PANEL_SCENE.instantiate() as DeveloperConsolePanel
	_panel.name = "DeveloperConsolePanel"
	add_child(_panel)


## 构造目标候选列表；只提供窗口契约要求的三个字段。
func _make_target_candidates(player_ids: Array) -> Array[Dictionary]:
	# 目标候选；显示文字只用于呈现，座次才是窗口回传的稳定标识。
	var candidates: Array[Dictionary] = []
	for player_id_variant: Variant in player_ids:
		# 当前座次；测试只用非负座次。
		var player_id: int = int(player_id_variant)
		candidates.append({"player_id":player_id, "display_text":"玩家%d" % (player_id + 1), "is_local":player_id == 0})
	return candidates


## 构造一个 Esc 按下事件；用于直接驱动窗口的取消输入分支。
func _make_escape_event() -> InputEventKey:
	# 合成键盘事件；只需要 keycode 与按下状态，窗口同时接受 ui_cancel 动作与原始 Esc 键。
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


## 递归收集指定类型的后代节点；用于结构断言与字体色审计。
func _collect_descendants_by_class(root: Node, target_class: String) -> Array[Node]:
	# 命中结果；保持深度优先顺序，便于稳定定位失败项。
	var matches: Array[Node] = []
	for child: Node in root.get_children():
		if child.is_class(target_class):
			matches.append(child)
		matches.append_array(_collect_descendants_by_class(child, target_class))
	return matches


## 验证窗口结构与主题契约：层级、效果行数据化、滑条范围与字体色覆盖。
func _test_panel_structure_and_theme() -> bool:
	if _panel == null:
		return _fail("panel_missing")
	# 层级必须落在局内菜单 500 与回放覆盖层 620 之间，避免被菜单遮挡或盖住回放。
	if _panel.z_index != DeveloperConsolePanel.CONSOLE_Z_INDEX or _panel.z_index != 520:
		return _fail("panel_z_index=%d" % _panel.z_index)
	# 效果行必须完全由声明表驱动；两者数量不一致说明存在硬编码分支。
	if _panel._effect_rows.size() != DeveloperConsolePanel.EFFECT_DECLARATIONS.size():
		return _fail("panel_row_count=%d expected=%d" % [_panel._effect_rows.size(), DeveloperConsolePanel.EFFECT_DECLARATIONS.size()])
	# 数值类与载荷类的行结构；数值类必须同时具备滑条与输入框，载荷类必须两者都没有。
	var amount_row_count: int = 0
	var payload_row_count: int = 0
	for declaration: Dictionary in DeveloperConsolePanel.EFFECT_DECLARATIONS:
		# 当前效果键；用于定位控件组。
		var effect_kind: String = str(declaration.get("kind", ""))
		var row: Dictionary = _panel._effect_rows.get(effect_kind, {}) as Dictionary
		if row.get("button") == null:
			return _fail("panel_row_missing_button kind=%s" % effect_kind)
		if bool(declaration.get("uses_amount", true)):
			amount_row_count += 1
			if row.get("slider") == null or row.get("input") == null:
				return _fail("panel_amount_row_missing_controls kind=%s" % effect_kind)
			# 滑条范围必须是 1..10 且步长为 1；输入框的无上限行为由取值解析用例覆盖。
			var slider: HSlider = row.get("slider") as HSlider
			if int(slider.min_value) != 1 or int(slider.max_value) != 10 or int(slider.step) != 1:
				return _fail("panel_slider_range=%s" % [[slider.min_value, slider.max_value, slider.step]])
		else:
			payload_row_count += 1
			if row.get("slider") != null or row.get("input") != null:
				return _fail("panel_payload_row_has_controls kind=%s" % effect_kind)
	# 需求固定为「九个数值效果 + 两个纯按钮」，数量漂移必须让用例失败。
	if amount_row_count != 9 or payload_row_count != 2:
		return _fail("panel_row_split amount=%d payload=%d" % [amount_row_count, payload_row_count])
	# 字体色覆盖：窗口内每个 Label 都必须带 font_color，否则主题切换后会回退默认白字。
	var label_nodes: Array[Node] = _collect_descendants_by_class(_panel, "Label")
	if label_nodes.is_empty():
		return _fail("panel_no_labels")
	for label_node: Node in label_nodes:
		if not (label_node as Label).has_theme_color_override("font_color"):
			return _fail("panel_label_missing_font_color name=%s" % label_node.name)
	return true


## 验证数值取值解析：滑条驱动输入框、输入框优先且无上限、非法与越界输入收敛。
func _test_panel_amount_resolution() -> bool:
	# 任取一条数值效果行；所有数值行共用同一套解析逻辑。
	var effect_kind: String = DeveloperEffectService.EFFECT_DRAW
	var row: Dictionary = _panel._effect_rows.get(effect_kind, {}) as Dictionary
	var slider: HSlider = row.get("slider") as HSlider
	var input: LineEdit = row.get("input") as LineEdit
	if slider == null or input == null:
		return _fail("panel_amount_row_missing_controls")
	# 滑条单向驱动输入框文本，避免两者互相触发形成回环。
	slider.value = 7
	if input.text != "7" or _panel._resolve_amount(effect_kind) != 7:
		return _fail("panel_slider_to_input text=%s resolved=%d" % [input.text, _panel._resolve_amount(effect_kind)])
	# 输入框优先于滑条；滑条仍为 7，但输入框写 42 时必须提交 42（输入框不设上限）。
	input.text = "42"
	if _panel._resolve_amount(effect_kind) != 42:
		return _fail("panel_resolve_input_over_slider=%d" % _panel._resolve_amount(effect_kind))
	# 非法文本回退滑条值，而不是静默变成 0 或 1。
	input.text = "abc"
	if _panel._resolve_amount(effect_kind) != 7:
		return _fail("panel_resolve_invalid_fallback=%d" % _panel._resolve_amount(effect_kind))
	# 空文本同样回退滑条值。
	input.text = ""
	if _panel._resolve_amount(effect_kind) != 7:
		return _fail("panel_resolve_empty_fallback=%d" % _panel._resolve_amount(effect_kind))
	# 下限钳制：0 与负数都被抬到 1，避免提交无意义条目。
	input.text = "0"
	if _panel._resolve_amount(effect_kind) != 1:
		return _fail("panel_resolve_zero_clamp=%d" % _panel._resolve_amount(effect_kind))
	input.text = "-5"
	if _panel._resolve_amount(effect_kind) != 1:
		return _fail("panel_resolve_negative_clamp=%d" % _panel._resolve_amount(effect_kind))
	input.text = "1"
	return true


## 验证目标选择：默认本机、刷新保留选择、目标失效回退、空列表收敛为未选择。
func _test_panel_target_selection() -> bool:
	# 初始注入：默认选中本机玩家（座次 0）。
	_panel.set_target_candidates(_make_target_candidates([0, 1]), 0)
	if _panel._selected_target_id != 0:
		return _fail("panel_default_target=%d" % _panel._selected_target_id)
	# 切换到座次 1；随后的快照刷新必须保留该选择，而不是每次都重置回默认目标。
	_panel._on_target_selected(1)
	if _panel._selected_target_id != 1:
		return _fail("panel_switch_target=%d" % _panel._selected_target_id)
	_panel.set_target_candidates(_make_target_candidates([0, 1]), 0)
	if _panel._selected_target_id != 1:
		return _fail("panel_selection_not_preserved=%d" % _panel._selected_target_id)
	# 目标离场：原选择失效时必须回退到首选目标，而不是保留一个不可用的座次。
	_panel.set_target_candidates(_make_target_candidates([0, 2]), 2)
	if _panel._selected_target_id != 2:
		return _fail("panel_fallback_target=%d" % _panel._selected_target_id)
	# 空列表：必须收敛为 -1，使效果按钮转为提示而不是提交到空座。
	_panel.set_target_candidates([], 0)
	if _panel._selected_target_id != -1:
		return _fail("panel_empty_target=%d" % _panel._selected_target_id)
	# 复原候选，避免影响后续用例。
	_panel.set_target_candidates(_make_target_candidates([0, 1]), 0)
	return true


## 验证第二层视图导航与意图信号：窗口只发信号，且 Esc 优先级为「先返回、后关闭」。
func _test_panel_sub_view_navigation_and_signals() -> bool:
	_panel.set_target_candidates(_make_target_candidates([0, 1]), 0)
	_panel.open_console()
	# 意图信号记录；窗口不得直接改写任何规则状态，只能通过这些信号表达请求。
	var close_requests: Array = []
	var draw_pile_requests: Array = []
	var effect_requests: Array = []
	_panel.close_requested.connect(func() -> void: close_requests.append(true))
	_panel.draw_pile_candidates_requested.connect(func() -> void: draw_pile_requests.append(true))
	_panel.effect_requested.connect(func(kind: String, target_id: int, amount: int) -> void: effect_requests.append([kind, target_id, amount]))
	# 进入摸牌堆视图：必须先请求桌面注入牌面，并切换到第二层视图。
	_panel._on_effect_pressed(DeveloperEffectService.EFFECT_GAIN_DRAW_PILE_CARD)
	if draw_pile_requests.size() != 1:
		return _fail("panel_draw_pile_request_missing=%d" % draw_pile_requests.size())
	if _panel._view != DeveloperConsolePanel.View.DRAW_PILE or not _panel._draw_pile_view.visible or _panel._main_view.visible:
		return _fail("panel_draw_pile_view_state")
	# Esc 在第二层只返回主视图，不得直接关闭窗口。
	_panel._unhandled_input(_make_escape_event())
	if _panel._view != DeveloperConsolePanel.View.MAIN or close_requests.size() != 0:
		return _fail("panel_sub_view_escape view=%d closes=%d" % [_panel._view, close_requests.size()])
	# 主视图按 Esc 才请求关闭。
	_panel._unhandled_input(_make_escape_event())
	if close_requests.size() != 1:
		return _fail("panel_main_escape_closes=%d" % close_requests.size())
	# 窗口隐藏时不得吞掉 Esc，否则牌桌的取消与结束出牌会失效。
	_panel.visible = false
	_panel._unhandled_input(_make_escape_event())
	if close_requests.size() != 1:
		return _fail("panel_hidden_escape_consumed=%d" % close_requests.size())
	_panel.visible = true
	# 数值效果按钮必须按「当前目标 + 当前输入数值」发出请求。
	var row: Dictionary = _panel._effect_rows.get(DeveloperEffectService.EFFECT_LOSE_HP, {}) as Dictionary
	(row.get("input") as LineEdit).text = "3"
	_panel._on_effect_pressed(DeveloperEffectService.EFFECT_LOSE_HP)
	if effect_requests.size() != 1 or effect_requests[0] != [DeveloperEffectService.EFFECT_LOSE_HP, 0, 3]:
		return _fail("panel_effect_request=%s" % [effect_requests])
	# 未选择目标时不得发出效果请求，只应给出提示。
	_panel.set_target_candidates([], 0)
	_panel._on_effect_pressed(DeveloperEffectService.EFFECT_LOSE_HP)
	if effect_requests.size() != 1:
		return _fail("panel_effect_without_target=%s" % [effect_requests])
	_panel.set_target_candidates(_make_target_candidates([0, 1]), 0)
	return true


## 输出失败原因并以非 0 状态结束场景；返回 false 便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	printerr("DEVELOPER_CONSOLE_FAIL %s" % reason)
	get_tree().quit(1)
	return false
