extends Node

## 模式陈列卡的独立装饰组件。父节点仍是原生Button，选择、焦点与开局信号由首页管理。
## 卡面使用矢量徽记、序号和深色信息页脚；不加载武将数据库，不持有游戏模式状态。

## 卡片序号；0至6用于读取静态徽记与栏目短名，默认0对应身份模式，运行时无需调整。
@export_range(0, 6, 1) var mode_index: int = 0
## 深色页脚高度；默认106像素，与卡片标题区相匹配，修改时应同步场景中的文字边距。
@export_range(80.0, 140.0, 1.0) var footer_height: float = 106.0
## 徽记尺寸；默认108像素，0以外的正数均可，用于调整装饰比例，运行时无需修改。
@export_range(64.0, 160.0, 1.0) var emblem_size: float = 108.0
## 内框距边缘的留白；默认14像素，避免装饰线与卡片边框重叠。
const INSET: float = 14.0
## 序号与模式短名；纯展示文案，不用于解析规则ID或提交玩法请求。
const CAPTIONS: Array[String] = ["STANDARD", "CHALLENGE", "TEAM PLAY", "DUEL", "FORTUNE", "EXPEDITION", "SURVIVAL"]
## 七种模式的矢量徽记；只作为低成本界面装饰，尺寸由emblem_size统一控制。
const EMBLEMS: Array[Texture2D] = [
	preload("res://assets/ui/modes/standard.svg"),
	preload("res://assets/ui/modes/challenge.svg"),
	preload("res://assets/ui/modes/team.svg"),
	preload("res://assets/ui/modes/duel.svg"),
	preload("res://assets/ui/modes/fortune.svg"),
	preload("res://assets/ui/modes/expedition.svg"),
	preload("res://assets/ui/modes/survival.svg"),
]
## 原生卡片按钮；初始为空，入树后绑定直接父节点，组件不越界查找首页。
var _button: Button
## 复用的页脚样式；只在主题改变时重建，不在每次绘制分配资源。
var _footer: StyleBoxFlat


## 注册绘制和主题监听；没有逐帧处理，不改变原按钮的点击区域。
func _ready() -> void:
	_button = get_parent() as Button
	_button.draw.connect(_draw_card)
	_button.resized.connect(_button.queue_redraw)
	_button.toggled.connect(_on_toggled)
	GameSettings.ui_style_changed.connect(_on_style_changed)
	refresh_style()


## 切换选中态仅请求重绘；按钮信号继续由原有业务代码消费。
func _on_toggled(_selected: bool) -> void:
	_button.queue_redraw()


## 等主题协调器写入活动配色后再更新装饰，避免混用新旧主题。
func _on_style_changed(_style_id: String) -> void:
	call_deferred("refresh_style")


## 构造深色页脚；其浅色文字使用on_dark语义，与内容面的深色正文分离。
func refresh_style() -> void:
	_footer = StyleBoxFlat.new()
	_footer.bg_color = BattleUIStyle.get_color("rail")
	_footer.corner_radius_bottom_left = 8
	_footer.corner_radius_bottom_right = 8
	_button.queue_redraw()


## 绘制没有鼠标区域的装饰；所有坐标由宿主尺寸计算，窗口拉伸后自动保持比例。
func _draw_card() -> void:
	# 可用卡面矩形；留出页脚和边缘，避免徽记遮挡文字。
	var face: Rect2 = Rect2(Vector2.ONE * INSET, Vector2(_button.size.x - INSET * 2.0, _button.size.y - footer_height - INSET * 2.0))
	# 香槟金线色；选中时提高饱和度，无需额外闪烁动画。
	var gold: Color = BattleUIStyle.get_color("border")
	# 展示序号；超出范围时钳制，编辑器中不产生数组越界。
	var index: int = clampi(mode_index, 0, CAPTIONS.size() - 1)
	# 中央徽记位置；相对纸面中心略下移，为顶部编号留出呼吸空间。
	var center: Vector2 = face.get_center() + Vector2(0.0, 14.0)
	# 紧凑卡身的徽记绘制尺寸；保留顶部编号空间，不修改按钮布局或文字字号。
	var fitted_emblem_size: float = minf(emblem_size, maxf(face.size.y - 64.0, 48.0))
	_button.draw_rect(face, Color(gold, 0.36), false, 1.0)
	_button.draw_line(Vector2(INSET, 52.0), Vector2(_button.size.x - INSET, 52.0), Color(gold, 0.24), 1.0)
	_button.draw_string(ThemeDB.fallback_font, Vector2(25.0, 38.0), "%02d  /  %s" % [index + 1, CAPTIONS[index]], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, BattleUIStyle.get_color("text_muted"))
	_button.draw_arc(center, fitted_emblem_size * 0.79, 0.0, TAU, 80, Color(gold, 0.16), 1.0, true)
	_button.draw_arc(center, fitted_emblem_size * 0.71, 0.0, TAU, 80, Color(gold, 0.24), 1.0, true)
	_button.draw_texture_rect(EMBLEMS[index], Rect2(center - Vector2.ONE * fitted_emblem_size * 0.5, Vector2.ONE * fitted_emblem_size), false, gold)
	_button.draw_style_box(_footer, Rect2(Vector2(0.0, _button.size.y - footer_height), Vector2(_button.size.x, footer_height)))
	_button.draw_line(Vector2(0.0, _button.size.y - footer_height), Vector2(_button.size.x, _button.size.y - footer_height), Color(gold, 0.8), 1.0)
	_button.draw_string(ThemeDB.fallback_font, Vector2(_button.size.x - 30.0, _button.size.y - 29.0), "›", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, BattleUIStyle.get_color("accent"))
	if _button.button_pressed:
		_button.draw_circle(Vector2(_button.size.x - 27.0, 32.0), 8.0, gold)
		_button.draw_line(Vector2(_button.size.x - 31.0, 32.0), Vector2(_button.size.x - 28.0, 35.0), BattleUIStyle.get_color("panel"), 1.8, true)
		_button.draw_line(Vector2(_button.size.x - 28.0, 35.0), Vector2(_button.size.x - 23.0, 29.0), BattleUIStyle.get_color("panel"), 1.8, true)
