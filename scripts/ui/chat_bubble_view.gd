class_name ChatBubbleView
extends Control

## 聊天气泡组件。发言者头顶显示其最新一条聊天正文，停留数秒后自动淡出隐藏。
## 组件只负责气泡外观、文本换行与淡出生命周期；发言者定位、坐标换算与按玩家复用由牌桌负责。
## 组件不读取快照、网络或规则状态，同一实例可被反复用于同一名玩家的多条消息。

## 气泡正文最大宽度像素；超过后自动换行，与武将牌宽度（148.35）接近保持视觉贴合。
@export var maximum_text_width: float = 176.0

## 气泡默认停留秒数；从显示到开始淡出的时间，默认4秒足够阅读一条200字符内的短消息。
@export var hold_seconds: float = 4.0

## 气泡淡出时长秒数；淡出结束后隐藏节点等待下一条消息复用。
@export var fade_seconds: float = 0.25

## 气泡正文字号；12像素在头顶窄气泡中保持可读且不过度遮挡牌面。
@export var font_size: int = 12

## 气泡背景面板；主题变化时按当前风格重绘底色与描边。
var _bubble_panel: PanelContainer = null

## 气泡正文标签；自动换行，文本与主题主要文字色一致。
var _message_label: Label = null

## 当前淡出补间；新消息到达时先终止旧补间，避免上一条的淡出提前隐藏新内容。
var _fade_tween: Tween = null


## 构建气泡节点树；默认隐藏，等待第一条消息。
func _ready() -> void:
	# 离线暂停（日志展开、武将详情）期间气泡仍应正常停留与淡出；气泡不影响任何规则状态。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_panel = PanelContainer.new()
	_bubble_panel.name = "ChatBubblePanel"
	_bubble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble_panel)
	_message_label = Label.new()
	_message_label.name = "ChatBubbleMessage"
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(0.0, 0.0)
	_message_label.add_theme_font_size_override("font_size", font_size)
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_panel.add_child(_message_label)
	refresh_ui_style()


## 显示一条聊天正文并重启停留计时；返回气泡的实际尺寸供牌桌完成头顶居中定位。
func show_message(message: String) -> Vector2:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_message_label.text = message
	# 先按单行测量宽度；短消息使用紧凑气泡，超过上限的长消息固定上限宽度并换行。
	var single_line_width: float = _message_label.get_theme_font("font").get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_message_label.custom_minimum_size = Vector2(minf(single_line_width + 2.0, maximum_text_width), 0.0)
	_bubble_panel.reset_size()
	# 气泡最终尺寸；由面板内容边距与正文换行结果共同决定。
	var bubble_size: Vector2 = _bubble_panel.get_combined_minimum_size()
	_bubble_panel.size = bubble_size
	size = bubble_size
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	visible = true
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_interval(hold_seconds)
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_seconds)
	_fade_tween.tween_callback(hide)
	return bubble_size


## 立即隐藏气泡并终止淡出；新一局开始或发言者座位消失时由牌桌调用。
func dismiss() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	visible = false


## 刷新活动 UI 风格；气泡使用主题金属底与描边，正文使用主要文字色。
func refresh_ui_style() -> void:
	if _bubble_panel == null:
		return
	_bubble_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("accent"), 1, 6))
	_message_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
