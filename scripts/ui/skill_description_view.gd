class_name SkillDescriptionView
extends RichTextLabel

## 可复用技能说明视图。轮回技按①②等轮回节切分，当前节使用强调色，其他节使用淡色，公共正文保持普通颜色。

## 可识别的轮回节序号；数组索引与轮回状态中的零基section_index完全一致。
const SECTION_SYMBOLS: Array[String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]

## 当前完整技能说明原文；只用于重绘和测试查询，任何分段都不会改写该字符串。
var _source_description: String = ""

## 当前说明是否属于轮回技；false时即使正文含带圈数字也保持普通颜色。
var _is_reincarnation: bool = false

## 当前轮回节零基索引；①对应0，越界值在绘制时收敛到现有分段范围。
var _current_section_index: int = 0

## 当前轮回技已轮回的轮回数；0表示不显示轮回数提示，非0时在正文之前独立渲染一行。
var _reincarnation_round_count: int = 0

## 最近一次绘制得到的文本分段；每项保存text、section_index与current，供界面回归验证颜色语义。
var _rendered_segments: Array[Dictionary] = []


## 初始化自动换行与内容自适应；该视图只展示文字，不接收鼠标或滚动输入。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bbcode_enabled = false
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("normal_font_size", 14)
	refresh_ui_style()


## 写入技能说明与当前轮回节；原文保持逐字不变，静态局外资料默认传入①对应的0。
## 轮回数提示以独立前置分段渲染，不写入 _source_description，因此技能描述原文始终逐字可读。
func configure_description(description: String, is_reincarnation_skill: bool = false, current_section_index: int = 0, reincarnation_round_count: int = 0) -> void:
	_source_description = description
	_is_reincarnation = is_reincarnation_skill
	_current_section_index = maxi(current_section_index, 0)
	_reincarnation_round_count = maxi(reincarnation_round_count, 0)
	_render_description()


## 返回未附加颜色标记的完整说明原文；信息框测试与辅助功能可直接读取。
func get_plain_description() -> String:
	return _source_description


## 返回最近一次分段的深拷贝；测试可验证当前节而无需解析RichTextLabel内部绘制命令。
func get_rendered_segments() -> Array[Dictionary]:
	return _rendered_segments.duplicate(true)


## 按当前活动主题重绘全部分段颜色；技能文本和轮回状态保持不变。
func refresh_ui_style() -> void:
	add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	_render_description()


## 解析轮回节边界并以主题颜色重新构建富文本；公共前后缀始终使用普通次级文字色。
func _render_description() -> void:
	clear()
	_rendered_segments.clear()
	# 轮回数提示分段；轮回技在正文之前独立显示，普通技能或未传入轮回数时不创建该段。
	# 该分段不参与轮回节着色，因此正文的①至⑩分段索引与原文逐字内容都不受影响。
	if _is_reincarnation and _reincarnation_round_count > 0:
		_append_colored_segment("本技能已轮回%d次。\n" % _reincarnation_round_count, BattleUIStyle.get_color("text_secondary"), -1, false)
	if _source_description.is_empty():
		return
	# 普通正文颜色；轮回技标签、触发条件、X说明和跨轮回节持续效果均使用该颜色。
	var normal_color: Color = BattleUIStyle.get_color("text_secondary")
	if not _is_reincarnation:
		_append_colored_segment(_source_description, normal_color, -1, false)
		return
	# 正文中实际出现的轮回节起始位置；按①至⑩顺序记录，配置异常缺号也不会改变原文。
	var section_positions: Array[int] = []
	for section_symbol: String in SECTION_SYMBOLS:
		# 当前带圈序号在正文中的首次位置；未出现时不创建空分段。
		var symbol_position: int = _source_description.find(section_symbol)
		if symbol_position >= 0:
			section_positions.append(symbol_position)
	if section_positions.is_empty():
		_append_colored_segment(_source_description, normal_color, -1, false)
		return
	section_positions.sort()
	# 第一个轮回节之前的技能类型和触发条件前缀；不属于任一可切换效果段。
	var first_section_position: int = section_positions[0]
	if first_section_position > 0:
		_append_colored_segment(_source_description.substr(0, first_section_position), normal_color, -1, false)
	# 最后已经写入的字符位置；最后轮回节后的X解释或共同效果从该位置继续按普通色绘制。
	var rendered_cursor: int = first_section_position
	for visible_section_index: int in range(section_positions.size()):
		# 当前轮回节起始字符位置；包含带圈序号本身。
		var section_start: int = section_positions[visible_section_index]
		# 当前轮回节默认结束位置；非最后一节止于下一个带圈序号之前。
		var section_end: int = section_positions[visible_section_index + 1] if visible_section_index + 1 < section_positions.size() else _find_last_section_end(section_start)
		# 当前轮回节是否为权威状态指定的高亮节；只有该段使用主题强调色。
		var is_current: bool = visible_section_index == clampi(_current_section_index, 0, section_positions.size() - 1)
		# 当前轮回节字体颜色；非当前节统一淡化，当前节使用高亮色。
		var section_color: Color = BattleUIStyle.get_color("accent") if is_current else BattleUIStyle.get_color("text_muted")
		_append_colored_segment(_source_description.substr(section_start, section_end - section_start), section_color, visible_section_index, is_current)
		rendered_cursor = section_end
	if rendered_cursor < _source_description.length():
		_append_colored_segment(_source_description.substr(rendered_cursor), normal_color, -1, false)


## 查找最后一个轮回节的规则句末；句末之后的轮回数解释或共同持续效果不随轮回节淡化。
func _find_last_section_end(section_start: int) -> int:
	# 最后轮回节后首个中文句号；优先把完整句子包含在轮回节段内。
	var period_position: int = _source_description.find("。", section_start)
	# 最后轮回节后首个中文分号；某些技能以分号结束最后一节，需与句号取更早者。
	var semicolon_position: int = _source_description.find("；", section_start)
	# 最早有效句末位置；两者均不存在时让最后轮回节延伸到正文末尾。
	var ending_position: int = -1
	if period_position >= 0:
		ending_position = period_position
	if semicolon_position >= 0 and (ending_position < 0 or semicolon_position < ending_position):
		ending_position = semicolon_position
	return ending_position + 1 if ending_position >= 0 else _source_description.length()


## 向RichTextLabel追加一段纯文本及颜色，并同步记录可测试分段元数据。
func _append_colored_segment(segment_text: String, color: Color, section_index: int, is_current: bool) -> void:
	if segment_text.is_empty():
		return
	push_color(color)
	add_text(segment_text)
	pop()
	_rendered_segments.append({"text":segment_text, "section_index":section_index, "current":is_current, "color":color.to_html(true)})
