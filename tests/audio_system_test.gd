extends Node

## 音频系统专项测试：校验目录约定、候选路径回退链、播放器行为、总线联动与核心层触发时机。
## 大部分断言使用内存探测器与内存音频流，素材缺失时依然稳定通过；最后一个用例改为探测真实磁盘文件，
## 用于确认实际投放的音频素材已经就位并能被引擎加载。
## 路径解析使用虚构路径，绝不读写磁盘；只有核心层触发用例会真实开局，以覆盖“AI 自动出牌即发声”的完整链路。

## 虚构技能 ID；与任何真实技能源码文件名都不重合，避免与正式素材产生歧义。
const PROBE_SKILL_ID: String = "_audio_probe_skill"

## 虚构卡牌 ID；同样不与正式卡牌定义重合。
const PROBE_CARD_ID: String = "_audio_probe_card"

## 虚构 BGM 场景标识；不占用正式的主菜单与战斗两个场景名。
const PROBE_BGM_SCENE: String = "_audio_probe_menu"

## 虚构角色 ID；用于验证角色专属配音的优先级。
const PROBE_CHARACTER_ID: String = "qiong"

## 真实卡牌 ID：已投放男声与女声专属配音的卡牌；用于确认性别维度在真实素材上生效。
const PROBE_REAL_CARD_ID: String = "sha"

## 真实卡牌 ID：没有投放专属配音的卡牌；用于确认它会回退到全卡牌通用兜底音效。
const PROBE_UNCOVERED_CARD_ID: String = "tao"

## 核心层自动触发用例最多等待的进程帧数；全 AI 对局在零延迟下会迅速出牌，通常在数十帧内即命中。
const MAX_AUTOMATION_FRAMES: int = 600

## 避免连续重复的抽样次数；次数足够多以暴露随机实现退化为固定取值的缺陷。
const REPEAT_AVOIDANCE_SAMPLES: int = 30

## 开局固定随机种子；保证测试可复现且不依赖系统时间。
const TEST_MATCH_SEED: int = 20260714

## 测试对局人数；四人局足以覆盖出牌、响应与技能发动路径。
const TEST_MATCH_PLAYER_COUNT: int = 4

## 对局控制器节点名；必须与正式场景的组件命名约定一致，控制器内部按名称查找组件。
const CONTROLLER_NODE_NAME: String = "MatchController"


## 进入场景树后立即开始异步测试；使用 deferred 保证自动加载节点已全部就绪。
func _ready() -> void:
	call_deferred("_run")


## 依次执行全部音频系统断言；任一步失败立即以返回码1结束进程。
func _run() -> void:
	await get_tree().process_frame
	# 音频目录约定；三个目录必须由项目预先创建，否则素材无处投放。
	for audio_dir: String in [AudioCatalog.SKILL_AUDIO_DIR, AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.BGM_DIR]:
		if not DirAccess.dir_exists_absolute(audio_dir):
			_fail("audio_directory_missing=%s" % audio_dir)
			return
	if not await _verify_skill_pool_tiers():
		return
	if not _verify_card_pool_fallback():
		return
	if not _verify_bgm_pool_merge():
		return
	if not _verify_real_audio_assets():
		return
	if not _verify_extension_priority():
		return
	if not await _verify_voice_player():
		return
	if not await _verify_bgm_player():
		return
	if not _verify_audio_bus_and_volume():
		return
	await _verify_core_voice_channels()


