extends CharacterDefinition

## 【驭空】武将源码。武将通过独立技能组件组合【鸣弦】的团队供牌与【逐风】的永久距离成长。

## 【鸣弦】技能脚本；负责为距离1以内的任意名角色检索并标记【杀】。
const MINGXIAN_SKILL: Script = preload("res://game_data/skills/mingxian.gd")

## 【逐风】技能脚本；负责伤害后永久减少距离并在全体距离为1时改为摸牌。
const ZHUFENG_SKILL: Script = preload("res://game_data/skills/zhufeng.gd")


## 写入驭空静态信息与技能组件引用；稳定ID严格使用主公指定的yvkong。
func _init() -> void:
	super({
		"id":"yvkong",
		"display_name":"驭空",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":4,
		"description":"仙舟联盟的飞行士，以鸣弦为友军供给无距离【杀】，并在战斗中逐步拉近与全场角色的距离。",
	}, [MINGXIAN_SKILL, ZHUFENG_SKILL])
