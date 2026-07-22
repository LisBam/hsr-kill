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
var _original_custom_character_assignment_enabled: bool = false

## 测试前过关斩将随机选将牌数；结束时恢复，避免本专项覆盖用户保存的1至20张配置。
var _original_conquest_character_candidate_count: int = GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT

## 测试前过关斩将换将卡数量；结束时恢复，避免本专项覆盖用户保存的独立离散档位配置。
var _original_conquest_character_replacement_count: int = GameSettings.DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT


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
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_CONQUEST)
	GameSettings.set_mulligan_limit(0)
	GameSettings.set_customize_ai_characters_enabled(false)
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_conquest_character_candidate_count(GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT)
	GameSettings.set_conquest_character_replacement_count(3)
	if not _test_mode_rules_and_equipment_subtypes():
		_restore_settings()
		return
	if not _test_level_bonus_service():
		_restore_settings()
		return
	if not await _test_full_match_replacement_flow():
		_restore_settings()
		return
	_restore_settings()
	print("CONQUEST_MODE_PASS rules+levels+initial_opportunity+replacement+skills+equipment+turn_handoff+death")
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
	if GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_CONQUEST, 9) != 2 or GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_CONQUEST) != 2:
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
	if level_four_opportunities != ["blue_max_hp_one", "purple_draw_phase_one", "blue_hand_limit_two"] or service.get_max_hp_bonus() != 1 or service.get_draw_phase_bonus() != 1 or service.get_hand_limit_bonus() != 2 or service.get_initial_hand_bonus() != 0:
		return _fail("level_four_opportunities=%s" % level_four_opportunities)
	state.conquest_state["level"] = 5
	# 第5关本次新抽取的技能机缘；历史保存完整机缘ID，且实际效果必须是获得技能。
	var level_five_skill_opportunities: Array[String] = service.ensure_skill_opportunity_rewards(enemy)
	if level_five_skill_opportunities.size() != 1 or str(OpportunityCatalog.get_card(level_five_skill_opportunities[0]).get("effect", "")) != "grant_skill" or service.get_enemy_skill_ids().size() != 1:
		return _fail("level_five_skill_opportunity")
	state.conquest_state["level"] = 8
	# 第6、7、8关继续追加蓝、紫、灰机缘；灰色初始手牌机缘只由关卡授予。
	var level_eight_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_eight_opportunities != ["blue_max_hp_one", "purple_draw_phase_one", "gray_initial_hand_four"] or service.get_max_hp_bonus() != 2 or service.get_draw_phase_bonus() != 2 or service.get_initial_hand_bonus() != 4:
		return _fail("level_eight_opportunities=%s" % level_eight_opportunities)
	state.conquest_state["level"] = 9
	var level_nine_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_nine_opportunities != ["green_slash_play_limit_one"] or service.get_slash_limit_bonus() != 1:
		return _fail("level_nine_opportunities=%s" % level_nine_opportunities)
	state.conquest_state["level"] = 10
	# 第10关技能机缘必须与第5关不重复；比较稳定技能ID而非随机机缘品质。
	var level_ten_skill_opportunities: Array[String] = service.ensure_skill_opportunity_rewards(enemy)
	if level_ten_skill_opportunities.size() != 1 or service.get_enemy_skill_ids().size() != 2 or service.get_enemy_skill_ids()[0] == service.get_enemy_skill_ids()[1]:
		return _fail("level_ten_skill_opportunity")
	state.conquest_state["level"] = 13
	var level_thirteen_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_thirteen_opportunities != ["purple_max_hp_two", "purple_draw_phase_one", "orange_damage_one"] or service.get_max_hp_bonus() != 4 or service.get_draw_phase_bonus() != 3 or service.get_damage_bonus() != 1:
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
	if level_sixteen_opportunities != ["gray_initial_hand_one", "blue_max_hp_one", "purple_draw_phase_one"] or service.get_max_hp_bonus() != 5 or service.get_draw_phase_bonus() != 4 or service.get_initial_hand_bonus() != 5:
		return _fail("level_sixteen_opportunities=%s" % level_sixteen_opportunities)
	state.conquest_state["level"] = 19
	var level_nineteen_opportunities: Array[String] = service.award_fixed_opportunities_through_current_level()
	if level_nineteen_opportunities.size() != 9 or service.get_max_hp_bonus() != 8 or service.get_draw_phase_bonus() != 7 or service.get_initial_hand_bonus() != 8:
		return _fail("level_nineteen_opportunities=%s" % level_nineteen_opportunities)
	return true


