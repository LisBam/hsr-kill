extends CharacterDefinition

## 【三月七】武将源码。武将通过独立技能组件配置【加护】与【冰封】。

## 【加护】技能脚本；负责准备阶段的横置与护盾支援。
const JIAHU_SKILL: Script = preload("res://game_data/skills/jiahu.gd")

## 【冰封】技能脚本；负责唯一目标牌的竖置、弃牌、无效与每目标限次。
const BINGFENG_SKILL: Script = preload("res://game_data/skills/bingfeng.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "march_7th",
		"display_name": "三月七",
		"gender": "female",
		"faction": "xingqionglieche",
		"max_hp": 3,
		"description": "以横置状态与护盾保护队友，并将唯一目标牌转化为控制效果。",
	}, [JIAHU_SKILL, BINGFENG_SKILL])
