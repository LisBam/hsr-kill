class_name AudioVoicePlayer
extends Node

## 语音播放组件。
## 职责边界：把音频流真正送到音效总线，并在多音效池中做出随机选择。
## 不判断“该不该播”（去重与时机由核心层事件通道决定），只负责“播哪一个、怎么播”。
## 按主公钦定不设并发上限与最小重播间隔：多张牌同时结算时各路语音会同时播出。
## 播放器按需分配：空闲播放器优先复用，不足时新建，播放结束后经 finished 信号回收。


## 音效总线名；与 AudioService 运行时确保存在的总线保持一致。
const SFX_BUS_NAME: String = "SFX"

## 是否避免同一音效池连续两次播放同一文件；默认开启，保证“多个配音随机”不退化为单曲循环。
## 运行时可关闭，关闭后每次都在整个池内均匀随机。
@export var avoid_immediate_repeat: bool = true

## 空闲播放器缓存；播放结束后回收到本数组复用，避免频繁创建与销毁节点。
var _idle_players: Array[AudioStreamPlayer] = []

## 正在播放的播放器；键为播放器实例ID、值为播放器本身，用于统计与统一停止。
var _busy_players: Dictionary = {}

## 各音效池上一次播放的资源路径；键为调用方提供的池标识，用于避免连续重复。
var _last_played_path_by_pool: Dictionary = {}


## 组件就绪时允许在暂停状态下继续回收播放器，避免暂停菜单音乐残留占用节点。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 从候选池中随机选一条语音并播放；返回是否真正开始播放。
## pool 为空、音频文件缺失或加载失败都返回 false，调用方无须额外判断。
## pool_key 用于记录该池上一次播放的文件，从而避免连续重复；同一技能应传入同一标识。
func play_pool(pool: Array[String], catalog: AudioCatalog, pool_key: String = "") -> bool:
	if pool.is_empty() or catalog == null:
		return false
	# 本次选中的资源路径；池内随机且按池标识规避连续重复。
	var selected_path: String = _pick_random_path(pool, pool_key)
	if selected_path.is_empty():
		return false
	# 音频流；文件缺失或类型不符时由 load_stream 返回 null，此处静默跳过。
	var stream: AudioStream = catalog.load_stream(selected_path)
	if stream == null:
		return false
	if not pool_key.is_empty():
		_last_played_path_by_pool[pool_key] = selected_path
	return play_stream(stream)


## 直接播放一条音频流；返回是否真正开始播放。
## 该入口供已经完成选择的调用方使用（例如固定的单音效），不参与池随机与连续重复规避。
func play_stream(stream: AudioStream) -> bool:
	if stream == null:
		return false
	# 播放器实例；优先复用空闲播放器，池不足时新建，因此同时播放数量不受人为上限约束。
	var player: AudioStreamPlayer = _acquire_player()
	if player == null:
		return false
	player.stream = stream
	player.play()
	return true


## 立即停止全部正在播放的语音并回收播放器；用于返回主菜单等需要清场的场景。
func stop_all() -> void:
	for player_variant: Variant in _busy_players.values():
		var player: AudioStreamPlayer = player_variant as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null
		_idle_players.append(player)
	_busy_players.clear()


## 返回当前正在播放的语音数量；仅用于诊断与自动化测试断言。
func get_active_voice_count() -> int:
	return _busy_players.size()


## 在候选池中随机选择一条路径；开启避免重复时排除上一次播放的文件。
func _pick_random_path(pool: Array[String], pool_key: String) -> String:
	if pool.is_empty():
		return ""
	if pool.size() == 1:
		return pool[0]
	# 上次播放路径；仅在开启避免重复且调用方提供了池标识时参与过滤。
	var last_played_path: String = ""
	if avoid_immediate_repeat and not pool_key.is_empty():
		last_played_path = str(_last_played_path_by_pool.get(pool_key, ""))
	# 实际参与随机的候选；默认使用完整池。
	var candidates: Array[String] = pool
	if not last_played_path.is_empty():
		# 过滤后的候选；若过滤结果为空（理论上不会发生）则退回完整池，保证始终可播。
		var filtered_candidates: Array[String] = []
		for path: String in pool:
			if path != last_played_path:
				filtered_candidates.append(path)
		if not filtered_candidates.is_empty():
			candidates = filtered_candidates
	return candidates[randi() % candidates.size()]


## 取得一个可用的播放器；优先复用空闲实例，全部占用时新建，因此不存在并发上限。
func _acquire_player() -> AudioStreamPlayer:
	# 空闲播放器复用循环；期间跳过已被外部释放的失效实例。
	while not _idle_players.is_empty():
		var reused_player: AudioStreamPlayer = _idle_players.pop_back()
		if is_instance_valid(reused_player):
			_busy_players[reused_player.get_instance_id()] = reused_player
			return reused_player
	# 新建播放器；统一挂音效总线，音量由总线统一控制。
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = "VoicePlayer"
	player.bus = SFX_BUS_NAME
	player.finished.connect(_on_player_finished.bind(player))
	add_child(player)
	_busy_players[player.get_instance_id()] = player
	return player


## 单条语音播放结束；清空流并把播放器回收到空闲池，供后续请求复用。
func _on_player_finished(player: AudioStreamPlayer) -> void:
	_busy_players.erase(player.get_instance_id())
	if not is_instance_valid(player):
		return
	player.stream = null
	_idle_players.append(player)
