extends CharacterDefinition

## 【刻律德菈】武将源码。武将通过【升变】分配军功与动态【奇袭】，并以【堪杀】在三段轮回中支付颜色牌或造成伤害。

## 【升变】技能脚本；负责军功重置、增长、奇袭赋予与轮回数上限。
const SHENGBIAN_SKILL: Script = preload("res://game_data/skills/shengbian.gd")

## 【堪杀】技能脚本；负责三轮回节费用、伤害与每节阶段限次。
const KANSHA_SKILL: Script = preload("res://game_data/skills/kansha.gd")


## 写入刻律德菈的稳定资料、3点体力上限与技能组件顺序。
func _init() -> void:
	super({
		"id":"kelvdela",
		"display_name":"刻律德菈",
		"gender":"female",
		"faction":"wengfaluosi",
		"max_hp":3,
		"description":"翁法罗斯的统御者，以升变授予军功与奇袭，并通过堪杀轮转红黑费用与伤害。",
	}, [SHENGBIAN_SKILL, KANSHA_SKILL])
