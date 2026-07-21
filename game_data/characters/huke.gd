extends CharacterDefinition

## 【虎克】武将源码。武将通过独立技能组件配置【无邪】与【飞焰】。

## 【无邪】技能脚本；负责伤害成立后为受到伤害的角色回复体力。
const WUXIE_SKILL: Script = preload("res://game_data/skills/wuxie_2.gd")

## 【飞焰】技能脚本；负责准备阶段虚拟使用火攻与替换本回合主要阶段。
const FEIYAN_SKILL: Script = preload("res://game_data/skills/feiyan.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"huke",
		"display_name":"虎克",
		"gender":"female",
		"faction":"beiluoboge",
		"max_hp":3,
		"description":"以火焰伤害创造连续出牌机会，并为自己与队友修复伤势。",
	}, [WUXIE_SKILL, FEIYAN_SKILL])
