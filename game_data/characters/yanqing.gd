extends CharacterDefinition

## 【彦卿】武将源码。武将通过独立技能组件配置【遥击】与【凌霜】。

## 【遥击】技能脚本；负责对距离最远角色使用【杀】时的无距离限制。
const YAOJI_SKILL: Script = preload("res://game_data/skills/yaoji.gd")

## 【凌霜】技能脚本；负责【杀】指定目标时的翻面、盲选弃牌与次数豁免。
const LINGSHUANG_SKILL: Script = preload("res://game_data/skills/lingshuang.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "yanqing",
		"display_name": "彦卿",
		"gender": "male",
		"faction": "xianzhou",
		"max_hp": 3,
		"description": "以遥击越过距离直取最远之敌，并以凌霜翻面换取弃牌与不计数的一击。",
	}, [YAOJI_SKILL, LINGSHUANG_SKILL])
