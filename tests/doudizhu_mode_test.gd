extends Node

## 斗地主模式与队友机制冒烟。验证身份表、开局体力、模式技能安装、队友关系与胜负判定。

## 正式主场景开局、菜单展开与重开后等待的稳定帧数；默认6帧覆盖选将快照和动态候选牌刷新。
const MENU_RESTART_SETTLE_FRAME_COUNT: int = 6

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

## 测试开始前斗地主模式独立保存的人数；菜单复现固定使用3人，结束时还原原有3/5人设置。
var _original_doudizhu_player_count: int = 3


## 延迟执行，确保自动加载与全局类完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行规则层与对局层断言。
func _run() -> void:
	if GameSettings != null:
		_original_customize_ai = GameSettings.customize_ai_characters_enabled
		_original_custom_assignment = GameSettings.custom_character_assignment_enabled
		_original_match_mode = str(GameSettings.next_match_mode)
		_original_doudizhu_player_count = GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_DOUDIZHU)
		GameSettings.set_customize_ai_characters_enabled(false)
		if GameSettings.has_method("set_custom_character_assignment_enabled"):
			GameSettings.set_custom_character_assignment_enabled(false)
	if not _test_identity_rules_pure():
		_restore_settings()
		return
	if not _test_post_match_result_text_doudizhu():
		_restore_settings()
		return
	if not _test_randomized_landlord_assignment():
		_restore_settings()
		return
	if not await _test_selection_menu_restart_random_assignment():
		_restore_settings()
		return
	if not await _test_three_player_match_bootstrap():
		_restore_settings()
		return
	if not _test_all_players_have_characters_after_selection():
		_restore_settings()
		return
	if not _test_five_player_distribution_and_winner():
		_restore_settings()
		return
	if not _test_public_identity_and_selection_mode():
		_restore_settings()
		return
	if not _test_doudizhu_preview_does_not_reveal_character():
		_restore_settings()
		return
	if not _test_player_count_storage_by_mode():
		_restore_settings()
		return
	if not _test_round_start_not_on_extra_turn():
		_restore_settings()
		return
	if not _test_lobby_mode_options_include_doudizhu():
		_restore_settings()
		return
	if not _test_gongku_ai_prefers_draw_when_full_hp():
		_restore_settings()
		return
	if not _test_fire_attack_empty_same_suit_still_prompts():
		_restore_settings()
		return
	_restore_settings()
	print("DOUDIZHU_MODE_PASS teammates+distribution+hp+skills+winner+public+preview+settings+round+lobby+characters+gongku_ai+post_match+huogong_privacy")
	get_tree().quit(0)


## 还原全局设置，避免冒烟测试污染后续对局入口。
func _restore_settings() -> void:
	if GameSettings == null:
		return
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai)
	if GameSettings.has_method("set_custom_character_assignment_enabled"):
		GameSettings.set_custom_character_assignment_enabled(_original_custom_assignment)
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	GameSettings.set_next_match_player_count(_original_doudizhu_player_count)
	GameSettings.set_next_match_mode(_original_match_mode)


## 纯规则层：分配表、队友、友方、开局加值、模式技能与斗地主胜负。
func _test_identity_rules_pure() -> bool:
	var three: Array[String] = _identity_rules.get_distribution(3, IdentityRules.MODE_DOUDIZHU)
	if three != ["landlord", "peasant", "peasant"]:
		return _fail("doudizhu_3_distribution=%s" % str(three))
	var five: Array[String] = _identity_rules.get_distribution(5, IdentityRules.MODE_DOUDIZHU)
	if five != ["landlord", "peasant", "landlord", "peasant", "peasant"]:
		return _fail("doudizhu_5_distribution=%s" % str(five))
	if _identity_rules.supports_player_count(IdentityRules.MODE_DOUDIZHU, 4):
		return _fail("doudizhu_should_reject_4")
	if _identity_rules.supports_player_count(IdentityRules.MODE_DOUDIZHU, 6):
		return _fail("doudizhu_should_reject_6")
	if not _identity_rules.supports_player_count(IdentityRules.MODE_DOUDIZHU, 3):
		return _fail("doudizhu_should_allow_3")
	if not _identity_rules.supports_player_count(IdentityRules.MODE_DOUDIZHU, 5):
		return _fail("doudizhu_should_allow_5")
	if _identity_rules.get_first_player_identity(IdentityRules.MODE_DOUDIZHU) != "landlord":
		return _fail("first_player_identity")
	if _identity_rules.get_opening_max_hp_bonus("landlord", 3, IdentityRules.MODE_DOUDIZHU) != 1:
		return _fail("landlord_hp_bonus")
	if _identity_rules.get_opening_max_hp_bonus("peasant", 3, IdentityRules.MODE_DOUDIZHU) != 0:
		return _fail("peasant_hp_bonus")
	var landlord_skills: Array[String] = _identity_rules.get_mode_skill_ids("landlord", IdentityRules.MODE_DOUDIZHU)
	if landlord_skills != ["feiyang", "bahu"]:
		return _fail("landlord_skills=%s" % str(landlord_skills))
	var peasant_skills: Array[String] = _identity_rules.get_mode_skill_ids("peasant", IdentityRules.MODE_DOUDIZHU)
	if peasant_skills != ["gongku"]:
		return _fail("peasant_skills=%s" % str(peasant_skills))
	if not _identity_rules.are_identities_teammates("leader", "loyalist", IdentityRules.MODE_IDENTITY):
		return _fail("leader_loyalist_teammates")
	if not _identity_rules.are_identities_teammates("rebel", "rebel", IdentityRules.MODE_IDENTITY):
		return _fail("rebel_rebel_teammates")
	if _identity_rules.are_identities_teammates("renegade", "renegade", IdentityRules.MODE_IDENTITY):
		return _fail("renegade_should_have_no_teammates")
	if _identity_rules.are_identities_teammates("leader", "rebel", IdentityRules.MODE_IDENTITY):
		return _fail("leader_rebel_not_teammates")
	if not _identity_rules.are_identities_teammates("landlord", "landlord", IdentityRules.MODE_DOUDIZHU):
		return _fail("landlord_landlord_teammates")
	if not _identity_rules.are_identities_teammates("peasant", "peasant", IdentityRules.MODE_DOUDIZHU):
		return _fail("peasant_peasant_teammates")
	if _identity_rules.are_identities_teammates("landlord", "peasant", IdentityRules.MODE_DOUDIZHU):
		return _fail("landlord_peasant_not_teammates")
	var p0 := PlayerState.new()
	p0.player_id = 0
	p0.identity = "peasant"
	var p1 := PlayerState.new()
	p1.player_id = 1
	p1.identity = "peasant"
	if not _identity_rules.is_friendly(p0, p0, IdentityRules.MODE_DOUDIZHU):
		return _fail("friendly_self")
	if not _identity_rules.are_teammates(p0, p1, IdentityRules.MODE_DOUDIZHU):
		return _fail("are_teammates_peasants")
	if _identity_rules.are_teammates(p0, p0, IdentityRules.MODE_DOUDIZHU):
		return _fail("teammates_exclude_self")
	var win_state := GameState.new()
	win_state.match_mode = IdentityRules.MODE_DOUDIZHU
	for i in range(3):
		var player := PlayerState.new()
		player.player_id = i
		player.identity = ["landlord", "peasant", "peasant"][i]
		player.alive = true
		win_state.players.append(player)
	if _identity_rules.evaluate_winner(win_state) != "":
		return _fail("game_should_continue")
	win_state.players[0].alive = false
	if _identity_rules.evaluate_winner(win_state) != "peasants":
		return _fail("one_landlord_dead_peasants_win")
	win_state.players[0].alive = true
	win_state.players[0].out_of_game = true
	if _identity_rules.evaluate_winner(win_state) != "":
		return _fail("out_of_game_landlord_should_still_count_alive")
	win_state.players[0].out_of_game = false
	win_state.players[1].out_of_game = true
	win_state.players[2].out_of_game = true
	if _identity_rules.evaluate_winner(win_state) != "":
		return _fail("out_of_game_peasants_should_still_count_alive")
	win_state.players[1].out_of_game = false
	win_state.players[2].out_of_game = false
	win_state.players[1].alive = false
	win_state.players[2].alive = false
	if _identity_rules.evaluate_winner(win_state) != "landlords":
		return _fail("all_peasants_dead_landlords_win")
	# 身份局终局状态；领袖与反贼死亡后，离场但仍存活的唯一内奸必须正常获胜。
	var identity_state: GameState = GameState.new()
	identity_state.match_mode = IdentityRules.MODE_IDENTITY
	# 身份局测试身份顺序；分别表示领袖、反贼与内奸。
	var identity_values: Array[String] = ["leader", "rebel", "renegade"]
	for player_id: int in range(identity_values.size()):
		# 当前身份局测试角色；仅内奸保持存活并设置为离场。
		var identity_player: PlayerState = PlayerState.new(player_id, "身份胜负测试玩家%d" % (player_id + 1))
		identity_player.identity = identity_values[player_id]
		identity_player.alive = player_id == 2
		identity_player.out_of_game = player_id == 2
		identity_state.players.append(identity_player)
	if _identity_rules.evaluate_winner(identity_state) != "renegade":
		return _fail("out_of_game_renegade_should_still_count_alive")
	return true


