extends CharacterDefinition

## 【米沙】武将源码。武将通过独立技能组件配置【幻影】与【传冲】。

## 【幻影】技能脚本；负责回合外受伤后的临时离场与回合结束返回。
const HUANYING_SKILL: Script = preload("res://game_data/skills/huanying.gd")

## 【传冲】技能脚本；负责四种花色手牌到指定锦囊牌的一一转化。
const CHUANCHONG_SKILL: Script = preload("res://game_data/skills/chuanchong.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"misha",
		"display_name":"米沙",
		"gender":"male",
		"faction":"pinuokangni",
		"max_hp":3,
		"description":"以临时离场规避后续影响，并按花色转化锦囊牌。",
	}, [HUANYING_SKILL, CHUANCHONG_SKILL])
