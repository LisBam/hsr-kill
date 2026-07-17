extends CharacterDefinition

## 【三月七】武将源码。武将通过脚本资源直接配置【六相冰】。

## 【六相冰】技能脚本；技能规则与元数据均由对应文件独立维护。
const LIUXIANGBING_SKILL: Script = preload("res://game_data/skills/liuxiangbing.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "march_7th",
		"display_name": "三月七",
		"gender": "female",
		"faction": "xingqionglieche",
		"max_hp": 3,
		"description": "防御型样例武将，用于验证女性与三体力数据。",
	}, [LIUXIANGBING_SKILL])
