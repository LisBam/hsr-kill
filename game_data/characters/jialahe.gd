extends CharacterDefinition

## 【加拉赫】武将源码。武将通过独立技能组件组合【亲酿】与【酩酊】。

## 【亲酿】技能脚本；负责黑色牌交付与持续到接收者下个回合结束的【酒】视为效果。
const QINNIANG_SKILL: Script = preload("res://game_data/skills/qinniang.gd")

## 【酩酊】技能脚本；负责限定翻面、虚拟【杀】与逐点伤害回复持续效果。
const MINGDING_SKILL: Script = preload("res://game_data/skills/mingding.gd")


## 写入武将静态信息与技能组件引用；稳定ID按设计要求使用jialahe。
func _init() -> void:
	super({
		"id":"jialahe",
		"display_name":"加拉赫",
		"gender":"male",
		"faction":"pinuokangni",
		"max_hp":4,
		"description":"匹诺康尼的调饮师，能将黑色牌酿成美酒，并以翻面代价建立围绕目标的持续治疗攻势。",
	}, [QINNIANG_SKILL, MINGDING_SKILL])
