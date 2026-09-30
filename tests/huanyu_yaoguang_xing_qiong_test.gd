extends Node

## 欢愉派系新增内容专项测试：爻光的【凶星】【鸿运】，星与穹共用的【咬它】，星【好活】与穹【当赏】。
## 覆盖静态元数据与正文标签一致性、角标叠层与清空、伤害加成、体力上限防止、
## 目标摸牌、场上弃牌、欢愉技强制驱动与整局花色额度。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 当前场景使用的固定随机源；阿哈时刻的触发判定与随机历史都从该实例取值。
var _rng: RandomNumberGenerator


## 延迟一帧执行全部断言，确保 GameDatabase 已完成新武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行断言；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_character_and_skill_metadata():
		return
	if not _test_xiongxing_stacking_and_badge():
		return
	if not _test_xiongxing_self_max_hp_guard():
		return
	if not _test_dangshang_draws_one_card():
		return
	if not _test_haohuo_discards_field_card():
		return
	if not _test_standalone_joy_performance_request():
		return
	if not _test_yaota_drives_joy_skill():
		return
	if not _test_yaota_drives_all_owned_joy_skills():
		return
	if not _test_yaota_falls_back_to_extra_play_phase():
		return
	if not _test_hongyun_extra_moment():
		return
	print("HUANYU_YAOGUANG_XING_QIONG_PASS xiongxing=116 hongyun yaota haohuo=120 dangshang=120")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器并装配必需子节点；不加载界面，保持规则断言隔离。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；伤害、技能时机与弃置批次共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保留正式节点供身份观察使用。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；动作提交与正式单机模式保持相同来源语义。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0


## 为当前单项测试创建最小权威状态；一号领袖、二号反贼、三号及以后忠臣使AI态度确定。
func _reset_state(player_count: int) -> void:
	# 专项场景隔离：取消上一场景残留的流程延时与出牌请求标记。
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "huanyu-yaoguang"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "start"
	_controller.state.phase_index = 0
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "欢愉测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state, _controller)
	_controller.player_mark_service = PlayerMarkService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller.trigger_manager = TriggerManager.new()
	_controller.timing_service = RuleTimingService.new(_controller.event_bus, _controller.trigger_manager, _controller.state)
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._rule_sequences.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._rule_continuations.reset()
	_controller._started_phase_lifecycles.clear()
	_controller.ai_coordinator._policies.clear()
	_controller._ai_drive_token += 1
	# 轮回技权威服务；真实对局由控制器统一创建，测试最小状态必须补上该组件，
	# 否则技能安装期的轮回技登记会被 null 服务静默拒绝。
	if _controller.reincarnation_skill_service == null:
		_controller.reincarnation_skill_service = ReincarnationSkillService.new()
	_controller.reincarnation_skill_service.configure(_controller)
	# 阿哈时刻组件；【鸿运】的额外演出与【咬它】的欢愉技驱动都经它执行，
	# 每个场景都绑定当前权威状态与固定随机源，保证触发判定与随机历史可复现。
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260930
	_controller.ahha_moment_system.configure(_controller, _controller.state, _rng, true)


## 向指定玩家手牌区加入一张实体牌；测试需要绕过摸牌流程构造确定手牌。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向摸牌堆顶部加入一张实体；数组末尾固定表示最顶层。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 牌堆实体；公共牌堆没有所属玩家。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 向指定玩家装备区加入一张装备牌；直接写入槽位字典以模拟已经装备完成的场上牌。
func _add_equipment_card(player_id: int, slot: String, definition_id: String) -> CardInstance:
	# 装备实体牌；区域与归属必须与真实装备流程保持一致。
	var card: CardInstance = CardInstance.new(definition_id, "spade", 7)
	card.zone = "equipment"
	card.owner_id = player_id
	_controller.state.get_player(player_id).equipment[slot] = card
	return card


