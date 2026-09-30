extends Node

## 过关斩将专项回归测试。验证固定单人机缘、敌方无限换将、关卡累计增强、装备子类别与终局规则。

## 权威控制器；复用正式对局组件树验证选将、机缘、死亡与换将协作。
var _controller: MatchController

## 测试前下一局模式；结束时恢复，避免污染其他模式的菜单或开局测试。
var _original_match_mode: String = GameSettings.MATCH_MODE_IDENTITY

## 测试前手气卡次数；设为0可让本测试直接进入开局机缘，不额外等待确认流程。
var _original_mulligan_limit: int = 0

## 测试前自选AI武将开关；过关斩将固定随机敌将，结束后必须恢复用户设置。
var _original_customize_ai_characters_enabled: bool = false

## 测试前自选武将与座次开关；过关斩将不使用该流程，结束后必须恢复用户设置。
## 过关斩将复用该持久化开关时只开放全部武将，不开放座次与身份，专项测试会显式开启验证降级语义。
var _original_custom_character_assignment_enabled: bool = false

## 测试前过关斩将随机选将牌数；结束时恢复，避免本专项覆盖用户保存的1至20张配置。
var _original_conquest_character_candidate_count: int = GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT

## 测试前过关斩将换将卡数量；结束时恢复，避免本专项覆盖用户保存的独立离散档位配置。
var _original_conquest_character_replacement_count: int = GameSettings.DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT

## 测试前过关斩将难度；专项默认使用难度五保持原流程，并在纯服务断言中独立覆盖五档奖励。
var _original_conquest_difficulty: int = GameSettings.DEFAULT_CONQUEST_DIFFICULTY


## 延迟执行以等待自动加载数据库完成卡牌、武将与技能索引。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次运行规则层与完整对局层断言；任意失败均恢复全局设置并以非零状态退出。
func _run() -> void:
	_original_match_mode = str(GameSettings.next_match_mode)
	_original_mulligan_limit = GameSettings.mulligan_limit
	_original_customize_ai_characters_enabled = GameSettings.customize_ai_characters_enabled
	_original_custom_character_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_original_conquest_character_candidate_count = GameSettings.conquest_character_candidate_count
	_original_conquest_character_replacement_count = GameSettings.conquest_character_replacement_count
	_original_conquest_difficulty = GameSettings.conquest_difficulty
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_CONQUEST)
	GameSettings.set_mulligan_limit(0)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(true)
	GameSettings.set_conquest_character_candidate_count(GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT)
	GameSettings.set_conquest_character_replacement_count(3)
	GameSettings.set_conquest_difficulty(GameSettings.DEFAULT_CONQUEST_DIFFICULTY)
	if not _test_mode_rules_and_equipment_subtypes():
		_restore_settings()
		return
	if not _test_level_bonus_service():
		_restore_settings()
		return
	if not _test_player_difficulty_service():
		_restore_settings()
		return
	if not await _test_full_match_replacement_flow():
		_restore_settings()
		return
	_restore_settings()
	print("CONQUEST_MODE_PASS rules+levels+difficulties+initial_opportunity+zaixian_kill_tail+replacement+skills+equipment+turn_handoff+revival+death")
	get_tree().quit(0)


