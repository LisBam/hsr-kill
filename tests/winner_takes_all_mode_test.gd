extends Node

## 胜者为王模式回归。
##
## 覆盖四层口径：
## 1) 规则层：模式注册、身份表、人数支持、身份公开、队友关系、击杀奖惩、座次补偿数值与胜负判定。
## 2) 设置层：分模式人数槽、座次补偿开关的读写。
## 3) 适配层：大厅模式登记与可玩判定、AI 全员敌对态度。
## 4) 对局层：真实开局后座次补偿的手牌与体力上限落点、仅剩一名存活者时的获胜 ID。
##
## 本用例不需要图形界面，可在 `--headless` 下回归。

## 权威对局控制器；与正式场景组件结构保持一致。
var _controller: MatchController

## 身份规则服务；用于在控制器外直接断言纯规则逻辑。
var _identity_rules: IdentityRules = IdentityRules.new()

## 测试开始前的 AI 调整开关；结束时还原，避免污染其他设置。
var _original_customize_ai: bool = false

## 测试开始前的自选座次开关；结束时还原。
var _original_custom_assignment: bool = false

## 测试开始前的对局模式；结束时还原。
var _original_match_mode: String = "identity"

## 测试开始前的座次补偿开关；结束时还原。
var _original_seat_compensation: bool = false

## 测试开始前的手气卡张数；结束时还原。
var _original_mulligan_limit: int = 0

## 最近一次等待发牌超时时停留的公开阶段；仅用于失败诊断信息。
var _last_stuck_phase: String = ""

## 最近一次等待发牌超时时仍未确认的玩家 ID 列表；仅用于失败诊断信息。
var _last_stuck_pending: String = ""

## 发牌窗口结束时捕获到的各座次手牌数；索引为座次-1（即 state.players 下标）。
## 必须在 gameDrawAfter 时机取样：此时起始手牌刚发完，而 gameStart 时机的武将技能摸牌尚未发生。
var _dealt_hand_by_seat: Array[int] = []

## 是否已经捕获到发牌窗口结束时的座次手牌快照。
var _deal_window_captured: bool = false

## 需要核对“界面接线”的场景路径；每项为 [场景资源路径, 该场景内必须能解析的唯一名列表]。
## 存在的意义：`%唯一名` 在节点缺失时只会于运行时抛错，而字体色审计遍历不到不存在的节点，
## 因此“脚本引用了节点但场景里没有它”不会被任何既有用例发现，必须在此显式断言。
const SCENE_WIRING_CHECKS: Array = [
	[
		"res://scenes/main.tscn",
		[
			"WinnerTakesAllModeButton",
			"WinnerTakesAllModeName",
			"WinnerTakesAllModePlayerCount",
			"WinnerTakesAllModeIndicator",
			"MainMenuSeatCompensationCheckBox",
			"SeatCompensationCheckBox",
		],
	],
	[
		"res://scenes/components/lan_lobby_panel.tscn",
		["SeatCompensationRow", "LanSeatCompensationCheckBox"],
	],
	[
		"res://scenes/components/online_lobby_panel.tscn",
		["SeatCompensationRow", "OnlineLobbySeatCompensationCheckBox"],
	],
]


## 延迟执行，确保自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行规则层、设置层、适配层与对局层断言；任一失败立即停止。
func _run() -> void:
	if GameSettings != null:
		_original_customize_ai = GameSettings.customize_ai_characters_enabled
		_original_custom_assignment = GameSettings.custom_character_assignment_enabled
		_original_match_mode = str(GameSettings.next_match_mode)
		_original_seat_compensation = GameSettings.seat_compensation_enabled
		_original_mulligan_limit = GameSettings.mulligan_limit
		GameSettings.set_customize_ai_characters_enabled(false)
		if GameSettings.has_method("set_custom_character_assignment_enabled"):
			GameSettings.set_custom_character_assignment_enabled(false)
		# 手气卡置0：起始手牌分发后直接进入首回合，用例可以稳定观察发牌结果。
		GameSettings.set_mulligan_limit(0)
	if not _test_identity_rules_pure():
		_restore_settings()
		return
	if not _test_seat_compensation_values():
		_restore_settings()
		return
	if not _test_settings_player_count_and_switch():
		_restore_settings()
		return
	if not _test_lobby_registration():
		_restore_settings()
		return
	if not _test_scene_wiring():
		_restore_settings()
		return
	if not _test_winner_id_and_text_mapping():
		_restore_settings()
		return
	if not _test_ai_attitude_all_hostile():
		_restore_settings()
		return
	if not await _test_match_bootstrap_without_seat_compensation():
		_restore_settings()
		return
	if not _test_winner_evaluation():
		_restore_settings()
		return
	if not await _test_seat_compensation_opening_numbers():
		_restore_settings()
		return
	_restore_settings()
	print("WINNER_TAKES_ALL_MODE_PASS rules+seat_compensation+settings+lobby+scene_wiring+winner+ai+bootstrap+opening_numbers")
	get_tree().quit(0)


