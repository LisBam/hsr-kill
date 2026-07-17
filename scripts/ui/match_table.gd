extends Control

## 标准身份局演示桌面。界面只提交 PlayerAction 并渲染快照，不直接修改任何对局状态。

## 游戏内座位容器场景；运行时把独立座次标签放在武将牌下方，不把标签混入武将牌编辑场景。
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")

## 正式卡牌视图场景；手牌、木牛“粮”、拖拽预览与不可见牌动画均复用同一完整牌面模型。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 中央确定与取消按钮的固定最小尺寸；146×42像素与界面文档的主操作规格一致。
const ACTION_BUTTON_MINIMUM_SIZE: Vector2 = Vector2(146.0, 42.0)

## 中央确定与取消按钮的水平间距；默认28像素避免两个相反命令视觉粘连，运行时无需修改。
const ACTION_BUTTON_SEPARATION: int = 28

## 右侧回合结束按钮的固定最小尺寸；112×36像素弱于中央确认命令但仍保持稳定命中区域，运行时无需修改。
const END_PLAY_BUTTON_MINIMUM_SIZE: Vector2 = Vector2(112.0, 36.0)

## 回合结束按钮相对主场景右下锚点的固定矩形；位置位于取消按钮右侧、技能栏上方且不遮挡中央操作。
const END_PLAY_BUTTON_OFFSETS: Rect2 = Rect2(-310.0, -218.0, 112.0, 36.0)

## 回合结束按钮的危险操作背景色；朱红色与普通暖金确认按钮区分，运行时无需修改。
const END_PLAY_BUTTON_COLOR: Color = Color("8f302d")

## 回合结束按钮的危险操作边框色；默认使用较亮朱红保证深色牌桌上的轮廓可见，运行时无需修改。
const END_PLAY_BUTTON_BORDER_COLOR: Color = Color("e06a61")

## “不响应该锦囊”开启后的深灰背景色；只表达当前锦囊跳过无懈询问，不改变按钮尺寸或其他规则状态。
const SUPPRESSED_TRICK_BUTTON_COLOR: Color = Color("292826")

## “不响应该锦囊”开启后的低亮度边框色；与普通朱红回合结束按钮保持明确区分。
const SUPPRESSED_TRICK_BUTTON_BORDER_COLOR: Color = Color("5b5751")

## 技能区相对主场景右边缘的固定右边界；与右下本地武将牌保留27.35像素间隔。
## 当前布局将安全间隔收紧为12像素，使技能按钮靠近本地武将牌，同时由手牌右边界计算继续保留8像素隔离。
## 当前最终间隔进一步收紧为6像素，仍由独立手牌边界保留8像素安全区，技能按钮不会覆盖手牌信息。
const LOCAL_SKILL_RIGHT_OFFSET: float = -170.35

## 技能区相对主场景底边的固定下边界；与本地武将牌牌面底边对齐，不占用座次标签区域。
const LOCAL_SKILL_BOTTOM_OFFSET: float = -26.0

## 手牌区与最左侧技能按钮之间的水平间距；默认8像素保持两个交互区域相邻但不重叠。
const HAND_SKILL_GAP: float = 8.0

## 本地武将座位左边界相对主场景右边缘的偏移；无技能时手牌栏延伸到该边界左侧。
const LOCAL_PLAYER_SEAT_LEFT_OFFSET: float = -164.35

## 本地装备区与手牌区的统一高度；175像素覆盖148像素牌面、18像素选中抬升及悬停缩放余量。
const LOCAL_CARD_AREA_HEIGHT: float = 175.0

## 本地装备栏的独立高度；148像素严格等于单张玩家手牌牌面高度，不包含手牌栏的选中抬升预留空间。
const LOCAL_EQUIPMENT_AREA_HEIGHT: float = 148.0

## 本地五个装备槽之间的统一纵向间距；默认3像素，与装备组件和界面文档保持一致。
## 当前第一视角固定使用10像素间距，配合五个27像素槽位恰好填满175像素装备栏高度。
## 当前五个装备槽连续排列，不在相邻槽位之间保留任何空隙。
const LOCAL_EQUIPMENT_ROW_GAP: float = 0.0

## 本地装备槽的统一覆盖量；默认0表示五槽互不覆盖，全部间距都由同一个间距参数控制。
const LOCAL_EQUIPMENT_ROW_OVERLAP: float = 0.0

## 每秒包含的毫秒数；对局时长使用单调时钟换算，不受系统时间调整影响。
const MILLISECONDS_PER_SECOND: int = 1000

## 每分钟包含的秒数；左上角时长固定格式化为“分:秒”。
const SECONDS_PER_MINUTE: int = 60

## 本地玩家目标指示锚点与手牌区顶边的垂直间距；默认8像素让线端点位于手牌上方且不遮挡牌面，运行时通常无需修改。
@export_range(0.0, 48.0, 1.0) var local_hand_indicator_margin: float = 8.0

## 本地获得牌动画起点距离手牌区右边缘的额外间距；默认24像素让新牌从区域外清晰进入，运行时可按主题调整。
@export_range(0.0, 96.0, 1.0) var local_hand_gain_entry_margin: float = 24.0

## 本地正式获得牌从右侧进入手牌布局的持续时间；默认0.42秒与通用飞牌节奏一致，可在检查器中独立调整。
@export_range(0.1, 1.5, 0.01) var local_hand_gain_duration: float = 0.42

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

## 程序化牌桌背景组件；主题切换时只接收风格标识并重绘，不读取设置菜单或对局状态。
@onready var reference_backdrop: ReferenceBackdrop = $ReferenceBackdrop

## 中央回合文本；显示回合编号与当前行动角色。
@onready var center_turn_label: Label = %CenterTurnLabel

## 中央阶段徽记；使用大号中文阶段名强化当前流程辨识。
@onready var center_phase_label: Label = %CenterPhaseLabel

## 右上角局内菜单组件；统一管理牌名切换、重新开局与下一局人数设置。
@onready var match_menu: MatchMenu = %MatchMenu

## 选将遮罩组件；只渲染裁剪后的候选快照并发出稳定武将 ID 选择请求。
@onready var character_selection_panel: CharacterSelectionPanel = %CharacterSelectionPanel

## 通用卡牌选择组件；响应、弃牌、目标区域和展示牌选择都复用该面板。
@onready var card_selection_panel: CardSelectionPanel = $CardSelectionPanel

## 其他玩家与本地玩家状态卡容器；每次快照整体重建以避免状态残留。
@onready var player_grid: DecadeBattleLayout = %PlayerGrid

## 本地玩家装备区文本；固定显示在牌桌左下角，与右下角武将牌分离。
## 当前节点已重构为独立装备堆叠组件；保留原变量名以避免破坏桌面脚本既有引用。
@onready var equipment_label: EquipmentStackView = %EquipmentStack

## 本地玩家统一武将牌组件；在主场景进入树后从独立武将牌场景实例化并锚定到右下角。
var local_player_card: PlayerTargetView

## 本地玩家运行时座位容器；统一承载右下角武将牌和其下方独立座次标签。
var local_player_seat_slot: Control

## 本地玩家的独立座次标签；只在进入实际对局时创建并写入中文座次号。
var local_player_seat_label: Label

## 本地玩家手牌按钮容器；名称模式切换后会重新渲染。
@onready var hand_container: DecadeHandContainer = %HandContainer

## 本地手牌可视滚动区域；获得牌动画以其右边缘作为入场起点，不使用可能超宽的内容容器边界。
@onready var hand_scroll: ScrollContainer = $HandPanel/HandScroll

## 本地手牌透明外层；技能数量变化时只调整右边界，不改变175像素固定高度。
@onready var hand_panel: PanelContainer = $HandPanel

## 本地技能透明外层；尺寸严格跟随当前一列或两列按钮，不绘制独立背景框。
@onready var skill_bar: PanelContainer = $SkillBar

## 本地武将技能按钮容器；使用基础容器类型接收旧场景缓存，进入_ready后统一升级为SkillButtonGrid。
@onready var skill_button_container: Container = %SkillButtonContainer

## 技能状态提示；展示技能说明、可用状态与尚未接入规则的提示。
@onready var skill_status_label: Label = %SkillStatusLabel

## 当前选择提示；展示已选牌 UID 与目标顺序。
@onready var selection_label: Label = %SelectionLabel

## 本地行动交互区；只在当前存在需要本地玩家确认、取消或选择的操作时显示，背景保持完全透明。
## 该节点是主场景根节点的固定直属子节点，使用直接路径避免场景唯一名称元数据缺失时返回空实例。
@onready var interaction_panel: PanelContainer = $InteractionPanel

## 交互步骤提示；根据当前选牌、选目标与规则预览展示下一步操作。
@onready var interaction_guide_label: Label = %InteractionGuideLabel

## 使用牌按钮；将当前选择封装为标准动作。
@onready var use_button: Button = %UseButton

## 重铸按钮；只对配置允许重铸的牌生效，规则核心负责最终校验。
## 该节点仅为旧场景兼容而保留并始终隐藏；实际重铸入口是无目标选择【铁索连环】后点击中央“确定”。
@onready var recast_button: Button = %RecastButton

## 结束出牌按钮；仅本地玩家的出牌阶段可用。
@onready var end_play_button: Button = %EndPlayButton

## 对局日志文本框；只追加规则核心发出的永久语义日志。
@onready var log_view: RichTextLabel = %LogView

## 可折叠对局日志组件；只读取其展开信号，离线暂停所有权由牌桌统一维护。
@onready var match_log_panel: MatchLogPanel = $LogPanel

## 错误提示文本；显示最近一次被规则核心拒绝的原因。
@onready var error_label: Label = %ErrorLabel

## 最近一次本地可见状态快照；界面刷新与选择校验均以此为准。
var _snapshot: Dictionary = {}

## 最近一次快照中每名玩家的公开体力；键为稳定玩家 ID，用于检测本次快照是否发生真实体力下降。
var _player_hp_by_id: Dictionary = {}

## 当前体力对账所属对局 ID；重新开局时先建立新基线，不能把新局初始体力误判为受伤。
var _hp_snapshot_match_id: String = ""

## 是否已经建立过至少一份体力基线；允许测试快照使用空对局 ID 时仍区分首次绑定与后续更新。
var _has_hp_snapshot: bool = false

## 当前选中的手牌 UID；未选择时为 -1。
var _selected_card_uid: int = -1

## 当前按点击顺序选择的目标 ID；借刀杀人等牌依赖该顺序。
var _selected_target_ids: Array[int] = []

## 当前因唯一合法候选而自动锁定的目标 ID；默认-1表示玩家仍可自行选择或取消目标。
var _auto_locked_target_id: int = -1

## 当前手牌 UID 到正式卡牌视图的映射；快照刷新按 UID 复用节点，实体离开本人牌区后才移除。
var _card_views: Dictionary = {}

## 已收到转移信号、等待正式手牌节点进入当前快照的本地获得牌 UID 集合；键为实体 UID，值固定为 true。
var _pending_local_hand_gain_uids: Dictionary = {}

## 正在从手牌区右侧进入的正式手牌 UID 到补间映射；快照刷新复用同一节点，不会创建或销毁替代牌面。
var _local_hand_gain_tweens: Dictionary = {}

## 已播放实际使用展示且最终应进入弃牌堆的实体 UID 集合；响应等待超过展示时长后仍用于阻止重复弃牌动画。
## 兼容旧调试字段；实际所有权已由 CardUseAnimationLayer 管理，本字典不再写入业务状态并始终保持为空。
var _presented_discard_card_uids: Dictionary = {}

## 当前技能 ID 到技能按钮视图的映射；预留给主动技能选择状态与冷却状态同步。
var _skill_views: Dictionary = {}

## 当前玩家 ID 到角色目标视图的映射；每次重绘场上角色时整体重建，只用于同步目标高亮。
## 当前字典只重建轻量 ID 索引，实际座位节点由 _player_seat_slots 持续复用，不再随快照释放。
var _player_views: Dictionary = {}

## 当前玩家 ID 到持久座位容器的映射；默认空字典，节点只在玩家进入、离开或本地观察者座次改变时创建和释放。
var _player_seat_slots: Dictionary = {}

## 最近一次已经渲染技能栏的本地武将 ID；空字符串表示尚未绑定或当前仍处于选将阶段。
var _rendered_skill_character_id: String = ""

## 当前已选卡牌的只读规则预览；由 MatchController 查询接口生成，不包含权威对象引用。
var _card_use_preview: Dictionary = {}

## 当前在本地手牌区完成的选择请求快照；空字典表示使用普通出牌交互或独立选择窗口。
var _inline_card_choice: Dictionary = {}

## 当前内联请求中按点击顺序选择的实体牌 UID；支持弃牌阶段一次选择多张手牌。
var _inline_selected_card_uids: Array[int] = []

## 当前独立选择窗口的请求 ID；默认-1表示窗口关闭，用于防止旧提交回调关闭同步创建的新窗口。
var _modal_choice_request_id: int = -1

## 当前独立选择窗口的完整请求副本；公共选牌展示刷新时用于决定哪些固定牌位允许本地点击。
var _modal_card_choice_request: Dictionary = {}

## 当前全体观察者可见的公共选牌展示；五谷丰登结算期间持续保留固定牌位与领取归属。
var _public_card_choice_display: Dictionary = {}

## 当前需要作出规则操作的玩家 ID；优先读取活动选择请求，未等待选择时回退当前回合角色。
var _current_operator_player_id: int = -1

## 当前同时处理规则操作的玩家 ID；无懈可击询问使用全体存活名单，不能根据候选牌数量裁剪。
var _simultaneous_operator_player_ids: Array[int] = []

## 当前计时器绑定的对局 ID；对局 ID 变化时重置开始时间，避免重新开局继承旧时长。
var _timed_match_id: String = ""

## 当前对局开始时的单调毫秒时间；默认-1表示尚未收到有效对局快照。
var _match_started_msec: int = -1

## 当前对局结束时的单调毫秒时间；默认-1表示仍在进行，用于终局后冻结显示时长。
var _match_finished_msec: int = -1

## 最近一次写入左上角的整秒时长；默认-1强制首个有效快照立即刷新。
var _last_rendered_duration_seconds: int = -1

## 当前通过点击装备进入的主动交互类型；空字符串表示普通出牌或普通内联选择，具体字符串来自装备定义元数据。
var _active_equipment_action: String = ""

## 当前被点击发动的装备实体 UID；默认-1，提交时核心会再次确认同一装备仍位于原槽位。
var _active_equipment_uid: int = -1

## 当前装备主动交互中按点击顺序选择的普通手牌材料 UID；丈八固定需要2张，木牛固定需要1张。
var _equipment_action_material_uids: Array[int] = []

## 当前客户端为未知玩家身份保存的本地标注；键为稳定玩家 ID，值为忠臣、反贼或内奸身份 ID。
var _identity_marks: Dictionary = {}

## 身份标注弹出菜单当前对应的玩家 ID；默认-1表示没有等待选择的身份徽记。
var _identity_mark_target_id: int = -1

