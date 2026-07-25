extends Node

## 局域网联机 UI 回归测试。验证只读连接入口、独立联机大厅、形象尺寸、对称座位、聊天、换位、房间设置、踢出入口、双主题与离开恢复。

## 正式主场景资源；测试复用完整节点树，覆盖主菜单、牌桌协调器、网络网关与两个联机界面的真实信号链。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 测试玩家使用的稳定武将 ID；希儿在正式数据库中登记了插画，可验证大厅只加载原始插画纹理。
const TEST_AVATAR_CHARACTER_ID: String = "xier"

## 大厅形象期望插画尺寸；必须与正式武将牌一致，但大厅组件不能复用武将牌场景。
const EXPECTED_AVATAR_SIZE: Vector2 = Vector2(148.35, 197.8)

## 几何比较允许误差；界面采用浮点尺寸，0.05像素足以覆盖布局计算误差且不会掩盖实际错位。
const POSITION_EPSILON: float = 0.05

## 测试期间实例化的完整主场景；结束前主动释放并退出 SceneTree。
var _main_instance: Control


## 实例化主场景并依次验证连接入口、房主大厅、动态布局、主题刷新与离开恢复。
func _ready() -> void:
	GameSettings.set_online_player_name("大厅测试房主")
	GameSettings.set_online_avatar_character_id(TEST_AVATAR_CHARACTER_ID)
	GameSettings.set_ui_style(UIStyleRegistry.DEFAULT_STYLE_ID)
	_main_instance = MAIN_SCENE.instantiate() as Control
	get_tree().root.add_child.call_deferred(_main_instance)
	await get_tree().process_frame
	await get_tree().process_frame
	# 启动主菜单；连接入口和正式大厅都必须默认隐藏。
	var main_menu: MainMenu = _main_instance.get_node("%MainMenu") as MainMenu
	# 局域网入口按钮；用于验证文案、入口模态和离开后的焦点恢复。
	var lan_button: Button = _main_instance.get_node("%MainMenuLanButton") as Button
	# 局域网连接入口；只能收集地址、端口与密码，不再保留成员列表或开始按钮。
	var connection_panel: LanLobbyPanel = _main_instance.get_node("%LanLobbyPanel") as LanLobbyPanel
	# 连接成功后的正式联机大厅；负责位置、聊天、设置、开始与离开操作。
	var online_lobby_panel: OnlineLobbyPanel = _main_instance.get_node("%OnlineLobbyPanel") as OnlineLobbyPanel
	# 单机开始按钮；任一联机模态打开时必须失去焦点能力，避免键盘操作穿透。
	var start_game_button: Button = _main_instance.get_node("%StartGameButton") as Button
	if main_menu == null or lan_button == null or connection_panel == null or online_lobby_panel == null or not main_menu.visible or connection_panel.visible or online_lobby_panel.visible or lan_button.text != "局域网联机":
		_fail("startup_entry")
		return
	main_menu.set_next_player_count(2)
	(_main_instance.get_node("%MainMenuPlayerCountInput") as SpinBox).get_line_edit().text = "2"
	lan_button.pressed.emit()
	await get_tree().process_frame
	# 玩家名称只读文本；连接入口只能显示联机设置保存值，不得恢复昵称输入框。
	var display_name_value: Label = connection_panel.get_node("%LanDisplayNameValue") as Label
	# 房间密码输入；创建与加入复用同一凭据输入，必须采用密文显示并限制32字符。
	var room_password_input: LineEdit = connection_panel.get_node("%LanRoomPasswordInput") as LineEdit
	# 大厅端口输入；测试使用独立高位端口，减少并行执行时的占用冲突。
	var port_input: SpinBox = connection_panel.get_node("%LanPortInput") as SpinBox
	# 建房按钮；通过真实按钮信号验证连接入口到网关再到正式大厅的完整协调链路。
	var host_button: Button = connection_panel.get_node("%LanHostButton") as Button
	if not connection_panel.visible or start_game_button.focus_mode != Control.FOCUS_NONE or display_name_value.text != "大厅测试房主" or connection_panel.get_node_or_null("%LanDisplayNameInput") != null or connection_panel.get_node_or_null("%LanConnectedView") != null or not room_password_input.secret or room_password_input.max_length != NetworkGateway.MAX_LOBBY_PASSWORD_LENGTH or host_button.focus_mode == Control.FOCUS_NONE:
		_fail("connection_entry")
		return
	# 测试端口；按进程 ID 选择非保留高位端口，保证同机多测试运行时更少冲突。
	var test_port: int = 39000 + (OS.get_process_id() % 9000)
	port_input.value = test_port
	port_input.get_line_edit().text = str(test_port)
	room_password_input.text = "大厅密码"
	host_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	# 局域网网关；房主大厅后续换位、聊天与设置都必须由该节点权威处理。
	var gateway: NetworkGateway = _main_instance.get_node("MatchController/NetworkGateway") as NetworkGateway
	# 房主地址提示；只在房主大厅显示可分享 IPv4 与当前监听端口。
	var address_label: Label = online_lobby_panel.get_node("%OnlineLobbyAddress") as Label
	# 房主开始按钮；一名真人时必须禁用，不能用 AI 补位绕过真人下限。
	var start_lan_button: Button = online_lobby_panel.get_node("%OnlineLobbyStartButton") as Button
	# 房主对局设置按钮；客户端隐藏，房主可修改模式、人数与密码。
	var settings_button: Button = online_lobby_panel.get_node("%OnlineLobbySettingsButton") as Button
	# 左下聊天输入；聊天快照重绘后仍应保留当前焦点，不得打断连续输入。
	var chat_input: LineEdit = online_lobby_panel.get_node("%OnlineLobbyChatInput") as LineEdit
	# 左下聊天发送按钮；通过真实按钮提交房主消息并等待公共快照回显。
	var chat_send_button: Button = online_lobby_panel.get_node("%OnlineLobbyChatSendButton") as Button
	# 公共聊天历史；房主消息必须以权威成员名称显示，不能采用输入正文自报署名。
	var chat_history: RichTextLabel = online_lobby_panel.get_node("%OnlineLobbyChatHistory") as RichTextLabel
	# 右下离开按钮；房主显示关闭房间并安全释放 ENet 监听端口。
	var leave_button: Button = online_lobby_panel.get_node("%OnlineLobbyLeaveButton") as Button
	# 房主私有快照；允许本机设置面板回填明文密码。
	var private_snapshot: Dictionary = gateway.get_lan_lobby_snapshot(true)
	# 公共快照；发给客户端的版本只能暴露 has_password，禁止泄漏明文密码。
	var public_snapshot: Dictionary = gateway.get_lan_lobby_snapshot()
	if connection_panel.visible or not online_lobby_panel.visible or not gateway.is_lan_host() or not address_label.visible or not address_label.text.contains("端口：%d" % test_port) or not start_lan_button.visible or not start_lan_button.disabled or not settings_button.visible or leave_button.text != "关闭房间" or str(private_snapshot.get("room_password", "")) != "大厅密码" or public_snapshot.has("room_password") or not bool(public_snapshot.get("has_password", false)):
		_fail("host_lobby_state")
		return
	# 2人设置的视觉位置；设计要求仍固定显示3个居中横向位置。
	var two_player_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if two_player_seats.size() != 3:
		_fail("two_player_slot_count=%d" % two_player_seats.size())
		return
	# 房主形象组件；初始最小空位分配应让房主位于位置1。
	var host_avatar: OnlineLobbyAvatar = two_player_seats[0]
	# 房主名称标签；必须完整位于插画上方，不能覆盖到联机形象内部。
	var host_name_label: Label = host_avatar.get_node("%OnlineLobbyAvatarName") as Label
	# 房主原始插画；只显示 TextureRect，不存在武将牌 UI 子树。
	var host_artwork: TextureRect = host_avatar.get_node("%OnlineLobbyAvatarArtwork") as TextureRect
	# 插画圆角遮罩材质；边框本身不会裁切纹理四角，必须由该材质写入透明 Alpha。
	var host_artwork_material: ShaderMaterial = host_artwork.material as ShaderMaterial
	# 插画圆角遮罩源码；遮罩只能裁切 Alpha，不能乘 CanvasItem 颜色输入把角色形象调制为黑色。
	var host_artwork_shader_code: String = host_artwork_material.shader.code if host_artwork_material != null and host_artwork_material.shader != null else ""
	# 房主形象边框；占用位置必须复用空位的圆角边框规格包裹插画，而不是裸露纹理。
	var host_avatar_frame: Panel = host_avatar.get_node("%OnlineLobbyAvatarFrame") as Panel
	# 形象边框样式；只允许绘制透明中心与描边，黑色阴影会遮罩联机形象插画。
	var host_avatar_frame_style: StyleBoxFlat = host_avatar_frame.get_theme_stylebox("panel") as StyleBoxFlat
	# 房主插画矩形；尺寸与武将牌一致，纵坐标必须大于名称标签底边。
	var host_avatar_rect: Rect2 = host_avatar.get_avatar_rect()
	if host_avatar.get_seat_index() != 0 or host_artwork.texture == null or host_artwork_material == null or host_artwork_material.shader == null or host_artwork_shader_code.contains("texture(TEXTURE, UV) * COLOR") or not host_artwork_shader_code.contains("texture_color.a * mask_alpha") or host_avatar_frame == null or host_avatar_frame_style == null or host_avatar_frame_style.draw_center or host_avatar_frame_style.shadow_size != 0 or not host_avatar_frame.visible or not host_avatar_rect.size.is_equal_approx(EXPECTED_AVATAR_SIZE) or not host_avatar_frame.get_rect().is_equal_approx(host_avatar_rect) or host_avatar_rect.position.y < host_name_label.position.y + host_name_label.size.y or host_avatar.get_node_or_null("PlayerCardTemplate") != null or not host_name_label.text.contains("大厅测试房主"):
		_fail("host_avatar_geometry rect=%s name_rect=%s" % [host_avatar_rect, host_name_label.get_rect()])
		return
	# 超长房主地址；模拟多网卡地址列表，地址标签必须在大厅内容面内自动向左调整且不覆盖标题真实文字宽度。
	var long_host_addresses: Array[String] = ["192.168.100.120", "10.234.56.78", "172.31.255.254", "192.168.200.201"]
	online_lobby_panel.bind_lobby(private_snapshot, long_host_addresses, test_port)
	await get_tree().process_frame
	# 大厅内容面；地址标签几何以其局部坐标为准，不能越过四周圆角边界。
	var lobby_surface: Panel = online_lobby_panel.get_node("%OnlineLobbySurface") as Panel
	# 大厅标题；用实际文字宽度验证地址起点，而不是使用标题静态预留宽度。
	var lobby_title: Label = online_lobby_panel.get_node("%OnlineLobbyTitle") as Label
	# 标题字体；缺失主题字体视为布局异常，无法可靠验证文字不相交。
	var title_font: Font = lobby_title.get_theme_font("font")
	var title_text_width: float = title_font.get_string_size(lobby_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, lobby_title.get_theme_font_size("font_size")).x if title_font != null else -1.0
	if address_label.position.x < lobby_title.position.x + title_text_width + online_lobby_panel.host_address_title_gap - POSITION_EPSILON or address_label.position.x + address_label.size.x > lobby_surface.size.x - online_lobby_panel.host_address_right_margin + POSITION_EPSILON or address_label.size.x < 0.0:
		_fail("host_address_layout address=%s title_width=%f surface=%s" % [address_label.get_rect(), title_text_width, lobby_surface.size])
		return
	# 长地址绑定会按正式逻辑重建动态座位；后续座位断言必须重新取得新实例，不能继续引用已释放节点。
	two_player_seats = _get_seat_views(online_lobby_panel)
	# 三位置单行中心；第一个与最后一个位置围绕座位区域中心对称，三者纵坐标相同。
	var seat_area: Control = online_lobby_panel.get_node("%OnlineLobbySeatArea") as Control
	if not is_equal_approx(two_player_seats[0].position.y, two_player_seats[1].position.y) or not is_equal_approx(two_player_seats[1].position.y, two_player_seats[2].position.y) or absf(_row_center_x(two_player_seats) - seat_area.size.x * 0.5) > POSITION_EPSILON:
		_fail("two_player_layout")
		return
	# 点击第三个空位；房主权威快照必须把本地成员移动到对应稳定位置。
	var target_empty_button: Button = two_player_seats[2].get_node("%OnlineLobbyEmptySlotButton") as Button
	target_empty_button.pressed.emit()
	await get_tree().process_frame
	# 换位后的房主成员；视觉位置可为2，但正式开局时仍按真人位置顺序映射到合法玩家 ID。
	var moved_host_member: Dictionary = (gateway.get_lan_lobby_snapshot().get("members", []) as Array)[0] as Dictionary
	if int(moved_host_member.get("seat_index", -1)) != 2:
		_fail("seat_change=%s" % moved_host_member)
		return
	chat_input.grab_focus()
	chat_input.text = "欢迎来到联机大厅"
	chat_send_button.pressed.emit()
	await get_tree().process_frame
	# 聊天提交后快照会重绘全部大厅内容，但焦点必须继续留在聊天输入以支持连续发言。
	if not chat_history.text.contains("大厅测试房主：欢迎来到联机大厅") or get_viewport().gui_get_focus_owner() != chat_input:
		_fail("host_chat focus=%s history=%s" % [get_viewport().gui_get_focus_owner(), chat_history.text])
		return
	await _save_room_settings(online_lobby_panel, 5, "更新密码")
	# 五人位置；前三个在上、后两个在下，两排必须分别围绕座位区域中心对称。
	var five_player_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if five_player_seats.size() != 5 or not _share_row_y(five_player_seats.slice(0, 3)) or not _share_row_y(five_player_seats.slice(3, 5)) or five_player_seats[3].position.y <= five_player_seats[0].position.y or absf(_row_center_x(five_player_seats.slice(0, 3)) - seat_area.size.x * 0.5) > POSITION_EPSILON or absf(_row_center_x(five_player_seats.slice(3, 5)) - seat_area.size.x * 0.5) > POSITION_EPSILON:
		_fail("five_player_layout")
		return
	await _save_room_settings(online_lobby_panel, 8, "更新密码")
	# 八人位置；四上四下，两排数量和中心必须完全一致。
	var eight_player_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if eight_player_seats.size() != 8 or not _share_row_y(eight_player_seats.slice(0, 4)) or not _share_row_y(eight_player_seats.slice(4, 8)) or eight_player_seats[4].position.y <= eight_player_seats[0].position.y or absf(_row_center_x(eight_player_seats.slice(0, 4)) - seat_area.size.x * 0.5) > POSITION_EPSILON or absf(_row_center_x(eight_player_seats.slice(4, 8)) - seat_area.size.x * 0.5) > POSITION_EPSILON:
		_fail("eight_player_layout")
		return
	# 底排形象与左右下角功能区；插画保持原尺寸时仍不得压住聊天或房间控制面板。
	var chat_panel: PanelContainer = online_lobby_panel.get_node("%OnlineLobbyChatPanel") as PanelContainer
	# 右下房间控制面板；与聊天框共同定义座位区域下边界。
	var control_panel: PanelContainer = online_lobby_panel.get_node("%OnlineLobbyControlPanel") as PanelContainer
	for bottom_seat: OnlineLobbyAvatar in eight_player_seats.slice(4, 8):
		if bottom_seat.get_global_rect().intersects(chat_panel.get_global_rect()) or bottom_seat.get_global_rect().intersects(control_panel.get_global_rect()):
			_fail("eight_player_bottom_overlap seat=%s chat=%s control=%s" % [bottom_seat.get_global_rect(), chat_panel.get_global_rect(), control_panel.get_global_rect()])
			return
	# 模拟包含远端成员的房主公共快照；只验证房主悬停远端形象时出现管理按钮，不伪造网关成员状态。
	var kick_snapshot: Dictionary = gateway.get_lan_lobby_snapshot(true)
	# 远端测试成员；形象、名字与位置都使用协议中的公开字段。
	var remote_member: Dictionary = {
		"peer_id":2,
		"display_name":"待管理玩家",
		"avatar_character_id":TEST_AVATAR_CHARACTER_ID,
		"is_host":false,
		"join_order":1,
		"seat_index":1,
	}
	(kick_snapshot.get("members", []) as Array).append(remote_member)
	kick_snapshot["member_count"] = 2
	online_lobby_panel.bind_lobby(kick_snapshot, ["127.0.0.1"], test_port)
	await get_tree().process_frame
	# 远端形象组件；鼠标进入整个组件后显示“踢出”，离开后重新隐藏。
	var remote_avatar: OnlineLobbyAvatar = _get_seat_views(online_lobby_panel)[1]
	# 踢出按钮；房主本人、空位和普通客户端不应看到该按钮。
	var kick_button: Button = remote_avatar.get_node("%OnlineLobbyKickButton") as Button
	# 踢出按钮常态样式；背景必须比主题危险色更深，避免缩小后的管理入口缺少危险语义。
	var kick_button_style: StyleBoxFlat = kick_button.get_theme_stylebox("normal") as StyleBoxFlat
	# 期望踢出按钮宽度；由形象宽度和组件导出的左右内缩共同决定。
	var expected_kick_button_width: float = maxf(remote_avatar.avatar_size.x - remote_avatar.kick_button_horizontal_inset * 2.0, 24.0)
	if kick_button_style == null or not kick_button.size.is_equal_approx(Vector2(expected_kick_button_width, remote_avatar.kick_button_height)) or not kick_button_style.bg_color.is_equal_approx(BattleUIStyle.get_color("danger").darkened(remote_avatar.kick_button_darken_amount)):
		_fail("kick_button_style")
		return
	remote_avatar.mouse_entered.emit()
	if not kick_button.visible or kick_button.text != "踢出":
		_fail("kick_hover_show")
		return
	# 鼠标从形象移动到踢出按钮；父组件离开与子按钮进入在同一输入周期发生，按钮不得被短暂隐藏。
	remote_avatar.mouse_exited.emit()
	kick_button.mouse_entered.emit()
	await get_tree().process_frame
	if not kick_button.visible:
		_fail("kick_hover_flicker")
		return
	# 鼠标离开按钮和形象范围后才隐藏管理入口。
	kick_button.mouse_exited.emit()
	remote_avatar.mouse_exited.emit()
	await get_tree().process_frame
	if kick_button.visible:
		_fail("kick_hover_hide")
		return
	# 崩铁主题大厅边框；切换前记录当前主题结果，确保之后确实发生重绘。
	var space_surface_style: StyleBoxFlat = online_lobby_panel.get_node("%OnlineLobbySurface").get_theme_stylebox("panel") as StyleBoxFlat
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD)
	await get_tree().process_frame
	# 高级黑金主题大厅边框；必须使用新增主题的香槟金语义，且不能保留崩铁风格旧颜色。
	var premium_surface_style: StyleBoxFlat = online_lobby_panel.get_node("%OnlineLobbySurface").get_theme_stylebox("panel") as StyleBoxFlat
	if not premium_surface_style.border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_PREMIUM_BLACK_GOLD, "border")) or premium_surface_style.border_color.is_equal_approx(space_surface_style.border_color):
		_fail("premium_theme_refresh")
		return
	GameSettings.set_ui_style(UIStyleRegistry.STYLE_DECADE_WOOD)
	await get_tree().process_frame
	# 暖木主题大厅边框；必须来自统一主题注册表，不能保留崩铁风格的旧颜色。
	var wood_surface_style: StyleBoxFlat = online_lobby_panel.get_node("%OnlineLobbySurface").get_theme_stylebox("panel") as StyleBoxFlat
	if not wood_surface_style.border_color.is_equal_approx(UIStyleRegistry.get_color(UIStyleRegistry.STYLE_DECADE_WOOD, "border")) or wood_surface_style.border_color.is_equal_approx(space_surface_style.border_color):
		_fail("theme_refresh")
		return
	leave_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if online_lobby_panel.visible or connection_panel.visible or gateway.mode != NetworkGateway.Mode.OFFLINE or not main_menu.visible or lan_button.focus_mode == Control.FOCUS_NONE:
		_fail("leave_recovery")
		return
	# 关闭房间后立即使用同一端口再次建房；旧 ENet peer 必须已经从 SceneMultiplayer 和底层套接字完全释放。
	lan_button.pressed.emit()
	await get_tree().process_frame
	# 重新打开后的创建按钮；离开流程必须清除旧会话标记并解除上次建房期间设置的禁用状态。
	if host_button.disabled:
		_fail("recreate_room_host_button_disabled")
		return
	port_input.value = test_port
	port_input.get_line_edit().text = str(test_port)
	host_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not gateway.is_lan_host():
		_fail("recreate_room_after_close")
		return
	gateway.leave_lan("")
	print("LAN_LOBBY_UI_PASS port=%d" % test_port)
	_reset_global_settings()
	_main_instance.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## 通过房主设置模态保存总人数与密码；等待两帧让权威快照、动态位置与焦点恢复全部完成。