## 校验技能音效的四级短路顺序；逐级删除虚构文件以确认每一层的命中结果。
func _verify_skill_pool_tiers() -> bool:
	# 虚构存在集合；键为完整候选路径，值恒为true，模拟磁盘上真实存在的素材。
	var existing_paths: Dictionary = {}
	# 四级路径；由具体到通用排列。
	var tier_one_path: String = "%s/%s_%s_2.ogg" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID, PROBE_CHARACTER_ID]
	var tier_two_path: String = "%s/%s_%s.ogg" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID, PROBE_CHARACTER_ID]
	var tier_three_path: String = "%s/%s_1.ogg" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID]
	var tier_four_path: String = "%s/%s.ogg" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID]
	for probe_path: String in [tier_one_path, tier_two_path, tier_three_path, tier_four_path]:
		existing_paths[probe_path] = true
	# 解析器实例；注入内存探测器后完全不访问磁盘。
	var catalog: AudioCatalog = AudioCatalog.new()
	catalog.path_probe = func(candidate_path: String) -> bool: return existing_paths.has(candidate_path)
	# 第一级；角色专属多音效池存在时优先，且不向下回退。
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, PROBE_CHARACTER_ID), [tier_one_path], "skill_tier_exclusive_pool"):
		return false
	# 第二级；专属池缺失后回退角色专属单音效。
	existing_paths.erase(tier_one_path)
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, PROBE_CHARACTER_ID), [tier_two_path], "skill_tier_exclusive_single"):
		return false
	# 第三级；角色专属全部缺失后回退通用多音效池。
	existing_paths.erase(tier_two_path)
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, PROBE_CHARACTER_ID), [tier_three_path], "skill_tier_common_pool"):
		return false
	# 第四级；仅剩通用单音效时命中它。
	existing_paths.erase(tier_three_path)
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, PROBE_CHARACTER_ID), [tier_four_path], "skill_tier_common_single"):
		return false
	# 四级全部缺失；必须返回空池而不是错误路径，调用方据此静默跳过。
	existing_paths.erase(tier_four_path)
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, PROBE_CHARACTER_ID), [], "skill_tier_missing"):
		return false
	# 未指定角色；必须跳过专属两级直接命中通用单音效，保证未选将时也有配音。
	existing_paths[tier_four_path] = true
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, ""), [tier_four_path], "skill_no_character_fallback"):
		return false
	return true


## 校验卡牌音效的性别专属优先级、名称体系回退与全卡牌通用兜底。
func _verify_card_pool_fallback() -> bool:
	# 虚构存在集合；同时投放性别专属、不分性别与通用兜底三层，用于验证优先级与回退方向。
	var existing_paths: Dictionary = {}
	var male_path: String = "%s/%s/%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CARD_GENDER_MALE, PROBE_CARD_ID]
	var female_custom_path: String = "%s/%s/%s_%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CARD_GENDER_FEMALE, PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM]
	var plain_custom_path: String = "%s/%s_%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM]
	var default_path: String = "%s/%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME]
	existing_paths[male_path] = true
	existing_paths[default_path] = true
	var catalog: AudioCatalog = AudioCatalog.new()
	catalog.path_probe = func(candidate_path: String) -> bool: return existing_paths.has(candidate_path)
	# 男声专属；使用者为男性时必须优先使用 male 子目录中的配音，而不是通用兜底。
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [male_path], "card_gender_priority"):
		return false
	# 女声缺失；使用者为女性时该牌没有专属配音，必须回退到全卡牌通用兜底。
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE), [default_path], "card_gender_missing_fallback"):
		return false
	# 未指定性别；必须跳过性别专属目录直接命中通用兜底，保证未选将时也有声音。
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, ""), [default_path], "card_no_gender_fallback"):
		return false
	# 未知性别取值；不得拼出无效子目录，同样回退通用兜底。
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, "unknown"), [default_path], "card_unknown_gender_fallback"):
		return false
	# 补入女声的当前体系配音；女性使用者改用该专属文件，男性使用者不受影响。
	existing_paths[female_custom_path] = true
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE), [female_custom_path], "card_female_system_priority"):
		return false
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [male_path], "card_male_unaffected"):
		return false
	# 名称体系回退；女性使用者请求原版牌名配音时该体系缺失，必须回退到同一性别下的自定义体系文件。
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_ORIGINAL, AudioCatalog.CARD_GENDER_FEMALE), [female_custom_path], "card_gender_system_fallback"):
		return false
	# 性别层整体缺失；不分性别的当前体系文件仍然优先于通用兜底。
	existing_paths.erase(male_path)
	existing_paths.erase(female_custom_path)
	existing_paths[plain_custom_path] = true
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [plain_custom_path], "card_plain_system_priority"):
		return false
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE), [plain_custom_path], "card_plain_shared"):
		return false
	# 名称体系回退；请求原版牌名时该体系缺失，必须回退到另一体系的不分性别文件。
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_ORIGINAL, AudioCatalog.CARD_GENDER_FEMALE), [plain_custom_path], "card_plain_system_fallback"):
		return false
	# 专属全部缺失；只要通用兜底存在就仍会发声，不会出现静默的牌。
	existing_paths.erase(plain_custom_path)
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path], "card_all_missing_uses_default"):
		return false
	# 连通用兜底都不存在；返回空池由调用方静默处理。
	existing_paths.erase(default_path)
	if not _expect_pool(catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [], "card_missing"):
		return false
	return true


