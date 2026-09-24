class_name SkillDefinition
extends RefCounted

## 武将技能源码定义基类。技能文件同时承载元数据、事件订阅与主动发动逻辑，不依赖集中技能注册表。

## 当前技能的完整静态元数据；由具体技能脚本构造并在数据库建立索引时读取。
var _metadata: Dictionary = {}

## 当前技能所属玩家 ID；未安装到对局时为 -1，安装后保持稳定 player_id。
var owner_player_id: int = -1

## 当前技能绑定的对局控制器端口；技能只能通过该端口请求规则操作，不直接修改界面节点。
var host: Object

## 当前技能实例绑定的武将入场代次；-1表示独立测试或未绑定权威角色，正式对局用于隔离换将前后的异步事件。
var _bound_character_generation: int = -1

## 当前技能是否为锁定技；true 表示效果满足条件时强制执行且不创建发动选择，默认 false 表示非锁定技。
var lock: bool = false

## 当前技能是否同时包含非锁定技前段与锁定技后段；默认根据正文中非开头位置的“锁定技”标签识别，也可由元数据显式配置。
var half_locked: bool = false

## 当前技能是否为领袖技；true 表示只有身份为 leader 的角色实际拥有并显示该技能，默认 false 表示不限制身份。
var leader_skill: bool = false

## 当前技能是否为离场技；true表示持有者存活但离场时仍可接收触发时机并参与纯查询效果，死亡后仍然失效。
var out_of_game_skill: bool = false

## 当前技能的卖血价值；非负浮点数，默认0.0表示受到伤害不会为本技能创造额外收益，1.0等价于AI估值中的一张牌。
var sell_blood_value: float = 0.0

## 当前技能是否为限定技；限定技默认只有一次固有发动额度，复原武将牌技能后恢复。
var limited: bool = false

## 当前技能是否为觉醒技；觉醒技同时具有锁定技与限定技语义，满足条件时不得由玩家取消。
var awakening: bool = false

## 当前限定技或觉醒技已经消耗的固有发动次数；默认0，首次实际发动并公开记录时变为1。
var _intrinsic_used_count: int = 0

## 当前技能是否为轮回技；轮回进度由ReincarnationSkillService保存，不存放在本运行时实例中。
var reincarnation: bool = false

## 当前正在执行的触发时机回调；仅在统一订阅包装器调用期间有效，用于让“额外发动”重放同一技能入口。
var _current_timing_callback: Callable = Callable()

## 当前正在执行的触发时机快照；只保存RuleEvent可序列化字段，避免跨结算持有已经结束的可写事件对象。
var _current_timing_event_snapshot: Dictionary = {}

## 最近一次公开发动对应的重放描述；主动技能保存上下文，触发技能保存回调与事件快照，仅供本技能实例局内使用。
var _last_activation_repeat_descriptor: Dictionary = {}

## 最近一次公开发动的递增令牌；初始0表示尚未发动，用于避免延迟重放命中后续另一场发动。
var _last_activation_repeat_token: int = 0

## 当前是否正在执行额外发动；true时新记录会标记为重复发动，防止【奇袭】递归复制自身产生无限循环。
var _repeat_activation_in_progress: bool = false

## 内容层显式语音请求的引擎毫秒时间戳；0表示本次发动过程中尚未显式请求语音。
## 核心层据此判断是否跳过默认自动播放：窗口内跳过，窗口外视为过期，避免“调用了却没真正发动”导致后续永久静音。
var _explicit_voice_request_msec: int = 0


