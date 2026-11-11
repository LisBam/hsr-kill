extends Control

## 轻量启动入口；首屏不引用正式牌桌、规则脚本或原画，先显示反馈，再由引擎后台加载正式场景。
## 只管理启动资源和场景移交，不等待数据库或创建对局；数据库继续通过自己的就绪信号发布目录。

## 正式首页场景路径；以字符串保存避免preload重新引入启动阻塞，通常无需运行时修改。
@export_file("*.tscn") var main_scene_path: String = "res://scenes/main.tscn"

## 启动状态文字；加载失败时保留可读错误，避免无反馈黑屏。
@onready var _status_label: Label = %BootStatus

## 资源加载进度条；0至100只表示场景资源准备进度，不代表对局或数据库的加载百分比。
@onready var _progress_bar: ProgressBar = %BootProgress


## 先留出首帧绘制机会，再提交后台场景请求；启动界面本身始终可响应系统窗口事件。
func _ready() -> void:
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	if ResourceLoader.load_threaded_request(main_scene_path, "PackedScene") != OK:
		_status_label.text = "游戏加载失败，请重新启动游戏"
		return
	set_process(true)


## 每帧只查询引擎任务状态；确认完成后才领取资源，防止threaded_get退化为主线程等待。
func _process(_delta: float) -> void:
	# 引擎返回的资源准备比例；任务开始时数组可能为空。
	var progress: Array = []
	# 当前后台任务状态；轮询不会等待磁盘或脚本解析结束。
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(main_scene_path, progress)
	if not progress.is_empty():
		_progress_bar.value = float(progress[0]) * 100.0
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	set_process(false)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_status_label.text = "游戏加载失败，请重新启动游戏"
		return
	# 已完整准备的正式场景；场景节点仍由主线程创建，后台线程不操作场景树。
	var packed: PackedScene = ResourceLoader.load_threaded_get(main_scene_path) as PackedScene
	if packed == null or get_tree().change_scene_to_packed(packed) != OK:
		_status_label.text = "无法进入游戏，请重新启动游戏"
