extends Node

## 全局显示与对局配置入口。该节点只保存跨场景配置，不持有任何具体对局状态。

signal card_name_mode_changed(mode: NameMode)

## UI 风格变化信号；界面组件收到稳定风格标识后从统一注册表刷新自身配色。
signal ui_style_changed(style_id: String)

## AI 响应等待时长变化信号；对局控制器订阅后同步下一次 AI 行动与选牌响应的等待时间。
signal ai_response_delay_changed(delay_seconds: float)

## 游戏流程间隔变化信号；对局控制器订阅后同步后续阶段切换与自动响应的最小等待时间。
signal game_speed_changed(interval_seconds: float)

## 自动身份标记开关变化信号；牌桌只据此刷新本地推测徽记，不修改任何权威身份数据。
signal auto_identity_marking_changed(enabled: bool)

## 联机玩家名称变化信号；大厅等只读显示组件据此刷新名称，不直接访问资料设置界面的输入节点。
signal online_player_name_changed(player_name: String)

## 联机形象变化信号；参数为稳定武将 ID，联机大厅据此提交并显示玩家选择的武将插画。
signal online_avatar_character_changed(character_id: String)

## 下一局人数变化信号；主菜单与局内菜单收到后同步各自输入框，不修改正在进行的对局人数。
signal next_match_player_count_changed(player_count: int)

## 下一局模式变化信号；主菜单选中身份模式或斗地主后发出，不修改正在进行的对局模式。
signal next_match_mode_changed(mode_id: String)

## 自选全部武将、座次与身份开关变化信号；该设置只在之后由离线玩家或房主创建的新对局中生效。
signal custom_character_assignment_changed(enabled: bool)

## 房主调整全部 AI 武将开关变化信号；当前对局已越过选将阶段时不会中途插入流程。
signal customize_ai_characters_changed(enabled: bool)

## 手气卡数量变化信号；参数为0至5、10或-1，-1表示无限张，仅影响之后创建的新对局。
signal mulligan_limit_changed(limit: int)

## AI 是否使用手气卡的开关变化信号；实际张数仍受手气卡数量设置约束。
signal ai_uses_mulligan_changed(enabled: bool)

## 换将卡数量变化信号；参数只会是0、3、5、8、10或20，仅影响之后创建的新对局。
signal character_replacement_count_changed(count: int)

## 过关斩将换将卡数量变化信号；参数只会是0、3、5、8、10或20，仅影响之后创建的过关斩将对局。
signal conquest_character_replacement_count_changed(count: int)

## 随机选将牌数变化信号；参数范围为1至20，仅影响之后创建的新对局。
signal character_candidate_count_changed(count: int)

## 过关斩将随机选将牌数变化信号；参数范围为1至20，仅影响之后创建的过关斩将对局。
signal conquest_character_candidate_count_changed(count: int)

## 过关斩将难度变化信号；参数只会是一至五，仅影响之后创建的过关斩将对局。
signal conquest_difficulty_changed(difficulty: int)

## 离线下一局是否由本机控制全部角色的变化信号；联机模式不会读取该设置。
signal control_all_characters_changed(enabled: bool)

## 1v1车轮战明置候选数量变化信号；参数范围3至20，仅影响之后创建的新对局。
signal wheel_duel_face_up_candidate_count_changed(count: int)

## 1v1车轮战暗置候选数量变化信号；参数范围3至20，仅影响之后创建的新对局。
signal wheel_duel_face_down_candidate_count_changed(count: int)

## 卡牌名称显示模式；CUSTOM 展示《崩铁杀》名称，ORIGINAL 展示原版三国杀名称。
enum NameMode {
	CUSTOM,
	ORIGINAL,
}

## 卡牌名称模式的设置选项；稳定枚举值用于菜单元数据，显示文字仅用于前端下拉框。
const CARD_NAME_MODE_OPTIONS: Array[Dictionary] = [
	{"mode":NameMode.CUSTOM, "label":"崩铁杀"},
	{"mode":NameMode.ORIGINAL, "label":"三国杀"},
]

## 手气卡数量下拉选项；稳定值0表示关闭，1至5与10表示可用手气卡张数，-1表示无限张。
const MULLIGAN_LIMIT_OPTIONS: Array[Dictionary] = [
	{"value":0, "label":"关闭"},
	{"value":1, "label":"一张"},
	{"value":2, "label":"两张"},
	{"value":3, "label":"三张"},
	{"value":4, "label":"四张"},
	{"value":5, "label":"五张"},
	{"value":10, "label":"十张"},
	{"value":-1, "label":"无限张"},
]

## 换将卡数量下拉选项；稳定值0表示关闭，其余数值表示每名玩家本局最多可换将的次数。
const CHARACTER_REPLACEMENT_COUNT_OPTIONS: Array[Dictionary] = [
	{"value":0, "label":"关闭"},
	{"value":3, "label":"三张"},
	{"value":5, "label":"五张"},
	{"value":8, "label":"八张"},
	{"value":10, "label":"十张"},
	{"value":20, "label":"二十张"},
]

## 过关斩将换将卡数量默认值；0表示默认关闭，旧存档缺失字段时不会意外启用换将。
const DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT: int = 0

## 过关斩将难度下拉选项；稳定数值一至五写入存档，中文文本只负责菜单显示。
const CONQUEST_DIFFICULTY_OPTIONS: Array[Dictionary] = [
	{"value":1, "label":"难度一"},
	{"value":2, "label":"难度二"},
	{"value":3, "label":"难度三"},
	{"value":4, "label":"难度四"},
	{"value":5, "label":"难度五"},
]

## 过关斩将允许的最低难度值；难度一提供最多玩家开局机缘。
const MIN_CONQUEST_DIFFICULTY: int = 1

## 过关斩将允许的最高难度值；难度五不提供玩家开局机缘。
const MAX_CONQUEST_DIFFICULTY: int = 5

## 过关斩将默认难度；难度五保持旧版本无玩家开局增益的行为，旧存档不会因缺少字段而改变强度。
const DEFAULT_CONQUEST_DIFFICULTY: int = 5

## 随机选将牌数下拉选项；稳定数值1至20直接作为每名玩家的普通随机候选数量。
const CHARACTER_CANDIDATE_COUNT_OPTIONS: Array[Dictionary] = [
	{"value":1, "label":"一张"},
	{"value":2, "label":"两张"},
	{"value":3, "label":"三张"},
	{"value":4, "label":"四张"},
	{"value":5, "label":"五张"},
	{"value":6, "label":"六张"},
	{"value":7, "label":"七张"},
	{"value":8, "label":"八张"},
	{"value":9, "label":"九张"},
	{"value":10, "label":"十张"},
	{"value":11, "label":"十一张"},
	{"value":12, "label":"十二张"},
	{"value":13, "label":"十三张"},
	{"value":14, "label":"十四张"},
	{"value":15, "label":"十五张"},
	{"value":16, "label":"十六张"},
	{"value":17, "label":"十七张"},
	{"value":18, "label":"十八张"},
	{"value":19, "label":"十九张"},
	{"value":20, "label":"二十张"},
]

