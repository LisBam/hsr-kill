extends RefCounted

## 角色标量状态变化的独立内容；原子提交与可插入通知分步，结果不借用全局恢复表。

## 当前权威宿主；仅在本局结果与步骤中持有，不进入网络或存档。
var _host: Object

## 本次真实规则内容身份；默认-1表示尚无内容，完成状态直接查询宿主内容寿命。
var _sequence_id: int = -1

## 已提交的实际带符号变化；失去体力为正数，护甲/上限减少为负数，布尔状态成功变化为1。
var amount: int = 0

## 是否发生了真实状态变化；前置取消、换将或幂等请求为false，不等同于completed。
var success: bool = false

## 提交事实快照；后置可以产生更多状态变化，但不能覆盖本次结果。
var result: Dictionary = {}

## 本次内容及全部子内容是否已结束；直接依真实内容身份判断，终局或撤销也能明确结束。
var completed: bool:
	get:
		return _sequence_id < 0 or not _host.is_rule_sequence_pending(_sequence_id)

## 完整完成后的实际变化绝对值；费用可用count，不把减少护甲的负号当成失败。
var count: int:
	get:
		return absi(amount) if completed and success else 0


func _init(host: Object) -> void:
	_host = host


## kind为lose_hp、hujia、max_hp、link或turn_over；options只保存稳定规则配置。
func begin(kind: String, source_id: int, target_id: int, requested_amount: int, reason: String, options: Dictionary = {}) -> void:
	# 原目标；等待后必须仍为这一武将代次。
	var target: PlayerState = _host.state.get_player(target_id) if _host.state != null else null
	if target == null or _host.state.game_over or not target.alive or (target.out_of_game and not bool(options.get("allow_out_of_game", false))):
		return
	if kind in ["lose_hp", "hujia", "max_hp"] and requested_amount == 0:
		return
	if kind == "lose_hp" and requested_amount < 0:
		return
	if kind == "link" and target.chained == bool(options.get("linked", false)):
		return
	# 窗口数据；各时机amount始终为正数，最终结果保留请求方向。
	var data: Dictionary = {"amount":absi(requested_amount), "reason":reason, "hp":target.hp, "max_hp":target.max_hp, "old_hujia":target.shield, "change_type":"gain" if requested_amount > 0 else "lose", "old_linked":target.chained, "linked":bool(options.get("linked", false)), "old_face_down":target.face_down, "face_down":not target.face_down}
	# 稳定身份和数据；不保存目标对象，事实提交后不再读取After作为前置修改。
	var context: Dictionary = {"sequence_kind":"player_state_change", "kind":kind, "source_id":source_id, "target_id":target_id, "generation":target.character_generation, "requested_amount":requested_amount, "reason":reason, "options":options.duplicate(true), "data":data, "cancelled":false, "hp_reduction":0, "event_id":_host._current_rule_parent_event_id()}
	# 每个窗口独占一步；旧兼容通知也拥有完整子内容等待边界。
	var steps: Array[Callable] = []
	match kind:
		"lose_hp":
			steps = [_before.bind("loseHpBefore"), _before.bind("lose_hp_before"), _before.bind("loseHpBegin"), _commit, _notify.bind("lose_hp_after"), _notify.bind("changeHp"), _notify.bind("loseHpEnd"), _notify.bind("loseHpAfter"), _notify.bind("hp_reduced"), _dying]
		"hujia":
			if requested_amount < 0 and target.shield <= 0:
				return
			if requested_amount < 0:
				data["amount"] = mini(absi(requested_amount), target.shield)
			steps = [_before.bind("changeHujiaBefore"), _commit, _notify.bind("shield_after"), _notify.bind("changeHujiaAfter")]
		"max_hp":
			# 上限方向对应独立生命周期，减少时至少保留1点上限。
			var base_name: String = "gainMaxHp" if requested_amount > 0 else "loseMaxHp"
			steps = [_before.bind(base_name + "Before"), _before.bind(base_name + "Begin"), _commit, _notify.bind(base_name + "End"), _notify.bind(base_name + "After"), _notify.bind("changeHp"), _dying]
		"link":
			steps = [_before.bind("linkBefore"), _before.bind("linkBegin"), _commit, _notify.bind("linkEnd"), _notify.bind("linkAfter")]
		"turn_over":
			steps = [_before.bind("turnOverBefore"), _commit, _notify.bind("turnOverEnd"), _notify.bind("turnOverAfter")]
		_:
			return
	steps.append(_complete)
	_sequence_id = _host.run_rule_sequence(steps, context)