## 规则层纯断言：模式注册、身份表、人数、首任身份、首回合、身份公开、队友关系与击杀奖惩。
func _test_identity_rules_pure() -> bool:
	if _identity_rules.normalize_mode("winner_takes_all") != IdentityRules.MODE_WINNER_TAKES_ALL:
		return _fail("normalize_mode_not_registered")
	if IdentityRules.MODE_WINNER_TAKES_ALL != "winner_takes_all":
		return _fail("mode_id_drift=%s" % IdentityRules.MODE_WINNER_TAKES_ALL)
	# 人数：2至10人全部支持，1人与11人不支持。
	var supported: Array[int] = _identity_rules.get_supported_player_counts(IdentityRules.MODE_WINNER_TAKES_ALL)
	if supported.size() != 9 or supported[0] != 2 or supported[8] != 10:
		return _fail("supported_counts=%s" % str(supported))
	if _identity_rules.supports_player_count(IdentityRules.MODE_WINNER_TAKES_ALL, 1):
		return _fail("should_not_support_1")
	if _identity_rules.supports_player_count(IdentityRules.MODE_WINNER_TAKES_ALL, 11):
		return _fail("should_not_support_11")
	# 身份表：任意人数都必须全部为内奸。
	for player_count: int in range(2, 11):
		var distribution: Array[String] = _identity_rules.get_distribution(player_count, IdentityRules.MODE_WINNER_TAKES_ALL)
		if distribution.size() != player_count:
			return _fail("distribution_size_%d=%d" % [player_count, distribution.size()])
		for identity: String in distribution:
			if identity != "renegade":
				return _fail("distribution_identity_%d=%s" % [player_count, identity])
	# 首任身份为空、固定一号位先手、身份开局公开。
	if not _identity_rules.get_first_player_identity(IdentityRules.MODE_WINNER_TAKES_ALL).is_empty():
		return _fail("first_player_identity_should_be_empty")
	if not _identity_rules.starts_from_first_seat(IdentityRules.MODE_WINNER_TAKES_ALL):
		return _fail("starts_from_first_seat_should_be_true")
	if not _identity_rules.is_identity_public_at_start("renegade", IdentityRules.MODE_WINNER_TAKES_ALL):
		return _fail("identity_should_be_public")
	# 队友关系：两个内奸之间也必须互为敌人。
	if _identity_rules.are_identities_teammates("renegade", "renegade", IdentityRules.MODE_WINNER_TAKES_ALL):
		return _fail("renegade_pair_must_not_be_teammates")
	# 该模式不放开联机自选身份。
	if _identity_rules.supports_lobby_custom_identity(IdentityRules.MODE_WINNER_TAKES_ALL):
		return _fail("should_not_support_custom_identity")
	# 击杀奖惩：任意有效击杀摸三张；无来源死亡没有奖惩。
	var killer: PlayerState = PlayerState.new(0, "击杀者")
	killer.identity = "renegade"
	var victim: PlayerState = PlayerState.new(1, "受害者")
	victim.identity = "renegade"
	if _identity_rules.get_death_reward(killer, victim, IdentityRules.MODE_WINNER_TAKES_ALL) != "draw_three":
		return _fail("death_reward_not_draw_three")
	if not _identity_rules.get_death_reward(null, victim, IdentityRules.MODE_WINNER_TAKES_ALL).is_empty():
		return _fail("no_killer_must_have_no_reward")
	# 其他模式的击杀奖惩保持不变。
	if _identity_rules.get_death_reward(killer, victim, IdentityRules.MODE_IDENTITY) != "":
		return _fail("identity_mode_reward_regressed")
	return true


