extends Node

## 联机过关斩将（多玩家协作）专项回归测试。
## 验证交替座次与身份、真人座位映射规则、逐玩家难度机缘与复活次数、投票/各自两种机缘选择、
## 关卡奖励写入全体敌人、部分玩家阵亡不终局与全体玩家阵亡终局。
## 本测试以离线权威控制器直接创建4角色（2玩家+2敌人）对局，网络传输层由既有LAN测试覆盖。

## 权威控制器；复用正式对局组件树验证多人选将、机缘投票、死亡与换将协作。
var _controller: MatchController

## 测试前下一局模式；结束时恢复，避免污染其他模式的菜单或开局测试。
var _original_match_mode: String = GameSettings.MATCH_MODE_IDENTITY

## 测试前手气卡次数；设为0可让本测试直接进入开局机缘，不额外等待确认流程。
var _original_mulligan_limit: int = 0

## 测试前自选武将与座次开关；本专项保持关闭以走纯随机候选流程，结束后必须恢复用户设置。
var _original_custom_character_assignment_enabled: bool = false

## 测试前过关斩将难度；本专项使用难度五保持无开局机缘，独立段落再验证难度一的逐玩家授予。
var _original_conquest_difficulty: int = GameSettings.DEFAULT_CONQUEST_DIFFICULTY

## 测试前过关斩将机缘选择方式；结束时恢复，避免覆盖用户保存的投票/各自选择配置。
var _original_conquest_opportunity_choice_mode: String = GameSettings.DEFAULT_CONQUEST_OPPORTUNITY_CHOICE_MODE


## 延迟执行以等待自动加载数据库完成卡牌、武将与技能索引。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次运行规则层与完整对局层断言；任意失败均恢复全局设置并以非零状态退出。
func _run() -> void:
	_original_match_mode = str(GameSettings.next_match_mode)
	_original_mulligan_limit = GameSettings.mulligan_limit
	_original_custom_character_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_original_conquest_difficulty = GameSettings.conquest_difficulty
	_original_conquest_opportunity_choice_mode = GameSettings.conquest_opportunity_choice_mode
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_CONQUEST)
	GameSettings.set_mulligan_limit(0)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_conquest_difficulty(GameSettings.DEFAULT_CONQUEST_DIFFICULTY)
	if not _test_coop_mode_rules():
		_restore_settings()
		return
	if not _test_multi_participant_service():
		_restore_settings()
		return
	if not await _test_vote_match_flow():
		_restore_settings()
		return
	if not await _test_individual_match_flow():
		_restore_settings()
		return
	_restore_settings()
	print("CONQUEST_COOP_PASS seats+lan_mapping+per_player_difficulty+vote+individual+shared_enemy_awards+partial_death+team_defeat")
	get_tree().quit(0)


## 验证角色总数2/4/6/8、交替红蓝身份表、真人偶数座位映射与机缘选择方式的规范化规则。
func _test_coop_mode_rules() -> bool:
	# 规则服务；独立于对局状态验证过关斩将的多人模式契约。
	var rules: IdentityRules = IdentityRules.new()
	if not rules.supports_player_count(IdentityRules.MODE_CONQUEST, 4) or not rules.supports_player_count(IdentityRules.MODE_CONQUEST, 6) or not rules.supports_player_count(IdentityRules.MODE_CONQUEST, 8) or rules.supports_player_count(IdentityRules.MODE_CONQUEST, 3) or rules.supports_player_count(IdentityRules.MODE_CONQUEST, 10):
		return _fail("supported_role_counts")
	if rules.get_distribution(4, IdentityRules.MODE_CONQUEST) != ["red", "blue", "red", "blue"] or rules.get_distribution(8, IdentityRules.MODE_CONQUEST) != ["red", "blue", "red", "blue", "red", "blue", "red", "blue"]:
		return _fail("alternating_distribution")
	# 局域网真人座位映射；过关斩将真人固定占偶数玩家座位，其他模式保持连续稳定ID。
	if NetworkGateway.build_match_seat_player_ids("conquest", 3) != [0, 2, 4] or NetworkGateway.build_match_seat_player_ids("identity", 3) != [0, 1, 2]:
		return _fail("lan_seat_mapping")
	if NetworkGateway.get_match_role_count_for_mode("conquest", 4) != 8 or NetworkGateway.get_match_role_count_for_mode("doudizhu", 5) != 5:
		return _fail("lan_role_count")
	if GameSettings.normalize_conquest_opportunity_choice_mode("individual") != GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_INDIVIDUAL or GameSettings.normalize_conquest_opportunity_choice_mode("unknown") != GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_VOTE:
		return _fail("choice_mode_normalize")
	# 多人胜负规则；部分红方阵亡不终局，全部红方阵亡才由蓝方获胜。
	var winner_state: GameState = GameState.new()
	winner_state.match_mode = IdentityRules.MODE_CONQUEST
	# 四名固定角色；座次与身份按交替规则手工构造。
	var winner_players: Array[PlayerState] = [PlayerState.new(0, "玩家1"), PlayerState.new(1, "敌人1"), PlayerState.new(2, "玩家2"), PlayerState.new(3, "敌人2")]
	for seat_index: int in range(winner_players.size()):
		winner_players[seat_index].identity = "red" if seat_index % 2 == 0 else "blue"
	winner_state.players = winner_players
	winner_players[2].alive = false
	if rules.evaluate_winner(winner_state) != "":
		return _fail("partial_death_should_continue")
	winner_players[0].alive = false
	if rules.evaluate_winner(winner_state) != "blue_team":
		return _fail("team_defeat_blue_wins")
	return true


