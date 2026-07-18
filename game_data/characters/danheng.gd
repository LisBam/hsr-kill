extends CharacterDefinition

## 【丹恒】武将源码。武将通过独立技能组件配置【罡风】与【疾雨】。

## 【罡风】技能脚本；负责黑色牌当雷【杀】使用或打出的视为牌流程。
const GANGFENG_SKILL: Script = preload("res://game_data/skills/gangfeng.gd")

## 【疾雨】技能脚本；负责雷【杀】的横置切换、目标分支与【闪】响应限制。
const JIYU_SKILL: Script = preload("res://game_data/skills/jiyu.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "dan_heng",
		"display_name": "丹恒",
		"gender": "male",
		"faction": "xingqionglieche",
		"max_hp": 4,
		"description": "以黑色牌转化雷【杀】，并通过横置与响应限制强化攻击。",
	}, [GANGFENG_SKILL, JIYU_SKILL])
