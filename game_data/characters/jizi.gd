extends CharacterDefinition

## 【姬子】武将源码。武将通过独立技能组件配置【星火】与【天坠】。

## 【星火】技能脚本；负责唯一目标牌的横置与自指目标摸牌。
const XINGHUO_SKILL: Script = preload("res://game_data/skills/xinghuo.gd")

## 【天坠】技能脚本；负责锦囊牌或重置自身作为发动费用的火属性伤害。
const TIANZHUI_SKILL: Script = preload("res://game_data/skills/tianzhui.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "himeko",
		"display_name": "姬子",
		"gender": "female",
		"faction": "xingqionglieche",
		"max_hp": 3,
		"description": "以连环状态控制目标并引燃火属性伤害。",
	}, [XINGHUO_SKILL, TIANZHUI_SKILL])
