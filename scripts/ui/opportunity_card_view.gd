class_name OpportunityCardView
extends PanelContainer

## 机缘卡牌面组件。牌面不使用插画，只显示规则正文，并用背景与边框颜色表达绿、蓝、紫、橙、红五种品质。

## 玩家点击可选机缘卡时发出稳定卡牌ID；组件不解释或执行任何效果。
signal card_selected(card_id: String)

## 机缘包含获得技能时发出统一悬停资料；弹窗与牌桌只负责转发，不创建机缘专用说明框。
signal information_requested(information: Dictionary, anchor_rect: Rect2)

## 鼠标离开、牌面禁用或节点释放时撤销当前机缘技能说明。
signal information_dismissed

## 正式机缘卡固定尺寸；宽高参考武将牌比例，三张并列时适配1280×720战斗视口。
@export var card_size: Vector2 = Vector2(180.0, 240.0)

## 是否向父级容器报告机缘牌最小尺寸；默认开启供普通独立展示使用，选择弹窗的固定牌位会在入树前关闭以隔离悬停缩放和样式变化。
@export var reports_layout_minimum_size: bool = true

## 普通机缘卡规则正文的默认字号；默认21像素沿用正式牌面规格，内容定义可按单张牌覆盖，运行时无需动态修改。
@export_range(12, 28, 1) var default_description_font_size: int = 21

## 鼠标悬停时的缩放倍率；默认1.06与正式卡牌一致，运行时只改变机缘卡视觉反馈。
@export_range(1.0, 1.2, 0.01) var hover_scale: float = 1.06

## 悬停缩放动画时长；默认0.12秒与正式卡牌一致，暂停选择期间仍会继续播放。
@export_range(0.05, 0.4, 0.01) var hover_animation_seconds: float = 0.12

## 悬停时卡面背景提亮比例；默认0.08与正式卡牌纸张反馈一致，不改变品质语义。
@export_range(0.0, 0.3, 0.01) var hover_lightening: float = 0.08

## 悬停时额外增加的边框像素；默认1像素，在保留品质粗边框的同时模拟正式卡牌加粗反馈。
@export_range(0, 4, 1) var hover_border_bonus: int = 1

## 悬停卡牌临时绘制层级；固定100与正式卡牌一致，确保三张卡重叠时当前牌显示在最上方。
const HOVER_Z_INDEX: int = 100

## 机缘牌内容区的固定内缩；4像素与普通品质边框一致，悬停边框变粗时仍保持正文、技能名与容器的可用区域不变。
const CARD_CONTENT_MARGIN: float = 4.0

## 当前机缘卡稳定ID；空字符串表示尚未配置，点击不会发出选择。
var _card_id: String = ""

## 当前是否允许点击；等待其他玩家时牌面可保持显示但不会提交动作。
var _interactive: bool = false

## 当前机缘卡品质主色；配置卡牌时写入，悬停刷新只基于该颜色计算而不重复解析卡牌定义。
var _quality_color: Color = Color("3f8f58")

## 当前品质普通状态的缓存面板样式；配置卡牌时重建一次，重复进入、离开与禁用时直接复用资源。
var _normal_panel_style: StyleBoxFlat

## 当前品质悬停状态的缓存面板样式；背景提亮与边框加粗在配置阶段预先计算，鼠标移动时不再分配新资源。
var _hovered_panel_style: StyleBoxFlat

## 当前鼠标是否悬停在可交互机缘卡上；只决定缩放、提亮、边框与绘制层级。
var _is_hovered: bool = false

## 当前悬停缩放动画；进入、离开或禁用时先停止旧动画，避免快速移动鼠标产生缩放抖动。
var _hover_tween: Tween

## 机缘卡未悬停时的原始绘制层级；默认0，恢复时不假设父容器永远使用同一层级。
var _resting_z_index: int = 0

