extends Node

## 牌桌纯表现装配器。接入静态和运行时新增按钮，不改变输入协议、技能可用性或业务显隐。
## 排除MainMenu及Node2D实体牌；牌面和选中态由各自组件管理，避免争抢拖牌、飞牌与悬停缩放。

## 复用原生按钮反馈；只有视觉偏移，不更改容器几何或发射pressed。
const BUTTON_MOTION: Script = preload("res://scripts/ui/menu_button_motion.gd")
## 状态文字反馈；按实际正文变化触发，没有逐帧扫描。
const TEXT_MOTION: Script = preload("res://scripts/ui/ui_text_motion.gd")
## 面板运动组件；全局只用于显隐明确的HUD分组，不接管关闭动作。
const SURFACE_MOTION: Script = preload("res://scripts/ui/ui_surface_motion.gd")
## 原生范围控件样式；统一滑条和内置滚动条，不修改玩家设置值。
const RANGE_STYLE: Script = preload("res://scripts/ui/ui_range_style.gd")
## HUD文字路径；允许检查器增减需要轻量反馈的Label，运行时通常不调整。
@export var text_paths: Array[NodePath] = [NodePath("%CenterTurnLabel"), NodePath("%CenterPhaseLabel"), NodePath("%InteractionGuideLabel"), NodePath("%SelectionLabel"), NodePath("%ErrorLabel")]
## HUD可见性分组路径；只做淡入，避免抬动包含实体牌的区域。
@export var surface_paths: Array[NodePath] = [NodePath("InteractionPanel"), NodePath("SkillBar")]
## 本次场景的根节点；不查找全局单例，测试场景可独立挂载。
var _scope: Node
## 当前场景局外子树；由菜单自身装配器拥有，不重复添加战斗反馈。
var _menu: Node
## 待装配节点弱引用；每帧合并一次新增事件，释放的节点自动忽略。
var _pending: Array[WeakRef] = []
## 合并任务开关；默认false，一次批量建技能或选项只安排一次延迟处理。
var _flush_queued: bool = false
## 已装配的范围控件弱引用；只在主题变化时迭代，动态页面释放后自动淘汰。
var _ranges: Array[WeakRef] = []


## 等父场景ready完成后挂载反馈，保证动态窗口已完成自身初始化。
func _ready() -> void:
	_scope = get_parent()
	_menu = _scope.get_node_or_null("MainMenu")
	call_deferred("_initialize")


## 首次只遍历一次现有树；之后仅处理node_added事件，不持续扫描牌桌。
func _initialize() -> void:
	_bind_branch(_scope)
	get_tree().node_added.connect(_on_node_added)
	GameSettings.ui_style_changed.connect(_on_style_changed)
	for path: NodePath in text_paths:
		# 显式登记的状态文字；缺失路径安全跳过，保持组件可复用。
		var label: Label = _scope.get_node_or_null(path) as Label
		if label != null and not label.has_node("TextMotion"):
			# 独立文字反馈；不挂到RichText技能原文上。
			var motion: Node = TEXT_MOTION.new()
			motion.name = "TextMotion"
			label.add_child(motion)
	for path: NodePath in surface_paths:
		SURFACE_MOTION.attach(_scope.get_node_or_null(path) as Control, "fade")


## 仅初次递归；正式Node2D牌面和已有局外组件保留自己的表现所有权。
func _bind_branch(node: Node) -> void:
	if _excluded(node):
		return
	_bind_node(node)
	for child: Node in node.get_children(true):
		_bind_branch(child)


## 检查完整祖先链；运行时动态加入牌面的透明输入按钮也不能被误绑定。
func _excluded(node: Node) -> bool:
	# 祖先游标；遇到本装配器、菜单或实体牌即停止。
	var cursor: Node = node
	while cursor != null and cursor != _scope:
		if cursor == self or cursor == _menu or cursor is Node2D or cursor is OpportunityCardView:
			return true
		cursor = cursor.get_parent()
	return cursor != _scope


## 装配单个原生按钮；重复调用不创建第二套反馈，不覆盖业务主题。
func _bind_node(node: Node) -> void:
	if (node is Slider or node is ScrollBar) and not node.has_meta("battle_range_style"):
		node.set_meta("battle_range_style", true)
		_ranges.append(weakref(node))
		RANGE_STYLE.apply(node as Control)
	if node is Button and not node.has_node("BattleButtonMotion"):
		# 附属绘制组件；原按钮继续独立发送按压与焦点信号。
		var motion: Control = BUTTON_MOTION.new()
		motion.name = "BattleButtonMotion"
		node.add_child(motion)


## 新节点只登记弱引用；不在node_added阶段修改尚未ready的控件。
func _on_node_added(node: Node) -> void:
	if not (node is Button or node is Slider or node is ScrollBar) or _excluded(node):
		return
	_pending.append(weakref(node))
	if not _flush_queued:
		_flush_queued = true
		call_deferred("_flush")


## 一批新选项共用一次装配任务；已被快照替换的按钮不会被访问。
func _flush() -> void:
	_flush_queued = false
	for reference: WeakRef in _pending:
		# 尚存活的候选按钮；只有仍在当前树内才挂载反馈。
		var node: Node = reference.get_ref() as Node
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.is_inside_tree() and not _excluded(node):
			_bind_node(node)
	_pending.clear()


## 主题信号由设置服务发出；只刷新已绑定范围控件，不重新遍历整张牌桌。
func _on_style_changed(_style_id: String) -> void:
	# 仍然存活的弱引用；用同一遍刷新顺便清理旧页面，不保留已释放候选。
	var live_ranges: Array[WeakRef] = []
	for reference: WeakRef in _ranges:
		# 当前范围控件；失效引用无副作用地跳过。
		var control: Control = reference.get_ref() as Control
		if is_instance_valid(control) and not control.is_queued_for_deletion():
			RANGE_STYLE.apply(control)
			live_ranges.append(reference)
	_ranges = live_ranges
