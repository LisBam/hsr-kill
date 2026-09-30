extends Node

## 【真珠】与星际和平公司专项回归测试：校验势力元数据、武将定义、两项技能的静态正文，
## 以及【补缀】在持有者下一个回合结束时的扣盾链路与【鉴映】连花色、点数一起视为的完整选择链路。

## 【补缀】玩家可见正文；与需求原文逐字一致，任何标点或顺序变化都会被本测试拒绝。
const BUZHUI_DESCRIPTION: String = "欢愉技，参演编号104，指定至多三名角色，这些角色各获得1点护盾。你的下一个回合结束时，这些角色各失去1点护盾。"

## 【鉴映】玩家可见正文；与需求原文逐字一致。
const JIANYING_DESCRIPTION: String = "出牌阶段限一次，你可以展示你的一张手牌A，然后展示一名有护盾的角色的一张手牌B，若B不为装备牌，则A视为B直到离开你的手牌区。"

## 【补缀】阿哈时刻参演编号；与技能源码常量共用同一需求数值。
const BUZHUI_PERFORMANCE_NUMBER: int = 104

## 【补缀】单次演出可获得护盾的最大角色数；用于构造三名目标场景。
const BUZHUI_MAX_TARGET_COUNT: int = 3

## 轮末扣盾记录上限断言使用的目标数；一次演出最多登记三名角色。
const BUZHUI_RECORD_TARGET_COUNT: int = 3

## 视为牌名断言的稳定卡牌ID；【桃】数值高，便于验证点数也被复制。
const JIANYING_VIEW_AS_DEFINITION_ID: String = "tao"

## 视为牌面断言的花色；红桃与黑桃颜色相反，可同时验证颜色聚合。
const JIANYING_VIEW_AS_SUIT: String = "heart"

## 视为牌面断言的点数。
const JIANYING_VIEW_AS_RANK: int = 12

## 材料牌原始牌名；视为建立后必须在离开手牌区时恢复。
const JIANYING_MATERIAL_DEFINITION_ID: String = "shan"

## 材料牌原始花色。
const JIANYING_MATERIAL_SUIT: String = "spade"

## 材料牌原始点数。
const JIANYING_MATERIAL_RANK: int = 2

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 本轮 roundEnd 时机的实际派发次数；用于验证普通轮末恰好一次、额外回合不派发。
var _round_end_dispatch_count: int = 0

## 最近一次 roundEnd 事件的数据副本；用于验证结束轮数与结束回合角色。
var _last_round_end_data: Dictionary = {}

## 是否在 roundEnd 回调中创建一个真实选择；用于验证轮末序列会暂停等待选择结算。
var _round_end_should_pause: bool = false

## roundEnd 回调创建的选择是否成功登记；回调内不能直接判定失败，否则会被后续断言覆盖退出码。
var _round_end_pause_request_created: bool = false


## 延迟一帧执行全部断言，确保 GameDatabase 已完成新势力、武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行断言；任一场景失败都立即停止并以非0结束。
func _run() -> void:
	_create_controller()
	if not _test_faction_and_character_metadata():
		return
	if not _test_buzhui_static_definition():
		return
	if not _test_jianying_static_definition():
		return
	if not _test_buzhui_grants_and_expires_shields():
		return
	if not _test_buzhui_zero_targets_is_legal():
		return
	if not _test_jianying_view_as_copies_face_and_restores():
		return
	if not _test_jianying_equipment_card_skips_view_as():
		return
	if not _test_jianying_cancel_and_phase_reset():
		return
	if not _test_ai_scoring_directions():
		return
	if not _test_jianying_ai_self_upgrade_condition():
		return
	if not _test_round_end_timing_boundary():
		return
	print("ZHENZHU_MECHANICS_PASS faction=xingjihepinggongsi hp=3 buzhui=104 jianying=face_view_as turn_end_expiry=owner_next_turn")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器并装配必需子节点；不加载界面，保持规则断言隔离。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；伤害、技能时机与选择恢复共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保留正式节点供身份观察与AI评分路径使用。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；动作提交与正式单机模式保持相同来源语义。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	# 关闭流程节奏：本测试只做同步规则断言，不验证表现延时。
	_controller.game_flow_interval_seconds = 0.0
	_controller.ai_action_delay_seconds = 0.0


## 为当前单项测试创建最小权威状态；一号领袖、二号反贼、三号及以后忠臣使AI态度确定。
func _reset_state(player_count: int, current_phase: String = "play") -> void:
	# 专项场景隔离：取消上一场景残留的流程延时与出牌请求标记。
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "zhenzhu-mechanics"
	_controller.state.round_number = 1
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = current_phase
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "真珠测试玩家%d" % (player_id + 1))
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


## 向指定玩家手牌区加入一张实体牌；测试需要绕过摸牌流程构造确定手牌。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
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
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool) -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；目标、实体牌与确认状态均显式填写。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":"", "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s pending=%s" % [actor_id, request_id, action.payload, _controller._pending_card_choice])
	return true


