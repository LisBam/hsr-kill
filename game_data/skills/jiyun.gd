extends SkillDefinition

## 【击云】技能源码。当前作为攻击类技能扩展样例，不修改卡牌或伤害结算。


## 写入技能静态信息；后续攻击触发可在 install 中订阅对应 RuleEvent。
func _init() -> void:
	super({
		"id": "cloud_piercer_sample",
		"name": "击云",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
