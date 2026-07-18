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

## 卡牌名称显示模式；CUSTOM 展示《崩铁杀》名称，ORIGINAL 展示原版三国杀名称。
enum NameMode {
	CUSTOM,
	ORIGINAL,
}

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


## 设置全局卡牌名称模式，并通知所有已连接的界面刷新显示文本。
func set_card_name_mode(mode: NameMode) -> void:
	if card_name_mode == mode:
		return
	card_name_mode = mode
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
	ai_response_delay_changed.emit(ai_response_delay_seconds)


## 设置相邻阶段和自动响应之间的最小等待时间；范围外输入按菜单允许值限制并对齐到固定步长。
func set_game_speed_interval_seconds(interval_seconds: float) -> void:
	# 限制后的流程间隔；统一按滑条步长取整，保证标签显示值与实际调度值一致。
	var clamped_interval_seconds: float = snappedf(clampf(interval_seconds, MIN_GAME_SPEED_INTERVAL_SECONDS, MAX_GAME_SPEED_INTERVAL_SECONDS), GAME_SPEED_INTERVAL_STEP_SECONDS)
	if is_equal_approx(game_speed_interval_seconds, clamped_interval_seconds):
		return
	game_speed_interval_seconds = clamped_interval_seconds
	game_speed_changed.emit(game_speed_interval_seconds)


## 设置全局 UI 风格；未知标识自动回退默认风格，并通知已连接的界面组件即时重绘。
func set_ui_style(style_id: String) -> void:
	# 已注册的风格标识；设置层只保存稳定 ID，不持有任何颜色字典或场景节点引用。
	var normalized_style_id: String = UIStyleRegistry.normalize_style_id(style_id)
	if ui_style_id == normalized_style_id:
		return
	ui_style_id = normalized_style_id
	ui_style_changed.emit(ui_style_id)


## 设置自动身份标记开关；变化只通知本地界面重新读取共享身份模型，不改变模型观察记录或规则状态。
func set_auto_identity_marking_enabled(enabled: bool) -> void:
	if auto_identity_marking_enabled == enabled:
		return
	auto_identity_marking_enabled = enabled
	auto_identity_marking_changed.emit(auto_identity_marking_enabled)


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
