extends Node

## 全局音频服务。
## 本节点是音频表现层对外的唯一门面：接收核心层下发的只读语音表现请求，解析音频文件并播放。
## 职责划分：
## 一、总线管理：运行时确保 BGM 与 SFX 两条总线存在并挂到 Master，不依赖额外的总线布局资源；
## 二、设置联动：订阅 GameSettings 的音量与静音变化，把线性音量换算为总线分贝；
## 三、请求分派：把语音表现负载翻译为候选路径解析与播放组件调用。
## 本节点不读取 GameState、MatchController 或任何技能运行时对象；缺少音频文件时全程静默。


## 背景音乐总线名；独立于音效总线，便于分别调节音量与统一静音。
const BGM_BUS_NAME: String = "BGM"

## 音效总线名；承载卡牌语音与技能语音。
const SFX_BUS_NAME: String = "SFX"

## 主总线名；两条音频总线均挂在该总线之下，最终由它输出到设备。
const MASTER_BUS_NAME: String = "Master"

## 语音表现请求类别：技能语音；负载需要 skill_id 与 character_id 两个字段。
const VOICE_KIND_SKILL: String = "skill"

## 语音表现请求类别：卡牌语音；负载需要 card_definition_id、card_names、gender 与 play_mode 字段。
const VOICE_KIND_CARD: String = "card"

## 语音表现请求类别：全局效果音；负载需要 effect_id 字段。
## 效果音与技能、卡牌语音共用同一条表现链路，因此单机本地播放、局域网由房主广播的表现语义完全一致。
const VOICE_KIND_EFFECT: String = "effect"

## 语音表现请求类别：武将阵亡语音；负载需要 character_id 字段。
## 阵亡是武将级事件而不是技能级事件，因此单独成类；它与技能语音一样按角色专属路径解析素材，
## 并复用同一条表现链路与联机广播通道。
const VOICE_KIND_DIE: String = "die"

## 全局设置自动加载路径；音频音量与静音开关的唯一持久化来源。
const GAME_SETTINGS_PATH: String = "/root/GameSettings"

## 播放时是否输出“音频缺失”诊断日志；默认关闭，避免缺少素材时刷屏，排查投放问题时再开启。
@export var debug_log_missing_audio: bool = false

## 音频资源解析器；负责候选路径推导与音频流缓存，不持有任何节点。
var _catalog: AudioCatalog

## 语音播放组件；负责多音效池随机与实际播放。
var _voice_player: AudioVoicePlayer

## 背景音乐播放组件；负责循环播放与场景切换淡入淡出。
var _bgm_player: AudioBgmPlayer


## 节点进入场景树时建立总线、装配子组件并同步一次音量设置。
func _ready() -> void:
	_ensure_audio_buses()
	_catalog = AudioCatalog.new()
	_voice_player = AudioVoicePlayer.new()
	_voice_player.name = "AudioVoicePlayer"
	add_child(_voice_player)
	_bgm_player = AudioBgmPlayer.new()
	_bgm_player.name = "AudioBgmPlayer"
	add_child(_bgm_player)
	_bind_settings()
	_apply_settings_to_buses()


## 播放一次语音表现请求；负载由核心层组装，本节点只负责解析与播放。
## 负载缺少必要字段或对应音频文件不存在时静默返回，不报错也不刷屏。
func play_voice_presentation(presentation_data: Dictionary) -> void:
	if _catalog == null or _voice_player == null:
		return
	# 请求类别；未知类别直接忽略，保持与核心层协议的前向兼容。
	var kind: String = str(presentation_data.get("kind", ""))
	if kind == VOICE_KIND_SKILL:
		_play_skill_voice(presentation_data)
	elif kind == VOICE_KIND_CARD:
		_play_card_voice(presentation_data)
	elif kind == VOICE_KIND_EFFECT:
		_play_effect_voice(presentation_data)
	elif kind == VOICE_KIND_DIE:
		_play_character_die_voice(presentation_data)


