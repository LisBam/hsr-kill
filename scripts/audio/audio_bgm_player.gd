class_name AudioBgmPlayer
extends Node

## 背景音乐播放组件。
## 职责边界：循环播放、场景切换时的淡入淡出，以及同场景重复请求的幂等处理。
## 循环属性由本组件在加载后强制设置，不依赖资源导入面板中的循环勾选项，避免BGM只播一遍。
## 同一时刻只保留一条BGM；切换场景时旧曲淡出后释放，新曲淡入，不会出现两声部叠放。


## 背景音乐总线名；与 AudioService 运行时确保存在的总线保持一致。
const BGM_BUS_NAME: String = "BGM"

## 淡出终点的分贝值；-60分贝已低于可闻阈值，用作淡出与淡入的静音端点。
const FADE_SILENT_DB: float = -60.0

## 正常播放的分贝值；BGM总线已承担全局音量，播放器自身保持0分贝基准。
const FADE_FULL_DB: float = 0.0

## 场景切换淡入淡出时长；默认0.6秒，足以消除硬切爆音，又不会让玩家感到音乐延迟。
## 运行时可调整；设为0与关闭淡入淡出等效，切换立即生效。
@export var fade_duration_seconds: float = 0.6

## 是否启用淡入淡出；自动化测试可关闭以获得确定的播放位置。
@export var use_crossfade: bool = true

## 当前BGM场景标识；空字符串表示尚未播放任何场景BGM。
var _current_scene_id: String = ""

## 当前正在使用的播放器；同一时刻只有一条，切换时旧播放器在淡出结束后释放。
var _active_player: AudioStreamPlayer


## 播放指定场景的BGM；返回是否真正开始播放新的曲目。
## 同一场景重复请求为幂等操作：正在播放且场景未变时直接返回 false，不会重头播放。
## pool 为空或资源缺失时返回 false，并保持当前BGM不受影响。
func play_pool(scene_id: String, pool: Array[String], catalog: AudioCatalog) -> bool:
	if pool.is_empty() or catalog == null:
		return false
	# 随机选曲；同一场景投放多首BGM时每次进入随机播放其中一首。
	var selected_path: String = pool[randi() % pool.size()]
	# 音频流；文件缺失或加载失败时保持当前BGM继续播放。
	var stream: AudioStream = catalog.load_stream(selected_path)
	if stream == null:
		return false
	return play_stream(scene_id, stream)


## 直接播放一条已经解析好的BGM音频流；返回是否真正开始播放。
## 该入口供已经完成选曲的调用方与自动化测试使用，不改变幂等语义。
func play_stream(scene_id: String, stream: AudioStream) -> bool:
	if stream == null:
		return false
	# 幂等判断；选将、战斗、结算等阶段会反复请求同一场景，必须避免中途重播。
	if scene_id == _current_scene_id and is_instance_valid(_active_player) and _active_player.playing:
		return false
	_enable_loop(stream)
	# 旧播放器；先淡出再释放，避免切换瞬间两声部叠放。
	var previous_player: AudioStreamPlayer = _active_player
	if is_instance_valid(previous_player):
		_fade_out_and_release(previous_player)
	# 新播放器；需要淡入时以静音端点起步，由补间推到正常音量。
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = "BgmPlayer"
	player.bus = BGM_BUS_NAME
	player.stream = stream
	player.volume_db = FADE_SILENT_DB if use_crossfade else FADE_FULL_DB
	add_child(player)
	player.play()
	_active_player = player
	_current_scene_id = scene_id
	if use_crossfade:
		_fade_in(player)
	return true


## 淡出并停止当前BGM；清空场景标识，使下一次同场景请求能够重新播放。
func stop_bgm() -> void:
	_current_scene_id = ""
	var player: AudioStreamPlayer = _active_player
	_active_player = null
	if is_instance_valid(player):
		_fade_out_and_release(player)


## 返回当前BGM场景标识；空字符串表示没有正在播放的场景BGM。
func get_current_scene_id() -> String:
	return _current_scene_id


## 返回当前BGM的播放位置（秒）；仅用于诊断与自动化测试的幂等性断言。
func get_playback_position() -> float:
	if is_instance_valid(_active_player) and _active_player.playing:
		return _active_player.get_playback_position()
	return 0.0


## 按流类型强制开启循环；同时修改资源本身，避免同一资源被复用时行为不一致。
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


## 淡入新曲；从静音端点平滑推到正常音量。
func _fade_in(player: AudioStreamPlayer) -> void:
	# 淡入补间；由本节点创建，随节点释放自动失效，不会残留回调。
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", FADE_FULL_DB, fade_duration_seconds)


## 淡出并释放播放器；关闭淡入淡出时立即停止并释放。
func _fade_out_and_release(player: AudioStreamPlayer) -> void:
	if not use_crossfade or fade_duration_seconds <= 0.0:
		player.stop()
		player.queue_free()
		return
	# 淡出补间；结束后停止并释放播放器，避免残留音频与节点。
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", FADE_SILENT_DB, fade_duration_seconds)
	tween.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	)
