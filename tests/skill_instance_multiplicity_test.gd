extends Node

## 技能实例多重性专项回归：锁定「同一角色可以拥有同一技能的多个实例，且各实例分别计算」的完整链路。
##
## 【为什么需要本用例】实例键是一条贯穿数据层、核心层与界面层的隐式约定：
## 键格式（首实例 == 技能ID，后续实例 == <技能ID>#N）、端口「实例键或技能ID」兼容、额度按实例记账、
## 快照同时下发实例粒度与技能粒度两种口径、旧存档只有纯技能ID 时回落到首实例。
## 任何一环漂移都会表现为“第二份实例点不到 / 不计数 / 读档后消失 / 界面少一个按钮”，
## 而这些症状分散在四层，靠人工回归极难发现，因此在这里逐环固定下来。

## 本次测试权威控制器；使用与正式场景同类型的实例并手动装配必需子节点。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 样例武将稳定ID；使用只有两个固有技能的武将，使固有技能集合可预测。
const SAMPLE_CHARACTER_ID: String = "luka"

## 被重复授予的样例技能稳定ID；该技能不属于样例武将的固有技能列表。
const DUPLICATE_SKILL_ID: String = "liubai"

## 第二份实例的期望实例键；键格式为「技能ID#2」，序号从2起。
const SECOND_INSTANCE_KEY: String = "liubai#2"

## 不存在的序号实例键；用于验证“显式实例键缺失时不静默回落到首实例”。
const ABSENT_INSTANCE_KEY: String = "liubai#9"

## 权威快照中的“实际安装技能”字段名；按实例键下发。
const INSTALLED_FIELD: String = "installed_skill_ids"

## 每份实例的每回合发动额度；两份实例各自独立持有该额度。
const PER_INSTANCE_TURN_LIMIT: int = 2