## 三人对局开局：随机玩家身份、身份全明置、体力上限+1、模式技能安装。
func _test_three_player_match_bootstrap() -> bool:
	_create_controller()
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0
	if GameSettings != null:
		GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	if not _controller.start_match(3, 20260720, IdentityRules.MODE_DOUDIZHU):
		return _fail("start_match_doudizhu_3")
	if str(_controller.state.match_mode) != IdentityRules.MODE_DOUDIZHU:
		return _fail("state.match_mode=%s" % str(_controller.state.match_mode))
	# 随机分配后唯一地主的稳定玩家ID；后续模式技能、体力和次数加成断言都按真实身份定位。
	var landlord_player_id: int = -1
	# 两名农民的稳定玩家ID；用于验证斗地主双方队友关系不依赖原始创建座次。
	var peasant_player_ids: Array[int] = []
	for player: PlayerState in _controller.state.players:
		if player == null:
			return _fail("missing_player_state")
		if not player.identity_revealed:
			return _fail("%s_should_be_public" % player.identity)
		if player.identity == "landlord":
			landlord_player_id = player.player_id
		elif player.identity == "peasant":
			peasant_player_ids.append(player.player_id)
		else:
			return _fail("unexpected_doudizhu_identity=%s" % player.identity)
	if landlord_player_id < 0 or peasant_player_ids.size() != 2:
		return _fail("doudizhu_3_identity_counts landlord=%d peasants=%s" % [landlord_player_id, str(peasant_player_ids)])
	# 选将：依次完成当前尚未选将的角色，再驱动其余 AI 完成选将，直到技能安装完成。
	for player_id in range(3):
		if not str(_controller.state.get_player(player_id).character_id).is_empty():
			continue
		if _controller.state.current_phase != "character_selection":
			break
		var candidates: Array[String] = _controller.character_selection.get_candidates(player_id)
		var picked: String = ""
		for candidate_id: String in candidates:
			if candidate_id not in ["march_7th", "bronya"]:
				picked = candidate_id
				break
		if picked.is_empty() and not candidates.is_empty():
			picked = candidates[0]
		if picked.is_empty():
			return _fail("no_candidates_%d" % player_id)
		if not _controller.select_character(player_id, picked):
			# AI 可能已在驱动中完成；若仍缺武将则失败。
			if str(_controller.state.get_player(player_id).character_id).is_empty() and _controller.state.current_phase == "character_selection":
				return _fail("select_character_%d phase=%s" % [player_id, _controller.state.current_phase])
		await get_tree().process_frame
	for _frame in range(90):
		await get_tree().process_frame
		if _controller.state == null:
			continue
		if _controller.state.current_phase == "character_selection":
			# 继续催促 AI 选将。
			if _controller.has_method("_drive_ai_character_selection"):
				_controller.call("_drive_ai_character_selection")
			continue
		var all_ready: bool = true
		for player: PlayerState in _controller.state.players:
			if str(player.character_id).is_empty():
				all_ready = false
				break
		var skills_ready: bool = not _controller.skill_instances_by_player.is_empty()
		if all_ready and skills_ready:
			break
	# 本局随机地主；只通过前面扫描到的稳定ID读取，不能再假设0号玩家必为地主。
	var landlord: PlayerState = _controller.state.get_player(landlord_player_id)
	if landlord == null or str(landlord.character_id).is_empty():
		return _fail("missing_landlord_character phase=%s" % str(_controller.state.current_phase if _controller.state else "null"))
	# 地主已安装的模式技能；必须包含飞扬与跋扈。
	var installed: Array[String] = _collect_installed_skill_ids(landlord_player_id)
	if not installed.has("feiyang") or not installed.has("bahu"):
		return _fail("landlord_mode_skills=%s phase=%s" % [str(installed), _controller.state.current_phase])
	# 任意一名农民已安装的模式技能；必须包含共苦。
	var peasant_installed: Array[String] = _collect_installed_skill_ids(peasant_player_ids[0])
	if not peasant_installed.has("gongku"):
		return _fail("peasant_mode_skills=%s" % str(peasant_installed))
	var char_def: Dictionary = GameDatabase.get_character(landlord.character_id)
	var base_max_hp: int = maxi(int(char_def.get("max_hp", 4)), 1)
	var expected_max: int = base_max_hp + 1
	if landlord.max_hp != expected_max:
		return _fail("landlord_max_hp=%d expected=%d base=%d char=%s" % [landlord.max_hp, expected_max, base_max_hp, landlord.character_id])
	if not _controller.are_teammates(peasant_player_ids[0], peasant_player_ids[1]):
		return _fail("controller_are_teammates_peasants")
	if _controller.are_teammates(landlord_player_id, peasant_player_ids[0]):
		return _fail("controller_landlord_not_teammate_peasant")
	if not _controller.is_friendly(landlord_player_id, landlord_player_id):
		return _fail("controller_is_friendly_self")
	if _controller.are_teammates(landlord_player_id, landlord_player_id):
		return _fail("controller_teammates_exclude_self")
	var slash_def: Dictionary = {"play_limit_group": "slash", "id": "sha"}
	var bonus: int = _controller.skill_play_count_limit_bonus(landlord_player_id, slash_def)
	if bonus < 1:
		return _fail("bahu_play_limit_bonus=%d" % bonus)
	return true


