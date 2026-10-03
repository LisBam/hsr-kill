extends Node

## 卡芙卡与【言灵】【游丝】专项回归。
## 覆盖四个层次：内容口径（卡牌/技能/武将原文与数值）、【言灵】两段（开局洗入三张专属牌、任意角色使用延时锦囊时摸牌并成为主演）、
## 【游丝】两段（秘密置牌与私有事实、回合结束时观看并获得一张牌）、以及配套 AI（救援判定区、敌方回放低价值牌、被发动者的出牌压力）。
##
## 全部断言都通过正式公开端口完成：不直接改写牌堆顺序、不直接移动牌，也不读取技能实例字段。
## 唯一使用内部接口的地方是「驱动时机」：专项场景不经过完整开局与回合轮转，因此需要显式派发 gameStart / phaseBefore / phaseAfter。

## 专属锦囊牌【言灵】的稳定定义 ID；与卡牌源码 id 字段逐字一致。
const YANLING_CARD_ID: String = "yanling"

## 【言灵】技能的稳定 ID；与卡牌同名，但两者分属 GameDatabase.skills 与 GameDatabase.cards 两个独立索引。
const YANLING_SKILL_ID: String = "yanling"

## 【游丝】技能的稳定 ID。
const YOUSI_SKILL_ID: String = "yousi"

## 卡芙卡的稳定武将 ID。
const KAFUKA_CHARACTER_ID: String = "kafuka"

## 【言灵】卡牌玩家可见描述原文；必须与需求提供文本逐字一致。
const YANLING_CARD_DESCRIPTION: String = "判定结果为梅花时，若场上有“主演”，本回合由“主演”操控。"

## 【言灵】技能玩家可见描述原文；必须与需求提供文本逐字一致。
const YANLING_SKILL_DESCRIPTION: String = "锁定技，游戏开始时，你往牌堆中随机加入三张【言灵】。当一名角色使用延时锦囊牌时，你摸一张牌并成为“主演”。"

## 【游丝】技能玩家可见描述原文；必须与需求提供文本逐字一致。
const YOUSI_SKILL_DESCRIPTION: String = "其他角色的回合开始时，你可以将一张手牌置于牌堆顶的第一张或第二张（其他角色不可知）。若如此做，本回合结束时，若其手牌中有此牌，你观看并获得其一张牌。"

## 开局应洗入的【言灵】张数；与需求原文「随机加入三张【言灵】」一致。
const EXPECTED_INSERT_COUNT: int = 3

## 专属牌自带牌面：梅花。花色取值域与 CardInstance.suit 一致。
const EXPECTED_CARD_SUIT: String = "club"

## 专属牌自带牌面：K（13点）。
const EXPECTED_CARD_RANK: int = 13

## 被发动【游丝】者的 AI 出牌压力期望值；与 game_data/effects/yousi_pressure.gd 的 AI_HAND_PRESSURE 一致。
const EXPECTED_HAND_PRESSURE: float = 3.0

## 被发动【游丝】者身上承载的持续效果 ID。
const PRESSURE_EFFECT_ID: String = "yousi_pressure"

## 端到端验证压力确实进入最终评分时使用的临时压力值。
## 它远大于生产数值，只用于把“某张无后续收益的手牌”从负分推到正分，从而证明机制真的生效；
## 生产数值仍以 game_data/effects/yousi_pressure.gd 的 AI_HAND_PRESSURE 为唯一来源。
const TEST_GUARANTEED_PRESSURE: float = 50.0

## 私有置牌事实的键名；与 MatchController 常量逐字一致。
const PRIVATE_KEY_CARD_UID: String = "card_uid"

## 私有置牌事实的位次键名。
const PRIVATE_KEY_POSITION: String = "position"

## 私有置牌事实的回合角色键名。
const PRIVATE_KEY_TURN_PLAYER_ID: String = "turn_player_id"

## 私有置牌事实的回合号键名。
const PRIVATE_KEY_TURN_NUMBER: String = "turn_number"

## 位次选项 ID：置于牌堆顶第一张。
const OPTION_TOP_ID: String = "pile_slot_1"

## 位次选项 ID：置于牌堆顶第二张。
const OPTION_SECOND_ID: String = "pile_slot_2"

## 全局看门狗超时秒数；只用于兜底，正常路径会在远小于该值的时间内完成。
## 取值刻意偏短：本用例完全同步执行，一旦出现运行时错误会立即停止脚本，此时只有看门狗能把进程拉回失败出口。
const WATCHDOG_SECONDS: float = 20.0

## 权威控制器；所有状态变化仍通过正式公开端口执行。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false


## 延迟一帧执行全部断言，确保 GameDatabase 已完成新卡牌、新技能与新武将的目录扫描。
## 同时安装看门狗：本用例全部同步推进，一旦某个内部调用抛错或流程停滞，看门狗会以失败状态结束进程，
## 避免测试进程永远挂起而无法从输出判断问题。
func _ready() -> void:
	call_deferred("_run")
	# 看门狗计时器；超时远大于本用例的正常执行时间，只用于兜底。
	var watchdog: SceneTreeTimer = get_tree().create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(_on_watchdog_timeout)


