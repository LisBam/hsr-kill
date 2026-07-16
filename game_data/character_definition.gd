class_name CharacterDefinition
extends RefCounted

## 武将源码定义基类。具体武将直接引用技能脚本，数据库只从目录自动发现武将并生成只读索引。

## 当前武将除技能外的完整静态元数据；运行时通过深拷贝向界面和规则层提供。
var _metadata: Dictionary = {}

## 当前武将直接配置的技能脚本数组；数组成员必须来自 res://game_data/skills 目录。
var _skill_scripts: Array[Script] = []


## 保存武将信息与技能脚本引用；技能 ID 会从脚本自身读取，武将文件无需重复维护字符串列表。
func _init(metadata: Dictionary = {}, skill_scripts: Array[Script] = []) -> void:
	_metadata = metadata.duplicate(true)
	_skill_scripts.assign(skill_scripts)


## 返回武将元数据深拷贝，并把直接引用的技能脚本转换为稳定技能 ID 数组供运行时序列化。
func get_metadata() -> Dictionary:
	# 武将对外元数据；在副本中补充技能 ID，避免调用方取得可执行脚本资源。
	var result: Dictionary = _metadata.duplicate(true)
	# 当前武将技能 ID 数组；顺序与武将文件内配置顺序一致，也决定技能栏展示顺序。
	var skill_ids: Array[String] = []
	for skill_script: Script in _skill_scripts:
		if skill_script == null:
			continue
		# 当前技能定义临时实例；只读取稳定 ID，不绑定玩家或安装事件。
		var skill_definition: SkillDefinition = skill_script.new() as SkillDefinition
		if skill_definition != null and not skill_definition.get_id().is_empty():
			skill_ids.append(skill_definition.get_id())
	result["skills"] = skill_ids
	return result


## 返回武将稳定 ID；该值必须在 game_data/characters 全目录中唯一。
func get_id() -> String:
	return str(_metadata.get("id", ""))


## 返回武将直接引用的技能脚本副本，供数据库校验引用确实来自已登记技能代码。
func get_skill_scripts() -> Array[Script]:
	return _skill_scripts.duplicate()