## 验证模式固定两名规则角色、红方先手、设置人数归一化与五类装备子类别槽位映射。
func _test_mode_rules_and_equipment_subtypes() -> bool:
	# 规则服务；独立于对局状态验证过关斩将的稳定模式契约。
	var rules: IdentityRules = IdentityRules.new()
	# 五种装备子类别的期望槽位；对子类别新增时必须同步更新该完整映射。
	var expected_slots: Dictionary = {
		EquipmentSubtype.WEAPON: "weapon",
		EquipmentSubtype.ARMOR: "armor",
		EquipmentSubtype.OFFENSIVE_MOUNT: "offensive_mount",
		EquipmentSubtype.DEFENSIVE_MOUNT: "defensive_mount",
		EquipmentSubtype.TREASURE: "treasure",
	}
	if rules.normalize_mode(IdentityRules.MODE_CONQUEST) != IdentityRules.MODE_CONQUEST or not rules.supports_player_count(IdentityRules.MODE_CONQUEST, 2) or rules.supports_player_count(IdentityRules.MODE_CONQUEST, 3) or rules.get_distribution(2, IdentityRules.MODE_CONQUEST) != ["red", "blue"] or not rules.starts_from_first_seat(IdentityRules.MODE_CONQUEST):
		return _fail("mode_rules")
	# 过关斩将人数设置表示“玩家数”：下限2（离线沿用历史值2）、上限4（局域网2至4名玩家）；超界输入向两端收敛。
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_CONQUEST, 9) != GameSettings.MAX_CONQUEST_LAN_PLAYER_COUNT or GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_CONQUEST, 1) != GameSettings.MIN_CONQUEST_LAN_PLAYER_COUNT or GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_CONQUEST) != 2:
		return _fail("mode_settings")
	# 普通模式原候选数量；过关斩将设置改变时必须保持不变，证明两个持久化槽彼此独立。
	var standard_candidate_count: int = GameSettings.character_candidate_count
	GameSettings.set_conquest_character_candidate_count(99)
	if GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT != 12 or GameSettings.conquest_character_candidate_count != 20 or GameSettings.get_character_candidate_count_for_mode(GameSettings.MATCH_MODE_CONQUEST) != 20 or GameSettings.character_candidate_count != standard_candidate_count:
		return _fail("conquest_candidate_count_max")
	GameSettings.set_conquest_character_candidate_count(-1)
	if GameSettings.conquest_character_candidate_count != 1 or GameSettings.get_character_candidate_count_for_mode(GameSettings.MATCH_MODE_CONQUEST) != 1:
		return _fail("conquest_candidate_count_min")
	GameSettings.set_conquest_character_candidate_count(GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT)
	# 普通模式原换将卡数量；过关斩将设置改变时必须保持不变，证明两个持久化槽彼此独立。
	var standard_replacement_count: int = GameSettings.character_replacement_count
	GameSettings.set_conquest_character_replacement_count(20)
	if GameSettings.conquest_character_replacement_count != 20 or GameSettings.get_character_replacement_count_for_mode(GameSettings.MATCH_MODE_CONQUEST) != 20 or GameSettings.character_replacement_count != standard_replacement_count:
		return _fail("conquest_replacement_count_max")
	GameSettings.set_conquest_character_replacement_count(99)
	if GameSettings.conquest_character_replacement_count != GameSettings.DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT or GameSettings.get_character_replacement_count_for_mode(GameSettings.MATCH_MODE_CONQUEST) != GameSettings.DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT:
		return _fail("conquest_replacement_count_invalid")
	GameSettings.set_conquest_character_replacement_count(3)
	if EquipmentSubtype.ALL.size() != expected_slots.size() or EquipmentSubtype.get_slot("unknown") != "":
		return _fail("equipment_subtype_count")
	for subtype: String in EquipmentSubtype.ALL:
		if not EquipmentSubtype.is_valid(subtype) or EquipmentSubtype.get_slot(subtype) != str(expected_slots.get(subtype, "")):
			return _fail("equipment_subtype_%s" % subtype)
	# 纯选将服务；隔离验证过关斩将开放所有武将但不进入座次身份自选，不让任意武将技能影响后续死亡专项。
	var selection_service: CharacterSelectionService = CharacterSelectionService.new()
	# 固定阵营测试角色；过关斩将始终保持一号位红方、二号位蓝方。
	var selection_players: Array[PlayerState] = [PlayerState.new(0, "玩家"), PlayerState.new(1, "敌方AI")]
	selection_players[0].identity = "red"
	selection_players[1].identity = "blue"
	# 全部武将稳定ID；使用1张随机候选保证能找到随机列表之外的全量候选。
	var selection_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		# 当前数据库武将ID；复制为强类型字符串供选将服务使用。
		var selection_character_id: String = str(character_id_variant)
		selection_character_ids.append(selection_character_id)
	# 独立随机源；只服务纯选将断言，不改变正式对局固定种子的随机序列。
	var selection_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	selection_rng.seed = 20260722
	if not selection_service.begin(selection_players, selection_character_ids, 1, selection_rng, false, 0, [], IdentityRules.MODE_CONQUEST, true).is_empty():
		return _fail("conquest_all_character_begin")
	# 本地纯武将快照；过关斩将开局只能由一号位玩家选将，敌方候选必须在玩家确认后才随机生成。
	var selection_snapshot: Dictionary = selection_service.to_dict(0)
	# 随机候选外的武将ID；用于证明服务实际接受全量列表，而不是只改变菜单文案。
	var outside_candidate_character_id: String = ""
	for character_id_variant: Variant in selection_snapshot.get("all_character_ids", []) as Array:
		# 当前全量候选ID；只取不在本次1张随机候选中的第一项。
		var all_character_id: String = str(character_id_variant)
		if not selection_service.get_candidates(0).has(all_character_id):
			outside_candidate_character_id = all_character_id
			break
	if selection_service.get_candidates(1).size() != 0 or selection_service.can_player_select(1) or selection_service.get_pending_player_ids() != [0] or not bool(selection_snapshot.get("allow_all_characters", false)) or bool(selection_snapshot.get("allow_custom_assignment", true)) or not (selection_snapshot.get("seat_options", []) as Array).is_empty() or not (selection_snapshot.get("identity_options", []) as Array).is_empty() or selection_character_ids.is_empty() or selection_service.select_character(1, selection_character_ids[0]).is_empty() or outside_candidate_character_id.is_empty() or not selection_service.select_character(0, outside_candidate_character_id).is_empty():
		return _fail("conquest_all_character_permissions")
	# 玩家确认后敌方才取得随机候选与选将权限；候选必须排除玩家已经确认的武将。
	var enemy_candidates: Array[String] = selection_service.get_candidates(1)
	if enemy_candidates.is_empty() or enemy_candidates.has(outside_candidate_character_id) or not selection_service.can_player_select(1) or selection_service.get_pending_player_ids() != [1]:
		return _fail("conquest_enemy_selection_after_player")
	return true


