extends CharacterDefinition

## 【玲可】武将源码。武将通过独立技能组件组合【勘测】与【求生】。

## 【勘测】技能脚本；每名玲可持有者独立记录各出牌阶段的发动次数。
const KANCE_SKILL: Script = preload("res://game_data/skills/kance.gd")

## 【求生】技能脚本；锁定技在濒死Begin时机检查并处理当前全部手牌。
const QIUSHENG_SKILL: Script = preload("res://game_data/skills/qiusheng.gd")


## 写入玲可的阵营、性别、体力与技能组件引用。
func _init() -> void:
	super({
		"id":"lingke",
		"display_name":"玲可",
		"gender":"female",
		"faction":"beiluoboge",
		"max_hp":3,
		"description":"贝洛伯格的雪原探险家，善于勘测情报、寻找补给并在绝境中求生。",
	}, [KANCE_SKILL, QIUSHENG_SKILL])