## 看门狗超时出口；输出可定位的失败标记并以1结束进程。
func _on_watchdog_timeout() -> void:
	if _failed:
		return
	_failed = true
	printerr("KAFUKA_FAIL watchdog_timeout")
	get_tree().quit(1)


## 依次执行内容口径、两段技能与配套 AI 的回归；任一场景失败都立即停止。
func _run() -> void:
	_create_controller()
	_log_progress("metadata")
	if not _test_content_metadata():
		return
	_log_progress("gameStart")
	if not _test_yanling_game_start_insertion():
		return
	_log_progress("delayedTrick")
	if not _test_yanling_delayed_trick_trigger():
		return
	_log_progress("placement")
	if not _test_yousi_placement_private_fact():
		return
	_log_progress("gain")
	if not _test_yousi_gain_on_turn_end():
		return
	_log_progress("aiPressure")
	if not _test_ai_pressure_mechanism():
		return
	print("KAFUKA_MECHANICS_PASS metadata+gameStart+delayedTrick+placement+privateFact+gain+aiPressure")
	get_tree().quit(0)


## 输出阶段进度；失败或停滞时用于定位卡在哪个用例，不参与任何断言，也不影响 PASS 判定。
func _log_progress(stage: String) -> void:
	print("KAFUKA_STAGE %s" % stage)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；全部技能时机都经它派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保留正式节点，用于验证压力值确实经协调器写入策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；动作提交与正式单机模式保持相同来源语义。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0


## 为当前场景创建最小权威状态；与正式开局共用同一批子组件，但只保留规则断言必需的字段。
func _reset_state(player_count: int) -> void:
	# 场景隔离：取消上一场景残留的流程延时与出牌请求标记。
	if _controller.game_flow_pacer != null:
		_controller.game_flow_pacer.cancel_all()
	_controller._play_choice_request_id = -1
	_controller._play_choice_event_id = -1
	_controller._play_choice_actor_id = -1
	_controller._play_choice_match_id = ""
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "kafuka-mechanics"
	_controller.state.turn_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	# 按场景需要创建最少角色；体力上限统一4点，避免濒死流程干扰规则断言。
	for player_id: int in range(player_count):
		var player: PlayerState = PlayerState.new(player_id, "卡芙卡测试玩家%d" % (player_id + 1))
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
	# 主演服务；专项场景不经过开局入口，因此在此按正式配置方式重建。
	_controller.starring_role_service = StarringRoleService.new()
	_controller.starring_role_service.configure(_controller)
	# 角色持续效果服务；本用例必须验证【游丝】施加的出牌压力，因此同样按正式配置方式重建。
	_controller.player_effect_service = PlayerEffectService.new(_controller.state)
	_controller.player_effect_service.configure(_controller)
	_controller.skill_instances_by_player.clear()
	_controller._pending_card_choice.clear()
	_controller._pending_negation_choices.clear()
	_controller._active_card_resolutions.clear()
	_controller._card_use_contexts.clear()
	_controller._rule_sequences.clear()
	_controller._deferred_skill_settlements.clear()
	_controller._rule_continuations.reset()
	_controller._cards_used_this_turn_by_player.clear()
	_controller._started_phase_lifecycles.clear()
	_controller._clear_pending_judgment_request()
	_controller._judgment_flow_in_progress = false
	_controller.ai_coordinator._policies.clear()
	_controller._ai_drive_token += 1
	_controller._scheduled_ai_drive_token = -1
	_controller._scheduled_ai_choice_request_id = -1
	_controller._ai_choice_submit_failures.clear()
	# 固定流程间隔为0；本测试全部同步推进，不依赖墙钟等待。
	_controller.game_flow_interval_seconds = 0.0


## 向指定玩家普通手牌区加入一张测试实体；花色、点数、区域与所有者全部显式写入。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新测试实体牌；稳定UID由CardInstance自动分配。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向当前测试牌堆顶部加入一张实体；数组末尾固定表示最顶层。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新牌堆实体；公共牌堆没有所属玩家。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 为指定玩家安装一个运行时技能实例；测试需要通过真实时机订阅复现完整流程。
func _install_single_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 新技能实例；技能目录缺失时返回null并交由调用方报告具体场景。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家已安装技能表；同一场景可连续追加多个技能以验证武将内技能联动。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 为当前统一选择请求提交牌、目标、文字选项或确认结果；测试通过正式PlayerAction入口覆盖事件运行时与恢复链。
func _submit_pending_choice(actor_id: int, selected_card_uids: Array[int], selected_target_ids: Array[int], confirmed: bool, selected_control_id: String = "") -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求序号；提交前读取稳定ID，避免同步恢复创建下一请求后误用新窗口编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；卡牌、目标与文字选项均显式填写，保持与真实界面提交协议一致。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d kind=%s" % [actor_id, request_id, str((_controller._pending_card_choice.get("context", {}) as Dictionary).get("kind", ""))])
	return true