## 向指定玩家判定区加入一张延时锦囊；数组顺序即真实判定顺序。
func _add_judgment_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 判定区实体牌；区域与归属必须与真实判定区流程保持一致。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "judgment"
	card.owner_id = player_id
	_controller.state.get_player(player_id).judgment_area.append(card)
	return card


## 为指定玩家安装一个运行时技能实例；通过真实 install() 复现时机订阅。
func _install_single_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 技能实例；技能目录缺失时返回null并交由调用方报告具体场景。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家已安装技能表；同一场景可连续追加多个技能。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 为当前统一选择请求提交目标、文字选项或确认结果；使用正式 PlayerAction 入口。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool, selected_control_id: String = "") -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；目标、文字选项与确认状态均显式填写。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s pending=%s" % [actor_id, request_id, action.payload, _controller._pending_card_choice])
	return true


## 触发持有者的回合开始前入口；使用真实时机对象复现 phaseBefore 派发参数。
func _trigger_turn_before(skill: SkillDefinition, player_id: int, turn_number: int) -> void:
	skill.call("_on_owner_turn_before", RuleEvent.new("phaseBefore", player_id, player_id, {"turn_number":turn_number}))


## 校验“令指定角色立即发动其欢愉技”这一请求入口本身可用；【咬它】与【鸿运】都依赖它。
func _test_standalone_joy_performance_request() -> bool:
	_reset_state(3)
	_controller.state.get_player(2).character_id = "huohua"
	if _install_single_skill(2, "haoxi") == null:
		return _fail("standalone_haoxi_missing")
	# 好戏只把“持有手牌的其他角色”当作合法目标；没有候选时它会立即收尾而不打开窗口。
	_add_hand_card(0, "sha", "spade", 5)
	# 请求入口；调用后必须建立演出队列，并由好戏打开自己的目标窗口。
	var started: bool = _controller.try_perform_single_joy_skill(2, "haoxi", {"kind":"test_completion", "skill_owner_id":0, "skill_id":"test", "skill_character_generation":-1})
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if not started or str((request.get("context", {}) as Dictionary).get("kind", "")) != "haoxi_targets":
		return _fail("standalone_joy_request started=%s request=%s active=%s queue=%s index=%d" % [started, request, _controller.ahha_moment_system.is_active(), _controller.ahha_moment_system._performance_queue, _controller.ahha_moment_system._active_index])
	return true