## 身份标注弹出菜单；只提供忠臣、反贼和内奸三个本地标记选项，不包含主公。
## 菜单额外提供“？”作为清除本地推测的入口，四项均只显示单字简写。
var _identity_mark_menu: PopupMenu

## 当前开启“不响应该锦囊”的群体锦囊实体 UID；默认-1表示未开启，牌离开处理区后自动清除。
var _suppressed_group_trick_uid: int = -1

## 当前场景树暂停是否由离线日志展开触发；只有持有该所有权时，收起日志或退出牌桌才恢复运行。
var _owns_log_pause: bool = false

## 当前日志展开持有的对局暂停令牌；-1表示日志没有通过统一接口暂停对局。
var _log_pause_token: int = -1


## 连接控制器与全局设置，并在首帧启动默认演示对局。
func _ready() -> void:
	BattleUIStyle.set_active_style(GameSettings.ui_style_id)
	_ensure_skill_button_grid()
	_configure_local_card_areas()
	_configure_interaction_controls()
	_create_local_player_card()
	_create_identity_mark_menu()
	match_controller.state_changed.connect(_on_state_changed)
	match_controller.log_added.connect(_on_log_added)
	match_controller.action_rejected.connect(_on_action_rejected)
	match_controller.card_presentation_requested.connect(_on_card_presentation_requested)
	match_controller.card_transfer_requested.connect(_on_card_transfer_requested)
	match_controller.card_animation_ownership_reset_requested.connect(_on_card_animation_ownership_reset_requested)
	match_controller.card_choice_requested.connect(_on_card_choice_requested)
	match_controller.public_card_choice_display_changed.connect(_on_public_card_choice_display_changed)
	match_controller.character_selection_changed.connect(_on_character_selection_changed)
	GameSettings.card_name_mode_changed.connect(_on_card_name_mode_changed)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	match_menu.card_name_toggle_requested.connect(_on_name_mode_pressed)
	match_menu.restart_requested.connect(_on_restart_requested)
	match_log_panel.expanded_changed.connect(_on_match_log_expanded_changed)
	match_menu.set_next_player_count(match_controller.default_player_count)
	character_selection_panel.character_selected.connect(_on_character_selected)
	card_selection_panel.choice_submitted.connect(_on_card_choice_submitted)
	card_selection_panel.choice_cancelled.connect(_on_card_choice_cancelled)
	use_button.pressed.connect(_on_use_pressed)
	%CancelButton.pressed.connect(_on_cancel_pressed)
	recast_button.pressed.connect(_on_recast_pressed)
	end_play_button.pressed.connect(_on_end_play_pressed)
	equipment_label.equipment_pressed.connect(_on_equipment_pressed)
	local_player_card.pressed.connect(_on_self_target_pressed)
	local_player_card.card_dropped.connect(_on_card_dropped)
	match_menu.refresh_card_name_text()
	_apply_ui_style()
	call_deferred("_start_default_match")


## 牌桌退出时只释放自身创建的日志暂停，避免场景切换后 SceneTree 残留暂停状态。
func _exit_tree() -> void:
	if _owns_log_pause and match_controller != null and is_instance_valid(match_controller):
		match_controller.release_gameplay_pause(_log_pause_token)
	_owns_log_pause = false
	_log_pause_token = -1


## 在离线模式展开日志时暂停整局；联网模式继续运行，收起时只恢复由本组件拥有的暂停。
func _on_match_log_expanded_changed(expanded: bool) -> void:
	if not expanded:
		if _owns_log_pause:
			match_controller.release_gameplay_pause(_log_pause_token)
			_owns_log_pause = false
			_log_pause_token = -1
		return
	# 当前是否为离线单机模式；LAN 与远程模式不能因本地查看日志暂停权威对局。
	var is_offline_match: bool = match_controller != null and match_controller.network_gateway != null and match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE
	if is_offline_match and not _owns_log_pause:
		_log_pause_token = match_controller.acquire_gameplay_pause("offline_match_log")
		_owns_log_pause = _log_pause_token >= 0


## 把旧主场景中的HFlowContainer替换为专用技能网格；迁移只处理布局组件，不读取或修改武将技能规则。
func _ensure_skill_button_grid() -> void:
	if skill_button_container is SkillButtonGrid:
		return
	# 旧技能容器父节点；缺失时无法保持原场景层级，因此保留现有节点并输出单条诊断。
	var legacy_parent: Node = skill_button_container.get_parent() if skill_button_container != null else null
	if legacy_parent == null:
		push_error("本地技能栏缺少可迁移的 SkillButtonContainer 父节点。")
		return
	# 旧技能容器在父节点中的顺序；替换后保持原有绘制与布局顺序。
	var legacy_index: int = skill_button_container.get_index()
	# 旧节点名称；继续保留唯一名称查询契约，避免其他桌面组件取得不同节点。
	var legacy_name: StringName = skill_button_container.name
	skill_button_container.free()
	# 专用技能网格；只接管按钮方向与间距，按钮内容仍由技能视图组件负责。
	var replacement_grid: SkillButtonGrid = SkillButtonGrid.new()
	replacement_grid.name = legacy_name
	replacement_grid.unique_name_in_owner = true
	legacy_parent.add_child(replacement_grid)
	legacy_parent.move_child(replacement_grid, mini(legacy_index, legacy_parent.get_child_count() - 1))
	replacement_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_button_container = replacement_grid


## 统一底部装备、手牌与技能区的透明样式和高度；旧场景缓存进入树后也会恢复当前布局规格。
func _configure_local_card_areas() -> void:
	# 本地装备外层；148像素高度严格等于玩家手牌牌面本身，底边继续锚定客户区底部。
	var equipment_panel: PanelContainer = $EquipmentPanel
	equipment_panel.offset_top = -LOCAL_EQUIPMENT_AREA_HEIGHT
	equipment_panel.offset_bottom = 0.0
	# 本地手牌外层；175像素继续保留选中抬升与悬停空间，不再作为装备栏高度基准。
	hand_panel.offset_top = -LOCAL_CARD_AREA_HEIGHT
	hand_panel.offset_bottom = 0.0
	equipment_label.equipment_row_gap = LOCAL_EQUIPMENT_ROW_GAP
	equipment_label.equipment_row_overlap = LOCAL_EQUIPMENT_ROW_OVERLAP
	equipment_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	hand_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	skill_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	skill_status_label.visible = false
	skill_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 按整秒刷新左上角对局时长；只更新文本，不驱动任何规则阶段、计时器或 AI 行为。
func _process(_delta: float) -> void:
	_refresh_match_duration_label()


## 统一操作区的运行时节点结构与视觉规格；即使旧场景缺少唯一名称或仍保留旧按钮层级，也能恢复当前交互布局。
func _configure_interaction_controls() -> void:
	interaction_panel.visible = false
	interaction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	use_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	BattleUIStyle.apply_interaction_button(use_button)
	# 中央取消按钮；与确定按钮使用相同尺寸与主按钮样式，避免旧场景资源保留次级按钮外观。
	var cancel_button: Button = %CancelButton
	cancel_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	BattleUIStyle.apply_interaction_button(cancel_button)
	$InteractionPanel/InteractionVBox/ActionRow.add_theme_constant_override("separation", ACTION_BUTTON_SEPARATION)
	recast_button.visible = false
	if end_play_button.get_parent() != self:
		end_play_button.reparent(self)
	end_play_button.visible = false
	end_play_button.custom_minimum_size = END_PLAY_BUTTON_MINIMUM_SIZE
	BattleUIStyle.apply_interaction_button(end_play_button, BattleUIStyle.get_color("end_play_button", END_PLAY_BUTTON_COLOR), BattleUIStyle.get_color("end_play_border", END_PLAY_BUTTON_BORDER_COLOR), true)
	end_play_button.anchor_left = 1.0
	end_play_button.anchor_top = 1.0
	end_play_button.anchor_right = 1.0
	end_play_button.anchor_bottom = 1.0
	end_play_button.offset_left = END_PLAY_BUTTON_OFFSETS.position.x
	end_play_button.offset_top = END_PLAY_BUTTON_OFFSETS.position.y
	end_play_button.offset_right = END_PLAY_BUTTON_OFFSETS.end.x
	end_play_button.offset_bottom = END_PLAY_BUTTON_OFFSETS.end.y
	end_play_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	end_play_button.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 创建未知身份的本地标注菜单；菜单项只影响当前客户端武将牌徽记，不提交任何规则动作。
func _create_identity_mark_menu() -> void:
	_identity_mark_menu = PopupMenu.new()
	_identity_mark_menu.name = "IdentityMarkMenu"
	_identity_mark_menu.add_item("？", 3)
	_identity_mark_menu.add_item("忠", 0)
	_identity_mark_menu.add_item("反", 1)
	_identity_mark_menu.add_item("内", 2)
	_identity_mark_menu.id_pressed.connect(_on_identity_mark_selected)
	add_child(_identity_mark_menu)


## 打开指定未知玩家的身份标注菜单；真实身份已公开或目标为本地玩家时保持无操作。
func _on_identity_badge_pressed(player_id: int) -> void:
	if player_id == match_controller.local_human_player_id:
		return
	# 当前目标公开快照；只有 identity=hidden 时允许创建或修改本地推测。
	var player: Dictionary = _get_player_snapshot(player_id)
	if player.is_empty() or str(player.get("identity", "hidden")) != "hidden":
		return
	_identity_mark_target_id = player_id
	_identity_mark_menu.position = Vector2i(get_viewport().get_mouse_position())
	_identity_mark_menu.popup()


## 保存身份菜单选择并立即刷新对应武将牌；菜单 ID 与身份字符串保持稳定一一映射。
func _on_identity_mark_selected(item_id: int) -> void:
	if _identity_mark_target_id < 0:
		return
	# 当前菜单项对应身份 ID；不存在的菜单项不会写入本地标注字典。
	# 问号使用空字符串表示移除本地推测，不修改任何权威身份数据。
	var identity_mark: String = {0:"loyalist", 1:"rebel", 2:"renegade"}.get(item_id, "")
	if identity_mark.is_empty() and item_id != 3:
		return
	if identity_mark.is_empty():
		_identity_marks.erase(_identity_mark_target_id)
	else:
		_identity_marks[_identity_mark_target_id] = identity_mark
	# 当前目标武将牌；持久座位存在时只刷新身份徽记，不重建其他牌面节点。
	var player_view: PlayerTargetView = _player_views.get(_identity_mark_target_id) as PlayerTargetView
	if player_view != null and is_instance_valid(player_view):
		player_view.set_identity_mark(identity_mark)
	_identity_mark_target_id = -1


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
	local_player_card.set_public_equipment_visible(false)
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
	# 本次体力下降玩家 ID；必须在覆盖旧快照前完成对账，渲染新体力后再播放反馈。
	var damaged_player_ids: Array[int] = _update_player_hp_snapshot(snapshot)
	_snapshot = snapshot.duplicate(true)
	_sync_match_clock()
	if _snapshot.has("processing_card_uids"):
		# 当前公开处理区实体 UID；动画层据此收尾因丢包或中断而未收到最终移牌通知的中央牌面。
		var processing_card_uids: Array[int] = []
		for card_uid_variant: Variant in _snapshot.get("processing_card_uids", []) as Array:
			processing_card_uids.append(int(card_uid_variant))
		card_use_animation_layer.reconcile_processing_card_uids(processing_card_uids)
	if bool(_snapshot.get("game_over", false)):
		# 对局结束会中断尚未产生最终移牌的响应树；中央牌面改为正常停留淡出，避免终局后永久残留。
		card_use_animation_layer.finish_pending_claimed_presentations()
	_public_card_choice_display = (_snapshot.get("public_card_choice_display", {}) as Dictionary).duplicate(true)
	if str(_snapshot.get("current_phase", "")) != "character_selection":
		character_selection_panel.close()
	# 当前运行时请求；用于清理已经完成或中断的旧内联/窗口状态，同时保留同步创建的新请求。
	var runtime_choice: Dictionary = _snapshot.get("current_choice_request", {}) as Dictionary
	# 当前运行时请求 ID；无活动请求时为-1。
	var runtime_request_id: int = int(runtime_choice.get("request_id", -1))
	if not _inline_card_choice.is_empty() and int(_inline_card_choice.get("request_id", -2)) != runtime_request_id:
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
	if _modal_choice_request_id >= 0 and _modal_choice_request_id != runtime_request_id:
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
	_current_operator_player_id = int(runtime_choice.get("actor_id", _snapshot.get("current_player_id", -1)))
	_simultaneous_operator_player_ids.clear()
	# 当前同时响应公共状态；只读取规则层公开的玩家 ID，不从本地候选或手牌亮度反推响应能力。
	var simultaneous_response_display: Dictionary = _snapshot.get("simultaneous_response_display", {}) as Dictionary
	for responder_id_variant: Variant in simultaneous_response_display.get("responder_ids", []) as Array:
		# 当前被同时询问玩家 ID；防御性去重避免异常快照重复刷新同一武将牌。
		var responder_id: int = int(responder_id_variant)
		if responder_id >= 0 and not _simultaneous_operator_player_ids.has(responder_id):
			_simultaneous_operator_player_ids.append(responder_id)
	_selected_card_uid = -1
	_selected_target_ids.clear()
	_auto_locked_target_id = -1
	_clear_equipment_action()
	error_label.text = ""
	_render_header()
	_render_players()
	_play_damage_feedback(damaged_player_ids)
	_render_local_hand()
	_refresh_selection_text()
	_refresh_card_selection_panel()


## 对账新旧公开体力并返回本次真正下降的玩家 ID；首次快照与新对局只建立基线，不播放受伤反馈。
func _update_player_hp_snapshot(snapshot: Dictionary) -> Array[int]:
	# 当前快照对局 ID；空字符串仍是测试和预览允许的稳定对局标识。
	var match_id: String = str(snapshot.get("match_id", ""))
	# 当前是否属于新对局；新对局玩家 ID 可复用，因此必须整体清空旧体力记录。
	var is_new_match: bool = not _has_hp_snapshot or match_id != _hp_snapshot_match_id
	if is_new_match:
		_player_hp_by_id.clear()
		_hp_snapshot_match_id = match_id
		_has_hp_snapshot = true
	# 本次发生体力下降的玩家 ID；同一快照每名玩家最多记录一次。
	var damaged_player_ids: Array[int] = []
	# 下一份体力基线；只保留当前快照仍存在的玩家，人数减少后不会残留旧座次数据。
	var next_player_hp_by_id: Dictionary = {}
	for player_variant: Variant in snapshot.get("players", []) as Array:
		# 当前公开玩家快照；体力属于公开信息，可用于纯表现反馈。
		var player: Dictionary = player_variant as Dictionary
		# 当前稳定玩家 ID；负数异常数据不进入反馈索引。
		var player_id: int = int(player.get("player_id", -1))
		if player_id < 0:
			continue
		# 当前公开体力；允许濒死状态低于0，比较时不进行裁剪。
		var current_hp: int = int(player.get("hp", 0))
		if not is_new_match and _player_hp_by_id.has(player_id) and current_hp < int(_player_hp_by_id.get(player_id, current_hp)):
			damaged_player_ids.append(player_id)
		next_player_hp_by_id[player_id] = current_hp
	_player_hp_by_id = next_player_hp_by_id
	return damaged_player_ids


