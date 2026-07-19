class_name EquipmentStackView
extends Control

## 可复用的本地装备堆叠视图。组件只渲染公开装备快照并发出实体 UID 点击信号，不读取或修改规则状态。

## 玩家点击可选装备横条时发出的信号；桌面协调器负责维护临时选择并提交统一选牌动作。
signal equipment_pressed(card_uid: int)

## 鼠标进入已装备横条时发出的统一信息请求；空槽不会产生卡牌信息。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开装备横条或装备区重建时发出的统一信息关闭请求。
signal information_dismissed

## 单张装备横条的显示高度；默认38像素让左下装备区在五槽布局中仍能清楚展示槽位、花色、点数和牌名，运行时通常无需动态修改。
## 参考图紧凑布局使用27像素固定槽高，与 `equip_new.css` 的单槽规格一致。
## 等高布局将27像素作为最小槽高，并按当前4槽或5槽数量自动放大到恰好填满装备栏。
@export_range(22.0, 40.0, 1.0) var equipment_row_height: float = 27.0

## 相邻装备横条至少覆盖的高度；默认8像素形成与武将牌装备横条一致的叠牌层次，只影响表现且运行时通常无需动态修改。
## 参考图的本地装备槽互不覆盖，因此默认值改为0；如需主题化叠牌仍可在检查器中增加该值。
@export_range(0.0, 12.0, 1.0) var equipment_row_overlap: float = 0.0

## 相邻装备槽的垂直间距；默认3像素复刻参考图的独立槽位分隔，运行时通常无需动态修改。
@export_range(0.0, 12.0, 1.0) var equipment_row_gap: float = 3.0

## 可选装备向右移动的距离；默认12像素在左侧装备区与手牌区之间提供明确候选反馈，运行时可按界面间距调整。
## 参考 CSS 的左侧布局使用10像素右移反馈，横条移动后仍与手牌区保留安全间距。
@export_range(0.0, 24.0, 1.0) var selectable_shift_distance: float = 10.0

## 已选装备在可用右移基础上继续向右移动的距离；默认再移动10像素区分“可发动”和“已选择”，运行时可按界面间距调整。
@export_range(0.0, 24.0, 1.0) var selected_shift_distance: float = 10.0

## 装备横条进入可用、选中或复原位置的动画时长；默认0.25秒提供清晰但不拖慢操作的位移反馈，运行时可由主题调整。
@export_range(0.0, 1.0, 0.01) var shift_animation_seconds: float = 0.25

## 装备横条正文字体尺寸；默认14像素适合198像素宽的本地装备区，运行时通常无需动态修改。
## 参考图紧凑横条使用13像素正文，保证130像素宽度内仍可显示花色、点数和牌名。
@export_range(10, 18, 1) var equipment_font_size: int = 13

## 槽位图标区域宽度；默认24像素让空槽和已装备槽的类型图标保持统一左对齐，运行时通常无需动态修改。
@export_range(18.0, 36.0, 1.0) var slot_icon_width: float = 24.0

## 固定装备槽顺序；前四槽始终参与位置计算，宝物槽只在实际装备宝物时加入布局。
## 第一视角装备栏常态保留全部五槽，宝物空槽与其他空槽使用相同深色类型占位。
const EQUIPMENT_SLOT_ORDER: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]

## 装备槽中文名称；横条直接标明槽位，空槽不创建占位文字但仍保留对应纵向位置。
const EQUIPMENT_SLOT_NAMES: Dictionary = {
	"weapon":"武器",
	"armor":"防具",
	"offensive_mount":"进攻",
	"defensive_mount":"防御",
	"treasure":"宝物",
}

## 装备槽类型图标；使用项目字体可稳定渲染的符号表达武器、防具、进攻坐骑、防御坐骑和宝物。
const EQUIPMENT_SLOT_ICONS: Dictionary = {
	"weapon":"⚔",
	"armor":"▣",
	"offensive_mount":"-",
	"defensive_mount":"+",
	"treasure":"▰",
}

