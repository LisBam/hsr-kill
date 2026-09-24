extends Node

## 翁法罗斯新增武将专项回归。覆盖精确元数据、军功与奇袭、堪杀、负火、区域废除、特殊形态往返及永劫轮回状态。

## 本测试共用的权威对局控制器；每项用例通过正式规则服务和技能实例执行。
var _controller: MatchController

## 最近一次状态广播中的当前请求快照；界面只读取该字段决定是否开放手牌与出牌控件。
var _last_broadcast_choice: Dictionary = {}


## 延迟一帧开始回归，确保GameDatabase已经完成目录扫描与静态校验。
func _ready() -> void:
	call_deferred("_run")


## 顺序执行全部翁法罗斯新增内容断言；任一失败立即以非零状态退出。
func _run() -> void:
	_create_controller()
	if not _test_metadata_and_special_pool():
		return
	if not _test_eternal_exit_and_zone_rules():
		return
	if not _test_shengbian_qixi_and_kansha():
		return
	if not _test_fuhuo_independent_limits():
		return
	if not _test_lunhui_and_yongjie_return():
		return
	if not _test_yongjie_wheel_and_tiancai():
		return
	if not _test_tiancai_play_choice_broadcast():
		return
	if not _test_active_virtual_card_skills():
		return
	print("OMPHALOS_TRANSFORM_PASS")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器和离线网关。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能触发与轮回生命周期共用该节点。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；技能评分测试与正式身份态度查询保持一致。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；状态广播沿用正式单机路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	_controller.game_flow_interval_seconds = 0.0


## 为单项测试创建最小身份局状态并重建所有规则服务；0号领袖、1号反贼、其余忠臣形成确定敌我关系。
func _reset_state(player_count: int) -> void:
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "omphalos-transform"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试角色；全部身份明置，使AI与友方接口得到稳定结果。
		var player: PlayerState = PlayerState.new(player_id, "翁法罗斯测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist")
		player.identity_revealed = true
		player.character_id = "wandi"
		player.character_generation = 1
		player.max_hp = 5
		player.hp = 5
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._pending_damage_finalizations.clear()
	_controller._pending_dying_start_contexts.clear()
	_controller._deferred_skill_settlements.clear()


## 安装指定技能并返回独立运行时实例；绑定与安装顺序和正式武将技能一致。
func _install_skill(player_id: int, skill_id: String) -> SkillDefinition:
	# 新技能实例；数据库必须能按稳定ID创建。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null:
		return null
	skill.bind(_controller, player_id)
	# 当前玩家技能表；同一测试可逐项组合一个武将的多个组件。
	var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
	player_skills[skill_id] = skill
	_controller.skill_instances_by_player[player_id] = player_skills
	skill.install()
	return skill


## 向牌堆加入指定数量测试牌；固定使用方片【闪】，保证摸牌不会因牌堆耗尽结束对局。
func _add_draw_cards(count: int) -> void:
	for card_index: int in range(maxi(count, 0)):
		# 当前测试牌；UID由CardInstance自动分配，区域显式标记为摸牌堆。
		var card: CardInstance = CardInstance.new("shan", "diamond", card_index % 13 + 1)
		card.zone = "draw_pile"
		_controller.state.draw_pile.append(card)


