extends Control

## 标准身份局演示桌面。界面只提交 PlayerAction 并渲染快照，不直接修改任何对局状态。

## 游戏内座位容器场景；运行时把独立座次标签放在武将牌下方，不把标签混入武将牌编辑场景。
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")

## 正式卡牌视图场景；手牌、木牛“粮”、拖拽预览与不可见牌动画均复用同一完整牌面模型。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 对局控制器节点路径；默认指向同场景根节点下的 MatchController，运行时无需修改。
@export var match_controller_path: NodePath = NodePath("MatchController")

## 对局控制器引用；只调用公开动作与查询接口。
@onready var match_controller: MatchController = get_node(match_controller_path) as MatchController

## 顶栏阶段文本；展示当前回合、阶段与牌堆数量。
@onready var phase_label: Label = %PhaseLabel

## 中央弃牌结算区；其全局中心用于确定卡牌飞行动画的落点，不承载规则状态。
@onready var discard_pile_panel: PanelContainer = %DiscardPilePanel

## 卡牌使用动画层；独立绘制飞牌和目标指示线，不修改快照或提交动作。
@onready var card_use_animation_layer: CardUseAnimationLayer = %CardUseAnimationLayer

## 中央回合文本；显示回合编号与当前行动角色。
@onready var center_turn_label: Label = %CenterTurnLabel

## 中央阶段徽记；使用大号中文阶段名强化当前流程辨识。
@onready var center_phase_label: Label = %CenterPhaseLabel

## 右上角局内菜单组件；统一管理牌名切换、重新开局与下一局人数设置。
@onready var match_menu: MatchMenu = %MatchMenu

## 选将遮罩组件；只渲染裁剪后的候选快照并发出稳定武将 ID 选择请求。
@onready var character_selection_panel: CharacterSelectionPanel = %CharacterSelectionPanel

## 其他玩家与本地玩家状态卡容器；每次快照整体重建以避免状态残留。
@onready var player_grid: DecadeBattleLayout = %PlayerGrid

## 本地玩家装备区文本；固定显示在牌桌左下角，与右下角武将牌分离。
@onready var equipment_label: Label = %EquipmentLabel

## 本地玩家统一武将牌组件；在主场景进入树后从独立武将牌场景实例化并锚定到右下角。
var local_player_card: PlayerTargetView

## 本地玩家运行时座位容器；统一承载右下角武将牌和其下方独立座次标签。
var local_player_seat_slot: Control

## 本地玩家的独立座次标签；只在进入实际对局时创建并写入中文座次号。
var local_player_seat_label: Label

## 本地玩家手牌按钮容器；名称模式切换后会重新渲染。
@onready var hand_container: DecadeHandContainer = %HandContainer

## 本地武将技能按钮容器；每次快照按武将配置重建，预留技能只展示说明不执行规则。
@onready var skill_button_container: HFlowContainer = %SkillButtonContainer

## 技能状态提示；展示技能说明、可用状态与尚未接入规则的提示。
@onready var skill_status_label: Label = %SkillStatusLabel

## 当前选择提示；展示已选牌 UID 与目标顺序。
@onready var selection_label: Label = %SelectionLabel

## 交互步骤提示；根据当前选牌、选目标与规则预览展示下一步操作。
@onready var interaction_guide_label: Label = %InteractionGuideLabel

## 使用牌按钮；将当前选择封装为标准动作。
@onready var use_button: Button = %UseButton

## 重铸按钮；只对配置允许重铸的牌生效，规则核心负责最终校验。
@onready var recast_button: Button = %RecastButton

## 木牛流马按钮；将当前选中的普通手牌存为“粮”，首个已选目标可接收宝物。
@onready var wooden_ox_button: Button = %WoodenOxButton

## 结束出牌按钮；仅本地玩家的出牌阶段可用。
@onready var end_play_button: Button = %EndPlayButton

## 对局日志文本框；只追加规则核心发出的永久语义日志。
@onready var log_view: RichTextLabel = %LogView

## 错误提示文本；显示最近一次被规则核心拒绝的原因。
@onready var error_label: Label = %ErrorLabel

## 最近一次本地可见状态快照；界面刷新与选择校验均以此为准。
var _snapshot: Dictionary = {}

## 当前选中的手牌 UID；未选择时为 -1。
var _selected_card_uid: int = -1

## 当前按点击顺序选择的目标 ID；借刀杀人等牌依赖该顺序。
var _selected_target_ids: Array[int] = []

