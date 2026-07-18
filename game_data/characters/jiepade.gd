extends CharacterDefinition

## 【杰帕德】武将源码。武将通过独立技能组件配置【永屹】。

## 【永屹】技能脚本；负责体力值受伤后的额外弃牌与护盾，以及护盾换取额外出牌阶段。
const YONGYI_SKILL: Script = preload("res://game_data/skills/yongyi.gd")


## 写入武将名称、性别、势力、4点体力上限、长期说明与技能代码引用。
func _init() -> void:
	super({
		"id": "gepard",
		"display_name": "杰帕德",
		"gender": "male",
		"faction": "beiluoboge",
		"max_hp": 4,
		"description": "以伤害后的阶段调度积累护盾，并将护盾转化为额外出牌机会。",
	}, [YONGYI_SKILL])
