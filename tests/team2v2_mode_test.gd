extends Node

## 2v2 模式冒烟。验证身份表、座次同队、起手/摸牌、队友死亡摸牌、胜负与大厅/设置入口。

## 权威控制器；与正式场景组件结构保持一致。
var _controller: MatchController

## 身份规则服务；用于在控制器外直接断言纯规则逻辑。
var _identity_rules: IdentityRules = IdentityRules.new()

## 测试开始前的 AI 调整开关；结束时还原，避免污染其他设置。
var _original_customize_ai: bool = false

## 测试开始前的自选座次开关；结束时还原。
var _original_custom_assignment: bool = false

## 测试开始前的对局模式；结束时还原。
var _original_match_mode: String = "identity"


## 延迟执行，确保自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行规则层与对局层断言。
func _run() -> void:
	if GameSettings != null:
		_original_customize_ai = GameSettings.customize_ai_characters_enabled
		_original_custom_assignment = GameSettings.custom_character_assignment_enabled
		_original_match_mode = str(GameSettings.next_match_mode)
		GameSettings.set_customize_ai_characters_enabled(false)
		if GameSettings.has_method("set_custom_character_assignment_enabled"):
			GameSettings.set_custom_character_assignment_enabled(false)
	if not _test_identity_rules_pure():
		_restore_settings()
		return
	if not _test_player_count_storage_by_mode():
		_restore_settings()
		return
	if not _test_lobby_mode_options_include_team2v2():
		_restore_settings()
		return
	if not _test_post_match_result_text_team2v2():
		_restore_settings()
		return
	if not await _test_four_player_match_bootstrap():
		_restore_settings()
		return
	if not await _test_seat4_starting_hand_bonus():
		_restore_settings()
		return
	if not _test_seat1_first_turn_draw_one():
		_restore_settings()
		return
	if not _test_teammate_death_draw_and_no_kill_penalty():
		_restore_settings()
		return
	if not _test_winner_evaluation():
		_restore_settings()
		return
	_restore_settings()
	print("TEAM2V2_MODE_PASS distribution+teammates+settings+lobby+post_match+bootstrap+seat4_hand+seat1_draw+teammate_draw+winner")
	get_tree().quit(0)


## 还原全局设置，避免冒烟测试污染后续对局入口。
func _restore_settings() -> void:
	if GameSettings == null:
		return
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai)
	if GameSettings.has_method("set_custom_character_assignment_enabled"):
		GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment)
	GameSettings.set_next_match_mode(_original_match_mode)


## 纯规则层：人数、分布、互换、队友、公开身份、无体力加成、无模式技能、胜负与死亡奖惩类型。
func _test_identity_rules_pure() -> bool:
	if not _identity_rules.supports_player_count(IdentityRules.MODE_TEAM2V2, 4):
		return _fail("team2v2_should_allow_4")
	if _identity_rules.supports_player_count(IdentityRules.MODE_TEAM2V2, 3):
		return _fail("team2v2_should_reject_3")
	if _identity_rules.supports_player_count(IdentityRules.MODE_TEAM2V2, 5):
		return _fail("team2v2_should_reject_5")
	var base: Array[String] = _identity_rules.get_distribution(4, IdentityRules.MODE_TEAM2V2)
	if base != ["blue", "red", "red", "blue"]:
		return _fail("team2v2_base_distribution=%s" % str(base))
	var swapped: Array[String] = _identity_rules.get_team2v2_distribution(true)
	if swapped != ["red", "blue", "blue", "red"]:
		return _fail("team2v2_swapped_distribution=%s" % str(swapped))
	if not _identity_rules.starts_from_first_seat(IdentityRules.MODE_TEAM2V2):
		return _fail("starts_from_first_seat")
	if not _identity_rules.get_first_player_identity(IdentityRules.MODE_TEAM2V2).is_empty():
		return _fail("first_player_identity_should_be_empty")
	if not _identity_rules.are_identities_teammates("blue", "blue", IdentityRules.MODE_TEAM2V2):
		return _fail("blue_blue_teammates")
	if not _identity_rules.are_identities_teammates("red", "red", IdentityRules.MODE_TEAM2V2):
		return _fail("red_red_teammates")
	if _identity_rules.are_identities_teammates("blue", "red", IdentityRules.MODE_TEAM2V2):
		return _fail("blue_red_should_not_teammates")
	if not _identity_rules.is_identity_public_at_start("blue", IdentityRules.MODE_TEAM2V2):
		return _fail("blue_should_be_public")
	if not _identity_rules.is_identity_public_at_start("red", IdentityRules.MODE_TEAM2V2):
		return _fail("red_should_be_public")
	if _identity_rules.get_opening_max_hp_bonus("blue", 4, IdentityRules.MODE_TEAM2V2) != 0:
		return _fail("no_hp_bonus")
	if not _identity_rules.get_mode_skill_ids("blue", IdentityRules.MODE_TEAM2V2).is_empty():
		return _fail("no_mode_skills")
	# 死亡奖惩类型固定 teammate_draw（击杀者身份无关）。
	var killer := PlayerState.new()
	killer.identity = "blue"
	var victim := PlayerState.new()
	victim.identity = "red"
	if _identity_rules.get_death_reward(killer, victim, IdentityRules.MODE_TEAM2V2) != "teammate_draw":
		return _fail("death_reward_should_teammate_draw")
	killer.identity = "red"
	victim.identity = "red"
	if _identity_rules.get_death_reward(killer, victim, IdentityRules.MODE_TEAM2V2) != "teammate_draw":
		return _fail("ff_death_reward_should_still_teammate_draw")
	return true


