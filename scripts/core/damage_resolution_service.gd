class_name DamageResolutionService
extends RefCounted

## 伤害步骤编排组件；窗口、装备修正、护盾和扣血各自只有一个执行点，实际状态写入仍委托权威控制器。

## 权威规则宿主；只在本局运行期引用，不写入序列上下文、回放或网络数据。
var _host: Object


## 注入既有规则接口；组件不自行创建玩家、选择适配器或第二套调度器。
func _init(host: Object) -> void:
	_host = host


## 窗口顺序沿用既有规则；各窗口的data由_read_window统一回读，不再使用多个同步局部快照。
## 以统一步骤协议展开伤害；所有窗口完成后才读取其最终修改值。
func resolve(context: Dictionary) -> void:
	# 固定步骤；每个窗口与状态写入分开，恢复时无需重复dispatch、装备效果或消费实体。
	var steps: Array[Callable] = [
		_emit_window.bind("damageBefore"),
		_emit_window.bind("damageBegin"),
		_emit_window.bind("damageBegin1"),
		_modify_weapon,
		# 第二伤害修改窗口；发生在来源装备修正后、目标防具修正前。
		# 第二伤害窗口数据；保留第一窗口与来源牌上下文，只用装备修正后的最终值覆盖amount。
		_emit_window.bind("damageBegin2"),
		# 第三伤害修改窗口；通常供受伤角色和防御技能在防具结算前修改。
		# 第三伤害窗口数据；沿用第二窗口全部扩展字段并更新上一窗口确认后的amount。
		_emit_window.bind("damageBegin3"),
		_modify_armor,
		# 第四及最终伤害修改窗口；其结果直接进入旧 damage_before 兼容事件和实际扣减。
		# 第四伤害窗口数据；保留制动等第三窗口写入的数据，并用防具修正后的amount进入最终修改阶段。
		_emit_window.bind("damageBegin4"),
		# 伤害前事件；处理器可修改 amount 或取消整次伤害。
		_emit_window.bind("damage_before"),
		# 伤害发生前护盾值；只用于计算本次优先吸收量，不改变最终伤害事件本身的数值。
		_prepare_shield,
		_commit,
		_emit_result.bind("damageZero"),
		_emit_result.bind("changeHujiaAfter"),
		_emit_result.bind("changeHp"),
		# damage时机内的选择必须先完成全部同一时机处理器；不能提前发布damage_after、濒死或整条伤害尾部。
		_emit_result.bind("damage"),
		_finish_result,
	]
	_host.run_rule_sequence(steps, context)


## 回读上一修改窗口；取消和目标代次失效在下一步骤入口统一收口。
func _read_window(sequence: RuleStepSequence) -> bool:
	if sequence.waiting_event != null:
		# 原窗口对象；异步处理器可能修改amount、nature或取消，不能使用派发时副本。
		var previous_event: RuleEvent = sequence.waiting_event
		sequence.waiting_event = null
		sequence.context["timing_data"] = previous_event.data.duplicate(true)
		if previous_event.cancelled or previous_event.neutralized:
			_cancel(sequence, previous_event.termination_reason)
			return false
	return _validate_target(sequence)


## 每次副作用前按稳定ID与武将代次重取目标；旧武将伤害不能落到同座位新武将身上。
func _validate_target(sequence: RuleStepSequence) -> bool:
	if _host.state == null or _host.state.game_over:
		sequence.finish()
		return false
	# 当前目标；等待期间允许被回复，但死亡、离场或换将后原伤害终止。
	var target: PlayerState = _host.state.get_player(int(sequence.context.get("target_id", -1)))
	if target == null or not target.alive or target.out_of_game or target.character_generation != int(sequence.context.get("target_character_generation", -1)):
		_cancel(sequence, "damage_target_changed")
		return false
	return true


## 统一取消出口；取消事实可触发自己的后续选择，原伤害不再扣血。
func _cancel(sequence: RuleStepSequence, reason: String) -> void:
	# 取消时机数据；保留来源牌信息并追加可诊断原因。
	var timing_data: Dictionary = (sequence.context.get("timing_data", {}) as Dictionary).duplicate(true)
	timing_data["reason"] = reason
	sequence.wait_for_timing(_emit(sequence, "damageCancelled", timing_data))
	sequence.finish()


