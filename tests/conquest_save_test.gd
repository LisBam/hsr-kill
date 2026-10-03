extends Node

## 过关斩将存档功能回归测试。验证存档文件读写与版本校验；空闲出牌询问中的立即存档退出；
## 结算或询问进行中的延迟预约、取消与回合边界存档；损坏存档拒绝恢复；以及两类恢复
## （回到同一回合出牌阶段 / 从下一回合开始）后的关卡、角色、牌区、机缘历史与获得技能一致性。

## 测试专用存档路径；绝不读写正式存档文件，避免破坏本机玩家的真实进度。
const TEST_SAVE_PATH: String = "user://conquest_save_test.dat"

## 大于2^53的64位整数样例；验证 var_to_str 文本格式完整保留随机源状态精度。
const LARGE_RNG_STATE_SAMPLE: int = 6917529027641081855

## 等待存档信号或阶段推进的统一超时毫秒数；覆盖敌方完整AI回合与无头计时器调度余量。
const WAIT_TIMEOUT_MILLISECONDS: int = 20000

## 权威控制器；复用正式对局组件树验证临时退出、边界存档与恢复流程。
var _controller: MatchController

## 回合边界捕获的存档字典；由 conquest_exit_save_ready 信号写入，空字典表示尚未捕获。
var _captured_save: Dictionary = {}

## 测试前下一局模式；结束时恢复，避免污染其他模式的菜单或开局测试。
var _original_match_mode: String = GameSettings.MATCH_MODE_IDENTITY

## 测试前手气卡次数；设为0可让本测试直接进入开局机缘，不额外等待确认流程。
var _original_mulligan_limit: int = 0

## 测试前自选AI武将开关；过关斩将固定随机敌将，结束后必须恢复用户设置。
var _original_customize_ai_characters_enabled: bool = false

## 测试前自选武将与座次开关；本测试关闭该流程走纯随机候选，结束后恢复用户设置。
var _original_custom_character_assignment_enabled: bool = false

## 测试前过关斩将随机选将牌数；结束时恢复，避免覆盖用户保存的1至20张配置。
var _original_conquest_character_candidate_count: int = GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT

## 测试前过关斩将换将卡数量；结束时恢复，避免覆盖用户保存的独立离散档位配置。
var _original_conquest_character_replacement_count: int = GameSettings.DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT

## 测试前过关斩将难度；本测试使用难度一覆盖复活次数与摸牌机缘的存档恢复，结束后恢复。
var _original_conquest_difficulty: int = GameSettings.DEFAULT_CONQUEST_DIFFICULTY


## 延迟执行以等待自动加载数据库完成卡牌、武将与技能索引。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次运行存储层与完整对局层断言；任意失败均恢复全局设置并以非零状态退出。
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
	GameSettings.set_custom_character_assignment_enabled(false)
	GameSettings.set_conquest_character_candidate_count(GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT)
	GameSettings.set_conquest_character_replacement_count(0)
	GameSettings.set_conquest_difficulty(1)
	if not _test_store_roundtrip():
		_restore_settings()
		return
	if not await _test_exit_and_resume_flow():
		_restore_settings()
		return
	_restore_settings()
	print("CONQUEST_SAVE_PASS store_roundtrip+immediate_play_idle_capture+deferred_exit_toggle+boundary_capture+corrupt_reject+resume_play_phase+resume_turn_start+resume_skills+resume_zones")
	get_tree().quit(0)


