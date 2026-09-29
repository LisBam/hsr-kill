extends CharacterDefinition

## 【白厄】武将源码。武将通过【负火】积累12枚火种，并由觉醒技【轮回】进入特殊形态【卡厄斯兰那】。

## 【负火】技能脚本；负责四项每回合独立额度、火种积累与不足5张时补牌。
const FUHUO_SKILL: Script = preload("res://game_data/skills/fuhuo.gd")

## 【轮回】技能脚本；负责觉醒判定、区域废除、友方离场、全场翻面、特殊换形态与额外回合。
const LUNHUI_SKILL: Script = preload("res://game_data/skills/lunhui.gd")

## 【薪继】技能脚本；负责领袖技触发、火种给予与其全部轮回技推进。
const XINJI_SKILL: Script = preload("res://game_data/skills/xinji.gd")


## 写入白厄的稳定资料、4点体力上限与技能组件顺序。
func _init() -> void:
	super({
		"id":"baie",
		"display_name":"白厄",
		"gender":"male",
		"faction":"wengfaluosi",
		"max_hp":4,
		"description":"翁法罗斯的救世者，以负火积累火种，并通过轮回觉醒为特殊形态卡厄斯兰那。",
	}, [FUHUO_SKILL, LUNHUI_SKILL, XINJI_SKILL])
