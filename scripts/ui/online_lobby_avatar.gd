class_name OnlineLobbyAvatar
extends Control

## 联机大厅单个玩家或空位置的表现组件。玩家只显示名称与联机形象插画，不复用局内武将牌场景或规则覆盖层。

## 本地玩家点击空位置时发出的换位请求；参数为大厅0起始位置索引。
signal empty_slot_pressed(seat_index: int)

## 房主点击悬停踢出按钮时发出的成员移除请求；参数为房主权威 ENet peer ID。
signal kick_requested(peer_id: int)

## 联机形象插画尺寸；默认与正式武将牌148.35×197.8像素一致，运行时通常无需修改。
@export var avatar_size: Vector2 = Vector2(148.35, 197.8)

## 玩家名称区域高度；默认26像素并始终位于插画上方，不覆盖插画内容。
@export_range(20.0, 48.0, 1.0) var name_height: float = 26.0

## 玩家名称与插画之间的垂直间距；默认4像素保持两者分离且不浪费大厅纵向空间。
@export_range(0.0, 16.0, 1.0) var name_gap: float = 4.0

## 踢出按钮左右内缩；默认34像素使管理入口比旧版更紧凑，运行时通常无需修改。
@export_range(0.0, 72.0, 1.0) var kick_button_horizontal_inset: float = 34.0

## 踢出按钮高度；默认31像素，缩小后仍保留鼠标与触屏可点击的最小操作区域。
@export_range(24.0, 48.0, 1.0) var kick_button_height: float = 31.0

## 踢出按钮距插画底边的间距；默认10像素让深红按钮位于边框内部而不压住圆角描边。
@export_range(0.0, 24.0, 1.0) var kick_button_bottom_inset: float = 10.0

## 踢出按钮相对主题危险色的加深比例；默认0.32使管理操作保持明显但不过度抢占插画视觉。
@export_range(0.0, 0.8, 0.01) var kick_button_darken_amount: float = 0.32

## 踢出按钮文字大小；默认13像素与31像素紧凑高度匹配，运行时通常无需修改。
@export_range(10, 18, 1) var kick_button_font_size: int = 13

## 踢出按钮上下内容边距；默认2像素避免通用操作按钮边距把紧凑高度撑大。
@export_range(0.0, 8.0, 1.0) var kick_button_vertical_content_margin: float = 2.0

## 玩家名称标签；始终位于联机形象上方，空位置显示对应位置编号。
@onready var _name_label: Label = %OnlineLobbyAvatarName

## 联机形象插画节点；只显示武将元数据中的插画纹理，不绘制牌框、势力、体力或技能 UI。
@onready var _artwork_rect: TextureRect = %OnlineLobbyAvatarArtwork

## 联机形象边框节点；占用位置使用与空位相同的圆角边框包裹插画，节点忽略鼠标以保持管理按钮悬停稳定。
@onready var _avatar_frame: Panel = %OnlineLobbyAvatarFrame

## 空位置按钮；覆盖与武将牌一致的插画区域，点击后请求本地玩家换位。
@onready var _empty_slot_button: Button = %OnlineLobbyEmptySlotButton

## 房主踢出按钮；仅房主悬停远端玩家形象时显示，房主本人和空位置始终隐藏。
@onready var _kick_button: Button = %OnlineLobbyKickButton

## 当前大厅位置索引；由 configure 写入，默认-1表示尚未绑定有效位置。
var _seat_index: int = -1

## 当前玩家网络 peer ID；空位置为0，房主为1，远端玩家大于1。
var _peer_id: int = 0

## 当前位置是否有真人玩家；决定插画、空位按钮与悬停踢出逻辑。
var _occupied: bool = false

## 当前本机是否拥有房主管理权限；只控制踢出按钮，不改变成员数据。
var _local_is_host: bool = false

## 当前位置是否属于本地玩家；本地玩家不能踢出自己，名称仍显示公共玩家名。
var _is_local_member: bool = false

## 鼠标是否停留在整个形象组件范围内；主题刷新时据此恢复踢出按钮可见性。
var _hovered: bool = false