## 播放一次全局效果音；供界面层按本地视角发声（例如终局胜负）使用。
## 该端口与核心层表现请求共用同一份解析与播放实现，区别只在于调用方：
## 核心层请求会随联机表现事件广播给全部客户端，界面层请求只在本机发声。
func play_effect(effect_id: String) -> void:
	if _catalog == null or _voice_player == null:
		return
	# 素材路径；该效果没有投放素材时返回空字符串，此处静默跳过。
	var effect_path: String = _catalog.resolve_effect_path(effect_id)
	if effect_path.is_empty():
		_log_missing_audio("effect", effect_id, "")
		return
	# 音频流；文件存在但类型不符时返回null，单独跳过而不影响其它音效。
	var stream: AudioStream = _catalog.load_stream(effect_path)
	if stream != null:
		_voice_player.play_stream(stream)


## 请求播放指定场景的背景音乐；同一场景重复请求为幂等操作，不会重头播放。
## 场景标识只区分主菜单与战斗两类；未知标识按战斗处理，保证任何对局阶段都有背景音乐。
func request_bgm(scene_id: String) -> void:
	if _catalog == null or _bgm_player == null:
		return
	# 规范化场景标识；主菜单之外的取值一律归入战斗场景。
	var normalized_scene_id: String = AudioCatalog.BGM_SCENE_MENU if scene_id == AudioCatalog.BGM_SCENE_MENU else AudioCatalog.BGM_SCENE_BATTLE
	# 候选曲目池；同一场景可投放多首曲目，进入时随机选择其中一首。
	var pool: Array[String] = _catalog.resolve_bgm_pool(normalized_scene_id)
	if pool.is_empty():
		_log_missing_audio("bgm", normalized_scene_id, "")
		return
	_bgm_player.play_pool(normalized_scene_id, pool, _catalog)


## 停止背景音乐并清空场景标识；返回主菜单或退出对局时可显式调用。
func stop_bgm() -> void:
	if _bgm_player == null:
		return
	_bgm_player.stop_bgm()


## 返回当前背景音乐场景标识；空字符串表示没有正在播放的场景BGM。
func get_current_bgm_scene() -> String:
	if _bgm_player == null:
		return ""
	return _bgm_player.get_current_scene_id()


## 返回当前背景音乐播放位置（秒）；仅供诊断与自动化测试的幂等性断言使用。
func get_bgm_playback_position() -> float:
	if _bgm_player == null:
		return 0.0
	return _bgm_player.get_playback_position()


## 设置背景音乐音量；转发给唯一的持久化入口 GameSettings，由其信号驱动总线刷新。
func set_bgm_volume_linear(volume_linear: float) -> void:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return
	settings.set_bgm_volume(volume_linear)


## 设置音效与语音音量；转发给唯一的持久化入口 GameSettings，由其信号驱动总线刷新。
func set_sfx_volume_linear(volume_linear: float) -> void:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return
	settings.set_sfx_volume(volume_linear)


## 设置全局静音开关；转发给唯一的持久化入口 GameSettings，由其信号驱动两条总线同步静音。
func set_audio_muted(muted: bool) -> void:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return
	settings.set_audio_muted(muted)


## 返回音频服务当前状态快照；仅供诊断与自动化测试断言，不参与任何游戏逻辑。
func get_debug_state() -> Dictionary:
	return {
		"bgm_scene": get_current_bgm_scene(),
		"active_voice_count": _voice_player.get_active_voice_count() if _voice_player != null else 0,
		"bgm_volume": _read_settings_value("bgm_volume", 0.0),
		"sfx_volume": _read_settings_value("sfx_volume", 0.0),
		"audio_muted": _read_settings_value("audio_muted", false),
	}


