extends Node

## 银狼机制专项回归：锁定【注入】的运行时组合链路、【以太】的造牌与回流链路，以及两者的选择协议。
##
## 【为什么需要本用例】银狼是首个「技能内容在运行时才确定」的武将，它的正确性依赖四条彼此独立的约定：
## ① 组合技能骨架（进程/缺陷）必须能按实例读取运行时配置并订阅对应时机；
## ② 注入必须在开局与每轮准备阶段各开一次组合窗口，并按目标是否为主演选择类别池；
## ③ 以太造出的牌必须带铸造来源标记，才能在任意角色回合结束时被认出来并洗回牌堆；
## ④ 两种窗口的合法答案无法预先枚举，必须走「自由控制项」协议且由权威侧做结构校验。
## 任何一条漂移都会表现为「技能获得了却不触发 / 牌造出来了却永远留在弃牌堆 / 客户端能伪造效果键」，
## 因此在这里逐环固定下来。

## 本次测试权威控制器；使用与正式场景同类型的实例并手动装配必需子节点。
var _controller: MatchController

## 测试是否已失败；true时停止后续断言并以1结束进程。
var _failed: bool = false

## 样例武将稳定ID；使用只有两个固有技能的武将，使固有技能集合可预测。
const SAMPLE_CHARACTER_ID: String = "luka"

## 被测武将稳定ID；银狼的固有技能集合固定为【注入】【以太】。
const YINLANG_CHARACTER_ID: String = "yinlang"

## 【注入】与【以太】的技能稳定ID。
const ZHURU_SKILL_ID: String = "zhuru"
const YITAI_SKILL_ID: String = "yitai"

## 组合技能骨架的技能稳定ID。
const JINCHENG_SKILL_ID: String = "jincheng"
const QUEXIAN_SKILL_ID: String = "quexian"

## 第二份组合技能实例的期望实例键；键格式为「技能ID#2」，序号从2起。
const SECOND_COMPOSED_INSTANCE_KEY: String = "jincheng#2"

## 测试使用的组合结果；时机取受击后，效果取摸牌，都是无需额外选择即可结算的组合。
const SAMPLE_TIMING_KEY: String = "damage_after"
const SAMPLE_EFFECT_KEY: String = "draw_one"

## 不存在的时机键；用于验证权威侧会拒绝伪造的时机。
const ABSENT_TIMING_KEY: String = "not_a_timing"

## 造牌使用的被复制牌定义ID与牌名；【杀】是最稳定的基本牌定义。
const MINT_SOURCE_DEFINITION_ID: String = "sha"
const MINT_CUSTOM_NAME: String = "以太造物"

## 造牌窗口选择请求的上下文类型；与以太技能写入的 kind 字段一致，重放断言据此构造请求。
const MINT_CHOICE_KIND: String = "yitai_mint"

## 重复落地断言使用的牌名；必须与 MINT_CUSTOM_NAME 不同，才能证明第二张牌没有被造出来。
const REPLAY_MINT_NAME: String = "重放牌"

## 造牌使用的花色与点数；与界面默认值无关，只用于验证数值原样落地。
const MINT_SUIT: String = "heart"
const MINT_RANK: int = 7

## 银狼窗口层的期望绘制层级；数值来自《界面与交互》文档的层级表。
const EXPECTED_WINDOW_Z_INDEX: int = 185

## 每次重建状态时放入公共摸牌堆的牌数；数量只需足够覆盖「摸一张牌」与洗牌断言，不影响任何规则分支。
const DRAW_PILE_SIZE: int = 20


## 延迟一帧执行全部断言，确保 GameDatabase 已完成武将、技能与卡牌目录扫描。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 按独立状态顺序执行全部断言；任一环节失败都立即停止并报告具体原因。
func _run() -> void:
	_create_controller()
	if not _test_character_definition():
		return
	if not _test_pool_integrity():
		return
	if not _test_free_control_protocol():
		return
	if not _test_inject_game_start():
		return
	if not _test_inject_prepare_phase_pools():
		return
	if not _test_composed_instances_accumulate():
		return
	if not _test_composed_skill_subscribes_runtime_timing():
		return
	if not _test_aether_mint_window():
		return
	if not _test_aether_returns_card_to_draw_pile():
		return
	if not _test_card_name_helpers():
		return
	if not _test_window_layer():
		return
	print("YINLANG_MECHANICS_PASS character=1 pool=1 protocol=1 gamestart=1 prepare=1 instances=1 subscribe=1 mint=1 washback=1 names=1 window=1")
	get_tree().quit(0)


## 创建与正式场景同类型的控制器、事件总线、AI协调器与离线网关；不加载界面。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；技能安装与卸载都会在这里订阅与释放时机。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI协调器；保持正式实现，避免技能查询走空分支。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网关；公开快照广播与正式单机模式保持相同路径。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.local_human_player_id = 0
	# 表现间隔归零；规则状态不得依赖计时器，断言在零速度模式下同步完成。
	_controller.game_flow_interval_seconds = 0.0


