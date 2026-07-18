extends Node

## 新武将机制专项回归。覆盖规则牌名、武将引用、横置旋转、护盾语义、五个新技能的核心结算与指定AI分支。

## 武将牌可复用场景；用真实场景结构验证横置角度与全局包围矩形。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 每个机制场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保GameDatabase已完成新武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行新机制回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_rule_names():
		return
	if not await _test_character_card_orientation():
		return
	if not _test_jiahu_and_bingfeng():
		return
	if not _test_gangfeng_response():
		return
	if not _test_jiyu_branches():
		return
	if not _test_yongyi_and_shield_semantics():
		return
	if not _test_new_skill_ai_rules():
		return
	print("NEW_CHARACTER_MECHANICS_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；护盾、伤害和技能时机共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；本测试直接使用评估器，仍保留正式节点供身份观察使用。
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
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "new-character-mechanics"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；全部身份公开以避免专项AI断言受推断衰减干扰。
		var player: PlayerState = PlayerState.new(player_id, "新武将玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
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
	_controller._active_extra_discard_phase.clear()
	_controller._extra_play_phase_counts.clear()
	_controller._extra_play_phase_returns_to_finish.clear()
	_controller._started_phase_lifecycles.clear()


## 验证属性【杀】的规则名与显示名分离，并核对三名武将的体力、势力和技能引用。
func _test_metadata_and_rule_names() -> bool:
	# 火【杀】与雷【杀】定义；rule_name用于规则称呼，original_name与custom_name继续提供两字牌面。
	var fire_slash: Dictionary = GameDatabase.get_card("sha_fire")
	# 雷【杀】定义；与火【杀】共同校验规则名和牌面显示名分离。
	var thunder_slash: Dictionary = GameDatabase.get_card("sha_thunder")
	if str(fire_slash.get("rule_name", "")) != "杀" or str(thunder_slash.get("rule_name", "")) != "杀" or str(fire_slash.get("original_name", "")) != "火杀" or str(thunder_slash.get("custom_name", "")) != "雷杀":
		return _fail("attribute_slash_names fire=%s thunder=%s" % [fire_slash, thunder_slash])
	# 三名新武将定义；技能数组顺序就是面板与运行时安装顺序。
	var march: Dictionary = GameDatabase.get_character("march_7th")
	# 杰帕德武将定义；验证势力、性别、体力与【永屹】引用。
	var gepard: Dictionary = GameDatabase.get_character("gepard")
	# 丹恒武将定义；验证势力、性别、体力与【罡风】【疾雨】引用。
	var dan_heng: Dictionary = GameDatabase.get_character("dan_heng")
	if int(march.get("max_hp", 0)) != 3 or str(march.get("gender", "")) != "female" or str(march.get("faction", "")) != "xingqionglieche" or (march.get("skills", []) as Array) != ["jiahu", "bingfeng"]:
		return _fail("march_metadata=%s" % march)
	if int(gepard.get("max_hp", 0)) != 4 or str(gepard.get("gender", "")) != "male" or str(gepard.get("faction", "")) != "beiluoboge" or (gepard.get("skills", []) as Array) != ["yongyi"]:
		return _fail("gepard_metadata=%s" % gepard)
	if int(dan_heng.get("max_hp", 0)) != 4 or str(dan_heng.get("faction", "")) != "xingqionglieche" or (dan_heng.get("skills", []) as Array) != ["gangfeng", "jiyu"]:
		return _fail("dan_heng_metadata=%s" % dan_heng)
	if not GameDatabase.get_skill("six_phased_ice_sample").is_empty() or not GameDatabase.get_skill("cloud_piercer_sample").is_empty():
		return _fail("placeholder_skills_still_registered")
	return true


## 验证武将牌从竖置切换为横置后实际旋转90度，再次切换时恢复竖直与原锚点。
func _test_character_card_orientation() -> bool:
	# 真实武将牌视图；加入场景树后才会记录竖置锚点。
	var player_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	add_child(player_view)
	await get_tree().process_frame
	# 竖置公开快照；包含武将牌视觉必需的最小字段。
	var snapshot: Dictionary = {"player_id":1, "display_name":"横置测试", "character_id":"march_7th", "identity":"rebel", "hp":3, "max_hp":3, "shield":0, "alive":true, "chained":false, "face_down":false, "hand_count":0, "equipment":{}, "judgment_area":[], "wooden_ox_storage_count":0}
	player_view.configure_snapshot(snapshot, GameDatabase.get_character("march_7th"))
	# 竖置锚点；恢复方向后必须精确回到该位置。
	var upright_position: Vector2 = player_view.position
	if not is_zero_approx(player_view.rotation):
		player_view.queue_free()
		return _fail("upright_rotation=%s" % player_view.rotation)
	snapshot["chained"] = true
	player_view.configure_snapshot(snapshot, GameDatabase.get_character("march_7th"))
	# 横置全局矩形；90度旋转后宽高应与竖置卡尺寸交换。
	var horizontal_rect: Rect2 = player_view.get_global_rect()
	if not is_equal_approx(player_view.rotation, PI * 0.5) or not is_equal_approx(horizontal_rect.size.x, player_view.card_size.y) or not is_equal_approx(horizontal_rect.size.y, player_view.card_size.x):
		player_view.queue_free()
		return _fail("horizontal_orientation rotation=%s rect=%s" % [player_view.rotation, horizontal_rect])
	snapshot["chained"] = false
	player_view.configure_snapshot(snapshot, GameDatabase.get_character("march_7th"))
	if not is_zero_approx(player_view.rotation) or not player_view.position.is_equal_approx(upright_position):
		player_view.queue_free()
		return _fail("orientation_restore rotation=%s position=%s/%s" % [player_view.rotation, player_view.position, upright_position])
	player_view.queue_free()
	return true


## 验证加护的横置护盾顺序，以及冰封的竖置、目标无效与每目标每回合限次。
func _test_jiahu_and_bingfeng() -> bool:
	_reset_state(2)
	# 加护运行时技能；直接恢复标准目标选择以验证权威效果。
	var jiahu: SkillDefinition = GameDatabase.create_skill("jiahu")
	jiahu.bind(_controller, 0)
	# 加护目标响应；确认二号玩家为唯一目标。
	var jiahu_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	jiahu_response.target_ids = [1]
	jiahu.continue_selection({"kind":"jiahu_target"}, jiahu_response)
	# 加护目标状态；应先横置再获得1点护盾。
	var protected_target: PlayerState = _controller.state.get_player(1)
	if not protected_target.chained or protected_target.shield != 1:
		return _fail("jiahu_result chained=%s shield=%d" % [protected_target.chained, protected_target.shield])
	protected_target.shield = 0
	# 冰封运行时技能；一回合内每个目标使用独立额度。
	var bingfeng: SkillDefinition = GameDatabase.create_skill("bingfeng")
	bingfeng.bind(_controller, 0)
	_controller._card_use_contexts[9001] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	# 冰封竖置分支响应；指定玩家可见选项的稳定ID。
	var straighten_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	straighten_response.control_id = "straighten_target"
	bingfeng.continue_selection({"kind":"bingfeng_option", "target_id":1, "card_uid":9001, "card_id":"sha"}, straighten_response)
	# 冰封用牌上下文；非自身目标应加入excluded_target_ids。
	var first_card_context: Dictionary = _controller._card_use_contexts[9001] as Dictionary
	if protected_target.chained or not (first_card_context.get("excluded_target_ids", []) as Array).has(1):
		return _fail("bingfeng_straighten chained=%s context=%s" % [protected_target.chained, first_card_context])
	protected_target.chained = true
	_controller._card_use_contexts[9002] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	bingfeng.continue_selection({"kind":"bingfeng_option", "target_id":1, "card_uid":9002, "card_id":"sha"}, straighten_response)
	# 第二张牌上下文；同回合同目标已用过冰封，不应再竖置或标记无效。
	var second_card_context: Dictionary = _controller._card_use_contexts[9002] as Dictionary
	if not protected_target.chained or not (second_card_context.get("excluded_target_ids", []) as Array).is_empty():
		return _fail("bingfeng_target_limit chained=%s context=%s" % [protected_target.chained, second_card_context])
	return true


## 验证罡风可在响应窗口将黑色实体牌转化为保留花色点数的雷【杀】，材料最终进入弃牌堆。
func _test_gangfeng_response() -> bool:
	_reset_state(2)
	# 罡风运行时技能；安装到玩家技能表后核心响应候选会自动查找该转化。
	var gangfeng: SkillDefinition = GameDatabase.create_skill("gangfeng")
	gangfeng.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"gangfeng":gangfeng}}
	# 黑色响应材料；使用梅花Q验证虚拟雷【杀】继承花色与点数。
	var material: CardInstance = _add_hand_card(0, "shan", "club", 12)
	# 转化后响应牌；定义ID必须为sha_thunder，但实体UID不替代真实材料记录。
	var response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, material.uid, ["sha"])
	if response_card == null or response_card.definition_id != "sha_thunder" or response_card.suit != "club" or response_card.rank != 12 or _controller.state.get_player(0).find_hand_card(material.uid) != null or not _controller.state.discard_pile.has(material):
		return _fail("gangfeng_response card=%s discard=%s" % [response_card.to_dict() if response_card != null else {}, _controller.state.discard_pile.has(material)])
	# 黑色装备材料；白银狮子离区应卸载装备运行时、回复1点体力并把材料送入弃牌堆。
	var response_owner: PlayerState = _controller.state.get_player(0)
	response_owner.hp = 3
	# 测试防具实体；黑桃花色使其满足罡风黑色材料条件。
	var armor_material: CardInstance = CardInstance.new("baiyin", "spade", 1)
	armor_material.zone = "equipment"
	armor_material.owner_id = 0
	response_owner.equipment["armor"] = armor_material
	_controller._install_card_runtime(armor_material, 0)
	# 装备材料转化后的响应牌；成功后装备槽、运行时索引与离区回复必须同时完成。
	var equipment_response_card: CardInstance = _controller._consume_response_card_uid_patterns(0, armor_material.uid, ["sha"])
	if equipment_response_card == null or equipment_response_card.definition_id != "sha_thunder" or response_owner.equipment.has("armor") or _controller.card_runtime_instances.has(armor_material.uid) or response_owner.hp != 4 or not _controller.state.discard_pile.has(armor_material):
		return _fail("gangfeng_equipment_response hp=%d equipment=%s runtime=%s discard=%s" % [response_owner.hp, response_owner.equipment, _controller.card_runtime_instances.has(armor_material.uid), _controller.state.discard_pile.has(armor_material)])
	return true


