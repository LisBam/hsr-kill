extends SkillDefinition

## 【智识】技能源码。持有者每次使用锦囊牌时可摸一张牌。


## 写入触发技能静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"zhishi",
		"name":"智识",
		"trigger":"useCard",
		"ui_enabled":false,
		"description":"当你使用锦囊牌时，你可以摸一张牌。",
	})


## 订阅持有者的使用与打出时机；普通锦囊走useCard，无懈可击等响应锦囊走respond。
func install() -> void:
	subscribe_timing("useCard", _on_owner_used_card, "source")
	subscribe_timing("respond", _on_owner_used_card, "source")


## 使用或打出锦囊牌时创建零材料确认请求；卡牌类别统一来自定义，取消不产生任何资源变化。
func _on_owner_used_card(event: RuleEvent) -> void:
	var definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if str(definition.get("type", "")) != "trick":
		return
	request_card_selection("智识", "是否发动【智识】摸一张牌？", [], 0, 0, true, {"kind":"zhishi_confirm", "card_uid":int(event.data.get("card_uid", -1)), "ai_allow_confirm":true})


## 恢复发动确认并摸一张牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "zhishi_confirm" or response == null:
		return false
	if response.confirmed:
		announce_activation({"card_uid":int(context.get("card_uid", -1))})
		host.call("draw", owner_player_id, 1)
	return true


## 摸一张牌始终是正资源收益，基础AI会在可发动时确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "zhishi_confirm" or not bool((action.get("payload", {}) as Dictionary).get("confirmed", false)):
		return 0.0
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, owner_player_id, 1, 0)