## 验证存储组件的写入、读取、版本校验、64位整数精度与清除；全部使用测试专用路径。
func _test_store_roundtrip() -> bool:
	ConquestSaveStore.clear_save(TEST_SAVE_PATH)
	if ConquestSaveStore.has_save(TEST_SAVE_PATH):
		return _fail("store_initial_not_empty")
	# 合法样例存档；只包含结构校验所需的最小字段与一个高精度整数。
	var sample_save: Dictionary = {
		"save_version":ConquestSaveStore.SAVE_FORMAT_VERSION,
		"match_mode":IdentityRules.MODE_CONQUEST,
		"players":[{"player_id":0}],
		"rng_state":LARGE_RNG_STATE_SAMPLE,
	}
	if not ConquestSaveStore.write_save(sample_save, TEST_SAVE_PATH) or not ConquestSaveStore.has_save(TEST_SAVE_PATH):
		return _fail("store_write")
	# 读回结果；整数必须逐位一致，证明文本序列化没有经过浮点数转换。
	var loaded_sample: Dictionary = ConquestSaveStore.read_save(TEST_SAVE_PATH)
	if int(loaded_sample.get("rng_state", 0)) != LARGE_RNG_STATE_SAMPLE or str(loaded_sample.get("match_mode", "")) != IdentityRules.MODE_CONQUEST:
		return _fail("store_read=%s" % [loaded_sample])
	# 版本不符样例；读取端必须拒绝并返回空字典。
	var stale_version_save: Dictionary = sample_save.duplicate(true)
	stale_version_save["save_version"] = ConquestSaveStore.SAVE_FORMAT_VERSION + 999
	if not ConquestSaveStore.write_save(stale_version_save, TEST_SAVE_PATH) or not ConquestSaveStore.read_save(TEST_SAVE_PATH).is_empty():
		return _fail("store_version_reject")
	# 非过关斩将模式样例；同样必须被结构校验拒绝。
	var wrong_mode_save: Dictionary = sample_save.duplicate(true)
	wrong_mode_save["match_mode"] = "identity"
	if not ConquestSaveStore.write_save(wrong_mode_save, TEST_SAVE_PATH) or not ConquestSaveStore.read_save(TEST_SAVE_PATH).is_empty():
		return _fail("store_mode_reject")
	ConquestSaveStore.clear_save(TEST_SAVE_PATH)
	if ConquestSaveStore.has_save(TEST_SAVE_PATH):
		return _fail("store_clear")
	return true