## 使用真实开局、单人机缘与死亡换将流程验证玩家固定先手、关卡推进、装备入场与敌方回合中断。
func _test_full_match_replacement_flow() -> bool:
	_create_controller()
	if not _controller.start_match(2, 20260722, IdentityRules.MODE_CONQUEST):
		return _fail("start_match")
	if int(_controller.state.match_options.get("character_replacement_count", -1)) != 3:
		return _fail("conquest_replacement_count_locked")
	# 本地玩家候选；过关斩将固定一号位为真人，二号位AI会由控制器自动确认。
	var player_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	if player_candidates.size() != GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT or not _controller.select_character(0, player_candidates[0]):
		return _fail("player_character_selection")
	for _frame_index: int in range(12):
		if str(_controller.state.opportunity_state.get("stage", "")) == "choosing":
			break
		await get_tree().process_frame
	# 玩家状态；红方一号位必须是唯一真人并在首个机缘选择前保持第1关。
	var player: PlayerState = _controller.state.get_player(0)
	# 敌方状态；蓝方二号位由AI控制并在后续死亡时无限换将。
	var enemy: PlayerState = _controller.state.get_player(1)
	if player == null or enemy == null or player.identity != "red" or enemy.identity != "blue" or _controller.local_human_player_id != 0 or not _controller.is_opportunity_enabled_for_current_match() or _controller.conquest_mode.get_level() != 1 or str(_controller.state.opportunity_state.get("stage", "")) != "choosing":
		return _fail("initial_state")
	if not await _choose_safe_opportunity(0):
		return _fail("initial_opportunity")
	if _controller.state.current_player_id != player.player_id:
		return _fail("player_first_turn")
	# 摄伏技能实例；优先复用随机武将自带实例，缺失时以局内获得技能安装，覆盖击杀后来源时机创建嵌套选择的卡死路径。
	var player_sefu: SkillDefinition = _controller.get_skill_instance(player.player_id, "shefu")
	if player_sefu == null and not _controller.grant_acquired_skill(player.player_id, "shefu", 0, 0, "conquest_test"):
		return _fail("conquest_sefu_install")
	player_sefu = _controller.get_skill_instance(player.player_id, "shefu")
	if player_sefu == null:
		return _fail("conquest_sefu_missing")
	# 双方初始手牌；清空所有可能的【桃】或【酒】，使本次真实致死伤害稳定走到死亡与来源尾部。
	while not player.hand.is_empty():
		_controller._move_to_discard(player.hand.pop_back())
	while not enemy.hand.is_empty():
		_controller._move_to_discard(enemy.hand.pop_back())
	# 首次击败前敌方武将；换将后必须改为另一稳定ID（武将库充足时不允许重复）。
	var defeated_character_id: String = enemy.character_id
	# 敌方手牌；预置一张牌后用于验证死亡时“区域内所有牌”会清空并进入弃牌堆。
	var extra_enemy_card: CardInstance = _controller.state.draw_pile.back()
	_controller._move_card_with_timings(extra_enemy_card, "hand", enemy.player_id, "conquest_test_setup")
	# 敌方剩余体力；用真实伤害击杀以让摄伏在damageSource中产生嵌套目标选择。
	enemy.hp = 1
	enemy.shield = 0
	_controller.damage(player.player_id, enemy.player_id, 1, "normal", "sha")
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
	# 换将等待只阻止旧规则继续，不暂停场景树；弃置区域的飞牌动画必须能在此期间持续播放。
	if _controller.is_gameplay_paused() or not _controller._conquest_replacement_transition_active or _controller.game_flow_pacer == null or not _controller.game_flow_pacer.has_pending(MatchController.CONQUEST_REPLACEMENT_OPPORTUNITY_TASK_KEY) or not _controller.state.opportunity_state.is_empty():
		return _fail("replacement_opportunity_preview")
	if not await _wait_for_conquest_replacement_opportunity():
		return _fail("replacement_opportunity_delay")
	if _controller.conquest_mode.get_level() != 2 or not enemy.alive or enemy.character_id.is_empty() or enemy.character_id == defeated_character_id or enemy.hand.size() < ConquestModeService.REPLACEMENT_DRAW_COUNT or enemy.max_hp != int(GameDatabase.get_character(enemy.character_id).get("max_hp", 4)) + 1 or enemy.mode_hand_limit_bonus != 0 or enemy.acquired_opportunity_ids != ["blue_max_hp_one"] or str(_controller.state.opportunity_state.get("stage", "")) != "choosing" or _controller.state.opportunity_state.get("participant_ids", []) != [player.player_id]:
		return _fail("first_replacement")
	if _controller.state.discard_pile.find(extra_enemy_card) < 0:
		return _fail("replacement_discards_all_regions")
	if not await _choose_safe_opportunity(player.player_id):
		return _fail("replacement_opportunity")
	if _controller.state.current_player_id != player.player_id:
		return _fail("player_turn_continues")
	# 关卡14灰色装备机缘；手动提升测试关卡后先记录对应机缘，再使用真实牌堆/弃牌堆入场装备入口。
	_controller.state.conquest_state["level"] = 14
	var level_fourteen_opportunities: Array[String] = _controller.conquest_mode.award_fixed_opportunities_through_current_level()
	_controller._record_conquest_enemy_opportunities(enemy, level_fourteen_opportunities)
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
	if not await _choose_safe_opportunity(player.player_id):
		return _fail("enemy_turn_replacement_choice")
	if _controller.state.current_player_id != player.player_id:
		return _fail("enemy_turn_handoff")
	# 玩家死亡；本模式不允许玩家换将，必须立刻结束对局并由蓝方AI获胜。
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


## 为当前强制目标选择提交一名角色；测试经统一PlayerAction入口验证嵌套选择会恢复到过关斩将换将续接。
func _submit_target_choice(actor_id: int, target_id: int) -> bool:
	return _submit_choice(actor_id, [target_id], true)


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


## 失败出口；打印稳定标记并释放临时控制器后以非零状态结束测试。
func _fail(reason: String) -> bool:
	printerr("CONQUEST_MODE_FAIL %s" % reason)
	if _controller != null:
		_controller.queue_free()
	_restore_settings()
	get_tree().quit(1)
	return false
