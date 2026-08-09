class_name MainMenu
extends Control

## 主菜单组件。该组件只管理启动前的模式选择、显示设置与开局请求，不直接创建或修改任何对局状态。

## 玩家确认开始身份局时发出的信号；参数为设置中确认的下一局人数，由牌桌统一调用对局控制器。
signal start_game_requested(player_count: int)

## 玩家在“对局回放”内容页请求播放回放时发出；参数为回放目录内的稳定文件名。
## 主菜单只转发意图；回放载入与第一视角整局重演由牌桌统一执行，失败经 show_replay_playback_error 回显。
signal replay_playback_requested(replay_file_name: String)

## 标准身份局允许的最少玩家人数；默认2人与身份规则支持范围一致，运行时可在检查器中调整显示范围。
@export_range(2, 10, 1) var minimum_player_count: int = 2

## 标准身份局允许的最多玩家人数；默认10人与身份规则支持范围一致，运行时可在检查器中调整显示范围。
@export_range(2, 10, 1) var maximum_player_count: int = 10

## 预览背景叠加当前主题面板色的透明度；默认0.18保证文字清晰且保留身份模式原图主体，运行时只影响视觉明暗。
@export_range(0.0, 1.0, 0.01) var preview_shade_opacity: float = 0.18

## 预览标题信息板的不透明度；默认0.82可在明亮原画上稳定承托文字，运行时只影响主菜单视觉层级。
@export_range(0.0, 1.0, 0.01) var preview_summary_opacity: float = 0.82

## 预览底部操作栏的不透明度；默认0.88用于隔离原画高亮区域与按钮，运行时不影响任何开局参数。
@export_range(0.0, 1.0, 0.01) var preview_action_opacity: float = 0.88

## 设置模态遮罩的不透明度；默认0.86确保设置面板成为唯一视觉焦点，运行时仅阻断主菜单底层输入。
@export_range(0.0, 1.0, 0.01) var settings_backdrop_opacity: float = 0.86

## 左侧模式卡片选中态相对主题操作色的加深比例；默认0.28让身份模式、斗地主与2v2的内部棕色形成清晰选中层级，运行时仅影响视觉表现，可在检查器中按主题对比度调整。
@export_range(0.0, 0.6, 0.01) var mode_selected_background_darkening: float = 0.28

## 左侧模式列表纵向滚动条宽度；默认12像素兼顾鼠标拖动与紧凑侧栏，运行时只影响界面浏览区域。
@export_range(8.0, 24.0, 1.0) var mode_scroll_bar_width: float = 12.0

## 左侧模式列表每次滚轮的基础移动距离；默认72像素接近一张模式卡高度，运行时只影响浏览手感。
@export_range(16.0, 240.0, 1.0) var mode_scroll_wheel_step: float = 72.0

## 身份模式正常待机时显示的状态文字；集中定义可避免按钮区与错误提示使用不同默认文案。
## 待机状态保留空文本，以便底部操作栏只在开局反馈或错误发生时显示状态信息。
const MODE_READY_STATUS_TEXT: String = ""

## 开局请求同步处理期间显示的状态文字；若控制器拒绝请求，会被具体错误原因立即替换。
const STARTING_STATUS_TEXT_IDENTITY: String = "正在创建身份局……"

## 斗地主开局请求处理期间显示的状态文字。
const STARTING_STATUS_TEXT_DOUDIZHU: String = "正在创建斗地主对局……"

## 2v2 开局请求处理期间显示的状态文字。
const STARTING_STATUS_TEXT_TEAM2V2: String = "正在创建2v2对局……"

## 1v1车轮战创建中的稳定状态文本；只影响主菜单反馈，不参与规则判断。
const STARTING_STATUS_TEXT_WHEEL_DUEL: String = "正在创建1v1车轮战对局……"

## 机缘大乱斗创建中的稳定状态文本；只影响主菜单反馈，不参与规则判断。
const STARTING_STATUS_TEXT_OPPORTUNITY_BRAWL: String = "正在创建机缘大乱斗对局……"

## 过关斩将创建中的稳定状态文本；只影响主菜单反馈，不参与规则判断。
const STARTING_STATUS_TEXT_CONQUEST: String = "正在创建过关斩将对局……"

## 模式详情入口的主菜单内容层级；默认1使按钮高于预览原画但低于设置遮罩的第2层，设置打开后不会遮挡任何设置控件或截获输入。
const MODE_DETAILS_BUTTON_Z_INDEX: int = 1

## 模式详情全屏遮罩层级；默认8高于主菜单设置面板，保证详情作为当前最高优先级模态窗口。
const MODE_DETAILS_BACKDROP_Z_INDEX: int = 8

## 模式详情正文面板层级；默认9高于自身遮罩1层，保证正文、滚动区与关闭按钮可接收输入。
const MODE_DETAILS_PANEL_Z_INDEX: int = 9

## 主菜单模式选择内容页稳定标识；只用于顶部导航三态切换，不写入玩家设置。
const CONTENT_PAGE_MODES: String = "modes"

## 主菜单联机设置内容页稳定标识；只用于顶部导航三态切换，不创建网络连接。
const CONTENT_PAGE_ONLINE_SETTINGS: String = "online_settings"

## 主菜单所有卡牌内容页稳定标识；只用于顶部导航三态切换，不创建卡牌实体或对局状态。
const CONTENT_PAGE_ALL_CARDS: String = "all_cards"

## 主菜单对局回放内容页稳定标识；只用于顶部导航四态切换，不创建对局、录制或网络状态。
const CONTENT_PAGE_MATCH_REPLAY: String = "match_replay"

## 支持详情弹窗的模式说明；键为稳定模式ID，标题与正文只用于长期玩法说明，不参与规则判断。
const MODE_DETAILS_BY_MODE: Dictionary = {
	GameSettings.MATCH_MODE_DOUDIZHU:{
		"title":"斗地主模式详情",
		"description":"支持3人或5人。3人局由1名地主对抗2名农民；5人局由一、三号位的2名地主对抗3名农民。身份开局明置，全员同时选将。地主体力上限+1并获得【飞扬】与【跋扈】，农民获得【共苦】。击杀全部对方阵营即可获胜。",
	},
	GameSettings.MATCH_MODE_OPPORTUNITY_BRAWL:{
		"title":"机缘大乱斗模式详情",
		"description":"支持2—10人并继承身份模式的阵营与胜负规则。每轮每个普通回合按1/N概率触发机缘；若整轮都未触发，则在轮末必定触发一次。触发后每名存活且未死亡的角色从3张私有机缘中选择1张，全员选择完成后从当前回合角色开始逆时针依次结算。灰色机缘不会进入随机候选。",
	},
	GameSettings.MATCH_MODE_CONQUEST:{
		"title":"过关斩将模式详情",
		"description":"离线为1名玩家对战1名AI，联机为2至4名玩家对战等量AI，玩家方先手。开局玩家方选择1次机缘；清空本层全部敌方武将后，敌方会弃置全部区域牌、统一提升关卡、随机换将并获得累计强化，随后玩家方再选择1次机缘。拥有复活次数时，玩家死亡会弃置区域内所有牌、将体力回复至体力上限并摸4张牌，随后继续游戏。\n\n难度一：增加2点体力上限；摸牌阶段额外摸一张牌；初始手牌数+2；出牌阶段使用【杀】的次数上限+1；复活次数+1。\n难度二：增加1点体力上限；摸牌阶段额外摸一张牌；初始手牌数+2；出牌阶段使用【杀】的次数上限+1。\n难度三：增加1点体力上限；初始手牌数+2；出牌阶段使用【杀】的次数上限+1。\n难度四：初始手牌数+1；出牌阶段使用【杀】的次数上限+1。\n难度五：无额外增益。",
	},
}

## 当前主菜单选中的下一局模式稳定 ID；与 GameSettings.next_match_mode 同步。
var _selected_match_mode: String = GameSettings.MATCH_MODE_IDENTITY if GameSettings != null else "identity"

## 顶部模式导航栏；目前只承载唯一的“身份模式”选项，后续新增模式仍可复用同一容器与主题样式。
## 补充：当前容器承载“模式选择”“联机设置”“所有卡牌”三个对等内容页，具体游戏模式仍在模式选择页左侧列表中切换。
@onready var _top_navigation: PanelContainer = %MainMenuTopNavigation

## 主菜单外框；左侧模式列表与右侧模式预览共同位于此容器内，颜色始终由当前 UI 风格提供。
@onready var _main_frame: PanelContainer = %MainMenuFrame

## 左侧模式选择区域；标题保持固定，模式卡通过内部滚动窗口扩展而不压缩原版卡片规格。
@onready var _mode_list: PanelContainer = %MainMenuModeList

## 左侧模式卡滚动窗口；只滚动模式卡片，固定标题、右侧预览和底部操作栏不随列表移动。
@onready var _mode_scroll: ScrollContainer = %MainMenuModeScroll

## 右侧身份模式预览区域；承载可裁剪的模式背景与底部操作按钮，不保存玩法状态。
@onready var _preview_panel: PanelContainer = %MainMenuPreviewPanel

## 主菜单全屏底色；使用主题外底色遮住尚未开始的牌桌静态节点，避免启动阶段呈现局内信息。
@onready var _menu_background: ColorRect = %MainMenuBackground

## 主菜单背景内容面；在最外层底色上提供主题桌面色层次，不绘制参考图中的毛玻璃游戏背景。
@onready var _menu_surface: ColorRect = %MainMenuBackgroundSurface

## 身份模式预览遮罩；只改善前景文本可读性，不负责复刻参考图中的游戏毛玻璃背景。
@onready var _preview_shade: ColorRect = %MainMenuPreviewShade

## 顶部身份模式选项的选中指示线；始终读取当前主题强调色，不保存独立模式状态。
@onready var _top_mode_indicator: ColorRect = %TopIdentityModeIndicator

## 左侧身份模式卡片的选中指示线；与按钮按下状态共同表达当前唯一可用模式。
@onready var _mode_card_indicator: ColorRect = %IdentityModeIndicator

## 左侧斗地主模式按钮指示条；选中斗地主时显示主题强调色。
@onready var _doudizhu_mode_card_indicator: ColorRect = %DouDizhuModeIndicator

## 左侧 2v2 模式按钮指示条；选中 2v2 时显示主题强调色。
@onready var _team2v2_mode_card_indicator: ColorRect = %Team2v2ModeIndicator

## 左侧1v1车轮战模式按钮指示条；选中时显示主题强调色。
@onready var _wheel_duel_mode_card_indicator: ColorRect = %WheelDuelModeIndicator

## 左侧机缘大乱斗模式按钮指示条；选中时显示主题强调色。
@onready var _opportunity_brawl_mode_card_indicator: ColorRect = %OpportunityBrawlModeIndicator

## 左侧斗地主模式卡片按钮；与身份模式并列，只负责写入下一局模式配置。
@onready var _doudizhu_mode_button: Button = %DouDizhuModeButton

## 左侧 2v2 模式卡片按钮；与身份模式、斗地主并列，写入下一局 team2v2 配置。
@onready var _team2v2_mode_button: Button = %Team2v2ModeButton

## 左侧1v1车轮战模式卡片按钮；固定2人并启用专属候选设置。
@onready var _wheel_duel_mode_button: Button = %WheelDuelModeButton

## 左侧机缘大乱斗模式卡片按钮；继承身份规则人数并启用机缘组件。
@onready var _opportunity_brawl_mode_button: Button = %OpportunityBrawlModeButton

## 左侧过关斩将模式卡片按钮；固定一名本地玩家与一名敌方AI，并使用专属关卡增强规则。
@onready var _conquest_mode_button: Button = %ConquestModeButton

## 左侧过关斩将模式按钮指示条；选中时显示主题强调色。
@onready var _conquest_mode_card_indicator: ColorRect = %ConquestModeIndicator

## 预览右上角模式摘要板；使用局部主题底板保证标题不会被明亮角色原画吞没。
@onready var _mode_summary_panel: PanelContainer = %MainMenuModeSummaryPanel

## 预览左上角模式标签；遮盖覆盖裁剪后可能残留的原图品牌碎片，并以当前主题标明标准身份局。
@onready var _preview_mode_badge: PanelContainer = %MainMenuPreviewModeBadge

## 预览底部操作栏；承载当前模式状态、设置与开始游戏按钮，并隔离原画高亮区域。
@onready var _action_panel: PanelContainer = %MainMenuActionPanel

## 顶部身份模式选项；当前唯一的游戏模式入口，按下后仅重新确认身份模式为选中状态。
## 补充：该按钮现作为“模式选择”内容页入口；从其他顶部页返回时继续沿用原入口并恢复身份模式预览。
@onready var _top_identity_mode_button: Button = %TopIdentityModeButton

## 顶部联机设置入口；位于“模式选择”右侧，与模式选择对等切换主菜单客户区内容，不直接建立网络连接。
@onready var _online_settings_button: Button = %MainMenuOnlineSettingsButton

## 顶部联机设置选中指示线；与模式选择指示线共用主题强调色，仅表达当前内容页。
@onready var _top_online_settings_indicator: ColorRect = %TopOnlineSettingsIndicator

## 顶部所有卡牌入口；与模式选择、联机设置对等切换主菜单客户区，不读取或修改对局状态。
@onready var _all_cards_button: Button = %MainMenuAllCardsButton

## 顶部所有卡牌选中指示线；只表达当前内容页，不保存分类或搜索状态。
@onready var _top_all_cards_indicator: ColorRect = %TopAllCardsIndicator

## 顶部对局回放入口；位于“所有卡牌”右侧，与其他内容页对等切换主菜单客户区，不读取或修改对局状态。
## 使用 get_node_or_null 防御旧场景缓存缺失该节点；缺失时回放入口不可用但不影响其他导航页。
@onready var _match_replay_button: Button = get_node_or_null("%MainMenuMatchReplayButton") as Button

## 顶部对局回放选中指示线；只表达当前内容页，不保存回放列表或播放进度。
@onready var _top_match_replay_indicator: ColorRect = get_node_or_null("%TopMatchReplayIndicator") as ColorRect

## 左侧身份模式按钮；对应参考布局中的模式选择列表，目前是唯一可选择的模式。
@onready var _identity_mode_button: Button = %IdentityModeButton

