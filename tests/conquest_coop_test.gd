extends Node

## 联机过关斩将（多玩家协作）专项回归测试。
## 验证交替座次与身份、真人座位映射规则、逐玩家难度机缘与复活次数、并行投票/各自两种机缘选择、
## 全体敌方阵亡才推进关卡、关卡奖励写入全体敌人、部分玩家阵亡不终局与全体玩家阵亡终局。
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
	print("CONQUEST_COOP_PASS seats+lan_mapping+per_player_difficulty+simultaneous_vote+vote_reveal+individual+all_enemies_level_clear+shared_enemy_awards+partial_death+next_level_revival+team_defeat")
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
	# 本层完成条件；任一敌人仍存活时都不能清层，只有两名敌人全部标记阵亡后结果才为true。
	players[1].alive = false
	if service.is_current_level_cleared():
		return _fail("single_enemy_defeat_must_not_clear_level")
	players[3].alive = false
	if not service.is_current_level_cleared():
		return _fail("all_enemies_defeated_must_clear_level")
	players[1].alive = true
	players[3].alive = true
	# 消耗玩家2的复活；玩家0的独立次数不得受影响，重复消耗同一玩家必须失败。
	if not service.consume_player_revive(2) or service.get_player_revives_remaining(2) != 0 or service.get_player_revives_remaining(0) != 1 or service.consume_player_revive(2):
		return _fail("per_player_revive_consume")
	# 下一关复活的次数重置；耗尽后恢复难度初始值并清零已用计数，其他玩家不受影响。
	service.reset_player_revives_to_initial(2)
	if service.get_player_revives_remaining(2) != 1 or int((state.conquest_state.get("player_revives_used_by_player", {}) as Dictionary).get("2", -1)) != 0 or service.get_player_revives_remaining(0) != 1:
		return _fail("per_player_revive_reset")
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
	# 首个未被AI玩家2占用的候选；固定种子下的候选列表可能已被该AI占用首项。
	var human_character_id: String = _pick_available_human_character_id(0)
	if player_candidates.is_empty() or human_character_id.is_empty() or not _controller.select_character(0, human_character_id):
		return _fail("vote_player_selection candidates=%s free=%s" % [player_candidates, human_character_id])
	for _frame_index: int in range(40):
		if str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	# 并行投票专项把第二名玩家暂时从内置AI改为直接测试提交者；选将已经完成，后续每次投票均由辅助函数同时驱动两名参与者。
	_controller.ai_coordinator.unregister_ai(2)
	# 开局机缘投票状态；两名玩家同时拥有提交资格，不存在单一current_chooser_id，敌人不在参与名单中。
	if str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or not bool(_controller.state.opportunity_state.get("vote_mode", false)) or _controller.state.opportunity_state.get("participant_ids", []) != [0, 2] or _controller.state.opportunity_state.get("pending_chooser_ids", []) != [0, 2] or int(_controller.state.opportunity_state.get("current_chooser_id", -2)) != -1:
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
	# 敌方在场防护；固定种子选将会随武将池变化而换人，若换到离场型武将（例如貊泽的【幽锋】每轮开始时离场），
	# 回合开始类技能的目标窗口就没有任何合法候选而无法结算。本测试验证模式规则本体，因此先把全部敌人拉回游戏。
	var restored_enemy_count: int = 0
	for coop_player: PlayerState in _controller.state.players:
		if coop_player.identity == "blue" and coop_player.out_of_game:
			if not _controller.restore_player_to_game(coop_player.player_id, "conquest_coop_test"):
				return _fail("enemy_out_of_game_restore player=%d" % coop_player.player_id)
			restored_enemy_count += 1
	# 玩家回合中先击败敌人1；仍有敌人2存活时关卡、机缘与换将均不得发生。
	# 回合开始类技能（例如【铁壁】）会留下待处理选择并把阶段写成 "choice"，使死亡结算无法推进；
	# 固定种子选将会随武将池变化而换人，因此先结算这些技能选择再执行死亡。
	if not _settle_pending_skill_choices():
		return _fail("opening_skill_choice_settle restored_enemies=%d phase=%s pending_kind=%s chooser=%d candidates=%d controls=%d lineup=%s" % [restored_enemy_count, _controller.state.current_phase, str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1)), (_controller._pending_card_choice.get("candidates", []) as Array).size(), (_controller._pending_card_choice.get("control_options", []) as Array).size(), _describe_lineup()])
	var first_enemy: PlayerState = _controller.state.get_player(1)
	var second_enemy: PlayerState = _controller.state.get_player(3)
	first_enemy.hp = 0
	_controller._resolve_death(first_enemy.player_id, 0)
	if _controller.conquest_mode.get_level() != 1 or first_enemy.alive or not second_enemy.alive or not _controller.state.opportunity_state.is_empty():
		return _fail("single_enemy_defeat_advanced level=%d first_alive=%s second_alive=%s opportunity=%s" % [_controller.conquest_mode.get_level(), str(first_enemy.alive), str(second_enemy.alive), str(_controller.state.opportunity_state)])
	# 本层最后一名敌人阵亡后才建立一次层结算；下一层必须整组换将并只发起一次全体机缘。
	second_enemy.hp = 0
	_controller._resolve_death(second_enemy.player_id, 0)
	if not await _wait_for_stage_choosing():
		return _fail("vote_replacement_opportunity_delay")
	if _controller.conquest_mode.get_level() != 2 or not bool(_controller.state.opportunity_state.get("vote_mode", false)):
		return _fail("vote_replacement_level")
	# 全体敌人共享关卡奖励；第2关灰色初始手牌机缘必须同时出现在两名重新入场敌人的历史中。
	if not first_enemy.acquired_opportunity_ids.has("gray_initial_hand_one") or not second_enemy.acquired_opportunity_ids.has("gray_initial_hand_one"):
		return _fail("vote_shared_enemy_awards first=%s second=%s" % [first_enemy.acquired_opportunity_ids, second_enemy.acquired_opportunity_ids])
	if not first_enemy.alive or not second_enemy.alive or first_enemy.character_id.is_empty() or second_enemy.character_id.is_empty() or first_enemy.character_id == second_enemy.character_id:
		return _fail("vote_enemy_group_replaced first=%s second=%s" % [first_enemy.character_id, second_enemy.character_id])
	if not await _submit_vote_and_wait([0, 2], "green_draw_two"):
		return false
	if _controller.state.current_player_id != 0:
		return _fail("vote_turn_resumes_after_replacement")
	# 部分玩家阵亡；难度五没有复活次数，玩家2真实死亡但对局必须继续。
	# 死亡前先给玩家2叠加局内获得技能与额外机缘/体力上限，用于验证下一关复活会完整回到初始状态。
	# 随机武将的技能可能已令玩家2临时离场（限时离场类效果），授予显式允许离场角色以保持固定种子下的确定性。
	var doomed_player: PlayerState = _controller.state.get_player(2)
	if not _controller.grant_acquired_skill(doomed_player.player_id, "gongku", 0, 0, "conquest_test", true):
		return _fail("vote_pre_death_skill_grant")
	doomed_player.acquired_opportunity_ids.append("blue_max_hp_one")
	doomed_player.max_hp += 1
	doomed_player.hp = 0
	_controller._resolve_death(doomed_player.player_id, 1)
	if doomed_player.alive or _controller.state.game_over:
		return _fail("vote_partial_death_continues")
	# 下一层仍需依次击败两名敌人；首名退场时保持第2关，末名退场后才进入第3关并复活玩家2。
	first_enemy.hp = 0
	_controller._resolve_death(first_enemy.player_id, 0)
	if _controller.conquest_mode.get_level() != 2 or first_enemy.alive or not second_enemy.alive:
		return _fail("second_level_partial_clear")
	second_enemy.hp = 0
	_controller._resolve_death(second_enemy.player_id, 0)
	if not await _wait_for_stage_choosing():
		return _fail("revival_level_opportunity_delay")
	if _controller.conquest_mode.get_level() != 3:
		return _fail("revival_level_advance")
	# 复活后的初始状态；存活、机缘历史与获得技能清空、体力回到武将基础上限（难度五无额外增益）、起始手牌4张。
	# 换将后新入场的敌人可能持有会询问“是否弃置整批牌”的技能（例如砂金的【风口】），但这类询问必须由技能自己
	# 延后到结算边界才创建，因此不会阻塞紧随换将的复活摸牌；此处不再额外代答任何请求，故障会直接暴露在下方断言。
	var revived_base_max_hp: int = maxi(int(GameDatabase.get_character(doomed_player.character_id).get("max_hp", 4)), 1)
	if not doomed_player.alive or not doomed_player.acquired_opportunity_ids.is_empty() or not doomed_player.acquired_skills.is_empty() or _controller.get_skill_instance(doomed_player.player_id, "gongku") != null:
		return _fail("revival_initial_history alive=%s opportunities=%s" % [doomed_player.alive, doomed_player.acquired_opportunity_ids])
	if doomed_player.max_hp != revived_base_max_hp or doomed_player.hp != doomed_player.max_hp or doomed_player.hand.size() != 4:
		return _fail("revival_initial_stats hp=%d/%d hand=%d base=%d" % [doomed_player.hp, doomed_player.max_hp, doomed_player.hand.size(), revived_base_max_hp])
	# 复活者照常参与本关全体机缘投票；参与名单必须重新包含两名玩家。
	if _controller.state.opportunity_state.get("participant_ids", []) != [0, 2]:
		return _fail("revival_participates participants=%s" % [_controller.state.opportunity_state.get("participant_ids", [])])
	if not await _submit_vote_and_wait([0, 2], "green_draw_two"):
		return false
	# 全体玩家阵亡；两名红方都死亡且没有新关卡推进时，蓝方获胜并结束对局。
	doomed_player.hp = 0
	_controller._resolve_death(doomed_player.player_id, 1)
	if doomed_player.alive or _controller.state.game_over:
		return _fail("vote_second_partial_death")
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
	# 首个未被AI玩家2占用的候选；固定种子下的候选列表可能已被该AI占用首项。
	var human_character_id: String = _pick_available_human_character_id(0)
	if player_candidates.is_empty() or human_character_id.is_empty() or not _controller.select_character(0, human_character_id):
		return _fail("individual_player_selection candidates=%s free=%s" % [player_candidates, human_character_id])
	for _frame_index: int in range(40):
		if str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	# 各自选择状态；投票标志必须为false，两名玩家仍共同参与但各持私有候选。
	if str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or bool(_controller.state.opportunity_state.get("vote_mode", true)) or _controller.state.opportunity_state.get("participant_ids", []) != [0, 2]:
		return _fail("individual_initial_opportunity")
	# 本地AI在本帧已经用自己抽到的候选完成估值，因此先留存它的候选ID集合，再覆盖候选注入真人选择。
	# 同时在线的两名参与者不存在先后解锁关系，AI不会等待真人先选，测试也不能再依赖“真人先提交”的时序窗口。
	var ai_option_ids: Array[String] = []
	for ai_option_variant: Variant in ((_controller.state.opportunity_state.get("options_by_player", {}) as Dictionary).get(str(2), []) as Array):
		ai_option_ids.append(str((ai_option_variant as Dictionary).get("id", "")))
	if ai_option_ids.size() != 3:
		return _fail("individual_ai_options=%s" % [ai_option_ids])
	if not await _submit_vote_and_wait([0, 2], "green_draw_two"):
		return false
	# 各自结果；真人固定选绿色摸两张，AI在本人候选中独立估值得出一张，两份历史互不相同也不互相覆盖。
	var individual_player_one: PlayerState = _controller.state.get_player(0)
	var individual_player_two: PlayerState = _controller.state.get_player(2)
	if individual_player_one.acquired_opportunity_ids != ["green_draw_two"]:
		return _fail("individual_human_choice one=%s" % [individual_player_one.acquired_opportunity_ids])
	if individual_player_two.acquired_opportunity_ids.size() != 1 or not ai_option_ids.has(str(individual_player_two.acquired_opportunity_ids[0])):
		return _fail("individual_ai_choice two=%s options=%s" % [individual_player_two.acquired_opportunity_ids, ai_option_ids])
	if individual_player_one.acquired_opportunity_ids == individual_player_two.acquired_opportunity_ids:
		return _fail("individual_choices_shared one=%s two=%s" % [individual_player_one.acquired_opportunity_ids, individual_player_two.acquired_opportunity_ids])
	if _controller.state.current_player_id != 0:
		return _fail("individual_first_turn")
	_controller.queue_free()
	_controller = null
	await get_tree().process_frame
	return true


