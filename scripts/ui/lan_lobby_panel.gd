class_name LanLobbyPanel
extends Control

## 局域网大厅界面组件。该组件只收集连接参数、渲染公共成员快照并发出用户意图，不直接创建 ENet 或对局状态。

## 创建房间请求；参数依次为本地显示名与监听端口，实际网络错误由协调器回传。
signal host_requested(display_name: String, port: int)

## 加入房间请求；参数依次为本地显示名、房主 IPv4 地址与端口。
signal join_requested(display_name: String, address: String, port: int)

## 房主开始对局请求；总人数包含大厅真人与由权威端补齐的 AI 座位。
signal start_match_requested(player_count: int)

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

## 大厅全屏遮罩；阻断底层主菜单鼠标输入，并使用当前主题的 shade 语义色。
@onready var _backdrop: ColorRect = %LanLobbyBackdrop

## 大厅中央主面板；连接表单与成员视图共用同一固定布局，切换状态时不重建节点。
@onready var _panel: PanelContainer = %LanLobbyFrame

## 大厅标题；入口阶段显示“局域网联机”，连接后显示房主或客户端角色。
@onready var _title_label: Label = %LanLobbyTitle

## 当前连接状态文本；普通进度、成功提示和错误均在同一位置显示，避免弹窗阻断连接回调。
@onready var _status_label: Label = %LanLobbyStatus

## 玩家显示名只读文本；名称由主菜单联机设置统一提供，大厅入口只展示且不能修改。
@onready var _display_name_value: Label = %LanDisplayNameValue

## 房主 IPv4 地址输入框；创建房间时禁用语义，加入房间时读取点分十进制地址或 localhost。
@onready var _address_input: LineEdit = %LanAddressInput

## ENet 端口输入；创建与加入必须使用相同数值，默认由网关配置传入。
@onready var _port_input: SpinBox = %LanPortInput

## 创建房间按钮；点击后进入等待状态，直到协调器返回大厅快照或错误。
@onready var _host_button: Button = %LanHostButton

## 加入房间按钮；点击后进入异步连接状态，连接失败时由 bind_connection_state 恢复可用。
@onready var _join_button: Button = %LanJoinButton

## 连接参数表单；成功进入大厅后隐藏，防止同一会话中重复创建或加入。
@onready var _connection_form: VBoxContainer = %LanConnectionForm

## 已连接大厅视图；显示房主地址、成员名单、总人数配置和开始按钮。
@onready var _lobby_view: VBoxContainer = %LanConnectedView

## 房主可分享地址提示；客户端只显示已连接房主，不枚举自己的本机网卡。
@onready var _address_hint_label: Label = %LanAddressHint

## 大厅成员标题；显示当前真人数量，房主与客户端读取同一公共快照。
@onready var _member_count_label: Label = %LanMemberCount

## 大厅成员列表；每行显示昵称与房主标记，不展示 ENet peer_id 或稳定玩家 ID。
@onready var _member_list: RichTextLabel = %LanMemberList

## 对局总人数输入；最小值动态提升到当前真人数量，额外座位由 AI 补齐。
@onready var _player_count_input: SpinBox = %LanPlayerCountInput

## 房主开始按钮；客户端始终隐藏，房主至少等待2名真人并选择足够总人数后才可用。
@onready var _start_button: Button = %LanStartMatchButton

## 底部离开按钮；未连接时仅关闭面板，已连接时请求协调器断开会话。
@onready var _leave_button: Button = %LanLeaveButton

## 当前是否已经进入一个局域网会话；决定关闭按钮文案与是否需要实际断开 ENet。
var _session_active: bool = false

## 当前大厅角色文本；可取 host、client 或空字符串，只用于控制开始按钮和地址提示。
var _role: String = ""

## 当前已登记真人数量；房主开始按钮与总人数最小值共用该公开计数。
var _member_count: int = 0

## 当前状态是否为错误；主题刷新时据此恢复危险色，而不是覆盖为普通次级文字色。
var _status_is_error: bool = false


## 初始化全部局域网大厅控件；面板默认隐藏，只有主菜单入口显式打开后才接收输入。
func _ready() -> void:
	visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_port_input.min_value = MINIMUM_PORT
	_port_input.max_value = MAXIMUM_PORT
	_port_input.step = 1.0
	_player_count_input.min_value = MINIMUM_PLAYER_COUNT
	_player_count_input.max_value = MAXIMUM_PLAYER_COUNT
	_player_count_input.step = 1.0
	_address_input.text_submitted.connect(_on_address_submitted)
	_host_button.pressed.connect(_request_host)
	_join_button.pressed.connect(_request_join)
	_start_button.pressed.connect(_request_start_match)
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
		_player_count_input.value = clampi(default_player_count, MINIMUM_PLAYER_COUNT, MAXIMUM_PLAYER_COUNT)
		_port_input.value = clampi(default_port, MINIMUM_PORT, MAXIMUM_PORT)
		_display_name_value.text = GameSettings.online_player_name
		_show_entry_state()
	call_deferred("_focus_primary_control")


