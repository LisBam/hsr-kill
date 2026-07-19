class_name LanLobbyPanel
extends Control

## 局域网连接入口组件。该组件只收集建房或加入参数并发出用户意图，不渲染已连接大厅，也不直接创建 ENet 或对局状态。

## 创建房间请求；参数依次为本地名称、联机形象、房间密码、监听端口与初始总人数。
signal host_requested(display_name: String, avatar_character_id: String, room_password: String, port: int, player_count: int)

## 加入房间请求；参数依次为本地名称、联机形象、房间密码、房主 IPv4 地址与端口。
signal join_requested(display_name: String, avatar_character_id: String, room_password: String, address: String, port: int)

## 离开或关闭请求；协调器根据当前是否已连接决定只隐藏面板还是断开网络会话。
signal leave_requested()

## 局域网端口允许的最小值；1024避开系统保留端口，运行时无需动态修改。
const MINIMUM_PORT: int = 1024

## 局域网端口允许的最大值；65535为 TCP/UDP 端口上限，运行时无需动态修改。
const MAXIMUM_PORT: int = 65535

## 标准身份局允许的最少总人数；局域网至少需要2名真人才能由房主开始。
const MINIMUM_PLAYER_COUNT: int = 2

## 标准身份局允许的最多总人数；与权威身份规则和牌桌布局上限保持一致。
const MAXIMUM_PLAYER_COUNT: int = 10

## 连接入口全屏遮罩；阻断底层主菜单鼠标输入，并使用当前主题的 shade 语义色。
@onready var _backdrop: ColorRect = %LanLobbyBackdrop

## 连接入口中央主面板；承载只读玩家名、房主地址、端口、密码与创建/加入操作。
@onready var _panel: PanelContainer = %LanLobbyFrame

## 连接入口标题；固定显示“局域网联机”，成功登记后由独立联机大厅接管全屏表现。
@onready var _title_label: Label = %LanLobbyTitle

## 当前连接状态文本；普通进度、成功提示和错误均在同一位置显示，避免弹窗阻断连接回调。
@onready var _status_label: Label = %LanLobbyStatus

## 玩家显示名只读文本；名称由主菜单联机设置统一提供，连接入口只展示且不能修改。
@onready var _display_name_value: Label = %LanDisplayNameValue

## 房主 IPv4 地址输入框；创建房间时禁用语义，加入房间时读取点分十进制地址或 localhost。
@onready var _address_input: LineEdit = %LanAddressInput

## ENet 端口输入；创建与加入必须使用相同数值，默认由网关配置传入。
@onready var _port_input: SpinBox = %LanPortInput

## 房间密码输入；创建时作为新房密码，加入时作为验证凭据，空值表示无密码房间。
@onready var _room_password_input: LineEdit = %LanRoomPasswordInput

## 创建房间按钮；点击后进入等待状态，直到协调器返回大厅快照或错误。
@onready var _host_button: Button = %LanHostButton

## 加入房间按钮；点击后进入异步连接状态，连接失败时由 bind_connection_state 恢复可用。
@onready var _join_button: Button = %LanJoinButton

## 连接参数表单；成功进入大厅后随整个入口隐藏，防止同一会话中重复创建或加入。
@onready var _connection_form: VBoxContainer = %LanConnectionForm

## 底部返回按钮；连接前仅关闭入口，连接成功后入口会隐藏且由独立大厅提供离开操作。
@onready var _leave_button: Button = %LanLeaveButton

## 当前是否已经进入一个局域网会话；决定关闭按钮文案与是否需要实际断开 ENet。
var _session_active: bool = false

## 创建房间时采用的初始对局人数；由主菜单当前人数传入，范围2至10，进入大厅后可由房主继续修改。
var _initial_player_count: int = MINIMUM_PLAYER_COUNT

## 当前状态是否为错误；主题刷新时据此恢复危险色，而不是覆盖为普通次级文字色。
var _status_is_error: bool = false


## 初始化全部局域网连接控件；面板默认隐藏，只有主菜单入口显式打开后才接收输入。
func _ready() -> void:
	visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_port_input.min_value = MINIMUM_PORT
	_port_input.max_value = MAXIMUM_PORT
	_port_input.step = 1.0
	_room_password_input.max_length = NetworkGateway.MAX_LOBBY_PASSWORD_LENGTH
	_address_input.text_submitted.connect(_on_address_submitted)
	_host_button.pressed.connect(_request_host)
	_join_button.pressed.connect(_request_join)
	_leave_button.pressed.connect(_request_leave)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	GameSettings.online_player_name_changed.connect(_on_online_player_name_changed)
	_show_entry_state()
	refresh_ui_style()


## 打开局域网入口并写入主菜单当前人数与网关默认端口；已有会话时保留大厅状态。
func open_panel(default_player_count: int, default_port: int) -> void:
	visible = true
	move_to_front()
	if not _session_active:
		_initial_player_count = clampi(default_player_count, MINIMUM_PLAYER_COUNT, MAXIMUM_PLAYER_COUNT)
		_port_input.value = clampi(default_port, MINIMUM_PORT, MAXIMUM_PORT)
		_display_name_value.text = GameSettings.online_player_name
		_show_entry_state()
	call_deferred("_focus_primary_control")


## 在协调器确认房主或客户端进入大厅后隐藏连接入口；正式成员、座位与设置改由 OnlineLobbyPanel 渲染。
func bind_lobby(lobby_snapshot: Dictionary, host_addresses: Array[String] = []) -> void:
	_session_active = true
	visible = false


