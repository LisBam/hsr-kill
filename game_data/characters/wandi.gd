extends CharacterDefinition

## 【万敌】武将源码。武将通过独立技能组件组合【血仇】轮回濒死效果与【弑神】强化【杀】。

## 【血仇】技能脚本；负责轮回数、两段濒死效果与轮回推进。
const XVECHOU_SKILL: Script = preload("res://game_data/skills/xvechou.gd")

## 【弑神】技能脚本；负责前X张【杀】解除距离次数限制及逐目标失去体力增伤。
const SHISHEN_SKILL: Script = preload("res://game_data/skills/shishen.gd")


## 写入万敌的稳定资料、5点体力上限与技能组件顺序。
func _init() -> void:
	super({
		"id":"wandi",
		"display_name":"万敌",
		"gender":"male",
		"faction":"wengfaluosi",
		"max_hp":5,
		"description":"翁法罗斯的战士，以血仇轮回应对濒死，并用弑神强化前X张【杀】。",
	}, [XVECHOU_SKILL, SHISHEN_SKILL])