## 发布单个伤害修改窗口；派发后立即返回，由统一管线等待同一窗口全部技能。
func _emit_window(sequence: RuleStepSequence, timing_name: String) -> void:
	if not _read_window(sequence):
		return
	# 共享窗口数据；amount在窗口边界钳制非负，其他扩展字段贯穿全部步骤。
	var timing_data: Dictionary = sequence.context.get("timing_data", {}) as Dictionary
	timing_data["amount"] = maxi(int(timing_data.get("amount", 0)), 0)
	sequence.wait_for_timing(_emit(sequence, timing_name, timing_data))


## 来源武器在Begin1与Begin2之间修改伤害；不重复触发或预先读取尚未完成窗口。
func _modify_weapon(sequence: RuleStepSequence) -> void:
	if not _read_window(sequence):
		return
	# 伤害来源状态；其武器可覆盖造成伤害修正钩子。
	var equipment_damage_source: PlayerState = _host.state.get_player(int(sequence.context.get("source_id", -1)))
	if equipment_damage_source == null or equipment_damage_source.character_generation != int(sequence.context.get("source_character_generation", -1)):
		return
	# 来源武器定义；不存在武器或定义缺失时不修改伤害。
	var source_weapon_definition: CardDefinition = _host.get_equipment_definition(equipment_damage_source.player_id, "weapon")
	if source_weapon_definition == null:
		return
	# 受伤目标状态；死亡或无效目标不重复结算。
	var target: PlayerState = _host.state.get_player(int(sequence.context.get("target_id", -1)))
	# 伤害修正上下文；装备源码只读取稳定规则字段，不依赖控制器内部局部变量。
	var equipment_damage_context: Dictionary = _equipment_context(sequence)
	# 最终伤害值；来源装备修正在本步骤仅执行一次。
	var final_amount: int = maxi(int(sequence.context.timing_data.get("amount", 0)), 0)
	sequence.context.timing_data["amount"] = source_weapon_definition.modify_outgoing_damage(_host, equipment_damage_source, target, equipment_damage_context, final_amount)


## 目标防具在Begin3与Begin4之间修改伤害；无视防具由原伤害上下文决定。
func _modify_armor(sequence: RuleStepSequence) -> void:
	if not _read_window(sequence) or bool(sequence.context.get("ignore_armor", false)):
		return
	# 当前目标；每个步骤重取状态，避免选择期间保留旧角色引用。
	var target: PlayerState = _host.state.get_player(int(sequence.context.get("target_id", -1)))
	# 目标防具定义；具体伤害压缩或属性增伤由防具卡牌源码提供。
	var target_armor_definition: CardDefinition = _host.get_equipment_definition(target.player_id, "armor")
	if target_armor_definition == null:
		return
	# 防具修正前的伤害；仅数值确实变化时才表现为本次防具生效，避免普通伤害重复提示。
	var amount_before_armor: int = maxi(int(sequence.context.timing_data.get("amount", 0)), 0)
	# 装备规则字段；由共享窗口读出最终属性，避免异步属性修改丢失。
	var equipment_damage_context: Dictionary = _equipment_context(sequence)
	# 防具修正结果；写回下一窗口共享amount。
	var final_amount: int = target_armor_definition.modify_incoming_damage(_host, target, equipment_damage_context, amount_before_armor)
	sequence.context.timing_data["amount"] = final_amount
	if final_amount != amount_before_armor:
		_host.record_equipment_activation(target.player_id, target_armor_definition.get_id())


## 将已完成修改窗口的伤害转换为待扣护盾；护盾窗口同样允许选择并暂停。
func _prepare_shield(sequence: RuleStepSequence) -> void:
	if not _read_window(sequence):
		return
	# 当前目标；护盾值以窗口开始时状态为准，提交时再次限制到当时可用护盾。
	var target: PlayerState = _host.state.get_player(int(sequence.context.get("target_id", -1)))
	# 最终伤害值；兼容damage_before完成后才确定。
	var final_amount: int = maxi(int(sequence.context.timing_data.get("amount", 0)), 0)
	sequence.context["amount"] = final_amount
	sequence.context["nature"] = str(sequence.context.timing_data.get("nature", "normal"))
	# 伤害结算前护盾值；负值在权威边界按0处理。
	var shield_before_damage: int = maxi(target.shield, 0)
	# 本次由护盾吸收的伤害值；最多吸收到最终伤害值，护盾不会变成负数。
	var shield_absorbed: int = mini(shield_before_damage, final_amount)
	sequence.context["shield_absorbed"] = shield_absorbed
	if shield_absorbed > 0:
		# 护甲减少前时机；amount 表示本次将扣除的护甲值，取消后伤害全部穿透到体力。
		var hujia_before_event: RuleEvent = _emit(sequence, "changeHujiaBefore", {"amount":shield_absorbed, "old_hujia":shield_before_damage, "reason":"damage", "damage_event_id":int(sequence.context.get("damage_event_id", -1)), "change_type":"lose"})
		sequence.wait_for_timing(hujia_before_event)