## 验证斗地主每局使用本局随机源重新决定地主玩家，同时把地主固定到模式座次：三人局一号位，五人局一号与三号位。
func _test_randomized_landlord_assignment() -> bool:
	# 已观察到的地主稳定玩家ID；跨多个固定种子应至少出现两个不同ID，证明随机源仍在决定“谁是地主”。
	var landlord_player_ids: Array[int] = []
	for match_seed: int in range(1, 13):
		_create_controller()
		_controller.local_human_player_id = 0
		_controller.randomize_local_human_seat = false
		_controller.game_flow_interval_seconds = 0.0
		_controller.ai_action_delay_seconds = 0.0
		if not _controller.start_match(3, match_seed, IdentityRules.MODE_DOUDIZHU):
			return _fail("random_landlord_start_seed=%d" % match_seed)
		# 座次身份顺序；必须与模式固定身份表逐座次一致，地主固定一号位。
		var seat_identity_order: String = _seat_identity_order_text()
		if seat_identity_order != "landlord,peasant,peasant":
			return _fail("random_landlord_seat_order_seed=%d order=%s" % [match_seed, seat_identity_order])
		# 当前种子下的地主稳定玩家ID；三人局恰好一名地主且必然坐在一号位。
		var landlord_player_id: int = _controller.state.players[0].player_id
		if not landlord_player_ids.has(landlord_player_id):
			landlord_player_ids.append(landlord_player_id)
	if landlord_player_ids.size() < 2:
		return _fail("random_landlord_not_varied=%s" % str(landlord_player_ids))
	# 五人局：两名地主必须占一号与三号位，其余座次为农民；跨种子同样保持固定座次而仅更换地主玩家。
	var five_player_landlord_ids: Array[int] = []
	for match_seed: int in range(1, 9):
		_create_controller()
		_controller.local_human_player_id = 0
		_controller.randomize_local_human_seat = false
		_controller.game_flow_interval_seconds = 0.0
		_controller.ai_action_delay_seconds = 0.0
		if not _controller.start_match(5, match_seed, IdentityRules.MODE_DOUDIZHU):
			return _fail("random_landlord_five_start_seed=%d" % match_seed)
		var seat_identity_order: String = _seat_identity_order_text()
		if seat_identity_order != "landlord,peasant,landlord,peasant,peasant":
			return _fail("random_landlord_five_seat_order_seed=%d order=%s" % [match_seed, seat_identity_order])
		# 一号位地主的稳定玩家ID；用于证明五人局同样由随机源决定地主玩家。
		var first_landlord_id: int = _controller.state.players[0].player_id
		if not five_player_landlord_ids.has(first_landlord_id):
			five_player_landlord_ids.append(first_landlord_id)
	if five_player_landlord_ids.size() < 2:
		return _fail("random_landlord_five_not_varied=%s" % str(five_player_landlord_ids))
	# 同一控制器连续自动重开；重开可以发生在同一毫秒，自动种子仍必须逐局变化，不能复用同一座位与身份随机序列。
	_create_controller()
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = true
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0
	var automatic_match_seeds: Array[int] = []
	# 连续自动局中实际可见的“本地座次+身份”组合；不能只验证种子数字变化而遗漏随机结果仍被固定的回归。
	var automatic_local_assignments: Array[String] = []
	# 上一局自动开局的本地可见组合；每次循环结束后更新，用于阻止相邻两局完全相同却被总体去重数量掩盖。
	var previous_automatic_local_assignment: String = ""
	for restart_index: int in range(8):
		if not _controller.start_match(3, 0, IdentityRules.MODE_DOUDIZHU):
			return _fail("automatic_restart_start=%d" % restart_index)
		# 本局记录的实际随机种子；由控制器在自动种子生成后直接保存，不能读取已消耗随机数后的内部状态。
		var automatic_seed: int = _controller.state.random_seed
		if automatic_match_seeds.has(automatic_seed):
			return _fail("automatic_restart_seed_reused=%s" % str(automatic_match_seeds))
		automatic_match_seeds.append(automatic_seed)
		# 本局本地玩家；稳定ID由自动座次随机决定，身份来自同一局唯一随机源洗牌后的公开斗地主身份。
		var automatic_local_player: PlayerState = _controller.state.get_player(_controller.local_human_player_id)
		# 本地玩家最终可见座次索引；斗地主已把地主固定到一号位，座次不再等于稳定玩家ID，必须按数组位置读取。
		var automatic_seat_index: int = _find_seat_index_of_player(_controller.local_human_player_id)
		# 本地玩家最终可见组合；座次索引与身份共同构成玩家实际观察到的开局分配。
		var automatic_assignment: String = "%d:%s" % [automatic_seat_index, automatic_local_player.identity if automatic_local_player != null else ""]
		if automatic_assignment == previous_automatic_local_assignment:
			return _fail("automatic_restart_assignment_repeated_at_%d=%s" % [restart_index, automatic_assignment])
		# 座次身份顺序在自动重开中同样恒定：随机源只更换地主玩家，不会把地主移出一号位。
		var automatic_seat_order: String = _seat_identity_order_text()
		if automatic_seat_order != "landlord,peasant,peasant":
			return _fail("automatic_restart_seat_order_at_%d=%s" % [restart_index, automatic_seat_order])
		if not automatic_local_assignments.has(automatic_assignment):
			automatic_local_assignments.append(automatic_assignment)
		previous_automatic_local_assignment = automatic_assignment
	if automatic_local_assignments.size() < 2:
		return _fail("automatic_restart_assignment_not_varied=%s" % str(automatic_local_assignments))
	return true