## 随机选将牌数允许的最小值；至少保留一张普通随机候选，运行时不应修改。
const MIN_CHARACTER_CANDIDATE_COUNT: int = 1

## 随机选将牌数允许的最大值；与菜单选项和选将滚动布局上限一致，运行时不应修改。
const MAX_CHARACTER_CANDIDATE_COUNT: int = 20

## 随机选将牌数默认值；5张保持旧版本开局行为，旧存档缺失字段时使用该值。
const DEFAULT_CHARACTER_CANDIDATE_COUNT: int = 5

## 过关斩将随机选将牌数默认值；12张给单人玩家与敌方AI提供更充足的随机武将选择，旧存档缺失字段时使用该值。
const DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT: int = 12

## AI 响应等待时间的最小值；默认0.05秒，在保留可见异步边界的同时支持快速对局。
## 当前范围补充：AI响应速度与游戏速度统一从0.10秒开始，避免两个设置提供不同的最低等待时间。
const MIN_AI_RESPONSE_DELAY_SECONDS: float = 0.10

## AI 响应等待时间的最大值；默认1秒，覆盖快速对局到观察型对局的常用节奏而不造成过长停顿。
const MAX_AI_RESPONSE_DELAY_SECONDS: float = 1.0

## AI 响应等待时间的调节步长；默认0.05秒，兼顾可感知变化与菜单滑条的调节精度。
## 当前步长补充：两个速度设置统一使用0.50秒步长，主菜单与局内菜单均从该常量读取。
const AI_RESPONSE_DELAY_STEP_SECONDS: float = 0.50

## 游戏流程间隔的最小值；默认0.1秒，保证连续阶段与响应之间保留可观察的画面更新边界。
const MIN_GAME_SPEED_INTERVAL_SECONDS: float = 0.1

## 游戏流程间隔的最大值；默认1秒，允许观察结算过程且避免自动流程等待过久。
const MAX_GAME_SPEED_INTERVAL_SECONDS: float = 1.0

## 游戏流程间隔的调节步长；默认0.1秒，与菜单滑条显示精度保持一致。
## 当前步长补充：流程间隔与AI响应等待共用0.50秒调节精度，避免设置入口出现不同档位。
const GAME_SPEED_INTERVAL_STEP_SECONDS: float = 0.50

## 联机玩家名称允许的最大 Unicode 字符数；20与局域网成员协议上限一致，运行时无需动态修改。
const MAX_ONLINE_PLAYER_NAME_LENGTH: int = 20

## 联机玩家名称为空时使用的默认文本；稳定回退可防止大厅成员列表出现空白行。
const DEFAULT_ONLINE_PLAYER_NAME: String = "玩家"

## 本地设置文件路径；仅保存跨启动保留的客户端偏好，不保存房间密码、ENet 会话或任何权威对局状态。
const SETTINGS_FILE_PATH: String = "user://game_settings.cfg"

## 设置文件格式版本；未来字段结构变化时可据此添加兼容迁移，当前版本从1开始。
const SETTINGS_SCHEMA_VERSION: int = 1

## 连续设置变化合并写盘的等待秒数；默认0.25秒可合并移动端滑条产生的密集事件，同时保持设置快速持久化。
const SETTINGS_SAVE_DEBOUNCE_SECONDS: float = 0.25

## 设置文件元数据分组名；该分组只保存格式版本，不承载具体游戏或联机选项。
const SETTINGS_METADATA_SECTION: String = "metadata"

## 游戏设置分组名；保存名称模式、界面风格、节奏、身份标记与下一局人数。
const GAMEPLAY_SETTINGS_SECTION: String = "gameplay"

## 联机资料分组名；只保存玩家主动选择的显示名和稳定武将形象 ID。
const ONLINE_SETTINGS_SECTION: String = "online"

## 下一局人数的最小值；与标准身份局和大厅允许的最小人数一致，运行时不应修改。
const MIN_NEXT_MATCH_PLAYER_COUNT: int = 2

## 下一局人数的最大值；与标准身份局和大厅允许的最大人数一致，运行时不应修改。
const MAX_NEXT_MATCH_PLAYER_COUNT: int = 10

## 下一局人数的默认值；与 MatchController 默认8人身份局保持一致，首次启动或无效存档时使用。
const DEFAULT_NEXT_MATCH_PLAYER_COUNT: int = 8

## 下一局标准身份局模式稳定 ID；与 IdentityRules.MODE_IDENTITY 一致。
const MATCH_MODE_IDENTITY: String = "identity"

## 下一局斗地主模式稳定 ID；与 IdentityRules.MODE_DOUDIZHU 一致。
const MATCH_MODE_DOUDIZHU: String = "doudizhu"

## 下一局 2v2 模式稳定 ID；与 IdentityRules.MODE_TEAM2V2 一致。
const MATCH_MODE_TEAM2V2: String = "team2v2"

## 下一局1v1车轮战模式稳定ID；与IdentityRules.MODE_WHEEL_DUEL一致。
const MATCH_MODE_WHEEL_DUEL: String = "wheel_duel"

## 下一局机缘大乱斗模式稳定ID；与IdentityRules.MODE_OPPORTUNITY_BRAWL一致。
const MATCH_MODE_OPPORTUNITY_BRAWL: String = "opportunity_brawl"

## 下一局过关斩将模式稳定ID；与IdentityRules.MODE_CONQUEST一致，固定由一名本地玩家对战AI。
const MATCH_MODE_CONQUEST: String = "conquest"

## 下一局默认模式；首次启动或无效存档时进入标准身份局。
const DEFAULT_NEXT_MATCH_MODE: String = MATCH_MODE_IDENTITY

## 斗地主模式默认人数；仅允许 3 或 5，默认 3 人。
const DEFAULT_DOUDIZHU_PLAYER_COUNT: int = 3

## 2v2 模式默认人数；固定 4 人。
const DEFAULT_TEAM2V2_PLAYER_COUNT: int = 4

## 1v1车轮战默认人数；固定2人。
const DEFAULT_WHEEL_DUEL_PLAYER_COUNT: int = 2

## 1v1车轮战默认明置候选数量；主公指定为6名。
const DEFAULT_WHEEL_DUEL_FACE_UP_CANDIDATE_COUNT: int = 6

## 1v1车轮战默认暗置候选数量；主公指定为4名。
const DEFAULT_WHEEL_DUEL_FACE_DOWN_CANDIDATE_COUNT: int = 4

## 1v1车轮战单类候选允许的最小值；明置与暗置设置均不可低于3。
const MIN_WHEEL_DUEL_CANDIDATE_COUNT: int = 3

## 1v1车轮战单类候选允许的最大值；明置与暗置设置均不可高于20。
const MAX_WHEEL_DUEL_CANDIDATE_COUNT: int = 20

## 身份模式默认人数；与历史全局默认 8 人保持一致。
const DEFAULT_IDENTITY_PLAYER_COUNT: int = DEFAULT_NEXT_MATCH_PLAYER_COUNT

