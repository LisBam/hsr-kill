extends CharacterDefinition

## 【卡厄斯兰那】特殊武将源码。该武将不会进入普通选将或随机池，只能由白厄的【轮回】显式替换出现。

## 【天裁】技能脚本；负责三段火焰自伤与连续【火攻】轮回。
const TIANCAI_SKILL: Script = preload("res://game_data/skills/tiancai.gd")

## 【弑魂】技能脚本；负责令其他角色使用火【杀】及固定目标反击轮回。
const SHIHUN_SKILL: Script = preload("res://game_data/skills/shihun.gd")

## 【永劫】技能脚本；负责非伤害牌火【杀】转化、其他轮回技永劫状态与返生白厄。
const YONGJIE_SKILL: Script = preload("res://game_data/skills/yongjie.gd")


## 写入卡厄斯兰那的稳定资料、5点体力上限、特殊武将标记与技能组件顺序。
func _init() -> void:
	super({
		"id":"kaesilanna",
		"display_name":"卡厄斯兰那",
		"gender":"male",
		"faction":"wengfaluosi",
		"max_hp":5,
		"special":true,
		"description":"由白厄觉醒进入的特殊武将形态，以天裁、弑魂与永劫操纵火焰轮回并最终返生。",
	}, [TIANCAI_SKILL, SHIHUN_SKILL, YONGJIE_SKILL])
