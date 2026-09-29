extends CharacterDefinition

## 【穹】武将源码。欢愉派系角色，以【咬它】强制驱动他人的欢愉技，并用【当赏】为队友补充手牌。

## 【咬它】技能脚本；与星共用的普通技能，每种花色整局限一次。
const YAOTA_SKILL: Script = preload("res://game_data/skills/yaota.gd")

## 【当赏】技能脚本；欢愉技，阿哈时刻按参演编号120驱动。
const DANGSHANG_SKILL: Script = preload("res://game_data/skills/dangshang.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"qiong_huanyv",
		"display_name":"穹",
		"gender":"male",
		"faction":"huanyu",
		"max_hp":4,
		"description":"以弃置花色手牌驱动同伴的欢愉技，并用欢愉技为队友补充手牌。",
	}, [YAOTA_SKILL, DANGSHANG_SKILL])