## 验证服务的多参与者配置：逐玩家难度机缘、独立复活次数、成员查询与旧单人存档字段回退。
func _test_multi_participant_service() -> bool:
	# 纯规则状态；两名玩家与两名敌人按交替座次构造。
	var state: GameState = GameState.new()
	var players: Array[PlayerState] = [PlayerState.new(0, "玩家1"), PlayerState.new(1, "敌人1"), PlayerState.new(2, "玩家2"), PlayerState.new(3, "敌人2")]
	state.players = players
	# 固定随机源；难度机缘不消耗随机数，仍按正式接口注入。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260726
	# 多参与者服务；难度一为每名玩家独立授予开局机缘与1次复活。
	var service: ConquestModeService = ConquestModeService.new()
	service.configure_participants(state, rng, [0, 2], [1, 3], 1)
	if service.get_player_ids() != [0, 2] or service.get_enemy_ids() != [1, 3] or not service.is_conquest_player(2) or service.is_conquest_player(1) or not service.is_enemy(3) or service.is_enemy(0):
		return _fail("participant_queries")
	# 难度一开局机缘；两名玩家的通用机缘历史必须完全一致且互相独立持有。
	var expected_starting_ids: Array[String] = ["purple_max_hp_two", "orange_draw_phase_one", "gray_initial_hand_two", "green_slash_play_limit_one", "gray_revive_one"]
	if players[0].acquired_opportunity_ids != expected_starting_ids or players[2].acquired_opportunity_ids != expected_starting_ids or not players[1].acquired_opportunity_ids.is_empty():
		return _fail("per_player_difficulty_opportunities")
	if service.get_player_revives_remaining(0) != 1 or service.get_player_revives_remaining(2) != 1:
		return _fail("per_player_revives_initial")
	# 消耗玩家2的复活；玩家0的独立次数不得受影响，重复消耗同一玩家必须失败。
	if not service.consume_player_revive(2) or service.get_player_revives_remaining(2) != 0 or service.get_player_revives_remaining(0) != 1 or service.consume_player_revive(2):
		return _fail("per_player_revive_consume")
	# 旧单人存档回退；缺少复数字段时成员查询与复活次数读取旧标量键。
	var legacy_state: GameState = GameState.new()
	legacy_state.players = [PlayerState.new(0, "玩家"), PlayerState.new(1, "敌方AI")] as Array[PlayerState]
	legacy_state.conquest_state = {"level":3, "player_id":0, "enemy_player_id":1, "player_revives_remaining":1, "enemy_opportunity_ids":[]}
	var legacy_service: ConquestModeService = ConquestModeService.new()
	legacy_service.restore(legacy_state, rng)
	if legacy_service.get_player_ids() != [0] or legacy_service.get_enemy_ids() != [1] or legacy_service.get_player_revives_remaining(0) != 1 or not legacy_service.can_revive_player(0):
		return _fail("legacy_scalar_fallback")
	return true


