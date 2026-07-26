class_name MatchReplayRecorder
extends RefCounted

## 对局回放录制器。组件只订阅牌桌已经收到的观察者裁剪快照与对局日志文本，把它们按时间顺序
## 流式写入本地临时文件；点击“保存回放”时经 MatchReplayStore 转存为正式 `.lisbam_replay` 文件。
## 录制器不读取 GameState、不访问 MatchController 内部状态、不修改任何规则数据；
## 离线对局、局域网房主与局域网客户端录到的都是本机视角快照，因此回放呈现与当局所见完全一致。
##
## 步骤流结构：每个步骤为一个 store_var 字典 {"t": 相对录制起点的毫秒数, "k": 步骤类型, "d": 数据}；
## 快照步骤的 d 为完整观察者快照字典，日志步骤的 d 为单条日志字符串，
## 表现步骤的 d 为纯数据表现字典（技能/防具发动、卡牌使用/展示/判定表现、移牌、摸牌批次、
## 所有权释放；只含稳定玩家 ID、名称与牌面快照，不含坐标或节点引用，结构由牌桌录制点定义）。

## 快照步骤类型标记；播放器据此把该步骤应用为全场状态刷新。
const STEP_KIND_SNAPSHOT: String = "s"

## 日志步骤类型标记；播放器据此把该步骤追加到回放日志正文。
const STEP_KIND_LOG: String = "l"

## 表现步骤类型标记；承载技能/防具发动提示、卡牌中央飞牌、目标指示线、移牌与摸牌批次等桌面表现，
## 重演端据此按原表现流程重放对应视觉。该类型为格式版本1的兼容性追加：旧读取端遇到未知类型直接忽略。
const STEP_KIND_PRESENTATION: String = "p"

## 默认临时步骤流文件路径；对局进行期间逐步追加写入，避免长局把全部快照堆积在内存。
const DEFAULT_TEMP_RECORDING_PATH: String = "user://replays/recording.tmp"

## 单局最大录制步骤数；超过后停止追加新步骤并在回放头标记截断，防止异常长局产生不可控的文件体积。
const MAX_RECORDED_STEPS: int = 30000

## 临时步骤流文件路径；默认位于回放目录内，自动化测试可在构造时传入独立路径避免污染玩家数据。
var _temp_recording_path: String = DEFAULT_TEMP_RECORDING_PATH

## 临时步骤流写入句柄；仅在录制进行中非空，保存与丢弃都会关闭句柄。
var _temp_file: FileAccess = null

## 当前录制对局的 match_id；用于识别新对局开始并防止跨局步骤混入同一份回放。
var _current_match_id: String = ""

## 当前录制对局的本机视角玩家 ID；写入回放头，播放器据此说明回放视角归属。
var _viewer_player_id: int = -1

## 录制起点的单调毫秒时刻；所有步骤时间戳都是相对该起点的差值，播放器按差值还原节奏。
var _begin_ticks_msec: int = 0

## 已录制步骤总数；达到 MAX_RECORDED_STEPS 后停止追加并置截断标记。
var _step_count: int = 0

## 已录制快照步骤数；写入回放头供列表展示回放长度。
var _snapshot_count: int = 0

## 已录制日志步骤数；写入回放头供列表展示日志规模。
var _log_count: int = 0

## 已录制表现步骤数；写入回放头供列表展示发动提示、飞牌与移牌等表现规模。
var _presentation_count: int = 0

## 是否因步骤上限而截断；写入回放头，播放器可提示玩家回放不完整。
var _truncated: bool = false

## 最近一次录制的完整快照；仅用于保存时生成回放头元数据（模式、玩家、胜负），不做第二份玩法状态。
var _latest_snapshot: Dictionary = {}

## 最近一步的相对毫秒时间戳；保存时作为回放总时长写入回放头。
var _last_step_time_msec: int = 0

## 本局已保存的回放文件名；同一局重复点击“保存回放”直接复用该结果，不生成重复文件。
var _saved_file_name: String = ""


## 构造录制器；可传入独立临时文件路径供自动化测试隔离，正式运行使用默认路径。
func _init(temp_recording_path: String = DEFAULT_TEMP_RECORDING_PATH) -> void:
	_temp_recording_path = temp_recording_path


## 开始录制一局新对局；会先丢弃未保存的旧录制，再创建全新的临时步骤流。返回是否成功开始。
func begin_recording(match_id: String, viewer_player_id: int) -> bool:
	discard_recording()
	if not MatchReplayStore.ensure_replay_directory(_temp_recording_path.get_base_dir()):
		return false
	_temp_file = FileAccess.open(_temp_recording_path, FileAccess.WRITE)
	if _temp_file == null:
		return false
	_current_match_id = match_id
	_viewer_player_id = viewer_player_id
	_begin_ticks_msec = Time.get_ticks_msec()
	_step_count = 0
	_snapshot_count = 0
	_log_count = 0
	_presentation_count = 0
	_truncated = false
	_latest_snapshot = {}
	_last_step_time_msec = 0
	_saved_file_name = ""
	return true


## 当前是否正在录制；牌桌据此决定是否把快照与日志转交给录制器。
func is_recording() -> bool:
	return _temp_file != null


## 当前录制对局的 match_id；牌桌用它识别快照是否属于新对局，从而自动开始新一份录制。
func get_current_match_id() -> String:
	return _current_match_id


## 本局是否已经保存过回放；结算面板据此提示重复保存直接复用既有文件。
func get_saved_file_name() -> String:
	return _saved_file_name