## 身份模式标题；显示当前右侧预览所代表的游戏模式，不作为规则状态来源。
@onready var _mode_title: Label = %MainMenuModeTitle

## 身份模式说明；用于在没有其他模式时明确当前可启动的是标准身份局。
@onready var _mode_description: Label = %MainMenuModeDescription

## 开始游戏按钮；点击后关闭主菜单并把人数请求交给牌桌的统一开局入口。
## 实际关闭时机由牌桌在权威对局创建成功后确认；请求失败时该按钮与主菜单继续保持可用。
@onready var _start_game_button: Button = %StartGameButton

## 设置按钮；位于开始游戏按钮左侧，替代参考布局中的商店入口。
@onready var _settings_button: Button = %MainMenuSettingsButton

## 局域网联机按钮；打开独立大厅组件，不直接创建 ENet、玩家状态或权威对局。
@onready var _lan_button: Button = %MainMenuLanButton

## 局域网大厅组件；只负责连接表单与成员快照展示，实际网络动作由牌桌协调器接收其信号。
@onready var _lan_lobby_panel: LanLobbyPanel = %LanLobbyPanel

## 联机资料设置组件；只编辑全局玩家名称与武将形象，作为与模式预览对等的主菜单客户区内容页，不弹出独立遮罩。
@onready var _online_settings_panel: OnlineSettingsPanel = %OnlineSettingsPanel

## 所有卡牌浏览组件；只读取三类静态内容目录并提供分类搜索与资料查看。
@onready var _all_cards_panel: AllCardsPanel = %AllCardsPanel

## 对局回放浏览与播放组件；只读取本地回放文件与静态武将定义，不创建对局或网络状态。
@onready var _match_replay_panel: MatchReplayPanel = get_node_or_null("%MatchReplayPanel") as MatchReplayPanel

## 联机大厅组件；连接成功后接管全屏座位、聊天与房间控制，主菜单只维护焦点和场景覆盖边界。
@onready var _online_lobby_panel: OnlineLobbyPanel = %OnlineLobbyPanel

## 设置浮层；默认隐藏，打开后允许修改全局显示与下一局人数配置。
@onready var _settings_panel: PanelContainer = %MainMenuSettingsPanel

## 设置浮层的全屏模态遮罩；打开设置时阻止模式与开局按钮接收误触，点击空白处可返回主菜单。
@onready var _settings_backdrop: ColorRect = %MainMenuSettingsBackdrop

## 设置关闭按钮；仅关闭设置浮层并返回主菜单，不改变已选择的游戏模式或未开始的对局状态。
@onready var _settings_close_button: Button = %MainMenuSettingsCloseButton

## 卡牌名称下拉框；选项元数据保存全局名称模式枚举，界面只显示玩家可见名称。
@onready var _card_name_option: OptionButton = %MainMenuCardNameOption

## UI 风格下拉框；选项元数据保存稳定风格标识，界面只显示注册表提供的名称。
@onready var _ui_style_option: OptionButton = %MainMenuUiStyleOption

## 自动身份标记复选框；开关仅影响本地显示推测，不写入对局规则状态。
@onready var _auto_identity_marking_checkbox: CheckBox = %MainMenuAutoIdentityMarkingCheckBox

## 离线控制全部角色开关；联机入口打开或已连接时由牌桌协调器隐藏，进行中的离线对局会实时响应变化。
@onready var _control_all_characters_checkbox: CheckBox = %MainMenuControlAllCharactersCheckBox

## 自选全武将、座次与身份开关；仅在之后由本机创建或房主创建的新对局中生效。
## 过关斩将显示为“自选武将”，只开放全部武将列表，不允许修改固定的一号位红方身份。
@onready var _custom_character_assignment_checkbox: CheckBox = %MainMenuCustomCharacterAssignmentCheckBox

## 房主调整全部 AI 武将开关；初次选将完成后决定是否插入开局前调整阶段。
@onready var _customize_ai_characters_checkbox: CheckBox = %MainMenuCustomizeAiCharactersCheckBox

## 手气卡数量下拉框；选项元数据保存0至5、10或-1，不依赖显示文字解析张数。
@onready var _mulligan_limit_option: OptionButton = %MainMenuMulliganLimitOption

## AI 使用手气卡开关；实际刷新张数仍读取手气卡数量设置。
@onready var _ai_uses_mulligan_checkbox: CheckBox = %MainMenuAiUsesMulliganCheckBox

## 换将卡数量下拉框；元数据保存0、3、5、8、10或20，作为房主下一局权威规则。
@onready var _character_replacement_count_option: OptionButton = %MainMenuCharacterReplacementCountOption

## 随机选将牌数下拉框；元数据保存1至20，领袖技武将不计入该普通候选数量。
@onready var _character_candidate_count_option: OptionButton = %MainMenuCharacterCandidateCountOption

## 过关斩将难度下拉框；元数据保存一至五，仅在过关斩将设置页显示并影响下一局。
@onready var _conquest_difficulty_option: OptionButton = %MainMenuConquestDifficultyOption

## 过关斩将难度整行容器；其他模式隐藏且不占用设置面板布局高度。
@onready var _conquest_difficulty_row: Control = %MainMenuConquestDifficultyRow

## 过关斩将机缘选择方式下拉框；元数据保存vote/individual稳定ID，仅在过关斩将设置页显示并影响下一局。
@onready var _conquest_opportunity_choice_option: OptionButton = %MainMenuConquestOpportunityChoiceOption

## 过关斩将机缘选择方式整行容器；其他模式隐藏且不占用设置面板布局高度。
@onready var _conquest_opportunity_choice_row: Control = %MainMenuConquestOpportunityChoiceRow

## 普通模式自选规则控件；车轮战使用独立抓将规则时隐藏。
@onready var _custom_character_assignment_row: Control = _custom_character_assignment_checkbox

## 普通模式AI武将调整控件；车轮战抓将阶段由专属服务处理时隐藏。
@onready var _customize_ai_characters_row: Control = _customize_ai_characters_checkbox

## 普通模式换将卡整行；车轮战改用固定公共候选池，不显示该设置。
@onready var _character_replacement_count_row: Control = _character_replacement_count_option.get_parent() as Control

## 普通模式随机候选整行；车轮战显示明置与暗置候选数量代替该设置。
@onready var _character_candidate_count_row: Control = _character_candidate_count_option.get_parent() as Control

## AI 响应速度标签；显示下一次 AI 行动或响应会使用的等待秒数。
@onready var _ai_response_delay_label: Label = %MainMenuAiResponseDelayLabel

## AI 响应速度滑条；修改后立即写入全局设置，并影响之后创建的 AI 等待任务。
@onready var _ai_response_delay_slider: HSlider = %MainMenuAiResponseDelaySlider

## 游戏速度标签；显示后续阶段切换和自动响应的最小间隔秒数。
@onready var _game_speed_label: Label = %MainMenuGameSpeedLabel

## 游戏速度滑条；修改后立即写入全局设置，不重置已经开始的计时任务。
@onready var _game_speed_slider: HSlider = %MainMenuGameSpeedSlider

## 下一局人数输入框；开始游戏时读取该控件，限制为标准身份局支持的2至10人范围。
@onready var _player_count_input: SpinBox = %MainMenuPlayerCountInput

## 游戏人数整行容器；车轮战固定2人时隐藏，普通模式继续显示各自独立人数。
@onready var _player_count_row: Control = _player_count_input.get_parent() as Control

## 车轮战明置候选数量输入框；范围3至20，默认6，仅在该模式选中时显示。
@onready var _wheel_duel_face_up_candidate_input: SpinBox = %WheelDuelFaceUpCandidateInput

## 车轮战暗置候选数量输入框；范围3至20，默认4，仅在该模式选中时显示。
@onready var _wheel_duel_face_down_candidate_input: SpinBox = %WheelDuelFaceDownCandidateInput

## 底部操作栏状态文字；正常显示模式选择，开局失败时在原位展示控制器返回的具体原因。
@onready var _menu_status_label: Label = %MainMenuStatusLabel

## 设置标题下的即时生效提示；颜色由当前主题的次级文字语义统一提供。
@onready var _settings_hint_label: Label = %MainMenuSettingsHint

## 当前状态文字是否表示错误；主题切换时据此保留危险色，而不是把错误重绘成普通提示。
var _status_is_error: bool = false

## 局域网大厅入口使用的默认端口；由牌桌从 NetworkGateway 检查器配置同步，默认7000仅作为独立组件测试回退。
var _lan_default_port: int = 7000

## 设置模态打开前的主菜单底层控件焦点模式；键为控件实例、值为原始 FocusMode，关闭设置后原样恢复，运行时不保存业务状态。
var _background_focus_modes: Dictionary = {}

## 主菜单覆盖前的局内控件焦点模式；主菜单可见期间阻止键盘与手柄导航进入隐藏牌桌，进入对局后原样恢复。
var _covered_interface_focus_modes: Dictionary = {}

## 模式列表滚动同步保护；同步 ScrollContainer 与 VScrollBar 时暂时阻断互相触发的 value_changed 回调。
var _mode_scroll_syncing: bool = false

## 模式预览左上角详情按钮；只在斗地主、机缘大乱斗与过关斩将选项页显示。
var _mode_details_button: Button

## 模式详情全屏遮罩；打开说明时阻断底层模式、设置与开局按钮输入。
var _mode_details_backdrop: ColorRect

## 模式详情居中面板；承载标题、可换行正文与关闭按钮，不保存任何玩法状态。
var _mode_details_panel: PanelContainer

## 模式详情标题标签；打开时从当前模式稳定说明表刷新。
var _mode_details_title_label: Label

## 模式详情正文标签；使用自动换行完整展示当前模式长期规则。
var _mode_details_description_label: Label

## 模式详情关闭按钮；关闭后把焦点归还详情入口。
var _mode_details_close_button: Button


## 初始化主菜单交互与全局设置同步；主菜单进入场景后始终覆盖尚未开局的牌桌。
func _ready() -> void:
	# 当前菜单绘制与输入层；提升到同级节点最前方，确保选将遮罩和局内菜单不会遮挡启动入口。
	call_deferred("_move_to_input_front")
	_build_mode_details_interface()
	visibility_changed.connect(_on_visibility_changed)
	_top_identity_mode_button.pressed.connect(_select_identity_mode)
	_identity_mode_button.pressed.connect(_select_identity_mode)
	_doudizhu_mode_button.pressed.connect(_select_doudizhu_mode)
	_team2v2_mode_button.pressed.connect(_select_team2v2_mode)
	_wheel_duel_mode_button.pressed.connect(_select_wheel_duel_mode)
	_opportunity_brawl_mode_button.pressed.connect(_select_opportunity_brawl_mode)
	_conquest_mode_button.pressed.connect(_select_conquest_mode)
	_online_settings_button.pressed.connect(_open_online_settings)
	_all_cards_button.pressed.connect(_open_all_cards)
	if _match_replay_button != null:
		_match_replay_button.pressed.connect(_open_match_replay)
	_settings_button.pressed.connect(_open_settings)
	_lan_button.pressed.connect(_open_lan_panel)
	_online_settings_panel.close_requested.connect(_close_online_settings)
	_all_cards_panel.close_requested.connect(_close_all_cards)
	if _match_replay_panel != null:
		_match_replay_panel.close_requested.connect(_close_match_replay)
		_match_replay_panel.playback_requested.connect(_on_replay_playback_requested)
	_settings_close_button.pressed.connect(_close_settings)
	_settings_backdrop.gui_input.connect(_on_settings_backdrop_gui_input)
	# 模式列表滚轮由主菜单统一接收，避免模式卡片按钮先消费滚轮后父级滚动容器无法更新。
	_mode_scroll.get_v_scroll_bar().value_changed.connect(_on_mode_scroll_bar_value_changed)
	_start_game_button.pressed.connect(_request_start_game)
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 1.0
	_player_count_input.value = GameSettings.next_match_player_count
	# 当前人数输入提交策略；键入数值后立即同步 Range，防止按下开始游戏时读取焦点尚未提交的旧值。
	_player_count_input.update_on_text_changed = true
	_player_count_input.value_changed.connect(_on_next_player_count_changed)
	_wheel_duel_face_up_candidate_input.set_value_no_signal(GameSettings.wheel_duel_face_up_candidate_count)
	_wheel_duel_face_up_candidate_input.value_changed.connect(_on_wheel_duel_face_up_candidate_count_changed)
	_wheel_duel_face_down_candidate_input.set_value_no_signal(GameSettings.wheel_duel_face_down_candidate_count)
	_wheel_duel_face_down_candidate_input.value_changed.connect(_on_wheel_duel_face_down_candidate_count_changed)
	_ai_response_delay_slider.min_value = GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.max_value = GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.step = GameSettings.AI_RESPONSE_DELAY_STEP_SECONDS
	_ai_response_delay_slider.value = GameSettings.ai_response_delay_seconds
	_ai_response_delay_slider.value_changed.connect(_on_ai_response_delay_changed)
	_game_speed_slider.min_value = GameSettings.MIN_GAME_SPEED_INTERVAL_SECONDS
	_game_speed_slider.max_value = GameSettings.MAX_GAME_SPEED_INTERVAL_SECONDS
	_game_speed_slider.step = GameSettings.GAME_SPEED_INTERVAL_STEP_SECONDS
	_game_speed_slider.value = GameSettings.game_speed_interval_seconds
	_game_speed_slider.value_changed.connect(_on_game_speed_changed)
	_populate_card_name_options()
	_card_name_option.item_selected.connect(_on_card_name_selected)
	_populate_ui_style_options()
	_ui_style_option.item_selected.connect(_on_ui_style_selected)
	_populate_conquest_difficulty_options()
	_conquest_difficulty_option.item_selected.connect(_on_conquest_difficulty_selected)
	_populate_conquest_opportunity_choice_options()
	_conquest_opportunity_choice_option.item_selected.connect(_on_conquest_opportunity_choice_selected)
	_auto_identity_marking_checkbox.set_pressed_no_signal(GameSettings.auto_identity_marking_enabled)
	_auto_identity_marking_checkbox.toggled.connect(_on_auto_identity_marking_toggled)
	_control_all_characters_checkbox.set_pressed_no_signal(GameSettings.control_all_characters_enabled)
	_control_all_characters_checkbox.toggled.connect(GameSettings.set_control_all_characters_enabled)
	_custom_character_assignment_checkbox.set_pressed_no_signal(GameSettings.custom_character_assignment_enabled)
	_custom_character_assignment_checkbox.toggled.connect(GameSettings.set_custom_character_assignment_enabled)
	_customize_ai_characters_checkbox.set_pressed_no_signal(GameSettings.customize_ai_characters_enabled)
	_customize_ai_characters_checkbox.toggled.connect(GameSettings.set_customize_ai_characters_enabled)
	_populate_mulligan_limit_options()
	_mulligan_limit_option.item_selected.connect(_on_mulligan_limit_selected)
	_ai_uses_mulligan_checkbox.set_pressed_no_signal(GameSettings.ai_uses_mulligan_enabled)
	_ai_uses_mulligan_checkbox.toggled.connect(GameSettings.set_ai_uses_mulligan_enabled)
	_populate_character_replacement_count_options()
	_character_replacement_count_option.item_selected.connect(_on_character_replacement_count_selected)
	_populate_character_candidate_count_options()
	_character_candidate_count_option.item_selected.connect(_on_character_candidate_count_selected)
	GameSettings.card_name_mode_changed.connect(_refresh_card_name_text)
	GameSettings.ui_style_changed.connect(_refresh_ui_style_selection)
	GameSettings.ai_response_delay_changed.connect(_refresh_ai_response_delay_text)
	GameSettings.game_speed_changed.connect(_refresh_game_speed_text)
	GameSettings.auto_identity_marking_changed.connect(_refresh_auto_identity_marking_state)
	GameSettings.control_all_characters_changed.connect(_control_all_characters_checkbox.set_pressed_no_signal)
	GameSettings.custom_character_assignment_changed.connect(_custom_character_assignment_checkbox.set_pressed_no_signal)
	GameSettings.customize_ai_characters_changed.connect(_customize_ai_characters_checkbox.set_pressed_no_signal)
	GameSettings.mulligan_limit_changed.connect(_refresh_mulligan_limit_selection)
	GameSettings.ai_uses_mulligan_changed.connect(_ai_uses_mulligan_checkbox.set_pressed_no_signal)
	GameSettings.character_replacement_count_changed.connect(_refresh_active_character_replacement_count_selection)
	GameSettings.conquest_character_replacement_count_changed.connect(_refresh_active_character_replacement_count_selection)
	GameSettings.character_candidate_count_changed.connect(_refresh_active_character_candidate_count_selection)
	GameSettings.conquest_character_candidate_count_changed.connect(_refresh_active_character_candidate_count_selection)
	GameSettings.conquest_difficulty_changed.connect(_refresh_conquest_difficulty_selection)
	GameSettings.conquest_opportunity_choice_mode_changed.connect(_refresh_conquest_opportunity_choice_selection)
	GameSettings.next_match_player_count_changed.connect(set_next_player_count)
	_suspend_covered_interface_focus()
	_set_settings_visible(false)
	_restore_selected_match_mode()
	_refresh_card_name_text()
	_refresh_ui_style_selection(GameSettings.ui_style_id)
	_refresh_ai_response_delay_text(GameSettings.ai_response_delay_seconds)
	_refresh_game_speed_text(GameSettings.game_speed_interval_seconds)
	_refresh_mulligan_limit_selection(GameSettings.mulligan_limit)
	_refresh_active_character_replacement_count_selection()
	_refresh_active_character_candidate_count_selection()
	_refresh_conquest_difficulty_selection(GameSettings.conquest_difficulty)
	_refresh_conquest_opportunity_choice_selection(GameSettings.conquest_opportunity_choice_mode)
	refresh_ui_style()
	call_deferred("_focus_start_game_button")


