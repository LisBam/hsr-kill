extends CharacterDefinition

## 【青雀】武将源码。武将通过三个独立技能组件组合“锁手牌的自闭过牌”与“无实体牌的视为使用”：
## 【独弈】与【弃和】是锁定技，分别限制自身用牌方式与抵消来袭伤害牌；
## 【自摸】是主动技，用手牌花色数决定“摸牌视为使用”或“弃一色换两次发动”两条分支。

## 【独弈】技能脚本；负责手牌基本牌与锦囊牌的使用/打出限制、弃牌阶段的随机保留与阶段跳过。
const DUYI_SKILL: Script = preload("res://game_data/skills/duyi.gd")

## 【弃和】技能脚本；负责成为伤害牌目标时的同花色随机弃牌与令牌无效。
const QIHE_SKILL: Script = preload("res://game_data/skills/qihe.gd")

## 【自摸】技能脚本；负责出牌阶段的虚拟手牌选牌、视为使用与出牌阶段限次改写。
const ZIMO_SKILL: Script = preload("res://game_data/skills/zimo.gd")


## 写入青雀的稳定资料与技能组件顺序；技能数组顺序同时决定技能栏展示顺序。
func _init() -> void:
	super({
		"id":"qingque",
		"display_name":"青雀",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":3,
		"description":"仙舟联盟的摸鱼棋手，只与自己对弈：既不碰手牌中的基本牌与锦囊牌，也总能从对手的杀招里舍掉一张以自保。",
	}, [DUYI_SKILL, QIHE_SKILL, ZIMO_SKILL])
