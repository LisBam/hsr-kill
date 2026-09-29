extends CharacterDefinition

## 【爻光】武将源码。仙舟联盟角色，以欢愉技【凶星】为集火目标叠层，并用【鸿运】追加一次额外的阿哈时刻。

## 【凶星】技能脚本；欢愉技，阿哈时刻按参演编号116驱动。
const XIONGXING_SKILL: Script = preload("res://game_data/skills/xiongxing.gd")

## 【鸿运】技能脚本；回合开始前可支付1点体力上限追加一次额外阿哈时刻，每轮限一次。
const HONGYUN_SKILL: Script = preload("res://game_data/skills/hongyun.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"yaoguang",
		"display_name":"爻光",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":3,
		"description":"以欢愉技为集火目标叠加增伤，并用额外的阿哈时刻换取体力上限代价。",
	}, [XIONGXING_SKILL, HONGYUN_SKILL])
