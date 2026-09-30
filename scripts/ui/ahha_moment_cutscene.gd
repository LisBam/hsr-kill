class_name AhhaMomentCutscene
extends Control

## 阿哈时刻过场动画表现组件。它只订阅规则层的「阿哈时刻开始」通知并播放绿幕视频，
## 不修改任何对局状态，也不充当规则完成条件：规则流程照常推进。
## 视频资源缺失、播放器缺失或解码失败时组件静默降级为不显示，绝不阻塞对局。

## 过场动画视频资源路径。Godot 内置播放器只支持 Ogg Theora，
## 因此原始 mp4 必须转码为 .ogv 后才能在这里播放，两者放在同一目录便于溯源。
## 当前启用「精简」版；同一目录下的 阿哈时刻过场动画.ogv 是完整版，保留备用、不再被本组件加载，
## 切换素材只需修改本常量，或在检查器中直接指定 cutscene_stream。
const CUTSCENE_STREAM_PATH: String = "res://game_data/video/阿哈时刻-精简.ogv"

## 过场动画的绘制层级。120 高于牌桌、飞牌、技能提示与角色资料，
## 低于卡牌选择窗口（150）、结算面板（220）与局内菜单（500），
## 因此动画播放期间弹出的选择窗口与菜单仍然完整可见、可操作。
const CUTSCENE_Z_INDEX: int = 120

## 申请对局暂停时使用的稳定原因文本；暂停令牌诊断与调试日志据此识别本次暂停来自过场动画。
const PAUSE_REASON: String = "ahha_moment_cutscene"

## 视频播放节点名。组件场景内的唯一子节点，缺失时组件降级为不播放。
const VIDEO_NODE_NAME: String = "Video"


## 过场动画播放结束（含淡出）时发出。只供调试与后续扩展订阅，规则层不读取也不等待该信号。
signal cutscene_finished()


## 过场动画视频。留空时按 CUTSCENE_STREAM_PATH 自动加载；可在检查器中替换成其它过场资源。
@export var cutscene_stream: VideoStream = null

## 是否在回合开始前的常规阿哈时刻播放过场；关闭后该来源只写对局日志、不显示动画。
@export var play_on_turn_start: bool = true

## 是否在整轮都未触发后的轮末保底阿哈时刻播放过场。
@export var play_on_round_end: bool = true

## 是否在技能请求的额外阿哈时刻（例如【鸿运】）播放过场。
@export var play_on_extra_moment: bool = true

## 淡入时长（秒）。默认 0.22 让动画自然出现而不是硬切；设为 0 表示立即完全显示。
@export_range(0.0, 2.0, 0.01) var fade_in_seconds: float = 0.22

## 淡出时长（秒）。默认 0.30 避免播完瞬间消失显得突兀；设为 0 表示立即隐藏。
@export_range(0.0, 2.0, 0.01) var fade_out_seconds: float = 0.30

## 淡出结束时的画面缩放倍率。0 表示画面一边变淡一边收拢到中心直至消失，1 表示只淡出不做缩放。
## 缩放与淡出共用 fade_out_seconds 作为时长，因此两者严格同时开始、同时结束。
@export_range(0.0, 1.0, 0.01) var fade_out_scale: float = 0.0

## 播放音量（分贝）。0 为素材原始音量，-80 等效静音；只影响本次播放，不修改音频总线。
@export_range(-80.0, 24.0, 0.5) var volume_db: float = 0.0

## 播放期间是否暂停对局。开启后牌桌与 AI 整体停止推进，动画结束后自动恢复，
## 适合被当作正式过场观看；关闭时动画只作为叠加演出，规则照常结算。
@export var pause_gameplay_while_playing: bool = false

## 色度键控的钥匙色。绿幕视频保持默认纯绿，蓝幕素材改为纯蓝即可完成抠像。
@export var chroma_key_color: Color = Color(0.0, 1.0, 0.0, 1.0)

## 色度相似度阈值。越大抠掉的背景越多，过大会吃掉前景中与钥匙色接近的绿色细节。
@export_range(0.0, 1.5, 0.01) var chroma_key_similarity: float = 0.30

