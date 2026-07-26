extends Node

## 对局回放功能回归测试。验证回放录制器的临时流式写入、自定义命名保存与重复保存复用；
## 回放存储层的保存、枚举、读取、重命名、顶置排序、导出、导入、损坏拒绝与删除；
## 64位整数在二进制变体序列化下的无损往返；结算面板“保存回放”命名弹窗的信号契约；
## 回放内容页的列表、重命名、顶置与播放意图；重演驱动器的顺序派发；
## 以及牌桌以第一视角整局重演真实录制回放并退出返回回放列表的完整流程。

## 结算面板场景；验证“保存回放”按钮打开命名弹窗并发出带自定义名的保存意图。
const GAME_SETTLEMENT_PANEL_SCENE: PackedScene = preload("res://scenes/components/game_settlement_panel.tscn")

## 对局回放内容页场景；验证列表、重命名、顶置与播放意图信号。
const MATCH_REPLAY_PANEL_SCENE: PackedScene = preload("res://scenes/components/match_replay_panel.tscn")

## 正式主场景；牌桌重演流程必须在真实组件树上验证。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 测试专用回放目录；绝不读写正式回放目录，避免污染本机玩家已保存的回放。
const TEST_REPLAY_DIRECTORY: String = "user://replay_test_dir"

## 测试专用录制临时文件路径；位于测试目录内，结束时随目录一并清理。
const TEST_TEMP_RECORDING_PATH: String = "user://replay_test_dir/recording.tmp"

## 测试专用导出目标路径；位于回放目录之外，验证导出字节复制与再导入闭环，结束时单独清理。
const TEST_EXPORT_PATH: String = "user://replay_test_exported.lisbam_replay"

## 大于2^53的64位整数样例；验证 store_var 二进制格式在回放步骤流中完整保留整数精度。
const LARGE_UID_SAMPLE: int = 6917529027641081855

## 测试硬超时毫秒数；异步流程异常挂起时保证进程按失败退出而不是永久悬挂。
const TEST_TIMEOUT_MILLISECONDS: int = 30000

## 结算面板命名弹窗确认后收到的自定义名；未收到信号时保持哨兵值。
var _received_save_custom_name: String = "__unset__"

## 回放内容页“播放”发出的文件名；未收到信号时保持空字符串。
var _received_playback_file_name: String = ""

## 重演驱动器派发的快照数量；顺序断言使用。
var _driver_snapshot_count: int = 0

## 重演驱动器派发的日志正文列表；顺序断言使用。
var _driver_log_messages: Array[String] = []

## 重演驱动器派发的表现步骤数量；目标线步骤派发断言使用。
var _driver_presentation_count: int = 0

## 重演驱动器是否已发出播放完毕信号。
var _driver_finished: bool = false


