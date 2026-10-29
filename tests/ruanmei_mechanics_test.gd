extends Node

## 阮梅专项回归测试：校验【梅绽】【灵赋】【阮弦】的规则、全局限次、操作顺序与 AI 估值。
##
## 沿用 tests/*_mechanics_test.gd 的既有写法：直接实例化控制器、构造最小权威状态、通过正式 PlayerAction 提交选择，
## 只断言公开可观察结果（体力、体力上限、手牌、日志顺序、待响应请求）与技能公开接口。

## 阮梅武将稳定ID；元数据与技能顺序断言使用。
const RUANMEI_CHARACTER_ID: String = "ruanmei"

## 【梅绽】技能稳定ID；同时也是【灵赋】授予与【阮弦】检索的目标技能ID。
const MEIZHAN_SKILL_ID: String = "meizhan"

## 【灵赋】技能稳定ID。
const LINGFU_SKILL_ID: String = "lingfu"

## 【阮弦】技能稳定ID。
const RUANXIAN_SKILL_ID: String = "ruanxian"

## 玩家可见技能正文；必须与设计原文逐字相等。
## 【梅绽】原文使用两个**右**引号（”梅绽”），属于原文事实，不得顺手改成左引号。
const MEIZHAN_DESCRIPTION: String = "锁定技，当你受到伤害后，所有拥有技能”梅绽”的角色各摸一张牌。"

## 【灵赋】玩家可见正文。
const LINGFU_DESCRIPTION: String = "出牌阶段限一次，你可以重铸一张手牌（每种类别限一次），然后令一名角色获得技能“梅绽”。若其已拥有技能“梅绽”，则改为令其增加1点体力上限并回复1点体力，然后你失去此技能。"

## 【阮弦】玩家可见正文。
const RUANXIAN_DESCRIPTION: String = "结束阶段，你可以重铸一张锦囊牌（每种花色限一次），然后令所有拥有技能“梅绽”的其他角色各摸一张牌。"

## 全局限次记录键名；与技能源码中的常量保持一致，用于断言“失去技能后额度不复活”。
const LINGFU_USED_CATEGORIES_KEY: String = "lingfu_used_card_categories"

## 阮弦全局限次记录键名；同上。
const RUANXIAN_USED_SUITS_KEY: String = "ruanxian_used_suits"

## 本次测试权威控制器；使用与正式场景同类型的实例并手动装配必需子节点。
var _controller: MatchController

## 本次捕获的公开日志文本；按写入顺序保存，用于断言“先重铸、后效果”的顺序。
var _captured_logs: Array[String] = []

## 首个失败原因；为空表示全部通过。
var _failure: String = ""


## 运行全部断言；测试节点保持 ALWAYS，避免流程暂停阻断断言推进。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_controller()
	call_deferred("_run")


## 依次执行全部用例；任一失败立即以非零状态结束。
func _run() -> void:
	_run_case(_test_ruanmei_metadata)
	_run_case(_test_ruanmei_description_verbatim)
	_run_case(_test_meizhan_multi_holder_draw)
	_run_case(_test_meizhan_shield_absorbed_no_trigger)
	_run_case(_test_meizhan_dynamic_sell_blood)
	_run_case(_test_lingfu_grant_branch)
	_run_case(_test_lingfu_upgrade_branch)
	_run_case(_test_lingfu_self_target)
	_run_case(_test_lingfu_global_quota)
	_run_case(_test_lingfu_phase_limit)
	_run_case(_test_ruanxian_other_holders_only)
	_run_case(_test_ruanxian_suit_quota)
	_run_case(_test_ruanxian_no_holder_no_request)
	_run_case(_test_ruanxian_nested_barrier)
	_run_case(_test_lingfu_ai_priority_and_cost)
	_run_case(_test_ruanxian_ai_sign)
	if not _failure.is_empty():
		printerr("RUANMEI_MECHANICS_FAIL %s" % _failure)
		if _controller != null:
			_controller.free()
		get_tree().quit(1)
		return
	print("RUANMEI_MECHANICS_PASS metadata=1 verbatim=3 meizhan=3 lingfu=5 ruanxian=4 ai=2")
	if _controller != null:
		_controller.free()
	get_tree().quit(0)


## 执行单个用例；失败时记录原因并停止后续用例。
func _run_case(case: Callable) -> void:
	if not _failure.is_empty():
		return
	case.call()


## 创建与正式场景同类型的控制器，并订阅公开日志；不加载界面，保持规则断言隔离。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能时机订阅与正式实现保持一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保持正式实现，避免技能与态度查询走空分支。
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
	_controller.log_added.connect(_on_log_added)


## 为单项测试创建最小权威状态并重建全部规则服务；身份公开以获得确定AI态度。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "ruanmei-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号忠臣、三号及以后反贼，形成稳定且可预期的敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "阮梅测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("loyalist" if player_id == 2 else "rebel")
		player.identity_revealed = true
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	# 摸牌堆；【梅绽】与重铸补摸断言都需要足够的可用实体牌。
	for card_index: int in range(30):
		_controller.state.draw_pile.append(CardInstance.new("shan", "heart", card_index % 13 + 1))
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._queued_equipment_triggers.clear()
	_captured_logs.clear()


## 安装一个运行时技能实例；走与正式安装相同的 bind + install 路径，保证时机订阅真实生效。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		_fail("install_missing_skill %s" % skill_id)
		return null
	skill.bind(_controller, player_id)
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 把一张实体牌直接放入指定玩家的普通手牌区；测试需要绕过摸牌流程构造确定手牌。
func _give_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	var player: PlayerState = _controller.state.get_player(player_id)
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	# 持有者与区域；正式对局由移动服务在写入玩家区域时补齐，测试直接入区必须自己写。
	card.owner_id = player_id
	card.zone = "hand"
	player.hand.append(card)
	return card