## 校验 BGM 候选池把编号曲目与无序号单曲合并为同一个随机池。
func _verify_bgm_pool_merge() -> bool:
	# 虚构存在集合；两首编号曲目与一首无序号单曲，覆盖“多首随机”与“单曲兜底”两种投放方式。
	var existing_paths: Dictionary = {}
	var numbered_one: String = "%s/%s_1.ogg" % [AudioCatalog.BGM_DIR, PROBE_BGM_SCENE]
	var numbered_two: String = "%s/%s_2.ogg" % [AudioCatalog.BGM_DIR, PROBE_BGM_SCENE]
	var single_track: String = "%s/%s.ogg" % [AudioCatalog.BGM_DIR, PROBE_BGM_SCENE]
	for probe_path: String in [numbered_one, numbered_two, single_track]:
		existing_paths[probe_path] = true
	var catalog: AudioCatalog = AudioCatalog.new()
	catalog.path_probe = func(candidate_path: String) -> bool: return existing_paths.has(candidate_path)
	# 合并顺序；编号曲目按序号升序在前，无序号单曲追加在后。
	if not _expect_pool(catalog.resolve_bgm_pool(PROBE_BGM_SCENE), [numbered_one, numbered_two, single_track], "bgm_merged_pool"):
		return false
	# 仅有无序号单曲；仍然是合法候选池，进入场景后照常播放。
	existing_paths.erase(numbered_one)
	existing_paths.erase(numbered_two)
	if not _expect_pool(catalog.resolve_bgm_pool(PROBE_BGM_SCENE), [single_track], "bgm_single_only"):
		return false
	# 该场景没有任何BGM；返回空池，调用方保持当前播放状态不变。
	existing_paths.erase(single_track)
	if not _expect_pool(catalog.resolve_bgm_pool(PROBE_BGM_SCENE), [], "bgm_missing"):
		return false
	# BGM显示名；无序号后缀的曲目在游戏内显示为“默认”，带序号时附带序号以便区分多首候选。
	if catalog.get_bgm_display_name(single_track) != AudioCatalog.BGM_DEFAULT_DISPLAY_NAME:
		_fail("bgm_display_name_default=%s" % catalog.get_bgm_display_name(single_track))
		return false
	if catalog.get_bgm_display_name(numbered_two) != "%s 2" % AudioCatalog.BGM_DEFAULT_DISPLAY_NAME:
		_fail("bgm_display_name_numbered=%s" % catalog.get_bgm_display_name(numbered_two))
		return false
	return true


