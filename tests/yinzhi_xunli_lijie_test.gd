extends Node

## 【银枝】机制回归测试：巡礼（他人回合开始插入三段额外阶段 + 阶段内距离改写 + 永久背面锁定）与礼节（两段可选回赠）。
##
## 覆盖口径：
## 1. 武将元数据：银枝的显示名、势力、性别、体力上限、技能引用与技能正文；全局内容校验必须保持零错误。
## 2. 永久背面锁定：技能声明、安装后立即落实、翻至正面被拒绝、正面→背面不受影响、回合开始前的兜底纠正。
## 3. 巡礼：他人回合开始时的可选发动、三段额外阶段的实际执行、阶段内距离改写与结束后的还原、
##    每轮一次的额度，以及额外摸牌与礼节的联动。
## 4. 礼节：一次性获得至少两张牌后令其他角色摸牌、其他角色令持有者回复体力后令其回复1点体力。
## 5. AI：延时锦囊对银枝的收益为0，以及两段询问的评分方向（友方为正、敌方为负、取消为0）。

## 测试控制器；按正式组件结构装配，本地人类固定为0号位（银枝）。
var _controller: MatchController

## 最近一次属于0号位（银枝）的统一选择请求；用于模拟界面确认、取消或选目标。
var _local_choice_request: Dictionary = {}

## 捕获到的日志文本；用于断言锁定技纠正与技能发动留痕。
var _logs: Array[String] = []

## 状态安装序号；每次重建权威状态时生成不同 match_id，避免旧请求命中新场景。
var _state_sequence: int = 0

## 测试是否已经结束；失败与成功出口共用该标记，防止重复退出。
var _finished: bool = false


## 延迟运行回归，确保自动加载数据与控制器子节点均已完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次执行全部断言；任意失败立即以非0退出码结束无头测试。
func _run() -> void:
	_create_controller()
	if not _test_character_metadata():
		return
	if not await _test_face_down_lock():
		return
	if not await _test_xunli_chain():
		return
	if not await _test_lijie_recover():
		return
	if not _test_ai_rules():
		return
	# 失效 AI 任务令牌；让场景内已创建的短计时器自然结束后再释放控制器。
	_controller._ai_drive_token += 1
	await get_tree().create_timer(0.03).timeout
	remove_child(_controller)
	_controller.free()
	print("YINZHI_PASS meta=1 lock=1 flip=1 enforce=1 xunli=1 distance=1 quota=1 lijie_gain=1 lijie_recover=1 ai=1")
	_finished = true
	get_tree().quit(0)


## 创建正式依赖结构；非本地玩家由基础AI同步完成选择，避免测试等待不存在的客户端。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；名称与正式控制器的节点依赖保持一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；额外阶段与回合推进中的非本地角色使用基础策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；选择来源与正式单机对局保持一致。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = false
	# 相邻阶段与表现等待归零；断言边界只保留规则本身的同步推进。
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.01
	_controller.delayed_judgment_preview_seconds = 0.0
	_controller.delayed_judgment_result_pause_seconds = 0.0
	for player_id: int in range(1, 5):
		_controller.ai_coordinator.register_basic_ai(player_id)
	_controller.card_choice_requested.connect(_on_card_choice_requested)
	_controller.log_added.connect(_on_log_added)


