extends CharacterDefinition

## 【火花】武将源码。欢愉派系角色，通过阿哈时刻驱动欢愉技【好戏】，并以主动技能【连戏】换取伤害。

## 【好戏】技能脚本；欢愉技，阿哈时刻按参演编号144驱动。
const HAOXI_SKILL: Script = preload("res://game_data/skills/haoxi.gd")

## 【连戏】技能脚本；出牌阶段限一次的多张重铸与结束伤害。
const LIANXI_SKILL: Script = preload("res://game_data/skills/lianxi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"huohua",
		"display_name":"火花",
		"gender":"female",
		"faction":"huanyu",
		"max_hp":3,
		"description":"以阿哈时刻驱动的欢愉技扰乱敌人，并用一次性多张重铸换取伤害。",
	}, [HAOXI_SKILL, LIANXI_SKILL])