## 回读完整前置并核对原角色；不提前finish，明确失败也由内容自然结束。
func _valid_target(sequence: RuleStepSequence) -> PlayerState:
	if sequence.waiting_event != null:
		sequence.context.data = sequence.waiting_event.data.duplicate(true)
		sequence.context.cancelled = bool(sequence.context.cancelled) or sequence.waiting_event.cancelled or sequence.waiting_event.neutralized
		sequence.waiting_event = null
	# 当前目标；来源可以已死亡，但不能把旧请求提交到新武将。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id)) if _host.state != null else null
	if bool(sequence.context.cancelled) or target == null or not target.alive or target.character_generation != int(sequence.context.generation) or (target.out_of_game and not bool(sequence.context.options.get("allow_out_of_game", false))):
		return null
	return target


## 发布前置后立即返回；下一步骤才读取最终修改与取消状态。
func _before(sequence: RuleStepSequence, timing_name: String) -> void:
	if _valid_target(sequence) != null:
		_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.target_id), int(sequence.context.source_id), int(sequence.context.target_id), sequence.context.data, int(sequence.context.event_id))


## 唯一状态写入步骤；每个具体规则保留自己的数值、日志与历史语义。
func _commit(sequence: RuleStepSequence) -> void:
	# 最后前置原事件；锁定规则在最终窗口数据确定后可补写明确取消原因。
	var before_event: RuleEvent = sequence.waiting_event
	# 等待后的真实目标；跨步骤不保留实体引用。
	var target: PlayerState = _valid_target(sequence)
	if target == null:
		return
	match str(sequence.context.kind):
		"lose_hp":
			_commit_hp_loss(sequence, target)
		"hujia":
			_commit_hujia(sequence, target)
		"max_hp":
			_commit_max_hp(sequence, target)
		"link":
			_commit_link(sequence, target)
		"turn_over":
			_commit_turn_over(sequence, target, before_event)
	if success:
		result = (sequence.context.data as Dictionary).duplicate(true)
		result["success"] = true
		result["delta"] = amount


## 失去体力绕过护盾、伤害修正与伤害历史；来源不作为濒死击杀者。
# 失去体力目标状态；死亡角色与非正数请求不会重复修改公开体力。
# 无名杀式失去体力前时机；与旧 lose_hp_before 并行保留，标准技能应优先订阅驼峰事件名。
# 失去体力前事件；只允许失去体力类技能修改或取消，不会触发 damage_before。
# 失去体力效果音；final_amount已经过两次非正数校验，此处必定大于0，无需重复判空。
# 失去体力后事件；与 damage_after 完全独立，受到伤害和造成伤害技能不会收到本事件。
# 标准失去体力结束与完成时机；二者都发生在实际扣减后、进入濒死前。
# 通用体力减少事件；失去体力与实际扣减体力的伤害都通过本事件提供统一观察入口。
# 失去体力不属于伤害，来源角色不会被登记为击杀者，也不会获得伤害击杀奖惩。
func _commit_hp_loss(sequence: RuleStepSequence, target: PlayerState) -> void:
	# 最终失去体力值；事件处理器可把数值调整为0以阻止本次体力减少。
	var final_amount: int = maxi(int(sequence.context.data.get("amount", 0)), 0)
	if final_amount <= 0:
		return
	target.hp -= final_amount
	amount = final_amount
	success = true
	sequence.context.hp_reduction = final_amount
	_host.request_effect_voice(target.player_id, MatchController.EFFECT_LOSE_HP)
	# 失去体力父事件；与伤害事件使用不同类型，回放和技能触发不会混淆两种体力减少来源。
	var lose_hp_event_id: int = _host._record_runtime_event("LoseHpEvent", "lose_hp", {"source_id":int(sequence.context.source_id), "target_id":target.player_id, "requested_amount":int(sequence.context.requested_amount), "reason":str(sequence.context.reason)}, {"amount":final_amount, "hp":target.hp}, int(sequence.context.event_id))
	sequence.context.event_id = lose_hp_event_id
	sequence.context.data = {"amount":final_amount, "hp":target.hp, "shield":target.shield, "reason":str(sequence.context.reason), "event_id":lose_hp_event_id, "change_type":"lose_hp", "reduction_type":"lose_hp"}
	_host.add_log("%s失去%d点体力（%d/%d，护盾%d）。" % [_host.format_player_state_log_name(target), final_amount, target.hp, target.max_hp, target.shield])


