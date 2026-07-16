extends SkillDefinition

## 【作战再部署】技能源码。当前作为辅助类主动技能扩展样例，不执行任何动作。


## 写入技能静态信息；需要按钮发动时可设置 ui_enabled 并覆盖 can_activate 与 activate。
func _init() -> void:
	super({
		"id": "command_sample",
		"name": "作战再部署",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