## 返回当前待处理选择的请求种类；没有待处理选择时返回空字符串。
func _pending_context_kind() -> String:
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))


## 校验势力元数据与真珠武将定义；势力配色、简称、性别、体力与技能顺序必须逐项稳定。
func _test_faction_and_character_metadata() -> bool:
	# 星际和平公司势力元数据；需求指定铜色，展示名与简称逐字锁定。
	var faction: Dictionary = GameDatabase.get_faction("xingjihepinggongsi")
	if str(faction.get("display_name", "")) != "星际和平公司" or str(faction.get("short_name", "")) != "司" or str(faction.get("color", "")) != "b87333":
		return _fail("faction_metadata %s" % [faction])
	# 真珠武将定义；女性、3点基础体力、两项技能按声明顺序登记。
	var zhenzhu: Dictionary = GameDatabase.get_character("zhenzhu")
	if str(zhenzhu.get("display_name", "")) != "真珠" or str(zhenzhu.get("gender", "")) != "female" or str(zhenzhu.get("faction", "")) != "xingjihepinggongsi" or int(zhenzhu.get("max_hp", 0)) != 3:
		return _fail("zhenzhu_metadata %s" % [zhenzhu])
	if (zhenzhu.get("skills", []) as Array) != ["buzhui", "jianying"]:
		return _fail("zhenzhu_skills %s" % [zhenzhu.get("skills", [])])
	# 内容层静态校验；新势力、武将与技能不得留下任何校验错误。
	if not GameDatabase.validation_errors.is_empty():
		return _fail("validation_errors %s" % [GameDatabase.validation_errors])
	return true


## 校验【补缀】的静态定义：欢愉技标签、参演编号与玩家可见正文。
func _test_buzhui_static_definition() -> bool:
	# 补缀运行时实例；只读取静态参数，不绑定对局。
	var buzhui: SkillDefinition = GameDatabase.create_skill("buzhui")
	if buzhui == null:
		return _fail("buzhui_missing")
	if not buzhui.is_joy_skill() or buzhui.get_performance_number() != BUZHUI_PERFORMANCE_NUMBER:
		return _fail("buzhui_joy_params joy=%s number=%d" % [str(buzhui.is_joy_skill()), buzhui.get_performance_number()])
	# 玩家可见正文；必须与需求原文逐字一致，且类型段声明与 joy_skill 标签一致。
	var description: String = str(GameDatabase.get_skill("buzhui").get("description", ""))
	if description != BUZHUI_DESCRIPTION:
		return _fail("buzhui_description %s" % description)
	if not SkillDefinition.description_declares_joy_type(description):
		return _fail("buzhui_description_type")
	return true


## 校验【鉴映】的静态定义：出牌阶段主动技能、非欢愉技、玩家可见正文与限一次标签。
func _test_jianying_static_definition() -> bool:
	# 鉴映运行时实例；只读取静态参数。
	var jianying: SkillDefinition = GameDatabase.create_skill("jianying")
	if jianying == null:
		return _fail("jianying_missing")
	if jianying.is_joy_skill() or jianying.get_performance_number() != 0:
		return _fail("jianying_joy_params joy=%s number=%d" % [str(jianying.is_joy_skill()), jianying.get_performance_number()])
	if not jianying.get_active_entries().has("phaseUse"):
		return _fail("jianying_active_entries %s" % [jianying.get_active_entries()])
	# 玩家可见正文；必须与需求原文逐字一致。
	var description: String = str(GameDatabase.get_skill("jianying").get("description", ""))
	if description != JIANYING_DESCRIPTION:
		return _fail("jianying_description %s" % description)
	if not jianying.declares_description_tag(SkillDefinition.PLAY_PHASE_ONCE_TAG):
		return _fail("jianying_play_phase_once_tag")
	return true