## 校验三名武将、八项技能精确原文与卡厄斯兰那的特殊抽取过滤。
func _test_metadata_and_special_pool() -> bool:
	# 刻律德菈定义；女性、3上限、翁法罗斯与双技能顺序必须稳定。
	var kelvdela: Dictionary = GameDatabase.get_character("kelvdela")
	# 白厄定义；男性、4上限与负火/轮回顺序必须稳定。
	var baie: Dictionary = GameDatabase.get_character("baie")
	# 卡厄斯兰那定义；男性、5上限、三技能与special=true必须稳定。
	var kaesilanna: Dictionary = GameDatabase.get_character("kaesilanna")
	if str(kelvdela.get("display_name", "")) != "刻律德菈" or str(kelvdela.get("gender", "")) != "female" or str(kelvdela.get("faction", "")) != "wengfaluosi" or int(kelvdela.get("max_hp", 0)) != 3 or kelvdela.get("skills", []) != ["shengbian", "kansha"]:
		return _fail("kelvdela_metadata=%s" % kelvdela)
	if str(baie.get("display_name", "")) != "白厄" or str(baie.get("gender", "")) != "male" or int(baie.get("max_hp", 0)) != 4 or baie.get("skills", []) != ["fuhuo", "lunhui"]:
		return _fail("baie_metadata=%s" % baie)
	if str(kaesilanna.get("display_name", "")) != "卡厄斯兰那" or int(kaesilanna.get("max_hp", 0)) != 5 or not bool(kaesilanna.get("special", false)) or kaesilanna.get("skills", []) != ["tiancai", "shihun", "yongjie"]:
		return _fail("kaesilanna_metadata=%s" % kaesilanna)
	# 需求指定八项技能原文；任何字符、标点、数字或X说明变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"shengbian":"轮回技，出牌阶段限一次，你可选择一名角色，若其有“军功”标记，你令其获得X枚“军功”标记；若其没有“军功”标记，你移除场上所有的“军功”标记，并令其获得2枚“军功”标记。拥有“军功”标记的角色视为拥有技能“奇袭”。（X为此技能的轮回数且至多为5）",
		"kansha":"轮回技，出牌阶段每个轮回节限一次，你可①弃置一张红色牌；②弃置一张黑色牌；③对一名其他角色造成1点伤害。",
		"qixi":"锁定技，当你发动非限定技、觉醒技、锁定技的技能后，若你的“军功”标记数少于6，你获得一枚“军功”标记；否则你将“军功”标记数移除至1，然后额外发动一次所发动的技能，若该技能有目标，则保持目标不变。",
		"fuhuo":"锁定技，每回合每项限一次，1.当你使用一张牌时，2.当你成为牌的目标时，3.当你受到伤害时，4.当你造成伤害时，若你的“火种”标记数小于12，你获得一枚“火种”标记，然后若你的手牌数小于5，你摸一张牌。",
		"lunhui":"觉醒技，一名角色回合结束时，若拥有的“火种”不少于12，你移除所有“火种”，废除装备区与判定区，令所有友方角色离场，将所有其他角色的武将牌翻面，将你的武将牌替换为“卡厄斯兰那”，将体力值回复至体力上限，然后进行一个额外回合。",
		"tiancai":"轮回技，出牌阶段，你可①受到无伤害来源的X点火焰伤害；②视为对至多X名角色各使用一张【火攻】。③视为对一名角色依次使用X-1张【火攻】。（X为此技能的轮回数）",
		"shihun":"轮回技，出牌阶段，你可①令任意名其他角色依次视为对你使用一张火【杀】；②视为使用一张目标为上次发动此技能所指定目标的火【杀】。",
		"yongjie":"锁定技，轮回技，你手牌中的非伤害牌均视为无距离限制的火【杀】。当你造成火焰伤害后，①你令你的所有其他轮回技进入每回合限一次的永劫状态；②摸一张牌；③摸一张牌并退出所有其他轮回技的永劫状态。当你体力值不大于0时，你将体力值回复至2点，恢复装备区与判定区，将武将牌替换为“白厄”，并复原武将牌上的技能，然后所有友方角色返场。",
	}
	for skill_id_variant: Variant in expected_descriptions.keys():
		# 当前技能稳定ID；数据库原文必须与需求文本逐字相同。
		var skill_id: String = str(skill_id_variant)
		if str(GameDatabase.get_skill(skill_id).get("description", "")) != str(expected_descriptions[skill_id]):
			return _fail("skill_description=%s" % skill_id)
	# 普通与显式特殊武将池；特殊形态不得被普通选将抽取，但显式规则仍可查到。
	var normal_pool: Array[String] = GameDatabase.get_selectable_character_ids()
	# 包含特殊武将的显式池；应当保留卡厄斯兰那供指定换形规则使用。
	var explicit_pool: Array[String] = GameDatabase.get_selectable_character_ids(true)
	if normal_pool.has("kaesilanna") or not explicit_pool.has("kaesilanna"):
		return _fail("kaesilanna_special_pool")
	return true


## 校验退出永劫保持轮回进度，以及废除区域会清牌、序列化并阻止后续装备与延时锦囊进入。
func _test_eternal_exit_and_zone_rules() -> bool:
	_reset_state(2)
	# 单独安装血仇作为两节轮回样本；先推进至②再进入与退出永劫。
	var xvechou: SkillDefinition = _install_skill(0, "xvechou")
	if xvechou == null or not xvechou.begin_reincarnation_activation() or not xvechou.complete_reincarnation_activation() or not _controller.enter_eternal_reincarnation_state(0, "xvechou", 1):
		return _fail("eternal_setup")
	# 退出前轮回节与轮回数；退出后必须完全保持，只清除永劫及额度字段。
	var before_exit: Dictionary = xvechou.get_reincarnation_state()
	if not _controller.exit_eternal_reincarnation_state(0, "xvechou"):
		return _fail("eternal_exit_rejected")
	# 退出永劫后的轮回状态；用于与before_exit逐项对比轮回节与轮回数。
	var after_exit: Dictionary = xvechou.get_reincarnation_state()
	if bool(after_exit.get("eternal", true)) or int(after_exit.get("section_index", -1)) != int(before_exit.get("section_index", -2)) or int(after_exit.get("round_count", -1)) != int(before_exit.get("round_count", -2)):
		return _fail("eternal_exit_state=%s/%s" % [before_exit, after_exit])
	# 现有装备与判定牌；废除区域时均应进入弃牌堆。
	var owner: PlayerState = _controller.state.get_player(0)
	# 预置于装备区的诸葛连弩实体；用于验证废除时的标准弃置。
	var equipment_card: CardInstance = CardInstance.new("zhuge", "club", 1)
	equipment_card.zone = "equipment"
	equipment_card.owner_id = 0
	owner.equipment["weapon"] = equipment_card
	# 预置于判定区的闪电实体；用于验证废除时的标准弃置。
	var delayed_card: CardInstance = CardInstance.new("shandian", "spade", 1)
	delayed_card.zone = "judgment"
	delayed_card.owner_id = 0
	owner.judgment_area.append(delayed_card)
	if not _controller.set_player_zones_abolished(0, true, true, "test") or not owner.equipment.is_empty() or not owner.judgment_area.is_empty() or _controller.state.discard_pile.size() != 2:
		return _fail("abolish_clear=%s/%s/%d" % [owner.equipment, owner.judgment_area, _controller.state.discard_pile.size()])
	# 装备与延时锦囊使用前校验；废除状态应直接提供明确拒绝。
	if _controller.card_rules.validate_virtual_use(0, "zhuge", [0]).is_empty():
		return _fail("abolished_equipment_allowed")
	_controller.state.current_player_id = 1
	if _controller.card_rules.validate_virtual_use(1, "lebu", [0]).is_empty():
		return _fail("abolished_judgment_allowed")
	# 权威快照与存档恢复必须保留区域废除状态；私有形态数据仅在权威快照中出现。
	owner.character_form_state["test_key"] = [1]
	# 持有者权威快照；包含形态私有状态并供存档恢复。
	var authoritative_player_data: Dictionary = owner.to_dict(0, true)
	# 其他观察者公开快照；形态私有字段必须被裁剪为空字典。
	var public_player_data: Dictionary = owner.to_dict(1, false)
	# 从权威数据重建的玩家状态；用于校验废除布尔值与私有形态数据。
	var restored_owner: PlayerState = PlayerState.from_authoritative_dict(authoritative_player_data)
	if not restored_owner.equipment_area_abolished or not restored_owner.judgment_area_abolished or restored_owner.character_form_state.get("test_key", []) != [1] or not (public_player_data.get("character_form_state", {}) as Dictionary).is_empty():
		return _fail("abolished_serialization")
	if not _controller.set_player_zones_abolished(0, false, false, "test_restore") or owner.equipment_area_abolished or owner.judgment_area_abolished:
		return _fail("zone_restore")
	return true


