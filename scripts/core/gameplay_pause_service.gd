class_name GameplayPauseService
extends Node

## 对局级令牌暂停服务。界面、调试器和后续网络托管只能申请与释放自己的暂停令牌，不能直接改写 SceneTree.paused。

## 对局暂停状态发生首个申请或最后一个释放时发出；订阅者只读取状态，不直接修改令牌集合。
signal pause_state_changed(paused: bool, active_reasons: Array[String])

## 下一个暂停令牌 ID；从1递增，0与负数始终表示无效令牌。
var _next_token_id: int = 1

## 当前活动令牌；键为稳定令牌 ID，值为长期可读的暂停原因文本。
var _active_tokens: Dictionary = {}

## 首个令牌申请前场景树原有的暂停状态；最后一个令牌释放后恢复该值，避免覆盖其他系统已有暂停。
var _tree_pause_state_before_first_token: bool = false


## 让暂停服务在场景树暂停时仍能接收日志收起等释放请求。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 申请一个独立对局暂停令牌；reason 用于调试、回放和界面所有权识别。
func acquire_pause(reason: String) -> int:
	# 当前申请是否会让服务从运行状态首次进入暂停；只有该边界需要保存并修改场景树状态。
	var enters_paused_state: bool = _active_tokens.is_empty()
	# 当前新令牌 ID；先保存后递增，保证同一运行期内不会重复。
	var token_id: int = _next_token_id
	_next_token_id += 1
	_active_tokens[token_id] = reason if not reason.is_empty() else "unspecified"
	if enters_paused_state:
		# 当前场景树；服务独立测试尚未入树时仍可登记令牌，进入树后的正常对局始终存在有效实例。
		var scene_tree: SceneTree = get_tree()
		if scene_tree != null:
			_tree_pause_state_before_first_token = scene_tree.paused
			scene_tree.paused = true
		pause_state_changed.emit(true, get_active_reasons())
	return token_id


## 释放调用方持有的指定令牌；未知或重复释放返回false，且不会影响其他暂停原因。
func release_pause(token_id: int) -> bool:
	if not _active_tokens.has(token_id):
		return false
	_active_tokens.erase(token_id)
	if _active_tokens.is_empty():
		# 当前场景树；恢复首个令牌申请前的状态，避免错误解除服务之外仍然存在的暂停。
		var scene_tree: SceneTree = get_tree()
		if scene_tree != null:
			scene_tree.paused = _tree_pause_state_before_first_token
		pause_state_changed.emit(false, get_active_reasons())
	return true


## 返回当前是否至少存在一个活动暂停令牌；AI、事件运行时和调试界面共用该只读接口。
func is_paused() -> bool:
	return not _active_tokens.is_empty()


## 返回按令牌 ID 排序的活动暂停原因副本；外部不能据此修改服务内部状态。
func get_active_reasons() -> Array[String]:
	# 已排序令牌 ID；Dictionary 键顺序不作为可回放契约，因此显式排序。
	var token_ids: Array = _active_tokens.keys()
	token_ids.sort()
	# 暂停原因结果；顺序与令牌申请顺序一致，便于日志和测试稳定比较。
	var reasons: Array[String] = []
	# 当前已排序令牌 ID；逐项解析对应原因，不能直接暴露内部字典。
	for token_id_variant: Variant in token_ids:
		reasons.append(str(_active_tokens.get(int(token_id_variant), "unspecified")))
	return reasons


## 场景退出时恢复服务接管前的场景树状态；正常调用方仍应优先显式释放自己的令牌。
func _exit_tree() -> void:
	if _active_tokens.is_empty():
		return
	# 当前场景树；退出回调期间仍可用时恢复原状态，防止切换场景后残留全局暂停。
	var scene_tree: SceneTree = get_tree()
	if scene_tree != null:
		scene_tree.paused = _tree_pause_state_before_first_token
	_active_tokens.clear()
