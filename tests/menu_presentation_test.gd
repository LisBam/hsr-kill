extends Node

## 局外表现集中回归：真实首页、四页导航、七模式、图鉴详情、模态重入、动态大厅及战斗隔离。

## 每次等待的最长常规过渡；0.36秒覆盖0.28秒入场及一帧调度，不使用游戏速度配置。
const SETTLE_SECONDS: float = 0.36
## 测试主场景；复用正式资源验证组件路径和调用关系。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## 等数据库与场景构建完成后开始，避免把资源异步加载误判为过渡问题。
func _ready() -> void:
	call_deferred("_run")


## 失败立即结束进程；用于命令行集中检查，不依赖断言后仍运行的图形调试器。
func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("MENU_PRESENTATION_FAIL: " + message)
		get_tree().quit(1)
	return condition


## 等待真实Tween时间；动画与规则速度解耦，测试也不修改时间缩放。
func _settle(seconds: float = SETTLE_SECONDS) -> void:
	await get_tree().create_timer(seconds).timeout


## 仅显式传入--capture-menu时输出渲染截图；普通无头回归不读取GPU画面。
func _capture(file_name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture-menu") or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/menu_review"))
	get_viewport().get_texture().get_image().save_png("res://.godot/menu_review/%s.png" % file_name)