## 完整4角色投票流程：交替座次建位、玩家先选将、全体投票取最高票、关卡奖励写入全体敌人与终局边界。
func _test_vote_match_flow() -> bool:
	GameSettings.set_conquest_opportunity_choice_mode(GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_VOTE)
	_create_controller()
	if not _controller.start_match(4, 20260726, IdentityRules.MODE_CONQUEST):
		return _fail("vote_start_match")
	if str(_controller.state.match_options.get("conquest_opportunity_choice_mode", "")) != GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_VOTE:
		return _fail("vote_mode_option_locked")
	# 四名角色的座次身份；必须按“玩家1、敌人1、玩家2、敌人2”交替，稳定ID等于创建索引。
	if _controller.state.players.size() != 4 or _controller.conquest_mode.get_player_ids() != [0, 2] or _controller.conquest_mode.get_enemy_ids() != [1, 3]:
		return _fail("vote_seat_composition")
	for seat_index: int in range(4):
		# 当前座次角色；身份与阵营按偶红奇蓝交替。
		var seated_player: PlayerState = _controller.state.players[seat_index]
		if seated_player.player_id != seat_index or seated_player.identity != ("red" if seat_index % 2 == 0 else "blue"):
			return _fail("vote_seat_identity_%d" % seat_index)
	# 敌方座位命名；玩家座位由AI补位时带AI前缀，敌方座位固定使用“敌人K”语义。
	if _controller.state.players[1].display_name != "[AI]敌人1" or _controller.state.players[3].display_name != "[AI]敌人2" or _controller.state.players[2].display_name != "[AI]玩家2":
		return _fail("vote_seat_names=%s" % [[_controller.state.players[1].display_name, _controller.state.players[2].display_name, _controller.state.players[3].display_name]])
	# 敌方候选生成边界；全部红方玩家确认前敌人不能选将（玩家2为AI会立即自动确认，因此只断言敌方仍在等待）。
	if _controller.character_selection.can_player_select(1) or _controller.character_selection.can_player_select(3):
		return _fail("vote_enemy_selection_locked")
	# 本地真人玩家选将；AI玩家2与两名敌人随后由控制器自动确认。
	var player_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	if player_candidates.is_empty() or not _controller.select_character(0, player_candidates[0]):
		return _fail("vote_player_selection")
	for _frame_index: int in range(40):
		if str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	# 开局机缘投票状态；两名玩家共同参与，投票标志公开且敌人不在参与名单中。
	if str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or not bool(_controller.state.opportunity_state.get("vote_mode", false)) or _controller.state.opportunity_state.get("participant_ids", []) != [0, 2]:
		return _fail("vote_initial_opportunity state=%s" % [_controller.state.opportunity_state])
	# 四名武将互不重复；敌方候选生成必须排除全部玩家已确认武将。
	var used_character_ids: Array[String] = []
	for seated_player: PlayerState in _controller.state.players:
		if seated_player.character_id.is_empty() or used_character_ids.has(seated_player.character_id):
			return _fail("vote_duplicate_characters")
		used_character_ids.append(seated_player.character_id)
	if not await _submit_vote_and_wait([0, 2], "green_draw_two"):
		return false
	# 投票结果；随机历史必须包含计票摘要，两名玩家获得同一张当选机缘（1票对1票时在两票中随机）。
	var vote_result_entry: Dictionary = _find_last_random_history_entry("opportunity_vote_result")
	if vote_result_entry.is_empty():
		return _fail("vote_result_history")
	# 本次当选机缘稳定ID；真人投绿色摸两张，AI按估值投紫色摸五张，平票在两者中随机。
	var winner_card_id: String = str(vote_result_entry.get("winner_card_id", ""))
	if not winner_card_id in ["green_draw_two", "purple_draw_five"]:
		return _fail("vote_winner_candidates=%s" % winner_card_id)
	# 两名玩家的机缘历史；难度五没有开局机缘，因此唯一历史项就是本次投票当选机缘。
	var vote_player_one: PlayerState = _controller.state.get_player(0)
	var vote_player_two: PlayerState = _controller.state.get_player(2)
	if vote_player_one.acquired_opportunity_ids != [winner_card_id] or vote_player_two.acquired_opportunity_ids != [winner_card_id]:
		return _fail("vote_shared_winner one=%s two=%s" % [vote_player_one.acquired_opportunity_ids, vote_player_two.acquired_opportunity_ids])
	if _controller.state.current_player_id != 0:
		return _fail("vote_first_turn")
	# 玩家回合中击败敌人1；关卡提升后新增机缘必须同时写入两名敌人的公开历史。
	var first_enemy: PlayerState = _controller.state.get_player(1)
	var second_enemy: PlayerState = _controller.state.get_player(3)
	first_enemy.hp = 0
	_controller._resolve_death(first_enemy.player_id, 0)
	if not await _wait_for_stage_choosing():
		return _fail("vote_replacement_opportunity_delay")
	if _controller.conquest_mode.get_level() != 2 or not bool(_controller.state.opportunity_state.get("vote_mode", false)):
		return _fail("vote_replacement_level")
	# 全体敌人共享关卡奖励；第2关灰色初始手牌机缘必须同时出现在阵亡换将敌人与在场敌人的历史中。
	if not first_enemy.acquired_opportunity_ids.has("gray_initial_hand_one") or not second_enemy.acquired_opportunity_ids.has("gray_initial_hand_one"):
		return _fail("vote_shared_enemy_awards first=%s second=%s" % [first_enemy.acquired_opportunity_ids, second_enemy.acquired_opportunity_ids])
	if not first_enemy.alive or first_enemy.character_id.is_empty():
		return _fail("vote_enemy_replaced")
	if not await _submit_vote_and_wait([0, 2], "green_draw_two"):
		return false
	if _controller.state.current_player_id != 0:
		return _fail("vote_turn_resumes_after_replacement")
	# 部分玩家阵亡；难度五没有复活次数，玩家2真实死亡但对局必须继续。
	var doomed_player: PlayerState = _controller.state.get_player(2)
	doomed_player.hp = 0
	_controller._resolve_death(doomed_player.player_id, 1)
	if doomed_player.alive or _controller.state.game_over:
		return _fail("vote_partial_death_continues")
	# 全体玩家阵亡；最后一名红方死亡后蓝方获胜并结束对局。
	var last_player: PlayerState = _controller.state.get_player(0)
	last_player.hp = 0
	_controller._resolve_death(last_player.player_id, 1)
	if last_player.alive or not _controller.state.game_over or _controller.state.winner != "blue_team":
		return _fail("vote_team_defeat")
	_controller.queue_free()
	_controller = null
	await get_tree().process_frame
	return true


