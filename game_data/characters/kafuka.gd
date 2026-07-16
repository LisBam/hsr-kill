extends CharacterDefinition

## 【卡芙卡】武将源码。武将通过脚本资源直接配置【言灵】。

## 【言灵】技能脚本；响应逻辑应通过统一规则事件和选择请求实现。
const YANLING_SKILL: Script = preload("res://game_data/skills/yanling.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "kafka",
		"display_name": "卡芙卡",
		"gender": "female",
		"faction": "stellaron_hunter",
		"max_hp": 3,
		"description": "响应效果样例武将，仅提供扩展结构。",
	}, [YANLING_SKILL])
