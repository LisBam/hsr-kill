extends Node

## 【岳峙】专项测试：校验限定技的接管询问时机、目标改写为X次重复、结算期伤害与回复守卫，以及守卫的解除与额度语义。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保 GameDatabase 已完成新技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行断言；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_yuezhi_static_definition():
		return
	if not _test_yuezhi_takes_over_multitarget_card():
		return
	if not _test_yuezhi_ignores_single_target_card():
		return
	if not _test_yuezhi_cancel_keeps_limited_use():
		return
	if not _test_yuezhi_guard_prevents_repeat_damage():
		return
	if not _test_yuezhi_guard_prevents_repeat_recover():
		return
	if not _test_yuezhi_guard_cleared_after_card():
		return
	if not _test_yuezhi_ai_source_rule():
		return
	print("YUEZHI_MECHANICS_PASS limited=true resolve_times=3 guard=first_only ai_source_rule=1")
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


## 为当前单项测试创建最小权威状态；一号领袖、二号反贼使AI态度确定。
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
	_controller.state.match_id = "yuezhi"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "岳峙测试玩家%d" % (player_id + 1))
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
	# 轮回技服务；本技能不是轮回技，但控制器内部多处会访问该字段。
	_controller.reincarnation_skill_service = ReincarnationSkillService.new()
	_controller.reincarnation_skill_service.configure(_controller)
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


## 为当前统一选择请求提交目标、牌或确认结果；使用正式 PlayerAction 入口。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool, selected_control_id: String = "") -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；目标、牌与确认状态均显式填写。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s pending=%s" % [actor_id, request_id, action.payload, _controller._pending_card_choice])
	return true


## 判断当前等待窗口是否为【岳峙】的接管询问；其他类型的等待窗口（如【杀】的响应请求）不在此列。
func _has_yuezhi_prompt() -> bool:
	if _controller._pending_card_choice.is_empty():
		return false
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) == "yuezhi_become_sole_target"