## 创建最小权威状态并安装武将技能；一号领袖、其余反贼形成稳定敌我关系。
## 参数 character_id 决定一号位使用银狼还是样例武将，其余位置固定使用样例武将。
func _reset_state(player_count: int, character_id: String = YINLANG_CHARACTER_ID) -> void:
	# 先卸载旧实例；否则上一场景的技能订阅会跨场景继续响应规则时机。
	_controller._uninstall_all_character_skills()
	_controller.state = GameState.new()
	_controller.state.match_id = "yinlang-mechanics"
	_controller.state.match_mode = IdentityRules.MODE_IDENTITY
	_controller.state.turn_number = 1
	_controller.state.round_number = 1
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	_controller.state.phase_index = 3
	for player_id: int in range(player_count):
		# 当前测试玩家；一号位按参数使用银狼，其余位置使用样例武将。
		var player: PlayerState = PlayerState.new(player_id, "银狼测试玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else "rebel"
		player.identity_revealed = true
		player.max_hp = 5
		player.hp = 5
		player.character_id = character_id if player_id == 0 else SAMPLE_CHARACTER_ID
		_controller.state.players.append(player)
	_controller._rebuild_match_rule_services_and_root_event()
	_controller._pending_card_choice.clear()
	_controller._deferred_skill_settlements.clear()
	# 摸牌堆；组合技能的「你摸一张牌」与以太回流都需要真实存在的公共牌堆。
	_fill_draw_pile(DRAW_PILE_SIZE)
	# 按武将定义安装固有技能；查询入口必须能在安装后立刻识别它们。
	_controller._install_all_character_skills()


## 往公共摸牌堆里放入指定数量的实体牌；数组末尾是牌堆顶。
func _fill_draw_pile(count: int) -> void:
	for index: int in range(count):
		# 新实体；初始属于公共区域，不携带任何持有者。
		var card: CardInstance = CardInstance.new("sha", "spade", index % 13 + 1)
		card.zone = "draw_pile"
		card.owner_id = -1
		_controller.state.draw_pile.append(card)


## 武将定义：银狼必须存在，势力、体力、性别与技能引用都必须与设计一致。
func _test_character_definition() -> bool:
	# 银狼武将元数据；字段缺失或数值漂移都会直接改变开局强度。
	var definition: Dictionary = GameDatabase.get_character(YINLANG_CHARACTER_ID)
	if definition.is_empty():
		return _fail("character_missing id=%s" % YINLANG_CHARACTER_ID)
	if str(definition.get("display_name", "")) != "银狼":
		return _fail("display_name=%s" % str(definition.get("display_name", "")))
	if str(definition.get("gender", "")) != "female":
		return _fail("gender=%s" % str(definition.get("gender", "")))
	if str(definition.get("faction", "")) != "xinghelieshou":
		return _fail("faction=%s" % str(definition.get("faction", "")))
	if int(definition.get("max_hp", 0)) != 3:
		return _fail("max_hp=%d" % int(definition.get("max_hp", 0)))
	# 技能引用顺序即技能栏顺序；必须与设计一致。
	var skill_ids: Array = definition.get("skills", []) as Array
	if skill_ids.size() != 2 or str(skill_ids[0]) != ZHURU_SKILL_ID or str(skill_ids[1]) != YITAI_SKILL_ID:
		return _fail("skills=%s" % [skill_ids])
	# 技能正文必须逐字等于设计原文；【以太】正文里的「限定技」还会驱动 limited 标记。
	var zhuru: SkillDefinition = GameDatabase.create_skill(ZHURU_SKILL_ID)
	var yitai: SkillDefinition = GameDatabase.create_skill(YITAI_SKILL_ID)
	if zhuru == null or yitai == null:
		return _fail("skill_instance_null")
	# 技能正文；技能定义把原文存在元数据里，界面与快照都从同一处读取。
	var zhuru_description: String = str(zhuru.get_metadata().get("description", ""))
	var yitai_description: String = str(yitai.get_metadata().get("description", ""))
	if not zhuru_description.begins_with("游戏开始时，你可组合并获得一项技能"):
		return _fail("zhuru_description=%s" % zhuru_description)
	if not yitai_description.begins_with("限定技，出牌阶段，你可以创造并获得一张卡牌"):
		return _fail("yitai_description=%s" % yitai_description)
	if not yitai.limited:
		return _fail("yitai_not_limited")
	# 【注入】不是锁定技，正文也不含「锁定技」字样；组合出来的技能才是锁定技。
	if zhuru.lock or zhuru.half_locked:
		return _fail("zhuru_unexpected_lock lock=%s half=%s" % [str(zhuru.lock), str(zhuru.half_locked)])
	return true


## 数据池完整性：时机键与效果键都必须有文本，组合正文格式固定，订阅时机不为空。
func _test_pool_integrity() -> bool:
	# 随机提供项断言需要权威状态与随机历史，因此先建立最小状态。
	_reset_state(2)
	# 时机池条目；每条都必须有稳定键、玩家可见文本与非空订阅时机。
	for entry_variant: Variant in ZhuruComposePools.get_timing_entries():
		# 当前时机条目；缺少键或文本会让界面显示空白、技能订阅不到任何时机。
		var entry: Dictionary = entry_variant as Dictionary
		# 当前时机键；用于后续按键查询。
		var timing_key: String = str(entry.get(ZhuruComposePools.KEY_FIELD, ""))
		if timing_key.is_empty() or str(entry.get(ZhuruComposePools.TEXT_FIELD, "")).is_empty():
			return _fail("timing_entry_incomplete=%s" % [entry])
		if ZhuruComposePools.get_subscription_timings(timing_key).is_empty():
			return _fail("timing_no_subscription key=%s" % timing_key)
		if not ZhuruComposePools.is_valid_timing_key(timing_key):
			return _fail("timing_key_not_valid key=%s" % timing_key)
	# 两个效果池；每条都必须有键、文本与所属类别。
	for pool_kind: String in [ZhuruComposePools.KIND_JINCHENG, ZhuruComposePools.KIND_QUEXIAN]:
		if ZhuruComposePools.get_effects(pool_kind).is_empty():
			return _fail("effect_pool_empty kind=%s" % pool_kind)
		for entry_variant: Variant in ZhuruComposePools.get_effects(pool_kind):
			# 当前效果条目；键为空会让组合控制项无法解析。
			var entry: Dictionary = entry_variant as Dictionary
			# 当前效果键；用于按类别校验。
			var effect_key: String = str(entry.get(ZhuruComposePools.KEY_FIELD, ""))
			if effect_key.is_empty() or str(entry.get(ZhuruComposePools.TEXT_FIELD, "")).is_empty():
				return _fail("effect_entry_incomplete kind=%s entry=%s" % [pool_kind, entry])
			if not ZhuruComposePools.is_valid_effect_key(pool_kind, effect_key):
				return _fail("effect_key_not_valid kind=%s key=%s" % [pool_kind, effect_key])
			# 类别隔离：进程池的效果键不得在缺陷池里也被判为合法（除非两个池确实共用同名效果）。
			if not ZhuruComposePools.is_valid_effect_key(ZhuruComposePools.KIND_JINCHENG, effect_key) and not ZhuruComposePools.is_valid_effect_key(ZhuruComposePools.KIND_QUEXIAN, effect_key):
				return _fail("effect_key_in_no_pool key=%s" % effect_key)
	# 组合正文格式：必须严格等于「锁定技，<时机>，<效果>。每回合限一次。」。
	# 时机文本与效果文本；用于拼出期望正文。
	var timing_text: String = str(ZhuruComposePools.get_timing_entry(SAMPLE_TIMING_KEY).get(ZhuruComposePools.TEXT_FIELD, ""))
	var effect_text: String = str(ZhuruComposePools.get_effect_entry(ZhuruComposePools.KIND_JINCHENG, SAMPLE_EFFECT_KEY).get(ZhuruComposePools.TEXT_FIELD, ""))
	if timing_text.is_empty() or effect_text.is_empty():
		return _fail("sample_entries_missing timing=%s effect=%s" % [SAMPLE_TIMING_KEY, SAMPLE_EFFECT_KEY])
	# 实际正文与期望正文；两者必须逐字一致。
	var expected: String = "锁定技，%s，%s。每回合限一次。" % [timing_text, effect_text]
	if ZhuruComposePools.compose_description(timing_text, effect_text) != expected:
		return _fail("description_format=%s" % ZhuruComposePools.compose_description(timing_text, effect_text))
	# 随机提供项：必须返回互不重复的键，且数量不超过候选总数。
	var offered: Array[String] = _controller.pick_random_distinct_keys(["a", "b", "c", "d"], 2, "yinlang_test_offering", {})
	if offered.size() != 2 or offered[0] == offered[1]:
		return _fail("random_offering=%s" % [offered])
	if _controller.pick_random_distinct_keys([], 2, "yinlang_test_offering", {}).size() != 0:
		return _fail("random_offering_empty_pool")
	# 组合技能必须声明「正文自带每回合额度」：界面据此不再追加「每回合可发动1次」，
	# 否则同一句「每回合限一次」会在悬停说明里出现两次。这条断言覆盖元数据 → 数据库的完整链路。
	for composed_skill_id: String in [JINCHENG_SKILL_ID, QUEXIAN_SKILL_ID]:
		if not bool(GameDatabase.get_skill(composed_skill_id).get("declares_own_per_turn_limit", false)):
			return _fail("composed_skill_missing_own_limit_declaration=%s" % composed_skill_id)
	# 普通技能不得误带该声明，否则它们会失去应有的额度提示。
	if bool(GameDatabase.get_skill("yitai").get("declares_own_per_turn_limit", false)):
		return _fail("yitai_wrongly_declares_own_limit")
	return true


## 自由控制项协议：声明 allow_free_control_id 的请求接受任意控制项，未声明的请求仍然严格拒绝。
func _test_free_control_protocol() -> bool:
	# 基线请求；只用于验证校验函数本身，不进入控制器。
	var request: ChoiceRequest = ChoiceRequest.new()
	request.request_id = 1
	request.actor_id = 0
	request.choice_type = MatchController.YINLANG_COMPOSE_CHOICE_TYPE
	request.control_ids = []
	# 响应对象；控制项与确认标记按被测场景填写。
	var response: ChoiceResponse = ChoiceResponse.new()
	response.request_id = 1
	response.actor_id = 0
	response.control_id = "%s%s%s%s" % [MatchController.YINLANG_COMPOSE_CONTROL_PREFIX, SAMPLE_TIMING_KEY, MatchController.YINLANG_CONTROL_SEPARATOR, SAMPLE_EFFECT_KEY]
	response.confirmed = true
	# 未声明自由控制项时必须拒绝：这是防止客户端伪造效果键的通用防线。
	if request.validate_response(response).is_empty():
		return _fail("free_control_accepted_without_flag")
	request.allow_free_control_id = true
	if not request.validate_response(response).is_empty():
		return _fail("free_control_rejected_with_flag reason=%s" % request.validate_response(response))
	# 取消提交：自由控制项标记不得改变取消语义。取消意味着「整份回答一并放弃」，
	# 因此即使响应里带着控制项也必须被接受（控制器只读取 confirmed=false），
	# 否则玩家在自由窗口里点取消会被权威端拒绝，窗口永远关不掉。
	var cancel_response: ChoiceResponse = ChoiceResponse.new()
	cancel_response.request_id = 1
	cancel_response.actor_id = 0
	cancel_response.control_id = response.control_id
	cancel_response.confirmed = false
	if not request.validate_response(cancel_response).is_empty():
		return _fail("free_control_cancel_rejected reason=%s" % request.validate_response(cancel_response))
	# 序列化往返必须保留该标记，否则联机与回放会退回严格白名单校验。
	var restored: ChoiceRequest = ChoiceRequest.from_dict(request.to_dict())
	if restored == null or not restored.allow_free_control_id:
		return _fail("free_control_flag_lost")
	return true


## 开局组合：gameStart 必须开出一个组合窗口，且只给持有者自己组合【进程】。
func _test_inject_game_start() -> bool:
	_reset_state(3)
	# 开局前不应存在任何组合技能实例。
	if not _controller.get_skill_instances(0, JINCHENG_SKILL_ID).is_empty():
		return _fail("composed_preinstalled")
	_controller._emit_rule_timing("gameStart", -1, -1, -1)
	# 当前待处理请求；必须是自由控制项类型的组合窗口。
	var window_error: String = _require_window(MatchController.YINLANG_COMPOSE_CHOICE_TYPE)
	if not window_error.is_empty():
		return _fail("gamestart_%s" % window_error)
	# 请求上下文；必须是注入窗口且类别池为进程。
	var context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(context.get(MatchController.YINLANG_WINDOW_CONTEXT_KEY, "")) != MatchController.YINLANG_WINDOW_INJECT:
		return _fail("gamestart_window_kind=%s" % str(context.get(MatchController.YINLANG_WINDOW_CONTEXT_KEY, "")))
	if str(context.get("pool_kind", "")) != ZhuruComposePools.KIND_JINCHENG:
		return _fail("gamestart_pool=%s" % str(context.get("pool_kind", "")))
	if int(context.get("grant_target_id", -1)) != 0:
		return _fail("gamestart_target=%d" % int(context.get("grant_target_id", -1)))
	# 默认候选：两栏都必须是非空的随机提供项，AI 短名单也必须在窗口里给出。
	if (context.get("timing_offering", []) as Array).is_empty() or (context.get("effect_offering", []) as Array).is_empty():
		return _fail("gamestart_offering_empty=%s" % [context])
	if (context.get("ai_candidate_control_ids", []) as Array).is_empty():
		return _fail("gamestart_ai_shortlist_empty")
	# AI 作答路径：合法动作必须来自短名单，否则 AI 的请求会永久挂住。
	var actions: Array[Dictionary] = _controller._build_card_choice_actions(_controller._pending_card_choice)
	# 短名单里的控制项；用于确认动作生成确实按短名单枚举。
	var shortlist: Array = context.get("ai_candidate_control_ids", []) as Array
	if actions.size() < shortlist.size():
		return _fail("gamestart_action_count=%d shortlist=%d" % [actions.size(), shortlist.size()])
	# 提交一个合法组合；必须产生一份【进程】实例并写入运行时配置。
	var control_id: String = "%s%s%s%s" % [MatchController.YINLANG_COMPOSE_CONTROL_PREFIX, SAMPLE_TIMING_KEY, MatchController.YINLANG_CONTROL_SEPARATOR, SAMPLE_EFFECT_KEY]
	if not _submit_control(control_id, true):
		return _fail("gamestart_submit_rejected")
	# 新实例；首份实例的实例键等于技能ID。
	var instance: SkillDefinition = _controller.get_skill_instance(0, JINCHENG_SKILL_ID)
	if instance == null:
		return _fail("gamestart_instance_missing keys=%s" % [_controller.get_installed_skill_keys(0)])
	if instance.get_instance_key() != JINCHENG_SKILL_ID:
		return _fail("gamestart_instance_key=%s" % instance.get_instance_key())
	# 运行时配置；必须与提交的组合严格一致。
	var runtime_data: Dictionary = _controller.get_runtime_skill_data(0, JINCHENG_SKILL_ID)
	if str(runtime_data.get(ComposedSkillBase.RUNTIME_KEY_TIMING, "")) != SAMPLE_TIMING_KEY or str(runtime_data.get(ComposedSkillBase.RUNTIME_KEY_EFFECT, "")) != SAMPLE_EFFECT_KEY:
		return _fail("gamestart_runtime_data=%s" % [runtime_data])
	# 动态正文；必须等于组合模板。动态正文按实例键存放在玩家状态里，界面与日志都读同一份。
	var display_description: String = str((_controller.state.get_player(0).dynamic_skill_descriptions as Dictionary).get(JINCHENG_SKILL_ID, ""))
	if not display_description.begins_with("锁定技，"):
		return _fail("gamestart_description=%s" % display_description)
	# 幂等：重复派发 gameStart 不得再发一份技能。
	_controller._emit_rule_timing("gameStart", -1, -1, -1)
	if not _controller._pending_card_choice.is_empty():
		return _fail("gamestart_not_idempotent")
	if _controller.get_skill_instances(0, JINCHENG_SKILL_ID).size() != 1:
		return _fail("gamestart_duplicate_instances")
	return true


## 准备阶段：主演目标拿到【进程】，非主演目标拿到【缺陷】；取消时不产生任何技能。
func _test_inject_prepare_phase_pools() -> bool:
	_reset_state(3)
	# 先把本人设为主演；准备阶段选择自己时必须给出进程池。
	_controller.set_starring_role(0)
	_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, -1)
	if _controller._pending_card_choice.is_empty():
		return _fail("prepare_no_target_request")
	if str(_controller._pending_card_choice.get("choice_type", "")) != "target":
		return _fail("prepare_choice_type=%s" % str(_controller._pending_card_choice.get("choice_type", "")))
	# 候选目标必须包含全部存活在场角色（含自己）。
	var candidates: Array = _controller._pending_card_choice.get("target_ids", []) as Array
	if candidates.size() != 3 or not candidates.has(0):
		return _fail("prepare_targets=%s" % [candidates])
	if not _submit_targets([0]):
		return _fail("prepare_target_submit_rejected")
	# 主演目标 → 进程池。
	if not _require_window(MatchController.YINLANG_COMPOSE_CHOICE_TYPE).is_empty():
		return _fail("prepare_starring_window_missing")
	# 主演组合窗口上下文；类别池必须是进程。
	var starring_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(starring_context.get("pool_kind", "")) != ZhuruComposePools.KIND_JINCHENG:
		return _fail("prepare_starring_pool=%s" % str(starring_context.get("pool_kind", "")))
	# 取消组合窗口：不得产生任何技能实例。
	if not _submit_control("", false):
		return _fail("prepare_compose_cancel_rejected")
	if not _controller.get_skill_instances(0, JINCHENG_SKILL_ID).is_empty() or not _controller.get_skill_instances(0, QUEXIAN_SKILL_ID).is_empty():
		return _fail("prepare_cancel_granted_skill")
	# 清除主演后选择他人：必须给出缺陷池，并把技能授予被选中的角色。
	_controller.starring_role_service.clear_starring()
	_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, -1)
	if not _submit_targets([1]):
		return _fail("prepare_nonstarring_target_submit_rejected")
	if not _require_window(MatchController.YINLANG_COMPOSE_CHOICE_TYPE).is_empty():
		return _fail("prepare_nonstarring_window_missing")
	# 非主演组合窗口上下文；类别池必须是缺陷，获得者必须是目标角色。
	var nonstarring_context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if str(nonstarring_context.get("pool_kind", "")) != ZhuruComposePools.KIND_QUEXIAN:
		return _fail("prepare_nonstarring_pool=%s" % str(nonstarring_context.get("pool_kind", "")))
	if int(nonstarring_context.get("grant_target_id", -1)) != 1:
		return _fail("prepare_nonstarring_target=%d" % int(nonstarring_context.get("grant_target_id", -1)))
	# 缺陷池的合法效果键与进程池不同，因此必须从本次请求声明的池里取键。
	var quexian_effect_key: String = _first_effect_key(ZhuruComposePools.KIND_QUEXIAN)
	if quexian_effect_key.is_empty():
		return _fail("quexian_pool_empty")
	var control_id: String = "%s%s%s%s" % [MatchController.YINLANG_COMPOSE_CONTROL_PREFIX, SAMPLE_TIMING_KEY, MatchController.YINLANG_CONTROL_SEPARATOR, quexian_effect_key]
	if not _submit_control(control_id, true):
		return _fail("prepare_quexian_submit_rejected")
	# 技能必须授予被选中的角色，而不是技能持有者。
	if _controller.get_skill_instance(1, QUEXIAN_SKILL_ID) == null:
		return _fail("quexian_not_granted keys=%s" % [_controller.get_installed_skill_keys(1)])
	if _controller.get_skill_instance(0, QUEXIAN_SKILL_ID) != null:
		return _fail("quexian_granted_to_wrong_player")
	return true


