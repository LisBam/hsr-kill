class_name CharacterSelectionPanel
extends Control

## 选将界面组件。该组件只渲染观察者可见候选、临时高亮和确认进度，通过稳定武将 ID 发出选择请求。

## 玩家确认武将时发出的信号；参数为稳定武将配置 ID，不携带节点或配置引用。
signal character_selected(character_id: String)

## 正式武将牌场景；五张候选牌与局内角色牌复用同一 Node2D 模型和数据渲染逻辑。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 选将标题节点的组件内相对路径；节点位于 SelectionFrame 下，不依赖场景唯一名称所有权。
const TITLE_LABEL_PATH: NodePath = NodePath("SelectionFrame/CharacterSelectionTitle")

## 选将状态文本节点的组件内相对路径；节点保留兼容但正式界面默认隐藏。
const STATUS_LABEL_PATH: NodePath = NodePath("SelectionFrame/CharacterSelectionStatus")

## 候选武将牌承载区的组件内相对路径；所有动态候选都只添加到该容器。
const CANDIDATE_AREA_PATH: NodePath = NodePath("SelectionFrame/CharacterCandidateArea")

## 主公武将牌承载区的组件内相对路径；主公亮将后创建的只读牌面添加到该容器。
const LORD_CHARACTER_AREA_PATH: NodePath = NodePath("SelectionFrame/LordCharacterArea")

## 主公牌标题节点的组件内相对路径；仅在主公牌面可见时同步显示。
const LORD_CHARACTER_LABEL_PATH: NodePath = NodePath("SelectionFrame/LordCharacterLabel")

## 主公牌与候选牌之间竖向分隔线的组件内相对路径；没有公开主公时保持隐藏且不占候选区域。
const LORD_DIVIDER_PATH: NodePath = NodePath("SelectionFrame/LordDivider")

## 旧场景缺少主公分隔线时使用的默认矩形；2像素宽竖线位于主公牌区与候选区之间。
const LORD_DIVIDER_RECT: Rect2 = Rect2(200.0, 82.0, 2.0, 242.0)

## 旧场景缺少主公分隔线时使用的暗金颜色；透明度0.72保证分隔可见但不抢占武将牌视觉层级。
const LORD_DIVIDER_COLOR: Color = Color(0.78, 0.63, 0.34, 0.72)

## 选将确认按钮的组件内相对路径；按钮只提交稳定武将 ID。
const CONFIRM_BUTTON_PATH: NodePath = NodePath("SelectionFrame/ConfirmCharacterButton")

## 候选武将牌之间的水平间距；默认18像素，在1280×720界面中可完整容纳五张148.35像素牌。
@export_range(0.0, 48.0, 1.0) var candidate_gap: float = 18.0

## 候选武将悬停时的放大倍数；默认1.08提供清晰反馈且不会明显遮挡相邻牌，运行时无需动态修改。
@export_range(1.0, 1.25, 0.01) var candidate_hover_scale: float = 1.08

## 候选武将悬停放大与恢复的过渡时长；默认0.14秒兼顾响应速度与缩放可见性，运行时无需动态修改。
@export_range(0.0, 0.5, 0.01) var candidate_hover_transition_seconds: float = 0.14

## 已公开主公武将牌的显示缩放；默认0.78使其弱于可选候选并保留分隔层级，运行时无需动态修改。
@export_range(0.5, 1.0, 0.01) var lord_character_scale: float = 0.78

## 选将标题；根据主公先选、其他玩家同时选和等待公开三个状态显示明确说明。
@onready var _title_label: Label = get_node_or_null(TITLE_LABEL_PATH) as Label

## 阶段说明文本；展示主公已亮武将和其他玩家确认进度，不泄漏隐藏选择内容。
@onready var _status_label: Label = get_node_or_null(STATUS_LABEL_PATH) as Label

## 候选武将牌承载区域；只负责提供局部坐标，牌面根节点保持 Node2D 类型。
@onready var _candidate_area: Control = get_node_or_null(CANDIDATE_AREA_PATH) as Control

## 主公武将牌承载区域；主公确认后固定显示在选将框左侧，不参与候选点击或提交。
@onready var _lord_character_area: Control = get_node_or_null(LORD_CHARACTER_AREA_PATH) as Control