## 当前手牌 UID 到卡牌视图的映射；每次重绘手牌时整体重建，只用于同步选中视觉。
var _card_views: Dictionary = {}

## 当前技能 ID 到技能按钮视图的映射；预留给主动技能选择状态与冷却状态同步。
var _skill_views: Dictionary = {}

## 当前玩家 ID 到角色目标视图的映射；每次重绘场上角色时整体重建，只用于同步目标高亮。
var _player_views: Dictionary = {}

## 当前已选卡牌的只读规则预览；由 MatchController 查询接口生成，不包含权威对象引用。
var _card_use_preview: Dictionary = {}


## 连接控制器与全局设置，并在首帧启动默认演示对局。
func _ready() -> void:
	_create_local_player_card()
	match_controller.state_changed.connect(_on_state_changed)
	match_controller.log_added.connect(_on_log_added)
	match_controller.action_rejected.connect(_on_action_rejected)
	match_controller.card_presentation_requested.connect(_on_card_presentation_requested)
	match_controller.character_selection_changed.connect(_on_character_selection_changed)
	GameSettings.card_name_mode_changed.connect(_on_card_name_mode_changed)
	match_menu.card_name_toggle_requested.connect(_on_name_mode_pressed)
	match_menu.restart_requested.connect(_on_restart_requested)
	match_menu.set_next_player_count(match_controller.default_player_count)
	character_selection_panel.character_selected.connect(_on_character_selected)
	use_button.pressed.connect(_on_use_pressed)
	%CancelButton.pressed.connect(_on_cancel_pressed)
	recast_button.pressed.connect(_on_recast_pressed)
	wooden_ox_button.pressed.connect(_on_wooden_ox_pressed)
	end_play_button.pressed.connect(_on_end_play_pressed)
	local_player_card.pressed.connect(_on_self_target_pressed)
	local_player_card.card_dropped.connect(_on_card_dropped)
	match_menu.refresh_card_name_text()
	call_deferred("_start_default_match")


## 启动检查器配置的默认对局；延迟到首帧保证自动加载数据已完成。
func _start_default_match() -> void:
	log_view.clear()
	match_controller.start_match()


## 从运行时座位容器创建本地牌；武将牌与座次标签保持独立节点，本地与对手使用同一组合结构。
func _create_local_player_card() -> void:
	# 本地座位容器实例；进入游戏后才创建，负责让独立座次标签始终位于武将牌正下方。
	local_player_seat_slot = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
	local_player_seat_slot.name = "LocalPlayerSeatSlot"
	# 本地武将牌实例；由座位容器中的可编辑场景提供，不包含座次标签节点。
	local_player_card = local_player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
	# 本地座次标签实例；只属于游戏内座位容器，文本会在收到玩家快照后写入。
	local_player_seat_label = local_player_seat_slot.get_node("Seat") as Label
	local_player_card.visible = true
	local_player_seat_slot.z_index = 12
	local_player_seat_slot.anchor_left = 1.0
	local_player_seat_slot.anchor_top = 1.0
	local_player_seat_slot.anchor_right = 1.0
	local_player_seat_slot.anchor_bottom = 1.0
	# 本地完整座位尺寸；直接读取组合场景的原生尺寸，桌面不改写武将牌或座次标签几何信息。
	var local_seat_size: Vector2 = local_player_seat_slot.size
	local_player_seat_slot.offset_left = -16.0 - local_seat_size.x
	local_player_seat_slot.offset_top = -local_seat_size.y
	local_player_seat_slot.offset_right = -16.0
	local_player_seat_slot.offset_bottom = 0.0
	local_player_seat_slot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	local_player_seat_slot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(local_player_seat_slot)


## 接收本地裁剪快照并刷新全部桌面区域。
func _on_state_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if str(_snapshot.get("current_phase", "")) != "character_selection":
		character_selection_panel.close()
	_selected_card_uid = -1
	_selected_target_ids.clear()
	error_label.text = ""
	_render_header()
	_render_players()
	_render_local_hand()
	_refresh_selection_text()


## 渲染顶栏回合与牌堆信息。
func _render_header() -> void:
	# 当前玩家 ID；用于从玩家数组取得显示名。
	var current_player_id: int = int(_snapshot.get("current_player_id", -1))
	# 当前玩家显示名；无对局时使用占位文本。
	var current_player_name: String = "无"
	for player_variant: Variant in _snapshot.get("players", []):
		# 当前玩家快照；与当前 ID 匹配时更新显示名。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == current_player_id:
			current_player_name = str(player.get("display_name", "无"))
			break
	phase_label.text = "第%d回合｜%s｜%s" % [
		int(_snapshot.get("turn_number", 0)),
		current_player_name,
		_phase_text(str(_snapshot.get("current_phase", "setup"))),
	]
	center_turn_label.text = "第%d回合 · %s" % [int(_snapshot.get("turn_number", 0)), current_player_name]
	center_phase_label.text = _phase_text(str(_snapshot.get("current_phase", "setup")))


