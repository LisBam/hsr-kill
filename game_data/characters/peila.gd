extends CharacterDefinition

## 【佩拉】武将源码。武将通过独立技能组件组合【追歼】与【秘策】。

## 【追歼】技能脚本；每名佩拉持有者独立维护目标、伤害事件预留与左上角提示来源。
const ZHUIJIAN_SKILL: Script = preload("res://game_data/skills/zhuijian.gd")

## 【秘策】技能脚本；额外阶段完成顺序由技能上下文与控制器通用阶段端口协作维护。
const MICE_SKILL: Script = preload("res://game_data/skills/mice.gd")


## 写入佩拉的阵营、性别、体力与技能组件引用。
func _init() -> void:
	super({
		"id":"peila",
		"display_name":"佩拉",
		"gender":"female",
		"faction":"beiluoboge",
		"max_hp":3,
		"description":"贝洛伯格的情报官，能够锁定属性伤害目标，并在回合尾声调度额外阶段。",
	}, [ZHUIJIAN_SKILL, MICE_SKILL])
