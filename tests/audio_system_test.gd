extends Node

## 音频系统专项测试：校验目录约定、候选路径回退链、播放器行为、总线联动与核心层触发时机。
## 大部分断言使用内存探测器与内存音频流，素材缺失时依然稳定通过；最后一个用例改为探测真实磁盘文件，
## 用于确认实际投放的音频素材已经就位并能被引擎加载。
## 路径解析使用虚构路径，绝不读写磁盘；只有核心层触发用例会真实开局，以覆盖“AI 自动出牌即发声”的完整链路。
## 武将阵亡语音同样用虚构路径校验回退链：项目尚未为每名武将投放阵亡语音，因此不要求真实素材存在。
## BGM 场景隔离由两处断言守住：播放器用例证明“进入无素材场景会停止上一场景的曲目”，
## 桥接用例用桩服务证明“主菜单与战斗的每次迁移都会先释放旧场景、再进入新场景，且节点卸载不遗留BGM”。

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

## 真实卡牌 ID：没有投放专属配音的卡牌；用于确认它只播放基础伴随音效而不是整张牌静默。
const PROBE_UNCOVERED_CARD_ID: String = "tao"

## 属性【杀】卡牌 ID：火【杀】与雷【杀】；它们各自拥有独立的专属配音，不共用【杀】的素材。
const PROBE_NATURE_SLASH_CARD_IDS: Array[String] = ["sha_fire", "sha_thunder"]

## 已实装的效果音标识；与 game_data/audio/effect 下的素材文件名逐一对应。
## 该清单是效果音迁移验收的权威快照：新增或删除效果音时必须同步维护，
## 素材缺失会直接报出具体标识，而不是让对应规则事件在运行时静默无声。
## 覆盖范围：普通与属性伤害、护甲承伤、体力回复、失去体力、连环与解除连环、五个装备槽位、终局胜负与平局。
const REQUIRED_EFFECT_IDS: Array[String] = [
	"damage", "damage2",
	"damage_fire", "damage_fire2",
	"damage_thunder", "damage_thunder2",
	"hujia_damage", "hujia_damage2",
	"hujia_damage_fire", "hujia_damage_fire2",
	"hujia_damage_thunder", "hujia_damage_thunder2",
	"recover", "loseHp",
	"link", "link_clear",
	"equip1", "equip2", "equip3", "equip4", "equip5",
	"win", "lose", "tie",
]

## 刻意未投放素材的效果音标识；项目没有冰属性伤害、没有判定与掷道具玩法，
## 因此这些标识必须解析为空字符串，绝不能回退到任何近似音效而播出与规则事件不符的声音。
const ABSENT_EFFECT_IDS: Array[String] = ["damage_ice", "damage_male", "damage_female", "draw", "discard", "judge", "coin", "throw_egg1"]

## 效果音标识推导用例；每项由“伤害属性、伤害点数、护盾实际吸收量、期望标识”组成。
## 覆盖基础音、点数加重音、火与雷属性音以及护甲承伤四类组合，防止后缀拼接顺序被改错。
const DAMAGE_EFFECT_CASES: Array[Array] = [
	["normal", 1, 0, "damage"],
	["normal", 3, 0, "damage2"],
	["fire", 1, 0, "damage_fire"],
	["fire", 2, 0, "damage_fire2"],
	["thunder", 1, 0, "damage_thunder"],
	["thunder", 4, 0, "damage_thunder2"],
	["normal", 1, 1, "hujia_damage"],
	["normal", 2, 2, "hujia_damage2"],
	["fire", 1, 1, "hujia_damage_fire"],
	["thunder", 5, 3, "hujia_damage_thunder2"],
	["ice", 1, 0, "damage"],
]

## 核心层自动触发用例最多等待的进程帧数；全 AI 对局在零延迟下会迅速出牌，通常在数十帧内即命中。
const MAX_AUTOMATION_FRAMES: int = 600