## 校验升变的重置/增长、军功动态奇袭和目标保持重演，并验证堪杀三节与阶段额度。
func _test_shengbian_qixi_and_kansha() -> bool:
	_reset_state(3)
	# 刻律德菈状态与技能；0号领袖和2号忠臣为友方。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kelvdela"
	owner.max_hp = 3
	owner.hp = 3
	# 刻律德菈的升变实例；负责军功、奇袭授予与单节轮回验证。
	var shengbian: SkillDefinition = _install_skill(0, "shengbian")
	# 刻律德菈的堪杀实例；负责红黑费用、伤害节与每节阶段限次验证。
	var kansha: SkillDefinition = _install_skill(0, "kansha")
	if shengbian == null or kansha == null:
		return _fail("kelvdela_skill_install")
	# 当前阶段全部合法动作；无手牌时应至少包含升变对合法角色的免费军功分配动作。
	var shengbian_legal_actions: Array[Dictionary] = _controller.get_legal_actions(0)
	# 标准基础AI策略；临时评分技能没有运行时宿主，必须只读权威快照仍能稳定选择升变。
	var shengbian_ai_policy: BasicAIPolicy = BasicAIPolicy.new(0)
	# AI最终动作；升变具有正基础收益，当前没有更高价值动作时应基本每阶段主动发动。
	var shengbian_ai_action: Dictionary = shengbian_ai_policy.choose_action(_controller.state.to_dict(0, true), shengbian_legal_actions)
	if str(shengbian_ai_action.get("action_type", "")) != "use_skill" or str(shengbian_ai_action.get("skill_id", (shengbian_ai_action.get("payload", {}) as Dictionary).get("skill_id", ""))) != "shengbian":
		return _fail("shengbian_ai_action=%s/%s" % [shengbian_ai_action, shengbian_legal_actions])
	# 无军功友方进入重置分支，获得2枚军功并立即动态拥有奇袭；单节轮回推进至X=2。
	if shengbian.activate({"target_ids":[2]}) != "":
		return _fail("shengbian_initial_activate")
	# 获得军功的2号友方；用于检查动态奇袭来源与标记数量。
	var ally: PlayerState = _controller.state.get_player(2)
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 2 or _controller.get_skill_instance(2, "qixi") == null or str((ally.acquired_skills.get("qixi", {}) as Dictionary).get("source", "")) != "shengbian_jungong" or shengbian.get_reincarnation_round_count() != 2:
		return _fail("shengbian_initial=%s/%s" % [_controller.get_player_mark(2, "jungong"), ally.acquired_skills])
	# 新出牌阶段恢复普通额度；已有军功友方按X=2增加至4，不清除其他角色标记。
	_controller.emit_rule_timing("phaseUseBegin", 0, 0, 0, {"turn_number":1})
	if shengbian.activate({"target_ids":[2]}) != "" or int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 4:
		return _fail("shengbian_growth=%s" % _controller.get_player_mark(2, "jungong"))
	# 为友方安装可重演的升变并把军功调至6；本次原效果加1后奇袭重置至1，再保持目标额外发动并以X=2加至3。
	_controller.state.current_player_id = 2
	# 2号友方的升变实例；作为【奇袭】通用额外发动和原目标保持样本。
	var ally_shengbian: SkillDefinition = _install_skill(2, "shengbian")
	_controller.change_player_mark_count(2, "jungong", 2, {"icon":"军", "name":"军功", "description":"测试军功"})
	if ally_shengbian == null or ally_shengbian.activate({"target_ids":[2]}) != "":
		return _fail("qixi_repeat_setup")
	_controller._resume_deferred_skill_settlements()
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 3 or ally_shengbian.get_reincarnation_round_count() != 3:
		return _fail("qixi_repeat_result=%s/%s" % [_controller.get_player_mark(2, "jungong"), ally_shengbian.get_reincarnation_state()])
	# 回到刻律德菈出牌阶段并准备一红一黑费用牌；堪杀应依次执行①②③。
	_controller.state.current_player_id = 0
	# 堪杀①的红色手牌费用；红桃2【闪】应当在发动后进入弃牌堆。
	var red_card: CardInstance = CardInstance.new("shan", "heart", 2)
	red_card.zone = "hand"
	red_card.owner_id = 0
	owner.hand.append(red_card)
	# 堪杀②的黑色手牌费用；黑桃3【闪】应当在发动后进入弃牌堆。
	var black_card: CardInstance = CardInstance.new("shan", "spade", 3)
	black_card.zone = "hand"
	black_card.owner_id = 0
	owner.hand.append(black_card)
	_controller.reincarnation_skill_service.on_play_phase_started(0)
	if kansha.activate({"card_uid":red_card.uid}) != "" or kansha.get_reincarnation_section_index() != 1:
		return _fail("kansha_red=%s" % kansha.get_reincarnation_state())
	if kansha.activate({"card_uid":black_card.uid}) != "" or kansha.get_reincarnation_section_index() != 2:
		return _fail("kansha_black=%s" % kansha.get_reincarnation_state())
	# ③对反贼造成1点伤害后回到①且X=2；同一出牌阶段①已用过，因此不能再次发动。
	var enemy: PlayerState = _controller.state.get_player(1)
	# 堪杀③结算前的敌方体力；结算后必须恰好减少1。
	var enemy_hp_before: int = enemy.hp
	if kansha.activate({"target_ids":[1]}) != "" or enemy.hp != enemy_hp_before - 1 or kansha.get_reincarnation_round_count() != 2 or kansha.get_reincarnation_section_index() != 0 or kansha.can_activate():
		return _fail("kansha_damage=%d/%s" % [enemy.hp, kansha.get_reincarnation_state()])
	return true


