extends CharacterDefinition

## 【丹恒·饮月】武将源码。武将通过独立技能组件配置【伏辰】与【濯世】。

## 【伏辰】技能脚本；负责在其他角色打出【杀】后获得该实体牌。
const FUCHEN_SKILL: Script = preload("res://game_data/skills/fuchen.gd")

## 【濯世】技能脚本；负责出牌阶段的三段弃牌与雷电伤害主动流程。
const ZHUOSHI_SKILL: Script = preload("res://game_data/skills/zhuoshi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "danheng_yinyue",
		"display_name": "丹恒·饮月",
		"gender": "male",
		"faction": "xianzhou",
		"max_hp": 4,
		"description": "以他人打出的【杀】为引，分三段弃置基本牌换取拆牌与雷电伤害。",
	}, [FUCHEN_SKILL, ZHUOSHI_SKILL])
