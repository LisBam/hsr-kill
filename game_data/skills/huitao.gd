extends SkillDefinition

## 【回涛】技能源码。任意角色的轮回技进入下一个轮回时，持有者可令该轮回技的持有者摸一张牌。

## 可触发【回涛】的轮回节数下限；数值3来自技能原文“轮回节数不小于3”。
const MIN_SECTION_COUNT: int = 3

## 视为“进入下一个轮回”的最小轮回数；首次开始与重置都会发布同一时机且轮回数为1，必须排除。
const MIN_ROUND_COUNT: int = 2

## 令轮回技持有者摸取的牌数；数值1来自技能原文“摸一张牌”。
const DRAW_COUNT: int = 1

## 确认发动选择业务类型；与恢复分支共用同一稳定值。
const CONFIRM_KIND: String = "huitao_confirm"


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id":"huitao",
		"name":"回涛",
		"trigger":"reincarnationStart",
		"ui_enabled":true,
		"description":"当一名角色的轮回技进入下一个轮回时，若该轮回技的轮回节数不小于3，你可令其摸一张牌。",
	})


## 订阅全场的轮回开始时机；role=global 才能观察任意角色轮回技的推进，而不只限于持有者自己。
func install() -> void:
	subscribe_timing("reincarnationStart", _on_reincarnation_start, "global")


## 读取节数与轮回数门槛后创建零材料确认请求；收益者固定为该轮回技的持有者。
func _on_reincarnation_start(event: RuleEvent) -> void:
	if event == null:
		return
	# 技能持有者；死亡或离场后不再产生发动入口。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 轮回节数门槛；节数不足3的轮回技推进时不出现入口。
	if int(event.data.get("section_count", 1)) < MIN_SECTION_COUNT:
		return
	# 轮回数门槛；reset 与首次开始也会发布同一时机且轮回数为1，只有至少2才属于“进入下一个轮回”。
	if int(event.data.get("round_count", 1)) < MIN_ROUND_COUNT:
		return
	request_card_selection("回涛", "是否发动【回涛】令其摸一张牌？", [], 0, 0, true, {"kind":CONFIRM_KIND, "trigger_player_id":event.player_id, "ai_allow_confirm":true})


## 恢复发动确认；只有明确确认才令该轮回技的持有者摸一张牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CONFIRM_KIND:
		return false
	if response.confirmed:
		# 轮回技持有者；等待期间已经死亡或离场时摸牌端口会安全忽略。
		var trigger_player_id: int = int(context.get("trigger_player_id", -1))
		host.call("draw", trigger_player_id, DRAW_COUNT)
		announce_activation({"trigger_player_id":trigger_player_id, "draw_count":DRAW_COUNT})
	return true


## 按统一资源换算评估轮回技持有者摸1张牌；对自己与友方为正收益，对敌方为负收益。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理回涛确认步骤。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CONFIRM_KIND:
		return 0.0
	# 当前动作负载；取消动作不产生摸牌效果。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 轮回技持有者 ID；技能令该角色固定摸1张牌。
	var trigger_player_id: int = int(context.get("trigger_player_id", -1))
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, trigger_player_id, DRAW_COUNT, 0)
