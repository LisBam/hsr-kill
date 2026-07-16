class_name SkillDefinition
extends RefCounted

## 武将技能源码定义基类。技能文件同时承载元数据、事件订阅与主动发动逻辑，不依赖集中技能注册表。

## 当前技能的完整静态元数据；由具体技能脚本构造并在数据库建立索引时读取。
var _metadata: Dictionary = {}

## 当前技能所属玩家 ID；未安装到对局时为 -1，安装后保持稳定 player_id。
var owner_player_id: int = -1

## 当前技能绑定的对局控制器端口；技能只能通过该端口请求规则操作，不直接修改界面节点。
var host: Object


## 保存技能元数据；元数据只在脚本构造时写入，运行时状态应使用独立成员变量保存。
func _init(metadata: Dictionary = {}) -> void:
	_metadata = metadata.duplicate(true)


## 返回技能元数据深拷贝，供武将引用校验、技能栏展示、网络与回放读取。
func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)


## 返回技能稳定 ID；同一技能脚本可被多个武将直接引用，但 ID 必须全项目唯一。
func get_id() -> String:
	return str(_metadata.get("id", ""))


## 绑定技能所属玩家与对局端口；数据库定义对象不会调用本函数，只有每局独立运行时实例会绑定。
func bind(match_host: Object, player_id: int) -> void:
	host = match_host
	owner_player_id = player_id


## 安装被动或触发技能；具体技能可在此订阅 host.event_bus 或 host.trigger_manager。
func install() -> void:
	pass


## 卸载技能持有的事件订阅；需要动态失去技能时应覆盖本函数并释放自身外部注册。
func uninstall() -> void:
	if host != null and host.get("event_bus") != null:
		host.event_bus.unsubscribe_owner(self)
	if host != null and host.get("trigger_manager") != null:
		host.trigger_manager.unsubscribe_owner(self)


## 判断主动技能当前是否可发动；context 只允许包含可序列化动作参数与只读选择结果。
func can_activate(_context: Dictionary = {}) -> bool:
	return false


## 执行主动技能；空字符串表示成功，非空字符串会作为统一动作拒绝原因返回。
func activate(_context: Dictionary = {}) -> String:
	return "该技能当前不可主动发动。"


## 恢复由本技能创建的普通选牌请求；返回 true 表示选择已识别并完成或进入下一段等待。
func continue_choice(_context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复由本技能创建的响应牌请求；response_card 为 null 表示响应者明确放弃。
func continue_response(_context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 向基础 AI 的出牌阶段合法动作列表追加技能动作；动作必须使用 action_type=use_skill 并携带稳定 skill_id。
func append_play_phase_actions(_result: Array[Dictionary]) -> void:
	pass


## 返回主动技能的只读交互预览；不得在本函数中消耗资源、创建选择或修改对局状态。
func get_activation_preview(_context: Dictionary = {}) -> Dictionary:
	return {}
