extends CharacterDefinition

## 【穹】武将源码。武将通过独立技能组件配置【王牌】与【全垒】。

## 【王牌】技能脚本；负责解除【杀】的配置化使用次数限制。
const WANGPAI_SKILL: Script = preload("res://game_data/skills/wangpai.gd")

## 【全垒】技能脚本；负责每个出牌阶段一次的手牌转化多目标雷【杀】流程。
const QUANLEI_SKILL: Script = preload("res://game_data/skills/quanlei.gd")


## 写入武将名称、性别、势力、4点体力上限、长期说明与技能代码引用。
func _init() -> void:
	super({
		"id": "qiong",
		"display_name": "穹",
		"gender": "male",
		"faction": "xingqionglieche",
		"max_hp": 4,
		"description": "不受【杀】次数限制，并能将手牌转化为至多双目标雷【杀】。",
	}, [WANGPAI_SKILL, QUANLEI_SKILL])
