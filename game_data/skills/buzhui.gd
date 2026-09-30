extends SkillDefinition

## 【补缀】欢愉技源码。阿哈时刻按参演编号104驱动：指定至多三名角色各获得1点护盾，这些护盾在持有者的下一个回合结束时各失去1点。
## 到期使用持有者本人的结束阶段时机 phaseJieshu（role="player"，见 RuleTimingCatalog），不是轮末 roundEnd，也不是内容层自造事件：
## 演出时先记下当时的权威回合序号，只有当前回合序号严格大于登记值时才代表“你的下一个回合”已经走到末尾，
## 因此同一回合内的演出不会当回合到期，别人回合的结束阶段也不会让它提前到期。
## 翻面被跳过的回合在 phaseBefore 翻回正面后直接跳过整个回合、不进入准备至结束阶段，因此它不存在“回合结束”，不会让护盾到期；
## 这与【酩酊】用 phaseBegin 表达“下一个实际回合开始”是同一条统一规则：只有真正进入六阶段的回合才算一个回合。
## 持有者死亡或离场后，技能不再接收任何结束阶段时机（本技能因此不覆盖 can_trigger_while_owner_inactive），护盾按原文保留、不再到期。
## 补充：欢愉技一律强制发动，本技能不创建“是否发动”询问，目标选择窗口也不提供取消，选择0名目标即为合法结算。

## 阿哈时刻参演编号；与静态定义 performance_number 共用同一常量，避免两处数值分叉。
const PERFORMANCE_NUMBER: int = 104

## 可选角色数量下限；固定0，对应原文“至多三名角色”，即允许不指定任何角色。
const MIN_TARGET_COUNT: int = 0

## 可选角色数量上限；固定3，与技能原文“至多三名角色”一致。
const MAX_TARGET_COUNT: int = 3

## 每名被指定角色获得的护盾数；固定1点，与原文“各获得1点护盾”一致。
const SHIELD_GRANT_AMOUNT: int = 1

## 每名被指定角色在持有者下一个回合结束时失去的护盾数；固定1点，与原文“各失去1点护盾”一致。
const SHIELD_LOSS_AMOUNT: int = 1

## 目标选择请求种类；恢复时按该值分流到结算入口。
const TARGET_CHOICE_KIND: String = "buzhui_targets"

## 目标选择窗口是否允许取消；固定false，对应“强制发动、没有取消按钮”的口径。
## 该值为false时界面不会显示取消按钮，玩家只能通过“不选任何角色直接确定”表达0名目标，
## 因此 allow_cancel 不能复用为“可以少选”的语义。
const ALLOW_TARGET_CANCEL: bool = false

## AI：友方获得1点护盾的基础收益；低于【加护】的常驻护盾估值，因为护盾会在持有者下一个回合结束时消失。
const AI_FRIENDLY_SHIELD_VALUE: float = 1.6

## AI：目标每点已损失体力追加的优先级；用于“队友多时优先血量较少的友方”。
const AI_FRIENDLY_MISSING_HP_VALUE: float = 0.8

## AI：自己已满体力时相对残血队友的折扣；避免AI把临时护盾优先浪费在健康角色身上。
const AI_SELF_SHIELD_DISCOUNT: float = 0.85

## AI：敌方获得1点护盾的负收益；负值保证AI在只有敌方可选时主动提交0名目标。
const AI_HOSTILE_SHIELD_VALUE: float = -1.2

## 本次演出已实际登记到到期扣盾的角色ID；同一次演出内重复选择同一角色只登记一次。
var _recorded_target_ids: Array[int] = []

## 尚未到期的护盾记录；每项为 {"granted_turn_number":int, "target_ids":Array[int]}。
## granted_turn_number 是演出发生时的权威回合序号：持有者之后遇到的、序号更大的第一个回合尾才会整条消费，
## 因此同一次演出只扣一次，而同一回合内多次演出会各留一条记录、到期时逐条各扣1点护盾。
## 只保存基础值，便于网络快照与回放恢复。
var _shield_expiry_records: Array = []


