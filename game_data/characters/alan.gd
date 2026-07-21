extends CharacterDefinition

## 【阿兰】武将源码。武将通过独立技能组件配置【倾力】与【强攻】。

## 【倾力】技能脚本；负责失去体力并视为使用或打出雷【杀】。
const QINGLI_SKILL: Script = preload("res://game_data/skills/qingli.gd")

## 【强攻】技能脚本；负责按费用牌颜色或武器类型强化【杀】。
const QIANGGONG_SKILL: Script = preload("res://game_data/skills/qianggong.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"alan",
		"display_name":"阿兰",
		"gender":"male",
		"faction":"xingjianhuanyv",
		"max_hp":4,
		"description":"以体力换取雷【杀】，并通过弃牌强化命中与伤害。",
	}, [QINGLI_SKILL, QIANGGONG_SKILL])
