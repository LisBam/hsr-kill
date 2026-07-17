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


## 返回指定玩家的技能角色操作对象；护盾、失去体力和造成伤害语法均通过该对象进入权威控制器。
func get_skill_player(player_id: int) -> SkillPlayer:
	return SkillPlayer.new(host, player_id, get_id())


## 返回技能持有者的角色操作对象；适合把持有者作为护盾来源、体力流失来源或伤害来源。
func get_owner_skill_player() -> SkillPlayer:
	return get_skill_player(owner_player_id)


## 返回技能声明的主动发动入口；旧的 ui_enabled 主动技能未配置 enable 时默认只允许 phaseUse。
func get_active_entries() -> Array[String]:
	# 标准主动入口结果；只保留目录登记名称并去重，避免错误元数据进入选择协议。
	var result: Array[String] = []
	# 元数据中的 enable 字段；允许单个字符串或字符串数组，便于简单与复合主动技能共用。
	var configured_entries: Variant = _metadata.get("enable", [])
	if configured_entries is String:
		var configured_entry: String = str(configured_entries)
		if RuleTimingCatalog.has_active_entry(configured_entry):
			result.append(configured_entry)
	elif configured_entries is Array:
		for entry_variant: Variant in configured_entries as Array:
			# 当前主动入口；无效值直接忽略并由数据库或内容测试报告元数据问题。
			var entry_name: String = str(entry_variant)
			if RuleTimingCatalog.has_active_entry(entry_name) and not result.has(entry_name):
				result.append(entry_name)
	if result.is_empty() and bool(_metadata.get("ui_enabled", false)):
		result.append("phaseUse")
	return result


## 返回技能是否允许在指定主动入口发动；被动技能和 sample_only 技能默认不支持任何入口。
func supports_active_entry(entry_name: String) -> bool:
	return get_active_entries().has(entry_name)


## 以技能持有者身份注册标准时机；role 决定匹配 player、source、target 或 global，成功返回稳定注册 ID。
func subscribe_timing(event_name: String, callback: Callable, role: String = "player", priority: int = 0, first_do: bool = false, last_do: bool = false, condition: Callable = Callable()) -> int:
	if host == null or host.get("trigger_manager") == null or not RuleTimingCatalog.has_timing(event_name):
		return -1
	# 当前对局高级触发器；由技能基类统一传入 self 与 owner_player_id，具体技能无需复制解绑字段。
	var manager: TriggerManager = host.get("trigger_manager") as TriggerManager
	return manager.subscribe(event_name, self, callback, priority, owner_player_id, role, first_do, last_do, condition)


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


## 恢复由本技能创建的通用选择请求；默认兼容旧 continue_choice，需同时读取目标的技能可覆盖本函数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	return continue_choice(context, response.card_ids)


## 恢复由本技能创建的响应牌请求；response_card 为 null 表示响应者明确放弃。
func continue_response(_context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 向基础 AI 的出牌阶段合法动作列表追加技能动作；动作必须使用 action_type=use_skill 并携带稳定 skill_id。
func append_play_phase_actions(_result: Array[Dictionary]) -> void:
	pass


## 返回主动技能的只读交互预览；不得在本函数中消耗资源、创建选择或修改对局状态。
func get_activation_preview(_context: Dictionary = {}) -> Dictionary:
	return {}


## 为技能持有者创建统一选牌请求；候选必须是可序列化牌面快照，恢复上下文会自动绑定技能 ID 与持有者。
func request_card_selection(title: String, prompt: String, candidates: Array[Dictionary], min_select: int, max_select: int, allow_cancel: bool, context: Dictionary = {}) -> Array[int]:
	if host == null or not host.has_method("request_card_choice"):
		return []
	# 技能恢复上下文；稳定技能 ID 与持有者 ID 由基类统一写入，具体技能只保存自身步骤参数。
	var skill_context: Dictionary = _build_selection_context(context)
	return host.call("request_card_choice", owner_player_id, title, prompt, candidates, min_select, max_select, allow_cancel, skill_context) as Array[int]


## 为技能持有者创建统一选目标请求；目标 ID 只来自权威规则查询，UI、AI 与网络提交同一种 ChoiceResponse。
func request_target_selection(prompt: String, target_ids: Array[int], min_select: int = 1, max_select: int = 1, allow_cancel: bool = true, context: Dictionary = {}) -> Array[int]:
	if host == null or not host.has_method("request_target_choice"):
		return []
	# 技能恢复上下文；选择种类仍由控制器写入请求，不要求技能脚本直接构造运行时对象。
	var skill_context: Dictionary = _build_selection_context(context)
	return host.call("request_target_choice", owner_player_id, prompt, target_ids, min_select, max_select, allow_cancel, skill_context) as Array[int]


## 为技能持有者创建同时选牌和选目标的请求；牌与目标数量分别配置，适合“弃一张牌并选择一名角色”等技能。
func request_card_target_selection(title: String, prompt: String, candidates: Array[Dictionary], target_ids: Array[int], min_cards: int, max_cards: int, min_targets: int, max_targets: int, allow_cancel: bool, context: Dictionary = {}) -> Dictionary:
	if host == null or not host.has_method("request_card_target_choice"):
		return {}
	# 技能恢复上下文；可在 context.target_ids_by_card_id 中提供实体牌到合法目标的组合映射。
	var skill_context: Dictionary = _build_selection_context(context)
	return host.call("request_card_target_choice", owner_player_id, title, prompt, candidates, target_ids, min_cards, max_cards, min_targets, max_targets, allow_cancel, skill_context) as Dictionary


## 构建技能选择恢复上下文；调用方同名字段不能覆盖稳定技能归属，避免响应被错误技能消费。
func _build_selection_context(context: Dictionary) -> Dictionary:
	# 可写上下文副本；仅保存可序列化值，不传递技能对象或 Callable。
	var result: Dictionary = context.duplicate(true)
	result["skill_id"] = get_id()
	result["skill_owner_id"] = owner_player_id
	return result