## 机缘大乱斗默认人数；继承身份模式的2至10人配置并默认使用8人。
const DEFAULT_OPPORTUNITY_BRAWL_PLAYER_COUNT: int = DEFAULT_NEXT_MATCH_PLAYER_COUNT

## 过关斩将默认人数；模式固定为一名玩家和一名敌方AI，因此恒为2人。
const DEFAULT_CONQUEST_PLAYER_COUNT: int = 2

## 当前卡牌名称模式；默认使用《崩铁杀》自定义牌名，可在运行时安全切换为原版三国杀牌名。
var card_name_mode: NameMode = NameMode.CUSTOM

## 当前 AI 每次行动或选择响应前的等待秒数；默认0.30秒，运行时可通过局内菜单动态修改。
## 当前默认补充：默认0.10秒必须是0.10至1.00秒、步长0.50秒约束下的合法值。
var ai_response_delay_seconds: float = 0.10

## 当前相邻阶段与自动响应之间的最小等待秒数；默认0.30秒，运行时可通过局内菜单动态修改。
## 当前默认补充：默认0.10秒必须是0.10至1.00秒、步长0.50秒约束下的合法值。
var game_speed_interval_seconds: float = 0.10

## 当前 UI 风格标识；默认使用黑白太空风格，运行时可在局内设置中即时切换且不修改对局规则。
var ui_style_id: String = UIStyleRegistry.DEFAULT_STYLE_ID

## 是否根据公开用牌行为自动标记其他角色身份；默认开启，可在战斗菜单即时关闭且不需要重新开局。
var auto_identity_marking_enabled: bool = true

## 当前联机玩家名称；默认“玩家”，在创建或加入局域网房间时作为不可编辑显示名提交。
var online_player_name: String = DEFAULT_ONLINE_PLAYER_NAME

## 当前联机形象对应的稳定武将 ID；空值表示尚未选择，资料面板或网络网关会回退到首个可用武将。
var online_avatar_character_id: String = ""

## 当前下一局人数；默认8人，仅影响之后创建或重开的对局，不修改正在运行的规则状态。
var next_match_player_count: int = DEFAULT_NEXT_MATCH_PLAYER_COUNT

## 当前下一局模式稳定 ID；默认 identity，仅影响之后创建或重开的对局。
var next_match_mode: String = DEFAULT_NEXT_MATCH_MODE

## 身份模式独立保存的下一局人数；切换回身份模式时恢复，不与斗地主人数互相覆盖。
var next_match_player_count_identity: int = DEFAULT_IDENTITY_PLAYER_COUNT

## 斗地主模式独立保存的下一局人数；仅 3 或 5，切换回斗地主时恢复。
var next_match_player_count_doudizhu: int = DEFAULT_DOUDIZHU_PLAYER_COUNT

## 2v2 模式独立保存的下一局人数；固定 4，切换回 2v2 时恢复。
var next_match_player_count_team2v2: int = DEFAULT_TEAM2V2_PLAYER_COUNT

## 1v1车轮战独立保存的下一局人数；固定2人。
var next_match_player_count_wheel_duel: int = DEFAULT_WHEEL_DUEL_PLAYER_COUNT

## 机缘大乱斗独立保存的下一局人数；范围2至10，切换模式时不覆盖身份模式人数。
var next_match_player_count_opportunity_brawl: int = DEFAULT_OPPORTUNITY_BRAWL_PLAYER_COUNT

## 过关斩将独立保存的下一局人数；固定2人，字段保留以与其他模式的持久化结构一致。
var next_match_player_count_conquest: int = DEFAULT_CONQUEST_PLAYER_COUNT

## 下一局1v1车轮战明置候选数量；默认6，运行时设置范围3至20。
var wheel_duel_face_up_candidate_count: int = DEFAULT_WHEEL_DUEL_FACE_UP_CANDIDATE_COUNT

## 下一局1v1车轮战暗置候选数量；默认4，运行时设置范围3至20。
var wheel_duel_face_down_candidate_count: int = DEFAULT_WHEEL_DUEL_FACE_DOWN_CANDIDATE_COUNT


## 是否允许玩家在选将时打开全部武将并自选座次与身份；默认关闭，仅在下一局初始化时读取。
var custom_character_assignment_enabled: bool = false

## 是否在全员初次选将后由房主调整 AI 武将；默认关闭，仅在下一局开局流程中读取。
var customize_ai_characters_enabled: bool = false

## 每名玩家下一局可使用的手气卡数量；0关闭、1至5与10为有限张数、-1为无限张。
var mulligan_limit: int = 0

## AI 是否根据起始手牌质量自动使用手气卡；默认关闭，且手气卡数量为0时不会产生额外阶段。
var ai_uses_mulligan_enabled: bool = false

## 每名玩家下一局可使用的换将卡数量；默认0表示关闭，只接受设置列表中的离散值。
var character_replacement_count: int = 0

## 过关斩将中每名角色下一局可使用的换将卡数量；默认关闭，与普通模式独立保存且只在该模式创建时读取。
var conquest_character_replacement_count: int = DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT

## 每名玩家下一局获得的普通随机选将牌数；默认5张，领袖技武将不计入该数值。
var character_candidate_count: int = DEFAULT_CHARACTER_CANDIDATE_COUNT

## 过关斩将中每名角色下一局获得的随机选将牌数；默认12张，与普通模式独立保存且只在该模式创建时读取。
var conquest_character_candidate_count: int = DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT

## 下一局过关斩将难度；默认难度五，仅在创建对局时锁定到 match_options 与关卡状态。
var conquest_difficulty: int = DEFAULT_CONQUEST_DIFFICULTY

## 下一局离线对局是否由本机控制全部角色；默认关闭，联机房主与客户端均忽略该值。
var control_all_characters_enabled: bool = false

## 当前实际读写的设置文件路径；默认使用用户目录，测试可在节点进入场景树前替换为独立临时路径。
var _settings_file_path: String = SETTINGS_FILE_PATH

## 设置合并保存计时器；进入场景树后创建，单次触发并忽略场景树暂停，保证菜单调整期间能够正常落盘。
var _settings_save_timer: Timer

## 当前是否存在尚未写入磁盘的设置变化；应用进入后台或节点退出时会强制刷新。
var _has_pending_settings_save: bool = false

## 最近一次设置文件保存结果；OK表示写入成功，失败值仅供诊断，不阻止内存设置继续生效。
var last_save_error: Error = OK

## 卡牌名称变化是否已排入空闲帧；用于合并同一帧内的重复选择并避免在GUI输入回调中同步重建牌面。
var _card_name_mode_signal_pending: bool = false

## UI风格变化是否已排入空闲帧；用于避免在下拉框输入回调中同步重建全部主题样式资源。
var _ui_style_signal_pending: bool = false


