extends "res://tests/card_single_sequence_test.gd"

## 刻律与阮梅的真实动作链回归；观察自然推进，不调用停滞修复或手动排空结算。

## 每个动作的自然恢复等待上限，单位毫秒；小于看门狗软修复时间，超时即保留现场报错。
const PROGRESS_TIMEOUT_MILLISECONDS: int = 1500

## 测试用非零阶段间隔，单位秒；覆盖真实异步转场，无需运行时修改，不改变正式对局配置。
const TEST_FLOW_INTERVAL_SECONDS: float = 0.025

## 测试AI响应等待，单位秒；实际下限仍由阶段间隔决定，无需运行时动态修改。
const TEST_AI_DELAY_SECONDS: float = 0.01

## 单次规则恢复的测试步数预算；2步迫使技能前置与费用跨帧，覆盖自然唤醒边界。
const TEST_SETTLEMENT_STEP_BUDGET: int = 2

## 压力对战的标准规则预算；与轻量异步专项分开，避免多局随机验证被刻意低预算拖慢。
const BATTLE_SETTLEMENT_STEP_BUDGET: int = 64

## 固定牌堆对战的目标回合数；达到25回合或自然终局即完成该局观察。
const BATTLE_TURN_LIMIT: int = 25


## 覆盖军功积累与重置、三节堪杀及阮梅的正式AI选择。
func _run() -> void:
	await _test_qixi_existing_ai_window()
	for merit_count: int in [2, 6]:
		for section_index: int in range(3):
			await _test_kansha_progress(merit_count, section_index)
	for merit_count: int in [0, 4, 6]:
		await _test_kelvdela_turn(merit_count)
	for timing_name: String in ["loseBefore", "discardAfter", "cardsDiscardedBatchAfter"]:
		await _test_kansha_progress(6, 0, timing_name)
	for timing_name: String in ["damageBefore", "damageAfter"]:
		await _test_kansha_progress(6, 2, timing_name)
	await _test_independent_play()
	# 默认三局用于快速回归；压力参数扩展到三十个固定随机种子。
	var battle_seeds: Array[int] = [19, 42, 91]
	if OS.get_cmdline_user_args().has("--soak"):
		battle_seeds.assign(range(1, 31))
	if OS.get_cmdline_user_args().has("--skip-battles"):
		battle_seeds.clear()
	for match_seed: int in battle_seeds:
		await _test_character_battle(match_seed)
		if _failed:
			break
	await _test_lingfu_choice()
	await _test_ruanxian_choice(false)
	await _test_ruanxian_choice(true)
	if _controller != null:
		_controller.free()
	if not _failed:
		print("CHARACTER_TURN_PROGRESS_PASS qixi_drive=1 kansha=11 kelvdela_turn=3 independent=1 battles=%d lingfu=1 ruanxian=2" % battle_seeds.size())
	get_tree().quit(1 if _failed else 0)


## 重建正式服务和可用出牌请求；关闭看门狗以暴露真实恢复缺失。
func _prepare_play(character_id: String) -> void:
	_reset_controller()
	_controller.stall_watchdog.set_process(false)
	_controller.game_flow_interval_seconds = TEST_FLOW_INTERVAL_SECONDS
	_controller.ai_action_delay_seconds = TEST_AI_DELAY_SECONDS
	_controller.max_settlement_steps_per_pass = TEST_SETTLEMENT_STEP_BUDGET
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.get_player(0).character_id = character_id
	for player: PlayerState in _controller.state.players:
		player.identity_revealed = true
	_controller._rebuild_match_rule_services_and_root_event()
	for card_index: int in range(12):
		# 重铸补摸实体；统一使用不可主动出的闪，隔离其他牌效。
		var card: CardInstance = CardInstance.new("shan", "heart", card_index % 13 + 1)
		card.zone = "draw_pile"
		_controller.state.draw_pile.append(card)


## 安装内容技能，保留与正式武将相同的组件和时机订阅。
func _install_content(skill_id: String, player_id: int = 0) -> SkillDefinition:
	# 本次独立技能组件；绑定后才订阅规则时机。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	skill.bind(_controller, player_id)
	# 持有者已安装技能表；追加不覆盖同一角色的其他组件。
	var skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = skills
	skill.install()
	return skill