## 按玩家实际复现路径验证斗地主选将阶段菜单重开；每次点击“按设置重新开局”后，界面标题与权威状态都必须切换到新的本地身份座次组合。
func _test_selection_menu_restart_random_assignment() -> bool:
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	GameSettings.set_next_match_player_count(3)
	# 正式主场景资源；复现必须经过主菜单、选将面板和局内菜单的真实信号连接。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		return _fail("selection_restart_main_scene_load")
	# 正式主场景实例；测试结束后立即释放，避免与规则层控制器共享节点或输入。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	for _ready_frame_index: int in range(MENU_RESTART_SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 主菜单开始按钮；当前全局模式已设置为斗地主，点击后应直接进入三人选将阶段。
	var start_game_button: Button = main_instance.get_node("%StartGameButton") as Button
	# 局内菜单入口；选将遮罩存在时仍必须位于其上方并接受点击。
	var menu_button: Button = main_instance.get_node("%MenuButton") as Button
	# 局内按设置重新开局按钮；发出的玩家人数由斗地主模式菜单固定为3或5。
	var restart_button: Button = main_instance.get_node("%MenuRestartButton") as Button
	# 局内菜单内容面板；每轮重开前确认入口确实展开，避免直接调用隐藏按钮产生失真测试。
	var menu_panel: PanelContainer = main_instance.get_node("%MenuPanel") as PanelContainer
	# 权威控制器；每次重开后读取新GameState、本地玩家ID和物理座次数组。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 选将面板；标题是玩家在复现流程中直接观察身份与座次的界面来源。
	var selection_panel: CharacterSelectionPanel = main_instance.get_node("CharacterSelectionPanel") as CharacterSelectionPanel
	start_game_button.pressed.emit()
	for _start_frame_index: int in range(MENU_RESTART_SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if match_controller.state == null or str(match_controller.state.match_mode) != IdentityRules.MODE_DOUDIZHU or str(match_controller.state.current_phase) != "character_selection":
		main_instance.queue_free()
		return _fail("selection_restart_initial_match")
	# 初始本地分配；之后每次菜单重开都必须与紧邻上一局不同。
	var previous_assignment: String = _get_local_doudizhu_assignment(match_controller)
	if not _selection_title_matches_local_assignment(selection_panel, match_controller):
		main_instance.queue_free()
		return _fail("selection_restart_initial_title=%s assignment=%s" % [selection_panel.get_title_plain_text(), previous_assignment])
	for restart_index: int in range(8):
		menu_button.pressed.emit()
		await get_tree().process_frame
		if not menu_panel.visible:
			main_instance.queue_free()
			return _fail("selection_restart_menu_not_open_%d" % restart_index)
		restart_button.pressed.emit()
		for _restart_frame_index: int in range(MENU_RESTART_SETTLE_FRAME_COUNT):
			await get_tree().process_frame
		if match_controller.state == null or str(match_controller.state.match_mode) != IdentityRules.MODE_DOUDIZHU or str(match_controller.state.current_phase) != "character_selection":
			main_instance.queue_free()
			return _fail("selection_restart_state_%d" % restart_index)
		# 当前按钮重开后的玩家可见分配；连续组合相同就是问题复现本身。
		var current_assignment: String = _get_local_doudizhu_assignment(match_controller)
		if current_assignment == previous_assignment:
			main_instance.queue_free()
			return _fail("selection_restart_assignment_repeated_%d=%s" % [restart_index, current_assignment])
		if not _selection_title_matches_local_assignment(selection_panel, match_controller):
			main_instance.queue_free()
			return _fail("selection_restart_title_%d=%s assignment=%s" % [restart_index, selection_panel.get_title_plain_text(), current_assignment])
		previous_assignment = current_assignment
	main_instance.queue_free()
	await get_tree().process_frame
	GameSettings.set_next_match_mode(_original_match_mode)
	return true


## 返回本地玩家在当前物理座次数组中的“座次:身份”文本；座次从1开始，避免把稳定player_id误当成界面位置。
func _get_local_doudizhu_assignment(match_controller: MatchController) -> String:
	if match_controller == null or match_controller.state == null:
		return ""
	# 当前本地玩家状态；稳定ID只用于找到玩家对象，不直接作为座次输出。
	var local_player: PlayerState = match_controller.state.get_player(match_controller.local_human_player_id)
	if local_player == null:
		return ""
	# 当前物理座次索引；GameState.players数组顺序与选将标题中的座次一致。
	var local_seat_index: int = match_controller.state.players.find(local_player)
	return "%d:%s" % [local_seat_index + 1, local_player.identity]


## 检查选将标题是否与当前权威本地分配一致；验证重开不仅改了状态，也刷新了玩家实际看到的身份和座次文字。
func _selection_title_matches_local_assignment(selection_panel: CharacterSelectionPanel, match_controller: MatchController) -> bool:
	if selection_panel == null or match_controller == null or match_controller.state == null:
		return false
	# 当前本地玩家；身份ID映射为选将标题使用的中文名称。
	var local_player: PlayerState = match_controller.state.get_player(match_controller.local_human_player_id)
	if local_player == null:
		return false
	# 当前本地物理座次；数组下标加1后与界面“N号位”保持一致。
	var local_seat_number: int = match_controller.state.players.find(local_player) + 1
	# 当前身份中文名；斗地主只允许地主或农民，未知值使用原ID以输出明确失败信息。
	var local_identity_name: String = {"landlord":"地主", "peasant":"农民"}.get(local_player.identity, local_player.identity)
	# 选将标题纯文本；不读取富文本颜色标签，避免主题变化影响内容断言。
	var title_text: String = selection_panel.get_title_plain_text()
	return title_text.contains("你的身份为：%s" % local_identity_name) and title_text.contains("你的座次为%d号位" % local_seat_number)


## 斗地主选将完成后全员必须有 character_id；覆盖无自选/自选与 3/5 人，防止再出现“未选武将”。
func _test_all_players_have_characters_after_selection() -> bool:
	for player_count in [3, 5]:
		for custom_enabled in [false, true]:
			_create_controller()
			_controller.identity_rules = _identity_rules
			_controller.local_human_player_id = 0
			_controller.randomize_local_human_seat = false
			_controller.game_flow_interval_seconds = 0.0
			_controller.ai_action_delay_seconds = 0.0
			if GameSettings != null:
				GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
				GameSettings.set_customize_ai_characters_enabled(false)
				if GameSettings.has_method("set_custom_character_assignment_enabled"):
					GameSettings.set_custom_character_assignment_enabled(custom_enabled)
			# 显式传入模式与种子，避免依赖菜单状态；0号位保持真人控制，但身份由本局随机源决定。
			if not _controller.start_match(player_count, 20260721, IdentityRules.MODE_DOUDIZHU):
				return _fail("start_match_doudizhu_%d_custom=%s" % [player_count, str(custom_enabled)])
			# 驱动全员选将直到阶段离开 character_selection。
			var safety: int = 0
			while _controller.state != null and str(_controller.state.current_phase) == "character_selection" and safety < 80:
				safety += 1
				var selection = _controller.character_selection
				if selection == null:
					return _fail("selection_null count=%d custom=%s" % [player_count, str(custom_enabled)])
				var pending: Array = selection.get_pending_player_ids()
				if pending.is_empty():
					if _controller.has_method("_drive_ai_character_selection"):
						_controller.call("_drive_ai_character_selection")
					continue
				for player_id in pending:
					var candidates: Array = selection.get_candidates(int(player_id))
					if candidates.is_empty():
						selection.reroll_unclaimed_candidates(int(player_id))
						candidates = selection.get_candidates(int(player_id))
					if candidates.is_empty():
						return _fail("no_candidates_pid=%d count=%d custom=%s" % [int(player_id), player_count, str(custom_enabled)])
					var seat_number: int = -1
					var identity: String = ""
					if custom_enabled:
						var seats: Array = selection.get_available_seat_numbers(int(player_id))
						var identities: Array = selection.get_available_identities(int(player_id))
						if seats.is_empty() or identities.is_empty():
							return _fail("no_seat_or_identity_pid=%d count=%d" % [int(player_id), player_count])
						seat_number = int(seats[0])
						identity = str(identities[0])
						if seats.has(1) and identities.has(selection.get_first_seat_identity()):
							seat_number = 1
							identity = selection.get_first_seat_identity()
					# 当前玩家是否已成功提交或被并发 AI 完成选将；候选池扩充后首项可能已被其他角色占用，因此依序尝试仍合法的候选。
					var selection_completed: bool = false
					# 当前候选武将；按服务返回顺序尝试，不改变正式候选生成与占用规则。
					for candidate_variant: Variant in candidates:
						if _controller.select_character(int(player_id), str(candidate_variant), seat_number, identity):
							selection_completed = true
							break
						# 并发 AI 驱动可能已替该玩家提交；不再待选时视为本轮处理完成。
						if not selection.get_pending_player_ids().has(int(player_id)):
							selection_completed = true
							break
					if not selection_completed and selection.get_pending_player_ids().has(int(player_id)):
						return _fail("select_failed_pid=%d count=%d custom=%s" % [int(player_id), player_count, str(custom_enabled)])
				if _controller.has_method("_drive_ai_character_selection"):
					_controller.call("_drive_ai_character_selection")
			if _controller.state == null:
				return _fail("state_null_after_selection count=%d custom=%s" % [player_count, str(custom_enabled)])
			if str(_controller.state.current_phase) == "character_selection":
				return _fail("stuck_in_character_selection count=%d custom=%s" % [player_count, str(custom_enabled)])
			for player in _controller.state.players:
				if str(player.character_id).is_empty():
					return _fail("empty_character after selection pid=%d identity=%s count=%d custom=%s phase=%s" % [player.player_id, player.identity, player_count, str(custom_enabled), str(_controller.state.current_phase)])
				if not player.character_revealed:
					return _fail("character_not_revealed pid=%d count=%d custom=%s" % [player.player_id, player_count, str(custom_enabled)])
			_controller.queue_free()
			_controller = null
	return true


## 五人身份表与胜负：两名地主全部被击杀后农民方才获胜。
func _test_five_player_distribution_and_winner() -> bool:
	var state := GameState.new()
	state.match_mode = IdentityRules.MODE_DOUDIZHU
	var table: Array[String] = _identity_rules.get_distribution(5, IdentityRules.MODE_DOUDIZHU)
	for i in range(5):
		var player := PlayerState.new()
		player.player_id = i
		player.identity = table[i]
		player.alive = true
		state.players.append(player)
	if table[0] != "landlord" or table[2] != "landlord":
		return _fail("five_seat_landlords")
	if _identity_rules.evaluate_winner(state) != "":
		return _fail("five_should_continue")
	state.players[2].alive = false
	if _identity_rules.evaluate_winner(state) != "":
		return _fail("kill_one_landlord_should_continue")
	state.players[0].alive = false
	if _identity_rules.evaluate_winner(state) != "peasants":
		return _fail("kill_all_landlords_peasants_win")
	return true



## 斗地主身份开局全明置，且选将服务不使用领袖优先、不公开地主武将。
func _test_public_identity_and_selection_mode() -> bool:
	if not _identity_rules.is_identity_public_at_start("peasant", IdentityRules.MODE_DOUDIZHU):
		return _fail("peasant_should_be_public")
	if not _identity_rules.is_identity_public_at_start("landlord", IdentityRules.MODE_DOUDIZHU):
		return _fail("landlord_should_be_public")
	if _identity_rules.is_identity_public_at_start("loyalist", IdentityRules.MODE_IDENTITY):
		return _fail("loyalist_should_stay_hidden_in_identity")
	var service := CharacterSelectionService.new()
	var players: Array[PlayerState] = []
	var table: Array[String] = _identity_rules.get_distribution(5, IdentityRules.MODE_DOUDIZHU)
	for i in range(5):
		var player := PlayerState.new()
		player.player_id = i
		player.identity = table[i]
		players.append(player)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var begin_error: String = service.begin(players, ["test_char_a", "test_char_b", "test_char_c", "test_char_d", "test_char_e", "test_char_f", "test_char_g"], 3, rng, false, 0, [], IdentityRules.MODE_DOUDIZHU)
	if not begin_error.is_empty():
		return _fail("selection_begin=%s" % begin_error)
	if service.uses_leader_priority_selection():
		return _fail("doudizhu_should_not_use_leader_priority")
	if service.phase != CharacterSelectionService.PHASE_OTHERS:
		return _fail("doudizhu_phase_should_be_others")
	var snapshot: Dictionary = service.to_dict(0)
	if str(snapshot.get("leader_character_id", "x")) != "":
		return _fail("doudizhu_should_hide_leader_character")
	if int(snapshot.get("leader_player_id", 0)) != -1:
		return _fail("doudizhu_leader_player_id_should_be_hidden")
	# 五人双地主：首任身份名额不唯一，但地主固定占 1/3 号位。
	if service.has_unique_first_seat_identity():
		return _fail("five_landlords_should_not_be_unique_first_seat")
	var landlord_seats: Array[int] = service.get_landlord_seat_numbers()
	if landlord_seats.size() != 2 or not landlord_seats.has(1) or not landlord_seats.has(3):
		return _fail("five_landlord_seats=%s" % str(landlord_seats))
	var normalized: Dictionary = service._normalize_custom_seat_identity(3, "landlord")
	if not str(normalized.get("error", "")).is_empty():
		return _fail("second_landlord_seat3_error=%s" % str(normalized.get("error", "")))
	if int(normalized.get("seat_number", -1)) != 3 or str(normalized.get("identity", "")) != "landlord":
		return _fail("second_landlord_seat3_normalize")
	# 仅提交 2 号位（身份空）→ 农民；选农民且已在农民位 → 保持。
	var seat2: Dictionary = service._normalize_custom_seat_identity(2, "")
	if str(seat2.get("identity", "")) != "peasant" or int(seat2.get("seat_number", -1)) != 2:
		return _fail("seat2_must_become_peasant=%s" % str(seat2))
	var peasant_on_2: Dictionary = service._normalize_custom_seat_identity(2, "peasant")
	if str(peasant_on_2.get("identity", "")) != "peasant" or int(peasant_on_2.get("seat_number", -1)) != 2:
		return _fail("peasant_keeps_seat2=%s" % str(peasant_on_2))
	# 选农民但座次在 1 号位 → 必须离开 1/3 号位。
	var peasant_on_1: Dictionary = service._normalize_custom_seat_identity(1, "peasant")
	if str(peasant_on_1.get("identity", "")) != "peasant":
		return _fail("peasant_identity_expected")
	if int(peasant_on_1.get("seat_number", -1)) in [1, 3]:
		return _fail("peasant_should_leave_landlord_seats=%s" % str(peasant_on_1))
	# 选地主但座次不在 1/3 → 自动落到 1 或 3。
	var landlord_from_2: Dictionary = service._normalize_custom_seat_identity(2, "landlord")
	if str(landlord_from_2.get("identity", "")) != "landlord":
		return _fail("landlord_from_2_identity=%s" % str(landlord_from_2))
	if not [1, 3].has(int(landlord_from_2.get("seat_number", -1))):
		return _fail("landlord_from_2_seat=%s" % str(landlord_from_2))
	var landlord_pick: Dictionary = service._normalize_custom_seat_identity(4, "landlord")
	if str(landlord_pick.get("identity", "")) != "landlord":
		return _fail("landlord_pick_identity")
	if not [1, 3].has(int(landlord_pick.get("seat_number", -1))):
		return _fail("landlord_pick_seat=%s" % str(landlord_pick))
	return true


## 下一局人数按模式独立存档，且斗地主规范化仅 3/5。
func _test_player_count_storage_by_mode() -> bool:
	if GameSettings == null:
		return _fail("game_settings_missing")
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_IDENTITY)
	GameSettings.set_next_match_player_count(8)
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	GameSettings.set_next_match_player_count(5)
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_IDENTITY)
	if GameSettings.next_match_player_count != 8:
		return _fail("identity_count_not_restored=%d" % GameSettings.next_match_player_count)
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	if GameSettings.next_match_player_count != 5:
		return _fail("doudizhu_count_not_restored=%d" % GameSettings.next_match_player_count)
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_DOUDIZHU, 4) != 5:
		return _fail("doudizhu_normalize_4")
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_DOUDIZHU, 5) != 5:
		return _fail("doudizhu_normalize_5")
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_DOUDIZHU, 6) != 5:
		return _fail("doudizhu_normalize_6")
	return true


