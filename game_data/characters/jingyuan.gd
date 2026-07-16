extends CharacterDefinition

## 【景元】武将源码。武将通过脚本资源直接配置【神君】。

## 【神君】技能脚本；延迟触发状态由每名玩家的独立技能实例维护。
const SHENJUN_SKILL: Script = preload("res://game_data/skills/shenjun.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "jing_yuan",
		"display_name": "景元",
		"gender": "male",
		"faction": "xianzhou",
		"max_hp": 4,
		"description": "延迟效果样例武将，仅提供扩展结构。",
	}, [SHENJUN_SKILL])
