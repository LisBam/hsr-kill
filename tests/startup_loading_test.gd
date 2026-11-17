extends Node

## 验证首页先于数据库就绪，以及异步页面请求和完整数据提交。

## 正式主场景；用于覆盖与玩家启动相同的界面初始化链。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## 初始化主菜单并验证加载期间的导航请求只执行最后一次。
func _ready() -> void:
	# 正式主场景实例；测试结束时随场景树统一释放。
	var main: Control = MAIN_SCENE.instantiate() as Control
	add_child(main)
	# 内容尚未访问时首页应先显示，不能被空装备和空武将的占位查询迫使同步加载。
	assert(not GameDatabase.is_database_ready(), "首页创建前不应同步载入完整数据库")
	# 主菜单；模拟加载期间连续点击图鉴、模式选择与联机设置。
	var menu: Control = main.get_node("MainMenu")
	# 暂停主线程提交后台结果，保证真实加载提示有稳定的布局检查窗口；后台线程照常准备数据。
	GameDatabase.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	# 加载前的设置按钮矩形；状态区只能向左扩展，不能推动操作按钮。
	var settings_rect: Rect2 = (menu.get_node("%MainMenuSettingsButton") as Control).get_global_rect()
	menu.call("_open_all_cards")
	menu.call("_select_identity_mode")
	menu.call("_open_online_settings")
	await get_tree().process_frame
	await get_tree().process_frame
	# 实际导航请求触发的状态标签；按生效字体测量显示宽度，覆盖后台数据库未就绪的正式分支。
	var loading_status: Label = menu.get_node("%MainMenuStatusLabel") as Label
	# 当前字体下完整文案的宽度；字号或字体变更后断言仍以真实渲染需求为准。
	var loading_text_width: float = loading_status.get_theme_font("font").get_string_size(loading_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, loading_status.get_theme_font_size("font_size")).x
	# 加载后的设置按钮矩形；检查状态标签与按钮分别拥有可见且独立的区域。
	var loaded_settings_rect: Rect2 = (menu.get_node("%MainMenuSettingsButton") as Control).get_global_rect()
	if loading_status.text != "正在加载中..." or not loading_status.visible or loading_status.size.x < loading_text_width or loading_status.get_global_rect().intersects(loaded_settings_rect) or not settings_rect.is_equal_approx(loaded_settings_rect):
		printerr("STARTUP_LOADING_FAIL: 真实加载入口的提示被截断或改变按钮位置 text=%s width=%s required=%s before=%s after=%s" % [loading_status.text, loading_status.size.x, loading_text_width, settings_rect, loaded_settings_rect])
		get_tree().quit(1)
		return
	GameDatabase.set_process(true)
	await GameDatabase.wait_until_ready()
	await get_tree().process_frame
	# 最后请求的页面应打开，过期的图鉴请求不得在加载完成后抢占页面。
	var online: Control = menu.get_node("OnlineSettingsPanel")
	var gallery: Control = menu.get_node("AllCardsPanel")
	assert(online.visible and not gallery.visible, "加载期间只应执行最后一次有效导航")
	assert(GameDatabase.cards.size() > 0 and GameDatabase.characters.size() > 0 and GameDatabase.skills.size() > 0, "后台数据库应提交完整目录")
	assert(GameDatabase.validation_errors.is_empty(), "后台数据库应保留原有完整校验")
	# 后台结果的关键索引；同步重新加载后比较，确保两条路径登记相同内容。
	var card_ids: Array = GameDatabase.cards.keys()
	var character_ids: Array = GameDatabase.characters.keys()
	var skill_ids: Array = GameDatabase.skills.keys()
	assert(GameDatabase.reload_all(), "同步重载应通过校验")
	assert(card_ids == GameDatabase.cards.keys() and character_ids == GameDatabase.characters.keys() and skill_ids == GameDatabase.skills.keys(), "后台加载与同步重载的索引应一致")
	# 独立数据库节点；验证旧同步调用在后台加载期间读取字典时仍能得到完整结果。
	var separate_database: Node = GameDatabase.get_script().new()
	add_child(separate_database)
	await get_tree().process_frame
	await get_tree().process_frame
	# 同步读取将等待后台结果或执行安全回退，不得返回部分索引。
	var synchronous_cards: Dictionary = separate_database.get("cards")
	assert(synchronous_cards.keys() == card_ids, "直接同步读取应得到完整后台结果")
	separate_database.queue_free()
	await get_tree().process_frame
	print("STARTUP_LOADING_PASS")
	get_tree().quit()
