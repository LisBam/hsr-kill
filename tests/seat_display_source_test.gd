extends Node

## 座次显示同源回归。验证选将期间牌桌座次标签（快照 `seat_number`，即玩家数组下标+1）与权威座次序
## （选将标题读取的同一来源）在全部模式下完全一致，并且选将完成后不出现座次跳变。

## 测试专用设置文件；本用例修改的开局偏好不会写入玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://seat_display_source_test_settings.cfg"

## 身份局用例人数；八人局使首任领袖更可能不落在创建下标0，从而让两套座次口径真实分离。
const IDENTITY_PLAYER_COUNT: int = 8

## 斗地主用例人数；三人局为最小完整牌局，且地主固定一号位。
const DOUDIZHU_PLAYER_COUNT: int = 3

## 2v2 用例人数；该模式仅支持四人。
const TEAM2V2_PLAYER_COUNT: int = 4

## 本地真人的稳定玩家ID；同时等于创建下标，用于把“创建顺序”与“最终座次”分离观察。
const LOCAL_HUMAN_PLAYER_ID: int = 0

## 扫描首任领袖用的最大种子数；从小整数稳定扫描，不依赖某个固定种子的身份分布。
const SEED_SCAN_LIMIT: int = 128

## 测试前设置文件路径；结束时恢复。
var _original_settings_file_path: String = "user://game_settings.cfg"

## 测试前自选座次身份开关；结束时恢复实际原值。
var _original_custom_assignment_enabled: bool = false

## 测试前AI自选武将开关；结束时恢复实际原值。
var _original_customize_ai_characters_enabled: bool = false

## 测试前手气卡次数；结束时恢复实际原值，避免开局换牌干扰座次断言。
var _original_mulligan_limit: int = 0

## 测试使用的权威控制器；按正式子组件名称装配。
var _controller: MatchController


## 延迟执行，确保自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证身份局座次同源、选将前后无跳变、斗地主显示名同源，以及无首任身份模式的座次稳定。
func _run() -> void:
	_begin_settings_isolation()
	if not _test_identity_seats_share_one_source():
		return
	if not _test_doudizhu_display_names_share_one_source():
		return
	if not _test_modes_without_first_identity_keep_creation_order():
		return
	_restore_settings()
	# 成功出口显式释放权威对局，避免测试进程退出时残留ObjectDB实例诊断。
	if _controller != null and is_instance_valid(_controller):
		_controller.abandon_match()
	_controller = null
	print("SEAT_DISPLAY_SOURCE_PASS identity+doudizhu+team2v2")
	get_tree().quit(0)