## 对已经完成新快照渲染的对应武将牌播放受伤反馈；缺失座位安全跳过，不创建临时替代节点。
func _play_damage_feedback(damaged_player_ids: Array[int]) -> void:
	# 当前发生体力下降的稳定玩家 ID；每名玩家在同一快照中最多出现一次。
	for player_id: int in damaged_player_ids:
		if player_id == match_controller.local_human_player_id:
			if local_player_card != null and is_instance_valid(local_player_card):
				local_player_card.play_damage_feedback()
			continue
		# 当前其他玩家武将牌；持久座位索引在本次渲染后已经完成创建或复用。
		var player_view: PlayerTargetView = _player_views.get(player_id) as PlayerTargetView
		if player_view != null and is_instance_valid(player_view):
			player_view.play_damage_feedback()


## 渲染顶栏回合与牌堆信息。
func _render_header() -> void:
	phase_label.text = "第%d轮" % int(_snapshot.get("round_number", 0))
	center_turn_label.text = "牌堆剩余：%d" % int(_snapshot.get("draw_pile_count", 0))
	_refresh_match_duration_label(true)


## 根据最新快照维护本地对局计时边界；重新开局重置起点，终局后冻结终点。
func _sync_match_clock() -> void:
	# 当前快照对局 ID；测试快照允许为空，但同一空 ID 仍只在首次收到时建立一次计时起点。
	var match_id: String = str(_snapshot.get("match_id", ""))
	if _match_started_msec < 0 or match_id != _timed_match_id:
		_timed_match_id = match_id
		_match_started_msec = Time.get_ticks_msec()
		_match_finished_msec = -1
		_last_rendered_duration_seconds = -1
	if bool(_snapshot.get("game_over", false)) and _match_finished_msec < 0:
		_match_finished_msec = Time.get_ticks_msec()


## 把单调时钟差格式化为“对局时长：分:秒”；相同整秒不会重复写入标签。
func _refresh_match_duration_label(force_refresh: bool = false) -> void:
	if center_phase_label == null:
		return
	if _match_started_msec < 0:
		center_phase_label.text = "对局时长：00:00"
		return
	# 计时终点；对局进行中读取当前单调时间，终局后使用冻结时间保持结果稳定。
	var end_msec: int = _match_finished_msec if _match_finished_msec >= 0 else Time.get_ticks_msec()
	# 已经过的完整秒数；负值只可能来自异常时钟数据，统一裁剪为0。
	var elapsed_seconds: int = maxi((end_msec - _match_started_msec) / MILLISECONDS_PER_SECOND, 0)
	if not force_refresh and elapsed_seconds == _last_rendered_duration_seconds:
		return
	_last_rendered_duration_seconds = elapsed_seconds
	# 完整分钟数；允许超过59分钟，不在客户端截断长局时长。
	var elapsed_minutes: int = elapsed_seconds / SECONDS_PER_MINUTE
	# 当前分钟内秒数；固定补足两位保持左上角宽度稳定。
	var remaining_seconds: int = elapsed_seconds % SECONDS_PER_MINUTE
	center_phase_label.text = "对局时长：%02d:%02d" % [elapsed_minutes, remaining_seconds]


## 渲染全部玩家状态卡，并为存活角色提供按顺序选择目标的按钮。
func _render_players() -> void:
	player_grid.clear_opponent_views()
	# 下一帧玩家视图索引；按本地相对座次重新插入键，同时复用已有实际节点。
	var next_player_views: Dictionary = {}
	# 本地玩家 ID；由控制器在每局创建时随机分配座次。
	var local_player_id: int = match_controller.local_human_player_id
	# 玩家快照数组；保留权威状态的绝对座次顺序，之后再相对本地座次旋转。
	var player_snapshots: Array[Dictionary] = []
	for player_variant: Variant in _snapshot.get("players", []):
		player_snapshots.append(player_variant as Dictionary)
	# 本地玩家状态快照；用于独立渲染底部区域。
	var local_player_snapshot: Dictionary = {}
	# 本地玩家在座次数组中的索引；用于让右侧首位始终是本地玩家的下家。
	var local_player_index: int = -1
	for player_index: int in range(player_snapshots.size()):
		if int(player_snapshots[player_index].get("player_id", -1)) == local_player_id:
			local_player_index = player_index
			local_player_snapshot = player_snapshots[player_index]
			break
	if local_player_index < 0:
		return
	# 本次快照需要保留的对手玩家 ID；本地玩家使用独立固定座位，不进入该集合。
	var desired_opponent_ids: Array[int] = []
	for seat_offset: int in range(1, player_snapshots.size()):
		desired_opponent_ids.append(int(player_snapshots[(local_player_index + seat_offset) % player_snapshots.size()].get("player_id", -1)))
	# 已经不属于对手集合的旧座位；重开随机本地座次或人数减少时才会进入该清理分支。
	for existing_player_id_variant: Variant in _player_seat_slots.keys():
		# 旧座位对应玩家 ID；用于和本次对手集合做稳定身份对账。
		var existing_player_id: int = int(existing_player_id_variant)
		if desired_opponent_ids.has(existing_player_id):
			continue
		# 待释放座位容器；先从布局树移除再排队释放，下一次布局不会访问旧节点。
		var stale_seat_slot: Control = _player_seat_slots.get(existing_player_id) as Control
		if stale_seat_slot != null and is_instance_valid(stale_seat_slot):
			if stale_seat_slot.get_parent() == player_grid:
				player_grid.remove_child(stale_seat_slot)
			stale_seat_slot.queue_free()
		_player_seat_slots.erase(existing_player_id)
	for seat_offset: int in range(1, player_snapshots.size()):
		# 当前玩家快照；从本地下家开始环形读取，确保视觉方位与规则行动顺序一致。
		var player: Dictionary = player_snapshots[(local_player_index + seat_offset) % player_snapshots.size()]
		# 当前按钮对应的稳定玩家 ID；通过持久组件自身字段读取点击目标，无需每帧重新绑定信号。
		var target_id: int = int(player.get("player_id", -1))
		# 其他玩家运行时座位容器；武将牌与座次标签是并列节点，进入对局后才按玩家创建。
		var player_seat_slot: Control = _player_seat_slots.get(target_id) as Control
		# 本次是否新建座位；只有新节点需要连接一次输入信号，持续复用时不重复构造 Callable。
		var player_seat_slot_was_created: bool = false
		if player_seat_slot == null or not is_instance_valid(player_seat_slot):
			player_seat_slot = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
			_player_seat_slots[target_id] = player_seat_slot
			player_grid.add_child(player_seat_slot)
			player_seat_slot_was_created = true
		# 其他玩家选择按钮；来自座位容器内的可编辑武将牌场景，包含状态摘要、目标高亮与卡牌拖放入口。
		var player_button: PlayerTargetView = player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
		player_button.set_match_overlays_visible(true)
		if player_seat_slot_was_created:
			player_button.pressed.connect(_on_persistent_target_pressed.bind(player_button))
			player_button.card_dropped.connect(_on_card_dropped)
			player_button.identity_pressed.connect(_on_identity_badge_pressed)
		# 其他玩家独立座次标签；仅显示中文座次号，不属于武将牌自身节点树。
		var player_seat_label: Label = player_seat_slot.get_node("Seat") as Label
		# 当前按钮对应的稳定玩家 ID；通过 bind 传入回调。
		# 当前武将定义；角色组件只读取可选插画路径，不持有全局配置引用。
		var character_definition: Dictionary = GameDatabase.get_character(str(player.get("character_id", "")))
		# 当前武将势力展示元数据；独立配置提供牌面简称、完整名称和主题颜色。
		var faction_definition: Dictionary = GameDatabase.get_faction(str(character_definition.get("faction", "")))
		player_button.configure_snapshot(player, character_definition, target_id == int(_snapshot.get("current_player_id", -1)), faction_definition)
		player_button.set_operation_state(target_id == _current_operator_player_id or _simultaneous_operator_player_ids.has(target_id))
		# 当前公开身份；身份已经展示时清理旧本地标注，未知身份继续显示当前客户端的推测结果。
		var public_identity: String = str(player.get("identity", "hidden"))
		if public_identity != "hidden":
			_identity_marks.erase(target_id)
		player_button.set_identity_mark(str(_identity_marks.get(target_id, "")))
		player_seat_label.text = _seat_text(int(player.get("seat_number", target_id + 1)))
		player_grid.move_child(player_seat_slot, seat_offset - 1)
		next_player_views[target_id] = player_button
	_player_views = next_player_views
	_layout_opponent_players()
	# 本地武将定义；统一武将牌从相同静态数据读取名称、插画和势力 ID。
	var local_character_definition: Dictionary = GameDatabase.get_character(str(local_player_snapshot.get("character_id", "")))
	# 本地武将势力展示元数据；与其他玩家使用同一配置入口，避免本地牌面拥有独立硬编码样式。
	var local_faction_definition: Dictionary = GameDatabase.get_faction(str(local_character_definition.get("faction", "")))
	local_player_card.configure_snapshot(local_player_snapshot, local_character_definition, int(local_player_snapshot.get("player_id", -1)) == int(_snapshot.get("current_player_id", -1)), local_faction_definition)
	local_player_card.set_operation_state(int(local_player_snapshot.get("player_id", -1)) == _current_operator_player_id or _simultaneous_operator_player_ids.has(int(local_player_snapshot.get("player_id", -1))))
	local_player_card.set_public_equipment_visible(false)
	local_player_card.set_match_overlays_visible(true)
	local_player_seat_label.text = _seat_text(int(local_player_snapshot.get("seat_number", int(local_player_snapshot.get("player_id", -1)) + 1)))
	_render_local_equipment(local_player_snapshot)
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
	# 当前本地武将 ID；技能元数据只随武将变化，体力、手牌和回合刷新不需要重建技能按钮。
	var local_character_id: String = str(local_player.get("character_id", ""))
	if _rendered_skill_character_id == local_character_id:
		for skill_id_variant: Variant in _skill_views.keys():
			# 当前已存在按钮的技能 ID；相同武将只刷新动态可发动状态，不重建节点。
			var skill_id: String = str(skill_id_variant)
			# 当前技能定义；按钮名称和说明继续来自独立技能文件的元数据。
			var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
			# 当前主动技能可用状态；被动技能和样例技能始终不显示为可点击发动。
			var skill_available: bool = bool(skill_definition.get("ui_enabled", false)) and match_controller.can_activate_skill(match_controller.local_human_player_id, skill_id)
			(_skill_views[skill_id] as SkillButtonView).configure(skill_definition, skill_available)
		_layout_local_skill_area(_skill_views.size())
		return
	_rendered_skill_character_id = local_character_id
	_clear_container(skill_button_container)
	_skill_views.clear()
	skill_status_label.text = ""
	# 本地武将定义；技能列表只保存稳定技能 ID。
	var character: Dictionary = GameDatabase.get_character(local_character_id)
	# 武将技能 ID 数组；空数组表示该武将当前没有配置技能。
	var skill_ids: Array = character.get("skills", []) as Array
	if skill_ids.is_empty():
		_layout_local_skill_area(0)
		return
	for skill_id_variant: Variant in skill_ids:
		# 当前技能 ID；用于查询元数据与绑定稳定点击回调。
		var skill_id: String = str(skill_id_variant)
		# 当前技能定义；不存在时构造可诊断占位信息，避免技能栏静默缺项。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		if skill_definition.is_empty():
			skill_definition = {"id":skill_id, "name":skill_id, "description":"技能元数据尚未登记。"}
		# 技能是否当前可主动发动；技能文件负责阶段、次数、资源与其他动态条件。
		var skill_available: bool = bool(skill_definition.get("ui_enabled", false)) and match_controller.can_activate_skill(match_controller.local_human_player_id, skill_id)
		# 当前技能按钮；组件只展示元数据并发出请求信号。
		var skill_button: SkillButtonView = SkillButtonView.new()
		skill_button.configure(skill_definition, skill_available)
		skill_button.skill_requested.connect(_on_skill_requested)
		skill_button_container.add_child(skill_button)
		_skill_views[skill_id] = skill_button
	_layout_local_skill_area(skill_ids.size())


## 按技能数量收紧透明技能区，并让手牌栏右边界延伸到第一或第二个技能按钮旁。
func _layout_local_skill_area(skill_count: int) -> void:
	# 当前有效技能数量；负数配置按0处理，避免生成反向尺寸。
	var safe_skill_count: int = maxi(skill_count, 0)
	if safe_skill_count == 0:
		skill_bar.visible = false
		hand_panel.offset_right = LOCAL_PLAYER_SEAT_LEFT_OFFSET - HAND_SKILL_GAP
		return
	# 当前首个技能按钮；动态按钮共用相同尺寸，缺失时回退组件默认62×44像素。
	var first_skill_button: SkillButtonView
	if not _skill_views.is_empty():
		first_skill_button = _skill_views.values()[0] as SkillButtonView
	# 当前单个技能按钮尺寸；直接读取组件暴露参数，使检查器调整后布局仍保持一致。
	var button_size: Vector2 = Vector2(first_skill_button.button_width, first_skill_button.button_height) if first_skill_button != null else Vector2(62.0, 44.0)
	# 专用技能网格；_ready阶段已把旧容器迁移为该组件，空值仅表示场景结构已被外部破坏。
	var skill_grid: SkillButtonGrid = skill_button_container as SkillButtonGrid
	if skill_grid == null:
		push_error("本地技能栏未能初始化 SkillButtonGrid。")
		return
	# 当前实际列数；一个技能只占右侧一列，两个及以上固定占满两列。
	var column_count: int = mini(safe_skill_count, skill_grid.maximum_columns)
	# 当前实际层数；第三个技能开始放到第二层并继续向上扩展。
	var row_count: int = ceili(float(safe_skill_count) / float(maxi(skill_grid.maximum_columns, 1)))
	# 当前技能透明区域尺寸；只包含按钮和按钮间距，不额外保留背景内边距。
	var skill_area_size: Vector2 = Vector2(
		button_size.x * float(column_count) + skill_grid.horizontal_gap * float(maxi(column_count - 1, 0)),
		button_size.y * float(row_count) + skill_grid.vertical_gap * float(maxi(row_count - 1, 0))
	)
	skill_bar.visible = true
	skill_bar.offset_right = LOCAL_SKILL_RIGHT_OFFSET
	skill_bar.offset_left = LOCAL_SKILL_RIGHT_OFFSET - skill_area_size.x
	skill_bar.offset_bottom = LOCAL_SKILL_BOTTOM_OFFSET
	skill_bar.offset_top = LOCAL_SKILL_BOTTOM_OFFSET - skill_area_size.y
	# 手牌栏右边界紧贴当前最左技能列；一个技能时自然增长到第一按钮旁，两个及以上缩短到第二按钮旁。
	hand_panel.offset_right = skill_bar.offset_left - HAND_SKILL_GAP
	skill_grid.queue_sort()