## 安装一份指定人数的权威状态；0号位固定为银枝，其余角色使用通用武将占位。
func _install_state(player_count: int) -> GameState:
	_state_sequence += 1
	# 新权威状态；非空 match_id 令0号位的选择走真实提交路径。
	var game_state: GameState = GameState.new()
	game_state.match_id = "yinzhi-%d" % _state_sequence
	for player_id: int in range(player_count):
		# 当前测试玩家；0号位为被测武将银枝，其余角色使用已登记的通用武将。
		var player: PlayerState = PlayerState.new(player_id, "银枝测试玩家%d" % (player_id + 1))
		# 身份分配：一号位领袖、二号位反贼、其余忠臣；方向固定的敌我关系供AI评分断言使用。
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.character_id = "yinzhi" if player_id == 0 else "gepard"
		player.character_revealed = true
		player.max_hp = 4
		player.hp = 4
		game_state.players.append(player)
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.round_number = 1
	game_state.turn_number = 1
	_controller.state = game_state
	# 规则服务与根事件重建；同时清空上一场景遗留的技能订阅，避免跨场景触发。
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._reset_per_match_progress_state()
	_controller._ai_drive_token += 1
	_controller._active_extra_draw_phase.clear()
	_controller._active_extra_discard_phase.clear()
	_controller._active_independent_play_phase.clear()
	_local_choice_request.clear()
	_logs.clear()
	return game_state


## 验证银枝的静态内容：元数据、势力、体力上限、技能引用、技能正文与全局校验零错误。
func _test_character_metadata() -> bool:
	# 银枝元数据；数据库自动扫描 game_data/characters 后按稳定 ID 生成。
	var character: Dictionary = GameDatabase.get_character("yinzhi")
	if character.is_empty():
		return _fail("metadata_missing")
	if str(character.get("display_name", "")) != "银枝":
		return _fail("metadata_name=%s" % str(character.get("display_name", "")))
	if str(character.get("faction", "")) != "xingjianhuanyv":
		return _fail("metadata_faction=%s" % str(character.get("faction", "")))
	if str(character.get("gender", "")) != "male":
		return _fail("metadata_gender=%s" % str(character.get("gender", "")))
	if int(character.get("max_hp", 0)) != 4:
		return _fail("metadata_max_hp=%s" % str(character.get("max_hp", 0)))
	# 技能引用数组；顺序决定技能栏展示顺序，必须与武将文件内 preload 顺序一致。
	var skill_ids: Array = character.get("skills", []) as Array
	if skill_ids.size() != 2 or str(skill_ids[0]) != "xunli" or str(skill_ids[1]) != "lijie":
		return _fail("metadata_skills=%s" % str(skill_ids))
	# 势力展示元数据；星间寰宇必须已登记，否则选将过滤与界面都会缺失该势力。
	if GameDatabase.get_faction("xingjianhuanyv").is_empty():
		return _fail("metadata_faction_missing")
	# 全局内容校验；新增武将与技能不得引入任何校验错误。
	if not GameDatabase.validation_errors.is_empty():
		return _fail("validation=%s" % str(GameDatabase.validation_errors))
	# 技能正文；玩家可见文本必须与需求原文逐字一致（含半锁定技的类型段写法）。
	var xunli_metadata: Dictionary = GameDatabase.get_skill("xunli")
	var lijie_metadata: Dictionary = GameDatabase.get_skill("lijie")
	if str(xunli_metadata.get("description", "")) != "每轮限一次，一名角色的回合开始时，你可以依次执行额外的摸牌阶段、出牌阶段、弃牌阶段，这些阶段内，你计算与所有和当前回合角色距离为1的其他角色的距离1。锁定技，你的武将牌始终背面向上。":
		return _fail("xunli_text")
	if str(lijie_metadata.get("description", "")) != "当你一次性获得至少两张牌后，你可令一名其他角色摸一张牌。当其他角色令你回复体力后，你可令其回复1点体力。":
		return _fail("lijie_text")
	return true