## 校验【补缀】完整链路：选择0至3名角色、各得1点护盾、同一回合可多次演出，
## 护盾只在持有者的下一个回合尾各失去对应点数，同一回合尾与其他人回合尾都不会让它提前到期。
func _test_buzhui_grants_and_expires_shields() -> bool:
	_reset_state(4)
	_controller.state.get_player(0).character_id = "zhenzhu"
	# 补缀运行时实例；直接演出以便在同步测试中精确控制目标。
	var buzhui: SkillDefinition = _install_single_skill(0, "buzhui")
	if buzhui == null:
		return _fail("buzhui_missing")
	if not buzhui.can_perform_joy_skill():
		return _fail("buzhui_can_perform")
	# 第一次演出：指定三名角色，全部可获得护盾。
	buzhui.perform_joy_skill({"target_ids":[0, 1, 2]})
	for target_id: int in [0, 1, 2]:
		if _controller.state.get_player(target_id).shield != 1:
			return _fail("buzhui_first_grant target=%d shield=%d" % [target_id, _controller.state.get_player(target_id).shield])
	if _controller.state.get_player(3).shield != 0:
		return _fail("buzhui_untargeted_shield=%d" % _controller.state.get_player(3).shield)
	# 第二次演出：同一回合内重复指定两名角色，护盾叠加，到期时必须逐条扣减。
	buzhui.perform_joy_skill({"target_ids":[0, 1]})
	if _controller.state.get_player(0).shield != 2 or _controller.state.get_player(1).shield != 2 or _controller.state.get_player(2).shield != 1:
		return _fail("buzhui_second_grant %d/%d/%d" % [_controller.state.get_player(0).shield, _controller.state.get_player(1).shield, _controller.state.get_player(2).shield])
	# 尚未到期的护盾记录；两条演出记录都必须在到期消费前保留。
	var records: Array = buzhui.get("_shield_expiry_records") as Array
	if records.size() != 2 or (records[0].get("target_ids", []) as Array).size() != BUZHUI_RECORD_TARGET_COUNT:
		return _fail("buzhui_records %s" % [records])
	# 演出发生在持有者自己的这个回合内，因此本回合的回合尾不是“你的下一个回合”，护盾必须保留。
	_emit_owner_turn_end(0, _controller.state.turn_number)
	if _controller.state.get_player(0).shield != 2 or _controller.state.get_player(1).shield != 2 or _controller.state.get_player(2).shield != 1:
		return _fail("buzhui_same_turn_expiry %d/%d/%d" % [_controller.state.get_player(0).shield, _controller.state.get_player(1).shield, _controller.state.get_player(2).shield])
	# 其他角色的回合尾：护盾绑定“你的下一个回合”，不得被别人的回合尾提前扣掉。
	_controller.state.turn_number += 1
	_emit_owner_turn_end(1, _controller.state.turn_number)
	if _controller.state.get_player(0).shield != 2 or _controller.state.get_player(1).shield != 2 or _controller.state.get_player(2).shield != 1:
		return _fail("buzhui_other_turn_expiry %d/%d/%d" % [_controller.state.get_player(0).shield, _controller.state.get_player(1).shield, _controller.state.get_player(2).shield])
	# 三号位在到期前死亡；已死亡角色不再接受护盾扣减，也不应影响其他目标结算。
	_controller.state.get_player(2).alive = false
	# 持有者的下一个回合尾：回合序号大于登记值，两条记录逐条各扣1点护盾。
	_controller.state.turn_number += 1
	_emit_owner_turn_end(0, _controller.state.turn_number)
	if _controller.state.get_player(0).shield != 0 or _controller.state.get_player(1).shield != 0:
		return _fail("buzhui_next_turn_end_lose %d/%d" % [_controller.state.get_player(0).shield, _controller.state.get_player(1).shield])
	if _controller.state.get_player(2).shield != 1:
		return _fail("buzhui_dead_target_skipped=%d" % _controller.state.get_player(2).shield)
	# 记录已被消费；同一个回合尾再次派发也不会二次扣盾。
	if not (buzhui.get("_shield_expiry_records") as Array).is_empty():
		return _fail("buzhui_records_not_consumed %s" % [buzhui.get("_shield_expiry_records")])
	_emit_owner_turn_end(0, _controller.state.turn_number)
	if _controller.state.get_player(0).shield != 0:
		return _fail("buzhui_double_settlement")
	# 技能持有者阵亡后不会再有“你的下一个回合”，已发放的护盾按原文保留、不再到期。
	_reset_state(3)
	_controller.state.get_player(0).character_id = "zhenzhu"
	buzhui = _install_single_skill(0, "buzhui")
	if buzhui == null:
		return _fail("buzhui_missing_reinstall")
	buzhui.perform_joy_skill({"target_ids":[1]})
	_controller.state.get_player(0).alive = false
	_controller.state.turn_number += 2
	_emit_owner_turn_end(0, _controller.state.turn_number)
	if _controller.state.get_player(1).shield != 1:
		return _fail("buzhui_owner_dead_keeps_shield=%d" % _controller.state.get_player(1).shield)
	# 记录同样保留：死亡持有者不会再有回合尾，因此这条记录永远不会被消费。
	if (buzhui.get("_shield_expiry_records") as Array).size() != 1:
		return _fail("buzhui_owner_dead_records %s" % [buzhui.get("_shield_expiry_records")])
	# 真实回合尾入口：控制器在持有者本人回合尾派发 phaseAfter 并携带当前回合序号，技能据此扣盾，
	# 而不是只在测试手工派发的时机上成立。
	_reset_state(3, "finish")
	_controller.state.get_player(0).character_id = "zhenzhu"
	buzhui = _install_single_skill(0, "buzhui")
	if buzhui == null:
		return _fail("buzhui_missing_real_turn_end")
	buzhui.perform_joy_skill({"target_ids":[1]})
	# 持有者的下一个回合：权威回合序号前进后，由真实回合尾入口结束该回合。
	_controller.state.turn_number += 1
	_controller.state.current_player_id = 0
	_controller._complete_finish_turn(0)
	if _controller.state.get_player(1).shield != 0:
		return _fail("buzhui_real_turn_end_expiry=%d" % _controller.state.get_player(1).shield)
	if not (buzhui.get("_shield_expiry_records") as Array).is_empty():
		return _fail("buzhui_real_turn_end_records %s" % [buzhui.get("_shield_expiry_records")])
	# 收尾：更换对局ID使刚刚安排的回合切换失效，避免测试退出前在最小状态上开始真实回合。
	_controller.state.match_id = "zhenzhu-mechanics-closed"
	return true