## 写入欢愉技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"buzhui",
		"name":"补缀",
		"trigger":"passive",
		"joy_skill":true,
		"performance_number":PERFORMANCE_NUMBER,
		"description":"欢愉技，参演编号104，指定至多三名角色，这些角色各获得1点护盾。你的下一个回合结束时，这些角色各失去1点护盾。",
	})


## 订阅持有者本人的结束阶段时机；护盾到期属于已经发放的持续效果，只随持有者自己的回合推进。
## 不使用 global 订阅：护盾绑定“你的下一个回合”，其他角色的结束阶段不得让它提前到期。
## 必须用 phaseJieshu 而不是回合尾 phaseAfter：翻面被跳过的回合同样会经过控制器的统一回合尾入口（phaseAfter），
## 但它按统一规则跳过准备至结束阶段、不存在“回合结束”，不能成为护盾的到期点。
func install() -> void:
	subscribe_timing("phaseJieshu", _on_owner_end_phase, "player")


## 阿哈时刻的唯一执行入口：先选择0至3名角色，再统一发放护盾并登记到期扣盾记录。
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


## 结算补缀：向全部有效目标各发放1点护盾，并登记一条到期扣盾记录，最后回报演出结束。
func _execute_buzhui(selected_target_ids: Array[int]) -> void:
	# 本次演出实际获得护盾的角色；等待期间死亡、离场的目标由护盾端口拒绝，不写入到期记录。
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
		_register_shield_expiry_record(granted_target_ids)
	announce_activation({
		"target_ids":selected_target_ids.duplicate(),
		"shielded_target_ids":granted_target_ids.duplicate(),
		"shield_amount":SHIELD_GRANT_AMOUNT,
	})
	finish_joy_skill_performance()


## 登记一条到期扣盾记录；回合序号取当前权威回合序号，代表本记录发生在该回合的结束阶段之前。
func _register_shield_expiry_record(granted_target_ids: Array[int]) -> void:
	# 当前权威回合序号；补缀总在某个回合开始前的阿哈时刻（或轮末补触发的阿哈时刻）演出，
	# 因此该值通常是上一个已结束回合的序号：持有者自己的下一个回合开始时序号才会递增，其结束阶段即可消费本记录。
	# 若演出发生在持有者自己的回合进行中（由其他技能驱动的演出），该值就是本回合序号，本回合结束阶段按等号条件保留，留到下一个结束阶段。
	var current_turn_number: int = int(host.state.turn_number) if host != null and host.get("state") != null else 0
	_shield_expiry_records.append({
		"granted_turn_number":current_turn_number,
		"target_ids":granted_target_ids.duplicate(),
	})


## 持有者结束阶段清理：让登记在此前回合的护盾记录各失去1点护盾；死亡、离场或护盾为0的目标由权威端口自然跳过。
## 同一回合内留下的记录（登记序号不小于当前回合序号）属于“你的这个回合”，必须留到持有者的下一个回合结束阶段。
## 只订阅结束阶段：翻面被跳过的回合不进入六阶段，因此不会提前消费记录。
func _on_owner_end_phase(event: RuleEvent) -> void:
	if event == null:
		return
	# 当前回合序号；事件数据优先，异常缺失时回退当前权威回合序号，保证清理不会因为载荷缺失而整条丢失。
	var current_turn_number: int = int(event.data.get("turn_number", host.state.turn_number))
	# 尚未到期的记录；登记序号不小于当前回合序号的记录属于持有者尚未走完的回合，必须保留到那时再结算。
	var remaining_records: Array = []
	for record_variant: Variant in _shield_expiry_records:
		# 当前到期记录；结构异常时直接丢弃，避免污染后续回合。
		var record: Dictionary = record_variant as Dictionary
		if int(record.get("granted_turn_number", 0)) >= current_turn_number:
			remaining_records.append(record)
			continue
		for target_variant: Variant in record.get("target_ids", []) as Array:
			# 目标稳定玩家ID；护盾扣减端口负责拒绝已死亡、已离场或没有护盾的角色。
			get_skill_player(int(target_variant)).loseShield(SHIELD_LOSS_AMOUNT, get_owner_skill_player())
	_shield_expiry_records = remaining_records


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