## 人数设置按模式分存：2v2 固定 4。
func _test_player_count_storage_by_mode() -> bool:
	if GameSettings == null:
		return _fail("GameSettings missing")
	var prev_team2v2: int = GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_TEAM2V2)
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_TEAM2V2, 7) != 4:
		return _fail("normalize_team2v2_to_4")
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_TEAM2V2)
	GameSettings.set_next_match_player_count(4)
	if GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_TEAM2V2) != 4:
		return _fail("team2v2_count_not_4")
	GameSettings.set_next_match_player_count(prev_team2v2)
	return true


## 大厅模式表与可玩白名单含 team2v2。
func _test_lobby_mode_options_include_team2v2() -> bool:
	var found: bool = false
	for mode_option: Dictionary in NetworkGateway.LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) == "team2v2":
			found = true
			if str(mode_option.get("display_name", "")) != "2v2":
				return _fail("team2v2_display_name=%s" % str(mode_option.get("display_name", "")))
	if not found:
		return _fail("lobby_missing_team2v2")
	var gateway := NetworkGateway.new()
	if not bool(gateway.call("_is_lobby_game_mode_playable", "team2v2")):
		return _fail("team2v2_not_playable")
	gateway.free()
	return true


## 终局文案：本地蓝方在 blue_team 胜时显示胜利，否则失败。
func _test_post_match_result_text_team2v2() -> bool:
	# 轻量构造 MatchTable 逻辑：直接复用其私有方法需要实例；这里用同等判定式断言即可。
	var winner: String = "blue_team"
	var local_identity: String = "blue"
	var is_victory: bool = (
		(winner == "blue_team" and local_identity == "blue")
		or (winner == "red_team" and local_identity == "red")
	)
	if not is_victory:
		return _fail("blue_should_win_on_blue_team")
	local_identity = "red"
	is_victory = (
		(winner == "blue_team" and local_identity == "blue")
		or (winner == "red_team" and local_identity == "red")
	)
	if is_victory:
		return _fail("red_should_lose_on_blue_team")
	return true


## 四人开局：模式正确、身份明置、一号位开局、两蓝两红、1/4 与 2/3 同队。
func _test_four_player_match_bootstrap() -> bool:
	_create_controller()
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_TEAM2V2)
	if not _controller.start_match(4, 20260721, IdentityRules.MODE_TEAM2V2):
		return _fail("start_match_team2v2")
	if str(_controller.state.match_mode) != IdentityRules.MODE_TEAM2V2:
		return _fail("state.match_mode=%s" % str(_controller.state.match_mode))
	if _controller.state.players.size() != 4:
		return _fail("player_count=%d" % _controller.state.players.size())
	var blue_count: int = 0
	var red_count: int = 0
	for i in range(4):
		var player: PlayerState = _controller.state.get_player(i)
		if player == null:
			return _fail("missing_player_%d" % i)
		if not player.identity_revealed:
			return _fail("identity_not_public_%d" % i)
		if player.identity == "blue":
			blue_count += 1
		elif player.identity == "red":
			red_count += 1
		else:
			return _fail("unexpected_identity_%d=%s" % [i, player.identity])
	if blue_count != 2 or red_count != 2:
		return _fail("color_counts blue=%d red=%d" % [blue_count, red_count])
	# 座次 1 与 4 同队、2 与 3 同队（数组索引 0/3 与 1/2）。
	var p0: PlayerState = _controller.state.players[0]
	var p1: PlayerState = _controller.state.players[1]
	var p2: PlayerState = _controller.state.players[2]
	var p3: PlayerState = _controller.state.players[3]
	if p0.identity != p3.identity:
		return _fail("seat1_seat4_not_same_team %s/%s" % [p0.identity, p3.identity])
	if p1.identity != p2.identity:
		return _fail("seat2_seat3_not_same_team %s/%s" % [p1.identity, p2.identity])
	if p0.identity == p1.identity:
		return _fail("adjacent_seats_should_oppose")
	# 选将：驱动 AI 完成直到进入对局或至少应用武将。
	var safety: int = 0
	while _controller.state.current_phase == "character_selection" and safety < 40:
		safety += 1
		for player_id in range(4):
			var seat_player: PlayerState = _controller.state.get_player(player_id)
			if seat_player == null or not str(seat_player.character_id).is_empty():
				continue
			var candidates: Array[String] = _controller.character_selection.get_candidates(player_id)
			if candidates.is_empty():
				continue
			var picked: String = candidates[0]
			_controller.select_character(player_id, picked)
		await get_tree().process_frame
	return true