## 同名技能累积：连续组合两次必须得到两份独立实例，各自持有独立额度与独立正文。
func _test_composed_instances_accumulate() -> bool:
	_reset_state(2)
	# 第一次组合：占用首实例键。
	if not _compose_once(SAMPLE_EFFECT_KEY):
		return false
	# 第二次组合：必须占用最小空闲序号键，而不是替换首实例。
	if not _compose_once(SAMPLE_EFFECT_KEY):
		return false
	# 实例粒度：两份实例都在。
	var instances: Array[SkillDefinition] = _controller.get_skill_instances(0, JINCHENG_SKILL_ID)
	if instances.size() != 2:
		return _fail("accumulate_count=%d keys=%s" % [instances.size(), _controller.get_installed_skill_keys(0)])
	# 第二份实例键必须等于「技能ID#2」。
	var second_instance: SkillDefinition = _controller.get_skill_instance(0, SECOND_COMPOSED_INSTANCE_KEY)
	if second_instance == null:
		return _fail("accumulate_second_missing keys=%s" % [_controller.get_installed_skill_keys(0)])
	if second_instance.get_instance_key() != SECOND_COMPOSED_INSTANCE_KEY:
		return _fail("accumulate_second_key=%s" % second_instance.get_instance_key())
	# 额度按实例分别计算：先耗尽第二份实例的每回合额度，首实例必须仍可发动。
	if not _controller.consume_acquired_skill_use(0, SECOND_COMPOSED_INSTANCE_KEY):
		return _fail("accumulate_second_consume_rejected")
	if _controller.can_use_acquired_skill(0, SECOND_COMPOSED_INSTANCE_KEY):
		return _fail("accumulate_second_quota_not_exhausted")
	if not _controller.can_use_acquired_skill(0, JINCHENG_SKILL_ID):
		return _fail("accumulate_first_quota_affected")
	# 技能粒度去重后只剩一项；界面按技能ID渲染时不会出现重复行。
	var deduped_ids: Array[String] = _controller.get_installed_skill_ids(0)
	# 该技能在去重结果里出现的次数；必须恰好一次。
	var deduped_hits: int = 0
	for skill_id: String in deduped_ids:
		if skill_id == JINCHENG_SKILL_ID:
			deduped_hits += 1
	if deduped_hits != 1:
		return _fail("accumulate_deduped_hits=%d" % deduped_hits)
	return true


