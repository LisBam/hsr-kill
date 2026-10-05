extends Node

## 选将阶段 AI 等待门禁回归。验证「多名玩家同时选将」阶段必须等全部真人确认后 AI 才分配武将，
## 且该等待与「自选座次身份」开关无关；同时验证无真人时不会死锁、有真人时保持同调用栈推进。

## 测试专用设置文件；本用例修改的开局偏好不会写入玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://character_selection_timing_test_settings.cfg"

## 身份局等待门禁用例的玩家人数；三人局保证真人之外至少存在两名AI，覆盖「领袖由AI担任」的实际开局路径。
const IDENTITY_PLAYER_COUNT: int = 3

## 斗地主等待门禁用例的玩家人数；三人斗地主为最小完整牌局。
const DOUDIZHU_PLAYER_COUNT: int = 3

## 2v2 等待门禁用例的玩家人数；该模式仅支持四人。
const TEAM2V2_PLAYER_COUNT: int = 4

## 本地真人的稳定玩家ID；固定为0并关闭随机座次，使「真人是否担任首任领袖」只由身份分配决定。
const LOCAL_HUMAN_PLAYER_ID: int = 0

## 无真人对局使用的玩家ID；负值表示本局不指派本地真人，用于验证全AI开局不会死锁。
const NO_HUMAN_PLAYER_ID: int = -1

## 扫描首任领袖用的最大种子数；从小整数稳定扫描，避免硬编码某一随机算法之外的种子。
const SEED_SCAN_LIMIT: int = 65

## 测试前设置文件路径；结束时恢复。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 测试前自选座次身份开关；结束时恢复实际原值。
var _original_custom_assignment_enabled: bool = false

## 测试前AI自选武将开关；结束时恢复实际原值。
var _original_customize_ai_characters_enabled: bool = false

## 测试前控制全部角色开关；结束时恢复实际原值，避免玩家配置影响AI控制权判定。
var _original_control_all_characters_enabled: bool = false

## 测试前手气卡次数；结束时恢复实际原值，避免开局换牌干扰选将断言。
var _original_mulligan_limit: int = 0

## 测试使用的权威控制器；按正式子组件名称装配。
var _controller: MatchController


## 延迟执行，确保自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证身份局、斗地主、2v2 的同时选将等待、无真人对局不死锁，以及自选开关开启时的既有等待语义。
func _run() -> void:
	_begin_settings_isolation()
	if not _test_identity_defers_ai_until_human_confirms():
		return
	if not _test_doudizhu_defers_ai_until_human_confirms():
		return
	if not _test_team2v2_defers_ai_until_human_confirms():
		return
	if not _test_all_ai_match_completes_without_human():
		return
	if not _test_custom_assignment_still_defers():
		return
	_restore_settings()
	# 成功出口显式释放权威对局，避免测试进程退出时残留ObjectDB实例诊断。
	if _controller != null and is_instance_valid(_controller):
		_controller.abandon_match()
	_controller = null
	print("CHARACTER_SELECTION_TIMING_PASS identity+doudizhu+team2v2+all_ai+custom_assignment")
	get_tree().quit(0)