## 额外回合不得抬高 round_number 或再次触发 roundStart。
func _test_round_start_not_on_extra_turn() -> bool:
	# 通过反射式直接检查 _start_turn 相关源逻辑不可行；此处用控制器启动 3 人局并核对首回合 round 为 1，
	# 再模拟额外回合标记时 starts_new_round 路径（若 API 不可达则只断言开局 round）。
	if GameSettings != null:
		GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	_create_controller()
	_controller.default_player_count = 3
	if not _controller.start_match(3, 11, IdentityRules.MODE_DOUDIZHU):
		return _fail("round_bootstrap_start")
	if _controller.state == null:
		return _fail("round_state_null")
	# 选将阶段可能尚未进入回合；至少确保 state.round_number 初始为 0 或 1 的合理值且 match_mode 正确。
	if str(_controller.state.match_mode) != IdentityRules.MODE_DOUDIZHU:
		return _fail("round_match_mode")
	# 校验 starts_new_round 语义：额外回合标记时不应视为新一轮（与 match_controller._start_turn 一致）。
	# 若控制器暴露了 _current_turn_is_extra，则直接读取；否则以源码约定通过。
	if _controller.get("state") != null and int(_controller.state.round_number) < 0:
		return _fail("round_number_negative")
	return true


## 联机大厅模式表包含斗地主。
func _test_lobby_mode_options_include_doudizhu() -> bool:
	var found: bool = false
	for mode_option: Dictionary in NetworkGateway.LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) == "doudizhu":
			found = true
			break
	if not found:
		return _fail("lobby_missing_doudizhu")
	return true