## 当前本地装备快照；键为固定槽位 ID，值为裁剪后的实体牌字典。
var _equipment: Dictionary = {}

## 当前木牛流马公开“粮”数量；默认0，只有宝物为木牛流马时附加到装备名后。
var _wooden_ox_count: int = 0

## 当前允许在本组件中选择的装备 UID；不在集合中的装备保持原位且不接收点击。
var _candidate_uids: Array[int] = []

## 当前已被桌面临时选中的实体 UID；选中横条使用金色描边但不自行改变规则状态。
var _selected_uids: Array[int] = []

## 当前槽位到装备横条按钮的映射；只保存本组件创建的表现节点，用于固定槽位布局与测试查询。
var _rows_by_slot: Dictionary = {}

## 当前参与纵向位置计算的槽位数量；默认4，装备宝物后变为5并压缩整组堆叠间距。
## 第一视角装备栏固定显示五槽，因此该值常态为5并只保留为布局计算入口。
var _visible_slot_count: int = 5

## 最近一次装备、候选、选中和名称模式的配置签名；默认-1表示从未配置，重复快照不会重建相同横条。
var _configuration_signature: int = -1

## 当前槽位到横向位移动画的映射；配置变化时先停止旧动画，避免重建横条后多个补间同时写入位置。
var _row_shift_tweens: Dictionary = {}


## 初始化鼠标策略；空白装备区不遮挡牌桌输入，只有可选装备横条自身接收点击。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild_rows()


## 接收本地装备快照和当前桌面选择状态；输入均为值副本，组件不会持有可修改的权威对象引用。
func configure(equipment: Dictionary, wooden_ox_count: int, candidate_uids: Array[int] = [], selected_uids: Array[int] = []) -> void:
	# 本次完整配置签名；全局牌名模式参与缓存判断，切换名称后会强制刷新全部装备横条。
	var next_configuration_signature: int = hash([equipment, wooden_ox_count, candidate_uids, selected_uids, GameSettings.card_name_mode, GameSettings.ui_style_id])
	if _configuration_signature == next_configuration_signature:
		return
	_configuration_signature = next_configuration_signature
	_equipment = equipment.duplicate(true)
	_wooden_ox_count = maxi(wooden_ox_count, 0)
	_candidate_uids = candidate_uids.duplicate()
	_selected_uids = selected_uids.duplicate()
	_visible_slot_count = EQUIPMENT_SLOT_ORDER.size()
	_rebuild_rows()


## 按当前活动 UI 风格重建装备横条；装备快照、候选 UID、选中 UID 与位移动画语义保持不变。
func refresh_ui_style() -> void:
	_configuration_signature = -1
	_rebuild_rows()


## 返回指定槽位当前创建的装备横条；空槽返回 null，调用方可据此读取公开布局而不访问规则状态。
## 当前可见空槽也会返回深色占位横条；只有尚未启用的宝物槽返回 null。
func get_row(slot: String) -> Button:
	return _rows_by_slot.get(slot) as Button


## 返回指定槽位当前是否实际装备实体牌；空槽横条和隐藏宝物槽都返回 false。
func is_slot_equipped(slot: String) -> bool:
	return _equipment.has(slot)


