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
		_prepare_points,
		# 伤害发生前护盾值；只用于计算本次优先吸收量，不改变最终伤害事件本身的数值。
		_prepare_shield,
		_commit,
		_emit_result.bind("damageZero"),
		_emit_result.bind("changeHujiaAfter"),
		_emit_result.bind("changeHp"),
		# damage时机内的选择必须先完成全部同一时机处理器；不能提前发布damage_after、濒死或整条伤害尾部。
		_emit_result.bind("damage"),
		_start_committed_points,
		_finish_result,
	]
	_host.run_rule_sequence(steps, context)


## 展开整次伤害确认后的候选点；每点可独立阻止，整次伤害仍只扣血、统计和进入濒死一次。
func _prepare_points(sequence: RuleStepSequence) -> void:
	if not _read_window(sequence):
		return
	sequence.context["proposed_damage_amount"] = maxi(int(sequence.context.timing_data.get("amount", 0)), 0)
	sequence.context["accepted_damage_points"] = 0
	sequence.context["damage_point_index"] = 0
	_insert_next_point(sequence)


## 每次只展开一个候选点；长序列由统一帧预算让出执行权，不建立独立循环或恢复字典。
func _insert_next_point(sequence: RuleStepSequence) -> void:
	if not _validate_target(sequence):
		return
	if int(sequence.context.damage_point_index) >= int(sequence.context.proposed_damage_amount):
		sequence.context.timing_data["amount"] = int(sequence.context.accepted_damage_points)
		return
	sequence.context["damage_point_index"] = int(sequence.context.damage_point_index) + 1
	sequence.context["point_cancelled"] = false
	# 单点上下文；总量在整次Begin窗口修改，这里amount只允许0或1。
	var point_data: Dictionary = (sequence.context.timing_data as Dictionary).duplicate(true)
	point_data["amount"] = 1
	point_data["damage_point_index"] = int(sequence.context.damage_point_index)
	point_data["damage_total_amount"] = int(sequence.context.proposed_damage_amount)
	sequence.context["point_data"] = point_data
	# 当前点的修改窗口及接受步骤；读取最终窗口结果后才决定是否计入总伤害。
	var steps: Array[Callable] = [_emit_point_before.bind("damagePointBefore"), _emit_point_before.bind("damagePointBegin"), _accept_point, _insert_next_point]
	sequence.insert_steps(steps)


## 回读单点修改；取消仅阻止当前候选点，不取消整次伤害或其他点。
func _read_point_window(sequence: RuleStepSequence) -> void:
	if sequence.waiting_event == null:
		return
	# 原始单点窗口；所有处理器及其子内容完成后再读取取消和amount。
	var point_event: RuleEvent = sequence.waiting_event
	sequence.waiting_event = null
	sequence.context["point_data"] = point_event.data.duplicate(true)
	if point_event.cancelled or point_event.neutralized or int(point_event.data.get("amount", 1)) <= 0:
		sequence.context["point_cancelled"] = true


## 单点提交前窗口；每点Before完成后才进入Begin，取消的点不再发布Begin。
func _emit_point_before(sequence: RuleStepSequence, timing_name: String) -> void:
	_read_point_window(sequence)
	if not _validate_target(sequence) or bool(sequence.context.get("point_cancelled", false)):
		return
	sequence.context.point_data["amount"] = 1
	sequence.wait_for_timing(_emit(sequence, timing_name, sequence.context.point_data))


## 接受当前点但不直接扣血；避免多点伤害被拆成多次受伤、濒死或连环。
func _accept_point(sequence: RuleStepSequence) -> void:
	_read_point_window(sequence)
	if not bool(sequence.context.get("point_cancelled", false)):
		sequence.context["accepted_damage_points"] = int(sequence.context.accepted_damage_points) + 1


## 实际伤害成立后逐点通知；结果窗口中的取消不能撤销已经提交的体力和统计。
func _start_committed_points(sequence: RuleStepSequence) -> void:
	sequence.waiting_event = null
	sequence.context["committed_point_index"] = 0
	_emit_committed_point(sequence, "damagePoint", sequence.context.get("result", {}) as Dictionary)