## 派发一次指定角色的标准回合尾时机；护盾到期只依赖持有者本人的 phaseAfter（role="player"）。
## 回合序号显式传入，使“同一个回合”与“下一个回合”的边界不依赖测试状态的自增顺序。
func _emit_owner_turn_end(player_id: int, turn_number: int) -> void:
	_controller._emit_rule_timing("phaseAfter", player_id, -1, player_id, {"player_id":player_id, "phase":"finish", "turn_number":turn_number})


## 校验【补缀】目标窗口契约：不可取消、下限0上限3，选择0名角色是合法结算且不产生任何记录。
func _test_buzhui_zero_targets_is_legal() -> bool:
	_reset_state(5)
	_controller.state.get_player(0).character_id = "zhenzhu"
	var buzhui: SkillDefinition = _install_single_skill(0, "buzhui")
	if buzhui == null:
		return _fail("buzhui_missing")
	buzhui.perform_joy_skill({})
	if str(_controller._pending_card_choice.get("choice_type", "")) != "target" or _pending_context_kind() != "buzhui_targets":
		return _fail("buzhui_target_request %s" % [_controller._pending_card_choice])
	if bool(_controller._pending_card_choice.get("allow_cancel", true)) or int(_controller._pending_card_choice.get("min_target_select", -1)) != 0 or int(_controller._pending_card_choice.get("max_target_select", -1)) != BUZHUI_MAX_TARGET_COUNT:
		return _fail("buzhui_target_window cancel=%s min=%s max=%s" % [str(_controller._pending_card_choice.get("allow_cancel", true)), str(_controller._pending_card_choice.get("min_target_select", -1)), str(_controller._pending_card_choice.get("max_target_select", -1))])
	if (_controller._pending_card_choice.get("target_ids", []) as Array).size() != 5:
		return _fail("buzhui_target_candidates %s" % [_controller._pending_card_choice.get("target_ids", [])])
	if not _submit_pending_choice(0, [], [], true):
		return false
	for player: PlayerState in _controller.state.players:
		if player.shield != 0:
			return _fail("buzhui_zero_target_shield player=%d shield=%d" % [player.player_id, player.shield])
	if not (buzhui.get("_shield_expiry_records") as Array).is_empty():
		return _fail("buzhui_zero_target_records %s" % [buzhui.get("_shield_expiry_records")])
	# 演出必须已经结束：没有残留请求，且可以立即开始下一次演出。
	if not _controller._pending_card_choice.is_empty():
		return _fail("buzhui_zero_target_pending %s" % [_controller._pending_card_choice])
	return true


