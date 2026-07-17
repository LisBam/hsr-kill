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
	# 左上角三行对局信息；只允许显示轮数、牌堆剩余与对局时长，不再混入行动角色或阶段。
	var round_label: Label = main_instance.get_node("%PhaseLabel") as Label
	# 左上角牌堆标签；只显示当前摸牌堆剩余数量。
	var draw_pile_label: Label = main_instance.get_node("%CenterTurnLabel") as Label
	# 左上角时长标签；按“对局时长：分:秒”格式持续刷新。
	var match_duration_label: Label = main_instance.get_node("%CenterPhaseLabel") as Label
	if round_label.text != "第3轮" or draw_pile_label.text != "牌堆剩余：121" or not match_duration_label.text.begins_with("对局时长：") or round_label.text.contains("玩家") or draw_pile_label.text.contains("阶段"):
		_fail("top_info:%s/%s/%s" % [round_label.text, draw_pile_label.text, match_duration_label.text])
		return
	# 右上角菜单按钮；必须完整位于视口内并能通过真实鼠标事件收到 pressed 信号。
	var menu_button: Button = main_instance.get_node("%MenuButton") as Button
	# 底部装备面板；左下区域必须完整位于窗口客户区内。
	var equipment_panel: Control = main_instance.get_node("%EquipmentPanel") as Control
	# 参考图装备面板固定规格；透明外层只负责提供130×147像素的五槽布局区域。
	# 当前装备面板与手牌栏统一为175像素高，并横向延伸到手牌栏左边界。
	if not equipment_panel.size.is_equal_approx(Vector2(150.0, 175.0)):
		_fail("equipment_panel_size:%s" % equipment_panel.size)
		return
	# 底部手牌面板；其底边必须随窗口底部锚定，不能继续停留在固定720坐标。
	var hand_panel: Control = main_instance.get_node("HandPanel") as Control
	# 手牌栏背景样式；当前只保留透明滚动容器，不绘制整块边框或底色。
	var hand_panel_style: StyleBox = (hand_panel as PanelContainer).get_theme_stylebox("panel")
	# 中央交互面板；当前不是本地玩家行动时必须隐藏，且面板样式为空背景。
	var interaction_panel: PanelContainer = main_instance.get_node("InteractionPanel") as PanelContainer
	# 中央确定按钮；与取消按钮使用相同主按钮规格。
	var confirm_button: Button = main_instance.get_node("%UseButton") as Button
	# 中央取消按钮；不再使用较小的次级按钮规格。
	var cancel_button: Button = main_instance.get_node("%CancelButton") as Button
	# 右侧回合结束按钮；必须脱离 InteractionPanel 成为主场景直接子节点。
	var end_play_button: Button = main_instance.get_node("%EndPlayButton") as Button
	# 已废弃重铸按钮；节点仅保留旧场景兼容，不得在任何状态进入可见布局。
	var recast_button: Button = main_instance.get_node("%RecastButton") as Button
	# 已废弃存木牛按钮；木牛流马改由装备横条点击发动。
	# 中央操作按钮行；确定与取消使用28像素间距，避免相反命令视觉粘连。
	var action_row: HBoxContainer = main_instance.get_node("InteractionPanel/InteractionVBox/ActionRow") as HBoxContainer
	# 回合结束普通样式；朱红背景必须与中央暖金操作按钮清晰区分。
	var end_play_normal_style: StyleBoxFlat = end_play_button.get_theme_stylebox("normal") as StyleBoxFlat
	# 确定按钮禁用样式；不可选择时固定为深灰，不沿用普通或悬停高亮。
	var confirm_disabled_style: StyleBoxFlat = confirm_button.get_theme_stylebox("disabled") as StyleBoxFlat
	# 确定按钮普通样式；用于验证禁用状态具有明确亮度差。
	var confirm_normal_style: StyleBoxFlat = confirm_button.get_theme_stylebox("normal") as StyleBoxFlat
	if interaction_panel.visible or not (interaction_panel.get_theme_stylebox("panel") is StyleBoxEmpty) or not confirm_button.custom_minimum_size.is_equal_approx(cancel_button.custom_minimum_size) or action_row.get_theme_constant("separation") != 28 or not end_play_button.custom_minimum_size.is_equal_approx(Vector2(112.0, 36.0)) or end_play_button.custom_minimum_size.x >= cancel_button.custom_minimum_size.x or cancel_button.get_global_rect().intersects(end_play_button.get_global_rect()) or end_play_normal_style.bg_color.r <= end_play_normal_style.bg_color.g * 1.5 or confirm_normal_style.bg_color.get_luminance() - confirm_disabled_style.bg_color.get_luminance() < 0.1 or end_play_button.get_parent() != main_instance or end_play_button.visible or recast_button.visible:
		_fail("interaction_controls panel=%s end_parent=%s" % [interaction_panel.visible, end_play_button.get_parent().name])
		return
	# 手牌栏额外保留18像素选中抬升空间；装备栏与其同为175像素，二者右左边界精确相接且背景透明。
	if not is_equal_approx(hand_panel.size.y, 175.0) or not is_equal_approx(equipment_panel.size.y, 175.0) or not is_equal_approx(equipment_panel.position.x + equipment_panel.size.x, hand_panel.position.x) or not hand_panel_style is StyleBoxEmpty:
		_fail("hand_equipment_alignment equipment=%s hand=%s" % [equipment_panel.get_rect(), hand_panel.get_rect()])
		return
	# 底部技能栏；右侧区域必须完整位于本地武将牌左侧并保持可见。
	var skill_bar: Control = main_instance.get_node("SkillBar") as Control
	# 技能状态兼容标签；正式技能区只显示按钮，因此该节点必须保持隐藏且不占布局。
	var skill_status_label: Label = main_instance.get_node("%SkillStatusLabel") as Label
	# 当前本地技能按钮映射；测试武将只有一个技能，手牌栏应增长到该按钮左侧。
	var skill_views: Dictionary = main_instance.get("_skill_views") as Dictionary
	# 当前唯一技能按钮；正文固定只显示技能名前两个字，不附加状态文字。
	var first_skill_button: SkillButtonView
	if not skill_views.is_empty():
		first_skill_button = skill_views.values()[0] as SkillButtonView
	if not skill_bar.get_theme_stylebox("panel") is StyleBoxEmpty or skill_status_label.visible or skill_views.size() != 1 or first_skill_button == null or first_skill_button.text.length() > 2 or not is_equal_approx(hand_panel.position.x + hand_panel.size.x + 8.0, skill_bar.position.x):
		_fail("skill_button_only_layout:%s/%s" % [skill_bar.get_rect(), first_skill_button.text if first_skill_button != null else "null"])
		return
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
	# 当前节点已重构为装备堆叠组件；保留原测试变量名，改为检查实际宝物横条及其完整说明。
	var local_equipment_label: EquipmentStackView = main_instance.get_node("%EquipmentStack") as EquipmentStackView
	# 本地武器横条；与宝物同时存在时必须位于五槽布局第一行，不能和宝物自动紧凑排列。
	var local_weapon_row: Button = local_equipment_label.get_row("weapon")
	# 本地宝物横条；木牛流马存有3张“粮”，数量必须紧跟装备名写入牌面说明。
	var local_treasure_row: Button = local_equipment_label.get_row("treasure")
	# 本地空防具横条；即使没有装备也必须显示参考图中的深色槽位和类型图标。
	var local_empty_armor_row: Button = local_equipment_label.get_row("armor")
	# 五槽固定节距；武器到宝物应跨越4个完整的27像素槽高与3像素间距。
	# 当前五槽自适应高度；175像素扣除四段间距后平均分配。
	var local_adaptive_equipment_row_height: float = (local_equipment_label.size.y - local_equipment_label.equipment_row_gap * 4.0) / 5.0
	# 当前五槽节距；等于29像素自适应槽高加3像素间距。
	var local_equipment_row_pitch: float = local_adaptive_equipment_row_height - local_equipment_label.equipment_row_overlap + local_equipment_label.equipment_row_gap
	if local_weapon_row == null or local_treasure_row == null or local_empty_armor_row == null or not is_equal_approx(local_weapon_row.size.y, local_adaptive_equipment_row_height) or not local_treasure_row.tooltip_text.contains("木牛流马（3）") or not is_equal_approx(local_treasure_row.position.y - local_weapon_row.position.y, local_equipment_row_pitch * 4.0) or local_equipment_label.is_slot_equipped("armor") or not local_empty_armor_row.disabled:
		_fail("local_equipment_stack:%s" % local_equipment_label.tooltip_text)
		return
	# 本地武将牌装备条；第一视角只通过左侧装备栏查看装备，武将牌自身不得重复显示横条。
	var local_player_card: PlayerTargetView = main_instance.get("local_player_card") as PlayerTargetView
	# 武将牌当前装备条数组；第一视角关闭公开装备绘制后应保持为空。
	var local_player_equipment_rows: Array = local_player_card.get("_equipment_rows") as Array
	# 武将牌当前装备槽位数组；关闭绘制后不保留任何视觉槽位索引。
	var local_player_equipment_slots: Array = local_player_card.get("_equipment_row_slots") as Array
	if not local_player_equipment_rows.is_empty() or not local_player_equipment_slots.is_empty():
		_fail("local_player_equipment_slots:%s" % [local_player_equipment_slots])
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
	# 当前回合角色牌；0号玩家必须保留3像素亮金边框，即使当前实际等待5号玩家操作。
	var current_turn_view: PlayerTargetView = player_views.get(0) as PlayerTargetView
	# 当前操作角色牌；5号玩家通过选择请求 actor 高亮，并与当前回合金边语义分离。
	var current_operator_view: PlayerTargetView = player_views.get(5) as PlayerTargetView
	# 当前回合角色最终面板样式；用于验证亮金边框颜色与3像素宽度。
	var current_turn_style: StyleBoxFlat = (current_turn_view.get_node("CardBody") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	# 当前操作角色最终面板样式；用于验证只提亮底色和边框，不再绘制青绿色外发光。
	var current_operator_style: StyleBoxFlat = (current_operator_view.get_node("CardBody") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	if not current_turn_view.is_current_actor or current_turn_view.is_current_operator or current_turn_style.border_color != BattleUIStyle.ACCENT_COLOR or current_turn_style.border_width_left != 3 or current_operator_view.is_current_actor or not current_operator_view.is_current_operator or current_operator_style.shadow_color == Color("72d8b5aa"):
		_fail("player_operation_highlight")
		return
	# 玩家名悬停阴影；正式对局武将牌进入悬停后应在上部显示公开玩家名，离开后立即隐藏。
	var hover_name_shade: TextureRect = current_operator_view.get_node("HoverNameShade") as TextureRect
	# 玩家名标签；测试目标为六号位，因此显示名固定为“玩家6”。
	var hover_player_name: Label = current_operator_view.get_node("HoverNameShade/HoverPlayerName") as Label
	current_operator_view.call("_on_input_mouse_entered")
	if not hover_name_shade.visible or hover_player_name.text != "玩家6":
		_fail("player_name_hover:%s/%s" % [hover_name_shade.visible, hover_player_name.text])
		return
	current_operator_view.call("_on_input_mouse_exited")
	if hover_name_shade.visible:
		_fail("player_name_hover_exit")
		return
	# 未知身份本地标注；选择反贼后只改变当前客户端徽记，不修改快照中的 hidden 身份。
	main_instance.call("_on_identity_badge_pressed", 5)
	main_instance.call("_on_identity_mark_selected", 1)
	# 已标注身份徽记；用于验证本地推测文本与标注字典同步。
	var marked_identity_badge: Label = current_operator_view.get_node("IdentityBadge") as Label
	if marked_identity_badge.text != "反" or str((main_instance.get("_identity_marks") as Dictionary).get(5, "")) != "rebel":
		_fail("identity_local_mark:%s" % marked_identity_badge.text)
		return
	# 真实身份公开优先级；即使随后写入另一项本地标注，徽记仍必须显示权威忠臣身份。
	var revealed_player_snapshot: Dictionary = (((_make_ten_player_snapshot().get("players", []) as Array)[5]) as Dictionary).duplicate(true)
	revealed_player_snapshot["identity"] = "loyalist"
	# 公开身份测试武将定义；沿用快照武将 ID 获取正式牌面元数据。
	var revealed_character_definition: Dictionary = GameDatabase.get_character(str(revealed_player_snapshot.get("character_id", "")))
	# 公开身份测试势力定义；保持配置签名与正式渲染入口一致。
	var revealed_faction_definition: Dictionary = GameDatabase.get_faction(str(revealed_character_definition.get("faction", "")))
	current_operator_view.configure_snapshot(revealed_player_snapshot, revealed_character_definition, false, revealed_faction_definition)
	current_operator_view.set_identity_mark("renegade")
	if marked_identity_badge.text != "忠":
		_fail("identity_reveal_priority:%s" % marked_identity_badge.text)
		return
	# 首次渲染的玩家 ID 到座位节点实例 ID；重复快照后用于确认没有整桌释放重建。
	var opponent_instance_ids: Dictionary = {}
	for player_id_variant: Variant in player_views.keys():
		opponent_instance_ids[int(player_id_variant)] = (player_views[player_id_variant] as PlayerTargetView).get_instance_id()
	main_instance.call("_on_state_changed", _make_ten_player_snapshot())
	# 重复快照后的玩家视图索引；轻量字典允许重建，但每名玩家必须继续绑定原节点实例。
	var repeated_player_views: Dictionary = main_instance.get("_player_views") as Dictionary
	for player_id_variant: Variant in repeated_player_views.keys():
		if int(opponent_instance_ids.get(int(player_id_variant), -1)) != (repeated_player_views[player_id_variant] as PlayerTargetView).get_instance_id():
			_fail("opponent_view_recreated:%s" % player_id_variant)
			return
	player_views = repeated_player_views
	# 正式选将组件；无主公快照时候选区域应直接占用左侧空位，不保留不可见主公占位。
	var character_selection_panel: CharacterSelectionPanel = main_instance.get_node("%CharacterSelectionPanel") as CharacterSelectionPanel
	# 无主公选将快照；两张候选足以验证左对齐、悬停缩放与点击高亮语义。
	var selection_snapshot_without_lord: Dictionary = {
		"phase":CharacterSelectionService.PHASE_OTHERS,
		"can_select":true,
		"local_candidates":["trailblazer", "march_7th"],
		"lord_character_id":"",
		"lord_player_id":0,
	}
	character_selection_panel.bind_snapshot(selection_snapshot_without_lord)
	await get_tree().process_frame
	# 候选区域与主公区域；无主公时两者左边界应完全一致，分隔线保持隐藏。
	var candidate_area: Control = character_selection_panel.get_node("SelectionFrame/CharacterCandidateArea") as Control
	# 主公只读区域；无主公时其左边界成为候选区新的左对齐基准。
	var lord_area: Control = character_selection_panel.get_node("SelectionFrame/LordCharacterArea") as Control
	# 主公竖向分隔线；无主公时隐藏，有主公时显示。
	var lord_divider: ColorRect = character_selection_panel.get_node("SelectionFrame/LordDivider") as ColorRect
	if not is_equal_approx(candidate_area.position.x, lord_area.position.x) or lord_divider.visible:
		_fail("selection_without_lord_partition:%s/%s" % [candidate_area.position.x, lord_divider.visible])
		return
	# 当前候选视图；第一张用于悬停缩放，第二张用于确认未选牌不会获得合法目标发光。
	var candidate_views: Dictionary = character_selection_panel.get("_candidate_views") as Dictionary
	# 第一张候选武将牌；承担悬停缩放与点击选中断言。
	var first_candidate: PlayerTargetView = candidate_views.get("trailblazer") as PlayerTargetView
	# 第二张候选武将牌；承担未选状态不发光断言。
	var second_candidate: PlayerTargetView = candidate_views.get("march_7th") as PlayerTargetView
	character_selection_panel.call("_on_candidate_hover_changed", true, "trailblazer")
	await get_tree().create_timer(0.18).timeout
	if first_candidate.scale.x <= 1.0:
		_fail("selection_hover_scale:%s" % first_candidate.scale)
		return
	character_selection_panel.call("_on_candidate_hover_changed", false, "trailblazer")
	await get_tree().create_timer(0.18).timeout
	if not first_candidate.scale.is_equal_approx(Vector2.ONE):
		_fail("selection_hover_restore:%s" % first_candidate.scale)
		return
	character_selection_panel.call("_select_candidate", "trailblazer")
	if not first_candidate.is_target_selected or first_candidate.is_legal_target or second_candidate.is_target_selected or second_candidate.is_legal_target:
		_fail("selection_click_glow_scope")
		return
	# 有主公选将快照；主公牌缩小并显示竖线，候选区域恢复到分隔线右侧。
	var selection_snapshot_with_lord: Dictionary = selection_snapshot_without_lord.duplicate(true)
	selection_snapshot_with_lord["lord_character_id"] = "welt"
	character_selection_panel.bind_snapshot(selection_snapshot_with_lord)
	await get_tree().process_frame
	# 缩小后的主公武将牌；缩放值必须读取组件公开配置并保持只读。
	var lord_character_view: PlayerTargetView = character_selection_panel.get("_lord_character_view") as PlayerTargetView
	if lord_character_view == null or not is_equal_approx(lord_character_view.scale.x, character_selection_panel.lord_character_scale) or not lord_divider.visible or candidate_area.position.x <= lord_area.position.x:
		_fail("selection_lord_partition")
		return
	character_selection_panel.close()
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
	# 该数组现嵌入 CardPresentationEvent 字典，目标 ID 的强类型协议保持不变。
	var presentation_target_ids: Array[int] = [5, 6]
	# 使用牌表现事件；真实处理区牌接管后续弃牌移动，目标数组用于绘制两条指示线。
	var use_presentation_data: Dictionary = {"presentation_id":1, "event_id":1, "event_name":"useCard", "card_data":presentation_card_data, "actor_id":4, "target_ids":presentation_target_ids, "source_zone":"processing", "owns_discard_transfer":true}
	main_instance.call("_on_card_presentation_requested", use_presentation_data)
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
	# 该数组现嵌入 CardPresentationEvent 字典，空目标语义保持不变。
	var shown_hand_target_ids: Array[int] = []
	# 火攻展示事件；实体仍留在手牌区，因此不得接管该 UID 未来真正进入弃牌堆的移动。
	var shown_hand_presentation_data: Dictionary = {"presentation_id":2, "event_id":2, "event_name":"showCards", "card_data":shown_hand_card_data, "actor_id":5, "target_ids":shown_hand_target_ids, "source_zone":"hand", "owns_discard_transfer":false}
	main_instance.call("_on_card_presentation_requested", shown_hand_presentation_data)
	# 最新展示牌表现；无目标展示不会绘制目标指示线，仍保留展示者的真实来源位置。
	var shown_hand_presentation: Dictionary = animation_layer._line_presentations.get(animation_layer._presentation_sequence, {}) as Dictionary
	# 展示者预期起点；与前面已验证的六号位武将牌中心保持同一动画坐标空间。
	var expected_shown_hand_start: Vector2 = main_instance.call("_get_player_indicator_position", 5) as Vector2
	# 展示动画终点数组；火攻展示不指定伤害或卡牌目标，因此必须为空。
	var shown_hand_target_positions: Array = shown_hand_presentation.get("target_positions", []) as Array
	if not (shown_hand_presentation.get("start_position", Vector2.ZERO) as Vector2).is_equal_approx(expected_shown_hand_start) or not shown_hand_target_positions.is_empty():
		_fail("shown_hand_presentation:%s" % shown_hand_presentation)
		return
	if animation_layer.consume_discard_transfer_claim(90002):
		_fail("shown_hand_claimed_discard")
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
	# 延迟弃牌使用事件；动画淡出后仍需保留 UID 所有权，直到真实 processing -> discard 移动到达。
	var delayed_discard_presentation_data: Dictionary = {"presentation_id":3, "event_id":3, "event_name":"useCard", "card_data":delayed_discard_card_data, "actor_id":4, "target_ids":delayed_discard_target_ids, "source_zone":"processing", "owns_discard_transfer":true}
	main_instance.call("_on_card_presentation_requested", delayed_discard_presentation_data)
	# 重复表现包；相同 presentation_id 在任何节点创建前被拒绝，活动队列始终只有一个实体牌面。
	main_instance.call("_on_card_presentation_requested", delayed_discard_presentation_data)
	if animation_layer._active_cards.size() != 1:
		_fail("duplicate_presentation_created=%s" % [animation_layer._active_cards])
		return
	await get_tree().create_timer(0.06).timeout
	if not animation_layer._active_cards.is_empty() or not animation_layer._discard_transfer_claims.has(90007):
		_fail("delayed_discard_presentation_state:%s" % [animation_layer._active_cards])
		return
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	if not animation_layer._active_cards.is_empty() or animation_layer._discard_transfer_claims.has(90007):
		_fail("delayed_discard_duplicate:%s" % [animation_layer._active_cards])
		return
	# 重复移动增量；认领消费后继续保留幂等 UID，第二次转发也不能在牌桌上方重新实例化同一张牌。
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	if not animation_layer._active_cards.is_empty() or not animation_layer._consumed_discard_transfer_claims.has(90007):
		_fail("repeated_discard_transfer_created:%s" % [animation_layer._active_cards])
		return
	# 不同表现 ID 的迟到包；实体仍在弃牌生命周期时也必须拒绝，不能把网络重发误判为下一次真实使用。
	var late_presentation_data: Dictionary = delayed_discard_presentation_data.duplicate(true)
	late_presentation_data["presentation_id"] = 4
	main_instance.call("_on_card_presentation_requested", late_presentation_data)
	if not animation_layer._active_cards.is_empty() or not animation_layer._consumed_discard_transfer_claims.has(90007):
		_fail("late_distinct_presentation_created:%s" % [animation_layer._active_cards])
		return
	# 实体进入新的非弃牌区域；权威移牌内部通知会释放旧待消费与已消费状态，使该牌未来一次合法普通弃置重新可见。
	main_instance.call("_on_card_animation_ownership_reset_requested", 90007)
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	if animation_layer._active_cards.size() != 1 or animation_layer._active_cards[0].card_uid != 90007:
		_fail("discard_claim_not_released:%s" % [animation_layer._active_cards])
		return
	animation_layer.clear_presentations()
	# 尚未到达弃牌堆的旧认领也必须在实体进入新区域时释放，否则该 UID 下一次真实使用会被误判为重复表现。
	if not animation_layer.claim_presentation(5, 90008, true):
		_fail("pending_discard_claim_registration")
		return
	animation_layer.release_consumed_discard_claim(90008)
	if not animation_layer.claim_presentation(6, 90008, true):
		_fail("pending_discard_claim_not_released")
		return
	animation_layer.clear_presentations()
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
			player_snapshot["equipment"] = {
				"weapon":{"uid":94000, "definition_id":"qinggang", "suit":"spade", "rank":6, "zone":"equipment", "owner_id":4},
				"treasure":{"uid":94001, "definition_id":"muniu", "suit":"diamond", "rank":5, "zone":"equipment", "owner_id":4},
			}
			player_snapshot["wooden_ox_storage_count"] = 3
		players.append(player_snapshot)
	# 十人界面快照；准备阶段禁用出牌控件，但保留完整本地技能栏和全部公开角色信息。
	var snapshot: Dictionary = {
		"players":players,
		"current_player_id":0,
		"current_phase":"setup",
		"current_choice_request":{"request_id":77, "actor_id":5},
		"round_number":3,
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
