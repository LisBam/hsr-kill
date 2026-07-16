extends SkillDefinition

## 【重力压制】技能源码。当前作为控制类技能扩展样例，不改变阶段或行动次数。


## 写入技能静态信息；控制效果实现时应在本文件订阅稳定规则事件。
func _init() -> void:
	super({
		"id": "gravity_sample",
		"name": "重力压制",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
