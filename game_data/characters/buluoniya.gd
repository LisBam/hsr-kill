extends CharacterDefinition

## 【布洛妮娅】武将源码。武将通过脚本资源直接配置【作战再部署】。

## 【作战再部署】技能脚本；主动技能入口与规则逻辑均由对应文件提供。
const ZUOZHANZAIBUSHU_SKILL: Script = preload("res://game_data/skills/zuozhanzaibushu.gd")


## 写入武将静态信息与技能代码引用。
func _init() -> void:
	super({
		"id": "bronya",
		"display_name": "布洛妮娅",
		"gender": "female",
		"faction": "beiluoboge",
		"max_hp": 3,
		"description": "辅助效果样例武将，仅提供扩展结构。",
	}, [ZUOZHANZAIBUSHU_SKILL])