## 阵亡自动触发用例最多等待的进程帧数；死亡结算由事件运行时逐帧推进，需要额外等待其事实提交。
const DEATH_SETTLE_MAX_FRAMES: int = 240

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
	# 音频目录约定；五个目录必须由项目预先创建，否则素材无处投放。
	for audio_dir: String in [AudioCatalog.SKILL_AUDIO_DIR, AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CHARACTER_DIE_AUDIO_DIR, AudioCatalog.EFFECT_AUDIO_DIR, AudioCatalog.BGM_DIR]:
		if not DirAccess.dir_exists_absolute(audio_dir):
			_fail("audio_directory_missing=%s" % audio_dir)
			return
	if not await _verify_skill_pool_tiers():
		return
	if not _verify_die_voice_pool():
		return
	if not _verify_card_voice_layers():
		return
	if not _verify_bgm_pool_merge():
		return
	if not _verify_real_audio_assets():
		return
	if not _verify_effect_audio_assets():
		return
	if not _verify_extension_priority():
		return
	if not await _verify_voice_player():
		return
	if not await _verify_bgm_player():
		return
	if not _verify_bgm_scene_isolation():
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


## 校验武将阵亡语音的两级短路顺序；阵亡语音按武将ID命名，多音效池优先于单音效且没有通用兜底。
func _verify_die_voice_pool() -> bool:
	# 虚构存在集合；键为完整候选路径，值恒为true，模拟磁盘上真实存在的素材。
	var existing_paths: Dictionary = {}
	# 两级路径；由具体到唯一。
	var die_pool_path: String = "%s/%s_1.ogg" % [AudioCatalog.CHARACTER_DIE_AUDIO_DIR, PROBE_CHARACTER_ID]
	var die_single_path: String = "%s/%s.ogg" % [AudioCatalog.CHARACTER_DIE_AUDIO_DIR, PROBE_CHARACTER_ID]
	existing_paths[die_pool_path] = true
	existing_paths[die_single_path] = true
	# 解析器实例；注入内存探测器后完全不访问磁盘。
	var catalog: AudioCatalog = AudioCatalog.new()
	catalog.path_probe = func(candidate_path: String) -> bool: return existing_paths.has(candidate_path)
	# 多音效池存在时优先；即使同名单音效同时存在也不与池混播，避免随机性失真。
	if not _expect_pool(catalog.resolve_character_die_voice_pool(PROBE_CHARACTER_ID), [die_pool_path], "die_pool_before_single"):
		return false
	# 池缺失后回退该武将的单音效；此时阵亡语音仍然存在，不会静默。
	existing_paths.erase(die_pool_path)
	if not _expect_pool(catalog.resolve_character_die_voice_pool(PROBE_CHARACTER_ID), [die_single_path], "die_single_fallback"):
		return false
	# 该武将没有投放素材；阵亡语音没有通用兜底层，必须返回空池而不是借用技能音效或其他武将素材。
	existing_paths.erase(die_single_path)
	if not _expect_pool(catalog.resolve_character_die_voice_pool(PROBE_CHARACTER_ID), [], "die_missing_silent"):
		return false
	# 空武将ID；未选将或武将未知时无法构造路径，同样返回空池。
	if not _expect_pool(catalog.resolve_character_die_voice_pool(""), [], "die_empty_character"):
		return false
	return true