## 校验负火四项额度彼此独立、同项不重复、跨回合恢复且12枚上限后不再摸牌。
func _test_fuhuo_independent_limits() -> bool:
	_reset_state(2)
	_add_draw_cards(16)
	# 白厄状态与负火实例；初始0手牌、0火种。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "baie"
	owner.max_hp = 4
	owner.hp = 4
	# 白厄的负火实例；用于派发四类时机并校验独立次数。
	var fuhuo: SkillDefinition = _install_skill(0, "fuhuo")
	if fuhuo == null:
		return _fail("fuhuo_install")
	# 第1项重复两次只取一次；随后第2、3、4项各自再触发一次。
	_controller.emit_rule_timing("useCard", 0, 0, -1, {"card_id":"shan", "card_uid":101})
	_controller.emit_rule_timing("useCard", 0, 0, -1, {"card_id":"shan", "card_uid":102})
	_controller.emit_rule_timing("useCardToTargeted", 0, 1, 0, {"card_id":"sha", "card_uid":103, "target_id":0})
	_controller.emit_rule_timing("damageAfter", 0, 1, 0, {"amount":1, "nature":"normal", "damage_event_id":104})
	_controller.emit_rule_timing("damageAfter", 1, 0, 1, {"amount":1, "nature":"normal", "damage_event_id":105})
	if int(_controller.get_player_mark(0, "huozhong").get("count", 0)) != 4 or owner.hand.size() != 4:
		return _fail("fuhuo_four_items=%s/%d" % [_controller.get_player_mark(0, "huozhong"), owner.hand.size()])
	# 新全局回合恢复四项额度；再次用牌增加第5枚火种，并因触发前手牌4张摸至5张。
	_controller.state.turn_number = 2
	_controller.emit_rule_timing("useCard", 0, 0, -1, {"card_id":"shan", "card_uid":106})
	if int(_controller.get_player_mark(0, "huozhong").get("count", 0)) != 5 or owner.hand.size() != 5:
		return _fail("fuhuo_next_turn=%s/%d" % [_controller.get_player_mark(0, "huozhong"), owner.hand.size()])
	# 达到12枚后原文条件不成立；下一回合任何项目均不消费额度、不增加标记也不摸牌。
	_controller.change_player_mark_count(0, "huozhong", 7, {"icon":"火", "name":"火种", "description":"测试火种"})
	_controller.state.turn_number = 3
	# 火种已达上限时的手牌数；后续时机不得改变该数值。
	var hand_count_before: int = owner.hand.size()
	_controller.emit_rule_timing("useCard", 0, 0, -1, {"card_id":"shan", "card_uid":107})
	if int(_controller.get_player_mark(0, "huozhong").get("count", 0)) != 12 or owner.hand.size() != hand_count_before:
		return _fail("fuhuo_cap")
	return true