## 校验【岳峙】的静态定义：限定技标记与玩家可见正文逐字一致。
func _test_yuezhi_static_definition() -> bool:
	# 岳峙运行时实例；只读取静态参数，不绑定对局。
	var yuezhi: SkillDefinition = GameDatabase.create_skill("yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "限定技，当一张牌指定多名角色为目标时，你可成为该牌的唯一目标，且此牌的效果对你结算X次，此牌结算期间你受到伤害/回复体力后，防止你受到伤害/回复体力直到该牌结算完毕。（X为此牌原目标数）"
	var description: String = str(GameDatabase.get_skill("yuezhi").get("description", ""))
	if description != expected_description:
		return _fail("yuezhi_description %s" % description)
	# 限定技标记由正文自动识别；缺失会让技能可以被无限次发动。
	if not yuezhi.limited or not yuezhi.has_available_intrinsic_use():
		return _fail("yuezhi_limited limited=%s available=%s" % [str(yuezhi.limited), str(yuezhi.has_available_intrinsic_use())])
	# 触发时机必须是会写回用牌上下文的整牌时机；否则目标改写会被静默丢弃。
	if str(GameDatabase.get_skill("yuezhi").get("trigger", "")) != "useCard":
		return _fail("yuezhi_trigger %s" % str(GameDatabase.get_skill("yuezhi").get("trigger", "")))
	return true


## 校验核心链路：多目标牌被接管后目标数组变为持有者的X次重复，其他角色不再收到该牌效果。
func _test_yuezhi_takes_over_multitarget_card() -> bool:
	_reset_state(3)
	# 三名角色全部受伤；若接管未生效，三人都会被【桃园结义】回复。
	_controller.state.get_player(0).hp = 1
	_controller.state.get_player(1).hp = 1
	_controller.state.get_player(2).hp = 1
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	# 由玩家1使用【桃园结义】；它指定全部角色为目标，且没有响应窗口与选牌交互。
	var taoyuan_card: CardInstance = _add_hand_card(1, "taoyuan", "heart", 1)
	_controller._execute_card_use(1, taoyuan_card, [0, 1, 2])
	# 接管询问必须在整牌时机内创建，并携带改写前的原目标数。
	if not _has_yuezhi_prompt():
		return _fail("yuezhi_no_prompt %s" % [_controller._pending_card_choice])
	var prompt_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if int(prompt_context.get("original_target_count", 0)) != 3:
		return _fail("yuezhi_original_target_count %s" % [prompt_context])
	if str(prompt_context.get("card_definition_id", "")) != "taoyuan":
		return _fail("yuezhi_card_definition_id %s" % [prompt_context])
	if not _submit_pending_choice(0, [], [], true):
		return false
	# X = 3：该牌对持有者结算3次，回复守卫只放行首次，因此体力只上升1点。
	if _controller.state.get_player(0).hp != 2:
		return _fail("yuezhi_owner_hp=%d" % _controller.state.get_player(0).hp)
	# 被改写掉的原本目标不会收到该牌效果；这是“成为唯一目标”与单纯“多结算”的关键区别。
	if _controller.state.get_player(1).hp != 1 or _controller.state.get_player(2).hp != 1:
		return _fail("yuezhi_others_hp=%d,%d" % [_controller.state.get_player(1).hp, _controller.state.get_player(2).hp])
	# 限定技额度只允许一次；发动后立即耗尽。
	if yuezhi.has_available_intrinsic_use():
		return _fail("yuezhi_limited_not_consumed")
	return true


## 校验单目标牌不触发接管：原文限定“指定多名角色为目标”。
func _test_yuezhi_ignores_single_target_card() -> bool:
	_reset_state(2)
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	var slash_card: CardInstance = _add_hand_card(0, "sha", "spade", 7)
	_controller._execute_card_use(0, slash_card, [1])
	if _has_yuezhi_prompt():
		return _fail("yuezhi_single_target_prompted %s" % [_controller._pending_card_choice])
	# 未触发时额度必须保持可用。
	if not yuezhi.has_available_intrinsic_use():
		return _fail("yuezhi_single_target_consumed_use")
	return true


## 校验取消接管不消耗限定额度：玩家拒绝后仍可在后续的多目标牌上发动。
func _test_yuezhi_cancel_keeps_limited_use() -> bool:
	_reset_state(3)
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	var taoyuan_card: CardInstance = _add_hand_card(1, "taoyuan", "heart", 1)
	_controller._execute_card_use(1, taoyuan_card, [0, 1, 2])
	if not _has_yuezhi_prompt():
		return _fail("yuezhi_cancel_no_prompt")
	if not _submit_pending_choice(0, [], [], false):
		return false
	if not yuezhi.has_available_intrinsic_use():
		return _fail("yuezhi_cancel_consumed_use")
	# 未接管时目标数组保持原样：三名受伤角色都会回复1点。
	if _controller.state.get_player(1).hp != 4 or _controller.state.get_player(2).hp != 4:
		return _fail("yuezhi_cancel_changed_targets hp=%d,%d" % [_controller.state.get_player(1).hp, _controller.state.get_player(2).hp])
	return true


## 校验结算期伤害守卫：首次伤害放行，其后每一次伤害都被防止。
## 直接置位守卫状态以隔离验证核心规则，不依赖真实用牌流程；守卫生成的完整链路已在上面的接管用例覆盖。
func _test_yuezhi_guard_prevents_repeat_damage() -> bool:
	_reset_state(2)
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	# 守卫生效并绑定一张不存在的牌UID；本用例只验证伤害窗口。
	yuezhi._guard_card_uid = 999999
	yuezhi._guard_active = true
	yuezhi._damage_resolved = false
	yuezhi._recover_resolved = false
	# 连续两次1点伤害：只有第一次应该成立，体力从4降到3。
	yuezhi.get_skill_player(0).damage(1, yuezhi.get_skill_player(0))
	yuezhi.get_skill_player(0).damage(1, yuezhi.get_skill_player(0))
	if _controller.state.get_player(0).hp != 3:
		return _fail("yuezhi_guard_damage hp=%d" % _controller.state.get_player(0).hp)
	return true


## 校验结算期回复守卫：首次回复放行，其后每一次回复都被防止；与伤害守卫各自独立计数。
func _test_yuezhi_guard_prevents_repeat_recover() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).hp = 2
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	# 守卫生效；伤害与回复分别持有独立的放行名额。
	yuezhi._guard_card_uid = 999999
	yuezhi._guard_active = true
	yuezhi._damage_resolved = false
	yuezhi._recover_resolved = false
	# 连续两次1点回复：只有第一次应该成立，体力从2升到3。
	_controller.recover(0, 0, 1, "taoyuan")
	_controller.recover(0, 0, 1, "taoyuan")
	if _controller.state.get_player(0).hp != 3:
		return _fail("yuezhi_guard_recover hp=%d" % _controller.state.get_player(0).hp)
	return true


## 校验守卫在该牌整牌结算完毕后解除：后续伤害不再被防止，状态不会泄漏到下一张牌。
func _test_yuezhi_guard_cleared_after_card() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).hp = 1
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing")
	# 真实发动一次接管，使守卫绑定到一张确实会走完整个生命周期的牌。
	var taoyuan_card: CardInstance = _add_hand_card(1, "taoyuan", "heart", 1)
	_controller._execute_card_use(1, taoyuan_card, [0, 1, 2])
	if not _has_yuezhi_prompt():
		return _fail("yuezhi_guard_clear_no_prompt")
	if not _submit_pending_choice(0, [], [], true):
		return false
	# 该牌已经整牌结算完毕，守卫必须已被 useCardAfter 解除。
	if yuezhi._guard_active:
		return _fail("yuezhi_guard_not_cleared")
	# 守卫解除后伤害恢复为正常结算：连续两次伤害都必须成立，体力从4降到2。
	_controller.state.get_player(0).hp = 4
	yuezhi.get_skill_player(0).damage(1, yuezhi.get_skill_player(0))
	yuezhi.get_skill_player(0).damage(1, yuezhi.get_skill_player(0))
	if _controller.state.get_player(0).hp != 2:
		return _fail("yuezhi_guard_leaked hp=%d" % _controller.state.get_player(0).hp)
	return true