## 校验【鉴映】核心链路：三段选择严格按序、B连花色点数一起视为、离开手牌区后恢复物理牌面。
func _test_jianying_view_as_copies_face_and_restores() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "zhenzhu"
	# 材料牌A；黑桃2，点数与花色都与B不同，便于逐项验证复制结果。
	var material_card: CardInstance = _add_hand_card(0, JIANYING_MATERIAL_DEFINITION_ID, JIANYING_MATERIAL_SUIT, JIANYING_MATERIAL_RANK)
	# B实体；红桃12，视为后颜色应由黑变红。
	var revealed_card: CardInstance = _add_hand_card(1, JIANYING_VIEW_AS_DEFINITION_ID, JIANYING_VIEW_AS_SUIT, JIANYING_VIEW_AS_RANK)
	# 双方各1点护盾；真珠有护盾、目标有护盾是技能的两项前置条件。
	_controller.change_hujia(0, 1, -1, "test")
	_controller.change_hujia(1, 1, -1, "test")
	var jianying: SkillDefinition = _install_single_skill(0, "jianying")
	if jianying == null or not jianying.can_activate():
		return _fail("jianying_can_activate")
	if not str(jianying.activate()).is_empty():
		return _fail("jianying_activate_rejected")
	# 第一步：展示自己的手牌A；此时尚未展示任何目标手牌。
	if _pending_context_kind() != "jianying_material" or not bool(_controller._pending_card_choice.get("allow_cancel", false)):
		return _fail("jianying_material_request %s" % [_controller._pending_card_choice])
	if revealed_card.shown:
		return _fail("jianying_b_shown_too_early")
	if not _submit_pending_choice(0, [material_card.uid], [], true):
		return false
	# A 必须在选择B来源之前公开，且此后不再提供取消。
	if not material_card.shown:
		return _fail("jianying_material_not_shown")
	if _pending_context_kind() != "jianying_shield_target" or bool(_controller._pending_card_choice.get("allow_cancel", true)):
		return _fail("jianying_target_request %s" % [_controller._pending_card_choice])
	if (_controller._pending_card_choice.get("target_ids", []) as Array) != [0, 1]:
		return _fail("jianying_target_candidates %s" % [_controller._pending_card_choice.get("target_ids", [])])
	if not _submit_pending_choice(0, [], [1], true):
		return false
	# 第三步：由真珠从目标手牌中选B；他人手牌只下发不可见候选，且B仍未展示。
	if _pending_context_kind() != "jianying_revealed_card":
		return _fail("jianying_revealed_request %s" % [_controller._pending_card_choice])
	# 目标手牌候选；恰好一张且必须标记为不可见。
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if candidates.size() != 1 or bool((candidates[0] as Dictionary).get("visible", true)):
		return _fail("jianying_revealed_candidates %s" % [candidates])
	if revealed_card.shown:
		return _fail("jianying_b_shown_before_confirm")
	if not _submit_pending_choice(0, [revealed_card.uid], [], true):
		return false
	# 视为结果：牌名、花色与点数全部来自B，颜色随花色改为红色。
	if material_card.definition_id != JIANYING_VIEW_AS_DEFINITION_ID or material_card.suit != JIANYING_VIEW_AS_SUIT or material_card.rank != JIANYING_VIEW_AS_RANK:
		return _fail("jianying_view_as_face %s/%s/%d" % [material_card.definition_id, material_card.suit, material_card.rank])
	if material_card.get_color() != "red" or not material_card.has_hand_view_as():
		return _fail("jianying_view_as_color=%s has_view_as=%s" % [material_card.get_color(), str(material_card.has_hand_view_as())])
	if str(material_card.hand_view_as_original_definition_id) != JIANYING_MATERIAL_DEFINITION_ID or str(material_card.hand_view_as_original_suit) != JIANYING_MATERIAL_SUIT or int(material_card.hand_view_as_original_rank) != JIANYING_MATERIAL_RANK:
		return _fail("jianying_original_face %s/%s/%d" % [material_card.hand_view_as_original_definition_id, material_card.hand_view_as_original_suit, material_card.hand_view_as_original_rank])
	# 虚拟牌材料聚合读取的是实体花色，因此转化牌会继承视为后的花色与颜色。
	var aggregate: Dictionary = VirtualCard.resolve_material_aggregate([material_card])
	if str(aggregate.get("suit", "")) != JIANYING_VIEW_AS_SUIT or str(aggregate.get("color", "")) != "red":
		return _fail("jianying_aggregate %s" % [aggregate])
	# 快照字段；表现层用 view_as_* 显示横幅，用 presentation_original_* 显示物理牌角。
	var snapshot: Dictionary = material_card.to_dict()
	if str(snapshot.get("view_as_suit", "")) != JIANYING_VIEW_AS_SUIT or int(snapshot.get("view_as_rank", 0)) != JIANYING_VIEW_AS_RANK or str(snapshot.get("view_as_definition_id", "")) != JIANYING_VIEW_AS_DEFINITION_ID:
		return _fail("jianying_snapshot_view_as %s" % [snapshot])
	if str(snapshot.get("presentation_original_suit", "")) != JIANYING_MATERIAL_SUIT or int(snapshot.get("presentation_original_rank", 0)) != JIANYING_MATERIAL_RANK:
		return _fail("jianying_snapshot_original %s" % [snapshot])
	# 离开手牌区后必须恢复物理牌面，同时保留“本轮曾视为”的表现信息。
	if not _controller.discard_card_from_hand(0, material_card.uid):
		return _fail("jianying_discard_material")
	if material_card.definition_id != JIANYING_MATERIAL_DEFINITION_ID or material_card.suit != JIANYING_MATERIAL_SUIT or material_card.rank != JIANYING_MATERIAL_RANK or material_card.has_hand_view_as():
		return _fail("jianying_restore %s/%s/%d" % [material_card.definition_id, material_card.suit, material_card.rank])
	var restored_snapshot: Dictionary = material_card.to_dict()
	if str(restored_snapshot.get("view_as_definition_id", "")) != JIANYING_VIEW_AS_DEFINITION_ID or str(restored_snapshot.get("view_as_suit", "")) != JIANYING_VIEW_AS_SUIT or int(restored_snapshot.get("view_as_rank", 0)) != JIANYING_VIEW_AS_RANK:
		return _fail("jianying_restore_presentation %s" % [restored_snapshot])
	return true