## 发布一个已成立的伤害点，追加后继步骤保留等待边界；After沿用整次伤害收尾后的原语义。
func _emit_committed_point(sequence: RuleStepSequence, timing_name: String, timing_data: Dictionary) -> void:
	# 已通知数量；每次派发前递增，恢复不会重复当前点。
	var damage_point_index: int = int(sequence.context.get("committed_point_index", 0))
	# 最终伤害总点数；护盾吸收不减少每点伤害的通知次数。
	var damage_total_amount: int = maxi(int(timing_data.get("amount", 0)), 0)
	if damage_point_index >= damage_total_amount:
		return
	sequence.context["committed_point_index"] = damage_point_index + 1
	# 单点事实快照；保留整次护盾吸收与体力减少，amount固定为1。
	var damage_point_data: Dictionary = timing_data.duplicate(true)
	damage_point_data["amount"] = 1
	damage_point_data["damage_total_amount"] = damage_total_amount
	damage_point_data["damage_point_index"] = damage_point_index + 1
	# 下一点在本点全部技能完成后运行；即使这是最后一点，也保留读取完成边界。
	var steps: Array[Callable] = [_emit_committed_point.bind(timing_name, timing_data)]
	sequence.insert_steps(steps)
	sequence.wait_for_timing(_emit(sequence, timing_name, damage_point_data))


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
		_start_damage_tail(sequence, result)
	else:
		sequence.insert_steps([
			_emit_legacy_result.bind("damage_after"),
			_emit_legacy_result.bind("hp_reduced"),
			_resolve_result_dying,
			_start_damage_tail_from_result,
		])


## 统一装备上下文；读取最终属性而不泄露步骤对象。
func _equipment_context(sequence: RuleStepSequence) -> Dictionary:
	# 窗口共享数据；装备只读取标准伤害字段。
	var timing_data: Dictionary = sequence.context.get("timing_data", {}) as Dictionary
	return {"source_id":sequence.context.get("source_id", -1), "target_id":sequence.context.get("target_id", -1), "nature":timing_data.get("nature", "normal"), "card_id":timing_data.get("card_id", ""), "chain_transfer":timing_data.get("chain_transfer", false)}


## 用同一伤害父ID发布标准或兼容时机；不在组件内重新排序触发器。
func _emit(sequence: RuleStepSequence, timing_name: String, timing_data: Dictionary) -> RuleEvent:
	return _host.emit_sequence_timing(sequence, timing_name, int(sequence.context.get("target_id", -1)), int(sequence.context.get("source_id", -1)), int(sequence.context.get("target_id", -1)), timing_data, int(sequence.context.get("damage_event_id", -1)))


## 把已经提交的伤害结果并入原伤害序列，再插入固定尾部，避免另建恢复边界。
func _start_damage_tail_from_result(sequence: RuleStepSequence) -> void:
	_start_damage_tail(sequence, sequence.context.get("result", {}) as Dictionary)


## 初始化当前伤害序列的稳定尾部快照，并依序等待来源、结束、After、逐点After及连环子伤害。
func _start_damage_tail(sequence: RuleStepSequence, result: Dictionary) -> void:
	if result.is_empty():
		sequence.finish()
		return
	# 权威伤害结果；尾部数据只合并提交事实，不覆盖当前步骤游标或共享对象。
	for key_variant: Variant in result.keys():
		sequence.context[str(key_variant)] = result[key_variant]
	sequence.context["completion_data"] = _build_completion_data(result)
	sequence.context["committed_point_index"] = 0
	sequence.context["chain_target_index"] = 0
	sequence.insert_steps([
		_emit_completion.bind("damageSource"),
		_emit_completion.bind("damageEnd"),
		_emit_completion.bind("damageAfter"),
		_start_point_after,
		_continue_chain,
	])


## 尾部字段构建保持原有来源上下文契约；扩展数据不得覆盖权威伤害事实。
func _build_completion_data(context: Dictionary) -> Dictionary:
	# 统一尾部数据；来源触发与受伤者触发读取同一最终伤害、护甲吸收和体力减少值。
	var timing_data: Dictionary = {
		"amount":int(context.get("amount", 0)),
		"shield_absorbed":int(context.get("shield_absorbed", 0)),
		"hp_lost":int(context.get("hp_lost", 0)),
		"nature":str(context.get("nature", "normal")),
		"card_id":str(context.get("card_id", "")),
		"card_user_id":int(context.get("card_user_id", int(context.get("source_id", -1)))),
		"chain_transfer":bool(context.get("chain_transfer", false)),
		"damage_event_id":int(context.get("damage_event_id", -1)),
		"source_character_generation":int(context.get("source_character_generation", -1)),
		"target_character_generation":int(context.get("target_character_generation", -1)),
	}
	# 来源牌扩展上下文；只补充不存在的键，最终伤害数值与角色代次始终以权威尾部字段为准。
	var source_context: Dictionary = context.get("source_context", {}) as Dictionary
	for source_context_key_variant: Variant in source_context.keys():
		# 当前来源上下文字段名；【山倾】花色等纯数据可由 damageSource 技能读取。
		var source_context_key: String = str(source_context_key_variant)
		if not timing_data.has(source_context_key):
			timing_data[source_context_key] = source_context[source_context_key_variant]
	return timing_data


