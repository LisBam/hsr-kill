extends CharacterDefinition

## 【大黑塔】武将源码。武将通过独立技能组件配置【解构】【灵感】与【看破】。

## 【解构】技能脚本；负责重铸非延时锦囊并记录其牌名。
const JIEGOU_SKILL: Script = preload("res://game_data/skills/jiegou.gd")

## 【灵感】技能脚本；负责视为使用记录牌名并按另一记录牌名结算目标。
const LINGGAN_SKILL: Script = preload("res://game_data/skills/linggan.gd")

## 【看破】技能脚本；负责移除记录牌名并令锦囊对自身无效。
const KANPO_SKILL: Script = preload("res://game_data/skills/kanpo.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "daheita",
		"display_name": "大黑塔",
		"gender": "female",
		"faction": "yinhexvezhe",
		"max_hp": 3,
		"description": "以解构记录牌名，用灵感重演并改写目标，用看破抵消指向自己的锦囊。",
	}, [JIEGOU_SKILL, LINGGAN_SKILL, KANPO_SKILL])
