extends Node

## 经典战斗历史配色回归：使用正式主场景、公开快照和真实详情组件，不依赖可选的菜单/战斗动效装配器。

## 正式主场景；保留工作区场景布局与装配选择，仅验证颜色链路。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 战斗语义入口；实际组件通过同一适配器获取历史颜色。
const BATTLE_STYLE: Script = preload("res://scripts/ui/battle_surface_style.gd")
## 入场和布局等待秒数；0.35秒覆盖当前最长过渡及两次容器排序。
const SETTLE_SECONDS: float = 0.35
## ffddb75a提交前a61e4959的固定颜色样本；防止后续调色偏离指定参考。
## 当前样本保留历史深色明度，并按主菜单炭黑/香槟金语义进行小幅同色系统一。
const EXPECTED_COLORS: Dictionary = {
	"outer_background": Color("252525"),
	"table_surface": Color("282725"),
	"table_inner": Color("34322e"),
	"rail": Color("282725"),
	"panel": Color("282725f2"),
	"metal_panel": Color("242321f7"),
	"border": Color("b9a47d"),
	"accent": Color("d5b67a"),
	"action_button": Color("3e372c"),
	"text_primary": Color("f7f1e5"),
	"text_secondary": Color("cfc5b3"),
	"selection_panel": Color("282725f2"),
	"equipment_background": Color("eeeae2"),
	"equipment_text": Color("292621"),
	"card_paper": Color("f4f1e9"),
}


## 等正式数据库完成后开始；暂停详情时测试驱动仍能继续退出。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 失败立即返回非零状态，不停在调试断点。
func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("CLASSIC_BATTLE_PALETTE_FAIL: " + message)
		get_tree().quit(1)
	return condition


## 图形模式输出真实牌桌和详情；普通无头回归不读取GPU。
func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/classic_palette_review"))
	get_viewport().get_texture().get_image().save_png("res://.godot/classic_palette_review/%s.png" % file_name)


## 只读八人快照；角色与牌面来自正式数据库，界面展示不创建权威对局。
func _make_snapshot() -> Dictionary:
	# 确定的公开武将序列；覆盖真实牌面、势力与原画。
	var character_ids: Array[String] = ["gepard", "march_7th", "natasha", "dan_heng", "gepard", "march_7th", "natasha", "dan_heng"]
	# 本地公开手牌；其他玩家只看到数量。
	var hand: Array = [{"uid":901, "definition_id":"sha", "suit":"spade", "rank":7, "zone":"hand", "owner_id":0}, {"uid":902, "definition_id":"shan", "suit":"heart", "rank":3, "zone":"hand", "owner_id":0}]
	# 公开角色字典；只供正式牌桌渲染。
	var players: Array = []
	for index: int in range(character_ids.size()):
		players.append({"player_id":index, "seat_number":index + 1, "display_name":"玩家%d" % (index + 1), "character_id":character_ids[index], "identity":"leader" if index == 0 else "unknown", "identity_revealed":index == 0, "alive":true, "hp":4, "max_hp":4, "hand_count":2, "hand":hand if index == 0 else [], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "wooden_ox_storage_count":0})
	return {"players":players, "current_player_id":0, "current_phase":"play", "turn_number":3, "round_number":2, "draw_pile_count":87, "discard_pile_count":16, "game_over":false, "match_mode":"identity"}


## 检查配色来源、主题边界和真实组件的最终颜色，保持现有场景修改。
func _run() -> void:
	GameSettings.set("_settings_file_path", "res://.godot/classic_battle_palette_test.cfg")
	get_viewport().gui_disable_input = true
	await GameDatabase.wait_until_ready()
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_CLASSIC)
	if not _check(BATTLE_STYLE.get_color("accent").is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, "accent")) and BATTLE_STYLE.get_color("border").is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, "border")) and BATTLE_STYLE.get_color("text_primary").is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, "on_dark")), "战斗金色和正文未与主菜单深色表面统一"):
		return
	for key: String in EXPECTED_COLORS:
		if not _check(BATTLE_STYLE.get_color(key).is_equal_approx(EXPECTED_COLORS[key]), "经典战斗语义不一致: " + key):
			return
	# 正式场景实例；禁止控制器自动创建随机对局。
	var main: Control = MAIN_SCENE.instantiate() as Control
	# 控制器仅用于转发快照，不操作规则状态。
	var controller: MatchController = main.get_node("MatchController") as MatchController
	controller.default_player_count = 1
	controller.local_human_player_id = 0
	controller.randomize_local_human_seat = false
	add_child(main)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	# 当前主题两处入口；经典与夜间顺序继续保留。
	var style_option: OptionButton = main.get_node("%MainMenuUiStyleOption") as OptionButton
	if not _check(str(style_option.get_item_metadata(0)) == UIStyleRegistry.STYLE_CLASSIC and str(style_option.get_item_metadata(1)) == UIStyleRegistry.STYLE_NIGHT, "主题入口顺序改变"):
		return
	if not _check((main.get_node("%MainMenuBackgroundSurface") as ColorRect).color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_SPACE_MONO, "table_surface")), "经典主菜单纸金色发生变化"):
		return
	main.get_node("MainMenu").hide()
	# 公开快照与副本；确认调色不会修改牌桌数据。
	var snapshot: Dictionary = _make_snapshot()
	# 验证结束时用于比较的只读副本。
	var original_snapshot: Dictionary = snapshot.duplicate(true)
	controller.state_changed.emit(snapshot)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	# 实际背景组件；覆盖外底、中心与边缘色，不依赖仅查询注册表的断言。
	var backdrop: ReferenceBackdrop = main.get_node("ReferenceBackdrop") as ReferenceBackdrop
	if not _check(backdrop.outer_background_color.is_equal_approx(EXPECTED_COLORS["outer_background"]) and backdrop.table_surface_color.is_equal_approx(EXPECTED_COLORS["table_surface"]) and backdrop.table_inner_color.is_equal_approx(EXPECTED_COLORS["table_inner"]), "历史背景色未落到真实牌桌"):
		return
	await _capture("battle")
	# 实际武将详情；检查完整正文与暗色面板相匹配。
	var information: InformationBoxLayer = main.get("information_box") as InformationBoxLayer
	information.show_character_details(snapshot["players"][0], GameDatabase.get_character("gepard"))
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	# 当前详情的首个技能说明；使用正式组件创建的富文本分段。
	var description: SkillDescriptionView = information.get_character_skill_list().get_child(0).get_child(1) as SkillDescriptionView
	if not _check(Color(str(description.get_rendered_segments()[0]["color"])).is_equal_approx(EXPECTED_COLORS["text_secondary"]), "详情正文未恢复历史颜色"):
		return
	await _capture("details")
	information.close_character_details()
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	if not _check(snapshot == original_snapshot, "调色改变了公开快照"):
		return
	main.queue_free()
	await get_tree().process_frame
	print("CLASSIC_BATTLE_PALETTE_PASS")
	get_tree().quit(0)
