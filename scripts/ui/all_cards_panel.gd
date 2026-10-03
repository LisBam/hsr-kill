class_name AllCardsPanel
extends Control

## 主菜单“所有卡牌”内容页。组件只读取静态武将、游戏牌与机缘目录，负责分类浏览、全文搜索和资料展示，不创建对局状态或复制规则数据源。

## 玩家从“所有卡牌”页请求返回模式选择页时发出的信号；主菜单负责切换顶部导航和客户区。
signal close_requested()

## 正式武将牌场景；图鉴复用牌桌与选将界面的同一牌面组件，避免维护第二套武将外观。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 正式游戏牌场景；每种已登记定义只展示一张代表牌面，花色点数优先取牌堆中的首个实体配置。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 正式机缘卡场景；图鉴复用品质卡面与完整规则正文，不创建机缘选择流程。
const OPPORTUNITY_CARD_SCENE: PackedScene = preload("res://scenes/components/opportunity_card.tscn")

## 所有武将子分页的稳定标识；只用于组件内部分类，不进入设置文件或网络数据。
const CATEGORY_CHARACTERS: String = "characters"

## 所有游戏牌子分页的稳定标识；只用于组件内部分类，不替代卡牌定义 ID。
const CATEGORY_GAME_CARDS: String = "game_cards"

## 所有机缘子分页的稳定标识；只用于组件内部分类，不替代机缘稳定 ID。
const CATEGORY_OPPORTUNITIES: String = "opportunities"

## 子分页稳定顺序；左侧按钮、默认页与测试均以该顺序为准。
const CATEGORY_ORDER: Array[String] = [CATEGORY_CHARACTERS, CATEGORY_GAME_CARDS, CATEGORY_OPPORTUNITIES]

## 游戏牌类型的玩家可见名称；搜索和资料页共用该映射，未知扩展类型保留原始标识便于定位。
const CARD_TYPE_NAMES: Dictionary = {
	"basic":"基本牌",
	"trick":"锦囊牌",
	"equipment":"装备牌",
}

## 游戏牌子类型的玩家可见名称；只补充常用细分类别，不参与任何规则判断。
const CARD_SUBTYPE_NAMES: Dictionary = {
	"attack":"进攻牌",
	"response":"响应牌",
	"normal":"普通锦囊",
	"delayed":"延时锦囊",
	"weapon":"武器",
	"armor":"防具",
	"offensive_horse":"进攻坐骑",
	"offensive_mount":"进攻坐骑",
	"defensive_horse":"防御坐骑",
	"defensive_mount":"防御坐骑",
	"treasure":"宝物",
}

## 武将性别稳定 ID 到玩家可见文本的映射；未知配置统一显示“未知”。
const GENDER_NAMES: Dictionary = {
	"male":"男",
	"female":"女",
	"unknown":"未知",
}

## 专属锦囊牌的玩家可见标识；只在卡牌元数据 `exclusive` 为真时前置到分类文本，非专属牌完全不受影响。
const EXCLUSIVE_CARD_TAG_NAME: String = "专属"

## 武将牌在图鉴网格中的显示比例；默认0.72与联机形象选择一致，运行时只影响浏览密度。
@export_range(0.5, 1.0, 0.01) var character_card_scale: float = 0.72

## 游戏牌在图鉴网格中的显示比例；默认0.90兼顾牌名可读性与每行展示数量，运行时不改变正式牌面尺寸。
@export_range(0.6, 1.2, 0.01) var game_card_scale: float = 0.90

## 机缘卡在图鉴网格中的显示比例；默认0.68让完整卡池保持紧凑，牌面正文仍可点击后在资料框完整阅读。
@export_range(0.5, 1.0, 0.01) var opportunity_card_scale: float = 0.68

## 同行图鉴卡牌之间的水平间距；默认18像素避免悬停边框与相邻牌面相交，只影响客户端布局。
@export_range(0.0, 48.0, 1.0) var horizontal_gap: float = 18.0

## 相邻图鉴行之间的垂直间距；默认18像素保留牌面阴影和点击边界，只影响客户端布局。
@export_range(0.0, 48.0, 1.0) var vertical_gap: float = 18.0

## 右侧浏览区叠加主题面板色的透明度；默认0.18与主菜单其他内容页一致，只影响视觉明暗。
@export_range(0.0, 1.0, 0.01) var detail_shade_opacity: float = 0.18

## 卡牌资料遮罩的不透明度；默认0.90使完整说明成为当前视觉焦点，运行时只阻断图鉴底层输入。
@export_range(0.0, 1.0, 0.01) var information_backdrop_opacity: float = 0.90

## 图鉴及资料区纵向滚动条宽度；默认12像素与主菜单模式选择滑条一致，运行时只影响浏览控件宽度。
@export_range(8.0, 24.0, 1.0) var scroll_bar_width: float = 12.0

## 图鉴牌面与右侧滚动条之间的安全留白；默认28像素让最右列主动左移并避免被拖条遮挡，运行时只影响网格布局。
@export_range(0.0, 64.0, 1.0) var gallery_scroll_bar_clearance: float = 28.0

## 武将详情左侧正式武将牌的缩放倍率；默认0.78兼顾牌面辨识度与右侧技能说明宽度，运行时只影响详情布局。
@export_range(0.5, 1.0, 0.01) var information_character_card_scale: float = 0.78

## 武将详情右侧技能条目之间的垂直间距；默认12像素明确区分相邻技能，运行时只影响文字排版。
@export_range(4, 28, 1) var information_skill_separation: int = 12

## 武将详情右侧技能名称颜色；默认使用稳定暖黄色确保在两套主题中都与说明正文形成清晰层级，运行时只影响文字表现。
@export var information_skill_name_color: Color = Color("f4cf66")

## 图鉴外框；左侧三个子分页与右侧搜索网格共同位于此容器内。
@onready var _frame: PanelContainer = %AllCardsFrame

## 图鉴左侧子分页列表；宽度与模式选择和联机设置的左侧列表保持一致。
@onready var _side_list: PanelContainer = %AllCardsSideList

## 图鉴左右分栏容器；网格宽度从该稳定客户区扣除侧栏与间距计算，避免滚动内容反向撑大页面。
@onready var _content: HBoxContainer = _side_list.get_parent() as HBoxContainer

## 图鉴右侧内容面板；承载搜索栏、结果数量、滚动网格和空结果提示。
@onready var _detail_panel: PanelContainer = %AllCardsDetailPanel