## 取消一名角色身上的指定持续效果；本用例用它验证效果生命周期。
func _remove_pressure_effect(player_id: int) -> void:
	_controller.remove_player_effect(player_id, PRESSURE_EFFECT_ID)


## 收集快照中出现的全部实体牌 UID；只接受以 uid 结尾的键名，避免血量等整数误报。
func _collect_snapshot_card_uids(value: Variant, out_uids: Dictionary) -> void:
	if value is Dictionary:
		for key_variant: Variant in (value as Dictionary).keys():
			# 当前键名；只按名字判定是否为实体身份字段。
			var key_name: String = str(key_variant).to_lower()
			var child_value: Variant = (value as Dictionary)[key_variant]
			if key_name == "uid" or key_name.ends_with("_uid") or key_name.ends_with("_uids"):
				if child_value is Array:
					for uid_variant: Variant in child_value as Array:
						if uid_variant is int or uid_variant is float:
							out_uids[int(uid_variant)] = true
				elif child_value is int or child_value is float:
					out_uids[int(child_value)] = true
			_collect_snapshot_card_uids(child_value, out_uids)
		return
	if value is Array:
		for item_variant: Variant in value as Array:
			_collect_snapshot_card_uids(item_variant, out_uids)


## 内容口径：卡牌、两个技能与武将的玩家可见原文、锁定标记与关键数值必须与需求逐字逐值一致。
func _test_content_metadata() -> bool:
	# 卡牌元数据；类型、子类、专属标记、牌面与描述全部逐项核对。
	var card: Dictionary = GameDatabase.get_card(YANLING_CARD_ID)
	if card.is_empty():
		return _fail("yanling_card_missing")
	if str(card.get("original_name", "")) != "言灵" or str(card.get("custom_name", "")) != "言灵":
		return _fail("yanling_card_name=%s/%s" % [str(card.get("original_name", "")), str(card.get("custom_name", ""))])
	if str(card.get("type", "")) != "trick" or str(card.get("subtype", "")) != "delayed":
		return _fail("yanling_card_type=%s/%s" % [str(card.get("type", "")), str(card.get("subtype", ""))])
	if not bool(card.get("exclusive", false)) or not bool(card.get("delayed", false)):
		return _fail("yanling_card_exclusive_or_delayed=%s/%s" % [str(card.get("exclusive", false)), str(card.get("delayed", false))])
	if str(card.get("description", "")) != YANLING_CARD_DESCRIPTION:
		return _fail("yanling_card_description=%s" % str(card.get("description", "")))
	if str(card.get("suit", "")) != EXPECTED_CARD_SUIT or int(card.get("rank", 0)) != EXPECTED_CARD_RANK:
		return _fail("yanling_card_face=%s/%d" % [str(card.get("suit", "")), int(card.get("rank", 0))])
	# 专属锦囊牌不得被任何牌堆引用；它只能由技能或规则在运行时加入游戏。
	# 牌堆条目是数组形式 [花色, 点数, 定义ID]，因此定义 ID 固定位于下标2。
	for deck_id_variant: Variant in GameDatabase.decks.keys():
		for deck_row_variant: Variant in GameDatabase.get_deck_cards(str(deck_id_variant)):
			# 当前牌堆条目；结构异常的行不参与比较。
			var deck_row: Array = deck_row_variant as Array
			if deck_row.size() >= 3 and str(deck_row[2]) == YANLING_CARD_ID:
				return _fail("yanling_card_in_deck=%s" % str(deck_id_variant))
	# 【言灵】技能元数据；锁定技、无主动入口、描述逐字一致。
	var yanling_skill: Dictionary = GameDatabase.get_skill(YANLING_SKILL_ID)
	if yanling_skill.is_empty():
		return _fail("yanling_skill_missing")
	if not bool(yanling_skill.get("lock", false)) or bool(yanling_skill.get("ui_enabled", true)):
		return _fail("yanling_skill_lock_or_ui=%s/%s" % [str(yanling_skill.get("lock", false)), str(yanling_skill.get("ui_enabled", true))])
	if str(yanling_skill.get("description", "")) != YANLING_SKILL_DESCRIPTION:
		return _fail("yanling_skill_description=%s" % str(yanling_skill.get("description", "")))
	# 【游丝】技能元数据；非锁定技但没有主动入口（两段都由时机触发）。
	var yousi_skill: Dictionary = GameDatabase.get_skill(YOUSI_SKILL_ID)
	if yousi_skill.is_empty():
		return _fail("yousi_skill_missing")
	if bool(yousi_skill.get("lock", true)) or bool(yousi_skill.get("ui_enabled", true)):
		return _fail("yousi_skill_lock_or_ui=%s/%s" % [str(yousi_skill.get("lock", true)), str(yousi_skill.get("ui_enabled", true))])
	if str(yousi_skill.get("description", "")) != YOUSI_SKILL_DESCRIPTION:
		return _fail("yousi_skill_description=%s" % str(yousi_skill.get("description", "")))
	# 武将元数据；姓名、性别、势力、体力上限与技能列表。
	var character: Dictionary = GameDatabase.get_character(KAFUKA_CHARACTER_ID)
	if character.is_empty():
		return _fail("kafuka_character_missing")
	if str(character.get("display_name", "")) != "卡芙卡" or str(character.get("gender", "")) != "female":
		return _fail("kafuka_name_or_gender=%s/%s" % [str(character.get("display_name", "")), str(character.get("gender", ""))])
	if str(character.get("faction", "")) != "xinghelieshou" or int(character.get("max_hp", 0)) != 3:
		return _fail("kafuka_faction_or_hp=%s/%d" % [str(character.get("faction", "")), int(character.get("max_hp", 0))])
	if not (character.get("skills", []) as Array).has(YANLING_SKILL_ID) or not (character.get("skills", []) as Array).has(YOUSI_SKILL_ID):
		return _fail("kafuka_skills=%s" % str(character.get("skills", [])))
	return true


