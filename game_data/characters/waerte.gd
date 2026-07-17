extends CharacterDefinition

## 【瓦尔特】武将源码。武将通过脚本资源直接配置【重力压制】。

## 【重力压制】技能脚本；每局运行时实例互相独立，不共享技能状态。
const ZHONGLIYAZHI_SKILL: Script = preload("res://game_data/skills/zhongliyazhi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "welt",
		"display_name": "瓦尔特",
		"gender": "male",
		"faction": "xingqionglieche",
		"max_hp": 4,
		"description": "控制效果样例武将，仅提供扩展结构。",
	}, [ZHONGLIYAZHI_SKILL])
