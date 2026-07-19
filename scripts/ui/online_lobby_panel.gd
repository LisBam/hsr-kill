class_name OnlineLobbyPanel
extends Control

## 联机大厅界面组件。该组件只渲染公共房间快照并发出聊天、换位、踢人、设置、开始与离开意图。

## 本地玩家发送大厅聊天时发出的请求；正文已经过组件空值检查，网络层仍会统一裁剪长度。
signal chat_requested(message: String)

## 本地玩家点击空位置时发出的换位请求；参数为大厅0起始位置索引。
signal seat_change_requested(seat_index: int)

## 房主点击玩家悬停管理按钮时发出的踢出请求；参数为远端成员 ENet peer ID。
signal kick_requested(peer_id: int)

## 房主保存对局设置时发出的请求；参数依次为稳定模式 ID、总人数与房间密码。
signal settings_update_requested(game_mode_id: String, player_count: int, room_password: String)

## 房主点击开始游戏时发出的请求；对局人数与模式已经由权威房间设置保存。
signal start_match_requested()

## 任意玩家点击离开房间时发出的请求；实际 ENet 生命周期由牌桌协调器处理。
signal leave_requested()

## 单个大厅玩家形象场景；只显示玩家名与插画，不复用局内武将牌场景。
const ONLINE_LOBBY_AVATAR_SCENE: PackedScene = preload("res://scenes/components/online_lobby_avatar.tscn")

## 2至3人大厅固定绘制的位置数量；根据设计要求始终显示3个居中横向位置。
const MINIMUM_DISPLAY_SLOT_COUNT: int = 3

## 玩家形象组件总尺寸；宽度等于武将牌，227.8高度包含上方26像素名称与4像素间距。
const AVATAR_COMPONENT_SIZE: Vector2 = Vector2(148.35, 227.8)

## 同行大厅位置水平间距；默认44像素让四张插画仍可在中央区域完整排列。
@export_range(0.0, 96.0, 1.0) var horizontal_slot_gap: float = 44.0

## 两行大厅位置垂直间距；默认18像素使上下玩家名称与插画之间保持清晰分层。
@export_range(0.0, 64.0, 1.0) var vertical_slot_gap: float = 18.0

## 大厅全屏背景；读取当前主题桌面色，确保崩铁风格与暖木家园都具有完整底色。
@onready var _background: ColorRect = %OnlineLobbyBackground

## 大厅中央内容面；使用不接管子节点布局的 Panel，使玩家位置、聊天区与房间控制区保持各自矩形。
@onready var _surface: Panel = %OnlineLobbySurface

## 大厅标题；房主与客户端都显示当前模式、人数和密码状态摘要。
@onready var _title_label: Label = %OnlineLobbyTitle

## 房主地址提示；只在房主本地显示可分享 IPv4 与端口。
@onready var _address_label: Label = %OnlineLobbyAddress

## 玩家位置承载区；脚本根据对局人数动态生成空位置与真人形象组件。
@onready var _seat_area: Control = %OnlineLobbySeatArea

## 左下聊天主面板；历史与输入框共同使用当前主题样式。
@onready var _chat_panel: PanelContainer = %OnlineLobbyChatPanel

## 大厅公共聊天历史；所有玩家按房主权威序号显示相同消息顺序。
@onready var _chat_history: RichTextLabel = %OnlineLobbyChatHistory

## 聊天文本输入；回车与发送按钮均提交同一正文并在成功发出后清空。
@onready var _chat_input: LineEdit = %OnlineLobbyChatInput

## 聊天发送按钮；本地空文本时保持可点击但不会产生网络消息。
@onready var _chat_send_button: Button = %OnlineLobbyChatSendButton

## 右下控制主面板；承载房间摘要、设置按钮、开始按钮与离开按钮。
@onready var _control_panel: PanelContainer = %OnlineLobbyControlPanel

## 房间当前设置摘要；所有玩家只读显示模式、人数与密码开启状态。
@onready var _room_summary_label: Label = %OnlineLobbyRoomSummary

## 房主对局设置按钮；客户端隐藏，房主打开模式、人数和密码编辑区域。
@onready var _settings_button: Button = %OnlineLobbySettingsButton

