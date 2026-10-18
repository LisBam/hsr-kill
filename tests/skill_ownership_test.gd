extends Node

## 技能拥有查询专项回归：锁定「某角色此刻是否拥有技能X」的唯一权威入口与它的快照等价实现。
##
## 覆盖四个技能来源（固有 / 模式 / 临时 / 局内获得）、失去技能后的立刻收敛，
## 以及本次收敛修复的两处旧缺陷：
## 1. 旧 AI 技能枚举不按实际安装集合裁剪，会把已经被【留白】类效果失去的技能继续算成仍然拥有；
## 2. 旧【药理】联动只读武将固有技能列表，会漏判模式技能、临时技能与局内获得技能。

## 本次测试权威控制器；使用与正式场景同类型的实例并手动装配必需子节点。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 样例武将稳定ID；其固有【百折】声明了非零卖血价值，可同时验证 AI 侧读取口径。
const SAMPLE_CHARACTER_ID: String = "luka"

## 样例武将的两个固有技能稳定ID；与 luka.gd 的技能引用顺序保持一致。
const NATIVE_SKILL_IDS: Array[String] = ["baizhe", "zhidong"]

## 声明非零卖血价值的固有技能稳定ID；用于验证卖血价值只在技能仍在身上时才被计入。
const SELL_BLOOD_SKILL_ID: String = "baizhe"

## 不属于样例武将固有技能列表的普通技能；用于验证临时技能来源。
const TEMPORARY_SKILL_ID: String = "tianzhui"

## 不属于样例武将固有技能列表的普通技能；用于验证局内获得技能来源。
const ACQUIRED_SKILL_ID: String = "liubai"

## 权威快照中的“实际安装技能ID”字段名；缺失该字段表示旧快照，此时不做裁剪。
const INSTALLED_FIELD: String = "installed_skill_ids"

## 样例武将固有【百折】声明的卖血价值；测试按该数值断言 AI 侧累计结果。
const SELL_BLOOD_EXPECTED_VALUE: float = 1.0


## 延迟一帧执行全部断言，确保 GameDatabase 已完成武将、技能与卡牌目录扫描。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 按独立状态顺序执行全部断言；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_controller_native_and_lost_skill():
		return
	if not _test_controller_temporary_and_acquired_skill():
		return
	if not _test_snapshot_sources_and_trimming():
		return
	if not _test_snapshot_entries_agree():
		return
	if not _test_ai_sell_blood_respects_installed():
		return
	if not _test_yaoli_linkage_uses_unified_entry():
		return
	if not _test_empty_inputs_are_safe():
		return
	print("SKILL_OWNERSHIP_PASS native=2 lost=1 temporary=1 acquired=1 trim=1 agree=1 yaoli=1")
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
	_controller.state.match_id = "skill-ownership"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；统一使用样例武将，使固有技能集合可预测。
		var player: PlayerState = PlayerState.new(player_id, "技能查询测试玩家%d" % (player_id + 1))
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


## 构建玩家权威快照；overrides 直接并入玩家字典，用于切换技能来源与裁剪字段。
## 注意：快照侧统一入口接收的是**玩家快照**（character_id 位于顶层），而不是包含 players 数组的整局快照。
func _build_snapshot(overrides: Dictionary) -> Dictionary:
	# 玩家快照；字段与 PlayerState.to_dict 的公开部分保持一致。
	var player_snapshot: Dictionary = {
		"player_id":0,
		"identity":"leader",
		"identity_revealed":true,
		"alive":true,
		"out_of_game":false,
		"hp":4,
		"max_hp":4,
		"hand_count":0,
		"hand":[],
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage":[],
		"chained":false,
		"character_id":SAMPLE_CHARACTER_ID,
	}
	player_snapshot.merge(overrides, true)
	return player_snapshot


## 构建整局权威快照；部分技能判定（如【药理】联动）接收的是含 players 数组的整局快照。
## 只放入一号玩家，使其 player_id 与这些技能的 owner_player_id 一致。
func _build_match_snapshot(player_overrides: Dictionary) -> Dictionary:
	return {"players":[_build_snapshot(player_overrides)]}