## 自动加载节点进入场景树时恢复已保存配置；恢复阶段不发变更信号，后续界面会直接读取最终值完成首次绘制。
func _ready() -> void:
	_load_saved_settings()
	_settings_save_timer = Timer.new()
	_settings_save_timer.name = "SettingsSaveTimer"
	_settings_save_timer.one_shot = true
	_settings_save_timer.wait_time = SETTINGS_SAVE_DEBOUNCE_SECONDS
	_settings_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_save_timer.timeout.connect(flush_pending_settings)
	add_child(_settings_save_timer)


## 应用进入后台时立即保存待处理设置；移动系统可能随后终止进程，不能继续等待合并计时器。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		flush_pending_settings()


## 节点退出前立即保存待处理设置；测试实例释放与正常关闭都复用同一安全出口。
func _exit_tree() -> void:
	flush_pending_settings()


## 设置全局卡牌名称模式，并通知所有已连接的界面刷新显示文本。
func set_card_name_mode(mode: NameMode) -> void:
	# 规范化后的名称模式；存档可能来自旧版本或手工编辑，未知值统一回退自定义名称。
	var normalized_mode: NameMode = _normalize_card_name_mode(mode)
	if card_name_mode == normalized_mode:
		return
	card_name_mode = normalized_mode
	_queue_settings_save()
	_queue_card_name_mode_changed_signal()


## 在两套卡牌名称之间切换，适合直接绑定设置按钮。
func toggle_card_name_mode() -> void:
	if card_name_mode == NameMode.CUSTOM:
		set_card_name_mode(NameMode.ORIGINAL)
	else:
		set_card_name_mode(NameMode.CUSTOM)


## 设置 AI 每次行动与响应前的统一等待时间；范围外输入会限制到全局设置允许的安全区间。
func set_ai_response_delay_seconds(delay_seconds: float) -> void:
	# 限制后的延迟；统一按滑条步长取整，保证界面显示值与调度实际使用值一致。
	var clamped_delay_seconds: float = _normalize_timed_setting_seconds(delay_seconds, MIN_AI_RESPONSE_DELAY_SECONDS, MAX_AI_RESPONSE_DELAY_SECONDS, AI_RESPONSE_DELAY_STEP_SECONDS)
	if is_equal_approx(ai_response_delay_seconds, clamped_delay_seconds):
		return
	ai_response_delay_seconds = clamped_delay_seconds
	_queue_settings_save()
	ai_response_delay_changed.emit(ai_response_delay_seconds)


## 设置相邻阶段和自动响应之间的最小等待时间；范围外输入按菜单允许值限制并对齐到固定步长。
func set_game_speed_interval_seconds(interval_seconds: float) -> void:
	# 限制后的流程间隔；统一按滑条步长取整，保证标签显示值与实际调度值一致。
	var clamped_interval_seconds: float = _normalize_timed_setting_seconds(interval_seconds, MIN_GAME_SPEED_INTERVAL_SECONDS, MAX_GAME_SPEED_INTERVAL_SECONDS, GAME_SPEED_INTERVAL_STEP_SECONDS)
	if is_equal_approx(game_speed_interval_seconds, clamped_interval_seconds):
		return
	game_speed_interval_seconds = clamped_interval_seconds
	_queue_settings_save()
	game_speed_changed.emit(game_speed_interval_seconds)


## 将任意秒数限制到设置范围并相对最小值按步长对齐；最大值不是步长整倍数时仍保留为可选上限，避免0.10秒配0.50秒步长被错误吸附为0.00秒。
func _normalize_timed_setting_seconds(value_seconds: float, minimum_seconds: float, maximum_seconds: float, step_seconds: float) -> float:
	# 已限制到合法闭区间的秒数；先处理上限可保证1.00秒作为范围终点始终可保存和显示。
	var clamped_seconds: float = clampf(value_seconds, minimum_seconds, maximum_seconds)
	if is_equal_approx(clamped_seconds, maximum_seconds):
		return maximum_seconds
	# 相对最小值的步进距离；减去最小值后再取整，使0.10秒成为首个合法档位而非被全局零点取整。
	var snapped_offset_seconds: float = snappedf(clamped_seconds - minimum_seconds, step_seconds)
	return clampf(minimum_seconds + snapped_offset_seconds, minimum_seconds, maximum_seconds)


## 设置全局 UI 风格；未知标识自动回退默认风格，并通知已连接的界面组件即时重绘。
func set_ui_style(style_id: String) -> void:
	# 已注册的风格标识；设置层只保存稳定 ID，不持有任何颜色字典或场景节点引用。
	var normalized_style_id: String = UIStyleRegistry.normalize_style_id(style_id)
	if ui_style_id == normalized_style_id:
		return
	ui_style_id = normalized_style_id
	_queue_settings_save()
	_queue_ui_style_changed_signal()


## 设置自动身份标记开关；变化只通知本地界面重新读取共享身份模型，不改变模型观察记录或规则状态。
func set_auto_identity_marking_enabled(enabled: bool) -> void:
	if auto_identity_marking_enabled == enabled:
		return
	auto_identity_marking_enabled = enabled
	_queue_settings_save()
	auto_identity_marking_changed.emit(auto_identity_marking_enabled)


## 设置联机玩家名称；首尾空白会被移除，空值回退默认名称，超长文本限制为协议允许的20个字符。
func set_online_player_name(player_name: String) -> void:
	# 标准化后的玩家名称；统一入口保证资料面板与局域网提交使用完全相同的文本。
	var normalized_player_name: String = normalize_online_player_name(player_name)
	if online_player_name == normalized_player_name:
		return
	online_player_name = normalized_player_name
	_queue_settings_save()
	online_player_name_changed.emit(online_player_name)


## 设置联机形象的稳定武将 ID；空值允许表示尚未完成选择，合法性由消费武将数据库的资料面板校验。
func set_online_avatar_character_id(character_id: String) -> void:
	# 去除首尾空白后的武将 ID；稳定 ID 本身不应包含空格，清理可避免配置比较出现伪差异。
	var normalized_character_id: String = character_id.strip_edges()
	if online_avatar_character_id == normalized_character_id:
		return
	online_avatar_character_id = normalized_character_id
	_queue_settings_save()
	online_avatar_character_changed.emit(online_avatar_character_id)


## 设置下一局人数并同步所有菜单；范围外输入自动限制为标准身份局支持的2至10人。
func set_next_match_player_count(player_count: int) -> void:
	# 按当前下一局模式规范化人数；身份局 2–10，斗地主仅 3/5，并同步写入该模式独立存档槽。
	var normalized_player_count: int = normalize_player_count_for_mode(next_match_mode, player_count)
	# 当前菜单人数是否变化；仅此项决定是否需要向正在显示的输入框广播。
	var current_count_changed: bool = next_match_player_count != normalized_player_count
	# 当前模式独立人数槽是否变化；即使菜单显示数字相同，也必须写盘避免切换模式后丢失设置。
	var stored_count_changed: bool = get_stored_player_count_for_mode(next_match_mode) != normalized_player_count
	if not current_count_changed and not stored_count_changed:
		return
	if current_count_changed:
		next_match_player_count = normalized_player_count
	_store_player_count_for_mode(next_match_mode, normalized_player_count)
	_queue_settings_save()
	if current_count_changed:
		next_match_player_count_changed.emit(next_match_player_count)


