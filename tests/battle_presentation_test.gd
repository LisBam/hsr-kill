extends Node

## 集中验证真实牌桌表现边界：无文字选择、重复快照、拖牌、暂停、动态按钮、窗口重开和三主题。
## 图形模式自动输出.godot/battle_review截图；无头模式只检查契约，不启动真实网络或推进正式对局。

## 正式主场景；使用同一资源测试装配，避免复制一套仅测试可用的UI。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 战斗文字语义；用于检查局内技能说明没有误用局外纸面文字色。
const BATTLE_STYLE: Script = preload("res://scripts/ui/battle_surface_style.gd")
## 表现稳定等待时间；覆盖最长0.22秒入场与两次布局，不依赖对局速度。
const SETTLE_SECONDS: float = 0.32
## 异步悬停验证的最长真实等待时间；默认5000毫秒，容纳图形首帧编译与两次布局，但不放宽最终状态断言。
const HOVER_SETTLE_TIMEOUT_MSEC: int = 5000
## 累积失败数；最后统一退出非零状态，避免只看首条断言遗漏相邻界面问题。
var _failures: int = 0


## 测试自身在暂停时继续执行；被测规则控制器仍保持原process_mode。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 记录独立断言；不会用assert停在编辑器断点导致验证进程悬挂。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("BATTLE_PRESENTATION_FAIL: " + message)


## 等待有限Tween，不驱动规则动作，也不修改全局时间缩放。
func _settle() -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout


## 仅图形进程截图；保持在忽略目录，不污染正式资源与玩家设置。
func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/battle_review"))
	get_viewport().get_texture().get_image().save_png("res://.godot/battle_review/%s.png" % file_name)


## 用只读公开快照建立八人牌桌；所有展示数值只是测试夹具，不写入内容数据库。
func _make_snapshot() -> Dictionary:
	# 八名角色公开快照；顺序固定，便于比较主题和窗口的渲染结果。
	var players: Array[Dictionary] = []
	# 已登记武将；选择已有素材的角色，不能从测试修改技能定义。
	var characters: Array[String] = ["gepard", "march_7th", "natasha", "dan_heng", "gepard", "march_7th", "natasha", "dan_heng"]
	# 本地可见手牌；普通牌与装备均使用数据库中的真实定义。
	var hand: Array[Dictionary] = []
	for index: int in range(6):
		hand.append({"uid":801 + index, "definition_id":["sha", "shan", "tao"][index % 3], "suit":["spade", "heart", "club"][index % 3], "rank":index + 2, "zone":"hand", "owner_id":0})
	for index: int in range(characters.size()):
		players.append({"player_id":index, "seat_number":index + 1, "display_name":"开拓者%d" % (index + 1), "character_id":characters[index], "identity":"leader" if index == 0 else "unknown", "identity_revealed":index == 0, "hp":3 if index == 2 else 4, "max_hp":4, "alive":true, "chained":false, "hand_count":6 if index == 0 else 3, "hand":hand if index == 0 else [], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "wooden_ox_storage_count":0, "total_damage_dealt":index + 2, "total_damage_received":index, "total_healing_done":1, "total_cards_drawn":12 + index, "total_kill_count":0})
	return {"players":players, "current_player_id":0, "current_phase":"play", "turn_number":3, "draw_pile_count":87, "discard_pile_count":16, "game_over":false, "match_mode":"identity"}