## 权威侧入口：固有技能必须被识别，失去后必须立刻收敛，且不影响同角色的其他技能。
func _test_controller_native_and_lost_skill() -> bool:
	_reset_state(2)
	for skill_id: String in NATIVE_SKILL_IDS:
		if not _controller.has_skill(0, skill_id):
			return _fail("native_skill_not_detected skill=%s installed=%s" % [skill_id, _controller.get_installed_skill_ids(0)])
	# 非本武将技能必须为假；否则“拥有技能X”会退化成“拥有任意技能”。
	if _controller.has_skill(0, ACQUIRED_SKILL_ID):
		return _fail("foreign_skill_detected skill=%s" % ACQUIRED_SKILL_ID)
	if not _controller.remove_skill(0, SELL_BLOOD_SKILL_ID, "技能查询测试"):
		return _fail("remove_skill_rejected skill=%s" % SELL_BLOOD_SKILL_ID)
	if _controller.has_skill(0, SELL_BLOOD_SKILL_ID):
		return _fail("lost_skill_still_detected skill=%s" % SELL_BLOOD_SKILL_ID)
	# 失去是一次性事实而不是整表清空；同角色的其他技能必须保持可查询。
	if not _controller.has_skill(0, NATIVE_SKILL_IDS[1]):
		return _fail("sibling_skill_lost skill=%s" % NATIVE_SKILL_IDS[1])
	return true


## 权威侧入口：临时技能与局内获得技能都必须被识别，且查询严格按玩家隔离。
func _test_controller_temporary_and_acquired_skill() -> bool:
	_reset_state(2)
	if not _controller.grant_temporary_skill(0, TEMPORARY_SKILL_ID, 3):
		return _fail("grant_temporary_rejected skill=%s" % TEMPORARY_SKILL_ID)
	if not _controller.has_skill(0, TEMPORARY_SKILL_ID):
		return _fail("temporary_skill_not_detected skill=%s" % TEMPORARY_SKILL_ID)
	if not _controller.grant_acquired_skill(0, ACQUIRED_SKILL_ID):
		return _fail("grant_acquired_rejected skill=%s" % ACQUIRED_SKILL_ID)
	if not _controller.has_skill(0, ACQUIRED_SKILL_ID):
		return _fail("acquired_skill_not_detected skill=%s" % ACQUIRED_SKILL_ID)
	# 他人授予不得泄漏到其他玩家；否则“所有拥有技能X的角色”类效果会波及全场。
	if _controller.has_skill(1, TEMPORARY_SKILL_ID) or _controller.has_skill(1, ACQUIRED_SKILL_ID):
		return _fail("cross_player_leak installed1=%s" % [_controller.get_installed_skill_ids(1)])
	# 无效参数必须安全返回假；越界与负数ID不得抛错也不得误报。
	if _controller.has_skill(0, "") or _controller.has_skill(999, TEMPORARY_SKILL_ID) or _controller.has_skill(-1, TEMPORARY_SKILL_ID):
		return _fail("invalid_query_not_false")
	return true


