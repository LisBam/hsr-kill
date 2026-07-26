class_name OnlineLobbyAvatar
extends Control

## 联机大厅单个玩家或空位置的表现组件。占用位置沿用空位同款武将框作为底框，联机形象插画内嵌框中，不复用局内武将牌场景或规则覆盖层。

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

## 插画在武将框内的四周内缩；默认7像素露出空位同款底色与描边，让玩家形象嵌入框体而不是覆盖整框。
@export_range(0.0, 24.0, 0.5) var artwork_inset: float = 7.0

## 插画自身圆角像素；默认4像素小于武将框6像素圆角，保证内缩后的插画四角不越出框体弧线。
@export_range(0.0, 12.0, 0.5) var artwork_corner_radius: float = 4.0

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

## 身份徽记尺寸；默认48×22像素紧贴武将框右上角，运行时通常无需修改。
@export var identity_badge_size: Vector2 = Vector2(48.0, 22.0)

## 身份徽记距武将框右上角的内缩距离；默认4像素让徽记完整位于框体描边内部。
@export_range(0.0, 16.0, 1.0) var identity_badge_inset: float = 4.0

## 身份到玩家可见文案的固定映射；与规则层身份 ID 一一对应，未知身份直接显示原始 ID 便于排查。
const IDENTITY_DISPLAY_NAMES: Dictionary = {
	"leader":"领袖",
	"loyalist":"忠臣",
	"rebel":"反贼",
	"renegade":"内奸",
	"landlord":"地主",
	"peasant":"农民",
	"blue":"蓝方",
	"red":"红方",
}

## 玩家名称标签；始终位于联机形象上方，空位置显示对应位置编号。
@onready var _name_label: Label = %OnlineLobbyAvatarName

## 联机形象插画节点；只显示武将元数据中的插画纹理，不绘制牌框、势力、体力或技能 UI。
@onready var _artwork_rect: TextureRect = %OnlineLobbyAvatarArtwork

## 联机形象武将框节点；占用位置沿用与空位完全相同的圆角面板作为底框并包裹内嵌插画，节点忽略鼠标以保持管理按钮悬停稳定。
@onready var _avatar_frame: Panel = %OnlineLobbyAvatarFrame

## 空位置按钮；覆盖与武将牌一致的插画区域，点击后请求本地玩家换位。
@onready var _empty_slot_button: Button = %OnlineLobbyEmptySlotButton

## 房主踢出按钮；仅房主悬停远端玩家形象时显示，房主本人和空位置始终隐藏。
@onready var _kick_button: Button = %OnlineLobbyKickButton

## 位置身份徽记；自选身份开启时显示该位置绑定的身份，空位与玩家形象右上角共用同一徽记。
@onready var _identity_badge_label: Label = %OnlineLobbyIdentityBadge

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

## 当前位置绑定的身份 ID；空字符串表示未开启自选身份或该模式无位置身份，徽记隐藏。
var _identity_id: String = ""


