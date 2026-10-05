extends CharacterDefinition

## 【银枝】武将源码。星间寰宇角色，靠【巡礼】在任意角色的回合开始时插入额外的摸牌、出牌与弃牌阶段，
## 并把自己的武将牌永久锁在背面；【礼节】则把一次性获得的牌与他人给予的回复回赠给同行者。

## 【巡礼】技能脚本；半锁定技，锁定后段令武将牌始终背面向上。
const XUNLI_SKILL: Script = preload("res://game_data/skills/xunli.gd")

## 【礼节】技能脚本；批量获得与受他人回复后的两段可选回赠。
const LIJIE_SKILL: Script = preload("res://game_data/skills/lijie.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"yinzhi",
		"display_name":"银枝",
		"gender":"male",
		"faction":"xingjianhuanyv",
		"max_hp":4,
		"description":"永远背对众人的寰宇骑士，在他人回合开始时以巡礼插入三段额外阶段，并以礼节回赠同行者。",
	}, [XUNLI_SKILL, LIJIE_SKILL])