## 座次补偿数值：手牌按每三个座次递增1张，体力上限5至8号+1、9号及以后+2。
func _test_seat_compensation_values() -> bool:
	# 需求钦定的期望表；索引为座次-1。手牌档位为 1至3号+0、4至6号+1、7至9号+2、10号+3。
	var expected_hand: Array[int] = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3]
	var expected_hp: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2]
	for seat_index: int in range(10):
		var seat_number: int = seat_index + 1
		var hand_bonus: int = _identity_rules.get_seat_compensation_hand_bonus(IdentityRules.MODE_WINNER_TAKES_ALL, seat_number, true)
		if hand_bonus != expected_hand[seat_index]:
			return _fail("hand_bonus_seat%d=%d expected=%d" % [seat_number, hand_bonus, expected_hand[seat_index]])
		var hp_bonus: int = _identity_rules.get_seat_compensation_max_hp_bonus(IdentityRules.MODE_WINNER_TAKES_ALL, seat_number, true)
		if hp_bonus != expected_hp[seat_index]:
			return _fail("hp_bonus_seat%d=%d expected=%d" % [seat_number, hp_bonus, expected_hp[seat_index]])
	# 关闭开关时一律为0。
	for seat_number: int in range(1, 11):
		if _identity_rules.get_seat_compensation_hand_bonus(IdentityRules.MODE_WINNER_TAKES_ALL, seat_number, false) != 0:
			return _fail("hand_bonus_disabled_seat%d" % seat_number)
		if _identity_rules.get_seat_compensation_max_hp_bonus(IdentityRules.MODE_WINNER_TAKES_ALL, seat_number, false) != 0:
			return _fail("hp_bonus_disabled_seat%d" % seat_number)
	# 其他模式即使开启补偿也必须为0，避免选项泄漏到既有模式。
	for other_mode: String in [IdentityRules.MODE_IDENTITY, IdentityRules.MODE_DOUDIZHU, IdentityRules.MODE_TEAM2V2, IdentityRules.MODE_WHEEL_DUEL, IdentityRules.MODE_CONQUEST]:
		if _identity_rules.get_seat_compensation_hand_bonus(other_mode, 10, true) != 0:
			return _fail("hand_bonus_leaked_%s" % other_mode)
		if _identity_rules.get_seat_compensation_max_hp_bonus(other_mode, 10, true) != 0:
			return _fail("hp_bonus_leaked_%s" % other_mode)
	# 非法座次返回0。
	if _identity_rules.get_seat_compensation_hand_bonus(IdentityRules.MODE_WINNER_TAKES_ALL, 0, true) != 0:
		return _fail("hand_bonus_seat0")
	if _identity_rules.get_seat_compensation_max_hp_bonus(IdentityRules.MODE_WINNER_TAKES_ALL, -1, true) != 0:
		return _fail("hp_bonus_negative_seat")
	# 既有模式的开局体力加值不受影响：胜者为王恒为0，身份局领袖规则保持原样。
	if _identity_rules.get_opening_max_hp_bonus("renegade", 8, IdentityRules.MODE_WINNER_TAKES_ALL) != 0:
		return _fail("opening_hp_bonus_should_be_zero")
	if _identity_rules.get_opening_max_hp_bonus("leader", 8, IdentityRules.MODE_IDENTITY) != 1:
		return _fail("identity_leader_hp_bonus_regressed")
	if _identity_rules.get_opening_max_hp_bonus("landlord", 3, IdentityRules.MODE_DOUDIZHU) != 1:
		return _fail("doudizhu_landlord_hp_bonus_regressed")
	return true


