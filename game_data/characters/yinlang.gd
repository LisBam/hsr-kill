extends CharacterDefinition

## 【银狼】武将源码。星核猎手势力，体力值 3，通过【注入】组合出【进程】/【缺陷】，通过【以太】造牌。
##
## 【设计定位】银狼本身没有固定牌效：她的强度来自「按对局形势现场组合技能」。
## 【注入】每轮准备阶段都能再组合一份，因此同一个角色会累积多个同名组合技能（依赖技能实例键底座）；
## 【以太】是限定技，一次对局只造一张牌，并在任意角色回合结束时把自己推上「主演」并把该牌洗回牌堆。

## 【注入】技能脚本；负责开局与每轮准备阶段的组合选择。
const ZHURU_SKILL: Script = preload("res://game_data/skills/zhuru.gd")

## 【以太】技能脚本；负责限定技造牌与回合结束时的牌堆回流。
const YITAI_SKILL: Script = preload("res://game_data/skills/yitai.gd")


## 写入武将静态信息与技能代码引用；技能顺序即技能栏展示顺序，不得调整。
func _init() -> void:
	super({
		"id": "yinlang",
		"display_name": "银狼",
		"gender": "female",
		"faction": "xinghelieshou",
		"max_hp": 3,
		"description": "以现场组合技能与创造专属卡牌掌控节奏的星核猎手。",
	}, [ZHURU_SKILL, YITAI_SKILL])
