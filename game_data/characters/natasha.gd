extends CharacterDefinition

## 【娜塔莎】武将源码。武将通过独立技能组件组合【药理】与【焕发】。

## 【药理】技能脚本；每名娜塔莎持有者拥有独立的阶段次数状态。
const YAOLI_SKILL: Script = preload("res://game_data/skills/yaoli.gd")

## 【焕发】技能脚本；每名娜塔莎持有者独立记录每轮发动次数。
const HUANFA_SKILL: Script = preload("res://game_data/skills/huanfa.gd")


## 写入武将静态信息与技能组件引用。
func _init() -> void:
	super({
		"id": "natasha",
		"display_name": "娜塔莎",
		"gender": "female",
		"faction": "beiluoboge",
		"max_hp": 3,
		"description": "贝洛伯格的医者，能够将红色手牌化为药物并激发队友继续行动。",
	}, [YAOLI_SKILL, HUANFA_SKILL])
