extends SkillDefinition

## 【神君】技能源码。当前作为延迟触发类技能扩展样例，不创建额外单位或计时状态。


## 写入技能静态信息；延迟触发实现应通过事件订阅保存可序列化状态。
func _init() -> void:
	super({
		"id": "lightning_lord_sample",
		"name": "神君",
		"trigger": "sample_only",
		"ui_enabled": false,
		"description": "样例占位技能，不参与当前标准规则结算。",
	})