## 主公武将牌标题；仅在主公已经亮将时显示，用于说明左侧只读牌面归属。
@onready var _lord_character_label: Label = get_node_or_null(LORD_CHARACTER_LABEL_PATH) as Label

## 主公牌与候选牌之间的竖向分隔线；只在主公武将已经公开时显示。
@onready var _lord_divider: ColorRect = get_node_or_null(LORD_DIVIDER_PATH) as ColorRect

## 选将确认按钮；只有已临时选中候选且规则快照允许选择时才可用。
@onready var _confirm_button: Button = get_node_or_null(CONFIRM_BUTTON_PATH) as Button

## 最近一次选将快照；只包含本地可见候选和公开确认状态，用于重绘界面。
var _snapshot: Dictionary = {}

## 本地临时选中的武将 ID；点击确认前不会发送规则动作或改变公开状态。
var _selected_character_id: String = ""

## 当前候选武将 ID 到正式武将牌视图的映射；只用于同步金色选中边框。
var _candidate_views: Dictionary = {}

## 当前左侧主公武将牌视图；主公尚未确认或选将界面关闭时为 null。
var _lord_character_view: PlayerTargetView

## 候选武将 ID 到未缩放基础位置的映射；悬停补间始终相对该位置居中放大并恢复。
var _candidate_base_positions: Dictionary = {}

## 候选武将 ID 到当前缩放补间的映射；重复进入或离开时停止旧补间，避免多个动画同时写入同一节点。
var _candidate_hover_tweens: Dictionary = {}

## 候选区域存在主公时的原始左边界；从场景保存几何读取，避免脚本重复硬编码布局坐标。
var _candidate_area_with_lord_left: float = 0.0

## 候选区域不存在主公时的左边界；与主公只读区域左边缘对齐，使候选直接占用空出的空间。
var _candidate_area_without_lord_left: float = 0.0

## 候选区域固定右边界；切换主公占位时只改变左边界，不影响确认按钮或选将框宽度。
var _candidate_area_right: float = 0.0

## 必需场景节点是否已经完整绑定；为 false 时组件保持隐藏并拒绝渲染，避免产生连续空实例报错。
var _required_nodes_ready: bool = false


## 初始化确认信号并保持选将遮罩默认隐藏，直到收到规则核心快照。
func _ready() -> void:
	_ensure_lord_divider()
	_required_nodes_ready = _validate_required_nodes()
	if not _required_nodes_ready:
		visible = false
		return
	BattleUIStyle.apply_interaction_button(_confirm_button)
	_confirm_button.pressed.connect(_confirm_selection)
	_status_label.visible = false
	_lord_character_label.visible = false
	_lord_character_area.visible = false
	_lord_divider.visible = false
	_candidate_area_with_lord_left = _candidate_area.position.x
	_candidate_area_without_lord_left = _lord_character_area.position.x
	_candidate_area_right = _candidate_area.position.x + _candidate_area.size.x
	visible = false


## 为仍在编辑器内存中的旧主场景补建主公分隔线；新节点继续使用稳定相对路径参与统一校验和显隐。
func _ensure_lord_divider() -> void:
	if _lord_divider != null:
		return
	# 选将主框；旧场景只有在该稳定父节点存在时才能安全补建分隔线。
	var selection_frame: Control = get_node_or_null("SelectionFrame") as Control
	if selection_frame == null:
		return
	# 运行时主公分隔线；几何和颜色与正式场景资源保持一致，编辑器重新载入场景后不会产生视觉差异。
	var runtime_lord_divider: ColorRect = ColorRect.new()
	runtime_lord_divider.name = StringName(LORD_DIVIDER_PATH.get_name(LORD_DIVIDER_PATH.get_name_count() - 1))
	runtime_lord_divider.position = LORD_DIVIDER_RECT.position
	runtime_lord_divider.size = LORD_DIVIDER_RECT.size
	runtime_lord_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	runtime_lord_divider.color = LORD_DIVIDER_COLOR
	runtime_lord_divider.visible = false
	selection_frame.add_child(runtime_lord_divider)
	_lord_divider = runtime_lord_divider