func _save_room_settings(online_lobby_panel: OnlineLobbyPanel, player_count: int, room_password: String) -> void:
	# 房主对局设置按钮；每次打开都会从权威快照回填当前值。
	var settings_button: Button = online_lobby_panel.get_node("%OnlineLobbySettingsButton") as Button
	# 对局人数输入；测试同步设置 Range 值与内部文本，覆盖鼠标和键盘两种读取路径。
	var player_count_input: SpinBox = online_lobby_panel.get_node("%OnlineLobbyPlayerCountInput") as SpinBox
	# 房间密码输入；保存后明文只保留在房主私有快照中。
	var password_input: LineEdit = online_lobby_panel.get_node("%OnlineLobbyPasswordInput") as LineEdit
	# 保存设置按钮；通过真实信号链调用网关校验并广播新大厅快照。
	var save_button: Button = online_lobby_panel.get_node("%OnlineLobbySettingsSaveButton") as Button
	settings_button.pressed.emit()
	await get_tree().process_frame
	player_count_input.value = player_count
	player_count_input.get_line_edit().text = str(player_count)
	password_input.text = room_password
	save_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame


## 返回座位区域中按位置索引创建的全部大厅形象组件；父组件每次快照都会按索引顺序重建。
func _get_seat_views(online_lobby_panel: OnlineLobbyPanel) -> Array[OnlineLobbyAvatar]:
	# 座位区域；只有 OnlineLobbyAvatar 动态子节点，不包含装饰或规则覆盖层。
	var seat_area: Control = online_lobby_panel.get_node("%OnlineLobbySeatArea") as Control
	# 类型化位置数组；测试后续可直接读取稳定索引、坐标与子控件。
	var seat_views: Array[OnlineLobbyAvatar] = []
	for child: Node in seat_area.get_children():
		if child is OnlineLobbyAvatar:
			seat_views.append(child as OnlineLobbyAvatar)
	return seat_views


