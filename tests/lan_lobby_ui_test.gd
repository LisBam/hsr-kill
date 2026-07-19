extends Node

## 局域网大厅 UI 回归测试。验证主菜单入口、模态焦点、单人房主状态、地址提示与安全离开流程。

## 正式主场景资源；测试复用完整节点树，避免独立假组件遗漏主菜单协调逻辑。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 测试期间实例化的完整主场景；结束前主动释放并退出 SceneTree。
var _main_instance: Control


## 实例化主场景并依次验证联机入口、建房大厅和离开恢复状态。
func _ready() -> void:
	_main_instance = MAIN_SCENE.instantiate() as Control
	get_tree().root.add_child.call_deferred(_main_instance)
	await get_tree().process_frame
	await get_tree().process_frame
	# 启动主菜单；联机入口必须作为独立按钮存在且大厅默认隐藏。
	var main_menu: MainMenu = _main_instance.get_node("%MainMenu") as MainMenu
	# 局域网入口按钮；用于验证按钮文案、模态开启与离开后的焦点恢复。
	var lan_button: Button = _main_instance.get_node("%MainMenuLanButton") as Button
	# 局域网大厅面板；用于验证默认可见性、建房状态和安全关闭流程。
	var lobby_panel: LanLobbyPanel = _main_instance.get_node("%LanLobbyPanel") as LanLobbyPanel
	# 单机开始按钮；大厅打开时必须暂时取消焦点，避免键盘操作穿透模态层。
	var start_game_button: Button = _main_instance.get_node("%StartGameButton") as Button
	if main_menu == null or lan_button == null or lobby_panel == null or not main_menu.visible or lobby_panel.visible or lan_button.text != "局域网联机":
		_fail("startup_entry")
		return
	lan_button.pressed.emit()
	await get_tree().process_frame
	# 大厅连接入口控件；底层单机按钮必须暂停焦点，昵称输入获得模态焦点。
	var display_name_input: LineEdit = lobby_panel.get_node("%LanDisplayNameInput") as LineEdit
	# 大厅端口输入框；测试写入独立高位端口并核对地址提示使用同一数值。
	var port_input: SpinBox = lobby_panel.get_node("%LanPortInput") as SpinBox
	# 建房按钮；通过真实按钮信号验证 UI 到网络网关的完整协调链路。
	var host_button: Button = lobby_panel.get_node("%LanHostButton") as Button
	# 局域网开局按钮；单人大厅必须保持禁用，达到真人下限后才可使用。
	var start_lan_button: Button = lobby_panel.get_node("%LanStartMatchButton") as Button
	# 房主地址提示；建房后应展示可供局域网成员输入的地址与监听端口。
	var address_hint: Label = lobby_panel.get_node("%LanAddressHint") as Label
	# 真人数量标签；单人建房后应准确显示一名真人成员。
	var member_count_label: Label = lobby_panel.get_node("%LanMemberCount") as Label
	# 离开按钮；会话建立后负责关闭 ENet、隐藏大厅并恢复主菜单状态。
	var leave_button: Button = lobby_panel.get_node("%LanLeaveButton") as Button
	if not lobby_panel.visible or start_game_button.focus_mode != Control.FOCUS_NONE or display_name_input.focus_mode == Control.FOCUS_NONE:
		_fail("modal_focus")
		return
	# 测试端口；按进程 ID 选择非保留高位端口，减少并行测试端口冲突概率。
	var test_port: int = 39000 + (OS.get_process_id() % 9000)
	port_input.value = test_port
	port_input.get_line_edit().text = str(test_port)
	display_name_input.text = "大厅测试房主"
	host_button.pressed.emit()
	await get_tree().process_frame
	if not lobby_panel.visible or member_count_label.text != "真人玩家：1 人" or not start_lan_button.disabled or not address_hint.visible or not address_hint.text.contains("端口：%d" % test_port) or leave_button.text != "离开房间":
		_fail("host_lobby_state visible=%s members=%s start_disabled=%s address_visible=%s address=%s leave=%s port=%d" % [lobby_panel.visible, member_count_label.text, start_lan_button.disabled, address_hint.visible, address_hint.text, leave_button.text, test_port])
		return
	leave_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	# 离开后必须恢复离线网关、隐藏大厅并归还主菜单焦点能力。
	var gateway: NetworkGateway = _main_instance.get_node("MatchController/NetworkGateway") as NetworkGateway
	if lobby_panel.visible or gateway.mode != NetworkGateway.Mode.OFFLINE or not main_menu.visible or lan_button.focus_mode == Control.FOCUS_NONE:
		_fail("leave_recovery")
		return
	# 客户端大厅快照；显式覆盖非房主分支，确保空地址列表仍保持 Array[String] 类型并能完成 UI 绑定。
	var client_lobby_snapshot: Dictionary = {
		"role":"client",
		"member_count":2,
		"members":[
			{"peer_id":1, "display_name":"测试房主", "is_host":true, "join_order":0},
			{"peer_id":2, "display_name":"测试客户端", "is_host":false, "join_order":1},
		],
		"player_count":0,
		"match_active":false,
	}
	lan_button.pressed.emit()
	await get_tree().process_frame
	# 测试网关角色；仅切换大厅显示分支，不创建 ENet 对等体或修改对局规则状态。
	gateway.lan_role = NetworkGateway.LanRole.CLIENT
	gateway.lan_lobby_changed.emit(client_lobby_snapshot)
	await get_tree().process_frame
	# 客户端成员列表；用于确认房主与客户端名称均已由公共快照成功渲染。
	var member_list: RichTextLabel = lobby_panel.get_node("%LanMemberList") as RichTextLabel
	if not lobby_panel.visible or member_count_label.text != "真人玩家：2 人" or address_hint.visible or start_lan_button.visible or not member_list.text.contains("测试房主（房主）") or not member_list.text.contains("测试客户端"):
		_fail("client_lobby_state visible=%s members=%s address_visible=%s start_visible=%s list=%s" % [lobby_panel.visible, member_count_label.text, address_hint.visible, start_lan_button.visible, member_list.text])
		return
	gateway.lan_role = NetworkGateway.LanRole.NONE
	print("LAN_LOBBY_UI_PASS port=%d" % test_port)
	_main_instance.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## 输出稳定失败标识、关闭可能占用的 ENet 端口并以非零状态退出。
func _fail(reason: String) -> void:
	printerr("LAN_LOBBY_UI_FAIL %s" % reason)
	if _main_instance != null and is_instance_valid(_main_instance):
		# 测试网关；仅在已经创建房间时释放端口，离线调用保持幂等。
		var gateway: NetworkGateway = _main_instance.get_node_or_null("MatchController/NetworkGateway") as NetworkGateway
		if gateway != null:
			gateway.leave_lan("")
		_main_instance.queue_free()
	get_tree().quit(1)