## 保存技能元数据；元数据只在脚本构造时写入，运行时状态应使用独立成员变量保存。
func _init(metadata: Dictionary = {}) -> void:
	_metadata = metadata.duplicate(true)
	# 技能正文；“锁定技”位于正文中段时，从该标签开始的后段属于锁定技，前段仍按非锁定技处理。
	var description: String = str(_metadata.get("description", ""))
	awakening = bool(_metadata.get("awakening", false)) or description.contains("觉醒技")
	limited = bool(_metadata.get("limited", false)) or description.contains("限定技") or awakening
	# 觉醒技强制具有锁定语义；普通技能仍只读取显式lock配置。
	lock = bool(_metadata.get("lock", false)) or awakening
	_metadata["lock"] = lock
	_metadata["limited"] = limited
	_metadata["awakening"] = awakening
	# 锁定技标签位置；索引大于0表示正文具有非锁定前段，索引为0则是完整锁定技。
	var locked_label_index: int = description.find("锁定技")
	half_locked = bool(_metadata.get("half_locked", not lock and locked_label_index > 0))
	_metadata["half_locked"] = half_locked
	leader_skill = bool(_metadata.get("leader_skill", false))
	_metadata["leader_skill"] = leader_skill
	out_of_game_skill = bool(_metadata.get("out_of_game_skill", false))
	_metadata["out_of_game_skill"] = out_of_game_skill
	sell_blood_value = maxf(float(_metadata.get("sell_blood_value", 0.0)), 0.0)
	_metadata["sell_blood_value"] = sell_blood_value
	reincarnation = bool(_metadata.get("reincarnation", false)) or description.begins_with("轮回技")
	_metadata["reincarnation"] = reincarnation
	if reincarnation:
		# 轮回节总数；优先读取显式元数据，缺失时按正文中出现的最大带圈序号推导。
		var section_count: int = maxi(int(_metadata.get("reincarnation_section_count", _infer_reincarnation_section_count(description))), 1)
		_metadata["reincarnation_section_count"] = section_count
		_metadata["reincarnation_has_explicit_sections"] = bool(_metadata.get("reincarnation_has_explicit_sections", _description_has_reincarnation_sections(description)))
		_metadata["reincarnation_each_section_once_per_play_phase"] = bool(_metadata.get("reincarnation_each_section_once_per_play_phase", description.contains("出牌阶段每个轮回节限一次")))


## 返回技能元数据深拷贝，供武将引用校验、技能栏展示、网络与回放读取。
func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)


## 返回技能稳定 ID；同一技能脚本可被多个武将直接引用，但 ID 必须全项目唯一。
func get_id() -> String:
	return str(_metadata.get("id", ""))


## 返回技能的非负卖血价值；基础AI按1点等价1张牌修正友方主动卖血与敌方攻击收益。
func get_sell_blood_value() -> float:
	return sell_blood_value


## 绑定技能所属玩家与对局端口；数据库定义对象不会调用本函数，只有每局独立运行时实例会绑定。
func bind(match_host: Object, player_id: int) -> void:
	host = match_host
	owner_player_id = player_id
	# 当前技能所属角色；正式对局在安装技能前已应用武将，因此可以稳定捕获本次入场代次。
	var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.get("state") != null else null
	_bound_character_generation = owner.character_generation if owner != null else -1
	if reincarnation and host != null and host.has_method("register_reincarnation_skill"):
		host.call("register_reincarnation_skill", owner_player_id, get_id(), _metadata)


## 返回技能实例绑定的武将入场代次；规则续接只保存该整数，不保存技能对象引用。
func get_bound_character_generation() -> int:
	return _bound_character_generation


## 校验技能实例是否仍属于指定武将代次；负数期望值兼容不绑定权威状态的独立内容测试。
func matches_character_generation(expected_generation: int = -1) -> bool:
	# 当前技能持有者；正式对局必须同时满足实例绑定代次与角色最新代次一致。
	var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.get("state") != null else null
	if owner == null:
		return expected_generation < 0 and _bound_character_generation < 0
	if _bound_character_generation >= 0 and owner.character_generation != _bound_character_generation:
		return false
	return expected_generation < 0 or _bound_character_generation < 0 or expected_generation == _bound_character_generation


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
	_prepare_repeat_descriptor(activation_context)
	if _repeat_activation_in_progress:
		activation_context["repeated_activation"] = true
	host.call("record_skill_activation", owner_player_id, get_id(), activation_context)
	consume_intrinsic_use()
	# 局内获得技能次数；固有技能会由控制器直接返回true且不写入任何额外状态。
	if host.has_method("consume_acquired_skill_use"):
		host.call("consume_acquired_skill_use", owner_player_id, get_id())


## 记录一次由指定角色实际支付费用或执行效果的技能发动；领袖技可用此入口将提示与日志归属到本回合发动者。
func announce_activation_for_player(activator_player_id: int, context: Dictionary = {}) -> void:
	if host == null or not host.has_method("record_skill_activation"):
		return
	# 永久记录上下文副本；指定发动者仍须由控制器复核为存活在场角色，避免技能实例直接写入无效日志。
	var activation_context: Dictionary = context.duplicate(true)
	_prepare_repeat_descriptor(activation_context)
	if _repeat_activation_in_progress:
		activation_context["repeated_activation"] = true
	host.call("record_skill_activation", activator_player_id, get_id(), activation_context)
	consume_intrinsic_use()