## 在父节点完成初始化后提升主菜单分支；保证启动页面的绘制顺序与真实 GUI 命中顺序一致。
func _move_to_input_front() -> void:
	move_to_front()
	if visible:
		_suspend_covered_interface_focus()


## 响应主菜单自身显隐变化；无论由正式开局入口、测试场景或后续场景路由切换，都同步维护牌桌焦点边界。
func _on_visibility_changed() -> void:
	if not is_node_ready():
		return
	if visible:
		_suspend_covered_interface_focus()
		call_deferred("_focus_start_game_button")
	else:
		_close_mode_details(false)
		_set_settings_visible(false)
		_close_online_settings(false)
		_close_all_cards(false)
		_close_match_replay(false)
		_online_lobby_panel.visible = false
		_restore_covered_interface_focus()


## 统一处理主菜单模式列表的鼠标滚轮；事件只在滚轮指针位于模式滚动窗口且其他模态未打开时消费。
func _input(event: InputEvent) -> void:
	if not visible or _mode_scroll == null or not is_instance_valid(_mode_scroll):
		return
	if _settings_panel.visible or (_mode_details_panel != null and _mode_details_panel.visible) or _lan_lobby_panel.visible or _online_settings_panel.visible or _all_cards_panel.visible or _is_match_replay_page_visible() or _online_lobby_panel.visible:
		return
	if not event is InputEventMouseButton:
		return
	# 当前鼠标滚轮事件；只有按下阶段的上下滚轮才改变模式列表位置。
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if not _mode_scroll.get_global_rect().has_point(mouse_event.position):
		return
	# 滚轮方向；向下滚动增加 ScrollContainer 的纵向值，向上滚动减少该值。
	var direction: float = 1.0 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
	# 设备滚轮倍率；缺失或零倍率按一格处理，避免合成事件无法滚动。
	var wheel_factor: float = maxf(absf(mouse_event.factor), 1.0)
	_set_mode_scroll_vertical(_mode_scroll.scroll_vertical + direction * mode_scroll_wheel_step * wheel_factor)
	get_viewport().set_input_as_handled()


## 将牌桌提供的下一局人数写入主菜单设置；人数保持限制在标准身份局的有效范围。
func set_next_player_count(player_count: int) -> void:
	# 按当前选中模式规范化人数；使用无信号写入避免与 GameSettings 信号形成无限递归。
	var mode_id: String = _selected_match_mode
	# 当前模式允许的规范人数；非法输入按各模式人数规则收敛到可保存范围。
	var clamped_player_count: int = GameSettings.normalize_player_count_for_mode(mode_id, player_count) if GameSettings != null else clampi(player_count, minimum_player_count, maximum_player_count)
	if int(_player_count_input.value) != clamped_player_count:
		_player_count_input.set_value_no_signal(float(clamped_player_count))
	if GameSettings != null:
		GameSettings.set_next_match_player_count(clamped_player_count)


## 返回设置面板当前指定的人数；优先读取仍在编辑中的文本，避免输入框失焦前的数据丢失。
func get_next_player_count() -> int:
	# 输入框当前文本；优先读取尚未因焦点切换而提交的键入内容。
	var typed_player_count: int = _player_count_input.get_line_edit().text.to_int()
	# 当前最终人数输入；空或不可解析文本回退 SpinBox 已提交数值。
	var resolved_player_count: int = int(_player_count_input.value) if typed_player_count == 0 else typed_player_count
	if GameSettings != null:
		return GameSettings.normalize_player_count_for_mode(_selected_match_mode, resolved_player_count)
	return clampi(resolved_player_count, minimum_player_count, maximum_player_count)


## 同步局域网网关默认端口；主菜单只保存显示入口参数，不创建或持有 ENet 对等体。
func set_lan_default_port(port: int) -> void:
	_lan_default_port = clampi(port, 1024, 65535)


## 设置离线专属控制权选项是否可见；联机模式隐藏整项但不改写之后离线对局使用的偏好。
func set_control_all_characters_visible(controls_visible: bool) -> void:
	if _control_all_characters_checkbox == null:
		return
	_control_all_characters_checkbox.visible = controls_visible
	if not controls_visible and _control_all_characters_checkbox.has_focus():
		_control_all_characters_checkbox.release_focus()