## 响应技能按钮请求；预留技能展示永久说明，可主动发动的技能通过统一 PlayerAction 进入规则核心。
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
		return
	if not bool(skill_definition.get("ui_enabled", false)):
		error_label.text = "【%s】不是可由按钮主动发动的技能。" % skill_name
		return
	# 主动技能动作；技能文件自行校验阶段、次数、目标与资源，界面不直接修改任何规则状态。
	var action: PlayerAction = PlayerAction.new("use_skill", match_controller.local_human_player_id)
	action.payload = {"skill_id":skill_id}
	match_controller.submit_action(action)


## 按实体 UID 对账本地玩家手牌，并根据当前名称模式刷新牌面；现有正式节点会持续复用，不因快照刷新整体重建。
func _render_local_hand() -> void:
	# 本地玩家快照；找不到时保持空字典。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	# 是否轮到本地玩家出牌；决定卡牌与四个动作按钮是否可用。
	# 重铸与存木牛兼容节点始终隐藏，因此当前可见操作只由中央确定/取消和右侧回合结束承担。
	var can_act: bool = _can_local_player_act()
	# 当前内联选择候选 UID；存在请求时只有该集合中的本人牌允许点击或拖动。
	var inline_candidate_uids: Array[int] = _get_inline_candidate_uids()
	# 当前是否正在本地手牌区完成选择请求；该状态与普通出牌选择互斥。
	var has_inline_choice: bool = not _inline_card_choice.is_empty()
	# 当前出牌请求候选 UID；普通出牌阶段只开放至少存在一种合法动作的实体牌。
	var play_candidate_uids: Array[int] = _get_play_phase_candidate_uids()
	# 当前装备技能材料候选；主动模式只开放普通手牌，木牛“粮”不会被当作丈八材料或再次存入木牛。
	var equipment_material_candidate_uids: Array[int] = _get_equipment_action_material_candidate_uids()
	# 当前快照中的手牌条目；每项同时记录牌面快照与是否来自木牛流马，数组顺序就是正式手牌显示顺序。
	var desired_card_entries: Array[Dictionary] = []
	# 木牛流马“粮”固定先加入显示数组，使其无论何时获得或刷新都保持在手牌区最左侧。
	for card_variant: Variant in local_player.get("wooden_ox_storage", []):
		# 当前木牛“粮”条目；true 让同一正式牌面显示独立来源标记。
		desired_card_entries.append({"card":(card_variant as Dictionary), "wooden_ox_card":true})
	for card_variant: Variant in local_player.get("hand", []):
		# 当前普通手牌条目；false 表示牌面不显示木牛“粮”来源标记。
		desired_card_entries.append({"card":(card_variant as Dictionary), "wooden_ox_card":false})
	# 当前快照需要保留的实体 UID 集合；用于移除已经离开本人手牌与木牛区域的旧视图。
	var desired_uid_lookup: Dictionary = {}
	for entry: Dictionary in desired_card_entries:
		# 当前条目的实体 UID；稳定 UID 是复用正式 CardView 的唯一身份。
		var desired_card: Dictionary = entry.get("card", {}) as Dictionary
		desired_uid_lookup[int(desired_card.get("uid", -1))] = true
	# 已离开本人牌区的旧实体视图；手牌容器仍持有时由桌面释放，已被出牌动画层接管时只移除映射。
	for existing_uid_variant: Variant in _card_views.keys():
		# 当前旧视图实体 UID；用于查询新快照是否仍需要该节点。
		var existing_uid: int = int(existing_uid_variant)
		if desired_uid_lookup.has(existing_uid):
			continue
		_cancel_local_hand_gain_animation(existing_uid)
		# 当前旧卡牌视图；只有仍位于手牌容器的节点才由本方法释放。
		var existing_view: CardView = _card_views.get(existing_uid) as CardView
		if existing_view != null and is_instance_valid(existing_view) and existing_view.get_parent() == hand_container:
			hand_container.remove_child(existing_view)
			existing_view.queue_free()
	# 不在最新快照中的待入场 UID；转移结果已失效或被后续规则移动，禁止在未来快照中错误启动动画。
	for pending_uid_variant: Variant in _pending_local_hand_gain_uids.keys():
		if not desired_uid_lookup.has(int(pending_uid_variant)):
			_pending_local_hand_gain_uids.erase(pending_uid_variant)
	# 本轮对账后的 UID 到正式视图映射；只包含当前快照仍属于本人牌区的节点。
	var next_card_views: Dictionary = {}
	# 当前按快照顺序排列的正式手牌节点；对账完成后统一调整子节点顺序并计算最终落点。
	var ordered_card_views: Array[CardView] = []
	for entry: Dictionary in desired_card_entries:
		# 当前牌面快照；包含配置 ID、花色、点数、区域和稳定 UID。
		var card: Dictionary = entry.get("card", {}) as Dictionary
		# 当前实体 UID；用于查找并复用已有正式牌面节点。
		var card_uid: int = int(card.get("uid", -1))
		# 当前牌面定义；用于双名称、类别和插画刷新。
		var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		# 当前牌是否来自木牛流马；只改变来源标记，不改变实体 UID 或节点身份。
		var wooden_ox_card: bool = bool(entry.get("wooden_ox_card", false))
		# 当前手牌是否允许交互；响应与普通出牌均以权威请求候选为准，不能只按阶段整体启用。
		var card_interactable: bool = equipment_material_candidate_uids.has(card_uid) if not _active_equipment_action.is_empty() else (inline_candidate_uids.has(card_uid) if has_inline_choice else can_act and play_candidate_uids.has(card_uid))
		# 当前正式手牌视图；优先复用同 UID 节点，缺失或不在手牌容器时才创建新节点。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			card_view = _create_local_hand_card_view(card_uid)
		card_view.configure(card, definition, wooden_ox_card, card_interactable)
		next_card_views[card_uid] = card_view
		ordered_card_views.append(card_view)
	_card_views = next_card_views
	# 当前正式手牌顺序索引；把复用或新建的节点顺序与权威快照数组保持一致。
	for card_index: int in range(ordered_card_views.size()):
		hand_container.move_child(ordered_card_views[card_index], card_index)
	hand_container.layout_cards_now()
	_start_pending_local_hand_gain_animations()
	use_button.disabled = true
	recast_button.disabled = not can_act
	end_play_button.disabled = not can_act
	%CancelButton.visible = false
	%CancelButton.disabled = false
	recast_button.visible = false


## 创建一张会长期留在手牌容器中的正式 CardView；节点按实体 UID 绑定一次输入信号，后续快照只更新内容。
func _create_local_hand_card_view(card_uid: int) -> CardView:
	# 新正式手牌节点；它会一直复用到实体牌离开本人手牌或木牛区域。
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	card_view.visible = true
	card_view.pressed.connect(_on_card_pressed.bind(card_uid))
	card_view.card_drag_started.connect(_on_card_drag_started)
	hand_container.add_child(card_view)
	return card_view


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
	if equipment.has("treasure"):
		# 当前宝物实体快照；木牛流马需要在装备名后直接显示公开存牌数量。
		var treasure_card: Dictionary = equipment.get("treasure", {}) as Dictionary
		var treasure_definition: Dictionary = GameDatabase.get_card(str(treasure_card.get("definition_id", "")))
		if bool(treasure_definition.get("shows_attachment_count", false)):
			# 装备公开附属牌数；0张时仍显示，避免把无存牌误解为数量信息缺失。
			var wooden_ox_count: int = int(player.get("wooden_ox_storage_count", 0))
			treasure_name += "（%d）" % wooden_ox_count
	return "⚔ 武器　%s\n🛡 防具　%s\n♞ 进攻　%s\n♞ 防御　%s\n◇ 宝物　%s" % [weapon_name, armor_name, offensive_mount_name, defensive_mount_name, treasure_name]