## 请求播放本技能本次发动的语音；技能源码可在效果代码中调用它以自定义播放时机。
## 默认情况下核心统一出口已自动触发，重复调用不会导致重复发声。
func play_voice() -> void:
	if host == null or not host.has_method("request_skill_voice"):
		return
	# 记录显式请求时间戳；核心层会在抑制窗口内跳过本次自动播放，避免同一动作发出两次配音。
	_explicit_voice_request_msec = Time.get_ticks_msec()
	host.call("request_skill_voice", owner_player_id, get_id())


## 消费一次显式语音请求标记；距离显式调用未超过给定窗口时返回true，由核心层跳过自动播放。
## 窗口过期后标记自动失效，避免“调用了却没真正发动”导致后续发动被永久静音。
func consume_explicit_voice_request(window_seconds: float) -> bool:
	if _explicit_voice_request_msec <= 0:
		return false
	# 距显式请求的毫秒数；无论是否命中窗口标记都会清零，保证每次请求只被消费一次。
	var elapsed_msec: int = Time.get_ticks_msec() - _explicit_voice_request_msec
	_explicit_voice_request_msec = 0
	return elapsed_msec >= 0 and elapsed_msec <= int(window_seconds * 1000.0)


## 返回限定技或觉醒技是否仍有固有发动额度；普通技能始终返回true。
func has_available_intrinsic_use() -> bool:
	return not limited or _intrinsic_used_count <= 0


## 在技能首次实际发动时消耗限定额度；普通技能和已经消耗的限定技返回false。
func consume_intrinsic_use() -> bool:
	if not limited or _intrinsic_used_count > 0:
		return false
	_intrinsic_used_count = 1
	return true


## 复原限定技与觉醒技的固有发动额度；武将牌技能整体复原时由新实例自然回到同一状态。
func restore_intrinsic_use() -> void:
	_intrinsic_used_count = 0


## 复原当前限定技的一次固有发动额度；具体技能若保存了与限定额度同步的兼容状态，应覆盖本方法并在调用super后复原该状态。
## 本入口只复原限定技次数，不重置轮回、每回合、每轮、每阶段状态，也不清除已经生效的持续效果。
func restore_limited_use() -> void:
	restore_intrinsic_use()


## 返回当前轮回技公开状态；普通技能或未绑定状态返回空字典。
func get_reincarnation_state() -> Dictionary:
	if not reincarnation or host == null or not host.has_method("get_reincarnation_skill_state"):
		return {}
	return host.call("get_reincarnation_skill_state", owner_player_id, get_id()) as Dictionary


## 返回轮回技当前轮回数X；普通技能安全回退为初始值1。
func get_reincarnation_round_count() -> int:
	return maxi(int(get_reincarnation_state().get("round_count", 1)), 1)


## 返回轮回技当前轮回节零基索引；①对应0，普通技能回退0。
func get_reincarnation_section_index() -> int:
	return maxi(int(get_reincarnation_state().get("section_index", 0)), 0)


## 检查并开始一次轮回技发动；通用永劫与每轮回节阶段限次均在服务中统一复核。
func begin_reincarnation_activation() -> bool:
	return reincarnation and matches_character_generation() and host != null and host.has_method("begin_reincarnation_skill_activation") and bool(host.call("begin_reincarnation_skill_activation", owner_player_id, get_id()))


## 完成轮回技当前轮回节并推进状态；效果未实际成立时不得调用本入口。
func complete_reincarnation_activation() -> bool:
	return reincarnation and matches_character_generation() and host != null and host.has_method("complete_reincarnation_skill_activation") and bool(host.call("complete_reincarnation_skill_activation", owner_player_id, get_id()))


## 返回当前轮回技是否未触及通用限次；技能自身条件仍应在具体can_activate或触发回调中判断。
func can_activate_reincarnation() -> bool:
	return reincarnation and matches_character_generation() and host != null and host.has_method("can_activate_reincarnation_skill") and bool(host.call("can_activate_reincarnation_skill", owner_player_id, get_id()))


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


