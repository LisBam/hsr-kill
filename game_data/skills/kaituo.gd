extends SkillDefinition

## 【开拓】技能源码。当前作为规则扩展样例，不消耗资源，也不订阅任何对局事件。


## 写入技能名称、触发类型与永久说明；后续实现只需在本文件覆盖 install 或 activate。
func _init() -> void:
	super({
		"id": "trailblaze_sample",
		"name": "开拓",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
