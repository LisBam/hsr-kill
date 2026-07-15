extends Node

## 全局显示与对局配置入口。该节点只保存跨场景配置，不持有任何具体对局状态。

signal card_name_mode_changed(mode: NameMode)

## AI 响应等待时长变化信号；对局控制器订阅后同步下一次 AI 行动与选牌响应的等待时间。
signal ai_response_delay_changed(delay_seconds: float)

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

## 当前卡牌名称模式；默认使用原版三国杀牌名，可在运行时安全切换为《崩铁杀》自定义牌名。
var card_name_mode: NameMode = NameMode.ORIGINAL

## 当前 AI 每次行动或选择响应前的等待秒数；默认0.30秒，运行时可通过局内菜单动态修改。
var ai_response_delay_seconds: float = 0.30


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


## 根据当前全局模式，从卡牌配置中返回唯一的前端显示名称。
func resolve_card_name(card_definition: Dictionary) -> String:
	if card_name_mode == NameMode.ORIGINAL:
		return str(card_definition.get("original_name", card_definition.get("id", "未知牌")))
	return str(card_definition.get("custom_name", card_definition.get("original_name", "未知牌")))