## 校验真实投放的音频素材能被解析器发现。
## 本函数走真实磁盘探测而非注入探测器，因此它是“素材已就位且可被引擎加载”的守门测试。
func _verify_real_audio_assets() -> bool:
	var catalog: AudioCatalog = AudioCatalog.new()
	# 通用兜底音效；虚构卡牌必然回退到它，命中即证明 default 素材已真实投放。
	var default_pool: Array[String] = catalog.resolve_card_voice_pool(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, "")
	if default_pool.size() != 1 or not default_pool[0].contains(AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME):
		_fail("real_card_default_audio=%s" % str(default_pool))
		return false
	# 男声【杀】；必须解析到 male 子目录下的真实文件。
	var male_sha: Array[String] = catalog.resolve_card_voice_pool(PROBE_REAL_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE)
	if male_sha.size() != 1 or not male_sha[0].contains("/%s/%s" % [AudioCatalog.CARD_GENDER_MALE, PROBE_REAL_CARD_ID]):
		_fail("real_card_male_sha=%s" % str(male_sha))
		return false
	# 女声【杀】；必须解析到 female 子目录下的真实文件，证明性别维度确实生效且两套配音互不串用。
	var female_sha: Array[String] = catalog.resolve_card_voice_pool(PROBE_REAL_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE)
	if female_sha.size() != 1 or not female_sha[0].contains("/%s/%s" % [AudioCatalog.CARD_GENDER_FEMALE, PROBE_REAL_CARD_ID]):
		_fail("real_card_female_sha=%s" % str(female_sha))
		return false
	# 两个性别必须解析到不同文件；否则性别维度形同虚设。
	if male_sha[0] == female_sha[0]:
		_fail("real_card_gender_not_separated=%s" % male_sha[0])
		return false
	# 未投放专属配音的卡牌；【桃】没有单独素材，必须回退到通用兜底而不是静默。
	var tao_pool: Array[String] = catalog.resolve_card_voice_pool(PROBE_UNCOVERED_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE)
	if tao_pool.size() != 1 or not tao_pool[0].contains(AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME):
		_fail("real_card_uncovered_fallback=%s" % str(tao_pool))
		return false
	# 战斗BGM；必须真实存在，且游戏内显示名为“默认”。
	var bgm_pool: Array[String] = catalog.resolve_bgm_pool(AudioCatalog.BGM_SCENE_BATTLE)
	if bgm_pool.is_empty():
		_fail("real_bgm_battle_missing")
		return false
	if catalog.get_bgm_display_name(bgm_pool[0]) != AudioCatalog.BGM_DEFAULT_DISPLAY_NAME:
		_fail("real_bgm_battle_name=%s" % catalog.get_bgm_display_name(bgm_pool[0]))
		return false
	return true


## 校验同一基名存在多种格式时按 ogg、wav、mp3 的固定优先级取用首个。
func _verify_extension_priority() -> bool:
	# 虚构存在集合；先只放 wav 与 mp3，再补入 ogg 观察优先级切换。
	var existing_paths: Dictionary = {}
	var wav_path: String = "%s/%s.wav" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID]
	var mp3_path: String = "%s/%s.mp3" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID]
	var ogg_path: String = "%s/%s.ogg" % [AudioCatalog.SKILL_AUDIO_DIR, PROBE_SKILL_ID]
	existing_paths[wav_path] = true
	existing_paths[mp3_path] = true
	var catalog: AudioCatalog = AudioCatalog.new()
	catalog.path_probe = func(candidate_path: String) -> bool: return existing_paths.has(candidate_path)
	# 无ogg时；wav优先于mp3。
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, ""), [wav_path], "extension_wav_before_mp3"):
		return false
	# 补入ogg后；ogg应立刻取代wav成为首选，体积最小且支持原生循环标记。
	existing_paths[ogg_path] = true
	if not _expect_pool(catalog.resolve_skill_voice_pool(PROBE_SKILL_ID, ""), [ogg_path], "extension_ogg_first"):
		return false
	return true


