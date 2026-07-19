extends CharacterDefinition

## 【星】存护形态武将源码。稳定ID为xing_cunhu，与其他同名武将仅通过ID区分。

## 【琥珀】技能脚本；负责令黑色【杀】无法指定持有者为目标。
const HUPO_SKILL: Script = preload("res://game_data/skills/hupo.gd")

## 【铁壁】技能脚本；负责轮开始弃【闪】、横置目标并临时授予【琥珀】。
const TIEBI_SKILL: Script = preload("res://game_data/skills/tiebi.gd")


## 写入武将名称、性别、势力、4点体力上限、长期说明与技能代码引用。
func _init() -> void:
	super({
		"id": "xing_cunhu",
		"display_name": "星",
		"gender": "female",
		"faction": "xingqionglieche",
		"max_hp": 4,
		"description": "免疫黑色【杀】的目标指定，并可把该防护临时赋予其他角色。",
	}, [HUPO_SKILL, TIEBI_SKILL])