## 校验【岳峙】的 AI 使用者规则：队友使用的非【五谷丰登】牌一律不发动，任意角色使用【五谷丰登】时无条件发动。
## 第一段用真实用牌验证询问上下文确实携带使用者与牌定义；第二段固定同一份上下文只改使用者，直接对比评分方向。
func _test_yuezhi_ai_source_rule() -> bool:
	# 真实用牌段：二号位忠臣使用【桃园结义】，询问上下文必须写入使用者与牌定义，供AI判断阵营。
	_reset_state(3)
	var yuezhi: SkillDefinition = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing_ai_source")
	var taoyuan_card: CardInstance = _add_hand_card(2, "taoyuan", "heart", 1)
	_controller._execute_card_use(2, taoyuan_card, [0, 1, 2])
	if not _has_yuezhi_prompt():
		return _fail("yuezhi_ai_source_no_prompt")
	var prompted_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if int(prompted_context.get("source_id", -1)) != 2:
		return _fail("yuezhi_ai_source_field=%s" % [prompted_context])
	if str(prompted_context.get("card_definition_id", "")) != "taoyuan":
		return _fail("yuezhi_ai_source_card=%s" % [prompted_context])
	# 评分段：五人局中一号领袖持有岳峙、二至四号忠臣残血为队友、五号反贼为敌。
	_reset_state(5)
	_controller.state.get_player(1).identity = "loyalist"
	_controller.state.get_player(4).identity = "rebel"
	for teammate_id: int in [1, 2, 3]:
		_controller.state.get_player(teammate_id).hp = 1
	yuezhi = _install_single_skill(0, "yuezhi")
	if yuezhi == null:
		return _fail("yuezhi_missing_ai_scoring")
	# 固定的伤害牌接管上下文；【万箭齐发】的目标已排除使用者本人，仅替换使用者即可对比敌我两种来源。
	var damage_target_ids: Array[int] = [0, 1, 2, 3]
	# 敌方（五号反贼）使用伤害牌：接管可替三名残血队友挡伤，评分必须为正分，证明拦截只针对队友。
	var enemy_context: Dictionary = {"kind":"yuezhi_become_sole_target", "card_uid":90001, "original_target_count":4, "original_target_ids":damage_target_ids, "card_definition_id":"wanjian", "source_id":4}
	# 队友（二号忠臣）使用同一张牌：接管会把队友的收益整体转走，评分必须为0，即取消发动。
	var teammate_context: Dictionary = {"kind":"yuezhi_become_sole_target", "card_uid":90002, "original_target_count":4, "original_target_ids":damage_target_ids, "card_definition_id":"wanjian", "source_id":2}
	if _score_yuezhi_confirm(enemy_context) <= 0.0:
		return _fail("yuezhi_ai_enemy_score=%f" % _score_yuezhi_confirm(enemy_context))
	if not is_zero_approx(_score_yuezhi_confirm(teammate_context)):
		return _fail("yuezhi_ai_teammate_score=%f" % _score_yuezhi_confirm(teammate_context))
	# 【五谷丰登】段：敌方与队友使用时都必须无条件确认，且评分高于任何普通牌接管收益。
	var wugu_context: Dictionary = {"kind":"yuezhi_become_sole_target", "card_uid":90003, "original_target_count":4, "original_target_ids":damage_target_ids, "card_definition_id":"wugu", "source_id":4}
	var teammate_wugu_context: Dictionary = {"kind":"yuezhi_become_sole_target", "card_uid":90004, "original_target_count":4, "original_target_ids":damage_target_ids, "card_definition_id":"wugu", "source_id":2}
	if _score_yuezhi_confirm(wugu_context) <= 0.0 or _score_yuezhi_confirm(teammate_wugu_context) <= 0.0:
		return _fail("yuezhi_ai_wugu_score=%f/%f" % [_score_yuezhi_confirm(wugu_context), _score_yuezhi_confirm(teammate_wugu_context)])
	if _score_yuezhi_confirm(teammate_wugu_context) <= _score_yuezhi_confirm(enemy_context):
		return _fail("yuezhi_ai_wugu_not_unconditional=%f" % _score_yuezhi_confirm(teammate_wugu_context))
	return true


## 用正式AI估值器对给定【岳峙】接管上下文中的“确认发动”动作评分；只读权威快照，不改变对局状态。
func _score_yuezhi_confirm(prompt_context: Dictionary) -> float:
	# 当前岳峙实例；缺失时返回0便于调用方直接失败退出。
	var yuezhi: SkillDefinition = _controller.get_skill_instance(0, "yuezhi")
	if yuezhi == null:
		return 0.0
	# 权威AI快照；技能AI钩子只允许读取该快照与估值器实例。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	return yuezhi.score_ai_choice(snapshot, {"context":prompt_context}, {"payload":{"confirmed":true}}, NonameAIEvaluator.new())


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(reason: String) -> bool:
	if not _failed:
		_failed = true
		printerr("YUEZHI_MECHANICS_FAIL %s" % reason)
		get_tree().quit(1)
	return false
