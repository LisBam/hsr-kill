class_name YinlangWindowsLayer
extends Control

## 可取消的面板入场；只订阅显隐，不延迟关闭、提交或权威状态更新。
const SURFACE_MOTION: Script = preload("res://scripts/ui/ui_surface_motion.gd")

## 局内外壳样式；只组织面板与按钮层次，不改变规则语义色和内容尺寸。
const BATTLE_STYLE: Script = preload("res://scripts/ui/battle_surface_style.gd")

## 银狼专属窗口层：承载【注入】的组合窗口与【以太】的造牌窗口，二者共用同一套高科技黑蓝外观。
##
## 【为什么单独做一层】这两种窗口的合法答案无法预先枚举（23 × 24 种组合、自由文本牌名），
## 因此不能复用通用选择面板的「候选列表 + 确定」形态。窗口层只负责遮罩、外框、标题与视图切换，
## 具体交互分别交给 `YinlangComposeView` 与 `YinlangMintView`，规则判定一律不在界面里进行。
##
## 【层级】185：高于机缘弹窗（180）与通用选牌层（150），低于主菜单（400）与局内菜单（500）。
## 这样银狼窗口一定盖住其他规则窗口，但不会挡住玩家主动打开的菜单。

## 玩家完成或取消窗口时发出；牌桌负责转成统一 PlayerAction。
signal choice_submitted(request_id: int, control_id: String, confirmed: bool)

## 窗口绘制层级；数值来自《界面与交互》文档的层级表，修改会破坏与其它弹窗的遮挡关系。
const MODAL_Z_INDEX: int = 185

## 组合窗口的标题；正文由请求上下文与静态数据池共同决定。
## 本窗口没有副标题：两栏各只有两个候选，按钮本身已经说明了要做什么，再写一行说明只是重复信息。
const COMPOSE_TITLE: String = "注入"

## 造牌窗口的标题与副标题。
const MINT_TITLE: String = "以太"
const MINT_SUBTITLE: String = "创造一张卡牌：牌名不可与已有牌相同"

## 全屏遮罩；阻止窗口显示期间误触牌桌其他交互。
var _shade: ColorRect

## 全屏居中容器；让固定尺寸的主框始终居中，窗口尺寸变化不影响遮罩铺满。
var _center: CenterContainer

## 窗口主框；使用固定最小尺寸承载两个视图。
var _frame: PanelContainer

## 标题标签；按窗口种类切换文本。
var _title_label: Label

## 副标题标签；按窗口种类切换文本。
var _subtitle_label: Label

## 当前视图容器；每次显示请求时整体重建，避免上一个视图的状态残留。
var _view_holder: MarginContainer

## 当前显示的组合视图；非组合窗口时为 null。
var _compose_view: YinlangComposeView

## 当前显示的造牌视图；非造牌窗口时为 null。
var _mint_view: YinlangMintView

## 当前请求序号；提交时原样回传，权威端据此核对请求身份。
var _request_id: int = -1


## 初始化暂停可用的模态层；规则核心暂停 SceneTree 时仍允许玩家操作窗口。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = MODAL_Z_INDEX
	visible = false
	_build_nodes()
	refresh_ui_style()
	SURFACE_MOTION.attach(_frame, "modal")


## 建立遮罩、外框与内容骨架；节点结构在代码中一次性建立，避免为纯代码层维护场景文件。
func _build_nodes() -> void:
	_shade = ColorRect.new()
	_shade.name = "Shade"
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.custom_minimum_size = Vector2(760.0, 420.0)
	_center.add_child(_frame)
	# 外框内容边距；与其它弹窗保持相近的呼吸空间。
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_frame.add_child(margin)
	# 纵向内容；标题、副标题与视图依次排列。
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	content.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	content.add_child(_subtitle_label)
	_view_holder = MarginContainer.new()
	_view_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_view_holder)


## 按当前活动 UI 风格刷新遮罩、外框与标题配色；科技黑蓝语义只用于本层。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_shade.color = BattleUIStyle.get_color("shade")
	# 外框样式；黑蓝底 + 亮青描边，形成「高科技面板」的第一层观感。
	var frame_style: StyleBoxFlat = BATTLE_STYLE.make_panel(BattleUIStyle.get_color("tech_panel"), BattleUIStyle.get_color("tech_accent"), 2, 10)
	frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.78)
	frame_style.shadow_size = 16
	frame_style.shadow_offset = Vector2(0.0, 6.0)
	_frame.add_theme_stylebox_override("panel", frame_style)
	_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("tech_accent"))
	_subtitle_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	if _compose_view != null:
		_compose_view.refresh_ui_style()
	if _mint_view != null:
		_mint_view.refresh_ui_style()


