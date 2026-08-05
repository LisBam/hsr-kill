extends CharacterDefinition

## 【停云】武将源码。武将通过独立技能组件组合【祥音】的持续赐福与【光覆】的摸牌、限定技复原。

## 【祥音】技能脚本；负责给予赐福标记及每个全局回合首张【杀】无距离规则。
const XIANGYIN_SKILL: Script = preload("res://game_data/skills/xiangyin.gd")

## 【光覆】技能脚本；负责目标摸1张牌并在本回合结束时精确复原其一项已发动限定技。
const GUANGFU_SKILL: Script = preload("res://game_data/skills/guangfu.gd")


## 写入停云的稳定资料、仙舟联盟势力、女性性别、3点体力上限与技能组件顺序。
func _init() -> void:
	super({
		"id":"tingyun",
		"display_name":"停云",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":3,
		"description":"仙舟联盟的接渡使，以祥音赐福友方的首张【杀】，并借光覆令角色摸牌、复原已发动的限定技。",
	}, [XIANGYIN_SKILL, GUANGFU_SKILL])
