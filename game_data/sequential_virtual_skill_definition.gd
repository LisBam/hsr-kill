class_name SequentialVirtualSkillDefinition
extends SkillDefinition

## 连续无材料虚拟用牌技能基类。组件按队列逐张提交标准CardUseEvent，上一张完整结束或取消后才开始下一张。

## 当前连续用牌队列；每项保存actor_id、definition_id、target_ids、rule_overrides与可选日志，默认空数组表示没有任务。
var _virtual_card_sequence_entries: Array[Dictionary] = []

## 当前连续用牌完成上下文；仅保存可序列化字段，最后一张结束后交给子类完成技能自身推进。
var _virtual_card_sequence_completion_context: Dictionary = {}

## 当前连续用牌递增令牌；初始0，每次建立新队列加1，旧卡牌结束时机不能恢复新队列。
var _virtual_card_sequence_token: int = 0

## 当前是否正在等待一张虚拟牌完成生命周期；true时禁止重复提交队首，卡牌结束时恢复false。
var _virtual_card_sequence_waiting: bool = false


## 安装连续虚拟用牌完成监听；子类install必须调用一次，卸载仍由SkillDefinition统一按owner清理。
func install_virtual_card_sequence_listener() -> void:
	subscribe_timing("useCardAfter", _on_virtual_sequence_card_finished, "global")
	subscribe_timing("useCardCancelled", _on_virtual_sequence_card_finished, "global")


## 建立一组按顺序执行的无材料虚拟牌；已有队列未结束时拒绝覆盖，避免两个技能动作交叉消费同一完成事件。
func start_cardless_virtual_card_sequence(entries: Array[Dictionary], completion_context: Dictionary = {}) -> bool:
	if host == null or entries.is_empty() or _virtual_card_sequence_waiting or not _virtual_card_sequence_entries.is_empty():
		return false
	_virtual_card_sequence_token += 1
	_virtual_card_sequence_completion_context = completion_context.duplicate(true)
	for entry: Dictionary in entries:
		_virtual_card_sequence_entries.append(entry.duplicate(true))
	_execute_next_virtual_sequence_card()
	return true


## 处理基类连续用牌恢复上下文；子类continue_settlement应先调用本函数，返回true表示上下文已被消费。
func continue_virtual_card_sequence_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "sequential_virtual_card_continue" or int(context.get("sequence_token", -1)) != _virtual_card_sequence_token:
		return false
	_execute_next_virtual_sequence_card()
	return true


## 连续虚拟牌全部完成后的扩展点；子类在此推进轮回、清理本次目标或继续自身效果。
func on_virtual_card_sequence_completed(_context: Dictionary) -> void:
	pass


## 提交队首虚拟牌；非法条目会被跳过，全部条目耗尽后只调用一次完成钩子。
func _execute_next_virtual_sequence_card() -> void:
	if _virtual_card_sequence_waiting:
		return
	while not _virtual_card_sequence_entries.is_empty():
		# 当前队首条目；先移出队列，卡牌同步结束时也不会再次提交同一张牌。
		var entry: Dictionary = _virtual_card_sequence_entries.pop_front() as Dictionary
		# 虚拟牌业务存储；组件稳定标签与子类字段合并，保留卡牌生命周期内的来源追踪。
		var virtual_storage: Dictionary = (entry.get("virtual_storage", {}) as Dictionary).duplicate(true)
		virtual_storage["sequence_skill_owner_id"] = owner_player_id
		virtual_storage["sequence_skill_id"] = get_id()
		virtual_storage["sequence_token"] = _virtual_card_sequence_token
		_virtual_card_sequence_waiting = true
		# 本张虚拟牌目标；条目必须只包含整数ID，异常值由统一卡牌规则拒绝。
		var target_ids: Array[int] = []
		for target_id_variant: Variant in entry.get("target_ids", []) as Array:
			target_ids.append(int(target_id_variant))
		# 本张虚拟牌是否已成功提交；只有true才等待卡牌结束时机，false则继续跳过失效条目。
		var submitted: bool = bool(host.call("execute_cardless_virtual_card_use", int(entry.get("actor_id", owner_player_id)), str(entry.get("definition_id", "")), target_ids, str(entry.get("log_message", "")), entry.get("rule_overrides", {}) as Dictionary, virtual_storage))
		if submitted:
			return
		_virtual_card_sequence_waiting = false
	# 完成上下文副本；先清理运行时状态，完成钩子可以安全建立下一组新队列。
	var completion_context: Dictionary = _virtual_card_sequence_completion_context.duplicate(true)
	_virtual_card_sequence_completion_context.clear()
	on_virtual_card_sequence_completed(completion_context)


## 识别当前队列所提交虚拟牌的结束或取消时机，并把下一张登记到统一技能结算队列。
func _on_virtual_sequence_card_finished(event: RuleEvent) -> void:
	if event == null or not _virtual_card_sequence_waiting:
		return
	# 逻辑牌存储；只有本技能、本持有者且令牌一致的牌可以释放当前等待状态。
	var virtual_storage: Dictionary = event.data.get("virtual_storage", {}) as Dictionary
	if int(virtual_storage.get("sequence_skill_owner_id", -1)) != owner_player_id or str(virtual_storage.get("sequence_skill_id", "")) != get_id() or int(virtual_storage.get("sequence_token", -1)) != _virtual_card_sequence_token:
		return
	_virtual_card_sequence_waiting = false
	defer_settlement({"kind":"sequential_virtual_card_continue", "sequence_token":_virtual_card_sequence_token})