## 【言灵】第一段：游戏开始时机派发后，牌堆恰好增加三张【言灵】，牌面恒为梅花K，位次随机且逐条写入随机历史。
func _test_yanling_game_start_insertion() -> bool:
	_reset_state(3)
	_add_draw_pile_card("sha", "spade", 3)
	_add_draw_pile_card("shan", "heart", 4)
	if _install_single_skill(0, YANLING_SKILL_ID) == null:
		return _fail("yanling_skill_install")
	# 开局前的牌堆长度与随机历史长度；两者都必须恰好增加3，多一张或少一张都说明洗入次数错误。
	var pile_size_before: int = _controller.state.draw_pile.size()
	var history_before: int = _controller.state.random_history.size()
	_controller._emit_rule_timing("gameStart", -1, -1, -1, {"player_count":3})
	if _controller.state.draw_pile.size() != pile_size_before + EXPECTED_INSERT_COUNT:
		return _fail("yanling_insert_count=%d" % (_controller.state.draw_pile.size() - pile_size_before))
	if _controller.state.random_history.size() != history_before + EXPECTED_INSERT_COUNT:
		return _fail("yanling_insert_history=%d" % (_controller.state.random_history.size() - history_before))
	# 逐张核对定义与牌面；同时统计随机历史条目类型，确认位次随机确实走的是权威随机源。
	var inserted_count: int = 0
	for card: CardInstance in _controller.state.draw_pile:
		if card.definition_id != YANLING_CARD_ID:
			continue
		inserted_count += 1
		if card.suit != EXPECTED_CARD_SUIT or card.rank != EXPECTED_CARD_RANK:
			return _fail("yanling_insert_face=%s/%d" % [card.suit, card.rank])
	if inserted_count != EXPECTED_INSERT_COUNT:
		return _fail("yanling_inserted_cards=%d" % inserted_count)
	for index: int in range(history_before, _controller.state.random_history.size()):
		# 当前随机历史条目；kind 必须与控制器专属洗入原因逐字一致。
		var entry: Dictionary = _controller.state.random_history[index] as Dictionary
		if str(entry.get("kind", "")) != "exclusive_card_insert" or str(entry.get("definition_id", "")) != YANLING_CARD_ID:
			return _fail("yanling_history_entry=%s" % str(entry))
		# 记录位次必须落在当时合法范围内；位次是“从顶往下数”的相对位次。
		var recorded_position: int = int(entry.get("position", 0))
		if recorded_position < 1 or recorded_position > _controller.state.draw_pile.size():
			return _fail("yanling_history_position=%d" % recorded_position)
	return true