## 边缘过渡宽度。越大边缘越柔和且能保留发丝，越小轮廓越锐利但更容易出现锯齿。
@export_range(0.001, 1.0, 0.001) var chroma_key_smoothness: float = 0.12

## 去溢色强度。1 表示完全移除角色边缘沿钥匙色方向的残留反光，0 表示保留原始绿边。
@export_range(0.0, 1.0, 0.01) var chroma_key_spill_suppression: float = 1.0

## 色度键控着色器。为空时沿用组件场景中已经配置好的材质；两者都为空时直接显示未抠像的视频，便于排查。
@export var chroma_key_shader: Shader


## 视频播放节点。组件场景缺失该节点时为 null，全部播放入口直接返回失败。
var _video_player: VideoStreamPlayer

## 当前用于暂停对局的服务。由桌面在创建组件后注入；未注入时暂停开关静默失效。
var _pause_service: GameplayPauseService

## 当前持有的对局暂停令牌。-1 表示没有暂停对局，避免重复申请或重复释放。
var _pause_token: int = -1

## 当前淡入淡出补间。播放新动画前先终止旧补间，避免上一段淡出把新动画一起隐藏。
var _fade_tween: Tween

## 当前是否处于播放中（不含淡出阶段）。重复触发时按重播处理，不会叠加第二份画面。
var _playing: bool = false


## 初始化绘制层级、视频节点与抠像参数。组件默认隐藏，只在被明确要求播放时出现。
func _ready() -> void:
	z_index = CUTSCENE_Z_INDEX
	visible = false
	modulate.a = 0.0
	# 缩放中心跟随控件尺寸：不设置时缩放以左上角为原点，画面会往左上角缩而不是往画面中心收。
	resized.connect(_update_pivot_offset)
	_update_pivot_offset()
	_video_player = get_node_or_null(VIDEO_NODE_NAME) as VideoStreamPlayer
	if _video_player == null:
		return
	_video_player.finished.connect(_on_video_finished)
	_apply_chroma_key_parameters()


## 把缩放中心更新为控件中心。全屏过场在窗口尺寸变化后仍要保持「从画面中心收拢」的观感。
func _update_pivot_offset() -> void:
	pivot_offset = size * 0.5


## 退出场景树时释放暂停令牌；返回主菜单或关闭场景不会残留全局暂停。
func _exit_tree() -> void:
	_release_pause()


## 注入对局暂停服务。桌面在创建组件后调用；未注入时暂停开关静默失效而不是报错。
func set_pause_service(service: GameplayPauseService) -> void:
	_pause_service = service


## 按触发来源播放过场动画；返回 true 表示本次确实开始播放。
## 来源被关闭、视频资源缺失或组件缺少播放节点时返回 false，调用方不需要任何补偿。
func play_cutscene(source: String) -> bool:
	if not _is_source_enabled(source):
		return false
	# 本次播放使用的视频；缺失时直接放弃播放，规则流程不受影响。
	var stream: VideoStream = _resolve_stream()
	if stream == null or _video_player == null:
		return false
	_kill_fade_tween()
	# 暂停在播放真正开始时申请；被拒绝的播放请求不会留下无法释放的令牌。
	_acquire_pause()
	_video_player.stream = stream
	_video_player.volume_db = volume_db
	# 重复触发时从头重播：先停止旧播放，避免上一段的残帧与新动画叠加。
	_video_player.stop()
	_video_player.play()
	_playing = true
	visible = true
	# 复位上一轮淡出留下的缩放与透明度；否则第二次播放会从缩小状态直接出现。
	scale = Vector2.ONE
	_update_pivot_offset()
	modulate.a = 0.0
	if fade_in_seconds <= 0.0:
		modulate.a = 1.0
		return true
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, fade_in_seconds)
	return true


## 立即结束过场动画并释放暂停令牌。重新开局、返回主菜单与场景退出时调用，可安全重复执行。
func stop_cutscene() -> void:
	_kill_fade_tween()
	if _video_player != null:
		_video_player.stop()
	_playing = false
	visible = false
	modulate.a = 0.0
	# 缩放复位，保证下一次播放从完整尺寸开始而不是继承上次被中断的缩小状态。
	scale = Vector2.ONE
	_release_pause()