## 旧【药理】联动缺陷的回归锁：该入口必须走统一快照判定，而不是只读武将固有技能列表。
## 触发条件：技能需要判断“持有者是否拥有技能X”时，若自行枚举武将定义的固有技能，
## 就会漏判模式技能、临时技能与局内获得技能（机缘授予、军功授予等），
## 也会把已经被【留白】类效果失去的技能继续算成拥有。
func _test_yaoli_linkage_uses_unified_entry() -> bool:
	# 【药理】独立实例；只需绑定宿主与持有者即可调用其私有判定，无需安装时机订阅。
	var yaoli: SkillDefinition = GameDatabase.create_skill("yaoli")
	if yaoli == null:
		return _fail("yaoli_missing")
	yaoli.bind(_controller, 0)
	# 场景一：旧实现在这里会返回假——技能只存在于局内获得记录，不在武将固有列表里。
	if not bool(yaoli.call("_owner_has_skill", _build_match_snapshot({"acquired_skills":{ACQUIRED_SKILL_ID:{"source":"test"}}}), ACQUIRED_SKILL_ID)):
		return _fail("yaoli_linkage_missed_acquired skill=%s" % ACQUIRED_SKILL_ID)
	# 场景二：临时技能同样必须被识别，证明该入口覆盖全部四类来源。
	if not bool(yaoli.call("_owner_has_skill", _build_match_snapshot({"temporary_skills":{TEMPORARY_SKILL_ID:{"expires_at_round":3}}}), TEMPORARY_SKILL_ID)):
		return _fail("yaoli_linkage_missed_temporary skill=%s" % TEMPORARY_SKILL_ID)
	# 场景三：固有技能仍必须为真，收敛不得把原有能力改坏。
	if not bool(yaoli.call("_owner_has_skill", _build_match_snapshot({}), SELL_BLOOD_SKILL_ID)):
		return _fail("yaoli_linkage_lost_native skill=%s" % SELL_BLOOD_SKILL_ID)
	# 场景四：权威快照明确未安装时，已失去的固有技能不得再被算成拥有。
	if bool(yaoli.call("_owner_has_skill", _build_match_snapshot({INSTALLED_FIELD:[NATIVE_SKILL_IDS[1]]}), SELL_BLOOD_SKILL_ID)):
		return _fail("yaoli_linkage_lost_skill_still_owned skill=%s" % SELL_BLOOD_SKILL_ID)
	return true


## 快照侧入口：四个来源齐全，且 installed_skill_ids 只裁剪固有与模式技能。
func _test_snapshot_sources_and_trimming() -> bool:
	# 旧快照缺少裁剪字段：固有技能必须全部可见，保持与改动前一致。
	var legacy_ids: Array[String] = SkillDefinition.collect_snapshot_skill_ids(_build_snapshot({}))
	for skill_id: String in NATIVE_SKILL_IDS:
		if not legacy_ids.has(skill_id):
			return _fail("legacy_snapshot_missing_native skill=%s ids=%s" % [skill_id, legacy_ids])
	# 权威快照明确未安装【百折】：它必须从拥有列表里消失。
	var trimmed_ids: Array[String] = SkillDefinition.collect_snapshot_skill_ids(_build_snapshot({INSTALLED_FIELD:[NATIVE_SKILL_IDS[1]]}))
	if trimmed_ids.has(SELL_BLOOD_SKILL_ID):
		return _fail("trimmed_native_still_listed ids=%s" % [trimmed_ids])
	if not trimmed_ids.has(NATIVE_SKILL_IDS[1]):
		return _fail("trimmed_snapshot_lost_installed ids=%s" % [trimmed_ids])
	# 临时与局内获得技能不参与裁剪：记录键存在即代表此刻拥有。
	var runtime_ids: Array[String] = SkillDefinition.collect_snapshot_skill_ids(_build_snapshot({
		INSTALLED_FIELD:[],
		"temporary_skills":{TEMPORARY_SKILL_ID:{"expires_at_round":3}},
		"acquired_skills":{ACQUIRED_SKILL_ID:{"source":"test"}},
	}))
	for skill_id: String in [TEMPORARY_SKILL_ID, ACQUIRED_SKILL_ID]:
		if not runtime_ids.has(skill_id):
			return _fail("runtime_skill_missing skill=%s ids=%s" % [skill_id, runtime_ids])
	# 模式技能与固有技能共用同一条裁剪规则。
	if SkillDefinition.collect_snapshot_skill_ids(_build_snapshot({"mode_skill_ids":[TEMPORARY_SKILL_ID], INSTALLED_FIELD:[]})).has(TEMPORARY_SKILL_ID):
		return _fail("trimmed_mode_still_listed skill=%s" % TEMPORARY_SKILL_ID)
	if not SkillDefinition.collect_snapshot_skill_ids(_build_snapshot({"mode_skill_ids":[TEMPORARY_SKILL_ID], INSTALLED_FIELD:[TEMPORARY_SKILL_ID]})).has(TEMPORARY_SKILL_ID):
		return _fail("installed_mode_dropped skill=%s" % TEMPORARY_SKILL_ID)
	return true