## 当前机缘可获得技能的统一信息内容；空字典表示本卡不授予技能，悬停只保留牌面动画。
var _skill_information: Dictionary = {}

## 当前是否已经发出技能悬停资料；用于禁用或离树时只撤销真实存在的说明来源。
var _skill_information_visible: bool = false

## 卡面规则正文；只显示主公提供的机缘描述，不添加插画、标题或额外规则改写。
@onready var _description_label: Label = %DescriptionLabel

## 获得技能机缘的专用文字容器；把技能名称从描述中拆出为独占一行，避免短技能名被自动换行拆断。
@onready var _skill_description_content: VBoxContainer = %SkillDescriptionContent

## 获得技能机缘中位于技能名前的原始描述片段；保留原始规则文案与引号格式。
@onready var _skill_prefix_label: Label = %SkillPrefixLabel

## 获得技能机缘的技能名称专用单行标签；超出牌面宽度时显示省略号而不换行。
@onready var _skill_name_label: Label = %SkillNameLabel

## 获得技能机缘中位于技能名后的原始描述片段；兼容“并获得技能”等复合规则描述。
@onready var _skill_suffix_label: Label = %SkillSuffixLabel

## 覆盖整张牌面的透明按钮；输入与视觉分离，正文标签保持纯展示职责。
@onready var _input_button: Button = %InputButton


## 初始化透明输入并应用默认不可交互状态。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 对外最小尺寸；固定牌位内的卡面不参与父HBox最小尺寸计算，独立展示仍保持正式卡牌尺寸。
	custom_minimum_size = card_size if reports_layout_minimum_size else Vector2.ZERO
	pivot_offset = card_size * 0.5
	_resting_z_index = z_index
	_input_button.pressed.connect(_on_pressed)
	_input_button.mouse_entered.connect(_on_mouse_entered)
	_input_button.mouse_exited.connect(_on_mouse_exited)
	_input_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_refresh_interaction_state()


## 配置机缘卡静态快照；card_definition必须来自权威快照或OpportunityCatalog深拷贝。
func configure(card_definition: Dictionary, interactive: bool = true) -> void:
	_dismiss_skill_information()
	_card_id = str(card_definition.get("id", ""))
	_interactive = interactive and not _card_id.is_empty()
	# 机缘原始描述；技能名称展示会在下方按原文切分，普通机缘则保持整个描述使用统一正文标签。
	var description: String = str(card_definition.get("description", ""))
	# 本张普通机缘正文的最终字号；未声明覆盖值时恢复默认值，保证同一牌面节点复用后不会继承上一张卡的缩小样式。
	var description_font_size: int = int(card_definition.get("description_font_size", default_description_font_size))
	_description_label.add_theme_font_size_override("font_size", description_font_size)
	# 机缘授予的技能ID；没有技能字段的普通数值机缘不创建空说明框。
	var skill_id: String = str(card_definition.get("skill_id", ""))
	# 机缘技能定义；说明沿用技能源码唯一原文，并按当前卡牌名称模式解析完整书名号。
	var skill_definition: Dictionary = GameDatabase.get_skill(skill_id) if not skill_id.is_empty() else {}
	_configure_description_layout(description, skill_definition)
	_skill_information = {}
	if not skill_definition.is_empty():
		_skill_information = {
			"title":"【%s】" % str(skill_definition.get("name", skill_id)),
			"subtitle":"机缘可获得技能",
			"description":GameDatabase.resolve_card_names_in_text(str(skill_definition.get("description", "技能元数据尚未登记。"))),
			"reincarnation":bool(skill_definition.get("reincarnation", false)),
			"reincarnation_section_index":0,
		}
	_apply_quality_style(str(card_definition.get("quality", "green")))
	if not _interactive:
		_restore_hover_state()
	_refresh_interaction_state()


