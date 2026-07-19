extends SkillDefinition

## 【王牌】技能源码。持有者使用规则牌名为【杀】的卡牌时不受配置化次数限制。


## 写入锁定技静态信息；技能描述严格保持武将面板原文。
func _init() -> void:
	super({
		"id": "wangpai",
		"name": "王牌",
		"trigger": "modifier",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，你使用【杀】无次数限制。",
	})


## 仅解除共享slash牌族的使用次数限制；距离、目标数与响应规则保持不变。
func ignores_play_count_limit(card_definition: Dictionary) -> bool:
	return str(card_definition.get("play_limit_group", "")) == "slash"