## 渲染全部玩家状态卡，并为存活角色提供按顺序选择目标的按钮。
func _render_players() -> void:
	player_grid.clear_opponent_views()
	_clear_container(player_grid)
	_player_views.clear()
	# 本地玩家 ID；来自控制器配置，默认0。
	var local_player_id: int = match_controller.local_human_player_id
	# 本地玩家状态快照；用于独立渲染底部区域。
	var local_player_snapshot: Dictionary = {}
	for player_variant: Variant in _snapshot.get("players", []):
		# 当前玩家快照；公共信息与本地私有信息已由核心裁剪。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == local_player_id:
			local_player_snapshot = player
			continue
		# 其他玩家运行时座位容器；武将牌与座次标签是并列节点，进入对局后才按玩家创建。
		var player_seat_slot: Control = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
		# 其他玩家选择按钮；来自座位容器内的可编辑武将牌场景，包含状态摘要、目标高亮与卡牌拖放入口。
		var player_button: PlayerTargetView = player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
		# 其他玩家独立座次标签；仅显示中文座次号，不属于武将牌自身节点树。
		var player_seat_label: Label = player_seat_slot.get_node("Seat") as Label
		# 当前按钮对应的稳定玩家 ID；通过 bind 传入回调。
		var target_id: int = int(player.get("player_id", -1))
		# 当前武将定义；角色组件只读取可选插画路径，不持有全局配置引用。
		var character_definition: Dictionary = GameDatabase.get_character(str(player.get("character_id", "")))
		# 当前武将势力展示元数据；独立配置提供牌面简称、完整名称和主题颜色。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
		player_button.configure_snapshot(player, character_definition, target_id == int(_snapshot.get("current_player_id", -1)), faction_definition)
		player_seat_label.text = _seat_text(target_id + 1)
		player_button.pressed.connect(_on_target_pressed.bind(target_id))
		player_button.card_dropped.connect(_on_card_dropped)
		player_grid.add_child(player_seat_slot)
		_player_views[target_id] = player_button
	_layout_opponent_players()
	if not local_player_snapshot.is_empty():
		# 本地武将定义；统一武将牌从相同静态数据读取名称、插画和势力 ID。
		var local_character_definition: Dictionary = GameDatabase.get_character(str(local_player_snapshot.get("character_id", "")))
		# 本地武将势力展示元数据；与其他玩家使用同一配置入口，避免本地牌面拥有独立硬编码样式。
		var local_faction_definition: Dictionary = GameDatabase.get_faction(str(local_character_definition.get("faction", "")))
		local_player_card.configure_snapshot(local_player_snapshot, local_character_definition, int(local_player_snapshot.get("player_id", -1)) == int(_snapshot.get("current_player_id", -1)), local_faction_definition)
		local_player_seat_label.text = _seat_text(int(local_player_snapshot.get("player_id", -1)) + 1)
		equipment_label.text = _format_local_equipment(local_player_snapshot)
		_render_local_skills(local_player_snapshot)


## 按环桌座次排列其他玩家；优先放置上方座位，超出部分依次放到左右两侧。
func _layout_opponent_players() -> void:
	# 已创建的角色座位容器数组；字典保持插入顺序，与快照中的座次顺序一致。
	var opponent_views: Array[Control] = []
	for player_view_variant: Variant in _player_views.values():
		# 当前武将牌的父容器；容器同时承载独立座次标签，因此环桌布局移动容器而不是牌面本身。
		var player_view: PlayerTargetView = player_view_variant as PlayerTargetView
		# 当前武将牌所属座位容器；Node2D 牌面只提供表现，Control 容器继续负责响应式环桌布局。
		var player_seat_slot: Control = player_view.get_parent() as Control
		if player_seat_slot != null:
			opponent_views.append(player_seat_slot)
	# 对局总人数；座次布局器用该数值选择与无名杀一致的二至十人位置模板。
	var total_player_count: int = (_snapshot.get("players", []) as Array).size()
	player_grid.bind_opponent_views(opponent_views, total_player_count)


