extends CharacterDefinition

## 【布洛妮娅】武将源码。武将通过独立技能组件配置【行军】、【军势】与领袖技【振旗】。

## 【行军】技能脚本；负责跳过出牌阶段并在回合结束时安排额外回合。
const XINGJUN_SKILL: Script = preload("res://game_data/skills/xingjun.gd")

## 【军势】技能脚本；负责每个出牌阶段首次【杀】指定目标后的可选摸牌。
const JUNSHI_SKILL: Script = preload("res://game_data/skills/junshi.gd")

## 【振旗】领袖技脚本；仅在布洛妮娅身份为领袖时安装并显示，负责贝洛伯格角色的配对费用与支援效果。
const ZHENQI_SKILL: Script = preload("res://game_data/skills/zhenqi.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "bronya",
		"display_name": "布洛妮娅",
		"gender": "female",
		"faction": "beiluoboge",
		"max_hp": 3,
		"description": "以阶段调度与协同进攻支援其他角色。",
	}, [XINGJUN_SKILL, JUNSHI_SKILL, ZHENQI_SKILL])
