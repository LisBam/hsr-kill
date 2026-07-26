extends Node

## 过关斩将存档功能回归测试。验证存档文件读写与版本校验、临时退出预约与取消、
## 回合边界自动构建存档并发出信号、损坏存档拒绝恢复，以及从存档恢复后的关卡、
## 角色、牌区、机缘历史与获得技能一致性。

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
	print("CONQUEST_SAVE_PASS store_roundtrip+exit_request_toggle+boundary_capture+corrupt_reject+resume_state+resume_skills+resume_zones")
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


## 使用真实对局验证临时退出预约、回合边界存档、文件往返与恢复后的状态一致性。
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
	# 预约、取消与再次预约；权威开关必须与查询接口保持一致。
	if not _controller.request_conquest_temporary_exit() or not _controller.is_conquest_temporary_exit_requested():
		return _fail("exit_request")
	if not _controller.cancel_conquest_temporary_exit() or _controller.is_conquest_temporary_exit_requested():
		return _fail("exit_cancel")
	if not _controller.request_conquest_temporary_exit():
		return _fail("exit_request_again")
	_controller.conquest_exit_save_ready.connect(_on_conquest_save_ready)
	# 高额护盾；敌方完整AI回合中的任何伤害都不能让玩家进入濒死，保证边界存档必然到来。
	player.shield = 99
	# 清空玩家手牌；弃牌阶段与敌方回合的响应询问都会被显式放弃，避免测试依赖随机手牌内容。
	while not player.hand.is_empty():
		_controller._move_to_discard(player.hand.pop_back())
	if not await _wait_until(func() -> bool:
		return _controller._has_active_play_choice()):
		return _fail("play_choice_missing")
	# 结束出牌动作；随后进入弃牌与结束阶段，敌方AI回合结束后的回合边界触发存档。
	var end_play_action: PlayerAction = PlayerAction.new("end_play", 0)
	if not _controller.submit_action(end_play_action):
		return _fail("end_play_submit")
	if not await _wait_until(func() -> bool:
		if _captured_save.is_empty():
			_answer_pending_player_choice()
		return not _captured_save.is_empty()):
		return _fail("save_not_captured phase=%s player=%d" % [_controller.state.current_phase, _controller.state.current_player_id])
	# 边界断言；预约已消费、对局未终局。玩家回合完整结算后，下一回合正是尚未开始的敌方回合。
	if _controller.is_conquest_temporary_exit_requested() or _controller.state.game_over:
		return _fail("capture_side_effects")
	if int(_captured_save.get("next_turn_player_id", -1)) != 1 or (_captured_save.get("players", []) as Array).size() != 2:
		return _fail("capture_shape next=%d" % int(_captured_save.get("next_turn_player_id", -1)))
	if int((_captured_save.get("conquest_state", {}) as Dictionary).get("level", -1)) != 1 or int((_captured_save.get("conquest_state", {}) as Dictionary).get("player_revives_remaining", -1)) != 1:
		return _fail("capture_conquest_state=%s" % [_captured_save.get("conquest_state", {})])
	# 玩家存档条目；护盾与获得技能记录必须原样进入存档。
	var saved_player: Dictionary = (_captured_save.get("players", []) as Array)[0] as Dictionary
	if int(saved_player.get("shield", -1)) != 99:
		return _fail("capture_player_shield=%d" % int(saved_player.get("shield", -1)))
	if granted_zaixian and int(((saved_player.get("acquired_skills", {}) as Dictionary).get("zaixian", {}) as Dictionary).get("total_limit", -1)) != 5:
		return _fail("capture_acquired_skill=%s" % [saved_player.get("acquired_skills", {})])
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
	# 存档玩家手牌UID；恢复后必须全部回到玩家手中（新回合摸牌只会增加实体）。
	var saved_hand_uids: Array[int] = []
	for card_data_variant: Variant in saved_player.get("hand", []) as Array:
		saved_hand_uids.append(int((card_data_variant as Dictionary).get("uid", -1)))
	# 存档摸牌堆UID顺序；恢复后的摸牌堆必须是该序列去掉顶端已摸部分的前缀。
	var saved_draw_uids: Array[int] = []
	for card_data_variant: Variant in loaded_save.get("draw_pile", []) as Array:
		saved_draw_uids.append(int((card_data_variant as Dictionary).get("uid", -1)))
	# 存档实体总数；恢复后的全区域实体数必须完全一致，证明没有实体丢失或凭空产生。
	var saved_total_cards: int = _count_saved_cards(loaded_save)
	# 损坏存档拒绝；空字典与缺少角色的存档都必须在破坏旧状态前被拒绝。
	if _controller.resume_conquest_match({}):
		return _fail("resume_accepts_empty")
	var corrupted_save: Dictionary = loaded_save.duplicate(true)
	corrupted_save["players"] = []
	if _controller.resume_conquest_match(corrupted_save):
		return _fail("resume_accepts_corrupted")
	# 正式恢复；成功后立即从存档记录的下一回合角色开始行动。
	if not _controller.resume_conquest_match(loaded_save):
		return _fail("resume_rejected")
	if str(_controller.state.match_mode) != IdentityRules.MODE_CONQUEST or _controller.conquest_mode.get_level() != 1 or _controller.conquest_mode.get_player_revives_remaining() != 1:
		return _fail("resume_conquest_state level=%d" % _controller.conquest_mode.get_level())
	if _controller.state.current_player_id != 1 or _controller.state.turn_number != expected_turn_number + 1 or _controller.state.round_number < expected_round_number:
		return _fail("resume_turn state=%d/%d player=%d" % [_controller.state.turn_number, expected_turn_number, _controller.state.current_player_id])
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
	# 手牌恢复；存档手牌实体必须全部在场，新回合摸牌只能追加新实体。
	for saved_hand_uid: int in saved_hand_uids:
		if resumed_player.find_hand_card(saved_hand_uid) == null:
			return _fail("resume_hand_missing uid=%d" % saved_hand_uid)
	# 摸牌堆顺序恢复；当前牌堆必须是存档序列的前缀，顶端差额等于恢复后已摸走的张数。
	if _controller.state.draw_pile.size() > saved_draw_uids.size():
		return _fail("resume_draw_pile_grew")
	for pile_index: int in range(_controller.state.draw_pile.size()):
		if _controller.state.draw_pile[pile_index].uid != saved_draw_uids[pile_index]:
			return _fail("resume_draw_pile_order index=%d" % pile_index)
	# 实体守恒；恢复并开始新回合后的全区域实体总数必须与存档完全一致。
	if _count_live_cards() != saved_total_cards:
		return _fail("resume_card_conservation live=%d saved=%d" % [_count_live_cards(), saved_total_cards])
	ConquestSaveStore.clear_save(TEST_SAVE_PATH)
	# 结束恢复对局的全部运行时活动；进程退出前敌方AI回合的延时任务不再持有活动引用。
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
	# 强制请求回退；五谷丰登等必选请求提交首个候选实体。
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if candidates.is_empty():
		return
	var forced_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	forced_action.payload = {"request_id":request_id, "selected_card_uids":[int((candidates[0] as Dictionary).get("uid", -1))], "selected_target_ids":[], "confirmed":true}
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
func _fail(reason: String) -> bool:
	printerr("CONQUEST_SAVE_FAIL %s" % reason)
	print("CONQUEST_SAVE_FAIL %s" % reason)
	if _controller != null:
		_controller.queue_free()
	_restore_settings()
	get_tree().quit(1)
	return false
