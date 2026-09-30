extends CharacterDefinition

## 【刃】武将源码。星核猎手角色，用【万死】把濒死边缘兑换成主演身份与额外回合，
## 并以【支离】把每一次【杀】改写成对相邻角色的范围打击。

## 【万死】技能脚本；受到伤害后体力恰为1时可于本回合结束后成为主演并执行额外回合。
const WANSI_SKILL: Script = preload("res://game_data/skills/wansi.gd")

## 【支离】技能脚本；锁定技，自己是自己使用【杀】的合法目标，且【杀】的唯一目标被改写为相邻角色。
const ZHILI_SKILL: Script = preload("res://game_data/skills/zhili.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"ren",
		"display_name":"刃",
		"gender":"male",
		"faction":"xinghelieshou",
		"max_hp":4,
		"description":"以【万死】在濒死边缘换取主演身份与额外回合，并用【支离】把【杀】扩散到目标的两侧相邻角色。",
	}, [WANSI_SKILL, ZHILI_SKILL])