## 校验语音播放器的按需分配、播放结束回收、无并发上限与池内随机不连续重复。
func _verify_voice_player() -> bool:
	var voice_player: AudioVoicePlayer = AudioVoicePlayer.new()
	add_child(voice_player)
	await get_tree().process_frame
	# 首次申请；空闲池为空因此新建播放器，同时播放数量变为1。
	var first_player: AudioStreamPlayer = voice_player._acquire_player()
	if first_player == null or voice_player.get_active_voice_count() != 1:
		_fail("voice_player_acquire")
		return false
	# 模拟播放结束；播放器必须回收到空闲池并从在播集合移除。
	voice_player._on_player_finished(first_player)
	if voice_player.get_active_voice_count() != 0:
		_fail("voice_player_recycle")
		return false
	# 再次申请；必须复用同一实例而不是新建节点，避免长时间对局累积节点。
	var reused_player: AudioStreamPlayer = voice_player._acquire_player()
	if reused_player != first_player:
		_fail("voice_player_reuse")
		return false
	# 并发申请；不设并发上限，必须新建第二个播放器而不是复用正在播放的实例。
	var second_player: AudioStreamPlayer = voice_player._acquire_player()
	if second_player == first_player or voice_player.get_active_voice_count() != 2:
		_fail("voice_player_no_concurrency_cap")
		return false
	# 统一停止；全部在播语音立即停止并回收。
	voice_player.stop_all()
	if voice_player.get_active_voice_count() != 0:
		_fail("voice_player_stop_all")
		return false
	# 池内随机；记录上一首后连续抽样都不得再命中同一文件。
	var probe_pool: Array[String] = ["a.ogg", "b.ogg", "c.ogg"]
	voice_player._last_played_path_by_pool["probe"] = "b.ogg"
	for sample_index: int in range(REPEAT_AVOIDANCE_SAMPLES):
		if voice_player._pick_random_path(probe_pool, "probe") == "b.ogg":
			_fail("voice_player_avoid_immediate_repeat")
			return false
	# 关闭避免重复；取值必须仍然落在池内，不能返回池外路径。
	voice_player.avoid_immediate_repeat = false
	if not probe_pool.has(voice_player._pick_random_path(probe_pool, "probe")):
		_fail("voice_player_random_range")
		return false
	# 单元素池；即使该文件正是上一次播放的文件，也必须照常返回它，否则该技能会彻底失声。
	voice_player._last_played_path_by_pool["probe"] = "a.ogg"
	if voice_player._pick_random_path(["a.ogg"], "probe") != "a.ogg":
		_fail("voice_player_single_item_pool")
		return false
	voice_player.queue_free()
	return true


## 校验BGM播放器的循环强制设置与同场景幂等语义。
func _verify_bgm_player() -> bool:
	var bgm_player: AudioBgmPlayer = AudioBgmPlayer.new()
	# 关闭淡入淡出；测试关注循环与幂等语义，不需要等待补间完成。
	bgm_player.use_crossfade = false
	add_child(bgm_player)
	await get_tree().process_frame
	# 初始状态；尚未播放任何场景BGM。
	if not bgm_player.get_current_scene_id().is_empty():
		_fail("bgm_initial_scene=%s" % bgm_player.get_current_scene_id())
		return false
	# 循环标记；wav与ogg都必须被强制开启循环，避免BGM只播一遍。
	var wav_stream: AudioStreamWAV = AudioStreamWAV.new()
	bgm_player._enable_loop(wav_stream)
	var ogg_stream: AudioStreamOggVorbis = AudioStreamOggVorbis.new()
	bgm_player._enable_loop(ogg_stream)
	if wav_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD or not ogg_stream.loop:
		_fail("bgm_loop_flag wav=%d ogg=%s" % [wav_stream.loop_mode, ogg_stream.loop])
		return false
	# 实际播放；首次请求应返回true并记录场景标识。
	if not bgm_player.play_stream(AudioCatalog.BGM_SCENE_MENU, wav_stream):
		_fail("bgm_first_play")
		return false
	if bgm_player.get_current_scene_id() != AudioCatalog.BGM_SCENE_MENU:
		_fail("bgm_scene_recorded=%s" % bgm_player.get_current_scene_id())
		return false
	# 同一场景重复请求；正在播放时必须幂等返回false，避免选将、结算等阶段反复切歌导致音乐中断。
	if bgm_player.play_stream(AudioCatalog.BGM_SCENE_MENU, wav_stream):
		_fail("bgm_same_scene_idempotent")
		return false
	# 切换场景；不同场景必须允许切换并返回true。
	if not bgm_player.play_stream(AudioCatalog.BGM_SCENE_BATTLE, wav_stream):
		_fail("bgm_scene_switch")
		return false
	if bgm_player.get_current_scene_id() != AudioCatalog.BGM_SCENE_BATTLE:
		_fail("bgm_scene_switch_recorded=%s" % bgm_player.get_current_scene_id())
		return false
	# 停止；场景标识清空，使下一次同场景请求可以重新播放。
	bgm_player.stop_bgm()
	if not bgm_player.get_current_scene_id().is_empty():
		_fail("bgm_stop_clears_scene")
		return false
	bgm_player.queue_free()
	return true


