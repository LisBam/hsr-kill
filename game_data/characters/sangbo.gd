extends CharacterDefinition

## 【桑博】武将源码。武将通过独立技能组件配置【破风】。

## 【破风】技能脚本；负责结束阶段弃牌取得带目标限制的额外完整回合。
const POFENG_SKILL: Script = preload("res://game_data/skills/pofeng.gd")


## 写入武将名称、性别、势力、4点体力上限、长期说明与技能代码引用。
func _init() -> void:
	super({
		"id": "sangbo",
		"display_name": "桑博",
		"gender": "male",
		"faction": "beiluoboge",
		"max_hp": 4,
		"description": "以本回合【杀】目标为行动边界，通过弃牌换取受限的额外完整回合。",
	}, [POFENG_SKILL])
