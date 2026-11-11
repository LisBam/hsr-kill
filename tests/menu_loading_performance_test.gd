extends Node

## 使用正式主场景测量首页、形象页与图鉴的冷访问和缓存访问；无头结果只代表 CPU，不包含 GPU 上传耗时。
## 运行本场景时输出 MENU_PERFORMANCE JSON，便于同设备、同帧率上限比较；不修改玩家持久化设置。

## 每个页面的采样帧数；120 帧覆盖首屏创建与邻屏预取，运行时无需修改。
const SAMPLE_FRAMES: int = 120


## 从空场景进入正式首页，避免预先加载正式场景造成冷访问测量失真。
func _ready() -> void:
	call_deferred("_run")


## 采样首次装配、数据库就绪与页面切换，最后释放主场景并退出独立测试进程。
func _run() -> void:
	# 全流程起点；同时记录脚本/场景加载与节点装配的 CPU 时间。
	var started: int = Time.get_ticks_usec()
	# 玩家实际启动场景；动态加载使测试资源自身不提前预热首页。
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# 正式牌桌与首页实例；完整保留实际启动路径。
	var main: Control = packed.instantiate() as Control
	add_child(main)
	# 首次装配耗时；在首个绘制机会前结束的同步工作全部计入。
	var startup_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	await get_tree().process_frame
	# 首帧时数据库状态；用于发现隐藏组件同步查询导致的启动等待。
	var database_ready_at_first_frame: bool = GameDatabase.is_database_ready()
	await GameDatabase.wait_until_ready()
	# 正式主菜单；页面操作沿用玩家按钮调用的业务入口。
	var menu: MainMenu = main.get_node("%MainMenu") as MainMenu
	# 分类性能结果；每项包含同步打开时间和后续最慢帧间隔。
	var samples: Dictionary = {}
	for page: String in ["online", "cards", "online", "cards"]:
		# 当前样本名；后半轮验证缓存页面再次访问。
		var sample_name: String = page if not samples.has(page) else page + "_cached"
		# 打开操作起点；同步磁盘读取和目录重建会反映在该数值中。
		var opened: int = Time.get_ticks_usec()
		if page == "online":
			menu.call("_open_online_settings")
		else:
			menu.call("_open_all_cards")
		# 打开入口同步耗时；异步准备由后续帧采样继续覆盖。
		var open_ms: float = (Time.get_ticks_usec() - opened) / 1000.0
		# 前一帧时间；覆盖操作触发后的首帧。
		var previous: int = opened
		# 采样窗口内最慢帧；含引擎帧率上限等待，应只在相同启动参数下比较。
		var maximum_ms: float = 0.0
		for frame_index: int in range(SAMPLE_FRAMES):
			await get_tree().process_frame
			# 当前帧时间；帧间隔比只统计创建函数更能发现页面打开后的卡顿。
			var current: int = Time.get_ticks_usec()
			maximum_ms = maxf(maximum_ms, (current - previous) / 1000.0)
			previous = current
		samples[sample_name] = {"open_ms":open_ms, "max_frame_ms":maximum_ms}
	print("MENU_PERFORMANCE ", JSON.stringify({"startup_ms":startup_ms, "database_ready_at_first_frame":database_ready_at_first_frame, "samples":samples}))
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit()
