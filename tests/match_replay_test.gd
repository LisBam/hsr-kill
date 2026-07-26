extends Node

## 对局回放功能回归测试。验证回放录制器的临时流式写入与重复保存复用；回放存储层的保存、
## 枚举、读取、导出、导入、损坏拒绝与删除；64位整数在二进制变体序列化下的无损往返；
## 结算面板“保存回放”按钮的信号契约；以及回放内容页的列表、播放、步进与返回列表流程。

## 结算面板场景；验证“保存回放”按钮存在于正式场景并发出保存意图。
const GAME_SETTLEMENT_PANEL_SCENE: PackedScene = preload("res://scenes/components/game_settlement_panel.tscn")

## 对局回放内容页场景；验证列表、播放器与目录覆盖入口。
const MATCH_REPLAY_PANEL_SCENE: PackedScene = preload("res://scenes/components/match_replay_panel.tscn")

## 测试专用回放目录；绝不读写正式回放目录，避免污染本机玩家已保存的回放。
const TEST_REPLAY_DIRECTORY: String = "user://replay_test_dir"

## 测试专用录制临时文件路径；位于测试目录内，结束时随目录一并清理。
const TEST_TEMP_RECORDING_PATH: String = "user://replay_test_dir/recording.tmp"

## 测试专用导出目标路径；位于回放目录之外，验证导出字节复制与再导入闭环，结束时单独清理。
const TEST_EXPORT_PATH: String = "user://replay_test_exported.lisbam_replay"

## 大于2^53的64位整数样例；验证 store_var 二进制格式在回放步骤流中完整保留整数精度。
const LARGE_UID_SAMPLE: int = 6917529027641081855

## 结算面板是否已发出保存回放信号；由信号回调写入。
var _save_replay_signal_received: bool = false