## 初始化输入信号并应用固定几何；玩家与空位置共用同一组件尺寸。
func _ready() -> void:
	custom_minimum_size = Vector2(avatar_size.x, name_height + name_gap + avatar_size.y)
	size = custom_minimum_size
	_name_label.position = Vector2.ZERO
	_name_label.size = Vector2(avatar_size.x, name_height)
	# 武将框原点；空位按钮、玩家底框与内嵌插画都以该矩形为基准，保证占用与空位共用同一框体。
	var frame_position: Vector2 = Vector2(0.0, name_height + name_gap)
	_avatar_frame.position = frame_position
	_avatar_frame.size = avatar_size
	_empty_slot_button.position = frame_position
	_empty_slot_button.size = avatar_size
	# 插画实际尺寸；在武将框内四周内缩，让空位同款底色与描边完整露出并包裹玩家形象。
	var artwork_size: Vector2 = Vector2(maxf(avatar_size.x - artwork_inset * 2.0, 1.0), maxf(avatar_size.y - artwork_inset * 2.0, 1.0))
	_artwork_rect.position = frame_position + Vector2(artwork_inset, artwork_inset)
	_artwork_rect.size = artwork_size
	# 插画圆角遮罩材质；场景子资源在全部座位实例间共享，写入本实例内缩后的宽高比与圆角前必须先复制。
	var mask_material: ShaderMaterial = _artwork_rect.material as ShaderMaterial
	if mask_material != null:
		mask_material = mask_material.duplicate() as ShaderMaterial
		mask_material.set_shader_parameter("artwork_aspect_ratio", artwork_size.x / artwork_size.y)
		mask_material.set_shader_parameter("corner_radius", artwork_corner_radius / artwork_size.y)
		_artwork_rect.material = mask_material
	# 身份徽记位置；紧贴武将框右上角并按内缩距离嵌入框体，位于插画之上、踢出按钮之下的绘制层。
	_identity_badge_label.size = identity_badge_size
	_identity_badge_label.position = frame_position + Vector2(avatar_size.x - identity_badge_size.x - identity_badge_inset, identity_badge_inset)
	# 当前踢出按钮宽度；内缩过大时保留24像素宽度，避免检查器配置导致按钮反向或不可点击。
	var kick_button_width: float = maxf(avatar_size.x - kick_button_horizontal_inset * 2.0, 24.0)
	_kick_button.position = frame_position + Vector2(kick_button_horizontal_inset, avatar_size.y - kick_button_bottom_inset - kick_button_height)
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
## identity_id 为该位置在自选身份下绑定的身份；空字符串表示不显示身份徽记。
func configure(seat_index: int, member: Dictionary, local_is_host: bool, local_peer_id: int, identity_id: String = "") -> void:
	_seat_index = seat_index
	_local_is_host = local_is_host
	_occupied = not member.is_empty()
	_identity_id = identity_id
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
	_empty_slot_button.add_theme_stylebox_override("normal", _make_slot_frame_style())
	_empty_slot_button.add_theme_stylebox_override("hover", BattleUIStyle.make_panel(Color(BattleUIStyle.get_color("action_button"), 0.58), BattleUIStyle.get_color("accent"), 2, 6))
	_empty_slot_button.add_theme_stylebox_override("pressed", BattleUIStyle.make_panel(Color(BattleUIStyle.get_color("action_button"), 0.78), BattleUIStyle.get_color("accent"), 2, 6))
	_empty_slot_button.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_empty_slot_button.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	# 当前玩家形象武将框；直接沿用空位常态的同一底色、描边与阴影规格，插画节点绘制在框体之上并按内缩距离嵌入。
	_avatar_frame.add_theme_stylebox_override("panel", _make_slot_frame_style())
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
	_refresh_identity_badge()
	_update_kick_visibility()


## 返回组件当前绑定的大厅位置索引；布局测试与父组件可据此验证人数排版顺序。
func get_seat_index() -> int:
	return _seat_index


## 返回当前位置绑定的身份 ID；空字符串表示徽记隐藏，回归测试据此验证自选身份布局。
func get_identity_id() -> String:
	return _identity_id


## 按当前身份 ID 刷新右上角身份徽记；文案取固定映射，颜色取主题身份语义色，空身份直接隐藏。
func _refresh_identity_badge() -> void:
	if not is_node_ready() or _identity_badge_label == null:
		return
	if _identity_id.is_empty():
		_identity_badge_label.visible = false
		return
	_identity_badge_label.text = str(IDENTITY_DISPLAY_NAMES.get(_identity_id, _identity_id))
	# 当前身份语义色；未登记身份回退次级文字色，保证徽记在任何主题下可读。
	var identity_color: Color = BattleUIStyle.get_color("identity_%s" % _identity_id, BattleUIStyle.get_color("text_secondary"))
	_identity_badge_label.add_theme_color_override("font_color", identity_color)
	# 徽记底色；沿用金属面板语义并保持高不透明度，让身份文字在插画上保持稳定对比。
	var badge_background: Color = BattleUIStyle.get_color("metal_panel")
	badge_background.a = 0.92
	# 徽记样式；身份色细描边、紧凑零内边距与小圆角，避免遮挡插画主体。
	var badge_style: StyleBoxFlat = BattleUIStyle.make_panel(badge_background, identity_color, 1, 4)
	badge_style.content_margin_left = 0.0
	badge_style.content_margin_top = 0.0
	badge_style.content_margin_right = 0.0
	badge_style.content_margin_bottom = 0.0
	badge_style.shadow_size = 0
	badge_style.shadow_offset = Vector2.ZERO
	_identity_badge_label.add_theme_stylebox_override("normal", badge_style)
	_identity_badge_label.visible = true


## 返回插画实际显示矩形；大厅布局测试据此确认插画按内缩距离完整嵌入武将框内部。
func get_avatar_rect() -> Rect2:
	return Rect2(_artwork_rect.position, _artwork_rect.size)


## 构造空位与玩家共用的武将框常态样式；占用位置的底框必须与空位按钮保持同一底色、描边与圆角规格。
func _make_slot_frame_style() -> StyleBoxFlat:
	return BattleUIStyle.make_panel(Color(BattleUIStyle.get_color("panel"), 0.36), Color(BattleUIStyle.get_color("border"), 0.55), 1, 6)


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
