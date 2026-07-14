extends Node

## 无界面烟雾测试：校验数据规模，并让四名基础 AI 通过统一动作入口运行若干帧。

## 烟雾测试最多等待的进程帧数；达到上限仍未发现运行时错误也会输出阶段状态。
const MAX_FRAMES: int = 1200

## 测试用对局控制器；在 _initialize 中按正式场景的组件结构装配。
var _controller: MatchController


## 创建纯 AI 对局并开始异步帧检查。
func _ready() -> void:
	call_deferred("_run")


## 执行数据断言和纯 AI 对局烟雾测试。
func _run() -> void:
	await get_tree().process_frame
	# 数据校验错误；任何非空结果都说明配置不能安全开局。
	var validation_errors: Array[String] = GameDatabase.validation_errors
	if not validation_errors.is_empty():
		printerr("SMOKE_FAIL data_validation: %s" % "；".join(validation_errors))
		get_tree().quit(1)
		return
	# 默认完整牌堆实体牌数量；标准与EX 108张加完整军争53张应为161。
	var deck_count: int = GameDatabase.get_deck_cards("standard_161").size()
	if deck_count != 161:
		printerr("SMOKE_FAIL deck_count=%d" % deck_count)
		get_tree().quit(1)
		return
	# 卡牌定义数量；当前规则表应完整登记45种配置 ID。
	var definition_count: int = GameDatabase.cards.size()
	if definition_count != 45:
		printerr("SMOKE_FAIL card_definitions=%d" % definition_count)
		get_tree().quit(1)
		return
	# 技能元数据数量；当前八名样例武将各登记一个用于技能 UI 预留的技能。
	var skill_definition_count: int = GameDatabase.skills.size()
	if skill_definition_count != 8:
		printerr("SMOKE_FAIL skill_definitions=%d" % skill_definition_count)
		get_tree().quit(1)
		return
	# 【酒】正常使用目标模式；官方规则允许指定包括使用者在内的一名角色。
	if str(GameDatabase.get_card("jiu").get("target_mode", "")) != "any_player":
		printerr("SMOKE_FAIL wine_target_mode")
		get_tree().quit(1)
		return
	# 丈八蛇矛生成的多实体虚拟【杀】应为无色，不能错误触发仁王盾的黑色【杀】条件。
	var colorless_virtual_slash: CardInstance = CardInstance.new("sha", "none", 0)
	if colorless_virtual_slash.get_color() != "none":
		printerr("SMOKE_FAIL virtual_slash_color=%s" % colorless_virtual_slash.get_color())
		get_tree().quit(1)
		return
	# 当前效果执行器支持的效果 ID 集合；配置中的每种牌必须映射到其中一项。
	var supported_effects: Array[String] = ["slash", "dodge", "peach", "wine", "discard_target", "steal_target", "duel", "borrow_sword", "draw_two", "negate", "aoe_dodge", "aoe_slash", "heal_all", "harvest", "lightning", "skip_play", "chain", "fire_attack", "skip_draw", "flood", "equip"]
	for card_id_variant: Variant in GameDatabase.cards.keys():
		# 当前卡牌 ID；用于生成精确的失败信息。
		var card_id: String = str(card_id_variant)
		# 当前卡牌定义；双名称与效果 ID 都必须完整。
		var definition: Dictionary = GameDatabase.get_card(card_id)
		if str(definition.get("original_name", "")).is_empty() or str(definition.get("custom_name", "")).is_empty():
			printerr("SMOKE_FAIL missing_dual_name=%s" % card_id)
			get_tree().quit(1)
			return
		if not supported_effects.has(str(definition.get("effect_id", ""))):
			printerr("SMOKE_FAIL unsupported_effect=%s:%s" % [card_id, definition.get("effect_id", "")])
			get_tree().quit(1)
			return
	# 八人身份分配数量；用于校验标准配置仍为1主2忠4反1内。
	var eight_player_identities: Array[String] = IdentityRules.new().get_distribution(8)
	if eight_player_identities.count("lord") != 1 or eight_player_identities.count("loyalist") != 2 or eight_player_identities.count("rebel") != 4 or eight_player_identities.count("renegade") != 1:
		printerr("SMOKE_FAIL identity_distribution_8")
		get_tree().quit(1)
		return
	# 无名杀式手牌布局组件；实例化用于保证全局类、导出参数和基础显示数值可被无头环境解析。
	var hand_layout: DecadeHandContainer = DecadeHandContainer.new()
	if hand_layout.card_size != Vector2(108.0, 148.0) or not is_equal_approx(hand_layout.minimum_visible_width, 64.0) or not is_equal_approx(hand_layout.selected_lift, 18.0):
		printerr("SMOKE_FAIL decade_hand_layout_defaults")
		get_tree().quit(1)
		return
	# 无名杀式座次布局组件；实例化用于校验常规与紧凑武将牌尺寸保持文档约定。
	var battle_layout: DecadeBattleLayout = DecadeBattleLayout.new()
	if battle_layout.opponent_card_size != Vector2(118.0, 172.0) or battle_layout.compact_opponent_card_size != Vector2(104.0, 156.0):
		printerr("SMOKE_FAIL decade_battle_layout_defaults")
		get_tree().quit(1)
		return

	_controller = MatchController.new()
	_controller.name = "MatchController"
	_controller.local_human_player_id = -1
	_controller.ai_action_delay_seconds = 0.0
	# 测试规则事件总线；节点名必须与正式控制器的组件约定一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# 测试 AI 调度组件；四名玩家均会登记基础策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 测试通信网关；保持离线模式，不接入外部网络。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	get_tree().root.add_child(_controller)
	await get_tree().process_frame
	if not _controller.start_match(4, 20260714):
		printerr("SMOKE_FAIL start_match")
		get_tree().quit(1)
		return

	for frame_index: int in range(MAX_FRAMES):
		await get_tree().process_frame
		if _controller.state.game_over:
			print("SMOKE_PASS game_over winner=%s actions=%d frames=%d" % [_controller.state.winner, _controller.state.action_sequence, frame_index])
			get_tree().quit(0)
			return
	print("SMOKE_PASS running phase=%s turn=%d actions=%d" % [_controller.state.current_phase, _controller.state.turn_number, _controller.state.action_sequence])
	get_tree().quit(0)