## 规范化下一局模式 ID；未知值回退到标准身份局。
func normalize_match_mode(mode_id: String) -> String:
	if mode_id == MATCH_MODE_DOUDIZHU:
		return MATCH_MODE_DOUDIZHU
	if mode_id == MATCH_MODE_TEAM2V2:
		return MATCH_MODE_TEAM2V2
	if mode_id == MATCH_MODE_WHEEL_DUEL:
		return MATCH_MODE_WHEEL_DUEL
	if mode_id == MATCH_MODE_OPPORTUNITY_BRAWL:
		return MATCH_MODE_OPPORTUNITY_BRAWL
	if mode_id == MATCH_MODE_CONQUEST:
		return MATCH_MODE_CONQUEST
	return MATCH_MODE_IDENTITY


## 将人数限制到指定模式合法范围；身份局 2–10，斗地主仅 3 或 5，2v2 固定 4。
func normalize_player_count_for_mode(mode_id: String, player_count: int) -> int:
	var mode: String = normalize_match_mode(mode_id)
	if mode == MATCH_MODE_DOUDIZHU:
		if player_count == 3 or player_count == 5:
			return player_count
		return 3 if player_count < 4 else 5
	if mode == MATCH_MODE_TEAM2V2:
		return DEFAULT_TEAM2V2_PLAYER_COUNT
	if mode == MATCH_MODE_WHEEL_DUEL:
		return DEFAULT_WHEEL_DUEL_PLAYER_COUNT
	if mode == MATCH_MODE_CONQUEST:
		return DEFAULT_CONQUEST_PLAYER_COUNT
	return clampi(player_count, MIN_NEXT_MATCH_PLAYER_COUNT, MAX_NEXT_MATCH_PLAYER_COUNT)


## 读取指定模式独立保存的下一局人数；未知模式回退身份局默认。
func get_stored_player_count_for_mode(mode_id: String) -> int:
	var mode: String = normalize_match_mode(mode_id)
	if mode == MATCH_MODE_DOUDIZHU:
		return next_match_player_count_doudizhu
	if mode == MATCH_MODE_TEAM2V2:
		return next_match_player_count_team2v2
	if mode == MATCH_MODE_WHEEL_DUEL:
		return next_match_player_count_wheel_duel
	if mode == MATCH_MODE_OPPORTUNITY_BRAWL:
		return next_match_player_count_opportunity_brawl
	if mode == MATCH_MODE_CONQUEST:
		return next_match_player_count_conquest
	return next_match_player_count_identity


## 将人数写入指定模式的独立存档槽；不广播信号，由调用方决定是否同步全局 next_match_player_count。
func _store_player_count_for_mode(mode_id: String, player_count: int) -> void:
	var mode: String = normalize_match_mode(mode_id)
	var normalized_count: int = normalize_player_count_for_mode(mode, player_count)
	if mode == MATCH_MODE_DOUDIZHU:
		next_match_player_count_doudizhu = normalized_count
	elif mode == MATCH_MODE_TEAM2V2:
		next_match_player_count_team2v2 = normalized_count
	elif mode == MATCH_MODE_WHEEL_DUEL:
		next_match_player_count_wheel_duel = normalized_count
	elif mode == MATCH_MODE_OPPORTUNITY_BRAWL:
		next_match_player_count_opportunity_brawl = normalized_count
	elif mode == MATCH_MODE_CONQUEST:
		next_match_player_count_conquest = normalized_count
	else:
		next_match_player_count_identity = normalized_count


## 设置下一局模式并同步主菜单；未知模式回退身份局，不修改进行中的对局。
func set_next_match_mode(mode_id: String) -> void:
	# 规范化模式后切换；同时加载该模式独立保存的人数，避免身份局与斗地主共用同一数字造成非法人数。
	var normalized_mode: String = normalize_match_mode(mode_id)
	if next_match_mode == normalized_mode:
		return
	next_match_mode = normalized_mode
	# 模式本身也是持久化字段；即使新旧模式恰好使用相同人数，也必须安排一次写盘。
	_queue_settings_save()
	# 切换模式时恢复该模式自己的人数，并广播人数变化让各设置入口同步 SpinBox。
	var mode_player_count: int = get_stored_player_count_for_mode(next_match_mode)
	mode_player_count = normalize_player_count_for_mode(next_match_mode, mode_player_count)
	if next_match_player_count != mode_player_count:
		next_match_player_count = mode_player_count
		next_match_player_count_changed.emit(next_match_player_count)
	next_match_mode_changed.emit(next_match_mode)


## 设置下一局是否开放全部武将、座次与身份自选；当前已经创建的玩家与身份不会被修改。
func set_custom_character_assignment_enabled(enabled: bool) -> void:
	if custom_character_assignment_enabled == enabled:
		return
	custom_character_assignment_enabled = enabled
	_queue_settings_save()
	custom_character_assignment_changed.emit(custom_character_assignment_enabled)


## 设置下一局是否允许房主在初次选将后调整全部 AI 武将。
func set_customize_ai_characters_enabled(enabled: bool) -> void:
	if customize_ai_characters_enabled == enabled:
		return
	customize_ai_characters_enabled = enabled
	_queue_settings_save()
	customize_ai_characters_changed.emit(customize_ai_characters_enabled)


## 设置下一局手气卡数量；只接受关闭、一至五张、十张与无限张，其他值回退关闭。
func set_mulligan_limit(limit: int) -> void:
	# 标准化后的手气卡张数；仅允许界面公开的离散档位，防止存档或外部调用产生不可见数值。
	var normalized_limit: int = limit if [0, 1, 2, 3, 4, 5, 10, -1].has(limit) else 0
	if mulligan_limit == normalized_limit:
		return
	mulligan_limit = normalized_limit
	_queue_settings_save()
	mulligan_limit_changed.emit(mulligan_limit)


## 设置 AI 是否使用手气卡；开关不自动改变玩家手气卡数量配置。
func set_ai_uses_mulligan_enabled(enabled: bool) -> void:
	if ai_uses_mulligan_enabled == enabled:
		return
	ai_uses_mulligan_enabled = enabled
	_queue_settings_save()
	ai_uses_mulligan_changed.emit(ai_uses_mulligan_enabled)


## 设置下一局每名玩家的换将卡数量；未知离散值统一回退关闭，避免存档或外部调用产生隐藏规则档位。
func set_character_replacement_count(count: int) -> void:
	# 标准化后的换将卡数量；仅允许菜单公开的六个稳定值。
	var normalized_count: int = count if [0, 3, 5, 8, 10, 20].has(count) else 0
	if character_replacement_count == normalized_count:
		return
	character_replacement_count = normalized_count
	_queue_settings_save()
	character_replacement_count_changed.emit(character_replacement_count)


