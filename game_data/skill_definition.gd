class_name SkillDefinition
extends RefCounted

## 武将技能源码定义基类。技能文件同时承载元数据、事件订阅与主动发动逻辑，不依赖集中技能注册表。

## 当前技能的完整静态元数据；由具体技能脚本构造并在数据库建立索引时读取。
var _metadata: Dictionary = {}

## 当前技能所属玩家 ID；未安装到对局时为 -1，安装后保持稳定 player_id。
var owner_player_id: int = -1

## 当前技能绑定的对局控制器端口；技能只能通过该端口请求规则操作，不直接修改界面节点。
var host: Object

## 当前技能是否为锁定技；true 表示效果满足条件时强制执行且不创建发动选择，默认 false 表示非锁定技。
var lock: bool = false

## 当前技能是否为领袖技；true 表示只有身份为 leader 的角色实际拥有并显示该技能，默认 false 表示不限制身份。
var leader_skill: bool = false


## 保存技能元数据；元数据只在脚本构造时写入，运行时状态应使用独立成员变量保存。
func _init(metadata: Dictionary = {}) -> void:
	_metadata = metadata.duplicate(true)
	lock = bool(_metadata.get("lock", false))
	_metadata["lock"] = lock
	leader_skill = bool(_metadata.get("leader_skill", false))
	_metadata["leader_skill"] = leader_skill


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


## 上报一次已经确认成功的公开技能目标行为；ai_profile 使用卡牌 AI 的 target_result/expose 语义且不改变任何规则状态。
func observe_identity_behavior(target_ids: Array[int], ai_profile: Dictionary) -> void:
	if host == null or not host.has_method("observe_skill_identity_behavior"):
		return
	# 稳定目标副本；技能运行时不得在上报后继续修改身份模型收到的目标集合。
	var stable_target_ids: Array[int] = target_ids.duplicate()
	# 身份行为配置副本；目标收益与显式暴露值由当前技能源码负责声明。
	var stable_ai_profile: Dictionary = ai_profile.duplicate(true)
	host.call("observe_skill_identity_behavior", owner_player_id, stable_target_ids, stable_ai_profile)


## 记录一次已经实际成立的技能发动；技能应在确认支付费用、执行锁定效果或完成主动目标选择后调用，避免取消询问写入日志。
func announce_activation(context: Dictionary = {}) -> void:
	if host == null or not host.has_method("record_skill_activation"):
		return
	# 永久记录上下文副本；只允许基础可序列化值，不能把技能对象或界面节点交给日志、回放或表现层。
	var activation_context: Dictionary = context.duplicate(true)
	host.call("record_skill_activation", owner_player_id, get_id(), activation_context)


## 记录一次由指定角色实际支付费用或执行效果的技能发动；领袖技可用此入口将提示与日志归属到本回合发动者。
func announce_activation_for_player(activator_player_id: int, context: Dictionary = {}) -> void:
	if host == null or not host.has_method("record_skill_activation"):
		return
	# 永久记录上下文副本；指定发动者仍须由控制器复核为存活在场角色，避免技能实例直接写入无效日志。
	var activation_context: Dictionary = context.duplicate(true)
	host.call("record_skill_activation", activator_player_id, get_id(), activation_context)


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
	if host != null and host.get("modifier_pipeline") != null:
		host.modifier_pipeline.unregister_owner(self)


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


## 判断一张当前由持有者拥有的实体牌能否通过本技能转化为指定响应模式；默认不提供转化能力。
func can_convert_response_card(_card: CardInstance, _response_patterns: Array[String]) -> bool:
	return false


## 返回响应转化后使用的虚拟卡牌定义 ID；空字符串表示等待期间条件失效，控制器不会消耗材料牌。
func get_converted_response_definition_id(_card: CardInstance, _response_patterns: Array[String]) -> String:
	return ""


## 通知技能其转化响应已经实际消费材料并成功打出；可在此记录每回合次数，不能再次移动材料牌。
func on_converted_response_consumed(_card: CardInstance, _response_pattern: String, _virtual_definition_id: String) -> void:
	pass


## 恢复由控制器完整执行的额外阶段；上下文只包含稳定玩家、技能与阶段来源数据，不持有运行时对象。
func continue_extra_phase(_context: Dictionary) -> bool:
	return false


## 恢复因嵌套触发选择而暂停的技能后续结算；上下文只允许基础可序列化值，返回true表示已识别该步骤。
func continue_settlement(_context: Dictionary) -> bool:
	return false


## 将本技能的一段后续效果登记到控制器结算队列；当前嵌套选择全部结束后会回调continue_settlement。
func defer_settlement(context: Dictionary) -> bool:
	if host == null or not host.has_method("defer_skill_settlement"):
		return false
	return bool(host.call("defer_skill_settlement", owner_player_id, get_id(), context))


