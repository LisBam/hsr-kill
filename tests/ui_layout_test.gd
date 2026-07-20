extends Node

## 局内界面布局与鼠标命中回归测试。测试使用正式主场景，验证边缘按钮和底部区域在默认窗口内完整可见。

## 主场景完成主菜单和动态节点构建前等待的帧数；默认6帧覆盖控件初始化、主题刷新与容器排序。
const SETTLE_FRAME_COUNT: int = 6

## 模拟未应用画布拉伸时的客户区尺寸；1152×648与项目默认启动窗口一致，用于复现固定1280×720坐标越界问题。
const COMPACT_CLIENT_SIZE: Vector2 = Vector2(1152.0, 648.0)

## 极短补间的回归等待时长；默认0.08秒覆盖无头模式下补间从下一帧开始处理的调度差异，不改变正式动画参数。
const SHORT_TWEEN_SETTLE_SECONDS: float = 0.08

## 统一悬停信息框延迟的回归等待时长；默认0.55秒覆盖正式0.5秒配置与无头计时器调度余量。
const HOVER_INFORMATION_DELAY_SETTLE_SECONDS: float = 0.55

## 菜单按钮是否通过真实视口输入收到点击；默认 false，按钮信号触发后改为 true。
var _menu_button_pressed: bool = false


