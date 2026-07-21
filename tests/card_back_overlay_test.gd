extends Node

## 牌背覆盖层回归测试。验证手牌与武将牌都使用场景内节点遮挡信息，而非改写底层展示数据；并校验隐藏候选选中时牌背外框与正面共用 accent 描边。

## 正式手牌场景；测试必须实例化生产资源，避免节点路径与层级在独立样例中失效。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 正式武将牌场景；测试快照中的 face_down 状态必须由该组件消费。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")


## 延迟执行断言，确保测试根节点与自动加载均已进入场景树。
func _ready() -> void:
	call_deferred("_run")


## 检查牌背覆盖层的默认状态、手牌切换语义和武将翻面快照同步。
func _run() -> void:
	# 正式手牌实例；先写入正面数据，再确认牌背切换不会清空这些可复用缓存。
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	add_child(card_view)
	await get_tree().process_frame
	# 标准【杀】实体快照；字段与手牌渲染接口保持一致。
	var card_data: Dictionary = {"uid":99001, "definition_id":"sha", "suit":"spade", "rank":7}
	# 标准【杀】定义；用于验证正面名称在显示牌背后仍保留在底层视图中。
	var card_definition: Dictionary = GameDatabase.get_card("sha")
	card_view.configure(card_data, card_definition, false, true)
	# 手牌牌背节点；场景默认必须隐藏，正面配置后也不得意外显示。
	var card_back: Panel = card_view.get_node("牌背") as Panel
	if card_back == null or card_back.visible:
		_fail("card_back_default_visibility")
		return
	# 底层牌名标签；切换到牌背前记录文本，验证信息隐藏改由覆盖层完成。
	var card_name_label: Label = card_view.get_node("CardBody/Name") as Label
	# 正面牌名；没有有效名称说明测试前置数据无效。
	var front_name: String = card_name_label.text
	if front_name.is_empty():
		_fail("card_front_name_missing")
		return
	card_view.configure_back(99001, true)
	if not card_back.visible or card_name_label.text != front_name:
		_fail("card_back_overlay_switch")
		return
	# 未选中牌背；默认主题边框色与 2 像素宽度，不能误用强调金色。
	var unselected_back_style: StyleBoxFlat = card_back.get_theme_stylebox("panel") as StyleBoxFlat
	if unselected_back_style == null or not unselected_back_style.border_color.is_equal_approx(BattleUIStyle.get_color("border")) or unselected_back_style.border_width_left != 2:
		_fail("card_back_unselected_border:%s/%d" % [unselected_back_style.border_color if unselected_back_style != null else Color.TRANSPARENT, unselected_back_style.border_width_left if unselected_back_style != null else -1])
		return
	# 选中牌背；必须与正面选中态共用 accent 色和 3 像素描边，覆盖【寒冰剑】等隐藏候选与五谷丰登一致的选中反馈。
	card_view.set_selected_state(true)
	var selected_back_style: StyleBoxFlat = card_back.get_theme_stylebox("panel") as StyleBoxFlat
	if selected_back_style == null or not selected_back_style.border_color.is_equal_approx(BattleUIStyle.get_color("accent")) or selected_back_style.border_width_left != 3:
		_fail("card_back_selected_border:%s/%d" % [selected_back_style.border_color if selected_back_style != null else Color.TRANSPARENT, selected_back_style.border_width_left if selected_back_style != null else -1])
		return
	# 取消选中后牌背必须恢复默认边框，避免残留强调描边。
	card_view.set_selected_state(false)
	var restored_back_style: StyleBoxFlat = card_back.get_theme_stylebox("panel") as StyleBoxFlat
	if restored_back_style == null or not restored_back_style.border_color.is_equal_approx(BattleUIStyle.get_color("border")) or restored_back_style.border_width_left != 2:
		_fail("card_back_restored_border:%s/%d" % [restored_back_style.border_color if restored_back_style != null else Color.TRANSPARENT, restored_back_style.border_width_left if restored_back_style != null else -1])
		return
	# 独立输入区必须位于牌背之后，使已隐藏候选仍能接收选择输入。
	var card_input_area: Control = card_view.get_node("InputArea") as Control
	if card_back.get_index() >= card_input_area.get_index():
		_fail("card_back_input_order")
		return
	# 视为牌快照；原实体【闪】保留原牌面名称，逻辑定义【桃】只显示在贯穿插画的独立横条中。
	var view_as_card_data: Dictionary = {"uid":99002, "definition_id":"tao", "original_definition_id":"shan", "suit":"heart", "rank":8}
	card_view.configure(view_as_card_data, GameDatabase.get_card("tao"), false, true)
	# 原牌名称标签；当前名称模式下必须继续显示实体【闪】而不是逻辑【桃】。
	var original_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card("shan"))
	# 视为横条；节点必须显示逻辑【桃】且位于牌面中部，不替代原名称标签。
	var view_as_banner: Panel = card_view.get_node("CardBody/ViewAsBanner") as Panel
	var view_as_name: Label = card_view.get_node("CardBody/ViewAsBanner/Name") as Label
	var viewed_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card("tao"))
	if card_name_label.text != original_name or view_as_banner == null or not view_as_banner.visible or view_as_name == null or view_as_name.text != viewed_name or not is_equal_approx(view_as_banner.position.y + view_as_banner.size.y * 0.5, card_view.card_height * 0.5):
		_fail("card_view_as_banner:%s/%s/%s" % [card_name_label.text, view_as_name.text if view_as_name != null else "", view_as_banner.get_rect() if view_as_banner != null else Rect2()])
		return
	# 视为横条样式；红桃【闪】视为【桃】时，底板使用牌面白色、边框使用逻辑基本牌色、文字使用红色牌名色。
	var view_as_banner_style: StyleBoxFlat = view_as_banner.get_theme_stylebox("panel") as StyleBoxFlat
	# 期望底板色；不透明度沿用卡牌组件的可配置参数。
	var expected_banner_background: Color = BattleUIStyle.get_color("card_paper")
	expected_banner_background.a = card_view.view_as_banner_opacity
	# 期望边框色；逻辑【桃】属于基本牌，横条边框保留0.96不透明度。
	var expected_banner_border: Color = BattleUIStyle.get_color("card_basic")
	expected_banner_border.a = 0.96
	if view_as_banner_style == null or not view_as_banner_style.bg_color.is_equal_approx(expected_banner_background) or not view_as_banner_style.border_color.is_equal_approx(expected_banner_border) or not view_as_name.get_theme_color("font_color").is_equal_approx(BattleUIStyle.get_color("card_red_suit")):
		_fail("card_view_as_banner_style:%s/%s/%s" % [view_as_banner_style.bg_color if view_as_banner_style != null else Color.TRANSPARENT, view_as_banner_style.border_color if view_as_banner_style != null else Color.TRANSPARENT, view_as_name.get_theme_color("font_color")])
		return
	# 普通牌重新配置后横条必须隐藏，避免旧实体复用时残留视为状态。
	card_view.configure(card_data, card_definition, false, true)
	if view_as_banner.visible:
		_fail("card_view_as_banner_clear")
		return

	# 正式武将牌实例；直接消费裁剪快照验证 face_down 到覆盖层的映射。
	var player_target_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	add_child(player_target_view)
	await get_tree().process_frame
	# 面朝上的公开角色快照；空公开区域避免引入与本测试无关的装备布局。
	var player_snapshot: Dictionary = {
		"player_id":77,
		"display_name":"测试玩家",
		"character_id":"",
		"identity":"hidden",
		"hp":4,
		"max_hp":4,
		"alive":true,
		"chained":false,
		"face_down":false,
		"hand_count":4,
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage_count":0,
	}
	player_target_view.configure_snapshot(player_snapshot)
	# 武将牌牌背节点；面朝上时保持默认隐藏。
	var player_card_back: Panel = player_target_view.get_node("牌背") as Panel
	if player_card_back == null or player_card_back.visible:
		_fail("player_card_back_front_visibility")
		return
	# 翻面快照；只切换视觉覆盖层，不需要创建第二张武将牌或改写规则对象。
	player_snapshot["face_down"] = true
	player_target_view.configure_snapshot(player_snapshot)
	if not player_card_back.visible:
		_fail("player_card_back_face_down_visibility")
		return
	# 武将牌输入区必须高于覆盖层，维持目标选择与卡牌拖放行为。
	var player_input_area: Control = player_target_view.get_node("InputArea") as Control
	if player_card_back.get_index() >= player_input_area.get_index():
		_fail("player_card_back_input_order")
		return

	print("CARD_BACK_OVERLAY_PASS")
	get_tree().quit(0)


## 输出统一失败原因并以非零状态结束测试，方便命令行与持续集成定位断言。
func _fail(reason: String) -> void:
	printerr("CARD_BACK_OVERLAY_FAIL %s" % reason)
	get_tree().quit(1)
