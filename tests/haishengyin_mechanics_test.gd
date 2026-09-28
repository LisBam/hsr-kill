extends Node

## 海瑟音【泛音】【回涛】专项回归。覆盖武将元数据、两条技能原文、四轮回节数量、弃置批次聚合、黑红结算顺序与回涛门槛。

## 本测试共用的权威对局控制器；全部机制通过正式服务与技能端口执行。
var _controller: MatchController

## 弃置批次时机捕获到的批次数据；每批一项，用于验证“一次弃置动作”只产生一个批次事件。
var _captured_batches: Array[Dictionary] = []


## 延迟一帧开始回归，确保 GameDatabase 已完成目录扫描和静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部断言；任一失败立即以非零状态结束。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_descriptions():
		return
	if not _test_discard_batch_aggregation():
		return
	if not _test_fanyin_black_then_red():
		return
	if not _test_huitao_thresholds():
		return
	print("HAISHENGYIN_MECHANICS_PASS batch=1 sections=4 black_first=1 huitao_min=3")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；弃置批次与轮回生命周期共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；身份观察和目标态度查询保持正式实现。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；公开快照广播与正式单机模式保持相同路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0


## 为单项测试创建最小权威状态并重建全部规则服务；角色身份公开以获得确定AI态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "haishengyin-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "海瑟音测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	# 摸牌堆；泛音红色效果与回涛摸牌断言需要可用的实体牌。
	for card_index: int in range(20):
		_controller.state.draw_pile.append(CardInstance.new("shan", "heart", card_index % 13 + 1))
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()


## 安装指定技能并返回独立运行时实例；测试与正式固有技能安装使用同一bind/install顺序。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 待安装技能实例；数据库必须能按稳定ID创建独立对象。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家技能表；允许同一测试逐项追加同武将的多个组件。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 校验武将资料、两条技能原文与泛音的四轮回节半锁定元数据。
func _test_metadata_and_descriptions() -> bool:
	# 海瑟音静态定义；性别、势力、体力与技能顺序必须与设计一致。
	var haishengyin: Dictionary = GameDatabase.get_character("haishengyin")
	if str(haishengyin.get("display_name", "")) != "海瑟音" or str(haishengyin.get("gender", "")) != "female" or str(haishengyin.get("faction", "")) != "wengfaluosi" or int(haishengyin.get("max_hp", 0)) != 4 or haishengyin.get("skills", []) != ["fanyin", "huitao"]:
		return _fail("character_metadata=%s" % haishengyin)
	# 需求指定的两条技能原文；任何字符、标点或带圈序号变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"fanyin":"轮回技，出牌阶段，你可弃置一张①黑桃②红桃③梅花④方块牌。锁定技，当你弃置牌时，若这些牌中有黑色牌，你令一名角色弃置一张手牌；若这些牌中有红色牌，你摸一张牌。",
		"huitao":"当一名角色的轮回技进入下一个轮回时，若该轮回技的轮回节数不小于3，你可令其摸一张牌。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；静态数据库说明必须与期望逐字一致。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("skill_description=%s" % skill_id)
	# 泛音运行时元数据；前段非锁定、后段锁定，且固定四个轮回节。
	var fanyin: SkillDefinition = GameDatabase.create_skill("fanyin")
	if fanyin == null or not fanyin.half_locked or fanyin.lock or not fanyin.reincarnation or int(fanyin._metadata.get("reincarnation_section_count", 0)) != 4:
		return _fail("fanyin_metadata")
	return true


## 校验一次弃置动作的全部牌只产生一个批次事件，并携带完整UID集合。
func _test_discard_batch_aggregation() -> bool:
	_reset_state(2)
	_captured_batches.clear()
	_controller.event_bus.subscribe("cardsDiscardedBatchAfter", self, _capture_discard_batch)
	# 三张手牌；一次性弃置必须只产生一个批次事件。
	var player: PlayerState = _controller.state.get_player(0)
	# 本次弃置的费用UID；按顺序登记以便逐张进入弃牌堆。
	var selected_uids: Array[int] = []
	for card_index: int in range(3):
		var card: CardInstance = CardInstance.new("shan", "heart", card_index + 1)
		# 持有者与区域；正式对局由移动服务在进入玩家区域时写入，测试直接入区必须补齐。
		card.owner_id = 0
		card.zone = "hand"
		player.hand.append(card)
		selected_uids.append(card.uid)
	if int(_controller.discard_selected_hand_cards(0, selected_uids)) != 3:
		return _fail("batch_discard_count")
	if _captured_batches.size() != 1:
		return _fail("batch_event_count=%d" % _captured_batches.size())
	# 批次内容；三张牌必须归属同一批次且数量一致。
	var batch: Dictionary = _captured_batches[0]
	if (batch.get("card_uids", []) as Array).size() != 3 or int(batch.get("batch_size", 0)) != 3 or int(batch.get("source_player_id", -1)) != 0:
		return _fail("batch_content=%s" % batch)
	return true


## 记录一次批次事件的数据快照；只读取规则事件提供的稳定字段。
func _capture_discard_batch(event: RuleEvent) -> void:
	_captured_batches.append((event.data as Dictionary).duplicate(true))


