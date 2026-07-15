extends Node

## 局内界面布局与鼠标命中回归测试。测试使用正式主场景，验证边缘按钮和底部区域在默认窗口内完整可见。

## 主场景完成自动开局和动态节点构建前等待的帧数；默认6帧覆盖延迟开局、快照渲染与容器排序。
const SETTLE_FRAME_COUNT: int = 6

## 模拟未应用画布拉伸时的客户区尺寸；1152×648与项目默认启动窗口一致，用于复现固定1280×720坐标越界问题。
const COMPACT_CLIENT_SIZE: Vector2 = Vector2(1152.0, 648.0)

## 菜单按钮是否通过真实视口输入收到点击；默认 false，按钮信号触发后改为 true。
var _menu_button_pressed: bool = false


## 延迟执行正式场景检查，保证测试根节点已经进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 检查默认窗口中的可视范围、按钮鼠标命中与底部安全区。
func _run() -> void:
	# 正式主场景资源；测试必须覆盖与玩家运行完全相同的节点结构和脚本连接。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；作为测试根节点子节点运行完整界面初始化流程。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	# 正式对局控制器；先使用非法的1人配置阻止规则对局和AI异步任务启动，随后以五号位作为本地玩家注入只读十人界面快照。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	match_controller.default_player_count = 1
	match_controller.local_human_player_id = 4
	match_controller.randomize_local_human_seat = false
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	match_controller.state_changed.emit(_make_ten_player_snapshot())
	await get_tree().process_frame
	await get_tree().process_frame
	main_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_instance.position = Vector2.ZERO
	main_instance.size = COMPACT_CLIENT_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	# 当前模拟客户区矩形；直接使用主场景尺寸，覆盖编辑器嵌入运行未应用画布拉伸的情况。
	var viewport_rect: Rect2 = Rect2(main_instance.position, main_instance.size)
	# 右上角菜单按钮；必须完整位于视口内并能通过真实鼠标事件收到 pressed 信号。
	var menu_button: Button = main_instance.get_node("%MenuButton") as Button
	# 底部装备面板；左下区域必须完整位于窗口客户区内。
	var equipment_panel: Control = main_instance.get_node("%EquipmentPanel") as Control
	# 底部手牌面板；其底边必须随窗口底部锚定，不能继续停留在固定720坐标。
	var hand_panel: Control = main_instance.get_node("HandPanel") as Control
	# 底部技能栏；右侧区域必须完整位于本地武将牌左侧并保持可见。
	var skill_bar: Control = main_instance.get_node("SkillBar") as Control
	# 本地玩家座位容器；右下角区域必须使用右下锚点完整留在客户区内，并承载牌面下方的独立座次标签。
	var local_player_seat_slot: Control = main_instance.get_node("LocalPlayerSeatSlot") as Control
	for checked_control: Control in [menu_button, equipment_panel, hand_panel, skill_bar, local_player_seat_slot]:
		# 当前控件的屏幕矩形；`get_screen_transform()` 已包含画布拉伸和锚点换算。
		var screen_rect: Rect2 = _screen_rect(checked_control)
		if not viewport_rect.encloses(screen_rect):
			_fail("control_outside:%s:%s viewport=%s" % [checked_control.name, screen_rect, viewport_rect])
			return
	# 底部区域屏幕矩形；装备、手牌、技能和本地座位之间必须依次保留安全间隔。
	var bottom_layout_rects: Array[Rect2] = [_screen_rect(equipment_panel), _screen_rect(hand_panel), _screen_rect(skill_bar), _screen_rect(local_player_seat_slot)]
	for rect_index: int in range(bottom_layout_rects.size() - 1):
		# 当前相邻底部区域；只检查同层功能区，允许操作提示在牌桌中心使用独立纵向层级。
		var current_rect: Rect2 = bottom_layout_rects[rect_index]
		# 下一个相邻底部区域；排列顺序固定为从左到右，任何相交都说明安全边距未适配新牌宽。
		var next_rect: Rect2 = bottom_layout_rects[rect_index + 1]
		if current_rect.intersects(next_rect):
			_fail("bottom_controls_overlap:%s:%s" % [current_rect, next_rect])
			return
	# 本地完整座位屏幕尺寸；紧凑客户区未应用画布拉伸时仍应保持148.35×223.8像素规格。
	var local_seat_screen_rect: Rect2 = _screen_rect(local_player_seat_slot)
	if not local_seat_screen_rect.size.is_equal_approx(Vector2(148.35, 223.8)):
		_fail("local_seat_size:%s" % local_seat_screen_rect.size)
		return
	# 本地座次标签；测试把本地玩家设为五号位，底部牌面必须显示对应中文座次。
	var local_seat_label: Label = local_player_seat_slot.get_node("Seat") as Label
	if local_seat_label.text != "五":
		_fail("local_random_seat_label:%s" % local_seat_label.text)
		return
	# 本地装备区文本；测试快照中的木牛流马存有3张牌，数量必须紧跟装备名显示。
	var local_equipment_label: Label = main_instance.get_node("%EquipmentLabel") as Label
	if not local_equipment_label.text.contains("木牛流马（3）"):
		_fail("local_wooden_ox_count:%s" % local_equipment_label.text)
		return
	# 对手座位容器；十人局应创建9个对手座位，用于覆盖顶部五席和左右各两席的最拥挤布局。
	var opponent_seat_slots: Array[Control] = []
	# 全屏对手座次布局器；动态座位都是该容器的直接子节点。
	var player_grid: Control = main_instance.get_node("%PlayerGrid") as Control
	for player_grid_child: Node in player_grid.get_children():
		if player_grid_child is Control and player_grid_child.has_node("PlayerTargetView") and player_grid_child.has_node("Seat"):
			opponent_seat_slots.append(player_grid_child as Control)
	if opponent_seat_slots.size() != 9:
		_fail("opponent_seat_count:%d" % opponent_seat_slots.size())
		return
	# 桌面脚本保存的对手视图映射；插入顺序必须从本地五号位的下家六号位开始环形排列。
	var player_views: Dictionary = main_instance.get("_player_views") as Dictionary
	# 期望对手顺序；六至十号位之后绕回一至四号位。
	var expected_opponent_order: Array = [5, 6, 7, 8, 9, 0, 1, 2, 3]
	if player_views.keys() != expected_opponent_order:
		_fail("opponent_relative_order:%s" % [player_views.keys()])
		return
	# 已确认的对手座位屏幕矩形；逐个加入并检查相邻牌面不会重叠。
	var occupied_opponent_rects: Array[Rect2] = []
	for opponent_seat_slot: Control in opponent_seat_slots:
		# 当前对手座位屏幕矩形；必须完整留在紧凑客户区内。
		var opponent_screen_rect: Rect2 = _screen_rect(opponent_seat_slot)
		if not viewport_rect.encloses(opponent_screen_rect):
			_fail("opponent_outside:%s:%s" % [opponent_seat_slot.name, opponent_screen_rect])
			return
		for occupied_rect: Rect2 in occupied_opponent_rects:
			if opponent_screen_rect.intersects(occupied_rect):
				_fail("opponent_overlap:%s:%s" % [opponent_screen_rect, occupied_rect])
				return
		for bottom_rect: Rect2 in bottom_layout_rects:
			if opponent_screen_rect.intersects(bottom_rect):
				_fail("opponent_bottom_overlap:%s:%s" % [opponent_screen_rect, bottom_rect])
				return
			occupied_opponent_rects.append(opponent_screen_rect)
	# 卡牌使用动画层；必须位于对局操作和武将牌上方，但低于选将与菜单层。
	var animation_layer: CardUseAnimationLayer = main_instance.get_node("%CardUseAnimationLayer") as CardUseAnimationLayer
	if animation_layer.z_index != 30:
		_fail("animation_layer_z:%d" % animation_layer.z_index)
		return
	animation_layer.card_flight_duration = 0.01
	animation_layer.card_hold_duration = 0.01
	animation_layer.target_line_draw_duration = 0.01
	animation_layer.target_line_fade_duration = 0.01
	# 六号位武将牌；这是 Node2D 根节点，用于验证目标指示不再错误转换为 Control。
	var first_target_view: PlayerTargetView = player_views.get(5) as PlayerTargetView
	# 六号位期望动画局部中心；通过动画层完整逆变换从武将牌全局中心换算。
	var expected_first_target_position: Vector2 = animation_layer.get_global_transform().affine_inverse() * first_target_view.get_global_rect().get_center()
	# 六号位实际指示锚点；应精确落在武将牌中心而非中央弃牌区。
	var actual_first_target_position: Vector2 = main_instance.call("_get_player_indicator_position", 5) as Vector2
	if not actual_first_target_position.is_equal_approx(expected_first_target_position):
		_fail("opponent_indicator_anchor:%s expected=%s" % [actual_first_target_position, expected_first_target_position])
		return
	# 本地手牌容器；指示线的本地起点和终点都统一使用其顶边上方中心。
	var hand_container: Control = main_instance.get_node("%HandContainer") as Control
	# 本地锚点全局坐标；水平取手牌区中心，纵向位于顶边上方8像素。
	var local_anchor_global_position: Vector2 = Vector2(hand_container.get_global_rect().get_center().x, hand_container.get_global_rect().position.y - float(main_instance.get("local_hand_indicator_margin")))
	# 本地期望动画局部锚点；与对手锚点使用同一坐标空间。
	var expected_local_anchor: Vector2 = animation_layer.get_global_transform().affine_inverse() * local_anchor_global_position
	# 本地实际指示锚点；五号位无论作为使用者还是目标都应返回该值。
	var actual_local_anchor: Vector2 = main_instance.call("_get_player_indicator_position", 4) as Vector2
	if not actual_local_anchor.is_equal_approx(expected_local_anchor):
		_fail("local_hand_indicator_anchor:%s expected=%s" % [actual_local_anchor, expected_local_anchor])
		return
	# 双目标展示牌数据；使用未占用的稳定 UID 创建正式牌面表现。
	var presentation_card_data: Dictionary = {"uid":90001, "definition_id":"sha", "suit":"spade", "rank":7, "zone":"processing", "owner_id":-1}
	# 双目标玩家 ID；使用强类型数组与正式展示回调的 Array[int] 协议完全一致。
	var presentation_target_ids: Array[int] = [5, 6]
	main_instance.call("_on_card_presentation_requested", presentation_card_data, 4, presentation_target_ids)
	# 本次双目标指示线数据；最新表现序号必须保存共同本地起点与两个不同目标中心。
	var multi_target_presentation: Dictionary = animation_layer._line_presentations.get(animation_layer._presentation_sequence, {}) as Dictionary
	# 双目标终点数组；每名目标必须保留一个独立终点以同步绘制两条线。
	var multi_target_positions: Array = multi_target_presentation.get("target_positions", []) as Array
	if not (multi_target_presentation.get("start_position", Vector2.ZERO) as Vector2).is_equal_approx(expected_local_anchor) or multi_target_positions.size() != 2 or (multi_target_positions[0] as Vector2).is_equal_approx(multi_target_positions[1] as Vector2):
		_fail("multi_target_indicator:%s" % multi_target_presentation)
		return
	animation_layer.clear_presentations()
	await get_tree().create_timer(0.03).timeout
	# 火攻展示牌数据；展示牌没有规则目标，但动画起点必须是展示者武将牌中心。
	var shown_hand_card_data: Dictionary = {"uid":90002, "definition_id":"shan", "suit":"heart", "rank":6, "zone":"hand", "owner_id":5}
	# 展示牌目标 ID；空的强类型数组明确匹配正式展示回调的 Array[int] 参数协议。
	var shown_hand_target_ids: Array[int] = []
	main_instance.call("_on_card_presentation_requested", shown_hand_card_data, 5, shown_hand_target_ids)
	# 最新展示牌表现；无目标展示不会绘制目标指示线，仍保留展示者的真实来源位置。
	var shown_hand_presentation: Dictionary = animation_layer._line_presentations.get(animation_layer._presentation_sequence, {}) as Dictionary
	# 展示者预期起点；与前面已验证的六号位武将牌中心保持同一动画坐标空间。
	var expected_shown_hand_start: Vector2 = main_instance.call("_get_player_indicator_position", 5) as Vector2
	# 展示动画终点数组；火攻展示不指定伤害或卡牌目标，因此必须为空。
	var shown_hand_target_positions: Array = shown_hand_presentation.get("target_positions", []) as Array
	if not (shown_hand_presentation.get("start_position", Vector2.ZERO) as Vector2).is_equal_approx(expected_shown_hand_start) or not shown_hand_target_positions.is_empty():
		_fail("shown_hand_presentation:%s" % shown_hand_presentation)
		return
	animation_layer.clear_presentations()
	await get_tree().create_timer(0.03).timeout
	# 本地获得牌数据；从其他玩家手牌取得后应成为手牌容器中的正式实体节点，并从右侧进入。
	var gained_card_data: Dictionary = {"uid":90003, "definition_id":"tao", "suit":"heart", "rank":3, "zone":"hand", "owner_id":4}
	# 包含获得牌的最新快照；转移信号先登记 UID，随后快照对账创建唯一正式手牌节点。
	var gained_snapshot: Dictionary = _make_ten_player_snapshot()
	# 本地五号位快照；新增实体牌进入 hand 数组并同步公开手牌数量。
	var gained_local_player: Dictionary = (gained_snapshot.get("players", []) as Array)[4] as Dictionary
	gained_local_player["hand"] = [gained_card_data]
	gained_local_player["hand_count"] = 1
	main_instance.call("_on_card_transfer_requested", gained_card_data, 5, "hand", 4, "hand")
	main_instance.call("_on_state_changed", gained_snapshot)
	# 正式手牌视图映射；获得牌必须直接登记在当前手牌 UID 映射中。
	var gained_card_views: Dictionary = main_instance.get("_card_views") as Dictionary
	# 正在入场的正式手牌节点；整个动画与后续交互都复用该实例。
	var gained_hand_card: CardView = gained_card_views.get(90003) as CardView
	# 期望获得牌全局起点中心；桌面辅助查询使用当前可视滚动区右边缘计算。
	var expected_gain_start_center: Vector2 = main_instance.call("_get_local_hand_gain_start_global_position", gained_hand_card.get_card_size()) as Vector2
	# 期望获得牌全局左上角；CardView 的 Node2D 原点位于正式牌面左上角。
	var expected_gain_start_position: Vector2 = expected_gain_start_center - gained_hand_card.get_card_size() * 0.5
	# 获得牌正式实例 ID；再次刷新相同快照后必须保持不变，证明没有重建临时替代节点。
	var gained_card_instance_id: int = gained_hand_card.get_instance_id()
	if gained_hand_card.get_parent() != hand_container or gained_hand_card.is_face_down or not gained_hand_card.global_position.is_equal_approx(expected_gain_start_position) or not (main_instance.get("_local_hand_gain_tweens") as Dictionary).has(90003) or not animation_layer._transfer_cards.is_empty():
		_fail("local_gain_entity parent=%s position=%s expected=%s back=%s transfers=%s" % [gained_hand_card.get_parent(), gained_hand_card.global_position, expected_gain_start_position, gained_hand_card.is_face_down, animation_layer._transfer_cards])
		return
	# 动画中重复收到同一快照；正式手牌节点必须继续复用，补间不能因界面刷新被销毁。
	main_instance.call("_on_state_changed", gained_snapshot)
	if (main_instance.get("_card_views") as Dictionary).get(90003).get_instance_id() != gained_card_instance_id:
		_fail("local_gain_entity_recreated")
		return
	await get_tree().create_timer(0.6).timeout
	# 动画完成后的正式手牌节点；仍位于手牌容器、偏移归零且不再登记入场补间。
	gained_hand_card = (main_instance.get("_card_views") as Dictionary).get(90003) as CardView
	if gained_hand_card.get_parent() != hand_container or not gained_hand_card.hand_entry_offset.is_zero_approx() or (main_instance.get("_local_hand_gain_tweens") as Dictionary).has(90003):
		_fail("local_gain_entity_finish parent=%s offset=%s" % [gained_hand_card.get_parent(), gained_hand_card.hand_entry_offset])
		return
	# 本地摸牌实体数据；牌堆进入本地手牌也必须复用正式手牌节点从右侧入场，而不是创建临时牌背转移节点。
	var drawn_card_data: Dictionary = {"uid":90006, "definition_id":"shan", "suit":"diamond", "rank":2, "zone":"hand", "owner_id":4}
	# 包含原获得牌与新摸牌的快照；原节点继续复用，新 UID 创建第二张正式手牌节点。
	var drawn_snapshot: Dictionary = gained_snapshot.duplicate(true)
	# 本地摸牌后的玩家快照；手牌数组顺序就是正式手牌布局顺序。
	var drawn_local_player: Dictionary = (drawn_snapshot.get("players", []) as Array)[4] as Dictionary
	drawn_local_player["hand"] = [gained_card_data, drawn_card_data]
	drawn_local_player["hand_count"] = 2
	main_instance.call("_on_card_transfer_requested", drawn_card_data, -1, "draw_pile", 4, "hand")
	main_instance.call("_on_state_changed", drawn_snapshot)
	# 本地摸牌正式节点；应立即登记右侧入场补间，动画层不能持有额外临时转移牌。
	var drawn_hand_card: CardView = (main_instance.get("_card_views") as Dictionary).get(90006) as CardView
	if drawn_hand_card == null or drawn_hand_card.get_parent() != hand_container or not (main_instance.get("_local_hand_gain_tweens") as Dictionary).has(90006) or not animation_layer._transfer_cards.is_empty():
		_fail("local_draw_entity:%s/%s" % [drawn_hand_card, animation_layer._transfer_cards])
		return
	main_instance.call("_clear_local_hand_gain_animations")
	# 同批弃置的第一张牌；信号顺序应成为中央队列从左到右的稳定顺序。
	var first_discard_card_data: Dictionary = {"uid":90004, "definition_id":"shan", "suit":"diamond", "rank":8, "zone":"discard_pile", "owner_id":-1}
	# 同批弃置的第二张牌；与第一张在同一帧进入弃牌堆，必须完整共存而不是逐张替换。
	var second_discard_card_data: Dictionary = {"uid":90005, "definition_id":"jiu", "suit":"spade", "rank":9, "zone":"discard_pile", "owner_id":-1}
	animation_layer.card_hold_duration = 0.06
	main_instance.call("_on_card_transfer_requested", first_discard_card_data, 5, "hand", -1, "discard_pile")
	main_instance.call("_on_card_transfer_requested", second_discard_card_data, 6, "hand", -1, "discard_pile")
	await get_tree().create_timer(0.02).timeout
	if animation_layer._active_cards.size() != 2 or animation_layer._active_cards[0].card_uid != 90004 or animation_layer._active_cards[1].card_uid != 90005 or animation_layer._active_cards[0].position.x >= animation_layer._active_cards[1].position.x:
		_fail("discard_batch_order:%s" % [animation_layer._active_cards.map(func(card: CardView) -> int: return card.card_uid)])
		return
	animation_layer.clear_presentations()
	await get_tree().create_timer(0.03).timeout
	# 已展示并淡出的实际使用牌；最终处理区转弃牌时不得在中央重新创建第二张表现牌。
	var delayed_discard_card_data: Dictionary = {"uid":90007, "definition_id":"sha", "suit":"club", "rank":6, "zone":"processing", "owner_id":-1}
	# 单目标展示目标；使用已验证的六号位武将牌中心创建一次正常使用动画。
	var delayed_discard_target_ids: Array[int] = [5]
	animation_layer.card_hold_duration = 0.01
	main_instance.call("_on_card_presentation_requested", delayed_discard_card_data, 4, delayed_discard_target_ids)
	await get_tree().create_timer(0.06).timeout
	if not animation_layer._active_cards.is_empty() or not (main_instance.get("_presented_discard_card_uids") as Dictionary).has(90007):
		_fail("delayed_discard_presentation_state:%s" % [animation_layer._active_cards])
		return
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	if not animation_layer._active_cards.is_empty() or (main_instance.get("_presented_discard_card_uids") as Dictionary).has(90007):
		_fail("delayed_discard_duplicate:%s" % [animation_layer._active_cards])
		return
	# 单目标交互状态；本地五号位持有一张决斗，其他存活角色都是可替换目标。
	var single_target_state: GameState = _make_single_target_state()
	match_controller.state = single_target_state
	match_controller.card_rules = CardRuleService.new(single_target_state)
	main_instance.call("_on_state_changed", single_target_state.to_dict(4, false))
	# 单目标测试牌；从本地状态读取稳定 UID，避免依赖全局实体牌计数器的当前值。
	var single_target_card: CardInstance = single_target_state.players[4].hand[0]
	main_instance.call("_on_card_pressed", single_target_card.uid)
	main_instance.call("_on_target_pressed", 5)
	# 第一次目标选择结果；点击六号位后应只保留该目标。
	var first_single_target_selection: Array = (main_instance.get("_selected_target_ids") as Array).duplicate()
	main_instance.call("_on_target_pressed", 6)
	# 第二次目标选择结果；无需先点六号位取消，直接点击七号位即可替换。
	var switched_single_target_selection: Array = (main_instance.get("_selected_target_ids") as Array).duplicate()
	if first_single_target_selection != [5] or switched_single_target_selection != [6]:
		_fail("single_target_switch:%s/%s" % [first_single_target_selection, switched_single_target_selection])
		return
	menu_button.pressed.connect(_on_menu_button_pressed)
	await _click_control(menu_button)
	if not _menu_button_pressed:
		_fail("menu_button_input")
		return
	# 菜单内容面板；真实点击后必须展开，人数输入与重新开局按钮才能参与后续命中测试。
	var menu_panel: PanelContainer = main_instance.get_node("%MenuPanel") as PanelContainer
	if not menu_panel.visible:
		_fail("menu_panel_not_open")
		return
	# AI 响应速度滑条；修改值后必须写入全局设置并同步给当前对局控制器，无需重开对局。
	var ai_response_delay_slider: HSlider = main_instance.get_node("%AiResponseDelaySlider") as HSlider
	# 本用例选择的 AI 响应等待时间；0.65秒位于0.05至1秒设置范围内且对默认值具有可见差异。
	var requested_ai_response_delay: float = 0.65
	ai_response_delay_slider.value = requested_ai_response_delay
	await get_tree().process_frame
	if not is_equal_approx(GameSettings.ai_response_delay_seconds, requested_ai_response_delay) or not is_equal_approx(match_controller.ai_action_delay_seconds, requested_ai_response_delay):
		_fail("ai_response_delay_setting:%s/%s" % [GameSettings.ai_response_delay_seconds, match_controller.ai_action_delay_seconds])
		return
	# 对局日志展开按钮；点击后正文面板必须显示，验证“记录”入口不再只是静态标题。
	var log_toggle_button: Button = main_instance.get_node("%LogToggleButton") as Button
	# 对局日志正文面板；折叠组件只改变该节点可见性，不中断日志追加。
	var log_content_panel: PanelContainer = main_instance.get_node("%LogContentPanel") as PanelContainer
	await _click_control(log_toggle_button)
	if not log_content_panel.visible:
		_fail("log_panel_not_expanded")
		return
	# 下一局人数输入；直接写入尚未失焦提交的文本，验证重开按钮会读取玩家当前键入值。
	var player_count_input: SpinBox = main_instance.get_node("%NextPlayerCountInput") as SpinBox
	player_count_input.get_line_edit().text = "6"
	# 菜单重新开局按钮；点击后控制器应创建六人对局并进入新的选将阶段。
	var restart_button: Button = main_instance.get_node("%MenuRestartButton") as Button
	animation_layer.card_flight_duration = 0.01
	animation_layer.card_hold_duration = 0.01
	animation_layer.target_line_fade_duration = 0.01
	# 重开时仍在执行的区域转移牌面；真实菜单点击必须先清除它，再创建下一局状态。
	var restarting_transfer_card: CardView = (load("res://scenes/components/card_view.tscn") as PackedScene).instantiate() as CardView
	restarting_transfer_card.configure_back(93001, false)
	animation_layer.add_child(restarting_transfer_card)
	animation_layer.play_transfer(restarting_transfer_card, Vector2(460.0, 260.0), Vector2(680.0, 460.0), "draw:menu_restart")
	await _click_control(restart_button)
	for _restart_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if match_controller.default_player_count != 6 or match_controller.state == null or match_controller.state.players.size() != 6:
		# 当前悬停控件；失败信息用于判断重开按钮是否被更高层级界面遮挡。
		var hovered_control: Control = get_viewport().gui_get_hovered_control()
		_fail("restart_player_count:%d menu=%s button=%s input=%s/%s hovered=%s" % [match_controller.state.players.size() if match_controller.state != null else -1, menu_panel.visible, _screen_rect(restart_button), player_count_input.get_line_edit().text, player_count_input.value, hovered_control.get_path() if hovered_control != null else "none"])
		return
	if animation_layer.get_child_count() != 0 or not animation_layer._transfer_cards.is_empty() or not animation_layer._transfer_tweens.is_empty() or not animation_layer._draw_transfer_stacks.is_empty():
		_fail("restart_transfer_cleanup:%d/%s/%s/%s" % [animation_layer.get_child_count(), animation_layer._transfer_cards, animation_layer._transfer_tweens, animation_layer._draw_transfer_stacks])
		return
	# 选将遮罩已经打开；菜单仍必须位于其上方，允许玩家在开局阶段继续调整人数并重新开始。
	_menu_button_pressed = false
	await _click_control(menu_button)
	if not _menu_button_pressed or not menu_panel.visible:
		_fail("menu_blocked_by_character_selection")
		return
	player_count_input.get_line_edit().text = "4"
	await _click_control(restart_button)
	for _second_restart_frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	if match_controller.default_player_count != 4 or match_controller.state == null or match_controller.state.players.size() != 4:
		_fail("second_restart_player_count:%d" % (match_controller.state.players.size() if match_controller.state != null else -1))
		return
	# 菜单与重开交互完成后等待面板布局稳定，再释放正式场景实例。
	await get_tree().process_frame
	await get_tree().process_frame
	remove_child(main_instance)
	main_instance.free()
	await get_tree().process_frame
	print("UI_LAYOUT_PASS viewport=%s" % viewport_rect.size)
	get_tree().quit(0)


