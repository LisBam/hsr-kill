class_name RuleContinuationQueue
extends RefCounted

## 规则续接栈。同步规则在插入异步选择前保存可序列化后续步骤，最内层事件完成后按后进先出顺序恢复。

## 下一条续接记录的稳定编号；从1递增，0与负数始终表示无效记录，重新开局时恢复默认值。
var _next_continuation_id: int = 1

## 尚未恢复的续接记录；数组尾部是最内层中断点，记录只包含稳定类型和可序列化上下文。
var _continuations: Array[Dictionary] = []


## 压入一条规则续接并返回稳定编号；空类型会被拒绝，调用方不能保存 Callable 或运行时对象。
func push(continuation_type: String, context: Dictionary = {}) -> int:
	if continuation_type.is_empty():
		return -1
	# 当前续接稳定编号；父流程可在同步子事件完成后精确移除预先登记的保险续接点。
	var continuation_id: int = _next_continuation_id
	_next_continuation_id += 1
	_continuations.append({
		"continuation_id":continuation_id,
		"continuation_type":continuation_type,
		"context":context.duplicate(true),
	})
	return continuation_id


## 弹出最内层续接记录；没有等待项时返回空字典，返回值与内部存储完全分离。
func pop() -> Dictionary:
	if _continuations.is_empty():
		return {}
	# 最内层续接记录；后进先出保证嵌套选择先恢复直接父事件，再恢复更外层流程。
	var continuation: Dictionary = _continuations.pop_back() as Dictionary
	return continuation.duplicate(true)


## 返回最内层续接记录的深拷贝但不移除；结算管线可据此让模式边界等待技能后续先完成。
func peek() -> Dictionary:
	if _continuations.is_empty():
		return {}
	return (_continuations.back() as Dictionary).duplicate(true)


## 按稳定编号移除一条尚未恢复的记录；用于子事件同步完成时撤销父流程预先登记的保险续接点。
func remove(continuation_id: int) -> bool:
	# 倒序续接索引；从栈顶开始查找最近父流程，取值范围为现有记录下标至0。
	for continuation_index: int in range(_continuations.size() - 1, -1, -1):
		# 当前候选续接；从栈顶向下查找可优先命中最近建立的父流程记录。
		var continuation: Dictionary = _continuations[continuation_index] as Dictionary
		if int(continuation.get("continuation_id", -1)) == continuation_id:
			_continuations.remove_at(continuation_index)
			return true
	return false


## 返回是否存在尚未恢复的规则后半段；只读查询不会暴露内部数组引用。
func has_pending() -> bool:
	return not _continuations.is_empty()


## 返回等待续接数量；测试、诊断和流程保护可据此判断是否已经完全排空。
func size() -> int:
	return _continuations.size()


## 返回全部等待记录的深拷贝；顺序保持由外层到内层，禁止调用方修改后写回。
func to_array() -> Array[Dictionary]:
	# 对外快照数组；默认空数组，调用方取得的内容不会共享内部字典引用。
	var result: Array[Dictionary] = []
	# 当前待复制续接；遍历顺序保持从最外层到最内层，不改变真实栈结构。
	for continuation: Dictionary in _continuations:
		result.append(continuation.duplicate(true))
	return result


## 清空旧对局全部续接并重置稳定编号；重新开局、终局和半成品开局失败都必须调用。
func reset() -> void:
	_continuations.clear()
	_next_continuation_id = 1