## 【言灵】第二段：任意角色使用延时锦囊牌时，持有者摸一张牌并成为「主演」；非延时锦囊不触发。
func _test_yanling_delayed_trick_trigger() -> bool:
	_reset_state(3)
	# 牌堆预备；摸牌端口在没有可摸牌时不会凭空造牌，因此触发前必须保证牌堆非空。
	_add_draw_pile_card("sha", "spade", 3)
	_add_draw_pile_card("shan", "heart", 4)
	_add_draw_pile_card("tao", "heart", 9)
	if _install_single_skill(0, YANLING_SKILL_ID) == null:
		return _fail("yanling_skill_install")
	# 普通锦囊【决斗】不触发；即使使用者与目标都存在也不应改变手牌数或主演归属。
	_controller._emit_rule_timing("useCard", 1, 1, 2, {"card_uid":9001, "card_id":"juedou", "target_ids":[2]})
	if _controller.state.get_player(0).hand.size() != 0 or _controller.get_starring_role_player_id() != -1:
		return _fail("yanling_non_delayed_triggered hand=%d starring=%d" % [_controller.state.get_player(0).hand.size(), _controller.get_starring_role_player_id()])
	# 延时锦囊【乐不思蜀】触发；摸牌与主演都必须立即生效。
	_controller._emit_rule_timing("useCard", 1, 1, 2, {"card_uid":9002, "card_id":"lebu", "target_ids":[2]})
	if _controller.state.get_player(0).hand.size() != 1:
		return _fail("yanling_delayed_draw=%d" % _controller.state.get_player(0).hand.size())
	if _controller.get_starring_role_player_id() != 0 or not _controller.is_starring_role(0):
		return _fail("yanling_delayed_starring=%d" % _controller.get_starring_role_player_id())
	# 主演唯一性由既有主演服务保证：第二名技能持有者再次触发时顶替原主演。
	if _install_single_skill(1, YANLING_SKILL_ID) == null:
		return _fail("yanling_second_install")
	_controller._emit_rule_timing("useCard", 2, 2, 0, {"card_uid":9003, "card_id":"lebu", "target_ids":[0]})
	if _controller.get_starring_role_player_id() != 1 or _controller.is_starring_role(0):
		return _fail("yanling_starring_replace=%d" % _controller.get_starring_role_player_id())
	# 持有者阵亡后既不再摸牌，也不再成为主演；这里单独开一个场景，避免另一名持有者的分支同时生效。
	_reset_state(3)
	_add_draw_pile_card("sha", "spade", 3)
	_add_draw_pile_card("shan", "heart", 4)
	if _install_single_skill(0, YANLING_SKILL_ID) == null:
		return _fail("yanling_dead_owner_install")
	var dead_owner: PlayerState = _controller.state.get_player(0)
	dead_owner.alive = false
	dead_owner.hp = 0
	_controller._emit_rule_timing("useCard", 1, 1, 2, {"card_uid":9004, "card_id":"bingliang", "target_ids":[2]})
	if dead_owner.hand.size() != 0 or _controller.get_starring_role_player_id() != -1:
		return _fail("yanling_dead_owner_still_triggered hand=%d starring=%d" % [dead_owner.hand.size(), _controller.get_starring_role_player_id()])
	return true


## 【游丝】第一段：其他角色回合开始时询问一张手牌与一个位次，并把牌秘密置于牌堆顶第一或第二张。
func _test_yousi_placement_private_fact() -> bool:
	_reset_state(3)
	if _install_single_skill(0, YOUSI_SKILL_ID) == null:
		return _fail("yousi_skill_install")
	var placed: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	var kept: CardInstance = _add_hand_card(0, "shan", "heart", 4)
	_add_draw_pile_card("tao", "heart", 9)
	# 持有者自己的回合不询问；【游丝】只作用于其他角色。
	_controller._emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("yousi_asked_on_own_turn")
	# 其他角色回合开始时创建位次询问；窗口必须是"card_position"且恰好三个选项。
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":1})
	if _controller._pending_card_choice.is_empty():
		return _fail("yousi_request_missing")
	var pending: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(pending.get("choice_type", "")) != "card_position" or int(pending.get("chooser_id", -1)) != 0:
		return _fail("yousi_request_shape=%s" % str(pending.get("choice_type", "")))
	var option_ids: Array[String] = []
	for option_variant: Variant in pending.get("control_options", []) as Array:
		option_ids.append(str((option_variant as Dictionary).get("id", "")))
	if option_ids != [OPTION_TOP_ID, OPTION_SECOND_ID, "cancel"]:
		return _fail("yousi_option_ids=%s" % str(option_ids))
	# 取消不写任何私有事实、不移动任何牌。
	if not _submit_pending_choice(0, [], [], false, "cancel"):
		return false
	if not _controller.get_private_pile_placement(0).is_empty() or _controller.state.get_player(0).find_hand_card(placed.uid) == null:
		return _fail("yousi_cancel_wrote_state")
	# 合法提交：换到另一名角色的回合开始，把【杀】置于牌堆顶第二张；牌离开手牌，且对方看不到它。
	var pile_top_before: int = _controller.state.draw_pile.back().uid
	_controller._emit_rule_timing("phaseBefore", 2, 2, 2, {"turn_number":1})
	if _controller._pending_card_choice.is_empty():
		return _fail("yousi_second_request_missing")
	if not _submit_pending_choice(0, [placed.uid], [], true, OPTION_SECOND_ID):
		return false
	if _controller.state.get_player(0).find_hand_card(placed.uid) != null:
		return _fail("yousi_placed_card_still_in_hand")
	if _controller.state.draw_pile.size() < 2 or _controller.state.draw_pile[_controller.state.draw_pile.size() - 2].uid != placed.uid:
		return _fail("yousi_placed_card_not_second")
	if _controller.state.draw_pile.back().uid != pile_top_before:
		return _fail("yousi_placement_disturbed_top")
	if not _controller.state.get_player(0).hand.has(kept):
		return _fail("yousi_placement_disturbed_other_card")
	# 私有事实逐字段核对；它是第二段唯一的权威依据。
	var fact: Dictionary = _controller.get_private_pile_placement(0)
	if int(fact.get(PRIVATE_KEY_CARD_UID, -1)) != placed.uid or int(fact.get(PRIVATE_KEY_POSITION, 0)) != 2:
		return _fail("yousi_private_fact=%s" % str(fact))
	if int(fact.get(PRIVATE_KEY_TURN_PLAYER_ID, -1)) != 2 or int(fact.get(PRIVATE_KEY_TURN_NUMBER, -1)) != 1:
		return _fail("yousi_private_turn=%s" % str(fact))
	# 隐私边界：任何观察者的快照都不含该牌 UID；它只存在于权威状态与持有者的私有事实里。
	for player: PlayerState in _controller.state.players:
		var visible_uids: Dictionary = {}
		_collect_snapshot_card_uids(_controller.state.to_dict(player.player_id, false), visible_uids)
		if visible_uids.has(placed.uid):
			return _fail("yousi_placed_uid_leaked viewer=%d" % player.player_id)
	# 被发动者身上出现出牌压力，且压力只挂在“本回合角色”身上。
	if not is_equal_approx(_controller.get_ai_hand_pressure(2), EXPECTED_HAND_PRESSURE):
		return _fail("yousi_pressure=%f" % _controller.get_ai_hand_pressure(2))
	if not is_equal_approx(_controller.get_ai_hand_pressure(1), 0.0) or not is_equal_approx(_controller.get_ai_hand_pressure(0), 0.0):
		return _fail("yousi_pressure_leaked others=%f/%f" % [_controller.get_ai_hand_pressure(1), _controller.get_ai_hand_pressure(0)])
	# 回合结束时效果自行到期；这里直接按权威端口移除后再确认，避免依赖完整回合尾部编排。
	_remove_pressure_effect(2)
	if not is_equal_approx(_controller.get_ai_hand_pressure(2), 0.0):
		return _fail("yousi_pressure_not_removed=%f" % _controller.get_ai_hand_pressure(2))
	return true


