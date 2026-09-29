extends SkillDefinition

## 【星火】技能源码。持有者使用牌指定一名武将牌竖置的唯一目标后，自动令目标进入连环状态。
## 牌的类型不受限制：锦囊、【杀】以及装备、【桃】等自指牌都按“使用牌指定目标”统一判定。
## 目标已经横置时不满足“竖置”条件，技能整体不触发，也不会把已横置目标改回竖置。


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "xinghuo",
		"name": "星火",
		"trigger": "useCardToTargeted",
		"locked": true,
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，当你使用牌指定一名武将牌竖置的唯一目标后，你横置目标角色。若该角色为你，你摸一张牌。",
	})


## 订阅持有者使用牌的指定目标后时机；锁定技不创建发动询问。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_owner_card_targeted, "source")


## 仅处理最终目标数组恰好为一名角色、且该目标武将牌竖置的使用牌；牌的类型不作为触发条件。
func _on_owner_card_targeted(event: RuleEvent) -> void:
	# 最终目标数组；唯一目标按数组长度判断，不因目标是否为自己或牌的类型而改变。
	var target_ids: Array = event.data.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return
	# 唯一目标 ID；逐目标时机的 target_id 与最终数组成员应一致，仍以事件字段作为权威目标。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	# 目标武将牌状态；只有竖置（未横置）的目标满足技能条件，已横置目标整体不触发。
	var target: PlayerState = host.state.get_player(target_id)
	if target == null or target.chained:
		return
	announce_activation({"target_id":target_id, "card_uid":int(event.data.get("card_uid", -1))})
	host.call("set_player_linked", target_id, true, owner_player_id, get_id())
	if target_id == owner_player_id:
		host.call("draw", owner_player_id, 1)


## 修正持有者使用牌指定唯一竖置目标的评分；横置敌方有利，横置友方不利，自身目标额外计入摸1张牌。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前目标数组；技能要求最终恰好一名目标，牌的类型同样不参与判定。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return current_score
	# 唯一目标 ID；已横置目标不满足“竖置”条件，技能不生效也不产生任何收益。
	var target_id: int = int(target_ids[0])
	# 唯一目标快照；无效目标保持原评分。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or bool(target.get("chained", false)):
		return current_score
	# 横置或重置价值；未横置敌方适合横置，已横置友方适合重置，重复横置不会静默失效。
	# 连环切换评分；当前横置时重置方向与施加横置严格相反。
	# 说明：技能改为“指定一名武将牌竖置的唯一目标”后，已横置目标在上方提前返回，上述反转分支不再执行。
	var target_attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 竖置目标的横置收益；只保留施加横置的唯一方向，敌方计为正收益、友方计为负收益。
	var link_score: float = -target_attitude * 0.25
	# 自身目标摸牌收益；统一入口按1张牌计算，避免技能文件维护另一套资源比例。
	var self_draw_score: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, 1, 0) if target_id == owner_player_id else 0.0
	return current_score + link_score + self_draw_score
