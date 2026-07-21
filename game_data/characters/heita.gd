extends CharacterDefinition

## 【黑塔】武将源码。武将通过独立技能组件配置【智识】与【机巧】。

## 【智识】技能脚本；负责使用锦囊牌后的可选摸牌。
const ZHISHI_SKILL: Script = preload("res://game_data/skills/zhishi.gd")

## 【机巧】技能脚本；负责锦囊距离解除与防具、宝物弃置保护。
const JIQIAO_SKILL: Script = preload("res://game_data/skills/jiqiao.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"heita",
		"display_name":"黑塔",
		"gender":"female",
		"faction":"yinhexvezhe",
		"max_hp":3,
		"description":"持续使用锦囊补牌，并保护关键装备不被弃置。",
	}, [ZHISHI_SKILL, JIQIAO_SKILL])