## 设置层：分模式人数槽互相隔离，座次补偿开关可读写且发信号。
func _test_settings_player_count_and_switch() -> bool:
	if GameSettings == null:
		return _fail("game_settings_missing")
	if GameSettings.MATCH_MODE_WINNER_TAKES_ALL != "winner_takes_all":
		return _fail("settings_mode_id_drift")
	# 人数规范化：2至10保留，越界收敛。
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_WINNER_TAKES_ALL, 7) != 7:
		return _fail("normalize_count_7")
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_WINNER_TAKES_ALL, 1) != 2:
		return _fail("normalize_count_low")
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_WINNER_TAKES_ALL, 99) != 10:
		return _fail("normalize_count_high")
	# 写入胜者为王人数不得覆盖身份模式人数。
	var identity_count_before: int = GameSettings.next_match_player_count_identity
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_WINNER_TAKES_ALL)
	GameSettings.set_next_match_player_count(6)
	if GameSettings.next_match_player_count_winner_takes_all != 6:
		return _fail("winner_count_not_stored=%d" % GameSettings.next_match_player_count_winner_takes_all)
	if GameSettings.next_match_player_count_identity != identity_count_before:
		return _fail("identity_count_overwritten")
	# 切回身份模式后人数应恢复身份模式自己的槽位。
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_IDENTITY)
	if GameSettings.next_match_player_count != identity_count_before:
		return _fail("identity_count_not_restored=%d expected=%d" % [GameSettings.next_match_player_count, identity_count_before])
	# 座次补偿开关：默认关闭，可写入并回读。
	if GameSettings.DEFAULT_SEAT_COMPENSATION_ENABLED:
		return _fail("seat_compensation_default_should_be_off")
	# 先把开关归零再断言信号：本机设置文件里的当前值可能是 `true`（开发者手动开启或历史用例残留），
	# 而 setter 对“值未变化”不重复发信号，因此不断言初始值就不可能稳定断言信号序列。
	GameSettings.set_seat_compensation_enabled(false)
	var signal_seen: Array[bool] = []
	var on_changed := func(enabled: bool) -> void:
		signal_seen.append(enabled)
	GameSettings.seat_compensation_changed.connect(on_changed)
	GameSettings.set_seat_compensation_enabled(true)
	if not GameSettings.seat_compensation_enabled:
		GameSettings.seat_compensation_changed.disconnect(on_changed)
		return _fail("seat_compensation_not_set")
	GameSettings.set_seat_compensation_enabled(false)
	GameSettings.seat_compensation_changed.disconnect(on_changed)
	if GameSettings.seat_compensation_enabled:
		return _fail("seat_compensation_not_cleared")
	if signal_seen.size() != 2 or not signal_seen[0] or signal_seen[1]:
		return _fail("seat_compensation_signal=%s" % str(signal_seen))
	return true


## 适配层：大厅模式登记、可玩判定、自选身份不放开、房间快照携带座次补偿开关。
func _test_lobby_registration() -> bool:
	var found: bool = false
	for mode_option: Dictionary in NetworkGateway.LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) != "winner_takes_all":
			continue
		found = true
		if str(mode_option.get("display_name", "")) != "胜者为王":
			return _fail("lobby_display_name=%s" % str(mode_option.get("display_name", "")))
	if not found:
		return _fail("lobby_missing_winner_takes_all")
	var gateway: NetworkGateway = NetworkGateway.new()
	if not bool(gateway.call("_is_lobby_game_mode_playable", "winner_takes_all")):
		gateway.free()
		return _fail("winner_takes_all_not_playable")
	if str(gateway.call("_normalize_lobby_game_mode_id", "winner_takes_all")) != "winner_takes_all":
		gateway.free()
		return _fail("lobby_mode_id_not_normalized")
	if int(gateway.call("_normalize_lobby_player_count", 7, "winner_takes_all")) != 7:
		gateway.free()
		return _fail("lobby_player_count_not_normalized")
	if int(gateway.call("_normalize_lobby_player_count", 99, "winner_takes_all")) != 10:
		gateway.free()
		return _fail("lobby_player_count_high_not_clamped")
	# 房间快照必须携带座次补偿字段，客户端才能同步房主开关。
	var snapshot: Dictionary = gateway.get_lan_lobby_snapshot()
	if not snapshot.has("seat_compensation_enabled"):
		gateway.free()
		return _fail("snapshot_missing_seat_compensation")
	if bool(snapshot.get("seat_compensation_enabled", true)):
		gateway.free()
		return _fail("snapshot_seat_compensation_default")
	# 离线状态下不启用房间级开关。
	if gateway.is_lan_seat_compensation_enabled():
		gateway.free()
		return _fail("offline_seat_compensation_should_be_false")
	gateway.free()
	# 协议版本必须已推进，避免新旧客户端静默混用大厅字段。
	if NetworkGateway.PROTOCOL_VERSION < 11:
		return _fail("protocol_version=%d" % NetworkGateway.PROTOCOL_VERSION)
	return true


