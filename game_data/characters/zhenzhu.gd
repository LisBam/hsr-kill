extends CharacterDefinition

## 【真珠】武将源码。星际和平公司角色，通过欢愉技【补缀】在阿哈时刻为多名角色补上临时护盾，
## 并以主动技【鉴映】把自己的低价值手牌连花色点数一起视为另一张牌使用。

## 【补缀】技能脚本；欢愉技，阿哈时刻按参演编号104驱动，护盾在持有者的下一个回合结束时各失去1点。
const BUZHUI_SKILL: Script = preload("res://game_data/skills/buzhui.gd")

## 【鉴映】技能脚本；出牌阶段限一次的展示与视为复制。
const JIANYING_SKILL: Script = preload("res://game_data/skills/jianying.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"zhenzhu",
		"display_name":"真珠",
		"gender":"female",
		"faction":"xingjihepinggongsi",
		"max_hp":3,
		"description":"以临时护盾补缀全队，并把低价值手牌鉴映为高价值牌的星际和平公司干员。",
	}, [BUZHUI_SKILL, JIANYING_SKILL])
