extends Node

## 验证图鉴与联机形象的可见范围加载、缓存复用和目录失效。

## 正式主场景；测试复用真实菜单与两个内容面板。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## 等待若干绘制帧，使分帧牌面创建与滚动布局完成。
func _wait_frames(count: int = 40) -> void:
	for frame_index: int in range(count):
		await get_tree().process_frame


## 验证滚动回看、切换分类、关闭重开和数据库重载的缓存行为。
func _ready() -> void:
	# 正式主场景和菜单；覆盖真实布局与页面生命周期。
	var main: Control = MAIN_SCENE.instantiate() as Control
	add_child(main)
	await GameDatabase.wait_until_ready()
	var menu: Control = main.get_node("MainMenu")
	var gallery: Control = menu.get_node("AllCardsPanel")
	var online: Control = menu.get_node("OnlineSettingsPanel")
	gallery.open_panel()
	assert((gallery.get("_loading_cover") as Control).visible, "首屏准备时应遮住分帧过程")
	await _wait_frames()
	# 第一条武将牌面；用节点身份验证滚动与页面切换后没有重新创建。
	var entries: Array = gallery.get("_entries")
	var first_view: Node = entries[0].get("view")
	assert(is_instance_valid(first_view), "首屏武将牌应完成加载")
	assert(not (gallery.get("_loading_cover") as Control).visible, "首屏加载完成后遮罩应消失")
	var scroll: ScrollContainer = gallery.get("_grid_scroll")
	# 当前屏下方预取数量；非零表示玩家滚动前已经准备邻近牌面。
	var prefetched: int = 0
	for entry: Dictionary in entries:
		var slot: Control = entry.get("slot") as Control
		if slot.position.y >= scroll.size.y and is_instance_valid(entry.get("view")):
			prefetched += 1
	assert(prefetched > 0, "图鉴应预取当前屏下方的牌面")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _wait_frames()
	assert(entries[0].get("view") == first_view, "滚动后图鉴牌面应保留")
	scroll.scroll_vertical = 0
	await _wait_frames()
	gallery.call("_select_category", "game_cards")
	await _wait_frames()
	assert((gallery.get("_content_views") as Array).size() > 0, "游戏牌首屏应加载")
	gallery.call("_select_category", "characters")
	await _wait_frames()
	assert((gallery.get("_entries") as Array)[0].get("view") == first_view, "切换分类后图鉴牌面应复用")
	gallery.visible = false
	gallery.open_panel()
	await _wait_frames()
	assert((gallery.get("_entries") as Array)[0].get("view") == first_view, "重新打开图鉴应复用牌面")
	gallery.visible = false
	online.open_panel()
	assert((online.get("_loading_cover") as Control).visible, "形象首屏准备时应遮住分帧过程")
	await _wait_frames()
	# 已加载形象与其稳定 ID；滚动后验证同一节点和选择状态仍保留。
	var avatars: Dictionary = online.get("_avatar_views")
	assert(not avatars.is_empty(), "联机形象首屏应加载")
	var first_id: String = str(avatars.keys()[0])
	var first_avatar: Node = avatars[first_id]
	online.call("_select_avatar", first_id)
	var avatar_scroll: ScrollContainer = online.get("_avatar_scroll")
	avatar_scroll.scroll_vertical = int(avatar_scroll.get_v_scroll_bar().max_value)
	await _wait_frames()
	assert(avatars.get(first_id) == first_avatar, "滚动后形象牌应保留")
	assert(online.get("_selected_character_id") == first_id, "滚动不得清除临时选择")
	online.visible = false
	online.open_panel()
	await _wait_frames()
	assert((online.get("_avatar_views") as Dictionary).get(first_id) == first_avatar, "重新打开联机设置应复用牌面")
	assert(not (online.get("_loading_cover") as Control).visible, "形象加载完成后遮罩应消失")
	# 完整数据库重载后，旧牌面必须失效，确保开发时新增和调整内容可见。
	assert(GameDatabase.reload_all(), "数据库重载应通过校验")
	online.visible = false
	online.open_panel()
	avatar_scroll.scroll_vertical = 0
	await _wait_frames()
	assert(not is_instance_valid(first_avatar), "内容重载后应释放旧形象牌")
	assert(is_instance_valid((online.get("_avatar_views") as Dictionary).get(first_id)), "内容重载后应加载新形象牌")
	gallery.open_panel()
	await _wait_frames()
	assert(not is_instance_valid(first_view), "内容重载后应释放旧图鉴牌面")
	assert(is_instance_valid((gallery.get("_entries") as Array)[0].get("view")), "内容重载后应加载新图鉴牌面")
	print("GALLERY_CACHE_PASS")
	get_tree().quit()