## 验证「武将牌始终背面向上」：安装落实、翻面拒绝、反向翻面仍可用、回合开始前的兜底纠正。
func _test_face_down_lock() -> bool:
	# 本场景权威状态；三人局足以完成一次回合跳过。
	var game_state: GameState = _install_state(3)
	# 安装前先把武将牌置于正面；安装流程必须把它落实回背面。
	game_state.players[0].face_down = false
	_controller._reinstall_character_skills_for_player(game_state.players[0])
	# 巡礼实例；技能声明接口必须与锁定描述一致。
	var xunli: SkillDefinition = _controller.get_skill_instance(0, "xunli")
	if xunli == null or not xunli.locks_face_down():
		return _fail("locks_face_down_declaration")
	if not _controller.is_face_down_locked(0):
		return _fail("face_down_lock_query")
	if not bool(game_state.players[0].face_down):
		return _fail("install_enforce")
	# 背面→正面必须被拒绝，并且不产生翻面历史；这是「始终背面向上」的主路径。
	var log_count_before: int = _logs.size()
	if _controller.turn_over_player(0, 0, "yinzhi_face_down_test"):
		return _fail("flip_to_front_allowed")
	if not bool(game_state.players[0].face_down) or _logs.size() <= log_count_before:
		return _fail("flip_block_log=%s" % str(_logs))
	# 正面→背面不受锁定影响；锁定技角色仍可被正常翻到背面（也保证锁定方向本身可被复核）。
	game_state.players[0].face_down = false
	if not _controller.turn_over_player(0, 0, "yinzhi_face_down_test"):
		return _fail("flip_to_back_rejected")
	if not bool(game_state.players[0].face_down):
		return _fail("flip_back_state")
	# 回合开始前的兜底：再次人为把武将牌置于正面，回合开始流程必须纠正为背面并跳过本回合。
	game_state.players[0].face_down = false
	_controller._start_turn(0)
	# 银枝自己是当前回合角色，因此先出现巡礼的可选发动窗口；取消后进入背面跳过判定。
	if not await _await_local_choice("xunli_activate"):
		return false
	if not _submit_control(false, ""):
		return false
	if not bool(game_state.players[0].face_down):
		return _fail("turn_start_enforce")
	# 回合被整体跳过：当前阶段角色已移交给下一名角色，且银枝的判定区永远不会结算。
	await get_tree().process_frame
	if game_state.current_player_id == 0:
		return _fail("face_down_turn_not_skipped")
	return true


