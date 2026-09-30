class_name SkillDescriptionView
extends RichTextLabel

## 可复用技能说明视图。轮回技按①②等轮回节切分，当前节使用强调色，其他节使用淡色，公共正文保持普通颜色。

## 可识别的轮回节序号；数组索引与轮回状态中的零基section_index完全一致。
const SECTION_SYMBOLS: Array[String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]

## 删除线标记的开始标记；技能用它把已经失效的原文片段划掉（例如【断界】已被删除的选项）。
const STRIKE_OPEN_TAG: String = "[s]"

## 删除线标记的结束标记；必须与开始标记成对出现，未闭合的开始标记延伸到所在分段末尾。
const STRIKE_CLOSE_TAG: String = "[/s]"

## 自绘删除线的线宽（像素）；RichTextLabel 内置删除线由字体度量决定、只有1像素左右且引擎不提供加粗接口，
## 因此本视图不使用 push_strikethrough，而是按被划片段的位置自己画一条明显更粗的线。
## 该常量是“删除线显眼程度”的唯一调节点：数值越大线越粗；典型取值2.0至4.0，0.0等同于不画。
const STRIKE_THICKNESS: float = 3.0

## 删除线在行内的垂直位置比例；0.5 表示画在行高中线（与字体内置删除线的视觉位置接近）。
## 取值过小会贴到文字上沿、过大则接近下划线，一般不需要修改。
const STRIKE_VERTICAL_RATIO: float = 0.5


## 删除线覆盖层。它只是父视图的绘制画布：父视图算好每段线的位置后写入 segments，
## 覆盖层在自身 _draw() 中以指定线宽绘制，从而绕开“字体内置删除线无法加粗”的引擎限制。
## 覆盖层与父视图同尺寸、不接收鼠标事件，因此不会影响信息框的悬停与滚动行为。
class StrikeOverlay extends Control:
	## 待绘制线段；每项为 {"x0":float, "x1":float, "y":float}，坐标以覆盖层（即父视图）左上角为原点。
	var segments: Array[Dictionary] = []

	## 线段颜色；与所属文本相同，保持“删除线与文字同色”的既有观感，靠加粗提升可见度。
	var line_color: Color = Color.WHITE

	## 线宽（像素）；由父视图的 STRIKE_THICKNESS 写入。
	var thickness: float = 3.0

	## 绘制全部删除线段；antialiased 打开避免斜线锯齿，水平线本身不受影响。
	func _draw() -> void:
		if segments.is_empty() or thickness <= 0.0:
			return
		for segment: Dictionary in segments:
			# 当前线段端点；缺字段时按0处理，绝不让异常数据中断整层绘制。
			var start_point: Vector2 = Vector2(float(segment.get("x0", 0.0)), float(segment.get("y", 0.0)))
			var end_point: Vector2 = Vector2(float(segment.get("x1", 0.0)), float(segment.get("y", 0.0)))
			draw_line(start_point, end_point, line_color, thickness, true)


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

## 最近一次绘制中被划掉的片段；每项为 {"start":int, "end":int, "color":"#rrggbbaa"}，
## 区间是可见文本中的左闭右开下标，颜色为片段所在段落的文字颜色（删除线与文字同色）。
var _rendered_strike_ranges: Array[Dictionary] = []

## 最近一次计算的删除线段深拷贝；每项为 {"x0","x1","y","color"}，供界面回归与调试读取。
var _strike_segments: Array[Dictionary] = []

## 删除线覆盖层；在 _ready 中创建，负责把粗删除线画在文本之上。
var _strike_overlay: StrikeOverlay = null

## 绘制兜底是否已经用过；首次布局完成前 get_line_count() 可能仍为0，
## 因此在真正绘制时补算一次线段，并用该标记保证同一次渲染只重试一次，避免刷新循环。
var _strike_refresh_retry_used: bool = false


## 初始化自动换行与内容自适应；该视图只展示文字，不接收鼠标或滚动输入。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bbcode_enabled = false
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("normal_font_size", 14)
	_create_strike_overlay()
	refresh_ui_style()