## 按当前活动主题刷新主菜单全部静态控件；不保存主题颜色副本，也不修改任何玩法配置。
func refresh_ui_style() -> void:
	if not is_node_ready():
		return
	_menu_background.color = BattleUIStyle.get_color("outer_background")
	_menu_surface.color = BattleUIStyle.get_color("table_surface")
	_top_navigation.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("rail"), BattleUIStyle.get_color("border"), 2, 8))
	_main_frame.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel(BattleUIStyle.get_color("rail"), BattleUIStyle.get_color("border"), 2, 8))
	_mode_list.add_theme_stylebox_override("panel", _make_flat_inner_panel(BattleUIStyle.get_color("mode_list_panel", BattleUIStyle.get_color("panel")), BattleUIStyle.get_color("border")))
	_apply_mode_scroll_bar_style()
	_preview_panel.add_theme_stylebox_override("panel", _make_flat_inner_panel(BattleUIStyle.get_color("metal_panel"), BattleUIStyle.get_color("border")))
	_preview_mode_badge.add_theme_stylebox_override("panel", _make_flat_inner_panel(Color(BattleUIStyle.get_color("metal_panel"), 1.0), BattleUIStyle.get_color("border"), 1, 0))
	_mode_summary_panel.add_theme_stylebox_override("panel", _make_flat_inner_panel(Color(BattleUIStyle.get_color("metal_panel"), preview_summary_opacity), BattleUIStyle.get_color("border")))
	_action_panel.add_theme_stylebox_override("panel", _make_flat_inner_panel(Color(BattleUIStyle.get_color("metal_panel"), preview_action_opacity), BattleUIStyle.get_color("accent"), 1, 0))
	_settings_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	if _mode_details_panel != null:
		_mode_details_panel.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	_preview_shade.color = Color(BattleUIStyle.get_color("panel"), preview_shade_opacity)
	_settings_backdrop.color = Color(BattleUIStyle.get_color("shade"), settings_backdrop_opacity)
	if _mode_details_backdrop != null:
		_mode_details_backdrop.color = Color(BattleUIStyle.get_color("shade"), settings_backdrop_opacity)
	_top_mode_indicator.color = BattleUIStyle.get_color("accent")
	_top_online_settings_indicator.color = BattleUIStyle.get_color("accent")
	_top_all_cards_indicator.color = BattleUIStyle.get_color("accent")
	_mode_card_indicator.color = BattleUIStyle.get_color("accent")
	_doudizhu_mode_card_indicator.color = BattleUIStyle.get_color("accent")
	_team2v2_mode_card_indicator.color = BattleUIStyle.get_color("accent")
	_wheel_duel_mode_card_indicator.color = BattleUIStyle.get_color("accent")
	_opportunity_brawl_mode_card_indicator.color = BattleUIStyle.get_color("accent")
	_conquest_mode_card_indicator.color = BattleUIStyle.get_color("accent")
	(%TopNavigationDivider as ColorRect).color = Color(BattleUIStyle.get_color("border"), 0.48)
	(%MainMenuSettingsDivider as ColorRect).color = Color(BattleUIStyle.get_color("border"), 0.62)
	_refresh_top_navigation_page_style()
	_apply_mode_button_style(_identity_mode_button)
	_apply_mode_button_style(_doudizhu_mode_button)
	_apply_mode_button_style(_team2v2_mode_button)
	_apply_mode_button_style(_wheel_duel_mode_button)
	_apply_mode_button_style(_opportunity_brawl_mode_button)
	_apply_mode_button_style(_conquest_mode_button)
	BattleUIStyle.apply_interaction_button(_settings_button, BattleUIStyle.get_color("secondary_button", BattleUIStyle.get_color("panel")), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_lan_button, BattleUIStyle.get_color("secondary_button", BattleUIStyle.get_color("panel")), BattleUIStyle.get_color("accent"), false)
	BattleUIStyle.apply_interaction_button(_start_game_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_settings_close_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	if _mode_details_button != null:
		BattleUIStyle.apply_interaction_button(_mode_details_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), false)
	if _mode_details_close_button != null:
		BattleUIStyle.apply_interaction_button(_mode_details_close_button, BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true)
	BattleUIStyle.apply_interaction_button(_card_name_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_ui_style_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_mulligan_limit_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_character_replacement_count_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_character_candidate_count_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_conquest_difficulty_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	BattleUIStyle.apply_interaction_button(_conquest_opportunity_choice_option, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
	_mode_title.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_mode_title.add_theme_color_override("font_outline_color", BattleUIStyle.get_color("outer_background"))
	_mode_description.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_mode_description.add_theme_color_override("font_outline_color", BattleUIStyle.get_color("outer_background"))
	(%MainMenuTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%MainMenuBrandSubtitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	(%MainMenuModeListTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%IdentityModeName as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%IdentityModePlayerCount as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%DouDizhuModeName as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%DouDizhuModePlayerCount as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%Team2v2ModeName as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%Team2v2ModePlayerCount as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	# 车轮战模式卡两个标签；本机编辑器可能以旧场景缓存覆写 unique 标记，缺失时跳过表现覆盖而不中断整页主题刷新。
	var wheel_duel_mode_name_label: Label = get_node_or_null("%WheelDuelModeName") as Label
	if wheel_duel_mode_name_label != null:
		wheel_duel_mode_name_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	# 车轮战模式卡人数标签；与名称标签独立校验，任一缺失都不影响其余控件继续应用主题色。
	var wheel_duel_mode_player_count_label: Label = get_node_or_null("%WheelDuelModePlayerCount") as Label
	if wheel_duel_mode_player_count_label != null:
		wheel_duel_mode_player_count_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%OpportunityBrawlModeName as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%OpportunityBrawlModePlayerCount as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%ConquestModeName as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%ConquestModePlayerCount as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuModeEyebrow as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("accent"))
	(%MainMenuPreviewModeBadgeLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	(%MainMenuModeRuleHint as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	_menu_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger") if _status_is_error else BattleUIStyle.get_color("text_secondary"))
	(%MainMenuSettingsTitle as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	_settings_hint_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_muted"))
	(%MainMenuCardNameLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuUiStyleLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuMulliganLimitLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuCharacterReplacementCountLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuCharacterCandidateCountLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuConquestDifficultyLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	(%MainMenuConquestOpportunityChoiceLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	if _mode_details_title_label != null:
		_mode_details_title_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	if _mode_details_description_label != null:
		_mode_details_description_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	# 车轮战两项候选设置与其他开局规则共享主题字体色；避免模式切换后回退到场景默认白字。
	# 明置候选标签；精简的界面回归场景可能不含车轮战设置，缺失时只跳过表现覆盖。
	var wheel_duel_face_up_candidate_label: Label = get_node_or_null("MainMenuSettingsPanel/SettingsVBox/WheelDuelFaceUpCandidateRow/WheelDuelFaceUpCandidateLabel") as Label
	if wheel_duel_face_up_candidate_label != null:
		wheel_duel_face_up_candidate_label.add_theme_font_override("font", ThemeDB.fallback_font)
		wheel_duel_face_up_candidate_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		wheel_duel_face_up_candidate_label.add_theme_color_override("font_shadow_color", BattleUIStyle.get_color("outer_background"))
	# 暗置候选标签；与明置标签独立校验，避免局部场景缓存缺失其中一项时中断整页主题刷新。
	var wheel_duel_face_down_candidate_label: Label = get_node_or_null("MainMenuSettingsPanel/SettingsVBox/WheelDuelFaceDownCandidateRow/WheelDuelFaceDownCandidateLabel") as Label
	if wheel_duel_face_down_candidate_label != null:
		wheel_duel_face_down_candidate_label.add_theme_font_override("font", ThemeDB.fallback_font)
		wheel_duel_face_down_candidate_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
		wheel_duel_face_down_candidate_label.add_theme_color_override("font_shadow_color", BattleUIStyle.get_color("outer_background"))
	(%MainMenuPlayerCountLabel as Label).add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_ai_response_delay_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_game_speed_label.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_auto_identity_marking_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_auto_identity_marking_checkbox.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	_auto_identity_marking_checkbox.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("accent"))
	_control_all_characters_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_control_all_characters_checkbox.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	_control_all_characters_checkbox.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("accent"))
	_custom_character_assignment_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_custom_character_assignment_checkbox.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	_custom_character_assignment_checkbox.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("accent"))
	_customize_ai_characters_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_customize_ai_characters_checkbox.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	_customize_ai_characters_checkbox.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("accent"))
	_ai_uses_mulligan_checkbox.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	_ai_uses_mulligan_checkbox.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	_ai_uses_mulligan_checkbox.add_theme_color_override("font_pressed_color", BattleUIStyle.get_color("accent"))
	_apply_slider_style(_ai_response_delay_slider)
	_apply_slider_style(_game_speed_slider)
	_apply_spin_box_style(_player_count_input)
	_apply_spin_box_style(_wheel_duel_face_up_candidate_input)
	_apply_spin_box_style(_wheel_duel_face_down_candidate_input)
	_apply_option_popup_style(_ui_style_option)
	_apply_option_popup_style(_card_name_option)
	_apply_option_popup_style(_mulligan_limit_option)
	_apply_option_popup_style(_character_replacement_count_option)
	_apply_option_popup_style(_character_candidate_count_option)
	_apply_option_popup_style(_conquest_difficulty_option)
	_apply_option_popup_style(_conquest_opportunity_choice_option)
	_lan_lobby_panel.refresh_ui_style()
	_online_settings_panel.refresh_ui_style()
	_all_cards_panel.refresh_ui_style()
	if _match_replay_panel != null:
		_match_replay_panel.refresh_ui_style()
	_online_lobby_panel.refresh_ui_style()


## 切换到模式选择内容页；顶部“模式选择”与“联机设置”对等互斥，仅替换客户区，不创建弹层。
## 补充：“所有卡牌”加入后同样参与互斥，模式选择页仍是三个内容页的默认回退目标。
func _restore_selected_match_mode() -> void:
	# 根据全局下一局模式恢复主菜单选中态；未知值回退身份模式。
	if GameSettings == null:
		_select_identity_mode()
		return
	# 当前持久化模式的规范稳定 ID；未知旧值回退身份模式。
	var restored_mode: String = GameSettings.normalize_match_mode(GameSettings.next_match_mode)
	if restored_mode == GameSettings.MATCH_MODE_DOUDIZHU:
		_select_doudizhu_mode()
	elif restored_mode == GameSettings.MATCH_MODE_TEAM2V2:
		_select_team2v2_mode()
	elif restored_mode == GameSettings.MATCH_MODE_WHEEL_DUEL:
		_select_wheel_duel_mode()
	elif restored_mode == GameSettings.MATCH_MODE_OPPORTUNITY_BRAWL:
		_select_opportunity_brawl_mode()
	elif restored_mode == GameSettings.MATCH_MODE_CONQUEST:
		_select_conquest_mode()
	else:
		_select_identity_mode()


func _select_identity_mode() -> void:
	# 联机设置内容页；点击“模式选择”时回到默认主菜单内容，顶部导航始终保留在原位。
	if _online_settings_panel.visible:
		_close_online_settings(false)
	# 所有卡牌内容页；点击“模式选择”时恢复默认客户区，不保留图鉴遮罩或搜索焦点。
	if _all_cards_panel.visible:
		_close_all_cards(false)
	if _is_match_replay_page_visible():
		_close_match_replay(false)
	_selected_match_mode = GameSettings.MATCH_MODE_IDENTITY
	if GameSettings != null:
		GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_IDENTITY)
	# 身份模式人数范围；恢复检查器默认 2-10，并加载身份模式独立人数。
	minimum_player_count = 2
	maximum_player_count = 10
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 1.0
	# 身份模式上次保存的人数；首次运行时回退当前人数输入值。
	var identity_count: int = GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_IDENTITY) if GameSettings != null else int(_player_count_input.value)
	set_next_player_count(identity_count)
	_mode_title.text = "身份模式"
	_mode_description.text = "标准身份局 · %d—%d人 · 主公忠臣 vs 反贼内奸" % [minimum_player_count, maximum_player_count]
	# 预览左上角“标准身份局”徽章已按需求隐藏；身份与斗地主均不展示该 UI。
	if _preview_mode_badge != null:
		_preview_mode_badge.visible = false
	_set_top_navigation_page(false)
	_identity_mode_button.button_pressed = true
	_doudizhu_mode_button.button_pressed = false
	_team2v2_mode_button.button_pressed = false
	_wheel_duel_mode_button.button_pressed = false
	_opportunity_brawl_mode_button.button_pressed = false
	_conquest_mode_button.button_pressed = false
	_mode_card_indicator.visible = true
	_doudizhu_mode_card_indicator.visible = false
	_team2v2_mode_card_indicator.visible = false
	_wheel_duel_mode_card_indicator.visible = false
	_opportunity_brawl_mode_card_indicator.visible = false
	_conquest_mode_card_indicator.visible = false
	_set_wheel_duel_settings_visible(false)
	_show_status(MODE_READY_STATUS_TEXT, false)
	call_deferred("_ensure_mode_button_visible", _identity_mode_button)


## 选中斗地主模式；人数限制为 3 与 5，写入下一局模式配置后不改进行中的对局。
func _select_doudizhu_mode() -> void:
	if _online_settings_panel.visible:
		_close_online_settings(false)
	if _all_cards_panel.visible:
		_close_all_cards(false)
	if _is_match_replay_page_visible():
		_close_match_replay(false)
	_selected_match_mode = GameSettings.MATCH_MODE_DOUDIZHU
	if GameSettings != null:
		GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_DOUDIZHU)
	# 斗地主仅 3/5 人；步长 2 使上下键在 3 与 5 之间切换，禁止其它人数。
	minimum_player_count = 3
	maximum_player_count = 5
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 2.0
	# 恢复该模式独立保存人数；非 3/5 时由全局规范化夹到合法值。
	var preferred_count: int = GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_DOUDIZHU) if GameSettings != null else 3
	preferred_count = GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_DOUDIZHU, preferred_count) if GameSettings != null else (3 if preferred_count < 4 else 5)
	set_next_player_count(preferred_count)
	_mode_title.text = "斗地主"
	_mode_description.text = "斗地主·3或5人·地主VS农民"
	# 左侧模式卡片人数标签；场景默认与斗地主合法人数 3/5 保持一致。
	var doudizhu_count_label: Label = %DouDizhuModePlayerCount as Label
	if doudizhu_count_label != null:
		doudizhu_count_label.text = "3/5人"
	if _preview_mode_badge != null:
		_preview_mode_badge.visible = false
	_set_top_navigation_page(false)
	_identity_mode_button.button_pressed = false
	_doudizhu_mode_button.button_pressed = true
	_team2v2_mode_button.button_pressed = false
	_wheel_duel_mode_button.button_pressed = false
	_opportunity_brawl_mode_button.button_pressed = false
	_conquest_mode_button.button_pressed = false
	_mode_card_indicator.visible = false
	_doudizhu_mode_card_indicator.visible = true
	_team2v2_mode_card_indicator.visible = false
	_wheel_duel_mode_card_indicator.visible = false
	_opportunity_brawl_mode_card_indicator.visible = false
	_conquest_mode_card_indicator.visible = false
	_set_wheel_duel_settings_visible(false)
	_show_status(MODE_READY_STATUS_TEXT, false)
	call_deferred("_ensure_mode_button_visible", _doudizhu_mode_button)


## 选中 2v2 模式；固定 4 人，写入下一局模式配置后不改进行中的对局。
func _select_team2v2_mode() -> void:
	if _online_settings_panel.visible:
		_close_online_settings(false)
	if _all_cards_panel.visible:
		_close_all_cards(false)
	if _is_match_replay_page_visible():
		_close_match_replay(false)
	_selected_match_mode = GameSettings.MATCH_MODE_TEAM2V2
	if GameSettings != null:
		GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_TEAM2V2)
	# 2v2 固定 4 人；禁用人数微调范围外的值。
	minimum_player_count = 4
	maximum_player_count = 4
	_player_count_input.min_value = 4
	_player_count_input.max_value = 4
	_player_count_input.step = 1.0
	# 2v2 上次保存的人数；规范化后始终为4。
	var preferred_count: int = GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_TEAM2V2) if GameSettings != null else 4
	preferred_count = GameSettings.normalize_player_count_for_mode(GameSettings.MATCH_MODE_TEAM2V2, preferred_count) if GameSettings != null else 4
	set_next_player_count(preferred_count)
	_mode_title.text = "2v2"
	_mode_description.text = "2v2·4人·蓝方VS红方·一/四同队、二/三同队"
	# 2v2 左侧模式卡人数标签；固定显示4人并与输入限制保持一致。
	var team2v2_count_label: Label = %Team2v2ModePlayerCount as Label
	if team2v2_count_label != null:
		team2v2_count_label.text = "4人"
	if _preview_mode_badge != null:
		_preview_mode_badge.visible = false
	_set_top_navigation_page(false)
	_identity_mode_button.button_pressed = false
	_doudizhu_mode_button.button_pressed = false
	_team2v2_mode_button.button_pressed = true
	_wheel_duel_mode_button.button_pressed = false
	_opportunity_brawl_mode_button.button_pressed = false
	_conquest_mode_button.button_pressed = false
	_mode_card_indicator.visible = false
	_doudizhu_mode_card_indicator.visible = false
	_team2v2_mode_card_indicator.visible = true
	_wheel_duel_mode_card_indicator.visible = false
	_opportunity_brawl_mode_card_indicator.visible = false
	_conquest_mode_card_indicator.visible = false
	_set_wheel_duel_settings_visible(false)
	_show_status(MODE_READY_STATUS_TEXT, false)
	call_deferred("_ensure_mode_button_visible", _team2v2_mode_button)


## 选中1v1车轮战模式；固定2人并显示明置X、暗置Y两项专属候选设置。
func _select_wheel_duel_mode() -> void:
	if _online_settings_panel.visible:
		_close_online_settings(false)
	if _all_cards_panel.visible:
		_close_all_cards(false)
	if _is_match_replay_page_visible():
		_close_match_replay(false)
	_selected_match_mode = GameSettings.MATCH_MODE_WHEEL_DUEL
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_WHEEL_DUEL)
	minimum_player_count = 2
	maximum_player_count = 2
	_player_count_input.min_value = 2
	_player_count_input.max_value = 2
	_player_count_input.step = 1.0
	set_next_player_count(2)
	_mode_title.text = "1v1车轮战"
	_mode_description.text = "2人·先手红方VS后手蓝方·三将车轮对战"
	if _preview_mode_badge != null:
		_preview_mode_badge.visible = false
	_set_top_navigation_page(false)
	_identity_mode_button.button_pressed = false
	_doudizhu_mode_button.button_pressed = false
	_team2v2_mode_button.button_pressed = false
	_wheel_duel_mode_button.button_pressed = true
	_opportunity_brawl_mode_button.button_pressed = false
	_conquest_mode_button.button_pressed = false
	_mode_card_indicator.visible = false
	_doudizhu_mode_card_indicator.visible = false
	_team2v2_mode_card_indicator.visible = false
	_wheel_duel_mode_card_indicator.visible = true
	_opportunity_brawl_mode_card_indicator.visible = false
	_conquest_mode_card_indicator.visible = false
	_set_wheel_duel_settings_visible(true)
	_show_status(MODE_READY_STATUS_TEXT, false)
	call_deferred("_ensure_mode_button_visible", _wheel_duel_mode_button)


## 选中机缘大乱斗模式；人数范围继承身份模式2至10人，并显示普通身份局的开局设置。
func _select_opportunity_brawl_mode() -> void:
	if _online_settings_panel.visible:
		_close_online_settings(false)
	if _all_cards_panel.visible:
		_close_all_cards(false)
	if _is_match_replay_page_visible():
		_close_match_replay(false)
	_selected_match_mode = GameSettings.MATCH_MODE_OPPORTUNITY_BRAWL
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_OPPORTUNITY_BRAWL)
	minimum_player_count = 2
	maximum_player_count = 10
	_player_count_input.min_value = minimum_player_count
	_player_count_input.max_value = maximum_player_count
	_player_count_input.step = 1.0
	# 机缘大乱斗独立人数设置；默认8人，切换模式时不覆盖普通身份局人数。
	var preferred_count: int = GameSettings.get_stored_player_count_for_mode(GameSettings.MATCH_MODE_OPPORTUNITY_BRAWL)
	set_next_player_count(preferred_count)
	_mode_title.text = "机缘大乱斗"
	_mode_description.text = "身份模式基础 · 2—10人 · 每轮全体三选一机缘"
	if _preview_mode_badge != null:
		_preview_mode_badge.visible = false
	_set_top_navigation_page(false)
	_identity_mode_button.button_pressed = false
	_doudizhu_mode_button.button_pressed = false
	_team2v2_mode_button.button_pressed = false
	_wheel_duel_mode_button.button_pressed = false
	_opportunity_brawl_mode_button.button_pressed = true
	_conquest_mode_button.button_pressed = false
	_mode_card_indicator.visible = false
	_doudizhu_mode_card_indicator.visible = false
	_team2v2_mode_card_indicator.visible = false
	_wheel_duel_mode_card_indicator.visible = false
	_opportunity_brawl_mode_card_indicator.visible = true
	_conquest_mode_card_indicator.visible = false
	_set_wheel_duel_settings_visible(false)
	_show_status(MODE_READY_STATUS_TEXT, false)
	call_deferred("_ensure_mode_button_visible", _opportunity_brawl_mode_button)