## 验证巡礼的阶段链、阶段内距离改写、礼节的顺手联动与每轮一次的额度。
func _test_xunli_chain() -> bool:
	# 五人局；环形座次下2号位与1、3号位距离为1，与0、4号位距离为2，可观测改写的差异。
	var game_state: GameState = _install_state(5)
	_controller._reinstall_character_skills_for_player(game_state.players[0])
	var xunli: SkillDefinition = _controller.get_skill_instance(0, "xunli")
	if xunli == null:
		return _fail("xunli_install")
	# 银枝四张起手牌；额外摸牌两张后达到6张，弃牌阶段必定需要弃置2张。
	for hand_index: int in range(4):
		_add_hand(0, "shan", "spade", hand_index + 1)
	_fill_draw_pile(30)
	# 发动前距离基线：改写只影响以银枝为来源的距离查询。
	if _controller.card_rules.calculate_distance(0, 3) != 2 or _controller.card_rules.calculate_distance(2, 3) != 1:
		return _fail("distance_baseline=%d/%d" % [_controller.card_rules.calculate_distance(0, 3), _controller.card_rules.calculate_distance(2, 3)])
	# 2号位回合开始：巡礼询问必须归属于银枝（0号位本地玩家）。
	_controller._start_turn(2)
	if not await _await_local_choice("xunli_activate"):
		return false
	if not _submit_control(true, "xunli_activate_yes"):
		return false
	# 确认后先延后启动阶段链，再依次执行额外摸牌阶段；等待统一管线把阶段推进到额外出牌阶段。
	if not await _await_local_choice("lijie_gain_target"):
		return false
	# 快照目标集合：只有与2号位距离为1的角色（1号位与3号位）被改写。
	if xunli._override_target_ids.size() != 2 or not xunli._override_target_ids.has(1) or not xunli._override_target_ids.has(3):
		return _fail("override_snapshot=%s" % str(xunli._override_target_ids.keys()))
	if not bool(xunli._distance_override_active):
		return _fail("override_inactive")
	# 阶段内距离改写：3号位的距离由2改写为1；回合角色2号位不在快照内，保持2。
	if _controller.card_rules.calculate_distance(0, 3) != 1 or _controller.card_rules.calculate_distance(0, 2) != 2:
		return _fail("distance_override=%d/%d" % [_controller.card_rules.calculate_distance(0, 3), _controller.card_rules.calculate_distance(0, 2)])
	# 额外摸牌阶段的2张牌同时满足礼节“一次性获得至少两张牌”，因此此处正等待礼节的目标选择。
	if game_state.players[0].hand.size() != 6:
		return _fail("extra_draw_hand=%d" % game_state.players[0].hand.size())
	# 礼节第一段：令3号位摸一张牌；提交后额外摸牌阶段才会完成并进入额外出牌阶段。
	if not _submit_targets([3], true):
		return false
	if game_state.players[3].hand.size() != 1:
		return _fail("lijie_gain_target_hand=%d" % game_state.players[3].hand.size())
	await _settle_frames(3)
	if game_state.current_player_id != 0 or game_state.current_phase != "play":
		return _fail("extra_play=%d/%s" % [game_state.current_player_id, game_state.current_phase])
	# 结束额外出牌阶段，进入额外弃牌阶段；6张手牌超过上限4，必须弃置2张。
	if not _controller.end_current_play_phase(0):
		return false
	if not await _await_local_choice("extra_discard_phase"):
		return false
	# 强制弃牌候选；从请求快照中取前两张，避免依赖手牌顺序之外的字段。
	var discard_uids: Array[int] = []
	for candidate_variant: Variant in _local_choice_request.get("candidates", []) as Array:
		var candidate: Dictionary = candidate_variant as Dictionary
		if discard_uids.size() < 2:
			discard_uids.append(int(candidate.get("uid", -1)))
	if discard_uids.size() != 2:
		return _fail("discard_candidates=%s" % str(_local_choice_request.get("candidates", [])))
	if not _submit_cards(discard_uids, true):
		return false
	# 阶段链收尾：距离改写解除、活动阶段清空、回合交还给2号位。
	if bool(xunli._distance_override_active) or not xunli._override_target_ids.is_empty() or not str(xunli._chain_stage).is_empty():
		return _fail("chain_not_finalized=%s" % str(xunli._override_target_ids.keys()))
	if not _controller._active_extra_draw_phase.is_empty() or not _controller._active_extra_discard_phase.is_empty() or not _controller._active_independent_play_phase.is_empty():
		return _fail("active_phase_leftover")
	if _controller.card_rules.calculate_distance(0, 3) != 2:
		return _fail("distance_restored=%d" % _controller.card_rules.calculate_distance(0, 3))
	if game_state.current_player_id != 2:
		return _fail("turn_not_resumed=%d" % game_state.current_player_id)
	if game_state.players[0].hand.size() != 4:
		return _fail("discard_hand=%d" % game_state.players[0].hand.size())
	# 每轮一次：本轮额度已消耗，新的一轮开始后自动恢复。
	if int(xunli._used_round_number) != 1 or xunli._can_request_activation():
		return _fail("quota_used=%d" % int(xunli._used_round_number))
	game_state.round_number = 2
	if not xunli._can_request_activation():
		return _fail("quota_not_restored")
	return true