## 根据是否授予技能选择牌面文字布局；技能名保持一整行，其他原始文案继续由可换行正文承载。
func _configure_description_layout(description: String, skill_definition: Dictionary) -> void:
	_description_label.text = description
	_description_label.visible = true
	_skill_description_content.visible = false
	_skill_prefix_label.text = ""
	_skill_prefix_label.visible = false
	_skill_name_label.text = ""
	_skill_suffix_label.text = ""
	_skill_suffix_label.visible = false
	if skill_definition.is_empty():
		return
	# 机缘技能显示名；使用原始中文引号以保持卡牌描述文案不被改写。
	var skill_name: String = str(skill_definition.get("name", ""))
	if skill_name.is_empty():
		return
	# 原始描述中的完整技能名称片段；只拆分一次，避免复合描述的其他正文被丢失。
	var quoted_skill_name: String = "“%s”" % skill_name
	var skill_name_start: int = description.find(quoted_skill_name)
	if skill_name_start < 0:
		return
	# 技能名之前的原文；例如“获得技能”或“……并获得技能”。
	var prefix_text: String = description.left(skill_name_start)
	# 技能名之后的原文；当前大多数机缘为空，但保留此段以支持未来追加规则而不破坏布局。
	var suffix_text: String = description.substr(skill_name_start + quoted_skill_name.length())
	_skill_prefix_label.text = prefix_text
	_skill_prefix_label.visible = not prefix_text.is_empty()
	_skill_name_label.text = quoted_skill_name
	_skill_suffix_label.text = suffix_text
	_skill_suffix_label.visible = not suffix_text.is_empty()
	_description_label.visible = false
	_skill_description_content.visible = true


## 设置当前牌面是否允许提交选择；权威回包前可立即禁用内部按钮，避免快速连点产生重复动作。
func set_interactive(interactive: bool) -> void:
	_interactive = interactive and not _card_id.is_empty()
	if not _interactive:
		_restore_hover_state()
	_refresh_interaction_state()


## 根据品质应用整张卡面颜色；颜色仅表达稀有度，不改变正文与规则数值。
func _apply_quality_style(quality_id: String) -> void:
	# 品质主色；灰色用于不参与随机抽取的关卡专属机缘，其余五种颜色用于普通三选一卡池。
	_quality_color = {
		"gray":Color("707782"),
		"green":Color("3f8f58"),
		"blue":Color("356fa8"),
		"purple":Color("7550a8"),
		"orange":Color("b66a2f"),
		"red":Color("a9363f"),
	}.get(quality_id, Color("3f8f58")) as Color
	_rebuild_panel_style_cache()
	_refresh_visual_state()
	_description_label.add_theme_color_override("font_color", Color("fff8e8"))
	_description_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.92))
	_description_label.add_theme_constant_override("outline_size", 4)
	_skill_prefix_label.add_theme_color_override("font_color", Color("fff8e8"))
	_skill_prefix_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.92))
	_skill_prefix_label.add_theme_constant_override("outline_size", 4)
	_skill_name_label.add_theme_color_override("font_color", Color("fff8e8"))
	_skill_name_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.92))
	_skill_name_label.add_theme_constant_override("outline_size", 4)
	_skill_suffix_label.add_theme_color_override("font_color", Color("fff8e8"))
	_skill_suffix_label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.92))
	_skill_suffix_label.add_theme_constant_override("outline_size", 4)


## 根据品质、悬停与交互状态重绘卡面；悬停只提亮原品质色，不替换品质颜色。
func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	if _normal_panel_style == null or _hovered_panel_style == null:
		_rebuild_panel_style_cache()
	# 卡面样式；深色品质底面承托白色正文，亮色边框模拟武将牌的正式轮廓。
	var panel_style: StyleBoxFlat = _hovered_panel_style if _is_hovered and _interactive else _normal_panel_style
	add_theme_stylebox_override("panel", panel_style)


