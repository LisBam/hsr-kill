extends SkillDefinition

## 【无邪】技能源码。虎克造成伤害后，可以令本次受到伤害的角色回复1点体力。

## 单次发动回复的体力值；固定为1，修改时必须同步技能原文与玩法文档。
const RECOVER_AMOUNT: int = 1

## AI确认帮助自己或友方时使用的额外正向倾向；只影响选择，不修改回复数值。
const AI_FRIENDLY_CONFIRM_BONUS: float = 8.0

## AI面对敌方目标时使用的拒绝分；确保可取消询问不会帮助敌方回复。
const AI_HOSTILE_CONFIRM_SCORE: float = -20.0

## 群体伤害牌命中一名友方时的回复补偿；按1点体力等于2张牌的统一资源尺度抵消友伤。
const AI_FRIENDLY_AOE_RECOVERY_COMPENSATION: float = 4.0


## 写入技能静态信息；技能描述严格保持需求钦定原文。
func _init() -> void:
	super({
		"id":"wuxie_2",
		"name":"无邪",
		"trigger":"damageAfter",
		"ui_enabled":false,
		"description":"当你造成伤害后，你可令受到伤害的角色回复1点体力。",
	})


## 订阅技能持有者作为伤害来源的标准伤害后时机。
func install() -> void:
	subscribe_timing("damageAfter", _on_damage_after, "source")


## 对仍在场且体力未满的受伤角色创建零材料确认请求。
func _on_damage_after(event: RuleEvent) -> void:
	if event.source_id != owner_player_id or int(event.data.get("amount", 0)) <= 0:
		return
	# 本次受到伤害的目标；等待前先校验其仍可获得回复。
	var target: PlayerState = host.state.get_player(event.target_id)
	if target == null or not target.alive or target.out_of_game or target.hp >= target.max_hp:
		return
	request_card_selection("无邪", "是否令受到伤害的角色回复1点体力？", [], 0, 0, true, {"kind":"wuxie_2_confirm", "target_id":event.target_id, "ai_allow_confirm":true})


## 恢复无邪确认；目标等待期间失效或已满体力时安全跳过。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "wuxie_2_confirm" or response == null:
		return false
	if not response.confirmed:
		return true
	# 固定回复目标；其必须仍然存活、在场且体力未满。
	var target_id: int = int(context.get("target_id", -1))
	# 固定回复目标状态；重新读取权威状态避免异步等待使用旧对象。
	var target: PlayerState = host.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or target.hp >= target.max_hp:
		return true
	announce_activation({"target_id":target_id})
	host.call("recover", owner_player_id, target_id, RECOVER_AMOUNT, get_id())
	observe_identity_behavior([target_id], {"target_result":1.0})
	return true


## AI无条件帮助自己和友方，拒绝为敌方回复体力。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 当前请求上下文；非无邪确认不提供技能评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "wuxie_2_confirm":
		return 0.0
	# 当前选择负载；取消动作保持零分供敌方目标选择。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 固定回复目标ID；用于读取虎克对其的身份态度。
	var target_id: int = int(context.get("target_id", -1))
	# 当前关系态度；自身或正态度角色始终发动，敌方明确拒绝。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	if target_id == owner_player_id or attitude > 0.0:
		return AI_FRIENDLY_CONFIRM_BONUS + evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, RECOVER_AMOUNT)
	return AI_HOSTILE_CONFIRM_SCORE


## 为群体伤害牌补回命中友方后可由无邪恢复1点体力的收益，避免AI重复计算友伤净损失。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前逻辑牌定义；只有明确声明为多目标伤害时才应用补偿。
	var card_definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	if not bool((card_definition.get("ai", {}) as Dictionary).get("damage", false)) or not bool((card_definition.get("ai", {}) as Dictionary).get("multitarget", false)):
		return current_score
	# 最终评分；每名自己或友方实际目标各补偿一次1点回复价值。
	var result: float = current_score
	for target_variant: Variant in action.get("target_ids", []) as Array:
		# 当前伤害目标ID；只按持有者可感知态度判断友方关系。
		var target_id: int = int(target_variant)
		if target_id == owner_player_id or evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) > 0.0:
			result += AI_FRIENDLY_AOE_RECOVERY_COMPENSATION
	return result