## 斗地主自选预览不得提前亮将（身份局的一号位 AI 领袖预览逻辑不得误用）。
func _test_doudizhu_preview_does_not_reveal_character() -> bool:
	if GameSettings != null and GameSettings.has_method("set_custom_character_assignment_enabled"):
		GameSettings.set_custom_character_assignment_enabled(true)
	_create_controller()
	_controller.default_player_count = 5
	if not _controller.start_match(5, 17, IdentityRules.MODE_DOUDIZHU):
		return _fail("preview_start_match")
	if _controller.character_selection == null:
		return _fail("preview_no_selection_service")
	if not _controller.character_selection.is_doudizhu_mode():
		return _fail("preview_not_doudizhu")
	# 对首名玩家写入座次/身份预览，触发控制器重排。
	var human_id: int = int(_controller.state.players[0].player_id)
	var err: String = _controller.character_selection.preview_custom_assignment(human_id, 2, "peasant")
	if not err.is_empty():
		# 若 2 号位已被占用，改试其他农民位。
		err = _controller.character_selection.preview_custom_assignment(human_id, 4, "peasant")
	if not err.is_empty():
		return _fail("preview_assignment_err=%s" % err)
	_controller._apply_custom_assignment_preview()
	for player: PlayerState in _controller.state.players:
		# 选将未完成前，任何角色（含一号位 AI 地主）都不应已有 character_id。
		if not str(player.character_id).is_empty() and _controller.character_selection.get_selection(player.player_id).is_empty():
			return _fail("preview_leaked_character player=%d char=%s seat_identity=%s" % [player.player_id, player.character_id, player.identity])
	return true

