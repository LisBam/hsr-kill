extends Node

## 验证正式启动入口先提供轻量反馈，并最终切换到完整首页；不提前引用正式场景或规则类。

## 启动等待上限（微秒）；30秒兼容调试版首次解析，超时代表启动链断裂而非性能阈值。
const TIMEOUT_USEC: int = 30000000


## 延迟进入测试，使自动加载节点与测试根先完成装配。
func _ready() -> void:
	call_deferred("_run")


## 从项目配置读取真实入口，测量首屏就绪与正式首页就绪并检查未创建对局。
func _run() -> void:
	# 采样起点；不包含Godot进程与自动加载节点本身的初始化。
	var started: int = Time.get_ticks_usec()
	# 项目配置中的真实入口；测试必须能发现入口被误改回重型场景。
	var entry_path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	if entry_path != "res://scenes/game_bootstrap.tscn":
		_fail("启动配置没有使用轻量入口")
		return
	# 轻量入口资源；动态加载避免测试脚本预热正式首页。
	var packed: PackedScene = load(entry_path) as PackedScene
	# 独立启动实例；将SceneTree当前场景指向它，让原测试节点作为根级监视器保留。
	var bootstrap: Control = packed.instantiate() as Control
	get_tree().root.add_child(bootstrap)
	get_tree().current_scene = bootstrap
	await get_tree().process_frame
	# 首个反馈帧耗时；只描述测试进程内的首屏，不能充当完整设备冷启动时间。
	var feedback_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	if not bootstrap.is_visible_in_tree() or not bootstrap.has_node("%BootStatus"):
		_fail("首帧缺少可见启动反馈")
		return
	while get_tree().current_scene == bootstrap or get_tree().current_scene == null:
		if Time.get_ticks_usec() - started > TIMEOUT_USEC:
			_fail("正式首页加载超时")
			return
		await get_tree().process_frame
	# 实际正式首页；路径和未开局状态均必须符合启动契约。
	var main: Node = get_tree().current_scene
	if main.scene_file_path != "res://scenes/main.tscn" or main.get_node("MatchController").get("state") != null:
		_fail("启动没有进入未开局的正式首页")
		return
	await get_tree().process_frame
	print("GAME_BOOTSTRAP_PASS ", JSON.stringify({"feedback_ms":feedback_ms, "main_ready_ms":(Time.get_ticks_usec() - started) / 1000.0}))
	await GameDatabase.wait_until_ready()
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## 失败以非零退出码交给命令行，不依赖图形调试器断点。
func _fail(message: String) -> void:
	printerr("GAME_BOOTSTRAP_FAIL: ", message)
	get_tree().quit(1)