## 接收裁剪后的选将快照并重建候选牌；任何隐藏选择都不会进入该组件。
func bind_snapshot(snapshot: Dictionary) -> void:
	if not _required_nodes_ready:
		return
	_snapshot = snapshot.duplicate(true)
	_selected_character_id = ""
	visible = not str(_snapshot.get("phase", "")).is_empty() and str(_snapshot.get("phase", "")) != CharacterSelectionService.PHASE_COMPLETE
	if not visible:
		return
	_render_header()
	_render_lord_character()
	_render_candidates()
	_confirm_button.disabled = true


## 在正式对局开始后隐藏选将遮罩并清理动态候选牌。
func close() -> void:
	visible = false
	if not _required_nodes_ready:
		_snapshot.clear()
		_selected_character_id = ""
		return
	_clear_candidates()
	_clear_lord_character()
	_snapshot.clear()
	_selected_character_id = ""


## 渲染阶段标题、公开主公武将与其他玩家完成数量。
## 当前界面只保留阶段标题；公开主公武将由左侧正式牌面表达，确认进度文本保持隐藏。
func _render_header() -> void:
	# 当前选将阶段；决定本地是主公选择、其他玩家同时选择还是等待全员完成。
	var phase: String = str(_snapshot.get("phase", ""))
	# 本地是否可以选择；已经确认的玩家只看到等待提示，不再显示候选内容。
	var can_select: bool = bool(_snapshot.get("can_select", false))
	if phase == CharacterSelectionService.PHASE_LORD:
		_title_label.text = "主公选将"
	else:
		_title_label.text = "选择武将" if can_select else "等待其他玩家选将"
	_status_label.text = ""


## 在选将框左侧渲染已经公开的主公武将牌；主公阶段尚未确认时保持该区域隐藏。
func _render_lord_character() -> void:
	_clear_lord_character()
	# 已公开主公武将 ID；空字符串表示主公尚未完成选择，不创建占位牌。
	var lord_character_id: String = str(_snapshot.get("lord_character_id", ""))
	if lord_character_id.is_empty():
		_update_lord_partition(false)
		return
	# 主公武将定义；用于左侧正式牌面的体力、势力、名称与插画。
	var character_definition: Dictionary = GameDatabase.get_character(lord_character_id)
	# 主公势力定义；只提供牌面主题，不参与身份或阵营判定。
	var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
	_lord_character_view = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	_lord_character_area.add_child(_lord_character_view)
	# 主公只读牌面快照；不显示手牌数与对局装备，只表达已公开的武将选择。
	var lord_snapshot: Dictionary = {
		"player_id":int(_snapshot.get("lord_player_id", -1)),
		"display_name":"主公",
		"character_id":lord_character_id,
		"character_revealed":true,
		"identity":"lord",
		"hp":int(character_definition.get("max_hp", 4)),
		"max_hp":int(character_definition.get("max_hp", 4)),
		"alive":true,
		"chained":false,
		"hand_count":0,
		"equipment":{},
		"judgment_area":[],
		"wooden_ox_storage_count":0,
	}
	_lord_character_view.configure_snapshot(lord_snapshot, character_definition, false, faction_definition)
	_lord_character_view.set_operation_state(false)
	_lord_character_view.scale = Vector2.ONE * lord_character_scale
	_lord_character_view.position = (_lord_character_area.size - _lord_character_view.card_size * lord_character_scale) * 0.5
	_lord_character_area.visible = true
	_lord_character_label.visible = true
	_update_lord_partition(true)