## 校验卡牌音效的两层叠加：基础伴随音效每张牌都有，专属牌名配音按性别与名称体系逐级命中。
func _verify_card_voice_layers() -> bool:
	# 虚构存在集合；先只投放基础伴随音效，用于确认它是与牌名无关的固定一层。
	var existing_paths: Dictionary = {}
	var default_path: String = "%s/%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME]
	var male_path: String = "%s/%s/%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CARD_GENDER_MALE, PROBE_CARD_ID]
	var female_custom_path: String = "%s/%s/%s_%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, AudioCatalog.CARD_GENDER_FEMALE, PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM]
	var plain_custom_path: String = "%s/%s_%s.ogg" % [AudioCatalog.CARD_AUDIO_DIR, PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM]
	existing_paths[default_path] = true
	var catalog: AudioCatalog = AudioCatalog.new()
	catalog.path_probe = func(candidate_path: String) -> bool: return existing_paths.has(candidate_path)
	# 只有基础音效；任意卡牌都必须拿到它，证明它不是“缺失专属时才用”的兜底而是固定伴随层。
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path], "card_base_always"):
		return false
	# 空卡牌ID；无法构造专属路径，但基础音效仍然播放。
	if not _expect_pool(catalog.resolve_card_voice_paths("", AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path], "card_base_empty_id"):
		return false
	# 补入男声专属配音；男性使用者应同时播放基础音效与专属配音两层。
	existing_paths[male_path] = true
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path, male_path], "card_male_two_layers"):
		return false
	# 女性使用者没有专属配音；只播放基础音效，而不是整张牌静默。
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE), [default_path], "card_female_base_only"):
		return false
	# 未指定性别；跳过性别专属目录但保留基础音效。
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, ""), [default_path], "card_no_gender_base_only"):
		return false
	# 未知性别取值；不得拼出无效子目录，同样只保留基础音效。
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, "unknown"), [default_path], "card_unknown_gender_base_only"):
		return false
	# 补入女声当前体系配音；女性使用者改用该专属配音，男性使用者不受影响。
	existing_paths[female_custom_path] = true
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE), [default_path, female_custom_path], "card_female_two_layers"):
		return false
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path, male_path], "card_male_unaffected"):
		return false
	# 名称体系回退；请求原版牌名时该体系缺失，必须回退到同一性别下的自定义体系配音。
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_ORIGINAL, AudioCatalog.CARD_GENDER_FEMALE), [default_path, female_custom_path], "card_system_fallback"):
		return false
	# 性别层整体缺失；不分性别的当前体系文件仍然优先于“只剩基础音效”。
	existing_paths.erase(male_path)
	existing_paths.erase(female_custom_path)
	existing_paths[plain_custom_path] = true
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path, plain_custom_path], "card_plain_two_layers"):
		return false
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_ORIGINAL, AudioCatalog.CARD_GENDER_FEMALE), [default_path, plain_custom_path], "card_plain_system_fallback"):
		return false
	# 专属层全部缺失；退回只播基础音效，仍然有声。
	existing_paths.erase(plain_custom_path)
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [default_path], "card_base_only_again"):
		return false
	# 基础音效也缺失；此时才是真正的空结果，由调用方静默处理。
	existing_paths.erase(default_path)
	if not _expect_pool(catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE), [], "card_all_missing"):
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
	# 基础伴随音效；虚构卡牌也能拿到它，命中即证明 default 素材已真实投放。
	var base_paths: Array[String] = catalog.resolve_card_voice_paths(PROBE_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE)
	if base_paths.size() != 1 or not base_paths[0].contains(AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME):
		_fail("real_card_default_audio=%s" % str(base_paths))
		return false
	# 男声【杀】；必须同时拿到基础伴随音效与 male 子目录下的专属配音两层。
	var male_sha: Array[String] = catalog.resolve_card_voice_paths(PROBE_REAL_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE)
	if male_sha.size() != 2 or not male_sha[0].contains(AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME):
		_fail("real_card_male_sha_base=%s" % str(male_sha))
		return false
	if not male_sha[1].contains("/%s/%s" % [AudioCatalog.CARD_GENDER_MALE, PROBE_REAL_CARD_ID]):
		_fail("real_card_male_sha_voice=%s" % str(male_sha))
		return false
	# 女声【杀】；专属配音必须落在 female 子目录，且与男声指向不同文件，否则性别维度形同虚设。
	var female_sha: Array[String] = catalog.resolve_card_voice_paths(PROBE_REAL_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE)
	if female_sha.size() != 2:
		_fail("real_card_female_sha_size=%s" % str(female_sha))
		return false
	if not female_sha[1].contains("/%s/%s" % [AudioCatalog.CARD_GENDER_FEMALE, PROBE_REAL_CARD_ID]):
		_fail("real_card_female_sha_voice=%s" % str(female_sha))
		return false
	if female_sha[1] == male_sha[1]:
		_fail("real_card_gender_not_separated=%s" % female_sha[1])
		return false
	# 没有专属配音的卡牌；只播放基础伴随音效，而不是整张牌静默。
	var uncovered_paths: Array[String] = catalog.resolve_card_voice_paths(PROBE_UNCOVERED_CARD_ID, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_FEMALE)
	if uncovered_paths.size() != 1 or not uncovered_paths[0].contains(AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME):
		_fail("real_card_uncovered=%s" % str(uncovered_paths))
		return false
	# 属性【杀】各自拥有专属配音；火【杀】与雷【杀】必须解析到自己的素材，而不是共用【杀】的那一份。
	for nature_card_id: String in PROBE_NATURE_SLASH_CARD_IDS:
		# 该属性【杀】的男声播放路径；必须同样是基础伴随音效加专属配音两层。
		var nature_paths: Array[String] = catalog.resolve_card_voice_paths(nature_card_id, AudioCatalog.NAME_SYSTEM_CUSTOM, AudioCatalog.CARD_GENDER_MALE)
		if nature_paths.size() != 2 or not nature_paths[0].contains(AudioCatalog.CARD_DEFAULT_AUDIO_BASENAME):
			_fail("real_nature_slash_layers=%s:%s" % [nature_card_id, str(nature_paths)])
			return false
		# 专属配音文件名必须就是本牌稳定ID，否则说明素材投放到了错误的名字上。
		if not nature_paths[1].contains("/%s/%s" % [AudioCatalog.CARD_GENDER_MALE, nature_card_id]):
			_fail("real_nature_slash_voice=%s:%s" % [nature_card_id, str(nature_paths)])
			return false
		# 与【杀】本牌的配音必须是不同文件，否则属性【杀】的独立配音形同虚设。
		if nature_paths[1] == male_sha[1]:
			_fail("real_nature_slash_shares_sha=%s:%s" % [nature_card_id, nature_paths[1]])
			return false
	if not _verify_audio_asset_names():
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