## 根据本地武将配置渲染技能按钮；未接入规则的样例技能保持“预留”状态并可查看说明。
func _render_local_skills(local_player: Dictionary) -> void:
	_clear_container(skill_button_container)
	_skill_views.clear()
	skill_status_label.text = "点击技能查看说明"
	# 本地武将定义；技能列表只保存稳定技能 ID。
	var character: Dictionary = GameDatabase.get_character(str(local_player.get("character_id", "")))
	# 武将技能 ID 数组；空数组表示该武将当前没有配置技能。
	var skill_ids: Array = character.get("skills", []) as Array
	if skill_ids.is_empty():
		skill_status_label.text = "当前武将没有已配置技能"
		return
	for skill_id_variant: Variant in skill_ids:
		# 当前技能 ID；用于查询元数据与绑定稳定点击回调。
		var skill_id: String = str(skill_id_variant)
		# 当前技能定义；不存在时构造可诊断占位信息，避免技能栏静默缺项。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		if skill_definition.is_empty():
			skill_definition = {"id":skill_id, "name":skill_id, "description":"技能元数据尚未登记。"}
		# 技能是否已经接入可执行规则；当前 sample_only 技能全部为界面预留状态。
		var skill_available: bool = str(skill_definition.get("trigger", "sample_only")) != "sample_only" and bool(skill_definition.get("ui_enabled", false))
		# 当前技能按钮；组件只展示元数据并发出请求信号。
		var skill_button: SkillButtonView = SkillButtonView.new()
		skill_button.configure(skill_definition, skill_available)
		skill_button.skill_requested.connect(_on_skill_requested)
		skill_button_container.add_child(skill_button)
		_skill_views[skill_id] = skill_button


## 响应技能按钮请求；预留技能展示永久说明，未来主动技能可在此转交独立技能交互控制器。
func _on_skill_requested(skill_id: String) -> void:
	# 被请求的技能定义；用于展示名称、说明和接入状态。
	var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
	# 技能显示名称；元数据缺失时回退到稳定 ID。
	var skill_name: String = str(skill_definition.get("name", skill_id))
	# 技能说明；预留按钮点击后始终向玩家解释当前行为。
	var skill_description: String = str(skill_definition.get("description", "技能元数据尚未登记。"))
	skill_status_label.text = "【%s】%s" % [skill_name, skill_description]
	if str(skill_definition.get("trigger", "sample_only")) == "sample_only":
		error_label.text = "【%s】技能界面已预留，规则效果尚未接入。" % skill_name


## 渲染本地玩家手牌，并根据当前名称模式生成牌面文本。
func _render_local_hand() -> void:
	_clear_container(hand_container)
	_card_views.clear()
	# 本地玩家快照；找不到时保持空字典。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	# 是否轮到本地玩家出牌；决定卡牌与四个动作按钮是否可用。
	var can_act: bool = _can_local_player_act()
	for card_variant: Variant in local_player.get("hand", []):
		# 当前手牌快照；包含 UID、配置 ID、花色与点数。
		var card: Dictionary = card_variant as Dictionary
		# 当前手牌定义；用于双名称与类型提示。
		var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		# 当前手牌节点；正式卡牌场景负责牌面表现，独立输入区域只改变界面选择状态。
		var card_button: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		card_button.visible = true
		# 当前实体牌 UID；通过 bind 传入选择回调。
		var card_uid: int = int(card.get("uid", -1))
		card_button.configure(card, definition, false, can_act)
		card_button.pressed.connect(_on_card_pressed.bind(card_uid))
		card_button.card_drag_started.connect(_on_card_drag_started)
		hand_container.add_child(card_button)
		_card_views[card_uid] = card_button
	for card_variant: Variant in local_player.get("wooden_ox_storage", []):
		# 当前“粮”快照；所有者可像手牌一样选择并使用或打出。
		var card: Dictionary = card_variant as Dictionary
		# 当前“粮”定义；用于双名称与规则提示。
		var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		# 当前“粮”卡牌节点；与普通手牌共用选择 UID、卡牌视觉与使用牌动作。
		var card_button: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		card_button.visible = true
		# 当前“粮”的实体牌 UID；通过 bind 传入选择回调。
		var card_uid: int = int(card.get("uid", -1))
		card_button.configure(card, definition, true, can_act)
		card_button.pressed.connect(_on_card_pressed.bind(card_uid))
		card_button.card_drag_started.connect(_on_card_drag_started)
		hand_container.add_child(card_button)
		_card_views[card_uid] = card_button
	use_button.disabled = true
	recast_button.disabled = not can_act
	wooden_ox_button.disabled = not can_act
	end_play_button.disabled = not can_act
	%CancelButton.visible = false
	recast_button.visible = false
	wooden_ox_button.visible = false