## 按当前品质与导出参数建立普通、悬停两份样式；只在配置变化时分配资源，悬停热路径仅切换引用。
func _rebuild_panel_style_cache() -> void:
	# 普通卡面背景色；固定按品质主色压暗0.42，确保白色正文在所有品质下均可阅读。
	var normal_background_color: Color = _quality_color.darkened(0.42)
	_normal_panel_style = _create_panel_style(normal_background_color, 4)
	# 悬停卡面背景色；按检查器比例提亮并增加配置边框像素，不改变品质主色或卡面尺寸。
	var hovered_background_color: Color = normal_background_color.lightened(hover_lightening)
	_hovered_panel_style = _create_panel_style(hovered_background_color, 4 + hover_border_bonus)


## 创建一份完整机缘卡面样式；调用方传入背景色与边框宽度，品质边框、圆角和阴影保持统一。
func _create_panel_style(background_color: Color, border_width: int) -> StyleBoxFlat:
	# 新面板样式；只由缓存重建入口创建，不在鼠标进入或离开事件中反复分配。
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = background_color
	panel_style.border_color = _quality_color.lightened(0.30)
	panel_style.set_border_width_all(border_width)
	# 内容区内缩；显式固定四边边距，禁止悬停边框由4像素变为5像素时挤压PanelContainer内部文字布局。
	panel_style.content_margin_left = CARD_CONTENT_MARGIN
	panel_style.content_margin_top = CARD_CONTENT_MARGIN
	panel_style.content_margin_right = CARD_CONTENT_MARGIN
	panel_style.content_margin_bottom = CARD_CONTENT_MARGIN
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.shadow_size = 10
	panel_style.shadow_offset = Vector2(0.0, 5.0)
	return panel_style


## 同步透明按钮禁用状态与牌面明暗；等待状态仍可阅读正文但不会产生悬停误导。
func _refresh_interaction_state() -> void:
	if _input_button == null:
		return
	_input_button.disabled = not _interactive
	modulate = Color.WHITE if _interactive else Color(0.72, 0.72, 0.72, 1.0)
	_refresh_visual_state()


## 鼠标进入可交互机缘卡时播放与正式卡牌一致的放大动画，并将当前卡提升至最上层。
func _on_mouse_entered() -> void:
	if not _interactive:
		return
	_is_hovered = true
	z_index = HOVER_Z_INDEX
	_refresh_visual_state()
	_start_hover_tween(Vector2.ONE * hover_scale)
	if not _skill_information.is_empty():
		_skill_information_visible = true
		information_requested.emit(_skill_information.duplicate(true), get_global_rect())


## 鼠标离开机缘卡时恢复原始缩放、品质样式和父容器绘制层级。
func _on_mouse_exited() -> void:
	_restore_hover_state()


## 结束悬停状态；提交选择导致按钮禁用时也调用，避免牌面停留在放大状态。
func _restore_hover_state() -> void:
	_dismiss_skill_information()
	_is_hovered = false
	z_index = _resting_z_index
	_refresh_visual_state()
	_start_hover_tween(Vector2.ONE)


## 撤销当前机缘技能说明；普通机缘或尚未发出说明时保持静默。
func _dismiss_skill_information() -> void:
	if not _skill_information_visible:
		return
	_skill_information_visible = false
	information_dismissed.emit()


## 启动悬停缩放补间；二次缓出曲线与正式卡牌保持一致，连续进入离开时从当前比例平滑过渡。
func _start_hover_tween(target_scale: Vector2) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	if hover_animation_seconds <= 0.0:
		scale = target_scale
		return
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_QUAD)
	_hover_tween.set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target_scale, hover_animation_seconds)


## 提交当前稳定卡牌ID；空ID与禁用状态由配置层和按钮共同防御。
func _on_pressed() -> void:
	if _interactive and not _card_id.is_empty():
		card_selected.emit(_card_id)


## 节点离开场景树时停止尚未完成的补间，避免动态重建下一名选择者牌面时保留旧动画引用。
func _exit_tree() -> void:
	_dismiss_skill_information()
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