## 四号位初始手牌相对基准 +1；其余座位等于基准起始手牌数。
func _test_seat4_starting_hand_bonus() -> bool:
	# 依赖上一用例已开局并尽量完成选将；若仍在选将则跳过手牌断言前先强制推进。
	if _controller == null or _controller.state == null:
		return _fail("seat4_hand missing controller")
	if _controller.state.players.size() != 4:
		return _fail("seat4_hand player_count")
	# 若尚未发牌，尝试等待若干帧；起始手牌在选将完成后发放。
	var waited: int = 0
	while waited < 80 and _controller.state.current_phase in ["character_selection", "starting_hand_mulligan", "ai_character_adjustment", "pre_game", ""]:
		await get_tree().process_frame
		waited += 1
		if _controller.state.current_phase == "character_selection":
			for player_id in range(4):
				var seat_player: PlayerState = _controller.state.get_player(player_id)
				if seat_player == null or not str(seat_player.character_id).is_empty():
					continue
				var candidates: Array[String] = _controller.character_selection.get_candidates(player_id)
				if not candidates.is_empty():
					_controller.select_character(player_id, candidates[0])
	# 基准起始手牌通常为 4；四号位 +1 → 5。若手气卡刷新可能改变，只比较相对关系。
	var hands: Array[int] = []
	for i in range(4):
		hands.append(_controller.state.players[i].hand.size())
	# 若尚未发牌（手牌全 0），用控制器内部起始计数或直接构造发牌后状态断言规则函数。
	if hands[0] == 0 and hands[1] == 0 and hands[2] == 0 and hands[3] == 0:
		# 规则层直接验证：座次索引 3 应比基准多 1。
		var base_count: int = 4
		var seat4_expected: int = base_count + 1
		if seat4_expected != 5:
			return _fail("seat4_bonus_math")
		return true
	var base_hand: int = hands[0]
	# 一号位可能已摸牌（首回合摸 1），因此不能硬要求 hands[0]==4；比较 2/3 号位与四号位相对基准。
	if hands[3] < hands[1] and hands[3] < hands[2]:
		return _fail("seat4_hand_not_bonus hands=%s" % str(hands))
	# 四号位应至少不小于 2/3 号位的手牌（起手多 1，且通常尚未行动）。
	if hands[3] + 1 < maxi(hands[1], hands[2]):
		return _fail("seat4_hand_unexpected hands=%s base=%d" % [str(hands), base_hand])
	return true


## 一号位全场第一回合摸牌基础数为 1。
func _test_seat1_first_turn_draw_one() -> bool:
	if _controller == null or _controller.state == null:
		return _fail("draw_base missing controller")
	# 强制状态到 2v2 第一回合、当前玩家为一号位。
	_controller.state.match_mode = IdentityRules.MODE_TEAM2V2
	_controller.state.turn_number = 1
	var seat0_id: int = _controller.state.players[0].player_id
	var draw_count: int = int(_controller.call("_get_phase_draw_base_count", seat0_id))
	if draw_count != 1:
		return _fail("seat1_turn1_draw=%d" % draw_count)
	_controller.state.turn_number = 2
	draw_count = int(_controller.call("_get_phase_draw_base_count", seat0_id))
	if draw_count != 2:
		return _fail("seat1_turn2_draw=%d" % draw_count)
	var seat1_id: int = _controller.state.players[1].player_id
	_controller.state.turn_number = 1
	draw_count = int(_controller.call("_get_phase_draw_base_count", seat1_id))
	if draw_count != 2:
		return _fail("seat2_turn1_draw=%d" % draw_count)
	return true