## 校验白厄觉醒为特殊形态以及永劫濒死时按精确顺序恢复白厄、区域、技能和友方。
func _test_lunhui_and_yongjie_return() -> bool:
	_reset_state(4)
	_add_draw_cards(8)
	# 白厄状态；保留2点体力以验证换形态后回复至5点上限。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "baie"
	owner.max_hp = 4
	owner.hp = 2
	# 白厄的负火实例；确保换形前固有技能组安装完整。
	var fuhuo: SkillDefinition = _install_skill(0, "fuhuo")
	# 白厄的轮回觉醒实例；负责触发区域废除、离场、翻面、换形和额外回合。
	var lunhui: SkillDefinition = _install_skill(0, "lunhui")
	if fuhuo == null or lunhui == null:
		return _fail("baie_skill_install")
	# 白厄觉醒前的诸葛连弩实体；用于检查装备区废除会清空既有牌。
	var equipment_card: CardInstance = CardInstance.new("zhuge", "club", 1)
	equipment_card.zone = "equipment"
	equipment_card.owner_id = 0
	owner.equipment["weapon"] = equipment_card
	# 白厄觉醒前的闪电实体；用于检查判定区废除会清空既有牌。
	var delayed_card: CardInstance = CardInstance.new("shandian", "spade", 1)
	delayed_card.zone = "judgment"
	delayed_card.owner_id = 0
	owner.judgment_area.append(delayed_card)
	# 觉醒前已因其他效果离场的3号友方；永劫的“所有友方角色返场”也必须恢复该角色。
	var preexisting_out_of_game_ally: PlayerState = _controller.state.get_player(3)
	preexisting_out_of_game_ally.out_of_game = true
	_controller.change_player_mark_count(0, "huozhong", 12, {"icon":"火", "name":"火种", "description":"测试火种"})
	_controller.emit_rule_timing("phaseAfter", 1, 1, 1, {"turn_number":1})
	# 忠臣2因轮回离场且忠臣3保持既有离场，反贼1翻面；白厄变为5上限满体力特殊形态并排入额外回合。
	if owner.character_id != "kaesilanna" or owner.max_hp != 5 or owner.hp != 5 or not owner.equipment_area_abolished or not owner.judgment_area_abolished or not _controller.get_player_mark(0, "huozhong").is_empty():
		return _fail("lunhui_owner=%s/%d/%d" % [owner.character_id, owner.max_hp, owner.hp])
	if not _controller.state.get_player(2).out_of_game or not _controller.state.get_player(3).out_of_game or _controller.state.get_player(1).out_of_game or not _controller.state.get_player(1).face_down or not _controller._extra_turn_queue.has(0):
		return _fail("lunhui_others")
	if _controller.get_skill_instance(0, "yongjie") == null or _controller.get_skill_instance(0, "lunhui") != null:
		return _fail("lunhui_skill_replace")
	# 卡厄斯兰那进入濒死；永劫应回复至2、开放区域、换回白厄、复原技能并让两名原离场友方返场。
	owner.hp = 0
	_controller.emit_rule_timing("dyingBegin", 0, -1, 0, {"hp":0, "required_recover":1})
	if owner.character_id != "baie" or owner.max_hp != 4 or owner.hp != 2 or owner.equipment_area_abolished or owner.judgment_area_abolished:
		return _fail("yongjie_return_owner=%s/%d/%d" % [owner.character_id, owner.max_hp, owner.hp])
	if _controller.state.get_player(2).out_of_game or _controller.state.get_player(3).out_of_game or _controller.get_skill_instance(0, "fuhuo") == null or _controller.get_skill_instance(0, "lunhui") == null or _controller.get_skill_instance(0, "yongjie") != null:
		return _fail("yongjie_return_allies_or_skills")
	# 复原后的觉醒技必须恢复限定额度，允许下一次重新达到条件后觉醒。
	var restored_lunhui: SkillDefinition = _controller.get_skill_instance(0, "lunhui")
	if restored_lunhui == null or not restored_lunhui.has_available_intrinsic_use():
		return _fail("yongjie_restore_awaken")
	return true


## 校验永劫火焰伤害三节会进入/退出其他轮回技永劫，并验证天裁①的无来源火焰伤害与推进。
func _test_yongjie_wheel_and_tiancai() -> bool:
	_reset_state(3)
	_add_draw_cards(8)
	# 卡厄斯兰那状态与三项技能；仅使用直接时机测试，不创建火攻或火杀响应窗口。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	# 卡厄斯兰那的天裁实例；同时作为永劫进退的“其他轮回技”样本。
	var tiancai: SkillDefinition = _install_skill(0, "tiancai")
	# 卡厄斯兰那的弑魂实例；作为第二个永劫进退样本。
	var shihun: SkillDefinition = _install_skill(0, "shihun")
	# 卡厄斯兰那的永劫实例；用于推进三节火焰伤害锁定效果。
	var yongjie: SkillDefinition = _install_skill(0, "yongjie")
	if tiancai == null or shihun == null or yongjie == null:
		return _fail("kaesilanna_skill_install")
	# 第一次火焰伤害执行①，使天裁与弑魂进入每回合限一次永劫，永劫自身进入②。
	_controller.emit_rule_timing("damageAfter", 1, 0, 1, {"amount":1, "nature":"fire", "damage_event_id":201})
	# 天裁进入永劫后的轮回状态；用于检查锁节与每回合额度。
	var tiancai_state: Dictionary = tiancai.get_reincarnation_state()
	# 弑魂进入永劫后的轮回状态；用于检查两个其他轮回技都被处理。
	var shihun_state: Dictionary = shihun.get_reincarnation_state()
	if not bool(tiancai_state.get("eternal", false)) or int(tiancai_state.get("eternal_per_turn_limit", 0)) != 1 or not bool(shihun_state.get("eternal", false)) or yongjie.get_reincarnation_section_index() != 1:
		return _fail("yongjie_enter_eternal=%s/%s/%s" % [tiancai_state, shihun_state, yongjie.get_reincarnation_state()])
	# 第二与第三次火焰伤害各摸1张；③完成后退出所有其他轮回技永劫并进入下一轮回①。
	_controller.emit_rule_timing("damageAfter", 1, 0, 1, {"amount":1, "nature":"fire", "damage_event_id":202})
	_controller.emit_rule_timing("damageAfter", 1, 0, 1, {"amount":1, "nature":"fire", "damage_event_id":203})
	if owner.hand.size() != 2 or bool(tiancai.get_reincarnation_state().get("eternal", true)) or bool(shihun.get_reincarnation_state().get("eternal", true)) or yongjie.get_reincarnation_round_count() != 2 or yongjie.get_reincarnation_section_index() != 0:
		return _fail("yongjie_exit_eternal=%d/%s/%s/%s" % [owner.hand.size(), tiancai.get_reincarnation_state(), shihun.get_reincarnation_state(), yongjie.get_reincarnation_state()])
	# 单独重置状态测试天裁①；无来源1点火焰伤害令体力5→4且进入②，不会被“造成伤害”来源规则误认。
	_reset_state(2)
	owner = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	tiancai = _install_skill(0, "tiancai")
	if tiancai == null or tiancai.activate({}) != "" or owner.hp != 4 or tiancai.get_reincarnation_section_index() != 1 or tiancai.get_reincarnation_round_count() != 1:
		return _fail("tiancai_self_fire=%d/%s" % [owner.hp, tiancai.get_reincarnation_state() if tiancai != null else {}])
	return true