## 组合技能按实例读取运行时配置并订阅对应时机：受击后必须真的结算一次摸牌。
func _test_composed_skill_subscribes_runtime_timing() -> bool:
	_reset_state(2)
	if not _compose_once(SAMPLE_EFFECT_KEY):
		return false
	# 受击前的摸牌堆数量；用于验证时机确实被订阅并结算。
	var draw_count_before: int = _controller.state.draw_pile.size()
	# 模拟一次对持有者的伤害结算；damage_after 的 target 角色必须命中技能持有者。
	_controller._emit_rule_timing("damageAfter", 1, 1, 0, {"amount":1, "card_id":""})
	# 摸牌堆数量必须减少；这是「技能真的触发了」的唯一客观证据。
	if _controller.state.draw_pile.size() >= draw_count_before:
		return _fail("composed_timing_not_triggered before=%d after=%d" % [draw_count_before, _controller.state.draw_pile.size()])
	# 每回合限一次：第二次同一时机不得再次结算。
	var draw_count_after_first: int = _controller.state.draw_pile.size()
	_controller._emit_rule_timing("damageAfter", 1, 1, 0, {"amount":1, "card_id":""})
	if _controller.state.draw_pile.size() != draw_count_after_first:
		return _fail("composed_quota_not_enforced")
	return true