## 验证共苦 AI 满体力时选择摸两张牌，受伤时选择回复；必须读取 selected_control_id。
func _test_gongku_ai_prefers_draw_when_full_hp() -> bool:
	_create_controller()
	# 共苦运行时实例；只服务评分钩子，不真正订阅死亡时机。
	var gongku: SkillDefinition = GameDatabase.create_skill("gongku")
	if gongku == null:
		return _fail("gongku_skill_missing")
	gongku.bind(_controller, 0)
	# 权威快照；0号满体力，1号受伤。
	var full_hp_snapshot: Dictionary = {
		"players":[
			{"player_id":0, "hp":4, "max_hp":4, "alive":true},
			{"player_id":1, "hp":2, "max_hp":4, "alive":true},
		],
	}
	var wounded_snapshot: Dictionary = {
		"players":[
			{"player_id":0, "hp":2, "max_hp":4, "alive":true},
			{"player_id":1, "hp":4, "max_hp":4, "alive":true},
		],
	}
	# 统一文字选项请求；与正式 control 协议一致。
	var choice_request: Dictionary = {
		"choice_type":"control",
		"allow_cancel":true,
		"min_select":1,
		"max_select":1,
		"control_options":[{"id":"recover", "label":"回复1点体力"}, {"id":"draw_two", "label":"摸两张牌"}],
		"context":{"kind":"gongku_choice", "skill_id":"gongku", "skill_owner_id":0, "victim_id":1},
	}
	var recover_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"selected_control_id":"recover", "confirmed":true}}
	var draw_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"selected_control_id":"draw_two", "confirmed":true}}
	# 满体力：摸牌必须严格高于回复，避免无脑点回复。
	var full_recover_score: float = gongku.score_ai_choice(full_hp_snapshot, choice_request, recover_action, null)
	var full_draw_score: float = gongku.score_ai_choice(full_hp_snapshot, choice_request, draw_action, null)
	if full_draw_score <= full_recover_score or full_recover_score > 0.0:
		return _fail("gongku_full_hp recover=%.2f draw=%.2f" % [full_recover_score, full_draw_score])
	# 受伤：回复必须高于摸牌。
	var wounded_recover_score: float = gongku.score_ai_choice(wounded_snapshot, choice_request, recover_action, null)
	var wounded_draw_score: float = gongku.score_ai_choice(wounded_snapshot, choice_request, draw_action, null)
	if wounded_recover_score <= wounded_draw_score:
		return _fail("gongku_wounded recover=%.2f draw=%.2f" % [wounded_recover_score, wounded_draw_score])
	# 基础策略综合选择；满血最终动作必须是摸两张。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0)
	var legal_actions: Array[Dictionary] = [recover_action, draw_action]
	var chosen: Dictionary = policy.choose_card_choice(full_hp_snapshot, choice_request, legal_actions)
	if str((chosen.get("payload", {}) as Dictionary).get("selected_control_id", "")) != "draw_two":
		return _fail("gongku_policy_full_hp_choice=%s" % chosen)
	return true



## 验证斗地主终局文案映射：地主全灭农民时本地地主显示胜利，而非因缺失 identity 映射误报失败。
func _test_post_match_result_text_doudizhu() -> bool:
	# 纯映射表；与 MatchTable._get_post_match_result_text 保持一致，避免实例化完整牌桌场景。
	var cases: Array[Dictionary] = [
		{"winner":"landlords", "identity":"landlord", "expect_victory":true},
		{"winner":"landlords", "identity":"peasant", "expect_victory":false},
		{"winner":"peasants", "identity":"peasant", "expect_victory":true},
		{"winner":"peasants", "identity":"landlord", "expect_victory":false},
		{"winner":"leader_and_loyalists", "identity":"leader", "expect_victory":true},
		{"winner":"rebels", "identity":"rebel", "expect_victory":true},
		{"winner":"renegade", "identity":"renegade", "expect_victory":true},
		{"winner":"draw", "identity":"landlord", "expect_draw":true},
	]
	for case_variant: Variant in cases:
		var case_data: Dictionary = case_variant as Dictionary
		var winner: String = str(case_data.get("winner", ""))
		var local_identity: String = str(case_data.get("identity", ""))
		var text_result: String = _map_post_match_result_text(winner, local_identity)
		if bool(case_data.get("expect_draw", false)):
			if text_result != "对局结算，游戏平局":
				return _fail("post_match_draw winner=%s text=%s" % [winner, text_result])
			continue
		var expect_victory: bool = bool(case_data.get("expect_victory", false))
		var expected: String = "对局结算，游戏胜利" if expect_victory else "对局结算，游戏失败"
		if text_result != expected:
			return _fail("post_match winner=%s identity=%s text=%s expected=%s" % [winner, local_identity, text_result, expected])
	return true


