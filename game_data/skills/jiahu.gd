extends SkillDefinition

## 【加护】技能源码。准备阶段可横置一名竖置且没有护盾的角色，并为其提供1点护盾。

## 单次成功发动提供的护盾数；默认1点，修改后必须同步技能原文与玩法数值文档。
const SHIELD_AMOUNT: int = 1

## AI将获得1点护盾估算为的基础防御收益；只影响目标选择，不修改实际护盾。
const AI_SHIELD_VALUE: float = 2.5

## AI将一名角色从竖置切换为横置的状态代价；数值越高越保守。
const AI_LINK_COST: float = 1.0


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "jiahu",
		"name": "加护",
		"trigger": "phaseZhunbeiBegin",
		"ui_enabled": false,
		"description": "准备阶段，你可以横置一名武将牌竖置且没有护盾的角色，并令其获得1点护盾。",
	})


## 订阅技能持有者的准备阶段Begin时机；可选技不在没有合法目标时创建空询问。
func install() -> void:
	subscribe_timing("phaseZhunbeiBegin", _on_preparation_phase_begin, "player")


## 在准备阶段请求一名竖置且无护盾的存活角色；取消表示本次不发动。
func _on_preparation_phase_begin(_event: RuleEvent) -> void:
	# 当前合法目标；包含技能持有者自己，只依据“一名角色”的原文限制。
	var target_ids: Array[int] = _get_eligible_target_ids()
	if target_ids.is_empty():
		return
	run_steps([_choose_jiahu_target, _link_jiahu_target, _grant_jiahu_shield], {"target_ids":target_ids})


## 恢复加护目标选择；等待期间目标状态改变时直接跳过已不可执行的效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "jiahu_target" or response == null:
		return false
	# 兼容旧选择入口；两条入口共享内容步骤，不重复维护横置与护盾的结算分支。
	run_steps([Callable(self, "_link_jiahu_target").bind(response), _grant_jiahu_shield])
	return true


## 第一步只创建目标请求；AI和真人都通过相同请求结果进入下一步。
func _choose_jiahu_target(sequence: RuleStepSequence) -> void:
	request_step_targets(sequence, "【加护】请选择一名武将牌竖置且没有护盾的角色", _get_eligible_target_ids(), 0, 1, true, {"kind":"jiahu_target"})


## 第二步验证选择并横置目标；link时机产生的子选择必须完成后才进入护盾步骤。
func _link_jiahu_target(sequence: RuleStepSequence, response: ChoiceResponse = null) -> void:
	if response == null:
		response = sequence.choice_response
	if response == null or not response.confirmed or response.target_ids.size() != 1:
		sequence.finish()
		return
	# 最终目标ID；必须仍然存活、竖置且护盾为0才执行顺序效果。
	var target_id: int = response.target_ids[0]
	if not _get_eligible_target_ids().has(target_id):
		sequence.finish()
		return
	sequence.context["target_id"] = target_id
	sequence.context["target_character_generation"] = host.state.get_player(target_id).character_generation
	if not bool(host.call("set_player_linked", target_id, true, owner_player_id, get_id())):
		sequence.finish()
		return
	announce_activation({"target_id":target_id})


## 第三步提供护盾；目标换将或离场后不向同座位的新角色泄漏旧效果。
func _grant_jiahu_shield(sequence: RuleStepSequence) -> void:
	# 已确认目标ID；由横置步骤写入，不重新选择或重复发动技能。
	var target_id: int = int(sequence.context.get("target_id", -1))
	# 当前目标；体力存活和武将代次校验保证异步结果仍属于同一角色。
	var target: PlayerState = host.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or target.character_generation != int(sequence.context.get("target_character_generation", -1)):
		return
	get_skill_player(target_id).shield(SHIELD_AMOUNT, get_owner_skill_player())
	observe_identity_behavior([target_id], {"target_result":1.0})

## 返回当前全部竖置、无护盾且在场存活的角色ID；座次顺序用于稳定交互与回放。
func _get_eligible_target_ids() -> Array[int]:
	# 合法目标结果；空数组表示本次效果不可触发，上层将直接跳过。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game and not player.chained and player.shield <= 0:
			result.append(player.player_id)
	return result


## 评估加护目标；只为态度为正的角色承担横置代价并提供护盾。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非加护目标步骤不提供额外评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "jiahu_target":
		return 0.0
	# 选择动作负载；取消或无目标保持0分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 已选目标数组；本技能每次只允许一名目标。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if not bool(payload.get("confirmed", false)) or selected_targets.size() != 1:
		return 0.0
	# 目标ID；用于读取持有者对其的当前身份态度。
	var target_id: int = int(selected_targets[0])
	# 当前态度；非友方不值得主动提供防御资源。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if attitude <= 0.0:
		return attitude - AI_LINK_COST
	return attitude / 5.0 * AI_SHIELD_VALUE - AI_LINK_COST