## 【游丝】第二段：本回合结束时若那张牌已经进入对方手牌，持有者观看其手牌与装备区并获得其中一张。
##
## 兑现链条：持有者把一张手牌置于牌堆顶第一或第二张 → 本回合角色在摸牌阶段把它摸走 → 回合结束时它仍在手牌中。
## 因此“牌是否在对方手里”天然等价于“对方是否真的摸到了那张牌”：没摸到（例如摸牌阶段被跳过）就不触发。
func _test_yousi_gain_on_turn_end() -> bool:
	# 场景一：目标没有摸到那张牌（仍留在牌堆里），回合结束时第二段不成立，但私有事实必须被清除。
	_reset_state(3)
	if _install_single_skill(0, YOUSI_SKILL_ID) == null:
		return _fail("yousi_skill_install")
	var placed: CardInstance = _add_hand_card(0, "sha", "spade", 5)
	_add_draw_pile_card("tao", "heart", 9)
	_controller.state.turn_number = 4
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":4})
	if not _submit_pending_choice(0, [placed.uid], [], true, OPTION_TOP_ID):
		return false
	if _controller.get_private_pile_placement(0).is_empty():
		return _fail("yousi_placement_fact_missing")
	_controller._emit_rule_timing("phaseAfter", 1, 1, 1, {"turn_number":4})
	if not _controller._pending_card_choice.is_empty():
		return _fail("yousi_gain_triggered_without_placed_card")
	if not _controller.get_private_pile_placement(0).is_empty():
		return _fail("yousi_private_fact_not_cleared")
	# 场景二：回合角色不匹配时不兑现，也不清除私有事实（结算只能发生在它真正服务的那个回合结尾）。
	_reset_state(3)
	if _install_single_skill(0, YOUSI_SKILL_ID) == null:
		return _fail("yousi_skill_install")
	var second_placed: CardInstance = _add_hand_card(0, "sha", "spade", 6)
	_add_draw_pile_card("tao", "heart", 10)
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":1})
	if not _submit_pending_choice(0, [second_placed.uid], [], true, OPTION_TOP_ID):
		return false
	_controller._emit_rule_timing("phaseAfter", 2, 2, 2, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("yousi_gain_on_wrong_turn_player")
	if _controller.get_private_pile_placement(0).is_empty():
		return _fail("yousi_fact_cleared_on_wrong_turn")
	# 场景三：真正的回合结尾且那张牌已经被对方摸走：候选必须包含对方完整手牌牌面与装备区，且不含判定区。
	var target: PlayerState = _controller.state.get_player(1)
	var target_hand: CardInstance = _add_hand_card(1, "tao", "heart", 7)
	var target_equipment: CardInstance = CardInstance.new("baguazhen", "spade", 2)
	target_equipment.zone = "equipment"
	target_equipment.owner_id = 1
	target.equipment["armor"] = target_equipment
	var target_judgment: CardInstance = CardInstance.new("lebu", "heart", 3)
	target_judgment.zone = "judgment"
	target_judgment.owner_id = 1
	target.judgment_area.append(target_judgment)
	# 走正式摸牌端口把牌堆顶那张牌摸走；牌从牌堆移到目标手牌，因此“其手牌中有此牌”成立。
	_controller.draw(1, 1)
	if target.find_hand_card(second_placed.uid) == null:
		return _fail("yousi_draw_did_not_pick_placed_card")
	_controller._emit_rule_timing("phaseAfter", 1, 1, 1, {"turn_number":1})
	if _controller._pending_card_choice.is_empty():
		return _fail("yousi_gain_request_missing")
	var gain_request: Dictionary = _controller._pending_card_choice.duplicate(true)
	if str(gain_request.get("choice_type", "")) != "card" or int(gain_request.get("min_card_select", 0)) != 1 or int(gain_request.get("max_card_select", 0)) != 1:
		return _fail("yousi_gain_request_shape=%s/%d" % [str(gain_request.get("choice_type", "")), int(gain_request.get("max_card_select", 0))])
	# 候选集合：手牌两张（摸到的【杀】与原【桃】）加装备一张，共3张；判定区那张不得出现。
	var candidate_uids: Array[int] = []
	for candidate_variant: Variant in gain_request.get("candidates", []) as Array:
		# 当前候选；持有者必须始终是目标角色，且必须对观看者可见（“观看”意味着看到牌面）。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("owner_id", -1)) != 1 or not bool(candidate.get("visible", false)):
			return _fail("yousi_gain_candidate=%s" % str(candidate))
		candidate_uids.append(int(candidate.get("uid", -1)))
	if candidate_uids.size() != 3 or not candidate_uids.has(target_hand.uid) or not candidate_uids.has(target_equipment.uid) or not candidate_uids.has(second_placed.uid):
		return _fail("yousi_gain_candidates=%s" % str(candidate_uids))
	if candidate_uids.has(target_judgment.uid):
		return _fail("yousi_gain_includes_judgment")
	# 取走装备区那张；牌进入持有者手牌，目标失去它。
	if not _submit_pending_choice(0, [target_equipment.uid], [], true):
		return false
	if not _controller.state.get_player(0).hand.has(target_equipment):
		return _fail("yousi_gain_not_acquired")
	if (target.equipment.get("armor") as CardInstance) != null:
		return _fail("yousi_gain_target_kept_equipment")
	if not _controller.get_private_pile_placement(0).is_empty():
		return _fail("yousi_fact_not_cleared_after_gain")
	return true


## 【游丝】配套 AI：救援判定区、敌方回放低价值牌，以及被发动者的出牌压力。三个部分都只读公开信息或标量倾向。
func _test_ai_pressure_mechanism() -> bool:
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 主演为敌方（反贼1）：领袖0应当有防备；主演为友方（忠臣2）时不需要防备。
	var enemy_starring: Dictionary = _build_policy_snapshot(1)
	var ally_starring: Dictionary = _build_policy_snapshot(2)
	var no_starring: Dictionary = _build_policy_snapshot(-1)
	if evaluator.get_starring_player_id(enemy_starring) != 1 or evaluator.get_starring_player_id(no_starring) != -1:
		return _fail("starring_snapshot_read=%d/%d" % [evaluator.get_starring_player_id(enemy_starring), evaluator.get_starring_player_id(no_starring)])
	if not evaluator.should_dump_hand_against_starring(enemy_starring, 0):
		return _fail("starring_enemy_not_detected")
	if evaluator.should_dump_hand_against_starring(ally_starring, 0) or evaluator.should_dump_hand_against_starring(no_starring, 0):
		return _fail("starring_ally_or_absent_flagged")
	# 策略层：压力只加在消耗自己手牌的动作上，并且只在主演不为队友时生效。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var use_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"jiu", "target_ids":[0], "payload":{}}
	var end_action: Dictionary = {"action_type":"end_play", "actor_id":0}
	policy.set_hand_pressure(EXPECTED_HAND_PRESSURE)
	if not is_equal_approx(float(policy.call("_get_hand_pressure_bonus", enemy_starring, use_action)), EXPECTED_HAND_PRESSURE):
		return _fail("pressure_bonus_use_card=%f" % float(policy.call("_get_hand_pressure_bonus", enemy_starring, use_action)))
	if not is_equal_approx(float(policy.call("_get_hand_pressure_bonus", enemy_starring, end_action)), 0.0):
		return _fail("pressure_bonus_end_play")
	if not is_equal_approx(float(policy.call("_get_hand_pressure_bonus", ally_starring, use_action)), 0.0):
		return _fail("pressure_bonus_ally_starring")
	# 端到端效果：复刻已验证的【酒】负分基线场景。
	# 同一组合法动作（一张在当前阶段没有后续收益的【酒】与结束出牌），压力为0时必须结束出牌；
	# 压力足够大时必须改为把这张手牌打出去：这条断言同时证明“压力进入了最终评分”和“压力让 AI 更愿意消耗手牌”。
	var wine_snapshot: Dictionary = _build_policy_snapshot(1, true)
	# 无后续收益的【酒】动作；目标是自己，与基线场景完全一致。
	var wine_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":102, "card_definition_id":"jiu", "target_ids":[0], "payload":{}}
	var wine_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var no_pressure_choice: Dictionary = wine_policy.choose_action(wine_snapshot, [wine_action, end_action])
	if str(no_pressure_choice.get("action_type", "")) != "end_play":
		return _fail("pressure_baseline_not_end_play=%s" % str(no_pressure_choice))
	var pressured_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	pressured_policy.set_hand_pressure(TEST_GUARANTEED_PRESSURE)
	var pressured_choice: Dictionary = pressured_policy.choose_action(wine_snapshot, [wine_action, end_action])
	if str(pressured_choice.get("card_definition_id", "")) != "jiu":
		return _fail("pressure_did_not_change_choice=%s" % str(pressured_choice))
	# 一次决策结束后压力必须自动清零，避免倾向泄漏到下一名角色。
	if not is_equal_approx(pressured_policy.hand_pressure, 0.0):
		return _fail("pressure_not_consumed=%f" % pressured_policy.hand_pressure)
	# 主演是队友时，同样的压力不得产生任何效果。
	var ally_pressured_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	ally_pressured_policy.set_hand_pressure(TEST_GUARANTEED_PRESSURE)
	var ally_choice: Dictionary = ally_pressured_policy.choose_action(_build_policy_snapshot(2, true), [wine_action, end_action])
	if str(ally_choice.get("action_type", "")) != "end_play":
		return _fail("pressure_applied_for_ally_starring=%s" % str(ally_choice))
	# 协调器入口：传入的压力值必须写入策略并在决策后自动清零；默认0.0时既有行为逐字不变。
	_controller.ai_coordinator.register_basic_ai(0)
	_controller.ai_coordinator.request_action(0, wine_snapshot, [wine_action, end_action], TEST_GUARANTEED_PRESSURE)
	var registered_policy: BasicAIPolicy = _controller.ai_coordinator._policies.get(0) as BasicAIPolicy
	if registered_policy == null or not is_equal_approx(registered_policy.hand_pressure, 0.0):
		return _fail("coordinator_pressure_not_reset=%s" % str(registered_policy.hand_pressure if registered_policy != null else -1.0))
	var neutral_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var neutral_choice: Dictionary = neutral_policy.choose_action(wine_snapshot, [wine_action, end_action])
	if str(neutral_choice.get("action_type", "")) != str(no_pressure_choice.get("action_type", "")):
		return _fail("neutral_pressure_changed_choice=%s/%s" % [str(neutral_choice.get("action_type", "")), str(no_pressure_choice.get("action_type", ""))])
	return true


## 构建最小 AI 决策快照；主演标记写入公开提示条目，因此 AI 只读公开信息即可识别「主演」。
## wine_scenario=true 时额外复刻 ai_policy_test 里已经验证过的【酒】基线场景：
## 领袖手里同时有【杀】与【酒】，但本次合法动作集合故意不含【杀】，因此“空喝【酒】”的通用评分为负值、基线必然是结束出牌。
## 只有在这个可复现的负分基线上，才能确定地断言“压力把负分动作推过了接受阈值”。
func _build_policy_snapshot(starring_player_id: int, wine_scenario: bool = false) -> Dictionary:
	# 玩家数组；座次0为领袖、1为反贼、2为忠臣，身份全部公开以便态度模型稳定。
	var players: Array = []
	for player_id: int in range(3):
		players.append({
			"player_id":player_id,
			"identity":"leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist"),
			"identity_revealed":true,
			"alive":true,
			"out_of_game":false,
			"hp":4,
			"max_hp":4,
			"hand_count":0,
			"hand":[],
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage":[],
			"chained":false,
			"character_id":"xier",
			"character_corner_text_entries":{},
		})
	if wine_scenario:
		# 领袖手牌；与已归档基线场景一致：【杀】101 与【酒】102。
		var actor: Dictionary = players[0] as Dictionary
		actor["hand"] = [_policy_card(101, "sha", 0), _policy_card(102, "jiu", 0)]
		actor["hand_count"] = 2
		# 反贼体力；2点使【酒】在该场景下的通用评分为负，从而形成可复现的负分基线。
		(players[1] as Dictionary)["hp"] = 2
	if starring_player_id >= 0:
		# 主演公开条目；只写稳定条目ID与文本，与正式主演服务序列化结果一致。
		var starring_player: Dictionary = players[starring_player_id] as Dictionary
		var entries: Dictionary = starring_player.get("character_corner_text_entries", {}) as Dictionary
		entries[StarringRoleService.CORNER_ENTRY_ID] = {"text":StarringRoleService.CORNER_TEXT, "order":StarringRoleService.CORNER_TEXT_ORDER, "view_kind":""}
	return {"match_id":"kafuka_mechanics_test", "players":players}


## 构建最小实体牌快照；AI 评估器只读取 UID、定义 ID、牌面与持有者。
func _policy_card(uid: int, definition_id: String, owner_id: int) -> Dictionary:
	return {"uid":uid, "definition_id":definition_id, "suit":"spade", "rank":1, "color":"black", "zone":"hand", "owner_id":owner_id}


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("KAFUKA_FAIL %s" % message)
	get_tree().quit(1)
	return false
