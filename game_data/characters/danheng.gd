extends CharacterDefinition

## 【丹恒】武将源码。武将通过脚本资源直接配置【击云】。

## 【击云】技能脚本；新增或调整技能时不需要修改武将数据库加载器。
const JIYUN_SKILL: Script = preload("res://game_data/skills/jiyun.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "dan_heng",
		"display_name": "丹恒",
		"gender": "male",
		"faction": "astral_express",
		"max_hp": 4,
		"description": "攻击型样例武将，用于验证男性与四体力数据。",
	}, [JIYUN_SKILL])
