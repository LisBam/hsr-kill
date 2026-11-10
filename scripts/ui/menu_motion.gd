extends Node

## 仅在指定局外根节点下工作的过渡服务。页面的显隐和模式状态仍由原组件拥有，本服务只管理短生命周期Tween。
## 调用enter可重播或取消退出；try_close把关闭回调延迟到退场末尾，系统清理和切页仍可直接隐藏。

## 页面入场时长；默认0.28秒，可运行时调整，不阻塞业务或内容加载。
@export_range(0.05, 0.8, 0.01) var page_duration: float = 0.28
## 模态入场时长；默认0.24秒，可运行时调整。
@export_range(0.05, 0.8, 0.01) var modal_duration: float = 0.24
## 模态退场时长；默认0.14秒，可运行时调整，期间只冻结正在退出的表单输入。
@export_range(0.05, 0.4, 0.01) var exit_duration: float = 0.14
## 页面进入距离；默认18逻辑像素，仅视觉变换，不影响布局与命中范围。
@export_range(0.0, 48.0, 1.0) var travel: float = 18.0
## 动效总开关；默认开启，关闭时入场直接就位、关闭回调同步执行。
@export var animations_enabled: bool = true:
	set(value):
		animations_enabled = value
		if is_node_ready() and not value:
			for key: int in _active.keys():
				_finish(key)
## 局外根节点上的服务标识；仅该子树可发现服务，不允许修改战斗界面。
const SERVICE_META: StringName = &"menu_motion_service"
## 回调重入标记；关闭完成时允许原关闭函数执行一次，不重复排队。
const EXIT_READY_META: StringName = &"menu_motion_exit_ready"
## 正在执行的过渡；键为实例ID，值包含弱引用、Tween、输入策略与退出标志，完成后删除。
var _active: Dictionary = {}


## 查找当前节点所属的局外服务；独立测试或被复用到战斗树时返回null并安全降级。
static func _find_service(control: Control) -> Node:
	# 祖先游标；沿树向上查找，不访问全局场景单例。
	var cursor: Node = control
	while cursor != null:
		if cursor.has_meta(SERVICE_META):
			return (cursor.get_meta(SERVICE_META) as WeakRef).get_ref() as Node
		cursor = cursor.get_parent()
	return null


## 让已可见内容入场；kind为page/modal/fade，方向只影响页面的水平视觉位移。
static func enter(control: Control, kind: String = "page", direction: float = 1.0) -> void:
	if control == null:
		return
	# 当前局外服务；缺失时不修改调用方状态。
	var service: Node = _find_service(control)
	if service != null:
		service.call("reveal", control, kind, direction)


## 用户关闭入口的可选退场；返回true表示回调已接管，调用方应立即return；隐藏清理路径不调用本方法。
static func try_close(control: Control, close_callback: Callable) -> bool:
	if control == null or not control.is_visible_in_tree() or control.has_meta(EXIT_READY_META):
		return false
	# 所属服务；单独实例化原页面时保持原来的同步关闭契约。
	var service: Node = _find_service(control)
	return bool(service.call("dismiss", control, close_callback)) if service != null else false


## 观察可见性边界；视觉目标可与开关节点不同，例如全屏大厅只让内容面进入。
func watch(trigger: Control, visual: Control, kind: String = "page") -> void:
	trigger.visibility_changed.connect(_on_surface_visibility.bind(trigger, visual, kind))
	if trigger.is_visible_in_tree():
		reveal(visual, kind)


## 只在页面可见时进入；父级隐藏会立即取消Tween并恢复输入和视觉基线。
func _on_surface_visibility(trigger: Control, visual: Control, kind: String) -> void:
	if trigger.is_visible_in_tree():
		reveal(visual, kind)
	else:
		cancel(visual)
		if trigger != visual:
			cancel(trigger)


## 开始一次淡入/滑入；同一控件的新动画先取消旧动画，因此快速来回切页不会叠加位移。
func reveal(control: Control, kind: String = "page", direction: float = 1.0) -> void:
	cancel(control)
	if not animations_enabled or not control.is_visible_in_tree():
		return
	# 控件实例ID；用于淘汰过期回调，不保存强引用。
	var key: int = control.get_instance_id()
	# 本次入场轨道；绑定目标生命周期，目标释放时由引擎取消。
	var tween: Tween = control.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 当前控件原透明度；还原时保留调用方自身的调色，不强制覆盖为白色。
	var base_modulate: Color = control.modulate
	_active[key] = {"control": weakref(control), "tween": tween, "modulate": base_modulate, "closing": false}
	control.offset_transform_enabled = true
	control.offset_transform_visual_only = true
	control.modulate.a = 0.0
	control.offset_transform_position = Vector2(0.0, travel * 0.6) if kind == "modal" else Vector2(travel * direction, 0.0)
	control.offset_transform_scale = Vector2.ONE * (0.975 if kind == "modal" else 1.0)
	if kind == "fade":
		control.offset_transform_position = Vector2.ZERO
	# 模态比页面更快；遮罩只做透明度过渡。
	var duration: float = modal_duration if kind == "modal" else page_duration
	tween.tween_property(control, "modulate:a", base_modulate.a, duration)
	tween.tween_property(control, "offset_transform_position", Vector2.ZERO, duration)
	tween.tween_property(control, "offset_transform_scale", Vector2.ONE, duration)
	tween.finished.connect(_finish.bind(key))
	if not control.tree_exiting.is_connected(_forget.bind(key)):
		control.tree_exiting.connect(_forget.bind(key), CONNECT_ONE_SHOT)


