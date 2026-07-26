extends Node

## 联机大厅自选身份与1v1车轮战空位回归测试。
## 覆盖：车轮战大厅固定两个位置且拒绝越界换位；自选身份的位置身份表与徽记显示；
## 2v2“上蓝下红”大厅布局到一/四、二/三成队座次的映射；开局按位置身份表固定分配身份。

## 正式主场景资源；测试复用完整节点树，覆盖网关、联机大厅与权威控制器的真实链路。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 测试专用设置文件；隔离写盘避免污染玩家正式 game_settings.cfg。
const TEST_SETTINGS_FILE_PATH: String = "user://lan_custom_identity_test_settings.cfg"

## 测试形象使用的稳定武将 ID；希儿在正式数据库中登记了插画。
const TEST_AVATAR_CHARACTER_ID: String = "xier"

## 身份模式八人局的期望位置身份表；一号位领袖、二三号忠臣、四号内奸、其余四位反贼。
const EXPECTED_IDENTITY_8P: Array[String] = ["leader", "loyalist", "loyalist", "renegade", "rebel", "rebel", "rebel", "rebel"]

## 斗地主五人局的期望位置身份表；一号与三号位地主，其余农民。
const EXPECTED_DOUDIZHU_5P: Array[String] = ["landlord", "peasant", "landlord", "peasant", "peasant"]

## 2v2 大厅位置的期望身份表；上排两位蓝方、下排两位红方。
const EXPECTED_TEAM2V2_LOBBY: Array[String] = ["blue", "blue", "red", "red"]

## 2v2 开局的期望规则座次身份表；一号/四号蓝方同队、二号/三号红方同队。
const EXPECTED_TEAM2V2_MATCH: Array[String] = ["blue", "red", "red", "blue"]

## 测试期间实例化的完整主场景；结束前主动释放并退出 SceneTree。
var _main_instance: Control


## 依次执行规则映射、大厅界面、网关权威与开局身份分配四组校验。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 主流程；任何一步失败都会输出原因并以非零码退出。
func _run() -> void:
	if GameSettings != null:
		GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)
	_main_instance = MAIN_SCENE.instantiate() as Control
	# 阻止主场景自动创建规则对局；后续由测试显式调用 start_match。
	(_main_instance.get_node("MatchController") as MatchController).default_player_count = 1
	get_tree().root.add_child(_main_instance)
	await get_tree().process_frame
	await get_tree().process_frame

	# 身份规则服务；大厅布局与座次映射的唯一权威来源。
	var identity_rules: IdentityRules = IdentityRules.new()
	if not _check_rule_mappings(identity_rules):
		return
	# 联机大厅组件；通过构造快照直接驱动位置渲染，不依赖真实网络。
	var online_lobby_panel: OnlineLobbyPanel = _main_instance.get_node("%OnlineLobbyPanel") as OnlineLobbyPanel
	if not await _check_lobby_seat_rendering(online_lobby_panel):
		return
	# 局域网网关；房主权威换位、设置与开局映射校验。
	var gateway: NetworkGateway = _main_instance.get_node("MatchController/NetworkGateway") as NetworkGateway
	if not _check_gateway_authority(gateway):
		return
	if not _check_match_identity_assignment(gateway):
		return
	gateway.leave_lan("")
	_main_instance.queue_free()
	print("LAN_CUSTOM_IDENTITY_PASS")
	get_tree().quit(0)


