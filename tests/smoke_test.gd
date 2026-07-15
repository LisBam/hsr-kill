extends Node

## 无界面烟雾测试：校验数据规模，并让四名基础 AI 通过统一动作入口运行若干帧。

## 主战斗场景；测试从其内置卡牌模板复制手牌，并验证桌面节点结构。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 可编辑武将牌场景；测试直接实例化正式资源，确保编辑器所见尺寸与游戏实例一致。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 游戏内座位容器场景；测试验证座次标签只在运行时容器中出现并位于武将牌正下方。
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")

## 正式卡牌场景；测试验证根节点是 Node2D 且保留111×148的3:4实体牌尺寸。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

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
	# 默认完整牌堆实体牌数量；官方规则集3.0身份局牌表包含【银月枪】与【木牛流马】，合计162张。
	var deck_count: int = GameDatabase.get_deck_cards("standard_162").size()
	if deck_count != 162:
		printerr("SMOKE_FAIL deck_count=%d" % deck_count)
		get_tree().quit(1)
		return
	# 卡牌定义数量；补齐【银月枪】后当前规则表应登记46种配置 ID。
	var definition_count: int = GameDatabase.cards.size()
	if definition_count != 46:
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
	# 群体牌行动顺序状态；使用者为三号位时，其他角色应从四号位开始并环形回到一、二号位。
	var target_order_state: GameState = GameState.new()
	for target_order_player_id: int in range(4):
		target_order_state.players.append(PlayerState.new(target_order_player_id, "玩家%d" % (target_order_player_id + 1)))
	# 群体牌规则服务；只读取测试状态，不执行卡牌效果。
	var target_order_rules: CardRuleService = CardRuleService.new(target_order_state)
	# 测试万箭齐发实体；目标模式来自正式卡牌配置。
	var target_order_card: CardInstance = CardInstance.new("wanjian", "heart", 1)
	# 规范化群体目标顺序；预期从三号位使用者的下家四号位开始环形排列。
	var normalized_target_order: Array[int] = target_order_rules.normalize_targets(2, target_order_card, [])
	if normalized_target_order != [3, 0, 1]:
		printerr("SMOKE_FAIL all_others_action_order=%s" % normalized_target_order)
		get_tree().quit(1)
		return
	# 测试铁索连环实体；用于校验手动多目标也会按当前回合角色起算的行动顺序重排。
	var manual_multi_target_card: CardInstance = CardInstance.new("tiesuo", "club", 10)
	# 规范后的手动多目标；使用者为三号位时，点击二、四号位应先结算四号位再结算二号位。
	var normalized_manual_target_order: Array[int] = target_order_rules.normalize_targets(2, manual_multi_target_card, [1, 3])
	if normalized_manual_target_order != [3, 1]:
		printerr("SMOKE_FAIL manual_multi_target_order=%s" % normalized_manual_target_order)
		get_tree().quit(1)
		return
	# 测试借刀杀人实体；其两个 ID 分别表示持刀者与被杀者，必须保留提交语义顺序。
	var borrow_sword_order_card: CardInstance = CardInstance.new("jiedao", "club", 12)
	if target_order_rules.normalize_targets(2, borrow_sword_order_card, [1, 3]) != [1, 3]:
		printerr("SMOKE_FAIL borrow_sword_target_semantics")
		get_tree().quit(1)
		return
	# 测试火攻实体；规则允许以包括使用者在内的任意一名有手牌角色为目标。
	var fire_attack_target_card: CardInstance = CardInstance.new("huogong", "heart", 2)
	# 使用者测试手牌；只用于满足【火攻】目标须有手牌的合法性条件。
	var fire_attack_actor_hand: CardInstance = CardInstance.new("shan", "heart", 2)
	target_order_state.players[2].hand.append(fire_attack_actor_hand)
	if not target_order_rules.list_legal_targets(2, fire_attack_target_card).has(2):
		printerr("SMOKE_FAIL fire_attack_self_target")
		get_tree().quit(1)
		return
	# 纯数据选将服务；验证主公先选、默认5张候选、其他玩家同时确认和完成前隐藏选择。
	var selection_service: CharacterSelectionService = CharacterSelectionService.new()
	# 测试选将随机源；固定种子保证候选断言可复现且不依赖系统时间。
	var selection_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	selection_rng.seed = 20260715
	# 测试玩家状态；0号主公先选，1号和2号代表随后同时选将的其他玩家。
	var selection_players: Array[PlayerState] = [PlayerState.new(0, "主公"), PlayerState.new(1, "玩家二"), PlayerState.new(2, "玩家三")]
	selection_players[0].identity = "lord"
	selection_players[1].identity = "loyalist"
	selection_players[2].identity = "rebel"
	# 测试武将 ID 数组；使用正式数据库全部武将，候选数量应恰好为默认5张且单列表不重复。
	var selection_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		selection_character_ids.append(str(character_id_variant))
	if not selection_service.begin(selection_players, selection_character_ids, 5, selection_rng).is_empty():
		printerr("SMOKE_FAIL character_selection_begin")
		get_tree().quit(1)
		return
	var lord_candidates: Array[String] = selection_service.get_candidates(0)
	if selection_service.phase != CharacterSelectionService.PHASE_LORD or lord_candidates.size() != 5 or selection_service.can_player_select(1):
		printerr("SMOKE_FAIL character_selection_lord_phase")
		get_tree().quit(1)
		return
	# 主公确认候选首项后立即进入其他玩家同时选将阶段，并在所有观察者快照中公开主公武将。
	var selected_lord_character_id: String = lord_candidates[0]
	if not selection_service.select_character(0, selected_lord_character_id).is_empty() or selection_service.phase != CharacterSelectionService.PHASE_OTHERS or str(selection_service.to_dict(2).get("lord_character_id", "")) != selected_lord_character_id:
		printerr("SMOKE_FAIL character_selection_lord_reveal")
		get_tree().quit(1)
		return
	# 玩家二确认后，玩家三只能看到完成状态而不能看到玩家二具体选择；全员完成前阶段不得结束。
	var player_two_choice: String = selection_service.get_candidates(1)[0]
	selection_service.select_character(1, player_two_choice)
	var player_three_snapshot: Dictionary = selection_service.to_dict(2)
	if selection_service.phase != CharacterSelectionService.PHASE_OTHERS or player_three_snapshot.has("selections_by_player") or str(player_three_snapshot.get("local_selected_character_id", "")) == player_two_choice:
		printerr("SMOKE_FAIL character_selection_hidden_choices")
		get_tree().quit(1)
		return
	selection_service.select_character(2, selection_service.get_candidates(2)[0])
	if selection_service.phase != CharacterSelectionService.PHASE_COMPLETE:
		printerr("SMOKE_FAIL character_selection_complete")
		get_tree().quit(1)
		return
	# 无名杀式手牌布局组件；实例化用于保证全局类、导出参数和基础显示数值可被无头环境解析。
	var hand_layout: DecadeHandContainer = DecadeHandContainer.new()
	if hand_layout.card_size != Vector2(111.0, 148.0) or not is_equal_approx(hand_layout.minimum_visible_width, 64.0) or not is_equal_approx(hand_layout.selected_lift, 18.0):
		printerr("SMOKE_FAIL decade_hand_layout_defaults")
		get_tree().quit(1)
		return
	hand_layout.free()
	# 可编辑武将牌场景实例；根节点必须是 Node2D，固定牌面尺寸由 card_size 与子视觉节点共同表达。
	var player_card_template: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	# 入树前的静态预览体力圆点数量；场景应预置三绿一暗共4枚，正式运行后会按快照重建。
	var static_preview_health_pip_count: int = (player_card_template.get_node("HealthPips") as VBoxContainer).get_child_count()
	if player_card_template.get_class() != "Node2D" or player_card_template.card_size != Vector2(148.35, 197.8):
		printerr("SMOKE_FAIL player_card_node2d size=%s" % player_card_template.card_size)
		get_tree().quit(1)
		return
	player_card_template.visible = true
	get_tree().root.add_child(player_card_template)
	await get_tree().process_frame
	# 武将牌独立输入区域；必须覆盖完整牌面，保证 Node2D 根节点不依赖按钮继承处理点击与拖放。
	var player_card_input_area: PlayerTargetInputArea = player_card_template.get_node("InputArea") as PlayerTargetInputArea
	if player_card_template.card_size != Vector2(148.35, 197.8) or (player_card_template.get_node("CardBody") as Panel).size != Vector2(148.35, 197.8) or player_card_input_area.size != Vector2(148.35, 197.8):
		printerr("SMOKE_FAIL player_card_runtime_size=%s" % player_card_template.card_size)
		get_tree().quit(1)
		return
	# 编辑器武将牌预览；座次不属于牌面节点树，体力容器预置三绿一暗四枚圆点以呈现标准3/4体力。
	# 编辑器插画槽；原生尺寸为141.35×190.8像素，只扩展插画宽度以形成3:4武将牌。
	var preview_artwork: TextureRect = player_card_template.get_node("Artwork") as TextureRect
	# 编辑器武将名竖条；缩小至22像素宽，避免占据过多插画区域。
	var preview_character_name: Label = player_card_template.get_node("CharacterName") as Label
	# 编辑器势力徽记；缩小至26×26像素，保留识别所需的最小尺寸。
	var preview_faction_badge: Label = player_card_template.get_node("FactionBadge") as Label
	# 编辑器手牌角标；缩小至24×24像素，降低对插画左下角的遮挡。
	var preview_hand_count: Label = player_card_template.get_node("HandCount") as Label
	# 编辑器身份徽记；进入场景树后保持23×20像素，验证静态场景内的信息控件规格。
	var preview_identity_badge: Label = player_card_template.get_node("IdentityBadge") as Label
	# 编辑器体力列；移动到右下角并扩大为26×90像素，验证静态场景内的信息控件规格。
	var preview_health_column: VBoxContainer = player_card_template.get_node("HealthPips") as VBoxContainer
	if player_card_template.has_node("Seat") or static_preview_health_pip_count != 4 or not preview_artwork.position.is_equal_approx(Vector2(4.0, 4.0)) or not preview_artwork.size.is_equal_approx(Vector2(141.35, 190.8)) or not preview_character_name.size.is_equal_approx(Vector2(22.0, 86.0)) or not preview_faction_badge.size.is_equal_approx(Vector2(26.0, 26.0)) or not preview_hand_count.size.is_equal_approx(Vector2(24.0, 24.0)) or not preview_identity_badge.size.is_equal_approx(Vector2(23.0, 20.0)) or not preview_health_column.position.is_equal_approx(Vector2(120.35, 104.0)) or not preview_health_column.size.is_equal_approx(Vector2(26.0, 90.0)) or player_card_template.health_pip_font_size != 18 or player_card_template.health_pip_separation != -10 or preview_health_column.get_theme_constant("separation") != -10:
		printerr("SMOKE_FAIL player_card_scene_preview seat=%s static_pips=%d artwork_position=%s artwork=%s name=%s faction=%s hand=%s identity=%s health=%s" % [player_card_template.has_node("Seat"), static_preview_health_pip_count, preview_artwork.position, preview_artwork.size, preview_character_name.size, preview_faction_badge.size, preview_hand_count.size, preview_identity_badge.size, preview_health_column.size])
		get_tree().quit(1)
		return
	# 游戏内座位容器；座次标签必须位于武将牌下方，容器总高度额外包含18像素字体进入场景树后产生的26像素真实控件高度。
	var player_seat_slot: Control = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
	get_tree().root.add_child(player_seat_slot)
	await get_tree().process_frame
	# 运行时座次标签；应为座位容器的独立子节点，不能回流到武将牌场景。
	var runtime_seat: Label = player_seat_slot.get_node("Seat") as Label
	# 容器内复用的武将牌；尺寸必须继续保持统一的148.35×197.8像素规格。
	var runtime_player_card: PlayerTargetView = player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
	if player_seat_slot.size != Vector2(148.35, 223.8) or runtime_player_card.card_size != Vector2(148.35, 197.8) or runtime_seat.position != Vector2(0.0, 197.8) or runtime_seat.size != Vector2(148.35, 26.0) or runtime_seat.get_theme_font_size("font_size") != 18:
		printerr("SMOKE_FAIL player_seat_slot_layout slot=%s card=%s seat_position=%s seat_size=%s seat_font=%d" % [player_seat_slot.size, runtime_player_card.card_size, runtime_seat.position, runtime_seat.size, runtime_seat.get_theme_font_size("font_size")])
		get_tree().quit(1)
		return
	get_tree().root.remove_child(player_seat_slot)
	player_seat_slot.free()
	# 统一武将牌组件；直接使用场景实例，用于校验装备横条高度与五槽显示上限。
	var player_card_view: PlayerTargetView = player_card_template
	if not is_equal_approx(player_card_view.equipment_row_height, 15.0) or player_card_view.maximum_equipment_rows != 5:
		printerr("SMOKE_FAIL player_card_reference_layout_defaults")
		get_tree().quit(1)
		return
	# 武将牌固定尺寸；装备、名称和体力等内容只在正式牌面子节点中渲染，根节点保持 Node2D。
	if player_card_view.card_size != Vector2(148.35, 197.8) or (player_card_view.get_node("CardBody") as Panel).size != Vector2(148.35, 197.8):
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
	# 实际装备横条是否全部保持60×15像素；默认true，发现任意尺寸不符条目后改为false。
	var equipment_rows_keep_original_size: bool = true
	for child: Node in player_card_view.get_children():
		for grandchild: Node in child.get_children():
			if grandchild is RichTextLabel:
				rendered_equipment_row_count += 1
				if (grandchild as RichTextLabel).size != Vector2(60.0, 15.0):
					equipment_rows_keep_original_size = false
	if rendered_equipment_row_count != 2 or not equipment_rows_keep_original_size:
		printerr("SMOKE_FAIL player_card_equipment_rows=%d" % rendered_equipment_row_count)
		get_tree().quit(1)
		return
	get_tree().root.remove_child(player_card_view)
	player_card_view.free()
	# 主场景预览实例；只读取菜单与控制器默认参数，不进入场景树以避免启动正式对局。
	var main_scene_preview: Control = MAIN_SCENE.instantiate() as Control
	# 主场景对局控制器；直接运行场景时由该节点的导出默认值决定开局人数。
	var main_scene_match_controller: MatchController = main_scene_preview.get_node("MatchController") as MatchController
	if main_scene_match_controller.default_player_count != 8 or main_scene_match_controller.first_turn_seat_number != 1 or not main_scene_match_controller.randomize_local_human_seat or main_scene_match_controller.default_deck_id != "standard_162":
		printerr("SMOKE_FAIL default_player_count=%d" % main_scene_match_controller.default_player_count)
		get_tree().quit(1)
		return
	# 正式卡牌组件实例；验证根节点为 Node2D、牌面模型尺寸为111×148且不再继承按钮。
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 卡牌独立输入区域；场景静态尺寸必须与正式牌面一致，进入任意容器后都能保持完整命中范围。
	var card_input_area: CardInputArea = card_view.get_node("InputArea") as CardInputArea
	if card_view.get_class() != "Node2D" or not is_equal_approx(card_view.card_width, 111.0) or not is_equal_approx(card_view.card_height, 148.0) or card_view.get_card_size() != Vector2(111.0, 148.0) or card_input_area.size != Vector2(111.0, 148.0):
		printerr("SMOKE_FAIL card_view_node2d_defaults")
		get_tree().quit(1)
		return
	card_view.free()
	# 弃牌动画层；两张正式卡牌应同时从各自起点进入中央队列、保持水平铺开并在停留后全部淡出。
	var animation_layer: CardUseAnimationLayer = CardUseAnimationLayer.new()
	animation_layer.card_flight_duration = 0.01
	animation_layer.card_hold_duration = 0.08
	animation_layer.target_line_fade_duration = 0.04
	animation_layer.target_line_draw_duration = 0.02
	animation_layer.queue_reflow_duration = 0.01
	get_tree().root.add_child(animation_layer)
	# 第一张动画牌；模拟一名其他玩家从左侧座位使用卡牌。
	var first_animation_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 第二张动画牌；模拟另一名玩家在前一张牌消失前继续使用卡牌。
	var second_animation_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	animation_layer.add_child(first_animation_card)
	animation_layer.add_child(second_animation_card)
	first_animation_card.position = Vector2(80.0, 120.0)
	second_animation_card.position = Vector2(900.0, 120.0)
	animation_layer.play_card(first_animation_card, first_animation_card.position, Vector2(500.0, 300.0), [Vector2(800.0, 200.0)])
	animation_layer.play_card(second_animation_card, second_animation_card.position, Vector2(500.0, 300.0), [])
	# 第一条目标线表现数据；必须保存来源、目标和动态延伸进度，确保不是一次性绘制静态整线。
	var first_line_presentation: Dictionary = animation_layer._line_presentations.get(1, {}) as Dictionary
	if first_line_presentation.get("target_positions", []) != [Vector2(800.0, 200.0)] or not first_line_presentation.has("progress"):
		printerr("SMOKE_FAIL target_line_presentation=%s" % first_line_presentation)
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.04).timeout
	if first_animation_card.rotation != 0.0 or second_animation_card.rotation != 0.0 or is_equal_approx(first_animation_card.position.x, second_animation_card.position.x):
		printerr("SMOKE_FAIL discard_animation_queue")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.04).timeout
	if animation_layer._line_presentations.has(1):
		printerr("SMOKE_FAIL target_line_fade_after_draw")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.3).timeout
	if animation_layer.get_child_count() != 0:
		printerr("SMOKE_FAIL discard_animation_cleanup=%d" % animation_layer.get_child_count())
		get_tree().quit(1)
		return
	get_tree().root.remove_child(animation_layer)
	animation_layer.free()
	# 右上角菜单组件；替代独立牌名和重开按钮，并默认保存8人作为下一局配置。
	var menu_button: Button = main_scene_preview.get_node("%MenuButton") as Button
	if menu_button.text != "菜单" or main_scene_preview.has_node("%NameModeButton") or main_scene_preview.has_node("%RestartButton"):
		printerr("SMOKE_FAIL match_menu_structure")
		get_tree().quit(1)
		return
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
	# 随机座次样本；多个固定种子应产生不同的本地座次与主公座次，且至少一局本地玩家不是主公。
	var observed_local_seats: Dictionary = {}
	# 随机主公座次样本；键为座次 ID，用于验证主公不固定于一号位。
	var observed_lord_seats: Dictionary = {}
	# 是否观察到本地玩家不为主公；默认 false，样本中出现后置为 true。
	var observed_non_lord_local_player: bool = false
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = true
	for random_seed: int in range(20260701, 20260717):
		if not _controller.start_match(8, random_seed):
			printerr("SMOKE_FAIL randomized_start seed=%d" % random_seed)
			get_tree().quit(1)
			return
		# 当前种子分配的本地座次；每局可以不同，但固定种子的结果可复现。
		var randomized_local_seat: int = _controller.local_human_player_id
		# 当前种子分配的主公；身份池整体洗牌后可位于任意座次。
		var randomized_lord: PlayerState = _controller._find_player_by_identity("lord")
		observed_local_seats[randomized_local_seat] = true
		observed_lord_seats[randomized_lord.player_id] = true
		if randomized_lord.player_id != randomized_local_seat:
			observed_non_lord_local_player = true
	if observed_local_seats.size() <= 1 or observed_lord_seats.size() <= 1 or observed_lord_seats.has(0) and observed_lord_seats.size() == 1 or not observed_non_lord_local_player:
		printerr("SMOKE_FAIL randomized_seats local=%s lord=%s non_lord_local=%s" % [observed_local_seats.keys(), observed_lord_seats.keys(), observed_non_lord_local_player])
		get_tree().quit(1)
		return
	# 无懈可击响应状态；三号位是当前回合角色，应比一号位更早响应同一有害锦囊。
	var negation_state: GameState = GameState.new()
	for negation_player_id: int in range(4):
		# 无懈响应测试玩家；目标与两名响应者同属主忠阵营。
		var negation_player: PlayerState = PlayerState.new(negation_player_id, "玩家%d" % (negation_player_id + 1))
		negation_player.identity = "lord" if negation_player_id == 1 else ("rebel" if negation_player_id == 3 else "loyalist")
		negation_state.players.append(negation_player)
	negation_state.current_player_id = 2
	# 一号位无懈可击；若仍从数组首项询问就会被错误消耗。
	var seat_one_counter: CardInstance = CardInstance.new("wuxie", "spade", 11)
	seat_one_counter.zone = "hand"
	seat_one_counter.owner_id = 0
	negation_state.players[0].hand.append(seat_one_counter)
	# 三号位无懈可击；当前回合角色应首先消耗该牌。
	var seat_three_counter: CardInstance = CardInstance.new("wuxie", "spade", 13)
	seat_three_counter.zone = "hand"
	seat_three_counter.owner_id = 2
	negation_state.players[2].hand.append(seat_three_counter)
	_controller.state = negation_state
	_controller.card_rules = CardRuleService.new(negation_state)
	if not _controller.resolve_trick_negation(3, 1, "guohe") or negation_state.players[2].hand.size() != 0 or negation_state.players[0].hand.size() != 1:
		printerr("SMOKE_FAIL negation_response_order seat1=%d seat3=%d" % [negation_state.players[0].hand.size(), negation_state.players[2].hand.size()])
		get_tree().quit(1)
		return
	# 连环传导测试状态；当前回合为三号位，初始受伤目标为二号位，其余横置角色应按三、四、一的顺序传导。
	var chain_order_state: GameState = GameState.new()
	for chain_player_id: int in range(4):
		# 连环传导玩家；全部初始为4点体力且处于横置状态。
		var chain_player: PlayerState = PlayerState.new(chain_player_id, "玩家%d" % (chain_player_id + 1))
		chain_player.chained = true
		chain_order_state.players.append(chain_player)
	chain_order_state.current_player_id = 2
	# 伤害后目标顺序；事件回调同步记录初始伤害与后续传导的实际结算次序。
	var chain_damage_order: Array[int] = []
	# 连环顺序监听者；仅在本次同步伤害结算期间保持有效。
	var chain_listener: RefCounted = RefCounted.new()
	_controller.event_bus.subscribe("damage_after", chain_listener, func(event: RuleEvent) -> void: chain_damage_order.append(event.target_id))
	_controller.state = chain_order_state
	_controller.card_rules = CardRuleService.new(chain_order_state)
	_controller.damage(2, 1, 1, "fire", "sha_fire")
	_controller.event_bus.unsubscribe_owner(chain_listener)
	if chain_damage_order != [1, 2, 3, 0]:
		printerr("SMOKE_FAIL chain_damage_order=%s" % chain_damage_order)
		get_tree().quit(1)
		return
	# 银月枪测试状态；回合外打出黑色手牌后，无【闪】的范围内敌方应受到1点伤害。
	var silver_moon_state: GameState = GameState.new()
	for silver_player_id: int in range(3):
		# 银月枪测试玩家；一号位反贼持有武器，二号位主公作为优先敌方。
		var silver_player: PlayerState = PlayerState.new(silver_player_id, "玩家%d" % (silver_player_id + 1))
		silver_player.identity = "rebel" if silver_player_id != 1 else "lord"
		silver_moon_state.players.append(silver_player)
	silver_moon_state.current_player_id = 2
	# 银月枪实体牌；位于一号位武器槽并提供3点攻击范围。
	var silver_moon_weapon: CardInstance = CardInstance.new("yinyue", "diamond", 12)
	silver_moon_weapon.zone = "equipment"
	silver_moon_weapon.owner_id = 0
	silver_moon_state.players[0].equipment["weapon"] = silver_moon_weapon
	# 触发用黑色手牌；模拟已在回合外打出并移入弃牌堆的【无懈可击】。
	var silver_trigger_card: CardInstance = CardInstance.new("wuxie", "spade", 11)
	silver_trigger_card.zone = "discard_pile"
	silver_moon_state.discard_pile.append(silver_trigger_card)
	_controller.state = silver_moon_state
	_controller.card_rules = CardRuleService.new(silver_moon_state)
	_controller._resolve_silver_moon_trigger(0, silver_trigger_card, true)
	if silver_moon_state.players[1].hp != 3:
		printerr("SMOKE_FAIL silver_moon_damage hp=%d" % silver_moon_state.players[1].hp)
		get_tree().quit(1)
		return
	# 当前回合死亡状态；二号位反贼在自己回合对自己使用【火攻】死亡，仍有另一名反贼使对局继续。
	var current_death_state: GameState = GameState.new()
	for death_player_id: int in range(4):
		# 当前回合死亡测试玩家；身份依次为主公、反贼、反贼与忠臣。
		var death_player: PlayerState = PlayerState.new(death_player_id, "玩家%d" % (death_player_id + 1))
		death_player.identity = ["lord", "rebel", "rebel", "loyalist"][death_player_id]
		current_death_state.players.append(death_player)
	current_death_state.current_player_id = 1
	current_death_state.current_phase = "play"
	current_death_state.turn_number = 1
	current_death_state.players[1].hp = 1
	# 自伤火攻实体牌；作为当前行为从手牌进入处理区。
	var self_fire_attack: CardInstance = CardInstance.new("huogong", "heart", 2)
	self_fire_attack.zone = "hand"
	self_fire_attack.owner_id = 1
	current_death_state.players[1].hand.append(self_fire_attack)
	# 火攻同花色手牌；目标展示后由同一玩家弃置，对自己造成1点火焰伤害。
	var self_fire_cost: CardInstance = CardInstance.new("shan", "heart", 3)
	self_fire_cost.zone = "hand"
	self_fire_cost.owner_id = 1
	current_death_state.players[1].hand.append(self_fire_cost)
	_controller.state = current_death_state
	_controller.card_rules = CardRuleService.new(current_death_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, current_death_state)
	if not _controller.submit_action(PlayerAction.new("use_card", 1, self_fire_attack.uid, [1])) or current_death_state.players[1].alive or current_death_state.current_player_id != 2 or current_death_state.current_phase != "play" or current_death_state.turn_number != 2:
		printerr("SMOKE_FAIL current_player_death alive=%s current=%d phase=%s turn=%d" % [current_death_state.players[1].alive, current_death_state.current_player_id, current_death_state.current_phase, current_death_state.turn_number])
		get_tree().quit(1)
		return
	# 胜负结束死亡状态；最后一名反贼亮出身份后立即满足主忠胜利条件。
	var terminal_death_state: GameState = GameState.new()
	# 终局主公；保持存活以使最后反贼死亡后判定主忠胜利。
	var terminal_lord: PlayerState = PlayerState.new(0, "主公")
	terminal_lord.identity = "lord"
	terminal_death_state.players.append(terminal_lord)
	# 终局反贼；携带1张手牌，用于确认胜负条件在死亡弃牌之前立即终止结算。
	var terminal_rebel: PlayerState = PlayerState.new(1, "反贼")
	terminal_rebel.identity = "rebel"
	terminal_rebel.hp = 0
	var terminal_rebel_card: CardInstance = CardInstance.new("shan", "heart", 2)
	terminal_rebel_card.zone = "hand"
	terminal_rebel_card.owner_id = 1
	terminal_rebel.hand.append(terminal_rebel_card)
	terminal_death_state.players.append(terminal_rebel)
	terminal_death_state.current_player_id = 0
	_controller.state = terminal_death_state
	_controller.card_rules = CardRuleService.new(terminal_death_state)
	_controller._resolve_death(1, 0)
	if not terminal_death_state.game_over or terminal_death_state.winner != "lord_and_loyalists" or terminal_rebel.hand.size() != 1:
		printerr("SMOKE_FAIL terminal_death winner=%s hand=%d" % [terminal_death_state.winner, terminal_rebel.hand.size()])
		get_tree().quit(1)
		return
	# 群体牌终局状态；首名目标死亡满足胜负条件后，必须终止后续目标与使用牌区域移动。
	var terminal_aoe_state: GameState = GameState.new()
	for terminal_aoe_player_id: int in range(3):
		# 群体牌终局玩家；身份依次为主公、最后一名反贼与忠臣。
		var terminal_aoe_player: PlayerState = PlayerState.new(terminal_aoe_player_id, "玩家%d" % (terminal_aoe_player_id + 1))
		terminal_aoe_player.identity = ["lord", "rebel", "loyalist"][terminal_aoe_player_id]
		terminal_aoe_state.players.append(terminal_aoe_player)
	terminal_aoe_state.current_player_id = 0
	terminal_aoe_state.current_phase = "play"
	terminal_aoe_state.players[1].hp = 1
	# 终局测试万箭齐发；规则顺序先处理二号位反贼，再处理三号位忠臣。
	var terminal_aoe_card: CardInstance = CardInstance.new("wanjian", "heart", 1)
	terminal_aoe_card.zone = "hand"
	terminal_aoe_card.owner_id = 0
	terminal_aoe_state.players[0].hand.append(terminal_aoe_card)
	_controller.state = terminal_aoe_state
	_controller.card_rules = CardRuleService.new(terminal_aoe_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, terminal_aoe_state)
	if not _controller.submit_action(PlayerAction.new("use_card", 0, terminal_aoe_card.uid, [])) or not terminal_aoe_state.game_over or terminal_aoe_state.players[2].hp != 4 or not terminal_aoe_state.processing_area.has(terminal_aoe_card) or terminal_aoe_state.discard_pile.has(terminal_aoe_card):
		printerr("SMOKE_FAIL terminal_aoe winner=%s later_hp=%d processing=%s discard=%s" % [terminal_aoe_state.winner, terminal_aoe_state.players[2].hp, terminal_aoe_state.processing_area.has(terminal_aoe_card), terminal_aoe_state.discard_pile.has(terminal_aoe_card)])
		get_tree().quit(1)
		return
	# 判定阶段死亡状态；当前角色被闪电击杀但仍有同阵营角色存活，对局应转交给其下名存活角色。
	var judgment_death_state: GameState = GameState.new()
	for judgment_death_player_id: int in range(4):
		# 判定死亡测试玩家；身份依次为主公、当前反贼、另一名反贼与忠臣。
		var judgment_death_player: PlayerState = PlayerState.new(judgment_death_player_id, "玩家%d" % (judgment_death_player_id + 1))
		judgment_death_player.identity = ["lord", "rebel", "rebel", "loyalist"][judgment_death_player_id]
		judgment_death_state.players.append(judgment_death_player)
	judgment_death_state.players[1].hp = 1
	# 待结算闪电；进入二号位判定区，命中后造成3点无来源雷电伤害。
	var pending_lightning: CardInstance = CardInstance.new("shandian", "spade", 1)
	pending_lightning.zone = "judgment"
	pending_lightning.owner_id = 1
	judgment_death_state.players[1].judgment_area.append(pending_lightning)
	# 闪电判定牌；牌堆末尾为顶部，黑桃2保证本次判定命中。
	var lightning_judgment: CardInstance = CardInstance.new("shan", "spade", 2)
	lightning_judgment.zone = "draw_pile"
	judgment_death_state.draw_pile.append(lightning_judgment)
	_controller.ai_coordinator._policies.clear()
	_controller.state = judgment_death_state
	_controller.card_rules = CardRuleService.new(judgment_death_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, judgment_death_state)
	_controller._start_turn(1)
	if judgment_death_state.game_over or judgment_death_state.players[1].alive or judgment_death_state.current_player_id != 2 or judgment_death_state.current_phase != "play" or judgment_death_state.turn_number != 2:
		printerr("SMOKE_FAIL judgment_turn_transfer game_over=%s alive=%s current=%d phase=%s turn=%d" % [judgment_death_state.game_over, judgment_death_state.players[1].alive, judgment_death_state.current_player_id, judgment_death_state.current_phase, judgment_death_state.turn_number])
		get_tree().quit(1)
		return
	# 纯 AI 四人局；主公座次随机，完成选将后应立即成为首回合角色且不获得小于5人局的体力加值。
	_controller.local_human_player_id = -1
	if not _controller.start_match(4, 20260714):
		printerr("SMOKE_FAIL start_match")
		get_tree().quit(1)
		return
	# 四人局主公；用于同时校验随机座次首回合和小人数体力上限。
	var four_player_lord: PlayerState = _controller._find_player_by_identity("lord")
	# 四人局主公武将基础体力；应与实际上限完全一致。
	var four_player_lord_base_hp: int = int(GameDatabase.get_character(four_player_lord.character_id).get("max_hp", 4))
	if _controller.state.current_player_id != four_player_lord.player_id or _controller.state.turn_number != 1 or four_player_lord.max_hp != four_player_lord_base_hp:
		printerr("SMOKE_FAIL first_turn seat=%d turn=%d" % [_controller.state.current_player_id + 1, _controller.state.turn_number])
		get_tree().quit(1)
		return
	# 纯 AI 五人局；规则集规定从五人起主公的体力上限才增加1点。
	if not _controller.start_match(5, 20260715):
		printerr("SMOKE_FAIL five_player_start")
		get_tree().quit(1)
		return
	# 五人局主公；用于校验不少于5人时的唯一体力加值。
	var five_player_lord: PlayerState = _controller._find_player_by_identity("lord")
	# 五人局主公武将基础体力；实际上限应比该值高1点。
	var five_player_lord_base_hp: int = int(GameDatabase.get_character(five_player_lord.character_id).get("max_hp", 4))
	if _controller.state.current_player_id != five_player_lord.player_id or five_player_lord.max_hp != five_player_lord_base_hp + 1:
		printerr("SMOKE_FAIL lord_hp_bonus seat=%d hp=%d base=%d" % [five_player_lord.player_id + 1, five_player_lord.max_hp, five_player_lord_base_hp])
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
