extends Control

## 标准身份局演示桌面。界面只提交 PlayerAction 并渲染快照，不直接修改任何对局状态。

## 游戏内座位容器场景；运行时把独立座次标签放在武将牌下方，不把标签混入武将牌编辑场景。
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")

## 正式卡牌视图场景；手牌、木牛“粮”、拖拽预览与不可见牌动画均复用同一完整牌面模型。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 可自动锁定自身目标的牌定义 ID；【桃】【酒】与【无中生有】按自身牌规则自动选择本人，自身限定装备另由目标模式通用判断。
## 【闪电】同样只有使用者本人这一名合法目标，因此与既有自身牌共用自动锁定流程。
const AUTO_SELECTED_SELF_CARD_DEFINITION_IDS: Array[String] = ["tao", "jiu", "wuzhong", "shandian"]

## 统一信息框场景；手牌、装备、技能与武将牌共用该组件，不再创建 Godot 原生工具提示。
const INFORMATION_BOX_LAYER_SCENE: PackedScene = preload("res://scenes/components/information_box_layer.tscn")

## 全体机缘选择弹窗场景；选择时只渲染本地观察者的私有候选，投票收齐后渲染全员公开结果，并仅提交稳定机缘卡ID。
const OPPORTUNITY_CHOICE_PANEL_SCENE: PackedScene = preload("res://scenes/components/opportunity_choice_panel.tscn")

## 游戏终局结算场景；只读取终局快照中的累计统计，关闭后由终局操作区再次打开。
const GAME_SETTLEMENT_PANEL_SCENE: PackedScene = preload("res://scenes/components/game_settlement_panel.tscn")

## 阿哈时刻过场动画场景；订阅控制器的阿哈时刻开始信号后播放绿幕过场视频，不参与任何规则结算。
const AHHA_MOMENT_CUTSCENE_SCENE: PackedScene = preload("res://scenes/components/ahha_moment_cutscene.tscn")

## 音频服务自动加载路径；终局胜负需要按本机视角发声，因此由表现层直接请求而不经过核心层广播。
const AUDIO_SERVICE_PATH: String = "/root/AudioService"

## 终局效果音标识：本机玩家属于权威胜者阵营。
const MATCH_RESULT_EFFECT_WIN: String = "win"

## 终局效果音标识：本机玩家不属于权威胜者阵营。
const MATCH_RESULT_EFFECT_LOSE: String = "lose"

## 终局效果音标识：牌堆与弃牌堆同时耗尽导致的中性平局。
const MATCH_RESULT_EFFECT_TIE: String = "tie"

## 断线自动重连期间顶部横幅的常显秒数；默认3600秒远大于整个重连窗口，重连结束时由新的默认时长横幅覆盖淡出。
const RECONNECT_NOTICE_HOLD_SECONDS: float = 3600.0

## 中央确定与取消按钮的固定最小尺寸；146×42像素与界面文档的主操作规格一致。
const ACTION_BUTTON_MINIMUM_SIZE: Vector2 = Vector2(146.0, 42.0)

## 中央确定与取消按钮的水平间距；默认28像素避免两个相反命令视觉粘连，运行时无需修改。
const ACTION_BUTTON_SEPARATION: int = 28

## 【振旗】三项内联选择按钮的最小尺寸；默认104×42像素，保证三个按钮能在原操作区中并列显示。
const ZHENQI_ACTION_BUTTON_MINIMUM_SIZE: Vector2 = Vector2(104.0, 42.0)

## 牌堆位次询问的选择类型标识；与 MatchController.CARD_POSITION_CHOICE_TYPE 逐字一致。
## 该类型同时具备「手牌维度」与「文字选项维度」，因此由内联控制询问入口接管，而不是打开独立窗口。
const CARD_POSITION_CHOICE_TYPE: String = "card_position"

## 组合选择上下文键：声明哪一个文字选项在界面语义上等同于「取消」。
## 与 MatchController.CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID 逐字一致；界面因此不需要认识任何具体选项 ID。
const CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID: String = "control_cancel_option_id"

## 技能发动名称的字体尺寸；默认28像素使短技能名能在武将牌插画中心清晰辨认，运行时无需动态修改。
const SKILL_ACTIVATION_FONT_SIZE: int = 28

## 技能发动名称的黑色描边宽度；默认6像素保证文字不会与任意明暗插画混淆，运行时无需动态修改。
const SKILL_ACTIVATION_OUTLINE_SIZE: int = 6

## 技能发动名称保持完全可见的时长；默认0.48秒让玩家确认发动来源，运行时无需动态修改。
const SKILL_ACTIVATION_HOLD_SECONDS: float = 0.48

## 技能发动名称淡出的时长；默认0.32秒使提示自然收尾且不遮挡后续操作，运行时无需动态修改。
const SKILL_ACTIVATION_FADE_SECONDS: float = 0.32

## 技能发动名称的绘制层级；默认34，高于30层的飞牌与底部手牌，低于40层的选将遮罩和50层菜单。
## 取值必须高于卡牌表现层的最高偏移（批次摸牌 +3，绝对33）：子节点层级会叠加在动画层之上，提示名要盖住全部飞牌就不能停在31层。
const SKILL_ACTIVATION_Z_INDEX: int = 34

## 头顶聊天气泡的绘制层级；默认38高于技能发动提示与“记录”面板（35），低于选将遮罩（40）与聊天窗口（45）。
const CHAT_BUBBLE_Z_INDEX: int = 38

## 头顶聊天气泡与武将牌上边缘的垂直间距像素；默认6保持气泡贴近发言者又不遮挡体力行。
const CHAT_BUBBLE_VERTICAL_GAP: float = 6.0

## 托管手牌覆盖层的默认绘制层级；默认5保证滤镜位于普通手牌之上，并保留本地技能按钮与武将牌的更高层级。
const AUTO_MANAGED_HAND_OVERLAY_Z_INDEX: int = 5

## 本地技能栏相对托管覆盖层的最小绘制层级；默认6让托管滤镜横向延伸后仍不会挡住任何技能按钮。
const LOCAL_SKILL_BAR_Z_INDEX: int = 6

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

## 技能区相对本地武将牌底边的附加偏移；默认0表示两者底边平行，实际客户区偏移还会减去武将牌底部留白。
const LOCAL_SKILL_BOTTOM_OFFSET: float = 0.0

## 手牌区与最左侧技能按钮之间的水平间距；默认8像素保持两个交互区域相邻但不重叠。
const HAND_SKILL_GAP: float = 8.0

## 本地武将座位左边界相对主场景右边缘的偏移；无技能时手牌栏延伸到该边界左侧。
const LOCAL_PLAYER_SEAT_LEFT_OFFSET: float = -164.35

## 本地装备区与手牌区的统一高度；175像素覆盖148像素牌面、18像素选中抬升及悬停缩放余量。
const LOCAL_CARD_AREA_HEIGHT: float = 175.0

## 本地延时锦囊标记区的固定高度；22像素与武将牌原判定菱形尺寸保持一致，避免移动后改变图标比例。
const LOCAL_JUDGMENT_ZONE_HEIGHT: float = 22.0

## 本地延时锦囊标记区与手牌区顶边之间的间距；6像素使图标不压住手牌选中抬升空间。
const LOCAL_JUDGMENT_ZONE_HAND_GAP: float = 6.0

## 本地公开标记横排的固定高度；20像素等于单枚圆形标记直径，多个标记只横向增长。
const LOCAL_PLAYER_MARKER_ZONE_HEIGHT: float = 20.0

## 本地公开标记横排与右侧判定区之间的水平间距；默认8像素防止圆形图标与判定菱形相贴。
## 当前标记缩小后间距调整为2像素；判定区仍保留独立的左侧安全偏移。
## 当前主视角标记已移至手牌栏右上方，本常量仅保留给旧场景或外部脚本兼容，不参与现行布局。
const LOCAL_PLAYER_MARKER_JUDGMENT_GAP: float = 2.0

## 本地公开标记与武将牌左边缘之间的间距；默认2像素让标记紧贴武将牌，同时保持独立悬停命中区域。
## 当前主视角不再锚定本地武将牌左侧，本常量仅保留给旧场景或外部脚本兼容，不参与现行布局。
const LOCAL_PLAYER_MARKER_CARD_GAP: float = 2.0

## 本地主视角标记相对手牌栏顶边的下移量；默认8像素让标记位于手牌栏右上方且不压住判定牌。
const LOCAL_PLAYER_MARKER_HAND_TOP_OFFSET: float = 8.0

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

## 对局时长标签的检查间隔；0.25秒把每帧轮询降低为每秒4次，同时让整秒显示延迟最多为0.25秒。
## 该参数只影响客户端文本刷新频率，不改变规则计时、动画、AI延迟或游戏流程，运行时无需动态修改。
const MATCH_CLOCK_REFRESH_INTERVAL_SECONDS: float = 0.25

## 顶栏关卡、轮次、牌堆剩余数与对局时长的统一字号；16像素沿用原有下两行文字规格，运行时无需动态修改。
const TOP_INFO_PRIMARY_FONT_SIZE: int = 16

## 本地玩家目标指示锚点与手牌区顶边的垂直间距；默认8像素让线端点位于手牌上方且不遮挡牌面，运行时通常无需修改。
@export_range(0.0, 48.0, 1.0) var local_hand_indicator_margin: float = 8.0

## 本地获得牌动画起点距离手牌区右边缘的额外间距；默认24像素让新牌从区域外清晰进入，运行时可按主题调整。
## 真实获得牌已改为从真实来源直飞最终槽位，本参数现在只服务虚拟手牌候选与虚拟牌回归的右侧入场表现。
@export_range(0.0, 96.0, 1.0) var local_hand_gain_entry_margin: float = 24.0

## 本地正式获得牌从右侧进入手牌布局的持续时间；默认0.42秒与通用飞牌节奏一致，可在检查器中独立调整。
## 当前默认0.24秒以匹配加快后的摸牌节奏；同一正式手牌入场逻辑也服务于其他获得牌，从而保持本地手牌反馈一致。
## 真实获得牌已改为从真实来源直飞最终槽位、落地即到位，本参数现在只服务虚拟手牌候选与虚拟牌回归的右侧入场表现。
@export_range(0.1, 1.5, 0.01) var local_hand_gain_duration: float = 0.24

## 虚拟手牌替换请求期间真实手牌向左离场、可选牌向右离场的持续时间。
## 默认0.24秒与摸牌入场保持一致，使“手牌换成可选牌再换回来”的往复节奏读起来是同一个动作，运行时可按主题调整。
@export_range(0.1, 1.5, 0.01) var local_hand_exit_duration: float = 0.24

## 手牌离场时越过可视手牌区边缘的额外距离；默认24像素与 local_hand_gain_entry_margin 左右对称。
## 该距离保证离场牌完全离开滚动区裁剪范围，运行时通常无需修改。
@export_range(0.0, 96.0, 1.0) var local_hand_exit_margin: float = 24.0

## 主视角武将牌与客户区底边之间的垂直留白；默认0像素为十人局右侧下方座位腾出完整的垂直安全区，运行时通常无需动态修改。
@export_range(0.0, 96.0, 1.0) var local_player_card_bottom_margin: float = 0.0

## 第一视角判定区相对手牌左边界的右移距离；默认120像素避开左侧“托管”按钮，运行时通常无需动态修改。
@export_range(0.0, 240.0, 1.0) var local_judgment_zone_left_offset: float = 120.0

## 对局控制器节点路径；默认指向同场景根节点下的 MatchController，运行时无需修改。
@export var match_controller_path: NodePath = NodePath("MatchController")

## 对局控制器引用；只调用公开动作与查询接口。
@onready var match_controller: MatchController = get_node(match_controller_path) as MatchController

## 顶栏阶段文本；展示当前回合、阶段与牌堆数量。
@onready var phase_label: Label = %PhaseLabel

## 顶栏过关斩将关卡文本；仅该模式显示并与轮次文本同排，不覆盖通用轮次信息。
@onready var conquest_level_label: Label = %ConquestLevelLabel

## 顶栏关卡与轮次共享的标签样式；运行时直接绑定字体、字号和主题色，避免两个独立主题覆盖发生漂移。
var _top_info_primary_label_settings: LabelSettings

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

## 安卓系统返回键适配组件；只在标准取消动作无人处理时向牌桌请求页面级回退。
@onready var android_back_adapter: AndroidBackAdapter = %AndroidBackAdapter

## 启动主菜单组件；负责在对局创建前选择身份模式、调整设置并发出统一开局请求。
@onready var main_menu: MainMenu = %MainMenu

## 局域网大厅组件；只渲染连接参数与公共成员快照，所有网络调用由牌桌协调器统一处理。
@onready var lan_lobby_panel: LanLobbyPanel = %LanLobbyPanel

## 连接成功后的联机大厅组件；渲染纯插画玩家位置、聊天和房间控制，网络动作仍由牌桌协调。
@onready var online_lobby_panel: OnlineLobbyPanel = %OnlineLobbyPanel

## 选将遮罩组件；只渲染裁剪后的候选快照并发出稳定武将 ID 选择请求。
@onready var character_selection_panel: CharacterSelectionPanel = %CharacterSelectionPanel

## 通用卡牌选择组件；响应、弃牌、目标区域和展示牌选择都复用该面板。
@onready var card_selection_panel: CardSelectionPanel = $CardSelectionPanel

## 其他玩家与本地玩家状态卡容器；每次快照整体重建以避免状态残留。
## 实际运行时按玩家 ID 持久复用其他玩家座位节点，仅在玩家集合变化时创建或释放，并由组件对重复布局进行去重。
@onready var player_grid: DecadeBattleLayout = %PlayerGrid

## 本地玩家装备区文本；固定显示在牌桌左下角，与右下角武将牌分离。
## 当前节点已重构为独立装备堆叠组件；保留原变量名以避免破坏桌面脚本既有引用。
@onready var equipment_label: EquipmentStackView = %EquipmentStack

## 牌桌统一信息框组件；运行时实例化后集中处理目标旁说明和居中武将详情。
var information_box: InformationBoxLayer

## 机缘选择弹窗组件；规则暂停期间保持可输入，所有效果仍由MatchController权威结算。
var opportunity_choice_panel: OpportunityChoicePanel

## 游戏结算弹窗组件；只展示权威快照已累计的战绩，不参与胜负判定或数值计算。
var game_settlement_panel: GameSettlementPanel

## 局内聊天窗口组件；由局内菜单“聊天”按钮切换显隐，消息权威登记与广播由 NetworkGateway 负责。
var match_chat_panel: MatchChatPanel

## 阿哈时刻过场动画组件；只订阅控制器的阿哈时刻开始信号播放绿幕视频，规则流程不等待其播放结果。
var ahha_moment_cutscene: AhhaMomentCutscene

## 按发言者稳定玩家 ID 复用的头顶聊天气泡；键为玩家 ID，值为 ChatBubbleView，新消息复用同一气泡节点。
var _chat_bubbles: Dictionary = {}

## 对局回放录制器；持续把本机收到的观察者快照与日志写入临时文件，结算面板“保存回放”时落盘为正式回放。
var _match_replay_recorder: MatchReplayRecorder = MatchReplayRecorder.new()

## 对局回放重演驱动器；播放回放时按录制节奏把快照与日志重新送入牌桌表现入口，首次播放时创建并复用。
var _match_replay_playback_driver: MatchReplayPlaybackDriver = null

## 对局回放重演覆盖层；重演期间封锁桌面输入并提供速度选择与退出入口，首次播放时创建并复用。
var _match_replay_overlay: MatchReplayOverlay = null

## 当前是否处于回放重演会话；重演期间桌面只渲染回放快照、禁止全部操作提交并暂停回放录制。
var _replay_session_active: bool = false

## 回放重演读取目录覆盖路径；自动化测试指向独立目录避免依赖玩家回放，空字符串表示正式回放目录。
var replay_playback_directory_override: String = ""

## 进入重演前的本机第一视角玩家 ID；退出回放时恢复，避免重演视角影响之后的正常开局。
var _replay_previous_local_player_id: int = 0

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

## 本地延时锦囊独立标记区；运行时固定布局到手牌区上方，不再随右下武将牌移动。
var local_judgment_zone: JudgmentZoneView

## 本地玩家公开标记横排；从手牌栏上方左侧开始排列，并与其他角色纵排复用相同图标和悬停协议。
var local_player_markers: PlayerMarkersView

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

## 终局结算界面按钮；仅在整局结束后显示，位于重新开始与返回主菜单之间。
@onready var settlement_button: Button = %SettlementButton

## 重铸按钮；只对配置允许重铸的牌生效，规则核心负责最终校验。
## 该节点仅为旧场景兼容而保留并始终隐藏；实际重铸入口是无目标选择【铁索连环】后点击中央“确定”。
@onready var recast_button: Button = %RecastButton

## 结束出牌按钮；仅本地玩家的出牌阶段可用。
@onready var end_play_button: Button = %EndPlayButton

## 对局日志文本框；只追加规则核心发出的永久语义日志。
@onready var log_view: RichTextLabel = %LogView

## 可折叠对局日志组件；只读取其展开信号，离线暂停所有权由牌桌统一维护。
@onready var match_log_panel: MatchLogPanel = $LogPanel

## 本地玩家托管开关；位于“记录”按钮旁，只提交标准托管动作，不直接注册或移除 AI。
@onready var auto_manage_button: Button = %AutoManageButton

## 本地手牌托管覆盖组件；根据权威快照遮挡手牌并拦截指针输入，动态文字由组件自身驱动。
@onready var auto_managed_hand_overlay: PlayerAutoManagedHandOverlay = %AutoManagedHandOverlay

## 错误提示文本；显示最近一次被规则核心拒绝的原因。
@onready var error_label: Label = %ErrorLabel

## 最近一次控制器拒绝信息；同步重开失败时用于把同一原因交还主菜单，不从标签文本反向推导业务反馈。
var _last_action_rejection_message: String = ""

## 最近一次本地可见状态快照；界面刷新与选择校验均以此为准。
var _snapshot: Dictionary = {}

## 已自动展示结算面板的对局ID；用户手动关闭后保持该ID，避免同一终局快照再次广播时自动弹回。
var _settlement_auto_shown_match_id: String = ""

## 当前快照按稳定玩家 ID 建立的只读索引；每次状态广播重建一次，避免同一帧多处线性扫描玩家数组。
var _player_snapshots_by_id: Dictionary = {}

## 记录牌名只读窗口数据；非空表示该窗口正被打开，它不参与任何规则请求，也不产生规则动作。
## 数据由武将牌角标按钮按下时按当前公开快照构造，关闭时清空。
var _recorded_names_view: Dictionary = {}

## 已读取的卡牌静态定义缓存；值只供界面读取，任何调用方都不得修改返回字典。
var _card_definition_cache: Dictionary = {}

## 已读取的武将静态定义缓存；值只供界面读取，避免每次状态刷新重复深拷贝同一配置。
var _character_definition_cache: Dictionary = {}

## 已读取的势力静态定义缓存；值只供界面读取，主题切换不会改变配置本身。
var _faction_definition_cache: Dictionary = {}

## 最近一次快照中每名玩家的公开体力；键为稳定玩家 ID，用于检测本次快照是否发生真实体力下降。
var _player_hp_by_id: Dictionary = {}

## 最近一次快照中每名玩家的累计受伤次数；键为稳定玩家ID，用于识别被护盾完全吸收但仍实际成立的伤害。
var _player_damage_taken_count_by_id: Dictionary = {}

## 当前体力对账所属对局 ID；重新开局时先建立新基线，不能把新局初始体力误判为受伤。
var _hp_snapshot_match_id: String = ""

## 是否已经建立过至少一份体力基线；允许测试快照使用空对局 ID 时仍区分首次绑定与后续更新。
var _has_hp_snapshot: bool = false

## 当前选中的手牌 UID；未选择时为 -1。
var _selected_card_uid: int = -1

## 当前按点击顺序选择的目标 ID；借刀杀人等牌依赖该顺序。
var _selected_target_ids: Array[int] = []

## 当前因【桃】【酒】或【无中生有】自身目标而自动锁定的目标 ID；默认-1表示玩家必须自行选择目标。
var _auto_locked_target_id: int = -1

## 当前手牌 UID 到正式卡牌视图的映射；快照刷新按 UID 复用节点，实体离开本人牌区后才移除。
var _card_views: Dictionary = {}

## 当前普通手牌的本地显示顺序；只影响本客户端手牌布局，新获得的牌会按权威快照追加到末尾。
var _local_hand_display_order: Array[int] = []

## 当前木牛流马“粮”的本地显示顺序；只允许在木牛分区内调整，永远位于普通手牌左侧。
var _local_wooden_ox_display_order: Array[int] = []

## 当前本地手牌排序所属的对局 ID；切换对局时清空旧排序，避免不同实体 UID 的新局继承旧布局。
var _hand_order_match_id: String = ""

## 当前正在直接拖动的本地手牌实体 UID；默认-1表示没有原牌节点处于鼠标跟随状态。
var _active_hand_drag_card_uid: int = -1

## 已收到转移信号、等待正式手牌节点进入当前快照的本地获得牌 UID 集合；键为实体 UID，值固定为 true。
var _pending_local_hand_gain_uids: Dictionary = {}

## 正在从手牌区右侧进入的正式手牌 UID 到补间映射；快照刷新复用同一节点，不会创建或销毁替代牌面。
var _local_hand_gain_tweens: Dictionary = {}

## 本机获得牌的前置飞行门闸；键为实体 UID，值为该牌本次飞行的记录字典。
## 记录字段：card=本次飞行使用的牌面（自愈判定用，牌面已释放说明落地回调不会再来）；
## origin=飞行起点（动画层坐标）；started=飞行是否已经起飞；batch=所属摸牌批次 ID（-1 表示单张获得）；
## snapshot_generation=登记该门闸时已生效的快照代次（用于区分“尚未进入快照”与“已经离开手牌”）。
## 门闸存在期间，对应正式手牌节点必须停留在本次飞行的起点——该点位于手牌滚动区之外因而被裁剪不可见，
## 于是玩家看到的是一张牌从来源连续飞向槽位，而不是“先出现在槽位再被飞入一次”。
## 门闸正常只由飞行落地回调解除：落地那一帧节点直接出现在自己的槽位，不再有第二段滑动；
## 保持飞行牌面是为了让保持阶段能识别“飞行牌已消失但回调不会再来”的异常情况并自动补齐解闸，
## 重新开局、牌离开手牌区或飞行被清理时也会一并清除，避免残留门闸让手牌永远停在屏幕外。
var _local_hand_gain_flight_gates: Dictionary = {}

## 本地手牌快照代次；每收到一次本地快照自增一次，供门闸判断对账所用快照是否已经晚于本次飞行登记。
## 存在原因：转移信号先于权威快照到达，而询问界面等入口会在同一帧用**旧快照**重新对账手牌；
## 若把“旧快照里没有这张牌”当成“这张牌已经离开手牌”，正在等待起飞的飞行就会被误取消（表现为摸牌跳过动画直接进手牌）。
var _local_hand_snapshot_generation: int = 0

## 已登记但尚未起飞的本机摸牌批次；键为控制器分配的批次 ID，值为该批未起飞成员的牌面映射与飞行起点。
## 逐张结构为 {"views_by_uid":{实体 UID:牌面}, "origin":飞行起点}；成员起飞或离场后逐个摘除。
## 之所以延后起飞：批次完成信号早于权威快照，只有快照布局之后才知道这批牌各自的手牌槽位。
var _pending_local_draw_batches: Dictionary = {}

## 当前虚拟手牌替换模式是否已经生效；为 true 时手牌区显示的是技能请求声明的可选虚拟牌而不是真实手牌。
var _virtual_hand_choice_active: bool = false

## 虚拟手牌入场序列是否仍在播放真实手牌离场动画；期间禁止重新对账手牌，避免打断离场补间。
var _virtual_hand_entry_playing: bool = false

## 虚拟手牌离场序列是否已经启动；防止连续快照刷新重复播放同一段离场动画。
var _virtual_hand_exit_playing: bool = false

## 当前显示的虚拟手牌占位 UID 到卡牌视图映射；只保存界面节点，虚拟牌不会写入权威对局状态。
## 同一批节点同时登记在 _card_views 中，以复用统一的选中描边、悬停与入场动画链路。
var _virtual_hand_views: Dictionary = {}

## 当前正在向左离场的真实手牌补间；补间对象由整批手牌共享，重新开局时统一停止。
var _local_hand_exit_tween: Tween

## 当前正在向右离场的虚拟手牌补间；补间对象由整批虚拟牌共享，重新开局时统一停止。
var _virtual_hand_exit_tween: Tween

## 当前等待批次完成的摸牌表现数据；键为控制器分配的稳定批次 ID，值保存目标玩家和按牌堆顺序到达的瞬时牌面副本。
var _draw_presentation_batches: Dictionary = {}

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

## 最近一次已经渲染技能栏的本地身份；与武将 ID 共同决定领袖技是否需要创建按钮。
var _rendered_skill_identity: String = ""

## 最近一次已经渲染技能栏的可见技能列表签名；武将固有技能、模式技能与局内临时技能变化时必须重建按钮。
var _rendered_skill_list_signature: String = ""

## 当前已选卡牌的只读规则预览；由 MatchController 查询接口生成，不包含权威对象引用。
var _card_use_preview: Dictionary = {}

## 当前在本地手牌区完成的选择请求快照；空字典表示使用普通出牌交互或独立选择窗口。
var _inline_card_choice: Dictionary = {}

## 当前内联请求中按点击顺序选择的实体牌 UID；支持弃牌阶段一次选择多张手牌。
var _inline_selected_card_uids: Array[int] = []

## 当前内联响应中由玩家明确点击的转化技能ID；空字符串表示只开放可直接响应的实体牌。
var _active_response_skill_id: String = ""

## 【振旗】内联取消按钮；仅在费用选择时显示，与原确定/取消按钮共同组成三项直接选择。
var _zhenqi_cancel_button: Button

## 当前内联文字选项映射到原“确定”按钮的稳定选项 ID；空字符串表示该按钮应执行普通确认或当前没有文字选项请求。
var _inline_control_primary_option_id: String = ""

## 当前内联文字选项映射到原“取消”按钮的稳定选项 ID；空字符串时该按钮保留为真正的放弃操作。
var _inline_control_secondary_option_id: String = ""

## 超出原确定/取消两枚按钮容量的内联文字选项按钮；每次请求刷新时重建，仅保存客户端表现节点。
var _inline_control_extra_option_buttons: Array[Button] = []

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

## 最新权威快照确认的本人待办请求 ID 清单；并行无懈会同时存在多条，单槽位请求编号无法表达全部待办。
var _local_pending_choice_request_ids: Array[int] = []

## 最新快照是否携带本人待办请求清单字段；false 表示旧回放或纯界面测试快照，对账回落到单槽位请求编号。
var _has_local_pending_choice_request_ids: bool = false

## 当前计时器绑定的对局 ID；对局 ID 变化时重置开始时间，避免重新开局继承旧时长。
var _timed_match_id: String = ""

## 当前对局开始时的单调毫秒时间；默认-1表示尚未收到有效对局快照。
var _match_started_msec: int = -1

## 当前对局结束时的单调毫秒时间；默认-1表示仍在进行，用于终局后冻结显示时长。
var _match_finished_msec: int = -1

## 最近一次写入左上角的整秒时长；默认-1强制首个有效快照立即刷新。
var _last_rendered_duration_seconds: int = -1

## 对局时长低频刷新计时器；仅在有效对局进行期间运行，主菜单与终局保持停止，运行时不得替换。
var _match_clock_timer: Timer

## 当前通过点击装备进入的主动交互类型；空字符串表示普通出牌或普通内联选择，具体字符串来自装备定义元数据。
var _active_equipment_action: String = ""

## 当前被点击发动的装备实体 UID；默认-1，提交时核心会再次确认同一装备仍位于原槽位。
var _active_equipment_uid: int = -1

## 当前装备主动交互中按点击顺序选择的普通手牌材料 UID；丈八固定需要2张，木牛固定需要1张。
var _equipment_action_material_uids: Array[int] = []

## 当前客户端为未知玩家身份保存的本地标注；键为稳定玩家 ID，值为忠臣、反贼或内奸身份 ID。
var _identity_marks: Dictionary = {}

## 当前本地身份标注所归属的对局 ID；默认空字符串表示尚未建立归属。
## 它只用于识别“新的一局”，值变化即清空上一局的手动标注；同一对局（含联机断线重连）内不清理，
## 因为联机客户端的牌桌节点跨局常驻，本地标注不会随场景重建自动消失。
var _identity_marks_match_id: String = ""

## 身份标注弹出菜单当前对应的玩家 ID；默认-1表示没有等待选择的身份徽记。
var _identity_mark_target_id: int = -1

## 身份标注弹出菜单；只提供忠臣、反贼和内奸三个本地标记选项，不包含领袖。
## 菜单额外提供“？”作为清除本地推测的入口，四项均只显示单字简写。
var _identity_mark_menu: PopupMenu

## 当前开启“不响应该锦囊”的群体锦囊实体 UID；默认-1表示未开启，牌离开处理区后自动清除。
var _suppressed_group_trick_uid: int = -1

## 当前场景树暂停是否由离线日志展开触发；只有持有该所有权时，收起日志或退出牌桌才恢复运行。
var _owns_log_pause: bool = false

## 当前日志展开持有的对局暂停令牌；-1表示日志没有通过统一接口暂停对局。
var _log_pause_token: int = -1

## 当前场景树暂停是否由离线武将详情触发；只在持有该所有权时释放对应令牌。
var _owns_character_details_pause: bool = false

## 当前武将详情持有的对局暂停令牌；-1表示详情框没有暂停离线对局。
var _character_details_pause_token: int = -1


## 连接控制器与全局设置，并在首帧启动默认演示对局。
## 当前主菜单流程会等待玩家确认后再创建对局；初始化阶段只连接组件、创建表现节点并保持控制器状态为空。
func _ready() -> void:
	BattleUIStyle.set_active_style(GameSettings.ui_style_id)
	_ensure_skill_button_grid()
	_configure_local_card_areas()
	_configure_interaction_controls()
	_create_information_box()
	_create_local_player_card()
	_create_local_judgment_zone()
	_create_local_player_markers()
	_create_opportunity_choice_panel()
	_create_game_settlement_panel()
	_create_match_chat_panel()
	_create_ahha_moment_cutscene()
	_create_identity_mark_menu()
	_create_match_clock_timer()
	resized.connect(_queue_auto_managed_hand_overlay_layout)
	resized.connect(_queue_local_judgment_zone_layout)
	hand_panel.resized.connect(_queue_auto_managed_hand_overlay_layout)
	hand_panel.resized.connect(_queue_local_judgment_zone_layout)
	local_player_seat_slot.item_rect_changed.connect(_queue_auto_managed_hand_overlay_layout)
	match_controller.state_changed.connect(_on_state_changed)
	match_controller.log_added.connect(_on_log_added)
	match_controller.action_rejected.connect(_on_action_rejected)
	match_controller.self_repair_performed.connect(_on_self_repair_performed)
	match_controller.card_presentation_requested.connect(_on_card_presentation_requested)
	match_controller.card_transfer_requested.connect(_on_card_transfer_requested)
	match_controller.draw_presentation_batch_started.connect(_on_draw_presentation_batch_started)
	match_controller.draw_presentation_batch_finished.connect(_on_draw_presentation_batch_finished)
	match_controller.card_animation_ownership_reset_requested.connect(_on_card_animation_ownership_reset_requested)
	match_controller.skill_activated.connect(_on_skill_activated)
	match_controller.skill_target_indicated.connect(_on_skill_target_indicated)
	match_controller.equipment_activated.connect(_on_equipment_activated)
	match_controller.card_choice_requested.connect(_on_card_choice_requested)
	card_selection_panel.control_submitted.connect(_on_control_choice_submitted)
	card_selection_panel.read_only_view_closed.connect(_on_read_only_view_closed)
	match_controller.public_card_choice_display_changed.connect(_on_public_card_choice_display_changed)
	match_controller.character_selection_changed.connect(_on_character_selection_changed)
	GameSettings.card_name_mode_changed.connect(_on_card_name_mode_changed)
	GameSettings.ui_style_changed.connect(_on_ui_style_changed)
	GameSettings.auto_identity_marking_changed.connect(_on_auto_identity_marking_changed)
	match_controller.ai_coordinator.identity_mark_changed.connect(_on_automatic_identity_mark_changed)
	match_menu.card_name_toggle_requested.connect(_on_name_mode_pressed)
	match_menu.restart_requested.connect(_on_restart_requested)
	match_menu.main_menu_requested.connect(_on_main_menu_requested)
	match_menu.conquest_temporary_exit_toggle_requested.connect(_on_conquest_temporary_exit_toggle_requested)
	match_menu.chat_toggle_requested.connect(_on_match_chat_toggle_requested)
	match_controller.conquest_exit_save_ready.connect(_on_conquest_exit_save_ready)
	match_controller.match_finished.connect(_on_match_finished_for_conquest_save)
	android_back_adapter.unhandled_back_requested.connect(_on_unhandled_android_back_requested)
	main_menu.start_game_requested.connect(_on_main_menu_start_requested)
	main_menu.replay_playback_requested.connect(_on_replay_playback_requested)
	main_menu.visibility_changed.connect(_sync_match_menu_visibility)
	lan_lobby_panel.host_requested.connect(_on_lan_host_requested)
	lan_lobby_panel.join_requested.connect(_on_lan_join_requested)
	lan_lobby_panel.leave_requested.connect(_on_lan_leave_requested)
	online_lobby_panel.chat_requested.connect(_on_lan_lobby_chat_requested)
	online_lobby_panel.seat_change_requested.connect(_on_lan_lobby_seat_change_requested)
	online_lobby_panel.kick_requested.connect(_on_lan_lobby_kick_requested)
	online_lobby_panel.settings_update_requested.connect(_on_lan_lobby_settings_update_requested)
	online_lobby_panel.start_match_requested.connect(_on_lan_start_match_requested)
	online_lobby_panel.leave_requested.connect(_on_lan_leave_requested)
	match_controller.network_gateway.lan_lobby_changed.connect(_on_lan_lobby_changed)
	match_controller.network_gateway.connection_state_changed.connect(_on_lan_connection_state_changed)
	match_controller.network_gateway.lan_match_started.connect(_on_lan_match_started)
	match_controller.network_gateway.lan_session_closed.connect(_on_lan_session_closed)
	match_controller.network_gateway.lan_reconnect_state_changed.connect(_on_lan_reconnect_state_changed)
	match_controller.network_gateway.match_chat_received.connect(_on_match_chat_received)
	match_log_panel.expanded_changed.connect(_on_match_log_expanded_changed)
	match_log_panel.blank_area_pressed.connect(_close_open_match_overlays_from_blank_click)
	auto_manage_button.pressed.connect(_on_auto_manage_pressed)
	auto_managed_hand_overlay.cancel_requested.connect(_on_auto_manage_pressed)
	# 已保存的下一局人数；主菜单与局内菜单共用同一全局配置，首次进入场景时同步覆盖检查器默认值。
	var saved_next_match_player_count: int = GameSettings.next_match_player_count
	match_controller.default_player_count = saved_next_match_player_count
	match_menu.set_next_player_count(saved_next_match_player_count)
	_refresh_match_menu_authority_controls()
	main_menu.set_next_player_count(saved_next_match_player_count)
	main_menu.set_lan_default_port(match_controller.network_gateway.default_lan_port)
	character_selection_panel.selection_submitted.connect(_on_character_selection_submitted)
	character_selection_panel.candidate_replacement_requested.connect(_on_character_candidate_replacement_requested)
	character_selection_panel.custom_assignment_preview_requested.connect(_on_custom_assignment_preview_requested)
	character_selection_panel.information_requested.connect(_on_information_requested.bind(character_selection_panel))
	character_selection_panel.information_dismissed.connect(_on_information_dismissed.bind(character_selection_panel))
	card_selection_panel.choice_submitted.connect(_on_card_choice_submitted)
	card_selection_panel.choice_cancelled.connect(_on_card_choice_cancelled)
	card_selection_panel.arrangement_submitted.connect(_on_pile_arrangement_submitted)
	card_selection_panel.information_requested.connect(_on_information_requested.bind(card_selection_panel))
	card_selection_panel.information_dismissed.connect(_on_information_dismissed.bind(card_selection_panel))
	use_button.pressed.connect(_on_use_pressed)
	settlement_button.pressed.connect(_on_settlement_button_pressed)
	%CancelButton.pressed.connect(_on_cancel_pressed)
	recast_button.pressed.connect(_on_recast_pressed)
	end_play_button.pressed.connect(_on_end_play_pressed)
	equipment_label.equipment_pressed.connect(_on_equipment_pressed)
	equipment_label.information_requested.connect(_on_information_requested.bind(equipment_label))
	equipment_label.information_dismissed.connect(_on_information_dismissed.bind(equipment_label))
	local_player_card.pressed.connect(_on_self_target_pressed)
	local_player_card.corner_action_pressed.connect(_on_corner_action_pressed)
	local_player_card.details_requested.connect(_on_character_details_requested)
	local_player_card.information_requested.connect(_on_information_requested.bind(local_player_card))
	local_player_card.information_dismissed.connect(_on_information_dismissed.bind(local_player_card))
	match_menu.refresh_card_name_text()
	_apply_ui_style()
	_layout_auto_managed_hand_overlay()
	_sync_match_menu_visibility()


## 牌桌退出时只释放自身创建的日志暂停，避免场景切换后 SceneTree 残留暂停状态。
## 武将详情使用另一枚独立令牌，退出牌桌时按相同所有权规则单独释放。
func _exit_tree() -> void:
	if _owns_log_pause and match_controller != null and is_instance_valid(match_controller):
		match_controller.release_gameplay_pause(_log_pause_token)
	_owns_log_pause = false
	_log_pause_token = -1
	if _owns_character_details_pause and match_controller != null and is_instance_valid(match_controller):
		match_controller.release_gameplay_pause(_character_details_pause_token)
	_owns_character_details_pause = false
	_character_details_pause_token = -1


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
func _on_match_clock_timeout() -> void:
	_refresh_match_duration_label()


## 创建牌桌私有的低频时长计时器；初始保持停止，收到有效进行中快照后才开始周期检查。
func _create_match_clock_timer() -> void:
	_match_clock_timer = Timer.new()
	_match_clock_timer.name = "MatchClockTimer"
	_match_clock_timer.wait_time = MATCH_CLOCK_REFRESH_INTERVAL_SECONDS
	_match_clock_timer.one_shot = false
	_match_clock_timer.timeout.connect(_on_match_clock_timeout)
	add_child(_match_clock_timer)


## 统一操作区的运行时节点结构与视觉规格；即使旧场景缺少唯一名称或仍保留旧按钮层级，也能恢复当前交互布局。
func _configure_interaction_controls() -> void:
	interaction_panel.visible = false
	interaction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	use_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	BattleUIStyle.apply_interaction_button(use_button)
	# 终局结算按钮；常态隐藏，仅在整局结束后插入重新开始与返回主菜单之间。
	settlement_button.visible = false
	settlement_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	BattleUIStyle.apply_interaction_button(settlement_button)
	# 中央取消按钮；与确定按钮使用相同尺寸与主按钮样式，避免旧场景资源保留次级按钮外观。
	var cancel_button: Button = %CancelButton
	cancel_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	BattleUIStyle.apply_interaction_button(cancel_button)
	# 【振旗】第三个取消按钮；常态隐藏，费用询问时与原两个位置并列，不创建遮罩窗口。
	_zhenqi_cancel_button = Button.new()
	_zhenqi_cancel_button.name = "ZhenqiCancelButton"
	_zhenqi_cancel_button.visible = false
	_zhenqi_cancel_button.custom_minimum_size = ZHENQI_ACTION_BUTTON_MINIMUM_SIZE
	_zhenqi_cancel_button.text = "取消"
	_zhenqi_cancel_button.pressed.connect(_on_zhenqi_cancel_pressed)
	BattleUIStyle.apply_interaction_button(_zhenqi_cancel_button)
	var action_row: HBoxContainer = $InteractionPanel/InteractionVBox/ActionRow
	action_row.add_child(_zhenqi_cancel_button)
	action_row.add_theme_constant_override("separation", ACTION_BUTTON_SEPARATION)
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
	_identity_mark_menu.add_item("?", 3)
	_identity_mark_menu.add_item("忠", 0)
	_identity_mark_menu.add_item("反", 1)
	_identity_mark_menu.add_item("内", 2)
	_identity_mark_menu.id_pressed.connect(_on_identity_mark_selected)
	add_child(_identity_mark_menu)


## 打开指定未知玩家的身份标注菜单；真实身份已公开或目标为本地玩家时保持无操作。
func _on_identity_badge_pressed(player_id: int) -> void:
	if player_id == match_controller.local_human_player_id:
		return
	# 斗地主身份全明置，不提供本地身份标记菜单。
	if str(_snapshot.get("match_mode", "")) == "doudizhu":
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
		player_view.set_identity_mark(_resolve_display_identity_mark(_identity_mark_target_id))
	_identity_mark_target_id = -1


## 返回指定其他角色当前应显示的本地身份推测；手动标注优先，自动模式只接收共享模型的忠反结果。
func _resolve_display_identity_mark(player_id: int) -> String:
	# 斗地主身份开局全明置，不需要也不显示推测/手动身份标记。
	if str(_snapshot.get("match_mode", GameSettings.next_match_mode if GameSettings != null else "identity")) == "doudizhu":
		return ""
	if _identity_marks.has(player_id):
		return str(_identity_marks.get(player_id, ""))
	if not GameSettings.auto_identity_marking_enabled or match_controller.ai_coordinator == null:
		return ""
	return match_controller.ai_coordinator.get_identity_mark(player_id)


## 响应自动标记开关变化；重新渲染当前持久座位即可切换推测徽记，不改变任何快照数据。
func _on_auto_identity_marking_changed(_enabled: bool) -> void:
	if not _snapshot.is_empty():
		_render_players()


## 接收公开行为产生的单名角色推断变化；仅刷新未知身份、非本地且没有手动覆盖的现有武将牌。
func _on_automatic_identity_mark_changed(player_id: int, _identity_mark: String) -> void:
	if not GameSettings.auto_identity_marking_enabled or _identity_marks.has(player_id) or player_id == match_controller.local_human_player_id:
		return
	# 当前目标公开快照；真实身份已经公开时由权威徽记接管，不再应用本地推断。
	var player: Dictionary = _get_player_snapshot(player_id)
	if player.is_empty() or str(player.get("identity", "hidden")) != "hidden":
		return
	# 当前持久角色牌；只更新身份文本与颜色，不重建牌面、座次或装备节点。
	var player_view: PlayerTargetView = _player_views.get(player_id) as PlayerTargetView
	if player_view != null and is_instance_valid(player_view):
		player_view.set_identity_mark(_resolve_display_identity_mark(player_id))


## 按当前公开快照的对局 ID 收敛身份标注的对局归属；对局 ID 变化即视为进入新的一局并整体清空本地身份推测。
## 手动标注只存在于本地内存，重开对局时玩家 ID 会被复用，因此必须显式按对局边界清理，
## 否则联机客户端（牌桌节点跨局常驻，不经过 _reset_presentation_for_new_match）会继续显示上一局的身份推测。
## 联机断线重连沿用同一 match_id，因此重连回到原对局时玩家自己已有的标注与推断都会被完整保留。
func _sync_identity_marks_match_scope() -> void:
	# 当前快照对局 ID；空字符串用于界面预览与规则测试，与初始值相同因此不会产生多余的清理动作。
	var match_id: String = str(_snapshot.get("match_id", ""))
	if match_id == _identity_marks_match_id:
		return
	_identity_marks_match_id = match_id
	_identity_marks.clear()
	# 未提交的身份标注菜单随旧局一并丢弃；目标玩家 ID 在新局指向另一名角色，继续保留会误标。
	_identity_mark_target_id = -1
	# 共享身份模型同样按对局边界丢弃上一局的公开行为推断：模型只在观察行为或主动同步时才按 match_id 自清，
	# 而联机客户端在新局第一次出牌前不会同步，不重置会让复用座次的武将牌继续显示上一局的忠反推测。
	if match_controller != null and match_controller.ai_coordinator != null:
		match_controller.ai_coordinator.reset_identity_observations()


## 接收主菜单的身份局开局请求；主菜单关闭后才清理旧表现并创建新的权威对局状态。
## 当前失败安全流程先同步尝试创建权威对局，只有返回成功时才通知主菜单关闭；拒绝时入口保持可见并允许重试。
## 过关斩将存在临时退出存档时，主按钮语义为“继续上次游戏”，改走存档恢复入口而不是全新开局。
func _on_main_menu_start_requested(player_count: int) -> void:
	match_menu.set_next_player_count(player_count)
	if GameSettings != null and GameSettings.normalize_match_mode(GameSettings.next_match_mode) == GameSettings.MATCH_MODE_CONQUEST:
		# 当前过关斩将存档；读取成功即恢复上次对局，文件缺失或损坏时按普通新开局处理。
		var conquest_save_data: Dictionary = ConquestSaveStore.read_save()
		if not conquest_save_data.is_empty():
			if _on_conquest_resume_requested(conquest_save_data):
				main_menu.confirm_game_started()
			return
	if _on_restart_requested(player_count):
		main_menu.confirm_game_started()


## 接收连接入口创建房间意图；网关保存形象、密码、人数、模式、自选身份与固定座位初始配置，成功后进入独立联机大厅。
func _on_lan_host_requested(display_name: String, avatar_character_id: String, room_password: String, port: int, player_count: int, custom_identity_enabled: bool, fixed_seat_enabled: bool) -> void:
	# 建房结果；Godot Error 只用于程序判断，玩家可见文本由网关统一返回。
	# 使用主菜单当前下一局模式；斗地主入口建房时自动创建斗地房间。
	var game_mode_id: String = GameSettings.normalize_match_mode(GameSettings.next_match_mode) if GameSettings != null else NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID
	var host_error: Error = match_controller.network_gateway.host_lan(display_name, port, avatar_character_id, room_password, player_count, game_mode_id, custom_identity_enabled, fixed_seat_enabled)
	if host_error != OK:
		lan_lobby_panel.show_error("创建局域网房间失败，请检查端口是否被占用。")


## 接收连接入口加入房间意图；联机形象与密码随握手登记包提交，房主负责最终校验。
func _on_lan_join_requested(display_name: String, avatar_character_id: String, room_password: String, address: String, port: int) -> void:
	# 发起连接结果；OK 只表示客户端已开始连接，不代表房主已经接受大厅登记。
	var join_error: Error = match_controller.network_gateway.join_lan(address, display_name, port, avatar_character_id, room_password)
	if join_error != OK:
		lan_lobby_panel.show_error("无法发起局域网连接，请检查 IP 与端口。")


## 房主从联机大厅请求开始对局；读取权威房间设置建立真人映射，成功后才广播客户端开局。
func _on_lan_start_match_requested() -> void:
	if not match_controller.network_gateway.is_lan_host():
		online_lobby_panel.show_error("只有局域网房主可以开始对局。")
		return
	# 当前权威大厅设置；房主本地读取总人数与稳定模式 ID，不相信界面临时输入。
	var lobby_snapshot: Dictionary = match_controller.network_gateway.get_lan_lobby_snapshot(true)
	# 当前游戏模式；可开局集合由网关唯一维护，身份、斗地主、2v2、车轮战、机缘大乱斗与过关斩将均可创建权威对局。
	var game_mode_id: String = str(lobby_snapshot.get("game_mode_id", NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID))
	if not match_controller.network_gateway.is_game_mode_playable(game_mode_id):
		online_lobby_panel.show_error("当前游戏模式尚未实现。")
		return
	# 当前大厅总人数；过关斩将表示玩家数（2至4），其他模式即规则角色总数。
	var player_count: int = int(lobby_snapshot.get("player_count", 2))
	# 本局规则角色总数；过关斩将为玩家数两倍（每名玩家配一名敌方AI），其他模式与大厅人数一致。
	var role_count: int = NetworkGateway.get_match_role_count_for_mode(game_mode_id, player_count)
	# 开局前写入全局下一局模式；保证 start_match 与局内设置读取到大厅权威模式。
	if GameSettings != null:
		GameSettings.set_next_match_mode(game_mode_id)
		GameSettings.set_next_match_player_count(player_count)
	# 数据配置前置错误；必须在生成成员座次与清理旧表现前返回，房间可原地重试。
	var validation_error: String = match_controller.get_match_start_validation_error(role_count, game_mode_id)
	if not validation_error.is_empty():
		online_lobby_panel.show_error(validation_error)
		return
	# 真人到稳定玩家 ID 的大厅位置映射错误；通常由真人不足2名或总人数小于成员数引起。
	# 网关按大厅语义接收人数，过关斩将在其内部把真人映射到偶数玩家座位并换算角色总数。
	var assignment_error: String = match_controller.network_gateway.prepare_lan_match_assignments(player_count)
	if not assignment_error.is_empty():
		online_lobby_panel.show_error(assignment_error)
		return
	match_menu.set_next_player_count(player_count)
	if not _on_restart_requested(role_count):
		match_controller.network_gateway.cancel_prepared_lan_match()
		# 最近控制器拒绝原因；为空时使用稳定兜底，不把半成品对局广播给客户端。
		var failure_message: String = _last_action_rejection_message if not _last_action_rejection_message.is_empty() else "无法创建局域网对局，请检查数据配置后重试。"
		online_lobby_panel.show_error(failure_message)
		return
	match_controller.network_gateway.begin_prepared_lan_match()
	match_controller.replicate_current_state()


## 转发本地大厅聊天意图；房主网关统一署名、裁剪长度并广播公共聊天历史。
func _on_lan_lobby_chat_requested(message: String) -> void:
	match_controller.network_gateway.send_lan_lobby_chat_message(message)


## 转发本地点击空位的换位意图；房主权威复核目标仍为空后广播新座位。
func _on_lan_lobby_seat_change_requested(seat_index: int) -> void:
	match_controller.network_gateway.request_lan_lobby_seat_change(seat_index)


## 房主请求踢出远端大厅成员；失败原因在联机大厅右下控制区显示。
func _on_lan_lobby_kick_requested(peer_id: int) -> void:
	var kick_error: String = match_controller.network_gateway.kick_lan_lobby_member(peer_id)
	if not kick_error.is_empty():
		online_lobby_panel.show_error(kick_error)


## 房主保存模式、人数、密码、自选身份与固定座位设置；网关校验真人下限并广播完整公共快照。
func _on_lan_lobby_settings_update_requested(game_mode_id: String, player_count: int, room_password: String, custom_identity_enabled: bool, fixed_seat_enabled: bool) -> void:
	var settings_error: String = match_controller.network_gateway.update_lan_lobby_settings(game_mode_id, player_count, room_password, custom_identity_enabled, fixed_seat_enabled)
	if not settings_error.is_empty():
		online_lobby_panel.show_error(settings_error)
		return
	online_lobby_panel.confirm_settings_updated()


## 大厅离开按钮协调入口；未开局时关闭 ENet 会话并恢复普通主菜单，不触碰任何规则状态。
func _on_lan_leave_requested() -> void:
	match_controller.network_gateway.leave_lan("")
	match_controller.clear_remote_network_state()
	# 连接入口会话状态；先复位已禁用的建房/加入按钮，再由主菜单隐藏入口，确保下次打开可以立即重新创建房间。
	lan_lobby_panel.return_to_entry()
	main_menu.close_lan_panel()
	_refresh_match_menu_authority_controls()


## 绑定房主广播的公共大厅成员表；房主额外显示本机可分享 IPv4 地址，客户端不显示网卡列表。
func _on_lan_lobby_changed(lobby_snapshot: Dictionary) -> void:
	# 房主地址列表；显式创建强类型空数组，避免三元表达式的无类型空数组使客户端加入时发生类型赋值错误。
	var host_addresses: Array[String] = []
	if match_controller.network_gateway.is_lan_host():
		host_addresses = match_controller.network_gateway.get_lan_ipv4_addresses()
	lan_lobby_panel.bind_lobby(lobby_snapshot, host_addresses)
	# 房主私有大厅设置；只在房主本机补充明文密码，远端公共快照始终只有 has_password 布尔值。
	var display_snapshot: Dictionary = match_controller.network_gateway.get_lan_lobby_snapshot(true) if match_controller.network_gateway.is_lan_host() else lobby_snapshot.duplicate(true)
	online_lobby_panel.bind_lobby(display_snapshot, host_addresses, lan_lobby_panel.get_port())
	main_menu.show_online_lobby()
	_refresh_match_menu_authority_controls()


## 把网关连接状态转交大厅状态栏；该回调不据文本推断角色或对局阶段。
func _on_lan_connection_state_changed(is_connected: bool, message: String) -> void:
	lan_lobby_panel.bind_connection_state(is_connected, message)


## 接收局域网开局绑定；客户端设置自身稳定玩家 ID，房主沿用权威控制器已经采用的映射。
func _on_lan_match_started(local_player_id: int, player_count: int) -> void:
	if match_controller.network_gateway.is_lan_client():
		match_controller.local_human_player_id = local_player_id
		# 协议身份绑定：之后即使因回合操控切换到被操控者视角，上行归属与代理授权仍按本绑定值判定。
		match_controller.call("_bind_lan_bound_player_id", local_player_id)
		match_controller.clear_remote_network_state()
		match_log_panel.clear_entries()
		card_use_animation_layer.clear_presentations()
		# 旧绑定的手牌入场补间与前置飞行门闸随表现清场一并丢弃；
		# 飞行补间被清场终止后落地回调不会再触发，若不在此清空门闸，新绑定的获得牌会永远停在手牌区右侧之外。
		_clear_local_hand_gain_animations()
		card_selection_panel.close()
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
	if match_chat_panel != null and is_instance_valid(match_chat_panel):
		# 开局与断线重连共用本入口；聊天正文与网关历史对齐（新局为空、重连保留），气泡一律重置。
		match_chat_panel.set_history(match_controller.network_gateway.get_match_chat_history())
	_dismiss_all_chat_bubbles()
	# 从权威大厅快照同步模式与人数；客户端局内设置与斗地主人数限制才能与房主一致。
	var lobby_snapshot: Dictionary = match_controller.network_gateway.get_lan_lobby_snapshot()
	var game_mode_id: String = str(lobby_snapshot.get("game_mode_id", NetworkGateway.DEFAULT_LOBBY_GAME_MODE_ID))
	# 写入设置与菜单的人数；过关斩将广播值为规则角色总数，落到设置层时换算回“玩家数”（每2个角色对应1名玩家）。
	var settings_player_count: int = int(floorf(float(player_count) / 2.0)) if game_mode_id == GameSettings.MATCH_MODE_CONQUEST else player_count
	if GameSettings != null:
		GameSettings.set_next_match_mode(game_mode_id)
		GameSettings.set_next_match_player_count(settings_player_count)
	match_controller.default_player_count = player_count
	match_menu.set_next_player_count(settings_player_count)
	_refresh_match_menu_authority_controls()
	main_menu.set_next_player_count(settings_player_count)
	lan_lobby_panel.confirm_match_started()
	online_lobby_panel.confirm_match_started()
	main_menu.confirm_game_started()


## 处理意外局域网会话结束；局域网不迁移房主，清空远端表现并以具体原因恢复联机入口。
func _on_lan_session_closed(message: String) -> void:
	_hide_game_settlement_panel_for_main_menu()
	match_controller.clear_remote_network_state()
	_refresh_match_menu_authority_controls()
	if match_controller.state != null:
		match_controller.abandon_match()
	card_selection_panel.close()
	_inline_card_choice.clear()
	_inline_selected_card_uids.clear()
	_modal_choice_request_id = -1
	_modal_card_choice_request.clear()
	main_menu.show_lan_session_error(message)


## 展示局域网断线自动重连进度；重连期间保留当前对局界面并常显顶部横幅，成功或失败的收尾文案复用同一横幅。
## 重连失败的完整清理仍由 lan_session_closed 回调统一执行，本回调不修改任何对局或网络状态。
func _on_lan_reconnect_state_changed(reconnecting: bool, message: String) -> void:
	if information_box == null or not is_instance_valid(information_box):
		return
	# 本条横幅停留时长；重连期间使用常显时长保持提示不消失，重连结束回退默认时长自动淡出。
	var hold_seconds: float = RECONNECT_NOTICE_HOLD_SECONDS if reconnecting else -1.0
	information_box.show_notice(message, hold_seconds)


## 创建牌桌唯一的统一信息框组件；组件只消费视图请求，不直接访问控制器、网络模式或规则状态。
func _create_information_box() -> void:
	information_box = INFORMATION_BOX_LAYER_SCENE.instantiate() as InformationBoxLayer
	information_box.name = "InformationBoxLayer"
	information_box.z_index = 100
	add_child(information_box)
	information_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	information_box.character_details_visibility_changed.connect(_on_character_details_visibility_changed)


## 把任意视图的统一信息请求交给牌桌唯一信息框；来源实例 ID 防止旧离开信号关闭新内容。
func _on_information_requested(information: Dictionary, anchor_rect: Rect2, source: Node) -> void:
	if information_box == null or source == null or not is_instance_valid(source):
		return
	information_box.show_hover_information(information, anchor_rect, source.get_instance_id())


## 关闭指定视图拥有的目标旁信息；来源不匹配时信息框会保持当前新目标内容。
func _on_information_dismissed(source: Node) -> void:
	if information_box == null or source == null:
		return
	information_box.hide_hover_information(source.get_instance_id())


## 打开武将详情；详情组件负责牌面与技能渲染，牌桌只提供公开快照和静态定义。
func _on_character_details_requested(snapshot: Dictionary, character_definition: Dictionary, faction_definition: Dictionary) -> void:
	if information_box == null:
		return
	information_box.show_character_details(_build_character_details_snapshot(snapshot), character_definition, faction_definition)


## 为武将详情补充当前模式展示语义；角色公开快照本身保持纯规则数据，不由牌面组件硬编码模式ID。
func _build_character_details_snapshot(snapshot: Dictionary) -> Dictionary:
	# 详情专用快照；复制后追加是否显示机缘分组，避免改写桌面共享的观察者快照。
	var details_snapshot: Dictionary = _build_player_display_snapshot(snapshot)
	# 当前观察者模式；远程客户端可能没有权威GameState，因此优先从桌面最新根快照和控制器导出模式列表判断。
	var snapshot_mode: String = str(_snapshot.get("match_mode", ""))
	var opportunity_mode_enabled: bool = match_controller != null and (match_controller.is_opportunity_enabled_for_current_match() or match_controller.opportunity_enabled_mode_ids.has(snapshot_mode))
	details_snapshot["opportunity_mode_enabled"] = opportunity_mode_enabled
	return details_snapshot


## 为玩家公开快照补充仅供界面读取的受限技能次数文案；不修改权威获得技能记录或规则状态。
func _build_player_display_snapshot(player_snapshot: Dictionary) -> Dictionary:
	# 显示专用玩家副本；其他玩家武将牌、悬停资料与右键详情共同使用，避免各自计算次数造成显示不一致。
	var display_snapshot: Dictionary = player_snapshot.duplicate()
	# 当前局内获得技能记录；没有局内技能时不写入额外展示字段，固有与临时技能保持原有资料格式。
	var acquired_skills: Dictionary = player_snapshot.get("acquired_skills", {}) as Dictionary
	# 受限技能完整次数文案；键为技能ID，值为“还可发动”等完整句式。
	var remaining_uses_by_skill: Dictionary = {}
	for skill_id_variant: Variant in acquired_skills.keys():
		# 当前局内获得技能ID；只为确实存在限制维度的记录写入展示数据。
		var skill_id: String = str(skill_id_variant)
		# 当前技能剩余次数；统一复用本地技能栏的回合、轮次和总次数计算，不让展示层自行扣减。
		var remaining_uses: Dictionary = _get_acquired_skill_remaining_uses(player_snapshot, skill_id)
		# 当前技能完整说明；空字符串表示未设置任一限制，悬停与详情不附加括号。
		var remaining_uses_description: String = str(remaining_uses.get("description", ""))
		if not remaining_uses_description.is_empty():
			remaining_uses_by_skill[skill_id] = remaining_uses_description
	if not remaining_uses_by_skill.is_empty():
		display_snapshot["acquired_skill_remaining_uses"] = remaining_uses_by_skill
	return display_snapshot


## 使用最新公开状态原位刷新已打开的武将详情；局域网对局继续运行时获得技能与机缘会立即显示。
func _refresh_open_character_details() -> void:
	if information_box == null or not information_box.is_character_details_visible():
		return
	# 当前详情玩家ID；详情组件只允许同一稳定角色原位刷新，不在状态广播中自动切换查看目标。
	var details_player_id: int = information_box.get_character_details_player_id()
	# 最新公开玩家快照；角色离场或死亡仍保留公开资料，只有快照缺失时跳过本次刷新。
	var player_snapshot: Dictionary = _player_snapshots_by_id.get(details_player_id, {}) as Dictionary
	if player_snapshot.is_empty():
		return
	# 最新武将与势力静态定义；名称模式和UI风格仍由信息框统一解析与重绘。
	var character_definition: Dictionary = _get_cached_character_definition(str(player_snapshot.get("character_id", "")))
	var faction_definition: Dictionary = _get_cached_faction_definition(str(character_definition.get("faction", "")))
	information_box.refresh_character_details(_build_character_details_snapshot(player_snapshot), character_definition, faction_definition)


## 根据武将详情可见状态管理独立离线暂停令牌；LAN 与远程对局始终继续运行。
func _on_character_details_visibility_changed(visible: bool) -> void:
	if not visible:
		if _owns_character_details_pause:
			match_controller.release_gameplay_pause(_character_details_pause_token)
			_owns_character_details_pause = false
			_character_details_pause_token = -1
		return
	# 当前是否为离线单机模式；联网客户端不能通过本地详情框暂停权威对局。
	var is_offline_match: bool = match_controller != null and match_controller.network_gateway != null and match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE
	if is_offline_match and not _owns_character_details_pause:
		_character_details_pause_token = match_controller.acquire_gameplay_pause("offline_character_details")
		_owns_character_details_pause = _character_details_pause_token >= 0


## 从运行时座位容器创建本地牌；武将牌与座次标签保持独立节点，本地与对手使用同一组合结构。
func _create_local_player_card() -> void:
	# 本地座位容器实例；进入游戏后才创建，负责让独立座次标签始终位于武将牌正下方。
	local_player_seat_slot = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
	local_player_seat_slot.name = "LocalPlayerSeatSlot"
	# 本地武将牌实例；由座位容器中的可编辑场景提供，不包含座次标签节点。
	local_player_card = local_player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
	# 本地座次标签实例；只属于游戏内座位容器，文本会在收到玩家快照后写入。
	local_player_seat_label = local_player_seat_slot.get_node("Seat") as Label
	# 主视角座次已经由玩家自身位置明确表达；隐藏标签并清空文本，其他玩家座位仍继续显示公开中文座次号。
	local_player_seat_label.visible = false
	local_player_seat_label.text = ""
	local_player_card.visible = true
	local_player_card.set_public_equipment_visible(false)
	local_player_card.set_public_judgment_visible(false)
	local_player_card.set_public_markers_visible(false)
	local_player_seat_slot.z_index = 12
	local_player_seat_slot.anchor_left = 1.0
	local_player_seat_slot.anchor_top = 1.0
	local_player_seat_slot.anchor_right = 1.0
	local_player_seat_slot.anchor_bottom = 1.0
	# 本地完整座位尺寸；直接读取组合场景的原生尺寸，桌面不改写武将牌或座次标签几何信息。
	# 主视角不再保留26像素座次区域，容器尺寸只覆盖148.35×197.8像素武将牌本身。
	var local_seat_size: Vector2 = local_player_card.card_size
	local_player_seat_slot.custom_minimum_size = local_seat_size
	local_player_seat_slot.size = local_seat_size
	local_player_seat_slot.offset_left = -16.0 - local_seat_size.x
	local_player_seat_slot.offset_top = -local_player_card_bottom_margin - local_seat_size.y
	local_player_seat_slot.offset_right = -16.0
	local_player_seat_slot.offset_bottom = -local_player_card_bottom_margin
	local_player_seat_slot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	local_player_seat_slot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(local_player_seat_slot)


## 创建本地玩家专用的延时锦囊标记区；该组件与手牌区同级，避免延时锦囊图标压在右下武将牌底部。
func _create_local_judgment_zone() -> void:
	# 本地判定区实例；沿用其他玩家武将牌上的同一标记组件，保证图标形状、配色与名称缩写一致。
	local_judgment_zone = JudgmentZoneView.new()
	local_judgment_zone.name = "LocalJudgmentZone"
	# 本地判定区绘制层级；高于普通手牌但低于选择弹窗与菜单，图标不会被手牌插画或阵亡滤镜遮挡。
	local_judgment_zone.z_index = 6
	# 本地判定区固定高度；宽度在手牌区域发生响应式变化后由统一布局函数同步。
	local_judgment_zone.size = Vector2(1.0, LOCAL_JUDGMENT_ZONE_HEIGHT)
	add_child(local_judgment_zone)
	_queue_local_judgment_zone_layout()


## 创建第一视角公开标记横排；组件位于手牌区上方左侧，不随右下武将牌移动。
func _create_local_player_markers() -> void:
	local_player_markers = PlayerMarkersView.new()
	local_player_markers.name = "LocalPlayerMarkers"
	local_player_markers.z_index = 7
	add_child(local_player_markers)
	local_player_markers.information_requested.connect(_on_information_requested.bind(local_player_markers))
	local_player_markers.information_dismissed.connect(_on_information_dismissed.bind(local_player_markers))
	_queue_local_judgment_zone_layout()


## 创建独立机缘选择弹窗并绑定统一玩家动作入口；组件不直接读取或修改GameState。
func _create_opportunity_choice_panel() -> void:
	opportunity_choice_panel = OPPORTUNITY_CHOICE_PANEL_SCENE.instantiate() as OpportunityChoicePanel
	opportunity_choice_panel.name = "OpportunityChoicePanel"
	add_child(opportunity_choice_panel)
	opportunity_choice_panel.opportunity_selected.connect(_on_opportunity_selected)
	opportunity_choice_panel.information_requested.connect(_on_information_requested.bind(opportunity_choice_panel))
	opportunity_choice_panel.information_dismissed.connect(_on_information_dismissed.bind(opportunity_choice_panel))


## 创建游戏终局结算面板并绑定关闭事件；组件只消费快照，牌桌保留自动展示与再次打开策略。
func _create_game_settlement_panel() -> void:
	game_settlement_panel = GAME_SETTLEMENT_PANEL_SCENE.instantiate() as GameSettlementPanel
	game_settlement_panel.name = "GameSettlementPanel"
	add_child(game_settlement_panel)
	game_settlement_panel.close_requested.connect(_on_game_settlement_close_requested)
	game_settlement_panel.save_replay_requested.connect(_on_save_replay_requested)


## 创建局内聊天窗口；窗口默认隐藏，由局内菜单“聊天”按钮切换，消息发送统一交给通信网关。
func _create_match_chat_panel() -> void:
	match_chat_panel = MatchChatPanel.new()
	match_chat_panel.name = "MatchChatPanel"
	add_child(match_chat_panel)
	match_chat_panel.chat_submitted.connect(_on_match_chat_submitted)
	match_chat_panel.close_requested.connect(_on_match_chat_close_requested)


## 创建阿哈时刻过场动画组件并订阅控制器的演出开始信号。
## 组件只做本地表现：牌桌不读取它的任何状态，播放失败也不会影响阿哈时刻的规则结算。
func _create_ahha_moment_cutscene() -> void:
	ahha_moment_cutscene = AHHA_MOMENT_CUTSCENE_SCENE.instantiate() as AhhaMomentCutscene
	ahha_moment_cutscene.name = "AhhaMomentCutscene"
	add_child(ahha_moment_cutscene)
	# 暂停服务由桌面注入；只有组件自身的“播放期间暂停对局”开关开启时才会申请令牌。
	ahha_moment_cutscene.set_pause_service(match_controller.gameplay_pause_service)
	# 两个只读探针同样由桌面提供：组件据此判断“能不能停”，但不读取网络模式或牌桌请求列表。
	# 必须用探针而不是布尔快照：联机模式在组件创建之后才建立，牌桌的待办请求也会随快照实时变化。
	ahha_moment_cutscene.set_network_client_probe(Callable(self, "_is_local_network_client"))
	ahha_moment_cutscene.set_pending_choice_probe(Callable(self, "_has_local_pending_choice_request"))
	# 终局与联机会话关闭兜底：这两种收场都不会再走组件的播放出口，必须由桌面显式结束过场，
	# 否则过场持有的暂停令牌会残留到主菜单，整局界面保持冻结。
	match_controller.match_finished.connect(_on_match_finished_for_ahha_cutscene)
	match_controller.network_gateway.lan_session_closed.connect(_on_lan_session_closed_for_ahha_cutscene)
	match_controller.ahha_moment_started.connect(_on_ahha_moment_started)


## 供过场组件查询「本机当前是否为当局局域网客户端」的只读探针；只读网络模式，不修改任何状态。
func _is_local_network_client() -> bool:
	if match_controller == null or match_controller.network_gateway == null:
		return false
	return match_controller.network_gateway.is_lan_client()


## 供过场组件查询「本机当前是否存在待办选择请求」的只读探针；判定素材与询问渲染使用同一份列表，
## 因此不会出现“界面认为有请求、探针认为没有”的分叉。
func _has_local_pending_choice_request() -> bool:
	# 快照清单：权威端下发的本人待办请求 ID 列表，并行无懈等多条请求也能完整表达。
	if _has_local_pending_choice_request_ids and not _local_pending_choice_request_ids.is_empty():
		return true
	# 本地询问槽位：请求到达与下一次快照之间存在时间差，清单可能尚未刷新，
	# 此时以界面正在显示或已建立的询问为准，保证“正在等待玩家作答”永远能被探针看到。
	return _modal_choice_request_id >= 0 or not _inline_card_choice.is_empty()


## 整局结束时结束过场动画；终局后不再有新的演出，残留的暂停令牌会让终局界面无法操作。
func _on_match_finished_for_ahha_cutscene(_winner: String) -> void:
	if ahha_moment_cutscene != null and is_instance_valid(ahha_moment_cutscene):
		ahha_moment_cutscene.stop_cutscene()


## 联机会话意外关闭时结束过场动画；随后不再有快照与表现事件，过场也永远等不到视频结束。
func _on_lan_session_closed_for_ahha_cutscene(_message: String) -> void:
	if ahha_moment_cutscene != null and is_instance_valid(ahha_moment_cutscene):
		ahha_moment_cutscene.stop_cutscene()


## 阿哈时刻开始：播放过场动画并立即返回，牌桌不等待播放结果。
## performance_count 为本场参演欢愉技数量（当前表现不读取，保留给后续扩展的负载）；
## source 为 AhhaMomentSystem 的公开来源常量，由组件按来源开关决定是否播放。
func _on_ahha_moment_started(_performance_count: int, source: String) -> void:
	if ahha_moment_cutscene == null or not is_instance_valid(ahha_moment_cutscene):
		return
	# 回放重演期间只播放画面、不申请暂停：重演里没有真实规则需要冻结，暂停只会把回放播放器一起卡住。
	ahha_moment_cutscene.play_cutscene(source, not _replay_session_active)


## 同步终局结算面板的自动展示状态；同一局只首次自动展示，用户关闭后不会被重复状态广播打断。
func _sync_game_settlement_panel() -> void:
	if game_settlement_panel == null or not is_instance_valid(game_settlement_panel):
		return
	# 回放重演不弹出结算模态；终局画面停留在牌桌上，由回放覆盖层提示播放完毕。
	if _replay_session_active:
		game_settlement_panel.hide_settlement()
		return
	# 当前快照是否为整局终局；本地角色阵亡但整局继续时不创建结算面板。
	var is_game_over: bool = bool(_snapshot.get("game_over", false))
	if not is_game_over:
		_settlement_auto_shown_match_id = ""
		game_settlement_panel.hide_settlement()
		return
	# 当前对局稳定ID；测试快照允许为空字符串，仍可用同一空ID防止同局重复弹出。
	var match_id: String = str(_snapshot.get("match_id", ""))
	if _settlement_auto_shown_match_id == match_id:
		return
	_settlement_auto_shown_match_id = match_id
	# 终局效果音；胜负取决于本机玩家视角，因此不能走核心层广播链路，否则全部客户端会播出同一种结果。
	_play_match_result_effect()
	game_settlement_panel.show_settlement(_snapshot)


## 播放本机终局效果音；音频服务缺失或该视角没有投放素材时静默跳过，不影响结算面板展示。
func _play_match_result_effect() -> void:
	var audio_service: Node = get_node_or_null(AUDIO_SERVICE_PATH)
	if audio_service == null:
		return
	audio_service.play_effect(_resolve_match_result_effect_id())


## 响应结算面板关闭；自动展示标记刻意不清空，确保用户关闭后的同局快照不会立即重新打开。
func _on_game_settlement_close_requested() -> void:
	pass


## 在主菜单重新取得输入前关闭结算模态并清空本局自动展示标记；正常退出、局域网会话结束和菜单可见性变化都复用此边界，避免高层遮罩残留在主菜单之上。
func _hide_game_settlement_panel_for_main_menu() -> void:
	if game_settlement_panel != null and is_instance_valid(game_settlement_panel):
		game_settlement_panel.hide_settlement()
	_settlement_auto_shown_match_id = ""


## 从终局操作区再次打开结算界面；仅整局结束时允许，避免本地阵亡但对局继续时看到未完成统计。
func _on_settlement_button_pressed() -> void:
	if game_settlement_panel == null or not is_instance_valid(game_settlement_panel) or not bool(_snapshot.get("game_over", false)):
		return
	game_settlement_panel.show_settlement(_snapshot)


## 把本机收到的观察者快照送入回放录制器；快照属于新对局时自动开始新一份录制并丢弃未保存旧录制。
## 回放重演期间不录制：重演快照来自既有回放文件，再次录制只会产生毫无意义的嵌套回放。
func _record_replay_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or _replay_session_active:
		return
	# 快照所属对局稳定 ID；与录制器当前对局不一致说明新一局开始，重建录制上下文。
	var match_id: String = str(snapshot.get("match_id", ""))
	if not _match_replay_recorder.is_recording() or _match_replay_recorder.get_current_match_id() != match_id:
		_match_replay_recorder.begin_recording(match_id, match_controller.local_human_player_id)
	_match_replay_recorder.record_snapshot(snapshot)


## 把一步桌面表现送入回放录制器；表现字典为纯数据（稳定玩家 ID、名称、牌面快照），不携带坐标或节点引用。
## 回放重演期间不录制，与快照入口的旁路规则一致；录制器未激活时该调用为空操作。
func _record_replay_presentation(presentation: Dictionary) -> void:
	if _replay_session_active:
		return
	_match_replay_recorder.record_presentation(presentation)


## 响应结算面板命名弹窗确认的“保存回放”；custom_name 为空时按默认名落盘，并通过顶部横幅提示结果。
func _on_save_replay_requested(custom_name: String) -> void:
	# 保存前已存在的文件名；用于区分“新保存成功”与“重复点击复用既有文件”两种提示。
	var previously_saved_file_name: String = _match_replay_recorder.get_saved_file_name()
	# 本次保存结果文件名；失败时为空字符串。
	var saved_file_name: String = _match_replay_recorder.save_recording(MatchReplayStore.REPLAY_DIRECTORY, custom_name)
	if information_box == null or not is_instance_valid(information_box):
		return
	if saved_file_name.is_empty():
		information_box.show_notice("回放保存失败，未生成回放文件。")
	elif not previously_saved_file_name.is_empty():
		information_box.show_notice("本局回放此前已保存为 %s。" % saved_file_name)
	else:
		information_box.show_notice("回放已保存为 %s，可在主菜单“对局回放”中查看。" % saved_file_name)


## 响应主菜单“对局回放”页的播放意图；载入回放并像进入一场新对局一样在正式牌桌上重演。
## 重演使用录制端的第一视角快照流，玩家不可操作，只能通过覆盖层加速或退出。
func _on_replay_playback_requested(replay_file_name: String) -> void:
	if _replay_session_active:
		return
	if match_controller.network_gateway.mode != NetworkGateway.Mode.OFFLINE:
		main_menu.show_replay_playback_error("局域网会话中不能播放回放，请先离开房间。")
		return
	# 实际读取目录；测试覆盖优先，正式运行使用存储层默认目录。
	var replay_directory: String = replay_playback_directory_override if not replay_playback_directory_override.is_empty() else MatchReplayStore.REPLAY_DIRECTORY
	# 回放完整路径；回放头与步骤流分别读取，任一失败都保持主菜单并提示原因。
	var replay_path: String = "%s/%s" % [replay_directory, replay_file_name]
	# 回放头元数据；提供录制端视角玩家 ID 与玩家表。
	var replay_header: Dictionary = MatchReplayStore.read_replay_header(replay_path)
	# 回放全部步骤；重演期间常驻驱动器内存，退出时释放。
	var replay_steps: Array[Dictionary] = MatchReplayStore.read_replay_steps(replay_path)
	if replay_header.is_empty() or replay_steps.is_empty():
		main_menu.show_replay_playback_error("回放载入失败：文件缺失或已损坏。")
		return
	# 残留的上一局权威状态；重演不依赖任何规则运行时，播放前统一放弃并丢弃未保存录制。
	if match_controller.state != null:
		match_controller.abandon_match()
	_match_replay_recorder.discard_recording()
	_reset_presentation_for_new_match()
	_replay_previous_local_player_id = match_controller.local_human_player_id
	# 重演第一视角玩家 ID；使用录制端视角，异常缺失时回退回放头玩家表首名保证座位可建立。
	var viewer_player_id: int = int(replay_header.get("viewer_player_id", -1))
	if viewer_player_id < 0:
		# 回放头玩家表；录制器保存时至少包含一名玩家，防御空表回退0。
		var header_players: Array = replay_header.get("players", []) as Array
		viewer_player_id = int((header_players[0] as Dictionary).get("player_id", 0)) if not header_players.is_empty() else 0
	match_controller.local_human_player_id = viewer_player_id
	_replay_session_active = true
	_ensure_replay_playback_components()
	_match_replay_overlay.open_overlay(replay_file_name.get_basename())
	_match_replay_playback_driver.set_speed_multiplier(1.0)
	main_menu.confirm_game_started()
	_sync_match_menu_visibility()
	_match_replay_playback_driver.start_playback(replay_steps)


## 惰性创建回放重演驱动器与覆盖层；两个组件全程复用，覆盖层保持在组件树末尾以拦截全部桌面输入。
func _ensure_replay_playback_components() -> void:
	if _match_replay_playback_driver == null or not is_instance_valid(_match_replay_playback_driver):
		_match_replay_playback_driver = MatchReplayPlaybackDriver.new()
		_match_replay_playback_driver.name = "MatchReplayPlaybackDriver"
		# 重演纯属表现流程；任何暂停状态（日志展开、详情框）都不应冻结回放推进。
		_match_replay_playback_driver.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_match_replay_playback_driver)
		_match_replay_playback_driver.snapshot_step_ready.connect(_on_replay_snapshot_step)
		_match_replay_playback_driver.log_step_ready.connect(_on_replay_log_step)
		_match_replay_playback_driver.presentation_step_ready.connect(_on_replay_presentation_step)
		_match_replay_playback_driver.playback_finished.connect(_on_replay_playback_finished)
	if _match_replay_overlay == null or not is_instance_valid(_match_replay_overlay):
		_match_replay_overlay = MatchReplayOverlay.new()
		_match_replay_overlay.name = "MatchReplayOverlay"
		add_child(_match_replay_overlay)
		_match_replay_overlay.speed_selected.connect(_on_replay_speed_selected)
		_match_replay_overlay.exit_requested.connect(_on_replay_exit_requested)


## 重演快照步骤入口；复用唯一状态刷新入口，使回放呈现与录制端当时所见完全一致。
func _on_replay_snapshot_step(snapshot: Dictionary) -> void:
	_on_state_changed(snapshot)


## 重演日志步骤入口；复用唯一日志入口，“记录”面板正文随重演逐条恢复。
func _on_replay_log_step(message: String) -> void:
	_on_log_added(message)


## 重演表现步骤入口；把录制的表现数据送回与正式对局完全相同的表现处理器，直接复刻原表现流程：
## 技能/防具发动提示与目标线、卡牌进入牌桌中心的使用/展示/判定飞牌、移牌与摸牌批次动画逐步重放。
## 坐标不来自录制：各处理器按当前重演布局用稳定玩家 ID 重新解析锚点，与录制端解析规则完全一致。
func _on_replay_presentation_step(presentation: Dictionary) -> void:
	# 表现步骤类型；每种类型对应一个正式表现信号入口，未知类型静默跳过保证向前兼容。
	var presentation_kind: String = str(presentation.get("e", ""))
	if presentation_kind == "activation":
		_show_character_card_activation(int(presentation.get("player_id", -1)), str(presentation.get("name", "")), {"target_ids":presentation.get("target_ids", [])})
	elif presentation_kind == "card_presentation":
		_on_card_presentation_requested(presentation.get("data", {}) as Dictionary)
	elif presentation_kind == "card_transfer":
		_on_card_transfer_requested(presentation.get("card_data", {}) as Dictionary, int(presentation.get("source_player_id", -1)), str(presentation.get("source_zone", "")), int(presentation.get("target_player_id", -1)), str(presentation.get("target_zone", "")))
	elif presentation_kind == "draw_batch_started":
		_on_draw_presentation_batch_started(int(presentation.get("batch_id", -1)), int(presentation.get("player_id", -1)))
	elif presentation_kind == "draw_batch_finished":
		_on_draw_presentation_batch_finished(int(presentation.get("batch_id", -1)), int(presentation.get("player_id", -1)))
	elif presentation_kind == "ownership_reset":
		_on_card_animation_ownership_reset_requested(int(presentation.get("card_uid", -1)))


## 回放全部步骤播放完毕；覆盖层标记完成，终局画面停留在牌桌上等待玩家退出。
func _on_replay_playback_finished() -> void:
	if _match_replay_overlay != null and is_instance_valid(_match_replay_overlay):
		_match_replay_overlay.mark_finished()


## 覆盖层速度选择回调；把倍率转交驱动器，重演只允许加速。
func _on_replay_speed_selected(speed_multiplier: float) -> void:
	if _match_replay_playback_driver != null and is_instance_valid(_match_replay_playback_driver):
		_match_replay_playback_driver.set_speed_multiplier(speed_multiplier)


## 覆盖层退出回放回调；结束重演会话并返回主菜单“对局回放”页。
func _on_replay_exit_requested() -> void:
	_end_replay_session()


## 结束回放重演会话；停止驱动器、收起覆盖层、恢复重演前视角并返回主菜单回放列表。
## 重演画面与普通对局一样保留在主菜单下方，不再获得输入或状态更新。
func _end_replay_session() -> void:
	if not _replay_session_active:
		return
	_replay_session_active = false
	if _match_replay_playback_driver != null and is_instance_valid(_match_replay_playback_driver):
		_match_replay_playback_driver.stop_playback()
	if _match_replay_overlay != null and is_instance_valid(_match_replay_overlay):
		_match_replay_overlay.close_overlay()
	match_controller.local_human_player_id = _replay_previous_local_player_id
	if _match_clock_timer != null:
		_match_clock_timer.stop()
	_hide_game_settlement_panel_for_main_menu()
	main_menu.show_match_replay_page()


## 响应局内菜单“聊天”按钮；窗口开着就收起，收起状态则携带完整历史展开。
func _on_match_chat_toggle_requested() -> void:
	if match_chat_panel == null or not is_instance_valid(match_chat_panel):
		return
	if match_chat_panel.is_open():
		match_chat_panel.close_panel()
	else:
		match_chat_panel.open_panel(match_controller.network_gateway.get_match_chat_history())


## 响应聊天窗口关闭按钮；窗口已自行隐藏，牌桌无需额外处理，历史保留在网关中。
func _on_match_chat_close_requested() -> void:
	pass


## 把聊天窗口提交的正文交给通信网关；离线模式附带本机第一视角玩家 ID 与显示名用于署名。
func _on_match_chat_submitted(message: String) -> void:
	match_controller.network_gateway.send_match_chat_message(message, match_controller.local_human_player_id, _get_local_player_display_name())


## 处理网关到达的对局内聊天条目；同步聊天窗口正文并在发言者头顶显示聊天气泡。
func _on_match_chat_received(chat_entry: Dictionary) -> void:
	if match_chat_panel != null and is_instance_valid(match_chat_panel):
		match_chat_panel.append_entry(chat_entry)
	_show_chat_bubble(int(chat_entry.get("sender_player_id", -1)), str(chat_entry.get("message", "")))


## 在发言者武将牌上方显示聊天气泡；按玩家 ID 复用气泡节点，发言者没有可见座位时静默跳过。
func _show_chat_bubble(player_id: int, message: String) -> void:
	if message.is_empty():
		return
	# 发言者武将牌的全局矩形；本地玩家取右下角第一视角武将牌，其他玩家取座位复用节点。
	var anchor_rect: Rect2
	if player_id == match_controller.local_human_player_id and local_player_card != null and is_instance_valid(local_player_card):
		anchor_rect = local_player_card.get_global_rect()
	else:
		# 发言者座位武将牌组件；AI 不发言，找不到座位说明发言者不在当前视图中。
		var player_view: PlayerTargetView = _player_views.get(player_id) as PlayerTargetView
		if player_view == null or not is_instance_valid(player_view):
			return
		anchor_rect = player_view.get_global_rect()
	# 发言者的复用气泡；首条消息时创建并登记，后续消息复用同一节点重启停留计时。
	var bubble: ChatBubbleView = _chat_bubbles.get(player_id) as ChatBubbleView
	if bubble == null or not is_instance_valid(bubble):
		bubble = ChatBubbleView.new()
		bubble.name = "ChatBubble_%d" % player_id
		bubble.z_index = CHAT_BUBBLE_Z_INDEX
		add_child(bubble)
		_chat_bubbles[player_id] = bubble
	# 气泡实际尺寸；由正文换行结果决定，用于头顶水平居中定位。
	var bubble_size: Vector2 = bubble.show_message(message)
	# 全局到牌桌局部坐标的逆变换；与技能发动提示共用同一定位范式。
	var root_inverse_transform: Transform2D = get_global_transform().affine_inverse()
	# 武将牌左上角与右下角的牌桌局部坐标；用于计算头顶居中位置。
	var card_top_left: Vector2 = root_inverse_transform * anchor_rect.position
	var card_bottom_right: Vector2 = root_inverse_transform * anchor_rect.end
	# 气泡横坐标；头顶水平居中并钳制在客户区内，避免边缘座位的气泡被裁切。
	var bubble_x: float = clampf((card_top_left.x + card_bottom_right.x - bubble_size.x) * 0.5, 4.0, maxf(size.x - bubble_size.x - 4.0, 4.0))
	# 气泡纵坐标；位于武将牌上边缘上方固定间距处，顶部座位不足时下沉到客户区顶边。
	var bubble_y: float = maxf(card_top_left.y - bubble_size.y - CHAT_BUBBLE_VERTICAL_GAP, 2.0)
	bubble.position = Vector2(bubble_x, bubble_y)


## 立即隐藏全部头顶聊天气泡；新一局开始与返回主菜单时调用，气泡节点保留供复用。
func _dismiss_all_chat_bubbles() -> void:
	for bubble_variant: Variant in _chat_bubbles.values():
		# 当前玩家气泡；节点可能已随场景清理释放，防御无效实例。
		var bubble: ChatBubbleView = bubble_variant as ChatBubbleView
		if bubble != null and is_instance_valid(bubble):
			bubble.dismiss()


## 解析本机第一视角玩家的公开显示名；离线聊天署名使用，缺失快照时回退通用名称。
func _get_local_player_display_name() -> String:
	# 本机玩家的只读快照；索引在每次状态广播时重建。
	var local_player: Dictionary = _player_snapshots_by_id.get(match_controller.local_human_player_id, {}) as Dictionary
	return str(local_player.get("display_name", "玩家"))


## 使用最新观察者快照刷新机缘弹窗；角色名只取公开显示名，不向等待玩家暴露身份或候选正文。
func _refresh_opportunity_choice_panel() -> void:
	if opportunity_choice_panel == null:
		return
	# 当前机缘交互快照；绝大多数普通状态广播不处于选择或投票公开阶段，应直接关闭弹窗并跳过全体武将名解析。
	var opportunity_snapshot: Dictionary = _snapshot.get("opportunity_state", {}) as Dictionary
	# 当前机缘阶段；只有选择与投票公开需要角色名映射，效果结算阶段不占用模态界面。
	var opportunity_stage: String = str(opportunity_snapshot.get("stage", ""))
	if opportunity_snapshot.is_empty() or opportunity_stage not in ["choosing", "revealing"]:
		opportunity_choice_panel.show_opportunity(opportunity_snapshot, match_controller.local_human_player_id, {})
		return
	# 玩家ID到公开显示名映射；弹窗等待文案使用当前武将名或玩家名，不读取私有身份。
	var player_names: Dictionary = {}
	for player_id_variant: Variant in _player_snapshots_by_id.keys():
		# 当前玩家ID；快照索引键由状态广播时统一转换为整数。
		var player_id: int = int(player_id_variant)
		# 当前公开玩家快照；武将未公开时回退玩家显示名。
		var player_snapshot: Dictionary = _player_snapshots_by_id.get(player_id, {}) as Dictionary
		player_names[player_id] = _snapshot_character_name(player_snapshot, str(player_snapshot.get("display_name", "角色")))
	opportunity_choice_panel.show_opportunity(opportunity_snapshot, match_controller.local_human_player_id, player_names)


## 将机缘卡点击转换为统一玩家动作；局域网客户端沿用MatchController的标准上行路径。
func _on_opportunity_selected(card_id: String) -> void:
	if card_id.is_empty():
		return
	# 机缘选择动作；只携带稳定卡牌ID，品质、正文和效果均由房主权威目录重新读取。
	var action: PlayerAction = PlayerAction.new("choose_opportunity", match_controller.local_human_player_id)
	action.payload = {"card_id":card_id}
	match_controller.submit_action(action)


## 在布局帧结束后重新计算本地延时锦囊标记区的位置；技能栏变化会连带改变手牌右边界，不能读取旧尺寸。
func _queue_local_judgment_zone_layout() -> void:
	call_deferred("_layout_local_judgment_zone")


## 将本地延时锦囊标记区紧贴手牌区上方；不与右下武将牌或手牌悬停抬升共享坐标系。
func _layout_local_judgment_zone() -> void:
	if local_judgment_zone == null or not is_instance_valid(local_judgment_zone) or hand_panel == null or not is_instance_valid(hand_panel):
		return
	# 当前手牌区域全局布局；直接使用根节点局部坐标，二者同为牌桌根节点的子控件，不需要额外变换。
	var hand_position: Vector2 = hand_panel.position
	# 当前手牌区域尺寸；宽度随技能栏列数收紧或扩展，判定标记区必须同步避免越过技能按钮。
	var hand_size: Vector2 = hand_panel.size
	# 本地标记占用尺寸；空标记集合返回0宽，不改变原判定区左移配置。
	var marker_size: Vector2 = local_player_markers.get_required_size() if local_player_markers != null and is_instance_valid(local_player_markers) else Vector2.ZERO
	# 手牌上方判定区带顶边；20像素标记改由手牌栏右上方独立锚定，判定菱形继续使用该带的几何计算。
	var marker_zone_top: float = -LOCAL_PLAYER_MARKER_ZONE_HEIGHT - LOCAL_JUDGMENT_ZONE_HAND_GAP
	if local_player_markers != null and is_instance_valid(local_player_markers):
		# 本地标记固定贴合手牌栏右上方；横排从右向左保留完整宽度，避免压住右侧技能栏。
		local_player_markers.position = hand_position + Vector2(maxf(hand_size.x - marker_size.x, 0.0), -marker_size.y + LOCAL_PLAYER_MARKER_HAND_TOP_OFFSET)
	# 判定区左侧避让距离；第一视角标记已移至手牌右上方，不再占用判定区的横向空间。
	var desired_horizontal_offset: float = local_judgment_zone_left_offset
	var horizontal_offset: float = minf(desired_horizontal_offset, maxf(hand_size.x - 1.0, 0.0))
	# 判定区纵坐标；当前在20像素标记带内居中，二者底部与手牌区保持相同6像素安全间距。
	var judgment_vertical_offset: float = marker_zone_top + (LOCAL_PLAYER_MARKER_ZONE_HEIGHT - LOCAL_JUDGMENT_ZONE_HEIGHT) * 0.5
	local_judgment_zone.position = hand_position + Vector2(horizontal_offset, judgment_vertical_offset)
	local_judgment_zone.size = Vector2(maxf(hand_size.x - horizontal_offset, 1.0), LOCAL_JUDGMENT_ZONE_HEIGHT)


## 接收本地裁剪快照并刷新全部桌面区域。
func _on_state_changed(snapshot: Dictionary) -> void:
	_record_replay_snapshot(snapshot)
	# 本次体力下降玩家 ID；必须在覆盖旧快照前完成对账，渲染新体力后再播放反馈。
	var damaged_player_ids: Array[int] = _update_player_hp_snapshot(snapshot)
	# 控制器每次广播都会新建完整序列化快照，桌面在本次广播后只读保存，避免再次复制整棵玩家与手牌数据。
	_snapshot = snapshot
	# 快照代次递增；必须紧随快照替换，使随后登记的门闸知道“当前快照是否已经包含本次移动”。
	_local_hand_snapshot_generation += 1
	# 新对局检测必须先于武将牌渲染执行；否则复用座次的联机客户端会先把上一局的身份标注与忠反推断重新画到新一局的身份徽记上。
	_sync_identity_marks_match_scope()
	match_menu.set_match_mode(str(_snapshot.get("match_mode", GameSettings.next_match_mode if GameSettings != null else "identity")))
	# 临时退出预约状态同步；权威端在预约、取消或存档生效时都会广播快照，按钮文字始终跟随真实状态。
	match_menu.set_conquest_exit_armed(match_controller.is_conquest_temporary_exit_requested())
	_refresh_match_menu_authority_controls()
	_player_snapshots_by_id.clear()
	for player_variant: Variant in _snapshot.get("players", []) as Array:
		# 当前玩家只读快照；同一广播周期内由全部界面区域共享，不允许局部写入。
		var indexed_player: Dictionary = player_variant as Dictionary
		_player_snapshots_by_id[int(indexed_player.get("player_id", -1))] = indexed_player
	_refresh_open_character_details()
	_refresh_opportunity_choice_panel()
	_sync_game_settlement_panel()
	_refresh_auto_management_controls()
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
	_public_card_choice_display = (_snapshot.get("public_card_choice_display", {}) as Dictionary).duplicate()
	# 选将面板只在真正离开选将阶段时关闭；车轮战抓将阶段双方共享候选池，必须常驻。
	# 若把车轮战阶段一并关闭，每次快照刷新都会清空并重建全部候选牌，界面闪烁且悬停状态被反复重置。
	if str(_snapshot.get("current_phase", "")) not in ["character_selection", "wheel_duel_selection"]:
		character_selection_panel.close()
	# 当前运行时请求；用于清理已经完成或中断的旧内联/窗口状态，同时保留同步创建的新请求。
	var runtime_choice: Dictionary = _snapshot.get("current_choice_request", {}) as Dictionary
	# 当前运行时请求 ID；无活动请求时为-1。
	var runtime_request_id: int = int(runtime_choice.get("request_id", -1))
	# 本人待办请求清单；并行无懈会同时等待多条请求，只有该清单才能完整表达本地窗口是否仍然有效。
	_local_pending_choice_request_ids.clear()
	_has_local_pending_choice_request_ids = _snapshot.has("local_pending_choice_request_ids")
	if _has_local_pending_choice_request_ids:
		for local_request_id_variant: Variant in _snapshot.get("local_pending_choice_request_ids", []) as Array:
			# 当前本人待办请求 ID；无效负数不会参与任何窗口对账。
			var local_request_id: int = int(local_request_id_variant)
			if local_request_id >= 0 and not _local_pending_choice_request_ids.has(local_request_id):
				_local_pending_choice_request_ids.append(local_request_id)
	if not _inline_card_choice.is_empty() and not _is_local_request_still_pending(int(_inline_card_choice.get("request_id", -2)), runtime_request_id):
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
		_active_response_skill_id = ""
	if _modal_choice_request_id >= 0 and not _is_local_request_still_pending(_modal_choice_request_id, runtime_request_id):
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
		_player_damage_taken_count_by_id.clear()
		_hp_snapshot_match_id = match_id
		_has_hp_snapshot = true
	# 本次发生体力下降的玩家 ID；同一快照每名玩家最多记录一次。
	var damaged_player_ids: Array[int] = []
	# 下一份体力基线；只保留当前快照仍存在的玩家，人数减少后不会残留旧座次数据。
	var next_player_hp_by_id: Dictionary = {}
	# 下一份累计受伤次数基线；与体力索引一同按当前玩家集合重建。
	var next_player_damage_taken_count_by_id: Dictionary = {}
	for player_variant: Variant in snapshot.get("players", []) as Array:
		# 当前公开玩家快照；体力属于公开信息，可用于纯表现反馈。
		var player: Dictionary = player_variant as Dictionary
		# 当前稳定玩家 ID；负数异常数据不进入反馈索引。
		var player_id: int = int(player.get("player_id", -1))
		if player_id < 0:
			continue
		# 当前公开体力；允许濒死状态低于0，比较时不进行裁剪。
		var current_hp: int = int(player.get("hp", 0))
		# 当前累计受伤次数；旧快照没有该字段时回退到体力下降检测，保持存档与组件测试兼容。
		var current_damage_taken_count: int = int(player.get("damage_taken_count", _player_damage_taken_count_by_id.get(player_id, 0)))
		# 是否出现新的有效伤害；累计计数优先，体力下降作为旧快照兼容条件。
		var received_new_damage: bool = not is_new_match and _player_damage_taken_count_by_id.has(player_id) and current_damage_taken_count > int(_player_damage_taken_count_by_id.get(player_id, current_damage_taken_count))
		if not received_new_damage and not is_new_match and not player.has("damage_taken_count") and _player_hp_by_id.has(player_id):
			received_new_damage = current_hp < int(_player_hp_by_id.get(player_id, current_hp))
		if received_new_damage:
			damaged_player_ids.append(player_id)
		next_player_hp_by_id[player_id] = current_hp
		next_player_damage_taken_count_by_id[player_id] = current_damage_taken_count
	_player_hp_by_id = next_player_hp_by_id
	_player_damage_taken_count_by_id = next_player_damage_taken_count_by_id
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


## 渲染顶栏轮次、过关斩将关卡与牌堆信息；关卡只额外显示，不替代所有模式通用的轮次。
func _render_header() -> void:
	var match_mode: String = str(_snapshot.get("match_mode", "identity"))
	var conquest_state: Dictionary = _snapshot.get("conquest_state", {}) as Dictionary
	phase_label.text = "第%d轮" % int(_snapshot.get("round_number", 0))
	if conquest_level_label != null:
		conquest_level_label.visible = match_mode == IdentityRules.MODE_CONQUEST
		if conquest_level_label.visible:
			conquest_level_label.text = "第%d关" % int(conquest_state.get("level", 1))
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
	if _match_clock_timer == null:
		return
	if bool(_snapshot.get("game_over", false)):
		_match_clock_timer.stop()
	elif _match_clock_timer.is_stopped():
		_match_clock_timer.start()


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
		# 其他玩家选择按钮；来自座位容器内的可编辑武将牌场景，包含状态摘要、目标高亮与点击入口。
		var player_button: PlayerTargetView = player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
		player_button.set_match_overlays_visible(true)
		if player_seat_slot_was_created:
			player_button.pressed.connect(_on_persistent_target_pressed.bind(player_button))
			player_button.identity_pressed.connect(_on_identity_badge_pressed)
			player_button.details_requested.connect(_on_character_details_requested)
			player_button.information_requested.connect(_on_information_requested.bind(player_button))
			player_button.information_dismissed.connect(_on_information_dismissed.bind(player_button))
			player_button.corner_action_pressed.connect(_on_corner_action_pressed)
		# 其他玩家独立座次标签；仅显示中文座次号，不属于武将牌自身节点树。
		var player_seat_label: Label = player_seat_slot.get_node("Seat") as Label
		# 当前按钮对应的稳定玩家 ID；通过 bind 传入回调。
		# 当前武将定义；角色组件只读取可选插画路径，不持有全局配置引用。
		var character_definition: Dictionary = _get_cached_character_definition(str(player.get("character_id", "")))
		# 当前武将势力展示元数据；独立配置提供牌面简称、完整名称和主题颜色。
		var faction_definition: Dictionary = _get_cached_faction_definition(str(character_definition.get("faction", "")))
		player_button.configure_snapshot(_build_player_display_snapshot(player), character_definition, target_id == int(_snapshot.get("current_player_id", -1)), faction_definition)
		player_button.set_operation_state(target_id == _current_operator_player_id or _simultaneous_operator_player_ids.has(target_id))
		# 当前公开身份；身份已经展示时清理旧本地标注，未知身份继续显示当前客户端的推测结果。
		var public_identity: String = str(player.get("identity", "hidden"))
		if public_identity != "hidden":
			_identity_marks.erase(target_id)
		player_button.set_identity_mark(_resolve_display_identity_mark(target_id))
		player_seat_label.text = _seat_text(int(player.get("seat_number", target_id + 1)))
		if player_seat_slot.get_index() != seat_offset - 1:
			player_grid.move_child(player_seat_slot, seat_offset - 1)
		next_player_views[target_id] = player_button
	_player_views = next_player_views
	_layout_opponent_players()
	# 本地武将定义；统一武将牌从相同静态数据读取名称、插画和势力 ID。
	var local_character_definition: Dictionary = _get_cached_character_definition(str(local_player_snapshot.get("character_id", "")))
	# 本地武将势力展示元数据；与其他玩家使用同一配置入口，避免本地牌面拥有独立硬编码样式。
	var local_faction_definition: Dictionary = _get_cached_faction_definition(str(local_character_definition.get("faction", "")))
	local_player_card.configure_snapshot(_build_player_display_snapshot(local_player_snapshot), local_character_definition, int(local_player_snapshot.get("player_id", -1)) == int(_snapshot.get("current_player_id", -1)), local_faction_definition)
	local_player_card.set_operation_state(int(local_player_snapshot.get("player_id", -1)) == _current_operator_player_id or _simultaneous_operator_player_ids.has(int(local_player_snapshot.get("player_id", -1))))
	local_player_card.set_public_equipment_visible(false)
	local_player_card.set_public_judgment_visible(false)
	local_player_card.set_public_markers_visible(false)
	local_player_card.set_match_overlays_visible(true)
	local_player_seat_label.text = ""
	_render_local_player_markers(local_player_snapshot)
	_render_local_judgment_zone(local_player_snapshot)
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
	# 当前本地身份；本人快照始终可见真实身份，领袖技只在该值为 leader 时进入技能栏。
	var local_identity: String = str(local_player.get("identity", ""))
	# 本地武将定义；技能列表只保存稳定技能 ID。
	var character: Dictionary = _get_cached_character_definition(local_character_id)
	# 当前完整可见技能 ID；包含武将固有技能、模式技能与局内获得的临时技能。
	var skill_ids: Array[String] = _get_visible_skill_ids(character, local_identity, local_player)
	# 当前已经发动的限定技ID；完全读取权威快照，不根据按钮禁用状态或本地历史自行推断。
	var used_limited_skill_ids: Array = local_player.get("used_limited_skill_ids", []) as Array
	# 可见技能列表签名；临时技能增减时即使武将与身份不变也必须重建按钮。
	var skill_list_signature: String = ",".join(skill_ids)
	if _rendered_skill_character_id == local_character_id and _rendered_skill_identity == local_identity and _rendered_skill_list_signature == skill_list_signature:
		for skill_id_variant: Variant in _skill_views.keys():
			# 当前已存在按钮的技能 ID；相同可见技能集合只刷新动态可发动状态，不重建节点。
			var skill_id: String = str(skill_id_variant)
			# 当前技能定义；按钮名称和说明继续来自独立技能文件的元数据。
			var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
			# 当前技能是否拥有正在进行的可取消释放流程；选中按钮允许再次点击放弃本次材料或目标选择。
			var skill_selected: bool = _get_selected_skill_release_id() == skill_id
			# 当前主动技能可用状态；被动技能和样例技能始终不显示为可点击发动。
			var skill_available: bool = bool(skill_definition.get("ui_enabled", false)) and (match_controller.can_activate_skill(match_controller.local_human_player_id, skill_id, _get_local_skill_activation_context()) or skill_selected)
			# 当前受限技能剩余次数；普通固有技能返回空文本，按钮保持原有两字显示。
			var remaining_uses: Dictionary = _get_acquired_skill_remaining_uses(local_player, skill_id)
			# 当前已存在的技能按钮；动态状态刷新复用节点，避免手牌或体力快照变化导致技能栏重建。
			var existing_skill_view: SkillButtonView = _skill_views[skill_id] as SkillButtonView
			# 当前轮回技公开状态；普通技能获得空字典并保持单色说明。
			var reincarnation_state: Dictionary = (local_player.get("reincarnation_skills", {}) as Dictionary).get(skill_id, {}) as Dictionary
			existing_skill_view.configure(skill_definition, skill_available, str(remaining_uses.get("description", "")), reincarnation_state, used_limited_skill_ids.has(skill_id), _resolve_skill_dynamic_description(local_player, skill_id))
			existing_skill_view.set_selected_state(skill_selected)
		_layout_local_skill_area(_skill_views.size())
		return
	_rendered_skill_character_id = local_character_id
	_rendered_skill_identity = local_identity
	_rendered_skill_list_signature = skill_list_signature
	_clear_container(skill_button_container)
	_skill_views.clear()
	skill_status_label.text = ""
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
		# 当前技能是否拥有正在进行的可取消释放流程；初次创建按钮时同步选中描边。
		var skill_selected: bool = _get_selected_skill_release_id() == skill_id
		# 技能是否当前可主动发动；技能文件负责阶段、次数、资源与其他动态条件。
		var skill_available: bool = bool(skill_definition.get("ui_enabled", false)) and (match_controller.can_activate_skill(match_controller.local_human_player_id, skill_id, _get_local_skill_activation_context()) or skill_selected)
		# 当前受限技能剩余次数；快照中的获得技能记录是唯一数据来源，UI不自行扣减次数。
		var remaining_uses: Dictionary = _get_acquired_skill_remaining_uses(local_player, skill_id)
		# 当前技能按钮；组件只展示元数据并发出请求信号。
		var skill_button: SkillButtonView = SkillButtonView.new()
		# 当前轮回技公开状态；技能按钮只转发给统一说明视图，不读取运行时技能对象。
		var reincarnation_state: Dictionary = (local_player.get("reincarnation_skills", {}) as Dictionary).get(skill_id, {}) as Dictionary
		skill_button.configure(skill_definition, skill_available, str(remaining_uses.get("description", "")), reincarnation_state, used_limited_skill_ids.has(skill_id), _resolve_skill_dynamic_description(local_player, skill_id))
		skill_button.set_selected_state(skill_selected)
		skill_button.skill_requested.connect(_on_skill_requested)
		skill_button.information_requested.connect(_on_information_requested.bind(skill_button))
		skill_button.information_dismissed.connect(_on_information_dismissed.bind(skill_button))
		skill_button_container.add_child(skill_button)
		_skill_views[skill_id] = skill_button
	_layout_local_skill_area(skill_ids.size())


## 返回技能在指定玩家公开快照中的动态显示描述；快照的 dynamic_skill_descriptions 是唯一数据来源。
## 该字段只包含“当前进度与静态原文不同”的技能（例如【断界】已被删除的选项需要划掉），
## 因此普通技能返回空字符串，技能按钮据此回退 GameDatabase 的静态原文。
func _resolve_skill_dynamic_description(player_snapshot: Dictionary, skill_id: String) -> String:
	# 快照下发的动态描述覆盖；缺失该可选字段时返回空字符串表示“没有覆盖”。
	var dynamic_descriptions: Dictionary = player_snapshot.get("dynamic_skill_descriptions", {}) as Dictionary
	return str(dynamic_descriptions.get(skill_id, ""))


## 返回局内获得技能在当前快照中的剩余额度；总共、每回合与每轮限制均独立显示，0表示该维度无限制。
func _get_acquired_skill_remaining_uses(player_snapshot: Dictionary, skill_id: String) -> Dictionary:
	# 局内获得技能记录；固有、模式与临时技能不存在该记录，直接返回空显示数据。
	var acquired_skills: Dictionary = player_snapshot.get("acquired_skills", {}) as Dictionary
	# 当前技能限制状态；缺失记录时保持普通技能按钮的原有外观。
	var usage: Dictionary = acquired_skills.get(skill_id, {}) as Dictionary
	if usage.is_empty():
		return {}
	# 当前全局回合编号；只在记录属于当前回合时读取已用次数，跨回合自动视为0。
	var current_turn_number: int = int(_snapshot.get("turn_number", -1))
	# 当前全局轮编号；额外回合不会增加该编号，因此会继续共享本轮额度。
	var current_round_number: int = int(_snapshot.get("round_number", -1))
	# 每回合额度；0表示不限制，非0时显示剩余次数。
	var per_turn_limit: int = maxi(int(usage.get("per_turn_limit", 0)), 0)
	# 每轮额度；0表示不限制，非0时显示剩余次数。
	var per_round_limit: int = maxi(int(usage.get("per_round_limit", 0)), 0)
	# 总共额度；0表示不限制，非0时显示本局累计剩余次数。
	var total_limit: int = maxi(int(usage.get("total_limit", 0)), 0)
	# 当前回合已用次数；旧快照缺失tracked_turn_number时按跨回合处理，保证不会显示负数。
	var uses_this_turn: int = int(usage.get("uses_this_turn", 0)) if int(usage.get("tracked_turn_number", -1)) == current_turn_number else 0
	# 当前轮已用次数；旧快照缺失tracked_round_number时按跨轮处理，保证不会显示负数。
	var uses_this_round: int = int(usage.get("uses_this_round", 0)) if int(usage.get("tracked_round_number", -1)) == current_round_number else 0
	# 本局累计已用次数；总共限制不随回合或轮次重置。
	var total_uses: int = maxi(int(usage.get("total_uses", 0)), 0)
	# 按固定顺序写入按钮缩写；总、回、轮可在62像素按钮第二行稳定并列显示。
	# 当前界面规范取消按钮缩写，以下固定顺序只用于悬停与右键详情的完整文案。
	# 按固定顺序写入悬停完整说明；文本直接说明剩余次数，避免玩家自行推导已用次数。
	var description_parts: Array[String] = []
	if total_limit > 0:
		# 总共剩余次数；达到0时仍显示，提示玩家该获得技能已耗尽。
		var total_remaining: int = maxi(total_limit - total_uses, 0)
		description_parts.append("还可发动%d次" % total_remaining)
	if per_turn_limit > 0:
		# 回合剩余次数；跨回合时uses_this_turn已按0读取。
		var turn_remaining: int = maxi(per_turn_limit - uses_this_turn, 0)
		description_parts.append("每回合可发动%d次" % turn_remaining)
	if per_round_limit > 0:
		# 轮次剩余次数；额外回合仍使用同一轮的已用次数。
		var round_remaining: int = maxi(per_round_limit - uses_this_round, 0)
		description_parts.append("每轮可发动%d次" % round_remaining)
	return {"description":"；".join(description_parts)}


## 返回指定身份实际拥有并可显示的武将技能；领袖技仅 leader 可见，模式技能与局内临时技能追加在固有技能之后。
## 判定依据是快照中的实际安装技能ID：失去技能（如【留白】）会卸载实例，该列表随之收缩，界面无需任何名单即可收敛。
func _get_visible_skill_ids(character: Dictionary, identity: String, player_snapshot: Dictionary = {}) -> Array[String]:
	# 可见技能结果；顺序直接继承武将源码，保证按钮布局与安装顺序一致。
	var result: Array[String] = []
	# 当前实际安装的技能ID；这是“某个技能现在是否还在这名角色身上”的唯一依据。
	# 界面若继续只读武将静态定义，已被卸载的技能会继续占位并出现在悬停与右键详情里。
	# 快照缺少该字段时（旧回放、手动构造的预览快照）不做裁剪，保持与改动前逐字节一致。
	var filter_by_installed: bool = player_snapshot.has("installed_skill_ids")
	var installed_skill_ids: Array = player_snapshot.get("installed_skill_ids", []) as Array
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		# 当前技能 ID 与元数据；缺失定义仍保留占位按钮，便于发现普通技能配置错误。
		var skill_id: String = str(skill_id_variant)
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 缺失定义属于配置错误，必须继续显示以便被发现，因此不参与“已安装”裁剪。
		if filter_by_installed and not skill_definition.is_empty() and not installed_skill_ids.has(skill_id):
			continue
		if bool(skill_definition.get("leader_skill", false)) and identity != "leader":
			continue
		result.append(skill_id)
	# 模式技能；优先读玩家快照注入字段，缺省时按对局模式与身份推算。
	var mode_skill_ids: Array = player_snapshot.get("mode_skill_ids", []) as Array
	if mode_skill_ids.is_empty() and not identity.is_empty():
		var match_mode: String = str(_snapshot.get("match_mode", "identity"))
		mode_skill_ids = IdentityRules.new().get_mode_skill_ids(identity, match_mode)
	for mode_skill_id_variant: Variant in mode_skill_ids:
		var mode_skill_id: String = str(mode_skill_id_variant)
		# 已失去的模式技能同样不显示；否则技能栏会留下一个点不动的空按钮。
		if filter_by_installed and not installed_skill_ids.has(mode_skill_id):
			continue
		if not mode_skill_id.is_empty() and not result.has(mode_skill_id):
			result.append(mode_skill_id)
	# 局内临时技能；例如【铁壁】授予的【琥珀】，必须显示在主视角技能栏。
	# 键顺序保持字典遍历顺序，稳定追加到固有与模式技能之后。
	var temporary_skills: Dictionary = player_snapshot.get("temporary_skills", {}) as Dictionary
	# 临时技能 ID 列表副本；排序保证同帧内不同来源快照不会打乱按钮相对位置。
	var temporary_skill_ids: Array[String] = []
	for temporary_skill_id_variant: Variant in temporary_skills.keys():
		var temporary_skill_id: String = str(temporary_skill_id_variant)
		if temporary_skill_id.is_empty() or result.has(temporary_skill_id):
			continue
		temporary_skill_ids.append(temporary_skill_id)
	temporary_skill_ids.sort()
	for temporary_skill_id: String in temporary_skill_ids:
		result.append(temporary_skill_id)
	# 局内永久获得技能；机缘授予技能在临时技能之后按稳定ID排序显示，死亡前不会因轮数自动移除。
	var acquired_skills: Dictionary = player_snapshot.get("acquired_skills", {}) as Dictionary
	# 已获得技能ID副本；排序避免字典序列化实现差异改变按钮位置。
	var acquired_skill_ids: Array[String] = []
	for acquired_skill_id_variant: Variant in acquired_skills.keys():
		# 当前已获得技能ID；与固有、模式或临时技能重复时只显示一次。
		var acquired_skill_id: String = str(acquired_skill_id_variant)
		if acquired_skill_id.is_empty() or result.has(acquired_skill_id):
			continue
		acquired_skill_ids.append(acquired_skill_id)
	acquired_skill_ids.sort()
	for acquired_skill_id: String in acquired_skill_ids:
		result.append(acquired_skill_id)
	return result


## 按技能数量收紧透明技能区，并让手牌栏右边界延伸到第一或第二个技能按钮旁。
func _layout_local_skill_area(skill_count: int) -> void:
	# 当前有效技能数量；负数配置按0处理，避免生成反向尺寸。
	var safe_skill_count: int = maxi(skill_count, 0)
	if safe_skill_count == 0:
		skill_bar.visible = false
		hand_panel.offset_right = LOCAL_PLAYER_SEAT_LEFT_OFFSET - HAND_SKILL_GAP
		_layout_auto_managed_hand_overlay()
		_queue_local_judgment_zone_layout()
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
	# 技能区底边；动态读取本地武将牌留白，检查器调整牌面高度时仍保持两条底边平行。
	var skill_bottom_offset: float = -local_player_card_bottom_margin + LOCAL_SKILL_BOTTOM_OFFSET
	skill_bar.offset_bottom = skill_bottom_offset
	skill_bar.offset_top = skill_bottom_offset - skill_area_size.y
	# 手牌栏右边界紧贴当前最左技能列；一个技能时自然增长到第一按钮旁，两个及以上缩短到第二按钮旁。
	hand_panel.offset_right = skill_bar.offset_left - HAND_SKILL_GAP
	skill_grid.queue_sort()
	_layout_auto_managed_hand_overlay()
	_queue_local_judgment_zone_layout()


## 延迟到当前控件布局完成后重新计算托管滤镜；窗口缩放和本地座位锚点变化会在同一帧触发，不能读取旧坐标。
func _queue_auto_managed_hand_overlay_layout() -> void:
	call_deferred("_layout_auto_managed_hand_overlay")


## 让托管滤镜从手牌左边界延伸到本地武将牌左侧，并始终把技能栏置于滤镜上方。
func _layout_auto_managed_hand_overlay() -> void:
	if auto_managed_hand_overlay == null or not is_instance_valid(auto_managed_hand_overlay) or hand_panel == null or not is_instance_valid(hand_panel) or local_player_seat_slot == null or not is_instance_valid(local_player_seat_slot):
		return
	# 覆盖层采用主场景局部坐标；手牌和本地座位均为主场景直属节点，因此无需在全局与局部坐标之间转换。
	var overlay_position: Vector2 = hand_panel.position
	# 覆盖层右边界；与本地武将牌之间保留8像素空隙，技能按钮在覆盖层上方继续可见且可操作。
	var overlay_right_edge: float = local_player_seat_slot.position.x - HAND_SKILL_GAP
	# 覆盖层宽度；最小为0以防场景尚未完成首帧锚点布局时生成负尺寸。
	var overlay_width: float = maxf(overlay_right_edge - overlay_position.x, 0.0)
	# 覆盖层层级；五谷公开展示抬高手牌后同步越过手牌，默认仍维持5层。
	var overlay_z_index: int = maxi(hand_panel.z_index + 1, AUTO_MANAGED_HAND_OVERLAY_Z_INDEX)
	auto_managed_hand_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	auto_managed_hand_overlay.position = overlay_position
	auto_managed_hand_overlay.size = Vector2(overlay_width, hand_panel.size.y)
	auto_managed_hand_overlay.z_index = overlay_z_index
	# 技能栏层级；始终高于托管滤镜，点击技能按钮不会被横向延伸的遮罩截获。
	skill_bar.z_index = maxi(overlay_z_index + 1, LOCAL_SKILL_BAR_Z_INDEX)


## 响应技能按钮请求；不可发动技能静默忽略，可主动发动技能通过统一 PlayerAction 进入规则核心。
func _on_skill_requested(skill_id: String) -> void:
	# 响应转化技能已处于选中状态时，第二次点击只退出材料转化模式，不取消整条响应请求。
	if _active_response_skill_id == skill_id:
		_active_response_skill_id = ""
		_inline_selected_card_uids.clear()
		error_label.text = ""
		_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
		_render_local_hand()
		_render_local_skills(_get_player_snapshot(match_controller.local_human_player_id))
		_refresh_selection_text()
		return
	# 主动技能已经创建可取消的内联选择时，第二次点击提交标准取消响应，不消费材料、目标或发动次数。
	if _is_originating_inline_skill_release(skill_id):
		_cancel_originating_inline_skill_release()
		return
	# 被请求的技能定义；用于展示名称、说明和接入状态。
	var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
	# 不可主动发动、条件不满足或锁定技按钮保持静默；说明只由工具提示承担，不写入错误提示区。
	# 当前主动入口上下文；响应阶段包含所需牌型与可发动技能列表，出牌阶段为空字典。
	var activation_context: Dictionary = _get_local_skill_activation_context()
	if not bool(skill_definition.get("ui_enabled", false)) or not match_controller.can_activate_skill(match_controller.local_human_player_id, skill_id, activation_context):
		return
	if _is_inline_response_skill_available(skill_id):
		_active_response_skill_id = skill_id
		_inline_selected_card_uids.clear()
		error_label.text = ""
		_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
		_render_local_hand()
		_render_local_skills(_get_player_snapshot(match_controller.local_human_player_id))
		_refresh_selection_text()
		return
	# 主动技能动作；技能文件自行校验阶段、次数、目标与资源，界面不直接修改任何规则状态。
	var action: PlayerAction = PlayerAction.new("use_skill", match_controller.local_human_player_id)
	# 当前主动入口上下文；响应技能必须把房主下发的牌型与active_entry原样带回，出牌阶段空上下文仍只增加skill_id。
	action.payload = activation_context.duplicate(true)
	action.payload["skill_id"] = skill_id
	match_controller.submit_action(action)


## 返回当前界面正在选择材料或目标的主动技能 ID；空字符串表示没有可由技能按钮再次取消的释放流程。
func _get_selected_skill_release_id() -> String:
	if not _active_response_skill_id.is_empty():
		return _active_response_skill_id
	if _inline_card_choice.is_empty() or not bool(_inline_card_choice.get("allow_cancel", false)):
		return ""
	# 当前技能选择上下文；基类会为主动技能请求写入稳定技能 ID 与持有者 ID。
	var context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
	# 当前技能 ID；只有拥有主动按钮的技能才使用再次点击取消语义，被动触发询问继续使用原取消按钮。
	var skill_id: String = str(context.get("skill_id", ""))
	return skill_id if bool(GameDatabase.get_skill(skill_id).get("ui_enabled", false)) else ""


## 判断指定技能是否正拥有当前可取消内联选择；用于把第二次按钮点击与其他技能的新发动请求区分开。
func _is_originating_inline_skill_release(skill_id: String) -> bool:
	return not skill_id.is_empty() and _get_selected_skill_release_id() == skill_id and _active_response_skill_id.is_empty()


## 取消当前主动技能创建的内联选择；文字选项与牌/目标请求分别沿用既有标准 ChoiceResponse 提交入口。
func _cancel_originating_inline_skill_release() -> void:
	if _inline_card_choice.is_empty() or not bool(_inline_card_choice.get("allow_cancel", false)):
		return
	if _is_inline_control_choice(_inline_card_choice):
		_submit_inline_control_choice("", false)
	else:
		# 空材料数组；confirmed=false 明确表达整次主动技能选择取消，不会被最少选择数量误判为确认。
		var cancelled_card_uids: Array[int] = []
		_submit_inline_card_choice(cancelled_card_uids, false)


## 返回本地技能按钮当前使用的主动入口上下文；响应请求之外保持空字典并沿用普通出牌阶段判断。
func _get_local_skill_activation_context() -> Dictionary:
	if _inline_card_choice.is_empty():
		return {}
	# 内联请求上下文；规则核心已写入active_entry、active_skill_ids与响应牌型。
	var context: Dictionary = (_inline_card_choice.get("context", {}) as Dictionary).duplicate(true)
	return context


## 判断指定技能是否是当前响应请求公开的显式材料转化入口。
func _is_inline_response_skill_available(skill_id: String) -> bool:
	if _inline_card_choice.is_empty() or str(_inline_card_choice.get("choice_type", "")) != "respond":
		return false
	# 响应上下文；候选转化技能由服务端在本次响应请求中显式汇总，不能由客户端自行推断。
	var context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
	# 当前请求声明的转化技能集合；兼容旧请求缺失该字段时继续读取通用主动技能列表。
	var response_conversion_skill_ids: Array = context.get("response_conversion_skill_ids", []) as Array
	var active_skill_ids: Array = context.get("active_skill_ids", []) as Array
	if not response_conversion_skill_ids.has(skill_id) and not active_skill_ids.has(skill_id):
		return false
	for candidate_variant: Variant in _inline_card_choice.get("candidates", []) as Array:
		# 当前响应候选；至少一张材料要求该技能时按钮才承担筛选入口。
		var candidate: Dictionary = candidate_variant as Dictionary
		if str(candidate.get("required_response_skill_id", "")) == skill_id:
			return true
	return false


## 按实体 UID 对账本地玩家手牌，并根据当前名称模式刷新牌面；现有正式节点会持续复用，不因快照刷新整体重建。
func _render_local_hand() -> void:
	# 虚拟手牌替换请求：手牌区整体切换为技能声明的可选虚拟牌，真实手牌先向左离场，请求结束后再摸牌式回归。
	if _refresh_virtual_hand_choice_mode():
		return
	# 当前快照所属对局 ID；新对局必须放弃上一局仅在客户端保存的手牌排列。
	var current_match_id: String = str(_snapshot.get("match_id", ""))
	if current_match_id != _hand_order_match_id:
		_cancel_active_hand_drag()
		_hand_order_match_id = current_match_id
		_local_hand_display_order.clear()
		_local_wooden_ox_display_order.clear()
	# 本地玩家快照；找不到时保持空字典。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	# 是否轮到本地玩家出牌；决定卡牌与四个动作按钮是否可用。
	# 重铸与存木牛兼容节点始终隐藏，因此当前可见操作只由中央确定/取消和右侧回合结束承担。
	var can_act: bool = _can_local_player_act()
	# 当前内联选择候选 UID；存在请求时只有该集合中的本人牌允许点击选中，排序拖拽仍独立对全部正式手牌开放。
	var inline_candidate_uids: Array[int] = _get_inline_candidate_uids()
	# 当前是否正在本地手牌区完成选择请求；该状态与普通出牌选择互斥。
	var has_inline_choice: bool = not _inline_card_choice.is_empty()
	# 当前出牌请求候选 UID；普通出牌阶段只开放至少存在一种合法动作的实体牌。
	var play_candidate_uids: Array[int] = _get_play_phase_candidate_uids()
	# 当前装备技能材料候选；主动模式只开放普通手牌，木牛“粮”不会被当作丈八材料或再次存入木牛。
	var equipment_material_candidate_uids: Array[int] = _get_equipment_action_material_candidate_uids()
	# 当前快照中的木牛“粮”；先按独立本地排序规范化，保证该分区始终固定在普通手牌左侧。
	var ordered_wooden_ox_cards: Array[Dictionary] = _apply_local_hand_display_order(local_player.get("wooden_ox_storage", []) as Array, _local_wooden_ox_display_order)
	# 当前快照中的普通手牌；按独立本地排序规范化，新进入分区的实体会追加到末尾。
	var ordered_hand_cards: Array[Dictionary] = _apply_local_hand_display_order(local_player.get("hand", []) as Array, _local_hand_display_order)
	# 当前快照中的手牌条目；每项同时记录牌面快照与是否来自木牛流马，数组顺序就是正式手牌显示顺序。
	var desired_card_entries: Array[Dictionary] = []
	# 木牛流马“粮”固定先加入显示数组，使其无论何时获得或刷新都保持在手牌区最左侧。
	for card: Dictionary in ordered_wooden_ox_cards:
		# 当前木牛“粮”条目；true 让同一正式牌面显示独立来源标记。
		desired_card_entries.append({"card":card, "wooden_ox_card":true})
	for card: Dictionary in ordered_hand_cards:
		# 当前普通手牌条目；false 表示牌面不显示木牛“粮”来源标记。
		desired_card_entries.append({"card":card, "wooden_ox_card":false})
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
		# 当前旧卡牌视图原始值；映射理论上不残留已释放节点，但一旦残留，
		# 对已释放对象做 CardView 强制转换会直接中止本函数，使整轮手牌对账被静默跳过，
		# 因此这里先按 Variant 校验有效性再转换。
		var existing_view_variant: Variant = _card_views.get(existing_uid)
		if not is_instance_valid(existing_view_variant):
			continue
		# 当前旧卡牌视图；只有仍位于手牌容器的节点才由本方法释放。
		var existing_view: CardView = existing_view_variant as CardView
		if existing_view != null and is_instance_valid(existing_view) and existing_view.get_parent() == hand_container:
			hand_container.remove_child(existing_view)
			existing_view.queue_free()
	# 不在最新快照中的待入场 UID；转移结果已失效或被后续规则移动，禁止在未来快照中错误启动动画。
	for pending_uid_variant: Variant in _pending_local_hand_gain_uids.keys():
		if not desired_uid_lookup.has(int(pending_uid_variant)):
			_pending_local_hand_gain_uids.erase(pending_uid_variant)
	# 不在最新快照中的前置飞行门闸；该牌已经离开手牌区，门闸不会再有落地回调来解除。
	# 但「当前快照没有这张牌」只有在快照确实晚于门闸登记时才等价于「已经离开手牌」：
	# 转移信号先于权威快照到达，而询问界面等入口会在同一帧用旧快照重新对账手牌，
	# 若此时按“不在快照中”直接删门闸，正在等待起飞的获得牌飞行会被整批丢弃，
	# 玩家看到的就是「摸牌跳过动画、牌直接出现在手牌区」（例如持有【风口】时摸牌后的第一段询问）。
	for gated_uid_variant: Variant in _local_hand_gain_flight_gates.keys():
		if desired_uid_lookup.has(int(gated_uid_variant)):
			continue
		# 当前门闸记录；登记之后还没有任何更新的快照到达时保留门闸，继续等待它出现。
		var gated_flight: Dictionary = _local_hand_gain_flight_gates.get(gated_uid_variant, {}) as Dictionary
		if int(gated_flight.get("snapshot_generation", _local_hand_snapshot_generation)) >= _local_hand_snapshot_generation:
			continue
		_local_hand_gain_flight_gates.erase(gated_uid_variant)
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
		var definition: Dictionary = _get_cached_card_definition(str(card.get("definition_id", "")))
		# 当前牌是否来自木牛流马；只改变来源标记，不改变实体 UID 或节点身份。
		var wooden_ox_card: bool = bool(entry.get("wooden_ox_card", false))
		# 当前手牌是否允许交互；响应与普通出牌均以权威请求候选为准，不能只按阶段整体启用。
		var card_interactable: bool = equipment_material_candidate_uids.has(card_uid) if not _active_equipment_action.is_empty() else (inline_candidate_uids.has(card_uid) if has_inline_choice else can_act and play_candidate_uids.has(card_uid))
		# 当前正式手牌视图原始值；被动画层接管的节点会在接管点同步移出映射，
		# 这里仍先校验有效性再转换，避免任何残留的已释放对象中止整轮手牌对账。
		var card_view_variant: Variant = _card_views.get(card_uid)
		if not is_instance_valid(card_view_variant):
			card_view_variant = null
		# 当前正式手牌视图；优先复用同 UID 节点，缺失或不在手牌容器时才创建新节点。
		var card_view: CardView = card_view_variant as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			card_view = _create_local_hand_card_view(card_uid)
		card_view.configure(card, definition, wooden_ox_card, card_interactable)
		# 外观镜像：正式节点每次重配后都要把明暗同步给同一张牌正在进行的飞行牌面；
		# 放在这里是因为飞行可能跨越多次快照，只有每次重配都同步才能保证落地交接时两者完全一致。
		_sync_local_hand_gain_flight_appearance(card_uid, card_view)
		next_card_views[card_uid] = card_view
		ordered_card_views.append(card_view)
	_card_views = next_card_views
	# 当前正式手牌顺序索引；把复用或新建的节点顺序与两个分区各自的本地排列保持一致。
	for card_index: int in range(ordered_card_views.size()):
		if ordered_card_views[card_index].get_index() != card_index:
			hand_container.move_child(ordered_card_views[card_index], card_index)
	hand_container.layout_cards_now()
	# 顺序不可调换：先把仍等待飞行的获得牌按在飞行起点，再让槽位已经可用的获得牌起飞（飞行终点取刚刚写好的槽位）。
	_hold_gated_local_hand_entries()
	_start_pending_local_hand_gain_flights()
	# 虚拟手牌候选与虚拟牌回归仍使用“从右侧滑入”的入场表现，与真实获得牌的直飞最终槽位互不影响。
	_start_pending_local_hand_gain_animations()
	# 内联询问期间的按钮态由询问刷新函数唯一维护；本函数不得回写普通出牌态。
	# 缺少本守卫时，延迟执行的手牌重渲染（例如虚拟候选离场动画结束回调）会覆盖刚刚建立的询问按钮，
	# 表现为“确定点不动、取消也不见”，玩家必须先在装备区点一次取消选中再点一次选中才能继续。
	if _inline_card_choice.is_empty():
		use_button.disabled = true
		%CancelButton.visible = false
		%CancelButton.disabled = false
	recast_button.disabled = not can_act
	end_play_button.disabled = not can_act
	recast_button.visible = false


## 创建一张会长期留在手牌容器中的正式 CardView；节点按实体 UID 绑定一次输入信号，后续快照只更新内容。
func _create_local_hand_card_view(card_uid: int) -> CardView:
	# 新正式手牌节点；它会一直复用到实体牌离开本人手牌或木牛区域。
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	card_view.visible = true
	card_view.pressed.connect(_on_card_pressed.bind(card_uid))
	card_view.hand_reorder_requested.connect(_on_hand_card_reorder_requested)
	card_view.hand_drag_started.connect(_on_hand_drag_started)
	card_view.hand_drag_moved.connect(_on_hand_drag_moved)
	card_view.hand_drag_finished.connect(_on_hand_drag_finished)
	card_view.information_requested.connect(_on_information_requested.bind(card_view))
	card_view.information_dismissed.connect(_on_information_dismissed.bind(card_view))
	hand_container.add_child(card_view)
	return card_view


## 统一维护「虚拟手牌替换」模式状态机；返回 true 表示手牌区已由本模式接管，调用方不得再渲染真实手牌。
##
## 本模式把真实手牌临时换成技能声明的可选虚拟牌：进入时真实手牌向左离场，可选牌以摸牌动画进入；
## 玩家像使用真实手牌一样选中一张并点击目标后确认；请求结束时可选牌向右离场，真实手牌再以摸牌动画回归。
## 虚拟牌只是选择介质，从未真正加入手牌，规则效果仍由技能自行结算。
##
## 三条走向：请求仍是虚拟手牌请求 → 保证虚拟牌显示在手牌区；请求已结束 → 播放离场并交回真实手牌；
## 与虚拟手牌无关 → 返回 false，由调用方按原有逻辑渲染真实手牌。
func _refresh_virtual_hand_choice_mode() -> bool:
	if _is_virtual_hand_request(_inline_card_choice):
		_begin_virtual_hand_entry()
		if _virtual_hand_choice_active:
			# 快照刷新期间技能可能重新枚举候选，因此每次都对账一次虚拟牌集合。
			_render_virtual_hand_choice()
		return true
	if _virtual_hand_choice_active or _virtual_hand_exit_playing:
		return _begin_virtual_hand_exit()
	return false


## 判断一个选择请求是否为虚拟手牌替换请求；稳定标记由技能侧请求端口写入，界面不按标题或候选数量猜测规则。
func _is_virtual_hand_request(choice_data: Dictionary) -> bool:
	if choice_data.is_empty():
		return false
	return bool((choice_data.get("context", {}) as Dictionary).get("virtual_hand", false))


## 提取请求中的虚拟候选；只保留显式带 virtual_hand 标记的条目，避免把混入的真实牌当作虚拟牌渲染。
func _get_virtual_hand_candidates(choice_data: Dictionary) -> Array[Dictionary]:
	# 虚拟候选结果；顺序沿用请求声明顺序，也就是手牌区从左到右的显示顺序。
	var result: Array[Dictionary] = []
	for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
		# 当前候选快照；标记缺失时属于普通实体牌候选，交由原手牌区逻辑处理。
		var candidate: Dictionary = candidate_variant as Dictionary
		if bool(candidate.get("virtual_hand", false)):
			result.append(candidate)
	return result


## 确保虚拟手牌模式已经进入；首次调用时先播放真实手牌向左离场动画，动画结束后再生成虚拟候选。
func _begin_virtual_hand_entry() -> void:
	if _virtual_hand_choice_active or _virtual_hand_entry_playing:
		return
	# 当前仍在手牌容器中显示的真实手牌；它们整体向左离场，让出整个手牌区。
	var exiting_views: Array[CardView] = []
	var exiting_uids: Array[int] = []
	for card_uid_variant: Variant in _card_views.keys():
		# 当前手牌实体 UID 与视图；只有真正停留在手牌容器里的节点参与离场。
		var card_uid: int = int(card_uid_variant)
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			continue
		exiting_views.append(card_view)
		exiting_uids.append(card_uid)
	if exiting_views.is_empty():
		# 手牌区本就为空；直接进入虚拟手牌模式，不播放空的离场动画。
		_virtual_hand_choice_active = true
		return
	_virtual_hand_entry_playing = true
	_play_virtual_hand_entry_sequence(exiting_views, exiting_uids)


## 播放真实手牌向左离场动画，随后把手牌区交给虚拟候选。
##
## 等待使用定时器而不是补间 finished 信号：离场补间可能在重新开局时被强制停止，而定时器仍会恢复执行，
## 因此播放标记一定会被清空，不会把界面卡在“正在离场”的中间状态。
func _play_virtual_hand_entry_sequence(exiting_views: Array[CardView], exiting_uids: Array[int]) -> void:
	# 离场补间；全部真实手牌并行左移并淡出，使“手牌退场”读起来是一次整体动作。
	_local_hand_exit_tween = create_tween()
	_local_hand_exit_tween.set_parallel(true)
	_local_hand_exit_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for card_view: CardView in exiting_views:
		_local_hand_exit_tween.tween_property(card_view, "hand_entry_offset", _get_hand_exit_offset(card_view, true), local_hand_exit_duration)
		_local_hand_exit_tween.tween_property(card_view, "modulate:a", 0.0, local_hand_exit_duration)
	await get_tree().create_timer(local_hand_exit_duration).timeout
	_virtual_hand_entry_playing = false
	# 离场期间可能已经重新开局；逐项校验后只释放仍登记在映射中的旧节点。
	for card_uid: int in exiting_uids:
		_release_local_hand_view(card_uid)
	# 请求可能在离场动画期间结束（例如取消或技能条件失效）；此时不再生成虚拟牌，直接交回真实手牌。
	if not _is_virtual_hand_request(_inline_card_choice):
		_render_local_hand()
		return
	_virtual_hand_choice_active = true
	_render_virtual_hand_choice()


## 结束虚拟手牌模式：先播放虚拟候选向右离场动画，再交回真实手牌。
##
## 返回 true 表示手牌区仍由本模式接管（离场动画进行中，调用方应停止渲染）；返回 false 表示模式已同步清理完毕，
## 调用方可以在同一次调用里继续渲染真实手牌。补间被 kill 时不会发出 finished，因此同步收尾分支必须存在。
func _begin_virtual_hand_exit() -> bool:
	if _virtual_hand_exit_playing:
		return true
	if _virtual_hand_views.is_empty():
		_finish_virtual_hand_choice()
		return false
	_virtual_hand_exit_playing = true
	# 离场补间；虚拟候选整体向右移出并淡出，与入场方向一致，读起来是“收起这次临时选择”。
	_virtual_hand_exit_tween = create_tween()
	_virtual_hand_exit_tween.set_parallel(true)
	_virtual_hand_exit_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for candidate_uid_variant: Variant in _virtual_hand_views.keys():
		# 当前虚拟牌节点；节点可能已被重新开局释放，缺失时跳过。
		var card_view: CardView = _virtual_hand_views.get(candidate_uid_variant) as CardView
		if card_view == null or not is_instance_valid(card_view):
			continue
		_virtual_hand_exit_tween.tween_property(card_view, "hand_entry_offset", _get_hand_exit_offset(card_view, false), local_hand_exit_duration)
		_virtual_hand_exit_tween.tween_property(card_view, "modulate:a", 0.0, local_hand_exit_duration)
	_virtual_hand_exit_tween.finished.connect(_on_virtual_hand_exit_animation_finished)
	return true


## 虚拟候选离场动画结束；释放可选牌并以摸牌动画恢复真实手牌。
func _on_virtual_hand_exit_animation_finished() -> void:
	_virtual_hand_exit_playing = false
	_finish_virtual_hand_choice()
	_render_local_hand()


## 释放全部虚拟候选并把真实手牌标记为待入场；调用后手牌区不再属于虚拟手牌模式。
func _finish_virtual_hand_choice() -> void:
	for candidate_uid_variant: Variant in _virtual_hand_views.keys():
		_release_virtual_hand_view(int(candidate_uid_variant))
	_virtual_hand_views.clear()
	_virtual_hand_choice_active = false
	_virtual_hand_exit_playing = false
	# 真实手牌回归沿用获得牌入场链路：把当前快照中的手牌标记为待入场，
	# 下一步重新对账会重建这些节点并从手牌区右侧像摸牌一样进入，而不是瞬间出现。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	for returning_card_variant: Variant in (local_player.get("hand", []) as Array) + (local_player.get("wooden_ox_storage", []) as Array):
		# 当前回归手牌 UID；无效 UID 不会进入待入场集合。
		var returning_uid: int = int((returning_card_variant as Dictionary).get("uid", -1))
		if returning_uid >= 0:
			_pending_local_hand_gain_uids[returning_uid] = true


## 把手牌区渲染为当前请求声明的虚拟候选；与真实手牌对账同构，但牌面固定隐藏花色与点数。
func _render_virtual_hand_choice() -> void:
	var candidates: Array[Dictionary] = _get_virtual_hand_candidates(_inline_card_choice)
	# 当前请求允许交互的候选 UID；虚拟牌与真实牌共用同一份权威候选集合。
	var inline_candidate_uids: Array[int] = _get_inline_candidate_uids()
	# 本轮对账后的虚拟牌映射；只包含本次请求仍然声明的占位 UID。
	var next_views: Dictionary = {}
	# 当前按请求顺序排列的虚拟牌节点；对账完成后统一调整子节点顺序。
	var ordered_views: Array[CardView] = []
	for candidate: Dictionary in candidates:
		# 当前虚拟候选；牌面固定取自 card_data，占位 UID 是复用节点的唯一身份。
		var candidate_uid: int = int(candidate.get("uid", -1))
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		var definition: Dictionary = _get_cached_card_definition(str(card_data.get("definition_id", "")))
		var card_view: CardView = _virtual_hand_views.get(candidate_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			card_view = _create_virtual_hand_card_view(candidate_uid)
		# 虚拟牌没有花色也没有点数（视为使用的牌本身不带这两项），因此 hide_suit_rank 固定为 true。
		card_view.configure(card_data, definition, false, inline_candidate_uids.has(candidate_uid), true, true)
		card_view.modulate.a = 1.0
		next_views[candidate_uid] = card_view
		ordered_views.append(card_view)
	# 释放已经不在本次请求中的虚拟牌；请求被替换时不会残留上一批可选牌。
	for existing_uid_variant: Variant in _virtual_hand_views.keys():
		var existing_uid: int = int(existing_uid_variant)
		if not next_views.has(existing_uid):
			_release_virtual_hand_view(existing_uid)
	_virtual_hand_views = next_views
	for card_index: int in range(ordered_views.size()):
		if ordered_views[card_index].get_index() != card_index:
			hand_container.move_child(ordered_views[card_index], card_index)
	hand_container.layout_cards_now()
	# 新生成的虚拟牌以摸牌动画进入手牌区；已在场的牌偏移已归零，不会重复播放。
	_start_pending_local_hand_gain_animations()


## 创建一张虚拟候选卡牌视图；虚拟牌只是选择介质，因此不连接手牌拖拽排序信号。
func _create_virtual_hand_card_view(candidate_uid: int) -> CardView:
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	card_view.visible = true
	card_view.pressed.connect(_on_card_pressed.bind(candidate_uid))
	hand_container.add_child(card_view)
	_card_views[candidate_uid] = card_view
	# 新节点需要一次入场动画；沿用获得牌待入场集合，使虚拟牌与真实摸牌的表现完全一致。
	_pending_local_hand_gain_uids[candidate_uid] = true
	return card_view


## 释放一张虚拟候选视图；同时从统一手牌映射中移除，避免占位 UID 在后续对账里被当作真实牌。
func _release_virtual_hand_view(candidate_uid: int) -> void:
	_virtual_hand_views.erase(candidate_uid)
	_release_local_hand_view(candidate_uid)


## 从手牌容器与统一映射中释放一张手牌视图；真实手牌与虚拟牌共用，保证两套节点生命周期完全一致。
func _release_local_hand_view(card_uid: int) -> void:
	# 先停止该 UID 可能仍在运行的入场补间；此时映射仍在，取消逻辑可以安全地归零运行时偏移。
	_cancel_local_hand_gain_animation(card_uid)
	var card_view: CardView = _card_views.get(card_uid) as CardView
	_card_views.erase(card_uid)
	if card_view == null or not is_instance_valid(card_view):
		return
	if card_view.get_parent() == hand_container:
		hand_container.remove_child(card_view)
	card_view.queue_free()


## 返回一张手牌向手牌区左/右外侧离场时使用的运行时偏移量；单位与 hand_entry_offset 一致。
##
## 距离取可视滚动区宽度加一张牌宽：从当前布局位置出发一定移出滚动区裁剪范围；配合同时播放的淡出，
## 即使手牌区已经横向滚动，离场也一定会彻底消失在对应的那一侧。
func _get_hand_exit_offset(card_view: CardView, from_left_side: bool) -> Vector2:
	var exit_distance: float = hand_scroll.size.x + card_view.get_card_size().x + local_hand_exit_margin
	return Vector2(-exit_distance if from_left_side else exit_distance, 0.0)


## 停止仍在播放的两类手牌离场补间；补间被 kill 不会发出 finished，因此调用方必须自行清理模式状态。
func _kill_hand_exit_tweens() -> void:
	if _local_hand_exit_tween != null and _local_hand_exit_tween.is_valid():
		_local_hand_exit_tween.kill()
	_local_hand_exit_tween = null
	if _virtual_hand_exit_tween != null and _virtual_hand_exit_tween.is_valid():
		_virtual_hand_exit_tween.kill()
	_virtual_hand_exit_tween = null


## 丢弃全部虚拟手牌状态；重新开局或换将边界调用，避免旧局的占位 UID 残留在新对局手牌区。
func _clear_virtual_hand_choice() -> void:
	_kill_hand_exit_tweens()
	_virtual_hand_entry_playing = false
	_virtual_hand_exit_playing = false
	_virtual_hand_choice_active = false
	for candidate_uid_variant: Variant in _virtual_hand_views.keys():
		_release_virtual_hand_view(int(candidate_uid_variant))
	_virtual_hand_views.clear()


## 按本地保存的 UID 顺序整理同一手牌分区；离开分区的旧 UID 会移除，新进入的实体按权威快照追加。
func _apply_local_hand_display_order(cards: Array, display_order: Array[int]) -> Array[Dictionary]:
	# 当前实体 UID 到牌面快照的映射；只在本次刷新中读取，不向规则状态写入本地排序。
	var cards_by_uid: Dictionary = {}
	# 当前快照给出的 UID 顺序；用于给没有本地排序记录的新实体提供稳定追加顺序。
	var snapshot_uids: Array[int] = []
	for card_variant: Variant in cards:
		# 当前分区牌面快照；必须复制引用以避免把界面临时状态写入权威快照。
		var card: Dictionary = card_variant as Dictionary
		# 当前实体稳定 UID；同一实体在不同快照中保持不变，是本地排列的唯一键。
		var card_uid: int = int(card.get("uid", -1))
		# 本地排序只复制快照引用并读取 UID，不向牌面字典写入选中、顺序或动画状态，因此无需逐牌深拷贝。
		cards_by_uid[card_uid] = card
		snapshot_uids.append(card_uid)
	# 规范化后的本地 UID 顺序；先保留仍在分区的旧排列，再追加新实体。
	var normalized_order: Array[int] = []
	# 已进入规范化顺序的UID集合；长手牌下使用常数时间去重，避免每次快照反复线性扫描结果数组。
	var normalized_uid_lookup: Dictionary = {}
	for stored_uid: int in display_order:
		if cards_by_uid.has(stored_uid) and not normalized_uid_lookup.has(stored_uid):
			normalized_order.append(stored_uid)
			normalized_uid_lookup[stored_uid] = true
	for snapshot_uid: int in snapshot_uids:
		if not normalized_uid_lookup.has(snapshot_uid):
			normalized_order.append(snapshot_uid)
			normalized_uid_lookup[snapshot_uid] = true
	display_order.clear()
	display_order.append_array(normalized_order)
	# 按规范化 UID 顺序输出的牌面数组；调用方据此重排正式 CardView 子节点。
	var ordered_cards: Array[Dictionary] = []
	for ordered_uid: int in normalized_order:
		ordered_cards.append(cards_by_uid.get(ordered_uid, {}) as Dictionary)
	return ordered_cards


## 返回实体牌当前所属的可排序分区；木牛“粮”和普通手牌永远是两个互不连通的分区。
func _get_local_hand_reorder_zone(card_uid: int) -> String:
	# 本地玩家公开快照；只有仍在本人可见手牌区的实体可以参与排序。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	for card_variant: Variant in local_player.get("wooden_ox_storage", []) as Array:
		# 当前木牛“粮”快照；UID 一致时返回木牛专属分区。
		var wooden_ox_card: Dictionary = card_variant as Dictionary
		if int(wooden_ox_card.get("uid", -1)) == card_uid:
			return "wooden_ox"
	for card_variant: Variant in local_player.get("hand", []) as Array:
		# 当前普通手牌快照；UID 一致时返回普通手牌分区。
		var hand_card: Dictionary = card_variant as Dictionary
		if int(hand_card.get("uid", -1)) == card_uid:
			return "hand"
	return ""


## 在同一分区内移动一个实体 UID；目标牌左半边插入前方，右半边插入后方的判断由 CardInputArea 完成。
func _on_hand_card_reorder_requested(source_card_uid: int, target_card_uid: int, insert_after_target: bool) -> void:
	# 被拖拽牌所属分区；空字符串表示实体已离开本地手牌，拒绝使用过期拖放数据。
	var source_zone: String = _get_local_hand_reorder_zone(source_card_uid)
	# 接收牌所属分区；只有与来源完全一致时才允许调整，禁止跨越木牛与普通手牌边界。
	var target_zone: String = _get_local_hand_reorder_zone(target_card_uid)
	if source_zone.is_empty() or source_zone != target_zone:
		return
	# 当前分区持久化的显示顺序；两个分区使用不同数组，保证木牛始终在最左侧。
	var display_order: Array[int] = _local_wooden_ox_display_order if source_zone == "wooden_ox" else _local_hand_display_order
	# 来源牌在当前分区内的位置；不存在表示界面尚未按当前快照完成首次对账。
	var source_index: int = display_order.find(source_card_uid)
	# 目标牌在当前分区内的位置；不存在时拒绝本次过期拖放，避免错误插入到末尾。
	var target_index: int = display_order.find(target_card_uid)
	if source_index < 0 or target_index < 0 or source_card_uid == target_card_uid:
		return
	display_order.remove_at(source_index)
	# 移除来源后目标牌可能左移一格，因此重新查询最终插入索引。
	target_index = display_order.find(target_card_uid)
	# 最终插入位置；true 放在目标右侧，false 放在目标左侧。
	var insertion_index: int = target_index + (1 if insert_after_target else 0)
	display_order.insert(insertion_index, source_card_uid)
	_render_local_hand()


## 开始直接拖动一张本地实体手牌；只允许当前快照仍存在且位于正式手牌分区的同一节点进入鼠标跟随状态。
func _on_hand_drag_started(source_card_uid: int, pointer_global_position: Vector2) -> void:
	if _active_hand_drag_card_uid >= 0 or _get_local_hand_reorder_zone(source_card_uid).is_empty():
		return
	# 当前正式牌面节点；只有仍由手牌容器拥有的原始实体视图可以被直接拖动。
	var source_view: CardView = _card_views.get(source_card_uid) as CardView
	if source_view == null or not is_instance_valid(source_view) or source_view.get_parent() != hand_container:
		return
	_active_hand_drag_card_uid = source_card_uid
	source_view.begin_hand_drag(pointer_global_position)


## 更新正在直接拖动的原实体手牌位置；区域变化或视图失效时立即终止，防止旧输入继续移动新局节点。
func _on_hand_drag_moved(source_card_uid: int, pointer_global_position: Vector2) -> void:
	if source_card_uid != _active_hand_drag_card_uid or _get_local_hand_reorder_zone(source_card_uid).is_empty():
		_cancel_active_hand_drag()
		return
	# 当前直接拖动的正式牌面；坐标转换封装在CardView，桌面不向节点写入任何规则数据。
	var source_view: CardView = _card_views.get(source_card_uid) as CardView
	if source_view == null or not is_instance_valid(source_view) or source_view.get_parent() != hand_container:
		_cancel_active_hand_drag()
		return
	source_view.move_hand_drag(pointer_global_position)


## 结束实体手牌直接拖动；释放点命中同分区另一张牌时按其左右半区排序，否则恢复原有规范布局。
func _on_hand_drag_finished(source_card_uid: int, pointer_global_position: Vector2) -> void:
	if source_card_uid != _active_hand_drag_card_uid:
		return
	# 拖动来源分区；木牛“粮”和普通手牌绝不允许互相成为落点。
	var source_zone: String = _get_local_hand_reorder_zone(source_card_uid)
	# 命中的目标实体 UID；在结束原节点跟随前查询，避免容器立即重排后丢失真实释放位置。
	var target_card_uid: int = _find_hand_drag_target_at_position(source_card_uid, source_zone, pointer_global_position)
	# 原实体牌面；必须先退出跟随状态，后续重排才会重新接管其位置和层级。
	var source_view: CardView = _card_views.get(source_card_uid) as CardView
	# 鼠标松开那一帧的释放点（容器坐标）；必须在退出跟随与任何重排之前取得，
	# 否则拖拽位置会先被布局写回槽位，落位过渡就失去了起点。
	var release_position: Vector2 = source_view.position if source_view != null and is_instance_valid(source_view) else Vector2.ZERO
	_active_hand_drag_card_uid = -1
	if source_view != null and is_instance_valid(source_view):
		source_view.end_hand_drag()
		# 登记拖拽落位过渡起点；下一次布局会把该牌先留在释放点，再用 drag_settle_seconds 滑向稳定槽位。
		hand_container.begin_card_settle(source_view, release_position)
	if target_card_uid < 0:
		hand_container.layout_cards_now()
		return
	# 目标原牌面；左右半区以其全局矩形为基准，滚动手牌与画布缩放下仍保持正确语义。
	var target_view: CardView = _card_views.get(target_card_uid) as CardView
	if target_view == null or not is_instance_valid(target_view):
		hand_container.layout_cards_now()
		return
	var insert_after_target: bool = pointer_global_position.x >= target_view.get_global_rect().get_center().x
	_on_hand_card_reorder_requested(source_card_uid, target_card_uid, insert_after_target)


## 在释放点寻找同分区的真实目标牌；重叠手牌优先选择当前最上层可见实体，保证结果与玩家看到的牌面一致。
func _find_hand_drag_target_at_position(source_card_uid: int, source_zone: String, pointer_global_position: Vector2) -> int:
	if source_zone.is_empty():
		return -1
	# 当前最佳目标UID；默认-1表示释放点没有落在任何同分区实体牌上。
	var result: int = -1
	# 当前最佳绘制层级；同层级时使用后加入的节点，符合重叠手牌的可见顺序。
	var best_z_index: int = -2147483648
	# 当前最佳同层级子节点索引；默认-1保证任意有效候选都可替换。
	var best_child_index: int = -1
	for card_uid_variant: Variant in _card_views.keys():
		# 当前候选实体UID；来源自身被排除，避免拖动中的原牌遮住实际落点。
		var candidate_card_uid: int = int(card_uid_variant)
		if candidate_card_uid == source_card_uid or _get_local_hand_reorder_zone(candidate_card_uid) != source_zone:
			continue
		# 当前候选正式牌面；离开手牌容器或释放中的旧节点不能接收排序。
		var candidate_view: CardView = _card_views.get(candidate_card_uid) as CardView
		if candidate_view == null or not is_instance_valid(candidate_view) or candidate_view.get_parent() != hand_container or not candidate_view.get_global_rect().has_point(pointer_global_position):
			continue
		# 当前候选在手牌容器内的绘制顺序；同层级取后者以匹配后绘制的上层实体。
		var candidate_child_index: int = candidate_view.get_index()
		if candidate_view.z_index > best_z_index or (candidate_view.z_index == best_z_index and candidate_child_index > best_child_index):
			result = candidate_card_uid
			best_z_index = candidate_view.z_index
			best_child_index = candidate_child_index
	return result


## 取消当前直接拖动并恢复原实体牌到手牌容器布局；换局、区域变化与过期输入都复用此安全收口。
func _cancel_active_hand_drag() -> void:
	if _active_hand_drag_card_uid < 0:
		return
	# 当前原实体牌面；若已释放或离开容器，只清理UID标记，绝不访问失效节点。
	var source_view: CardView = _card_views.get(_active_hand_drag_card_uid) as CardView
	_active_hand_drag_card_uid = -1
	if source_view != null and is_instance_valid(source_view):
		source_view.end_hand_drag()
	hand_container.layout_cards_now()


## 返回左下装备区的固定槽位文本；其他玩家装备仍直接显示在其武将牌状态中。
## 文本顺序与本地装备栏、武将牌装备条保持一致（武器、防具、防御坐骑、进攻坐骑、宝物）；
## 当前界面已由 EquipmentStackView 直接绘制牌面，本函数保留为同一顺序的纯文本摘要出口。
func _format_local_equipment(player: Dictionary) -> String:
	# 本地装备字典；键为weapon、armor、坐骑和treasure等稳定槽位 ID。
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	# 本地已废除装备栏；无障碍摘要优先说明“已废除”而不是把栏位误读为普通空栏。
	var abolished_slots: Dictionary = player.get("abolished_equipment_slots", {}) as Dictionary
	# 武器显示名；槽位为空时显示“无”。
	var weapon_name: String = _equipment_slot_name(equipment, "weapon", abolished_slots)
	# 防具显示名；槽位为空时显示“无”。
	var armor_name: String = _equipment_slot_name(equipment, "armor", abolished_slots)
	# 进攻坐骑显示名；槽位为空时显示“无”。
	var offensive_mount_name: String = _equipment_slot_name(equipment, "offensive_mount", abolished_slots)
	# 防御坐骑显示名；槽位为空时显示“无”。
	var defensive_mount_name: String = _equipment_slot_name(equipment, "defensive_mount", abolished_slots)
	# 宝物显示名；槽位为空时显示“无”。
	var treasure_name: String = _equipment_slot_name(equipment, "treasure", abolished_slots)
	if equipment.has("treasure") and not bool(abolished_slots.get("treasure", false)):
		# 当前宝物实体快照；木牛流马需要在装备名后直接显示公开存牌数量。
		var treasure_card: Dictionary = equipment.get("treasure", {}) as Dictionary
		var treasure_definition: Dictionary = _get_cached_card_definition(str(treasure_card.get("definition_id", "")))
		if bool(treasure_definition.get("shows_attachment_count", false)):
			# 装备公开附属牌数；0张时仍显示，避免把无存牌误解为数量信息缺失。
			var wooden_ox_count: int = int(player.get("wooden_ox_storage_count", 0))
			treasure_name += "（%d）" % wooden_ox_count
	return "⚔ 武器　%s\n🛡 防具　%s\n+ 防御　%s\n- 进攻　%s\n◇ 宝物　%s" % [weapon_name, armor_name, defensive_mount_name, offensive_mount_name, treasure_name]


## 把本地公开装备快照写入独立堆叠组件；候选与选中 UID 只来自当前本地内联请求。
func _render_local_equipment(player: Dictionary) -> void:
	# 本地装备字典；组件按固定槽位位置显示已有实体，空槽保留位置但不绘制“无”占位。
	var equipment: Dictionary = player.get("equipment", {}) as Dictionary
	# 已废除装备栏公开快照；组件以当前主题的不可交互废除占位条显示。
	var abolished_slots: Dictionary = player.get("abolished_equipment_slots", {}) as Dictionary
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
	equipment_label.configure(equipment, int(player.get("wooden_ox_storage_count", 0)), candidate_uids, selected_uids, abolished_slots)
	# 原固定槽位文本继续作为组件的完整无障碍摘要；可见牌面由堆叠横条负责。
	equipment_label.tooltip_text = ""


## 按装备槽位返回当前名称模式下的牌名；空槽位统一返回“无”。
func _equipment_slot_name(equipment: Dictionary, slot: String, abolished_slots: Dictionary = {}) -> String:
	if bool(abolished_slots.get(slot, false)):
		return "已废除"
	if not equipment.has(slot):
		return "无"
	# 当前槽位装备快照；只读取定义 ID 解析显示名称。
	var card: Dictionary = equipment.get(slot, {}) as Dictionary
	return GameSettings.resolve_card_display_name(_get_cached_card_definition(str(card.get("definition_id", ""))))


## 将本地玩家公开判定区同步到手牌区上方的独立标记组件；牌名继续遵循全局名称模式。
func _render_local_judgment_zone(player: Dictionary) -> void:
	if local_judgment_zone == null or not is_instance_valid(local_judgment_zone):
		return
	# 当前判定区公开实体；快照顺序就是规则结算顺序，标记从左到右保持同一顺序。
	var judgment_area: Array = player.get("judgment_area", []) as Array
	# 当前判定牌显示名；只读取静态定义与全局名称模式，不把实体引用交给 UI 组件。
	var judgment_names: Array[String] = []
	for judgment_variant: Variant in judgment_area:
		# 当前判定牌快照；定义缺失时名称解析会返回稳定空回退，组件仍保持固定图标尺寸。
		var judgment_card: Dictionary = judgment_variant as Dictionary
		judgment_names.append(GameSettings.resolve_card_name(_get_cached_card_definition(str(judgment_card.get("definition_id", "")))))
	local_judgment_zone.configure(judgment_names, bool(player.get("judgment_area_abolished", false)))
	_queue_local_judgment_zone_layout()


## 将本地玩家公开标记同步到手牌栏上方左侧横排；空集合隐藏且自动释放判定区避让宽度。
func _render_local_player_markers(player: Dictionary) -> void:
	if local_player_markers == null or not is_instance_valid(local_player_markers):
		return
	# 本地公开标记；与其他观察者收到的内容一致，不包含身份推测或客户端私有状态。
	var public_marks: Dictionary = player.get("public_marks", {}) as Dictionary
	local_player_markers.configure(public_marks, true)
	_queue_local_judgment_zone_layout()


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
		# 初始规则预览；全体目标牌由规则层展开，只有明确列出的三张自身牌保留自动选择本人。
		var initial_preview: Dictionary = match_controller.get_card_use_preview(match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
		# 当前目标模式；普通单目标牌即使只有一名候选也必须等待玩家点击，不再静默锁定。
		var target_mode: String = str(initial_preview.get("target_mode", ""))
		# 当前实体快照；视为牌继续读取逻辑定义 ID，因此按【桃】视为的手牌也遵循【桃】的自动自身目标语义。
		var selected_card: Dictionary = _get_selected_card_snapshot()
		# 当前逻辑牌定义 ID；只有白名单中的三张自身牌允许自动锁定本地玩家。
		var selected_definition_id: String = str(selected_card.get("definition_id", ""))
		# 当前逻辑牌定义；装备是否仅能装备给自身由通用类型与目标模式声明，不维护装备 ID 白名单。
		var selected_definition: Dictionary = _get_cached_card_definition(selected_definition_id)
		# 自身限定装备；所有 type=equipment 且 target_mode=self 的装备都与自身牌使用同一自动锁定流程。
		var is_self_only_equipment: bool = str(selected_definition.get("type", "")) == "equipment" and target_mode == "self"
		# 唯一合法目标；自动锁定只在规则预览确认本人是唯一候选时成立，异常空候选不会伪造目标。
		var legal_target_ids: Array = initial_preview.get("legal_target_ids", []) as Array
		var only_self_is_legal: bool = legal_target_ids.size() == 1 and int(legal_target_ids[0]) == match_controller.local_human_player_id
		if only_self_is_legal and (((target_mode == "self" or target_mode == "self_wounded") and AUTO_SELECTED_SELF_CARD_DEFINITION_IDS.has(selected_definition_id)) or is_self_only_equipment):
			_selected_target_ids.assign([match_controller.local_human_player_id])
			_auto_locked_target_id = match_controller.local_human_player_id
		elif target_mode == "all_players" or target_mode == "all_others":
			_selected_target_ids.clear()
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
	var definition: Dictionary = _get_cached_card_definition(str(equipment_card.get("definition_id", "")))
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
	# 装备材料选满后仍由玩家手动点击目标；唯一候选不再自动写入临时目标数组。
	error_label.text = ""
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


## 判断内联响应候选是否为需要额外普通手牌材料的装备入口。
func _is_inline_material_equipment_response_candidate(card_uid: int) -> bool:
	# 只有权威请求已经声明为响应时，装备才可以进入材料响应模式；弃置、获得等普通选牌不能被装备定义劫持。
	if str(_inline_card_choice.get("choice_type", "")) != "respond":
		return false
	for candidate_variant: Variant in _inline_card_choice.get("candidates", []) as Array:
		# 当前候选；装备定义元数据声明响应材料数量。
		var candidate: Dictionary = candidate_variant as Dictionary
		var candidate_card: Dictionary = candidate.get("card_data", {}) as Dictionary
		if int(candidate.get("uid", -1)) == card_uid and int(candidate.get("owner_id", -1)) == match_controller.local_human_player_id and str(candidate.get("zone", "")) == "equipment":
			var definition: Dictionary = _get_cached_card_definition(str(candidate_card.get("definition_id", "")))
			return int(definition.get("response_material_count", 0)) > 0
	return false


## 返回当前主动装备的静态定义；没有活动装备时返回空字典。
func _get_active_equipment_definition() -> Dictionary:
	var equipment_card: Dictionary = _get_local_equipment_snapshot(_active_equipment_uid)
	return _get_cached_card_definition(str(equipment_card.get("definition_id", "")))


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
		# 内联技能选目标；只有 target 与 card_target 请求允许武将牌写入临时目标集合。
		var inline_choice_type: String = str(_inline_card_choice.get("choice_type", "card"))
		if inline_choice_type not in ["target", "target_control", "card_target"]:
			return
		# 当前请求目标候选；界面只更新临时集合，确认时仍由权威 ChoiceRequest 复核。
		var inline_target_ids: Array[int] = _get_selectable_target_ids()
		if not inline_target_ids.has(target_id):
			return
		# 目标上限；上限为1时点击新目标直接替换旧目标，与普通单目标牌保持一致操作语义。
		var inline_maximum_target_count: int = int(_inline_card_choice.get("max_target_select", _inline_card_choice.get("max_select", 1)))
		if _selected_target_ids.has(target_id):
			_selected_target_ids.erase(target_id)
		else:
			if inline_maximum_target_count == 1:
				_selected_target_ids.clear()
			if _selected_target_ids.size() < inline_maximum_target_count:
				_selected_target_ids.append(target_id)
		_refresh_selection_text()
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
	if str(_snapshot.get("current_phase", "")) == "ai_character_adjustment":
		# 当前本地是否为房主；其他玩家只显示等待提示，点击武将牌不提交网络动作。
		var pre_game_setup: Dictionary = _snapshot.get("pre_game_setup", {}) as Dictionary
		if int(pre_game_setup.get("host_player_id", -1)) != match_controller.local_human_player_id:
			return
		# 房主调整 AI 目标动作；核心仍会再次校验房主身份与目标属于内置 AI。
		var adjustment_action: PlayerAction = PlayerAction.new("select_ai_adjustment_target", match_controller.local_human_player_id)
		adjustment_action.payload = {"target_player_id":player_view.player_id}
		match_controller.submit_action(adjustment_action)
		return
	_on_target_pressed(player_view.player_id)


## 返回当前牌面可点击的合法目标；单目标牌保留空选择时的完整候选，支持一次点击直接切换目标。
func _get_selectable_target_ids() -> Array[int]:
	if not _inline_card_choice.is_empty():
		# 内联技能目标候选；选牌/响应请求没有目标维度时返回空数组。
		var inline_choice_type: String = str(_inline_card_choice.get("choice_type", "card"))
		if inline_choice_type not in ["target", "target_control", "card_target"]:
			return []
		var inline_target_ids: Array[int] = []
		inline_target_ids.assign(_inline_card_choice.get("target_ids", []) as Array)
		# 当前请求恢复上下文；组合映射只读取可序列化字典，不能把规则对象传入界面。
		var inline_context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
		# 多材料组合到完整目标映射；山倾在选择两张材料时按当前材料前缀即时收窄目标。
		var target_ids_by_card_combination: Dictionary = inline_context.get("target_combinations_by_card_combination", {}) as Dictionary
		if inline_choice_type == "card_target" and not target_ids_by_card_combination.is_empty():
			return _get_inline_combination_target_ids(target_ids_by_card_combination, _inline_selected_card_uids, inline_target_ids)
		# 牌到目标组合映射；选中一张材料牌后只高亮该牌当前允许的目标。
		if inline_choice_type == "card_target" and _inline_selected_card_uids.size() == 1:
			# 实体牌UID到完整有序目标组合的映射；优先用于不同材料转化出不同目标数量的主动技能。
			var target_combinations_by_card_id: Dictionary = inline_context.get("target_combinations_by_card_id", {}) as Dictionary
			if not target_combinations_by_card_id.is_empty():
				# 当前唯一选中的材料UID；完整组合只在该材料范围内筛选，不回退到其他材料的目标。
				var selected_material_uid: int = _inline_selected_card_uids[0]
				# 当前材料全部完整目标组合；字符串和整数键共同兼容网络序列化。
				var target_combinations: Array = target_combinations_by_card_id.get(str(selected_material_uid), target_combinations_by_card_id.get(selected_material_uid, [])) as Array
				# 当前准备选择的目标位置；已选目标形成前缀，下一次点击只能补全至少一条合法组合。
				var target_position: int = _selected_target_ids.size()
				# 下一步可点击目标；按映射出现顺序去重，保证目标高亮与点击顺序稳定。
				var next_target_ids: Array[int] = []
				for target_combination_variant: Variant in target_combinations:
					# 当前有序目标组合；需要先匹配已选前缀，才能开放后续位置。
					var target_combination: Array = target_combination_variant as Array
					if target_combination.size() <= target_position:
						continue
					# 当前组合是否匹配已经选择的目标前缀；顺序必须保留，不能把借刀两名目标视为无序集合。
					var matches_selected_prefix: bool = true
					for selected_index: int in range(_selected_target_ids.size()):
						if int(target_combination[selected_index]) != _selected_target_ids[selected_index]:
							matches_selected_prefix = false
							break
					if matches_selected_prefix:
						# 当前可追加目标；只在尚未出现时写入，避免重复目标破坏请求的单击语义。
						var next_target_id: int = int(target_combination[target_position])
						if not next_target_ids.has(next_target_id):
							next_target_ids.append(next_target_id)
				inline_target_ids = next_target_ids
				return inline_target_ids
			# 实体牌 UID 到合法目标 ID 数组的映射；空字典表示全部请求目标均可用。
			var targets_by_card_id: Dictionary = inline_context.get("target_ids_by_card_id", {}) as Dictionary
			if not targets_by_card_id.is_empty():
				# 当前唯一选中的材料牌 UID；用于取得该牌自己的合法目标集合。
				var selected_card_uid: int = _inline_selected_card_uids[0]
				inline_target_ids.assign(targets_by_card_id.get(str(selected_card_uid), targets_by_card_id.get(selected_card_uid, [])) as Array)
		return inline_target_ids
	if _uses_rule_expanded_targets():
		# 群体锦囊由规则自动展开目标：亮起集合取规范化后的合法目标，禁止手动点选写入。
		# 非法目标在选中该牌期间压暗；藤甲等“效果无效”仍会进入展开列表，因此不会被暗置。
		var expanded_target_ids: Array[int] = []
		expanded_target_ids.assign(_card_use_preview.get("normalized_target_ids", []) as Array)
		return expanded_target_ids
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


## 根据已选材料前缀读取多材料组合的下一步合法目标；未选材料时返回所有可行组合目标并集。
func _get_inline_combination_target_ids(target_mapping: Dictionary, selected_card_uids: Array[int], fallback_target_ids: Array[int]) -> Array[int]:
	# 已声明的完整材料组合；山倾通过该数组让界面无需解析字典键即可判断前缀兼容性。
	var valid_card_combinations: Array = (_inline_card_choice.get("context", {}) as Dictionary).get("valid_card_combinations", []) as Array
	if valid_card_combinations.is_empty():
		return fallback_target_ids
	# 当前目标位置；已选目标按点击顺序形成完整目标数组前缀。
	var target_position: int = _selected_target_ids.size()
	# 当前多材料目标结果；按权威组合与目标数组顺序去重。
	var result: Array[int] = []
	for card_combination_variant: Variant in valid_card_combinations:
		# 当前完整材料组合；只要包含已选材料前缀即可继续展示其目标。
		var card_combination: Array[int] = []
		for card_uid_variant: Variant in card_combination_variant as Array:
			card_combination.append(int(card_uid_variant))
		var contains_selected_cards: bool = true
		for selected_card_uid: int in selected_card_uids:
			if not card_combination.has(selected_card_uid):
				contains_selected_cards = false
				break
		if not contains_selected_cards:
			continue
		# 当前材料组合对应的完整目标数组；缺失映射时禁止回退到全部目标。
		var target_combinations: Array = target_mapping.get(_make_card_combination_key(card_combination), []) as Array
		for target_combination_variant: Variant in target_combinations:
			# 当前有序目标组合；目标位置超出长度时表示该组合已完成，不能再添加目标。
			var target_combination: Array = target_combination_variant as Array
			if target_combination.size() <= target_position:
				continue
			# 当前目标前缀是否仍匹配；多目标技能必须保留玩家点击顺序。
			var matches_selected_prefix: bool = true
			for selected_index: int in range(_selected_target_ids.size()):
				if int(target_combination[selected_index]) != _selected_target_ids[selected_index]:
					matches_selected_prefix = false
					break
			if matches_selected_prefix:
				# 当前下一目标；同一目标由多个材料组合支持时只显示一次。
				var next_target_id: int = int(target_combination[target_position])
				if not result.has(next_target_id):
					result.append(next_target_id)
	return result


## 将材料UID集合规范化为稳定组合键；排序只影响映射查询，不改变玩家点击顺序。
func _make_card_combination_key(card_uids: Array[int]) -> String:
	# 排序后的UID副本；同一材料组合无论点击先后都命中同一键。
	var normalized_uids: Array[int] = card_uids.duplicate()
	normalized_uids.sort()
	# 字符串键；网络快照经过JSON化后仍保持一致。
	var key_parts: Array[String] = []
	for card_uid: int in normalized_uids:
		key_parts.append(str(card_uid))
	return ",".join(key_parts)


## 返回当前卡牌是否由规则层自动展开全体目标；此类牌仍禁止武将牌点击改目标，但会用展开结果做预览暗置。
func _uses_rule_expanded_targets() -> bool:
	if _selected_card_uid < 0 or not _active_equipment_action.is_empty():
		return false
	return str(_card_use_preview.get("target_mode", "")) in ["all_players", "all_others"]


## 判断当前界面是否处于目标预览/选择态；合法目标保持正常亮度，非法目标在此期间压暗。
## 群体锦囊虽不可手动点选目标，仍开启该态，以规则展开后的合法目标集合控制暗置范围。
func _is_manual_target_selection_active() -> bool:
	if not _inline_card_choice.is_empty():
		return str(_inline_card_choice.get("choice_type", "card")) in ["target", "target_control", "card_target"]
	if not _active_equipment_action.is_empty():
		return int(_card_use_preview.get("max_targets", 0)) > 0
	if _selected_card_uid < 0:
		return false
	# 群体锦囊：开启暗置预览，亮起集合来自 normalized_target_ids 而非手动候选。
	if _uses_rule_expanded_targets():
		return true
	return int(_card_use_preview.get("max_targets", 0)) > 0


## 将本地玩家自身加入或移出目标列表。
func _on_self_target_pressed() -> void:
	_on_target_pressed(match_controller.local_human_player_id)


## 提交使用牌动作；本地阵亡或终局时复用同一位置按当前设置重新开局，其他情况继续提交标准动作。
func _on_use_pressed() -> void:
	if _should_show_post_match_actions():
		_on_restart_requested(match_menu.get_next_player_count())
		return
	if str(_snapshot.get("current_phase", "")) == "ai_character_adjustment":
		match_controller.submit_action(PlayerAction.new("finish_ai_character_adjustment", match_controller.local_human_player_id))
		return
	if str(_snapshot.get("current_phase", "")) == "starting_hand_mulligan":
		match_controller.submit_action(PlayerAction.new("mulligan_refresh", match_controller.local_human_player_id))
		return
	if not _active_equipment_action.is_empty():
		_submit_equipment_action()
		return
	if not _inline_card_choice.is_empty():
		if _is_inline_zhenqi_cost_choice(_inline_card_choice):
			_submit_inline_control_choice("discard_hand")
			return
		if _is_inline_control_choice(_inline_card_choice):
			if not _inline_control_primary_option_id.is_empty():
				_submit_inline_control_choice(_inline_control_primary_option_id)
			return
		_submit_inline_card_choice(_inline_selected_card_uids)
		return
	if _selected_card_uid < 0:
		_on_action_rejected("请先选择一张手牌。")
		return
	# 无目标铁索连环；确定按钮直接提交重铸并摸1张牌，不再依赖独立“重铸”按钮。
	var selected_card: Dictionary = _get_selected_card_snapshot()
	var selected_definition: Dictionary = _get_cached_card_definition(str(selected_card.get("definition_id", "")))
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
	# 回放重演期间牌桌快捷键整体失效；退出与调速由回放覆盖层独立处理。
	if _replay_session_active:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		# 当前键盘事件；只响应确认、取消和结束出牌三个稳定桌面操作。
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			if not _active_equipment_action.is_empty():
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif _is_inline_zhenqi_cost_choice(_inline_card_choice):
				_on_zhenqi_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif _is_inline_control_choice(_inline_card_choice) and bool(_inline_card_choice.get("allow_cancel", false)):
				_submit_inline_control_choice("", false)
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
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# 当前未被任何控件消费的鼠标按键；左键表示点击牌桌空白处，右键沿用规则选择取消快捷操作。
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and _close_open_match_overlays_from_blank_click():
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if not _active_equipment_action.is_empty():
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif _is_inline_zhenqi_cost_choice(_inline_card_choice):
				_on_zhenqi_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif _is_inline_control_choice(_inline_card_choice) and bool(_inline_card_choice.get("allow_cancel", false)):
				_submit_inline_control_choice("", false)
				get_viewport().set_input_as_handled()
			elif not _inline_card_choice.is_empty() and bool(_inline_card_choice.get("allow_cancel", false)):
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
			elif _selected_card_uid >= 0:
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()


## 关闭点击牌桌空白处时仍展开的对局记录与局内菜单；返回 true 表示本次点击实际收起了至少一个浮层。
func _close_open_match_overlays_from_blank_click() -> bool:
	if main_menu != null and main_menu.visible:
		return false
	# 是否关闭了任一浮层；两个面板可同时展开，因此需要分别处理后再统一返回。
	var closed_any_overlay: bool = false
	if match_log_panel != null and match_log_panel.is_expanded():
		match_log_panel.set_expanded(false)
		closed_any_overlay = true
	if match_menu != null and match_menu.is_menu_open():
		match_menu.set_menu_open(false)
		closed_any_overlay = true
	if match_chat_panel != null and is_instance_valid(match_chat_panel) and match_chat_panel.is_open():
		match_chat_panel.close_panel()
		closed_any_overlay = true
	return closed_any_overlay


## 处理没有被模态界面、详情框或选牌流程消费的安卓返回键；主页退出应用，对局中切换局内菜单。
func _on_unhandled_android_back_requested() -> void:
	if _replay_session_active:
		# 回放重演期间返回键等同“退出回放”；直接结束重演会话回到回放列表。
		_end_replay_session()
		return
	if main_menu.visible:
		get_tree().quit()
		return
	if match_chat_panel != null and is_instance_valid(match_chat_panel) and match_chat_panel.is_open():
		# 返回键优先收起聊天窗口；与设置、联机面板等可取消层保持一致的返回语义。
		match_chat_panel.close_panel()
		return
	match_menu.set_menu_open(not match_menu.is_menu_open())


## 取消当前选牌与目标；本地阵亡或终局时复用同一位置返回主菜单。
func _on_cancel_pressed() -> void:
	if _should_show_post_match_actions():
		_on_main_menu_requested()
		return
	if str(_snapshot.get("current_phase", "")) == "starting_hand_mulligan":
		match_controller.submit_action(PlayerAction.new("mulligan_finish", match_controller.local_human_player_id))
		return
	if not _active_equipment_action.is_empty():
		_clear_equipment_action()
		_selected_target_ids.clear()
		_auto_locked_target_id = -1
		error_label.text = ""
		_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
		_render_local_hand()
		_render_local_skills(_get_player_snapshot(match_controller.local_human_player_id))
		_refresh_selection_text()
		return
	if not _inline_card_choice.is_empty():
		if _is_inline_zhenqi_cost_choice(_inline_card_choice):
			_submit_inline_control_choice("lose_hp")
			return
		if _is_inline_control_choice(_inline_card_choice):
			# 第二项此刻确实可提交时才代替取消；未满足目标或手牌维度时，本按键回退为真正的放弃语义。
			# 这条回退对牌堆位次询问尤其重要：未选牌时「牌堆顶第二张」不可提交，右键与Esc必须仍能取消本次放置。
			if not _inline_control_secondary_option_id.is_empty() and _is_inline_control_option_submittable(_inline_control_secondary_option_id):
				_submit_inline_control_choice(_inline_control_secondary_option_id)
			elif bool(_inline_card_choice.get("allow_cancel", false)):
				_submit_inline_control_choice("", false)
			return
		if bool(_inline_card_choice.get("allow_cancel", false)):
			# 空选择；明确表示放弃本次可取消请求，不会消费任何手牌。
			var cancelled_uids: Array[int] = []
			_submit_inline_card_choice(cancelled_uids, false)
		return
	_selected_card_uid = -1
	_selected_target_ids.clear()
	_auto_locked_target_id = -1
	error_label.text = ""
	_refresh_selection_text()


## 取消【振旗】费用选择；第三个按钮提交明确的 confirmed=false，保持与普通可取消请求完全一致的权威语义。
func _on_zhenqi_cancel_pressed() -> void:
	if _is_inline_zhenqi_cost_choice(_inline_card_choice):
		_submit_inline_control_choice("", false)


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


## 设置全局卡牌名称模式；所有牌面与装备名称随后统一刷新。
func _on_name_mode_pressed(mode: int) -> void:
	GameSettings.set_card_name_mode(mode)


## 响应名称模式变化并重新渲染现有快照；技能说明中的卡牌引用与牌面使用同一名称模式。
func _on_card_name_mode_changed(_mode: GameSettings.NameMode) -> void:
	match_menu.refresh_card_name_text()
	if information_box != null and is_instance_valid(information_box):
		information_box.refresh_card_name_mode()
	if not _snapshot.is_empty():
		_render_players()
		_render_local_skills(_get_player_snapshot(match_controller.local_human_player_id))
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
	($BackdropShade as ColorRect).color = BattleUIStyle.get_color("backdrop_shade", Color.TRANSPARENT)
	($TableOrnament as TextureRect).modulate = BattleUIStyle.get_color("ornament_overlay", Color(BattleUIStyle.get_color("ornament"), 0.12))
	($TopInfoPanel as PanelContainer).add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	# 顶栏轮次与关卡统一指定回退字体；动态显示“第N关”时不会因场景默认主题差异出现字形不一致。
	_apply_top_info_primary_label_style()
	center_turn_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	center_phase_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	match_menu.refresh_ui_style()
	main_menu.refresh_ui_style()
	BattleUIStyle.apply_interaction_button(%LogToggleButton, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(auto_manage_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), false)
	(%LogContentPanel as PanelContainer).add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	($LogPanel/LogContentPanel/LogVBox/LogTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	log_view.add_theme_color_override("default_color", BattleUIStyle.get_color("text_secondary"))
	interaction_guide_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_guide"))
	selection_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	error_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger"))
	BattleUIStyle.apply_interaction_button(use_button)
	BattleUIStyle.apply_interaction_button(settlement_button)
	BattleUIStyle.apply_interaction_button(%CancelButton)
	if game_settlement_panel != null and is_instance_valid(game_settlement_panel):
		game_settlement_panel.refresh_ui_style()
	if opportunity_choice_panel != null and is_instance_valid(opportunity_choice_panel):
		opportunity_choice_panel.refresh_ui_style()
	if match_chat_panel != null and is_instance_valid(match_chat_panel):
		match_chat_panel.refresh_ui_style()
	if _match_replay_overlay != null and is_instance_valid(_match_replay_overlay):
		_match_replay_overlay.refresh_ui_style()
	for chat_bubble_variant: Variant in _chat_bubbles.values():
		# 当前玩家头顶气泡；主题切换时按当前风格重绘底色、描边与文字色。
		var chat_bubble: ChatBubbleView = chat_bubble_variant as ChatBubbleView
		if chat_bubble != null and is_instance_valid(chat_bubble):
			chat_bubble.refresh_ui_style()
	_refresh_group_trick_response_button()
	card_selection_panel.refresh_ui_style()
	character_selection_panel.refresh_ui_style()
	card_use_animation_layer.target_line_color = BattleUIStyle.get_color("target_line")
	equipment_label.refresh_ui_style()
	if local_judgment_zone != null and is_instance_valid(local_judgment_zone):
		local_judgment_zone.refresh_ui_style()
	if local_player_markers != null and is_instance_valid(local_player_markers):
		local_player_markers.refresh_ui_style()
	if information_box != null and is_instance_valid(information_box):
		information_box.refresh_ui_style()
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


## 把同一份显式标签样式应用到关卡与轮次；字体、字号和颜色与牌堆剩余数、对局时长保持一致。
func _apply_top_info_primary_label_style() -> void:
	if phase_label == null:
		return
	if _top_info_primary_label_settings == null:
		_top_info_primary_label_settings = LabelSettings.new()
	_top_info_primary_label_settings.font = ThemeDB.fallback_font
	_top_info_primary_label_settings.font_size = TOP_INFO_PRIMARY_FONT_SIZE
	_top_info_primary_label_settings.font_color = BattleUIStyle.get_color("text_secondary")
	phase_label.label_settings = _top_info_primary_label_settings
	if conquest_level_label != null:
		conquest_level_label.label_settings = _top_info_primary_label_settings
	if center_turn_label != null:
		center_turn_label.add_theme_font_override("font", ThemeDB.fallback_font)
		center_turn_label.add_theme_font_size_override("font_size", TOP_INFO_PRIMARY_FONT_SIZE)
	if center_phase_label != null:
		center_phase_label.add_theme_font_override("font", ThemeDB.fallback_font)
		center_phase_label.add_theme_font_size_override("font_size", TOP_INFO_PRIMARY_FONT_SIZE)


## 清空日志并使用菜单设置的人数启动下一局；当前对局人数只在重新开局时改变。
## 返回 true 表示权威对局已创建并可关闭主菜单；返回 false 时根据旧状态是否仍有效恢复局内菜单或主菜单。
func _on_restart_requested(player_count: int) -> bool:
	if match_controller.network_gateway.is_lan_client():
		match_controller.action_rejected.emit("局域网客户端不能重新创建对局，请等待房主操作。")
		return false
	if match_controller.network_gateway.is_lan_host() and match_controller.network_gateway.is_lan_match_active():
		# 当前局域网总人数；同一 ENet 房间重开保持真人映射稳定，暂不允许改变总座位数。
		# 对局进行中快照返回的已是规则角色总数；过关斩将的局内菜单不暴露人数控件，重开直接沿用该权威角色数。
		var current_lan_player_count: int = int(match_controller.network_gateway.get_lan_lobby_snapshot().get("player_count", player_count))
		if GameSettings != null and GameSettings.normalize_match_mode(GameSettings.next_match_mode) == GameSettings.MATCH_MODE_CONQUEST:
			player_count = current_lan_player_count
		elif player_count != current_lan_player_count:
			match_controller.action_rejected.emit("局域网房间内重新开始时不能改变游戏总人数。")
			return false
		# 重新开始必须重新随机排布座位：在创建新对局前按大厅位置重建“真人→规则座次”映射并重新洗牌。
		# 重开复用映射会让每局座位完全相同，且只置换真人座次时 2 名真人的相对顺序几乎不变，观感就是“座位没有随机”。
		# 上一局已签发的会话令牌与掉线座位预约由网关按大厅位置迁移到新座位，断线重连的玩家身份不受重开影响。
		var reassignment_error: String = match_controller.network_gateway.prepare_lan_match_assignments(current_lan_player_count, true)
		if not reassignment_error.is_empty():
			match_controller.action_rejected.emit(reassignment_error)
			return false
	# 离线过关斩将是否必须锁定角色总数；该模式的人数设置只有局域网大厅才表示“玩家数×2”，
	# 离线单人游玩固定为1名本地玩家对1名敌人，因此任何调用方传入的更大角色数都在此收敛。
	var offline_conquest_roles_locked: bool = match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE and GameSettings != null and GameSettings.normalize_match_mode(GameSettings.next_match_mode) == GameSettings.MATCH_MODE_CONQUEST
	if offline_conquest_roles_locked:
		# 离线过关斩将最终角色总数；不读取菜单人数残值，避免单人局被扩大成多名玩家与多名敌人。
		player_count = GameSettings.OFFLINE_CONQUEST_ROLE_COUNT
	match_controller.default_player_count = player_count
	_last_action_rejection_message = ""
	# 开局前置校验错误；必须在清除旧日志、动画与选择表现前读取，拒绝时原对局可继续安全运行。
	var validation_error: String = match_controller.get_match_start_validation_error(player_count)
	if not validation_error.is_empty():
		match_controller.start_match(player_count)
		if not main_menu.visible:
			match_menu.restore_after_restart_failure()
		return false
	_reset_presentation_for_new_match()
	# 当前开局结果；控制器同步返回后才能决定保留主菜单、恢复主菜单或进入新一局选将。
	var match_started: bool = match_controller.start_match(player_count)
	if match_started and match_controller.state != null and str(match_controller.state.match_mode) == GameSettings.MATCH_MODE_CONQUEST:
		# 全新过关斩将开局意味着放弃上一次临时退出的进度；清除旧存档并恢复主菜单主按钮文字。
		ConquestSaveStore.clear_save()
		main_menu.refresh_start_button_text()
	if not match_started and match_controller.state != null and not main_menu.visible:
		match_menu.restore_after_restart_failure()
	elif not match_started and not main_menu.visible:
		# 当前重开失败原因；控制器正常会先发出 action_rejected，空值仅作为未知扩展失败的稳定兜底。
		var failure_message: String = _last_action_rejection_message if not _last_action_rejection_message.is_empty() else "无法重新开始游戏，请检查数据配置后重试。"
		main_menu.set_next_player_count(player_count)
		main_menu.restore_after_failed_restart(failure_message)
	return match_started


## 清空上一局残留的全部本地表现与临时交互状态；普通重开与存档恢复开局共用本入口。
func _reset_presentation_for_new_match() -> void:
	# 过场动画先于其它表现清理：它可能正持有对局暂停令牌，不释放会让新局一开始就停住。
	if ahha_moment_cutscene != null and is_instance_valid(ahha_moment_cutscene):
		ahha_moment_cutscene.stop_cutscene()
	if information_box != null and is_instance_valid(information_box):
		information_box.close_character_details()
	if game_settlement_panel != null and is_instance_valid(game_settlement_panel):
		game_settlement_panel.hide_settlement()
	_settlement_auto_shown_match_id = ""
	match_log_panel.clear_entries()
	if match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE:
		# 离线对局的聊天历史按局清空；LAN 的房间级历史由网关在大厅开局与会话结束边界维护，同房重开保留聊天。
		match_controller.network_gateway.clear_match_chat_history()
	if match_chat_panel != null and is_instance_valid(match_chat_panel):
		# 聊天窗口收起并与网关当前历史重新对齐；离线新局为空正文，LAN 同房重开保留原正文。
		match_chat_panel.close_panel()
		match_chat_panel.set_history(match_controller.network_gateway.get_match_chat_history())
	_dismiss_all_chat_bubbles()
	card_use_animation_layer.clear_presentations()
	# 未收齐的摸牌表现批次随旧局丢弃；新局与回放重演的批次 ID 从干净容器开始，不继承旧填充。
	_draw_presentation_batches.clear()
	_clear_local_hand_gain_animations()
	# 虚拟手牌替换状态随旧局丢弃；否则新局可能残留上一局的占位 UID 与离场补间。
	_clear_virtual_hand_choice()
	_local_hand_display_order.clear()
	_local_wooden_ox_display_order.clear()
	_hand_order_match_id = ""
	card_selection_panel.close()
	# 选将面板持有本地座次与身份的乐观选择值，且其取值优先级高于快照权威字段；
	# 新对局必须在这里复位它，否则同一阶段名（如 PHASE_OTHERS）与同一目标玩家会让面板的
	# 上下文延续判断成立，把上一局缓存的座次与身份继续显示并写进确认载荷，造成“开局显示的
	# 座位与选将完成后所在座位不相符”。返回主菜单路径与主菜单可见性同步都会关闭该面板，
	# 只有局内“按设置重新开局”不经过主菜单，因此复位必须放在本共用入口。
	if character_selection_panel != null and is_instance_valid(character_selection_panel):
		character_selection_panel.close()
	# 记录牌名只读窗口随旧局丢弃；它不属于任何选择请求，因此必须在此显式清空，
	# 否则新局仍会按旧数据重新打开一个查看窗口。注意不能放进 _on_state_changed：
	# 出牌阶段每次状态广播都会清空，会让窗口在 AI 行动期间刚显示就被关闭。
	_recorded_names_view.clear()
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
	if _match_clock_timer != null:
		_match_clock_timer.stop()
	_presented_discard_card_uids.clear()
	_identity_marks.clear()
	_identity_mark_target_id = -1
	# 本地标注的对局归属同步归零；下一份快照会按新 match_id 重新建立归属，避免旧局 ID 被误判为同一局。
	_identity_marks_match_id = ""
	_suppressed_group_trick_uid = -1


## 从存档恢复上一局过关斩将；失败时清除无法继续的存档并把具体原因反馈到主菜单入口。
func _on_conquest_resume_requested(save_data: Dictionary) -> bool:
	if match_controller.network_gateway.is_lan_client() or match_controller.network_gateway.is_lan_host():
		match_controller.action_rejected.emit("局域网会话中不能继续过关斩将存档。")
		return false
	_last_action_rejection_message = ""
	# 恢复前置校验错误；失败时不清理旧表现，主菜单保持可见并提示玩家。
	var resume_validation_error: String = match_controller.get_conquest_resume_validation_error(save_data)
	if not resume_validation_error.is_empty():
		# 无法继续的存档保留只会让“继续上次游戏”按钮永远失败；清除后玩家可直接开始新的一局。
		ConquestSaveStore.clear_save()
		main_menu.refresh_start_button_text()
		main_menu.show_start_error("%s存档已清除，可重新开始新对局。" % resume_validation_error)
		return false
	_reset_presentation_for_new_match()
	# 恢复结果；校验已提前通过，此处失败属于罕见的运行时异常，同样清档避免入口死循环。
	var match_resumed: bool = match_controller.resume_conquest_match(save_data)
	if not match_resumed:
		ConquestSaveStore.clear_save()
		main_menu.refresh_start_button_text()
		var resume_failure_message: String = _last_action_rejection_message if not _last_action_rejection_message.is_empty() else "无法继续上次对局，存档已清除。"
		main_menu.show_start_error(resume_failure_message)
	return match_resumed


## 转发局内菜单的临时退出切换请求；按权威当前预约状态在预约与取消之间切换，并立即回写按钮文字。
func _on_conquest_temporary_exit_toggle_requested() -> void:
	if match_controller.is_conquest_temporary_exit_requested():
		match_controller.cancel_conquest_temporary_exit()
	else:
		match_controller.request_conquest_temporary_exit()
	match_menu.set_conquest_exit_armed(match_controller.is_conquest_temporary_exit_requested())


## 接收控制器在回合边界发出的临时退出存档；写入本地文件后按标准返回主菜单流程结束当前会话。
## 文件写入失败时仍按玩家意图退出，但保留旧存档文件并弹出提醒，避免静默丢失更早的进度。
func _on_conquest_exit_save_ready(save_data: Dictionary) -> void:
	# 存档写入结果；成功后主菜单的“开始游戏”会因存在存档而显示“继续上次游戏”。
	var save_written: bool = ConquestSaveStore.write_save(save_data)
	if not save_written and information_box != null and is_instance_valid(information_box):
		information_box.show_notice("过关斩将进度写入失败，本次临时退出未生成新存档。")
	match_menu.set_conquest_exit_armed(false)
	# 下一局模式保持过关斩将；重新打开游戏后主菜单会直接选中该模式并显示继续入口。
	if GameSettings != null:
		GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_CONQUEST)
	# 延迟一帧再拆除对局运行时；存档信号发自回合边界的规则调用栈内部，直接同步拆除存在重入风险。
	call_deferred("_on_main_menu_requested")


## 过关斩将终局时清除临时退出存档；对局已经分出胜负，上一次临时退出的进度不再具有继续意义。
func _on_match_finished_for_conquest_save(_winner: String) -> void:
	if match_controller.state == null or str(match_controller.state.match_mode) != GameSettings.MATCH_MODE_CONQUEST:
		return
	ConquestSaveStore.clear_save()
	match_menu.set_conquest_exit_armed(false)
	main_menu.refresh_start_button_text()


## 退出当前权威对局并恢复主菜单；局内表现保留在主菜单下方但不再获得焦点或规则更新。
func _on_main_menu_requested() -> void:
	if information_box != null and is_instance_valid(information_box):
		information_box.close_character_details()
	_hide_game_settlement_panel_for_main_menu()
	if match_chat_panel != null and is_instance_valid(match_chat_panel):
		match_chat_panel.close_panel()
	_dismiss_all_chat_bubbles()
	# 未保存的回放录制随对局放弃一并丢弃；已保存的回放文件不受影响。
	_match_replay_recorder.discard_recording()
	match_controller.abandon_match()
	if match_controller.network_gateway.mode == NetworkGateway.Mode.LAN:
		match_controller.network_gateway.leave_lan("")
		match_controller.clear_remote_network_state()
	card_selection_panel.close()
	# 选将面板必须与选牌面板一同关闭：车轮战抓将中的候选牌带有“我方选择”“对方选择”中央标记，只隐藏不清理会把这些文本留在主菜单之上。
	character_selection_panel.close()
	_inline_card_choice.clear()
	_inline_selected_card_uids.clear()
	_modal_choice_request_id = -1
	_modal_card_choice_request.clear()
	_suppressed_group_trick_uid = -1
	if _match_clock_timer != null:
		_match_clock_timer.stop()
	main_menu.set_next_player_count(match_menu.get_next_player_count())
	main_menu.return_to_main_menu()


## 主菜单覆盖牌桌时隐藏右上局内菜单入口；可见性切换由主菜单信号驱动，测试与场景路由同样生效。
func _sync_match_menu_visibility() -> void:
	if main_menu == null or not is_instance_valid(main_menu):
		return
	var main_menu_visible: bool = main_menu.visible
	# 主菜单可见是所有返回入口的最终界面边界；即使未来入口漏掉主动清理，也不能让终局模态继续覆盖主菜单。
	if main_menu_visible:
		_hide_game_settlement_panel_for_main_menu()
		# 选将遮罩同样属于“覆盖主菜单”的局内浮层：任何返回入口漏掉主动关闭时，这里也必须收起它。
		# 车轮战抓将候选牌携带“我方选择”“对方选择”文本，只隐藏遮罩不清理候选会把这些文本永久留在屏幕上。
		if character_selection_panel != null and is_instance_valid(character_selection_panel):
			character_selection_panel.close()
	if match_menu == null or not is_instance_valid(match_menu):
		return
	if main_menu_visible and match_menu.is_menu_open():
		match_menu.set_menu_open(false)
	if main_menu_visible:
		# 主菜单覆盖牌桌时同步收起聊天窗口与头顶气泡，避免局内浮层残留在主菜单之上。
		if match_chat_panel != null and is_instance_valid(match_chat_panel):
			match_chat_panel.close_panel()
		_dismiss_all_chat_bubbles()
	# 回放重演期间不显示局内菜单与其下方“聊天”按钮；重演只保留覆盖层的速度与退出入口。
	match_menu.visible = not main_menu_visible and not _replay_session_active


## 接收观察者裁剪后的选将快照；候选内容只存在于本地选将组件，不写入桌面状态或玩家快照。
func _on_character_selection_changed(selection_snapshot: Dictionary) -> void:
	character_selection_panel.bind_snapshot(selection_snapshot)


## 接收公共选牌展示快照并立即刷新所有观察者可见窗口；空字典只关闭公共层，不影响其他有效本地请求。
func _on_public_card_choice_display_changed(display_data: Dictionary) -> void:
	_public_card_choice_display = display_data.duplicate()
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
	if _is_inline_hand_choice(choice_data) or _is_inline_control_choice(choice_data):
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
		_inline_card_choice = choice_data.duplicate(true)
		_inline_selected_card_uids.clear()
		_active_response_skill_id = ""
		_selected_target_ids.clear()
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
		_render_local_skills(_get_player_snapshot(match_controller.local_human_player_id))
		_refresh_selection_text()
		_refresh_card_selection_panel()
		return
	_inline_card_choice.clear()
	_inline_selected_card_uids.clear()
	_active_response_skill_id = ""
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
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "confirmed":true}
	if match_controller.submit_action(action):
		if _modal_choice_request_id == request_id:
			_modal_choice_request_id = -1
			_modal_card_choice_request.clear()
			_refresh_card_selection_panel()


## 把牌堆双行排序转换为标准选择动作；UID总顺序和顶行数量都会在权威端再次校验。
func _on_pile_arrangement_submitted(request_id: int, ordered_card_uids: Array[int], top_count: int) -> void:
	# 排序动作；control_id复用稳定选择协议表达顶行数量，避免网络负载携带UI节点或行容器。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {
		"request_id":request_id,
		"selected_card_uids":ordered_card_uids.duplicate(),
		"selected_target_ids":[],
		"selected_control_id":"top_count_%d" % top_count,
		"confirmed":true,
	}
	if match_controller.submit_action(action) and _modal_choice_request_id == request_id:
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
		_refresh_card_selection_panel()


## 将“放弃”转换为空 UID 的标准选择动作；能否放弃仍由当前请求数量约束决定。
func _on_card_choice_cancelled(request_id: int) -> void:
	# 明确取消响应；confirmed=false 与空卡牌数组共同表达放弃，不会被强制选择的最小数量误推断为确认。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_control_id":"", "confirmed":false}
	if match_controller.submit_action(action) and _modal_choice_request_id == request_id:
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
		_refresh_card_selection_panel()


## 武将牌角标按钮被按下；按中性查看类型打开对应的只读界面。
## 桌面只做“查看类型到数据来源”的映射，不解释技能语义，因此新增查看类型不需要改武将牌组件。
func _on_corner_action_pressed(player_id: int, _entry_id: String, view_kind: String) -> void:
	if view_kind == "recorded_card_names":
		_open_recorded_card_names(player_id)
		return


## 打开记录牌名只读窗口；数据取当前观察者裁剪快照中的公开记录字段，任何角色都能查看且只能查看。
## 该窗口不进入规则请求通道，因此打开与关闭都不会产生任何规则动作，权威状态在前后完全一致。
func _open_recorded_card_names(player_id: int) -> void:
	# 目标角色公开快照；缺失时不打开窗口，避免显示一个无主的空面板。
	var player_snapshot: Dictionary = _get_player_snapshot(player_id)
	# 记录牌名列表；空数组按需求不显示按钮，这里再兜底一次，防止出现必然为空的窗口。
	var recorded_card_names: Array = player_snapshot.get("recorded_card_names", []) as Array
	if recorded_card_names.is_empty():
		return
	# 当前角色显示名；用于让观看者确认这是谁的记录，未知时退回通用标题。
	var display_name: String = str(player_snapshot.get("display_name", ""))
	var window_title: String = "记录的牌名" if display_name.is_empty() else "%s 的记录牌名" % display_name
	_recorded_names_view = {
		"title":window_title,
		"prompt":"共记录了 %d 张牌名" % recorded_card_names.size(),
		"card_names":recorded_card_names.duplicate(),
	}
	_refresh_card_selection_panel()
	# 再延迟一帧刷新一次。本方法可能在同一帧的规则请求处理过程中被调用，此时 _modal_card_choice_request
	# 还没被清空，_refresh_card_selection_panel 会让只读窗口为规则请求让位而不显示；而请求在同一帧稍后
	# 结束后通常不会再有状态广播（对局静止时无广播），窗口就会一直不出现，表现为按钮“点了没反应”。
	call_deferred("_refresh_card_selection_panel")


## 只读查看窗口被关闭；清空窗口数据并让面板按当前请求状态重新决定显示内容。
func _on_read_only_view_closed() -> void:
	_recorded_names_view.clear()
	_refresh_card_selection_panel()


## 把文字选项按钮提交转换为标准选择动作；具体费用与后续效果只由创建请求的技能恢复逻辑解释。
func _on_control_choice_submitted(request_id: int, control_id: String) -> void:
	# 统一文字选择动作；不携带牌或目标，避免选项协议与其他选择维度产生歧义。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":control_id, "confirmed":true}
	if match_controller.submit_action(action) and _modal_choice_request_id == request_id:
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
		_refresh_card_selection_panel()


## 根据公共展示与本地独立请求统一决定选择窗口内容；公共展示始终优先保持可见。
func _refresh_card_selection_panel() -> void:
	_refresh_hand_layer_for_public_display()
	if not _public_card_choice_display.is_empty():
		# 本地存在与公共展示不同类型的内联询问时，公共窗口暂时让出手牌与按钮输入，询问结束后会从保留快照自动恢复。
		if not _inline_card_choice.is_empty() and str((_inline_card_choice.get("context", {}) as Dictionary).get("kind", "")) != str(_public_card_choice_display.get("kind", "")):
			card_selection_panel.close()
			return
		# 本地存在与公共展示不同类型的独立请求时优先显示该请求，公共牌位数据仍保留在桌面快照中。
		if not _modal_card_choice_request.is_empty() and str((_modal_card_choice_request.get("context", {}) as Dictionary).get("kind", "")) != str(_public_card_choice_display.get("kind", "")):
			card_selection_panel.show_request(_enrich_target_zone_card_choice_request(_modal_card_choice_request))
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
		card_selection_panel.show_request(_enrich_target_zone_card_choice_request(_modal_card_choice_request))
		return
	# 无任何规则请求时显示记录牌名只读窗口；它不属于请求，因此不参与上面的优先级比较。
	# 一旦出现规则请求，上面的分支会接管窗口，避免只读窗口挡住玩家必须完成的选择。
	if not _recorded_names_view.is_empty():
		card_selection_panel.show_recorded_names(_recorded_names_view)
		return
	card_selection_panel.close()


## 判断一条本地窗口请求是否仍由权威端等待；联机快照优先读取本人待办清单，缺失该字段时回落到单槽位请求编号。
## 并行无懈会同时为多名玩家登记请求，单槽位 current_choice_request 只能承载其中一条；
## 若始终用该槽位判定，其他玩家请求到达时会把本地仍在等待的无懈窗口误清并永久停在询问阶段。
func _is_local_request_still_pending(request_id: int, fallback_request_id: int) -> bool:
	if request_id < 0:
		return false
	if _has_local_pending_choice_request_ids:
		return _local_pending_choice_request_ids.has(request_id)
	return request_id == fallback_request_id


## 为实际“选择角色区域内的牌”请求补充公开目标武将名；文字控制请求即使携带只读牌面也只负责观看，不能被改写为选牌提示。
func _enrich_target_zone_card_choice_request(choice_request: Dictionary) -> Dictionary:
	var result: Dictionary = choice_request.duplicate(true)
	# 当前选择维度；只有会提交实体牌UID的请求才适用“请选择某角色区域内的牌”文案。
	# 【勘测】等control/bool请求携带的display_candidates只供私下观看，必须保留其后续效果的原始提示。
	var choice_type: String = str(result.get("choice_type", "card"))
	if choice_type in ["control", "bool", "target_control"]:
		return result
	# 只有固定数量的目标区域选择才改写提示；可变数量费用和普通手牌选择继续保留规则端原文。
	var required_count: int = int(result.get("min_select", 0))
	if required_count <= 0 or int(result.get("max_select", 0)) != required_count:
		return result
	var context: Dictionary = result.get("context", {}) as Dictionary
	# 目标角色稳定ID；通用牌和技能使用target_id，机缘逐目标流程使用target_player_id，二者都只作为展示定位。
	var target_id: int = int(context.get("target_id", context.get("target_player_id", -1)))
	if target_id < 0:
		return result
	# 用于展示的候选；不可弃置的保护牌也可能在该数组中，仍然属于“目标角色区域”的提示语义。
	var display_candidates: Array = context.get("display_candidates", result.get("candidates", [])) as Array
	var has_target_zone_candidate: bool = false
	for candidate_variant: Variant in display_candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		var candidate_zone: String = str(candidate.get("zone", ""))
		if int(candidate.get("owner_id", -1)) == target_id and candidate_zone in ["hand", "equipment", "judgment"]:
			has_target_zone_candidate = true
			break
	if not has_target_zone_candidate:
		return result
	# 目标公开快照；已亮将时使用武将名，未亮将时安全回退公开玩家显示名。
	var target_snapshot: Dictionary = _get_player_snapshot(target_id)
	var target_name: String = _snapshot_character_name(target_snapshot, str(target_snapshot.get("display_name", "角色")))
	if target_name.is_empty():
		return result
	# 目标区域固定数量文案；一张使用中文量词，其余数量沿用阿拉伯数字以便玩家快速确认费用。
	var count_text: String = "一张" if required_count == 1 else "%d张" % required_count
	result["prompt"] = "请选择“%s”区域内的%s牌" % [target_name, count_text]
	result["prompt_highlight"] = target_name
	return result


## 保持本地手牌处于牌桌基础层级；五谷丰登等模态选择窗口必须完整覆盖手牌和悬停放大牌面。
func _refresh_hand_layer_for_public_display() -> void:
	if hand_panel == null or not is_instance_valid(hand_panel):
		return
	hand_panel.z_index = 0
	_layout_auto_managed_hand_overlay()


## 按当前网络权威身份刷新局内菜单；离线玩家与房主保留权威设置，局域网客户端只显示本地可生效选项。
func _refresh_match_menu_authority_controls() -> void:
	if match_menu == null or not is_instance_valid(match_menu) or match_controller == null or match_controller.network_gateway == null:
		return
	match_menu.set_authority_controls_visible(not match_controller.network_gateway.is_lan_client())
	# 控制全部角色只属于纯离线对局；局域网房主虽然拥有其他权威设置，也必须隐藏该项。
	var is_offline_mode: bool = match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE
	match_menu.set_offline_controls_visible(is_offline_mode)
	if main_menu != null and is_instance_valid(main_menu):
		main_menu.set_control_all_characters_visible(is_offline_mode)
	# 只有标准身份局需要推测隐藏身份；斗地主、2v2与车轮战身份全明置时隐藏该开关。
	var current_match_mode: String = str(_snapshot.get("match_mode", GameSettings.next_match_mode if GameSettings != null else "identity"))
	match_menu.set_auto_identity_marking_visible(current_match_mode == "identity")


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
	# 文字控制项需要显示独立选项按钮，空候选不能误判为可在手牌区完成。
	# 牌名候选同样没有实体手牌：它的 candidates 为空数组，若不排除，下方循环因“没有任何候选违反条件”
	# 而直接返回 true，请求会被误判为内联，独立窗口不显示，表现为点击技能后毫无反应。
	# 牌堆位次询问（card_position）同样不属于「纯手牌选择」：它还要在操作区显示三个位次按钮，
	# 因此这里保持排除，由 _is_inline_control_choice 接管；它照样会在手牌区里选牌，但按钮来自文字选项维度。
	if str(choice_data.get("choice_type", "card")) in ["control", "bool", "target_control", "card_name", "card_position"]:
		return false
	# 请求选择者 ID；所有候选必须属于该玩家，不能把他人区域牌错误放入本地手牌交互。
	var chooser_id: int = int(choice_data.get("chooser_id", -1))
	for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
		# 当前候选快照；区域与所有者共同决定其是否已经显示在本地手牌或装备组件中。
		var candidate: Dictionary = candidate_variant as Dictionary
		# 虚拟手牌候选同样显示在手牌区（由 _render_virtual_hand_choice 接管该区域），因此与手牌同级参与内联判定。
		if int(candidate.get("owner_id", -1)) != chooser_id or str(candidate.get("zone", "")) not in ["hand", "wooden_ox", "equipment", "virtual_hand"]:
			return false
	return true


## 判断请求是否为【振旗】的费用选择；该控制项需要直接复用桌面原有操作按钮区，而不是打开独立遮罩窗口。
func _is_inline_zhenqi_cost_choice(choice_data: Dictionary) -> bool:
	if str(choice_data.get("choice_type", "card")) not in ["control", "bool"]:
		return false
	# 技能上下文；稳定 kind 由【振旗】源码写入，避免界面按标题中文或选项数量猜测规则。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	return str(context.get("kind", "")) == "zhenqi_cost_option"


## 判断文字互斥选项是否应复用手牌上方操作区；所有技能控制询问统一使用此入口，不再创建额外遮罩窗口。
## 牌堆位次询问（card_position）也走本入口：它的手牌维度由内联手牌区承担，文字选项维度就是三个位次按钮，
## 因此与【咬它】等组合询问保持完全相同的交互形态——手牌区选牌、操作区点询问按钮，不再弹出独立窗口。
func _is_inline_control_choice(choice_data: Dictionary) -> bool:
	# 当前选择类型；control 与 bool 都由稳定选项数组表达，其他选择仍按牌区或独立窗口规则处理。
	var choice_type: String = str(choice_data.get("choice_type", "card"))
	# 需要同时展示私有牌面的控制请求使用独立窗口，避免手牌上方操作区遮住被观看内容。
	var display_candidates: Array = ((choice_data.get("context", {}) as Dictionary).get("display_candidates", []) as Array)
	# 牌名候选需要以牌面形式呈现，同样必须使用独立窗口而不是手牌上方操作区。
	var card_name_candidates: Array = ((choice_data.get("context", {}) as Dictionary).get("card_name_candidates", []) as Array)
	return choice_type in ["control", "bool", "target_control", CARD_POSITION_CHOICE_TYPE] and display_candidates.is_empty() and card_name_candidates.is_empty()


## 返回当前内联请求允许选择的实体 UID；空请求返回空数组，使全部手牌与装备保持不可选并仅允许取消。
func _get_inline_candidate_uids() -> Array[int]:
	# 候选 UID 集合；保持规则请求顺序并防御性去重。
	var result: Array[int] = []
	for candidate_variant: Variant in _inline_card_choice.get("candidates", []) as Array:
		# 当前候选 UID；无效负数不会进入可交互集合。
		var candidate: Dictionary = candidate_variant as Dictionary
		# 当前候选 UID；稳定实体标识用于牌面交互和权威提交。
		var candidate_uid: int = int(candidate.get("uid", -1))
		# 候选要求的响应技能；未点击该技能时保持暗置，普通实体响应牌始终开放。
		var required_response_skill_id: String = str(candidate.get("required_response_skill_id", ""))
		var response_skill_ready: bool = required_response_skill_id.is_empty() or required_response_skill_id == _active_response_skill_id
		if candidate_uid >= 0 and response_skill_ready and not result.has(candidate_uid) and (_inline_selected_card_uids.has(candidate_uid) or _is_inline_candidate_compatible(candidate_uid)):
			result.append(candidate_uid)
	return result


## 判断一张内联候选追加到当前选择后是否仍能组成权威声明的合法完整组合。
func _is_inline_candidate_compatible(candidate_uid: int) -> bool:
	# 最大选择数；达到上限后未选候选全部不可继续选择。
	var max_select: int = int(_inline_card_choice.get("max_card_select", _inline_card_choice.get("max_select", 0)))
	if _inline_selected_card_uids.size() >= max_select:
		return false
	# 选择上下文；组合约束由技能源码预先计算，界面只判断选择前缀。
	var context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
	# 完整合法组合；空数组表示所有基础候选可自由组合。
	var valid_card_combinations: Array = context.get("valid_card_combinations", []) as Array
	if valid_card_combinations.is_empty():
		return true
	# 待验证选择前缀；新候选只在至少一条完整组合中与全部已选牌共同出现时可用。
	var tentative_selection: Array[int] = _inline_selected_card_uids.duplicate()
	tentative_selection.append(candidate_uid)
	for combination_variant: Variant in valid_card_combinations:
		# 当前完整合法组合；元素转换为整数UID后进行成员匹配。
		var combination: Array[int] = []
		for card_uid_variant: Variant in combination_variant as Array:
			combination.append(int(card_uid_variant))
		# 当前组合是否包含全部选择前缀；成员顺序不影响寒鸦等组合规则。
		var contains_all_selected: bool = true
		for selected_uid: int in tentative_selection:
			if not combination.has(selected_uid):
				contains_all_selected = false
				break
		if contains_all_selected:
			return true
	return false


## 返回可自动选中的装备触发UID；兼容普通装备触发equipment_uid与八卦阵优先响应immediate_response_equipment_uid。
func _get_auto_selected_equipment_trigger_uid(choice_data: Dictionary) -> int:
	# 触发上下文；装备规则必须写入明确UID，客户端不能仅凭“唯一候选”推断发动语义。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	# 请求绑定的装备实体UID；八卦阵独立询问使用immediate_response_equipment_uid，其他装备触发使用equipment_uid。
	var equipment_uid: int = int(context.get("equipment_uid", context.get("immediate_response_equipment_uid", -1)))
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
		var equipment_definition: Dictionary = _get_cached_card_definition(str(equipment_card.get("definition_id", "")))
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
		var max_select: int = int(_inline_card_choice.get("max_card_select", _inline_card_choice.get("max_select", 0)))
		if max_select == 1:
			_inline_selected_card_uids.clear()
		if _inline_selected_card_uids.size() < max_select:
			_inline_selected_card_uids.append(card_uid)
	# 组合技能切换材料牌后重新校验目标；旧目标不在新映射中时立即清除临时选择。
	if str(_inline_card_choice.get("choice_type", "card")) == "card_target":
		# 当前请求上下文；材料目标映射和自动目标映射都只读取这份可序列化规则数据。
		var inline_context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
		# 当前材料牌对应的合法目标；切换材料后用于清理已经失效的旧目标。
		var legal_target_ids: Array[int] = _get_selectable_target_ids()
		for selected_target_id: int in _selected_target_ids.duplicate():
			if not legal_target_ids.has(selected_target_id):
				_selected_target_ids.erase(selected_target_id)
		# 自身目标虚拟牌由规则上下文预填唯一合法目标；必须在旧目标清理后写入，避免“下一目标为空”误删已经完整的自身组合。
		if _inline_selected_card_uids.size() == 1:
			# 材料UID到唯一自动目标数组的映射；字符串键兼容网络快照JSON化后的字典结构。
			var auto_target_ids_by_card_id: Dictionary = inline_context.get("auto_target_ids_by_card_id", {}) as Dictionary
			# 当前唯一选中材料UID；多选请求不会进入该自动预填分支。
			var selected_material_uid: int = _inline_selected_card_uids[0]
			# 当前材料的规则自动目标；未声明时保留玩家手动选择流程。
			var auto_target_ids: Array = auto_target_ids_by_card_id.get(str(selected_material_uid), auto_target_ids_by_card_id.get(selected_material_uid, [])) as Array
			if not auto_target_ids.is_empty():
				_selected_target_ids.clear()
				for auto_target_id_variant: Variant in auto_target_ids:
					_selected_target_ids.append(int(auto_target_id_variant))
	error_label.text = ""
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


## 提交手牌区内联选择；只有当前请求仍与提交 ID 相同时才清理，避免覆盖同步创建的下一请求。
func _submit_inline_card_choice(selected_card_uids: Array[int], confirmed: bool = true) -> void:
	if _inline_card_choice.is_empty():
		return
	# 本次提交请求 ID；控制器恢复过程中可能同步发出下一条请求，因此必须保留独立副本。
	var request_id: int = int(_inline_card_choice.get("request_id", -1))
	# 统一选择动作；只提交请求号与实体 UID，不直接修改手牌、处理区或阶段。
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids.duplicate(), "selected_target_ids":_selected_target_ids.duplicate() if confirmed else [], "confirmed":confirmed}
	if confirmed and selected_card_uids.size() == 1 and not _active_response_skill_id.is_empty():
		for candidate_variant: Variant in _inline_card_choice.get("candidates", []) as Array:
			# 当前已选候选；只有其明确要求当前技能时才提交转化技能ID，普通实体【杀】仍按自身响应。
			var candidate: Dictionary = candidate_variant as Dictionary
			if int(candidate.get("uid", -1)) == selected_card_uids[0] and str(candidate.get("required_response_skill_id", "")) == _active_response_skill_id:
				action.payload["response_skill_id"] = _active_response_skill_id
				break
	if not match_controller.submit_action(action):
		return
	if int(_inline_card_choice.get("request_id", -2)) == request_id:
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
		_active_response_skill_id = ""
		_selected_target_ids.clear()
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


## 把选将界面的稳定武将 ID 封装为标准动作，并交由权威控制器再次校验。
func _on_character_selected(character_id: String) -> void:
	# 选将动作；payload 只存放可序列化武将 ID，支持网络、回放和 AI 共用。
	var action: PlayerAction = PlayerAction.new("select_character", match_controller.local_human_player_id)
	action.payload = {"character_id":character_id}
	match_controller.submit_action(action)


## 把选将面板提交的完整武将、座次、身份或 AI 调整数据转换为对应标准动作。
func _on_character_selection_submitted(selection_data: Dictionary) -> void:
	# 当前选将用途；AI 调整与初次选将使用不同权威动作，不能只凭目标 ID 猜测。
	var selection_kind: String = str(selection_data.get("selection_kind", "initial"))
	if selection_kind == "wheel_duel":
		if not (selection_data.get("character_ids", []) as Array).is_empty():
			var lineup_action: PlayerAction = PlayerAction.new("wheel_duel_submit_lineup", match_controller.local_human_player_id)
			lineup_action.payload = {"character_ids":(selection_data.get("character_ids", []) as Array).duplicate()}
			match_controller.submit_action(lineup_action)
		else:
			var pick_action: PlayerAction = PlayerAction.new("wheel_duel_pick", match_controller.local_human_player_id)
			pick_action.payload = {"slot_id":int(selection_data.get("slot_id", -1))}
			match_controller.submit_action(pick_action)
		return
	if selection_kind == "ai_adjustment":
		# 房主调整 AI 武将动作；目标与武将 ID 均由当前私有选将快照产生。
		var adjustment_action: PlayerAction = PlayerAction.new("set_ai_character", match_controller.local_human_player_id)
		adjustment_action.payload = {
			"target_player_id":int(selection_data.get("target_player_id", -1)),
			"character_id":str(selection_data.get("character_id", "")),
		}
		match_controller.submit_action(adjustment_action)
		return
	# 初次选将动作；普通模式的座次和身份保持无效默认值，自选模式由核心服务复核联动与剩余名额。
	var action: PlayerAction = PlayerAction.new("select_character", match_controller.local_human_player_id)
	action.payload = {
		"character_id":str(selection_data.get("character_id", "")),
		"seat_number":int(selection_data.get("seat_number", -1)),
		"identity":str(selection_data.get("identity", "")),
	}
	match_controller.submit_action(action)


## 把选将面板的单张换将请求封装为标准动作；房主权威服务会再次校验候选、锁定状态与剩余次数。
func _on_character_candidate_replacement_requested(character_id: String) -> void:
	# 换将动作；只携带本人当前候选的稳定武将 ID，不传递按钮、牌面节点或随机结果。
	var action: PlayerAction = PlayerAction.new("replace_character_candidate", match_controller.local_human_player_id)
	action.payload = {"character_id":character_id}
	match_controller.submit_action(action)


## 把座次身份按钮的即时改动封装为预览动作；控制器在不确认武将的前提下刷新全部角色与 AI 展示。
func _on_custom_assignment_preview_requested(seat_number: int, identity: String) -> void:
	# 自选预览动作；只携带已经由界面完成领袖联动的稳定座次与身份，不传递按钮或候选节点。
	var action: PlayerAction = PlayerAction.new("preview_custom_assignment", match_controller.local_human_player_id)
	action.payload = {"seat_number":seat_number, "identity":identity}
	match_controller.submit_action(action)


## 追加一条规则日志并自动滚动到底部。
## 折叠状态由日志组件只保存字符串历史；只有展开状态会在帧末批量追加并滚动正文。
func _on_log_added(message: String) -> void:
	match_log_panel.append_entry(message)
	# 日志与快照共同构成回放步骤流；录制器未激活时该调用为空操作。
	_match_replay_recorder.record_log(message)


## 在实际发动者的武将牌中心短暂显示技能名；提示与目标线只订阅控制器信号，不持有技能对象或改写对局状态。
## 发动提示与已确认目标同时进入回放录制，重演时按同一入口恢复名称提示与目标指示线。
func _on_skill_activated(player_id: int, skill_name: String, context: Dictionary) -> void:
	_record_replay_presentation({"e":"activation", "player_id":player_id, "name":skill_name, "target_ids":_get_skill_activation_target_ids(context)})
	_show_character_card_activation(player_id, skill_name, context)


## 在防具实际生效时复用武将牌中央提示显示防具名；防具没有目标线，且不会被写入技能发动历史。
## 防具提示同样进入回放录制，使重演画面与录制端当时所见保持一致。
func _on_equipment_activated(player_id: int, equipment_name: String, context: Dictionary) -> void:
	_record_replay_presentation({"e":"activation", "player_id":player_id, "name":equipment_name, "target_ids":_get_skill_activation_target_ids(context)})
	_show_character_card_activation(player_id, equipment_name, context)


## 在指定角色的武将牌中心短暂显示一条已确认的技能或防具名称；调用方只提供表现数据，不允许通过本函数修改规则状态。
func _show_character_card_activation(player_id: int, activation_name: String, context: Dictionary) -> void:
	# 当前发动者武将牌全局矩形；本地与其他玩家使用各自持久组件，未知或刚离场角色不创建错误的中央提示。
	var player_card_rect: Rect2 = Rect2()
	if player_id == match_controller.local_human_player_id:
		if local_player_card == null or not is_instance_valid(local_player_card):
			return
		player_card_rect = local_player_card.get_global_rect()
	else:
		# 当前对手武将牌；只从本次桌面已渲染的稳定玩家索引读取，避免等待快照时访问已释放节点。
		var player_view: PlayerTargetView = _player_views.get(player_id) as PlayerTargetView
		if player_view == null or not is_instance_valid(player_view):
			return
		player_card_rect = player_view.get_global_rect()
	_play_skill_activation_target_indicator(player_id, context)
	# 牌桌根节点局部坐标；完整逆变换兼容画布缩放与后续窗口适配，不假设全局坐标恒等于场景坐标。
	var root_inverse_transform: Transform2D = get_global_transform().affine_inverse()
	# 武将牌左上角的本地坐标；文本标签作为牌桌根节点子项，必须先转换坐标系。
	var label_top_left: Vector2 = root_inverse_transform * player_card_rect.position
	# 武将牌右下角的本地坐标；和左上角相减后得到随缩放保持正确的提示尺寸。
	var label_bottom_right: Vector2 = root_inverse_transform * player_card_rect.end
	# 实际技能提示文本节点；独立节点可让多个角色连续发动时各自淡出，而不会互相覆盖或取消。
	var activation_label: Label = Label.new()
	activation_label.name = "SkillActivation_%d" % player_id
	activation_label.position = label_top_left
	activation_label.size = label_bottom_right - label_top_left
	activation_label.z_index = SKILL_ACTIVATION_Z_INDEX
	activation_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activation_label.text = "【%s】" % activation_name
	activation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	activation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	activation_label.add_theme_font_size_override("font_size", SKILL_ACTIVATION_FONT_SIZE)
	activation_label.add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
	activation_label.add_theme_color_override("font_outline_color", Color.BLACK)
	activation_label.add_theme_constant_override("outline_size", SKILL_ACTIVATION_OUTLINE_SIZE)
	add_child(activation_label)
	# 当前提示淡出补间；只操作本次新建节点，完成后立即释放以免在长局中积累不可见标签。
	var activation_tween: Tween = create_tween()
	activation_tween.tween_interval(SKILL_ACTIVATION_HOLD_SECONDS)
	activation_tween.tween_property(activation_label, "modulate:a", 0.0, SKILL_ACTIVATION_FADE_SECONDS)
	activation_tween.tween_callback(activation_label.queue_free)


## 在技能独立请求目标指示器时播放一次性指向线；请求可以被技能在任意时机发出，因此本入口不收拢任何状态。
func _on_skill_target_indicated(source_player_id: int, target_player_ids: Array[int]) -> void:
	_play_target_indicator_line(source_player_id, target_player_ids)


## 从来源角色锚点向给定目标逐个取锚点并播放技能指示线；与技能发动提示共用同一绘制入口与样式参数。
## 锚点缺失的角色只跳过自己那条线段，其余目标仍正常显示，避免座位尚未建立时整条指示线消失。
func _play_target_indicator_line(source_player_id: int, target_player_ids: Array[int]) -> void:
	if card_use_animation_layer == null:
		return
	# 来源锚点；缺失时不回退到桌面中央，避免为技能伪造来源方向。
	var source_anchor_result: Dictionary = _try_get_player_indicator_position(source_player_id)
	if not bool(source_anchor_result.get("valid", false)):
		return
	# 目标锚点集合；保持请求顺序，使多目标指示线的绘制次序稳定可复现。
	var target_positions: Array[Vector2] = []
	for target_id: int in target_player_ids:
		# 当前目标锚点；目标刚离场或座位尚未建立时跳过对应线段。
		var target_anchor_result: Dictionary = _try_get_player_indicator_position(target_id)
		if bool(target_anchor_result.get("valid", false)):
			target_positions.append(target_anchor_result.get("position", Vector2.ZERO) as Vector2)
	if not target_positions.is_empty():
		card_use_animation_layer.play_skill_target_indicator(source_anchor_result.get("position", Vector2.ZERO) as Vector2, target_positions)


## 在技能实际发动时播放已确认目标的动态指示线；选择阶段只保留目标描边，避免把尚未确认的候选误表现为已发动。
func _play_skill_activation_target_indicator(activator_player_id: int, context: Dictionary) -> void:
	# 已确认技能目标；只读取发动记录上下文，不能从当前候选或仍可点击的武将牌反推。
	_play_target_indicator_line(activator_player_id, _get_skill_activation_target_ids(context))


## 从技能实际发动上下文提取稳定目标 ID；优先使用通用target_id/target_ids，并兼容现有支援技能的受益者字段。
func _get_skill_activation_target_ids(context: Dictionary) -> Array[int]:
	# 已确认目标结果；按技能声明顺序去重，保持多目标指示线的确定绘制顺序。
	var result: Array[int] = []
	for target_id_variant: Variant in context.get("target_ids", []) as Array:
		# 当前多目标成员；负数和重复ID不构成可绘制角色目标。
		var target_id: int = int(target_id_variant)
		if target_id >= 0 and not result.has(target_id):
			result.append(target_id)
	# 常规单目标字段；绝大多数单目标技能在announce_activation时写入该键。
	var single_target_id: int = int(context.get("target_id", -1))
	if single_target_id >= 0 and not result.has(single_target_id):
		result.append(single_target_id)
	# 已有跨角色支援技能的受益者字段；无通用目标字段时仍可复用同一动态线，而不要求重写既有结算上下文。
	if result.is_empty():
		for fallback_key: String in ["recipient_id", "slash_user_id"]:
			var fallback_target_id: int = int(context.get(fallback_key, -1))
			if fallback_target_id >= 0 and not result.has(fallback_target_id):
				result.append(fallback_target_id)
	return result


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
	var definition: Dictionary = _get_cached_card_definition(str(card_data.get("definition_id", "")))
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
	# 分阶段目标线局部坐标；借刀杀人等牌按规则给出的来源与目标顺序逐段解析。
	var indicator_stages: Array[Dictionary] = []
	for indicator_stage_variant: Variant in presentation_data.get("indicator_stages", []) as Array:
		# 当前规则阶段；只包含稳定玩家ID，不包含界面节点引用。
		var indicator_stage: Dictionary = indicator_stage_variant as Dictionary
		# 当前阶段来源锚点；缺失来源时整段省略，不能从中央伪造玩家位置。
		var stage_source_result: Dictionary = _try_get_player_indicator_position(int(indicator_stage.get("actor_id", -1)))
		if not bool(stage_source_result.get("valid", false)):
			continue
		# 当前阶段目标锚点数组；个别离场目标只省略自身线段。
		var stage_target_positions: Array[Vector2] = []
		for stage_target_variant: Variant in indicator_stage.get("target_ids", []) as Array:
			# 当前阶段目标锚点；使用稳定玩家ID查询最新桌面位置。
			var stage_target_result: Dictionary = _try_get_player_indicator_position(int(stage_target_variant))
			if bool(stage_target_result.get("valid", false)):
				stage_target_positions.append(stage_target_result.get("position", Vector2.ZERO) as Vector2)
		if not stage_target_positions.is_empty():
			indicator_stages.append({"start_position":stage_source_result.get("position", Vector2.ZERO) as Vector2, "target_positions":stage_target_positions})
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
	# 卡牌表现重演步骤；去重通过后录制完整表现数据（牌面快照、来源、目标与规则阶段均为纯数据），
	# 重演端把同一份数据送回本入口，中央飞牌、展示队列与目标指示线按原表现流程完整复刻。
	_record_replay_presentation({"e":"card_presentation", "data":presentation_data.duplicate(true)})
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
		# 展示副本的牌面起点；本机手牌或装备区的牌被展示时取该牌真实所在位置，因此不会从手牌区中心凭空出现。
		animated_card.position = _resolve_presentation_card_position(card_uid, actor_id, str(presentation_data.get("source_zone", card_data.get("zone", ""))), start_position) - animated_card.get_card_size() * 0.5
	card_use_animation_layer.play_card(animated_card, start_position, discard_position, target_positions, owns_discard_transfer, indicator_stages)


## 登记一次权威摸牌调用的表现批次；批次内卡牌先由普通转移信号逐张填充，完成信号到达后才一起交给动画层。
## 批次边界进入回放录制，重演端按同一开始/填充/完成节拍复刻同批居中并行的摸牌动画。
func _on_draw_presentation_batch_started(batch_id: int, player_id: int) -> void:
	if batch_id < 0:
		return
	_record_replay_presentation({"e":"draw_batch_started", "batch_id":batch_id, "player_id":player_id})
	# 当前批次初始数据；卡牌数组按 CardMovementService 信号顺序追加，顺序就是牌堆实际摸取顺序。
	_draw_presentation_batches[batch_id] = {"player_id":player_id, "cards":[]}


## 将已收齐的同一次摸牌交给动画层；动画层负责同批居中、并行飞行，多个玩家或连续摸牌批次均立即开始，桌面不自行等待计时器。
func _on_draw_presentation_batch_finished(batch_id: int, player_id: int) -> void:
	_record_replay_presentation({"e":"draw_batch_finished", "batch_id":batch_id, "player_id":player_id})
	# 当前批次数据；信号可能在重开清理后迟到，缺失批次安全忽略且不回退到逐张动画。
	var draw_batch: Dictionary = _draw_presentation_batches.get(batch_id, {}) as Dictionary
	_draw_presentation_batches.erase(batch_id)
	if draw_batch.is_empty() or int(draw_batch.get("player_id", -1)) != player_id:
		return
	# 当前批次牌面数据；牌堆耗尽时允许空批次正常结束，不创建无内容动画任务。
	var drawn_card_data: Array = draw_batch.get("cards", []) as Array
	if drawn_card_data.is_empty():
		return
	# 手牌目标锚点；本地玩家使用手牌区顶边中心，其他玩家使用武将牌中心，缺失座位不伪造动画落点。
	var target_anchor_result: Dictionary = _try_get_player_indicator_position(player_id)
	if not bool(target_anchor_result.get("valid", false)):
		return
	# 牌堆起点；与普通摸牌一致使用中央公共锚点，所有同批牌面从同一位置同时开始飞行。
	var draw_start_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	# 本批整体中心；动画层以此中心对称铺开多张牌，单张时保持原有的目标锚点。
	var draw_target_position: Vector2 = target_anchor_result.get("position", Vector2.ZERO) as Vector2
	# 当前批次是否属于本机玩家；本机批次的牌背要飞向各自最终槽位，必须先等快照布局算出槽位再起飞。
	var is_local_draw_batch: bool = player_id == match_controller.local_human_player_id
	# 当前批次的正式牌面节点；本机批次直接显示正面，其他观察者不可见私有手牌、只显示同款牌背并由权威快照决定实际手牌显示。
	var draw_card_views: Array[CardView] = []
	# 本批属于本机玩家的摸牌实体 UID；用于在牌面落地后再让正式手牌节点出现在各自槽位。
	var drawn_local_card_uids: Array = []
	for card_data_variant: Variant in drawn_card_data:
		# 当前摸到实体的瞬时牌面副本；本机批次读取正面配置，其他观察者只读取 UID 配置牌背，不泄露私有牌面。
		var card_data: Dictionary = card_data_variant as Dictionary
		# 当前摸到实体的稳定 UID；本机摸牌需要按该 UID 登记手牌飞行与门闸。
		var drawn_card_uid: int = int(card_data.get("uid", -1))
		var draw_card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		draw_card_view.visible = false
		if is_local_draw_batch:
			# 本机摸到的牌落地后一定会正面显示在自己的手牌区，因此飞行途中直接使用正面，避免落地瞬间翻面。
			draw_card_view.configure(card_data, _get_cached_card_definition(str(card_data.get("definition_id", ""))), false, false)
		else:
			# 其他观察者看不清本批具体牌面，只按 UID 配置统一牌背。
			draw_card_view.configure_back(drawn_card_uid, false)
		draw_card_views.append(draw_card_view)
		if is_local_draw_batch:
			drawn_local_card_uids.append(drawn_card_uid)
			# 本机摸牌的手牌飞行登记；批次完成信号早于权威快照，因此这里只登记门闸与飞行起点，
			# 真正的起飞由 _start_pending_local_hand_gain_flights 在快照布局之后完成，终点是每张牌自己的槽位。
			# 门闸值保存本张牌面，使保持阶段能在牌面异常消失时自愈解闸。
			if drawn_card_uid >= 0:
				_local_hand_gain_flight_gates[drawn_card_uid] = {"card":draw_card_view, "origin":draw_start_position, "started":false, "batch":batch_id, "snapshot_generation":_local_hand_snapshot_generation}
	if is_local_draw_batch:
		# 本机摸牌批次延后起飞；同批成员共用同一个牌堆起点，落点在快照到达后逐张解析。
		_pending_local_draw_batches[batch_id] = {"views_by_uid":_build_card_view_uid_lookup(draw_card_views, drawn_local_card_uids), "origin":draw_start_position}
		_start_pending_local_hand_gain_flights()
		return
	card_use_animation_layer.play_draw_transfer_batch(draw_card_views, draw_start_position, draw_target_position, _release_local_hand_gain_flight_gates.bind(drawn_local_card_uids))


## 按本批摸牌顺序把牌面节点与其实体 UID 配对；待起飞批次据此在快照到达后逐张解析最终落点。
## 无效 UID 或已释放节点不进入结果，保证待起飞成员始终可以被安全地起飞或释放。
func _build_card_view_uid_lookup(card_views: Array[CardView], card_uids: Array) -> Dictionary:
	# 实体 UID 到牌面节点的映射；键值顺序同时保留了牌堆摸取顺序。
	var view_lookup: Dictionary = {}
	for card_index: int in range(mini(card_views.size(), card_uids.size())):
		# 当前成员 UID；无效 UID 不登记，避免待起飞批次里出现无法解闸的成员。
		var card_uid: int = int(card_uids[card_index])
		if card_uid < 0:
			continue
		view_lookup[card_uid] = card_views[card_index]
	return view_lookup


## 接收统一牌区移动事件；摸牌、获得、响应和展示牌弃置都从实际来源锚点移动。
## 完整入参在任何早退分支前进入回放录制；重演端以同一入口重跑同样的批次填充、去重与锚点判定。
func _on_card_transfer_requested(card_data: Dictionary, source_player_id: int, source_zone: String, target_player_id: int, target_zone: String) -> void:
	_record_replay_presentation({"e":"card_transfer", "card_data":card_data.duplicate(true), "source_player_id":source_player_id, "source_zone":source_zone, "target_player_id":target_player_id, "target_zone":target_zone})
	# 同一张使用牌已经由完整出牌动画接管时，不再创建第二张转移牌，避免瞬间出现在目标武将牌上。
	var card_uid: int = int(card_data.get("uid", -1))
	# 当前摸牌表现批次；批次开始信号已先建立容器，只有带此标记的牌堆到手牌移动会延后到完成信号统一播放。
	var draw_batch_id: int = int(card_data.get(MatchController.DRAW_PRESENTATION_BATCH_ID_KEY, -1))
	if draw_batch_id >= 0 and _draw_presentation_batches.has(draw_batch_id):
		# 当前批次可写副本；仅保存瞬时序列化牌面，规则状态、手牌节点与区域所有权仍由正常快照处理。
		var draw_batch: Dictionary = _draw_presentation_batches.get(draw_batch_id, {}) as Dictionary
		var drawn_cards: Array = draw_batch.get("cards", []) as Array
		drawn_cards.append(card_data.duplicate(true))
		draw_batch["cards"] = drawn_cards
		_draw_presentation_batches[draw_batch_id] = draw_batch
		return
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
		# 离场来源；本机手牌与装备区直接取该牌真实所在位置，其他来源沿用玩家武将牌或中央公共锚点。
		var discard_origin_result: Dictionary = _try_take_card_origin(card_uid, source_player_id, source_zone)
		if not bool(discard_origin_result.get("valid", false)):
			return
		# 弃置飞行起点；命中本机正式手牌时等于该牌当前槽位中心，因此接管后不会出现位置跳变。
		var discard_start_position: Vector2 = discard_origin_result.get("position", Vector2.ZERO) as Vector2
		# 中央弃牌落点；所有离场牌最终都收敛到队列中的同一片区域。
		var discard_target_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
		# 可接管的正式手牌节点；存在时直接交给动画层，弃置表现从牌面原位置连续开始而不是先消失再从锚点生成。
		var discarded_card: CardView = discard_origin_result.get("card_view") as CardView
		# 被接管的正式手牌节点立即退出手牌映射，之后它的生命周期完全由动画层负责。
		_forget_taken_over_hand_card(card_uid, discarded_card)
		if discarded_card == null:
			# 新建表现牌；装备区、其他角色与公共区域的牌没有可接管的正式手牌节点，必须按来源矩形单独创建。
			discarded_card = CARD_VIEW_SCENE.instantiate() as CardView
			discarded_card.visible = false
			if _should_show_card_back(source_player_id, source_zone, target_player_id, target_zone):
				discarded_card.configure_back(card_uid, false)
			else:
				var discarded_definition: Dictionary = _get_cached_card_definition(str(card_data.get("definition_id", "")))
				discarded_card.configure(card_data, discarded_definition, false, false)
			card_use_animation_layer.add_child(discarded_card)
			discarded_card.position = discard_start_position - discarded_card.get_card_size() * 0.5
		# 弃置牌与展示手牌共用中央完整牌面队列；同一帧的多张牌按信号顺序一次性展示并成批淡出。
		card_use_animation_layer.play_card(discarded_card, discard_start_position, discard_target_position, [])
		return
	if target_zone != "discard_pile":
		# 实体已经进入新的规则区域；上一轮弃牌移动的待消费与已消费所有权到此失效，未来普通弃置或再次使用可重新播放。
		card_use_animation_layer.release_consumed_discard_claim(card_uid)
	# 本地摸牌与其他获得都使用手牌容器中的正式实体视图；先登记飞行起点与门闸，
	# 收到包含该牌的快照、算出该牌自己的最终槽位之后才真正起飞，使牌从真实来源直接飞向它的槽位。
	var is_local_gain: bool = target_player_id == match_controller.local_human_player_id and target_zone == "hand"
	if is_local_gain:
		# 前置飞行段；来源是本机自己的区域时没有可见的飞行起点，只保留正式节点的正常对账。
		_play_local_hand_gain_flight(card_uid, card_data, source_player_id, source_zone)
		_start_pending_local_hand_gain_flights()
		return
	# 转移来源；本机手牌与装备区取实体牌真实位置，其他来源沿用玩家武将牌或中央公共锚点。
	var transfer_origin_result: Dictionary = _try_take_card_origin(card_uid, source_player_id, source_zone)
	if not bool(transfer_origin_result.get("valid", false)):
		return
	# 动画起点；命中本机正式手牌时等于该牌当前槽位中心，接管后由动画层保留全局变换继续飞行。
	var start_position: Vector2 = transfer_origin_result.get("position", Vector2.ZERO) as Vector2
	# 动画终点；进入角色手牌时移动到其武将锚点，本地主视角的非摸牌获得已由正式手牌节点分支提前处理。
	var target_position: Vector2 = _global_to_animation_position(discard_pile_panel.get_global_rect().get_center())
	if target_player_id >= 0 and target_zone in ["hand", "equipment", "judgment", "wooden_ox"]:
		# 当前目标玩家锚点；快照重建期间缺失时宁可跳过短时动画，也不能在窗口中上部留下伪造落点。
		var target_anchor_result: Dictionary = _try_get_player_indicator_position(target_player_id)
		if not bool(target_anchor_result.get("valid", false)):
			return
		target_position = target_anchor_result.get("position", target_position) as Vector2
	# 牌面可见性；牌堆摸牌和其他观察者不可见的手牌转移只显示统一牌背，公开弃牌与公开区域显示正面。
	var show_card_back: bool = _should_show_card_back(source_player_id, source_zone, target_player_id, target_zone)
	# 转移牌节点；优先接管本机仍在手牌容器中的正式节点，使被他人取走的牌从它真实所在位置起飞。
	var animated_card: CardView = transfer_origin_result.get("card_view") as CardView
	# 被接管的正式手牌节点立即退出手牌映射，之后它的生命周期完全由动画层负责。
	_forget_taken_over_hand_card(card_uid, animated_card)
	if animated_card == null:
		# 表现牌面；所有表现仍复用正式 CardView，不创建简化标签。
		animated_card = CARD_VIEW_SCENE.instantiate() as CardView
		animated_card.visible = false
		if show_card_back:
			animated_card.configure_back(card_uid, false)
		else:
			var definition: Dictionary = _get_cached_card_definition(str(card_data.get("definition_id", "")))
			animated_card.configure(card_data, definition, false, false)
		card_use_animation_layer.add_child(animated_card)
		animated_card.position = start_position - animated_card.get_card_size() * 0.5
	# 摸牌堆叠键；同一目标玩家连续从牌堆进入手牌的牌按数量依次堆叠，其他转移保持独立动画。
	var draw_stack_key: String = "draw:%d" % target_player_id if source_zone == "draw_pile" and target_zone == "hand" and target_player_id >= 0 else ""
	card_use_animation_layer.play_transfer(animated_card, start_position, target_position, draw_stack_key)


## 接收实体进入新区域的内部所有权通知；只释放旧弃牌待消费与已消费状态，不创建牌面或修改权威区域。
## 所有权释放同样进入回放录制，重演端的中央牌面生命周期与录制端逐步一致。
func _on_card_animation_ownership_reset_requested(card_uid: int) -> void:
	_record_replay_presentation({"e":"ownership_reset", "card_uid":card_uid})
	card_use_animation_layer.release_consumed_discard_claim(card_uid)


## 判断一次牌区转移是否只能显示牌背；这是全项目唯一的牌背判定入口，所有表现路径必须共用它。
##
## 判定口径：进入本机手牌区的牌一律显示正面（该牌落地后就是本人可见的手牌，途中显示牌背会出现落地瞬间的翻面突变）；
## 牌堆方向对除本机手牌目标之外的所有观察者隐藏；手牌与木牛方向只对“既不是来源本人、也不是目标本人”的观察者隐藏；
## 进入弃牌堆属于公开信息，以及展示牌、装备区、判定区等公开区域一律显示正面。
## 集中到一处的原因：本机获得、他人获得和纯展示三条路径曾经各写一份类似的布尔表达式，
## 任何一处漏改都会把其他观察者不可见的私有牌面公开成正面。
func _should_show_card_back(source_player_id: int, source_zone: String, target_player_id: int, target_zone: String) -> bool:
	# 本机玩家 ID；手牌与木牛方向只对旁观者隐藏，来源本人和目标本人始终能看到牌面。
	var local_player_id: int = match_controller.local_human_player_id
	if target_player_id == local_player_id and target_zone == "hand":
		# 本机手牌目标的正面判定必须排在牌堆判定之前，否则本机摸牌会以牌背飞入手牌区。
		return false
	if source_zone == "draw_pile":
		return true
	return source_zone in ["hand", "wooden_ox"] and source_player_id != local_player_id and target_player_id != local_player_id and target_zone != "discard_pile"


## 统一解析一张牌离场瞬间的真实来源位置与可接管节点；所有离场、被取走和被展示的表现都必须经此入口取起点。
##
## 解析优先级（顺序即优先级；不得在其他函数里重写这套判断，否则同一种语义会分裂出第二套位置规则）：
## 1. 本机手牌区／木牛区的正式 CardView：直接返回该节点，调用方让动画层接管它，飞行从真实槽位连续开始。
## 2. 本机装备区的装备横条：装备行不是 CardView，只返回槽位矩形，由调用方新建表现牌面。
## 3. 其他角色：返回其武将牌锚点；本机看不到对方具体牌位，不得伪造位置。
## 4. 公共区域（牌堆、处理区、展示区、弃牌堆）：返回中央弃牌锚点。
##
## 返回 valid=false 时调用方必须放弃本次表现，不能用中央锚点顶替玩家来源。
## 返回 position 为动画层局部坐标下的牌面中心；返回 global_rect 为来源屏幕矩形；
## 返回 card_view 仅在命中本机正式手牌节点时非空，调用方可直接把它交给动画层接管。
##
## 命中正式手牌节点时本函数会先收尾该牌未完成的入场与整理表现，使接管严格从它当前稳定槽位开始，
## 且不会与仍在对 position 写入的旧补间争用坐标。
func _try_take_card_origin(card_uid: int, source_player_id: int, source_zone: String) -> Dictionary:
	if source_zone in ["hand", "wooden_ox"] and source_player_id == match_controller.local_human_player_id:
		# 当前正式手牌节点；只有仍挂在手牌容器中时才可被动画层接管，UID 映射里可能残留已经离开的引用。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view != null and is_instance_valid(card_view) and card_view.get_parent() == hand_container:
			# 先结束尚未播完的入场动画：它的补间会持续写入入场偏移，必须在新表现接管前停止。
			_cancel_local_hand_gain_animation(card_uid)
			# 再结束整理过渡：残留偏移会让飞牌起点偏离槽位，且旧补间会继续争用同一个 position。
			hand_container.end_card_relayout_transition(card_view)
			# 当前手牌全局矩形；CardView 的 Node2D 原点位于牌面左上角，选中抬升已包含在矩形里。
			var hand_card_rect: Rect2 = card_view.get_global_rect()
			return {"valid":true, "position":_global_to_animation_position(hand_card_rect.get_center()), "global_rect":hand_card_rect, "card_view":card_view}
	if source_zone == "equipment" and source_player_id == match_controller.local_human_player_id:
		# 当前装备槽矩形查询；装备横条缺失时按“查不到”处理，不用武将牌锚点顶替它的真实槽位。
		var equipment_slot_result: Dictionary = equipment_label.find_card_global_rect(card_uid)
		if bool(equipment_slot_result.get("valid", false)):
			var equipment_rect: Rect2 = equipment_slot_result.get("rect", Rect2()) as Rect2
			return {"valid":true, "position":_global_to_animation_position(equipment_rect.get_center()), "global_rect":equipment_rect, "card_view":null}
	if source_player_id >= 0 and source_zone not in ["draw_pile", "processing", "discard_pile"]:
		# 当前来源玩家锚点；座位尚未建立时整个表现放弃，避免牌面错误出现在窗口中上部。
		var source_anchor_result: Dictionary = _try_get_player_indicator_position(source_player_id)
		if not bool(source_anchor_result.get("valid", false)):
			return {"valid":false, "position":Vector2.ZERO, "global_rect":Rect2(), "card_view":null}
		return {"valid":true, "position":source_anchor_result.get("position", Vector2.ZERO) as Vector2, "global_rect":Rect2(), "card_view":null}
	# 公共锚点；牌堆、处理区、展示区和弃牌堆都以中央弃牌区中心为公共来源。
	return {"valid":true, "position":_global_to_animation_position(discard_pile_panel.get_global_rect().get_center()), "global_rect":Rect2(), "card_view":null}


## 把已由动画层接管的正式手牌节点从手牌 UID 映射中移除。
##
## 「_card_views」的语义是“当前仍由手牌区拥有的正式手牌节点”；一旦节点被出牌或转移动画接管，
## 它的位置、可见性和生命周期都改由动画层决定，映射必须同步遗忘该实体。
## 若不遗忘，动画层稍后释放该节点时映射会残留已释放对象，而后续快照对账、选中态刷新等路径
## 都会对映射值做 CardView 强制转换，对已释放对象转换会直接中止当前函数，
## 表现为整轮手牌渲染被静默跳过（既不释放旧牌也不计算新槽位）。
func _forget_taken_over_hand_card(card_uid: int, card_view: CardView) -> void:
	# 只有映射当前确实指向这个被接管节点时才移除，避免误删同一 UID 之后重新建立的手牌节点。
	if card_view == null or _card_views.get(card_uid) != card_view:
		return
	_card_views.erase(card_uid)


## 把正式手牌节点的明暗同步到同一张牌正在进行的获得牌飞行牌面上；每次快照重配正式节点后调用。
##
## 正式节点落地后就是玩家最终看到的那张牌：若飞行牌面一直保持默认的禁用压暗，而正式节点是可用状态（明亮），
## 玩家会在牌刚进入手牌区之后看到一次亮度跳变（飞行牌面淡出、底下亮牌显露）。
## 同步只写观感，不改变飞行牌面的输入权限与 UID，因此飞行中的牌仍然不可点击。
func _sync_local_hand_gain_flight_appearance(card_uid: int, card_view: CardView) -> void:
	# 当前门闸记录；本机区域之间移动、普通对账都不会登记门闸，此时没有飞行牌面需要同步。
	var gate: Dictionary = _local_hand_gain_flight_gates.get(card_uid, {}) as Dictionary
	if gate.is_empty():
		return
	# 当前门闸记录的飞行牌面；已被清场释放时跳过，正式节点仍会正常落位。
	var flight_card_variant: Variant = gate.get("card", null)
	if not (flight_card_variant is CardView) or not is_instance_valid(flight_card_variant):
		return
	(flight_card_variant as CardView).set_content_dimmed(card_view.is_content_dimmed())


## 登记一次本机获得牌的前置飞行；返回 true 表示已经登记门闸并需要等待落地回调解除。
##
## 只有“来源不是本机自己的区域”的获得才需要前置飞行：本机区域之间的移动没有可见来源，
## 直接由手牌容器的槽位整理过渡表达即可，不再从右侧滑入。
## 本方法只登记起点与门闸、不在此处起飞：飞行终点必须是该牌在手牌区的最终槽位，
## 而槽位要等包含该牌的权威快照完成布局，因此真正的起飞统一交给 _start_pending_local_hand_gain_flights()。
## 若该牌此刻正显示在中央展示队列中（例如获得别人刚打出的【杀】），这里直接取走那张牌面本身继续飞行，
## 而不是新建第二张牌面，避免出现“牌飞进手里、原牌还留在中央”的复制观感。
func _play_local_hand_gain_flight(card_uid: int, card_data: Dictionary, source_player_id: int, source_zone: String) -> bool:
	if source_player_id == match_controller.local_human_player_id:
		return false
	if source_player_id < 0 and source_zone in ["hand", "wooden_ox", "equipment"]:
		# 缺少来源玩家的本机私有区域移动没有可解析的真实来源，放弃前置飞行而不是伪造中央起点。
		# “processing”不属于私有区域：它对应中央处理区，公共锚点即其真实来源，因此必须保留飞行能力。
		return false
	# 中央展示队列里同 UID 的正式牌面；命中时它就是本次飞行的牌面，飞行从它当前所在位置开始。
	var flight_card: CardView = card_use_animation_layer.take_over_active_card(card_uid)
	# 前置飞行起点；命中展示牌面时等于它当前所在位置，其余来源取统一的来源解析结果。
	var flight_start_position: Vector2 = Vector2.ZERO
	if flight_card != null:
		flight_start_position = flight_card.position + flight_card.get_card_size() * 0.5
	else:
		# 来源解析；无法解析时放弃前置飞行，正式手牌节点会在快照后直接出现在自己的槽位，不会留下停在屏幕上的孤立牌面。
		var origin_result: Dictionary = _try_take_card_origin(card_uid, source_player_id, source_zone)
		if not bool(origin_result.get("valid", false)):
			return false
		# 前置飞行起点；命中本机正式手牌时等于该牌槽位中心，其余来源为武将牌锚点或公共锚点。
		flight_start_position = origin_result.get("position", Vector2.ZERO) as Vector2
		# 飞行牌面；获得牌在本机视角按统一牌背规则显示，牌堆方向仍为牌背，其余来源显示正面。
		flight_card = CARD_VIEW_SCENE.instantiate() as CardView
		flight_card.visible = false
		if _should_show_card_back(source_player_id, source_zone, match_controller.local_human_player_id, "hand"):
			flight_card.configure_back(card_uid, false)
		else:
			var flight_definition: Dictionary = _get_cached_card_definition(str(card_data.get("definition_id", "")))
			flight_card.configure(card_data, flight_definition, false, false)
		card_use_animation_layer.add_child(flight_card)
		flight_card.position = flight_start_position - flight_card.get_card_size() * 0.5
	# 手牌飞行门闸；必须在快照之前登记，保证正式手牌节点先被按在飞行起点，而不是提前出现在槽位。
	# started=false 表示尚未起飞：起飞需要等快照布局算出该牌的最终槽位；batch=-1 表示这是一次单张获得飞行。
	# snapshot_generation 记录登记时已生效的快照代次，供对账区分“快照还没包含这张牌”与“这张牌已经离开手牌”。
	_local_hand_gain_flight_gates[card_uid] = {"card":flight_card, "origin":flight_start_position, "started":false, "batch":-1, "snapshot_generation":_local_hand_snapshot_generation}
	return true


## 解除一批本机获得牌的前置飞行门闸并让对应正式手牌节点落在各自槽位；由飞行落地回调触发。
## 单张获得与整批摸牌共用同一入口，避免为“批次解闸”再维护第二套逻辑。
func _release_local_hand_gain_flight_gates(card_uids: Array) -> void:
	# 本次是否真的解除了门闸；没有任何门闸变化时不必重新落位。
	var released_any: bool = false
	# 本次真正解除门闸的实体 UID；用于精确收尾对应节点的起点保持偏移。
	var released_uids: Array = []
	for card_uid_variant: Variant in card_uids:
		# 当前解闸实体 UID；迟到或已清理的 UID 不会误触发落位。
		var card_uid: int = int(card_uid_variant)
		# 当前门闸记录；解闸前先取出飞行牌面，落地帧要立即隐去它，只留下正式手牌节点。
		var gate: Dictionary = _local_hand_gain_flight_gates.get(card_uid, {}) as Dictionary
		if _local_hand_gain_flight_gates.erase(card_uid):
			released_any = true
			released_uids.append(card_uid)
			# 飞行牌面与正式节点此刻停在同一个槽位；立即隐去飞行牌面，避免两张牌重叠产生亮度与描边差异，
			# 也避免看不见的上层牌面继续拦截鼠标、挡住刚落地的手牌点击。
			var landed_card_variant: Variant = gate.get("card", null)
			if landed_card_variant is CardView and is_instance_valid(landed_card_variant):
				(landed_card_variant as CardView).visible = false
	if released_any:
		_finish_local_hand_gain_holds(released_uids)


## 结束一批获得牌的起点保持，让它们立即出现在各自槽位；落地帧一次性收尾，不产生第二段滑动。
## 飞行牌面此刻正好停在槽位中心，正式节点同帧出现在同一位置，玩家看到的是同一张牌连续到位。
func _finish_local_hand_gain_holds(card_uids: Array) -> void:
	# 本次是否有节点真正改动了偏移；没有任何节点需要收尾时不必重新布局。
	var changed_any: bool = false
	for card_uid_variant: Variant in card_uids:
		# 当前需要落位的实体 UID；牌已离开手牌时只跳过，不影响其他成员。
		var card_uid: int = int(card_uid_variant)
		# 当前正式手牌节点；已被动画层接管或已释放的节点不再由本函数写入位置。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			continue
		if not card_view.hand_entry_offset.is_zero_approx():
			card_view.hand_entry_offset = Vector2.ZERO
			changed_any = true
	if changed_any:
		hand_container.layout_cards_now()


## 启动所有已经可以起飞的本机获得牌飞行；在每次快照手牌布局之后调用，此时每张牌的最终槽位才存在。
##
## 单张获得与整批摸牌共用本入口：整批摸牌一次播放同批牌背并逐张抵达各自槽位，单张获得则播放自己的飞行。
## 尚未进入快照的牌保留待起飞登记；门闸已被清理（该牌离开手牌区）的成员在此丢弃并释放其人未播放的牌面，
## 绝不留下停在屏幕上的孤立牌面，也绝不让门闸永远等不到落地回调。
func _start_pending_local_hand_gain_flights() -> void:
	for batch_id_variant: Variant in _pending_local_draw_batches.keys():
		# 当前待起飞批次 ID 与数据；批次可能已被取消，缺失时跳过。
		var batch_id: int = int(batch_id_variant)
		var draw_batch: Dictionary = _pending_local_draw_batches.get(batch_id, {}) as Dictionary
		if draw_batch.is_empty():
			continue
		# 本批飞行起点；同批全部牌面共用一个牌堆起点，因此逐张落点只改终点。
		var batch_origin: Vector2 = draw_batch.get("origin", Vector2.ZERO) as Vector2
		# 本批仍未起飞的成员映射；起飞或丢弃后逐个摘除，避免后续快照重复播放。
		var batch_views: Dictionary = (draw_batch.get("views_by_uid", {}) as Dictionary).duplicate()
		# 本帧可播放的成员；三组数组下标严格对应同一批牌。
		var flight_views: Array[CardView] = []
		var flight_targets: Array[Vector2] = []
		var flight_uids: Array = []
		for card_uid_variant: Variant in batch_views.keys():
			# 当前批次成员 UID；门闸缺失说明这张牌已经离开手牌区，本批不再需要播放它。
			var card_uid: int = int(card_uid_variant)
			if not _local_hand_gain_flight_gates.has(card_uid):
				# 未加入动画层的牌面必须在此释放；否则会留下永远不播放的孤立节点。
				var dropped_view: CardView = batch_views.get(card_uid_variant) as CardView
				if dropped_view != null and is_instance_valid(dropped_view):
					dropped_view.queue_free()
				batch_views.erase(card_uid_variant)
				continue
			# 当前正式手牌节点；还没有进入快照时保留成员，等下一次对账再判断。
			var card_view: CardView = _card_views.get(card_uid) as CardView
			if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
				continue
			flight_views.append(batch_views[card_uid_variant] as CardView)
			flight_targets.append(_get_local_hand_card_slot_center(card_view))
			flight_uids.append(card_uid)
		if flight_views.is_empty():
			# 本帧没有成员可以起飞；写回清理结果后继续等待下一次快照。
			if batch_views.is_empty():
				_pending_local_draw_batches.erase(batch_id)
			else:
				draw_batch["views_by_uid"] = batch_views
				_pending_local_draw_batches[batch_id] = draw_batch
			continue
		for flight_uid_variant: Variant in flight_uids:
			# 起飞即置位；同一门闸不会因为后续快照再启动第二段飞行。
			var gate: Dictionary = _local_hand_gain_flight_gates.get(flight_uid_variant, {}) as Dictionary
			if not gate.is_empty():
				gate["started"] = true
				_local_hand_gain_flight_gates[flight_uid_variant] = gate
			batch_views.erase(flight_uid_variant)
		if batch_views.is_empty():
			_pending_local_draw_batches.erase(batch_id)
		else:
			draw_batch["views_by_uid"] = batch_views
			_pending_local_draw_batches[batch_id] = draw_batch
		# 逐张落点的整批摸牌；同批仍共用一条批次补间、同帧起飞，只是各自飞向自己的手牌槽位。
		card_use_animation_layer.play_draw_transfer_batch(flight_views, batch_origin, batch_origin, _release_local_hand_gain_flight_gates.bind(flight_uids), flight_targets)
	for card_uid_variant: Variant in _local_hand_gain_flight_gates.keys():
		# 当前单张获得门闸 UID；整批摸牌的门闸由上面的批次分支统一处理。
		var card_uid: int = int(card_uid_variant)
		var gate: Dictionary = _local_hand_gain_flight_gates.get(card_uid_variant, {}) as Dictionary
		if gate.is_empty() or bool(gate.get("started", false)) or int(gate.get("batch", -1)) >= 0:
			continue
		# 当前正式手牌节点；还没有进入快照时保留门闸，等下一次对账再起飞。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			continue
		var flight_card_variant: Variant = gate.get("card", null)
		if not is_instance_valid(flight_card_variant):
			# 飞行牌面已被清场释放；直接解闸让正式节点落位，绝不留下永远等不到回调的门闸。
			_release_local_hand_gain_flight_gates([card_uid])
			continue
		gate["started"] = true
		_local_hand_gain_flight_gates[card_uid] = gate
		# 飞行终点是该牌自己的最终槽位；落地回调解闸后正式节点就出现在同一个位置。
		card_use_animation_layer.play_transfer(flight_card_variant as CardView, gate.get("origin", Vector2.ZERO) as Vector2, _get_local_hand_card_slot_center(card_view), "", _release_local_hand_gain_flight_gates.bind([card_uid]))
	# 起飞后立即把正式节点按在飞行起点；本函数可能在保持阶段之前被调用（先起飞再登记 started），
	# 若不在此补一次保持，刚起飞的牌会在本帧以槽位位置闪现，正是需要消除的“先出现在手牌区”观感。
	_hold_gated_local_hand_entries()


## 返回一张正式手牌节点最终槽位中心的动画层坐标；所有获得牌飞行的终点都必须经此取值。
## 稳定槽位真值来自容器本次布局写入的 position：扣除入场、选中与整理三类运行时偏移后即为槽位左上角，
## 因此飞行终点不会跟随其他独立表现漂移，也不需要任何调用方自行估算坐标。
func _get_local_hand_card_slot_center(card_view: CardView) -> Vector2:
	# 稳定槽位左上角的容器坐标；三类偏移都必须剔除。
	var slot_local_position: Vector2 = card_view.position - card_view.hand_entry_offset - card_view.hand_selection_offset - card_view.hand_layout_offset
	# 槽位中心的全局坐标；容器变换包含画布缩放、手牌滚动与窗口适配。
	var slot_global_position: Vector2 = hand_container.get_global_transform() * (slot_local_position + card_view.get_card_size() * 0.5)
	return _global_to_animation_position(slot_global_position)


## 把仍被前置飞行门闸挡住的本机获得牌固定在本次飞行的起点；在每次快照手牌布局之后调用。
##
## 门闸期间这些牌不能出现在最终槽位，否则玩家会先看到牌已经躺进手牌区，随后又被重新飞入一次；
## 而起点位于手牌滚动区之外，节点会被滚动容器裁剪，因此在玩家看来它仍在来源处。
## 本方法同时承担门闸的最后一道兜底：飞行牌面已被动画层释放说明落地回调不会再触发，
## 此时立即补齐解闸并让牌落位，避免任何异常清场路径把牌永久留在可视手牌区之外。
func _hold_gated_local_hand_entries() -> void:
	if _local_hand_gain_flight_gates.is_empty():
		return
	# 本轮需要兜底解除的门闸 UID；先收集再删除，禁止在遍历字典期间直接修改它。
	var stale_gate_uids: Array[int] = []
	for card_uid_variant: Variant in _local_hand_gain_flight_gates.keys():
		# 当前仍被门闸挡住的实体 UID；尚未出现在快照中的牌本轮没有节点可保持。
		var card_uid: int = int(card_uid_variant)
		# 当前门闸记录；结构异常时按正常门闸继续等待落地回调。
		var gate: Dictionary = _local_hand_gain_flight_gates.get(card_uid_variant, {}) as Dictionary
		if gate.is_empty():
			continue
		# 当前门闸记录的飞行牌面；牌面已被释放说明落地回调不会再来。
		var gate_flight_variant: Variant = gate.get("card", null)
		if gate_flight_variant is CardView and not is_instance_valid(gate_flight_variant):
			stale_gate_uids.append(card_uid)
			continue
		if not bool(gate.get("started", false)):
			# 尚未起飞：位置仍由来源处与快照的自然顺序决定，本函数不写入任何偏移。
			continue
		# 当前正式手牌节点；只在它已经进入手牌容器后才需要保持在飞行起点。
		var card_view: CardView = _card_views.get(card_uid) as CardView
		if card_view == null or not is_instance_valid(card_view) or card_view.get_parent() != hand_container:
			continue
		# 起点保持偏移；与飞行起点取同一坐标，解闸后节点正好出现在飞行牌面抵达的槽位。
		card_view.hand_entry_offset = _get_local_hand_gain_origin_offset(card_view, gate.get("origin", Vector2.ZERO) as Vector2)
	if stale_gate_uids.is_empty():
		return
	_release_local_hand_gain_flight_gates(stale_gate_uids)


## 返回正式手牌节点在飞行期间被按在飞行起点所需的偏移量；单位与 hand_entry_offset 一致。
## 传入的起点是动画层坐标下的牌面中心，必须经真实变换链转成容器坐标，兼容画布缩放与手牌滚动。
func _get_local_hand_gain_origin_offset(card_view: CardView, origin_position: Vector2) -> Vector2:
	# 飞行起点的全局坐标；动画层坐标经真实变换转回全局。
	var origin_global_position: Vector2 = card_use_animation_layer.get_global_transform() * origin_position
	# 飞行起点左上角的容器坐标；CardView 的 Node2D 原点位于牌面左上角。
	var origin_local_position: Vector2 = hand_container.get_global_transform().affine_inverse() * origin_global_position - card_view.get_card_size() * 0.5
	# 稳定槽位左上角的容器坐标；扣除三类运行时偏移，保证按住位置只由槽位与飞行起点决定。
	var slot_local_position: Vector2 = card_view.position - card_view.hand_entry_offset - card_view.hand_selection_offset - card_view.hand_layout_offset
	return origin_local_position - slot_local_position


## 返回指定正式手牌节点在容器坐标下的右侧入场偏移量；入场补间与虚拟牌离场序列共享同一落点公式。
## 真实获得牌的门闸保持已改为按各自飞行起点计算，不再使用本函数。
func _get_local_hand_gain_entry_offset(card_view: CardView, target_position: Vector2) -> Vector2:
	# 右侧入场中心全局坐标；固定从当前可视滚动区外侧进入，不受超宽内容区域影响。
	var start_global_center: Vector2 = _get_local_hand_gain_start_global_position(card_view.get_card_size())
	# 右侧入场左上角全局坐标；CardView 的 Node2D 原点位于牌面左上角。
	var start_global_position: Vector2 = start_global_center - card_view.get_card_size() * 0.5
	# 右侧入场左上角容器坐标；完整逆变换兼容画布缩放、滚动区位置和窗口适配。
	var start_local_position: Vector2 = hand_container.get_global_transform().affine_inverse() * start_global_position
	return start_local_position - target_position


## 返回一次展示表现中牌面副本的起飞中心；本机手牌或装备区的牌被展示时使用它真实所在的位置。
##
## 展示表现自带声明的来源区域，因此这里只在来源属于本机私有牌区时改写起点；
## 处理区、牌堆、展示区和弃牌堆的来源语义完全由调用方传入的统一玩家锚点表达，
## 若在此按公共锚点覆盖，反而会让使用牌从桌面中心凭空出现。
func _resolve_presentation_card_position(card_uid: int, actor_id: int, source_zone: String, fallback_position: Vector2) -> Vector2:
	if source_zone not in ["hand", "wooden_ox", "equipment"]:
		return fallback_position
	# 精确来源查询；只能命中本机自己的牌，其他玩家仍返回其武将牌锚点，与 fallback 完全一致。
	var origin_result: Dictionary = _try_take_card_origin(card_uid, actor_id, source_zone)
	if not bool(origin_result.get("valid", false)):
		return fallback_position
	return origin_result.get("position", fallback_position) as Vector2


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
		if _local_hand_gain_flight_gates.has(card_uid):
			# 前置飞行尚未落地；保留待入场登记，等落地回调再次调用本函数，绝不能提前滑入。
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
	# 右侧入场偏移；与门闸保持阶段共用同一落点公式，两处不得各写一套坐标换算。
	card_view.hand_entry_offset = _get_local_hand_gain_entry_offset(card_view, target_position)
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
	# 前置飞行门闸同时撤销；该牌的落位不会再等待一段已经被取消的飞行。
	# 尚未起飞的飞行牌面与待起飞批次登记由本调用一并回收，避免留下永不播放的孤立牌面。
	_cancel_pending_local_hand_gain_flight(card_uid)
	_local_hand_gain_flight_gates.erase(card_uid)
	# 当前实体正在运行的入场补间；停止后从索引移除，防止旧完成回调修改后续状态。
	var gain_tween: Tween = _local_hand_gain_tweens.get(card_uid) as Tween
	if gain_tween != null and gain_tween.is_valid():
		gain_tween.kill()
	_local_hand_gain_tweens.erase(card_uid)
	# 当前正式手牌节点原始值；被动画层接管并释放的节点可能仍被调用方按 UID 传入，
	# 先按 Variant 校验有效性，避免对已释放对象强制转换中止调用方（例如整轮手牌对账）。
	var card_view_variant: Variant = _card_views.get(card_uid)
	if not is_instance_valid(card_view_variant):
		return
	# 当前正式手牌节点；仍位于手牌容器时清除剩余偏移，使后续出牌从真实布局位置开始。
	var card_view: CardView = card_view_variant as CardView
	if card_view.get_parent() == hand_container:
		card_view.hand_entry_offset = Vector2.ZERO
		# 起点保持偏移与整理偏移同样必须归零：被取消的获得牌不该继续停在来源处或旧槽位。
		card_view.hand_layout_offset = Vector2.ZERO
		hand_container.layout_cards_now()


## 撤销一张牌尚未起飞的前置飞行；已经起飞的牌面不改动，它由动画层在落地淡出后自行释放。
## 未起飞的飞行牌面既没有交给动画层播放过、也不会再被播放，因此必须在此释放，并从待起飞摸牌批次中摘除。
func _cancel_pending_local_hand_gain_flight(card_uid: int) -> void:
	# 当前门闸记录；缺失表示这张牌没有等待中的飞行。
	var gate: Dictionary = _local_hand_gain_flight_gates.get(card_uid, {}) as Dictionary
	if gate.is_empty():
		return
	if not bool(gate.get("started", false)):
		var gate_flight_variant: Variant = gate.get("card", null)
		if is_instance_valid(gate_flight_variant):
			(gate_flight_variant as CardView).queue_free()
	for batch_id_variant: Variant in _pending_local_draw_batches.keys():
		# 当前待起飞批次；只处理包含该 UID 的批次，其余批次保持原样等待快照。
		var batch_id: int = int(batch_id_variant)
		var draw_batch: Dictionary = _pending_local_draw_batches.get(batch_id, {}) as Dictionary
		var batch_views: Dictionary = draw_batch.get("views_by_uid", {}) as Dictionary
		if not batch_views.has(card_uid):
			continue
		batch_views.erase(card_uid)
		if batch_views.is_empty():
			_pending_local_draw_batches.erase(batch_id)
			continue
		draw_batch["views_by_uid"] = batch_views
		_pending_local_draw_batches[batch_id] = draw_batch


## 清空全部本地正式手牌入场任务；重新开局时调用，避免旧局补间继续写入新桌面。
func _clear_local_hand_gain_animations() -> void:
	for gain_tween_variant: Variant in _local_hand_gain_tweens.values():
		# 当前仍有效的入场补间；统一停止后再清空索引。
		var gain_tween: Tween = gain_tween_variant as Tween
		if gain_tween != null and gain_tween.is_valid():
			gain_tween.kill()
	for card_view_variant: Variant in _card_views.values():
		# 映射值有效性预检；理论上映射不残留已释放节点，但清场路径必须容忍异常值，
		# 否则对已释放对象强制转换会中止本函数，导致门闸与补间索引无法清空。
		if not is_instance_valid(card_view_variant):
			continue
		# 当前正式手牌节点；清场前归零运行时偏移，避免复用时继承旧局位置。
		var card_view: CardView = card_view_variant as CardView
		if card_view != null and is_instance_valid(card_view) and card_view.get_parent() == hand_container:
			card_view.hand_entry_offset = Vector2.ZERO
	_pending_local_hand_gain_uids.clear()
	_local_hand_gain_tweens.clear()
	# 待起飞的本机摸牌批次；成员牌面从未交给动画层播放，必须在此释放，否则会留下永远不播放的孤立节点。
	for batch_id_variant: Variant in _pending_local_draw_batches.keys():
		# 当前待起飞批次；只读取成员映射，缺失时安全跳过。
		var draw_batch: Dictionary = _pending_local_draw_batches.get(batch_id_variant, {}) as Dictionary
		for batch_view_variant: Variant in (draw_batch.get("views_by_uid", {}) as Dictionary).values():
			if is_instance_valid(batch_view_variant):
				(batch_view_variant as CardView).queue_free()
	_pending_local_draw_batches.clear()
	# 前置飞行门闸属于同一批表现生命周期；未起飞的飞行牌面与门闸一起清空，否则新局的获得牌会永远停在屏幕外。
	for gate_variant: Variant in _local_hand_gain_flight_gates.values():
		# 当前门闸记录；已起飞的牌面由动画层清场统一释放，这里只处理从未播放的牌面。
		var gate: Dictionary = gate_variant as Dictionary
		if gate.is_empty() or bool(gate.get("started", false)):
			continue
		var gate_card_variant: Variant = gate.get("card", null)
		if is_instance_valid(gate_card_variant):
			(gate_card_variant as CardView).queue_free()
	_local_hand_gain_flight_gates.clear()
	# 清场后偏移已归零但 position 里仍保留着上一次写入的保持位置，必须重新布局一次让仍在容器中的手牌回到自己的槽位。
	hand_container.layout_cards_now()


## 将全局画布坐标转换为动画层局部坐标；使用完整逆变换以兼容父节点位移、缩放与后续视口适配。
func _global_to_animation_position(global_position: Vector2) -> Vector2:
	return card_use_animation_layer.get_global_transform().affine_inverse() * global_position


## 显示最近一次动作拒绝原因。
func _on_action_rejected(message: String) -> void:
	_last_action_rejection_message = message
	error_label.text = message
	if main_menu != null and is_instance_valid(main_menu) and main_menu.visible:
		main_menu.show_start_error(message)


## 展示对局停滞自修复提醒横幅；报告级别决定提示文案，完整修复细节仍可在对局日志中查看。
func _on_self_repair_performed(repair_report: Dictionary) -> void:
	if information_box == null or not is_instance_valid(information_box):
		return
	# 本次修复级别；human_reminder 只是待办提示重发，其余级别都代表系统实际修复了停滞流程。
	var repair_kind: String = str(repair_report.get("kind", ""))
	# 面向玩家的横幅文案；保持一句话说明发生了什么，避免打断对局节奏。
	var notice_message: String = "检测到对局停滞，系统已自动修复并恢复流程。"
	if repair_kind == "human_reminder":
		notice_message = "当前有待办选择等待操作，已重新发送选择提示。"
	information_box.show_notice(notice_message)


## 更新当前选择摘要，目标以玩家显示名与选择顺序呈现；本地阵亡或终局时改为显示重开与返回主菜单操作。
func _refresh_selection_text() -> void:
	_card_use_preview = {}
	recast_button.visible = false
	_clear_inline_control_extra_option_buttons()
	_inline_control_primary_option_id = ""
	_inline_control_secondary_option_id = ""
	if _zhenqi_cancel_button != null and is_instance_valid(_zhenqi_cancel_button):
		_zhenqi_cancel_button.visible = false
	use_button.visible = true
	settlement_button.visible = false
	settlement_button.disabled = true
	use_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	%CancelButton.text = "取消"
	%CancelButton.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	selection_label.visible = true
	call_deferred("_refresh_group_trick_response_button")
	if _should_show_post_match_actions():
		_refresh_post_match_actions()
		return
	# 房主调整 AI 武将阶段；房主可点击合法 AI 并用确定结束，其他玩家只显示等待提示。
	if str(_snapshot.get("current_phase", "")) == "ai_character_adjustment":
		_refresh_ai_character_adjustment_text()
		return
	# 起始手牌手气卡阶段；每名真人只操作自己的刷新与结束按钮。
	if str(_snapshot.get("current_phase", "")) == "starting_hand_mulligan":
		_refresh_starting_hand_mulligan_text()
		return
	# 本地玩家托管时不显示任何牌、技能、响应或结束阶段操作；手牌遮罩仍保留“取消托管”按钮以外的所有输入隔离。
	if bool(_get_player_snapshot(match_controller.local_human_player_id).get("auto_managed", false)):
		interaction_panel.visible = false
		use_button.disabled = true
		%CancelButton.visible = false
		end_play_button.visible = false
		end_play_button.disabled = true
		_refresh_component_states()
		return
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
	if _selected_card_uid < 0:
		# 未选牌时不显示废弃的通用文字框；手牌、目标高亮与确定按钮禁用状态已完整表达当前交互状态。
		selection_label.text = ""
		selection_label.visible = false
		interaction_guide_label.text = ""
		use_button.disabled = true
		%CancelButton.visible = false
		_refresh_component_states()
		return
	_card_use_preview = match_controller.get_card_use_preview(match_controller.local_human_player_id, _selected_card_uid, _selected_target_ids)
	# 已选卡牌定义；用于统一名称模式与说明文本。
	var selected_card: Dictionary = _get_selected_card_snapshot()
	var selected_definition: Dictionary = _get_cached_card_definition(str(selected_card.get("definition_id", "")))
	# 选牌说明只显示卡牌静态效果；牌名与当前目标已经分别由牌面和高亮状态表达，不再重复拼接。
	selection_label.visible = true
	selection_label.text = str(_card_use_preview.get("description", ""))
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


## 显示房主调整 AI 武将阶段的操作提示；局域网客户端不能看到可提交按钮。
func _refresh_ai_character_adjustment_text() -> void:
	# 当前公共开局设置；包含房主稳定玩家 ID 与可点击 AI 目标集合。
	var pre_game_setup: Dictionary = _snapshot.get("pre_game_setup", {}) as Dictionary
	# 当前本地玩家是否为权威房主；离线模式同样使用本地真人 ID。
	var is_authority_player: bool = int(pre_game_setup.get("host_player_id", -1)) == match_controller.local_human_player_id
	interaction_panel.visible = true
	selection_label.visible = false
	selection_label.text = ""
	interaction_guide_label.text = "请选择需要修改武将的角色" if is_authority_player else "房主调整武将中..."
	use_button.visible = is_authority_player
	use_button.text = "结束修改"
	use_button.disabled = not is_authority_player
	%CancelButton.visible = false
	end_play_button.visible = false
	end_play_button.disabled = true
	_refresh_component_states()


## 显示本地玩家手气卡询问；确认刷新，取消表示保留当前手牌并完成自己的开局确认。
func _refresh_starting_hand_mulligan_text() -> void:
	# 本地私有手气卡状态；房主按观察者裁剪，其他玩家看不到剩余张数。
	var mulligan_snapshot: Dictionary = _snapshot.get("starting_hand_mulligan", {}) as Dictionary
	# 当前玩家是否仍需操作；已完成玩家只显示等待其他玩家。
	var can_choose: bool = bool(mulligan_snapshot.get("can_choose", false))
	interaction_panel.visible = true
	selection_label.visible = false
	selection_label.text = ""
	use_button.visible = can_choose
	use_button.text = "使用手气卡"
	use_button.disabled = not bool(mulligan_snapshot.get("can_refresh", false))
	# 当前剩余张数；-1使用“无限张”，有限张数显示具体数字。
	var remaining: int = int(mulligan_snapshot.get("remaining", 0))
	var remaining_text: String = "无限张" if remaining == -1 else "%d张" % remaining
	interaction_guide_label.text = "是否使用手气卡？剩余%s" % remaining_text if can_choose else "等待其他玩家确认手气卡..."
	%CancelButton.visible = can_choose
	%CancelButton.text = "不再刷新"
	%CancelButton.disabled = false
	end_play_button.visible = false
	end_play_button.disabled = true
	_refresh_component_states()


## 判断是否应在本地手牌区上方显示终局操作；整局结束或本地角色阵亡都允许立即开始下一局或退出。
func _should_show_post_match_actions() -> bool:
	if _snapshot.is_empty():
		return false
	if bool(_snapshot.get("game_over", false)):
		return true
	# 本地玩家快照；只读取公开存活状态，不推断身份或修改权威对局。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	return not local_player.is_empty() and not bool(local_player.get("alive", true))


## 把原确定与取消位置复用于终局操作；固定尺寸、主题和手牌区上方锚点继续沿用统一操作区规格。
func _refresh_post_match_actions() -> void:
	interaction_panel.visible = true
	selection_label.text = ""
	selection_label.visible = false
	interaction_guide_label.text = _get_post_match_result_text()
	use_button.visible = true
	use_button.text = "重新开始"
	use_button.disabled = false
	use_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	# 终局结算入口；仅整局结束时显示，本地阵亡但整局未结束时不展示未完成数据。
	settlement_button.visible = bool(_snapshot.get("game_over", false))
	settlement_button.text = "结算界面"
	settlement_button.disabled = not settlement_button.visible
	settlement_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	# 原取消按钮；终局时承担退出当前对局的明确命令，不向规则核心提交取消选择。
	var cancel_button: Button = %CancelButton
	cancel_button.visible = true
	cancel_button.text = "返回主菜单"
	cancel_button.disabled = false
	cancel_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	end_play_button.visible = false
	end_play_button.disabled = true
	_refresh_component_states()


## 返回本地玩家视角的终局提示；胜者字段由权威对局快照给出，缺失时只保留中性结算标题供场景测试与旧回放使用。
func _get_post_match_result_text() -> String:
	# 当前权威胜者阵营；draw 代表牌堆与弃牌堆均无法提供摸牌时的平局终局。
	var winner: String = str(_snapshot.get("winner", ""))
	if winner == "draw":
		return "对局结算，游戏平局"
	if _is_local_player_victory(winner):
		return "对局结算，游戏胜利"
	if not winner.is_empty():
		return "对局结算，游戏失败"
	return "对局结算"


## 判定本机玩家是否属于权威胜者阵营；终局提示与终局音效共用同一判定，避免文字与音效互相矛盾。
func _is_local_player_victory(winner: String) -> bool:
	# 当前本地玩家公开身份；身份局终局阵营只由该稳定枚举判断，不依赖武将或座次。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	# 当前本地身份；快照不完整时不能错误宣告胜负。
	var local_identity: String = str(local_player.get("identity", ""))
	# 当前阵营是否与权威胜者一致；领袖与忠臣共享胜利条件，反贼和内奸分别独立，斗地主地主/农民与 2v2 蓝/红各自对应胜方字段。
	return (
		(winner == "leader_and_loyalists" and local_identity in ["leader", "loyalist"])
		or (winner == "rebels" and local_identity == "rebel")
		or (winner == "renegade" and local_identity == "renegade")
		or (winner == "landlords" and local_identity == "landlord")
		or (winner == "peasants" and local_identity == "peasant")
		or (winner == "blue_team" and local_identity == "blue")
		or (winner == "red_team" and local_identity == "red")
	)


## 推导本机视角的终局效果音标识；平局、胜利与失败各自使用独立音效，与本机终局提示完全一致。
func _resolve_match_result_effect_id() -> String:
	# 当前权威胜者阵营；与终局提示读取同一字段，保证两种表现不会出现分歧。
	var winner: String = str(_snapshot.get("winner", ""))
	if winner == "draw":
		return MATCH_RESULT_EFFECT_TIE
	if _is_local_player_victory(winner):
		return MATCH_RESULT_EFFECT_WIN
	# 胜者字段缺失说明快照不完整；此时不发声，避免把未知结果误报为失败。
	if winner.is_empty():
		return ""
	return MATCH_RESULT_EFFECT_LOSE


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
	var equipment_name: String = GameSettings.resolve_card_display_name(definition)
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
	# 确认提示；装备源码可通过 confirm_prompt 声明本段确定后的效果，没有声明时沿用通用文案。
	# 两段式装备（如木牛流马）的第一段没有目标，因此不能再显示“请选择目标”。
	var equipment_confirm_prompt: String = str(_card_use_preview.get("confirm_prompt", "请确认当前操作"))
	interaction_guide_label.text = equipment_confirm_prompt if bool(_card_use_preview.get("can_submit", false)) else ("请选择目标" if int(_card_use_preview.get("max_targets", 0)) > 0 else "请选择手牌材料")
	use_button.disabled = not bool(_card_use_preview.get("can_submit", false))
	_refresh_component_states()


## 刷新手牌区内联选择提示与操作按钮；确认必须至少选择一张且满足请求数量范围。
func _refresh_inline_choice_text() -> void:
	if _is_inline_zhenqi_cost_choice(_inline_card_choice):
		_refresh_inline_zhenqi_cost_choice_text()
		return
	if _is_inline_control_choice(_inline_card_choice):
		_refresh_inline_control_choice_text()
		return
	# 已选牌数；只读取界面临时数组，不修改权威请求的 selected_card_ids。
	var selected_count: int = _inline_selected_card_uids.size()
	# 规则要求的最少数量；弃牌阶段可能大于1，可取消响应通常为0。
	var min_select: int = int(_inline_card_choice.get("min_select", 0))
	# 规则允许的最多数量；单张响应为1，弃牌阶段等于必须弃置的手牌数。
	var max_select: int = int(_inline_card_choice.get("max_select", 0))
	# 当前选择类型；组合选择会分别读取卡牌和目标数量范围。
	var choice_type: String = str(_inline_card_choice.get("choice_type", "card"))
	# 卡牌维度范围；纯选目标固定为0，普通选牌继续使用兼容字段。
	var minimum_card_count: int = int(_inline_card_choice.get("min_card_select", 0 if choice_type == "target" else min_select))
	# 卡牌维度上限；用于组合选择确认状态。
	var maximum_card_count: int = int(_inline_card_choice.get("max_card_select", 0 if choice_type == "target" else max_select))
	# 目标维度范围；普通选牌固定为0，纯目标与组合选择读取请求字段。
	var minimum_target_count: int = int(_inline_card_choice.get("min_target_select", min_select if choice_type == "target" else 0))
	# 目标维度上限；用于阻止超过技能规则数量时确认。
	var maximum_target_count: int = int(_inline_card_choice.get("max_target_select", max_select if choice_type == "target" else 0))
	# 当前目标选择数量；只属于界面临时状态，不修改权威请求快照。
	var selected_target_count: int = _selected_target_ids.size()
	# 确认按钮的卡牌下限；可取消的普通选牌仍要求至少选1张，空结果必须通过“取消”表达。
	# 补充：不可取消的请求没有“取消”可以表达空结果，因此不能抬高下限，否则0张这一合法选择无处提交。
	var confirm_minimum_card_count: int = maxi(minimum_card_count, 1) if choice_type in ["card", "respond", "discard"] and maximum_card_count > 0 and bool(_inline_card_choice.get("allow_cancel", false)) else minimum_card_count
	# 确认按钮的目标下限；可取消的纯选目标同样要求至少选1名，避免空确认与取消语义混淆。
	# 补充：不可取消的请求必须允许0名目标直接确定——【好戏】等强制发动的技能用“不选任何角色”表达原文的0名目标，
	# 抬高下限会让确定按钮永久禁用，玩家既无法按原文结算0名目标，也无法推进这次强制发动。
	var confirm_minimum_target_count: int = maxi(minimum_target_count, 1) if choice_type == "target" and maximum_target_count > 0 and bool(_inline_card_choice.get("allow_cancel", false)) else minimum_target_count
	# 内联询问只保留具体规则提示与操作按钮；通用标题、已选数量和范围摘要不重复显示。
	selection_label.text = ""
	selection_label.visible = false
	interaction_guide_label.text = str(_inline_card_choice.get("prompt", "请选择卡牌"))
	interaction_panel.visible = true
	use_button.text = "确定"
	use_button.disabled = selected_count < confirm_minimum_card_count or selected_count > maximum_card_count or selected_target_count < confirm_minimum_target_count or selected_target_count > maximum_target_count
	# 取消按钮的可见性与可用性分别由请求声明，两者语义不同、不得混用：
	# allow_cancel 是**规则**声明，表示“取消是否是一个合法提交”；语义上不可取消但仍需要玩家从两个候选中择一的请求
	# （例如强制弃牌）保留“可见但禁用”的取消按钮，用禁用态表达这次选择无法跳过。
	# context.hide_cancel_button 是**表现**声明，由内容层在“本请求根本没有可放弃的出口”时显式置位，
	# 界面据此直接暗置按钮。缺少这条入口时，这类请求只能发 allow_cancel=true，
	# 于是取消按钮既可见又可按，点了却只会重新打开同一个询问，表现为“按了没有任何反应”。
	%CancelButton.visible = not bool((_inline_card_choice.get("context", {}) as Dictionary).get("hide_cancel_button", false))
	%CancelButton.disabled = not bool(_inline_card_choice.get("allow_cancel", false))
	end_play_button.visible = false
	_refresh_component_states()


## 将【振旗】费用选择显示为原操作区中的“弃置手牌 / 失去体力 / 取消”三个按钮；不可支付的弃牌分支保持可见但禁用。
func _refresh_inline_zhenqi_cost_choice_text() -> void:
	# 当前选项 ID 集合；规则层没有提供的费用不能由界面伪造提交。
	var option_ids: Array[String] = []
	for option_variant: Variant in _inline_card_choice.get("control_options", []) as Array:
		# 当前文字选项；只读取稳定 ID，不依赖显示文本来判断费用语义。
		var option: Dictionary = option_variant as Dictionary
		option_ids.append(str(option.get("id", "")))
	selection_label.text = ""
	selection_label.visible = false
	interaction_guide_label.text = "是否发动【振旗】？"
	interaction_panel.visible = true
	use_button.visible = true
	use_button.text = "弃置手牌"
	use_button.custom_minimum_size = ZHENQI_ACTION_BUTTON_MINIMUM_SIZE
	use_button.disabled = not option_ids.has("discard_hand")
	var cancel_button: Button = %CancelButton
	cancel_button.visible = true
	cancel_button.text = "失去体力"
	cancel_button.custom_minimum_size = ZHENQI_ACTION_BUTTON_MINIMUM_SIZE
	cancel_button.disabled = not option_ids.has("lose_hp")
	if _zhenqi_cancel_button != null and is_instance_valid(_zhenqi_cancel_button):
		_zhenqi_cancel_button.visible = true
		_zhenqi_cancel_button.disabled = not bool(_inline_card_choice.get("allow_cancel", false))
	end_play_button.visible = false
	_refresh_component_states()


## 将任意技能的文字选项映射到手牌上方原有操作区；前两项复用确定与取消位置，其余项按需追加同规格按钮。
func _refresh_inline_control_choice_text() -> void:
	# 已过滤后的文字选项；空ID不能提交给权威选择请求，空标签回退为稳定ID以避免出现不可辨认按钮。
	var control_options: Array[Dictionary] = []
	for option_variant: Variant in _inline_card_choice.get("control_options", []) as Array:
		# 当前规则声明的单个选项；只保留具备稳定ID的条目，标签由规则层提供给玩家阅读。
		var option: Dictionary = option_variant as Dictionary
		var option_id: String = str(option.get("id", ""))
		if option_id.is_empty():
			continue
		control_options.append({"id":option_id, "label":str(option.get("label", option_id))})
	# 当前是否允许放弃；取消必须提交 confirmed=false，不能伪造成任一实际技能分支。
	var allow_cancel: bool = bool(_inline_card_choice.get("allow_cancel", false))
	# 规则声明的取消选项ID；非空时该选项本身就是放弃入口，界面不再追加重复的取消按钮。
	var declared_cancel_option_id: String = _get_inline_control_cancel_option_id()
	selection_label.text = ""
	selection_label.visible = false
	interaction_guide_label.text = str(_inline_card_choice.get("prompt", "请选择一项"))
	interaction_panel.visible = true
	end_play_button.visible = false
	# 原确定按钮；始终承担第一项文字选项，保持所有常见二选一询问的固定视觉位置。
	use_button.visible = not control_options.is_empty()
	use_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	use_button.disabled = true
	if not control_options.is_empty():
		_inline_control_primary_option_id = str((control_options[0] as Dictionary).get("id", ""))
		use_button.text = str((control_options[0] as Dictionary).get("label", _inline_control_primary_option_id))
		use_button.disabled = not _is_inline_control_option_submittable(_inline_control_primary_option_id)
	# 原取消按钮；存在第二项时承担第二项，否则保留为真正取消入口。
	var cancel_button: Button = %CancelButton
	cancel_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	if control_options.size() >= 2:
		_inline_control_secondary_option_id = str((control_options[1] as Dictionary).get("id", ""))
		cancel_button.visible = true
		cancel_button.text = str((control_options[1] as Dictionary).get("label", _inline_control_secondary_option_id))
		cancel_button.disabled = _inline_control_secondary_option_id.is_empty() or not _is_inline_control_option_submittable(_inline_control_secondary_option_id)
	elif allow_cancel:
		cancel_button.visible = true
		cancel_button.text = "取消"
		cancel_button.disabled = false
	else:
		cancel_button.visible = false
	# 超出两项的实际选项；按钮仍位于同一操作行，按声明顺序提交对应稳定ID。
	for option_index: int in range(2, control_options.size()):
		var extra_option: Dictionary = control_options[option_index] as Dictionary
		_append_inline_control_option_button(str(extra_option.get("id", "")), str(extra_option.get("label", "")))
		# 新建的实际选项按钮；声明为取消的选项始终可点，其余选项必须同时满足目标与手牌维度。
		var extra_option_button: Button = _inline_control_extra_option_buttons.back() if not _inline_control_extra_option_buttons.is_empty() else null
		if extra_option_button != null:
			extra_option_button.disabled = not _is_inline_control_option_submittable(str(extra_option.get("id", "")))
	# 两项及以上选项且允许放弃时，额外追加真正取消按钮，避免原第二位置既承担选项又丢失放弃语义。
	# 例外：请求已经声明了取消选项时，那个选项就是放弃入口，再追加一个“取消”会让玩家看到两个功能相同的按钮。
	if allow_cancel and control_options.size() >= 2 and declared_cancel_option_id.is_empty():
		_append_inline_control_cancel_button()
	_refresh_component_states()


## 判断文字选项询问的手牌维度是否已经满足；未声明手牌数量范围的控制请求直接返回true。
## 牌堆位次询问通过 min_card_select/max_card_select 声明「恰好一张手牌」，因此两位次按钮在未选牌时保持禁用。
func _is_inline_control_card_selection_ready() -> bool:
	# 手牌维度最少数量；0表示本请求没有手牌要求，例如所有普通控制询问。
	var minimum_card_count: int = int(_inline_card_choice.get("min_card_select", 0))
	# 手牌维度最多数量；缺失时回退为下限，保证“无要求”时上下限同为0。
	var maximum_card_count: int = int(_inline_card_choice.get("max_card_select", minimum_card_count))
	if minimum_card_count <= 0 and maximum_card_count <= 0:
		return true
	# 当前已选手牌数量；只读界面临时数组，不修改权威请求。
	var selected_card_count: int = _inline_selected_card_uids.size()
	return selected_card_count >= minimum_card_count and selected_card_count <= maximum_card_count


## 返回当前控制请求声明的「取消」选项 ID；未声明时返回空字符串。
## 界面因此不需要认识任何具体选项 ID，只按规则层声明的语义把该选项当作放弃入口。
func _get_inline_control_cancel_option_id() -> String:
	return str((_inline_card_choice.get("context", {}) as Dictionary).get(CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID, ""))


## 判断当前控制请求的某个文字选项此刻是否可以提交。
## 声明为取消的选项永远可以提交（放弃不应被选择数量阻塞），其余选项必须同时满足目标与手牌维度。
func _is_inline_control_option_submittable(option_id: String) -> bool:
	if option_id.is_empty():
		return false
	if option_id == _get_inline_control_cancel_option_id():
		return true
	return _is_inline_target_control_selection_ready() and _is_inline_control_card_selection_ready()


## 判断当前文字选项请求的目标维度是否已经满足；非target_control请求没有目标要求并直接返回true。
func _is_inline_target_control_selection_ready() -> bool:
	if str(_inline_card_choice.get("choice_type", "")) != "target_control":
		return true
	# 目标最少数量；由权威请求提供，当前秘策固定为1。
	var minimum_target_count: int = int(_inline_card_choice.get("min_target_select", 1))
	# 目标最多数量；用于防御异常界面状态，正式请求同样固定为1。
	var maximum_target_count: int = int(_inline_card_choice.get("max_target_select", minimum_target_count))
	return _selected_target_ids.size() >= minimum_target_count and _selected_target_ids.size() <= maximum_target_count


## 在当前操作行追加一个实际文字选项按钮；回调只提交稳定ID，不解析技能效果或修改权威请求。
func _append_inline_control_option_button(option_id: String, option_label: String) -> void:
	if option_id.is_empty():
		return
	# 动态选项按钮；尺寸和主题完全复用原确定/取消按钮，避免不同技能产生独立弹窗样式。
	var option_button: Button = Button.new()
	option_button.name = "InlineControlOptionButton_%d" % _inline_control_extra_option_buttons.size()
	option_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	option_button.text = option_label if not option_label.is_empty() else option_id
	option_button.pressed.connect(_on_inline_control_extra_option_pressed.bind(option_id))
	BattleUIStyle.apply_interaction_button(option_button)
	$InteractionPanel/InteractionVBox/ActionRow.add_child(option_button)
	_inline_control_extra_option_buttons.append(option_button)


## 在当前操作行追加真正的放弃按钮；用于已有两个以上实际选项的可取消文字询问。
func _append_inline_control_cancel_button() -> void:
	# 动态取消按钮；名称稳定便于界面回归测试和未来主题脚本定位，不参与规则选择ID集合。
	var cancel_button: Button = Button.new()
	cancel_button.name = "InlineControlCancelButton"
	cancel_button.custom_minimum_size = ACTION_BUTTON_MINIMUM_SIZE
	cancel_button.text = "取消"
	cancel_button.pressed.connect(_on_inline_control_cancel_pressed)
	BattleUIStyle.apply_interaction_button(cancel_button)
	$InteractionPanel/InteractionVBox/ActionRow.add_child(cancel_button)
	_inline_control_extra_option_buttons.append(cancel_button)


## 清理上一次文字选项请求创建的附加按钮；原确定、取消与振旗兼容按钮始终保留在场景中复用。
func _clear_inline_control_extra_option_buttons() -> void:
	for option_button: Button in _inline_control_extra_option_buttons:
		# 当前动态按钮；节点可能已经随场景退出释放，仍需先验证实例有效性。
		if option_button != null and is_instance_valid(option_button):
			if option_button.get_parent() != null:
				option_button.get_parent().remove_child(option_button)
			option_button.queue_free()
	_inline_control_extra_option_buttons.clear()


## 提交动态追加的文字选项；提交前仍确认当前请求属于通用内联控制询问，防止旧按钮迟到触发新请求。
## 规则声明为「取消」的选项走放弃语义（confirmed=false），其余选项都是实际技能分支。
func _on_inline_control_extra_option_pressed(option_id: String) -> void:
	if not _is_inline_control_choice(_inline_card_choice):
		return
	if not option_id.is_empty() and option_id == _get_inline_control_cancel_option_id():
		_submit_inline_control_choice(option_id, false)
		return
	_submit_inline_control_choice(option_id)


## 提交通用内联文字询问的明确放弃；与右键和Esc保持完全相同的confirmed=false语义。
func _on_inline_control_cancel_pressed() -> void:
	if _is_inline_control_choice(_inline_card_choice) and bool(_inline_card_choice.get("allow_cancel", false)):
		_submit_inline_control_choice("", false)


## 将内联文字选项提交为标准选择动作；费用 ID 仍由权威 ChoiceRequest 复核，界面不解释技能效果。
func _submit_inline_control_choice(control_id: String, confirmed: bool = true) -> void:
	if _inline_card_choice.is_empty():
		return
	# 当前请求 ID；同步恢复可能建立下一条请求，提交后只清理仍属于该 ID 的本地副本。
	var request_id: int = int(_inline_card_choice.get("request_id", -1))
	var action: PlayerAction = PlayerAction.new("choose_cards", match_controller.local_human_player_id)
	# 复合请求确认时携带当前目标；取消始终清空目标，保持confirmed=false的唯一放弃语义。
	# 强类型目标结果；避免三元表达式的空数组被推断为弱类型Array后无法赋给Array[int]。
	var selected_target_ids: Array[int] = []
	if confirmed and str(_inline_card_choice.get("choice_type", "")) == "target_control":
		for selected_target_id: int in _selected_target_ids:
			selected_target_ids.append(selected_target_id)
	# 组合请求的手牌维度；只有牌堆位次询问同时提交一张手牌与一个文字选项，取消时两者都必须为空。
	# 强类型手牌结果；与目标维度同理，先构造再写入载荷，避免弱类型数组触发校验失败。
	var selected_card_uids: Array[int] = []
	if confirmed and str(_inline_card_choice.get("choice_type", "")) == CARD_POSITION_CHOICE_TYPE:
		for selected_card_uid: int in _inline_selected_card_uids:
			selected_card_uids.append(selected_card_uid)
	action.payload = {"request_id":request_id, "selected_card_uids":selected_card_uids, "selected_target_ids":selected_target_ids, "selected_control_id":control_id, "confirmed":confirmed}
	if not match_controller.submit_action(action):
		return
	if int(_inline_card_choice.get("request_id", -2)) == request_id:
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
		_selected_target_ids.clear()
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	_render_local_hand()
	_refresh_selection_text()


## 判断一条本地选择是否属于可切换“不响应”的群体锦囊无懈询问。
func _is_group_trick_negation_choice(choice_data: Dictionary) -> bool:
	# 当前请求上下文；只有控制器创建的 trick_negation 响应链具备本功能语义。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "trick_negation":
		return false
	# 当前被响应锦囊定义；全体或全体其他角色目标模式视为群体锦囊。
	var trick_definition: Dictionary = _get_cached_card_definition(str(context.get("trick_id", "")))
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
	_submit_inline_card_choice([], false)


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
		end_play_button.text = "结束阶段"
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
		# 映射值有效性预检；被动画层接管的节点不参与选中态刷新，也不能对已释放对象做强制转换。
		if not is_instance_valid(_card_views.get(card_uid)):
			continue
		(_card_views[card_uid] as CardView).set_selected_state(card_selected)
	# 本地装备堆叠组件；与手牌同步候选位移和选中描边，不创建第二套选择状态。
	_render_local_equipment(_get_player_snapshot(match_controller.local_human_player_id))
	# 合法目标 ID 数组；没有选牌时为空，角色卡保持普通状态。
	# 单目标牌已有选择时仍补充空选择预览中的候选，以支持直接切换目标。
	var legal_target_ids: Array[int] = _get_selectable_target_ids()
	# 当前是否处于目标选择/群体预览流程；非法武将牌仅在该状态下整体变暗。
	var target_selection_active: bool = _is_manual_target_selection_active()
	if str(_snapshot.get("current_phase", "")) == "ai_character_adjustment":
		# 房主调整 AI 的公共合法目标；非房主只显示等待文本，不进入目标选择视觉状态。
		legal_target_ids.clear()
		var pre_game_setup: Dictionary = _snapshot.get("pre_game_setup", {}) as Dictionary
		if int(pre_game_setup.get("host_player_id", -1)) == match_controller.local_human_player_id:
			for target_id_variant: Variant in pre_game_setup.get("target_player_ids", []) as Array:
				legal_target_ids.append(int(target_id_variant))
			target_selection_active = true
		else:
			target_selection_active = false
	for player_id_variant: Variant in _player_views.keys():
		# 当前角色 ID；用于同步合法与已选状态。
		var player_id: int = int(player_id_variant)
		(_player_views[player_id] as PlayerTargetView).set_target_state(legal_target_ids.has(player_id), _selected_target_ids.has(player_id), target_selection_active)
	# 本地玩家目标按钮；自身目标合法或已选择时使用与角色卡一致的颜色语义。
	var self_is_legal: bool = legal_target_ids.has(match_controller.local_human_player_id)
	var self_is_selected: bool = _selected_target_ids.has(match_controller.local_human_player_id)
	local_player_card.set_target_state(self_is_legal, self_is_selected, target_selection_active)
	# 技能目标只在实际发动后播放动态线；选择中的候选与临时目标仅用武将牌描边表达。
	if card_use_animation_layer != null:
		card_use_animation_layer.clear_target_preview_indicator()


## 同步技能选目标预览线；来源与目标锚点直接复用正式卡牌出牌指示线的坐标和绘制组件。
func _refresh_skill_target_preview_indicator() -> void:
	if card_use_animation_layer == null:
		return
	if _inline_card_choice.is_empty():
		card_use_animation_layer.clear_target_preview_indicator()
		return
	# 当前内联选择类型；只有需要在武将牌上选择目标的请求才允许显示预览线。
	var choice_type: String = str(_inline_card_choice.get("choice_type", "card"))
	if choice_type not in ["target", "target_control", "card_target"]:
		card_use_animation_layer.clear_target_preview_indicator()
		return
	# 当前规则上下文；技能定义写入稳定 skill_id，普通内联选牌即使有目标也不应伪装为技能目标线。
	var context: Dictionary = _inline_card_choice.get("context", {}) as Dictionary
	if str(context.get("skill_id", "")).is_empty():
		card_use_animation_layer.clear_target_preview_indicator()
		return
	# 技能拥有者；规则可能要求本地为其他角色完成选择，因此优先读取上下文而非固定本地玩家。
	var skill_owner_id: int = int(context.get("skill_owner_id", match_controller.local_human_player_id))
	# 技能来源锚点；来源座位尚未建立时不绘制，避免从中央弃牌区伪造指示线。
	var source_anchor_result: Dictionary = _try_get_player_indicator_position(skill_owner_id)
	if not bool(source_anchor_result.get("valid", false)):
		card_use_animation_layer.clear_target_preview_indicator()
		return
	# 已选目标的动画层坐标；候选高亮但未选中时不绘制，避免把技能误导为已经指定全部候选。
	var target_positions: Array[Vector2] = []
	for target_id: int in _selected_target_ids:
		# 当前目标锚点；离场或尚未创建的视图只跳过自身，不影响其他有效目标。
		var target_anchor_result: Dictionary = _try_get_player_indicator_position(target_id)
		if bool(target_anchor_result.get("valid", false)):
			target_positions.append(target_anchor_result.get("position", Vector2.ZERO) as Vector2)
	if target_positions.is_empty():
		card_use_animation_layer.clear_target_preview_indicator()
		return
	card_use_animation_layer.set_target_preview_indicator(source_anchor_result.get("position", Vector2.ZERO) as Vector2, target_positions)


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


## 根据本地玩家公开快照刷新托管按钮与手牌覆盖层；界面只读取状态，真正的 AI 接管由控制器处理。
func _refresh_auto_management_controls() -> void:
	# 当前本地玩家公开快照；未进入对局或快照尚未包含本地座次时保持按钮禁用。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	# 当前是否已托管；离线托管仍显示覆盖层，但按钮禁用以表达该连接已经不能自行恢复。
	var auto_managed: bool = bool(local_player.get("auto_managed", false))
	# 当前托管是否因掉线产生；只有联机房主写入 true，客户端本机不应尝试取消。
	var offline_managed: bool = bool(local_player.get("auto_managed_offline", false))
	if auto_managed_hand_overlay != null:
		auto_managed_hand_overlay.configure(auto_managed)
	if auto_manage_button == null:
		return
	auto_manage_button.text = "取消托管" if auto_managed else "托管"
	auto_manage_button.disabled = local_player.is_empty() or bool(_snapshot.get("game_over", false)) or not bool(local_player.get("alive", false)) or offline_managed
	if auto_managed:
		# 进入托管后清除仅属于本地 UI 的未提交选择，避免遮罩关闭前残留可点击的牌或目标高亮。
		_selected_card_uid = -1
		_selected_target_ids.clear()
		_inline_card_choice.clear()
		_inline_selected_card_uids.clear()
		_active_response_skill_id = ""
		_modal_choice_request_id = -1
		_modal_card_choice_request.clear()
		_clear_equipment_action()
		card_selection_panel.close()


## 切换本地玩家的手动托管状态；动作会在 LAN 客户端上行到房主，在离线或房主端由同一权威入口执行。
func _on_auto_manage_pressed() -> void:
	# 当前本地玩家快照；无有效玩家或离线托管时按钮理论上已禁用，此处仍防御性拒绝。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	if local_player.is_empty() or bool(local_player.get("auto_managed_offline", false)):
		return
	# 当前开关目标；由最新权威快照反转，避免本地快速连点维护第二份状态。
	var enabled: bool = not bool(local_player.get("auto_managed", false))
	var action: PlayerAction = PlayerAction.new("set_auto_managed", match_controller.local_human_player_id)
	action.payload = {"enabled":enabled}
	match_controller.submit_action(action)


## 判断当前是否为本地玩家的有效出牌阶段；所有交互控件共用该条件。
func _can_local_player_act() -> bool:
	# 当前本地玩家快照；手动或离线托管均必须在表现层禁用一切常规操作，控制器仍会再次权威拒绝。
	var local_player: Dictionary = _get_player_snapshot(match_controller.local_human_player_id)
	if bool(local_player.get("auto_managed", false)):
		return false
	# 当前运行时选择；阶段间隔内仍保留上一阶段名称，但活动 chooseToUse 已关闭，此时任何出牌控件都必须禁用。
	var current_choice: Dictionary = _snapshot.get("current_choice_request", {}) as Dictionary
	return int(_snapshot.get("current_player_id", -1)) == match_controller.local_human_player_id and str(_snapshot.get("current_phase", "")) == "play" and not bool(_snapshot.get("game_over", false)) and str(current_choice.get("choice_type", "")) == "use" and int(current_choice.get("actor_id", -1)) == match_controller.local_human_player_id


## 按玩家 ID 返回当前快照中的只读玩家字典；调用方不得修改返回值或其嵌套数组。
func _get_player_snapshot(player_id: int) -> Dictionary:
	return _player_snapshots_by_id.get(player_id, {}) as Dictionary


## 返回缓存的卡牌静态定义；配置只在 GameDatabase 初始化时加载，界面运行期间不得修改返回字典。
func _get_cached_card_definition(definition_id: String) -> Dictionary:
	if definition_id.is_empty():
		return {}
	if not _card_definition_cache.has(definition_id):
		_card_definition_cache[definition_id] = GameDatabase.get_card(definition_id)
	return _card_definition_cache.get(definition_id, {}) as Dictionary


## 返回缓存的武将静态定义；缓存消除每个状态快照为全桌角色重复创建配置副本的开销。
func _get_cached_character_definition(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not _character_definition_cache.has(character_id):
		_character_definition_cache[character_id] = GameDatabase.get_character(character_id)
	return _character_definition_cache.get(character_id, {}) as Dictionary


## 返回缓存的势力静态定义；空势力 ID 返回空字典并由牌面组件使用稳定默认表现。
func _get_cached_faction_definition(faction_id: String) -> Dictionary:
	if faction_id.is_empty():
		return {}
	if not _faction_definition_cache.has(faction_id):
		_faction_definition_cache[faction_id] = GameDatabase.get_faction(faction_id)
	return _faction_definition_cache.get(faction_id, {}) as Dictionary


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
	return {"setup":"准备", "character_selection":"选将阶段", "start":"开始阶段", "judgment":"判定阶段", "draw":"摸牌阶段", "play":"出牌阶段", "choice":"等待选择", "opportunity":"选择机缘", "discard":"弃牌阶段", "finish":"结束阶段", "game_over":"对局结束"}.get(phase, phase)


## 返回一至十号座次的中文数字；座次标签属于游戏内座位容器，超出当前模式上限时回退阿拉伯数字。
func _seat_text(seat_number: int) -> String:
	return {1:"一", 2:"二", 3:"三", 4:"四", 5:"五", 6:"六", 7:"七", 8:"八", 9:"九", 10:"十"}.get(seat_number, str(seat_number))