## 堪杀的真实主动入口必须完整结束，并恢复下一次输入；军功重置不能留下父内容等待。
func _test_kansha_progress(merit_count: int, section_index: int, timing_name: String = "") -> void:
	_prepare_play("kelvdela")
	# 被测轮回技能；通过公开轮回端口构造各节，不改写运行时私有轮回状态。
	var skill: SkillDefinition = _install_content("kansha")
	_install_content("qixi")
	_controller.change_player_mark_count(0, "jungong", merit_count)
	for advance_index: int in range(section_index):
		_controller.enter_next_reincarnation_section(0, "kansha")
	# 当前颜色费用；第三节不会使用该牌。
	var card: CardInstance = _add_single_card()
	card.suit = "heart" if section_index == 0 else "spade"
	_controller._begin_play_choice(0)
	_controller.ai_coordinator.register_basic_ai(0)
	if not timing_name.is_empty():
		_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 正式技能动作；直接参数与AI枚举的协议相同。
	var action: PlayerAction = PlayerAction.new("use_skill", 0)
	action.payload = {"skill_id":"kansha", "card_uid":card.uid} if section_index < 2 else {"skill_id":"kansha", "target_ids":[1]}
	_check(_controller.submit_action(action), "kansha action rejected")
	# 单调时钟截止点；仅观察真实进程帧和已登记的恢复任务。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and (not _controller._rule_sequences.is_empty() or not _controller._deferred_skill_settlements.is_empty() or not _controller._has_active_play_choice()):
		await get_tree().process_frame
	_check(_controller._rule_sequences.is_empty() and _controller._deferred_skill_settlements.is_empty() and _controller._has_active_play_choice(), "kansha stalled merit=%d section=%d diagnostics=%s sequences=%s" % [merit_count, section_index, _controller.get_stall_diagnostics(), _controller._rule_sequences.keys()])
	_check(skill.get_reincarnation_section_index() == (section_index + (2 if merit_count == 6 else 1)) % 3, "kansha lost reincarnation advance")
	_check(_controller.get_settlement_fault_count() == 0, "kansha relied on settlement fault guard")
	# 出牌窗口存在还不足以证明AI会行动；必须已经有驱动，或下一动作已经被实际提交。
	_check(_controller._scheduled_ai_drive_token == _controller._ai_drive_token or _controller.state.action_sequence > 1, "kansha lost AI drive merit=%d section=%d diagnostics=%s" % [merit_count, section_index, _controller.get_stall_diagnostics()])


## 奇袭延后完成时出牌请求可能已经存在；恢复AI不能依赖“本次恰好新建请求”这一附带条件。
func _test_qixi_existing_ai_window() -> void:
	_prepare_play("kelvdela")
	_install_content("kansha")
	# 真实锁定技组件；只有达到阈值时才创建延后结算，故覆盖该临界值。
	var qixi: SkillDefinition = _install_content("qixi")
	_controller.change_player_mark_count(0, "jungong", 6)
	_controller._begin_play_choice(0)
	_controller.ai_coordinator.register_basic_ai(0)
	# 实际发动事实通过正式端口触发奇袭；输入窗口保持原身份，后续重置由现有管线自然消费。
	_controller.record_skill_activation(0, "kansha")
	_check(not _controller._deferred_skill_settlements.is_empty(), "qixi did not defer reset")
	_controller._ensure_ai_progress_after_resolution()
	_check(_controller._scheduled_ai_drive_token < 0, "AI crossed pending qixi reset")
	# 等待实际后续动作；不主动唤醒结算或调用任何自动修复端口。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and _controller.state.action_sequence == 0:
		await get_tree().process_frame
	_check(_controller.state.action_sequence > 0, "qixi reset completed but AI input has no drive: %s" % _controller.get_stall_diagnostics())
	_check(qixi != null and _controller._deferred_skill_settlements.is_empty(), "qixi reset not consumed")


## 完整回合从升变开始，必须在无看门狗与额外恢复调用的条件下进入下一角色回合。
func _test_kelvdela_turn(merit_count: int) -> void:
	_prepare_play("kelvdela")
	_install_content("shengbian")
	_install_content("kansha")
	_install_content("zhengfu")
	_controller.state.get_player(2).identity = "rebel"
	_controller.local_human_player_id = -1
	_controller.ai_coordinator.register_basic_ai(0)
	_controller.change_player_mark_count(0, "jungong", merit_count)
	# 黑色费用与摸牌堆红色费用同时存在，保证两个弃牌节均可发动。
	var card: CardInstance = _add_single_card()
	card.suit = "spade"
	_controller.state.current_phase = "test"
	_controller._start_turn(0)
	# 完整回合截止点；角色切换是比动作计数更强的自然推进证据。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and _controller.state.current_player_id == 0:
		await get_tree().process_frame
	_check(_controller.state.current_player_id != 0, "kelvdela turn stalled merit=%d diagnostics=%s deferred=%s continuations=%s" % [merit_count, _controller.get_stall_diagnostics(), _controller._deferred_skill_settlements, _controller._rule_continuations.to_array()])