## 使用正式 Node2D 武将牌横向排列本地候选；候选数量由快照决定，可从默认5张继续扩展。
func _render_candidates() -> void:
	_clear_candidates()
	# 本地可见候选数组；未轮到本地或已经确认时为空，不创建占位按钮。
	var candidate_ids: Array = _snapshot.get("local_candidates", []) as Array
	if candidate_ids.is_empty():
		_confirm_button.visible = false
		return
	_confirm_button.visible = true
	_confirm_button.text = "请选择武将牌"
	for candidate_index: int in range(candidate_ids.size()):
		# 当前候选武将 ID；点击与确认只使用该稳定 ID。
		var character_id: String = str(candidate_ids[candidate_index])
		# 当前武将定义；用于体力、势力、技能说明和正式牌面插画渲染。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		# 当前势力定义；候选牌与局内角色牌共用同一圆徽配色来源。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
		# 正式武将牌节点；根类型为 Node2D，透明输入区域负责点击。
		var character_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
		_candidate_area.add_child(character_view)
		# 候选牌快照；只包含表现所需字段，不伪造玩家规则状态或加入对局玩家数组。
		var candidate_snapshot: Dictionary = {
			"player_id":candidate_index,
			"display_name":"候选武将",
			"character_id":character_id,
			"character_revealed":true,
			"identity":"hidden",
			"hp":int(character_definition.get("max_hp", 4)),
			"max_hp":int(character_definition.get("max_hp", 4)),
			"alive":true,
			"chained":false,
			"hand_count":0,
			"equipment":{},
			"judgment_area":[],
			"wooden_ox_storage_count":0,
		}
		character_view.configure_snapshot(candidate_snapshot, character_definition, false, faction_definition)
		character_view.pressed.connect(_select_candidate.bind(character_id))
		character_view.hover_changed.connect(_on_candidate_hover_changed.bind(character_id))
		_candidate_views[character_id] = character_view
	# 第一张正式候选牌；其场景尺寸是全部候选布局的唯一牌宽来源，避免桌面脚本重复保存几何常量。
	var first_character_view: PlayerTargetView = _candidate_views[str(candidate_ids[0])] as PlayerTargetView
	# 单张武将牌宽度；直接读取正式3:4牌面，不创建选将专用尺寸或硬编码副本。
	var card_width: float = first_character_view.card_size.x
	# 全部候选占用宽度；用于在候选区域中水平居中，并支持后续调整候选数量。
	var total_width: float = card_width * float(candidate_ids.size()) + candidate_gap * float(maxi(candidate_ids.size() - 1, 0))
	# 首张候选横坐标；区域宽度不足时从0开始，避免产生负坐标裁切。
	var start_x: float = maxf((_candidate_area.size.x - total_width) * 0.5, 0.0)
	for candidate_index: int in range(candidate_ids.size()):
		# 当前候选武将 ID；用于按快照顺序取回已经创建的正式武将牌视图。
		var character_id: String = str(candidate_ids[candidate_index])
		# 当前候选武将牌；只更新布局位置，不重复配置数据或信号。
		var character_view: PlayerTargetView = _candidate_views[character_id] as PlayerTargetView
		var base_position: Vector2 = Vector2(start_x + float(candidate_index) * (card_width + candidate_gap), 0.0)
		character_view.position = base_position
		_candidate_base_positions[character_id] = base_position


## 更新本地临时选择和候选牌边框；规则状态在确认按钮点击前保持不变。
func _select_candidate(character_id: String) -> void:
	_selected_character_id = character_id
	for candidate_id_variant: Variant in _candidate_views.keys():
		# 当前候选 ID；与临时选择相同时显示金色选中边框。
		var candidate_id: String = str(candidate_id_variant)
		# 当前候选牌视图；映射只在本次候选重绘期间有效。
		var candidate_view: PlayerTargetView = _candidate_views[candidate_id] as PlayerTargetView
		candidate_view.set_target_state(false, candidate_id == _selected_character_id)
	_confirm_button.disabled = _selected_character_id.is_empty()
	_confirm_button.text = "确认选择：%s" % GameDatabase.resolve_character_name(_selected_character_id)


## 发出稳定武将 ID 选择请求；权威服务仍会再次校验阶段、玩家和候选列表。
func _confirm_selection() -> void:
	if _selected_character_id.is_empty() or not bool(_snapshot.get("can_select", false)):
		return
	_confirm_button.disabled = true
	character_selected.emit(_selected_character_id)


## 清理所有动态候选牌；每次阶段快照重建，避免保留旧输入连接或高亮状态。
func _clear_candidates() -> void:
	for hover_tween_variant: Variant in _candidate_hover_tweens.values():
		# 当前候选缩放补间；候选节点释放前先停止，避免结束回调继续访问旧节点。
		var hover_tween: Tween = hover_tween_variant as Tween
		if hover_tween != null and hover_tween.is_valid():
			hover_tween.kill()
	_candidate_hover_tweens.clear()
	_candidate_base_positions.clear()
	_candidate_views.clear()
	for child: Node in _candidate_area.get_children():
		_candidate_area.remove_child(child)
		child.queue_free()