## 返回左下装备区的固定槽位文本；其他玩家装备仍直接显示在其武将牌状态中。
func _format_local_equipment(player: Dictionary) -> String:
	# 本地装备字典；键为weapon、armor、坐骑和treasure等稳定槽位 ID。
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	# 武器显示名；槽位为空时显示“无”。
	var weapon_name: String = _equipment_slot_name(equipment, "weapon")
	# 防具显示名；槽位为空时显示“无”。
	var armor_name: String = _equipment_slot_name(equipment, "armor")
	# 进攻坐骑显示名；槽位为空时显示“无”。
	var offensive_mount_name: String = _equipment_slot_name(equipment, "offensive_mount")
	# 防御坐骑显示名；槽位为空时显示“无”。
	var defensive_mount_name: String = _equipment_slot_name(equipment, "defensive_mount")
	# 宝物显示名；槽位为空时显示“无”。
	var treasure_name: String = _equipment_slot_name(equipment, "treasure")
	return "⚔ 武器　%s\n🛡 防具　%s\n♞ 进攻　%s\n♞ 防御　%s\n◇ 宝物　%s" % [weapon_name, armor_name, offensive_mount_name, defensive_mount_name, treasure_name]


## 按装备槽位返回当前名称模式下的牌名；空槽位统一返回“无”。
func _equipment_slot_name(equipment: Dictionary, slot: String) -> String:
	if not equipment.has(slot):
		return "无"
	# 当前槽位装备快照；只读取定义 ID 解析显示名称。
	var card: Dictionary = equipment.get(slot, {}) as Dictionary
	return GameSettings.resolve_card_name(GameDatabase.get_card(str(card.get("definition_id", ""))))