## 外层内容等待独立出牌阶段时，刻律自己的技能后续与AI仍应自然推进并归还父内容。
func _test_independent_play() -> void:
	_prepare_play("kelvdela")
	_install_content("kansha")
	_install_content("qixi")
	_controller.change_player_mark_count(0, "jungong", 6)
	_controller.ai_coordinator.register_basic_ai(0)
	_controller.local_human_player_id = -1
	_add_single_card()
	_controller.state.current_phase = "test"
	_controller.state.current_player_id = 1
	# 父内容的完成观察；必须等刻律执行完整额外阶段之后才能写入。
	var completed: Array[bool] = [false]
	_controller.run_rule_sequence([
		func(_sequence: RuleStepSequence) -> void: _controller.request_extra_play_phase(0, 1, "test_extra_play", {}),
		func(_sequence: RuleStepSequence) -> void: completed[0] = true,
	])
	# 独立阶段截止点；仍然仅观察自然帧，不手动恢复管线。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and not completed[0]:
		await get_tree().process_frame
	_check(completed[0], "kelvdela independent play stalled diagnostics=%s deferred=%s continuations=%s" % [_controller.get_stall_diagnostics(), _controller._deferred_skill_settlements, _controller._rule_continuations.to_array()])


## 固定随机源的真实牌堆对战；覆盖两个武将与其他技能、牌效和响应在同一事件树内协作。
func _test_character_battle(match_seed: int) -> void:
	_prepare_play("kelvdela")
	for player_id: int in range(3, 8):
		# 额外座位；交错敌我身份，扩大军功迁移与跨角色技能协作覆盖。
		var player: PlayerState = PlayerState.new(player_id, "对战%d" % player_id)
		player.identity = "loyalist" if player_id % 2 == 0 else "rebel"
		player.identity_revealed = true
		_controller.state.players.append(player)
	_controller.max_settlement_steps_per_pass = BATTLE_SETTLEMENT_STEP_BUDGET
	_controller._rng.seed = match_seed
	# 可选压力模式使用随机其他武将，仍固定包含刻律与阮梅。
	var character_ids: Array[String] = GameDatabase.get_selectable_character_ids()
	_controller._shuffle_array(character_ids)
	_controller.state.draw_pile.clear()
	_controller._create_and_shuffle_deck()
	_controller.local_human_player_id = -1
	for player: PlayerState in _controller.state.players:
		player.character_id = ["kelvdela", "ruanmei", "himeko"][player.player_id % 3]
		if OS.get_cmdline_user_args().has("--random-roster"):
			player.character_id = ["kelvdela", "ruanmei"][player.player_id] if player.player_id < 2 else character_ids[player.player_id]
			player.identity_revealed = player.player_id == 0
		player.max_hp = int(GameDatabase.get_character(player.character_id).get("max_hp", 3))
		player.hp = player.max_hp
		_controller.ai_coordinator.register_basic_ai(player.player_id)
		for card_index: int in range(4):
			# 初始发牌只构造手牌，不额外触发摸牌技能。
			var card: CardInstance = _controller.state.draw_pile.pop_back()
			card.zone = "hand"
			card.owner_id = player.player_id
			player.hand.append(card)
	_controller._install_all_character_skills()
	_controller.state.current_phase = "test"
	_controller._start_turn(0)
	# 连续无进展的截止点；每次权威指纹变化即重新计时，正常真人等待在本纯AI场景不存在。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	# 最近进展指纹；包含规则内容、请求、AI驱动及阶段，保留完整现场供诊断。
	var fingerprint: String = ""
	while not _controller.state.game_over and _controller.state.turn_number < BATTLE_TURN_LIMIT and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		# 当前进展指纹；来自正式诊断端口，不修改任何队列或安排额外恢复。
		var next_fingerprint: String = str(_controller.get_stall_diagnostics().get("fingerprint", ""))
		if next_fingerprint != fingerprint:
			fingerprint = next_fingerprint
			deadline = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	_check(_controller.state.game_over or _controller.state.turn_number >= BATTLE_TURN_LIMIT, "character battle stalled seed=%d diagnostics=%s deferred=%s continuations=%s" % [match_seed, _controller.get_stall_diagnostics(), _controller._deferred_skill_settlements, _controller._rule_continuations.to_array()])
	print("CHARACTER_BATTLE_OBSERVED seed=%d turn=%d actions=%d" % [match_seed, _controller.state.turn_number, _controller.state.action_sequence])