## 通过正式 PlayerAction 入口提交当前待响应选择；与真实界面提交协议完全一致。
func _submit_choice(actor_id: int, card_uids: Array[int], target_ids: Array[int], confirmed: bool) -> bool:
	if _controller._pending_card_choice.is_empty():
		_fail("missing_pending_choice")
		return false
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":card_uids.duplicate(), "selected_target_ids":target_ids.duplicate(), "selected_control_id":"", "confirmed":confirmed}
	if not _controller.submit_action(action):
		_fail("choice_rejected request=%d payload=%s pending=%s" % [request_id, action.payload, _controller._pending_card_choice])
		return false
	return true


## 返回当前待响应请求的业务键；没有请求时返回空字符串。
func _pending_kind() -> String:
	return str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))


## 构造与本项目 AI 入口一致的权威快照；必须补写限定技用量与实际安装技能列表。
func _build_snapshot(viewer_id: int) -> Dictionary:
	var snapshot: Dictionary = _controller.state.to_dict(viewer_id, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	return snapshot


## 校验武将静态资料与技能顺序。
func _test_ruanmei_metadata() -> void:
	var definition: Dictionary = GameDatabase.get_character(RUANMEI_CHARACTER_ID)
	if str(definition.get("faction", "")) != "yinhexvezhe" or int(definition.get("max_hp", 0)) != 3 or str(definition.get("gender", "")) != "female":
		_fail("ruanmei_metadata faction=%s hp=%s gender=%s" % [definition.get("faction", ""), definition.get("max_hp", 0), definition.get("gender", "")])
		return
	if (definition.get("skills", []) as Array) != [MEIZHAN_SKILL_ID, LINGFU_SKILL_ID, RUANXIAN_SKILL_ID]:
		_fail("ruanmei_skill_order %s" % str(definition.get("skills", [])))
		return
	# 三个技能必须都能被数据库工厂实例化，且脚本与元数据一一对应。
	for skill_id: String in [MEIZHAN_SKILL_ID, LINGFU_SKILL_ID, RUANXIAN_SKILL_ID]:
		if GameDatabase.create_skill(skill_id) == null:
			_fail("ruanmei_skill_missing %s" % skill_id)
			return
	# 开局选将可用：阮梅必须进入普通可选武将池，且显示名可解析；否则武将存在却永远选不到。
	if not GameDatabase.get_selectable_character_ids().has(RUANMEI_CHARACTER_ID):
		_fail("ruanmei_not_selectable special=%s" % str(definition.get("special", false)))
		return
	if GameDatabase.resolve_character_name(RUANMEI_CHARACTER_ID) != "阮梅":
		_fail("ruanmei_display_name %s" % GameDatabase.resolve_character_name(RUANMEI_CHARACTER_ID))
		return


## 校验三个技能正文与设计原文逐字相等；【梅绽】必须保留原文的两个右引号。
func _test_ruanmei_description_verbatim() -> void:
	var expected: Dictionary = {
		MEIZHAN_SKILL_ID:MEIZHAN_DESCRIPTION,
		LINGFU_SKILL_ID:LINGFU_DESCRIPTION,
		RUANXIAN_SKILL_ID:RUANXIAN_DESCRIPTION,
	}
	for skill_id: String in expected.keys():
		var actual: String = str(GameDatabase.get_skill(skill_id).get("description", ""))
		if actual != str(expected[skill_id]):
			_fail("ruanmei_description %s actual=%s" % [skill_id, actual])
			return
	# 【梅绽】的两个引号都必须是右引号；左引号出现即说明原文被“修正”过。
	var meizhan_text: String = str(GameDatabase.get_skill(MEIZHAN_SKILL_ID).get("description", ""))
	if not meizhan_text.contains("技能”梅绽”的角色"):
		_fail("meizhan_quotes %s" % meizhan_text)
		return


## 校验【梅绽】：任一持有者受伤后，所有持有者各摸一张牌，未持有者不摸。
func _test_meizhan_multi_holder_draw() -> void:
	_reset_state(3)
	_install_skill(0, MEIZHAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	# 摸牌堆基线；两名持有者各摸一张，未持有的2号不摸。
	var draw_pile_before: int = _controller.state.draw_pile.size()
	_controller.damage(2, 0, 1, "normal", "test")
	if _controller.state.get_player(0).hand.size() != 1 or _controller.state.get_player(1).hand.size() != 1:
		_fail("meizhan_holders_hand %d/%d" % [_controller.state.get_player(0).hand.size(), _controller.state.get_player(1).hand.size()])
		return
	if not _controller.state.get_player(2).hand.is_empty():
		_fail("meizhan_non_holder_drew %d" % _controller.state.get_player(2).hand.size())
		return
	if _controller.state.draw_pile.size() != draw_pile_before - 2:
		_fail("meizhan_draw_count %d" % (_draw_pile_before_used(draw_pile_before)))
		return
	# 一次伤害事件只触发一次：2点伤害仍是各摸一张，而不是各摸两张。
	_reset_state(3)
	_install_skill(0, MEIZHAN_SKILL_ID)
	draw_pile_before = _controller.state.draw_pile.size()
	_controller.damage(1, 0, 2, "normal", "test")
	if _controller.state.get_player(0).hand.size() != 1 or _controller.state.draw_pile.size() != draw_pile_before - 1:
		_fail("meizhan_per_damage_event hand=%d" % _controller.state.get_player(0).hand.size())
		return
	# 动态归属：通过统一端口临时授予后立刻参与摸牌。
	_reset_state(3)
	_install_skill(0, MEIZHAN_SKILL_ID)
	if not _controller.grant_temporary_skill(2, MEIZHAN_SKILL_ID, 99):
		_fail("meizhan_grant_temporary")
		return
	_controller.damage(1, 0, 1, "normal", "test")
	if _controller.state.get_player(2).hand.size() != 1:
		_fail("meizhan_granted_holder_drew %d" % _controller.state.get_player(2).hand.size())
		return


## 返回自基线以来实际消耗的摸牌数；仅用于失败信息，避免断言表达式里出现长计算。
func _draw_pile_before_used(draw_pile_before: int) -> int:
	return draw_pile_before - _controller.state.draw_pile.size()


## 校验护盾全额吸收（hp_lost == 0）时【梅绽】不触发。
func _test_meizhan_shield_absorbed_no_trigger() -> void:
	_reset_state(3)
	_install_skill(0, MEIZHAN_SKILL_ID)
	_controller.state.get_player(0).shield = 5
	var draw_pile_before: int = _controller.state.draw_pile.size()
	_controller.damage(2, 0, 1, "normal", "test")
	if not _controller.state.get_player(0).hand.is_empty() or _controller.state.draw_pile.size() != draw_pile_before:
		_fail("meizhan_shield_absorbed drew=%d" % _controller.state.get_player(0).hand.size())
		return
	# 已失去【梅绽】的角色不再参与摸牌；拥有判定走统一入口，不依赖任何名单。
	_reset_state(3)
	_install_skill(0, MEIZHAN_SKILL_ID)
	if not _controller.remove_skill(0, MEIZHAN_SKILL_ID, "test"):
		_fail("meizhan_remove_skill")
		return
	draw_pile_before = _controller.state.draw_pile.size()
	_controller.damage(2, 0, 1, "normal", "test")
	if not _controller.state.get_player(0).hand.is_empty() or _controller.state.draw_pile.size() != draw_pile_before:
		_fail("meizhan_removed_still_drew %d" % _controller.state.get_player(0).hand.size())
		return


## 校验【梅绽】的卖血价值：静态口径为1.0，动态修正只对伤害牌生效且符号随敌我分布翻转。
## 收入现由统一钩子包含受伤者本人，并按态度强度加权；旧来牌钩子对任何牌都保持原分，避免重复收入。
func _test_meizhan_dynamic_sell_blood() -> void:
	_reset_state(4)
	# 受伤者1号持有“梅绽”；2号是队友、3号是敌人，分别构成“净+1”与“净-1”两种分布。
	# 通过统一的“局内获得”端口授予，使快照同时带上实例与获得记录，与真实对局一致。
	if not _controller.grant_acquired_skill(1, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("meizhan_grant_victim")
		return
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	var snapshot: Dictionary = _build_snapshot(0)
	# 静态卖血价值必须为正：【闪避决策】依赖 > 0 判定“是否卖血角色”。
	if not is_equal_approx(evaluator.get_snapshot_sell_blood_value(_player_snapshot(snapshot, 1)), 1.0):
		_fail("meizhan_static_sell_blood %f" % evaluator.get_snapshot_sell_blood_value(_player_snapshot(snapshot, 1)))
		return
	var meizhan: SkillDefinition = GameDatabase.create_skill(MEIZHAN_SKILL_ID)
	meizhan.bind(null, 0)
	# 只有受伤者一人持有：受伤者自己那一份已由静态项按态度符号计入，动态修正必须为0，不能重复计算。
	if not is_equal_approx(meizhan.score_ai_damage_benefit(snapshot, 0, 1, 1, 1, 0, evaluator), evaluator.score_resource_change(snapshot, 0, 1, 1, 0)):
		_fail("meizhan_solo_dynamic %f" % meizhan.modify_ai_incoming_card_effect(snapshot, 0, 1, {}, {"damage":true}, 0.0, 1, 0.0, evaluator))
		return
	# 非伤害牌不触发“受到伤害后”。
	if not is_zero_approx(meizhan.modify_ai_incoming_card_effect(snapshot, 0, 1, {}, {"damage":false}, 0.0, 1, 0.0, evaluator)):
		_fail("meizhan_non_damage_modified")
		return
	# 队友持有者：本次伤害整体有利于出手方，修正为正。
	if not _controller.grant_acquired_skill(2, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("meizhan_grant_ally")
		return
	snapshot = _build_snapshot(0)
	if meizhan.score_ai_damage_benefit(snapshot, 0, 1, 1, 1, 0, evaluator) <= evaluator.score_resource_change(snapshot, 0, 1, 1, 0):
		_fail("meizhan_ally_holder_not_positive")
		return
	# 敌方持有者：本次伤害整体有害于出手方，修正为负。
	_controller.remove_skill(2, MEIZHAN_SKILL_ID, "test")
	if not _controller.grant_acquired_skill(3, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("meizhan_grant_enemy")
		return
	snapshot = _build_snapshot(0)
	if meizhan.score_ai_damage_benefit(snapshot, 0, 1, 1, 1, 0, evaluator) >= evaluator.score_resource_change(snapshot, 0, 1, 1, 0):
		_fail("meizhan_enemy_holder_not_negative")
		return
	# 【百折】的既有卖血估值不受本次改动影响；固有技能必须真实安装，否则快照会按“实际安装”裁剪掉它。
	_reset_state(3)
	_controller.state.get_player(1).character_id = "luka"
	_install_skill(1, "baizhe")
	var baizhe_snapshot: Dictionary = _build_snapshot(0)
	if not is_equal_approx(evaluator.get_snapshot_sell_blood_value(_player_snapshot(baizhe_snapshot, 1)), 1.0):
		_fail("baizhe_sell_blood_regressed %f" % evaluator.get_snapshot_sell_blood_value(_player_snapshot(baizhe_snapshot, 1)))
		return


## 从权威快照中取出指定玩家的玩家快照；缺失时返回空字典。
func _player_snapshot(snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in snapshot.get("players", []) as Array:
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}


## 校验【灵赋】分支一：先重铸补摸、后授予技能，且新持有者随后能触发【梅绽】。
func _test_lingfu_grant_branch() -> void:
	_reset_state(3)
	var lingfu: SkillDefinition = _install_skill(0, LINGFU_SKILL_ID)
	# 阮梅固有拥有“梅绽”；1号尚未拥有，是本次授予的目标。
	_install_skill(0, MEIZHAN_SKILL_ID)
	# 一张基本牌作为材料；1号尚未拥有“梅绽”。
	var material: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var draw_pile_before: int = _controller.state.draw_pile.size()
	if lingfu == null or not lingfu.can_activate():
		_fail("lingfu_grant_cannot_activate")
		return
	lingfu.activate({})
	if _pending_kind() != "lingfu_grant_target":
		_fail("lingfu_grant_request %s" % _pending_kind())
		return
	if not _submit_choice(0, [material.uid], [1], true):
		return
	# 先重铸：材料已进入弃牌堆，并补摸一张，手牌总数不变。
	if not _controller.state.discard_pile.has(material) or _controller.state.draw_pile.size() != draw_pile_before - 1:
		_fail("lingfu_recast_not_first discard=%s pile=%d" % [_controller.state.discard_pile.has(material), _controller.state.draw_pile.size()])
		return
	# 后效果：1号获得“梅绽”，且全局限次已记账。
	if not _controller.has_skill(1, MEIZHAN_SKILL_ID):
		_fail("lingfu_grant_missing")
		return
	if not (_controller.state.get_player(0).character_form_state.get(LINGFU_USED_CATEGORIES_KEY, []) as Array).has("basic"):
		_fail("lingfu_quota_not_recorded %s" % str(_controller.state.get_player(0).character_form_state))
		return
	# 顺序断言：公开日志中“重铸”必须早于“获得技能”。
	var recast_index: int = _log_index_containing("重铸了")
	var grant_index: int = _log_index_containing("获得了技能【梅绽】")
	if recast_index < 0 or grant_index < 0 or recast_index > grant_index:
		_fail("lingfu_order recast=%d grant=%d logs=%s" % [recast_index, grant_index, str(_captured_logs)])
		return
	# 新持有者随后受伤必须触发【梅绽】；1号与阮梅各摸一张。
	var hand_before: int = _controller.state.get_player(1).hand.size()
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	_controller.damage(2, 1, 1, "normal", "test")
	if _controller.state.get_player(1).hand.size() != hand_before + 1 or _controller.state.get_player(0).hand.size() != owner_hand_before + 1:
		_fail("lingfu_granted_holder_meizhan %d/%d" % [_controller.state.get_player(1).hand.size(), _controller.state.get_player(0).hand.size()])
		return


## 返回公开日志中首个包含指定文本的下标；不存在时返回-1。
func _log_index_containing(text: String) -> int:
	for log_index: int in range(_captured_logs.size()):
		if _captured_logs[log_index].contains(text):
			return log_index
	return -1


## 校验【灵赋】分支二：目标已拥有“梅绽”时增加体力上限、回复体力，并令阮梅失去【灵赋】。
func _test_lingfu_upgrade_branch() -> void:
	_reset_state(3)
	var lingfu: SkillDefinition = _install_skill(0, LINGFU_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	# 1号先受伤，使回复体力可观察；材料为一张锦囊牌。
	_controller.state.get_player(1).hp = 2
	var material: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	if lingfu.activate({}) != "":
		_fail("lingfu_upgrade_activate")
		return
	if not _submit_choice(0, [material.uid], [1], true):
		return
	var target: PlayerState = _controller.state.get_player(1)
	if target.max_hp != 5 or target.hp != 3:
		_fail("lingfu_upgrade_stats max_hp=%d hp=%d" % [target.max_hp, target.hp])
		return
	# 阮梅失去【灵赋】；统一拥有查询必须立刻反映。
	if _controller.has_skill(0, LINGFU_SKILL_ID) or lingfu.can_activate():
		_fail("lingfu_not_lost")
		return
	# 目标仍只有一份“梅绽”，不会被重复授予。
	if not _controller.has_skill(1, MEIZHAN_SKILL_ID):
		_fail("lingfu_upgrade_lost_meizhan")
		return
	# 取消请求不消耗任何额度，也不移动材料。
	_reset_state(3)
	lingfu = _install_skill(0, LINGFU_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	var kept_material: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	lingfu.activate({})
	if not _submit_choice(0, [], [], false):
		return
	if not _controller.state.get_player(0).hand.has(kept_material) or not _controller.has_skill(0, LINGFU_SKILL_ID) or not lingfu.can_activate():
		_fail("lingfu_cancel_consumed")
		return
	if not (_controller.state.get_player(0).character_form_state.get(LINGFU_USED_CATEGORIES_KEY, []) as Array).is_empty():
		_fail("lingfu_cancel_recorded_quota")
		return


## 校验【灵赋】可以选择自己，且自己固有拥有“梅绽”时必定进入分支二。
func _test_lingfu_self_target() -> void:
	_reset_state(3)
	var lingfu: SkillDefinition = _install_skill(0, LINGFU_SKILL_ID)
	_install_skill(0, MEIZHAN_SKILL_ID)
	_controller.state.get_player(0).hp = 2
	var material: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	if lingfu.activate({}) != "":
		_fail("lingfu_self_activate")
		return
	# 目标候选必须包含自己。
	var target_ids: Array = _controller._pending_card_choice.get("target_ids", []) as Array
	if not target_ids.has(0):
		_fail("lingfu_self_not_candidate %s" % str(target_ids))
		return
	if not _submit_choice(0, [material.uid], [0], true):
		return
	var owner: PlayerState = _controller.state.get_player(0)
	if owner.max_hp != 5 or owner.hp != 3 or _controller.has_skill(0, LINGFU_SKILL_ID):
		_fail("lingfu_self_branch max_hp=%d hp=%d lingfu=%s" % [owner.max_hp, owner.hp, _controller.has_skill(0, LINGFU_SKILL_ID)])
		return


## 校验【灵赋】的“每种类别限一次”是整局额度：同类第二次被拒，失去技能后重新获得也不复活。
func _test_lingfu_global_quota() -> void:
	_reset_state(3)
	var lingfu: SkillDefinition = _install_skill(0, LINGFU_SKILL_ID)
	# 两张基本牌与一张锦囊牌；基本牌额度用尽后基本牌不再进入候选。
	var first_basic: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var second_basic: CardInstance = _give_hand_card(0, "shan", "club", 3)
	var trick_card: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	lingfu.activate({})
	if not _submit_choice(0, [first_basic.uid], [1], true):
		return
	# 下一出牌阶段恢复“每阶段一次”，但基本牌类别已用尽，因此候选里只剩锦囊牌。
	_emit_play_phase_begin(0)
	if not lingfu.can_activate():
		_fail("lingfu_next_phase_blocked")
		return
	lingfu.activate({})
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == second_basic.uid:
			_fail("lingfu_basic_quota_revived")
			return
	if not _submit_choice(0, [trick_card.uid], [1], true):
		return
	# 失去【灵赋】后重新获得：全局限次记录仍在，已用类别不得复活。
	_controller.remove_skill(0, LINGFU_SKILL_ID, "test")
	lingfu = _install_skill(0, LINGFU_SKILL_ID)
	_emit_play_phase_begin(0)
	if not (_controller.state.get_player(0).character_form_state.get(LINGFU_USED_CATEGORIES_KEY, []) as Array).has("basic"):
		_fail("lingfu_quota_record_lost")
		return
	# 手牌只剩基本牌时不能发动；额度未随失去技能而复原。
	var third_basic: CardInstance = _give_hand_card(0, "tao", "diamond", 5)
	if lingfu.can_activate():
		_fail("lingfu_quota_revived_after_regrant")
		return
	# 存档往返：全局限次必须随权威快照序列化并在恢复后原样保留，否则一次存读档就能洗掉额度。
	var restored: PlayerState = PlayerState.from_authoritative_dict(_controller.state.get_player(0).to_dict(-1, true))
	if not (restored.character_form_state.get(LINGFU_USED_CATEGORIES_KEY, []) as Array).has("basic"):
		_fail("lingfu_quota_lost_across_save_load %s" % str(restored.character_form_state))
		return
	# 取消的锦囊请求不会写入额度；这里用一次未提交的请求确认候选与额度解耦。
	if not _controller.state.get_player(0).hand.has(third_basic):
		_fail("lingfu_quota_hand_mutated")
		return


## 校验【灵赋】的“出牌阶段限一次”：同一阶段第二次被拒，额外出牌阶段恢复一次额度。
func _test_lingfu_phase_limit() -> void:
	_reset_state(3)
	var lingfu: SkillDefinition = _install_skill(0, LINGFU_SKILL_ID)
	var basic: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	var trick_card: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	lingfu.activate({})
	if not _submit_choice(0, [basic.uid], [1], true):
		return
	# 同一出牌阶段：即使仍有未用类别，也不能再次发动。
	if lingfu.can_activate():
		_fail("lingfu_same_phase_reusable")
		return
	# 额外出牌阶段派发同一个 phaseUseBegin，额度恢复一次。
	_emit_play_phase_begin(0)
	if not lingfu.can_activate():
		_fail("lingfu_extra_phase_blocked")
		return
	lingfu.activate({})
	if not _submit_choice(0, [trick_card.uid], [1], true):
		return
	# 非出牌阶段不能发动。
	_emit_play_phase_begin(0)
	_controller.state.current_phase = "discard"
	if lingfu.can_activate():
		_fail("lingfu_activated_outside_play_phase")
		return


## 派发指定角色的出牌阶段开始时机；额外出牌阶段在规则上派发同一个时机。
func _emit_play_phase_begin(player_id: int) -> void:
	_controller._emit_rule_timing("phaseUseBegin", player_id, player_id, -1, {"turn_number":_controller.state.turn_number})


## 校验【阮弦】：只有**其他**“梅绽”持有者摸牌，阮梅自己不摸。
func _test_ruanxian_other_holders_only() -> void:
	_reset_state(3)
	var ruanxian: SkillDefinition = _install_skill(0, RUANXIAN_SKILL_ID)
	# 阮梅自己固有拥有“梅绽”，但【阮弦】的“其他角色”明确排除她自己。
	_install_skill(0, MEIZHAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	var trick_card: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	var owner_hand_before: int = _controller.state.get_player(0).hand.size()
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if _pending_kind() != "ruanxian_recast_trick":
		_fail("ruanxian_request %s" % _pending_kind())
		return
	if not _submit_choice(0, [trick_card.uid], [], true):
		return
	# 1号摸一张；阮梅自己因为重铸补摸一张，但没有额外的【阮弦】摸牌。
	if _controller.state.get_player(1).hand.size() != 1:
		_fail("ruanxian_other_holder_hand %d" % _controller.state.get_player(1).hand.size())
		return
	if _controller.state.get_player(0).hand.size() != owner_hand_before:
		_fail("ruanxian_owner_drew %d/%d" % [_controller.state.get_player(0).hand.size(), owner_hand_before])
		return
	if not (_controller.state.get_player(0).character_form_state.get(RUANXIAN_USED_SUITS_KEY, []) as Array).has("heart"):
		_fail("ruanxian_suit_not_recorded %s" % str(_controller.state.get_player(0).character_form_state))
		return
	# 不拥有“梅绽”的角色不摸牌。
	_reset_state(3)
	ruanxian = _install_skill(0, RUANXIAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	trick_card = _give_hand_card(0, "wuzhong", "spade", 4)
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if not _submit_choice(0, [trick_card.uid], [], true):
		return
	if not _controller.state.get_player(2).hand.is_empty():
		_fail("ruanxian_non_holder_drew %d" % _controller.state.get_player(2).hand.size())
		return
	# 材料必须是锦囊牌：基本牌不出现在候选里。
	_reset_state(3)
	ruanxian = _install_skill(0, RUANXIAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	var basic_only: CardInstance = _give_hand_card(0, "sha", "spade", 7)
	if ruanxian != null and _has_ruanxian_candidate(basic_only.uid):
		_fail("ruanxian_basic_candidate")
		return


## 判断当前【阮弦】请求的候选里是否包含指定实体牌。
func _has_ruanxian_candidate(card_uid: int) -> bool:
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if _pending_kind() != "ruanxian_recast_trick":
		return false
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == card_uid:
			return true
	return false


## 校验【阮弦】的“每种花色限一次”：同花色第二次被拒，不同花色独立计数。
func _test_ruanxian_suit_quota() -> void:
	_reset_state(3)
	var ruanxian: SkillDefinition = _install_skill(0, RUANXIAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	var heart_trick: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	var spade_trick: CardInstance = _give_hand_card(0, "nanman", "spade", 9)
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if not _submit_choice(0, [heart_trick.uid], [], true):
		return
	# 同一花色第二次被拒：心牌额度已用，候选里不能再出现心牌。
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if _pending_kind() != "ruanxian_recast_trick":
		_fail("ruanxian_second_request %s" % _pending_kind())
		return
	if _has_candidate_uid(heart_trick.uid):
		_fail("ruanxian_heart_quota_revived")
		return
	if not _has_candidate_uid(spade_trick.uid):
		_fail("ruanxian_spade_missing")
		return
	if not _submit_choice(0, [spade_trick.uid], [], true):
		return
	var used_suits: Array = _controller.state.get_player(0).character_form_state.get(RUANXIAN_USED_SUITS_KEY, []) as Array
	if not used_suits.has("heart") or not used_suits.has("spade"):
		_fail("ruanxian_used_suits %s" % str(used_suits))
		return
	# 失去技能后重新获得：已用花色不复活。
	_controller.remove_skill(0, RUANXIAN_SKILL_ID, "test")
	ruanxian = _install_skill(0, RUANXIAN_SKILL_ID)
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if _pending_kind() == "ruanxian_recast_trick" and (_has_candidate_uid(heart_trick.uid) or _has_candidate_uid(spade_trick.uid)):
		_fail("ruanxian_suit_quota_revived_after_regrant")
		return
	if not _controller.state.get_player(0).character_form_state.has(RUANXIAN_USED_SUITS_KEY):
		_fail("ruanxian_suit_record_lost")
		return
	# 存档往返：已用花色必须随权威快照序列化并在恢复后原样保留。
	var restored: PlayerState = PlayerState.from_authoritative_dict(_controller.state.get_player(0).to_dict(-1, true))
	var restored_suits: Array = restored.character_form_state.get(RUANXIAN_USED_SUITS_KEY, []) as Array
	if not restored_suits.has("heart") or not restored_suits.has("spade"):
		_fail("ruanxian_suit_lost_across_save_load %s" % str(restored.character_form_state))
		return


## 判断当前待响应请求的候选里是否包含指定实体牌。
func _has_candidate_uid(card_uid: int) -> bool:
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == card_uid:
			return true
	return false


## 校验【阮弦】：场上没有其他“梅绽”持有者时不创建任何选择请求。
func _test_ruanxian_no_holder_no_request() -> void:
	_reset_state(3)
	_install_skill(0, RUANXIAN_SKILL_ID)
	_install_skill(0, MEIZHAN_SKILL_ID)
	_give_hand_card(0, "wuzhong", "heart", 4)
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		_fail("ruanxian_solo_request %s" % _pending_kind())
		return
	# 没有可用锦囊牌时同样不创建请求。
	_reset_state(3)
	_install_skill(0, RUANXIAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	_give_hand_card(0, "sha", "spade", 7)
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		_fail("ruanxian_no_material_request %s" % _pending_kind())
		return


## 校验【阮弦】：结束阶段存在嵌套屏障时登记重建入口，而不是静默丢弃请求。
func _test_ruanxian_nested_barrier() -> void:
	_reset_state(3)
	var ruanxian: SkillDefinition = _install_skill(0, RUANXIAN_SKILL_ID)
	_install_skill(1, MEIZHAN_SKILL_ID)
	var trick_card: CardInstance = _give_hand_card(0, "wuzhong", "heart", 4)
	# 人为制造嵌套屏障：装备触发队列非空时 has_nested_settlement_barrier() 为真。
	_controller._queued_equipment_triggers.append({})
	_controller._emit_rule_timing("phaseEnd", 0, 0, -1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		_fail("ruanxian_barrier_created_request %s" % _pending_kind())
		return
	if _controller._deferred_skill_settlements.is_empty():
		_fail("ruanxian_barrier_no_rebuild_entry")
		return
	if str((_controller._deferred_skill_settlements[0].get("context", {}) as Dictionary).get("kind", "")) != "ruanxian_rebuild_entry":
		_fail("ruanxian_barrier_entry %s" % str(_controller._deferred_skill_settlements))
		return
	# 屏障解除后重建同一条请求；重建期间材料仍然合法。
	_controller._queued_equipment_triggers.clear()
	_controller._resume_deferred_skill_settlements()
	if _pending_kind() != "ruanxian_recast_trick" or not _has_candidate_uid(trick_card.uid):
		_fail("ruanxian_barrier_rebuild %s" % _pending_kind())
		return
	# 重建后的请求与首次请求行为一致：确认后先重铸补摸一张，再令其他持有者摸一张，因此摸牌堆共少两张。
	var draw_pile_before: int = _controller.state.draw_pile.size()
	if not _submit_choice(0, [trick_card.uid], [], true):
		return
	if not _controller.state.discard_pile.has(trick_card) or _controller.state.draw_pile.size() != draw_pile_before - 2:
		_fail("ruanxian_barrier_recast discard=%s pile=%d before=%d" % [_controller.state.discard_pile.has(trick_card), _controller.state.draw_pile.size(), draw_pile_before])
		return
	if _controller.state.get_player(1).hand.size() != 1:
		_fail("ruanxian_barrier_draw %d" % _controller.state.get_player(1).hand.size())
		return
	if ruanxian == null:
		_fail("ruanxian_barrier_install")
		return


## 校验【灵赋】AI：三级优先顺序、费用两层同源、敌方目标严格负分。
func _test_lingfu_ai_priority_and_cost() -> void:
	# 五人局：0号领袖、1/3/4号反贼、2号忠臣，因此初始队友只有2号。
	_reset_state(5)
	var lingfu: SkillDefinition = _install_skill(0, LINGFU_SKILL_ID)
	# 阮梅固有拥有“梅绽”，因此自己始终落在“已拥有”池里，不会被当成一级授予目标。
	# 快照侧的拥有判定只认四类来源（固有/模式/临时/局内获得），因此必须同时写入武将ID并真实安装。
	_controller.state.get_player(0).character_id = RUANMEI_CHARACTER_ID
	_install_skill(0, MEIZHAN_SKILL_ID)
	_give_hand_card(0, "sha", "spade", 7)
	_give_hand_card(0, "wuzhong", "heart", 4)
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	lingfu.bind(null, 0)
	var action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":LINGFU_SKILL_ID, "payload":{"skill_id":LINGFU_SKILL_ID}}
	# 一级优先：唯一的队友2号还没有“梅绽”，应给出正分并选中他。
	if lingfu.score_ai_action(_build_snapshot(0), action, evaluator) <= 0.0:
		_fail("lingfu_ai_grant_score %f" % lingfu.score_ai_action(_build_snapshot(0), action, evaluator))
		return
	if lingfu._pick_ai_target(_build_snapshot(0), evaluator) != 2:
		_fail("lingfu_ai_level1 %d" % lingfu._pick_ai_target(_build_snapshot(0), evaluator))
		return
	# 二级：队友已拥有“梅绽”时改走升级分支，仍然选中该队友。
	if not _controller.grant_acquired_skill(2, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("lingfu_ai_grant_teammate")
		return
	if lingfu._pick_ai_target(_build_snapshot(0), evaluator) != 2:
		_fail("lingfu_ai_level2 %d" % lingfu._pick_ai_target(_build_snapshot(0), evaluator))
		return
	# 三级：3号也成为拥有“梅绽”的队友；两名候选收益相同时取体力值最低者。
	_controller.state.get_player(3).identity = "loyalist"
	if not _controller.grant_acquired_skill(3, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("lingfu_ai_grant_second_teammate")
		return
	_controller.state.get_player(2).hp = 4
	_controller.state.get_player(3).hp = 1
	if lingfu._pick_ai_target(_build_snapshot(0), evaluator) != 3:
		_fail("lingfu_ai_level3_low_hp %d" % lingfu._pick_ai_target(_build_snapshot(0), evaluator))
		return
	_controller.state.get_player(2).hp = 1
	_controller.state.get_player(3).hp = 4
	if lingfu._pick_ai_target(_build_snapshot(0), evaluator) != 2:
		_fail("lingfu_ai_level3_switch %d" % lingfu._pick_ai_target(_build_snapshot(0), evaluator))
		return
	# 自己与队友体力相同时优先队友：对自己发动会失去【灵赋】，扣掉技能损失后毛收益更低。
	_controller.state.get_player(0).hp = 1
	if lingfu._pick_ai_target(_build_snapshot(0), evaluator) != 2:
		_fail("lingfu_ai_self_preferred %d" % lingfu._pick_ai_target(_build_snapshot(0), evaluator))
		return
	# 敌方目标一律严格负分：没有“梅绽”的敌方是白送技能，已有“梅绽”的敌方是资敌。
	if lingfu._score_target_gross(_build_snapshot(0), 1, evaluator) >= 0.0:
		_fail("lingfu_ai_enemy_grant %f" % lingfu._score_target_gross(_build_snapshot(0), 1, evaluator))
		return
	if not _controller.grant_acquired_skill(4, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("lingfu_ai_grant_enemy")
		return
	if lingfu._score_target_gross(_build_snapshot(0), 4, evaluator) >= 0.0:
		_fail("lingfu_ai_enemy_upgrade %f" % lingfu._score_target_gross(_build_snapshot(0), 4, evaluator))
		return
	# 费用两层同源：用“AI 实际会选中的最低价值材料”构造确认动作，选择层评分必须等于动作层评分。
	var snapshot: Dictionary = _build_snapshot(0)
	var chosen_target: int = lingfu._pick_ai_target(snapshot, evaluator)
	# 手牌中保留价值最低的候选；AI 在多个候选中总是选择它。
	var cheapest_uid: int = -1
	var cheapest_value: float = INF
	for card_variant: Variant in _controller.state.get_player(0).hand:
		var card: CardInstance = card_variant as CardInstance
		var card_value: float = evaluator.get_card_value_by_id(card.definition_id, snapshot, 0)
		if card_value < cheapest_value:
			cheapest_value = card_value
			cheapest_uid = card.uid
	if cheapest_uid < 0:
		_fail("lingfu_ai_no_material")
		return
	var choice_request: Dictionary = {"context":{"kind":"lingfu_grant_target"}, "candidates":_controller.get_hand_candidates(0, 0)}
	var confirm_action: Dictionary = {"payload":{"confirmed":true, "selected_target_ids":[chosen_target], "selected_card_uids":[cheapest_uid]}}
	var choice_score: float = lingfu.score_ai_choice(snapshot, choice_request, confirm_action, evaluator)
	var action_score: float = lingfu.score_ai_action(snapshot, action, evaluator)
	if not is_equal_approx(choice_score, action_score):
		_fail("lingfu_ai_cost_mismatch choice=%f action=%f" % [choice_score, action_score])
		return
	# 取消恒为0分；目标或材料数量不足时给严格负分。
	var cancel_action: Dictionary = {"payload":{"confirmed":false, "selected_target_ids":[], "selected_card_uids":[]}}
	if not is_zero_approx(lingfu.score_ai_choice(snapshot, choice_request, cancel_action, evaluator)):
		_fail("lingfu_ai_cancel_not_zero")
		return
	if lingfu.score_ai_choice(snapshot, choice_request, {"payload":{"confirmed":true, "selected_target_ids":[], "selected_card_uids":[cheapest_uid]}}, evaluator) >= 0.0:
		_fail("lingfu_ai_missing_target_not_negative")
		return


## 校验【阮弦】AI：受益队友为正、敌方持有者为负、取消恒为0分。
func _test_ruanxian_ai_sign() -> void:
	# 四人局：0号领袖、1号反贼、2/3号忠臣，因此队友为2号与3号。
	_reset_state(4)
	_controller.state.get_player(3).identity = "loyalist"
	var ruanxian: SkillDefinition = _install_skill(0, RUANXIAN_SKILL_ID)
	# 材料取价值最低的锦囊【铁索连环】：AI 的收益必须高于材料机会成本才会发动，
	# 用高价值锦囊（如【无中生有】）作为材料时即使有两名受益者也应当给出负分。
	_give_hand_card(0, "tiesuo", "club", 12)
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	ruanxian.bind(null, 0)
	var action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":RUANXIAN_SKILL_ID, "payload":{"skill_id":RUANXIAN_SKILL_ID}}
	# 没有其他持有者时严格负分，避免白重铸一张锦囊。
	if ruanxian.score_ai_action(_build_snapshot(0), action, evaluator) >= 0.0:
		_fail("ruanxian_ai_no_holder_positive %f" % ruanxian.score_ai_action(_build_snapshot(0), action, evaluator))
		return
	# 两名队友持有者：收益高于一张锦囊的机会成本，总评分为正。
	# 快照侧的拥有判定只认四类来源，因此必须同时写入武将ID并真实安装。
	for teammate_id: int in [2, 3]:
		_controller.state.get_player(teammate_id).character_id = RUANMEI_CHARACTER_ID
		_install_skill(teammate_id, MEIZHAN_SKILL_ID)
	if ruanxian.score_ai_action(_build_snapshot(0), action, evaluator) <= 0.0:
		_fail("ruanxian_ai_ally_not_positive %f" % ruanxian.score_ai_action(_build_snapshot(0), action, evaluator))
		return
	# 材料换成高价值锦囊【无中生有】时收益不再覆盖机会成本，AI 必须拒绝发动：
	# 用一张高价值锦囊换两名队友各摸一张牌是亏的，评分必须为负。
	_reset_state(4)
	_controller.state.get_player(3).identity = "loyalist"
	ruanxian = _install_skill(0, RUANXIAN_SKILL_ID)
	_give_hand_card(0, "wuzhong", "heart", 4)
	for teammate_id: int in [2, 3]:
		_controller.state.get_player(teammate_id).character_id = RUANMEI_CHARACTER_ID
		_install_skill(teammate_id, MEIZHAN_SKILL_ID)
	if ruanxian.score_ai_action(_build_snapshot(0), action, evaluator) >= 0.0:
		_fail("ruanxian_ai_expensive_material_not_negative %f" % ruanxian.score_ai_action(_build_snapshot(0), action, evaluator))
		return
	# 只有敌方持有者时为负收益。
	_reset_state(4)
	ruanxian = _install_skill(0, RUANXIAN_SKILL_ID)
	_give_hand_card(0, "tiesuo", "club", 12)
	if not _controller.grant_acquired_skill(1, MEIZHAN_SKILL_ID, 0, 0, "test"):
		_fail("ruanxian_ai_grant_enemy")
		return
	if ruanxian.score_ai_action(_build_snapshot(0), action, evaluator) >= 0.0:
		_fail("ruanxian_ai_enemy_not_negative %f" % ruanxian.score_ai_action(_build_snapshot(0), action, evaluator))
		return
	# 取消恒为0分；请求类型不匹配时同样为0分。
	var choice_request: Dictionary = {"context":{"kind":"ruanxian_recast_trick"}, "candidates":_controller.get_hand_candidates(0, 0)}
	var cancel_action: Dictionary = {"payload":{"confirmed":false, "selected_card_uids":[]}}
	if not is_zero_approx(ruanxian.score_ai_choice(_build_snapshot(0), choice_request, cancel_action, evaluator)):
		_fail("ruanxian_ai_cancel_not_zero")
		return
	if not is_zero_approx(ruanxian.score_ai_choice(_build_snapshot(0), {"context":{"kind":"other"}}, cancel_action, evaluator)):
		_fail("ruanxian_ai_foreign_request")
		return


## 记录首个失败原因；后续用例不再执行。
func _fail(reason: String) -> void:
	if _failure.is_empty():
		_failure = reason


## 记录公开日志文本；顺序断言只读取本数组。
func _on_log_added(message: String) -> void:
	_captured_logs.append(message)
