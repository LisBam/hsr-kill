class_name OnlineSettingsPanel
extends Control

## 联机资料设置组件。该组件只编辑跨大厅复用的玩家名称与武将形象，不创建网络连接或修改对局状态。

## 玩家保存资料或取消返回时发出的关闭请求；主菜单据此恢复底层焦点，不依赖组件内部节点路径。
signal close_requested()

## 正式武将牌场景；联机形象选择与选将、局内角色牌复用同一插画和主题渲染组件。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 每行显示的武将牌数量；默认5张可在1280×720逻辑视口内保留舒适间距，运行时一般无需动态修改。
@export_range(1, 8, 1) var avatar_columns: int = 5

## 联机形象武将牌的显示比例；默认0.72可同时展示两行候选，运行时只影响资料面板布局。
@export_range(0.5, 1.0, 0.01) var avatar_card_scale: float = 0.72

## 同行武将牌之间的水平间距；默认18像素用于清晰区分相邻候选，运行时只影响资料面板布局。
@export_range(0.0, 48.0, 1.0) var avatar_horizontal_gap: float = 18.0

## 相邻武将牌行之间的垂直间距；默认16像素避免选中描边与下一行牌面相交，运行时只影响资料面板布局。
@export_range(0.0, 48.0, 1.0) var avatar_vertical_gap: float = 16.0

## 面板全屏遮罩；打开资料设置时阻断主菜单底层鼠标输入，并使用当前主题 shade 语义色。
@onready var _backdrop: ColorRect = %OnlineSettingsBackdrop

## 联机资料中央主面板；名称编辑、武将形象列表和保存操作共同位于该容器。
@onready var _panel: PanelContainer = %OnlineSettingsFrame

## 面板标题；固定显示“联机设置”，只承担界面说明。
@onready var _title_label: Label = %OnlineSettingsTitle

## 面板提示；说明联机形象当前只保存选择，未来大厅实现后再消费该配置。
@onready var _hint_label: Label = %OnlineSettingsHint

## 玩家名称输入框；最大长度与局域网协议统一为20个 Unicode 字符，保存前仍会经过全局标准化。
@onready var _player_name_input: LineEdit = %OnlinePlayerNameInput

## 武将形象选区滚动容器；武将数量超过当前可视区域时允许纵向浏览全部候选。
@onready var _avatar_scroll: ScrollContainer = %OnlineAvatarScroll

## 动态武将牌承载区；脚本按稳定排序写入正式 PlayerTargetView 节点，不保存规则对象引用。
@onready var _avatar_content: Control = %OnlineAvatarContent

## 当前选择文字；只显示所选武将的本地化名称，不暴露稳定英文 ID。
@onready var _selected_avatar_label: Label = %OnlineSelectedAvatarLabel

## 保存并返回按钮；提交标准化名称与稳定武将 ID 后请求主菜单关闭模态层。
@onready var _save_button: Button = %OnlineSettingsSaveButton

## 取消返回按钮；放弃本次未保存编辑并请求主菜单关闭模态层。
@onready var _cancel_button: Button = %OnlineSettingsCancelButton

## 当前临时选择的稳定武将 ID；点击保存前不写入 GameSettings，取消时直接丢弃。
var _selected_character_id: String = ""

## 武将 ID 到正式牌面视图的映射；只用于同步选中描边与主题刷新，不参与网络或规则状态。
var _avatar_views: Dictionary = {}


## 初始化资料面板信号与主题监听；组件默认隐藏，只有主菜单顶部入口显式打开后才接收输入。
func _ready() -> void:
	visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_name_input.max_length = GameSettings.MAX_ONLINE_PLAYER_NAME_LENGTH
	_player_name_input.select_all_on_focus = false
	_save_button.pressed.connect(_save_and_close)
	_cancel_button.pressed.connect(_cancel_and_close)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	refresh_ui_style()


## 打开联机资料设置；每次从全局设置重新载入名称与形象，保证取消后再次进入不会保留未提交内容。
func open_panel() -> void:
	visible = true
	move_to_front()
	_player_name_input.text = GameSettings.online_player_name
	_player_name_input.caret_column = _player_name_input.text.length()
	_rebuild_avatar_options()
	call_deferred("_focus_primary_control")