## 校验同一批次同时含黑红时先执行黑色效果，再执行红色效果。
func _test_fanyin_black_then_red() -> bool:
	_reset_state(3)
	# 玩家0持有泛音；玩家1保留一张手牌作为黑色效果目标。
	if _install_skill(0, "fanyin") == null:
		return _fail("fanyin_install")
	var owner: PlayerState = _controller.state.get_player(0)
	# 黑色费用牌；与红色费用牌同批弃置以触发两种颜色效果。
	var black_card: CardInstance = CardInstance.new("shan", "spade", 7)
	# 红色费用牌；同批弃置时其效果必须排在黑色效果之后。
	var red_card: CardInstance = CardInstance.new("shan", "heart", 2)
	# 持有者与区域；正式对局由移动服务在进入玩家区域时写入。
	black_card.owner_id = 0
	black_card.zone = "hand"
	red_card.owner_id = 0
	red_card.zone = "hand"
	owner.hand.append(black_card)
	owner.hand.append(red_card)
	# 黑色效果目标；必须有手牌才会进入目标选择。
	var target: PlayerState = _controller.state.get_player(1)
	# 目标待弃置的手牌；结算后应离开其手牌区。
	var target_card: CardInstance = CardInstance.new("shan", "club", 3)
	target_card.owner_id = 1
	target_card.zone = "hand"
	target.hand.append(target_card)
	if int(_controller.discard_selected_hand_cards(0, [black_card.uid, red_card.uid])) != 2:
		return _fail("fanyin_discard_count")
	# 黑色效果入口；批次整体判定后必须先创建目标请求。
	var target_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(target_context.get("kind", "")) != "fanyin_black_target":
		return _fail("fanyin_black_request=%s" % target_context)
	# 黑色效果尚未结算时不得先摸牌；这是“先黑后红”的直接判据。
	if not owner.hand.is_empty():
		return _fail("fanyin_red_before_black=%d" % owner.hand.size())
	if not _submit_choice(0, [1], true):
		return false
	# 第二段选择；由目标本人选择要弃置的手牌。
	var discard_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(discard_context.get("kind", "")) != "fanyin_black_discard" or int(discard_context.get("target_id", -1)) != 1:
		return _fail("fanyin_black_discard_request=%s" % discard_context)
	if not _submit_card_choice(1, [target_card.uid], true):
		return false
	# 结算结果；目标失去一张手牌，持有者随后因红色效果摸回一张。
	if not target.hand.is_empty() or owner.hand.size() != 1:
		return _fail("fanyin_effects target=%d owner=%d" % [target.hand.size(), owner.hand.size()])
	return true


## 校验回涛只在轮回节数不小于3的轮回技进入下一个轮回时出现入口，且收益者为该轮回技持有者。
func _test_huitao_thresholds() -> bool:
	_reset_state(3)
	if _install_skill(0, "huitao") == null:
		return _fail("huitao_install")
	# 玩家1的4节轮回技；推进到轮回数2会发布“进入下一个轮回”。
	var four_section_skill: SkillDefinition = SkillDefinition.new({"id":"huitao_probe_four", "reincarnation":true, "reincarnation_section_count":4, "reincarnation_has_explicit_sections":true, "description":"轮回技，出牌阶段，①你摸一张牌；②你摸一张牌；③你摸一张牌；④你摸一张牌。"})
	four_section_skill.bind(_controller, 1)
	for _section_index: int in range(4):
		four_section_skill.begin_reincarnation_activation()
		four_section_skill.complete_reincarnation_activation()
	if four_section_skill.get_reincarnation_round_count() != 2:
		return _fail("probe_round_count=%d" % four_section_skill.get_reincarnation_round_count())
	# 发动入口；节数4不小于3，必须创建回涛确认请求。
	var context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "huitao_confirm" or int(context.get("trigger_player_id", -1)) != 1:
		return _fail("huitao_entry=%s" % context)
	# 确认发动；摸牌收益者必须是轮回技持有者而不是海瑟音本人。
	var trigger_hand_before: int = _controller.state.get_player(1).hand.size()
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	if not _submit_confirm(0, true):
		return false
	if _controller.state.get_player(1).hand.size() != trigger_hand_before + 1 or _controller.state.get_player(0).hand.size() != owner_hand_before:
		return _fail("huitao_draw_target")
	# 节数不足3的轮回技推进时不得出现发动入口。
	_controller._pending_card_choice.clear()
	var two_section_skill: SkillDefinition = SkillDefinition.new({"id":"huitao_probe_two", "reincarnation":true, "reincarnation_section_count":2, "reincarnation_has_explicit_sections":true, "description":"轮回技，出牌阶段，①你摸一张牌；②你摸一张牌。"})
	two_section_skill.bind(_controller, 2)
	for _section_index: int in range(2):
		two_section_skill.begin_reincarnation_activation()
		two_section_skill.complete_reincarnation_activation()
	if two_section_skill.get_reincarnation_round_count() != 2:
		return _fail("probe_two_round_count=%d" % two_section_skill.get_reincarnation_round_count())
	if not _controller._pending_card_choice.is_empty():
		return _fail("huitao_threshold_two_sections")
	return true


## 为当前选择请求提交目标或取消；选择动作必须绑定创建时的同一请求编号。
func _submit_choice(actor_id: int, target_ids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_choice")
	# 当前请求稳定编号；同步恢复可能立刻创建下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":target_ids.duplicate(), "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("target_choice_rejected")
	return true


## 为当前选择请求提交实体牌UID；等待期间离区的牌由权威端口再次复核。
func _submit_card_choice(actor_id: int, selected_card_uids: Array[int], confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return _fail("missing_card_choice")
	# 当前请求稳定编号；提交绑定该稳定ID，避免同步续接后误操作下一请求。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":[], "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("card_choice_rejected")
	return true


## 为当前零材料确认请求提交确认或取消；泛音与回涛的发动确认共用该入口。
func _submit_confirm(actor_id: int, confirmed: bool) -> bool:
	return _submit_choice(actor_id, [], confirmed)


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("HAISHENGYIN_FAIL %s" % reason)
	get_tree().quit(1)
	return false
