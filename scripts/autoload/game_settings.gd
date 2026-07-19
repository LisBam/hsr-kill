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

## AI 响应等待时间的最小值；默认0.05秒，在保留可见异步边界的同时支持快速对局。
const MIN_AI_RESPONSE_DELAY_SECONDS: float = 0.05

## AI 响应等待时间的最大值；默认1秒，覆盖快速对局到观察型对局的常用节奏而不造成过长停顿。
const MAX_AI_RESPONSE_DELAY_SECONDS: float = 1.0

## AI 响应等待时间的调节步长；默认0.05秒，兼顾可感知变化与菜单滑条的调节精度。
const AI_RESPONSE_DELAY_STEP_SECONDS: float = 0.05

## 游戏流程间隔的最小值；默认0.1秒，保证连续阶段与响应之间保留可观察的画面更新边界。
const MIN_GAME_SPEED_INTERVAL_SECONDS: float = 0.1

## 游戏流程间隔的最大值；默认1秒，允许观察结算过程且避免自动流程等待过久。
const MAX_GAME_SPEED_INTERVAL_SECONDS: float = 1.0

## 游戏流程间隔的调节步长；默认0.1秒，与菜单滑条显示精度保持一致。
const GAME_SPEED_INTERVAL_STEP_SECONDS: float = 0.1

## 联机玩家名称允许的最大 Unicode 字符数；20与局域网成员协议上限一致，运行时无需动态修改。
const MAX_ONLINE_PLAYER_NAME_LENGTH: int = 20

## 联机玩家名称为空时使用的默认文本；稳定回退可防止大厅成员列表出现空白行。
const DEFAULT_ONLINE_PLAYER_NAME: String = "玩家"

## 本地设置文件路径；仅保存跨启动保留的客户端偏好，不保存房间密码、ENet 会话或任何权威对局状态。
const SETTINGS_FILE_PATH: String = "user://game_settings.cfg"

## 设置文件格式版本；未来字段结构变化时可据此添加兼容迁移，当前版本从1开始。
const SETTINGS_SCHEMA_VERSION: int = 1

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

## 当前卡牌名称模式；默认使用《崩铁杀》自定义牌名，可在运行时安全切换为原版三国杀牌名。
var card_name_mode: NameMode = NameMode.CUSTOM

## 当前 AI 每次行动或选择响应前的等待秒数；默认0.30秒，运行时可通过局内菜单动态修改。
var ai_response_delay_seconds: float = 0.30

## 当前相邻阶段与自动响应之间的最小等待秒数；默认0.30秒，运行时可通过局内菜单动态修改。
var game_speed_interval_seconds: float = 0.30

## 当前 UI 风格标识；默认使用黑白太空风格，运行时可在局内设置中即时切换且不修改对局规则。
var ui_style_id: String = UIStyleRegistry.DEFAULT_STYLE_ID

## 是否根据公开用牌行为自动标记其他角色身份；默认开启，可在战斗菜单即时关闭且不需要重新开局。
var auto_identity_marking_enabled: bool = true

## 当前联机玩家名称；默认“玩家”，在创建或加入局域网房间时作为不可编辑显示名提交。
var online_player_name: String = DEFAULT_ONLINE_PLAYER_NAME

## 当前联机形象对应的稳定武将 ID；空值表示尚未选择，资料面板或网络网关会回退到首个可用武将。
var online_avatar_character_id: String = ""

## 当前下一局人数；默认8人，仅影响之后创建或重开的身份局，不修改正在运行的规则状态。
var next_match_player_count: int = DEFAULT_NEXT_MATCH_PLAYER_COUNT

## 当前实际读写的设置文件路径；默认使用用户目录，测试可在节点进入场景树前替换为独立临时路径。
var _settings_file_path: String = SETTINGS_FILE_PATH


## 自动加载节点进入场景树时恢复已保存配置；恢复阶段不发变更信号，后续界面会直接读取最终值完成首次绘制。
func _ready() -> void:
	_load_saved_settings()


## 设置全局卡牌名称模式，并通知所有已连接的界面刷新显示文本。
func set_card_name_mode(mode: NameMode) -> void:
	# 规范化后的名称模式；存档可能来自旧版本或手工编辑，未知值统一回退自定义名称。
	var normalized_mode: NameMode = _normalize_card_name_mode(mode)
	if card_name_mode == normalized_mode:
		return
	card_name_mode = normalized_mode
	_save_settings()
	card_name_mode_changed.emit(card_name_mode)


## 在两套卡牌名称之间切换，适合直接绑定设置按钮。
func toggle_card_name_mode() -> void:
	if card_name_mode == NameMode.CUSTOM:
		set_card_name_mode(NameMode.ORIGINAL)
	else:
		set_card_name_mode(NameMode.CUSTOM)


## 设置 AI 每次行动与响应前的统一等待时间；范围外输入会限制到全局设置允许的安全区间。
func set_ai_response_delay_seconds(delay_seconds: float) -> void:
	# 限制后的延迟；统一按滑条步长取整，保证界面显示值与调度实际使用值一致。
	var clamped_delay_seconds: float = snappedf(clampf(delay_seconds, MIN_AI_RESPONSE_DELAY_SECONDS, MAX_AI_RESPONSE_DELAY_SECONDS), AI_RESPONSE_DELAY_STEP_SECONDS)
	if is_equal_approx(ai_response_delay_seconds, clamped_delay_seconds):
		return
	ai_response_delay_seconds = clamped_delay_seconds
	_save_settings()
	ai_response_delay_changed.emit(ai_response_delay_seconds)