## 以太造牌窗口：控制项必须被权威侧接受并造出带铸造来源的牌；非法参数必须被拒绝。
func _test_aether_mint_window() -> bool:
	_reset_state(2)
	# 以太是限定技；必须处于自己的出牌阶段才可发动。
	if not _controller.can_activate_skill(0, YITAI_SKILL_ID):
		return _fail("yitai_not_activatable")
	if not _controller.activate_skill(0, YITAI_SKILL_ID):
		return _fail("yitai_activate_rejected")
	if not _require_window(MatchController.YINLANG_MINT_CHOICE_TYPE).is_empty():
		return _fail("mint_window_missing")
	# 请求上下文；必须携带已有牌名快照、长度上限与可复制牌列表。
	var context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	if (context.get("existing_card_names", []) as Array).is_empty():
		return _fail("mint_existing_names_empty")
	if int(context.get("card_name_max_length", 0)) != MatchController.MINT_CARD_NAME_MAX_LENGTH:
		return _fail("mint_name_max_length=%d" % int(context.get("card_name_max_length", 0)))
	if (context.get("copyable_cards", []) as Array).is_empty():
		return _fail("mint_copyable_cards_empty")
	if (context.get("ai_candidate_control_ids", []) as Array).is_empty():
		return _fail("mint_ai_shortlist_empty")
	# AI 短名单里的每一条都必须是合法的六段造牌控制项；短名单拼接错误会让 AI 的造牌请求永远被拒绝。
	for control_variant: Variant in context.get("ai_candidate_control_ids", []) as Array:
		# 当前 AI 候选控制项；分段数必须与协议一致。
		var ai_control_id: String = str(control_variant)
		if ai_control_id.split(MatchController.YINLANG_CONTROL_SEPARATOR).size() != MatchController.YINLANG_MINT_CONTROL_FIELD_COUNT:
			return _fail("mint_ai_control_segments=%s" % ai_control_id)
	# 静态定义重名必须被拒绝；判据按**显示牌名**（如「杀」）而不是定义ID（如 sha）比对。
	var static_display_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card(MINT_SOURCE_DEFINITION_ID))
	var duplicate_control_id: String = _build_mint_control_id(static_display_name, MINT_SUIT, MINT_RANK, MINT_SOURCE_DEFINITION_ID)
	if _submit_control(duplicate_control_id, true):
		return _fail("mint_duplicate_static_name_accepted name=%s" % static_display_name)
	if _controller._pending_card_choice.is_empty():
		# 被拒绝后请求必须仍然在等待，否则玩家一次误输入就会失去这次限定技。
		return _fail("mint_request_cleared_after_reject")
	# 不存在的被复制牌定义必须被拒绝。
	var absent_definition_control_id: String = _build_mint_control_id(MINT_CUSTOM_NAME, MINT_SUIT, MINT_RANK, "not_a_card")
	if _submit_control(absent_definition_control_id, true):
		return _fail("mint_absent_definition_accepted")
	# 非法点数必须被拒绝；int("abc") 会静默返回0，因此必须显式判非法。
	var bad_rank_control_id: String = "%s%s%s%s%sabc%s%s" % [MatchController.YINLANG_MINT_CONTROL_PREFIX, MINT_CUSTOM_NAME, MatchController.YINLANG_CONTROL_SEPARATOR, MINT_SUIT, MatchController.YINLANG_CONTROL_SEPARATOR, MatchController.YINLANG_CONTROL_SEPARATOR, MINT_SOURCE_DEFINITION_ID]
	if _submit_control(bad_rank_control_id, true):
		return _fail("mint_bad_rank_accepted")
	# 合法造牌；牌必须进入手牌并带铸造来源标记。
	var hand_count_before: int = _controller.state.get_player(0).hand.size()
	var minted_control_id: String = _build_mint_control_id(MINT_CUSTOM_NAME, MINT_SUIT, MINT_RANK, MINT_SOURCE_DEFINITION_ID)
	if not _submit_control(minted_control_id, true):
		return _fail("mint_submit_rejected")
	var hand: Array = _controller.state.get_player(0).hand
	if hand.size() != hand_count_before + 1:
		return _fail("mint_hand_size=%d before=%d" % [hand.size(), hand_count_before])
	# 新牌实体；牌名覆写、铸造来源与花色点数都必须原样落地。
	var minted_card: CardInstance = hand[hand.size() - 1] as CardInstance
	if minted_card == null or minted_card.get_display_name_override() != MINT_CUSTOM_NAME:
		return _fail("mint_card_name=%s" % ("" if minted_card == null else minted_card.get_display_name_override()))
	if minted_card.minted_skill_id != YITAI_SKILL_ID:
		return _fail("mint_skill_id=%s" % minted_card.minted_skill_id)
	if minted_card.definition_id != MINT_SOURCE_DEFINITION_ID or minted_card.suit != MINT_SUIT or minted_card.rank != MINT_RANK:
		return _fail("mint_card_fields=%s/%s/%d" % [minted_card.definition_id, minted_card.suit, minted_card.rank])
	# 限定技额度必须已经消耗；再次发动必须失败。
	if _controller.can_activate_skill(0, YITAI_SKILL_ID):
		return _fail("yitai_quota_not_consumed")
	# 同一出牌阶段内的重复落地：即使有人把第二条「已确认」的造牌响应再送进技能一次
	# （窗口被重复提交、网络重放、回放重放、事件调度重跑同一步），也不得造出第二张牌。
	# 这条断言覆盖的是**效果落地处自己的额度复核**——发动入口的拦截管不到提交路径。
	var yitai_instance: SkillDefinition = _controller.get_skill_instance(0, YITAI_SKILL_ID)
	if yitai_instance == null:
		return _fail("yitai_instance_missing")
	# 重放响应；请求号与事件号不影响本技能解析，只有 confirmed 与 control_id 参与判定。
	var replay_response: ChoiceResponse = ChoiceResponse.new(1, -1, 0, true)
	replay_response.control_id = _build_mint_control_id(REPLAY_MINT_NAME, MINT_SUIT, MINT_RANK, MINT_SOURCE_DEFINITION_ID)
	yitai_instance.continue_selection({"kind":MINT_CHOICE_KIND}, replay_response)
	if _controller.state.get_player(0).hand.size() != hand.size():
		return _fail("yitai_duplicate_mint_hand=%d" % _controller.state.get_player(0).hand.size())
	# 重放用的牌名必须仍然可用；若它已经被占用，说明第二张牌真的被造了出来。
	if not _controller.is_card_name_available(REPLAY_MINT_NAME):
		return _fail("yitai_duplicate_mint_created_card")
	return true