## 在协调器确认房主或客户端进入大厅后绑定公共成员快照；房主地址仅由本机网关提供。
func bind_lobby(lobby_snapshot: Dictionary, host_addresses: Array[String] = []) -> void:
	_session_active = true
	_role = str(lobby_snapshot.get("role", ""))
	_member_count = int(lobby_snapshot.get("member_count", 0))
	_connection_form.visible = false
	_lobby_view.visible = true
	_title_label.text = "局域网房间（房主）" if _role == "host" else "局域网房间"
	_leave_button.text = "离开房间"
	# 真人成员数组；成员文本只使用显示名与房主标记，不暴露网络连接标识。
	var members: Array = lobby_snapshot.get("members", []) as Array
	# 成员展示文本数组；每名真人独占一行，房主追加固定身份标记。
	var member_lines: Array[String] = []
	for member_variant: Variant in members:
		# 当前大厅成员公开数据；只消费显示名和房主标记字段。
		var member: Dictionary = member_variant as Dictionary
		# 当前成员显示名；缺失时回退通用名称，避免大厅出现空白行。
		var member_name: String = str(member.get("display_name", "玩家"))
		member_lines.append("%s%s" % [member_name, "（房主）" if bool(member.get("is_host", false)) else ""])
	_member_count_label.text = "真人玩家：%d 人" % _member_count
	_member_list.text = "\n".join(member_lines)
	# 对局总人数下限；已加入真人不能被房主配置排除，超出部分自动作为 AI 座位。
	_player_count_input.min_value = maxi(_member_count, MINIMUM_PLAYER_COUNT)
	_player_count_input.value = maxi(int(_player_count_input.value), int(_player_count_input.min_value))
	_player_count_input.editable = _role == "host"
	_start_button.visible = _role == "host"
	_start_button.disabled = _member_count < MINIMUM_PLAYER_COUNT
	_address_hint_label.visible = _role == "host"
	_address_hint_label.text = "房主地址：%s  ｜  端口：%d" % [" / ".join(host_addresses), get_port()] if _role == "host" else ""
	show_status("等待房主开始对局。" if _role != "host" else ("至少再等待1名真人玩家加入。" if _member_count < MINIMUM_PLAYER_COUNT else "房间已就绪，可由房主开始对局。"), false)
	call_deferred("_focus_primary_control")


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
	_role = ""
	_member_count = 0
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


## 返回房主配置的对局总人数；最少等于当前真人数量，最多10人。
func get_player_count() -> int:
	# 当前手动输入人数；0不属于合法范围，因此安全回退 SpinBox 数值。
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	# 最终候选总人数；返回前同时受当前真人数、最小开局人数和最大人数约束。
	var resolved_player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	return clampi(resolved_player_count, maxi(_member_count, MINIMUM_PLAYER_COUNT), MAXIMUM_PLAYER_COUNT)


## 按当前活动主题刷新面板、按钮、文本框与状态色；不修改任何连接参数或大厅数据。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_backdrop.color = BattleUIStyle.get_color("shade")
	_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	BattleUIStyle.apply_interaction_button(_host_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_join_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_start_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_leave_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger") if _status_is_error else BattleUIStyle.get_color("text_secondary"))
	_address_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_member_count_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_member_list.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	_display_name_value.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_apply_line_edit_style(_address_input)
	_apply_spin_box_style(_port_input)
	_apply_spin_box_style(_player_count_input)


## 恢复未连接入口布局；该函数不清空玩家输入的昵称和地址，便于失败后直接重试。
func _show_entry_state() -> void:
	_connection_form.visible = true
	_lobby_view.visible = false
	_title_label.text = "局域网联机"
	_leave_button.text = "返回主菜单"
	_set_connection_buttons_enabled(true)
	show_status("创建房间，或输入房主的局域网 IPv4 地址加入。", false)


## 提交创建房间请求；网络建立期间暂时禁用两个入口按钮，防止重复占用端口。
func _request_host() -> void:
	_set_connection_buttons_enabled(false)
	show_status("正在创建局域网房间……", false)
	host_requested.emit(GameSettings.online_player_name, get_port())


## 提交加入房间请求；空地址由网关回退127.0.0.1，适合本机双实例测试。
func _request_join() -> void:
	_set_connection_buttons_enabled(false)
	show_status("正在连接局域网房主……", false)
	join_requested.emit(GameSettings.online_player_name, _address_input.text, get_port())


## 房主提交开始对局请求；按钮随后保持禁用，直到协调器确认开局或返回错误。
func _request_start_match() -> void:
	_start_button.disabled = true
	show_status("正在创建权威局域网对局……", false)
	start_match_requested.emit(get_player_count())


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


## 把键盘焦点放到当前状态的主要操作；入口优先创建房间，大厅房主优先开始，客户端优先离开。
func _focus_primary_control() -> void:
	if not visible:
		return
	if _connection_form.visible:
		_host_button.grab_focus()
	elif _role == "host" and _start_button.visible and not _start_button.disabled:
		_start_button.grab_focus()
	else:
		_leave_button.grab_focus()


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
