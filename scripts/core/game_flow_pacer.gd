class_name GameFlowPacer
extends Node

## 对局流程节奏组件。它只管理可取消的延时回调，不读取或修改任何玩法状态。

## 下一条延时任务的稳定令牌；从1开始，避免0与未创建任务混淆。
var _next_task_token: int = 1

## 每个业务键当前有效的任务令牌；同键新任务会使旧计时器自然失效。
var _task_tokens_by_key: Dictionary = {}


## 按业务键安排一次延时回调；延时为0时同步执行，便于规则测试关闭表现节奏。
func schedule(task_key: String, delay_seconds: float, callback: Callable) -> int:
	cancel(task_key)
	# 当前任务令牌；计时结束时必须仍与业务键登记值一致才允许执行。
	var task_token: int = _next_task_token
	_next_task_token += 1
	_task_tokens_by_key[task_key] = task_token
	if delay_seconds <= 0.0:
		_execute_if_current(task_key, task_token, callback)
	else:
		_run_after_delay(task_key, task_token, delay_seconds, callback)
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


## 等待指定秒数后尝试执行任务；计时器服从场景树暂停，暂停期间不会消耗流程间隔。
func _run_after_delay(task_key: String, task_token: int, delay_seconds: float, callback: Callable) -> void:
	await get_tree().create_timer(delay_seconds, false).timeout
	_execute_if_current(task_key, task_token, callback)


## 仅执行仍为该业务键最新版本的回调；执行前删除登记值，允许回调继续安排下一阶段。
func _execute_if_current(task_key: String, task_token: int, callback: Callable) -> void:
	if int(_task_tokens_by_key.get(task_key, -1)) != task_token:
		return
	_task_tokens_by_key.erase(task_key)
	if callback.is_valid():
		callback.call()