## 清理旧横条并按固定槽位顺序重建现有装备；没有装备的槽位不生成占位节点。
## 参考图布局会为全部可见槽位生成深色空态；宝物槽仍按项目规则只在实际装备宝物时创建。
func _rebuild_rows() -> void:
	information_dismissed.emit()
	# 重建前各槽位的实际横坐标；新横条从该位置继续动画，保证可用、选中和复原状态之间不会瞬移。
	var previous_shift_by_slot: Dictionary = {}
	for slot_variant: Variant in _rows_by_slot.keys():
		# 旧槽位 ID；用于把旧横条的实时位置转交给同槽位新横条。
		var previous_slot: String = str(slot_variant)
		# 旧装备横条；补间进行到一半时 position.x 仍是准确的下一段动画起点。
		var previous_row: Button = _rows_by_slot.get(previous_slot) as Button
		if previous_row != null and is_instance_valid(previous_row):
			previous_shift_by_slot[previous_slot] = previous_row.position.x
	for shift_tween_variant: Variant in _row_shift_tweens.values():
		# 旧横向位移动画；对应横条即将释放，必须先停止以避免访问失效节点。
		var shift_tween: Tween = shift_tween_variant as Tween
		if shift_tween != null and shift_tween.is_valid():
			shift_tween.kill()
	_row_shift_tweens.clear()
	for row_variant: Variant in _rows_by_slot.values():
		# 旧装备横条；配置变化时立即从树中移除，避免名称模式切换期间短暂显示重复牌面。
		var old_row: Button = row_variant as Button
		if old_row != null and is_instance_valid(old_row):
			remove_child(old_row)
			old_row.queue_free()
	_rows_by_slot.clear()
	if not is_node_ready():
		return
	for slot: String in EQUIPMENT_SLOT_ORDER:
		# 当前槽位是否实际装备实体牌；空槽继续创建深色背景与类型图标，但不接受选择输入。
		var is_equipped: bool = _equipment.has(slot)
		# 当前槽位装备快照；只读取稳定 UID、定义 ID、花色和点数生成牌面横条。
		var equipment_card: Dictionary = _equipment.get(slot, {}) as Dictionary
		# 当前装备实体 UID；负数数据仍可展示，但不会进入可交互候选集合。
		var card_uid: int = int(equipment_card.get("uid", -1))
		# 当前装备定义；用于统一解析卡牌名称和悬停说明。
		var card_definition: Dictionary = GameDatabase.get_card(str(equipment_card.get("definition_id", "")))
		# 当前名称模式下的装备名；配置缺失时回退到稳定定义 ID，便于定位数据异常。
		var equipment_name: String = GameSettings.resolve_card_display_name(card_definition) if not card_definition.is_empty() else str(equipment_card.get("definition_id", "未知装备"))
		if bool(card_definition.get("shows_attachment_count", false)):
			equipment_name += "（%d）" % _wooden_ox_count
		# 当前装备是否属于选择请求候选；候选向右移并接收点击，非候选保持禁用输入。
		var is_candidate: bool = _candidate_uids.has(card_uid)
		# 当前装备是否已被临时选中；选中状态优先使用金色边框。
		var is_selected: bool = _selected_uids.has(card_uid)
		# 单张装备横条按钮；按钮只承接点击，具体花色点数与牌名由子级富文本绘制。
		var equipment_row: Button = _create_equipment_row(slot, equipment_card, card_definition, equipment_name, is_equipped, is_candidate, is_selected)
		equipment_row.pressed.connect(_on_equipment_row_pressed.bind(card_uid))
		if is_equipped:
			equipment_row.mouse_entered.connect(_on_equipment_information_entered.bind(slot, equipment_card, card_definition, equipment_name, equipment_row))
			equipment_row.mouse_exited.connect(_on_equipment_information_exited)
		add_child(equipment_row)
		_rows_by_slot[slot] = equipment_row
	_layout_rows()
	for slot_variant: Variant in _rows_by_slot.keys():
		# 新槽位 ID；与旧槽位同名时才继承上一次实时横坐标。
		var slot: String = str(slot_variant)
		# 新装备横条；纵向布局已经完成，本段只接管横向状态动画。
		var equipment_row: Button = _rows_by_slot.get(slot) as Button
		# 当前状态的目标横坐标；可用右移一段，已选择再额外右移一段，静态状态回到0。
		var target_shift: float = equipment_row.position.x
		# 本次动画起点；首次创建没有旧位置时直接使用目标值，不播放无来源的入场滑动。
		var previous_shift: float = float(previous_shift_by_slot.get(slot, target_shift))
		equipment_row.position.x = previous_shift
		_start_row_shift_animation(slot, equipment_row, target_shift)


