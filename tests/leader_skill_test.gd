extends Node

## 领袖技专项回归。验证身份归属、文字选项、振旗同位配对、领航次数消费与双向连环状态触发。

## 测试使用的权威控制器；全部选择仍通过标准 PlayerAction 提交并由 ChoiceRequest 复核。
var _controller: MatchController

## 当前测试是否已经失败；失败后立即停止后续场景并以非零状态退出。
var _failed: bool = false


## 延迟一帧执行测试，确保 GameDatabase 已完成新增技能与武将引用扫描。
func _ready() -> void:
	call_deferred("_run")


## 依次执行互相隔离的领袖技场景；全部通过后输出稳定成功摘要。
func _run() -> void:
	_create_controller()
	if not _test_leader_skill_ownership_and_ui_filter():
		return
	if not _test_control_choice_panel():
		return
	if not _test_zhenqi_paired_branches():
		return
	if not _test_linghang_link_directions_and_limit():
		return
	print("LEADER_SKILL_PASS ownership=leader_only zhenqi=paired linghang=bidirectional_once")
	get_tree().quit(0)


## 创建带事件、AI 与网络组件的最小控制器；组件结构与正式主场景保持一致。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能通过标准时机服务订阅，不直接调用测试回调。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；测试玩家均由手动标准动作响应，策略表保持为空。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网络网关；保留正式选择响应与命令协议所需节点。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0


## 为单项场景创建最小权威状态并重建全部状态型服务；旧技能会先卸载，避免订阅跨场景残留。
func _reset_state(character_ids: Array[String], identities: Array[String]) -> void:
	_controller._uninstall_all_character_skills()
	_controller.event_scheduler.reset()
	_controller.state = GameState.new()
	_controller.state.match_id = "leader-skill-test"
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "test"
	_controller.state.turn_number = 1
	for player_id: int in range(character_ids.size()):
		# 当前测试玩家；武将与身份由场景参数明确给出，全部公开以便 UI 与 AI 读取稳定快照。
		var player: PlayerState = PlayerState.new(player_id, "领袖技测试玩家%d" % (player_id + 1))
		player.character_id = character_ids[player_id]
		player.character_revealed = true
		player.identity = identities[player_id]
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
	_controller._resolved_card_choice_uids.clear()
	_controller._resolved_target_choice_ids.clear()
	_controller._resolved_control_choice_id = ""
	_controller.ai_coordinator._policies.clear()


## 验证领袖技元数据、运行时安装与技能栏过滤共享同一 leader 身份约束。
func _test_leader_skill_ownership_and_ui_filter() -> bool:
	_reset_state(["bronya", "bronya"], ["leader", "rebel"])
	_controller._install_all_character_skills()
	# 领袖与非领袖技能实例；同一武将只有领袖实际拥有振旗。
	var leader_skills: Dictionary = _controller.skill_instances_by_player.get(0, {}) as Dictionary
	var non_leader_skills: Dictionary = _controller.skill_instances_by_player.get(1, {}) as Dictionary
	if not leader_skills.has("zhenqi") or non_leader_skills.has("zhenqi"):
		return _fail("leader_ownership leader=%s non_leader=%s" % [leader_skills.keys(), non_leader_skills.keys()])
	# 两项新增技能元数据；原文与 leader_skill 标记必须同时准确。
	var zhenqi_metadata: Dictionary = GameDatabase.get_skill("zhenqi")
	var linghang_metadata: Dictionary = GameDatabase.get_skill("linghang")
	if not bool(zhenqi_metadata.get("leader_skill", false)) or not bool(linghang_metadata.get("leader_skill", false)):
		return _fail("leader_metadata zhenqi=%s linghang=%s" % [zhenqi_metadata, linghang_metadata])
	if str(zhenqi_metadata.get("description", "")) != "领袖技，“贝洛伯格”势力的角色的回合开始时，其可弃置一张手牌/失去1点体力，然后你令另一名“贝洛伯格”势力的角色摸一张牌/回复1点体力。" or str(linghang_metadata.get("description", "")) != "领袖技，“星穹列车”势力的角色使一名角色横置时，你可对其发动此技能，然后其可重铸一张手牌。每回合限一次。":
		return _fail("leader_descriptions")
	# 技能栏脚本实例；过滤函数不依赖节点就绪状态，可直接验证领袖与非领袖按钮 ID 集合。
	var table_script: Script = load("res://scripts/ui/match_table.gd") as Script
	var table: Node = table_script.new() as Node
	var character: Dictionary = GameDatabase.get_character("bronya")
	var leader_visible_ids: Array = table.call("_get_visible_skill_ids", character, "leader") as Array
	var non_leader_visible_ids: Array = table.call("_get_visible_skill_ids", character, "rebel") as Array
	table.free()
	if not leader_visible_ids.has("zhenqi") or non_leader_visible_ids.has("zhenqi"):
		return _fail("leader_ui_filter leader=%s non_leader=%s" % [leader_visible_ids, non_leader_visible_ids])
	return true