## 校验身份规则的模式支持性、位置身份表、座次映射与大厅位置数静态规则。
func _check_rule_mappings(identity_rules: IdentityRules) -> bool:
	if identity_rules.supports_lobby_custom_identity("conquest") or not identity_rules.supports_lobby_custom_identity("identity") or not identity_rules.supports_lobby_custom_identity("doudizhu") or not identity_rules.supports_lobby_custom_identity("team2v2") or not identity_rules.supports_lobby_custom_identity("wheel_duel") or not identity_rules.supports_lobby_custom_identity("opportunity_brawl"):
		return _fail("custom_identity_mode_support")
	if identity_rules.get_lobby_slot_identities("identity", 8) != EXPECTED_IDENTITY_8P:
		return _fail("identity_8p_slot_identities=%s" % str(identity_rules.get_lobby_slot_identities("identity", 8)))
	if identity_rules.get_lobby_slot_identities("doudizhu", 5) != EXPECTED_DOUDIZHU_5P:
		return _fail("doudizhu_5p_slot_identities=%s" % str(identity_rules.get_lobby_slot_identities("doudizhu", 5)))
	if identity_rules.get_lobby_slot_identities("team2v2", 4) != EXPECTED_TEAM2V2_LOBBY:
		return _fail("team2v2_slot_identities=%s" % str(identity_rules.get_lobby_slot_identities("team2v2", 4)))
	if identity_rules.get_lobby_slot_match_seats("team2v2", 4) != IdentityRules.TEAM2V2_LOBBY_SLOT_TO_MATCH_SEAT:
		return _fail("team2v2_slot_match_seats=%s" % str(identity_rules.get_lobby_slot_match_seats("team2v2", 4)))
	if identity_rules.get_lobby_slot_match_seats("identity", 8) != [0, 1, 2, 3, 4, 5, 6, 7]:
		return _fail("identity_slot_match_seats")
	# 大厅视觉位置数静态规则；车轮战固定2位、自选身份等于规则人数、其余保持2至3人3位设计。
	if NetworkGateway.get_lobby_display_slot_count_for("wheel_duel", 2, false) != 2 or NetworkGateway.get_lobby_display_slot_count_for("identity", 2, false) != 3 or NetworkGateway.get_lobby_display_slot_count_for("identity", 2, true) != 2 or NetworkGateway.get_lobby_display_slot_count_for("identity", 8, true) != 8 or NetworkGateway.get_lobby_display_slot_count_for("conquest", 2, true) != 3:
		return _fail("display_slot_count_rule")
	return true