## 延迟执行以等待自动加载数据库完成索引；组件实例化依赖主题与数据库单例。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次运行录制器、存储层、结算命名弹窗、内容页、驱动器与牌桌重演断言；任意失败清理测试文件并以非零状态退出。
func _run() -> void:
	_install_timeout_guard()
	_cleanup_test_files()
	# 回放录制器；使用测试目录内的独立临时文件。
	var recorder: MatchReplayRecorder = MatchReplayRecorder.new(TEST_TEMP_RECORDING_PATH)
	if not recorder.begin_recording("test-match-1", 0):
		_fail(recorder, "begin_recording")
		return
	recorder.record_snapshot(_build_test_snapshot(4, 4))
	recorder.record_log("测试日志一")
	recorder.record_log("测试日志二")
	recorder.record_presentation({"e":"activation", "player_id":0, "name":"测试技", "target_ids":[1]})
	recorder.record_snapshot(_build_test_snapshot(2, 4))
	# 首次保存结果文件名；使用玩家自定义名，应直接生成同名 .lisbam_replay 文件。
	var saved_file_name: String = recorder.save_recording(TEST_REPLAY_DIRECTORY, "我的精彩对局")
	if saved_file_name != "我的精彩对局.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION:
		_fail(recorder, "save_recording_custom_name name=%s" % saved_file_name)
		return
	# 重复保存结果；同一局必须复用首次文件而不是生成第二份，即使传入不同名称。
	var repeated_file_name: String = recorder.save_recording(TEST_REPLAY_DIRECTORY, "另一个名字")
	if repeated_file_name != saved_file_name or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 1:
		_fail(recorder, "save_recording_idempotent")
		return
	# 保存后继续录制的步骤；验证保存不中断录制流。
	recorder.record_log("保存之后的日志")
	# 列表首个条目；检查回放头的统计与元数据字段。
	var listed_entry: Dictionary = MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY)[0]
	# 列表条目的回放头；保存时快照统计为2份快照与2条日志。
	var header: Dictionary = listed_entry.get("header", {}) as Dictionary
	if str(listed_entry.get("file_name", "")) != saved_file_name or bool(listed_entry.get("pinned", true)) or int(header.get("player_count", 0)) != 2 or int(header.get("snapshot_count", 0)) != 2 or int(header.get("log_count", 0)) != 2 or int(header.get("presentation_count", -1)) != 1 or int(header.get("step_count", 0)) != 5 or str(header.get("match_mode", "")) != "identity" or int(header.get("viewer_player_id", -1)) != 0 or bool(header.get("truncated", true)):
		_fail(recorder, "replay_header %s" % str(header))
		return
	# 回放完整路径；供读取与导出断言复用。
	var replay_path: String = "%s/%s" % [TEST_REPLAY_DIRECTORY, saved_file_name]
	# 读取的全部步骤；顺序必须与录制一致：快照、日志、日志、表现、快照。
	var steps: Array[Dictionary] = MatchReplayStore.read_replay_steps(replay_path)
	if steps.size() != 5 or str(steps[0].get("k", "")) != MatchReplayRecorder.STEP_KIND_SNAPSHOT or str(steps[1].get("k", "")) != MatchReplayRecorder.STEP_KIND_LOG or str(steps[2].get("k", "")) != MatchReplayRecorder.STEP_KIND_LOG or str(steps[3].get("k", "")) != MatchReplayRecorder.STEP_KIND_PRESENTATION or str(steps[4].get("k", "")) != MatchReplayRecorder.STEP_KIND_SNAPSHOT:
		_fail(recorder, "replay_steps size=%d" % steps.size())
		return
	# 表现步骤数据往返；稳定玩家 ID 与名称必须原样保留供重演端解析。
	var presentation_step: Dictionary = steps[3].get("d", {}) as Dictionary
	if str(presentation_step.get("e", "")) != "activation" or int(presentation_step.get("player_id", -1)) != 0 or str(presentation_step.get("name", "")) != "测试技" or int((presentation_step.get("target_ids", []) as Array)[0]) != 1:
		_fail(recorder, "presentation_step_roundtrip %s" % str(presentation_step))
		return
	# 第一份快照步骤数据；验证64位整数与嵌套结构无损往返。
	var first_snapshot: Dictionary = steps[0].get("d", {}) as Dictionary
	if int(first_snapshot.get("uid_sample", 0)) != LARGE_UID_SAMPLE or str(steps[1].get("d", "")) != "测试日志一":
		_fail(recorder, "replay_step_precision")
		return
	if not MatchReplayStore.export_replay(saved_file_name, TEST_EXPORT_PATH, TEST_REPLAY_DIRECTORY):
		_fail(recorder, "export_replay")
		return
	# 导入结果文件名；从导出文件再导入应生成不覆盖原回放的新条目。
	var imported_file_name: String = MatchReplayStore.import_replay(TEST_EXPORT_PATH, TEST_REPLAY_DIRECTORY)
	if imported_file_name.is_empty() or imported_file_name == saved_file_name or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 2:
		_fail(recorder, "import_replay name=%s" % imported_file_name)
		return
	# 重命名导入回放；应生成新文件名并保持列表数量不变。
	var renamed_file_name: String = MatchReplayStore.rename_replay(imported_file_name, "改名后的回放", TEST_REPLAY_DIRECTORY)
	if renamed_file_name != "改名后的回放.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 2 or FileAccess.file_exists("%s/%s" % [TEST_REPLAY_DIRECTORY, imported_file_name]):
		_fail(recorder, "rename_replay name=%s" % renamed_file_name)
		return
	# 与既有回放重名的重命名；应自动追加序号而不是覆盖首份回放。
	var conflicted_file_name: String = MatchReplayStore.rename_replay(renamed_file_name, "我的精彩对局", TEST_REPLAY_DIRECTORY)
	if conflicted_file_name != "我的精彩对局_2.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 2:
		_fail(recorder, "rename_replay_conflict name=%s" % conflicted_file_name)
		return
	# 顶置第二份回放；顶置条目必须排到列表首位并带顶置标记。
	if not MatchReplayStore.set_replay_pinned(conflicted_file_name, true, TEST_REPLAY_DIRECTORY):
		_fail(recorder, "set_replay_pinned")
		return
	# 顶置后的列表；首位应为顶置条目，第二位保持未顶置。
	var pinned_entries: Array[Dictionary] = MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY)
	if str(pinned_entries[0].get("file_name", "")) != conflicted_file_name or not bool(pinned_entries[0].get("pinned", false)) or bool(pinned_entries[1].get("pinned", true)):
		_fail(recorder, "pinned_sort %s" % str(pinned_entries))
		return
	# 顶置状态在重命名后迁移；改回原名并确认顶置仍在。
	var pin_migrated_name: String = MatchReplayStore.rename_replay(conflicted_file_name, "顶置迁移", TEST_REPLAY_DIRECTORY)
	if pin_migrated_name.is_empty() or not MatchReplayStore.is_replay_pinned(pin_migrated_name, TEST_REPLAY_DIRECTORY) or MatchReplayStore.is_replay_pinned(conflicted_file_name, TEST_REPLAY_DIRECTORY):
		_fail(recorder, "pin_migration name=%s" % pin_migrated_name)
		return
	# 损坏文件路径；写入无关文本后导入必须被拒绝。
	var corrupted_path: String = "%s/corrupted.lisbam_replay" % TEST_REPLAY_DIRECTORY
	var corrupted_file: FileAccess = FileAccess.open(corrupted_path, FileAccess.WRITE)
	corrupted_file.store_string("这不是回放文件")
	corrupted_file.close()
	if not MatchReplayStore.import_replay(corrupted_path, TEST_REPLAY_DIRECTORY).is_empty() or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 2:
		_fail(recorder, "corrupted_import_rejected")
		return
	# 删除顶置回放；文件删除后顶置元数据同步清理。
	if not MatchReplayStore.delete_replay(pin_migrated_name, TEST_REPLAY_DIRECTORY) or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 1 or MatchReplayStore.is_replay_pinned(pin_migrated_name, TEST_REPLAY_DIRECTORY):
		_fail(recorder, "delete_replay")
		return
	recorder.discard_recording()
	if FileAccess.file_exists(TEST_TEMP_RECORDING_PATH):
		_fail(recorder, "discard_recording_cleanup")
		return
	# 结算面板实例；验证“保存回放”按钮打开命名弹窗并发出带自定义名的信号。
	var settlement_panel: GameSettlementPanel = GAME_SETTLEMENT_PANEL_SCENE.instantiate() as GameSettlementPanel
	add_child(settlement_panel)
	await get_tree().process_frame
	settlement_panel.save_replay_requested.connect(func(custom_name: String) -> void: _received_save_custom_name = custom_name)
	settlement_panel.show_settlement(_build_test_snapshot(3, 4))
	# 结算面板中的保存回放按钮；缺失说明场景未同步。
	var save_replay_button: Button = settlement_panel.get_node_or_null("%SaveReplayButton") as Button
	if save_replay_button == null or save_replay_button.text != "保存回放":
		_fail(null, "settlement_save_button")
		return
	save_replay_button.pressed.emit()
	await get_tree().process_frame
	# 点击保存后必须先出现命名弹窗，而不是立即发出保存信号。
	if not settlement_panel._naming_panel.visible or _received_save_custom_name != "__unset__":
		_fail(null, "settlement_naming_modal")
		return
	settlement_panel._naming_input.text = "结算命名回放"
	settlement_panel._naming_confirm_button.pressed.emit()
	await get_tree().process_frame
	if _received_save_custom_name != "结算命名回放" or settlement_panel._naming_panel.visible:
		_fail(null, "settlement_save_signal name=%s" % _received_save_custom_name)
		return
	# 再次打开弹窗并留空确认；应发出空名称表示按默认名保存。
	save_replay_button.pressed.emit()
	await get_tree().process_frame
	settlement_panel._naming_confirm_button.pressed.emit()
	await get_tree().process_frame
	if _received_save_custom_name != "":
		_fail(null, "settlement_save_default_name")
		return
	settlement_panel.queue_free()
	# 回放内容页实例；指向测试目录后打开应列出剩余的1份回放。
	var replay_panel: MatchReplayPanel = MATCH_REPLAY_PANEL_SCENE.instantiate() as MatchReplayPanel
	add_child(replay_panel)
	await get_tree().process_frame
	replay_panel.replay_directory_override = TEST_REPLAY_DIRECTORY
	replay_panel.playback_requested.connect(func(file_name: String) -> void: _received_playback_file_name = file_name)
	replay_panel.open_panel()
	await get_tree().process_frame
	if replay_panel._list_container.get_child_count() != 1 or not replay_panel._play_button.disabled or not replay_panel._rename_button.disabled or not replay_panel._pin_button.disabled:
		_fail(null, "replay_panel_list count=%d" % replay_panel._list_container.get_child_count())
		return
	(replay_panel._list_container.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	if replay_panel._play_button.disabled or not replay_panel._detail_body_label.text.contains("身份模式"):
		_fail(null, "replay_panel_selection")
		return
	# 内容页重命名闭环；模态按重命名语义预填基础名，确认后条目与选中态跟随新名。
	replay_panel._rename_button.pressed.emit()
	await get_tree().process_frame
	if not replay_panel._modal_panel.visible or replay_panel._modal_mode != "rename" or replay_panel._modal_path_input.text != "我的精彩对局":
		_fail(null, "replay_panel_rename_modal mode=%s" % replay_panel._modal_mode)
		return
	replay_panel._modal_path_input.text = "页内改名"
	replay_panel._on_modal_confirm_pressed()
	await get_tree().process_frame
	if str(replay_panel._selected_entry.get("file_name", "")) != "页内改名.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION or replay_panel._play_button.disabled:
		_fail(null, "replay_panel_rename_result %s" % str(replay_panel._selected_entry.get("file_name", "")))
		return
	# 内容页顶置切换；按钮文字随选中条目顶置状态变化，列表条目带星号前缀。
	replay_panel._pin_button.pressed.emit()
	await get_tree().process_frame
	if not bool(replay_panel._selected_entry.get("pinned", false)) or replay_panel._pin_button.text != "取消顶置" or not (replay_panel._list_container.get_child(0) as Button).text.begins_with(MatchReplayPanel.PINNED_ENTRY_PREFIX):
		_fail(null, "replay_panel_pin_toggle")
		return
	replay_panel._pin_button.pressed.emit()
	await get_tree().process_frame
	if bool(replay_panel._selected_entry.get("pinned", true)) or replay_panel._pin_button.text != "顶置回放":
		_fail(null, "replay_panel_unpin_toggle")
		return
	# “播放”按钮只发出播放意图；实际重演由牌桌执行，内容页不再内置迷你播放器。
	replay_panel._play_button.pressed.emit()
	await get_tree().process_frame
	if _received_playback_file_name != "页内改名.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION:
		_fail(null, "replay_panel_playback_signal name=%s" % _received_playback_file_name)
		return
	replay_panel.queue_free()
	# 重演驱动器顺序派发；载入刚才的回放步骤并断言快照与日志按录制顺序送出。
	var playback_driver: MatchReplayPlaybackDriver = MatchReplayPlaybackDriver.new()
	add_child(playback_driver)
	playback_driver.snapshot_step_ready.connect(func(_snapshot: Dictionary) -> void: _driver_snapshot_count += 1)
	playback_driver.log_step_ready.connect(func(message: String) -> void: _driver_log_messages.append(message))
	playback_driver.presentation_step_ready.connect(func(_presentation: Dictionary) -> void: _driver_presentation_count += 1)
	playback_driver.playback_finished.connect(func() -> void: _driver_finished = true)
	# 驱动器测试步骤；读取重命名后的回放文件。
	var driver_steps: Array[Dictionary] = MatchReplayStore.read_replay_steps("%s/%s" % [TEST_REPLAY_DIRECTORY, "页内改名.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION])
	if not playback_driver.start_playback(driver_steps) or _driver_snapshot_count != 1:
		_fail(null, "driver_start snapshots=%d" % _driver_snapshot_count)
		return
	# 手动推进10秒；间隔按2000毫秒上限截断，足以派发剩余全部步骤并触发完成信号。
	playback_driver._process(10.0)
	if _driver_snapshot_count != 2 or _driver_log_messages != ["测试日志一", "测试日志二"] or _driver_presentation_count != 1 or not _driver_finished or playback_driver.is_playing():
		_fail(null, "driver_dispatch snapshots=%d logs=%s presentations=%d" % [_driver_snapshot_count, str(_driver_log_messages), _driver_presentation_count])
		return
	playback_driver.queue_free()
	# 牌桌整局重演流程；使用真实离线对局录制一份回放，再以第一视角在正式牌桌上重演。
	await _run_table_replay_flow()


## 在正式主场景中录制一段真实对局并完整重演；覆盖输入封锁、菜单隐藏、播放完毕与退出返回列表。
func _run_table_replay_flow() -> void:
	# 正式主场景实例；重演流程全部挂在牌桌根节点之下。
	var main_instance: Control = MAIN_SCENE.instantiate() as Control
	add_child(main_instance)
	for _frame_index: int in range(6):
		await get_tree().process_frame
	# 权威控制器；离线开局产生真实观察者快照供录制。
	var match_controller: MatchController = main_instance.get_node("MatchController") as MatchController
	# 显式传入人数、种子与模式开局；不依赖本机保存的下一局设置。
	if not match_controller.start_match(2, 7, "identity"):
		_fail(null, "table_replay_match_start")
		return
	(main_instance.get_node("%MainMenu") as Control).visible = false
	for _frame_index: int in range(4):
		await get_tree().process_frame
	# 牌桌回放录制器；开局后已经自动录到真实快照，保存为测试目录内的命名回放。
	var table_recorder: MatchReplayRecorder = main_instance.get("_match_replay_recorder") as MatchReplayRecorder
	# 录制保存结果；至少包含一份选将阶段快照。
	var table_saved_name: String = table_recorder.save_recording(TEST_REPLAY_DIRECTORY, "重演测试")
	if table_saved_name != "重演测试.%s" % MatchReplayStore.REPLAY_FILE_EXTENSION:
		_fail(null, "table_replay_save name=%s" % table_saved_name)
		return
	# 返回主菜单结束当前对局；重演必须在无权威对局状态下运行。
	main_instance.call("_on_main_menu_requested")
	await get_tree().process_frame
	# 记录重演前的第一视角玩家 ID；退出回放后必须恢复。
	var previous_local_player_id: int = match_controller.local_human_player_id
	# 保存回放的回放头；重演视角必须与录制端视角玩家一致。
	var table_saved_header: Dictionary = MatchReplayStore.read_replay_header("%s/%s" % [TEST_REPLAY_DIRECTORY, table_saved_name])
	main_instance.set("replay_playback_directory_override", TEST_REPLAY_DIRECTORY)
	main_instance.call("_on_replay_playback_requested", table_saved_name)
	await get_tree().process_frame
	# 主菜单与局内菜单在重演期间必须同时隐藏；覆盖层展开并封锁桌面输入。
	var main_menu: Control = main_instance.get_node("%MainMenu") as Control
	var match_menu: Control = main_instance.get_node("MatchMenu") as Control
	# 重演覆盖层；由牌桌惰性创建。
	var replay_overlay: MatchReplayOverlay = main_instance.get_node_or_null("MatchReplayOverlay") as MatchReplayOverlay
	if not bool(main_instance.get("_replay_session_active")) or main_menu.visible or match_menu.visible or replay_overlay == null or not replay_overlay.is_open() or int(match_controller.local_human_player_id) != int(table_saved_header.get("viewer_player_id", -99)):
		_fail(null, "table_replay_session_state")
		return
	# 等待驱动器按录制节奏派发完全部步骤；真实录制间隔极短，数帧内应播放完毕。
	for _frame_index: int in range(30):
		await get_tree().process_frame
		if replay_overlay._title_label.text.contains("已播放完毕"):
			break
	if not replay_overlay._title_label.text.contains("已播放完毕"):
		_fail(null, "table_replay_finish title=%s" % replay_overlay._title_label.text)
		return
	# 重演期间不产生新的回放录制；录制器保持非活动状态。
	if table_recorder.is_recording():
		_fail(null, "table_replay_no_rerecord")
		return
	# 重演表现步骤；技能发动应创建名称提示标签并在动画层登记动态目标线。
	var animation_layer: Node = main_instance.get("card_use_animation_layer") as Node
	# 回放头玩家表；表现步骤使用真实录制的稳定玩家 ID 解析重演座位。
	var header_players: Array = table_saved_header.get("players", []) as Array
	var first_player_id: int = int((header_players[0] as Dictionary).get("player_id", 0))
	var second_player_id: int = int((header_players[1] as Dictionary).get("player_id", 1))
	main_instance.call("_on_replay_presentation_step", {"e":"activation", "player_id":first_player_id, "name":"回放技", "target_ids":[second_player_id]})
	if (animation_layer.get("_line_presentations") as Dictionary).size() < 1 or main_instance.get_node_or_null("SkillActivation_%d" % first_player_id) == null:
		_fail(null, "replay_presentation_activation")
		return
	# 重演卡牌使用表现；完整表现数据经正式入口复刻中央飞牌与目标线，动画层新增一张展示牌面与一条线。
	if GameDatabase.get_card("sha").is_empty():
		_fail(null, "replay_presentation_card_definition")
		return
	# 注入前动画层子节点数；卡牌使用与移牌重演各应新增一个正式 CardView 节点。
	var layer_child_count_before: int = animation_layer.get_child_count()
	main_instance.call("_on_replay_presentation_step", {"e":"card_presentation", "data":{
		"event_name":"useCard",
		"presentation_id":700001,
		"owns_discard_transfer":false,
		"actor_id":first_player_id,
		"target_ids":[second_player_id],
		"indicator_stages":[],
		"card_data":{"uid":700990, "definition_id":"sha", "suit":"spade", "number":7},
	}})
	if animation_layer.get_child_count() != layer_child_count_before + 1 or (animation_layer.get("_line_presentations") as Dictionary).size() < 2:
		_fail(null, "replay_presentation_card_flight children=%d" % animation_layer.get_child_count())
		return
	# 重演移牌表现；牌堆到远端玩家手牌的转移经正式入口创建一张牌背转移节点（本机获得走手牌入场不加节点）。
	var viewer_id: int = int(table_saved_header.get("viewer_player_id", -1))
	# 非本机视角的目标玩家；保证转移动画分支创建可断言的牌背节点。
	var remote_player_id: int = second_player_id if viewer_id == first_player_id else first_player_id
	main_instance.call("_on_replay_presentation_step", {"e":"card_transfer", "card_data":{"uid":700991, "definition_id":""}, "source_player_id":-1, "source_zone":"draw_pile", "target_player_id":remote_player_id, "target_zone":"hand"})
	if animation_layer.get_child_count() != layer_child_count_before + 2:
		_fail(null, "replay_transfer_flight children=%d" % animation_layer.get_child_count())
		return
	# 控制条可拖动；模拟按住条体空白区域拖动固定位移，位置应精确跟随且不被中途钳制。
	var control_bar: PanelContainer = replay_overlay._control_bar
	# 拖动前的条体位置；默认顶部居中，位移后用于差值断言。
	var bar_position_before_drag: Vector2 = control_bar.position
	_send_overlay_bar_drag(replay_overlay, Vector2(120.0, 260.0))
	if not control_bar.position.is_equal_approx(bar_position_before_drag + Vector2(120.0, 260.0)):
		_fail(null, "overlay_bar_drag before=%s after=%s" % [bar_position_before_drag, control_bar.position])
		return
	# 越界拖动被钳制；向右下拖出画面后条体必须完整停在安全边距内。
	_send_overlay_bar_drag(replay_overlay, Vector2(99999.0, 99999.0))
	# 钳制后的期望位置；画面尺寸减条体尺寸再留安全边距。
	var expected_clamped_position: Vector2 = Vector2(replay_overlay.size.x - control_bar.size.x - replay_overlay.bar_boundary_margin, replay_overlay.size.y - control_bar.size.y - replay_overlay.bar_boundary_margin)
	if not control_bar.position.is_equal_approx(expected_clamped_position):
		_fail(null, "overlay_bar_clamp position=%s expected=%s" % [control_bar.position, expected_clamped_position])
		return
	# 退出回放；应返回主菜单并直接停在“对局回放”内容页，第一视角恢复重演前的值。
	replay_overlay._exit_button.pressed.emit()
	await get_tree().process_frame
	# 主菜单内的回放内容页；退出重演后应保持可见。
	var menu_replay_panel: Control = main_instance.get_node("%MatchReplayPanel") as Control
	if bool(main_instance.get("_replay_session_active")) or not main_menu.visible or not menu_replay_panel.visible or replay_overlay.is_open() or int(match_controller.local_human_player_id) != previous_local_player_id:
		_fail(null, "table_replay_exit")
		return
	main_instance.queue_free()
	_cleanup_test_files()
	print("MATCH_REPLAY_PASS 命名保存、重命名顶置、播放意图、驱动器派发与牌桌整局重演全部通过")
	get_tree().quit(0)


## 向回放覆盖层控制条注入一次“按下-位移-松开”的合成拖动；位移经由拖动输入入口逐事件传递。
func _send_overlay_bar_drag(replay_overlay: MatchReplayOverlay, drag_delta: Vector2) -> void:
	# 合成左键按下事件；控制条据此进入拖动状态。
	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	replay_overlay._on_control_bar_gui_input(press_event)
	# 合成移动事件；relative 即拖动位移，覆盖层按该值移动并钳制条体。
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.relative = drag_delta
	replay_overlay._on_control_bar_gui_input(motion_event)
	# 合成左键松开事件；拖动状态结束。
	var release_event: InputEventMouseButton = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	replay_overlay._on_control_bar_gui_input(release_event)


## 构建一份满足录制头与武将牌渲染需要的最小公开快照；仅用于测试，不来自任何真实对局。
func _build_test_snapshot(first_player_hp: int, first_player_max_hp: int) -> Dictionary:
	return {
		"match_id": "test-match-1",
		"match_mode": "identity",
		"rules_snapshot": "noname-v1.10.16",
		"round_number": 1,
		"current_phase": "play",
		"current_player_id": 0,
		"game_over": false,
		"winner": "",
		"uid_sample": LARGE_UID_SAMPLE,
		"players": [
			{
				"player_id": 0,
				"display_name": "玩家1",
				"character_id": "",
				"identity": "hidden",
				"seat_number": 1,
				"hp": first_player_hp,
				"max_hp": first_player_max_hp,
				"shield": 0,
				"alive": true,
				"chained": false,
				"face_down": false,
				"hand_count": 4,
				"equipment": {},
				"judgment_area": [],
				"wooden_ox_storage_count": 0,
				"total_damage_dealt": 1,
				"total_damage_received": 2,
				"total_healing_done": 0,
				"total_cards_drawn": 6,
				"total_kill_count": 0,
			},
			{
				"player_id": 1,
				"display_name": "[AI]玩家2",
				"character_id": "",
				"identity": "hidden",
				"seat_number": 2,
				"hp": 3,
				"max_hp": 4,
				"shield": 0,
				"alive": true,
				"chained": false,
				"face_down": false,
				"hand_count": 4,
				"equipment": {},
				"judgment_area": [],
				"wooden_ox_storage_count": 0,
				"total_damage_dealt": 2,
				"total_damage_received": 1,
				"total_healing_done": 1,
				"total_cards_drawn": 5,
				"total_kill_count": 0,
			},
		],
	}


## 输出失败标签并清理测试产物；统一以非零状态退出。
func _fail(recorder: MatchReplayRecorder, failure_tag: String) -> void:
	if recorder != null:
		recorder.discard_recording()
	_cleanup_test_files()
	printerr("MATCH_REPLAY_FAIL %s" % failure_tag)
	get_tree().quit(1)


## 删除测试目录内全部文件与目录本身；测试开始与结束共用，保证多次运行互不影响。
func _cleanup_test_files() -> void:
	# 测试目录访问器；目录不存在时无需清理。
	var directory: DirAccess = DirAccess.open(TEST_REPLAY_DIRECTORY)
	if directory != null:
		for file_name: String in directory.get_files():
			directory.remove(file_name)
		DirAccess.open("user://").remove(TEST_REPLAY_DIRECTORY)
	# 目录外的导出样例文件；单独删除避免多次运行相互影响。
	if FileAccess.file_exists(TEST_EXPORT_PATH):
		DirAccess.open("user://").remove(TEST_EXPORT_PATH)


## 安装硬超时保护；异步等待异常时测试仍会以失败结束。
func _install_timeout_guard() -> void:
	# 超时计时器；一次性触发，命中即按失败退出。
	var timeout_timer: Timer = Timer.new()
	timeout_timer.one_shot = true
	timeout_timer.wait_time = TEST_TIMEOUT_MILLISECONDS / 1000.0
	timeout_timer.timeout.connect(func() -> void: _fail(null, "timeout"))
	add_child(timeout_timer)
	timeout_timer.start()