## 使用真实对局验证两类临时退出捕获点与恢复一致性：
## 甲、空闲出牌询问中的立即存档与“回到同一回合出牌阶段”的恢复；
## 乙、结算或询问进行中的延迟预约、取消，以及回合边界存档与“从下一回合开始”的恢复。
func _test_exit_and_resume_flow() -> bool:
	_create_controller()
	if not _controller.start_match(2, 20260726, IdentityRules.MODE_CONQUEST):
		return _fail("start_match")
	# 本地玩家候选；过关斩将固定一号位为真人，二号位AI由控制器自动确认。
	var player_candidates: Array[String] = _controller.character_selection.get_candidates(0)
	if player_candidates.is_empty() or not _controller.select_character(0, player_candidates[0]):
		return _fail("player_character_selection")
	# 等待开局机缘三选一建立；难度一的开局机缘只写入历史，不产生额外选择。
	if not await _wait_until(func() -> bool:
		return str(_controller.state.opportunity_state.get("stage", "")) == "choosing"):
		return _fail("initial_opportunity_missing")
	if not await _choose_safe_opportunity(0):
		return _fail("initial_opportunity_choice")
	# 玩家状态；难度一必须带着1次复活与开局机缘进入第1关首回合。
	var player: PlayerState = _controller.state.get_player(0)
	if player == null or _controller.state.current_player_id != 0 or _controller.conquest_mode.get_level() != 1 or _controller.conquest_mode.get_player_revives_remaining() != 1:
		return _fail("initial_state revives=%d" % _controller.conquest_mode.get_player_revives_remaining())
	# 再现技能实例；优先复用随机武将自带实例，缺失时以限总5次的获得技能安装，覆盖获得技能的存档恢复。
	var granted_zaixian: bool = false
	if _controller.get_skill_instance(0, "zaixian") == null:
		if not _controller.grant_acquired_skill(0, "zaixian", 0, 5, "conquest_save_test"):
			return _fail("zaixian_grant")
		granted_zaixian = true
	# 高额护盾；后续敌方AI回合中的任何伤害都不能让玩家进入濒死，保证乙阶段边界存档必然到来。
	player.shield = 99
	_controller.conquest_exit_save_ready.connect(_on_conquest_save_ready)
	# 敌方在场防护；固定种子选将会随武将池变化而换人，若换到离场型武将（例如貊泽的【幽锋】每轮开始时离场），
	# 敌方回合会被整体跳过，本测试依赖的“敌方回合开始前边界存档”就永远不会到来。因此先把敌人拉回游戏。
	var initial_enemy: PlayerState = _controller.state.get_player(1)
	if initial_enemy != null and initial_enemy.out_of_game and not _controller.restore_player_to_game(initial_enemy.player_id, "conquest_save_test"):
		return _fail("enemy_out_of_game_restore")
	# 回合开始类技能（例如【铁壁】）会创建可取消的费用目标询问并把阶段写成 "choice"，从而阻止常驻出牌询问建立；
	# 固定种子选将会随武将池变化而换人，因此先结算这些技能选择，再等待出牌询问。
	if not _settle_pending_skill_choices():
		return _fail("opening_skill_choice_settle")
	# 等待常驻出牌询问建立；此时没有任何进行中的结算，属于可以立即存档的空闲询问时机。
	if not await _wait_until(func() -> bool:
		return _controller._has_active_play_choice()):
		return _fail("play_choice_missing")
	# 甲：空闲询问中的请求必须同步立即存档，不等待回合结束；预约标志同时被消费。
	if not _controller.request_conquest_temporary_exit():
		return _fail("immediate_exit_request")
	if _captured_save.is_empty() or _controller.is_conquest_temporary_exit_requested() or _controller.state.game_over:
		return _fail("immediate_capture_missing")
	if str(_captured_save.get("resume_kind", "")) != "play_phase" or int(_captured_save.get("next_turn_player_id", -1)) != 0 or (_captured_save.get("players", []) as Array).size() != 2:
		return _fail("immediate_capture_shape kind=%s next=%d" % [_captured_save.get("resume_kind", ""), int(_captured_save.get("next_turn_player_id", -1))])
	if int((_captured_save.get("conquest_state", {}) as Dictionary).get("level", -1)) != 1 or int((_captured_save.get("conquest_state", {}) as Dictionary).get("player_revives_remaining", -1)) != 1:
		return _fail("immediate_capture_conquest_state=%s" % [_captured_save.get("conquest_state", {})])
	if not (_captured_save.get("turn_flow", {}) as Dictionary).has("started_phase_lifecycles"):
		return _fail("immediate_capture_turn_flow=%s" % [_captured_save.get("turn_flow", {})])
	# 玩家存档条目；护盾与获得技能记录必须原样进入存档。
	var saved_player: Dictionary = (_captured_save.get("players", []) as Array)[0] as Dictionary
	if int(saved_player.get("shield", -1)) != 99:
		return _fail("immediate_capture_shield=%d" % int(saved_player.get("shield", -1)))
	if granted_zaixian and int(((saved_player.get("acquired_skills", {}) as Dictionary).get("zaixian", {}) as Dictionary).get("total_limit", -1)) != 5:
		return _fail("immediate_capture_acquired_skill=%s" % [saved_player.get("acquired_skills", {})])
	# 文件往返；恢复直接使用读回数据，覆盖文本序列化的完整保真链路。
	if not ConquestSaveStore.write_save(_captured_save, TEST_SAVE_PATH):
		return _fail("capture_write")
	var loaded_save: Dictionary = ConquestSaveStore.read_save(TEST_SAVE_PATH)
	if loaded_save.is_empty() or int(loaded_save.get("rng_state", -1)) != int(_captured_save.get("rng_state", -2)):
		return _fail("capture_reload")
	# 恢复期望值；全部取自读回的存档数据，不依赖仍然存活的旧对局对象。
	var expected_turn_number: int = int(loaded_save.get("turn_number", -1))
	var expected_round_number: int = int(loaded_save.get("round_number", -1))
	var saved_enemy: Dictionary = (loaded_save.get("players", []) as Array)[1] as Dictionary
	# 存档玩家手牌UID顺序；出牌阶段恢复不发生摸牌，恢复后手牌必须逐张逐序一致。
	var saved_hand_uids: Array[int] = []
	for card_data_variant: Variant in saved_player.get("hand", []) as Array:
		saved_hand_uids.append(int((card_data_variant as Dictionary).get("uid", -1)))
	# 存档摸牌堆UID顺序；出牌阶段恢复后的摸牌堆必须与该序列完全一致。
	var saved_draw_uids: Array[int] = []
	for card_data_variant: Variant in loaded_save.get("draw_pile", []) as Array:
		saved_draw_uids.append(int((card_data_variant as Dictionary).get("uid", -1)))
	# 存档实体总数；恢复后的全区域实体数必须完全一致，证明没有实体丢失或凭空产生。
	var saved_total_cards: int = _count_saved_cards(loaded_save)
	# 损坏存档拒绝；空字典、缺少角色与未知恢复类型都必须在破坏旧状态前被拒绝。
	if _controller.resume_conquest_match({}):
		return _fail("resume_accepts_empty")
	var corrupted_save: Dictionary = loaded_save.duplicate(true)
	corrupted_save["players"] = []
	if _controller.resume_conquest_match(corrupted_save):
		return _fail("resume_accepts_corrupted")
	var unknown_kind_save: Dictionary = loaded_save.duplicate(true)
	unknown_kind_save["resume_kind"] = "bogus_kind"
	if _controller.resume_conquest_match(unknown_kind_save):
		return _fail("resume_accepts_unknown_kind")
	# 甲恢复；必须回到同一回合的出牌阶段空闲询问，而不是开始新回合。
	if not _controller.resume_conquest_match(loaded_save):
		return _fail("resume_rejected")
	if str(_controller.state.match_mode) != IdentityRules.MODE_CONQUEST or _controller.conquest_mode.get_level() != 1 or _controller.conquest_mode.get_player_revives_remaining() != 1:
		return _fail("resume_conquest_state level=%d" % _controller.conquest_mode.get_level())
	if _controller.state.current_player_id != 0 or _controller.state.current_phase != "play" or _controller.state.turn_number != expected_turn_number or _controller.state.round_number != expected_round_number:
		return _fail("resume_play_phase turn=%d/%d phase=%s player=%d" % [_controller.state.turn_number, expected_turn_number, _controller.state.current_phase, _controller.state.current_player_id])
	if not _controller._has_active_play_choice():
		return _fail("resume_play_choice_missing")
	# 阿哈时刻组件：拆解旧对局运行时会调用它的 shutdown()（把 _enabled 置为 false 并解绑旧状态），
	# 恢复流程必须像请机会组件一样重新 configure 一次，否则本局剩余全程都不会触发阿哈时刻。
	if not _controller.ahha_moment_system._enabled or _controller.ahha_moment_system._state != _controller.state:
		return _fail("resume_ahha_moment enabled=%s" % str(_controller.ahha_moment_system._enabled))
	# 恢复后的双方角色；武将、体力、护盾与机缘历史必须与存档一致。
	var resumed_player: PlayerState = _controller.state.get_player(0)
	var resumed_enemy: PlayerState = _controller.state.get_player(1)
	if resumed_player == null or resumed_enemy == null:
		return _fail("resume_players_missing")
	if resumed_player.character_id != str(saved_player.get("character_id", "")) or resumed_player.shield != 99 or resumed_player.hp != int(saved_player.get("hp", -1)) or resumed_player.max_hp != int(saved_player.get("max_hp", -1)):
		return _fail("resume_player_stats hp=%d shield=%d" % [resumed_player.hp, resumed_player.shield])
	if resumed_enemy.character_id != str(saved_enemy.get("character_id", "")) or resumed_enemy.hp != int(saved_enemy.get("hp", -1)):
		return _fail("resume_enemy_stats")
	# 机缘历史一致性；难度一开局机缘与玩家三选一结果都必须原样恢复。
	var saved_opportunity_ids: Array = saved_player.get("acquired_opportunity_ids", []) as Array
	if resumed_player.acquired_opportunity_ids.size() != saved_opportunity_ids.size() or not resumed_player.acquired_opportunity_ids.has("green_draw_two"):
		return _fail("resume_opportunities=%s" % [resumed_player.acquired_opportunity_ids])
	# 技能恢复；固有技能与存档获得技能都必须重新安装，获得技能保留原有限总次数记录。
	if _controller.get_skill_instance(0, "zaixian") == null:
		return _fail("resume_zaixian_instance")
	if granted_zaixian and int((resumed_player.acquired_skills.get("zaixian", {}) as Dictionary).get("total_limit", -1)) != 5:
		return _fail("resume_zaixian_limit=%s" % [resumed_player.acquired_skills])
	# 手牌完整恢复；出牌阶段恢复没有任何摸牌或弃牌，张数与顺序都必须与存档完全一致。
	if resumed_player.hand.size() != saved_hand_uids.size():
		return _fail("resume_hand_size=%d/%d" % [resumed_player.hand.size(), saved_hand_uids.size()])
	for hand_index: int in range(saved_hand_uids.size()):
		if resumed_player.hand[hand_index].uid != saved_hand_uids[hand_index]:
			return _fail("resume_hand_order index=%d" % hand_index)
	# 摸牌堆完整恢复；出牌阶段恢复后的牌堆序列必须逐张一致。
	if _controller.state.draw_pile.size() != saved_draw_uids.size():
		return _fail("resume_draw_pile_size=%d/%d" % [_controller.state.draw_pile.size(), saved_draw_uids.size()])
	for pile_index: int in range(saved_draw_uids.size()):
		if _controller.state.draw_pile[pile_index].uid != saved_draw_uids[pile_index]:
			return _fail("resume_draw_pile_order index=%d" % pile_index)
	# 实体守恒；恢复后的全区域实体总数必须与存档完全一致。
	if _count_live_cards() != saved_total_cards:
		return _fail("resume_card_conservation live=%d saved=%d" % [_count_live_cards(), saved_total_cards])
	# 乙：弃牌询问进行中不属于空闲时机；预约保持挂起，取消与再预约都不得触发存档。
	_captured_save = {}
	# 本回合需要弃置的张数；难度一开局手牌远多于手牌上限，保证结束出牌后必然出现弃牌询问。
	var discard_needed: int = resumed_player.hand.size() - resumed_player.get_hand_limit()
	if discard_needed <= 0:
		return _fail("discard_setup hand=%d limit=%d" % [resumed_player.hand.size(), resumed_player.get_hand_limit()])
	var end_play_action: PlayerAction = PlayerAction.new("end_play", 0)
	if not _controller.submit_action(end_play_action):
		return _fail("end_play_submit")
	if not _controller.has_pending_card_choice() or int(_controller._pending_card_choice.get("chooser_id", -1)) != 0:
		return _fail("discard_prompt_missing phase=%s" % _controller.state.current_phase)
	if not _controller.request_conquest_temporary_exit() or not _controller.is_conquest_temporary_exit_requested() or not _captured_save.is_empty():
		return _fail("deferred_exit_request")
	# 预约取消与再预约；存档生效前玩家可以反悔，重复预约保持同一挂起状态。
	if not _controller.cancel_conquest_temporary_exit() or _controller.is_conquest_temporary_exit_requested():
		return _fail("deferred_exit_cancel")
	if not _controller.request_conquest_temporary_exit() or not _captured_save.is_empty():
		return _fail("deferred_exit_request_again")
	# 完成弃牌询问；本回合随后进入结束阶段，敌方回合开始前的边界触发存档。
	var discard_uids: Array[int] = []
	for hand_index: int in range(discard_needed):
		discard_uids.append(resumed_player.hand[hand_index].uid)
	if not _submit_card_uid_choice(0, discard_uids, true):
		return _fail("discard_submit")
	if not await _wait_until(func() -> bool:
		if _captured_save.is_empty():
			_answer_pending_player_choice()
		return not _captured_save.is_empty()):
		return _fail("deferred_capture_missing phase=%s player=%d pending_kind=%s chooser=%d candidates=%d controls=%d targets=%d lineup=%s" % [_controller.state.current_phase, _controller.state.current_player_id, str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")), int(_controller._pending_card_choice.get("chooser_id", -1)), (_controller._pending_card_choice.get("candidates", []) as Array).size(), (_controller._pending_card_choice.get("control_options", []) as Array).size(), (_controller._pending_card_choice.get("target_ids", []) as Array).size(), _describe_lineup()])
	# 乙边界断言；玩家回合完整结算后，下一回合正是尚未开始的敌方回合。
	if str(_captured_save.get("resume_kind", "")) != "turn_start" or int(_captured_save.get("next_turn_player_id", -1)) != 1:
		return _fail("deferred_capture_shape kind=%s next=%d" % [_captured_save.get("resume_kind", ""), int(_captured_save.get("next_turn_player_id", -1))])
	if int(_captured_save.get("turn_number", -1)) != expected_turn_number:
		return _fail("deferred_capture_turn=%d/%d" % [int(_captured_save.get("turn_number", -1)), expected_turn_number])
	# 乙恢复；敌方新回合立即开始，随后AI完整行动并把行动权交回玩家。
	if not _controller.resume_conquest_match(_captured_save.duplicate(true)):
		return _fail("deferred_resume_rejected")
	if _controller.state.current_player_id != 1 or _controller.state.turn_number != expected_turn_number + 1:
		return _fail("deferred_resume_turn=%d player=%d" % [_controller.state.turn_number, _controller.state.current_player_id])
	if not await _wait_until(func() -> bool:
		_answer_pending_player_choice()
		return _controller.state.current_player_id == 0 and _controller._has_active_play_choice()):
		return _fail("deferred_resume_handoff phase=%s player=%d" % [_controller.state.current_phase, _controller.state.current_player_id])
	ConquestSaveStore.clear_save(TEST_SAVE_PATH)
	# 结束恢复对局的全部运行时活动；进程退出前对局延时任务不再持有活动引用。
	_controller.abandon_match()
	return true


## 接收回合边界存档信号；深复制存档字典供后续断言与文件往返使用。
func _on_conquest_save_ready(save_data: Dictionary) -> void:
	_captured_save = save_data.duplicate(true)


## 统计存档中全部区域的实体牌总数；覆盖双方手牌、装备、判定区、“粮”与两个公共牌堆。
func _count_saved_cards(save_data: Dictionary) -> int:
	# 实体总数；玩家区域逐项累加后再叠加公共牌堆。
	var total: int = (save_data.get("draw_pile", []) as Array).size() + (save_data.get("discard_pile", []) as Array).size()
	for player_data_variant: Variant in save_data.get("players", []) as Array:
		var player_data: Dictionary = player_data_variant as Dictionary
		total += (player_data.get("hand", []) as Array).size()
		total += (player_data.get("judgment_area", []) as Array).size()
		total += (player_data.get("wooden_ox_storage", []) as Array).size()
		total += (player_data.get("equipment", {}) as Dictionary).size()
	return total


## 统计恢复后对局中全部区域的实体牌总数；口径与存档统计完全一致。
func _count_live_cards() -> int:
	# 实体总数；处理区在回合边界必然为空，但仍纳入统计保证口径完整。
	var total: int = _controller.state.draw_pile.size() + _controller.state.discard_pile.size() + _controller.state.processing_area.size()
	for player: PlayerState in _controller.state.players:
		total += player.hand.size()
		total += player.judgment_area.size()
		total += player.wooden_ox_storage.size()
		total += player.equipment.size()
	return total


## 为当前选择请求提交实体牌UID；弃牌询问与机缘区域选牌使用同一PlayerAction协议。
func _submit_card_uid_choice(actor_id: int, selected_card_uids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return false
	# 当前区域选择请求编号；提交绑定该稳定ID，避免同步续接后误操作下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选牌动作；只携带实体UID，不伪造目标或机缘定义。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":[], "confirmed":confirmed}
	return _controller.submit_action(action)


## 应答敌方回合中属于玩家的选择请求；优先明确放弃，强制请求回退为选择首个候选。
func _answer_pending_player_choice() -> void:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return
	if int(_controller._pending_card_choice.get("chooser_id", -1)) != 0:
		return
	# 当前请求稳定编号；提交必须绑定创建时的同一编号，避免误答后续请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 放弃动作；响应、无懈与濒死救援等可取消请求由此直接关闭。
	var decline_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	decline_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}
	if _controller.submit_action(decline_action):
		return
	# 强制窗口回退；五谷丰登的弃牌、貊泽【幽锋】的费用、海瑟音【泛音】的目标窗口以及弃牌阶段都不可取消，
	# 因此按权威窗口下发的首个合法候选做“牌 + 目标 + 文字选项”三者一并确认。
	# 同一请求可能是“选牌”“选目标”或“牌与目标组合”三种形态之一，空字段由权威入口自行忽略；
	# 需要恰好 N 张牌的请求必须一次提交足够张数，否则窗口会因数量不足而继续保留，等待流程将一直空转。
	var min_select: int = int(_controller._pending_card_choice.get("min_card_select", _controller._pending_card_choice.get("min_select", 0)))
	var forced_card_uids: Array[int] = []
	# 权威窗口下发的候选牌集合；手牌候选在暗置时仍带稳定uid，可直接用于强制提交。
	var candidate_cards: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if not candidate_cards.is_empty():
		for candidate_index: int in range(mini(maxi(min_select, 1), candidate_cards.size())):
			forced_card_uids.append(int((candidate_cards[candidate_index] as Dictionary).get("uid", -1)))
	var forced_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	forced_action.payload = {"request_id":request_id, "selected_card_uids":forced_card_uids, "selected_target_ids":_first_candidate_target_ids(), "selected_control_id":_first_candidate_control_id(), "confirmed":true}
	_controller.submit_action(forced_action)


## 把当前单人机缘候选固定为无目标摸牌卡并提交；避免随机卡牌的额外目标选择遮蔽存档流程断言。
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
	return await _wait_until(func() -> bool:
		return _controller.state.opportunity_state.is_empty())


## 逐帧等待谓词成立；返回是否在超时前满足条件。
func _wait_until(predicate: Callable, timeout_milliseconds: int = WAIT_TIMEOUT_MILLISECONDS) -> bool:
	# 本次等待截止时刻；使用单调毫秒时钟，不受系统时间调整影响。
	var deadline_msec: int = Time.get_ticks_msec() + timeout_milliseconds
	while Time.get_ticks_msec() < deadline_msec:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


## 创建与正式场景一致的最小控制器组件树；红方为本地玩家，蓝方由AI管理。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；死亡、装备与技能安装均通过正式时机接口派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；负责自动提交蓝方选将与敌方完整回合，玩家红方仍由测试手动操作。
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
	ConquestSaveStore.clear_save(TEST_SAVE_PATH)
	GameSettings.set_next_match_mode(_original_match_mode)
	GameSettings.set_mulligan_limit(_original_mulligan_limit)
	GameSettings.set_customize_ai_characters_enabled(_original_customize_ai_characters_enabled)
	GameSettings.set_custom_character_assignment_enabled(_original_custom_character_assignment_enabled)
	GameSettings.set_conquest_character_candidate_count(_original_conquest_character_candidate_count)
	GameSettings.set_conquest_character_replacement_count(_original_conquest_character_replacement_count)
	GameSettings.set_conquest_difficulty(_original_conquest_difficulty)


## 失败出口；打印稳定标记并释放临时控制器后以非零状态结束测试。
## 结算回合开始类技能创建的全部待处理选择；取消它们并把阶段恢复为出牌阶段。
## 部分武将（例如持有【铁壁】的星穹旅伴）会在每回合开始创建可取消的费用目标询问，把阶段写成 "choice"，
## 从而阻止常驻出牌询问建立。固定种子选将会随武将池变化而换人，测试不能假设开局没有这类请求。
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
		# 不可取消的强制窗口（例如貊泽【幽锋】每轮开始时必须弃置一名其他角色的一张牌）：
		# 按请求自身下发的首个合法候选确认；牌、目标与文字选项三者一并提交，
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
	printerr("CONQUEST_SAVE_FAIL %s" % reason)
	print("CONQUEST_SAVE_FAIL %s" % reason)
	if _controller != null:
		_controller.queue_free()
	_restore_settings()
	get_tree().quit(1)
	return false