## 验证身份局在「首任领袖由AI担任」时，AI必须先等待真人确认才分配其余武将。
func _test_identity_defers_ai_until_human_confirms() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	# 能让真人不是首任领袖的种子；此时首任领袖由AI担任，开局驱动后必然进入「其他玩家同时选将」阶段。
	var ai_leader_seed: int = -1
	for candidate_seed: int in range(1, SEED_SCAN_LIMIT):
		if not _controller.start_match(IDENTITY_PLAYER_COUNT, candidate_seed, IdentityRules.MODE_IDENTITY):
			return _fail("identity_start seed=%d" % candidate_seed)
		if _controller.character_selection.get_initial_identity(LOCAL_HUMAN_PLAYER_ID) != "leader":
			ai_leader_seed = candidate_seed
			break
	if ai_leader_seed < 0:
		return _fail("identity_ai_leader_seed_not_found scanned=%d" % SEED_SCAN_LIMIT)
	# AI首任领袖已在开局驱动内确认，阶段必须停在「其他玩家同时选将」，而不是直接完成。
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_OTHERS:
		return _fail("identity_phase_should_be_others actual=%s seed=%d" % [_controller.character_selection.phase, ai_leader_seed])
	# 当前待确认玩家；真人必须仍在集合内，即AI没有把整个阶段推进到完成。
	var pending_ids: Array[int] = _controller.character_selection.get_pending_player_ids()
	if not pending_ids.has(LOCAL_HUMAN_PLAYER_ID):
		return _fail("identity_human_should_remain_pending pending=%s seed=%d" % [str(pending_ids), ai_leader_seed])
	# 真人当前武将结果；必须为空，保证等待期间没有任何一方代真人落定武将。
	if _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID) != "":
		return _fail("identity_ai_must_not_confirm_for_human selection=%s seed=%d" % [_controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID), ai_leader_seed])
	# 真人是否仍可选将；等待期间必须保持可提交，否则界面会给出无法确认的选将窗口。
	if not _controller.character_selection.can_player_select(LOCAL_HUMAN_PLAYER_ID):
		return _fail("identity_human_should_still_select seed=%d" % ai_leader_seed)
	# 真人候选武将；等待期间必须仍然可用——AI 提前确认会取走真人候选中的同一张，使真人提交被拒。
	var candidates: Array[String] = _controller.character_selection.get_candidates(LOCAL_HUMAN_PLAYER_ID)
	if candidates.is_empty():
		return _fail("identity_human_candidates_empty seed=%d" % ai_leader_seed)
	# 本次缺陷的核心判别式：真人未确认期间，除首任领袖外不得有任何玩家（AI）确认武将。
	# 仅断言“真人仍待确认”是空泛的——循环本就会跳过非AI座位，因此必须断言AI侧确实没有提前落定。
	if not _assert_only_leader_confirmed("identity", ai_leader_seed):
		return false
	# 真人本次提交的武将；取首张以复现实机「点到候选第一张」的路径。
	var submitted_character_id: String = candidates[0]
	if not _controller.select_character(LOCAL_HUMAN_PLAYER_ID, submitted_character_id):
		return _fail("identity_human_submit_rejected character=%s seed=%d" % [submitted_character_id, ai_leader_seed])
	# 真人确认后AI必须在同一次调用内完成，不得依赖额外帧；否则会改变既有同步推进语义。
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		return _fail("identity_not_complete_in_same_call phase=%s seed=%d" % [_controller.character_selection.phase, ai_leader_seed])
	if _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID) != submitted_character_id:
		return _fail("identity_human_selection_changed expected=%s actual=%s" % [submitted_character_id, _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID)])
	return _assert_every_player_has_character("identity")


## 验证斗地主在自选座次身份关闭时同样等待真人确认。
func _test_doudizhu_defers_ai_until_human_confirms() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(DOUDIZHU_PLAYER_COUNT, 20260720, IdentityRules.MODE_DOUDIZHU):
		return _fail("doudizhu_start")
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_OTHERS:
		return _fail("doudizhu_phase_should_be_others actual=%s" % _controller.character_selection.phase)
	var pending_ids: Array[int] = _controller.character_selection.get_pending_player_ids()
	if not pending_ids.has(LOCAL_HUMAN_PLAYER_ID):
		return _fail("doudizhu_human_should_remain_pending pending=%s" % str(pending_ids))
	if _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID) != "":
		return _fail("doudizhu_ai_must_not_confirm_for_human selection=%s" % _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID))
	# 斗地主没有领袖阶段，因此真人未确认期间任何座位都不得确认武将。
	if not _assert_no_player_confirmed("doudizhu"):
		return false
	var candidates: Array[String] = _controller.character_selection.get_candidates(LOCAL_HUMAN_PLAYER_ID)
	if candidates.is_empty():
		return _fail("doudizhu_human_candidates_empty")
	if not _controller.select_character(LOCAL_HUMAN_PLAYER_ID, candidates[0]):
		return _fail("doudizhu_human_submit_rejected character=%s" % candidates[0])
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		return _fail("doudizhu_not_complete_in_same_call phase=%s" % _controller.character_selection.phase)
	return _assert_every_player_has_character("doudizhu")