## 校验回合内主动技能结算后，权威出牌窗口与界面可见请求同步恢复。
## 【天裁】①是不创建任何子选择的同步轮回节：若只重建请求而不重新广播，界面快照会停在“无请求”状态，
## 手牌、确定/取消与结束回合按钮会全部失效，只能靠再次点击技能按钮被动恢复。
func _test_tiancai_play_choice_broadcast() -> bool:
	_reset_state(3)
	# 本用例需要真实出牌请求与界面广播；独立对局ID避免复用其他用例的根事件标识。
	_controller.state.match_id = "omphalos-transform-play-choice"
	# 天裁持有者；5点体力用于核对①的无来源1点火焰伤害。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kaesilanna"
	owner.max_hp = 5
	owner.hp = 5
	# 天裁运行时实例；本用例只通过正式动作入口发动，不直接调用技能对象。
	var tiancai: SkillDefinition = _install_skill(0, "tiancai")
	if tiancai == null:
		return _fail("tiancai_play_choice_install")
	# 界面可见请求记录；每次广播覆盖为界面真正读取的 current_choice_request 字段。
	_last_broadcast_choice = {}
	_controller.state_changed.connect(_on_state_changed)
	# 正式出牌窗口；主动技能必须先完成该请求，技能内部子选择才会接在它之后。
	_controller.event_scheduler.reset()
	_controller.call("_begin_play_choice", 0)
	if not bool(_controller.call("_has_active_play_choice")):
		return _fail("tiancai_play_choice_begin")
	# 正式主动技能动作；payload 只携带稳定技能ID，与界面技能按钮提交完全一致。
	var action: PlayerAction = PlayerAction.new("use_skill", 0)
	action.payload = {"skill_id":"tiancai"}
	if not _controller.submit_action(action):
		return _fail("tiancai_play_choice_submit")
	# 界面最后一次收到的请求类型；必须仍是本回合的 chooseToUse，界面才会重新开放手牌与操作按钮。
	var broadcast_choice_type: String = str(_last_broadcast_choice.get("choice_type", ""))
	# 广播中的请求行动者；非本人请求不会开放本地出牌控件。
	var broadcast_actor_id: int = int(_last_broadcast_choice.get("actor_id", -1))
	if owner.hp != 4 or tiancai.get_reincarnation_section_index() != 1 or not bool(_controller.call("_has_active_play_choice")) or broadcast_choice_type != "use" or broadcast_actor_id != 0:
		return _fail("tiancai_play_choice=%d/%s/%s/%s/%d" % [owner.hp, tiancai.get_reincarnation_state(), _controller.call("_has_active_play_choice"), broadcast_choice_type, broadcast_actor_id])
	_controller.state_changed.disconnect(_on_state_changed)
	# 关闭本用例建立的出牌窗口，避免影响同文件后续用例的根事件栈。
	_controller.call("_cancel_active_play_choice", "omphalos_transform_test")
	return true


## 记录最近一次状态广播中的当前请求；界面只读取该字段决定是否开放出牌控件。
func _on_state_changed(snapshot: Dictionary) -> void:
	_last_broadcast_choice = (snapshot.get("current_choice_request", {}) as Dictionary).duplicate(true)