## 返回当前效果片段在“非锁定技失效”状态下是否仍能生效；完整锁定技始终有效，半锁定技仅允许显式标记的锁定后段。
func can_use_effect(locked_segment: bool = false) -> bool:
	# 技能持有者状态；数据库静态对象和独立内容测试没有权威状态时默认允许读取与执行。
	var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.get("state") != null else null
	if owner == null or not owner.non_locked_skills_disabled:
		return true
	return lock or (half_locked and locked_segment)


## 以技能持有者身份注册标准时机；role 决定匹配 player、source、target 或 global，成功返回稳定注册 ID。
## locked_segment只用于半锁定技后段；maintenance只允许持续效果到期或清理回调使用，不得在失效期间产生新收益。
func subscribe_timing(event_name: String, callback: Callable, role: String = "player", priority: int = 0, first_do: bool = false, last_do: bool = false, condition: Callable = Callable(), locked_segment: bool = false, maintenance: bool = false) -> int:
	if host == null or host.get("trigger_manager") == null or not RuleTimingCatalog.has_timing(event_name):
		return -1
	# 当前对局高级触发器；由技能基类统一传入 self 与 owner_player_id，具体技能无需复制解绑字段。
	var manager: TriggerManager = host.get("trigger_manager") as TriggerManager
	# 技能统一生效条件；注册时固化武将代次，暂停保存的旧处理器快照不会因实例之后重新绑定而变成新武将触发器。
	var guarded_condition: Callable = Callable(self, "_can_receive_timing_event").bind(condition, _bound_character_generation, locked_segment, maintenance)
	# 技能回调包装器；在不改变原回调签名的前提下记录可供“额外发动”复用的同一时机入口。
	var guarded_callback: Callable = Callable(self, "_dispatch_timing_callback").bind(callback)
	return manager.subscribe(event_name, self, guarded_callback, priority, owner_player_id, role, first_do, last_do, guarded_condition)


## 判断技能持有者失效后是否仍可接收指定时机；普通技能默认 false，明确设计为死亡后触发的技能可覆盖本接口。
func can_trigger_while_owner_inactive(_event: RuleEvent) -> bool:
	return false


## 统一校验技能时机订阅是否仍有效；死亡或离场持有者不会继续发动普通全局技能。
func _can_receive_timing_event(event: RuleEvent, custom_condition: Callable, subscribed_character_generation: int = -1, locked_segment: bool = false, maintenance: bool = false) -> bool:
	# 技能持有者权威状态；未绑定、死亡或离场时仅允许显式覆盖的特殊技能继续接收时机。
	var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.get("state") != null else null
	if not matches_character_generation(subscribed_character_generation):
		return false
	# 时机记录的角色代次；旧伤害尾部即使在新武将入场后恢复，也不能命中新安装的同名或同类技能。
	var expected_generation: int = -1
	if event.player_id == owner_player_id and event.data.has("player_character_generation"):
		expected_generation = int(event.data.get("player_character_generation", -1))
	if event.source_id == owner_player_id and event.data.has("source_character_generation"):
		expected_generation = int(event.data.get("source_character_generation", -1))
	if event.target_id == owner_player_id and event.data.has("target_character_generation"):
		expected_generation = int(event.data.get("target_character_generation", -1))
	if expected_generation >= 0 and not matches_character_generation(expected_generation):
		return false
	if (owner == null or not owner.alive) and not can_trigger_while_owner_inactive(event):
		return false
	if owner != null and owner.out_of_game and not out_of_game_skill and not can_trigger_while_owner_inactive(event):
		return false
	# 非锁定技失效时，完整非锁定技及半锁定技前段均不接收新时机；完整锁定技与半锁定技后段继续正常结算。
	if not maintenance and not can_use_effect(locked_segment):
		return false
	# 局内获得技能的每回合或总次数限制；额度耗尽后不再接收新的触发时机。
	if host != null and host.has_method("can_use_acquired_skill") and not bool(host.call("can_use_acquired_skill", owner_player_id, get_id())):
		return false
	return not custom_condition.is_valid() or bool(custom_condition.call(event))


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