## 冻结退出表单并播放短退场；重复关闭直接吞掉，业务回调只执行一次。
func dismiss(control: Control, close_callback: Callable) -> bool:
	if not animations_enabled:
		return false
	# 当前轨道键；同一表单不能同时提交多条关闭回调。
	var key: int = control.get_instance_id()
	if bool((_active.get(key, {}) as Dictionary).get("closing", false)):
		return true
	cancel(control)
	# 当前输入策略；退场完毕或中断都恢复原值，避免重新打开后不可操作。
	var mouse_behavior: int = control.mouse_behavior_recursive
	# 当前焦点策略；不修改任何子控件原有focus_mode。
	var focus_behavior: int = control.focus_behavior_recursive
	# 当前表单原透明度；关闭中断时恢复该值。
	var base_modulate: Color = control.modulate
	# 退场Tween；主菜单隐藏或切页时由cancel取消，不触发迟到的关闭回调。
	var tween: Tween = control.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active[key] = {"control": weakref(control), "tween": tween, "modulate": base_modulate, "closing": true, "mouse": mouse_behavior, "focus": focus_behavior}
	control.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	tween.tween_property(control, "modulate:a", 0.0, exit_duration)
	if not control is ColorRect:
		tween.tween_property(control, "offset_transform_scale", Vector2.ONE * 0.985, exit_duration)
	tween.finished.connect(_complete_close.bind(key, close_callback))
	if not control.tree_exiting.is_connected(_forget.bind(key)):
		control.tree_exiting.connect(_forget.bind(key), CONNECT_ONE_SHOT)
	return true


## 退场完成后执行原关闭逻辑；标记只在同步回调期间存在，供原函数跳过再次播放。
func _complete_close(key: int, close_callback: Callable) -> void:
	if not _active.has(key):
		return
	# 有效表单；使用弱引用，释放后的节点绝不调用业务方法。
	var control: Control = (_active[key]["control"] as WeakRef).get_ref() as Control
	_finish(key)
	if is_instance_valid(control) and close_callback.is_valid():
		control.set_meta(EXIT_READY_META, true)
		close_callback.call()
		if is_instance_valid(control):
			control.remove_meta(EXIT_READY_META)


## 取消单个控件轨道并恢复基线；不执行关闭回调、不更改visible。
func cancel(control: Control) -> void:
	if is_instance_valid(control):
		_finish(control.get_instance_id())


## 隐藏整个局外界面时停止全部表现轨道；不让隐藏大厅或旧页面继续运行退出回调。
func cancel_all() -> void:
	for key: int in _active.keys():
		_finish(key)


## 清理已完成或被替代的过渡；隐藏、释放及连续切页共用这一条回收路径。
func _finish(key: int) -> void:
	if not _active.has(key):
		return
	# 本次动画状态；先移出字典，避免输入恢复信号造成重入。
	var state: Dictionary = _active[key]
	_active.erase(key)
	# 当前Tween；kill不会发射finished，因此取消不会执行过期关闭回调。
	var tween: Tween = state["tween"] as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	# 被动画控件；释放后只清理字典，不再访问对象属性。
	var control: Control = (state["control"] as WeakRef).get_ref() as Control
	if not is_instance_valid(control):
		return
	control.modulate = state["modulate"]
	control.offset_transform_position = Vector2.ZERO
	control.offset_transform_scale = Vector2.ONE
	if bool(state.get("closing", false)):
		control.set("mouse_behavior_recursive", int(state["mouse"]))
		control.set("focus_behavior_recursive", int(state["focus"]))


## 释放节点时清理引用；不把历史图鉴条目留在过渡字典中。
func _forget(key: int) -> void:
	_finish(key)


## 局外根节点离开场景树时回收全部轨道，防止关闭后的界面继续占用Tween。
func _exit_tree() -> void:
	for key: int in _active.keys():
		_finish(key)