## 原子提交护盾、体力和统计；提交前读取护盾窗口结果，所有结果时机留到后续步骤。
func _commit(sequence: RuleStepSequence) -> void:
	if not _validate_target(sequence):
		return
	# 护盾修改窗口；取消护盾扣减只令伤害穿透，不取消整次伤害。
	var hujia_before_event: RuleEvent = sequence.waiting_event
	sequence.waiting_event = null
	if hujia_before_event != null:
		sequence.context["shield_absorbed"] = 0 if hujia_before_event.cancelled or hujia_before_event.neutralized else maxi(int(hujia_before_event.data.get("amount", 0)), 0)
	sequence.context["result"] = _host.call("_commit_prepared_damage", sequence.context)


## 提交后逐个发布结果窗口；护盾耗尽、体力变化和damage之间都允许插入独立子选择。
func _emit_result(sequence: RuleStepSequence, timing_name: String) -> void:
	# 已经提交的伤害事实；后续时机不能重新扣血或重新统计。
	var result: Dictionary = sequence.context.get("result", {}) as Dictionary
	if result.is_empty():
		sequence.finish()
		return
	# 当前结果时机参数；始终从提交快照派生，保留牌与来源信息。
	var timing_data: Dictionary = result.duplicate(true)
	if timing_name == "damageZero":
		if int(result.get("amount", 0)) != 0:
			return
	elif int(result.get("amount", 0)) == 0:
		return
	elif timing_name == "changeHujiaAfter":
		if int(result.get("shield_absorbed", 0)) <= 0:
			return
		timing_data["amount"] = int(result.get("shield_absorbed", 0))
		timing_data["hujia"] = int(result.get("shield", 0))
		timing_data["reason"] = "damage"
		timing_data["change_type"] = "lose"
	elif timing_name == "changeHp":
		if int(result.get("hp_lost", 0)) <= 0:
			return
		timing_data["amount"] = int(result.get("hp_lost", 0))
		timing_data["reason"] = str(result.get("card_id", ""))
		timing_data["change_type"] = "damage"
	sequence.wait_for_timing(_emit(sequence, timing_name, timing_data))


## 结果窗口完成后进入既有濒死与伤害尾部；父序列预登记位置会等待其全部子续接。
func _finish_result(sequence: RuleStepSequence) -> void:
	# 已提交结果；包含连环目标快照、武将代次和牌使用者等稳定字段。
	var result: Dictionary = sequence.context.get("result", {}) as Dictionary
	if int(result.get("amount", 0)) == 0:
		_host.call("_finish_damage_timing", result)
	else:
		_host.call("_continue_damage_after_result", result)


## 统一装备上下文；读取最终属性而不泄露步骤对象。
func _equipment_context(sequence: RuleStepSequence) -> Dictionary:
	# 窗口共享数据；装备只读取标准伤害字段。
	var timing_data: Dictionary = sequence.context.get("timing_data", {}) as Dictionary
	return {"source_id":sequence.context.get("source_id", -1), "target_id":sequence.context.get("target_id", -1), "nature":timing_data.get("nature", "normal"), "card_id":timing_data.get("card_id", ""), "chain_transfer":timing_data.get("chain_transfer", false)}


## 用同一伤害父ID发布标准或兼容时机；不在组件内重新排序触发器。
func _emit(sequence: RuleStepSequence, timing_name: String, timing_data: Dictionary) -> RuleEvent:
	return _host.emit_rule_timing(timing_name, int(sequence.context.get("target_id", -1)), int(sequence.context.get("source_id", -1)), int(sequence.context.get("target_id", -1)), timing_data, int(sequence.context.get("damage_event_id", -1)))
