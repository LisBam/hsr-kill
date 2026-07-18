extends CharacterDefinition

## 【雪衣】武将源码。武将通过独立技能组件组合【还阳】与【摄伏】。

## 【还阳】技能脚本；伤害来源距离与回复均通过权威规则端口结算。
const HUANYANG_SKILL: Script = preload("res://game_data/skills/huanyang.gd")

## 【摄伏】技能脚本；每个全局回合的首次伤害额度由独立实例保存。
const SEFU_SKILL: Script = preload("res://game_data/skills/sefu.gd")


## 写入武将静态信息与技能组件引用；稳定ID按设计要求使用xveyi。
func _init() -> void:
	super({
		"id": "xveyi",
		"display_name": "雪衣",
		"gender": "female",
		"faction": "xianzhou",
		"max_hp": 4,
		"description": "仙舟联盟的判官，能从近距离伤害中恢复，并按造成伤害的牌名字数调取资源。",
	}, [HUANYANG_SKILL, SEFU_SKILL])