## 同一权威请求经过完整策略评分后应确认，不能只验证技能局部评分而漏掉通用费用。
func _test_lingfu_choice() -> void:
	_prepare_play("ruanmei")
	_install_content("lingfu")
	_install_content("meizhan")
	_add_single_card()
	_controller._begin_play_choice(0)
	# 正式主动动作；随后使用真实请求和合法动作枚举调用基础策略。
	var action: PlayerAction = PlayerAction.new("use_skill", 0)
	action.payload = {"skill_id":"lingfu"}
	_check(_controller.submit_action(action), "lingfu action rejected")
	# 低预算会让前置通知跨帧，必须等待真实材料请求出现后再交给策略。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and not _controller.has_pending_card_choice():
		await get_tree().process_frame
	# 当前权威快照；补写已安装技能，和正式AI驱动读取口径一致。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	# 独立策略；避免测试直接调用技能钩子时遗漏通用评分。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	# 策略最终动作；必须完成真实费用选择，而不是在每次技能请求中取消。
	var choice: Dictionary = policy.choose_card_choice(snapshot, _controller._pending_card_choice, _controller.get_pending_choice_legal_actions())
	_check(bool((choice.get("payload", {}) as Dictionary).get("confirmed", false)), "lingfu AI cancels profitable action: %s" % choice)
	# 策略实际选中的目标；此处验证推进而不替代技能自身的目标估值。
	var selected_target_id: int = int(((choice.get("payload", {}) as Dictionary).get("selected_target_ids", [0]) as Array)[0])
	_check(_controller.submit_action(PlayerAction.from_dict(choice)), "lingfu AI choice rejected")
	deadline = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and not _controller._has_active_play_choice():
		await get_tree().process_frame
	_check(_controller.has_skill(selected_target_id, "meizhan") and _controller._has_active_play_choice() and _controller._rule_sequences.is_empty(), "lingfu did not resolve target and restore play")
	_check((_controller.state.get_player(0).character_form_state.get("lingfu_used_card_categories", []) as Array).has("basic"), "lingfu did not consume actual quota")


## 阮弦的真实费用请求仅由技能评分；收益不足时仍取消，不以强制确认掩盖估值问题。
func _test_ruanxian_choice(expensive_only: bool) -> void:
	_prepare_play("ruanmei")
	# 第二名受益队友；两张牌收益高于铁索的重铸机会成本，仍低于无中的机会成本。
	var teammate: PlayerState = PlayerState.new(3, "受益队友")
	teammate.identity = "loyalist"
	teammate.identity_revealed = true
	_controller.state.players.append(teammate)
	_install_content("ruanxian")
	_install_content("meizhan")
	# 公开获得记录使只读评分实例能识别队友的梅绽，和正式局内授予同源。
	_controller.grant_acquired_skill(2, "meizhan", 0, 0, "lingfu")
	_controller.grant_acquired_skill(3, "meizhan", 0, 0, "lingfu")
	# 真实锦囊材料；低价铁索值得重铸，高价无中不值得只换两名队友各摸一张。
	var card: CardInstance = _add_single_card()
	card.definition_id = "wuzhong" if expensive_only else "tiesuo"
	card.suit = "club"
	_controller.state.current_phase = "finish"
	_controller.emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	# 权威结束阶段快照；策略必须结合真实的材料上下文和其他受益者。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	# 独立策略避免沿用前一用例的身份推断缓存。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	# 实际确认或取消动作；取消的基准固定为零。
	var choice: Dictionary = policy.choose_card_choice(snapshot, _controller._pending_card_choice, _controller.get_pending_choice_legal_actions())
	_check(bool((choice.get("payload", {}) as Dictionary).get("confirmed", false)) != expensive_only, "ruanxian material decision mismatch: %s" % choice)
	_check(_controller.submit_action(PlayerAction.from_dict(choice)), "ruanxian AI choice rejected")
	# 结束阶段后续自然恢复上限；不以主动排空代替技能自身的唤醒。
	var deadline: int = Time.get_ticks_msec() + PROGRESS_TIMEOUT_MILLISECONDS
	while Time.get_ticks_msec() < deadline and not _controller._rule_sequences.is_empty():
		await get_tree().process_frame
	_check(_controller.state.get_player(2).hand.size() == (0 if expensive_only else 1), "ruanxian beneficiary draw mismatch")
	_check(_controller.state.get_player(3).hand.size() == (0 if expensive_only else 1), "ruanxian second beneficiary draw mismatch")
	_check(_controller._rule_sequences.is_empty() and _controller._deferred_skill_settlements.is_empty(), "ruanxian left pending content")