## 护甲独立于体力；增加无上限，减少钳制为当前非负护甲值。
# 护盾目标状态；死亡角色不能获得护盾，避免无效公开状态继续累积。
# 护甲变化前时机；当前项目护盾值承载无名杀 hùjia 语义，触发器可修改本次增加量或取消。
# 实际增加的护盾值；当前规则没有护盾上限，因此等于经过非正数校验后的请求值。
# 获得护盾后事件；技能可以读取来源、目标、实际增加量、当前护盾与效果原因。
# 护甲目标状态；死亡角色不再接受普通规则调整。
# 请求扣减量；对外 delta 为负数，时机中的 amount 始终使用正数便于技能修改。
# 实际扣减量；触发器可减少但不能令护甲变为负数。
func _commit_hujia(sequence: RuleStepSequence, target: PlayerState) -> void:
	# 前置修改后的变化幅度；最终结果再恢复请求方向。
	var gained_amount: int = maxi(int(sequence.context.data.get("amount", 0)), 0)
	if int(sequence.context.requested_amount) < 0:
		gained_amount = mini(gained_amount, maxi(target.shield, 0))
	if gained_amount <= 0:
		return
	amount = gained_amount if int(sequence.context.requested_amount) > 0 else -gained_amount
	target.shield = maxi(target.shield, 0) + amount
	success = true
	sequence.context.data = {"amount":gained_amount, "hujia":target.shield, "shield":target.shield, "reason":str(sequence.context.reason), "change_type":"gain" if amount > 0 else "lose"}
	if amount > 0:
		# 护盾事件记录；保存来源、技能或卡牌原因、实际增加量和结算后的总护盾值。
		var shield_event_id: int = _host._record_runtime_event("ShieldEvent", "shield", {"source_id":int(sequence.context.source_id), "target_id":target.player_id, "requested_amount":int(sequence.context.requested_amount), "reason":str(sequence.context.reason)}, {"amount":amount, "shield":target.shield}, int(sequence.context.event_id))
		sequence.context.event_id = shield_event_id
		sequence.context.data["event_id"] = shield_event_id
		_host.add_log("%s获得%d点护盾（护盾%d）。" % [_host.format_player_state_log_name(target), amount, target.shield])


## 上限改变在同一原子步骤压低当前体力；changeHp与潜在濒死分别等待，不能提前回复。
# 体力上限目标；死亡角色不通过普通内容端口改变上限。
# 生命周期基础名称；增加和减少分别使用独立的四段时机。
# 请求变化量；事件内使用正数，最终返回值再恢复正负号。
func _commit_max_hp(sequence: RuleStepSequence, target: PlayerState) -> void:
	# 最终变化量；减少体力上限时至少保留1点上限。
	var actual_amount: int = maxi(int(sequence.context.data.get("amount", 0)), 0)
	if int(sequence.context.requested_amount) < 0:
		actual_amount = mini(actual_amount, maxi(target.max_hp - 1, 0))
	if actual_amount <= 0:
		return
	# 变化前体力；减少上限可能同步压低当前体力并产生 changeHp。
	var previous_hp: int = target.hp
	amount = actual_amount if int(sequence.context.requested_amount) > 0 else -actual_amount
	target.max_hp += amount
	target.hp = mini(target.hp, target.max_hp)
	success = true
	sequence.context.hp_reduction = previous_hp - target.hp
	sequence.context.data = {"amount":actual_amount, "hp":target.hp, "max_hp":target.max_hp, "reason":str(sequence.context.reason)}