## 把本地公开装备快照写入独立堆叠组件；候选与选中 UID 只来自当前本地内联请求。
func _render_local_equipment(player: Dictionary) -> void:
	# 本地装备字典；组件按固定槽位位置显示已有实体，空槽保留位置但不绘制“无”占位。
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	# 当前内联候选 UID；组件会自行过滤不属于装备区的手牌或木牛“粮”实体。
	var candidate_uids: Array[int] = []
	# 当前内联已选 UID；装备横条与手牌共用同一临时选择顺序和数量约束。
	var selected_uids: Array[int] = []
	if not _active_equipment_action.is_empty():
		candidate_uids = [_active_equipment_uid]
		selected_uids = [_active_equipment_uid]
	elif not _inline_card_choice.is_empty():
		candidate_uids = _get_inline_candidate_uids()
		selected_uids = _inline_selected_card_uids.duplicate()
	elif _can_local_player_act():
		candidate_uids = _get_play_phase_equipment_candidate_uids()
	equipment_label.configure(equipment, int(player.get("wooden_ox_storage_count", 0)), candidate_uids, selected_uids)
	# 原固定槽位文本继续作为组件的完整无障碍摘要；可见牌面由堆叠横条负责。
	equipment_label.tooltip_text = _format_local_equipment(player)


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
	if not _active_equipment_action.is_empty():
		_toggle_equipment_action_material(card_uid)
		return
	if not _inline_card_choice.is_empty():
		_toggle_inline_card_choice(card_uid)
		return
	# 当前点击是否取消已经选中的同一张牌；用于在写入新选择前决定最终 UID。
	var deselecting_current_card: bool = _selected_card_uid == card_uid
	_selected_card_uid = -1 if deselecting_current_card else card_uid
	_selected_target_ids.clear()
	_auto_locked_target_id = -1
	if _selected_card_uid >= 0:
		# 初始规则预览；自身、全体与唯一候选目标牌可据此自动整理目标选择。
		var initial_preview: Dictionary = match_controller.get_card_use_preview(match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
		# 当前目标模式；自身目标自动选择自己，全体目标牌由核心展开且无需保留手动目标。
		var target_mode: String = str(initial_preview.get("target_mode", ""))
		if target_mode == "self" or target_mode == "self_wounded":
			_selected_target_ids.assign([match_controller.local_human_player_id])
			_auto_locked_target_id = match_controller.local_human_player_id
		elif target_mode == "all_players" or target_mode == "all_others":
			_selected_target_ids.clear()
		else:
			# 当前合法目标；恰好一个时没有可供玩家选择的分支，因此自动锁定并仅等待明确确认。
			var legal_target_ids: Array = initial_preview.get("legal_target_ids", []) as Array
			if legal_target_ids.size() == 1:
				_auto_locked_target_id = int(legal_target_ids[0])
				_selected_target_ids.assign([_auto_locked_target_id])
	error_label.text = ""
	_refresh_selection_text()


## 选择或取消本地装备区中的候选实体；装备与手牌共用统一内联请求和确认按钮。
func _on_equipment_pressed(card_uid: int) -> void:
	if not _active_equipment_action.is_empty():
		if card_uid == _active_equipment_uid:
			_clear_equipment_action()
			_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
			_render_local_hand()
			_refresh_selection_text()
		return
	if not _inline_card_choice.is_empty():
		if _is_inline_material_equipment_response_candidate(card_uid):
			_activate_equipment_action("equipment_response", card_uid)
			return
		_toggle_inline_card_choice(card_uid)
		return
	# 出牌阶段装备候选由当前 chooseToUse 请求提供；未列入请求的静态装备不能通过点击绕过规则核心。
	if not _get_play_phase_equipment_candidate_uids().has(card_uid):
		return
	# 被点击装备快照；交互类别由卡牌定义元数据声明，界面不识别具体装备 ID。
	var equipment_card: Dictionary = _get_local_equipment_snapshot(card_uid)
	# 当前装备定义；play_phase_interaction 为空表示没有点击发动流程。
	var definition: Dictionary = GameDatabase.get_card(str(equipment_card.get("definition_id", "")))
	var interaction_type: String = str(definition.get("play_phase_interaction", ""))
	if not interaction_type.is_empty():
		_activate_equipment_action(interaction_type, card_uid)


## 进入一条点击装备后的材料选择流程；主动装备保持右移与选中描边，普通出牌选牌和旧目标同时清空。
func _activate_equipment_action(action_type: String, equipment_uid: int) -> void:
	_active_equipment_action = action_type
	_active_equipment_uid = equipment_uid
	_equipment_action_material_uids.clear()
	_selected_card_uid = -1
	_selected_target_ids.clear()
	_auto_locked_target_id = -1
	_inline_selected_card_uids.clear()
	error_label.text = ""
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


## 清空装备主动交互的全部临时状态；只影响本地视觉选择，不提交动作或移动任何权威实体牌。
func _clear_equipment_action() -> void:
	_active_equipment_action = ""
	_active_equipment_uid = -1
	_equipment_action_material_uids.clear()


## 选择或取消装备技能的一张普通手牌材料；材料上限由当前装备定义元数据提供。
func _toggle_equipment_action_material(card_uid: int) -> void:
	if not _get_equipment_action_material_candidate_uids().has(card_uid):
		return
	if _equipment_action_material_uids.has(card_uid):
		_equipment_action_material_uids.erase(card_uid)
	else:
		# 当前材料上限；非负整数由卡牌文件的 play_phase_material_count 或 response_material_count 提供。
		var definition: Dictionary = _get_active_equipment_definition()
		var maximum_material_count: int = int(definition.get("response_material_count", 0)) if _active_equipment_action == "equipment_response" else int(definition.get("play_phase_material_count", 0))
		if maximum_material_count == 1:
			_equipment_action_material_uids.clear()
		if _equipment_action_material_uids.size() < maximum_material_count:
			_equipment_action_material_uids.append(card_uid)
	_selected_target_ids.clear()
	_auto_locked_target_id = -1
	# 装备材料选满后若恰好只有一名合法目标，则沿用普通出牌的唯一候选自动锁定语义。
	var active_definition: Dictionary = _get_active_equipment_definition()
	var required_material_count: int = int(active_definition.get("play_phase_material_count", 0))
	if _active_equipment_action != "equipment_response" and required_material_count > 0 and _equipment_action_material_uids.size() == required_material_count:
		var initial_preview: Dictionary = match_controller.get_equipment_action_preview(match_controller.local_human_player_id, _active_equipment_uid, {"material_card_uids":_equipment_action_material_uids.duplicate()}, [])
		var legal_target_ids: Array = initial_preview.get("legal_target_ids", []) as Array
		if legal_target_ids.size() == 1:
			_auto_locked_target_id = int(legal_target_ids[0])
			_selected_target_ids.assign([_auto_locked_target_id])
	error_label.text = ""
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


## 判断内联响应候选是否为需要额外普通手牌材料的装备入口。
func _is_inline_material_equipment_response_candidate(card_uid: int) -> bool:
	for candidate_variant: Variant in _inline_card_choice.get("candidates", []) as Array:
		# 当前候选；装备定义元数据声明响应材料数量。
		var candidate: Dictionary = candidate_variant as Dictionary
		var candidate_card: Dictionary = candidate.get("card_data", {}) as Dictionary
		if int(candidate.get("uid", -1)) == card_uid and str(candidate.get("zone", "")) == "equipment":
			var definition: Dictionary = GameDatabase.get_card(str(candidate_card.get("definition_id", "")))
			return int(definition.get("response_material_count", 0)) > 0
	return false


## 返回当前主动装备的静态定义；没有活动装备时返回空字典。
func _get_active_equipment_definition() -> Dictionary:
	var equipment_card: Dictionary = _get_local_equipment_snapshot(_active_equipment_uid)
	return GameDatabase.get_card(str(equipment_card.get("definition_id", "")))


## 按实体 UID 返回本地装备快照；找不到时返回空字典，调用方不能据此假定装备仍可发动。
func _get_local_equipment_snapshot(card_uid: int) -> Dictionary:
	# 本地玩家装备字典；只包含对所有观察者公开的牌面数据。
	var equipment: Dictionary = (_get_player_snapshot(match_controller.local_human_player_id).get("equipment", {}) as Dictionary)
	for equipment_variant: Variant in equipment.values():
		# 当前装备快照；UID 匹配时返回深拷贝，避免界面状态污染最近快照。
		var equipment_card: Dictionary = equipment_variant as Dictionary
		if int(equipment_card.get("uid", -1)) == card_uid:
			return equipment_card.duplicate(true)
	return {}


## 按点击顺序选择或取消一名目标；最多保留三个目标以支持方天画戟。
## 最大目标数现由规则预览动态提供；当上限为1时，点击新目标会直接替换旧目标。
func _on_target_pressed(target_id: int) -> void:
	if not _inline_card_choice.is_empty():
		return
	if _uses_rule_expanded_targets():
		return
	if target_id == _auto_locked_target_id:
		return
	if _selected_target_ids.has(target_id):
		_selected_target_ids.erase(target_id)
	elif _selected_card_uid >= 0 or not _active_equipment_action.is_empty():
		# 当前可点击的合法目标；单目标牌已选择目标后仍返回全部可替换候选。
		var selectable_target_ids: Array[int] = _get_selectable_target_ids()
		# 当前牌允许的最大目标数；包含方天画戟等规则修正，不在界面硬编码三目标上限。
		var maximum_target_count: int = int(_card_use_preview.get("max_targets", 0))
		if selectable_target_ids.has(target_id):
			if maximum_target_count == 1:
				_selected_target_ids.clear()
			if _selected_target_ids.size() < maximum_target_count:
				_selected_target_ids.append(target_id)
	_refresh_selection_text()


## 接收持久对手组件的点击并读取其最新玩家 ID；节点复用后无需为每次快照重新连接带 ID 的 Callable。
func _on_persistent_target_pressed(player_view: PlayerTargetView) -> void:
	if player_view == null or not is_instance_valid(player_view):
		return
	_on_target_pressed(player_view.player_id)


## 返回当前牌面可点击的合法目标；单目标牌保留空选择时的完整候选，支持一次点击直接切换目标。
func _get_selectable_target_ids() -> Array[int]:
	if _uses_rule_expanded_targets():
		return []
	# 当前预览给出的后续合法目标；多目标牌直接按已有选择继续追加。
	var selectable_target_ids: Array[int] = []
	selectable_target_ids.assign(_card_use_preview.get("legal_target_ids", []) as Array)
	if not _active_equipment_action.is_empty():
		return selectable_target_ids
	if _selected_card_uid < 0 or int(_card_use_preview.get("max_targets", 0)) != 1 or _auto_locked_target_id >= 0:
		return selectable_target_ids
	# 单目标牌的空选择预览；已选目标不会排除其他候选，因此角色高亮和点击都可直接切换。
	var replacement_preview: Dictionary = match_controller.get_card_use_preview(match_controller.local_human_player_id, _selected_card_uid, [])
	selectable_target_ids.assign(replacement_preview.get("legal_target_ids", []) as Array)
	return selectable_target_ids


## 返回当前卡牌是否由规则层自动展开全体目标；此类牌不开放武将牌点击、拖放或手动高亮入口。
func _uses_rule_expanded_targets() -> bool:
	if _selected_card_uid < 0 or not _active_equipment_action.is_empty():
		return false
	return str(_card_use_preview.get("target_mode", "")) in ["all_players", "all_others"]


## 拖动卡牌开始时同步选牌状态，使目标组件立即展示该牌的合法投放区域。
func _on_card_drag_started(card_uid: int) -> void:
	if _selected_card_uid != card_uid:
		_on_card_pressed(card_uid)


## 接收角色组件的卡牌拖放结果；拖放与点击共用选牌、选目标和确认提交流程。
func _on_card_dropped(card_uid: int, target_id: int) -> void:
	if not _active_equipment_action.is_empty():
		if not _equipment_action_material_uids.has(card_uid):
			_toggle_equipment_action_material(card_uid)
		if _active_equipment_action != "equipment_response" and not _selected_target_ids.has(target_id):
			_on_target_pressed(target_id)
		return
	if not _inline_card_choice.is_empty():
		return
	if _selected_card_uid != card_uid:
		_on_card_pressed(card_uid)
	if _uses_rule_expanded_targets():
		return
	if not _selected_target_ids.has(target_id):
		_on_target_pressed(target_id)


## 将本地玩家自身加入或移出目标列表。
func _on_self_target_pressed() -> void:
	_on_target_pressed(match_controller.local_human_player_id)


## 提交使用牌动作；所有规则错误由核心返回并显示。
func _on_use_pressed() -> void:
	if not _active_equipment_action.is_empty():
		_submit_equipment_action()
		return
	if not _inline_card_choice.is_empty():
		_submit_inline_card_choice(_inline_selected_card_uids)
		return
	if _selected_card_uid < 0:
		_on_action_rejected("请先选择一张手牌。")
		return
	# 无目标铁索连环；确定按钮直接提交重铸并摸1张牌，不再依赖独立“重铸”按钮。
	var selected_card: Dictionary = _get_selected_card_snapshot()
	var selected_definition: Dictionary = GameDatabase.get_card(str(selected_card.get("definition_id", "")))
	if _selected_target_ids.is_empty() and bool(selected_definition.get("recast", false)) and _can_recast_selected_card():
		match_controller.submit_action(PlayerAction.new("recast_card", match_controller.local_human_player_id, _selected_card_uid))
		return
	# 使用牌标准动作；目标数组按界面点击顺序复制。
	var action: PlayerAction = PlayerAction.new("use_card", match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
	match_controller.submit_action(action)


## 提交当前点击装备后的完整动作；界面只发送装备、材料与目标 ID，核心仍会复核所有区域和规则条件。
func _submit_equipment_action() -> void:
	# 当前装备定义；材料数量、动作类型和 card_uid 来源全部由卡牌元数据提供。
	var definition: Dictionary = _get_active_equipment_definition()
	# 当前装备显示名；用于生成通用材料不足提示。
	var equipment_name: String = GameSettings.resolve_card_name(definition)
	# 当前所需材料数量；响应与出牌阶段可分别声明。
	var required_material_count: int = int(definition.get("response_material_count", 0)) if _active_equipment_action == "equipment_response" else int(definition.get("play_phase_material_count", 0))
	if _equipment_action_material_uids.size() != required_material_count:
		_on_action_rejected("请为【%s】选择%d张手牌。" % [equipment_name, required_material_count])
		return
	if _active_equipment_action == "equipment_response":
		# 当前响应请求 ID；装备点击模式仍属于原 chooseToRespond，不能新建第二个并行选择窗口。
		var request_id: int = int(_inline_card_choice.get("request_id", -1))
		# 装备响应动作；selected_card_uids 选择装备入口，material_card_uids 保存实际费用。
		var response_action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
		response_action.payload = {"request_id":request_id, "selected_card_uids":[_active_equipment_uid], "material_card_uids":_equipment_action_material_uids.duplicate()}
		if match_controller.submit_action(response_action):
			if int(_inline_card_choice.get("request_id", -2)) == request_id:
				_inline_card_choice.clear()
				_inline_selected_card_uids.clear()
			_clear_equipment_action()
		return
	# 出牌阶段装备动作类型；空值表示卡牌配置不完整。
	var action_type: String = str(definition.get("play_phase_action_type", ""))
	if action_type.is_empty():
		_on_action_rejected("当前装备没有配置主动动作类型。")
		return
	# 动作 card_uid 来源；虚拟牌装备使用装备 UID，存储类装备使用首张材料 UID。
	var card_uid: int = _active_equipment_uid
	if str(definition.get("play_phase_action_card_source", "equipment")) == "material" and not _equipment_action_material_uids.is_empty():
		card_uid = _equipment_action_material_uids[0]
	# 装备主动动作；材料数组统一写入 payload，未使用该字段的装备可安全忽略。
	var equipment_action: PlayerAction = PlayerAction.new(action_type, match_controller.local_human_player_id, card_uid, _selected_target_ids)
	equipment_action.payload = {"material_card_uids":_equipment_action_material_uids.duplicate(), "equipment_uid":_active_equipment_uid}
	match_controller.submit_action(equipment_action)


## 处理无名杀式键盘与右键快捷操作；快捷键只调用现有标准动作，不绕过规则核心。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		# 当前键盘事件；只响应确认、取消和结束出牌三个稳定桌面操作。
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			if not _active_equipment_action.is_empty():
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif not _inline_card_choice.is_empty() and bool(_inline_card_choice.get("allow_cancel", false)):
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif _selected_card_uid >= 0:
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_ENTER and not use_button.disabled:
			_on_use_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_SPACE and _selected_card_uid < 0 and _active_equipment_action.is_empty() and not end_play_button.disabled:
			_on_end_play_pressed()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		if not _active_equipment_action.is_empty():
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif not _inline_card_choice.is_empty() and bool(_inline_card_choice.get("allow_cancel", false)):
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif _selected_card_uid >= 0:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()


## 取消当前选牌与目标，不向规则核心提交任何动作。
func _on_cancel_pressed() -> void:
	if not _active_equipment_action.is_empty():
		_clear_equipment_action()
		_selected_target_ids.clear()
		_auto_locked_target_id = -1
		error_label.text = ""
		_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
		_render_local_hand()
		_refresh_selection_text()
		return
	if not _inline_card_choice.is_empty():
		if bool(_inline_card_choice.get("allow_cancel", false)):
			# 空选择；明确表示放弃本次可取消请求，不会消费任何手牌。
			var cancelled_uids: Array[int] = []
			_submit_inline_card_choice(cancelled_uids)
		return
	_selected_card_uid = -1
	_selected_target_ids.clear()
	_auto_locked_target_id = -1
	error_label.text = ""
	_refresh_selection_text()


## 提交重铸动作；不允许重铸的牌会由核心拒绝。
func _on_recast_pressed() -> void:
	if _selected_card_uid < 0:
		_on_action_rejected("请先选择一张手牌。")
		return
	match_controller.submit_action(PlayerAction.new("recast_card", match_controller.local_human_player_id, _selected_card_uid))


## 提交结束出牌阶段动作。
func _on_end_play_pressed() -> void:
	if _has_group_trick_response_button_context():
		_toggle_group_trick_suppression()
		return
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
		_refresh_card_selection_panel()


## 响应全局 UI 风格变化；设置层只发送稳定标识，桌面负责通知各独立表现组件重绘。
func _on_ui_style_changed(style_id: String) -> void:
	BattleUIStyle.set_active_style(style_id)
	_apply_ui_style()


## 把当前活动风格应用到桌面静态控件与可复用动态组件；不重建对局、不提交动作也不修改规则快照。
func _apply_ui_style() -> void:
	if not is_node_ready():
		return
	reference_backdrop.apply_ui_style(BattleUIStyle.get_active_style_id())
	($Background as ColorRect).color = BattleUIStyle.get_color("outer_background")
	($BackdropShade as ColorRect).color = Color(BattleUIStyle.get_color("outer_background"), 0.10)
	($TableOrnament as TextureRect).modulate = Color(BattleUIStyle.get_color("ornament"), 0.12)
	($TopInfoPanel as PanelContainer).add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	phase_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	center_turn_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	center_phase_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	match_menu.refresh_ui_style()
	BattleUIStyle.apply_interaction_button(%LogToggleButton, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	(%LogContentPanel as PanelContainer).add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	($LogPanel/LogContentPanel/LogVBox/LogTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	log_view.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	interaction_guide_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_guide"))
	selection_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	error_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger"))
	BattleUIStyle.apply_interaction_button(use_button)
	BattleUIStyle.apply_interaction_button(%CancelButton)
	_refresh_group_trick_response_button()
	card_selection_panel.refresh_ui_style()
	character_selection_panel.refresh_ui_style()
	card_use_animation_layer.target_line_color = BattleUIStyle.get_color("target_line")
	equipment_label.refresh_ui_style()
	for card_view_variant: Variant in _card_views.values():
		# 当前正式手牌视图；主题刷新不能改变实体 UID、输入权限或选中状态。
		var card_view: CardView = card_view_variant as CardView
		if card_view != null and is_instance_valid(card_view):
			card_view.refresh_ui_style()
	for player_view_variant: Variant in _player_views.values():
		# 当前对手武将牌；主题刷新保留目标合法性、选中状态和受伤反馈基线。
		var player_view: PlayerTargetView = player_view_variant as PlayerTargetView
		if player_view != null and is_instance_valid(player_view):
			player_view.refresh_ui_style()
	if local_player_card != null and is_instance_valid(local_player_card):
		local_player_card.refresh_ui_style()
	for skill_view_variant: Variant in _skill_views.values():
		# 当前技能按钮；只更新颜色，不重新判断规则可用性。
		var skill_view: SkillButtonView = skill_view_variant as SkillButtonView
		if skill_view != null and is_instance_valid(skill_view):
			skill_view.refresh_ui_style()


## 清空日志并使用菜单设置的人数启动下一局；当前对局人数只在重新开局时改变。
func _on_restart_requested(player_count: int) -> void:
	log_view.clear()
	card_use_animation_layer.clear_presentations()
	_clear_local_hand_gain_animations()
	card_selection_panel.close()
	_public_card_choice_display.clear()
	_inline_card_choice.clear()
	_inline_selected_card_uids.clear()
	_clear_equipment_action()
	_modal_choice_request_id = -1
	_modal_card_choice_request.clear()
	_timed_match_id = ""
	_match_started_msec = -1
	_match_finished_msec = -1
	_last_rendered_duration_seconds = -1
	_presented_discard_card_uids.clear()
	_identity_marks.clear()
	_identity_mark_target_id = -1
	_suppressed_group_trick_uid = -1
	match_controller.default_player_count = player_count
	match_controller.start_match(player_count)


## 接收观察者裁剪后的选将快照；候选内容只存在于本地选将组件，不写入桌面状态或玩家快照。
func _on_character_selection_changed(selection_snapshot: Dictionary) -> void:
	character_selection_panel.bind_snapshot(selection_snapshot)


## 接收公共选牌展示快照并立即刷新所有观察者可见窗口；空字典只关闭公共层，不影响其他有效本地请求。
func _on_public_card_choice_display_changed(display_data: Dictionary) -> void:
	_public_card_choice_display = display_data.duplicate(true)
	_refresh_card_selection_panel()


## 显示属于本地玩家的统一选牌请求；本人手牌与装备候选使用桌面内联交互，其他区域继续使用独立窗口。
func _on_card_choice_requested(choice_data: Dictionary) -> void:
	# 当前请求选择者；并行无懈期间公共名单优先，普通单人请求继续使用该玩家作为唯一操作高亮。
	var chooser_id: int = int(choice_data.get("chooser_id", -1))
	if _simultaneous_operator_player_ids.is_empty():
		_current_operator_player_id = chooser_id
	if not _snapshot.is_empty():
		_render_players()
	# 非本地并行请求只更新公共高亮，不能关闭或替换本地玩家已经显示的询问界面。
	if chooser_id != match_controller.local_human_player_id:
		_refresh_card_selection_panel()
		return
	# 新请求已经替换旧独立窗口时先清理旧副本；同步创建的新本地请求会在后续分支重新写入。
	var incoming_request_id: int = int(choice_data.get("request_id", -1))
	if _modal_choice_request_id >= 0 and _modal_choice_request_id != incoming_request_id:
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
	# 当前群体锦囊已开启“不响应”时直接提交空选择；界面不创建询问栏，规则核心仍校验同一请求 ID 与可取消语义。
	if _is_suppressed_group_trick_choice(choice_data):
		call_deferred("_submit_suppressed_group_trick_choice", choice_data.duplicate(true))
		_refresh_selection_text()
		return
	if _is_inline_hand_choice(choice_data):
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
		_inline_card_choice = choice_data.duplicate(true)
		_inline_selected_card_uids.clear()
		# 装备触发询问的公开装备 UID；自动选中只准备本地临时选择，仍需玩家点击确定发动或点击取消放弃。
		var auto_selected_equipment_uid: int = _get_auto_selected_equipment_trigger_uid(choice_data)
		if auto_selected_equipment_uid >= 0:
			_inline_selected_card_uids.append(auto_selected_equipment_uid)
		_clear_equipment_action()
		_selected_card_uid = -1
		_selected_target_ids.clear()
		_auto_locked_target_id = -1
		_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
		_render_local_hand()
		_refresh_selection_text()
		_refresh_card_selection_panel()
		return
	_inline_card_choice.clear()
	_inline_selected_card_uids.clear()
	_clear_equipment_action()
	_modal_choice_request_id = int(choice_data.get("request_id", -1))
	_modal_card_choice_request = choice_data.duplicate(true)
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()
	_refresh_card_selection_panel()


## 把选择组件返回的 UID 封装为标准 choose_cards 动作并交由规则核心复核。
func _on_card_choice_submitted(request_id: int, selected_card_uids: Array[int]) -> void:
	# 统一选择动作；payload 只含请求序号与稳定实体牌 UID，可直接进入网络和回放。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate()}
	if match_controller.submit_action(action):
		if _modal_choice_request_id == request_id:
			_modal_choice_request_id = -1
			_modal_card_choice_request.clear()
			_refresh_card_selection_panel()


## 将“放弃”转换为空 UID 的标准选择动作；能否放弃仍由当前请求数量约束决定。
func _on_card_choice_cancelled(request_id: int) -> void:
	_on_card_choice_submitted(request_id, [])


## 根据公共展示与本地独立请求统一决定选择窗口内容；公共展示始终优先保持可见。
func _refresh_card_selection_panel() -> void:
	if not _public_card_choice_display.is_empty():
		# 本地存在与公共展示不同类型的内联询问时，公共窗口暂时让出手牌与按钮输入，询问结束后会从保留快照自动恢复。
		if not _inline_card_choice.is_empty() and str((_inline_card_choice.get("context", {}) as Dictionary).get("kind", "")) != str(_public_card_choice_display.get("kind", "")):
			card_selection_panel.close()
			return
		# 本地存在与公共展示不同类型的独立请求时优先显示该请求，公共牌位数据仍保留在桌面快照中。
		if not _modal_card_choice_request.is_empty() and str((_modal_card_choice_request.get("context", {}) as Dictionary).get("kind", "")) != str(_public_card_choice_display.get("kind", "")):
			card_selection_panel.show_request(_modal_card_choice_request)
			return
		# 公共展示副本；补充武将显示名后交给纯 UI 组件，不把玩家快照或规则对象传入牌位节点。
		var enriched_display: Dictionary = _enrich_public_card_choice_display(_public_card_choice_display)
		# 本地交互请求；只有请求类型与当前公共展示一致时才开放点击和底部操作按钮。
		var interactive_request: Dictionary = {}
		if int(_modal_card_choice_request.get("chooser_id", -1)) == match_controller.local_human_player_id:
			# 本地独立请求类型；只有与公共展示 kind 完全一致时才能开放公共牌位输入。
			var request_kind: String = str((_modal_card_choice_request.get("context", {}) as Dictionary).get("kind", ""))
			if request_kind == str(_public_card_choice_display.get("kind", "")):
				interactive_request = _modal_card_choice_request.duplicate(true)
		card_selection_panel.show_public_display(enriched_display, interactive_request)
		return
	if not _modal_card_choice_request.is_empty():
		card_selection_panel.show_request(_modal_card_choice_request)
		return
	card_selection_panel.close()


## 为公共选牌牌位补充当前选择者与领取者武将名；规则状态仍只保存稳定玩家 ID。
func _enrich_public_card_choice_display(display_data: Dictionary) -> Dictionary:
	# 可写公共展示副本；所有名称只属于当前客户端表现，不回写权威 GameState。
	var result: Dictionary = display_data.duplicate(true)
	# 当前选择者 ID；负数表示公共展示已创建但暂时没有有效选择者。
	var active_player_id: int = int(result.get("active_player_id", -1))
	if active_player_id >= 0:
		# 当前选择者武将名；配置异常时回退玩家显示名，确保提示仍可定位到操作者。
		var active_player: Dictionary = _get_player_snapshot(active_player_id)
		# 当前选择者公开武将名；未选将或异常快照时随后回退玩家显示名。
		var active_character_name: String = GameDatabase.resolve_character_name(str(active_player.get("character_id", "")))
		if str(active_player.get("character_id", "")).is_empty():
			active_character_name = str(active_player.get("display_name", "玩家"))
		result["prompt"] = "【%s】正在选择展示牌" % active_character_name
	# 公共固定牌位；逐项补充领取者武将名，UID、牌面与领取者 ID 保持原值。
	var enriched_slots: Array = []
	for slot_variant: Variant in result.get("slots", []) as Array:
		# 当前牌位副本；只新增客户端显示字段，不删除原始领取者 ID。
		var display_slot: Dictionary = (slot_variant as Dictionary).duplicate(true)
		# 当前牌位领取者玩家 ID；-1表示未领取，不需要补充武将名。
		var taken_by_player_id: int = int(display_slot.get("taken_by_player_id", -1))
		if taken_by_player_id >= 0:
			# 领取者公开玩家快照；武将已在正式对局开始前全部亮出，因此名称可向所有观察者显示。
			var taken_by_player: Dictionary = _get_player_snapshot(taken_by_player_id)
			# 领取者公开武将名；配置异常时随后回退玩家显示名或“已领取”占位。
			var taken_by_character_name: String = GameDatabase.resolve_character_name(str(taken_by_player.get("character_id", "")))
			if str(taken_by_player.get("character_id", "")).is_empty():
				taken_by_character_name = str(taken_by_player.get("display_name", "已领取"))
			display_slot["taken_by_character_name"] = taken_by_character_name
		enriched_slots.append(display_slot)
	result["slots"] = enriched_slots
	return result


## 判断选择请求是否能完全在本地手牌区或装备区完成；空候选的可取消响应也使用内联取消按钮。
func _is_inline_hand_choice(choice_data: Dictionary) -> bool:
	# 请求选择者 ID；所有候选必须属于该玩家，不能把他人区域牌错误放入本地手牌交互。
	var chooser_id: int = int(choice_data.get("chooser_id", -1))
	for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
		# 当前候选快照；区域与所有者共同决定其是否已经显示在本地手牌或装备组件中。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("owner_id", -1)) != chooser_id or str(candidate.get("zone", "")) not in ["hand", "wooden_ox", "equipment"]:
			return false
	return true


## 返回当前内联请求允许选择的实体 UID；空请求返回空数组，使全部手牌与装备保持不可选并仅允许取消。
func _get_inline_candidate_uids() -> Array[int]:
	# 候选 UID 集合；保持规则请求顺序并防御性去重。
	var result: Array[int] = []
	for candidate_variant: Variant in _inline_card_choice.get("candidates", []) as Array:
		# 当前候选 UID；无效负数不会进入可交互集合。
		var candidate_uid: int = int((candidate_variant as Dictionary).get("uid", -1))
		if candidate_uid >= 0 and not result.has(candidate_uid):
			result.append(candidate_uid)
	return result


## 返回可自动选中的装备触发 UID；只有上下文明确绑定同一公开装备实体时生效，普通响应与目标区域选牌不自动选择。
func _get_auto_selected_equipment_trigger_uid(choice_data: Dictionary) -> int:
	# 触发上下文；装备规则创建询问时写入 equipment_uid，客户端不能从候选位置自行推断发动语义。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	# 请求绑定的装备实体 UID；负数表示本请求不是装备发动询问。
	var equipment_uid: int = int(context.get("equipment_uid", -1))
	if equipment_uid < 0:
		return -1
	for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
		# 当前候选快照；必须属于本地选择者的装备区并与上下文实体完全一致。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == equipment_uid and int(candidate.get("owner_id", -1)) == match_controller.local_human_player_id and str(candidate.get("zone", "")) == "equipment":
			return equipment_uid
	return -1


## 返回当前 chooseToUse 请求中属于本地装备区的主动技能入口；丈八蛇矛与木牛流马以装备实体 UID 参与候选右移。
func _get_play_phase_equipment_candidate_uids() -> Array[int]:
	# 装备候选结果；不是本地出牌阶段时全部装备保持静态。
	var result: Array[int] = []
	if not _can_local_player_act():
		return result
	# 当前出牌请求实体 UID；核心只在装备效果确实可发动时把装备加入该集合。
	var runtime_choice: Dictionary = _snapshot.get("current_choice_request", {}) as Dictionary
	if int(runtime_choice.get("actor_id", -1)) != match_controller.local_human_player_id or str(runtime_choice.get("choice_type", "")) != "use":
		return result
	# 当前请求全部实体 UID；手牌与装备共用稳定 ID，但只保留本地装备字典中的丈八和木牛。
	var runtime_card_uids: Array[int] = []
	for card_uid_variant: Variant in runtime_choice.get("card_ids", []) as Array:
		runtime_card_uids.append(int(card_uid_variant))
	# 本地装备字典；逐槽读取可以保留装备实体身份并忽略其他锁定技或触发技装备。
	var equipment: Dictionary = (_get_player_snapshot(match_controller.local_human_player_id).get("equipment", {}) as Dictionary)
	for equipment_variant: Variant in equipment.values():
		# 当前装备快照；卡牌定义声明主动交互类型时才进入出牌阶段点击入口。
		var equipment_card: Dictionary = equipment_variant as Dictionary
		var equipment_uid: int = int(equipment_card.get("uid", -1))
		var equipment_definition: Dictionary = GameDatabase.get_card(str(equipment_card.get("definition_id", "")))
		if runtime_card_uids.has(equipment_uid) and not str(equipment_definition.get("play_phase_interaction", "")).is_empty():
			result.append(equipment_uid)
	return result


## 返回当前装备主动效果可以选择的普通手牌 UID；丈八与木牛都不允许把木牛“粮”当作本次材料。
func _get_equipment_action_material_candidate_uids() -> Array[int]:
	# 材料候选结果；没有主动装备流程时保持空数组，普通出牌可用性由 chooseToUse 单独决定。
	var result: Array[int] = []
	if _active_equipment_action.is_empty():
		return result
	# 本地普通手牌；快照中的 wooden_ox_storage 使用独立字段，因此此处不会混入“粮”。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	for card_variant: Variant in local_player.get("hand", []) as Array:
		# 当前材料实体 UID；负数异常数据不会开放点击。
		var card_uid: int = int((card_variant as Dictionary).get("uid", -1))
		if card_uid >= 0:
			result.append(card_uid)
	return result


## 返回当前本地出牌阶段可以进入使用、重铸或木牛存粮动作的实体 UID；请求缺失时不开放任何牌。
func _get_play_phase_candidate_uids() -> Array[int]:
	# 可用实体 UID 结果；只来源于运行时当前 chooseToUse 请求，不在界面重复实现卡牌规则。
	var result: Array[int] = []
	if not _can_local_player_act():
		return result
	# 当前运行时选择请求；出牌阶段应为 choice_type=use，其他响应请求不能误启用普通出牌交互。
	var runtime_choice: Dictionary = _snapshot.get("current_choice_request", {}) as Dictionary
	if int(runtime_choice.get("actor_id", -1)) != match_controller.local_human_player_id or str(runtime_choice.get("choice_type", "")) != "use":
		return result
	for card_uid_variant: Variant in runtime_choice.get("card_ids", []) as Array:
		# 当前合法实体 UID；防御性去重，避免异常快照让同一牌重复进入交互集合。
		var card_uid: int = int(card_uid_variant)
		if card_uid >= 0 and not result.has(card_uid):
			result.append(card_uid)
	return result


## 切换内联候选牌的临时选中状态，并严格限制请求声明的最大选择数量。
func _toggle_inline_card_choice(card_uid: int) -> void:
	if not _get_inline_candidate_uids().has(card_uid):
		return
	if _inline_selected_card_uids.has(card_uid):
		_inline_selected_card_uids.erase(card_uid)
	else:
		# 最大选择数；单选响应点击新牌时替换旧选择，多选弃牌则按点击顺序追加。
		var max_select: int = int(_inline_card_choice.get("max_select", 0))
		if max_select == 1:
			_inline_selected_card_uids.clear()
		if _inline_selected_card_uids.size() < max_select:
			_inline_selected_card_uids.append(card_uid)
	error_label.text = ""
	_refresh_selection_text()


## 提交手牌区内联选择；只有当前请求仍与提交 ID 相同时才清理，避免覆盖同步创建的下一请求。
func _submit_inline_card_choice(selected_card_uids: Array[int]) -> void:
	if _inline_card_choice.is_empty():
		return
	# 本次提交请求 ID；控制器恢复过程中可能同步发出下一条请求，因此必须保留独立副本。
	var request_id: int = int(_inline_card_choice.get("request_id", -1))
	# 统一选择动作；只提交请求号与实体 UID，不直接修改手牌、处理区或阶段。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate()}
	if not match_controller.submit_action(action):
		return
	if int(_inline_card_choice.get("request_id", -2)) == request_id:
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


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
func _on_card_presentation_requested(presentation_data: Dictionary) -> void:
	# 被展示牌快照；来自 CardPresentationEvent，不包含可修改的规则对象引用。
	var card_data: Dictionary = presentation_data.get("card_data", {}) as Dictionary
	if card_data.is_empty():
		return
	# 表现来源玩家 ID；使用牌、展示牌和判定牌都以该角色的桌面锚点作为起点。
	# 判定牌是上述规则的公共来源例外：规则层传入-1，使其直接从中央弃牌展示锚点出现。
	var actor_id: int = int(presentation_data.get("actor_id", -1))
	# 使用牌目标 ID；showCards 和 judge 发送空数组，因此不会错误绘制目标线。
	var target_ids: Array[int] = []
	for target_id_variant: Variant in presentation_data.get("target_ids", []) as Array:
		target_ids.append(int(target_id_variant))
	# 卡牌定义；用于配置正式卡牌视图，不参与效果判断。
	var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
	# 动画起点；公共判定牌使用中央锚点，玩家来源必须存在真实武将牌或本地手牌锚点，不能回退到中央伪造来源。
	var start_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	if actor_id >= 0:
		# 当前玩家来源锚点查询；座位尚未建立时丢弃本次纯表现，避免牌面错误出现在窗口中上部。
		var source_anchor_result: Dictionary = _try_get_player_indicator_position(actor_id)
		if not bool(source_anchor_result.get("valid", false)):
			return
		start_position = source_anchor_result.get("position", start_position) as Vector2
	# 中央弃牌区落点；所有正常使用牌先飞向该位置展示，装备或延时锦囊的最终规则区域不受影响。
	var discard_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	# 目标位置数组；多目标牌会同时绘制多根使用者到目标的指示线。
	var target_positions: Array[Vector2] = []
	for target_id: int in target_ids:
		# 当前目标锚点查询；缺失目标只省略对应指示线，不改变牌面本身的合法使用表现。
		var target_anchor_result: Dictionary = _try_get_player_indicator_position(target_id)
		if bool(target_anchor_result.get("valid", false)):
			target_positions.append(target_anchor_result.get("position", Vector2.ZERO) as Vector2)
	# 正式卡牌节点；本地牌存在时直接接管同一节点，其他玩家隐藏手牌则实例化同款完整牌面。
	# 手牌展示不会移动权威实体，因此展示请求必须使用正式牌面的独立表现实例。
	# 当前请求是否只展示牌面；手牌展示不会移动权威实体，因此必须使用正式牌面的独立表现实例。
	# 当前请求是否只展示牌面；showCards 不接管手牌节点，useCard 与 judge 对应真实处理区实体。
	var presentation_only: bool = str(presentation_data.get("event_name", "")) == "showCards"
	# 当前展示实体 UID；实际使用牌需要先停止可能尚未完成的本地获得动画，再把同一正式节点交给出牌动画层。
	var card_uid: int = int(card_data.get("uid", -1))
	# 当前表现稳定 ID；动画层在创建或接管任何节点前原子去重，重复网络包不会生成第二张牌面。
	var presentation_id: int = int(presentation_data.get("presentation_id", -1))
	# 本次是否接管后续弃牌移动；只有真实使用牌和判定牌可以登记实体 UID 所有权。
	var owns_discard_transfer: bool = bool(presentation_data.get("owns_discard_transfer", false))
	if not card_use_animation_layer.claim_presentation(presentation_id, card_uid, owns_discard_transfer):
		return
	if not presentation_only:
		_cancel_local_hand_gain_animation(card_uid)
		# 普通使用牌最终会从处理区进入弃牌堆；即使中央展示已经淡出，后续移牌信号也不能再生成第二张牌。
		# 该所有权由 presentation_data 明确声明并交给动画层保存，桌面不再维护第二套 UID 状态。
	# 正式卡牌节点；实际使用的本地处理区牌接管原节点，纯展示和不可见来源实例化同款完整牌面。
	var animated_card: CardView = null if presentation_only else _card_views.get(card_uid) as CardView
	if animated_card == null:
		animated_card = CARD_VIEW_SCENE.instantiate() as CardView
		animated_card.visible = false
		animated_card.configure(card_data, definition, false, false)
		card_use_animation_layer.add_child(animated_card)
		animated_card.position = start_position - animated_card.get_card_size() * 0.5
	card_use_animation_layer.play_card(animated_card, start_position, discard_position, target_positions, owns_discard_transfer)


## 接收统一牌区移动事件；摸牌、获得、响应和展示牌弃置都从实际来源锚点移动。
func _on_card_transfer_requested(card_data: Dictionary, source_player_id: int, source_zone: String, target_player_id: int, target_zone: String) -> void:
	# 同一张使用牌已经由完整出牌动画接管时，不再创建第二张转移牌，避免瞬间出现在目标武将牌上。
	var card_uid: int = int(card_data.get("uid", -1))
	# 同区域重复增量不代表实体发生了新的区域变化；直接丢弃，避免从中央锚点原地生成一张无来源牌面。
	if source_zone == target_zone and source_player_id == target_player_id:
		return
	if card_uid == _suppressed_group_trick_uid and source_zone == "processing" and target_zone != "processing":
		# 被抑制锦囊已经完成本次处理区生命周期；按钮恢复普通回合结束语义，下一次同名实体不会继承本地开关。
		_suppressed_group_trick_uid = -1
		_refresh_selection_text()
	if target_zone == "discard_pile":
		# 真实使用/判定牌先消费表现层认领；普通弃牌首次登记 UID，重复增量和迟到包都不再创建第二张牌。
		if card_use_animation_layer.register_discard_transfer(card_uid):
			return
		# 已有同 UID 牌面仍在中央队列时，纯展示或旧转移增量不能再并排创建重复节点。
		if card_use_animation_layer.has_active_card_uid(card_uid):
			return
		# 处理区牌必须由 useCard、delayedJudge 或 judge 表现明确认领；未认领增量多为虚拟材料收尾，不能在中央锚点凭空合成牌面。
		if source_zone == "processing":
			return
	if target_zone != "discard_pile":
		# 实体已经进入新的规则区域；上一轮弃牌移动的待消费与已消费所有权到此失效，未来普通弃置或再次使用可重新播放。
		card_use_animation_layer.release_consumed_discard_claim(card_uid)
	# 本地摸牌与其他获得都使用手牌容器中的正式实体视图；先登记 UID，收到包含该牌的快照后再让同一节点从右侧进入。
	var is_local_gain: bool = target_player_id == match_controller.local_human_player_id and target_zone == "hand"
	if is_local_gain:
		_pending_local_hand_gain_uids[card_uid] = true
		_start_pending_local_hand_gain_animations()
		return
	# 动画起点；牌堆、处理区、展示区和弃牌堆都以桌面中心为公共锚点。
	var start_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	if source_player_id >= 0 and source_zone not in ["draw_pile", "processing", "discard_pile"]:
		# 当前来源玩家锚点；座位不存在时不把牌错误地放到中央公共锚点。
		var source_anchor_result: Dictionary = _try_get_player_indicator_position(source_player_id)
		if not bool(source_anchor_result.get("valid", false)):
			return
		start_position = source_anchor_result.get("position", start_position) as Vector2
	# 动画终点；进入角色手牌时移动到其武将锚点，本地主视角的非摸牌获得已由正式手牌节点分支提前处理。
	var target_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	if target_player_id >= 0 and target_zone in ["hand", "equipment", "judgment", "wooden_ox"]:
		# 当前目标玩家锚点；快照重建期间缺失时宁可跳过短时动画，也不能在窗口中上部留下伪造落点。
		var target_anchor_result: Dictionary = _try_get_player_indicator_position(target_player_id)
		if not bool(target_anchor_result.get("valid", false)):
			return
		target_position = target_anchor_result.get("position", target_position) as Vector2
	# 牌面可见性；牌堆摸牌和其他角色不可见手牌转移只显示统一牌背，公开弃牌与公开区域显示正面。
	var show_card_back: bool = source_zone == "draw_pile" or (source_zone in ["hand", "wooden_ox"] and source_player_id != match_controller.local_human_player_id and target_player_id != match_controller.local_human_player_id and target_zone != "discard_pile")
	# 转移牌节点；所有表现仍复用正式 CardView，不创建简化标签。
	var animated_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	animated_card.visible = false
	if show_card_back:
		animated_card.configure_back(card_uid, false)
	else:
		var definition: Dictionary = GameDatabase.get_card(str(card_data.get("definition_id", "")))
		animated_card.configure(card_data, definition, false, false)
	card_use_animation_layer.add_child(animated_card)
	if target_zone == "discard_pile":
		# 弃置牌与展示手牌共用中央完整牌面队列；同一帧的多张牌按信号顺序一次性展示并成批淡出。
		animated_card.position = start_position - animated_card.get_card_size() * 0.5
		card_use_animation_layer.play_card(animated_card, start_position, target_position, [])
		return
	# 摸牌堆叠键；同一目标玩家连续从牌堆进入手牌的牌按数量依次堆叠，其他转移保持独立动画。
	var draw_stack_key: String = "draw:%d" % target_player_id if source_zone == "draw_pile" and target_zone == "hand" and target_player_id >= 0 else ""
	card_use_animation_layer.play_transfer(animated_card, start_position, target_position, draw_stack_key)


## 接收实体进入新区域的内部所有权通知；只释放旧弃牌待消费与已消费状态，不创建牌面或修改权威区域。
func _on_card_animation_ownership_reset_requested(card_uid: int) -> void:
	card_use_animation_layer.release_consumed_discard_claim(card_uid)


## 返回指定玩家的目标指示锚点；本地玩家使用手牌区上方中心，其他玩家使用武将牌中心。
func _get_player_indicator_position(player_id: int) -> Vector2:
	# 指定玩家锚点查询；兼容调用方只读取位置，未知玩家仍回退中央，但动画创建入口会先使用可用性接口拒绝错误落点。
	var anchor_result: Dictionary = _try_get_player_indicator_position(player_id)
	if bool(anchor_result.get("valid", false)):
		return anchor_result.get("position", Vector2.ZERO) as Vector2
	return _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())


## 查询指定玩家是否存在可用动画锚点；返回字典避免用 Vector2.ZERO 同时表达合法坐标与查询失败。
func _try_get_player_indicator_position(player_id: int) -> Dictionary:
	if player_id == match_controller.local_human_player_id:
		# 本地手牌区全局矩形；顶边中心能统一表达本地玩家作为卡牌来源或目标的位置。
		var hand_rect: Rect2 = hand_container.get_global_rect()
		return {"valid":true, "position":_global_to_animation_position(Vector2(hand_rect.get_center().x, hand_rect.position.y - local_hand_indicator_margin))}
	# 其他玩家角色视图；武将牌根节点是 Node2D，不能按 Control 转换。
	var player_view: PlayerTargetView = _player_views.get(player_id) as PlayerTargetView
	if player_view != null and is_instance_valid(player_view):
		return {"valid":true, "position":_global_to_animation_position(player_view.get_global_rect().get_center())}
	return {"valid":false, "position":Vector2.ZERO}


## 返回本地正式获得牌在手牌区右侧的全局入场中心；使用可视滚动区域而不是可能超宽的内容区域。
func _get_local_hand_gain_start_global_position(card_size: Vector2) -> Vector2:
	# 手牌滚动区全局矩形；右边缘始终位于当前客户区内，不随隐藏内容宽度变化。
	var hand_scroll_rect: Rect2 = hand_scroll.get_global_rect()
	# 新牌全局中心；横向位于滚动区右侧，纵向与手牌底部对齐后的牌面中心一致。
	var start_global_position: Vector2 = Vector2(hand_scroll_rect.end.x + card_size.x * 0.5 + local_hand_gain_entry_margin, hand_scroll_rect.end.y - card_size.y * 0.5)
	return start_global_position


## 为已经进入当前快照的待处理 UID 启动正式手牌节点动画；尚未出现在快照中的 UID 保留到下一次对账。
func _start_pending_local_hand_gain_animations() -> void:
	for card_uid_variant: Variant in _pending_local_hand_gain_uids.keys():
		# 当前待入场实体 UID；同一 UID 已有补间时不会重复启动。
		var card_uid: int = int(card_uid_variant)
		if _local_hand_gain_tweens.has(card_uid):
			_pending_local_hand_gain_uids.erase(card_uid)
			continue
		# 当前正式手牌节点；只有已经由快照对账加入手牌容器后才能计算最终布局落点。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			continue
		_pending_local_hand_gain_uids.erase(card_uid)
		_start_local_hand_gain_animation(card_uid, card_view)


## 让指定正式手牌节点从可视手牌区右侧移动回自身布局位置；动画结束后节点继续留在容器和 UID 映射中。
func _start_local_hand_gain_animation(card_uid: int, card_view: CardView) -> void:
	hand_container.layout_cards_now()
	# 正式手牌的最终布局位置；扣除可能残留的入场偏移后作为本次补间的零点。
	var target_position: Vector2 = card_view.position - card_view.hand_entry_offset
	# 右侧入场中心全局坐标；固定从当前可视滚动区外侧进入，不受超宽内容区域影响。
	var start_global_center: Vector2 = _get_local_hand_gain_start_global_position(card_view.get_card_size())
	# 右侧入场左上角全局坐标；CardView 的 Node2D 原点位于牌面左上角。
	var start_global_position: Vector2 = start_global_center - card_view.get_card_size() * 0.5
	# 右侧入场左上角容器坐标；完整逆变换兼容画布缩放、滚动区位置和窗口适配。
	var start_local_position: Vector2 = hand_container.get_global_transform().affine_inverse() * start_global_position
	card_view.hand_entry_offset = start_local_position - target_position
	# 正式手牌入场补间；只驱动运行时偏移归零，容器仍持续拥有并布局同一个实体 UID 节点。
	var gain_tween: Tween = create_tween()
	gain_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gain_tween.tween_property(card_view, "hand_entry_offset", Vector2.ZERO, local_hand_gain_duration)
	_local_hand_gain_tweens[card_uid] = gain_tween
	gain_tween.finished.connect(_on_local_hand_gain_animation_finished.bind(card_uid, card_view.get_instance_id()))


## 完成本地正式手牌入场并重新应用稳定布局；实例 ID 校验防止旧补间清理同 UID 的新局节点。
func _on_local_hand_gain_animation_finished(card_uid: int, card_instance_id: int) -> void:
	_local_hand_gain_tweens.erase(card_uid)
	# 当前 UID 对应的正式手牌节点；重新开局或牌已离开时映射可能为空。
	var card_view: CardView = _card_views.get(card_uid) as CardView
	if card_view == null or not is_instance_valid(card_view) or card_view.get_instance_id() != card_instance_id:
		return
	card_view.hand_entry_offset = Vector2.ZERO
	hand_container.layout_cards_now()


## 取消指定实体的本地获得动画；用于牌在入场途中被使用、离开手牌或重新开局的情况。
func _cancel_local_hand_gain_animation(card_uid: int) -> void:
	_pending_local_hand_gain_uids.erase(card_uid)
	# 当前实体正在运行的入场补间；停止后从索引移除，防止旧完成回调修改后续状态。
	var gain_tween: Tween = _local_hand_gain_tweens.get(card_uid) as Tween
	if gain_tween != null and gain_tween.is_valid():
		gain_tween.kill()
	_local_hand_gain_tweens.erase(card_uid)
	# 当前正式手牌节点；仍位于手牌容器时清除剩余偏移，使后续出牌从真实布局位置开始。
	var card_view: CardView = _card_views.get(card_uid) as CardView
	if card_view != null and is_instance_valid(card_view) and card_view.get_parent() == hand_container:
		card_view.hand_entry_offset = Vector2.ZERO
		hand_container.layout_cards_now()


## 清空全部本地正式手牌入场任务；重新开局时调用，避免旧局补间继续写入新桌面。
func _clear_local_hand_gain_animations() -> void:
	for gain_tween_variant: Variant in _local_hand_gain_tweens.values():
		# 当前仍有效的入场补间；统一停止后再清空索引。
		var gain_tween: Tween = gain_tween_variant as Tween
		if gain_tween != null and gain_tween.is_valid():
			gain_tween.kill()
	for card_view_variant: Variant in _card_views.values():
		# 当前正式手牌节点；清场前归零运行时偏移，避免复用时继承旧局位置。
		var card_view: CardView = card_view_variant as CardView
		if card_view != null and is_instance_valid(card_view) and card_view.get_parent() == hand_container:
			card_view.hand_entry_offset = Vector2.ZERO
	_pending_local_hand_gain_uids.clear()
	_local_hand_gain_tweens.clear()


## 将全局画布坐标转换为动画层局部坐标；使用完整逆变换以兼容父节点位移、缩放与后续视口适配。
func _global_to_animation_position(global_position: Vector2) -> Vector2:
	return card_use_animation_layer.get_global_transform().affine_inverse() * global_position


## 显示最近一次动作拒绝原因。
func _on_action_rejected(message: String) -> void:
	error_label.text = message


## 更新当前选择摘要，目标以玩家显示名与选择顺序呈现。
func _refresh_selection_text() -> void:
	_card_use_preview = {}
	recast_button.visible = false
	selection_label.visible = true
	call_deferred("_refresh_group_trick_response_button")
	# 本地是否处于普通出牌阶段；右侧回合结束按钮只在该阶段独立显示，不属于中央交互面板。
	var can_act: bool = _can_local_player_act()
	end_play_button.visible = can_act and _inline_card_choice.is_empty()
	end_play_button.disabled = not end_play_button.visible
	if not _active_equipment_action.is_empty():
		_refresh_equipment_action_text()
		return
	if not _inline_card_choice.is_empty():
		_refresh_inline_choice_text()
		return
	interaction_panel.visible = can_act
	if not can_act:
		use_button.disabled = true
		%CancelButton.visible = false
		_refresh_component_states()
		return
	use_button.text = "确定"
	%CancelButton.disabled = false
	# 已选目标显示名数组；按选择顺序构建。
	var target_names: Array[String] = []
	for target_id: int in _selected_target_ids:
		# 目标玩家快照；用于从稳定 ID 解析显示名。
		var player: Dictionary = _get_player_snapshot(target_id)
		target_names.append(_snapshot_character_name(player, "玩家%d" % target_id))
	if _selected_card_uid < 0:
		selection_label.text = "未选择卡牌｜可点击牌面，或直接拖动卡牌到青色目标"
		interaction_guide_label.text = "请选择要使用的牌"
		use_button.disabled = true
		%CancelButton.visible = false
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
	# 当前是否可用“确定”执行重铸；允许重铸的普通手牌在没有选择目标时直接走重铸动作。
	var can_confirm_recast: bool = _selected_target_ids.is_empty() and bool(selected_definition.get("recast", false)) and _can_recast_selected_card()
	if can_confirm_recast:
		interaction_guide_label.text = "确定后重铸并摸一张牌"
	elif bool(_card_use_preview.get("can_submit", false)):
		interaction_guide_label.text = "请确认当前操作"
	else:
		interaction_guide_label.text = "请选择目标"
	use_button.disabled = not can_act or (not bool(_card_use_preview.get("can_submit", false)) and not can_confirm_recast)
	%CancelButton.visible = true
	_refresh_component_states()


## 刷新点击装备后的材料、目标和中央主按钮；交互规则全部读取当前装备定义元数据与核心预览。
func _refresh_equipment_action_text() -> void:
	interaction_panel.visible = true
	use_button.text = "确定"
	%CancelButton.visible = true
	%CancelButton.disabled = false
	recast_button.visible = false
	end_play_button.visible = _can_local_player_act() and _active_equipment_action != "equipment_response"
	end_play_button.disabled = not end_play_button.visible
	# 当前装备定义与显示名；界面不识别具体装备 ID。
	var definition: Dictionary = _get_active_equipment_definition()
	var equipment_name: String = GameSettings.resolve_card_name(definition)
	# 当前材料上限；响应和出牌阶段分别读取自身配置。
	var required_material_count: int = int(definition.get("response_material_count", 0)) if _active_equipment_action == "equipment_response" else int(definition.get("play_phase_material_count", 0))
	# 已选目标名称；装备主动流程最多保留一名目标。
	var target_name: String = "无"
	if not _selected_target_ids.is_empty():
		var target: Dictionary = _get_player_snapshot(_selected_target_ids[0])
		target_name = _snapshot_character_name(target, "玩家%d" % _selected_target_ids[0])
	if _active_equipment_action == "equipment_response":
		selection_label.text = "%s｜已选择%d/%d张手牌" % [equipment_name, _equipment_action_material_uids.size(), required_material_count]
		interaction_guide_label.text = "请选择装备响应所需的手牌材料"
		use_button.disabled = _equipment_action_material_uids.size() != required_material_count
		_refresh_component_states()
		return
	# 出牌阶段装备预览；材料、目标和可提交状态由装备源码生成。
	_card_use_preview = match_controller.get_equipment_action_preview(match_controller.local_human_player_id, _active_equipment_uid, {"material_card_uids":_equipment_action_material_uids.duplicate()}, _selected_target_ids)
	if _card_use_preview.is_empty():
		# 纯界面预览回退；没有权威对局状态的场景测试只验证材料交互，不替代正式规则校验。
		_card_use_preview = {"can_submit":_equipment_action_material_uids.size() == required_material_count, "legal_target_ids":[], "max_targets":int(definition.get("preview_max_targets", 0))}
	selection_label.text = "%s｜材料%d/%d｜目标：%s" % [equipment_name, _equipment_action_material_uids.size(), required_material_count, target_name]
	interaction_guide_label.text = "请确认当前操作" if bool(_card_use_preview.get("can_submit", false)) else ("请选择目标" if _equipment_action_material_uids.size() == required_material_count else "请选择手牌材料")
	use_button.disabled = not bool(_card_use_preview.get("can_submit", false))
	_refresh_component_states()


## 刷新手牌区内联选择提示与操作按钮；确认必须至少选择一张且满足请求数量范围。
func _refresh_inline_choice_text() -> void:
	# 已选牌数；只读取界面临时数组，不修改权威请求的 selected_card_ids。
	var selected_count: int = _inline_selected_card_uids.size()
	# 规则要求的最少数量；弃牌阶段可能大于1，可取消响应通常为0。
	var min_select: int = int(_inline_card_choice.get("min_select", 0))
	# 规则允许的最多数量；单张响应为1，弃牌阶段等于必须弃置的手牌数。
	var max_select: int = int(_inline_card_choice.get("max_select", 0))
	# 确认所需最少数量；可取消请求的空选择必须走“取消”，避免空确认语义不清。
	var minimum_confirm_count: int = maxi(min_select, 1)
	# 内联询问只保留具体规则提示与操作按钮；通用标题、已选数量和范围摘要不重复显示。
	selection_label.text = ""
	selection_label.visible = false
	interaction_guide_label.text = str(_inline_card_choice.get("prompt", "请选择卡牌"))
	interaction_panel.visible = true
	use_button.text = "确定"
	use_button.disabled = selected_count < minimum_confirm_count or selected_count > max_select
	%CancelButton.visible = true
	%CancelButton.disabled = not bool(_inline_card_choice.get("allow_cancel", false))
	end_play_button.visible = false
	_refresh_component_states()


## 判断一条本地选择是否属于可切换“不响应”的群体锦囊无懈询问。
func _is_group_trick_negation_choice(choice_data: Dictionary) -> bool:
	# 当前请求上下文；只有控制器创建的 trick_negation 响应链具备本功能语义。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "trick_negation":
		return false
	# 当前被响应锦囊定义；全体或全体其他角色目标模式视为群体锦囊。
	var trick_definition: Dictionary = GameDatabase.get_card(str(context.get("trick_id", "")))
	return str(trick_definition.get("target_mode", "")) in ["all_players", "all_others"] and int(context.get("parent_card_uid", -1)) >= 0


## 判断当前请求是否应按已开启状态自动提交空响应；实体 UID 保证同名下一张锦囊不会继承开关。
func _is_suppressed_group_trick_choice(choice_data: Dictionary) -> bool:
	if _suppressed_group_trick_uid < 0 or not _is_group_trick_negation_choice(choice_data):
		return false
	# 当前父锦囊实体 UID；必须与正在抑制的同一处理区实体完全一致。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	return int(context.get("parent_card_uid", -1)) == _suppressed_group_trick_uid


## 返回右侧按钮当前是否承担群体锦囊响应开关；已开启期间即使暂时没有询问也保持可取消。
func _has_group_trick_response_button_context() -> bool:
	return _suppressed_group_trick_uid >= 0 or _is_group_trick_negation_choice(_inline_card_choice)


## 切换本次群体锦囊的不响应状态；开启时同时放弃当前无懈询问，关闭时等待后续询问正常出现。
func _toggle_group_trick_suppression() -> void:
	if _suppressed_group_trick_uid >= 0:
		_suppressed_group_trick_uid = -1
		_refresh_selection_text()
		return
	if not _is_group_trick_negation_choice(_inline_card_choice):
		return
	# 当前无懈询问所属群体锦囊实体 UID；开关只持续到该实体离开处理区。
	var context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
	_suppressed_group_trick_uid = int(context.get("parent_card_uid", -1))
	_refresh_group_trick_response_button()
	# 开启后立即以空选择放弃当前询问；后续同一锦囊请求由自动提交入口继续跳过。
	_submit_inline_card_choice([])


## 为已经开启不响应的后续无懈请求提交空选择；提交前复核请求仍活动且仍属于同一锦囊。
func _submit_suppressed_group_trick_choice(choice_data: Dictionary) -> void:
	if not _is_suppressed_group_trick_choice(choice_data):
		# 延迟提交执行前玩家可能已经取消开关；请求仍活动时重新进入正常渲染，避免留下不可见的待响应窗口。
		if match_controller.has_pending_card_choice():
			_on_card_choice_requested(choice_data)
		return
	# 自动放弃动作；仍经过控制器 request ID、响应者、数量和 allow_cancel 权威校验。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {"request_id":int(choice_data.get("request_id", -1)), "selected_card_uids":[]}
	match_controller.submit_action(action)


## 根据当前群体锦囊响应状态复用右侧按钮；开启时使用深灰外观，关闭时保留朱红可切换外观。
func _refresh_group_trick_response_button() -> void:
	if not is_node_ready() or end_play_button == null:
		return
	if not _has_group_trick_response_button_context():
		end_play_button.text = "回合结束"
		BattleUIStyle.apply_interaction_button(end_play_button, BattleUIStyle.get_color("end_play_button", END_PLAY_BUTTON_COLOR), BattleUIStyle.get_color("end_play_border", END_PLAY_BUTTON_BORDER_COLOR), true)
		return
	end_play_button.visible = true
	end_play_button.disabled = false
	end_play_button.text = "不响应该锦囊"
	if _suppressed_group_trick_uid >= 0:
		BattleUIStyle.apply_interaction_button(end_play_button, BattleUIStyle.get_color("suppressed_button", SUPPRESSED_TRICK_BUTTON_COLOR), BattleUIStyle.get_color("suppressed_border", SUPPRESSED_TRICK_BUTTON_BORDER_COLOR), false)
	else:
		BattleUIStyle.apply_interaction_button(end_play_button, BattleUIStyle.get_color("end_play_button", END_PLAY_BUTTON_COLOR), BattleUIStyle.get_color("end_play_border", END_PLAY_BUTTON_BORDER_COLOR), true)


## 判断当前选中实体牌是否位于普通手牌区；木牛流马“粮”不属于可重铸来源。
func _can_recast_selected_card() -> bool:
	if _selected_card_uid < 0:
		return false
	# 本地玩家快照；重铸只允许普通手牌，木牛流马下的“粮”只能使用或打出，不能进入重铸动作。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	for card_variant: Variant in local_player.get("hand", []):
		# 当前普通手牌；稳定 UID 匹配时确认规则动作与按钮展示保持一致。
		var hand_card: Dictionary = card_variant as Dictionary
		if int(hand_card.get("uid", -1)) == _selected_card_uid:
			return true
	return false


## 同步所有动态卡牌与角色组件的选中、合法目标和目标顺序视觉。
func _refresh_component_states() -> void:
	for card_uid_variant: Variant in _card_views.keys():
		# 当前卡牌 UID；用于判断该视图是否对应已选实体牌。
		var card_uid: int = int(card_uid_variant)
		# 当前选中状态；装备材料、内联多选与普通出牌按当前互斥模式读取各自唯一临时数组。
		var card_selected: bool = _equipment_action_material_uids.has(card_uid) if not _active_equipment_action.is_empty() else (_inline_selected_card_uids.has(card_uid) if not _inline_card_choice.is_empty() else card_uid == _selected_card_uid)
		(_card_views[card_uid] as CardView).set_selected_state(card_selected)
	# 本地装备堆叠组件；与手牌同步候选位移和选中描边，不创建第二套选择状态。
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	# 合法目标 ID 数组；没有选牌时为空，角色卡保持普通状态。
	# 单目标牌已有选择时仍补充空选择预览中的候选，以支持直接切换目标。
	var legal_target_ids: Array[int] = _get_selectable_target_ids()
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


## 返回卡牌交互文本使用的武将名；武将信息尚未公开时才使用调用方提供的玩家名占位。
func _snapshot_character_name(player_snapshot: Dictionary, fallback_name: String) -> String:
	# 当前公开武将 ID；空值表示选将尚未完成或该观察者暂时不可见。
	var character_id: String = str(player_snapshot.get("character_id", ""))
	if character_id.is_empty():
		return fallback_name
	# 当前武将显示名；统一通过数据仓库解析，避免卡牌询问暴露“[AI]玩家X”等控制权标签。
	var character_name: String = GameDatabase.resolve_character_name(character_id)
	return character_name if not character_name.is_empty() else fallback_name


## 删除容器全部子节点；节点排队释放后不再参与后续布局。
func _clear_container(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


## 将阶段 ID 转换为中文界面文本。
func _phase_text(phase: String) -> String:
	return {"setup":"准备", "character_selection":"选将阶段", "start":"开始阶段", "judgment":"判定阶段", "draw":"摸牌阶段", "play":"出牌阶段", "choice":"等待选择", "discard":"弃牌阶段", "finish":"结束阶段", "game_over":"对局结束"}.get(phase, phase)


## 返回一至十号座次的中文数字；座次标签属于游戏内座位容器，超出当前模式上限时回退阿拉伯数字。
func _seat_text(seat_number: int) -> String:
	return {1:"一", 2:"二", 3:"三", 4:"四", 5:"五", 6:"六", 7:"七", 8:"八", 9:"九", 10:"十"}.get(seat_number, str(seat_number))
