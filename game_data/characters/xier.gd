extends CharacterDefinition

## 【希儿】武将源码。武将通过独立技能组件配置【再现】与【蝶影】。

## 【再现】技能脚本；负责弃牌强化【杀】并在造成伤害后追加额外出牌阶段。
const ZAIXIAN_SKILL: Script = preload("res://game_data/skills/zaixian.gd")

## 【蝶影】技能脚本；负责统计本回合进入弃牌堆的【杀】并在回合结束时换牌。
const DIEYING_SKILL: Script = preload("res://game_data/skills/dieying.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "xier",
		"display_name": "希儿",
		"gender": "female",
		"faction": "beiluoboge",
		"max_hp": 4,
		"description": "以【杀】造成伤害后连续展开出牌阶段。",
	}, [ZAIXIAN_SKILL, DIEYING_SKILL])
