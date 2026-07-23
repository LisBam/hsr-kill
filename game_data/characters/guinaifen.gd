extends CharacterDefinition

## 【桂乃芬】武将源码。武将通过独立技能组件组合【戏法】牌堆控制与【投狭】回合弃牌回收。

## 【戏法】技能脚本；负责所有判定前的观看、双行牌堆排序与阵营化 AI 改判定。
const XIFA_SKILL: Script = preload("res://game_data/skills/xifa.gd")

## 【投狭】技能脚本；负责每轮一次判定、回合出牌阶段弃牌筛选、获得与当前回合角色摸牌。
const TOUXIA_SKILL: Script = preload("res://game_data/skills/touxia.gd")


## 写入桂乃芬的稳定资料与技能组件顺序。
func _init() -> void:
	super({
		"id":"guinaifen",
		"display_name":"桂乃芬",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":3,
		"description":"仙舟联盟的街头艺人，以戏法操控判定，并借投狭回收回合内进入弃牌堆的同花色牌。",
	}, [XIFA_SKILL, TOUXIA_SKILL])