## 把当前机缘候选固定为三张无目标摸牌卡并完成当前选择流程；投票与各自选择都同时开放全部参与者，区别只在候选是否共享与结果是否公开票面。
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
	# 真人选择动作；生产路径仅携带稳定机缘ID，具体定义仍由权威目录重新获取。
	var action: PlayerAction = PlayerAction.new("choose_opportunity", participant_ids[0])
	action.payload = {"card_id":human_card_id}
	if not _controller.submit_action(action):
		return _fail("vote_submit_rejected")
	if bool(_controller.state.opportunity_state.get("vote_mode", false)):
		# 首票提交后第二名仍在同一选择阶段独立可投；不存在把第二人的资格切换为current_chooser_id的串行步骤。
		if str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or _controller.state.opportunity_state.get("pending_chooser_ids", []) != [participant_ids[1]] or int(_controller.state.opportunity_state.get("current_chooser_id", -2)) != -1:
			return _fail("vote_not_simultaneous_after_first state=%s" % [_controller.state.opportunity_state])
		# 第二名参与者的权威选票；测试直接调用组件以避开该座位的内置AI来源门控，候选与重复提交校验仍走正式入口。
		if not _controller.opportunity_system.submit_choice(participant_ids[1], "purple_draw_five"):
			return _fail("vote_second_parallel_submit")
		# 投票收齐后的公开阶段；所有观察者均能看到逐玩家票面与当选牌，而选择阶段从未公开具体票面。
		if str(_controller.state.opportunity_state.get("stage", "")) != "revealing":
			return _fail("vote_reveal_stage state=%s" % [_controller.state.opportunity_state])
		# 公开投票结果；两名玩家各一票，映射顺序与参与名单保持一致。
		var revealed_votes: Array = _controller.state.opportunity_state.get("revealed_votes", []) as Array
		if revealed_votes.size() != 2 or int((revealed_votes[0] as Dictionary).get("player_id", -1)) != participant_ids[0] or str((revealed_votes[0] as Dictionary).get("card_id", "")) != human_card_id or int((revealed_votes[1] as Dictionary).get("player_id", -1)) != participant_ids[1] or str((revealed_votes[1] as Dictionary).get("card_id", "")) != "purple_draw_five":
			return _fail("vote_reveal_mapping=%s" % [revealed_votes])
		# 两名不同观察者的公开快照；候选仍按观察者裁剪，但revealed_votes必须完整且一致。
		var first_viewer_opportunity: Dictionary = (_controller.state.to_dict(participant_ids[0], false).get("opportunity_state", {}) as Dictionary)
		# 第二名观察者公开机缘快照；用于验证局域网各客户端接收同一公布结果。
		var second_viewer_opportunity: Dictionary = (_controller.state.to_dict(participant_ids[1], false).get("opportunity_state", {}) as Dictionary)
		if first_viewer_opportunity.get("revealed_votes", []) != revealed_votes or second_viewer_opportunity.get("revealed_votes", []) != revealed_votes:
			return _fail("vote_reveal_not_public")
	for _frame_index: int in range(180):
		if _controller.state.opportunity_state.is_empty():
			return true
		_settle_pending_resolution_choice()
		await get_tree().process_frame
	# 超时诊断：固定种子选将会随武将池变化而换人，除机缘状态外同时列出登场阵容、体力与待处理窗口类型，便于定位换人带来的差异。
	return _fail("vote_resolution_timeout phase=%s pending_kind=%s pending_chooser=%d lineup=%s hp=%s state=%s" % [_controller.state.current_phase, str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1)), _describe_lineup(), str(_controller.state.players.map(func(resolution_player: PlayerState) -> int: return resolution_player.hp)), _controller.state.opportunity_state])


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
	# 投票结果公开等待；0.05秒足以让专项读取revealing快照，同时避免正式默认2秒拖慢无头回归。
	_controller.opportunity_system.vote_reveal_duration_seconds = 0.05


