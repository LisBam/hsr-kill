extends SkillDefinition

## 【补缀】欢愉技源码。阿哈时刻按参演编号104驱动：指定至多三名角色各获得1点护盾，这些护盾在本轮结束时各失去1点。
## 本轮结束使用真实标准时机 roundEnd（见 RuleTimingCatalog），不是“下一轮开始时”清理，也不是内容层自造事件。
## 补充：欢愉技一律强制发动，本技能不创建“是否发动”询问，目标选择窗口也不提供取消，选择0名目标即为合法结算。

## 阿哈时刻参演编号；与静态定义 performance_number 共用同一常量，避免两处数值分叉。
const PERFORMANCE_NUMBER: int = 104

## 可选角色数量下限；固定0，对应原文“至多三名角色”，即允许不指定任何角色。
const MIN_TARGET_COUNT: int = 0

## 可选角色数量上限；固定3，与技能原文“至多三名角色”一致。
const MAX_TARGET_COUNT: int = 3

## 每名被指定角色获得的护盾数；固定1点，与原文“各获得1点护盾”一致。
const SHIELD_GRANT_AMOUNT: int = 1

## 每名被指定角色在轮末失去的护盾数；固定1点，与原文“各失去1点护盾”一致。
const SHIELD_LOSS_AMOUNT: int = 1

## 目标选择请求种类；恢复时按该值分流到结算入口。
const TARGET_CHOICE_KIND: String = "buzhui_targets"

## 目标选择窗口是否允许取消；固定false，对应“强制发动、没有取消按钮”的口径。
## 该值为false时界面不会显示取消按钮，玩家只能通过“不选任何角色直接确定”表达0名目标，
## 因此 allow_cancel 不能复用为“可以少选”的语义。
const ALLOW_TARGET_CANCEL: bool = false

## AI：友方获得1点护盾的基础收益；低于【加护】的常驻护盾估值，因为本轮结束时护盾必然消失。
const AI_FRIENDLY_SHIELD_VALUE: float = 1.6

## AI：目标每点已损失体力追加的优先级；用于“队友多时优先血量较少的友方”。
const AI_FRIENDLY_MISSING_HP_VALUE: float = 0.8

## AI：自己已满体力时相对残血队友的折扣；避免AI把临时护盾优先浪费在健康角色身上。
const AI_SELF_SHIELD_DISCOUNT: float = 0.85

## AI：敌方获得1点护盾的负收益；负值保证AI在只有敌方可选时主动提交0名目标。
const AI_HOSTILE_SHIELD_VALUE: float = -1.2

## 本次演出已实际登记到轮末扣盾的角色ID；同一次演出内重复选择同一角色只登记一次。
var _recorded_target_ids: Array[int] = []

## 本轮各次演出的轮末扣盾记录；每项为 {"round_number":int, "target_ids":Array[int]}。
## 只保存基础值，便于网络快照与回放恢复；同轮多次演出会留下多条记录，轮末逐条各扣1点护盾。
var _round_end_shield_records: Array = []


## 写入欢愉技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"buzhui",
		"name":"补缀",
		"trigger":"passive",
		"joy_skill":true,
		"performance_number":PERFORMANCE_NUMBER,
		"description":"欢愉技，参演编号104，指定至多三名角色，这些角色各获得1点护盾。本轮结束时，这些角色各失去1点护盾。",
	})


## 订阅真实轮末时机；maintenance只跳过“非锁定技失效”检查，用于持续效果的到期清理。
func install() -> void:
	subscribe_timing("roundEnd", _on_round_end, "global", 0, false, false, Callable(), false, true)


## 护盾的轮末到期属于已经生效的持续效果清理，不因技能持有者中途阵亡而失效。
## 本技能只订阅 roundEnd，因此该覆盖不会让死亡持有者接收任何其他时机或产生新收益。
func can_trigger_while_owner_inactive(_event: RuleEvent) -> bool:
	return true


## 阿哈时刻的唯一执行入口：先选择0至3名角色，再统一发放护盾并登记轮末扣盾。
func perform_joy_skill(context: Dictionary) -> void:
	# 直接动作目标；由调试或回放入口显式给出时跳过选择窗口，正常演出路径不携带该字段。
	if context.has("target_ids"):
		var direct_target_ids: Array[int] = []
		for target_variant: Variant in context.get("target_ids", []) as Array:
			direct_target_ids.append(int(target_variant))
		_execute_buzhui(direct_target_ids)
		return
	# 可作为目标的全部角色；原文“至多三名角色”不排除任何一方，因此包含技能持有者自己。
	var candidate_target_ids: Array[int] = _get_candidate_target_ids()
	if candidate_target_ids.is_empty():
		# 没有可选角色时仍要完整结束演出，避免阿哈时刻队列卡在本技能。
		_execute_buzhui([])
		return
	request_target_selection("【补缀】请选择至多三名角色各获得1点护盾", candidate_target_ids, MIN_TARGET_COUNT, mini(MAX_TARGET_COUNT, candidate_target_ids.size()), ALLOW_TARGET_CANCEL, {"kind":TARGET_CHOICE_KIND})


## 恢复目标选择；窗口不可取消，因此正常路径必定收到已确认响应，未确认分支只兜底异常或回放输入。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return false
	# 已确认目标列表；异常输入按0名目标处理，对应本次演出不产生任何护盾。
	var selected_target_ids: Array[int] = []
	if response.confirmed:
		selected_target_ids = response.target_ids
	_execute_buzhui(selected_target_ids)
	return true