## 集中覆盖表现组件和真实窗口；每个操作只等待一次有限动画。
func _run() -> void:
	# 本测试通过正式接口和信号驱动界面；关闭真实GUI鼠标输入，避免弹窗收起时的mouse_entered覆盖合成悬停来源。
	get_viewport().gui_disable_input = true
	GameSettings.set("_settings_file_path", "res://.godot/battle_presentation_test.cfg")
	# 既有深色表面断言以原纸金战斗配色为固定基线；后面的主题遍历单独检查经典和夜间。
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_SPACE_MONO)
	await GameDatabase.wait_until_ready()
	# 正式场景实例；禁止控制器自动发起随机对局，全部测试只消费公开夹具。
	var main: Control = MAIN_SCENE.instantiate() as Control
	# 控制器仅负责转发已有界面信号，不创建权威状态。
	var controller: MatchController = main.get_node("MatchController") as MatchController
	controller.default_player_count = 1
	controller.local_human_player_id = 0
	controller.randomize_local_human_seat = false
	add_child(main)
	await _settle()
	main.get_node("MainMenu").hide()
	# 固定牌桌快照；主题、选中和开关窗口后核对它没有被改写。
	var snapshot: Dictionary = _make_snapshot()
	# 快照副本；专门检测纯表现层是否意外修改业务数据。
	var snapshot_before: Dictionary = snapshot.duplicate(true)
	controller.state_changed.emit(snapshot)
	await _settle()
	# 对局时长每秒更新；不应挂载文字位移动画，牌堆文字仍保留反馈。
	_check(not main.get_node("%CenterPhaseLabel").has_node("TextMotion"), "对局时长不应随文本更新跳动")
	_check(main.get_node("%CenterTurnLabel").has_node("TextMotion"), "牌堆文字反馈应保持启用")
	# 正式对手视图；选中反馈不依赖独立样例或假牌面。
	var target: PlayerTargetView = (main.get("_player_views") as Dictionary).get(1) as PlayerTargetView
	# 正式手牌；后续同时验证选择和原实体拖动。
	var card: CardView = (main.get("_card_views") as Dictionary).get(801) as CardView
	if target == null or card == null:
		_check(false, "正式快照没有生成武将或手牌")
		get_tree().quit(1)
		return
	target.set_target_state(true, true, true)
	card.set_selected_state(true)
	# 相邻选中手牌必须以整张牌为单位排序，左侧选中框不得越过右侧牌面。
	var next_card: CardView = (main.get("_card_views") as Dictionary).get(802) as CardView
	if next_card == null:
		_check(false, "缺少相邻手牌")
		get_tree().quit(1)
		return
	next_card.set_selected_state(true)
	(card.get_parent() as DecadeHandContainer).layout_cards_now()
	# 左侧手牌的选中装饰；其相对层级必须与所属牌面一致，才能被右侧牌正常遮挡。
	var card_feedback: Control = card.get_node("SelectionFeedback") as Control
	_check(card_feedback.z_as_relative and card_feedback.z_index == 0 and card.z_index < next_card.z_index, "选中框越过相邻手牌层级")
	_check(card_feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "手牌选中框拦截输入")
	# 选中组件和原始节点位置；边缘动画不能移动武将或改变原输入矩形。
	var feedback: Control = target.get_node("SelectionFeedback") as Control
	# 当前Tween；重复快照不应重新创建它。
	var selection_tween: Tween = feedback.get("_tween") as Tween
	# 原始目标矩形；后续重绘保持精确相等。
	var target_rect: Rect2 = target.get_global_rect()
	for _index: int in range(8):
		target.set_target_state(true, true, true)
	_check(feedback.get("_tween") == selection_tween, "重复选中刷新重启了动画")
	_check(not (target.get_node("SelectedTargetMarker") as Label).visible and (target.get_node("SelectedTargetMarker") as Label).text.is_empty(), "牌面仍有选中大字")
	_check(feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE, "选中装饰拦截输入")
	await _settle()
	_check(target.get_global_rect().is_equal_approx(target_rect), "选择反馈改变武将命中范围")
	_check(is_equal_approx(float(feedback.get("_amount")), 1.0), "选择角线未完成入场")
	await _capture("01_battle_selected")
	# 选将使用同一武将牌；被选项不能再出现覆盖插画的大字。
	var character_selection: CharacterSelectionPanel = main.get_node("CharacterSelectionPanel") as CharacterSelectionPanel
	character_selection.bind_snapshot({"phase":"leader_selecting", "can_select":true, "local_candidates":["gepard", "march_7th", "natasha", "dan_heng"], "local_identity":"leader", "local_seat_number":1})
	character_selection.call("_select_candidate", "march_7th")
	await _settle()
	_check(UIStyleRegistry.get_color(BattleUIStyle.get_active_style_id(), "battle_selection_panel").get_luminance() < 0.3, "选将窗口仍使用亮白底")
	await _capture("01a_character_selection")
	character_selection.bind_snapshot({"phase":"others_selecting", "can_select":true, "local_candidates":["gepard", "march_7th", "natasha", "dan_heng", "xiluwa", "sangbo", "xing", "qiong"], "leader_character_id":"xiluwa", "local_identity":"rebel", "local_seat_number":2, "initial_identity":"rebel", "initial_seat_number":2, "allow_custom_assignment":true, "allow_all_characters":true, "player_count":8, "seat_options":[1,2,3,4,5,6,7,8], "identity_options":["leader","loyalist","rebel","renegade"]})
	await _settle()
	for button: Button in character_selection.find_children("*", "Button", true, false):
		for state_name: String in ["normal", "hover", "pressed", "disabled"]:
			# 读取真实按钮绘制状态；禁用态同样不得回退浅色共享材质。
			var style: StyleBoxFlat = button.get_theme_stylebox(state_name) as StyleBoxFlat
			if style != null and style.bg_color.a > 0.0:
				_check(style.bg_color.get_luminance() < 0.8, "选将按钮仍有白底：%s/%s" % [button.name, state_name])
	await _capture("01b_custom_character_selection")
	character_selection.close()
	# 取消、重选并拖动；选中位移不能与鼠标同时争抢原牌位置。
	card.set_selected_state(false)
	card.begin_hand_drag(card.global_position + Vector2(15.0, 20.0))
	card.move_hand_drag(Vector2(520.0, 570.0))
	# 拖动中的位置；继续等待选择动画时必须不漂移。
	var dragged_position: Vector2 = card.global_position
	await _settle()
	_check(card.global_position.is_equal_approx(dragged_position), "选中位移干扰直接拖牌")
	card.end_hand_drag()
	card.set_selected_state(true)
	await _settle()
	# 原生主按钮；按压仅改变视觉偏移，不能改变点击区域。
	var button: Button = main.get_node("%MenuButton") as Button
	# 按压前矩形；用同步推进避免操作系统鼠标事件干扰合成按压。
	var button_rect: Rect2 = button.get_global_rect()
	button.button_down.emit()
	(button.get_node("BattleButtonMotion").get("_tween") as Tween).custom_step(0.10)
	_check(button.get_global_rect().is_equal_approx(button_rect) and button.offset_transform_scale.x < 1.0, "原生按钮按压改变布局或没有反馈")
	button.button_up.emit()
	# 真实暂停菜单；Tween必须在暂停中完成，关闭必须同步取消。
	var menu: Control = main.get_node("MatchMenu") as Control
	menu.set_menu_open(true)
	get_tree().paused = true
	await _settle()
	# 实际面板；不得残留半透明或偏移。
	var menu_surface: Control = menu.get("_menu_panel") as Control
	_check(is_equal_approx(menu_surface.modulate.a, 1.0) and menu_surface.offset_transform_position.is_zero_approx(), "暂停中菜单动画未完成")
	await _capture("02_match_menu")
	menu.set_menu_open(false)
	menu.set_menu_open(true)
	menu.set_menu_open(false)
	_check(not menu_surface.visible and not bool(menu_surface.get_node("SurfaceMotion").get("_active")), "快速关闭留下动画或可见面板")
	get_tree().paused = false
	# 动态选牌弹窗；新建候选保持卡牌输入，动态按钮接入反馈。
	var choices: CardSelectionPanel = main.get_node("CardSelectionPanel") as CardSelectionPanel
	# 实体候选；复用与规则层一致的UID及候选结构。
	var candidates: Array = []
	for entry: Dictionary in (snapshot["players"][0] as Dictionary)["hand"]:
		candidates.append({"uid":entry["uid"], "owner_id":0, "zone":"hand", "visible":true, "card_data":entry})
	choices.show_request({"request_id":901, "chooser_id":0, "choice_type":"card", "title":"选择卡牌", "prompt":"请选择一张牌", "candidates":candidates, "min_select":1, "max_select":1, "allow_cancel":true})
	choices.call("_on_card_pressed", 801)
	await _settle()
	_check((choices.get("_confirm_button") as Button).has_node("BattleButtonMotion"), "动态选牌确认按钮缺少反馈")
	await _capture("03_card_choice")
	choices.close()
	# 机缘品质牌；正文与品质保持原文，仅外围视觉增强。
	var opportunity: OpportunityChoicePanel = main.get("opportunity_choice_panel") as OpportunityChoicePanel
	opportunity.show_opportunity({"active":true, "stage":"choosing", "current_chooser_id":0, "pending_chooser_ids":[0], "chosen_player_ids":[], "options_by_player":{"0":[{"id":"visual_a", "quality":"blue", "description":"摸两张牌。"}, {"id":"visual_b", "quality":"purple", "description":"回复一点体力。"}, {"id":"visual_c", "quality":"orange", "description":"增加一点体力上限。"}]}}, 0, {0:"开拓者"})
	await _settle()
	await _capture("04_opportunity")
	opportunity.close()
	# 悬浮信息框；布局阶段先透明，稳定后入场，不能被旧Tween重新隐藏。
	var information: InformationBoxLayer = main.get("information_box") as InformationBoxLayer
	information.show_hover_information({"title":"【测试技能】", "description":"技能说明保持原文，边缘反馈不占用牌面中央。"}, target_rect, 123456)
	# 测量完成的信息框；验证透明度与边界都稳定。
	var hover_panel: Control = information.get("_hover_panel") as Control
	# 真实时间截止点；定时器到期不代表跨帧布局已经结束，因此逐帧等待实际可见状态。
	var hover_deadline_msec: int = Time.get_ticks_msec() + HOVER_SETTLE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < hover_deadline_msec:
		if int(information.get("_hover_source_id")) == 123456 and hover_panel.visible and is_equal_approx(hover_panel.modulate.a, 1.0):
			break
		await get_tree().process_frame
	_check(int(information.get("_hover_source_id")) == 123456 and hover_panel.visible and is_equal_approx(hover_panel.modulate.a, 1.0), "信息框测量与淡入互相覆盖（visible=%s alpha=%s source=%s）" % [hover_panel.visible, hover_panel.modulate.a, information.get("_hover_source_id")])
	# 普通悬停说明；正文颜色必须来自战斗面板语义。
	var hover_description: SkillDescriptionView = information.get("_hover_description_label") as SkillDescriptionView
	_check(hover_description.use_battle_colors and Color(str(hover_description.get_rendered_segments()[0]["color"])).is_equal_approx(BATTLE_STYLE.get_color("text_secondary")), "普通悬停说明未使用战斗文字色")
	information.hide_hover_information(123456)
	# 结构化武将悬停资料；独立创建的技能说明同样应使用局内颜色。
	information.show_hover_information({"title":"测试武将", "description_sections":[{"title":"测试技能", "description":"普通技能说明"}]}, target_rect, 123457)
	# 等待悬停延迟和布局完成，避免在技能标签创建之前检查。
	var structured_hover_deadline_msec: int = Time.get_ticks_msec() + HOVER_SETTLE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < structured_hover_deadline_msec and int(information.get("_hover_source_id")) != 123457:
		await get_tree().process_frame
	# 当前武将悬停的技能说明视图；实际组件动态创建并维护该列表。
	var hover_skills: Array = information.get("_hover_skill_description_labels") as Array
	_check(not hover_skills.is_empty() and (hover_skills[0] as SkillDescriptionView).use_battle_colors, "武将悬停技能未使用战斗文字色")
	information.hide_hover_information(123457)
	# 正式武将详情；检查普通技能正文和轮回技分段在战斗配色下均可读。
	information.show_character_details(snapshot["players"][0], GameDatabase.get_character("gepard"))
	await _settle()
	# 详情中的技能说明；使用真实详情组件创建的首个条目。
	var detail_description: SkillDescriptionView = information.get_character_skill_list().get_child(0).get_child(1) as SkillDescriptionView
	_check(detail_description != null and detail_description.use_battle_colors, "武将详情未启用战斗文字色")
	if detail_description != null:
		detail_description.configure_description("轮回技，①第一节；②第二节。", true, 0)
		# 轮回技能分段；普通前缀和非当前节分别使用战斗次级色与淡色。
		var detail_segments: Array[Dictionary] = detail_description.get_rendered_segments()
		_check(Color(str(detail_segments[0]["color"])).is_equal_approx(BATTLE_STYLE.get_color("text_secondary")) and Color(str(detail_segments[2]["color"])).is_equal_approx(BATTLE_STYLE.get_color("text_muted")), "武将详情轮回技正文颜色不正确")
	await _capture("04a_character_details")
	information.close_character_details()
	# 局内聊天与日志；纯文本内容和滚动仍由原组件负责。
	var chat: MatchChatPanel = main.get("match_chat_panel") as MatchChatPanel
	chat.open_panel([{"display_name":"开拓者", "message":"准备好下一回合了吗？"}])
	main.get_node("LogPanel").append_entry("第三轮 · 准备阶段")
	main.get_node("LogPanel").set_expanded(true)
	await _settle()
	await _capture("05_chat_and_log")
	chat.close_panel()
	main.get_node("LogPanel").set_expanded(false)
	get_tree().paused = false
	# 科技造牌窗口；配置真实候选结构，重新显示同一请求必须保留已输入名称。
	var windows: YinlangWindowsLayer = main.get("yinlang_windows_layer") as YinlangWindowsLayer
	# 本地请求数据；专门检验视图复用，不提交到控制器。
	var mint_request: Dictionary = {"request_id":903, "context":{MatchController.YINLANG_WINDOW_CONTEXT_KEY:MatchController.YINLANG_WINDOW_AETHER, "copyable_cards":[{"id":"sha", "name":GameSettings.resolve_card_display_name(GameDatabase.get_card("sha")), "type":"basic"}, {"id":"shan", "name":GameSettings.resolve_card_display_name(GameDatabase.get_card("shan")), "type":"basic"}, {"id":"tao", "name":GameSettings.resolve_card_display_name(GameDatabase.get_card("tao")), "type":"basic"}], "existing_card_names":[]}}
	windows.show_request(mint_request)
	(windows.get("_mint_view").get("_name_edit") as LineEdit).text = "星光"
	(windows.get("_mint_view").get("_name_edit") as LineEdit).text_changed.emit("星光")
	windows.hide_view()
	windows.show_request(mint_request)
	await _settle()
	_check((windows.get("_mint_view").get("_name_edit") as LineEdit).text == "星光", "窗口重开丢失输入")
	await _capture("06_yinlang_mint")
	windows.close()
	# 结算只读统计；底纹不能增加统计列、改变玩家顺序或污染快照。
	var settlement: GameSettlementPanel = main.get("game_settlement_panel") as GameSettlementPanel
	settlement.show_settlement(snapshot)
	await _settle()
	await _capture("07_settlement")
	settlement.call("_on_save_replay_button_pressed")
	await _settle()
	await _capture("07a_replay_naming")
	settlement.call("_close_naming_modal")
	settlement.hide_settlement()
	# 开发者二级页面与回放控制条也走正式组件，覆盖运行时新增按钮。
	var console_panel: DeveloperConsolePanel = main.get("developer_console_panel") as DeveloperConsolePanel
	console_panel.open_console()
	await _settle()
	await _capture("08_console")
	console_panel.call("_apply_view", DeveloperConsolePanel.View.CHARACTER)
	await _settle()
	_check(is_equal_approx((console_panel.get("_character_view") as Control).modulate.a, 1.0), "开发者分页未完成过渡")
	console_panel.close_console()
	get_tree().paused = false
	for style_id: String in UIStyleRegistry.get_style_ids():
		GameSettings.set_ui_style(style_id)
		await _settle()
		_check((feedback.get("_accent") as Color).is_equal_approx(BattleUIStyle.get_color("accent")), "选中边光未跟随主题")
		hover_description.refresh_ui_style()
		_check(hover_description.get_theme_color("default_color").is_equal_approx(BATTLE_STYLE.get_color("text_secondary")), "局内说明切换主题后颜色错误: " + style_id)
		# 局外默认说明；同一组件不应把战斗深色面板文字泄漏到纸面图鉴。
		var gallery_description: SkillDescriptionView = SkillDescriptionView.new()
		add_child(gallery_description)
		gallery_description.configure_description("图鉴技能说明")
		_check(Color(str(gallery_description.get_rendered_segments()[0]["color"])).is_equal_approx(BattleUIStyle.get_color("text_secondary")), "局外说明未使用原主题文字色: " + style_id)
		gallery_description.queue_free()
		_check((main.get_node("ReferenceBackdrop") as ReferenceBackdrop).table_surface_color.is_equal_approx(BattleUIStyle.get_color("battle_table_surface", BattleUIStyle.get_color("table_surface"))), "牌桌未应用独立局内配色")
		if style_id == UIStyleRegistry.STYLE_SPACE_MONO:
			_check(BattleUIStyle.get_color("battle_table_inner").get_luminance() < 0.3, "局内桌面过亮")
			_check(BattleUIStyle.get_color("table_surface").get_luminance() > 0.8, "战斗换肤影响了局外纸面")
			_check((main.get_node("%CenterTurnLabel") as Label).get_theme_color("font_color").get_luminance() > 0.7, "深色信息栏文字不清晰")
		if style_id == UIStyleRegistry.STYLE_CLASSIC or style_id == UIStyleRegistry.STYLE_NIGHT:
			# 经典明亮暖色与夜间深色；背景、正文必须成组变化，身份色与原画仍来自基础主题。
			# 经典战斗按指定历史版本恢复炭灰/古金配色；两者现在均为暗色表面与浅色正文。
			var classic: bool = style_id == UIStyleRegistry.STYLE_CLASSIC
			_check(BATTLE_STYLE.get_color("selection_panel").get_luminance() < 0.3, "派生主题战斗表面明度错误: " + style_id)
			if classic:
				_check(BATTLE_STYLE.get_color("table_surface").is_equal_approx(Color("282725")) and BATTLE_STYLE.get_color("table_inner").is_equal_approx(Color("34322e")), "经典战斗未应用统一暖色桌面")
			_check(BATTLE_STYLE.get_color("text_secondary").get_luminance() > 0.6, "派生主题战斗文字明度错误: " + style_id)
			_check(BattleUIStyle.get_color("identity_leader").is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, "identity_leader")), "派生主题改变身份语义色")
			_check((card.get_node("CardBody/ArtworkPlaceholder") as Label).get_theme_color("font_color").is_equal_approx(BattleUIStyle.get_color("card_placeholder")), "牌面占位文字未使用主题颜色: " + style_id)
			_check((target.get_parent().get_node("Seat") as Label).get_theme_color("font_color").is_equal_approx(BATTLE_STYLE.get_color("seat_text")), "座次号未跟随主题: " + style_id)
			information.show_character_details(snapshot["players"][0], GameDatabase.get_character("gepard"))
			await _settle()
			# 主题切换后新建的详情正文；实际富文本分段与面板必须使用同一战斗语义。
			var themed_description: SkillDescriptionView = information.get_character_skill_list().get_child(0).get_child(1) as SkillDescriptionView
			_check(Color(str(themed_description.get_rendered_segments()[0]["color"])).is_equal_approx(BATTLE_STYLE.get_color("text_secondary")), "派生主题详情正文颜色错误: " + style_id)
			# 原始技能说明仅作测试后还原，截图继续显示正式数据库内容。
			var original_skill_description: String = themed_description.get_plain_description()
			# 当前轮回节也必须在浅色纸面清晰；不能沿用深底上的浅金文字。
			themed_description.configure_description("轮回技，①第一节；②第二节。", true, 0)
			_check(Color(str(themed_description.get_rendered_segments()[1]["color"])).is_equal_approx(BATTLE_STYLE.get_color("accent")), "派生主题轮回技高亮颜色错误: " + style_id)
			themed_description.configure_description(original_skill_description)
			await _settle()
			_check(information.get_character_close_button().get_theme_color("font_focus_color").is_equal_approx(BATTLE_STYLE.get_color("text_primary")), "详情关闭按钮焦点文字不清晰: " + style_id)
			await _capture("details_" + style_id)
			information.close_character_details()
		await _capture("theme_" + style_id)
	# 重演控制条只改变显示，不开启录制或网络。
	main.call("_ensure_replay_playback_components")
	var replay: MatchReplayOverlay = main.get("_match_replay_overlay") as MatchReplayOverlay
	replay.open_overlay("表现回归")
	await _settle()
	await _capture("09_replay_overlay")
	replay.close_overlay()
	_check(snapshot == snapshot_before, "纯表现修改了只读快照")
	main.queue_free()
	await get_tree().process_frame
	print("BATTLE_PRESENTATION_%s failures=%d" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
