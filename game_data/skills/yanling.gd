extends SkillDefinition

## 【言灵】技能源码。当前作为响应类技能扩展样例，不拦截任何规则事件。


## 写入技能静态信息；响应规则实现时应使用统一选择请求而非直接读取界面节点。
func _init() -> void:
	super({
		"id": "spirit_whisper_sample",
		"name": "言灵",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