## 按当前活动主题刷新面板、文本框、按钮与动态武将牌；不改变任何临时编辑或已保存资料。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_backdrop.color = BattleUIStyle.get_color("shade")
	_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	(%OnlinePlayerNameLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%OnlineAvatarLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_selected_avatar_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%OnlineSettingsDivider as ColorRect).color = Color(BattleUIStyle.get_color("border"), 0.62)
	_apply_line_edit_style(_player_name_input)
	BattleUIStyle.apply_interaction_button(_save_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_cancel_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	for avatar_view_variant: Variant in _avatar_views.values():
		# 当前武将形象牌面；只刷新主题颜色，临时选择与布局保持不变。
		var avatar_view: PlayerTargetView = avatar_view_variant as PlayerTargetView
		if avatar_view != null and is_instance_valid(avatar_view):
			avatar_view.refresh_ui_style()


## 从数据库全部现有武将重建形象候选；显示顺序按中文名称稳定排序，新增武将无需修改本组件。
func _rebuild_avatar_options() -> void:
	_clear_avatar_options()
	# 当前已登记武将 ID；复制后按显示名排序，避免直接依赖数据库字典遍历顺序。
	var character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		character_ids.append(str(character_id_variant))
	character_ids.sort_custom(_sort_character_ids_by_name)
	if character_ids.is_empty():
		_selected_character_id = ""
		_selected_avatar_label.text = "当前形象：暂无可用武将牌"
		_save_button.disabled = true
		_avatar_content.custom_minimum_size = Vector2(_avatar_scroll.size.x, 1.0)
		return
	# 已保存形象；配置缺失或对应武将被移除时回退到排序后的第一张武将牌。
	var saved_character_id: String = GameSettings.online_avatar_character_id
	_selected_character_id = saved_character_id if character_ids.has(saved_character_id) else character_ids[0]
	_save_button.disabled = false
	# 第一张武将牌的缩放尺寸；全部候选复用同一正式场景规格，因此可作为统一布局基准。
	var scaled_card_size: Vector2 = Vector2.ZERO
	for character_index: int in range(character_ids.size()):
		# 当前稳定武将 ID；点击与保存只提交该值，牌面文本使用数据库本地化名称。
		var character_id: String = character_ids[character_index]
		# 当前武将定义；用于牌面体力、势力、名称和插画展示。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		# 当前势力定义；只提供正式牌面的圆徽名称与主题颜色。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
		# 当前候选占位容器；Control 负责滚动内容尺寸，武将牌根节点仍保持可复用的 Node2D 类型。
		var avatar_slot: Control = Control.new()
		avatar_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar_content.add_child(avatar_slot)
		# 当前正式武将牌；组件只渲染静态资料并发出点击，不创建玩家或对局状态。
		var avatar_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
		avatar_slot.add_child(avatar_view)
		avatar_view.scale = Vector2.ONE * avatar_card_scale
		# 联机形象预览快照；只包含牌面渲染字段，不进入 GameState、网络快照或选将流程。
		var avatar_snapshot: Dictionary = {
			"player_id":character_index,
			"display_name":"联机形象",
			"character_id":character_id,
			"character_revealed":true,
			"identity":"hidden",
			"hp":int(character_definition.get("max_hp", 4)),
			"max_hp":int(character_definition.get("max_hp", 4)),
			"alive":true,
			"chained":false,
			"hand_count":0,
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage_count":0,
		}
		avatar_view.configure_snapshot(avatar_snapshot, character_definition, false, faction_definition)
		avatar_view.pressed.connect(_select_avatar.bind(character_id))
		_avatar_views[character_id] = avatar_view
		if scaled_card_size == Vector2.ZERO:
			scaled_card_size = avatar_view.card_size * avatar_card_scale
		avatar_slot.size = scaled_card_size
		avatar_slot.position = _resolve_avatar_slot_position(character_index, scaled_card_size)
	# 实际行数；向上取整保证最后一行不完整时仍为全部候选保留滚动高度。
	var row_count: int = ceili(float(character_ids.size()) / float(avatar_columns))
	# 实际显示列数；武将不足一行时按真实数量收紧内容并保持整体居中。
	var visible_column_count: int = mini(character_ids.size(), avatar_columns)
	# 全部候选占用宽度；不包含额外边距，滚动容器会按内容实际尺寸处理裁剪。
	var content_width: float = scaled_card_size.x * float(visible_column_count) + avatar_horizontal_gap * float(maxi(visible_column_count - 1, 0))
	# 全部候选占用高度；每行牌高固定，行间只加入统一垂直间距。
	var content_height: float = scaled_card_size.y * float(row_count) + avatar_vertical_gap * float(maxi(row_count - 1, 0))
	_avatar_content.custom_minimum_size = Vector2(content_width, content_height)
	_update_avatar_selection()


## 返回指定候选在滚动内容中的左上坐标；列数和间距均来自可视化配置参数。
func _resolve_avatar_slot_position(character_index: int, scaled_card_size: Vector2) -> Vector2:
	# 当前候选列索引；从0开始并在达到每行上限后回到首列。
	var column_index: int = character_index % avatar_columns
	# 当前候选行索引；整数除法保证同一行共享相同纵坐标。
	var row_index: int = character_index / avatar_columns
	return Vector2(float(column_index) * (scaled_card_size.x + avatar_horizontal_gap), float(row_index) * (scaled_card_size.y + avatar_vertical_gap))


## 按本地化武将名称排序稳定 ID；名称相同的异常配置再按稳定 ID 排序，保证跨平台显示顺序一致。
func _sort_character_ids_by_name(first_character_id: String, second_character_id: String) -> bool:
	# 第一名武将的本地化名称；所有玩家可见排序都不直接显示稳定英文 ID。
	var first_name: String = GameDatabase.resolve_character_name(first_character_id)
	# 第二名武将的本地化名称；仅用于当前排序比较。
	var second_name: String = GameDatabase.resolve_character_name(second_character_id)
	return first_character_id < second_character_id if first_name == second_name else first_name < second_name


## 更新临时联机形象选择；只改变本面板金色描边与文字，保存前不影响全局配置。
func _select_avatar(character_id: String) -> void:
	if not _avatar_views.has(character_id):
		return
	_selected_character_id = character_id
	_update_avatar_selection()


## 将当前临时形象同步到所有武将牌选中状态，并更新玩家可见的中文名称说明。
func _update_avatar_selection() -> void:
	for character_id_variant: Variant in _avatar_views.keys():
		# 当前稳定武将 ID；只用于比较选择，不显示给玩家。
		var character_id: String = str(character_id_variant)
		# 当前武将形象视图；选中的唯一牌面使用主题强调色描边。
		var avatar_view: PlayerTargetView = _avatar_views[character_id] as PlayerTargetView
		avatar_view.set_target_state(false, character_id == _selected_character_id)
	_selected_avatar_label.text = "当前形象：%s" % GameDatabase.resolve_character_name(_selected_character_id)


## 保存标准化名称与稳定武将形象 ID；资料更新完成后由主菜单统一关闭模态并恢复焦点。
func _save_and_close() -> void:
	GameSettings.set_online_player_name(_player_name_input.text)
	GameSettings.set_online_avatar_character_id(_selected_character_id)
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	close_requested.emit()


## 放弃本次临时编辑并返回主菜单；全局名称与形象配置保持打开面板前的值。
func _cancel_and_close() -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	close_requested.emit()


## 清理全部动态武将形象牌；重新打开或数据库刷新时不会保留旧信号、牌面或选择描边。
func _clear_avatar_options() -> void:
	_avatar_views.clear()
	for child: Node in _avatar_content.get_children():
		_avatar_content.remove_child(child)
		child.queue_free()


## 为玩家名称输入框应用当前主题的常态与焦点边框；文本编辑行为仍由 Godot LineEdit 管理。
func _apply_line_edit_style(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 把初始焦点放到当前平台的安全控件；Android等待玩家主动点击名称框，避免打开面板时自动弹出输入法。
func _focus_primary_control() -> void:
	if not visible:
		return
	if OS.get_name() == "Android":
		MobileKeyboardGuard.focus_non_text(_save_button)
		return
	_player_name_input.grab_focus()


## 响应全局 UI 风格切换；只重绘当前面板与已有武将牌，不重置未保存编辑。
func _on_ui_style_changed(_style_id: String) -> void:
	refresh_ui_style()


## 联机设置打开时允许 Esc 执行与取消按钮相同的安全返回行为。
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel_and_close()
		get_viewport().set_input_as_handled()