## 判断同一排的全部位置是否共享纵坐标；空数组与单元素数组视为同排。
func _share_row_y(seat_views: Array[OnlineLobbyAvatar]) -> bool:
	if seat_views.size() <= 1:
		return true
	# 本排基准纵坐标；后续位置只允许存在浮点布局误差。
	var row_y: float = seat_views[0].position.y
	for seat_view: OnlineLobbyAvatar in seat_views:
		if absf(seat_view.position.y - row_y) > POSITION_EPSILON:
			return false
	return true


## 返回一排位置外接宽度的水平中心；用于验证奇数排与偶数排都独立居中。
func _row_center_x(seat_views: Array[OnlineLobbyAvatar]) -> float:
	if seat_views.is_empty():
		return 0.0
	# 本排最左边界；位置数组按索引顺序创建，因此首项即最左位置。
	var left_x: float = seat_views[0].position.x
	# 本排最右边界；末项横坐标加组件宽度得到完整外接矩形右边。
	var right_x: float = seat_views[-1].position.x + seat_views[-1].size.x
	return (left_x + right_x) * 0.5


## 恢复测试改动的全局联机资料与 UI 风格，避免同一进程后续场景继承测试值。
func _reset_global_settings() -> void:
	GameSettings.set_online_player_name(GameSettings.DEFAULT_ONLINE_PLAYER_NAME)
	GameSettings.set_online_avatar_character_id("")
	GameSettings.set_ui_style(UIStyleRegistry.DEFAULT_STYLE_ID)


## 输出稳定失败标识、关闭可能占用的 ENet 端口并以非零状态退出。
func _fail(reason: String) -> void:
	printerr("LAN_LOBBY_UI_FAIL %s" % reason)
	_reset_global_settings()
	if _main_instance != null and is_instance_valid(_main_instance):
		# 测试网关；仅在已经创建房间时释放端口，离线调用保持幂等。
		var gateway: NetworkGateway = _main_instance.get_node_or_null("MatchController/NetworkGateway") as NetworkGateway
		if gateway != null:
			gateway.leave_lan("")
		_main_instance.queue_free()
	get_tree().quit(1)
