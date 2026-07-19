extends Node

## 本组专项回归验证阶段限次、连环切换、借刀目标语义、锁定技标签与阶段 Begin 技能询问。

## 测试使用的权威控制器；依赖结构与正式主场景保持一致。
var _controller: MatchController

## 当前异步选择场景；选择信号根据该稳定值提交对应标准响应。
var _scenario: String = ""

## 借刀杀人测试中持刀者用于响应的【杀】实体 UID；默认-1表示尚未创建。
var _borrow_slash_uid: int = -1

## 是否在 phaseUseBegin 同步调用栈中收到【行军】发动询问；默认 false。
var _xingjun_begin_request_seen: bool = false

## 同一使用牌时机实际收到的可选技能询问顺序；用于验证从当前回合角色起按座次依次询问。
var _same_timing_choice_kinds: Array[String] = []

## 最近一次控制器状态快照；用于验证选将结束后会在首轮技能询问前同步起始手牌与过渡阶段。
var _latest_state_snapshot: Dictionary = {}

## 隐藏手牌保护场景实际收到的技能询问类型；【铁壁】与【坚垒】均应在没有【闪】时出现。
var _hidden_hand_prompt_kinds: Array[String] = []

## 测试是否已经失败；失败后延迟选择回调不得继续提交旧请求。
var _failed: bool = false


## 延迟一帧执行全部断言，保证自动加载数据库已经完成卡牌和技能扫描。
func _ready() -> void:
	call_deferred("_run")


## 依次执行互相隔离的专项场景；任一失败立即结束测试。
func _run() -> void:
	_create_controller()
	if not _test_lock_metadata():
		return
	if not _test_play_phase_limit_scope():
		return
	if not _test_chain_targets_and_ai():
		return
	if not await _test_opening_skill_prompt_and_hidden_hand_privacy():
		return
	if not _test_restricted_group_trick_targets():
		return
	if not await _test_same_timing_skill_prompt_order():
		return
	if not await _test_borrow_sword_target_semantics():
		return
	if not await _test_borrow_sword_weapon_transfer():
		return
	if not await _test_phase_use_begin_prompt():
		return
	print("REQUESTED_CHANGES_PASS")
	get_tree().quit(0)


## 创建控制器及解耦子组件；全部玩家动作仍通过 PlayerAction 进入权威校验。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能时机与卡牌生命周期通过该节点派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；铁索测试直接创建策略，异步选择由测试代码模拟本地玩家。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网络网关；保留与正式对局一致的动作来源协议。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.card_choice_requested.connect(_on_card_choice_requested)
	_controller.state_changed.connect(_on_state_changed)