## 各自选择流程：同一4角色开局下每名玩家独立三选一，各自历史只保存本人所选机缘。
func _test_individual_match_flow() -> bool:
	GameSettings.set_conquest_opportunity_choice_mode(GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_INDIVIDUAL)
	_create_controller()
	if not _controller.start_match(4, 20260727, IdentityRules.MODE_CONQUEST):
		return _fail("individual_start_match")
	var player_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	if player_candidates.is_empty() or not _controller.select_character(0, player_candidates[0]):
		return _fail("individual_player_selection")
	for _frame_index: int in range(40):
		if str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	# 各自选择状态；投票标志必须为false，两名玩家仍共同参与但各持私有候选。
	if str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or bool(_controller.state.opportunity_state.get("vote_mode", true)) or _controller.state.opportunity_state.get("participant_ids", []) != [0, 2]:
		return _fail("individual_initial_opportunity")
	if not await _submit_vote_and_wait([0, 2], "green_draw_two"):
		return false
	# 各自结果；真人固定选绿色摸两张，AI按估值在覆盖候选中选择紫色摸五张，两份历史互不相同。
	var individual_player_one: PlayerState = _controller.state.get_player(0)
	var individual_player_two: PlayerState = _controller.state.get_player(2)
	if individual_player_one.acquired_opportunity_ids != ["green_draw_two"] or individual_player_two.acquired_opportunity_ids != ["purple_draw_five"]:
		return _fail("individual_choices one=%s two=%s" % [individual_player_one.acquired_opportunity_ids, individual_player_two.acquired_opportunity_ids])
	if _controller.state.current_player_id != 0:
		return _fail("individual_first_turn")
	_controller.queue_free()
	_controller = null
	await get_tree().process_frame
	return true


