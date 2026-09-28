extends Node

## 大黑塔【解构】【灵感】【看破】专项回归。覆盖武将元数据与三条技能原文、记录容器的去重与跨回合保留、
## 无懈可击的双向排除、灵感三段选择的取消语义、目标模式重定向、结算后移除记录、看破的仅对本人无效，
## 以及三条技能的AI钩子必须产出正分。

## 本测试共用的权威对局控制器；全部机制通过正式服务与技能端口执行。
var _controller: MatchController


## 延迟一帧开始回归，确保 GameDatabase 已完成目录扫描和静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部断言；任一失败立即以非零状态结束。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_descriptions():
		return
	if not _test_jiegou_records_normal_trick_only():
		return
	if not _test_jiegou_recast_wuxie_without_recording():
		return
	if not _test_jiegou_record_persists_across_turns():
		return
	if not _test_linggan_candidates_exclude_wuxie():
		return
	if not _test_linggan_cancel_paths():
		return
	if not _test_linggan_target_redirect():
		return
	if not _test_linggan_removes_used_names():
		return
	if not _test_linggan_self_expanding_target_mode():
		return
	if not _test_linggan_all_others_target_mode_on_self_effect():
		return
	if not _test_linggan_self_target_mode():
		return
	if not _test_linggan_single_name_skips_retarget_prompt():
		return
	if not _test_kanpo_negates_self_only():
		return
	if not _test_kanpo_preconditions():
		return
	if not _test_ai_hooks_positive():
		return
	if not _test_corner_record_button():
		return
	print("DAHEITA_MECHANICS_PASS records=1 recast_wuxie=1 redirect=1 expanding=1 self_target=1 single_name=1 cancel_safe=1 negate_self=1 wuxie_excluded=1 corner_button=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能时机与轮回生命周期共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；身份观察与目标态度查询保持正式实现。
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
	_controller.state.match_id = "daheita-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号领袖、二号反贼、其余忠臣形成稳定敌我关系。
		var player: PlayerState = PlayerState.new(player_id, "大黑塔测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		# 被测角色固定为大黑塔；武将固有技能的重建依赖该字段指向正式武将资料。
		player.character_id = "daheita" if player_id == 0 else ""
		player.max_hp = 6
		player.hp = 6
		_controller.state.players.append(player)
	# 摸牌堆；重铸与视为使用需要可用的实体牌。
	for card_index: int in range(30):
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


## 安装大黑塔的全部三个技能；需要跨技能协作的用例统一走该入口。
func _install_daheita_skills(player_id: int) -> bool:
	for skill_id: String in ["jiegou", "linggan", "kanpo"]:
		if _install_skill(player_id, skill_id) == null:
			return false
	return true


## 向指定玩家手牌区加入一张指定牌名实体并补齐来源字段；直接入区必须写入正式移动服务才会写入的字段。
func _give_card(player_id: int, definition_id: String, suit: String = "spade", rank: int = 1) -> int:
	var player: PlayerState = _controller.state.get_player(player_id)
	var card: CardInstance = CardInstance.new(definition_id, suit, rank)
	card.owner_id = player_id
	card.zone = "hand"
	player.hand.append(card)
	return card.uid


## 验证记录牌名角标按钮的条目契约：按钮可声明、可共存、且绝不参与既有文本合成。
## 这是本次重构的核心不变量——character_corner_text 被AI评估与多个既有测试直接断言，
## 因此按钮条目必须与文本合成完全隔离，否则所有既有角标断言都会连带回退。
func _test_corner_record_button() -> bool:
	_reset_state(2)
	var player: PlayerState = _controller.state.get_player(0)
	player.character_corner_text_entries.clear()
	# 一条纯文本角标与一条按钮角标共存，模拟“酩酊”之类的状态提示与记录按钮同时出现。
	if not _controller.set_character_corner_text_entry(0, "test:text", "提示", 50):
		return _fail("corner_text_entry")
	if not _controller.set_character_corner_text_entry(0, "test:button", "解构", 60, "recorded_card_names"):
		return _fail("corner_button_entry")
	# 合成文本只包含纯文本条目；按钮条目不得进入 character_corner_text。
	if str(player.character_corner_text) != "提示":
		return _fail("corner_text_compose=%s" % str(player.character_corner_text))
	# 按钮条目仍完整保留在公开条目字典中，供表现层渲染可点击角标。
	var button_entry: Dictionary = player.character_corner_text_entries.get("test:button", {}) as Dictionary
	if str(button_entry.get("view_kind", "")) != "recorded_card_names":
		return _fail("corner_button_view_kind")
	if str(button_entry.get("text", "")) != "解构":
		return _fail("corner_button_text")
	if int(button_entry.get("order", -1)) != 60:
		return _fail("corner_button_order")
	# 清空记录后按钮条目仍保留：是否渲染由表现层按公开记录是否为空决定，
	# 因此移除记录的【看破】不需要知道【解构】的存在，两个技能保持互不引用。
	_set_recorded_names(0, [])
	if not player.character_corner_text_entries.has("test:button"):
		return _fail("corner_button_lifecycle")
	# 还原构造的状态；后续用例不应看到本次测试写入的角标条目。
	player.character_corner_text_entries.clear()
	player.character_corner_text = ""
	return true


## 手工写入玩家的记录牌名；测试用于跳过【解构】直接构造【灵感】与【看破】的前置条件。
func _set_recorded_names(player_id: int, definition_ids: Array) -> void:
	var player: PlayerState = _controller.state.get_player(player_id)
	player.recorded_card_names.clear()
	player.recorded_card_names.assign(definition_ids)


## 返回当前待处理选择的上下文；没有请求时返回空字典。
func _pending_context() -> Dictionary:
	return _controller._pending_card_choice.get("context", {}) as Dictionary


## 提交当前零材料确认请求；返回底层提交结果，便于测试断言“预期失败”的分支。
func _try_confirm(actor_id: int, confirmed: bool) -> bool:
	return _try_submit(actor_id, [], [], "", confirmed)


## 提交当前控制项选择；返回底层提交结果。
func _try_control(actor_id: int, control_id: String, confirmed: bool = true) -> bool:
	return _try_submit(actor_id, [], [], control_id, confirmed)


## 提交当前选牌选择；返回底层提交结果。
func _try_cards(actor_id: int, card_uids: Array[int], confirmed: bool = true) -> bool:
	return _try_submit(actor_id, card_uids, [], "", confirmed)


## 提交当前目标选择；返回底层提交结果。
func _try_targets(actor_id: int, target_ids: Array[int], confirmed: bool = true) -> bool:
	return _try_submit(actor_id, [], target_ids, "", confirmed)


## 统一提交入口；选择动作必须绑定创建时的同一请求编号。
func _try_submit(actor_id: int, card_uids: Array[int], target_ids: Array[int], control_id: String, confirmed: bool) -> bool:
	if _controller == null or _controller._pending_card_choice.is_empty():
		return false
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", actor_id)
	action.payload = {"request_id":request_id, "selected_card_uids":card_uids.duplicate(), "selected_target_ids":target_ids.duplicate(), "selected_control_id":control_id, "confirmed":confirmed}
	return _controller.submit_action(action)


## 提交并断言成功；用于必须成功的步骤，失败即输出原因。
func _submit_or_fail(actor_id: int, card_uids: Array[int], target_ids: Array[int], control_id: String, confirmed: bool, scene: String) -> bool:
	if not _try_submit(actor_id, card_uids, target_ids, control_id, confirmed):
		_fail("submit_rejected=%s" % str(scene))
		return false
	return true


## 校验武将资料、三条技能原文与三项运行时元数据。
func _test_metadata_and_descriptions() -> bool:
	# 大黑塔静态定义；性别、势力、体力与技能顺序必须与设计一致。
	var daheita: Dictionary = GameDatabase.get_character("daheita")
	if str(daheita.get("display_name", "")) != "大黑塔" or str(daheita.get("gender", "")) != "female" or str(daheita.get("faction", "")) != "yinhexvezhe" or int(daheita.get("max_hp", 0)) != 3 or daheita.get("skills", []) != ["jiegou", "linggan", "kanpo"]:
		return _fail("character_metadata=%s" % str(daheita))
	# 需求指定的三条技能原文；任何字符、标点、引号或【解读】字样变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"jiegou":"出牌阶段，你可以重铸一张非延时锦囊牌，然后若该锦囊牌的牌名未被记录，你记录该牌牌名。",
		"linggan":"出牌阶段限一次，你可以视为使用一张“解构”记录的牌名的牌，然后可令该牌的目标按另一张“解读”记录牌名的牌的目标结算。该牌结算完毕后，移除“解构”中记录的这两张牌名。",
		"kanpo":"当你成为其他角色使用的锦囊牌的目标时，你可移除“解构”中与此牌相同的牌名，然后令此牌对你无效。每轮限一次。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；静态数据库说明必须与期望逐字一致。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("skill_description=%s" % str(skill_id))
	# 三项技能都不是限定技或轮回技；看破是触发技，解构与灵感是主动技。
	for skill_id: String in ["jiegou", "linggan", "kanpo"]:
		var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
		if skill == null or skill.limited or skill.reincarnation:
			return _fail("skill_flags=%s" % str(skill_id))
	return true


## 校验【解构】只接受非延时普通锦囊：延时锦囊不出现在候选中，重复牌名不重复记录。
func _test_jiegou_records_normal_trick_only() -> bool:
	_reset_state(3)
	if _install_skill(0, "jiegou") == null:
		return _fail("jiegou_install")
	# 普通锦囊与延时锦囊各一张；只有普通锦囊应进入候选。
	var nanman_uid: int = _give_card(0, "nanman", "spade", 1)
	_give_card(0, "lebu", "spade", 2)
	# 装备牌与基本牌同样不可记录。
	_give_card(0, "sha", "spade", 3)
	if not _controller.activate_skill(0, "jiegou", {"active_entry":"phaseUse"}):
		return _fail("jiegou_activate_rejected")
	# 候选数量；三张手牌中只有【南蛮入侵】可被记录。
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if candidates.size() != 1 or int((candidates[0] as Dictionary).get("uid", -1)) != nanman_uid:
		return _fail("jiegou_candidates=%s" % str(candidates))
	if not _submit_or_fail(0, [nanman_uid], [], "", true, "jiegou_recast"):
		return false
	var owner: PlayerState = _controller.state.get_player(0)
	if not owner.recorded_card_names.has("nanman") or owner.recorded_card_names.size() != 1:
		return _fail("jiegou_record=%s" % str(owner.recorded_card_names))
	# 重铸确实生效：该实体已离开手牌并进入弃牌堆。
	if owner.find_hand_card(nanman_uid) != null:
		return _fail("jiegou_recast_not_moved")
	# 重复记录：再重铸一张同名锦囊，记录数量必须保持为1。
	var second_nanman: int = _give_card(0, "nanman", "club", 4)
	if not _controller.activate_skill(0, "jiegou", {"active_entry":"phaseUse"}):
		return _fail("jiegou_second_rejected")
	if not _submit_or_fail(0, [second_nanman], [], "", true, "jiegou_second_recast"):
		return false
	if owner.recorded_card_names.size() != 1:
		return _fail("jiegou_duplicate_record=%s" % str(owner.recorded_card_names))
	return true


## 校验【解构】可以重铸【无懈可击】但不记录它：响应类锦囊能被重铸，却不能用于使用或转换。
func _test_jiegou_recast_wuxie_without_recording() -> bool:
	_reset_state(3)
	if _install_skill(0, "jiegou") == null:
		return _fail("wuxie_recast_install")
	var wuxie_uid: int = _give_card(0, "wuxie", "heart", 5)
	if not _controller.activate_skill(0, "jiegou", {"active_entry":"phaseUse"}):
		return _fail("wuxie_recast_rejected")
	# 无懈可击是非延时锦囊，因此必须出现在可重铸候选里。
	var candidates: Array = _controller._pending_card_choice.get("candidates", []) as Array
	if candidates.size() != 1 or int((candidates[0] as Dictionary).get("uid", -1)) != wuxie_uid:
		return _fail("wuxie_recast_candidates=%s" % str(candidates))
	if not _submit_or_fail(0, [wuxie_uid], [], "", true, "wuxie_recast"):
		return false
	var owner: PlayerState = _controller.state.get_player(0)
	# 重铸已生效，但记录容器必须保持为空：它不能被用于使用或转换。
	if owner.find_hand_card(wuxie_uid) != null:
		return _fail("wuxie_recast_not_moved")
	if not owner.recorded_card_names.is_empty():
		return _fail("wuxie_recast_recorded=%s" % str(owner.recorded_card_names))
	# 记录为空时【灵感】不应开放任何发动入口。
	if _install_skill(0, "linggan") == null:
		return _fail("wuxie_recast_linggan_install")
	if _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("wuxie_recast_linggan_enabled")
	return true


## 校验记录跨回合保留，并且写入公开快照与存档往返。
func _test_jiegou_record_persists_across_turns() -> bool:
	_reset_state(3)
	if _install_skill(0, "jiegou") == null:
		return _fail("persist_install")
	_set_recorded_names(0, ["nanman", "tiesuo"])
	# 推进到下一个回合与轮次；记录是公开的长期事实，不应被回合边界清空。
	_controller.state.turn_number = 5
	_controller.state.round_number = 3
	_controller._emit_rule_timing("turnBegin", 0, 0, -1, {"player_id":0})
	_controller._emit_rule_timing("roundBegin", 0, 0, -1, {"round":3})
	var owner: PlayerState = _controller.state.get_player(0)
	if owner.recorded_card_names != ["nanman", "tiesuo"]:
		return _fail("persist_turn_cleared=%s" % str(owner.recorded_card_names))
	# 公开快照；记录属于公开信息，必须出现在普通观察者的快照里。
	var public_snapshot: Dictionary = _controller.state.to_dict(1, false)
	var public_player: Dictionary = (public_snapshot.get("players", []) as Array)[0] as Dictionary
	if (public_player.get("recorded_card_names", []) as Array) != ["nanman", "tiesuo"]:
		return _fail("persist_public_snapshot=%s" % str(public_player.get("recorded_card_names", [])))
	# 存档往返；from_authoritative_dict 接收单个玩家的权威字典，读档后候选集合必须与存档前一致。
	var archived_player: Dictionary = (_controller.state.to_dict(0, true).get("players", []) as Array)[0] as Dictionary
	var restored: PlayerState = PlayerState.from_authoritative_dict(archived_player)
	if restored.recorded_card_names != ["nanman", "tiesuo"]:
		return _fail("persist_roundtrip=%s" % str(restored.recorded_card_names))
	return true


## 校验【灵感】的牌名候选排除【无懈可击】；即使记录被污染也不允许作为候选出现。
func _test_linggan_candidates_exclude_wuxie() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("wuxie_install")
	# 人为把无懈可击写入记录；正常流程不会产生该记录，此处验证防御性排除。
	# 额外保留第三张记录牌名，使第二步确认确实存在：只剩被排除牌名时技能会跳过询问。
	_set_recorded_names(0, ["wuxie", "nanman", "tiesuo"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("wuxie_activate_rejected")
	# 第一段候选；只允许出现南蛮入侵与铁索连环，无懈可击必须被排除。
	var options: Array = _controller._pending_card_choice.get("control_options", []) as Array
	if options.size() != 2:
		return _fail("wuxie_first_options=%s" % str(options))
	for option_variant: Variant in options:
		if str((option_variant as Dictionary).get("id", "")) == "wuxie":
			return _fail("wuxie_first_options=%s" % str(options))
	if not _submit_or_fail(0, [], [], "nanman", true, "wuxie_pick_effect"):
		return false
	# 第二段确认重定向；确认后第三段候选同样不得出现无懈可击。
	if not _submit_or_fail(0, [], [], "", true, "wuxie_confirm"):
		return false
	var second_options: Array = _controller._pending_card_choice.get("control_options", []) as Array
	if second_options.size() != 1 or str((second_options[0] as Dictionary).get("id", "")) != "tiesuo":
		return _fail("wuxie_second_options=%s" % str(second_options))
	return true


## 校验【灵感】的取消语义：任一步取消都不消耗次数、不移除记录，之后仍可再次发动。
func _test_linggan_cancel_paths() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("cancel_install")
	# 记录两张牌名，使第二步询问确实存在：只有一张记录时技能会跳过询问直接结算。
	# 效果牌名使用铁索连环（非全体、非自指），因此会进入目标选择阶段，供后续取消检验。
	_set_recorded_names(0, ["tiesuo", "nanman"])
	# 第一步取消；应完全放弃本次发动。
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("cancel_activate_rejected")
	if not _submit_or_fail(0, [], [], "", false, "cancel_effect"):
		return false
	# 取消后无残留请求，记录未被移除。
	if not _controller._pending_card_choice.is_empty():
		return _fail("cancel_residual_request")
	var owner: PlayerState = _controller.state.get_player(0)
	if owner.recorded_card_names.size() != 2:
		return _fail("cancel_record_removed=%s" % str(owner.recorded_card_names))
	# 次数未被消耗；同一出牌阶段仍可再次发动并走完全流程。
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("cancel_second_activate_rejected")
	if not _submit_or_fail(0, [], [], "tiesuo", true, "cancel_second_effect"):
		return false
	# 第二步取消等价于“不重定向”，应继续进入目标选择而不是整体放弃。
	if not _submit_or_fail(0, [], [], "", false, "cancel_retarget"):
		return false
	if _controller._pending_card_choice.is_empty():
		return _fail("cancel_retarget_no_target_request")
	# 在目标选择阶段取消：不消耗次数、不移除记录。
	if not _submit_or_fail(0, [], [], "", false, "cancel_targets"):
		return false
	if owner.recorded_card_names.size() != 2:
		return _fail("cancel_targets_record_removed=%s" % str(owner.recorded_card_names))
	# 关键回归：目标选择取消后必须仍能重新发动，而不是被误判为“本阶段已发动过”而永久失效。
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("cancel_targets_then_reactivate")
	if not _submit_or_fail(0, [], [], "tiesuo", true, "cancel_third_effect"):
		return false
	return true


## 校验【灵感】的目标模式重定向：效果取南蛮入侵，目标模式取铁索连环后目标上限变为2。
func _test_linggan_target_redirect() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("redirect_install")
	_set_recorded_names(0, ["nanman", "tiesuo"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("redirect_activate_rejected")
	# 三段选择：效果=南蛮入侵，确认重定向，目标模式=铁索连环。
	if not _submit_or_fail(0, [], [], "nanman", true, "redirect_effect"):
		return false
	if not _submit_or_fail(0, [], [], "", true, "redirect_confirm"):
		return false
	if not _submit_or_fail(0, [], [], "tiesuo", true, "redirect_target_mode"):
		return false
	# 已进入目标选择；三名角色都应是可点击目标（铁索模式不排除任何人）。
	if _controller._pending_card_choice.is_empty():
		return _fail("redirect_no_target_request")
	var context: Dictionary = _pending_context()
	if str(context.get("kind", "")) != "linggan_select_targets" or str(context.get("target_mode_id", "")) != "tiesuo":
		return _fail("redirect_context=%s" % str(context))
	var selectable_targets: Array = _controller._pending_card_choice.get("target_ids", []) as Array
	if selectable_targets.size() != 3:
		return _fail("redirect_selectable=%s" % str(selectable_targets))
	# 超过铁索连环目标上限的提交必须被拒绝，证明补丁已进入提交校验。
	if _try_targets(0, [0, 1, 2]):
		return _fail("redirect_max_not_enforced")
	# 请求在失败提交后必须仍然可用，随后提交两个合法目标应成功。
	if _controller._pending_card_choice.is_empty():
		return _fail("redirect_request_lost")
	if not _submit_or_fail(0, [], [1, 2], "", true, "redirect_submit"):
		return false
	# 结算后两张牌名都被移除，且次数已消耗。
	var owner: PlayerState = _controller.state.get_player(0)
	if not owner.recorded_card_names.is_empty():
		return _fail("redirect_records_kept=%s" % str(owner.recorded_card_names))
	if _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("redirect_play_phase_limit")
	return true


## 校验【灵感】只用一张牌名时只移除该牌名，未被使用的记录必须保留。
func _test_linggan_removes_used_names() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("remove_install")
	_set_recorded_names(0, ["tiesuo", "nanman"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("remove_activate_rejected")
	# 效果取铁索连环（非全体模式），并且不重定向，因此会进入目标选择。
	if not _submit_or_fail(0, [], [], "tiesuo", true, "remove_effect"):
		return false
	if not _submit_or_fail(0, [], [], "", false, "remove_no_retarget"):
		return false
	if not _submit_or_fail(0, [], [1], "", true, "remove_targets"):
		return false
	# 只移除了使用过的牌名；未被使用的记录必须保留。
	var owner: PlayerState = _controller.state.get_player(0)
	if owner.recorded_card_names != ["nanman"]:
		return _fail("remove_used_names=%s" % str(owner.recorded_card_names))
	return true


## 校验【灵感】使用全体模式锦囊时直接结算：不询问目标，且目标由权威逻辑展开而不含使用者自己。
func _test_linggan_self_expanding_target_mode() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("expand_install")
	# 两张记录：保证第二步确认存在，从而验证“取消后仍直接结算全体模式”。
	_set_recorded_names(0, ["nanman", "tiesuo"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("expand_activate_rejected")
	if not _submit_or_fail(0, [], [], "nanman", true, "expand_effect"):
		return false
	# 第二步取消：不重定向。【南蛮入侵】是全体模式，应直接进入结算而不是请求玩家选择目标。
	# 这条断言同时保证群体锦囊不会被拆成“只指定部分目标”，也不会把使用者自己算作目标。
	if not _submit_or_fail(0, [], [], "", false, "expand_no_retarget"):
		return false
	var owner: PlayerState = _controller.state.get_player(0)
	if owner.hp != 6:
		return _fail("expand_self_damaged=%d" % owner.hp)
	# 结算已开始：出现【杀】响应请求，且请求者不是使用者本人。
	if _controller._pending_card_choice.is_empty():
		return _fail("expand_no_response_request")
	var responder_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	if responder_id == 0:
		return _fail("expand_self_targeted=%d" % responder_id)
	return true


## 校验效果取【无中生有】、目标模式取【南蛮入侵】时，所有其他角色都成为目标并各自结算摸牌。
func _test_linggan_all_others_target_mode_on_self_effect() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("wuzhong_expand_install")
	# 效果为自指的【无中生有】，目标模式改为全体的【南蛮入侵】：目标应由目标模式决定。
	_set_recorded_names(0, ["wuzhong", "nanman"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("wuzhong_expand_rejected")
	if not _submit_or_fail(0, [], [], "wuzhong", true, "wuzhong_expand_effect"):
		return false
	if not _submit_or_fail(0, [], [], "", true, "wuzhong_expand_confirm"):
		return false
	if not _submit_or_fail(0, [], [], "nanman", true, "wuzhong_expand_target_mode"):
		return false
	# 全体模式不请求目标选择，直接结算：两名其他角色各按【无中生有】摸2张，使用者自己不是目标。
	var hand_counts: Array[int] = []
	for player_id: int in range(3):
		hand_counts.append(_controller.state.get_player(player_id).hand.size())
	if hand_counts[0] != 0 or hand_counts[1] != 2 or hand_counts[2] != 2:
		return _fail("wuzhong_expand_hands=%s" % str(hand_counts))
	return true


## 校验效果取【万箭齐发】、目标模式取【无中生有】时，视为使用了一张目标为自己的万箭齐发。
func _test_linggan_self_target_mode() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("self_target_install")
	# 效果为全体的【万箭齐发】，目标模式改为自指的【无中生有】：只有使用者自己成为目标。
	_set_recorded_names(0, ["wanjian", "wuzhong"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("self_target_rejected")
	if not _submit_or_fail(0, [], [], "wanjian", true, "self_target_effect"):
		return false
	if not _submit_or_fail(0, [], [], "", true, "self_target_confirm"):
		return false
	if not _submit_or_fail(0, [], [], "wuzhong", true, "self_target_mode"):
		return false
	# 自指模式不请求目标选择：结算要求使用者自己对【万箭齐发】作出【闪】响应。
	if _controller._pending_card_choice.is_empty():
		return _fail("self_target_no_response_request")
	var responder_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	if responder_id != 0:
		return _fail("self_target_responder=%d" % responder_id)
	return true


## 校验记录中只有一张牌名时不再询问目标重定向，直接按该牌自身的目标规则结算。
func _test_linggan_single_name_skips_retarget_prompt() -> bool:
	_reset_state(3)
	if _install_skill(0, "linggan") == null:
		return _fail("single_name_install")
	_set_recorded_names(0, ["tiesuo"])
	if not _controller.activate_skill(0, "linggan", {"active_entry":"phaseUse"}):
		return _fail("single_name_rejected")
	if not _submit_or_fail(0, [], [], "tiesuo", true, "single_name_effect"):
		return false
	# 没有第二张记录牌名可作目标模式，因此不应出现确认步骤，而应直接进入目标选择。
	var context: Dictionary = _pending_context()
	if str(context.get("kind", "")) != "linggan_select_targets":
		return _fail("single_name_context=%s" % str(context))
	if not _submit_or_fail(0, [], [1], "", true, "single_name_targets"):
		return false
	# 只有一张牌名被使用，结算后记录必须清空。
	var owner: PlayerState = _controller.state.get_player(0)
	if not owner.recorded_card_names.is_empty():
		return _fail("single_name_records=%s" % str(owner.recorded_card_names))
	return true


## 校验【看破】令锦囊仅对持有者本人无效，不影响同牌的其他目标。
func _test_kanpo_negates_self_only() -> bool:
	_reset_state(3)
	if _install_skill(1, "kanpo") == null:
		return _fail("kanpo_install")
	_set_recorded_names(1, ["nanman"])
	# 玩家0对玩家1与玩家2使用【南蛮入侵】；处理区实体与用牌上下文按正式结构手工装配。
	var trick: CardInstance = CardInstance.new("nanman", "spade", 7)
	trick.zone = "processing"
	trick.owner_id = -1
	_controller.state.processing_area.append(trick)
	_controller._card_use_contexts[trick.uid] = {"actor_id":0, "card_definition_id":"nanman", "target_ids":[1, 2], "excluded_target_ids":[], "direct_hit_target_ids":[], "custom_args":{}, "virtual_storage":{}}
	# 触发“成为目标”时机；player_id为看破持有者，source为使用者，target为被指定的目标。
	_controller._emit_rule_timing("useCardToTargeted", 1, 0, 1, {"timing_name":"useCardToTargeted", "card_uid":trick.uid, "card_id":"nanman", "target_id":1})
	var context: Dictionary = _pending_context()
	if str(context.get("kind", "")) != "kanpo_confirm" or str(context.get("trick_id", "")) != "nanman":
		return _fail("kanpo_entry=%s" % str(context))
	if not _submit_or_fail(1, [], [], "", true, "kanpo_confirm"):
		return false
	# 仅移除记录并令该牌对持有者本人无效；另一名目标不受影响。
	var holder: PlayerState = _controller.state.get_player(1)
	if not holder.recorded_card_names.is_empty():
		return _fail("kanpo_record_kept=%s" % str(holder.recorded_card_names))
	var excluded: Array = (_controller._card_use_contexts.get(trick.uid, {}) as Dictionary).get("excluded_target_ids", []) as Array
	if excluded != [1]:
		return _fail("kanpo_excluded=%s" % str(excluded))
	# 每轮限一次；同一轮内再次成为目标不再询问。
	_controller._emit_rule_timing("useCardToTargeted", 1, 0, 1, {"timing_name":"useCardToTargeted", "card_uid":trick.uid, "card_id":"nanman", "target_id":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("kanpo_round_limit")
	_controller.state.processing_area.erase(trick)
	_controller._card_use_contexts.erase(trick.uid)
	return true


## 校验【看破】的发动前提：无记录、自己使用、非锦囊都不开放入口。
func _test_kanpo_preconditions() -> bool:
	_reset_state(3)
	if _install_skill(1, "kanpo") == null:
		return _fail("precondition_install")
	# 前提一：记录中没有该牌名。
	_set_recorded_names(1, ["tiesuo"])
	var trick_uid: int = _build_trick_context(0, "nanman", [1, 2])
	_controller._emit_rule_timing("useCardToTargeted", 1, 0, 1, {"timing_name":"useCardToTargeted", "card_uid":trick_uid, "card_id":"nanman", "target_id":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("precondition_unrecorded")
	_erase_trick_context(trick_uid)
	# 前提二：持有者自己使用该锦囊。
	_set_recorded_names(1, ["nanman"])
	var self_trick_uid: int = _build_trick_context(1, "nanman", [1, 2])
	_controller._emit_rule_timing("useCardToTargeted", 1, 1, 1, {"timing_name":"useCardToTargeted", "card_uid":self_trick_uid, "card_id":"nanman", "target_id":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("precondition_self_actor")
	_erase_trick_context(self_trick_uid)
	# 前提三：非锦囊牌（【杀】）不触发看破。
	_set_recorded_names(1, ["sha"])
	var slash_uid: int = _build_trick_context(0, "sha", [1], "processing")
	_controller._emit_rule_timing("useCardToTargeted", 1, 0, 1, {"timing_name":"useCardToTargeted", "card_uid":slash_uid, "card_id":"sha", "target_id":1})
	if not _controller._pending_card_choice.is_empty():
		return _fail("precondition_not_trick")
	_erase_trick_context(slash_uid)
	return true


## 校验三条技能的AI钩子都能对合法动作给出正分；AI不得访问宿主，只能读快照。
func _test_ai_hooks_positive() -> bool:
	_reset_state(3)
	if not _install_daheita_skills(0):
		return _fail("ai_install")
	_set_recorded_names(0, ["nanman", "tiesuo"])
	# 手牌；解构需要一个可记录的锦囊候选。
	var nanman_uid: int = _give_card(0, "nanman", "spade", 1)
	# 权威快照；与正式AI入口一致，必须先补写限定技用量字段。
	var snapshot: Dictionary = _controller.state.to_dict(0, true)
	_controller._append_limited_skill_usage_to_snapshot(snapshot)
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new()
	# 【解构】选牌评分；重铸换牌加首次记录必须为正。
	var jiegou: SkillDefinition = _controller.get_skill_instance(0, "jiegou")
	if jiegou == null:
		return _fail("ai_jiegou_missing")
	var jiegou_request: Dictionary = {"context":{"kind":"jiegou_recast"}, "candidates":[{"uid":nanman_uid, "card_data":{"definition_id":"nanman"}}]}
	var jiegou_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[nanman_uid]}}
	var jiegou_score: float = jiegou.score_ai_choice(snapshot, jiegou_request, jiegou_action, evaluator)
	if jiegou_score <= 0.0:
		return _fail("ai_jiegou_score=%f" % jiegou_score)
	# 【解构】发动动作评分；基类 score_ai_action 默认返回 0.0 会让AI判定本技能毫无价值而永不发动。
	var jiegou_activate_score: float = jiegou.score_ai_action(snapshot, {"action_type":"use_skill", "actor_id":0, "skill_id":"jiegou"}, evaluator)
	if jiegou_activate_score <= 0.0:
		return _fail("ai_jiegou_activate_score=%f" % jiegou_activate_score)
	# 【灵感】选效果牌名评分。
	var linggan: SkillDefinition = _controller.get_skill_instance(0, "linggan")
	if linggan == null:
		return _fail("ai_linggan_missing")
	var linggan_request: Dictionary = {"context":{"kind":"linggan_pick_effect"}, "control_options":[{"id":"nanman", "label":"南蛮入侵"}, {"id":"tiesuo", "label":"铁索连环"}]}
	var linggan_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"nanman"}}
	var linggan_score: float = linggan.score_ai_choice(snapshot, linggan_request, linggan_action, evaluator)
	if linggan_score <= 0.0:
		return _fail("ai_linggan_score=%f" % linggan_score)
	# 【灵感】发动动作评分；同源问题，不覆盖基类默认0分则记录再多也不会被AI使用。
	var linggan_activate_score: float = linggan.score_ai_action(snapshot, {"action_type":"use_skill", "actor_id":0, "skill_id":"linggan"}, evaluator)
	if linggan_activate_score <= 0.0:
		return _fail("ai_linggan_activate_score=%f" % linggan_activate_score)
	# 【灵感】目标模式重定向评分；单体效果改群体目标应获得额外加成。
	var retarget_request: Dictionary = {"context":{"kind":"linggan_pick_target_mode", "effect_id":"tiesuo"}, "control_options":[{"id":"nanman", "label":"南蛮入侵"}]}
	var retarget_action: Dictionary = {"payload":{"confirmed":true, "selected_control_id":"nanman"}}
	var retarget_score: float = linggan.score_ai_choice(snapshot, retarget_request, retarget_action, evaluator)
	if retarget_score <= 0.0:
		return _fail("ai_retarget_score=%f" % retarget_score)
	# 【看破】确认评分；抵消不利锦囊必须为正。
	var kanpo: SkillDefinition = _controller.get_skill_instance(0, "kanpo")
	if kanpo == null:
		return _fail("ai_kanpo_missing")
	var kanpo_request: Dictionary = {"context":{"kind":"kanpo_confirm", "trick_id":"nanman"}}
	var kanpo_action: Dictionary = {"payload":{"confirmed":true}}
	var kanpo_score: float = kanpo.score_ai_choice(snapshot, kanpo_request, kanpo_action, evaluator)
	if kanpo_score <= 0.0:
		return _fail("ai_kanpo_score=%f" % kanpo_score)
	return true


## 装配一张处理区锦囊及其用牌上下文；返回牌UID供时机触发使用。
func _build_trick_context(actor_id: int, definition_id: String, target_ids: Array[int], zone: String = "processing") -> int:
	var trick: CardInstance = CardInstance.new(definition_id, "spade", 7)
	trick.zone = zone
	trick.owner_id = -1
	_controller.state.processing_area.append(trick)
	_controller._card_use_contexts[trick.uid] = {"actor_id":actor_id, "card_definition_id":definition_id, "target_ids":target_ids.duplicate(), "excluded_target_ids":[], "direct_hit_target_ids":[], "custom_args":{}, "virtual_storage":{}}
	return trick.uid


## 清理手工装配的处理区实体与用牌上下文。
func _erase_trick_context(card_uid: int) -> void:
	for processing_card: CardInstance in _controller.state.processing_area:
		if processing_card.uid == card_uid:
			_controller.state.processing_area.erase(processing_card)
			break
	_controller._card_use_contexts.erase(card_uid)
	_controller._pending_card_choice.clear()


## 输出失败原因并以非零状态结束当前无头测试。
func _fail(reason: String) -> bool:
	printerr("DAHEITA_FAIL %s" % reason)
	get_tree().quit(1)
	return false