## 用构造快照驱动大厅位置渲染；校验车轮战两位布局与各模式身份徽记。
func _check_lobby_seat_rendering(online_lobby_panel: OnlineLobbyPanel) -> bool:
	# 车轮战2人快照；未开启自选身份也只允许两个视觉位置。
	online_lobby_panel.bind_lobby(_make_lobby_snapshot("wheel_duel", 2, false))
	await get_tree().process_frame
	# 车轮战当前位置组件；数量必须为2且不显示身份徽记。
	var wheel_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if wheel_seats.size() != 2 or wheel_seats[0].get_identity_id() != "" or wheel_seats[1].get_identity_id() != "":
		return _fail("wheel_duel_slot_count=%d" % wheel_seats.size())
	# 车轮战开启自选身份；一号位红方先手、二号位蓝方后手。
	online_lobby_panel.bind_lobby(_make_lobby_snapshot("wheel_duel", 2, true))
	await get_tree().process_frame
	wheel_seats = _get_seat_views(online_lobby_panel)
	if wheel_seats.size() != 2 or wheel_seats[0].get_identity_id() != "red" or wheel_seats[1].get_identity_id() != "blue":
		return _fail("wheel_duel_custom_identity_badges")
	# 身份模式八人自选身份快照；每个位置右上角徽记按固定身份表显示。
	online_lobby_panel.bind_lobby(_make_lobby_snapshot("identity", 8, true))
	await get_tree().process_frame
	# 身份局当前位置组件；数量与身份表一一对应。
	var identity_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if identity_seats.size() != 8:
		return _fail("identity_8p_slot_count=%d" % identity_seats.size())
	for slot_index: int in range(8):
		# 当前座位身份徽记标签；必须可见且文案与身份表匹配。
		var badge_label: Label = identity_seats[slot_index].get_node("%OnlineLobbyIdentityBadge") as Label
		if identity_seats[slot_index].get_identity_id() != EXPECTED_IDENTITY_8P[slot_index] or badge_label == null or not badge_label.visible:
			return _fail("identity_8p_badge slot=%d identity=%s" % [slot_index, identity_seats[slot_index].get_identity_id()])
	# 一号位徽记文案；领袖必须显示为中文文案而不是稳定 ID。
	if (identity_seats[0].get_node("%OnlineLobbyIdentityBadge") as Label).text != "领袖":
		return _fail("identity_leader_badge_text")
	# 未开启自选身份的八人快照；所有位置隐藏徽记。
	online_lobby_panel.bind_lobby(_make_lobby_snapshot("identity", 8, false))
	await get_tree().process_frame
	identity_seats = _get_seat_views(online_lobby_panel)
	if identity_seats.size() != 8 or identity_seats[0].get_identity_id() != "" or (identity_seats[0].get_node("%OnlineLobbyIdentityBadge") as Label).visible:
		return _fail("identity_8p_badges_hidden")
	# 2v2 自选身份快照；上排两位蓝方、下排两位红方。
	online_lobby_panel.bind_lobby(_make_lobby_snapshot("team2v2", 4, true))
	await get_tree().process_frame
	# 2v2 当前位置组件；身份布局与大厅专属表一致。
	var team_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if team_seats.size() != 4:
		return _fail("team2v2_slot_count=%d" % team_seats.size())
	for slot_index: int in range(4):
		if team_seats[slot_index].get_identity_id() != EXPECTED_TEAM2V2_LOBBY[slot_index]:
			return _fail("team2v2_badge slot=%d identity=%s" % [slot_index, team_seats[slot_index].get_identity_id()])
	# 斗地主五人自选身份快照；一号与三号位显示地主。
	online_lobby_panel.bind_lobby(_make_lobby_snapshot("doudizhu", 5, true))
	await get_tree().process_frame
	# 斗地主当前位置组件；身份布局与固定身份表一致。
	var doudizhu_seats: Array[OnlineLobbyAvatar] = _get_seat_views(online_lobby_panel)
	if doudizhu_seats.size() != 5:
		return _fail("doudizhu_slot_count=%d" % doudizhu_seats.size())
	for slot_index: int in range(5):
		if doudizhu_seats[slot_index].get_identity_id() != EXPECTED_DOUDIZHU_5P[slot_index]:
			return _fail("doudizhu_badge slot=%d identity=%s" % [slot_index, doudizhu_seats[slot_index].get_identity_id()])
	online_lobby_panel.visible = false
	return true