## 返回本地真人玩家首个仍未被其他玩家选走的候选武将ID；全部候选都被占用时返回空字符串。
## 玩家2固定为内置AI并会立即自动确认武将，固定种子选将会随武将池变化而换人，
## 因此真人候选列表的首项可能已经被该AI占用，测试不能盲目提交 candidates[0]。
func _pick_available_human_character_id(human_player_id: int) -> String:
	# 人类玩家本次随机候选；为空表示选将阶段尚未开放。
	var candidates: Array[String] = _controller.character_selection.get_candidates(human_player_id)
	if candidates.is_empty():
		return ""
	# 其他玩家已经确认的武将；选将服务会拒绝重复占用同一武将。
	var taken_character_ids: Array[String] = []
	for seated_player: PlayerState in _controller.state.players:
		if seated_player.player_id == human_player_id:
			continue
		# 当前座次已确认武将；尚未确认时为空字符串。
		var seated_character_id: String = _controller.character_selection.get_selection(seated_player.player_id)
		if not seated_character_id.is_empty():
			taken_character_ids.append(seated_character_id)
	for candidate_id: String in candidates:
		if not taken_character_ids.has(candidate_id):
			return candidate_id
	return ""


## 结算机缘解析期间出现的待处理窗口，让解析得以推进。
## 机缘解析在存在待处理选择时会整体等待（`OpportunitySystem._resolve_next_effect()` 的 `has_pending_card_choice()` 分支），
## 而本测试只驱动“提交机缘选择”，不驱动选将之后的车轮战窗口：真人座位没有内置AI，
## 投票专项还会主动 `unregister_ai(2)`，因此任何落在这些座位上的窗口都会让解析永久停住。
## 固定种子选将会随武将池变化而换人，机缘牌效也可能因此在首轮就打出致死伤害并追问濒死救援，
## 测试不能假设解析期间不会出现这类窗口；这里按窗口自身下发的候选取消（不可取消的窗口再用首个合法候选确认）。
## **不改写 `current_phase`**：机缘解析期间阶段是 `"choice"`，强行改成出牌阶段会破坏 `resume_phase = "opportunity"` 的续接。
func _settle_pending_resolution_choice() -> void:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return
	# 当前请求稳定编号与回答者；取消动作必须绑定创建时的取值，否则会被权威入口拒绝。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	var cancel_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	cancel_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	if _controller.submit_action(cancel_action):
		return
	# 不可取消的强制窗口；按请求自身下发的首个合法候选确认，候选只取自权威窗口。
	var forced_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	forced_action.payload = {"request_id":request_id, "selected_card_uids":_first_candidate_card_uids(), "selected_target_ids":_first_candidate_target_ids(), "selected_control_id":_first_candidate_control_id(), "confirmed":true}
	_controller.submit_action(forced_action)


