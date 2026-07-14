extends Node

## 无界面烟雾测试：校验数据规模，并让四名基础 AI 通过统一动作入口运行若干帧。

## 主战斗场景；测试从其内置卡牌模板复制手牌，并验证桌面节点结构。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 可编辑武将牌场景；测试直接实例化正式资源，确保编辑器所见尺寸与游戏实例一致。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 游戏内座位容器场景；测试验证座次标签只在运行时容器中出现并位于武将牌正下方。
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")

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
	# 势力展示元数据数量；当前八名样例武将共使用四个独立势力主题。
	var faction_definition_count: int = GameDatabase.factions.size()
	if faction_definition_count != 4:
		printerr("SMOKE_FAIL faction_definitions=%d" % faction_definition_count)
		get_tree().quit(1)
		return
	# 已登记武将的中文显示名；界面显示不得退化为内部英文 ID。
	var trailblazer_display_name: String = GameDatabase.resolve_character_name("trailblazer")
	if trailblazer_display_name != "开拓者":
		printerr("SMOKE_FAIL character_display_name=%s" % trailblazer_display_name)
		get_tree().quit(1)
		return
	# 未登记武将的显示回退；必须保留中文占位且不泄漏调用方传入的英文稳定 ID。
	var unknown_character_display_name: String = GameDatabase.resolve_character_name("unknown_character")
	if unknown_character_display_name != "未知武将":
		printerr("SMOKE_FAIL unknown_character_display_name=%s" % unknown_character_display_name)
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
	hand_layout.free()
	# 无名杀式座次布局组件；实例化用于校验所有座次统一使用文档约定的固定武将牌尺寸。
	var battle_layout: DecadeBattleLayout = DecadeBattleLayout.new()
	if DecadeBattleLayout.UNIFIED_PLAYER_CARD_SIZE != Vector2(118.0, 172.0) or not is_equal_approx(DecadeBattleLayout.PLAYER_SEAT_LABEL_HEIGHT, 18.0) or DecadeBattleLayout.PLAYER_SEAT_SLOT_SIZE != Vector2(118.0, 190.0):
		printerr("SMOKE_FAIL decade_battle_layout_defaults")
		get_tree().quit(1)
		return
	battle_layout.free()
	# 可编辑武将牌场景实例；场景默认尺寸必须与常规对手武将牌一致，避免编辑器与对局牌面尺寸脱节。
	var player_card_template: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	if player_card_template.custom_minimum_size != Vector2(118.0, 172.0) or player_card_template.size != Vector2(118.0, 172.0) or not is_equal_approx(player_card_template.panel_width, 118.0) or not is_equal_approx(player_card_template.panel_height, 172.0):
		printerr("SMOKE_FAIL player_card_template_size")
		get_tree().quit(1)
		return
	# 编辑器武将牌预览；座次不属于牌面节点树，体力容器预置三绿一暗四枚圆点以呈现标准3/4体力。
	var preview_health_pips: VBoxContainer = player_card_template.get_node("HealthPips") as VBoxContainer
	if player_card_template.has_node("Seat") or preview_health_pips.get_child_count() != 4:
		printerr("SMOKE_FAIL player_card_scene_preview")
		get_tree().quit(1)
		return
	# 游戏内座位容器；座次标签必须位于武将牌下方，容器总高度仅额外增加18像素。
	var player_seat_slot: Control = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
	# 运行时座次标签；应为座位容器的独立子节点，不能回流到武将牌场景。
	var runtime_seat: Label = player_seat_slot.get_node("Seat") as Label
	# 容器内复用的武将牌；尺寸必须继续保持统一的118×172像素规格。
	var runtime_player_card: PlayerTargetView = player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
	if player_seat_slot.size != Vector2(118.0, 190.0) or runtime_player_card.size != Vector2(118.0, 172.0) or runtime_seat.position != Vector2(0.0, 172.0) or runtime_seat.size != Vector2(118.0, 18.0):
		printerr("SMOKE_FAIL player_seat_slot_layout")
		get_tree().quit(1)
		return
	player_seat_slot.free()
	# 统一武将牌组件；直接使用场景实例，用于校验装备横条高度与五槽显示上限。
	var player_card_view: PlayerTargetView = player_card_template
	if not is_equal_approx(player_card_view.equipment_row_height, 18.0) or player_card_view.maximum_equipment_rows != 5:
		printerr("SMOKE_FAIL player_card_reference_layout_defaults")
		get_tree().quit(1)
		return
	player_card_view.apply_panel_size(Vector2(118.0, 172.0))
	player_card_view.visible = true
	player_card_view.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().root.add_child(player_card_view)
	await get_tree().process_frame
	# 武将牌固定尺寸；装备、名称和体力等内容只能在牌面内裁切，不能反向撑大角色卡。
	if player_card_view.size != Vector2(118.0, 172.0) or player_card_view.custom_minimum_size != Vector2(118.0, 172.0) or not player_card_view.clip_contents:
		printerr("SMOKE_FAIL player_card_fixed_size")
		get_tree().quit(1)
		return
	# 带装备的角色牌测试快照；两件公开装备分别覆盖武器与防具槽，用于验证横条实际生成数量。
	var equipped_player_snapshot: Dictionary = {
		"player_id":1,
		"display_name":"测试玩家",
		"character_id":"trailblazer",
		"identity":"rebel",
		"hp":3,
		"max_hp":4,
		"alive":true,
		"chained":false,
		"hand_count":4,
		"equipment":{
			"weapon":{"definition_id":"qinglong", "suit":"spade", "rank":5},
			"armor":{"definition_id":"bagua", "suit":"spade", "rank":2},
		},
		"judgment_area":[],
		"wooden_ox_storage_count":0,
	}
	# 测试武将定义；提供武将名和势力 ID，使统一牌面能够生成完整覆盖层。
	var equipped_character_definition: Dictionary = GameDatabase.get_character("trailblazer")
	# 测试势力定义；提供圆徽简称与主题颜色，验证数据驱动入口可正常传递。
	var equipped_faction_definition: Dictionary = GameDatabase.get_faction(str(equipped_character_definition.get("faction", "")))
	player_card_view.configure_snapshot(equipped_player_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 实际装备横条数量；装备承载层是角色牌的直接子节点，其富文本子节点一一对应公开装备。
	var rendered_equipment_row_count: int = 0
	for child: Node in player_card_view.get_children():
		for grandchild: Node in child.get_children():
			if grandchild is RichTextLabel:
				rendered_equipment_row_count += 1
	if rendered_equipment_row_count != 2:
		printerr("SMOKE_FAIL player_card_equipment_rows=%d" % rendered_equipment_row_count)
		get_tree().quit(1)
		return
	get_tree().root.remove_child(player_card_view)
	player_card_view.free()
	# 主场景预览实例；只读取内置卡牌模板，不进入场景树以避免启动正式对局。
	var main_scene_preview: Control = MAIN_SCENE.instantiate() as Control
	# 内置卡牌模板；手牌与木牛“粮”均从主场景中该节点复制。
	var card_template: CardView = main_scene_preview.get_node("CardTemplate") as CardView
	# 卡牌组件实例；验证主场景内置模板可以复制并保留标准尺寸参数。
	var card_view: CardView = card_template.duplicate() as CardView
	if not is_equal_approx(card_view.card_width, 108.0) or not is_equal_approx(card_view.card_height, 148.0) or card_view.custom_minimum_size != Vector2(108.0, 148.0):
		printerr("SMOKE_FAIL card_template_defaults")
		get_tree().quit(1)
		return
	card_view.free()
	main_scene_preview.free()
	# 逻辑视口宽度；保持1280像素作为全部场景坐标和布局文档的统一设计基准。
	var viewport_width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	# 逻辑视口高度；保持720像素以维持十周年牌桌的16:9布局比例。
	var viewport_height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	# 默认启动窗口宽度；使用1152像素为系统窗口边框预留屏幕空间，同时由画布拉伸保持完整界面。
	var initial_window_width: int = int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	# 默认启动窗口高度；使用648像素避免720高屏幕上的标题栏和任务栏把底部界面推到屏幕外。
	var initial_window_height: int = int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	# 画布拉伸宽高比策略；固定为keep以保证非16:9窗口完整显示逻辑视口而不是裁切底部或右侧内容。
	var stretch_aspect: String = str(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	if viewport_width != 1280 or viewport_height != 720 or initial_window_width != 1152 or initial_window_height != 648 or stretch_aspect != "keep":
		printerr("SMOKE_FAIL safe_window_size viewport=%dx%d window=%dx%d aspect=%s" % [viewport_width, viewport_height, initial_window_width, initial_window_height, stretch_aspect])
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
