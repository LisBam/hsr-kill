extends CharacterDefinition

## 砂金武将静态资料。固有技能顺序决定技能栏展示顺序与【筹码】的开局结算顺序。

## 【筹码】锁定技组件；游戏开始时按持有者体力上限摸牌并提升手牌上限。
const CHOUMA_SKILL: Script = preload("res://game_data/skills/chouma.gd")
## 【盲注】组件；摸牌阶段开始时弃置颜色不同的牌，按与阶段内获得的牌的颜色重合数结算。
const MANGZHU_SKILL: Script = preload("res://game_data/skills/mangzhu.gd")
## 【风口】组件；批量获得后可选弃置整批牌积累次数，出牌阶段按该次数连续获得他人随机手牌后失去本技能。
const FENGKOU_SKILL: Script = preload("res://game_data/skills/fengkou.gd")


func _init() -> void:
	super({
		"id": "shajin",
		"display_name": "砂金",
		"gender": "male",
		"faction": "xingjihepinggongsi",
		"max_hp": 3,
		"description": "以筹码开局铺开手牌，借盲注与风口把每一次批量获得都换成下一次的主动权。",
	}, [CHOUMA_SKILL, MANGZHU_SKILL, FENGKOU_SKILL])