## 验证礼节第二段：其他角色令银枝回复体力后，可以令该来源回复1点体力。
func _test_lijie_recover() -> bool:
	# 三人局；银枝与1号位都处于受伤状态，便于观察一次双向回复。
	var game_state: GameState = _install_state(3)
	_controller._reinstall_character_skills_for_player(game_state.players[0])
	if _controller.get_skill_instance(0, "lijie") == null:
		return _fail("lijie_install")
	game_state.players[0].hp = 3
	game_state.players[1].hp = 3
	# 1号位令银枝回复体力；回复结算完成后礼节必须询问是否回赠。
	_controller.recover(1, 0, 1, "yinzhi_test_recover")
	if game_state.players[0].hp != 4:
		return _fail("recover_not_applied=%d" % game_state.players[0].hp)
	if not await _await_local_choice("lijie_recover_source"):
		return false
	if not _submit_control(true, "lijie_recover_yes"):
		return false
	if game_state.players[1].hp != 4:
		return _fail("source_recover=%d" % game_state.players[1].hp)
	# 自己令自己回复不触发：银枝再次受伤后自行回复，不得产生新的询问。
	game_state.players[0].hp = 3
	_controller.recover(0, 0, 1, "yinzhi_test_self_recover")
	await get_tree().process_frame
	await get_tree().process_frame
	if not _local_choice_request.is_empty():
		return _fail("self_recover_triggered=%s" % str(_local_choice_request.get("context", {})))
	return true


## 验证AI口径：延时锦囊对银枝的收益为0，两段询问的评分方向与取消基准。
func _test_ai_rules() -> bool:
	# 本场景只为构造快照；技能以纯AI钩子方式调用，不安装时机。
	var game_state: GameState = _install_state(3)
	var xunli: SkillDefinition = GameDatabase.create_skill("xunli")
	var lijie: SkillDefinition = GameDatabase.create_skill("lijie")
	if xunli == null or lijie == null:
		return _fail("ai_skill_missing")
	xunli.bind(_controller, 0)
	lijie.bind(_controller, 0)
	# 权威快照与评估器；与基础AI读取同一套公开字段。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var snapshot: Dictionary = game_state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	# 延时锦囊对银枝的收益恒为0；以真实牌定义元数据判定，不写死牌ID。
	var delayed_definition: Dictionary = GameDatabase.get_card("lebu")
	var normal_definition: Dictionary = GameDatabase.get_card("sha")
	if not bool(delayed_definition.get("delayed", false)):
		return _fail("lebu_definition")
	if not is_zero_approx(xunli.modify_ai_incoming_card_effect(snapshot, 1, 0, delayed_definition, {}, -1.0, 1, 3.0, evaluator)):
		return _fail("delayed_trick_value")
	# 非延时锦囊与其他目标保持通用估值。
	if not is_equal_approx(xunli.modify_ai_incoming_card_effect(snapshot, 1, 0, normal_definition, {}, -1.0, 1, 3.0, evaluator), 3.0):
		return _fail("normal_card_value")
	if not is_equal_approx(xunli.modify_ai_incoming_card_effect(snapshot, 1, 1, delayed_definition, {}, -1.0, 1, 3.0, evaluator), 3.0):
		return _fail("other_target_value")
	# 巡礼发动确认：确认严格正分（无脑发动），取消保持中性。
	var xunli_context: Dictionary = {"kind":"xunli_activate"}
	if xunli.score_ai_choice(snapshot, {"context":xunli_context}, {"payload":{"confirmed":true, "selected_control_id":"xunli_activate_yes"}}, evaluator) <= 0.0:
		return _fail("xunli_ai_confirm")
	if not is_zero_approx(xunli.score_ai_choice(snapshot, {"context":xunli_context}, {"payload":{"confirmed":false}}, evaluator)):
		return _fail("xunli_ai_cancel")
	# 持有者在等待期间死亡或离场时，AI 不得再提交确认：评分落到强负分。
	# 这里只改快照里的存活标记，因此不依赖任何运行时状态，也不会影响后面的真实回合用例。
	var dead_snapshot: Dictionary = game_state.to_dict(0, true)
	var dead_player: Dictionary = evaluator.get_player(dead_snapshot, 0)
	dead_player["alive"] = false
	if bool(evaluator.get_player(dead_snapshot, 0).get("alive", true)):
		return _fail("dead_snapshot_mutation")
	if xunli.score_ai_choice(dead_snapshot, {"context":xunli_context}, {"payload":{"confirmed":true, "selected_control_id":"xunli_activate_yes"}}, evaluator) > -1.0:
		return _fail("xunli_ai_dead_penalty")
	# 礼节第一段：友方获得一张牌为正、敌方为负、取消为0。
	var gain_context: Dictionary = {"kind":"lijie_gain_target"}
	if lijie.score_ai_choice(snapshot, {"context":gain_context}, {"payload":{"confirmed":true, "selected_target_ids":[2]}}, evaluator) <= 0.0:
		return _fail("lijie_ai_gain_ally")
	if lijie.score_ai_choice(snapshot, {"context":gain_context}, {"payload":{"confirmed":true, "selected_target_ids":[1]}}, evaluator) >= 0.0:
		return _fail("lijie_ai_gain_enemy")
	if not is_zero_approx(lijie.score_ai_choice(snapshot, {"context":gain_context}, {"payload":{"confirmed":false, "selected_target_ids":[]}}, evaluator)):
		return _fail("lijie_ai_gain_cancel")
	# 礼节第二段：友方来源获得1点体力为正、敌方为负、取消为0。
	if lijie.score_ai_choice(snapshot, {"context":{"kind":"lijie_recover_source", "source_id":2}}, {"payload":{"confirmed":true, "selected_control_id":"lijie_recover_yes"}}, evaluator) <= 0.0:
		return _fail("lijie_ai_recover_ally")
	if lijie.score_ai_choice(snapshot, {"context":{"kind":"lijie_recover_source", "source_id":1}}, {"payload":{"confirmed":true, "selected_control_id":"lijie_recover_yes"}}, evaluator) >= 0.0:
		return _fail("lijie_ai_recover_enemy")
	if not is_zero_approx(lijie.score_ai_choice(snapshot, {"context":{"kind":"lijie_recover_source", "source_id":2}}, {"payload":{"confirmed":false}}, evaluator)):
		return _fail("lijie_ai_recover_cancel")
	return true