## 校验卡牌音频目录里的每一份素材都以“卡牌稳定ID”命名，而不是以卡牌源码文件名命名。
## 这两种名字在多数卡牌上恰好相同，但在火【杀】这类牌上并不一致（源码文件名 huosha、稳定ID sha_fire），
## 一旦用错，解析器就会找不到专属配音、只播基础伴随音效，而且不会报任何错误——因此必须逐一核对。
func _verify_audio_asset_names() -> bool:
	for gender: String in [AudioCatalog.CARD_GENDER_MALE, AudioCatalog.CARD_GENDER_FEMALE]:
		# 当前性别子目录的绝对路径；目录缺失时后续断言无法成立。
		var dir_path: String = "%s/%s" % [AudioCatalog.CARD_AUDIO_DIR, gender]
		# 目录下的全部条目；包含导入产物，因此只挑出音频本体。
		var entries: PackedStringArray = DirAccess.get_files_at(dir_path)
		if entries.is_empty():
			_fail("real_audio_dir_empty=%s" % dir_path)
			return false
		for entry: String in entries:
			if not entry.ends_with(".mp3"):
				continue
			# 素材基名；必须能作为卡牌稳定ID查到定义，否则该配音永远不会被播放。
			var base_name: String = entry.get_basename()
			if GameDatabase.get_card(base_name).is_empty():
				_fail("real_audio_name_not_card_id=%s/%s" % [gender, entry])
				return false
	return true