## 创建单张叠放装备横条；样式与武将牌装备条共享浅色纸张、暗金边和花色点数表达。
func _create_equipment_row(slot: String, equipment_card: Dictionary, card_definition: Dictionary, equipment_name: String, is_equipped: bool, is_candidate: bool, is_selected: bool) -> Button:
	# 装备横条按钮；禁用状态仍使用正常纸张样式，只通过位置和描边表达候选状态。
	var equipment_row: Button = Button.new()
	equipment_row.focus_mode = Control.FOCUS_NONE
	equipment_row.disabled = not is_candidate
	equipment_row.mouse_filter = Control.MOUSE_FILTER_STOP if is_equipped else Control.MOUSE_FILTER_IGNORE
	# 装备横条普通边框；选中金色优先，其次候选青绿，最后使用武将牌装备条的暗金色。
	var border_color: Color = BattleUIStyle.get_color("accent") if is_selected else (BattleUIStyle.get_color("legal_target") if is_candidate else BattleUIStyle.get_color("equipment_border"))
	# 装备横条普通描边宽度；候选或选中使用2像素，静态装备使用1像素。
	var border_width: int = 2 if is_candidate or is_selected else 1
	# 装备横条基础纸色；已装备槽使用参考图浅米色牌面，空槽使用深胡桃色背景。
	var row_background_color: Color = BattleUIStyle.get_color("equipment_background") if is_equipped else BattleUIStyle.get_color("equipment_empty_background")
	# 装备横条基础边框；候选与选中仍优先使用状态色，普通槽位使用低亮度暗金边。
	var row_border_color: Color = border_color if is_candidate or is_selected else (BattleUIStyle.get_color("equipment_border") if is_equipped else BattleUIStyle.get_color("equipment_empty_border"))
	# 装备横条普通样式；内容边距归零，富文本可完整使用按钮矩形。
	var normal_style: StyleBoxFlat = _make_row_style(row_background_color, row_border_color, border_width)
	# 装备横条悬停样式；只为可交互候选轻微提亮纸张，不改变横条尺寸。
	var hover_style: StyleBoxFlat = _make_row_style(BattleUIStyle.get_color("equipment_hover_background"), row_border_color, border_width)
	equipment_row.add_theme_stylebox_override("normal", normal_style)
	equipment_row.add_theme_stylebox_override("disabled", normal_style)
	equipment_row.add_theme_stylebox_override("focus", normal_style)
	equipment_row.add_theme_stylebox_override("hover", hover_style)
	equipment_row.add_theme_stylebox_override("pressed", hover_style)
	# 装备完整说明；悬停时同时展示槽位、当前名称和卡牌规则描述，空槽只说明槽位名称。
	# 原生工具提示保持关闭；上述完整说明改由统一信息请求显示，空槽不创建卡牌信息内容。
	equipment_row.tooltip_text = ""
	# 槽位类型图标；空槽与已装备槽共用相同左侧位置，避免牌面变化时文字横向跳动。
	var slot_icon: Label = Label.new()
	slot_icon.position = Vector2.ZERO
	slot_icon.size = Vector2(slot_icon_width, equipment_row_height)
	slot_icon.anchor_bottom = 1.0
	slot_icon.offset_bottom = 0.0
	slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_icon.text = str(EQUIPMENT_SLOT_ICONS.get(slot, "◇"))
	slot_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_icon.add_theme_font_size_override("font_size", 13)
	slot_icon.add_theme_color_override("font_color", BattleUIStyle.get_color("equipment_text") if is_equipped else BattleUIStyle.get_color("equipment_empty_text"))
	equipment_row.add_child(slot_icon)
	# 装备横条富文本；花色点数保留红黑色，槽位和牌名使用深褐色并居中显示。
	var equipment_text: RichTextLabel = RichTextLabel.new()
	equipment_text.position = Vector2(slot_icon_width, 0.0)
	equipment_text.size = Vector2.ZERO
	equipment_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_text.offset_left = slot_icon_width
	equipment_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipment_text.bbcode_enabled = true
	equipment_text.fit_content = false
	equipment_text.scroll_active = false
	equipment_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	equipment_text.add_theme_font_size_override("normal_font_size", equipment_font_size)
	equipment_text.add_theme_color_override("default_color", BattleUIStyle.get_color("equipment_text") if is_equipped else BattleUIStyle.get_color("equipment_empty_text"))
	# 当前装备花色；红桃和方片使用朱红色，其余花色使用近黑色。
	var suit: String = str(equipment_card.get("suit", "none"))
	# 当前装备点数；A、J、Q、K使用标准牌面字符，无有效点数时保持空白。
	var rank: int = int(equipment_card.get("rank", 0))
	equipment_text.text = ("[center][color=%s]%s%s[/color] %s[/center]" % [_suit_color(suit).to_html(false), _suit_symbol(suit), _rank_text(rank), equipment_name]) if is_equipped else ""
	equipment_row.add_child(equipment_text)
	return equipment_row