## 校验【鉴映】对装备牌B的处理：只展示不建立视为，且本阶段次数仍然消费。
func _test_jianying_equipment_card_skips_view_as() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "zhenzhu"
	var material_card: CardInstance = _add_hand_card(0, JIANYING_MATERIAL_DEFINITION_ID, JIANYING_MATERIAL_SUIT, JIANYING_MATERIAL_RANK)
	# 装备牌B；位于目标手牌中，按原文不能作为视为对象。
	var equipment_card: CardInstance = _add_hand_card(1, "bagua", "club", 2)
	_controller.change_hujia(0, 1, -1, "test")
	_controller.change_hujia(1, 1, -1, "test")
	var jianying: SkillDefinition = _install_single_skill(0, "jianying")
	if jianying == null or not jianying.can_activate():
		return _fail("jianying_equipment_can_activate")
	jianying.activate()
	if not _submit_pending_choice(0, [material_card.uid], [], true):
		return false
	if not _submit_pending_choice(0, [], [1], true):
		return false
	if not _submit_pending_choice(0, [equipment_card.uid], [], true):
		return false
	if equipment_card.shown != true:
		return _fail("jianying_equipment_not_shown")
	if material_card.definition_id != JIANYING_MATERIAL_DEFINITION_ID or material_card.suit != JIANYING_MATERIAL_SUIT or material_card.has_hand_view_as():
		return _fail("jianying_equipment_view_as %s/%s" % [material_card.definition_id, material_card.suit])
	# 装备分支已经完成一次公开展示与目标选择，本阶段次数必须已消费。
	if not bool(jianying.get("_used_this_play_phase")) or jianying.can_activate():
		return _fail("jianying_equipment_usage used=%s" % [str(jianying.get("_used_this_play_phase"))])
	return true


## 校验【鉴映】的取消契约与阶段额度：未确认前取消不消费次数，新出牌阶段重新获得一次。
func _test_jianying_cancel_and_phase_reset() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "zhenzhu"
	var material_card: CardInstance = _add_hand_card(0, JIANYING_MATERIAL_DEFINITION_ID, JIANYING_MATERIAL_SUIT, JIANYING_MATERIAL_RANK)
	_add_hand_card(1, JIANYING_VIEW_AS_DEFINITION_ID, JIANYING_VIEW_AS_SUIT, JIANYING_VIEW_AS_RANK)
	_controller.change_hujia(0, 1, -1, "test")
	_controller.change_hujia(1, 1, -1, "test")
	var jianying: SkillDefinition = _install_single_skill(0, "jianying")
	if jianying == null or not jianying.can_activate():
		return _fail("jianying_cancel_can_activate")
	jianying.activate()
	if not _submit_pending_choice(0, [], [], false):
		return false
	if bool(jianying.get("_used_this_play_phase")) or material_card.shown or not _controller._pending_card_choice.is_empty():
		return _fail("jianying_cancel_consumed used=%s shown=%s" % [str(jianying.get("_used_this_play_phase")), str(material_card.shown)])
	if not jianying.can_activate():
		return _fail("jianying_cancel_blocks_reactivation")
	# 完整发动一次后本阶段次数用尽。
	jianying.activate()
	if not _submit_pending_choice(0, [material_card.uid], [], true):
		return false
	if not _submit_pending_choice(0, [], [1], true):
		return false
	if not _submit_pending_choice(0, [_controller.state.get_player(1).hand[0].uid], [], true):
		return false
	if not bool(jianying.get("_used_this_play_phase")) or jianying.can_activate():
		return _fail("jianying_once_per_phase used=%s" % [str(jianying.get("_used_this_play_phase"))])
	# 新的出牌阶段（含额外出牌阶段）重新获得一次独立额度。
	_controller._emit_rule_timing("phaseUseBegin", 0, 0, 0, {"player_id":0, "phase":"play"})
	if bool(jianying.get("_used_this_play_phase")) or not jianying.can_activate():
		return _fail("jianying_phase_reset used=%s" % [str(jianying.get("_used_this_play_phase"))])
	return true