## 结算补缀：向全部有效目标各发放1点护盾，并按本轮登记一条轮末扣盾记录，最后回报演出结束。
func _execute_buzhui(selected_target_ids: Array[int]) -> void:
	# 本次演出实际获得护盾的角色；等待期间死亡、离场的目标由护盾端口拒绝，不写入轮末记录。
	var granted_target_ids: Array[int] = []
	# 本次演出的去重结果；同一次演出内重复点名同一角色只应发放并登记一次。
	_recorded_target_ids.clear()
	for target_id: int in selected_target_ids:
		if _recorded_target_ids.has(target_id) or granted_target_ids.size() >= MAX_TARGET_COUNT:
			continue
		_recorded_target_ids.append(target_id)
		# 实际增加护盾数；权威端口在目标无效时返回0，技能层不需要重复判断存活与离场。
		if get_skill_player(target_id).shield(SHIELD_GRANT_AMOUNT, get_owner_skill_player()) > 0:
			granted_target_ids.append(target_id)
	if not granted_target_ids.is_empty():
		_register_round_end_record(granted_target_ids)
	announce_activation({
		"target_ids":selected_target_ids.duplicate(),
		"shielded_target_ids":granted_target_ids.duplicate(),
		"shield_amount":SHIELD_GRANT_AMOUNT,
	})
	finish_joy_skill_performance()


## 登记一条轮末扣盾记录；轮数取当前权威轮数，轮末按“小于等于结束轮数”消费。
func _register_round_end_record(granted_target_ids: Array[int]) -> void:
	# 当前权威轮数；补缀总在回合开始前的阿哈时刻演出，因此该值就是本次护盾应当到期的轮数。
	var current_round_number: int = int(host.state.round_number) if host != null and host.get("state") != null else 0
	_round_end_shield_records.append({
		"round_number":current_round_number,
		"target_ids":granted_target_ids.duplicate(),
	})


## 轮末清理：让本轮全部被指定角色各失去1点护盾；死亡、离场或护盾为0的目标由权威端口自然跳过。
func _on_round_end(event: RuleEvent) -> void:
	if event == null:
		return
	# 结束轮数；事件数据优先，异常缺失时回退当前权威轮数，保证清理不会因为载荷缺失而整轮丢失。
	var ending_round_number: int = int(event.data.get("round_number", host.state.round_number))
	# 尚未消费的记录；轮数更大的记录属于后续轮次，必须保留到对应轮末再结算。
	var remaining_records: Array = []
	for record_variant: Variant in _round_end_shield_records:
		# 当前到期记录；结构异常时直接丢弃，避免污染后续轮次。
		var record: Dictionary = record_variant as Dictionary
		if int(record.get("round_number", 0)) > ending_round_number:
			remaining_records.append(record)
			continue
		for target_variant: Variant in record.get("target_ids", []) as Array:
			# 目标稳定玩家ID；护盾扣减端口负责拒绝已死亡、已离场或没有护盾的角色。
			get_skill_player(int(target_variant)).loseShield(SHIELD_LOSS_AMOUNT, get_owner_skill_player())
	_round_end_shield_records = remaining_records


## 返回当前全部可作为目标的角色ID；必须存活且未离场，“一名角色”包含技能持有者本人。
func _get_candidate_target_ids() -> Array[int]:
	# 目标结果；保持权威座次顺序，界面、AI与回放据此稳定复现。
	var target_ids: Array[int] = []
	if host == null or host.get("state") == null:
		return target_ids
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			target_ids.append(player.player_id)
	return target_ids


## 为AI评估补缀的目标组合；友方按护盾收益与残血程度加分，敌方按同等数值反向计入。
##
## 分数按“每名目标”累加，因此友方足够时AI会自然选满3名；
## 全体候选都是敌方时任何组合都为负分，提交0名目标的空选择即为最优，与“强制发动但可以少选”一致。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理补缀的目标选择。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TARGET_CHOICE_KIND:
		return 0.0
	# 动作负载；未确认等价于不指定任何角色。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；超出上限的动作由权威端拒绝，AI不应主动提交。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() > MAX_TARGET_COUNT:
		return -20.0
	# 本次动作总分；逐名目标累加，重复目标不会重复计分。
	var total_score: float = 0.0
	# 已计分目标；防止异常负载用重复ID虚增收益。
	var scored_target_ids: Array[int] = []
	for target_variant: Variant in selected_targets:
		# 当前目标ID；越界或无效角色无法读取态度，直接按无效动作拒绝。
		var target_id: int = int(target_variant)
		if scored_target_ids.has(target_id):
			continue
		scored_target_ids.append(target_id)
		# 当前目标快照；缺失时按无效动作拒绝，避免AI凭空获得护盾收益。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty():
			return -20.0
		# 目标已损失体力；数值越高越值得优先补盾，对应“队友多则指定血量较少的友方”。
		var missing_hp: int = maxi(int(target.get("max_hp", 0)) - int(target.get("hp", 0)), 0)
		# 敌我态度；正值友方、负值敌方、0表示身份未明。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		if attitude < 0.0:
			total_score += AI_HOSTILE_SHIELD_VALUE
			continue
		if target_id == owner_player_id:
			total_score += AI_FRIENDLY_SHIELD_VALUE * AI_SELF_SHIELD_DISCOUNT + float(missing_hp) * AI_FRIENDLY_MISSING_HP_VALUE
			continue
		if attitude > 0.0:
			total_score += AI_FRIENDLY_SHIELD_VALUE + float(missing_hp) * AI_FRIENDLY_MISSING_HP_VALUE
	return total_score