## 创建删除线覆盖层并跟随父视图尺寸变化重算线段；覆盖层始终位于文本之上。
func _create_strike_overlay() -> void:
	if _strike_overlay != null:
		return
	_strike_overlay = StrikeOverlay.new()
	_strike_overlay.name = "StrikeOverlay"
	_strike_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strike_overlay.thickness = STRIKE_THICKNESS
	_strike_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_strike_overlay)
	# 布局变化（换行位置、行高、控件宽度）都会改变删除线坐标，因此必须重新计算。
	resized.connect(_refresh_strike_segments)
	# 该视图自身绘制时补一次兜底计算，覆盖“文本刚写入、布局尚未完成”的首帧。
	draw.connect(_on_view_drawn)


## 视图绘制时的兜底：首帧布局可能尚未完成，此时补算一次删除线线段。
func _on_view_drawn() -> void:
	if _strike_overlay == null or _strike_refresh_retry_used:
		return
	if _strike_segments.is_empty() and not _rendered_strike_ranges.is_empty():
		_strike_refresh_retry_used = true
		_refresh_strike_segments()


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


## 返回最近一次绘制中被划掉的片段区间与颜色；没有被划掉的片段时为空数组。
func get_rendered_strike_ranges() -> Array[Dictionary]:
	return _rendered_strike_ranges.duplicate(true)


## 返回最近一次计算的删除线段深拷贝；未布局或没有被划片段时为空数组。
func get_strike_segments() -> Array[Dictionary]:
	return _strike_segments.duplicate(true)


## 返回自绘删除线的线宽；界面回归据此确认删除线确实被加粗，而不是沿用字体内置细线。
func get_strike_thickness() -> float:
	return STRIKE_THICKNESS


## 按当前活动主题重绘全部分段颜色；技能文本和轮回状态保持不变。
func refresh_ui_style() -> void:
	add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	_render_description()


## 解析轮回节边界并以主题颜色重新构建富文本；公共前后缀始终使用普通次级文字色。
func _render_description() -> void:
	clear()
	_rendered_segments.clear()
	_rendered_visible_text = ""
	_rendered_strike_ranges.clear()
	# 新文本允许再用一次绘制兜底；旧文本的线段在下面的刷新里被清空。
	_strike_refresh_retry_used = false
	# 文本内容已变化，旧的删除线坐标全部失效；在本次布局完成后统一重算。
	_refresh_strike_segments()
	if _source_description.is_empty():
		return
	# 普通正文颜色；轮回技标签、触发条件、X说明和跨轮回节持续效果均使用该颜色。
	var normal_color: Color = BattleUIStyle.get_color("text_secondary")
	if not _is_reincarnation:
		_append_colored_segment(_source_description, normal_color, -1, false)
		call_deferred("_refresh_strike_segments")
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
		call_deferred("_refresh_strike_segments")
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
	call_deferred("_refresh_strike_segments")


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
	_append_text_with_strike(segment_text, color)
	pop()
	_rendered_segments.append({"text":segment_text, "section_index":section_index, "current":is_current, "color":color.to_html(true)})


## 按删除线标记切分并逐段追加文本；标记本身不进入可见文本，返回的分段元数据仍保留原始标记。
## 不使用 BBCode：本视图显式关闭 bbcode_enabled，add_text 不会解析任何标签，因此这里自行解析这一对标记——
## 既能画出删除线，又不会让其他技能描述里出现的方括号被误当成富文本标签。
## 被划片段只登记区间与段落颜色，真正的粗删除线由覆盖层在布局完成后自绘。
func _append_text_with_strike(segment_text: String, color: Color) -> void:
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
			_append_struck_text(segment_text.substr(content_start), color)
			return
		_append_struck_text(segment_text.substr(content_start, close_index - content_start), color)
		cursor = close_index + STRIKE_CLOSE_TAG.length()


## 追加一段被划掉的可见文本并登记其位置。
## 这里**不**改变文字颜色、也**不**调用 push_strikethrough：内置删除线由字体度量决定、无法加粗，
## 因此只用所在段落的颜色正常写入文字，删除线交给覆盖层按登记的区间自绘。
func _append_struck_text(struck_text: String, color: Color) -> void:
	if struck_text.is_empty():
		return
	# 被划片段在可见文本中的起点；必须在本段文字写入之前读取。
	var strike_start: int = _rendered_visible_text.length()
	_append_visible_text(struck_text)
	_rendered_strike_ranges.append({
		"start":strike_start,
		"end":_rendered_visible_text.length(),
		"color":color.to_html(true),
	})


## 追加一段可见文本并同步记录纯文本镜像；所有可见文字都必须经由此入口写入，标记不得进入镜像。
func _append_visible_text(visible_text: String) -> void:
	if visible_text.is_empty():
		return
	add_text(visible_text)
	_rendered_visible_text += visible_text