## 验证第1至15关固定累计数值、第5/10/15关不重复技能及第16关后的每关递增规则。
func _test_level_bonus_service() -> bool:
	# 纯规则状态；服务只读取该状态中的关卡快照，不依赖控制器或界面节点。
	var state: GameState = GameState.new()
	# 随机源；固定种子令技能候选可复现，测试只断言非重复和数量。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# 规则服务；本测试直接切换层数验证各项累计查询的边界。
	var service: ConquestModeService = ConquestModeService.new()
	# 敌方状态；任取一名已登记武将，用于过滤原生技能后的随机技能抽取。
	var enemy: PlayerState = PlayerState.new(1, "敌方AI")
	# 可用武将稳定ID；数据库在项目启动后至少应提供一名用于本模式。
	var character_ids: Array = GameDatabase.characters.keys()
	if character_ids.is_empty():
		return _fail("missing_characters")
	enemy.character_id = str(character_ids[0])
	# 规则状态角色数组；显式使用强类型数组，避免普通Array在写入GameState时丢失元素类型。
	var players: Array[PlayerState] = [PlayerState.new(0, "玩家"), enemy]
	state.players = players
	rng.seed = 20260722
	service.configure(state, rng, 0, 1)
	if service.get_level() != 1 or not service.get_enemy_opportunity_ids().is_empty() or service.get_max_hp_bonus() != 0 or service.get_draw_phase_bonus() != 0 or service.get_initial_hand_bonus() != 0 or service.get_hand_limit_bonus() != 0 or service.get_slash_limit_bonus() != 0 or service.get_damage_bonus() != 0:
		return _fail("level_one_bonus")
	state.conquest_state["level"] = 4
	# 第2、3、4关固定机缘；直接跳关时服务也必须补齐每一层记录，保证回放恢复不会缺失历史。
	var level_four_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_four_opportunities != ["gray_initial_hand_one", "blue_hand_limit_two", "orange_draw_phase_one"] or service.get_max_hp_bonus() != 0 or service.get_draw_phase_bonus() != 1 or service.get_hand_limit_bonus() != 2 or service.get_initial_hand_bonus() != 1:
		return _fail("level_four_opportunities=%s" % level_four_opportunities)
	state.conquest_state["level"] = 5
	# 第5关本次新抽取的技能机缘；历史保存完整机缘ID，且实际效果必须是获得技能。
	var level_five_skill_opportunities: Array[String] = service.ensure_skill_opportunity_rewards(enemy)
	if level_five_skill_opportunities.size() != 1 or str(OpportunityCatalog.get_card(level_five_skill_opportunities[0]).get("effect", "")) != "grant_skill" or service.get_enemy_skill_ids().size() != 1:
		return _fail("level_five_skill_opportunity")
	state.conquest_state["level"] = 8
	# 第6、7、8关继续追加体力上限、【杀】次数和摸牌阶段机缘。
	var level_eight_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_eight_opportunities != ["blue_max_hp_one", "green_slash_play_limit_one", "orange_draw_phase_one"] or service.get_max_hp_bonus() != 1 or service.get_draw_phase_bonus() != 2 or service.get_initial_hand_bonus() != 1 or service.get_slash_limit_bonus() != 1:
		return _fail("level_eight_opportunities=%s" % level_eight_opportunities)
	state.conquest_state["level"] = 9
	var level_nine_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_nine_opportunities != ["gray_initial_hand_four"] or service.get_initial_hand_bonus() != 5:
		return _fail("level_nine_opportunities=%s" % level_nine_opportunities)
	state.conquest_state["level"] = 10
	# 第10关技能机缘必须与第5关不重复；比较稳定技能ID而非随机机缘品质。
	var level_ten_skill_opportunities: Array[String] = service.ensure_skill_opportunity_rewards(enemy)
	if level_ten_skill_opportunities.size() != 1 or service.get_enemy_skill_ids().size() != 2 or service.get_enemy_skill_ids()[0] == service.get_enemy_skill_ids()[1]:
		return _fail("level_ten_skill_opportunity")
	state.conquest_state["level"] = 13
	var level_thirteen_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_thirteen_opportunities != ["purple_max_hp_two", "blue_draw_phase_one", "orange_damage_one"] or service.get_max_hp_bonus() != 3 or service.get_draw_phase_bonus() != 3 or service.get_damage_bonus() != 1:
		return _fail("level_thirteen_opportunities=%s" % level_thirteen_opportunities)
	state.conquest_state["level"] = 14
	var level_fourteen_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_fourteen_opportunities != ["gray_equip_distinct_four"] or not service.should_equip_distinct_subtypes():
		return _fail("level_fourteen_opportunities=%s" % level_fourteen_opportunities)
	state.conquest_state["level"] = 15
	# 第15关技能机缘补足第三项；所有技能卡都应同时保留在敌方机缘历史中。
	var level_fifteen_skill_opportunities: Array[String] = service.ensure_skill_opportunity_rewards(enemy)
	if level_fifteen_skill_opportunities.size() != 1 or service.get_enemy_skill_ids().size() != 3:
		return _fail("level_fifteen_skill_opportunity")
	state.conquest_state["level"] = 16
	var level_sixteen_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_sixteen_opportunities != ["gray_initial_hand_one", "blue_max_hp_one", "orange_draw_phase_one"] or service.get_max_hp_bonus() != 4 or service.get_draw_phase_bonus() != 4 or service.get_initial_hand_bonus() != 6:
		return _fail("level_sixteen_opportunities=%s" % level_sixteen_opportunities)
	state.conquest_state["level"] = 19
	var level_nineteen_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_nineteen_opportunities.size() != 9 or service.get_max_hp_bonus() != 7 or service.get_draw_phase_bonus() != 7 or service.get_initial_hand_bonus() != 9:
		return _fail("level_nineteen_opportunities=%s" % level_nineteen_opportunities)
	return true


## 验证难度一至五只通过机缘目录授予精确开局增益，并由服务权威记录和消耗复活次数。
func _test_player_difficulty_service() -> bool:
	# 各难度期望机缘ID；顺序与玩家右键详情中的实际授予顺序保持一致。
	var expected_opportunity_ids_by_difficulty: Dictionary = {
		1:["purple_max_hp_two", "orange_draw_phase_one", "gray_initial_hand_two", "green_slash_play_limit_one", "gray_revive_one"],
		2:["blue_max_hp_one", "orange_draw_phase_one", "gray_initial_hand_two", "green_slash_play_limit_one"],
		3:["blue_max_hp_one", "gray_initial_hand_two", "green_slash_play_limit_one"],
		4:["gray_initial_hand_one", "green_slash_play_limit_one"],
		5:[],
	}
	for difficulty: int in range(GameSettings.MIN_CONQUEST_DIFFICULTY, GameSettings.MAX_CONQUEST_DIFFICULTY + 1):
		# 当前难度独立状态；每档重新构建玩家，避免上一个难度的机缘历史污染结果。
		var difficulty_state: GameState = GameState.new()
		# 当前难度两名固定角色；玩家ID为0、敌方ID为1，与正式模式一致。
		var difficulty_players: Array[PlayerState] = [PlayerState.new(0, "玩家"), PlayerState.new(1, "敌方AI")]
		difficulty_state.players = difficulty_players
		# 当前难度服务；随机源不参与固定开局机缘，但仍按正式接口提供。
		var difficulty_service: ConquestModeService = ConquestModeService.new()
		# 当前难度随机源；固定种子保证未来扩展仍可复现。
		var difficulty_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		difficulty_rng.seed = 20260723 + difficulty
		difficulty_service.configure(difficulty_state, difficulty_rng, 0, 1, difficulty)
		# 当前难度期望机缘；强类型副本用于同时校验服务快照与玩家通用机缘历史。
		var expected_opportunity_ids: Array[String] = []
		for opportunity_id_variant: Variant in expected_opportunity_ids_by_difficulty.get(difficulty, []) as Array:
			expected_opportunity_ids.append(str(opportunity_id_variant))
		if difficulty_service.get_difficulty() != difficulty or difficulty_service.get_player_starting_opportunity_ids() != expected_opportunity_ids or difficulty_players[0].acquired_opportunity_ids != expected_opportunity_ids:
			return _fail("difficulty_%d_opportunities=%s/%s" % [difficulty, difficulty_service.get_player_starting_opportunity_ids(), difficulty_players[0].acquired_opportunity_ids])
		# 只有难度一拥有一次复活；消耗后必须归零且不可重复消耗。
		var expected_revive_count: int = 1 if difficulty == 1 else 0
		if difficulty_service.get_player_revives_remaining() != expected_revive_count or difficulty_service.can_revive_player(1):
			return _fail("difficulty_%d_revives=%d" % [difficulty, difficulty_service.get_player_revives_remaining()])
		if difficulty == 1 and (not difficulty_service.consume_player_revive(0) or difficulty_service.get_player_revives_remaining() != 0 or difficulty_service.consume_player_revive(0)):
			return _fail("difficulty_one_consume_revive")
	return true