## 把控件本地矩形转换为实际视口屏幕坐标，包含画布缩放与窗口拉伸。
func _screen_rect(control: Control) -> Rect2:
	# 控件到屏幕坐标的完整变换；场景没有旋转，但仍按四角计算以避免缩放假设。
	var screen_transform: Transform2D = control.get_screen_transform()
	# 屏幕坐标下的左上角；由控件局部原点经过完整变换得到。
	var top_left: Vector2 = screen_transform * Vector2.ZERO
	# 屏幕坐标下的右下角；由控件局部尺寸经过完整变换得到。
	var bottom_right: Vector2 = screen_transform * control.size
	return Rect2(top_left, bottom_right - top_left)


## 向控件中心发送鼠标移动、按下和释放事件，验证真实 GUI 命中链而非直接调用按钮方法。
func _click_control(control: Control) -> void:
	# 当前控件屏幕中心；所有输入事件使用与视口可见矩形相同的坐标空间。
	var click_position: Vector2 = _screen_rect(control).get_center()
	# 鼠标移动事件；先更新悬停目标，确保后续按钮事件走正常 GUI 分发路径。
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.position = click_position
	get_viewport().push_input(motion_event, true)
	await get_tree().process_frame
	# 鼠标按下事件；使用左键且不直接发射 pressed 信号。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.position = click_position
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	get_viewport().push_input(press_event, true)
	await get_tree().process_frame
	# 鼠标释放事件；Button 在正常按下与释放序列完成后发出 pressed。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.position = click_position
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	get_viewport().push_input(release_event, true)
	await get_tree().process_frame