## 验证疾雨第1项写入雷【杀】直击目标，并验证第2项仅横置丹恒当前攻击范围内的另一名角色。
func _test_jiyu_branches() -> bool:
	_reset_state(3)
	# 疾雨运行时技能；分支恢复使用权威卡牌上下文与攻击范围查询。
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	jiyu.bind(_controller, 0)
	_controller._card_use_contexts[9101] = {"target_ids":[1], "excluded_target_ids":[], "direct_hit_target_ids":[]}
	# 疾雨第1项响应；目标明确选择不可响应此【杀】。
	var direct_hit_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 1, true)
	direct_hit_response.control_id = "direct_hit"
	jiyu.continue_selection({"kind":"jiyu_target_option", "target_id":1, "card_uid":9101}, direct_hit_response)
	# 雷【杀】使用上下文；二号玩家应成为唯一直击目标。
	var card_context: Dictionary = _controller._card_use_contexts[9101] as Dictionary
	if not (card_context.get("direct_hit_target_ids", []) as Array).has(1):
		return _fail("jiyu_direct_hit=%s" % card_context)
	# 疾雨第2项目标响应；三人局基础攻击范围内的三号玩家为合法“另一名角色”。
	var link_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	link_response.target_ids = [2]
	jiyu.continue_selection({"kind":"jiyu_link_other_target", "target_id":1, "card_uid":9101}, link_response)
	if not _controller.state.get_player(2).chained:
		return _fail("jiyu_link_other_not_applied")
	return true