## 以太回流：任意角色回合结束时，弃牌堆里的以太牌必须让持有者成为主演并被洗回摸牌堆。
func _test_aether_returns_card_to_draw_pile() -> bool:
	_reset_state(2)
	if not _controller.activate_skill(0, YITAI_SKILL_ID):
		return _fail("washback_activate_rejected")
	# 直接构造合法造牌请求并提交；避免依赖界面路径。
	var minted_control_id: String = _build_mint_control_id(MINT_CUSTOM_NAME, MINT_SUIT, MINT_RANK, MINT_SOURCE_DEFINITION_ID)
	if not _submit_control(minted_control_id, true):
		return _fail("washback_mint_rejected")
	# 新牌实体；把它手工移入弃牌堆，模拟“以太牌已经用掉”。
	var hand: Array = _controller.state.get_player(0).hand
	var minted_card: CardInstance = hand[hand.size() - 1] as CardInstance
	if minted_card == null:
		return _fail("washback_card_missing")
	hand.remove_at(hand.size() - 1)
	minted_card.zone = "discard_pile"
	minted_card.owner_id = -1
	_controller.state.discard_pile.append(minted_card)
	# 弃牌堆检索端口必须按铸造来源认出它。
	var found_uids: Array[int] = _controller.get_discard_pile_card_uids_by_skill(YITAI_SKILL_ID)
	if not found_uids.has(minted_card.uid):
		return _fail("washback_lookup=%s uid=%d" % [found_uids, minted_card.uid])
	# 一名其他角色的回合结束；回流与回合归属无关。
	_controller._emit_rule_timing("phaseAfter", 1, 1, -1)
	if not _controller.is_starring_role(0):
		return _fail("washback_not_starring")
	if _controller.state.discard_pile.has(minted_card):
		return _fail("washback_card_still_in_discard")
	if not _controller.state.draw_pile.has(minted_card):
		return _fail("washback_card_not_in_draw_pile")
	# 洗回后铸造来源标记必须保留，否则它再也无法被识别（例如第二次回流或读档）。
	if minted_card.minted_skill_id != YITAI_SKILL_ID:
		return _fail("washback_skill_id_lost=%s" % minted_card.minted_skill_id)
	# 弃牌堆已无以太牌时不得改变主演归属；由主演服务保证至多一名主演。
	_controller.starring_role_service.clear_starring()
	_controller._emit_rule_timing("phaseAfter", 1, 1, -1)
	if _controller.is_starring_role(0):
		return _fail("washback_starring_without_card")
	return true


