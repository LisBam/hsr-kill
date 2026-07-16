extends CharacterDefinition

## 【开拓者】武将源码。武将通过脚本资源直接配置【开拓】，无需在数据库维护技能 ID 列表。

## 【开拓】技能脚本；运行时会为选择该武将的玩家创建独立技能实例。
const KAITUO_SKILL: Script = preload("res://game_data/skills/kaituo.gd")


## 写入武将名称、性别、势力、体力上限、说明与直接引用的技能代码。
func _init() -> void:
	super({
		"id": "trailblazer",
		"display_name": "开拓者",
		"gender": "unknown",
		"faction": "astral_express",
		"max_hp": 4,
		"description": "通用样例武将，用于验证武将数据、体力与技能接口。",
	}, [KAITUO_SKILL])