## 鼠标是否停留在踢出按钮范围内；父组件因子控件命中而收到离开事件时，该状态会保持管理按钮可见。
var _kick_button_hovered: bool = false


## 初始化输入信号并应用固定几何；玩家与空位置共用同一组件尺寸。
func _ready() -> void:
	custom_minimum_size = Vector2(avatar_size.x, name_height + name_gap + avatar_size.y)
	size = custom_minimum_size
	_name_label.position = Vector2.ZERO
	_name_label.size = Vector2(avatar_size.x, name_height)
	_artwork_rect.position = Vector2(0.0, name_height + name_gap)
	_artwork_rect.size = avatar_size
	_avatar_frame.position = _artwork_rect.position
	_avatar_frame.size = avatar_size
	_empty_slot_button.position = _artwork_rect.position
	_empty_slot_button.size = avatar_size
	# 当前踢出按钮宽度；内缩过大时保留24像素宽度，避免检查器配置导致按钮反向或不可点击。
	var kick_button_width: float = maxf(avatar_size.x - kick_button_horizontal_inset * 2.0, 24.0)
	_kick_button.position = _artwork_rect.position + Vector2(kick_button_horizontal_inset, avatar_size.y - kick_button_bottom_inset - kick_button_height)
	_kick_button.custom_minimum_size = Vector2(kick_button_width, kick_button_height)
	_kick_button.size = Vector2(kick_button_width, kick_button_height)
	_empty_slot_button.pressed.connect(_on_empty_slot_pressed)
	_kick_button.pressed.connect(_on_kick_pressed)
	_kick_button.mouse_entered.connect(_on_kick_button_mouse_entered)
	_kick_button.mouse_exited.connect(_on_kick_button_mouse_exited)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh_ui_style()


## 绑定一名大厅成员或空位置；成员字典只读取名称、形象 ID、peer ID 与房主标记。
func configure(seat_index: int, member: Dictionary, local_is_host: bool, local_peer_id: int) -> void:
	_seat_index = seat_index
	_local_is_host = local_is_host
	_occupied = not member.is_empty()
	_peer_id = int(member.get("peer_id", 0)) if _occupied else 0
	_is_local_member = _occupied and _peer_id == local_peer_id
	_hovered = false
	_kick_button_hovered = false
	if not _occupied:
		_name_label.text = "位置%d" % (seat_index + 1)
		_artwork_rect.texture = null
		_artwork_rect.visible = false
		_avatar_frame.visible = false
		_empty_slot_button.visible = true
		_kick_button.visible = false
		refresh_ui_style()
		return
	# 当前成员显示名；房主标记附加在插画上方的名称区域，不绘制到插画内部。
	var display_name: String = str(member.get("display_name", "玩家"))
	_name_label.text = "%s%s" % [display_name, "（房主）" if bool(member.get("is_host", false)) else ""]
	# 当前联机形象定义；只通过稳定武将 ID 查找最新插画元数据。
	var character_definition: Dictionary = GameDatabase.get_character(str(member.get("avatar_character_id", "")))
	_artwork_rect.texture = ArtworkLoader.load_from_definition(character_definition, ArtworkLoader.CHARACTER_ART_FIELD)
	_artwork_rect.visible = true
	_avatar_frame.visible = true
	_empty_slot_button.visible = false
	_update_kick_visibility()
	refresh_ui_style()


