class_name GameFlowPacer
extends Node

## 对局流程节奏组件。它只管理可取消的延时回调，不读取或修改任何玩法状态。

## 下一条延时任务的稳定令牌；从1开始，避免0与未创建任务混淆。
var _next_task_token: int = 1

## 每个业务键当前有效的任务令牌；同键新任务会使旧计时器自然失效。
var _task_tokens_by_key: Dictionary = {}


## 按业务键安排一次延时回调；延时为0时同步执行，process_always用于暂停规则流程期间仍需完成的纯表现等待。
func schedule(task_key: String, delay_seconds: float, callback: Callable, process_always: bool = false) -> int:
	cancel(task_key)
	# 当前任务令牌；计时结束时必须仍与业务键登记值一致才允许执行。
	var task_token: int = _next_task_token
	_next_task_token += 1
	_task_tokens_by_key[task_key] = task_token
	if delay_seconds <= 0.0:
		_execute_if_current(task_key, task_token, callback)
	else:
		_run_after_delay(task_key, task_token, delay_seconds, callback, process_always)
	return task_token


## 取消指定业务键的待执行任务；已经完成或不存在的键安全忽略。
func cancel(task_key: String) -> void:
	_task_tokens_by_key.erase(task_key)


## 取消全部待执行任务；重新开局和节点退出时使用，旧计时器恢复后不会调用业务代码。
func cancel_all() -> void:
	_task_tokens_by_key.clear()


## 返回指定业务键是否仍有有效任务；只用于调度防重与回归测试，不暴露计时器对象。
func has_pending(task_key: String) -> bool:
	return _task_tokens_by_key.has(task_key)


## 返回是否存在任意尚未执行的流程延时任务；供测试与全量取消前查询，不直接作为出牌恢复条件。
func has_any_pending() -> bool:
	return not _task_tokens_by_key.is_empty()


## 返回是否存在会创建下一段技能选择的流程间隔任务。
## 排除 `response_prompt:*` 与 `phase_transition`：前者只延时 UI 提示，后者只推进阶段；二者残留不得阻塞出牌阶段 chooseToUse 恢复。
func has_pending_skill_interval() -> bool:
	for task_key_variant: Variant in _task_tokens_by_key.keys():
		# 当前业务键；技能多步间隔使用 `skill_id:owner_id:task_name` 格式。
		var task_key: String = str(task_key_variant)
		if task_key.begins_with("response_prompt:") or task_key == "phase_transition":
			continue
		return true
	return false


## 等待指定秒数后尝试执行任务；普通流程计时器服从场景树暂停，process_always任务可在暂停期间完成已展示的固定等待。
func _run_after_delay(task_key: String, task_token: int, delay_seconds: float, callback: Callable, process_always: bool) -> void:
	await get_tree().create_timer(delay_seconds, process_always).timeout
	_execute_if_current(task_key, task_token, callback)


## 仅执行仍为该业务键最新版本的回调；执行前删除登记值，允许回调继续安排下一阶段。
func _execute_if_current(task_key: String, task_token: int, callback: Callable) -> void:
	if int(_task_tokens_by_key.get(task_key, -1)) != task_token:
		return
	_task_tokens_by_key.erase(task_key)
	if callback.is_valid():
		callback.call()