## 设置下一局过关斩将每名角色的换将卡数量；未知离散值统一回退关闭，不会修改普通模式的换将设置。
func set_conquest_character_replacement_count(count: int) -> void:
	# 标准化后的过关斩将换将卡数量；与普通模式共享公开档位，但写入独立持久化字段。
	var normalized_count: int = count if [0, 3, 5, 8, 10, 20].has(count) else DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT
	if conquest_character_replacement_count == normalized_count:
		return
	conquest_character_replacement_count = normalized_count
	_queue_settings_save()
	conquest_character_replacement_count_changed.emit(conquest_character_replacement_count)


## 返回指定模式应读取的换将卡数量；只有过关斩将使用专属设置，其余模式保留普通换将配置。
func get_character_replacement_count_for_mode(mode_id: String) -> int:
	# 规范化后的模式ID；未知模式按身份局处理，避免外部调用读取到不稳定配置。
	var normalized_mode: String = normalize_match_mode(mode_id)
	return conquest_character_replacement_count if normalized_mode == MATCH_MODE_CONQUEST else character_replacement_count


## 按指定模式写入换将卡数量；菜单只调用该接口，不应自行判断或修改两个持久化字段。
func set_character_replacement_count_for_mode(mode_id: String, count: int) -> void:
	# 规范化后的模式ID；与读取接口使用同一规则，确保主菜单和局内菜单不会写入不同设置槽。
	var normalized_mode: String = normalize_match_mode(mode_id)
	if normalized_mode == MATCH_MODE_CONQUEST:
		set_conquest_character_replacement_count(count)
		return
	set_character_replacement_count(count)


## 设置下一局普通随机选将牌数；范围外输入限制到1至20，当前已经建立的候选不会中途改变。
func set_character_candidate_count(count: int) -> void:
	# 标准化后的随机候选数量；菜单、存档和控制器统一使用同一范围。
	var normalized_count: int = clampi(count, MIN_CHARACTER_CANDIDATE_COUNT, MAX_CHARACTER_CANDIDATE_COUNT)
	if character_candidate_count == normalized_count:
		return
	character_candidate_count = normalized_count
	_queue_settings_save()
	character_candidate_count_changed.emit(character_candidate_count)


## 设置下一局过关斩将随机选将牌数；范围外输入限制到1至20，不会修改普通模式的候选数量。
func set_conquest_character_candidate_count(count: int) -> void:
	# 标准化后的过关斩将候选数量；与普通候选共用一至二十张的下拉范围，但保存到独立字段。
	var normalized_count: int = clampi(count, MIN_CHARACTER_CANDIDATE_COUNT, MAX_CHARACTER_CANDIDATE_COUNT)
	if conquest_character_candidate_count == normalized_count:
		return
	conquest_character_candidate_count = normalized_count
	_queue_settings_save()
	conquest_character_candidate_count_changed.emit(conquest_character_candidate_count)


## 设置下一局过关斩将难度；范围外输入限制到一至五，不会修改已经开始的关卡、机缘或复活次数。
func set_conquest_difficulty(difficulty: int) -> void:
	# 标准化后的难度；菜单、存档与对局创建统一使用一至五的整数协议。
	var normalized_difficulty: int = clampi(difficulty, MIN_CONQUEST_DIFFICULTY, MAX_CONQUEST_DIFFICULTY)
	if conquest_difficulty == normalized_difficulty:
		return
	conquest_difficulty = normalized_difficulty
	_queue_settings_save()
	conquest_difficulty_changed.emit(conquest_difficulty)


## 返回指定模式应读取的随机选将牌数；只有过关斩将使用专属设置，其余模式保留普通候选配置。
func get_character_candidate_count_for_mode(mode_id: String) -> int:
	# 规范化后的模式ID；未知模式按身份局处理，避免外部调用读取到不稳定配置。
	var normalized_mode: String = normalize_match_mode(mode_id)
	return conquest_character_candidate_count if normalized_mode == MATCH_MODE_CONQUEST else character_candidate_count


## 按指定模式写入随机选将牌数；菜单只调用该接口，不应自行判断或修改两个持久化字段。
func set_character_candidate_count_for_mode(mode_id: String, count: int) -> void:
	# 规范化后的模式ID；与读取接口使用同一规则，确保主菜单和局内菜单不会写入不同设置槽。
	var normalized_mode: String = normalize_match_mode(mode_id)
	if normalized_mode == MATCH_MODE_CONQUEST:
		set_conquest_character_candidate_count(count)
		return
	set_character_candidate_count(count)


## 设置下一局离线对局是否控制全部角色；当前已创建对局不会中途改变角色控制权。
func set_control_all_characters_enabled(enabled: bool) -> void:
	if control_all_characters_enabled == enabled:
		return
	control_all_characters_enabled = enabled
	_queue_settings_save()
	control_all_characters_changed.emit(control_all_characters_enabled)