## 房主开始游戏按钮；至少2名真人且当前设置有效时可用，客户端隐藏。
@onready var _start_button: Button = %OnlineLobbyStartButton

## 所有玩家可用的离开按钮；房主调用会关闭房间，客户端调用只退出自身会话。
@onready var _leave_button: Button = %OnlineLobbyLeaveButton

## 房间设置模态遮罩；只在房主打开设置时显示并阻断大厅底层输入。
@onready var _settings_backdrop: ColorRect = %OnlineLobbySettingsBackdrop

## 房间设置中央面板；当前提供游戏模式、对局人数与房间密码三项配置。
@onready var _settings_panel: PanelContainer = %OnlineLobbySettingsPanel

## 游戏模式下拉框；选项元数据保存稳定模式 ID，当前唯一实际模式为身份模式。
@onready var _game_mode_option: OptionButton = %OnlineLobbyGameModeOption

## 对局人数输入；范围2至10，最小值动态提升到当前真人数量。
@onready var _player_count_input: SpinBox = %OnlineLobbyPlayerCountInput

## 房间密码输入；最长32字符，空值表示取消密码并允许后续玩家直接加入。
@onready var _password_input: LineEdit = %OnlineLobbyPasswordInput

## 保存房间设置按钮；发出纯数据请求，成功与失败由牌桌协调器回传。
@onready var _settings_save_button: Button = %OnlineLobbySettingsSaveButton

## 取消房间设置按钮；丢弃本次编辑并返回大厅，不修改权威快照。
@onready var _settings_cancel_button: Button = %OnlineLobbySettingsCancelButton

## 当前大厅公共快照；仅保存可序列化副本，用于重绘位置、聊天与设置摘要。
var _snapshot: Dictionary = {}

## 当前本机是否为房主；控制踢出、对局设置和开始按钮权限。
var _local_is_host: bool = false

## 当前本机网络 peer ID；用于玩家形象组件禁止房主踢出自己并识别本地成员。
var _local_peer_id: int = 0

## 当前大厅玩家形象与空位置组件；每次快照整体重建，避免旧成员信号或悬停状态残留。
var _seat_views: Array[OnlineLobbyAvatar] = []

## 房主设置模态打开前的大厅控件焦点模式；关闭设置后原样恢复，避免键盘导航穿透到底层聊天与座位。
var _settings_background_focus_modes: Dictionary = {}


## 初始化大厅交互信号与游戏模式选项；组件默认隐藏，连接成功后由主菜单显式打开。
func _ready() -> void:
	visible = false
	_settings_backdrop.visible = false
	_settings_panel.visible = false
	_chat_input.max_length = NetworkGateway.MAX_LOBBY_CHAT_LENGTH
	_password_input.max_length = NetworkGateway.MAX_LOBBY_PASSWORD_LENGTH
	_chat_send_button.pressed.connect(_submit_chat_message)
	_chat_input.text_submitted.connect(_on_chat_text_submitted)
	_settings_button.pressed.connect(_open_settings)
	_start_button.pressed.connect(_request_start_match)
	_leave_button.pressed.connect(leave_requested.emit)
	_settings_save_button.pressed.connect(_save_settings)
	_settings_cancel_button.pressed.connect(_close_settings)
	_settings_backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	_seat_area.resized.connect(_on_seat_area_resized)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	_populate_game_mode_options()
	refresh_ui_style()


## 打开并绑定公共大厅快照；房主私有设置可额外包含明文密码供本机设置面板回填。
func bind_lobby(lobby_snapshot: Dictionary, host_addresses: Array[String] = [], host_port: int = 0) -> void:
	# 绑定前可见状态；只有首次进入大厅时主动设置主要焦点，聊天或座位快照刷新不得打断玩家输入。
	var was_visible: bool = visible
	_snapshot = lobby_snapshot.duplicate(true)
	_local_is_host = str(_snapshot.get("role", "")) == "host"
	_local_peer_id = int(_snapshot.get("local_peer_id", 0))
	visible = true
	move_to_front()
	_address_label.visible = _local_is_host
	_address_label.text = "房主地址：%s  ｜  端口：%d" % [" / ".join(host_addresses), host_port] if _local_is_host else ""
	_render_room_summary()
	_render_seats()
	_render_chat_history()
	_refresh_room_controls()
	if not was_visible:
		call_deferred("_focus_primary_control")


