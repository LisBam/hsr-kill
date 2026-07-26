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

## 气泡正文左右内边距像素；默认7为紧凑气泡，正文与描边保持最小可读间隙，不留大片空白。
@export var horizontal_padding: float = 7.0

## 气泡正文上下内边距像素；默认4使单行气泡高度贴合字高，多行时逐行同样紧凑。
@export var vertical_padding: float = 4.0

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
	# 按标签同款换行规则预排版正文；取换行后最宽一行的实际宽度，使短消息与折行消息都不留横向空白。
	var wrapped_text_width: float = _measure_wrapped_text_width(message)
	_message_label.custom_minimum_size = Vector2(minf(wrapped_text_width + 2.0, maximum_text_width), 0.0)
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
## 通用面板样式的内容边距按气泡紧凑内边距收窄，避免小尺寸气泡继承大面板的宽边距形成空白。
func refresh_ui_style() -> void:
	if _bubble_panel == null:
		return
	# 气泡专属面板样式；基于主题工厂生成后收紧内容边距，保持底色与描边随主题联动。
	var bubble_style: StyleBoxFlat = BattleUIStyle.make_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("accent"), 1, 6)
	bubble_style.content_margin_left = horizontal_padding
	bubble_style.content_margin_right = horizontal_padding
	bubble_style.content_margin_top = vertical_padding
	bubble_style.content_margin_bottom = vertical_padding
	_bubble_panel.add_theme_stylebox_override("panel", bubble_style)
	_message_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))


## 按气泡换行上限预排版正文并返回最宽一行的像素宽度；与标签 AUTOWRAP_WORD_SMART 使用同一组断行标志，
## 保证测量结果与实际渲染逐行一致，折行后的气泡宽度贴合正文而不是固定停留在换行上限。
func _measure_wrapped_text_width(message: String) -> float:
	# 预排版段落对象；只用于测量，不参与渲染，函数返回后即释放。
	var paragraph: TextParagraph = TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.width = maximum_text_width
	paragraph.add_string(message, _message_label.get_theme_font("font"), font_size)
	# 换行后最宽一行的宽度；单行短消息即其完整宽度，多行消息取各行最大值。
	var widest_line_width: float = 0.0
	for line_index: int in range(paragraph.get_line_count()):
		widest_line_width = maxf(widest_line_width, paragraph.get_line_size(line_index).x)
	return widest_line_width
