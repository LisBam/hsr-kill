class_name AudioCatalog
extends RefCounted

## 音频资源目录解析器。
## 该组件是纯逻辑组件：只根据逻辑标识（技能ID、角色ID、卡牌ID、BGM场景）推导候选资源路径，
## 并负责音频流的加载与缓存；不持有任何节点、不播放、不读取对局状态，因此可被独立单元测试。
## 路径发现全部使用 ResourceLoader.exists() 探测，不使用 DirAccess 目录扫描：
## 导出包中音频资源的磁盘文件名会被改写为 .oggvorbisstr 等导入名，目录扫描结果不可靠。


## 技能音效目录；技能音效文件名以技能源码文件名（即技能ID）为基准。
const SKILL_AUDIO_DIR: String = "res://game_data/skills/audio"

## 卡牌音效目录；卡牌音效文件名由卡牌ID与名称体系后缀共同构成。
const CARD_AUDIO_DIR: String = "res://game_data/cards/audio"

## 背景音乐目录；BGM按场景基名加可选序号构成候选池。
const BGM_DIR: String = "res://game_data/BGM"

## 音频扩展名探测优先级；ogg体积最小且支持循环标记，wav与mp3作为兼容备选依次探测。
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]

## 多音效池允许的最大序号；序号从1开始，上限8足以覆盖同一配音的多套变体，同时限制无效探测次数。
const MAX_POOL_SIZE: int = 8

## 多音效池的首个序号；与主公约定一致，编号文件形如 gangfeng_1、gangfeng_2。
const FIRST_POOL_INDEX: int = 1

## 卡牌名称体系后缀：崩铁杀自定义牌名；与 GameSettings.NameMode.CUSTOM 语义一致。
const NAME_SYSTEM_CUSTOM: String = "custom"

## 卡牌名称体系后缀：原版三国杀牌名；与 GameSettings.NameMode.ORIGINAL 语义一致。
const NAME_SYSTEM_ORIGINAL: String = "original"

## 主菜单BGM场景标识；对应 game_data/BGM/menu 系列文件。
const BGM_SCENE_MENU: String = "menu"

## 战斗BGM场景标识；对应 game_data/BGM/battle 系列文件，进入对局后含选将与结算阶段持续播放。
const BGM_SCENE_BATTLE: String = "battle"

## 已加载音频流缓存；键为资源路径、值为 AudioStream，命中后不再重复读取磁盘。
var _stream_cache: Dictionary = {}

## 资源存在性探测器；留空时使用引擎的 ResourceLoader.exists，自动化测试可注入内存探测器以覆盖全部回退分支。
var path_probe: Callable = Callable()


## 解析技能音效的最终候选池。
## 查找顺序为主公钦定的四级短路规则：
## 一、<技能ID>_<角色ID>_<序号> 角色专属多音效池；
## 二、<技能ID>_<角色ID> 角色专属单音效；
## 三、<技能ID>_<序号> 通用多音效池；
## 四、<技能ID> 通用单音效。
## 任一级命中即返回，不再向下回退；全部缺失时返回空数组，由调用方静默处理。
func resolve_skill_voice_pool(skill_id: String, character_id: String) -> Array[String]:
	# 规范化技能ID；空ID无法构造任何路径，直接返回空池。
	var normalized_skill_id: String = skill_id.strip_edges()
	if normalized_skill_id.is_empty():
		return []
	# 规范化角色ID；缺失时跳过专属两级只按通用音效回退，保证未指定武将时仍有配音。
	var normalized_character_id: String = character_id.strip_edges()
	if not normalized_character_id.is_empty():
		# 角色专属基名；技能ID与角色ID正向拼接，即使角色ID自身含下划线也不会与序号产生歧义。
		var exclusive_base: String = "%s/%s_%s" % [SKILL_AUDIO_DIR, normalized_skill_id, normalized_character_id]
		# 角色专属多音效池；非空即命中，池内随机由播放组件负责。
		var exclusive_pool: Array[String] = _collect_existing_pool(exclusive_base)
		if not exclusive_pool.is_empty():
			return exclusive_pool
		# 角色专属单音效；专属池缺失时才回退到该角色的单一配音。
		var exclusive_single: String = _resolve_existing_path(exclusive_base)
		if not exclusive_single.is_empty():
			# 专属单音效包成单元素池；统一返回类型便于播放组件复用同一个随机入口。
			var exclusive_single_pool: Array[String] = [exclusive_single]
			return exclusive_single_pool
	# 通用基名；未命中角色专属音效时回退到全部角色共享的配音。
	var common_base: String = "%s/%s" % [SKILL_AUDIO_DIR, normalized_skill_id]
	# 通用多音效池；非空即命中，避免池与单音效混播导致随机性失真。
	var common_pool: Array[String] = _collect_existing_pool(common_base)
	if not common_pool.is_empty():
		return common_pool
	# 通用单音效；四级全部缺失时返回空池。
	var common_single: String = _resolve_existing_path(common_base)
	if not common_single.is_empty():
		# 通用单音效包成单元素池；与专属单音效保持同一返回结构。
		var common_single_pool: Array[String] = [common_single]
		return common_single_pool
	return []


