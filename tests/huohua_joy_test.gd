extends Node

## 欢愉派系与火花专项测试：校验势力元数据、武将定义、两项技能的静态正文与参数，以及【好戏】【连戏】的完整结算链路。

## 每个场景共用的权威对局控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保 GameDatabase 已完成新武将与技能目录扫描。
func _ready() -> void:
	call_deferred("_run")


## 按独立状态顺序执行断言；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	if not _test_huanyu_faction_and_huohua_metadata():
		return
	if not _test_haoxi_static_definition():
		return
	if not _test_lianxi_static_definition():
		return
	if not _test_haoxi_gains_basic_cards_by_target_count():
		return
	if not _test_haoxi_discards_random_hand_cards():
		return
	if not _test_lianxi_recast_times_and_damage():
		return
	if not _test_lianxi_requires_basic_card():
		return
	print("HUOHUA_JOY_PASS faction=huanyu hp=3 haoxi=144 lianxi_recast=7")
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
	_controller.state.match_id = "huohua-joy"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
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


## 校验欢愉势力元数据与火花的武将定义；势力颜色、性别、体力与技能顺序必须逐项稳定。
func _test_huanyu_faction_and_huohua_metadata() -> bool:
	# 欢愉势力元数据；需求指定颜色为橙红色，展示名与简称逐字锁定。
	var faction: Dictionary = GameDatabase.get_faction("huanyu")
	if str(faction.get("display_name", "")) != "欢愉" or str(faction.get("short_name", "")) != "欢" or str(faction.get("color", "")) != "e0673c":
		return _fail("huanyu_faction %s" % [faction])
	# 火花武将定义；欢愉派系女性、3点基础体力、两项技能按声明顺序登记。
	var huohua: Dictionary = GameDatabase.get_character("huohua")
	if str(huohua.get("display_name", "")) != "火花" or str(huohua.get("gender", "")) != "female" or str(huohua.get("faction", "")) != "huanyu" or int(huohua.get("max_hp", 0)) != 3:
		return _fail("huohua_metadata %s" % [huohua])
	if (huohua.get("skills", []) as Array) != ["haoxi", "lianxi"]:
		return _fail("huohua_skills %s" % [huohua.get("skills", [])])
	return true


## 校验【好戏】的静态定义：欢愉技标签、参演编号与玩家可见正文。
func _test_haoxi_static_definition() -> bool:
	# 好戏运行时实例；只读取静态参数，不绑定对局。
	var haoxi: SkillDefinition = GameDatabase.create_skill("haoxi")
	if haoxi == null:
		return _fail("haoxi_missing")
	if not haoxi.is_joy_skill() or haoxi.get_performance_number() != 144:
		return _fail("haoxi_joy_params joy=%s number=%d" % [str(haoxi.is_joy_skill()), haoxi.get_performance_number()])
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "欢愉技，参演编号144，你可弃置0-2名其他角色各一张随机手牌，然后从牌堆中获得X张基本牌。（X为2-本次选择的目标数）"
	var description: String = str(GameDatabase.get_skill("haoxi").get("description", ""))
	if description != expected_description:
		return _fail("haoxi_description %s" % description)
	# 正文类型段必须与 joy_skill 标签一致，否则 GameDatabase 会在加载期拒绝开局。
	if not SkillDefinition.description_declares_joy_type(description):
		return _fail("haoxi_description_type")
	return true


## 校验【连戏】的静态定义：普通出牌阶段主动技能、非欢愉技、玩家可见正文。
func _test_lianxi_static_definition() -> bool:
	# 连戏运行时实例；只读取静态参数。
	var lianxi: SkillDefinition = GameDatabase.create_skill("lianxi")
	if lianxi == null:
		return _fail("lianxi_missing")
	# 连戏不是欢愉技：其正文没有类型段声明，也不参与阿哈时刻的参演排序。
	if lianxi.is_joy_skill() or lianxi.get_performance_number() != 0:
		return _fail("lianxi_joy_params joy=%s number=%d" % [str(lianxi.is_joy_skill()), lianxi.get_performance_number()])
	# 玩家可见正文；必须与需求原文逐字一致。
	var expected_description: String = "出牌阶段限一次，你可以重铸你手牌中的所有基本牌，你可以重复此流程（至多重铸七次），最后对一名其他角色造成Y点伤害。（Y为你本次重铸的次数/2，向下取整）"
	var description: String = str(GameDatabase.get_skill("lianxi").get("description", ""))
	if description != expected_description:
		return _fail("lianxi_description %s" % description)
	if not lianxi.declares_description_tag(SkillDefinition.PLAY_PHASE_ONCE_TAG):
		return _fail("lianxi_play_phase_once_tag")
	return true