## 延迟执行正式场景检查，保证测试根节点已经进入场景树。
func _ready() -> void:
	# 日志暂停用例期间测试驱动仍需继续发送输入与执行断言，始终处理模式只作用于测试根节点。
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# 牌桌根节点必须忽略鼠标，让背景空白左键进入未处理输入回调；实际按钮和面板仍由各自子控件命中。
	if main_instance.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("main_root_mouse_filter:%d" % main_instance.mouse_filter)
		return
	# 正式对局控制器；先使用非法的1人配置阻止规则对局和AI异步任务启动，随后以五号位作为本地玩家注入只读十人界面快照。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 牌桌统一信息框；本地装备、手牌、技能和双方武将牌都通过该单一组件显示说明。
	var information_box: InformationBoxLayer = main_instance.get("information_box") as InformationBoxLayer
	match_controller.default_player_count = 1
	match_controller.local_human_player_id = 4
	match_controller.randomize_local_human_seat = false
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 启动主菜单；新进入场景时必须先显示身份模式预览，不允许在未确认前自动创建对局。
	var startup_main_menu: MainMenu = main_instance.get_node("%MainMenu") as MainMenu
	# 主菜单开始按钮；文字与可见性共同验证“前往挑战”已改为“开始游戏”。
	var startup_start_button: Button = main_instance.get_node("%StartGameButton") as Button
	# 主菜单设置按钮；位于开始按钮左侧，替代参考布局中的商店入口。
	var startup_settings_button: Button = main_instance.get_node("%MainMenuSettingsButton") as Button
	if startup_main_menu == null or not startup_main_menu.visible or startup_start_button.text != "开始游戏" or startup_settings_button.text != "设置" or match_controller.state != null:
		_fail("startup_main_menu")
		return
	# 本回归用例后续需要注入稳定快照并验证局内输入；隐藏启动覆盖层不触发开局，避免与人为快照混入真实选将流程。
	startup_main_menu.visible = false
	var ten_player_snapshot: Dictionary = _make_ten_player_snapshot()
	match_controller.state_changed.emit(ten_player_snapshot)
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
	# UI 风格选项；默认必须选中黑白太空，同时保留暖木十周年作为可切换项。
	# 当前默认显示名为“崩铁风格”，稳定 ID 仍为 `space_mono`，旧设置应直接映射到新版主题。
	# 暖木风格的设置显示名现为“暖木家园”，稳定 ID 继续沿用原值以兼容已有设置。
	var ui_style_option: OptionButton = main_instance.get_node("%UiStyleOption") as OptionButton
	# 卡牌名称选项；与UI风格下拉框共用完整悬停和弹出列表主题。
	var card_name_option: OptionButton = main_instance.get_node("%MenuCardNameOption") as OptionButton
	# 左上信息面板；切换风格后边框颜色必须立即跟随注册表更新，不需要重新开局。
	var top_info_panel: PanelContainer = main_instance.get_node("TopInfoPanel") as PanelContainer
	# 黑白太空背景遮罩；重新设计后不再用近黑覆盖层模拟滤镜，透明度必须为0。
	# 崩铁风格继续保持遮罩透明，参考图中的紫蓝毛玻璃地图不作为主题背景叠加到牌桌。
	var backdrop_shade: ColorRect = main_instance.get_node("BackdropShade") as ColorRect
	# 程序化背景组件；黑白太空风格不再绘制导航网格，只保留星点、轨道和远景剪影。
	# 崩铁风格关闭旧星点、山脊和建筑剪影，仅保留暖白桌面上的低透明度金色轨道纹样。
	var reference_backdrop: ReferenceBackdrop = main_instance.get_node("ReferenceBackdrop") as ReferenceBackdrop
	if GameSettings.ui_style_id != UIStyleRegistry.DEFAULT_STYLE_ID or ui_style_option.item_count != 2 or ui_style_option.get_item_text(0) != "崩铁风格" or ui_style_option.get_item_text(1) != "暖木家园" or str(ui_style_option.get_item_metadata(ui_style_option.selected)) != UIStyleRegistry.STYLE_SPACE_MONO or not (top_info_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, "border")) or not is_zero_approx(backdrop_shade.color.a) or bool(reference_backdrop.get("_uses_space_grid")) or bool(reference_backdrop.get("_uses_starfield")) or bool(reference_backdrop.get("_uses_scenery")) or not is_equal_approx(reference_backdrop.table_inset, 34.0) or not is_equal_approx(reference_backdrop.rail_width, 14.0):
		_fail("default_ui_style:%s/%d/%d" % [GameSettings.ui_style_id, ui_style_option.item_count, ui_style_option.selected])
		return
	# 黑白太空主题的主要界面语义键；这些颜色必须保持无色相黑白灰，玩法语义色由独立键保留。
	# 旧版纯黑白断言已由崩铁风格的分层配色断言替代；主题必须同时具备中性深色外底、雾面深灰内容区、黑框与金色强调。
	# 崩铁风格核心颜色期望；固定值用于阻止主题被误改回单色滤镜或失去参考图的视觉层级。
	var expected_style_colors: Dictionary = {
		"outer_background": Color("111214"),
		"outer_background_secondary": Color("111214"),
		"table_surface": Color("24262b"),
		"table_inner": Color("30333a"),
		"rail": Color("1d1d1d"),
		"border": Color("bfa86c"),
		"accent": Color("d4b55f"),
	}
	for primary_key: String in expected_style_colors:
		# 当前主要界面颜色；必须与参考图抽象出的主题语义色一致。
		var primary_color: Color = UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, primary_key)
		if not primary_color.is_equal_approx(expected_style_colors[primary_key] as Color):
			_fail("space_style_palette:%s/%s" % [primary_key, primary_color])
			return
	# 局内下拉框悬停样式；按钮本体与PopupMenu都必须使用当前主题，不能回退引擎默认皮肤。
	var card_name_hover_style: StyleBoxFlat = card_name_option.get_theme_stylebox("hover") as StyleBoxFlat
	# UI风格按钮悬停样式；与卡牌名称控件保持同一交互语义。
	var ui_style_hover_style: StyleBoxFlat = ui_style_option.get_theme_stylebox("hover") as StyleBoxFlat
	# 卡牌名称弹出列表悬停样式；选项行必须保留主题背景与强调边框。
	var card_name_popup_hover_style: StyleBoxFlat = card_name_option.get_popup().get_theme_stylebox("hover") as StyleBoxFlat
	# UI风格弹出列表悬停样式；切换主题后由同一入口即时重绘。
	var ui_style_popup_hover_style: StyleBoxFlat = ui_style_option.get_popup().get_theme_stylebox("hover") as StyleBoxFlat
	if card_name_hover_style == null or ui_style_hover_style == null or card_name_popup_hover_style == null or ui_style_popup_hover_style == null or not card_name_hover_style.bg_color.is_equal_approx(BattleUIStyle.get_color("action_button")) or not ui_style_hover_style.border_color.is_equal_approx(BattleUIStyle.get_color("accent")) or not card_name_popup_hover_style.bg_color.is_equal_approx(BattleUIStyle.get_color("action_button")) or not ui_style_popup_hover_style.border_color.is_equal_approx(BattleUIStyle.get_color("accent")):
		_fail("match_menu_option_hover_style")
		return
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_DECADE_WOOD)
	await get_tree().process_frame
	if str(ui_style_option.get_item_metadata(ui_style_option.selected)) != UIStyleRegistry.STYLE_DECADE_WOOD or not (top_info_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "border")) or is_zero_approx(backdrop_shade.color.a) or bool(reference_backdrop.get("_uses_space_grid")) or not is_equal_approx(reference_backdrop.table_inset, 18.0) or not is_equal_approx(reference_backdrop.rail_width, 14.0):
		_fail("ui_style_switch_to_wood")
		return
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_SPACE_MONO)
	await get_tree().process_frame
	# 底部装备面板；左下区域必须完整位于窗口客户区内。
	var equipment_panel: Control = main_instance.get_node("%EquipmentPanel") as Control
	# 当前装备面板固定为150×148像素，严格等于玩家手牌牌面高度，不包含175像素手牌栏的抬升留白。
	if not equipment_panel.size.is_equal_approx(Vector2(150.0, 148.0)):
		_fail("equipment_panel_size:%s" % equipment_panel.size)
		return
	# 底部手牌面板；其底边必须随窗口底部锚定，不能继续停留在固定720坐标。
	var hand_panel: Control = main_instance.get_node("HandPanel") as Control
	# 本地托管覆盖层；必须直属主场景，才能从手牌横向延伸到本地武将牌左侧。
	var auto_managed_hand_overlay: PlayerAutoManagedHandOverlay = main_instance.get_node("%AutoManagedHandOverlay") as PlayerAutoManagedHandOverlay
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
	# 当前测试改为验证注册表中的活动主题色，组件尺寸与交互语义保持原有要求。
	var end_play_normal_style: StyleBoxFlat = end_play_button.get_theme_stylebox("normal") as StyleBoxFlat
	# 确定按钮禁用样式；不可选择时固定为深灰，不沿用普通或悬停高亮。
	var confirm_disabled_style: StyleBoxFlat = confirm_button.get_theme_stylebox("disabled") as StyleBoxFlat
	# 确定按钮普通样式；用于验证禁用状态具有明确亮度差。
	var confirm_normal_style: StyleBoxFlat = confirm_button.get_theme_stylebox("normal") as StyleBoxFlat
	if interaction_panel.visible or not (interaction_panel.get_theme_stylebox("panel") is StyleBoxEmpty) or not confirm_button.custom_minimum_size.is_equal_approx(cancel_button.custom_minimum_size) or action_row.get_theme_constant("separation") != 28 or not end_play_button.custom_minimum_size.is_equal_approx(Vector2(112.0, 36.0)) or end_play_button.text != "结束阶段" or end_play_button.custom_minimum_size.x >= cancel_button.custom_minimum_size.x or cancel_button.get_global_rect().intersects(end_play_button.get_global_rect()) or not end_play_normal_style.bg_color.is_equal_approx(BattleUIStyle.get_color("end_play_button")) or confirm_normal_style.bg_color.get_luminance() - confirm_disabled_style.bg_color.get_luminance() < 0.1 or end_play_button.get_parent() != main_instance or end_play_button.visible or recast_button.visible:
		_fail("interaction_controls panel=%s end_parent=%s" % [interaction_panel.visible, end_play_button.get_parent().name])
		return
	# 手牌栏继续保留175像素抬升空间；装备栏只等于148像素牌面高度，二者底边对齐且横向边界精确相接。
	if not is_equal_approx(hand_panel.size.y, 175.0) or not is_equal_approx(equipment_panel.size.y, 148.0) or not is_equal_approx(equipment_panel.position.y + equipment_panel.size.y, hand_panel.position.y + hand_panel.size.y) or not is_equal_approx(equipment_panel.position.x + equipment_panel.size.x, hand_panel.position.x) or not hand_panel_style is StyleBoxEmpty:
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
	if not skill_bar.get_theme_stylebox("panel") is StyleBoxEmpty or skill_status_label.visible or skill_views.size() != 1 or first_skill_button == null or first_skill_button.text.length() > 2 or not is_equal_approx(hand_panel.position.x + hand_panel.size.x + 8.0, skill_bar.position.x) or not is_equal_approx(skill_bar.position.x + skill_bar.size.x + 6.0, (main_instance.get_node("LocalPlayerSeatSlot") as Control).position.x):
		_fail("skill_button_only_layout:%s/%s" % [skill_bar.get_rect(), first_skill_button.text if first_skill_button != null else "null"])
		return
	# 不可发动技能普通样式；测试武将为样例技能，因此按钮必须使用中性灰禁用外观。
	var skill_normal_style: StyleBoxFlat = first_skill_button.get_theme_stylebox("normal") as StyleBoxFlat
	# 不可发动技能悬停样式；颜色和边框必须与普通样式完全一致，不产生悬停反馈。
	var skill_hover_style: StyleBoxFlat = first_skill_button.get_theme_stylebox("hover") as StyleBoxFlat
	# 不可发动技能禁用样式；Button 实际绘制该状态，必须与普通灰显样式保持一致。
	var skill_disabled_style: StyleBoxFlat = first_skill_button.get_theme_stylebox("disabled") as StyleBoxFlat
	if not first_skill_button.disabled or not skill_normal_style.bg_color.is_equal_approx(skill_hover_style.bg_color) or not skill_normal_style.border_color.is_equal_approx(skill_hover_style.border_color) or not skill_normal_style.bg_color.is_equal_approx(skill_disabled_style.bg_color):
		_fail("skill_disabled_visual disabled=%s normal=%s hover=%s" % [first_skill_button.disabled, skill_normal_style.bg_color, skill_hover_style.bg_color])
		return
	first_skill_button.mouse_entered.emit()
	await get_tree().process_frame
	if information_box == null or not first_skill_button.tooltip_text.is_empty() or information_box.is_hover_information_visible():
		_fail("skill_information_shown_too_early:%s" % (information_box.get_hover_title_text() if information_box != null else "missing"))
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or not information_box.get_hover_title_text().contains(first_skill_button.text):
		_fail("skill_information:%s/%s" % [first_skill_button.tooltip_text, information_box.get_hover_title_text() if information_box != null else "missing"])
		return
	first_skill_button.mouse_exited.emit()
	await get_tree().process_frame
	# 动态技能牌名说明；原文使用崩铁杀【药】，切换三国杀名称后已打开的信息框必须立即显示【桃】。
	var skill_name_hover_delay_seconds: float = information_box.hover_display_delay_seconds
	information_box.hover_display_delay_seconds = 0.0
	GameSettings.set_card_name_mode(GameSettings.NameMode.CUSTOM)
	await get_tree().process_frame
	information_box.show_hover_information({"title":"【焕发】", "description":str(GameDatabase.get_skill("huanfa").get("description", ""))}, Rect2(Vector2(320.0, 240.0), Vector2(60.0, 40.0)), 990001)
	await get_tree().process_frame
	if not information_box.get_hover_description_text().contains("【药】"):
		_fail("skill_description_custom_name:%s" % information_box.get_hover_description_text())
		return
	GameSettings.set_card_name_mode(GameSettings.NameMode.ORIGINAL)
	await get_tree().process_frame
	await get_tree().process_frame
	if not information_box.get_hover_description_text().contains("【桃】") or information_box.get_hover_description_text().contains("【药】"):
		_fail("skill_description_original_name:%s" % information_box.get_hover_description_text())
		return
	information_box.hide_hover_information(990001)
	information_box.hover_display_delay_seconds = skill_name_hover_delay_seconds
	GameSettings.set_card_name_mode(GameSettings.NameMode.CUSTOM)
	await get_tree().process_frame
	# 技能点击错误区；直接调用处理入口模拟过期点击，不可发动技能必须保持静默。
	var error_label: Label = main_instance.get_node("%ErrorLabel") as Label
	error_label.text = ""
	main_instance.call("_on_skill_requested", first_skill_button.skill_id)
	if not error_label.text.is_empty():
		_fail("skill_unavailable_popup=%s" % error_label.text)
		return
	# 本地玩家座位容器；右下角区域必须使用右下锚点完整留在客户区内，并承载牌面下方的独立座次标签。
	var local_player_seat_slot: Control = main_instance.get_node("LocalPlayerSeatSlot") as Control
	# 托管覆盖层期望宽度；从手牌左侧开始，到本地武将牌左侧保留8像素安全间距。
	var expected_auto_managed_overlay_width: float = local_player_seat_slot.position.x - hand_panel.position.x - 8.0
	if auto_managed_hand_overlay == null or auto_managed_hand_overlay.get_parent() != main_instance or not is_equal_approx(auto_managed_hand_overlay.position.x, hand_panel.position.x) or not is_equal_approx(auto_managed_hand_overlay.position.y, hand_panel.position.y) or not is_equal_approx(auto_managed_hand_overlay.size.x, expected_auto_managed_overlay_width) or not is_equal_approx(auto_managed_hand_overlay.size.y, hand_panel.size.y) or auto_managed_hand_overlay.z_index >= skill_bar.z_index:
		_fail("auto_managed_overlay_layout=%s/%s/%d/%d" % [auto_managed_hand_overlay.get_rect() if auto_managed_hand_overlay != null else Rect2(), hand_panel.get_rect(), auto_managed_hand_overlay.z_index if auto_managed_hand_overlay != null else -1, skill_bar.z_index])
		return
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
	# 主视角移除座次标签后，容器只保留148.35×197.8像素武将牌本体。
	var local_seat_screen_rect: Rect2 = _screen_rect(local_player_seat_slot)
	if not local_seat_screen_rect.size.is_equal_approx(Vector2(148.35, 197.8)):
		_fail("local_seat_size:%s" % local_seat_screen_rect.size)
		return
	# 技能栏屏幕矩形；按钮区底边必须与本地武将牌底边严格平行。
	var skill_bar_screen_rect: Rect2 = _screen_rect(skill_bar)
	if not is_equal_approx(skill_bar_screen_rect.end.y, local_seat_screen_rect.end.y):
		_fail("skill_card_bottom_alignment:%s/%s" % [skill_bar_screen_rect.end.y, local_seat_screen_rect.end.y])
		return
	# 本地身份徽记；身份 UI 背景与边框必须为完全不透明，不保留半透明叠色。
	var identity_badge: Label = (main_instance.get("local_player_card") as PlayerTargetView).get_node("IdentityBadge") as Label
	# 身份徽记样式；StyleBoxFlat 的背景与边框 alpha 均应为1.0。
	var identity_style: StyleBoxFlat = identity_badge.get_theme_stylebox("normal") as StyleBoxFlat
	if not is_equal_approx(identity_style.bg_color.a, 1.0) or not is_equal_approx(identity_style.border_color.a, 1.0):
		_fail("identity_opacity:%s/%s" % [identity_style.bg_color.a, identity_style.border_color.a])
		return
	# 本地武将牌屏幕底部留白；默认0像素让十人局右侧下方座位保留完整安全区，不恢复已隐藏的主视角座次标签。
	var local_seat_bottom_margin: float = viewport_rect.end.y - local_seat_screen_rect.end.y
	if not is_equal_approx(local_seat_bottom_margin, 0.0) or not is_equal_approx(float(main_instance.get("local_player_card_bottom_margin")), 0.0):
		_fail("local_seat_bottom_margin:%s" % local_seat_bottom_margin)
		return
	# 本地座次标签；测试把本地玩家设为五号位，底部牌面必须显示对应中文座次。
	# 主视角不再显示座次号，标签节点仅作为通用座位场景兼容结构保留并保持隐藏。
	var local_seat_label: Label = local_player_seat_slot.get_node("Seat") as Label
	if local_seat_label.visible or not local_seat_label.text.is_empty():
		_fail("local_seat_label_visible:%s/%s" % [local_seat_label.visible, local_seat_label.text])
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
	# 当前五槽自适应高度；148像素按五槽均分为29.6像素，相邻槽不留任何距离。
	var local_adaptive_equipment_row_height: float = local_equipment_label.size.y / 5.0
	# 当前五槽节距；无覆盖且无间距时严格等于单槽高度。
	var local_equipment_row_pitch: float = local_adaptive_equipment_row_height - local_equipment_label.equipment_row_overlap + local_equipment_label.equipment_row_gap
	# 本地空进攻坐骑横条；五槽常驻布局中必须保留第三个等高槽位。
	var local_offensive_mount_row: Button = local_equipment_label.get_row("offensive_mount")
	# 本地空防御坐骑横条；五槽常驻布局中必须保留第四个等高槽位。
	var local_defensive_mount_row: Button = local_equipment_label.get_row("defensive_mount")
	if local_weapon_row == null or local_treasure_row == null or local_empty_armor_row == null or local_offensive_mount_row == null or local_defensive_mount_row == null:
		_fail("local_equipment_rows_missing")
		return
	# 当前五个固定装备槽；数组顺序用于逐段验证相邻空隙完全一致。
	var local_equipment_rows: Array[Button] = [local_weapon_row, local_empty_armor_row, local_offensive_mount_row, local_defensive_mount_row, local_treasure_row]
	# 当前相邻装备槽的实际空隙；全部四段都必须等于组件统一配置值。
	var local_equipment_gaps_are_equal: bool = true
	for equipment_row_index: int in range(local_equipment_rows.size() - 1):
		# 当前相邻装备槽实际间距；由下一槽顶边减去当前槽底边得到，不受槽高变化影响。
		var actual_equipment_gap: float = local_equipment_rows[equipment_row_index + 1].position.y - (local_equipment_rows[equipment_row_index].position.y + local_equipment_rows[equipment_row_index].size.y)
		if not is_equal_approx(actual_equipment_gap, local_equipment_label.equipment_row_gap):
			local_equipment_gaps_are_equal = false
			break
	if not is_equal_approx(local_weapon_row.size.y, local_adaptive_equipment_row_height) or not local_treasure_row.tooltip_text.is_empty() or not is_equal_approx(local_treasure_row.position.y - local_weapon_row.position.y, local_equipment_row_pitch * 4.0) or not is_equal_approx(local_weapon_row.position.y, 0.0) or not is_equal_approx(local_treasure_row.position.y + local_treasure_row.size.y, local_equipment_label.size.y) or not local_equipment_gaps_are_equal or local_equipment_label.is_slot_equipped("armor") or not local_empty_armor_row.disabled:
		_fail("local_equipment_stack:%s" % local_equipment_label.tooltip_text)
		return
	local_treasure_row.mouse_entered.emit()
	await get_tree().process_frame
	if information_box == null or information_box.is_hover_information_visible():
		_fail("local_equipment_information_shown_too_early:%s" % (information_box.get_hover_title_text() if information_box != null else "missing"))
		return
	await _wait_for_hover_information_delay()
	# 目标旁信息面板；按内容在240至520像素宽度内动态调整，并优先保持4:3比例且始终限制在当前客户区内。
	# 目标旁信息面板；按内容在240至520像素宽度内动态调整，并在可配的最小与最大比例内保持自然形状。
	var hover_information_panel: PanelContainer = information_box.get_node("HoverInformationPanel") as PanelContainer
	var hover_information_aspect_ratio: float = hover_information_panel.size.x / maxf(hover_information_panel.size.y, 1.0)
	if information_box == null or not information_box.is_hover_information_visible() or not information_box.get_hover_title_text().contains("货运星槎（3）") or hover_information_panel.size.x < information_box.hover_panel_minimum_width or hover_information_panel.size.x > information_box.hover_panel_maximum_width or hover_information_aspect_ratio < information_box.hover_panel_minimum_aspect_ratio or hover_information_aspect_ratio > information_box.hover_panel_maximum_aspect_ratio or not main_instance.get_global_rect().encloses(hover_information_panel.get_global_rect()) or not local_equipment_label.tooltip_text.is_empty():
		_fail("local_equipment_information:%s/%s ratio=%.3f limits=%.3f-%.3f bounds=%s main=%s panel=%s tooltip=%s" % [information_box.get_hover_title_text() if information_box != null else "missing", hover_information_panel.size if hover_information_panel != null else Vector2.ZERO, hover_information_aspect_ratio, information_box.hover_panel_minimum_aspect_ratio if information_box != null else -1.0, information_box.hover_panel_maximum_aspect_ratio if information_box != null else -1.0, main_instance.get_global_rect().encloses(hover_information_panel.get_global_rect()) if hover_information_panel != null else false, main_instance.get_global_rect(), hover_information_panel.get_global_rect() if hover_information_panel != null else Rect2(), local_equipment_label.tooltip_text])
		return
	local_treasure_row.mouse_exited.emit()
	await get_tree().process_frame
	if information_box.is_hover_information_visible():
		_fail("local_equipment_information_exit")
		return
	# 本地武将牌装备条；第一视角只通过左侧装备栏查看装备，武将牌自身不得重复显示横条。
	var local_player_card: PlayerTargetView = main_instance.get("local_player_card") as PlayerTargetView
	# 本地武将牌受伤反馈次数；首次快照只建立体力基线，不应在进入牌桌时抖动。
	var initial_damage_feedback_count: int = local_player_card.get_damage_feedback_playback_count()
	# 本地武将牌受伤前原始位置；单次冲击完成后必须精确恢复，不能留下布局偏移。
	var local_player_rest_position: Vector2 = local_player_card.position
	# 独立受伤反馈组件；当前配置必须固定为1次冲击位移，禁止恢复旧的多段往返抖动。
	var damage_feedback: DamageShakeFeedback = local_player_card.get_node("DamageShakeFeedback") as DamageShakeFeedback
	# 体力下降快照；只修改本地五号位1点体力，验证新牌面渲染后恰好触发一次独立反馈组件。
	var damaged_snapshot: Dictionary = ten_player_snapshot.duplicate(true)
	# 当前待修改玩家快照；只匹配稳定本地玩家 ID，不依赖座次数组下标。
	for damaged_player_variant: Variant in damaged_snapshot.get("players", []) as Array:
		# 当前玩家字典；命中本地玩家后只降低公开体力字段1点。
		var damaged_player: Dictionary = damaged_player_variant as Dictionary
		if int(damaged_player.get("player_id", -1)) == 4:
			damaged_player["hp"] = int(damaged_player.get("hp", 4)) - 1
			break
	match_controller.state_changed.emit(damaged_snapshot)
	await get_tree().process_frame
	if local_player_card.get_damage_feedback_playback_count() != initial_damage_feedback_count + 1 or damage_feedback.shake_step_count != 1:
		_fail("local_damage_feedback:%d/%d" % [initial_damage_feedback_count, local_player_card.get_damage_feedback_playback_count()])
		return
	await get_tree().create_timer(damage_feedback.shake_duration + 0.05).timeout
	if not local_player_card.position.is_equal_approx(local_player_rest_position):
		_fail("damage_feedback_position_not_restored:%s/%s" % [local_player_rest_position, local_player_card.position])
		return
	# 恢复原体力快照只属于测试对账，不应把体力上升误判为第二次受伤。
	match_controller.state_changed.emit(ten_player_snapshot)
	await get_tree().process_frame
	if local_player_card.get_damage_feedback_playback_count() != initial_damage_feedback_count + 1:
		_fail("damage_feedback_recover_repeat")
		return
	# 护盾吸收伤害快照；体力保持不变，但累计受伤次数递增时仍应播放一次受伤抖动。
	var shield_damage_snapshot: Dictionary = ten_player_snapshot.duplicate(true)
	for shield_damage_player_variant: Variant in shield_damage_snapshot.get("players", []) as Array:
		# 当前护盾受伤玩家快照；仅为本地玩家补充正式状态中的累计受伤次数字段。
		var shield_damage_player: Dictionary = shield_damage_player_variant as Dictionary
		if int(shield_damage_player.get("player_id", -1)) == 4:
			shield_damage_player["damage_taken_count"] = 1
			shield_damage_player["shield"] = 0
			break
	match_controller.state_changed.emit(shield_damage_snapshot)
	await get_tree().process_frame
	if local_player_card.get_damage_feedback_playback_count() != initial_damage_feedback_count + 2:
		_fail("shield_damage_feedback:%d" % local_player_card.get_damage_feedback_playback_count())
		return
	# 武将牌当前装备条数组；第一视角关闭公开装备绘制后应保持为空。
	var local_player_equipment_rows: Array = local_player_card.get("_equipment_rows") as Array
	# 武将牌当前装备槽位数组；关闭绘制后不保留任何视觉槽位索引。
	var local_player_equipment_slots: Array = local_player_card.get("_equipment_row_slots") as Array
	if not local_player_equipment_rows.is_empty() or not local_player_equipment_slots.is_empty():
		_fail("local_player_equipment_slots:%s" % [local_player_equipment_slots])
		return
	# 本地武将牌横置覆盖层；横置框应向两侧越出牌面，而覆盖层中间宽度仍以原武将牌尺寸为基准。
	var local_state_overlay: PlayerStateOverlay = local_player_card.get_node("StateOverlay") as PlayerStateOverlay
	local_state_overlay.configure(true, true)
	if local_state_overlay.position.x >= 0.0 or local_state_overlay.size.x <= local_player_card.card_size.x or not is_equal_approx(local_state_overlay.size.y, local_player_card.card_size.y) or not is_equal_approx(local_state_overlay.chained_outer_extension, 6.0) or not is_equal_approx(local_state_overlay.chained_outer_frame_height, 8.0) or not is_equal_approx(local_state_overlay.chained_inner_frame_inset, 1.0) or not is_equal_approx(local_state_overlay.chained_outer_border_width, 1.0) or not is_equal_approx(local_state_overlay.chained_inner_border_width, 1.0):
		_fail("chained_overlay_geometry:%s/%s/%s" % [local_state_overlay.position, local_state_overlay.size, local_player_card.card_size])
		return
	local_state_overlay.configure(true, false)
	# 本地武将牌悬停资料；第一视角同样必须在0.5秒后显示武将完整技能，不能只允许其他玩家牌面使用该入口。
	local_player_card.call("_on_input_mouse_entered")
	await get_tree().process_frame
	if information_box.is_hover_information_visible():
		_fail("local_player_information_shown_too_early:%s" % information_box.get_hover_title_text())
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or information_box.get_hover_title_text() != "杰帕德" or not information_box.get_hover_description_text().contains(str(GameDatabase.get_skill("yongyi").get("description", ""))) or not local_player_card.scale.is_equal_approx(Vector2.ONE):
		_fail("local_player_information:%s/%s" % [information_box.get_hover_description_text(), local_player_card.scale])
		return
	local_player_card.call("_on_input_mouse_exited")
	if information_box.is_hover_information_visible():
		_fail("local_player_information_exit")
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
	# 持久座位容器映射；键为稳定玩家 ID，可直接验证五号位视角下四张侧边牌的座次与几何位置。
	var player_seat_slots: Dictionary = main_instance.get("_player_seat_slots") as Dictionary
	# 左上三号位座位；五号位视角的环形顺序末段第一名应进入左侧上方。
	var seat_three_slot: Control = player_seat_slots.get(2) as Control
	# 左下四号位座位；五号位视角的环形顺序末段第二名应进入左侧下方。
	var seat_four_slot: Control = player_seat_slots.get(3) as Control
	# 右下六号位座位；五号位视角的下家应进入右侧下方。
	var seat_six_slot: Control = player_seat_slots.get(5) as Control
	# 右上七号位座位；五号位视角的下家下一位应进入右侧上方。
	var seat_seven_slot: Control = player_seat_slots.get(6) as Control
	if seat_three_slot == null or seat_four_slot == null or seat_six_slot == null or seat_seven_slot == null:
		_fail("ten_player_side_slot_missing:%s" % [player_seat_slots.keys()])
		return
	# 四张侧边牌的公开座次标签；验证稳定玩家 ID 与最终绝对座次没有在布局阶段发生交换。
	var seat_three_label: Label = seat_three_slot.get_node("Seat") as Label
	# 左下座位公开标签；应保留四号位文字而不是沿用相邻上方座位。
	var seat_four_label: Label = seat_four_slot.get_node("Seat") as Label
	# 右下座位公开标签；应保留六号位文字而不是沿用相邻上方座位。
	var seat_six_label: Label = seat_six_slot.get_node("Seat") as Label
	# 右上座位公开标签；应保留七号位文字而不是沿用相邻下方座位。
	var seat_seven_label: Label = seat_seven_slot.get_node("Seat") as Label
	# 左侧上下完整座位的实际间隔；使用缩放后的完整座位高度，确保牌面与座次标签都不发生重叠。
	var left_stacked_seat_gap: float = seat_four_slot.position.y - seat_three_slot.position.y - seat_three_slot.size.y * player_grid.ten_player_card_scale
	# 右侧上下完整座位的实际间隔；右侧也必须使用与左侧相同的紧凑间隔。
	var right_stacked_seat_gap: float = seat_six_slot.position.y - seat_seven_slot.position.y - seat_seven_slot.size.y * player_grid.ten_player_card_scale
	if seat_three_label == null or seat_four_label == null or seat_six_label == null or seat_seven_label == null or not is_equal_approx(player_grid.ten_player_card_scale, 0.9) or seat_three_label.text != "三" or seat_four_label.text != "四" or seat_six_label.text != "六" or seat_seven_label.text != "七" or not is_equal_approx(seat_three_slot.position.x, seat_four_slot.position.x) or not is_equal_approx(seat_six_slot.position.x, seat_seven_slot.position.x) or seat_three_slot.position.y >= seat_four_slot.position.y or seat_seven_slot.position.y >= seat_six_slot.position.y or not is_equal_approx(left_stacked_seat_gap, player_grid.ten_player_stacked_vertical_gap) or not is_equal_approx(right_stacked_seat_gap, player_grid.ten_player_stacked_vertical_gap):
		_fail("ten_player_side_seats:3=%s/4=%s/6=%s/7=%s positions=%s/%s/%s/%s scale=%s gaps=%s/%s" % [seat_three_label.text if seat_three_label != null else "", seat_four_label.text if seat_four_label != null else "", seat_six_label.text if seat_six_label != null else "", seat_seven_label.text if seat_seven_label != null else "", seat_three_slot.position, seat_four_slot.position, seat_six_slot.position, seat_seven_slot.position, player_grid.ten_player_card_scale, left_stacked_seat_gap, right_stacked_seat_gap])
		return
	# 当前回合角色牌；0号玩家必须保留3像素亮金边框，即使当前实际等待5号玩家操作。
	var current_turn_view: PlayerTargetView = player_views.get(0) as PlayerTargetView
	# 当前操作角色牌；5号玩家通过选择请求 actor 高亮，并与当前回合金边语义分离。
	var current_operator_view: PlayerTargetView = player_views.get(5) as PlayerTargetView
	# 当前回合角色最终面板样式；用于验证亮金边框颜色与3像素宽度。
	var current_turn_style: StyleBoxFlat = (current_turn_view.get_node("CardBody") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	# 当前操作角色最终面板样式；用于验证只提亮底色和边框，不再绘制青绿色外发光。
	var current_operator_style: StyleBoxFlat = (current_operator_view.get_node("CardBody") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	if not current_turn_view.is_current_actor or current_turn_view.is_current_operator or current_turn_style.border_color != BattleUIStyle.get_color("accent") or current_turn_style.border_width_left != 3 or current_operator_view.is_current_actor or not current_operator_view.is_current_operator or current_operator_style.shadow_color == Color("72d8b5aa"):
		_fail("player_operation_highlight")
		return
	# 全体目标牌交互状态；不可手动点选写入目标，但规则展开后的合法目标应亮起，非法目标进入暗置预览。
	# 本地人类为 0 号，当前操作角色为 5 号；展开仅含 5 时 5 合法且不暗置，0 非法且压暗。
	main_instance.set("_selected_card_uid", 999999)
	main_instance.set("_selected_target_ids", [])
	main_instance.set("_card_use_preview", {"target_mode":"all_others", "legal_target_ids":[], "normalized_target_ids":[5], "max_targets":99})
	main_instance.call("_refresh_component_states")
	main_instance.call("_on_target_pressed", 5)
	# 自动目标点击后的临时目标数组；必须保持为空并由规则层在提交时自行展开。
	var automatic_target_selection: Array = main_instance.get("_selected_target_ids") as Array
	# 本地玩家武将牌；群体预览下若不在展开列表中应非法且压暗（避免与外层已有 local_player_card 变量名冲突）。
	var self_target_view: PlayerTargetView = main_instance.get("local_player_card") as PlayerTargetView
	if not automatic_target_selection.is_empty() or current_operator_view.is_target_selected or not current_operator_view.is_legal_target or not current_operator_view.is_target_selection_active or self_target_view == null or self_target_view.is_legal_target or not self_target_view.is_target_selection_active or self_target_view.modulate == Color.WHITE or current_operator_view.modulate != Color.WHITE:
		_fail("automatic_target_preview_dim:%s legal5=%s dim5=%s legal0=%s dim0=%s selection_active=%s" % [automatic_target_selection, current_operator_view.is_legal_target, current_operator_view.modulate, self_target_view.is_legal_target if self_target_view != null else false, self_target_view.modulate if self_target_view != null else Color.TRANSPARENT, current_operator_view.is_target_selection_active])
		return
	main_instance.set("_selected_card_uid", -1)
	main_instance.set("_card_use_preview", {})
	main_instance.call("_refresh_component_states")
	# 其他玩家武将牌悬停资料；正式对局立即显示玩家名阴影，不显示原生工具提示，并在0.5秒后通过统一信息框显示完整技能。
	var hover_name_shade: TextureRect = current_operator_view.get_node("HoverNameShade") as TextureRect
	current_operator_view.call("_on_input_mouse_entered")
	# 当前悬停武将定义；用于逐项验证武将名、势力、性别、体力上限和全部技能均来自静态内容数据。
	var hovered_character_definition: Dictionary = GameDatabase.get_character("gepard")
	# 当前悬停武将首个技能定义；测试武将只有一个技能，可同时验证技能名与完整描述。
	var hovered_character_skill: Dictionary = GameDatabase.get_skill(str((hovered_character_definition.get("skills", []) as Array)[0]))
	if not hover_name_shade.visible or not (current_operator_view.get_node("InputArea") as Control).tooltip_text.is_empty() or information_box.is_hover_information_visible():
		_fail("player_hover_shown_too_early:%s" % hover_name_shade.visible)
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or information_box.get_hover_title_text() != "杰帕德" or not information_box.get_hover_description_text().contains(str(hovered_character_skill.get("description", ""))):
		_fail("player_hover_information:%s" % information_box.get_hover_description_text())
		return
	# 武将悬停标题标签；武将名必须使用与右键详情技能名一致的主题金色，而普通卡牌标题仍可保持主文字色。
	var hovered_character_title_label: Label = information_box.get("_hover_title_label") as Label
	# 武将悬停结构化技能名标签；测试武将只有一个技能，应只创建一个金色技能名标签。
	var hovered_character_skill_name_labels: Array = information_box.get("_hover_skill_name_labels") as Array
	if hovered_character_title_label == null or hovered_character_title_label.get_theme_color("font_color") != BattleUIStyle.get_color("accent") or hovered_character_skill_name_labels.size() != 1 or (hovered_character_skill_name_labels[0] as Label).get_theme_color("font_color") != BattleUIStyle.get_color("accent"):
		_fail("player_hover_accent_colors:%s/%s" % [hovered_character_title_label.get_theme_color("font_color") if hovered_character_title_label != null else Color.TRANSPARENT, (hovered_character_skill_name_labels[0] as Label).get_theme_color("font_color") if hovered_character_skill_name_labels.size() == 1 else Color.TRANSPARENT])
		return
	# 重复武将资料请求；公开快照刷新期间同来源同内容必须保持可见，不能隐藏后重新等待0.5秒造成闪烁。
	current_operator_view.call("_request_character_information")
	# 悬停延迟计时器；幂等请求不应重新启动共享计时器。
	var repeated_hover_delay_timer: Timer = information_box.get("_hover_delay_timer") as Timer
	if not information_box.is_hover_information_visible() or repeated_hover_delay_timer == null or not repeated_hover_delay_timer.is_stopped():
		_fail("player_hover_repeated_request_flicker:%s/%s" % [information_box.is_hover_information_visible(), repeated_hover_delay_timer.is_stopped() if repeated_hover_delay_timer != null else false])
		return
	# 其他玩家公开装备横条；透明武将牌输入层按局部坐标识别装备，并把目标牌说明交给统一信息框。
	var opponent_equipment_rows: Array = current_operator_view.get("_equipment_rows") as Array
	if opponent_equipment_rows.is_empty():
		_fail("opponent_equipment_information_missing_row")
		return
	# 当前对手武器横条；测试快照只为该玩家配置一张武器，因此首项就是目标牌。
	var opponent_weapon_row: RichTextLabel = opponent_equipment_rows[0] as RichTextLabel
	current_operator_view.call("_on_input_pointer_moved", opponent_weapon_row.position + opponent_weapon_row.size * 0.5)
	await get_tree().process_frame
	if information_box.is_hover_information_visible():
		_fail("opponent_equipment_information_shown_too_early:%s" % information_box.get_hover_title_text())
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or not information_box.get_hover_title_text().contains("碎星斩舰刀 2"):
		_fail("opponent_equipment_information:%s" % information_box.get_hover_title_text())
		return
	# 指针移出公开装备横条但仍停留在武将牌内时，统一信息框先隐藏装备，完整等待后恢复该武将资料。
	current_operator_view.call("_on_input_pointer_moved", Vector2(70.0, 50.0))
	await get_tree().process_frame
	if information_box.is_hover_information_visible():
		_fail("player_information_restore_shown_too_early:%s" % information_box.get_hover_title_text())
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or information_box.get_hover_title_text() != "杰帕德" or not information_box.get_hover_description_text().contains(str(hovered_character_skill.get("description", ""))):
		_fail("player_information_restore:%s" % information_box.get_hover_description_text())
		return
	current_operator_view.call("_on_input_mouse_exited")
	if hover_name_shade.visible or information_box.is_hover_information_visible():
		_fail("player_hover_exit")
		return
	# 悬停框首帧闪现回归：整体透明度必须继承到标题和技能文字，禁止子节点在默认位置短暂绘制。
	var original_hover_delay_seconds: float = information_box.hover_display_delay_seconds
	information_box.hover_display_delay_seconds = 0.0
	information_box.show_hover_information({"title":"首帧位置回归", "description":"布局前不应显示。"}, Rect2(Vector2(42.0, 42.0), Vector2(80.0, 80.0)), current_operator_view.get_instance_id())
	# 当前悬停面板及标题标签；面板必须使用会继承给文字子节点的 modulate 属性，而非 self_modulate。
	var pre_layout_hover_panel: PanelContainer = information_box.get_node("HoverInformationPanel") as PanelContainer
	var pre_layout_hover_title: Label = information_box.get("_hover_title_label") as Label
	if pre_layout_hover_panel == null or pre_layout_hover_title == null or not pre_layout_hover_panel.visible or not is_zero_approx(pre_layout_hover_panel.modulate.a):
		_fail("player_hover_pre_layout_flash:%s/%s" % [pre_layout_hover_panel.visible if pre_layout_hover_panel != null else false, pre_layout_hover_panel.modulate.a if pre_layout_hover_panel != null else -1.0])
		return
	await get_tree().process_frame
	if not information_box.is_hover_information_visible() or not is_equal_approx(pre_layout_hover_panel.modulate.a, 1.0):
		_fail("player_hover_post_layout_visibility:%s/%s" % [information_box.is_hover_information_visible(), pre_layout_hover_panel.modulate.a])
		return
	# 短说明最终宽度；再等待1帧让二次边界收紧完成，作为长说明的动态宽度对照。
	await get_tree().process_frame
	var compact_hover_width: float = pre_layout_hover_panel.size.x
	information_box.hide_hover_information(current_operator_view.get_instance_id())
	# 长说明请求；使用显式长文本验证信息框会扩宽，不依赖某张卡牌当前翻译长度。
	information_box.show_hover_information({"title":"动态宽度回归", "description":"这是一段用于验证悬停信息框动态宽度的较长说明文本。面板应根据实际文字量适度扩宽，同时受最小和最大宽高比限制，不再固定为四比三，也不应形成过窄过高或过宽过矮的异常形状。"}, Rect2(Vector2(42.0, 42.0), Vector2(80.0, 80.0)), current_operator_view.get_instance_id())
	await get_tree().process_frame
	await get_tree().process_frame
	# 长说明最终宽度与比例；宽度必须大于短文本，比例仍保持在组件声明的安全范围内。
	var expanded_hover_width: float = pre_layout_hover_panel.size.x
	var expanded_hover_aspect_ratio: float = expanded_hover_width / maxf(pre_layout_hover_panel.size.y, 1.0)
	if expanded_hover_width <= compact_hover_width or expanded_hover_aspect_ratio < information_box.hover_panel_minimum_aspect_ratio or expanded_hover_aspect_ratio > information_box.hover_panel_maximum_aspect_ratio:
		_fail("hover_dynamic_width compact=%.2f expanded=%.2f ratio=%.3f" % [compact_hover_width, expanded_hover_width, expanded_hover_aspect_ratio])
		return
	information_box.hide_hover_information(current_operator_view.get_instance_id())
	information_box.hover_display_delay_seconds = original_hover_delay_seconds
	# 武将牌右键事件；保留一个临时选牌 UID，用于确认武将输入组件消费按下与释放后不会触发牌桌右键取消。
	main_instance.set("_selected_card_uid", 999999)
	await _right_click_control(current_operator_view.get_node("InputArea") as Control)
	# 居中详情面板；其中心必须与当前紧凑客户区中心一致，短技能内容会自动收紧高度而不沿固定1280×720坐标偏移。
	var character_details_panel: PanelContainer = information_box.get_node("CharacterDetailsPanel") as PanelContainer
	# 武将详情标题标签；左右对称占位后，其全局中心必须与整个详情面板中心一致。
	var character_details_title: Label = information_box.get_character_title_label()
	# 单技能详情条目；短内容必须位于滚动视口中部，不能继续贴住右侧区域顶边。
	var single_skill_entry: Control = information_box.get_character_skill_list().get_child(0) as Control
	# 详情左侧武将牌区域；区域高度改变时正式牌面必须按自身缩放后尺寸持续上下居中。
	var character_card_area: Control = character_details_panel.find_child("CharacterCardArea", true, false) as Control
	# 详情左侧正式武将牌；只读复用的牌面位置由 InformationBoxLayer 在区域尺寸变化时重新居中。
	var detail_character_card: PlayerTargetView = information_box.get("_character_card_view") as PlayerTargetView
	# 技能区右侧边距容器；滚动条应与详情面板右边框保持检查器配置的额外留白。
	var character_skill_right_margin: MarginContainer = information_box.get("_character_skill_margin") as MarginContainer
	# 单技能详情牌面缩放后的尺寸；与区域实际尺寸共同计算期望的上下居中位置。
	var detail_character_card_size: Vector2 = detail_character_card.card_size * information_box.character_card_scale if detail_character_card != null else Vector2.ZERO
	# 单技能详情牌面期望位置；公式与运行时组件一致，便于验证高度变动后的纵向居中不依赖固定偏移。
	var expected_detail_character_position: Vector2 = (character_card_area.size - detail_character_card_size) * 0.5 if character_card_area != null else Vector2.ZERO
	# 单技能详情当前自动计算出的紧凑高度；多技能详情必须在后续断言中随内容增加而扩展。
	var single_skill_details_height: float = character_details_panel.size.y
	# 第一个技能名所在条目到面板上边框的距离；包含固定标题栏与标题到主体的间距。
	var single_skill_top_gap: float = single_skill_entry.get_global_rect().position.y - character_details_panel.get_global_rect().position.y
	# 最后一行文字所在条目到面板下边框的距离；底部对称留白应使其与上方距离一致。
	var single_skill_bottom_gap: float = character_details_panel.get_global_rect().end.y - single_skill_entry.get_global_rect().end.y
	if character_skill_right_margin == null or not is_equal_approx(float(character_skill_right_margin.get_theme_constant("margin_right")), information_box.character_skill_right_margin):
		_fail("character_details_right_margin:%s/%s" % [character_skill_right_margin.get_theme_constant("margin_right") if character_skill_right_margin != null else -1, information_box.character_skill_right_margin])
		return
	if not information_box.is_character_details_visible() or information_box.get_character_title_text() != "武将详情" or not is_equal_approx(character_details_panel.size.x, 760.0) or character_details_panel.size.y >= 440.0 or character_details_panel.size.y < information_box.character_panel_minimum_height or not character_details_panel.get_global_rect().get_center().is_equal_approx(main_instance.get_global_rect().get_center()) or not is_equal_approx(character_details_title.get_global_rect().get_center().x, character_details_panel.get_global_rect().get_center().x) or not information_box.get_character_card_scale().is_equal_approx(Vector2.ONE * 0.78) or information_box.get_character_skill_entry_count() != 1 or information_box.get_character_skill_separator_count() != 0 or single_skill_entry.position.y <= 0.0 or not is_equal_approx(single_skill_top_gap, single_skill_bottom_gap) or character_card_area == null or detail_character_card == null or not detail_character_card.position.is_equal_approx(expected_detail_character_position) or information_box.get_character_skill_scroll_bar() == null or not is_equal_approx(information_box.get_character_skill_scroll_bar().custom_minimum_size.x, 12.0) or int(main_instance.get("_selected_card_uid")) != 999999 or not get_tree().paused or not bool(main_instance.get("_owns_character_details_pause")) or int(main_instance.get("_character_details_pause_token")) < 0:
		_fail("character_details_open:%s/%s/%d/%s size=%s min=%s center=%s/%s title=%s/%s scale=%s separators=%d entry_y=%s gaps=%s/%s scrollbar=%s/%s selected=%d pause=%s/%s token=%d" % [information_box.is_character_details_visible(), information_box.get_character_title_text(), information_box.get_character_skill_entry_count(), get_tree().paused, character_details_panel.size, information_box.character_panel_minimum_height, character_details_panel.get_global_rect().get_center(), main_instance.get_global_rect().get_center(), character_details_title.get_global_rect().get_center().x, character_details_panel.get_global_rect().get_center().x, information_box.get_character_card_scale(), information_box.get_character_skill_separator_count(), single_skill_entry.position.y, single_skill_top_gap, single_skill_bottom_gap, information_box.get_character_skill_scroll_bar(), information_box.get_character_skill_scroll_bar().custom_minimum_size.x if information_box.get_character_skill_scroll_bar() != null else -1.0, int(main_instance.get("_selected_card_uid")), bool(main_instance.get("_owns_character_details_pause")), int(main_instance.get("_character_details_pause_token")) >= 0, int(main_instance.get("_character_details_pause_token"))])
		return
	# 多技能武将定义；布洛妮娅拥有3个静态技能，应在相邻技能之间创建正好2条主题横线。
	var bronya_definition: Dictionary = GameDatabase.get_character("bronya")
	# 多技能详情快照；只替换当前测试武将 ID 和静态体力，不改变公开玩家或暂停所有权。
	var bronya_snapshot: Dictionary = ((ten_player_snapshot.get("players", []) as Array)[5] as Dictionary).duplicate(true)
	bronya_snapshot["character_id"] = "bronya"
	bronya_snapshot["hp"] = int(bronya_definition.get("max_hp", 3))
	bronya_snapshot["max_hp"] = int(bronya_definition.get("max_hp", 3))
	information_box.show_character_details(bronya_snapshot, bronya_definition, GameDatabase.get_faction(str(bronya_definition.get("faction", ""))))
	await get_tree().process_frame
	await get_tree().process_frame
	# 多技能详情最新牌面；面板增加高度后仍必须在左侧可用区域上下居中。
	detail_character_card = information_box.get("_character_card_view") as PlayerTargetView
	detail_character_card_size = detail_character_card.card_size * information_box.character_card_scale if detail_character_card != null else Vector2.ZERO
	expected_detail_character_position = (character_card_area.size - detail_character_card_size) * 0.5 if character_card_area != null else Vector2.ZERO
	if information_box.get_character_skill_entry_count() != 3 or information_box.get_character_skill_separator_count() != 2 or character_details_panel.size.y <= single_skill_details_height or character_details_panel.size.y > information_box.character_panel_size.y or character_card_area == null or character_card_area.size.y <= detail_character_card_size.y or detail_character_card == null or not detail_character_card.position.is_equal_approx(expected_detail_character_position):
		_fail("character_details_separators:%d/%d/%s" % [information_box.get_character_skill_entry_count(), information_box.get_character_skill_separator_count(), character_details_panel.size.y])
		return
	await _click_control(information_box.get_character_close_button())
	if information_box.is_character_details_visible() or get_tree().paused or bool(main_instance.get("_owns_character_details_pause")) or int(main_instance.get("_character_details_pause_token")) >= 0:
		_fail("character_details_close:%s/%s close=%s visible=%s filter=%s disabled=%s process=%s hovered=%s" % [information_box.is_character_details_visible(), get_tree().paused, _screen_rect(information_box.get_character_close_button()), information_box.get_character_close_button().is_visible_in_tree(), information_box.get_character_close_button().mouse_filter, information_box.get_character_close_button().disabled, information_box.get_character_close_button().process_mode, get_viewport().gui_get_hovered_control()])
		return
	main_instance.set("_selected_card_uid", -1)
	# 同时无懈公共高亮；全部十名玩家都进入操作状态，不能只高亮实际持有无懈候选的角色。
	var simultaneous_snapshot: Dictionary = ten_player_snapshot.duplicate(true)
	simultaneous_snapshot["simultaneous_response_display"] = {"kind":"trick_negation", "round_id":1, "responder_ids":[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "target_id":0, "trick_id":"wugu"}
	match_controller.state_changed.emit(simultaneous_snapshot)
	await get_tree().process_frame
	for simultaneous_view_variant: Variant in (main_instance.get("_player_views") as Dictionary).values():
		# 当前对手武将牌；无论私有候选数量如何都必须显示统一操作高亮。
		var simultaneous_view: PlayerTargetView = simultaneous_view_variant as PlayerTargetView
		if not simultaneous_view.is_current_operator:
			_fail("simultaneous_operator_highlight:%d" % simultaneous_view.player_id)
			return
	if not (main_instance.get("local_player_card") as PlayerTargetView).is_current_operator:
		_fail("simultaneous_local_highlight")
		return
	match_controller.state_changed.emit(ten_player_snapshot)
	await get_tree().process_frame
	# 身份标注菜单；未知、忠臣、反贼和内奸都只显示单字简写。
	var identity_mark_menu: PopupMenu = main_instance.get("_identity_mark_menu") as PopupMenu
	# 身份标注菜单文本；顺序固定为清除推测、忠臣、反贼和内奸。
	var identity_mark_menu_texts: Array[String] = []
	for identity_mark_menu_index: int in range(identity_mark_menu.item_count):
		identity_mark_menu_texts.append(identity_mark_menu.get_item_text(identity_mark_menu_index))
	if identity_mark_menu_texts != ["?", "忠", "反", "内"]:
		_fail("identity_mark_menu_texts:%s" % [identity_mark_menu_texts])
		return
	# 自动身份标记设置；默认开启并使用复选框呈现，二元配置不通过普通文字按钮模拟。
	var auto_identity_marking_checkbox: CheckBox = main_instance.get_node("%AutoIdentityMarkingCheckBox") as CheckBox
	if not auto_identity_marking_checkbox.button_pressed or not GameSettings.auto_identity_marking_enabled:
		_fail("auto_identity_mark_default")
		return
	# 自动标记使用的权威观察快照；真实身份只交给共享身份模型，牌桌当前公开快照仍保持hidden。
	var identity_observation_snapshot: Dictionary = _make_ten_player_snapshot()
	identity_observation_snapshot["match_id"] = "ui-auto-identity-mark"
	for observed_player_variant: Variant in identity_observation_snapshot.get("players", []) as Array:
		# 当前权威观察角色；本循环只修改深复制测试快照，不接触牌桌公开快照。
		var observed_player: Dictionary = observed_player_variant as Dictionary
		# 当前观察角色稳定 ID；0号为公开领袖，5号为隐藏反贼，其余身份只用于补全标准身份态度关系。
		var observed_player_id: int = int(observed_player.get("player_id", -1))
		observed_player["identity"] = "leader" if observed_player_id == 0 else ("rebel" if observed_player_id == 5 else "loyalist")
		observed_player["identity_revealed"] = observed_player_id == 0
		observed_player["out_of_game"] = false
	# 5号隐藏角色公开对领袖使用【杀】；单目标-0.2忠反信号应立即形成反贼倾向标记。
	match_controller.ai_coordinator.observe_card_use(identity_observation_snapshot, 5, GameDatabase.get_card("sha"), [0])
	# 自动身份徽记；推断只存在共享模型中，不得写入手动标注字典或公开身份快照。
	var marked_identity_badge: Label = current_operator_view.get_node("IdentityBadge") as Label
	# 自动标记目标的公开玩家快照；其身份必须继续保持hidden，证明模型没有覆盖界面状态。
	var observed_public_player: Dictionary = (ten_player_snapshot.get("players", []) as Array)[5] as Dictionary
	if marked_identity_badge.text != "反" or marked_identity_badge.get_theme_color("font_color") != BattleUIStyle.get_color("identity_rebel") or (main_instance.get("_identity_marks") as Dictionary).has(5) or str(observed_public_player.get("identity", "")) != "hidden":
		_fail("automatic_identity_mark:%s" % marked_identity_badge.text)
		return
	# 关闭自动标记后立即恢复未知徽记；模型观察结果继续保留，重新开启时无需重算历史行为。
	auto_identity_marking_checkbox.button_pressed = false
	await get_tree().process_frame
	if GameSettings.auto_identity_marking_enabled or marked_identity_badge.text != "?":
		_fail("automatic_identity_mark_disabled:%s" % marked_identity_badge.text)
		return
	# 未知身份本地标注；选择反贼后只改变当前客户端徽记，不修改快照中的 hidden 身份。
	main_instance.call("_on_identity_badge_pressed", 5)
	main_instance.call("_on_identity_mark_selected", 1)
	# 已标注身份徽记；用于验证本地推测文本与标注字典同步。
	if marked_identity_badge.text != "反" or marked_identity_badge.get_theme_color("font_color") != BattleUIStyle.get_color("identity_rebel") or str((main_instance.get("_identity_marks") as Dictionary).get(5, "")) != "rebel":
		_fail("identity_local_mark:%s" % marked_identity_badge.text)
		return
	# 本地内奸标记；身份文字使用蓝色，且仍不修改公开快照。
	current_operator_view.set_identity_mark("renegade")
	if marked_identity_badge.text != "内" or marked_identity_badge.get_theme_color("font_color") != BattleUIStyle.get_color("identity_renegade"):
		_fail("identity_renegade_color:%s/%s" % [marked_identity_badge.text, marked_identity_badge.get_theme_color("font_color")])
		return
	current_operator_view.set_identity_mark("rebel")
	# 清除身份本地标注；重新选择问号后删除字典记录并恢复未知徽记。
	main_instance.call("_on_identity_badge_pressed", 5)
	main_instance.call("_on_identity_mark_selected", 3)
	if marked_identity_badge.text != "?" or (main_instance.get("_identity_marks") as Dictionary).has(5):
		_fail("identity_mark_reset:%s" % marked_identity_badge.text)
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
	if marked_identity_badge.text != "忠" or marked_identity_badge.get_theme_color("font_color") != BattleUIStyle.get_color("identity_loyalist"):
		_fail("identity_reveal_priority:%s" % marked_identity_badge.text)
		return
	# 公开领袖身份徽记；固定使用红色阵营字体。
	var leader_identity_badge: Label = (player_views.get(0) as PlayerTargetView).get_node("IdentityBadge") as Label
	if leader_identity_badge.text != "领" or leader_identity_badge.get_theme_color("font_color") != BattleUIStyle.get_color("identity_leader"):
		_fail("identity_leader_color:%s/%s" % [leader_identity_badge.text, leader_identity_badge.get_theme_color("font_color")])
		return
	# 恢复默认自动标记设置，避免本用例后续菜单和重复渲染检查继承关闭状态。
	auto_identity_marking_checkbox.button_pressed = true
	await get_tree().process_frame
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
	# 正式选将组件；无领袖快照时候选区域应直接占用左侧空位，不保留不可见领袖占位。
	var character_selection_panel: CharacterSelectionPanel = main_instance.get_node("%CharacterSelectionPanel") as CharacterSelectionPanel
	# 无领袖选将快照；两张候选足以验证左对齐、悬停缩放与点击高亮语义。
	var selection_snapshot_without_leader: Dictionary = {
		"phase":CharacterSelectionService.PHASE_OTHERS,
		"can_select":true,
		"local_identity":"rebel",
		"local_candidates":["gepard", "march_7th"],
		"leader_character_id":"",
		"leader_player_id":0,
	}
	character_selection_panel.bind_snapshot(selection_snapshot_without_leader)
	await get_tree().process_frame
	if character_selection_panel.get_title_plain_text() != "你的身份为：反贼，请选择武将" or character_selection_panel.get_title_identity_color() != BattleUIStyle.get_color("identity_rebel"):
		_fail("selection_identity_title:%s/%s" % [character_selection_panel.get_title_plain_text(), character_selection_panel.get_title_identity_color()])
		return
	# 候选区域与领袖区域；无领袖时两者左边界应完全一致，分隔线保持隐藏。
	var candidate_area: Control = character_selection_panel.get_node("SelectionFrame/CharacterCandidateArea") as Control
	# 领袖只读区域；无领袖时其左边界成为候选区新的左对齐基准。
	var leader_area: Control = character_selection_panel.get_node("SelectionFrame/LeaderCharacterArea") as Control
	# 领袖竖向分隔线；无领袖时隐藏，有领袖时显示。
	var leader_divider: ColorRect = character_selection_panel.get_node("SelectionFrame/LeaderDivider") as ColorRect
	if not is_equal_approx(candidate_area.position.x, leader_area.position.x) or leader_divider.visible:
		_fail("selection_without_leader_partition:%s/%s" % [candidate_area.position.x, leader_divider.visible])
		return
	# 当前候选视图；第一张用于悬停缩放，第二张用于确认未选牌不会获得合法目标发光。
	var candidate_views: Dictionary = character_selection_panel.get("_candidate_views") as Dictionary
	# 第一张候选武将牌；承担悬停缩放与点击选中断言。
	var first_candidate: PlayerTargetView = candidate_views.get("gepard") as PlayerTargetView
	# 第二张候选武将牌；承担未选状态不发光断言。
	var second_candidate: PlayerTargetView = candidate_views.get("march_7th") as PlayerTargetView
	first_candidate.call("_on_input_mouse_entered")
	await get_tree().create_timer(0.18).timeout
	if first_candidate.scale.x <= 1.0 or information_box.is_hover_information_visible():
		_fail("selection_hover_scale:%s" % first_candidate.scale)
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or information_box.get_hover_title_text() != "杰帕德" or not information_box.get_hover_description_text().contains(str(hovered_character_skill.get("description", ""))):
		_fail("selection_hover_information:%s" % information_box.get_hover_title_text())
		return
	first_candidate.call("_on_input_mouse_exited")
	await get_tree().create_timer(0.18).timeout
	if not first_candidate.scale.is_equal_approx(Vector2.ONE) or information_box.is_hover_information_visible():
		_fail("selection_hover_restore:%s" % first_candidate.scale)
		return
	# 第一张候选的布局位置；点击高亮只能修改边框，不能重置动态候选的坐标。
	var first_candidate_position_before_selection: Vector2 = first_candidate.position
	# 第二张候选的布局位置；用于防止其他候选在点击首张后被意外移动到原点。
	var second_candidate_position_before_selection: Vector2 = second_candidate.position
	character_selection_panel.call("_select_candidate", "gepard")
	if not first_candidate.is_target_selected or first_candidate.is_legal_target or second_candidate.is_target_selected or second_candidate.is_legal_target or not first_candidate.position.is_equal_approx(first_candidate_position_before_selection) or not second_candidate.position.is_equal_approx(second_candidate_position_before_selection):
		_fail("selection_click_glow_or_position_scope:%s/%s expected=%s/%s" % [first_candidate.position, second_candidate.position, first_candidate_position_before_selection, second_candidate_position_before_selection])
		return
	# 有领袖选将快照；领袖牌缩小并显示竖线，候选区域恢复到分隔线右侧。
	var selection_snapshot_with_leader: Dictionary = selection_snapshot_without_leader.duplicate(true)
	selection_snapshot_with_leader["leader_character_id"] = "natasha"
	character_selection_panel.bind_snapshot(selection_snapshot_with_leader)
	await get_tree().process_frame
	# 缩小后的领袖武将牌；缩放值必须读取组件公开配置并保持只读。
	var leader_character_view: PlayerTargetView = character_selection_panel.get("_leader_character_view") as PlayerTargetView
	if leader_character_view == null or not is_equal_approx(leader_character_view.scale.x, character_selection_panel.leader_character_scale) or not leader_divider.visible or candidate_area.position.x <= leader_area.position.x:
		_fail("selection_leader_partition")
		return
	leader_character_view.call("_on_input_mouse_entered")
	await get_tree().process_frame
	if information_box.is_hover_information_visible():
		_fail("selection_leader_information_shown_too_early:%s" % information_box.get_hover_title_text())
		return
	await _wait_for_hover_information_delay()
	if not information_box.is_hover_information_visible() or information_box.get_hover_title_text() != "娜塔莎":
		_fail("selection_leader_information:%s" % information_box.get_hover_title_text())
		return
	leader_character_view.call("_on_input_mouse_exited")
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
	# 缺失座位的玩家转移；表现层不得把未知玩家锚点回退到中央窗口中上部。
	var missing_anchor_card_data: Dictionary = {"uid":90990, "definition_id":"sha", "suit":"spade", "rank":9, "zone":"draw_pile", "owner_id":-1}
	main_instance.call("_on_card_transfer_requested", missing_anchor_card_data, -1, "draw_pile", 999, "hand")
	# 缺失来源座位的使用牌表现；必须在取得 UID 所有权前被拒绝，避免留下无法收尾的中央牌面。
	var missing_anchor_presentation: Dictionary = {"presentation_id":90, "event_id":90, "event_name":"useCard", "card_data":missing_anchor_card_data, "actor_id":999, "target_ids":[], "source_zone":"processing", "owns_discard_transfer":true}
	main_instance.call("_on_card_presentation_requested", missing_anchor_presentation)
	if not animation_layer._active_cards.is_empty() or not animation_layer._transfer_cards.is_empty() or animation_layer._discard_transfer_claims.has(90990):
		_fail("missing_anchor_created_central_card")
		return
	if animation_layer.z_index != 30:
		_fail("animation_layer_z:%d" % animation_layer.z_index)
		return
	animation_layer.card_flight_duration = 0.01
	animation_layer.card_hold_duration = 0.01
	animation_layer.target_line_draw_duration = 0.01
	animation_layer.target_line_fade_duration = 0.01
	animation_layer.draw_flight_duration = 0.01
	animation_layer.draw_hold_duration = 0.01
	animation_layer.draw_fade_duration = 0.01
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
	# 当前真实使用牌节点；响应等待期间会继续留在中央队列，鼠标离开不得把其纵坐标重置到窗口顶部。
	var presented_use_card: CardView = animation_layer._active_cards[0] as CardView
	await get_tree().create_timer(SHORT_TWEEN_SETTLE_SECONDS).timeout
	# 当前中央队列目标位置；飞行结束后牌面必须精确停在该位置，而不是来源玩家座位。
	var expected_presented_card_position: Vector2 = animation_layer.call("_queue_card_position", 0) as Vector2
	if not presented_use_card.position.is_equal_approx(expected_presented_card_position):
		_fail("presented_card_not_at_center:%s/%s" % [presented_use_card.position, expected_presented_card_position])
		return
	# 鼠标离开前位置；直接复现动画牌透明输入区发出 hover_finished 的真实异常路径。
	var position_before_mouse_exit: Vector2 = presented_use_card.position
	presented_use_card.call("_on_mouse_exited")
	await get_tree().process_frame
	if not presented_use_card.position.is_equal_approx(position_before_mouse_exit):
		_fail("animated_card_mouse_exit_position_reset:%s/%s" % [position_before_mouse_exit, presented_use_card.position])
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
	gained_hand_card.call("_on_mouse_entered")
	await get_tree().process_frame
	if not (gained_hand_card.get_node("InputArea") as Control).tooltip_text.is_empty() or information_box.is_hover_information_visible():
		_fail("hand_card_information_shown_too_early:%s" % information_box.get_hover_title_text())
		return
	await _wait_for_hover_information_delay()
	# 首次手牌说明的面板比例；【桃】说明应在动态宽度下保持4:3，不能因自动换行初始宽度错误而被撑成大量空白。
	# 首次手牌说明的面板比例；【桃】短说明应保持在允许比例范围内，且不与更长的装备说明共用固定宽度。
	var hand_information_panel_height: float = hover_information_panel.size.y
	var hand_information_aspect_ratio: float = hover_information_panel.size.x / maxf(hand_information_panel_height, 1.0)
	if not information_box.is_hover_information_visible() or not information_box.get_hover_title_text().contains("药") or hover_information_panel.size.x < information_box.hover_panel_minimum_width or hover_information_panel.size.x > information_box.hover_panel_maximum_width or hand_information_aspect_ratio < information_box.hover_panel_minimum_aspect_ratio or hand_information_aspect_ratio > information_box.hover_panel_maximum_aspect_ratio:
		_fail("hand_card_information:%s/%s" % [information_box.get_hover_title_text(), hover_information_panel.size])
		return
	gained_hand_card.call("_on_mouse_exited")
	await get_tree().process_frame
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
	# 同区域重复移动数据；弃牌堆到弃牌堆不应在中央原地创建一张无来源牌面。
	var redundant_discard_card_data: Dictionary = {"uid":90009, "definition_id":"shan", "suit":"heart", "rank":10, "zone":"discard_pile", "owner_id":-1}
	main_instance.call("_on_card_transfer_requested", redundant_discard_card_data, -1, "discard_pile", -1, "discard_pile")
	if not animation_layer._active_cards.is_empty():
		_fail("same_zone_discard_created=%s" % [animation_layer._active_cards])
		return
	# 普通弃牌重复增量；首次请求只创建一张牌，迟到的同一 UID 请求必须被动画层幂等过滤。
	var duplicate_discard_card_data: Dictionary = {"uid":90010, "definition_id":"jiu", "suit":"club", "rank":4, "zone":"discard_pile", "owner_id":-1}
	main_instance.call("_on_card_transfer_requested", duplicate_discard_card_data, 5, "hand", -1, "discard_pile")
	main_instance.call("_on_card_transfer_requested", duplicate_discard_card_data, 5, "hand", -1, "discard_pile")
	if animation_layer._active_cards.size() != 1 or animation_layer._active_cards[0].card_uid != 90010:
		_fail("duplicate_discard_created=%s" % [animation_layer._active_cards])
		return
	animation_layer.clear_presentations()
	# 已展示并淡出的实际使用牌；最终处理区转弃牌时不得在中央重新创建第二张表现牌。
	var delayed_discard_card_data: Dictionary = {"uid":90007, "definition_id":"sha", "suit":"club", "rank":6, "zone":"processing", "owner_id":-1}
	# 单目标展示目标；使用已验证的六号位武将牌中心创建一次正常使用动画。
	var delayed_discard_target_ids: Array[int] = [5]
	animation_layer.card_flight_duration = 0.01
	animation_layer.card_hold_duration = 0.01
	animation_layer.target_line_fade_duration = 0.01
	# 延迟弃牌使用事件；动画淡出后仍需保留 UID 所有权，直到真实 processing -> discard 移动到达。
	var delayed_discard_presentation_data: Dictionary = {"presentation_id":3, "event_id":3, "event_name":"useCard", "card_data":delayed_discard_card_data, "actor_id":4, "target_ids":delayed_discard_target_ids, "source_zone":"processing", "owns_discard_transfer":true}
	main_instance.call("_on_card_presentation_requested", delayed_discard_presentation_data)
	# 重复表现包；相同 presentation_id 在任何节点创建前被拒绝，活动队列始终只有一个实体牌面。
	main_instance.call("_on_card_presentation_requested", delayed_discard_presentation_data)
	if animation_layer._active_cards.size() != 1:
		_fail("duplicate_presentation_created=%s" % [animation_layer._active_cards])
		return
	await get_tree().create_timer(0.06).timeout
	if animation_layer._active_cards.size() != 1 or not animation_layer._discard_transfer_claims.has(90007) or not animation_layer._discard_claim_card_instance_ids.has(90007):
		_fail("delayed_discard_presentation_state:%s" % [animation_layer._active_cards])
		return
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	if animation_layer._active_cards.size() != 1 or animation_layer._discard_transfer_claims.has(90007) or animation_layer._discard_claim_card_instance_ids.has(90007):
		_fail("delayed_discard_duplicate:%s" % [animation_layer._active_cards])
		return
	# 重复移动增量；认领消费后继续保留幂等 UID，第二次转发也不能在牌桌上方重新实例化同一张牌。
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	if animation_layer._active_cards.size() != 1 or not animation_layer._consumed_discard_transfer_claims.has(90007):
		_fail("repeated_discard_transfer_created:%s" % [animation_layer._active_cards])
		return
	# 不同表现 ID 的迟到包；实体仍在弃牌生命周期时也必须拒绝，不能把网络重发误判为下一次真实使用。
	var late_presentation_data: Dictionary = delayed_discard_presentation_data.duplicate(true)
	late_presentation_data["presentation_id"] = 4
	main_instance.call("_on_card_presentation_requested", late_presentation_data)
	if animation_layer._active_cards.size() != 1 or not animation_layer._consumed_discard_transfer_claims.has(90007):
		_fail("late_distinct_presentation_created:%s" % [animation_layer._active_cards])
		return
	await get_tree().create_timer(0.05).timeout
	if not animation_layer._active_cards.is_empty():
		_fail("resolved_presentation_not_faded:%s" % [animation_layer._active_cards])
		return
	# 实体进入新的非弃牌区域；权威移牌内部通知会释放旧待消费与已消费状态，使该牌未来一次合法普通弃置重新可见。
	main_instance.call("_on_card_animation_ownership_reset_requested", 90007)
	main_instance.call("_on_card_transfer_requested", delayed_discard_card_data, -1, "processing", -1, "discard_pile")
	# 未附带新表现事件的处理区收尾不应在中央锚点重新合成牌面，即使旧 UID 所有权已经释放。
	if not animation_layer._active_cards.is_empty():
		_fail("unclaimed_processing_discard_created:%s" % [animation_layer._active_cards])
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
	# 漏失最终移牌通知的认领牌；权威处理区 UID 对账确认实体已离开后必须自动进入收尾，不能永久停在窗口中上部。
	var reconciled_card_data: Dictionary = {"uid":90009, "definition_id":"sha", "suit":"diamond", "rank":10, "zone":"processing", "owner_id":-1}
	# 防御性对账表现事件；使用有效本地来源锚点创建一张正常认领牌，但故意不发送 processing -> discard 增量。
	var reconciled_presentation_data: Dictionary = {"presentation_id":7, "event_id":7, "event_name":"useCard", "card_data":reconciled_card_data, "actor_id":4, "target_ids":[], "source_zone":"processing", "owns_discard_transfer":true}
	main_instance.call("_on_card_presentation_requested", reconciled_presentation_data)
	if animation_layer._active_cards.size() != 1 or not animation_layer._discard_claim_card_instance_ids.has(90009):
		_fail("reconcile_setup:%s" % [animation_layer._active_cards])
		return
	animation_layer.reconcile_processing_card_uids([])
	await get_tree().create_timer(0.08).timeout
	if not animation_layer._active_cards.is_empty() or animation_layer._discard_claim_card_instance_ids.has(90009):
		_fail("reconcile_missing_final_move:%s" % [animation_layer._active_cards])
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
	# 唯一候选状态；除本地五号位和六号位外全部标记死亡，验证普通单目标牌不再自动写入唯一目标。
	for player_id: int in range(single_target_state.players.size()):
		if player_id != 4 and player_id != 5:
			single_target_state.players[player_id].alive = false
	main_instance.call("_on_state_changed", single_target_state.to_dict(4, false))
	main_instance.call("_on_card_pressed", single_target_card.uid)
	# 唯一合法目标；界面必须保持空选择并等待玩家真实点击六号位。
	var automatic_unique_target_selection: Array = (main_instance.get("_selected_target_ids") as Array).duplicate()
	if not automatic_unique_target_selection.is_empty() or int(main_instance.get("_auto_locked_target_id")) >= 0:
		_fail("single_target_unique_auto_selected:%s" % automatic_unique_target_selection)
		return
	main_instance.call("_on_target_pressed", 5)
	if (main_instance.get("_selected_target_ids") as Array) != [5]:
		_fail("single_target_unique_manual_select:%s" % main_instance.get("_selected_target_ids"))
		return
	# 常规选牌说明；只显示静态效果，禁止重新拼接“卡牌名｜目标：角色｜”等状态文本。
	single_target_card.definition_id = "jiedao"
	main_instance.call("_on_state_changed", single_target_state.to_dict(4, false))
	main_instance.call("_on_card_pressed", single_target_card.uid)
	var selection_effect_label: Label = main_instance.get_node("%SelectionLabel") as Label
	var jiedao_description: String = str(GameDatabase.get_card("jiedao").get("description", ""))
	if selection_effect_label.text != jiedao_description or selection_effect_label.text.contains("目标：") or selection_effect_label.text.contains("借刀杀人｜"):
		_fail("selection_effect_only:%s" % selection_effect_label.text)
		return
	# 三张例外自身牌；【桃】【酒】【无中生有】仍在选中后自动锁定本地玩家本人。
	# 【闪电】新增复用同一自身唯一目标规则，因此一并进入本组自动锁定回归。
	for self_target_definition_id: String in ["tao", "jiu", "wuzhong", "shandian"]:
		single_target_card.definition_id = self_target_definition_id
		single_target_state.players[4].hp = 3 if self_target_definition_id == "tao" else 4
		main_instance.call("_on_state_changed", single_target_state.to_dict(4, false))
		main_instance.call("_on_card_pressed", single_target_card.uid)
		var expected_self_target: Array[int] = [4]
		if (main_instance.get("_selected_target_ids") as Array) != expected_self_target or int(main_instance.get("_auto_locked_target_id")) != 4:
			_fail("self_target_auto_selected:%s/%s" % [self_target_definition_id, main_instance.get("_selected_target_ids")])
			return
	# 自身限定装备牌；不依赖装备ID白名单，所有 target_mode=self 的装备都应与【桃】等自身牌自动锁定本地玩家。
	single_target_card.definition_id = "tengjia"
	main_instance.call("_on_state_changed", single_target_state.to_dict(4, false))
	main_instance.call("_on_card_pressed", single_target_card.uid)
	if (main_instance.get("_selected_target_ids") as Array) != [4] or int(main_instance.get("_auto_locked_target_id")) != 4:
		_fail("self_only_equipment_auto_selected:%s/%s" % [main_instance.get("_selected_target_ids"), main_instance.get("_auto_locked_target_id")])
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
	# 游戏速度滑条；范围固定为0.1至1.0秒，修改后立即同步后续阶段与自动响应的全局最小间隔。
	var game_speed_slider: HSlider = main_instance.get_node("%GameSpeedSlider") as HSlider
	# 本用例游戏流程间隔；0.8秒与AI独立设置不同，用于验证两个设置没有错误共用同一变量。
	var requested_game_speed_interval: float = 0.8
	game_speed_slider.value = requested_game_speed_interval
	await get_tree().process_frame
	if not is_equal_approx(game_speed_slider.min_value, 0.1) or not is_equal_approx(game_speed_slider.max_value, 1.0) or not is_equal_approx(game_speed_slider.step, 0.1) or not is_equal_approx(GameSettings.game_speed_interval_seconds, requested_game_speed_interval) or not is_equal_approx(match_controller.game_flow_interval_seconds, requested_game_speed_interval):
		_fail("game_speed_setting:%s/%s" % [GameSettings.game_speed_interval_seconds, match_controller.game_flow_interval_seconds])
		return
	# 对局日志展开按钮；点击后正文面板必须显示，验证“记录”入口不再只是静态标题。
	var log_toggle_button: Button = main_instance.get_node("%LogToggleButton") as Button
	# 左下四号位座次标签的屏幕矩形；其底边应紧贴记录按钮上边缘，以压缩十人局侧边纵向空白。
	var lower_left_seat_label_rect: Rect2 = _screen_rect(seat_four_label)
	# 记录按钮的屏幕矩形；按钮顶部是十人局下侧座位布局的稳定视觉锚点。
	var log_toggle_button_rect: Rect2 = _screen_rect(log_toggle_button)
	# 座次标签到记录按钮的垂直间隔；默认2像素既保持贴合又避免交叠和鼠标命中竞争。
	var lower_left_seat_to_log_gap: float = log_toggle_button_rect.position.y - lower_left_seat_label_rect.end.y
	if not is_equal_approx(lower_left_seat_to_log_gap, 2.0):
		_fail("ten_player_record_gap:%s labels=%s button=%s" % [lower_left_seat_to_log_gap, lower_left_seat_label_rect, log_toggle_button_rect])
		return
	# 对局记录组件；直接调用其始终处理输入回调，验证离线暂停时空白点击仍能触发关闭意图。
	var log_panel: MatchLogPanel = main_instance.get_node("LogPanel") as MatchLogPanel
	# 对局日志正文面板；折叠组件只改变该节点可见性，不中断日志追加。
	var log_content_panel: PanelContainer = main_instance.get_node("%LogContentPanel") as PanelContainer
	await _click_control(log_toggle_button)
	if not log_content_panel.visible or not get_tree().paused or not bool(main_instance.get("_owns_log_pause")) or not match_controller.is_gameplay_paused() or int(main_instance.get("_log_pause_token")) < 0 or not match_controller.event_scheduler.pause_registry.has_active():
		_fail("offline_log_pause expanded=%s paused=%s owner=%s interface=%s" % [log_content_panel.visible, get_tree().paused, main_instance.get("_owns_log_pause"), match_controller.is_gameplay_paused()])
		return
	# 顶部回合信息板；记录展开后正文顶部必须紧贴该信息板下边，不再只占左下角的小窗口。
	var expanded_log_top_info_panel: PanelContainer = main_instance.get_node("TopInfoPanel") as PanelContainer
	# 展开记录正文的屏幕矩形；高度应延伸到常驻“记录”按钮上方并保持可滚动。
	var log_content_screen_rect: Rect2 = _screen_rect(log_content_panel)
	# 记录根节点；层级必须高于阵亡滤镜的30层，避免展开后被角色状态覆盖。
	if log_panel.z_index <= 30 or not is_equal_approx(log_content_screen_rect.position.y, _screen_rect(expanded_log_top_info_panel).end.y) or log_content_screen_rect.end.y >= log_toggle_button_rect.position.y:
		_fail("expanded_log_layer_or_bounds:%s/%s/%s" % [log_panel.z_index, log_content_screen_rect, _screen_rect(expanded_log_top_info_panel)])
		return
	# 离线日志打开时牌桌本身已暂停；始终处理的日志组件仍要把空白左键交给牌桌，收起记录与菜单并释放日志暂停。
	var match_menu: MatchMenu = main_instance.get_node("MatchMenu") as MatchMenu
	match_menu.set_menu_open(true)
	var blank_click_event: InputEventMouseButton = InputEventMouseButton.new()
	blank_click_event.button_index = MOUSE_BUTTON_LEFT
	blank_click_event.pressed = true
	log_panel.call("_unhandled_input", blank_click_event)
	if log_content_panel.visible or match_menu.is_menu_open() or get_tree().paused or bool(main_instance.get("_owns_log_pause")) or match_controller.is_gameplay_paused() or int(main_instance.get("_log_pause_token")) >= 0 or match_controller.event_scheduler.pause_registry.has_active():
		_fail("offline_blank_click_overlay_close expanded=%s menu=%s paused=%s owner=%s" % [log_content_panel.visible, match_menu.is_menu_open(), get_tree().paused, main_instance.get("_owns_log_pause")])
		return
	# 远程通信模式；本地展开日志只能改变可见性，不得暂停仍由权威端推进的联网对局。
	match_controller.network_gateway.mode = NetworkGateway.Mode.REMOTE
	await _click_control(log_toggle_button)
	if not log_content_panel.visible or get_tree().paused or bool(main_instance.get("_owns_log_pause")) or match_controller.is_gameplay_paused():
		_fail("remote_log_must_continue expanded=%s paused=%s owner=%s" % [log_content_panel.visible, get_tree().paused, main_instance.get("_owns_log_pause")])
		return
	await _click_control(log_toggle_button)
	match_controller.network_gateway.mode = NetworkGateway.Mode.OFFLINE
	# 空白点击已按规则收起局内菜单；重开前重新通过真实入口展开，避免向不可见按钮注入失真的鼠标事件。
	await _click_control(menu_button)
	if not match_menu.is_menu_open():
		_fail("menu_reopen_before_restart")
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


## 等待统一信息框完成正式0.5秒悬停延迟；集中保留无头测试调度余量，避免各个手牌、装备、技能和武将牌断言使用不同等待值。
func _wait_for_hover_information_delay() -> void:
	await get_tree().create_timer(HOVER_INFORMATION_DELAY_SETTLE_SECONDS).timeout


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


## 向控件中心发送右键移动、按下和释放事件，验证武将详情与牌桌右键取消的真实输入优先级。
func _right_click_control(control: Control) -> void:
	# 当前控件屏幕中心；输入事件与正常鼠标命中使用相同画布变换结果。
	var click_position: Vector2 = _screen_rect(control).get_center()
	# 鼠标移动事件；先建立正式悬停目标，保证按键进入武将牌透明输入组件。
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.position = click_position
	get_viewport().push_input(motion_event, true)
	await get_tree().process_frame
	# 右键按下事件；武将牌输入组件必须消费该阶段，不能让牌桌提前取消当前选择。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.position = click_position
	press_event.button_index = MOUSE_BUTTON_RIGHT
	press_event.pressed = true
	get_viewport().push_input(press_event, true)
	await get_tree().process_frame
	# 右键释放事件；透明输入组件只在该阶段发出一次武将详情请求。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.position = click_position
	release_event.button_index = MOUSE_BUTTON_RIGHT
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
			"character_id":"gepard",
			"identity":"leader" if player_index == 0 else "hidden",
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
		elif player_index == 5:
			# 六号位公开武器；用于验证其他玩家武将牌上的装备横条也进入统一悬浮信息接口。
			player_snapshot["equipment"] = {
				"weapon":{"uid":95000, "definition_id":"qinggang", "suit":"club", "rank":7, "zone":"equipment", "owner_id":5},
			}
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
		player.identity = "leader" if player_id == 0 else "rebel"
		player.character_id = "gepard"
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
	# 活动出牌请求摘要；正式界面只有在阶段与 chooseToUse 同时有效时才允许编辑卡牌目标。
	game_state.current_choice_request = {"request_id":98001, "event_id":98002, "actor_id":4, "choice_type":"use"}
	return game_state


## 记录右上角菜单按钮收到真实鼠标点击，供异步输入流程断言。
func _on_menu_button_pressed() -> void:
	_menu_button_pressed = true


## 输出统一失败原因并以非零状态结束测试。
func _fail(reason: String) -> void:
	printerr("UI_LAYOUT_FAIL %s" % reason)
	get_tree().quit(1)