## 录制一份观察者快照步骤；快照为牌桌收到的只读裁剪字典，录制器深拷贝后写入避免后续修改污染。
func record_snapshot(snapshot: Dictionary) -> void:
	if _temp_file == null or snapshot.is_empty():
		return
	_latest_snapshot = snapshot
	# 追加前的步骤计数；用于判断本份快照是否真正写入（未因步骤上限被丢弃）。
	var previous_step_count: int = _step_count
	_append_step(STEP_KIND_SNAPSHOT, snapshot.duplicate(true))
	if _step_count > previous_step_count:
		_snapshot_count += 1


## 录制一条对局日志步骤；日志文本与牌桌“记录”面板收到的完全一致。
func record_log(message: String) -> void:
	if _temp_file == null or message.is_empty():
		return
	# 追加前的步骤计数；用于判断本条日志是否真正写入（未因步骤上限被丢弃）。
	var previous_step_count: int = _step_count
	_append_step(STEP_KIND_LOG, message)
	if _step_count > previous_step_count:
		_log_count += 1


## 录制一步桌面表现；presentation 为纯数据字典（技能/防具发动、卡牌表现、移牌、摸牌批次、所有权释放），
## 深拷贝后写入避免调用方后续修改污染，重演端把同一份数据送回正式表现入口并按当时布局重新解析坐标。
func record_presentation(presentation: Dictionary) -> void:
	if _temp_file == null or presentation.is_empty():
		return
	# 追加前的步骤计数；用于判断本步表现是否真正写入（未因步骤上限被丢弃）。
	var previous_step_count: int = _step_count
	_append_step(STEP_KIND_PRESENTATION, presentation.duplicate(true))
	if _step_count > previous_step_count:
		_presentation_count += 1


## 把当前录制内容保存为正式回放文件；返回保存后的文件名，失败返回空字符串。
## 同一局重复调用直接返回首次保存的文件名；保存后录制继续进行，不影响后续步骤追加。
## preferred_base_name 为玩家在命名弹窗填写的自定义回放名（不含后缀）；留空时由存储层生成默认名。
func save_recording(directory_path: String = MatchReplayStore.REPLAY_DIRECTORY, preferred_base_name: String = "") -> String:
	if _temp_file == null or _snapshot_count <= 0:
		return _saved_file_name
	if not _saved_file_name.is_empty():
		return _saved_file_name
	# 保存前先关闭写句柄；Windows 平台不保证同一文件可同时读写，转存完成后再以追加方式续开。
	_temp_file.close()
	_temp_file = null
	# 转存结果文件名；空字符串表示存储层失败，录制状态仍保留供玩家重试。
	var file_name: String = MatchReplayStore.save_replay_from_temp(_build_header(), _temp_recording_path, directory_path, preferred_base_name)
	# 续写句柄；READ_WRITE 不截断既有内容，指针移动到末尾后继续追加后续步骤。
	var resumed_file: FileAccess = FileAccess.open(_temp_recording_path, FileAccess.READ_WRITE)
	if resumed_file != null:
		resumed_file.seek_end()
		_temp_file = resumed_file
	if not file_name.is_empty():
		_saved_file_name = file_name
	return file_name


## 丢弃当前录制并删除临时步骤流文件；新对局开始、返回主菜单与退出牌桌统一使用本入口。
func discard_recording() -> void:
	if _temp_file != null:
		_temp_file.close()
		_temp_file = null
	if FileAccess.file_exists(_temp_recording_path):
		# 临时文件目录访问器；目录打开失败时放弃删除，孤立临时文件会在下次开始录制时被覆盖。
		var directory: DirAccess = DirAccess.open(_temp_recording_path.get_base_dir())
		if directory != null:
			directory.remove(_temp_recording_path.get_file())
	_current_match_id = ""
	_latest_snapshot = {}
	_saved_file_name = ""


## 追加一个步骤到临时流；统一处理时间戳、步骤上限与截断标记。
func _append_step(step_kind: String, step_data: Variant) -> void:
	if _step_count >= MAX_RECORDED_STEPS:
		_truncated = true
		return
	_last_step_time_msec = maxi(Time.get_ticks_msec() - _begin_ticks_msec, 0)
	_temp_file.store_var({
		"t": _last_step_time_msec,
		"k": step_kind,
		"d": step_data,
	})
	_step_count += 1


## 依据最近快照构建回放头元数据；只提取公开字段，回放头不包含任何未录入步骤流的私有信息。
func _build_header() -> Dictionary:
	# 回放头玩家条目；仅保留列表与播放界面需要的公开身份资料，隐藏字段保持快照原始裁剪结果。
	var player_entries: Array[Dictionary] = []
	for player_variant: Variant in _latest_snapshot.get("players", []) as Array:
		# 当前玩家公开快照；字段缺失时使用与快照一致的默认值。
		var player: Dictionary = player_variant as Dictionary
		if player.is_empty():
			continue
		player_entries.append({
			"player_id": int(player.get("player_id", -1)),
			"display_name": str(player.get("display_name", "玩家")),
			"character_id": str(player.get("character_id", "")),
			"identity": str(player.get("identity", "hidden")),
			"seat_number": int(player.get("seat_number", 0)),
		})
	return {
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"rules_snapshot": str(_latest_snapshot.get("rules_snapshot", "")),
		"match_id": _current_match_id,
		"match_mode": str(_latest_snapshot.get("match_mode", "identity")),
		"player_count": player_entries.size(),
		"viewer_player_id": _viewer_player_id,
		"players": player_entries,
		"winner": str(_latest_snapshot.get("winner", "")),
		"game_over": bool(_latest_snapshot.get("game_over", false)),
		"duration_msec": _last_step_time_msec,
		"step_count": _step_count,
		"snapshot_count": _snapshot_count,
		"log_count": _log_count,
		"presentation_count": _presentation_count,
		"truncated": _truncated,
	}