## 验证失去护盾不影响体力也不写入伤害历史，并验证永屹额外弃牌阶段完成后才获得1点护盾。
func _test_yongyi_and_shield_semantics() -> bool:
	_reset_state(2)
	# 杰帕德权威状态；初始1点护盾用于验证SkillPlayer.loseShield独立语义。
	var gepard: PlayerState = _controller.state.get_player(0)
	gepard.shield = 1
	# 永屹运行时技能；同时登记到技能表供额外阶段完成回调定位。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	yongyi.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{"yongyi":yongyi}}
	# 失去护盾前的体力与伤害历史数；执行后必须完全不变。
	var hp_before: int = gepard.hp
	# 失去护盾前的伤害历史条目数；用于证明该动作不会产生伤害事实。
	var damage_history_count_before: int = gepard.damage_history.size()
	if yongyi.get_owner_skill_player().loseShield(1, yongyi.get_owner_skill_player()) != 1 or gepard.hp != hp_before or gepard.damage_history.size() != damage_history_count_before:
		return _fail("lose_shield_semantics hp=%d shield=%d history=%d" % [gepard.hp, gepard.shield, gepard.damage_history.size()])
	# 额外弃牌阶段完成上下文；无超限手牌时阶段会同步完成并回调永屹。
	var completion_context: Dictionary = {"kind":"yongyi_extra_discard_complete", "skill_owner_id":0, "skill_id":"yongyi"}
	if not _controller.request_extra_discard_phase(0, 1, "yongyi", completion_context) or gepard.shield != 1 or not _controller._active_extra_discard_phase.is_empty():
		return _fail("yongyi_extra_discard shield=%d active=%s" % [gepard.shield, _controller._active_extra_discard_phase])
	_controller.state.current_phase = "discard"
	# 永屹弃牌阶段确认响应；支付1点护盾后应排队1个额外出牌阶段并标记其结束后直接进入结束阶段。
	var extra_play_response: ChoiceResponse = ChoiceResponse.new(-1, -1, 0, true)
	yongyi.continue_selection({"kind":"yongyi_play_phase_confirm"}, extra_play_response)
	if gepard.shield != 0 or int(_controller._extra_play_phase_counts.get(0, 0)) != 1 or not bool(_controller._extra_play_phase_returns_to_finish.get(0, false)):
		return _fail("yongyi_extra_play shield=%d count=%d return_finish=%s" % [gepard.shield, int(_controller._extra_play_phase_counts.get(0, 0)), _controller._extra_play_phase_returns_to_finish])
	return true