## 返回当前是否正在播放过场动画。只读诊断接口，供测试复核播放状态，不参与任何规则判定。
func is_cutscene_playing() -> bool:
	return _playing


## 视频播完后的收尾：一边淡出一边收拢，结束后才释放暂停令牌，玩家不会看到动画消失瞬间的对局跳变。
func _on_video_finished() -> void:
	if not _playing:
		return
	# 先清播放标记：迟到的重复 finished 不会再启动第二段淡出。
	_playing = false
	if fade_out_seconds <= 0.0:
		visible = false
		modulate.a = 0.0
		scale = Vector2.ONE
		_release_pause()
		cutscene_finished.emit()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_out_seconds)
	# 缩放与淡出并行且共用同一时长：画面一边变透明一边收拢到中心，两者严格同时结束。
	_fade_tween.parallel().tween_property(self, "scale", Vector2.ONE * fade_out_scale, fade_out_seconds)
	_fade_tween.finished.connect(_on_fade_out_finished)


## 淡出补间结束：隐藏节点、复位缩放、恢复对局并广播过场结束。
func _on_fade_out_finished() -> void:
	visible = false
	# 缩放复位放在隐藏之后：下一轮播放不需要依赖 play_cutscene 的复位也能从完整尺寸开始。
	scale = Vector2.ONE
	_release_pause()
	cutscene_finished.emit()


## 判断本次触发来源是否允许播放过场。来源字符串统一取自 AhhaMomentSystem 的公开常量，避免两侧字符串分叉。
func _is_source_enabled(source: String) -> bool:
	match source:
		AhhaMomentSystem.SOURCE_TURN_START:
			return play_on_turn_start
		AhhaMomentSystem.SOURCE_ROUND_END:
			return play_on_round_end
		AhhaMomentSystem.SOURCE_EXTRA_MOMENT:
			return play_on_extra_moment
	return false


## 解析本次播放使用的视频。检查器已指定时直接使用，否则按固定路径加载，路径不存在时返回 null。
func _resolve_stream() -> VideoStream:
	if cutscene_stream != null:
		return cutscene_stream
	if not ResourceLoader.exists(CUTSCENE_STREAM_PATH):
		return null
	return ResourceLoader.load(CUTSCENE_STREAM_PATH) as VideoStream


## 把检查器中的键控参数写入视频材质。着色器缺失时保留场景内原材质，材质也不存在时不做任何修改。
##
## 参数优先级：根节点上的四个 @export 是抠像参数的**唯一权威来源**。
## 场景里 Video 节点的材质同样能在检查器中改到同名参数，但那些值会在运行时被本方法覆盖，
## 因此调参请一律改根节点，不要改材质，否则会出现「改了没反应」。
func _apply_chroma_key_parameters() -> void:
	if _video_player == null:
		return
	# 当前抠像材质；检查器指定着色器时新建或替换，否则沿用组件场景中已配置的材质。
	var material: ShaderMaterial = _video_player.material as ShaderMaterial
	if chroma_key_shader != null:
		if material == null:
			material = ShaderMaterial.new()
		material.shader = chroma_key_shader
		_video_player.material = material
	if material == null:
		return
	material.set_shader_parameter("key_color", chroma_key_color)
	material.set_shader_parameter("similarity", chroma_key_similarity)
	material.set_shader_parameter("smoothness", chroma_key_smoothness)
	material.set_shader_parameter("spill_suppression", chroma_key_spill_suppression)


## 按开关申请一次对局暂停。未开启暂停、没有注入服务或已经持有时都不重复申请。
func _acquire_pause() -> void:
	if not pause_gameplay_while_playing or _pause_service == null or _pause_token >= 0:
		return
	_pause_token = _pause_service.acquire_pause(PAUSE_REASON)


## 释放组件自己持有的暂停令牌。未持有令牌时不做任何事，重复调用安全。
func _release_pause() -> void:
	if _pause_token < 0:
		return
	if _pause_service != null:
		_pause_service.release_pause(_pause_token)
	_pause_token = -1


## 终止仍在运行的淡入淡出补间。补间对象由引擎回收，这里只保证新旧补间不会互相覆盖透明度。
func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