## 校验全局效果音素材已经就位、可被引擎加载，并且没有对应规则事件的效果音不会被误命中。
## 效果音是全局唯一素材，既不区分性别与角色，也没有专属多音效池，因此这里逐个核对文件名与可加载性。
func _verify_effect_audio_assets() -> bool:
	var catalog: AudioCatalog = AudioCatalog.new()
	for effect_id: String in REQUIRED_EFFECT_IDS:
		# 解析结果；必须命中一个真实文件，否则说明该效果音的素材漏放或改了名字。
		var resolved_path: String = catalog.resolve_effect_path(effect_id)
		if resolved_path.is_empty():
			_fail("real_effect_missing=%s" % effect_id)
			return false
		# 可加载性；文件存在但导入失败时同样播不出声音，必须与缺失一样视为失败。
		if catalog.load_stream(resolved_path) == null:
			_fail("real_effect_unloadable=%s" % resolved_path)
			return false
	# 未投放标识；解析器只按精确文件名探测，不会近似匹配到其它效果音。
	for absent_effect_id: String in ABSENT_EFFECT_IDS:
		if not catalog.resolve_effect_path(absent_effect_id).is_empty():
			_fail("absent_effect_resolved=%s" % absent_effect_id)
			return false
	# 空标识；调用方没给出效果标识时必须返回空字符串，而不是命中目录本身。
	if not catalog.resolve_effect_path("").is_empty():
		_fail("empty_effect_resolved")
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
	# 暂停语义；记录面板、武将详情与机缘选择会申请对局暂停令牌冻结场景树，BGM 必须继续播放。
	# 断言使用 can_process() 读取真实处理状态，而不是只比较枚举值，避免其他层级重新接管暂停模式后失效。
	get_tree().paused = true
	# 暂停期间节点是否仍被引擎处理；false 表示背景音乐与淡入淡出会随界面暂停一起中断。
	var bgm_can_process_while_paused: bool = bgm_player.can_process()
	get_tree().paused = false
	if bgm_player.process_mode != Node.PROCESS_MODE_ALWAYS or not bgm_can_process_while_paused:
		_fail("bgm_paused_process_mode=%d can_process=%s" % [bgm_player.process_mode, bgm_can_process_while_paused])
		return false
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
	# 场景接管；重新进入战斗场景后确认曲目确实在播放。
	if not bgm_player.play_stream(AudioCatalog.BGM_SCENE_BATTLE, wav_stream):
		_fail("bgm_replay_battle")
		return false
	if not bgm_player.is_scene_playing():
		_fail("bgm_battle_not_playing")
		return false
	# 进入无素材场景；模拟“主菜单还没有投放BGM”的真实状态，空池不得返回成功。
	if bgm_player.play_pool(AudioCatalog.BGM_SCENE_MENU, [], null):
		_fail("bgm_empty_pool_reports_playing")
		return false
	# 核心回归点；进入无素材场景后上一场景的战斗曲目必须已经停止，场景归属也必须已经转移。
	# 旧实现遇到空池直接返回，战斗BGM会一直播到下一次进入有素材的场景，正是本用例拦截的缺陷。
	if bgm_player.is_scene_playing():
		_fail("bgm_stale_battle_still_playing")
		return false
	if bgm_player.get_current_scene_id() != AudioCatalog.BGM_SCENE_MENU:
		_fail("bgm_empty_pool_scene=%s" % bgm_player.get_current_scene_id())
		return false
	# 同一无素材场景重复请求；幂等返回且不会误报成功。
	if bgm_player.play_pool(AudioCatalog.BGM_SCENE_MENU, [], null):
		_fail("bgm_empty_pool_idempotent")
		return false
	# 作用域释放反例；退出一个并未持有的场景不得影响任何播放状态。
	if not bgm_player.play_stream(AudioCatalog.BGM_SCENE_BATTLE, wav_stream):
		_fail("bgm_battle_after_empty_scene")
		return false
	if bgm_player.release_scene(AudioCatalog.BGM_SCENE_MENU):
		_fail("bgm_release_foreign_scene_acted")
		return false
	if bgm_player.get_current_scene_id() != AudioCatalog.BGM_SCENE_BATTLE or not bgm_player.is_scene_playing():
		_fail("bgm_release_foreign_scene_disturbed=%s" % bgm_player.get_current_scene_id())
		return false
	# 作用域释放正例；退出当前持有的场景必须真正停止曲目并清空归属。
	if not bgm_player.release_scene(AudioCatalog.BGM_SCENE_BATTLE):
		_fail("bgm_release_current_scene")
		return false
	if bgm_player.is_scene_playing() or not bgm_player.get_current_scene_id().is_empty():
		_fail("bgm_release_current_scene_state=%s" % bgm_player.get_current_scene_id())
		return false
	bgm_player.queue_free()
	return true