## 验证冰封会主动把对横置队友的负收益牌转化为正收益，且疾雨在候选只有丹恒队友时无条件选第2项。
func _test_new_skill_ai_rules() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "march_7th"
	_controller.state.get_player(2).chained = true
	# 权威AI快照；对本地策略包含完整手牌与公开技能历史。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 无名杀式AI评估器；使用公开身份得到稳定忠反态度。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 对横置队友使用【杀】的负收益动作；冰封应移除原效果并加入竖置收益。
	var harmful_ally_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_definition_id":"sha", "target_ids":[2]}
	# 原【杀】基础分；对公开忠臣造成伤害应为负。
	var base_harmful_score: float = evaluator.score_action(snapshot, harmful_ally_action, 0)
	# 冰封修正分；主动转化后应严格高于原动作且为正。
	var bingfeng: SkillDefinition = GameDatabase.create_skill("bingfeng")
	bingfeng.bind(null, 0)
	# 冰封修正后的动作评分；必须体现无效负收益牌并竖置友方的组合收益。
	var converted_score: float = bingfeng.modify_ai_card_action_score(snapshot, harmful_ally_action, base_harmful_score, evaluator)
	if converted_score <= base_harmful_score or converted_score <= 0.0:
		return _fail("bingfeng_ai_conversion base=%s converted=%s" % [base_harmful_score, converted_score])
	# 疾雨静态AI技能；选项候选只含三号忠臣，其为丹恒队友。
	var jiyu: SkillDefinition = GameDatabase.create_skill("jiyu")
	jiyu.bind(null, 0)
	# 目标文字选项请求；二号反贼即使没有【闪】，也应因候选只有丹恒队友而选第2项。
	var option_request: Dictionary = {"context":{"kind":"jiyu_target_option", "target_id":1, "redirect_target_ids":[2]}}
	# 第1项AI动作；表示不可响应此【杀】。
	var direct_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"direct_hit"}}
	# 第2项AI动作；表示令丹恒横置一名范围内角色。
	var redirect_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"link_other"}}
	if jiyu.score_ai_choice(snapshot, option_request, redirect_action, evaluator) <= jiyu.score_ai_choice(snapshot, option_request, direct_action, evaluator):
		return _fail("jiyu_ai_only_ally")
	# 永屹静态AI技能；可命中敌方的【杀】应使额外出牌收益高于1点护盾。
	var yongyi: SkillDefinition = GameDatabase.create_skill("yongyi")
	yongyi.bind(null, 0)
	# 永屹额外出牌确认请求；显式写入1张可用牌与可命中敌方【杀】。
	var play_request: Dictionary = {"context":{"kind":"yongyi_play_phase_confirm", "usable_card_count":1, "enemy_slash_available":true}}
	# 零牌确认动作；只有技能计算的净收益决定是否发动。
	var confirm_action: Dictionary = {"payload":{"confirmed":true}}
	if yongyi.score_ai_choice(snapshot, play_request, confirm_action, evaluator) <= 0.0:
		return _fail("yongyi_ai_extra_play")
	return true


## 向指定玩家普通手牌区加入一张测试实体；花色、点数、区域与所有者全部显式写入。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("NEW_CHARACTER_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