## 界面接线断言：本模式新增的每个 `%唯一名` 都必须能在其场景中解析。
## 只实例化不挂入场景树，因此不会触发 `_ready`、不会启动对局，开销仅为一次资源加载。
## 必须显式断言的原因：`%唯一名` 在节点缺失时只在运行时抛错，而字体色审计遍历不到不存在的节点，
## 所以“脚本引用了节点、场景里却没有它”不会被任何既有用例发现。
func _test_scene_wiring() -> bool:
	for entry: Array in SCENE_WIRING_CHECKS:
		# 场景资源路径；加载失败即用例自身失效，直接失败而不是跳过。
		var scene_path: String = str(entry[0])
		var packed_scene: PackedScene = load(scene_path) as PackedScene
		if packed_scene == null:
			return _fail("scene_load_%s" % scene_path)
		# 场景实例；仅用于解析唯一名，用完立即释放。
		var scene_instance: Node = packed_scene.instantiate()
		if scene_instance == null:
			return _fail("scene_instantiate_%s" % scene_path)
		for unique_name: String in entry[1]:
			if scene_instance.get_node_or_null("%" + unique_name) == null:
				scene_instance.free()
				return _fail("scene_node_missing %s %%%s" % [scene_path, unique_name])
		scene_instance.free()
	return true


## 终局口径：获胜 ID 独立于身份局内奸阵营，并映射为专属文案；平局复用 draw。
func _test_winner_id_and_text_mapping() -> bool:
	if IdentityRules.WINNER_TAKES_ALL_WINNER_ID != "last_survivor":
		return _fail("winner_id_drift=%s" % IdentityRules.WINNER_TAKES_ALL_WINNER_ID)
	if IdentityRules.WINNER_TAKES_ALL_WINNER_ID == "renegade":
		return _fail("winner_id_must_not_reuse_renegade")
	var prober: MatchController = MatchController.new()
	if str(prober.call("_winner_text", "last_survivor")) != "最后的胜者":
		var text: String = str(prober.call("_winner_text", "last_survivor"))
		prober.free()
		return _fail("winner_text=%s" % text)
	# 既有映射保持不变。
	if str(prober.call("_winner_text", "renegade")) != "内奸":
		prober.free()
		return _fail("renegade_text_regressed")
	if str(prober.call("_winner_text", "draw")) != "draw":
		prober.free()
		return _fail("draw_text_regressed")
	prober.free()
	return true


## AI 口径：胜者为王下任意两名不同玩家之间都是敌对，且不依赖身份暴露度衰减。
func _test_ai_attitude_all_hostile() -> bool:
	# 四人场快照；四人存活时身份局的内奸对内奸落在平衡分支（0.0），最能证明本模式分支确实改变了行为。
	var four_players: Array[Dictionary] = [
		{"player_id":0, "identity":"renegade", "identity_revealed":true, "alive":true, "hp":4},
		{"player_id":1, "identity":"renegade", "identity_revealed":true, "alive":true, "hp":4},
		{"player_id":2, "identity":"renegade", "identity_revealed":true, "alive":true, "hp":4},
		{"player_id":3, "identity":"renegade", "identity_revealed":true, "alive":true, "hp":4},
	]
	var model: IdentityAIModel = IdentityAIModel.new()
	var hostile_snapshot: Dictionary = {"match_id":"wta4", "match_mode":IdentityRules.MODE_WINNER_TAKES_ALL, "players":four_players}
	for target_id: int in [1, 2, 3]:
		var real_attitude: float = model.get_real_attitude(hostile_snapshot, 0, target_id)
		if real_attitude >= 0.0:
			return _fail("real_attitude_player%d=%f should_be_hostile" % [target_id, real_attitude])
		var attitude: float = model.get_attitude(hostile_snapshot, 0, target_id)
		if attitude >= 0.0:
			return _fail("attitude_player%d=%f should_be_hostile" % [target_id, attitude])
	# 自己对自己不参与敌对分支。
	if model.get_real_attitude(hostile_snapshot, 0, 0) <= 0.0:
		return _fail("self_attitude_should_be_positive")
	# 回归：同一份四人身份下，身份模式的内奸对内奸仍保持中立（平衡分支未被改动）。
	var identity_snapshot: Dictionary = {"match_id":"idm4", "match_mode":IdentityRules.MODE_IDENTITY, "players":four_players}
	if not is_zero_approx(model.get_real_attitude(identity_snapshot, 0, 1)):
		return _fail("identity_renegade_pair_regressed=%f" % model.get_real_attitude(identity_snapshot, 0, 1))
	# 三人残局：身份局内奸对内奸本就是 -8.0（既有三足鼎立特例）；胜者为王必须在二人残局也保持敌对，
	# 否则终局会退化成双方互不进攻。
	var two_players: Array[Dictionary] = [
		{"player_id":0, "identity":"renegade", "identity_revealed":true, "alive":true, "hp":4},
		{"player_id":1, "identity":"renegade", "identity_revealed":true, "alive":true, "hp":4},
	]
	var endgame_snapshot: Dictionary = {"match_id":"wta2", "match_mode":IdentityRules.MODE_WINNER_TAKES_ALL, "players":two_players}
	if model.get_real_attitude(endgame_snapshot, 0, 1) >= 0.0:
		return _fail("two_player_endgame_should_be_hostile")
	var identity_endgame: Dictionary = {"match_id":"idm2", "match_mode":IdentityRules.MODE_IDENTITY, "players":two_players}
	if not is_zero_approx(model.get_real_attitude(identity_endgame, 0, 1)):
		return _fail("identity_two_player_renegade_regressed=%f" % model.get_real_attitude(identity_endgame, 0, 1))
	return true