## 对局正式开始后隐藏大厅与设置模态；ENet 会话保持连接供正式牌桌继续使用。
func confirm_match_started() -> void:
	_close_settings()
	visible = false


## 房主设置保存成功后关闭模态；权威网关已经同步发出新快照，摘要与位置由 bind_lobby 完成重绘。
func confirm_settings_updated() -> void:
	_close_settings()


## 显示房间操作错误；摘要下方复用状态标签，不弹出阻断式系统窗口。
func show_error(message: String) -> void:
	# 房间错误标签；只在发生错误时显示，下一份有效快照会重新隐藏。
	var error_label: Label = %OnlineLobbyErrorLabel
	error_label.text = message
	error_label.visible = not message.is_empty()
	error_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger"))
	_refresh_room_controls()


## 按当前活动主题刷新大厅全部静态控件与动态玩家形象；不修改房间快照或未提交设置。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_background.color = BattleUIStyle.get_color("outer_background")
	_surface.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("table_surface"), BattleUIStyle.get_color("border"), 2, 8))
	_chat_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(Color(BattleUIStyle.get_color("metal_panel"), 0.94), BattleUIStyle.get_color("border"), 1, 6))
	_control_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(Color(BattleUIStyle.get_color("metal_panel"), 0.96), BattleUIStyle.get_color("border"), 1, 6))
	_settings_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	_settings_backdrop.color = Color(BattleUIStyle.get_color("shade"), 0.90)
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_address_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_room_summary_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_chat_history.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	(%OnlineLobbyChatTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%OnlineLobbySettingsTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%OnlineLobbyGameModeLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%OnlineLobbyPlayerCountLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%OnlineLobbyPasswordLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_apply_line_edit_style(_chat_input)
	_apply_line_edit_style(_password_input)
	_apply_spin_box_style(_player_count_input)
	_apply_option_button_style(_game_mode_option)
	BattleUIStyle.apply_interaction_button(_chat_send_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_settings_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_start_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_leave_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("danger"), false)
	BattleUIStyle.apply_interaction_button(_settings_save_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_settings_cancel_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	for seat_view: OnlineLobbyAvatar in _seat_views:
		if seat_view != null and is_instance_valid(seat_view):
			seat_view.refresh_ui_style()


## 根据当前总人数重建大厅位置；2至3人为单行3位，其余人数按上下两行对称分配。
func _render_seats() -> void:
	_clear_seats()
	if _snapshot.is_empty():
		return
	# 当前设置总人数；限制到项目支持范围，并让2人局同样绘制3个视觉位置。
	var player_count: int = clampi(int(_snapshot.get("player_count", 2)), 2, NetworkGateway.MAX_MATCH_PLAYER_COUNT)
	# 当前视觉位置数；2至3人固定3位，其余与总人数一致。
	var slot_count: int = MINIMUM_DISPLAY_SLOT_COUNT if player_count <= 3 else player_count
	# 大厅成员按座位索引映射；空位置不创建伪成员字典。
	var members_by_seat: Dictionary = {}
	for member_variant: Variant in _snapshot.get("members", []) as Array:
		var member: Dictionary = member_variant as Dictionary
		members_by_seat[int(member.get("seat_index", -1))] = member.duplicate(true)
	# 每行位置数量；奇数时上排多1个，偶数上下平分，2至3人只使用单行。
	var top_count: int = slot_count if player_count <= 3 else ceili(float(slot_count) / 2.0)
	# 下排位置数量；2至3人为0，其余为剩余位置。
	var bottom_count: int = slot_count - top_count
	# 玩家组件宽度；用于在中央区域内分别居中上下两行。
	var card_width: float = AVATAR_COMPONENT_SIZE.x
	# 玩家组件高度；包含上方玩家名，布局必须保证名字不与另一行插画重叠。
	var component_height: float = AVATAR_COMPONENT_SIZE.y
	# 上排总宽度；同一行相邻位置按固定水平间距分隔。
	var top_width: float = card_width * float(top_count) + horizontal_slot_gap * float(maxi(top_count - 1, 0))
	# 下排总宽度；空下排宽度为0，不参与坐标计算。
	var bottom_width: float = card_width * float(bottom_count) + horizontal_slot_gap * float(maxi(bottom_count - 1, 0))
	# 两行整体高度；单行只使用一张组件高度，双行增加垂直间距。
	var total_height: float = component_height if bottom_count == 0 else component_height * 2.0 + vertical_slot_gap
	# 整体起始纵坐标；让全部玩家位置在中央承载区严格垂直居中。
	var start_y: float = maxf((_seat_area.size.y - total_height) * 0.5, 0.0)
	for seat_index: int in range(slot_count):
		# 当前玩家或空位置组件；所有位置保持与武将牌一致的插画尺寸。
		var seat_view: OnlineLobbyAvatar = ONLINE_LOBBY_AVATAR_SCENE.instantiate() as OnlineLobbyAvatar
		_seat_area.add_child(seat_view)
		seat_view.configure(seat_index, members_by_seat.get(seat_index, {}) as Dictionary, _local_is_host, _local_peer_id)
		seat_view.empty_slot_pressed.connect(seat_change_requested.emit)
		seat_view.kick_requested.connect(kick_requested.emit)
		# 当前是否属于下排；上排索引0..top_count-1，下排继续使用稳定位置索引。
		var is_bottom_row: bool = seat_index >= top_count
		# 当前行内索引；用于计算相对本行居中的横坐标。
		var row_index: int = seat_index - top_count if is_bottom_row else seat_index
		# 当前行位置数量；上下行分别计算总宽，保证五人局3上2下保持对称。
		var row_count: int = bottom_count if is_bottom_row else top_count
		# 当前行总宽度；与 row_count 配套使用，空下排不会创建视图。
		var row_width: float = bottom_width if is_bottom_row else top_width
		# 当前行起始横坐标；两行各自在完整座位区域内居中。
		var row_start_x: float = maxf((_seat_area.size.x - row_width) * 0.5, 0.0)
		seat_view.position = Vector2(row_start_x + float(row_index) * (card_width + horizontal_slot_gap), start_y + (component_height + vertical_slot_gap if is_bottom_row else 0.0))
		_seat_views.append(seat_view)


## 更新大厅标题与房间摘要；模式显示名来自稳定配置，密码只显示开启状态。
func _render_room_summary() -> void:
	# 当前游戏模式稳定 ID；未知值按身份模式显示，实际开局仍由网关权威校验。
	var game_mode_id: String = str(_snapshot.get("game_mode_id", NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID))
	# 当前游戏模式玩家可见名称；从网关固定选项解析，避免 UI 自行维护第二份模式映射。
	var game_mode_name: String = _resolve_game_mode_display_name(game_mode_id)
	# 当前对局总人数；范围外快照只用于显示时限制，不写回网络状态。
	var player_count: int = clampi(int(_snapshot.get("player_count", 2)), 2, NetworkGateway.MAX_MATCH_PLAYER_COUNT)
	# 当前真人数量；用于开始按钮与摘要说明。
	var member_count: int = int(_snapshot.get("member_count", 0))
	# 当前密码状态；公共快照只含布尔值，不显示或传递房主明文密码。
	var password_text: String = "已设置" if bool(_snapshot.get("has_password", false)) else "未设置"
	_title_label.text = "联机大厅 · %s" % game_mode_name
	_room_summary_label.text = "真人：%d  ｜  对局人数：%d  ｜  房间密码：%s" % [member_count, player_count, password_text]
	(%OnlineLobbyErrorLabel as Label).visible = false


## 把公共聊天历史渲染为“时间 玩家名：正文”；不启用 BBCode，防止用户文本注入样式标签。
func _render_chat_history() -> void:
	var lines: Array[String] = []
	for chat_variant: Variant in _snapshot.get("chat_history", []) as Array:
		# 当前公共聊天记录；字段已经由房主标准化，缺失值使用可读回退。
		var chat_entry: Dictionary = chat_variant as Dictionary
		lines.append("[%s] %s：%s" % [str(chat_entry.get("time_text", "--:--:--")), str(chat_entry.get("display_name", "玩家")), str(chat_entry.get("message", ""))])
	_chat_history.text = "\n".join(lines)
	call_deferred("_scroll_chat_to_bottom")


## 根据房主权限与真人数量刷新右下操作；客户端只保留离开按钮。
func _refresh_room_controls() -> void:
	_settings_button.visible = _local_is_host
	_start_button.visible = _local_is_host
	_start_button.disabled = not _local_is_host or int(_snapshot.get("member_count", 0)) < 2
	_leave_button.text = "关闭房间" if _local_is_host else "离开房间"
	_player_count_input.min_value = maxi(int(_snapshot.get("member_count", 0)), 2)
	_player_count_input.max_value = NetworkGateway.MAX_MATCH_PLAYER_COUNT


## 打开房主对局设置；当前权威快照回填模式、人数与房主私有密码。
func _open_settings() -> void:
	if not _local_is_host:
		return
	_select_game_mode(str(_snapshot.get("game_mode_id", NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID)))
	_player_count_input.value = clampi(int(_snapshot.get("player_count", 2)), int(_player_count_input.min_value), NetworkGateway.MAX_MATCH_PLAYER_COUNT)
	_password_input.text = str(_snapshot.get("room_password", ""))
	_settings_backdrop.visible = true
	_settings_panel.visible = true
	_settings_panel.move_to_front()
	_suspend_settings_background_focus()
	_settings_save_button.grab_focus()


## 关闭房主设置模态并丢弃未提交编辑；下一次打开会重新读取权威快照。
func _close_settings() -> void:
	_settings_backdrop.visible = false
	_settings_panel.visible = false
	_restore_settings_background_focus()
	if visible and _local_is_host:
		_settings_button.grab_focus()


## 保存房间设置请求；稳定模式 ID 从选项元数据读取，人数与密码仍由房主网关最终校验。
func _save_settings() -> void:
	# 当前游戏模式稳定 ID；选项异常时回退身份模式，避免显示文本被当作协议值。
	var game_mode_id: String = str(_game_mode_option.get_item_metadata(_game_mode_option.selected)) if _game_mode_option.selected >= 0 else NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID
	# 当前人数输入；编辑文本优先，0或非法值回退 SpinBox 已确认值。
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	# 最终人数候选；网络层仍会复核当前真人数与10人上限。
	var player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	settings_update_requested.emit(game_mode_id, player_count, _password_input.text)


## 房主请求开始当前设置的对局；按钮暂时禁用直到成功开局或协调器回传错误。
func _request_start_match() -> void:
	if not _local_is_host:
		return
	_start_button.disabled = true
	start_match_requested.emit()


## 发送当前聊天输入；标准化由网关统一完成，组件只阻止纯空白消息。
func _submit_chat_message() -> void:
	if _chat_input.text.strip_edges().is_empty():
		return
	chat_requested.emit(_chat_input.text)
	_chat_input.clear()
	_chat_input.grab_focus()


## 聊天输入按回车时复用发送按钮行为，保证键盘与鼠标得到相同消息处理。
func _on_chat_text_submitted(_text: String) -> void:
	_submit_chat_message()


## 点击设置遮罩空白区域时关闭模态；只处理鼠标左键按下避免滚轮误触。
func _on_settings_backdrop_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_close_settings()
		accept_event()


## 清理全部动态位置组件；下一份大厅快照会重新创建与当前人数完全一致的布局。
func _clear_seats() -> void:
	_seat_views.clear()
	for child: Node in _seat_area.get_children():
		_seat_area.remove_child(child)
		child.queue_free()


## 大厅中央区域尺寸变化时按当前人数重新计算座位；窗口缩放不会保留旧坐标。
func _on_seat_area_resized() -> void:
	if visible and not _snapshot.is_empty():
		_render_seats()


## 设置打开时冻结设置面板外的大厅焦点；动态玩家形象中的空位和踢出按钮也会自动进入隔离范围。
func _suspend_settings_background_focus() -> void:
	for control_node: Node in find_children("*", "Control", true, false):
		# 当前可聚焦控件；设置面板及其后代保留原焦点模式，其余控件缓存后设为不可聚焦。
		var control: Control = control_node as Control
		if control == null or control == _settings_panel or _settings_panel.is_ancestor_of(control) or control.focus_mode == Control.FOCUS_NONE or _settings_background_focus_modes.has(control):
			continue
		_settings_background_focus_modes[control] = control.focus_mode
		control.focus_mode = Control.FOCUS_NONE


## 关闭设置时恢复大厅控件原始焦点模式；动态节点已经释放时安全跳过。
func _restore_settings_background_focus() -> void:
	for control_variant: Variant in _settings_background_focus_modes.keys():
		if not is_instance_valid(control_variant):
			continue
		var control: Control = control_variant as Control
		if control != null:
			control.focus_mode = int(_settings_background_focus_modes.get(control_variant, Control.FOCUS_ALL))
	_settings_background_focus_modes.clear()


## 将聊天滚动条移动到底部；延迟执行保证 RichTextLabel 已完成本帧内容布局。
func _scroll_chat_to_bottom() -> void:
	_chat_history.scroll_to_line(maxi(_chat_history.get_line_count() - 1, 0))


## 从网关稳定模式配置填充下拉框；显示名变化不会影响保存的模式 ID。
func _populate_game_mode_options() -> void:
	_game_mode_option.clear()
	for mode_option: Dictionary in NetworkGateway.LOBBY_GAME_MODE_OPTIONS:
		var option_index: int = _game_mode_option.item_count
		_game_mode_option.add_item(str(mode_option.get("display_name", "未知模式")))
		_game_mode_option.set_item_metadata(option_index, str(mode_option.get("id", NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID)))


## 按稳定模式 ID 选中下拉项；没有命中时回退首个已登记模式。
func _select_game_mode(game_mode_id: String) -> void:
	for option_index: int in range(_game_mode_option.item_count):
		if str(_game_mode_option.get_item_metadata(option_index)) == game_mode_id:
			_game_mode_option.select(option_index)
			return
	if _game_mode_option.item_count > 0:
		_game_mode_option.select(0)


## 返回稳定模式 ID 对应的玩家可见名称；未知 ID 回退“身份模式”。
func _resolve_game_mode_display_name(game_mode_id: String) -> String:
	for mode_option: Dictionary in NetworkGateway.LOBBY_GAME_MODE_OPTIONS:
		if str(mode_option.get("id", "")) == game_mode_id:
			return str(mode_option.get("display_name", "身份模式"))
	return "身份模式"


## 为大厅文本输入应用当前主题的常态与焦点边框。
func _apply_line_edit_style(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 为人数输入内部文本框应用同一主题样式；范围与动态最小值保持不变。
func _apply_spin_box_style(spin_box: SpinBox) -> void:
	_apply_line_edit_style(spin_box.get_line_edit())


## 为游戏模式下拉框与弹出列表应用当前主题配色。
func _apply_option_button_style(option_button: OptionButton) -> void:
	BattleUIStyle.apply_interaction_button(option_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	var popup: PopupMenu = option_button.get_popup()
	popup.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	popup.add_theme_stylebox_override("hover", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), false))
	popup.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	popup.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))


## 把焦点放到聊天输入；房主仍可通过 Tab 导航到设置与开始按钮。
func _focus_primary_control() -> void:
	if visible and not _settings_panel.visible:
		_chat_input.grab_focus()


## 响应全局 UI 风格切换；大厅快照、玩家位置和聊天内容保持不变。
func _on_ui_style_changed(_style_id: String) -> void:
	refresh_ui_style()


## 大厅可见时 Esc 优先关闭房间设置，未打开设置时执行离开房间请求。
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _settings_panel.visible:
		_close_settings()
	else:
		leave_requested.emit()
	get_viewport().set_input_as_handled()
