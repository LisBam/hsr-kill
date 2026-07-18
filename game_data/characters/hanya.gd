extends CharacterDefinition

## 【寒鸦】武将源码。武将通过独立技能组件组合【冥谶】与【录事】。

## 【冥谶】技能脚本；锁定触发与目标选择由每名持有者独立结算。
const MINGCHEN_SKILL: Script = preload("res://game_data/skills/mingchen.gd")

## 【录事】技能脚本；主动弃牌组合与AI估值均封装在技能组件内。
const LUSHI_SKILL: Script = preload("res://game_data/skills/lushi.gd")


## 写入武将静态信息与技能组件引用。
func _init() -> void:
	super({
		"id": "hanya",
		"display_name": "寒鸦",
		"gender": "female",
		"faction": "xianzhou",
		"max_hp": 3,
		"description": "仙舟联盟的判官，以牌名字数整理资源，并在失去最后手牌时执行冥谶。",
	}, [MINGCHEN_SKILL, LUSHI_SKILL])
