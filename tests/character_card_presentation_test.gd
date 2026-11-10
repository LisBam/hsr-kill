extends Control

## 正式武将牌的集中表现检查；三主题截图与状态边界在同一次图形运行完成，不启动对局或网络。

## 正式武将牌资源；所有检查和截图均消费真实组件，避免维护平行展示实现。
const CARD_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")
## 预览放大比例；默认1.2方便比较饰面，正式牌面尺寸依然由生产资源定义。
const PREVIEW_SCALE: float = 1.2
## 预览使用的数据库ID；覆盖不同势力、长名字与正式插画。
const CHARACTER_IDS: Array[String] = ["gepard", "natasha", "march_7th", "danheng_tenghuang", "dan_heng", "gepard", "natasha", "march_7th"]
## 每个预览的状态说明；只属于验证画布，不加入正式牌面。
const STATE_LABELS: Array[String] = ["普通 · 四点体力", "选中 · 仅边框", "残血 · 一点体力", "护盾 · 长姓名", "高体力 · 数字模式", "翻面 · 原遮挡层", "阵亡 · 原状态层", "离场 · 原透明度"]
## 已创建的正式视图；主题切换复用实例，不重建场景。
var _cards: Array[PlayerTargetView] = []
## 原输入几何；装饰和悬停完成后应保持完全一致。
var _input_rects: Array[Rect2] = []
## 累积失败数；集中输出结果后以非零退出，不停在调试器断点。
var _failures: int = 0


## 自动加载完成后再创建正式组件，避免把数据库尚未就绪误判为界面缺失。
func _ready() -> void:
	call_deferred("_run")


## 记录失败而不影响剩余状态检查，使一次运行覆盖全部预览状态。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("CHARACTER_CARD_PRESENTATION_FAIL: " + message)


## 构建真实场景矩阵并集中核对输入、信息保密、数值模式、主题与节点生命周期。
func _run() -> void:
	GameSettings.set("_settings_file_path", "res://.godot/character_card_presentation.cfg")
	await GameDatabase.wait_until_ready()
	# 全屏背景；只属于验证画布，不介入武将牌实现。
	var backdrop: ColorRect = ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	# 预览标题；字体和位置独立于正式牌面。
	var title: Label = Label.new()
	title.position = Vector2(38.0, 20.0)
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	# 预览状态说明标签；主题切换时统一更新可读颜色。
	var captions: Array[Label] = []
	for index: int in range(CHARACTER_IDS.size()):
		# 当前真实武将定义；ID必须有效，不能靠占位牌掩盖错误夹具。
		var definition: Dictionary = GameDatabase.get_character(CHARACTER_IDS[index])
		_check(not definition.is_empty(), "missing character: " + CHARACTER_IDS[index])
		# 当前正式武将牌；边界信息仍通过已有公开配置入口传入。
		var card: PlayerTargetView = CARD_SCENE.instantiate() as PlayerTargetView
		card.position = Vector2(62.0 + float(index % 4) * 305.0, 98.0 + float(index / 4) * 296.0)
		card.scale = Vector2.ONE * PREVIEW_SCALE
		add_child(card)
		card.set_match_overlays_visible(true)
		# 序列化测试快照；不拥有权威状态，仅覆盖表现分支。
		var snapshot: Dictionary = {"player_id":index, "character_id":CHARACTER_IDS[index], "display_name":"开拓者", "identity":"leader" if index == 0 else "hidden", "alive":index != 6, "out_of_game":index == 7, "face_down":index == 5, "hp":1 if index == 2 else (6 if index == 4 else 3), "max_hp":8 if index == 4 else 4, "shield":2 if index == 3 else 0, "hand_count":4, "equipment":{}, "judgment_area":[]}
		card.configure_snapshot(snapshot, definition, false, GameDatabase.get_faction(str(definition.get("faction", ""))))
		if index == 1:
			card.set_target_state(true, true, true)
		_cards.append(card)
		_input_rects.append((card.get_node("InputArea") as Control).get_global_rect())
		# 画布说明；位于原牌面外，不进入武将牌内部排版。
		var caption: Label = Label.new()
		caption.text = STATE_LABELS[index]
		caption.position = card.position + Vector2(0.0, -28.0)
		caption.add_theme_font_size_override("font_size", 14)
		add_child(caption)
		captions.append(caption)
	for style_id: String in UIStyleRegistry.get_style_ids():
		BattleUIStyle.set_active_style(style_id)
		backdrop.color = BattleUIStyle.get_color("table_background", Color("20242c"))
		title.text = "武将牌 · 材质与状态 / " + style_id
		title.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
		for caption: Label in captions:
			caption.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		for card: PlayerTargetView in _cards:
			card.refresh_ui_style()
			card.get_node("CardFinish").set_hovered(true)
		# 布局帧先于有限动画检查；首帧贴图编译的耗时不能替代实际布局帧。
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.30).timeout
		for index: int in range(_cards.size()):
			# 当前待检查的正式牌面；饰面不能引入第二份输入或额外布局尺寸。
			var card: PlayerTargetView = _cards[index]
			_check((card.get_node("InputArea") as Control).get_global_rect().is_equal_approx(_input_rects[index]), "input geometry changed")
			_check(card.get_node("CharacterCornerStack").get_index() > card.get_node("InputArea").get_index(), "corner action input order changed")
			_check(not (card.get_node("SelectedTargetMarker") as Label).visible, "selection text reappeared")
			_check(is_equal_approx((card.get_node("IdentityBadge") as Label).get_theme_stylebox("normal").bg_color.a, 1.0), "identity background is transparent")
			# 相同快照刷新签名不得替换既有体力节点；装饰跟随原节点生命周期。
			var first_pip_id: int = card.get_node("HealthFrame/HealthPips").get_child(0).get_instance_id()
			card.set_target_state(card.is_legal_target, card.is_target_selected, card.is_target_selection_active)
			_check(card.get_node("HealthFrame/HealthPips").get_child(0).get_instance_id() == first_pip_id, "selection rebuilt health pips")
		_check((_cards[4].get_node("HealthFrame/HealthPips").get_child(0) as Label).text == "6\n/\n8", "numeric health changed")
		_check((_cards[5].get_node("牌背") as Panel).visible, "face-down overlay lost")
		_check(is_equal_approx(_cards[7].modulate.a, _cards[7].out_of_game_modulate.a), "out-of-game transparency changed")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/character_card_review"))
			get_viewport().get_texture().get_image().save_png("res://.godot/character_card_review/%s.png" % style_id)
	print("CHARACTER_CARD_PRESENTATION_%s failures=%d" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
