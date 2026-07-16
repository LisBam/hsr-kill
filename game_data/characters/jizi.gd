extends CharacterDefinition

## 【姬子】武将源码。武将通过脚本资源直接配置【轨道打击】。

## 【轨道打击】技能脚本；技能安装与效果只在对应技能文件维护。
const GUIDAODAJI_SKILL: Script = preload("res://game_data/skills/guidaodaji.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "himeko",
		"display_name": "姬子",
		"gender": "female",
		"faction": "astral_express",
		"max_hp": 4,
		"description": "群体效果样例武将，仅提供扩展结构。",
	}, [GUIDAODAJI_SKILL])
