extends CharacterDefinition

## 【卡芙卡】武将源码。星核猎手角色，以【言灵】把五张专属锦囊牌洗入牌堆，
## 并在任意角色使用延时锦囊牌时摸牌、成为「主演」；以【游丝】秘密置牌，
## 在目标回合结束时兑现“观看并获得其一张牌”。

## 【言灵】技能脚本；锁定技，开局洗入五张专属牌，任意角色使用延时锦囊时摸一张牌并成为主演。
const YANLING_SKILL: Script = preload("res://game_data/skills/yanling.gd")

## 【游丝】技能脚本；其他角色回合开始时秘密置牌，本回合结束时观看并获得其一张牌。
const YOUSI_SKILL: Script = preload("res://game_data/skills/yousi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"kafuka",
		"display_name":"卡芙卡",
		"gender":"female",
		"faction":"xinghelieshou",
		"max_hp":3,
		"description":"以【言灵】在开局把五张专属锦囊洗入牌堆，并在任意角色使用延时锦囊时摸牌、成为“主演”；以【游丝】秘密置牌，在目标回合结束时观看并获得其一张牌。",
	}, [YANLING_SKILL, YOUSI_SKILL])