## 延迟一帧执行全部断言，确保 GameDatabase 已完成武将、技能与卡牌目录扫描。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 按独立状态顺序执行全部断言；任一环节失败都立即停止并报告具体原因。
func _run() -> void:
	_create_controller()
	if not _test_instance_key_format():
		return
	if not _test_duplicate_grant_and_lookup():
		return
	if not _test_per_instance_quota():
		return
	if not _test_independent_removal():
		return
	if not _test_remove_all_instances_by_skill_id():
		return
	if not _test_runtime_skill_data_is_per_instance():
		return
	if not _test_snapshot_exposes_both_granularities():
		return
	if not _test_ui_view_renders_each_instance():
		return
	if not _test_legal_actions_carry_instance_keys():
		return
	if not _test_legacy_plain_id_falls_back_to_first_instance():
		return
	if not _test_state_round_trip_keeps_runtime_data():
		return
	print("SKILL_INSTANCE_MULTIPLICITY_PASS keys=1 duplicate=1 quota=1 remove_one=1 remove_all=1 runtime=1 snapshot=1 ui=1 legal=1 legacy=1 roundtrip=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关；不加载界面。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能安装与卸载都会在这里订阅与释放时机。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保持正式实现，避免技能查询走空分支。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；公开快照广播与正式单机模式保持相同路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	# 表现间隔归零；规则状态不得依赖计时器，断言在零速度模式下同步完成。
	_controller.game_flow_interval_seconds = 0.0


## 创建最小权威状态并安装武将技能；一号领袖、其余反贼形成稳定敌我关系。
func _reset_state(player_count: int) -> void:
	# 先卸载旧实例；否则上一场景的技能订阅会跨场景继续响应规则时机。
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "skill-instance-multiplicity"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；统一使用样例武将，使固有技能集合可预测。
		var player: PlayerState = PlayerState.new(player_id, "技能实例测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		player.character_id = SAMPLE_CHARACTER_ID
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()
	# 按武将定义安装固有技能；查询入口必须能在安装后立刻识别它们。
	_controller._install_all_character_skills()


## 授予两份同名技能实例并返回是否成功；两份实例都带每回合额度，便于验证额度互不影响。
func _grant_two_instances() -> bool:
	if not _controller.grant_acquired_skill(0, DUPLICATE_SKILL_ID, PER_INSTANCE_TURN_LIMIT):
		return _fail("first_grant_rejected skill=%s" % DUPLICATE_SKILL_ID)
	if not _controller.grant_acquired_skill(0, DUPLICATE_SKILL_ID, PER_INSTANCE_TURN_LIMIT, 0, "runtime", false, 0, true):
		return _fail("duplicate_grant_rejected skill=%s" % DUPLICATE_SKILL_ID)
	return true


## 实例键格式：首实例等于技能ID，第二份实例为「技能ID#2」，还原函数对两种形态都稳定。
func _test_instance_key_format() -> bool:
	if SkillDefinition.base_skill_id_of(DUPLICATE_SKILL_ID) != DUPLICATE_SKILL_ID:
		return _fail("plain_id_not_identity value=%s" % SkillDefinition.base_skill_id_of(DUPLICATE_SKILL_ID))
	if SkillDefinition.base_skill_id_of(SECOND_INSTANCE_KEY) != DUPLICATE_SKILL_ID:
		return _fail("instance_key_not_reduced value=%s" % SkillDefinition.base_skill_id_of(SECOND_INSTANCE_KEY))
	# 技能ID本身不含“#”（数据库只允许 [a-z0-9_]），因此还原必须取最后一个“#”之后的部分。
	if SkillDefinition.base_skill_id_of("") != "":
		return _fail("empty_key_not_empty")
	return true


## 重复授予与按实例查询：默认拒绝重复，显式允许后两份实例各自可被精确取到。
func _test_duplicate_grant_and_lookup() -> bool:
	_reset_state(2)
	# 第一次授予占用首实例键；此时实例键与技能ID同形。
	if not _controller.grant_acquired_skill(0, DUPLICATE_SKILL_ID):
		return _fail("first_grant_rejected skill=%s" % DUPLICATE_SKILL_ID)
	# 未显式允许重复时必须拒绝；否则“是否已经拥有技能X”的既有语义会被破坏。
	if _controller.grant_acquired_skill(0, DUPLICATE_SKILL_ID):
		return _fail("duplicate_grant_not_rejected skill=%s" % DUPLICATE_SKILL_ID)
	# 显式允许重复后必须成功，并占用最小空闲序号。
	if not _controller.grant_acquired_skill(0, DUPLICATE_SKILL_ID, 0, 0, "runtime", false, 0, true):
		return _fail("duplicate_grant_rejected skill=%s" % DUPLICATE_SKILL_ID)
	# 实例粒度：两份实例都在，且按键序（首实例优先）排列。
	var instances: Array[SkillDefinition] = _controller.get_skill_instances(0, DUPLICATE_SKILL_ID)
	if instances.size() != 2:
		return _fail("instance_count=%d keys=%s" % [instances.size(), _controller.get_installed_skill_keys(0)])
	# 技能粒度：按技能ID去重后只剩一项。
	var deduped_ids: Array[String] = _controller.get_installed_skill_ids(0)
	# 该技能在去重结果里出现的次数；必须恰好一次。
	var deduped_hits: int = 0
	for skill_id: String in deduped_ids:
		if skill_id == DUPLICATE_SKILL_ID:
			deduped_hits += 1
	if deduped_hits != 1:
		return _fail("deduped_hits=%d ids=%s" % [deduped_hits, deduped_ids])
	# 精确查询：技能ID取首实例，序号键取第二份实例，二者必须是不同的运行时对象。
	var first_instance: SkillDefinition = _controller.get_skill_instance(0, DUPLICATE_SKILL_ID)
	var second_instance: SkillDefinition = _controller.get_skill_instance(0, SECOND_INSTANCE_KEY)
	if first_instance == null or second_instance == null or first_instance == second_instance:
		return _fail("exact_lookup_failed first=%s second=%s" % [first_instance, second_instance])
	if first_instance.get_instance_key() != DUPLICATE_SKILL_ID or second_instance.get_instance_key() != SECOND_INSTANCE_KEY:
		return _fail("instance_key_mismatch first=%s second=%s" % [first_instance.get_instance_key(), second_instance.get_instance_key()])
	# 不存在的序号实例键不得静默回落到首实例；否则内容层会改错实例。
	if _controller.get_skill_instance(0, ABSENT_INSTANCE_KEY) != null:
		return _fail("absent_instance_key_fell_back key=%s" % ABSENT_INSTANCE_KEY)
	# 拥有口径对两种粒度都必须成立。
	if not _controller.has_skill(0, DUPLICATE_SKILL_ID) or not _controller.has_skill(0, SECOND_INSTANCE_KEY):
		return _fail("has_skill_failed keys=%s" % _controller.get_installed_skill_keys(0))
	return true


## 额度按实例记账：一份实例耗尽自己的额度时，另一份实例仍可继续发动。
func _test_per_instance_quota() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	# 第二份实例先用满自己的每回合额度。
	for use_index: int in range(PER_INSTANCE_TURN_LIMIT):
		if not _controller.consume_acquired_skill_use(0, SECOND_INSTANCE_KEY):
			return _fail("second_consume_rejected index=%d" % use_index)
	if _controller.can_use_acquired_skill(0, SECOND_INSTANCE_KEY):
		return _fail("second_instance_quota_not_exhausted")
	# 首实例的额度必须完全不受影响；这是「分别计算」的核心断言。
	if not _controller.can_use_acquired_skill(0, DUPLICATE_SKILL_ID):
		return _fail("first_instance_quota_affected")
	if not _controller.consume_acquired_skill_use(0, DUPLICATE_SKILL_ID):
		return _fail("first_consume_rejected")
	return true


## 单独移除一份实例：另一份实例与它的额度记录都必须完好。
func _test_independent_removal() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	if not _controller.remove_acquired_skill(0, SECOND_INSTANCE_KEY):
		return _fail("remove_second_rejected key=%s" % SECOND_INSTANCE_KEY)
	# 第二份实例必须消失，首实例必须仍在。
	if _controller.get_skill_instance(0, SECOND_INSTANCE_KEY) != null:
		return _fail("removed_instance_still_present key=%s" % SECOND_INSTANCE_KEY)
	if _controller.get_skill_instance(0, DUPLICATE_SKILL_ID) == null:
		return _fail("sibling_instance_removed keys=%s" % _controller.get_installed_skill_keys(0))
	# 额度记录必须随实例一起清掉；否则序号会被复用后继承旧额度。
	if (_controller.state.get_player(0).acquired_skills as Dictionary).has(SECOND_INSTANCE_KEY):
		return _fail("removed_instance_quota_left key=%s" % SECOND_INSTANCE_KEY)
	# 序号复用：再次授予必须重新占用最小空闲序号 #2，而不是继续增长到 #3。
	if not _controller.grant_acquired_skill(0, DUPLICATE_SKILL_ID, PER_INSTANCE_TURN_LIMIT, 0, "runtime", false, 0, true):
		return _fail("regrant_rejected")
	if _controller.get_skill_instance(0, SECOND_INSTANCE_KEY) == null:
		return _fail("regrant_key_not_reused keys=%s" % _controller.get_installed_skill_keys(0))
	return true


## 按技能ID移除技能时必须清掉全部实例；这是内容层「并失去本技能」的既有语义。
func _test_remove_all_instances_by_skill_id() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	if not _controller.remove_skill(0, DUPLICATE_SKILL_ID, "技能实例测试"):
		return _fail("remove_skill_rejected skill=%s" % DUPLICATE_SKILL_ID)
	if _controller.has_skill(0, DUPLICATE_SKILL_ID) or _controller.has_skill(0, SECOND_INSTANCE_KEY):
		return _fail("remove_skill_left_instances keys=%s" % _controller.get_installed_skill_keys(0))
	# 技能粒度结果里也不得残留。
	if _controller.get_installed_skill_ids(0).has(DUPLICATE_SKILL_ID):
		return _fail("remove_skill_left_deduped_id")
	return true


## 运行时配置按实例键隔离：两份实例可以携带完全不同的组合参数。
func _test_runtime_skill_data_is_per_instance() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	_controller.set_runtime_skill_data(0, DUPLICATE_SKILL_ID, {"timing":"damageAfter", "effect":"draw"})
	_controller.set_runtime_skill_data(0, SECOND_INSTANCE_KEY, {"timing":"roundStart", "effect":"loseHp"})
	# 两份实例的配置必须各自独立，不能互相覆盖。
	var first_data: Dictionary = _controller.get_runtime_skill_data(0, DUPLICATE_SKILL_ID)
	var second_data: Dictionary = _controller.get_runtime_skill_data(0, SECOND_INSTANCE_KEY)
	if str(first_data.get("timing", "")) != "damageAfter" or str(second_data.get("timing", "")) != "roundStart":
		return _fail("runtime_data_shared first=%s second=%s" % [first_data, second_data])
	# 深拷贝语义：修改返回值不得影响权威状态。
	first_data["timing"] = "mutated"
	if str(_controller.get_runtime_skill_data(0, DUPLICATE_SKILL_ID).get("timing", "")) != "damageAfter":
		return _fail("runtime_data_not_deep_copied")
	# 传空字典等价于清除该实例的配置。
	_controller.set_runtime_skill_data(0, SECOND_INSTANCE_KEY, {})
	if not _controller.get_runtime_skill_data(0, SECOND_INSTANCE_KEY).is_empty():
		return _fail("runtime_data_not_cleared")
	return true


## 构建只含本人条目的最小整局快照，并由权威侧补齐技能字段。
## 基础玩家条目取自 PlayerState.to_dict，因此自带 acquired_skills 等运行时技能来源；
## 只手工拼一个 {"player_id":0} 会让快照缺少技能来源，两个拥有口径入口都会正确地返回空结果。
func _build_local_snapshot() -> Dictionary:
	# 本人权威玩家字典；reveal_private=true 让测试看到与房主视角一致的完整字段。
	var player_snapshot: Dictionary = _controller.state.get_player(0).to_dict(0, true)
	# 整局快照；只放本人，使 player_id 与断言目标一致。
	var snapshot: Dictionary = {"players":[player_snapshot]}
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	return snapshot


## 公开快照同时提供实例粒度与技能粒度两种口径，且两种口径互相自洽。
func _test_snapshot_exposes_both_granularities() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	# 构造只含本人条目的最小整局快照，随后由权威侧补齐技能字段。
	var snapshot: Dictionary = _build_local_snapshot()
	# 快照玩家条目；上面的构造保证它存在。
	var player_snapshot: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	# 实例粒度字段必须同时含两份实例键。
	var installed_keys: Array = player_snapshot.get(INSTALLED_FIELD, []) as Array
	if not installed_keys.has(DUPLICATE_SKILL_ID) or not installed_keys.has(SECOND_INSTANCE_KEY):
		return _fail("installed_keys=%s" % [installed_keys])
	# 技能粒度入口读取同一份快照时必须只给出一项，且两份实例都被判定为“拥有”。
	var collected_ids: Array[String] = SkillDefinition.collect_snapshot_skill_ids(player_snapshot)
	if not collected_ids.has(DUPLICATE_SKILL_ID):
		return _fail("collected_ids=%s" % [collected_ids])
	if not SkillDefinition.snapshot_has_skill(player_snapshot, DUPLICATE_SKILL_ID):
		return _fail("snapshot_has_skill_false")
	# 实例粒度入口保留两项，且每项都能还原成同一个技能ID。
	var collected_keys: Array[String] = SkillDefinition.collect_snapshot_skill_keys(player_snapshot)
	if not collected_keys.has(DUPLICATE_SKILL_ID) or not collected_keys.has(SECOND_INSTANCE_KEY):
		return _fail("collected_keys=%s" % [collected_keys])
	# 实例键列表成员判定：技能ID命中任一实例，显式实例键只命中自己。
	if not SkillDefinition.instance_key_list_has_skill([SECOND_INSTANCE_KEY], DUPLICATE_SKILL_ID):
		return _fail("instance_list_base_id_missed")
	if SkillDefinition.instance_key_list_has_skill([SECOND_INSTANCE_KEY], ABSENT_INSTANCE_KEY):
		return _fail("instance_list_absent_key_hit")
	return true


## 界面视图模型必须为每一份实例产出一条独立条目，且两条条目的技能ID相同、实例键不同。
func _test_ui_view_renders_each_instance() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	var snapshot: Dictionary = _build_local_snapshot()
	var player_snapshot: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	# 被查看角色的武将定义副本；固有技能顺序由它决定。
	var character_definition: Dictionary = GameDatabase.get_character(SAMPLE_CHARACTER_ID)
	# 可见实例键；两份同名实例必须各自出现一次。
	var visible_keys: Array[String] = CharacterSkillDisplay.collect_visible_skill_keys(player_snapshot, character_definition)
	# 目标技能在可见实例键里出现的次数。
	var visible_hits: int = 0
	for visible_key: String in visible_keys:
		if SkillDefinition.base_skill_id_of(visible_key) == DUPLICATE_SKILL_ID:
			visible_hits += 1
	if visible_hits != 2:
		return _fail("visible_hits=%d keys=%s" % [visible_hits, visible_keys])
	# 技能粒度入口在同一份快照上只给出一项，证明两个入口的分工没有互相污染。
	var visible_ids: Array[String] = CharacterSkillDisplay.collect_visible_skill_ids(player_snapshot, character_definition)
	# 目标技能在可见技能ID里出现的次数。
	var id_hits: int = 0
	for visible_id: String in visible_ids:
		if visible_id == DUPLICATE_SKILL_ID:
			id_hits += 1
	if id_hits != 1:
		return _fail("visible_id_hits=%d ids=%s" % [id_hits, visible_ids])
	# 条目列表：两份实例各一条，技能ID一致、实例键不同，标题不得出现内部“#序号”。
	var entries: Array[Dictionary] = CharacterSkillDisplay.build_skill_entries(player_snapshot, character_definition)
	# 本次目标技能产生的条目实例键。
	var entry_keys: Array[String] = []
	for entry: Dictionary in entries:
		if str(entry.get("skill_id", "")) == DUPLICATE_SKILL_ID:
			entry_keys.append(str(entry.get("instance_key", "")))
			if str(entry.get("title", "")).contains("#"):
				return _fail("entry_title_leaked_key title=%s" % entry.get("title"))
	if entry_keys.size() != 2 or not entry_keys.has(DUPLICATE_SKILL_ID) or not entry_keys.has(SECOND_INSTANCE_KEY):
		return _fail("entry_keys=%s" % [entry_keys])
	return true


## 合法动作枚举必须为每一份实例产出可区分的技能动作标识。
## 【留白】的主动入口在最小状态（存活、本人出牌阶段、限定额度未用）下即可发动，
## 因此不需要构造手牌或目标，断言只依赖实例键的改写这一条链路。
func _test_legal_actions_carry_instance_keys() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	# 合法动作集合；只有技能动作需要携带实例键，卡牌动作不受影响。
	var legal_actions: Array[Dictionary] = _controller.get_legal_actions(0)
	# 本技能两份实例各自产出的动作标识。
	var action_keys: Array[String] = []
	for legal_action: Dictionary in legal_actions:
		if str(legal_action.get("action_type", "")) != "use_skill":
			continue
		# 当前技能动作标识；顶层与负载必须一致，否则提交与预校验会读到不同的技能。
		var action_key: String = str(legal_action.get("skill_id", ""))
		if SkillDefinition.base_skill_id_of(action_key) != DUPLICATE_SKILL_ID:
			continue
		if str((legal_action.get("payload", {}) as Dictionary).get("skill_id", "")) != action_key:
			return _fail("action_payload_mismatch top=%s payload=%s" % [action_key, legal_action.get("payload")])
		if not action_keys.has(action_key):
			action_keys.append(action_key)
	if action_keys.size() != 2 or not action_keys.has(DUPLICATE_SKILL_ID) or not action_keys.has(SECOND_INSTANCE_KEY):
		return _fail("legal_action_keys=%s" % [action_keys])
	return true


## 旧存档兼容：只有纯技能ID 的输入必须落到首实例，不因缺少序号而报错或丢技能。
func _test_legacy_plain_id_falls_back_to_first_instance() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	# 额度端口接受技能ID：传技能ID时命中首实例，单实例语义与改动前完全一致。
	if not _controller.can_use_acquired_skill(0, DUPLICATE_SKILL_ID):
		return _fail("legacy_can_use_rejected")
	if not _controller.consume_acquired_skill_use(0, DUPLICATE_SKILL_ID):
		return _fail("legacy_consume_rejected")
	# 只有纯技能ID 的旧存档记录：按技能ID移除时必须仍然生效。
	if not _controller.remove_skill(0, DUPLICATE_SKILL_ID, "旧存档兼容测试"):
		return _fail("legacy_remove_rejected")
	if _controller.has_skill(0, DUPLICATE_SKILL_ID):
		return _fail("legacy_remove_left_skill")
	return true


## 权威存档往返：runtime_skill_data 必须随 PlayerState 一起保存与恢复。
func _test_state_round_trip_keeps_runtime_data() -> bool:
	_reset_state(2)
	if not _grant_two_instances():
		return false
	_controller.set_runtime_skill_data(0, SECOND_INSTANCE_KEY, {"timing":"roundStart"})
	# 原玩家状态；取其权威字典副本作为存档内容。
	var source_player: PlayerState = _controller.state.get_player(0)
	var saved_data: Dictionary = source_player.to_dict()
	# 恢复后的玩家状态；只验证运行时技能配置这一条链路。
	var restored_player: PlayerState = PlayerState.from_authoritative_dict(saved_data)
	if restored_player == null:
		return _fail("restore_returned_null")
	var restored_data: Dictionary = restored_player.runtime_skill_data.get(SECOND_INSTANCE_KEY, {}) as Dictionary
	if str(restored_data.get("timing", "")) != "roundStart":
		return _fail("runtime_data_lost restored=%s" % [restored_player.runtime_skill_data])
	# 首实例没有配置，恢复后也必须保持没有配置。
	if restored_player.runtime_skill_data.has(DUPLICATE_SKILL_ID):
		return _fail("unexpected_first_instance_data")
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("SKILL_INSTANCE_MULTIPLICITY_FAIL %s" % message)
	get_tree().quit(1)
	return false
