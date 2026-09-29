extends CharacterDefinition

## 【星】武将源码。欢愉派系角色，以【咬它】强制驱动他人的欢愉技，并用【好活】拆解场上装备与延时锦囊。

## 【咬它】技能脚本；与穹共用的普通技能，每种花色整局限一次。
const YAOTA_SKILL: Script = preload("res://game_data/skills/yaota.gd")

## 【好活】技能脚本；欢愉技，阿哈时刻按参演编号120驱动。
const HAOHUO_SKILL: Script = preload("res://game_data/skills/haohuo.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"xing_huanyv",
		"display_name":"星",
		"gender":"female",
		"faction":"huanyu",
		"max_hp":4,
		"description":"以弃置花色手牌驱动同伴的欢愉技，并用欢愉技拆除场上的装备与延时锦囊。",
	}, [YAOTA_SKILL, HAOHUO_SKILL])