## 按请求上下文显示对应窗口；上下文缺少窗口标记时立即关闭，避免留下无内容的空框。
##
## 【同一条请求重复显示时保留视图】提交被权威端拒绝（牌名重名、组合键非法等）后请求依然存在，
## 窗口需要重新显示。此时**不重建视图**，玩家已经输入的内容（例如牌名）得以保留，
## 只需要改掉被拒绝的那一项再提交即可。只有请求序号变化时才重建。
func show_request(choice_data: Dictionary) -> void:
	# 请求上下文；窗口种类与业务参数都在其中，界面不读取规则状态。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	# 窗口种类标记；由银狼技能写入，是界面分流的唯一依据。
	var window_kind: String = str(context.get(MatchController.YINLANG_WINDOW_CONTEXT_KEY, ""))
	if window_kind != MatchController.YINLANG_WINDOW_INJECT and window_kind != MatchController.YINLANG_WINDOW_AETHER:
		close()
		return
	# 本次请求序号；与已装载视图的序号一致时说明只是重新显示，不应丢弃玩家已输入的内容。
	var requested_id: int = int(choice_data.get("request_id", -1))
	if is_loaded_request(requested_id):
		visible = true
		move_to_front()
		return
	_request_id = requested_id
	_clear_view()
	if window_kind == MatchController.YINLANG_WINDOW_INJECT:
		_title_label.text = COMPOSE_TITLE
		_subtitle_label.text = ""
		_compose_view = YinlangComposeView.new()
		_view_holder.add_child(_compose_view)
		_compose_view.configure(context)
		_compose_view.submitted.connect(_on_view_submitted)
		_compose_view.cancelled.connect(_on_view_cancelled)
	else:
		_title_label.text = MINT_TITLE
		_subtitle_label.text = MINT_SUBTITLE
		_mint_view = YinlangMintView.new()
		_view_holder.add_child(_mint_view)
		_mint_view.configure(context)
		_mint_view.submitted.connect(_on_view_submitted)
		_mint_view.cancelled.connect(_on_view_cancelled)
	visible = true
	move_to_front()
	refresh_ui_style()


## 收起窗口外观但保留当前视图与请求序号；用于「已提交、等待权威判定」的中间态。
## 与 `close()` 的区别：提交被拒绝时可以直接重新显示同一条请求，玩家输入不丢失。
## 名字必须避开 `CanvasItem.hide()`：同名覆盖原生方法在本项目里被当作错误（警告即错误）而无法加载。
func hide_view() -> void:
	visible = false


## 关闭窗口并释放当前视图；下一次请求会用全新视图重建。
func close() -> void:
	visible = false
	_request_id = -1
	_clear_view()


## 判断当前是否已为某个请求装载了视图；与 `is_showing_request` 的区别是不要求窗口可见。
func is_loaded_request(request_id: int) -> bool:
	return _request_id >= 0 and _request_id == request_id


## 判断当前窗口是否正在等待某个请求；牌桌据此决定是否让通用选择面板让位。
func is_showing_request(request_id: int) -> bool:
	return visible and is_loaded_request(request_id)


## 释放当前视图节点；先移出容器再释放，避免它继续参与布局。
func _clear_view() -> void:
	_compose_view = null
	_mint_view = null
	for child: Node in _view_holder.get_children():
		_view_holder.remove_child(child)
		child.queue_free()


## 转发视图提交；只收起外观，视图与玩家输入保留到权威判定为止。
## 【为什么不是 close()】提交只是「发出请求」，权威端仍可能拒绝（牌名重名、组合键非法等）。
## 若在这里就 close()，视图会被释放，重试时玩家必须从零重新输入；而请求其实还挂在那里。
## 真正的关闭由牌桌在权威快照里确认请求消失后调用 `close()` 完成。
func _on_view_submitted(control_id: String) -> void:
	# 本次提交对应的请求序号；收起外观不会清空它，仍随信号交给牌桌。
	var submitted_request_id: int = _request_id
	hide_view()
	choice_submitted.emit(submitted_request_id, control_id, true)


## 转发视图取消；同样只收起外观，取消被拒绝时可以直接重新显示同一条请求。
func _on_view_cancelled() -> void:
	# 本次取消对应的请求序号；收起外观不会清空它，仍随信号交给牌桌。
	var submitted_request_id: int = _request_id
	hide_view()
	choice_submitted.emit(submitted_request_id, "", false)