## 延迟执行以等待自动加载数据库完成索引；组件实例化依赖主题与数据库单例。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 依次运行录制器、存储层、结算按钮与回放内容页断言；任意失败清理测试文件并以非零状态退出。
func _run() -> void:
	_cleanup_test_files()
	# 回放录制器；使用测试目录内的独立临时文件。
	var recorder: MatchReplayRecorder = MatchReplayRecorder.new(TEST_TEMP_RECORDING_PATH)
	if not recorder.begin_recording("test-match-1", 0):
		_fail(recorder, "begin_recording")
		return
	recorder.record_snapshot(_build_test_snapshot(4, 4))
	recorder.record_log("测试日志一")
	recorder.record_log("测试日志二")
	recorder.record_snapshot(_build_test_snapshot(2, 4))
	# 首次保存结果文件名；应生成非空的 .lisbam_replay 文件。
	var saved_file_name: String = recorder.save_recording(TEST_REPLAY_DIRECTORY)
	if saved_file_name.is_empty() or saved_file_name.get_extension() != MatchReplayStore.REPLAY_FILE_EXTENSION:
		_fail(recorder, "save_recording name=%s" % saved_file_name)
		return
	# 重复保存结果；同一局必须复用首次文件而不是生成第二份。
	var repeated_file_name: String = recorder.save_recording(TEST_REPLAY_DIRECTORY)
	if repeated_file_name != saved_file_name or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 1:
		_fail(recorder, "save_recording_idempotent")
		return
	# 保存后继续录制的步骤；验证保存不中断录制流。
	recorder.record_log("保存之后的日志")
	# 列表首个条目；检查回放头的统计与元数据字段。
	var listed_entry: Dictionary = MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY)[0]
	# 列表条目的回放头；保存时快照统计为2份快照与2条日志。
	var header: Dictionary = listed_entry.get("header", {}) as Dictionary
	if str(listed_entry.get("file_name", "")) != saved_file_name or int(header.get("player_count", 0)) != 2 or int(header.get("snapshot_count", 0)) != 2 or int(header.get("log_count", 0)) != 2 or int(header.get("step_count", 0)) != 4 or str(header.get("match_mode", "")) != "identity" or int(header.get("viewer_player_id", -1)) != 0 or bool(header.get("truncated", true)):
		_fail(recorder, "replay_header %s" % str(header))
		return
	# 回放完整路径；供读取与导出断言复用。
	var replay_path: String = "%s/%s" % [TEST_REPLAY_DIRECTORY, saved_file_name]
	# 读取的全部步骤；顺序必须与录制一致：快照、日志、日志、快照。
	var steps: Array[Dictionary] = MatchReplayStore.read_replay_steps(replay_path)
	if steps.size() != 4 or str(steps[0].get("k", "")) != MatchReplayRecorder.STEP_KIND_SNAPSHOT or str(steps[1].get("k", "")) != MatchReplayRecorder.STEP_KIND_LOG or str(steps[2].get("k", "")) != MatchReplayRecorder.STEP_KIND_LOG or str(steps[3].get("k", "")) != MatchReplayRecorder.STEP_KIND_SNAPSHOT:
		_fail(recorder, "replay_steps size=%d" % steps.size())
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
	# 损坏文件路径；写入无关文本后导入必须被拒绝。
	var corrupted_path: String = "%s/corrupted.lisbam_replay" % TEST_REPLAY_DIRECTORY
	var corrupted_file: FileAccess = FileAccess.open(corrupted_path, FileAccess.WRITE)
	corrupted_file.store_string("这不是回放文件")
	corrupted_file.close()
	if not MatchReplayStore.import_replay(corrupted_path, TEST_REPLAY_DIRECTORY).is_empty() or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 2:
		_fail(recorder, "corrupted_import_rejected")
		return
	if not MatchReplayStore.delete_replay(imported_file_name, TEST_REPLAY_DIRECTORY) or MatchReplayStore.list_replays(TEST_REPLAY_DIRECTORY).size() != 1:
		_fail(recorder, "delete_replay")
		return
	# 结算面板实例；验证“保存回放”按钮存在并发出信号。
	var settlement_panel: GameSettlementPanel = GAME_SETTLEMENT_PANEL_SCENE.instantiate() as GameSettlementPanel
	add_child(settlement_panel)
	await get_tree().process_frame
	settlement_panel.save_replay_requested.connect(func() -> void: _save_replay_signal_received = true)
	settlement_panel.show_settlement(_build_test_snapshot(3, 4))
	# 结算面板中的保存回放按钮；缺失说明场景未同步。
	var save_replay_button: Button = settlement_panel.get_node_or_null("%SaveReplayButton") as Button
	if save_replay_button == null or save_replay_button.text != "保存回放":
		_fail(recorder, "settlement_save_button")
		return
	save_replay_button.pressed.emit()
	await get_tree().process_frame
	if not _save_replay_signal_received:
		_fail(recorder, "settlement_save_signal")
		return
	settlement_panel.queue_free()
	# 回放内容页实例；指向测试目录后打开应列出剩余的1份回放。
	var replay_panel: MatchReplayPanel = MATCH_REPLAY_PANEL_SCENE.instantiate() as MatchReplayPanel
	add_child(replay_panel)
	await get_tree().process_frame
	replay_panel.replay_directory_override = TEST_REPLAY_DIRECTORY
	replay_panel.open_panel()
	await get_tree().process_frame
	if replay_panel._list_container.get_child_count() != 1 or not replay_panel._play_button.disabled:
		_fail(recorder, "replay_panel_list count=%d" % replay_panel._list_container.get_child_count())
		return
	(replay_panel._list_container.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	if replay_panel._play_button.disabled or not replay_panel._detail_body_label.text.contains("身份模式"):
		_fail(recorder, "replay_panel_selection")
		return
	replay_panel._play_button.pressed.emit()
	await get_tree().process_frame
	if not replay_panel._playback_content.visible or replay_panel._browser_content.visible or replay_panel._playback_seat_views.size() != 2 or replay_panel._step_index != 0:
		_fail(recorder, "replay_playback_open step=%d seats=%d" % [replay_panel._step_index, replay_panel._playback_seat_views.size()])
		return
	replay_panel._step_forward_button.pressed.emit()
	await get_tree().process_frame
	if replay_panel._step_index != 3 or not replay_panel._playback_log_view.text.contains("测试日志二"):
		_fail(recorder, "replay_step_forward step=%d" % replay_panel._step_index)
		return
	replay_panel._step_back_button.pressed.emit()
	await get_tree().process_frame
	if replay_panel._step_index != 0 or replay_panel._playback_log_view.text.contains("测试日志一"):
		_fail(recorder, "replay_step_back step=%d" % replay_panel._step_index)
		return
	replay_panel._back_button.pressed.emit()
	await get_tree().process_frame
	if replay_panel._playback_content.visible or not replay_panel._browser_content.visible:
		_fail(recorder, "replay_back_to_list")
		return
	recorder.discard_recording()
	if FileAccess.file_exists(TEST_TEMP_RECORDING_PATH):
		_fail(recorder, "discard_recording_cleanup")
		return
	_cleanup_test_files()
	print("MATCH_REPLAY_PASS 录制保存、存储闭环、结算按钮与回放页播放全部通过")
	get_tree().quit(0)


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