## 校验音频服务创建的两条总线、静音开关与线性音量换算。
func _verify_audio_bus_and_volume() -> bool:
	# 音频服务自动加载节点；由项目设置注册，测试直接复用正式实例。
	var audio_service: Node = get_node_or_null("/root/AudioService")
	if audio_service == null:
		_fail("audio_service_autoload_missing")
		return false
	# 两条总线；必须由服务在运行时创建并挂到主总线之下。
	for bus_name: String in [AudioService.BGM_BUS_NAME, AudioService.SFX_BUS_NAME]:
		# 总线索引；小于0表示服务未能创建该总线。
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			_fail("audio_bus_missing=%s" % bus_name)
			return false
		if AudioServer.get_bus_send(bus_index) != "Master":
			_fail("audio_bus_send=%s" % bus_name)
			return false
	# 音量联动；写入设置后BGM总线分贝必须立即等于线性音量换算结果。
	var original_bgm_volume: float = GameSettings.bgm_volume
	var original_sfx_volume: float = GameSettings.sfx_volume
	var original_muted: bool = GameSettings.audio_muted
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioService.BGM_BUS_NAME)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioService.SFX_BUS_NAME)
	GameSettings.set_bgm_volume(0.5)
	if not is_equal_approx(AudioServer.get_bus_volume_db(bgm_bus_index), linear_to_db(0.5)):
		_fail("audio_bgm_volume_db=%f" % AudioServer.get_bus_volume_db(bgm_bus_index))
		return false
	# 静音开关；两条总线必须同时静音，且已保存的音量数值不被改写。
	GameSettings.set_audio_muted(true)
	if not AudioServer.is_bus_mute(bgm_bus_index) or not AudioServer.is_bus_mute(sfx_bus_index):
		_fail("audio_mute_both_buses")
		return false
	GameSettings.set_audio_muted(false)
	if AudioServer.is_bus_mute(bgm_bus_index) or AudioServer.is_bus_mute(sfx_bus_index):
		_fail("audio_unmute_both_buses")
		return false
	# 零音量；必须走总线静音开关，而不是把负无穷写入分贝属性。
	GameSettings.set_bgm_volume(0.0)
	if not AudioServer.is_bus_mute(bgm_bus_index):
		_fail("audio_zero_volume_uses_mute")
		return false
	# 还原玩家设置；避免测试污染真实设置文件与后续用例。
	GameSettings.set_audio_muted(original_muted)
	GameSettings.set_bgm_volume(original_bgm_volume)
	GameSettings.set_sfx_volume(original_sfx_volume)
	return true


