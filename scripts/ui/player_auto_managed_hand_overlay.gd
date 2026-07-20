class_name PlayerAutoManagedHandOverlay
extends Control

## 本地玩家托管时覆盖手牌栏的独立表现组件。它只管理黑色滤镜、动态文字与鼠标拦截，不读取规则或网络状态。

## 玩家点击“托管中...”文字时发出结束手动托管意图；父级桌面负责按最新权威快照决定是否允许提交关闭动作。
signal cancel_requested

## 托管动态省略号的切换间隔秒数；默认0.45秒使“.”、“..”、“...”保持可辨识的循环节奏，运行时可在检查器调整。
@export_range(0.1, 2.0, 0.05) var dot_cycle_interval_seconds: float = 0.45

## 黑色滤镜透明度；默认0.76确保手牌仍可辨认轮廓，同时明确表达当前不能操作，运行时通常无需修改。
@export_range(0.0, 1.0, 0.01) var shade_alpha: float = 0.76

## 黑色滤镜节点；完整覆盖本组件矩形，只负责视觉遮罩并忽略鼠标事件。
@onready var _shade: ColorRect = $Shade

## 托管文字节点；显示固定中文和动态省略号，始终处于滤镜上方。
@onready var _status_label: Label = $StatusLabel

## 当前是否启用托管覆盖；true 时组件拦截手牌栏鼠标输入，false 时完全忽略输入。
var _auto_managed: bool = false

## 距离下一次省略号变化已累计的秒数；仅在托管启用期间递增，关闭后重置保证再次开启从单点开始。
var _dot_elapsed_seconds: float = 0.0

## 当前显示的省略号数量；范围1至3，默认1以输出“托管中.”。
var _dot_count: int = 1


## 初始化滤镜外观和始终处理模式；离线日志暂停期间文字动画也应继续表达托管状态。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade.color = Color(0.0, 0.0, 0.0, shade_alpha)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_label.gui_input.connect(_on_status_label_gui_input)
	configure(false)


## 写入当前本地玩家的托管状态；启用时显示遮罩并阻断手牌输入，关闭时立即恢复原手牌栏。
func configure(auto_managed: bool) -> void:
	_auto_managed = auto_managed
	visible = _auto_managed
	mouse_filter = Control.MOUSE_FILTER_STOP if _auto_managed else Control.MOUSE_FILTER_IGNORE
	# 隐藏状态不需要接收每帧回调；重新开启托管时恢复处理以维持原0.45秒文字动画。
	set_process(_auto_managed)
	if not _auto_managed:
		_dot_elapsed_seconds = 0.0
		_dot_count = 1
	_update_status_text()


## 在托管开启时循环更新“托管中.”、“托管中..”、“托管中...”三个文本状态。
func _process(delta: float) -> void:
	if not _auto_managed:
		return
	_dot_elapsed_seconds += delta
	if _dot_elapsed_seconds < dot_cycle_interval_seconds:
		return
	_dot_elapsed_seconds = fmod(_dot_elapsed_seconds, dot_cycle_interval_seconds)
	_dot_count = _dot_count % 3 + 1
	_update_status_text()


## 用当前点数刷新可见文字；该函数不分配规则状态，便于测试直接验证三个循环状态。
func _update_status_text() -> void:
	if _status_label == null:
		return
	_status_label.text = "托管中" + ".".repeat(_dot_count)


## 接收“托管中...”文字区域的鼠标输入；只在左键按下时发出一次取消意图，其他遮罩区域继续单纯阻断输入。
func _on_status_label_gui_input(event: InputEvent) -> void:
	if not _auto_managed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		cancel_requested.emit()