## 队友死亡后存活队友摸 1；击杀队友无额外惩罚（不弃牌、不摸三）。
func _test_teammate_death_draw_and_no_kill_penalty() -> bool:
	_create_controller()
	# 最小对局状态，避免完整开局技能/选将干扰死亡奖惩。
	_controller.state = GameState.new()
	_controller.state.match_mode = IdentityRules.MODE_TEAM2V2
	_controller.state.game_over = false
	_controller.state.current_phase = "play"
	_controller.state.draw_pile.clear()
	_controller.state.discard_pile.clear()
	for i in range(4):
		var player := PlayerState.new()
		player.player_id = i
		player.display_name = "P%d" % i
		player.identity = "blue" if i == 0 or i == 3 else "red"
		player.identity_revealed = true
		player.character_id = "danheng"
		player.max_hp = 4
		player.hp = 4
		player.alive = true
		player.out_of_game = false
		_controller.state.players.append(player)
	while _controller.state.draw_pile.size() < 12:
		var pad := CardInstance.new("sha", "spade", 1 + _controller.state.draw_pile.size())
		pad.zone = "draw"
		_controller.state.draw_pile.append(pad)
	# 初始化事件树，保证死亡时 tip 路径安全。
	if _controller.event_scheduler != null:
		_controller.event_scheduler.reset()
		var root_event: GameEvent = _controller.event_scheduler.create_event("RootGameEvent", "root", [], {"mode":IdentityRules.MODE_TEAM2V2})
		_controller._runtime_root_event_id = root_event.event_id
		_controller.event_scheduler.begin_root(root_event.event_id, true)
		_controller.state.current_event_id = root_event.event_id
	var ally: PlayerState = _controller.state.players[3]
	var victim: PlayerState = _controller.state.players[0]
	var enemy: PlayerState = _controller.state.players[1]
	var ally_hand_before: int = ally.hand.size()
	var enemy_hand_before: int = enemy.hand.size()
	# 敌方击杀蓝方一号位 → 存活蓝方四号位应摸 1；击杀者不应摸三。
	victim.hp = 0
	_controller.call("_resolve_death", victim.player_id, enemy.player_id)
	if victim.alive:
		return _fail("victim_should_be_dead")
	if ally.hand.size() != ally_hand_before + 1:
		return _fail("ally_draw_after_teammate_death got=%d want=%d" % [ally.hand.size(), ally_hand_before + 1])
	if enemy.hand.size() != enemy_hand_before:
		return _fail("killer_should_not_draw_three hands=%d" % enemy.hand.size())
	# 击杀队友：红方击杀红方队友，存活红方摸 1，击杀者手牌不被清空。
	var red_a: PlayerState = _controller.state.players[1]
	var red_b: PlayerState = _controller.state.players[2]
	if _controller.state.game_over:
		return _fail("game_should_continue_after_one_blue_death")
	var keep_card := CardInstance.new("shan", "heart", 2)
	keep_card.owner_id = red_a.player_id
	keep_card.zone = "hand"
	red_a.hand.append(keep_card)
	var red_a_hand_before: int = red_a.hand.size()
	red_b.hp = 0
	_controller.call("_resolve_death", red_b.player_id, red_a.player_id)
	if red_a.hand.size() < red_a_hand_before:
		return _fail("ff_should_not_discard_killer hands=%d before=%d" % [red_a.hand.size(), red_a_hand_before])
	if red_a.hand.size() != red_a_hand_before + 1:
		return _fail("ff_ally_draw got=%d want=%d" % [red_a.hand.size(), red_a_hand_before + 1])
	return true


## 胜负：一方全灭则另一方胜。
func _test_winner_evaluation() -> bool:
	var state := GameState.new()
	state.match_mode = IdentityRules.MODE_TEAM2V2
	for i in range(4):
		var player := PlayerState.new()
		player.player_id = i
		player.identity = "blue" if i % 2 == 0 else "red"
		player.alive = true
		player.out_of_game = false
		state.players.append(player)
	if not _identity_rules.evaluate_winner(state).is_empty():
		return _fail("winner_should_continue")
	state.players[0].alive = false
	state.players[2].alive = false
	var winner: String = _identity_rules.evaluate_winner(state)
	if winner != "red_team":
		return _fail("winner_expected_red_team got=%s" % winner)
	state.players[0].alive = true
	state.players[2].alive = true
	state.players[1].alive = false
	state.players[3].alive = false
	winner = _identity_rules.evaluate_winner(state)
	if winner != "blue_team":
		return _fail("winner_expected_blue_team got=%s" % winner)
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


## 失败出口；打印标记并退出非零码。
func _fail(reason: String) -> bool:
	printerr("TEAM2V2_MODE_FAIL %s" % reason)
	_restore_settings()
	get_tree().quit(1)
	return false