## 验证 2v2 在自选座次身份关闭时同样等待真人确认。
func _test_team2v2_defers_ai_until_human_confirms() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(TEAM2V2_PLAYER_COUNT, 20260721, IdentityRules.MODE_TEAM2V2):
		return _fail("team2v2_start")
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_OTHERS:
		return _fail("team2v2_phase_should_be_others actual=%s" % _controller.character_selection.phase)
	var pending_ids: Array[int] = _controller.character_selection.get_pending_player_ids()
	if not pending_ids.has(LOCAL_HUMAN_PLAYER_ID):
		return _fail("team2v2_human_should_remain_pending pending=%s" % str(pending_ids))
	if _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID) != "":
		return _fail("team2v2_ai_must_not_confirm_for_human selection=%s" % _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID))
	# 2v2 同样没有领袖阶段，真人未确认期间任何座位都不得确认武将。
	if not _assert_no_player_confirmed("team2v2"):
		return false
	var candidates: Array[String] = _controller.character_selection.get_candidates(LOCAL_HUMAN_PLAYER_ID)
	if candidates.is_empty():
		return _fail("team2v2_human_candidates_empty")
	if not _controller.select_character(LOCAL_HUMAN_PLAYER_ID, candidates[0]):
		return _fail("team2v2_human_submit_rejected character=%s" % candidates[0])
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		return _fail("team2v2_not_complete_in_same_call phase=%s" % _controller.character_selection.phase)
	return _assert_every_player_has_character("team2v2")


## 验证无真人对局（全AI）不会被等待门禁卡死，开局驱动即完成全部选将。
func _test_all_ai_match_completes_without_human() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	_controller.local_human_player_id = NO_HUMAN_PLAYER_ID
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(IDENTITY_PLAYER_COUNT, 20260723, IdentityRules.MODE_IDENTITY):
		return _fail("all_ai_start")
	# 全AI局没有任何真人待办，门禁必须放行并在开局驱动内一次完成。
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		return _fail("all_ai_should_complete_without_waiting phase=%s pending=%s" % [_controller.character_selection.phase, str(_controller.character_selection.get_pending_player_ids())])
	# 全AI局不得注册任何AI策略缺失的座位；该断言同时保证上面的放行不是靠“协调器缺失”换来的。
	for player: PlayerState in _controller.state.players:
		if not _controller.ai_coordinator.is_ai_controlled(player.player_id):
			return _fail("all_ai_player_without_policy player_id=%d" % player.player_id)
	return _assert_every_player_has_character("all_ai")


## 验证自选座次身份开启时的既有等待语义未被破坏（回归保护：该路径改动前就已正确）。
func _test_custom_assignment_still_defers() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(true)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	# 能让真人不是首任领袖的种子；自选开关开启时首任领袖确认后进入最终自选阶段。
	var custom_seed: int = -1
	for candidate_seed: int in range(1, SEED_SCAN_LIMIT):
		if not _controller.start_match(IDENTITY_PLAYER_COUNT, candidate_seed, IdentityRules.MODE_IDENTITY):
			return _fail("custom_start seed=%d" % candidate_seed)
		if _controller.character_selection.get_initial_identity(LOCAL_HUMAN_PLAYER_ID) != "leader":
			custom_seed = candidate_seed
			break
	if custom_seed < 0:
		return _fail("custom_ai_leader_seed_not_found scanned=%d" % SEED_SCAN_LIMIT)
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_CUSTOM:
		return _fail("custom_phase_should_be_custom actual=%s seed=%d" % [_controller.character_selection.phase, custom_seed])
	if not _controller.character_selection.get_pending_player_ids().has(LOCAL_HUMAN_PLAYER_ID):
		return _fail("custom_human_should_remain_pending pending=%s seed=%d" % [str(_controller.character_selection.get_pending_player_ids()), custom_seed])
	if _controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID) != "":
		return _fail("custom_ai_must_not_confirm_for_human selection=%s seed=%d" % [_controller.character_selection.get_selection(LOCAL_HUMAN_PLAYER_ID), custom_seed])
	return true


