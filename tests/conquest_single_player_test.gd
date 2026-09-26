extends Node

## 过关斩将离线单人回归测试。
## 验证单人游玩恒为“1名本地玩家对1名敌人”，且人数控件的显示文本与数值始终一致；
## 局域网大厅的“玩家数”语义只服务于联机，任何陈旧菜单数值都不得把单人局扩大成多人局。

## 主场景完成节点就绪与延迟布局前等待的帧数；与主菜单回归测试保持一致。
const SETTLE_FRAME_COUNT: int = 6

## 陈旧人数文本；模拟 SpinBox 内部文本行残留的旧数字，读取人数时不得采信该文本。
const STALE_PLAYER_COUNT_TEXT: String = "8"

## 模拟联机大厅语义的陈旧人数入参；离线开局入口收到该值时必须收敛为离线角色总数。
const STALE_REQUESTED_ROLE_COUNT: int = 4

## 测试前下一局模式；结束时恢复，避免污染其他模式的菜单与开局断言。
var _original_match_mode: String = GameSettings.MATCH_MODE_IDENTITY


## 延迟执行以等待自动加载数据库与主场景节点完成就绪。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次验证菜单人数契约、陈旧文本容错与离线开局角色总数；任一失败均以非零状态退出。
func _run() -> void:
	_original_match_mode = str(GameSettings.next_match_mode)
	# 正式主场景资源；测试必须使用玩家实际启动的场景，才覆盖真实菜单与牌桌连接。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main_scene_load")
		return
	# 正式主场景实例；主菜单、局内菜单与控制器在同一节点树中协作。
	var main_instance: Control = main_scene.instantiate() as Control
	add_child(main_instance)
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 主菜单组件；负责把选中模式规范化人数后发出开局请求。
	var main_menu: MainMenu = main_instance.get_node("%MainMenu") as MainMenu
	# 权威控制器；负责按开局入口传入的角色总数创建权威状态。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 主菜单人数控件；显示文本必须与数值同步，否则玩家会按错误数字判断开局人数。
	var player_count_input: SpinBox = main_instance.get_node("%MainMenuPlayerCountInput") as SpinBox
	# 选中过关斩将：离线单人的角色总数为1名玩家加1名敌人，菜单人数固定为该角色总数。
	main_menu.call("_select_conquest_mode")
	await get_tree().process_frame
	if int(player_count_input.value) != GameSettings.OFFLINE_CONQUEST_ROLE_COUNT or player_count_input.get_line_edit().text != str(GameSettings.OFFLINE_CONQUEST_ROLE_COUNT) or main_menu.get_next_player_count() != GameSettings.OFFLINE_CONQUEST_ROLE_COUNT:
		_fail("conquest_menu_count=%d/%s/%d" % [int(player_count_input.value), player_count_input.get_line_edit().text, main_menu.get_next_player_count()])
		return
	# 陈旧文本容错：即使内部文本行被写成旧数字，读取人数仍必须以控件数值为唯一权威。
	player_count_input.get_line_edit().text = STALE_PLAYER_COUNT_TEXT
	if main_menu.get_next_player_count() != GameSettings.OFFLINE_CONQUEST_ROLE_COUNT:
		_fail("conquest_stale_text_read=%d" % main_menu.get_next_player_count())
		return
	# 离线开局入口：即使调用方传入联机语义的陈旧人数，单人局也必须只创建1名玩家与1名敌人。
	if not bool(main_instance.call("_on_restart_requested", STALE_REQUESTED_ROLE_COUNT)):
		_fail("conquest_offline_start_rejected")
		return
	if match_controller.state == null:
		_fail("conquest_offline_state")
		return
	# 实际创建的角色总数；离线过关斩将必须等于离线角色总数常量。
	var started_role_count: int = match_controller.state.players.size()
	# 实际座次身份；偶数座位为红方玩家、奇数座位为蓝方敌人。
	var started_identities: Array[String] = []
	for started_player: PlayerState in match_controller.state.players:
		started_identities.append(started_player.identity)
	# 关卡服务记录的玩家方与敌方稳定 ID；单人局各自只能有1名角色。
	var conquest_player_ids: Array = match_controller.state.conquest_state.get("player_ids", []) as Array
	# 关卡服务记录的敌方稳定 ID；必须与玩家方等量且座次交替。
	var conquest_enemy_ids: Array = match_controller.state.conquest_state.get("enemy_player_ids", []) as Array
	if started_role_count != GameSettings.OFFLINE_CONQUEST_ROLE_COUNT or started_identities != ["red", "blue"] or conquest_player_ids.size() != 1 or int(conquest_player_ids[0]) != 0 or conquest_enemy_ids.size() != 1 or int(conquest_enemy_ids[0]) != 1:
		_fail("conquest_offline_roles=%d/%s/%d/%d" % [started_role_count, started_identities, conquest_player_ids.size(), conquest_enemy_ids.size()])
		return
	# 临时对局只用于本测试断言；释放后恢复全局模式，保证同进程后续测试读取干净状态。
	match_controller.abandon_match()
	GameSettings.set_next_match_mode(_original_match_mode)
	main_instance.queue_free()
	print("CONQUEST_SINGLE_PLAYER_PASS menu_count+stale_text+offline_roles")
	get_tree().quit(0)


## 失败出口；打印稳定标记、恢复全局模式并以非零状态结束测试。
func _fail(reason: String) -> void:
	printerr("CONQUEST_SINGLE_PLAYER_FAIL %s" % reason)
	GameSettings.set_next_match_mode(_original_match_mode)
	get_tree().quit(1)