## 覆盖完整局外生命周期，不创建网络会话或正式对局。
func _run() -> void:
	# 独立测试偏好文件；不写入玩家的正式本地配置。
	GameSettings.set("_settings_file_path", "res://.godot/menu_presentation_test.cfg")
	await GameDatabase.wait_until_ready()
	# 正式首页实例；只在本测试进程生存。
	var main: Control = MAIN_SCENE.instantiate() as Control
	add_child(main)
	await _settle()
	await _capture("01_home")
	# 首页及装配器；必须仅挂载于局外根节点。
	var menu: MainMenu = main.get_node("MainMenu") as MainMenu
	# 表现装配器；使用属性接口测试检查器开关。
	var presentation: Node = menu.get_node("MenuPresentation")
	# 原始开始按钮；验证视觉按压不会改变实际布局矩形。
	var start: Button = menu.get_node("%StartGameButton") as Button
	# 点击前的命中矩形；视觉变换前后必须相同。
	var start_rect: Rect2 = start.get_global_rect()
	start.button_down.emit()
	# 同步推进反馈轨道，避免真实窗口首次激活的系统鼠标事件干扰合成按压信号。
	var press_tween: Tween = start.get_node("MenuButtonMotion").get("_tween") as Tween
	press_tween.custom_step(0.10)
	if not _check(start.get_global_rect().is_equal_approx(start_rect) and start.offset_transform_visual_only and start.offset_transform_scale.x < 1.0, "按压必须只改变视觉变换 before=%s after=%s scale=%s disabled=%s" % [start_rect, start.get_global_rect(), start.offset_transform_scale, start.disabled]):
		return
	start.button_up.emit()
	await _settle()
	if not _check(start.offset_transform_scale.is_equal_approx(Vector2.ONE), "松开必须回弹到原尺寸"):
		return
	# 战斗菜单中的按钮；局外装配器不得越界挂载组件。
	var battle_button: BaseButton = main.get_node("%MenuButton") as BaseButton
	if not _check(not battle_button.has_node("MenuButtonMotion"), "战斗按钮必须保持独立"):
		return
	# 四个导航入口；逐一覆盖静态页及运行时构建的回放页。
	var nav_names: Array[String] = ["MainMenuOnlineSettingsButton", "MainMenuAllCardsButton", "MainMenuMatchReplayButton", "TopIdentityModeButton"]
	# 与入口对应的业务页面；作为唯一可见页验证对象。
	var page_names: Array[String] = ["OnlineSettingsPanel", "AllCardsPanel", "MatchReplayPanel", "MainMenuFrame"]
	for index: int in range(nav_names.size()):
		(menu.get_node("%" + nav_names[index]) as Button).pressed.emit()
		await _settle()
		await _capture("page_%d" % index)
		# 当前业务页面；淡入完成后必须完全可见并恢复视觉位置。
		var page: Control = menu.get_node(page_names[index]) as Control
		if not _check(page.visible and is_equal_approx(page.modulate.a, 1.0) and page.offset_transform_position.is_zero_approx(), "页面切换未归位: " + page_names[index]):
			return
	# 原主题；测试只写入独立偏好文件，检查后恢复当前运行的展示。
	var original_style: String = GameSettings.ui_style_id
	for style_id: String in UIStyleRegistry.STYLE_ORDER:
		GameSettings.set_ui_style(style_id)
		await _settle(0.10)
		# 主按钮背景；三套主题必须读取当前强调语义，不能残留上一个主题颜色。
		var start_style: StyleBoxFlat = start.get_theme_stylebox("normal") as StyleBoxFlat
		if not _check(start_style.bg_color.is_equal_approx(BattleUIStyle.get_color("accent")), "主按钮主题未同步: " + style_id):
			return
		await _capture("theme_" + style_id)
	GameSettings.set_ui_style(original_style)
	await _settle(0.10)
	# 七个模式快速切换；重点检查可打断Tween不留下摘要半透明状态。
	var mode_names: Array[String] = ["IdentityModeButton", "DouDizhuModeButton", "Team2v2ModeButton", "WheelDuelModeButton", "OpportunityBrawlModeButton", "ConquestModeButton", "WinnerTakesAllModeButton"]
	for mode_name: String in mode_names:
		(menu.get_node("%" + mode_name) as Button).pressed.emit()
		await get_tree().process_frame
	await _settle()
	# 当前摘要；模式状态仍由原业务写入GameSettings。
	var summary: Control = menu.get_node("%MainMenuModeSummaryPanel") as Control
	if not _check(GameSettings.next_match_mode == GameSettings.MATCH_MODE_WINNER_TAKES_ALL and is_equal_approx(summary.modulate.a, 1.0), "快速切模式必须保留最后一次选择"):
		return
	menu.call("_open_settings")
	await _settle()
	await _capture("02_settings")
	# 设置模态；关闭过程中再次打开应取消旧回调并恢复输入。
	var settings: Control = menu.get_node("%MainMenuSettingsPanel") as Control
	menu.call("_close_settings")
	menu.call("_open_settings")
	await _settle()
	if not _check(settings.visible and settings.mouse_behavior_recursive != Control.MOUSE_BEHAVIOR_DISABLED, "重开设置必须取消迟到关闭"):
		return
	menu.call("_close_settings")
	menu.call("_close_settings")
	await _settle()
	if not _check(not settings.visible and not (menu.get_node("%MainMenuSettingsBackdrop") as Control).visible, "重复关闭必须只执行一次并清除遮罩"):
		return
	menu.call("_open_all_cards")
	await _settle()
	# 图鉴与首名合法武将；不手写武将ID，数据变化不影响界面测试。
	var gallery: AllCardsPanel = menu.get_node("AllCardsPanel") as AllCardsPanel
	gallery.call("_open_information", "characters", str(GameDatabase.characters.keys()[0]))
	await _settle()
	await _capture("03_card_details")
	gallery.call("_close_information")
	await _settle()
	if not _check(not (gallery.get_node("%AllCardsInfoBackdrop") as Control).visible, "图鉴详情关闭必须移除模态"):
		return
	for category: String in ["game_cards", "opportunities", "characters"]:
		gallery.call("_select_category", category)
		await _settle(0.10)
	if not _check((gallery.get("_entries") as Array).size() > 0, "图鉴子页必须保留内容"):
		return
	menu.call("_open_match_replay")
	await _settle()
	# 回放共享模态；验证动态创建的输入和按钮也已接入表现服务。
	var replay: MatchReplayPanel = menu.get_node("MatchReplayPanel") as MatchReplayPanel
	replay.call("_open_path_modal", "import")
	await _settle()
	await _capture("04_replay_modal")
	if not _check(replay.find_child("ReplayPathModalConfirm", true, false).has_node("MenuButtonMotion"), "动态回放模态按钮遗漏动效"):
		return
	replay.call("_close_path_modal")
	await _settle()
	menu.call("_select_identity_mode")
	menu.call("_open_lan_panel")
	await _settle()
	await _capture("05_connection")
	# 连接面板；关闭只发出原有请求，不建立测试网络端口。
	var entry: LanLobbyPanel = menu.get_node("LanLobbyPanel") as LanLobbyPanel
	entry.call("_request_leave")
	await _settle()
	if not _check(not entry.visible, "连接入口退场必须回到首页"):
		return
	# 本地展示快照；只含UI需要的公开字段，无真实网络会话。
	var snapshot: Dictionary = {"role": "host", "local_peer_id": 1, "player_count": 4, "game_mode_id": "identity", "members": [{"peer_id": 1, "seat_index": 0, "display_name": "界面测试", "avatar_character_id": str(GameDatabase.characters.keys()[0]), "is_host": true}], "chat_history": []}
	# 大厅组件；变更聊天不能重建座位或丢失其交互状态。
	var lobby: OnlineLobbyPanel = menu.get_node("OnlineLobbyPanel") as OnlineLobbyPanel
	lobby.bind_lobby(snapshot)
	menu.show_online_lobby()
	await _settle()
	await _capture("06_lobby")
	# 第一张座位节点标识；快照重复绑定后应保持实例不变。
	var seat_id: int = (lobby.get("_seat_views") as Array)[0].get_instance_id()
	snapshot["chat_history"] = [{"display_name": "界面测试", "message": "缓存验证"}]
	lobby.bind_lobby(snapshot)
	if not _check((lobby.get("_seat_views") as Array)[0].get_instance_id() == seat_id, "聊天刷新不得重建座位"):
		return
	lobby.call("_open_settings")
	await _settle()
	await _capture("07_lobby_settings")
	lobby.call("_close_settings")
	await _settle()
	if not _check(not (lobby.get_node("%OnlineLobbySettingsPanel") as Control).visible, "大厅设置必须完整退出"):
		return
	lobby.call("_open_settings")
	lobby.confirm_match_started()
	if not _check(not lobby.visible and not (lobby.get_node("%OnlineLobbySettingsPanel") as Control).visible, "权威开局必须立即清理大厅及其模态"):
		return
	# 关闭动效时必须同步关闭，便于静态展示与业务测试复用。
	presentation.set("animations_enabled", false)
	menu.visible = false
	await get_tree().process_frame
	if not _check((presentation.get_node("Motion").get("_active") as Dictionary).is_empty(), "离开首页必须回收全部过渡"):
		return
	main.queue_free()
	await get_tree().process_frame
	print("MENU_PRESENTATION_PASS: pages, modes, three themes, input geometry, modal cancellation, gallery, replay, lobby reuse, battle isolation")
	get_tree().quit(0)