## 恢复本测试修改的全局开局设置，保证其他无头测试与手动开局读取用户原有值。
func _restore_settings() -> void:
	GameSettings.set_next_match_mode(_original_match_mode)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.set_custom_character_assignment_enabled(_original_custom_character_assignment_enabled)
	GameSettings.set_conquest_difficulty(_original_conquest_difficulty)
	GameSettings.set_conquest_opportunity_choice_mode(_original_conquest_opportunity_choice_mode)


## 失败出口；打印稳定标记并释放临时控制器后以非零状态结束测试。
## 结算回合开始类技能创建的全部待处理选择；取消它们并把阶段恢复为出牌阶段。
## 部分武将（例如持有【铁壁】的星穹旅伴）会在每回合开始创建可取消的费用目标询问，把阶段写成 "choice"，
## 使死亡结算等后续流程无法推进。固定种子选将会随武将池变化而换人，测试不能假设开局没有这类请求。
func _settle_pending_skill_choices() -> bool:
	# 取消一个请求可能同步续接出下一个，因此按上限循环直到请求表清空。
	for _attempt: int in range(16):
		if _controller._pending_card_choice.is_empty():
			break
		# 当前请求稳定编号与回答者；取消动作必须绑定创建时的取值，否则会被权威入口拒绝。
		var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
		var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
		# 标准选择动作；取消时不携带任何牌或目标。
		var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
		if _controller.submit_action(action):
			continue
		# 不可取消的强制窗口（例如貊泽【幽锋】每轮开始时必须弃置一名其他角色的一张牌，
		# 或爻光的【凶星】是强制发动的欢愉技演出）：按请求自身下发的首个合法候选确认。
		# 候选只取自权威窗口，不额外探测任何隐藏信息；牌、目标与文字选项三者一并提交，
		# 因为同一请求可能是“选牌”“选目标”或“牌与目标组合”三种形态之一，多余字段由权威入口自行忽略。
		var forced_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		forced_action.payload = {"request_id":request_id, "selected_card_uids":_first_candidate_card_uids(), "selected_target_ids":_first_candidate_target_ids(), "selected_control_id":_first_candidate_control_id(), "confirmed":true}
		if not _controller.submit_action(forced_action):
			return false
	if not _controller._pending_card_choice.is_empty():
		return false
	# 非出牌类子选择会把阶段写成 "choice"；取消后显式恢复到出牌阶段，后续才能重建常驻询问。
	if _controller.state.current_phase == "choice":
		_controller.state.current_phase = "play"
	return true


