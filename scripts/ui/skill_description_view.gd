class_name SkillDescriptionView
extends RichTextLabel

## 可复用技能说明视图。轮回技按①②等轮回节切分，当前节使用强调色，其他节使用淡色，公共正文保持普通颜色。

## 可识别的轮回节序号；数组索引与轮回状态中的零基section_index完全一致。
const SECTION_SYMBOLS: Array[String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]

## 删除线标记的开始标记；技能用它把已经失效的原文片段划掉（例如【断界】已被删除的选项）。
const STRIKE_OPEN_TAG: String = "[s]"

## 删除线标记的结束标记；必须与开始标记成对出现，未闭合的开始标记延伸到所在分段末尾。
const STRIKE_CLOSE_TAG: String = "[/s]"

## 被划掉片段的颜色语义键；使用主题危险色让“已失效”的原文一眼可见，
## 而不是与正文同色的细删线（正文次级色在深色面板上几乎看不出划线）。
## 该颜色在每次重绘时读取，因此切换主题后由 refresh_ui_style 自动跟随。
const STRIKE_COLOR_KEY: String = "danger"

## 当前完整技能说明原文；只用于重绘和测试查询，任何分段都不会改写该字符串。
var _source_description: String = ""

## 当前说明是否属于轮回技；false时即使正文含带圈数字也保持普通颜色。
var _is_reincarnation: bool = false

## 当前轮回节零基索引；①对应0，越界值在绘制时收敛到现有分段范围。
var _current_section_index: int = 0

## 最近一次绘制得到的文本分段；每项保存text、section_index与current，供界面回归验证颜色语义。
var _rendered_segments: Array[Dictionary] = []

## 最近一次绘制实际写入控件的可见纯文本；删除线标记已剥离，与分段元数据互补，
## 供界面回归验证“标记被解析成删除线而不是被当成普通文字画出来”。
var _rendered_visible_text: String = ""

## 最近一次绘制中被删除线划掉的片段颜色；每项为 "#rrggbbaa"，
## 供界面回归验证被划掉的原文确实使用了醒目色，而不是与正文同色的默认细线。
var _rendered_strike_colors: Array[String] = []


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
func configure_description(description: String, is_reincarnation_skill: bool = false, current_section_index: int = 0) -> void:
	_source_description = description
	_is_reincarnation = is_reincarnation_skill
	_current_section_index = maxi(current_section_index, 0)
	_render_description()


## 返回未附加颜色标记的完整说明原文；信息框测试与辅助功能可直接读取。
func get_plain_description() -> String:
	return _source_description


## 返回最近一次分段的深拷贝；测试可验证当前节而无需解析RichTextLabel内部绘制命令。
func get_rendered_segments() -> Array[Dictionary]:
	return _rendered_segments.duplicate(true)


## 返回最近一次绘制实际写入控件的可见纯文本；删除线标记已剥离，未渲染时为空字符串。
func get_rendered_visible_text() -> String:
	return _rendered_visible_text


## 返回最近一次绘制中被删除线划掉的片段颜色；没有被划掉的片段时为空数组。
func get_rendered_strike_colors() -> Array[String]:
	return _rendered_strike_colors.duplicate()


## 按当前活动主题重绘全部分段颜色；技能文本和轮回状态保持不变。
func refresh_ui_style() -> void:
	add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	_render_description()


## 解析轮回节边界并以主题颜色重新构建富文本；公共前后缀始终使用普通次级文字色。
func _render_description() -> void:
	clear()
	_rendered_segments.clear()
	_rendered_visible_text = ""
	_rendered_strike_colors.clear()
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
	_append_text_with_strike(segment_text)
	pop()
	_rendered_segments.append({"text":segment_text, "section_index":section_index, "current":is_current, "color":color.to_html(true)})


## 按删除线标记切分并逐段追加文本；标记本身不进入可见文本，返回的分段元数据仍保留原始标记。
## 不使用 BBCode：本视图显式关闭 bbcode_enabled，add_text 不会解析任何标签，因此这里自行解析这一对标记——
## 既能画出删除线，又不会让其他技能描述里出现的方括号被误当成富文本标签。
func _append_text_with_strike(segment_text: String) -> void:
	# 尚未追加的起始位置；每次处理完一对标记后指向结束标记之后。
	var cursor: int = 0
	while cursor < segment_text.length():
		# 当前起始标记位置；没有剩余标记时直接追加尾部普通文本并结束。
		var open_index: int = segment_text.find(STRIKE_OPEN_TAG, cursor)
		if open_index < 0:
			_append_visible_text(segment_text.substr(cursor))
			return
		if open_index > cursor:
			_append_visible_text(segment_text.substr(cursor, open_index - cursor))
		# 起始标记之后的正文起点；找不到结束标记时按“延伸到分段末尾”处理，保证标记不丢失也不吞掉后续文本。
		var content_start: int = open_index + STRIKE_OPEN_TAG.length()
		var close_index: int = segment_text.find(STRIKE_CLOSE_TAG, content_start)
		if close_index < 0:
			_append_struck_text(segment_text.substr(content_start))
			return
		_append_struck_text(segment_text.substr(content_start, close_index - content_start))
		cursor = close_index + STRIKE_CLOSE_TAG.length()


## 追加一段被删除线划掉的可见文本。
## 被划掉的片段改用主题危险色绘制：富文本的删除线使用当前文字颜色描线，
## 因此改颜色能让文字与划线同时从正文次级色里跳出来，解决“划线细、颜色接近背景、看不出被划掉”的问题。
## 颜色每次重绘时重新读取，主题切换后无需额外刷新入口；片段颜色同时记入可测试元数据。
func _append_struck_text(struck_text: String) -> void:
	if struck_text.is_empty():
		return
	# 被划片段颜色；取自当前活动主题，缺键时回退为危险色常量，保证任何主题下划线都清晰可见。
	var strike_color: Color = BattleUIStyle.get_color(STRIKE_COLOR_KEY, BattleUIStyle.DANGER_COLOR)
	push_color(strike_color)
	push_strikethrough()
	_append_visible_text(struck_text)
	pop()
	pop()
	_rendered_strike_colors.append(strike_color.to_html(true))


## 追加一段可见文本并同步记录纯文本镜像；所有可见文字都必须经由此入口写入，标记不得进入镜像。
func _append_visible_text(visible_text: String) -> void:
	if visible_text.is_empty():
		return
	add_text(visible_text)
	_rendered_visible_text += visible_text
