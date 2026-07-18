extends SkillDefinition

## 【星火】技能源码。持有者使用锦囊牌或【杀】指定唯一目标后，自动令目标进入连环状态。
## 目标已经横置时再次应用同一横置效果会切换为竖置，目标状态不会保持不变。


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "xinghuo",
		"name": "星火",
		"trigger": "useCardToTargeted",
		"locked": true,
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，当你使用锦囊牌或【杀】指定唯一目标后，你横置目标角色。若该角色为你，你摸一张牌。",
	})


## 订阅持有者使用牌的指定目标后时机；锁定技不创建发动询问。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_owner_card_targeted, "source")


## 仅处理锦囊牌或【杀】且最终目标数组恰好为一名角色的使用牌。
func _on_owner_card_targeted(event: RuleEvent) -> void:
	# 最终目标数组；唯一目标按数组长度判断，不因目标是否为自己而改变。
	var target_ids: Array = event.data.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return
	# 当前牌定义；锦囊牌读取 type=trick，【杀】读取共享 effect_id=slash。
	var definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(definition.get("type", "")) != "trick" and str(definition.get("effect_id", "")) != "slash":
		return
	# 唯一目标 ID；逐目标时机的 target_id 与最终数组成员应一致，仍以事件字段作为权威目标。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	announce_activation({"target_id":target_id, "card_uid":int(event.data.get("card_uid", -1))})
	host.call("toggle_player_linked", target_id, owner_player_id, get_id())
	if target_id == owner_player_id:
		host.call("draw", owner_player_id, 1)


## 修正持有者使用锦囊或【杀】指定唯一目标的评分；横置敌方有利，横置友方不利，自身目标额外计入摸1张牌。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前卡牌定义；只有锦囊牌或共享 effect_id=slash 的【杀】触发技能。
	var definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	if str(definition.get("type", "")) != "trick" and str(definition.get("effect_id", "")) != "slash":
		return current_score
	# 当前目标数组；技能要求最终恰好一名目标。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return current_score
	# 唯一目标 ID；已横置目标不再获得重复横置收益。
	var target_id: int = int(target_ids[0])
	# 唯一目标快照；无效目标保持原评分。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return current_score
	# 横置或重置价值；未横置敌方适合横置，已横置友方适合重置，重复横置不会静默失效。
	var target_attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 连环切换评分；当前横置时重置方向与施加横置严格相反。
	var link_score: float = target_attitude * 0.25 if bool(target.get("chained", false)) else -target_attitude * 0.25
	# 自身目标摸牌收益；固定按2分加入，代表一张未知牌的直接资源收益。
	var self_draw_score: float = 2.0 if target_id == owner_player_id else 0.0
	return current_score + link_score + self_draw_score
