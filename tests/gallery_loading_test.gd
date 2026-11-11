extends Node

## 验证正式图鉴的后台加载、滚动缓存、快速切页、空搜索、取消形象编辑与目录失效。

## 调试环境的任务等待上限（毫秒）；只防止测试永久挂起，不限制玩家设备的实际加载速度。
const WAIT_TIMEOUT_MS: int = 15000


## 等待测试根入树后开始，避免混淆组件装配与测试驱动。
func _ready() -> void:
	call_deferred("_run")


## 使用玩家的完整主场景，验证界面状态与节点身份，测试不保存玩家偏好。
func _run() -> void:
	await GameDatabase.wait_until_ready()
	# 正式主场景；动态加载保持组件装配路径与游戏一致。
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 独立主场景实例；测试结束显式释放以核对异步任务与节点生命周期。
	var main: Control = packed.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	# 首页控制器；使用现有页面入口，覆盖焦点隔离和加载器显隐边界。
	var menu: MainMenu = main.get_node("%MainMenu") as MainMenu
	# 联机形象页；选择只是本地临时数据，保存前不得修改GameSettings。
	var online: OnlineSettingsPanel = main.get_node("%OnlineSettingsPanel") as OnlineSettingsPanel
	# 三分类图鉴；加载、搜索和缓存均通过正式组件验证。
	var gallery: AllCardsPanel = main.get_node("%AllCardsPanel") as AllCardsPanel
	menu.call("_open_online_settings")
	if not await _wait_for_idle(online):
		return
	# 第一次访问后的完整目录；固定尺寸槽必须覆盖所有武将。
	var avatar_entries: Array = online.get("_avatar_entries")
	# 第一张正式牌面；后续滚动与重开必须保留这个对象的身份。
	var first_view: Node = avatar_entries[0]["view"]
	# 打开时恢复的已保存形象；取消后必须回到它，而不是最后临时点击的候选。
	var saved_selection: String = str(online.get("_selected_character_id"))
	if not _check(avatar_entries.size() == GameDatabase.characters.size() and is_instance_valid(first_view), "形象首屏或完整目录缺失"):
		return
	if not _check((main.get_node("%StartGameButton") as Control).focus_mode == Control.FOCUS_NONE and (main.get_node("%MainMenuAllCardsButton") as Control).focus_mode != Control.FOCUS_NONE, "内容页焦点边界错误"):
		return
	await _capture("online_ready")
	# 形象滚动区；真实改变滚动偏移，验证新范围唤醒与已完成范围停止处理。
	var avatar_scroll: ScrollContainer = online.get_node("%OnlineAvatarScroll") as ScrollContainer
	avatar_scroll.scroll_vertical = int(avatar_scroll.get_v_scroll_bar().max_value)
	if not await _wait_for_idle(online):
		return
	avatar_scroll.scroll_vertical = 0
	if not await _wait_for_idle(online):
		return
	if not _check(avatar_entries[0]["view"] == first_view, "滚动回看重建了已有牌面"):
		return
	# 最近加载过的另一候选；不保存，以验证关闭重开时恢复原设置。
	var candidate_ids: Array = (online.get("_avatar_views") as Dictionary).keys()
	online.call("_select_avatar", str(candidate_ids.back()))
	menu.call("_select_identity_mode")
	menu.call("_open_online_settings")
	if not await _wait_for_idle(online):
		return
	if not _check(str(online.get("_selected_character_id")) == saved_selection and (online.get("_avatar_entries") as Array)[0]["view"] == first_view, "重开没有恢复保存选择或复用节点"):
		return
	# 同一帧切换分类并清空结果；旧队列必须丢弃，空列表不能残留加载遮罩。
	menu.call("_open_all_cards")
	gallery.call("_select_category", "game_cards")
	gallery.call("_select_category", "opportunities")
	gallery.call("_select_category", "characters")
	# 正式搜索输入框；文本与信号按玩家编辑后的同一值同步。
	var search: LineEdit = gallery.get_node("%AllCardsSearchInput") as LineEdit
	search.text = "__no_gallery_result__"
	search.text_changed.emit(search.text)
	if not await _wait_for_idle(gallery):
		return
	if not _check(not (gallery.get("_loading_cover") as Control).visible and not (online.get("_view_loader") as Node).is_processing(), "空结果或隐藏页面仍在等待加载"):
		return
	search.text = ""
	search.text_changed.emit("")
	if not await _wait_for_idle(gallery):
		return
	# 武将图鉴首个正式对象；跨分类必须原样恢复。
	var character_view: Node = (gallery.get("_entries") as Array)[0]["view"]
	await _capture("characters_ready")
	for category: String in ["game_cards", "opportunities", "characters"]:
		gallery.call("_select_category", category)
		if not await _wait_for_idle(gallery):
			return
	if not _check((gallery.get("_entries") as Array)[0]["view"] == character_view, "切换分类丢弃了缓存牌面"):
		return
	GameDatabase.reload_all()
	menu.call("_open_all_cards")
	if not await _wait_for_idle(gallery):
		return
	if not _check(not is_instance_valid(character_view) and is_instance_valid((gallery.get("_entries") as Array)[0]["view"]), "数据库重载没有失效旧牌面"):
		return
	main.queue_free()
	await get_tree().process_frame
	print("GALLERY_LOADING_PASS: viewport, idle, scroll reuse, cancel, rapid switching, empty search, category reuse, database reload")
	get_tree().quit()


## 等待事件触发后的加载队列清空；至少让出两帧，涵盖延迟布局与滚动条的值钳制。
func _wait_for_idle(panel: Control) -> bool:
	# 本次等待终点；超时明确失败，避免固定等待帧数依赖设备速度。
	var deadline: int = Time.get_ticks_msec() + WAIT_TIMEOUT_MS
	await get_tree().process_frame
	await get_tree().process_frame
	while (panel.get("_view_loader") as Node).is_processing():
		if Time.get_ticks_msec() > deadline:
			return _check(false, "图鉴加载任务超时")
		await get_tree().process_frame
	return true


## 记录首个失败并以非零退出码停止独立进程。
func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("GALLERY_LOADING_FAIL: ", message)
		get_tree().quit(1)
	return condition


## 显式传入--capture-gallery时保存实际渲染结果；无头回归不请求GPU读回。
func _capture(file_name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture-gallery") or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/menu_review"))
	get_viewport().get_texture().get_image().save_png("res://.godot/menu_review/%s.png" % file_name)
