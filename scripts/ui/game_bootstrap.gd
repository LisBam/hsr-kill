extends Control

## 轻量启动入口；首屏不引用正式牌桌、规则脚本或原画，先显示反馈，再由引擎后台加载正式场景。
## 只管理启动资源和场景移交，不等待数据库或创建对局；数据库继续通过自己的就绪信号发布目录。

## 正式首页场景路径；以字符串保存避免preload重新引入启动阻塞，通常无需运行时修改。
@export_file("*.tscn") var main_scene_path: String = "res://scenes/main.tscn"

## 启动进度轨道色；固定纸面中性色，加载主题前即可使用，运行时无需修改。
## 默认深灰轨道避免启动时闪现浅色，颜色独立于资源加载进度。
@export var progress_track_color: Color = Color("303840")
## 启动进度填充色；低饱和金色与首页一致，运行时无需修改。
@export var progress_fill_color: Color = Color("b59a66")
## 进度条圆角半径；默认3逻辑像素，只影响绘制，运行时无需修改。
@export_range(0, 12, 1) var progress_corner_radius: int = 3

## 启动背景色；默认深石墨与首页同色系，不依赖主场景加载，运行时无需修改。
@export var background_color: Color = Color("191e24")
## 启动标题色；默认暖白保证深底对比度，运行时无需修改。
@export var title_color: Color = Color("e3ddd1")
## 启动状态色；默认柔和暖灰区分标题层级，运行时无需修改。
@export var status_color: Color = Color("bbb7ae")

## 启动状态文字；加载失败时保留可读错误，避免无反馈黑屏。
@onready var _status_label: Label = %BootStatus

## 资源加载进度条；0至100只表示场景资源准备进度，不代表对局或数据库的加载百分比。
@onready var _progress_bar: ProgressBar = %BootProgress


## 先留出首帧绘制机会，再提交后台场景请求；启动界面本身始终可响应系统窗口事件。
func _ready() -> void:
	($Background as ColorRect).color = background_color
	($Center/Content/Title as Label).add_theme_color_override("font_color", title_color)
	_status_label.add_theme_color_override("font_color", status_color)
	# 启动入口使用轻量样式工厂；不加载牌桌、原画或规则资源。
	var progress_track: StyleBoxFlat = StyleBoxFlat.new()
	progress_track.bg_color = progress_track_color
	progress_track.set_corner_radius_all(progress_corner_radius)
	_progress_bar.add_theme_stylebox_override("background", progress_track)
	# 金色进度填充；宽度仍由后台场景加载进度驱动，颜色不影响数值。
	var progress_fill: StyleBoxFlat = StyleBoxFlat.new()
	progress_fill.bg_color = progress_fill_color
	progress_fill.set_corner_radius_all(progress_corner_radius)
	_progress_bar.add_theme_stylebox_override("fill", progress_fill)
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
