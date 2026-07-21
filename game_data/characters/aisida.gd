extends CharacterDefinition

## 【艾丝妲】武将源码。武将通过独立技能组件配置【星祈】与【星落】。

## 【星祈】技能脚本；负责观看、分配锦囊与牌堆顶底排序。
const XINGQI_SKILL: Script = preload("res://game_data/skills/xingqi.gd")

## 【星落】技能脚本；负责多角色依次重铸与共同属性奖励。
const XINGLUO_SKILL: Script = preload("res://game_data/skills/xingluo.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"aisida",
		"display_name":"艾丝妲",
		"gender":"female",
		"faction":"yinhexvezhe",
		"max_hp":3,
		"description":"通过牌堆观星和多人重铸调度手牌质量。",
	}, [XINGQI_SKILL, XINGLUO_SKILL])