## 校验核心层的语音请求端口、去重表、技能统一出口自动触发与真实对局自动触发。
func _verify_core_voice_channels() -> void:
	# 测试对局控制器；按正式场景的组件结构装配最小组件，保证节点名与控制器内部查找一致。
	var controller: MatchController = MatchController.new()
	controller.name = CONTROLLER_NODE_NAME
	controller.local_human_player_id = -1
	controller.ai_action_delay_seconds = 0.0
	# 规则事件总线；技能与卡牌时机都通过它派发。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	controller.add_child(event_bus)
	# AI 调度组件；全部座次登记基础策略，使对局可以无人操作地推进。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	controller.add_child(ai_coordinator)
	# 通信网关；保持离线模式，不接入外部网络。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	controller.add_child(network_gateway)
	get_tree().root.add_child(controller)
	await get_tree().process_frame
	# 控制器入树时会读取全局菜单设置，因此在就绪后再次归零，保证固定帧数内能推进对局。
	controller.ai_action_delay_seconds = 0.0
	controller.game_flow_interval_seconds = 0.0
	# 开局；未建立对局状态时语音端口会静默拒绝请求，因此必须先开局。
	if not controller.start_match(TEST_MATCH_PLAYER_COUNT, TEST_MATCH_SEED, "identity"):
		_fail("controller_start_match")
		await _release_controller(controller)
		return
	# 语音表现请求收集；只订阅公开信号，不读取控制器内部规则状态。
	var captured_requests: Array[Dictionary] = []
	controller.voice_presentation_requested.connect(func(presentation_data: Dictionary) -> void: captured_requests.append(presentation_data))
	# 联机表现通道；语音请求信号必须已连接到广播入口，网络事件信号也必须已连接到客户端分派入口。
	# 两处连接都是局域网客户端听到主机权威音效的前提，缺少任一连接都会让联机对局失去全部语音。
	if not controller.voice_presentation_requested.is_connected(controller._replicate_voice_presentation_event):
		_fail("voice_presentation_not_replicated")
		await _release_controller(controller)
		return
	if not controller.network_gateway.game_event_received.is_connected(controller._on_network_game_event_received):
		_fail("voice_presentation_client_dispatch_missing")
		await _release_controller(controller)
		return
	# 使用者座次；取首个玩家，其武将已由开局流程安装完毕。
	var actor_id: int = controller.state.players[0].player_id
	# 卡牌语音端口；手动请求一次应产生一条卡牌类负载。
	controller.request_card_voice(actor_id, "sha", MatchController.VOICE_PLAY_MODE_USE)
	if captured_requests.size() != 1:
		_fail("card_voice_port_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 负载字段；必须携带稳定的类别、牌定义与两套牌名，供音频层选择与联机广播。
	var first_request: Dictionary = captured_requests[0]
	# 两套牌名负载；缺失任一名称都会导致某一显示模式下找不到配音。
	var card_names: Dictionary = first_request.get("card_names", {}) as Dictionary
	if str(first_request.get("kind", "")) != MatchController.VOICE_KIND_CARD or str(first_request.get("card_definition_id", "")) != "sha" or str(card_names.get("custom", "")).is_empty() or str(card_names.get("original", "")).is_empty():
		_fail("card_voice_payload=%s" % [first_request])
		await _release_controller(controller)
		return
	# 去重；同一事件与同一动作模式的第二次请求必须被丢弃，防止同一张牌发出两次配音。
	controller.request_card_voice(actor_id, "sha", MatchController.VOICE_PLAY_MODE_USE)
	if captured_requests.size() != 1:
		_fail("card_voice_dedup_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 打出模式；与使用模式属于不同请求，应新增一条负载。
	controller.request_card_voice(actor_id, "sha", MatchController.VOICE_PLAY_MODE_RESPOND)
	if captured_requests.size() != 2:
		_fail("card_voice_respond_mode_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 技能统一出口；写入一条实际成立的发动记录后应自动产生技能类音频请求。
	captured_requests.clear()
	# 使用者武将定义；取其第一个已安装技能作为被测技能，缺失时退回通用锁定技。
	var actor_character: Dictionary = GameDatabase.get_character(controller.state.players[0].character_id)
	var actor_skills: Array = actor_character.get("skills", []) as Array
	var probe_skill_id: String = str(actor_skills[0]) if not actor_skills.is_empty() else "wangpai"
	controller.record_skill_activation(actor_id, probe_skill_id)
	# 技能请求是否存在；自动触发必须在统一出口内完成，内容技能无须逐个改造。
	var skill_request_found: bool = false
	for captured_request: Dictionary in captured_requests:
		if str(captured_request.get("kind", "")) == MatchController.VOICE_KIND_SKILL and str(captured_request.get("skill_id", "")) == probe_skill_id:
			skill_request_found = true
	if not skill_request_found:
		_fail("skill_voice_auto_trigger=%s" % [captured_requests])
		await _release_controller(controller)
		return
	# 真实对局自动触发；使用牌与响应打出都必须产生卡牌类请求，覆盖“统一出口默认触发”的完整链路。
	captured_requests.clear()
	for frame_index: int in range(MAX_AUTOMATION_FRAMES):
		await get_tree().process_frame
		# 同时等待使用与打出两种模式；前者出现更早，后者证明响应消耗出口也已接通。
		if _has_voice_request_of_kind(captured_requests, MatchController.VOICE_KIND_CARD) and _has_voice_play_mode(captured_requests, MatchController.VOICE_PLAY_MODE_RESPOND):
			break
	# 自动触发的卡牌请求；必须由对局流程自身产生，而不是测试手动调用端口。
	if not _has_voice_request_of_kind(captured_requests, MatchController.VOICE_KIND_CARD):
		_fail("card_voice_auto_trigger_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 自动触发的打出请求；响应牌消耗出口必须同样发声，否则【闪】等响应牌会静默。
	if not _has_voice_play_mode(captured_requests, MatchController.VOICE_PLAY_MODE_RESPOND):
		_fail("card_voice_auto_respond_missing=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 自动触发的技能请求数量；作为副证据记录，AI 未发动技能时不视为失败。
	var auto_skill_request_count: int = 0
	for captured_request: Dictionary in captured_requests:
		if str(captured_request.get("kind", "")) == MatchController.VOICE_KIND_SKILL:
			auto_skill_request_count += 1
	await _release_controller(controller)
	print("AUDIO_SYSTEM_PASS skill_tiers=4 card_fallback=ok card_gender=ok real_assets=ok bgm_pool=ok extension_order=ok voices=ok bus=ok auto_trigger=ok auto_skill=%d" % auto_skill_request_count)
	get_tree().quit(0)


## 释放测试对局控制器；先停止AI驱动再移出场景树，避免退出时继续结算。
func _release_controller(controller: MatchController) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	# AI 驱动令牌；自增后所有已排队的AI任务都会自行作废。
	controller._ai_drive_token += 1
	controller.ai_coordinator._policies.clear()
	get_tree().root.remove_child(controller)
	controller.free()


## 判断已收集的语音请求中是否存在指定类别的负载；用于对局自动触发用例的等待条件与断言。
func _has_voice_request_of_kind(captured_requests: Array[Dictionary], kind: String) -> bool:
	for captured_request: Dictionary in captured_requests:
		if str(captured_request.get("kind", "")) == kind:
			return true
	return false


## 判断已收集的请求中是否存在指定动作模式的卡牌负载；用于验证“使用”与“打出”两条出口都已接通。
func _has_voice_play_mode(captured_requests: Array[Dictionary], play_mode: String) -> bool:
	for captured_request: Dictionary in captured_requests:
		if str(captured_request.get("kind", "")) == MatchController.VOICE_KIND_CARD and str(captured_request.get("play_mode", "")) == play_mode:
			return true
	return false


## 断言候选池与期望完全一致；不一致时输出可诊断信息。
func _expect_pool(actual_pool: Array[String], expected_pool: Array[String], case_name: String) -> bool:
	if actual_pool == expected_pool:
		return true
	_fail("%s actual=%s expected=%s" % [case_name, str(actual_pool), str(expected_pool)])
	return false


## 输出失败信息并以返回码1结束测试进程；外部脚本据此判定失败。
func _fail(message: String) -> void:
	printerr("AUDIO_SYSTEM_FAIL %s" % message)
	get_tree().quit(1)