## 播放技能语音；按“角色专属池 → 角色专属单音 → 通用池 → 通用单音”顺序解析候选。
func _play_skill_voice(presentation_data: Dictionary) -> void:
	# 技能ID；与技能源码文件名一致，是音效命名基准。
	var skill_id: String = str(presentation_data.get("skill_id", ""))
	# 发动者武将ID；用于优先命中该角色的专属配音，技能换主后音色随之变化。
	var character_id: String = str(presentation_data.get("character_id", ""))
	# 候选池；空表示该技能尚无任何配音，静默处理。
	var pool: Array[String] = _catalog.resolve_skill_voice_pool(skill_id, character_id)
	if pool.is_empty():
		_log_missing_audio("skill", skill_id, character_id)
		return
	# 池标识使用技能ID；同一技能的多套配音共享“避免连续重复”的记录。
	_voice_player.play_pool(pool, _catalog, "skill:%s" % skill_id)


## 播放卡牌语音；基础伴随音效与专属牌名配音各播放一次，两层叠加而不是互相替代。
func _play_card_voice(presentation_data: Dictionary) -> void:
	# 卡牌定义ID；虚拟牌（例如罡风转化的雷【杀】）传入的是实际结算的虚拟定义ID。
	var card_definition_id: String = str(presentation_data.get("card_definition_id", ""))
	# 使用者性别；核心层已按发动者武将解析，未选将或未知性别时音频层跳过性别专属目录。
	var gender: String = str(presentation_data.get("gender", ""))
	# 播放路径；第一位是每一张牌都有的基础伴随音效，其后是该牌的专属配音（可能不存在）。
	var paths: Array[String] = _catalog.resolve_card_voice_paths(card_definition_id, _get_current_card_name_system(), gender)
	if paths.is_empty():
		_log_missing_audio("card", card_definition_id, "")
		return
	# 逐条播放；播放器按需分配，因此两层音效会同时出声，后一层不会打断前一层。
	for path: String in paths:
		# 音频流；该层文件缺失或类型不符时返回 null，单独跳过这一层而不影响另一层。
		var stream: AudioStream = _catalog.load_stream(path)
		if stream != null:
			_voice_player.play_stream(stream)


## 播放核心层下发的效果音表现请求；负载字段与界面层 play_effect() 端口完全一致。
## 效果音不区分角色与性别，因此不读取负载中的发动者字段，只取效果标识本身。
func _play_effect_voice(presentation_data: Dictionary) -> void:
	play_effect(str(presentation_data.get("effect_id", "")))


## 播放武将阵亡语音；素材按阵亡者的武将ID在 game_data/characters/audio/die 下解析。
## 与技能语音的差别只有查找层级：阵亡语音只按武将身份定位素材，没有通用兜底层。
func _play_character_die_voice(presentation_data: Dictionary) -> void:
	# 阵亡武将ID；与武将源码文件名一致，是阵亡语音的命名基准。
	var character_id: String = str(presentation_data.get("character_id", ""))
	# 候选池；空表示该武将尚未投放阵亡语音，静默处理。
	var pool: Array[String] = _catalog.resolve_character_die_voice_pool(character_id)
	if pool.is_empty():
		_log_missing_audio("die", character_id, "")
		return
	# 池标识使用武将ID；同一武将的多套阵亡语音共享“避免连续重复”的记录。
	_voice_player.play_pool(pool, _catalog, "die:%s" % character_id)


## 读取当前卡牌名称显示模式对应的名称体系后缀。
## 以枚举成员而非字面量比较，避免名称模式扩展时此处漏改；设置缺失时回退崩铁杀自定义牌名。
func _get_current_card_name_system() -> String:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return AudioCatalog.NAME_SYSTEM_CUSTOM
	if int(settings.card_name_mode) == int(settings.NameMode.ORIGINAL):
		return AudioCatalog.NAME_SYSTEM_ORIGINAL
	return AudioCatalog.NAME_SYSTEM_CUSTOM