## 构造只包含界面公开字段的十人快照；覆盖本地玩家在五号位时的最拥挤座次布局且不启动规则核心、AI计时器或卡牌动画。
func _make_ten_player_snapshot() -> Dictionary:
	# 测试玩家数组；五号位作为本地玩家，其余9名用于顶部五席与左右各两席。
	var players: Array[Dictionary] = []
	for player_index: int in range(10):
		# 当前玩家快照；字段与正式裁剪快照保持一致，空区域避免引入无关卡牌交互。
		var player_snapshot: Dictionary = {
			"player_id":player_index,
			"display_name":"玩家%d" % (player_index + 1),
			"character_id":"trailblazer",
			"identity":"lord" if player_index == 0 else "hidden",
			"hp":4,
			"max_hp":4,
			"alive":true,
			"chained":false,
			"hand_count":4,
			"hand":[],
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage":[],
			"wooden_ox_storage_count":0,
		}
		if player_index == 4:
			player_snapshot["equipment"] = {"treasure":{"uid":94001, "definition_id":"muniu", "suit":"diamond", "rank":5, "zone":"equipment", "owner_id":4}}
			player_snapshot["wooden_ox_storage_count"] = 3
		players.append(player_snapshot)
	# 十人界面快照；准备阶段禁用出牌控件，但保留完整本地技能栏和全部公开角色信息。
	var snapshot: Dictionary = {
		"players":players,
		"current_player_id":0,
		"current_phase":"setup",
		"turn_number":1,
		"draw_pile_count":121,
		"discard_pile_count":0,
		"game_over":false,
	}
	return snapshot


