class_name CharacterSelectionPanel
extends Control

## 选将界面组件。该组件只渲染观察者可见候选、临时高亮和确认进度，通过稳定武将 ID 发出选择请求。

## 玩家确认武将时发出的信号；参数为稳定武将配置 ID，不携带节点或配置引用。
signal character_selected(character_id: String)

## 正式武将牌场景；五张候选牌与局内角色牌复用同一 Node2D 模型和数据渲染逻辑。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 候选武将牌之间的水平间距；默认18像素，在1280×720界面中可完整容纳五张148.35像素牌。
@export_range(0.0, 48.0, 1.0) var candidate_gap: float = 18.0

## 选将标题；根据主公先选、其他玩家同时选和等待公开三个状态显示明确说明。
@onready var _title_label: Label = %CharacterSelectionTitle

## 阶段说明文本；展示主公已亮武将和其他玩家确认进度，不泄漏隐藏选择内容。
@onready var _status_label: Label = %CharacterSelectionStatus

## 候选武将牌承载区域；只负责提供局部坐标，牌面根节点保持 Node2D 类型。
@onready var _candidate_area: Control = %CharacterCandidateArea

## 选将确认按钮；只有已临时选中候选且规则快照允许选择时才可用。
@onready var _confirm_button: Button = %ConfirmCharacterButton

## 最近一次选将快照；只包含本地可见候选和公开确认状态，用于重绘界面。
var _snapshot: Dictionary = {}

## 本地临时选中的武将 ID；点击确认前不会发送规则动作或改变公开状态。
var _selected_character_id: String = ""

## 当前候选武将 ID 到正式武将牌视图的映射；只用于同步金色选中边框。
var _candidate_views: Dictionary = {}


## 初始化确认信号并保持选将遮罩默认隐藏，直到收到规则核心快照。
func _ready() -> void:
	BattleUIStyle.apply_interaction_button(_confirm_button)
	_confirm_button.pressed.connect(_confirm_selection)
	visible = false


## 接收裁剪后的选将快照并重建候选牌；任何隐藏选择都不会进入该组件。
func bind_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_selected_character_id = ""
	visible = not str(_snapshot.get("phase", "")).is_empty() and str(_snapshot.get("phase", "")) != CharacterSelectionService.PHASE_COMPLETE
	if not visible:
		return
	_render_header()
	_render_candidates()
	_confirm_button.disabled = true


## 在正式对局开始后隐藏选将遮罩并清理动态候选牌。
func close() -> void:
	visible = false
	_clear_candidates()
	_snapshot.clear()
	_selected_character_id = ""


## 渲染阶段标题、公开主公武将与其他玩家完成数量。
func _render_header() -> void:
	# 当前选将阶段；决定本地是主公选择、其他玩家同时选择还是等待全员完成。
	var phase: String = str(_snapshot.get("phase", ""))
	# 本地是否可以选择；已经确认的玩家只看到等待提示，不再显示候选内容。
	var can_select: bool = bool(_snapshot.get("can_select", false))
	if phase == CharacterSelectionService.PHASE_LORD:
		_title_label.text = "主公选将"
		_status_label.text = "主公先从候选武将牌中选择，确认后立即亮出。" if can_select else "等待主公选择并亮出武将。"
	else:
		_title_label.text = "同时选将"
		# 已公开主公武将 ID；空字符串只会出现在异常快照中，显示稳定占位文本。
		var lord_character_id: String = str(_snapshot.get("lord_character_id", ""))
		# 已完成玩家数量；只公开确认状态，不展示其他玩家选择的武将 ID。
		var ready_count: int = 0
		# 选将玩家总数；等于 readiness 数组长度，供进度文字完整显示。
		var total_count: int = (_snapshot.get("readiness", []) as Array).size()
		for readiness_variant: Variant in _snapshot.get("readiness", []):
			if bool((readiness_variant as Dictionary).get("ready", false)):
				ready_count += 1
		_status_label.text = "主公已亮出【%s】｜其他玩家同时选择，完成 %d/%d%s" % [
			GameDatabase.resolve_character_name(lord_character_id),
			ready_count,
			total_count,
			"" if can_select else "｜等待全员同时亮出",
		]


## 使用正式 Node2D 武将牌横向排列本地候选；候选数量由快照决定，可从默认5张继续扩展。
func _render_candidates() -> void:
	_clear_candidates()
	# 本地可见候选数组；未轮到本地或已经确认时为空，不创建占位按钮。
	var candidate_ids: Array = _snapshot.get("local_candidates", []) as Array
	if candidate_ids.is_empty():
		_confirm_button.visible = false
		return
	_confirm_button.visible = true
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
		character_view.position = Vector2(start_x + float(candidate_index) * (card_width + candidate_gap), 0.0)


## 更新本地临时选择和候选牌边框；规则状态在确认按钮点击前保持不变。
func _select_candidate(character_id: String) -> void:
	_selected_character_id = character_id
	for candidate_id_variant: Variant in _candidate_views.keys():
		# 当前候选 ID；与临时选择相同时显示金色选中边框。
		var candidate_id: String = str(candidate_id_variant)
		# 当前候选牌视图；映射只在本次候选重绘期间有效。
		var candidate_view: PlayerTargetView = _candidate_views[candidate_id] as PlayerTargetView
		candidate_view.set_target_state(true, candidate_id == _selected_character_id)
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
	_candidate_views.clear()
	for child: Node in _candidate_area.get_children():
		_candidate_area.remove_child(child)
		child.queue_free()
