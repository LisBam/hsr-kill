extends CharacterDefinition

## 【丹恒·腾荒】武将源码。武将通过独立技能组件配置【同袍】与【岳峙】。

## 【同袍】技能脚本；负责四节顺序推进的自伤、护盾与区域弃牌轮回流程。
const TONGPAO_SKILL: Script = preload("res://game_data/skills/tongpao.gd")

## 【岳峙】技能脚本；负责限定技接管多目标牌，并守卫该牌结算期间的伤害与回复。
const YUEZHI_SKILL: Script = preload("res://game_data/skills/yuezhi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "danheng_tenhuang",
		"display_name": "丹恒·腾荒",
		"gender": "male",
		"faction": "wengfaluosi",
		"max_hp": 4,
		"description": "以同袍的四节轮回换取护盾与压制，并以岳峙独担多目标牌的全部结算。",
	}, [TONGPAO_SKILL, YUEZHI_SKILL])
