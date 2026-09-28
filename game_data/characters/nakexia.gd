extends CharacterDefinition

## 【那刻夏】武将源码。武将通过独立技能组件配置【逐虚】【揭质】与【留白】。

## 【逐虚】技能脚本；负责两节轮回的随机弃牌与随机伤害。
const ZHUXV_SKILL: Script = preload("res://game_data/skills/zhuxv.gd")

## 【揭质】技能脚本；负责在逐虚结算后对同一目标重复执行同一节效果。
const JIEZHI_SKILL: Script = preload("res://game_data/skills/jiezhi.gd")

## 【留白】技能脚本；负责重置其他技能并在本回合结束时永久失去全部技能。
const LIUBAI_SKILL: Script = preload("res://game_data/skills/liubai.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "nakexia",
		"display_name": "那刻夏",
		"gender": "female",
		"faction": "wengfaluosi",
		"max_hp": 3,
		"description": "以随机削弱与随机伤害推进轮回，用重置换取本回合末尾的技能枯竭。",
	}, [ZHUXV_SKILL, JIEZHI_SKILL, LIUBAI_SKILL])