## 牌名辅助端口：已占用牌名快照必须同时包含静态定义名与本局造出的牌名。
func _test_card_name_helpers() -> bool:
	_reset_state(2)
	# 静态牌名快照；必须非空且包含【杀】。
	var static_names: Array[String] = GameDatabase.get_all_card_display_names()
	if static_names.is_empty():
		return _fail("static_names_empty")
	# 已占用牌名快照；静态名必须全部包含在内。
	var taken_names: Array[String] = _controller.collect_taken_card_display_names()
	if taken_names.size() < static_names.size():
		return _fail("taken_names=%d static=%d" % [taken_names.size(), static_names.size()])
	# 本局造出的牌名也必须进入快照，否则界面会在造第二张牌时给出错误提示。
	if not _controller.activate_skill(0, YITAI_SKILL_ID):
		return _fail("names_activate_rejected")
	if not _submit_control(_build_mint_control_id(MINT_CUSTOM_NAME, MINT_SUIT, MINT_RANK, MINT_SOURCE_DEFINITION_ID), true):
		return _fail("names_mint_rejected")
	if not _controller.collect_taken_card_display_names().has(MINT_CUSTOM_NAME):
		return _fail("minted_name_not_in_taken_names")
	# 牌名判据与快照同源：已占用名必须被判为不可用。
	if _controller.is_card_name_available(MINT_CUSTOM_NAME):
		return _fail("minted_name_reported_available")
	# 静态定义名同样必须被判为不可用；按显示牌名比对，而不是定义ID。
	var static_display_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card(MINT_SOURCE_DEFINITION_ID))
	if _controller.is_card_name_available(static_display_name):
		return _fail("static_name_reported_available=%s" % static_display_name)
	# 按类别取牌：基本牌列表必须非空且按字典序排列。
	var basic_ids: Array[String] = GameDatabase.get_card_ids_by_type("basic")
	if basic_ids.is_empty():
		return _fail("basic_card_ids_empty")
	# 排序校验；相邻项必须非降序。
	for index: int in range(1, basic_ids.size()):
		if basic_ids[index - 1] > basic_ids[index]:
			return _fail("basic_card_ids_unsorted=%s" % [basic_ids])
	# 造牌窗口的本地牌名判据必须与权威判据同源：重名与超长都要禁用「确定」，
	# 否则会出现「提示说重名、按钮却能点」的不一致（PRD 明确要求重名时确定不可点击）。
	# 这里选好被复制牌，使「确定」的唯一变量就是牌名。
	var mint_view: YinlangMintView = YinlangMintView.new()
	add_child(mint_view)
	mint_view.configure({
		"existing_card_names":[static_display_name],
		"card_name_max_length":MatchController.MINT_CARD_NAME_MAX_LENGTH,
		"copyable_cards":[{"id":MINT_SOURCE_DEFINITION_ID, "name":static_display_name, "type":"basic"}],
	})
	# 花色与点数必须全部铺开成按钮，而不是收在下拉框里：数量直接对应选项表长度。
	if mint_view._suit_buttons.size() != YinlangMintView.SUIT_OPTIONS.size():
		mint_view.queue_free()
		return _fail("mint_view_suit_buttons=%d" % mint_view._suit_buttons.size())
	if mint_view._rank_buttons.size() != YinlangMintView.MAX_RANK - YinlangMintView.MIN_RANK + 1:
		mint_view.queue_free()
		return _fail("mint_view_rank_buttons=%d" % mint_view._rank_buttons.size())
	# 被复制牌也必须铺开成按钮；一张候选对应一个按钮，跨类别共用一个互斥按钮组。
	if mint_view._card_buttons.size() != 1:
		mint_view.queue_free()
		return _fail("mint_view_card_buttons=%d" % mint_view._card_buttons.size())
	mint_view._on_card_toggled(true, MINT_SOURCE_DEFINITION_ID)
	if mint_view._selected_definition_id != MINT_SOURCE_DEFINITION_ID:
		mint_view.queue_free()
		return _fail("mint_view_card_not_selected=%s" % mint_view._selected_definition_id)
	# 默认牌名：输入框占位文本必须是默认名，且默认名长度不得超过上限（否则「什么都不填」必然超长）。
	if mint_view._name_edit.placeholder_text != YinlangMintView.DEFAULT_NAME_TEXT:
		mint_view.queue_free()
		return _fail("mint_view_placeholder=%s" % mint_view._name_edit.placeholder_text)
	if YinlangMintView.DEFAULT_NAME_TEXT.length() > MatchController.MINT_CARD_NAME_MAX_LENGTH:
		mint_view.queue_free()
		return _fail("mint_view_default_name_too_long=%d" % YinlangMintView.DEFAULT_NAME_TEXT.length())
	# 空名：不再禁用「确定」，而是回落到默认牌名；默认名可用时确定必须可点。
	if mint_view._effective_name() != YinlangMintView.DEFAULT_NAME_TEXT:
		mint_view.queue_free()
		return _fail("mint_view_effective_name=%s" % mint_view._effective_name())
	if not mint_view._name_rejection_reason().is_empty() or mint_view._confirm_button.disabled:
		mint_view.queue_free()
		return _fail("mint_view_default_name_rejected=%s" % mint_view._name_rejection_reason())
	# 可用名：确定必须启用。
	mint_view._name_edit.text = MINT_CUSTOM_NAME
	mint_view._refresh_name_hint()
	mint_view._refresh_confirm_state()
	if mint_view._confirm_button.disabled or not mint_view._name_rejection_reason().is_empty():
		mint_view.queue_free()
		return _fail("mint_view_available_name_rejected=%s" % mint_view._name_rejection_reason())
	# 重名：必须给出提示且禁用确定。
	mint_view._name_edit.text = static_display_name
	mint_view._refresh_name_hint()
	mint_view._refresh_confirm_state()
	if mint_view._name_rejection_reason().is_empty():
		mint_view.queue_free()
		return _fail("mint_view_duplicate_name_accepted")
	if not mint_view._confirm_button.disabled:
		mint_view.queue_free()
		return _fail("mint_view_duplicate_name_confirm_enabled")
	# 默认名已被占用：空输入同样必须被拦下，否则玩家不填名字会提交一个必然被权威拒绝的请求。
	mint_view.configure({
		"existing_card_names":[YinlangMintView.DEFAULT_NAME_TEXT],
		"card_name_max_length":MatchController.MINT_CARD_NAME_MAX_LENGTH,
		"copyable_cards":[{"id":MINT_SOURCE_DEFINITION_ID, "name":static_display_name, "type":"basic"}],
	})
	mint_view._on_card_toggled(true, MINT_SOURCE_DEFINITION_ID)
	if mint_view._name_rejection_reason().is_empty() or not mint_view._confirm_button.disabled:
		mint_view.queue_free()
		return _fail("mint_view_taken_default_name_accepted")
	# 超长：输入框本身按 max_length 截断，因此正常输入路径下判据不会触发；
	# 但判据必须**独立于输入框**仍然成立（否则将来若有代码路径绕过 LineEdit 写入，超长牌名会漏过本地校验）。
	# 这里把判据使用的长度上限调小、同时把输入框上限调大，单独验证判据本身。
	mint_view._name_edit.text = "名".repeat(MatchController.MINT_CARD_NAME_MAX_LENGTH + 3)
	if mint_view._name_edit.text.length() != MatchController.MINT_CARD_NAME_MAX_LENGTH:
		mint_view.queue_free()
		return _fail("mint_view_name_not_truncated=%d" % mint_view._name_edit.text.length())
	mint_view._name_max_length = 2
	mint_view._refresh_name_hint()
	mint_view._refresh_confirm_state()
	if mint_view._name_rejection_reason().is_empty() or not mint_view._confirm_button.disabled:
		mint_view.queue_free()
		return _fail("mint_view_overlong_name_accepted")
	mint_view.queue_free()
	return true


