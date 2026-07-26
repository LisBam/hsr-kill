class_name MatchReplayPlaybackDriver
extends Node

## 对局回放重演驱动器。组件按录制时间差顺序派发回放步骤，使牌桌像收到真实对局广播一样
## 依次收到快照与日志，从而在正式对局界面上完整重演一局。组件只负责步骤节奏与速度倍率，
## 不理解快照语义、不渲染任何界面、不读取 GameState，也不修改任何规则状态；
## 牌桌通过信号消费步骤，重演期间的输入封锁与界面切换由牌桌与回放覆盖层负责。

## 派发一份观察者快照步骤时发出；快照为录制端当时收到的只读裁剪字典。
signal snapshot_step_ready(snapshot: Dictionary)

## 派发一条对局日志步骤时发出；正文与录制端“记录”面板当时收到的完全一致。
signal log_step_ready(message: String)

## 派发一步目标线类表现步骤时发出；字典只含稳定玩家 ID 与名称，坐标由牌桌按重演布局解析。
signal presentation_step_ready(presentation: Dictionary)

## 全部步骤派发完毕时发出；牌桌据此提示“回放播放完毕”，驱动器停止帧处理。
signal playback_finished

## 相邻步骤的最大等待毫秒数；录制间隔超过该值时按上限播放，跳过真实对局中的长思考停顿。
@export var maximum_step_gap_msec: int = 2000

## 当前速度倍率；1.0为按录制节奏原速重演，只允许加速，由回放覆盖层的速度选择驱动。
var _speed_multiplier: float = 1.0

## 当前载入回放的全部步骤；重演期间常驻内存，播放结束或停止时释放。
var _steps: Array[Dictionary] = []

## 下一个待派发的步骤索引；从0开始顺序推进，重演不支持回退或跳转。
var _next_step_index: int = 0

## 自到达当前步骤以来累计的毫秒数；乘以速度倍率后与下一步的录制间隔比较。
var _accumulated_msec: float = 0.0

## 是否正在重演；开始播放置真，全部步骤派发完毕或外部停止后置假并关闭帧处理。
var _playing: bool = false


## 常态关闭帧处理；只有重演进行中才逐帧推进，空闲驱动器不产生任何轮询开销。
func _ready() -> void:
	set_process(false)


## 开始重演一份回放步骤流；立即派发首个步骤，之后按录制时间差与速度倍率逐帧推进。
## 返回是否成功开始；空步骤流拒绝开始。
func start_playback(steps: Array[Dictionary]) -> bool:
	if steps.is_empty():
		return false
	stop_playback()
	_steps = steps
	_next_step_index = 0
	_accumulated_msec = 0.0
	_playing = true
	set_process(true)
	# 立即派发第一个步骤；玩家进入重演即看到开局状态，不等待首个录制间隔。
	_dispatch_step(0)
	_next_step_index = 1
	_finish_if_completed()
	return true


## 停止重演并释放步骤内存；退出回放与重复开始共用本入口，停止不派发剩余步骤。
func stop_playback() -> void:
	_playing = false
	set_process(false)
	_steps = []
	_next_step_index = 0
	_accumulated_msec = 0.0


## 当前是否正在重演；覆盖层与测试据此断言驱动器状态。
func is_playing() -> bool:
	return _playing


## 设置速度倍率；限制在1倍及以上，回放只允许加速不允许减速或倒退。
func set_speed_multiplier(speed_multiplier: float) -> void:
	_speed_multiplier = maxf(speed_multiplier, 1.0)


## 返回当前速度倍率；覆盖层重建速度选择时读取。
func get_speed_multiplier() -> float:
	return _speed_multiplier


## 帧驱动；按录制时间差与速度倍率推进，同一帧允许连续派发多个已到期步骤。
func _process(delta: float) -> void:
	if not _playing:
		return
	_accumulated_msec += delta * 1000.0 * _speed_multiplier
	while _playing and _next_step_index < _steps.size():
		# 下一步与当前步的录制间隔毫秒；超过上限时按上限等待，跳过长时间思考停顿。
		var step_gap_msec: int = _get_step_gap_msec(_next_step_index)
		if _accumulated_msec < float(step_gap_msec):
			break
		_accumulated_msec -= float(step_gap_msec)
		_dispatch_step(_next_step_index)
		_next_step_index += 1
	_finish_if_completed()


## 返回指定步骤与其前一步的录制间隔毫秒；用于自动播放节奏，间隔按上限截断。
func _get_step_gap_msec(step_index: int) -> int:
	if step_index <= 0 or step_index >= _steps.size():
		return 0
	return clampi(int(_steps[step_index].get("t", 0)) - int(_steps[step_index - 1].get("t", 0)), 0, maximum_step_gap_msec)


## 派发单个步骤；快照、日志与表现分别走独立信号，未知步骤类型静默跳过保证向前兼容。
func _dispatch_step(step_index: int) -> void:
	if step_index < 0 or step_index >= _steps.size():
		return
	# 当前步骤字典；k 为步骤类型，d 为快照、日志或表现数据。
	var step: Dictionary = _steps[step_index]
	if str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_SNAPSHOT:
		snapshot_step_ready.emit(step.get("d", {}) as Dictionary)
	elif str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_LOG:
		log_step_ready.emit(str(step.get("d", "")))
	elif str(step.get("k", "")) == MatchReplayRecorder.STEP_KIND_PRESENTATION:
		presentation_step_ready.emit(step.get("d", {}) as Dictionary)


## 全部步骤派发完毕时收尾；关闭帧处理并发出完成信号，步骤内存保留到外部停止时释放。
func _finish_if_completed() -> void:
	if _playing and _next_step_index >= _steps.size():
		_playing = false
		set_process(false)
		playback_finished.emit()
