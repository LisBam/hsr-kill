class_name RuleStepSequence
extends RefCounted

## 可暂停规则步骤的内容对象；只保存游标与上下文，继续使用RuleContinuationQueue调度，不创建独立循环或计时器。

## 控制器分配的单调身份；默认-1表示未登记，内容步骤不得修改。
var sequence_id: int = -1

## 步骤共享的可序列化数据；默认空，不能存入节点或实体引用。
var context: Dictionary = {}

## 下一步骤游标；回调前递增，暂停恢复不重复扣费或执行效果。
var step: int = 0

## 最近派发的原始修改窗口；保留引用直至全部触发处理器完成，再读取最终data。
var waiting_event: RuleEvent

## 最近选择结果；默认空，提交后下一步可直接读取牌、目标及确认状态。
var choice_response: ChoiceResponse

## 剩余步骤是否终止；默认false，结束不会越过本步已产生的子结算。
var finished: bool = false

## 本步开始时的技能续接序号；默认0，用于区分新子结算与旧外层结算。
var skill_settlement_watermark: int = 0

## 创建内容时已存在的外层判定ID；默认-1，仅新判定才是本序列需要等待的子流程。
var enclosing_judgment_request_id: int = -1

## 创建序列时已存在的独立出牌阶段身份；仅等待之后插入的子阶段，不等待包含自己的外层阶段。
var enclosing_play_phase_id: int = -1

## 创建序列时已存在的额外弃牌阶段身份；子阶段结束恢复原内容，默认-1表示无外层阶段。
var enclosing_discard_phase_id: int = -1

## 只在当前对局内存中存在的内容回调；每项接收本对象，不进入网络快照。
var _steps: Array[Callable] = []

## 步骤所属RefCounted对象的强引用；Callable仅记录对象身份，暂停后局部服务不能提前析构。节点仍由场景树管理。
var _step_owners: Array[RefCounted] = []


## 创建独立上下文与步骤副本；不共享调用方可变容器。
func _init(steps: Array[Callable] = [], initial_context: Dictionary = {}) -> void:
	_steps = steps.duplicate()
	context = initial_context.duplicate(true)
	# 回调所有者；同一服务只持有一次，序列释放时一并释放，不写入共享上下文。
	for callback: Callable in _steps:
		if callback.is_valid() and callback.get_object() is RefCounted and not _step_owners.has(callback.get_object()):
			_step_owners.append(callback.get_object() as RefCounted)


## 执行唯一下一步；返回false表示回调已失效，应局部结束并报告。
func execute_next() -> bool:
	if finished or step >= _steps.size():
		finished = true
		return true
	# 当前回调；先推进游标，重入恢复不能再次执行本步骤。
	var callback: Callable = _steps[step]
	step += 1
	if not callback.is_valid():
		finished = true
		return false
	callback.call(self)
	if step >= _steps.size():
		finished = true
	return true


## 保存待完成修改窗口；下一步读取waiting_event.data而非派发时的早期快照。
func wait_for_timing(event: RuleEvent) -> void:
	waiting_event = event


## 在当前步骤之后插入子步骤，按传入顺序执行；用于由运行时目标或伤害点数决定的内容。
## 只能扩展尚未结束的序列；同一回调内多次调用时，后插入的批次先执行。
func insert_steps(steps: Array[Callable]) -> void:
	if finished:
		return
	# 插入偏移；保持调用方数组的先后顺序，不改变已完成步骤游标。
	var offset: int = 0
	# 新内容回调；动态加入的服务也需要强引用，选择等待期间不能提前析构。
	for callback: Callable in steps:
		_steps.insert(step + offset, callback)
		offset += 1
		if callback.is_valid() and callback.get_object() is RefCounted and not _step_owners.has(callback.get_object()):
			_step_owners.append(callback.get_object() as RefCounted)


## 结束未执行步骤；当前子选择与收尾仍由统一管线负责。
func finish() -> void:
	finished = true