## 依据最近一次渲染结果与当前布局重算删除线线段，并交给覆盖层绘制。
## RichTextLabel 只暴露行级信息（get_line_range/get_line_offset/get_line_height/get_line_width），
## 没有现成的“字符矩形”接口，因此这里按行与被划区间求交，再用字体测量前缀宽度得到精确的起止 x。
func _refresh_strike_segments() -> void:
	if _strike_overlay == null:
		return
	_strike_segments.clear()
	# 没有可绘制内容时立即清空覆盖层，避免残留上一份描述的删除线。
	if _rendered_strike_ranges.is_empty() or _rendered_visible_text.is_empty() or get_line_count() <= 0:
		_strike_overlay.segments = []
		_strike_overlay.queue_redraw()
		return
	# 文本绘制原点；fit_content 视图的内容矩形左上角即文本起点，可自动兼容内容边距。
	var content_origin: Vector2 = Vector2(get_visible_content_rect().position)
	# 当前字体与字号；必须与渲染时使用的 normal_font 保持一致才能量出正确宽度。
	var text_font: Font = get_theme_font("normal_font")
	var text_font_size: int = get_theme_font_size("normal_font_size")
	# 覆盖层使用的线色；同一份描述里不同段落颜色可能不同，逐段取色即可。
	var overlay_segments: Array[Dictionary] = []
	for line_index: int in range(get_line_count()):
		# 当前行覆盖的字符区间；左闭右开，与 _rendered_strike_ranges 同一坐标系。
		var line_range: Vector2i = get_line_range(line_index)
		var line_text: String = _rendered_visible_text.substr(line_range.x, line_range.y - line_range.x)
		if line_text.is_empty():
			continue
		# 当前行的起始 x；左对齐时就是文本原点，居中与右对齐需要按行宽补偿。
		var line_start_x: float = content_origin.x + _get_line_alignment_offset(line_index)
		# 当前行的删除线纵坐标；取行高中线，与字体内置删除线的视觉位置接近。
		var line_y: float = content_origin.y + get_line_offset(line_index) + float(get_line_height(line_index)) * STRIKE_VERTICAL_RATIO
		for strike_range: Dictionary in _rendered_strike_ranges:
			# 被划区间与当前行的交集；没有交集说明该片段落在别的行。
			var overlap_start: int = maxi(int(strike_range.get("start", 0)), line_range.x)
			var overlap_end: int = mini(int(strike_range.get("end", 0)), line_range.y)
			if overlap_end <= overlap_start:
				continue
			# 行内前缀与被划文字；两者都用同一字体测量，保证与真实排版一致。
			var prefix_text: String = line_text.substr(0, overlap_start - line_range.x)
			var struck_text: String = line_text.substr(overlap_start - line_range.x, overlap_end - overlap_start)
			var x0: float = line_start_x + text_font.get_string_size(prefix_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_font_size).x
			var x1: float = x0 + text_font.get_string_size(struck_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_font_size).x
			# 线段颜色；与所属段落文字颜色一致，保持“同色但更粗”的删除线观感。
			var line_color: Color = Color(str(strike_range.get("color", "#ffffffff")))
			overlay_segments.append({"x0":x0, "x1":x1, "y":line_y})
			_strike_segments.append({"x0":x0, "x1":x1, "y":line_y, "color":line_color.to_html(true)})
	# 覆盖层逐段绘制；没有线段时也刷新一次，确保旧线被清除。
	_strike_overlay.segments = overlay_segments
	# 线色统一取第一段的颜色：同一份技能描述内被划片段通常同色，逐段异色时以首段为准仍可读。
	_strike_overlay.line_color = Color(str(_rendered_strike_ranges[0].get("color", "#ffffffff")))
	_strike_overlay.thickness = STRIKE_THICKNESS
	_strike_overlay.queue_redraw()


## 返回当前行相对文本原点的水平偏移；只处理左/中/右三种对齐，其他对齐按左对齐处理。
func _get_line_alignment_offset(line_index: int) -> float:
	match get_horizontal_alignment():
		HORIZONTAL_ALIGNMENT_CENTER:
			return maxf((size.x - float(get_line_width(line_index))) * 0.5, 0.0)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return maxf(size.x - float(get_line_width(line_index)), 0.0)
		_:
			return 0.0