## 在当前装备横条附近请求统一卡牌信息；内容只来自公开装备快照和静态卡牌定义。
func _on_equipment_information_entered(slot: String, equipment_card: Dictionary, card_definition: Dictionary, equipment_name: String, equipment_row: Button) -> void:
	if equipment_row == null or not is_instance_valid(equipment_row):
		return
	# 当前装备花色点数；与横条牌面保持一致并作为信息框副标题的一部分。
	var suit_rank_text: String = "%s%s" % [_suit_symbol(str(equipment_card.get("suit", "none"))), _rank_text(int(equipment_card.get("rank", 0)))]
	# 统一装备信息；槽位、花色点数、当前名称模式和规则说明共同描述实际目标牌。
	var information: Dictionary = {
		"title":"【%s】" % equipment_name,
		"subtitle":"%s｜%s" % [str(EQUIPMENT_SLOT_NAMES.get(slot, "装备")), suit_rank_text],
		"description":str(card_definition.get("description", "暂无卡牌说明。")),
	}
	information_requested.emit(information, equipment_row.get_global_rect())


## 鼠标离开已装备横条后关闭由本地装备区拥有的信息框。
func _on_equipment_information_exited() -> void:
	information_dismissed.emit()


## 装备区退出场景树时关闭活动信息，避免切换场景后残留悬浮节点。
func _exit_tree() -> void:
	information_dismissed.emit()


## 按固定槽位索引排列装备横条；空槽保留位置，宝物出现时从四槽布局切换为五槽布局。
func _layout_rows() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# 当前自适应槽高；扣除所有3像素间距后平均分配剩余高度，4槽为37像素、5槽为29像素。
	# 第一视角五槽布局使用固定27像素槽高；剩余高度由统一10像素间距填满，避免不同牌面状态改变单槽高度。
	# 当前布局按装备栏实际高度均分全部常驻槽位；148像素五等分为29.6像素，不依赖手牌栏额外留白。
	var adaptive_row_height: float = (size.y + equipment_row_overlap * float(_visible_slot_count - 1) - equipment_row_gap * float(_visible_slot_count - 1)) / float(maxi(_visible_slot_count, 1))
	# 当前槽位间可用纵向距离；参考图以固定槽高、可配置覆盖量和3像素间隔组成稳定节距。
	var row_pitch: float = adaptive_row_height - equipment_row_overlap + equipment_row_gap
	# 当前整组装备占用高度；用于在没有宝物的四槽布局中保持底部对齐。
	var total_height: float = adaptive_row_height + float(_visible_slot_count - 1) * row_pitch
	# 第一槽纵坐标；五槽常驻布局恰好填满装备栏，因此首槽贴顶、末槽贴底且中间没有空隙。
	var start_y: float = maxf(size.y - total_height, 0.0)
	# 装备横条基础宽度；参考图使用装备栏完整宽度，候选位移会向右溢出但仍留在手牌安全间距内。
	var row_width: float = maxf(size.x, 1.0)
	for slot: String in EQUIPMENT_SLOT_ORDER:
		if not _rows_by_slot.has(slot):
			continue
		# 当前装备横条；位置只由固定槽位索引决定，不受其他槽位是否装备影响。
		var equipment_row: Button = _rows_by_slot.get(slot) as Button
		# 当前固定槽位索引；宝物未装备时不会创建第五行，前四槽索引保持0至3。
		var slot_index: int = EQUIPMENT_SLOT_ORDER.find(slot)
		# 当前装备实体 UID；空槽使用-1，因此不会进入候选或选中集合。
		var equipment_uid: int = int((_equipment.get(slot, {}) as Dictionary).get("uid", -1))
		# 当前装备是否可选；可选横条向右移动第一段距离，提示玩家可直接在装备区发动。
		var shift_x: float = selectable_shift_distance if _candidate_uids.has(equipment_uid) else 0.0
		# 已选装备继续右移第二段距离；两级位置分别表达“可发动”和“已选中”。
		if _selected_uids.has(equipment_uid):
			shift_x += selected_shift_distance
		equipment_row.position = Vector2(shift_x, start_y + float(slot_index) * row_pitch)
		equipment_row.size = Vector2(row_width, adaptive_row_height)
		equipment_row.z_index = slot_index