## 验证身份局选将期间每个座位的快照座次都等于权威座次，且该座次在选将完成后不再变化。
func _test_identity_seats_share_one_source() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	# 能让首任领袖不落在创建下标0的种子；只有此时“创建顺序”与“最终座次”才会真实分离，
	# 断言才具备区分力。领袖的稳定 player_id 恒等于其创建下标，因此该判据在修复前后同样可算。
	var separated_seed: int = -1
	for candidate_seed: int in range(1, SEED_SCAN_LIMIT):
		if not _controller.start_match(IDENTITY_PLAYER_COUNT, candidate_seed, IdentityRules.MODE_IDENTITY):
			return _fail("identity_start seed=%d" % candidate_seed)
		if _controller.character_selection.leader_player_id != LOCAL_HUMAN_PLAYER_ID:
			separated_seed = candidate_seed
			break
	if separated_seed < 0:
		return _fail("identity_separated_seed_not_found scanned=%d" % SEED_SCAN_LIMIT)
	# AI首任领袖在开局驱动内确认领袖武将后立即推进到“其他玩家同时选将”，并在真人确认前停住；
	# 因此本用例在该阶段观察座次，此时两套座次口径若不同源就会直接暴露。
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_OTHERS:
		return _fail("identity_phase_should_be_others actual=%s seed=%d" % [_controller.character_selection.phase, separated_seed])
	# 选将期间的逐玩家快照座次；这是牌桌座次标签与在局日志直接读取的值。
	var during_selection_seats: Dictionary = _collect_snapshot_seats()
	if not _assert_snapshot_seats_match_authoritative("identity_during_selection", separated_seed):
		return false
	# 本地玩家在选将标题中展示的座次；它来自服务权威值，必须与同一玩家在快照中的座次一致。
	var local_snapshot_seat: int = int(during_selection_seats.get(LOCAL_HUMAN_PLAYER_ID, -1))
	var local_authoritative_seat: int = _controller.character_selection.get_initial_seat_number(LOCAL_HUMAN_PLAYER_ID)
	if local_snapshot_seat != local_authoritative_seat:
		return _fail("identity_local_title_seat_mismatch snapshot_seat=%d authoritative_seat=%d seed=%d" % [local_snapshot_seat, local_authoritative_seat, separated_seed])
	# 首任领袖固定一号位；数组首位即最终座次首位，必须在选将期间就已成立。
	if str(_controller.state.players[0].identity) != "leader":
		return _fail("identity_first_array_slot_should_be_leader actual_player_id=%d identity=%s seed=%d" % [_controller.state.players[0].player_id, str(_controller.state.players[0].identity), separated_seed])
	# 真人确认后选将立即完成；AI 在同一调用栈内补选，因此随后可复核“无事后跳变”。
	var candidates: Array[String] = _controller.character_selection.get_candidates(LOCAL_HUMAN_PLAYER_ID)
	if candidates.is_empty():
		return _fail("identity_local_candidates_empty seed=%d" % separated_seed)
	if not _controller.select_character(LOCAL_HUMAN_PLAYER_ID, candidates[0]):
		return _fail("identity_local_submit_rejected character=%s seed=%d" % [candidates[0], separated_seed])
	if _controller.character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		return _fail("identity_selection_not_complete phase=%s seed=%d" % [_controller.character_selection.phase, separated_seed])
	# 选将完成后的逐玩家快照座次；必须与选将期间逐玩家相等，否则玩家会看到座位“跳变”。
	var after_selection_seats: Dictionary = _collect_snapshot_seats()
	return _assert_seats_unchanged("identity_after_selection", during_selection_seats, after_selection_seats)


## 验证斗地主在创建后重排座次时同步刷新显示名：显示名中的座次编号必须等于快照座次。
func _test_doudizhu_display_names_share_one_source() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(DOUDIZHU_PLAYER_COUNT, 20260720, IdentityRules.MODE_DOUDIZHU):
		return _fail("doudizhu_start")
	if not _assert_snapshot_seats_match_authoritative("doudizhu_during_selection", 20260720):
		return false
	return _assert_display_names_match_seats("doudizhu")


## 验证 2v2 在创建时座次已固定，因此快照座次等于权威座次（回归保护：该模式不受本次重排影响）。
func _test_modes_without_first_identity_keep_creation_order() -> bool:
	_create_controller(NetworkGateway.Mode.OFFLINE)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_mulligan_limit(0)
	if not _controller.start_match(TEAM2V2_PLAYER_COUNT, 20260721, IdentityRules.MODE_TEAM2V2):
		return _fail("team2v2_start")
	if not _assert_snapshot_seats_match_authoritative("team2v2_during_selection", 20260721):
		return false
	return _assert_display_names_match_seats("team2v2")


## 返回当前快照中“稳定玩家ID → 座次号”的映射；座次号来自快照字段，等价于玩家数组下标加1。
func _collect_snapshot_seats() -> Dictionary:
	# 本地观察者快照；座次字段对所有观察者一致，使用本地真人视角即可。
	var snapshot: Dictionary = _controller.state.to_dict(LOCAL_HUMAN_PLAYER_ID, false)
	# 快照玩家数组；每项至少包含稳定玩家ID、座次号与显示名。
	var serialized_players: Array = snapshot.get("players", [])
	# 收集结果；键为稳定玩家ID，值为该玩家在快照中的座次号。
	var seats_by_player_id: Dictionary = {}
	for entry: Dictionary in serialized_players:
		seats_by_player_id[int(entry.get("player_id", -1))] = int(entry.get("seat_number", -1))
	return seats_by_player_id


