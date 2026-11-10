extends Node

## 轻量状态文字过渡；只在正文改变时触发，主题重绘和Tween自己的重绘不重复播放。

## 文字过渡时长；默认0.16秒，不隐藏当前提示，可运行时调整。
@export_range(0.0, 0.4, 0.01) var duration: float = 0.16
## 文字入场距离；默认3像素，仅绘制偏移，不影响交互区排版。
@export_range(0.0, 8.0, 1.0) var travel: float = 3.0
## 已呈现的正文；初始为空，首次加载直接呈现避免启动时整桌闪烁。
var _last_text: String = ""
## 标签宿主；只支持原生Label，不读取快照或控制器。
var _label: Label
## 单个文字位移轨道；再次变更时从最新提示重新进入。
var _tween: Tween


## 订阅原生重绘；不用逐帧轮询，字段变化后Godot会主动安排一次draw。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = get_parent() as Label
	if _label == null:
		return
	_last_text = _label.text
	_label.offset_transform_enabled = true
	_label.offset_transform_visual_only = true
	_label.draw.connect(_on_drawn)
	_label.visibility_changed.connect(_on_visibility_changed)


## 只动画文字位置；不修改文本、颜色或透明度，错误提示从第一帧就完整可读。
func _on_drawn() -> void:
	if _last_text == _label.text:
		return
	_last_text = _label.text
	_reset()
	if _last_text.is_empty() or not _label.is_visible_in_tree() or duration <= 0.0:
		return
	_label.offset_transform_position = Vector2(0.0, travel)
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "offset_transform_position", Vector2.ZERO, duration)


## 标签隐藏时复位；回到牌桌不会沿用上一阶段的位移。
func _on_visibility_changed() -> void:
	if not _label.is_visible_in_tree():
		_reset()


## 清理本组件唯一轨道；不触碰其他组件的缩放或颜色。
func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(_label):
		_label.offset_transform_position = Vector2.ZERO


## 退树时取消有限Tween，避免已释放文字保留轨道。
func _exit_tree() -> void:
	_reset()
