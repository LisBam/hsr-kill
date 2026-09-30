extends CharacterDefinition

## 【瓦尔特】武将源码。武将通过独立技能组件配置【断界】。

## 【断界】技能脚本；负责横置、竖置与翻面的四项可选操作，并在每次发动后删除最后一项。
const DUANJIE_SKILL: Script = preload("res://game_data/skills/duanjie.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "waerte",
		"display_name": "瓦尔特",
		"gender": "male",
		"faction": "xingqionglieche",
		"max_hp": 4,
		"description": "以断界在横置与翻面之间切换战局，但每用掉一项选择，就永远失去最后那一项。",
	}, [DUANJIE_SKILL])