## 窗口层：绘制层级必须符合文档层级表，窗口按上下文分流，未知标记必须立即关闭。
func _test_window_layer() -> bool:
	# 窗口层实例；直接挂到测试场景下，不依赖牌桌。
	var layer: YinlangWindowsLayer = YinlangWindowsLayer.new()
	layer.name = "YinlangWindowsLayer"
	add_child(layer)
	# _ready 已在 add_child 时执行；层级必须等于文档约定值。
	if layer.z_index != EXPECTED_WINDOW_Z_INDEX:
		return _fail("window_z_index=%d" % layer.z_index)
	if layer.visible:
		return _fail("window_visible_by_default")
	# 组合窗口；必须显示并进入等待状态。
	# 两栏各给两个候选：组合窗口的候选数就是权威随机抽出的个数，界面不再提供展开完整池的入口。
	var timing_offering: Array[String] = [SAMPLE_TIMING_KEY, ABSENT_TIMING_KEY]
	var effect_offering: Array[String] = [SAMPLE_EFFECT_KEY]
	for entry_variant: Variant in ZhuruComposePools.get_effects(ZhuruComposePools.KIND_JINCHENG):
		# 当前效果键；跳过已经放入的第一个候选，取池内下一个不同的键。
		var effect_key: String = str((entry_variant as Dictionary).get(ZhuruComposePools.KEY_FIELD, ""))
		if effect_key != SAMPLE_EFFECT_KEY:
			effect_offering.append(effect_key)
			break
	var compose_request: Dictionary = {
		"request_id":41,
		"choice_type":MatchController.YINLANG_COMPOSE_CHOICE_TYPE,
		"context":{
			MatchController.YINLANG_WINDOW_CONTEXT_KEY:MatchController.YINLANG_WINDOW_INJECT,
			"pool_kind":ZhuruComposePools.KIND_JINCHENG,
			"timing_offering":timing_offering,
			"effect_offering":effect_offering,
		},
	}
	layer.show_request(compose_request)
	if not layer.visible or not layer.is_showing_request(41):
		return _fail("compose_window_not_shown")
	# 组合窗口结构：两栏各两个按钮，而不是可滚动的候选列表；副标题必须为空。
	if layer._compose_view == null:
		return _fail("compose_view_missing")
	if layer._compose_view._timing_buttons.size() != timing_offering.size() or layer._compose_view._effect_buttons.size() != effect_offering.size():
		return _fail("compose_option_buttons=%d/%d" % [layer._compose_view._timing_buttons.size(), layer._compose_view._effect_buttons.size()])
	if not layer._subtitle_label.text.is_empty():
		return _fail("compose_subtitle_not_empty=%s" % layer._subtitle_label.text)
	# 选中两栏各一项后，预览必须给出组合正文，且「确定」解禁。
	layer._compose_view._on_timing_option_toggled(true, SAMPLE_TIMING_KEY)
	layer._compose_view._on_effect_option_toggled(true, SAMPLE_EFFECT_KEY)
	if layer._compose_view._confirm_button.disabled or layer._compose_view._preview_label.text.is_empty():
		return _fail("compose_confirm_disabled_after_select")
	# 未选择完整时「确定」必须保持禁用，避免提交一个必然被权威拒绝的组合。
	layer._compose_view._on_timing_option_toggled(false, SAMPLE_TIMING_KEY)
	layer._compose_view._selected_timing_key = ""
	layer._compose_view._refresh_preview()
	if not layer._compose_view._confirm_button.disabled:
		return _fail("compose_confirm_enabled_without_timing")
	# 造牌窗口；必须切换视图并进入等待状态。
	var mint_request: Dictionary = {
		"request_id":42,
		"choice_type":MatchController.YINLANG_MINT_CHOICE_TYPE,
		"context":{
			MatchController.YINLANG_WINDOW_CONTEXT_KEY:MatchController.YINLANG_WINDOW_AETHER,
			"existing_card_names":["sha"],
			"card_name_max_length":MatchController.MINT_CARD_NAME_MAX_LENGTH,
			"copyable_cards":[{"id":MINT_SOURCE_DEFINITION_ID, "name":"杀", "type":"basic"}],
		},
	}
	layer.show_request(mint_request)
	if not layer.is_showing_request(42):
		return _fail("mint_window_not_shown")
	# 同一条请求重复显示；必须保留已装载的视图，玩家已输入的内容不能因为一次被拒绝的提交而丢失。
	layer.hide_view()
	if layer.is_showing_request(42):
		return _fail("hidden_view_still_reported_visible")
	if not layer.is_loaded_request(42):
		return _fail("hidden_view_lost_loaded_request")
	layer.show_request(mint_request)
	if not layer.is_showing_request(42):
		return _fail("rejected_request_not_reshown")
	# 提交路径本身也不得释放视图：提交后窗口隐藏，但请求与视图都还在，权威拒绝时可原样重试。
	# 这条断言覆盖的是真实链路（视图信号 → 窗口转发），而不只是手工调用 hide_view()。
	layer._on_view_submitted("yinlang|mint|测试|spade|1|%s" % MINT_SOURCE_DEFINITION_ID)
	if layer.visible:
		return _fail("submitted_window_still_visible")
	if not layer.is_loaded_request(42):
		return _fail("submit_released_view")
	layer.show_request(mint_request)
	if not layer.is_showing_request(42):
		return _fail("submit_retry_not_reshown")
	# 取消路径同理：取消同样只是发出请求，不能先释放视图。
	layer._on_view_cancelled()
	if layer.visible or not layer.is_loaded_request(42):
		return _fail("cancel_released_view")
	layer.show_request(mint_request)
	if not layer.is_showing_request(42):
		return _fail("cancel_retry_not_reshown")
	# 未知窗口标记；必须立即关闭，不能留下无法提交的空框。
	layer.show_request({"request_id":43, "choice_type":"card", "context":{}})
	if layer.visible:
		return _fail("unknown_window_left_visible")
	if layer.is_loaded_request(42):
		return _fail("unknown_window_kept_loaded_request")
	# 主题切换刷新；窗口层必须能在任何主题下重建配色而不报错。
	layer.refresh_ui_style()
	layer.queue_free()
	return true


## 断言当前待处理请求是指定类型的自由控制项窗口；返回空字符串表示通过。
func _require_window(expected_choice_type: String) -> String:
	if _controller._pending_card_choice.is_empty():
		return "no_pending_request"
	if str(_controller._pending_card_choice.get("choice_type", "")) != expected_choice_type:
		return "choice_type=%s expected=%s" % [str(_controller._pending_card_choice.get("choice_type", "")), expected_choice_type]
	if not bool(_controller._pending_card_choice.get("allow_free_control_id", false)):
		return "free_control_flag_missing"
	return ""


## 提交一个文字控制项响应；返回是否被权威入口接受。
func _submit_control(control_id: String, confirmed: bool) -> bool:
	# 当前请求编号与回答者；必须与创建时的取值一致，否则会被权威入口拒绝。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	# 标准选择动作；控制项维度是自由文本，因此不携带任何实体牌或目标。
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":control_id, "confirmed":confirmed}
	return _controller.submit_action(action)


## 提交一个纯目标选择响应；返回是否被权威入口接受。
func _submit_targets(target_ids: Array[int]) -> bool:
	# 当前请求编号与回答者；必须与创建时的取值一致。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	var chooser_id: int = int(_controller._pending_card_choice.get("chooser_id", -1))
	# 标准选择动作；只提交目标维度。
	var action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":target_ids.duplicate(), "confirmed":true}
	return _controller.submit_action(action)


## 走完一次完整的注入准备阶段组合；返回是否成功。
## 先把本人设为主演，使目标落在收益池（进程）上，效果键才能从进程池里取。
func _compose_once(effect_key: String) -> bool:
	_controller.set_starring_role(0)
	_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, -1)
	if not _submit_targets([0]):
		return _fail("compose_target_submit_rejected")
	if not _require_window(MatchController.YINLANG_COMPOSE_CHOICE_TYPE).is_empty():
		return _fail("compose_window_missing")
	# 本次请求声明的类别池；效果键必须从该池里取。
	var context: Dictionary = _controller._pending_card_choice.get("context", {}) as Dictionary
	# 类别池；主演目标固定得到进程池。
	var pool_kind: String = str(context.get("pool_kind", ""))
	# 控制项；格式与权威侧解析规则严格一致。
	var control_id: String = "%s%s%s%s" % [MatchController.YINLANG_COMPOSE_CONTROL_PREFIX, SAMPLE_TIMING_KEY, MatchController.YINLANG_CONTROL_SEPARATOR, effect_key]
	if not _submit_control(control_id, true):
		return _fail("compose_submit_rejected pool=%s" % pool_kind)
	return true


## 取一个效果池里的首个效果键；池为空时返回空字符串。
func _first_effect_key(pool_kind: String) -> String:
	for entry_variant: Variant in ZhuruComposePools.get_effects(pool_kind):
		return str((entry_variant as Dictionary).get(ZhuruComposePools.KEY_FIELD, ""))
	return ""


## 按协议格式拼出以太造牌控制项；与控制器解析规则严格一致。
func _build_mint_control_id(card_name: String, suit: String, rank: int, definition_id: String) -> String:
	return "%s%s%s%s%s%d%s%s" % [MatchController.YINLANG_MINT_CONTROL_PREFIX, card_name, MatchController.YINLANG_CONTROL_SEPARATOR, suit, MatchController.YINLANG_CONTROL_SEPARATOR, rank, MatchController.YINLANG_CONTROL_SEPARATOR, definition_id]


## 记录首个失败原因并以1结束测试进程；返回false便于调用方立即退出。
func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	printerr("YINLANG_MECHANICS_FAIL %s" % message)
	get_tree().quit(1)
	return false