## 按当前 UI 风格重绘名称、空位与踢出按钮；玩家插画纹理和大厅座位保持不变。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary") if _occupied else BattleUIStyle.get_color("text_muted"))
	_name_label.add_theme_color_override("font_outline_color", BattleUIStyle.get_color("outer_background"))
	_empty_slot_button.add_theme_stylebox_override("normal", BattleUIStyle.make_panel(Color(BattleUIStyle.get_color("panel"), 0.36), Color(BattleUIStyle.get_color("border"), 0.55), 1, 6))
	_empty_slot_button.add_theme_stylebox_override("hover", BattleUIStyle.make_panel(Color(BattleUIStyle.get_color("action_button"), 0.58), BattleUIStyle.get_color("accent"), 2, 6))
	_empty_slot_button.add_theme_stylebox_override("pressed", BattleUIStyle.make_panel(Color(BattleUIStyle.get_color("action_button"), 0.78), BattleUIStyle.get_color("accent"), 2, 6))
	_empty_slot_button.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_empty_slot_button.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	# 当前玩家形象纯边框；通用面板默认阴影会覆盖插画边缘，因此这里明确关闭填充与阴影，只保留空位同规格的圆角描边。
	var avatar_frame_style: StyleBoxFlat = BattleUIStyle.make_panel(Color.TRANSPARENT, Color(BattleUIStyle.get_color("border"), 0.55), 1, 6)
	avatar_frame_style.draw_center = false
	avatar_frame_style.shadow_size = 0
	_avatar_frame.add_theme_stylebox_override("panel", avatar_frame_style)
	# 当前踢出按钮背景；在主题危险色基础上加深，避免与普通错误提示和高亮操作混淆。
	var kick_button_color: Color = BattleUIStyle.get_color("danger").darkened(kick_button_darken_amount)
	BattleUIStyle.apply_interaction_button(_kick_button, kick_button_color, BattleUIStyle.get_color("danger"), true)
	_kick_button.add_theme_font_size_override("font_size", kick_button_font_size)
	for state_name: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		# 当前踢出按钮状态样式；压缩上下边距后，所有交互状态都保持同一31像素固定高度。
		var kick_button_state_style: StyleBoxFlat = _kick_button.get_theme_stylebox(state_name) as StyleBoxFlat
		if kick_button_state_style != null:
			kick_button_state_style.content_margin_top = kick_button_vertical_content_margin
			kick_button_state_style.content_margin_bottom = kick_button_vertical_content_margin
	_update_kick_visibility()


## 返回组件当前绑定的大厅位置索引；布局测试与父组件可据此验证人数排版顺序。
func get_seat_index() -> int:
	return _seat_index


## 返回插画实际显示矩形；大厅布局测试用于确认玩家形象尺寸与武将牌一致。
func get_avatar_rect() -> Rect2:
	return Rect2(_artwork_rect.position, _artwork_rect.size)


## 空位置点击只发出稳定位置索引；房主权威网关决定该位置是否仍为空。
func _on_empty_slot_pressed() -> void:
	if not _occupied and _seat_index >= 0:
		empty_slot_pressed.emit(_seat_index)


## 踢出按钮点击只发出当前成员 peer ID；空位置、房主本人和本地成员不会触发。
func _on_kick_pressed() -> void:
	if _occupied and _local_is_host and not _is_local_member and _peer_id > NetworkGateway.SERVER_PEER_ID:
		kick_requested.emit(_peer_id)


## 鼠标进入玩家形象时显示房主管理按钮；普通玩家与空位置保持原表现。
func _on_mouse_entered() -> void:
	_hovered = true
	_update_kick_visibility()


## 鼠标离开组件时隐藏房主管理按钮，避免按钮在其他玩家形象上残留。
func _on_mouse_exited() -> void:
	_hovered = false
	# 延迟到当前输入事件结束；进入踢出按钮时父组件可能先收到离开事件，子按钮会在同一事件周期写入自身悬停状态。
	call_deferred("_update_kick_visibility")


## 鼠标进入踢出按钮时保留管理入口；按钮属于形象组件可视范围，不能被父组件离开事件错误隐藏。
func _on_kick_button_mouse_entered() -> void:
	_kick_button_hovered = true
	_update_kick_visibility()


## 鼠标离开踢出按钮时延迟复核父组件悬停状态；回到插画区域时父组件会在同一输入周期重新进入。
func _on_kick_button_mouse_exited() -> void:
	_kick_button_hovered = false
	call_deferred("_update_kick_visibility")


## 根据权限、占用状态与悬停状态统一决定踢出按钮可见性。
func _update_kick_visibility() -> void:
	if not is_node_ready():
		return
	_kick_button.visible = _occupied and _local_is_host and not _is_local_member and _peer_id > NetworkGateway.SERVER_PEER_ID and (_hovered or _kick_button_hovered)
