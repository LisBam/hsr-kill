extends Node

## 局内聊天功能回归测试。验证网关对局聊天的正文标准化、200字符截断、100条历史上限与清空；
## 局内菜单“聊天”按钮的存在与切换；聊天窗口的提交、历史正文同步；以及发言者头顶聊天气泡的
## 显示内容与自动定位。测试使用离线回环模式，不创建任何网络连接。

## 正式主场景；聊天按钮、聊天窗口与气泡都必须存在于真实牌桌组件树中。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 场景实例化后等待稳定的帧数；与其他全场景测试保持一致，覆盖延迟初始化的运行时组件。
const SETTLE_FRAME_COUNT: int = 6

## 测试硬超时毫秒数；异步流程异常挂起时保证进程按失败退出而不是永久悬挂。
const TEST_TIMEOUT_MILLISECONDS: int = 20000

## 网关聊天信号捕获列表；每次 match_chat_received 追加一条，用于断言信号与历史一致。
var _received_chat_entries: Array[Dictionary] = []


## 延迟执行以等待自动加载数据库完成索引。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次运行网关层与界面层断言；任意失败均以非零状态退出。
func _run() -> void:
	_install_timeout_guard()
	# 正式主场景实例；聊天功能全部挂在牌桌根节点之下。
	var main_instance: Control = MAIN_SCENE.instantiate() as Control
	add_child(main_instance)
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 权威控制器；离线回环下同时承担规则与本地快照广播。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 通信网关；离线模式立即回环聊天条目。
	var gateway: NetworkGateway = main_instance.get_node("MatchController/NetworkGateway") as NetworkGateway
	gateway.match_chat_received.connect(_on_match_chat_received)
	# 正文标准化：首尾空白移除、内部换行替换为空格。
	gateway.send_match_chat_message("  你好\n世界  ", 3, "测试玩家")
	# 当前网关聊天历史；标准化断言使用第一条。
	var history: Array[Dictionary] = gateway.get_match_chat_history()
	if history.size() != 1 or str(history[0].get("message", "")) != "你好 世界" or int(history[0].get("sender_player_id", -1)) != 3 or str(history[0].get("display_name", "")) != "测试玩家" or _received_chat_entries.size() != 1:
		_fail("offline_chat_sanitize %s" % str(history))
		return
	# 长度截断：250字符正文必须裁到200字符上限。
	gateway.send_match_chat_message("长".repeat(250), 0, "玩家1")
	history = gateway.get_match_chat_history()
	if history.size() != 2 or str(history[1].get("message", "")).length() != NetworkGateway.MAX_MATCH_CHAT_LENGTH:
		_fail("offline_chat_truncate")
		return
	# 历史上限：连续写入超过100条后只保留最近100条。
	for message_index: int in range(NetworkGateway.MAX_MATCH_CHAT_HISTORY + 5):
		gateway.send_match_chat_message("消息%d" % message_index, 0, "玩家1")
	history = gateway.get_match_chat_history()
	if history.size() != NetworkGateway.MAX_MATCH_CHAT_HISTORY or str(history[history.size() - 1].get("message", "")) != "消息%d" % (NetworkGateway.MAX_MATCH_CHAT_HISTORY + 4):
		_fail("offline_chat_history_cap size=%d" % history.size())
		return
	gateway.clear_match_chat_history()
	if not gateway.get_match_chat_history().is_empty():
		_fail("offline_chat_clear")
		return
	_received_chat_entries.clear()
	# 进入真实离线对局；显式传入人数、种子与模式，不依赖本机保存的下一局设置。
	if not match_controller.start_match(2, 7, "identity"):
		_fail("offline_match_start")
		return
	(main_instance.get_node("%MainMenu") as Control).visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	# 局内菜单组件；“聊天”按钮位于其“菜单”按钮正下方。
	var match_menu: Control = main_instance.get_node("MatchMenu") as Control
	if not match_menu.visible:
		_fail("match_menu_hidden")
		return
	# 局内“聊天”按钮；对离线、房主与客户端都必须存在且不属于权威控件。
	var chat_button: Button = main_instance.get_node_or_null("%MatchChatButton") as Button
	if chat_button == null or chat_button.text != "聊天" or not chat_button.visible:
		_fail("chat_button_missing")
		return
	# 聊天窗口组件；由牌桌在 _ready 阶段创建，默认隐藏。
	var chat_panel: MatchChatPanel = main_instance.get_node_or_null("MatchChatPanel") as MatchChatPanel
	if chat_panel == null or chat_panel.is_open():
		_fail("chat_panel_initial_state")
		return
	chat_button.pressed.emit()
	await get_tree().process_frame
	if not chat_panel.is_open():
		_fail("chat_panel_toggle_open")
		return
	# 通过窗口输入框提交一条真实消息；离线回环立即返回带署名的聊天条目。
	chat_panel._input_field.text = "大家好，出杀！"
	chat_panel._submit_chat_message()
	await get_tree().process_frame
	# 提交后的网关历史；离线署名必须是本机第一视角玩家。
	var match_history: Array[Dictionary] = gateway.get_match_chat_history()
	if match_history.size() != 1 or str(match_history[0].get("message", "")) != "大家好，出杀！" or int(match_history[0].get("sender_player_id", -1)) != match_controller.local_human_player_id:
		_fail("chat_submit_history %s" % str(match_history))
		return
	if not chat_panel._history_view.text.contains("大家好，出杀！") or not chat_panel._input_field.text.is_empty():
		_fail("chat_panel_history_text")
		return
	# 牌桌按玩家 ID 复用的气泡集合；发言后本机玩家头顶必须出现内容一致的可见气泡。
	var chat_bubbles: Dictionary = main_instance.get("_chat_bubbles") as Dictionary
	# 本机发言者的气泡组件；由牌桌在首条消息时创建。
	var local_bubble: ChatBubbleView = chat_bubbles.get(match_controller.local_human_player_id) as ChatBubbleView
	if local_bubble == null or not local_bubble.visible or local_bubble._message_label.text != "大家好，出杀！" or local_bubble.position.y < 0.0:
		_fail("chat_bubble_display")
		return
	# 关闭按钮收起窗口；历史保留在网关中，再次展开可恢复。
	chat_panel._close_button.pressed.emit()
	await get_tree().process_frame
	if chat_panel.is_open():
		_fail("chat_panel_close")
		return
	chat_button.pressed.emit()
	await get_tree().process_frame
	if not chat_panel.is_open() or not chat_panel._history_view.text.contains("大家好，出杀！"):
		_fail("chat_panel_reopen_history")
		return
	print("MATCH_CHAT_PASS 网关标准化、按钮切换、窗口历史与头顶气泡全部通过")
	get_tree().quit(0)


## 网关聊天信号回调；捕获条目供数量断言。
func _on_match_chat_received(chat_entry: Dictionary) -> void:
	_received_chat_entries.append(chat_entry)


## 输出失败标签并以非零状态退出。
func _fail(failure_tag: String) -> void:
	printerr("MATCH_CHAT_FAIL %s" % failure_tag)
	get_tree().quit(1)


## 安装硬超时保护；异步等待异常时测试仍会以失败结束。
func _install_timeout_guard() -> void:
	# 超时计时器；一次性触发，命中即按失败退出。
	var timeout_timer: Timer = Timer.new()
	timeout_timer.one_shot = true
	timeout_timer.wait_time = TEST_TIMEOUT_MILLISECONDS / 1000.0
	timeout_timer.timeout.connect(func() -> void: _fail("timeout"))
	add_child(timeout_timer)
	timeout_timer.start()