## 设置相邻阶段和自动响应之间的最小等待时间；范围外输入按菜单允许值限制并对齐到固定步长。
func set_game_speed_interval_seconds(interval_seconds: float) -> void:
	# 限制后的流程间隔；统一按滑条步长取整，保证标签显示值与实际调度值一致。
	var clamped_interval_seconds: float = snappedf(clampf(interval_seconds, MIN_GAME_SPEED_INTERVAL_SECONDS, MAX_GAME_SPEED_INTERVAL_SECONDS), GAME_SPEED_INTERVAL_STEP_SECONDS)
	if is_equal_approx(game_speed_interval_seconds, clamped_interval_seconds):
		return
	game_speed_interval_seconds = clamped_interval_seconds
	_save_settings()
	game_speed_changed.emit(game_speed_interval_seconds)


## 设置全局 UI 风格；未知标识自动回退默认风格，并通知已连接的界面组件即时重绘。
func set_ui_style(style_id: String) -> void:
	# 已注册的风格标识；设置层只保存稳定 ID，不持有任何颜色字典或场景节点引用。
	var normalized_style_id: String = UIStyleRegistry.normalize_style_id(style_id)
	if ui_style_id == normalized_style_id:
		return
	ui_style_id = normalized_style_id
	_save_settings()
	ui_style_changed.emit(ui_style_id)


## 设置自动身份标记开关；变化只通知本地界面重新读取共享身份模型，不改变模型观察记录或规则状态。
func set_auto_identity_marking_enabled(enabled: bool) -> void:
	if auto_identity_marking_enabled == enabled:
		return
	auto_identity_marking_enabled = enabled
	_save_settings()
	auto_identity_marking_changed.emit(auto_identity_marking_enabled)


## 设置联机玩家名称；首尾空白会被移除，空值回退默认名称，超长文本限制为协议允许的20个字符。
func set_online_player_name(player_name: String) -> void:
	# 标准化后的玩家名称；统一入口保证资料面板与局域网提交使用完全相同的文本。
	var normalized_player_name: String = normalize_online_player_name(player_name)
	if online_player_name == normalized_player_name:
		return
	online_player_name = normalized_player_name
	_save_settings()
	online_player_name_changed.emit(online_player_name)


## 设置联机形象的稳定武将 ID；空值允许表示尚未完成选择，合法性由消费武将数据库的资料面板校验。
func set_online_avatar_character_id(character_id: String) -> void:
	# 去除首尾空白后的武将 ID；稳定 ID 本身不应包含空格，清理可避免配置比较出现伪差异。
	var normalized_character_id: String = character_id.strip_edges()
	if online_avatar_character_id == normalized_character_id:
		return
	online_avatar_character_id = normalized_character_id
	_save_settings()
	online_avatar_character_changed.emit(online_avatar_character_id)


## 设置下一局人数并同步所有菜单；范围外输入自动限制为标准身份局支持的2至10人。
func set_next_match_player_count(player_count: int) -> void:
	# 限制后的人数；只保存下一局配置，当前对局已经创建时不改变其玩家、身份或座次。
	var normalized_player_count: int = clampi(player_count, MIN_NEXT_MATCH_PLAYER_COUNT, MAX_NEXT_MATCH_PLAYER_COUNT)
	if next_match_player_count == normalized_player_count:
		return
	next_match_player_count = normalized_player_count
	_save_settings()
	next_match_player_count_changed.emit(next_match_player_count)


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
	ai_response_delay_seconds = snappedf(clampf(float(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "ai_response_delay_seconds", ai_response_delay_seconds)), MIN_AI_RESPONSE_DELAY_SECONDS, MAX_AI_RESPONSE_DELAY_SECONDS), AI_RESPONSE_DELAY_STEP_SECONDS)
	game_speed_interval_seconds = snappedf(clampf(float(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "game_speed_interval_seconds", game_speed_interval_seconds)), MIN_GAME_SPEED_INTERVAL_SECONDS, MAX_GAME_SPEED_INTERVAL_SECONDS), GAME_SPEED_INTERVAL_STEP_SECONDS)
	ui_style_id = UIStyleRegistry.normalize_style_id(str(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "ui_style_id", ui_style_id)))
	auto_identity_marking_enabled = bool(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "auto_identity_marking_enabled", auto_identity_marking_enabled))
	next_match_player_count = clampi(int(settings_file.get_value(GAMEPLAY_SETTINGS_SECTION, "next_match_player_count", next_match_player_count)), MIN_NEXT_MATCH_PLAYER_COUNT, MAX_NEXT_MATCH_PLAYER_COUNT)
	online_player_name = normalize_online_player_name(str(settings_file.get_value(ONLINE_SETTINGS_SECTION, "player_name", online_player_name)))
	online_avatar_character_id = str(settings_file.get_value(ONLINE_SETTINGS_SECTION, "avatar_character_id", online_avatar_character_id)).strip_edges()


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
	settings_file.set_value(ONLINE_SETTINGS_SECTION, "player_name", online_player_name)
	settings_file.set_value(ONLINE_SETTINGS_SECTION, "avatar_character_id", online_avatar_character_id)
	settings_file.save(_settings_file_path)


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
