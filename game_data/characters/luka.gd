extends CharacterDefinition

## 【卢卡】武将源码。武将通过独立技能组件组合【百折】与【制动】，两者共享公开“斗志”资源。

## 【百折】技能脚本；负责视为使用【决斗】与逐点伤害获得“斗志”。
const BAIZHE_SKILL: Script = preload("res://game_data/skills/baizhe.gd")

## 【制动】技能脚本；负责视为使用或打出【杀】与按直接响应数增加单目标牌伤害。
const ZHIDONG_SKILL: Script = preload("res://game_data/skills/zhidong.gd")


## 写入武将静态信息与技能组件引用；稳定ID按设计要求使用luka。
func _init() -> void:
	super({
		"id":"luka",
		"display_name":"卢卡",
		"gender":"male",
		"faction":"beiluoboge",
		"max_hp":4,
		"description":"贝洛伯格的地火拳手，在受伤与进攻中积累斗志，并将对手的响应转化为更强伤害。",
	}, [BAIZHE_SKILL, ZHIDONG_SKILL])