## 额外发动最近一次已经成立的技能；触发技重放同一时机入口，主动技复用原上下文并保持既有目标字段。
## 具体技能存在分段选择或特殊费用时可覆盖本函数，成功提交效果返回true。
func repeat_activation(context: Dictionary = {}, activation_token: int = -1) -> bool:
	if activation_token >= 0 and activation_token != _last_activation_repeat_token:
		return false
	# 最近一次重放描述；空值表示技能尚未通过announce_activation留下可重放入口。
	var descriptor: Dictionary = _last_activation_repeat_descriptor.duplicate(true)
	if descriptor.is_empty():
		return false
	_repeat_activation_in_progress = true
	# 触发技能回调；克隆事件避免重复发动修改原事件的结束状态或结果。
	if str(descriptor.get("kind", "")) == "timing":
		# 原技能实际发动时所在的订阅回调；只在当前运行时实例内保存。
		var callback: Callable = descriptor.get("callback", Callable()) as Callable
		# 从序列化快照重建的独立规则事件；不复用原事件ID、结果或终止状态。
		var replay_event: RuleEvent = _create_rule_event_from_snapshot(descriptor.get("event", {}) as Dictionary)
		if callback.is_valid() and replay_event != null:
			callback.call(replay_event)
			_repeat_activation_in_progress = false
			return true
	# 主动技能回放；调用方上下文优先保留首次目标，内部标记只用于防止额外发动递归。
	var replay_context: Dictionary = (descriptor.get("context", context) as Dictionary).duplicate(true)
	replay_context["repeated_activation"] = true
	# 主动技能重放的错误文本；空字符串表示原入口已成功提交效果或后续选择。
	var activation_error: String = activate(replay_context)
	_repeat_activation_in_progress = false
	return activation_error.is_empty()


## 返回最近一次公开发动令牌；控制器只把该整数写入实际发动时机，不暴露运行时回调。
func get_last_activation_repeat_token() -> int:
	return _last_activation_repeat_token


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


## 返回无需实体材料即可提供的响应牌定义 ID；空字符串表示技能不支持无材料响应。
func get_cardless_response_definition_id(_response_patterns: Array[String]) -> String:
	return ""


## 通知技能无材料响应已经通过权威校验并实际打出；费用应在 activate() 中完成，本回调只记录成功事实。
func on_cardless_response_consumed(_response_pattern: String, _virtual_definition_id: String) -> void:
	pass


## 恢复由控制器完整执行的额外阶段；上下文只包含稳定玩家、技能与阶段来源数据，不持有运行时对象。
func continue_extra_phase(_context: Dictionary) -> bool:
	return false


## 恢复因嵌套触发选择而暂停的技能后续结算；上下文只允许基础可序列化值，返回true表示已识别该步骤。
func continue_settlement(_context: Dictionary) -> bool:
	return false


## 恢复由本技能发起、曾被判定前选择暂停的判定结果；judgment_card 为 null 表示判定被取消或牌堆耗尽。
## 返回 true 表示本技能识别并完成该判定后续，控制器只负责继续统一结算管线。
func continue_judgment(_context: Dictionary, _judgment_card: CardInstance) -> bool:
	return false


## 将本技能的一段后续效果登记到控制器结算队列；当前嵌套选择全部结束后会回调continue_settlement。
func defer_settlement(context: Dictionary) -> bool:
	if host == null or not host.has_method("defer_skill_settlement"):
		return false
	# 代次化结算上下文；换将后即使新武将再次拥有同名技能，旧“然后”步骤也只能安全失效。
	var settlement_context: Dictionary = context.duplicate(true)
	settlement_context["skill_character_generation"] = _bound_character_generation
	return bool(host.call("defer_skill_settlement", owner_player_id, get_id(), settlement_context))


## 按当前对局流程间隔安排一次纯表现延时回调；技能只提供稳定业务键与恢复回调，不直接读取或管理流程计时器。
## 回调应只在已经完成规则结算后创建下一段交互或表现，不能把伤害、摸牌等规则数值依赖于等待是否完成。
func schedule_after_flow_interval(task_name: String, callback: Callable) -> bool:
	if host == null or not callback.is_valid():
		return false
	# 当前对局节奏器；不存在时按同步模式执行，保持无场景测试与零速度模式的规则结果一致。
	var flow_pacer: GameFlowPacer = host.get("game_flow_pacer") as GameFlowPacer
	# 当前全局流程间隔；读取控制器公开配置而不由技能写入，范围由控制器和设置层统一限制。
	var delay_seconds: float = float(host.get("game_flow_interval_seconds"))
	if flow_pacer == null or delay_seconds <= 0.0:
		callback.call()
		return true
	# 同一技能持有者和业务键共享取消域；新回调会替换旧回调，重新开局时控制器统一取消全部任务。
	var task_key: String = "%s:%d:%s" % [get_id(), owner_player_id, task_name]
	flow_pacer.schedule(task_key, delay_seconds, callback)
	return true


