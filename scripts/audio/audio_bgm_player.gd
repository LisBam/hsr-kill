class_name AudioBgmPlayer
extends Node

## 背景音乐播放组件。
## 职责边界：循环播放、场景切换时的淡入淡出，以及同场景重复请求的幂等处理。
## 循环属性由本组件在加载后强制设置，不依赖资源导入面板中的循环勾选项，避免BGM只播一遍。
## 同一时刻只保留一条BGM；切换场景时旧曲淡出后释放，新曲淡入，不会出现两声部叠放。
## 暂停语义：记录面板、武将详情与机缘选择等界面会申请对局暂停令牌并冻结场景树，
## 该冻结只应停止玩法推进，不应中断背景音乐；本组件因此始终在处理模式下运行，
## 使 BGM 播放与淡入淡出补间在 SceneTree.paused 期间继续推进。
##
## 场景所有权（BGM 隔离的核心约定）：
## 本组件在任何时刻最多只归属于一个场景标识，_current_scene_id 记录“当前持有播放权的场景”。
##   一、进入场景一定接管：play_pool()/play_stream() 只要收到新的场景标识，就先把上一个场景的曲目淡出停止，
##       再把归属改到新场景。因此“目标场景没有投放任何素材”不会退化成“上一个场景的曲目继续播放”——
##       这正是退出对局后战斗BGM仍在播放的根因所在。
##   二、退出场景必须指名：release_scene() 只会停止与传入标识相同的场景，
##       退出A场景不会误停B场景正在播放的曲目，两类BGM互不干扰。
##   三、组件销毁即静音：_exit_tree() 会立刻停止正在播放的曲目，
##       避免播放权随节点销毁而丢失后，曲目在下一个场景里继续出声。


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

## 当前BGM场景标识；空字符串表示尚未持有任何场景的播放权。
var _current_scene_id: String = ""

## 当前正在使用的播放器；同一时刻只有一条，切换时旧播放器在淡出结束后释放。
var _active_player: AudioStreamPlayer


## 组件就绪时允许在暂停状态下继续播放并推进淡入淡出补间。
## 与 AudioVoicePlayer 保持同一处理模式：暂停只冻结玩法，不冻结背景音乐与界面音效。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 组件离开场景树时立刻停止当前曲目；返回的是硬停止而不是淡出。
## 淡出由绑定在本节点上的补间推进，节点离开场景树后补间不再前进，此时若不硬停止，
## 播放器会随着本组件的释放而失去归属，正在播放的BGM就会遗留到下一个场景（音频总线归自动加载节点所有）。
func _exit_tree() -> void:
	_current_scene_id = ""
	var player: AudioStreamPlayer = _active_player
	_active_player = null
	if is_instance_valid(player):
		player.stop()


## 播放指定场景的BGM；返回是否真正开始播放新的曲目。
## 同一场景重复请求为幂等操作：正在播放且场景未变时直接返回 false，不会重头播放。
## pool 为空表示该场景没有投放任何BGM：本组件依然接管该场景，并停止上一个场景的曲目，
## 保证“进入无BGM的场景”等价于“上一个场景的BGM结束”。
func play_pool(scene_id: String, pool: Array[String], catalog: AudioCatalog) -> bool:
	# 场景曲目；池为空或解析器缺失时保持 null，由 play_stream 完成“接管但无曲可播”的语义。
	var stream: AudioStream = null
	if not pool.is_empty() and catalog != null:
		# 随机选曲；同一场景投放多首BGM时每次进入随机播放其中一首。
		var selected_path: String = pool[randi() % pool.size()]
		# 音频流；文件缺失或加载失败时同样按“本场景无曲可播”处理，并照常释放上一个场景的曲目。
		stream = catalog.load_stream(selected_path)
	return play_stream(scene_id, stream)


## 直接播放一条已经解析好的BGM音频流；返回是否真正开始播放。
## 该入口供已经完成选曲的调用方与自动化测试使用，不改变幂等语义与场景接管语义。
## stream 为 null 表示该场景没有可用曲目：此时仍然接管场景归属并停掉上一个场景的曲目。
func play_stream(scene_id: String, stream: AudioStream) -> bool:
	# 规范化场景标识；空标识无法表达“接管哪个场景”，直接拒绝，避免出现无主的BGM。
	var normalized_scene_id: String = scene_id.strip_edges()
	if normalized_scene_id.is_empty():
		return false
	# 幂等判断；选将、战斗、结算等阶段会反复请求同一场景，必须避免中途重播。
	if normalized_scene_id == _current_scene_id and is_instance_valid(_active_player) and _active_player.playing:
		return false
	# 场景切换；把上一个场景的曲目淡出并解除归属，随后无论新场景是否真的有曲目，播放权都已转移。
	_release_active_player()
	_current_scene_id = normalized_scene_id
	if stream == null:
		return false
	_enable_loop(stream)
	# 新播放器；需要淡入时以静音端点起步，由补间推到正常音量。
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = "BgmPlayer"
	player.bus = BGM_BUS_NAME
	player.stream = stream
	player.volume_db = FADE_SILENT_DB if use_crossfade else FADE_FULL_DB
	add_child(player)
	player.play()
	_active_player = player
	if use_crossfade:
		_fade_in(player)
	return true


## 释放指定场景的BGM播放权；只有当前播放的正是该场景时才会停止。
## 返回是否真的执行了释放。该作用域语义让“退出A场景”与“进入B场景”互不误伤：
## 调用方可以在不确定当前在播哪一套BGM时安全地声明自己负责的那一套已经结束。
func release_scene(scene_id: String) -> bool:
	# 规范化场景标识；空标识与不匹配的标识都不属于本组件当前持有的场景。
	var normalized_scene_id: String = scene_id.strip_edges()
	if normalized_scene_id.is_empty() or normalized_scene_id != _current_scene_id:
		return false
	_current_scene_id = ""
	_release_active_player()
	return true


## 淡出并停止当前BGM；清空场景标识，使下一次同场景请求能够重新播放。
## 与 release_scene() 的区别：本入口不做场景匹配，无条件清空归属，供诊断与整体停机使用。
func stop_bgm() -> void:
	_current_scene_id = ""
	_release_active_player()


## 返回当前BGM场景标识；空字符串表示没有正在播放的场景BGM。
func get_current_scene_id() -> String:
	return _current_scene_id


## 返回当前场景是否真的有曲目在播放；场景已接管但该场景没有素材时返回 false。
## 仅供诊断与自动化测试断言，不参与播放决策。
func is_scene_playing() -> bool:
	return is_instance_valid(_active_player) and _active_player.playing


## 返回当前BGM的播放位置（秒）；仅用于诊断与自动化测试的幂等性断言。
func get_playback_position() -> float:
	if is_instance_valid(_active_player) and _active_player.playing:
		return _active_player.get_playback_position()
	return 0.0


## 解除当前播放器的归属并按配置释放；释放后 _active_player 不再指向任何播放器。
## 旧播放器先淡出再释放（关闭淡入淡出时立即停止），避免切换瞬间两声部叠放。
func _release_active_player() -> void:
	var player: AudioStreamPlayer = _active_player
	_active_player = null
	if is_instance_valid(player):
		_fade_out_and_release(player)


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