## 设置下一局1v1车轮战明置候选数量；范围外输入限制到3至20，并要求调用方在开局前保证明暗合计不少于10。
func set_wheel_duel_face_up_candidate_count(count: int) -> void:
	# 标准化后的明置候选数量；默认6，修改只影响之后创建的新车轮战对局。
	var normalized_count: int = clampi(count, MIN_WHEEL_DUEL_CANDIDATE_COUNT, MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	if wheel_duel_face_up_candidate_count == normalized_count:
		return
	wheel_duel_face_up_candidate_count = normalized_count
	_queue_settings_save()
	wheel_duel_face_up_candidate_count_changed.emit(wheel_duel_face_up_candidate_count)


## 设置下一局1v1车轮战暗置候选数量；范围外输入限制到3至20，并要求调用方在开局前保证明暗合计不少于10。
func set_wheel_duel_face_down_candidate_count(count: int) -> void:
	# 标准化后的暗置候选数量；默认4，修改只影响之后创建的新车轮战对局。
	var normalized_count: int = clampi(count, MIN_WHEEL_DUEL_CANDIDATE_COUNT, MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	if wheel_duel_face_down_candidate_count == normalized_count:
		return
	wheel_duel_face_down_candidate_count = normalized_count
	_queue_settings_save()
	wheel_duel_face_down_candidate_count_changed.emit(wheel_duel_face_down_candidate_count)


## 返回符合联机协议的玩家名称；该纯函数可供设置界面预览与未来资料持久化复用。
func normalize_online_player_name(player_name: String) -> String:
	# 去除首尾空白后的名称；内部空格保留，允许玩家使用自然昵称。
	var normalized_player_name: String = player_name.strip_edges()
	if normalized_player_name.is_empty():
		normalized_player_name = DEFAULT_ONLINE_PLAYER_NAME
	if normalized_player_name.length() > MAX_ONLINE_PLAYER_NAME_LENGTH:
		normalized_player_name = normalized_player_name.left(MAX_ONLINE_PLAYER_NAME_LENGTH)
	return normalized_player_name


## 返回当前设置文件路径；诊断与独立持久化测试可读取该路径，但普通界面不需要接触文件系统。
func get_settings_file_path() -> String:
	return _settings_file_path


## 从本地配置文件恢复所有客户端偏好；缺失、损坏或字段缺失时保留脚本内默认值并允许后续保存覆盖。
func _load_saved_settings() -> void:
	# 当前设置文件读取器；只在内存中解析，不会在读取失败时创建空文件或修改玩家数据。
	var settings_file: ConfigFile = ConfigFile.new()
	# 配置文件读取结果；首次启动的文件不存在属于正常情况，继续使用脚本默认值。
	var load_error: Error = settings_file.load(_settings_file_path)
	if load_error != OK:
		return
	# 已保存的格式版本；当前版本字段兼容时直接读取，未来版本可在此处按版本执行迁移。
	var stored_schema_version: int = int(settings_file.get_value(SETTINGS_METADATA_SECTION, "schema_version", SETTINGS_SCHEMA_VERSION))
	if stored_schema_version < 1:
		return
	card_name_mode = _normalize_card_name_mode(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "card_name_mode", card_name_mode))
	ai_response_delay_seconds = _normalize_timed_setting_seconds(float(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "ai_response_delay_seconds", ai_response_delay_seconds)), MIN_AI_RESPONSE_DELAY_SECONDS, MAX_AI_RESPONSE_DELAY_SECONDS, AI_RESPONSE_DELAY_STEP_SECONDS)
	game_speed_interval_seconds = _normalize_timed_setting_seconds(float(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "game_speed_interval_seconds", game_speed_interval_seconds)), MIN_GAME_SPEED_INTERVAL_SECONDS, MAX_GAME_SPEED_INTERVAL_SECONDS, GAME_SPEED_INTERVAL_STEP_SECONDS)
	ui_style_id = UIStyleRegistry.normalize_style_id(str(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "ui_style_id", ui_style_id)))
	auto_identity_marking_enabled = bool(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "auto_identity_marking_enabled", auto_identity_marking_enabled))
	next_match_mode = normalize_match_mode(str(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_mode", next_match_mode)))
	# 分模式人数：优先读独立字段；旧存档仅有单一 next_match_player_count 时按当前模式回填对应槽位。
	var stored_identity_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_identity", -1))
	var stored_doudizhu_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_doudizhu", -1))
	var stored_team2v2_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_team2v2", -1))
	# 1v1车轮战独立人数存档；当前固定2人，字段保留以维持分模式设置结构一致。
	var stored_wheel_duel_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_wheel_duel", -1))
	# 机缘大乱斗独立人数存档；范围与身份模式一致，但保持单独设置槽位。
	var stored_opportunity_brawl_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_opportunity_brawl", -1))
	# 过关斩将独立人数存档；固定2人，旧存档缺失时回退模式默认值。
	var stored_conquest_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_conquest", -1))
	var legacy_player_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count", next_match_player_count))
	if stored_identity_count < 0:
		stored_identity_count = legacy_player_count if normalize_match_mode(next_match_mode) == MATCH_MODE_IDENTITY else DEFAULT_IDENTITY_PLAYER_COUNT
	if stored_doudizhu_count < 0:
		stored_doudizhu_count = legacy_player_count if normalize_match_mode(next_match_mode) == MATCH_MODE_DOUDIZHU else DEFAULT_DOUDIZHU_PLAYER_COUNT
	if stored_team2v2_count < 0:
		stored_team2v2_count = legacy_player_count if normalize_match_mode(next_match_mode) == MATCH_MODE_TEAM2V2 else DEFAULT_TEAM2V2_PLAYER_COUNT
	if stored_wheel_duel_count < 0:
		stored_wheel_duel_count = legacy_player_count if normalize_match_mode(next_match_mode) == MATCH_MODE_WHEEL_DUEL else DEFAULT_WHEEL_DUEL_PLAYER_COUNT
	if stored_opportunity_brawl_count < 0:
		stored_opportunity_brawl_count = legacy_player_count if normalize_match_mode(next_match_mode) == MATCH_MODE_OPPORTUNITY_BRAWL else DEFAULT_OPPORTUNITY_BRAWL_PLAYER_COUNT
	if stored_conquest_count < 0:
		stored_conquest_count = legacy_player_count if normalize_match_mode(next_match_mode) == MATCH_MODE_CONQUEST else DEFAULT_CONQUEST_PLAYER_COUNT
	next_match_player_count_identity = normalize_player_count_for_mode(MATCH_MODE_IDENTITY, stored_identity_count)
	next_match_player_count_doudizhu = normalize_player_count_for_mode(MATCH_MODE_DOUDIZHU, stored_doudizhu_count)
	next_match_player_count_team2v2 = normalize_player_count_for_mode(MATCH_MODE_TEAM2V2, stored_team2v2_count)
	next_match_player_count_wheel_duel = normalize_player_count_for_mode(MATCH_MODE_WHEEL_DUEL, stored_wheel_duel_count)
	next_match_player_count_opportunity_brawl = normalize_player_count_for_mode(MATCH_MODE_OPPORTUNITY_BRAWL, stored_opportunity_brawl_count)
	next_match_player_count_conquest = normalize_player_count_for_mode(MATCH_MODE_CONQUEST, stored_conquest_count)
	next_match_player_count = get_stored_player_count_for_mode(next_match_mode)

	custom_character_assignment_enabled = bool(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "custom_character_assignment_enabled", custom_character_assignment_enabled))
	customize_ai_characters_enabled = bool(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "customize_ai_characters_enabled", customize_ai_characters_enabled))
	# 已保存手气卡张数；旧版一至五张保持兼容，十张与无限张分别保留稳定值。
	var stored_mulligan_limit: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "mulligan_limit", mulligan_limit))
	mulligan_limit = stored_mulligan_limit if [0, 1, 2, 3, 4, 5, 10, -1].has(stored_mulligan_limit) else 0
	ai_uses_mulligan_enabled = bool(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "ai_uses_mulligan_enabled", ai_uses_mulligan_enabled))
	# 已保存换将卡数量；未知值回退关闭，避免旧测试或手工配置绕过离散选项。
	var stored_character_replacement_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "character_replacement_count", character_replacement_count))
	character_replacement_count = stored_character_replacement_count if [0, 3, 5, 8, 10, 20].has(stored_character_replacement_count) else 0
	# 过关斩将独立换将卡数量；旧存档未保存该字段时固定回退关闭，不继承普通模式当前值。
	var stored_conquest_character_replacement_count: int = int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "conquest_character_replacement_count", DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT))
	conquest_character_replacement_count = stored_conquest_character_replacement_count if [0, 3, 5, 8, 10, 20].has(stored_conquest_character_replacement_count) else DEFAULT_CONQUEST_CHARACTER_REPLACEMENT_COUNT
	character_candidate_count = clampi(int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "character_candidate_count", character_candidate_count)), MIN_CHARACTER_CANDIDATE_COUNT, MAX_CHARACTER_CANDIDATE_COUNT)
	# 过关斩将独立随机选将牌数；旧存档未保存该字段时固定回退12张，不继承普通模式当前值。
	conquest_character_candidate_count = clampi(int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "conquest_character_candidate_count", DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT)), MIN_CHARACTER_CANDIDATE_COUNT, MAX_CHARACTER_CANDIDATE_COUNT)
	# 过关斩将难度；旧存档缺少字段时使用难度五，保持新增机制前无玩家开局机缘的对局强度。
	conquest_difficulty = clampi(int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "conquest_difficulty", DEFAULT_CONQUEST_DIFFICULTY)), MIN_CONQUEST_DIFFICULTY, MAX_CONQUEST_DIFFICULTY)
	control_all_characters_enabled = bool(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "control_all_characters_enabled", control_all_characters_enabled))
	wheel_duel_face_up_candidate_count = clampi(int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "wheel_duel_face_up_candidate_count", wheel_duel_face_up_candidate_count)), MIN_WHEEL_DUEL_CANDIDATE_COUNT, MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	wheel_duel_face_down_candidate_count = clampi(int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "wheel_duel_face_down_candidate_count", wheel_duel_face_down_candidate_count)), MIN_WHEEL_DUEL_CANDIDATE_COUNT, MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	online_player_name = normalize_online_player_name(str(settings_file.get_value(ONLINE_SETTINGS_SECTION, "player_name", online_player_name)))
	online_avatar_character_id = str(settings_file.get_value(ONLINE_SETTINGS_SECTION, "avatar_character_id", online_avatar_character_id)).strip_edges()