## 选中过关斩将模式；固定玩家先手对战AI，菜单仅保留通用显示设置并隐藏普通选将与车轮战候选配置。
func _select_conquest_mode() -> void:
	if _online_settings_panel.visible:
		_close_online_settings(false)
	if _all_cards_panel.visible:
		_close_all_cards(false)
	if _is_match_replay_page_visible():
		_close_match_replay(false)
	_selected_match_mode = GameSettings.MATCH_MODE_CONQUEST
	GameSettings.set_next_match_mode(GameSettings.MATCH_MODE_CONQUEST)
	minimum_player_count = 2
	maximum_player_count = 2
	_player_count_input.min_value = 2
	_player_count_input.max_value = 2
	_player_count_input.step = 1.0
	set_next_player_count(2)
	_mode_title.text = "过关斩将"
	_mode_description.text = "单人1人·联机2至4人·清空本层全部敌方后挑战下一关"
	if _preview_mode_badge != null:
		_preview_mode_badge.visible = false
	_set_top_navigation_page(false)
	_identity_mode_button.button_pressed = false
	_doudizhu_mode_button.button_pressed = false
	_team2v2_mode_button.button_pressed = false
	_wheel_duel_mode_button.button_pressed = false
	_opportunity_brawl_mode_button.button_pressed = false
	_conquest_mode_button.button_pressed = true
	_mode_card_indicator.visible = false
	_doudizhu_mode_card_indicator.visible = false
	_team2v2_mode_card_indicator.visible = false
	_wheel_duel_mode_card_indicator.visible = false
	_opportunity_brawl_mode_card_indicator.visible = false
	_conquest_mode_card_indicator.visible = true
	_set_wheel_duel_settings_visible(true)
	_show_status(MODE_READY_STATUS_TEXT, false)
	call_deferred("_ensure_mode_button_visible", _conquest_mode_button)


## 控制车轮战专属设置行显隐；隐藏时不占VBox布局高度，过关斩将保留独立随机选将牌数设置。
func _set_wheel_duel_settings_visible(visible_state: bool) -> void:
	# 过关斩将与车轮战一样都是固定2人，但仅过关斩将保留独立的随机选将牌数设置。
	var is_conquest: bool = _selected_match_mode == GameSettings.MATCH_MODE_CONQUEST
	# 车轮战明置候选设置行；仅车轮战显示且隐藏后不占布局高度。
	var face_up_row: Control = _wheel_duel_face_up_candidate_input.get_parent() as Control
	# 车轮战暗置候选设置行；显隐规则与明置设置行相同。
	var face_down_row: Control = _wheel_duel_face_down_candidate_input.get_parent() as Control
	if face_up_row != null:
		face_up_row.visible = visible_state and not is_conquest
	if face_down_row != null:
		face_down_row.visible = visible_state and not is_conquest
	_custom_character_assignment_row.visible = not visible_state or is_conquest
	_custom_character_assignment_checkbox.text = "自选武将" if is_conquest else "自选全武将、座次与身份"
	_customize_ai_characters_row.visible = not visible_state
	_character_replacement_count_row.visible = not visible_state or is_conquest
	_character_candidate_count_row.visible = not visible_state or is_conquest
	_conquest_difficulty_row.visible = is_conquest
	_conquest_opportunity_choice_row.visible = is_conquest
	_auto_identity_marking_checkbox.visible = not visible_state
	_player_count_row.visible = not visible_state
	_refresh_active_character_replacement_count_selection()
	_refresh_active_character_candidate_count_selection()
	_refresh_mode_details_button()
	# 每次模式切换都经过本入口；过关斩将存档存在时把主按钮同步为“继续上次游戏”，其他模式恢复默认文字。
	refresh_start_button_text()


## 动态构建模式详情入口与模态面板；节点只承载主菜单说明，避免把模式规则复制进独立场景脚本。
func _build_mode_details_interface() -> void:
	# 预览内容根节点；详情按钮挂在原画与遮罩之后并保持左上角固定位置。
	var preview_content: Control = _preview_panel.get_node("MainMenuPreviewContent") as Control
	_mode_details_button = Button.new()
	_mode_details_button.name = "MainMenuModeDetailsButton"
	_mode_details_button.text = "详情"
	_mode_details_button.visible = false
	_mode_details_button.z_index = MODE_DETAILS_BUTTON_Z_INDEX
	_mode_details_button.custom_minimum_size = Vector2(104.0, 44.0)
	_mode_details_button.position = Vector2(22.0, 20.0)
	_mode_details_button.size = Vector2(104.0, 44.0)
	_mode_details_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mode_details_button.pressed.connect(_open_mode_details)
	preview_content.add_child(_mode_details_button)
	_mode_details_backdrop = ColorRect.new()
	_mode_details_backdrop.name = "MainMenuModeDetailsBackdrop"
	_mode_details_backdrop.visible = false
	_mode_details_backdrop.z_index = MODE_DETAILS_BACKDROP_Z_INDEX
	_mode_details_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_mode_details_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mode_details_backdrop.gui_input.connect(_on_mode_details_backdrop_gui_input)
	add_child(_mode_details_backdrop)
	_mode_details_panel = PanelContainer.new()
	_mode_details_panel.name = "MainMenuModeDetailsPanel"
	_mode_details_panel.visible = false
	_mode_details_panel.z_index = MODE_DETAILS_PANEL_Z_INDEX
	_mode_details_panel.custom_minimum_size = Vector2(680.0, 420.0)
	_mode_details_panel.set_anchors_preset(Control.PRESET_CENTER)
	_mode_details_panel.offset_left = -340.0
	_mode_details_panel.offset_top = -210.0
	_mode_details_panel.offset_right = 340.0
	_mode_details_panel.offset_bottom = 210.0
	add_child(_mode_details_panel)
	# 详情纵向内容；固定顺序为标题、滚动正文与关闭按钮。
	var details_content: VBoxContainer = VBoxContainer.new()
	details_content.name = "ModeDetailsContent"
	details_content.add_theme_constant_override("separation", 14)
	_mode_details_panel.add_child(details_content)
	_mode_details_title_label = Label.new()
	_mode_details_title_label.name = "Title"
	_mode_details_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_details_title_label.add_theme_font_size_override("font_size", 26)
	details_content.add_child(_mode_details_title_label)
	# 详情正文滚动区；较长模式描述在紧凑窗口中仍可完整阅读。
	var description_scroll: ScrollContainer = ScrollContainer.new()
	description_scroll.name = "DescriptionScroll"
	description_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	description_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	details_content.add_child(description_scroll)
	_mode_details_description_label = Label.new()
	_mode_details_description_label.name = "Description"
	_mode_details_description_label.custom_minimum_size.x = 620.0
	_mode_details_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_details_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_details_description_label.add_theme_font_size_override("font_size", 18)
	_mode_details_description_label.add_theme_constant_override("line_spacing", 7)
	description_scroll.add_child(_mode_details_description_label)
	_mode_details_close_button = Button.new()
	_mode_details_close_button.name = "CloseButton"
	_mode_details_close_button.text = "关闭"
	_mode_details_close_button.custom_minimum_size = Vector2(150.0, 46.0)
	_mode_details_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mode_details_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mode_details_close_button.pressed.connect(_close_mode_details)
	details_content.add_child(_mode_details_close_button)


## 按当前模式刷新详情按钮显隐；未列入说明表的身份、2v2与车轮战暂时隐藏入口。
func _refresh_mode_details_button() -> void:
	if _mode_details_button == null:
		return
	_mode_details_button.visible = MODE_DETAILS_BY_MODE.has(_selected_match_mode)
	if not _mode_details_button.visible and _mode_details_panel != null and _mode_details_panel.visible:
		_close_mode_details(false)


## 打开当前模式详情；标题与正文每次从稳定说明表读取，切换模式后不会残留旧内容。
func _open_mode_details() -> void:
	# 当前模式详情静态说明；未登记模式不打开空白模态。
	var mode_details: Dictionary = MODE_DETAILS_BY_MODE.get(_selected_match_mode, {}) as Dictionary
	if mode_details.is_empty() or _mode_details_panel == null:
		return
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_mode_details_title_label.text = str(mode_details.get("title", "模式详情"))
	_mode_details_description_label.text = str(mode_details.get("description", ""))
	_mode_details_backdrop.visible = true
	_mode_details_panel.visible = true
	_suspend_background_focus(_mode_details_panel)
	_mode_details_close_button.grab_focus()


## 关闭模式详情并恢复主菜单焦点；可选参数用于页面切换或主菜单退出时避免抢占新入口。
func _close_mode_details(restore_focus: bool = true) -> void:
	if _mode_details_panel == null or not _mode_details_panel.visible:
		return
	_mode_details_backdrop.visible = false
	_mode_details_panel.visible = false
	_restore_background_focus()
	if restore_focus and _mode_details_button != null and _mode_details_button.visible:
		_mode_details_button.grab_focus()


## 点击模式详情面板外的遮罩时关闭弹窗；只响应左键按下，滚轮继续留给正文滚动区。
func _on_mode_details_backdrop_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	# 当前鼠标事件；按下左键时完成一次关闭并标记输入已处理。
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_close_mode_details()
		accept_event()


