extends SkillDefinition

## 【星火】技能源码。持有者使用锦囊牌或【杀】指定唯一目标后，自动令目标进入连环状态。


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "xinghuo",
		"name": "星火",
		"trigger": "useCardToTargeted",
		"locked": true,
		"ui_enabled": false,
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
	host.call("set_player_linked", target_id, true, owner_player_id, get_id())
	if target_id == owner_player_id:
		host.call("draw", owner_player_id, 1)
