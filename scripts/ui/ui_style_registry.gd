class_name UIStyleRegistry
extends RefCounted

## UI 风格注册表。该类只维护风格标识、显示名称与配色数据，不读取场景节点、对局状态或玩家设置。

## 黑白太空风格的稳定标识；作为默认风格使用，修改字符串会使旧设置无法继续匹配。
## 当前显示为“崩铁风格”；稳定标识继续沿用 `space_mono`，保证旧设置无需迁移即可自动使用新版视觉。
const STYLE_SPACE_MONO: String = "space_mono"

## 暖木十周年风格的稳定标识；用于保留项目原有深青、木色与暗金配色。
## 设置显示名调整为“暖木家园”，稳定标识继续保留以兼容已有设置数据。
const STYLE_DECADE_WOOD: String = "decade_wood"

## 新安装与未识别设置使用的默认风格；黑白太空风格强调近黑背景、银白边框与星空层次。
## 当前默认视觉提取参考界面的黑色厚框、雾面深灰内容区与低饱和金色装饰；浅色只保留给卡牌和装备信息面，避免大面积亮底抢夺焦点。
const DEFAULT_STYLE_ID: String = STYLE_SPACE_MONO

## 设置菜单中的固定风格顺序；默认风格置于首项，后续新增风格只需在注册表追加标识与配色。
const STYLE_ORDER: Array[String] = [STYLE_SPACE_MONO, STYLE_DECADE_WOOD]

## 风格显示名称；仅用于设置菜单与文档展示，不参与配色查询或场景判断。
const STYLE_DISPLAY_NAMES: Dictionary = {
	STYLE_SPACE_MONO: "崩铁风格",
	STYLE_DECADE_WOOD: "暖木家园",
}