## 向基础 AI 的出牌阶段合法动作列表追加技能动作；动作必须使用 action_type=use_skill 并携带稳定 skill_id。
func append_play_phase_actions(_result: Array[Dictionary]) -> void:
	pass


## 计算基础 AI 对本技能主动动作的额外评分；具体技能只能读取快照、动作与评估器公开查询。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 返回主动技能实际生成的虚拟用牌动作；基础AI会把该动作送入完整卡牌与被动技能评分链，再把新增收益合并回技能动作。
## 非转化技能保持空字典；覆盖时只能返回只读、可序列化的use_card动作，不得修改对局状态或技能运行时字段。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> Dictionary:
	return {}


## 计算基础 AI 对本技能创建的选择动作评分；确认、费用、选牌与选目标逻辑应写在对应技能文件中。
func score_ai_choice(_authoritative_snapshot: Dictionary, _choice_request: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 修正持有者使用卡牌动作的 AI 评分；锁定技与被动联动可在自身技能文件内表达牌效增减。
func modify_ai_card_action_score(_authoritative_snapshot: Dictionary, _action: Dictionary, current_score: float, _evaluator: Object) -> float:
	return current_score


## 修正其他角色对持有者造成的牌效 AI 估值；濒死自救等改变预期结局的技能可在自身文件内覆盖，默认保持通用估值。
func modify_ai_incoming_card_effect(_authoritative_snapshot: Dictionary, _actor_id: int, _target_id: int, _definition: Dictionary, _ai_profile: Dictionary, _target_result: float, _expected_damage_amount: int, current_score: float, _evaluator: Object) -> float:
	return current_score


## 判断持有者是否因本技能解除指定卡牌的配置化使用次数限制；默认不修改任何卡牌次数。
func ignores_play_count_limit(_card_definition: Dictionary) -> bool:
	return false


## 判断持有者使用指定卡牌后是否不计入配置化次数限制；此规则不会帮助已经达到上限的牌通过使用前校验。
func does_not_count_toward_play_limit(_card_definition: Dictionary) -> bool:
	return false


## 返回当前技能对指定牌 play_limit 的额外次数加成；默认0，正值在配置基础上增加可使用次数，不修改历史统计。
## 例如【跋扈】对 slash 牌族返回1，使出牌阶段使用【杀】的次数上限+1。
func get_play_count_limit_bonus(_card_definition: Dictionary) -> int:
	return 0


## 判断技能是否令指定卡牌忽略距离限制；默认保持卡牌自身的攻击范围、距离1或特殊距离规则。
func ignores_card_distance_limit(_card_definition: Dictionary) -> bool:
	return false


## 修正持有者到指定目标的最终距离；默认保持坐骑与座次计算结果，返回值必须收敛为0以上整数。
func modify_distance_to_target(_target_id: int, current_distance: int) -> int:
	return current_distance


## 判断其他角色能否弃置持有者的指定牌；默认允许，保护技能只拒绝规则明确覆盖的区域与牌型。
func can_other_player_discard_card(_source_player_id: int, _card: CardInstance, _zone: String, _slot: String) -> bool:
	return true


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


## 为技能持有者创建“目标与文字选项同时确认”的复合请求；适合先点选角色再按效果按钮的一步式交互。
func request_target_control_selection(title: String, prompt: String, target_ids: Array[int], options: Array[Dictionary], allow_cancel: bool, context: Dictionary = {}) -> Dictionary:
	if host == null or not host.has_method("request_target_control_choice"):
		return {}
	# 技能恢复上下文；目标和控制项均由同一ChoiceResponse提交，避免两个窗口之间出现状态变化歧义。
	var skill_context: Dictionary = _build_selection_context(context)
	return host.call("request_target_control_choice", owner_player_id, title, prompt, target_ids, options, allow_cancel, skill_context) as Dictionary


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


## 为技能持有者创建牌堆顶/底双行排序请求；响应 card_ids 保存从左到右顺序，control_id 保存牌堆顶行数量。
func request_pile_arrangement(title: String, prompt: String, candidates: Array[Dictionary], context: Dictionary = {}) -> Array[int]:
	if host == null or not host.has_method("request_card_choice") or candidates.is_empty():
		return []
	# 排序上下文；全部候选必须恰好出现一次，界面可在两行之间拖动并保持每行从左到右的顺序语义。
	var skill_context: Dictionary = _build_selection_context(context)
	skill_context["choice_type_override"] = "arrange"
	# 顶行数量选项；稳定ID随候选总数生成，权威提交据此分割顶行和底行。
	var top_count_options: Array[Dictionary] = []
	for top_count: int in range(candidates.size() + 1):
		top_count_options.append({"id":"top_count_%d" % top_count, "label":str(top_count)})
	skill_context["control_options"] = top_count_options
	return host.call("request_card_choice", owner_player_id, title, prompt, candidates, candidates.size(), candidates.size(), false, skill_context) as Array[int]


## 按稳定UID查找技能持有者当前拥有的转化材料；支持手牌、木牛“粮”与装备区，不移动实体牌。
func get_owned_conversion_material_card(card_uid: int) -> CardInstance:
	# 技能持有者权威状态；未绑定或角色无效时没有任何可用材料。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return null
	# 手牌或木牛“粮”实体；PlayerState统一可使用牌源保证临时视为牌也能保留原实体颜色。
	var playable_card: CardInstance = owner.find_playable_card(card_uid)
	if playable_card != null:
		return playable_card
	for equipment_variant: Variant in owner.equipment.values():
		# 当前装备实体；稳定UID匹配时允许满足“一张牌”类转化材料描述。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card != null and equipment_card.uid == card_uid:
			return equipment_card
	return null


## 构建单材料虚拟牌的规则覆写；材料真实颜色会覆盖调用方同名字段，防止预览或动作伪造颜色。
func build_virtual_rule_overrides(material_card: CardInstance, base_overrides: Dictionary = {}) -> Dictionary:
	# 本次独立规则覆写；深复制避免向技能常量或后续候选查询写入材料状态。
	var rule_overrides: Dictionary = base_overrides.duplicate(true)
	# 单材料真实颜色；无材料时使用none，让多材料或无色虚拟牌继续接受最终事件复核。
	rule_overrides["card_color"] = material_card.get_color() if material_card != null else "none"
	return rule_overrides


## 使用材料真实颜色校验虚拟牌的完整目标组合；次数、距离、技能免疫和目标数量均走统一规则服务。
func validate_virtual_use_for_material(virtual_definition_id: String, material_card: CardInstance, target_ids: Array[int], base_overrides: Dictionary = {}) -> String:
	if host == null or host.get("card_rules") == null or material_card == null:
		return "转化材料或规则服务不存在。"
	return str(host.card_rules.validate_virtual_use(owner_player_id, virtual_definition_id, target_ids, build_virtual_rule_overrides(material_card, base_overrides)))


## 为每张候选材料计算其转化牌合法目标，并同时返回全部目标并集；UI与AI据此避免先选到材料不兼容的目标。
func build_virtual_target_selection_data(virtual_definition_id: String, candidates: Array[Dictionary], base_overrides: Dictionary = {}) -> Dictionary:
	# 实体UID到合法目标数组的映射；键使用字符串保证网络序列化后仍可稳定查询。
	var target_ids_by_card_id: Dictionary = {}
	# 全部材料合法目标的并集；用于材料尚未选中时展示至少存在一种材料可以命中的角色。
	var all_target_ids: Array[int] = []
	if host == null or host.get("card_rules") == null:
		return {"target_ids":all_target_ids, "target_ids_by_card_id":target_ids_by_card_id}
	for candidate: Dictionary in candidates:
		# 当前候选材料UID；无效候选仍写入空映射，禁止界面回退到全部目标。
		var material_card_uid: int = int(candidate.get("uid", -1))
		# 当前权威材料实体；等待期间已离区的候选自然得到空目标集合。
		var material_card: CardInstance = get_owned_conversion_material_card(material_card_uid)
		# 当前材料对应的合法目标；传入真实颜色后，【琥珀】等来牌限制会在预览与AI枚举阶段生效。
		var material_target_ids: Array[int] = []
		if material_card != null:
			material_target_ids.assign(host.card_rules.list_legal_virtual_targets(owner_player_id, virtual_definition_id, build_virtual_rule_overrides(material_card, base_overrides)))
		target_ids_by_card_id[str(material_card_uid)] = material_target_ids.duplicate()
		for target_id: int in material_target_ids:
			if not all_target_ids.has(target_id):
				all_target_ids.append(target_id)
	return {"target_ids":all_target_ids, "target_ids_by_card_id":target_ids_by_card_id}


## 构建技能选择恢复上下文；调用方同名字段不能覆盖稳定技能归属，避免响应被错误技能消费。
func _build_selection_context(context: Dictionary) -> Dictionary:
	# 可写上下文副本；仅保存可序列化值，不传递技能对象或 Callable。
	var result: Dictionary = context.duplicate(true)
	result["skill_id"] = get_id()
	result["skill_owner_id"] = owner_player_id
	result["skill_character_generation"] = _bound_character_generation
	# 离场技选择许可；控制器只在请求归属技能明确声明离场技时允许存活离场持有者继续完成目标或选牌。
	if out_of_game_skill:
		result["allow_out_of_game_chooser"] = true
	return result


## 通过统一包装器执行技能时机回调，并在调用期间保存可序列化事件快照供announce_activation登记重放入口。
func _dispatch_timing_callback(event: RuleEvent, callback: Callable) -> void:
	if event == null or not callback.is_valid():
		return
	# 外层嵌套时机的回调；内层时机结束后恢复，避免丢失外层技能重放入口。
	var previous_timing_callback: Callable = _current_timing_callback
	# 外层嵌套时机的可序列化快照；深拷贝保证内层修改不影响恢复值。
	var previous_timing_event_snapshot: Dictionary = _current_timing_event_snapshot.duplicate(true)
	_current_timing_callback = callback
	_current_timing_event_snapshot = event.to_dict()
	callback.call(event)
	_current_timing_callback = previous_timing_callback
	_current_timing_event_snapshot = previous_timing_event_snapshot


## 为一次实际发动建立稳定重放描述；每次发动递增令牌，较早的延迟请求因此不会误重放后续发动。
func _prepare_repeat_descriptor(activation_context: Dictionary) -> void:
	_last_activation_repeat_token += 1
	if _current_timing_callback.is_valid() and not _current_timing_event_snapshot.is_empty():
		_last_activation_repeat_descriptor = {"kind":"timing", "callback":_current_timing_callback, "event":_current_timing_event_snapshot.duplicate(true)}
	else:
		_last_activation_repeat_descriptor = {"kind":"active", "context":activation_context.duplicate(true)}


## 从序列化快照创建独立RuleEvent；额外发动只复用原时机业务字段，不复用终态、结果或事件ID。
func _create_rule_event_from_snapshot(snapshot: Dictionary) -> RuleEvent:
	if snapshot.is_empty():
		return null
	# 重放规则事件；player参数显式恢复，避免构造器默认把source当作主要角色。
	var replay_event: RuleEvent = RuleEvent.new(str(snapshot.get("name", "")), int(snapshot.get("source_id", -1)), int(snapshot.get("target_id", -1)), snapshot.get("data", {}) as Dictionary, int(snapshot.get("player_id", -1)))
	replay_event.data["repeated_activation"] = true
	return replay_event


## 从技能正文中推导轮回节数量；支持①至⑩，未出现序号时按单轮回节处理。
func _infer_reincarnation_section_count(description: String) -> int:
	# 可识别的带圈序号；数组位置+1即对应轮回节数量。
	var section_symbols: Array[String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
	# 当前正文中出现的最大轮回节序号；默认1实现无显式序号的单轮回节语义。
	var inferred_count: int = 1
	for symbol_index: int in range(section_symbols.size()):
		if description.contains(section_symbols[symbol_index]):
			inferred_count = symbol_index + 1
	return inferred_count


## 判断技能正文是否显式包含至少一个带圈轮回节序号；无序号轮回技仍保留单节进度但界面不拆段。
func _description_has_reincarnation_sections(description: String) -> bool:
	return description.contains("①")
