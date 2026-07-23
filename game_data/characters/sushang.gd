extends CharacterDefinition

## 【素裳】武将源码。武将通过独立技能组件组合【剑势】判定增伤与【山倾】双牌花色【杀】。

## 【剑势】技能脚本；负责【杀】伤害前确认、可暂停判定与红色结果增伤。
const JIANSHI_SKILL: Script = preload("res://game_data/skills/jianshi.gd")

## 【山倾】技能脚本；负责双材料虚拟【杀】、花色效果、回合限次与完整 AI 决策。
const SHANQING_SKILL: Script = preload("res://game_data/skills/shanqing.gd")


## 写入素裳的稳定资料与技能组件顺序。
func _init() -> void:
	super({
		"id":"sushang",
		"display_name":"素裳",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":4,
		"description":"仙舟联盟的云骑新人，以剑势强化【杀】，并用两张牌汇聚花色效果发动山倾。",
	}, [JIANSHI_SKILL, SHANQING_SKILL])
