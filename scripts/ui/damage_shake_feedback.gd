class_name DamageShakeFeedback
extends Node

## 武将牌受伤抖动组件。组件只修改传入牌面节点的临时位置，并在动画结束后恢复原位，不读取体力或规则状态。

## 单次抖动的最大水平位移；默认7像素足以提供受击感，同时不会越过相邻座位安全间距，运行时通常无需动态修改。
@export_range(1.0, 24.0, 0.5) var shake_amplitude: float = 7.0

## 单次抖动的总持续时间；默认0.24秒提供清晰且不阻塞操作的反馈，运行时可按界面风格调整。
@export_range(0.05, 1.0, 0.01) var shake_duration: float = 0.24

## 抖动过程中的左右位移段数；默认6段形成三次往返，数值越高频率越密但总时长不变。
## 当前受伤反馈固定只执行1次冲击位移后回正，不再进行左右往返抖动。
@export_range(1, 1, 1) var shake_step_count: int = 1

## 当前正在播放的位置补间；重复受伤时先停止旧补间，避免多个动画争用同一牌面位置。
var _shake_tween: Tween

## 当前被抖动的武将牌节点；动画完成或重播后用于精确恢复原始位置。
var _target: Node2D

## 当前动画开始前的牌面原始局部位置；结束时必须恢复该值，不能把反馈偏移写入布局。
var _rest_position: Vector2 = Vector2.ZERO

## 本组件累计播放次数；只用于界面回归和调试观察，不参与任何玩法逻辑。
var _playback_count: int = 0


## 对指定武将牌播放一次逐步衰减的水平抖动；target 通常为 PlayerTargetView 根节点。
func play(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_reset_active_target()
	_target = target
	_rest_position = target.position
	_playback_count += 1
	# 每段补间时长；至少按1段计算，避免异常检查器数据产生除零。
	var step_duration: float = shake_duration / float(maxi(shake_step_count + 1, 1))
	_shake_tween = create_tween()
	_shake_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 当前抖动段索引；每段交替方向并按索引递减幅度。
	for step_index: int in range(shake_step_count):
		# 当前幅度衰减比例；从1逐步降到接近0，使反馈自然回稳而不是突然停止。
		var decay: float = 1.0 - float(step_index) / float(maxi(shake_step_count, 1))
		# 当前水平方向；偶数段向右、奇数段向左，形成稳定往返节奏。
		var direction: float = 1.0 if step_index % 2 == 0 else -1.0
		_shake_tween.tween_property(target, "position", _rest_position + Vector2(shake_amplitude * decay * direction, 0.0), step_duration)
	_shake_tween.tween_property(target, "position", _rest_position, step_duration)
	_shake_tween.finished.connect(_on_shake_finished)


## 返回累计播放次数；自动化测试可确认体力下降只触发一次反馈。
func get_playback_count() -> int:
	return _playback_count


## 停止旧补间并恢复旧目标位置；连续伤害会从稳定布局原点开始新一轮反馈。
func _reset_active_target() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	if _target != null and is_instance_valid(_target):
		_target.position = _rest_position
	_shake_tween = null
	_target = null


## 动画自然完成后清理引用；目标位置已经由补间最后一段恢复到原位。
func _on_shake_finished() -> void:
	_shake_tween = null
	_target = null