## 校验三名新武将的元数据与五项技能的静态正文和标签。
func _test_character_and_skill_metadata() -> bool:
	# 爻光：仙舟联盟女性、3点基础体力、两项技能按声明顺序登记。
	var yaoguang: Dictionary = GameDatabase.get_character("yaoguang")
	if str(yaoguang.get("display_name", "")) != "爻光" or str(yaoguang.get("gender", "")) != "female" or str(yaoguang.get("faction", "")) != "xianzhou" or int(yaoguang.get("max_hp", 0)) != 3:
		return _fail("yaoguang_metadata %s" % [yaoguang])
	if (yaoguang.get("skills", []) as Array) != ["xiongxing", "hongyun"]:
		return _fail("yaoguang_skills %s" % [yaoguang.get("skills", [])])
	# 星：欢愉派系女性、4点基础体力。
	var xing: Dictionary = GameDatabase.get_character("xing_huanyv")
	if str(xing.get("display_name", "")) != "星" or str(xing.get("gender", "")) != "female" or str(xing.get("faction", "")) != "huanyu" or int(xing.get("max_hp", 0)) != 4:
		return _fail("xing_huanyv_metadata %s" % [xing])
	if (xing.get("skills", []) as Array) != ["yaota", "haohuo"]:
		return _fail("xing_huanyv_skills %s" % [xing.get("skills", [])])
	# 穹：欢愉派系男性、4点基础体力；与星共用同一技能ID。
	var qiong: Dictionary = GameDatabase.get_character("qiong_huanyv")
	if str(qiong.get("display_name", "")) != "穹" or str(qiong.get("gender", "")) != "male" or str(qiong.get("faction", "")) != "huanyu" or int(qiong.get("max_hp", 0)) != 4:
		return _fail("qiong_huanyv_metadata %s" % [qiong])
	if (qiong.get("skills", []) as Array) != ["yaota", "dangshang"]:
		return _fail("qiong_huanyv_skills %s" % [qiong.get("skills", [])])
	# 技能正文逐字锁定；任何标点或语序变化都必须在这里失败。
	var expected_descriptions: Dictionary = {
		"xiongxing":"欢愉技，参演编号116，你令一名角色下次受到的伤害+1。若该角色为你，则当你下次体力上限减少时，防止之。",
		"hongyun":"你的回合开始前，你可以立即触发一次额外的阿哈时刻；该阿哈时刻结束后，你减少1点体力上限。每轮限一次。",
		"yaota":"每种花色限一次，你的回合开始前，你可以弃置一张手牌，然后令一名角色发动其欢愉技。若其没有欢愉技，则令其执行一个额外的出牌阶段。",
		"haohuo":"欢愉技，参演编号120，你弃置场上的一张牌。",
		"dangshang":"欢愉技，参演编号120，你令一名角色摸一张牌。",
	}
	for skill_id: String in expected_descriptions.keys():
		# 当前技能定义；缺失或正文不一致都必须立即失败。
		var definition: Dictionary = GameDatabase.get_skill(skill_id)
		if str(definition.get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("%s_description %s" % [skill_id, definition.get("description", "")])
	# 欢愉技标签与参演编号；非欢愉技不得声明编号。
	var expected_joy_numbers: Dictionary = {"xiongxing":116, "haohuo":120, "dangshang":120}
	for skill_id: String in ["xiongxing", "hongyun", "yaota", "haohuo", "dangshang"]:
		# 当前技能元数据中的欢愉技标签与编号。
		var definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 期望编号；不在表内表示该技能不是欢愉技。
		var is_joy: bool = expected_joy_numbers.has(skill_id)
		if bool(definition.get("joy_skill", false)) != is_joy:
			return _fail("%s_joy_tag %s" % [skill_id, definition.get("joy_skill", false)])
		if int(definition.get("performance_number", 0)) != int(expected_joy_numbers.get(skill_id, 0)):
			return _fail("%s_performance_number %d" % [skill_id, definition.get("performance_number", 0)])
	# 正文类型声明判定；咬它与鸿运在效果描述中引用“欢愉技”，必须不被误判为类型声明。
	if not SkillDefinition.description_declares_joy_type(str(expected_descriptions["xiongxing"])):
		return _fail("xiongxing_description_type")
	if SkillDefinition.description_declares_joy_type(str(expected_descriptions["yaota"])):
		return _fail("yaota_description_type")
	if SkillDefinition.description_declares_joy_type(str(expected_descriptions["hongyun"])):
		return _fail("hongyun_description_type")
	return true


## 校验【凶星】叠层、角标文本、伤害加成与一次性消费。
func _test_xiongxing_stacking_and_badge() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "yaoguang"
	var xiongxing: SkillDefinition = _install_single_skill(0, "xiongxing")
	if xiongxing == null or not xiongxing.is_joy_skill() or xiongxing.get_performance_number() != 116:
		return _fail("xiongxing_static")
	# 第一次发动；窗口必须存在且不可取消，候选含自己与其他角色。
	xiongxing.perform_joy_skill({})
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(request.get("choice_type", "")) != "target" or bool(request.get("allow_cancel", true)) or (request.get("target_ids", []) as Array).size() != 3:
		return _fail("xiongxing_request %s" % [request])
	if not _submit_pending_choice(0, [], [1], true):
		return false
	# 一层凶星：私有层数为1，角标只显示基础文本。
	var target: PlayerState = _controller.state.get_player(1)
	if int(target.character_form_state.get("xiongxing_damage_stacks", 0)) != 1 or target.character_corner_text != "凶星":
		return _fail("xiongxing_first_stack state=%s text=%s" % [target.character_form_state, target.character_corner_text])
	# 第二次发动叠加到两层；角标改为“凶星2”。
	xiongxing.perform_joy_skill({})
	if not _submit_pending_choice(0, [], [1], true):
		return false
	if int(target.character_form_state.get("xiongxing_damage_stacks", 0)) != 2 or target.character_corner_text != "凶星2":
		return _fail("xiongxing_second_stack state=%s text=%s" % [target.character_form_state, target.character_corner_text])
	# 一次1点普通伤害被提升到3点；成立后清空全部层数与角标。
	_controller.damage(0, 1, 1, "normal", "sha")
	if target.hp != 1 or int(target.character_form_state.get("xiongxing_damage_stacks", 0)) != 0 or not target.character_corner_text.is_empty():
		return _fail("xiongxing_consume hp=%d state=%s text=%s" % [target.hp, target.character_form_state, target.character_corner_text])
	# 消费后的下一次伤害恢复基础值，证明层数确实已经清空。
	_controller.damage(0, 1, 1, "normal", "sha")
	if target.hp != 0:
		return _fail("xiongxing_after_consume hp=%d" % target.hp)
	return true


## 校验【凶星】自选时的体力上限保护；保护只对持有者本人生效并一次性消耗。
func _test_xiongxing_self_max_hp_guard() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "yaoguang"
	var xiongxing: SkillDefinition = _install_single_skill(0, "xiongxing")
	xiongxing.perform_joy_skill({})
	if not _submit_pending_choice(0, [], [0], true):
		return false
	var owner: PlayerState = _controller.state.get_player(0)
	if int(owner.character_form_state.get("xiongxing_max_hp_guard", 0)) != 1:
		return _fail("xiongxing_guard_state %s" % [owner.character_form_state])
	# 体力上限减少被完全防止；上限、防止额度与减少返回值同时保持中性。
	var applied: int = _controller.change_max_hp(0, -1, 1, "test")
	if applied != 0 or owner.max_hp != 4 or int(owner.character_form_state.get("xiongxing_max_hp_guard", 0)) != 0:
		return _fail("xiongxing_guard_prevent applied=%d max_hp=%d state=%s" % [applied, owner.max_hp, owner.character_form_state])
	# 保护已消耗；第二次上限减少正常生效。
	var second_applied: int = _controller.change_max_hp(0, -1, 1, "test")
	if second_applied == 0 or owner.max_hp != 3:
		return _fail("xiongxing_guard_consumed applied=%d max_hp=%d" % [second_applied, owner.max_hp])
	return true


## 校验【当赏】令目标摸一张牌，且窗口不可取消、含持有者自己。
func _test_dangshang_draws_one_card() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "qiong_huanyv"
	_add_draw_pile_card("sha", "spade", 7)
	var dangshang: SkillDefinition = _install_single_skill(0, "dangshang")
	if dangshang == null or not dangshang.is_joy_skill() or dangshang.get_performance_number() != 120:
		return _fail("dangshang_static")
	dangshang.perform_joy_skill({})
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(request.get("choice_type", "")) != "target" or bool(request.get("allow_cancel", true)) or not (request.get("target_ids", []) as Array).has(0):
		return _fail("dangshang_request %s" % [request])
	if not _submit_pending_choice(0, [], [1], true):
		return false
	if _controller.state.get_player(1).hand.size() != 1 or not _controller.state.draw_pile.is_empty():
		return _fail("dangshang_draw hand=%d pile=%d" % [_controller.state.get_player(1).hand.size(), _controller.state.draw_pile.size()])
	return true


## 校验【好活】弃置场上的一张牌；判定区与装备区都属于“场上”，手牌区不属于。
func _test_haohuo_discards_field_card() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "xing_huanyv"
	# 敌方判定区的延时锦囊、敌方装备区的武器，以及一张不应出现在候选中的敌方手牌。
	var judgment_card: CardInstance = _add_judgment_card(1, "lebu", "heart", 6)
	var equipment_card: CardInstance = _add_equipment_card(1, "weapon", "qinggang")
	var hand_card: CardInstance = _add_hand_card(1, "sha", "spade", 9)
	var haohuo: SkillDefinition = _install_single_skill(0, "haohuo")
	if haohuo == null or not haohuo.is_joy_skill() or haohuo.get_performance_number() != 120:
		return _fail("haohuo_static")
	haohuo.perform_joy_skill({})
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	# 候选UID集合；必须同时包含判定区与装备区牌，且排除手牌。
	var candidate_uids: Array[int] = []
	for candidate_variant: Variant in request.get("candidates", []) as Array:
		candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	if str(request.get("choice_type", "")) != "card" or bool(request.get("allow_cancel", true)) or not candidate_uids.has(judgment_card.uid) or not candidate_uids.has(equipment_card.uid) or candidate_uids.has(hand_card.uid):
		return _fail("haohuo_candidates %s" % [request])
	if not _submit_pending_choice(0, [equipment_card.uid], [], true):
		return false
	if not _controller.state.discard_pile.has(equipment_card) or _controller.state.get_player(1).equipment.has("weapon"):
		return _fail("haohuo_discard")
	return true


## 校验【咬它】用一张花色手牌强制驱动目标的欢愉技，并锁定该花色的整局额度。
func _test_yaota_drives_joy_skill() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "xing_huanyv"
	# 队友掌握欢愉技【好戏】；咬它必须驱动其演出而不是给予额外阶段。
	_controller.state.get_player(2).character_id = "huohua"
	if _install_single_skill(2, "haoxi") == null:
		return _fail("yaota_target_haoxi_missing")
	# 支付用黑桃手牌与牌堆基本牌；另给另一名队友一张手牌，好戏才有合法弃置目标。
	var cost: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	_add_hand_card(1, "tao", "heart", 5)
	_add_draw_pile_card("shan", "heart", 2)
	_add_draw_pile_card("shan", "diamond", 3)
	var yaota: SkillDefinition = _install_single_skill(0, "yaota")
	if yaota == null or yaota.is_joy_skill():
		return _fail("yaota_static")
	_trigger_turn_before(yaota, 0, 1)
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(request.get("choice_type", "")) != "card_target" or str((request.get("context", {}) as Dictionary).get("kind", "")) != "yaota_cost_target":
		return _fail("yaota_request %s" % [request])
	# 目标当前可执行的欢愉技；咬它的分流完全依赖该查询，必须先确认查询本身可用。
	var target_joy_skill_ids: Array[String] = _controller.get_joy_skill_ids(2)
	if target_joy_skill_ids != ["haoxi"]:
		return _fail("yaota_target_joy_ids %s" % [target_joy_skill_ids])
	if not _submit_pending_choice(0, [cost.uid], [2], true):
		return false
	# 费用已进入弃牌堆，且目标的好戏被强制驱动并创建了自己的目标窗口。
	var haoxi_request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if not _controller.state.discard_pile.has(cost) or str((haoxi_request.get("context", {}) as Dictionary).get("kind", "")) != "haoxi_targets":
		return _fail("yaota_joy_dispatch request=%s discarded=%s standalone=%s independent=%s enabled=%s active=%s game_over=%s joy_can=%s" % [haoxi_request, _controller.state.discard_pile.has(cost), _controller.ahha_moment_system.is_standalone_performance(), _controller._active_independent_play_phase, _controller.ahha_moment_system._enabled, _controller.ahha_moment_system.is_active(), _controller.state.game_over, _controller.get_skill_instance(2, "haoxi").can_perform_joy_skill()])
	# 好戏不选目标直接确定；对方获得两张基本牌，整条演出链路完整收尾。
	if not _submit_pending_choice(2, [], [], true):
		return false
	if _controller.state.get_player(2).hand.size() != 2 or _controller.has_pending_card_choice():
		return _fail("yaota_joy_complete hand=%d pending=%s" % [_controller.state.get_player(2).hand.size(), _controller.has_pending_card_choice()])
	# 黑桃额度已消耗；同花色不再产生候选，因此不会再创建询问。
	var same_suit: CardInstance = _add_hand_card(0, "shan", "spade", 3)
	_trigger_turn_before(yaota, 0, 2)
	if not _controller._pending_card_choice.is_empty() or not _controller.state.get_player(0).hand.has(same_suit):
		return _fail("yaota_suit_quota pending=%s" % [_controller._pending_card_choice])
	# 其他花色仍可发动；候选只包含尚未消耗的花色。
	var other_suit: CardInstance = _add_hand_card(0, "tao", "heart", 4)
	_trigger_turn_before(yaota, 0, 3)
	var second_request: Dictionary = _controller._pending_card_choice.duplicate(true)
	var second_candidate_uids: Array[int] = []
	for candidate_variant: Variant in second_request.get("candidates", []) as Array:
		second_candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	if str((second_request.get("context", {}) as Dictionary).get("kind", "")) != "yaota_cost_target" or not second_candidate_uids.has(other_suit.uid) or second_candidate_uids.has(same_suit.uid):
		return _fail("yaota_other_suit %s" % [second_request])
	return true


## 校验【咬它】按参演编号顺序依次发动目标的全部欢愉技，而不是只发动排序第一项。
func _test_yaota_drives_all_owned_joy_skills() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "xing_huanyv"
	# 目标同时持有【好活】与【当赏】；两者参演编号同为120、座次也相同，因此按技能稳定ID字典序依次演出。
	var cost: CardInstance = _add_hand_card(0, "sha", "spade", 9)
	var haohuo: SkillDefinition = _install_single_skill(2, "haohuo")
	var dangshang: SkillDefinition = _install_single_skill(2, "dangshang")
	if haohuo == null or dangshang == null or not haohuo.is_joy_skill() or not dangshang.is_joy_skill():
		return _fail("yaota_all_owned_static")
	# 查询口径；两个参演编号相同的欢愉技都必须出现在可执行列表里。
	var target_joy_skill_ids: Array[String] = _controller.get_joy_skill_ids(2)
	if target_joy_skill_ids != ["dangshang", "haohuo"]:
		return _fail("yaota_all_owned_ids %s" % [target_joy_skill_ids])
	# 【好活】需要一张可弃置的场上牌，【当赏】需要摸牌堆至少有一张牌。
	_add_equipment_card(1, "weapon", "qinggang")
	_add_draw_pile_card("shan", "heart", 2)
	var yaota: SkillDefinition = _install_single_skill(0, "yaota")
	_trigger_turn_before(yaota, 0, 1)
	if not _submit_pending_choice(0, [cost.uid], [2], true):
		return false
	# 首个演出项；参演编号相同时按技能稳定ID字典序，"dangshang" 先于 "haohuo"。
	var first_request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((first_request.get("context", {}) as Dictionary).get("kind", "")) != "dangshang_target":
		return _fail("yaota_all_owned_first %s" % [first_request])
	if not _submit_pending_choice(2, [], [1], true):
		return false
	# 第二项必须紧接着演出；若仍只驱动首项，这里不会有任何待响应选择。
	var second_request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((second_request.get("context", {}) as Dictionary).get("kind", "")) != "haohuo_card":
		return _fail("yaota_all_owned_second %s" % [second_request])
	# 场上候选；本用例只有玩家1武器区的一张装备牌，直接取首项提交。
	var equipment_uid: int = int(((second_request.get("candidates", []) as Array)[0] as Dictionary).get("uid", -1))
	if equipment_uid < 0 or not _submit_pending_choice(2, [equipment_uid], [], true):
		return false
	# 两项演出全部结束；咬它不推进回合开始游标，因此不会残留待响应选择或活动演出。
	if _controller.has_pending_card_choice() or _controller.ahha_moment_system.is_active():
		return _fail("yaota_all_owned_complete pending=%s active=%s" % [_controller._pending_card_choice, _controller.ahha_moment_system.is_active()])
	if _controller.state.get_player(1).equipment.has("weapon"):
		return _fail("yaota_all_owned_discard")
	return true


## 校验【咬它】对没有可执行欢愉技的目标改为给予一个额外的出牌阶段。
func _test_yaota_falls_back_to_extra_play_phase() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "qiong_huanyv"
	# 目标没有任何欢愉技；咬它必须走额外出牌阶段分支。
	var cost: CardInstance = _add_hand_card(0, "sha", "club", 7)
	var yaota: SkillDefinition = _install_single_skill(0, "yaota")
	if yaota == null:
		return _fail("yaota_missing")
	_trigger_turn_before(yaota, 0, 1)
	if not _submit_pending_choice(0, [cost.uid], [2], true):
		return false
	# 额外出牌阶段已经建立；阶段角色切换为受益人且阶段为出牌阶段。
	if int(_controller._active_independent_play_phase.get("player_id", -1)) != 2 or _controller.state.current_player_id != 2 or _controller.state.current_phase != "play":
		return _fail("yaota_extra_phase phase=%s player=%d context=%s" % [_controller.state.current_phase, _controller.state.current_player_id, _controller._active_independent_play_phase])
	return true


## 校验【鸿运】在持有者回合开始前触发一次额外阿哈时刻，并在演出结束后支付体力上限代价。
func _test_hongyun_extra_moment() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "yaoguang"
	# 场上存在可执行的欢愉技；这是鸿运开放询问的前置条件之一。
	_install_single_skill(1, "haoxi")
	# 好戏只把“持有手牌的其他角色”当作合法目标；没有候选时它会立即收尾而不打开窗口。
	_add_hand_card(0, "sha", "spade", 5)
	_add_draw_pile_card("shan", "heart", 2)
	_add_draw_pile_card("tao", "diamond", 4)
	var hongyun: SkillDefinition = _install_single_skill(0, "hongyun")
	if hongyun == null or hongyun.is_joy_skill():
		return _fail("hongyun_static")
	_trigger_turn_before(hongyun, 0, 1)
	var request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(request.get("choice_type", "")) != "card" or str((request.get("context", {}) as Dictionary).get("kind", "")) != "hongyun_confirm" or not bool(request.get("allow_cancel", false)):
		return _fail("hongyun_request %s" % [request])
	# 确认发动；额外阿哈时刻立即开始演出，场上唯一的欢愉技【好戏】先创建自己的目标窗口。
	if not _submit_pending_choice(0, [], [], true):
		return false
	var haoxi_request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str((haoxi_request.get("context", {}) as Dictionary).get("kind", "")) != "haoxi_targets":
		return _fail("hongyun_extra_moment_start %s" % [haoxi_request])
	# 演出结束前不支付代价；确认好戏结算后才减少体力上限。
	if _controller.state.get_player(0).max_hp != 4:
		return _fail("hongyun_cost_too_early max_hp=%d" % _controller.state.get_player(0).max_hp)
	if not _submit_pending_choice(1, [], [], true):
		return false
	if _controller.state.get_player(0).max_hp != 3 or _controller.has_pending_card_choice():
		return _fail("hongyun_cost_after max_hp=%d pending=%s" % [_controller.state.get_player(0).max_hp, _controller.has_pending_card_choice()])
	# 每轮限一次；同轮再次进入回合开始前不再创建询问。
	_trigger_turn_before(hongyun, 0, 1)
	if not _controller._pending_card_choice.is_empty():
		return _fail("hongyun_round_limit pending=%s" % [_controller._pending_card_choice])
	# 额外演出不占用本轮常规阿哈时刻额度：演出结束后常规触发入口仍然可用，并且能真正触发一次。
	if _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("hongyun_extra_moment_consumed_quota")
	_controller.ahha_moment_system._tracked_round_number = _controller.state.round_number
	_controller.ahha_moment_system._round_trigger_probability = 1.0
	if not _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":false}, false):
		return _fail("hongyun_extra_moment_blocked_regular")
	if not _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("hongyun_regular_not_claimed")
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("HUANYU_YAOGUANG_XING_QIONG_FAIL %s" % message)
	get_tree().quit(1)
	return false