## 登记一次待保存变化并重启短计时器；连续滑条事件只会在停止操作后执行一次实际文件写入。
func _queue_settings_save() -> void:
	_has_pending_settings_save = true
	if _settings_save_timer == null or not is_instance_valid(_settings_save_timer):
		flush_pending_settings()
		return
	_settings_save_timer.start(SETTINGS_SAVE_DEBOUNCE_SECONDS)


## 立即把全部待处理设置写入磁盘；公开入口供应用生命周期和持久化测试安全强制落盘。
func flush_pending_settings() -> void:
	if not _has_pending_settings_save:
		return
	_has_pending_settings_save = false
	if _settings_save_timer != null and is_instance_valid(_settings_save_timer):
		_settings_save_timer.stop()
	_save_settings()


## 把卡牌名称变化安排到当前GUI输入结束后的空闲帧；重复请求只保留一次最终状态广播。
func _queue_card_name_mode_changed_signal() -> void:
	if _card_name_mode_signal_pending:
		return
	_card_name_mode_signal_pending = true
	call_deferred("_emit_card_name_mode_changed_signal")


## 广播最终卡牌名称模式；界面可安全重绘牌面，不会继续占用原下拉框输入调用栈。
func _emit_card_name_mode_changed_signal() -> void:
	_card_name_mode_signal_pending = false
	card_name_mode_changed.emit(card_name_mode)


## 把UI风格变化安排到当前GUI输入结束后的空闲帧；同一帧重复选择只重建一次主题资源。
func _queue_ui_style_changed_signal() -> void:
	if _ui_style_signal_pending:
		return
	_ui_style_signal_pending = true
	call_deferred("_emit_ui_style_changed_signal")


## 广播最终UI风格；所有组件的样式对象重建在空闲帧执行，避免移动端输入事件表现为卡死。
func _emit_ui_style_changed_signal() -> void:
	_ui_style_signal_pending = false
	ui_style_changed.emit(ui_style_id)


## 将当前客户端偏好写入本地配置文件；写入失败不影响已生效的内存设置或当前网络与对局状态。
func _save_settings() -> void:
	# 当前设置文件写入器；每次完整写入全部字段，避免增量更新产生缺失字段或跨版本半成品。
	var settings_file: ConfigFile = ConfigFile.new()
	settings_file.set_value(SETTINGS_METADATA_SECTION, "schema_version", SETTINGS_SCHEMA_VERSION)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "card_name_mode", int(card_name_mode))
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "ai_response_delay_seconds", ai_response_delay_seconds)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "game_speed_interval_seconds", game_speed_interval_seconds)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "ui_style_id", ui_style_id)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "auto_identity_marking_enabled", auto_identity_marking_enabled)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count", next_match_player_count)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_identity", next_match_player_count_identity)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_doudizhu", next_match_player_count_doudizhu)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_team2v2", next_match_player_count_team2v2)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_wheel_duel", next_match_player_count_wheel_duel)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_opportunity_brawl", next_match_player_count_opportunity_brawl)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count_conquest", next_match_player_count_conquest)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "next_match_mode", next_match_mode)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "custom_character_assignment_enabled", custom_character_assignment_enabled)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "customize_ai_characters_enabled", customize_ai_characters_enabled)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "mulligan_limit", mulligan_limit)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "ai_uses_mulligan_enabled", ai_uses_mulligan_enabled)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "character_replacement_count", character_replacement_count)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "conquest_character_replacement_count", conquest_character_replacement_count)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "character_candidate_count", character_candidate_count)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "conquest_character_candidate_count", conquest_character_candidate_count)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "conquest_difficulty", conquest_difficulty)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "control_all_characters_enabled", control_all_characters_enabled)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "wheel_duel_face_up_candidate_count", wheel_duel_face_up_candidate_count)
	settings_file.set_value(GAMEPLAY_SETTINGS_SECTION, "wheel_duel_face_down_candidate_count", wheel_duel_face_down_candidate_count)
	settings_file.set_value(ONLINE_SETTINGS_SECTION, "player_name", online_player_name)
	settings_file.set_value(ONLINE_SETTINGS_SECTION, "avatar_character_id", online_avatar_character_id)
	last_save_error = settings_file.save(_settings_file_path)


## 将任意存档或调用方提供的名称模式限制到两个已支持的稳定枚举值。
func _normalize_card_name_mode(mode: Variant) -> NameMode:
	return NameMode.ORIGINAL if int(mode) == int(NameMode.ORIGINAL) else NameMode.CUSTOM


## 根据当前全局模式，从卡牌配置中返回唯一的前端显示名称。
func resolve_card_name(card_definition: Dictionary) -> String:
	if card_name_mode == NameMode.ORIGINAL:
		return str(card_definition.get("original_name", card_definition.get("id", "未知牌")))
	return str(card_definition.get("custom_name", card_definition.get("original_name", "未知牌")))


## 返回用于牌面与装备栏的显示名称；武器会在名称后附加固定攻击范围，其他牌保持基础名称不变。
func resolve_card_display_name(card_definition: Dictionary) -> String:
	# 基础显示名；名称模式仍由唯一 resolve_card_name() 入口决定。
	var display_name: String = resolve_card_name(card_definition)
	if str(card_definition.get("type", "")) != "equipment" or str(card_definition.get("subtype", "")) != "weapon":
		return display_name
	# 武器攻击范围；非正或缺失配置使用基础范围1，避免界面出现无意义的0。
	var attack_range: int = maxi(int(card_definition.get("attack_range", 1)), 1)
	return "%s %d" % [display_name, attack_range]
