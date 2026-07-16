extends SkillDefinition

## 【六相冰】技能源码。当前作为防御类技能扩展样例，不修改任何规则数值。


## 写入技能静态信息；实际事件订阅与效果应继续维护在本文件中。
func _init() -> void:
	super({
		"id": "six_phased_ice_sample",
		"name": "六相冰",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
