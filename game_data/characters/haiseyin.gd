extends CharacterDefinition

## 【海瑟音】武将源码。武将通过独立技能组件配置【泛音】与【回涛】。

## 【泛音】技能脚本；负责四轮回节的花色费用弃置与“一次弃置动作”的黑红整批判定。
const FANYIN_SKILL: Script = preload("res://game_data/skills/fanyin.gd")

## 【回涛】技能脚本；负责观察任意轮回技进入下一轮回并令其持有者摸牌。
const HUITAO_SKILL: Script = preload("res://game_data/skills/huitao.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id":"haiseyin",
		"display_name":"海瑟音",
		"gender":"female",
		"faction":"wengfaluosi",
		"max_hp":4,
		"description":"以四种花色的弃置推进轮回，并在每次弃置时按黑红组成换取削牌与补牌。",
	}, [FANYIN_SKILL, HUITAO_SKILL])