## 使用真实开局、单人机缘与死亡换将流程验证玩家固定先手、关卡推进、装备入场与敌方回合中断。
func _test_full_match_replacement_flow() -> bool:
	_create_controller()
	if not _controller.start_match(2, 20260722, IdentityRules.MODE_CONQUEST):
		return _fail("start_match")
	if int(_controller.state.match_options.get("character_replacement_count", -1)) != 3 or int(_controller.state.match_options.get("conquest_difficulty", -1)) != GameSettings.DEFAULT_CONQUEST_DIFFICULTY or bool(_controller.state.match_options.get("custom_character_assignment_enabled", true)) or not bool(_controller.state.match_options.get("all_character_selection_enabled", false)):
		return _fail("conquest_replacement_count_locked")
	# 本地玩家候选；过关斩将固定一号位为真人，二号位AI会由控制器自动确认。
	var player_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	# 本地选将快照；开启设置后必须提供全武将入口，但不得提供任何座次或身份编辑数据。
	var player_selection_snapshot: Dictionary = _controller.character_selection.to_dict(0)
	if player_candidates.size() != GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT or not bool(player_selection_snapshot.get("allow_all_characters", false)) or bool(player_selection_snapshot.get("allow_custom_assignment", true)) or not (player_selection_snapshot.get("seat_options", []) as Array).is_empty() or not (player_selection_snapshot.get("identity_options", []) as Array).is_empty():
		return _fail("conquest_character_selection_permissions")
	# 玩家最终选择的武将；全武将入口固定使用不会在清空测试手牌时创建强制选择的丹恒，避免候选池新增武将后污染死亡时序专项断言。
	var selected_player_character_id: String = "dan_heng" if not GameDatabase.get_character("dan_heng").is_empty() else (player_candidates[0] if not player_candidates.is_empty() else "")
	if selected_player_character_id.is_empty() or not _controller.select_character(0, selected_player_character_id):
		return _fail("player_character_selection")
	for _frame_index: int in range(12):
		if str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	# 玩家状态；红方一号位必须是唯一真人并在首个机缘选择前保持第1关。
	var player: PlayerState = _controller.state.get_player(0)
	# 敌方状态；蓝方二号位由AI控制并在后续死亡时无限换将。
	var enemy: PlayerState = _controller.state.get_player(1)
	if player == null or enemy == null or player.character_id != selected_player_character_id or player.identity != "red" or enemy.identity != "blue" or _controller.local_human_player_id != 0 or not _controller.is_opportunity_enabled_for_current_match() or _controller.conquest_mode.get_level() != 1 or str(_controller.state.opportunity_state.get("stage", "")) != "choosing":
		return _fail("initial_state")
	if not await _choose_safe_opportunity(0):
		return _fail("initial_opportunity")
	if _controller.state.current_player_id != player.player_id:
		return _fail("player_first_turn")
	# 玩家当前武将的固有技能ID；本专项只验证模式死亡边界，先卸载固有技能，避免其额外询问抢占下方固定【杀】流程。
	var native_player_skill_ids: Array = GameDatabase.get_character(player.character_id).get("skills", []) as Array
	_controller._replace_native_character_skills(player, native_player_skill_ids, [])
	# 摄伏技能实例；优先复用随机武将自带实例，缺失时以局内获得技能安装，覆盖击杀后来源时机创建嵌套选择的卡死路径。
	var player_sefu: SkillDefinition = _controller.get_skill_instance(player.player_id, "shefu")
	if player_sefu == null and not _controller.grant_acquired_skill(player.player_id, "shefu", 0, 0, "conquest_test"):
		return _fail("conquest_sefu_install")
	player_sefu = _controller.get_skill_instance(player.player_id, "shefu")
	if player_sefu == null:
		return _fail("conquest_sefu_missing")
	# 再现技能实例；真实【杀】击杀后必须在换将边界前收到shaAfter，发放摸1张与1个额外出牌阶段。
	var player_zaixian: SkillDefinition = _controller.get_skill_instance(player.player_id, "zaixian")
	if player_zaixian == null and not _controller.grant_acquired_skill(player.player_id, "zaixian", 0, 0, "conquest_test"):
		return _fail("conquest_zaixian_install")
	player_zaixian = _controller.get_skill_instance(player.player_id, "zaixian")
	if player_zaixian == null:
		return _fail("conquest_zaixian_missing")
	# 敌方永屹技能；优先复用随机武将自带实例，缺失时临时授予，用于覆盖死亡换将不得继承damageAfter的卡死路径。
	var enemy_yongyi: SkillDefinition = _controller.get_skill_instance(enemy.player_id, "yongyi")
	if enemy_yongyi == null and not _controller.grant_acquired_skill(enemy.player_id, "yongyi", 0, 0, "conquest_test"):
		return _fail("conquest_yongyi_install")
	enemy_yongyi = _controller.get_skill_instance(enemy.player_id, "yongyi")
	if enemy_yongyi == null:
		return _fail("conquest_yongyi_missing")
	# 双方初始手牌；清空所有可能的【桃】或【酒】，使本次真实致死伤害稳定走到死亡与来源尾部。
	while not player.hand.is_empty():
		_controller._move_to_discard(player.hand.pop_back())
	while not enemy.hand.is_empty():
		_controller._move_to_discard(enemy.hand.pop_back())
	# 回合开始类技能（例如【铁壁】）会创建可取消的费用目标询问并把阶段写成 "choice"；
	# 固定种子选将会随武将池变化而换人，因此必须先结算这些技能选择，才能关闭旧请求并重建权威候选。
	if not _settle_pending_skill_choices():
		return _fail("opening_skill_choice_settle")
	# 取消开局技能选择会放行被其中断的流程（例如回合开始的摸牌阶段），因此必须再清空一次手牌，
	# 保证后续断言只统计本测试自己加入的实体牌；这些附带摸牌会随固定种子选将结果变化。
	while not player.hand.is_empty():
		_controller._move_to_discard(player.hand.pop_back())
	# 初始回合可能已经建立空的chooseToUse；先关闭旧请求，加入测试实体后再建立包含它们的权威候选。
	_controller._cancel_active_play_choice("conquest_test_setup")
	# 本次真实击杀使用的【杀】；从普通手牌进入processing并走完整指定目标、响应、伤害与生命周期尾部。
	# 固定使用红色【杀】：敌方武将随固定种子变化，若其持有【铁壁】授予的【琥珀】，黑色【杀】会被直接拒绝；
	# 本测试验证的是完整击杀链路而不是防具免疫，因此采用不会被【琥珀】拦截的红色【杀】。
	var killing_slash: CardInstance = CardInstance.new("sha", "heart", 7)
	killing_slash.zone = "hand"
	killing_slash.owner_id = player.player_id
	player.hand.append(killing_slash)
	# 再现固定弃置费用；成功支付1张后玩家在伤害结算前应回到0张手牌。
	var zaixian_cost_card: CardInstance = CardInstance.new("wuxie", "spade", 12)
	zaixian_cost_card.zone = "hand"
	zaixian_cost_card.owner_id = player.player_id
	player.hand.append(zaixian_cost_card)
	_controller._begin_play_choice(player.player_id)
	# 首次击败前敌方武将；换将后必须改为另一稳定ID（武将库充足时不允许重复）。
	var defeated_character_id: String = enemy.character_id
	# 首次击败前敌方武将代次；重新入场必须严格递增，旧伤害尾部继续保存该值。
	var defeated_character_generation: int = enemy.character_generation
	# 敌方手牌；使用已知非响应牌验证死亡时“区域内所有牌”会清空并进入弃牌堆，同时保证本次【杀】稳定命中。
	var extra_enemy_card: CardInstance = CardInstance.new("wuzhong", "heart", 8)
	extra_enemy_card.zone = "hand"
	extra_enemy_card.owner_id = enemy.player_id
	enemy.hand.append(extra_enemy_card)
	# 敌方剩余体力；真实【杀】会先询问再现费用与【闪】，随后进入濒死、死亡、摄伏和换将边界。
	enemy.hp = 1
	enemy.shield = 0
	# 标准用牌动作；先消费当前chooseToUse，再由正式CardUseEvent推进完整结算，避免测试绕过常驻出牌请求。
	var killing_slash_action: PlayerAction = PlayerAction.new("use_card", player.player_id, killing_slash.uid, [enemy.player_id])
	if not _controller.submit_action(killing_slash_action):
		# 待处理选择上下文；固定种子选将会随武将池变化而换人，开局技能子选择会令阶段停留在 "choice"。
		var blocked_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
		# 本局实际登场武将；失败时列出便于定位差异来源。
		var blocked_lineup: Array[String] = []
		for blocked_player: PlayerState in _controller.state.players:
			blocked_lineup.append("%d=%s" % [blocked_player.player_id, blocked_player.character_id])
		return _fail("conquest_slash_submit phase=%s play_choice=%s error=%s pending=%s chooser=%d lineup=%s" % [_controller.state.current_phase, _controller._has_active_play_choice(), _controller._last_action_rejection_message, str(blocked_context.get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1)), str(blocked_lineup)])
	# 再现费用请求；确认弃置恰好1张牌后才开始跟踪本次【杀】伤害。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "zaixian_discard" or not _submit_card_uid_choice(player.player_id, [zaixian_cost_card.uid], true):
		return _fail("conquest_zaixian_cost pending=%s" % _controller._pending_card_choice)
	# 敌方武将随固定种子与武将池变化，部分武将会在他人使用【杀】时插入可取消的确认请求：
	# 例如持有【军势】的布洛妮娅会在本次结算中先询问是否令使用者摸牌，抢在【闪】响应之前。
	# 因此不能假设下一个请求就是【闪】响应；先逐个取消非目标类别的请求，直到出现目标请求或请求表清空。
	for _pre_response_attempt: int in range(8):
		# 当前请求类别；已为目标类别或已无请求时立即停止取消。
		var pre_response_kind: String = str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))
		if pre_response_kind == "slash_response" or _controller._pending_card_choice.is_empty():
			break
		# 待取消请求的稳定编号与回答者；取消动作必须绑定创建时的取值，否则会被权威入口拒绝。
		var pre_response_request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
		var pre_response_chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
		# 标准选择动作；取消时不携带任何牌或目标。
		var pre_response_cancel: PlayerAction = PlayerAction.new("choose_cards", pre_response_chooser_id)
		pre_response_cancel.payload = {"request_id":pre_response_request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
		if not _controller.submit_action(pre_response_cancel):
			break
	# 猎杀目标的【闪】响应；敌方没有【闪】，仍按标准隐私询问明确放弃后再造成伤害。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "slash_response" or not _submit_choice(enemy.player_id, [], false):
		return _fail("conquest_slash_response")
	# 濒死救援请求；双方没有可救援牌仍须按标准顺序主动放弃，死亡后才会派发摄伏监听的来源尾部。
	for _dying_choice_index: int in range(4):
		var current_choice_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
		if str(current_choice_context.get("kind", "")) != "dying_response":
			break
		# 当前救援者稳定ID；以权威请求为准，避免依赖固定座次顺序。
		var dying_chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
		if not _submit_choice(dying_chooser_id, [], false):
			return false
	# 摄伏选择必须在换将等待开始前完成；此时既没有暂停也没有换将计时，防止旧尾部被新武将继承。
	if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "sefu_gain_target" or _controller._conquest_replacement_transition_active or (_controller.game_flow_pacer != null and _controller.game_flow_pacer.has_pending(MatchController.CONQUEST_REPLACEMENT_OPPORTUNITY_TASK_KEY)):
		return _fail("replacement_sefu_damage_source")
	if not _submit_target_choice(player.player_id, player.player_id):
		return false
	# 目标生命周期尾部；摄伏获得1张牌后，【杀】的shaAfter还必须让再现再摸1张并登记1个额外出牌阶段，然后才能进入换将等待。
	if player.hand.size() != 2 or int(_controller._extra_play_phase_counts.get(player.player_id, 0)) != 1:
		# 当前手牌定义ID；用于区分【再现】摸牌、【摄伏】获得与武将固有技能的额外来源。
		var tail_hand_ids: Array[String] = []
		for tail_card: CardInstance in player.hand:
			tail_hand_ids.append(tail_card.definition_id)
		# 本局实际登场武将；固定种子选将会随武将池变化而换人。
		var tail_lineup: Array[String] = []
		for tail_player: PlayerState in _controller.state.players:
			tail_lineup.append("%d=%s" % [tail_player.player_id, tail_player.character_id])
		return _fail("replacement_zaixian_tail hand=%d extra=%s cards=%s lineup=%s" % [player.hand.size(), _controller._extra_play_phase_counts, str(tail_hand_ids), str(tail_lineup)])
	# 换将等待只阻止旧规则继续，不暂停场景树；弃置区域的飞牌动画必须能在此期间持续播放。
	if _controller.is_gameplay_paused() or not _controller._conquest_replacement_transition_active or _controller._conquest_replacement_settlement_pause_token < 0 or _controller.game_flow_pacer == null or not _controller.game_flow_pacer.has_pending(MatchController.CONQUEST_REPLACEMENT_OPPORTUNITY_TASK_KEY) or not _controller.event_scheduler.pause_registry.has_active() or not _controller.state.opportunity_state.is_empty():
		return _fail("replacement_opportunity_preview")
	if not await _wait_for_conquest_replacement_opportunity():
		return _fail("replacement_opportunity_delay")
	if _controller.conquest_mode.get_level() != 2 or not enemy.alive or enemy.character_id.is_empty() or enemy.character_id == defeated_character_id or enemy.character_generation != defeated_character_generation + 1 or enemy.hand.size() < ConquestModeService.REPLACEMENT_DRAW_COUNT + 1 or enemy.max_hp != int(GameDatabase.get_character(enemy.character_id).get("max_hp", 4)) or enemy.mode_hand_limit_bonus != 0 or enemy.acquired_opportunity_ids != ["gray_initial_hand_one"] or str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or _controller.state.opportunity_state.get("participant_ids", []) != [player.player_id]:
		return _fail("first_replacement")
	if _controller.state.discard_pile.find(extra_enemy_card) < 0:
		return _fail("replacement_discards_all_regions")
	if not await _choose_gain_opportunity_from_enemy(player.player_id, enemy.player_id):
		return false
	if _controller.state.current_player_id != player.player_id or _controller._conquest_replacement_settlement_pause_token >= 0:
		return _fail("player_turn_continues")
	# 当前玩家出牌选择会占用统一请求槽；本断言先关闭它，再人工派发旧代次damageAfter验证新武将永屹不会继承旧伤害。
	_controller._cancel_active_play_choice("conquest_generation_test")
	enemy_yongyi = _controller.get_skill_instance(enemy.player_id, "yongyi")
	if enemy_yongyi == null and not _controller.grant_acquired_skill(enemy.player_id, "yongyi", 0, 0, "conquest_test"):
		return _fail("replacement_yongyi_reinstall")
	_controller._emit_rule_timing("damageAfter", enemy.player_id, player.player_id, enemy.player_id, {"amount":1, "hp_lost":1, "card_id":"sha", "source_character_generation":player.character_generation, "target_character_generation":defeated_character_generation})
	if _controller.has_pending_card_choice():
		return _fail("replacement_inherited_damage_after=%s" % [_controller._pending_card_choice])
	# 关卡14灰色装备机缘；手动提升测试关卡后先记录对应机缘，再使用真实牌堆/弃牌堆入场装备入口。
	_controller.state.conquest_state["level"] = 14
	var level_fourteen_opportunities: Array[String] = _controller.conquest_mode.award_fixed_opportunities_through_current_level()
	# 记录入口现按“每名敌人都会获得”写入全体敌方历史；单人局只有唯一敌人，行为与旧接口一致。
	_controller._record_conquest_enemy_opportunities(level_fourteen_opportunities)
	_controller._equip_conquest_enemy_from_piles(enemy.player_id)
	# 敌方已占用装备槽列表；四张装备必须落入四个不同的稳定子类别槽。
	var equipped_slots: Array = enemy.equipment.keys()
	if equipped_slots.size() != ConquestModeService.LEVEL_FOURTEEN_EQUIPMENT_SUBTYPE_COUNT:
		return _fail("level_fourteen_equipment_count=%d" % equipped_slots.size())
	for slot_variant: Variant in equipped_slots:
		# 当前装备槽稳定值；应与实体牌的装备子类别映射完全一致。
		var slot: String = str(slot_variant)
		# 当前槽位实体牌；由过关斩将入场逻辑从公共牌堆移动而来。
		var equipment_card: CardInstance = enemy.equipment.get(slot) as CardInstance
		# 当前装备静态定义；只读取其子类别并验证槽位映射。
		var equipment_definition: Dictionary = GameDatabase.get_card(equipment_card.definition_id) if equipment_card != null else {}
		if equipment_card == null or not EquipmentSubtype.is_valid(str(equipment_definition.get("subtype", ""))) or EquipmentSubtype.get_slot(str(equipment_definition.get("subtype", ""))) != slot:
			return _fail("level_fourteen_equipment_slot=%s" % slot)
	# 第5/10/15关技能机缘；控制器安装入口必须保留同一局的三项非重复技能机缘与运行时技能。
	_controller.state.conquest_state["level"] = 5
	_controller._restore_conquest_enemy_skills(enemy)
	_controller.state.conquest_state["level"] = 10
	_controller._restore_conquest_enemy_skills(enemy)
	_controller.state.conquest_state["level"] = 15
	_controller._restore_conquest_enemy_skills(enemy)
	if _controller.conquest_mode.get_enemy_skill_ids().size() != 3 or enemy.acquired_skills.size() < 3:
		return _fail("controller_skill_rewards")
	# 敌方回合内被击败；机缘完成后必须直接结束敌方回合并把行动权交回玩家。
	_controller.state.current_player_id = enemy.player_id
	_controller.state.current_phase = "play"
	enemy.hp = 0
	_controller._resolve_death(enemy.player_id, player.player_id)
	if not await _wait_for_conquest_replacement_opportunity():
		return _fail("enemy_turn_replacement_opportunity_delay")
	if str(_controller.state.opportunity_state.get("stage", "")) != "choosing":
		return _fail("enemy_turn_replacement_opportunity")
	# 新敌人恢复的关卡技能；换将时必须先恢复存活状态再重新安装，否则获得技能入口会拒绝死亡角色。
	for rewarded_skill_id: String in _controller.conquest_mode.get_enemy_skill_ids():
		if _controller.get_skill_instance(enemy.player_id, rewarded_skill_id) == null:
			return _fail("enemy_turn_replacement_skill_missing=%s" % rewarded_skill_id)
	if not await _choose_safe_opportunity(player.player_id):
		return _fail("enemy_turn_replacement_choice")
	# 新敌人可能持有会在回合内立即创建选择的技能（例如爻光的【凶星】是强制发动的欢愉技，演出时弹出目标窗口）；
	# 这些窗口没有取消入口，且本测试是手工推进死亡流程、AI 驱动未接管，因此必须先逐一结算，
	# 才能验证“行动权交回玩家”这条规则本身。换将结果会随武将库变化而换人，不能假设新敌人没有这类技能。
	if not _settle_pending_skill_choices():
		return _fail("enemy_turn_pending_choice_settle")
	if _controller.state.current_player_id != player.player_id:
		# 回合交接失败时的现场信息：当前行动者、阶段、待处理选择与双方武将。
		# 换将结果会随武将库变化而换人，列出武将便于快速定位差异来源。
		var handoff_lineup: Array[String] = []
		for handoff_player: PlayerState in _controller.state.players:
			handoff_lineup.append("%d=%s" % [handoff_player.player_id, handoff_player.character_id])
		return _fail("enemy_turn_handoff current=%d phase=%s pending=%s lineup=%s" % [_controller.state.current_player_id, str(_controller.state.current_phase), str(_controller._pending_card_choice.get("context", {})), str(handoff_lineup)])
	# 玩家死亡；本模式不允许玩家换将，必须立刻结束对局并由蓝方AI获胜。
	# 补充：本断言先人工授予一次复活，验证其拦截首次终局；次数耗尽后的第二次死亡仍执行上述终局规则。
	# 玩家复活机缘；正式难度五没有开局次数，本段显式追加同一灰色机缘并写入权威剩余次数以覆盖死亡拦截。
	player.acquired_opportunity_ids.append("gray_revive_one")
	_controller.state.conquest_state["player_revives_remaining"] = 1
	_controller.state.conquest_state["player_revives_used"] = 0
	# 多人字段与旧标量并存；服务优先读取按玩家ID的复数映射，因此测试覆盖复活次数时必须同步写入两种形式。
	_controller.state.conquest_state["player_revives_remaining_by_player"] = {"0":1}
	_controller.state.conquest_state["player_revives_used_by_player"] = {"0":0}
	# 复活前手牌；必须在复活时进入弃牌堆，随后新摸牌不能保留旧实体。
	var revival_discard_card: CardInstance = CardInstance.new("wuzhong", "diamond", 9)
	revival_discard_card.zone = "hand"
	revival_discard_card.owner_id = player.player_id
	player.hand.append(revival_discard_card)
	player.hp = 0
	_controller._resolve_death(player.player_id, enemy.player_id)
	if not player.alive or _controller.state.game_over or player.hp != player.max_hp or player.hand.size() != ConquestModeService.REVIVAL_DRAW_COUNT or _controller.state.discard_pile.find(revival_discard_card) < 0 or _controller.conquest_mode.get_player_revives_remaining() != 0:
		return _fail("player_revival alive=%s game_over=%s hp=%d/%d hand=%d revives=%d" % [player.alive, _controller.state.game_over, player.hp, player.max_hp, player.hand.size(), _controller.conquest_mode.get_player_revives_remaining()])
	# 复活次数耗尽后的再次死亡；此时不再拦截身份胜负结算，蓝方AI应正常获胜。
	player.hp = 0
	_controller._resolve_death(player.player_id, enemy.player_id)
	if player.alive or not _controller.state.game_over or _controller.state.winner != "blue_team":
		return _fail("player_death_game_over")
	return true


## 等待敌方新武将展示时间结束并进入单人机缘选择；测试根节点保持暂停可运行，避免依赖普通场景帧推进。
func _wait_for_conquest_replacement_opportunity() -> bool:
	# 展示等待上限；0.20秒覆盖正式0.05秒测试配置及无头计时器调度余量。
	await get_tree().create_timer(0.20, true).timeout
	return str(_controller.state.opportunity_state.get("stage", "")) == "choosing"


## 把当前单人机缘候选固定为无目标摸牌卡并提交；避免随机卡牌的额外目标选择遮蔽本模式流程断言。
func _choose_safe_opportunity(player_id: int) -> bool:
	if _controller == null or _controller.state == null or str(_controller.state.opportunity_state.get("stage", "")) != "choosing":
		return false
	# 安全候选一；玩家实际选择的摸两张牌机缘，无额外目标或确认请求。
	var draw_two: Dictionary = OpportunityCatalog.get_card("green_draw_two")
	# 安全候选二；保留三选一结构且不与第一项重复。
	var draw_three: Dictionary = OpportunityCatalog.get_card("blue_draw_three")
	# 安全候选三；保留三选一结构且不与前两项重复。
	var draw_five: Dictionary = OpportunityCatalog.get_card("purple_draw_five")
	if draw_two.is_empty() or draw_three.is_empty() or draw_five.is_empty():
		return false
	_controller.state.opportunity_state["options_by_player"] = {str(player_id):[draw_two, draw_three, draw_five]}
	# 玩家提交动作；生产路径仅携带稳定机缘ID，具体定义仍由权威目录重新获取。
	var action: PlayerAction = PlayerAction.new("choose_opportunity", player_id)
	action.payload = {"card_id":"green_draw_two"}
	if not _controller.submit_action(action):
		return false
	for _frame_index: int in range(24):
		if _controller.state.opportunity_state.is_empty():
			return true
		await get_tree().process_frame
	return false


## 在过关斩将换将过渡中完整执行绿色获得牌机缘；依次提交机缘、敌方目标和目标区域实体牌。
func _choose_gain_opportunity_from_enemy(player_id: int, enemy_player_id: int) -> bool:
	if _controller == null or _controller.state == null or str(_controller.state.opportunity_state.get("stage", "")) != "choosing":
		return _fail("gain_opportunity_not_choosing")
	# 绿色获得牌机缘；本回归固定把它放入当前玩家私有候选，避免依赖随机品质和抽牌顺序。
	var gain_one: Dictionary = OpportunityCatalog.get_card("green_gain_one")
	# 两张无目标候选；只用于保持正式三选一协议，不参与本次效果结算。
	var draw_three: Dictionary = OpportunityCatalog.get_card("blue_draw_three")
	# 第三张无目标候选；与前两张稳定ID不同，保持候选目录合法。
	var draw_five: Dictionary = OpportunityCatalog.get_card("purple_draw_five")
	if gain_one.is_empty() or draw_three.is_empty() or draw_five.is_empty():
		return _fail("gain_opportunity_catalog")
	_controller.state.opportunity_state["options_by_player"] = {str(player_id):[gain_one, draw_three, draw_five]}
	# 机缘提交动作；第一步仍使用choose_opportunity，成功后应同步建立目标选择请求。
	var opportunity_action: PlayerAction = PlayerAction.new("choose_opportunity", player_id)
	opportunity_action.payload = {"card_id":"green_gain_one"}
	if not _controller.submit_action(opportunity_action):
		return _fail("gain_opportunity_submit")
	# 机缘效果在下一帧推进；等待目标请求实际发布后再读取权威候选。
	for _frame_index: int in range(12):
		if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "opportunity_effect_target":
			break
		await get_tree().process_frame
	# 第一段目标上下文；必须允许选择重新入场后的敌方，且仍保持换将过渡屏障生效。
	var target_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if not _controller._conquest_replacement_transition_active or str(target_context.get("kind", "")) != "opportunity_effect_target" or not (_controller._pending_card_choice.get("target_ids", []) as Array).has(enemy_player_id):
		return _fail("gain_opportunity_enemy_target")
	# 过期请求动作；即使上下文属于机缘，错误请求ID也不能越过换将过渡边界。
	var stale_target_action: PlayerAction = PlayerAction.new("choose_cards", player_id)
	stale_target_action.payload = {"request_id":int(_controller._pending_card_choice.get("request_id", -1)) + 1, "selected_card_uids":[], "selected_target_ids":[enemy_player_id], "confirmed":true}
	if _controller.submit_action(stale_target_action):
		return _fail("gain_opportunity_stale_request_allowed")
	if not _submit_target_choice(player_id, enemy_player_id):
		return false
	# 目标响应恢复后通常同步创建区域请求；保留逐帧等待可覆盖后续解析器改为延迟推进的实现。
	for _frame_index: int in range(12):
		if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "opportunity_zone_cards":
			break
		await get_tree().process_frame
	# 第二段区域牌上下文；目标提交后必须继续生成敌方区域候选，不能被“正在重新入场”拦截。
	var zone_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	# 当前敌方区域候选；至少包含新武将入场时获得的基础手牌。
	var zone_candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if str(zone_context.get("kind", "")) != "opportunity_zone_cards" or str(zone_context.get("zone_operation", "")) != "gain_one" or int(zone_context.get("target_player_id", -1)) != enemy_player_id or zone_candidates.is_empty():
		return _fail("gain_opportunity_zone_choice")
	# 选中的敌方区域实体UID；结算后必须进入玩家普通手牌，不能只验证请求被接受。
	var selected_card_uid: int = int((zone_candidates[0] as Dictionary).get("uid", -1))
	if selected_card_uid < 0 or not _submit_card_uid_choice(player_id, [selected_card_uid], true):
		return false
	for _frame_index: int in range(24):
		if _controller.state.opportunity_state.is_empty():
			break
		await get_tree().process_frame
	# 玩家与所获实体；机缘结束同时证明换将屏障已按正常续接释放。
	var player: PlayerState = _controller.state.get_player(player_id)
	if not _controller.state.opportunity_state.is_empty() or player == null or player.find_hand_card(selected_card_uid) == null or _controller._conquest_replacement_transition_active:
		return _fail("gain_opportunity_resolution")
	return true


## 为当前强制目标选择提交一名角色；测试经统一PlayerAction入口验证嵌套选择会恢复到过关斩将换将续接。
func _submit_target_choice(actor_id: int, target_id: int) -> bool:
	return _submit_choice(actor_id, [target_id], true)


## 为当前选择请求提交实体牌UID；机缘区域选牌与普通目标选择使用同一PlayerAction协议但字段彼此独立。
func _submit_card_uid_choice(actor_id: int, selected_card_uids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_card_choice")
	# 当前区域选择请求编号；提交绑定该稳定ID，避免同步续接后误操作下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选牌动作；只携带实体UID，不伪造目标或机缘定义。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":[], "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("card_choice_rejected")
	return true


## 为当前选择请求提交目标或取消；濒死放弃和摄伏目标选择共用同一权威动作协议。
func _submit_choice(actor_id: int, target_ids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_choice")
	# 当前请求稳定编号；同步恢复可能立刻创建下一请求，提交必须绑定创建时的同一编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；摄伏只提交唯一目标，濒死放弃提交空目标与confirmed=false。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected")
	return true


## 创建与正式场景一致的最小控制器组件树；红方为本地玩家，蓝方由AI管理。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；死亡、装备与技能安装均通过正式时机接口派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；负责自动提交蓝方选将，玩家红方仍由测试手动确认。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 网络网关；离线默认状态满足过关斩将不支持局域网的规则限制。
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
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai_characters_enabled)
	GameSettings.set_custom_character_assignment_enabled(_original_custom_character_assignment_enabled)
	GameSettings.set_conquest_character_candidate_count(_original_conquest_character_candidate_count)
	GameSettings.set_conquest_character_replacement_count(_original_conquest_character_replacement_count)
	GameSettings.set_conquest_difficulty(_original_conquest_difficulty)


## 结算回合开始类技能创建的全部待处理选择；取消它们并把阶段恢复为出牌阶段。
## 部分武将（例如持有【铁壁】的星穹旅伴）会在每回合开始创建可取消的费用目标询问，把阶段写成 "choice"，
## 从而阻止常驻出牌询问建立。另有部分是**强制发动**的技能（例如爻光的【凶星】欢愉技目标窗口），
## 这类窗口没有取消入口，此时按请求自身下发的首个合法候选确认，否则清理会永远卡住。
## 固定种子选将会随武将池变化而换人，测试不能假设开局没有这类请求。
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
		# 不可取消的强制窗口（例如爻光的【凶星】是强制发动的欢愉技，演出时弹出目标窗口）：
		# 此时按请求自身下发的首个合法候选确认；候选只取自权威窗口，不额外探测任何隐藏信息。
		var forced_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		forced_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":_first_candidate_target_ids(), "selected_control_id":_first_candidate_control_id(), "confirmed":true}
		if not _controller.submit_action(forced_action):
			return false
	if not _controller._pending_card_choice.is_empty():
		return false
	# 非出牌类子选择会把阶段写成 "choice"；取消后显式恢复到出牌阶段，后续才能重建常驻询问。
	if _controller.state.current_phase == "choice":
		_controller.state.current_phase = "play"
	return true


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


## 失败出口；打印稳定标记并释放临时控制器后以非零状态结束测试。
func _fail(reason: String) -> bool:
	printerr("CONQUEST_MODE_FAIL %s" % reason)
	if _controller != null:
		_controller.queue_free()
	_restore_settings()
	get_tree().quit(1)
	return false
