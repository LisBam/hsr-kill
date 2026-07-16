extends SkillDefinition

## 【轨道打击】技能源码。当前作为群体效果扩展样例，不订阅规则事件。


## 写入技能静态信息；群体规则实现应通过 host 的公开规则端口完成。
func _init() -> void:
	super({
		"id": "orbital_strike_sample",
		"name": "轨道打击",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