## 构造用于单目标切换的同步规则状态；本地五号位持有【决斗】，其余九名玩家均为合法目标。
func _make_single_target_state() -> GameState:
	# 单目标测试状态；无 match_id 保证不会启动正式对局 AI 或网络流程。
	var game_state: GameState = GameState.new()
	for player_id: int in range(10):
		# 当前测试玩家；全部存活且使用连续稳定 ID，目标规则只排除使用者本人。
		var player: PlayerState = PlayerState.new(player_id, "玩家%d" % (player_id + 1))
		player.identity = "lord" if player_id == 0 else "rebel"
		player.character_id = "trailblazer"
		player.character_revealed = true
		game_state.players.append(player)
	# 单目标测试牌；【决斗】无距离限制且最多选择1名其他角色。
	var duel_card: CardInstance = CardInstance.new("juedou", "spade", 1)
	duel_card.zone = "hand"
	duel_card.owner_id = 4
	game_state.players[4].hand.append(duel_card)
	game_state.current_player_id = 4
	game_state.current_phase = "play"
	game_state.turn_number = 1
	return game_state


## 记录右上角菜单按钮收到真实鼠标点击，供异步输入流程断言。
func _on_menu_button_pressed() -> void:
	_menu_button_pressed = true


## 输出统一失败原因并以非零状态结束测试。
func _fail(reason: String) -> void:
	printerr("UI_LAYOUT_FAIL %s" % reason)
	get_tree().quit(1)
