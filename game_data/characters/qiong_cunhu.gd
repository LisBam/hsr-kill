extends CharacterDefinition

## 【穹】存护形态武将源码。稳定ID为qiong_cunhu，与其他同名武将仅通过ID区分。

## 【琥珀】技能脚本；负责令黑色【杀】无法指定持有者为目标。
const HUPO_SKILL: Script = preload("res://game_data/skills/hupo.gd")

## 【坚垒】技能脚本；负责弃【闪】保护距离1的黑色【杀】目标。
const JIANLEI_SKILL: Script = preload("res://game_data/skills/jianlei.gd")


## 写入武将名称、性别、势力、4点体力上限、长期说明与技能代码引用。
func _init() -> void:
	super({
		"id": "qiong_cunhu",
		"display_name": "穹",
		"gender": "male",
		"faction": "beiluoboge",
		"max_hp": 4,
		"description": "免疫黑色【杀】的目标指定，并能保护距离1的其他角色。",
	}, [HUPO_SKILL, JIANLEI_SKILL])
