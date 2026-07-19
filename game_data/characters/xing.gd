extends CharacterDefinition

## 【星】武将源码。武将通过独立技能组件配置【王牌】与【安打】。

## 【王牌】技能脚本；负责解除【杀】的配置化使用次数限制。
const WANGPAI_SKILL: Script = preload("res://game_data/skills/wangpai.gd")

## 【安打】技能脚本；负责每回合一次的一张牌转化无距离火【杀】流程。
const ANDA_SKILL: Script = preload("res://game_data/skills/anda.gd")


## 写入武将名称、性别、势力、4点体力上限、长期说明与技能代码引用。
func _init() -> void:
	super({
		"id": "xing",
		"display_name": "星",
		"gender": "female",
		"faction": "xingqionglieche",
		"max_hp": 4,
		"description": "不受【杀】次数限制，并能以任意牌发动无距离火【杀】。",
	}, [WANGPAI_SKILL, ANDA_SKILL])