## 两个快照入口必须对同一快照给出一致答案；这是“拥有口径只有一份实现”的可执行证明。
func _test_snapshot_entries_agree() -> bool:
	# 待核对快照集合；覆盖无裁剪、全裁剪、部分裁剪、混合来源与空快照五种形态。
	var snapshots: Array[Dictionary] = [
		_build_snapshot({}),
		_build_snapshot({INSTALLED_FIELD:[]}),
		_build_snapshot({INSTALLED_FIELD:[SELL_BLOOD_SKILL_ID]}),
		_build_snapshot({
			INSTALLED_FIELD:[NATIVE_SKILL_IDS[1]],
			"mode_skill_ids":[TEMPORARY_SKILL_ID],
			"temporary_skills":{ACQUIRED_SKILL_ID:{}},
		}),
		{},
	]
	# 待核对技能ID全集；覆盖样例武将固有技能、模式技能与两个运行时技能。
	var probe_ids: Array[String] = NATIVE_SKILL_IDS.duplicate()
	probe_ids.append(TEMPORARY_SKILL_ID)
	probe_ids.append(ACQUIRED_SKILL_ID)
	for snapshot: Dictionary in snapshots:
		# 当前快照的拥有列表；成员判定必须与它逐项一致。
		var collected: Array[String] = SkillDefinition.collect_snapshot_skill_ids(snapshot)
		for skill_id: String in probe_ids:
			if collected.has(skill_id) != SkillDefinition.snapshot_has_skill(snapshot, skill_id):
				return _fail("entries_disagree skill=%s list=%s member=%s" % [skill_id, collected.has(skill_id), SkillDefinition.snapshot_has_skill(snapshot, skill_id)])
		# 列表中的每一项都必须被成员判定确认；否则两者仍可能给出不同的“拥有”集合。
		for skill_id: String in collected:
			if not SkillDefinition.snapshot_has_skill(snapshot, skill_id):
				return _fail("collected_not_member skill=%s" % skill_id)
	return true


## AI 侧卖血估值必须服从实际安装集合；这正是旧枚举漏裁剪造成的缺陷。
func _test_ai_sell_blood_respects_installed() -> bool:
	# 独立评估器实例；卖血估值是纯函数，不依赖控制器状态。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 旧快照不裁剪：样例武将的【百折】必须按声明值计入。
	var legacy_value: float = evaluator.get_snapshot_sell_blood_value(_build_snapshot({}))
	if not is_equal_approx(legacy_value, SELL_BLOOD_EXPECTED_VALUE):
		return _fail("legacy_sell_blood=%s" % legacy_value)
	# 权威快照明确未安装【百折】：卖血价值必须归零，否则 AI 会为已经不存在的技能让路。
	var lost_snapshot: Dictionary = _build_snapshot({INSTALLED_FIELD:[NATIVE_SKILL_IDS[1]]})
	var lost_value: float = evaluator.get_snapshot_sell_blood_value(lost_snapshot)
	if not is_zero_approx(lost_value):
		return _fail("lost_sell_blood_still_counted=%s" % lost_value)
	# 运行时获得的卖血技能同样计入；证明读取口径覆盖全部来源而不是只读武将固有列表。
	var acquired_snapshot: Dictionary = _build_snapshot({INSTALLED_FIELD:[], "acquired_skills":{SELL_BLOOD_SKILL_ID:{"source":"test"}}})
	var acquired_value: float = evaluator.get_snapshot_sell_blood_value(acquired_snapshot)
	if not is_equal_approx(acquired_value, SELL_BLOOD_EXPECTED_VALUE):
		return _fail("acquired_sell_blood=%s" % acquired_value)
	return true


## 空输入必须安全返回空结果与假；两个入口都不允许因缺字段崩溃。
func _test_empty_inputs_are_safe() -> bool:
	if not SkillDefinition.collect_snapshot_skill_ids({}).is_empty():
		return _fail("empty_snapshot_not_empty")
	if SkillDefinition.snapshot_has_skill({}, SELL_BLOOD_SKILL_ID):
		return _fail("empty_snapshot_has_skill")
	if SkillDefinition.snapshot_has_skill(_build_snapshot({}), ""):
		return _fail("empty_skill_id_has_skill")
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("SKILL_OWNERSHIP_FAIL %s" % message)
	get_tree().quit(1)
	return false
