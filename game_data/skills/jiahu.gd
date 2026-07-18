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
	request_target_selection("【加护】请选择一名武将牌竖置且没有护盾的角色", target_ids, 0, 1, true, {"kind":"jiahu_target"})


## 恢复加护目标选择；等待期间目标状态改变时直接跳过已不可执行的效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "jiahu_target" or response == null:
		return false
	if not response.confirmed or response.target_ids.size() != 1:
		return true
	# 最终目标ID；必须仍然存活、竖置且护盾为0才执行顺序效果。
	var target_id: int = response.target_ids[0]
	if not _get_eligible_target_ids().has(target_id):
		return true
	if not bool(host.call("set_player_linked", target_id, true, owner_player_id, get_id())):
		return true
	announce_activation({"target_id":target_id})
	get_skill_player(target_id).shield(SHIELD_AMOUNT, get_owner_skill_player())
	observe_identity_behavior([target_id], {"target_result":1.0})
	return true


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