## 等待若干个空闲帧；规则管线的延后结算与暂停的时机派发按帧恢复。
func _settle_frames(count: int) -> void:
	for _frame_index: int in range(count):
		await get_tree().process_frame


## 等待指定种类的本地请求出现；超时返回false并输出稳定失败标签。
func _await_local_choice(expected_kind: String) -> bool:
	# 最多等待若干帧；规则管线的延后结算按空闲帧恢复，正常只需一到两帧。
	for _attempt: int in range(20):
		await get_tree().process_frame
		if not _local_choice_request.is_empty():
			# 当前请求上下文；kind 用于区分同一角色的多种窗口。
			var context: Dictionary = _local_choice_request.get("context", {}) as Dictionary
			if str(context.get("kind", "")) == expected_kind:
				return true
	return _fail("await_choice=%s got=%s | %s" % [expected_kind, str(_local_choice_request.get("context", {})), _diagnostics()])


## 汇总当前规则进度，供等待类断言失败时定位卡点。
func _diagnostics() -> String:
	if _controller == null or _controller.state == null:
		return "no_state"
	# 巡礼实例；用于读取阶段链进度。
	var xunli: SkillDefinition = _controller.get_skill_instance(0, "xunli")
	return "phase=%s cur=%d hand0=%d chain=%s override=%s draw_active=%s play_active=%s discard_active=%s pending=%s settle=%s logs=%s" % [
		_controller.state.current_phase,
		_controller.state.current_player_id,
		_controller.state.get_player(0).hand.size(),
		str(xunli._chain_stage) if xunli != null else "none",
		str(xunli._distance_override_active) if xunli != null else "none",
		str(not _controller._active_extra_draw_phase.is_empty()),
		str(not _controller._active_independent_play_phase.is_empty()),
		str(not _controller._active_extra_discard_phase.is_empty()),
		"chooser=%s kind=%s req=%s" % [
			str(_controller._pending_card_choice.get("chooser_id", -1)),
			str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")),
			str(_controller._pending_card_choice.get("request_id", -1)),
		],
		str(_controller._deferred_skill_settlements.size()),
		str(_logs.slice(maxi(_logs.size() - 6, 0))),
	]