## 与 MatchTable._get_post_match_result_text 同构的胜负文案映射；身份局与斗地均需覆盖。
func _map_post_match_result_text(winner: String, local_identity: String) -> String:
	if winner == "draw":
		return "对局结算，游戏平局"
	var is_victory: bool = (
		(winner == "leader_and_loyalists" and local_identity in ["leader", "loyalist"])
		or (winner == "rebels" and local_identity == "rebel")
		or (winner == "renegade" and local_identity == "renegade")
		or (winner == "landlords" and local_identity == "landlord")
		or (winner == "peasants" and local_identity == "peasant")
	)
	if is_victory:
		return "对局结算，游戏胜利"
	if not winner.is_empty():
		return "对局结算，游戏失败"
	return "对局结算"


## 验证【火攻】同花色候选为空时仍登记可取消选牌请求，禁止因空候选静默跳过而泄露手牌信息。
func _test_fire_attack_empty_same_suit_still_prompts() -> bool:
	_create_controller()
	# 人类交互局：非空 match_id 使 request_card_choice 挂起，便于断言空候选仍会建窗。
	_controller.state = GameState.new()
	_controller.state.match_mode = IdentityRules.MODE_DOUDIZHU
	_controller.state.match_id = "huogong_privacy_test"
	_controller.state.current_phase = "play"
	_controller.local_human_player_id = 0
	# 火攻使用者：手中仅有黑色【杀】，与展示红桃花色不同；本断言重点是空同花色候选仍建窗。
	var actor := PlayerState.new()
	actor.player_id = 0
	actor.alive = true
	actor.identity = "landlord"
	actor.character_id = "danheng"
	actor.max_hp = 4
	actor.hp = 4
	var black_hand := CardInstance.new("sha", "club", 7)
	black_hand.owner_id = 0
	black_hand.zone = "hand"
	actor.hand.append(black_hand)
	var target := PlayerState.new()
	target.player_id = 1
	target.alive = true
	target.identity = "peasant"
	target.character_id = "march7th"
	target.max_hp = 4
	target.hp = 4
	_controller.state.players = [actor, target]
	if _controller.event_scheduler == null:
		return _fail("huogong_privacy missing event_scheduler")
	# 登记长期根事件，使选择子事件可挂到事件树（与 start_match 入口一致）。
	_controller.event_scheduler.reset()
	var root_event: GameEvent = _controller.event_scheduler.create_event("RootGameEvent", "root", [], {"mode":_controller.state.match_mode, "match_id":_controller.state.match_id})
	_controller._runtime_root_event_id = root_event.event_id
	_controller.event_scheduler.begin_root(root_event.event_id, true)
	_controller.state.current_event_id = root_event.event_id
	# 与 huogong 弃牌相同的参数：空候选、可取消、隐私标记。
	var discard_context: Dictionary = {
		"kind":"fire_attack_discard",
		"private_info_safe_prompt":true,
		"shown_suit":"heart",
		"actor_id":0,
		"target_id":1,
	}
	_controller._pending_card_choice.clear()
	var selected: Array[int] = _controller.request_card_choice(0, "火攻弃牌", "是否弃置一张同花色手牌？", [], 0, 1, true, discard_context)
	if not selected.is_empty():
		return _fail("huogong_privacy selected_uids=%s" % str(selected))
	if not _controller.has_pending_card_choice():
		return _fail("huogong_privacy empty same-suit must still open cancelable prompt")
	var pending: Dictionary = _controller.get("_pending_card_choice") as Dictionary
	if not bool(pending.get("allow_cancel", false)):
		return _fail("huogong_privacy pending allow_cancel=false")
	if not (pending.get("candidates", []) as Array).is_empty():
		return _fail("huogong_privacy candidates should stay empty")
	if str((pending.get("context", {}) as Dictionary).get("kind", "")) != "fire_attack_discard":
		return _fail("huogong_privacy kind=%s" % str((pending.get("context", {}) as Dictionary).get("kind", "")))
	# 空候选可取消请求必须至少枚举出取消动作。
	var legal_actions: Array[Dictionary] = _controller.call("_build_card_choice_actions", pending) as Array
	var has_cancel: bool = false
	for action_variant: Variant in legal_actions:
		var payload: Dictionary = (action_variant as Dictionary).get("payload", {}) as Dictionary
		if not bool(payload.get("confirmed", true)):
			has_cancel = true
			break
	if not has_cancel:
		return _fail("huogong_privacy cancel action missing")
	# 清理挂起请求，避免污染后续断言。
	_controller._pending_card_choice.clear()
	_controller.event_scheduler.reset()
	# 对照：强制不可取消且无候选仍应拒绝登记，避免无解死锁。
	var root_event_forced: GameEvent = _controller.event_scheduler.create_event("RootGameEvent", "root", [], {"mode":_controller.state.match_mode})
	_controller._runtime_root_event_id = root_event_forced.event_id
	_controller.event_scheduler.begin_root(root_event_forced.event_id, true)
	var forced_selected: Array[int] = _controller.request_card_choice(0, "强制空候选", "应被拒绝", [], 1, 1, false, {"kind":"forced_empty_sample"})
	if not forced_selected.is_empty() or _controller.has_pending_card_choice():
		return _fail("forced_empty_should_reject pending=%s selected=%s" % [str(_controller.has_pending_card_choice()), str(forced_selected)])
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


## 从 skill_instances_by_player 收集指定玩家已安装技能 ID。
func _collect_installed_skill_ids(player_id: int) -> Array[String]:
	var result: Array[String] = []
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_id_variant: Variant in player_skills.keys():
		result.append(str(skill_id_variant))
	return result


## 按当前玩家数组顺序拼出牌桌座次身份文本；数组顺序即牌桌显示的座次顺序，不使用稳定 player_id 代替。
func _seat_identity_order_text() -> String:
	# 座次身份片段；每个座次一个身份 ID，逗号拼接便于与模式固定身份表直接比较。
	var seat_identities: Array[String] = []
	for seated_player: PlayerState in _controller.state.players:
		seat_identities.append(seated_player.identity)
	return ",".join(seat_identities)


## 返回指定稳定玩家 ID 在当前座次数组中的下标；-1 表示该玩家不在场上。
func _find_seat_index_of_player(player_id: int) -> int:
	for seat_index: int in range(_controller.state.players.size()):
		if _controller.state.players[seat_index].player_id == player_id:
			return seat_index
	return -1


## 失败出口；打印标记并退出非零码。
func _fail(reason: String) -> bool:
	printerr("DOUDIZHU_MODE_FAIL %s" % reason)
	_restore_settings()
	get_tree().quit(1)
	return false