## 解析卡牌音效的最终候选池。
## 查找顺序为主公钦定的名称体系回退：先取当前卡名显示模式对应的体系，缺失时回退另一体系。
## 同一张牌的“使用”与“打出”共用同一份音效，因此本函数不需要动作模式参数。
func resolve_card_voice_pool(card_id: String, current_name_system: String) -> Array[String]:
	# 规范化卡牌ID；空ID无法构造路径，直接静默。
	var normalized_card_id: String = card_id.strip_edges()
	if normalized_card_id.is_empty():
		return []
	# 当前名称体系；未知取值回退崩铁杀自定义牌名，与 GameSettings 的默认模式保持一致。
	var primary_system: String = NAME_SYSTEM_ORIGINAL if current_name_system == NAME_SYSTEM_ORIGINAL else NAME_SYSTEM_CUSTOM
	# 回退名称体系；当前体系缺失时改用另一套牌名的配音，实现双向回退。
	var fallback_system: String = NAME_SYSTEM_CUSTOM if primary_system == NAME_SYSTEM_ORIGINAL else NAME_SYSTEM_ORIGINAL
	for name_system: String in [primary_system, fallback_system]:
		# 当前体系候选路径；命中即返回，保证“当前牌名配音优先”。
		var resolved_path: String = _resolve_existing_path("%s/%s_%s" % [CARD_AUDIO_DIR, normalized_card_id, name_system])
		if not resolved_path.is_empty():
			# 卡牌音效不使用多音效池；包成单元素池以复用统一返回结构。
			var resolved_pool: Array[String] = [resolved_path]
			return resolved_pool
	return []


## 解析指定场景的BGM候选池。
## 同一场景的无序号单曲与多首编号曲目会合并为同一候选池，随机选曲但不影响循环播放。
## 返回空数组表示该场景没有可用BGM，由调用方保持当前播放状态不变。
func resolve_bgm_pool(scene_id: String) -> Array[String]:
	# 规范化场景标识；空标识无法定位BGM目录中的文件。
	var normalized_scene_id: String = scene_id.strip_edges()
	if normalized_scene_id.is_empty():
		return []
	# 场景基名；全部BGM位于统一目录下，以场景标识作为文件名前缀。
	var base_path: String = "%s/%s" % [BGM_DIR, normalized_scene_id]
	# 候选池；先收集编号曲目，再补充无序号单曲，二者都可参与随机。
	var pool: Array[String] = _collect_existing_pool(base_path)
	var single_path: String = _resolve_existing_path(base_path)
	if not single_path.is_empty():
		pool.append(single_path)
	return pool


## 加载音频流；路径为空、资源不存在或类型不符时返回 null，由调用方静默跳过播放。
## 加载成功的流会进入缓存，同一路径后续请求不再读取磁盘。
func load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	# 磁盘加载结果；非 AudioStream 资源（例如同名误放的场景文件）按缺失处理，不写入缓存。
	var stream: AudioStream = ResourceLoader.load(path) as AudioStream
	if stream == null:
		return null
	_stream_cache[path] = stream
	return stream


## 清空音频流缓存；仅供诊断与自动化测试使用，正常流程不需要主动调用。
func clear_cache() -> void:
	_stream_cache.clear()


## 收集以给定基名加序号构成的多音效池；返回全部实际存在的路径，序号按升序排列。
func _collect_existing_pool(base_path: String) -> Array[String]:
	# 池路径结果；只包含真实存在的文件，随机时不会命中空路径。
	var pool: Array[String] = []
	for pool_index: int in range(FIRST_POOL_INDEX, MAX_POOL_SIZE + 1):
		# 当前序号的候选路径；扩展名按全局优先级探测。
		var resolved_path: String = _resolve_existing_path("%s_%d" % [base_path, pool_index])
		if not resolved_path.is_empty():
			pool.append(resolved_path)
	return pool


## 按扩展名优先级探测单个音频文件；返回首个存在的完整路径，全部不存在时返回空字符串。
func _resolve_existing_path(base_path: String) -> String:
	for extension: String in AUDIO_EXTENSIONS:
		# 当前扩展名的候选路径；扩展名顺序即音频格式的优先顺序。
		var candidate_path: String = "%s.%s" % [base_path, extension]
		if _path_exists(candidate_path):
			return candidate_path
	return ""


## 判定候选路径是否存在；已注入探测器时使用探测器，否则使用引擎资源存在性检查。
func _path_exists(candidate_path: String) -> bool:
	if path_probe.is_valid():
		return bool(path_probe.call(candidate_path))
	return ResourceLoader.exists(candidate_path)
