extends Node

## 字体颜色统一回归测试。实例化正式主场景后遍历全部静态文本控件，任何 Label、RichTextLabel、CheckBox 缺失主题字体色覆盖即判失败。
## 该测试保证主菜单模式卡、设置面板、局内菜单与联机大厅等静态界面文字始终应用统一主题色，防止新增控件回退场景默认白字。

## 主场景完成主菜单和动态节点构建前等待的帧数；与既有界面回归测试保持一致，覆盖控件初始化与主题刷新。
const SETTLE_FRAME_COUNT: int = 6

## 审计专用设置文件；隔离写盘避免污染玩家正式配置。
const TEST_SETTINGS_FILE_PATH: String = "user://font_color_audit_settings.cfg"


## 延迟执行审计，保证测试根节点已进入场景树。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


## 实例化主场景并遍历文本控件，缺失 font_color 覆盖的静态文本控件清单非空时测试失败。
func _run() -> void:
	if GameSettings != null:
		GameSettings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)
	# 正式主场景资源；审计必须覆盖玩家实际运行的节点结构。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		printerr("FONT_COLOR_AUDIT_FAIL main_scene_load")
		get_tree().quit(1)
		return
	# 正式主场景实例；作为测试根节点子节点运行完整初始化流程。
	var main_instance: Control = main_scene.instantiate() as Control
	# 阻止规则对局与AI异步任务启动；1人配置会被控制器拒绝，仅保留界面初始化。
	var match_controller: Node = main_instance.get_node("MatchController")
	match_controller.set("default_player_count", 1)
	add_child(main_instance)
	for _frame_index: int in range(SETTLE_FRAME_COUNT):
		await get_tree().process_frame
	# 缺失覆盖的节点清单；遍历后统一输出便于日志检索。
	var missing_lines: Array[String] = []
	_collect_missing(main_instance, main_instance, missing_lines)
	for line: String in missing_lines:
		printerr(line)
	if not missing_lines.is_empty():
		printerr("FONT_COLOR_AUDIT_FAIL missing_theme_font_color:%d" % missing_lines.size())
		get_tree().quit(1)
		return
	print("FONT_COLOR_AUDIT_PASS")
	get_tree().quit(0)


## 递归收集缺失主题字体色覆盖的文本控件；Label 与 CheckBox 检查 font_color，RichTextLabel 检查 default_color。
func _collect_missing(node: Node, root: Node, missing_lines: Array[String]) -> void:
	if node is Label:
		var label: Label = node as Label
		if not label.has_theme_color_override("font_color"):
			missing_lines.append("MISSING Label %s | text=%s" % [str(root.get_path_to(node)), label.text.replace("\n", "\\n")])
	elif node is RichTextLabel:
		var rich_label: RichTextLabel = node as RichTextLabel
		if not rich_label.has_theme_color_override("default_color"):
			missing_lines.append("MISSING RichTextLabel %s" % str(root.get_path_to(node)))
	elif node is CheckBox or node is CheckButton:
		var check: Control = node as Control
		if not check.has_theme_color_override("font_color"):
			missing_lines.append("MISSING %s %s | text=%s" % [node.get_class(), str(root.get_path_to(node)), str(node.get("text"))])
	for child: Node in node.get_children():
		_collect_missing(child, root, missing_lines)