## 断言除首任领袖外没有任何玩家确认武将；领袖在领袖阶段确认属于既有规则，其余座位提前确认即为本次要修的缺陷。
## 该断言是本次修复的核心判别式：只断言「真人仍待确认」是空泛的，因为AI驱动本来就会跳过非AI座位。
func _assert_only_leader_confirmed(case_name: String, seed_value: int) -> bool:
	# 本局首任领袖的稳定玩家ID；该座位在领袖阶段合法确认，必须从断言中排除。
	var leader_player_id: int = _controller.character_selection.leader_player_id
	for player: PlayerState in _controller.state.players:
		if player.player_id == leader_player_id:
			continue
		if _controller.character_selection.get_selection(player.player_id) != "":
			return _fail("%s_ai_confirmed_before_human player_id=%d selection=%s leader=%d seed=%d" % [case_name, player.player_id, _controller.character_selection.get_selection(player.player_id), leader_player_id, seed_value])
	return true


## 断言没有任何玩家确认武将；用于没有领袖阶段的模式（斗地主、2v2），此时领袖例外不成立。
func _assert_no_player_confirmed(case_name: String) -> bool:
	for player: PlayerState in _controller.state.players:
		if _controller.character_selection.get_selection(player.player_id) != "":
			return _fail("%s_ai_confirmed_before_human player_id=%d selection=%s pending=%s" % [case_name, player.player_id, _controller.character_selection.get_selection(player.player_id), str(_controller.character_selection.get_pending_player_ids())])
	return true


## 断言全部玩家都已确认武将；失败信息列出仍在待确认集合中的玩家，便于定位卡在谁身上。
func _assert_every_player_has_character(case_name: String) -> bool:
	for player: PlayerState in _controller.state.players:
		if _controller.character_selection.get_selection(player.player_id) == "":
			return _fail("%s_player_without_character player_id=%d pending=%s" % [case_name, player.player_id, str(_controller.character_selection.get_pending_player_ids())])
	return true


## 创建离线模式的最小正式控制器组件树；与正式主场景使用同一组件组合方式。
func _create_controller(network_mode: NetworkGateway.Mode) -> void:
	if _controller != null and is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；控制器依赖它派发阶段事件。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；等待门禁通过它判断某座位是否由内置AI控制。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 网络网关；离线模式保证本地真人为唯一真人输入源。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	network_gateway.mode = network_mode
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = LOCAL_HUMAN_PLAYER_ID
	# 关闭本地座次随机；让「真人是否首任领袖」只由身份分配决定，便于稳定复现等待路径。
	_controller.randomize_local_human_seat = false
	# 关闭流程与AI动作延时；等待语义必须由门禁本身决定，不能靠帧间隔掩盖。
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 把本用例全部设置写入独立临时文件，并保存需要恢复的正式状态。
func _begin_settings_isolation() -> void:
	_original_settings_file_path = GameSettings.get_settings_file_path()
	_original_custom_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_original_customize_ai_characters_enabled = GameSettings.customize_ai_characters_enabled
	_original_control_all_characters_enabled = GameSettings.control_all_characters_enabled
	_original_mulligan_limit = GameSettings.mulligan_limit
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)


## 恢复设置、清空临时写盘并删除测试文件。
func _restore_settings() -> void:
	GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment_enabled)
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai_characters_enabled)
	GameSettings.set_control_all_characters_enabled(_original_control_all_characters_enabled)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))


## 失败出口；恢复设置后输出稳定错误标记并退出非零状态。
func _fail(reason: String) -> bool:
	_restore_settings()
	printerr("CHARACTER_SELECTION_TIMING_FAIL %s" % reason)
	get_tree().quit(1)
	return false