## 图鉴右侧基础底色；使用当前主题桌面色形成与主菜单预览一致的内容层级。
@onready var _detail_surface: ColorRect = %AllCardsDetailSurface

## 图鉴右侧半透明遮罩；只改善牌面与搜索栏对比度。
@onready var _detail_shade: ColorRect = %AllCardsDetailShade

## 所有武将子分页按钮；切换后从 GameDatabase.characters 重建当前列表。
@onready var _characters_tab_button: Button = %AllCharactersTabButton

## 所有游戏牌子分页按钮；切换后从 GameDatabase.cards 重建当前列表。
@onready var _game_cards_tab_button: Button = %AllGameCardsTabButton

## 所有机缘子分页按钮；切换后从 OpportunityCatalog 读取完整目录。
@onready var _opportunities_tab_button: Button = %AllOpportunitiesTabButton

## 所有武将子分页左侧选中指示线；仅在当前分类为武将时显示。
@onready var _characters_indicator: ColorRect = %AllCharactersTabIndicator

## 所有游戏牌子分页左侧选中指示线；仅在当前分类为游戏牌时显示。
@onready var _game_cards_indicator: ColorRect = %AllGameCardsTabIndicator

## 所有机缘子分页左侧选中指示线；仅在当前分类为机缘时显示。
@onready var _opportunities_indicator: ColorRect = %AllOpportunitiesTabIndicator

## 当前分类搜索输入框；每个子分页独立记忆本次打开期间的关键词。
@onready var _search_input: LineEdit = %AllCardsSearchInput

## 当前总数与筛选结果数量标签；搜索变化后立即刷新，不等待重新打开页面。
@onready var _result_count_label: Label = %AllCardsResultCountLabel

## 卡牌网格纵向滚动容器；内容超过可见高度时允许浏览全部匹配结果。
@onready var _grid_scroll: ScrollContainer = %AllCardsGridScroll

## 动态卡牌槽承载区；脚本只创建正式牌面节点并计算网格位置。
@onready var _grid_content: Control = %AllCardsGridContent

## 搜索无匹配结果时显示的占位说明；为空时替代滚动内容但不改变搜索词。
@onready var _empty_label: Label = %AllCardsEmptyLabel

## 完整资料模态遮罩；点击空白处或按 Esc 会关闭当前资料，不离开图鉴页。
@onready var _information_backdrop: ColorRect = %AllCardsInfoBackdrop

## 完整资料正文面板；使用主题内嵌面板样式并阻止点击穿透到遮罩。
@onready var _information_panel: PanelContainer = %AllCardsInfoPanel

## 完整资料标题；显示武将名、当前名称模式下的游戏牌名或机缘品质名称。
@onready var _information_title: Label = %AllCardsInfoTitle

## 完整资料副标题；显示势力体力、双牌名类别或机缘品质等摘要。
@onready var _information_subtitle: Label = %AllCardsInfoSubtitle

## 完整资料正文；武将技能、卡牌规则或机缘技能说明均在此完整换行显示。
@onready var _information_description: Label = %AllCardsInfoDescription

## 通用卡牌资料滚动区；游戏牌与机缘继续使用单列正文，武将详情打开时由双栏主体替代。
@onready var _information_scroll: ScrollContainer = %AllCardsInfoScroll

## 武将详情双栏主体；左侧承载正式武将牌，右侧承载黄色技能名与规则正文。
@onready var _information_character_body: HBoxContainer = %AllCardsInfoCharacterBody

## 武将详情左侧牌面区域；按实际区域尺寸把缩放后的正式武将牌保持居中。
@onready var _information_character_card_area: Control = %AllCardsInfoCharacterCardArea

## 武将详情右侧技能滚动区；技能较多时独立纵向浏览，不移动左侧武将牌。
@onready var _information_character_skill_scroll: ScrollContainer = %AllCardsInfoCharacterSkillScroll

## 武将详情右侧技能列表；每个技能使用独立名称标签与说明标签，允许分别配置颜色。
@onready var _information_character_skill_list: VBoxContainer = %AllCardsInfoCharacterSkillList

## 完整资料关闭按钮；关闭后把焦点归还搜索框或当前平台的安全子分页按钮。
@onready var _information_close_button: Button = %AllCardsInfoCloseButton

## 当前选中的子分页稳定标识；默认打开所有武将。
var _current_category: String = CATEGORY_CHARACTERS

## 当前分类动态条目；每项保存稳定 ID、搜索文本、显示槽与缩放后尺寸，不持有任何规则运行时对象。
var _entries: Array[Dictionary] = []

## 当前动态正式牌面节点集合；主题切换时只重绘已有节点，不重建静态目录。
var _content_views: Array[Node] = []

## 三个子分页各自的搜索词；切换分类时恢复此前输入，关闭整个页面后由 open_panel 统一清空。
var _search_queries_by_category: Dictionary = {
	CATEGORY_CHARACTERS:"",
	CATEGORY_GAME_CARDS:"",
	CATEGORY_OPPORTUNITIES:"",
}

## 游戏牌稳定 ID 到代表花色点数的缓存；每次重建游戏牌页时从全部牌堆首个命中项生成。
var _representative_card_by_definition_id: Dictionary = {}

## 网格重排是否已经登记到空闲帧；防止 ScrollContainer 连续尺寸变化创建重复布局任务。
var _layout_refresh_queued: bool = false

## 武将详情左侧当前创建的正式武将牌；关闭详情或切换到其他卡牌类别时释放，不持有规则运行时对象。
var _information_character_view: PlayerTargetView

## 武将详情右侧当前创建的技能名称标签；主题刷新时统一恢复指定黄色。
var _information_skill_name_labels: Array[Label] = []

## 武将详情右侧当前创建的技能说明视图；局外轮回技固定以初始①高亮并随主题重绘。
var _information_skill_description_labels: Array[SkillDescriptionView] = []


## 初始化分类按钮、搜索、资料模态与全局表现信号；组件默认隐藏且不读取任何对局状态。
func _ready() -> void:
	visible = false
	_characters_tab_button.pressed.connect(_select_category.bind(CATEGORY_CHARACTERS))
	_game_cards_tab_button.pressed.connect(_select_category.bind(CATEGORY_GAME_CARDS))
	_opportunities_tab_button.pressed.connect(_select_category.bind(CATEGORY_OPPORTUNITIES))
	_search_input.text_changed.connect(_on_search_text_changed)
	_grid_scroll.resized.connect(_queue_filter_and_layout)
	_information_close_button.pressed.connect(_close_information)
	_information_backdrop.gui_input.connect(_on_information_backdrop_gui_input)
	_information_character_card_area.resized.connect(_center_information_character_card)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	GameSettings.card_name_mode_changed.connect(_on_card_name_mode_changed)
	refresh_ui_style()