## 为单项测试创建指定人数的最小权威状态，并重新绑定全部状态型服务。
func _reset_state(player_count: int) -> void:
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "requested-changes-%s" % _scenario
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号位为公开领袖，其余角色为公开反贼，便于 AI 形成确定态度。
		var player: PlayerState = PlayerState.new(player_id, "专项玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, _controller.state)
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._negation_resume_results.clear()
	_controller._started_phase_lifecycles.clear()
	_controller._extra_play_phase_counts.clear()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.ai_coordinator._policies.clear()
	_borrow_slash_uid = -1
	_xingjun_begin_request_seen = false
	_same_timing_choice_kinds.clear()
	_latest_state_snapshot.clear()


## 验证所有技能元数据都拥有 bool 类型 lock，且现有锁定技【星火】明确标记为 true。
func _test_lock_metadata() -> bool:
	for skill_id_variant: Variant in GameDatabase.skills.keys():
		# 当前技能 ID；数据库键来自目录扫描结果，循环覆盖正式技能与样例技能。
		var skill_id: String = str(skill_id_variant)
		# 当前技能元数据；基类必须为所有定义补齐 bool 类型 lock，调用方不处理字段缺失。
		var metadata: Dictionary = GameDatabase.get_skill(skill_id)
		if not metadata.has("lock") or not (metadata.get("lock") is bool):
			return _fail("skill_lock_type id=%s value=%s" % [skill_id, metadata.get("lock")])
		# 当前技能说明；以“锁定技”开头的现有技能必须显式登记 true，避免说明与规则标签分离。
		var description: String = str(metadata.get("description", ""))
		if description.begins_with("锁定技") and not bool(metadata.get("lock", false)):
			return _fail("locked_skill_missing_tag id=%s" % skill_id)
	# 星火静态元数据；锁定技标签必须使用需求指定的精确字段名 lock。
	var locked_metadata: Dictionary = GameDatabase.get_skill("xinghuo")
	# 星火运行时实例；成员变量与对外元数据必须保持同一 bool 值。
	var locked_skill: SkillDefinition = GameDatabase.create_skill("xinghuo")
	# 普通技能元数据；基类应自动补齐 false，而不是让调用方处理缺失字段。
	var normal_metadata: Dictionary = GameDatabase.get_skill("tianzhui")
	if not locked_metadata.has("lock") or not (locked_metadata.get("lock") is bool) or not bool(locked_metadata.get("lock", false)) or locked_skill == null or not locked_skill.lock:
		return _fail("lock_metadata=%s runtime=%s" % [locked_metadata.get("lock"), locked_skill.lock if locked_skill != null else false])
	if not normal_metadata.has("lock") or not (normal_metadata.get("lock") is bool) or bool(normal_metadata.get("lock", true)):
		return _fail("normal_lock_metadata=%s" % normal_metadata.get("lock"))
	return true


## 验证【杀】按每个出牌阶段独立限次，而【酒】继续保留每回合一次限制。
func _test_play_phase_limit_scope() -> bool:
	_scenario = "play_phase_limit"
	_reset_state(2)
	# 当前行动玩家；两个历史分别模拟本回合与本出牌阶段已经使用一次普通【杀】。
	var actor: PlayerState = _controller.state.get_player(0)
	actor.card_use_history["sha"] = 1
	actor.play_phase_card_use_history["sha"] = 1
	# 第二张【杀】；同一阶段校验必须失败，进入额外阶段后必须重新合法。
	var slash: CardInstance = _add_hand_card(0, "sha", "club", 7)
	if _controller.card_rules.validate_use(0, slash, [1]).is_empty():
		return _fail("slash_same_phase_allowed")
	_controller._start_extra_play_phase(0)
	if not actor.play_phase_card_use_history.is_empty() or not _controller.card_rules.validate_use(0, slash, [1]).is_empty():
		return _fail("slash_extra_phase history=%s error=%s" % [actor.play_phase_card_use_history, _controller.card_rules.validate_use(0, slash, [1])])
	_controller._cancel_active_play_choice("requested_changes_phase_limit")
	# 【酒】回合历史；即使阶段历史已经清空，回合级限制仍必须拒绝第二次使用。
	var wine: CardInstance = _add_hand_card(0, "jiu", "spade", 9)
	actor.card_use_history["jiu"] = 1
	actor.play_phase_card_use_history.clear()
	if _controller.card_rules.validate_use(0, wine, [0]).is_empty():
		return _fail("wine_turn_limit_lost")
	return true


## 验证铁索允许自身、枚举双目标，并令基础 AI 在两个敌方均适合横置时选择两名目标。
func _test_chain_targets_and_ai() -> bool:
	_scenario = "chain_ai"
	_reset_state(3)
	# 铁索实体；普通手牌同时提供使用与重铸动作。
	var chain: CardInstance = _add_hand_card(0, "tiesuo", "club", 12)
	# 合法目标；必须显式包含使用者本人。
	var legal_target_ids: Array[int] = _controller.card_rules.list_legal_targets(0, chain)
	if not legal_target_ids.has(0) or not _controller.card_rules.validate_use(0, chain, [0]).is_empty():
		return _fail("chain_self_target=%s" % [legal_target_ids])
	# 全部合法动作；铁索源码应提供单目标和双目标组合，而不是只生成一名目标。
	var legal_actions: Array[Dictionary] = _controller.get_legal_actions(0)
	# 双目标铁索动作数量；大于0证明规则枚举已经覆盖组合。
	var double_target_action_count: int = 0
	for action: Dictionary in legal_actions:
		if str(action.get("action_type", "")) == "use_card" and int(action.get("card_uid", -1)) == chain.uid and (action.get("target_ids", []) as Array).size() == 2:
			double_target_action_count += 1
	if double_target_action_count == 0:
		return _fail("chain_double_actions=%s" % [legal_actions])
	# 基础 AI 策略；公开身份保证一号领袖明确敌视二、三号反贼。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0)
	# 最终动作；两个未横置敌方同时产生正收益时应使用一张铁索指定两名目标。
	var chosen_action: Dictionary = policy.choose_action(_controller.state.to_dict(0, true), legal_actions)
	if str(chosen_action.get("action_type", "")) != "use_card" or int(chosen_action.get("card_uid", -1)) != chain.uid or (chosen_action.get("target_ids", []) as Array).size() != 2:
		return _fail("chain_ai_action=%s" % [chosen_action])
	# 星火运行时技能；同一唯一目标连续触发两次应先横置再竖置。
	var xinghuo: SkillDefinition = GameDatabase.create_skill("xinghuo")
	xinghuo.bind(_controller, 0)
	# 星火触发事件；铁索属于锦囊牌且目标数组只有二号玩家。
	var targeted_event: RuleEvent = RuleEvent.new("useCardToTargeted", 0, 1, {"card_id":"tiesuo", "target_id":1, "target_ids":[1]}, 0)
	xinghuo.call("_on_owner_card_targeted", targeted_event)
	if not _controller.state.get_player(1).chained:
		return _fail("first_relink_not_horizontal")
	xinghuo.call("_on_owner_card_targeted", targeted_event)
	if _controller.state.get_player(1).chained:
		return _fail("second_relink_not_vertical")
	return true


## 验证选将结束先同步亮将与4张起始手牌，并验证【铁壁】【坚垒】不会因没有【闪】而跳过可取消询问。
func _test_opening_skill_prompt_and_hidden_hand_privacy() -> bool:
	_scenario = "opening_tiebi_privacy"
	_hidden_hand_prompt_kinds.clear()
	_reset_state(2)
	_controller.state.current_phase = "character_selection"
	# 开局牌堆全部使用非【闪】实体；【铁壁】仍必须创建可取消请求，同时牌桌快照应已经包含每人4张起始手牌。
	for card_index: int in range(8):
		_add_draw_pile_card("sha", "heart", card_index % 13 + 1)
	# 选将服务完成结果；领袖选择星存护，另一名角色选择希儿，随后直接进入正式统一收尾入口。
	var selection_service: CharacterSelectionService = CharacterSelectionService.new()
	var selection_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	selection_rng.seed = 20260720
	if not selection_service.begin(_controller.state.players, ["xing_cunhu", "xier"], 2, selection_rng).is_empty():
		return _fail("opening_selection_begin")
	if not selection_service.select_character(0, "xing_cunhu").is_empty() or not selection_service.select_character(1, "xier").is_empty():
		return _fail("opening_selection_submit")
	_controller.character_selection = selection_service
	_controller.call("_apply_character", _controller.state.get_player(0), "xing_cunhu", true)
	_controller.call("_finish_character_selection")
	# 当前请求；没有【闪】时只能取消，但请求本身必须存在且选将遮罩对应阶段已经结束。
	var opening_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var opening_context: Dictionary = opening_choice.get("context", {}) as Dictionary
	var snapshot_players: Array = _latest_state_snapshot.get("players", []) as Array
	if str(opening_context.get("kind", "")) != "tiebi_cost_target" or not (opening_choice.get("candidates", []) as Array).is_empty() or str(_latest_state_snapshot.get("current_phase", "")) == "character_selection" or snapshot_players.size() != 2 or int((snapshot_players[0] as Dictionary).get("hand_count", -1)) != 4 or int((snapshot_players[1] as Dictionary).get("hand_count", -1)) != 4:
		return _fail("opening_tiebi choice=%s snapshot=%s" % [opening_choice, _latest_state_snapshot])
	if not await _wait_until_no_card_choice():
		return _fail("opening_tiebi_cancel_timeout")
	# 【坚垒】无【闪】场景；黑色【杀】已在处理区，距离1的其他角色成为目标时仍应出现只能取消的请求。
	_scenario = "jianlei_privacy"
	_reset_state(2)
	var jianlei: SkillDefinition = GameDatabase.create_skill("jianlei")
	jianlei.bind(_controller, 0)
	var black_slash: CardInstance = CardInstance.new("sha", "spade", 7)
	black_slash.zone = "processing"
	black_slash.owner_id = 1
	_controller.state.processing_area.append(black_slash)
	jianlei.call("_on_any_targeted", RuleEvent.new("useCardToPlayer", 1, 1, {"card_uid":black_slash.uid}, 1))
	var jianlei_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((jianlei_choice.get("context", {}) as Dictionary).get("kind", "")) != "jianlei_cost" or not (jianlei_choice.get("candidates", []) as Array).is_empty():
		return _fail("jianlei_empty_shan_prompt=%s" % [jianlei_choice])
	if not await _wait_until_no_card_choice():
		return _fail("jianlei_cancel_timeout")
	if _hidden_hand_prompt_kinds != ["tiebi_cost_target", "jianlei_cost"]:
		return _fail("hidden_hand_prompt_kinds=%s" % [_hidden_hand_prompt_kinds])
	return true


## 验证【破风】只允许一名其他角色时，全体目标锦囊会收敛到该合法角色而不是因目标不足整张牌不可用。
func _test_restricted_group_trick_targets() -> bool:
	_scenario = "restricted_group_trick"
	_reset_state(3)
	# 破风运行时实例；活动限制只允许二号玩家，使用者本人和三号玩家都应从全体目标中被过滤。
	var pofeng: SkillDefinition = GameDatabase.create_skill("pofeng")
	pofeng.bind(_controller, 0)
	pofeng.set("_active_restricted_target_ids", {1:true})
	_controller.skill_instances_by_player = {0:{"pofeng":pofeng}}
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	# 两张全体目标锦囊；五谷与桃园都应自动得到唯一合法目标，并继续进入合法动作列表。
	var harvest: CardInstance = _add_hand_card(0, "wugu", "heart", 3)
	var peach_garden: CardInstance = _add_hand_card(0, "taoyuan", "heart", 1)
	var harvest_targets: Array[int] = _controller.card_rules.normalize_targets(0, harvest, [])
	var peach_garden_targets: Array[int] = _controller.card_rules.normalize_targets(0, peach_garden, [])
	if harvest_targets != [1] or peach_garden_targets != [1] or not _controller.card_rules.validate_use(0, harvest, harvest_targets).is_empty() or not _controller.card_rules.validate_use(0, peach_garden, peach_garden_targets).is_empty():
		return _fail("restricted_group_targets harvest=%s peach=%s" % [harvest_targets, peach_garden_targets])
	# 合法动作中的目标声明保持空数组；真正使用时仍由规则层按当前限制自动展开唯一目标。
	var legal_actions: Array[Dictionary] = _controller.get_legal_actions(0)
	var legal_group_card_uids: Array[int] = []
	for action: Dictionary in legal_actions:
		if str(action.get("action_type", "")) == "use_card" and int(action.get("card_uid", -1)) in [harvest.uid, peach_garden.uid]:
			legal_group_card_uids.append(int(action.get("card_uid", -1)))
	if not legal_group_card_uids.has(harvest.uid) or not legal_group_card_uids.has(peach_garden.uid):
		return _fail("restricted_group_actions=%s" % [legal_actions])
	return true


## 验证希儿使用【杀】指定目标后，先询问当前回合角色的【再现】，其完成或取消后再询问下一座次布洛妮娅的【军势】。
func _test_same_timing_skill_prompt_order() -> bool:
	_scenario = "same_timing_prompt_order"
	_reset_state(3)
	# 两名技能持有者；当前回合角色为一号希儿，布洛妮娅位于下一座次，正好覆盖用户报告的同一时机顺序。
	_controller.state.get_player(0).character_id = "xier"
	_controller.state.get_player(1).character_id = "bronya"
	# 希儿的【杀】与可选弃置费用；存在费用牌才能保证【再现】确实创建第一条询问。
	var slash: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	_add_hand_card(0, "shan", "heart", 2)
	# 两个运行时技能实例；直接安装可保持测试最小化，同时仍使用正式 TriggerManager、ChoiceRequest 和续列恢复入口。
	var zaixian: SkillDefinition = GameDatabase.create_skill("zaixian")
	var junshi: SkillDefinition = GameDatabase.create_skill("junshi")
	zaixian.bind(_controller, 0)
	junshi.bind(_controller, 1)
	zaixian.install()
	junshi.install()
	_controller.skill_instances_by_player = {0:{zaixian.get_id():zaixian}, 1:{junshi.get_id():junshi}}
	# 真实使用牌流程；测试选择处理器会依次取消两次询问，第二条只有第一条完整恢复后才允许出现。
	_controller._execute_card_use(0, slash, [2])
	if not await _wait_until_card_finalized(slash.uid):
		return _fail("same_timing_prompt_timeout kinds=%s" % [_same_timing_choice_kinds])
	if _same_timing_choice_kinds != ["zaixian_discard", "junshi_confirm"]:
		return _fail("same_timing_prompt_order=%s" % [_same_timing_choice_kinds])
	return true


## 验证【借刀杀人】使用时必须按“持刀者、被【杀】者”声明两个目标，而实际本牌目标时机只保留持刀者。
func _test_borrow_sword_target_semantics() -> bool:
	_scenario = "borrow_sword"
	_reset_state(3)
	# 持刀者武器；攻击范围3保证三人局中其余两名角色均为合法【杀】目标。
	var weapon: CardInstance = CardInstance.new("qinggang", "spade", 6)
	weapon.zone = "equipment"
	weapon.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = weapon
	# 持刀者响应牌；已声明的三号玩家会直接成为其强制【杀】目标，不再创建二次选目标请求。
	var slash: CardInstance = _add_hand_card(1, "sha", "spade", 7)
	_borrow_slash_uid = slash.uid
	# 借刀杀人实体；使用时必须同时声明持刀者与其需要使用【杀】的对象。
	var borrow_sword: CardInstance = _add_hand_card(0, "jiedao", "club", 12)
	if _controller.card_rules.validate_use(0, borrow_sword, [1]).is_empty() or not _controller.card_rules.validate_use(0, borrow_sword, [1, 2]).is_empty():
		return _fail("borrow_target_count one=%s two=%s" % [_controller.card_rules.validate_use(0, borrow_sword, [1]), _controller.card_rules.validate_use(0, borrow_sword, [1, 2])])
	# 真实结算目标与完整声明目标；直接调用内部入口时必须显式传入两套数组，正式 submit_action 会自动完成此分流。
	_controller._execute_card_use(0, borrow_sword, [1], [], false, [1, 2])
	if not await _wait_until_card_finalized(borrow_sword.uid):
		return _fail("borrow_sword_timeout")
	# 被【杀】者体力；拒绝【闪】后固定受到1点普通伤害。
	var victim: PlayerState = _controller.state.get_player(2)
	if victim.hp != 3 or _controller.state.get_player(1).find_hand_card(slash.uid) != null or _controller.state.get_player(1).get_weapon() != weapon:
		return _fail("borrow_sword_result hp=%d slash=%s weapon=%s" % [victim.hp, _controller.state.get_player(1).find_hand_card(slash.uid) != null, _controller.state.get_player(1).get_weapon() == weapon])
	# 被【杀】者是否错误进入借刀牌目标时机；只检查 useCardTo 四组标准目标事件。
	var victim_was_card_target: bool = false
	for record: Dictionary in _controller.event_scheduler.get_event_history():
		if str(record.get("kind", "")) != "start":
			continue
		# 当前事件摘要；目标阶段名称和 target_id 都来自只读运行时历史。
		var event_data: Dictionary = record.get("event", {}) as Dictionary
		if str(event_data.get("name", "")) in CardUseEventService.TARGET_TIMING_NAMES and int((event_data.get("context", {}) as Dictionary).get("target_id", -1)) == 2:
			victim_was_card_target = true
			break
	if victim_was_card_target:
		return _fail("borrow_victim_entered_card_targets")
	# 借刀表现分段；第一段从使用者指向持刀者，第二段从持刀者指向被要求出【杀】者。
	var indicator_stages: Array[Dictionary] = GameDatabase.get_card_definition("jiedao").get_presentation_indicator_stages(0, [1, 2], [1])
	if indicator_stages != [{"actor_id":0, "target_ids":[1]}, {"actor_id":1, "target_ids":[2]}]:
		return _fail("borrow_indicator_stages=%s" % [indicator_stages])
	return true


## 验证借刀目标没有【杀】可打出时完整结算，并把原武器从装备区交给锦囊使用者手牌。
func _test_borrow_sword_weapon_transfer() -> bool:
	_scenario = "borrow_sword_transfer"
	_reset_state(3)
	# 持刀者武器；其手牌保持为空，测试响应处理器会明确取消本次【杀】要求。
	var weapon: CardInstance = CardInstance.new("qinggang", "spade", 6)
	weapon.zone = "equipment"
	weapon.owner_id = 1
	_controller.state.get_player(1).equipment["weapon"] = weapon
	# 借刀杀人实体；完整声明持刀者与被要求出【杀】者，牌效只对持刀者进入目标时机。
	var borrow_sword: CardInstance = _add_hand_card(0, "jiedao", "club", 12)
	_controller._execute_card_use(0, borrow_sword, [1], [], false, [1, 2])
	if not await _wait_until_card_finalized(borrow_sword.uid):
		return _fail("borrow_sword_transfer_timeout")
	# 锦囊使用者状态；接收的武器必须成为隐藏手牌而非直接进入自身装备区。
	var source: PlayerState = _controller.state.get_player(0)
	if _controller.state.get_player(1).equipment.has("weapon") or not source.hand.has(weapon) or weapon.zone != "hand" or weapon.owner_id != 0 or not _controller.state.discard_pile.has(borrow_sword):
		return _fail("borrow_sword_transfer source_hand=%s holder_equipment=%s weapon=%s" % [source.hand.map(func(card: CardInstance) -> int: return card.uid), _controller.state.get_player(1).equipment, weapon.to_dict()])
	return true


## 验证“出牌阶段开始时”技能在 phaseUseBegin 派发期间立即创建询问，而非等待常规出牌请求。
func _test_phase_use_begin_prompt() -> bool:
	_scenario = "xingjun_begin"
	_reset_state(2)
	# 行军运行时实例；直接安装到当前玩家并订阅标准 phaseUseBegin。
	var xingjun: SkillDefinition = GameDatabase.create_skill("xingjun")
	xingjun.bind(_controller, 0)
	xingjun.install()
	_controller.skill_instances_by_player = {0:{xingjun.get_id():xingjun}}
	# 阶段开始结果；Begin 回调应成功创建可取消零牌确认请求。
	var phase_started: bool = _controller._begin_phase_lifecycle("phaseUse", 0, {"turn_number":1}, -1)
	# 当前请求上下文；函数尚未返回到常规 chooseToUse 建立点时已经存在。
	var pending_context: Dictionary = (_controller._pending_card_choice.get("context", {}) as Dictionary).duplicate(true)
	if not phase_started or not _xingjun_begin_request_seen or str(pending_context.get("kind", "")) != "xingjun_phase_use_begin":
		return _fail("xingjun_begin_prompt started=%s seen=%s context=%s" % [phase_started, _xingjun_begin_request_seen, pending_context])
	if not await _wait_until_no_card_choice():
		return _fail("xingjun_begin_cancel_timeout")
	_controller._cancel_active_play_choice("requested_changes_xingjun")
	if _controller.state.current_phase != "play" or xingjun.can_activate():
		return _fail("xingjun_delayed_button phase=%s active=%s" % [_controller.state.current_phase, xingjun.can_activate()])
	return true


## 向指定玩家普通手牌区加入一张测试实体，并返回对象供规则校验与区域断言。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新测试实体牌；区域与所有者字段必须和玩家手牌数组保持一致。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 捕获借刀与行军的统一选择请求，并在下一空闲帧提交标准牌、目标或取消响应。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	if _failed:
		return
	# 当前请求上下文；kind 唯一决定本专项测试的模拟选择。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	# 当前请求用途；未登记类型会立即报告，避免错误请求被空响应掩盖。
	var choice_kind: String = str(context.get("kind", ""))
	# 本次选择的实体牌 UID；目标选择与取消保持空数组。
	var selected_uids: Array[int] = []
	# 本次选择的玩家 ID；普通响应牌与取消保持空数组。
	var selected_target_ids: Array[int] = []
	# 本次是否确认；借刀的强制目标和响应【杀】为 true，拒绝【闪】与行军取消为 false。
	var confirmed: bool = false
	if _scenario == "borrow_sword" and choice_kind == "borrow_sword_response":
		selected_uids = [_borrow_slash_uid]
		confirmed = true
	elif _scenario == "borrow_sword_transfer" and choice_kind == "borrow_sword_response":
		confirmed = false
	elif _scenario == "borrow_sword" and choice_kind == "slash_response":
		confirmed = false
	elif _scenario == "same_timing_prompt_order" and choice_kind in ["zaixian_discard", "junshi_confirm"]:
		_same_timing_choice_kinds.append(choice_kind)
		confirmed = false
	elif _scenario == "same_timing_prompt_order" and choice_kind == "slash_response":
		confirmed = false
	elif _scenario == "xingjun_begin" and choice_kind == "xingjun_phase_use_begin":
		_xingjun_begin_request_seen = true
		confirmed = false
	elif _scenario == "opening_tiebi_privacy" and choice_kind == "tiebi_cost_target":
		_hidden_hand_prompt_kinds.append(choice_kind)
		confirmed = false
	elif _scenario == "jianlei_privacy" and choice_kind == "jianlei_cost":
		_hidden_hand_prompt_kinds.append(choice_kind)
		confirmed = false
	else:
		_fail("unexpected_choice=%s:%s" % [_scenario, choice_kind])
		return
	call_deferred("_submit_choice", int(choice_data.get("request_id", -1)), int(choice_data.get("chooser_id", -1)), selected_uids, selected_target_ids, confirmed)


## 提交捕获到的统一选择；请求 ID、选择者和确认状态均沿用只读请求快照。
func _submit_choice(request_id: int, chooser_id: int, selected_uids: Array[int], selected_target_ids: Array[int], confirmed: bool) -> void:
	if _failed:
		return
	# 标准选择动作；规则层仍会复核请求归属、牌 UID、目标 ID、数量和取消权限。
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		_fail("submit_choice=%s:%d" % [_scenario, request_id])


## 保存控制器最近一次公开状态；测试只读取序列化副本，不持有或修改权威PlayerState。
func _on_state_changed(snapshot: Dictionary) -> void:
	_latest_state_snapshot = snapshot.duplicate(true)


## 向当前测试牌堆顶部加入一张实体；数组末尾是正式摸牌顺序中的牌堆顶。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新牌堆实体；牌堆卡没有所属玩家，发牌时由移动服务写入最终所有者与区域。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 等待指定卡牌离开处理区且普通选择全部完成；超时返回 false 防止测试永久停滞。
func _wait_until_card_finalized(card_uid: int) -> bool:
	for _frame_index: int in range(180):
		await get_tree().process_frame
		if _failed:
			return false
		if _controller._find_processing_card(card_uid) == null and not _controller.has_pending_card_choice():
			return true
	return false


## 等待当前普通选择请求结束；用于没有父处理区卡牌的阶段 Begin 询问。
func _wait_until_no_card_choice() -> bool:
	for _frame_index: int in range(60):
		await get_tree().process_frame
		if _failed:
			return false
		if not _controller.has_pending_card_choice():
			return true
	return false


## 输出稳定失败原因并以非0状态退出；返回 false 便于调用方立即停止后续断言。
func _fail(reason: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("REQUESTED_CHANGES_FAIL %s" % reason)
	get_tree().quit(1)
	return false
