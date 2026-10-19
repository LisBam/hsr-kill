extends ComposedSkillBase

## 【缺陷】技能源码。由【注入】组合而成的局内技能：时机与效果在获得时确定，正文随之生成。
##
## 本文件只负责声明静态身份与所属效果池，全部组合逻辑由 ComposedSkillBase 承担。
## 【为什么进程与缺陷分成两个文件】两者共享同一套时机池，但效果池完全不同（进程是收益，缺陷是代价）；
## 拆成两个技能ID 让「同一角色同时拥有进程与缺陷的多份实例」在技能栏、日志与存档里天然可区分，
## 也让 AI 与界面可以按技能ID 直接判断收益方向，不需要再读运行时配置。


## 写入锁定技静态信息；正文为通用模板，实际正文在获得时由 set_skill_display_description 按组合结果写入。
## 静态模板同样以「锁定技，」开头：SkillDefinition 依据该标签判定锁定语义，模板与元数据必须一致。
func _init() -> void:
	super({
		"id": "quexian",
		"name": "缺陷",
		"trigger": "",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，组合技能。本技能的时机与效果在获得时组合确定，正文以对局内显示为准。",
	})


## 返回所属效果池类别；组合底座据此读取缺陷效果池并校验配置。
func _pool_kind() -> String:
	return ZhuruComposePools.KIND_QUEXIAN
