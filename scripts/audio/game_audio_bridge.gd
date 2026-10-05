class_name GameAudioBridge
extends Node

## 音频表现桥接组件。
## 职责边界：把核心层的只读语音表现信号与主菜单可见性变化翻译成音频服务请求。
## 自身不含任何播放逻辑，也不读取 GameState、MatchController 或技能运行时对象；
## 全部来源与目标都由 @export 路径指定，因此主场景重组时只需调整路径而无需改动本脚本。
##
## BGM场景所有权：本组件是“当前应该播放哪一套BGM”的唯一权威，并且只持有零或一个场景。
## 它把主菜单可见性这一场景级事实翻译成一次显式的“退出旧场景 → 进入新场景”迁移，
## 因此主菜单BGM与战斗BGM在任何时刻都不同时存在，也不会因为目标场景没有投放素材而残留上一场景的曲目。
## 进入对局的锚点是 MainMenu.visible 变为 false（此时权威对局已创建成功），
## 退出对局的锚点是它变回 true（返回主菜单、联机会话结束、重开失败回退），
## 选将与结算期间主菜单保持隐藏，因此战斗BGM在整局内自然延续而不中断。


## 音频服务自动加载路径；语音与BGM请求的统一出口。
## 默认指向自动加载节点，运行时不建议动态修改；提取为 @export 以便独立场景与自动化测试注入替代实现。
@export var audio_service_path: NodePath = NodePath("/root/AudioService")

## BGM场景标识：主菜单；与 AudioCatalog.BGM_SCENE_MENU 取值保持一致。
const BGM_SCENE_MENU: String = "menu"

## BGM场景标识：战斗（含选将、对局与结算）；与 AudioCatalog.BGM_SCENE_BATTLE 取值保持一致。
const BGM_SCENE_BATTLE: String = "battle"

## 语音表现信号来源路径；默认指向同级的对局控制器，运行时不建议动态修改。
@export var voice_signal_source_path: NodePath = NodePath("../MatchController")

## 主菜单节点路径；其可见性变化即代表“处于主菜单”与“位于对局内”两种BGM场景。
@export var main_menu_path: NodePath = NodePath("../MainMenu")

## 本组件当前已进入的BGM场景标识；空字符串表示未持有任何场景（不播放任何BGM）。
var _current_scene_id: String = ""


## 节点进入场景树时连接信号来源，并按主菜单当前可见性同步一次BGM。
func _ready() -> void:
	_connect_sources()
	_sync_bgm_scene()


## 节点退出场景树时先释放本组件持有的BGM场景，再断开全部连接。
## 顺序不可颠倒：只断连接的话，归属信息会随节点一起丢失，
## 而音频服务是自动加载节点，上一局的战斗BGM会在下一个场景里继续播放。
func _exit_tree() -> void:
	_apply_bgm_scene("")
	_disconnect_sources()


## 连接语音表现信号与主菜单可见性变化；单个来源缺失时只跳过该条链路，不影响另一条。
func _connect_sources() -> void:
	# 语音信号来源；缺少该节点时仅表示当前场景没有对局控制器，不影响主菜单BGM。
	var voice_source: Node = get_node_or_null(voice_signal_source_path)
	if voice_source != null and voice_source.has_signal("voice_presentation_requested") and not voice_source.voice_presentation_requested.is_connected(_on_voice_presentation_requested):
		voice_source.voice_presentation_requested.connect(_on_voice_presentation_requested)
	# 主菜单节点；缺少该节点时BGM场景无法判定，本组件保持不持有任何场景。
	var main_menu: Node = get_node_or_null(main_menu_path)
	if main_menu != null and not main_menu.visibility_changed.is_connected(_on_main_menu_visibility_changed):
		main_menu.visibility_changed.connect(_on_main_menu_visibility_changed)


## 断开全部连接；使用与连接时相同的来源路径，保证场景卸载后不残留回调。
func _disconnect_sources() -> void:
	var voice_source: Node = get_node_or_null(voice_signal_source_path)
	if voice_source != null and voice_source.is_connected("voice_presentation_requested", _on_voice_presentation_requested):
		voice_source.voice_presentation_requested.disconnect(_on_voice_presentation_requested)
	var main_menu: Node = get_node_or_null(main_menu_path)
	if main_menu != null and main_menu.is_connected("visibility_changed", _on_main_menu_visibility_changed):
		main_menu.visibility_changed.disconnect(_on_main_menu_visibility_changed)


## 语音表现请求回调；负载已是只读公开数据，直接转交音频服务。
func _on_voice_presentation_requested(presentation_data: Dictionary) -> void:
	# 音频服务节点；自动加载缺失时静默跳过，保证对局流程不受影响。
	var audio_service: Node = get_node_or_null(audio_service_path)
	if audio_service == null:
		return
	audio_service.play_voice_presentation(presentation_data)


## 主菜单可见性变化回调；选将与结算期间主菜单保持隐藏，因此战斗BGM会自然延续而不中断。
func _on_main_menu_visibility_changed() -> void:
	_sync_bgm_scene()


## 按主菜单当前可见性解析目标BGM场景并执行一次场景迁移。
func _sync_bgm_scene() -> void:
	_apply_bgm_scene(_resolve_target_scene_id())


## 解析当前应处的BGM场景；主菜单可见即主菜单场景，隐藏即战斗场景。
## 锚点节点缺失时返回空字符串，表示“本组件不持有任何BGM场景”。
## 刻意不做“缺少锚点就按战斗处理”的兜底：那会让一处路径配置错误表现为一局永不停止的战斗BGM，
## 而静默无声是更容易被发现且不会污染其它界面的失败形态。
func _resolve_target_scene_id() -> String:
	var main_menu: Node = get_node_or_null(main_menu_path)
	if main_menu == null:
		return ""
	return BGM_SCENE_MENU if (main_menu as CanvasItem).visible else BGM_SCENE_BATTLE


## 执行一次显式的BGM场景迁移：先按作用域退出旧场景，再进入新场景。
## 目标与当前场景相同时直接返回，保证选将、结算等阶段反复触发的可见性通知不会重播曲目。
## next_scene_id 为空字符串表示回到“不持有任何场景”，此时只退出、不进入，用于场景卸载。
func _apply_bgm_scene(next_scene_id: String) -> void:
	if next_scene_id == _current_scene_id:
		return
	# 旧场景标识；先记录再改写归属，避免释放过程中再次进入本函数时读到新值。
	var previous_scene_id: String = _current_scene_id
	_current_scene_id = next_scene_id
	if not previous_scene_id.is_empty():
		_release_bgm(previous_scene_id)
	if not next_scene_id.is_empty():
		_request_bgm(next_scene_id)


## 请求音频服务进入指定BGM场景。
func _request_bgm(scene_id: String) -> void:
	var audio_service: Node = get_node_or_null(audio_service_path)
	if audio_service == null:
		return
	audio_service.request_bgm(scene_id)


## 请求音频服务按场景作用域释放BGM；只有该场景仍是当前播放场景时才会真正停止。
func _release_bgm(scene_id: String) -> void:
	var audio_service: Node = get_node_or_null(audio_service_path)
	if audio_service == null:
		return
	audio_service.release_bgm(scene_id)