## 控件尺寸变化时重新计算堆叠间距；窗口适配只改变表现位置，不会重建或修改装备数据。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_rows()


## 把单个装备横条平滑移动到当前交互状态的位置；时长为0或位置未变化时直接对齐目标。
func _start_row_shift_animation(slot: String, equipment_row: Button, target_shift: float) -> void:
	if equipment_row == null or not is_instance_valid(equipment_row):
		return
	if shift_animation_seconds <= 0.0 or is_equal_approx(equipment_row.position.x, target_shift):
		equipment_row.position.x = target_shift
		return
	# 当前横向位移动画；二次缓出使装备接近目标位置时自然减速，持续时间由检查器参数统一控制。
	var shift_tween: Tween = create_tween()
	shift_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	shift_tween.tween_property(equipment_row, "position:x", target_shift, shift_animation_seconds)
	_row_shift_tweens[slot] = shift_tween
	shift_tween.finished.connect(_on_row_shift_animation_finished.bind(slot, shift_tween))


## 清理已经完成的装备位移动画索引；只有映射仍指向同一补间时才删除，避免旧回调覆盖新动画。
func _on_row_shift_animation_finished(slot: String, shift_tween: Tween) -> void:
	if _row_shift_tweens.get(slot) == shift_tween:
		_row_shift_tweens.erase(slot)


## 转发可选装备横条的稳定实体 UID；禁用横条不会触发 Button.pressed。
func _on_equipment_row_pressed(card_uid: int) -> void:
	if _candidate_uids.has(card_uid):
		equipment_pressed.emit(card_uid)


## 创建装备横条纸张样式；统一清空内容边距，避免动态宽度变化挤压富文本。
func _make_row_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	# 装备横条样式；窄圆角与武将牌横条一致，叠放后仍保留清晰牌边。
	var row_style: StyleBoxFlat = BattleUIStyle.make_panel(background_color, border_color, border_width, 0)
	row_style.content_margin_left = 0.0
	row_style.content_margin_top = 0.0
	row_style.content_margin_right = 0.0
	row_style.content_margin_bottom = 0.0
	return row_style


## 将花色 ID 转换为装备横条符号；无花色装备使用空心菱形保持信息位置稳定。
func _suit_symbol(suit: String) -> String:
	return {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦", "none":"◇"}.get(suit, "◇")


## 将点数转换为牌面字符；无点数装备不显示数字，A、J、Q、K使用标准字符。
func _rank_text(rank: int) -> String:
	if rank <= 0:
		return ""
	return {1:"A", 11:"J", 12:"Q", 13:"K"}.get(rank, str(rank))


## 返回装备花色点数的前景色；红桃和方片使用朱红色，黑桃和梅花使用近黑色。
func _suit_color(suit: String) -> Color:
	return Color("b62d2d") if suit in ["heart", "diamond"] else Color("26211d")
