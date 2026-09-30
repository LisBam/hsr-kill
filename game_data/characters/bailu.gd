extends CharacterDefinition

## 【白露】武将源码。仙舟联盟角色，以【悬壶】持续补充【桃】并用【生息】把用牌节奏兑换成永久额度。

## 【悬壶】技能脚本；锁定技，【桃】不计入手牌上限并在任意角色死亡后从句牌堆补一张【桃】。
const XUANHU_SKILL: Script = preload("res://game_data/skills/xuanhu.gd")

## 【生息】技能脚本；使用基本牌时二选一，摸一张牌或令本回合结束后永久累加X。
const SHENGXI_SKILL: Script = preload("res://game_data/skills/shengxi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"bailu",
		"display_name":"白露",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":3,
		"description":"以【悬壶】持续从牌堆补充【桃】，并用【生息】把每一次用牌兑换成永久累加的额度。",
	}, [XUANHU_SKILL, SHENGXI_SKILL])