## 校验网关权威行为：车轮战拒绝越界换位、自选身份开关规范化与开局座次映射。
func _check_gateway_authority(gateway: NetworkGateway) -> bool:
	# 测试端口；按进程 ID 选择非保留高位端口，减少并行执行时的占用冲突。
	var test_port: int = 39000 + ((OS.get_process_id() + 137) % 9000)
	if gateway.host_lan("身份测试房主", test_port, TEST_AVATAR_CHARACTER_ID, "", 2, "wheel_duel") != OK:
		return _fail("host_lan_error")
	# 车轮战房主快照；自选身份默认关闭且只允许两个位置。
	if bool(gateway.get_lan_lobby_snapshot().get("custom_identity_enabled", true)):
		return _fail("wheel_duel_custom_identity_default")
	# 越界换位请求；车轮战没有第三个视觉位置，房主必须保持在原位置。
	gateway.request_lan_lobby_seat_change(2)
	if int((gateway.get_lan_lobby_snapshot().get("members", []) as Array)[0].get("seat_index", -1)) != 0:
		return _fail("wheel_duel_seat_overflow_accepted")
	# 合法换位请求；二号位仍在两位范围内，房主应成功移动后归位。
	gateway.request_lan_lobby_seat_change(1)
	if int((gateway.get_lan_lobby_snapshot().get("members", []) as Array)[0].get("seat_index", -1)) != 1:
		return _fail("wheel_duel_seat_change_rejected")
	gateway.request_lan_lobby_seat_change(0)
	# 自选身份开关更新；身份模式八人开启后快照必须广播该标志。
	if not gateway.update_lan_lobby_settings("identity", 8, "", true).is_empty() or not gateway.is_lan_custom_identity_enabled() or not bool(gateway.get_lan_lobby_snapshot().get("custom_identity_enabled", false)):
		return _fail("identity_custom_identity_toggle")
	# 过关斩将不支持自选身份；即使请求开启也必须规范化为关闭。
	if not gateway.update_lan_lobby_settings("conquest", 2, "", true).is_empty() or gateway.is_lan_custom_identity_enabled():
		return _fail("conquest_custom_identity_not_normalized")
	if not gateway.update_lan_lobby_settings("identity", 8, "", true).is_empty():
		return _fail("identity_custom_identity_reenable")
	# 模拟一名已登记的远端成员占据八号位；自选身份下开局映射必须按位置直接绑定规则座次。
	gateway.set("_lobby_members", _with_fake_member(gateway, 7))
	if not gateway.prepare_lan_match_assignments(8).is_empty():
		return _fail("identity_prepare_error")
	if gateway.get_local_lan_player_id() != 0 or gateway.get_peer_id_for_player(7) != 99:
		return _fail("identity_seat_binding local=%d" % gateway.get_local_lan_player_id())
	gateway.cancel_prepared_lan_match()
	# 2v2 自选身份映射；大厅三号位（下排红方首位）必须绑定规则二号位。
	if not gateway.update_lan_lobby_settings("team2v2", 4, "", true).is_empty():
		return _fail("team2v2_settings_error")
	gateway.set("_lobby_members", _with_fake_member(gateway, 2))
	if not gateway.prepare_lan_match_assignments(4).is_empty():
		return _fail("team2v2_prepare_error")
	if gateway.get_local_lan_player_id() != 0 or gateway.get_peer_id_for_player(1) != 99:
		return _fail("team2v2_seat_binding local=%d" % gateway.get_local_lan_player_id())
	gateway.cancel_prepared_lan_match()
	# 移除模拟远端成员；后续设置广播只面向真实连接，避免向不存在的 peer 发送 RPC 的报错噪声。
	var host_only_members: Dictionary = (gateway.get("_lobby_members") as Dictionary).duplicate(true)
	host_only_members.erase(99)
	gateway.set("_lobby_members", host_only_members)
	return true


## 校验房主开局后的身份分配：自选身份锁定后按位置身份表固定分配，不再洗牌或蓝红互换。
func _check_match_identity_assignment(gateway: NetworkGateway) -> bool:
	# 权威控制器；直接读取开局后的玩家身份与本局锁定选项。
	var match_controller: MatchController = _main_instance.get_node("MatchController") as MatchController
	if not gateway.update_lan_lobby_settings("identity", 8, "", true).is_empty():
		return _fail("match_identity_settings_error")
	if not match_controller.start_match(8, 20260727, "identity"):
		return _fail("identity_match_start_failed")
	if not bool(match_controller.state.match_options.get("lan_custom_identity_enabled", false)):
		return _fail("identity_match_option_missing")
	if _identities_by_player_id(match_controller) != EXPECTED_IDENTITY_8P:
		return _fail("identity_match_identities=%s" % str(_identities_by_player_id(match_controller)))
	# 斗地主自选身份开局；一号与三号位固定地主且身份全部明置。
	if not gateway.update_lan_lobby_settings("doudizhu", 5, "", true).is_empty():
		return _fail("doudizhu_settings_error")
	if not match_controller.start_match(5, 20260728, "doudizhu"):
		return _fail("doudizhu_match_start_failed")
	if _identities_by_player_id(match_controller) != EXPECTED_DOUDIZHU_5P:
		return _fail("doudizhu_match_identities=%s" % str(_identities_by_player_id(match_controller)))
	# 2v2 自选身份开局；保持基准蓝红成队表，不做50%互换。
	if not gateway.update_lan_lobby_settings("team2v2", 4, "", true).is_empty():
		return _fail("team2v2_match_settings_error")
	if not match_controller.start_match(4, 20260729, "team2v2"):
		return _fail("team2v2_match_start_failed")
	if _identities_by_player_id(match_controller) != EXPECTED_TEAM2V2_MATCH:
		return _fail("team2v2_match_identities=%s" % str(_identities_by_player_id(match_controller)))
	return true


