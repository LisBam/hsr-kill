class_name SequentialVirtualSkillDefinition
extends SkillDefinition

## 连续无材料虚拟用牌技能基类。组件按队列逐张提交标准CardUseEvent，上一张完整结束或取消后才开始下一张。

## 当前是否正在等待一张虚拟牌完成生命周期；true时禁止重复提交队首，卡牌结束时恢复false。
## 步骤序列持有整组内容，等待状态延续到最后一张完整after结束，期间拒绝重复发动。
var _virtual_card_sequence_waiting: bool = false


## 建立一组按顺序执行的无材料虚拟牌；已有队列未结束时拒绝覆盖，避免两个技能动作交叉消费同一完成事件。
func start_cardless_virtual_card_sequence(entries: Array[Dictionary], completion_context: Dictionary = {}) -> bool:
	if host == null or entries.is_empty() or _virtual_card_sequence_waiting:
		return false
	_virtual_card_sequence_waiting = true
	# 每张牌使用一个内容步骤；原生子树完整归档后，公共序列才运行下一张。
	var steps: Array[Callable] = []
	# 本次条目副本；只绑定稳定配置，不在技能实例上维护第二套待执行队列。
	for entry: Dictionary in entries:
		steps.append(_execute_virtual_sequence_card.bind(entry.duplicate(true)))
	steps.append(_complete_virtual_sequence)
	if run_steps(steps, {"completion_context":completion_context.duplicate(true)}) < 0:
		_virtual_card_sequence_waiting = false
		return false
	return true


## 连续虚拟牌全部完成后的扩展点；子类在此推进轮回、清理本次目标或继续自身效果。
func on_virtual_card_sequence_completed(_context: Dictionary) -> void:
	pass


## 提交当前虚拟牌；非法条目直接跳过，成功创建的原生子牌由当前步骤自动等待。
func _execute_virtual_sequence_card(sequence: RuleStepSequence, entry: Dictionary) -> void:
	if not can_use_effect() or not matches_character_generation(int(sequence.context.get("skill_character_generation", -1))):
		_virtual_card_sequence_waiting = false
		sequence.finish()
		return
	# 虚拟牌业务存储；来源身份用于牌效追踪，不再充当恢复队列的完成信号。
	var virtual_storage: Dictionary = (entry.get("virtual_storage", {}) as Dictionary).duplicate(true)
	virtual_storage["sequence_skill_owner_id"] = owner_player_id
	virtual_storage["sequence_skill_id"] = get_id()
	# 本张虚拟牌目标；条目必须只包含整数ID，异常值由统一卡牌规则拒绝。
	var target_ids: Array[int] = []
	# 当前目标身份；保持条目声明的顺序。
	for target_id_variant: Variant in entry.get("target_ids", []) as Array:
		target_ids.append(int(target_id_variant))
	host.execute_cardless_virtual_card_use(int(entry.get("actor_id", owner_player_id)), str(entry.get("definition_id", "")), target_ids, str(entry.get("log_message", "")), entry.get("rule_overrides", {}) as Dictionary, virtual_storage)


## 最后一张牌的材料回收与After子内容结束后只通知一次；出牌窗口由宿主统一空闲出口恢复。
func _complete_virtual_sequence(sequence: RuleStepSequence) -> void:
	_virtual_card_sequence_waiting = false
	if can_use_effect() and matches_character_generation(int(sequence.context.get("skill_character_generation", -1))):
		on_virtual_card_sequence_completed(sequence.context.get("completion_context", {}) as Dictionary)