## 对局层：5人开局全员内奸、身份公开、一号位先手、座次补偿默认关闭时无额外手牌。
func _test_match_bootstrap_without_seat_compensation() -> bool:
	if GameSettings != null:
		GameSettings.set_seat_compensation_enabled(false)
	_create_controller()
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_WINNER_TAKES_ALL)
	if not _controller.start_match(5, 20261101, IdentityRules.MODE_WINNER_TAKES_ALL):
		return _fail("start_match_winner_takes_all")
	if str(_controller.state.match_mode) != IdentityRules.MODE_WINNER_TAKES_ALL:
		return _fail("state.match_mode=%s" % str(_controller.state.match_mode))
	if _controller.state.players.size() != 5:
		return _fail("player_count=%d" % _controller.state.players.size())
	# 本局选项必须锁定座次补偿取值。
	if not _controller.state.match_options.has("seat_compensation_enabled"):
		return _fail("match_options_missing_seat_compensation")
	if bool(_controller.state.match_options.get("seat_compensation_enabled", true)):
		return _fail("match_options_seat_compensation_should_be_false")
	if _controller.is_seat_compensation_enabled():
		return _fail("is_seat_compensation_enabled_should_be_false")
	for player: PlayerState in _controller.state.players:
		if player.identity != "renegade":
			return _fail("identity_not_renegade=%s" % player.identity)
		if not player.identity_revealed:
			return _fail("identity_not_public")
	# 选将服务必须已接入本模式：没有主公，一号位只承担先选职责。
	if _controller.character_selection == null:
		return _fail("character_selection_missing")
	if not _controller.character_selection.is_winner_takes_all_mode():
		return _fail("selection_mode_not_winner_takes_all=%s" % _controller.character_selection.match_mode)
	if not _controller.character_selection.get_first_seat_identity().is_empty():
		return _fail("selection_first_seat_identity_not_empty")
	if not _controller.character_selection.uses_leader_priority_selection():
		return _fail("leader_priority_selection_should_stay_true")
	# 座次补偿关闭：发牌瞬间各座次起始手牌数必须完全一致。
	_install_deal_window_probe()
	if not await _await_deal():
		return _fail("bootstrap_deal_timeout phase=%s pending=%s" % [_last_stuck_phase, _last_stuck_pending])
	if _dealt_hand_by_seat.size() != 5:
		return _fail("bootstrap_dealt_seat_count=%d" % _dealt_hand_by_seat.size())
	var base_hand: int = _dealt_hand_by_seat[1]
	if base_hand <= 0:
		return _fail("base_hand_empty")
	for seat_index: int in range(5):
		if _dealt_hand_by_seat[seat_index] != base_hand:
			return _fail("seat%d_dealt=%d expected=%d (compensation off) all=%s" % [seat_index + 1, _dealt_hand_by_seat[seat_index], base_hand, str(_dealt_hand_by_seat)])
	return true