## 校验天裁②/③、弑魂①/②与永劫非伤害牌转化都进入完整虚拟用牌生命周期。
func _test_active_virtual_card_skills() -> bool:
	_reset_state(3)
	# 空对局ID令纯规则测试的展示、响应与可取消弃牌选择使用标准同步回退动作，不创建交互窗口。
	_controller.state.match_id = ""
	# 天裁持有者；保持卡厄斯兰那的5点体力数值供连续用牌结算。
	var tiancai_owner: PlayerState = _controller.state.get_player(0)
	tiancai_owner.character_id = "kaesilanna"
	tiancai_owner.max_hp = 5
	tiancai_owner.hp = 5
	# 天裁②的第一名火攻目标；手牌是【火攻】合法目标的必要条件。
	var first_fire_attack_target: PlayerState = _controller.state.get_player(1)
	# 天裁②的第二名火攻目标；两名目标用于验证队列会逐张结算。
	var second_fire_attack_target: PlayerState = _controller.state.get_player(2)
	# 第一名目标用于展示的手牌；红桃【闪】不会在取消同花色费用时移动。
	var first_shown_card: CardInstance = CardInstance.new("shan", "heart", 4)
	first_shown_card.zone = "hand"
	first_shown_card.owner_id = 1
	first_fire_attack_target.hand.append(first_shown_card)
	# 第二名目标用于展示的手牌；黑桃【闪】确保两个火攻选择上下文相互独立。
	var second_shown_card: CardInstance = CardInstance.new("shan", "spade", 5)
	second_shown_card.zone = "hand"
	second_shown_card.owner_id = 2
	second_fire_attack_target.hand.append(second_shown_card)
	# 天裁运行时实例；先外部推进到X=1的③，验证0张【火攻】仍会完成轮回。
	var tiancai: SkillDefinition = _install_skill(0, "tiancai")
	# X=1时③使用0张火攻；仍应完成当前节并进入X=2的下一轮①。
	if tiancai == null or not _controller.enter_next_reincarnation_section(0, "tiancai") or not _controller.enter_next_reincarnation_section(0, "tiancai") or tiancai.activate({}) != "" or _controller.has_pending_card_choice() or _count_card_uses(0, "huogong") != 0 or tiancai.get_reincarnation_round_count() != 2 or tiancai.get_reincarnation_section_index() != 0:
		return _fail("tiancai_zero_repeat=%s" % tiancai.get_reincarnation_state())
	# X=2的②最多选择2名目标；两张火攻必须逐张完成后才进入③。
	if not _controller.enter_next_reincarnation_section(0, "tiancai") or tiancai.activate({"target_ids":[1, 2]}) != "":
		return _fail("tiancai_multi_fire_attack_start")
	_controller._resume_deferred_skill_settlements()
	_controller._resume_deferred_skill_settlements()
	if tiancai.get_reincarnation_round_count() != 2 or tiancai.get_reincarnation_section_index() != 2 or _count_card_uses(0, "huogong") != 2:
		return _fail("tiancai_multi_fire_attack=%s/%d" % [tiancai.get_reincarnation_state(), _count_card_uses(0, "huogong")])
	# X=2的③对同一目标使用1张火攻；完成后进入X=3的①。
	if tiancai.activate({"target_ids":[1]}) != "":
		return _fail("tiancai_repeated_fire_attack_start")
	_controller._resume_deferred_skill_settlements()
	if tiancai.get_reincarnation_round_count() != 3 or tiancai.get_reincarnation_section_index() != 0 or _count_card_uses(0, "huogong") != 3:
		return _fail("tiancai_repeated_fire_attack=%s/%d" % [tiancai.get_reincarnation_state(), _count_card_uses(0, "huogong")])

	_reset_state(3)
	_controller.state.match_id = ""
	# 弑魂持有者；①承受一张火【杀】后，②应对原指定使用者反击。
	var shihun_owner: PlayerState = _controller.state.get_player(0)
	shihun_owner.character_id = "kaesilanna"
	shihun_owner.max_hp = 5
	shihun_owner.hp = 5
	# 弑魂①指定的1号其他角色；该角色将成为第一张火【杀】使用者与后续反击目标。
	var first_shihun_actor: PlayerState = _controller.state.get_player(1)
	# 弑魂①指定的2号其他角色；用于证明同次发动的第二张火【杀】会在统一管线内继续结算。
	var second_shihun_actor: PlayerState = _controller.state.get_player(2)
	# 弑魂运行时实例；两个轮回节连续调用用于验证原目标保持。
	var shihun: SkillDefinition = _install_skill(0, "shihun")
	if shihun == null or shihun.activate({"target_ids":[1, 2]}) != "":
		return _fail("shihun_incoming_start")
	# 一次统一结算管线调用必须排空两张依次使用的火【杀】，不能每张牌都依赖外部再次恢复。
	_controller.resume_settlement_pipeline()
	if shihun_owner.hp != 3 or shihun.get_reincarnation_section_index() != 1 or _count_card_uses(1, "sha_fire") != 1 or _count_card_uses(2, "sha_fire") != 1:
		return _fail("shihun_incoming=%d/%s/%d/%d" % [shihun_owner.hp, shihun.get_reincarnation_state(), _count_card_uses(1, "sha_fire"), _count_card_uses(2, "sha_fire")])
	# 反击前两名原使用者的体力；②是一张固定多目标火【杀】，两名目标都应各承受1点伤害。
	var first_shihun_actor_hp_before: int = first_shihun_actor.hp
	# 第二名原使用者的反击前体力；与第一名共同验证①保存的完整目标集合。
	var second_shihun_actor_hp_before: int = second_shihun_actor.hp
	if shihun.activate({}) != "":
		return _fail("shihun_retaliation_start")
	_controller.resume_settlement_pipeline()
	if first_shihun_actor.hp != first_shihun_actor_hp_before - 1 or second_shihun_actor.hp != second_shihun_actor_hp_before - 1 or shihun.get_reincarnation_round_count() != 2 or shihun.get_reincarnation_section_index() != 0 or _count_card_uses(0, "sha_fire") != 1:
		return _fail("shihun_retaliation=%d/%d/%s/%d" % [first_shihun_actor.hp, second_shihun_actor.hp, shihun.get_reincarnation_state(), _count_card_uses(0, "sha_fire")])

	_reset_state(4)
	_controller.state.match_id = ""
	# 永劫锁定视为持有者；当前出牌阶段尚未使用【杀】，可通过标准实体牌动作直接提交视为火【杀】。
	var yongjie_owner: PlayerState = _controller.state.get_player(0)
	yongjie_owner.character_id = "kaesilanna"
	yongjie_owner.max_hp = 5
	yongjie_owner.hp = 5
	# 与持有者座距为2的目标；用于确认锁定视为牌自带无距离限制，而非依赖技能按钮传入覆写。
	var yongjie_target: PlayerState = _controller.state.get_player(2)
	# 永劫锁定视为的红桃【闪】；【闪】的AI伤害标记为false，安装技能后应立即在手牌中显示为火【杀】。
	var non_damage_material: CardInstance = CardInstance.new("shan", "heart", 6)
	non_damage_material.zone = "hand"
	non_damage_material.owner_id = 0
	yongjie_owner.hand.append(non_damage_material)
	# 真实伤害牌样本；普通【杀】不属于永劫转换范围，应保持原定义且仍受攻击距离限制。
	var damage_card: CardInstance = CardInstance.new("sha", "spade", 8)
	damage_card.zone = "hand"
	damage_card.owner_id = 0
	yongjie_owner.hand.append(damage_card)
	# 永劫运行时实例；只安装锁定视为状态，不应公开任何主动或响应技能按钮。
	var yongjie: SkillDefinition = _install_skill(0, "yongjie")
	# 手牌公开牌面数据；原牌名与实际视为牌名同时存在，界面据此绘制“视为火【杀】”横条标记。
	var marked_card_snapshot: Dictionary = non_damage_material.to_dict()
	# 永劫安装后的标准合法动作；视为牌应作为use_card出现，且能直接选择座距2目标。
	var yongjie_legal_actions: Array[Dictionary] = _controller.get_legal_actions(0)
	# 是否找到视为牌直击远距离目标的标准动作；默认false，遍历后必须变为true。
	var has_marked_fire_slash_action: bool = false
	for legal_action: Dictionary in yongjie_legal_actions:
		if str(legal_action.get("action_type", "")) == "use_card" and int(legal_action.get("card_uid", -1)) == non_damage_material.uid and (legal_action.get("target_ids", []) as Array).has(2):
			has_marked_fire_slash_action = true
	# 永劫火【杀】结算前的敌方体力；用于校验实际伤害与用牌生命周期。
	var yongjie_target_hp_before: int = yongjie_target.hp
	if yongjie == null or non_damage_material.definition_id != "sha_fire" or non_damage_material.hand_view_as_original_definition_id != "shan" or non_damage_material.hand_view_as_source_skill_id != "yongjie" or not non_damage_material.has_hand_mark_rule("ignore_distance_limit") or str(marked_card_snapshot.get("view_as_definition_id", "")) != "sha_fire" or damage_card.definition_id != "sha" or _controller.card_rules.validate_use(0, damage_card, [2]).is_empty() or _controller.get_active_skill_ids(0, "phaseUse").has("yongjie") or not has_marked_fire_slash_action:
		return _fail("yongjie_locked_view_as=%s/%s/%s" % [marked_card_snapshot, damage_card.definition_id, yongjie_legal_actions])
	# 标准出牌动作；玩家点击的是已标记手牌而不是永劫技能按钮，最终仍进入完整火【杀】生命周期。
	if not _controller.submit_action(PlayerAction.new("use_card", 0, non_damage_material.uid, [2])):
		return _fail("yongjie_locked_use_rejected")
	if yongjie_target.hp != yongjie_target_hp_before - 1 or yongjie_owner.find_hand_card(non_damage_material.uid) != null or _count_card_uses(0, "sha_fire") != 1 or yongjie.get_reincarnation_section_index() != 1:
		return _fail("yongjie_conversion=%d/%s/%d" % [yongjie_target.hp, yongjie.get_reincarnation_state(), _count_card_uses(0, "sha_fire")])
	# 安装后新获得的非伤害牌；gainAfter应立即应用同一锁定视为与无距离规则。
	var gained_non_damage_card: CardInstance = CardInstance.new("tao", "diamond", 9)
	gained_non_damage_card.zone = "draw_pile"
	_controller.state.draw_pile.append(gained_non_damage_card)
	if _controller._move_card_with_timings(gained_non_damage_card, "hand", 0, "yongjie_gain_test") == null or gained_non_damage_card.definition_id != "sha_fire" or gained_non_damage_card.hand_view_as_original_definition_id != "tao" or not gained_non_damage_card.has_hand_mark_rule("ignore_distance_limit"):
		return _fail("yongjie_gain_view_as=%s" % gained_non_damage_card.to_dict())
	return true


## 统计指定角色的完整用牌历史中某一逻辑牌ID出现次数；虚拟牌与实体牌使用同一事实历史。
func _count_card_uses(player_id: int, definition_id: String) -> int:
	# 待统计角色；不存在时安全返回0，避免测试诊断自身触发空引用。
	var player: PlayerState = _controller.state.get_player(player_id)
	if player == null:
		return 0
	return int(player.card_use_history.get(definition_id, 0))


## 输出失败原因并以非零状态退出；返回false便于调用方立即终止后续断言。
func _fail(message: String) -> bool:
	printerr("OMPHALOS_TRANSFORM_FAIL %s" % message)
	get_tree().quit(1)
	return false