## 整次伤害事实窗口；已提交伤害不因目标死亡而丢失其来源、结束和After通知。
func _emit_completion(sequence: RuleStepSequence, timing_name: String) -> void:
	sequence.wait_for_timing(_emit(sequence, timing_name, sequence.context.completion_data))


## 每点After在整次伤害After之后展开，保留百折、命定等正式技能的订阅语义。
func _start_point_after(sequence: RuleStepSequence) -> void:
	_emit_committed_point(sequence, "damagePointAfter", sequence.context.completion_data)


## 连环目标快照按座次逐一处理；通用序列预登记父步骤，子伤害自动先于下一目标。
func _continue_chain(sequence: RuleStepSequence) -> void:
	# 连环目标快照；保持原伤害建立时的座次顺序，等待期间只重新校验存活与横置状态。
	var chain_targets: Array = sequence.context.get("chain_targets", []) as Array
	# 已完成连环目标数量；每次仅消费一个目标，预算和等待交给统一调度器。
	var chain_target_index: int = int(sequence.context.get("chain_target_index", 0))
	if chain_target_index >= chain_targets.size():
		return
	sequence.context["chain_target_index"] = chain_target_index + 1
	# 下一目标；先插入再执行子伤害，避免同步与异步路径使用不同循环。
	var steps: Array[Callable] = [_continue_chain]
	sequence.insert_steps(steps)
	# 传导前再次检查角色仍存活且横置，避免前序死亡结算改变有效目标。
	var chained_target_id: int = int(chain_targets[chain_target_index])
	# 当前连环目标状态；每轮重新按稳定 ID 读取，防止嵌套伤害后继续使用过期对象。
	var chained_target: PlayerState = _host.state.get_player(chained_target_id)
	if chained_target == null or not chained_target.alive or chained_target.out_of_game or not chained_target.chained:
		return
	# 连环伤害继续保留原来源牌扩展数据，使“此牌造成伤害后”类技能能识别同一张属性牌的传导伤害。
	var chained_source_context: Dictionary = (sequence.context.get("source_context", {}) as Dictionary).duplicate(true)
	chained_source_context["card_user_id"] = int(sequence.context.get("card_user_id", sequence.context.get("source_id", -1)))
	_host.damage(int(sequence.context.get("source_id", -1)), chained_target_id, int(sequence.context.get("amount", 0)), str(sequence.context.get("nature", "normal")), str(sequence.context.get("card_id", "")), true, false, chained_source_context)


## 兼容事件也遵循逐窗口等待；字段保留已提交事实，不读取后续改变的体力。
func _emit_legacy_result(sequence: RuleStepSequence, timing_name: String) -> void:
	# 伤害事实副本；hp_reduced仅报告穿透护盾的实际体力减少。
	var timing_data: Dictionary = (sequence.context.get("result", {}) as Dictionary).duplicate(true)
	if timing_name == "hp_reduced":
		if int(timing_data.get("hp_lost", 0)) <= 0:
			return
		timing_data["damage_amount"] = timing_data.get("amount", 0)
		timing_data["amount"] = timing_data.get("hp_lost", 0)
		timing_data["reduction_type"] = "damage"
		timing_data["event_id"] = timing_data.get("damage_event_id", -1)
	_emit(sequence, timing_name, timing_data)


## 只有原武将仍存活且体力不足才进入救援；新武将不继承旧伤害的濒死检查。
func _resolve_result_dying(sequence: RuleStepSequence) -> void:
	# 每步重取当前武将；死亡和换将只结束救援需求，不丢弃已经成立的伤害通知。
	var result: Dictionary = sequence.context.get("result", {}) as Dictionary
	var target: PlayerState = _host.state.get_player(int(result.get("target_id", sequence.context.get("target_id", -1))))
	if target != null and target.alive and target.hp <= 0 and target.character_generation == int(result.get("target_character_generation", -1)):
		_host._resolve_dying(target.player_id, int(result.get("source_id", sequence.context.get("source_id", -1))))