## 提交最近一次本地请求的控制项选择；取消时 control_id 传空串。
func _submit_control(confirmed: bool, control_id: String) -> bool:
	if _local_choice_request.is_empty():
		return _fail("submit_control_without_request")
	# 标准选择动作；控制项选择同样携带 confirmed 供取消分支使用。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(_local_choice_request.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":control_id, "confirmed":confirmed}
	# 先清空捕获再提交：同一次提交的规则恢复可能立刻创建下一个询问（结算与选择恢复在同一调用栈内）。
	_local_choice_request.clear()
	if not _controller.submit_action(action):
		return _fail("control_rejected=%s/%s" % [str(confirmed), control_id])
	return true


## 提交最近一次本地请求的目标选择；目标数组必须与请求的上下限匹配。
func _submit_targets(target_ids: Array[int], confirmed: bool) -> bool:
	if _local_choice_request.is_empty():
		return _fail("submit_targets_without_request")
	# 标准选择动作；请求编号来自捕获的权威快照。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(_local_choice_request.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	# 先清空捕获再提交：同一次提交的规则恢复可能立刻创建下一个询问。
	_local_choice_request.clear()
	if not _controller.submit_action(action):
		return _fail("targets_rejected=%s" % str(target_ids))
	return true


## 提交最近一次本地请求的手牌选择；强制阶段不允许取消。
func _submit_cards(card_uids: Array[int], confirmed: bool) -> bool:
	if _local_choice_request.is_empty():
		return _fail("submit_cards_without_request")
	# 标准选择动作；请求编号用于绑定创建时的窗口。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(_local_choice_request.get("request_id", -1)), "selected_card_uids":card_uids.duplicate(), "selected_target_ids":[], "confirmed":confirmed}
	# 先清空捕获再提交：同一次提交的规则恢复可能立刻创建下一个询问。
	_local_choice_request.clear()
	if not _controller.submit_action(action):
		return _fail("cards_rejected=%s" % str(card_uids))
	return true


## 向指定角色手牌区加入一张实体牌；直接入区必须补齐正式移动服务会写入的字段。
func _add_hand(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 持有者状态；手牌区数组即为权威存储。
	var player: PlayerState = _controller.state.get_player(player_id)
	# 新实体牌；所有权与区域在加入数组前完整写入。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.owner_id = player_id
	card.zone = "hand"
	player.hand.append(card)
	return card


## 向公共牌堆压入指定数量的实体牌；GameState 使用数组末尾作为牌堆顶。
func _fill_draw_pile(count: int) -> void:
	for card_index: int in range(count):
		# 当前牌堆实体牌；公共牌堆没有所属玩家。
		var card: CardInstance = CardInstance.new("shan", "heart", card_index % 13 + 1)
		card.zone = "draw_pile"
		card.owner_id = -1
		_controller.state.draw_pile.append(card)


## 捕获属于0号本地玩家的统一选择请求；AI 请求不会覆盖等待断言的本地上下文。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	if int(choice_data.get("chooser_id", -1)) == 0:
		_local_choice_request = choice_data.duplicate(true)


## 捕获日志文本；用于断言锁定技纠正与技能发动留痕。
func _on_log_added(message: String) -> void:
	_logs.append(message)


## 输出稳定失败原因并以非0状态退出，便于命令行定位具体断言。
func _fail(reason: String) -> bool:
	if _finished:
		return false
	_finished = true
	printerr("YINZHI_FAIL %s" % reason)
	get_tree().quit(1)
	return false
