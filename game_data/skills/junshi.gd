extends SkillDefinition

## 【军势】技能源码。任意角色在一个出牌阶段内首次以【杀】指定目标时，持有者可令其摸一张牌。

## 【军势】对摸牌角色的身份观察牌效；正1表示成功发动是一次公开帮助行为，不改变实际摸牌数。
const IDENTITY_TARGET_RESULT: float = 1.0

## 当前出牌阶段是否已经发动；每次 phaseUseBegin 重置，确认发动后设为 true。
var _used_this_play_phase: bool = false


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "junshi",
		"name": "军势",
		"trigger": "useCardToTargeted",
		"ui_enabled": false,
		"description": "一名角色的出牌阶段，当其使用【杀】指定目标时，你可令其摸一张牌。每阶段限一次。",
	})


## 订阅所有角色的出牌阶段开始与指定目标时机；次数状态只保存在本技能运行时实例。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_any_play_phase_begin, "global")
	subscribe_timing("useCardToTargeted", _on_slash_targeted, "global")


## 每个新的出牌阶段都恢复一次发动额度，包括额外出牌阶段。
func _on_any_play_phase_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 【杀】指定目标时创建零材料确认请求；确认后摸牌，取消则本阶段仍可在后续【杀】上发动。
func _on_slash_targeted(event: RuleEvent) -> void:
	if _used_this_play_phase or host.state.current_phase != "play":
		return
	# 当前逻辑牌定义；普通、火和雷【杀】统一以 effect_id=slash 判定，不维护卡牌 ID 白名单。
	var card_definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(card_definition.get("effect_id", "")) != "slash":
		return
	request_card_selection("军势", "是否发动【军势】令使用【杀】的角色摸一张牌？", [], 0, 0, true, {"kind":"junshi_confirm", "slash_user_id":event.source_id, "ai_allow_confirm":true})


## 恢复发动确认；只有明确确认才消耗本阶段次数并令【杀】使用者摸一张牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "junshi_confirm" or response == null:
		return false
	if response.confirmed and not _used_this_play_phase:
		# 使用【杀】的角色 ID；等待期间若角色已死亡，摸牌端口会安全忽略。
		var slash_user_id: int = int(context.get("slash_user_id", -1))
		_used_this_play_phase = true
		observe_identity_behavior([slash_user_id], {"target_result":IDENTITY_TARGET_RESULT})
		host.call("draw", slash_user_id, 1)
	return true


## 根据技能持有者对【杀】使用者的态度决定是否发动；友方摸牌为正收益，敌方摸牌为负收益。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理军势确认步骤。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "junshi_confirm":
		return 0.0
	# 当前动作负载；取消动作不产生摸牌效果。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 【杀】使用者 ID；技能令该角色固定摸1张牌。
	var slash_user_id: int = int(context.get("slash_user_id", -1))
	return evaluator.get_attitude(authoritative_snapshot, owner_player_id, slash_user_id) / 2.0