## 全部 UI 风格配色；键名表示长期稳定的视觉语义，组件只能按语义取色，不能依赖具体主题名称。
const STYLE_PALETTES: Dictionary = {
	STYLE_SPACE_MONO: {
		"table_inset": 34.0,
		"rail_width": 14.0,
		"outer_background": Color("111214"),
		"outer_background_secondary": Color("111214"),
		"table_surface": Color("24262b"),
		"table_inner": Color("30333a"),
		"rail": Color("1d1d1d"),
		"rail_highlight": Color("3b3936"),
		"sky": Color("30333a"),
		"star": Color("c9ae6b"),
		"mountain": Color("30333a"),
		"building": Color("30333a"),
		"ornament": Color("bda66b"),
		"space_grid": Color("00000000"),
		"backdrop_shade": Color("00000000"),
		"ornament_overlay": Color("c9ae6b1f"),
		"panel": Color("242321f2"),
		"metal_panel": Color("171717f7"),
		"jade_panel": Color("2a2825f2"),
		"border": Color("bfa86c"),
		"accent": Color("d4b55f"),
		"legal_target": Color("f1dfaa"),
		"danger": Color("ef6268"),
		"action_button": Color("403b32"),
		"disabled_button": Color("1d1c1a"),
		"disabled_button_border": Color("575149"),
		"disabled_button_font": Color("847e73"),
		"button_font": Color("f4f1e8"),
		"button_hover_font": Color("fffaf0"),
		"button_pressed_font": Color("e2d4ae"),
		"text_primary": Color("f4f1e8"),
		"text_secondary": Color("d0c8b8"),
		"text_muted": Color("9b9488"),
		"text_guide": Color("f1dfaa"),
		"player_background": Color("242321f2"),
		"player_current_background": Color("363127f5"),
		"player_operator_background": Color("493e27f7"),
		"player_disabled_background": Color("201f1d"),
		"player_disabled_border": Color("615b52"),
		"health_full": Color("44ca67"),
		"health_warning": Color("e4c84f"),
		"health_danger": Color("ef4f55"),
		"health_lost": Color("34312d"),
		"health_shadow": Color("0b0b0b"),
		"health_number": Color("f4f1e8"),
		"health_frame_background": Color("1c1b19"),
		"health_frame_border": Color("bfa86c"),
		"faction_neutral": Color("6e7785"),
		"hand_badge_background": Color("2b2926"),
		"hand_badge_border": Color("d4b55f"),
		"equipment_background": Color("eeeae2"),
		"equipment_hover_background": Color("fffaf0"),
		"equipment_empty_background": Color("242321e8"),
		"equipment_border": Color("b49c63"),
		"equipment_empty_border": Color("75694fa6"),
		"equipment_text": Color("292621"),
		"equipment_empty_text": Color("aaa294"),
		"card_paper": Color("f4f1e9"),
		"card_wooden_ox_paper": Color("e9eee6"),
		"card_disabled_border": Color("726d65"),
		"card_text": Color("302d29"),
		"card_red_suit": Color("b43c42"),
		"card_basic": Color("b65350"),
		"card_trick": Color("4e7fa7"),
		"card_equipment": Color("a98d55"),
		"card_fire": Color("d66a46"),
		"card_thunder": Color("5e85ce"),
		"card_back_background": Color("1d1d1d"),
		"card_back_center": Color("393328"),
		"card_back_title": Color("f4f1e8"),
		"card_back_subtitle": Color("c9ae6b"),
		"skill_available_background": Color("4a3e25"),
		"skill_idle_background": Color("292724"),
		"skill_idle_border": Color("806f4b"),
		"shade": Color("000000d1"),
		"selection_panel": Color("211f1cf2"),
		"selection_section": Color("d4b55f"),
		"taken_label_background": Color("24211de8"),
		"target_line": Color("f1dfaa"),
		"end_play_button": Color("7d3431"),
		"end_play_border": Color("e06a61"),
		"suppressed_button": Color("242321"),
		"suppressed_border": Color("655f56"),
		"is_monochrome": false,
		"uses_space_grid": false,
		"uses_starfield": false,
		"uses_scenery": false,
	},
	STYLE_DECADE_WOOD: {
		"table_inset": 18.0,
		"rail_width": 14.0,
		"outer_background": Color("120d0c"),
		"outer_background_secondary": Color("120d0c"),
		"table_surface": Color("20202d"),
		"table_inner": Color("151725"),
		"rail": Color("4a2818"),
		"rail_highlight": Color("875532"),
		"sky": Color("222336"),
		"star": Color("d8d1c2"),
		"mountain": Color("151725"),
		"building": Color("10131f"),
		"ornament": Color("c6a15f"),
		"space_grid": Color("00000000"),
		"backdrop_shade": Color("120d0c1f"),
		"ornament_overlay": Color("d6b36d1a"),
		"panel": Color("342b25e8"),
		"metal_panel": Color("211b18f2"),
		"jade_panel": Color("172b27ed"),
		"border": Color("a8834f"),
		"accent": Color("efc76d"),
		"legal_target": Color("61c7a4"),
		"danger": Color("e96b63"),
		"action_button": Color("76521f"),
		"disabled_button": Color("242321"),
		"disabled_button_border": Color("514c45"),
		"disabled_button_font": Color("77736c"),
		"button_font": Color("f5e5b7"),
		"button_hover_font": Color("fff2c8"),
		"button_pressed_font": Color("ead49d"),
		"text_primary": Color("f0d18a"),
		"text_secondary": Color("c7c2ae"),
		"text_muted": Color("aaa398"),
		"text_guide": Color("f7e89e"),
		"player_background": Color("211d1af2"),
		"player_current_background": Color("332b20f5"),
		"player_operator_background": Color("463a28f7"),
		"player_disabled_background": Color("292724"),
		"player_disabled_border": Color("544f49"),
		"health_full": Color("44ca67"),
		"health_warning": Color("e4c84f"),
		"health_danger": Color("ef4f55"),
		"health_lost": Color("26382c"),
		"health_shadow": Color("07140a"),
		"health_number": Color("e7d59b"),
		"health_frame_background": Color("17251d"),
		"health_frame_border": Color("c69f4f"),
		"faction_neutral": Color("526b70"),
		"hand_badge_background": Color("9e3528"),
		"hand_badge_border": Color("f0ad36"),
		"equipment_background": Color("e4cfa6"),
		"equipment_hover_background": Color("f0ddb5"),
		"equipment_empty_background": Color("352620e8"),
		"equipment_border": Color("5a3221"),
		"equipment_empty_border": Color("8d7147a6"),
		"equipment_text": Color("33281e"),
		"equipment_empty_text": Color("9b8a70"),
		"card_paper": Color("e8dcc3"),
		"card_wooden_ox_paper": Color("d8e4d4"),
		"card_disabled_border": Color("655b50"),
		"card_text": Color("553e31"),
		"card_red_suit": Color("a63631"),
		"card_basic": Color("a44e43"),
		"card_trick": Color("4f718f"),
		"card_equipment": Color("8a7548"),
		"card_fire": Color("c65f3f"),
		"card_thunder": Color("547fc4"),
		"card_back_background": Color("151f23"),
		"card_back_center": Color("1e3439"),
		"card_back_title": Color("e7cd8b"),
		"card_back_subtitle": Color("a2bfb7"),
		"skill_available_background": Color("315d51"),
		"skill_idle_background": Color("413931"),
		"skill_idle_border": Color("81715d"),
		"shade": Color("030201d6"),
		"selection_panel": Color("201b18"),
		"selection_section": Color("9ed3c3"),
		"taken_label_background": Color("241c18e8"),
		"target_line": Color("e4bd67"),
		"end_play_button": Color("8f302d"),
		"end_play_border": Color("e06a61"),
		"suppressed_button": Color("292826"),
		"suppressed_border": Color("5b5751"),
		"is_monochrome": false,
		"uses_space_grid": false,
		"uses_starfield": true,
		"uses_scenery": true,
	},
}


