class_name PlayerTargetView
extends Button

## 可复用的角色状态与目标选择组件。组件渲染公开信息、反馈合法性，并接收卡牌拖放，不读取规则核心。

## 卡牌拖放到角色后的请求信号；桌面统一更新选牌与目标顺序。
signal card_dropped(card_uid: int, player_id: int)

## 角色卡默认宽度；默认172像素用于环桌武将牌布局，运行时可按玩家人数调整。
@export_range(150.0, 360.0, 1.0) var panel_width: float = 172.0

## 角色卡默认高度；默认126像素容纳武将插画、体力、手牌、装备与判定信息。
@export_range(110.0, 220.0, 1.0) var panel_height: float = 126.0

## 当前角色稳定玩家 ID；由 configure 写入，未配置时为 -1。
var player_id: int = -1

## 当前角色是否是所选牌的合法候选目标；只控制青绿色提示。
var is_legal_target: bool = false

## 当前角色是否已加入目标顺序；选中状态优先使用金色提示。
var is_target_selected: bool = false

## 当前角色是否正在行动；行动状态使用左侧文本标记，不影响目标合法性。
var is_current_actor: bool = false

## 当前武将插画纹理；配置未填写或资源不存在时为 null。
var _artwork_texture: Texture2D

## 武将插画显示节点；固定占据角色卡左侧区域并忽略鼠标输入。
var _artwork_rect: TextureRect

## 武将插画缺失占位标签；有效插画加载后自动隐藏。
var _artwork_placeholder: Label


## 初始化角色卡尺寸、文本布局和指针反馈。
func _ready() -> void:
	custom_minimum_size = Vector2(panel_width, panel_height)
	focus_mode = Control.FOCUS_NONE
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 12)
	_create_artwork_slot()
	_refresh_artwork()
	_refresh_visual_state()


## 写入角色公开快照与已经格式化的状态文本；组件不持有可修改的 PlayerState 引用。
func configure(id: int, formatted_text: String, alive: bool, current_actor: bool, character_definition: Dictionary = {}) -> void:
	player_id = id
	is_current_actor = current_actor
	text = ("◆ 行动中\n" if is_current_actor else "") + formatted_text
	disabled = not alive
	_artwork_texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	_refresh_artwork()
	_refresh_visual_state()


## 更新合法与选中状态；已选目标始终优先显示金色边框。
func set_target_state(legal_target: bool, selected_target: bool) -> void:
	is_legal_target = legal_target
	is_target_selected = selected_target
	_refresh_visual_state()


## 仅接受战斗卡牌组件提供的拖放字典；死亡角色和非法目标不会接收。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return not disabled and is_legal_target and data is Dictionary and str((data as Dictionary).get("drag_type", "")) == "battle_card"


## 将拖放转换为桌面层信号；组件不直接改变选择集合或提交动作。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# 卡牌 UID；来源于 CardView 的稳定拖放数据。
	var dropped_card_uid: int = int((data as Dictionary).get("card_uid", -1))
	if dropped_card_uid >= 0:
		card_dropped.emit(dropped_card_uid, player_id)


## 根据默认、合法、选中与禁用状态刷新角色卡样式。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	# 角色卡背景；当前行动者略微提亮，帮助玩家定位回合归属。
	var background_color: Color = Color("3b332d") if not is_current_actor else Color("4a3d2f")
	# 角色卡边框；选中金色优先，其次合法青绿，最后使用统一暗金边框。
	var border_color: Color = BattleUIStyle.GOLD_BORDER_COLOR
	# 角色卡描边宽度；合法或选中时使用3像素，普通状态使用1像素。
	var border_width: int = 1
	if is_target_selected:
		border_color = BattleUIStyle.ACCENT_COLOR
		border_width = 3
	elif is_legal_target:
		border_color = BattleUIStyle.LEGAL_TARGET_COLOR
		border_width = 3
	add_theme_color_override("font_color", Color("f3e7d0"))
	add_theme_color_override("font_disabled_color", Color("8c8175"))
	add_theme_stylebox_override("normal", _make_player_style(background_color, border_color, border_width))
	add_theme_stylebox_override("hover", _make_player_style(background_color.lightened(0.08), border_color.lightened(0.12), maxi(border_width, 2)))
	add_theme_stylebox_override("pressed", _make_player_style(background_color.darkened(0.06), BattleUIStyle.ACCENT_COLOR, 3))
	add_theme_stylebox_override("disabled", _make_player_style(Color("292724"), Color("544f49"), 1))


## 创建角色卡左侧插画槽；占位层与纹理层不拦截点击或卡牌拖放。
func _create_artwork_slot() -> void:
	_artwork_rect = TextureRect.new()
	_artwork_rect.position = Vector2(8.0, 8.0)
	_artwork_rect.size = Vector2(66.0, panel_height - 16.0)
	_artwork_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_artwork_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_artwork_rect)
	_artwork_placeholder = Label.new()
	_artwork_placeholder.position = Vector2(8.0, 8.0)
	_artwork_placeholder.size = Vector2(66.0, panel_height - 16.0)
	_artwork_placeholder.text = "◇\n武将\n插画"
	_artwork_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artwork_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_artwork_placeholder.add_theme_font_size_override("font_size", 11)
	_artwork_placeholder.add_theme_color_override("font_color", Color("a8977f"))
	_artwork_placeholder.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(Color("75664d44"), Color("77664e"), 1, 6))
	_artwork_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_artwork_placeholder)


## 刷新武将插画与占位可见性；configure 和 _ready 均可安全调用。
func _refresh_artwork() -> void:
	if not is_node_ready() or _artwork_rect == null:
		return
	_artwork_rect.texture = _artwork_texture
	_artwork_rect.visible = _artwork_texture != null
	_artwork_placeholder.visible = _artwork_texture == null


## 创建为左侧插画预留内容边距的角色卡样式，避免状态文字覆盖武将图像。
func _make_player_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	# 角色卡样式；插画区宽66像素，加上左右间距后文字从84像素处开始。
	var style: StyleBoxFlat = BattleUIStyle.make_button(background_color, border_color, border_width, 10)
	style.content_margin_left = 84.0
	return style
