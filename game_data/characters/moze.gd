extends CharacterDefinition

## 【貊泽】武将源码。武将通过三个独立离场技能组件组合猎物标记、返场追击与回合窗口。

## 【幽锋】技能脚本；负责每轮转移猎物标记并令貊泽离场或失去体力。
const YOUFENG_SKILL: Script = preload("res://game_data/skills/youfeng.gd")

## 【掠袭】技能脚本；负责猎物距离、不可响应、受伤追击与死亡返场收益。
const LVEXI_SKILL: Script = preload("res://game_data/skills/lvexi.gd")

## 【影出】技能脚本；负责在有效上家回合结束后返场并于自身回合结束再次离场。
const YINGCHU_SKILL: Script = preload("res://game_data/skills/yingchu.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"moze",
		"display_name":"貊泽",
		"gender":"male",
		"faction":"xianzhou",
		"max_hp":2,
		"description":"以离场潜伏和猎物标记锁定目标，在伤害窗口返场完成追击。",
	}, [YOUFENG_SKILL, LVEXI_SKILL, YINGCHU_SKILL])
