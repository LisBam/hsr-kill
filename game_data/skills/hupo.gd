extends SkillDefinition

## 【琥珀】技能源码。持有者成为黑色【杀】目标时，由目标时机直接排除本目标。


## 写入锁定技静态信息；同一脚本可作为武将固有技能或临时技能独立安装。
func _init() -> void:
	super({
		"id": "hupo",
		"name": "琥珀",
		"trigger": "useCardToPlayer",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，你无法成为黑色【杀】的目标。",
	})


## 订阅持有者成为用牌目标的最早逐目标时机；取消该时机会把持有者加入本牌排除目标集合。
func install() -> void:
	subscribe_timing("useCardToPlayer", _on_owner_targeted, "target", 100)


## 在实体牌合法性与AI候选阶段直接拒绝黑色【杀】目标；虚拟牌颜色未知时由目标时机再次复核。
func validate_incoming_card_target_selection(_actor_id: int, card_definition: Dictionary, card_color: String) -> String:
	if str(card_definition.get("effect_id", "")) == "slash" and card_color == "black":
		return "【琥珀】令该角色无法成为黑色【杀】的目标。"
	return ""


## 黑色【杀】指定持有者时强制令该目标无效；其他颜色与非【杀】不受影响。
func _on_owner_targeted(event: RuleEvent) -> void:
	# 当前使用牌UID；用于从处理区读取虚拟或实体牌的真实颜色与逻辑定义。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if not bool(host.call("is_processing_black_slash", card_uid)):
		return
	announce_activation({"card_uid":card_uid, "source_id":event.source_id})
	event.cancel()
