extends CharacterDefinition

## 【希露瓦】武将源码。武将通过独立技能组件配置【弦奏】与【安可】。

## 【弦奏】技能脚本；负责主要阶段重铸、跳过与弃牌阶段手牌调整。
const XIANZOU_SKILL: Script = preload("res://game_data/skills/xianzou.gd")

## 【安可】技能脚本；负责四花色弃牌统计与每轮至多三次额外回合。
const ANKE_SKILL: Script = preload("res://game_data/skills/anke.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"xiluwa",
		"display_name":"希露瓦",
		"gender":"female",
		"faction":"beiluoboge",
		"max_hp":3,
		"description":"通过四花色重铸跳过阶段，并以弃牌花色换取额外回合。",
	}, [XIANZOU_SKILL, ANKE_SKILL])