## 胜负判定：只剩一名存活者时返回专属获胜 ID，无人存活时平局，其余继续。
func _test_winner_evaluation() -> bool:
	if _controller == null or _controller.state == null:
		return _fail("winner_eval_missing_controller")
	# 复用上一用例的对局状态；先恢复全部存活再逐一收束。
	for player: PlayerState in _controller.state.players:
		player.alive = true
	if not _identity_rules.evaluate_winner(_controller.state).is_empty():
		return _fail("all_alive_should_continue")
	_controller.state.players[1].alive = false
	_controller.state.players[2].alive = false
	_controller.state.players[3].alive = false
	_controller.state.players[4].alive = false
	if _identity_rules.evaluate_winner(_controller.state) != IdentityRules.WINNER_TAKES_ALL_WINNER_ID:
		return _fail("last_survivor_expected=%s" % _identity_rules.evaluate_winner(_controller.state))
	_controller.state.players[0].alive = false
	if _identity_rules.evaluate_winner(_controller.state) != "draw":
		return _fail("no_survivor_should_be_draw=%s" % _identity_rules.evaluate_winner(_controller.state))
	# 回归：身份局判定不受影响（5人身份局仍有主公时必须返回空串）。
	var identity_state: GameState = GameState.new()
	identity_state.match_mode = IdentityRules.MODE_IDENTITY
	var identity_leader: PlayerState = PlayerState.new(0, "主公")
	identity_leader.identity = "leader"
	var identity_rebel: PlayerState = PlayerState.new(1, "反贼")
	identity_rebel.identity = "rebel"
	# 身份局玩家表；显式类型数组，保证赋给 GameState.players 时不发生类型推断歧义。
	var identity_players: Array[PlayerState] = [identity_leader, identity_rebel]
	identity_state.players = identity_players
	if not _identity_rules.evaluate_winner(identity_state).is_empty():
		return _fail("identity_winner_regressed=%s" % _identity_rules.evaluate_winner(identity_state))
	return true


## 对局层：开启座次补偿后，初始手牌按座次递增、5至8号体力上限+1。
func _test_seat_compensation_opening_numbers() -> bool:
	if GameSettings == null:
		return _fail("game_settings_missing")
	GameSettings.set_seat_compensation_enabled(true)
	_create_controller()
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_WINNER_TAKES_ALL)
	if not _controller.start_match(6, 20261102, IdentityRules.MODE_WINNER_TAKES_ALL):
		return _fail("start_match_with_seat_compensation")
	if not _controller.is_seat_compensation_enabled():
		return _fail("seat_compensation_not_locked_into_match_options")
	# 开局座次必须稳定：座次号与数组下标一一对应，否则补偿会错位。
	for seat_index: int in range(6):
		var seat_player: PlayerState = _controller.state.players[seat_index]
		if _controller.get_player_seat_number(seat_player) != seat_index + 1:
			return _fail("seat_number_mismatch index=%d got=%d" % [seat_index, _controller.get_player_seat_number(seat_player)])
	_install_deal_window_probe()
	if not await _await_deal():
		return _fail("seat_compensation_deal_timeout phase=%s pending=%s" % [_last_stuck_phase, _last_stuck_pending])
	if _dealt_hand_by_seat.size() != 6:
		return _fail("compensation_dealt_seat_count=%d" % _dealt_hand_by_seat.size())
	# 手牌：2号位为基准（1至3号同为+0档），4至6号位各+1。
	var base_hand: int = _dealt_hand_by_seat[1]
	if base_hand <= 0:
		return _fail("compensation_base_hand_empty")
	var expected_hand_delta: Array[int] = [0, 0, 0, 1, 1, 1]
	for seat_index: int in range(6):
		var expected_hand: int = base_hand + expected_hand_delta[seat_index]
		if _dealt_hand_by_seat[seat_index] != expected_hand:
			return _fail("seat%d_dealt=%d expected=%d all=%s" % [seat_index + 1, _dealt_hand_by_seat[seat_index], expected_hand, str(_dealt_hand_by_seat)])
	# 体力上限：按武将基础值 + 座次补偿计算，避免不同武将基础体力互相干扰。
	var expected_hp_delta: Array[int] = [0, 0, 0, 0, 1, 1]
	for seat_index: int in range(6):
		var seat_player: PlayerState = _controller.state.players[seat_index]
		if seat_player.character_id.is_empty():
			return _fail("seat%d_character_missing" % (seat_index + 1))
		var character: Dictionary = GameDatabase.get_character(seat_player.character_id)
		var base_max_hp: int = maxi(int(character.get("max_hp", 4)), 1)
		var expected_max_hp: int = base_max_hp + expected_hp_delta[seat_index]
		if seat_player.max_hp != expected_max_hp:
			return _fail("seat%d_max_hp=%d expected=%d base=%d" % [seat_index + 1, seat_player.max_hp, expected_max_hp, base_max_hp])
		if seat_player.hp != seat_player.max_hp:
			return _fail("seat%d_hp=%d max_hp=%d" % [seat_index + 1, seat_player.hp, seat_player.max_hp])
	return true