## 绑定底层连接状态；连接失败时恢复入口表单，成功进入大厅后的文案由 bind_lobby 接管。
func bind_connection_state(is_connected: bool, message: String) -> void:
	show_status(message, not is_connected and not message.is_empty())
	if not is_connected and not _session_active:
		_set_connection_buttons_enabled(true)


## 显示一个可重试错误；若尚未进入大厅则恢复创建和加入按钮。
func show_error(message: String) -> void:
	show_status(message, true)
	if not _session_active:
		_set_connection_buttons_enabled(true)


## 对局正式开始后隐藏大厅；ENet 会话保持连接，后续退出由牌桌统一处理。
func confirm_match_started() -> void:
	visible = false


## 会话结束后恢复连接入口；保留最后错误或断开原因，方便玩家修正地址后重试。
func return_to_entry(message: String = "") -> void:
	_session_active = false
	visible = true
	_show_entry_state()
	if not message.is_empty():
		show_status(message, true)
	call_deferred("_focus_primary_control")


## 返回输入框当前端口；编辑中的文本优先，非法或空文本回退 SpinBox 已确认值。
func get_port() -> int:
	# 当前手动输入端口；0不属于允许范围，可作为空文本与非法文本回退标记。
	var typed_port: int = _port_input.get_line_edit().text.to_int()
	# 最终候选端口；空文本或非法文本回退 SpinBox 当前数值，返回前统一限制合法范围。
	var resolved_port: int = int(_port_input.value) if typed_port == 0 else typed_port
	return clampi(resolved_port, MINIMUM_PORT, MAXIMUM_PORT)


## 返回创建房间时采用的初始对局总人数；正式大厅中的后续调整由 OnlineLobbyPanel 与网关管理。
func get_player_count() -> int:
	return clampi(_initial_player_count, MINIMUM_PLAYER_COUNT, MAXIMUM_PLAYER_COUNT)


## 按当前活动主题刷新面板、按钮、文本框与状态色；不修改任何连接参数或大厅数据。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_backdrop.color = BattleUIStyle.get_color("shade")
	_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	BattleUIStyle.apply_interaction_button(_host_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_join_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_leave_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger") if _status_is_error else BattleUIStyle.get_color("text_secondary"))
	_display_name_value.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_apply_line_edit_style(_address_input)
	_apply_line_edit_style(_room_password_input)
	_apply_spin_box_style(_port_input)


## 恢复未连接入口布局；该函数不清空玩家输入的昵称和地址，便于失败后直接重试。
func _show_entry_state() -> void:
	_connection_form.visible = true
	_title_label.text = "局域网联机"
	_leave_button.text = "返回主菜单"
	_set_connection_buttons_enabled(true)
	show_status("创建房间，或输入房主的局域网 IPv4 地址加入。", false)


## 提交创建房间请求；网络建立期间暂时禁用两个入口按钮，防止重复占用端口。
func _request_host() -> void:
	_set_connection_buttons_enabled(false)
	show_status("正在创建局域网房间……", false)
	host_requested.emit(GameSettings.online_player_name, GameSettings.online_avatar_character_id, _room_password_input.text, get_port(), _initial_player_count)


## 提交加入房间请求；空地址由网关回退127.0.0.1，适合本机双实例测试。
func _request_join() -> void:
	_set_connection_buttons_enabled(false)
	show_status("正在连接局域网房主……", false)
	join_requested.emit(GameSettings.online_player_name, GameSettings.online_avatar_character_id, _room_password_input.text, _address_input.text, get_port())


## 提交离开请求；协调器负责区分未连接关闭、客户端断开与房主关闭整个房间。
func _request_leave() -> void:
	leave_requested.emit()


## 地址输入按回车时默认加入房间；便于键盘完成完整直连流程。
func _on_address_submitted(_text: String) -> void:
	if _connection_form.visible and not _join_button.disabled:
		_request_join()


## 同步创建与加入按钮状态；连接回调返回前两者始终一起禁用，避免并发建立两个 ENet peer。
func _set_connection_buttons_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled


## 更新大厅状态文本与语义颜色；主题切换后仍由 _status_is_error 恢复正确颜色。
func show_status(message: String, is_error: bool) -> void:
	_status_is_error = is_error
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger") if is_error else BattleUIStyle.get_color("text_secondary"))


## 把键盘焦点放到连接入口主要操作；建房是默认动作，键盘仍可通过 Tab 访问加入与返回。
func _focus_primary_control() -> void:
	if not visible:
		return
	_host_button.grab_focus()


## 为大厅文本输入应用当前主题的常态与焦点边框；内容与光标仍由 Godot LineEdit 管理。
func _apply_line_edit_style(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 为大厅 SpinBox 内部文本框应用当前主题；范围、步长与动态最小人数不受视觉刷新影响。
func _apply_spin_box_style(spin_box: SpinBox) -> void:
	_apply_line_edit_style(spin_box.get_line_edit())


## 响应全局 UI 风格切换；只重绘现有节点，不重置连接表单或成员列表。
func _on_ui_style_changed(_style_id: String) -> void:
	refresh_ui_style()


## 同步联机设置中的玩家名称；仅入口表单显示该值，已连接大厅成员名称继续以公共快照为准。
func _on_online_player_name_changed(player_name: String) -> void:
	_display_name_value.text = player_name


## 大厅打开时允许 Esc 执行与底部离开按钮相同的安全退出请求。
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_request_leave()
		get_viewport().set_input_as_handled()
