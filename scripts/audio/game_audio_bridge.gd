class_name GameAudioBridge
extends Node

## 音频表现桥接组件。
## 职责边界：把核心层的只读语音表现信号与主菜单可见性变化翻译成音频服务请求。
## 自身不含任何播放逻辑，也不读取 GameState、MatchController 或技能运行时对象；
## 全部来源与目标都由 @export 路径指定，因此主场景重组时只需调整路径而无需改动本脚本。


## 音频服务自动加载路径；语音与BGM请求的统一出口。
const AUDIO_SERVICE_PATH: String = "/root/AudioService"

## BGM场景标识：主菜单；与 AudioCatalog.BGM_SCENE_MENU 取值保持一致。
const BGM_SCENE_MENU: String = "menu"

## BGM场景标识：战斗（含选将、对局与结算）；与 AudioCatalog.BGM_SCENE_BATTLE 取值保持一致。
const BGM_SCENE_BATTLE: String = "battle"

## 语音表现信号来源路径；默认指向同级的对局控制器，运行时不建议动态修改。
@export var voice_signal_source_path: NodePath = NodePath("../MatchController")

## 主菜单节点路径；其可见性变化即代表“处于主菜单”与“位于对局内”两种BGM场景。
@export var main_menu_path: NodePath = NodePath("../MainMenu")


## 节点进入场景树时连接信号来源，并按主菜单当前可见性同步一次BGM。
func _ready() -> void:
	_connect_sources()
	_sync_bgm_with_menu_visibility()


## 节点退出场景树时断开全部连接，避免场景重载后同一信号触发两次音频请求。
func _exit_tree() -> void:
	_disconnect_sources()


## 连接语音表现信号与主菜单可见性变化；单个来源缺失时只跳过该条链路，不影响另一条。
func _connect_sources() -> void:
	# 语音信号来源；缺少该节点时仅表示当前场景没有对局控制器，不影响主菜单BGM。
	var voice_source: Node = get_node_or_null(voice_signal_source_path)
	if voice_source != null and voice_source.has_signal("voice_presentation_requested") and not voice_source.voice_presentation_requested.is_connected(_on_voice_presentation_requested):
		voice_source.voice_presentation_requested.connect(_on_voice_presentation_requested)
	# 主菜单节点；缺少该节点时BGM固定按战斗场景处理。
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
	var audio_service: Node = get_node_or_null(AUDIO_SERVICE_PATH)
	if audio_service == null:
		return
	audio_service.play_voice_presentation(presentation_data)


## 主菜单可见性变化回调；选将与结算期间主菜单保持隐藏，因此战斗BGM会自然延续而不中断。
func _on_main_menu_visibility_changed() -> void:
	_sync_bgm_with_menu_visibility()


## 按主菜单当前可见性请求对应BGM场景；同一场景的重复请求由音频服务幂等处理。
func _sync_bgm_with_menu_visibility() -> void:
	var main_menu: Node = get_node_or_null(main_menu_path)
	# 主菜单是否可见；节点缺失时按战斗场景处理，保证对局内不会因为缺少菜单节点而失去背景音乐。
	var is_main_menu_visible: bool = main_menu != null and (main_menu as CanvasItem).visible
	_request_bgm(BGM_SCENE_MENU if is_main_menu_visible else BGM_SCENE_BATTLE)


## 请求音频服务切换BGM场景。
func _request_bgm(scene_id: String) -> void:
	var audio_service: Node = get_node_or_null(AUDIO_SERVICE_PATH)
	if audio_service == null:
		return
	audio_service.request_bgm(scene_id)