## 选择或取消一张手牌；切换牌时保留目标，便于快速比较合法性。
## 无名杀式交互以当前牌为完整选择上下文；切换或取消卡牌时会清空旧目标，避免非法目标残留高亮。
func _on_card_pressed(card_uid: int) -> void:
	# 当前点击是否取消已经选中的同一张牌；用于在写入新选择前决定最终 UID。
	var deselecting_current_card: bool = _selected_card_uid == card_uid
	_selected_card_uid = -1 if deselecting_current_card else card_uid
	_selected_target_ids.clear()
	if _selected_card_uid >= 0:
		# 初始规则预览；自身目标与全体目标牌可据此自动整理目标选择。
		var initial_preview: Dictionary = match_controller.get_card_use_preview(match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
		# 当前目标模式；self 自动选择自己，全体目标牌由核心展开且无需保留手动目标。
		var target_mode: String = str(initial_preview.get("target_mode", ""))
		if target_mode == "self":
			_selected_target_ids.assign([match_controller.local_human_player_id])
		elif target_mode == "all_players" or target_mode == "all_others":
			_selected_target_ids.clear()
	error_label.text = ""
	_refresh_selection_text()


## 按点击顺序选择或取消一名目标；最多保留三个目标以支持方天画戟。
func _on_target_pressed(target_id: int) -> void:
	if _selected_target_ids.has(target_id):
		_selected_target_ids.erase(target_id)
	elif _selected_card_uid >= 0 and (_card_use_preview.get("legal_target_ids", []) as Array).has(target_id) and _selected_target_ids.size() < 3:
		_selected_target_ids.append(target_id)
	_refresh_selection_text()


## 拖动卡牌开始时同步选牌状态，使目标组件立即展示该牌的合法投放区域。
func _on_card_drag_started(card_uid: int) -> void:
	if _selected_card_uid != card_uid:
		_on_card_pressed(card_uid)


## 接收角色组件的卡牌拖放结果；拖放与点击共用选牌、选目标和确认提交流程。
func _on_card_dropped(card_uid: int, target_id: int) -> void:
	if _selected_card_uid != card_uid:
		_on_card_pressed(card_uid)
	if not _selected_target_ids.has(target_id):
		_on_target_pressed(target_id)


## 将本地玩家自身加入或移出目标列表。
func _on_self_target_pressed() -> void:
	_on_target_pressed(match_controller.local_human_player_id)


## 提交使用牌动作；所有规则错误由核心返回并显示。
func _on_use_pressed() -> void:
	if _selected_card_uid < 0:
		_on_action_rejected("请先选择一张手牌。")
		return
	# 使用牌标准动作；目标数组按界面点击顺序复制。
	var action: PlayerAction = PlayerAction.new("use_card", match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
	match_controller.submit_action(action)


## 处理无名杀式键盘与右键快捷操作；快捷键只调用现有标准动作，不绕过规则核心。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		# 当前键盘事件；只响应确认、取消和结束出牌三个稳定桌面操作。
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE and _selected_card_uid >= 0:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_ENTER and not use_button.disabled:
			_on_use_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_SPACE and _selected_card_uid < 0 and not end_play_button.disabled:
			_on_end_play_pressed()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		if _selected_card_uid >= 0:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()


## 取消当前选牌与目标，不向规则核心提交任何动作。
func _on_cancel_pressed() -> void:
	_selected_card_uid = -1
	_selected_target_ids.clear()
	error_label.text = ""
	_refresh_selection_text()


## 提交重铸动作；不允许重铸的牌会由核心拒绝。
func _on_recast_pressed() -> void:
	if _selected_card_uid < 0:
		_on_action_rejected("请先选择一张手牌。")
		return
	match_controller.submit_action(PlayerAction.new("recast_card", match_controller.local_human_player_id, _selected_card_uid))


## 提交木牛流马存粮动作；若已选择目标，则把宝物与全部“粮”一并转移给首个目标。
func _on_wooden_ox_pressed() -> void:
	if _selected_card_uid < 0:
		_on_action_rejected("请先选择一张要存入木牛流马的手牌。")
		return
	# 木牛流马可选转移目标；只读取选择顺序中的第一名角色。
	var transfer_targets: Array[int] = []
	if not _selected_target_ids.is_empty():
		transfer_targets.append(_selected_target_ids[0])
	match_controller.submit_action(PlayerAction.new("store_wooden_ox", match_controller.local_human_player_id, _selected_card_uid, transfer_targets))


## 提交结束出牌阶段动作。
func _on_end_play_pressed() -> void:
	match_controller.submit_action(PlayerAction.new("end_play", match_controller.local_human_player_id))


## 切换全局卡牌名称模式；所有牌面与装备名称随后统一刷新。
func _on_name_mode_pressed() -> void:
	GameSettings.toggle_card_name_mode()


## 响应名称模式变化并重新渲染现有快照。
func _on_card_name_mode_changed(_mode: GameSettings.NameMode) -> void:
	match_menu.refresh_card_name_text()
	if not _snapshot.is_empty():
		_render_players()
		_render_local_hand()
		_refresh_selection_text()


## 清空日志并使用菜单设置的人数启动下一局；当前对局人数只在重新开局时改变。
func _on_restart_requested(player_count: int) -> void:
	log_view.clear()
	card_use_animation_layer.clear_presentations()
	match_controller.default_player_count = player_count
	match_controller.start_match(player_count)


## 接收观察者裁剪后的选将快照；候选内容只存在于本地选将组件，不写入桌面状态或玩家快照。
func _on_character_selection_changed(selection_snapshot: Dictionary) -> void:
	character_selection_panel.bind_snapshot(selection_snapshot)


## 把选将界面的稳定武将 ID 封装为标准动作，并交由权威控制器再次校验。
func _on_character_selected(character_id: String) -> void:
	# 选将动作；payload 只存放可序列化武将 ID，支持网络、回放和 AI 共用。
	var action: PlayerAction = PlayerAction.new("select_character", match_controller.local_human_player_id)
	action.payload = {"character_id":character_id}
	match_controller.submit_action(action)


## 追加一条规则日志并自动滚动到底部。
func _on_log_added(message: String) -> void:
	log_view.append_text("%s\n" % message)
	log_view.scroll_to_line(maxi(log_view.get_line_count() - 1, 0))


## 接收规则核心的只读卡牌展示请求，并把玩家视图位置转换为动画层局部坐标。
func _on_card_presentation_requested(card_data: Dictionary, actor_id: int, target_ids: Array[int]) -> void:
	# 卡牌定义；用于配置正式卡牌视图，不参与效果判断。
	var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
	# 动画起点；本地玩家使用底部状态区，其他玩家使用对应角色卡中心。
	var start_position: Vector2 = _get_player_animation_position(actor_id)
	# 中央弃牌区落点；所有正常使用牌先飞向该位置展示，装备或延时锦囊的最终规则区域不受影响。
	var discard_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	# 目标位置数组；多目标牌会同时绘制多根使用者到目标的指示线。
	var target_positions: Array[Vector2] = []
	for target_id: int in target_ids:
		target_positions.append(_get_player_animation_position(target_id))
	# 正式卡牌节点；本地牌存在时直接接管同一节点，其他玩家隐藏手牌则实例化同款完整牌面。
	var animated_card: CardView = _card_views.get(int(card_data.get("uid", -1))) as CardView
	if animated_card == null:
		animated_card = CARD_VIEW_SCENE.instantiate() as CardView
		animated_card.configure(card_data, definition, false, false)
		card_use_animation_layer.add_child(animated_card)
		animated_card.position = start_position - animated_card.get_card_size() * 0.5
	card_use_animation_layer.play_card(animated_card, start_position, discard_position, target_positions)


## 返回指定玩家在牌桌上的动画锚点；本地玩家固定使用底部面板中心。
func _get_player_animation_position(player_id: int) -> Vector2:
	if player_id == match_controller.local_human_player_id:
		return _global_to_animation_position(local_player_card.get_global_rect().get_center())
	# 其他玩家角色视图；快照刷新后按稳定玩家 ID 保存。
	var player_view: Control = _player_views.get(player_id) as Control
	if player_view != null and is_instance_valid(player_view):
		return _global_to_animation_position(player_view.get_global_rect().get_center())
	return _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())


## 将屏幕全局坐标转换为全屏动画层局部坐标；动画层无缩放，因此只需扣除其全局原点。
func _global_to_animation_position(global_position: Vector2) -> Vector2:
	return global_position - card_use_animation_layer.get_global_rect().position


## 显示最近一次动作拒绝原因。
func _on_action_rejected(message: String) -> void:
	error_label.text = message


## 更新当前选择摘要，目标以玩家显示名与选择顺序呈现。
func _refresh_selection_text() -> void:
	_card_use_preview = {}
	# 已选目标显示名数组；按选择顺序构建。
	var target_names: Array[String] = []
	for target_id: int in _selected_target_ids:
		# 目标玩家快照；用于从稳定 ID 解析显示名。
		var player: Dictionary = _get_player_snapshot(target_id)
		target_names.append(str(player.get("display_name", "玩家%d" % target_id)))
	if _selected_card_uid < 0:
		selection_label.text = "未选择卡牌｜可点击牌面，或直接拖动卡牌到青色目标"
		interaction_guide_label.text = "请选择要使用的牌"
		use_button.disabled = true
		%CancelButton.visible = false
		recast_button.visible = false
		wooden_ox_button.visible = false
		_refresh_component_states()
		return
	_card_use_preview = match_controller.get_card_use_preview(match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
	# 已选卡牌快照；用于展示名称而不是暴露技术 UID。
	var selected_card: Dictionary = _get_selected_card_snapshot()
	# 已选卡牌定义；用于统一名称模式与说明文本。
	var selected_definition: Dictionary = GameDatabase.get_card(str(selected_card.get("definition_id", "")))
	# 已选卡牌显示名；找不到定义时回退到实体 UID，便于诊断异常数据。
	var selected_card_name: String = GameSettings.resolve_card_name(selected_definition) if not selected_definition.is_empty() else "卡牌 %d" % _selected_card_uid
	selection_label.text = "%s｜目标：%s｜%s" % [
		selected_card_name,
		"由规则自动展开" if str(_card_use_preview.get("target_mode", "")) in ["all_players", "all_others"] else ("无" if target_names.is_empty() else " → ".join(target_names)),
		str(_card_use_preview.get("description", "")),
	]
	if bool(_card_use_preview.get("can_submit", false)):
		interaction_guide_label.text = "请确认当前操作"
	else:
		interaction_guide_label.text = "请选择目标"
	use_button.disabled = not _can_local_player_act() or not bool(_card_use_preview.get("can_submit", false))
	# 当前规则阶段；上下文按钮只在本地可出牌阶段显示，避免像普通面板一样长期占据操作区。
	var can_act: bool = _can_local_player_act()
	# 当前选中卡定义；用于判断重铸标志和木牛流马存粮资格。
	var selected_definition_for_controls: Dictionary = GameDatabase.get_card(str(selected_card.get("definition_id", "")))
	%CancelButton.visible = true
	recast_button.visible = can_act and bool(selected_definition_for_controls.get("recast", false))
	recast_button.disabled = not recast_button.visible
	wooden_ox_button.visible = can_act and _can_store_selected_card()
	wooden_ox_button.disabled = not wooden_ox_button.visible
	_refresh_component_states()


## 判断当前选中实体牌是否来自本地手牌，并且本地装备区存在木牛流马。
func _can_store_selected_card() -> bool:
	if _selected_card_uid < 0:
		return false
	# 本地玩家快照；用于检查选中实体牌区域和宝物槽，不修改任何状态。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	# 选中牌是否位于普通手牌区；木牛“粮”不能再次存入木牛流马。
	var selected_is_hand_card: bool = false
	for card_variant: Variant in local_player.get("hand", []):
		# 当前手牌快照；UID 匹配时确认牌不是木牛“粮”。
		var card: Dictionary = card_variant as Dictionary
		if int(card.get("uid", -1)) == _selected_card_uid:
			selected_is_hand_card = true
			break
	if not selected_is_hand_card:
		return false
	# 本地装备字典；木牛流马必须位于宝物槽才能存入“粮”。
	var equipment: Dictionary = local_player.get("equipment", {}) as Dictionary
	# 当前宝物槽快照；定义 ID 为 muniu 时允许显示存粮按钮。
	var treasure: Dictionary = equipment.get("treasure", {}) as Dictionary
	return str(treasure.get("definition_id", "")) == "muniu"


## 同步所有动态卡牌与角色组件的选中、合法目标和目标顺序视觉。
func _refresh_component_states() -> void:
	for card_uid_variant: Variant in _card_views.keys():
		# 当前卡牌 UID；用于判断该视图是否对应已选实体牌。
		var card_uid: int = int(card_uid_variant)
		(_card_views[card_uid] as CardView).set_selected_state(card_uid == _selected_card_uid)
	# 合法目标 ID 数组；没有选牌时为空，角色卡保持普通状态。
	var legal_target_ids: Array = _card_use_preview.get("legal_target_ids", []) as Array
	for player_id_variant: Variant in _player_views.keys():
		# 当前角色 ID；用于同步合法与已选状态。
		var player_id: int = int(player_id_variant)
		(_player_views[player_id] as PlayerTargetView).set_target_state(legal_target_ids.has(player_id), _selected_target_ids.has(player_id))
	# 本地玩家目标按钮；自身目标合法或已选择时使用与角色卡一致的颜色语义。
	var self_is_legal: bool = legal_target_ids.has(match_controller.local_human_player_id)
	var self_is_selected: bool = _selected_target_ids.has(match_controller.local_human_player_id)
	local_player_card.set_target_state(self_is_legal, self_is_selected)


## 返回当前选中卡牌的本地可见快照，包含手牌与木牛流马“粮”。
func _get_selected_card_snapshot() -> Dictionary:
	# 本地玩家快照；只有本地观察者能读取手牌和“粮”的完整牌面。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	for card_variant: Variant in local_player.get("hand", []):
		# 当前手牌快照；UID 匹配时返回深拷贝避免界面修改源字典。
		var card: Dictionary = card_variant as Dictionary
		if int(card.get("uid", -1)) == _selected_card_uid:
			return card.duplicate(true)
	for card_variant: Variant in local_player.get("wooden_ox_storage", []):
		# 当前“粮”快照；与手牌使用相同 UID 查找规则。
		var card: Dictionary = card_variant as Dictionary
		if int(card.get("uid", -1)) == _selected_card_uid:
			return card.duplicate(true)
	return {}


## 判断当前是否为本地玩家的有效出牌阶段；所有交互控件共用该条件。
func _can_local_player_act() -> bool:
	return int(_snapshot.get("current_player_id", -1)) == match_controller.local_human_player_id and str(_snapshot.get("current_phase", "")) == "play" and not bool(_snapshot.get("game_over", false))


## 按玩家 ID 返回当前快照中的玩家字典。
func _get_player_snapshot(player_id: int) -> Dictionary:
	for player_variant: Variant in _snapshot.get("players", []):
		# 当前玩家快照；ID 匹配时返回其深拷贝以避免界面误改原快照。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player.duplicate(true)
	return {}


## 删除容器全部子节点；节点排队释放后不再参与后续布局。
func _clear_container(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


## 将阶段 ID 转换为中文界面文本。
func _phase_text(phase: String) -> String:
	return {"setup":"准备", "character_selection":"选将阶段", "start":"开始阶段", "judgment":"判定阶段", "draw":"摸牌阶段", "play":"出牌阶段", "discard":"弃牌阶段", "finish":"结束阶段", "game_over":"对局结束"}.get(phase, phase)


## 返回一至十号座次的中文数字；座次标签属于游戏内座位容器，超出当前模式上限时回退阿拉伯数字。
func _seat_text(seat_number: int) -> String:
	return {1:"一", 2:"二", 3:"三", 4:"四", 5:"五", 6:"六", 7:"七", 8:"八", 9:"九", 10:"十"}.get(seat_number, str(seat_number))