## 返回设置菜单可展示的全部风格标识副本；调用方不能修改注册表中的固定顺序。
static func get_style_ids() -> Array[String]:
	return STYLE_ORDER.duplicate()


## 返回风格的中文显示名称；未知标识回退到默认风格名称，避免设置界面出现技术字符串。
static func get_display_name(style_id: String) -> String:
	# 已规范化的风格标识；保证显示名称与实际可用配色指向同一套注册项。
	var normalized_style_id: String = normalize_style_id(style_id)
	return str(STYLE_DISPLAY_NAMES.get(normalized_style_id, STYLE_DISPLAY_NAMES[DEFAULT_STYLE_ID]))


## 把外部风格标识限制为已注册值；配置缺失、旧存档或拼写错误统一回退默认风格。
static func normalize_style_id(style_id: String) -> String:
	return style_id if STYLE_PALETTES.has(style_id) else DEFAULT_STYLE_ID


## 返回指定风格的一份只读语义值；颜色与布尔标记都通过该入口查询，缺失键使用调用方回退值。
static func get_value(style_id: String, key: String, fallback: Variant = null) -> Variant:
	# 已规范化的风格标识；后续新增设置来源时也不会让组件访问不存在的字典。
	var normalized_style_id: String = normalize_style_id(style_id)
	# 当前风格配色字典；注册表常量只读，调用方只取得单个值而不持有整个字典引用。
	var palette: Dictionary = STYLE_PALETTES.get(normalized_style_id, {}) as Dictionary
	return palette.get(key, fallback)


## 返回指定语义颜色；缺失或类型错误时使用调用方提供的安全颜色。
static func get_color(style_id: String, key: String, fallback: Color = Color.WHITE) -> Color:
	# 当前语义值；显式校验 Color 类型，避免布尔配置或错误键被静默转换为透明色。
	var value: Variant = get_value(style_id, key, fallback)
	return value as Color if value is Color else fallback


## 返回指定风格是否采用单色化装饰；语义色如体力警告和红黑花色仍由各组件保留。
static func is_monochrome(style_id: String) -> bool:
	return bool(get_value(style_id, "is_monochrome", false))