## 打开设置浮层；模式预览保持可见，玩家可在不离开主菜单的情况下调整显示和人数配置。
func _open_settings() -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_close_mode_details(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_online_lobby_panel.visible = false
	_set_settings_visible(true)
	_settings_close_button.grab_focus()


## 切换到联机资料设置内容页；名称与形象由组件从 GameSettings 读取，顶部导航保持可点并可直接切回模式选择。
func _open_online_settings() -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_set_settings_visible(false)
	_lan_lobby_panel.visible = false
	_online_lobby_panel.visible = false
	_close_all_cards(false)
	_close_match_replay(false)
	# 默认主菜单内容；资料页与模式预览互斥显示，形成与“模式选择”对等的页面切换。
	_main_frame.visible = false
	_set_top_navigation_page(true)
	_online_settings_panel.open_panel()
	# 仅冻结模式预览与开局区；顶部“模式选择 / 联机设置”必须保持可聚焦，才能完成对等切页。
	# 补充：所有卡牌入口与上述两个标签同属保留的顶部导航根，因此联机设置页也可直接跳转图鉴。
	_suspend_background_focus(_online_settings_panel, [_top_navigation])


## 切换到所有卡牌内容页；浏览组件从静态目录读取武将、游戏牌与机缘，顶部导航保持可直接切换。
func _open_all_cards() -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_set_settings_visible(false)
	_lan_lobby_panel.visible = false
	_online_lobby_panel.visible = false
	_close_online_settings(false)
	_close_match_replay(false)
	# 默认模式内容；图鉴页与模式预览互斥显示，不覆盖顶部导航。
	_main_frame.visible = false
	_set_top_navigation_content_page(CONTENT_PAGE_ALL_CARDS)
	_all_cards_panel.open_panel()
	# 只冻结图鉴之外的客户区控件；顶部四个内容页标签继续保持可聚焦。
	_suspend_background_focus(_all_cards_panel, [_top_navigation])


## 切换到对局回放内容页；回放组件只读取本地回放文件，顶部导航保持可直接切换到其他内容页。
func _open_match_replay() -> void:
	if _match_replay_panel == null:
		return
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_set_settings_visible(false)
	_lan_lobby_panel.visible = false
	_online_lobby_panel.visible = false
	_close_online_settings(false)
	_close_all_cards(false)
	# 默认模式内容；回放页与模式预览互斥显示，不覆盖顶部导航。
	_main_frame.visible = false
	_set_top_navigation_content_page(CONTENT_PAGE_MATCH_REPLAY)
	_match_replay_panel.open_panel()
	# 只冻结回放页之外的客户区控件；顶部四个内容页标签继续保持可聚焦。
	_suspend_background_focus(_match_replay_panel, [_top_navigation])


## 回放页播放意图转发；主菜单不读取回放内容，直接把稳定文件名交给牌桌开始重演。
func _on_replay_playback_requested(replay_file_name: String) -> void:
	replay_playback_requested.emit(replay_file_name)


## 在回放内容页显示一条播放失败说明；牌桌载入回放失败时经本入口回显原因。
func show_replay_playback_error(message: String) -> void:
	if _match_replay_panel != null:
		_match_replay_panel.show_operation_status(message)


## 恢复主菜单并直接打开“对局回放”内容页；退出回放重演后由牌桌调用，玩家回到回放列表继续操作。
func show_match_replay_page() -> void:
	return_to_main_menu()
	_open_match_replay()


## 打开独立局域网大厅组件；人数沿用主菜单下一局配置，端口读取网关组件的公开默认值。
## 过关斩将同样可进入局域网：大厅人数表示玩家数（2至4），每名玩家对应一名敌方AI。
func _open_lan_panel() -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_set_settings_visible(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_online_lobby_panel.visible = false
	# 打开局域网前再次写入当前模式与人数；斗地主入口建房时 host_lan 读取 next_match_mode 创建对应房间。
	if GameSettings != null:
		GameSettings.set_next_match_mode(_selected_match_mode)
		GameSettings.set_next_match_player_count(get_next_player_count())
	_lan_lobby_panel.open_panel(get_next_player_count(), _lan_default_port)
	_suspend_background_focus(_lan_lobby_panel)


## 关闭设置浮层；已经写入 GameSettings 的配置立即保留，不需要额外确认按钮。
func _close_settings() -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_set_settings_visible(false)
	_settings_button.grab_focus()


## 关闭联机资料设置内容页并恢复模式选择内容；可选参数用于切换到其他页面时避免抢占新入口焦点。
func _close_online_settings(restore_focus: bool = true) -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	# 未打开联机设置时不重置其他对等内容页；生命周期清理可以安全重复调用。
	if not _online_settings_panel.visible:
		return
	_online_settings_panel.visible = false
	# 默认内容框；资料页关闭后立即恢复，不让主菜单留下空白客户区。
	_main_frame.visible = true
	_set_top_navigation_page(false)
	_restore_background_focus()
	if restore_focus:
		call_deferred("_focus_online_settings_button")


## 关闭所有卡牌内容页并恢复模式选择客户区；可选参数用于切换页面时避免抢占新入口焦点。
func _close_all_cards(restore_focus: bool = true) -> void:
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	# 未打开图鉴时保持当前其他内容页不变，允许主菜单生命周期重复执行清理。
	if not _all_cards_panel.visible:
		return
	_all_cards_panel.visible = false
	_main_frame.visible = true
	_set_top_navigation_content_page(CONTENT_PAGE_MODES)
	_restore_background_focus()
	if restore_focus:
		call_deferred("_focus_all_cards_button")


## 返回对局回放内容页当前是否可见；旧场景缓存缺失组件时视为不可见，供互斥与焦点守卫复用。
func _is_match_replay_page_visible() -> bool:
	return _match_replay_panel != null and _match_replay_panel.visible


## 关闭对局回放内容页并恢复模式选择客户区；可选参数用于切换页面时避免抢占新入口焦点。
func _close_match_replay(restore_focus: bool = true) -> void:
	# 未打开回放页时保持当前其他内容页不变，允许主菜单生命周期重复执行清理。
	if not _is_match_replay_page_visible():
		return
	MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
	_match_replay_panel.close_panel()
	_main_frame.visible = true
	_set_top_navigation_content_page(CONTENT_PAGE_MODES)
	_restore_background_focus()
	if restore_focus:
		call_deferred("_focus_match_replay_button")


## 对局回放页关闭后把焦点归还顶部入口；其他模态仍可见时安全跳过。
func _focus_match_replay_button() -> void:
	if visible and _match_replay_button != null and not _settings_panel.visible and not _lan_lobby_panel.visible and not _online_settings_panel.visible and not _all_cards_panel.visible and not _is_match_replay_page_visible() and not _online_lobby_panel.visible and not _match_replay_button.disabled:
		_match_replay_button.grab_focus()


## 读取有效人数并请求开始身份局；成功后的实际开局、状态清理与选将流程由牌桌统一处理。
func _request_start_game() -> void:
	# 已确认的下一局人数；写回控件使文本、Range 数值和发出的开局请求保持一致。
	var player_count: int = get_next_player_count()
	_player_count_input.value = player_count
	GameSettings.set_next_match_player_count(player_count)
	_set_settings_visible(false)
	_start_game_button.disabled = true
	# 当前模式开局状态文案；失败时会被具体错误替换。
	var starting_status: String = STARTING_STATUS_TEXT_IDENTITY
	if _selected_match_mode == GameSettings.MATCH_MODE_DOUDIZHU:
		starting_status = STARTING_STATUS_TEXT_DOUDIZHU
	elif _selected_match_mode == GameSettings.MATCH_MODE_TEAM2V2:
		starting_status = STARTING_STATUS_TEXT_TEAM2V2
	elif _selected_match_mode == GameSettings.MATCH_MODE_WHEEL_DUEL:
		starting_status = STARTING_STATUS_TEXT_WHEEL_DUEL
	elif _selected_match_mode == GameSettings.MATCH_MODE_OPPORTUNITY_BRAWL:
		starting_status = STARTING_STATUS_TEXT_OPPORTUNITY_BRAWL
	elif _selected_match_mode == GameSettings.MATCH_MODE_CONQUEST:
		starting_status = STARTING_STATUS_TEXT_CONQUEST
	_show_status(starting_status, false)
	# 再次确认模式写入；防止设置浮层改人数后模式丢失。
	if GameSettings != null:
		GameSettings.set_next_match_mode(_selected_match_mode)
	start_game_requested.emit(player_count)
	if visible:
		_start_game_button.disabled = false
		if _menu_status_label.text == starting_status:
			show_start_error("无法开始游戏，请检查数据配置后重试。")


## 在牌桌确认权威对局创建成功后关闭主菜单；失败请求不会调用该入口，因此玩家始终可以修改设置并重试。
func confirm_game_started() -> void:
	_set_settings_visible(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_lan_lobby_panel.confirm_match_started()
	_online_lobby_panel.confirm_match_started()
	_restore_background_focus()
	_start_game_button.disabled = false
	visible = false
	_restore_covered_interface_focus()


## 在主菜单底部显示开局拒绝原因；错误只属于入口反馈，不写入规则状态或全局设置。
func show_start_error(message: String) -> void:
	_show_status(message, true)
	_start_game_button.disabled = false


## 局内重新开局失败后恢复主菜单入口；统一重置模态、错误提示和主要操作焦点，避免玩家停留在无权威状态的旧牌桌。
func restore_after_failed_restart(message: String) -> void:
	visible = true
	_suspend_covered_interface_focus()
	_set_settings_visible(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_start_game_button.disabled = false
	refresh_start_button_text()
	_show_status(message, true)
	move_to_front()
	call_deferred("_focus_start_game_button")


## 关闭尚未开局的局域网面板并恢复普通主菜单焦点；实际断开操作由牌桌在调用前完成。
func close_lan_panel() -> void:
	_lan_lobby_panel.visible = false
	_online_lobby_panel.visible = false
	_restore_background_focus()
	call_deferred("_focus_lan_button")


## 在房主断开或连接失败后恢复主菜单和局域网入口，并保留具体错误供玩家修正后重试。
func show_lan_session_error(message: String) -> void:
	visible = true
	_suspend_covered_interface_focus()
	_set_settings_visible(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_lan_lobby_panel.return_to_entry(message)
	_online_lobby_panel.visible = false
	_suspend_background_focus(_lan_lobby_panel)
	move_to_front()


## 退出一局进行中或已结束的对局后恢复主菜单；该入口不显示错误，并保留玩家此前配置的下一局人数。
func return_to_main_menu() -> void:
	visible = true
	_suspend_covered_interface_focus()
	_set_settings_visible(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_online_lobby_panel.visible = false
	_start_game_button.disabled = false
	refresh_start_button_text()
	_show_status(MODE_READY_STATUS_TEXT, false)
	move_to_front()
	call_deferred("_focus_start_game_button")


## 按当前选中模式与过关斩将存档存在性刷新主操作按钮文字；存档存在且选中过关斩将时显示继续入口。
## 该函数只改变按钮显示文字；点击后的“继续”与“新开局”分流由牌桌按同一存档条件判定，二者始终一致。
func refresh_start_button_text() -> void:
	if _start_game_button == null:
		return
	# 是否显示继续入口；只有选中过关斩将且本地存在可解析存档时才切换文字。
	var shows_continue_entry: bool = _selected_match_mode == GameSettings.MATCH_MODE_CONQUEST and ConquestSaveStore.has_save()
	_start_game_button.text = "继续上次游戏" if shows_continue_entry else "开始游戏"


## 让设置面板与全屏遮罩保持同一可见状态；该入口避免出现只有面板或只有遮罩残留的输入异常。
func _set_settings_visible(settings_visible: bool) -> void:
	_settings_backdrop.visible = settings_visible
	_settings_panel.visible = settings_visible
	if settings_visible:
		_suspend_background_focus(_settings_panel)
	else:
		_restore_background_focus()


## 暂停主菜单内指定模态面板之外全部可聚焦控件；可选保留导航祖先，使内容页切换时顶部标签仍可点击。
func _suspend_background_focus(active_modal: Control = null, focus_keep_roots: Array = []) -> void:
	# 实际活动模态；未显式传入时继续使用设置面板，保持旧调用入口语义不变。
	var modal: Control = _settings_panel if active_modal == null else active_modal
	# 主菜单下的全部控件；设置浮层只需冻结同一组件内的模式和开局入口，局内焦点由主菜单覆盖边界独立管理。
	var menu_controls: Array[Node] = find_children("*", "Control", true, false)
	# 主菜单控件遍历项；逐个保留原始焦点模式，后续追加的模式按钮无需在组件中硬编码节点名。
	for control_node: Node in menu_controls:
		# 当前可聚焦控件；活动面板与允许保留的导航祖先及其后代保持原焦点模式。
		var control: Control = control_node as Control
		if control == null or control == modal or modal.is_ancestor_of(control) or control.focus_mode == Control.FOCUS_NONE or _background_focus_modes.has(control):
			continue
		# 是否属于需要继续接收输入的导航根；联机设置内容页必须保留顶部“模式选择 / 联机设置”。
		# 补充：所有卡牌页复用同一导航根，三个顶部标签都会保持可聚焦。
		var keep_focus: bool = false
		for keep_root_variant: Variant in focus_keep_roots:
			# 当前允许保留焦点的导航根；根节点自身及其后代都跳过冻结。
			var keep_root: Control = keep_root_variant as Control
			if keep_root != null and (control == keep_root or keep_root.is_ancestor_of(control)):
				keep_focus = true
				break
		if keep_focus:
			continue
		_background_focus_modes[control] = control.focus_mode
		control.focus_mode = Control.FOCUS_NONE


## 恢复设置打开前的底层焦点配置；失效节点会被跳过，避免场景退出期间访问已释放控件。
func _restore_background_focus() -> void:
	# 已缓存控件键；遍历快照后统一清空字典，恢复过程中不会修改当前迭代集合。
	for control_variant: Variant in _background_focus_modes.keys():
		if not is_instance_valid(control_variant):
			continue
		# 先前被暂停的底层控件；静态主菜单通常始终有效，实例校验为后续动态模式扩展提供安全边界。
		var control: Control = control_variant as Control
		if control == null:
			continue
		control.focus_mode = int(_background_focus_modes.get(control_variant, Control.FOCUS_ALL))
	_background_focus_modes.clear()


## 暂停当前视口内主菜单之外全部可聚焦控件；全屏底色负责鼠标，焦点边界负责键盘与手柄输入。
func _suspend_covered_interface_focus() -> void:
	# 当前视口下的全部控件；牌桌、日志和局内菜单均与主菜单共享焦点域，主菜单可见时必须统一隔离。
	var viewport_controls: Array[Node] = get_viewport().find_children("*", "Control", true, false)
	# 视口控件遍历项；主菜单自身及全部后代保留原焦点模式，其他可聚焦节点保存后设为不可聚焦。
	for control_node: Node in viewport_controls:
		# 当前视口控件；动态创建的牌桌控件也会在延迟置顶阶段补充进入缓存，不依赖固定节点路径。
		var control: Control = control_node as Control
		if control == null or control == self or is_ancestor_of(control) or control.focus_mode == Control.FOCUS_NONE or _covered_interface_focus_modes.has(control):
			continue
		_covered_interface_focus_modes[control] = control.focus_mode
		control.focus_mode = Control.FOCUS_NONE


## 恢复主菜单覆盖前的局内焦点配置；只在成功进入对局或组件退出场景树时调用。
func _restore_covered_interface_focus() -> void:
	# 已缓存局内控件键；使用快照遍历并在结尾统一清空，避免恢复过程中修改当前迭代集合。
	for control_variant: Variant in _covered_interface_focus_modes.keys():
		if not is_instance_valid(control_variant):
			continue
		# 被主菜单覆盖的局内控件；动态节点已经释放时安全跳过，其余节点恢复各自原始焦点模式。
		var control: Control = control_variant as Control
		if control == null:
			continue
		control.focus_mode = int(_covered_interface_focus_modes.get(control_variant, Control.FOCUS_ALL))
	_covered_interface_focus_modes.clear()


## 组件离开场景树时归还全部焦点模式；支持主菜单被独立卸载而不污染仍保留的牌桌控件。
func _exit_tree() -> void:
	_restore_background_focus()
	_restore_covered_interface_focus()


## 在底部操作栏更新状态文本与语义色；主题变化后仍通过错误标记恢复正确颜色。
func _show_status(message: String, is_error: bool) -> void:
	_status_is_error = is_error
	_menu_status_label.visible = not message.is_empty()
	_menu_status_label.text = message
	_menu_status_label.add_theme_color_override("font_color", BattleUIStyle.get_color("danger") if is_error else BattleUIStyle.get_color("text_secondary"))


## 点击设置面板外的模态遮罩时返回主菜单；仅处理鼠标左键按下，避免滚轮和右键误关闭。
func _on_settings_backdrop_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	# 当前鼠标事件；显式检查按键与按下阶段，保证一次点击只关闭一次浮层。
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_close_settings()
		accept_event()


## 设置浮层打开时允许使用 Esc 返回；主菜单本身不拦截对局阶段或其他组件的取消输入。
## 补充：模式详情弹窗使用同一取消入口，并优先于设置浮层关闭。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _mode_details_panel != null and _mode_details_panel.visible:
			_close_mode_details()
			get_viewport().set_input_as_handled()
		elif _settings_panel.visible:
			_close_settings()
			get_viewport().set_input_as_handled()


## 主菜单完成布局后把键盘焦点放到主要操作；玩家可直接按确认键开始当前唯一模式。
func _focus_start_game_button() -> void:
	if visible and not _settings_panel.visible and (_mode_details_panel == null or not _mode_details_panel.visible) and not _lan_lobby_panel.visible and not _online_settings_panel.visible and not _all_cards_panel.visible and not _is_match_replay_page_visible() and not _online_lobby_panel.visible:
		_start_game_button.grab_focus()


## 局域网面板关闭后把焦点归还联机入口；若主菜单或按钮不可用则安全跳过。
func _focus_lan_button() -> void:
	if visible and not _settings_panel.visible and not _lan_lobby_panel.visible and not _online_settings_panel.visible and not _all_cards_panel.visible and not _is_match_replay_page_visible() and not _online_lobby_panel.visible and not _lan_button.disabled:
		_lan_button.grab_focus()


## 联机资料面板关闭后把焦点归还顶部入口；其他模态仍可见时安全跳过。
func _focus_online_settings_button() -> void:
	if visible and not _settings_panel.visible and not _lan_lobby_panel.visible and not _online_settings_panel.visible and not _all_cards_panel.visible and not _is_match_replay_page_visible() and not _online_lobby_panel.visible and not _online_settings_button.disabled:
		_online_settings_button.grab_focus()


## 所有卡牌页关闭后把焦点归还顶部入口；其他模态仍可见时安全跳过。
func _focus_all_cards_button() -> void:
	if visible and not _settings_panel.visible and not _lan_lobby_panel.visible and not _online_settings_panel.visible and not _all_cards_panel.visible and not _is_match_replay_page_visible() and not _online_lobby_panel.visible and not _all_cards_button.disabled:
		_all_cards_button.grab_focus()


## 打开连接成功后的联机大厅并建立模态焦点边界；快照由牌桌协调器直接绑定到大厅组件。
func show_online_lobby() -> void:
	_set_settings_visible(false)
	_close_online_settings(false)
	_close_all_cards(false)
	_close_match_replay(false)
	_lan_lobby_panel.visible = false
	_suspend_background_focus(_online_lobby_panel)


## 同步顶部“模式选择 / 联机设置”互斥选中态与底部指示线；仅表达当前主菜单内容页，不保存业务状态。
## 补充：该旧布尔入口继续兼容原有两页调用；三页通用状态由 _set_top_navigation_content_page 统一处理。
func _set_top_navigation_page(is_online_settings_page: bool) -> void:
	_set_top_navigation_content_page(CONTENT_PAGE_ONLINE_SETTINGS if is_online_settings_page else CONTENT_PAGE_MODES)


## 同步顶部四个对等内容页的互斥选中态与指示线；未知页面安全回退模式选择。
func _set_top_navigation_content_page(page_id: String) -> void:
	# 当前规范化页面 ID；只接受四个已登记内容页，避免按钮与客户区出现全不选状态。
	var resolved_page_id: String = page_id if page_id in [CONTENT_PAGE_MODES, CONTENT_PAGE_ONLINE_SETTINGS, CONTENT_PAGE_ALL_CARDS, CONTENT_PAGE_MATCH_REPLAY] else CONTENT_PAGE_MODES
	_top_identity_mode_button.set_pressed_no_signal(resolved_page_id == CONTENT_PAGE_MODES)
	_online_settings_button.set_pressed_no_signal(resolved_page_id == CONTENT_PAGE_ONLINE_SETTINGS)
	_all_cards_button.set_pressed_no_signal(resolved_page_id == CONTENT_PAGE_ALL_CARDS)
	if _match_replay_button != null:
		_match_replay_button.set_pressed_no_signal(resolved_page_id == CONTENT_PAGE_MATCH_REPLAY)
	_top_mode_indicator.visible = resolved_page_id == CONTENT_PAGE_MODES
	_top_online_settings_indicator.visible = resolved_page_id == CONTENT_PAGE_ONLINE_SETTINGS
	_top_all_cards_indicator.visible = resolved_page_id == CONTENT_PAGE_ALL_CARDS
	if _top_match_replay_indicator != null:
		_top_match_replay_indicator.visible = resolved_page_id == CONTENT_PAGE_MATCH_REPLAY
	_refresh_top_navigation_page_style()


## 按当前内容页刷新顶部导航按钮主题；选中页使用强调边框，未选中页使用普通边框。
func _refresh_top_navigation_page_style() -> void:
	# 是否位于联机设置内容页；运行时由按钮按下状态表达，避免额外布尔字段与场景可见性脱节。
	var is_online_settings_page: bool = _online_settings_button.button_pressed
	# 是否位于所有卡牌内容页；运行时由按钮按下状态表达，不保存第二份页面状态。
	var is_all_cards_page: bool = _all_cards_button.button_pressed
	# 是否位于对局回放内容页；旧场景缓存缺失该按钮时视为未选中。
	var is_match_replay_page: bool = _match_replay_button != null and _match_replay_button.button_pressed
	# 是否位于模式选择内容页；四个按钮互斥时由其余三项共同推导。
	var is_modes_page: bool = not is_online_settings_page and not is_all_cards_page and not is_match_replay_page
	_apply_top_navigation_button_style(_top_identity_mode_button, is_modes_page)
	_apply_top_navigation_button_style(_online_settings_button, is_online_settings_page)
	_apply_top_navigation_button_style(_all_cards_button, is_all_cards_page)
	if _match_replay_button != null:
		_apply_top_navigation_button_style(_match_replay_button, is_match_replay_page)


## 为单个顶部内容页按钮应用当前主题；持续选中态只切换强调边框，不额外压暗参考图的蓝黑底色。
func _apply_top_navigation_button_style(button: Button, is_selected: bool) -> void:
	if button == null:
		return
	# 顶部导航底色；高级黑金使用独立蓝黑语义，其他主题回退原有面板颜色。
	var background_color: Color = BattleUIStyle.get_color("navigation_button", BattleUIStyle.get_color("panel"))
	# 顶部导航描边；当前页使用强调色，其他页使用普通边框色。
	var border_color: Color = BattleUIStyle.get_color("accent") if is_selected else BattleUIStyle.get_color("border")
	BattleUIStyle.apply_interaction_button(button, background_color, border_color, is_selected)
	# 持续按下样式；显式恢复主题底色，避免通用按钮工厂的瞬时按压加深污染当前页常驻颜色。
	button.add_theme_stylebox_override("pressed", BattleUIStyle.make_decade_button(background_color, border_color, is_selected))


## 创建没有重复阴影的内层面板；主框保留唯一强阴影，内部只用细边区分内容层级。
func _make_flat_inner_panel(background_color: Color, border_color: Color, border_width: int = 1, corner_radius: int = 5) -> StyleBoxFlat:
	# 内层面板样式；复用主题工厂的边距与圆角后移除阴影，避免多层金框产生视觉噪声。
	var style: StyleBoxFlat = BattleUIStyle.make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


## 为左侧模式卡片配置通用交互外观，并单独加深持续选中时的内部底色；该样式不影响顶部导航和其他操作按钮。
func _apply_mode_button_style(button: Button) -> void:
	if button == null:
		return
	# 模式卡片常态背景色；独立语义允许参考图使用石墨灰卡片，同时不改变主要操作按钮的暖棕底色。
	var background_color: Color = BattleUIStyle.get_color("mode_button", BattleUIStyle.get_color("action_button"))
	# 模式卡片边框色；沿用当前主题强调色以配合左侧选中指示条。
	var border_color: Color = BattleUIStyle.get_color("accent")
	# 当前主题的模式卡选中加深比例；缺失语义时回退检查器参数，保证旧主题和自定义场景继续兼容。
	var selected_background_darkening: float = clampf(float(UIStyleRegistry.get_value(BattleUIStyle.get_active_style_id(), "mode_selected_background_darkening", mode_selected_background_darkening)), 0.0, 0.6)
	# 模式卡片选中背景色；仅压低亮度，不改变主题提供的石墨灰或木色基调。
	var selected_background_color: Color = background_color.darkened(selected_background_darkening)
	BattleUIStyle.apply_interaction_button(button, background_color, border_color, true)
	button.add_theme_stylebox_override("pressed", BattleUIStyle.make_decade_button(selected_background_color, border_color, true))


## 为左侧模式列表滚动条应用当前主题；滚动轨道与拖块只负责浏览，不改变模式选择状态。
func _apply_mode_scroll_bar_style() -> void:
	if _mode_scroll == null:
		return
	# 模式列表纵向滚动条；宽度由检查器参数统一控制，主题切换时原位重绘。
	var scroll_bar: VScrollBar = _mode_scroll.get_v_scroll_bar()
	if scroll_bar == null:
		return
	BattleUIStyle.apply_main_menu_scroll_bar_style(scroll_bar, mode_scroll_bar_width)


## 创建贴合纵向滚动范围两端的滑条样式；清除通用面板上下边距后，滑块在最小值和最大值处与轨道端点齐平。
func _make_mode_scroll_bar_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	# 滑条样式；调用共享工厂后与卡牌图鉴保持相同主题色、端点边距和圆角规则。
	var style: StyleBoxFlat = BattleUIStyle.make_main_menu_scroll_bar_style(background_color, border_color)
	return style


## 让当前选中的模式卡完整进入滚动窗口；键盘恢复持久化模式时也不会把选中项留在视口外。
func _ensure_mode_button_visible(button: Control) -> void:
	if _mode_scroll == null or button == null or not is_instance_valid(button):
		return
	_mode_scroll.ensure_control_visible(button)
	_sync_mode_scroll_bar_value()


## 按指定像素值设置模式列表滚动位置，并立即把主题化纵向滑条更新到同一数值。
func _set_mode_scroll_vertical(requested_value: float) -> void:
	if _mode_scroll == null or not is_instance_valid(_mode_scroll):
		return
	# 当前模式列表滑条；其 max_value 包含内容总高，实际可滚动终点还要扣除可视 page 高度。
	var scroll_bar: VScrollBar = _mode_scroll.get_v_scroll_bar()
	# 模式列表可滚动最大值；内容未超出窗口时固定为0，避免滚轮写入负值。
	var maximum_scroll_value: float = maxf(scroll_bar.max_value - scroll_bar.page, 0.0) if scroll_bar != null else 0.0
	# 规范化滚动目标；整数化与 ScrollContainer 的 scroll_vertical 类型保持一致。
	var normalized_value: int = roundi(clampf(requested_value, 0.0, maximum_scroll_value))
	_mode_scroll_syncing = true
	_mode_scroll.scroll_vertical = normalized_value
	if scroll_bar != null:
		scroll_bar.value = normalized_value
	_mode_scroll_syncing = false


## 响应纵向滑条拖动；反向写回 ScrollContainer，保证拖条、滚轮和内容位移共享唯一滚动状态。
func _on_mode_scroll_bar_value_changed(value: float) -> void:
	if _mode_scroll_syncing or _mode_scroll == null or not is_instance_valid(_mode_scroll):
		return
	_mode_scroll_syncing = true
	_mode_scroll.scroll_vertical = roundi(value)
	_mode_scroll_syncing = false


## 在布局、程序化定位或主题刷新后对账滑条值；Godot 可能在内容尺寸更新后一帧才重新计算 max/page。
func _sync_mode_scroll_bar_value() -> void:
	if _mode_scroll == null or not is_instance_valid(_mode_scroll):
		return
	# 当前 ScrollContainer 值；通过统一入口再次钳制并写入 VScrollBar，避免内容尺寸变化造成滑块脱节。
	var current_scroll_value: float = _mode_scroll.scroll_vertical
	_set_mode_scroll_vertical(current_scroll_value)


## 为主菜单设置滑条应用主题轨道与已选区域；数值范围和步长仍由 GameSettings 决定。
func _apply_slider_style(slider: HSlider) -> void:
	# 未选择区域轨道；低对比度细边保持滑条在两套深色主题中都清晰可见。
	var track_style: StyleBoxFlat = _make_flat_inner_panel(BattleUIStyle.get_color("disabled_button"), BattleUIStyle.get_color("disabled_button_border"), 1, 4)
	track_style.content_margin_top = 3.0
	track_style.content_margin_bottom = 3.0
	# 已选择区域轨道；主题强调色半透明填充用于表达当前数值，不引入固定配色。
	var filled_style: StyleBoxFlat = _make_flat_inner_panel(Color(BattleUIStyle.get_color("accent"), 0.72), BattleUIStyle.get_color("accent"), 1, 4)
	filled_style.content_margin_top = 3.0
	filled_style.content_margin_bottom = 3.0
	slider.add_theme_stylebox_override("slider", track_style)
	slider.add_theme_stylebox_override("grabber_area", filled_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled_style)


## 为人数 SpinBox 的文本输入区应用主题样式；上下箭头仍由 Godot 提供标准键盘与鼠标行为。
func _apply_spin_box_style(spin_box: SpinBox) -> void:
	# SpinBox 内部文本框；只负责显示和编辑人数，不另存人数配置。
	var line_edit: LineEdit = spin_box.get_line_edit()
	# 直接指定全局回退字体，保证运行时创建的 SpinBox 编辑框与菜单其余中文控件使用同一字体来源。
	line_edit.add_theme_font_override("font", ThemeDB.fallback_font)
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_selected_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_uneditable_color", BattleUIStyle.get_color("text_secondary"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))


## 为主题下拉菜单的弹出列表补齐面板、悬停与文字配色；选项内容仍来自 UIStyleRegistry。
func _apply_option_popup_style(option_button: OptionButton) -> void:
	# OptionButton 自带的弹出菜单；该节点由 Godot 管理，主菜单只覆盖视觉主题。
	var popup: PopupMenu = option_button.get_popup()
	popup.add_theme_stylebox_override("panel", BattleUIStyle.make_inset_panel())
	popup.add_theme_stylebox_override("hover", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), false))
	popup.add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))
	popup.add_theme_color_override("font_hover_color", BattleUIStyle.get_color("text_primary"))
	popup.add_theme_color_override("font_disabled_color", BattleUIStyle.get_color("disabled_button_font"))


## 从注册表构建 UI 风格选项；稳定标识写入元数据，显示名称调整不会影响保存的设置值。
func _populate_ui_style_options() -> void:
	_ui_style_option.clear()
	# 注册表风格标识；按注册顺序生成显示选项，稳定 ID 只写入元数据而不暴露为按钮文字。
	for style_id: String in UIStyleRegistry.get_style_ids():
		# 当前选项索引；元数据保存稳定标识，后续无需通过中文名称反向匹配主题。
		var option_index: int = _ui_style_option.item_count
		_ui_style_option.add_item(UIStyleRegistry.get_display_name(style_id))
		_ui_style_option.set_item_metadata(option_index, style_id)


## 从固定名称模式配置构建下拉选项；枚举元数据让显示文字变更不会影响保存的设置值。
func _populate_card_name_options() -> void:
	_card_name_option.clear()
	for mode_option: Dictionary in GameSettings.CARD_NAME_MODE_OPTIONS:
		# 下拉项索引；模式枚举写入元数据，文本只参与玩家可见的设置界面。
		var option_index: int = _card_name_option.item_count
		_card_name_option.add_item(str(mode_option.get("label", "")))
		_card_name_option.set_item_metadata(option_index, mode_option.get("mode", GameSettings.NameMode.CUSTOM))


## 从标准手气卡配置构建下拉选项；张数语义保存在元数据中，界面文字调整不会影响规则值。
func _populate_mulligan_limit_options() -> void:
	_mulligan_limit_option.clear()
	for limit_option: Dictionary in GameSettings.MULLIGAN_LIMIT_OPTIONS:
		# 当前手气卡选项索引；元数据保存0至5、10或-1，避免通过中文显示文字反向解析规则。
		var option_index: int = _mulligan_limit_option.item_count
		_mulligan_limit_option.add_item(str(limit_option.get("label", "关闭")))
		_mulligan_limit_option.set_item_metadata(option_index, int(limit_option.get("value", 0)))


## 从标准换将卡配置构建下拉选项；显示文字只用于界面，稳定次数始终读取选项元数据。
func _populate_character_replacement_count_options() -> void:
	_character_replacement_count_option.clear()
	for count_option: Dictionary in GameSettings.CHARACTER_REPLACEMENT_COUNT_OPTIONS:
		# 当前换将卡选项索引；元数据保存权威次数，避免从中文量词反向解析。
		var option_index: int = _character_replacement_count_option.item_count
		_character_replacement_count_option.add_item(str(count_option.get("label", "关闭")))
		_character_replacement_count_option.set_item_metadata(option_index, int(count_option.get("value", 0)))


## 从标准随机选将牌数配置构建一至二十张选项；数值直接作为下一局普通候选数量。
func _populate_character_candidate_count_options() -> void:
	_character_candidate_count_option.clear()
	for count_option: Dictionary in GameSettings.CHARACTER_CANDIDATE_COUNT_OPTIONS:
		# 当前随机候选选项索引；元数据保存1至20，显示文字变化不会改变规则。
		var option_index: int = _character_candidate_count_option.item_count
		_character_candidate_count_option.add_item(str(count_option.get("label", "五张")))
		_character_candidate_count_option.set_item_metadata(option_index, int(count_option.get("value", GameSettings.DEFAULT_CHARACTER_CANDIDATE_COUNT)))


## 从全局配置构建过关斩将难度一至五；稳定数值写入元数据，显示文字不承担规则含义。
func _populate_conquest_difficulty_options() -> void:
	_conquest_difficulty_option.clear()
	for difficulty_option: Dictionary in GameSettings.CONQUEST_DIFFICULTY_OPTIONS:
		# 当前难度选项索引；规则只读取一至五的元数据，不通过中文标签反向解析。
		var option_index: int = _conquest_difficulty_option.item_count
		_conquest_difficulty_option.add_item(str(difficulty_option.get("label", "难度五")))
		_conquest_difficulty_option.set_item_metadata(option_index, int(difficulty_option.get("value", GameSettings.DEFAULT_CONQUEST_DIFFICULTY)))


## 按全局风格同步下拉框与主菜单颜色；无信号选择避免界面刷新产生重复设置回调。
func _refresh_ui_style_selection(style_id: String) -> void:
	if not is_node_ready():
		return
	# 已规范化的风格标识；配置缺失时稳定回退默认主题，保证下拉框存在有效选择。
	var normalized_style_id: String = UIStyleRegistry.normalize_style_id(style_id)
	# 下拉选项索引；只用于比较元数据和同步选中项，不作为主题的持久标识。
	for option_index: int in range(_ui_style_option.item_count):
		if str(_ui_style_option.get_item_metadata(option_index)) == normalized_style_id:
			_ui_style_option.select(option_index)
			break
	refresh_ui_style()


## 将玩家选中的主题稳定标识写入全局设置；所有已订阅的界面会即时重绘。
func _on_ui_style_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _ui_style_option.item_count:
		return
	GameSettings.set_ui_style(str(_ui_style_option.get_item_metadata(option_index)))


## 根据全局名称模式刷新下拉选择；名称模式只改变前端显示，不影响任何卡牌 ID 或规则。
func _refresh_card_name_text(mode: GameSettings.NameMode = GameSettings.NameMode.CUSTOM) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_card_name_option.item_count):
		if int(_card_name_option.get_item_metadata(option_index)) == int(mode):
			_card_name_option.select(option_index)
			return


## 将玩家选择的名称模式写入全局设置；所有已订阅的牌面、技能说明与菜单会即时同步。
func _on_card_name_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _card_name_option.item_count:
		return
	# 当前稳定名称模式；元数据缺失时不提交，避免意外把配置重置为默认值。
	var selected_mode: Variant = _card_name_option.get_item_metadata(option_index)
	if selected_mode == null:
		return
	GameSettings.set_card_name_mode(int(selected_mode))


## 按全局设置同步手气卡下拉框；无信号选择避免菜单刷新再次提交同一规则值。
func _refresh_mulligan_limit_selection(limit: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_mulligan_limit_option.item_count):
		if int(_mulligan_limit_option.get_item_metadata(option_index)) == limit:
			_mulligan_limit_option.select(option_index)
			return


## 将玩家选中的手气卡张数写入下一局全局设置；当前已经创建的对局继续使用自身锁定配置。
func _on_mulligan_limit_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _mulligan_limit_option.item_count:
		return
	GameSettings.set_mulligan_limit(int(_mulligan_limit_option.get_item_metadata(option_index)))


## 按传入值同步换将卡数量下拉框；无信号选择避免两套菜单互相重复写入。
func _refresh_character_replacement_count_selection(count: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_character_replacement_count_option.item_count):
		if int(_character_replacement_count_option.get_item_metadata(option_index)) == count:
			_character_replacement_count_option.select(option_index)
			return


## 按当前模式读取正确的换将卡数量并刷新下拉框；过关斩将不会被普通模式信号覆盖。
func _refresh_active_character_replacement_count_selection(_changed_count: int = 0) -> void:
	if GameSettings == null:
		return
	_refresh_character_replacement_count_selection(GameSettings.get_character_replacement_count_for_mode(_selected_match_mode))


## 将玩家选择的换将卡数量写入当前模式的独立设置；当前选将阶段继续使用开局时锁定的次数。
func _on_character_replacement_count_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _character_replacement_count_option.item_count:
		return
	GameSettings.set_character_replacement_count_for_mode(_selected_match_mode, int(_character_replacement_count_option.get_item_metadata(option_index)))


## 按传入值同步随机选将牌数下拉框；无信号选择保证主菜单与局内菜单稳定联动。
func _refresh_character_candidate_count_selection(count: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_character_candidate_count_option.item_count):
		if int(_character_candidate_count_option.get_item_metadata(option_index)) == count:
			_character_candidate_count_option.select(option_index)
			return


## 按当前模式读取正确的随机选将牌数并刷新下拉框；过关斩将不会被普通模式信号覆盖。
func _refresh_active_character_candidate_count_selection(_changed_count: int = 0) -> void:
	if GameSettings == null:
		return
	_refresh_character_candidate_count_selection(GameSettings.get_character_candidate_count_for_mode(_selected_match_mode))


## 将玩家选择的随机选将牌数写入当前模式的独立设置；领袖技固定候选由规则服务另行追加。
func _on_character_candidate_count_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _character_candidate_count_option.item_count:
		return
	GameSettings.set_character_candidate_count_for_mode(_selected_match_mode, int(_character_candidate_count_option.get_item_metadata(option_index)))


## 按全局设置同步过关斩将难度选中项；无信号选择避免主菜单与局内菜单之间形成重复保存。
## 填充过关斩将机缘选择方式下拉；选项文本与稳定ID均来自 GameSettings 的唯一配置表。
func _populate_conquest_opportunity_choice_options() -> void:
	_conquest_opportunity_choice_option.clear()
	for choice_option: Dictionary in GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_OPTIONS:
		# 当前下拉项索引；元数据保存稳定方式ID，显示文字仅负责菜单展示。
		var option_index: int = _conquest_opportunity_choice_option.item_count
		_conquest_opportunity_choice_option.add_item(str(choice_option.get("label", "投票选择")))
		_conquest_opportunity_choice_option.set_item_metadata(option_index, str(choice_option.get("value", GameSettings.DEFAULT_CONQUEST_OPPORTUNITY_CHOICE_MODE)))


## 同步机缘选择方式下拉的当前选中项；设置来源变化（含其他入口修改）时保持菜单一致。
func _refresh_conquest_opportunity_choice_selection(mode_id: String) -> void:
	if _conquest_opportunity_choice_option == null:
		return
	for option_index: int in range(_conquest_opportunity_choice_option.item_count):
		if str(_conquest_opportunity_choice_option.get_item_metadata(option_index)) == mode_id:
			_conquest_opportunity_choice_option.select(option_index)
			return


## 玩家在主菜单切换机缘选择方式；稳定ID写入全局设置并在下一局锁定。
func _on_conquest_opportunity_choice_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _conquest_opportunity_choice_option.item_count:
		return
	GameSettings.set_conquest_opportunity_choice_mode(str(_conquest_opportunity_choice_option.get_item_metadata(option_index)))


func _refresh_conquest_difficulty_selection(difficulty: int) -> void:
	if not is_node_ready():
		return
	for option_index: int in range(_conquest_difficulty_option.item_count):
		if int(_conquest_difficulty_option.get_item_metadata(option_index)) == difficulty:
			_conquest_difficulty_option.select(option_index)
			return


## 将玩家选择的过关斩将难度写入下一局设置；进行中的关卡继续使用创建时锁定的难度。
func _on_conquest_difficulty_selected(option_index: int) -> void:
	if option_index < 0 or option_index >= _conquest_difficulty_option.item_count:
		return
	GameSettings.set_conquest_difficulty(int(_conquest_difficulty_option.get_item_metadata(option_index)))


## 更新 AI 响应速度显示；数值越小代表 AI 行动与选牌等待越短。
func _refresh_ai_response_delay_text(delay_seconds: float) -> void:
	if not is_node_ready():
		return
	_ai_response_delay_slider.set_value_no_signal(delay_seconds)
	_ai_response_delay_label.text = "AI响应速度：%.2f秒" % delay_seconds


## 将 AI 响应滑条值写入全局设置；控制器只对后续创建的等待任务采用新值。
func _on_ai_response_delay_changed(delay_seconds: float) -> void:
	GameSettings.set_ai_response_delay_seconds(delay_seconds)


## 更新游戏速度显示；数值代表后续阶段切换和自动响应的最小等待间隔。
func _refresh_game_speed_text(interval_seconds: float) -> void:
	if not is_node_ready():
		return
	_game_speed_slider.set_value_no_signal(interval_seconds)
	_game_speed_label.text = "游戏速度：%.2f秒" % interval_seconds


## 将游戏速度滑条值写入全局设置；已开始的计时任务保持原时长以避免中途跳变。
func _on_game_speed_changed(interval_seconds: float) -> void:
	GameSettings.set_game_speed_interval_seconds(interval_seconds)


## 下一局人数输入变化时写入全局持久化设置；已开始对局不会读取该值改变当前身份与座次。
func _on_next_player_count_changed(player_count: float) -> void:
	# 按模式规范化；斗地主仅 3/5，身份局 2–10。无信号回写避免重复回调。
	var resolved_count: int = GameSettings.normalize_player_count_for_mode(_selected_match_mode, int(player_count)) if GameSettings != null else int(player_count)
	if int(_player_count_input.value) != resolved_count:
		_player_count_input.set_value_no_signal(float(resolved_count))
	if GameSettings != null:
		GameSettings.set_next_match_player_count(resolved_count)


## 写入车轮战明置候选数量；若明暗合计不足10，则同步抬高暗置数量以保证双方能够各抓5名武将。
func _on_wheel_duel_face_up_candidate_count_changed(candidate_count: float) -> void:
	# 规范化后的明置候选数量；限制在全局车轮战设置范围内。
	var normalized_count: int = clampi(int(candidate_count), GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT, GameSettings.MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	GameSettings.set_wheel_duel_face_up_candidate_count(normalized_count)
	# 保证双方共抓10名武将所需的最少暗置候选数量。
	var required_face_down_count: int = maxi(WheelDuelSelectionService.DRAFTED_CHARACTER_COUNT_PER_PLAYER * 2 - normalized_count, GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT)
	if GameSettings.wheel_duel_face_down_candidate_count < required_face_down_count:
		GameSettings.set_wheel_duel_face_down_candidate_count(required_face_down_count)
		_wheel_duel_face_down_candidate_input.set_value_no_signal(required_face_down_count)


## 写入车轮战暗置候选数量；若明暗合计不足10，则同步抬高明置数量以保证双方能够各抓5名武将。
func _on_wheel_duel_face_down_candidate_count_changed(candidate_count: float) -> void:
	# 规范化后的暗置候选数量；限制在全局车轮战设置范围内。
	var normalized_count: int = clampi(int(candidate_count), GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT, GameSettings.MAX_WHEEL_DUEL_CANDIDATE_COUNT)
	GameSettings.set_wheel_duel_face_down_candidate_count(normalized_count)
	# 保证双方共抓10名武将所需的最少明置候选数量。
	var required_face_up_count: int = maxi(WheelDuelSelectionService.DRAFTED_CHARACTER_COUNT_PER_PLAYER * 2 - normalized_count, GameSettings.MIN_WHEEL_DUEL_CANDIDATE_COUNT)
	if GameSettings.wheel_duel_face_up_candidate_count < required_face_up_count:
		GameSettings.set_wheel_duel_face_up_candidate_count(required_face_up_count)
		_wheel_duel_face_up_candidate_input.set_value_no_signal(required_face_up_count)


## 将自动身份标记开关写入全局设置；该设置只影响客户端推测徽记显示。
func _on_auto_identity_marking_toggled(enabled: bool) -> void:
	GameSettings.set_auto_identity_marking_enabled(enabled)


## 按全局设置同步自动身份标记复选框；无信号写入避免外部刷新形成重复回调。
func _refresh_auto_identity_marking_state(enabled: bool) -> void:
	if not is_node_ready():
		return
	_auto_identity_marking_checkbox.set_pressed_no_signal(enabled)