## 校验两项技能的AI评分方向：补缀偏好友方与残血、拒绝敌方；鉴映偏向自身升级与敌方目标。
func _test_ai_scoring_directions() -> bool:
	# 权威快照；身份全部公开，态度由身份规则直接给出。
	var snapshot: Dictionary = {
		"match_id":"zhenzhu_ai_snapshot",
		"players":[
			{"player_id":0, "identity":"leader", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":3, "max_hp":3, "shield":1, "hand_count":2, "hand":[{"uid":101, "definition_id":"shan", "owner_id":0, "zone":"hand"}, {"uid":102, "definition_id":"tao", "owner_id":0, "zone":"hand"}], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"zhenzhu"},
			{"player_id":1, "identity":"rebel", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "shield":1, "hand_count":1, "hand":[{"uid":201, "definition_id":"shan", "owner_id":1, "zone":"hand"}], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"gepard"},
			{"player_id":2, "identity":"loyalist", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":1, "max_hp":4, "shield":0, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"himeko"},
		],
	}
	# 统一AI估值器；技能评分只依赖快照与估值接口，不访问控制器。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var buzhui: SkillDefinition = GameDatabase.create_skill("buzhui")
	var jianying: SkillDefinition = GameDatabase.create_skill("jianying")
	if buzhui == null or jianying == null:
		return _fail("ai_skill_missing")
	buzhui.bind(null, 0)
	jianying.bind(null, 0)
	# 补缀：残血友方优于满血友方，敌方组合为负，未确认（0名目标）为0。
	var wounded_ally_score: float = buzhui.score_ai_choice(snapshot, {"context":{"kind":"buzhui_targets"}}, {"payload":{"confirmed":true, "selected_target_ids":[2]}}, evaluator)
	var healthy_ally_score: float = buzhui.score_ai_choice(snapshot, {"context":{"kind":"buzhui_targets"}}, {"payload":{"confirmed":true, "selected_target_ids":[0]}}, evaluator)
	var hostile_score: float = buzhui.score_ai_choice(snapshot, {"context":{"kind":"buzhui_targets"}}, {"payload":{"confirmed":true, "selected_target_ids":[1]}}, evaluator)
	if hostile_score >= 0.0:
		return _fail("buzhui_ai_hostile=%f" % hostile_score)
	if wounded_ally_score <= healthy_ally_score:
		return _fail("buzhui_ai_wounded=%f healthy=%f" % [wounded_ally_score, healthy_ally_score])
	# 鉴映：自身目标优于敌方目标，敌方目标优于友方目标；B来源是自己时高价值牌得分更高。
	var self_target_score: float = jianying.score_ai_choice(snapshot, {"context":{"kind":"jianying_shield_target"}}, {"payload":{"confirmed":true, "selected_target_ids":[0]}}, evaluator)
	var hostile_target_score: float = jianying.score_ai_choice(snapshot, {"context":{"kind":"jianying_shield_target"}}, {"payload":{"confirmed":true, "selected_target_ids":[1]}}, evaluator)
	var friendly_target_score: float = jianying.score_ai_choice(snapshot, {"context":{"kind":"jianying_shield_target"}}, {"payload":{"confirmed":true, "selected_target_ids":[2]}}, evaluator)
	if self_target_score <= hostile_target_score or hostile_target_score <= friendly_target_score:
		return _fail("jianying_ai_targets self=%f hostile=%f friendly=%f" % [self_target_score, hostile_target_score, friendly_target_score])
	# 材料段：低价值手牌的评分必须高于高价值手牌。
	var cheap_material_score: float = jianying.score_ai_choice(snapshot, {"candidates":[{"uid":101, "owner_id":0, "zone":"hand", "slot":"", "visible":true, "card_data":{"uid":101, "definition_id":"shan", "owner_id":0, "zone":"hand"}}], "context":{"kind":"jianying_material"}}, {"payload":{"confirmed":true, "selected_card_uids":[101]}}, evaluator)
	var rich_material_score: float = jianying.score_ai_choice(snapshot, {"candidates":[{"uid":102, "owner_id":0, "zone":"hand", "slot":"", "visible":true, "card_data":{"uid":102, "definition_id":"tao", "owner_id":0, "zone":"hand"}}], "context":{"kind":"jianying_material"}}, {"payload":{"confirmed":true, "selected_card_uids":[102]}}, evaluator)
	if cheap_material_score <= rich_material_score:
		return _fail("jianying_ai_material cheap=%f rich=%f" % [cheap_material_score, rich_material_score])
	# 回归：材料段确认分必须为正；为负时AI会判定“取消更优”，
	# 于是一个出牌阶段内反复“发动→取消”，表现为AI回合停滞。
	if cheap_material_score <= 0.0:
		return _fail("jianying_ai_material_nonpositive cheap=%f" % cheap_material_score)
	# 主动发动：自身有护盾且手牌存在价值差时为正分。
	var action_score: float = jianying.score_ai_action(snapshot, {"action_type":"use_skill", "actor_id":0, "skill_id":"jianying"}, evaluator)
	if action_score <= 0.0:
		return _fail("jianying_ai_action=%f" % action_score)
	return true


## 校验【鉴映】AI 的自选条件：只有「自己有护盾且手牌存在明显高低价值差」时才把展示目标放在自己身上。
## 缺少高低价值差时自选只会公开自己的手牌却换不到更高价值的牌，因此必须让位给敌人或队友。
func _test_jianying_ai_self_upgrade_condition() -> bool:
	# 权威快照；自身两张手牌同为【桃】，最高最低价值差为0，不构成升级对。
	var snapshot: Dictionary = {
		"match_id":"jianying_ai_flat_hand",
		"players":[
			{"player_id":0, "identity":"leader", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":3, "max_hp":3, "shield":1, "hand_count":2, "hand":[{"uid":101, "definition_id":"tao", "owner_id":0, "zone":"hand"}, {"uid":102, "definition_id":"tao", "owner_id":0, "zone":"hand"}], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"zhenzhu"},
			{"player_id":1, "identity":"rebel", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "shield":1, "hand_count":1, "hand":[{"uid":201, "definition_id":"shan", "owner_id":1, "zone":"hand"}], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"gepard"},
		],
	}
	# 统一AI估值器；技能评分只依赖快照与估值接口，不访问控制器。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var jianying: SkillDefinition = GameDatabase.create_skill("jianying")
	if jianying == null:
		return _fail("jianying_ai_flat_missing")
	jianying.bind(null, 0)
	var self_score: float = jianying.score_ai_choice(snapshot, {"context":{"kind":"jianying_shield_target"}}, {"payload":{"confirmed":true, "selected_target_ids":[0]}}, evaluator)
	var hostile_score: float = jianying.score_ai_choice(snapshot, {"context":{"kind":"jianying_shield_target"}}, {"payload":{"confirmed":true, "selected_target_ids":[1]}}, evaluator)
	# 自身仍有护盾，但手牌没有价值差；此时对敌发动才是更优选择。
	if self_score >= hostile_score:
		return _fail("jianying_ai_flat_self=%f hostile=%f" % [self_score, hostile_score])
	return true


## 校验真实轮末时机：普通轮末恰好派发一次、先于限时恢复、可被选择暂停；额外回合不派发。
func _test_round_end_timing_boundary() -> bool:
	_reset_state(3, "finish")
	# 轮末选择需要至少一个合法候选实体。
	_add_hand_card(0, JIANYING_MATERIAL_DEFINITION_ID, JIANYING_MATERIAL_SUIT, JIANYING_MATERIAL_RANK)
	# 限时离场的二号位；应在 roundEnd 之后的恢复步骤回到场上。
	var returning_player: PlayerState = _controller.state.get_player(1)
	returning_player.out_of_game = true
	returning_player.out_of_game_until_round = _controller.state.round_number
	_round_end_dispatch_count = 0
	_last_round_end_data.clear()
	_round_end_should_pause = true
	_round_end_pause_request_created = false
	_controller.trigger_manager.subscribe("roundEnd", self, _on_round_end, 100, -1, "global")
	# 三号位正常结束回合且下家轮转回到轮锚点，构成真实普通轮末边界。
	_controller.state.current_player_id = 2
	_controller._continue_after_phase_after(2)
	if _round_end_dispatch_count != 1:
		return _fail("round_end_dispatch_count=%d" % _round_end_dispatch_count)
	if int(_last_round_end_data.get("round_number", -1)) != 1 or int(_last_round_end_data.get("finished_player_id", -1)) != 2:
		return _fail("round_end_event_data %s" % [_last_round_end_data])
	# 处理者创建的选择必须让轮末序列暂停：限时恢复尚未执行。
	if not _round_end_pause_request_created:
		return _fail("round_end_pause_request_missing %s" % [_controller._pending_card_choice])
	if _pending_context_kind() != "zhenzhu_round_end_pause":
		return _fail("round_end_pause_request %s" % [_controller._pending_card_choice])
	if not returning_player.out_of_game:
		return _fail("round_end_restore_before_settlement")
	# 选择结算后序列继续执行，限时离场角色恢复，且 roundEnd 不会再次派发。
	if not _submit_pending_choice(0, [_controller.state.get_player(0).hand[0].uid], [], true):
		return false
	if returning_player.out_of_game:
		return _fail("round_end_restore_after_settlement=%s" % [str(returning_player.out_of_game)])
	if _round_end_dispatch_count != 1:
		return _fail("round_end_duplicate_dispatch=%d" % _round_end_dispatch_count)
	# 额外回合落在同一轮末边界上时不得派发 roundEnd。
	_round_end_dispatch_count = 0
	_controller.state.current_player_id = 2
	_controller.state.current_phase = "finish"
	_controller._current_turn_is_extra = true
	_controller._continue_after_phase_after(2)
	_controller._current_turn_is_extra = false
	if _round_end_dispatch_count != 0:
		return _fail("round_end_extra_turn_dispatch=%d" % _round_end_dispatch_count)
	# 收尾：更换对局ID使上面已经登记的阶段切换失效，避免测试退出前在最小状态上开始真实回合。
	_controller.state.match_id = "zhenzhu-mechanics-closed"
	return true


## 记录一次 roundEnd 派发；暂停模式下载荷中创建一个真实选择以验证轮末序列等待选择结算。
## 本回调运行在时机派发栈内，因此只记录结果，不在这里判定失败：回调内的退出码会被主流程后续断言覆盖。
func _on_round_end(event: RuleEvent) -> void:
	_round_end_dispatch_count += 1
	_last_round_end_data = (event.data as Dictionary).duplicate(true)
	if not _round_end_should_pause:
		return
	_round_end_should_pause = false
	# 交互式选择请求会立即返回空数组（等待真人提交），因此以请求表内容判断登记是否成功。
	_controller.request_card_choice(0, "轮末测试", "请选择一张手牌", _controller.get_hand_candidates(0, 0), 1, 1, false, {"kind":"zhenzhu_round_end_pause"})
	_round_end_pause_request_created = _pending_context_kind() == "zhenzhu_round_end_pause"


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("ZHENZHU_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