## 读取一项设置值；设置节点缺失或字段不存在时返回调用方给出的回退值。
func _read_settings_value(property_name: String, fallback_value: Variant) -> Variant:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return fallback_value
	return settings.get(property_name) if settings.get(property_name) != null else fallback_value


## 确保 BGM 与 SFX 两条总线存在并挂到主总线；已存在时不重复创建，保留玩家在系统中的手动调整。
func _ensure_audio_buses() -> void:
	for bus_name: String in [BGM_BUS_NAME, SFX_BUS_NAME]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		# 新总线索引；追加到总线列表末尾后再命名，避免覆盖既有总线。
		var bus_index: int = AudioServer.bus_count
		AudioServer.add_bus(bus_index)
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, MASTER_BUS_NAME)


## 订阅全局音频设置变化；设置节点缺失时（例如独立单元测试）跳过订阅。
func _bind_settings() -> void:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return
	if settings.has_signal("bgm_volume_changed"):
		settings.bgm_volume_changed.connect(_on_bgm_volume_changed)
	if settings.has_signal("sfx_volume_changed"):
		settings.sfx_volume_changed.connect(_on_sfx_volume_changed)
	if settings.has_signal("audio_muted_changed"):
		settings.audio_muted_changed.connect(_on_audio_muted_changed)


## 把当前设置一次性应用到两条总线；启动阶段与设置节点缺失时都依赖该入口完成初始同步。
func _apply_settings_to_buses() -> void:
	var settings: Node = get_node_or_null(GAME_SETTINGS_PATH)
	if settings == null:
		return
	_apply_bus_volume(BGM_BUS_NAME, float(settings.bgm_volume), bool(settings.audio_muted))
	_apply_bus_volume(SFX_BUS_NAME, float(settings.sfx_volume), bool(settings.audio_muted))


## 把线性音量与静音状态写入指定总线。
## 零音量改走总线静音开关：线性0换算成分贝是负无穷，直接写入会触发无效值告警。
func _apply_bus_volume(bus_name: String, volume_linear: float, muted: bool) -> void:
	# 总线索引；总线缺失时静默跳过，不影响任何游戏流程。
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	# 限制后的线性音量；取值范围与设置层保持一致。
	var clamped_volume: float = clampf(volume_linear, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, muted or clamped_volume <= 0.0)
	# 分贝值；零音量时写入0分贝并依赖静音开关，避免出现负无穷。
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(clamped_volume) if clamped_volume > 0.0 else 0.0)


## 背景音乐音量变化回调；只刷新BGM总线。
func _on_bgm_volume_changed(volume_linear: float) -> void:
	_apply_bus_volume(BGM_BUS_NAME, volume_linear, bool(_read_settings_value("audio_muted", false)))


## 音效音量变化回调；只刷新SFX总线。
func _on_sfx_volume_changed(volume_linear: float) -> void:
	_apply_bus_volume(SFX_BUS_NAME, volume_linear, bool(_read_settings_value("audio_muted", false)))


## 全局静音变化回调；两条总线同时切换静音状态，已保存的音量数值保持不变。
func _on_audio_muted_changed(muted: bool) -> void:
	_apply_bus_volume(BGM_BUS_NAME, float(_read_settings_value("bgm_volume", 0.0)), muted)
	_apply_bus_volume(SFX_BUS_NAME, float(_read_settings_value("sfx_volume", 0.0)), muted)


## 输出一条“音频缺失”诊断日志；默认关闭，仅在排查素材投放问题时启用。
func _log_missing_audio(kind: String, identifier: String, character_id: String) -> void:
	if not debug_log_missing_audio:
		return
	# 角色后缀；仅技能语音需要提示专属角色，其余类别保持简洁。
	var character_suffix: String = "（角色 %s）" % character_id if not character_id.is_empty() else ""
	print("[AudioService] 未找到%s音频：%s%s" % [kind, identifier, character_suffix])