## 清理左侧主公武将牌；阶段切换和重新开局时不会保留旧局节点。
func _clear_lord_character() -> void:
	_lord_character_view = null
	_lord_character_area.visible = false
	_lord_character_label.visible = false
	_lord_divider.visible = false
	for child: Node in _lord_character_area.get_children():
		_lord_character_area.remove_child(child)
		child.queue_free()


## 根据主公是否已公开调整候选区域与分隔线；没有主公时候选直接从原主公区域左边缘开始排列。
func _update_lord_partition(has_public_lord: bool) -> void:
	if _candidate_area == null or _lord_divider == null:
		return
	# 当前候选区域左边界；有主公时保留只读牌与竖线，没有主公时直接占用全部横向空间。
	var candidate_left: float = _candidate_area_with_lord_left if has_public_lord else _candidate_area_without_lord_left
	_candidate_area.position.x = candidate_left
	_candidate_area.size.x = maxf(_candidate_area_right - candidate_left, 0.0)
	_lord_divider.visible = has_public_lord


## 播放候选武将居中缩放；鼠标移走时使用相同时长平滑恢复基础位置与1倍尺寸。
func _on_candidate_hover_changed(hovered: bool, character_id: String) -> void:
	# 当前候选武将牌；快照重建后旧悬停信号可能迟到，无有效节点时直接忽略。
	var character_view: PlayerTargetView = _candidate_views.get(character_id) as PlayerTargetView
	if character_view == null or not is_instance_valid(character_view) or not _candidate_base_positions.has(character_id):
		return
	# 当前候选已有补间；新的进入或离开状态应从实时变换继续，不叠加第二个写入者。
	var previous_tween: Tween = _candidate_hover_tweens.get(character_id) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	# 当前目标缩放；离开时固定恢复1倍，进入时使用检查器配置倍数。
	var target_scale_value: float = candidate_hover_scale if hovered else 1.0
	# 当前基础位置；缩放时向左上补偿半个尺寸差，使武将牌围绕视觉中心放大。
	var base_position: Vector2 = _candidate_base_positions[character_id]
	# 当前目标位置；Node2D 默认以左上角为原点，因此需要显式中心补偿。
	var target_position: Vector2 = base_position - character_view.card_size * (target_scale_value - 1.0) * 0.5
	character_view.z_index = 10 if hovered else 0
	if candidate_hover_transition_seconds <= 0.0:
		character_view.scale = Vector2.ONE * target_scale_value
		character_view.position = target_position
		return
	# 当前悬停补间；位置与缩放并行使用二次缓出，进入和恢复都保持一致节奏。
	var hover_tween: Tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(character_view, "scale", Vector2.ONE * target_scale_value, candidate_hover_transition_seconds)
	hover_tween.tween_property(character_view, "position", target_position, candidate_hover_transition_seconds)
	_candidate_hover_tweens[character_id] = hover_tween
	hover_tween.finished.connect(_on_candidate_hover_tween_finished.bind(character_id, hover_tween))


## 清理已经完成的候选悬停补间索引；只有映射仍指向同一补间时才删除。
func _on_candidate_hover_tween_finished(character_id: String, hover_tween: Tween) -> void:
	if _candidate_hover_tweens.get(character_id) == hover_tween:
		_candidate_hover_tweens.erase(character_id)


## 校验选将组件依赖的静态节点；缺失时只输出一条包含全部节点名的长期诊断信息。
func _validate_required_nodes() -> bool:
	# 缺失节点名称数组；完整收集后一次性输出，避免每个 visible/text 赋值分别产生空实例错误。
	var missing_node_names: Array[String] = []
	if _title_label == null:
		missing_node_names.append(str(TITLE_LABEL_PATH))
	if _status_label == null:
		missing_node_names.append(str(STATUS_LABEL_PATH))
	if _candidate_area == null:
		missing_node_names.append(str(CANDIDATE_AREA_PATH))
	if _lord_character_area == null:
		missing_node_names.append(str(LORD_CHARACTER_AREA_PATH))
	if _lord_character_label == null:
		missing_node_names.append(str(LORD_CHARACTER_LABEL_PATH))
	if _lord_divider == null:
		missing_node_names.append(str(LORD_DIVIDER_PATH))
	if _confirm_button == null:
		missing_node_names.append(str(CONFIRM_BUTTON_PATH))
	if missing_node_names.is_empty():
		return true
	push_error("选将界面缺少必需节点：%s" % "、".join(missing_node_names))
	return false
