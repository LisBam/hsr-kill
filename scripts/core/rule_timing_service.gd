class_name RuleTimingService
extends RefCounted

## 同步规则时机派发服务。它统一连接普通事件总线、四角色有序触发器和当前座次，不执行任何具体牌效。

## 当前普通规则事件总线；未配置时只返回完成状态事件，不执行普通订阅。
var event_bus: RuleEventBus

## 当前有序触发器管理器；未配置时跳过 firstDo、lastDo、优先级和座次派发。
var trigger_manager: TriggerManager

## 当前权威对局状态；用于读取存活座次和当前回合起点，不直接修改玩家或卡牌数据。
var state: GameState

## 当前触发器是否因刚创建的选择请求而必须暂停；由控制器注入，空 Callable 时保持同步派发兼容行为。
var trigger_pause_condition: Callable = Callable()


## 创建服务并绑定可替换依赖；测试和重新开局可继续调用 configure 更新状态与触发器实例。
func _init(rule_event_bus: RuleEventBus = null, ordered_trigger_manager: TriggerManager = null, game_state: GameState = null) -> void:
	configure(rule_event_bus, ordered_trigger_manager, game_state)


## 更新普通总线、有序触发器和权威状态；不会清理订阅，订阅生命周期仍由各组件自身管理。
func configure(rule_event_bus: RuleEventBus, ordered_trigger_manager: TriggerManager, game_state: GameState) -> void:
	event_bus = rule_event_bus
	trigger_manager = ordered_trigger_manager
	state = game_state


## 设置同一时机可选技能的暂停判定；条件只应在本次派发中新建选择请求时返回 true。
func set_trigger_pause_condition(pause_condition: Callable) -> void:
	trigger_pause_condition = pause_condition


## 创建并派发一条带 player/source/target/global 角色语义的规则时机；返回对象保留处理器修改和终止结果。
func emit(event_name: String, player_id: int = -1, source_id: int = -1, target_id: int = -1, event_data: Dictionary = {}) -> RuleEvent:
	# 新规则事件；所有上下文都会深复制，技能不能在事件完成后继续修改调用方字典。
	var event: RuleEvent = RuleEvent.new(event_name, source_id, target_id, event_data, player_id)
	return dispatch(event)


## 派发已有 RuleEvent；普通处理器先执行，事件仍运行时再按角色、分组、优先级和座次执行高级触发器。
func dispatch(event: RuleEvent) -> RuleEvent:
	if event == null:
		return null
	if event_bus != null:
		event_bus.dispatch(event)
	if trigger_manager != null and not event.is_terminal():
		# 当前存活玩家座次；死亡与离场角色不参与普通触发排序。
		var seat_order: Array[int] = _get_alive_seat_order()
		# 当前排序起点；优先使用当前回合角色，无有效回合时依次回退 player、source 和 target。
		var start_player_id: int = _resolve_start_player_id(event)
		trigger_manager.dispatch(event, start_player_id, seat_order, trigger_pause_condition)
	if not event.is_terminal() and (trigger_manager == null or not trigger_manager.is_dispatch_deferred(event)):
		event.finish()
	return event


## 恢复同一时机尚未执行的技能；返回 true 表示仍有选择、嵌套子时机或预算续列等待统一管线继续处理。
func resume_deferred_dispatches() -> bool:
	if trigger_manager == null:
		return false
	return trigger_manager.resume_deferred(trigger_pause_condition)


## 只恢复最内层的一条暂停或分片时机；判定等子流程可在父时机剩余处理器之前取得结算优先级。
func resume_next_deferred_dispatch() -> bool:
	if trigger_manager == null:
		return false
	return trigger_manager.resume_next_deferred(trigger_pause_condition)


## 返回当前存活角色的稳定玩家 ID 座次；状态为空时返回空数组并保持注册顺序。
func _get_alive_seat_order() -> Array[int]:
	# 座次结果；只保存稳定 ID，不向触发器暴露 PlayerState 可变引用。
	var result: Array[int] = []
	if state == null:
		return result
	for player: PlayerState in state.get_alive_players():
		result.append(player.player_id)
	return result


## 决定同一时机多角色触发的环形排序起点；全部无效时返回-1并按注册顺序处理全局项。
func _resolve_start_player_id(event: RuleEvent) -> int:
	if state != null and state.current_player_id >= 0:
		return state.current_player_id
	if event.player_id >= 0:
		return event.player_id
	if event.source_id >= 0:
		return event.source_id
	return event.target_id