## 把当前机缘候选固定为三张无目标摸牌卡（全体参与者共用同一覆盖）并提交真人一票，随后等待流程完全结束。
## 投票模式下AI会在真人提交后立即投出自己的一票；各自选择模式下AI独立选择自己的候选。
func _submit_vote_and_wait(participant_ids: Array[int], human_card_id: String) -> bool:
	if _controller == null or _controller.state == null or str(_controller.state.opportunity_state.get("stage", "")) != "choosing":
		return _fail("vote_submit_not_choosing")
	# 安全候选组；三张无目标摸牌机缘避免额外目标选择遮蔽本专项的流程断言。
	var draw_two: Dictionary = OpportunityCatalog.get_card("green_draw_two")
	var draw_three: Dictionary = OpportunityCatalog.get_card("blue_draw_three")
	var draw_five: Dictionary = OpportunityCatalog.get_card("purple_draw_five")
	if draw_two.is_empty() or draw_three.is_empty() or draw_five.is_empty():
		return _fail("vote_safe_catalog")
	# 覆盖后的候选映射；每名参与者都持有同一组稳定候选，权威提交仍逐人校验各自条目。
	var overridden_options: Dictionary = {}
	for participant_id: int in participant_ids:
		overridden_options[str(participant_id)] = [draw_two.duplicate(true), draw_three.duplicate(true), draw_five.duplicate(true)]
	_controller.state.opportunity_state["options_by_player"] = overridden_options
	# 真人投票动作；生产路径仅携带稳定机缘ID，具体定义仍由权威目录重新获取。
	var action: PlayerAction = PlayerAction.new("choose_opportunity", participant_ids[0])
	action.payload = {"card_id":human_card_id}
	if not _controller.submit_action(action):
		return _fail("vote_submit_rejected")
	for _frame_index: int in range(48):
		if _controller.state.opportunity_state.is_empty():
			return true
		await get_tree().process_frame
	return _fail("vote_resolution_timeout state=%s" % [_controller.state.opportunity_state])


## 等待敌方换将展示时间结束并进入机缘选择；测试根节点保持暂停可运行。
func _wait_for_stage_choosing() -> bool:
	# 展示等待上限；0.20秒覆盖正式0.05秒测试配置及无头计时器调度余量。
	await get_tree().create_timer(0.20, true).timeout
	return str(_controller.state.opportunity_state.get("stage", "")) == "choosing"


## 从随机历史尾部反向查找指定类型的最新条目；不存在时返回空字典。
func _find_last_random_history_entry(kind: String) -> Dictionary:
	for entry_index: int in range(_controller.state.random_history.size() - 1, -1, -1):
		# 当前随机历史条目；只匹配指定kind的最新一条。
		var entry: Dictionary = _controller.state.random_history[entry_index] as Dictionary
		if str(entry.get("kind", "")) == kind:
			return entry
	return {}


## 创建与正式场景一致的最小控制器组件树；一号位红方为本地真人，其余座位由AI管理。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；死亡、装备与技能安装均通过正式时机接口派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；负责自动提交AI玩家与敌人的选将和机缘选择。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 网络网关；离线默认状态验证多人规则本体，真实ENet传输由既有LAN测试覆盖。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.conquest_enemy_replacement_opportunity_delay_seconds = 0.05
	_controller.ai_action_delay_seconds = 0.0


## 恢复本测试修改的全局开局设置，保证其他无头测试与手动开局读取用户原有值。
func _restore_settings() -> void:
	GameSettings.set_next_match_mode(_original_match_mode)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.set_custom_character_assignment_enabled(_original_custom_character_assignment_enabled)
	GameSettings.set_conquest_difficulty(_original_conquest_difficulty)
	GameSettings.set_conquest_opportunity_choice_mode(_original_conquest_opportunity_choice_mode)


## 失败出口；打印稳定标记并释放临时控制器后以非零状态结束测试。
func _fail(reason: String) -> bool:
	printerr("CONQUEST_COOP_FAIL %s" % reason)
	if _controller != null:
		_controller.queue_free()
	_restore_settings()
	get_tree().quit(1)
	return false