## 校验【好戏】的X算式：X=2-本次选择的目标数，0名目标取2张、1名目标取1张。
func _test_haoxi_gains_basic_cards_by_target_count() -> bool:
	# 0名目标场景；火花获得两张基本牌，且不弃置任何其他角色。
	_reset_state(3)
	_controller.state.get_player(0).character_id = "huohua"
	_add_draw_pile_card("sha", "spade", 7)
	_add_draw_pile_card("shan", "heart", 2)
	_add_draw_pile_card("tao", "club", 5)
	# 敌方手上的锦囊牌；0名目标时不应被移动。
	var untouched_card: CardInstance = _add_hand_card(1, "wuxie", "club", 9)
	var haoxi: SkillDefinition = _install_single_skill(0, "haoxi")
	if haoxi == null or not haoxi.can_perform_joy_skill():
		return _fail("haoxi_can_perform")
	haoxi.perform_joy_skill({})
	if str(_controller._pending_card_choice.get("choice_type", "")) != "target":
		return _fail("haoxi_target_request %s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], true):
		return false
	if _controller.state.get_player(0).hand.size() != 2:
		return _fail("haoxi_zero_target_draw=%d" % _controller.state.get_player(0).hand.size())
	# 获得的每张牌都必须是基本牌；牌堆中只有基本牌时不应出现杂牌。
	for gained_card: CardInstance in _controller.state.get_player(0).hand:
		if str(GameDatabase.get_card(gained_card.definition_id).get("type", "")) != "basic":
			return _fail("haoxi_non_basic_gain %s" % gained_card.definition_id)
	if not _controller.state.get_player(1).hand.has(untouched_card):
		return _fail("haoxi_zero_target_discarded")
	# 1名目标场景；火花只获得一张基本牌。
	_reset_state(3)
	_controller.state.get_player(0).character_id = "huohua"
	_add_draw_pile_card("sha", "spade", 7)
	_add_draw_pile_card("shan", "heart", 2)
	_add_hand_card(1, "wuxie", "club", 9)
	var single_haoxi: SkillDefinition = _install_single_skill(0, "haoxi")
	if single_haoxi == null:
		return _fail("haoxi_missing")
	single_haoxi.perform_joy_skill({})
	if not _submit_pending_choice(0, [], [1], true):
		return false
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("haoxi_one_target_draw=%d" % _controller.state.get_player(0).hand.size())
	return true


## 校验【好戏】的弃置分支：每名被选中的其他角色各随机弃置一张手牌，且X随目标数下降。
func _test_haoxi_discards_random_hand_cards() -> bool:
	_reset_state(3)
	_controller.state.get_player(0).character_id = "huohua"
	_add_draw_pile_card("sha", "spade", 7)
	# 两名目标各两张手牌；随机弃置后各剩一张，确认是“各一张”而不是集中在一人身上。
	var first_target_card_a: CardInstance = _add_hand_card(1, "sha", "spade", 9)
	var first_target_card_b: CardInstance = _add_hand_card(1, "shan", "heart", 6)
	_add_hand_card(2, "tao", "club", 4)
	_add_hand_card(2, "jiu", "diamond", 8)
	var haoxi: SkillDefinition = _install_single_skill(0, "haoxi")
	if haoxi == null:
		return _fail("haoxi_missing")
	haoxi.perform_joy_skill({})
	if not _submit_pending_choice(0, [], [1, 2], true):
		return false
	if _controller.state.get_player(1).hand.size() != 1 or _controller.state.get_player(2).hand.size() != 1:
		return _fail("haoxi_discard_counts one=%d two=%d" % [_controller.state.get_player(1).hand.size(), _controller.state.get_player(2).hand.size()])
	# 被弃置的实体必须来自原手牌并进入弃牌堆；随机只决定“哪一张”，不改变归属。
	var first_survivor: CardInstance = _controller.state.get_player(1).hand[0]
	var discarded_from_first: CardInstance = first_target_card_b if first_survivor == first_target_card_a else first_target_card_a
	if not _controller.state.discard_pile.has(discarded_from_first):
		return _fail("haoxi_discarded_not_in_discard_pile")
	# X = 2 - 2 = 0；本次不获得任何基本牌。
	if not _controller.state.get_player(0).hand.is_empty():
		return _fail("haoxi_two_target_draw=%d" % _controller.state.get_player(0).hand.size())
	if _controller.state.draw_pile.size() != 1:
		return _fail("haoxi_two_target_draw_pile=%d" % _controller.state.draw_pile.size())
	return true


## 校验【连戏】的完整链路：一轮重铸全部基本牌并等量补摸，重复七次后按Y=3造成伤害。
func _test_lianxi_recast_times_and_damage() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "huohua"
	# 火花手牌；全部为基本牌，用于确认“一次重铸所有基本牌”而不是只重铸一张。
	_add_hand_card(0, "sha", "spade", 7)
	_add_hand_card(0, "shan", "heart", 3)
	_add_hand_card(0, "tao", "club", 5)
	_add_hand_card(0, "jiu", "diamond", 9)
	# 摸牌堆；七轮重铸各补摸四张，因此至少需要 28 张实体牌。
	for draw_rank: int in range(1, 33):
		_add_draw_pile_card("shan", "club", draw_rank % 13 + 1)
	var lianxi: SkillDefinition = _install_single_skill(0, "lianxi")
	if lianxi == null or not lianxi.can_activate():
		return _fail("lianxi_can_activate")
	if not lianxi.activate().is_empty():
		return _fail("lianxi_activate")
	# 第1次窗口只提供“重铸所有基本牌”，避免0次重铸就结束的白发动路径。
	var first_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(first_choice.get("choice_type", "")) != "control" or str((first_choice.get("context", {}) as Dictionary).get("kind", "")) != "lianxi_recast":
		return _fail("lianxi_recast_request %s" % [first_choice])
	if (first_choice.get("control_options", []) as Array).size() != 1:
		return _fail("lianxi_first_options %s" % [first_choice.get("control_options", [])])
	# 连续重铸七次；每轮都先确认窗口仍是重铸流程，再提交“重铸所有基本牌”。
	for recast_index: int in range(7):
		if str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", "")) != "lianxi_recast":
			return _fail("lianxi_recast_window index=%d choice=%s" % [recast_index, _controller._pending_card_choice])
		# 重铸前手牌张数；重铸是等量换牌，因此张数必须保持不变。
		var hand_count_before: int = _controller.state.get_player(0).hand.size()
		if not _submit_pending_choice(0, [], [], true, "recast"):
			return false
		if _controller.state.get_player(0).hand.size() != hand_count_before:
			return _fail("lianxi_hand_count index=%d before=%d after=%d" % [recast_index, hand_count_before, _controller.state.get_player(0).hand.size()])
	# 七次用尽后窗口只剩“结束重铸并造成伤害”。
	var final_choice: Dictionary = _controller._pending_card_choice.duplicate(true)
	var final_options: Array = final_choice.get("control_options", []) as Array
	if final_options.size() != 1 or str((final_options[0] as Dictionary).get("id", "")) != "finish":
		return _fail("lianxi_final_options %s" % [final_options])
	if not _submit_pending_choice(0, [], [], true, "finish"):
		return false
	if str(_controller._pending_card_choice.get("choice_type", "")) != "target":
		return _fail("lianxi_target_request %s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [1], true):
		return false
	# Y = 7 / 2 向下取整 = 3；目标从4点体力降到1点。
	if _controller.state.get_player(1).hp != 1:
		return _fail("lianxi_damage hp=%d" % _controller.state.get_player(1).hp)
	return true


## 校验【连戏】在手牌没有基本牌时不开放入口，也不会创建空重铸窗口。
func _test_lianxi_requires_basic_card() -> bool:
	_reset_state(2)
	_controller.state.get_player(0).character_id = "huohua"
	# 只有锦囊牌；重铸不会发生任何事，因此技能入口必须保持关闭。
	_add_hand_card(0, "wuxie", "club", 9)
	var lianxi: SkillDefinition = _install_single_skill(0, "lianxi")
	if lianxi == null:
		return _fail("lianxi_missing")
	if lianxi.can_activate():
		return _fail("lianxi_activate_without_basic")
	var rejection: String = lianxi.activate()
	if rejection.is_empty() or _controller._pending_card_choice.size() > 0:
		return _fail("lianxi_activate_without_basic_message %s pending=%s" % [rejection, _controller._pending_card_choice])
	return true


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("HUOHUA_JOY_FAIL %s" % message)
	get_tree().quit(1)
	return false