## 验证文字控制项使用独立按钮呈现，取消按钮只负责放弃，不承担第二费用分支。
func _test_control_choice_panel() -> bool:
	# 独立选择面板；加入场景树后动态创建固定操作结构，再显示两项测试选项。
	var panel: CardSelectionPanel = CardSelectionPanel.new()
	add_child(panel)
	panel.show_request({
		"request_id":1,
		"choice_type":"control",
		"title":"振旗",
		"prompt":"选择费用",
		"control_options":[{"id":"discard_hand", "label":"弃置一张手牌"}, {"id":"lose_hp", "label":"失去1点体力"}],
		"allow_cancel":true,
	})
	# 动态选项按钮与底部按钮；两项必须各自可点，通用确定隐藏，取消保留为不发动。
	var option_buttons: Array = panel.get("_control_option_buttons") as Array
	var confirm_button: Button = panel.get("_confirm_button") as Button
	var cancel_button: Button = panel.get("_cancel_button") as Button
	var valid: bool = option_buttons.size() == 2 and not confirm_button.visible and cancel_button.visible
	panel.queue_free()
	if not valid:
		return _fail("control_panel options=%d confirm=%s cancel=%s" % [option_buttons.size(), confirm_button.visible, cancel_button.visible])
	return true


## 验证振旗严格执行弃牌对应摸牌、失去体力对应回复的同位配对，且选择者归属正确。
func _test_zhenqi_paired_branches() -> bool:
	# 弃牌分支场景；领袖0、费用支付者1与受益者2均为贝洛伯格角色。
	_reset_state(["bronya", "xier", "xier"], ["leader", "loyalist", "loyalist"])
	var zhenqi: SkillDefinition = _install_single_skill(0, "zhenqi")
	# 费用牌与补牌；费用牌应进入弃牌堆，补牌应进入三号玩家手牌。
	var cost_card: CardInstance = _add_hand_card(1, "shan", "heart", 2)
	var draw_card: CardInstance = _add_draw_pile_card("sha", "spade", 7)
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":1})
	if str(_controller._pending_card_choice.get("choice_type", "")) != "control" or int(_controller._pending_card_choice.get("chooser_id", -1)) != 1:
		return _fail("zhenqi_cost_chooser=%s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(1, [], [], "discard_hand", true):
		return false
	if int(_controller._pending_card_choice.get("chooser_id", -1)) != 1 or not _submit_pending_choice(1, [cost_card.uid], [], "", true):
		return _fail("zhenqi_discard_choice=%s" % [_controller._pending_card_choice])
	if int(_controller._pending_card_choice.get("chooser_id", -1)) != 0 or not _submit_pending_choice(0, [], [2], "", true):
		return _fail("zhenqi_recipient_choice=%s" % [_controller._pending_card_choice])
	if _controller.state.get_player(1).find_hand_card(cost_card.uid) != null or not _controller.state.discard_pile.has(cost_card) or _controller.state.get_player(2).find_hand_card(draw_card.uid) == null or _controller.state.get_player(2).hp != 4:
		return _fail("zhenqi_discard_draw payer_hand=%d target_hand=%d target_hp=%d" % [_controller.state.get_player(1).hand.size(), _controller.state.get_player(2).hand.size(), _controller.state.get_player(2).hp])
	# 失去体力分支场景；不弃牌、不摸牌，只让支付者失去1点并令所选另一角色回复1点。
	_reset_state(["bronya", "xier", "xier"], ["leader", "loyalist", "loyalist"])
	zhenqi = _install_single_skill(0, "zhenqi")
	_controller.state.get_player(1).hp = 3
	_controller.state.get_player(2).hp = 2
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":1})
	if not _submit_pending_choice(1, [], [], "lose_hp", true):
		return false
	if not _submit_pending_choice(0, [], [2], "", true):
		return false
	if _controller.state.get_player(1).hp != 2 or _controller.state.get_player(2).hp != 3 or not _controller.state.get_player(2).hand.is_empty():
		return _fail("zhenqi_lose_recover payer_hp=%d target_hp=%d target_hand=%d" % [_controller.state.get_player(1).hp, _controller.state.get_player(2).hp, _controller.state.get_player(2).hand.size()])
	# 失效持有者场景；全局时机订阅仍存在时，死亡或离场的布洛妮娅都不能继续发出费用询问。
	_reset_state(["bronya", "xier", "xier"], ["leader", "loyalist", "loyalist"])
	zhenqi = _install_single_skill(0, "zhenqi")
	_controller.state.get_player(0).alive = false
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("zhenqi_dead_owner_prompt=%s" % [_controller._pending_card_choice])
	_controller.state.get_player(0).alive = true
	_controller.state.get_player(0).out_of_game = true
	_controller._emit_rule_timing("phaseBefore", 1, 1, 1, {"turn_number":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("zhenqi_absent_owner_prompt=%s" % [_controller._pending_card_choice])
	return zhenqi != null


## 验证领航由连环事件来源角色重铸，横置与竖直两种变化都触发，并在确认发动时立即消费回合次数。
func _test_linghang_link_directions_and_limit() -> bool:
	_reset_state(["himeko", "dan_heng", "xier"], ["leader", "loyalist", "loyalist"])
	var linghang: SkillDefinition = _install_single_skill(0, "linghang")
	# 来源角色手牌与后续补牌；被横置目标2不持有重铸牌，用于识别重铸者是否错误。
	var recast_card: CardInstance = _add_hand_card(1, "shan", "heart", 8)
	var replacement_card: CardInstance = _add_draw_pile_card("sha", "club", 9)
	# 第一回合由星穹列车角色1使目标2横置；姬子确认后，来源角色1获得可取消重铸询问。
	if not _controller.set_player_linked(2, true, 1, "leader_skill_test") or int(_controller._pending_card_choice.get("chooser_id", -1)) != 0:
		return _fail("linghang_horizontal_prompt=%s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], "", true):
		return false
	if int(linghang.get("_used_turn_number")) != 1 or int(_controller._pending_card_choice.get("chooser_id", -1)) != 1:
		return _fail("linghang_use_consumption used=%s choice=%s" % [linghang.get("_used_turn_number"), _controller._pending_card_choice])
	# 来源角色直接取消重铸；次数仍保留，手牌不移动。
	if not _submit_pending_choice(1, [], [], "", false):
		return false
	if _controller.state.get_player(1).find_hand_card(recast_card.uid) == null:
		return _fail("linghang_cancel_moved_card")
	# 同回合由同一来源角色把目标竖直；状态变化成功，但已消耗次数，因此不会再次询问。
	if not _controller.set_player_linked(2, false, 1, "leader_skill_test") or not _controller._pending_card_choice.is_empty():
		return _fail("linghang_same_turn_limit=%s" % [_controller._pending_card_choice])
	# 非星穹列车角色先重新横置目标，不触发领航；下一回合再由来源角色1将其竖直，必须创建询问。
	if not _controller.set_player_linked(2, true, 2, "leader_skill_test") or not _controller._pending_card_choice.is_empty():
		return _fail("linghang_wrong_faction_trigger=%s" % [_controller._pending_card_choice])
	_controller.state.turn_number = 2
	if not _controller.set_player_linked(2, false, 1, "leader_skill_test") or int(_controller._pending_card_choice.get("chooser_id", -1)) != 0:
		return _fail("linghang_vertical_prompt=%s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(0, [], [], "", true) or int(_controller._pending_card_choice.get("chooser_id", -1)) != 1:
		return _fail("linghang_vertical_recast_chooser=%s" % [_controller._pending_card_choice])
	if not _submit_pending_choice(1, [recast_card.uid], [], "", true):
		return false
	if _controller.state.get_player(1).find_hand_card(recast_card.uid) != null or _controller.state.get_player(1).find_hand_card(replacement_card.uid) == null or not _controller.state.discard_pile.has(recast_card) or not _controller.state.get_player(2).hand.is_empty():
		return _fail("linghang_recast source_hand=%s target_hand=%d discard=%s" % [_controller.state.get_player(1).hand, _controller.state.get_player(2).hand.size(), _controller.state.discard_pile.has(recast_card)])
	return true


## 为指定玩家安装单个技能实例；测试场景无需加载同武将的其他技能即可验证独立组件行为。
func _install_single_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 新技能实例；数据库缺失会返回 null 并由调用方后续断言精确报告。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		_fail("missing_skill=%s" % skill_id)
		return null
	skill.bind(_controller, player_id)
	_controller.skill_instances_by_player[player_id] = {skill_id:skill}
	skill.install()
	return skill


## 向指定玩家普通手牌区加入一张实体，并返回稳定对象供移动断言使用。
func _add_hand_card(player_id: int, definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新手牌实体；区域与所有者字段必须和玩家手牌数组保持一致。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "hand"
	card.owner_id = player_id
	_controller.state.get_player(player_id).hand.append(card)
	return card


## 向摸牌堆顶加入一张实体；数组末尾是牌堆顶，下一次摸牌会取得本对象。
func _add_draw_pile_card(definition_id: String, suit: String, rank: int) -> CardInstance:
	# 新牌堆实体；未归属任何玩家，进入手牌时由移动服务写入新所有者。
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.zone = "draw_pile"
	card.owner_id = -1
	_controller.state.draw_pile.append(card)
	return card


## 提交当前统一选择请求；牌、目标、文字选项和取消状态完整走权威动作入口。
func _submit_pending_choice(actor_id: int, card_ids: Array[int], target_ids: Array[int], control_id: String, confirmed: bool) -> bool:
	if _controller._pending_card_choice.is_empty():
		return _fail("missing_pending_choice actor=%d" % actor_id)
	# 当前请求 ID；每次恢复可能同步创建下一请求，因此提交前只读取本窗口稳定编号。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	# 标准选择动作；全部维度都显式填写，避免测试依赖旧 confirmed 推断兼容逻辑。
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":card_ids.duplicate(), "selected_target_ids":target_ids.duplicate(), "selected_control_id":control_id, "confirmed":confirmed}
	if not _controller.submit_action(action):
		return _fail("choice_rejected actor=%d request=%d payload=%s" % [actor_id, request_id, action.payload])
	return true


## 输出专项失败原因并停止测试；返回 false 便于调用方直接终止当前场景。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("LEADER_SKILL_FAIL %s" % message)
	get_tree().quit(1)
	return false
