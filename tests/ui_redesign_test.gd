extends Node

## 纸金界面行为回归。验证真实控件是否可见、滚动后可达及页面切换后的布局；不以截屏像素代替交互契约。

## 正式场景；所有检查基于玩家实际使用的控件实例。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 需要验证的逻辑客户区；覆盖默认横屏、较高窗口和超宽窗口，单位为逻辑像素。
const VIEWPORT_SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1152, 648), Vector2(1280, 800), Vector2(1680, 720)]
## 最大内容准备帧数；防止加载失败导致测试无限挂起，正常缓存加载远低于此上限。
const MAX_LOAD_FRAMES: int = 1800
## 累计失败数量；从0开始，任一几何或交互约束失败都会令进程返回非零。
var _failures: int = 0


## 等场景树可安全挂载真实界面后再启动。
func _ready() -> void:
	call_deferred("_run")


## 记录独立失败并允许后续检查给出更多定位信息。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("UI_REDESIGN_FAIL: " + message)


## 等待布局和有限过渡完成；不修改玩法时间倍率。
func _settle() -> void:
	await get_tree().create_timer(0.36).timeout


## 渲染进程可选择输出审查图，无头回归不读取GPU内容。
func _capture(name_hint: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/ui_redesign_review"))
	get_viewport().get_texture().get_image().save_png("res://.godot/ui_redesign_review/%s.png" % name_hint)


## 检查横向模式浏览、图鉴列宽、设置安全区、主题对比度与大厅最大人数的排布。
func _run() -> void:
	GameSettings.set("_settings_file_path", "res://.godot/ui_redesign_settings.cfg")
	GameSettings.set_ui_style(UIStyleRegistry.DEFAULT_STYLE_ID)
	await GameDatabase.wait_until_ready()
	# 主场景独立实例；不创建网络会话或自动开始对局。
	var main: Control = MAIN_SCENE.instantiate() as Control
	add_child(main)
	await _settle()
	# 首页业务组件；测试通过真实按钮发出导航操作。
	var menu: MainMenu = main.get_node("MainMenu") as MainMenu
	# 横向浏览视口；其范围必须覆盖七种模式且允许末项完整进入。
	var mode_scroll: ScrollContainer = menu.get_node("%MainMenuModeScroll") as ScrollContainer
	for viewport_size: Vector2 in VIEWPORT_SIZES:
		main.size = viewport_size
		await _settle()
		_check((menu.get_node("%MainMenuTopNavigation") as Control).get_global_rect().end.y <= (menu.get_node("%MainMenuFrame") as Control).global_position.y, "紧凑窗口导航与卡片重叠")
		(menu.get_node("%IdentityModeButton") as Button).pressed.emit()
		await _settle()
		# 第一张卡的可见标题；确保锚点没有把文字排到按钮之外。
		var title: Label = menu.get_node("%IdentityModeName") as Label
		# 第一张真实模式按钮；标题必须完整落在自己的命中区域内。
		var card: Button = menu.get_node("%IdentityModeButton") as Button
		_check(card.get_global_rect().encloses(title.get_global_rect()), "模式标题越过卡面：%s" % viewport_size)
		_check(mode_scroll.get_global_rect().encloses(card.get_global_rect()), "首张模式卡未完整可见：%s" % viewport_size)
		(menu.get_node("%WinnerTakesAllModeButton") as Button).pressed.emit()
		await _settle()
		# 最后一张模式卡；确保右端可以通过正式选择入口滚动到达。
		var last_card: Button = menu.get_node("%WinnerTakesAllModeButton") as Button
		_check(mode_scroll.scroll_horizontal > 0 and mode_scroll.get_global_rect().grow(1.0).encloses(last_card.get_global_rect()), "横向模式末项不可达：%s" % viewport_size)
		(menu.get_node("%MainMenuSettingsButton") as Button).pressed.emit()
		await _settle()
		# 两栏设置页；外壳和返回按钮都必须在当前逻辑窗口内。
		var sheet: Control = menu.get_node("MainMenuSettingsPanel") as Control
		# 原生返回按钮；保留原业务信号，重排不能使它落到滚动区域之外。
		var close: Button = menu.get_node("%MainMenuSettingsCloseButton") as Button
		_check(Rect2(main.global_position, main.size).encloses(sheet.get_global_rect()), "设置面板超出窗口：%s" % viewport_size)
		_check(sheet.get_global_rect().encloses(close.get_global_rect()), "设置返回按钮不可见")
		_check((menu.get_node("%MainMenuMulliganLimitOption") as OptionButton).item_count > 0, "设置重排丢失原下拉选项")
		for scroll: ScrollContainer in sheet.find_children("*", "ScrollContainer", true, false):
			for option: OptionButton in scroll.find_children("*", "OptionButton", true, false):
				_check(option.get_global_rect().end.x <= scroll.get_v_scroll_bar().global_position.x - 4.0, "设置下拉框被滚动条遮挡：%s" % option.name)
		# 最后一项偏好设置；键盘聚焦必须让超出首屏的控件自动滚入可见范围。
		var last_preference: CheckBox = menu.get_node("%MainMenuAudioMutedCheckBox") as CheckBox
		last_preference.grab_focus()
		await _settle()
		# 焦点跟随所在滚动区；通过祖先遍历而非固定父路径读取重排后的真实容器。
		var ancestor: Node = last_preference.get_parent()
		while ancestor != null and not ancestor is ScrollContainer:
			ancestor = ancestor.get_parent()
		_check(ancestor != null and (ancestor as Control).get_global_rect().encloses(last_preference.get_global_rect()), "键盘聚焦不能显露末项设置")
		close.pressed.emit()
		await _settle()
	main.size = VIEWPORT_SIZES[0]
	(menu.get_node("%IdentityModeButton") as Button).pressed.emit()
	await _settle()
	await _capture("01_home")
	(menu.get_node("%MainMenuOnlineSettingsButton") as Button).pressed.emit()
	await _settle()
	# 联机形象必须在全宽内容区内完成首屏加载，不能把空列表误判为已完成。
	var profile: OnlineSettingsPanel = menu.get_node("OnlineSettingsPanel") as OnlineSettingsPanel
	for frame_index: int in range(MAX_LOAD_FRAMES):
		if not (profile.get("_view_loader") as Node).is_processing():
			break
		await get_tree().process_frame
	_check((profile.get("_avatar_views") as Dictionary).size() > 0, "联机资料首屏没有武将形象")
	await _capture("05_profile")
	(menu.get_node("%MainMenuAllCardsButton") as Button).pressed.emit()
	await _settle()
	# 正式图鉴组件；加载调度仍由原组件拥有。
	var gallery: Control = menu.get_node("AllCardsPanel") as Control
	for frame_index: int in range(MAX_LOAD_FRAMES):
		if not (gallery.get("_loading_cover") as Control).visible:
			break
		await get_tree().process_frame
	_check(not (gallery.get("_loading_cover") as Control).visible, "图鉴首屏未完成准备")
	# 图鉴条目槽；同一行至少两张，防止沿用旧侧栏扣减公式后退化成单列。
	var entries: Array = gallery.get("_entries") as Array
	if entries.size() >= 2:
		# 两个相邻槽的坐标；只比较实际排版结果，不依赖内部列数实现。
		var first_slot: Control = entries[0]["slot"] as Control
		# 下一张卡；必须与第一张同排且在其右侧。
		var second_slot: Control = entries[1]["slot"] as Control
		_check(second_slot.position.x > first_slot.position.x and is_equal_approx(second_slot.position.y, first_slot.position.y), "图鉴宽度计算仍依赖旧侧栏")
	await _capture("02_gallery")
	(menu.get_node("%TopIdentityModeButton") as Button).pressed.emit()
	await _settle()
	(menu.get_node("%MainMenuSettingsButton") as Button).pressed.emit()
	await _settle()
	for scroll: ScrollContainer in menu.get_node("MainMenuSettingsPanel").find_children("*", "ScrollContainer", true, false):
		scroll.scroll_vertical = 0
	await _settle()
	await _capture("03_settings")
	(menu.get_node("%MainMenuSettingsCloseButton") as Button).pressed.emit()
	await _settle()
	# 十人大厅；空位也是可交互实体，验证每个位完整处于座位区而不盖住聊天。
	var lobby: OnlineLobbyPanel = menu.get_node("OnlineLobbyPanel") as OnlineLobbyPanel
	lobby.bind_lobby({"members":[], "player_count":10, "game_mode_id":"identity", "role":"host", "local_peer_id":1, "chat_history":[]})
	menu.show_online_lobby()
	await _settle()
	# 大厅座位视口；十个位置必须同时可见，无需滚动或重叠。
	var seat_area: Control = lobby.get_node("%OnlineLobbySeatArea") as Control
	for seat: Control in lobby.get("_seat_views") as Array:
		_check(Rect2(Vector2.ZERO, seat_area.size).grow(1.0).encloses(Rect2(seat.position, seat.size)), "十人大厅座位超出座位区")
	await _capture("04_lobby_ten")
	print("UI_REDESIGN_RESULT failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