## 断言快照座次与选将服务的权威座次逐玩家相等；失败信息同时给出两侧数值与该玩家的创建下标。
func _assert_snapshot_seats_match_authoritative(case_name: String, seed_value: int) -> bool:
	# 当前快照座次映射；键为稳定玩家ID。
	var snapshot_seats: Dictionary = _collect_snapshot_seats()
	for player: PlayerState in _controller.state.players:
		# 该玩家的权威座次；与选将标题读取的是同一来源。
		var authoritative_seat: int = _controller.character_selection.get_initial_seat_number(player.player_id)
		# 该玩家在快照中的座次；牌桌座次标签与在局日志读取此值。
		var snapshot_seat: int = int(snapshot_seats.get(player.player_id, -1))
		if snapshot_seat != authoritative_seat:
			return _fail("%s seat_source_mismatch player_id=%d snapshot_seat=%d authoritative_seat=%d seed=%d" % [case_name, player.player_id, snapshot_seat, authoritative_seat, seed_value])
	return true


## 断言两名单的快照座次逐玩家保持不变；失败信息给出发生跳变的玩家与前后数值。
func _assert_seats_unchanged(case_name: String, before_seats: Dictionary, after_seats: Dictionary) -> bool:
	for player_id: int in before_seats.keys():
		# 该玩家在跳变检查前的座次；来源为选将期间的快照。
		var before_seat: int = int(before_seats.get(player_id, -1))
		# 该玩家在跳变检查后的座次；来源为选将完成后的快照。
		var after_seat: int = int(after_seats.get(player_id, -1))
		if before_seat != after_seat:
			return _fail("%s seat_jumped player_id=%d before_seat=%d after_seat=%d" % [case_name, player_id, before_seat, after_seat])
	return true


## 断言每名玩家的显示名编号等于其座次号；显示名与座次不同源时玩家会看到“名字与座位对不上”。
func _assert_display_names_match_seats(case_name: String) -> bool:
	# 本地观察者快照；显示名与座次字段对所有观察者一致。
	var snapshot: Dictionary = _controller.state.to_dict(LOCAL_HUMAN_PLAYER_ID, false)
	for entry: Dictionary in snapshot.get("players", []):
		# 该玩家的稳定ID与座次号；座次号是牌桌座次标签的显示值。
		var player_id: int = int(entry.get("player_id", -1))
		var seat_number: int = int(entry.get("seat_number", -1))
		# 该玩家的显示名；形如“玩家3”或“[AI]玩家3”，末尾数字即显示名声明的座次。
		var display_name: String = str(entry.get("display_name", ""))
		# 显示名末尾的连续数字；缺失时判为不一致并输出原文。
		var digits: String = ""
		for char_index: int in range(display_name.length() - 1, -1, -1):
			var current_char: String = display_name[char_index]
			if current_char.is_valid_int():
				digits = current_char + digits
			else:
				break
		if digits.is_empty() or digits.to_int() != seat_number:
			return _fail("%s display_name_seat_mismatch player_id=%d display_name=%s seat_number=%d" % [case_name, player_id, display_name, seat_number])
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
	# AI协调器；座次显示名按它判断某座位是否由内置AI控制。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 网络网关；离线模式保证没有局域网昵称参与显示名解析。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	network_gateway.mode = network_mode
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = LOCAL_HUMAN_PLAYER_ID
	# 关闭本地座次随机；让本地真人的创建下标恒为0，从而让“创建顺序”与“最终座次”分离只由领袖位置决定。
	_controller.randomize_local_human_seat = false
	# 关闭流程与AI动作延时；座次同源必须由创建期排序本身保证，不能靠帧间隔掩盖。
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 把本用例全部设置写入独立临时文件，并保存需要恢复的正式状态。
func _begin_settings_isolation() -> void:
	_original_settings_file_path = GameSettings.get_settings_file_path()
	_original_custom_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_original_customize_ai_characters_enabled = GameSettings.customize_ai_characters_enabled
	_original_mulligan_limit = GameSettings.mulligan_limit
	GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)


## 恢复设置、清空临时写盘并删除测试文件。
func _restore_settings() -> void:
	GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment_enabled)
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai_characters_enabled)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.flush_pending_settings()
	GameSettings.set("_settings_file_path", _original_settings_file_path)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH))


## 失败出口；恢复设置后输出稳定错误标记并退出非零状态。
func _fail(reason: String) -> bool:
	_restore_settings()
	printerr("SEAT_DISPLAY_SOURCE_FAIL %s" % reason)
	get_tree().quit(1)
	return false
