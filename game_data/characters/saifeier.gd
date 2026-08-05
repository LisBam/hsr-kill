extends CharacterDefinition

## 【赛飞儿】武将源码。武将通过独立技能组件组合【聚寇】轮回积累“币”与【换日】消耗标记造成伤害。

## 【聚寇】技能脚本；负责回合首次伤害询问、轮回节执行与“币”手牌上限联动。
const JVKOU_SKILL: Script = preload("res://game_data/skills/jvkou.gd")

## 【换日】技能脚本；负责每出牌阶段一次移除全部“币”并造成等量伤害。
const HUANRI_SKILL: Script = preload("res://game_data/skills/huanri.gd")


## 写入赛飞儿的稳定资料、3点体力上限与技能组件顺序。
func _init() -> void:
	super({
		"id":"saifeier",
		"display_name":"赛飞儿",
		"gender":"female",
		"faction":"wengfaluosi",
		"max_hp":3,
		"description":"翁法罗斯的盗贼，以聚寇轮回积累“币”，再通过换日将全部“币”转化为伤害。",
	}, [JVKOU_SKILL, HUANRI_SKILL])