## 创建标准控制器组件树。
func _create_controller() -> void:
	if _controller != null and is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
	_controller = MatchController.new()
	_controller.name = "MatchController"
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 驱动 AI 完成选将并等待起始手牌真正分发；超时返回 false 而不是无限等待。
## 本模式沿用身份局的领袖优先选将：一号位先选，本地真人必须由用例显式提交，其余座位交给正式 AI 驱动。
func _await_deal() -> bool:
	# 帧预算上限；保证任何停滞都会以失败结束而不是挂起进程。
	var safety: int = 0
	while safety < 600:
		safety += 1
		if _controller.state == null:
			return false
		if _deal_window_captured:
			return true
		if _controller.state.current_phase == "character_selection":
			if _controller.character_selection != null and _controller.character_selection.get_pending_player_ids().has(0):
				var candidates: Array[String] = _controller.character_selection.get_candidates(0)
				if not candidates.is_empty():
					_controller.select_character(0, candidates[0])
			if _controller.has_method("_drive_ai_character_selection"):
				_controller.call("_drive_ai_character_selection")
		await get_tree().process_frame
	# 超时诊断：记录停留阶段与待确认玩家，便于定位是选将卡死还是发牌未发生。
	_last_stuck_phase = str(_controller.state.current_phase)
	if _controller.character_selection != null:
		_last_stuck_pending = str(_controller.character_selection.get_pending_player_ids())
	return false


## 安装发牌窗口探针；在 gameDrawAfter 时机一次性记录各座次起始手牌数，避免被武将技能摸牌干扰。
func _install_deal_window_probe() -> void:
	_dealt_hand_by_seat.clear()
	_deal_window_captured = false
	_controller.trigger_manager.subscribe("gameDrawAfter", self, func(_event: RuleEvent) -> void:
		_capture_dealt_hands(), 0, -1, "global")


## 记录发牌窗口结束瞬间的座次手牌快照。
func _capture_dealt_hands() -> void:
	_dealt_hand_by_seat.clear()
	for player: PlayerState in _controller.state.players:
		_dealt_hand_by_seat.append(player.hand.size())
	_deal_window_captured = true


## 还原本次用例修改的设置；避免污染其他测试与开发者本机配置。
## 末尾必须强制落盘：`GameSettings` 的写入有 0.25 秒合并延迟，而本用例紧接着就 `quit()`，
## 不强制落盘会把用例中途写入的临时值（例如座次补偿 `true`）留在真实的 `user://game_settings.cfg` 里。
func _restore_settings() -> void:
	if GameSettings == null:
		return
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai)
	if GameSettings.has_method("set_custom_character_assignment_enabled"):
		GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment)
	GameSettings.set_seat_compensation_enabled(_original_seat_compensation)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.set_next_match_mode(_original_match_mode)
	if GameSettings.has_method("flush_pending_settings"):
		GameSettings.flush_pending_settings()


## 失败出口；打印标记并退出非零码。
func _fail(reason: String) -> bool:
	printerr("WINNER_TAKES_ALL_MODE_FAIL %s" % reason)
	_restore_settings()
	get_tree().quit(1)
	return false