## 打开“所有卡牌”内容页；重新读取三类静态目录，使开发期数据库重载后的新增内容立即进入图鉴。
func open_panel() -> void:
	visible = true
	move_to_front()
	_close_information(false)
	for category_id: String in CATEGORY_ORDER:
		_search_queries_by_category[category_id] = ""
	_current_category = CATEGORY_CHARACTERS
	_search_input.set_text("")
	_rebuild_current_entries()
	_refresh_category_state()
	refresh_ui_style()
	_queue_filter_and_layout()
	call_deferred("_focus_primary_control")


## 按当前活动主题刷新内容页、分类按钮、搜索框、滚动条与已有正式牌面；不改变分类、关键词或资料内容。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("rail"), BattleUIStyle.get_color("border"), 2, 8))
	_side_list.add_theme_stylebox_override("panel", _make_flat_inner_panel(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border")))
	_detail_panel.add_theme_stylebox_override("panel", _make_flat_inner_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border")))
	_detail_surface.color = BattleUIStyle.get_color("table_surface")
	_detail_shade.color = Color(BattleUIStyle.get_color("panel"), detail_shade_opacity)
	_information_backdrop.color = Color(BattleUIStyle.get_color("shade"), information_backdrop_opacity)
	_information_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	(%AllCardsSideListTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	for category_label: Label in [
		%AllCharactersTabName as Label,
		%AllGameCardsTabName as Label,
		%AllOpportunitiesTabName as Label,
	]:
		category_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	for category_hint: Label in [
		%AllCharactersTabHint as Label,
		%AllGameCardsTabHint as Label,
		%AllOpportunitiesTabHint as Label,
	]:
		category_hint.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	for category_indicator: ColorRect in [_characters_indicator, _game_cards_indicator, _opportunities_indicator]:
		category_indicator.color = BattleUIStyle.get_color("accent")
	_refresh_category_button_styles()
	_apply_line_edit_style(_search_input)
	_result_count_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_empty_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_information_title.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_information_subtitle.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
	_information_description.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_information_character_skill_list.add_theme_constant_override("separation", information_skill_separation)
	for skill_name_label: Label in _information_skill_name_labels:
		if skill_name_label != null and is_instance_valid(skill_name_label):
			skill_name_label.add_theme_color_override("font_color", information_skill_name_color)
	for skill_description_label: SkillDescriptionView in _information_skill_description_labels:
		if skill_description_label != null and is_instance_valid(skill_description_label):
			skill_description_label.refresh_ui_style()
	BattleUIStyle.apply_interaction_button(_information_close_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), false)
	_apply_scroll_bar_style(_grid_scroll.get_v_scroll_bar())
	_apply_scroll_bar_style(_information_scroll.get_v_scroll_bar())
	_apply_scroll_bar_style(_information_character_skill_scroll.get_v_scroll_bar())
	for view: Node in _content_views:
		if view != null and is_instance_valid(view) and view.has_method("refresh_ui_style"):
			view.call("refresh_ui_style")
	if _information_character_view != null and is_instance_valid(_information_character_view):
		_information_character_view.refresh_ui_style()


## 切换到指定子分页；每页从自身权威静态目录重建，并恢复该页在本次打开期间保存的搜索词。
func _select_category(category_id: String) -> void:
	if not CATEGORY_ORDER.has(category_id):
		return
	if _current_category == category_id and not _entries.is_empty():
		_refresh_category_state()
		return
	_search_queries_by_category[_current_category] = _search_input.text
	_current_category = category_id
	_search_input.set_text(str(_search_queries_by_category.get(category_id, "")))
	_rebuild_current_entries()
	_refresh_category_state()
	_grid_scroll.scroll_vertical = 0
	_queue_filter_and_layout()


## 同步三个子分页互斥按下态、指示线与当前搜索提示；分类只影响展示，不修改数据库。
func _refresh_category_state() -> void:
	_characters_tab_button.set_pressed_no_signal(_current_category == CATEGORY_CHARACTERS)
	_game_cards_tab_button.set_pressed_no_signal(_current_category == CATEGORY_GAME_CARDS)
	_opportunities_tab_button.set_pressed_no_signal(_current_category == CATEGORY_OPPORTUNITIES)
	_characters_indicator.visible = _current_category == CATEGORY_CHARACTERS
	_game_cards_indicator.visible = _current_category == CATEGORY_GAME_CARDS
	_opportunities_indicator.visible = _current_category == CATEGORY_OPPORTUNITIES
	_search_input.placeholder_text = {
		CATEGORY_CHARACTERS:"搜索武将名称、势力或技能",
		CATEGORY_GAME_CARDS:"搜索牌名、类别或规则说明",
		CATEGORY_OPPORTUNITIES:"搜索品质、机缘正文或技能",
	}.get(_current_category, "搜索卡牌")
	_refresh_category_button_styles()


## 依据当前分类清理并重建正式牌面节点；内容只取静态元数据深拷贝，不缓存规则定义对象。
func _rebuild_current_entries() -> void:
	_clear_entries()
	if _current_category == CATEGORY_CHARACTERS:
		_build_character_entries()
	elif _current_category == CATEGORY_GAME_CARDS:
		_build_game_card_entries()
	elif _current_category == CATEGORY_OPPORTUNITIES:
		_build_opportunity_entries()
	_queue_filter_and_layout()


## 从全部已登记武将建立正式武将牌条目；按中文名排序，重名时再按稳定 ID 保证顺序可复现。
## 补充：当前先按需求指定的势力顺序分组，再在同一势力内应用名称与稳定 ID 排序。
func _build_character_entries() -> void:
	# 全部武将稳定 ID；复制后排序，避免依赖数据库字典遍历顺序。
	var character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		character_ids.append(str(character_id_variant))
	character_ids.sort_custom(_sort_character_ids)
	for character_index: int in range(character_ids.size()):
		# 当前武将稳定 ID；点击与资料查询只使用该值。
		var character_id: String = character_ids[character_index]
		# 当前武将静态定义；牌面与搜索均读取同一份数据库副本。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		# 当前武将势力定义；只用于牌面徽记、搜索与资料摘要。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
		# 当前武将图鉴快照；只含牌面需要的公开字段，不创建 PlayerState。
		var character_snapshot: Dictionary = {
			"player_id":-(character_index + 1),
			"display_name":"武将图鉴",
			"character_id":character_id,
			"character_revealed":true,
			"identity":"hidden",
			"hp":int(character_definition.get("max_hp", 0)),
			"max_hp":int(character_definition.get("max_hp", 0)),
			"alive":true,
			"chained":false,
			"hand_count":0,
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage_count":0,
		}
		# 当前正式武将牌；外层缩放根保证后续组件动画不会覆盖图鉴比例。
		var character_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
		character_view.configure_snapshot(character_snapshot, character_definition, false, faction_definition)
		character_view.set_match_overlays_visible(false)
		character_view.pressed.connect(_open_information.bind(CATEGORY_CHARACTERS, character_id))
		# 当前武将缩放后尺寸；网格槽始终以此固定尺寸参与布局。
		var scaled_size: Vector2 = character_view.card_size * character_card_scale
		_add_entry_slot(character_id, _build_character_search_text(character_id, character_definition, faction_definition), character_view, scaled_size, character_card_scale)


## 从全部已登记游戏牌定义建立唯一牌面条目；同一牌名的不同逻辑定义仍按各自稳定 ID 分别展示。
## 补充：当前先按基本、锦囊、装备及其内部指定子类顺序分组，再以名称和稳定 ID 处理同组顺序。
func _build_game_card_entries() -> void:
	_build_representative_card_cache()
	# 全部游戏牌稳定 ID；按当前名称模式的玩家可见牌名排序。
	var card_ids: Array[String] = []
	for card_id_variant: Variant in GameDatabase.cards.keys():
		card_ids.append(str(card_id_variant))
	card_ids.sort_custom(_sort_game_card_ids)
	for card_index: int in range(card_ids.size()):
		# 当前游戏牌稳定 ID；代表实体与完整资料均由该 ID 定位。
		var card_id: String = card_ids[card_index]
		# 当前游戏牌静态定义；来自数据库深拷贝，不写回任何展示字段。
		var card_definition: Dictionary = GameDatabase.get_card(card_id)
		# 当前代表实体配置；优先使用牌堆首个花色点数，扩展牌未入牌堆时显示无花色点数的定义牌。
		var representative_card: Dictionary = (_representative_card_by_definition_id.get(card_id, {}) as Dictionary).duplicate(true)
		representative_card["uid"] = -(card_index + 1)
		representative_card["definition_id"] = card_id
		# 当前正式游戏牌；图鉴启用点击与悬停，但不绑定手牌排序分区或对局动作。
		var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		card_view.configure(representative_card, card_definition, false, true, false)
		card_view.pressed.connect(_open_information.bind(CATEGORY_GAME_CARDS, card_id))
		# 当前游戏牌缩放后尺寸；复用 CardView 公开尺寸接口避免读取场景子节点。
		var scaled_size: Vector2 = card_view.get_card_size() * game_card_scale
		_add_entry_slot(card_id, _build_game_card_search_text(card_id, card_definition), card_view, scaled_size, game_card_scale)


## 从完整机缘目录建立品质牌面条目；包括不参与随机三选一的灰色关卡机缘。
func _build_opportunity_entries() -> void:
	# 全部机缘定义；公开接口返回深拷贝，组件可安全排序而不改写静态目录。
	var opportunity_definitions: Array[Dictionary] = OpportunityCatalog.get_all_cards()
	for opportunity_definition: Dictionary in opportunity_definitions:
		# 当前机缘稳定 ID；点击资料与搜索结果均保持该唯一来源。
		var opportunity_id: String = str(opportunity_definition.get("id", ""))
		# 当前正式机缘牌；interactive 只启用图鉴点击和悬停，不会提交 choose_opportunity。
		var opportunity_view: OpportunityCardView = OPPORTUNITY_CARD_SCENE.instantiate() as OpportunityCardView
		# 当前机缘卡缩放后尺寸；外层缩放根保留 OpportunityCardView 自身1.06倍悬停动画。
		var scaled_size: Vector2 = opportunity_view.card_size * opportunity_card_scale
		_add_entry_slot(opportunity_id, _build_opportunity_search_text(opportunity_definition), opportunity_view, scaled_size, opportunity_card_scale)
		opportunity_view.configure(opportunity_definition, true)
		opportunity_view.card_selected.connect(_on_opportunity_card_selected)


## 为一张正式牌面创建固定尺寸槽和独立缩放根；网格只移动槽，不改写牌面组件自身位置。
func _add_entry_slot(entry_id: String, search_text: String, view: Node, scaled_size: Vector2, view_scale: float) -> void:
	# 当前网格槽；Control 提供滚动内容尺寸并忽略鼠标，让内部正式牌面独占输入。
	var slot: Control = Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size = scaled_size
	slot.custom_minimum_size = scaled_size
	_grid_content.add_child(slot)
	# 当前牌面缩放根；组件悬停动画只改变自身局部缩放，不覆盖图鉴的基础显示比例。
	var scale_root: Node2D = Node2D.new()
	scale_root.scale = Vector2.ONE * view_scale
	slot.add_child(scale_root)
	scale_root.add_child(view)
	_entries.append({
		"id":entry_id,
		"search_text":_normalize_search_text(search_text),
		"slot":slot,
		"size":scaled_size,
	})
	_content_views.append(view)


## 搜索文本变化时保存当前子分页关键词并重排可见条目；匹配使用不区分英文大小写的包含关系。
func _on_search_text_changed(search_text: String) -> void:
	_search_queries_by_category[_current_category] = search_text
	_grid_scroll.scroll_vertical = 0
	_queue_filter_and_layout()


## 把筛选与布局登记到空闲帧；等待容器完成本帧尺寸计算后再求列数，避免紧凑窗口首次打开错位。
func _queue_filter_and_layout() -> void:
	if not is_node_ready() or _layout_refresh_queued:
		return
	_layout_refresh_queued = true
	call_deferred("_apply_filter_and_layout")


## 按当前关键词过滤条目并计算自适应列数；只修改槽的可见性与坐标，不重建卡牌定义或规则对象。
func _apply_filter_and_layout() -> void:
	_layout_refresh_queued = false
	if not is_node_ready():
		return
	# 当前标准化搜索词；中文保持原文，英文转小写并去除首尾空白。
	var normalized_query: String = _normalize_search_text(_search_input.text)
	# 当前可见条目；沿用分类排序，搜索不会改变稳定浏览顺序。
	var visible_entries: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		# 当前条目是否匹配；空搜索词显示全部内容。
		var matches_query: bool = normalized_query.is_empty() or str(entry.get("search_text", "")).contains(normalized_query)
		# 当前条目固定槽；隐藏后不参与网格行数和滚动高度。
		var slot: Control = entry.get("slot") as Control
		if slot != null:
			slot.visible = matches_query
		if matches_query:
			visible_entries.append(entry)
	_empty_label.visible = visible_entries.is_empty()
	_grid_scroll.visible = not visible_entries.is_empty()
	_result_count_label.text = "共 %d 项" % _entries.size() if normalized_query.is_empty() else "显示 %d / %d 项" % [visible_entries.size(), _entries.size()]
	if visible_entries.is_empty():
		_grid_content.custom_minimum_size = Vector2(1.0, 1.0)
		return
	# 当前分类统一牌面尺寸；同一子分页所有正式场景使用一致外部规格。
	var item_size: Vector2 = visible_entries[0].get("size", Vector2.ZERO)
	# 当前可用网格宽度；最少保留一张牌宽度，窄窗口会通过单列继续完整浏览。
	var available_width: float = maxf(
		_content.size.x - _side_list.size.x - _content.get_theme_constant("separation") - 44.0 - gallery_scroll_bar_clearance,
		item_size.x
	)
	# 当前列数；以缩放后牌宽和导出间距动态计算，不硬编码桌面或移动端列数。
	var column_count: int = maxi(int(floor((available_width + horizontal_gap) / (item_size.x + horizontal_gap))), 1)
	# 当前实际使用列数；结果少于一行时按真实数量居中。
	var used_column_count: int = mini(column_count, visible_entries.size())
	# 当前网格实际宽度；用于在右侧内容区水平居中整组牌面。
	var used_width: float = used_column_count * item_size.x + maxi(used_column_count - 1, 0) * horizontal_gap
	# 当前网格左侧起点；保证单行不足列数时仍保持居中。
	var start_x: float = maxf((available_width - used_width) * 0.5, 0.0)
	for visible_index: int in range(visible_entries.size()):
		# 当前可见条目槽；位置按筛选后的连续索引计算，不给隐藏条目保留空洞。
		var visible_slot: Control = visible_entries[visible_index].get("slot") as Control
		# 当前条目所在列；每行从左到右填满后换行。
		var column_index: int = visible_index % column_count
		# 当前条目所在行；从上到下递增。
		var row_index: int = int(visible_index / float(column_count))
		visible_slot.position = Vector2(
			start_x + column_index * (item_size.x + horizontal_gap),
			row_index * (item_size.y + vertical_gap)
		)
	# 当前总行数；向上取整保证不完整末行仍占用完整牌面高度。
	var row_count: int = ceili(float(visible_entries.size()) / float(column_count))
	_grid_content.custom_minimum_size = Vector2(
		1.0,
		row_count * item_size.y + maxi(row_count - 1, 0) * vertical_gap
	)


## 打开指定条目的完整资料模态；标题、副标题与正文始终从当前静态目录重新解析，避免保存第二份内容快照。
func _open_information(category_id: String, entry_id: String) -> void:
	# 当前资料内容；固定包含标题、副标题和正文三个玩家可见字段。
	var information: Dictionary = {}
	if category_id == CATEGORY_CHARACTERS:
		information = _resolve_character_information(entry_id)
	elif category_id == CATEGORY_GAME_CARDS:
		information = _resolve_game_card_information(entry_id)
	elif category_id == CATEGORY_OPPORTUNITIES:
		information = _resolve_opportunity_information(entry_id)
	if information.is_empty():
		return
	_information_title.text = str(information.get("title", "卡牌资料"))
	_information_subtitle.text = str(information.get("subtitle", ""))
	_information_subtitle.visible = not _information_subtitle.text.is_empty()
	_information_description.text = str(information.get("description", "暂无说明。"))
	if category_id == CATEGORY_CHARACTERS:
		_information_scroll.visible = false
		_information_character_body.visible = true
		_show_character_information(entry_id)
	else:
		_clear_information_character_content()
		_information_character_body.visible = false
		_information_scroll.visible = true
	_information_backdrop.visible = true
	_information_backdrop.move_to_front()
	_information_close_button.grab_focus()


## 响应机缘牌点击信号；稳定 ID 由牌面传入，组件只打开资料而不提交任何权威选择动作。
func _on_opportunity_card_selected(card_id: String) -> void:
	_open_information(CATEGORY_OPPORTUNITIES, card_id)


## 关闭当前完整资料；可选择恢复搜索焦点，页面整体关闭时不会抢占新的顶部导航焦点。
func _close_information(restore_focus: bool = true) -> void:
	if _information_backdrop == null:
		return
	_information_backdrop.visible = false
	_clear_information_character_content()
	if restore_focus:
		call_deferred("_focus_primary_control")


## 点击完整资料面板外的遮罩时关闭资料；仅响应鼠标左键按下，滚轮与右键不会误关闭。
func _on_information_backdrop_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	# 当前鼠标事件；按下阶段关闭一次，释放阶段不重复处理。
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_close_information()
		accept_event()


## 生成武将完整资料；固有技能按定义顺序展示，技能原文中的牌名按当前全局名称模式解析。
func _resolve_character_information(character_id: String) -> Dictionary:
	# 当前武将定义；空结果表示开发期内容已移除，资料框不打开。
	var character_definition: Dictionary = GameDatabase.get_character(character_id)
	if character_definition.is_empty():
		return {}
	# 当前势力定义；缺失时使用武将配置的原始势力标识作为维护回退。
	var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
	# 当前技能说明分段；每项保持技能名与唯一原文，不改写需求钦定描述。
	var skill_sections: Array[String] = []
	for skill_id_variant: Variant in character_definition.get("skills", []) as Array:
		# 当前技能稳定 ID；只用于查询静态技能定义。
		var skill_id: String = str(skill_id_variant)
		# 当前技能定义；缺失时保留明确占位，避免武将资料静默丢项。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能名称；不存在元数据时以稳定 ID 回退，便于维护定位。
		var skill_name: String = str(skill_definition.get("name", skill_id))
		# 当前技能唯一说明；完整书名号牌名通过数据库统一解析。
		var skill_description: String = GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。")))
		skill_sections.append("【%s】\n%s" % [skill_name, skill_description])
	# 当前武将技能正文；无技能武将显示明确说明。
	var description: String = "\n\n".join(skill_sections) if not skill_sections.is_empty() else "无技能"
	return {
		"title":str(character_definition.get("display_name", GameDatabase.resolve_character_name(character_id))),
		"subtitle":"势力：%s｜性别：%s｜体力上限：%d" % [
			str(faction_definition.get("display_name", character_definition.get("faction", "未知势力"))),
			_resolve_gender_name(str(character_definition.get("gender", "unknown"))),
			int(character_definition.get("max_hp", 0)),
		],
		"description":description,
	}


## 构建武将详情双栏内容；左侧复用正式武将牌，右侧按定义顺序创建独立的黄色技能名与规则说明。
func _show_character_information(character_id: String) -> void:
	_clear_information_character_content()
	# 当前武将静态定义；为空时详情保留标题摘要但不创建无来源牌面。
	var character_definition: Dictionary = GameDatabase.get_character(character_id)
	if character_definition.is_empty():
		return
	# 当前武将势力定义；只用于左侧正式牌面的徽记名称与颜色。
	var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
	# 武将详情只读牌面快照；使用负玩家 ID 且不进入任何对局状态。
	var character_snapshot: Dictionary = {
		"player_id":-1,
		"display_name":"武将详情",
		"character_id":character_id,
		"character_revealed":true,
		"identity":"hidden",
		"hp":int(character_definition.get("max_hp", 0)),
		"max_hp":int(character_definition.get("max_hp", 0)),
		"alive":true,
		"chained":false,
		"hand_count":0,
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage_count":0,
	}
	_information_character_view = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	_information_character_card_area.add_child(_information_character_view)
	_information_character_view.scale = Vector2.ONE * information_character_card_scale
	_information_character_view.configure_snapshot(character_snapshot, character_definition, false, faction_definition)
	_information_character_view.set_match_overlays_visible(false)
	_information_character_view.set_interactable(false)
	for skill_id_variant: Variant in character_definition.get("skills", []) as Array:
		# 当前技能稳定 ID；只查询静态定义，不安装技能实例。
		var skill_id: String = str(skill_id_variant)
		# 当前技能静态定义；缺失时名称回退稳定 ID、正文显示明确维护提示。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能条目容器；名称与说明各占一行以便应用不同颜色。
		var skill_entry: VBoxContainer = VBoxContainer.new()
		skill_entry.add_theme_constant_override("separation", 4)
		_information_character_skill_list.add_child(skill_entry)
		# 当前技能名称标签；固定暖黄色并保持技能定义中的原始名称。
		var skill_name_label: Label = Label.new()
		skill_name_label.text = "【%s】" % str(skill_definition.get("name", skill_id))
		skill_name_label.add_theme_font_size_override("font_size", 18)
		skill_name_label.add_theme_color_override("font_color", information_skill_name_color)
		skill_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_entry.add_child(skill_name_label)
		_information_skill_name_labels.append(skill_name_label)
		# 当前技能说明标签；解析全局卡牌名称模式后自动换行，并使用主题次级文字色。
		var skill_description_label: SkillDescriptionView = SkillDescriptionView.new()
		# 局外静态武将资料没有运行时状态；轮回数初始为1且当前轮回节固定从①开始。
		skill_description_label.configure_description(GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。"))), bool(skill_definition.get("reincarnation", false)), 0)
		skill_description_label.add_theme_font_size_override("normal_font_size", 14)
		skill_description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_entry.add_child(skill_description_label)
		_information_skill_description_labels.append(skill_description_label)
	if _information_skill_name_labels.is_empty():
		# 无技能占位标签；明确说明静态定义没有技能，不伪造黄色技能标题。
		var empty_skill_label: Label = Label.new()
		empty_skill_label.text = "该武将牌没有固有技能"
		empty_skill_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		_information_character_skill_list.add_child(empty_skill_label)
	_information_character_skill_scroll.scroll_vertical = 0
	call_deferred("_center_information_character_card")


## 根据左侧可用区域居中武将详情牌面；窗口或面板尺寸改变时只更新显示坐标。
func _center_information_character_card() -> void:
	if _information_character_view == null or not is_instance_valid(_information_character_view):
		return
	# 详情武将牌缩放后尺寸；公开 card_size 与当前检查器倍率共同决定。
	var scaled_card_size: Vector2 = _information_character_view.card_size * information_character_card_scale
	_information_character_view.position = Vector2(
		maxf((_information_character_card_area.size.x - scaled_card_size.x) * 0.5, 0.0),
		maxf((_information_character_card_area.size.y - scaled_card_size.y) * 0.5, 0.0)
	)


## 清理武将详情动态牌面与技能条目；游戏牌、机缘牌或关闭详情后不残留隐藏节点和旧主题引用。
func _clear_information_character_content() -> void:
	_information_skill_name_labels.clear()
	_information_skill_description_labels.clear()
	if _information_character_card_area != null:
		for child: Node in _information_character_card_area.get_children():
			_information_character_card_area.remove_child(child)
			child.queue_free()
	if _information_character_skill_list != null:
		for child: Node in _information_character_skill_list.get_children():
			_information_character_skill_list.remove_child(child)
			child.queue_free()
	_information_character_view = null


## 生成游戏牌完整资料；同时显示双名称和细分类别，规则说明保持卡牌文件中的长期文本。
func _resolve_game_card_information(card_id: String) -> Dictionary:
	# 当前游戏牌定义；空结果表示内容已移除，不显示过期资料。
	var card_definition: Dictionary = GameDatabase.get_card(card_id)
	if card_definition.is_empty():
		return {}
	# 当前原版牌名；缺失时回退稳定 ID，避免资料标题为空。
	var original_name: String = str(card_definition.get("original_name", card_id))
	# 当前崩铁杀牌名；缺失时回退原版牌名。
	var custom_name: String = str(card_definition.get("custom_name", original_name))
	# 当前玩家可见牌名；严格复用全局名称模式解析入口。
	var display_name: String = GameSettings.resolve_card_display_name(card_definition)
	# 当前牌型文字；类型与子类型由静态元数据映射为玩家可见摘要。
	var type_name: String = _resolve_card_type_name(card_definition)
	return {
		"title":"【%s】" % display_name,
		"subtitle":"三国杀：%s｜崩铁杀：%s｜%s" % [original_name, custom_name, type_name],
		"description":GameDatabase.resolve_card_names_in_text(str(card_definition.get("description", "暂无卡牌说明。"))),
	}


## 生成机缘完整资料；品质与原始正文始终显示，授予技能时在后方补充该技能唯一说明。
func _resolve_opportunity_information(card_id: String) -> Dictionary:
	# 当前机缘定义；空结果表示目录中不存在该稳定 ID。
	var opportunity_definition: Dictionary = OpportunityCatalog.get_card(card_id)
	if opportunity_definition.is_empty():
		return {}
	# 当前机缘品质 ID；用于取得玩家可见品质名。
	var quality_id: String = str(opportunity_definition.get("quality", ""))
	# 当前机缘原始规则正文；禁止改写文字或标点。
	var description: String = GameDatabase.resolve_card_names_in_text(str(opportunity_definition.get("description", "暂无机缘说明。")))
	# 当前机缘授予技能 ID；非技能机缘保持空字符串。
	var skill_id: String = str(opportunity_definition.get("skill_id", ""))
	if not skill_id.is_empty():
		# 当前授予技能定义；资料页补充名称和唯一描述，便于完整查看机缘效果来源。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		if not skill_definition.is_empty():
			description += "\n\n获得技能：【%s】\n%s" % [
				str(skill_definition.get("name", skill_id)),
				GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。"))),
			]
	return {
		"title":"%s · 机缘" % OpportunityCatalog.get_quality_name(quality_id),
		"subtitle":"机缘卡｜点击遮罩空白处或关闭按钮返回",
		"description":description,
	}


## 构造武将搜索文本；覆盖名称、稳定 ID、势力、性别、体力以及全部固有技能名称与说明。
func _build_character_search_text(character_id: String, character_definition: Dictionary, faction_definition: Dictionary) -> String:
	# 当前武将搜索字段；集中拼接后进行一次标准化，避免逐次键入重复查询数据库。
	var search_parts: Array[String] = [
		character_id,
		str(character_definition.get("display_name", "")),
		str(character_definition.get("faction", "")),
		str(faction_definition.get("display_name", "")),
		str(faction_definition.get("short_name", "")),
		_resolve_gender_name(str(character_definition.get("gender", "unknown"))),
		str(character_definition.get("max_hp", 0)),
	]
	for skill_id_variant: Variant in character_definition.get("skills", []) as Array:
		# 当前固有技能 ID；允许开发者按稳定标识搜索，也允许玩家按名称和正文搜索。
		var skill_id: String = str(skill_id_variant)
		# 当前固有技能定义；缺失定义只保留稳定 ID。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		search_parts.append(skill_id)
		search_parts.append(str(skill_definition.get("name", "")))
		search_parts.append(GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", ""))))
	return "\n".join(search_parts)


## 构造游戏牌搜索文本；覆盖稳定 ID、双名称、规则名、类型、子类型和完整规则说明。
func _build_game_card_search_text(card_id: String, card_definition: Dictionary) -> String:
	# 当前游戏牌搜索字段；双名称始终同时存在，因此切换显示模式后仍可用任一名称检索。
	var search_parts: Array[String] = [
		card_id,
		str(card_definition.get("original_name", "")),
		str(card_definition.get("custom_name", "")),
		str(card_definition.get("rule_name", "")),
		str(card_definition.get("type", "")),
		str(card_definition.get("subtype", "")),
		_resolve_card_type_name(card_definition),
		GameDatabase.resolve_card_names_in_text(str(card_definition.get("description", ""))),
	]
	return "\n".join(search_parts)


## 构造机缘搜索文本；覆盖稳定 ID、品质、规则正文及可获得技能的名称和唯一说明。
func _build_opportunity_search_text(opportunity_definition: Dictionary) -> String:
	# 当前机缘品质 ID；同时加入稳定 ID 与中文品质名称。
	var quality_id: String = str(opportunity_definition.get("quality", ""))
	# 当前机缘授予技能 ID；普通机缘为空且不会追加无关技能字段。
	var skill_id: String = str(opportunity_definition.get("skill_id", ""))
	# 当前机缘搜索字段；description 保持目录原文，只在显示与检索时解析动态牌名。
	var search_parts: Array[String] = [
		str(opportunity_definition.get("id", "")),
		quality_id,
		OpportunityCatalog.get_quality_name(quality_id),
		GameDatabase.resolve_card_names_in_text(str(opportunity_definition.get("description", ""))),
	]
	if not skill_id.is_empty():
		# 当前授予技能定义；名称与说明让玩家可按技能内容反查机缘。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		search_parts.append(skill_id)
		search_parts.append(str(skill_definition.get("name", "")))
		search_parts.append(GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", ""))))
	return "\n".join(search_parts)


## 从全部牌堆建立每种游戏牌的首个代表花色点数；牌堆顺序与实体配置均不被修改。
func _build_representative_card_cache() -> void:
	_representative_card_by_definition_id.clear()
	# 全部牌堆稳定 ID；排序后扫描可避免字典插入顺序改变代表牌面。
	var deck_ids: Array[String] = []
	for deck_id_variant: Variant in GameDatabase.decks.keys():
		deck_ids.append(str(deck_id_variant))
	deck_ids.sort()
	for deck_id: String in deck_ids:
		for card_row_variant: Variant in GameDatabase.get_deck_cards(deck_id):
			# 当前紧凑牌堆条目；标准格式为[花色, 点数, 卡牌ID]。
			var card_row: Array = card_row_variant as Array
			if card_row.size() < 3:
				continue
			# 当前条目引用的稳定卡牌 ID；首个命中后不再覆盖。
			var definition_id: String = str(card_row[2])
			if _representative_card_by_definition_id.has(definition_id):
				continue
			_representative_card_by_definition_id[definition_id] = {
				"suit":str(card_row[0]),
				"rank":int(card_row[1]),
			}


## 按中文武将名排序；重名武将以稳定 ID 排序，保证图鉴顺序在平台之间一致。
## 补充：共享排序器会先按星穹列车、银河学者、贝洛伯格、仙舟联盟、匹诺康尼分组，扩展势力随后稳定排列。
func _sort_character_ids(left_character_id: String, right_character_id: String) -> bool:
	# 左侧武将玩家可见名称；只用于排序。
	var left_name: String = GameDatabase.resolve_character_name(left_character_id)
	# 右侧武将玩家可见名称；只用于排序。
	var right_name: String = GameDatabase.resolve_character_name(right_character_id)
	# 共享势力排序结果；优先处理所有非相等条目。
	var shared_result: bool = CardGallerySort.sort_character_ids(left_character_id, right_character_id)
	# 反向共享势力排序结果；与正向结果共同判断两个条目是否已经形成严格顺序。
	var reverse_shared_result: bool = CardGallerySort.sort_character_ids(right_character_id, left_character_id)
	if shared_result or reverse_shared_result:
		return shared_result
	if left_name == right_name:
		return left_character_id < right_character_id
	return left_name < right_name


## 按当前名称模式下的游戏牌名排序；同名逻辑牌以稳定 ID 排序。
## 补充：共享排序器会先按基本、锦囊、装备分组，并在组内应用需求指定的细分类顺序。
func _sort_game_card_ids(left_card_id: String, right_card_id: String) -> bool:
	# 左侧游戏牌显示名；切换名称模式后重建列表会按新名称重新排序。
	var left_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card(left_card_id))
	# 右侧游戏牌显示名；只用于当前图鉴顺序。
	var right_name: String = GameSettings.resolve_card_display_name(GameDatabase.get_card(right_card_id))
	# 共享类型排序结果；优先处理所有非相等条目。
	var shared_result: bool = CardGallerySort.sort_game_card_ids(left_card_id, right_card_id)
	# 反向共享类型排序结果；用于识别排序器判定为完全相等的同一条目。
	var reverse_shared_result: bool = CardGallerySort.sort_game_card_ids(right_card_id, left_card_id)
	if shared_result or reverse_shared_result:
		return shared_result
	if left_name == right_name:
		return left_card_id < right_card_id
	return left_name < right_name

## 返回游戏牌类型与子类型的组合文本；未知值保留原始标识，避免扩展内容在资料页失去分类。
## 专属锦囊牌（元数据 `exclusive: true`）额外前置「专属」标识：它不属于任何牌堆配置，
## 只有被其他角色的技能或其他情况触发时才会按要求加入游戏；图鉴必须能把它与可从牌堆摸到的常规牌区分开。
func _resolve_card_type_name(card_definition: Dictionary) -> String:
	# 当前主类型稳定 ID；用于映射基本、锦囊或装备。
	var card_type: String = str(card_definition.get("type", ""))
	# 当前子类型稳定 ID；为空时只显示主类型。
	var card_subtype: String = str(card_definition.get("subtype", ""))
	# 当前主类型玩家可见名称；未知类型回退原始标识。
	var type_name: String = str(CARD_TYPE_NAMES.get(card_type, card_type))
	# 当前子类型玩家可见名称；未知且非空时回退原始标识。
	var subtype_name: String = str(CARD_SUBTYPE_NAMES.get(card_subtype, card_subtype))
	# 组合后的分类文本；子类型为空时只保留主类型，避免出现悬空分隔符。
	var resolved_type_name: String = type_name if subtype_name.is_empty() else "%s · %s" % [type_name, subtype_name]
	# 专属标识；该字段同时进入资料页副标题与搜索文本，因此玩家可以直接搜索「专属」定位这类牌。
	if bool(card_definition.get("exclusive", false)):
		return "%s · %s" % [EXCLUSIVE_CARD_TAG_NAME, resolved_type_name]
	return resolved_type_name


## 返回武将性别玩家可见文本；未知扩展值统一回退“未知”。
func _resolve_gender_name(gender_id: String) -> String:
	return str(GENDER_NAMES.get(gender_id, "未知"))


## 标准化搜索文本；去除首尾空白并把英文转为小写，中文、数值和标点保持原样。
func _normalize_search_text(search_text: String) -> String:
	return search_text.strip_edges().to_lower()


## 清理当前分类的动态槽和正式牌面；重新打开或切换分类不会残留旧输入信号与节点。
func _clear_entries() -> void:
	_entries.clear()
	_content_views.clear()
	for child: Node in _grid_content.get_children():
		_grid_content.remove_child(child)
		child.queue_free()


## 刷新三个分类按钮的当前主题交互样式；选中页使用强调边框和持续按下态。
func _refresh_category_button_styles() -> void:
	for category_button: Button in [_characters_tab_button, _game_cards_tab_button, _opportunities_tab_button]:
		BattleUIStyle.apply_interaction_button(
			category_button,
			BattleUIStyle.get_color("action_button"),
			BattleUIStyle.get_color("accent") if category_button.button_pressed else BattleUIStyle.get_color("border"),
			category_button.button_pressed
		)


## 为搜索输入框应用当前主题常态与焦点样式；文本选择区使用半透明强调色。
func _apply_line_edit_style(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_placeholder_color", BattleUIStyle.get_color("text_muted"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 为纵向滚动条应用当前主题轨道与拖块；只改变浏览外观，不调整滚动数值。
func _apply_scroll_bar_style(scroll_bar: VScrollBar) -> void:
	BattleUIStyle.apply_main_menu_scroll_bar_style(scroll_bar, scroll_bar_width)


## 创建没有重复阴影的内层面板；图鉴外框保留唯一强阴影，内部只用细边区分内容。
func _make_flat_inner_panel(background_color: Color, border_color: Color, border_width: int = 1, corner_radius: int = 5) -> StyleBoxFlat:
	# 当前内层面板样式；复用主题工厂后移除阴影，避免多重外框产生视觉噪声。
	var style: StyleBoxFlat = BattleUIStyle.make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


## 恢复当前平台安全焦点；Android避免自动弹出键盘，桌面端直接聚焦搜索输入框。
func _focus_primary_control() -> void:
	if not visible or _information_backdrop.visible:
		return
	if OS.get_name() == "Android":
		MobileKeyboardGuard.focus_non_text(_characters_tab_button)
		return
	_search_input.grab_focus()


## 响应全局 UI 风格切换；只重绘当前图鉴与动态牌面，不重置搜索或分类。
func _on_ui_style_changed(_style_id: String) -> void:
	refresh_ui_style()


## 响应卡牌名称模式切换；重建当前分类的搜索文本、牌面名称和资料，规则稳定 ID 保持不变。
func _on_card_name_mode_changed(_mode: GameSettings.NameMode) -> void:
	if not visible:
		return
	_close_information(false)
	_rebuild_current_entries()
	_queue_filter_and_layout()


## Esc 优先关闭卡牌完整资料；没有资料模态时请求主菜单返回模式选择页。
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _information_backdrop.visible:
		_close_information()
	else:
		MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
		close_requested.emit()
	get_viewport().set_input_as_handled()