## 向基础 AI 的出牌阶段合法动作列表追加技能动作；动作必须使用 action_type=use_skill 并携带稳定 skill_id。
func append_play_phase_actions(_result: Array[Dictionary]) -> void:
	pass


## 计算基础 AI 对本技能主动动作的额外评分；具体技能只能读取快照、动作与评估器公开查询。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 计算基础 AI 对本技能创建的选择动作评分；确认、费用、选牌与选目标逻辑应写在对应技能文件中。
func score_ai_choice(_authoritative_snapshot: Dictionary, _choice_request: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 修正持有者使用卡牌动作的 AI 评分；锁定技与被动联动可在自身技能文件内表达牌效增减。
func modify_ai_card_action_score(_authoritative_snapshot: Dictionary, _action: Dictionary, current_score: float, _evaluator: Object) -> float:
	return current_score


## 判断持有者是否因本技能解除指定卡牌的配置化使用次数限制；默认不修改任何卡牌次数。
func ignores_play_count_limit(_card_definition: Dictionary) -> bool:
	return false


## 校验持有者使用牌时的技能附加目标限制；空字符串表示合法，非空文本会作为统一拒绝原因。
func validate_card_target_selection(_card_definition: Dictionary, _target_id: int, _all_target_ids: Array[int]) -> String:
	return ""


## 校验其他角色的牌能否指定本技能持有者；用于免疫类技能，必须保持纯查询且不得创建发动日志。
func validate_incoming_card_target_selection(_actor_id: int, _card_definition: Dictionary, _card_color: String) -> String:
	return ""


## 返回主动技能的只读交互预览；不得在本函数中消耗资源、创建选择或修改对局状态。
func get_activation_preview(_context: Dictionary = {}) -> Dictionary:
	return {}


## 为技能持有者创建统一选牌请求；候选必须是可序列化牌面快照，恢复上下文会自动绑定技能 ID 与持有者。
func request_card_selection(title: String, prompt: String, candidates: Array[Dictionary], min_select: int, max_select: int, allow_cancel: bool, context: Dictionary = {}) -> Array[int]:
	return request_card_selection_for_player(owner_player_id, title, prompt, candidates, min_select, max_select, allow_cancel, context)


## 为指定角色创建统一选牌请求；适用于技能持有者令事件来源角色弃牌、重铸或支付其自身手牌费用。
func request_card_selection_for_player(chooser_id: int, title: String, prompt: String, candidates: Array[Dictionary], min_select: int, max_select: int, allow_cancel: bool, context: Dictionary = {}) -> Array[int]:
	if host == null or not host.has_method("request_card_choice"):
		return []
	# 技能恢复上下文；稳定技能 ID 与持有者 ID 由基类统一写入，具体技能只保存自身步骤参数。
	var skill_context: Dictionary = _build_selection_context(context)
	# 上一段文字选择会在运行时上下文中写入 control 的协议字段；后续实体选牌必须清除这些字段，避免继承为同一文字询问。
	skill_context.erase("choice_type_override")
	skill_context.erase("control_options")
	skill_context.erase("min_card_select")
	skill_context.erase("max_card_select")
	skill_context.erase("min_target_select")
	skill_context.erase("max_target_select")
	skill_context["choice_chooser_id"] = chooser_id
	return host.call("request_card_choice", chooser_id, title, prompt, candidates, min_select, max_select, allow_cancel, skill_context) as Array[int]


## 为技能持有者创建单项文字选项请求；每个选项使用稳定 id 与玩家可见 label，取消表示不发动本次可选效果。
func request_control_selection(title: String, prompt: String, options: Array[Dictionary], allow_cancel: bool, context: Dictionary = {}) -> String:
	return request_control_selection_for_player(owner_player_id, title, prompt, options, allow_cancel, context)


## 为指定角色创建单项文字选项请求；响应通过 ChoiceResponse.control_id 恢复，不借用取消或空选牌表达第二选项。
func request_control_selection_for_player(chooser_id: int, title: String, prompt: String, options: Array[Dictionary], allow_cancel: bool, context: Dictionary = {}) -> String:
	if host == null or not host.has_method("request_control_choice"):
		return ""
	# 技能恢复上下文；跨角色选择仍绑定真实技能持有者，防止响应被选择者的同名技能实例误消费。
	var skill_context: Dictionary = _build_selection_context(context)
	skill_context["choice_chooser_id"] = chooser_id
	return str(host.call("request_control_choice", chooser_id, title, prompt, options, allow_cancel, skill_context))


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