## 连环按前置最终linked写入；嵌套操作已使状态满足请求时保持幂等。
# 连环目标状态；死亡角色和无需变化的请求不会重复触发。
func _commit_link(sequence: RuleStepSequence, target: PlayerState) -> void:
	# 最终连环状态；允许前置修改，实际旧状态在提交时采样。
	var linked: bool = bool(sequence.context.data.get("linked", false))
	if target.chained == linked:
		return
	sequence.context.data = {"old_linked":target.chained, "linked":linked, "reason":str(sequence.context.reason)}
	target.chained = linked
	amount = 1
	success = true
	# 连环效果音；被横置与解除连环使用两套不同音效，与无名杀的连环音效语义一致。
	_host.request_effect_voice(target.player_id, MatchController.EFFECT_LINK if linked else MatchController.EFFECT_LINK_CLEAR)


## 翻面尊重前置最终朝向与背面锁定；不能检查修改值后却仍按原反向写入。
# 翻面目标状态；死亡角色不再改变公开武将牌方向。
func _commit_turn_over(sequence: RuleStepSequence, target: PlayerState, before_event: RuleEvent) -> void:
	# 本次翻面的最终目标状态；事件处理器可改写 face_down，因此以事件数据而非入参为准。
	var intended_face_down: bool = bool(sequence.context.data.get("face_down", not target.face_down))
	if target.face_down == intended_face_down:
		return
	# 「武将牌始终背面向上」锁定规则：本次要翻至正面时如实取消本次翻面。
	# 不修改状态、不派发 turnOverEnd/turnOverAfter，使所有观察者看到“这次翻面没有发生”；
	# 反向（正面→背面）不受锁定影响，锁定技角色仍可被正常翻至背面。
	if not intended_face_down and _host.is_face_down_locked(target.player_id):
		if before_event != null:
			before_event.cancel("face_down_lock")
		result = {"success":false, "reason":"face_down_lock"}
		_host.add_log("%s的武将牌因锁定技无法翻至正面。" % _host.format_player_state_log_name(target))
		return
	sequence.context.data = {"old_face_down":target.face_down, "face_down":intended_face_down, "reason":str(sequence.context.reason)}
	target.face_down = intended_face_down
	amount = 1
	success = true


## 已提交结果逐窗口等待；后置取消不能撤销事实，也不覆盖下一窗口的提交快照。
func _notify(sequence: RuleStepSequence, timing_name: String) -> void:
	if not success or (timing_name == "shield_after" and amount < 0):
		return
	if timing_name == "changeHp" and str(sequence.context.kind) == "max_hp" and int(sequence.context.hp_reduction) <= 0:
		return
	# 当前窗口的独立事实数据；上限压低体力使用实际压低量，其他窗口使用本次状态变化量。
	var data: Dictionary = (sequence.context.data as Dictionary).duplicate(true)
	if timing_name == "changeHp" and str(sequence.context.kind) == "max_hp":
		data["amount"] = int(sequence.context.hp_reduction)
		data["change_type"] = "max_hp_clamp"
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.target_id), int(sequence.context.source_id), int(sequence.context.target_id), data, int(sequence.context.event_id))


## 后置子回复或换将完成后再判断濒死；不把原请求延续到新武将。
func _dying(sequence: RuleStepSequence) -> void:
	if not success or not bool(sequence.context.options.get("resolve_dying", true)):
		return
	# 当前原代次目标；后置回复可使原濒死条件不再成立。
	var target: PlayerState = _host.state.get_player(int(sequence.context.target_id))
	if target != null and target.alive and target.character_generation == int(sequence.context.generation) and target.hp <= 0:
		_host._resolve_dying(target.player_id, -1)


## 保留明确的最后步骤；宿主只在全部子内容结束后释放本内容身份。
func _complete(_sequence: RuleStepSequence) -> void:
	pass