## 构造仅含房主一名成员的公共大厅快照；直接驱动大厅界面渲染，不经过网络。
func _make_lobby_snapshot(game_mode_id: String, player_count: int, custom_identity_enabled: bool) -> Dictionary:
	return {
		"role":"host",
		"local_peer_id":1,
		"members":[{
			"peer_id":1,
			"display_name":"身份测试房主",
			"avatar_character_id":TEST_AVATAR_CHARACTER_ID,
			"is_host":true,
			"join_order":0,
			"seat_index":0,
		}],
		"member_count":1,
		"match_active":false,
		"player_count":player_count,
		"game_mode_id":game_mode_id,
		"custom_identity_enabled":custom_identity_enabled,
		"has_password":false,
		"chat_history":[],
	}


## 返回在网关现有成员表上追加一名固定 peer 99 远端成员的副本；seat_index 为其大厅位置。
func _with_fake_member(gateway: NetworkGateway, seat_index: int) -> Dictionary:
	# 现有成员表副本；保留房主成员并写入指定位置的远端成员。
	var members: Dictionary = (gateway.get("_lobby_members") as Dictionary).duplicate(true)
	members[99] = {
		"peer_id":99,
		"display_name":"远端测试玩家",
		"avatar_character_id":TEST_AVATAR_CHARACTER_ID,
		"is_host":false,
		"join_order":1,
		"seat_index":seat_index,
	}
	return members


## 按稳定玩家 ID 升序返回当前对局身份表；开局座次旋转不影响该顺序。
func _identities_by_player_id(match_controller: MatchController) -> Array[String]:
	# 身份结果；索引即稳定玩家 ID。
	var identities: Array[String] = []
	identities.resize(match_controller.state.players.size())
	for player: PlayerState in match_controller.state.players:
		identities[player.player_id] = player.identity
	return identities


## 收集大厅座位区中的全部形象组件；顺序即位置索引创建顺序。
func _get_seat_views(online_lobby_panel: OnlineLobbyPanel) -> Array[OnlineLobbyAvatar]:
	# 座位区域；只有 OnlineLobbyAvatar 动态子节点。
	var seat_area: Control = online_lobby_panel.get_node("%OnlineLobbySeatArea") as Control
	# 类型化位置数组；测试可直接读取稳定索引与身份。
	var seat_views: Array[OnlineLobbyAvatar] = []
	for child: Node in seat_area.get_children():
		if child is OnlineLobbyAvatar:
			seat_views.append(child as OnlineLobbyAvatar)
	return seat_views


## 输出失败原因并释放网络与场景资源；返回 false 便于调用方直接短路。
func _fail(reason: String) -> bool:
	printerr("LAN_CUSTOM_IDENTITY_FAIL %s" % reason)
	if _main_instance != null and is_instance_valid(_main_instance):
		# 测试网关；仅在已经创建房间时释放端口，离线调用保持幂等。
		var gateway: NetworkGateway = _main_instance.get_node_or_null("MatchController/NetworkGateway") as NetworkGateway
		if gateway != null:
			gateway.leave_lan("")
		_main_instance.queue_free()
	get_tree().quit(1)
	return false
