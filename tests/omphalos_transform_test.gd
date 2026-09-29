extends Node

## 翁法罗斯新增武将专项回归。覆盖精确元数据、军功与奇袭、堪杀、负火、区域废除、特殊形态往返及永劫轮回状态。

## 本测试共用的权威对局控制器；每项用例通过正式规则服务和技能实例执行。
var _controller: MatchController

## 最近一次状态广播中的当前请求快照；界面只读取该字段决定是否开放手牌与出牌控件。
var _last_broadcast_choice: Dictionary = {}

## 最近一次技能按钮发出的悬停标题；供轮回技标题用例逐字校验片段内容与顺序。
var _captured_skill_title: String = ""

## 最近一次武将牌悬停资料中的技能分段；供已释放变淡用例读取 intrinsic_use_consumed 标记。
var _captured_skill_sections: Array[Dictionary] = []


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
	if not _test_reincarnation_title_round_count():
		return
	if not _test_released_skill_content_dimming():
		return
	if not _test_tiancai_play_choice_broadcast():
		return
	if not _test_active_virtual_card_skills():
		return
	if not _test_xinji_first_damage_advance():
		return
	if not _test_zhengfu_kill_rewards():
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


## 校验三名武将、十项技能精确原文与卡厄斯兰那的特殊抽取过滤。
func _test_metadata_and_special_pool() -> bool:
	# 刻律德菈定义；女性、3上限、翁法罗斯与三技能顺序必须稳定。
	var kelvdela: Dictionary = GameDatabase.get_character("kelvdela")
	# 白厄定义；男性、4上限与负火/轮回/薪继顺序必须稳定。
	var baie: Dictionary = GameDatabase.get_character("baie")
	# 卡厄斯兰那定义；男性、5上限、三技能与special=true必须稳定。
	var kaesilanna: Dictionary = GameDatabase.get_character("kaesilanna")
	if str(kelvdela.get("display_name", "")) != "刻律德菈" or str(kelvdela.get("gender", "")) != "female" or str(kelvdela.get("faction", "")) != "wengfaluosi" or int(kelvdela.get("max_hp", 0)) != 3 or kelvdela.get("skills", []) != ["shengbian", "kansha", "zhengfu"]:
		return _fail("kelvdela_metadata=%s" % kelvdela)
	if str(baie.get("display_name", "")) != "白厄" or str(baie.get("gender", "")) != "male" or int(baie.get("max_hp", 0)) != 4 or baie.get("skills", []) != ["fuhuo", "lunhui", "xinji"]:
		return _fail("baie_metadata=%s" % baie)
	if str(kaesilanna.get("display_name", "")) != "卡厄斯兰那" or int(kaesilanna.get("max_hp", 0)) != 5 or not bool(kaesilanna.get("special", false)) or kaesilanna.get("skills", []) != ["tiancai", "shihun", "yongjie"]:
		return _fail("kaesilanna_metadata=%s" % kaesilanna)
	# 需求指定十项技能原文；任何字符、标点、数字或X说明变化都应立即失败。
	var expected_descriptions: Dictionary = {
		"shengbian":"轮回技，回合开始时，你可选择一名角色，若其有“军功”标记，你令其获得X枚“军功”标记（至多获得至8枚）；若其没有“军功”标记，你移除场上所有的“军功”标记，并令其获得2枚“军功”标记。拥有“军功”标记的角色视为拥有技能“奇袭”。（X为此技能的轮回数且至多为5）",
		"kansha":"轮回技，出牌阶段每个轮回节限一次，你可①弃置一张红色牌；②弃置一张黑色牌；③对一名其他角色造成1点伤害。",
		"zhengfu":"领袖技，锁定技，当你击杀其他角色时，你回复1点体力，然后若其势力不为“翁法罗斯”，所有“翁法罗斯”势力的角色的轮回技进入下一个轮回节；否则，你的击杀奖惩改为摸四张牌。",
		"qixi":"锁定技，当你发动“出牌阶段限一次”或“轮回技”的技能后，若你的“军功”标记数少于6，你获得一枚“军功”标记；否则你移除5枚“军功”，然后若此技能为“出牌阶段限一次”，则视为本回合未发动过此技能；若此技能为“轮回技”，则进入下一个轮回节。",
		"fuhuo":"锁定技，每回合每项限一次，1.当你使用一张牌时，2.当你成为牌的目标时，3.当你受到伤害时，4.当你造成伤害时，若你的“火种”标记数小于12，你获得一枚“火种”标记，然后若你的手牌数小于5，你摸一张牌。",
		"lunhui":"觉醒技，一名角色回合结束时，若拥有的“火种”不少于12，你移除所有“火种”，废除装备区与判定区，令所有友方角色离场，将你的武将牌替换为“卡厄斯兰那”，将体力值回复至体力上限，然后进行一个额外回合。",
		"xinji":"领袖技，当一名“翁法罗斯”势力的其他角色首次受到伤害后，其可令你获得一枚“火种”标记，然后你令其所有轮回技进入下一个轮回。",
		"tiancai":"轮回技，出牌阶段，你可①受到无伤害来源的X点火焰伤害；②视为对至多X名角色各使用一张【火攻】。③视为对一名角色依次使用X-1张【火攻】。（X为此技能的轮回数）",
		"shihun":"轮回技，出牌阶段，你可①令任意名其他角色依次视为对你使用一张火【杀】；②视为使用一张目标为上次发动此技能所指定目标的火【杀】。",
		"yongjie":"锁定技，轮回技，你手牌中的非伤害牌均视为无距离限制的火【杀】。当你造成火焰伤害后，①你令你的所有其他轮回技进入每回合限一次的永劫状态；②摸一张牌；③退出所有其他轮回技的永劫状态。当你体力值不大于0时，你将体力值回复至2点，恢复装备区与判定区，将武将牌替换为“白厄”，并复原武将牌上的技能，然后所有友方角色返场。",
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


## 校验升变的回合开始分配与军功累积、军功动态奇袭、奇袭的正文标签识别与移除5枚分支，并验证堪杀三节与阶段额度。
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
	# 改为回合开始触发后升变不再是出牌阶段主动技能；技能按钮列表必须不再包含它。
	if _controller.get_active_skill_ids(0, "phaseUse").has("shengbian"):
		return _fail("shengbian_active_entry=%s" % [_controller.get_active_skill_ids(0, "phaseUse")])
	# AI目标选择评分器；身份已明置，0号领袖对2号忠臣为正态度、对1号反贼为负态度。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 无宿主评分技能；与基础策略加载的临时评分实例构造方式一致。
	var scoring_shengbian: SkillDefinition = GameDatabase.create_skill("shengbian")
	scoring_shengbian.bind(null, 0)
	# 评分快照；目标选择评分必须只读权威快照，不能依赖运行时技能宿主。
	var shengbian_snapshot: Dictionary = _controller.state.to_dict(0, true)
	# 回合开始目标询问的稳定评分上下文；与技能实际创建的请求字段保持一致。
	var shengbian_ai_request: Dictionary = {"context":{"kind":"shengbian_target", "skill_id":"shengbian", "skill_owner_id":0}}
	if scoring_shengbian.score_ai_choice(shengbian_snapshot, shengbian_ai_request, {"payload":{"confirmed":true, "selected_target_ids":[2]}}, evaluator) <= scoring_shengbian.score_ai_choice(shengbian_snapshot, shengbian_ai_request, {"payload":{"confirmed":true, "selected_target_ids":[1]}}, evaluator):
		return _fail("shengbian_ai_target")
	# 回合开始时时机；升变必须创建可选择任意在场角色的目标询问。
	_controller._emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":1})
	if str(_controller._pending_card_choice.get("choice_type", "")) != "target" or int(_controller._pending_card_choice.get("chooser_id", -1)) != 0:
		return _fail("shengbian_turn_prompt=%s" % [_controller._pending_card_choice])
	# 取消询问不消耗轮回进度也不授予军功；下一次回合开始会重新询问。
	if not _submit_pending_choice(0, [], [], "", false) or shengbian.get_reincarnation_round_count() != 1 or not _controller.get_player_mark(2, "jungong").is_empty():
		return _fail("shengbian_cancel=%s/%s" % [shengbian.get_reincarnation_state(), _controller.get_player_mark(2, "jungong")])
	# 无军功友方进入重置分支，获得2枚军功并立即动态拥有奇袭；单节轮回推进至X=2。
	_controller.emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":2})
	if not _submit_pending_choice(0, [], [2], "", true):
		return _fail("shengbian_target=%s" % [_controller._pending_card_choice])
	# 获得军功的2号友方；用于检查动态奇袭来源与标记数量。
	var ally: PlayerState = _controller.state.get_player(2)
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 2 or _controller.get_skill_instance(2, "qixi") == null or str((ally.acquired_skills.get("qixi", {}) as Dictionary).get("source", "")) != "shengbian_jungong" or shengbian.get_reincarnation_round_count() != 2:
		return _fail("shengbian_initial=%s/%s" % [_controller.get_player_mark(2, "jungong"), ally.acquired_skills])
	# 已有军功友方按X=2增加至4，且不清除其他角色标记。
	_controller.emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":3})
	if not _submit_pending_choice(0, [], [2], "", true) or int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 4:
		return _fail("shengbian_growth=%s" % _controller.get_player_mark(2, "jungong"))
	# 军功持有总数不设上限：目标已有7枚时按X=3增长为10枚，证明“至多获得至8枚”截断的是本次获得的X而不是持有总数。
	_controller.change_player_mark_count(2, "jungong", 3, {"icon":"军", "name":"军功", "description":"测试军功"})
	_controller.emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":4})
	if not _submit_pending_choice(0, [], [2], "", true) or int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 10:
		return _fail("shengbian_accumulate=%s" % _controller.get_player_mark(2, "jungong"))
	# 继续累积：X=4时增长为14枚，已有军功既不被上限截断也不被清空，动态奇袭保持存在。
	_controller.emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":5})
	if not _submit_pending_choice(0, [], [2], "", true) or int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 14 or _controller.get_skill_instance(2, "qixi") == null:
		return _fail("shengbian_full=%s" % _controller.get_player_mark(2, "jungong"))
	# 正文识别必须屏蔽引号：奇袭自身正文里的两个标签都是引用，不会被当成它自己的技能类型。
	var qixi_description: String = str(GameDatabase.get_skill("qixi").get("description", ""))
	var shengbian_description: String = str(GameDatabase.get_skill("shengbian").get("description", ""))
	if SkillDefinition.description_declares_tag(qixi_description, "出牌阶段限一次") or SkillDefinition.description_declares_tag(qixi_description, "轮回技"):
		return _fail("qixi_quote_filter")
	# 升变改为回合开始时触发后不再声明“出牌阶段限一次”；奇袭对它只保留“进入下一个轮回节”分支。
	if SkillDefinition.description_declares_tag(shengbian_description, "出牌阶段限一次"):
		return _fail("play_phase_once_detection")
	# 轮回技改为读标签：升变带标签，奇袭（引号只是提及）与只引用他人轮回技的回涛都不带标签。
	for labeled_skill_id: String in ["fanyin", "jvkou", "kansha", "shengbian", "shihun", "tiancai", "xvechou", "yongjie", "zhuxv"]:
		if not bool(GameDatabase.get_skill(labeled_skill_id).get("reincarnation", false)):
			return _fail("reincarnation_tag_missing=%s" % labeled_skill_id)
	for unlabeled_skill_id: String in ["qixi", "huitao"]:
		if bool(GameDatabase.get_skill(unlabeled_skill_id).get("reincarnation", false)):
			return _fail("reincarnation_tag_unexpected=%s" % unlabeled_skill_id)
	# 正文类型声明与标签必须一致；回涛的正文只是提及他人轮回技，按紧跟标点的规则不计为类型声明。
	if not SkillDefinition.description_declares_reincarnation_type(shengbian_description) or SkillDefinition.description_declares_reincarnation_type(str(GameDatabase.get_skill("huitao").get("description", ""))) or SkillDefinition.description_declares_reincarnation_type(qixi_description):
		return _fail("reincarnation_type_detection")
	# 不属于两类技能的实际发动不推进军功；行军正文只声明“出牌阶段开始时”。
	_controller.emit_rule_timing("skillAfter", 2, 2, -1, {"skill_id":"xingjun", "actual_activation":true, "context":{}})
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 14:
		return _fail("qixi_unrelated_skill=%s" % _controller.get_player_mark(2, "jungong"))
	# 只引用他人轮回技的技能同样不推进军功：回涛既没有“出牌阶段限一次”正文声明，也没有轮回技标签。
	_controller.emit_rule_timing("skillAfter", 2, 2, -1, {"skill_id":"huitao", "actual_activation":true, "context":{}})
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 14:
		return _fail("qixi_reincarnation_reference=%s" % _controller.get_player_mark(2, "jungong"))
	# 移除5枚后仍有剩余时奇袭保留：14枚军功发动一次轮回技后剩9枚。
	_controller.emit_rule_timing("skillAfter", 2, 2, -1, {"skill_id":"kansha", "actual_activation":true, "context":{}})
	_controller._resume_deferred_skill_settlements()
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 9 or _controller.get_skill_instance(2, "qixi") == null:
		return _fail("qixi_reset_remaining=%s" % _controller.get_player_mark(2, "jungong"))
	# 再次发动仍按固定5枚移除：9枚剩4枚，证明阈值分支是“移除5枚”而不是把标记调整到某个固定值。
	_controller.emit_rule_timing("skillAfter", 2, 2, -1, {"skill_id":"kansha", "actual_activation":true, "context":{}})
	_controller._resume_deferred_skill_settlements()
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 4 or _controller.get_skill_instance(2, "qixi") == null:
		return _fail("qixi_reset_repeat=%s" % _controller.get_player_mark(2, "jungong"))
	# 阈值6大于移除量5，因此该分支自身恒留下至少1枚：恰好6枚时移除5枚后剩1枚并继续保留奇袭。
	_controller.change_player_mark_count(2, "jungong", 2, {"icon":"军", "name":"军功", "description":"测试军功"})
	_controller.emit_rule_timing("skillAfter", 2, 2, -1, {"skill_id":"kansha", "actual_activation":true, "context":{}})
	_controller._resume_deferred_skill_settlements()
	if int(_controller.get_player_mark(2, "jungong").get("count", 0)) != 1 or _controller.get_skill_instance(2, "qixi") == null:
		return _fail("qixi_reset_threshold=%s" % _controller.get_player_mark(2, "jungong"))
	# 军功被“移除场上所有的军功”整体清空时，持有者不再视为拥有奇袭，动态授予记录必须同步撤销。
	_controller.change_player_mark_count(2, "jungong", 3, {"icon":"军", "name":"军功", "description":"测试军功"})
	_controller.emit_rule_timing("phaseBefore", 0, 0, 0, {"turn_number":6})
	if not _submit_pending_choice(0, [], [1], "", true) or not _controller.get_player_mark(2, "jungong").is_empty() or _controller.get_skill_instance(2, "qixi") != null:
		return _fail("qixi_revoke=%s/%s" % [_controller.get_player_mark(2, "jungong"), ally.acquired_skills])
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


## 校验【薪继】仅在翁法罗斯其他角色本局首次受伤时询问，并把该角色的全部轮回技推进一个完整轮回。
func _test_xinji_first_damage_advance() -> bool:
	_reset_state(4)
	# 白厄（0号领袖）持有薪继；2号与3号都是可推进的翁法罗斯轮回技角色。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "baie"
	owner.max_hp = 4
	owner.hp = 4
	for ally_id: int in [2, 3]:
		# 当前盟方角色；换成刻律德菈以获得三节轮回技。
		var ally: PlayerState = _controller.state.get_player(ally_id)
		ally.character_id = "kelvdela"
		ally.max_hp = 3
		ally.hp = 3
	# 2号用于取消分支、3号用于确认分支的堪杀实例；轮回节索引可以区分两者是否被推进。
	var cancelled_skill: SkillDefinition = _install_skill(2, "kansha")
	var advanced_skill: SkillDefinition = _install_skill(3, "kansha")
	# 白厄的薪继实例；领袖身份由测试直接提供，正式对局中由核心按identity安装。
	var xinji: SkillDefinition = _install_skill(0, "xinji")
	if xinji == null or cancelled_skill == null or advanced_skill == null:
		return _fail("xinji_install")
	# 2号先推进一个轮回节；让“取消发动不推进”的断言拥有与初始状态不同的可区分基准。
	if not _controller.enter_next_reincarnation_section(2, "kansha") or cancelled_skill.get_reincarnation_section_index() != 1:
		return _fail("xinji_setup_section=%d" % cancelled_skill.get_reincarnation_section_index())
	# 2号本局首次受伤：选择权在受伤角色手上，请求的chooser必须是2号本人。
	_controller.emit_rule_timing("damageAfter", 2, 1, 2, {"amount":1, "nature":"normal", "damage_event_id":201})
	if int(_controller._pending_card_choice.get("chooser_id", -1)) != 2:
		return _fail("xinji_chooser=%s" % _controller._pending_card_choice)
	# 取消发动：不给予火种，也不推进任何轮回技，2号必须仍停在②。
	if not _submit_pending_choice(2, [], [], "", false):
		return false
	if not _controller.get_player_mark(0, "huozhong").is_empty() or cancelled_skill.get_reincarnation_section_index() != 1 or cancelled_skill.get_reincarnation_round_count() != 1:
		return _fail("xinji_cancel=%s/%d/%d" % [_controller.get_player_mark(0, "huozhong"), cancelled_skill.get_reincarnation_round_count(), cancelled_skill.get_reincarnation_section_index()])
	# 同一角色再次受伤不再询问：本局首次机会已经消耗，无论上次是否实际发动。
	_controller.emit_rule_timing("damageAfter", 2, 1, 2, {"amount":1, "nature":"normal", "damage_event_id":202})
	if not _controller._pending_card_choice.is_empty():
		return _fail("xinji_second_damage=%s" % _controller._pending_card_choice)
	# 3号本局首次受伤并确认发动：白厄获得1枚火种，3号全部轮回技进入下一个轮回（轮回数+1并回到①）。
	_controller.emit_rule_timing("damageAfter", 3, 1, 3, {"amount":1, "nature":"normal", "damage_event_id":203})
	if not _submit_pending_choice(3, [], [], "", true):
		return false
	if int(_controller.get_player_mark(0, "huozhong").get("count", 0)) != 1 or advanced_skill.get_reincarnation_round_count() != 2 or advanced_skill.get_reincarnation_section_index() != 0:
		return _fail("xinji_confirm=%s/%d/%d" % [_controller.get_player_mark(0, "huozhong"), advanced_skill.get_reincarnation_round_count(), advanced_skill.get_reincarnation_section_index()])
	# 非翁法罗斯势力角色首次受伤不满足原文条件，也不产生任何询问。
	_controller.state.get_player(1).character_id = "bronya"
	_controller.emit_rule_timing("damageAfter", 1, 2, 1, {"amount":1, "nature":"normal", "damage_event_id":204})
	if not _controller._pending_card_choice.is_empty():
		return _fail("xinji_foreign_faction=%s" % _controller._pending_card_choice)
	# “本局首次”记录保存在持有者私有形态状态中：随权威存档往返，且非本势力角色不会被误记。
	var triggered_ids: Array = owner.character_form_state.get("xinji_triggered_player_ids", []) as Array
	if not triggered_ids.has(2) or not triggered_ids.has(3) or triggered_ids.has(1):
		return _fail("xinji_record=%s" % [triggered_ids])
	return true


## 校验【征服】的击杀回复体力、全场轮回节推进与“击杀奖惩改为摸四张牌”两项势力分支。
func _test_zhengfu_kill_rewards() -> bool:
	_reset_state(4)
	_add_draw_cards(16)
	# 刻律德菈（0号领袖）持有征服；1号反贼为贝洛伯格角色，2号忠臣为翁法罗斯轮回技角色。
	var owner: PlayerState = _controller.state.get_player(0)
	owner.character_id = "kelvdela"
	owner.max_hp = 3
	owner.hp = 2
	# 非翁法罗斯被击杀者；用于验证“推进轮回节”分支与未被改写的击杀反贼摸三张。
	var foreign_victim: PlayerState = _controller.state.get_player(1)
	foreign_victim.character_id = "bronya"
	# 翁法罗斯被击杀者；用于验证“击杀奖惩改为摸四张牌”分支。
	var faction_victim: PlayerState = _controller.state.get_player(2)
	faction_victim.character_id = "kelvdela"
	# 3号内奸保持翁法罗斯势力且不持有轮回技；击杀反贼后对局不会因为反贼全灭而立即结束。
	_controller.state.get_player(3).identity = "renegade"
	# 2号的三节轮回技；只用于验证“进入下一个轮回节”而不是进入下一轮回。
	var kansha: SkillDefinition = _install_skill(2, "kansha")
	# 刻律德菈的征服实例；锁定技不创建任何确认请求，满足条件即自动结算。
	var zhengfu: SkillDefinition = _install_skill(0, "zhengfu")
	if zhengfu == null or kansha == null:
		return _fail("zhengfu_install")
	# 击杀非翁法罗斯反贼：回复1点体力、推进全场翁法罗斯轮回节，并保留身份规则原有的摸三张奖惩。
	foreign_victim.hp = 0
	_controller._resolve_death(1, 0)
	if owner.hp != 3 or owner.hand.size() != 3 or kansha.get_reincarnation_section_index() != 1 or kansha.get_reincarnation_round_count() != 1:
		return _fail("zhengfu_foreign=%d/%d/%d" % [owner.hp, owner.hand.size(), kansha.get_reincarnation_section_index()])
	# 击杀翁法罗斯忠臣：基础奖惩原本是领袖误杀忠臣的弃置全部牌，本技能把它整体替换为摸四张牌。
	if _controller.resolve_death_reward(0, 2) != "draw_four":
		return _fail("zhengfu_reward=%s" % _controller.resolve_death_reward(0, 2))
	faction_victim.hp = 0
	_controller._resolve_death(2, 0)
	if owner.hand.size() != 7:
		return _fail("zhengfu_own_faction_reward=%d" % owner.hand.size())
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
	# 白厄的轮回觉醒实例；负责触发区域废除、友方离场、换形和额外回合。
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
	# 忠臣2因轮回离场且忠臣3保持既有离场；原文已移除翻面效果，反贼1必须保持正面。
	if owner.character_id != "kaesilanna" or owner.max_hp != 5 or owner.hp != 5 or not owner.equipment_area_abolished or not owner.judgment_area_abolished or not _controller.get_player_mark(0, "huozhong").is_empty():
		return _fail("lunhui_owner=%s/%d/%d" % [owner.character_id, owner.max_hp, owner.hp])
	if not _controller.state.get_player(2).out_of_game or not _controller.state.get_player(3).out_of_game or _controller.state.get_player(1).out_of_game or _controller.state.get_player(1).face_down or not _controller._extra_turn_queue.has(0):
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
	# 进入永劫后的武将牌左上角提示；天裁与弑魂同时处于永劫仍只显示一条角色级提示。
	if owner.character_corner_text != "永劫" or owner.character_corner_text_entries.size() != 1:
		return _fail("yongjie_corner_text=%s/%s" % [owner.character_corner_text, owner.character_corner_text_entries])
	# 第二次火焰伤害摸1张；③不再摸牌，只退出所有其他轮回技永劫并进入下一轮回①。
	_controller.emit_rule_timing("damageAfter", 1, 0, 1, {"amount":1, "nature":"fire", "damage_event_id":202})
	_controller.emit_rule_timing("damageAfter", 1, 0, 1, {"amount":1, "nature":"fire", "damage_event_id":203})
	if owner.hand.size() != 1 or bool(tiancai.get_reincarnation_state().get("eternal", true)) or bool(shihun.get_reincarnation_state().get("eternal", true)) or yongjie.get_reincarnation_round_count() != 2 or yongjie.get_reincarnation_section_index() != 0:
		return _fail("yongjie_exit_eternal=%d/%s/%s/%s" % [owner.hand.size(), tiancai.get_reincarnation_state(), shihun.get_reincarnation_state(), yongjie.get_reincarnation_state()])
	# 退出永劫后提示必须移除；角色不再处于永劫状态，武将牌左上角不残留“永劫”文本。
	if not owner.character_corner_text.is_empty() or not owner.character_corner_text_entries.is_empty():
		return _fail("yongjie_corner_text_exit=%s/%s" % [owner.character_corner_text, owner.character_corner_text_entries])
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


## 校验轮回技悬停标题与右键详情在次数说明之前标注轮回数，普通技能标题保持原有格式。
func _test_reincarnation_title_round_count() -> bool:
	# 正式技能按钮组件；标题组装完全由该组件负责，无需创建完整牌桌。
	var skill_button: SkillButtonView = SkillButtonView.new()
	add_child(skill_button)
	skill_button.information_requested.connect(_on_skill_information_requested)
	# 轮回技定义；直接使用正式数据库元数据，避免在测试里复制技能名与文案。
	var reincarnation_definition: Dictionary = GameDatabase.get_skill("tiancai")
	# 轮回技显示名；标题断言按真实配置拼接，技能改名后测试自动跟随。
	var reincarnation_name: String = str(reincarnation_definition.get("name", ""))
	# 无局内次数限制的轮回技；标题只包含轮回数片段。
	skill_button.configure(reincarnation_definition, false, "", {"round_count":3, "section_index":1})
	skill_button._on_information_mouse_entered()
	if _captured_skill_title != "【%s】（轮回3）" % reincarnation_name:
		skill_button.queue_free()
		return _fail("reincarnation_title=%s" % _captured_skill_title)
	# 同时带次数限制的轮回技；已轮回次数必须排在“每回合可发动”之前。
	skill_button.configure(reincarnation_definition, false, "每回合可发动2次", {"round_count":3, "section_index":1})
	skill_button._on_information_mouse_entered()
	if _captured_skill_title != "【%s】（轮回3；每回合可发动2次）" % reincarnation_name:
		skill_button.queue_free()
		return _fail("reincarnation_title_order=%s" % _captured_skill_title)
	# 普通技能定义；标题必须保持原有格式，不得凭空出现轮回次数片段。
	var normal_definition: Dictionary = GameDatabase.get_skill("yongyi")
	# 普通技能显示名；用于拼接期望标题。
	var normal_name: String = str(normal_definition.get("name", ""))
	skill_button.configure(normal_definition, false, "每回合可发动2次", {})
	skill_button._on_information_mouse_entered()
	if _captured_skill_title != "【%s】（每回合可发动2次）" % normal_name:
		skill_button.queue_free()
		return _fail("normal_title=%s" % _captured_skill_title)
	# 右键武将详情的技能标题；与悬停标题同构，必须使用相同的片段顺序。
	var information_box: InformationBoxLayer = InformationBoxLayer.new()
	add_child(information_box)
	information_box._character_snapshot = {"reincarnation_skills":{"tiancai":{"round_count":3, "section_index":1}}, "acquired_skill_remaining_uses":{"tiancai":"每回合可发动2次"}}
	# 轮回技详情标题；次数文案之前必须出现已轮回次数。
	var detail_title: String = information_box._get_character_skill_information_title("tiancai", reincarnation_name)
	if detail_title != "【%s】（轮回3；每回合可发动2次）" % reincarnation_name:
		information_box.queue_free()
		skill_button.queue_free()
		return _fail("reincarnation_detail_title=%s" % detail_title)
	# 普通技能详情标题；不得凭空出现轮回次数片段。
	information_box._character_snapshot = {"acquired_skill_remaining_uses":{"yongyi":"每回合可发动2次"}}
	# 普通技能详情标题实际文本；用于失败时输出完整偏差。
	var normal_detail_title: String = information_box._get_character_skill_information_title("yongyi", normal_name)
	if normal_detail_title != "【%s】（每回合可发动2次）" % normal_name:
		information_box.queue_free()
		skill_button.queue_free()
		return _fail("normal_detail_title=%s" % normal_detail_title)
	information_box.queue_free()
	skill_button.queue_free()
	# 已消耗固有额度的技能集合；觉醒技必须只进入包含觉醒技的查询，普通查询保持排除。
	# 该差异是界面与【光覆】等复原入口共用同一数据源时的核心契约，不能为了按钮视觉而改变复原候选。
	_reset_state(2)
	var awakening_skill: SkillDefinition = _install_skill(0, "lunhui")
	if awakening_skill == null or not awakening_skill.awakening:
		return _fail("awakening_skill_install")
	awakening_skill.consume_intrinsic_use()
	# 普通限定技集合；觉醒技不属于【光覆】等复原入口的候选，该语义必须保持不变。
	var limited_only_ids: Array[String] = _controller.get_used_limited_skill_ids(0)
	# 含觉醒技的完整集合；悬停资料与右键详情的已释放变淡读取该集合。
	var intrinsic_use_ids: Array[String] = _controller.get_used_limited_skill_ids(0, true)
	if limited_only_ids.has("lunhui") or not intrinsic_use_ids.has("lunhui"):
		return _fail("used_intrinsic_use_ids=%s/%s" % [limited_only_ids, intrinsic_use_ids])
	# 公开快照字段；必须存在并包含觉醒技，界面只从快照读取该集合。
	# 探测快照只放一个玩家条目，等价于正式广播时逐玩家写入的最小形状。
	var snapshot_probe: Dictionary = {"players":[{"player_id":0}]}
	_controller._append_limited_skill_usage_to_snapshot(snapshot_probe)
	# 探测快照内的玩家条目；字段写入后必须可被界面按同一键名读取。
	var probe_player: Dictionary = (snapshot_probe.get("players", []) as Array)[0] as Dictionary
	# 快照中的普通限定技集合；继续排除觉醒技，保证复原入口候选不变。
	var snapshot_limited_ids: Array = probe_player.get("used_limited_skill_ids", []) as Array
	# 快照中的含觉醒技集合；界面据此显示已释放状态。
	var snapshot_intrinsic_ids: Array = probe_player.get("used_intrinsic_use_skill_ids", []) as Array
	if snapshot_limited_ids.has("lunhui") or not snapshot_intrinsic_ids.has("lunhui"):
		return _fail("used_intrinsic_use_snapshot=%s/%s" % [snapshot_limited_ids, snapshot_intrinsic_ids])
	return true


## 校验武将悬停资料与右键武将详情把已释放的限定技与觉醒技整块显示为变淡，被复原时保持原亮度。
func _test_released_skill_content_dimming() -> bool:
	# 统一信息框实例；两处技能列表都由该组件渲染，测试直接驱动其渲染入口而不重建整个牌桌。
	var information_box: InformationBoxLayer = InformationBoxLayer.new()
	add_child(information_box)
	# 悬停资料分段；intrinsic_use_consumed 由 PlayerTargetView 依据权威快照写入，这里直接构造两种状态。
	information_box._hover_information = {"description_sections":[
		{"title":"【轮回】", "description":"觉醒技，达到条件后发动。", "reincarnation":false, "reincarnation_section_index":0, "intrinsic_use_consumed":true},
		{"title":"【祥音】", "description":"限定技，出牌阶段发动。", "reincarnation":false, "reincarnation_section_index":0, "intrinsic_use_consumed":false},
	]}
	information_box._render_hover_description()
	if information_box._hover_skill_description_labels.size() != 2:
		information_box.queue_free()
		return _fail("hover_section_count=%d" % information_box._hover_skill_description_labels.size())
	# 已释放技能与未释放技能的整块容器；技能名与技能描述共用同一个容器，因此一次断言覆盖两者。
	var released_hover_container: Control = information_box._hover_skill_description_labels[0].get_parent() as Control
	var normal_hover_container: Control = information_box._hover_skill_description_labels[1].get_parent() as Control
	if not is_equal_approx(released_hover_container.modulate.a, 0.8) or not is_equal_approx(normal_hover_container.modulate.a, 1.0):
		information_box.queue_free()
		return _fail("hover_released_alpha=%.3f/%.3f" % [released_hover_container.modulate.a, normal_hover_container.modulate.a])
	# 右键武将详情技能列表；觉醒技与限定技都通过同一快照字段判定已释放。
	information_box._character_definition = {"skills":["lunhui", "yongyi"]}
	information_box._character_snapshot = {"used_intrinsic_use_skill_ids":["lunhui"]}
	information_box._render_character_skills()
	# 右键详情技能条目；列表内只有技能条目带该元数据，分隔线与占位标签会被跳过。
	var skill_entries: Array[Node] = []
	for child: Node in information_box._character_skill_list.get_children():
		if child.has_meta("information_box_skill_entry"):
			skill_entries.append(child)
	if skill_entries.size() != 2:
		information_box.queue_free()
		return _fail("character_skill_entry_count=%d" % skill_entries.size())
	if not is_equal_approx((skill_entries[0] as Control).modulate.a, 0.8) or not is_equal_approx((skill_entries[1] as Control).modulate.a, 1.0):
		information_box.queue_free()
		return _fail("detail_released_alpha=%.3f/%.3f" % [(skill_entries[0] as Control).modulate.a, (skill_entries[1] as Control).modulate.a])
	# 复原后的快照；已释放集合不再包含该觉醒技，条目必须恢复完全不透明。
	information_box._character_snapshot = {"used_intrinsic_use_skill_ids":[]}
	information_box._render_character_skills()
	# 复原后的首个技能条目；亮度必须回到1.0。
	var restored_entry: Control = null
	for child: Node in information_box._character_skill_list.get_children():
		if child.has_meta("information_box_skill_entry"):
			restored_entry = child as Control
			break
	if restored_entry == null or not is_equal_approx(restored_entry.modulate.a, 1.0):
		information_box.queue_free()
		return _fail("detail_restored_alpha=%s" % (restored_entry.modulate.a if restored_entry != null else "missing"))
	information_box.queue_free()
	# 武将牌悬停资料的标记来源；PlayerTargetView 必须依据权威快照为每个技能写入 intrinsic_use_consumed。
	# 信息框只消费该标记，因此这一层若漏传，悬停资料不会变淡但右键详情仍然正常。
	# 必须实例化正式场景：该组件的插画、体力等子节点由 .tscn 提供，直接 new() 会缺少节点。
	var target_view_scene: PackedScene = load("res://scenes/components/player_target_view.tscn") as PackedScene
	var target_view: PlayerTargetView = target_view_scene.instantiate() as PlayerTargetView
	add_child(target_view)
	target_view.configure_snapshot({"character_id":"kaesilanna", "used_intrinsic_use_skill_ids":["lunhui"]}, {"skills":["lunhui", "yongyi"], "display_name":"测试武将"})
	target_view.information_requested.connect(_on_character_information_requested)
	target_view._request_character_information()
	if _captured_skill_sections.size() != 2 or not bool(_captured_skill_sections[0].get("intrinsic_use_consumed", false)) or bool(_captured_skill_sections[1].get("intrinsic_use_consumed", true)):
		target_view.queue_free()
		return _fail("target_view_released_sections=%s" % str(_captured_skill_sections))
	target_view.queue_free()
	return true


## 记录武将牌悬停资料中的技能分段；测试只读取 intrinsic_use_consumed 标记，锚点矩形被忽略。
func _on_character_information_requested(information: Dictionary, _anchor_rect: Rect2) -> void:
	_captured_skill_sections.clear()
	for section_variant: Variant in information.get("description_sections", []) as Array:
		_captured_skill_sections.append((section_variant as Dictionary).duplicate())


## 记录技能按钮发出的悬停标题；测试只读取标题文本，锚点矩形由牌桌信息框消费。
func _on_skill_information_requested(information: Dictionary, _anchor_rect: Rect2) -> void:
	_captured_skill_title = str(information.get("title", ""))


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


## 提交当前统一选择请求；牌、目标、文字选项与取消状态完整走权威动作入口，用于驱动回合开始类技能的目标询问。
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


## 输出失败原因并以非零状态退出；返回false便于调用方立即终止后续断言。
func _fail(message: String) -> bool:
	printerr("OMPHALOS_TRANSFORM_FAIL %s" % message)
	get_tree().quit(1)
	return false