## 当前待处理选择的首个候选实体牌；没有候选时返回空数组，由权威入口按窗口类型校验。
func _first_candidate_card_uids() -> Array:
	# 权威窗口下发的候选牌集合；手牌候选在暗置时仍带稳定uid，可直接用于强制提交。
	var candidate_cards: Array = _controller._pending_card_choice.get("candidates", []) as Array
	return [int((candidate_cards[0] as Dictionary).get("uid", -1))] if not candidate_cards.is_empty() else []


## 当前待处理选择的首个候选目标；没有候选时返回空数组，由权威入口按窗口类型校验。
func _first_candidate_target_ids() -> Array:
	# 权威窗口下发的候选目标集合。
	var candidate_target_ids: Array = _controller._pending_card_choice.get("target_ids", []) as Array
	return [int(candidate_target_ids[0])] if not candidate_target_ids.is_empty() else []


## 当前待处理选择的首个候选文字选项稳定ID；没有候选时返回空字符串。
func _first_candidate_control_id() -> String:
	# 权威窗口下发的候选文字选项集合。
	var candidate_controls: Array = _controller._pending_card_choice.get("control_options", []) as Array
	return str((candidate_controls[0] as Dictionary).get("id", "")) if not candidate_controls.is_empty() else ""


## 本局实际登场武将与离场状态；断言失败时列出便于定位固定种子换人带来的差异。
func _describe_lineup() -> String:
	var lineup: Array[String] = []
	if _controller == null or _controller.state == null:
		return ""
	for lineup_player: PlayerState in _controller.state.players:
		lineup.append("%d=%s/oog=%s/alive=%s" % [lineup_player.player_id, lineup_player.character_id, str(lineup_player.out_of_game), str(lineup_player.alive)])
	return str(lineup)


func _fail(reason: String) -> bool:
	printerr("CONQUEST_COOP_FAIL %s" % reason)
	if _controller != null:
		_controller.queue_free()
	_restore_settings()
	get_tree().quit(1)
	return false