## 校验桥接组件的BGM场景隔离。
## 桥接节点是“当前该播哪一套BGM”的唯一权威，因此它必须把主菜单可见性变化翻译为
## 一次显式的“先按作用域退出旧场景、再进入新场景”迁移，并在自身卸载时释放已持有的场景。
## 本用例用桩服务取代自动加载的 AudioService，从而在不接触真实音频总线与素材的前提下断言调用顺序；
## 语音来源指向不存在的节点，用于确认语音链路缺失不会影响BGM链路。
func _verify_bgm_scene_isolation() -> bool:
	# 测试容器；把桩服务、桩主菜单与桥接节点挂成同级，模拟主场景的节点布局。
	var harness: Node = Node.new()
	harness.name = "BgmIsolationHarness"
	add_child(harness)
	var sink: StubAudioSink = StubAudioSink.new()
	sink.name = "StubAudioService"
	harness.add_child(sink)
	# 桩主菜单；只有 Control 才能提供 visibility_changed 信号。
	var menu: Control = Control.new()
	menu.name = "StubMainMenu"
	menu.visible = true
	harness.add_child(menu)
	var bridge: GameAudioBridge = GameAudioBridge.new()
	bridge.name = "StubAudioBridge"
	bridge.voice_signal_source_path = NodePath("NoSuchVoiceSource")
	bridge.audio_service_path = sink.get_path()
	bridge.main_menu_path = menu.get_path()
	harness.add_child(bridge)
	# 就绪同步；主菜单可见时必须只请求主菜单场景，且不释放任何场景。
	if sink.requested_scenes != [AudioCatalog.BGM_SCENE_MENU] or not sink.released_scenes.is_empty():
		_fail("bgm_bridge_initial requested=%s released=%s" % [str(sink.requested_scenes), str(sink.released_scenes)])
		return false
	# 进入对局；主菜单隐藏必须请求战斗场景，并在请求之前先释放主菜单场景。
	menu.visible = false
	if sink.requested_scenes != [AudioCatalog.BGM_SCENE_MENU, AudioCatalog.BGM_SCENE_BATTLE]:
		_fail("bgm_bridge_enter_battle requested=%s" % str(sink.requested_scenes))
		return false
	if sink.released_scenes != [AudioCatalog.BGM_SCENE_MENU]:
		_fail("bgm_bridge_enter_battle_release released=%s" % str(sink.released_scenes))
		return false
	# 同一场景内的阶段推进；重复同步必须幂等，不得产生任何新的进入或释放请求。
	bridge._sync_bgm_scene()
	if sink.requested_scenes.size() != 2 or sink.released_scenes.size() != 1:
		_fail("bgm_bridge_same_scene_idempotent requested=%s released=%s" % [str(sink.requested_scenes), str(sink.released_scenes)])
		return false
	# 退出对局回到主菜单；这是本次修复的核心路径——必须先释放战斗场景，
	# 否则主菜单没有投放BGM素材时，战斗BGM会一直播下去。
	menu.visible = true
	if sink.released_scenes != [AudioCatalog.BGM_SCENE_MENU, AudioCatalog.BGM_SCENE_BATTLE]:
		_fail("bgm_bridge_exit_battle_release released=%s" % str(sink.released_scenes))
		return false
	if sink.requested_scenes != [AudioCatalog.BGM_SCENE_MENU, AudioCatalog.BGM_SCENE_BATTLE, AudioCatalog.BGM_SCENE_MENU]:
		_fail("bgm_bridge_back_to_menu requested=%s" % str(sink.requested_scenes))
		return false
	# 节点卸载；桥接节点离开场景树时必须释放自己持有的场景，防止BGM跨场景泄漏到下一个场景。
	harness.remove_child(bridge)
	if sink.released_scenes != [AudioCatalog.BGM_SCENE_MENU, AudioCatalog.BGM_SCENE_BATTLE, AudioCatalog.BGM_SCENE_MENU]:
		_fail("bgm_bridge_teardown_release released=%s" % str(sink.released_scenes))
		return false
	bridge.free()
	# 锚点缺失；不得把“无法判定场景”推断成战斗场景，必须保持不持有任何场景且不发任何请求。
	var orphan_sink: StubAudioSink = StubAudioSink.new()
	orphan_sink.name = "StubOrphanAudioService"
	harness.add_child(orphan_sink)
	var orphan_bridge: GameAudioBridge = GameAudioBridge.new()
	orphan_bridge.name = "StubOrphanBridge"
	orphan_bridge.voice_signal_source_path = NodePath("NoSuchVoiceSource")
	orphan_bridge.audio_service_path = orphan_sink.get_path()
	orphan_bridge.main_menu_path = NodePath("NoSuchMainMenu")
	harness.add_child(orphan_bridge)
	if not orphan_sink.requested_scenes.is_empty() or not orphan_sink.released_scenes.is_empty():
		_fail("bgm_bridge_missing_anchor requested=%s released=%s" % [str(orphan_sink.requested_scenes), str(orphan_sink.released_scenes)])
		return false
	orphan_bridge.free()
	harness.queue_free()
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
	# 效果音端口；手动请求一次应产生一条效果音类负载，负载只含效果标识而不携带任何角色信息。
	captured_requests.clear()
	controller.request_effect_voice(actor_id, MatchController.EFFECT_RECOVER)
	if captured_requests.size() != 1:
		_fail("effect_voice_port_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 效果音负载；类别与效果标识必须逐字保留，音频层据此定位 game_data/audio/effect 下的固定素材。
	var effect_request: Dictionary = captured_requests[0]
	if str(effect_request.get("kind", "")) != MatchController.VOICE_KIND_EFFECT or str(effect_request.get("effect_id", "")) != MatchController.EFFECT_RECOVER:
		_fail("effect_voice_payload=%s" % [effect_request])
		await _release_controller(controller)
		return
	# 去重；同一次规则事件内重复请求同一效果音必须被丢弃，防止伤害续接恢复时连播两次。
	controller.request_effect_voice(actor_id, MatchController.EFFECT_RECOVER)
	if captured_requests.size() != 1:
		_fail("effect_voice_dedup_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 阵亡语音端口；手动请求一次应产生一条阵亡类负载，负载只含玩家与武将ID。
	captured_requests.clear()
	# 阵亡武将ID；取当前武将显式传入，用于验证负载字段与去重键都按武将区分。
	var die_character_id: String = str(controller.state.players[0].character_id)
	controller.request_die_voice(actor_id, die_character_id)
	if captured_requests.size() != 1:
		_fail("die_voice_port_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 阵亡语音负载；类别与武将ID必须逐字保留，音频层据此定位 game_data/characters/audio/die 下的专属素材。
	var die_request: Dictionary = captured_requests[0]
	if str(die_request.get("kind", "")) != MatchController.VOICE_KIND_DIE or str(die_request.get("character_id", "")) != die_character_id:
		_fail("die_voice_payload=%s" % [die_request])
		await _release_controller(controller)
		return
	# 不传武将ID；控制器必须回退解析该玩家的当前武将，且结果与显式传参完全相同，因此本次请求被去重丢弃。
	controller.request_die_voice(actor_id)
	if captured_requests.size() != 1:
		_fail("die_voice_character_fallback_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 未知玩家且未给出武将ID；解析不出任何武将时必须静默拒绝，而不是发出带空武将ID的无效负载。
	controller.request_die_voice(-1, "")
	if captured_requests.size() != 1:
		_fail("die_voice_unknown_player_count=%d" % captured_requests.size())
		await _release_controller(controller)
		return
	# 伤害标识推导；护甲承伤、属性后缀与点数后缀必须与无名杀命名约定逐项一致。
	for damage_case: Array in DAMAGE_EFFECT_CASES:
		# 期望标识；与游戏内投放的素材文件名完全同名。
		var expected_effect_id: String = str(damage_case[3])
		# 实际推导结果；只依赖伤害属性、点数与护盾实际吸收量三个公开输入。
		var actual_effect_id: String = controller._resolve_damage_effect_id(str(damage_case[0]), int(damage_case[1]), int(damage_case[2]))
		if actual_effect_id != expected_effect_id:
			_fail("damage_effect_id=%s:%s" % [str(damage_case), actual_effect_id])
			await _release_controller(controller)
			return
	# 装备标识推导；五个装备槽位各自对应一套音效，未登记槽位必须返回空字符串而不是回退到默认音效。
	if controller._resolve_equipment_effect_id("weapon") != "equip1" or controller._resolve_equipment_effect_id("armor") != "equip2" or controller._resolve_equipment_effect_id("offensive_mount") != "equip3" or controller._resolve_equipment_effect_id("defensive_mount") != "equip4" or controller._resolve_equipment_effect_id("treasure") != "equip5":
		_fail("equipment_effect_id_slots")
		await _release_controller(controller)
		return
	if not controller._resolve_equipment_effect_id("unknown_slot").is_empty():
		_fail("equipment_effect_id_unknown=%s" % controller._resolve_equipment_effect_id("unknown_slot"))
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
	# 自动触发的效果音请求数量；同样只作副证据，AI 全流程未造成伤害、回复体力或装备牌时不视为失败。
	var auto_effect_request_count: int = 0
	for captured_request: Dictionary in captured_requests:
		if str(captured_request.get("kind", "")) == MatchController.VOICE_KIND_EFFECT:
			auto_effect_request_count += 1
	# 自动触发的阵亡语音请求数量；同样只作副证据，测试对局在观察窗口内无人阵亡时不视为失败。
	var auto_die_request_count: int = 0
	for captured_request: Dictionary in captured_requests:
		if str(captured_request.get("kind", "")) == MatchController.VOICE_KIND_DIE:
			auto_die_request_count += 1
	# 阵亡自动触发；从存活角色中选一名制造确定的阵亡，覆盖“死亡内容组件 → 控制器端口 → 表现信号”的完整链路。
	# 该断言只在未终局时构造：终局状态下核心层会停止发布表现请求，属于协议约定而不是缺陷。
	captured_requests.clear()
	# 阵亡角色；按座次取一名仍存活且已选定武将的角色，避免选中观察窗口内已经阵亡的座次。
	var victim: PlayerState = _pick_living_character_player(controller, actor_id) if not controller.state.game_over else null
	if victim != null:
		var victim_id: int = victim.player_id
		var victim_character_id: String = str(victim.character_id)
		victim.hp = 0
		controller._resolve_death(victim_id, actor_id)
		# 死亡结算由事件运行时逐帧推进；等待到阵亡请求出现为止，终局或超出帧数上限时停止等待。
		for frame_index: int in range(DEATH_SETTLE_MAX_FRAMES):
			if _has_voice_request_of_kind(captured_requests, MatchController.VOICE_KIND_DIE) or controller.state.game_over:
				break
			await get_tree().process_frame
		# 阵亡请求；必须由死亡结算自身发出，且携带死亡时的原武将ID。
		var death_request_found: bool = false
		for captured_request: Dictionary in captured_requests:
			if str(captured_request.get("kind", "")) == MatchController.VOICE_KIND_DIE and int(captured_request.get("player_id", -1)) == victim_id and str(captured_request.get("character_id", "")) == victim_character_id:
				death_request_found = true
		if not death_request_found:
			_fail("die_voice_auto_trigger=%s" % [captured_requests])
			await _release_controller(controller)
			return
	elif auto_die_request_count <= 0:
		# 观察窗口内既无人阵亡、也构造不出确定的阵亡；此时按失败处理，避免该断言被静默跳过。
		_fail("die_voice_auto_trigger_unavailable")
		await _release_controller(controller)
		return
	await _release_controller(controller)
	print("AUDIO_SYSTEM_PASS skill_tiers=4 die_tiers=2 card_layers=2 effect_assets=%d real_assets=ok asset_names=ok nature_slash=ok bgm_pool=ok bgm_isolation=ok extension_order=ok voices=ok bus=ok auto_trigger=ok auto_skill=%d auto_effect=%d auto_die=%d" % [REQUIRED_EFFECT_IDS.size(), auto_skill_request_count, auto_effect_request_count, auto_die_request_count])
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


## 从对局中挑出一名仍存活、仍在场且已选定武将的角色；按座次顺序取第一个，全部不满足时返回 null。
## 阵亡自动触发用例通过它取得确定的死者，避免选中观察窗口内已经阵亡或被移出游戏的座次。
func _pick_living_character_player(controller: MatchController, exclude_player_id: int) -> PlayerState:
	for candidate: PlayerState in controller.state.players:
		if candidate == null or not candidate.alive or candidate.out_of_game:
			continue
		if candidate.player_id == exclude_player_id or str(candidate.character_id).is_empty():
			continue
		return candidate
	return null


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


## BGM 场景请求记录桩；替代自动加载的 AudioService，只按顺序记录桥接节点发出的进入与释放请求。
## 用它可以在不触碰真实音频总线与磁盘素材的前提下断言“退出战斗时确实释放了战斗场景”，
## 因此它是本次BGM场景隔离修复的守门断言载体。
class StubAudioSink extends Node:
	## 依次收到的进入场景请求；元素为场景标识。
	var requested_scenes: Array[String] = []
	## 依次收到的释放场景请求；元素为场景标识。
	var released_scenes: Array[String] = []

	## 记录一次“进入场景”请求；真实服务在此解析素材并接管播放，桩只记录调用顺序。
	func request_bgm(scene_id: String) -> void:
		requested_scenes.append(scene_id)

	## 记录一次“按作用域释放场景”请求；恒返回true表示该场景确实由本桩持有。
	func release_bgm(scene_id: String) -> bool:
		released_scenes.append(scene_id)
		return true
