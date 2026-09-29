class_name MatchController
extends Node

## 濒死开始与获救收尾组件；共用规则步骤调度，不单独维护恢复栈。
const DYING_RESOLUTION_SERVICE_SCRIPT = preload("res://scripts/core/dying_resolution_service.gd")

## 标准身份局权威控制器。它编排阶段与动作，并把具体合法性、卡牌效果、AI 和网络交给独立组件。

signal state_changed(snapshot: Dictionary)
signal log_added(message: String)
signal action_rejected(message: String)
signal match_finished(winner: String)

## 统一结算局部故障信号；异常技能续列或时机递归只终止当前链路，详情供日志、测试与停滞诊断读取。
signal settlement_faulted(fault_data: Dictionary)

## 统一牌面表现信号；使用牌、展示牌和判定牌都发送可序列化 CardPresentationEvent 快照。
signal card_presentation_requested(presentation_data: Dictionary)

## 区域移动表现信号；所有摸牌、获得、响应和弃牌都使用同一实体牌动画入口。
signal card_transfer_requested(card_data: Dictionary, source_player_id: int, source_zone: String, target_player_id: int, target_zone: String)

## 摸牌表现批次开始信号；同一次 draw() 的实体移动归入一个批次，界面据此把多张牌整体居中并同时起飞。
signal draw_presentation_batch_started(batch_id: int, player_id: int)

## 摸牌表现批次完成信号；界面收到后将本批全部已移动实体交给动画队列，下一次 draw() 的批次必须等待本批动画收尾。
signal draw_presentation_batch_finished(batch_id: int, player_id: int)

## 牌面弃牌幂等状态释放信号；实体进入任意非弃牌区域时发送，不代表需要播放一条可见转移动画。
signal card_animation_ownership_reset_requested(card_uid: int)

## 技能实际发动表现信号；桌面根据玩家、技能名和已确认的可序列化上下文显示提示与目标线，不读取或修改技能运行时。
signal skill_activated(player_id: int, skill_name: String, context: Dictionary)

## 防具实际生效表现信号；桌面复用武将牌中央提示显示防具名，不读取或修改装备实体与规则状态。
signal equipment_activated(player_id: int, equipment_name: String, context: Dictionary)

## 技能发动与卡牌使用、打出的统一音频表现信号；负载只含已公开数据（发动者、技能或牌定义、武将ID、两套牌名、动作模式）。
## 音频表现层据此选择并播放语音；该负载可序列化并随联机表现事件广播，表现层不需要回读任何控制器状态。
signal voice_presentation_requested(presentation_data: Dictionary)

## 音频请求类别：技能发动语音；音频服务据此按“角色专属 → 通用”顺序解析候选文件。
const VOICE_KIND_SKILL: String = "skill"

## 音频请求类别：卡牌使用或打出语音；音频服务据此按“当前名称体系 → 另一名称体系”解析候选文件。
const VOICE_KIND_CARD: String = "card"

## 音频请求类别：全局效果音；音频服务据此按固定效果标识解析通用素材。
## 效果音覆盖体力增减、属性伤害、护甲承伤、连环与装备等与具体技能无关的规则事件。
## 负载与技能、卡牌语音共用同一信号，因此表现层与联机广播链路不需要为效果音增加任何分支。
const VOICE_KIND_EFFECT: String = "effect"

## 音频请求类别：武将阵亡语音；音频服务据此按阵亡武将ID解析角色专属素材。
## 阵亡是武将级事件而不是技能级事件，因此单独成类；负载与技能、卡牌、效果音共用同一信号，
## 表现层与联机广播链路不需要为它增加任何分支。
const VOICE_KIND_DIE: String = "die"

## 效果音标识：回复体力；实际回复量大于0时发声。
const EFFECT_RECOVER: String = "recover"

## 效果音标识：失去体力；绕过护盾直接扣减体力时发声。
const EFFECT_LOSE_HP: String = "loseHp"

## 效果音标识：被横置（连环）；角色由未横置变为横置时发声。
const EFFECT_LINK: String = "link"

## 效果音标识：解除连环；角色由横置变为未横置时发声。
const EFFECT_LINK_CLEAR: String = "link_clear"

## 伤害效果音基础标识；未发生护甲承伤时使用，2点及以上伤害追加后缀2。
const EFFECT_DAMAGE_BASE: String = "damage"

## 伤害效果音基础标识（护甲承伤）；护盾实际吸收伤害时使用，与普通伤害音效区分。
const EFFECT_HUJIA_DAMAGE_BASE: String = "hujia_damage"

## 装备效果音标识表；键为本项目稳定的装备槽位ID，值为无名杀装备音效标识。
## 武器、防具、进攻马、防御马与宝物各自使用独立音色，未登记槽位不发声。
const EQUIPMENT_EFFECT_IDS: Dictionary = {
	"weapon":"equip1",
	"armor":"equip2",
	"offensive_mount":"equip3",
	"defensive_mount":"equip4",
	"treasure":"equip5",
}

## 防具类装备的稳定槽位ID列表；武器声明“无视防具”时，这些槽位提供的响应入口必须在同一次结算中整体停用。
## 列表集中声明槽位名而不是具体防具ID，新增防具（八卦阵等提供响应的防具）无需修改响应候选逻辑。
const ARMOR_EQUIPMENT_SLOTS: Array[String] = ["armor"]

## 卡牌音频动作模式：使用；与打出共用同一份音效，该字段仅用于诊断与日志。
const VOICE_PLAY_MODE_USE: String = "use"

## 卡牌音频动作模式：打出（响应消耗）；牌源文件不会在打出流程中被回调，因此必须由核心统一出口触发。
const VOICE_PLAY_MODE_RESPOND: String = "respond"

## 卡牌动作类别：使用。牌进入处理区并产生牌面效果，例如成为【杀】的目标时使用【闪】抵消该【杀】、濒死时使用【桃】救援、使用【无懈可击】抵消锦囊。
## “使用”既不是“打出”也不是“弃置”：牌离开手牌区时先进入处理区再进入弃牌堆，不构成一次“弃置牌”动作，因此不派发 cardsDiscardedBatchAfter。
const CARD_ACTION_USE: String = "use"

## 卡牌动作类别：打出。牌进入处理区但不产生牌面效果，例如响应【决斗】【南蛮入侵】打出的【杀】、响应【万箭齐发】打出的【闪】。
## “打出”同样不是“弃置”：牌经过处理区进入弃牌堆，不构成一次“弃置牌”动作，不派发 cardsDiscardedBatchAfter。
const CARD_ACTION_PLAY: String = "play"

## 全部合法卡牌动作类别；内容层声明 response_action 时只允许使用这两个稳定取值。
const CARD_ACTIONS: Array[String] = [CARD_ACTION_USE, CARD_ACTION_PLAY]

## 响应请求缺省动作类别；调用方未在响应上下文中声明 response_action 时按“打出”处理，保持未迁移内容的既有语义。
const DEFAULT_RESPONSE_ACTION: String = CARD_ACTION_PLAY

## 响应模式唯一确定的动作类别；【无懈可击】【桃】【酒】只有“使用”一种合法动作。
## 【杀】与【闪】既可能被使用也可能被打出，因此不在本表登记，必须由发起响应的内容显式声明。
const RESPONSE_PATTERN_ACTION_DEFAULTS: Dictionary = {
	"wuxie":CARD_ACTION_USE,
	"tao":CARD_ACTION_USE,
	"jiu":CARD_ACTION_USE,
}

## 技能显式播放抑制窗口（秒）；内容层在发动过程中调用 play_voice() 后，统一出口在该窗口内不再重复请求。
## 默认3秒足以覆盖“点技能按钮 → 选择材料与目标 → 确认发动”的完整交互，又能在发动被取消后自然过期。
const EXPLICIT_VOICE_SUPPRESS_WINDOW_SECONDS: float = 3.0

## 音频请求去重表容量上限；达到上限后清空重建，避免长局中条目无限增长。
const VOICE_REQUEST_TOKEN_CAPACITY: int = 512

## 技能元数据手动接管取值；技能声明 voice_trigger 为该值时核心层不再自动触发语音，由技能源码自行决定时机。
const VOICE_TRIGGER_MANUAL: String = "manual"

## 牌区转移数据中标识摸牌表现批次的私有键；只存在于瞬时信号副本，绝不写入 CardInstance、存档或回放状态。
const DRAW_PRESENTATION_BATCH_ID_KEY: String = "_draw_presentation_batch_id"

## 统一选择请求信号；选牌、选目标与组合选择都先发送可序列化询问，再提交兼容 choose_cards 动作。
signal card_choice_requested(choice_data: Dictionary)

## 过关斩将整层敌方重新入场后的流程任务键；同一时刻最多允许一条等待机缘的预览任务。
const CONQUEST_REPLACEMENT_OPPORTUNITY_TASK_KEY: String = "conquest_enemy_replacement_opportunity"

## 统一结算管线允许的通用规则续接类型；字符串不在此表时于登记阶段局部拒绝，避免无处理分支的记录静默丢失。
const RULE_CONTINUATION_TYPES: Array[String] = [
	"rule_sequence",
	"skill_response",
	"card_response",
	"equipment_response",
	"trick_negation_response",
	"simultaneous_negation_response",
	"slash_flow",
	"recast_draw",
	"current_player_death",
	"round_end_restore",
	"conquest_enemy_defeat",
	"conquest_enemy_replacement",
	"opportunity_resolution",
	"ahha_moment_resolution",
]

## 阶段转换协调组件脚本；显式预加载保证新工程首次无头启动时不依赖编辑器的全局类缓存扫描顺序。
## 阶段生命周期服务；前置与结束窗口由规则步骤持有唯一恢复点。
const PHASE_LIFECYCLE_SERVICE_SCRIPT: Script = preload("res://scripts/core/phase_lifecycle_service.gd")

## 回合开始内容组件；轮开始、翻面与准备阶段共享标准步骤协议。
const TURN_START_SERVICE_SCRIPT: Script = preload("res://scripts/core/turn_start_service.gd")

const GAME_FLOW_TRANSITION_COORDINATOR_SCRIPT: Script = preload("res://scripts/core/game_flow_transition_coordinator.gd")

## 公共选牌展示变化信号；五谷丰登等公开流程通过该信号让所有观察者持续看到固定牌位与领取归属。
signal public_card_choice_display_changed(display_data: Dictionary)

## 选将快照变化信号；只包含观察者可见候选、公开领袖武将和全员确认状态。
signal character_selection_changed(snapshot: Dictionary)

## 停滞自修复完成信号；看门狗触发修复且对局状态确实发生变化后发送，界面据此显示自动修复提醒横幅。
## 报告只包含可序列化诊断字段（修复级别、动作列表、阶段），不携带事件对象或内部队列引用。
signal self_repair_performed(repair_report: Dictionary)

## 过关斩将临时退出存档就绪信号；玩家预约临时退出后，控制器在下一个干净回合边界构建完整存档并发出。
## 存档字典只包含可序列化数据；文件写入与返回主菜单由界面层负责，规则核心不接触文件系统。
signal conquest_exit_save_ready(save_data: Dictionary)

## 默认牌堆 ID；可在检查器中替换为后续扩展牌堆，运行时通常无需动态修改。
@export var default_deck_id: String = "standard_162"

## 默认玩家人数；支持2至10，直接运行演示场景时创建8人局，运行时可在新开局前修改。
## 当前正式主场景会先显示主菜单，默认8人只在玩家确认开始或局内重新开局时用于创建身份局。
@export_range(2, 10, 1) var default_player_count: int = 8

## 人类本地玩家当前座次；默认0作为随机分配前的有效占位值，设为 -1 可运行纯 AI 自动对局。
@export_range(-1, 9, 1) var local_human_player_id: int = 0

## 是否在每局创建时为本地人类玩家重新随机分配座次；默认开启以保证本地玩家不固定在一号位，纯 AI 模式不受影响。
@export var randomize_local_human_seat: bool = true

## 自动触发全体机缘组件的模式稳定ID列表；默认只包含机缘大乱斗，其他模式可在检查器中直接追加复用。
@export var opportunity_enabled_mode_ids: Array[String] = ["opportunity_brawl"]

## 允许按明确模式时机触发机缘的模式稳定ID列表；默认过关斩将在开局与整层敌方全部阵亡后触发全体投票或各自选择。
@export var opportunity_manual_mode_ids: Array[String] = ["conquest"]

## AI 每次行动或选择响应前的等待秒数；默认0.30秒，局内菜单可在0.05至1.00秒范围内动态同步，测试可直接覆盖。
@export_range(0.05, 1.0, 0.05) var ai_action_delay_seconds: float = 0.30

## 相邻阶段与自动响应之间的最小等待秒数；正式菜单限制为0.1至1.0秒，规则测试可设为0关闭表现节奏。
@export_range(0.0, 1.0, 0.1) var game_flow_interval_seconds: float = 0.30

## 过关斩将敌方死亡后等待区域弃牌表现完成、再让新武将入场并弹出机缘的等待秒数；默认1.20秒，测试可设为0关闭表现节奏。
@export_range(0.0, 5.0, 0.05) var conquest_enemy_replacement_opportunity_delay_seconds: float = 1.20

## 延时锦囊进入中央展示后等待再开始无懈与判定的秒数；默认1.00秒保证玩家能辨认当前结算牌，运行时通常无需动态修改。
@export_range(0.0, 3.0, 0.05) var delayed_judgment_preview_seconds: float = 1.00

## 一张延时锦囊完成判定后等待再处理下一张的秒数；默认1.00秒让判定结果与下一张牌保持清晰间隔，运行时通常无需动态修改。
@export_range(0.0, 3.0, 0.05) var delayed_judgment_result_pause_seconds: float = 1.00

## 单个 AI 出牌阶段最多执行的动作数；默认64用于防止扩展牌循环导致界面停滞。
@export_range(1, 256, 1) var max_ai_actions_per_turn: int = 64

## 单次多选请求最多枚举的 AI 牌组组合数；默认256兼顾弃牌质量与大手牌组合爆炸风险，运行时通常无需修改。
@export_range(16, 1024, 16) var max_ai_choice_combinations: int = 256

## AI选择的策略动作与规则回退动作都提交失败后允许重新决策的次数；默认2次，耗尽后中断单个失效请求以保护整局流程。
@export_range(0, 5, 1) var max_ai_choice_submit_retries: int = 2

## 单帧统一结算管线最多恢复的后续步骤数；默认256防止异常扩展形成同步死循环，达到上限后会延后一帧继续且不会越过未完成事件。
@export_range(16, 4096, 16) var max_settlement_steps_per_pass: int = 256

## 每个同步分片最多检查的同一时机技能数；默认64保持常规时机同步完成，大型扩展则分片续接以避免主线程长时间占用。
@export_range(8, 512, 8) var max_trigger_handlers_per_slice: int = 64

## 同一调用栈允许的规则时机嵌套深度；默认32足以容纳伤害、濒死与响应链，超限时只熔断新的最内层事件。
@export_range(8, 128, 8) var max_rule_timing_dispatch_depth: int = 32

## 同一技能续结算链允许重复进入完全相同上下文的次数；默认16兼容有限重复效果，超限后丢弃异常新步骤。
@export_range(2, 128, 1) var max_repeated_skill_settlement_steps: int = 16

## 一条技能续结算因果链允许的最大步数；默认512高于标准牌堆规模，用于熔断不断改写上下文以规避重复检测的异常链。
@export_range(64, 4096, 64) var max_skill_settlement_chain_steps: int = 512

## 同一通用规则续接因果链允许重复执行完全相同类型与上下文的次数；默认16防止父流程自我入栈。
@export_range(2, 128, 1) var max_repeated_rule_continuation_steps: int = 16

## 一条通用规则续接因果链允许的最大步数；默认512允许有限批量响应与移牌，并阻止持续改写上下文的无限续接链。
@export_range(64, 4096, 64) var max_rule_continuation_chain_steps: int = 512

## 每名玩家随机展示的可选武将数量；默认5，运行时无需动态修改，后续扩展武将库后可在检查器调整。
@export_range(1, 20, 1) var character_candidate_count: int = 5

## 特殊模式预留的首回合座次号；标准身份局不读取该值而始终由随机座次的领袖开始，运行时无需修改。
@export_range(1, 10, 1) var first_turn_seat_number: int = 1

## 座次中文数字映射；仅用于对局日志中的“X号位”展示，不参与规则计算。
const SEAT_NUMBER_CN: Array[String] = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

## 标准阶段英文 ID 到中文名；对局日志统一写“xx阶段开始/结束”。
const PHASE_LOG_NAMES: Dictionary = {
	"start": "准备阶段",
	"judgment": "判定阶段",
	"draw": "摸牌阶段",
	"play": "出牌阶段",
	"discard": "弃牌阶段",
	"finish": "结束阶段",
	"phaseZhunbei": "准备阶段",
	"phaseJudge": "判定阶段",
	"phaseDraw": "摸牌阶段",
	"phaseUse": "出牌阶段",
	"phaseDiscard": "弃牌阶段",
	"phaseJieshu": "结束阶段",
}

## 永久跳过阶段机缘效果到主要阶段ID的映射；阶段入口只通过此表查询历史，新增同类效果无需复制判断分支。
const OPPORTUNITY_PERMANENT_SKIP_EFFECT_BY_PHASE: Dictionary = {"judgment":"skip_judgment_phase", "discard":"skip_discard_phase"}


## 当前权威对局状态；开局前为 null，外部模块应优先读取快照。
var state: GameState

## 身份规则服务；负责分配表、胜负与死亡奖惩类型。
var identity_rules: IdentityRules

## 卡牌合法性服务；每次开局绑定新状态实例。
var card_rules: CardRuleService

## 角色公开标记服务；每次开局绑定新状态实例，技能只通过控制器转发端口增删与查询标记。
var player_mark_service: PlayerMarkService

## 卡牌效果执行器；每次开局绑定当前控制器操作端口与新状态。
var effect_resolver: CardEffectResolver

## 规则触发总线组件；由场景子节点提供，技能可按优先级订阅。
var event_bus: RuleEventBus

## AI 调度组件；只负责策略映射与选择，不推进阶段。
var ai_coordinator: AICoordinator

## 通信网关组件；离线模式回环，LAN/REMOTE 模式交给外部传输适配器。
var network_gateway: NetworkGateway

## 当前选将规则服务；负责候选、阶段与隐藏选择，不接触卡牌规则或界面节点。
var character_selection: CharacterSelectionService

## 当前1v1车轮战专属选将服务；只在wheel_duel模式创建并与普通选将服务互斥。
var wheel_duel_selection: WheelDuelSelectionService

## 过关斩将规则服务；集中保存关卡层数、敌方累计增益与随机机缘技能，不参与普通身份局流程。
var conquest_mode: ConquestModeService

## 当前房主调整 AI 武将服务；只在对应开局选项启用且存在 AI 时创建活动阶段。
var ai_character_adjustment: AICharacterAdjustmentService

## 当前起始手牌手气卡服务；数量关闭或全部玩家确认后为非活动状态。
var starting_hand_mulligan: StartingHandMulliganService

## 本局经过 gameDraw 时机确认的实际起始手牌数；手气卡刷新始终重新发放相同数量。
var _starting_hand_count: int = 4

## 本局 gameDraw 前后时机是否允许实际发放起始手牌；手气卡与最终日志都复用该结果。
var _starting_cards_were_dealt: bool = true

## 本局是否启用全武将、座次与身份自选；开局时从房主设置复制，之后不随菜单变化。
var _custom_character_assignment_enabled: bool = false

## 本局是否开放全部武将候选；普通模式随座次身份自选开启，过关斩将只开放武将而保持固定座次与阵营。
var _all_character_selection_enabled: bool = false

## 本局是否启用房主调整全部 AI 武将；开局时锁定。
var _customize_ai_characters_enabled: bool = false

## 本局每名玩家的手气卡张数；0关闭、1至5与10有限张数、-1无限张。
var _mulligan_limit: int = 0

## 本局 AI 是否自动评估并使用手气卡；手气卡数量为0时该值不会产生流程。
var _ai_uses_mulligan_enabled: bool = false

## 离线对局是否由本机动态控制全部角色；设置可在对局中实时切换，任何局域网模式都强制为false。
var _control_all_characters_enabled: bool = false

## 离线对局最初由玩家控制的稳定角色ID；关闭全角色控制时恢复该第一视角。
var _primary_offline_human_player_id: int = -1

## 全角色控制当前临时接管的非主视角角色ID；负数表示没有额外角色被人工接管。
var _offline_manually_controlled_player_id: int = -1

## 本局1v1车轮战明置候选数量；开局时从房主设置锁定，默认6且范围3至20。
var _wheel_duel_face_up_candidate_count: int = 6

## 本局1v1车轮战暗置候选数量；开局时从房主设置锁定，默认4且范围3至20。
var _wheel_duel_face_down_candidate_count: int = 4

## 本局每名玩家拥有的换将卡数量；开局时从房主设置锁定，0表示关闭。
var _character_replacement_count: int = 0

## 本局每名玩家获得的普通随机选将牌数；范围1至20，首任领袖的领袖技固定候选不计入该数量。
var _character_candidate_count: int = 5

## 当前对局按玩家 ID 分组的独立技能实例；每个技能文件自行安装事件订阅与主动发动函数，重新开局时整体卸载。
var skill_instances_by_player: Dictionary = {}

## 当前对局按实体牌 UID 索引的持续卡牌实例；装备离开区域或重新开局时会精确卸载对应事件订阅。
var card_runtime_instances: Dictionary = {}

## 事件树运行时；统一管理根事件、子事件、after 队列、选择暂停和回放历史。
var event_scheduler: EventScheduler

## 对局级令牌暂停服务；界面和调试入口只通过公开申请/释放接口控制暂停，不直接改写场景树。
var gameplay_pause_service: GameplayPauseService

## 对局流程节奏组件；只负责可取消计时，不读取规则状态或决定下一阶段。
var game_flow_pacer: GameFlowPacer

## 阶段转换协调组件；集中保证同一时刻只有一条有效阶段推进，迟到或重复恢复不能覆盖已登记任务。
var game_flow_transition_coordinator: Node

## 过关斩将整层结算过渡是否正在等待弃牌表现、敌方重新入场或机缘选择；true 时阻止旧回合重新建立操作，表现层仍保持正常播放。
var _conquest_replacement_transition_active: bool = false

## 过关斩将换将期间冻结事件树的全局暂停令牌；-1表示未冻结，只阻止规则推进而不暂停弃牌动画与界面输入。
var _conquest_replacement_settlement_pause_token: int = -1

## 过关斩将临时退出预约标志；true 表示玩家已请求在当前结算完成后的下一个干净回合边界存档退出。
## 只在离线过关斩将中由界面入口写入，回合边界成功存档、取消预约或重新开局都会恢复 false。
var _conquest_temporary_exit_requested: bool = false

## 触发器排序组件；保留与同步 RuleEventBus 的兼容边界，逐步承载技能时机排序。
var trigger_manager: TriggerManager

## 统一规则时机派发服务；负责普通订阅、四角色过滤、优先级与座次排序，不执行具体玩法效果。
var timing_service: RuleTimingService

## 轮回技权威状态服务；集中维护轮回数、轮回节、永劫与通用限次，不执行具体技能效果。
var reincarnation_skill_service: ReincarnationSkillService

## 玩家区域废除服务；集中编排单装备栏、整个装备区与判定区的时机、弃牌和状态变更。
var player_zone_abolition_service: PlayerZoneAbolitionService

## 纯查询修正管线；技能与装备只通过该管线修改合法性查询，不直接改写控制器状态。
var modifier_pipeline: RuleModifierPipeline

## 当前对局纯查询门面；UI、AI 和规则组件共享同一合法性查询入口。
var rule_query: RuleQuery

## 实体牌唯一移动服务；新移牌记录写入 GameState.card_move_history。
var card_movement: CardMovementService

## 使用牌事件树构建组件；只声明 useCard 子事件拓扑，不读取状态或执行具体卡牌效果。
var card_use_event_service: CardUseEventService

## 可插拔机缘系统组件；负责全体三选一、私有候选、逆时针效果顺序与轮末保底触发。
var opportunity_system: OpportunitySystem

## 阿哈时刻系统组件；负责回合开始前的欢愉技触发判定、参演编号排序与串行演出推进。
var ahha_moment_system: AhhaMomentSystem

## 对局停滞自修复看门狗组件；只通过控制器公开诊断与修复端口工作，检测阈值可在检查器中调整。
var stall_watchdog: StallWatchdogService

## 上一轮硬修复时仍未解决的兼容选择请求ID；同一请求连续两轮硬修复仍卡住才会被强制中断，-1表示无记录。
var _stall_repair_last_stuck_request_id: int = -1

## 自动开局种子序号步长；使用大质数拉开相邻重开种子，避免与单调毫秒时间形成短周期重复。
const AUTOMATIC_MATCH_SEED_SERIAL_STEP: int = 104729

## 自动开局种子的系统时间换算倍率；把Unix秒转换为微秒，保证完整退出后重新启动也能取得新的跨进程时间分量。
const AUTOMATIC_MATCH_SEED_MICROSECONDS_PER_SECOND: int = 1000000

## 自动开局种子的进程号混合步长；使用质数让极短时间内重启产生的不同进程号不会直接落入相邻种子。
const AUTOMATIC_MATCH_SEED_PROCESS_STEP: int = 8191

## 对局随机数生成器；牌堆、身份与武将选择统一使用，便于未来记录种子回放。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 弃置批次栈；每次面向规则的弃置动作占一层，用于把“一次弃置多张”的牌聚合成一个批次事件。
## 每层键为 batch_id（稳定批次号）、player_id（本次弃置的主体角色）、reason（弃置原因）、card_uids（本批已进入弃牌堆的牌）。
## 使用栈而非单变量，使批次内技能连锁产生的新弃置动作可以各自成批，不会污染外层批次。
var _discard_batch_stack: Array[Dictionary] = []

## 下一个弃置批次号；从1起单调递增，只用于事件载荷的稳定标识，规则逻辑不得依赖其具体数值。
var _next_discard_batch_id: int = 1

## 自动开局种子自增序号；同一毫秒内连续重开时仍保证每局获得不同随机序列，避免斗地主座位与身份固定。
var _automatic_match_seed_serial: int = 0

## 上一局自动斗地主中本地玩家的座次索引；范围为0至4，-1表示当前控制器尚未完成自动斗地主开局。
var _last_automatic_doudizhu_local_seat_index: int = -1

## 上一局自动斗地主中本地玩家的身份ID；取landlord或peasant，空字符串表示尚无可比较的上一局结果。
var _last_automatic_doudizhu_local_identity: String = ""

## 当前 AI 出牌阶段已执行动作数；开始新回合时清零。
var _ai_actions_this_turn: int = 0

## AI 延迟任务令牌；任何阶段切换都会递增，使旧的异步回调自动失效。
var _ai_drive_token: int = 0

## 已安排但尚未执行的 AI 任务令牌；与当前令牌相同时禁止重复创建计时器，默认-1表示没有待执行任务。
var _scheduled_ai_drive_token: int = -1

## 已安排但尚未提交的 AI 选牌请求 ID；默认-1表示没有等待中的 AI 响应，避免同一请求创建多个计时器。
var _scheduled_ai_choice_request_id: int = -1

## 每个AI选择请求已经连续提交失败的次数；请求成功、被中断或对局重置时立即清除，键为全局请求ID。
var _ai_choice_submit_failures: Dictionary = {}

## 当前是否正在批量驱动 AI 选将；防止阶段推进时递归处理旧待选列表并产生重复提交。
var _is_driving_character_selection: bool = false

## 当前等待提交的统一选择请求；空字典表示没有响应、弃牌、区域选牌、技能目标或组合选择窗口。
var _pending_card_choice: Dictionary = {}

## 当前同时等待的无懈可击请求；键为请求 ID，值为该玩家的私有候选与可序列化恢复上下文。
var _pending_negation_choices: Dictionary = {}

## 当前规则时机派发开始前已有的普通选择请求 ID；-1表示无请求，用于只暂停本时机中新建的技能询问。
var _rule_timing_initial_choice_request_id: int = -1

## 当前规则时机派发是否正在执行；true 时选择创建可通知 TriggerManager 暂停并按座次续问。
var _is_dispatching_rule_timing: bool = false

## 摸牌表现批次递增序号；每次 draw() 调用获得唯一值，使多张同步摸牌与连续多次摸牌都能独立居中播放。
var _draw_presentation_batch_sequence: int = 0

## 当前正在发出移牌信号的摸牌表现批次；空字典表示普通移牌，不向界面附加批次信息。
var _active_draw_presentation_batch: Dictionary = {}

## 当前无懈可击同时响应轮次序号；每创建一轮递增，用于让迟到 AI 任务安全失效。
var _negation_round_sequence: int = 0

## 最近一次同步完成请求所选择的实体牌 UID；只供无交互测试与兼容回退在当前调用栈读取，正式 AI 请求始终异步恢复。
var _resolved_card_choice_uids: Array[int] = []

## 最近一次同步完成请求所选择的目标玩家 ID；只供技能测试与无交互回退读取，正式交互通过 continue_selection 恢复。
var _resolved_target_choice_ids: Array[int] = []

## 最近一次同步完成请求所选择的文字控制项 ID；空字符串表示取消、尚未选择或正式异步流程仍在等待。
var _resolved_control_choice_id: String = ""

## 最近一次同步选择随装备技能提交的实体材料 UID；丈八蛇矛响应会读取恰好两张手牌，其他选择保持空数组。
var _resolved_equipment_material_uids: Array[int] = []

## 最近一次同步响应明确选择的转化技能ID；空字符串表示使用实体响应牌或没有完成响应。
var _resolved_response_skill_id: String = ""

## 全局选择请求序号；每次创建窗口递增，防止旧界面或网络消息误提交到新请求。
## 当前实现只镜像 EventScheduler 最近一次分配的全局编号，不再维护第二套独立请求序列。
var _card_choice_sequence: int = 0

## 无懈可击延迟提交后的单次恢复结果；键包含原牌 UID 与目标，读取一次后立即删除。
var _negation_resume_results: Dictionary = {}

## 当前仍在逐目标结算的卡牌上下文；键为原实体牌 UID，值保存目标游标、共享伤害参数与当前目标状态。
var _active_card_resolutions: Dictionary = {}

## 当前尚未完成 contentAfter 的 CardUseEvent 上下文；键为实体 UID，值保存事件 ID、使用者和最终区域。
var _card_use_contexts: Dictionary = {}

## 需要在持有者下个回合结束时清理的手牌视为效果；键为实体UID，值保存持有者、来源技能与被标记的到期回合。
var _hand_view_as_turn_expiries: Dictionary = {}


## 活动的可暂停步骤内容；键为单调序列ID，只有内存持有Callable，续接队列只保存ID与游标。
var _rule_sequences: Dictionary = {}

## 下一步骤序列身份；跨重开保持单调，旧选择不能命中新序列。
var _next_rule_sequence_id: int = 1

## 当前正在执行内容步骤的调用深度；同步AI应答只回写结果，不允许在回调返回前重入续接管线。
var _rule_sequence_execution_depth: int = 0

## 已成功进入 Begin 的阶段生命周期集合；键为“玩家ID:阶段名”，防止跳过或取消阶段伪造 End 与 After。
var _started_phase_lifecycles: Dictionary = {}

## 技能插入阶段的单调身份；跨重置不复用，父序列按身份等待新子阶段，避免等待自己的外层阶段。
var _next_inserted_phase_id: int = 1

## 等待当前响应子事件完成后询问的银月枪触发队列；每项保存持有者和黑色实体牌 UID，不持有界面或事件对象引用。
var _queued_equipment_triggers: Array[Dictionary] = []

## 当前对局根事件 ID；所有阶段、卡牌、伤害和选择记录默认挂在该根事件下。
var _runtime_root_event_id: int = -1

## 当前回合 phase 事件 ID；阶段内选择恢复后继续使用同一父事件，默认-1表示尚未开始回合。
var _current_turn_event_id: int = -1

## 当前出牌阶段 chooseToUse 请求 ID；每次使用牌后创建新请求，明确结束阶段后清空。
var _play_choice_request_id: int = -1

## 当前出牌阶段 chooseToUse 事件 ID；标准动作会转换为该事件的 ChoiceResponse。
var _play_choice_event_id: int = -1

## 当前 chooseToUse 请求所属玩家 ID；用于拒绝旧回合或替换状态后的残留请求。
var _play_choice_actor_id: int = -1

## 当前 chooseToUse 请求所属对局 ID；规则测试替换 GameState 时不会误消费上一局请求。
var _play_choice_match_id: String = ""

## 当前对局牌面表现递增序号；每次使用、展示或判定递增，重新开局时归零。
var _card_presentation_sequence: int = 0

## 音频请求去重表；键为“类别|玩家|定义|事件令牌|动作模式”，命中即跳过重复请求，防止同一动作重复发声。
var _voice_request_tokens: Dictionary = {}

## 音频表现序号；每次音频请求自增一次，仅供表现层诊断与日志排序使用，不参与任何规则判定。
var _voice_presentation_sequence: int = 0

## 当前判定区顺序流程代次；重新开局、换回合或重新启动判定链时递增，使旧计时器无法继续修改新状态。
var _judgment_flow_token: int = 0

## 当前是否已有一条判定区顺序流程正在等待或结算；默认false，防止选择恢复重复创建并行计时器。
var _judgment_flow_in_progress: bool = false

## 判定流程从异步无懈或濒死选择恢复时是否需要先保留上一张判定结果；默认false，新回合从延时锦囊展示开始。
var _judgment_resume_needs_result_pause: bool = false

## 当前等待判定前技能完成的判定请求；空字典表示没有判定，内容只保存玩家、原因、阶段和可序列化后续接收者。
var _pending_judgment_request: Dictionary = {}

## 当前暂停判定对应的规则事件对象；仅用于在同一 judgeBefore 或 judgeBegin 续列恢复后读取取消状态，不进入快照或回放数据。
var _pending_judgment_rule_event: RuleEvent = null

## 判定请求递增序号；每次建立新请求加一，用于日志诊断与防止旧恢复上下文接管后续判定。
var _judgment_request_sequence: int = 0

## 对局级暂停在事件运行时持有的全局 token；-1表示当前没有同步阻塞事件栈。
var _gameplay_event_pause_token: int = -1

## 等待执行的额外完整回合角色队列；角色 ID 按技能结算顺序追加，死亡角色在执行前安全跳过。
var _extra_turn_queue: Array[int] = []

## 额外回合结束后需要恢复的原行动角色栈；最外层记录原当前角色的正常下家。
var _extra_turn_resume_player_ids: Array[int] = []

## 回合开始前机缘立即执行额外回合时待恢复的待开始回合上下文；键为玩家ID与starts_new_round，空字典表示额外回合链结束后恢复正常下家。
var _pending_turn_start_context: Dictionary = {}

## 当前回合是否属于额外回合；用于阻止额外回合结束时错误按该角色座次推进正常轮转。
var _current_turn_is_extra: bool = false

## 每名角色等待执行的额外出牌阶段数量；键为玩家 ID，值为尚未消费的正整数次数。
var _extra_play_phase_counts: Dictionary = {}

## 从弃牌阶段获得且完成后应直接进入结束阶段的额外出牌阶段标记；键为玩家 ID，值为是否存在该返回语义。
var _extra_play_phase_returns_to_finish: Dictionary = {}

## 每名角色等待执行的额外出牌阶段后继队列；每项保存阶段结束后应进入 discard、finish 或 turn_complete，避免选择窗口覆盖原阶段后丢失插入语义。
var _extra_play_phase_return_points: Dictionary = {}

## 当前正在执行的额外出牌阶段上下文；空字典表示当前出牌阶段属于标准回合流程。
var _active_extra_play_phase_context: Dictionary = {}

## 当前回合已被转换为出牌阶段的主要阶段集合；键为玩家ID，值为原主要阶段名数组，不使用跳过或额外阶段队列表达。
var _main_phase_play_conversions: Dictionary = {}

## 当前正在执行的转换后出牌阶段上下文；保存原阶段与结束后继，确保日志和阶段次数均按普通出牌阶段处理。
var _active_converted_play_phase_context: Dictionary = {}

## 当前由技能插入的独立额外弃牌阶段上下文；空字典表示没有等待阶段触发、弃牌选择或完成回调。
var _active_extra_discard_phase: Dictionary = {}

## 当前由技能插入、可属于非当前回合角色的独立额外出牌阶段；保存原回合展示与技能完成回调，空字典表示没有活动阶段。
var _active_independent_play_phase: Dictionary = {}
## 等待嵌套规则选择结束后继续的技能结算队列；仅保存技能 ID、持有者 ID 与可序列化上下文，不持有 Callable 或技能对象。
var _deferred_skill_settlements: Array[Dictionary] = []

## 下一条技能续结算的稳定编号；从1递增，重新开局时恢复为1。
var _next_skill_settlement_id: int = 1

## 当前正在恢复的技能续结算语义键；空字符串表示未处于continue_settlement回调内。
var _active_skill_settlement_key: String = ""

## 当前技能续结算因果链已访问的语义键次数；子步骤继承深拷贝，独立初始步骤互不影响。
var _active_skill_settlement_visits: Dictionary = {}

## 当前技能续结算因果链已执行的步数；初始步骤为1，子步骤逐一增加。
var _active_skill_settlement_chain_steps: int = 0

## 统一结算管线是否正在同步排空；true时的重入请求只登记唯一延后唤醒。
var _settlement_pipeline_running: bool = false

## 是否已经向场景树登记一次延后结算唤醒；同一时刻最多为true一次。
var _settlement_resume_scheduled: bool = false

## 结算延后唤醒代次；重新开局或拆除运行时时递增，使旧call_deferred回调自动失效。
var _settlement_resume_generation: int = 1

## 当前帧唤醒的唯一信号连接；默认空Callable，接管、重置或离树时主动断开，避免旧连接积累。
var _settlement_resume_callback: Callable = Callable()

## 最近一次统一结算故障的可序列化摘要；空字典表示本局尚未发生局部熔断。
var _last_settlement_fault: Dictionary = {}

## 本局统一结算局部熔断的累计次数；仅供诊断与测试，不修改任何玩法数值。
var _settlement_fault_count: int = 0

## 被嵌套选择中断的通用规则续接栈；响应、救援、重铸和父牌收尾只保存稳定类型与可序列化上下文。
var _rule_continuations: RuleContinuationQueue = RuleContinuationQueue.new()

## 当前正在恢复的通用规则续接语义键；空字符串表示未处于续接回调内。
var _active_rule_continuation_key: String = ""

## 当前通用规则续接因果链的语义键访问次数；新的独立父流程不继承旧记录。
var _active_rule_continuation_visits: Dictionary = {}

## 当前通用规则续接因果链已执行步数；子续接在父回调内登记时递增。
var _active_rule_continuation_chain_steps: int = 0

## 已预约临时退出但仍等待结算管线排空的下一回合角色；-1表示没有挂起的边界重试。
var _pending_conquest_boundary_player_id: int = -1

## 当前全局回合内各角色已经“使用”过的逻辑牌定义；响应牌仅在规则明确视为使用时由对应流程登记。
var _cards_used_this_turn_by_player: Dictionary = {}

## 局域网客户端最近一次收到的观察者裁剪快照；只供远端 UI 预览与渲染，不重建或替代权威 GameState。
var _remote_snapshot: Dictionary = {}

## 当前由控制器内部 AI 调度提交动作的玩家嵌套计数；仅此上下文可执行托管玩家动作，网络封包无法伪造该权限。
var _ai_submission_depth_by_player: Dictionary = {}

## 最近一次权威动作拒绝原因；网络命令入口在同步提交失败后读取并只返回给原发送者。
var _last_action_rejection_message: String = ""


## 绑定场景中的解耦组件并初始化身份规则服务。
func _ready() -> void:
	event_bus = get_node("RuleEventBus") as RuleEventBus
	_configure_rule_dispatch_guards()
	ai_coordinator = get_node("AICoordinator") as AICoordinator
	network_gateway = get_node("NetworkGateway") as NetworkGateway
	opportunity_system = get_node_or_null("OpportunitySystem") as OpportunitySystem
	if opportunity_system == null:
		opportunity_system = OpportunitySystem.new()
		opportunity_system.name = "OpportunitySystem"
		add_child(opportunity_system)
	ahha_moment_system = get_node_or_null("AhhaMomentSystem") as AhhaMomentSystem
	if ahha_moment_system == null:
		ahha_moment_system = AhhaMomentSystem.new()
		ahha_moment_system.name = "AhhaMomentSystem"
		add_child(ahha_moment_system)
	gameplay_pause_service = get_node_or_null("GameplayPauseService") as GameplayPauseService
	if gameplay_pause_service == null:
		gameplay_pause_service = GameplayPauseService.new()
		gameplay_pause_service.name = "GameplayPauseService"
		add_child(gameplay_pause_service)
	game_flow_pacer = get_node_or_null("GameFlowPacer") as GameFlowPacer
	if game_flow_pacer == null:
		game_flow_pacer = GameFlowPacer.new()
		game_flow_pacer.name = "GameFlowPacer"
		add_child(game_flow_pacer)
	game_flow_transition_coordinator = get_node_or_null("GameFlowTransitionCoordinator")
	if game_flow_transition_coordinator == null:
		game_flow_transition_coordinator = GAME_FLOW_TRANSITION_COORDINATOR_SCRIPT.new()
		game_flow_transition_coordinator.name = "GameFlowTransitionCoordinator"
		add_child(game_flow_transition_coordinator)
	game_flow_transition_coordinator.bind(game_flow_pacer)
	event_scheduler = get_node_or_null("EventScheduler") as EventScheduler
	if event_scheduler == null:
		event_scheduler = EventScheduler.new()
		event_scheduler.name = "EventScheduler"
		add_child(event_scheduler)
	stall_watchdog = get_node_or_null("StallWatchdogService") as StallWatchdogService
	if stall_watchdog == null:
		stall_watchdog = StallWatchdogService.new()
		stall_watchdog.name = "StallWatchdogService"
		add_child(stall_watchdog)
	stall_watchdog.bind(self)
	_connect_event_runtime()
	identity_rules = IdentityRules.new()
	card_use_event_service = CardUseEventService.new()
	if trigger_manager == null:
		trigger_manager = TriggerManager.new()
	timing_service = RuleTimingService.new(event_bus, trigger_manager, state)
	timing_service.set_trigger_pause_condition(Callable(self, "_should_pause_rule_timing_dispatch"))
	network_gateway.command_received.connect(_on_network_command_received)
	if not network_gateway.choice_response_received.is_connected(_on_network_choice_response_received):
		network_gateway.choice_response_received.connect(_on_network_choice_response_received)
	if not network_gateway.snapshot_received.is_connected(_on_network_snapshot_received):
		network_gateway.snapshot_received.connect(_on_network_snapshot_received)
	if not network_gateway.choice_request_received.is_connected(_on_network_choice_request_received):
		network_gateway.choice_request_received.connect(_on_network_choice_request_received)
	if not network_gateway.game_event_received.is_connected(_on_network_game_event_received):
		network_gateway.game_event_received.connect(_on_network_game_event_received)
	if not network_gateway.lan_match_peer_disconnected.is_connected(_on_lan_match_peer_disconnected):
		network_gateway.lan_match_peer_disconnected.connect(_on_lan_match_peer_disconnected)
	if not network_gateway.lan_match_peer_reconnected.is_connected(_on_lan_match_peer_reconnected):
		network_gateway.lan_match_peer_reconnected.connect(_on_lan_match_peer_reconnected)
	if not log_added.is_connected(_replicate_log_event):
		log_added.connect(_replicate_log_event)
	if not card_presentation_requested.is_connected(_replicate_card_presentation_event):
		card_presentation_requested.connect(_replicate_card_presentation_event)
	if not card_transfer_requested.is_connected(_replicate_card_transfer_event):
		card_transfer_requested.connect(_replicate_card_transfer_event)
	if not draw_presentation_batch_started.is_connected(_replicate_draw_batch_started_event):
		draw_presentation_batch_started.connect(_replicate_draw_batch_started_event)
	if not draw_presentation_batch_finished.is_connected(_replicate_draw_batch_finished_event):
		draw_presentation_batch_finished.connect(_replicate_draw_batch_finished_event)
	if not card_animation_ownership_reset_requested.is_connected(_replicate_card_animation_reset_event):
		card_animation_ownership_reset_requested.connect(_replicate_card_animation_reset_event)
	if not skill_activated.is_connected(_replicate_skill_activated_event):
		skill_activated.connect(_replicate_skill_activated_event)
	if not equipment_activated.is_connected(_replicate_equipment_activated_event):
		equipment_activated.connect(_replicate_equipment_activated_event)
	if not voice_presentation_requested.is_connected(_replicate_voice_presentation_event):
		voice_presentation_requested.connect(_replicate_voice_presentation_event)
	if not public_card_choice_display_changed.is_connected(_replicate_public_card_choice_display_event):
		public_card_choice_display_changed.connect(_replicate_public_card_choice_display_event)
	if not match_finished.is_connected(_replicate_match_finished_event):
		match_finished.connect(_replicate_match_finished_event)
	if not GameSettings.ai_response_delay_changed.is_connected(_on_ai_response_delay_changed):
		GameSettings.ai_response_delay_changed.connect(_on_ai_response_delay_changed)
	if not GameSettings.game_speed_changed.is_connected(_on_game_speed_changed):
		GameSettings.game_speed_changed.connect(_on_game_speed_changed)
	if not GameSettings.control_all_characters_changed.is_connected(_on_control_all_characters_changed):
		GameSettings.control_all_characters_changed.connect(_on_control_all_characters_changed)
	if not gameplay_pause_service.pause_state_changed.is_connected(_on_gameplay_pause_state_changed):
		gameplay_pause_service.pause_state_changed.connect(_on_gameplay_pause_state_changed)
	_on_ai_response_delay_changed(GameSettings.ai_response_delay_seconds)
	_on_game_speed_changed(GameSettings.game_speed_interval_seconds)


## 连接事件运行时信号并把只读摘要同步到 GameState；界面和网络只读取状态快照。
func _connect_event_runtime() -> void:
	if event_scheduler == null:
		return
	if not event_scheduler.event_started.is_connected(_on_runtime_event_started):
		event_scheduler.event_started.connect(_on_runtime_event_started)
	if not event_scheduler.event_finished.is_connected(_on_runtime_event_finished):
		event_scheduler.event_finished.connect(_on_runtime_event_finished)
	if not event_scheduler.choice_requested.is_connected(_on_runtime_choice_requested):
		event_scheduler.choice_requested.connect(_on_runtime_choice_requested)
	if not event_scheduler.choice_resolved.is_connected(_on_runtime_choice_resolved):
		event_scheduler.choice_resolved.connect(_on_runtime_choice_resolved)
	if not event_scheduler.event_faulted.is_connected(_on_runtime_event_faulted):
		event_scheduler.event_faulted.connect(_on_runtime_event_faulted)


## 申请一个对局级暂停令牌；调用方必须保存返回值，并只释放自己持有的令牌。
func acquire_gameplay_pause(reason: String) -> int:
	return gameplay_pause_service.acquire_pause(reason) if gameplay_pause_service != null else -1


## 释放指定对局级暂停令牌；其他调用方仍持有令牌时不会恢复对局或 AI。
func release_gameplay_pause(token_id: int) -> bool:
	return gameplay_pause_service.release_pause(token_id) if gameplay_pause_service != null else false


## 返回对局是否正被任一接口令牌暂停；AI 调度、测试和调试器共用该只读入口。
func is_gameplay_paused() -> bool:
	return gameplay_pause_service != null and gameplay_pause_service.is_paused()


## 把对局级暂停状态同步到事件运行时；全局 token 保证任何直接 drain 调用也不能跨暂停推进规则。
func _on_gameplay_pause_state_changed(paused: bool, _active_reasons: Array[String]) -> void:
	if event_scheduler == null:
		return
	if paused:
		if _gameplay_event_pause_token < 0:
			_gameplay_event_pause_token = event_scheduler.pause_registry.acquire("gameplay", -1, "gameplay_pause_interface")
		return
	if _gameplay_event_pause_token >= 0:
		# 当前事件运行时暂停 token；先清空字段再恢复，避免 drain 期间重入重复释放同一 token。
		var runtime_pause_token: int = _gameplay_event_pause_token
		_gameplay_event_pause_token = -1
		event_scheduler.resume(runtime_pause_token, "gameplay_resumed")
	call_deferred("_resume_ai_after_gameplay_pause")


## 对局恢复后补齐暂停前尚未安排的 AI 入口；已经存在的暂停感知计时器会自行继续，不会重复创建。
func _resume_ai_after_gameplay_pause() -> void:
	if is_gameplay_paused() or state == null or state.game_over:
		return
	if _redrive_pre_game_ai_progress():
		return
	_ensure_ai_progress_after_resolution()


## 按当前预开局阶段补齐AI驱动；托管接管、暂停恢复与停滞修复共用本唯一分派，避免多份阶段清单彼此漂移。
## 返回true表示当前处于预开局阶段且已执行对应驱动；手气卡驱动后所有玩家可能已确认，此时必须走唯一完成出口。
func _redrive_pre_game_ai_progress() -> bool:
	if state == null or state.game_over:
		return false
	if state.current_phase == "character_selection":
		_drive_ai_character_selection()
		return true
	if state.current_phase == "wheel_duel_selection":
		_drive_ai_wheel_duel_selection()
		return true
	if state.current_phase == "starting_hand_mulligan":
		_drive_ai_starting_hand_mulligan()
		# AI补齐后可能全部玩家均已确认；服务不再活动时复制开局入口的完成检查，防止阶段停在已结束的手气卡。
		if starting_hand_mulligan != null and not starting_hand_mulligan.active:
			_complete_pre_game_start()
		return true
	return false


## 返回对局停滞诊断快照；看门狗只依赖本端口判断“是否可监控、是否有人类待办、对局是否仍在推进”。
## 指纹覆盖事件历史、动作序号、待办请求、暂停令牌、阶段与机缘进度，任何真实推进都会改变指纹。
func get_stall_diagnostics() -> Dictionary:
	# 当前是否具备监控条件；无对局、终局或非权威端（局域网客户端）不做任何检测与修复。
	var monitorable: bool = state != null and not state.game_over
	if network_gateway != null and network_gateway.is_lan_client():
		monitorable = false
	# 用户主动打开日志或武将详情造成的对局暂停属于正常浏览；只有机缘选择暂停仍需继续监控。
	if monitorable and gameplay_pause_service != null and gameplay_pause_service.is_paused():
		for pause_reason: String in gameplay_pause_service.get_active_reasons():
			if pause_reason != "opportunity_selection":
				monitorable = false
				break
	if not monitorable:
		return {"monitorable": false, "waiting_for_human": false, "fingerprint": ""}
	return {
		"monitorable": true,
		"waiting_for_human": is_waiting_for_human_input(),
		"fingerprint": _compose_stall_fingerprint(),
	}


## 返回当前是否存在人类可以实际操作的待办；只要该函数为真，看门狗永远不会执行强制修复。
## 死亡角色的待办没有任何人能应答，因此不计入人类等待；离场但存活的角色仍可作答（机缘规则允许）。
func is_waiting_for_human_input() -> bool:
	if state == null:
		return false
	# 机缘全体选择阶段；投票可能同时存在多名待提交者，只要其中任一为可应答人类就属于正常等待。
	if opportunity_system != null and opportunity_system.is_active() and str(state.opportunity_state.get("stage", "")) == "choosing":
		# 当前待提交玩家集合；旧快照缺失集合时回退单一current_chooser_id，保持各自选择与存档兼容。
		var opportunity_pending_actor_ids: Array = state.opportunity_state.get("pending_chooser_ids", []) as Array
		if opportunity_pending_actor_ids.is_empty():
			opportunity_pending_actor_ids = [int(state.opportunity_state.get("current_chooser_id", -1))]
		for opportunity_pending_actor_id_variant: Variant in opportunity_pending_actor_ids:
			if _is_answerable_human_actor(int(opportunity_pending_actor_id_variant)):
				return true
		return false
	# 开局配置阶段（选将、车轮战抓将、手气卡、房主调整AI）；存在真人参与即视为人类等待，AI部分有独立驱动。
	if state.current_phase in ["character_selection", "wheel_duel_selection", "starting_hand_mulligan", "ai_character_adjustment"]:
		if local_human_player_id >= 0:
			return true
		return network_gateway != null and network_gateway.is_lan_host() and not network_gateway.get_remote_player_assignments().is_empty()
	# 事件运行时待办请求；任意一条属于可应答人类即表示人类可以操作。
	if event_scheduler != null:
		for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
			if _is_answerable_human_actor(int(request_data.get("actor_id", -1))):
				return true
	# 兼容层普通选择与同时无懈窗口；正常情况与运行时请求一一对应，此处作为一致性兜底再查一遍。
	if not _pending_card_choice.is_empty() and _is_answerable_human_actor(int(_pending_card_choice.get("chooser_id", -1))):
		return true
	for negation_choice_variant: Variant in _pending_negation_choices.values():
		if _is_answerable_human_actor(int((negation_choice_variant as Dictionary).get("chooser_id", -1))):
			return true
	return false


## 返回指定玩家是否是“可以实际作答的人类”；AI、托管、死亡、无效ID与无人认领的座位都返回false。
## 离场但存活的角色不排除：机缘选择与部分效果允许离场角色继续作答，其界面待办仍然有效。
func _is_answerable_human_actor(player_id: int) -> bool:
	if player_id < 0 or state == null:
		return false
	if ai_coordinator != null and ai_coordinator.is_ai_controlled(player_id):
		return false
	# 当前玩家状态；未登记ID无法作答，死亡角色的待办永远不可能被回应。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return false
	if player.auto_managed:
		return false
	# 该座位必须真的绑定一个人类界面：既非AI又不属于任何真人视角的“无人认领”座位没有任何人能作答，
	# 其待办必须交给停滞修复而不是当成人类思考无限等待。
	if network_gateway != null and network_gateway.is_lan_host():
		return player_id == local_human_player_id or network_gateway.get_peer_id_for_player(player_id) > NetworkGateway.SERVER_PEER_ID
	return player_id == local_human_player_id or _control_all_characters_enabled


## 组合当前对局进度指纹；只读取稳定可序列化字段，任何事件推进、动作提交或窗口变化都会改变结果。
func _compose_stall_fingerprint() -> String:
	# 指纹片段列表；顺序固定保证相同状态生成相同指纹。
	var parts: Array[String] = []
	parts.append(state.match_id)
	parts.append(str(state.action_sequence))
	parts.append(state.current_phase)
	parts.append(str(state.current_player_id))
	if event_scheduler != null:
		parts.append(str(event_scheduler.get_event_history_count()))
		parts.append("drain:%s" % str(event_scheduler.has_pending_drain_continuation()))
		# 待办请求指纹；修订号纳入其中，技能backup/restore等上下文切换同样视为推进。
		for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
			parts.append("req:%d:%d:%d" % [int(request_data.get("request_id", -1)), int(request_data.get("actor_id", -1)), int(request_data.get("revision", 0))])
		# 活动暂停令牌指纹；令牌解决或新增都代表流程仍在变化。
		for pause_token: Dictionary in event_scheduler.pause_registry.get_active_tokens():
			parts.append("tok:%d" % int(pause_token.get("token_id", -1)))
	parts.append("cc:%d" % int(_pending_card_choice.get("request_id", -1)))
	parts.append("neg:%d" % _pending_negation_choices.size())
	# 统一结算队列指纹；队首稳定ID或类型变化都表示技能与父规则确实在推进。
	var first_skill_settlement_id: int = int(_deferred_skill_settlements.front().get("settlement_id", -1)) if not _deferred_skill_settlements.is_empty() else -1
	# 最内层通用续接类型；空栈使用空字符串，不为诊断制造伪记录。
	var top_rule_continuation_type: String = str(_rule_continuations.peek().get("continuation_type", "")) if _rule_continuations.has_pending() else ""
	parts.append("settle:%d:%d:%d:%s:%d:%s:%s" % [_deferred_skill_settlements.size(), first_skill_settlement_id, _rule_continuations.size(), top_rule_continuation_type, trigger_manager.get_deferred_dispatch_count() if trigger_manager != null else 0, str(_settlement_resume_scheduled), str(_settlement_pipeline_running)])
	parts.append("settlement_faults:%d" % _settlement_fault_count)
	# AI调度标记；软修复重排计时器同样属于对局被推动，使修复有效性判定与玩家提醒不漏掉重排类修复。
	parts.append("aisch:%d:%d" % [_scheduled_ai_drive_token, _scheduled_ai_choice_request_id])
	if game_flow_pacer != null:
		parts.append("pace:%s:%s" % [str(game_flow_pacer.has_any_pending()), str(game_flow_pacer.has_pending_skill_interval())])
	if game_flow_transition_coordinator != null:
		# 阶段转换语义键；同一个计时业务键下仍能区分当前承诺的是哪一局、哪一回合与哪一阶段。
		parts.append("transition:%s" % str(game_flow_transition_coordinator.get_pending_snapshot()))
	# 机缘进度指纹；阶段、待提交集合、结算者与已选人数变化都会更新，机缘内部并行推进不会被误判为停滞。
	if not state.opportunity_state.is_empty():
		parts.append("opp:%s:%s:%d:%d" % [str(state.opportunity_state.get("stage", "")), str(state.opportunity_state.get("pending_chooser_ids", [])), int(state.opportunity_state.get("current_resolver_id", -1)), (state.opportunity_state.get("chosen_player_ids", []) as Array).size()])
	parts.append("conq:%s" % str(_conquest_replacement_transition_active))
	parts.append("judg:%s:%s" % [str(_judgment_flow_in_progress), str(has_pending_judgment_request())])
	return "|".join(parts)


## 执行指定级别的对局停滞自修复并返回可序列化报告；空字典表示当前不允许修复（非权威端或无对局）。
## human_reminder只重发界面提示绝不代替玩家选择；soft只重排既有异步任务；hard才清理孤儿令牌与不可应答请求。
func perform_stall_self_repair(repair_kind: String) -> Dictionary:
	if state == null or state.game_over:
		return {}
	if network_gateway != null and network_gateway.is_lan_client():
		return {}
	# 本次修复实际执行的动作代码列表；空列表表示本级修复没有找到可处理的停滞原因。
	var actions: Array[String] = []
	if repair_kind == "human_reminder":
		# 重发人类待办提示；兼容选择重新广播给本地与远端，同时无懈公共展示与完整快照一并刷新。
		_republish_manual_player_choice(local_human_player_id)
		if not _pending_negation_choices.is_empty():
			_refresh_simultaneous_choice_snapshot()
		# 完整观察者快照同时重发并行机缘待办；每名局域网玩家会再次收到自己的私有候选，不依赖单一当前选择者。
		_emit_state()
		actions.append("republish_prompts")
		add_log("【自动提醒】当前有待办选择等待操作，已重新发送选择提示。")
		# 提醒报告；提醒本身不改变规则状态，effective恒为true以便界面展示横幅。
		var reminder_report: Dictionary = {"kind": repair_kind, "actions": actions, "effective": true, "phase": state.current_phase}
		self_repair_performed.emit(reminder_report.duplicate(true))
		return reminder_report
	# 修复前进度指纹；修复后指纹变化才认定本次修复确实产生效果并提醒玩家。
	var fingerprint_before: String = _compose_stall_fingerprint()
	# 第一级软修复：重排开局配置阶段的AI驱动（选将、车轮战抓将、手气卡共用统一分派）。
	if _redrive_pre_game_ai_progress():
		actions.append("redrive_pre_game_ai")
	# 软修复：兼容普通选择属于AI时清除防重标记并强制重排延时决策任务。
	if not _pending_card_choice.is_empty():
		# 当前兼容请求与应答者；防重标记清零保证即使旧协程仍标记“已安排”也能重新创建计时器。
		var pending_choice_request_id: int = int(_pending_card_choice.get("request_id", -1))
		var pending_chooser_id: int = int(_pending_card_choice.get("chooser_id", -1))
		if ai_coordinator != null and ai_coordinator.is_ai_controlled(pending_chooser_id):
			_scheduled_ai_choice_request_id = -1
			_schedule_ai_card_choice_response(pending_choice_request_id, pending_chooser_id)
			actions.append("reschedule_ai_choice:%d" % pending_choice_request_id)
	# 软修复：同时无懈窗口中属于AI的请求逐个重排延时响应任务。
	var restarted_negation_tasks: int = _redrive_pending_negation_ai_tasks()
	if restarted_negation_tasks > 0:
		actions.append("reschedule_negation_ai:%d" % restarted_negation_tasks)
	# 软修复同步重驱已存在的触发、装备、规则或技能后续；唯一唤醒不会与原有回调并行。
	if not has_pending_card_choice() and (not _queued_equipment_triggers.is_empty() or _rule_continuations.has_pending() or not _deferred_skill_settlements.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())):
		_schedule_settlement_pipeline_resume()
		actions.append("redrive_settlement_pipeline")
	# 软修复：机缘流程推进兜底；仅在完全没有待办请求时轻推，避免越过尚未回应的正常选择。
	if opportunity_system != null and opportunity_system.is_active() and event_scheduler != null and event_scheduler.get_pending_choice_requests().is_empty() and not has_pending_card_choice():
		# 当前机缘阶段；结算阶段安全重连帧推进回调，选择阶段的强制代选只属于硬修复。
		var opportunity_stage: String = str(state.opportunity_state.get("stage", ""))
		if opportunity_stage == "resolving":
			opportunity_system.continue_after_barrier()
			actions.append("nudge_opportunity_resolution")
		elif opportunity_stage == "choosing" and repair_kind == "hard":
			# 当前机缘待提交集合；并行投票逐名检查，旧各自选择状态则回退单一current_chooser_id。
			var opportunity_pending_actor_ids: Array = state.opportunity_state.get("pending_chooser_ids", []) as Array
			if opportunity_pending_actor_ids.is_empty():
				opportunity_pending_actor_ids = [int(state.opportunity_state.get("current_chooser_id", -1))]
			# 待修复名单副本；代选会原地推进机缘状态，遍历副本可避免漏掉同批次其他无人应答玩家。
			var opportunity_repair_actor_ids: Array = opportunity_pending_actor_ids.duplicate()
			for opportunity_chooser_id_variant: Variant in opportunity_repair_actor_ids:
				# 当前待修复玩家稳定ID；可应答人类保持等待，只有AI、托管或无人认领座位进入代选。
				var opportunity_chooser_id: int = int(opportunity_chooser_id_variant)
				if opportunity_chooser_id >= 0 and not _is_answerable_human_actor(opportunity_chooser_id):
					if opportunity_system.choose_for_managed_player(opportunity_chooser_id):
						actions.append("opportunity_forced_choice:%d" % opportunity_chooser_id)
	# 软修复：阿哈时刻推进兜底；只在已经完成某个欢愉技、仅等待嵌套结算屏障时轻推，避免越过仍在等待响应的技能。
	if ahha_moment_system != null and ahha_moment_system.is_waiting_for_barrier() and event_scheduler != null and event_scheduler.get_pending_choice_requests().is_empty() and not has_pending_card_choice():
		ahha_moment_system.continue_after_barrier()
		actions.append("nudge_ahha_moment_resolution")
	if repair_kind == "hard":
		# 第二级硬修复：释放不可能再被解决的孤儿暂停令牌。
		var released_tokens: Array[String] = _release_orphan_runtime_pause_tokens()
		if not released_tokens.is_empty():
			actions.append("released_orphan_tokens:%s" % ",".join(released_tokens))
		# 硬修复：无人认领的存活座位（既非AI又不属于任何真人视角）转入标准托管，由基础AI接管其全部待办。
		for orphan_actor_id: int in _collect_orphan_pending_actor_ids():
			_set_player_auto_management(orphan_actor_id, true, false)
			actions.append("auto_managed_orphan_seat:%d" % orphan_actor_id)
		# 硬修复：关闭死亡应答者遗留的待办请求，父流程在令牌释放后继续收尾。
		var closed_requests: Array[String] = _close_unanswerable_choice_requests()
		if not closed_requests.is_empty():
			actions.append("closed_dead_requests:%s" % ",".join(closed_requests))
		# 硬修复：同一AI兼容请求经历上一轮硬修复仍未解决时，中断该请求并恢复父流程（与AI重试耗尽同一保护出口）。
		if not _pending_card_choice.is_empty():
			var stuck_choice_request_id: int = int(_pending_card_choice.get("request_id", -1))
			var stuck_chooser_id: int = int(_pending_card_choice.get("chooser_id", -1))
			if not _is_answerable_human_actor(stuck_chooser_id):
				if _stall_repair_last_stuck_request_id == stuck_choice_request_id:
					_abort_unresolvable_ai_choice(stuck_choice_request_id, "stall_watchdog_forced_abort")
					actions.append("aborted_stuck_choice:%d" % stuck_choice_request_id)
					_stall_repair_last_stuck_request_id = -1
				else:
					_stall_repair_last_stuck_request_id = stuck_choice_request_id
		else:
			_stall_repair_last_stuck_request_id = -1
	# 统一收尾：重进结算管线并排空事件树，再补齐AI进度；全部入口自带安全防重与状态校验。
	resume_settlement_pipeline()
	_ensure_ai_progress_after_resolution()
	_emit_state()
	# 修复后进度指纹；与修复前不同说明对局确实被推动，此时才向玩家发出自动修复提醒。
	var fingerprint_after: String = _compose_stall_fingerprint()
	var effective: bool = fingerprint_after != fingerprint_before
	# 本次修复报告；看门狗与测试读取动作列表和效果标记，界面据信号展示提醒。
	var repair_report: Dictionary = {"kind": repair_kind, "actions": actions, "effective": effective, "phase": state.current_phase}
	if effective:
		add_log("【自动修复】检测到对局停滞，已自动修复并恢复流程。")
		self_repair_performed.emit(repair_report.duplicate(true))
	return repair_report


## 释放不可能再被任何代码解决的孤儿暂停令牌；返回“通道#令牌ID”列表供修复报告记录。
## 判定规则按通道独立：gameplay与conquest_replacement对照各自的权威状态标志，choice对照待办请求，其余对照所属事件是否已终结。
func _release_orphan_runtime_pause_tokens() -> Array[String]:
	# 已释放令牌描述列表；空列表表示当前所有令牌都仍有合法的解决路径。
	var released_tokens: Array[String] = []
	if event_scheduler == null:
		return released_tokens
	# 当前待办请求ID集合；choice通道令牌与请求一一对应，请求消失后令牌永远无法被解决。
	var pending_request_ids: Dictionary = {}
	for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
		pending_request_ids[int(request_data.get("request_id", -1))] = true
	for pause_token: Dictionary in event_scheduler.pause_registry.get_active_tokens():
		# 当前令牌稳定字段；快照为深拷贝，读取不会影响注册表。
		var token_id: int = int(pause_token.get("token_id", -1))
		var token_channel: String = str(pause_token.get("channel", ""))
		var owner_event_id: int = int(pause_token.get("owner_event_id", -1))
		# 当前令牌是否已确认为孤儿；默认保守不释放。
		var orphaned: bool = false
		if token_channel == "gameplay":
			# 对局级暂停服务已恢复但事件树令牌残留；同步清空成员字段防止后续误用旧令牌ID。
			orphaned = not is_gameplay_paused()
			if orphaned and token_id == _gameplay_event_pause_token:
				_gameplay_event_pause_token = -1
		elif token_channel == "conquest_replacement":
			# 换将过渡标志已复位但专用令牌残留；同步清空成员字段保持释放路径幂等。
			orphaned = not _conquest_replacement_transition_active
			if orphaned and token_id == _conquest_replacement_settlement_pause_token:
				_conquest_replacement_settlement_pause_token = -1
		elif token_channel == "choice":
			# 选择令牌的原因固定为 choice_request:请求ID；对应请求已经消失时该令牌不可能再被解决。
			var token_reason: String = str(pause_token.get("reason", ""))
			if token_reason.begins_with("choice_request:"):
				orphaned = not pending_request_ids.has(int(token_reason.get_slice(":", 1)))
		elif owner_event_id >= 0:
			# 未来新增通道兜底：所属事件缺失或已终结时，没有任何流程还会解决该令牌。
			var owner_event_snapshot: Dictionary = event_scheduler.get_event_snapshot(owner_event_id)
			orphaned = owner_event_snapshot.is_empty() or bool(owner_event_snapshot.get("finalized", false))
		if orphaned:
			event_scheduler.resume(token_id, "stall_watchdog_orphan_release")
			released_tokens.append("%s#%d" % [token_channel, token_id])
	return released_tokens


## 关闭应答者已死亡、永远等不到回应的待办请求；返回“类型#请求ID”列表供修复报告记录。
## 同时无懈窗口通过标准放弃动作关闭以保持轮次簿记一致，其余请求使用统一中断保护出口。
func _close_unanswerable_choice_requests() -> Array[String]:
	# 已关闭请求描述列表；空列表表示所有待办请求的应答者都仍然存活。
	var closed_requests: Array[String] = []
	if state == null or event_scheduler == null:
		return closed_requests
	# 同时无懈窗口快照键列表；提交放弃动作会修改原字典，必须先复制键再逐个复核。
	var negation_request_ids: Array = _pending_negation_choices.keys().duplicate()
	for negation_request_id_variant: Variant in negation_request_ids:
		var negation_request_id: int = int(negation_request_id_variant)
		if not _pending_negation_choices.has(negation_request_id):
			continue
		# 当前无懈窗口数据与应答者；存活应答者的窗口保持等待，不做任何干预。
		var negation_choice_data: Dictionary = _pending_negation_choices.get(negation_request_id, {}) as Dictionary
		var negation_chooser_id: int = int(negation_choice_data.get("chooser_id", -1))
		var negation_chooser: PlayerState = state.get_player(negation_chooser_id)
		if negation_chooser != null and negation_chooser.alive:
			continue
		# 死亡应答者的标准放弃动作；走正式提交入口保证公共展示、轮次收尾与事件令牌全部一致。
		var decline_action: PlayerAction = PlayerAction.new("choose_cards", negation_chooser_id)
		decline_action.payload = {"request_id": negation_request_id, "event_id": int(negation_choice_data.get("runtime_event_id", -1)), "selected_card_uids": []}
		if _submit_simultaneous_negation_choice(decline_action):
			closed_requests.append("negation#%d" % negation_request_id)
	# 兼容普通选择请求；应答者死亡时复用AI不可恢复请求的统一中断保护出口恢复父流程。
	if not _pending_card_choice.is_empty():
		var pending_chooser_id: int = int(_pending_card_choice.get("chooser_id", -1))
		var pending_chooser: PlayerState = state.get_player(pending_chooser_id)
		if pending_chooser == null or not pending_chooser.alive:
			# 当前兼容请求ID；中断入口会释放选择令牌、恢复阶段并重新排空结算管线。
			var pending_request_id: int = int(_pending_card_choice.get("request_id", -1))
			_abort_unresolvable_ai_choice(pending_request_id, "stall_watchdog_dead_chooser")
			closed_requests.append("card_choice#%d" % pending_request_id)
	# 运行时原生请求；死亡应答者的剩余请求直接中断，父事件在选择令牌释放后继续收尾。
	for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
		# 当前请求应答者；无效ID或存活应答者都跳过，只处理确认无法作答的死亡角色。
		var request_actor_id: int = int(request_data.get("actor_id", -1))
		if request_actor_id < 0:
			continue
		var request_actor: PlayerState = state.get_player(request_actor_id)
		if request_actor != null and request_actor.alive:
			continue
		var runtime_request_id: int = int(request_data.get("request_id", -1))
		if event_scheduler.abort_choice(runtime_request_id, "stall_watchdog_dead_actor"):
			closed_requests.append("runtime#%d" % runtime_request_id)
	return closed_requests


## 收集当前全部待办请求中“存活但无人能作答且未由AI控制”的座位ID；供硬修复统一转入标准托管。
## 覆盖运行时原生请求、兼容普通选择、同时无懈窗口与当前回合的chooseToUse归属，去重后按稳定顺序返回。
func _collect_orphan_pending_actor_ids() -> Array[int]:
	# 孤儿座位结果；键去重，值固定true，最终导出为有序数组。
	var orphan_actor_ids: Dictionary = {}
	if state == null or event_scheduler == null:
		return []
	# 候选应答者集合；运行时原生请求已经覆盖兼容层请求，但两边独立收集并补充机缘并行待办可抵御一致性缺口。
	var candidate_actor_ids: Array[int] = []
	for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
		candidate_actor_ids.append(int(request_data.get("actor_id", -1)))
	if not _pending_card_choice.is_empty():
		candidate_actor_ids.append(int(_pending_card_choice.get("chooser_id", -1)))
	for negation_choice_variant: Variant in _pending_negation_choices.values():
		candidate_actor_ids.append(int((negation_choice_variant as Dictionary).get("chooser_id", -1)))
	if opportunity_system != null and opportunity_system.is_active() and str(state.opportunity_state.get("stage", "")) == "choosing":
		for opportunity_actor_id_variant: Variant in state.opportunity_state.get("pending_chooser_ids", []) as Array:
			candidate_actor_ids.append(int(opportunity_actor_id_variant))
	for candidate_actor_id: int in candidate_actor_ids:
		if candidate_actor_id < 0 or orphan_actor_ids.has(candidate_actor_id):
			continue
		if ai_coordinator != null and ai_coordinator.is_ai_controlled(candidate_actor_id):
			continue
		if _is_answerable_human_actor(candidate_actor_id):
			continue
		# 当前候选状态；死亡座位由死亡请求关闭路径处理，托管转入只针对存活的无人认领座位。
		var candidate_actor: PlayerState = state.get_player(candidate_actor_id)
		if candidate_actor == null or not candidate_actor.alive or candidate_actor.auto_managed:
			continue
		orphan_actor_ids[candidate_actor_id] = true
	# 有序导出；排序保证同一停滞在不同运行中产生相同的修复动作顺序。
	var result: Array[int] = []
	for orphan_actor_id_variant: Variant in orphan_actor_ids.keys():
		result.append(int(orphan_actor_id_variant))
	result.sort()
	return result


## 为仍在等待的同时无懈窗口逐个重启AI延时响应任务；返回实际重启数量。
## 统一AI进度入口对无懈非空直接返回（各窗口设计上自带计时器），因此控全切换、托管恢复与停滞修复必须使用本入口补排。
func _redrive_pending_negation_ai_tasks() -> int:
	# 已重启任务数量；0表示当前没有属于AI的无懈窗口需要补排。
	var restarted_count: int = 0
	for negation_request_id_variant: Variant in _pending_negation_choices.keys():
		# 当前无懈请求数据；轮次ID从共享上下文读取，旧轮任务在新一轮开始后自动失效。
		var negation_request_id: int = int(negation_request_id_variant)
		var negation_choice_data: Dictionary = _pending_negation_choices.get(negation_request_id, {}) as Dictionary
		var negation_chooser_id: int = int(negation_choice_data.get("chooser_id", -1))
		if ai_coordinator != null and ai_coordinator.is_ai_controlled(negation_chooser_id):
			_run_simultaneous_negation_ai_after_delay(negation_request_id, negation_chooser_id, int((negation_choice_data.get("context", {}) as Dictionary).get("negation_round_id", -1)))
			restarted_count += 1
	return restarted_count


## 返回开局请求的前置校验错误；空字符串表示可以安全进入会替换旧局的初始化阶段。
## mode_id 空时读取 GameSettings.next_match_mode；人数与模式组合不支持时返回明确中文原因。
func get_match_start_validation_error(player_count: int = -1, mode_id: String = "") -> String:
	# 实际玩家人数；未指定时使用检查器默认值。
	var actual_player_count: int = default_player_count if player_count < 0 else player_count
	# 规范化模式；空字符串回退全局下一局设置，再由身份规则兜底为 identity。
	var actual_mode: String = _resolve_match_mode(mode_id)
	if not identity_rules.supports_player_count(actual_mode, actual_player_count):
		if actual_mode == IdentityRules.MODE_DOUDIZHU:
			return "斗地主仅支持3人或5人。"
		if actual_mode == IdentityRules.MODE_TEAM2V2:
			return "2v2仅支持4名玩家。"
		if actual_mode == IdentityRules.MODE_WHEEL_DUEL:
			return "1v1车轮战仅支持2名玩家。"
		if actual_mode == IdentityRules.MODE_CONQUEST:
			return "过关斩将角色总数只支持2、4、6或8（1至4名玩家与等量敌人）。"
		return "标准身份局仅支持2至10名玩家。"
	if actual_mode == IdentityRules.MODE_CONQUEST and network_gateway != null and network_gateway.mode != NetworkGateway.Mode.OFFLINE:
		# 联机过关斩将只允许房主创建，且必须为2至4名玩家（角色总数4、6、8）；客户端与远程模式不能创建权威对局。
		if not network_gateway.is_lan_host():
			return "过关斩将联机对局只能由局域网房主创建。"
		if actual_player_count < 4:
			return "局域网过关斩将需要2至4名玩家（角色总数4、6或8）。"
	if not GameDatabase.validation_errors.is_empty():
		return "数据配置校验失败：%s" % "；".join(GameDatabase.validation_errors)
	if actual_mode == IdentityRules.MODE_WHEEL_DUEL:
		var wheel_candidate_total: int = GameSettings.wheel_duel_face_up_candidate_count + GameSettings.wheel_duel_face_down_candidate_count
		if wheel_candidate_total < WheelDuelSelectionService.DRAFTED_CHARACTER_COUNT_PER_PLAYER * 2:
			return "1v1车轮战的明置与暗置候选合计至少需要10名。"
		if GameDatabase.get_selectable_character_ids().size() < wheel_candidate_total:
			return "当前武将数量不足，无法生成%d名不重复的车轮战候选武将。" % wheel_candidate_total
	return ""


## 规范化对局模式；空值优先读取 GameSettings.next_match_mode，再回退到身份局。
func _resolve_match_mode(mode_id: String = "") -> String:
	# 调用方显式模式优先；否则使用全局下一局设置。
	var raw_mode: String = mode_id
	if raw_mode.is_empty() and GameSettings != null:
		raw_mode = str(GameSettings.next_match_mode)
	return identity_rules.normalize_mode(raw_mode)


## 解析本局唯一随机种子；显式非零值保持可复现，自动值混合跨进程系统时间、进程内单调时间、进程号与重开序号。
func _resolve_match_seed(requested_seed: int) -> int:
	if requested_seed != 0:
		return requested_seed
	_automatic_match_seed_serial += 1
	# 跨进程系统时间分量；退出游戏再进入时不依赖相近的菜单操作耗时，微秒精度用于区分快速连续启动。
	var wall_clock_microseconds: int = int(Time.get_unix_time_from_system() * float(AUTOMATIC_MATCH_SEED_MICROSECONDS_PER_SECOND))
	# 当前进程单调时间分量；同一进程内快速重开时提供比毫秒更细的启动间隔差异。
	var monotonic_microseconds: int = Time.get_ticks_usec()
	# 当前进程分量；极短时间内关闭并重启时进一步区分不同游戏进程。
	var process_component: int = OS.get_process_id() * AUTOMATIC_MATCH_SEED_PROCESS_STEP
	# 连续重开序号分量；同一微秒内的多个入口仍不会得到相同自动种子。
	var serial_component: int = _automatic_match_seed_serial * AUTOMATIC_MATCH_SEED_SERIAL_STEP
	# 混合后的自动种子；异或避免高位系统时间掩盖较小分量，同时保持完整64位结果供回放记录。
	var resolved_seed: int = wall_clock_microseconds ^ monotonic_microseconds ^ process_component ^ serial_component
	return resolved_seed if resolved_seed != 0 else serial_component


## 创建并开始一局；seed 为0时使用系统随机种子，mode_id 空时读取 GameSettings.next_match_mode。
func start_match(player_count: int = -1, seed: int = 0, mode_id: String = "") -> bool:
	# 实际玩家人数；未指定时使用检查器默认值。
	var actual_player_count: int = default_player_count if player_count < 0 else player_count
	# 本次是否使用自动种子；只允许自动开局应用跨局防重复约束，显式种子必须保持完全可复现。
	var uses_automatic_match_seed: bool = seed == 0
	# 本局模式；在破坏旧状态前完成校验，失败时调用方可保留原局。
	var actual_mode: String = _resolve_match_mode(mode_id)
	# 开局前置校验错误；任何错误都在破坏旧对局状态和表现之前同步拒绝。
	var validation_error: String = get_match_start_validation_error(actual_player_count, actual_mode)
	if not validation_error.is_empty():
		action_rejected.emit(validation_error)
		return false
	_teardown_previous_match_runtime()
	# 上一局的断线座位预约到此失效；重开新局时掉线玩家已被移出真人映射，其座位由 AI 正常补位。
	_invalidate_lan_seat_reservations()

	# 本局实际随机种子；全部无显式种子的入口共用解析函数，保证菜单返回、局内重开与完整重启都重新随机。
	var resolved_match_seed: int = _resolve_match_seed(seed)
	# 无论种子由调用方显式指定还是自动生成，都必须在本局开始前写入唯一随机源；显式种子供回放与测试复现，自动种子供菜单重开与退出重进获得新牌局。
	_rng.seed = resolved_match_seed
	# 局域网房主的本地玩家 ID 已由大厅位置顺序映射确定；联机过关斩将的真人只占偶数玩家座位，因此优先采用网关映射。
	# 离线过关斩将固定本地玩家为一号位，其他离线对局继续使用原有随机座次逻辑。
	var lan_local_player_id: int = network_gateway.get_local_lan_player_id() if network_gateway != null and network_gateway.is_lan_host() else -1
	if lan_local_player_id >= 0:
		local_human_player_id = lan_local_player_id
	elif actual_mode == IdentityRules.MODE_CONQUEST and local_human_player_id >= 0:
		local_human_player_id = 0
	else:
		_assign_local_human_player_seat(actual_player_count)
	CardInstance._next_uid = 1
	state = GameState.new()
	state.match_id = "%d-%d" % [Time.get_unix_time_from_system(), _rng.randi()]
	# 本局锁定的模式；菜单之后的模式切换只写入 GameSettings，不改进行中的规则。
	state.match_mode = actual_mode
	ai_coordinator.reset_identity_observations()
	state.random_seed = resolved_match_seed
	state.deck_id = default_deck_id
	# 本局锁定的房主权威开局选项；菜单之后的修改只作用于下一局，不会改变进行中的选将或手气卡阶段。
	_all_character_selection_enabled = GameSettings.custom_character_assignment_enabled and actual_mode != IdentityRules.MODE_WHEEL_DUEL
	_custom_character_assignment_enabled = _all_character_selection_enabled and actual_mode != IdentityRules.MODE_CONQUEST
	_customize_ai_characters_enabled = GameSettings.customize_ai_characters_enabled and actual_mode != IdentityRules.MODE_CONQUEST
	_mulligan_limit = GameSettings.mulligan_limit
	_ai_uses_mulligan_enabled = GameSettings.ai_uses_mulligan_enabled
	_control_all_characters_enabled = network_gateway != null and network_gateway.mode == NetworkGateway.Mode.OFFLINE and local_human_player_id >= 0 and GameSettings.control_all_characters_enabled
	_primary_offline_human_player_id = local_human_player_id
	_offline_manually_controlled_player_id = -1
	_character_replacement_count = GameSettings.get_character_replacement_count_for_mode(actual_mode)
	_character_candidate_count = GameSettings.get_character_candidate_count_for_mode(actual_mode)
	_wheel_duel_face_up_candidate_count = GameSettings.wheel_duel_face_up_candidate_count
	_wheel_duel_face_down_candidate_count = GameSettings.wheel_duel_face_down_candidate_count
	# 检查器兼容字段；运行时同步为房主设置锁定值，旧诊断与外部只读代码仍能看到本局实际候选数量。
	character_candidate_count = _character_candidate_count
	state.match_options = {
		"custom_character_assignment_enabled":_custom_character_assignment_enabled,
		"all_character_selection_enabled":_all_character_selection_enabled,
		"customize_ai_characters_enabled":_customize_ai_characters_enabled,
		"mulligan_limit":_mulligan_limit,
		"ai_uses_mulligan_enabled":_ai_uses_mulligan_enabled,
		"control_all_characters_enabled":_control_all_characters_enabled,
		"character_replacement_count":_character_replacement_count,
		"character_candidate_count":_character_candidate_count,
		"wheel_duel_face_up_candidate_count":_wheel_duel_face_up_candidate_count,
		"wheel_duel_face_down_candidate_count":_wheel_duel_face_down_candidate_count,
		"conquest_difficulty":GameSettings.conquest_difficulty,
		"conquest_opportunity_choice_mode":GameSettings.conquest_opportunity_choice_mode,
		"opportunity_system_enabled":opportunity_enabled_mode_ids.has(actual_mode) or opportunity_manual_mode_ids.has(actual_mode),
		"lan_custom_identity_enabled":network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_custom_identity_enabled(),
		"lan_fixed_seat_enabled":network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_fixed_seat_enabled(),
	}
	if opportunity_system != null:
		opportunity_system.configure(self, state, _rng, opportunity_enabled_mode_ids.has(actual_mode) or opportunity_manual_mode_ids.has(actual_mode), opportunity_enabled_mode_ids.has(actual_mode))
	if ahha_moment_system != null:
		# 阿哈时刻对所有模式生效；场上没有可执行欢愉技时组件在判定第一行即返回，因此不会改变任何现有对局的流程。
		ahha_moment_system.configure(self, state, _rng, true)
	_rebuild_match_rule_services_and_root_event()
	character_selection = CharacterSelectionService.new()
	wheel_duel_selection = WheelDuelSelectionService.new() if actual_mode == IdentityRules.MODE_WHEEL_DUEL else null
	conquest_mode = ConquestModeService.new() if actual_mode == IdentityRules.MODE_CONQUEST else null
	ai_character_adjustment = AICharacterAdjustmentService.new()
	starting_hand_mulligan = StartingHandMulliganService.new()
	_reset_per_match_progress_state()

	_create_players(actual_player_count, uses_automatic_match_seed)
	# 最终离线主操作者；自动斗地主防重复可能在创建玩家前改选本地座次，控制归属必须以调整后的稳定ID为准。
	_primary_offline_human_player_id = local_human_player_id
	if conquest_mode != null and state.players.size() >= 2 and state.players.size() % 2 == 0:
		# 过关斩将按“玩家1、敌人1、玩家2、敌人2……”交替建位：偶数座次索引为红方玩家，奇数为蓝方敌人。
		# 关卡状态在选将前建立，后续初始机缘与换将均复用稳定ID；单人局退化为一号位玩家对二号位敌人。
		# 补充：当前关卡状态还会锁定本局难度，并通过稳定机缘ID为每名玩家授予对应开局增益。
		var conquest_player_ids: Array[int] = []
		var conquest_enemy_ids: Array[int] = []
		for conquest_seat_index: int in range(state.players.size()):
			if conquest_seat_index % 2 == 0:
				conquest_player_ids.append(state.players[conquest_seat_index].player_id)
			else:
				conquest_enemy_ids.append(state.players[conquest_seat_index].player_id)
		conquest_mode.configure_participants(state, _rng, conquest_player_ids, conquest_enemy_ids, int(state.match_options.get("conquest_difficulty", GameSettings.DEFAULT_CONQUEST_DIFFICULTY)))
	_create_and_shuffle_deck()
	_record_runtime_event("identity.start", "mode", {"player_count":actual_player_count, "seed":resolved_match_seed, "mode":state.match_mode})
	state.current_phase = "wheel_duel_selection" if actual_mode == IdentityRules.MODE_WHEEL_DUEL else "character_selection"
	# 可用武将 ID；服务只持有字符串副本，不接触全局配置的可修改引用。
	var available_character_ids: Array[String] = GameDatabase.get_selectable_character_ids()
	# 领袖技武将 ID；依据技能元数据自动识别，选将服务只接收纯字符串数组并保持与数据库解耦。
	var leader_skill_character_ids: Array[String] = _get_leader_skill_character_ids(available_character_ids)
	# 选将初始化错误；空字符串表示领袖候选已生成。
	var selection_error: String = wheel_duel_selection.begin(state.players, available_character_ids, _wheel_duel_face_up_candidate_count, _wheel_duel_face_down_candidate_count, _rng) if wheel_duel_selection != null else character_selection.begin(state.players, available_character_ids, _character_candidate_count, _rng, _custom_character_assignment_enabled, _character_replacement_count, leader_skill_character_ids, str(state.match_mode), _all_character_selection_enabled)
	if not selection_error.is_empty():
		_discard_failed_match_start()
		action_rejected.emit(selection_error)
		return false
	# 选将日志；身份局保留领袖优先亮将文案，斗地主改为全员同时选将。
	if str(state.match_mode) == IdentityRules.MODE_WHEEL_DUEL:
		add_log("选将开始：后手先选，按122221顺序从%d名明置与%d名暗置候选中抓将。" % [_wheel_duel_face_up_candidate_count, _wheel_duel_face_down_candidate_count])
	elif str(state.match_mode) == IdentityRules.MODE_DOUDIZHU:
		add_log("选将开始：斗地主全员同时从%d张随机候选中选择武将（身份明置，不公开武将）。" % mini(_character_candidate_count, available_character_ids.size()))
	elif str(state.match_mode) == IdentityRules.MODE_TEAM2V2:
		add_log("选将开始：2v2全员同时从%d张随机候选中选择武将（蓝红身份明置，座次一/四同队、二/三同队）。" % mini(_character_candidate_count, available_character_ids.size()))
	elif str(state.match_mode) == IdentityRules.MODE_CONQUEST:
		add_log("选将开始：过关斩将中玩家先从%d张随机候选中选择武将，确认后敌方AI再随机选将。" % mini(_character_candidate_count, available_character_ids.size()))
	else:
		var first_player_title: String = _identity_text(identity_rules.get_first_player_identity(state.match_mode))
		add_log("选将开始：%s先从%d张普通随机候选及%d张领袖技固定候选中选择并亮出。" % [first_player_title, mini(_character_candidate_count, maxi(available_character_ids.size() - leader_skill_character_ids.size(), 0)), leader_skill_character_ids.size()])
	# 同一局域网房间内的重开必须重新广播开局绑定：客户端上一局的表现幂等窗口与实体 UID 认领记录仍然保留，
	# 而本局的牌面表现序号与卡牌实体 UID 都从1重新开始，只有客户端同步重置表现状态才能继续播放使用飞牌与目标指示线。
	# 首次开局的 `_lan_match_active` 仍为 false，因此本分支只覆盖“房主在同一房间内再来一局”的重开路径。
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.rebroadcast_prepared_lan_match()
	_emit_state()
	if wheel_duel_selection != null:
		_drive_ai_wheel_duel_selection()
	else:
		_drive_ai_character_selection()
	return true


## 释放上一局全部运行时残留；普通开局与存档恢复开局共用本入口，保证两条路径的清理清单不彼此漂移。
## 包含流程计时器、机缘组件、过关斩将服务、技能与卡牌运行时实例、额外回合与阶段队列、规则续接和判定请求。
func _teardown_previous_match_runtime() -> void:
	if game_flow_transition_coordinator != null:
		game_flow_transition_coordinator.cancel_pending("match_runtime_teardown")
	if game_flow_pacer != null:
		game_flow_pacer.cancel_all()
	_cancel_conquest_replacement_opportunity_preview()
	if opportunity_system != null:
		opportunity_system.shutdown()
	if ahha_moment_system != null:
		ahha_moment_system.shutdown()
	if conquest_mode != null:
		conquest_mode.reset()
	_uninstall_all_character_skills()
	_uninstall_all_card_runtimes()
	_conquest_temporary_exit_requested = false
	_extra_turn_queue.clear()
	_extra_turn_resume_player_ids.clear()
	_pending_turn_start_context.clear()
	_current_turn_is_extra = false
	_extra_play_phase_counts.clear()
	_extra_play_phase_returns_to_finish.clear()
	_extra_play_phase_return_points.clear()
	_active_extra_play_phase_context.clear()
	_main_phase_play_conversions.clear()
	_active_converted_play_phase_context.clear()
	_active_extra_discard_phase.clear()
	_active_independent_play_phase.clear()
	_deferred_skill_settlements.clear()
	_rule_continuations.reset()
	_reset_settlement_runtime_guard()
	_clear_pending_judgment_request()
	_cards_used_this_turn_by_player.clear()


## 以当前 state 重建全部规则服务并创建新的长期根事件；普通开局与存档恢复开局共用本入口。
## 调用前 state 必须已经创建并写入 match_id、match_mode 与 deck_id，根事件元数据直接引用这些字段。
func _rebuild_match_rule_services_and_root_event() -> void:
	card_rules = CardRuleService.new(state, self)
	player_mark_service = PlayerMarkService.new(state)
	if reincarnation_skill_service == null:
		reincarnation_skill_service = ReincarnationSkillService.new()
	reincarnation_skill_service.configure(self)
	if player_zone_abolition_service == null:
		player_zone_abolition_service = PlayerZoneAbolitionService.new()
	player_zone_abolition_service.configure(self)
	effect_resolver = CardEffectResolver.new(self, state)
	card_movement = CardMovementService.new(state)
	_bind_card_movement_service()
	modifier_pipeline = RuleModifierPipeline.new()
	rule_query = RuleQuery.new(state, card_rules, modifier_pipeline)
	trigger_manager = TriggerManager.new()
	_configure_rule_dispatch_guards()
	if timing_service == null:
		timing_service = RuleTimingService.new(event_bus, trigger_manager, state)
	else:
		timing_service.configure(event_bus, trigger_manager, state)
	timing_service.set_trigger_pause_condition(Callable(self, "_should_pause_rule_timing_dispatch"))
	skill_instances_by_player.clear()
	card_runtime_instances.clear()
	event_scheduler.reset()
	_gameplay_event_pause_token = -1
	_conquest_replacement_settlement_pause_token = -1
	# 根事件只保存规则启动元数据；后续身份、阶段和卡牌事件通过 parent_id 关联到该入口。
	var root_event: GameEvent = event_scheduler.create_event("RootGameEvent", "root", [], {"rules_snapshot":"noname-v1.10.16", "mode":state.match_mode, "match_id":state.match_id, "deck_id":state.deck_id})
	_runtime_root_event_id = root_event.event_id
	event_scheduler.begin_root(_runtime_root_event_id, true)
	if is_gameplay_paused():
		_gameplay_event_pause_token = event_scheduler.pause_registry.acquire("gameplay", -1, "gameplay_pause_interface")
	state.current_event_id = _runtime_root_event_id
	state.event_history = event_scheduler.get_event_history_reference_copy()


## 重置所有按局清零的进度、AI 调度与请求字段；普通开局与存档恢复开局共用本入口。
## 该函数不接触 state 的玩家或牌区数据，只保证控制器的每局私有游标从干净状态开始。
func _reset_per_match_progress_state() -> void:
	_starting_hand_count = 4
	_ai_drive_token += 1
	_scheduled_ai_drive_token = -1
	_scheduled_ai_choice_request_id = -1
	_ai_choice_submit_failures.clear()
	_ai_actions_this_turn = 0
	_pending_card_choice.clear()
	_pending_negation_choices.clear()
	_deferred_skill_settlements.clear()
	_rule_continuations.reset()
	_pending_conquest_boundary_player_id = -1
	_reset_settlement_runtime_guard()
	_negation_round_sequence = 0
	_resolved_card_choice_uids.clear()
	_resolved_equipment_material_uids.clear()
	_resolved_response_skill_id = ""
	_negation_resume_results.clear()
	_active_card_resolutions.clear()
	_card_use_contexts.clear()
	_hand_view_as_turn_expiries.clear()
	_conquest_replacement_transition_active = false
	_started_phase_lifecycles.clear()
	_queued_equipment_triggers.clear()
	_current_turn_event_id = -1
	_play_choice_request_id = -1
	_play_choice_event_id = -1
	_play_choice_actor_id = -1
	_play_choice_match_id = ""
	_card_presentation_sequence = 0
	_draw_presentation_batch_sequence = 0
	_active_draw_presentation_batch.clear()
	_judgment_flow_token += 1
	_judgment_flow_in_progress = false
	_judgment_resume_needs_result_pause = false
	_clear_pending_judgment_request()
	ai_coordinator._policies.clear()
	_ai_submission_depth_by_player.clear()


## 丢弃已进入初始化阶段但未能建立选将流程的半成品对局；失败后控制器恢复与首次进入主菜单相同的空状态。
func _discard_failed_match_start() -> void:
	if game_flow_transition_coordinator != null:
		game_flow_transition_coordinator.cancel_pending("failed_match_start")
	if game_flow_pacer != null:
		game_flow_pacer.cancel_all()
	_cancel_conquest_replacement_opportunity_preview()
	# 临时退出预约随对局一同丢弃；主动放弃对局后旧预约不得影响下一局的回合边界。
	_conquest_temporary_exit_requested = false
	if opportunity_system != null:
		opportunity_system.shutdown()
	if ahha_moment_system != null:
		ahha_moment_system.shutdown()
	_uninstall_all_character_skills()
	_uninstall_all_card_runtimes()
	if event_scheduler != null:
		event_scheduler.reset()
	ai_coordinator._policies.clear()
	_ai_submission_depth_by_player.clear()
	skill_instances_by_player.clear()
	card_runtime_instances.clear()
	character_selection = null
	wheel_duel_selection = null
	if conquest_mode != null:
		conquest_mode.reset()
	conquest_mode = null
	ai_character_adjustment = null
	starting_hand_mulligan = null
	card_rules = null
	player_mark_service = null
	effect_resolver = null
	card_movement = null
	modifier_pipeline = null
	rule_query = null
	trigger_manager = null
	timing_service = null
	_runtime_root_event_id = -1
	_current_turn_event_id = -1
	_gameplay_event_pause_token = -1
	_ai_drive_token += 1
	_scheduled_ai_drive_token = -1
	_scheduled_ai_choice_request_id = -1
	_ai_choice_submit_failures.clear()
	_is_driving_character_selection = false
	_rule_continuations.reset()
	_reset_settlement_runtime_guard()
	_clear_pending_judgment_request()
	state = null


## 返回当前武将库中全部拥有领袖技的武将 ID；顺序继承数据库武将索引，供选将固定候选稳定排列。
func _get_leader_skill_character_ids(character_ids: Array[String]) -> Array[String]:
	# 领袖技武将结果；同一武将即使配置多个领袖技也只加入一次。
	var result: Array[String] = []
	for character_id: String in character_ids:
		# 当前武将定义；技能数组只保存稳定技能 ID，不实例化运行时技能对象。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		for skill_id_variant: Variant in character_definition.get("skills", []) as Array:
			# 当前技能元数据；leader_skill=true表示该武将需要进入领袖固定候选区。
			var skill_definition: Dictionary = GameDatabase.get_skill(str(skill_id_variant))
			if bool(skill_definition.get("leader_skill", false)):
				result.append(character_id)
				break
	return result


## 主动放弃当前对局并回到空闲入口；主菜单使用该接口退出进行中或已结束的本地权威状态。
## 该操作不结算胜负、不写入回放，也不改变跨局显示设置，仅释放本局运行时服务和延迟任务。
func abandon_match() -> void:
	if state == null:
		return
	_discard_failed_match_start()


## 为本局分配有效的本地人类座次；随机模式使用对局随机源，固定模式把检查器配置限制到实际人数范围。
func _assign_local_human_player_seat(player_count: int) -> void:
	if local_human_player_id < 0:
		return
	local_human_player_id = _rng.randi_range(0, player_count - 1) if randomize_local_human_seat else clampi(local_human_player_id, 0, player_count - 1)


## 提交一名玩家的选将结果；所有人类、AI与网络入口共用相同阶段和候选校验。
func select_character(player_id: int, character_id: String, seat_number: int = -1, identity: String = "") -> bool:
	if state == null or state.game_over or state.current_phase != "character_selection" or character_selection == null:
		return _reject("当前不在选将阶段。")
	# 本次提交前是否处于首任领袖阶段；服务可能在成功后立即进入自选阶段，因此必须提前保存。
	var was_initial_leader_selection: bool = character_selection.phase == CharacterSelectionService.PHASE_LEADER
	# 本次提交前是否处于最终自选阶段；该阶段每名玩家确认时立即写入当前预览座次身份，完成时不得再次重置武将。
	var was_custom_character_selection: bool = character_selection.phase == CharacterSelectionService.PHASE_CUSTOM
	# 斗地主同时选将阶段；提交前相位为 PHASE_OTHERS，完成后统一亮将，确认过程中仅投射自选座次身份。
	var was_doudizhu_simultaneous_selection: bool = character_selection.uses_simultaneous_selection() and character_selection.phase == CharacterSelectionService.PHASE_OTHERS
	# 本次提交是否只确认首任领袖的座次身份；该武将已在领袖阶段应用并公开，不能再次改写稳定武将ID。
	# 该分支只处理AI首任领袖延后占用剩余名额；真人首任领袖不会产生第二次提交。
	var confirms_retained_initial_leader_character: bool = character_selection.is_retaining_initial_leader_character(player_id)
	# 真人首任领袖一次性提交完整性；AI可以先公开武将并等待真人占用名额，真人不得退回会再次弹框的旧式分步协议。
	var requires_initial_human_assignment: bool = was_initial_leader_selection and character_selection.custom_assignment_enabled and not ai_coordinator.is_ai_controlled(player_id)
	if requires_initial_human_assignment and (seat_number < 1 or identity.is_empty()):
		return _reject("请选择武将、座次与身份后再确认。")
	# 选将服务返回的校验错误；空字符串表示选择已经记录并可能推进阶段。
	var selection_error: String = character_selection.select_character(player_id, character_id, seat_number, identity)
	if not selection_error.is_empty():
		# 自选模式可能因其他真人先确认同一座次或身份名额而冲突；立即重发最新可用按钮快照。
		_emit_state()
		return _reject(selection_error)
	state.action_sequence += 1
	# 权威确认座次；自选模式记录服务完成一号位/领袖联动后的最终值，普通模式保留无效默认值。
	var confirmed_seat_number: int = character_selection.get_selected_seat_number(player_id) if character_selection.custom_assignment_enabled else seat_number
	# 权威确认身份；回放历史不能保存联动前的请求值，否则一号位自动领袖会与最终状态不一致。
	var confirmed_identity: String = character_selection.get_selected_identity(player_id) if character_selection.custom_assignment_enabled else identity
	state.random_history.append({"kind":"character_selection", "player_id":player_id, "character_id":character_id, "seat_number":confirmed_seat_number, "identity":confirmed_identity, "candidates":character_selection.get_candidates(player_id)})
	if was_custom_character_selection:
		# 已确认自选先投射当前完整座次身份；随后只应用本次玩家的新武将，避免结算末尾再次覆盖已经显示的牌面。
		_apply_custom_assignment_preview()
		if not confirms_retained_initial_leader_character:
			# 当前确认玩家；预览重排后按稳定玩家ID重新查询，保证领袖体力加值按最终身份计算。
			var custom_selected_player: PlayerState = state.get_player(player_id)
			_apply_character(custom_selected_player, character_id, true)
		else:
			# 首任领袖最终身份可能改为非领袖；只按最终身份刷新基础体力，不重新写入或随机选择武将。
			_refresh_pre_game_character_stats(state.get_player(player_id))
	elif was_doudizhu_simultaneous_selection and character_selection.custom_assignment_enabled:
		# 斗地主自选：阶段完成前不逐人亮将（统一由 _finish_character_selection 亮出），但座次/身份需即时投射到牌桌。
		_apply_custom_assignment_preview()
	if was_initial_leader_selection:
		# 领袖选择立即写入并公开，其他玩家候选只会在此之后生成。
		var leader: PlayerState = state.get_player(player_id)
		_apply_character(leader, character_id, true)
		add_log("领袖%s亮出武将【%s】。" % [leader.display_name, GameDatabase.resolve_character_name(character_id)])
		if character_selection.custom_assignment_enabled:
			# 初次自选默认值已是有效的真实座次身份；进入界面前立即投射，避免一号位和领袖只停留在按钮高亮。
			_apply_custom_assignment_preview()
			# 首任领袖的武将与座次身份已经在同一次提交中落定；投射最终身份后重算体力，避免领袖加成沿用提交前身份。
			_refresh_pre_game_character_stats(state.get_player(player_id))
			add_log("首任领袖选将完成，其他未确认玩家开始自选武将、座次与身份。")
		else:
			add_log("其他玩家开始同时选将，每人随机展示%d张候选武将牌。" % character_selection.candidate_count)
	if character_selection.phase == CharacterSelectionService.PHASE_COMPLETE:
		_finish_character_selection()
	else:
		_emit_state()
		if not _is_driving_character_selection:
			_drive_ai_character_selection()
	return true


## 提交1v1车轮战的一次公共候选抓取；权威服务按当前批次、行动玩家与稳定槽ID重新校验。
func pick_wheel_duel_candidate(player_id: int, slot_id: int) -> bool:
	if state == null or state.game_over or state.current_phase != "wheel_duel_selection" or wheel_duel_selection == null:
		return _reject("当前不在1v1车轮战选将阶段。")
	var selection_error: String = wheel_duel_selection.pick_candidate(player_id, slot_id)
	if not selection_error.is_empty():
		_emit_state()
		return _reject(selection_error)
	state.action_sequence += 1
	state.random_history.append({"kind":"wheel_duel_pick", "player_id":player_id, "slot_id":slot_id})
	if wheel_duel_selection.phase == WheelDuelSelectionService.PHASE_LINEUP:
		add_log("双方已各取得5名武将，请各自选择3名并确认固定出场顺序。")
	_emit_state()
	_drive_ai_wheel_duel_selection()
	return true


## 提交1v1车轮战三名武将的固定出场顺序；顺序仅对本人和权威端可见，完成后不可再次修改。
func submit_wheel_duel_lineup(player_id: int, ordered_character_ids: Array[String]) -> bool:
	if state == null or state.game_over or state.current_phase != "wheel_duel_selection" or wheel_duel_selection == null:
		return _reject("当前不在1v1车轮战阵容确认阶段。")
	var selection_error: String = wheel_duel_selection.submit_lineup(player_id, ordered_character_ids)
	if not selection_error.is_empty():
		_emit_state()
		return _reject(selection_error)
	state.action_sequence += 1
	state.random_history.append({"kind":"wheel_duel_lineup", "player_id":player_id, "character_ids":ordered_character_ids.duplicate()})
	if wheel_duel_selection.phase == WheelDuelSelectionService.PHASE_COMPLETE:
		_finish_wheel_duel_selection()
	else:
		_emit_state()
		_drive_ai_wheel_duel_selection()
	return true


## 完成车轮战选将并只亮出双方首发武将；后续阵容继续保存在玩家私有状态中。
func _finish_wheel_duel_selection() -> void:
	if state == null or wheel_duel_selection == null:
		return
	for player: PlayerState in state.players:
		# 本人最终阵容；服务已经校验固定为3名且互不重复。
		var lineup: Array[String] = wheel_duel_selection.get_lineup(player.player_id)
		player.wheel_duel_lineup = lineup.duplicate()
		player.wheel_duel_lineup_index = 0
		player.wheel_duel_defeated_count = 0
		_apply_character(player, lineup[0], true)
	add_log("双方亮出初始武将，未出场武将及其顺序继续对对手保密。")
	_continue_game_start_after_character_adjustment()


## 驱动车轮战内置AI完成当前抓将或阵容确认；AI仍通过标准PlayerAction入口接受完整权威校验。
func _drive_ai_wheel_duel_selection() -> void:
	if is_gameplay_paused() or state == null or wheel_duel_selection == null or wheel_duel_selection.phase == WheelDuelSelectionService.PHASE_COMPLETE:
		return
	while wheel_duel_selection.phase == WheelDuelSelectionService.PHASE_DRAFT:
		var drafter_id: int = wheel_duel_selection.get_current_drafter_id()
		if not ai_coordinator.is_ai_controlled(drafter_id):
			break
		var selection_snapshot: Dictionary = wheel_duel_selection.to_dict(drafter_id)
		var pool_slots: Array = selection_snapshot.get("pool_slots", []) as Array
		if pool_slots.is_empty():
			break
		# 当前首个未被选择的公共槽；已选槽保留原位并带有相对归属，AI不得重复提交。
		var available_slot_id: int = -1
		for slot_variant: Variant in pool_slots:
			var slot: Dictionary = slot_variant as Dictionary
			if str(slot.get("selection_owner", "")).is_empty():
				available_slot_id = int(slot.get("slot_id", -1))
				break
		if available_slot_id < 0:
			break
		var pick_action: PlayerAction = PlayerAction.new("wheel_duel_pick", drafter_id)
		pick_action.payload = {"slot_id":available_slot_id}
		_submit_ai_action(pick_action)
		if state == null or state.current_phase != "wheel_duel_selection":
			return
	if wheel_duel_selection.phase != WheelDuelSelectionService.PHASE_LINEUP:
		return
	for player: PlayerState in state.players:
		if not ai_coordinator.is_ai_controlled(player.player_id) or wheel_duel_selection.has_submitted_lineup(player.player_id):
			continue
		var drafted: Array[String] = wheel_duel_selection.get_drafted_characters(player.player_id)
		var lineup_action: PlayerAction = PlayerAction.new("wheel_duel_submit_lineup", player.player_id)
		lineup_action.payload = {"character_ids":drafted.slice(0, WheelDuelSelectionService.LINEUP_CHARACTER_COUNT_PER_PLAYER)}
		_submit_ai_action(lineup_action)


## 使用一张换将卡替换本人当前选将框中的指定普通候选；规则服务负责次数、锁定候选与随机池校验。
func replace_character_candidate(player_id: int, character_id: String) -> bool:
	if state == null or state.game_over or state.current_phase != "character_selection" or character_selection == null:
		return _reject("当前不在选将阶段。")
	# 换将服务错误；失败不会消耗次数或改变候选，仍重发当前私有状态供界面恢复按钮。
	var replacement_error: String = character_selection.replace_candidate(player_id, character_id)
	if not replacement_error.is_empty():
		_emit_state()
		return _reject(replacement_error)
	state.action_sequence += 1
	state.random_history.append({"kind":"character_candidate_replacement", "player_id":player_id, "replaced_character_id":character_id, "candidates":character_selection.get_candidates(player_id), "remaining":character_selection.get_replacement_cards_remaining(player_id)})
	_emit_state()
	return true


## 预览自选模式中的座次与身份改动；玩家尚未确认武将时即时重排角色，但保留仍为领袖的首次公开武将。
func preview_custom_assignment(player_id: int, seat_number: int, identity: String) -> bool:
	if state == null or state.game_over or state.current_phase != "character_selection" or character_selection == null:
		return _reject("当前不在自选座次与身份阶段。")
	if ai_coordinator.is_ai_controlled(player_id):
		return _reject("AI 不会提交自选座次与身份预览。")
	# 服务校验结果；预览不会写入最终名额，但会与已确认结果及其他玩家主动预览保持互斥。
	var preview_error: String = character_selection.preview_custom_assignment(player_id, seat_number, identity)
	if not preview_error.is_empty():
		_emit_state()
		return _reject(preview_error)
	_apply_custom_assignment_preview()
	state.action_sequence += 1
	state.random_history.append({"kind":"custom_assignment_preview", "player_id":player_id, "seat_number":character_selection.get_preview_seat_number(player_id), "identity":character_selection.get_preview_identity(player_id)})
	_emit_state()
	return true


## 判断换将过渡中的操作是否属于当前机缘流程；请求类型、选择者、请求ID和上下文必须全部匹配。
func _is_conquest_replacement_opportunity_action_allowed(action: PlayerAction) -> bool:
	if action == null:
		return false
	if action.action_type == "choose_opportunity":
		return true
	if action.action_type not in ["choose_cards", "choice_response"]:
		return false
	if _pending_card_choice.is_empty():
		return false
	# 换将过渡期内唯一合法的普通提交：与当前权威待办完全匹配的选择动作。
	# 机缘效果通过通用规则入口（获得装备、区域选牌等）嵌套创建的标准选择不带opportunity_前缀，同样必须放行；
	# 只按kind前缀过滤曾把这类嵌套选择全部拒绝，与结算管线的过渡门控形成循环等待并确认为对局死锁。
	# 旧回合遗留请求在过渡开始前已经清空或完成，请求ID与选择者的双重匹配足以阻挡任何过期或伪造提交。
	return action.actor_id == int(_pending_card_choice.get("chooser_id", -1)) \
		and int(action.payload.get("request_id", -1)) == int(_pending_card_choice.get("request_id", -2))


## 接受来自人类、AI 或网络的统一行为指令；返回是否通过规则校验并执行。
func submit_action(action: PlayerAction) -> bool:
	if action == null:
		return _reject("提交的玩家操作为空。")
	# 局域网客户端不持有权威状态；所有本地 UI 操作只上行给房主，并由房主使用同一函数再次完整校验。
	if network_gateway != null and network_gateway.is_lan_client():
		if not network_gateway.is_lan_match_active():
			return _reject("局域网对局尚未开始。")
		if action.actor_id != local_human_player_id:
			return _reject("客户端只能提交当前连接所绑定玩家的操作。")
		network_gateway.send_command(action)
		return true
	if state == null or state.game_over:
		return _reject("当前没有可操作的进行中对局。")
	# 过关斩将换将过渡只允许随后创建的机缘选择提交；旧回合遗留的出牌按钮或 AI 动作不能越过死亡结算继续执行。
	if _conquest_replacement_transition_active and not _is_conquest_replacement_opportunity_action_allowed(action):
		return _reject("敌方正在重新入场，请等待机缘选择。")
	# 离场技选择许可；只接受当前权威请求中明确写入的同一选择者和请求ID，旧请求或伪造普通动作无法复用该例外。
	var out_of_game_choice_allowed: bool = false
	# 机缘选择属于模式级三选一；离场角色仍可提交，但候选ID与待提交资格继续由机缘组件权威复核（全部参与者同时开放，不含先后顺序）。
	if action.action_type == "choose_opportunity":
		out_of_game_choice_allowed = true
	if action.action_type in ["choose_cards", "choice_response"] and not _pending_card_choice.is_empty():
		# 当前提交请求ID；choice_response与choose_cards都使用payload中的同名稳定字段。
		var submitted_request_id: int = int(action.payload.get("request_id", -1))
		# 当前请求上下文；allow_out_of_game_chooser由离场技等明确允许离场选择的规则写入，普通请求不得复用。
		var pending_choice_context: Dictionary = _pending_card_choice.get("context", {}) as Dictionary
		out_of_game_choice_allowed = action.actor_id == int(_pending_card_choice.get("chooser_id", -1)) \
			and submitted_request_id == int(_pending_card_choice.get("request_id", -2)) \
			and bool(pending_choice_context.get("allow_out_of_game_chooser", false))
	# 对局内行动者状态；普通离场角色不能借旧请求、旧按钮或网络封包继续执行任何玩家操作。
	var submitted_actor: PlayerState = state.get_player(action.actor_id)
	if submitted_actor != null and submitted_actor.out_of_game and not out_of_game_choice_allowed:
		return _reject("当前角色已移出游戏，不能执行操作。")
	if action.action_type == "set_auto_managed":
		return _submit_auto_management_change(action)
	# 托管玩家仍由 AI 通过同一动作入口执行；真人、本地脚本或远端封包不能在托管期间抢占操作。
	if _is_player_auto_managed(action.actor_id) and not _is_internal_ai_submission(action.actor_id):
		return _reject("当前玩家正在托管中，暂时不能进行操作。")
	if is_gameplay_paused() and ai_coordinator != null and ai_coordinator.is_ai_controlled(action.actor_id):
		return false
	if action.action_type == "choose_opportunity":
		if opportunity_system == null or not opportunity_system.submit_choice(action.actor_id, str(action.payload.get("card_id", ""))):
			return _reject("当前机缘选择已失效或所选机缘卡不在候选中。")
		state.action_sequence += 1
		return true
	if action.action_type == "select_character":
		return select_character(action.actor_id, str(action.payload.get("character_id", "")), int(action.payload.get("seat_number", -1)), str(action.payload.get("identity", "")))
	if action.action_type == "wheel_duel_pick":
		return pick_wheel_duel_candidate(action.actor_id, int(action.payload.get("slot_id", -1)))
	if action.action_type == "wheel_duel_submit_lineup":
		var lineup_ids: Array[String] = []
		for character_id_variant: Variant in action.payload.get("character_ids", []) as Array:
			lineup_ids.append(str(character_id_variant))
		return submit_wheel_duel_lineup(action.actor_id, lineup_ids)
	if action.action_type == "replace_character_candidate":
		return replace_character_candidate(action.actor_id, str(action.payload.get("character_id", "")))
	if action.action_type == "preview_custom_assignment":
		return preview_custom_assignment(action.actor_id, int(action.payload.get("seat_number", -1)), str(action.payload.get("identity", "")))
	if action.action_type == "select_ai_adjustment_target":
		return _select_ai_adjustment_target(action)
	if action.action_type == "set_ai_character":
		return _set_ai_character(action)
	if action.action_type == "finish_ai_character_adjustment":
		return _finish_ai_character_adjustment_action(action)
	if action.action_type == "mulligan_refresh":
		return _submit_mulligan_refresh(action)
	if action.action_type == "mulligan_finish":
		return _submit_mulligan_finish(action)
	if action.action_type == "use_skill":
		# 出牌阶段主动技能必须先完成当前 chooseToUse，技能内部后续选牌或选目标才会成为其子选择上下文。
		if action.actor_id == state.current_player_id and state.current_phase == "play":
			# 本次提交的稳定技能 ID；必须属于行动玩家当前安装的技能实例。
			var skill_id: String = str(action.payload.get("skill_id", ""))
			if not can_activate_skill(action.actor_id, skill_id, action.payload):
				return _reject("该技能当前不满足发动条件。")
			if not _submit_play_choice_response(action):
				return false
			# 技能发动结果；失败时仍会恢复新的出牌请求供玩家继续操作。
			var activated: bool = activate_skill(action.actor_id, skill_id, action.payload)
			# 技能被规则取消或执行入口返回错误时也必须恢复出牌请求，避免已关闭的 chooseToUse 令玩家失去后续操作。
			# 多步技能在流程间隔等待下一段选牌时仍算交互未完成，不能在空窗期抢先打开出牌窗口。
			if not state.game_over and state.current_phase == "play" and not has_pending_play_interaction():
				_begin_play_choice(state.current_player_id)
				# 同步一次完成的主动技能（如【天裁】①这类不创建任何子选择的轮回节）只在此处重建出牌窗口，
				# 而 activate_skill 内部的状态广播发生在本次重建之前；若不再补发一次，界面快照会停留在“无请求”状态，
				# 使手牌、确定/取消与结束回合按钮全部失效（只能靠再次点击技能按钮被动恢复）。
				# 只有确实新建了出牌请求才广播，阶段被规则取消或被流程间隔接管时沿用各自既有广播路径。
				if _has_active_play_choice():
					_emit_state()
			# 主动技能分支会在通用动作尾部之前返回；统一续接入口负责调度同步技能后的下一次AI行动或技能子选择。
			_ensure_ai_progress_after_resolution()
			return activated
		return activate_skill(action.actor_id, str(action.payload.get("skill_id", "")), action.payload)
	if action.action_type == "choice_response":
		var choice_response: ChoiceResponse = ChoiceResponse.from_dict(action.payload)
		var choice_action: PlayerAction = PlayerAction.new("choose_cards", choice_response.actor_id)
		choice_action.client_sequence = choice_response.client_sequence
		choice_action.payload = {
			"request_id":choice_response.request_id,
			"event_id":choice_response.event_id,
			"selected_card_uids":choice_response.card_ids.duplicate(),
			"selected_target_ids":choice_response.target_ids.duplicate(),
			"selected_button_ids":choice_response.button_ids.duplicate(),
			"selected_control_id":choice_response.control_id,
			"confirmed":choice_response.confirmed,
		}
		if _pending_negation_choices.has(choice_response.request_id):
			return _submit_simultaneous_negation_choice(choice_action)
		return _submit_card_choice(choice_action)
	if action.action_type == "choose_cards":
		if _pending_negation_choices.has(int(action.payload.get("request_id", -1))):
			return _submit_simultaneous_negation_choice(action)
		return _submit_card_choice(action)
	if action.actor_id != state.current_player_id:
		return _reject("行动者不是当前回合玩家。")
	# 自定义装备动作定义；动作类型由当前装备文件声明，不在控制器维护白名单。
	var active_equipment_definition: CardDefinition = _get_play_phase_equipment_action_definition(action.actor_id, action.action_type)
	if action.action_type in ["use_card", "recast_card", "end_play"] or active_equipment_definition != null:
		var play_validation_error: String = _prevalidate_play_action(action)
		if not play_validation_error.is_empty():
			return _reject(play_validation_error)
		if not _submit_play_choice_response(action):
			return false

	if action.action_type == "use_card":
		# 行动者状态；前置检查已保证其存在且为当前玩家。
		var actor: PlayerState = state.get_player(action.actor_id)
		# 指令引用的手牌；不存在时由合法性服务返回明确原因。
		var card: CardInstance = actor.find_playable_card(action.card_uid)
		if card == null:
			return _reject("指定手牌不存在。")
		# 自动展开后的最终目标数组；全体目标牌由规则服务按座次生成。
		var target_ids: Array[int] = card_rules.normalize_targets(action.actor_id, card, action.target_ids)
		# 卡牌使用失败原因；空字符串表示合法。
		var validation_error: String = card_rules.validate_use(action.actor_id, card, target_ids)
		if not validation_error.is_empty():
			return _reject(validation_error)
		# 当前卡牌源码；角色语义辅助目标可在此从实际目标时机中剥离，但完整声明顺序仍保留在使用牌上下文。
		var card_source_definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
		# 实际结算目标；【借刀杀人】等牌会将第二声明目标保存为效果参数，目标时机与本牌实际目标只保留首名持刀者。
		var resolution_target_ids: Array[int] = card_source_definition.get_resolution_target_ids(target_ids) if card_source_definition != null else target_ids.duplicate()
		# 身份观察快照；公开行为按权威实际目标与当前目标状态计算，不持有或修改 GameState。
		var identity_observation_snapshot: Dictionary = state.to_dict(-1, true)
		# 本次身份观察配置；定义缺失时回退到卡牌元数据中的静态 AI 配置。
		var identity_ai_profile: Dictionary = card_source_definition.get_identity_observation_ai_profile(identity_observation_snapshot, action.actor_id, resolution_target_ids) if card_source_definition != null else (GameDatabase.get_card(card.definition_id).get("ai", {}) as Dictionary)
		ai_coordinator.observe_public_behavior(identity_observation_snapshot, action.actor_id, identity_ai_profile, resolution_target_ids, local_human_player_id)
		# 同一公开行为同步给远端客户端；客户端在本地重放推断，因此非房主也能得到“自动标记身份”结果。
		_broadcast_identity_behavior(action.actor_id, identity_ai_profile, resolution_target_ids)
		# 手牌视为牌通过统一虚拟牌协议结算：实体离开手牌后恢复原名，已经声明的逻辑牌继续完成完整牌效与次数统计。
		if card.has_hand_view_as() and card.zone == "hand":
			# 单材料数组；稳定UID同时用于失去牌、回放和最终弃牌区恢复原始实体。
			var view_as_material_uids: Array[int] = [card.uid]
			# 手牌视为牌的实体标记规则；【永劫】等锁定视为效果只把明确登记的距离覆写传给逻辑代理。
			var view_as_rule_overrides: Dictionary = {}
			if card.has_hand_mark_rule("ignore_distance_limit"):
				view_as_rule_overrides["ignore_distance_limit"] = true
			if not execute_virtual_card_use(action.actor_id, card.definition_id, view_as_material_uids, resolution_target_ids, "", view_as_rule_overrides):
				return _reject("手牌视为效果当前无法完成使用。")
		else:
			_execute_card_use(action.actor_id, card, resolution_target_ids, [], false, target_ids)
	elif action.action_type == "recast_card":
		if not _execute_recast(action.actor_id, action.card_uid):
			return false
	elif action.action_type == "end_play":
		_end_play_phase(action.actor_id)
	elif active_equipment_definition != null:
		if not active_equipment_definition.execute_play_phase_action(self, action):
			return false
	else:
		return _reject("未知行为类型：%s" % action.action_type)

	state.action_sequence += 1
	if action.action_type == "end_play":
		# 结束出牌已安排下一阶段；此处补发递增后的动作序号，真正阶段入口仍由唯一节奏任务到期后执行。
		_emit_state()
		return true
	if not state.game_over:
		# 当前回合角色；若其在本次行为的插入结算中死亡，应在当前事件完整结算后交给下名存活角色。
		var current_turn_player: PlayerState = state.get_player(state.current_player_id)
		if current_turn_player != null and (not current_turn_player.alive or current_turn_player.out_of_game):
			if current_turn_player.out_of_game:
				_advance_after_current_player_out_of_game(current_turn_player.player_id)
			else:
				_advance_after_current_player_death(current_turn_player.player_id)
			return true
	if not state.game_over and state.current_phase == "play" and not has_pending_play_interaction():
		_begin_play_choice(state.current_player_id)
	_emit_state()
	_ensure_ai_progress_after_resolution()
	return true


## 返回指定玩家是否已进入托管；该查询只读取权威状态，供动作权限与测试使用。
func is_player_auto_managed(player_id: int) -> bool:
	return _is_player_auto_managed(player_id)


## 处理真人发起的托管开关；操作人只能修改自己的真人角色，掉线托管只能由网络断线流程写入。
func _submit_auto_management_change(action: PlayerAction) -> bool:
	# 当前请求的玩家状态；不存在的稳定 ID 不能创建虚假的托管记录。
	var player: PlayerState = state.get_player(action.actor_id)
	if player == null:
		return _reject("托管目标不存在。")
	if not _is_auto_management_change_authorized(action.actor_id):
		return _reject("只能调整自己的托管状态。")
	# 当前目标状态；缺失 enabled 字段时回退为切换，保证按钮与未来通用操作入口都可复用。
	var enabled: bool = bool(action.payload.get("enabled", not player.auto_managed))
	if not enabled and player.auto_managed_offline:
		return _reject("该玩家已离线，无法取消托管。")
	if player.auto_managed == enabled and not player.auto_managed_offline:
		return true
	_set_player_auto_management(action.actor_id, enabled, false)
	return true


## 应用玩家托管状态并接入已有基础 AI；该函数只由已验证的手动开关或 LAN 掉线回调调用。
func _set_player_auto_management(player_id: int, enabled: bool, offline: bool) -> void:
	# 当前托管目标；断线回调和手动开关都必须先确认该稳定玩家仍属于本局。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	if enabled:
		player.auto_managed = true
		player.auto_managed_offline = offline
		ai_coordinator.register_basic_ai(player_id)
	else:
		player.auto_managed = false
		player.auto_managed_offline = false
		ai_coordinator.unregister_ai(player_id)
	# 托管状态是可回放的有效玩家操作；断线接管同样递增序号，使远端快照可稳定覆盖旧界面。
	state.action_sequence += 1
	_emit_state()
	if enabled:
		_continue_auto_managed_player(player_id)
	else:
		_republish_manual_player_choice(player_id)


## 让刚进入托管的玩家从当前选将、选择或出牌入口继续；不重建角色状态，也不直接修改事件栈。
func _continue_auto_managed_player(player_id: int) -> void:
	if state == null or state.game_over:
		return
	if _redrive_pre_game_ai_progress():
		return
	# 机缘全体选择期间接管；该玩家仍在待提交集合中时由机缘组件按AI估值代选，解除全局暂停等待。
	# 该分支缺失曾导致断线接管后选择队列永远停在已离线玩家、整个场景树保持暂停的确认卡死。
	if opportunity_system != null and opportunity_system.choose_for_managed_player(player_id):
		return
	if not _pending_card_choice.is_empty() and int(_pending_card_choice.get("chooser_id", -1)) == player_id:
		_schedule_ai_card_choice_response(int(_pending_card_choice.get("request_id", -1)), player_id)
		return
	# 同时无懈响应可能为多名玩家并行存在；只恢复当前托管玩家自己的请求。
	for request_id_variant: Variant in _pending_negation_choices.keys():
		# 当前待处理的无懈请求 ID；用于精确恢复该玩家的异步响应任务。
		var request_id: int = int(request_id_variant)
		# 当前无懈请求数据；缺失时为空字典，不会错误匹配有效玩家。
		var choice_data: Dictionary = _pending_negation_choices.get(request_id, {}) as Dictionary
		if int(choice_data.get("chooser_id", -1)) == player_id:
			# 当前无懈回合上下文；轮次 ID 会使旧协程在新一轮开始后自动失效。
			var response_context: Dictionary = choice_data.get("context", {}) as Dictionary
			_run_simultaneous_negation_ai_after_delay(request_id, player_id, int(response_context.get("negation_round_id", -1)))
	_ensure_ai_progress_after_resolution()


## 把仍在等待该玩家的选择重新交给真人界面；取消手动托管后不需要重新创建规则请求。
func _republish_manual_player_choice(player_id: int) -> void:
	if state == null or state.game_over:
		return
	if state.current_phase == "character_selection" and character_selection != null:
		character_selection_changed.emit(character_selection.to_dict(local_human_player_id))
	elif state.current_phase == "wheel_duel_selection" and wheel_duel_selection != null:
		character_selection_changed.emit(wheel_duel_selection.to_dict(local_human_player_id))
	if not _pending_card_choice.is_empty() and int(_pending_card_choice.get("chooser_id", -1)) == player_id:
		# 当前兼容选择副本；本地 UI 与远端私有请求都只接收可序列化数据。
		var choice_data: Dictionary = _pending_card_choice.duplicate(true)
		card_choice_requested.emit(choice_data)
		_replicate_choice_request_to_remote_player(choice_data)
	# 仍在等待该玩家的同时无懈窗口；取消托管时其AI计时器已被身份检查静默作废，必须重发私有候选让真人接手。
	# 统一走发布入口以保持控全模式“只显示首个待办”的既有语义，并同步复制给对应远端观察者。
	for negation_request_id_variant: Variant in _pending_negation_choices.keys():
		# 当前无懈窗口数据；只重发属于该玩家的请求，其他响应者的窗口保持原有等待。
		var negation_choice_data: Dictionary = _pending_negation_choices.get(int(negation_request_id_variant), {}) as Dictionary
		if int(negation_choice_data.get("chooser_id", -1)) == player_id:
			_publish_card_choice_request(negation_choice_data, false)


## 返回操作人是否被允许修改其托管状态；LAN 房主用真实发送 peer 复核，离线模式只允许本地座次。
func _is_auto_management_change_authorized(player_id: int) -> bool:
	if network_gateway != null and network_gateway.is_lan_host():
		# 当前远端发送 peer；0 表示房主本机直接提交，正数远端 peer 已由网关校验 actor 映射。
		var incoming_peer_id: int = network_gateway.get_current_incoming_peer_id()
		if incoming_peer_id > NetworkGateway.SERVER_PEER_ID:
			return network_gateway.get_peer_id_for_player(player_id) == incoming_peer_id
		return player_id == local_human_player_id
	return player_id == local_human_player_id


## 返回玩家当前是否为托管状态；内部入口统一处理空状态与不存在玩家，避免调用点直接持有 PlayerState。
func _is_player_auto_managed(player_id: int) -> bool:
	if state == null:
		return false
	# 当前玩家状态；缺失稳定 ID 时按非托管处理，后续规则入口会给出自己的错误。
	var player: PlayerState = state.get_player(player_id)
	return player != null and player.auto_managed


## 返回当前动作是否由控制器内部 AI 调度提交；该标记存于控制器内存而不写入网络 payload。
func _is_internal_ai_submission(player_id: int) -> bool:
	return int(_ai_submission_depth_by_player.get(player_id, 0)) > 0


## 让 AI 通过标准动作入口提交，并在调用栈内短暂登记来源；托管权限不会暴露给 UI 或网络封包。
func _submit_ai_action(action: PlayerAction) -> bool:
	if action == null:
		return false
	# 当前玩家已有的 AI 提交嵌套深度；同一动作结算中再次触发 AI 时仍保持正确来源。
	var previous_depth: int = int(_ai_submission_depth_by_player.get(action.actor_id, 0))
	_ai_submission_depth_by_player[action.actor_id] = previous_depth + 1
	# 当前标准动作结果；所有阶段、实体与选择校验仍由 submit_action 完成。
	var accepted: bool = submit_action(action)
	if previous_depth <= 0:
		_ai_submission_depth_by_player.erase(action.actor_id)
	else:
		_ai_submission_depth_by_player[action.actor_id] = previous_depth
	return accepted


## 返回当前玩家可执行的全部基础动作，供 AI 决策与 UI 辅助使用。
func get_legal_actions(player_id: int) -> Array[Dictionary]:
	# 合法动作结果；每项均可直接转换为 PlayerAction。
	var result: Array[Dictionary] = []
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return result
	# 当前玩家状态；其手牌决定所有使用牌与重铸候选。
	var player: PlayerState = state.get_player(player_id)
	for card: CardInstance in player.get_playable_cards():
		# 当前卡牌定义；用于目标模式与 AI 展示字段。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		# 当前卡牌目标模式；决定候选目标组合的生成方式。
		var target_mode: String = str(definition.get("target_mode", ""))
		if target_mode == "response_only":
			continue
		if bool(definition.get("recast", false)) and card.zone == "hand":
			result.append({"action_type":"recast_card", "actor_id":player_id, "card_uid":card.uid, "target_ids":[], "card_definition_id":card.definition_id})
		# 当前卡牌源码；复杂多目标组合可在自身文件追加完整动作并接管默认枚举。
		var source_definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
		if source_definition != null and source_definition.append_play_phase_card_actions(self, player_id, card, result):
			continue
		if target_mode == "all_players" or target_mode == "all_others":
			_append_if_legal(result, player_id, card, [])
			continue
		# 当前卡牌所有单目标候选；铁索连环当前基础 AI 先使用单目标形式。
		var legal_targets: Array[int] = card_rules.list_legal_targets(player_id, card)
		for target_id: int in legal_targets:
			_append_if_legal(result, player_id, card, [target_id])
	# 装备主动动作；每件当前装备自行向统一结果追加 AI 可执行动作。
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；定义缺失时安全跳过。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null:
			equipment_definition.append_play_phase_actions(self, player_id, equipment_card, result)
	# 武将技能动作；每个运行时技能实例自行判断阶段、次数、资源和目标组合。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；样例或纯被动技能默认不会追加动作。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect():
			skill.append_play_phase_actions(result)
	return result


## 返回指定卡牌与当前目标顺序的只读交互预览，供 UI 展示合法目标、步骤提示与确认状态。
func get_card_use_preview(player_id: int, card_uid: int, selected_target_ids: Array[int] = []) -> Dictionary:
	if network_gateway != null and network_gateway.is_lan_client():
		return _get_remote_card_use_preview(player_id, card_uid, selected_target_ids)
	# 预览默认结果；任何不可操作状态都会返回明确原因且不暴露权威对象引用。
	var result: Dictionary = {
		"card_found": false,
		"can_submit": false,
		"validation_error": "当前卡牌不可用。",
		"legal_target_ids": [],
		"normalized_target_ids": [],
		"target_mode": "",
		"min_targets": 0,
		"max_targets": 0,
		"description": "",
	}
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return result
	# 行动玩家状态；只用于查找其手牌或木牛“粮”。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return result
	# 指定实体牌；UI 始终使用稳定 UID，不依赖手牌数组位置。
	var card: CardInstance = player.find_playable_card(card_uid)
	if card == null:
		return result
	# 卡牌定义；预览只返回界面需要的基础元数据。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 当前目标模式；用于 UI 决定是否自动选择自己或由核心展开全体目标。
	var target_mode: String = str(definition.get("target_mode", ""))
	# 规范化目标；全体目标牌由规则服务按存活座次自动展开。
	var normalized_targets: Array[int] = card_rules.normalize_targets(player_id, card, selected_target_ids)
	# 当前完整组合的规则校验结果；空字符串表示确认按钮可以提交。
	var validation_error: String = card_rules.validate_use(player_id, card, normalized_targets)
	# 下一步合法候选目标；候选会结合已有目标顺序验证当前卡牌的完整目标组合。
	var legal_target_ids: Array[int] = []
	for candidate: PlayerState in state.players:
		if not candidate.alive or selected_target_ids.has(candidate.player_id):
			continue
		# 候选目标顺序；把当前候选追加到已有选择末尾以保留顺序语义。
		var candidate_targets: Array[int] = selected_target_ids.duplicate()
		candidate_targets.append(candidate.player_id)
		# 候选完整校验结果；达到最少目标数后可直接使用完整校验。
		var candidate_error: String = card_rules.validate_use(player_id, card, candidate_targets)
		if candidate_error.is_empty():
			legal_target_ids.append(candidate.player_id)
			continue
		# 部分目标允许继续选择；单目标合法性由服务查询，双目标牌首目标也由该查询覆盖。
		if selected_target_ids.is_empty() and card_rules.list_legal_targets(player_id, card).has(candidate.player_id):
			legal_target_ids.append(candidate.player_id)
	result["card_found"] = true
	result["can_submit"] = validation_error.is_empty()
	result["validation_error"] = validation_error
	result["legal_target_ids"] = legal_target_ids
	result["normalized_target_ids"] = normalized_targets
	result["target_mode"] = target_mode
	result["min_targets"] = int(definition.get("min_targets", 0))
	result["max_targets"] = card_rules.get_maximum_target_count(player_id, card)
	result["description"] = str(definition.get("description", ""))
	return result


## 返回任意出牌阶段主动装备的只读交互预览；具体字段由对应装备文件生成。
func get_equipment_action_preview(player_id: int, equipment_uid: int, payload: Dictionary, selected_target_ids: Array[int] = []) -> Dictionary:
	if network_gateway != null and network_gateway.is_lan_client():
		return _get_remote_equipment_action_preview(player_id, equipment_uid, payload, selected_target_ids)
	if state == null:
		return {}
	# 当前武器实体；兼容 UI 入口只负责按 UID 定位装备源码。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return {}
	# 当前装备实体；按 UID 遍历全部槽位，支持武器、防具和宝物主动动作。
	var equipment_card: CardInstance
	for equipment_variant: Variant in player.equipment.values():
		var candidate: CardInstance = equipment_variant as CardInstance
		if candidate.uid == equipment_uid:
			equipment_card = candidate
			break
	if equipment_card == null:
		return {}
	# 当前武器定义；具体材料、目标和说明全部由装备文件提供。
	var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
	if equipment_definition == null:
		return {}
	return equipment_definition.get_play_phase_action_preview(self, player_id, equipment_uid, payload, selected_target_ids)


## 返回当前出牌阶段可以直接点击发动的装备实体 UID；结果只供界面候选位移和 chooseToUse 请求使用。
func get_play_phase_equipment_action_uids(player_id: int) -> Array[int]:
	# 可点击装备结果；装备条件不满足时保持空数组。
	var result: Array[int] = []
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return result
	# 当前玩家；每件装备自行检查手牌、次数、目标与其他发动条件。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return result
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；可用性钩子为 true 时进入界面候选。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null and equipment_definition.is_play_phase_action_available(self, player_id, equipment_card):
			result.append(equipment_card.uid)
	return result


## 按动作类型查找当前玩家装备区中声明该主动动作的唯一卡牌定义。
func _get_play_phase_equipment_action_definition(player_id: int, action_type: String) -> CardDefinition:
	if action_type.is_empty():
		return null
	# 当前玩家；不存在时没有装备主动动作。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；动作类型由其源码定义声明。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null and equipment_definition.get_play_phase_action_types().has(action_type):
			return equipment_definition
	return null


## 按主动动作类型返回当前玩家用于进入chooseToUse的装备实体UID；材料牌只属于装备的后续专用选择，不能替代该入口。
func _get_play_phase_equipment_action_uid(player_id: int, action_type: String) -> int:
	if action_type.is_empty():
		return -1
	# 当前玩家；不存在时没有可用于提交请求的装备入口。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return -1
	# 当前玩家装备遍历项；每个值都应是公开装备区中的实体牌。
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；只有其定义明确声明同一主动动作类型时才返回稳定UID。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		# 当前装备定义；内容文件拥有动作类型，控制器不维护具体装备白名单。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null and equipment_definition.get_play_phase_action_types().has(action_type):
			return equipment_card.uid
	return -1


## 返回当前是否存在等待玩家或 AI 提交的选择窗口；牌、目标和组合请求都会暂停后续结算。
func has_pending_card_choice() -> bool:
	if network_gateway != null and network_gateway.is_lan_client():
		# 远端当前选择请求；出牌阶段 use 请求属于常驻动作入口，不视为效果结算中的临时选择窗口。
		var remote_choice: Dictionary = _remote_snapshot.get("current_choice_request", {}) as Dictionary
		return not remote_choice.is_empty() and int(remote_choice.get("actor_id", -1)) == local_human_player_id and str(remote_choice.get("choice_type", "")) != "use"
	return not _pending_card_choice.is_empty() or not _pending_negation_choices.is_empty()


## 返回出牌阶段是否仍有未完成的交互结算；包含临时选择与会创建下一段选择的技能流程间隔，避免星落等多步技能在弹窗间隔空窗期误开 chooseToUse。
func has_pending_play_interaction() -> bool:
	if has_pending_card_choice():
		return true
	# 连续虚拟用牌等技能后续队列仍属于当前主动技能；队列排空前不得提前重建普通chooseToUse。
	if not _deferred_skill_settlements.is_empty():
		return true
	# 仅技能多步选牌间隔阻塞出牌窗口恢复；response_prompt 与 phase_transition 有各自恢复路径，不得因残留计时器卡住 chooseToUse。
	return game_flow_pacer != null and game_flow_pacer.has_pending_skill_interval()


## 在多步技能或流程间隔结束后尝试恢复正式出牌窗口；已有选择、间隔任务或活动 chooseToUse 时安全忽略。
func resume_play_phase_choice() -> void:
	if state == null or state.game_over or state.current_phase != "play":
		return
	if has_pending_play_interaction() or _has_active_play_choice():
		return
	_begin_play_choice(state.current_player_id)
	_emit_state()
	_ensure_ai_progress_after_resolution()


## 供技能流程间隔到期后重新进入统一结算管线；已有选择、判定或终局时内部入口会安全忽略。
func resume_settlement_pipeline() -> void:
	_resume_settlement_pipeline()
	if event_scheduler != null:
		event_scheduler.drain()


## 登记唯一的延后结算唤醒；多个技能、时机或停滞修复同帧请求时只保留一个call_deferred。
## 唤醒实际通过process_frame跨帧执行；直接接管和离树时释放连接，代次校验作为额外的过期回调保护。
func _schedule_settlement_pipeline_resume() -> void:
	if _settlement_resume_scheduled or state == null or state.game_over or not is_inside_tree():
		return
	_settlement_resume_scheduled = true
	_settlement_resume_generation += 1
	# 本次延后唤醒捕获的对局代次；重开或拆除后与当前值不等时直接失效。
	var resume_generation: int = _settlement_resume_generation
	_settlement_resume_callback = _run_scheduled_settlement_pipeline_resume.bind(resume_generation)
	get_tree().process_frame.connect(_settlement_resume_callback, CONNECT_ONE_SHOT)


## 执行已登记的延后结算唤醒；只有代次一致的唯一任务能重新进入管线。
func _run_scheduled_settlement_pipeline_resume(resume_generation: int) -> void:
	if resume_generation != _settlement_resume_generation:
		return
	_invalidate_scheduled_settlement_resume()
	_resume_settlement_pipeline()
	# 回合边界在结算管线排空前被暂缓时，排空后重新尝试同一边界；不创建新的回合或出牌窗口。
	if _pending_conquest_boundary_player_id >= 0 and _conquest_temporary_exit_requested:
		var boundary_player_id: int = _pending_conquest_boundary_player_id
		if _try_capture_conquest_temporary_exit(boundary_player_id):
			_pending_conquest_boundary_player_id = -1
		elif _conquest_temporary_exit_requested:
			_schedule_settlement_pipeline_resume()
		else:
			_pending_conquest_boundary_player_id = -1


## 释放当前帧唤醒的信号所有权；显式恢复、重开和离树复用，不能仅清布尔值而留下活动连接。
func _invalidate_scheduled_settlement_resume() -> void:
	if is_inside_tree() and _settlement_resume_callback.is_valid() and get_tree().process_frame.is_connected(_settlement_resume_callback):
		get_tree().process_frame.disconnect(_settlement_resume_callback)
	_settlement_resume_callback = Callable()
	_settlement_resume_generation += 1
	_settlement_resume_scheduled = false


## 节点离树后不再拥有对局帧唤醒；避免被释放的控制器留下绑定方法的延迟连接。
func _exit_tree() -> void:
	_invalidate_scheduled_settlement_resume()


## 使全部旧延后唤醒失效并重置技能续结算诊断；重新开局、放弃对局与半成品回滚共用。
func _reset_settlement_runtime_guard() -> void:
	_rule_sequences.clear()
	_rule_sequence_execution_depth = 0
	_invalidate_scheduled_settlement_resume()
	_settlement_pipeline_running = false
	_next_skill_settlement_id = 1
	_active_skill_settlement_key = ""
	_active_skill_settlement_visits.clear()
	_active_skill_settlement_chain_steps = 0
	_active_rule_continuation_key = ""
	_active_rule_continuation_visits.clear()
	_active_rule_continuation_chain_steps = 0
	_last_settlement_fault.clear()
	_settlement_fault_count = 0


## 返回最近一次统一结算局部熔断摘要；返回值为深拷贝，调试器不能改写真实运行时。
func get_last_settlement_fault() -> Dictionary:
	return _last_settlement_fault.duplicate(true)


## 返回本局统一结算局部熔断次数；该数值会纳入停滞指纹，但不参与玩法计算。
func get_settlement_fault_count() -> int:
	return _settlement_fault_count


## 记录一次统一结算局部熔断；详情合并当前阶段、队列与故障序号后发送只读信号。
func _record_settlement_fault(reason: String, details: Dictionary = {}) -> void:
	_settlement_fault_count += 1
	# 故障摘要；基础字段先建立，业务详情只能追加稳定可序列化数据。
	var fault_data: Dictionary = {
		"reason":reason,
		"fault_count":_settlement_fault_count,
		"phase":state.current_phase if state != null else "",
		"current_player_id":state.current_player_id if state != null else -1,
		"deferred_skill_settlement_count":_deferred_skill_settlements.size(),
		"rule_continuation_count":_rule_continuations.size(),
		"trigger_dispatch_count":trigger_manager.get_deferred_dispatch_count() if trigger_manager != null else 0,
	}
	for detail_key_variant: Variant in details.keys():
		# 当前详情键；统一转为字符串，保证网络、回放与JSON诊断具有相同形态。
		var detail_key: String = str(detail_key_variant)
		fault_data[detail_key] = details[detail_key_variant]
	_last_settlement_fault = fault_data.duplicate(true)
	settlement_faulted.emit(fault_data.duplicate(true))
	add_log("【流程保护】已终止异常结算步骤（%s），对局继续运行。" % reason)


## 取消指定请求的延时响应提示任务；请求已提交、中断或关闭后必须立即释放，否则 GameFlowPacer 残留任务会让 has_pending_play_interaction 误判为仍在交互中。
func _cancel_paced_response_prompt(request_id: int) -> void:
	if request_id < 0 or game_flow_pacer == null:
		return
	game_flow_pacer.cancel("response_prompt:%d" % request_id)


## 为当前角色创建可持续的 chooseToUse 请求；普通牌候选只包含可直接使用或重铸的实体，技能与装备材料由对应入口另行开放。
func _begin_play_choice(player_id: int) -> void:
	if state == null or state.game_over or state.current_phase != "play" or state.current_player_id != player_id:
		return
	if _has_active_play_choice():
		return
	# 已预约临时退出时，出牌询问重建点就是“每次操作结算完成后”的最近空闲存档点；
	# 捕获成功后本窗口不再创建，界面层随即保存退出，恢复时会重新建立等价询问。
	if _try_capture_conquest_temporary_exit_at_play_idle():
		return
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return
	# 出牌选择时机数据；主动入口同时包含阶段主动和用牌询问，技能命中任意一个即可加入候选。
	var timing_data: Dictionary = {"phase":"play", "active_entries":["phaseUse", "chooseToUse"]}
	# 使用牌选择前事件；取消表示本次不再建立选择窗口并直接结束当前出牌阶段。
	var before_event: RuleEvent = _emit_rule_timing("chooseToUseBefore", player_id, player_id, -1, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		_end_play_phase(player_id)
		return
	# 持续出牌请求事件；挂到运行时当前根，缓存根ID可能因reset失效。
	var event: GameEvent = event_scheduler.create_event("chooseToUse", "choice", [], {"player_id":player_id, "phase":"play"}, event_scheduler.root_event_id)
	event.player_id = player_id
	# 使用牌选择开始事件；在 ChoiceRequest 登记前派发，触发器可阻止本次窗口但不能伪造候选。
	var begin_event: RuleEvent = _emit_rule_timing("chooseToUseBegin", player_id, player_id, -1, timing_data, event.event_id)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		event.cancel("choose_to_use_cancelled")
		_end_play_phase(player_id)
		return
	var request: ChoiceRequest = ChoiceRequest.new(event.event_id, player_id, "use", "请选择要使用的牌或结束出牌阶段")
	request.min_count = 0
	request.max_count = 1
	request.can_cancel = true
	request.forced = false
	# 当前完整合法动作；具体装备和技能动作名全部由内容源码追加。
	var legal_actions: Array[Dictionary] = get_legal_actions(player_id)
	# 当前动作类型集合；结束出牌始终可用，其他类型从合法动作动态去重。
	var action_types: Array[String] = ["end_play"]
	for legal_action: Dictionary in legal_actions:
		var action_type: String = str(legal_action.get("action_type", ""))
		if not action_type.is_empty() and not action_types.has(action_type):
			action_types.append(action_type)
	# 当前两个主动入口的合法技能；请求只公开 ID，实际发动仍由 can_activate_skill 与 activate_skill 复核。
	var active_skill_ids: Array[String] = get_active_skill_ids(player_id, "phaseUse", timing_data)
	for choose_to_use_skill_id: String in get_active_skill_ids(player_id, "chooseToUse", timing_data):
		if not active_skill_ids.has(choose_to_use_skill_id):
			active_skill_ids.append(choose_to_use_skill_id)
	request.base_context = {"phase":"play", "action_types":action_types, "active_entries":["phaseUse", "chooseToUse"], "active_skill_ids":active_skill_ids}
	request.active_context = request.base_context.duplicate(true)
	request.button_ids = active_skill_ids.duplicate()
	for legal_action: Dictionary in legal_actions:
		# 当前动作类型；只有普通用牌与重铸能让动作自身的card_uid成为可直接点击手牌，技能或装备材料必须等待对应入口选中后再点亮。
		var candidate_action_type: String = str(legal_action.get("action_type", ""))
		if candidate_action_type not in ["use_card", "recast_card"]:
			continue
		# 当前可直接点击实体UID；同一张牌的多个目标动作只登记一次。
		var candidate_uid: int = int(legal_action.get("card_uid", -1))
		if candidate_uid >= 0 and not request.card_ids.has(candidate_uid):
			request.card_ids.append(candidate_uid)
	# 出牌请求允许提交的目标玩家；具体牌的数量、距离与组合语义仍由动作预校验和 CardRuleService 权威复核。
	for target_player: PlayerState in state.players:
		if target_player.alive and not target_player.out_of_game:
			request.target_ids.append(target_player.player_id)
	for equipment_uid: int in get_play_phase_equipment_action_uids(player_id):
		if not request.card_ids.has(equipment_uid):
			request.card_ids.append(equipment_uid)
	if event_scheduler.request_choice(request) == null:
		return
	_play_choice_request_id = request.request_id
	_play_choice_event_id = event.event_id
	_play_choice_actor_id = player_id
	_play_choice_match_id = state.match_id
	# 出牌选择是 phaseUse 下的真实等待事件；长期根事件保持开放时由此把请求压入调度栈。
	event_scheduler.drain()


## 返回当前 chooseToUse 是否仍是本局、本回合的活动请求；旧对局请求不会阻塞规则测试或新开局。
func _has_active_play_choice() -> bool:
	if _play_choice_request_id < 0 or state == null or _play_choice_match_id != state.match_id or _play_choice_actor_id != state.current_player_id:
		return false
	for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
		if int(request_data.get("request_id", -1)) == _play_choice_request_id and int(request_data.get("event_id", -1)) == _play_choice_event_id:
			return true
	return false


## 返回当前活动chooseToUse的只读请求快照；请求已经结束或不属于当前记录时返回空字典。
func _get_active_play_choice_snapshot() -> Dictionary:
	if not _has_active_play_choice():
		return {}
	# 当前待处理请求快照；只返回与控制器记录的请求ID和事件ID同时一致的一项。
	for request_data: Dictionary in event_scheduler.get_pending_choice_requests():
		if int(request_data.get("request_id", -1)) == _play_choice_request_id and int(request_data.get("event_id", -1)) == _play_choice_event_id:
			return request_data
	return {}


## 判断一条最新合法动作能否由既有chooseToUse快照表达；技能、普通牌与装备分别校验各自独立入口。
func _is_play_action_represented_by_choice(action: Dictionary, request_snapshot: Dictionary) -> bool:
	# 当前动作类型；结束阶段不需要牌或技能候选即可提交取消响应。
	var action_type: String = str(action.get("action_type", ""))
	if action_type == "end_play":
		return true
	if action_type == "use_skill":
		# 当前技能ID；优先读取标准负载，兼容合法动作顶层保留的索引字段。
		var skill_payload: Dictionary = action.get("payload", {}) as Dictionary
		# 当前技能稳定ID；必须已经登记为请求按钮候选。
		var skill_id: String = str(skill_payload.get("skill_id", action.get("skill_id", "")))
		return not skill_id.is_empty() and (request_snapshot.get("button_ids", []) as Array).has(skill_id)
	# 当前装备入口UID；木牛等动作的card_uid是材料牌，因此必须反查装备本体。
	var equipment_uid: int = _get_play_phase_equipment_action_uid(int(action.get("actor_id", -1)), action_type)
	if equipment_uid >= 0:
		return (request_snapshot.get("card_ids", []) as Array).has(equipment_uid)
	if action_type in ["use_card", "recast_card"]:
		return (request_snapshot.get("card_ids", []) as Array).has(int(action.get("card_uid", -1)))
	return false


## AI决策前重建已经落后于动态合法动作的chooseToUse快照；返回true表示本次确实完成了一次无副作用刷新。
func _refresh_stale_ai_play_choice(player_id: int, legal_actions: Array[Dictionary]) -> bool:
	if state == null or state.current_player_id != player_id or not _has_active_play_choice():
		return false
	# 当前活动请求快照；只读比较候选，不修改请求内部选择状态。
	var request_snapshot: Dictionary = _get_active_play_choice_snapshot()
	if request_snapshot.is_empty():
		return false
	# 当前最新合法动作；任何一项缺少请求入口都说明整个快照已经落后。
	for legal_action: Dictionary in legal_actions:
		if _is_play_action_represented_by_choice(legal_action, request_snapshot):
			continue
		# 旧请求只由系统取消，不执行结束出牌阶段；新请求立即按最新技能、装备与普通牌候选重新生成。
		_cancel_active_play_choice("refresh_stale_ai_play_choice")
		_begin_play_choice(player_id)
		return true
	return false


## 把现有 UI/AI 高层动作转换为当前 chooseToUse 的标准 ChoiceResponse，并交给事件运行时校验。
func _submit_play_choice_response(action: PlayerAction) -> bool:
	if not _has_active_play_choice():
		# 无 match_id 的纯规则测试直接调用控制器公开接口时，不强制依赖场景级出牌请求。
		return state.match_id.is_empty()
	var response: ChoiceResponse = ChoiceResponse.new(_play_choice_request_id, _play_choice_event_id, action.actor_id, action.action_type != "end_play")
	if action.action_type == "use_skill":
		response.button_ids = [str(action.payload.get("skill_id", ""))]
	elif action.action_type != "end_play":
		# 装备主动入口UID；木牛等动作把card_uid用于材料牌，chooseToUse实际消费的始终是此前点亮的装备本体。
		var equipment_uid: int = _get_play_phase_equipment_action_uid(action.actor_id, action.action_type)
		response.card_ids = [equipment_uid if equipment_uid >= 0 else action.card_uid]
	response.target_ids = action.target_ids.duplicate()
	response.client_sequence = action.client_sequence
	response.source = "ai" if ai_coordinator.is_ai_controlled(action.actor_id) else ("network" if network_gateway.mode != NetworkGateway.Mode.OFFLINE else "local")
	if not event_scheduler.submit_choice(response):
		return _reject("当前出牌选择已经失效或所选卡牌不合法。")
	_emit_rule_timing("chooseToUseAfter", action.actor_id, action.actor_id, -1, {"confirmed":response.confirmed, "action_type":action.action_type, "card_ids":response.card_ids.duplicate(), "target_ids":response.target_ids.duplicate()}, _play_choice_event_id)
	_play_choice_request_id = -1
	_play_choice_event_id = -1
	_play_choice_actor_id = -1
	_play_choice_match_id = ""
	return true


## 关闭仍属于上一回合的 chooseToUse 请求；换回合、死亡转交和测试强制转交都不能让旧请求继续阻塞根事件栈。
func _cancel_active_play_choice(reason: String) -> void:
	if not _has_active_play_choice():
		return
	# 系统取消响应；空卡牌与 confirmed=false 等价于结束旧选择窗口，但不会执行 end_play 的弃牌和阶段逻辑。
	var response: ChoiceResponse = ChoiceResponse.new(_play_choice_request_id, _play_choice_event_id, _play_choice_actor_id, false)
	response.source = "system:%s" % reason
	event_scheduler.submit_choice(response)
	_play_choice_request_id = -1
	_play_choice_event_id = -1
	_play_choice_actor_id = -1
	_play_choice_match_id = ""


## 在消费 chooseToUse 请求前执行无副作用预校验；失败动作不会关闭玩家当前出牌窗口。
func _prevalidate_play_action(action: PlayerAction) -> String:
	if action.action_type == "end_play":
		return "" if state.current_phase == "play" else "当前不能结束出牌阶段。"
	var actor: PlayerState = state.get_player(action.actor_id)
	if actor == null or state.current_phase != "play":
		return "当前不在可操作的出牌阶段。"
	if action.action_type == "use_card":
		var card: CardInstance = actor.find_playable_card(action.card_uid)
		if card == null:
			return "指定手牌不存在。"
		var normalized_targets: Array[int] = card_rules.normalize_targets(action.actor_id, card, action.target_ids)
		return card_rules.validate_use(action.actor_id, card, normalized_targets)
	if action.action_type == "recast_card":
		var recast_card: CardInstance = actor.find_hand_card(action.card_uid)
		if recast_card == null or not bool(GameDatabase.get_card(recast_card.definition_id).get("recast", false)):
			return "该卡牌当前不能重铸。"
		return ""
	# 装备主动动作定义；具体材料、目标、次数与区域条件由对应装备文件校验。
	var equipment_definition: CardDefinition = _get_play_phase_equipment_action_definition(action.actor_id, action.action_type)
	if equipment_definition != null:
		return equipment_definition.validate_play_phase_action(self, action)
	return "未知行为类型：%s" % action.action_type


## 创建统一选择请求；默认用于选牌，包装接口可通过上下文切换为选目标或牌目标组合。
func request_card_choice(chooser_id: int, title: String, prompt: String, candidates: Array[Dictionary], min_select: int, max_select: int, allow_cancel: bool, context: Dictionary) -> Array[int]:
	if state == null or state.game_over or not _pending_card_choice.is_empty() or not _pending_negation_choices.is_empty():
		return []
	# 当前选择者；死亡角色始终不能建立请求，离场角色仅可继续明确标记为离场技的自身选择。
	var choice_player: PlayerState = state.get_player(chooser_id)
	var allow_out_of_game_chooser: bool = bool(context.get("allow_out_of_game_chooser", false))
	if choice_player == null or not choice_player.alive or (choice_player.out_of_game and not allow_out_of_game_chooser):
		return []
	_resolved_card_choice_uids.clear()
	_resolved_target_choice_ids.clear()
	_resolved_equipment_material_uids.clear()
	_resolved_control_choice_id = ""
	_resolved_response_skill_id = ""
	# 选择事件名称；响应、弃牌和普通选牌使用稳定名称，调用方可通过 choice_event_name 指定其他已实现选择类型。
	var choice_type: String = str(context.get("choice_type_override", "card"))
	# 默认选择事件名称；目标与组合选择使用各自标准名称，普通请求使用 chooseCard。
	var default_choice_event_name: String = "chooseTarget" if choice_type in ["target", "target_control"] else ("chooseCardTarget" if choice_type == "card_target" else ("chooseToMove" if choice_type == "arrange" else "chooseCard"))
	# 最终选择事件名称；内容可显式覆盖为目录中已经实现的其他选择事件。
	var choice_event_name: String = str(context.get("choice_event_name", default_choice_event_name))
	# 选择用途稳定标识；用于恢复具体卡牌、装备、阶段或技能步骤。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_type == "card" and (not (context.get("response_patterns", []) as Array).is_empty() or choice_kind == "trick_negation"):
		choice_type = "respond"
		choice_event_name = "chooseToRespond"
	elif choice_type == "card" and choice_kind == "discard_phase":
		choice_type = "discard"
		choice_event_name = "chooseToDiscard"
	# 目标候选；target 与 card_target 请求只传递稳定玩家 ID，不向客户端暴露 PlayerState 引用。
	var choice_target_ids: Array[int] = []
	for target_id: int in _int_array(context.get("choice_target_ids", []) as Array):
		# 当前目标候选；统一入口只公开仍存活且在场的角色，具体技能仍可继续收紧目标条件。
		var choice_target: PlayerState = state.get_player(target_id)
		if choice_target != null and choice_target.alive and not choice_target.out_of_game and not choice_target_ids.has(target_id):
			choice_target_ids.append(target_id)
	# 卡牌维度范围；普通选牌沿用函数参数，组合选择可通过上下文独立配置。
	var minimum_card_count: int = int(context.get("min_card_select", 0 if choice_type in ["target", "target_control", "control", "bool"] else min_select))
	# 卡牌维度上限；始终不小于下限，避免异常技能参数创建无法完成的请求。
	var maximum_card_count: int = maxi(int(context.get("max_card_select", 0 if choice_type in ["target", "target_control", "control", "bool"] else max_select)), minimum_card_count)
	# 目标维度范围；纯选目标默认沿用函数参数，组合选择默认要求0名目标并由包装接口显式填写。
	var minimum_target_count: int = int(context.get("min_target_select", min_select if choice_type == "target" else 0))
	# 目标维度上限；始终不小于下限。
	var maximum_target_count: int = maxi(int(context.get("max_target_select", max_select if choice_type == "target" else minimum_target_count)), minimum_target_count)
	# 选择前时机只在目录确实存在对应 Before 名称时派发；普通 chooseCard 当前只有 Begin 时机。
	var choice_before_name: String = "%sBefore" % choice_event_name
	if RuleTimingCatalog.has_timing(choice_before_name):
		var choice_before_event: RuleEvent = _emit_rule_timing(choice_before_name, chooser_id, chooser_id, -1, {"choice_type":choice_type, "kind":choice_kind, "min_count":min_select, "max_count":max_select})
		if choice_before_event != null and (choice_before_event.cancelled or choice_before_event.neutralized):
			return []
	# 所有已登记选择类型的 Begin 时机在创建权威请求前触发；取消时不会产生无法提交的界面窗口。
	var choice_begin_name: String = "%sBegin" % choice_event_name
	if RuleTimingCatalog.has_timing(choice_begin_name):
		var choice_begin_event: RuleEvent = _emit_rule_timing(choice_begin_name, chooser_id, chooser_id, -1, {"choice_type":choice_type, "kind":choice_kind, "min_count":min_select, "max_count":max_select})
		if choice_begin_event != null and (choice_begin_event.cancelled or choice_begin_event.neutralized):
			return []
	# 请求创建前的规则阶段；选择提交后必须恢复，避免把响应窗口误当作新的回合阶段。
	var resume_phase: String = state.current_phase
	# 候选只读副本；UI 和 AI 只能看到请求明确公开的牌面，不能取得 CardInstance 引用。
	var serialized_candidates: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		serialized_candidates.append(candidate.duplicate(true))
	# 文字选项只读副本；每项仅保留稳定 ID 与显示标签，不允许脚本对象或回调进入选择协议。
	var serialized_control_options: Array[Dictionary] = []
	for option_variant: Variant in context.get("control_options", []) as Array:
		# 当前文字选项；空 ID、空标签和重复 ID 均不进入权威候选。
		var option: Dictionary = option_variant as Dictionary
		var option_id: String = str(option.get("id", ""))
		var option_label: String = str(option.get("label", ""))
		if option_id.is_empty() or option_label.is_empty():
			continue
		var duplicate_option: bool = false
		for existing_option: Dictionary in serialized_control_options:
			if str(existing_option.get("id", "")) == option_id:
				duplicate_option = true
				break
		if not duplicate_option:
			serialized_control_options.append({"id":option_id, "label":option_label})
	# 未注册 AI 的正式对局角色等待本地或网络动作；无 match_id 的纯规则测试使用标准放弃动作避免悬停。
	var interactive_human: bool = not ai_coordinator.is_ai_controlled(chooser_id) and local_human_player_id >= 0 and not state.match_id.is_empty()
	# 当前选择者是否由内置 AI 控制；AI 选择同样异步等待，避免响应牌和效果选牌绕过可调节的响应节奏。
	# 无 match_id 的纯规则状态不属于正在运行的对局，继续同步调用策略以保持测试与服务端预演确定性。
	var ai_controlled_chooser: bool = ai_coordinator.is_ai_controlled(chooser_id) and not state.match_id.is_empty()
	_pending_card_choice = {
		"request_id":-1,
		"chooser_id":chooser_id,
		"title":title,
		"prompt":prompt,
		"candidates":serialized_candidates,
		"choice_type":choice_type,
		"target_ids":choice_target_ids.duplicate(),
		"control_options":serialized_control_options.duplicate(true),
		"min_select":maxi(min_select, 0),
		"max_select":maxi(max_select, min_select),
		"min_card_select":maxi(minimum_card_count, 0),
		"max_card_select":maxi(maximum_card_count, minimum_card_count),
		"min_target_select":maxi(minimum_target_count, 0),
		"max_target_select":maxi(maximum_target_count, minimum_target_count),
		"allow_cancel":allow_cancel,
		"resume_phase":resume_phase,
		"context":context.duplicate(true),
		"choice_event_name":choice_event_name,
		"deferred":interactive_human or ai_controlled_chooser,
	}
	# 请求结构自检；没有任何标准合法动作的请求无法由玩家、AI或网络完成，必须在注册暂停令牌前安全拒绝。
	# allow_cancel=true 时 _build_card_choice_actions 必含取消动作，即使 candidates 为空（火攻同花色、铁壁无【闪】等隐私询问）也不得在此跳过。【无懈可击】并行登记不走本入口，仍可空候选不建阻塞窗口。
	if _build_card_choice_actions(_pending_card_choice).is_empty():
		if allow_cancel:
			# 防御分支：未来枚举若遗漏取消动作，仍强制可取消并继续登记，避免私密空候选被静默吞掉。
			_pending_card_choice["allow_cancel"] = true
		else:
			var invalid_choice_kind: String = str((_pending_card_choice.get("context", {}) as Dictionary).get("kind", "unknown"))
			_pending_card_choice.clear()
			_reject("选择请求没有合法结果，已跳过以避免流程停滞：%s。" % invalid_choice_kind)
			return []
	# 独立选择事件；控制器的兼容恢复分支继续执行具体效果，EventScheduler 负责请求身份和旧响应失效。
	# 选择父事件；规则效果内创建的响应必须挂到当前 content 子事件，阶段级选择则回退到长期根事件。
	var choice_parent_event_id: int = event_scheduler.get_current_event_id()
	if choice_parent_event_id < 0:
		# 调度器才是活动树的权威来源；重置后旧控制器摘要ID不能作为新请求父节点。
		choice_parent_event_id = event_scheduler.root_event_id
	# 调用方请求的稳定父事件；连续选择可复用原卡牌时机，避免把后续选择挂到已经解决的上一条选择事件。
	var requested_choice_parent_event_id: int = int(context.get("choice_parent_event_id", -1))
	# 被请求父事件的只读摘要；只有尚未终结的事件才能继续接收子选择，过期值安全回退当前事件。
	var requested_parent_event_snapshot: Dictionary = event_scheduler.get_event_snapshot(requested_choice_parent_event_id)
	if requested_choice_parent_event_id >= 0 and not requested_parent_event_snapshot.is_empty() and not bool(requested_parent_event_snapshot.get("finalized", true)):
		choice_parent_event_id = requested_choice_parent_event_id
	# 独立选择事件；控制器恢复分支执行具体结果，EventScheduler 负责父子阻塞、请求身份和旧响应失效。
	var choice_event: GameEvent = event_scheduler.create_event(choice_event_name, "choice", [], context, choice_parent_event_id)
	choice_event.player_id = chooser_id
	var runtime_request: ChoiceRequest = ChoiceRequest.new(choice_event.event_id, chooser_id, choice_type, prompt)
	runtime_request.min_count = maxi(min_select, 0)
	runtime_request.max_count = maxi(max_select, min_select)
	runtime_request.min_card_count = maxi(minimum_card_count, 0)
	runtime_request.max_card_count = maxi(maximum_card_count, minimum_card_count)
	runtime_request.min_target_count = maxi(minimum_target_count, 0)
	runtime_request.max_target_count = maxi(maximum_target_count, minimum_target_count)
	runtime_request.forced = not allow_cancel
	runtime_request.can_cancel = allow_cancel
	runtime_request.base_context = context.duplicate(true)
	# 实际选择父事件ID；后续连续选择可显式复用这个仍在等待的规则事件，避免依赖短生命周期的选择事件栈顶。
	runtime_request.base_context["choice_parent_event_id"] = choice_parent_event_id
	runtime_request.active_context = context.duplicate(true)
	# 当前选择可发动的主动技能；响应入口与普通选牌入口分别查询，结果只进入请求上下文不改变牌候选。
	var active_entry: String = "chooseToRespond" if choice_event_name == "chooseToRespond" else "chooseCard"
	runtime_request.base_context["active_entry"] = active_entry
	# 标准可发动技能；响应转换材料会在候选生成时额外声明对应技能，不能因其未实现普通主动入口而从本次响应按钮中遗漏。
	var active_skill_ids: Array[String] = get_active_skill_ids(chooser_id, active_entry, context)
	for response_skill_id_variant: Variant in context.get("response_conversion_skill_ids", []) as Array:
		# 候选已由权威转化查询生成；只补充非空且未重复的稳定技能ID。
		var response_skill_id: String = str(response_skill_id_variant)
		if not response_skill_id.is_empty() and not active_skill_ids.has(response_skill_id):
			active_skill_ids.append(response_skill_id)
	runtime_request.base_context["active_skill_ids"] = active_skill_ids
	runtime_request.active_context = runtime_request.base_context.duplicate(true)
	_pending_card_choice["context"] = runtime_request.base_context.duplicate(true)
	for candidate: Dictionary in serialized_candidates:
		runtime_request.card_ids.append(int(candidate.get("uid", -1)))
	runtime_request.target_ids = choice_target_ids.duplicate()
	for option: Dictionary in serialized_control_options:
		runtime_request.control_ids.append(str(option.get("id", "")))
	# 选择请求必须使用事件调度器分配的全局 ID；控制器自有序号不能与 chooseToUse 或其他请求共用命名空间。
	var registered_request: ChoiceRequest = event_scheduler.request_choice(runtime_request)
	if registered_request == null:
		# 登记失败时撤销临时事件并清空待处理状态，禁止界面显示无法提交的假窗口。
		_pending_card_choice.clear()
		choice_event.abort("choice_registration_failed")
		return []
	runtime_request = registered_request
	_card_choice_sequence = runtime_request.request_id
	_ai_choice_submit_failures.erase(runtime_request.request_id)
	_pending_card_choice["request_id"] = runtime_request.request_id
	_pending_card_choice["runtime_event_id"] = choice_event.event_id
	_pending_card_choice["runtime_request_id"] = runtime_request.request_id
	# 技能或效果子选择一旦登记成功，必须关闭可能在流程间隔空窗期误开的出牌请求，避免旧 chooseToUse 继续占用运行时请求表。
	if choice_type != "use":
		_cancel_active_play_choice("nested_choice_started")
	state.current_phase = "choice"
	_publish_card_choice_request(_pending_card_choice, choice_type == "respond")
	# 当前调用不在调度器内容步骤内时立即把选择子事件压栈；调度中重入 drain 会安全返回并由外层循环接管。
	event_scheduler.drain()
	if interactive_human:
		return []
	if ai_controlled_chooser:
		# 响应牌提示由节奏组件延时发布时，AI 必须在提示发布后才开始自身等待，避免与人类窗口同帧抢先提交。
		if choice_type != "respond" or game_flow_pacer == null or game_flow_interval_seconds <= 0.0:
			_schedule_ai_card_choice_response(runtime_request.request_id, chooser_id)
		return []
	# 非交互回退的合法动作列表；纯规则测试仍只从标准动作中选择，不能直接移动候选牌。
	var legal_actions: Array[Dictionary] = _build_card_choice_actions(_pending_card_choice)
	# 兼容策略快照；仅用于生成回退动作，不向策略暴露可变状态。
	var full_snapshot: Dictionary = state.to_dict(chooser_id, true)
	_append_limited_skill_usage_to_snapshot(full_snapshot)
	# 兼容策略选择结果；仍需经 submit_action 与 request_id、UID 和数量校验。
	var ai_response: ChoiceResponse = ai_coordinator.request_choice(chooser_id, full_snapshot, runtime_request, _pending_card_choice, legal_actions)
	var action_data: Dictionary = {}
	if ai_response != null:
		var ai_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		ai_action.payload = {"request_id":int(_pending_card_choice.get("request_id", runtime_request.request_id)), "event_id":ai_response.event_id, "selected_card_uids":ai_response.card_ids.duplicate(), "selected_target_ids":ai_response.target_ids.duplicate(), "selected_control_id":ai_response.control_id, "confirmed":ai_response.confirmed}
		action_data = ai_action.to_dict()
	if action_data.is_empty() or not _submit_ai_action(PlayerAction.from_dict(action_data)):
		# 同步规则测试也复用标准合法动作回退，固定牌组和响应转换字段不能退化为“前N项候选”。
		var fallback_action_data: Dictionary = _build_ai_choice_fallback_action(_pending_card_choice)
		if not fallback_action_data.is_empty():
			_submit_ai_action(PlayerAction.from_dict(fallback_action_data))
	return _resolved_card_choice_uids.duplicate()


## 创建单项文字选项请求；选项 ID 参与权威校验，显示标签仅供界面呈现，具体效果由恢复上下文决定。
func request_control_choice(chooser_id: int, title: String, prompt: String, options: Array[Dictionary], allow_cancel: bool = true, context: Dictionary = {}) -> String:
	# 控制项上下文；稳定选择类型与候选副本由本包装接口统一写入，调用方只维护业务 kind。
	var control_context: Dictionary = context.duplicate(true)
	control_context["choice_type_override"] = "control"
	control_context["control_options"] = options.duplicate(true)
	control_context["min_card_select"] = 0
	control_context["max_card_select"] = 0
	control_context["min_target_select"] = 0
	control_context["max_target_select"] = 0
	request_card_choice(chooser_id, title, prompt, [], 1, 1, allow_cancel, control_context)
	return _resolved_control_choice_id


## 创建目标与文字选项同时提交的复合请求；目标和选项均由同一权威ChoiceResponse复核。
func request_target_control_choice(chooser_id: int, title: String, prompt: String, target_ids: Array[int], options: Array[Dictionary], allow_cancel: bool = true, context: Dictionary = {}) -> Dictionary:
	# 复合选择上下文；控制项沿用min_select范围，目标维度固定选择一名角色。
	var combined_context: Dictionary = context.duplicate(true)
	combined_context["choice_type_override"] = "target_control"
	combined_context["control_options"] = options.duplicate(true)
	combined_context["choice_target_ids"] = target_ids.duplicate()
	combined_context["min_card_select"] = 0
	combined_context["max_card_select"] = 0
	combined_context["min_target_select"] = 1
	combined_context["max_target_select"] = 1
	request_card_choice(chooser_id, title, prompt, [], 1, 1, allow_cancel, combined_context)
	return {"target_ids":_resolved_target_choice_ids.duplicate(), "control_id":_resolved_control_choice_id}


## 发布一条兼容选择请求；响应牌窗口按游戏速度延时显示，其他选牌与目标请求保持立即可操作。
func _publish_card_choice_request(choice_data: Dictionary, paced_response: bool) -> void:
	# 当前请求 ID；独立业务键允许同时无懈的多个请求并行等待且互不取消。
	var request_id: int = int(choice_data.get("request_id", -1))
	# 离线全角色控制把并行无懈转为同一玩家依次操作；后登记请求保留权威并行状态，但等前一名明确放弃后再显示。
	if _control_all_characters_enabled and not _pending_negation_choices.is_empty():
		var first_pending_request_id: int = int(_pending_negation_choices.keys()[0])
		if request_id != first_pending_request_id:
			return
	if not paced_response or game_flow_pacer == null or game_flow_interval_seconds <= 0.0 or request_id < 0:
		if _prepare_offline_controlled_view(int(choice_data.get("chooser_id", -1))):
			_emit_state()
		card_choice_requested.emit(choice_data.duplicate(true))
		_replicate_choice_request_to_remote_player(choice_data)
		return
	# 延时提示回调；到期后会重新读取权威待处理请求，不长期持有候选牌副本。
	var publish_callback: Callable = Callable(self, "_emit_paced_card_choice_request").bind(request_id)
	game_flow_pacer.schedule("response_prompt:%d" % request_id, game_flow_interval_seconds, publish_callback)


## 发出仍然有效的延时响应提示；请求已提交、取消或重开时不显示过期窗口。
func _emit_paced_card_choice_request(request_id: int) -> void:
	if not _pending_card_choice.is_empty() and int(_pending_card_choice.get("request_id", -1)) == request_id:
		if _prepare_offline_controlled_view(int(_pending_card_choice.get("chooser_id", -1))):
			_emit_state()
		card_choice_requested.emit(_pending_card_choice.duplicate(true))
		_replicate_choice_request_to_remote_player(_pending_card_choice)
		# 当前普通响应选择者；AI 从提示已经公开的时刻开始计算自身响应等待，人类则继续等待标准动作提交。
		var chooser_id: int = int(_pending_card_choice.get("chooser_id", -1))
		if chooser_id >= 0 and ai_coordinator.is_ai_controlled(chooser_id):
			_schedule_ai_card_choice_response(request_id, chooser_id)
		return
	if _pending_negation_choices.has(request_id):
		# 当前同时无懈请求；每名响应者拥有独立私有候选，提示只发送对应请求的只读副本。
		var negation_choice_data: Dictionary = _pending_negation_choices.get(request_id, {}) as Dictionary
		if _prepare_offline_controlled_view(int(negation_choice_data.get("chooser_id", -1))):
			_emit_state()
		card_choice_requested.emit(negation_choice_data.duplicate(true))
		_replicate_choice_request_to_remote_player(negation_choice_data)
		# 当前无懈响应者；与普通响应一致，从提示发布后再开始独立 AI 等待。
		var responder_id: int = int(negation_choice_data.get("chooser_id", -1))
		# 当前无懈轮次；迟到任务仍由轮次 ID 和请求 ID 双重校验。
		var response_context: Dictionary = negation_choice_data.get("context", {}) as Dictionary
		if responder_id >= 0 and ai_coordinator.is_ai_controlled(responder_id):
			_run_simultaneous_negation_ai_after_delay(request_id, responder_id, int(response_context.get("negation_round_id", -1)))


## 创建统一选目标请求；该接口复用同一事件、暂停、AI、网络与恢复协议，不生成只供技能使用的旁路状态机。
func request_target_choice(chooser_id: int, prompt: String, target_ids: Array[int], min_select: int = 1, max_select: int = 1, allow_cancel: bool = true, context: Dictionary = {}) -> Array[int]:
	# 选目标上下文；包装接口只补充选择维度与候选，具体 kind 和技能步骤由调用方保留。
	var target_context: Dictionary = context.duplicate(true)
	target_context["choice_type_override"] = "target"
	target_context["choice_event_name"] = str(target_context.get("choice_event_name", "chooseTarget"))
	target_context["choice_target_ids"] = target_ids.duplicate()
	target_context["min_card_select"] = 0
	target_context["max_card_select"] = 0
	target_context["min_target_select"] = min_select
	target_context["max_target_select"] = max_select
	request_card_choice(chooser_id, "选择目标", prompt, [], min_select, max_select, allow_cancel, target_context)
	return _resolved_target_choice_ids.duplicate()


## 创建统一选牌并选目标请求；返回同步测试结果，正式本地、AI或网络流程通过技能 continue_selection 异步恢复。
func request_card_target_choice(chooser_id: int, title: String, prompt: String, candidates: Array[Dictionary], target_ids: Array[int], min_cards: int, max_cards: int, min_targets: int, max_targets: int, allow_cancel: bool, context: Dictionary = {}) -> Dictionary:
	# 组合选择上下文；牌与目标使用独立数量范围，避免复用单一 min_count 产生歧义。
	var combined_context: Dictionary = context.duplicate(true)
	combined_context["choice_type_override"] = "card_target"
	combined_context["choice_event_name"] = str(combined_context.get("choice_event_name", "chooseCardTarget"))
	combined_context["choice_target_ids"] = target_ids.duplicate()
	combined_context["min_card_select"] = min_cards
	combined_context["max_card_select"] = max_cards
	combined_context["min_target_select"] = min_targets
	combined_context["max_target_select"] = max_targets
	request_card_choice(chooser_id, title, prompt, candidates, min_cards, max_cards, allow_cancel, combined_context)
	return {"card_ids":_resolved_card_choice_uids.duplicate(), "target_ids":_resolved_target_choice_ids.duplicate()}


## 写入一份全体观察者可见的公共选牌展示；规则卡牌负责生成牌位与归属，界面只消费序列化副本。
func set_public_card_choice_display(display_data: Dictionary) -> void:
	if state == null:
		return
	state.public_card_choice_display = display_data.duplicate(true)
	public_card_choice_display_changed.emit(state.public_card_choice_display.duplicate(true))


## 清理指定类型的公共选牌展示；kind 为空时无条件清理，避免旧卡牌结算误关同步创建的新展示。
func clear_public_card_choice_display(kind: String = "") -> void:
	if state == null or state.public_card_choice_display.is_empty():
		return
	if not kind.is_empty() and str(state.public_card_choice_display.get("kind", "")) != kind:
		return
	state.public_card_choice_display.clear()
	public_card_choice_display_changed.emit({})


## 安排一条 AI 选牌响应；与普通 AI 出牌共用延迟参数，但使用请求 ID 防止旧窗口在新请求中误提交。
func _schedule_ai_card_choice_response(request_id: int, chooser_id: int) -> void:
	if is_gameplay_paused() or request_id < 0 or _scheduled_ai_choice_request_id == request_id:
		return
	# 当前阶段令牌；重开、换回合或终局后旧响应不会继续提交到新状态。
	var token: int = _ai_drive_token
	_scheduled_ai_choice_request_id = request_id
	_run_ai_card_choice_after_delay(request_id, chooser_id, token)


## 等待设置的响应时间后提交 AI 选择；决策和最终提交仍复用与玩家完全一致的标准动作入口。
func _run_ai_card_choice_after_delay(request_id: int, chooser_id: int, token: int) -> void:
	# AI 计时器不在场景树暂停期间推进；恢复后从剩余等待时间继续，而不是立即补交动作。
	await get_tree().create_timer(_get_effective_ai_response_delay_seconds(), false).timeout
	if _scheduled_ai_choice_request_id == request_id:
		_scheduled_ai_choice_request_id = -1
	if is_gameplay_paused() or state == null or state.game_over or _pending_card_choice.is_empty():
		return
	if int(_pending_card_choice.get("request_id", -1)) != request_id or int(_pending_card_choice.get("chooser_id", -1)) != chooser_id or not ai_coordinator.is_ai_controlled(chooser_id):
		return
	if token != _ai_drive_token:
		# 阶段令牌在等待期间被死亡结算、回合切换或额外阶段递增；同一请求仍是当前权威待办时必须按新令牌重排。
		# 静默作废会让该请求永远无人提交（重排入口曾被request_id去重挡回），这是已确认的对局卡死根因。
		_schedule_ai_card_choice_response(request_id, chooser_id)
		return
	# 当前运行时请求；待选快照使用 chooser_id/runtime_event_id 字段，恢复时显式映射到 ChoiceRequest 的 actor_id/event_id 协议。
	var runtime_request: ChoiceRequest = ChoiceRequest.new(int(_pending_card_choice.get("runtime_event_id", -1)), chooser_id, str(_pending_card_choice.get("choice_type", "card")), str(_pending_card_choice.get("prompt", "")))
	# 当前请求稳定 ID；策略生成的 ChoiceResponse 必须携带此 ID，避免迟到响应误命中新窗口。
	runtime_request.request_id = request_id
	runtime_request.min_count = int(_pending_card_choice.get("min_select", 0))
	runtime_request.max_count = int(_pending_card_choice.get("max_select", 1))
	runtime_request.min_card_count = int(_pending_card_choice.get("min_card_select", runtime_request.min_count))
	runtime_request.max_card_count = int(_pending_card_choice.get("max_card_select", runtime_request.max_count))
	runtime_request.min_target_count = int(_pending_card_choice.get("min_target_select", -1))
	runtime_request.max_target_count = int(_pending_card_choice.get("max_target_select", -1))
	for candidate_variant: Variant in _pending_card_choice.get("candidates", []) as Array:
		runtime_request.card_ids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	runtime_request.target_ids = _int_array(_pending_card_choice.get("target_ids", []) as Array)
	for option_variant: Variant in _pending_card_choice.get("control_options", []) as Array:
		runtime_request.control_ids.append(str((option_variant as Dictionary).get("id", "")))
	# 当前请求的合法兼容动作；每项仍会在提交时复核请求序号、候选 UID 和数量。
	var legal_actions: Array[Dictionary] = _build_card_choice_actions(_pending_card_choice)
	# 当前 AI 权威快照；策略只读取快照，不能取得可写的对局状态引用。
	var full_snapshot: Dictionary = state.to_dict(chooser_id, true)
	_append_limited_skill_usage_to_snapshot(full_snapshot)
	# AI 选择结果；空结果或异常结果随后使用同一候选集中的保守回退动作。
	var ai_response: ChoiceResponse = ai_coordinator.request_choice(chooser_id, full_snapshot, runtime_request, _pending_card_choice, legal_actions)
	var action_data: Dictionary = {}
	if ai_response != null:
		# AI 的标准选牌动作；事件 ID 与请求 ID 都由当前运行时请求提供，防止迟到响应进入新窗口。
		var ai_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		ai_action.payload = {"request_id":request_id, "event_id":ai_response.event_id, "selected_card_uids":ai_response.card_ids.duplicate(), "selected_target_ids":ai_response.target_ids.duplicate(), "selected_control_id":ai_response.control_id, "confirmed":ai_response.confirmed}
		action_data = ai_action.to_dict()
	if not action_data.is_empty() and _submit_ai_action(PlayerAction.from_dict(action_data)):
		return
	# 规则回退动作；直接复用合法动作枚举，保证固定牌组、转化技能ID和多维数量约束不会在回退路径丢失。
	var fallback_action_data: Dictionary = _build_ai_choice_fallback_action(_pending_card_choice)
	if not fallback_action_data.is_empty() and _submit_ai_action(PlayerAction.from_dict(fallback_action_data)):
		return
	_handle_failed_ai_choice_submission(request_id, chooser_id)


## 从规则层生成的合法选择中构建保守回退动作；可取消请求优先取消，强制请求选择稳定枚举中的首个确认结果。
func _build_ai_choice_fallback_action(choice_request: Dictionary) -> Dictionary:
	# 当前全部标准合法动作；其中已经包含固定组合、响应转换技能和文字选项所需字段。
	var legal_actions: Array[Dictionary] = _build_card_choice_actions(choice_request)
	if legal_actions.is_empty():
		return {}
	if bool(choice_request.get("allow_cancel", false)):
		for action: Dictionary in legal_actions:
			# 可取消请求的取消动作；异常策略不应在回退路径额外消耗资源。
			var payload: Dictionary = action.get("payload", {}) as Dictionary
			if not bool(payload.get("confirmed", false)):
				return action.duplicate(true)
	return legal_actions[0].duplicate(true)


## 处理AI策略与规则回退均提交失败的请求；有限重试耗尽后只中断该请求，防止永久占用选择暂停令牌。
func _handle_failed_ai_choice_submission(request_id: int, chooser_id: int) -> void:
	if _pending_card_choice.is_empty() or int(_pending_card_choice.get("request_id", -1)) != request_id:
		return
	# 当前请求连续失败次数；初次双重提交失败计为1，后续每次重新决策继续累加。
	var failure_count: int = int(_ai_choice_submit_failures.get(request_id, 0)) + 1
	_ai_choice_submit_failures[request_id] = failure_count
	if failure_count <= max_ai_choice_submit_retries:
		_schedule_ai_card_choice_response(request_id, chooser_id)
		return
	_abort_unresolvable_ai_choice(request_id, "ai_choice_submit_retries_exhausted")


## 中断一条已经无法通过权威入口提交的AI选择并恢复其父流程；正常技能取消与规则失败不得调用本入口。
func _abort_unresolvable_ai_choice(request_id: int, reason: String) -> void:
	if _pending_card_choice.is_empty() or int(_pending_card_choice.get("request_id", -1)) != request_id:
		return
	# 失效请求快照；清理前保存原阶段与业务类型，便于恢复阶段并输出长期诊断信息。
	var failed_choice: Dictionary = _pending_card_choice.duplicate(true)
	var failed_kind: String = str((failed_choice.get("context", {}) as Dictionary).get("kind", "unknown"))
	_cancel_paced_response_prompt(request_id)
	_pending_card_choice.clear()
	_scheduled_ai_choice_request_id = -1
	_ai_choice_submit_failures.erase(request_id)
	state.current_phase = str(failed_choice.get("resume_phase", state.current_phase))
	# 事件调度器只释放本请求的选择令牌；同一父事件中的其他暂停来源仍保持有效。
	event_scheduler.abort_choice(request_id, reason)
	_reject("AI选择连续提交失败，已中断失效请求并恢复流程：%s。" % failed_kind)
	# 被失效选择阻塞的通用续列；各组件只处理自身队列，不在本保护函数内识别具体技能ID。
	# 被失效选择阻塞的所有后续步骤仍经过同一优先级管线，单个请求中断不会改变父事件顺序。
	_resume_settlement_pipeline()
	event_scheduler.drain()
	_emit_state()
	_ensure_ai_progress_after_resolution()


## 枚举选择请求的基础合法动作；单选逐张枚举，多选为基础 AI 提供满足最少数量的稳定组合。
func _build_card_choice_actions(choice_request: Dictionary) -> Array[Dictionary]:
	# 合法动作结果；所有动作共享当前请求 ID 以防跨窗口提交。
	var result: Array[Dictionary] = []
	# 请求选择类型；文字控制项与卡牌、目标维度使用不同候选字段。
	var choice_type: String = str(choice_request.get("choice_type", "card"))
	# 是否允许取消；只有可取消请求才生成 confirmed=false 动作。
	var allow_cancel: bool = bool(choice_request.get("allow_cancel", false))
	# 请求最少选择数；为0时允许显式放弃。
	var min_select: int = int(choice_request.get("min_card_select", choice_request.get("min_select", 0)))
	# 请求最多选择数；单选请求会为每张候选生成一个动作。
	var max_select: int = int(choice_request.get("max_card_select", choice_request.get("max_select", 0)))
	# 目标选择范围；普通选牌默认为0，纯选目标和组合选择由请求显式提供。
	var min_target_select: int = int(choice_request.get("min_target_select", 0))
	# 目标选择上限；用于单目标逐项枚举或组合请求生成稳定基础动作。
	var max_target_select: int = int(choice_request.get("max_target_select", 0))
	# 请求序号；提交时由控制器再次核对。
	var request_id: int = int(choice_request.get("request_id", -1))
	# 选择者 ID；动作必须由被询问角色发出。
	var chooser_id: int = int(choice_request.get("chooser_id", -1))
	# 序列化候选；只读取稳定 UID。
	var candidates: Array = choice_request.get("candidates", []) as Array
	# 当前目标候选；只包含稳定玩家 ID。
	var target_ids: Array = choice_request.get("target_ids", []) as Array
	# 牌到完整有序目标组合的映射；用于同一技能内不同材料转化出不同目标数或目标语义的情况。
	var choice_context: Dictionary = choice_request.get("context", {}) as Dictionary
	var target_combinations_by_card_id: Dictionary = choice_context.get("target_combinations_by_card_id", {}) as Dictionary
	# 多材料组合到完整有序目标组合的映射；用于【山倾】等必须先支付多张材料再指定目标的复合请求。
	var target_combinations_by_card_combination: Dictionary = choice_context.get("target_combinations_by_card_combination", {}) as Dictionary
	if allow_cancel:
		var pass_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		pass_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":"", "confirmed":false}
		result.append(pass_action.to_dict())
	if choice_type == "arrange":
		# 排序请求的AI顺序由创建技能给出；缺失建议时保持候选原顺序并全部置于牌堆顶。
		var arrangement_context: Dictionary = choice_request.get("context", {}) as Dictionary
		var ordered_uids: Array[int] = _int_array(arrangement_context.get("ai_ordered_card_uids", []) as Array)
		if ordered_uids.size() != candidates.size():
			ordered_uids.clear()
			for candidate_variant: Variant in candidates:
				ordered_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		# AI顶行数量；限制到全部候选范围，0表示将所有剩余牌置于牌堆底。
		var top_count: int = clampi(int(arrangement_context.get("ai_top_count", ordered_uids.size())), 0, ordered_uids.size())
		var arrange_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		arrange_action.payload = {"request_id":request_id, "selected_card_uids":ordered_uids, "selected_target_ids":[], "selected_control_id":"top_count_%d" % top_count, "confirmed":true}
		result.append(arrange_action.to_dict())
		return result
	if choice_type == "target_control":
		# 目标与选项组合；每个合法“目标集合×文字选项”都生成独立动作，技能AI可统一比较完整收益。
		for selection_count: int in range(maxi(min_target_select, 0), mini(max_target_select, target_ids.size()) + 1):
			# 当前目标组合；通常为单目标，仍沿用通用枚举以保持协议可复用。
			var target_combinations: Array = []
			_collect_target_id_combinations(target_ids, selection_count, 0, [], target_combinations)
			for target_combination_variant: Variant in target_combinations:
				# 当前稳定目标数组；提交顺序与权威候选顺序一致。
				var target_combination: Array[int] = _int_array(target_combination_variant as Array)
				for option_variant: Variant in choice_request.get("control_options", []) as Array:
					# 当前控制项稳定ID；空ID不生成无法通过权威校验的动作。
					var option_id: String = str((option_variant as Dictionary).get("id", ""))
					if option_id.is_empty():
						continue
					var combined_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
					combined_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":target_combination.duplicate(), "selected_control_id":option_id, "confirmed":true}
					result.append(combined_action.to_dict())
		return result
	if choice_type in ["control", "bool"]:
		for option_variant: Variant in choice_request.get("control_options", []) as Array:
			# 当前文字选项；每个稳定 ID 生成一个标准确认动作，最终提交仍由 ChoiceRequest 再次校验。
			var option_id: String = str((option_variant as Dictionary).get("id", ""))
			if option_id.is_empty():
				continue
			var control_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
			control_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":option_id, "confirmed":true}
			result.append(control_action.to_dict())
		return result
	if choice_type == "respond":
		# 无材料响应技能作为独立确认动作进入同一AI候选集合；费用与牌型在提交阶段再次权威校验。
		var response_context: Dictionary = choice_request.get("context", {}) as Dictionary
		var response_patterns: Array[String] = _string_array(response_context.get("response_patterns", []) as Array)
		for skill_id_variant: Variant in response_context.get("active_skill_ids", []) as Array:
			# 当前响应技能；只有明确返回匹配定义ID的无材料技能才生成动作。
			var cardless_skill_id: String = str(skill_id_variant)
			var cardless_skill: SkillDefinition = get_skill_instance(chooser_id, cardless_skill_id)
			if cardless_skill == null or cardless_skill.get_cardless_response_definition_id(response_patterns).is_empty():
				continue
			var cardless_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
			cardless_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "cardless_response_skill_id":cardless_skill_id, "confirmed":true}
			result.append(cardless_action.to_dict())
	# 零材料布尔确认；技能必须显式声明 ai_allow_confirm，普通可取消选牌不会凭空生成确认动作。
	if max_select == 0 and max_target_select == 0 and bool((choice_request.get("context", {}) as Dictionary).get("ai_allow_confirm", false)):
		var confirm_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		confirm_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "confirmed":true}
		result.append(confirm_action.to_dict())
	if max_select == 0 and max_target_select == 1:
		for target_id_variant: Variant in target_ids:
			# 单目标动作；基础 AI 只能从权威候选中选一名角色。
			var target_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
			target_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[int(target_id_variant)], "confirmed":true}
			result.append(target_action.to_dict())
	elif max_select == 0 and max_target_select > 1:
		# 纯多目标请求；为固定双角色交换和“任意名角色”生成稳定不重复组合，提交后仍由ChoiceRequest复核数量与候选。
		for selection_count: int in range(maxi(min_target_select, 0), mini(max_target_select, target_ids.size()) + 1):
			# 当前数量的目标组合；结果受统一AI组合上限保护，避免10人任意目标产生指数级动作。
			var target_combinations: Array = []
			_collect_target_id_combinations(target_ids, selection_count, 0, [], target_combinations)
			for target_combination_variant: Variant in target_combinations:
				# 当前稳定目标组合；候选顺序沿用权威座次，不自行排序或重复目标。
				var target_combination: Array[int] = _int_array(target_combination_variant as Array)
				var target_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
				target_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":target_combination, "confirmed":true}
				result.append(target_action.to_dict())
	elif choice_type == "card_target" and max_select == 1 and not target_combinations_by_card_id.is_empty():
		# 逐材料完整目标组合；例如【传冲】的梅花材料转化【借刀杀人】时必须同时提交有序双目标。
		for candidate_variant: Variant in candidates:
			# 当前材料候选；只读取稳定UID以生成后续仍会被权威端复核的AI动作。
			var candidate: Dictionary = candidate_variant as Dictionary
			# 当前材料UID；字符串和整数键都兼容网络序列化前后的字典形态。
			var candidate_uid: int = int(candidate.get("uid", -1))
			# 当前材料允许的完整目标组合；不存在映射时不得回退到任意目标。
			var candidate_target_combinations: Array = target_combinations_by_card_id.get(str(candidate_uid), target_combinations_by_card_id.get(candidate_uid, [])) as Array
			for target_combination_variant: Variant in candidate_target_combinations:
				# 当前有序目标组合；复制为整数数组以保持【借刀杀人】等第一、第二目标语义。
				var target_combination: Array[int] = _int_array(target_combination_variant as Array)
				if target_combination.size() < min_target_select or target_combination.size() > max_target_select:
					continue
				var combined_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
				combined_action.payload = {"request_id":request_id, "selected_card_uids":[candidate_uid], "selected_target_ids":target_combination.duplicate(), "confirmed":true}
				result.append(combined_action.to_dict())
		return result
	elif choice_type == "card_target" and max_select > 1 and not target_combinations_by_card_combination.is_empty():
		# 多材料完整组合；每组材料只生成其专属合法目标，避免AI从目标并集中选到不匹配的远距离角色。
		var first_combination_size: int = maxi(min_select, 1)
		var last_combination_size: int = mini(max_select, candidates.size())
		for selection_count: int in range(first_combination_size, last_combination_size + 1):
			# 当前材料组合列表；候选顺序稳定，具体组合数量仍受统一枚举上限保护。
			var material_combinations: Array = []
			_collect_card_uid_combinations(candidates, selection_count, 0, [], material_combinations)
			for selected_uids_variant: Variant in material_combinations:
				# 当前完整材料UID数组；无序组合只用于查找目标映射，提交顺序仍保留玩家点击结果。
				var selected_uids: Array[int] = _int_array(selected_uids_variant as Array)
				if not _is_allowed_card_combination(choice_context, selected_uids):
					continue
				# 当前材料组合专属目标；缺失映射时不得回退到请求目标并集。
				var target_combinations: Array = target_combinations_by_card_combination.get(_make_card_combination_key(selected_uids), []) as Array
				for target_combination_variant: Variant in target_combinations:
					# 当前有序目标数组；山倾为单目标，协议仍保留数组形态以支持后续多目标技能。
					var target_combination: Array[int] = _int_array(target_combination_variant as Array)
					if target_combination.size() < min_target_select or target_combination.size() > max_target_select:
						continue
					var combined_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
					combined_action.payload = {"request_id":request_id, "selected_card_uids":selected_uids.duplicate(), "selected_target_ids":target_combination.duplicate(), "confirmed":true}
					result.append(combined_action.to_dict())
		return result
	elif max_select == 1 and max_target_select == 1:
		# 可选牌到目标映射；技能可用该字段表达选择一张牌后目标集合动态变化的组合规则。
		var targets_by_card_id: Dictionary = (choice_request.get("context", {}) as Dictionary).get("target_ids_by_card_id", {}) as Dictionary
		if min_select == 0:
			for target_id_variant: Variant in target_ids:
				# 零牌费用组合动作；自身横置的【天坠】等技能仍可只选择目标并确认。
				var target_only_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
				target_only_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[int(target_id_variant)], "confirmed":true}
				result.append(target_only_action.to_dict())
		for candidate_variant: Variant in candidates:
			# 当前卡牌 UID；组合动作会为每个合法目标生成一项，最终仍由 ChoiceRequest 复核牌到目标映射。
			var candidate: Dictionary = candidate_variant as Dictionary
			# 当前牌允许的目标；未提供映射时沿用请求的全部目标候选。
			var candidate_uid: int = int(candidate.get("uid", -1))
			var candidate_target_ids: Array = targets_by_card_id.get(str(candidate_uid), targets_by_card_id.get(candidate_uid, target_ids)) as Array
			for target_id_variant: Variant in target_ids:
				if not candidate_target_ids.has(int(target_id_variant)):
					continue
				var combined_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
				combined_action.payload = {"request_id":request_id, "selected_card_uids":[candidate_uid], "selected_target_ids":[int(target_id_variant)], "confirmed":true}
				result.append(combined_action.to_dict())
	elif max_select == 1:
		for candidate_variant: Variant in candidates:
			# 当前候选牌；每张牌对应一个可校验的单选动作。
			var candidate: Dictionary = candidate_variant as Dictionary
			var select_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
			select_action.payload = {"request_id":request_id, "selected_card_uids":[int(candidate.get("uid", -1))], "selected_target_ids":[], "confirmed":true}
			# 候选要求主动选择响应转化技能时，AI动作也必须显式携带技能ID，不能静默把材料当作响应牌。
			var required_response_skill_id: String = str(candidate.get("required_response_skill_id", ""))
			if not required_response_skill_id.is_empty():
				select_action.payload["response_skill_id"] = required_response_skill_id
			result.append(select_action.to_dict())
	elif min_select > 0 and candidates.size() >= min_select:
		# 强制多选牌组；枚举固定数量组合，使 AI 能依据卡牌价值选择最低费用或最高收益组合。
		var card_combinations: Array = []
		_collect_card_uid_combinations(candidates, min_select, 0, [], card_combinations)
		for selected_uids: Array in card_combinations:
			if not _is_allowed_card_combination(choice_request.get("context", {}) as Dictionary, _int_array(selected_uids)):
				continue
			var required_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
			required_action.payload = {"request_id":request_id, "selected_card_uids":selected_uids.duplicate(), "selected_target_ids":_first_target_ids(target_ids, min_target_select), "confirmed":true}
			result.append(required_action.to_dict())
	elif min_select == 0 and max_select > 1:
		# 可选多选请求；寒冰剑等效果需要比较选择1张或2张，水淹七军可声明只生成完整整组动作。
		var context: Dictionary = choice_request.get("context", {}) as Dictionary
		# 是否只允许 AI 考虑完整上限组；不改变玩家提交的权威数量范围，只裁剪基础 AI 枚举。
		var full_selection_only: bool = bool(context.get("ai_full_selection_only", false))
		# 最小确认数量；可选多选至少选择1张才构成确认。
		var first_count: int = mini(max_select, candidates.size()) if full_selection_only else 1
		# 最大确认数量；不能超过当前候选数量。
		var last_count: int = mini(max_select, candidates.size())
		for selection_count: int in range(first_count, last_count + 1):
			# 已生成确认动作数；取消动作不计入组合上限。
			var generated_confirmation_count: int = maxi(result.size() - 1, 0)
			# 当前数量仍可生成的组合数；达到总上限后停止后续数量枚举。
			var remaining_capacity: int = max_ai_choice_combinations - generated_confirmation_count
			if remaining_capacity <= 0:
				break
			# 当前数量的候选组合；总组合数仍受全局上限控制。
			var optional_combinations: Array = []
			_collect_card_uid_combinations(candidates, selection_count, 0, [], optional_combinations, remaining_capacity)
			for selected_uids: Array in optional_combinations:
				var optional_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
				optional_action.payload = {"request_id":request_id, "selected_card_uids":selected_uids.duplicate(), "selected_target_ids":_first_target_ids(target_ids, min_target_select), "confirmed":true}
				result.append(optional_action.to_dict())
	return result


## 递归枚举固定数量的候选牌 UID 组合；达到检查器配置上限后立即停止，避免大手牌请求组合爆炸。
func _collect_card_uid_combinations(candidates: Array, required_count: int, start_index: int, current_uids: Array[int], result: Array, requested_limit: int = -1) -> void:
	# 本次递归实际组合上限；负值使用控制器全局配置，显式值用于多个数量共享同一总预算。
	var combination_limit: int = max_ai_choice_combinations if requested_limit < 0 else mini(max_ai_choice_combinations, requested_limit)
	if result.size() >= combination_limit:
		return
	if current_uids.size() == required_count:
		result.append(current_uids.duplicate())
		return
	# 剩余所需数量；候选不足时循环上限自动阻止无效分支。
	var remaining_needed: int = required_count - current_uids.size()
	# 最后可选起始位置；保证包含当前位置在内仍有足够候选完成组合。
	var last_start_index: int = candidates.size() - remaining_needed
	for candidate_index: int in range(start_index, last_start_index + 1):
		# 当前候选 UID；只保存稳定实体标识，不向组合生成器传递牌面对象。
		var candidate_uid: int = int((candidates[candidate_index] as Dictionary).get("uid", -1))
		current_uids.append(candidate_uid)
		_collect_card_uid_combinations(candidates, required_count, candidate_index + 1, current_uids, result, combination_limit)
		current_uids.pop_back()
		if result.size() >= combination_limit:
			return


## 按候选顺序枚举固定数量的不重复目标组合；纯多目标选择与AI回退共用同一组合上限。
func _collect_target_id_combinations(target_ids: Array, required_count: int, start_index: int, current_target_ids: Array[int], result: Array, requested_limit: int = -1) -> void:
	# 当前组合上限；默认使用检查器配置，调用方可进一步缩小但不能扩大。
	var combination_limit: int = max_ai_choice_combinations if requested_limit < 0 else mini(max_ai_choice_combinations, requested_limit)
	if result.size() >= combination_limit:
		return
	if current_target_ids.size() == required_count:
		result.append(current_target_ids.duplicate())
		return
	# 尚需目标数；剩余候选不足时提前结束当前分支。
	var remaining_required: int = required_count - current_target_ids.size()
	for target_index: int in range(start_index, target_ids.size()):
		if target_ids.size() - target_index < remaining_required:
			break
		current_target_ids.append(int(target_ids[target_index]))
		_collect_target_id_combinations(target_ids, required_count, target_index + 1, current_target_ids, result, combination_limit)
		current_target_ids.pop_back()
		if result.size() >= combination_limit:
			return


## 返回候选数组前指定数量的 UID；只用于生成仍需权威校验的基础 AI 动作。
func _first_candidate_uids(candidates: Array, count: int) -> Array[int]:
	# UID 结果；数量不会超过候选总数。
	var result: Array[int] = []
	for index: int in range(mini(maxi(count, 0), candidates.size())):
		result.append(int((candidates[index] as Dictionary).get("uid", -1)))
	return result


## 返回目标候选数组前指定数量的玩家 ID；只用于生成仍需权威校验的基础 AI 回退动作。
func _first_target_ids(target_ids: Array, count: int) -> Array[int]:
	# 目标结果；数量不会超过候选总数，并保持请求声明的稳定顺序。
	var result: Array[int] = []
	for index: int in range(mini(maxi(count, 0), target_ids.size())):
		result.append(int(target_ids[index]))
	return result


## 校验并接受统一选择动作；同步 AI 返回给调用栈，人类和网络提交则恢复牌与目标对应的规则上下文。
func _submit_card_choice(action: PlayerAction) -> bool:
	if _pending_card_choice.is_empty():
		return _reject("当前没有等待处理的选牌请求。")
	if action.actor_id != int(_pending_card_choice.get("chooser_id", -1)):
		return _reject("该选择请求不属于当前行动者。")
	if int(action.payload.get("request_id", -1)) != int(_pending_card_choice.get("request_id", -2)):
		return _reject("选择请求已经失效。")
	if action.payload.has("event_id") and int(action.payload.get("event_id", -1)) != int(_pending_card_choice.get("runtime_event_id", -2)):
		return _reject("选择响应所属事件已经失效。")
	# 提交的实体牌 UID；逐项转换为整数并禁止重复选择。
	var selected_uids: Array[int] = []
	for uid_variant: Variant in action.payload.get("selected_card_uids", []):
		var selected_uid: int = int(uid_variant)
		if selected_uids.has(selected_uid):
			return _reject("不能重复选择同一张牌。")
		selected_uids.append(selected_uid)
	# 允许选择的 UID 集合；来源仅为本次请求快照。
	var candidate_uids: Array[int] = []
	for candidate_variant: Variant in _pending_card_choice.get("candidates", []):
		candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	for selected_uid: int in selected_uids:
		if not candidate_uids.has(selected_uid):
			return _reject("选择中包含不属于当前请求的牌。")
	# 提交的目标 ID；按操作顺序保留并禁止重复选择同一角色。
	var selected_target_ids: Array[int] = _int_array(action.payload.get("selected_target_ids", []) as Array)
	if selected_target_ids.size() != (action.payload.get("selected_target_ids", []) as Array).size():
		return _reject("目标选择数据格式无效。")
	# 允许选择的目标集合；来源仅为本次权威请求快照。
	var candidate_target_ids: Array[int] = _int_array(_pending_card_choice.get("target_ids", []) as Array)
	# 已见目标集合；重复目标不能通过组合请求提交。
	var seen_target_ids: Dictionary = {}
	for selected_target_id: int in selected_target_ids:
		if seen_target_ids.has(selected_target_id):
			return _reject("不能重复选择同一目标。")
		if not candidate_target_ids.has(selected_target_id):
			return _reject("选择中包含不属于当前请求的目标。")
		seen_target_ids[selected_target_id] = true
	# 当前请求选择类型；control 与 bool 使用单个稳定字符串，不占用卡牌或目标数组。
	var choice_type: String = str(_pending_card_choice.get("choice_type", "card"))
	# 提交的文字控制项 ID；空字符串表示取消或本请求不使用控制项维度。
	var selected_control_id: String = str(action.payload.get("selected_control_id", ""))
	# 权威文字控制项 ID；显示标签不参与规则校验，避免客户端伪造任意效果键。
	var candidate_control_ids: Array[String] = []
	for option_variant: Variant in _pending_card_choice.get("control_options", []) as Array:
		candidate_control_ids.append(str((option_variant as Dictionary).get("id", "")))
	if not selected_control_id.is_empty() and (choice_type not in ["control", "bool", "target_control", "arrange"] or not candidate_control_ids.has(selected_control_id)):
		return _reject("选择中包含无效文字选项。")
	# 卡牌与目标的独立数量范围；普通选牌的兼容字段继续映射到卡牌维度。
	var min_select: int = int(_pending_card_choice.get("min_card_select", _pending_card_choice.get("min_select", 0)))
	var max_select: int = int(_pending_card_choice.get("max_card_select", _pending_card_choice.get("max_select", 0)))
	# 目标选择数量；普通选牌保持0至0，纯目标与组合选择使用请求显式范围。
	var min_target_select: int = int(_pending_card_choice.get("min_target_select", 0))
	var max_target_select: int = int(_pending_card_choice.get("max_target_select", 0))
	var allow_cancel: bool = bool(_pending_card_choice.get("allow_cancel", false))
	# 是否确认当前选择；旧 choose_cards 动作未携带 confirmed 时按是否存在选择或强制数量推断。
	var confirmed: bool = bool(action.payload.get("confirmed", not selected_uids.is_empty() or not selected_target_ids.is_empty() or not selected_control_id.is_empty() or min_select > 0 or min_target_select > 0))
	if not confirmed and not allow_cancel:
		return _reject("当前选择不能取消。")
	if confirmed and choice_type in ["control", "bool", "target_control"]:
		# 控制项数量范围；当前协议使用空字符串表示0项、非空字符串表示1项。
		var selected_control_count: int = 0 if selected_control_id.is_empty() else 1
		var minimum_control_count: int = int(_pending_card_choice.get("min_select", 0))
		var maximum_control_count: int = int(_pending_card_choice.get("max_select", 1))
		if selected_control_count < minimum_control_count or selected_control_count > maximum_control_count:
			return _reject("选择的文字选项数量不符合要求。")
	if confirmed and choice_type == "arrange":
		# 排序请求必须携带唯一顶行数量；该数量允许0或全部候选，分别表示全部置底或全部置顶。
		if not selected_control_id.begins_with("top_count_"):
			return _reject("牌堆排序缺少牌堆顶行数量。")
		var arrangement_top_count: int = int(selected_control_id.trim_prefix("top_count_"))
		if arrangement_top_count < 0 or arrangement_top_count > selected_uids.size():
			return _reject("牌堆排序的牌堆顶行数量无效。")
	# 文字控制项的数量已在上方按 control_id 校验；不能再把其空实体牌数组误判为“选择的牌数不足”。
	if confirmed and choice_type not in ["control", "bool", "target_control"] and selected_uids.size() < min_select:
		return _reject("选择的牌数不足。")
	if selected_uids.size() > max_select:
		return _reject("选择的牌数超过上限。")
	# 请求声明的合法牌组；用于“选择两张牌名字数相同”等跨候选组合约束，客户端不能只凭数量绕过。
	if confirmed and not _is_allowed_card_combination(_pending_card_choice.get("context", {}) as Dictionary, selected_uids):
		return _reject("所选卡牌组合不符合当前技能要求。")
	# 响应转化技能必须由本次提交明确选择；普通实体响应牌不能伪造或继承技能ID。
	var selected_response_skill_id: String = str(action.payload.get("response_skill_id", ""))
	# 无材料响应技能；只允许在respond请求中以空实体数组提交，定义ID会由技能钩子再次推导而非信任客户端。
	var cardless_response_skill_id: String = str(action.payload.get("cardless_response_skill_id", ""))
	var cardless_response_definition_id: String = ""
	# 候选要求的响应技能ID；单选响应候选通过自身元数据声明，普通选择保持空字符串。
	var required_response_skill_id: String = ""
	if confirmed and selected_uids.size() == 1:
		for candidate_variant: Variant in _pending_card_choice.get("candidates", []) as Array:
			# 当前候选快照；稳定UID匹配后读取其转化技能要求。
			var candidate: Dictionary = candidate_variant as Dictionary
			if int(candidate.get("uid", -1)) == selected_uids[0]:
				required_response_skill_id = str(candidate.get("required_response_skill_id", ""))
				break
	if cardless_response_skill_id.is_empty() and selected_response_skill_id != required_response_skill_id:
		return _reject("请先发动对应技能，再选择该响应材料。")
	if not cardless_response_skill_id.is_empty():
		if choice_type != "respond" or not confirmed or not selected_uids.is_empty() or not selected_response_skill_id.is_empty():
			return _reject("无材料响应技能的选择格式无效。")
		# 当前无材料响应技能；必须仍安装、可在本响应入口发动且返回匹配当前响应牌型的定义。
		var cardless_skill: SkillDefinition = get_skill_instance(action.actor_id, cardless_response_skill_id)
		var response_patterns_for_skill: Array[String] = _string_array((_pending_card_choice.get("context", {}) as Dictionary).get("response_patterns", []) as Array)
		var cardless_cost_paid: bool = bool(action.payload.get("cardless_cost_paid", false))
		var pending_active_skill_ids: Array = ((_pending_card_choice.get("context", {}) as Dictionary).get("active_skill_ids", []) as Array)
		if cardless_skill == null or (cardless_cost_paid and not pending_active_skill_ids.has(cardless_response_skill_id)) or (not cardless_cost_paid and not can_activate_skill(action.actor_id, cardless_response_skill_id, (_pending_card_choice.get("context", {}) as Dictionary))):
			return _reject("无材料响应技能当前不可发动。")
		cardless_response_definition_id = cardless_skill.get_cardless_response_definition_id(response_patterns_for_skill)
		var cardless_definition: Dictionary = GameDatabase.get_card(cardless_response_definition_id)
		if cardless_response_definition_id.is_empty() or not response_patterns_for_skill.has(_get_provided_response_pattern(cardless_definition)):
			return _reject("无材料响应技能不能提供当前要求的响应牌。")
		# AI直接从选择动作发动时在此支付技能费用；界面技能按钮路径已经由activate_skill完成费用。
		if not cardless_cost_paid:
			var cardless_activation_error: String = cardless_skill.activate((_pending_card_choice.get("context", {}) as Dictionary))
			if not cardless_activation_error.is_empty():
				return _reject(cardless_activation_error)
	if confirmed and selected_target_ids.size() < min_target_select:
		return _reject("选择的目标数不足。")
	if selected_target_ids.size() > max_target_select:
		return _reject("选择的目标数超过上限。")
	if confirmed and not _is_allowed_target_combination(_pending_card_choice.get("context", {}) as Dictionary, selected_target_ids, selected_uids):
		return _reject("所选目标组合不符合当前技能要求。")
	# 已完成请求上下文；运行时确认接收后再清空窗口，避免失败响应把仍可重试的权威请求提前丢失。
	var completed_choice: Dictionary = _pending_card_choice.duplicate(true)
	# 已完成请求的基础上下文；显式响应技能随选择结果进入恢复流程，不由材料牌反向猜测。
	var completed_response_context: Dictionary = (completed_choice.get("context", {}) as Dictionary).duplicate(true)
	completed_response_context["selected_response_skill_id"] = selected_response_skill_id
	completed_response_context["selected_cardless_response_skill_id"] = cardless_response_skill_id
	completed_response_context["selected_cardless_response_definition_id"] = cardless_response_definition_id
	completed_choice["context"] = completed_response_context
	# 装备响应材料；普通选牌保持空数组，具体装备声明所需普通手牌数量与校验规则。
	var equipment_material_uids: Array[int] = []
	# 被选择装备的源码定义；非装备响应候选返回 null。
	var response_equipment_definition: CardDefinition
	if selected_uids.size() == 1:
		response_equipment_definition = _get_equipment_response_definition(completed_choice, selected_uids[0])
	if response_equipment_definition != null:
		# 已完成请求的恢复上下文；只保存实体 UID 数组，效果恢复不会持有界面状态或卡牌对象。
		# 已完成请求的恢复上下文；记录所选装备入口，使无结果的判定型装备可以回到同一手牌响应时机。
		var completed_context: Dictionary = (completed_choice.get("context", {}) as Dictionary).duplicate(true)
		completed_context["selected_response_equipment_uid"] = selected_uids[0]
		if response_equipment_definition.get_equipment_response_material_count() > 0:
			# 需要的材料数量；当前丈八蛇矛为2，后续装备可声明其他非负数量。
			var required_material_count: int = response_equipment_definition.get_equipment_response_material_count()
			equipment_material_uids = _int_array(action.payload.get("material_card_uids", []) as Array)
			if equipment_material_uids.is_empty() and ai_coordinator.is_ai_controlled(action.actor_id):
				# AI 装备响应材料；策略按卡牌文件保留价值选择最低费用牌并继续走装备源码校验。
				var ai_player: PlayerState = state.get_player(action.actor_id)
				if ai_player != null and ai_player.hand.size() >= required_material_count:
					# 全部普通手牌 UID；木牛“粮”不进入丈八蛇矛等装备材料候选。
					var candidate_material_uids: Array[int] = []
					for hand_card: CardInstance in ai_player.hand:
						candidate_material_uids.append(hand_card.uid)
					equipment_material_uids = ai_coordinator.choose_low_value_card_uids(action.actor_id, state.to_dict(action.actor_id, true), candidate_material_uids, required_material_count)
			# 装备响应材料错误；请求保持活动，玩家仍可重新选择合法材料后提交。
			var material_error: String = response_equipment_definition.validate_equipment_response_materials(self, action.actor_id, selected_uids[0], equipment_material_uids)
			if not material_error.is_empty():
				return _reject(material_error)
			completed_context["equipment_material_uids"] = equipment_material_uids.duplicate()
		completed_choice["context"] = completed_context
	# 通用运行时响应；AI、本地和网络使用完全相同的 ChoiceResponse 字段与权威候选校验。
	var runtime_response: ChoiceResponse = ChoiceResponse.new(
		int(completed_choice.get("runtime_request_id", completed_choice.get("request_id", -1))),
		int(completed_choice.get("runtime_event_id", -1)),
		action.actor_id,
		confirmed
	)
	runtime_response.card_ids = selected_uids.duplicate()
	runtime_response.target_ids = selected_target_ids.duplicate()
	runtime_response.control_id = selected_control_id
	runtime_response.client_sequence = action.client_sequence
	runtime_response.source = "ai" if ai_coordinator.is_ai_controlled(action.actor_id) else ("network" if network_gateway.mode != NetworkGateway.Mode.OFFLINE else "local")
	# 先解决选择自身 token 但延迟排空事件栈；具体效果必须应用选择结果后才能继续父 content 事件。
	if not event_scheduler.submit_choice(runtime_response, true):
		return _reject("事件运行时拒绝了已过期的选择结果。")
	# 当前请求已经被事件运行时接受；清除此前的AI提交失败计数，后续新请求使用独立请求ID重新统计。
	_ai_choice_submit_failures.erase(int(completed_choice.get("request_id", -1)))
	# 已提交的延时提示必须立刻失效，避免空窗残留阻塞出牌窗口恢复。
	_cancel_paced_response_prompt(int(completed_choice.get("request_id", -1)))
	_pending_card_choice.clear()
	state.current_phase = str(completed_choice.get("resume_phase", "play"))
	_resolved_card_choice_uids = selected_uids.duplicate()
	_resolved_target_choice_ids = selected_target_ids.duplicate()
	_resolved_control_choice_id = selected_control_id
	_resolved_equipment_material_uids = equipment_material_uids.duplicate()
	_resolved_response_skill_id = selected_response_skill_id
	state.action_sequence += 1
	# 步骤式选择不依赖人类/AI同步模式，结果始终写入所属序列的同一结果槽。
	# 先让已提交窗口退出，再派发After；新技能请求不能被旧窗口拒绝或被随后clear抹掉。
	if RuleTimingCatalog.has_timing("%sAfter" % str(completed_choice.get("choice_event_name", "chooseCard"))):
		run_rule_sequence([
			Callable(self, "_emit_completed_choice_after").bind(completed_choice, runtime_response),
			Callable(self, "_continue_completed_choice").bind(completed_choice, runtime_response, equipment_material_uids, selected_response_skill_id),
		])
	else:
		# 普通选牌没有After子窗口，必须立即应用结果；正在等待本选择的外层判定不能被误认成本选择新建的子任务。
		_continue_completed_choice(null, completed_choice, runtime_response, equipment_material_uids, selected_response_skill_id)
	if bool(completed_choice.get("deferred", false)):
		# 同一时机的后续可选技能必须等当前技能效果与其可能创建的后续选择完成后再按座次询问。
		# 所有被选择插入打断的触发、装备、规则后半段、技能与阶段统一从同一优先级管线恢复。
		_resume_settlement_pipeline()
	# 没有卡牌内容 token 的阶段级选择也必须在结果应用后完成其选择事件并恢复父事件。
	event_scheduler.drain()
	if bool(completed_choice.get("deferred", false)):
		# 新的 chooseToUse 必须等原 CardUseEvent 及其后续目标全部排空后再创建，避免后续响应覆盖已经提前发布的出牌请求快照。
		if not state.game_over and state.current_phase == "play" and not has_pending_play_interaction():
			_begin_play_choice(state.current_player_id)
		_emit_state()
		# AI 出牌被响应或技能选择暂停后，原异步驱动已经结束；统一续接入口负责下一动作或新子选择。
		_ensure_ai_progress_after_resolution()
	return true


## 派发已完成选择的After窗口；父响应结果等待该窗口及其子选择全部完成。
func _emit_completed_choice_after(sequence: RuleStepSequence, completed_choice: Dictionary, runtime_response: ChoiceResponse) -> void:
	# 选择完成时机；当前目录仅对 chooseToUse、chooseToRespond 和拼点等流程声明 After，普通选牌不会伪造不存在的事件。
	var choice_after_name: String = "%sAfter" % str(completed_choice.get("choice_event_name", "chooseCard"))
	if RuleTimingCatalog.has_timing(choice_after_name):
		sequence.wait_for_timing(_emit_rule_timing(choice_after_name, runtime_response.actor_id, runtime_response.actor_id, -1, {"confirmed":runtime_response.confirmed, "selected_card_uids":runtime_response.card_ids.duplicate(), "selected_target_ids":runtime_response.target_ids.duplicate(), "selected_control_id":runtime_response.control_id, "kind":str((completed_choice.get("context", {}) as Dictionary).get("kind", ""))}, int(completed_choice.get("runtime_event_id", -1))))


## 恢复已被权威接受的选择事实；嵌套选择不能覆盖父选择的牌、目标或装备费用槽。
func _continue_completed_choice(_sequence: RuleStepSequence, completed_choice: Dictionary, runtime_response: ChoiceResponse, equipment_material_uids: Array[int], selected_response_skill_id: String) -> void:
	_resolved_card_choice_uids = runtime_response.card_ids.duplicate()
	_resolved_target_choice_ids = runtime_response.target_ids.duplicate()
	_resolved_control_choice_id = runtime_response.control_id
	_resolved_equipment_material_uids = equipment_material_uids.duplicate()
	_resolved_response_skill_id = selected_response_skill_id
	if bool(completed_choice.get("deferred", false)) or (completed_choice.get("context", {}) as Dictionary).has("rule_sequence_id"):
		_continue_card_choice(completed_choice.get("context", {}) as Dictionary, runtime_response.card_ids, runtime_response.target_ids, runtime_response.confirmed, runtime_response.control_id)


## 校验请求上下文声明的固定合法牌组；未声明valid_card_combinations时保持全部数量合法组合可用。
func _is_allowed_card_combination(context: Dictionary, selected_uids: Array[int]) -> bool:
	if not context.has("valid_card_combinations"):
		return true
	# 提交牌组排序副本；牌组合法性不依赖玩家点击顺序，但仍禁止上层已经拦截的重复UID。
	var normalized_selected_uids: Array[int] = selected_uids.duplicate()
	normalized_selected_uids.sort()
	for combination_variant: Variant in context.get("valid_card_combinations", []) as Array:
		# 当前权威合法组合；转换整数并排序后与提交集合精确比较。
		var normalized_combination: Array[int] = _int_array(combination_variant as Array)
		normalized_combination.sort()
		if normalized_combination == normalized_selected_uids:
			return true
	return false


## 将多材料UID集合规范化为稳定组合键；排序只用于上下文查找，不改变提交数组的点击顺序。
func _make_card_combination_key(card_uids: Array[int]) -> String:
	# 排序后的UID副本；避免玩家先后点击顺序影响同一材料组合的映射命中。
	var normalized_uids: Array[int] = card_uids.duplicate()
	normalized_uids.sort()
	# 字符串键；网络序列化字典后仍保持稳定、可读且无对象引用。
	var key_parts: Array[String] = []
	for card_uid: int in normalized_uids:
		key_parts.append(str(card_uid))
	return ",".join(key_parts)


## 校验请求上下文声明的有序目标组合；材料专属组合优先于通用组合，未声明时保持全部数量合法组合可用。
func _is_allowed_target_combination(context: Dictionary, selected_target_ids: Array[int], selected_card_uids: Array[int] = []) -> bool:
	# 材料UID到完整目标组合的映射；用于同一请求内不同材料生成不同虚拟牌目标规则的技能。
	var target_combinations_by_card_id: Dictionary = context.get("target_combinations_by_card_id", {}) as Dictionary
	if not target_combinations_by_card_id.is_empty():
		# 当前组合请求只允许一张材料；缺失或多张材料都不能通过材料专属目标校验。
		if selected_card_uids.size() != 1:
			return false
		# 当前材料UID；字符串和整数键共同兼容本地与网络字典。
		var material_uid: int = selected_card_uids[0]
		# 当前材料允许的完整目标组合；缺失映射时不回退为任意目标。
		var target_combinations: Array = target_combinations_by_card_id.get(str(material_uid), target_combinations_by_card_id.get(material_uid, [])) as Array
		for combination_variant: Variant in target_combinations:
			# 当前有序目标组合；顺序必须与玩家提交严格一致。
			var combination: Array[int] = _int_array(combination_variant as Array)
			if combination == selected_target_ids:
				return true
		return false
	# 多材料UID集合到完整目标组合的映射；山倾等复合请求必须同时匹配材料集合和目标数组。
	var target_combinations_by_card_combination: Dictionary = context.get("target_combinations_by_card_combination", {}) as Dictionary
	if not target_combinations_by_card_combination.is_empty():
		if selected_card_uids.is_empty():
			return false
		# 当前材料组合对应的有序目标数组；缺失键时不得回退到通用目标候选。
		var target_combinations: Array = target_combinations_by_card_combination.get(_make_card_combination_key(selected_card_uids), []) as Array
		for combination_variant: Variant in target_combinations:
			# 当前完整目标组合；顺序保留以兼容未来多目标复合技能。
			var combination: Array[int] = _int_array(combination_variant as Array)
			if combination == selected_target_ids:
				return true
		return false
	if not context.has("valid_target_combinations"):
		return true
	for combination_variant: Variant in context.get("valid_target_combinations", []) as Array:
		# 当前目标组合；保留原顺序以支持借刀杀人的“持刀者、被杀者”位置语义。
		var combination: Array[int] = _int_array(combination_variant as Array)
		if combination == selected_target_ids:
			return true
	return false


## 根据暂停上下文恢复具体效果；各分支只调用公开规则操作，不读取任何 UI 节点。
func _continue_card_choice(context: Dictionary, selected_uids: Array[int], selected_target_ids: Array[int] = [], confirmed: bool = true, selected_control_id: String = "") -> void:
	# 步骤式内容使用自己的结果槽；仍走统一请求校验，只免去每个技能手写恢复分支。
	if context.has("rule_sequence_id"):
		# 原选择归属序列；失效或重开后没有对应对象时安全丢弃迟到结果。
		var sequence: RuleStepSequence = _rule_sequences.get(int(context.get("rule_sequence_id", -1))) as RuleStepSequence
		if sequence != null:
			sequence.choice_response = ChoiceResponse.new(-1, -1, int(context.get("choice_chooser_id", -1)), confirmed)
			sequence.choice_response.card_ids = selected_uids.duplicate()
			sequence.choice_response.target_ids = selected_target_ids.duplicate()
			sequence.choice_response.control_id = selected_control_id
		return
	# 选择用途；由创建请求的规则函数写入稳定字符串。
	var choice_kind: String = str(context.get("kind", ""))
	# 机缘组件自有选择恢复；只识别opportunity前缀上下文，避免与普通卡牌和技能选择产生硬编码关联。
	if choice_kind.begins_with("opportunity_") and opportunity_system != null:
		# 机缘选择响应；牌与目标均保留玩家提交顺序，具体效果由独立解析器继续复核。
		var opportunity_response: ChoiceResponse = ChoiceResponse.new(-1, -1, int(context.get("opportunity_owner_id", -1)), confirmed)
		opportunity_response.card_ids = selected_uids.duplicate()
		opportunity_response.target_ids = selected_target_ids.duplicate()
		opportunity_response.control_id = selected_control_id
		if opportunity_system.continue_choice(context, opportunity_response):
			return
	# 技能自有选择恢复；技能 ID 与持有者 ID 由创建请求的技能源码写入上下文。
	var skill_id: String = str(context.get("skill_id", ""))
	if not skill_id.is_empty():
		# 创建请求的技能实例；等待期间失去技能时旧选择安全失效。
		var skill_owner_id: int = int(context.get("skill_owner_id", -1))
		var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id)
		# 请求创建时的武将代次；缺失字段兼容旧回放，新请求必须与当前技能实例严格一致。
		var skill_character_generation: int = int(context.get("skill_character_generation", -1))
		if skill != null and skill.matches_character_generation(skill_character_generation) and skill.can_use_effect(bool(context.get("locked_skill_segment", false))):
			# 技能响应模式；非空时先统一消费实体牌，再把结果交回技能文件。
			var skill_response_patterns: Array[String] = _string_array(context.get("response_patterns", []) as Array)
			if not skill_response_patterns.is_empty():
				var skill_responder_id: int = int(context.get("responder_id", skill_owner_id))
				var skill_response_card: CardInstance = _consume_response_choice_with_retry(context, selected_uids, skill_responder_id, skill_response_patterns)
				if has_pending_judgment_request():
					return
				if _is_pending_response_retry(context):
					return
				if _has_nested_settlement_barrier():
					_defer_rule_continuation("skill_response", {"skill_owner_id":skill_owner_id, "skill_id":skill_id, "rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(skill_response_card)})
					return
				if skill.continue_response(context, skill_response_card):
					return
			else:
				# 技能通用选择结果；牌与目标保留玩家提交顺序，具体组合语义由技能文件继续复核。
				var skill_response: ChoiceResponse = ChoiceResponse.new(-1, -1, int(context.get("choice_chooser_id", skill_owner_id)), confirmed)
				skill_response.card_ids = selected_uids.duplicate()
				skill_response.target_ids = selected_target_ids.duplicate()
				skill_response.control_id = selected_control_id
				if skill.continue_selection(context, skill_response):
					return
	# 卡牌自有选择恢复；牌、目标和确认状态完整交回父牌源码，控制器只保留阶段与全局系统选择。
	var card_response: ChoiceResponse = ChoiceResponse.new(-1, -1, int(context.get("actor_id", context.get("source_id", -1))), confirmed)
	card_response.card_ids = selected_uids.duplicate()
	card_response.target_ids = selected_target_ids.duplicate()
	card_response.control_id = selected_control_id
	if effect_resolver.continue_selection(context, card_response):
		return
	# 濒死与无懈属于对局级响应协议，不绑定某一张处理区父牌。
	if choice_kind == "dying_response":
		_continue_dying_choice(context, selected_uids)
		return
	if choice_kind == "trick_negation":
		_continue_trick_negation_choice(context, selected_uids)
		return
	# 卡牌源码响应；响应模式由请求端口写入上下文，控制器只负责统一消费实体并交回父牌定义。
	var response_patterns: Array[String] = _string_array(context.get("response_patterns", []) as Array)
	if not response_patterns.is_empty() and int(context.get("parent_card_uid", -1)) >= 0:
		# 响应者 ID；多数牌使用 responder_id，【杀】通用上下文使用 target_id。
		var responder_id: int = int(context.get("responder_id", context.get("target_id", -1)))
		# 实际响应实体；空选择表示玩家明确放弃。
		var response_card: CardInstance = _consume_response_choice_with_retry(context, selected_uids, responder_id, response_patterns)
		if has_pending_judgment_request():
			return
		if _is_pending_response_retry(context):
			return
		if _has_nested_settlement_barrier():
			_defer_rule_continuation("card_response", {"rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(response_card)})
			return
		_continue_consumed_card_response(context, response_card)
		return
	# 无处理区父牌的装备恢复；装备定义 ID 由创建请求的卡牌源码写入上下文。
	var equipment_definition_id: String = str(context.get("equipment_definition_id", ""))
	if not equipment_definition_id.is_empty():
		# 创建请求的装备定义；只调用其公开恢复钩子，不按具体装备 ID 分支。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_definition_id)
		if equipment_definition != null:
			if choice_kind.contains("response"):
				# 响应者 ID；装备效果响应上下文统一使用 responder_id。
				var responder_id: int = int(context.get("responder_id", -1))
				# 实际响应牌；空选择表示明确放弃。
				var response_card: CardInstance = _consume_response_choice_with_retry(context, selected_uids, responder_id, _string_array(context.get("response_patterns", []) as Array))
				if has_pending_judgment_request():
					return
				if _is_pending_response_retry(context):
					return
				if _has_nested_settlement_barrier():
					_defer_rule_continuation("equipment_response", {"equipment_definition_id":equipment_definition_id, "rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(response_card)})
					return
				if equipment_definition.continue_equipment_response(self, context, response_card):
					return
			elif equipment_definition.continue_equipment_choice(self, context, selected_uids):
				return
	if choice_kind == "discard_phase":
		_continue_discard_phase_choice(context, selected_uids)
	elif choice_kind == "adjust_hand_size":
		# 调整手牌数的弃置步骤；等待期间失效的UID安全跳过，正常强制选择会完整达到目标数量。
		var adjustment_player_id: int = int(context.get("player_id", -1))
		for selected_uid: int in selected_uids:
			discard_card_from_hand(adjustment_player_id, selected_uid)
		# 创建者后续步骤进入统一技能结算队列；弃牌移动产生的触发会优先于该“然后”步骤完成。
		var completion_context: Dictionary = context.get("completion_context", {}) as Dictionary
		var completion_skill_owner_id: int = int(completion_context.get("skill_owner_id", -1))
		var completion_skill_id: String = str(completion_context.get("skill_id", ""))
		if completion_skill_owner_id >= 0 and not completion_skill_id.is_empty():
			defer_skill_settlement(completion_skill_owner_id, completion_skill_id, completion_context)
	elif choice_kind == "extra_discard_phase":
		_continue_extra_discard_phase_choice(context, selected_uids)
	elif choice_kind == "discard_target":
		_continue_target_card_choice(context, selected_uids, false)
	elif choice_kind == "steal_target":
		_continue_target_card_choice(context, selected_uids, true)


## 公开添加一条永久语义日志；UI、回放与调试器均可订阅同一信号。
func add_log(message: String) -> void:
	log_added.emit(message)


## 返回日志用角色名“武将名（X号位）”；武将未亮出或缺失时回退显示名。
func format_player_log_name(player_id: int) -> String:
	if state == null:
		return "未知角色"
	return format_player_state_log_name(state.get_player(player_id), player_id)


## 返回日志用角色名；seat 取当前 players 数组顺序（一号位起）。
func format_player_state_log_name(player: PlayerState, fallback_player_id: int = -1) -> String:
	if player == null:
		return "未知角色"
	# 座次序号；players 数组下标+1 与快照 seat_number 一致。
	var seat_number: int = fallback_player_id + 1
	if state != null:
		var seat_index: int = state.players.find(player)
		if seat_index >= 0:
			seat_number = seat_index + 1
	# 座次中文；超出映射时退回阿拉伯数字，保证日志仍可读。
	var seat_text: String = SEAT_NUMBER_CN[seat_number] if seat_number >= 1 and seat_number < SEAT_NUMBER_CN.size() else str(maxi(seat_number, 1))
	# 武将显示名；优先解析 character_id，缺失时用 display_name。
	var character_name: String = GameDatabase.resolve_character_name(player.character_id) if not player.character_id.is_empty() else ""
	if character_name.is_empty() or character_name == player.character_id:
		character_name = player.display_name if not player.display_name.is_empty() else "未知角色"
	return "%s（%s号位）" % [character_name, seat_text]


## 将目标 ID 列表格式化为“甲、乙”日志片段；空列表返回空串。
func format_target_log_names(target_ids: Array) -> String:
	# 已格式化目标名；按声明顺序去重，避免同一目标重复出现。
	var names: Array[String] = []
	for target_variant: Variant in target_ids:
		var target_id: int = int(target_variant)
		if target_id < 0:
			continue
		var target_name: String = format_player_log_name(target_id)
		if not names.has(target_name):
			names.append(target_name)
	if names.is_empty():
		return ""
	return "、".join(names)


## 返回实体牌在日志中的显示文本；含花色与点数，格式如“♠A【杀】”，虚拟牌无花色点数时仅显示【牌名】。
func format_card_log_name(card: CardInstance) -> String:
	if card == null:
		return "【未知牌】"
	# 当前卡牌定义；用于解析当前名称模式。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 牌名主体；统一包在中文方括号内，与历史日志阅读习惯一致。
	var card_name_text: String = "【%s】" % GameSettings.resolve_card_name(definition)
	# 点数字符串；11至13显示为J、Q、K，1显示为A；无点数的虚拟牌不追加点数。
	var rank_text: String = "" if card.rank <= 0 else str({1:"A", 11:"J", 12:"Q", 13:"K"}.get(card.rank, str(card.rank)))
	# 花色显示文本；仅四花色输出符号，none 或未知花色不追加前缀。
	var suit_text: String = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦"}.get(card.suit, "")
	if suit_text.is_empty() and rank_text.is_empty():
		return card_name_text
	return "%s%s%s" % [suit_text, rank_text, card_name_text]


## 返回技能在公开日志中的中文名称；未知定义不泄露内部稳定ID，以“未知技能”明确表示内容登记异常。
func format_skill_log_name(skill_id: String) -> String:
	# 技能静态元数据；正式技能均由目录扫描注册并必须提供中文name字段。
	var skill_metadata: Dictionary = GameDatabase.get_skill(skill_id)
	# 技能中文名称；空名称与未知ID使用统一可读回退，不把英文配置键显示给玩家。
	var skill_name: String = str(skill_metadata.get("name", "")).strip_edges()
	return skill_name if not skill_name.is_empty() else "未知技能"


## 返回日志中的规则原因；技能与卡牌稳定ID解析为中文显示名，普通中文原因保持原文。
func format_log_reason(reason: String) -> String:
	if reason.is_empty():
		return "规则效果"
	# 技能元数据；命中时优先按中文技能名称格式化，避免公开日志出现内部英文ID。
	var skill_metadata: Dictionary = GameDatabase.get_skill(reason)
	if not skill_metadata.is_empty():
		return "【%s】" % format_skill_log_name(reason)
	# 卡牌元数据；以卡牌ID作为原因的通用端口同样转换为当前名称模式下的牌名。
	var card_metadata: Dictionary = GameDatabase.get_card(reason)
	if not card_metadata.is_empty():
		return format_card_definition_log_name(reason)
	return reason


## 判断实体牌是否已被当前全部存活角色知晓；知识集合是唯一依据，不能仅凭进入手牌前曾经展示推断。
func is_card_known_to_all_players(card: CardInstance) -> bool:
	if card == null or state == null:
		return false
	# 当前需要知晓牌面的角色数量；没有存活角色时不把任何牌误判为全公开。
	var relevant_player_count: int = 0
	# 当前对局角色；死亡角色不再接收规则日志，全部存活角色均须位于知识集合。
	for player: PlayerState in state.players:
		if not player.alive:
			continue
		relevant_player_count += 1
		if not card.known_to.has(player.player_id):
			return false
	return relevant_player_count > 0


## 返回获得牌日志中的牌面文本；全体存活角色均已知时写出花色点数牌名，否则使用调用方提供的隐藏描述。
func format_gained_card_log_name(card: CardInstance, hidden_text: String = "一张牌") -> String:
	return format_card_log_name(card) if is_card_known_to_all_players(card) else hidden_text


## 返回定义 ID 对应的【牌名】日志文本。
func format_card_definition_log_name(definition_id: String) -> String:
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return "【%s】" % definition_id
	return "【%s】" % GameSettings.resolve_card_name(definition)


## 返回阶段中文名；未知阶段回退原字符串。
func format_phase_log_name(phase_id: String) -> String:
	return str(PHASE_LOG_NAMES.get(phase_id, phase_id))


## 写入阶段开始日志；额外出牌阶段不加技能括号。
func log_phase_begin(phase_id: String, extra_phase: bool = false) -> void:
	var phase_name: String = format_phase_log_name(phase_id)
	if phase_name.is_empty():
		return
	if extra_phase and phase_id in ["play", "phaseUse"]:
		add_log("额外出牌阶段开始。")
	else:
		add_log("%s开始。" % phase_name)


## 写入阶段结束日志。
func log_phase_end(phase_id: String, extra_phase: bool = false) -> void:
	var phase_name: String = format_phase_log_name(phase_id)
	if phase_name.is_empty():
		return
	if extra_phase and phase_id in ["play", "phaseUse"]:
		add_log("额外出牌阶段结束。")
	else:
		add_log("%s结束。" % phase_name)


## 返回适合界面显示的一张实体牌描述，名称模式由全局配置决定。
func describe_card(card: CardInstance) -> String:
	if card == null:
		return "未知牌"
	# 实体牌定义；用于解析当前名称模式。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 点数字符串；11至13显示为J、Q、K，1显示为A。
	var rank_text: String = "" if card.rank <= 0 else str({1:"A", 11:"J", 12:"Q", 13:"K"}.get(card.rank, str(card.rank)))
	# 花色显示文本；保持短文本便于日志阅读。
	var suit_text: String = {"spade":"♠", "heart":"♥", "club":"♣", "diamond":"♦", "none":"虚拟"}.get(card.suit, card.suit)
	return "%s%s %s" % [suit_text, rank_text, GameSettings.resolve_card_name(definition)]


## 为指定玩家摸若干牌；摸牌与获得牌前置窗口全部完成后才移动实体。
func draw(player_id: int, count: int, announce: bool = true, allow_out_of_game: bool = false) -> void:
	if state == null or state.game_over:
		return
	# 当前摸牌内容服务；每次调用创建独立序列，嵌套摸牌不覆盖外层计数或表现批次。
	var draw_service: RefCounted = preload("res://scripts/core/draw_resolution_service.gd").new(self)
	draw_service.draw(player_id, count, announce, allow_out_of_game)


## 回复体力并限制在体力上限内；模式或离场技可通过allow_out_of_game显式允许仍存活的离场目标。
func recover(source_id: int, target_id: int, amount: int, reason: String = "", allow_out_of_game: bool = false) -> void:
	if state == null or state.game_over:
		return
	# 独立回复内容；每次调用拥有自己的选择边界和最终事实。
	var recovery_service: RefCounted = preload("res://scripts/core/recovery_resolution_service.gd").new(self)
	recovery_service.recover(source_id, target_id, amount, reason, allow_out_of_game)


## 使指定角色获得护盾；护盾没有上限且只会在受到伤害时优先扣减，普通失去体力不会消耗护盾。
func shield(target_id: int, amount: int, source_id: int = -1, reason: String = "") -> int:
	if state == null or state.game_over:
		return 0
	# 护盾目标状态；死亡角色不能获得护盾，避免无效公开状态继续累积。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or amount <= 0:
		return 0
	# 护甲变化前时机；当前项目护盾值承载无名杀 hùjia 语义，触发器可修改本次增加量或取消。
	var before_event: RuleEvent = _emit_rule_timing("changeHujiaBefore", target_id, source_id, target_id, {"amount":amount, "old_hujia":target.shield, "reason":reason, "change_type":"gain"})
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return 0
	# 实际增加的护盾值；当前规则没有护盾上限，因此等于经过非正数校验后的请求值。
	var gained_amount: int = maxi(int(before_event.data.get("amount", amount)) if before_event != null else amount, 0)
	if gained_amount <= 0:
		return 0
	target.shield = maxi(target.shield, 0) + gained_amount
	# 护盾事件记录；保存来源、技能或卡牌原因、实际增加量和结算后的总护盾值。
	var shield_event_id: int = _record_runtime_event("ShieldEvent", "shield", {"source_id":source_id, "target_id":target_id, "requested_amount":amount, "reason":reason}, {"amount":gained_amount, "shield":target.shield})
	add_log("%s获得%d点护盾（护盾%d）。" % [format_player_state_log_name(target), gained_amount, target.shield])
	# 获得护盾后事件；技能可以读取来源、目标、实际增加量、当前护盾与效果原因。
	var event: RuleEvent = RuleEvent.new("shield_after", source_id, target_id, {"amount":gained_amount, "shield":target.shield, "reason":reason, "event_id":shield_event_id})
	_dispatch_rule_event(event)
	_emit_rule_timing("changeHujiaAfter", target_id, source_id, target_id, {"amount":gained_amount, "hujia":target.shield, "reason":reason, "change_type":"gain", "event_id":shield_event_id})
	return gained_amount


## 调整角色护甲值；正数复用 shield 获得流程，负数直接扣减且最低为0，返回实际带符号变化量。
func change_hujia(target_id: int, delta: int, source_id: int = -1, reason: String = "") -> int:
	if delta > 0:
		return shield(target_id, delta, source_id, reason)
	if state == null or state.game_over or delta == 0:
		return 0
	# 护甲目标状态；死亡角色不再接受普通规则调整。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or target.shield <= 0:
		return 0
	# 请求扣减量；对外 delta 为负数，时机中的 amount 始终使用正数便于技能修改。
	var requested_loss: int = mini(-delta, target.shield)
	var before_event: RuleEvent = _emit_rule_timing("changeHujiaBefore", target_id, source_id, target_id, {"amount":requested_loss, "old_hujia":target.shield, "reason":reason, "change_type":"lose"})
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return 0
	# 实际扣减量；触发器可减少但不能令护甲变为负数。
	var actual_loss: int = clampi(int(before_event.data.get("amount", requested_loss)) if before_event != null else requested_loss, 0, target.shield)
	target.shield -= actual_loss
	_emit_rule_timing("changeHujiaAfter", target_id, source_id, target_id, {"amount":actual_loss, "hujia":target.shield, "reason":reason, "change_type":"lose"})
	return -actual_loss


## 增加或减少角色体力上限；模式或离场技可显式允许仍存活的离场目标，返回实际带符号变化量。
## resolve_dying为false仅供已经位于dyingBegin内部的效果使用，避免同一次濒死因上限变化递归创建第二条濒死流程。
func change_max_hp(target_id: int, delta: int, source_id: int = -1, reason: String = "", allow_out_of_game: bool = false, resolve_dying: bool = true) -> int:
	if state == null or state.game_over or delta == 0:
		return 0
	# 体力上限目标；死亡角色不通过普通内容端口改变上限。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or (target.out_of_game and not allow_out_of_game):
		return 0
	# 生命周期基础名称；增加和减少分别使用独立的四段时机。
	var base_name: String = "gainMaxHp" if delta > 0 else "loseMaxHp"
	# 请求变化量；事件内使用正数，最终返回值再恢复正负号。
	var requested_amount: int = absi(delta)
	var before_event: RuleEvent = _emit_rule_timing("%sBefore" % base_name, target_id, source_id, target_id, {"amount":requested_amount, "max_hp":target.max_hp, "reason":reason})
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return 0
	var begin_event: RuleEvent = _emit_rule_timing("%sBegin" % base_name, target_id, source_id, target_id, before_event.data if before_event != null else {"amount":requested_amount, "max_hp":target.max_hp, "reason":reason})
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		return 0
	# 最终变化量；减少体力上限时至少保留1点上限。
	var actual_amount: int = maxi(int(begin_event.data.get("amount", requested_amount)) if begin_event != null else requested_amount, 0)
	if delta < 0:
		actual_amount = mini(actual_amount, maxi(target.max_hp - 1, 0))
	# 变化前体力；减少上限可能同步压低当前体力并产生 changeHp。
	var previous_hp: int = target.hp
	target.max_hp += actual_amount if delta > 0 else -actual_amount
	target.hp = mini(target.hp, target.max_hp)
	var result_data: Dictionary = {"amount":actual_amount, "max_hp":target.max_hp, "hp":target.hp, "reason":reason}
	_emit_rule_timing("%sEnd" % base_name, target_id, source_id, target_id, result_data)
	_emit_rule_timing("%sAfter" % base_name, target_id, source_id, target_id, result_data)
	if target.hp != previous_hp:
		_emit_rule_timing("changeHp", target_id, source_id, target_id, {"amount":previous_hp - target.hp, "hp":target.hp, "max_hp":target.max_hp, "reason":reason, "change_type":"max_hp_clamp"})
		if target.hp <= 0 and resolve_dying:
			_resolve_dying(target_id, -1)
	return actual_amount if delta > 0 else -actual_amount


## 增加角色的永久额外手牌上限；模式可显式允许仍存活的离场角色，当前仅接受正数累加。
func add_hand_limit_bonus(player_id: int, amount: int, reason: String = "", allow_out_of_game: bool = false) -> int:
	# 获得加成的角色；死亡、离场或非正数请求不改变状态。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or amount <= 0:
		return 0
	player.hand_limit_bonus += amount
	add_log("%s的手牌上限因%s增加%d点（额外上限%d）。" % [format_player_state_log_name(player), format_log_reason(reason), amount, player.hand_limit_bonus])
	_emit_state()
	return amount


## 增减角色的永久额外手牌上限；刷新机缘等需要撤销旧加成时使用，最终额外上限始终不低于0。
func change_hand_limit_bonus(player_id: int, delta: int, reason: String = "", allow_out_of_game: bool = false) -> int:
	# 手牌上限修正对象；死亡、未获明确离场许可的离场角色与零变化都不写入状态。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or delta == 0:
		return 0
	# 实际变化量；减少时最多减至0，避免任意来源把永久额外上限写为负数。
	var actual_delta: int = delta if delta > 0 else -mini(-delta, maxi(player.hand_limit_bonus, 0))
	if actual_delta == 0:
		return 0
	player.hand_limit_bonus += actual_delta
	# 公开日志的变化方向；数值始终显示正数，减少时用独立文字避免将负号混入本地化句式。
	var change_verb: String = "增加" if actual_delta > 0 else "减少"
	add_log("%s的手牌上限因%s%s%d点（额外上限%d）。" % [format_player_state_log_name(player), format_log_reason(reason), change_verb, absi(actual_delta), player.hand_limit_bonus])
	_emit_state()
	return actual_delta


## 交换两名角色在权威座次数组中的位置；玩家ID、身份、技能与牌区随角色整体移动，当前回合归属保持稳定ID不变。
func swap_player_seats(first_player_id: int, second_player_id: int, reason: String = "") -> bool:
	if state == null or state.game_over or first_player_id == second_player_id:
		return false
	# 第一名角色原座次索引；默认-1表示尚未找到。
	var first_index: int = -1
	# 第二名角色原座次索引；默认-1表示尚未找到。
	var second_index: int = -1
	for seat_index: int in range(state.players.size()):
		# 当前座次角色；稳定玩家ID用于定位整体角色对象。
		var seated_player: PlayerState = state.players[seat_index]
		if seated_player.player_id == first_player_id:
			first_index = seat_index
		elif seated_player.player_id == second_player_id:
			second_index = seat_index
	if first_index < 0 or second_index < 0:
		return false
	# 第一名角色对象；数组交换后对象携带的全部状态与技能归属仍由稳定ID关联。
	var first_player: PlayerState = state.players[first_index]
	# 第二名角色对象；用于日志记录交换后的新座次。
	var second_player: PlayerState = state.players[second_index]
	state.players[first_index] = second_player
	state.players[second_index] = first_player
	state.random_history.append({"kind":"seat_swap", "reason":reason, "first_player_id":first_player_id, "second_player_id":second_player_id, "first_old_seat":first_index + 1, "second_old_seat":second_index + 1})
	add_log("%s与%s交换了座位。" % [format_player_state_log_name(first_player), format_player_state_log_name(second_player)])
	_emit_state()
	return true


## 交换两名角色的武将牌资料；只交换武将ID、武将牌基础体力上限和武将固有技能，身份、当前体力来源与局内获得技能仍归原角色。
func swap_player_character_cards(first_player_id: int, second_player_id: int, reason: String = "") -> bool:
	if state == null or state.game_over or first_player_id == second_player_id:
		return false
	# 第一名交换角色；死亡、离场或未亮出武将的角色不能参与武将牌交换。
	var first_player: PlayerState = state.get_player(first_player_id)
	# 第二名交换角色；与第一名使用相同的公开状态约束。
	var second_player: PlayerState = state.get_player(second_player_id)
	if first_player == null or second_player == null or not first_player.alive or not second_player.alive or first_player.out_of_game or second_player.out_of_game or first_player.character_id.is_empty() or second_player.character_id.is_empty():
		return false
	# 双方原武将ID；用于定位应卸载的武将固有技能并写入可回放历史。
	var first_character_id: String = first_player.character_id
	var second_character_id: String = second_player.character_id
	# 双方当前体力上限；用于保留游戏过程中由身份、模式或效果产生的独立增减值。
	var first_max_hp: int = first_player.max_hp
	var second_max_hp: int = second_player.max_hp
	# 双方原武将牌基础体力上限；武将定义缺失时回退4点，避免异常数据制造非法上限。
	var first_character_base_max_hp: int = maxi(int(GameDatabase.get_character(first_character_id).get("max_hp", 4)), 1)
	var second_character_base_max_hp: int = maxi(int(GameDatabase.get_character(second_character_id).get("max_hp", 4)), 1)
	# 双方随角色保留的局内体力上限修正；正值与负值都必须在换将后继续归属于原角色。
	var first_runtime_max_hp_delta: int = first_max_hp - first_character_base_max_hp
	var second_runtime_max_hp_delta: int = second_max_hp - second_character_base_max_hp
	# 双方原武将固有技能；局内获得、临时与模式技能不在该数组中，因此不会随武将牌移动。
	var first_native_skill_ids: Array = GameDatabase.get_character(first_character_id).get("skills", []) as Array
	var second_native_skill_ids: Array = GameDatabase.get_character(second_character_id).get("skills", []) as Array
	first_player.character_id = second_character_id
	second_player.character_id = first_character_id
	# 双方都获得新的武将牌实例；旧武将已经登记的异步时机不得由交换后的同名技能继续接管。
	first_player.character_generation += 1
	second_player.character_generation += 1
	# 新上限由交换得到的武将牌基础值与原角色局内修正组成，不能直接交换当前总上限。
	first_player.max_hp = maxi(second_character_base_max_hp + first_runtime_max_hp_delta, 1)
	second_player.max_hp = maxi(first_character_base_max_hp + second_runtime_max_hp_delta, 1)
	# 当前体力不属于武将牌；仅在新体力上限更低的时候收敛到上限，避免产生当前体力高于上限的非法状态。
	var first_previous_hp: int = first_player.hp
	var second_previous_hp: int = second_player.hp
	first_player.hp = mini(first_player.hp, first_player.max_hp)
	second_player.hp = mini(second_player.hp, second_player.max_hp)
	_replace_native_character_skills(first_player, first_native_skill_ids, second_native_skill_ids)
	_replace_native_character_skills(second_player, second_native_skill_ids, first_native_skill_ids)
	if first_player.hp != first_previous_hp:
		_emit_rule_timing("changeHp", first_player_id, -1, first_player_id, {"amount":first_previous_hp - first_player.hp, "hp":first_player.hp, "max_hp":first_player.max_hp, "reason":reason, "change_type":"character_card_swap_clamp"})
	if second_player.hp != second_previous_hp:
		_emit_rule_timing("changeHp", second_player_id, -1, second_player_id, {"amount":second_previous_hp - second_player.hp, "hp":second_player.hp, "max_hp":second_player.max_hp, "reason":reason, "change_type":"character_card_swap_clamp"})
	state.random_history.append({"kind":"character_card_swap", "reason":reason, "first_player_id":first_player_id, "second_player_id":second_player_id, "first_old_character_id":first_character_id, "second_old_character_id":second_character_id, "first_old_max_hp":first_max_hp, "second_old_max_hp":second_max_hp, "first_runtime_max_hp_delta":first_runtime_max_hp_delta, "second_runtime_max_hp_delta":second_runtime_max_hp_delta})
	add_log("%s与%s交换了武将牌。" % [format_player_state_log_name(first_player), format_player_state_log_name(second_player)])
	_emit_state()
	return true


## 将一名角色的武将牌替换为指定武将；特殊武将只能通过本显式规则入口出现，身份、区域、标记及局内获得技能保持原归属。
func replace_player_character_card(player_id: int, new_character_id: String, reason: String = "", preserve_runtime_max_hp_delta: bool = true) -> bool:
	if state == null or state.game_over or new_character_id.is_empty():
		return false
	# 被替换角色；死亡、离场或尚未配置武将牌的角色不能在普通技能流程中换形态。
	var player: PlayerState = state.get_player(player_id)
	# 新武将静态定义；直接查完整数据库，因此special=true的定义只在本显式入口可用。
	var new_character_definition: Dictionary = GameDatabase.get_character(new_character_id)
	if player == null or not player.alive or player.out_of_game or player.character_id.is_empty() or new_character_definition.is_empty() or player.character_id == new_character_id:
		return false
	# 原武将定义与技能；只替换武将牌固有内容，不触碰模式、临时或局内获得来源。
	var old_character_id: String = player.character_id
	# 旧武将静态定义；提供旧基础体力上限与固有技能集合。
	var old_character_definition: Dictionary = GameDatabase.get_character(old_character_id)
	# 旧武将牌固有技能ID；换形时只卸载不再由任何来源保留的条目。
	var old_native_skill_ids: Array = old_character_definition.get("skills", []) as Array
	# 新武将牌固有技能ID；换形后以独立实例安装缺失条目。
	var new_native_skill_ids: Array = new_character_definition.get("skills", []) as Array
	# 旧武将牌基础上限；用于分离游戏过程中独立产生的体力上限修正。
	var old_base_max_hp: int = maxi(int(old_character_definition.get("max_hp", 4)), 1)
	# 新武将牌基础上限；特殊形态同样必须提供至少1点合法上限。
	var new_base_max_hp: int = maxi(int(new_character_definition.get("max_hp", 4)), 1)
	# 角色当前局内体力上限修正；preserve=false时形态直接采用新牌基础值。
	var runtime_max_hp_delta: int = player.max_hp - old_base_max_hp if preserve_runtime_max_hp_delta else 0
	# 替换前体力与上限；写入可回放历史并在新上限更低时派发体力收敛时机。
	var previous_hp: int = player.hp
	# 替换前的实际体力上限；用于记录换形历史并追溯运行时修正。
	var previous_max_hp: int = player.max_hp
	player.character_id = new_character_id
	player.character_generation += 1
	player.max_hp = maxi(new_base_max_hp + runtime_max_hp_delta, 1)
	player.hp = mini(player.hp, player.max_hp)
	_replace_native_character_skills(player, old_native_skill_ids, new_native_skill_ids)
	if player.hp != previous_hp:
		_emit_rule_timing("changeHp", player_id, -1, player_id, {"amount":previous_hp - player.hp, "hp":player.hp, "max_hp":player.max_hp, "reason":reason, "change_type":"character_card_replace_clamp"})
	state.random_history.append({"kind":"character_card_replace", "reason":reason, "player_id":player_id, "old_character_id":old_character_id, "new_character_id":new_character_id, "old_max_hp":previous_max_hp, "new_max_hp":player.max_hp, "runtime_max_hp_delta":runtime_max_hp_delta})
	add_log("%s的武将牌替换为【%s】。" % [format_player_state_log_name(player), GameDatabase.resolve_character_name(new_character_id)])
	_emit_rule_timing("changeSkillsAfter", player_id, player_id, player_id, {"change_type":"replace_character_card", "old_skill_ids":old_native_skill_ids.duplicate(), "skill_ids":new_native_skill_ids.duplicate(), "reason":reason})
	_emit_state()
	return true


## 同步设置角色整个装备区与判定区；整个装备区等价于全部五个基础装备栏，保留旧内容调用方的四参数用法。
func set_player_zones_abolished(player_id: int, equipment_abolished: bool, judgment_abolished: bool, reason: String = "", source_player_id: int = -1) -> bool:
	_ensure_player_zone_abolition_service()
	# 区域服务的实际变更结果；两个区域都已是目标状态时不发送冗余快照。
	var changed: bool = player_zone_abolition_service != null and player_zone_abolition_service.set_zones_abolished(player_id, equipment_abolished, judgment_abolished, reason, source_player_id)
	if changed:
		_emit_state()
	return changed


## 废除或恢复指定装备栏；栏位ID固定为weapon、armor、offensive_mount、defensive_mount与treasure。
func set_player_equipment_slots_abolished(player_id: int, slots: Array, abolished: bool, reason: String = "", source_player_id: int = -1) -> bool:
	_ensure_player_zone_abolition_service()
	# 弱类型输入的栏位数组；网络、回放和动态技能上下文均在公开边界收窄为字符串数组。
	var typed_slots: Array[String] = []
	for slot_variant: Variant in slots:
		typed_slots.append(str(slot_variant))
	# 单栏服务的实际变更结果；输入重复或无效栏位不产生状态快照。
	var changed: bool = player_zone_abolition_service != null and player_zone_abolition_service.set_equipment_slots_abolished(player_id, typed_slots, abolished, reason, source_player_id)
	if changed:
		_emit_state()
	return changed


## 废除或恢复指定角色的判定区；恢复只重新开放区域，不返还废除时离区的延时锦囊。
func set_player_judgment_area_abolished(player_id: int, abolished: bool, reason: String = "", source_player_id: int = -1) -> bool:
	_ensure_player_zone_abolition_service()
	# 判定区服务的实际变更结果；幂等调用不发送冗余快照。
	var changed: bool = player_zone_abolition_service != null and player_zone_abolition_service.set_judgment_area_abolished(player_id, abolished, reason, source_player_id)
	if changed:
		_emit_state()
	return changed


## 返回指定角色的某个装备栏是否已废除；只读查询可供技能、AI与测试共用。
func is_player_equipment_slot_abolished(player_id: int, slot: String) -> bool:
	# 待查询玩家；无效ID或未知栏位统一返回false。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	return player != null and player.is_equipment_slot_abolished(slot)


## 返回指定角色按标准顺序排列的已废除装备栏ID副本。
func get_player_abolished_equipment_slot_ids(player_id: int) -> Array[String]:
	# 待查询玩家；无效ID返回空强类型数组。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	return player.get_abolished_equipment_slot_ids() if player != null else []


## 确保区域废除服务绑定当前控制器；规则测试替换state后也能安全重用。
func _ensure_player_zone_abolition_service() -> void:
	if player_zone_abolition_service == null:
		player_zone_abolition_service = PlayerZoneAbolitionService.new()
	player_zone_abolition_service.configure(self)


## 仅替换一名角色的武将固有技能；对局中获得、临时和模式技能实例保持原归属与现有使用次数。
func _replace_native_character_skills(player: PlayerState, old_native_skill_ids: Array, new_native_skill_ids: Array) -> void:
	if player == null:
		return
	# 当前玩家全部已安装技能；只移除不再属于新武将且没有其他来源的旧固有技能。
	var player_skills: Dictionary = skill_instances_by_player.get(player.player_id, {}) as Dictionary
	# 模式技能ID；斗地主地主技等由身份与模式提供，不属于武将牌交换范围。
	var mode_skill_ids: Array[String] = identity_rules.get_mode_skill_ids(player.identity, str(state.match_mode))
	for old_skill_id_variant: Variant in old_native_skill_ids:
		# 旧武将固有技能ID；新武将同样拥有或仍有其他运行时来源时保留原实例。
		var old_skill_id: String = str(old_skill_id_variant)
		if new_native_skill_ids.has(old_skill_id) or mode_skill_ids.has(old_skill_id) or player.temporary_skills.has(old_skill_id) or player.acquired_skills.has(old_skill_id):
			continue
		# 待卸载旧固有技能实例；卸载会清理事件订阅与规则修正器。
		var old_skill: SkillDefinition = player_skills.get(old_skill_id) as SkillDefinition
		if old_skill != null:
			old_skill.uninstall()
		player_skills.erase(old_skill_id)
		# 旧固有轮回技的权威进度；换形后该技能不再安装，必须清除登记。
		# 否则技能脚本自身的运行时字段（例如“上次指定目标”）随实例一起销毁，而轮回节被保留，
		# 会造成轮回节停在需要旧字段的分支且永久无法发动。
		if reincarnation_skill_service != null:
			reincarnation_skill_service.clear_skill_state(player.player_id, old_skill_id)
	for new_skill_id_variant: Variant in new_native_skill_ids:
		# 新武将固有技能ID；已有其他来源实例时直接复用，避免重复订阅同一技能。
		var new_skill_id: String = str(new_skill_id_variant)
		if player_skills.has(new_skill_id):
			continue
		# 新固有技能实例；领袖技仍遵守身份限制，非领袖交换到该武将牌时不获得领袖技效果。
		var new_skill: SkillDefinition = GameDatabase.create_skill(new_skill_id)
		if new_skill == null or new_skill.leader_skill and player.identity != "leader":
			continue
		new_skill.bind(self, player.player_id)
		player_skills[new_skill_id] = new_skill
		new_skill.install()
	# 仍由新武将、模式或局内来源保留的实例继续保存自身次数，但必须重建订阅并绑定到交换后的武将代次。
	for retained_skill_variant: Variant in player_skills.values():
		# 当前保留技能实例；卸载与安装只重建订阅和修正器，不重置技能自身使用记录。
		var retained_skill: SkillDefinition = retained_skill_variant as SkillDefinition
		if retained_skill != null:
			retained_skill.uninstall()
			retained_skill.bind(self, player.player_id)
			retained_skill.install()
	skill_instances_by_player[player.player_id] = player_skills


## 复原一名角色武将牌上的全部固有技能；限定、觉醒、轮回、每回合与每出牌阶段次数均回到未发动状态。
func restore_character_card_skills(player_id: int, reason: String = "") -> bool:
	if state == null or state.game_over:
		return false
	# 待复原角色；角色不存在或尚未配置武将牌时没有可复原技能。
	var player: PlayerState = state.get_player(player_id)
	if player == null or player.character_id.is_empty():
		return false
	# 当前武将固有技能ID；模式、临时与局内获得技能不属于“武将牌上的技能”。
	var native_skill_ids: Array = GameDatabase.get_character(player.character_id).get("skills", []) as Array
	# 当前玩家全部技能实例；只替换固有技能对应键，其他来源实例和次数保持原状。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for native_skill_id_variant: Variant in native_skill_ids:
		# 当前固有技能稳定ID；用于卸载旧实例并创建全新未使用实例。
		var native_skill_id: String = str(native_skill_id_variant)
		# 原技能实例；卸载会清理持续标记、时机订阅与纯查询修正器。
		var previous_skill: SkillDefinition = player_skills.get(native_skill_id) as SkillDefinition
		if previous_skill != null:
			previous_skill.uninstall()
		# 新技能实例；新建对象自然复原各技能脚本自行保存的回合、阶段与限定状态。
		var restored_skill: SkillDefinition = GameDatabase.create_skill(native_skill_id)
		if restored_skill == null or restored_skill.leader_skill and player.identity != "leader":
			player_skills.erase(native_skill_id)
			continue
		if reincarnation_skill_service != null:
			reincarnation_skill_service.reset_skill(player_id, native_skill_id, true, false)
		restored_skill.bind(self, player_id)
		player_skills[native_skill_id] = restored_skill
		restored_skill.install()
	skill_instances_by_player[player_id] = player_skills
	# 技能变化时机只公开复原事实和稳定ID，不传递运行时技能对象。
	_emit_rule_timing("changeSkillsAfter", player_id, player_id, player_id, {"change_type":"restore_character_card_skills", "skill_ids":native_skill_ids.duplicate(), "reason":reason})
	_emit_state()
	return true


## 返回一名角色已经消耗固有额度的限定技ID；默认排除觉醒技，供“已发动的限定技”选择与公开按钮状态共用。
func get_used_limited_skill_ids(player_id: int, include_awakening_skills: bool = false) -> Array[String]:
	# 已发动限定技结果；保持技能安装顺序，使文字选项、AI与回放具有稳定顺序。
	var result: Array[String] = []
	# 当前角色技能实例；固有、模式、临时与局内获得技能都可按自身元数据参与精确查询。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_id_variant: Variant in player_skills.keys():
		# 当前技能实例；限定额度仍可用时不属于“已发动”的候选。
		var skill: SkillDefinition = player_skills.get(skill_id_variant) as SkillDefinition
		if skill == null or not skill.limited or skill.has_available_intrinsic_use():
			continue
		if skill.awakening and not include_awakening_skills:
			continue
		result.append(str(skill_id_variant))
	return result


## 复原一名角色指定限定技的一次固有发动额度；不重置其他技能、轮回进度或阶段次数，觉醒技不属于本入口候选。
func restore_limited_skill_use(player_id: int, skill_id: String, reason: String = "") -> bool:
	if state == null or state.game_over or skill_id.is_empty():
		return false
	# 待复原角色；死亡或离场角色不能在回合尾获得新的限定技发动额度。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	# 待复原技能；只接受已经消耗额度的普通限定技，拒绝普通技能、觉醒技和伪造ID。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null or not skill.limited or skill.awakening or skill.has_available_intrinsic_use():
		return false
	skill.restore_limited_use()
	# 技能变化时机；只公开单项限定额度已复原，不传递运行时对象或扩大到其他技能状态。
	_emit_rule_timing("changeSkillsAfter", player_id, player_id, player_id, {"change_type":"restore_limited_skill_use", "skill_ids":[skill_id], "reason":reason})
	add_log("%s的【%s】已复原。" % [format_player_state_log_name(player), format_skill_log_name(skill_id)])
	_emit_state()
	return true


## 复原一名角色指定技能在本出牌阶段的发动额度，使其视为本回合未发动过；【奇袭】等内容通过该端口调用。
## 与复原限定技、重置全部技能不同：本入口只改写该技能自己的阶段额度，不触碰限定次数、轮回进度、其他技能与持续效果。
## 技能没有约定阶段额度字段时返回false，调用方无需区分“无该字段”与“复原失败”，两者都表示本次没有任何额度被改写。
func reset_skill_play_phase_usage(player_id: int, skill_id: String) -> bool:
	if state == null or state.game_over or skill_id.is_empty():
		return false
	# 目标技能实例；失去技能、换将或异常ID不会改写任何其他角色的同名技能。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null or not skill.matches_character_generation() or not skill.can_use_effect():
		return false
	if not skill.reset_play_phase_usage():
		return false
	# 阶段额度属于界面按钮可用性来源；复原后必须重建公开快照，否则技能按钮仍显示为已用完。
	_emit_state()
	return true


## 将一名仍存活角色移出游戏；离场期间其不参与行动、距离、响应、普通技能与目标选择，回合自然尾部可关闭中断调度。
func remove_player_from_game(player_id: int, reason: String = "", interrupt_current_turn: bool = true) -> bool:
	if state == null or state.game_over:
		return false
	# 离场角色；死亡、未知或已经离场的角色不会重复派发移出时机。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	# 移出前时机；规则可在状态写入前取消本次离场。
	var before_event: RuleEvent = _emit_rule_timing("removeCharacterBefore", player_id, player_id, player_id, {"reason":reason, "turn_number":state.turn_number})
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return false
	player.out_of_game = true
	player.out_of_game_until_round = -1
	add_log("%s移出游戏。" % format_player_state_log_name(player))
	_emit_rule_timing("removeCharacterEnd", player_id, player_id, player_id, {"reason":reason, "turn_number":state.turn_number})
	_emit_state()
	# 当前回合角色离场后立即结束回合；阶段尾部使用独立中断入口，不伪造未进入阶段的End与After。
	if interrupt_current_turn and state.current_player_id == player_id:
		_advance_after_current_player_out_of_game(player_id)
	return true


## 令一名角色离场直到当前轮结束；下一轮roundStart之前自动返回，普通永久离场不会被该机制误恢复。
func remove_player_until_round_end(player_id: int, reason: String = "") -> bool:
	if state == null or state.game_over:
		return false
	# 机缘结算期间先完成全体机缘队列；当前回合角色的中断在机缘恢复入口统一处理，避免提前启动下一回合。
	var interrupt_current_turn: bool = state.current_phase != "opportunity"
	if not remove_player_from_game(player_id, reason, interrupt_current_turn):
		return false
	# 离场所属轮数；下一次普通新轮开始时仅恢复标记早于新轮轮数的角色。
	var player: PlayerState = state.get_player(player_id)
	player.out_of_game_until_round = state.round_number
	_emit_state()
	return true


## 令一名尚存活的离场角色返回游戏；座次、区域、体力与历史均保持离场前状态。
func restore_player_to_game(player_id: int, reason: String = "") -> bool:
	if state == null or state.game_over:
		return false
	# 返回角色；只有仍存活且确实离场的角色可以恢复。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or not player.out_of_game:
		return false
	player.out_of_game = false
	player.out_of_game_until_round = -1
	add_log("%s回到游戏。" % format_player_state_log_name(player))
	_emit_rule_timing("enterGame", player_id, player_id, player_id, {"reason":reason, "turn_number":state.turn_number})
	_emit_state()
	return true


## 在下一轮roundStart之前恢复“直到本轮结束”的离场角色；返回人数只供测试和日志校验。
func _restore_round_limited_out_of_game_players(new_round_number: int) -> int:
	# 实际返回人数；普通离场标记为-1，不参与自动恢复。
	var restored_count: int = 0
	for player: PlayerState in state.players:
		if player != null and player.alive and player.out_of_game and player.out_of_game_until_round >= 0 and player.out_of_game_until_round < new_round_number:
			if restore_player_to_game(player.player_id, "round_end"):
				restored_count += 1
	return restored_count


## 设置角色连环状态；状态确实变化时依次派发 linkBefore、linkBegin、linkEnd 和 linkAfter。
func set_player_linked(target_id: int, linked: bool, source_id: int = -1, reason: String = "") -> bool:
	if state == null or state.game_over:
		return false
	# 连环目标状态；死亡角色和无需变化的请求不会重复触发。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or target.chained == linked:
		return false
	var timing_data: Dictionary = {"old_linked":target.chained, "linked":linked, "reason":reason}
	var before_event: RuleEvent = _emit_rule_timing("linkBefore", target_id, source_id, target_id, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return false
	var begin_event: RuleEvent = _emit_rule_timing("linkBegin", target_id, source_id, target_id, before_event.data if before_event != null else timing_data)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		return false
	target.chained = linked
	# 连环效果音；被横置与解除连环使用两套不同音效，与无名杀的连环音效语义一致。
	request_effect_voice(target_id, EFFECT_LINK if linked else EFFECT_LINK_CLEAR)
	var result_data: Dictionary = {"old_linked":not linked, "linked":linked, "reason":reason}
	_emit_rule_timing("linkEnd", target_id, source_id, target_id, result_data)
	_emit_rule_timing("linkAfter", target_id, source_id, target_id, result_data)
	return true


## 切换角色连环状态；具体设置与时机顺序统一委托给 set_player_linked。
func toggle_player_linked(target_id: int, source_id: int = -1, reason: String = "") -> bool:
	# 当前目标；不存在时不能推导反向状态。
	var target: PlayerState = state.get_player(target_id) if state != null else null
	return target != null and set_player_linked(target_id, not target.chained, source_id, reason)


## 翻转角色武将牌正反面；依次派发 turnOverBefore、turnOverEnd 和 turnOverAfter，返回状态是否改变。
func turn_over_player(target_id: int, source_id: int = -1, reason: String = "") -> bool:
	if state == null or state.game_over:
		return false
	# 翻面目标状态；死亡角色不再改变公开武将牌方向。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game:
		return false
	var timing_data: Dictionary = {"old_face_down":target.face_down, "face_down":not target.face_down, "reason":reason}
	var before_event: RuleEvent = _emit_rule_timing("turnOverBefore", target_id, source_id, target_id, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return false
	target.face_down = not target.face_down
	var result_data: Dictionary = {"old_face_down":not target.face_down, "face_down":target.face_down, "reason":reason}
	_emit_rule_timing("turnOverEnd", target_id, source_id, target_id, result_data)
	_emit_rule_timing("turnOverAfter", target_id, source_id, target_id, result_data)
	return true


## 使指定角色失去体力；该流程绕过护盾、装备修正、伤害事件、伤害历史与属性连环，离场技可显式允许离场持有者结算。
func lose_hp(source_id: int, target_id: int, amount: int, reason: String = "", allow_out_of_game: bool = false) -> int:
	if state == null or state.game_over:
		return 0
	# 失去体力目标状态；死亡角色与非正数请求不会重复修改公开体力。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or (target.out_of_game and not allow_out_of_game) or amount <= 0:
		return 0
	# 无名杀式失去体力前时机；与旧 lose_hp_before 并行保留，标准技能应优先订阅驼峰事件名。
	var standard_before_event: RuleEvent = _emit_rule_timing("loseHpBefore", target_id, source_id, target_id, {"amount":amount, "reason":reason, "hp":target.hp})
	if standard_before_event != null and (standard_before_event.cancelled or standard_before_event.neutralized):
		return 0
	# 失去体力前事件；只允许失去体力类技能修改或取消，不会触发 damage_before。
	var before_event: RuleEvent = RuleEvent.new("lose_hp_before", source_id, target_id, {"amount":int(standard_before_event.data.get("amount", amount)) if standard_before_event != null else amount, "reason":reason})
	_dispatch_rule_event(before_event)
	if state.game_over or before_event.cancelled:
		return 0
	# 最终失去体力值；事件处理器可把数值调整为0以阻止本次体力减少。
	var final_amount: int = maxi(int(before_event.data.get("amount", amount)), 0)
	if final_amount == 0:
		return 0
	var begin_event: RuleEvent = _emit_rule_timing("loseHpBegin", target_id, source_id, target_id, {"amount":final_amount, "reason":reason, "hp":target.hp})
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		return 0
	final_amount = maxi(int(begin_event.data.get("amount", final_amount)) if begin_event != null else final_amount, 0)
	if final_amount == 0:
		return 0
	target.hp -= final_amount
	# 失去体力效果音；final_amount已经过两次非正数校验，此处必定大于0，无需重复判空。
	request_effect_voice(target_id, EFFECT_LOSE_HP)
	# 失去体力父事件；与伤害事件使用不同类型，回放和技能触发不会混淆两种体力减少来源。
	var lose_hp_event_id: int = _record_runtime_event("LoseHpEvent", "lose_hp", {"source_id":source_id, "target_id":target_id, "requested_amount":amount, "reason":reason}, {"amount":final_amount, "hp":target.hp})
	add_log("%s失去%d点体力（%d/%d，护盾%d）。" % [format_player_state_log_name(target), final_amount, target.hp, target.max_hp, target.shield])
	# 失去体力后事件；与 damage_after 完全独立，受到伤害和造成伤害技能不会收到本事件。
	var after_event: RuleEvent = RuleEvent.new("lose_hp_after", source_id, target_id, {"amount":final_amount, "hp":target.hp, "shield":target.shield, "reason":reason, "event_id":lose_hp_event_id})
	_dispatch_rule_event(after_event)
	# 标准失去体力结束与完成时机；二者都发生在实际扣减后、进入濒死前。
	var result_data: Dictionary = {"amount":final_amount, "hp":target.hp, "shield":target.shield, "reason":reason, "event_id":lose_hp_event_id, "change_type":"lose_hp"}
	_emit_rule_timing("changeHp", target_id, source_id, target_id, result_data)
	_emit_rule_timing("loseHpEnd", target_id, source_id, target_id, result_data)
	_emit_rule_timing("loseHpAfter", target_id, source_id, target_id, result_data)
	if state.game_over:
		return final_amount
	# 通用体力减少事件；失去体力与实际扣减体力的伤害都通过本事件提供统一观察入口。
	_dispatch_rule_event(RuleEvent.new("hp_reduced", source_id, target_id, {"amount":final_amount, "hp":target.hp, "reduction_type":"lose_hp", "reason":reason, "event_id":lose_hp_event_id}))
	if state.game_over:
		return final_amount
	if target.hp <= 0:
		# 失去体力不属于伤害，来源角色不会被登记为击杀者，也不会获得伤害击杀奖惩。
		_resolve_dying(target_id, -1)
	return final_amount


## 解析牌效结算期间的有效来源角色ID；使用者仍存活时返回其稳定player_id，已经阵亡时返回-1表示无来源。
## 设计意图：牌的使用事实在声明使用时已经成立，使用者在结算中途阵亡不应撤销整张牌，
## 而是让后续伤害按“无来源”结算；需要使用者本人继续选牌或指定的牌由卡牌定义另行声明为整体失效。
## 使用场景：卡牌源码在派发以使用者为来源的时机与伤害前调用，界面与测试可读取同一判定结果。
func resolve_card_effect_source_id(actor_id: int) -> int:
	# 使用者状态；不存在的座次同样视为没有可用来源。
	var actor: PlayerState = state.get_player(actor_id) if state != null and actor_id >= 0 else null
	if actor == null or not actor.alive:
		return -1
	return actor_id


## 返回指定牌的使用者是否仍可作为本牌的来源继续结算；阵亡后依赖使用者的牌必须整体失效。
func is_card_effect_actor_available(actor_id: int) -> bool:
	return resolve_card_effect_source_id(actor_id) >= 0


## 返回指定卡牌是否声明“结算中必须由使用者本人选牌或指定”；控制器据此判断使用者阵亡后整张牌是否失效。
func requires_card_effect_actor(card_definition_id: String) -> bool:
	# 当前卡牌源码定义；未注册或已失效的定义不声明任何依赖。
	var definition: CardDefinition = GameDatabase.get_card_definition(card_definition_id)
	return definition != null and definition.requires_actor_choice()


## 造成伤害并执行防具修正、濒死、死亡及属性连环传导。
func damage(source_id: int, target_id: int, amount: int, nature: String = "normal", card_id: String = "", chain_transfer: bool = false, ignore_armor: bool = false, source_context: Dictionary = {}) -> void:
	if state == null or state.game_over:
		return
	# 受伤目标状态；死亡或无效目标不重复结算。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or amount <= 0:
		return
	# 受伤武将入场代次；伤害异步等待期间即使同一座次换上新武将，尾部也只属于本次受伤的旧武将。
	var target_character_generation: int = target.character_generation
	# 造成伤害的牌实际使用者；默认等于伤害来源，决斗等“原使用者与最终伤害来源不同”的牌效必须通过source_context显式覆盖。
	# 必须在来源降级之前读取：牌的使用事实在声明使用时即已成立，来源死亡只取消伤害归属，不改变“谁使用了这张牌”。
	var card_user_id: int = int(source_context.get("card_user_id", source_id))
	# 伤害来源角色；无来源伤害保持空值，不伪造来源武将代次。
	var damage_source_player: PlayerState = state.get_player(source_id) if source_id >= 0 else null
	# 来源死亡降级；伤害来源角色已经阵亡时本次伤害改为无来源，来源ID统一取-1。
	# 设计意图：使用牌在声明时已经成立，来源在结算中途死亡不撤销牌效，只让本段伤害不再归属任何角色，
	# 因此既不计入死者的累计造成伤害与击杀统计，也不会触发“你造成伤害后”这类以来源身份为前提的技能。
	if damage_source_player != null and not damage_source_player.alive:
		source_id = -1
		damage_source_player = null
	# 来源武将入场代次；-1表示无角色来源，来源技能只能响应与本代次一致的伤害尾部。
	var source_character_generation: int = damage_source_player.character_generation if damage_source_player != null else -1
	# 最终伤害值；先应用武器增伤，再应用防具修正与事件处理器。
	var final_amount: int = amount
	# 造成伤害加成机缘；机缘历史是唯一来源，过关斩将与普通机缘模式都通过同一查询生效。
	final_amount += get_acquired_opportunity_effect_total(source_id, "damage_bonus")
	# 伤害父事件；多级 Begin、扣血、濒死和来源事件均通过该 ID 建立可回放关系。
	var damage_event_id: int = _record_runtime_event("DamageEvent", "damage", {"source_id":source_id, "target_id":target_id, "source_character_generation":source_character_generation, "target_character_generation":target_character_generation, "amount":amount, "nature":nature, "card_id":card_id, "card_user_id":card_user_id, "chain_transfer":chain_transfer})
	# 伤害生命周期共享数据；四个修改窗口逐次读取上一时机写回的 amount，保证数值修改链可预测。
	var timing_data: Dictionary = {"amount":final_amount, "nature":nature, "card_id":card_id, "card_user_id":card_user_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id, "source_character_generation":source_character_generation, "target_character_generation":target_character_generation}
	for source_context_key_variant: Variant in source_context.keys():
		# 来源牌上下文字段；父牌UID、逻辑目标数等稳定数据需要贯穿全部伤害修改窗口，但不得覆盖核心伤害字段。
		var source_context_key: String = str(source_context_key_variant)
		if not timing_data.has(source_context_key):
			timing_data[source_context_key] = source_context[source_context_key_variant]
	# 伤害编排组件；独立窗口步骤使用已有规则续接栈，调用方仍通过同一damage入口。
	var damage_resolution: DamageResolutionService = DamageResolutionService.new(self)
	damage_resolution.resolve({
		"source_id":source_id, "target_id":target_id,
		"source_character_generation":source_character_generation, "target_character_generation":target_character_generation,
		"amount":final_amount, "nature":nature, "card_id":card_id, "card_user_id":card_user_id,
		"chain_transfer":chain_transfer, "ignore_armor":ignore_armor, "damage_event_id":damage_event_id,
		"timing_data":timing_data, "source_context":source_context.duplicate(true),
	})


## 原子写入已通过全部修改窗口的伤害；本函数不派发可暂停时机，不承担选择或阶段推进。
func _commit_prepared_damage(context: Dictionary) -> Dictionary:
	# 已确认伤害上下文中的source_id；恢复仅按稳定值定位，不重复执行前置窗口。
	var source_id: int = int(context.get("source_id", -1))
	# 已确认伤害上下文中的target_id；恢复仅按稳定值定位，不重复执行前置窗口。
	var target_id: int = int(context.get("target_id", -1))
	# 已确认伤害上下文中的source_character_generation；恢复仅按稳定值定位，不重复执行前置窗口。
	var source_character_generation: int = int(context.get("source_character_generation", -1))
	# 已确认伤害上下文中的target_character_generation；恢复仅按稳定值定位，不重复执行前置窗口。
	var target_character_generation: int = int(context.get("target_character_generation", -1))
	# 已确认伤害上下文中的nature；恢复仅按稳定值定位，不重复执行前置窗口。
	var nature: String = str(context.get("nature", "normal"))
	# 已确认伤害上下文中的card_id；恢复仅按稳定值定位，不重复执行前置窗口。
	var card_id: String = str(context.get("card_id", ""))
	# 已确认伤害上下文中的card_user_id；恢复仅按稳定值定位，不重复执行前置窗口。
	var card_user_id: int = int(context.get("card_user_id", -1))
	# 已确认伤害上下文中的chain_transfer；恢复仅按稳定值定位，不重复执行前置窗口。
	var chain_transfer: bool = bool(context.get("chain_transfer", false))
	# 已确认伤害上下文中的damage_event_id；恢复仅按稳定值定位，不重复执行前置窗口。
	var damage_event_id: int = int(context.get("damage_event_id", -1))
	# 来源牌扩展上下文；保留父牌、实际使用者和逐目标规则参数。
	var source_context: Dictionary = context.get("source_context", {}) as Dictionary
	# 本次最终伤害值；已经通过全部可暂停修改窗口，负值仍按0处理。
	var final_amount: int = maxi(int(context.get("amount", 0)), 0)
	# 提交时目标；目标代次由编排组件在本函数前复核。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		return {}
	if final_amount == 0:
		# 零伤害事实；不扣盾、扣血或增加受伤次数，但仍保留标准零伤害尾部。
		var zero_data: Dictionary = context.duplicate(true)
		zero_data.merge({"amount":0, "shield_absorbed":0, "hp_lost":0, "hp":target.hp, "max_hp":target.max_hp, "shield":target.shield, "chain_targets":[]}, true)
		return zero_data

	# 伤害发生前是否处于连环状态；属性伤害需要基于该状态决定传导。
	var should_chain: bool = nature != "normal" and target.chained and not chain_transfer
	# 需要接收传导的其他横置角色；在原目标结算前建立快照。
	var chain_targets: Array[int] = []
	if should_chain:
		# 连环传导顺序；多角色结算从当前回合角色起按存活座次建立目标快照。
		var chain_order: Array[PlayerState] = _get_alive_players_in_action_order(state.current_player_id)
		for player: PlayerState in chain_order:
			if player.alive and not player.out_of_game and player.chained and player.player_id != target_id:
				chain_targets.append(player.player_id)

	# 伤害结算前护盾值；异步等待后的当前值，不能覆盖期间合法增减。
	var shield_before_damage: int = maxi(target.shield, 0)
	# 本次由护盾吸收的伤害值；最多吸收到最终伤害值，护盾不会变成负数。
	var shield_absorbed: int = clampi(int(context.get("shield_absorbed", 0)), 0, mini(shield_before_damage, final_amount))
	# 本次实际扣减的体力值；伤害剩余量为0时仍属于一次有效伤害并触发 damage_after。
	var hp_lost: int = final_amount - shield_absorbed
	target.shield = shield_before_damage - shield_absorbed
	target.hp -= hp_lost
	_record_runtime_event("damage", "damage", {"source_id":source_id, "target_id":target_id, "nature":nature}, {"amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "shield":target.shield, "hp":target.hp}, damage_event_id)
	# 终局累计受伤值；护盾抵消的部分仍是有效伤害，和现有damage_taken_count的受伤语义保持一致。
	target.total_damage_received += final_amount
	target.damage_taken_count += 1
	target.damage_history.append({"event_id":damage_event_id, "source_id":source_id, "target_id":target_id, "amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "nature":nature})
	# 伤害来源；无来源伤害不累计任何角色的造成伤害统计。
	var source_player: PlayerState = state.get_player(source_id)
	# 终局累计造成伤害值；自伤仍属于来源角色造成的伤害，故不与目标是否相同绑定。
	if source_player != null:
		source_player.total_damage_dealt += final_amount
	if source_player != null and source_player != target:
		source_player.damage_history.append({"event_id":damage_event_id, "source_id":source_id, "target_id":target_id, "amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "nature":nature})
	if target.chained and nature != "normal":
		target.chained = false
	# 受伤效果音；护盾实际吸收伤害时使用护甲音效，否则使用体力音效，并已按属性与伤害点数选好变体。
	request_effect_voice(target_id, _resolve_damage_effect_id(nature, final_amount, shield_absorbed))
	if shield_absorbed > 0:
		add_log("%s受到%d点%s伤害，护盾抵消%d点（%d/%d，护盾%d）。" % [format_player_state_log_name(target), final_amount, _nature_text(nature), shield_absorbed, target.hp, target.max_hp, target.shield])
	else:
		add_log("%s受到%d点%s伤害（%d/%d）。" % [format_player_state_log_name(target), final_amount, _nature_text(nature), target.hp, target.max_hp])
	# 伤害实际成立时机；发生在护甲和体力扣减后、旧 damage_after 与濒死流程前。
	var damage_result_data: Dictionary = {"amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "shield":target.shield, "hp":target.hp, "nature":nature, "card_id":card_id, "card_user_id":card_user_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id, "source_character_generation":source_character_generation, "target_character_generation":target_character_generation}
	for context_key_variant: Variant in source_context.keys():
		# 来源上下文字段名；只补充【杀】父牌与目标流程数据，不覆盖伤害核心最终值。
		var context_key: String = str(context_key_variant)
		if not damage_result_data.has(context_key):
			damage_result_data[context_key] = source_context[context_key_variant]
	# 已提交伤害结果；当前伤害序列持有后续时机、濒死和尾部，不额外写入恢复阶段标记。
	damage_result_data["chain_targets"] = chain_targets.duplicate()
	damage_result_data["source_context"] = source_context.duplicate(true)
	damage_result_data["source_id"] = source_id
	damage_result_data["target_id"] = target_id
	damage_result_data["max_hp"] = target.max_hp
	return damage_result_data


## 消耗一张符合响应模式的牌；八卦阵与丈八蛇矛的转化也通过该入口处理。
func consume_response(player_id: int, response_pattern: String) -> bool:
	# 统一响应上下文；旧规则调用方仍可使用布尔接口，但实际选择先通过询问组件完成。
	var context: Dictionary = {"kind":"generic_response", "responder_id":player_id, "response_pattern":response_pattern}
	return request_response_card(player_id, response_pattern, "请选择是否响应%s。" % response_pattern, context) != null


## 向指定角色询问是否打出一张响应牌；玩家与 AI 共用选择请求和 choose_cards 提交入口。
func request_response_card(player_id: int, response_pattern: String, prompt: String, context: Dictionary) -> CardInstance:
	return request_response_card_patterns(player_id, [response_pattern], prompt, context)


## 向指定角色同时询问多种响应牌；候选共享同一个时机和窗口，所选实体牌仍按自身响应模式校验并消耗。
func request_response_card_patterns(player_id: int, response_patterns: Array[String], prompt: String, context: Dictionary) -> CardInstance:
	# 响应者状态；死亡或无效角色不能创建响应窗口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return null
	# 直击目标不创建空响应窗口；【掠袭】等效果写入父牌直击集合后，目标不能用任何响应牌或响应技能。
	if is_response_blocked_by_direct_hit(player_id, context):
		return null
	# 去重后的合法响应模式；空数组不能创建没有明确规则语义的响应请求。
	var allowed_patterns: Array[String] = []
	for response_pattern: String in response_patterns:
		if not response_pattern.is_empty() and not allowed_patterns.has(response_pattern):
			allowed_patterns.append(response_pattern)
	if allowed_patterns.is_empty():
		return null
	# 同一响应时机已经失败的装备入口；判定型装备失败后不会在重开窗口中再次出现，其他手牌与装备仍正常保留。
	var excluded_response_candidate_uids: Array[int] = _int_array(context.get("excluded_response_candidate_uids", []) as Array)
	# 完整响应上下文；恢复回调使用同一模式集合校验实体牌，不能由客户端自行声明所选牌的响应类型。
	var response_context: Dictionary = context.duplicate(true)
	# 本次结算整体停用的装备槽位；【杀】宣布无视防具后，目标防具提供的响应入口（如八卦阵）在本次响应的每次重试中都不得出现。
	response_context["ignored_response_equipment_slots"] = _get_ignored_equipment_response_slots(response_context)
	# 需要优先独立询问的装备候选；同一时机只取装备区稳定遍历顺序中的首个入口，取消或失败后通过排除集合继续寻找下一项。
	var immediate_equipment_candidate: Dictionary = _get_immediate_equipment_response_candidate(player, allowed_patterns, excluded_response_candidate_uids, _read_ignored_equipment_slots(response_context))
	# 可响应候选；手牌与木牛“粮”都按实际 UID 提供给本人，规则定义决定是否匹配响应模式。
	var candidates: Array[Dictionary] = []
	if not immediate_equipment_candidate.is_empty():
		candidates.append(immediate_equipment_candidate)
	else:
		candidates = _build_response_choice_candidates(player, allowed_patterns, excluded_response_candidate_uids, _read_ignored_equipment_slots(response_context))
	response_context["responder_id"] = player_id
	response_context["response_patterns"] = allowed_patterns.duplicate()
	response_context["response_prompt"] = prompt
	# 父牌当前直接响应数；AI可据此评估【制动】在决斗或强制命中后的累计增伤风险，客户端不能修改权威计数。
	var response_parent_card_uid: int = int(response_context.get("parent_card_uid", -1))
	if response_parent_card_uid >= 0:
		response_context["direct_response_count"] = get_card_direct_response_count(response_parent_card_uid)
	# 独立装备入口 UID；恢复时取消也会把该入口加入排除集合并重新打开原普通响应窗口。
	if not immediate_equipment_candidate.is_empty():
		response_context["immediate_response_equipment_uid"] = int(immediate_equipment_candidate.get("uid", -1))
	# 当前候选需要显式点击的转化技能；该列表由实体候选反向汇总，确保任何合法视为牌在本次响应窗口都有可用技能入口。
	var response_conversion_skill_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		# 候选声明的转化技能；普通实体响应牌保持空字符串，不会额外点亮技能按钮。
		var response_skill_id: String = str(candidate.get("required_response_skill_id", ""))
		if not response_skill_id.is_empty() and not response_conversion_skill_ids.has(response_skill_id):
			response_conversion_skill_ids.append(response_skill_id)
	response_context["response_conversion_skill_ids"] = response_conversion_skill_ids
	# 响应允许主动不出牌；即使候选为空也创建请求，保证 AI 与真实玩家经历相同问询。
	# 当前窗口标题与提示；独立装备询问使用装备名称和自身提示，普通窗口保持原响应语义。
	var request_title: String = str(immediate_equipment_candidate.get("response_title", "响应询问"))
	# 当前窗口说明；独立装备提示由卡牌源码提供，避免控制器硬编码具体装备名。
	var request_prompt: String = str(immediate_equipment_candidate.get("response_prompt", prompt))
	var selected_uids: Array[int] = request_card_choice(player_id, request_title, request_prompt, candidates, 0, 1, true, response_context)
	if has_pending_card_choice() or selected_uids.is_empty():
		return null
	# 同步响应结果；无等待的测试和AI路径也必须与异步提交统一累计父牌的直接响应数。
	var resolved_response_card: CardInstance = _consume_response_card_uid_patterns(player_id, selected_uids[0], allowed_patterns, _resolved_equipment_material_uids, _resolved_response_skill_id, response_context)
	if resolved_response_card != null:
		_record_direct_response_from_context(response_context)
	return resolved_response_card


## 返回当前响应上下文需要整体停用的装备槽位；【杀】结算宣布无视防具时，目标防具提供的响应入口必须失效。
func _get_ignored_equipment_response_slots(context: Dictionary) -> Array[String]:
	# 无视防具结论；由发起本次响应的卡牌源码写入共享结算上下文，控制器只读取该只读语义标记。
	if not bool(context.get("ignore_armor", false)):
		return []
	# 被停用的装备槽位；返回副本，调用方不能修改全局槽位声明。
	return ARMOR_EQUIPMENT_SLOTS.duplicate()


## 从响应上下文读取需要整体停用的装备槽位；缺失或格式异常时返回空数组，保持原有全部候选。
func _read_ignored_equipment_slots(response_context: Dictionary) -> Array[String]:
	return _string_array(response_context.get("ignored_response_equipment_slots", []) as Array)


## 返回装备实体当前所在的装备槽名；不在任何槽位时返回空字符串。
func _find_equipment_slot_for_card(player: PlayerState, equipment_card: CardInstance) -> String:
	if player == null or equipment_card == null:
		return ""
	for equipment_slot_variant: Variant in player.equipment.keys():
		# 当前槽位名与其实体；比较只依赖实体身份与稳定槽位名，不使用具体装备定义ID白名单。
		var equipment_slot: String = str(equipment_slot_variant)
		if player.equipment[equipment_slot] == equipment_card:
			return equipment_slot
	return ""


## 返回当前响应时机最先需要独立询问的装备候选；普通装备继续留在统一响应候选窗口中。
func _get_immediate_equipment_response_candidate(player: PlayerState, allowed_patterns: Array[String], excluded_card_uids: Array[int], ignored_equipment_slots: Array[String] = []) -> Dictionary:
	# 默认空候选；无存活角色、无装备或装备不支持当前模式时保持普通响应流程。
	var result: Dictionary = {}
	if player == null or not player.alive or player.out_of_game:
		return result
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；同一响应时机已取消或判定失败的入口不能再次询问。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card == null or excluded_card_uids.has(equipment_card.uid):
			continue
		# 当前装备所在槽位；被本次结算整体停用的槽位不建立独立询问。
		if ignored_equipment_slots.has(_find_equipment_slot_for_card(player, equipment_card)):
			continue
		# 当前装备源码；只有同时支持本响应模式并声明优先询问时才建立独立窗口。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition == null or not equipment_definition.can_offer_equipment_response(self, player.player_id, allowed_patterns) or not equipment_definition.uses_immediate_equipment_response_prompt():
			continue
		result = _serialize_choice_candidate(equipment_card, player.player_id, "equipment", true, str(GameDatabase.get_card(equipment_card.definition_id).get("slot", "")))
		result["response_title"] = GameSettings.resolve_card_name(equipment_definition.get_metadata())
		result["response_prompt"] = equipment_definition.get_immediate_equipment_response_prompt()
		return result
	return result


## 构造指定玩家在同一响应模式集合下的私有候选；普通逐人响应与无懈同时响应共用此入口。
func _build_response_choice_candidates(player: PlayerState, allowed_patterns: Array[String], excluded_card_uids: Array[int] = [], ignored_equipment_slots: Array[String] = []) -> Array[Dictionary]:
	# 可序列化候选结果；只包含响应者本人可见的实体牌与公开装备入口。
	var candidates: Array[Dictionary] = []
	if player == null or not player.alive or player.out_of_game:
		return candidates
	for card: CardInstance in player.get_playable_cards():
		if excluded_card_uids.has(card.uid):
			continue
		# 当前候选定义；普通杀与属性杀可共享 sha 响应模式。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		# 实体牌是否可直接响应；可直接响应时不要求额外点击转化技能。
		var provides_direct_response: bool = allowed_patterns.has(_get_provided_response_pattern(definition))
		# 响应转化技能ID；只有实体牌无法直接响应时才作为显式技能材料加入。
		var response_skill_id: String = "" if provides_direct_response else _get_response_conversion_skill_id(player.player_id, card, allowed_patterns)
		if provides_direct_response or not response_skill_id.is_empty():
			# 当前序列化候选；技能材料附带显式要求，客户端在点击技能前不会开放选择。
			var candidate: Dictionary = _serialize_choice_candidate(card, player.player_id, card.zone, true)
			if not response_skill_id.is_empty():
				candidate["required_response_skill_id"] = response_skill_id
			candidates.append(candidate)
	# 装备响应候选；每件装备源码自行判断响应模式和材料条件。
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；候选只作为发动入口，不会离开装备区。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if excluded_card_uids.has(equipment_card.uid):
			continue
		# 当前装备所在槽位；被本次结算整体停用的槽位不进入候选，避免无视防具时仍能发动防具响应。
		if ignored_equipment_slots.has(_find_equipment_slot_for_card(player, equipment_card)):
			continue
		# 当前装备定义；定义钩子返回 true 时加入同一响应窗口。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		# 装备自身是否提供响应入口；提供时不应再要求武将转化技能。
		var provides_equipment_response: bool = equipment_definition != null and equipment_definition.can_offer_equipment_response(self, player.player_id, allowed_patterns)
		# 装备牌作为武将技能材料时同样必须显式点击技能。
		var response_skill_id: String = "" if provides_equipment_response else _get_response_conversion_skill_id(player.player_id, equipment_card, allowed_patterns)
		if provides_equipment_response or not response_skill_id.is_empty():
			# 当前装备候选；保留槽位并附加可选转化技能ID。
			var candidate: Dictionary = _serialize_choice_candidate(equipment_card, player.player_id, "equipment", true, str(GameDatabase.get_card(equipment_card.definition_id).get("slot", "")))
			if not response_skill_id.is_empty():
				candidate["required_response_skill_id"] = response_skill_id
			candidates.append(candidate)
	return candidates


## 消费响应选择；判定型装备未生成响应牌时，在同一上下文中排除该装备并重新开放其余合法候选。
func _consume_response_choice_with_retry(context: Dictionary, selected_uids: Array[int], responder_id: int, response_patterns: Array[String]) -> CardInstance:
	# 无材料技能响应已经在选择提交阶段完成费用校验；此处只建立标准响应生命周期与虚拟响应牌代理。
	var cardless_skill_id: String = str(context.get("selected_cardless_response_skill_id", ""))
	var cardless_definition_id: String = str(context.get("selected_cardless_response_definition_id", ""))
	if not cardless_skill_id.is_empty() and not cardless_definition_id.is_empty():
		# 无材料响应结果；成功生成虚拟响应牌后与实体牌一致累计一次直接响应。
		var cardless_response: CardInstance = _consume_cardless_skill_response(responder_id, cardless_skill_id, cardless_definition_id, response_patterns, context)
		if cardless_response != null:
			_record_direct_response_from_context(context)
		return cardless_response
	if selected_uids.is_empty():
		# 独立装备询问被取消；本次只放弃该装备入口，随后立即恢复原手牌、技能与其他装备响应窗口。
		var declined_immediate_equipment_uid: int = int(context.get("immediate_response_equipment_uid", -1))
		if declined_immediate_equipment_uid >= 0:
			return _retry_response_after_equipment_attempt(context, responder_id, response_patterns, declined_immediate_equipment_uid)
		return null
	# 当前响应结果；普通实体牌与成功的虚拟装备响应会直接返回，不创建第二次询问。
	var response_card: CardInstance = _consume_response_card_uid_patterns(responder_id, selected_uids[0], response_patterns, _int_array(context.get("equipment_material_uids", []) as Array), str(context.get("selected_response_skill_id", "")), context)
	if response_card != null:
		_record_direct_response_from_context(context)
		return response_card
	# 判定型装备已经建立异步判定时，由装备的 continue_judgment 恢复原响应；此处不能把尚未完成的判定误判为失败并提前重开手牌窗口。
	if has_pending_judgment_request():
		return null
	# 本次失败的装备入口 UID；只有权威提交阶段明确识别为装备候选时才允许重开响应。
	var failed_equipment_uid: int = int(context.get("selected_response_equipment_uid", -1))
	if failed_equipment_uid < 0 or failed_equipment_uid != selected_uids[0]:
		return null
	return _retry_response_after_equipment_attempt(context, responder_id, response_patterns, failed_equipment_uid)


## 在独立装备被取消或判定型装备失败后重开同一响应时机，并永久排除本次已经处理的装备 UID。
func _retry_response_after_equipment_attempt(context: Dictionary, responder_id: int, response_patterns: Array[String], equipment_uid: int) -> CardInstance:
	# 重试上下文；移除上一次选择标记，并把已处理装备加入本响应时机的排除集合。
	var retry_context: Dictionary = context.duplicate(true)
	retry_context.erase("selected_response_equipment_uid")
	retry_context.erase("immediate_response_equipment_uid")
	retry_context.erase("equipment_material_uids")
	# 已排除装备 UID；数组会跨多次判定型装备失败累积，但只作用于当前响应上下文。
	var excluded_response_candidate_uids: Array[int] = _int_array(retry_context.get("excluded_response_candidate_uids", []) as Array)
	if not excluded_response_candidate_uids.has(equipment_uid):
		excluded_response_candidate_uids.append(equipment_uid)
	retry_context["excluded_response_candidate_uids"] = excluded_response_candidate_uids
	# 原响应提示；上下文缺失时使用稳定通用文本，不把具体牌名硬编码进控制器。
	var response_prompt: String = str(context.get("response_prompt", "请选择是否响应。"))
	return request_response_card_patterns(responder_id, response_patterns, response_prompt, retry_context)


## 执行一次已经支付费用的无材料技能响应；按动作类别派发 useCard 或 respond 时机并返回虚拟牌代理供父效果读取。
func _consume_cardless_skill_response(player_id: int, skill_id: String, definition_id: String, response_patterns: Array[String], response_context: Dictionary = {}) -> CardInstance:
	# 响应者与技能实例；离场、死亡或等待期间失去技能都会令旧响应失效。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if player == null or not player.alive or player.out_of_game or skill == null or not skill.can_use_effect():
		return null
	# 虚拟响应定义与模式；必须同时匹配技能当前返回值和父请求允许的牌型。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	var response_pattern: String = _get_provided_response_pattern(definition)
	if definition.is_empty() or not response_patterns.has(response_pattern) or skill.get_cardless_response_definition_id(response_patterns) != definition_id:
		return null
	# 无材料响应采用的卡牌动作类别；与实体响应牌读取同一套声明，确保日志、时机与语音一致。
	var response_action: String = resolve_response_action(response_context, response_patterns)
	var timing_data: Dictionary = {"card_uid":-1, "card_id":definition_id, "response_pattern":response_pattern, "response_action":response_action, "skill_id":skill_id, "virtual":true, "cardless":true}
	var respond_before_event: RuleEvent = _emit_rule_timing("respondBefore", player_id, player_id, -1, timing_data)
	if respond_before_event != null and (respond_before_event.cancelled or respond_before_event.neutralized):
		return null
	var respond_begin_event: RuleEvent = _emit_rule_timing("respondBegin", player_id, player_id, -1, respond_before_event.data if respond_before_event != null else timing_data)
	if respond_begin_event != null and (respond_begin_event.cancelled or respond_begin_event.neutralized):
		return null
	# 无材料响应父事件；material_card_uids为空明确表达技能只支付了自身规则费用。
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "skill_id":skill_id, "material_card_uids":[], "response_action":response_action}, {"responded":true, "virtual":true, "cardless":true, "card_id":definition_id, "response_action":response_action})
	timing_data["respond_event_id"] = respond_event_id
	# 主体时机按动作类别分派；无材料技能响应同样区分“使用”与“打出”。
	_emit_rule_timing(_get_card_action_main_timing(response_action), player_id, player_id, -1, timing_data, respond_event_id)
	player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":-1, "material_card_uids":[], "skill_id":skill_id, "virtual_card_id":definition_id, "response_action":response_action})
	skill.on_cardless_response_consumed(response_pattern, definition_id)
	skill.announce_activation({"response_pattern":response_pattern, "virtual_card_id":definition_id})
	add_log("%s通过【%s】视为%s%s。" % [player.display_name, format_skill_log_name(skill_id), _get_card_action_verb(response_action), GameSettings.resolve_card_name(definition)])
	# 尾部时机与实体响应牌保持同一分派规则。
	if response_action == CARD_ACTION_USE:
		_emit_rule_timing("useCardAfter", player_id, player_id, -1, timing_data, respond_event_id)
	else:
		_emit_rule_timing("respondEnd", player_id, player_id, -1, timing_data, respond_event_id)
		_emit_rule_timing("respondAfter", player_id, player_id, -1, timing_data, respond_event_id)
	return CardInstance.new(definition_id, "none", 0)


## 判断消费失败后创建的当前请求是否属于同一装备响应重试；重试会自行重新进入原恢复分支，不能登记空响应续接。
func _is_pending_response_retry(original_context: Dictionary) -> bool:
	if _pending_card_choice.is_empty():
		return false
	# 当前等待请求的恢复上下文；只有携带已排除装备集合的同一响应语义才视为重试。
	var pending_context: Dictionary = _pending_card_choice.get("context", {}) as Dictionary
	if (pending_context.get("excluded_response_candidate_uids", []) as Array).is_empty():
		return false
	return str(pending_context.get("kind", "")) == str(original_context.get("kind", "")) \
		and int(pending_context.get("responder_id", -1)) == int(original_context.get("responder_id", -1)) \
		and int(pending_context.get("parent_card_uid", -1)) == int(original_context.get("parent_card_uid", -1))


## 把可空响应牌转换为续接安全快照；空字典稳定表示本次明确放弃或响应失效。
func _serialize_optional_response_card(response_card: CardInstance) -> Dictionary:
	return response_card.to_dict() if response_card != null else {}


## 从续接上下文恢复可空响应牌；既有 UID 不会消耗新的实体编号。
func _deserialize_optional_response_card(response_card_data: Dictionary) -> CardInstance:
	return CardInstance.from_dict(response_card_data) if not response_card_data.is_empty() else null


## 在嵌套触发和装备事件完成后恢复技能响应；技能等待期间失去时安全跳过旧回调。
func _continue_skill_response_after_barrier(continuation_context: Dictionary) -> void:
	# 创建响应的技能实例；稳定持有者与技能 ID 防止同名技能或新对局错误接管旧结果。
	var skill: SkillDefinition = get_skill_instance(int(continuation_context.get("skill_owner_id", -1)), str(continuation_context.get("skill_id", "")))
	# 原响应规则上下文；牌效、响应者和父事件信息保持选择创建时的可序列化快照。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	if skill == null or not skill.matches_character_generation(int(rule_context.get("skill_character_generation", -1))) or not skill.can_use_effect(bool(rule_context.get("locked_skill_segment", false))):
		return
	# 已经完成消费的响应牌代理；恢复只应用结果，绝不再次移动同一实体。
	var response_card: CardInstance = _deserialize_optional_response_card(continuation_context.get("response_card", {}) as Dictionary)
	skill.continue_response(rule_context, response_card)


## 在嵌套触发和装备事件完成后恢复卡牌响应，并从唯一入口判断是否完成父目标。
func _continue_card_response_after_barrier(continuation_context: Dictionary) -> void:
	# 原卡牌响应上下文；父牌 UID 与恢复 kind 决定 CardEffectResolver 分派目标。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	# 已经消费的实体或虚拟响应代理；空值表示响应者放弃。
	var response_card: CardInstance = _deserialize_optional_response_card(continuation_context.get("response_card", {}) as Dictionary)
	_continue_consumed_card_response(rule_context, response_card)


## 应用一张已经完成移动的父牌响应结果；后续又产生选择时只续接目标完成，不重复执行牌效回调。
func _continue_consumed_card_response(rule_context: Dictionary, response_card: CardInstance) -> void:
	# 响应内容先登记父位置；子伤害没有选牌但仍有后续步骤时也不能提前发布目标After。
	var steps: Array[Callable] = [_apply_consumed_card_response, _finish_consumed_card_response]
	run_rule_sequence(steps, {"rule_context":rule_context.duplicate(true), "response_card":_serialize_optional_response_card(response_card)})


## 已消费响应只执行一次；伤害、判定和技能等子流程在下一步骤前完成。
func _apply_consumed_card_response(sequence: RuleStepSequence) -> void:
	effect_resolver.continue_response(sequence.context.rule_context, _deserialize_optional_response_card(sequence.context.response_card))


## 子内容全部结束后才完成父目标；取消、死亡与额外阶段不依靠全局无选择状态推测。
func _finish_consumed_card_response(sequence: RuleStepSequence) -> void:
	# 原父响应参数；包含目标是否由本入口收尾的显式契约。
	var rule_context: Dictionary = sequence.context.rule_context
	if bool(rule_context.get("complete_parent_target_after_response", false)):
		_complete_active_card_target(int(rule_context.get("parent_card_uid", -1)))


## 在嵌套触发和装备事件完成后恢复无处理区父牌的装备响应结果。
func _continue_equipment_response_after_barrier(continuation_context: Dictionary) -> void:
	# 创建请求的装备定义；只用稳定定义 ID 找回源码，不依赖等待前的对象引用。
	var equipment_definition: CardDefinition = GameDatabase.get_card_definition(str(continuation_context.get("equipment_definition_id", "")))
	if equipment_definition == null:
		return
	# 原装备响应上下文；实体 UID 仍由装备源码在恢复时重新校验。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	# 已经消费的响应牌代理；空值表示装备判定失败或玩家放弃。
	var response_card: CardInstance = _deserialize_optional_response_card(continuation_context.get("response_card", {}) as Dictionary)
	equipment_definition.continue_equipment_response(self, rule_context, response_card)


## 恢复判定型装备的异步响应结果；失败时排除本装备并重开原响应窗口，成功时按原技能、卡牌或装备路由继续。
func continue_async_equipment_judgment_response(context: Dictionary, response_card: CardInstance, failed_equipment_uid: int) -> void:
	# 原响应者；普通卡牌响应使用 responder_id，【杀】兼容上下文可回退 target_id。
	var responder_id: int = int(context.get("responder_id", context.get("target_id", -1)))
	# 原请求允许的响应模式；判定成功牌与后续重试都必须保持同一牌型集合。
	var response_patterns: Array[String] = _string_array(context.get("response_patterns", []) as Array)
	# 最终响应牌；判定失败时尝试从排除当前装备后的其余合法候选中取得。
	var resolved_response_card: CardInstance = response_card
	# 异步判定成功的装备响应此前尚未经过普通消费成功分支，需要在此为父牌登记唯一一次直接响应。
	if response_card != null:
		_record_direct_response_from_context(context)
	if resolved_response_card == null:
		resolved_response_card = _retry_response_after_equipment_attempt(context, responder_id, response_patterns, failed_equipment_uid)
		if has_pending_card_choice() or has_pending_judgment_request():
			return
	# 技能自有响应路由；创建请求的技能仍存在且代次一致时才接收结果。
	var skill_id: String = str(context.get("skill_id", ""))
	if not skill_id.is_empty():
		# 技能持有者；跨角色选择仍由真实持有者实例处理。
		var skill_owner_id: int = int(context.get("skill_owner_id", -1))
		# 当前技能实例；等待期间失去技能时旧响应安全失效。
		var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id)
		if skill == null or not skill.matches_character_generation(int(context.get("skill_character_generation", -1))) or not skill.can_use_effect(bool(context.get("locked_skill_segment", false))):
			return
		if _has_nested_settlement_barrier():
			_defer_rule_continuation("skill_response", {"skill_owner_id":skill_owner_id, "skill_id":skill_id, "rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(resolved_response_card)})
			return
		skill.continue_response(context, resolved_response_card)
		return
	# 处理区父牌响应路由；【杀】等牌效由 CardEffectResolver 找回原定义并完成目标结算。
	if int(context.get("parent_card_uid", -1)) >= 0:
		if _has_nested_settlement_barrier():
			_defer_rule_continuation("card_response", {"rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(resolved_response_card)})
			return
		_continue_consumed_card_response(context, resolved_response_card)
		return
	# 无处理区父牌的装备自有响应；由创建请求的装备定义解释最终响应牌。
	var equipment_definition_id: String = str(context.get("equipment_definition_id", ""))
	if not equipment_definition_id.is_empty():
		if _has_nested_settlement_barrier():
			_defer_rule_continuation("equipment_response", {"equipment_definition_id":equipment_definition_id, "rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(resolved_response_card)})
			return
		# 当前装备定义；异步判定完成后仍按原稳定定义 ID 恢复，不依赖等待前的脚本对象引用。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_definition_id)
		if equipment_definition != null:
			equipment_definition.continue_equipment_response(self, context, resolved_response_card)


## 按选择请求提交的 UID 消耗响应牌；再次校验区域和响应模式后进入弃牌堆并播放动画。
func _consume_response_card_uid(player_id: int, card_uid: int, response_pattern: String) -> CardInstance:
	return _consume_response_card_uid_patterns(player_id, card_uid, [response_pattern])


## 按候选响应模式集合消耗一张实体牌；用于【桃】与【酒】等共享时机但牌名不同的单一询问窗口。
## 本入口严格区分“使用”与“打出”：两者都经处理区进入弃牌堆，都不构成一次“弃置牌”动作。
func _consume_response_card_uid_patterns(player_id: int, card_uid: int, response_patterns: Array[String], equipment_material_uids: Array[int] = [], response_skill_id: String = "", response_context: Dictionary = {}) -> CardInstance:
	# 响应玩家；请求等待期间其牌区可能被插入结算改变，因此必须重新查询。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null
	# 本次响应的卡牌动作类别；内容层显式声明优先，否则按响应模式取牌自身唯一合法的动作，最后回落到“打出”。
	var response_action: String = resolve_response_action(response_context, response_patterns)
	# 装备响应入口；装备文件负责复核模式、实体 UID、材料并返回虚拟响应牌。
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；只允许选择仍在装备区的同一 UID。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card.uid != card_uid:
			continue
		# 当前装备定义；不能提供本次模式时返回 null。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		# 当前装备所在槽位；本次结算整体停用的槽位（无视防具时的防具响应）必须在提交阶段再次拒绝，防止迟到或伪造动作。
		if _read_ignored_equipment_slots(response_context).has(_find_equipment_slot_for_card(player, equipment_card)):
			return null
		if equipment_definition != null and equipment_definition.can_offer_equipment_response(self, player_id, response_patterns):
			return equipment_definition.consume_equipment_response(self, player_id, card_uid, response_patterns, equipment_material_uids, response_context)
		return _consume_skill_converted_response(player_id, equipment_card, response_patterns, response_skill_id, response_context)
	# 被选响应牌；只能来自当前仍可使用的牌源。
	var card: CardInstance = player.find_playable_card(card_uid)
	if card == null:
		return null
	# 响应定义；模式不匹配时拒绝消费，防止旧请求或伪造动作改变状态。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 实体牌实际响应模式；日志与历史必须记录牌自身能提供的模式，不能把普通锦囊的受响应字段当作无懈牌能力。
	var response_pattern: String = _get_provided_response_pattern(definition)
	if not response_patterns.has(response_pattern):
		return _consume_skill_converted_response(player_id, card, response_patterns, response_skill_id, response_context)
	# 响应牌生命周期数据；player 与 source 都是响应者，父级牌或选择用途保留在 response_pattern 中。
	# response_action 让技能、回放与表现层能区分本次是“使用”还是“打出”，两者的实体移动语义相同而时机不同。
	var timing_data: Dictionary = {"card_uid":card.uid, "card_id":card.definition_id, "response_pattern":response_pattern, "response_action":response_action}
	var respond_before_event: RuleEvent = _emit_rule_timing("respondBefore", player_id, player_id, -1, timing_data)
	if respond_before_event != null and (respond_before_event.cancelled or respond_before_event.neutralized):
		return null
	var respond_begin_event: RuleEvent = _emit_rule_timing("respondBegin", player_id, player_id, -1, respond_before_event.data if respond_before_event != null else timing_data)
	if respond_begin_event != null and (respond_begin_event.cancelled or respond_begin_event.neutralized):
		return null
	# 是否为实际手牌；银月枪只由回合外使用或打出的黑色手牌触发。
	var was_hand_card: bool = player.hand.has(card)
	# 响应时声明的逻辑牌ID；手牌视为效果会在实体离开手牌区时恢复原名，因此必须在移动前保存牌效身份。
	var logical_definition_id: String = card.definition_id
	# 当前实体是否由手牌视为效果提供响应；用于移动后构造不进入权威区域的逻辑响应代理。
	var was_hand_view_as: bool = card.has_hand_view_as()
	# 实际消耗牌；take_playable_card 同时支持普通手牌与木牛“粮”。
	var consumed: CardInstance = player.take_playable_card(card.uid)
	# 响应父事件；使用与打出共用同一稳定事件名，动作类别写入载荷供技能与回放读取。
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "card_uid":consumed.uid, "response_action":response_action}, {"responded":true, "response_action":response_action})
	# 实体回收；这里必须走“使用与打出”的经处理区路径，不能调用弃置入口。
	# 直接弃置会让响应牌与“弃置牌”共用同一条移动路径并计入弃置批次，
	# 使【闪】等响应被误判为“弃置”并错误触发【泛音】等“当你弃置牌时”类效果。
	_move_played_card_to_discard(consumed, response_action, respond_event_id, player_id)
	timing_data["respond_event_id"] = respond_event_id
	# 主体时机；使用派发 useCard，打出派发 respond，两者语义互斥且不会同时派发。
	_emit_rule_timing(_get_card_action_main_timing(response_action), player_id, player_id, -1, timing_data, respond_event_id)
	player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":consumed.uid, "response_action":response_action})
	# 响应结果对象；普通牌直接沿用实体，手牌视为牌使用逻辑代理以继续正确执行【桃】等后续效果。
	var resolved_response_card: CardInstance = consumed
	if was_hand_view_as:
		resolved_response_card = CardInstance.new(logical_definition_id, consumed.suit, consumed.rank)
		resolved_response_card.uid = consumed.uid
		resolved_response_card.zone = consumed.zone
	# 响应日志显示已经声明的逻辑牌名，弃牌堆中的实体快照仍展示恢复后的原始牌名。
	# 使用与打出的日志动词不同，日志是玩家理解“这张牌算使用还是打出”的唯一公开依据。
	add_log(_build_card_action_log(player, resolved_response_card, response_action))
	# 音频表现：响应牌结算成功后请求一次卡牌语音；响应流程不会回调牌源文件，因此必须在本统一出口触发。
	request_card_voice(player_id, logical_definition_id, _get_card_action_voice_mode(response_action))
	_notify_equipment_card_consumed(player.player_id, consumed, was_hand_card)
	# 尾部时机同样按动作类别分派；使用型响应以 useCardAfter 收尾，打出型响应保留 respondEnd 与 respondAfter。
	if response_action == CARD_ACTION_USE:
		_emit_rule_timing("useCardAfter", player_id, player_id, -1, timing_data, respond_event_id)
	else:
		_emit_rule_timing("respondEnd", player_id, player_id, -1, timing_data, respond_event_id)
		_emit_rule_timing("respondAfter", player_id, player_id, -1, timing_data, respond_event_id)
	return resolved_response_card


## 返回一张牌实际能够提供的响应模式；映射基于牌效语义，避免所有可被无懈的普通锦囊都被误当成【无懈可击】。
func _get_provided_response_pattern(definition: Dictionary) -> String:
	# 卡牌文件显式提供的响应模式；新增响应牌不需要登记牌效兼容映射。
	return str(definition.get("provided_response_pattern", ""))


## 解析一次响应请求的卡牌动作类别；优先读取内容层在响应上下文中显式声明的 response_action。
## 未显式声明时按响应模式回落：【无懈可击】【桃】【酒】只有“使用”一种合法动作，
## 【杀】与【闪】既可能被使用也可能被打出，必须由发起响应的内容显式声明，缺省按“打出”处理。
## response_patterns 故意声明为无类型 Array：内容层会以 ["shan"] 这类字面量数组直接调用本端口，
## 而 GDScript 的 Array[String] 形参在运行时拒绝无类型数组实参并抛错，因此这里只做逐元素字符串读取。
func resolve_response_action(response_context: Dictionary, response_patterns: Array) -> String:
	# 内容层显式声明；只接受两个稳定取值，非法值按未声明处理而不猜测语义。
	var declared_action: String = str(response_context.get("response_action", ""))
	if CARD_ACTIONS.has(declared_action):
		return declared_action
	# 模式集合推导结果；【桃】与【酒】共享救援窗口时要求全部模式同为“使用”才成立。
	var deduced_action: String = ""
	for pattern_variant: Variant in response_patterns:
		# 当前响应模式；统一转为字符串后再查表，未登记模式（【杀】【闪】与扩展响应标签）一律按“打出”处理。
		var response_pattern: String = str(pattern_variant)
		# 当前响应模式的默认动作；缺失登记时回落到“打出”，保证未迁移内容行为不变。
		var pattern_action: String = str(RESPONSE_PATTERN_ACTION_DEFAULTS.get(response_pattern, DEFAULT_RESPONSE_ACTION))
		if deduced_action.is_empty():
			deduced_action = pattern_action
		elif deduced_action != pattern_action:
			return DEFAULT_RESPONSE_ACTION
	return deduced_action if not deduced_action.is_empty() else DEFAULT_RESPONSE_ACTION


## 返回一次卡牌动作对应的主体时机名；使用走 useCard，打出走 respond，两者互斥且不会同时派发。
func _get_card_action_main_timing(action: String) -> String:
	return "useCard" if action == CARD_ACTION_USE else "respond"


## 返回一次卡牌动作对应的音频动作模式；两种动作共用同一份音效，该字段只影响解析与诊断。
func _get_card_action_voice_mode(action: String) -> String:
	return VOICE_PLAY_MODE_USE if action == CARD_ACTION_USE else VOICE_PLAY_MODE_RESPOND


## 构造一次使用或打出的公开日志；动词由动作类别决定，实体牌名沿用统一牌名格式化。
func _build_card_action_log(player: PlayerState, card: CardInstance, action: String) -> String:
	return "%s%s%s。" % [format_player_state_log_name(player), _get_card_action_verb(action), format_card_log_name(card)]


## 返回动作类别对应的中文动词；日志是玩家判断“这张牌算使用还是打出”的唯一公开依据。
func _get_card_action_verb(action: String) -> String:
	return "使用了" if action == CARD_ACTION_USE else "打出了"


## 把已经离开原牌源的使用牌或打出牌经处理区送入弃牌堆。
## 使用与打出都必须先公开进入处理区，这是它们与“弃置”唯一可靠的规则边界：
## 弃置批次只认手牌、装备与木牛“粮”三种来源，处理区收尾天然不构成一次“弃置牌”动作，
## 因此不会派发 cardsDiscardedBatchAfter，也就不会触发【泛音】等“当你弃置牌时”类效果。
## actor_id 是本次使用或打出的角色，只用于牌面表现事件，不参与规则判定。
## 返回是否完成回收；处理区前置时机取消时返回 false（实体此时不再位于任何权威区域，与取消一次使用牌的处理一致）。
func _move_played_card_to_discard(card: CardInstance, action: String, parent_event_id: int, actor_id: int) -> bool:
	if card == null:
		return false
	_ensure_card_movement()
	# 处理区落点；移动原因使用动作类别，回放与移牌历史可据此区分“使用”和“打出”。
	if _move_card_with_timings(card, "processing", -1, action, parent_event_id) == null:
		return false
	# 使用与打出的牌面表现认领；必须在处理区收尾之前发出，这是本函数第二条不可调换的顺序约束。
	# 表现层只承认由 useCard 表现认领过的处理区实体：未经认领的 processing -> discard_pile 增量会被判定为虚拟材料收尾并创建 0 张牌面，
	# 导致响应牌完全没有飞牌动画。响应牌没有目标角色，因此只播放“从响应者锚点飞向中央展示区”的整牌动画。
	_request_card_presentation(card, actor_id, [], "useCard", parent_event_id, true)
	# 处理区收尾；此处复用统一弃置入口，使 cardsDiscard 事件、公共区可见性与主动使用牌完全一致。
	# 由于实体此刻已经在处理区，弃置入口不会把它计入任何弃置批次——这正是本函数存在的唯一理由。
	_move_to_discard(card, parent_event_id)
	return card.zone == "discard_pile"


## 判断玩家的一张当前拥有牌能否由任一已安装技能转化为本次响应；技能只声明合法性，不移动实体牌。
func _can_skill_convert_response_card(player_id: int, card: CardInstance, response_patterns: Array[String]) -> bool:
	return not _get_response_conversion_skill_id(player_id, card, response_patterns).is_empty()


## 返回首个能把指定材料转化为本次响应的已安装技能ID；空字符串表示没有合法转化入口。
func _get_response_conversion_skill_id(player_id: int, card: CardInstance, response_patterns: Array[String]) -> String:
	if card == null:
		return ""
	# 当前玩家的运行时技能表；按武将配置顺序稳定查找，保证多个转化技能并存时结果确定。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前转化技能；被动、触发和普通主动技能默认返回false。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect() and can_use_acquired_skill(player_id, skill.get_id()) and skill.can_convert_response_card(card, response_patterns):
			return skill.get_id()
	return ""


## 通过首个仍合法的武将技能消耗一张材料牌并生成虚拟响应牌；等待期间条件失效时不移动材料。
## 技能转化的响应同样区分“使用”与“打出”，材料经处理区进入弃牌堆，不构成一次“弃置牌”动作。
func _consume_skill_converted_response(player_id: int, material_card: CardInstance, response_patterns: Array[String], response_skill_id: String = "", response_context: Dictionary = {}) -> CardInstance:
	if material_card == null or response_skill_id.is_empty():
		return null
	# 转化响应采用的卡牌动作类别；与实体响应牌读取同一套声明，保证日志、时机与语音完全一致。
	var response_action: String = resolve_response_action(response_context, response_patterns)
	# 当前玩家的运行时技能表；安装顺序决定多个转化技能同时可用时的稳定优先级。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前候选技能；必须在提交时再次满足材料颜色、区域和响应模式条件。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or not skill.can_use_effect() or skill.get_id() != response_skill_id or not can_use_acquired_skill(player_id, skill.get_id()) or not skill.can_convert_response_card(material_card, response_patterns):
			continue
		# 转化后的卡牌定义；其自身必须能够提供当前请求中的一种响应模式。
		var virtual_definition_id: String = skill.get_converted_response_definition_id(material_card, response_patterns)
		# 转化后的完整卡牌定义；用于校验响应标签并向后续响应生命周期提供逻辑牌数据。
		var virtual_definition: Dictionary = GameDatabase.get_card(virtual_definition_id)
		# 转化牌实际提供的响应标签；空值或不匹配当前请求时不得消耗实体材料。
		var response_pattern: String = _get_provided_response_pattern(virtual_definition)
		if virtual_definition.is_empty() or not response_patterns.has(response_pattern):
			continue
		# 响应生命周期数据；逻辑牌名使用转化结果，材料 UID 继续保证移动、回放与迟到提交可追踪。
		var timing_data: Dictionary = {"card_uid":material_card.uid, "card_id":virtual_definition_id, "material_card_id":material_card.definition_id, "response_pattern":response_pattern, "response_action":response_action, "skill_id":skill.get_id(), "virtual":true}
		# 响应前置时机事件；取消或中立化时保留原材料区域并终止本次转化。
		var respond_before_event: RuleEvent = _emit_rule_timing("respondBefore", player_id, player_id, -1, timing_data)
		if respond_before_event != null and (respond_before_event.cancelled or respond_before_event.neutralized):
			return null
		# 响应开始时机事件；继承前置时机可能修改的数据，供其他规则继续处理。
		var respond_begin_event: RuleEvent = _emit_rule_timing("respondBegin", player_id, player_id, -1, respond_before_event.data if respond_before_event != null else timing_data)
		if respond_begin_event != null and (respond_begin_event.cancelled or respond_begin_event.neutralized):
			return null
		# 材料原本是否位于普通手牌区；银月枪等“使用或打出黑色手牌”效果继续读取真实材料来源。
		# 材料持有者状态；用于在移动前保存手牌与装备区的真实来源。
		var player: PlayerState = state.get_player(player_id)
		# 材料移动前是否属于普通手牌；该标记决定是否触发依赖手牌来源的后续效果。
		var was_hand_card: bool = player != null and player.hand.has(material_card)
		# 材料原本是否位于装备区；成功移出后必须卸载持续效果并执行白银狮子、木牛流马等离区规则。
		var was_equipment_card: bool = player != null and player.equipment.values().has(material_card)
		# 虚拟响应父事件；材料先进入处理区再进入弃牌堆，与实体响应牌保持相同公开移动语义。
		var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "skill_id":skill.get_id(), "material_card_uids":[material_card.uid], "response_action":response_action}, {"responded":true, "virtual":true, "card_id":virtual_definition_id, "response_action":response_action})
		_ensure_card_movement()
		if _move_card_with_timings(material_card, "processing", -1, response_action, respond_event_id) == null:
			return null
		if was_equipment_card:
			_on_equipment_lost(player, material_card, true)
		# 处理区收尾；此时实体来源已经是处理区，复用统一弃置入口不会产生弃置批次，收益是与主动使用牌完全一致的 cardsDiscard 收尾事件。
		_move_to_discard(material_card, respond_event_id)
		timing_data["respond_event_id"] = respond_event_id
		# 主体时机按动作类别分派；使用走 useCard，打出走 respond。
		_emit_rule_timing(_get_card_action_main_timing(response_action), player_id, player_id, -1, timing_data, respond_event_id)
		player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":-1, "material_card_uids":[material_card.uid], "skill_id":skill.get_id(), "virtual_card_id":virtual_definition_id, "response_action":response_action})
		skill.on_converted_response_consumed(material_card, response_pattern, virtual_definition_id)
		skill.announce_activation({"material_card_uid":material_card.uid, "response_pattern":response_pattern, "virtual_card_id":virtual_definition_id})
		add_log("%s将一张牌当%s%s。" % [player.display_name, GameSettings.resolve_card_name(virtual_definition), _get_card_action_verb(response_action)])
		# 音频表现：技能转化的响应牌同样按实际结算的虚拟牌定义请求语音。
		request_card_voice(player_id, virtual_definition_id, _get_card_action_voice_mode(response_action))
		_notify_equipment_card_consumed(player_id, material_card, was_hand_card)
		# 尾部时机与实体响应牌保持同一分派规则。
		if response_action == CARD_ACTION_USE:
			_emit_rule_timing("useCardAfter", player_id, player_id, -1, timing_data, respond_event_id)
		else:
			_emit_rule_timing("respondEnd", player_id, player_id, -1, timing_data, respond_event_id)
			_emit_rule_timing("respondAfter", player_id, player_id, -1, timing_data, respond_event_id)
		# 单材料转化保留原花色和点数，使颜色、防具与后续牌面查询遵循实体材料属性。
		return CardInstance.new(virtual_definition_id, material_card.suit, material_card.rank)
	return null


## 恢复无懈可击选择；延时锦囊回到原判定步骤，普通锦囊恢复当前目标效果。
func _continue_trick_negation_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 响应者 ID；选择的无懈可击必须仍来自其可用牌源。
	var responder_id: int = int(context.get("responder_id", -1))
	# 当前抵消状态；每实际打出一张无懈可击翻转一次。
	var final_negated: bool = bool(context.get("negated", false))
	# 实际打出的无懈可击；空值表示当前角色明确放弃，本轮继续询问下一名角色。
	var counter_card: CardInstance
	if not selected_uids.is_empty():
		# 实际无懈可击响应牌；请求完成后仍需复核牌源与响应模式。
		counter_card = _consume_response_card_uid(responder_id, selected_uids[0], "wuxie")
	if state.game_over:
		return
	if counter_card != null and _has_nested_settlement_barrier():
		_defer_rule_continuation("trick_negation_response", {"responder_id":responder_id, "final_negated":final_negated, "rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(counter_card)})
		return
	_continue_consumed_trick_negation(context, responder_id, final_negated, counter_card)


## 在失牌触发与装备事件完成后恢复传统逐人无懈响应链。
func _continue_trick_negation_after_barrier(continuation_context: Dictionary) -> void:
	# 原无懈链上下文；响应游标、锦囊目标与奇偶状态保持中断前快照。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	# 已消费的无懈响应牌；恢复时只记录链结果，不再次移动实体。
	var counter_card: CardInstance = _deserialize_optional_response_card(continuation_context.get("response_card", {}) as Dictionary)
	_continue_consumed_trick_negation(rule_context, int(continuation_context.get("responder_id", -1)), bool(continuation_context.get("final_negated", false)), counter_card)


## 把一张已经消费的无懈写入奇偶链并继续下一轮；空响应只推进当前询问游标。
func _continue_consumed_trick_negation(context: Dictionary, responder_id: int, final_negated: bool, counter_card: CardInstance) -> void:
	if counter_card != null:
		final_negated = not final_negated
		# 当前响应玩家；等待期间失效时仍保留回放事实，但日志安全回退到玩家编号。
		var responder: PlayerState = state.get_player(responder_id)
		add_log("%s使用【无懈可击】，当前锦囊%s。" % [responder.display_name if responder != null else "玩家%d" % responder_id, "被抵消" if final_negated else "恢复生效"])
	context["negated"] = final_negated
	if counter_card != null:
		# 成功响应后开启新一轮无懈询问；任何角色均可继续响应刚打出的【无懈可击】。
		context["response_index"] = 0
		_record_wuxie_chain_response(context, responder_id, counter_card)
	else:
		# 当前角色放弃响应；只推进本轮询问游标，不结束整条响应链。
		context["response_index"] = int(context.get("response_index", 0)) + 1
	# 后续链结果；存在下一名可响应者时会立即创建新请求，完整一轮无人响应才返回完成状态。
	var chain_result: Dictionary = _advance_trick_negation_chain(context)
	if bool(chain_result.get("pending", false)):
		return
	_finish_trick_negation_chain(context, bool(chain_result.get("negated", final_negated)))


## 记录一张实际打出的【无懈可击】并更新可回放的奇偶状态；该状态始终绑定原锦囊的当前目标。
func _record_wuxie_chain_response(context: Dictionary, responder_id: int, counter_card: CardInstance) -> void:
	# 已完成响应结果；每项只保存稳定玩家、实体牌和原锦囊信息，不持有可变对象引用。
	var response_results: Array = (context.get("wuxie_response_results", []) as Array).duplicate(true)
	# 本张无懈直接响应的对象；第一张响应原锦囊，后续无懈只响应上一张无懈，不重复累计到原锦囊。
	var responded_card_uid: int = int(context.get("parent_card_uid", -1)) if response_results.is_empty() else int((response_results.back() as Dictionary).get("card_uid", -1))
	response_results.append({"player_id":responder_id, "card_uid":counter_card.uid, "card_id":counter_card.definition_id, "respond_to":str(context.get("trick_id", "")) if response_results.is_empty() else "wuxie", "respond_to_card_uid":responded_card_uid})
	context["wuxie_response_results"] = response_results
	if response_results.size() == 1:
		record_card_direct_response(int(context.get("parent_card_uid", -1)), responder_id)
	# 原锦囊定义；无懈身份观察通过其目标收益与当前奇偶结果判断本次响应的忠反方向。
	var response_subject_definition: Dictionary = GameDatabase.get_card(str(context.get("trick_id", "")))
	# 成功打出的无懈可击公开行为；仅在原使用者已有暴露且响应者不是目标本人时形成身份线索。
	ai_coordinator.observe_card_response(state.to_dict(-1, true), responder_id, GameDatabase.get_card(counter_card.definition_id), response_subject_definition, context, local_human_player_id)
	# 同一公开响应行为同步给远端客户端；只下发公开结算方向，客户端本地重放以保持各自独立推断。
	_broadcast_identity_response(responder_id, counter_card.definition_id, str(context.get("trick_id", "")), context)
	# 当前无懈状态对象；按已有响应顺序重建，确保异步上下文与独立状态类使用同一奇偶规则。
	var wuxie_state: WuxieChainState = WuxieChainState.new(int(context.get("root_event_id", state.current_event_id)))
	for response_variant: Variant in response_results:
		# 单次历史响应；重建时逐项翻转状态并保留原始可序列化字段。
		var response_result: Dictionary = response_variant as Dictionary
		wuxie_state.add_response(int(response_result.get("player_id", -1)), response_result)
	_record_runtime_event("WuxieChainState", "response", {"trick_id":str(context.get("trick_id", "")), "target_id":int(context.get("target_id", -1))}, wuxie_state.to_dict())


## 从当前游标继续询问无懈可击；返回 pending 表示等待选择，返回完成结果表示本轮所有角色均已放弃。
## 并行响应补充：正式对局会在同一轮为全部存活玩家登记请求，最先提交合法无懈的玩家取得本轮结算权。
func _advance_trick_negation_chain(context: Dictionary) -> Dictionary:
	if state == null or state.game_over:
		return {"pending":false, "negated":bool(context.get("negated", false))}
	if not _pending_negation_choices.is_empty():
		return {"pending":true, "negated":bool(context.get("negated", false))}
	# 无正式对局 ID 的规则测试无法等待真实输入；使用行动顺序作为同帧响应的稳定裁决顺序。
	if state.match_id.is_empty():
		return _resolve_simultaneous_negation_synchronously(context)
	_begin_simultaneous_negation_round(context)
	return {"pending":not _pending_negation_choices.is_empty(), "negated":bool(context.get("negated", false))}


## 在无交互规则测试中同步完成无懈链；每轮仍检查全部存活角色，但同帧并列响应按固定行动顺序裁决。
func _resolve_simultaneous_negation_synchronously(context: Dictionary) -> Dictionary:
	# 固定行动顺序玩家 ID；仅作为同步环境无法表达网络到达时间时的稳定平局规则。
	var response_order_ids: Array = context.get("response_order_ids", []) as Array
	while not state.game_over:
		# 当前轮是否已经有玩家实际使用无懈；成功后立即进入下一轮反无懈。
		var round_responded: bool = false
		for responder_id_variant: Variant in response_order_ids:
			# 当前同时被询问玩家；死亡角色不会进入候选构造或响应消费。
			var responder_id: int = int(responder_id_variant)
			# 当前响应者状态；同步规则测试仍使用与正式对局一致的 AI 收益判断。
			var responder: PlayerState = state.get_player(responder_id)
			if responder == null or not responder.alive or responder.out_of_game or not _should_auto_negate(responder, int(context.get("source_id", -1)), int(context.get("target_id", -1)), str(context.get("trick_id", "")), bool(context.get("negated", false))):
				continue
			# 当前响应者私有候选；只消费规则声明为 wuxie 的首张合法实体。
			var candidates: Array[Dictionary] = _build_response_choice_candidates(responder, ["wuxie"])
			if candidates.is_empty():
				continue
			# 当前实际响应牌；等待期间区域不变化的同步环境仍通过统一消费入口复核。
			var counter_card: CardInstance = _consume_response_card_uid(responder_id, int(candidates[0].get("uid", -1)), "wuxie")
			if counter_card == null:
				continue
			context["negated"] = not bool(context.get("negated", false))
			_record_wuxie_chain_response(context, responder_id, counter_card)
			add_log("%s使用【无懈可击】，当前锦囊%s。" % [responder.display_name, "被抵消" if bool(context.get("negated", false)) else "恢复生效"])
			round_responded = true
			break
		if not round_responded:
			break
	return {"pending":false, "negated":bool(context.get("negated", false))}


## 为一轮无懈可击同时登记全部存活玩家；候选按玩家分别保存，公共状态只公开统一高亮名单。
func _begin_simultaneous_negation_round(context: Dictionary) -> void:
	if state == null or state.game_over or not _pending_negation_choices.is_empty():
		return
	_negation_round_sequence += 1
	# 当前轮可序列化上下文；每个玩家请求取得独立副本，任何客户端都不能修改其他玩家候选。
	var round_context: Dictionary = context.duplicate(true)
	round_context["negation_round_id"] = _negation_round_sequence
	if not round_context.has("negation_parent_event_id"):
		round_context["negation_parent_event_id"] = event_scheduler.get_current_event_id()
	if not round_context.has("resume_phase"):
		round_context["resume_phase"] = state.current_phase
	# 本轮全部存活响应者；无论是否持有无懈都进入公共名单，避免高亮泄露私有手牌。
	var responder_ids: Array[int] = []
	for responder_id_variant: Variant in round_context.get("response_order_ids", []) as Array:
		# 当前响应者 ID；公共名单防御性去重并跳过死亡或离场角色。
		var responder_id: int = int(responder_id_variant)
		# 当前响应者状态；不存在或死亡时不创建已经无效的网络请求。
		var responder: PlayerState = state.get_player(responder_id)
		if responder != null and responder.alive and not responder_ids.has(responder_id):
			responder_ids.append(responder_id)
	state.current_phase = "choice"
	state.simultaneous_response_display = {
		"kind":"trick_negation",
		"round_id":_negation_round_sequence,
		"responder_ids":responder_ids.duplicate(),
		"target_id":int(round_context.get("target_id", -1)),
		"trick_id":str(round_context.get("trick_id", "")),
	}
	# 公共高亮先于私有请求发布，界面不会在首个请求到达时短暂暴露单一行动者。
	_emit_state()
	for responder_id: int in responder_ids:
		_register_simultaneous_negation_choice(responder_id, round_context)
	if _pending_negation_choices.is_empty():
		# 本轮无人拥有合法无懈候选时直接结束询问；公共名单仍已统一发布，不会逐座位暴露跳过过程。
		state.simultaneous_response_display.clear()
		state.current_phase = str(round_context.get("resume_phase", "play"))
	_refresh_simultaneous_choice_snapshot()
	_emit_state()


## 为一名玩家登记本轮私有无懈请求；候选为空时只保留公共高亮，不创建阻塞窗口。
func _register_simultaneous_negation_choice(responder_id: int, round_context: Dictionary) -> void:
	# 当前响应者状态；登记前再次复核存活，避免创建无法提交的请求。
	var responder: PlayerState = state.get_player(responder_id)
	if responder == null or not responder.alive:
		return
	# 当前响应者私有候选；其他观察者只能通过裁剪快照看到空候选。
	var candidates: Array[Dictionary] = _build_response_choice_candidates(responder, ["wuxie"])
	if candidates.is_empty():
		# 无候选玩家已经包含在公共高亮名单中，但不创建只能放弃的私有阻塞窗口。
		return
	# 当前玩家独立上下文；响应者、AI选择倾向与响应模式均由权威端写入。
	var response_context: Dictionary = round_context.duplicate(true)
	response_context["responder_id"] = responder_id
	response_context["response_patterns"] = ["wuxie"]
	response_context["ai_prefer_select"] = _should_auto_negate(responder, int(round_context.get("source_id", -1)), int(round_context.get("target_id", -1)), str(round_context.get("trick_id", "")), bool(round_context.get("negated", false)))
	# 当前目标角色；询问文字使用武将名，不把玩家昵称或 AI 前缀混入卡牌规则提示。
	var target: PlayerState = state.get_player(int(round_context.get("target_id", -1)))
	# 当前目标武将名；异常状态下使用稳定通用描述。
	var target_name: String = _player_character_name(target) if target != null else "当前目标"
	# 当前询问文字；抵消状态决定本轮无懈将令原锦囊恢复还是无效。
	var prompt: String = "是否使用【无懈可击】令锦囊对%s的效果%s？" % [target_name, "恢复生效" if bool(round_context.get("negated", false)) else "无效"]
	# 当前选择事件；所有并行请求都挂在原锦囊 content 事件下，不形成按座次串行父子链。
	var choice_event: GameEvent = event_scheduler.create_event("chooseToRespond", "choice", [], response_context, int(round_context.get("negation_parent_event_id", event_scheduler.root_event_id)))
	choice_event.player_id = responder_id
	# 当前运行时请求；0至1张且允许取消，候选已经在登记前确认非空。
	var runtime_request: ChoiceRequest = ChoiceRequest.new(choice_event.event_id, responder_id, "respond", prompt)
	runtime_request.min_count = 0
	runtime_request.max_count = 1
	runtime_request.forced = false
	runtime_request.can_cancel = true
	runtime_request.base_context = response_context.duplicate(true)
	runtime_request.active_context = response_context.duplicate(true)
	for candidate: Dictionary in candidates:
		runtime_request.card_ids.append(int(candidate.get("uid", -1)))
	# 已登记请求；失败时终止临时事件，其他玩家请求仍可独立继续。
	var registered_request: ChoiceRequest = event_scheduler.request_choice(runtime_request)
	if registered_request == null:
		choice_event.abort("negation_choice_registration_failed")
		return
	# 桌面兼容请求快照；保留 chooser_id 字段供现有卡牌选择组件直接复用。
	var choice_data: Dictionary = {
		"request_id":registered_request.request_id,
		"chooser_id":responder_id,
		"title":"响应询问",
		"prompt":prompt,
		"candidates":candidates.duplicate(true),
		"min_select":0,
		"max_select":1,
		"allow_cancel":true,
		"resume_phase":str(round_context.get("resume_phase", "play")),
		"context":response_context.duplicate(true),
		"deferred":true,
		"runtime_event_id":choice_event.event_id,
		"runtime_request_id":registered_request.request_id,
	}
	_pending_negation_choices[registered_request.request_id] = choice_data
	_publish_card_choice_request(choice_data, true)
	if ai_coordinator.is_ai_controlled(responder_id):
		# 关闭流程节奏的规则测试仍立即启动 AI 等待；正式对局由延时提示发布回调统一启动。
		if game_flow_pacer == null or game_flow_interval_seconds <= 0.0:
			_run_simultaneous_negation_ai_after_delay(registered_request.request_id, responder_id, _negation_round_sequence)


## 等待统一 AI 响应延迟后提交本轮决定；所有 AI 计时器并行启动，先到达的合法无懈立即获胜。
func _run_simultaneous_negation_ai_after_delay(request_id: int, responder_id: int, round_id: int) -> void:
	# 并行无懈计时器同样服从对局暂停；暂停不会改变恢复后的先到先结算语义。
	await get_tree().create_timer(_get_effective_ai_response_delay_seconds(), false).timeout
	if state == null or state.game_over or round_id != _negation_round_sequence or not _pending_negation_choices.has(request_id):
		return
	if is_gameplay_paused():
		# 暂停恰好覆盖计时器到期时重新等待同一请求；否则AI请求会永久残留并把无懈链卡在询问阶段。
		_run_simultaneous_negation_ai_after_delay(request_id, responder_id, round_id)
		return
	# 当前 AI 私有请求；只读副本用于生成合法动作，不允许策略修改权威候选。
	var choice_data: Dictionary = (_pending_negation_choices.get(request_id, {}) as Dictionary).duplicate(true)
	if int(choice_data.get("chooser_id", -1)) != responder_id or not ai_coordinator.is_ai_controlled(responder_id):
		return
	# 当前运行时请求；字段与登记时的稳定 ID 完全一致，迟到结果无法命中新轮。
	var runtime_request: ChoiceRequest = ChoiceRequest.new(int(choice_data.get("runtime_event_id", -1)), responder_id, "respond", str(choice_data.get("prompt", "")))
	runtime_request.request_id = request_id
	runtime_request.min_count = 0
	runtime_request.max_count = 1
	runtime_request.can_cancel = true
	# 当前合法动作；空选择与每张候选分别通过相同权威提交入口。
	var legal_actions: Array[Dictionary] = _build_card_choice_actions(choice_data)
	# 当前 AI 完整快照；策略只读并按上下文中的收益倾向决定是否响应。
	var full_snapshot: Dictionary = state.to_dict(responder_id, true)
	# 当前 AI 响应；空返回使用明确放弃作为保守结果。
	var ai_response: ChoiceResponse = ai_coordinator.request_choice(responder_id, full_snapshot, runtime_request, choice_data, legal_actions)
	# 当前标准动作；即使放弃也携带同一请求 ID 进入权威校验。
	var action: PlayerAction = PlayerAction.new("choose_cards", responder_id)
	action.payload = {"request_id":request_id, "event_id":int(choice_data.get("runtime_event_id", -1)), "selected_card_uids":ai_response.card_ids.duplicate() if ai_response != null else []}
	_submit_ai_action(action)


## 校验并提交一名玩家在同时无懈轮次中的响应；成功出牌后原子关闭同轮其他请求。
func _submit_simultaneous_negation_choice(action: PlayerAction) -> bool:
	# 当前请求 ID；必须仍属于正在等待的同一无懈轮次。
	var request_id: int = int(action.payload.get("request_id", -1))
	if not _pending_negation_choices.has(request_id):
		return _reject("无懈可击响应请求已经失效。")
	# 当前私有请求；提交者、候选和事件 ID 都从权威副本复核。
	var choice_data: Dictionary = (_pending_negation_choices.get(request_id, {}) as Dictionary).duplicate(true)
	if action.actor_id != int(choice_data.get("chooser_id", -1)):
		return _reject("该无懈可击请求不属于当前玩家。")
	if action.payload.has("event_id") and int(action.payload.get("event_id", -1)) != int(choice_data.get("runtime_event_id", -2)):
		return _reject("无懈可击响应所属事件已经失效。")
	# 本次选择 UID；无懈请求最多选择一张，空数组表示明确放弃。
	var selected_uids: Array[int] = _int_array(action.payload.get("selected_card_uids", []) as Array)
	if selected_uids.size() > 1:
		return _reject("无懈可击响应最多选择一张牌。")
	# 当前合法候选 UID；只来源于该响应者收到的私有请求。
	var candidate_uids: Array[int] = []
	for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
		candidate_uids.append(int((candidate_variant as Dictionary).get("uid", -1)))
	if not selected_uids.is_empty() and not candidate_uids.has(selected_uids[0]):
		return _reject("选择中包含不属于本次无懈询问的牌。")
	# 当前运行时响应；先解决本请求 token，具体链状态更新完成后再统一排空事件树。
	var runtime_response: ChoiceResponse = ChoiceResponse.new(request_id, int(choice_data.get("runtime_event_id", -1)), action.actor_id, not selected_uids.is_empty())
	runtime_response.card_ids = selected_uids.duplicate()
	runtime_response.client_sequence = action.client_sequence
	runtime_response.source = "ai" if ai_coordinator.is_ai_controlled(action.actor_id) else ("network" if network_gateway.mode != NetworkGateway.Mode.OFFLINE else "local")
	if not event_scheduler.submit_choice(runtime_response, true):
		return _reject("事件运行时拒绝了已过期的无懈响应。")
	_cancel_paced_response_prompt(request_id)
	_pending_negation_choices.erase(request_id)
	state.action_sequence += 1
	# 当前轮共享上下文；所有请求都持有相同初始链状态，首个合法响应成为唯一写入者。
	var context: Dictionary = (choice_data.get("context", {}) as Dictionary).duplicate(true)
	# 当前实际无懈牌；提交后再次复核实体仍位于合法牌源，失效选择按放弃处理。
	var counter_card: CardInstance
	if not selected_uids.is_empty():
		# 已提交实体在权威候选中通过复核后立即关闭同轮其他请求，使失去该牌产生的普通技能选择可以安全插入。
		_close_remaining_simultaneous_negation_choices()
		state.simultaneous_response_display.clear()
		state.current_choice_request.clear()
		counter_card = _consume_response_card_uid_patterns(action.actor_id, selected_uids[0], ["wuxie"], _int_array(action.payload.get("material_card_uids", []) as Array))
	if counter_card != null:
		if _has_nested_settlement_barrier():
			_defer_rule_continuation("simultaneous_negation_response", {"responder_id":action.actor_id, "rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(counter_card)})
			event_scheduler.drain()
			_emit_state()
			return true
		_continue_consumed_simultaneous_negation(context, action.actor_id, counter_card)
		return true
	if not _pending_negation_choices.is_empty():
		_refresh_simultaneous_choice_snapshot()
		event_scheduler.drain()
		_emit_state()
		_publish_next_control_all_negation_choice()
		return true
	# 本轮最后一名响应者明确放弃；此时没有失效实体需要重试，应直接以当前奇偶结果结束无懈链。
	if selected_uids.is_empty():
		_finish_simultaneous_negation_submission(context)
		return true
	# 已选择实体在消费时失效；同轮请求已经关闭时重新建立完整一轮，避免一次失败提交错误结束无懈链。
	var retry_chain_result: Dictionary = _advance_trick_negation_chain(context)
	if not bool(retry_chain_result.get("pending", false)):
		_finish_simultaneous_negation_submission(context)
	else:
		event_scheduler.drain()
		_emit_state()
	return true


## 在失牌触发与装备事件完成后恢复同时无懈的获胜响应。
func _continue_simultaneous_negation_after_barrier(continuation_context: Dictionary) -> void:
	# 原无懈共享上下文；当前锦囊、目标与奇偶结果保持获胜响应提交时的快照。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	# 已消费的无懈实体或虚拟牌；恢复时不会重新参与同轮竞争。
	var counter_card: CardInstance = _deserialize_optional_response_card(continuation_context.get("response_card", {}) as Dictionary)
	if counter_card != null:
		_continue_consumed_simultaneous_negation(rule_context, int(continuation_context.get("responder_id", -1)), counter_card)


## 写入一张已经取得本轮结算权的无懈并开启下一轮；完整一轮无人响应时才恢复原锦囊。
func _continue_consumed_simultaneous_negation(context: Dictionary, responder_id: int, counter_card: CardInstance) -> void:
	context["negated"] = not bool(context.get("negated", false))
	_record_wuxie_chain_response(context, responder_id, counter_card)
	# 获胜响应者；等待期间离场时仍保留已经成立的响应事实，日志使用稳定玩家编号回退。
	var responder: PlayerState = state.get_player(responder_id)
	add_log("%s使用【无懈可击】，当前锦囊%s。" % [responder.display_name if responder != null else "玩家%d" % responder_id, "被抵消" if bool(context.get("negated", false)) else "恢复生效"])
	# 成功响应立即开启下一轮，允许任意玩家继续反无懈；新请求登记后再恢复调度栈。
	var chain_result: Dictionary = _advance_trick_negation_chain(context)
	if not bool(chain_result.get("pending", false)):
		_finish_simultaneous_negation_submission(context)
		return
	event_scheduler.drain()
	_emit_state()


## 完成一条不再等待下一轮的同时无懈链，并恢复原卡牌、判定或出牌阶段的唯一后续流程。
func _finish_simultaneous_negation_submission(context: Dictionary) -> void:
	state.simultaneous_response_display.clear()
	state.current_choice_request.clear()
	state.current_phase = str(context.get("resume_phase", "play"))
	_finish_trick_negation_chain(context, bool(context.get("negated", false)))
	_resume_settlement_pipeline()
	event_scheduler.drain()
	# 无懈链可能是出牌阶段最后一个异步窗口；原卡牌事件排空后重新建立唯一 chooseToUse 请求。
	if not state.game_over and state.current_phase == "play" and not has_pending_play_interaction():
		_begin_play_choice(state.current_player_id)
	_emit_state()
	if not state.game_over and state.current_phase == "play" and ai_coordinator.is_ai_controlled(state.current_player_id) and not has_pending_card_choice():
		_schedule_ai_action()


## 以系统放弃响应关闭本轮剩余请求；请求历史保留取消结果，但不会再次进入链恢复分支。
func _close_remaining_simultaneous_negation_choices() -> void:
	# 待关闭请求 ID 副本；提交运行时响应会修改原字典，因此不能直接遍历键视图。
	var remaining_request_ids: Array = _pending_negation_choices.keys().duplicate()
	for request_id_variant: Variant in remaining_request_ids:
		# 当前剩余请求 ID；可能已被更早的同步回调移除，提交前再次复核。
		var request_id: int = int(request_id_variant)
		if not _pending_negation_choices.has(request_id):
			continue
		# 当前剩余请求；系统只提交空选择并释放 token，不消费任何实体牌。
		var choice_data: Dictionary = _pending_negation_choices.get(request_id, {}) as Dictionary
		# 当前系统响应；actor 与 event 必须保持原请求归属才能通过运行时校验。
		var response: ChoiceResponse = ChoiceResponse.new(request_id, int(choice_data.get("runtime_event_id", -1)), int(choice_data.get("chooser_id", -1)), false)
		response.source = "system"
		event_scheduler.submit_choice(response, true)
		_cancel_paced_response_prompt(request_id)
		_pending_negation_choices.erase(request_id)


## 把本地玩家仍活动的并行请求写入单请求兼容快照；其他玩家候选继续只通过各自网络请求传递。
func _refresh_simultaneous_choice_snapshot() -> void:
	if state == null:
		return
	state.current_choice_request.clear()
	for choice_variant: Variant in _pending_negation_choices.values():
		# 当前私有请求；桌面兼容快照只选择本地玩家本人，避免最后登记的 AI 请求覆盖本地手牌交互。
		var choice_data: Dictionary = choice_variant as Dictionary
		if int(choice_data.get("chooser_id", -1)) != local_human_player_id:
			continue
		# 当前候选 UID；快照继续使用 ChoiceRequest 的 card_ids 字段，不复制完整牌面对象。
		var card_ids: Array[int] = []
		for candidate_variant: Variant in choice_data.get("candidates", []) as Array:
			card_ids.append(int((candidate_variant as Dictionary).get("uid", -1)))
		state.current_choice_request = {
			"request_id":int(choice_data.get("request_id", -1)),
			"event_id":int(choice_data.get("runtime_event_id", -1)),
			"actor_id":local_human_player_id,
			"choice_type":"respond",
			"prompt":str(choice_data.get("prompt", "")),
			"card_ids":card_ids,
			"selected_card_ids":[],
			"base_context":choice_data.get("context", {}) as Dictionary,
			"active_context":choice_data.get("context", {}) as Dictionary,
		}


## 返回指定观察者本人仍在等待提交的全部请求 ID；普通兼容选择与同时无懈共用一个稳定清单。
## 联机客户端按“本人当前请求”解释快照字段，而单槽位 current_choice_request 只能表达一条请求：
## 并行无懈同时为多名玩家登记请求时，其他玩家的请求编号会覆盖该槽位，客户端据此对账就会把
## 自己仍在等待的无懈窗口误判为已失效并清空，表现为询问一闪而过后既不能使用也无法放弃。
## 因此这里按观察者投射本人请求清单，使界面只在权威端确实不再等待该请求时才关闭窗口。
func _get_pending_choice_request_ids(viewer_id: int) -> Array[int]:
	# 待办请求 ID 清单；只包含该观察者自己的请求，其他玩家的私有请求不进入本快照。
	var request_ids: Array[int] = []
	if viewer_id < 0:
		return request_ids
	# 普通兼容选择；单槽位权威副本只属于其实际选择者，其他观察者继续只读观察。
	if not _pending_card_choice.is_empty() and int(_pending_card_choice.get("chooser_id", -1)) == viewer_id:
		request_ids.append(int(_pending_card_choice.get("request_id", -1)))
	# 同时无懈响应；同一轮可以为全部存活玩家并行登记，必须逐条比对本人才不会漏掉仍在等待的窗口。
	for choice_variant: Variant in _pending_negation_choices.values():
		# 当前私有请求；响应者不属于本观察者时不属于其待办清单。
		var choice_data: Dictionary = choice_variant as Dictionary
		if int(choice_data.get("chooser_id", -1)) == viewer_id:
			request_ids.append(int(choice_data.get("request_id", -1)))
	return request_ids


## 离线全角色控制中发布下一名仍待操作角色的无懈请求；普通离线与联机仍保持原并行发布语义。
func _publish_next_control_all_negation_choice() -> void:
	if not _control_all_characters_enabled or _pending_negation_choices.is_empty():
		return
	for choice_variant: Variant in _pending_negation_choices.values():
		var choice_data: Dictionary = choice_variant as Dictionary
		if int(choice_data.get("chooser_id", -1)) != local_human_player_id:
			continue
		card_choice_requested.emit(choice_data.duplicate(true))
		return


## 完成异步无懈链并恢复原目标；被抵消时只跳过当前目标，未抵消时从同一目标的效果入口继续。
func _finish_trick_negation_chain(context: Dictionary, final_negated: bool) -> void:
	# 原锦囊 UID；选择等待期间必须仍位于处理区。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	# 原锦囊实体；等待期间已经离开处理区时禁止恢复旧效果。
	var parent_card: CardInstance = _find_processing_card(parent_card_uid)
	if parent_card == null:
		return
	if final_negated:
		_emit_rule_timing("eventNeutralized", int(context.get("target_id", -1)), int(context.get("source_id", -1)), int(context.get("target_id", -1)), {"card_uid":parent_card_uid, "card_id":parent_card.definition_id, "negated":true})
		# 当前锦囊源码；需要避免重复无效目标的牌自行声明是否记录本回合AI记忆。
		var negated_definition: CardDefinition = GameDatabase.get_card_definition(parent_card.definition_id)
		if negated_definition != null and negated_definition.records_failed_ai_target_when_negated():
			record_failed_card_target(int(context.get("source_id", -1)), parent_card.definition_id, int(context.get("target_id", -1)))
	if bool(context.get("delayed_judgment", false)):
		_resolve_delayed_judgment_card(int(context.get("target_id", -1)), parent_card, final_negated)
		return
	if effect_resolver.continue_negation(context, final_negated):
		return
	if final_negated:
		_complete_active_card_target(parent_card_uid)
		return
	# 恢复键；效果执行器重新查询无懈可击时读取 false 并直接继续当前目标。
	var source_id: int = int(context.get("source_id", -1))
	var target_id: int = int(context.get("target_id", -1))
	var trick_id: String = str(context.get("trick_id", parent_card.definition_id))
	var resume_key: String = _negation_resume_key(parent_card_uid, source_id, target_id, trick_id)
	_negation_resume_results[resume_key] = false
	# 普通锦囊重新进入当前目标效果；延时锦囊无使用者时直接结束本次处理，避免重新放置同一判定牌。
	if source_id < 0:
		_finalize_processing_card(parent_card_uid)
		return
	_resume_active_card_target(parent_card_uid)


## 消耗并返回响应实体牌或虚拟牌；返回 null 表示玩家无法响应。
func consume_response_card(player_id: int, response_pattern: String) -> CardInstance:
	# 所有响应牌都通过统一选择请求；该入口保留给旧规则与扩展技能复用。
	var context: Dictionary = {"kind":"generic_response", "responder_id":player_id, "response_pattern":response_pattern}
	return request_response_card(player_id, response_pattern, "请选择是否响应%s。" % response_pattern, context)


## 返回一条响应选择中被点击装备的源码定义；普通手牌、失效装备或不支持当前模式时返回 null。
func _get_equipment_response_definition(choice_data: Dictionary, selected_uid: int) -> CardDefinition:
	# 选择者状态；装备必须仍位于其公开装备区。
	var player: PlayerState = state.get_player(int(choice_data.get("chooser_id", -1)))
	if player == null:
		return null
	# 当前响应模式集合；由权威请求创建，客户端不能自行扩展。
	var response_patterns: Array[String] = _string_array((choice_data.get("context", {}) as Dictionary).get("response_patterns", []) as Array)
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；UID 必须与选择完全一致。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card.uid != selected_uid:
			continue
		# 当前装备定义；再次调用候选钩子防止等待期间条件变化。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		# 当前装备所在槽位；本次结算整体停用的槽位不再是合法响应入口，迟到提交必须与候选阶段得到同一结论。
		if _read_ignored_equipment_slots(choice_data.get("context", {}) as Dictionary).has(_find_equipment_slot_for_card(player, equipment_card)):
			return null
		if equipment_definition != null and equipment_definition.can_offer_equipment_response(self, player.player_id, response_patterns):
			return equipment_definition
		return null
	return null


## 消耗若干已经由装备源码验证的普通手牌，并生成按材料聚合花色与颜色的虚拟响应牌。
## 装备转化的响应同样区分“使用”与“打出”，材料经处理区进入弃牌堆，不构成一次“弃置牌”动作。
func consume_virtual_equipment_response(player_id: int, equipment_uid: int, material_card_uids: Array[int], response_pattern: String, virtual_card_definition_id: String, log_message: String, response_context: Dictionary = {}) -> CardInstance:
	# 响应玩家；不存在或材料为空时不能生成虚拟牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or material_card_uids.is_empty() or response_pattern.is_empty() or virtual_card_definition_id.is_empty():
		return null
	# 装备转化响应采用的卡牌动作类别；八卦阵、丈八蛇矛等入口随所在响应窗口一起声明。
	var response_action: String = resolve_response_action(response_context, [response_pattern])
	# 参与响应的材料实体；移动前统一收集，用于推导本次虚拟牌的聚合花色与颜色。
	var material_cards: Array[CardInstance] = []
	for material_card_uid: int in material_card_uids:
		# 当前材料实体；不在普通手牌区时本次响应无效。
		var material_card: CardInstance = player.find_hand_card(material_card_uid)
		if material_card == null:
			return null
		material_cards.append(material_card)
	# 材料聚合结果；同花色视为该花色，同色不同花色保留颜色但无花色，异色无色。
	var material_aggregate: Dictionary = VirtualCard.resolve_material_aggregate(material_cards)
	_ensure_card_movement()
	# 响应事件；全部材料共享同一稳定父事件，便于回放还原顺序。
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "equipment_uid":equipment_uid, "material_card_uids":material_card_uids.duplicate(), "response_action":response_action}, {"responded":true, "virtual":true, "response_action":response_action})
	for material_card_uid: int in material_card_uids:
		# 当前材料；装备源码已验证来自普通手牌，移动前仍需重新查询防止旧选择。
		var material_card: CardInstance = player.find_hand_card(material_card_uid)
		_move_card_with_timings(material_card, "processing", -1, response_action, respond_event_id)
		# 处理区收尾；全部材料共享同一父事件，复用统一弃置入口不会把它们计入弃置批次。
		_move_to_discard(material_card, respond_event_id)
	player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":-1, "material_card_uids":material_card_uids.duplicate(), "equipment_uid":equipment_uid, "response_action":response_action})
	# 主体时机按动作类别分派，使装备转化的响应与实体响应牌对外表现完全一致。
	_emit_rule_timing(_get_card_action_main_timing(response_action), player_id, player_id, -1, {"card_uid":-1, "card_id":virtual_card_definition_id, "response_pattern":response_pattern, "response_action":response_action, "equipment_uid":equipment_uid, "material_card_uids":material_card_uids.duplicate(), "virtual":true, "respond_event_id":respond_event_id}, respond_event_id)
	if not log_message.is_empty():
		add_log(log_message)
	# 虚拟响应牌不继承任一材料点数；花色与颜色按全部材料聚合，与主动使用虚拟牌保持同一语义。
	var virtual_card: CardInstance = CardInstance.new(virtual_card_definition_id, str(material_aggregate.get("suit", "none")), 0)
	# 聚合颜色覆写；只有“某色无花色”时才写入，花色已能表达颜色时保持空值。
	var aggregated_color: String = str(material_aggregate.get("color", "none"))
	if virtual_card.suit == "none" and aggregated_color != "none":
		virtual_card.color_override = aggregated_color
	return virtual_card


## 旧版自动响应实现的独立内部端口；当前规则不得直接调用，保留用于兼容扩展技能调试。
func _consume_response_card_automatic(player_id: int, response_pattern: String) -> CardInstance:
	if state == null or state.game_over:
		return null
	# 响应玩家状态；死亡玩家不能使用或打出牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return null
	for card: CardInstance in player.get_playable_cards():
		# 当前手牌定义；response_pattern 允许普通与属性【杀】共享响应。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if _get_provided_response_pattern(definition) == response_pattern:
			# 是否为真实手牌；【银月枪】只能由回合外使用或打出的黑色手牌触发，木牛“粮”不算手牌。
			var was_hand_card: bool = player.hand.has(card)
			# 本次兼容响应的动作类别；同样按响应模式推导，【无懈可击】【桃】【酒】会被识别为“使用”。
			var response_action: String = resolve_response_action({}, [response_pattern])
			# 从手牌移出的响应牌；随后经处理区进入弃牌堆，与正式响应入口保持同一移动语义。
			var consumed: CardInstance = player.take_playable_card(card.uid)
			_move_played_card_to_discard(consumed, response_action, state.current_event_id, player_id)
			# 兼容入口沿用 describe_card 的旧日志格式，只在动词上区分“使用”与“打出”。
			add_log("%s%s%s。" % [player.display_name, _get_card_action_verb(response_action), describe_card(consumed)])
			_notify_equipment_card_consumed(player.player_id, consumed, was_hand_card)
			return consumed

	# 兼容装备响应；每件装备源码自行声明模式、材料数量、判定与虚拟牌结果。
	var response_patterns: Array[String] = [response_pattern]
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体与定义；不支持本次响应模式时跳过。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition == null or not equipment_definition.can_offer_equipment_response(self, player_id, response_patterns):
			continue
		# 自动材料；兼容入口按普通手牌顺序取得装备声明数量。
		var material_card_uids: Array[int] = []
		var material_count: int = equipment_definition.get_equipment_response_material_count()
		if player.hand.size() < material_count:
			continue
		for material_index: int in range(material_count):
			material_card_uids.append(player.hand[material_index].uid)
		if equipment_definition.validate_equipment_response_materials(self, player_id, equipment_card.uid, material_card_uids).is_empty():
			return equipment_definition.consume_equipment_response(self, player_id, equipment_card.uid, response_patterns, material_card_uids)
	return null


## 处理普通锦囊的【无懈可击】响应链；附加上下文用于阶段型锦囊在异步响应后回到原步骤。
func resolve_trick_negation(source_id: int, target_id: int, trick_id: String, continuation_context: Dictionary = {}) -> bool:
	if state == null or state.game_over:
		return false
	# 附加上下文指定的原锦囊 UID；五谷展示牌等处理区附属牌存在时必须优先使用稳定 UID 定位父牌。
	var parent_card_uid_hint: int = int(continuation_context.get("parent_card_uid", -1))
	# 当前被响应锦囊；普通锦囊和延时锦囊结算时都位于公共处理区。
	var parent_card: CardInstance = _find_processing_card(parent_card_uid_hint) if parent_card_uid_hint >= 0 else _find_processing_card_by_definition(trick_id)
	# 当前锦囊目标是否被直击；其本人不进入无懈名单，但其他角色仍可对该锦囊正常使用无懈。
	var target_response_blocked: bool = parent_card != null and is_card_target_direct_hit(parent_card.uid, target_id)
	# 恢复结果键；本地玩家提交后重新进入效果执行器时只读取一次，避免再次弹出同一询问。
	var resume_key: String = _negation_resume_key(parent_card.uid if parent_card != null else -1, source_id, target_id, trick_id)
	if _negation_resume_results.has(resume_key):
		var resumed_negated: bool = bool(_negation_resume_results[resume_key])
		_negation_resume_results.erase(resume_key)
		return resumed_negated
	# 当前抵消状态；每使用一张【无懈可击】翻转一次，最终为 true 表示原锦囊被抵消。
	var negated: bool = false
	# 本次目标独立的响应顺序；无名杀在每个 useCardToBegin 目标事件上分别建立无懈链，多目标牌不会共享一次抵消结果。
	var response_order_ids: Array[int] = []
	for player: PlayerState in _get_alive_players_in_action_order(state.current_player_id):
		if target_response_blocked and player.player_id == target_id:
			continue
		response_order_ids.append(player.player_id)
	# 无懈响应上下文；全部字段可序列化，异步选择后能够从准确响应者与目标继续。
	var negate_context: Dictionary = {
		"kind":"trick_negation",
		"parent_card_uid":parent_card.uid if parent_card != null else -1,
		"source_id":source_id,
		"target_id":target_id,
		"trick_id":trick_id,
		"negated":negated,
		"response_order_ids":response_order_ids,
		"response_index":0,
		"wuxie_response_results":[],
		"root_event_id":state.current_event_id,
		# 动作类别显式声明为“使用”：【无懈可击】只有“使用”一种合法动作，不是“打出”也不是“弃置”。
		"response_action":CARD_ACTION_USE,
	}
	for context_key_variant: Variant in continuation_context.keys():
		# 附加上下文字段名；仅复制可序列化阶段信息，不覆盖当前无懈响应的核心归属字段。
		var context_key: String = str(context_key_variant)
		if not negate_context.has(context_key):
			negate_context[context_key] = continuation_context[context_key_variant]
	# 链推进结果；正式对局通常在首个可响应角色处暂停，无人持有无懈时同步返回未抵消。
	var chain_result: Dictionary = _advance_trick_negation_chain(negate_context)
	return bool(chain_result.get("negated", false))


## 构造无懈可击恢复键；所有字段均为可序列化值，支持同名牌对不同目标分别结算。
func _negation_resume_key(parent_card_uid: int, source_id: int, target_id: int, trick_id: String) -> String:
	return "%d:%d:%d:%s" % [parent_card_uid, source_id, target_id, trick_id]


## 按定义 ID 查找处理区中的原锦囊；同一同步结算栈只会有一张对应父牌。
func _find_processing_card_by_definition(definition_id: String) -> CardInstance:
	for processing_card: CardInstance in state.processing_area:
		if processing_card.definition_id == definition_id:
			return processing_card
	return null


## 返回当前是否有一条判定正在等待判定前技能或其后续选择完成；内容脚本只读取该布尔状态，不取得内部请求字典。
func has_pending_judgment_request() -> bool:
	return not _pending_judgment_request.is_empty()


## 建立一次可暂停判定；judgment_ai_context 公开有利/不利条件与角色价值，供【戏法】等改判定 AI 作阵营决策。
## continuation 只保存 skill 或 card 接收者的稳定 ID 与基础上下文；同步完成时直接返回判定牌，曾暂停时由对应 continue_judgment 恢复。
func request_judgment(player_id: int, reason: String, continuation: Dictionary = {}, judgment_ai_context: Dictionary = {}) -> CardInstance:
	if state == null or state.game_over or has_pending_judgment_request():
		return null
	# 判定玩家；不存在或已经离场时不能创建判定事件。
	# 补充校验：已经死亡的角色同样不能建立新的判定事件。
	var judgment_player: PlayerState = state.get_player(player_id)
	if judgment_player == null or not judgment_player.alive or judgment_player.out_of_game:
		return null
	_judgment_request_sequence += 1
	# 判定前公开数据；改判定技能只能依据本字典与牌堆观看候选决策，不能读取调用方局部对象。
	var judge_before_data: Dictionary = {
		"reason":reason,
		"judgment_request_id":_judgment_request_sequence,
		"judgment_ai_context":judgment_ai_context.duplicate(true),
	}
	# 活动请求；stage 指向当前规则时机完成后的下一步，was_paused 决定是否通过接收者回调恢复原结算。
	_pending_judgment_request = {
		"request_id":_judgment_request_sequence,
		"player_id":player_id,
		"reason":reason,
		"stage":"after_judge_before",
		"event_data":judge_before_data.duplicate(true),
		"continuation":continuation.duplicate(true),
		"was_paused":false,
		"parent_event_id":_current_rule_parent_event_id(),
	}
	# 判定前与开始时机；取消后不从牌堆取牌，也不创建中央判定展示。
	_pending_judgment_rule_event = _emit_rule_timing("judgeBefore", player_id, player_id, player_id, judge_before_data)
	if has_pending_card_choice():
		_pending_judgment_request["was_paused"] = true
		return null
	return _advance_pending_judgment_request()


## 执行一次判定并将判定牌置入弃牌堆；返回牌对象供调用方读取花色与点数。
## 判定牌遵循无名杀 judge -> judgeResult -> cardsDiscard 顺序，并在判定者位置公开展示后由同一表现接管弃牌动画。
## 兼容旧同步调用的判定入口；没有判定前交互时立即返回结果，出现选择时返回 null 并由请求状态机完成牌面与历史收尾。
func perform_judgment(player_id: int, reason: String) -> CardInstance:
	return request_judgment(player_id, reason)


## 在最内层判定前触发续列完成后推进 judgeBegin 或实际翻牌；返回值只供未暂停的同步调用栈读取。
func _advance_pending_judgment_request() -> CardInstance:
	if _pending_judgment_request.is_empty() or state == null or state.game_over or has_pending_card_choice():
		return null
	# 当前稳定请求副本；每个阶段完成后都会把下一阶段写回唯一活动字典。
	var request: Dictionary = _pending_judgment_request
	# 当前判定玩家；等待期间死亡或离场时以空判定结果结束并恢复原调用者。
	var player_id: int = int(request.get("player_id", -1))
	# 当前判定玩家状态；不能继续判定时按取消结果通知异步接收者。
	var judgment_player: PlayerState = state.get_player(player_id)
	if judgment_player == null or not judgment_player.alive or judgment_player.out_of_game:
		return _complete_pending_judgment_request(null)
	# 当前阶段；after_judge_before 先检查判定前时机，再进入 judgeBegin。
	var stage: String = str(request.get("stage", "after_judge_before"))
	if stage == "after_judge_before":
		if _pending_judgment_rule_event != null and (_pending_judgment_rule_event.cancelled or _pending_judgment_rule_event.neutralized):
			return _complete_pending_judgment_request(null)
		# judgeBegin 继承 judgeBefore 最终数据；其中包含判定目的与通用 AI 结果接口。
		var begin_data: Dictionary = _pending_judgment_rule_event.data.duplicate(true) if _pending_judgment_rule_event != null else (request.get("event_data", {}) as Dictionary).duplicate(true)
		_pending_judgment_request["stage"] = "after_judge_begin"
		_pending_judgment_request["event_data"] = begin_data.duplicate(true)
		_pending_judgment_rule_event = _emit_rule_timing("judgeBegin", player_id, player_id, player_id, begin_data)
		if has_pending_card_choice():
			_pending_judgment_request["was_paused"] = true
			return null
		stage = "after_judge_begin"
	if stage == "after_judge_begin":
		if _pending_judgment_rule_event != null and (_pending_judgment_rule_event.cancelled or _pending_judgment_rule_event.neutralized):
			return _complete_pending_judgment_request(null)
		# 实际判定牌；judgeBegin 已全部完成，因此此处翻开的必然是改判定技能最终保留在牌堆顶的牌。
		var judgment_card: CardInstance = _draw_and_finish_judgment_card(player_id, str(request.get("reason", "判定")), int(request.get("parent_event_id", -1)))
		return _complete_pending_judgment_request(judgment_card)
	return null


## 翻开牌堆顶判定牌并完成 judge、judgeResult、弃牌、judgeEnd 与 judgeAfter；调用前必须保证 Before/Begin 已完整结束。
func _draw_and_finish_judgment_card(player_id: int, reason: String, parent_event_id: int) -> CardInstance:
	if state.draw_pile.is_empty():
		_reshuffle_discard_pile()
	if state.draw_pile.is_empty():
		_end_match_as_draw("deck_empty_judgment")
		return null
	# 判定玩家；日志只读取当前显示名，等待期间失效会在推进入口提前结束。
	var judgment_player: PlayerState = state.get_player(player_id)
	# 判定父事件；判定牌移动、结果和后置弃牌都通过该 ID 建立可回放关联。
	var judgment_event_id: int = _record_runtime_event("judge", "judgment", {"player_id":player_id, "reason":reason}, {}, parent_event_id)
	_ensure_card_movement()
	# 牌堆顶判定牌；判定生效后直接进入弃牌堆。
	# 牌堆顶判定牌；先进入公共处理区并公开展示，判定结果记录后再进入弃牌堆。
	var judgment_card: CardInstance = state.draw_pile.back()
	_move_card_with_timings(judgment_card, "processing", -1, "judge", judgment_event_id)
	# 判定牌产生时机；技能可读取牌面稳定字段并在 judgeFixing 前记录修改结果。
	var judge_data: Dictionary = {"player_id":player_id, "reason":reason, "card_uid":judgment_card.uid, "card_id":judgment_card.definition_id, "suit":judgment_card.suit, "rank":judgment_card.rank, "color":judgment_card.get_color()}
	_emit_rule_timing("judge", player_id, player_id, player_id, judge_data, judgment_event_id)
	# 判定牌属于公共牌堆而非判定角色打出的牌；来源使用-1让界面直接从中央弃牌锚点出现。
	_request_card_presentation(judgment_card, -1, [], "judge", judgment_event_id, true)
	add_log("%s的%s判定牌为%s。" % [judgment_player.display_name, format_log_reason(reason), describe_card(judgment_card)])
	_emit_rule_timing("judgeFixing", player_id, player_id, player_id, judge_data, judgment_event_id)
	_record_runtime_event("judgeResult", "judgment_result", {"player_id":player_id, "reason":reason, "card_uid":judgment_card.uid}, {"suit":judgment_card.suit, "rank":judgment_card.rank, "color":judgment_card.get_color()}, judgment_event_id)
	_move_to_discard(judgment_card, judgment_event_id)
	_emit_rule_timing("judgeEnd", player_id, player_id, player_id, judge_data, judgment_event_id)
	_emit_rule_timing("judgeAfter", player_id, player_id, player_id, judge_data, judgment_event_id)
	return judgment_card


## 完成当前判定请求并在确实发生过暂停时交回稳定技能或卡牌接收者；同步调用者直接使用返回的 CardInstance。
func _complete_pending_judgment_request(judgment_card: CardInstance) -> CardInstance:
	# 完成请求副本；先清空活动状态，接收者后续再次发起判定时不会被旧请求拒绝。
	var completed_request: Dictionary = _pending_judgment_request.duplicate(true)
	# 是否曾因选择暂停；只有异步路径需要回调，未暂停路径由 request_judgment 的返回值继续执行。
	var was_paused: bool = bool(completed_request.get("was_paused", false))
	_clear_pending_judgment_request()
	if was_paused:
		_dispatch_judgment_continuation(completed_request.get("continuation", {}) as Dictionary, judgment_card)
	return judgment_card


## 把异步判定结果交回创建请求的技能或卡牌定义；只按稳定 ID 定位当前实例，不保存 Callable 或内容对象引用。
func _dispatch_judgment_continuation(continuation: Dictionary, judgment_card: CardInstance) -> void:
	# 接收者类型；skill 定位本局技能实例，card 定位无状态卡牌源码定义。
	var receiver_type: String = str(continuation.get("receiver_type", ""))
	# 业务上下文；牌 UID、目标和响应信息均使用基础可序列化值。
	var context: Dictionary = (continuation.get("context", {}) as Dictionary).duplicate(true)
	if receiver_type == "skill":
		# 技能持有者与稳定技能 ID；换将或失去技能后旧判定结果安全失效。
		var skill_owner_id: int = int(continuation.get("skill_owner_id", -1))
		# 当前运行时技能实例；角色代次必须与请求建立时一致。
		var skill: SkillDefinition = get_skill_instance(skill_owner_id, str(continuation.get("skill_id", "")))
		if skill != null and skill.matches_character_generation(int(continuation.get("skill_character_generation", -1))) and skill.can_use_effect(bool(context.get("locked_skill_segment", false))):
			skill.continue_judgment(context, judgment_card)
		return
	if receiver_type == "card":
		# 卡牌或装备源码定义；其自身根据 context.kind 复核父牌、目标和当前区域。
		var definition: CardDefinition = GameDatabase.get_card_definition(str(continuation.get("card_definition_id", "")))
		if definition != null:
			definition.continue_judgment(self, context, judgment_card)


## 清空当前判定运行时；重新开局、换回合与终局均调用本入口，防止旧选择恢复到新状态。
func _clear_pending_judgment_request() -> void:
	_pending_judgment_request.clear()
	_pending_judgment_rule_event = null


## 将处理区中的装备放入对应槽位，并处理旧装备离开时的效果。
func equip_from_processing(player_id: int, card: CardInstance) -> void:
	# 装备目标玩家；装备牌默认只能对自己使用。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		_move_to_discard(card)
		return
	# 装备卡定义；slot 决定唯一装备槽。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 装备槽名称；配置表保证非空。
	var slot: String = str(definition.get("slot", ""))
	if player.is_equipment_slot_abolished(slot):
		_move_to_discard(card)
		return
	if player.equipment.has(slot):
		_discard_equipment_slot(player_id, slot, true)
	_ensure_card_movement()
	# 装备实体的最终移动结果；前置时机取消或目标栏位在结算中被废除时不得安装持续效果。
	var equipment_move: CardMoveEvent = _move_card_with_timings(card, "equipment", player_id, "equip", state.current_event_id, slot)
	if equipment_move == null:
		return
	_install_card_runtime(card, player_id)
	# 装备效果音；按装备槽位选用武器、防具、进攻马、防御马与宝物五套音效之一，未登记槽位不发声。
	request_effect_voice(player_id, _resolve_equipment_effect_id(slot))
	add_log("%s装备了%s。" % [format_player_state_log_name(player), format_card_log_name(card)])


## 将处理区中的延时锦囊放入目标判定区。
func place_delayed_trick(target_id: int, card: CardInstance) -> void:
	# 延时锦囊目标；合法性层已保证其存活且判定区无同名牌。
	var target: PlayerState = state.get_player(target_id)
	if target == null or target.judgment_area_abolished:
		_move_to_discard(card)
		return
	_ensure_card_movement()
	# 延时锦囊的最终移动结果；前置时机取消或判定区在结算中被废除时不得记录虚假的进入日志。
	var judgment_move: CardMoveEvent = _move_card_with_timings(card, "judgment", target_id, "add_judge", state.current_event_id)
	if judgment_move == null:
		return
	add_log("%s的判定区加入了%s。" % [target.display_name, describe_card(card)])


## 请求来源角色自主选择并弃置目标区域的一张牌；候选固定按手牌、装备、判定区排列。
func discard_one_from_player(_source_id: int, target_id: int, parent_card_uid: int = -1) -> void:
	# 目标全部区域牌；不可见手牌只公开牌背，受保护装备仍保留暗置展示所需的只读牌面。
	var display_candidates: Array[Dictionary] = _build_player_zone_candidates(_source_id, target_id)
	# 实际可弃置候选；目标技能拒绝的防具或宝物不会进入权威提交集合。
	var candidates: Array[Dictionary] = []
	for candidate: Dictionary in display_candidates:
		# 当前候选实体；按区域和槽位复核目标技能的弃置保护规则。
		var candidate_card: CardInstance = _find_player_zone_card(target_id, int(candidate.get("uid", -1)))
		if can_discard_player_card(_source_id, target_id, candidate_card, str(candidate.get("zone", "")), str(candidate.get("slot", ""))):
			candidates.append(candidate)
	# 本次选择上下文；人类稍后提交时据此恢复过河拆桥结算并收尾处理区卡牌。
	var context: Dictionary = {"kind":"discard_target", "source_id":_source_id, "target_id":target_id, "parent_card_uid":parent_card_uid, "display_candidates":display_candidates}
	# 选择结果；AI 会通过 choose_cards 同步返回，人类则保持请求挂起。
	var selected_uids: Array[int] = request_card_choice(_source_id, "选择弃置牌", "请选择目标区域内的一张牌", candidates, 1, 1, false, context)
	if has_pending_card_choice() or selected_uids.is_empty():
		return
	_discard_selected_player_card(target_id, selected_uids[0], _source_id)


## 请求来源角色自主选择并获得目标区域的一张牌；所有区域共用同一个选择组件。
func take_one_from_player(source_id: int, target_id: int, parent_card_uid: int = -1) -> void:
	# 目标区域候选；顺序与界面要求一致，手牌位于最上方。
	var candidates: Array[Dictionary] = _build_player_zone_candidates(source_id, target_id)
	# 本次选择上下文；延迟提交后用于恢复顺手牵羊结算。
	var context: Dictionary = {"kind":"steal_target", "source_id":source_id, "target_id":target_id, "parent_card_uid":parent_card_uid}
	# 选择结果；AI 与人类都只能从本次候选 UID 中提交。
	var selected_uids: Array[int] = request_card_choice(source_id, "选择获得牌", "请选择要获得的一张牌", candidates, 1, 1, false, context)
	if has_pending_card_choice() or selected_uids.is_empty():
		return
	_take_selected_player_card(source_id, target_id, selected_uids[0])


## 返回来源角色当前可以弃置的目标区域候选；目标技能保护规则在生成候选与最终移动时各复核一次。
func get_opportunity_discard_candidates(source_id: int, target_id: int) -> Array[Dictionary]:
	# 目标全部区域候选；隐藏手牌保留牌背语义，公开装备与判定牌保留完整牌面。
	var display_candidates: Array[Dictionary] = _build_player_zone_candidates(source_id, target_id)
	# 实际可弃置候选；任一保护技能拒绝的牌不会进入结果。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in display_candidates:
		# 当前候选实体；用于读取真实区域和装备槽并执行技能保护纯查询。
		var candidate_card: CardInstance = _find_player_zone_card(target_id, int(candidate.get("uid", -1)))
		if can_discard_player_card(source_id, target_id, candidate_card, str(candidate.get("zone", "")), str(candidate.get("slot", ""))):
			result.append(candidate.duplicate(true))
	return result


## 弃置目标区域内玩家明确选择的多张牌；每张独立复核位置与保护规则，返回实际弃置数量。
func discard_selected_player_cards(target_id: int, selected_uids: Array[int], source_id: int = -1) -> int:
	# 弃置批次；弃置主体是实际失去牌的目标角色，而不是下达弃置要求的来源角色。
	_begin_discard_batch(target_id, "discard_selected_player_cards")
	# 实际弃置数量；等待期间已经离区或新受保护的UID不会计入。
	var discarded_count: int = 0
	for selected_uid: int in selected_uids:
		if _discard_selected_player_card(target_id, selected_uid, source_id):
			discarded_count += 1
	_end_discard_batch()
	return discarded_count


## 将目标区域内一张明确选择的牌交给来源角色；公开包装保留内部统一移牌、装备离开与动画逻辑。
func take_selected_player_card(source_id: int, target_id: int, card_uid: int) -> bool:
	return _take_selected_player_card(source_id, target_id, card_uid)


## 构建一名角色可选择的手牌、装备和判定牌快照；顺序严格为手牌区、装备区、判定区。
func _build_player_zone_candidates(viewer_id: int, target_id: int, include_hand: bool = true, include_equipment: bool = true, include_judgment: bool = true) -> Array[Dictionary]:
	# 候选结果；每项包含稳定 UID、区域和可见性，供同一选择组件分区展示。
	var result: Array[Dictionary] = []
	# 被查看目标；无效 ID 返回空候选。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		return result
	if include_hand:
		for hand_card: CardInstance in target.hand:
			# 手牌是否对选择者可见；本人选择自己的牌时展示正面，其他角色默认只见牌背。
			var hand_visible: bool = viewer_id == target_id
			result.append(_serialize_choice_candidate(hand_card, target_id, "hand", hand_visible))
	if include_equipment:
		for slot: String in ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]:
			if target.equipment.has(slot):
				result.append(_serialize_choice_candidate(target.equipment[slot] as CardInstance, target_id, "equipment", true, slot))
	if include_judgment:
		for judgment_card: CardInstance in target.judgment_area:
			result.append(_serialize_choice_candidate(judgment_card, target_id, "judgment", true))
	return result


## 按稳定 UID 查找目标手牌、装备或判定区中的实体；只读查询不改变任何区域顺序。
func _find_player_zone_card(target_id: int, card_uid: int) -> CardInstance:
	# 目标玩家；不存在时没有可查询区域。
	var target: PlayerState = state.get_player(target_id) if state != null else null
	if target == null:
		return null
	# 普通手牌；优先命中可避免遍历公开装备。
	var hand_card: CardInstance = target.find_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for equipment_variant: Variant in target.equipment.values():
		# 当前装备实体；UID匹配时返回原对象供保护技能纯查询。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card != null and equipment_card.uid == card_uid:
			return equipment_card
	for judgment_card: CardInstance in target.judgment_area:
		if judgment_card.uid == card_uid:
			return judgment_card
	return null


## 把实体牌转换为选择候选；隐藏候选只保留 UID 和牌背语义，不携带牌面定义。
func _serialize_choice_candidate(card: CardInstance, owner_id: int, zone: String, visible: bool, slot: String = "") -> Dictionary:
	# 可见牌面数据；隐藏手牌不发送定义、花色和点数。
	var card_data: Dictionary = card.to_dict() if visible else {"uid":card.uid, "definition_id":"", "suit":"none", "rank":0, "zone":zone, "owner_id":owner_id}
	return {"uid":card.uid, "owner_id":owner_id, "zone":zone, "slot":slot, "visible":visible, "card_data":card_data}


## 弃置目标区域内指定 UID 的牌；区域查找基于实体 UID，不依赖候选数组下标。
func _discard_selected_player_card(target_id: int, card_uid: int, source_id: int = -1) -> bool:
	# 目标玩家；无效目标不能移动牌。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		return false
	# 当前实体与区域；外部弃置必须在移动前再次通过保护技能校验，防止旧候选或随机弃置绕过规则。
	var selected_card: CardInstance = _find_player_zone_card(target_id, card_uid)
	var selected_zone: String = selected_card.zone if selected_card != null else ""
	var selected_slot: String = ""
	for slot_variant: Variant in target.equipment.keys():
		# 当前装备槽；仅在实体UID匹配时提供给保护技能判断牌型。
		var slot_name: String = str(slot_variant)
		var slot_card: CardInstance = target.equipment[slot_name] as CardInstance
		if slot_card != null and slot_card.uid == card_uid:
			selected_slot = slot_name
			break
	if not can_discard_player_card(source_id, target_id, selected_card, selected_zone, selected_slot):
		return false
	# 手牌候选；自主弃牌和拆牌都从实际区域移除后进入统一弃牌动画入口。
	var hand_card: CardInstance = target.take_hand_card(card_uid)
	if hand_card != null:
		_move_to_discard(hand_card)
		return true
	for slot_variant: Variant in target.equipment.keys():
		# 当前装备槽；UID 匹配时复用装备离开效果与弃牌移动。
		var slot: String = str(slot_variant)
		var equipment_card: CardInstance = target.equipment[slot] as CardInstance
		if equipment_card.uid == card_uid:
			_discard_equipment_slot(target_id, slot, true)
			return true
	for judgment_index: int in range(target.judgment_area.size()):
		if target.judgment_area[judgment_index].uid == card_uid:
			_move_to_discard(target.judgment_area.pop_at(judgment_index))
			return true
	return false


## 将目标区域内指定 UID 的牌交入来源角色手牌，并发出从目标武将到获得者的移动动画。
func _take_selected_player_card(source_id: int, target_id: int, card_uid: int) -> bool:
	# 获得者状态；所有取得牌最终进入其手牌。
	var source: PlayerState = state.get_player(source_id)
	# 失去牌的目标状态；无效玩家直接失败。
	var target: PlayerState = state.get_player(target_id)
	if source == null or target == null:
		return false
	# 实际取得牌；按 UID 搜索三个区域，搜索顺序不影响玩家已经作出的选择。
	var taken_card: CardInstance = target.find_hand_card(card_uid)
	if taken_card == null:
		for slot_variant: Variant in target.equipment.keys():
			var slot: String = str(slot_variant)
			var equipment_card: CardInstance = target.equipment[slot] as CardInstance
			if equipment_card.uid == card_uid:
				taken_card = equipment_card
				_on_equipment_lost(target, taken_card, true)
				break
	if taken_card == null:
		for judgment_card: CardInstance in target.judgment_area:
			if judgment_card.uid == card_uid:
				taken_card = judgment_card
				break
	if taken_card == null:
		return false
	# 移动前区域；表现层据此从目标角色锚点开始飞行。
	# 该来源现由 CardMovementService 在移动前写入统一事件，避免获得牌出现两次动画。
	_ensure_card_movement()
	_move_card_with_timings(taken_card, "hand", source_id, "gain", state.current_event_id, "", [source_id])
	add_log("%s获得了%s的%s。" % [source.display_name, target.display_name, format_gained_card_log_name(taken_card)])
	return true


## 恢复延迟的过河拆桥或顺手牵羊选择，并在效果完成后把原锦囊移入弃牌堆。
func _continue_target_card_choice(context: Dictionary, selected_uids: Array[int], is_steal: bool) -> void:
	if selected_uids.is_empty():
		return
	# 先完成移动及其子技能，再推进父目标；完成步骤不通过全局有无选择推测。
	var steps: Array[Callable] = [_apply_target_card_choice, _finish_target_card_choice]
	run_rule_sequence(steps, {"rule_context":context, "selected_uids":selected_uids, "is_steal":is_steal})


## 区域选择主体；恢复时由移动入口重新校验实体UID和所在区域。
func _apply_target_card_choice(sequence: RuleStepSequence) -> void:
	# 已接受的选择上下文；父牌、来源和目标均使用稳定ID。
	var context: Dictionary = sequence.context.rule_context
	# 来源角色 ID；顺手牵羊需要把牌交给该角色。
	var source_id: int = int(context.get("source_id", -1))
	# 目标角色 ID；所选 UID 必须仍位于其区域。
	var target_id: int = int(context.get("target_id", -1))
	# 来源有效性复核；等待选择期间来源阵亡时【过河拆桥】【顺手牵羊】已经整体失效，
	# 既不能继续移动目标区域的牌，更不能把牌交给已经阵亡的角色；牌仍由后续步骤正常收尾进弃牌堆。
	if resolve_card_effect_source_id(source_id) < 0:
		return
	if bool(sequence.context.is_steal):
		_take_selected_player_card(source_id, target_id, int(sequence.context.selected_uids[0]))
	else:
		_discard_selected_player_card(target_id, int(sequence.context.selected_uids[0]), source_id)


## 区域移动触发的技能与装备事件必须先结算；父锦囊目标完成步骤只登记一次稳定续接点。
func _finish_target_card_choice(sequence: RuleStepSequence) -> void:
	# 原父牌UID；完成入口会忽略已经失效的牌。
	var parent_card_uid: int = int(sequence.context.rule_context.get("parent_card_uid", -1))
	_complete_active_card_target(parent_card_uid)


## 弃置指定手牌 UID；返回是否成功，供火攻与装备技能复用。
func discard_card_from_hand(player_id: int, card_uid: int) -> bool:
	# 失去手牌的玩家；无效玩家直接失败。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false
	# 从手牌移出的实体牌；未找到时返回 null。
	var card: CardInstance = player.take_hand_card(card_uid)
	if card == null:
		return false
	_move_to_discard(card)
	return true


## 弃置指定角色当前全部普通手牌；使用UID副本逐张移动，等待期间新增手牌不会被追溯加入本次效果。
func discard_all_hand_cards(player_id: int, source_id: int = -1, reason: String = "discard_all_hand") -> int:
	# 弃牌目标；死亡或无效角色没有可移动手牌。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return 0
	# 本次手牌UID副本；实体移动期间原数组会缩短，不能直接遍历并删除。
	var hand_uids: Array[int] = []
	for hand_card: CardInstance in player.hand:
		hand_uids.append(hand_card.uid)
	# 弃置批次；整批手牌共享一个批次事件，使“一次弃置多张”的技能能够整批判定黑红与花色等信息。
	_begin_discard_batch(player_id, reason)
	# 实际弃置数量；每张仍通过标准手牌弃置端口进入移动时机与弃牌堆。
	var discarded_count: int = 0
	for card_uid: int in hand_uids:
		if discard_card_from_hand(player_id, card_uid):
			discarded_count += 1
	_end_discard_batch()
	if discarded_count > 0:
		add_log("%s因%s弃置了全部手牌。" % [format_player_state_log_name(player), format_log_reason(reason)])
		if source_id >= 0:
			observe_skill_identity_behavior(source_id, [player_id], {"target_result":-1.0})
	return discarded_count


## 将一名其他角色当前全部普通手牌依次交给获得者；手牌副本锁定结算开始时的范围，进入手牌的牌不会再次转移。
func gain_all_hand_cards(receiver_id: int, target_id: int, reason: String = "gain_all_hand") -> int:
	# 获得者与失去牌角色；同一角色或无效角色不产生无意义的同区域移动。
	var receiver: PlayerState = state.get_player(receiver_id) if state != null else null
	# 目标角色；死亡角色的遗留牌区应由死亡流程处理，不通过普通获得效果移动。
	var target: PlayerState = state.get_player(target_id) if state != null else null
	if receiver == null or target == null or receiver_id == target_id or not receiver.alive or receiver.out_of_game:
		return 0
	# 本次目标手牌UID副本；每张牌仍通过统一获得端口移动并裁剪私有信息。
	var hand_uids: Array[int] = []
	for hand_card: CardInstance in target.hand:
		hand_uids.append(hand_card.uid)
	# 实际获得数量；等待期间已经离开目标手牌区的实体安全跳过。
	var gained_count: int = 0
	for card_uid: int in hand_uids:
		if _take_selected_player_card(receiver_id, target_id, card_uid):
			gained_count += 1
	if gained_count > 0:
		add_log("%s因%s获得了%s的全部手牌。" % [format_player_state_log_name(receiver), format_log_reason(reason), format_player_state_log_name(target)])
	return gained_count


## 弃置一张可使用牌，可来自普通手牌或木牛流马下的“粮”。
func _discard_playable_card(player_id: int, card_uid: int) -> bool:
	# 失去牌的玩家；无效 ID 直接失败。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false
	# 从统一牌源移出的实体牌；找不到时返回 null。
	var card: CardInstance = player.take_playable_card(card_uid)
	if card == null:
		return false
	_move_to_discard(card)
	return true


## 弃置玩家区域内至多指定数量的牌；选择顺序为手牌、装备、判定区。
func discard_n_from_player(player_id: int, count: int) -> void:
	# 弃置批次；整次“弃置至多N张”共享一个批次事件。必须无条件开启，嵌套弃置才能各自成批。
	_begin_discard_batch(player_id, "discard_n_from_player")
	for _index: int in range(maxi(count, 0)):
		# 当前玩家状态；每次循环重新读取区域数量。
		var player: PlayerState = state.get_player(player_id)
		if player == null:
			break
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand[0].uid)
		elif not player.equipment.is_empty():
			_discard_equipment_slot(player_id, str(player.equipment.keys()[0]), true)
		elif not player.judgment_area.is_empty():
			_move_to_discard(player.judgment_area.pop_front())
		else:
			# 无可弃置区域时结束循环而不是直接返回，保证批次栈正常收尾。
			break
	_end_discard_batch()


## 返回玩家手牌、装备与判定区的可弃置牌总数。
func get_discardable_count(player_id: int) -> int:
	# 指定玩家状态；不存在时数量为0。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return player.hand.size() + player.equipment.size() + player.judgment_area.size()


## 返回指定角色当前普通手牌UID副本；交换手牌时先锁定原集合，后续获得的新牌不追溯加入。
func get_hand_card_uids(player_id: int) -> Array[int]:
	# 手牌UID结果；不存在的角色返回空数组。
	var result: Array[int] = []
	# 指定角色；只读取当前普通手牌，不包含木牛“粮”。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return result
	for card: CardInstance in player.hand:
		result.append(card.uid)
	return result


## 将权威状态中任意牌堆、弃牌堆或角色区域实体按UID交入指定角色手牌；装备离区效果与私有知识由统一移动端口处理。
func gain_card_to_hand_by_uid(receiver_id: int, card_uid: int, reason: String = "gain_card", allow_out_of_game: bool = false) -> bool:
	# 获得者；死亡角色不能获得牌，离场角色仅在明确模式效果下允许。
	var receiver: PlayerState = state.get_player(receiver_id) if state != null else null
	if receiver == null or not receiver.alive or (receiver.out_of_game and not allow_out_of_game):
		return false
	# 实体当前位置；包含牌对象、区域、原持有者和装备槽，等待期间变化会使本次UID安全失败。
	var location: Dictionary = _find_card_location_by_uid(card_uid)
	# 待获得实体；处理区中的牌属于未完成规则，不允许被独立获得效果截走。
	var card: CardInstance = location.get("card") as CardInstance
	var source_zone: String = str(location.get("zone", ""))
	var source_owner_id: int = int(location.get("owner_id", -1))
	if card == null or source_zone.is_empty() or source_zone == "processing" or (source_zone == "hand" and source_owner_id == receiver_id):
		return false
	if source_zone == "equipment":
		# 装备离区持有者；白银狮子、木牛流马和持续装备实例必须在实体移动前完成统一清理。
		var equipment_owner: PlayerState = state.get_player(source_owner_id)
		if equipment_owner == null:
			return false
		_on_equipment_lost(equipment_owner, card, true)
	_ensure_card_movement()
	# 牌堆与弃牌堆进入手牌时重置为接收者私有知识；公开角色区域牌沿用已经公开的历史知识。
	# 当前知识说明：已由全部存活角色知晓的公开弃牌堆实体属于例外，移动后继续保留历史知识并显示具体获得牌。
	# 移动前公开知识；公开弃牌堆选择若已被全部存活角色知晓，进入手牌后仍保持该历史知识并在日志中写出牌面。
	var source_card_known_to_all: bool = is_card_known_to_all_players(card)
	# 摸牌堆实体始终重置为接收者私有；弃牌堆中并非全体已知的检索结果同样隐藏，公开选定实体则保留知识。
	var reset_hand_knowledge: bool = source_zone == "draw_pile" or (source_zone == "discard_pile" and not source_card_known_to_all)
	if _move_card_with_timings(card, "hand", receiver_id, reason, state.current_event_id, "", [receiver_id], reset_hand_knowledge) == null:
		return false
	add_log("%s因%s获得了%s。" % [format_player_state_log_name(receiver), format_log_reason(reason), format_gained_card_log_name(card)])
	return true


## 返回指定回合角色在指定全局回合的出牌阶段进入弃牌堆、且当前仍留在弃牌堆的实体牌候选。
## suit 为空时返回全部四花色牌，指定花色时只保留完全匹配项；结果按首次符合条件的移动历史顺序排列。
func get_turn_play_discard_candidates(_viewer_id: int, turn_number: int, turn_player_id: int, suit: String = "") -> Array[Dictionary]:
	# 最终候选；弃牌堆属于公开区域，viewer_id 仅保留与其他候选接口一致的观察者参数语义。
	var result: Array[Dictionary] = []
	if state == null or turn_number <= 0 or turn_player_id < 0:
		return result
	# 当前仍位于弃牌堆的实体映射；等待期间离开的旧 UID 不会重新进入候选。
	var discard_cards_by_uid: Dictionary = {}
	for discarded_card: CardInstance in state.discard_pile:
		discard_cards_by_uid[discarded_card.uid] = discarded_card
	# 已加入结果的 UID；同一实体在本阶段多次进入弃牌堆时仍只展示一次。
	var appended_uids: Dictionary = {}
	_ensure_card_movement()
	# 当前历史移动；只统计指定回合、指定行动角色、play 阶段真实进入弃牌堆的记录。
	# 该筛选现已在移牌组件写入索引时完成，控制器直接读取符合上述条件的UID短桶。
	# 本回合候选UID；移牌组件已按回合号和行动角色索引，查询范围不再随整局历史长度增长。
	var indexed_card_uids: Array[int] = card_movement.get_turn_play_discard_uids(turn_number, turn_player_id)
	# 当前索引桶实体UID；循环只处理目标回合的短数组，不接触其他回合历史。
	for card_uid: int in indexed_card_uids:
		# 当前实体 UID；必须仍在弃牌堆且尚未加入结果。
		if appended_uids.has(card_uid) or not discard_cards_by_uid.has(card_uid):
			continue
		# 当前弃牌实体；无花色虚拟牌不满足任何实体花色条件。
		var card: CardInstance = discard_cards_by_uid[card_uid] as CardInstance
		if card == null or card.suit not in ["spade", "heart", "club", "diamond"] or (not suit.is_empty() and card.suit != suit):
			continue
		appended_uids[card_uid] = true
		result.append(_serialize_choice_candidate(card, -1, "discard_pile", true))
	return result


## 获得一张仍符合指定回合出牌阶段弃牌历史的牌；选择等待期间离区、换花色条件或旧回合 UID 均会失败。
func gain_turn_play_discard_card(receiver_id: int, card_uid: int, turn_number: int, turn_player_id: int, suit: String, reason: String = "gain_turn_play_discard") -> bool:
	# 当前合法候选；最终移动前再次按完整历史和现区域复核，客户端不能仅凭旧窗口 UID 取得其他弃牌。
	var candidates: Array[Dictionary] = get_turn_play_discard_candidates(receiver_id, turn_number, turn_player_id, suit)
	for candidate: Dictionary in candidates:
		if int(candidate.get("uid", -1)) == card_uid:
			return gain_card_to_hand_by_uid(receiver_id, card_uid, reason)
	return false


## 返回一张实体牌的当前权威位置；结果只供控制器语义端口使用，不向客户端公开对象引用。
func _find_card_location_by_uid(card_uid: int) -> Dictionary:
	for card: CardInstance in state.draw_pile:
		if card.uid == card_uid:
			return {"card":card, "zone":"draw_pile", "owner_id":-1, "slot":""}
	for card: CardInstance in state.discard_pile:
		if card.uid == card_uid:
			return {"card":card, "zone":"discard_pile", "owner_id":-1, "slot":""}
	for card: CardInstance in state.processing_area:
		if card.uid == card_uid:
			return {"card":card, "zone":"processing", "owner_id":-1, "slot":""}
	for player: PlayerState in state.players:
		for card: CardInstance in player.hand:
			if card.uid == card_uid:
				return {"card":card, "zone":"hand", "owner_id":player.player_id, "slot":""}
		# 木牛流马“粮”；与普通手牌同属可使用或打出的牌源，缺少该分支会让“粮”在标准移牌流程中找不到来源区域而静默失败。
		# 区域名必须返回稳定标识 "wooden_ox"，与 CardMovementService 的区域读写、移牌生命周期 lose 判定保持同一字符串。
		for card: CardInstance in player.wooden_ox_storage:
			if card.uid == card_uid:
				return {"card":card, "zone":"wooden_ox", "owner_id":player.player_id, "slot":""}
		for card: CardInstance in player.judgment_area:
			if card.uid == card_uid:
				return {"card":card, "zone":"judgment", "owner_id":player.player_id, "slot":""}
		for slot_variant: Variant in player.equipment.keys():
			# 当前装备槽与实体；交换和全场获得需要保留槽位信息。
			var slot: String = str(slot_variant)
			var equipment_card: CardInstance = player.equipment[slot] as CardInstance
			if equipment_card != null and equipment_card.uid == card_uid:
				return {"card":equipment_card, "zone":"equipment", "owner_id":player.player_id, "slot":slot}
	return {}


## 返回牌堆、弃牌堆和全场装备区/判定区中的全部装备牌UID；手牌中的装备牌不属于“场上的牌”。
func get_all_global_equipment_card_uids() -> Array[int]:
	# 全部装备牌UID；牌堆和弃牌堆按顶部向下，场上按座次与标准装备槽顺序排列。
	var result: Array[int] = []
	for draw_index: int in range(state.draw_pile.size() - 1, -1, -1):
		# 摸牌堆候选；只按静态type识别装备牌。
		var draw_card: CardInstance = state.draw_pile[draw_index]
		if str(GameDatabase.get_card(draw_card.definition_id).get("type", "")) == "equipment":
			result.append(draw_card.uid)
	for discard_index: int in range(state.discard_pile.size() - 1, -1, -1):
		# 弃牌堆候选；已经在结果中的实体不会重复出现于其他权威区域。
		var discard_card: CardInstance = state.discard_pile[discard_index]
		if str(GameDatabase.get_card(discard_card.definition_id).get("type", "")) == "equipment":
			result.append(discard_card.uid)
	for player: PlayerState in state.players:
		for slot: String in ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]:
			if player.equipment.has(slot):
				result.append((player.equipment[slot] as CardInstance).uid)
		for judgment_card: CardInstance in player.judgment_area:
			if str(GameDatabase.get_card(judgment_card.definition_id).get("type", "")) == "equipment":
				result.append(judgment_card.uid)
	return result


## 从牌堆和弃牌堆顶部方向选出至多指定张牌名互不相同的延时锦囊牌UID；本函数只锁定实体，不执行移动。
func get_distinct_delayed_trick_card_uids(count: int) -> Array[int]:
	# 结果UID与已选定义ID；“牌名不同”使用稳定definition_id判定，不受双名称设置影响。
	var result: Array[int] = []
	var selected_definition_ids: Dictionary = {}
	# 按规则检索顺序拼接摸牌堆顶部向下与弃牌堆顶部向下的实体。
	var ordered_cards: Array[CardInstance] = []
	for draw_index: int in range(state.draw_pile.size() - 1, -1, -1):
		ordered_cards.append(state.draw_pile[draw_index])
	for discard_index: int in range(state.discard_pile.size() - 1, -1, -1):
		ordered_cards.append(state.discard_pile[discard_index])
	for card: CardInstance in ordered_cards:
		# 当前延时锦囊定义；必须同时属于锦囊牌且delayed=true。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if str(definition.get("type", "")) != "trick" or not bool(definition.get("delayed", false)) or selected_definition_ids.has(card.definition_id):
			continue
		selected_definition_ids[card.definition_id] = true
		result.append(card.uid)
		if result.size() >= maxi(count, 0):
			break
	return result


## 为“每名角色区域内随机若干张牌”锁定随机UID；接收者自己的普通手牌已归其所有，不进入无意义获得候选。
func get_random_zone_card_uids_for_each_player(receiver_id: int, count_each: int) -> Array[int]:
	# 最终随机UID；按座次逐名角色追加，每名角色最多贡献count_each张。
	var result: Array[int] = []
	for player: PlayerState in state.players:
		if player == null or not player.alive:
			continue
		# 当前角色可实际移入接收者手牌的区域UID；自己仅包含装备和判定牌。
		var candidate_uids: Array[int] = []
		if player.player_id != receiver_id:
			for hand_card: CardInstance in player.hand:
				candidate_uids.append(hand_card.uid)
		for slot: String in ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]:
			if player.equipment.has(slot):
				candidate_uids.append((player.equipment[slot] as CardInstance).uid)
		for judgment_card: CardInstance in player.judgment_area:
			candidate_uids.append(judgment_card.uid)
		# Fisher-Yates洗牌只影响本次候选副本，权威区域顺序保持不变。
		for shuffle_index: int in range(candidate_uids.size() - 1, 0, -1):
			var swap_index: int = _rng.randi_range(0, shuffle_index)
			var temporary_uid: int = candidate_uids[shuffle_index]
			candidate_uids[shuffle_index] = candidate_uids[swap_index]
			candidate_uids[swap_index] = temporary_uid
		for candidate_index: int in range(mini(maxi(count_each, 0), candidate_uids.size())):
			result.append(candidate_uids[candidate_index])
	state.random_history.append({"kind":"opportunity_random_zone_cards", "receiver_id":receiver_id, "count_each":count_each, "card_uids":result.duplicate()})
	return result


## 从候选集合中等概率取一项并写入随机历史；技能随机效果必须经此入口，禁止自建随机源或裸随机数。
## 使用全局 _rng，保证固定种子下可复现、存档 rng_state 恢复后结果一致、联机各端判定统一。
## 返回索引而非元素：调用方保留自己对候选数组的类型控制，异构候选无需统一返回值类型。
## candidate_count 不大于0时返回-1，表示没有可选项，由调用方按“本次无效果”处理而不在此抛错。
func pick_random_candidate_index(candidate_count: int, history_kind: String = "", history_data: Dictionary = {}) -> int:
	if candidate_count <= 0:
		return -1
	# 权威随机索引；与区域内随机取牌共用同一套随机流，闭区间取值覆盖全部候选。
	var picked_index: int = _rng.randi_range(0, candidate_count - 1)
	# 随机历史条目；固定kind便于测试与复盘检索，候选规模与命中索引始终记录以支持复现。
	var history_entry: Dictionary = {
		"kind":(history_kind if not history_kind.is_empty() else "skill_random_pick"),
		"candidate_count":candidate_count,
		"picked_index":picked_index,
	}
	history_entry.merge(history_data, true)
	state.random_history.append(history_entry)
	return picked_index


## 将指定角色当前全部普通手牌持续视为同一牌名，实体离开该角色手牌区时由统一移动边界自动恢复原定义。
func set_all_hand_cards_view_as(player_id: int, view_as_definition_id: String, source_id: String = "runtime", allow_out_of_game: bool = false) -> int:
	# 目标角色；无效定义、死亡或未获许可的离场角色不修改任何实体牌。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or GameDatabase.get_card(view_as_definition_id).is_empty():
		return 0
	# 实际建立或已经满足视为名称的手牌数；用于日志和测试确认范围。
	var affected_count: int = 0
	for card: CardInstance in player.hand:
		if card.definition_id == view_as_definition_id or card.set_hand_view_as(view_as_definition_id, source_id):
			affected_count += 1
	if affected_count > 0:
		add_log("%s的%d张手牌视为%s，直到各自离开手牌区。" % [format_player_state_log_name(player), affected_count, format_card_definition_log_name(view_as_definition_id)])
		_emit_state()
	return affected_count


## 为指定持有者的一张普通手牌写入通用标记标签；标签不改变牌名，并在实体离开当前手牌区时自动清除。
func set_hand_card_mark_tag(holder_id: int, card_uid: int, tag_id: String, tag_data: Dictionary) -> bool:
	# 当前手牌持有者；死亡、离场或不存在的角色不能获得新的手牌标记。
	var holder: PlayerState = state.get_player(holder_id) if state != null else null
	# 当前手牌实体；UID必须仍位于指定角色的普通手牌区。
	var card: CardInstance = holder.find_hand_card(card_uid) if holder != null else null
	if holder == null or not holder.alive or holder.out_of_game or card == null or not card.set_hand_mark_tag(tag_id, tag_data):
		return false
	_emit_state()
	return true


## 返回两名角色交换装备区时的完整实体与目标槽位快照；解析器会先清空双方装备区再按本快照装入对方。
func get_equipment_swap_entries(first_player_id: int, second_player_id: int) -> Array[Dictionary]:
	# 交换条目；每项保存原持有者、目标持有者、槽位和实体UID。
	var result: Array[Dictionary] = []
	for pair_variant: Variant in [[first_player_id, second_player_id], [second_player_id, first_player_id]]:
		# 当前方向数组；索引0为原持有者，索引1为目标持有者。
		var pair: Array = pair_variant as Array
		var source: PlayerState = state.get_player(int(pair[0]))
		if source == null:
			continue
		for slot: String in ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]:
			if source.equipment.has(slot):
				result.append({"card_uid":(source.equipment[slot] as CardInstance).uid, "source_player_id":int(pair[0]), "target_player_id":int(pair[1]), "slot":slot})
	return result


## 将指定装备实体移入公共处理区并执行离开装备区效果；交换装备使用该中间态避免同槽覆盖丢牌。
func move_equipment_card_to_processing(player_id: int, card_uid: int, reason: String = "equipment_swap") -> bool:
	# 当前装备位置；必须仍属于指定角色的装备区。
	var location: Dictionary = _find_card_location_by_uid(card_uid)
	var card: CardInstance = location.get("card") as CardInstance
	if card == null or str(location.get("zone", "")) != "equipment" or int(location.get("owner_id", -1)) != player_id:
		return false
	# 失去装备角色；离区效果和运行时卸载必须在移动前完成。
	var player: PlayerState = state.get_player(player_id)
	_on_equipment_lost(player, card, true)
	_ensure_card_movement()
	return _move_card_with_timings(card, "processing", -1, reason, state.current_event_id) != null


## 将交换流程中位于处理区的装备实体装入目标对应槽位；目标槽必须已经清空。
func move_processing_card_to_equipment(player_id: int, card_uid: int, slot: String, reason: String = "equipment_swap") -> bool:
	# 目标角色与处理区实体；槽位冲突表示交换清空阶段尚未完成，不能覆盖现有牌。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	var card: CardInstance = _find_processing_card(card_uid)
	if player == null or card == null or player.is_equipment_slot_abolished(slot) or player.equipment.has(slot):
		return false
	_ensure_card_movement()
	if _move_card_with_timings(card, "equipment", player_id, reason, state.current_event_id, slot) == null:
		return false
	_install_card_runtime(card, player_id)
	return true


## 返回玩家手牌区与装备区的牌数；装备技能的“弃置牌”费用和寒冰剑只允许操作这两个区域。
func get_hand_equipment_card_count(player_id: int) -> int:
	# 指定玩家状态；不存在时数量为0。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return player.hand.size() + player.equipment.size()


## 从玩家手牌区和装备区依次弃置至多指定数量的牌；不会错误弃置判定区中的延时锦囊。
func discard_n_from_hand_equipment(player_id: int, count: int) -> void:
	# 弃置批次；整次“从手牌与装备区弃置至多N张”共享一个批次事件。
	_begin_discard_batch(player_id, "discard_n_from_hand_equipment")
	for _index: int in range(maxi(count, 0)):
		# 当前玩家状态；每次循环重新读取区域，保证装备离开效果结算后数量准确。
		var player: PlayerState = state.get_player(player_id)
		if player == null:
			break
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand[0].uid)
		elif not player.equipment.is_empty():
			_discard_equipment_slot(player_id, str(player.equipment.keys()[0]), true)
		else:
			# 两个区域都已空时结束循环而不是直接返回，保证批次栈正常收尾。
			break
	_end_discard_batch()


## 把一张普通手牌交给指定存活角色，并在进入其手牌区后赋予临时视为牌名；目标可以与来源相同。
func transfer_hand_card_as(from_id: int, to_id: int, card_uid: int, view_as_definition_id: String, source_skill_id: String) -> bool:
	# 交牌来源；必须仍存活、在场并实际持有所选普通手牌。
	var source: PlayerState = state.get_player(from_id) if state != null else null
	# 交牌目标；“一名角色”允许来源本人，但死亡或离场角色不能获得手牌。
	var target: PlayerState = state.get_player(to_id) if state != null else null
	if source == null or target == null or not source.alive or source.out_of_game or not target.alive or target.out_of_game:
		return false
	# 被交出的实体牌；等待期间离开来源手牌区时本次效果失效且不消费技能次数。
	var card: CardInstance = source.find_hand_card(card_uid)
	if card == null or GameDatabase.get_card(view_as_definition_id).is_empty():
		return false
	# 交给自己不产生无效的同区域移动事件，只在原手牌上建立临时牌名；实体UID、顺序与牌面知识保持不变。
	if from_id == to_id:
		if card.definition_id != view_as_definition_id and not card.set_hand_view_as(view_as_definition_id, source_skill_id):
			return false
		add_log("%s将%s交给了自己。" % [source.display_name, format_gained_card_log_name(card, "一张手牌")])
		return true
	_ensure_card_movement()
	if _move_card_with_timings(card, "hand", to_id, "give", state.current_event_id, "", [to_id]) == null:
		return false
	# 临时牌名只在实体已属于目标手牌时建立；后续离手由统一移动边界自动恢复原始定义。
	if card.definition_id != view_as_definition_id and not card.set_hand_view_as(view_as_definition_id, source_skill_id):
		return false
	add_log("%s将%s交给了%s。" % [source.display_name, format_gained_card_log_name(card, "一张手牌"), target.display_name])
	return true


## 令指定持有者的一张手牌持续视为目标牌名，直到该实体离开手牌区或持有者的下个回合结束。
func set_hand_card_view_as_until_next_turn_end(holder_id: int, card_uid: int, view_as_definition_id: String, source_skill_id: String) -> bool:
	# 当前持有者；等待期间死亡或不存在时不能建立到期效果。
	var holder: PlayerState = state.get_player(holder_id) if state != null else null
	# 当前手牌实体；等待期间发生转移时不能把旧效果登记到新区域。
	var card: CardInstance = holder.find_hand_card(card_uid) if holder != null else null
	if holder == null or card == null or GameDatabase.get_card(view_as_definition_id).is_empty():
		return false
	# 已经是目标牌名且没有视为来源时无需创建到期记录；实体本身的真实牌名不会在回合尾被错误恢复。
	if card.definition_id == view_as_definition_id and not card.has_hand_view_as():
		return true
	if card.definition_id != view_as_definition_id and not card.set_hand_view_as(view_as_definition_id, source_skill_id):
		return false
	# 到期记录；expire_turn_number为-1表示尚未进入持有者的下个回合，创建于其当前回合时不会提前到期。
	_hand_view_as_turn_expiries[card_uid] = {
		"holder_id":holder_id,
		"source_skill_id":source_skill_id,
		"expire_turn_number":-1,
	}
	_emit_state()
	return true


## 执行“交给一名角色并视为牌”的完整移动；来源装备只允许交给自己，并先通过统一装备离区流程收入手牌。
func transfer_hand_or_self_equipment_card_as_until_next_turn_end(from_id: int, to_id: int, card_uid: int, view_as_definition_id: String, source_skill_id: String) -> bool:
	# 实体当前位置；只接受来源角色实际持有的区域实体。
	var location: Dictionary = _find_card_location_by_uid(card_uid)
	# 实体来源区域；普通手牌可交给任意目标，装备只允许持有者收回自己手牌。
	var source_zone: String = str(location.get("zone", ""))
	if int(location.get("owner_id", -1)) != from_id or source_zone not in ["hand", "equipment"]:
		return false
	if source_zone == "equipment":
		if to_id != from_id or not gain_card_to_hand_by_uid(from_id, card_uid, source_skill_id):
			return false
	elif not transfer_hand_card_as(from_id, to_id, card_uid, view_as_definition_id, source_skill_id):
		return false
	return set_hand_card_view_as_until_next_turn_end(to_id, card_uid, view_as_definition_id, source_skill_id)


## 在一名角色进入回合时锁定其待到期手牌视为效果；本回合内新获得的同类效果会等待再下一个回合。
func _arm_hand_view_as_expiries_for_turn(player_id: int) -> void:
	for card_uid_variant: Variant in _hand_view_as_turn_expiries.keys():
		# 当前实体UID；作为到期记录与权威牌实体的稳定关联键。
		var card_uid: int = int(card_uid_variant)
		# 当前实体到期记录；只处理属于本回合角色且尚未锁定到期回合的效果。
		var expiry: Dictionary = _hand_view_as_turn_expiries.get(card_uid_variant, {}) as Dictionary
		if int(expiry.get("holder_id", -1)) != player_id or int(expiry.get("expire_turn_number", -1)) >= 0:
			continue
		expiry["expire_turn_number"] = state.turn_number
		_hand_view_as_turn_expiries[card_uid] = expiry


## 在持有者回合结束时清理已经锁定到本回合的手牌视为效果；牌已离区时仅移除陈旧记录。
func _expire_hand_view_as_effects_for_turn(player_id: int) -> void:
	# 是否实际恢复过手牌定义；只有牌面发生变化时才需要额外广播状态。
	var changed: bool = false
	for card_uid_variant: Variant in _hand_view_as_turn_expiries.keys():
		# 当前实体UID；字典遍历期间使用键副本，可安全删除已处理记录。
		var card_uid: int = int(card_uid_variant)
		# 当前到期数据；持有者与锁定回合必须同时匹配才执行恢复。
		var expiry: Dictionary = _hand_view_as_turn_expiries.get(card_uid_variant, {}) as Dictionary
		if int(expiry.get("holder_id", -1)) != player_id or int(expiry.get("expire_turn_number", -1)) != state.turn_number:
			continue
		# 到期效果持有者；回合结束时重新取得权威角色状态。
		var player: PlayerState = state.get_player(player_id)
		# 到期手牌实体；仅清理仍由同一技能来源建立的视为效果，避免覆盖后续规则重新赋予的新效果。
		var card: CardInstance = player.find_hand_card(card_uid) if player != null else null
		if card != null and card.has_hand_view_as() and card.hand_view_as_source_skill_id == str(expiry.get("source_skill_id", "")):
			card.clear_hand_view_as()
			# 到期表现清理；限时视为在持有者手牌内恢复原牌时不是“离手展示”，必须同步移除旧逻辑牌横条。
			card.clear_hand_view_as_presentation()
			changed = true
		_hand_view_as_turn_expiries.erase(card_uid_variant)
	if changed:
		_emit_state()


## 令指定角色从摸牌堆或弃牌堆获得最顶上的指定牌；先完整检索摸牌堆，缺失时才检索弃牌堆。
func gain_top_named_card_from_draw_or_discard(player_id: int, definition_id: String, reason: String = "gain_named_card", allow_out_of_game: bool = false) -> CardInstance:
	# 获得者；死亡、离场或终局后不再改变牌区。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or state.game_over or definition_id.is_empty():
		return null
	# 指定实体；数组末尾是牌堆顶与弃牌堆顶，倒序扫描保证取得最顶上的匹配牌而不改变其他牌相对顺序。
	var matched_card: CardInstance
	for draw_index: int in range(state.draw_pile.size() - 1, -1, -1):
		# 当前摸牌堆候选；只比较稳定定义ID，不移动未命中的牌。
		var draw_card: CardInstance = state.draw_pile[draw_index]
		if draw_card.definition_id == definition_id:
			matched_card = draw_card
			break
	if matched_card == null:
		for discard_index: int in range(state.discard_pile.size() - 1, -1, -1):
			# 当前弃牌堆候选；从顶部向下遇到首张匹配牌后立即停止。
			var discard_card: CardInstance = state.discard_pile[discard_index]
			if discard_card.definition_id == definition_id:
				matched_card = discard_card
				break
	if matched_card == null:
		return null
	_ensure_card_movement()
	if _move_card_with_timings(matched_card, "hand", player_id, reason, state.current_event_id, "", [player_id], true) == null:
		return null
	add_log("%s从牌堆或弃牌堆获得了一张牌。" % player.display_name)
	return matched_card


## 按类型、花色、规则牌名或定义ID分组，从摸牌堆或弃牌堆为角色获得每组指定数量的牌。
## 摸牌堆优先于弃牌堆，同一区域从顶部向下检索；某组不足时获得现存数量且不以其他组补足。
func gain_group_cards_from_draw_or_discard(player_id: int, group_kind: String, groups: Array, count_each: int, reason: String = "gain_group_cards", allow_out_of_game: bool = false) -> int:
	# 获得者；死亡、离场、终局或无效数量时不移动任何牌。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or state.game_over or count_each <= 0:
		return 0
	# 实际获得总数；每个分组独立计数，便于牌堆不足时保留准确结果。
	var gained_count: int = 0
	for group_variant: Variant in groups:
		# 当前分组值；type使用basic/trick/equipment，suit使用四花色，rule_name使用稳定原版规则名。
		var group_value: String = str(group_variant)
		for _copy_index: int in range(count_each):
			# 当前匹配实体；先完整检索摸牌堆，缺失时再检索弃牌堆。
			var matched_card: CardInstance = _find_top_group_card(state.draw_pile, group_kind, group_value)
			if matched_card == null:
				matched_card = _find_top_group_card(state.discard_pile, group_kind, group_value)
			if matched_card == null:
				break
			_prepare_hidden_pile_gain(matched_card, player_id)
			_ensure_card_movement()
			if _move_card_with_timings(matched_card, "hand", player_id, reason, state.current_event_id, "", [player_id], true) != null:
				gained_count += 1
	if gained_count > 0:
		add_log("%s从牌堆或弃牌堆获得了%d张牌。" % [format_player_state_log_name(player), gained_count])
	return gained_count


## 从指定牌区顶部方向查找首张匹配分组的实体牌；只读查询不改变未命中牌的相对顺序。
func _find_top_group_card(card_zone: Array[CardInstance], group_kind: String, group_value: String) -> CardInstance:
	for card_index: int in range(card_zone.size() - 1, -1, -1):
		# 当前候选实体；分组属性由稳定牌定义或实体花色读取。
		var card: CardInstance = card_zone[card_index]
		# 当前牌静态定义；类型与规则牌名不受玩家显示名称模式影响。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if group_kind == "type" and str(definition.get("type", "")) == group_value:
			return card
		if group_kind == "suit" and card.suit == group_value:
			return card
		if group_kind == "rule_name" and str(definition.get("rule_name", definition.get("original_name", ""))) == group_value:
			return card
		if group_kind == "definition_id" and card.definition_id == group_value:
			return card
	return null


## 从摸牌堆与弃牌堆获得指定数量且结算牌名字数相同的牌；优先选可取得数量最多的字数组，数量相同则优先含有更顶端牌的字数组。
func gain_same_name_length_cards_from_draw_or_discard(player_id: int, requested_count: int, reason: String = "gain_same_name_length_cards", allow_out_of_game: bool = false) -> int:
	# 获得者；死亡、未获明确离场许可的离场角色、终局或非正数量均不执行牌区移动。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or state.game_over or requested_count <= 0:
		return 0
	# 各结算名字数的可取得总数；摸牌堆与弃牌堆合并统计，属性【杀】等继续按统一rule_name计数。
	var available_count_by_name_length: Dictionary = {}
	for card_zone: Array[CardInstance] in [state.draw_pile, state.discard_pile]:
		for card: CardInstance in card_zone:
			# 当前实体的结算名字数；缺失定义返回0，不参与同字数取牌。
			var name_length: int = get_card_original_name_length(card.definition_id)
			if name_length > 0:
				available_count_by_name_length[name_length] = int(available_count_by_name_length.get(name_length, 0)) + 1
	if available_count_by_name_length.is_empty():
		return 0
	# 最佳字数候选；先按可取得数量选择，平局时按“摸牌堆顶、弃牌堆顶”的扫描顺序维持稳定结果。
	var selected_name_length: int = 0
	var selected_available_count: int = -1
	for card_zone: Array[CardInstance] in [state.draw_pile, state.discard_pile]:
		for card_index: int in range(card_zone.size() - 1, -1, -1):
			# 当前顶向候选的名字数；同一名字数只在首次遇到时参与平局比较。
			var candidate_name_length: int = get_card_original_name_length(card_zone[card_index].definition_id)
			var candidate_available_count: int = int(available_count_by_name_length.get(candidate_name_length, 0))
			if candidate_name_length > 0 and candidate_available_count > selected_available_count:
				selected_name_length = candidate_name_length
				selected_available_count = candidate_available_count
	if selected_name_length <= 0:
		return 0
	# 实际获得数量；先从摸牌堆顶部向下取，摸牌堆不足再从弃牌堆顶部向下补足，始终保持同一结算名字数。
	var gained_count: int = 0
	for card_zone: Array[CardInstance] in [state.draw_pile, state.discard_pile]:
		while gained_count < requested_count:
			# 当前区域最顶端的同字数实体；未命中时切换下一牌区，绝不移动无关牌。
			var matched_card: CardInstance = _find_top_card_by_name_length(card_zone, selected_name_length)
			if matched_card == null:
				break
			_prepare_hidden_pile_gain(matched_card, player_id)
			_ensure_card_movement()
			if _move_card_with_timings(matched_card, "hand", player_id, reason, state.current_event_id, "", [player_id], true) != null:
				gained_count += 1
	if gained_count > 0:
		add_log("%s从牌堆或弃牌堆获得了%d张牌。" % [format_player_state_log_name(player), gained_count])
	return gained_count


## 从指定牌区顶部方向查找首张结算牌名字数匹配的实体；只读查询不会重排或移动未命中牌。
func _find_top_card_by_name_length(card_zone: Array[CardInstance], name_length: int) -> CardInstance:
	for card_index: int in range(card_zone.size() - 1, -1, -1):
		# 当前实体；统一通过结算名称接口比较，避免显示名称模式影响实际规则。
		var card: CardInstance = card_zone[card_index]
		if get_card_original_name_length(card.definition_id) == name_length:
			return card
	return null


## 令指定角色从摸牌堆获得最顶上的固定牌名字数卡牌；普通牌按《崩铁杀》自定义牌名计算，属性【杀】等规则名牌优先按规则名计算。
func gain_top_draw_card_by_name_length(player_id: int, name_length: int, reason: String = "gain_name_length_card") -> CardInstance:
	# 获得者；无效角色和非正名字数不会查询或移动牌堆。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over or name_length <= 0:
		return null
	# 指定实体；倒序扫描摸牌堆取得最顶上的匹配卡牌，弃牌堆不参与本接口。
	var matched_card: CardInstance
	for draw_index: int in range(state.draw_pile.size() - 1, -1, -1):
		# 当前摸牌堆候选；统一结算名字数匹配时即为最顶上的合法实体。
		var draw_card: CardInstance = state.draw_pile[draw_index]
		if get_card_original_name_length(draw_card.definition_id) == name_length:
			matched_card = draw_card
			break
	if matched_card == null:
		return null
	_ensure_card_movement()
	if _move_card_with_timings(matched_card, "hand", player_id, reason, state.current_event_id, "", [player_id], true) == null:
		return null
	add_log("%s从牌堆获得了一张牌。" % player.display_name)
	return matched_card


## 令指定角色从摸牌堆顶向下获得首张满足序列化过滤条件的牌；弃牌堆与重洗流程不参与本次检索。
func gain_top_draw_card_matching(player_id: int, filter: Dictionary, reason: String = "gain_matching_draw_card") -> CardInstance:
	# 获得者；死亡、离场、终局或空过滤条件不会移动任何牌。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over or filter.is_empty():
		return null
	# 最顶端匹配实体；数组末尾是摸牌堆顶，倒序扫描不会改变未命中牌的相对顺序。
	var matched_card: CardInstance
	for draw_index: int in range(state.draw_pile.size() - 1, -1, -1):
		# 当前摸牌堆候选；牌面与静态定义共同参与过滤器复核。
		var draw_card: CardInstance = state.draw_pile[draw_index]
		if _does_draw_card_match_filter(draw_card, filter):
			matched_card = draw_card
			break
	if matched_card == null:
		return null
	_prepare_hidden_pile_gain(matched_card, player_id)
	_ensure_card_movement()
	if _move_card_with_timings(matched_card, "hand", player_id, reason, state.current_event_id, "", [player_id], true) == null:
		return null
	add_log("%s从牌堆获得了一张牌。" % format_player_state_log_name(player))
	return matched_card


## 判断一张摸牌堆实体是否满足通用检索过滤器；全部已声明字段采用“且”关系，未声明字段不参与限制。
func _does_draw_card_match_filter(card: CardInstance, filter: Dictionary) -> bool:
	if card == null:
		return false
	# 当前牌静态定义；牌效、类型与属性均从稳定内容数据读取。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 单一定义ID限制；适合精确检索【桃】等固定牌。
	var required_definition_id: String = str(filter.get("definition_id", ""))
	if not required_definition_id.is_empty() and card.definition_id != required_definition_id:
		return false
	# 定义ID集合限制；空数组表示不限制，非空时至少命中其中一项。
	var required_definition_ids: Array = filter.get("definition_ids", []) as Array
	if not required_definition_ids.is_empty() and not required_definition_ids.has(card.definition_id):
		return false
	# 共享牌效限制；普通、火与雷【杀】可通过effect_id统一识别。
	var required_effect_id: String = str(filter.get("effect_id", ""))
	if not required_effect_id.is_empty() and str(definition.get("effect_id", "")) != required_effect_id:
		return false
	# 属性集合限制；用于只保留火焰与雷属性牌并排除普通属性。
	var required_natures: Array = filter.get("natures", []) as Array
	if not required_natures.is_empty() and not required_natures.has(str(definition.get("nature", "normal"))):
		return false
	# 卡牌类型限制；basic、trick与equipment使用内容数据中的稳定类型值。
	var required_type: String = str(filter.get("type", ""))
	if not required_type.is_empty() and str(definition.get("type", "")) != required_type:
		return false
	return true


## 把从牌堆或弃牌堆获得的实体恢复为仅获得者知晓的手牌信息；技能即使写明牌名也不向其他角色保留牌面知识。
func _prepare_hidden_pile_gain(card: CardInstance, player_id: int) -> void:
	if card == null:
		return
	card.shown = false
	card.known_to.clear()
	if player_id >= 0:
		card.known_to.append(player_id)
	card.private_owner_id = player_id


## 记录一张牌在当前回合未能对指定目标产生预期效果；只保存稳定定义ID和玩家ID，不持有牌或玩家对象。
func record_failed_card_target(actor_id: int, card_definition_id: String, target_id: int) -> void:
	# 行动者状态；无效玩家、牌ID或目标不写入AI行为记忆。
	var actor: PlayerState = state.get_player(actor_id) if state != null else null
	if actor == null or card_definition_id.is_empty() or target_id < 0:
		return
	# 当前牌的失败目标数组；复制后写回可避免弱类型数组被外部引用修改。
	var failed_target_ids: Array[int] = []
	for target_variant: Variant in actor.ai_failed_card_target_ids.get(card_definition_id, []) as Array:
		failed_target_ids.append(int(target_variant))
	if not failed_target_ids.has(target_id):
		failed_target_ids.append(target_id)
	actor.ai_failed_card_target_ids[card_definition_id] = failed_target_ids


## 返回卡牌用于名字数结算的Unicode字符数；存在规则名时优先读取规则名，否则读取《崩铁杀》自定义牌名，不受当前显示名称模式影响。
func get_card_original_name_length(definition_id: String) -> int:
	# 卡牌静态定义；提供规则名的牌可声明与牌面不同的结算名称，例如火、雷【杀】均按“杀”计算。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	# 规则结算名称；非空时覆盖牌面名称，保证属性【杀】继续按1个汉字参与名字数规则。
	var rule_name: String = str(definition.get("rule_name", ""))
	if not rule_name.is_empty():
		return rule_name.length()
	# 崩铁杀牌面名称；未声明规则名的普通牌固定按此字段计数，缺失时才回退原版名称以兼容扩展内容。
	var custom_name: String = str(definition.get("custom_name", definition.get("original_name", "")))
	return custom_name.length()


## 弃置目标全部装备；水淹七军、死亡与领袖惩罚可复用此操作。
func discard_all_equipment(target_id: int, trigger_loss_effects: bool = true) -> void:
	# 目标状态；复制键数组以允许循环中安全删除装备。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		return
	# 当前全部装备槽快照；后续删除不会影响遍历。
	var slots: Array = target.equipment.keys().duplicate()
	for slot_variant: Variant in slots:
		_discard_equipment_slot(target_id, str(slot_variant), trigger_loss_effects)


## 弃置指定装备栏中的实体牌并执行标准离区效果；空栏或无效玩家返回false。
func discard_equipment_slot(player_id: int, slot: String, trigger_loss_effects: bool = true) -> bool:
	# 装备栏所属玩家；服务只能处理当前真实存在的装备实体。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.equipment.has(slot):
		return false
	_discard_equipment_slot(player_id, slot, trigger_loss_effects)
	return true


## 将指定角色判定区内全部延时锦囊按当前顺序置入弃牌堆。
func discard_all_judgment_area_cards(player_id: int) -> void:
	# 判定区所属玩家；无效ID不产生任何移牌事件。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return
	# 判定区实体副本；标准移动服务负责从原数组移除，前置时机取消时实体仍安全留在原区域而不会成为游离牌。
	var delayed_cards: Array[CardInstance] = player.judgment_area.duplicate()
	for delayed_card: CardInstance in delayed_cards:
		_move_to_discard(delayed_card)


## 转移一个装备槽中的牌；借刀杀人使用该操作将武器交给来源角色手牌。
func transfer_equipment(from_id: int, to_id: int, slot: String) -> void:
	# 原持有者状态；指定槽为空时不执行。
	var from_player: PlayerState = state.get_player(from_id)
	# 接收者状态；借刀杀人将武器交入其手牌而非直接装备。
	var to_player: PlayerState = state.get_player(to_id)
	if not from_player.equipment.has(slot):
		return
	# 被转移的装备实体牌；离开装备区后触发丢失装备效果。
	var card: CardInstance = from_player.equipment[slot] as CardInstance
	_on_equipment_lost(from_player, card, true)
	# 移动前区域；借刀杀人的获得动画从原持有者武将牌飞向获得者。
	# 该来源现由 CardMovementService 在移动前写入统一事件，目标界面只消费一次移动增量。
	_ensure_card_movement()
	_move_card_with_timings(card, "hand", to_id, "gain", state.current_event_id, "", [to_id])
	add_log("%s将武器交给了%s。" % [from_player.display_name, to_player.display_name])


## 返回玩家指定装备槽中的卡牌配置 ID；空槽返回空字符串。
func get_equipment_id(player_id: int, slot: String) -> String:
	# 指定玩家状态；无效 ID 视为空槽。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return ""
	# 装备槽中的实体牌；返回其定义 ID。
	var card: CardInstance = player.equipment[slot] as CardInstance
	return card.definition_id


## 检查玩家是否装备指定配置 ID，不要求调用方知道其槽位。
func player_has_equipment(player_id: int, definition_id: String) -> bool:
	# 指定玩家状态；不存在时返回 false。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false
	for card_variant: Variant in player.equipment.values():
		# 当前装备实体牌；逐项比较定义 ID。
		var card: CardInstance = card_variant as CardInstance
		if card.definition_id == definition_id:
			return true
	return false


## 返回指定装备槽当前实体对应的卡牌源码定义；空槽或失效定义返回 null。
func get_equipment_definition(player_id: int, slot: String) -> CardDefinition:
	# 指定玩家状态；无效玩家没有装备定义。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return null
	# 当前装备实体；定义通过自动扫描数据库按稳定 ID 定位。
	var card: CardInstance = player.equipment[slot] as CardInstance
	return GameDatabase.get_card_definition(card.definition_id)


## 返回指定装备槽中的权威实体牌；卡牌源码只用于保存和复核稳定 UID，不得直接移动该对象。
func get_equipment_card(player_id: int, slot: String) -> CardInstance:
	# 指定玩家状态；无效玩家或空槽返回 null。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return null
	# 当前装备实体；调用方只能读取 UID、定义 ID、花色和点数。
	var card: CardInstance = player.equipment[slot] as CardInstance
	return card


## 从指定玩家开始返回全部存活角色的行动顺序副本；卡牌源码只能读取结果。
func get_alive_players_in_action_order(start_player_id: int) -> Array[PlayerState]:
	return _get_alive_players_in_action_order(start_player_id)


## 返回两个身份的基础 AI 阵营态度；装备源码可复用该只读目标策略。
func get_identity_attitude(from_identity: String, to_identity: String) -> int:
	return _identity_attitude(from_identity, to_identity)


## 转发技能文件已经成功执行的公开目标行为；身份观察只读权威快照，不参与技能效果、费用或合法性判断。
func observe_skill_identity_behavior(actor_id: int, target_ids: Array[int], ai_profile: Dictionary) -> void:
	if state == null or ai_coordinator == null or state.get_player(actor_id) == null or ai_profile.is_empty():
		return
	ai_coordinator.observe_public_behavior(state.to_dict(-1, true), actor_id, ai_profile, target_ids, local_human_player_id)
	# 技能公开行为同步给远端客户端；非房主发动的技能同样进入各客户端本地身份推断。
	_broadcast_identity_behavior(actor_id, ai_profile, target_ids)


## 请求玩家决定是否发动一件仍在装备区的非锁定装备；选择装备实体表示发动，取消表示不发动且不消耗装备。
func request_equipment_trigger(player_id: int, definition_id: String, title: String, prompt: String, context: Dictionary, ai_prefer_select: bool = true) -> bool:
	# 当前装备实体；等待前必须存在，恢复时具体效果仍会再次校验其实体 UID。
	var equipment_card: CardInstance = _get_equipment_card_by_definition(player_id, definition_id)
	if equipment_card == null:
		return false
	# 装备候选；公开装备使用独立选择面板，选择只表达发动意愿，不会移动实体牌。
	# 本地玩家是上述表现规则的例外：桌面会把本人 equipment 候选留在左侧装备区内联选择；规则层仍只提供相同公开候选且不感知具体界面。
	var candidates: Array[Dictionary] = [_serialize_choice_candidate(equipment_card, player_id, "equipment", true, str(GameDatabase.get_card(definition_id).get("slot", "")))]
	# 完整触发上下文；稳定装备 UID 防止响应等待期间换装后误发动新装备。
	var trigger_context: Dictionary = context.duplicate(true)
	trigger_context["equipment_id"] = definition_id
	trigger_context["equipment_uid"] = equipment_card.uid
	trigger_context["ai_prefer_select"] = ai_prefer_select
	# 发动选择；正式对局异步等待，纯规则测试没有选择策略时保守返回不发动。
	var selected_uids: Array[int] = request_card_choice(player_id, title, prompt, candidates, 0, 1, true, trigger_context)
	if has_pending_card_choice():
		return false
	return selected_uids.has(equipment_card.uid)


## 返回一名玩家手牌区与装备区的可选实体快照；装备技能费用和目标弃牌效果使用同一稳定 UID 边界。
func get_hand_equipment_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	return _build_player_zone_candidates(viewer_id, target_id, true, true, false)


## 返回目标手牌、装备与判定区的完整选择候选；技能可用于“弃置一名角色的一张牌”，最终移动仍需调用权威弃置端口复核。
func get_player_zone_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	return _build_player_zone_candidates(viewer_id, target_id, true, true, true)


## 返回全部存活在场角色装备区与判定区中的可弃置候选，即规则概念中的「场上」。
## 「场上」只含装备区与判定区，不含手牌区；include_self 决定是否纳入来源角色自己的场地牌。
## 候选沿用统一区域候选结构，实际移动仍必须调用 discard_selected_player_card() 复核保护规则。
func get_field_card_candidates(viewer_id: int, include_self: bool = true) -> Array[Dictionary]:
	# 场上候选结果；按权威座次顺序聚合，界面、AI与回放据此稳定复现。
	var result: Array[Dictionary] = []
	if state == null:
		return result
	for player: PlayerState in state.players:
		if player == null or not player.alive or player.out_of_game:
			continue
		if not include_self and player.player_id == viewer_id:
			continue
		# 装备区候选；逐槽判断废除状态，已废除的栏位不产生候选，与区域废除语义保持一致。
		for slot: String in PlayerState.EQUIPMENT_SLOT_ORDER:
			if player.is_equipment_slot_abolished(slot):
				continue
			# 当前槽位装备实体；空槽位不产生候选。
			var equipment_card: CardInstance = player.equipment.get(slot) as CardInstance
			if equipment_card == null:
				continue
			if not can_discard_player_card(viewer_id, player.player_id, equipment_card, "equipment", slot):
				continue
			result.append(_serialize_choice_candidate(equipment_card, player.player_id, "equipment", true, slot))
		# 判定区候选；整区废除时该角色的判定区牌不进入场上。
		if player.judgment_area_abolished:
			continue
		for judgment_card: CardInstance in player.judgment_area:
			if judgment_card == null:
				continue
			if not can_discard_player_card(viewer_id, player.player_id, judgment_card, "judgment"):
				continue
			result.append(_serialize_choice_candidate(judgment_card, player.player_id, "judgment", true))
	return result


## 返回指定角色当前可执行的欢愉技稳定ID列表；按参演编号升序、技能稳定ID字典序排列。
## 排序口径与阿哈时刻参演序列完全一致，"令其发动欢愉技"因此与常规演出选中同一优先级最高者。
func get_joy_skill_ids(player_id: int) -> Array[String]:
	# 欢愉技ID结果；角色不存在、已死亡、已离场或没有可执行欢愉技时返回空数组。
	var result: Array[String] = []
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game:
		return result
	# 欢愉技条目；先收集编号与ID再排序，避免排序回调内反复查询技能实例。
	var entries: Array[Dictionary] = []
	# 当前角色技能实例表；与阿哈时刻读取同一索引，不额外缓存技能对象。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；非欢愉技、效果失效或持有者状态不满足时跳过，与参演筛选口径一致。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or not skill.is_joy_skill() or not skill.can_perform_joy_skill():
			continue
		entries.append({"skill_id":skill.get_id(), "performance_number":skill.get_performance_number()})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		# 主排序键；编号越小优先级越高。
		var left_number: int = int(left.get("performance_number", 0))
		var right_number: int = int(right.get("performance_number", 0))
		if left_number != right_number:
			return left_number < right_number
		# 次排序键；编号相同时按技能稳定ID字典序，保证结果与排序调用无关。
		return str(left.get("skill_id", "")) < str(right.get("skill_id", ""))
	)
	for entry: Dictionary in entries:
		result.append(str(entry.get("skill_id", "")))
	return result


## 由来源角色弃置目标区域内指定UID的一张牌；成功返回true，装备保护与等待期间区域变化会在移动前再次校验。
func discard_selected_player_card(source_player_id: int, target_player_id: int, card_uid: int) -> bool:
	return _discard_selected_player_card(target_player_id, card_uid, source_player_id)


## 返回一名玩家普通手牌区的可选实体快照；木牛“粮”和装备牌不会混入要求弃置手牌的装备效果。
func get_hand_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	return _build_player_zone_candidates(viewer_id, target_id, true, false, false)


## 返回仅向指定观看者发送的完整手牌牌面候选；本查询不修改shown、known_to或任何公开快照字段。
func get_private_hand_view_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	# 私有观看结果；viewer_id保留为权限语义边界，候选只会进入该观看者的定向选择请求。
	var result: Array[Dictionary] = []
	# 被观看角色；死亡、离场或无效角色均不提供旧手牌信息。
	var target: PlayerState = state.get_player(target_id) if state != null else null
	if viewer_id < 0 or target == null or not target.alive or target.out_of_game:
		return result
	for hand_card: CardInstance in target.hand:
		result.append(_serialize_choice_candidate(hand_card, target_id, "hand", true))
	return result


## 返回目标判定区中的选牌候选；viewer_id 保留与其他区域候选 API 一致，判定区牌默认公开。
func get_judgment_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	return _build_player_zone_candidates(viewer_id, target_id, false, false, true)


## 仅弃置玩家手牌中被明确选择的实体；装备与判定区 UID 不会被本端口处理。
func discard_selected_hand_cards(player_id: int, selected_uids: Array[int]) -> int:
	# 实际弃置数量；调用方据此判断费用是否完整支付。
	var discarded_count: int = 0
	# 持有者；不存在时安全返回 0。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return 0
	# 弃置批次；整批手牌共享一个批次事件，便于“一次弃置多张”类技能整批判定。
	_begin_discard_batch(player_id, "discard_selected_hand_cards")
	for selected_uid: int in selected_uids:
		# 从手牌区取出实体；take_hand_card 保证不会误取装备。
		var hand_card: CardInstance = player.take_hand_card(selected_uid)
		if hand_card == null:
			continue
		_move_to_discard(hand_card)
		discarded_count += 1
	_end_discard_batch()
	return discarded_count


## 弃置目标判定区中被明确选择的一张牌；成功返回 true。
func discard_selected_judgment_card(target_id: int, card_uid: int) -> bool:
	# 判定区持有者；不存在时失败。
	var target: PlayerState = state.get_player(target_id) if state != null else null
	if target == null:
		return false
	for judgment_index: int in range(target.judgment_area.size()):
		if target.judgment_area[judgment_index].uid == card_uid:
			_move_to_discard(target.judgment_area.pop_at(judgment_index))
			return true
	return false


## 判断两名玩家是否为队友；队友不包括自己，模式取自当前对局。
func are_teammates(from_player_id: int, to_player_id: int) -> bool:
	if state == null:
		return false
	return identity_rules.are_teammates(state.get_player(from_player_id), state.get_player(to_player_id), str(state.match_mode))


## 判断目标是否为来源的友方；友方包括自己，其他友方等于队友。
func is_friendly(from_player_id: int, to_player_id: int) -> bool:
	if state == null:
		return false
	return identity_rules.is_friendly(state.get_player(from_player_id), state.get_player(to_player_id), str(state.match_mode))


## 返回指定玩家可用作视为牌材料的全部自有牌；包含手牌、木牛“粮”与装备区。
func get_skill_material_candidates(player_id: int) -> Array[Dictionary]:
	# 材料候选结果；按手牌、木牛“粮”、标准装备槽顺序返回，保证UI、AI与回放枚举一致。
	var result: Array[Dictionary] = []
	# 材料持有者；不存在、阵亡或离场时不暴露任何可选实体。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game:
		return result
	for hand_card: CardInstance in player.hand:
		result.append(_serialize_choice_candidate(hand_card, player_id, "hand", true))
	for stored_card: CardInstance in player.wooden_ox_storage:
		result.append(_serialize_choice_candidate(stored_card, player_id, "wooden_ox", true))
	for slot: String in ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]:
		if player.equipment.has(slot):
			result.append(_serialize_choice_candidate(player.equipment[slot] as CardInstance, player_id, "equipment", true, slot))
	return result


## 返回除指定角色外的全部其他存活玩家 ID；顺序沿用当前状态座次数组，技能可直接作为目标选择候选。
func get_other_alive_player_ids(excluded_player_id: int) -> Array[int]:
	# 目标结果；只包含仍存活且不等于排除角色的稳定玩家 ID。
	var result: Array[int] = []
	if state == null:
		return result
	for player: PlayerState in state.players:
		if player.alive and not player.out_of_game and player.player_id != excluded_player_id:
			result.append(player.player_id)
	return result


## 返回来源角色当前攻击范围内的其他存活角色；excluded_player_ids 用于排除已被当前效果处理的角色。
func get_players_in_attack_range(source_id: int, excluded_player_ids: Array[int] = []) -> Array[int]:
	# 合法范围结果；保持权威座次顺序，界面、AI与回放会得到相同候选排列。
	var result: Array[int] = []
	if state == null or card_rules == null:
		return result
	# 攻击来源；死亡或离场角色没有可用于技能选择的攻击范围。
	var source: PlayerState = state.get_player(source_id)
	if source == null or not source.alive or source.out_of_game:
		return result
	# 当前攻击范围；武器范围和进攻、防御坐骑距离修正均由卡牌规则服务统一计算。
	var attack_range: int = card_rules.get_attack_range(source_id)
	for target: PlayerState in state.players:
		if not target.alive or target.out_of_game or target.player_id == source_id or excluded_player_ids.has(target.player_id):
			continue
		if card_rules.calculate_distance(source_id, target.player_id) <= attack_range:
			result.append(target.player_id)
	return result


## 将指定存活角色加入额外完整回合队列；技能侧应通过 `who.addPhase()` 调用本端口。
func add_phase(player_id: int, reason: String = "", allow_out_of_game: bool = false) -> bool:
	# 获得额外回合的角色；失效、阵亡或离场角色不能进入后续行动队列。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or state.game_over:
		return false
	_extra_turn_queue.append(player_id)
	add_log("%s获得了一个额外的回合。" % format_player_state_log_name(player))
	return true


## 将当前角色本回合尚未执行的四个主要阶段直接转换为出牌阶段；转换不产生跳过时机，也不登记额外阶段。
func convert_current_turn_main_phases_to_play(player_id: int, reason: String = "") -> bool:
	# 阶段转换角色；只允许当前回合仍存活在场的角色在结束阶段前建立本回合转换规则。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over or state.current_player_id != player_id or _get_effective_rule_phase() == "finish":
		return false
	# 转换阶段集合；复制统一主要阶段目录，避免技能侧维护判定、摸牌、出牌、弃牌四份硬编码。
	var converted_phases: Array[String] = RuleTimingCatalog.MAIN_PHASES.duplicate()
	_main_phase_play_conversions[player_id] = converted_phases
	# 转换原因只进入可回放运行时事件，不输出“跳过”或“额外阶段”日志，避免混淆阶段定义。
	_record_runtime_event("mainPhaseConversion", "phase", {"player_id":player_id, "target_phase":"play", "reason":reason}, {"converted_phases":converted_phases.duplicate()}, _current_turn_event_id)
	return true


## 判断指定原主要阶段是否在当前回合被直接转换为出牌阶段；普通出牌阶段本身无需特殊调度上下文。
func _is_main_phase_converted_to_play(player_id: int, phase_name: String) -> bool:
	if not RuleTimingCatalog.is_main_phase(phase_name):
		return false
	return (_main_phase_play_conversions.get(player_id, []) as Array).has(phase_name)


## 返回指定角色当前能否排队额外出牌阶段；阶段必须仍属于该角色的当前回合或其正在执行的额外弃牌阶段。
func can_add_play_phase(player_id: int) -> bool:
	# 获得阶段的角色；失效、阵亡、离场或终局后都不能继续加入阶段队列。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over or state.current_player_id != player_id:
		return false
	# 当前回合在结束阶段前均可登记后续出牌阶段；实际执行点由现有阶段流程统一消费。
	return _get_effective_rule_phase() in ["start", "judgment", "draw", "play", "discard", "finish"]


## 为指定角色排队一个额外出牌阶段；当前角色可在出牌阶段或弃牌阶段触发点登记。
func add_play_phase(player_id: int, reason: String = "") -> bool:
	# 获得额外出牌阶段的角色；公开查询统一处理存活、离场、终局、回合归属与阶段边界。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if not can_add_play_phase(player_id):
		return false
	_extra_play_phase_counts[player_id] = int(_extra_play_phase_counts.get(player_id, 0)) + 1
	# 当前规则阶段；普通选择会把公开阶段临时写为choice，因此必须读取选择保存的resume_phase才能保留真实插入点。
	var source_phase: String = _get_effective_rule_phase()
	# 本次额外出牌阶段的明确后继；额外阶段内再次获得阶段时继承当前阶段原本的最终去向。
	var return_point: String = _resolve_extra_play_phase_return_point(source_phase)
	# 当前角色的后继队列；与次数队列保持一一对应，多个额外阶段可以拥有不同的最终去向。
	var return_points: Array = (_extra_play_phase_return_points.get(player_id, []) as Array).duplicate()
	return_points.append(return_point)
	_extra_play_phase_return_points[player_id] = return_points
	# 弃牌阶段获得的额外出牌阶段完成后直接进入结束阶段，不能再次执行一个普通弃牌阶段。
	if return_point == "finish":
		_extra_play_phase_returns_to_finish[player_id] = true
	add_log("%s获得了一个额外的出牌阶段。" % format_player_state_log_name(player))
	return true


## 执行一个可属于非当前回合角色的独立额外出牌阶段；阶段结束后通过稳定技能上下文交回创建者。
func request_extra_play_phase(player_id: int, source_id: int, reason: String, completion_context: Dictionary) -> bool:
	if state == null or state.game_over or not _active_independent_play_phase.is_empty():
		return false
	# 阶段角色；死亡或离场角色不能获得新的独立出牌阶段。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	# 原回合角色；独立阶段完成后必须恢复其结束阶段，而不是按阶段角色座次推进正常下家。
	var original_player_id: int = state.current_player_id
	# 原公开阶段；通常为finish，仍完整保存以支持其他可复用规则入口。
	var original_phase: String = state.current_phase
	# 原阶段索引；恢复后界面与阶段守卫继续使用原回合位置。
	var original_phase_index: int = state.phase_index
	_active_independent_play_phase = {
		"phase_id":_next_inserted_phase_id,
		"player_id":player_id,
		"source_id":source_id,
		"reason":reason,
		"parent_event_id":state.current_event_id,
		"completion_context":completion_context.duplicate(true),
		"original_player_id":original_player_id,
		"original_phase":original_phase,
		"original_phase_index":original_phase_index,
		"original_ai_action_count":_ai_actions_this_turn,
	}
	_next_inserted_phase_id += 1
	# 新阶段使用独立AI行动额度；递增驱动令牌会令旧角色尚未执行的异步动作安全失效。
	_ai_drive_token += 1
	_ai_actions_this_turn = 0
	state.current_player_id = player_id
	_start_independent_extra_play_phase()
	return true


## 建立独立额外出牌阶段的完整phaseUse生命周期，并复用普通出牌合法性、界面与AI入口。
func _start_independent_extra_play_phase(change_completed: bool = false) -> void:
	if _active_independent_play_phase.is_empty() or state == null or state.game_over:
		return
	# 阶段角色ID；活动上下文是唯一来源，不能从原回合角色推断。
	var player_id: int = int(_active_independent_play_phase.get("player_id", -1))
	# 阶段角色状态；等待开始期间失效时直接结束本阶段并恢复原回合。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		_complete_active_independent_play_phase(true)
		return
	# 阶段来源角色；用于phaseChange与完成日志追溯技能效果来源。
	var source_id: int = int(_active_independent_play_phase.get("source_id", -1))
	# 前一公开阶段；通常是发动者的结束阶段。
	var previous_phase: String = state.current_phase
	if not change_completed:
		_change_phase_then("phaseChange", player_id, source_id, player_id, {"from_phase":previous_phase, "to_phase":"play", "extra_phase":true, "independent_phase":true}, int(_active_independent_play_phase.get("parent_event_id", -1)), Callable(self, "_start_independent_extra_play_phase").bind(true))
		return
	state.current_phase = "play"
	state.phase_index = 3
	# 【杀】次数与阶段级用牌历史均按新的独立出牌阶段重新计算。
	player.slash_count = 0
	player.play_phase_card_use_history.clear()
	player.play_phase_card_use_limit_exempt_history.clear()
	if reincarnation_skill_service != null:
		reincarnation_skill_service.on_play_phase_started(player_id)
	_record_runtime_event("phaseUse", "phase", {"player_id":player_id, "extra_phase":true, "independent_phase":true}, {}, int(_active_independent_play_phase.get("parent_event_id", -1)))
	_begin_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number, "extra_phase":true, "independent_phase":true}, int(_active_independent_play_phase.get("parent_event_id", -1)), Callable(self, "_resume_play_phase_body").bind(player_id), Callable(self, "_complete_active_independent_play_phase").bind(true))


## 完成或中断独立额外出牌阶段，恢复原回合展示并把控制权交回创建技能。
func _complete_active_independent_play_phase(interrupted: bool = false) -> void:
	if _active_independent_play_phase.is_empty():
		return
	# 已完成阶段快照；先清空活动字段，允许技能回调继续创建下一项独立阶段。
	var completed_phase: Dictionary = _active_independent_play_phase.duplicate(true)
	_active_independent_play_phase.clear()
	# 阶段角色ID；用于清理尚未完成的生命周期键和旧出牌请求。
	var player_id: int = int(completed_phase.get("player_id", -1))
	_cancel_active_play_choice("independent_extra_play_phase_complete")
	_started_phase_lifecycles.erase("%d:phaseUse" % player_id)
	_active_extra_play_phase_context.clear()
	_extra_play_phase_counts.erase(player_id)
	_extra_play_phase_return_points.erase(player_id)
	_extra_play_phase_returns_to_finish.erase(player_id)
	# 原回合角色与阶段；恢复发生在技能回调前，使后续额外弃牌或出牌阶段拥有正确父流程。
	var original_player_id: int = int(completed_phase.get("original_player_id", -1))
	state.current_player_id = original_player_id
	state.current_phase = str(completed_phase.get("original_phase", "finish"))
	state.phase_index = int(completed_phase.get("original_phase_index", 5))
	_ai_actions_this_turn = int(completed_phase.get("original_ai_action_count", 0))
	_ai_drive_token += 1
	# 创建阶段的技能上下文；缺失或换将失效时只恢复原回合，不调用旧实例。
	var completion_context: Dictionary = completed_phase.get("completion_context", {}) as Dictionary
	# 回调技能持有者ID；与阶段角色相互独立。
	var skill_owner_id: int = int(completion_context.get("skill_owner_id", -1))
	# 回调技能稳定ID；空值表示纯系统阶段。
	var skill_id: String = str(completion_context.get("skill_id", ""))
	# 当前运行时技能实例；武将代次不一致时安全跳过。
	var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id)
	if skill != null and skill.matches_character_generation(int(completion_context.get("skill_character_generation", -1))) and skill.can_use_effect(bool(completion_context.get("locked_skill_segment", false))):
		# 阶段是否因角色死亡、离场或取消被中断；技能可按业务需要读取但不能改写核心阶段状态。
		var stable_completion_context: Dictionary = completion_context.duplicate(true)
		stable_completion_context["phase_interrupted"] = interrupted
		skill.continue_extra_phase(stable_completion_context)
	_emit_state()
	# 技能回调可能登记“然后”步骤或下一项阶段；统一管线和回合尾部守卫会按顺序继续。
	_resume_settlement_pipeline()
	# 原回合角色在独立阶段期间死亡或离场时，恢复后必须从其真实回合中断入口推进。
	var original_player: PlayerState = state.get_player(original_player_id) if state != null else null
	if original_player != null and state.current_player_id == original_player_id and (not original_player.alive or original_player.out_of_game) and _active_independent_play_phase.is_empty():
		if original_player.out_of_game:
			_advance_after_current_player_out_of_game(original_player_id)
		else:
			_advance_after_current_player_death(original_player_id)


## 返回选择窗口背后的真实规则阶段；没有普通选择时直接返回当前阶段，避免业务代码依赖临时choice展示状态。
func _get_effective_rule_phase() -> String:
	if state == null:
		return ""
	if state.current_phase == "choice" and not _pending_card_choice.is_empty():
		return str(_pending_card_choice.get("resume_phase", ""))
	return state.current_phase


## 根据额外阶段的插入位置确定结束后继；额外出牌阶段内继续插入时继承当前活动阶段的既定后继。
func _resolve_extra_play_phase_return_point(source_phase: String) -> String:
	if source_phase == "play" and not _active_extra_play_phase_context.is_empty():
		return str(_active_extra_play_phase_context.get("return_point", "discard"))
	if source_phase == "play" and not _active_converted_play_phase_context.is_empty():
		return str(_active_converted_play_phase_context.get("return_point", "discard"))
	if source_phase == "play" and not _active_independent_play_phase.is_empty():
		return "independent_complete"
	if source_phase == "discard":
		return "finish"
	if source_phase == "finish":
		return "turn_complete"
	return "discard"


## 消费指定角色队首的一个额外出牌阶段，并把其稳定后继写入当前活动上下文。
func _consume_extra_play_phase(player_id: int) -> bool:
	# 当前等待次数；次数与后继队列同时递减，任一缺失时使用标准弃牌后继完成防御性收口。
	var pending_count: int = int(_extra_play_phase_counts.get(player_id, 0))
	if pending_count <= 0:
		return false
	if pending_count == 1:
		_extra_play_phase_counts.erase(player_id)
	else:
		_extra_play_phase_counts[player_id] = pending_count - 1
	# 当前角色后继队列；队首对应本次即将开始的额外出牌阶段。
	var return_points: Array = (_extra_play_phase_return_points.get(player_id, []) as Array).duplicate()
	# 本次阶段结束后的稳定去向；异常旧状态默认进入弃牌阶段，保持原有行为。
	var return_point: String = str(return_points.pop_front()) if not return_points.is_empty() else "discard"
	if return_points.is_empty():
		_extra_play_phase_return_points.erase(player_id)
	else:
		_extra_play_phase_return_points[player_id] = return_points
	# 兼容标记只反映尚未消费的弃牌阶段插入项；真实调度始终读取当前活动上下文与后继队列。
	var has_finish_return: bool = return_point == "finish" or return_points.has("finish")
	if has_finish_return:
		_extra_play_phase_returns_to_finish[player_id] = true
	else:
		_extra_play_phase_returns_to_finish.erase(player_id)
	_active_extra_play_phase_context = {"player_id":player_id, "return_point":return_point}
	return true


## 执行一个由技能插入的额外弃牌阶段；阶段开始、弃牌选择和完成回调都经过统一时机与选择协议。
func request_extra_discard_phase(player_id: int, source_id: int, reason: String, completion_context: Dictionary) -> bool:
	if state == null or state.game_over or not _active_extra_discard_phase.is_empty():
		return false
	# 阶段角色；死亡或离场角色不能建立新的额外弃牌阶段。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	# 阶段完成上下文；技能归属使用独立字段，避免本阶段的系统弃牌选择被提前交给技能恢复入口。
	_active_extra_discard_phase = {
		"phase_id":_next_inserted_phase_id,
		"player_id":player_id,
		"source_id":source_id,
		"reason":reason,
		"parent_event_id":state.current_event_id,
		"completion_context":completion_context.duplicate(true),
		"status":"begin_before",
	}
	_next_inserted_phase_id += 1
	# 额外阶段使用独立生命周期键，不覆盖相同角色尚在等待的普通弃牌阶段。
	_active_extra_discard_phase["lifecycle_scope"] = ":extra:%d" % int(_active_extra_discard_phase.phase_id)
	# 阶段前置参数；来源角色与原父事件完整保留。
	var phase_data: Dictionary = {"turn_number":state.turn_number, "extra_phase":true, "reason":reason}
	# 专属服务只负责窗口，主体仍使用统一的手牌上限与弃牌选择接口。
	var phase_service: RefCounted = PHASE_LIFECYCLE_SERVICE_SCRIPT.new(self)
	return phase_service.begin("phaseDiscard", player_id, phase_data, int(_active_extra_discard_phase.get("parent_event_id", -1)), Callable(self, "_begin_active_extra_discard_body"), Callable(self, "_cancel_active_extra_discard_phase"), str(_active_extra_discard_phase.lifecycle_scope), source_id)


## 额外弃牌Before和Begin均完成后才计算主体；不靠公开阶段恢复入口猜测。
func _begin_active_extra_discard_body() -> void:
	if _active_extra_discard_phase.is_empty():
		return
	_active_extra_discard_phase["status"] = "body"
	_continue_active_extra_discard_phase_body()


## 取消未进入主体的额外阶段；不发放以完整阶段为条件的技能收益。
func _cancel_active_extra_discard_phase() -> void:
	_active_extra_discard_phase.clear()
	_resume_settlement_pipeline()


## 在额外弃牌阶段开始时机全部恢复后计算弃牌数量，并在需要时创建强制手牌选择。
func _continue_active_extra_discard_phase_body() -> void:
	if _active_extra_discard_phase.is_empty() or has_pending_card_choice():
		return
	# 阶段角色；等待触发期间死亡或离场时不再移动牌，但仍安全结束已经进入Begin的阶段。
	var player_id: int = int(_active_extra_discard_phase.get("player_id", -1))
	# 阶段角色状态；用于复核存活、在场和当前实际手牌上限。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		_finish_active_extra_discard_phase()
		return
	# 最终弃牌数量；额外弃牌阶段与普通弃牌阶段共用“手牌数减手牌上限”规则。
	var discard_count: int = maxi(player.hand.size() - player.get_hand_limit(), 0)
	if discard_count <= 0:
		_finish_active_extra_discard_phase()
		return
	# 自身普通手牌候选；装备、判定区与木牛“粮”都不属于弃牌阶段的手牌上限弃置。
	var candidates: Array[Dictionary] = _build_player_zone_candidates(player_id, player_id, true, false, false)
	# 系统恢复上下文；完成技能信息保存在活动阶段字典，不进入普通技能选择分流。
	var context: Dictionary = {"kind":"extra_discard_phase", "player_id":player_id, "discard_count":discard_count}
	_active_extra_discard_phase["status"] = "discard_choice"
	# 已同步取得的弃牌实体 UID；人类等待请求时为空，AI或零延迟恢复时可直接进入弃置流程。
	var selected_uids: Array[int] = request_card_choice(player_id, "额外弃牌阶段", "请选择%d张手牌弃置" % discard_count, candidates, discard_count, discard_count, false, context)
	if has_pending_card_choice():
		return
	_continue_extra_discard_phase_choice(context, selected_uids)


## 恢复额外弃牌阶段的强制选牌；只弃置仍在本人普通手牌区中的合法实体。
func _continue_extra_discard_phase_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	if _active_extra_discard_phase.is_empty() or int(context.get("player_id", -1)) != int(_active_extra_discard_phase.get("player_id", -1)):
		return
	# 阶段角色 ID；每张牌继续通过公开手牌弃置端口复核等待期间区域变化。
	var player_id: int = int(context.get("player_id", -1))
	# 实际弃置数量；合法强制选择正常等于请求数量，异常区域变化时日志记录真实成功数。
	var discarded_count: int = 0
	for selected_uid: int in selected_uids:
		if discard_card_from_hand(player_id, selected_uid):
			discarded_count += 1
	# 阶段角色；日志只读取永久显示名，不暴露手牌定义。
	var player: PlayerState = state.get_player(player_id)
	if player != null:
		add_log("%s在额外弃牌阶段完成弃置。" % format_player_state_log_name(player))
	_finish_active_extra_discard_phase()


## 依次完成额外弃牌阶段的End与After；任一时机创建选择时保存状态并等待统一恢复入口继续。
func _finish_active_extra_discard_phase() -> void:
	if _active_extra_discard_phase.is_empty():
		return
	_active_extra_discard_phase["status"] = "ending"
	# 阶段角色与独立实例范围；相同角色的普通阶段继续保留自己的生命周期。
	var player_id: int = int(_active_extra_discard_phase.get("player_id", -1))
	# 统一收尾服务；结束窗口顺序、重复调用与预算让步不再由阶段单独实现。
	var phase_service: RefCounted = PHASE_LIFECYCLE_SERVICE_SCRIPT.new(self)
	phase_service.complete("phaseDiscard", player_id, {"turn_number":state.turn_number, "extra_phase":true, "reason":str(_active_extra_discard_phase.get("reason", ""))}, int(_active_extra_discard_phase.get("parent_event_id", -1)), Callable(self, "_complete_active_extra_discard_phase"), str(_active_extra_discard_phase.get("lifecycle_scope", "")))


## 完成额外弃牌阶段并把控制权交回创建它的技能实例；阶段字典先清空以允许回调继续创建新阶段。
func _complete_active_extra_discard_phase() -> void:
	if _active_extra_discard_phase.is_empty():
		return
	# 稳定完成上下文；先复制再清空，避免技能回调重入时覆盖仍在读取的字典。
	var completed_phase: Dictionary = _active_extra_discard_phase.duplicate(true)
	_active_extra_discard_phase.clear()
	# 创建阶段的技能上下文；缺失技能表示纯系统调用，只需结束阶段而不执行额外效果。
	var completion_context: Dictionary = completed_phase.get("completion_context", {}) as Dictionary
	# 完成回调的技能持有者 ID；用于从权威运行时技能表定位唯一实例。
	var skill_owner_id: int = int(completion_context.get("skill_owner_id", -1))
	# 完成回调的稳定技能 ID；空值表示创建者不需要接收阶段完成通知。
	var skill_id: String = str(completion_context.get("skill_id", ""))
	# 接收额外阶段完成回调的运行时技能实例；实例失效时安全跳过回调。
	var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id)
	if skill != null and skill.matches_character_generation(int(completion_context.get("skill_character_generation", -1))) and skill.can_use_effect(bool(completion_context.get("locked_skill_segment", false))):
		skill.continue_extra_phase(completion_context)
	# 回调可能登记下一项阶段或技能“然后”步骤；全部活动项排空后才允许结束阶段继续收尾。
	_resume_settlement_pipeline()


## 结束当前出牌阶段；武将技能通过该公开端口实现“跳过出牌阶段”，不直接调用控制器私有流程。
func end_current_play_phase(player_id: int) -> bool:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return false
	_cancel_active_play_choice("skill_ended_play_phase")
	_end_play_phase(player_id)
	return true


## 跳过当前角色正在进行的主要阶段；阶段开始技确认后可调用，其他阶段与其他角色请求会被拒绝。
func skip_current_main_phase(player_id: int, phase_name: String, reason: String = "") -> bool:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != phase_name or not RuleTimingCatalog.is_main_phase(phase_name):
		return false
	# 当前阶段角色；死亡或离场后由各自回合中断入口处理，不再建立阶段跳过转场。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	# 当前阶段 Begin 时机；阶段开始技能完成选择后决定跳过时，必须终止其尚未询问的同层处理器，防止旧时机跨越阶段边界恢复。
	var phase_begin_timing_name: String = RuleTimingCatalog.get_main_phase_timing_name(phase_name, "Begin")
	if trigger_manager != null and not phase_begin_timing_name.is_empty():
		trigger_manager.cancel_matching_dispatches(phase_begin_timing_name, player_id, "phase_skipped")
	player.skipped_phases[phase_name] = true
	add_log("%s跳过%s。" % [format_player_state_log_name(player), {"judgment":"判定阶段", "draw":"摸牌阶段", "play":"出牌阶段", "discard":"弃牌阶段"}.get(phase_name, phase_name)])
	match phase_name:
		"judgment":
			_judgment_flow_token += 1
			_judgment_flow_in_progress = false
			_clear_pending_judgment_request()
			_started_phase_lifecycles.erase("%d:phaseJudge" % player_id)
			_emit_rule_timing("phaseJudgeSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number, "reason":reason}, _current_turn_event_id)
			state.current_phase = "judgment_skipped"
			_schedule_phase_transition(player_id, "judgment_skipped", Callable(self, "_enter_draw_phase").bind(player_id))
		"draw":
			_started_phase_lifecycles.erase("%d:phaseDraw" % player_id)
			_emit_rule_timing("phaseDrawSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number, "reason":reason}, _current_turn_event_id)
			state.current_phase = "draw_skipped"
			_schedule_phase_transition(player_id, "draw_skipped", Callable(self, "_enter_play_phase").bind(player_id))
		"play":
			_cancel_active_play_choice("main_phase_skipped")
			_started_phase_lifecycles.erase("%d:phaseUse" % player_id)
			_emit_rule_timing("phaseUseSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number, "reason":reason}, _current_turn_event_id)
			_end_play_phase(player_id, false, true)
		"discard":
			_started_phase_lifecycles.erase("%d:phaseDiscard" % player_id)
			_emit_rule_timing("phaseDiscardSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number, "reason":reason}, _current_turn_event_id)
			state.current_phase = "discard_skipped"
			_schedule_phase_transition(player_id, "discard_skipped", Callable(self, "_enter_finish_phase").bind(player_id))
	return true


## 返回一名玩家装备区的公开候选快照；可选槽位列表为空时按标准顺序返回全部装备。
func get_equipment_candidates(_viewer_id: int, target_id: int, requested_slots: Array[String] = []) -> Array[Dictionary]:
	# 装备候选结果；公开装备不因查看者不同而隐藏牌面。
	var result: Array[Dictionary] = []
	# 装备所有者；不存在时返回空数组。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		return result
	# 实际槽位顺序；卡牌文件可只声明自身需要操作的槽位子集。
	var slots: Array[String] = requested_slots.duplicate()
	if slots.is_empty():
		slots = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]
	for slot: String in slots:
		if target.equipment.has(slot):
			result.append(_serialize_choice_candidate(target.equipment[slot] as CardInstance, target_id, "equipment", true, slot))
	return result


## 返回公共处理区中指定 UID 的公开候选；展示牌选择只暴露仍位于处理区的实体。
func get_processing_candidates(card_uids: Array[int]) -> Array[Dictionary]:
	# 公共候选结果；顺序与传入 UID 顺序一致。
	var candidates: Array[Dictionary] = []
	for card_uid: int in card_uids:
		# 当前处理区实体；等待期间已移动的牌不会继续显示为候选。
		var card: CardInstance = _find_processing_card(card_uid)
		if card != null:
			candidates.append(_serialize_choice_candidate(card, -1, "processing", true))
	return candidates


## 公开并展示一张仍在指定玩家手牌区的牌；返回实体供卡牌源码继续读取花色与点数。
func reveal_hand_card(player_id: int, card_uid: int, reason: String) -> CardInstance:
	# 展示者状态；无效玩家不能展示手牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null
	# 被展示手牌；只公开牌面，不改变其所属区域。
	var card: CardInstance = player.find_hand_card(card_uid)
	if card == null:
		return null
	_ensure_card_movement()
	card_movement.reveal_card(card)
	add_log("%s展示了%s。" % [player.display_name, describe_card(card)])
	# 展示事件 ID；表现层使用正式卡牌视图从武将区域飞入中央牌桌。
	var show_cards_event_id: int = _record_runtime_event("showCards", "card_presentation", {"player_id":player_id, "card_uids":[card.uid], "reason":reason}, {}, _current_rule_parent_event_id())
	_request_card_presentation(card, player_id, [], "showCards", show_cards_event_id, false)
	return card


## 标记逐目标卡牌的当前目标完成；卡牌源码在异步选择恢复后通过该端口推进目标游标。
func complete_card_target(parent_card_uid: int) -> void:
	_complete_active_card_target(parent_card_uid)


## 完成整牌型卡牌处理并依据定义移动父牌；只供已结束全部异步步骤的卡牌源码调用。
func finish_processing_card(parent_card_uid: int) -> void:
	_finalize_processing_card(parent_card_uid)


## 更新一张活动卡牌共享结算上下文中的单个可序列化字段；装备源码不能直接访问控制器内部字典。
func set_active_card_resolution_value(parent_card_uid: int, key: String, value: Variant) -> bool:
	if not _active_card_resolutions.has(parent_card_uid) or key.is_empty():
		return false
	# 当前活动结算上下文；更新后写回以保证后续目标读取最新值。
	var resolution_context: Dictionary = _active_card_resolutions[parent_card_uid] as Dictionary
	resolution_context[key] = value
	_active_card_resolutions[parent_card_uid] = resolution_context
	return true


## 将一张仍处于使用生命周期的牌对指定目标标记为无效；只跳过该目标内容，不取消其他合法目标。
func exclude_card_target(card_uid: int, target_id: int, _reason: String = "") -> bool:
	if not _card_use_contexts.has(card_uid):
		return false
	# 当前使用牌共享上下文；目标必须仍属于最终目标数组，客户端不能借此排除未指定角色。
	var card_use_context: Dictionary = _card_use_contexts[card_uid] as Dictionary
	if not (card_use_context.get("target_ids", []) as Array).has(target_id):
		return false
	# 被排除目标数组；重复请求保持幂等并继续返回true，便于多个效果安全表达同一结果。
	var excluded_target_ids: Array = card_use_context.get("excluded_target_ids", []) as Array
	if not excluded_target_ids.has(target_id):
		excluded_target_ids.append(target_id)
	card_use_context["excluded_target_ids"] = excluded_target_ids
	_card_use_contexts[card_uid] = card_use_context
	return true


## 将一张仍处于使用生命周期的牌对指定目标标记为直击；响应流程会跳过该目标的可响应牌询问。
func add_card_direct_hit_target(card_uid: int, target_id: int, _reason: String = "") -> bool:
	if not _card_use_contexts.has(card_uid):
		return false
	# 当前使用牌共享上下文；只允许最终目标获得直击标记，避免伪造无关角色响应状态。
	var card_use_context: Dictionary = _card_use_contexts[card_uid] as Dictionary
	if not (card_use_context.get("target_ids", []) as Array).has(target_id):
		return false
	# 直击目标数组；重复追加保持幂等，后续【杀】和锦囊响应统一读取本字段。
	var direct_hit_target_ids: Array = card_use_context.get("direct_hit_target_ids", []) as Array
	if not direct_hit_target_ids.has(target_id):
		direct_hit_target_ids.append(target_id)
	card_use_context["direct_hit_target_ids"] = direct_hit_target_ids
	_card_use_contexts[card_uid] = card_use_context
	return true


## 为当前使用牌对指定目标累加伤害加值；数据保存在使用牌共享customArgs中并随目标内容读取。
func add_card_target_damage_bonus(card_uid: int, target_id: int, amount: int, _reason: String = "") -> bool:
	if amount == 0 or not _card_use_contexts.has(card_uid):
		return false
	# 当前使用牌上下文；只能修改仍属于最终目标数组的角色，避免技能向无关角色预埋伤害。
	var card_use_context: Dictionary = _card_use_contexts[card_uid] as Dictionary
	if not (card_use_context.get("target_ids", []) as Array).has(target_id):
		return false
	# 每目标参数字典；字符串目标ID保证网络与回放序列化后键语义稳定。
	var custom_args: Dictionary = (card_use_context.get("custom_args", {}) as Dictionary).duplicate(true)
	var target_args: Dictionary = (custom_args.get(str(target_id), {}) as Dictionary).duplicate(true)
	target_args["damage_bonus"] = int(target_args.get("damage_bonus", 0)) + amount
	custom_args[str(target_id)] = target_args
	card_use_context["custom_args"] = custom_args
	_card_use_contexts[card_uid] = card_use_context
	# 同步落到仍在等待提交的用牌修改窗口；只写共享上下文会被随后的结果提交用派发前快照覆盖。
	_publish_pending_custom_args(card_uid, str(target_id), "damage_bonus", amount)
	return true


## 返回当前使用牌对指定目标已经登记的伤害加值；没有活动上下文时返回0。
func get_card_target_damage_bonus(card_uid: int, target_id: int) -> int:
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	var custom_args: Dictionary = card_use_context.get("custom_args", {}) as Dictionary
	var target_args: Dictionary = custom_args.get(str(target_id), {}) as Dictionary
	return int(target_args.get("damage_bonus", 0))


## 把异步恢复期间写入的每目标自定义参数同步到仍在等待提交的用牌修改窗口。
## 使用牌时机的“派发”与“结果提交”是两个独立步骤：可选技能尚未应答时序列不会提交结果，
## 技能在恢复回调里写入的实时数据必须同时落到该窗口的事件数据，否则提交时会用派发前
## 快照整体覆盖共享上下文，技能效果静默失效。没有等待中的窗口时保持纯写入，不影响旧流程。
func _publish_pending_custom_args(card_uid: int, target_key: String, argument_name: String, amount: int) -> void:
	if amount == 0:
		return
	# 等待中的使用牌修改窗口；同一张牌同一时刻至多有一个窗口处于等待应答状态。
	var pending_event: RuleEvent = _find_pending_card_timing_event(card_uid)
	if pending_event == null:
		return
	# 事件侧每目标参数字典；与共享上下文使用同一套字符串目标键协议。
	var custom_args: Dictionary = (pending_event.data.get("custom_args", {}) as Dictionary).duplicate(true)
	var target_args: Dictionary = (custom_args.get(target_key, {}) as Dictionary).duplicate(true)
	target_args[argument_name] = int(target_args.get(argument_name, 0)) + amount
	custom_args[target_key] = target_args
	pending_event.data["custom_args"] = custom_args


## 返回当前正等待可选技能应答的使用牌修改窗口；没有等待中的窗口时返回null。
## 只扫描续接中的步骤序列，不新增需要跨帧维护或进入快照的运行时状态。
func _find_pending_card_timing_event(card_uid: int) -> RuleEvent:
	# 最近创建的候选序列身份；嵌套窗口取最内层，确保数据落到真正等待应答的那一个。
	var latest_sequence_id: int = -1
	# 最近创建的候选窗口事件；未命中任何序列时为null，调用方据此跳过同步。
	var latest_event: RuleEvent = null
	for sequence_id_variant: Variant in _rule_sequences.keys():
		# 当前序列身份；数值越大表示创建越晚。
		var sequence_id: int = int(sequence_id_variant)
		if sequence_id <= latest_sequence_id:
			continue
		# 当前序列；已结束或被取消的序列不持有等待窗口。
		var sequence: RuleStepSequence = _rule_sequences[sequence_id] as RuleStepSequence
		if sequence == null or sequence.waiting_event == null:
			continue
		# 事件数据契约；使用牌修改窗口固定携带卡牌UID与每目标自定义参数两组字段。
		if int(sequence.waiting_event.data.get("card_uid", -1)) != card_uid:
			continue
		if not sequence.waiting_event.data.has("custom_args"):
			continue
		latest_sequence_id = sequence_id
		latest_event = sequence.waiting_event
	return latest_event


## 记录一张牌收到的一次直接响应及响应者；只累计直接以该牌为父对象的实际打出，不递归计算响应牌受到的反响应。
func record_card_direct_response(card_uid: int, responder_id: int = -1) -> bool:
	if card_uid < 0 or not _card_use_contexts.has(card_uid):
		return false
	# 当前使用牌上下文；直接响应数在整张牌的全部目标间共享，适用于【决斗】连续打【杀】等流程。
	var card_use_context: Dictionary = _card_use_contexts[card_uid] as Dictionary
	card_use_context["direct_response_count"] = maxi(int(card_use_context.get("direct_response_count", 0)) + 1, 0)
	# 直接响应者ID序列；保留重复项，使同一角色在【决斗】中连续打出的多张【杀】仍逐张计数。
	var direct_response_player_ids: Array = (card_use_context.get("direct_response_player_ids", []) as Array).duplicate()
	direct_response_player_ids.append(responder_id)
	card_use_context["direct_response_player_ids"] = direct_response_player_ids
	_card_use_contexts[card_uid] = card_use_context
	return true


## 返回一张仍处于使用生命周期中的牌累计收到的直接响应数；生命周期外或无响应时返回0。
func get_card_direct_response_count(card_uid: int) -> int:
	return maxi(int((_card_use_contexts.get(card_uid, {}) as Dictionary).get("direct_response_count", 0)), 0)


## 返回除指定角色外的直接响应牌数量；用于“其他角色响应”语义，未知旧记录按其他角色处理以保持兼容。
func get_card_direct_response_count_excluding_player(card_uid: int, excluded_player_id: int) -> int:
	# 当前使用牌上下文；生命周期外没有可统计的响应。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 响应者序列；每个元素对应一张实际打出的直接响应牌，同一角色可出现多次。
	var responder_ids: Array = card_use_context.get("direct_response_player_ids", []) as Array
	if responder_ids.is_empty():
		return get_card_direct_response_count(card_uid)
	# 排除指定角色后的响应牌数量；负数未知ID不会等于任何正常玩家ID。
	var result: int = 0
	for responder_id_variant: Variant in responder_ids:
		if int(responder_id_variant) != excluded_player_id:
			result += 1
	return result


## 返回一张仍处于使用生命周期中的牌的最终目标数；使用牌时机增删目标后读取最新权威数组。
func get_card_use_target_count(card_uid: int) -> int:
	return (_card_use_contexts.get(card_uid, {}) as Dictionary).get("target_ids", []).size()


## 从响应上下文登记对父牌的一次直接响应；缺少父牌UID的救援、装备询问和独立响应不会误计数。
func _record_direct_response_from_context(context: Dictionary) -> void:
	record_card_direct_response(int(context.get("parent_card_uid", -1)), int(context.get("responder_id", -1)))


## 在整牌准备选择完成后恢复兼容逐目标游标；真实事件树由父事件自然恢复，不主动重复推进。
func continue_card_after_preparation(parent_card_uid: int) -> void:
	# 当前使用牌生命周期；runtime_managed 表示真实 CardUseEvent 正在负责后续步骤。
	var card_use_context: Dictionary = _card_use_contexts.get(parent_card_uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(parent_card_uid)


## 按稳定 UID 弃置玩家手牌区或装备区中被明确选择的牌；不存在或已移动的 UID 会安全跳过。
func discard_selected_hand_equipment(player_id: int, selected_uids: Array[int]) -> int:
	# 弃置批次；整批费用牌共享一个批次事件，便于“一次弃置多张”类技能整批判定。
	_begin_discard_batch(player_id, "discard_selected_hand_equipment")
	# 实际弃置数量；调用方据此判断装备费用是否完整支付。
	var discarded_count: int = 0
	for selected_uid: int in selected_uids:
		if _discard_selected_player_card(player_id, selected_uid):
			discarded_count += 1
	_end_discard_batch()
	return discarded_count


## 返回玩家武将配置中的性别；未知或缺失配置返回 unknown。
func get_player_gender(player_id: int) -> String:
	# 指定玩家状态；用于取得武将 ID。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return "unknown"
	return str(GameDatabase.get_character(player.character_id).get("gender", "unknown"))


## 从牌堆顶亮出指定数量的公共牌并放入处理区。
func reveal_top_cards(count: int) -> Array[CardInstance]:
	# 亮牌结果；顺序与抽取顺序一致。
	var result: Array[CardInstance] = []
	for _index: int in range(maxi(count, 0)):
		if state.draw_pile.is_empty():
			_reshuffle_discard_pile()
		if state.draw_pile.is_empty():
			_end_match_as_draw("deck_empty_reveal")
			break
		# 当前亮出的牌；公共处理区不属于任何玩家。
		_ensure_card_movement()
		var card: CardInstance = state.draw_pile.back()
		_move_card_with_timings(card, "processing", -1, "reveal", state.current_event_id)
		result.append(card)
	return result


## 返回仅供指定观察者观看的牌堆顶候选；牌仍留在摸牌堆，选择暂停期间不会公开移动或改变原顺序。
func get_top_draw_card_candidates(viewer_id: int, count: int) -> Array[Dictionary]:
	# 私有候选结果；顺序从牌堆最上方到更下方，左侧牌因此对应更早的后续摸牌。
	var result: Array[Dictionary] = []
	if state == null or state.game_over or count <= 0:
		return result
	# 牌堆不足时先执行统一重洗；重洗事实公开，但观看到的具体牌面只进入选择者私有请求。
	if state.draw_pile.size() < count and not state.discard_pile.is_empty():
		_reshuffle_discard_pile()
	var actual_count: int = mini(count, state.draw_pile.size())
	for offset: int in range(actual_count):
		# 当前牌堆顶实体；数组末尾是最顶端，offset递增表示逐步向牌堆下方观看。
		var card: CardInstance = state.draw_pile[state.draw_pile.size() - 1 - offset]
		result.append(_serialize_choice_candidate(card, -1, "processing", true))
	return result


## 将仍位于摸牌堆中的指定实体交给角色手牌；用于观看牌堆后的精确获得，不要求该牌仍是最顶端。
func gain_draw_pile_card_by_uid(player_id: int, card_uid: int, reason: String = "gain_viewed_draw_card") -> CardInstance:
	# 获得者与目标实体；离场角色或已离开摸牌堆的旧UID不能完成获得。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game:
		return null
	var card: CardInstance = null
	for draw_card: CardInstance in state.draw_pile:
		if draw_card.uid == card_uid:
			card = draw_card
			break
	if card == null:
		return null
	_prepare_hidden_pile_gain(card, player_id)
	_ensure_card_movement()
	if _move_card_with_timings(card, "hand", player_id, reason, state.current_event_id, "", [player_id], true) == null:
		return null
	add_log("%s从观看的牌中获得了一张牌。" % format_player_state_log_name(player))
	return card


## 将指定摸牌堆实体按双行结果放回牌堆顶或牌堆底；ordered_uids中前top_count张属于顶行。
func arrange_draw_pile_cards(ordered_uids: Array[int], top_count: int, reason: String = "pile_arrangement") -> bool:
	if state == null or state.game_over or ordered_uids.is_empty() or top_count < 0 or top_count > ordered_uids.size():
		return false
	# 当前可重排实体映射；所有UID必须唯一且仍在摸牌堆，旧请求不能重排已经被其他效果移动的牌。
	var cards_by_uid: Dictionary = {}
	for card_uid: int in ordered_uids:
		if cards_by_uid.has(card_uid):
			return false
		var matched_card: CardInstance = null
		for draw_card: CardInstance in state.draw_pile:
			if draw_card.uid == card_uid:
				matched_card = draw_card
				break
		if matched_card == null:
			return false
		cards_by_uid[card_uid] = matched_card
	# 先移除全部被观看实体；牌堆中未参与本次排序的牌保持相对顺序不变。
	for card_uid: int in ordered_uids:
		state.draw_pile.erase(cards_by_uid[card_uid] as CardInstance)
	# 底行从左到右表示由更上方到更下方；逐张push_front可得到右侧牌更靠近数组底端的实际结构。
	for ordered_index: int in range(top_count, ordered_uids.size()):
		state.draw_pile.push_front(cards_by_uid[ordered_uids[ordered_index]] as CardInstance)
	# 顶行左侧是牌堆最上方；反向append后，最左牌最终位于数组末尾。
	for ordered_index: int in range(top_count - 1, -1, -1):
		state.draw_pile.append(cards_by_uid[ordered_uids[ordered_index]] as CardInstance)
	state.random_history.append({"kind":reason, "ordered_card_uids":ordered_uids.duplicate(), "top_count":top_count})
	_emit_state()
	return true


## 将角色普通手牌数调整至指定值；不足时摸牌，超出时由该角色选择并弃置差额。
func adjust_hand_size(player_id: int, target_count: int, completion_context: Dictionary = {}) -> bool:
	if state == null or state.game_over:
		return false
	# 调整角色；死亡或离场角色不能通过本机制移动手牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	var normalized_target_count: int = maxi(target_count, 0)
	var difference: int = normalized_target_count - player.hand.size()
	if difference > 0:
		draw(player_id, difference)
		# 摸牌产生嵌套选择时由通用调整机制登记调用者后续，避免技能读取控制器私有请求状态。
		if has_pending_card_choice():
			var completion_skill_owner_id: int = int(completion_context.get("skill_owner_id", -1))
			var completion_skill_id: String = str(completion_context.get("skill_id", ""))
			if completion_skill_owner_id >= 0 and not completion_skill_id.is_empty():
				defer_skill_settlement(completion_skill_owner_id, completion_skill_id, completion_context)
		return true
	if difference == 0:
		return true
	# 超出目标的手牌候选；选择上下文不直接绑定具体技能，完成后通过独立completion字段恢复调用者。
	var discard_count: int = -difference
	var candidates: Array[Dictionary] = _build_player_zone_candidates(player_id, player_id, true, false, false)
	var context: Dictionary = {"kind":"adjust_hand_size", "player_id":player_id, "target_count":normalized_target_count, "completion_context":completion_context.duplicate(true)}
	request_card_choice(player_id, "调整手牌", "请选择%d张手牌弃置" % discard_count, candidates, discard_count, discard_count, false, context)
	return true


## 将五谷丰登亮出的牌交给指定玩家手牌。
func give_revealed_card(player_id: int, card: CardInstance) -> void:
	# 获得牌的玩家状态；死亡玩家不会在正常结算中调用。
	var player: PlayerState = state.get_player(player_id)
	# 展示牌来源区域；获得动画从桌面中央展示区移动到角色武将锚点。
	# 该来源现由 CardMovementService 在移动前写入统一事件，五谷选择完成后只生成一张获得表现牌。
	_ensure_card_movement()
	_move_card_with_timings(card, "hand", player_id, "gain", state.current_event_id, "", [player_id])
	add_log("%s从展示牌中获得了%s。" % [player.display_name, describe_card(card)])


## 将未被选择的展示牌移入弃牌堆。
func discard_revealed_card(card: CardInstance) -> void:
	_move_to_discard(card)


## 将任意已由规则确认归属的实体牌置入弃牌堆；装备附属区清理使用同一权威移动端口。
func discard_card_instance(card: CardInstance) -> void:
	if card != null:
		_move_to_discard(card)


## 将一张普通手牌移动到指定装备附属区域；返回成功移动的实体牌。
func move_hand_card_to_equipment_attachment(owner_id: int, card_uid: int, attachment_zone: String) -> CardInstance:
	# 装备持有者；附属材料只能来自其普通手牌区。
	var owner: PlayerState = state.get_player(owner_id)
	if owner == null or attachment_zone.is_empty():
		return null
	# 被附属的手牌；不存在时移动失败。
	var card: CardInstance = owner.take_hand_card(card_uid)
	if card == null:
		return null
	_ensure_card_movement()
	if _move_card_with_timings(card, attachment_zone, owner_id, "equipment_attachment_store", state.current_event_id) == null:
		return null
	return card


## 将一个装备槽实体和指定附属牌整体转移给另一名玩家；目标同槽旧装备会先正常弃置。
func transfer_equipment_with_attachments(from_id: int, to_id: int, slot: String, attachment_cards: Array[CardInstance], attachment_zone: String) -> bool:
	# 原持有者与接收者；双方必须仍存活于当前状态。
	var from_player: PlayerState = state.get_player(from_id)
	var to_player: PlayerState = state.get_player(to_id)
	if from_player == null or to_player == null or to_player.is_equipment_slot_abolished(slot) or not from_player.equipment.has(slot) or attachment_zone.is_empty():
		return false
	if to_player.equipment.has(slot):
		_discard_equipment_slot(to_id, slot, true)
	# 被转移装备实体；转移到装备区不执行离区附属牌弃置效果。
	var equipment_card: CardInstance = from_player.equipment[slot] as CardInstance
	_uninstall_card_runtime(equipment_card.uid)
	_ensure_card_movement()
	_move_card_with_timings(equipment_card, "equipment", to_id, "equipment_transfer", state.current_event_id, slot)
	_install_card_runtime(equipment_card, to_id)
	for attachment_card: CardInstance in attachment_cards.duplicate():
		_move_card_with_timings(attachment_card, attachment_zone, to_id, "equipment_attachment_transfer", state.current_event_id)
	return true


## 按稳定 UID 查找公共处理区实体牌；选择等待期间数组位置变化不会影响结果。
func _find_processing_card(card_uid: int) -> CardInstance:
	for processing_card: CardInstance in state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	return null


## 弃置装备槽并执行白银狮子、木牛流马等离开装备区效果。
func _discard_equipment_slot(player_id: int, slot: String, trigger_loss_effects: bool) -> void:
	# 失去装备的玩家状态；空槽安全返回。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return
	# 离开装备区的实体牌；先移除再执行丢失后效果。
	var card: CardInstance = player.equipment[slot] as CardInstance
	player.equipment.erase(slot)
	_on_equipment_lost(player, card, trigger_loss_effects)
	_move_to_discard(card)


## 处理装备离开后的附属状态与触发；不负责移动装备牌本身。
func _on_equipment_lost(player: PlayerState, card: CardInstance, trigger_loss_effects: bool) -> void:
	_uninstall_card_runtime(card.uid)
	# 离区卡牌定义；木牛附属区和白银狮子回复等专属规则由各自源码处理。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if definition != null:
		definition.on_leave_equipment(self, player, trigger_loss_effects)


## 为进入持续区域的实体牌创建独立源码实例；具体卡牌可在 install_runtime 中订阅规则事件或查询修正。
func _install_card_runtime(card: CardInstance, owner_player_id: int) -> void:
	if card == null:
		return
	_uninstall_card_runtime(card.uid)
	# 当前卡牌运行时实例；数据库静态定义不保存玩家或实体状态，因此必须从脚本重新创建。
	var runtime: CardDefinition = GameDatabase.create_card_runtime(card.definition_id)
	if runtime == null:
		return
	runtime.bind_runtime(self, owner_player_id, card.uid)
	card_runtime_instances[card.uid] = runtime
	runtime.install_runtime()


## 卸载指定实体牌的持续效果；换装、弃置、获得或死亡清区都通过稳定 UID 精确处理。
func _uninstall_card_runtime(card_uid: int) -> void:
	# 当前卡牌运行时实例；不存在表示该牌没有持续效果或已经完成卸载。
	var runtime: CardDefinition = card_runtime_instances.get(card_uid) as CardDefinition
	if runtime == null:
		return
	runtime.uninstall_runtime()
	card_runtime_instances.erase(card_uid)


## 卸载上一局全部持续卡牌实例；必须在替换事件总线或状态前释放订阅。
func _uninstall_all_card_runtimes() -> void:
	for runtime_variant: Variant in card_runtime_instances.values():
		# 当前卡牌运行时实例；无效实例跳过，避免场景退出期间重复访问。
		var runtime: CardDefinition = runtime_variant as CardDefinition
		if runtime != null:
			runtime.uninstall_runtime()
	card_runtime_instances.clear()


## 创建玩家并随机分配身份；武将、体力与技能相关状态统一在选将完成后初始化。
## automatic_match_seed为true时，离线斗地主会避免连续两局得到完全相同的本地座次与身份组合。
func _create_players(player_count: int, automatic_match_seed: bool = false) -> void:
	# 本局模式；决定身份表是否洗牌以及开局公开身份规则。
	var match_mode: String = identity_rules.normalize_mode(str(state.match_mode))
	# 身份配置副本；身份局整表洗牌；斗地主按座次固定；2v2 按座次固定后可整体互换蓝红。
	# 补充：斗地主现将身份数量池洗牌，确保每局由本局随机源重新决定哪名玩家成为地主。
	# 联机自选身份锁定标志；开启时大厅位置身份表原样按座次生效，不洗牌也不做2v2蓝红互换。
	var lan_custom_identity_enabled: bool = bool(state.match_options.get("lan_custom_identity_enabled", false))
	# 联机固定座位锁定标志；只用于记录本局座位是否随大厅位置固定，不改变身份表内容。
	var lan_fixed_seat_enabled: bool = bool(state.match_options.get("lan_fixed_seat_enabled", false))
	var identities: Array[String] = identity_rules.get_distribution(player_count, match_mode)
	# 自选身份下身份必须跟随大厅位置而不是跟随物理座次；座位随机开局时位置与座次不再一一对应，因此先按开局映射重排身份表。
	if lan_custom_identity_enabled:
		identities = _build_lan_slot_identity_distribution(match_mode, player_count, identities)
	if match_mode == IdentityRules.MODE_TEAM2V2:
		# 2v2：50% 概率整表互换蓝红，保持一号与四号同队、二号与三号同队；自选身份保持基准表使大厅蓝红选择生效。
		if not lan_custom_identity_enabled:
			identities = identity_rules.get_team2v2_distribution(_rng.randf() < 0.5)
	elif match_mode != IdentityRules.MODE_WHEEL_DUEL and match_mode != IdentityRules.MODE_CONQUEST:
		if not lan_custom_identity_enabled:
			_shuffle_array(identities)
	if automatic_match_seed and match_mode == IdentityRules.MODE_DOUDIZHU:
		_avoid_repeated_automatic_doudizhu_local_assignment(identities)
	# 局域网真人玩家 ID；房主大厅已按位置顺序绑定成员，离线模式保持只有 local_human_player_id 一名真人。
	# 联机过关斩将的真人由网关映射到偶数玩家座位，奇数敌方座位始终由内置 AI 补齐。
	var lan_human_player_ids: Array[int] = []
	if network_gateway != null and network_gateway.is_lan_host():
		lan_human_player_ids = network_gateway.get_lan_human_player_ids()
	for index: int in range(player_count):
		# 新建玩家状态；显示名保持稳定座次便于日志辨认。
		# 内置 AI 名称带有明确前缀，真实玩家保持“玩家X”；选将完成旋转座次后会按最终座次再次统一刷新。
		var is_human_player: bool = lan_human_player_ids.has(index) if not lan_human_player_ids.is_empty() else index == local_human_player_id
		# 当前玩家显示名；局域网真人沿用大厅昵称，离线真人与 AI 继续使用原有稳定座次名称。
		var default_player_name: String = network_gateway.get_lan_player_display_name(index) if not lan_human_player_ids.is_empty() and is_human_player else ("玩家%d" % (index + 1) if is_human_player else "[AI]玩家%d" % (index + 1))
		if match_mode == IdentityRules.MODE_CONQUEST:
			# 过关斩将按交替座位命名：偶数座位为“玩家K”（真人沿用大厅昵称），奇数座位固定为“[AI]敌人K”。
			default_player_name = _make_conquest_seat_display_name(index, is_human_player)
		# 当前新建玩家状态；稳定玩家 ID 使用原始创建索引，显示名使用本轮默认座次名称。
		var player: PlayerState = PlayerState.new(index, default_player_name)
		# 当前座次身份；身份局与斗地主均已洗牌，2v2、车轮战与过关斩将按各自固定规则赋值。
		player.identity = identities[index]
		player.identity_revealed = identity_rules.is_identity_public_at_start(player.identity, match_mode)
		player.character_id = ""
		player.character_revealed = false
		state.players.append(player)
		if not is_human_player:
			ai_coordinator.register_basic_ai(index)
	state.random_history.append({"kind":"identity_distribution", "mode":match_mode, "identities":identities.duplicate(), "local_human_player_id":local_human_player_id, "human_player_ids":lan_human_player_ids.duplicate() if not lan_human_player_ids.is_empty() else [local_human_player_id], "lan_custom_identity_enabled":lan_custom_identity_enabled, "lan_fixed_seat_enabled":lan_fixed_seat_enabled})


## 返回自选身份开局按规则座次排列的身份表；大厅位置身份写入真正占用该座位的玩家。
## 固定座位下座位与大厅位置一一对应，结果与模式座次身份表完全一致；随机座位下身份继续跟随大厅位置而不跟随座位。
func _build_lan_slot_identity_distribution(match_mode: String, player_count: int, fallback_identities: Array[String]) -> Array[String]:
	# 大厅位置身份表；2v2 使用“上蓝下红”的大厅专属布局，其余模式沿用固定座次身份表。
	var lobby_identities: Array[String] = identity_rules.get_lobby_slot_identities(match_mode, player_count)
	if lobby_identities.is_empty():
		return fallback_identities
	# 本次开局的座位到大厅位置映射；非房主开局或映射缺失时为空，此时保持调用方传入的座次身份表。
	var seat_lobby_slots: Array[int] = []
	if network_gateway != null and network_gateway.is_lan_host():
		seat_lobby_slots = network_gateway.get_lan_seat_lobby_slots()
	# 映射尺寸必须与本次对局的角色总数一致才可使用；否则说明它属于上一局或另一种模式，整表回退到座次身份表以免身份错配。
	if seat_lobby_slots.size() != player_count:
		return fallback_identities
	# 结果身份表；每个座次取“占用该座位成员的大厅位置”对应身份，未映射座位回退到自身座次身份。
	var result: Array[String] = fallback_identities.duplicate()
	for seat_index: int in range(result.size()):
		# 当前座次占用者的大厅位置；-1表示该座位由 AI 补位，沿用该座次原有的身份。
		var lobby_slot: int = seat_lobby_slots[seat_index]
		if lobby_slot >= 0 and lobby_slot < lobby_identities.size():
			result[seat_index] = lobby_identities[lobby_slot]
	return result


## 避免自动斗地主连续两局向本地玩家展示完全相同的座次与身份；初次抽取仍来自本局随机源，只在命中上一局组合时从其他合法座次中随机改选。
func _avoid_repeated_automatic_doudizhu_local_assignment(identities: Array[String]) -> void:
	if network_gateway != null and network_gateway.mode != NetworkGateway.Mode.OFFLINE:
		return
	if not randomize_local_human_seat or local_human_player_id < 0 or local_human_player_id >= identities.size() or identities.is_empty():
		return
	# 本次随机抽取对应的本地身份；与座次共同构成玩家在选将标题中实际观察到的开局分配。
	var current_local_identity: String = identities[local_human_player_id]
	if local_human_player_id == _last_automatic_doudizhu_local_seat_index and current_local_identity == _last_automatic_doudizhu_local_identity:
		# 身份与上一局不同的其他座次；优先从这里随机选择，使重复命中时座次和身份都产生可见变化。
		var different_identity_seat_indices: Array[int] = []
		# 任意其他座次；仅在异常身份表没有另一种身份时作为稳定兜底，仍保证座次不会连续重复。
		var other_seat_indices: Array[int] = []
		for seat_index: int in range(identities.size()):
			if seat_index == _last_automatic_doudizhu_local_seat_index:
				continue
			other_seat_indices.append(seat_index)
			if identities[seat_index] != _last_automatic_doudizhu_local_identity:
				different_identity_seat_indices.append(seat_index)
		# 最终候选座次数组；标准三人和五人身份表始终存在不同身份座次，兜底只保护未来自定义分布。
		var replacement_seat_indices: Array[int] = different_identity_seat_indices if not different_identity_seat_indices.is_empty() else other_seat_indices
		if not replacement_seat_indices.is_empty():
			local_human_player_id = replacement_seat_indices[_rng.randi_range(0, replacement_seat_indices.size() - 1)]
			current_local_identity = identities[local_human_player_id]
	_last_automatic_doudizhu_local_seat_index = local_human_player_id
	_last_automatic_doudizhu_local_identity = current_local_identity


## 把已确认武将应用到玩家状态；体力上限只在该入口初始化，避免界面与选将服务重复写数值。
func _apply_character(player: PlayerState, character_id: String, reveal_character: bool) -> void:
	if player == null:
		return
	# 新武将入场代次；即使稳定玩家ID不变，异步技能、伤害时机和选择也不能跨越本边界。
	player.character_generation += 1
	player.character_id = character_id
	player.character_revealed = reveal_character
	_refresh_pre_game_character_stats(player)


## 按玩家当前武将与最终身份刷新开局基础体力；该函数不修改武将ID、公开状态、候选或随机源。
func _refresh_pre_game_character_stats(player: PlayerState) -> void:
	if player == null or player.character_id.is_empty():
		return
	# 已选武将配置；基础体力上限取 max_hp，模式与身份可再叠加开局加值。
	var character: Dictionary = GameDatabase.get_character(player.character_id)
	# 模式开局体力上限加值；身份局领袖在不少于5人时+1，斗地主地主固定+1。
	var opening_max_hp_bonus: int = identity_rules.get_opening_max_hp_bonus(player.identity, state.players.size(), str(state.match_mode))
	player.max_hp = maxi(int(character.get("max_hp", 4)), 1) + opening_max_hp_bonus
	# 过关斩将敌方的体力与手牌上限从已获得关卡机缘重新汇总；其他角色不写模式专属字段。
	# 补充：玩家难度体力机缘不写模式专属字段，而在后续通用机缘历史入口单独计算。
	if conquest_mode != null and conquest_mode.is_enemy(player.player_id):
		player.max_hp += conquest_mode.get_max_hp_bonus()
		player.mode_hand_limit_bonus = conquest_mode.get_hand_limit_bonus()
	else:
		player.mode_hand_limit_bonus = 0
	# 过关斩将玩家由难度获得的体力上限机缘；敌方仍由关卡服务汇总，避免同一历史被重复计算。
	# 联机多人局中每名红方玩家都独立累加自己的机缘体力上限。
	if conquest_mode != null and conquest_mode.is_conquest_player(player.player_id):
		player.max_hp += get_acquired_opportunity_effect_total(player.player_id, "max_hp")
	player.hp = player.max_hp
	# 初始护盾值；选将应用角色时统一归零，后续只能通过护盾规则端口获得。
	player.shield = 0


## 从角色已获得机缘历史中累加指定效果数值；目录定义是伤害、摸牌与次数加成的唯一数值来源。
func get_acquired_opportunity_effect_total(player_id: int, effect_id: String) -> int:
	# 当前机缘持有者；无效来源或空效果名不产生任何修正，保证无来源伤害等路径安全。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or effect_id.is_empty():
		return 0
	# 缓存前后边界是否仍与已处理前缀一致；正式流程只追加，此校验额外兼容测试、回放工具直接清空或替换历史后再写入的情况。
	var opportunity_history_replaced: bool = player.opportunity_effect_cache_processed_count < 0 or player.opportunity_effect_cache_processed_count > player.acquired_opportunity_ids.size()
	if not opportunity_history_replaced and player.opportunity_effect_cache_processed_count > 0:
		opportunity_history_replaced = player.acquired_opportunity_ids.is_empty() \
			or player.acquired_opportunity_ids[0] != player.opportunity_effect_cache_first_processed_id \
			or player.acquired_opportunity_ids[player.opportunity_effect_cache_processed_count - 1] != player.opportunity_effect_cache_last_processed_id
	if opportunity_history_replaced:
		player.opportunity_effect_totals_cache.clear()
		player.opportunity_effect_cache_processed_count = 0
		player.opportunity_effect_cache_first_processed_id = ""
		player.opportunity_effect_cache_last_processed_id = ""
	while player.opportunity_effect_cache_processed_count < player.acquired_opportunity_ids.size():
		# 当前尚未汇总的机缘ID；未知历史项仍推进游标，避免每次规则查询重复验证同一损坏记录。
		var opportunity_id: String = player.acquired_opportunity_ids[player.opportunity_effect_cache_processed_count]
		# 当前机缘效果稳定ID；目录以不可变标量接口提供，避免在每次出牌合法性枚举中复制完整定义。
		var cached_effect_id: String = OpportunityCatalog.get_effect_id(opportunity_id)
		if not cached_effect_id.is_empty():
			player.opportunity_effect_totals_cache[cached_effect_id] = int(player.opportunity_effect_totals_cache.get(cached_effect_id, 0)) + OpportunityCatalog.get_effect_count(opportunity_id)
		player.opportunity_effect_cache_processed_count += 1
	if player.opportunity_effect_cache_processed_count > 0:
		# 已处理前缀边界；下次查询以两个常数时间哨兵识别常见的直接替换，正常追加路径无需重新扫描。
		player.opportunity_effect_cache_first_processed_id = player.acquired_opportunity_ids[0]
		player.opportunity_effect_cache_last_processed_id = player.acquired_opportunity_ids[player.opportunity_effect_cache_processed_count - 1]
	return int(player.opportunity_effect_totals_cache.get(effect_id, 0))


## 判断角色是否因已获得机缘永久跳过指定主要阶段；未登记映射、无历史或0层效果均返回false。
func has_acquired_opportunity_permanent_phase_skip(player_id: int, phase_name: String) -> bool:
	# 阶段对应的稳定效果ID；只允许目录声明的判定与弃牌阶段，其他主要阶段不会被本接口误跳过。
	var effect_id: String = str(OPPORTUNITY_PERMANENT_SKIP_EFFECT_BY_PHASE.get(phase_name, ""))
	return not effect_id.is_empty() and get_acquired_opportunity_effect_total(player_id, effect_id) > 0


## 用新的机缘历史替换角色已有历史，并同步重建该历史派生的技能、体力上限与额外手牌上限；一次性资源效果不会倒放或重复结算。
func replace_acquired_opportunity_history(player_id: int, replacement_opportunity_ids: Array[String], reason: String = "opportunity_history_replace") -> bool:
	# 历史所属角色；死亡角色不接收刷新，离场但存活角色允许机缘规则显式修改自身历史。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or replacement_opportunity_ids.is_empty():
		return false
	# 新历史合法性；未知卡ID会破坏后续缓存与详情展示，因此整次替换拒绝而不是部分写入。
	for replacement_opportunity_id: String in replacement_opportunity_ids:
		if not OpportunityCatalog.has_card(replacement_opportunity_id):
			return false
	# 原历史副本；先计算两类需要真实撤销的永久数值，之后再整体写入历史。
	var original_opportunity_ids: Array[String] = player.acquired_opportunity_ids.duplicate()
	# 旧体力上限机缘合计；此前每张机缘在结算时已经直接改变最大体力。
	var original_max_hp_bonus: int = _get_opportunity_effect_total_from_ids(original_opportunity_ids, "max_hp")
	# 新体力上限机缘合计；替换后只应用差额，不重放历史中的一次性体力变化。
	var replacement_max_hp_bonus: int = _get_opportunity_effect_total_from_ids(replacement_opportunity_ids, "max_hp")
	# 旧额外手牌上限合计；该值同样在机缘结算时写入PlayerState，不是纯查询修正。
	var original_hand_limit_bonus: int = _get_opportunity_effect_total_from_ids(original_opportunity_ids, "hand_limit")
	# 新额外手牌上限合计；通过差额撤销已失效机缘并保留不属于机缘的其他上限来源。
	var replacement_hand_limit_bonus: int = _get_opportunity_effect_total_from_ids(replacement_opportunity_ids, "hand_limit")
	# 旧机缘来源技能ID；只移除source为opportunity的记录，武将、模式、临时与过关斩将来源保持独立。
	var acquired_skill_ids: Array = player.acquired_skills.keys().duplicate()
	for acquired_skill_id_variant: Variant in acquired_skill_ids:
		# 当前局内技能记录；机缘刷新不应误卸载其他系统授予的同名技能。
		var acquired_skill_id: String = str(acquired_skill_id_variant)
		var acquired_skill_data: Dictionary = player.acquired_skills.get(acquired_skill_id, {}) as Dictionary
		if str(acquired_skill_data.get("source", "")) == "opportunity":
			remove_acquired_skill(player_id, acquired_skill_id)
	# 新机缘历史；必须在重新安装技能前写入，保证技能查询与右键详情立即读取同一权威来源。
	player.acquired_opportunity_ids = replacement_opportunity_ids.duplicate()
	# 公开快照缓存失效；整体替换可能保持相同长度和首尾ID，必须显式要求PlayerState在下一次广播生成新只读数组。
	player.invalidate_acquired_opportunity_snapshot_cache()
	# 增量缓存失效；刷新可能保留首尾ID却替换中间项，不能依赖普通追加路径的两个边界哨兵判断。
	player.opportunity_effect_totals_cache.clear()
	player.opportunity_effect_cache_processed_count = 0
	player.opportunity_effect_cache_first_processed_id = ""
	player.opportunity_effect_cache_last_processed_id = ""
	# 体力上限差额；降低上限仍经统一端口派发时机、压低当前体力并在必要时进入濒死流程。
	var max_hp_delta: int = replacement_max_hp_bonus - original_max_hp_bonus
	if max_hp_delta != 0:
		change_max_hp(player_id, max_hp_delta, player_id, reason, true)
	# 额外手牌上限差额；新端口只修改机缘原先写入的部分，不触碰模式专属上限字段。
	var hand_limit_delta: int = replacement_hand_limit_bonus - original_hand_limit_bonus
	if hand_limit_delta != 0:
		change_hand_limit_bonus(player_id, hand_limit_delta, reason, true)
	# 替换后仍存活时逐张恢复其授予的局内技能；同一技能重复出现会由统一授予端口自然去重。
	if player.alive:
		for replacement_opportunity_id: String in replacement_opportunity_ids:
			# 当前替换后的卡定义；仅三种“获得技能”效果会安装运行时实例，其他效果保持历史查询或已结算资源。
			var replacement_card: Dictionary = OpportunityCatalog.get_card(replacement_opportunity_id)
			var replacement_effect_id: String = str(replacement_card.get("effect", ""))
			if replacement_effect_id in ["grant_skill", "gain_group_and_skill", "gain_same_name_length_and_skill"]:
				grant_acquired_skill(player_id, str(replacement_card.get("skill_id", "")), int(replacement_card.get("per_turn_limit", 0)), int(replacement_card.get("total_limit", 0)), "opportunity", true, int(replacement_card.get("per_round_limit", 0)))
	_emit_state()
	return true


## 汇总指定机缘ID数组中某种数值效果的count；用于历史整体替换前后的差额计算，不修改缓存或角色状态。
func _get_opportunity_effect_total_from_ids(opportunity_ids: Array[String], effect_id: String) -> int:
	# 汇总结果；未知ID与不匹配效果按0处理，调用方已经在替换入口完成完整合法性校验。
	var total: int = 0
	for opportunity_id: String in opportunity_ids:
		if OpportunityCatalog.get_effect_id(opportunity_id) == effect_id:
			total += OpportunityCatalog.get_effect_count(opportunity_id)
	return total


## 返回指定玩家当前持有的技能实例；空结果表示玩家未选择武将、未配置该技能或对局尚未完成技能安装。
func get_skill_instance(player_id: int, skill_id: String) -> SkillDefinition:
	# 玩家技能实例表；键为稳定技能 ID，值为仅属于该玩家的运行时对象。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	return player_skills.get(skill_id) as SkillDefinition


## 为技能安装流程登记轮回技静态配置；非轮回技与无效玩家由服务拒绝且不创建状态。
func register_reincarnation_skill(player_id: int, skill_id: String, metadata: Dictionary) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.register_skill(player_id, skill_id, metadata)


## 返回指定轮回技的公开权威状态深拷贝；界面、AI与技能公式读取同一份轮回进度。
func get_reincarnation_skill_state(player_id: int, skill_id: String) -> Dictionary:
	return reincarnation_skill_service.get_skill_state(player_id, skill_id) if reincarnation_skill_service != null else {}


## 返回指定角色当前已登记的全部轮回技稳定ID副本；技能据此表达“令其所有轮回技进入下一个轮回（节）”。
## 该接口不筛选技能来源，固有、模式、局内获得与临时轮回技只要登记过就会一并返回。
func list_reincarnation_skill_ids(player_id: int) -> Array[String]:
	# 已登记轮回技ID；无轮回服务时返回空数组，调用方无需额外判空。
	var result: Array[String] = []
	if reincarnation_skill_service == null:
		return result
	result.assign(reincarnation_skill_service.list_skill_ids(player_id))
	return result


## 检查轮回技通用限次；具体技能条件仍由自身触发回调或can_activate负责。
func can_activate_reincarnation_skill(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.can_activate(player_id, skill_id)


## 开始一次轮回技效果；首次进入初始轮回节时由服务补发开始生命周期。
func begin_reincarnation_skill_activation(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.begin_activation(player_id, skill_id)


## 完成一次轮回技效果并推进到下一轮回节；最后一节和永劫状态自动进入下一轮回。
func complete_reincarnation_skill_activation(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.complete_activation(player_id, skill_id)


## 令指定轮回技进入下一个轮回节；永劫状态下保持当前节并增加轮回数。
func enter_next_reincarnation_section(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.enter_next_section(player_id, skill_id)


## 令指定轮回技直接进入下一轮回；普通状态回到①，永劫状态保持锁定轮回节。
func enter_next_reincarnation(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.enter_next_round(player_id, skill_id)


## 将轮回数重置为1并回到①；普通重置不解除永劫，完整技能复原会显式清除永劫。
func reset_reincarnation(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.reset_skill(player_id, skill_id)


## 清除指定技能的轮回权威登记；武将牌换形卸载旧轮回技时调用，保证技能重新安装后从①与轮回数1开始。
## 只清理进度登记，不触碰事件订阅、卡牌状态或其他技能，因此换形链不会继承旧形态的轮回节。
func clear_reincarnation_skill_state(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.clear_skill_state(player_id, skill_id)


## 令轮回技进入永劫并锁定当前轮回节；重复进入无事发生，每回合限制从成功进入后开始计数。
func enter_eternal_reincarnation_state(player_id: int, skill_id: String, per_turn_limit: int = 0) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.enter_eternal_state(player_id, skill_id, per_turn_limit)


## 解除轮回技的永劫状态；当前轮回数与轮回节保持不变，未处于永劫时无事发生。
func exit_eternal_reincarnation_state(player_id: int, skill_id: String) -> bool:
	return reincarnation_skill_service != null and reincarnation_skill_service.exit_eternal_state(player_id, skill_id)


## 轮回状态改变后的统一快照通知入口；状态服务无需知道离线、局域网与界面广播实现。
func notify_reincarnation_state_changed() -> void:
	_emit_state()


## 汇总指定玩家全部已安装技能的次数解除钩子；技能只读取卡牌定义，不修改使用历史。
func skill_ignores_play_count_limit(player_id: int, card_definition: Dictionary) -> bool:
	# 当前玩家技能实例表；临时技能与武将固有技能共用同一容器，因此会自然参与查询。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；任一技能明确解除限制即可通过，不要求其他技能重复确认。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect() and skill.ignores_play_count_limit(card_definition):
			return true
	return false


## 汇总指定玩家全部已安装技能的“不计入使用次数限制”钩子；该语义不解除使用前已经达到的上限。
func skill_card_use_does_not_count_toward_play_limit(player_id: int, card_definition: Dictionary) -> bool:
	# 当前玩家技能实例表；固有、临时与局内获得技能使用同一纯查询容器。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；查询不得移动牌、创建选择或直接修改次数历史。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect() and skill.does_not_count_toward_play_limit(card_definition):
			return true
	return false


## 汇总指定玩家全部已安装技能对某张牌 play_limit 的额外次数加成；返回非负整数，由卡牌规则服务叠加到配置上限。
func skill_play_count_limit_bonus(player_id: int, card_definition: Dictionary) -> int:
	# 加成总和；多个技能可同时对同一牌族生效并累加。
	var total_bonus: int = 0
	# 当前玩家技能实例表；模式技能与武将技能共用同一容器。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；无效对象跳过。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect():
			total_bonus += maxi(skill.get_play_count_limit_bonus(card_definition), 0)
	# 【杀】次数机缘按共同次数组作用于普通、火与雷【杀】，普通机缘模式与过关斩将使用同一历史查询。
	if str(card_definition.get("play_limit_group", card_definition.get("id", ""))) == "slash":
		total_bonus += get_acquired_opportunity_effect_total(player_id, "slash_play_limit_bonus")
	return total_bonus


## 汇总指定玩家全部已安装技能的卡牌距离解除钩子；任一技能生效即可忽略该牌的距离限制。
func skill_ignores_card_distance_limit(player_id: int, card_definition: Dictionary) -> bool:
	# 当前玩家技能实例表；临时技能与固有技能通过相同纯查询入口参与距离规则。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；距离钩子不得移动牌、消耗次数或创建选择。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect() and skill.ignores_card_distance_limit(card_definition):
			return true
	# 当前逻辑牌族；公开标记可以声明“每个全局回合首次使用该牌族时忽略距离”，使用历史仍由控制器统一判断。
	var card_group: String = str(card_definition.get("play_limit_group", card_definition.get("id", "")))
	if player_mark_service != null and player_mark_service.allows_first_group_use_to_ignore_distance(player_id, card_definition) and not has_used_card_group_this_turn(player_id, card_group):
		return true
	return false


## 汇总指定来源角色全部技能对某名目标的最终距离修正；技能按安装顺序串联，返回值最低为1。
func modify_skill_distance_to_target(player_id: int, target_id: int, current_distance: int) -> int:
	# 串联后的距离；每项技能读取上一项结果，允许通用加减与“固定为1”效果自然组合。
	var modified_distance: int = maxi(current_distance, 1)
	# 当前玩家技能实例表；固有、模式与临时技能共用纯查询容器。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；距离修正不得移动牌、记录发动或创建选择。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect():
			modified_distance = maxi(skill.modify_distance_to_target(target_id, modified_distance), 1)
	return modified_distance


## 设置一名角色的公开标记；globally_unique用于“全场同ID仅一名角色拥有”的转移型标记。
func set_player_mark(player_id: int, mark_id: String, mark_data: Dictionary, globally_unique: bool = false) -> bool:
	if player_mark_service == null or not player_mark_service.set_mark(player_id, mark_id, mark_data, globally_unique):
		return false
	_emit_state()
	return true


## 移除一名角色的公开标记；标记不存在时返回false且不发送冗余快照。
func remove_player_mark(player_id: int, mark_id: String) -> bool:
	if player_mark_service == null or not player_mark_service.remove_mark(player_id, mark_id):
		return false
	_emit_state()
	return true


## 返回一名角色指定公开标记的深拷贝；空字典表示当前没有该标记。
func get_player_mark(player_id: int, mark_id: String) -> Dictionary:
	return player_mark_service.get_mark(player_id, mark_id) if player_mark_service != null else {}


## 按增量修改一名角色的公开标记数量；mark_data提供首次创建时的图标、名称和说明，结果为修改后的权威数量。
func change_player_mark_count(player_id: int, mark_id: String, amount: int, mark_data: Dictionary = {}) -> int:
	if player_mark_service == null or mark_id.is_empty() or amount == 0:
		return int(get_player_mark(player_id, mark_id).get("count", 0))
	# 当前标记数据；已存在时保留原图标、说明与来源，只更新数量。
	var current_mark: Dictionary = get_player_mark(player_id, mark_id)
	# 修改后的标记数量；统一收敛到公开标记服务支持的0至999范围。
	var changed_count: int = clampi(int(current_mark.get("count", 0)) + amount, 0, PlayerMarkService.MAX_MARK_COUNT)
	if changed_count <= 0:
		remove_player_mark(player_id, mark_id)
		return 0
	# 待写入标记数据；首次创建读取调用方配置，后续修改以既有权威字段为准。
	var changed_mark: Dictionary = mark_data.duplicate(true) if current_mark.is_empty() else current_mark.duplicate(true)
	changed_mark["count"] = changed_count
	set_player_mark(player_id, mark_id, changed_mark)
	return changed_count


## 添加或解除一项“非锁定技失效”来源；多个来源叠加时，只有全部解除后非锁定技才恢复生效。
func set_non_locked_skills_disabled(player_id: int, disabled: bool, source_id: String = "runtime", source_player_id: int = -1, reason: String = "") -> bool:
	if state == null or source_id.is_empty():
		return false
	# 目标角色；死亡角色仍允许清理旧来源，但不能新增长期失效状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or (disabled and not player.alive):
		return false
	# 修改前状态；用于避免无实质变化时发送冗余快照。
	var previous_sources: Dictionary = player.non_locked_skill_disable_sources.duplicate(true)
	if disabled:
		player.non_locked_skill_disable_sources[source_id] = {"source_player_id":source_player_id, "reason":reason}
	else:
		player.non_locked_skill_disable_sources.erase(source_id)
	player.non_locked_skills_disabled = not player.non_locked_skill_disable_sources.is_empty()
	if previous_sources == player.non_locked_skill_disable_sources:
		return false
	_emit_state()
	return true


## 查找指定来源创建的公开标记当前属于哪名角色；未找到返回-1。
func find_player_mark_owner(mark_id: String, source_player_id: int = -1) -> int:
	return player_mark_service.find_mark_owner(mark_id, source_player_id) if player_mark_service != null else -1


## 判断来源角色是否可以弃置目标角色区域内的指定牌；目标本人弃置自己的牌始终允许。
func can_discard_player_card(source_player_id: int, target_player_id: int, card: CardInstance, zone: String, slot: String = "") -> bool:
	if card == null or source_player_id == target_player_id or source_player_id < 0:
		return card != null
	# 目标角色技能实例表；保护规则由牌的当前拥有者提供，来源技能不能替目标放宽限制。
	var target_skills: Dictionary = skill_instances_by_player.get(target_player_id, {}) as Dictionary
	for skill_variant: Variant in target_skills.values():
		# 当前保护技能；任一技能拒绝即表示该牌不可由其他角色弃置。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.can_use_effect() and not skill.can_other_player_discard_card(source_player_id, card, zone, slot):
			return false
	return true


## 汇总指定玩家全部已安装技能的目标附加限制；首个非空错误会阻止目标进入使用指令。
func validate_skill_card_target_selection(player_id: int, card_definition: Dictionary, target_id: int, all_target_ids: Array[int]) -> String:
	# 当前玩家技能实例表；技能顺序与武将技能栏及临时技能安装顺序一致，保证拒绝原因稳定。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；目标校验必须保持纯查询，不能在此消费技能次数或牌。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or not skill.can_use_effect():
			continue
		var validation_error: String = skill.validate_card_target_selection(card_definition, target_id, all_target_ids)
		if not validation_error.is_empty():
			return validation_error
	return ""


## 汇总目标角色全部已安装技能的来牌目标限制；用于黑色【杀】免疫等无需触发选择的规则。
func validate_incoming_skill_card_target_selection(target_id: int, actor_id: int, card_definition: Dictionary, card_color: String) -> String:
	# 目标角色技能实例表；临时授予的【琥珀】与固有技能使用相同查询路径。
	var target_skills: Dictionary = skill_instances_by_player.get(target_id, {}) as Dictionary
	for skill_variant: Variant in target_skills.values():
		# 当前目标技能；来牌校验只读取稳定定义、颜色和角色ID。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or not skill.can_use_effect():
			continue
		var validation_error: String = skill.validate_incoming_card_target_selection(actor_id, card_definition, card_color)
		if not validation_error.is_empty():
			return validation_error
	return ""


## 永久授予一项数据库技能并立即安装；可配置每个全局回合次数与总发动次数，相同技能不会重复创建。
## 当前接口额外支持每轮次数，0表示对应维度不限制；新增参数置于末尾以兼容既有调用方。
func grant_acquired_skill(player_id: int, skill_id: String, per_turn_limit: int = 0, total_limit: int = 0, source: String = "runtime", allow_out_of_game: bool = false, per_round_limit: int = 0) -> bool:
	# 技能获得者；死亡、离场或无效角色不能取得新技能。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game) or skill_id.is_empty():
		return false
	# 永久失去技能的角色不能再通过任何来源获得技能；该标记不可逆，必须早于任何装配动作拦截。
	if player.skills_permanently_removed:
		return false
	# 当前技能实例表；固有、模式、临时与已获得技能共用同一运行时容器。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	if player_skills.has(skill_id):
		add_log("%s已经拥有【%s】，本次获得未重复安装。" % [format_player_state_log_name(player), format_skill_log_name(skill_id)])
		return false
	# 新技能运行时实例；领袖技不能通过普通局内效果绕过身份限制获得。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill == null or skill.leader_skill:
		return false
	skill.bind(self, player_id)
	player_skills[skill_id] = skill
	skill_instances_by_player[player_id] = player_skills
	# 已获得技能限制记录；0表示不限制，对应普通“获得技能”卡牌。
	player.acquired_skills[skill_id] = {
		"source":source,
		"per_turn_limit":maxi(per_turn_limit, 0),
		"per_round_limit":maxi(per_round_limit, 0),
		"total_limit":maxi(total_limit, 0),
		"tracked_turn_number":state.turn_number,
		"tracked_round_number":state.round_number,
		"uses_this_turn":0,
		"uses_this_round":0,
		"total_uses":0,
	}
	skill.install()
	add_log("%s获得了技能【%s】。" % [format_player_state_log_name(player), format_skill_log_name(skill_id)])
	_emit_state()
	return true


## 判断一项已安装技能是否仍有局内获得来源配置的发动额度；非获得技能不受本接口限制。
func can_use_acquired_skill(player_id: int, skill_id: String) -> bool:
	# 技能持有者；无效角色不能发动任何技能。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive:
		return false
	if not player.acquired_skills.has(skill_id):
		return true
	# 当前限制记录；回合号不同视为本回合尚未使用，不必提前写回重置状态。
	var usage: Dictionary = player.acquired_skills.get(skill_id, {}) as Dictionary
	# 当前回合已用次数；跨回合时按0读取。
	var uses_this_turn: int = int(usage.get("uses_this_turn", 0)) if int(usage.get("tracked_turn_number", -1)) == state.turn_number else 0
	# 当前轮已用次数；跨轮时按0读取，额外回合保持同一轮的累计限制。
	var uses_this_round: int = int(usage.get("uses_this_round", 0)) if int(usage.get("tracked_round_number", -1)) == state.round_number else 0
	# 每回合限制；0表示无限制。
	var per_turn_limit: int = maxi(int(usage.get("per_turn_limit", 0)), 0)
	# 每轮限制；0表示无限制，独立于每回合与总次数统计。
	var per_round_limit: int = maxi(int(usage.get("per_round_limit", 0)), 0)
	# 总发动限制；0表示不会因累计次数失去技能。
	var total_limit: int = maxi(int(usage.get("total_limit", 0)), 0)
	return (per_turn_limit == 0 or uses_this_turn < per_turn_limit) and (per_round_limit == 0 or uses_this_round < per_round_limit) and (total_limit == 0 or int(usage.get("total_uses", 0)) < total_limit)


## 消耗一次已获得技能发动额度；普通固有技能返回true但不记录，达到总次数后立即失去该获得技能。
func consume_acquired_skill_use(player_id: int, skill_id: String) -> bool:
	# 技能持有者；无效状态或额度耗尽时拒绝重复记录。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not can_use_acquired_skill(player_id, skill_id):
		return false
	if not player.acquired_skills.has(skill_id):
		return true
	# 可写限制记录副本；跨回合先清零单回合计数再累加本次成功发动。
	var usage: Dictionary = (player.acquired_skills.get(skill_id, {}) as Dictionary).duplicate(true)
	if int(usage.get("tracked_turn_number", -1)) != state.turn_number:
		usage["tracked_turn_number"] = state.turn_number
		usage["uses_this_turn"] = 0
	# 新轮重置轮内已用次数；额外回合不改变round_number，因此会继续消耗同一轮额度。
	if int(usage.get("tracked_round_number", -1)) != state.round_number:
		usage["tracked_round_number"] = state.round_number
		usage["uses_this_round"] = 0
	usage["uses_this_turn"] = int(usage.get("uses_this_turn", 0)) + 1
	usage["uses_this_round"] = int(usage.get("uses_this_round", 0)) + 1
	usage["total_uses"] = int(usage.get("total_uses", 0)) + 1
	player.acquired_skills[skill_id] = usage
	# 总次数耗尽标记；先保存本次发动记录，再卸载技能，保证第五次【行军】完整生效后才失去。
	var total_limit: int = maxi(int(usage.get("total_limit", 0)), 0)
	if total_limit > 0 and int(usage.get("total_uses", 0)) >= total_limit:
		remove_acquired_skill(player_id, skill_id)
	return true


## 移除一项确由局内获得来源安装的技能；固有、模式与临时技能不会被本接口误卸载。
func remove_acquired_skill(player_id: int, skill_id: String) -> bool:
	# 技能持有者；不存在获得记录时不改变运行时实例。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.acquired_skills.has(skill_id):
		return false
	player.acquired_skills.erase(skill_id)
	# 当前技能是否仍由交换后的武将牌、模式或临时来源提供；存在其他来源时只清除获得记录，不卸载共享实例。
	var native_skill_ids: Array = GameDatabase.get_character(player.character_id).get("skills", []) as Array
	var mode_skill_ids: Array[String] = identity_rules.get_mode_skill_ids(player.identity, str(state.match_mode))
	if native_skill_ids.has(skill_id) or mode_skill_ids.has(skill_id) or player.temporary_skills.has(skill_id):
		_emit_state()
		return true
	# 当前技能实例；没有其他来源时卸载并移除。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	# 待卸载技能实例；卸载会释放全部时机订阅与修正器。
	var skill: SkillDefinition = player_skills.get(skill_id) as SkillDefinition
	if skill != null:
		skill.uninstall()
	player_skills.erase(skill_id)
	skill_instances_by_player[player_id] = player_skills
	add_log("%s失去了技能【%s】。" % [format_player_state_log_name(player), format_skill_log_name(skill_id)])
	_emit_state()
	return true


## 动态授予一项数据库技能并立即安装；相同技能不会重复创建，失效信息记录在玩家公开运行时状态中。
func grant_temporary_skill(player_id: int, skill_id: String, expires_at_round: int) -> bool:
	# 技能获得者；死亡、离场或无效角色不能取得临时技能。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or skill_id.is_empty():
		return false
	# 当前技能实例表；已经拥有同名固有或临时技能时只延长临时记录，不重复订阅事件。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	if not player_skills.has(skill_id):
		# 新技能运行时实例；数据库工厂保证每名角色拥有独立状态。
		var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
		if skill == null or skill.leader_skill:
			return false
		skill.bind(self, player_id)
		player_skills[skill_id] = skill
		skill_instances_by_player[player_id] = player_skills
		skill.install()
	player.temporary_skills[skill_id] = {"expires_at_round":maxi(expires_at_round, state.round_number + 1)}
	return true


## 移除一项确由临时系统授予的技能；武将固有技能即使存在同名临时记录也始终保留。
func remove_temporary_skill(player_id: int, skill_id: String) -> bool:
	# 技能获得者；不存在临时记录时不改变任何技能实例。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.temporary_skills.has(skill_id):
		return false
	player.temporary_skills.erase(skill_id)
	# 武将固有技能ID；同名固有技能不能因临时期限结束而卸载。
	var native_skill_ids: Array = GameDatabase.get_character(player.character_id).get("skills", []) as Array
	if native_skill_ids.has(skill_id):
		return true
	# 当前技能实例；卸载会同步清理时机订阅与纯查询修正器。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	var skill: SkillDefinition = player_skills.get(skill_id) as SkillDefinition
	if skill != null:
		skill.uninstall()
	player_skills.erase(skill_id)
	skill_instances_by_player[player_id] = player_skills
	return true


## 在新轮的roundStart触发前移除到期临时技能，确保“直到本轮结束”不延续到下一轮任何触发窗口。
func _expire_temporary_skills_for_round(round_number: int) -> void:
	for player: PlayerState in state.players:
		# 待移除技能ID副本；遍历期间会修改temporary_skills，不能直接遍历原字典键视图。
		var expired_skill_ids: Array[String] = []
		for skill_id_variant: Variant in player.temporary_skills.keys():
			# 当前临时技能失效配置；旧格式或无效数据默认在当前轮移除，避免永久残留。
			var expiry_data: Dictionary = player.temporary_skills.get(skill_id_variant, {}) as Dictionary
			if int(expiry_data.get("expires_at_round", round_number)) <= round_number:
				expired_skill_ids.append(str(skill_id_variant))
		for skill_id: String in expired_skill_ids:
			remove_temporary_skill(player.player_id, skill_id)


## 查询处理区中的当前使用牌是否为黑色【杀】；供目标触发技能复用，不暴露实体对象写权限。
func is_processing_black_slash(card_uid: int) -> bool:
	# 当前处理区实体；虚拟牌同样拥有本次代理花色，可按材料继承结果判断颜色。
	var card: CardInstance = _find_processing_card(card_uid)
	if card == null:
		return false
	# 当前逻辑牌定义；普通、火与雷【杀】统一以effect_id=slash识别。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	return str(definition.get("effect_id", "")) == "slash" and card.get_color() == "black"


## 查询主动技能当前是否可发动；技能文件负责阶段、次数、目标和资源条件，控制器只提供统一入口。
func can_activate_skill(player_id: int, skill_id: String, context: Dictionary = {}) -> bool:
	if skill_id.is_empty():
		return false
	if network_gateway != null and network_gateway.is_lan_client():
		if player_id != local_human_player_id:
			return false
		# 远端持有者公开状态；死亡或离场后即使旧请求仍含技能白名单也不能继续点击发动。
		var remote_owner: Dictionary = {}
		for player_variant: Variant in _remote_snapshot.get("players", []) as Array:
			var remote_player: Dictionary = player_variant as Dictionary
			if int(remote_player.get("player_id", -1)) == player_id:
				remote_owner = remote_player
				break
		if remote_owner.is_empty() or not bool(remote_owner.get("alive", false)) or bool(remote_owner.get("out_of_game", false)):
			return false
		# 当前远端请求；房主已经完成技能入口、次数、资源和阶段校验，客户端只据其私有白名单控制按钮亮起。
		var remote_choice: Dictionary = _remote_snapshot.get("current_choice_request", {}) as Dictionary
		if int(remote_choice.get("actor_id", -1)) != player_id:
			return false
		# 活动上下文；优先读取技能 backup 后上下文，缺失时回退基础上下文。
		var active_context: Dictionary = remote_choice.get("active_context", remote_choice.get("base_context", {})) as Dictionary
		# 当前请求允许直接发动的主动技能 ID；仅用于客户端按钮提示，房主仍执行完整校验。
		var active_skill_ids: Array = active_context.get("active_skill_ids", []) as Array
		if active_skill_ids.has(skill_id):
			return true
		# 响应转换技能；请求上下文会明确列出已逐材料校验通过的稳定技能 ID。
		var response_conversion_skill_ids: Array = context.get("response_conversion_skill_ids", active_context.get("response_conversion_skill_ids", [])) as Array
		return response_conversion_skill_ids.has(skill_id)
	# 本地权威技能持有者；死亡或离场角色不能通过旧按钮、网络动作或未完整自检的技能脚本发动主动技能。
	var owner: PlayerState = state.get_player(player_id) if state != null else null
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	# 当前技能运行时实例；未安装的技能不能通过伪造动作直接发动。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null or not skill.can_use_effect(bool(context.get("locked_skill_segment", false))):
		return false
	if not skill.has_available_intrinsic_use():
		return false
	if skill.reincarnation and not skill.can_activate_reincarnation():
		return false
	if not can_use_acquired_skill(player_id, skill_id):
		return false
	# 当前响应候选声明的转化技能；候选已逐张通过can_convert_response_card权威校验，因此允许它在本次chooseToRespond中作为材料筛选入口出现。
	# 此分支不直接消费牌，提交阶段仍要求材料UID、response_skill_id和当前响应模式全部再次匹配。
	var response_conversion_skill_ids: Array = context.get("response_conversion_skill_ids", []) as Array
	if str(context.get("active_entry", "")) == "chooseToRespond" and response_conversion_skill_ids.has(skill_id):
		return true
	# 当前允许的主动入口；技能只需命中其中一个入口，复合 chooseToUse 与 phaseUse 请求不会要求重复声明。
	var active_entries: Array[String] = _resolve_active_entries(player_id, context)
	if not active_entries.is_empty():
		var supports_entry: bool = false
		for active_entry: String in active_entries:
			if skill.supports_active_entry(active_entry):
				supports_entry = true
				break
		if not supports_entry:
			return false
	return skill.can_activate(context)


## 返回指定玩家在当前主动入口可以发动的技能 ID；结果只包含已安装、入口匹配且 can_activate 通过的实例。
func get_active_skill_ids(player_id: int, active_entry: String, context: Dictionary = {}) -> Array[String]:
	# 可发动技能结果；按武将技能安装顺序遍历，界面和 AI 得到稳定按钮顺序。
	var result: Array[String] = []
	if not RuleTimingCatalog.has_active_entry(active_entry):
		return result
	# 当前技能持有者；死亡或离场后不再向界面、AI或网络请求公开主动技能入口。
	var owner: PlayerState = state.get_player(player_id) if state != null else null
	if owner == null or not owner.alive or owner.out_of_game:
		return result
	# 当前玩家技能表；未选将或技能尚未安装时为空字典。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；主动入口与自身规则条件必须同时满足。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or not skill.can_use_effect() or not skill.has_available_intrinsic_use() or not skill.supports_active_entry(active_entry) or not can_use_acquired_skill(player_id, skill.get_id()):
			continue
		if skill.reincarnation and not skill.can_activate_reincarnation():
			continue
		# 技能查询上下文；补充主动入口但不覆盖调用方其他可序列化参数。
		var activation_context: Dictionary = context.duplicate(true)
		activation_context["active_entry"] = active_entry
		if skill.can_activate(activation_context):
			result.append(skill.get_id())
	return result


## 返回指定角色当前全部已安装技能稳定ID；结果只含字符串副本，技能可据此组合通用状态而不读取运行时实例。
func get_installed_skill_ids(player_id: int) -> Array[String]:
	# 已安装技能表；固有、模式、临时与局内获得技能均由同一容器维护。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	# 稳定ID结果；沿用安装字典顺序，调用方不得据此依赖运行时对象。
	var result: Array[String] = []
	for skill_id_variant: Variant in player_skills.keys():
		result.append(str(skill_id_variant))
	return result


## 返回主动技能的只读交互预览；界面与 AI 可查询，但所有提交仍由技能 can_activate 与 activate 权威复核。
func get_skill_activation_preview(player_id: int, skill_id: String, context: Dictionary = {}) -> Dictionary:
	# 当前技能实例；未安装技能没有预览内容。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null or not skill.can_use_effect(bool(context.get("locked_skill_segment", false))):
		return {}
	return skill.get_activation_preview(context).duplicate(true)


## 通过统一动作入口发动技能；技能成功后记录稳定技能 ID，失败原因直接返回给动作提交者。
func activate_skill(player_id: int, skill_id: String, context: Dictionary = {}) -> bool:
	if state == null or state.game_over:
		return _reject("当前没有可发动技能的进行中对局。")
	# 当前技能运行时实例；必须由玩家所选武将直接配置并在开局时自动安装。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null:
		return _reject("当前武将未配置该技能。")
	if not can_activate_skill(player_id, skill_id, context):
		return _reject("该技能当前不满足发动条件。")
	# 技能时机共享数据；全部字段均可序列化，触发器可读取但不得写入节点或运行时对象。
	var timing_data: Dictionary = {"skill_id":skill_id, "context":context.duplicate(true)}
	_emit_rule_timing("logSkillBegin", player_id, player_id, -1, timing_data)
	_emit_rule_timing("logSkill", player_id, player_id, -1, timing_data)
	# 技能执行开始时机；被取消或中立化时不调用技能效果入口。
	var begin_event: RuleEvent = _emit_rule_timing("useSkillBegin", player_id, player_id, -1, timing_data)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		return _reject("该技能的发动已被规则取消。")
	# 技能主要使用时机；允许高优先级规则在实际消耗或效果前阻止本次主动技能。
	var use_event: RuleEvent = _emit_rule_timing("useSkill", player_id, player_id, -1, timing_data)
	if use_event != null and (use_event.cancelled or use_event.neutralized):
		return _reject("该技能的执行已被规则取消。")
	# 技能执行错误；空字符串表示技能已通过公开规则端口成功提交效果或选择请求。
	var activation_error: String = skill.activate(context)
	if not activation_error.is_empty():
		return _reject(activation_error)
	# 无材料响应技能由技能入口先支付费用，再以同一请求ID提交标准选择结果并恢复父牌流程。
	if str(context.get("active_entry", "")) == "chooseToRespond":
		var cardless_definition_id: String = skill.get_cardless_response_definition_id(_string_array(context.get("response_patterns", []) as Array))
		if not cardless_definition_id.is_empty() and not _submit_cardless_skill_response_choice(player_id, skill_id):
			return _reject("无材料响应技能未能完成当前响应请求。")
	state.action_sequence += 1
	_emit_rule_timing("useSkillAfter", player_id, player_id, -1, timing_data)
	_emit_rule_timing("skillAfter", player_id, player_id, -1, timing_data)
	_dispatch_rule_event(RuleEvent.new("skill_used", player_id, -1, {"skill_id":skill_id, "context":context.duplicate(true)}))
	_emit_state()
	return true


## 将已由主动技能支付费用的无材料响应提交到当前选择请求；所有请求归属与牌型仍由_submit_card_choice复核。
func _submit_cardless_skill_response_choice(player_id: int, skill_id: String) -> bool:
	if _pending_card_choice.is_empty() or int(_pending_card_choice.get("chooser_id", -1)) != player_id or str(_pending_card_choice.get("choice_type", "")) != "respond":
		return false
	# 标准选择动作；空实体数组与专用技能ID共同表达无材料响应，cardless_cost_paid防止重复支付体力等费用。
	var action: PlayerAction = PlayerAction.new("choose_cards", player_id)
	action.payload = {
		"request_id":int(_pending_card_choice.get("request_id", -1)),
		"selected_card_uids":[],
		"selected_target_ids":[],
		"cardless_response_skill_id":skill_id,
		"cardless_cost_paid":true,
		"confirmed":true,
	}
	return _submit_card_choice(action)


## 请求播放一次技能发动语音。
## 本端口是内容层显式调用与核心统一出口的共同入口：技能源码可在效果代码中调用它自定义播放时机。
## 同一次发动内的重复请求会被去重表拦截，因此显式调用不会与默认触发重复发声。
func request_skill_voice(player_id: int, skill_id: String) -> void:
	if state == null or state.game_over or skill_id.is_empty():
		return
	# 去重键；技能以当前规则事件为令牌，同一次发动链路只允许请求一次语音。
	var dedup_key: String = "%s|%d|%s|%d|%s" % [VOICE_KIND_SKILL, player_id, skill_id, state.current_event_id, ""]
	if _is_duplicate_voice_request(dedup_key):
		return
	# 发动者武将ID；用于优先命中角色专属配音，同一技能被不同角色拥有时音色随之变化。
	var character_id: String = _resolve_player_character_id(player_id)
	# 只读表现负载；只包含已公开数据，可安全序列化并随联机表现事件广播。
	var presentation_data: Dictionary = {
		"kind": VOICE_KIND_SKILL,
		"player_id": player_id,
		"skill_id": skill_id,
		"character_id": character_id,
		"sequence": _voice_presentation_sequence,
	}
	_voice_presentation_sequence += 1
	voice_presentation_requested.emit(presentation_data)


## 请求播放一次卡牌使用或打出语音。
## 本端口由核心统一出口调用（使用声明、响应消耗、技能转化响应），卡牌源码也可显式调用以自定义时机。
## 同一张牌的“使用”与“打出”共用同一份音效，仅动作模式字段不同。
func request_card_voice(player_id: int, card_definition_id: String, play_mode: String) -> void:
	if state == null or state.game_over or card_definition_id.is_empty():
		return
	# 卡牌定义；同时提供两套牌名，音频层据当前卡名显示模式选择并回退另一体系。
	var card_definition: Dictionary = GameDatabase.get_card(card_definition_id)
	if card_definition.is_empty():
		return
	# 去重键；卡牌以当前规则事件与动作模式为令牌，同一张牌的使用与打出各自只请求一次。
	var dedup_key: String = "%s|%d|%s|%d|%s" % [VOICE_KIND_CARD, player_id, card_definition_id, state.current_event_id, play_mode]
	if _is_duplicate_voice_request(dedup_key):
		return
	# 两套牌名；音频层按当前卡名模式优先取用，缺失时回退另一体系。
	var card_names: Dictionary = {
		"custom": str(card_definition.get("custom_name", "")),
		"original": str(card_definition.get("original_name", "")),
	}
	# 使用者性别；音频层据此优先选用 male/female 子目录中的专属配音，未选将或未知性别时跳过该层。
	var gender: String = get_player_gender(player_id)
	# 只读表现负载；不包含手牌归属、身份或随机种子等任何隐藏信息。
	var presentation_data: Dictionary = {
		"kind": VOICE_KIND_CARD,
		"player_id": player_id,
		"card_definition_id": card_definition_id,
		"card_names": card_names,
		"gender": gender,
		"play_mode": play_mode,
		"sequence": _voice_presentation_sequence,
	}
	_voice_presentation_sequence += 1
	voice_presentation_requested.emit(presentation_data)


## 请求播放一次全局效果音。
## 本端口与技能、卡牌语音共用同一条表现链路：单机本地播放，局域网由房主广播给全部客户端。
## 效果音不区分角色与性别，负载因此只含效果标识本身，随联机表现事件广播不会泄露任何隐藏信息。
func request_effect_voice(player_id: int, effect_id: String) -> void:
	if state == null or state.game_over or effect_id.is_empty():
		return
	# 去重键；以当前规则事件为令牌，避免伤害续接恢复或嵌套结算对同一次事件重复发声。
	var dedup_key: String = "%s|%d|%s|%d|%s" % [VOICE_KIND_EFFECT, player_id, effect_id, state.current_event_id, ""]
	if _is_duplicate_voice_request(dedup_key):
		return
	# 只读表现负载；效果音是全局素材，因此不需要武将、牌名或性别字段。
	var presentation_data: Dictionary = {
		"kind": VOICE_KIND_EFFECT,
		"player_id": player_id,
		"effect_id": effect_id,
		"sequence": _voice_presentation_sequence,
	}
	_voice_presentation_sequence += 1
	voice_presentation_requested.emit(presentation_data)


## 请求播放一次武将阵亡语音。
## 本端口是死亡内容服务的统一出口：死亡事实成立时按阵亡者的武将ID请求一次发音。
## 负载只含玩家与武将ID，二者在死亡结算中均已公开，因此可随联机表现事件安全广播。
## character_id 留空时按该玩家当前武将回退，使“只传玩家”的调用同样可用。
func request_die_voice(player_id: int, character_id: String = "") -> void:
	if state == null or state.game_over:
		return
	# 阵亡武将ID；优先采用调用方给出的死亡时武将，避免等待期间换将后取到新武将的音色。
	var resolved_character_id: String = character_id.strip_edges()
	if resolved_character_id.is_empty():
		resolved_character_id = _resolve_player_character_id(player_id)
	if resolved_character_id.is_empty():
		return
	# 去重键；同一事件内同一名武将只允许请求一次阵亡语音。
	# 武将ID参与去重，因此车轮战等模式中同一玩家先后阵亡的不同武将各自都能发声。
	var dedup_key: String = "%s|%d|%s|%d|%s" % [VOICE_KIND_DIE, player_id, resolved_character_id, state.current_event_id, ""]
	if _is_duplicate_voice_request(dedup_key):
		return
	# 只读表现负载；不包含手牌归属、身份或随机种子等任何隐藏信息。
	var presentation_data: Dictionary = {
		"kind": VOICE_KIND_DIE,
		"player_id": player_id,
		"character_id": resolved_character_id,
		"sequence": _voice_presentation_sequence,
	}
	_voice_presentation_sequence += 1
	voice_presentation_requested.emit(presentation_data)


## 推导一次伤害对应的效果音标识；与无名杀的伤害音效命名规则逐项对齐。
## 命名规则与无名杀保持一致：护盾实际吸收伤害时使用 hujia_damage 系列，否则使用 damage 系列；
## 火与雷属性追加属性后缀，2点及以上伤害追加“2”后缀。
## 项目只定义普通、火焰与雷电三种伤害属性，其余属性取值一律回退到基础音效，不会命中不存在的素材。
func _resolve_damage_effect_id(nature: String, amount: int, shield_absorbed: int) -> String:
	# 效果音基名；护盾参与吸收即视为护甲承受伤害，与无名杀的护甲语义完全对应。
	var effect_id: String = EFFECT_HUJIA_DAMAGE_BASE if shield_absorbed > 0 else EFFECT_DAMAGE_BASE
	# 属性后缀；只有火与雷两种属性拥有独立音色，其它属性共用基础音效。
	if nature == "fire" or nature == "thunder":
		effect_id += "_%s" % nature
	# 点数后缀；2点及以上伤害使用加重的第二套音效，1点伤害使用基础音效。
	if amount > 1:
		effect_id += "2"
	return effect_id


## 推导装备槽位对应的效果音标识；未登记槽位返回空字符串，由请求端口直接跳过。
func _resolve_equipment_effect_id(slot: String) -> String:
	return str(EQUIPMENT_EFFECT_IDS.get(slot, ""))


## 技能发动的默认音频触发；内容层已显式播放或声明手动接管时跳过，保证不重复发声。
func _request_auto_skill_voice(player_id: int, skill_id: String, skill_metadata: Dictionary) -> void:
	# 内容层声明手动接管的技能不自动发声，由技能文件自行选择播放时机与条件。
	if str(skill_metadata.get("voice_trigger", "")) == VOICE_TRIGGER_MANUAL:
		return
	# 技能实例；用于判断内容层是否已在本次发动过程中显式请求过语音。
	var skill_instance: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill_instance != null and skill_instance.consume_explicit_voice_request(EXPLICIT_VOICE_SUPPRESS_WINDOW_SECONDS):
		return
	request_skill_voice(player_id, skill_id)


## 返回指定玩家的武将ID；玩家不存在或尚未选将时返回空字符串，音频层据此回退到通用音效。
func _resolve_player_character_id(player_id: int) -> String:
	if state == null:
		return ""
	# 目标玩家状态；已离场或从未创建时无法取得武将信息。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return ""
	return str(player.character_id)


## 记录并判断一次音频请求是否为重复；重复请求返回 true，由调用方直接丢弃。
func _is_duplicate_voice_request(dedup_key: String) -> bool:
	if _voice_request_tokens.has(dedup_key):
		return true
	# 容量保护；达到上限后清空重建，避免长局中条目无限增长。
	if _voice_request_tokens.size() >= VOICE_REQUEST_TOKEN_CAPACITY:
		_voice_request_tokens.clear()
	_voice_request_tokens[dedup_key] = true
	return false


## 写入一条实际成立的技能发动记录，并通知对局日志与桌面表现；内容技能只能通过本公开端口调用，不能直接改写历史数组。
func record_skill_activation(player_id: int, skill_id: String, context: Dictionary = {}) -> void:
	if state == null or state.game_over:
		return
	# 技能元数据；离场技允许存活但离场的持有者记录真实成立的触发，普通技能仍保持在场限制。
	var skill_metadata: Dictionary = GameDatabase.get_skill(skill_id)
	# 发动者状态；未知或死亡角色不能留下新记录，离场角色仅在技能明确声明离场技时例外。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or (player.out_of_game and not bool(skill_metadata.get("out_of_game_skill", false))):
		return
	# 音频表现：技能实际发动成立时默认请求一次技能语音，覆盖主动技、触发技与领袖技的全部发动路径。
	_request_auto_skill_voice(player_id, skill_id, skill_metadata)
	# 技能名称；缺失时回退稳定 ID，保证日志与动画仍能定位来源。
	# 当前日志说明：稳定ID只保存在结构化历史中，玩家可见名称缺失时统一显示中文“未知技能”。
	var skill_name: String = format_skill_log_name(skill_id)
	# 永久历史条目；保存技能、触发事件、回合与内容上下文，供回放和未来统计读取。
	player.skill_history.append({"skill_id":skill_id, "skill_name":skill_name, "event_id":state.current_event_id, "turn_number":state.turn_number, "context":context.duplicate(true)})
	# 技能目标日志片段；有目标时追加“，目标为xx”。
	var skill_target_text: String = format_target_log_names(context.get("target_ids", []) as Array)
	if skill_target_text.is_empty():
		skill_target_text = format_target_log_names([context.get("target_id", -1)])
	if skill_target_text.is_empty():
		for fallback_key: String in ["recipient_id", "slash_user_id", "restricted_target_ids"]:
			if fallback_key == "restricted_target_ids":
				skill_target_text = format_target_log_names(context.get(fallback_key, []) as Array)
			else:
				skill_target_text = format_target_log_names([context.get(fallback_key, -1)])
			if not skill_target_text.is_empty():
				break
	if skill_target_text.is_empty():
		add_log("%s发动了【%s】。" % [format_player_state_log_name(player), skill_name])
	else:
		add_log("%s发动了【%s】，目标为%s。" % [format_player_state_log_name(player), skill_name, skill_target_text])
	# 技能表现上下文副本；目标线等客户端表现只读取已经确认的稳定目标字段，不能持有或改写规则历史原字典。
	var presentation_context: Dictionary = context.duplicate(true)
	skill_activated.emit(player_id, skill_name, presentation_context)
	# 实际发动时机；区别于主动按钮提交时的兼容skillAfter，触发技与选择恢复后的发动同样从本入口统一发布。
	var skill_instance: SkillDefinition = get_skill_instance(player_id, skill_id)
	# 实际发动的纯数据时机负载；包含原上下文、重复标记与当次唯一令牌。
	var actual_timing_data: Dictionary = {
		"skill_id":skill_id,
		"context":context.duplicate(true),
		"actual_activation":true,
		"repeated_activation":bool(context.get("repeated_activation", false)),
		"activation_repeat_token":skill_instance.get_last_activation_repeat_token() if skill_instance != null else -1,
	}
	_emit_rule_timing("skillAfter", player_id, player_id, -1, actual_timing_data)


## 令指定技能按最近一次实际发动入口额外发动；角色代次与技能ID复核避免换将后的旧请求命中新实例。
func repeat_skill_activation(player_id: int, skill_id: String, activation_context: Dictionary, activation_repeat_token: int, character_generation: int = -1) -> bool:
	# 当前技能实例；必须仍属于原武将代次且处于可生效状态，重复发动不重新消耗主动按钮次数校验。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null or not skill.matches_character_generation(character_generation) or not skill.can_use_effect():
		return false
	return skill.repeat_activation(activation_context.duplicate(true), activation_repeat_token)


## 记录一件防具已经实际生效的表现事件；该入口只负责武将牌名称提示，不写入技能历史、不增加日志或修改装备状态。
func record_equipment_activation(player_id: int, equipment_definition_id: String, context: Dictionary = {}) -> void:
	if state == null or state.game_over or equipment_definition_id.is_empty():
		return
	# 防具持有者；死亡、离场或不存在的角色不产生过期界面提示。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return
	# 防具静态定义；仅防具槽类型允许进入本表现入口，避免其他装备误用同一提示。
	var equipment_metadata: Dictionary = GameDatabase.get_card(equipment_definition_id)
	if str(equipment_metadata.get("subtype", "")) != "armor":
		return
	# 当前名称模式下的防具名；缺失配置时回退稳定 ID，保证界面不会因内容异常空白。
	var equipment_name: String = GameSettings.resolve_card_name(equipment_metadata) if not equipment_metadata.is_empty() else equipment_definition_id
	# 只读表现上下文；调用者可补充判定或伤害来源信息，但不可借此改写权威装备或历史。
	var presentation_context: Dictionary = context.duplicate(true)
	equipment_activated.emit(player_id, equipment_name, presentation_context)


## 推导一次主动技能提交所属入口；显式 active_entries 优先，其次 active_entry，最后依据当前阶段回退 phaseUse。
func _resolve_active_entries(player_id: int, context: Dictionary) -> Array[String]:
	# 主动入口结果；去重后供技能元数据匹配，数组为空表示调用方未处于标准主动窗口。
	var result: Array[String] = []
	for entry_variant: Variant in context.get("active_entries", []) as Array:
		# 当前入口名称；只接受目录中的四种稳定值。
		var entry_name: String = str(entry_variant)
		if RuleTimingCatalog.has_active_entry(entry_name) and not result.has(entry_name):
			result.append(entry_name)
	# 单入口兼容字段；技能按钮和响应扩展可只传一个字符串。
	var single_entry: String = str(context.get("active_entry", ""))
	if RuleTimingCatalog.has_active_entry(single_entry) and not result.has(single_entry):
		result.append(single_entry)
	if result.is_empty() and state != null and state.current_player_id == player_id and state.current_phase == "play":
		result.append("phaseUse")
	return result


## 为全部已选武将创建并安装独立技能实例；武将脚本中的直接引用顺序决定安装与技能栏顺序。
func _install_all_character_skills() -> void:
	_uninstall_all_character_skills()
	for player: PlayerState in state.players:
		# 永久失去技能的角色不装配任何技能；标记来自【留白】等不可逆效果。
		if player.skills_permanently_removed:
			continue
		# 当前武将定义；skills 数组由 CharacterDefinition 从直接引用的技能脚本自动生成。
		var character: Dictionary = GameDatabase.get_character(player.character_id)
		# 当前玩家技能实例表；不同玩家即使持有同一技能也不会共享次数、标记或临时状态。
		var player_skills: Dictionary = {}
		# 待安装技能 ID；武将固有技能后追加模式/身份技能，避免覆盖同名键。
		var skill_ids_to_install: Array[String] = []
		for skill_id_variant: Variant in character.get("skills", []):
			skill_ids_to_install.append(str(skill_id_variant))
		for mode_skill_id: String in identity_rules.get_mode_skill_ids(player.identity, str(state.match_mode)):
			if not skill_ids_to_install.has(mode_skill_id):
				skill_ids_to_install.append(mode_skill_id)
		for skill_id: String in skill_ids_to_install:
			# 当前技能运行时实例；配置校验已保证正常开局时不会为空。
			var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
			if skill == null:
				push_error("无法为玩家%d创建技能：%s" % [player.player_id, skill_id])
				continue
			# 领袖技归属校验；非领袖不会安装实例、订阅时机或进入主动技能列表，等价于本局不拥有该技能。
			if skill.leader_skill and player.identity != "leader":
				continue
			skill.bind(self, player.player_id)
			player_skills[skill_id] = skill
			skill.install()
		skill_instances_by_player[player.player_id] = player_skills


## 卸载上一局或动态移除的全部技能；事件总线订阅必须在清空实例引用前释放。
func _uninstall_all_character_skills() -> void:
	for player_skills_variant: Variant in skill_instances_by_player.values():
		# 当前玩家技能实例表；遍历副本保证卸载回调可安全调整外部事件注册。
		var player_skills: Dictionary = player_skills_variant as Dictionary
		for skill_variant: Variant in player_skills.values():
			# 当前待卸载技能；无效实例直接跳过，避免场景释放期间重复访问。
			var skill: SkillDefinition = skill_variant as SkillDefinition
			if skill != null:
				skill.uninstall()
	skill_instances_by_player.clear()


## 仅重新安装指定玩家当前武将的技能；车轮战换将使用该入口，避免卸载并重建对手未变化的技能实例。
func _reinstall_character_skills_for_player(player: PlayerState) -> void:
	if player == null:
		return
	# 旧武将技能实例；逐个卸载后清空该玩家映射，防止死亡武将的订阅继续响应规则时机。
	var previous_skills: Dictionary = skill_instances_by_player.get(player.player_id, {}) as Dictionary
	for skill_variant: Variant in previous_skills.values():
		var previous_skill: SkillDefinition = skill_variant as SkillDefinition
		if previous_skill != null:
			previous_skill.uninstall()
	skill_instances_by_player[player.player_id] = {}
	# 永久失去技能的角色只卸载旧实例而不再装配；否则换将与车轮战重装都会让已失去的技能复活。
	if player.skills_permanently_removed:
		return
	var player_skills: Dictionary = {}
	var character: Dictionary = GameDatabase.get_character(player.character_id)
	var skill_ids_to_install: Array[String] = []
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		skill_ids_to_install.append(str(skill_id_variant))
	for mode_skill_id: String in identity_rules.get_mode_skill_ids(player.identity, str(state.match_mode)):
		if not skill_ids_to_install.has(mode_skill_id):
			skill_ids_to_install.append(mode_skill_id)
	for skill_id: String in skill_ids_to_install:
		var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
		if skill == null or skill.leader_skill and player.identity != "leader":
			continue
		skill.bind(self, player.player_id)
		player_skills[skill_id] = skill
		skill.install()
	skill_instances_by_player[player.player_id] = player_skills


## 本局永久移除指定角色的全部技能；写入不可逆标记，使后续所有装配路径都不再为其安装技能。
## 端口职责：释放时机订阅 → 清空获得与临时技能记录 → 清空轮回公开状态 → 置标记 → 广播状态。
## 标记进入公开快照与存档，因此读档、换将、车轮战重装与局内获得都不会让已失去的技能复活。
func remove_all_skills_permanently(player_id: int, reason: String = "") -> bool:
	# 目标角色；不存在或无效对局中没有可移除的技能。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return false
	# 重复调用视为已达成目标；不再重复卸载与广播，避免同一回合内多次触发同一清算。
	if player.skills_permanently_removed:
		return true
	# 当前技能实例表；逐个卸载以释放事件总线订阅，再从容器中移除该玩家的整条记录。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前待卸载技能；无效实例直接跳过，避免场景释放期间重复访问。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null:
			skill.uninstall()
	skill_instances_by_player.erase(player_id)
	# 获得与临时技能记录；失去全部技能后这些记录不再有消费者，清空以免界面与AI读到幽灵技能。
	player.acquired_skills.clear()
	player.temporary_skills.clear()
	# 轮回技公开状态；失去技能后不再保留轮回数、轮回节与永劫标记。
	player.reincarnation_skills.clear()
	player.skills_permanently_removed = true
	add_log("%s永久失去了全部技能%s。" % [format_player_state_log_name(player), "（%s）" % reason if not reason.is_empty() else ""])
	_emit_state()
	return true


## 为指定角色记录一个牌名；已存在时不重复记录并返回 false，供技能区分“首次记录”与“重复记录”。
## 记录按稳定牌ID保存并进入公开快照，因此展示名由名称模式在读取时解析，记录本身不受名称模式切换影响。
func record_card_name(player_id: int, definition_id: String) -> bool:
	# 目标角色；不存在时无处记录。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or definition_id.is_empty():
		return false
	# 已记录牌名保持幂等；重复重铸同一牌名不应产生第二条记录，也不重复广播状态。
	if player.recorded_card_names.has(definition_id):
		return false
	player.recorded_card_names.append(definition_id)
	# 记录日志使用当前名称模式下的显示名；牌名解析失败时回退为稳定ID，保证日志始终可读。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	var display_name: String = GameSettings.resolve_card_name(definition) if not definition.is_empty() else definition_id
	add_log("%s记录了牌名%s。" % [format_player_state_log_name(player), display_name])
	_emit_state()
	return true


## 移除指定角色已记录的一个牌名；不存在时返回 false，供【灵感】结算完毕与【看破】发动时调用。
## 记录是公开信息，因此移除后必须广播状态，使界面与对手AI的候选集合立即同步收缩。
func remove_recorded_card_name(player_id: int, definition_id: String) -> bool:
	# 目标角色；不存在时无记录可移除。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or definition_id.is_empty():
		return false
	# 未记录该牌名；保持静默失败，调用方据此判断条件是否成立。
	if not player.recorded_card_names.has(definition_id):
		return false
	player.recorded_card_names.erase(definition_id)
	# 移除日志与记录日志对称，便于回放与排查时还原记录的完整生命周期。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	var display_name: String = GameSettings.resolve_card_name(definition) if not definition.is_empty() else definition_id
	add_log("%s移除了记录的牌名%s。" % [format_player_state_log_name(player), display_name])
	_emit_state()
	return true


## 返回指定角色当前记录的牌名列表副本；技能、界面与AI只需读取，禁止直接改写权威数组。
func get_recorded_card_names(player_id: int) -> Array[String]:
	# 目标角色；不存在时返回空数组，避免调用方额外判空。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		var empty_result: Array[String] = []
		return empty_result
	return player.recorded_card_names.duplicate()


## 重置指定角色除排除项以外的全部技能；复原限定技、出牌阶段限次、每回合限次、觉醒技与轮回进度。
## 复用复原武将牌技能入口重建固有技能实例：新建实例天然归零各技能脚本自行保存的私有额度。
## 排除项必须保留原实例：重建会把它自身的限定技标记一并清零，导致限定技可无限发动。
## 局内获得技能的额度记录在 acquired_skills 中，不随实例重建复原，因此在此显式归零已用次数。
## 返回值：被重置的固有技能数量，供测试断言与AI估值复用；排除项不计入。
func reset_all_other_skills(player_id: int, exclude_skill_id: String = "") -> int:
	# 目标角色；不存在或已永久失去技能的角色没有任何可重置内容。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or player.skills_permanently_removed:
		return 0
	var reset_count: int = _rebuild_character_skills_and_zero_usage(player, exclude_skill_id, "reset_all_other_skills")
	add_log("%s重置了除【%s】以外的全部技能。" % [format_player_state_log_name(player), format_skill_log_name(exclude_skill_id)])
	_emit_state()
	return reset_count


## 重置指定角色的全部技能，不保留任何排除项；【揭质】以自身为目标重复【逐虚】效果时通过该端口发动。
## 与 reset_all_other_skills 的唯一差异是不存在排除项：调用方技能自身的限定技、阶段额度与局内获得次数同样归零。
## reason 只写入技能变化时机数据与日志，不参与规则判定；为空时回退为端口名，保证日志始终可读。
## 返回值：被重置的固有技能数量，供测试断言与AI估值复用。
func reset_all_skills(player_id: int, reason: String = "") -> int:
	# 目标角色；不存在或已永久失去技能的角色没有任何可重置内容。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or player.skills_permanently_removed:
		return 0
	# 重置原因；缺省回退为端口名，使日志与技能变化时机始终带有可读来源。
	var reset_reason: String = reason if not reason.is_empty() else "reset_all_skills"
	var reset_count: int = _rebuild_character_skills_and_zero_usage(player, "", reset_reason)
	add_log("%s重置了全部技能（%s）。" % [format_player_state_log_name(player), reset_reason])
	_emit_state()
	return reset_count


## 两个重置端口共用的底层实现：重建固有技能实例，并把局内获得技能的已用次数与统计基准归零。
## exclude_skill_id 非空时回填该技能的原实例，保留其限定技与阶段额度等全部私有状态；为空表示不保留任何技能。
## reason 透传给复原武将牌技能入口，用于写入 changeSkillsAfter 时机数据。
## 返回值：被重置的固有技能数量；排除项不计入，因为它没有被重置。
func _rebuild_character_skills_and_zero_usage(player: PlayerState, exclude_skill_id: String, reason: String) -> int:
	# 排除项原实例；先取引用，复原结束后回填，保留其限定技与阶段额度等全部私有状态。
	var current_skills: Dictionary = skill_instances_by_player.get(player.player_id, {}) as Dictionary
	var excluded_skill: SkillDefinition = current_skills.get(exclude_skill_id) as SkillDefinition
	# 复原武将牌上的全部固有技能；该入口会卸载旧实例并新建未使用实例，同时重置对应轮回进度。
	if not restore_character_card_skills(player.player_id, reason):
		return 0
	# 复原后的技能表；排除项的新实例必须卸载后回填旧实例，否则两者会重复订阅同一时机。
	var rebuilt_skills: Dictionary = skill_instances_by_player.get(player.player_id, {}) as Dictionary
	# 被重置的固有技能数量；排除项不计入，因为它没有被重置。
	var reset_count: int = rebuilt_skills.size()
	if excluded_skill != null:
		var rebuilt_excluded: SkillDefinition = rebuilt_skills.get(exclude_skill_id) as SkillDefinition
		rebuilt_skills[exclude_skill_id] = excluded_skill
		if rebuilt_excluded != null and rebuilt_excluded != excluded_skill:
			# 复原过程已经统一卸载了排除项的旧实例；此处卸载重建出的新实例并重新安装旧实例，
			# 否则回填进来的旧实例不会持有任何时机订阅，其第二段延迟效果将永远不会执行。
			rebuilt_excluded.uninstall()
			excluded_skill.install()
			reset_count -= 1
	# 局内获得技能；额度定义与已用次数同存于 acquired_skills，复原实例不会清空这些计数，必须逐项归零。
	for acquired_skill_id_variant: Variant in player.acquired_skills.keys():
		# 当前获得技能稳定ID；仅改写已用次数与统计基准，保留来源与三类上限定义。
		var acquired_skill_id: String = str(acquired_skill_id_variant)
		var usage: Dictionary = (player.acquired_skills.get(acquired_skill_id, {}) as Dictionary).duplicate(true)
		usage["uses_this_turn"] = 0
		usage["uses_this_round"] = 0
		usage["total_uses"] = 0
		usage["tracked_turn_number"] = state.turn_number
		usage["tracked_round_number"] = state.round_number
		player.acquired_skills[acquired_skill_id] = usage
	return reset_count


## 完成其他玩家同时选将、统一亮将、发4张起始手牌并由领袖开始首回合。
func _finish_character_selection() -> void:
	# 完成时统一写入全部选将结果。身份局旧路径会跳过 leader_player_id（依赖领袖阶段已亮将），
	# 斗地主没有领袖优先亮将，且自选提交发生在 PHASE_OTHERS，跳过/不批量应用会导致地主或全员 character_id 为空并显示“未选武将”。
	if character_selection.custom_assignment_enabled:
		# 自选：先把最终座次与身份落到玩家状态，再写武将，保证地主体力+1 等模式加值按最终身份计算。
		_apply_custom_assignment_preview()
	for player: PlayerState in state.players:
		# 服务中已确认的稳定武将 ID；空值表示该玩家未能完成选将（不应在 PHASE_COMPLETE 出现）。
		var selected_character_id: String = character_selection.get_selection(player.player_id)
		if selected_character_id.is_empty():
			push_error("选将完成时玩家%d缺少已确认武将（mode=%s identity=%s）。" % [player.player_id, str(state.match_mode), player.identity])
			continue
		_apply_character(player, selected_character_id, true)
	add_log("所有玩家完成选将并同时亮出武将。")
	if _begin_ai_character_adjustment():
		return
	_continue_game_start_after_character_adjustment()


## 将未确认的自选座次身份即时投射到开局前牌桌；每名玩家最终确认时也复用本函数投射座次身份，只应用本次确认的武将。
func _apply_custom_assignment_preview() -> void:
	if state == null or character_selection == null:
		return
	# 当前可分配座次；已确认或主动预览的玩家先占用，剩余玩家随后按首次随机分配稳定补位。
	var available_seats: Array[int] = []
	for seat_number: int in range(1, state.players.size() + 1):
		available_seats.append(seat_number)
	# 当前可分配身份池；身份数量只从首次随机分配读取，连续预览不会把上一帧预览误作新的规则名额。
	var available_identities: Array[String] = []
	for player: PlayerState in state.players:
		available_identities.append(character_selection.get_initial_identity(player.player_id))
	# 玩家 ID 到预览结果的映射；每项只保存稳定座次和身份，不保存节点或角色对象。
	var assignments_by_player: Dictionary = {}
	for player: PlayerState in state.players:
		# 当前是否已有最终确认；确认结果和主动预览都优先于首次随机分配。
		var has_final_assignment: bool = character_selection.get_selected_seat_number(player.player_id) >= 1 and not character_selection.get_selected_identity(player.player_id).is_empty()
		var has_preview_assignment: bool = character_selection.has_custom_assignment_preview(player.player_id)
		if not has_final_assignment and not has_preview_assignment:
			continue
		# 当前固定座次与身份；服务已在提交或预览入口完成一号位与领袖联动及互斥校验。
		var fixed_seat_number: int = character_selection.get_preview_seat_number(player.player_id)
		var fixed_identity: String = character_selection.get_preview_identity(player.player_id)
		if not available_seats.has(fixed_seat_number) or not available_identities.has(fixed_identity):
			continue
		assignments_by_player[player.player_id] = {"seat_number":fixed_seat_number, "identity":fixed_identity}
		available_seats.erase(fixed_seat_number)
		available_identities.erase(fixed_identity)
	# 未固定首任一号位身份；保留首次公开角色优先级，若其已经被其他预览占用则按当前玩家数组选择首名可用角色。
	var first_seat_identity: String = character_selection.get_first_seat_identity()
	if available_seats.has(1) and available_identities.has(first_seat_identity):
		var fallback_leader_player_id: int = -1
		for player: PlayerState in state.players:
			if assignments_by_player.has(player.player_id):
				continue
			if character_selection.get_initial_identity(player.player_id) == first_seat_identity:
				fallback_leader_player_id = player.player_id
				break
		if fallback_leader_player_id < 0:
			for player: PlayerState in state.players:
				if not assignments_by_player.has(player.player_id):
					fallback_leader_player_id = player.player_id
					break
		if fallback_leader_player_id >= 0:
			assignments_by_player[fallback_leader_player_id] = {"seat_number":1, "identity":first_seat_identity}
			available_seats.erase(1)
			available_identities.erase(first_seat_identity)
	# 其余未确认玩家；尽量保留首次随机座次与身份，冲突时使用剩余池中的首个稳定值。
	# 斗地主额外约束：剩余地主名额只落到固定地主座（1/3），农民名额不占地主座。
	var landlord_seats: Array[int] = character_selection.get_landlord_seat_numbers()
	for player: PlayerState in state.players:
		if assignments_by_player.has(player.player_id) or available_seats.is_empty() or available_identities.is_empty():
			continue
		var preferred_seat_number: int = character_selection.get_initial_seat_number(player.player_id)
		var preferred_identity: String = character_selection.get_initial_identity(player.player_id)
		var remaining_seat_number: int = preferred_seat_number if available_seats.has(preferred_seat_number) else available_seats[0]
		var remaining_identity: String = preferred_identity if available_identities.has(preferred_identity) else str(available_identities[0])
		if character_selection.is_doudizhu_mode() and not landlord_seats.is_empty():
			# 若剩余池仍有地主位且有地主名额，优先把偏好为地主的玩家（或任意剩余）填到地主位。
			var free_landlord_seats: Array[int] = []
			for seat_option: int in landlord_seats:
				if available_seats.has(seat_option):
					free_landlord_seats.append(seat_option)
			var free_peasant_seats: Array[int] = []
			for seat_option: int in available_seats:
				if not landlord_seats.has(seat_option):
					free_peasant_seats.append(seat_option)
			if preferred_identity == "landlord" and available_identities.has("landlord") and not free_landlord_seats.is_empty():
				remaining_seat_number = preferred_seat_number if free_landlord_seats.has(preferred_seat_number) else free_landlord_seats[0]
				remaining_identity = "landlord"
			elif preferred_identity == "peasant" and available_identities.has("peasant") and not free_peasant_seats.is_empty():
				remaining_seat_number = preferred_seat_number if free_peasant_seats.has(preferred_seat_number) else free_peasant_seats[0]
				remaining_identity = "peasant"
			elif available_identities.has("landlord") and not free_landlord_seats.is_empty():
				remaining_seat_number = free_landlord_seats[0]
				remaining_identity = "landlord"
			elif available_identities.has("peasant") and not free_peasant_seats.is_empty():
				remaining_seat_number = free_peasant_seats[0]
				remaining_identity = "peasant"
			else:
				# 兜底：座次决定身份，保证预览桌面不出现“2号位地主”等非法组合。
				remaining_seat_number = available_seats[0]
				remaining_identity = "landlord" if landlord_seats.has(remaining_seat_number) else "peasant"
				if not available_identities.has(remaining_identity):
					remaining_identity = str(available_identities[0])
		elif character_selection.is_team2v2_mode():
			# 2v2：剩余补位必须遵守开局座次→蓝/红绑定表，禁止出现“3号蓝位却显示红方”等错位预览。
			var bound_for_preferred: String = character_selection.get_team2v2_identity_for_seat(preferred_seat_number)
			if available_seats.has(preferred_seat_number) and available_identities.has(bound_for_preferred if not bound_for_preferred.is_empty() else preferred_identity):
				remaining_seat_number = preferred_seat_number
				remaining_identity = bound_for_preferred if not bound_for_preferred.is_empty() else preferred_identity
			else:
				var filled_preview: bool = false
				var preview_bound_identity: String = ""
				# 尽量保留偏好颜色的绑定座。
				var preferred_team_seats: Array[int] = character_selection.get_team2v2_seats_for_identity(preferred_identity)
				for team_seat: int in preferred_team_seats:
					if available_seats.has(team_seat) and available_identities.has(preferred_identity):
						remaining_seat_number = team_seat
						remaining_identity = preferred_identity
						filled_preview = true
						break
				if not filled_preview:
					for seat_option: int in available_seats:
						preview_bound_identity = character_selection.get_team2v2_identity_for_seat(seat_option)
						if not preview_bound_identity.is_empty() and available_identities.has(preview_bound_identity):
							remaining_seat_number = seat_option
							remaining_identity = preview_bound_identity
							filled_preview = true
							break
				if not filled_preview:
					remaining_seat_number = available_seats[0]
					remaining_identity = character_selection.get_team2v2_identity_for_seat(remaining_seat_number)
					if remaining_identity.is_empty() or not available_identities.has(remaining_identity):
						remaining_identity = str(available_identities[0])
		assignments_by_player[player.player_id] = {"seat_number":remaining_seat_number, "identity":remaining_identity}
		available_seats.erase(remaining_seat_number)
		available_identities.erase(remaining_identity)
	# 按预览座次构建显示顺序；所有位置都在服务与补位规则下得到一个稳定玩家对象。
	var reordered_players: Array[PlayerState] = []
	reordered_players.resize(state.players.size())
	for player: PlayerState in state.players:
		# 当前玩家预览数据；缺失时保留首次随机分配，防御异常快照导致数组出现空位。
		var assignment: Dictionary = assignments_by_player.get(player.player_id, {"seat_number":character_selection.get_initial_seat_number(player.player_id), "identity":character_selection.get_initial_identity(player.player_id)}) as Dictionary
		player.identity = str(assignment.get("identity", character_selection.get_initial_identity(player.player_id)))
		player.identity_revealed = identity_rules.is_identity_public_at_start(player.identity, str(state.match_mode))
		var applied_seat_number: int = int(assignment.get("seat_number", -1))
		if applied_seat_number >= 1 and applied_seat_number <= reordered_players.size():
			reordered_players[applied_seat_number - 1] = player
	for seat_index: int in range(reordered_players.size()):
		if reordered_players[seat_index] == null:
			return
	state.players = reordered_players
	# 首任领袖在仍占一号位时保留首次公开武将；其余未确认角色必须恢复未亮将，不能在背景抢先展示所有AI武将。
	# 首任领袖公开武将已是最终选择，即使预览后暂不位于一号位也不能清空或重新随机。
	# 斗地主无领袖优先选将：自选预览只重排座次/身份，任何角色均不得提前亮将（含一号位 AI 地主）。
	var uses_leader_preview: bool = character_selection.uses_leader_priority_selection()
	var preview_leader_before_clear: PlayerState = state.players[0] if not state.players.is_empty() else null
	for player: PlayerState in state.players:
		# 保留条件；仅身份局下同一名首任领袖仍是当前预览领袖且尚未提交最终新武将时，才沿用其已经公开的牌面。
		var preserves_initial_leader_character: bool = (
			uses_leader_preview
			and player == preview_leader_before_clear
			and player.player_id == character_selection.leader_player_id
			and player.identity == character_selection.get_first_seat_identity()
			and not player.character_id.is_empty()
		)
		if character_selection.get_selection(player.player_id).is_empty() and not preserves_initial_leader_character:
			_clear_pre_game_character_preview(player)
	# 当前预览领袖；仅身份局在领袖由 AI 控制且尚未最终确认时公开候选，斗地主全程保持未亮将。
	if uses_leader_preview:
		var preview_leader: PlayerState = state.players[0] if not state.players.is_empty() else null
		if preview_leader != null and ai_coordinator.is_ai_controlled(preview_leader.player_id) and character_selection.get_selection(preview_leader.player_id).is_empty() and preview_leader.character_id.is_empty():
			var preview_character_id: String = _get_preview_ai_character_id(preview_leader)
			if not preview_character_id.is_empty():
				_apply_character(preview_leader, preview_character_id, true)
	_refresh_player_display_names_for_current_seats()


## 清空开局预览产生的临时武将；最终确认前不保留武将、体力或公开状态，避免背景亮将泄露候选流程。
func _clear_pre_game_character_preview(player: PlayerState) -> void:
	if player == null:
		return
	player.character_id = ""
	player.character_revealed = false
	player.max_hp = 4
	player.hp = 4
	player.shield = 0


## 从当前AI私有候选中挑选一张领袖预览武将；只有当前预览领袖调用，其他AI保持未亮将。
func _get_preview_ai_character_id(player: PlayerState) -> String:
	if player == null or character_selection == null:
		return ""
	# 当前AI私有随机候选；优先保持正式选将阶段已经生成的随机结果，不额外消耗换将卡或重洗候选。
	var candidates: Array[String] = character_selection.get_candidates(player.player_id)
	for candidate_id: String in candidates:
		if candidate_id != player.character_id:
			return candidate_id
	if not candidates.is_empty():
		return candidates[0]
	# 全局回退候选；候选为空时仍保证AI领袖拥有一张可公开的武将。
	for character_id_variant: Variant in GameDatabase.get_selectable_character_ids():
		var character_id: String = str(character_id_variant)
		if character_id != player.character_id:
			return character_id
	return ""


## 在需要时进入房主调整 AI 武将阶段；返回true表示开局流程已经暂停等待房主操作。
func _begin_ai_character_adjustment() -> bool:
	if not _customize_ai_characters_enabled or ai_character_adjustment == null:
		return false
	# 当前全部 AI 玩家；按当前玩家数组顺序保存，真人和掉线托管尚未进入对局，不属于内置 AI 调整对象。
	var ai_player_ids: Array[int] = []
	for player: PlayerState in state.players:
		if ai_coordinator.is_ai_controlled(player.player_id):
			ai_player_ids.append(player.player_id)
	# 全部武将 ID；调整服务使用副本重新随机候选。
	var available_character_ids: Array[String] = GameDatabase.get_selectable_character_ids()
	# 房主权威玩家；离线为本地真人，局域网房主同样使用已经绑定的本地玩家 ID。
	var authority_player_id: int = local_human_player_id
	ai_character_adjustment.begin(ai_player_ids, available_character_ids, _character_candidate_count, _custom_character_assignment_enabled, authority_player_id, _rng)
	if not ai_character_adjustment.active:
		return false
	# 普通身份局原本在起始手牌后旋转领袖座次；调整阶段需要先显示最终一号位，因此提前执行同一幂等排序。
	_reorder_players_from_leader()
	state.current_phase = "ai_character_adjustment"
	state.pre_game_setup = {
		"kind":"ai_character_adjustment",
		"host_player_id":authority_player_id,
		"target_player_ids":ai_character_adjustment.get_ai_player_ids(),
	}
	add_log("初次选将完成，等待房主调整 AI 武将。")
	_emit_state()
	return true


## 完成武将调整后继续安装技能、派发开局时机并发放起始手牌。
func _continue_game_start_after_character_adjustment() -> void:
	state.pre_game_setup.clear()
	# 选将完成后的过渡阶段；先离开character_selection并同步全部亮将结果，避免开局时机创建的技能询问被选将遮罩拦截。
	state.current_phase = "game_start"
	_emit_state()
	_install_all_character_skills()
	_record_runtime_event("gameStart", "mode", {"player_count":state.players.size()})
	_emit_rule_timing("gameStart", -1, -1, -1, {"player_count":state.players.size()})
	for entered_player: PlayerState in state.players:
		_emit_rule_timing("enterGame", entered_player.player_id, entered_player.player_id, entered_player.player_id, {"character_id":entered_player.character_id})
	var game_draw_data: Dictionary = {"cards_per_player":4, "player_count":state.players.size()}
	# 最终起始手牌数；默认4，允许 gameDrawBefore 与 gameDrawBegin 在不直接访问牌堆的情况下修改。
	var starting_hand_count: int = 4
	# 是否执行起始手牌分发；取消 gameDrawBefore 或 gameDrawBegin 只跳过发牌，不能令选将完成后的对局永久停住。
	var should_deal_starting_cards: bool = true
	var game_draw_before_event: RuleEvent = _emit_rule_timing("gameDrawBefore", -1, -1, -1, game_draw_data)
	if game_draw_before_event != null and (game_draw_before_event.cancelled or game_draw_before_event.neutralized):
		should_deal_starting_cards = false
	if should_deal_starting_cards:
		var game_draw_begin_event: RuleEvent = _emit_rule_timing("gameDrawBegin", -1, -1, -1, game_draw_before_event.data if game_draw_before_event != null else game_draw_data)
		if game_draw_begin_event != null and (game_draw_begin_event.cancelled or game_draw_begin_event.neutralized):
			should_deal_starting_cards = false
		else:
			starting_hand_count = maxi(int(game_draw_begin_event.data.get("cards_per_player", starting_hand_count)) if game_draw_begin_event != null else starting_hand_count, 0)
	if should_deal_starting_cards:
		# 2v2：四号位初始手牌 +1；其他模式与各座次统一使用 starting_hand_count。
		var is_team2v2_start: bool = identity_rules.normalize_mode(str(state.match_mode)) == IdentityRules.MODE_TEAM2V2
		for seat_index: int in range(state.players.size()):
			# 当前座次玩家；seat_index 0 为一号位，3 为四号位。
			var seated_player: PlayerState = state.players[seat_index]
			# 当前角色实际起始手牌数；难度灰色机缘与2v2四号位加值在统一基础数量上累加。
			var seat_hand_count: int = starting_hand_count + (1 if is_team2v2_start and seat_index == 3 else 0) + get_acquired_opportunity_effect_total(seated_player.player_id, "initial_hand_bonus")
			draw(seated_player.player_id, seat_hand_count, false)
		var game_draw_result_data: Dictionary = {"cards_per_player":starting_hand_count, "player_count":state.players.size(), "team2v2_seat4_bonus":1 if is_team2v2_start else 0}
		_record_runtime_event("gameDraw", "draw", game_draw_result_data)
		_emit_rule_timing("gameDrawAfter", -1, -1, -1, game_draw_result_data)
	_starting_hand_count = starting_hand_count
	_starting_cards_were_dealt = should_deal_starting_cards
	# 身份确认后重新旋转物理座次；领袖固定为一号位，后续数组顺序就是顺时针座次。
	_reorder_players_from_leader()
	if should_deal_starting_cards and _begin_starting_hand_mulligan():
		return
	_complete_pre_game_start()


## 创建所有玩家的手气卡确认阶段；返回true表示仍有真人需要决定是否刷新。
func _begin_starting_hand_mulligan() -> bool:
	if starting_hand_mulligan == null or _mulligan_limit == 0:
		return false
	# 按最终座次保存参与玩家 ID；服务只管理次数，不持有玩家或卡牌引用。
	var player_ids: Array[int] = []
	for player: PlayerState in state.players:
		player_ids.append(player.player_id)
	starting_hand_mulligan.begin(player_ids, _mulligan_limit, _ai_uses_mulligan_enabled)
	if not starting_hand_mulligan.active:
		return false
	state.current_phase = "starting_hand_mulligan"
	state.pre_game_setup = {"kind":"starting_hand_mulligan"}
	_drive_ai_starting_hand_mulligan()
	if not starting_hand_mulligan.active:
		return false
	add_log("起始手牌发放完成，等待所有玩家确认是否使用手气卡。")
	_emit_state()
	return true


## 完成全部开局前设置并由领袖开始首回合；普通开局和手气卡结束共用本唯一出口。
func _complete_pre_game_start() -> void:
	state.pre_game_setup.clear()
	# 手气卡阶段已经由最后一名玩家完成；先切换到首轮roundStart窗口，避免该时机的技能选择继续沿用开局确认界面。
	state.current_phase = "round_start"
	# 首回合稳定玩家ID；车轮战固定先手红方，其他模式继续读取普通选将服务的首任角色。
	var configured_first_player_id: int = state.players[0].player_id if identity_rules.starts_from_first_seat(str(state.match_mode)) and not state.players.is_empty() else character_selection.leader_player_id
	_record_runtime_event("phaseLoop", "phase_loop", {"first_player_id":configured_first_player_id})
	# 首回合玩家状态；身份局/斗地主由首任身份决定，2v2 固定一号位。
	var first_turn_player: PlayerState = null
	if identity_rules.starts_from_first_seat(str(state.match_mode)):
		first_turn_player = state.players[0] if not state.players.is_empty() else null
	else:
		first_turn_player = _find_player_by_identity(identity_rules.get_first_player_identity(str(state.match_mode)))
	if first_turn_player == null:
		push_error("对局缺少首回合角色，无法开始首回合。")
		return
	if _starting_cards_were_dealt:
		add_log("对局开始：%d名玩家，牌堆%d张，每名玩家起始手牌%d张。" % [state.players.size(), state.draw_pile.size(), _starting_hand_count])
	else:
		add_log("对局开始：%d名玩家，起始手牌分发被规则取消。" % state.players.size())
	# 首回合可能在roundStart立即创建技能询问；开始回合前必须先同步最终座次与起始手牌，保证本地内联候选已经存在于牌桌快照中。
	_emit_state()
	if conquest_mode != null and opportunity_system != null:
		# 过关斩将开局由全体玩家按“投票选择/各自选择”设置完成一次机缘；完成后通过专用恢复类型开始固定先手的第一回合。
		if _begin_conquest_group_opportunity("conquest_initial_opportunity", {"first_player_id":first_turn_player.player_id}):
			return
	_start_turn(first_turn_player.player_id)


## 返回过关斩将当前仍存活的全部玩家方稳定ID；按座次顺序排列，供机缘参与名单与全体奖励复用。
func _get_alive_conquest_player_ids() -> Array[int]:
	# 存活玩家方结果；死亡且复活耗尽的玩家不再参与机缘选择或投票。
	var result: Array[int] = []
	if conquest_mode == null or state == null:
		return result
	for conquest_player_id: int in conquest_mode.get_player_ids():
		# 当前玩家方角色状态；离场但存活角色继续参与机缘流程。
		var conquest_player: PlayerState = state.get_player(conquest_player_id)
		if conquest_player != null and conquest_player.alive:
			result.append(conquest_player_id)
	return result


## 返回过关斩将当前仍存活的全部敌方稳定ID；按座次顺序排列，供关卡奖励同步写入每名敌人。
func _get_alive_conquest_enemy_ids() -> Array[int]:
	# 存活敌方结果；换将过渡中的阵亡敌人由调用方按上下文单独处理。
	var result: Array[int] = []
	if conquest_mode == null or state == null:
		return result
	for conquest_enemy_id: int in conquest_mode.get_enemy_ids():
		# 当前敌方角色状态；只统计仍然存活的敌人。
		var conquest_enemy: PlayerState = state.get_player(conquest_enemy_id)
		if conquest_enemy != null and conquest_enemy.alive:
			result.append(conquest_enemy_id)
	return result


## 以本局锁定的“机缘选择”设置为过关斩将全体存活玩家发起一次机缘；返回是否成功进入机缘流程。
## 投票选择：全体玩家共享候选并投票，当选机缘人人获得；各自选择：每名玩家独立三选一。
## 单人局或仅剩一名存活玩家时两种设置行为一致，保持既有单人流程与存档回放不变。
func _begin_conquest_group_opportunity(resume_kind: String, resume_context: Dictionary) -> bool:
	if conquest_mode == null or opportunity_system == null or state == null or state.game_over:
		return false
	# 本次机缘参与者；全部存活玩家按座次顺序参与，全部阵亡时跳过机缘直接恢复流程。
	var participant_ids: Array[int] = _get_alive_conquest_player_ids()
	if participant_ids.is_empty():
		return false
	# 本局锁定的机缘选择方式；vote为投票选择，individual为各自选择，开局时从设置复制后不再变化。
	var choice_mode: String = str(state.match_options.get("conquest_opportunity_choice_mode", GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_VOTE))
	# 是否走投票流程；只有多名存活玩家且设置为投票时才建立共享候选。
	var uses_vote: bool = choice_mode == GameSettings.CONQUEST_OPPORTUNITY_CHOICE_MODE_VOTE and participant_ids.size() > 1
	# 机缘流程启动结果；组件持有活动流程或终局时返回false，调用方继续原有恢复路径。
	var opportunity_started: bool = false
	if uses_vote:
		opportunity_started = opportunity_system.force_trigger_vote_for_players(participant_ids[0], participant_ids, resume_kind, resume_context)
	else:
		opportunity_started = opportunity_system.force_trigger_for_players(participant_ids[0], participant_ids, resume_kind, resume_context)
	if opportunity_started:
		if participant_ids.size() > 1:
			add_log("第%d关%s，全体玩家%s一次机缘。" % [conquest_mode.get_level(), "开始" if resume_kind == "conquest_initial_opportunity" else "敌方整组入场", "投票选择" if uses_vote else "各自选择"])
		elif resume_kind == "conquest_initial_opportunity":
			# 单人开局保持既有日志文案；换将后的单人机缘继续沿用机缘组件自身的通用日志。
			add_log("第%d关开始，玩家选择一次机缘。" % conquest_mode.get_level())
	return opportunity_started


## 处理房主点击 AI 武将牌；目标合法后生成一组新的随机候选并通过私有选将快照打开选将框。
func _select_ai_adjustment_target(action: PlayerAction) -> bool:
	if state == null or state.current_phase != "ai_character_adjustment" or ai_character_adjustment == null:
		return _reject("当前不在 AI 武将调整阶段。")
	# 当前目标玩家 ID；只允许来自公共可调整 AI 集合。
	var target_player_id: int = int(action.payload.get("target_player_id", -1))
	# 调整服务校验结果；只有房主和内置 AI 目标可以通过。
	var selection_error: String = ai_character_adjustment.select_ai_target(action.actor_id, target_player_id)
	if not selection_error.is_empty():
		return _reject(selection_error)
	state.action_sequence += 1
	_emit_state()
	return true


## 应用房主为当前 AI 选择的武将；技能尚未安装，因此只需重新初始化该玩家武将与基础体力。
func _set_ai_character(action: PlayerAction) -> bool:
	if state == null or state.current_phase != "ai_character_adjustment" or ai_character_adjustment == null:
		return _reject("当前不在 AI 武将调整阶段。")
	# 当前 AI 玩家与武将 ID；均由选将框提交稳定值。
	var target_player_id: int = int(action.payload.get("target_player_id", -1))
	var character_id: String = str(action.payload.get("character_id", ""))
	# 服务校验结果；空字符串表示房主、目标与候选均有效。
	var selection_error: String = ai_character_adjustment.select_character(action.actor_id, target_player_id, character_id)
	if not selection_error.is_empty():
		return _reject(selection_error)
	# 当前 AI 玩家状态；服务已经确认目标属于本局 AI，仍防御性检查状态存在。
	var target_player: PlayerState = state.get_player(target_player_id)
	if target_player == null:
		return _reject("需要调整的 AI 玩家不存在。")
	_apply_character(target_player, character_id, true)
	state.action_sequence += 1
	state.random_history.append({"kind":"ai_character_adjustment", "player_id":target_player_id, "character_id":character_id})
	add_log("房主将%s的武将调整为【%s】。" % [target_player.display_name, GameDatabase.resolve_character_name(character_id)])
	_emit_state()
	return true


## 处理房主结束 AI 武将调整的动作；完成后立即进入统一开局与起始手牌流程。
func _finish_ai_character_adjustment_action(action: PlayerAction) -> bool:
	if state == null or state.current_phase != "ai_character_adjustment" or ai_character_adjustment == null:
		return _reject("当前不在 AI 武将调整阶段。")
	# 服务结束结果；非房主提交会被明确拒绝。
	var finish_error: String = ai_character_adjustment.finish(action.actor_id)
	if not finish_error.is_empty():
		return _reject(finish_error)
	state.action_sequence += 1
	add_log("房主完成 AI 武将调整。")
	_continue_game_start_after_character_adjustment()
	return true


## 处理玩家使用一次手气卡；成功后旧手牌洗回牌堆并重新发放相同数量的起始手牌。
func _submit_mulligan_refresh(action: PlayerAction) -> bool:
	if state == null or state.current_phase != "starting_hand_mulligan" or starting_hand_mulligan == null:
		return _reject("当前不在手气卡阶段。")
	if not starting_hand_mulligan.can_refresh(action.actor_id):
		return _reject("当前玩家没有剩余手气卡张数。")
	if not _refresh_starting_hand(action.actor_id, false):
		return _reject("起始手牌刷新失败。")
	state.action_sequence += 1
	add_log("%s使用手气卡刷新了起始手牌。" % format_player_log_name(action.actor_id))
	_emit_state()
	return true


## 处理玩家确认保留当前起始手牌；全部玩家完成后才进入领袖首回合。
func _submit_mulligan_finish(action: PlayerAction) -> bool:
	if state == null or state.current_phase != "starting_hand_mulligan" or starting_hand_mulligan == null:
		return _reject("当前不在手气卡阶段。")
	if not starting_hand_mulligan.finish_player(action.actor_id):
		return _reject("当前玩家已经完成手气卡确认。")
	state.action_sequence += 1
	if starting_hand_mulligan.active:
		_emit_state()
	else:
		_complete_pre_game_start()
	return true


## 让全部内置 AI 按最终座次评估起始手牌；关闭 AI 手气卡时直接确认保留。
func _drive_ai_starting_hand_mulligan() -> void:
	if starting_hand_mulligan == null or not starting_hand_mulligan.active:
		return
	for seat_index: int in range(state.players.size()):
		# 当前最终座次玩家；只有内置 AI 自动处理，真人与局域网玩家等待各自提交。
		var player: PlayerState = state.players[seat_index]
		if not ai_coordinator.is_ai_controlled(player.player_id):
			continue
		while starting_hand_mulligan.can_choose(player.player_id):
			# 当前 AI 是否需要刷新；后置位防御需求通过服务按座次连续提高。
			var should_refresh: bool = starting_hand_mulligan.should_ai_refresh(player, seat_index + 1, state.players.size())
			if should_refresh and _refresh_starting_hand(player.player_id, true):
				continue
			starting_hand_mulligan.finish_player(player.player_id)
			break


## 把一名玩家当前全部起始手牌洗回牌堆、重洗并重新发放；不进入弃牌堆、不触发普通摸牌时机且不改变手牌数量。
func _refresh_starting_hand(player_id: int, is_ai: bool) -> bool:
	# 当前刷新玩家；无效、死亡或手气卡服务拒绝时不移动任何牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or starting_hand_mulligan == null or not starting_hand_mulligan.can_refresh(player_id):
		return false
	_ensure_card_movement()
	if card_movement == null:
		return false
	# 当前旧手牌副本；逐张通过唯一移动服务返回牌堆，避免直接清空数组留下区域字段不一致。
	var returned_cards: Array[CardInstance] = player.hand.duplicate()
	# 本次需要重新发放的牌数；使用实际起始手牌数量，兼容开局规则调整后的非4张初始手牌。
	var redeal_count: int = returned_cards.size()
	for card: CardInstance in returned_cards:
		if card_movement.move_card(card, "draw_pile", -1, "mulligan_return", state.current_event_id) == null:
			return false
		card.known_to.clear()
		card.shown = false
		card.private_owner_id = -1
	# 牌堆重新洗牌；固定种子下每次手气卡结果可由 random_history 复现。
	_shuffle_array(state.draw_pile)
	var shuffled_card_uids: Array[int] = []
	for shuffled_card: CardInstance in state.draw_pile:
		shuffled_card_uids.append(shuffled_card.uid)
	state.random_history.append({"kind":"mulligan_shuffle", "player_id":player_id, "card_uids":shuffled_card_uids})
	if not starting_hand_mulligan.consume_refresh(player_id, is_ai):
		return false
	# 手气卡重发只属于开局配置替换，不是回合内摸牌；直接移动实体牌可避免触发摸牌技能或被摸牌修正改变数量。
	for _card_index: int in range(redeal_count):
		if state.draw_pile.is_empty():
			return false
		# 当前牌堆顶实体；数组末尾与普通摸牌入口保持相同牌堆方向。
		var redealt_card: CardInstance = state.draw_pile.back()
		if card_movement.move_card(redealt_card, "hand", player_id, "mulligan_deal", state.current_event_id, "", [player_id]) == null:
			return false
	return player.hand.size() == redeal_count


## 以领袖为数组首位旋转普通身份局玩家，保留稳定 player_id 供网络、回放和实体牌所有权使用。
func _reorder_players_from_leader() -> void:
	# 斗地主的身份池已经按本局随机源洗牌；保留创建时的物理座次，避免把随机地主旋转回一号位而使画面恒为固定身份顺序。
	# 首回合仍由 _complete_pre_game_start 按地主身份单独寻找，不依赖玩家数组第一位。
	if identity_rules.normalize_mode(str(state.match_mode)) == IdentityRules.MODE_DOUDIZHU:
		_refresh_player_display_names_for_current_seats()
		return
	# 首任公开身份；普通身份局为领袖，非斗地主模式继续沿用领袖一号位的既有规则。
	var first_identity: String = identity_rules.get_first_player_identity(str(state.match_mode))
	# 首任身份在当前数组中的索引；身份分配完成前不调用此函数。
	var leader_index: int = -1
	for index: int in range(state.players.size()):
		if state.players[index].identity == first_identity:
			leader_index = index
			break
	if leader_index > 0:
		# 旋转后的座次数组；首任身份角色为一号位，其原下家按顺时针依次成为后续座次。
		var reordered_players: Array[PlayerState] = []
		for offset: int in range(state.players.size()):
			reordered_players.append(state.players[(leader_index + offset) % state.players.size()])
		state.players = reordered_players
	# 玩家显示编号属于当前对局座次，不属于稳定 player_id；旋转完成后统一刷新，日志与牌面名称保持一致。
	for seat_index: int in range(state.players.size()):
		# 当前座次玩家；AI 控制权决定显示名前缀，网络或本地真实玩家不添加 AI 标记。
		var seated_player: PlayerState = state.players[seat_index]
		seated_player.display_name = _resolve_seat_display_name(seated_player, seat_index)


## 按当前玩家数组顺序刷新座次显示名；自选座次已经完成排序时不再旋转数组。
func _refresh_player_display_names_for_current_seats() -> void:
	for seat_index: int in range(state.players.size()):
		# 当前座次玩家；局域网真人沿用大厅名称，离线真人与 AI 使用最终座次编号。
		var seated_player: PlayerState = state.players[seat_index]
		seated_player.display_name = _resolve_seat_display_name(seated_player, seat_index)


## 解析单名角色在当前座次下的统一显示名；局域网真人沿用大厅昵称，其余按模式与AI控制权生成座次名称。
## 过关斩将使用“玩家K/[AI]敌人K”的交替命名，其他模式保持“玩家N/[AI]玩家N”的既有规则。
func _resolve_seat_display_name(seated_player: PlayerState, seat_index: int) -> String:
	if seated_player == null:
		return "玩家%d" % (seat_index + 1)
	# 局域网真人昵称优先；房主与远端真人在任何模式下都沿用大厅显示名。
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.get_lan_human_player_ids().has(seated_player.player_id):
		return network_gateway.get_lan_player_display_name(seated_player.player_id)
	# 当前角色是否由内置 AI 控制；决定显示名的 AI 前缀。
	var is_ai_seat: bool = ai_coordinator != null and ai_coordinator.is_ai_controlled(seated_player.player_id)
	if identity_rules.normalize_mode(str(state.match_mode)) == IdentityRules.MODE_CONQUEST:
		return _make_conquest_seat_display_name(seat_index, not is_ai_seat)
	return ("[AI]玩家%d" if is_ai_seat else "玩家%d") % (seat_index + 1)


## 生成过关斩将的交替座位默认名：偶数座位为红方“玩家K”，奇数座位为蓝方“[AI]敌人K”。
## K 为同阵营内的序号（从1开始）；未被真人占用的玩家座位显示“[AI]玩家K”。
func _make_conquest_seat_display_name(seat_index: int, is_human_player: bool) -> String:
	# 同阵营序号；玩家1对应座位0，敌人1对应座位1，玩家2对应座位2，以此类推。显式向下取整避免整数除法告警。
	var side_ordinal: int = int(floorf(float(seat_index) / 2.0)) + 1
	if seat_index % 2 == 0:
		return ("玩家%d" if is_human_player else "[AI]玩家%d") % side_ordinal
	return "[AI]敌人%d" % side_ordinal


## 让内置 AI 在当前选将阶段从自己的候选中确认首张；所有 AI 仍通过同一 select_character 校验入口。
func _drive_ai_character_selection() -> void:
	if is_gameplay_paused() or _is_driving_character_selection or character_selection == null or character_selection.phase == CharacterSelectionService.PHASE_COMPLETE:
		return
	# 自选模式优先等待全部真人确认，避免 AI 抢占真人希望选择的座次与身份名额。
	# 斗地主全员同时选将也使用同一等待策略（阶段为 PHASE_OTHERS，而非身份局 PHASE_CUSTOM）。
	if character_selection.custom_assignment_enabled and (
		character_selection.phase == CharacterSelectionService.PHASE_CUSTOM
		or (character_selection.uses_simultaneous_selection() and character_selection.phase == CharacterSelectionService.PHASE_OTHERS)
	):
		for pending_player_id: int in character_selection.get_pending_player_ids():
			if not ai_coordinator.is_ai_controlled(pending_player_id):
				return
	_is_driving_character_selection = true
	while character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		# 自选阶段每轮都重新检查真人完成状态；首任领袖由 AI 确认后可能在同一循环内刚进入该阶段。
		# 斗地主同时选将同样需等待真人，防止 AI 先占座次/身份导致五人局卡死。
		if character_selection.custom_assignment_enabled and (
			character_selection.phase == CharacterSelectionService.PHASE_CUSTOM
			or (character_selection.uses_simultaneous_selection() and character_selection.phase == CharacterSelectionService.PHASE_OTHERS)
		):
			var waiting_for_human: bool = false
			for pending_custom_player_id: int in character_selection.get_pending_player_ids():
				if not ai_coordinator.is_ai_controlled(pending_custom_player_id):
					waiting_for_human = true
					break
			if waiting_for_human:
				break
		# 当前轮是否提交了至少一项 AI 选择；没有进展表示正在等待人类或网络玩家。
		var made_progress: bool = false
		# 当前待确认玩家副本；每轮结束后重新获取，安全覆盖领袖到其他玩家的阶段切换。
		var pending_player_ids: Array[int] = character_selection.get_pending_player_ids()
		# 首任AI领袖已经锁定公开武将，但仍等待最终座次身份。真人全部确认后，它必须先取得仍空缺的一号位与领袖，
		# 否则按稳定玩家ID排序的其他AI会先抢占领袖，使已公开武将被错误降为其他身份。
		var retained_initial_leader_player_id: int = character_selection.leader_player_id
		if character_selection.is_retaining_initial_leader_character(retained_initial_leader_player_id):
			pending_player_ids.erase(retained_initial_leader_player_id)
			pending_player_ids.push_front(retained_initial_leader_player_id)
		for player_id: int in pending_player_ids:
			if not ai_coordinator.is_ai_controlled(player_id):
				continue
			# AI 候选武将；优先从尚未被其他玩家确认的私有候选中选择，避免所有 AI 继承同一张武将牌。
			var character_id: String = _get_ai_character_selection_candidate(player_id)
			if character_id.is_empty():
				# 当前候选若全部已被其他玩家确认，重建不占用换将卡的未占用候选后重试一次。
				character_selection.reroll_unclaimed_candidates(player_id)
				character_id = _get_ai_character_selection_candidate(player_id)
			if character_id.is_empty():
				continue
			# AI 选将动作；与人类和网络玩家共用标准 PlayerAction 入口及服务校验。
			var action: PlayerAction = PlayerAction.new("select_character", player_id)
			action.payload = {"character_id":character_id}
			# 当前 AI 是否必须同时提交座次身份；身份局最终自选与斗地主同时选将均需完整分配。
			var requires_custom_assignment: bool = character_selection.custom_assignment_enabled and (
				character_selection.phase == CharacterSelectionService.PHASE_CUSTOM
				or (character_selection.uses_simultaneous_selection() and character_selection.phase == CharacterSelectionService.PHASE_OTHERS)
			)
			if requires_custom_assignment:
				# 当前剩余座次与身份；斗地优先占满固定地主座（1/3），2v2 按开局成队表绑定蓝/红，身份局优先一号位与领袖。
				var available_seats: Array[int] = character_selection.get_available_seat_numbers(player_id)
				var available_identities: Array[String] = character_selection.get_available_identities(player_id)
				var selected_seat_number: int = -1
				var selected_identity: String = ""
				var first_seat_identity: String = character_selection.get_first_seat_identity()
				var landlord_seats: Array[int] = character_selection.get_landlord_seat_numbers()
				if character_selection.is_doudizhu_mode() and not landlord_seats.is_empty():
					# 优先给空闲地主位填地主，再给空闲农民位填农民。
					var filled: bool = false
					if available_identities.has("landlord"):
						for landlord_seat: int in landlord_seats:
							if available_seats.has(landlord_seat):
								selected_seat_number = landlord_seat
								selected_identity = "landlord"
								filled = true
								break
					if not filled and available_identities.has("peasant"):
						for seat_option: int in available_seats:
							if not landlord_seats.has(seat_option):
								selected_seat_number = seat_option
								selected_identity = "peasant"
								filled = true
								break
					if not filled and not available_seats.is_empty() and not available_identities.is_empty():
						selected_seat_number = available_seats[0]
						selected_identity = available_identities[0]
				elif character_selection.is_team2v2_mode():
					# 2v2：座次与蓝/红按开局成队表绑定；优先沿用首次随机座次（其身份由绑定表决定）。
					var preferred_seat_number: int = character_selection.get_initial_seat_number(player_id)
					var preferred_identity: String = character_selection.get_initial_identity(player_id)
					var filled: bool = false
					var seat_bound_identity: String = ""
					if available_seats.has(preferred_seat_number):
						seat_bound_identity = character_selection.get_team2v2_identity_for_seat(preferred_seat_number)
						if seat_bound_identity.is_empty():
							seat_bound_identity = preferred_identity
						if available_identities.has(seat_bound_identity):
							selected_seat_number = preferred_seat_number
							selected_identity = seat_bound_identity
							filled = true
					if not filled:
						# 偏好座已被占用：先找仍可用的同色座，再任意合法绑定对。
						var team_seats: Array[int] = character_selection.get_team2v2_seats_for_identity(preferred_identity)
						for team_seat: int in team_seats:
							if available_seats.has(team_seat) and available_identities.has(preferred_identity):
								selected_seat_number = team_seat
								selected_identity = preferred_identity
								filled = true
								break
					if not filled:
						for seat_option: int in available_seats:
							seat_bound_identity = character_selection.get_team2v2_identity_for_seat(seat_option)
							if not seat_bound_identity.is_empty() and available_identities.has(seat_bound_identity):
								selected_seat_number = seat_option
								selected_identity = seat_bound_identity
								filled = true
								break
					if not filled and not available_seats.is_empty() and not available_identities.is_empty():
						selected_seat_number = available_seats[0]
						selected_identity = character_selection.get_team2v2_identity_for_seat(selected_seat_number)
						if selected_identity.is_empty() or not available_identities.has(selected_identity):
							selected_identity = available_identities[0]
				elif not first_seat_identity.is_empty() and available_seats.has(1) and available_identities.has(first_seat_identity):
					# 身份局/需绑定一号位的模式：优先同时占住一号位与首任身份。
					selected_seat_number = 1
					selected_identity = first_seat_identity
				else:
					# 仅当仍有“唯一首任身份”尚未落定，才预留一号位给后续玩家。
					# 2v2 已在上方专用分支处理，绝不能 erase(1) 导致最后一名 AI 提交 seat=-1。
					if (
						not first_seat_identity.is_empty()
						and character_selection.has_unique_first_seat_identity()
						and available_identities.has(first_seat_identity)
					):
						available_seats.erase(1)
						available_identities.erase(first_seat_identity)
					if not available_seats.is_empty() and not available_identities.is_empty():
						var preferred_seat_number: int = character_selection.get_initial_seat_number(player_id)
						var preferred_identity: String = character_selection.get_initial_identity(player_id)
						selected_seat_number = preferred_seat_number if available_seats.has(preferred_seat_number) else available_seats[0]
						selected_identity = preferred_identity if available_identities.has(preferred_identity) else available_identities[0]
						if (
							selected_seat_number == 1
							and not first_seat_identity.is_empty()
							and available_identities.has(first_seat_identity)
						):
							selected_identity = first_seat_identity
				action.payload["seat_number"] = selected_seat_number
				action.payload["identity"] = selected_identity
			made_progress = _submit_ai_action(action) or made_progress
		if not made_progress:
			break
	_is_driving_character_selection = false


## 返回 AI 当前可安全确认的一张候选武将；当前已公开的预览领袖优先确认同一武将，避免进入对局时重新随机。
func _get_ai_character_selection_candidate(player_id: int) -> String:
	if character_selection == null:
		return ""
	# 首任领袖的公开武将已经写入最终选择；自选阶段只差座次身份确认时，AI必须提交同一ID，不能因候选列表已清空而停住或重新抽取。
	var retained_initial_leader_character_id: String = character_selection.get_selection(player_id)
	if character_selection.is_retaining_initial_leader_character(player_id):
		return retained_initial_leader_character_id
	# 当前公开预览领袖；最终自选中该AI已经有向玩家展示的武将时，确认必须复用该结果而不是改取另一张随机候选。
	var preview_leader: PlayerState = state.players[0] if state != null and not state.players.is_empty() else null
	if character_selection.phase == CharacterSelectionService.PHASE_CUSTOM and preview_leader != null and preview_leader.player_id == player_id and preview_leader.identity == character_selection.get_first_seat_identity() and not preview_leader.character_id.is_empty():
		# 公开领袖武将是否已经被其他玩家确认；若发生冲突则继续走普通候选筛选，避免AI提交无效重复武将。
		var preview_character_already_selected: bool = false
		for player: PlayerState in state.players:
			if player.player_id != player_id and character_selection.get_selection(player.player_id) == preview_leader.character_id:
				preview_character_already_selected = true
				break
		if not preview_character_already_selected:
			return preview_leader.character_id
	# 当前 AI 私有候选；候选仍由选将服务生成，控制器只过滤已经落定的稳定武将 ID。
	var candidates: Array[String] = character_selection.get_candidates(player_id)
	# 当前尚未被其他玩家确认的合法候选；普通AI继续使用首张随机候选，首任AI领袖会在完整集合中随机选择。
	var available_candidates: Array[String] = []
	for candidate_id: String in candidates:
		var already_selected: bool = false
		for player: PlayerState in state.players:
			if player.player_id != player_id and character_selection.get_selection(player.player_id) == candidate_id:
				already_selected = true
				break
		if not already_selected:
			available_candidates.append(candidate_id)
	# 首任AI领袖的领袖技候选虽然固定排在列表前端，但不应形成取将优先级。
	# 它从本次全部合法候选中使用对局随机源取一张，使普通候选与领袖技候选拥有相同的被选择机会。
	if character_selection.phase == CharacterSelectionService.PHASE_LEADER and player_id == character_selection.leader_player_id and not available_candidates.is_empty():
		return available_candidates[_rng.randi_range(0, available_candidates.size() - 1)]
	if not available_candidates.is_empty():
		return available_candidates[0]
	return ""


## 根据牌堆配置创建实体牌、设置区域并洗牌。
func _create_and_shuffle_deck() -> void:
	for entry_variant: Variant in GameDatabase.get_deck_cards(state.deck_id):
		# 紧凑牌堆条目；格式为花色、点数、卡牌定义 ID。
		var entry: Array = entry_variant as Array
		# 新建实体牌；唯一 UID 由 CardInstance 自动分配。
		var card: CardInstance = CardInstance.new(str(entry[2]), str(entry[0]), int(entry[1]))
		card.zone = "draw_pile"
		card.owner_id = -1
		state.draw_pile.append(card)
	_shuffle_array(state.draw_pile)
	var shuffled_card_uids: Array[int] = []
	for shuffled_card: CardInstance in state.draw_pile:
		shuffled_card_uids.append(shuffled_card.uid)
	state.random_history.append({"kind":"deck_shuffle", "deck_id":state.deck_id, "card_uids":shuffled_card_uids})


## 安排一次相邻阶段切换；当前阶段先广播给界面，计时结束后仍匹配同一对局、角色和阶段才执行。
func _schedule_phase_transition(player_id: int, expected_phase: String, callback: Callable) -> void:
	if state == null or state.game_over or not callback.is_valid():
		return
	# 当前对局 ID；重新开局会更换该值，使旧计时任务即使恢复也不能进入新局阶段。
	var expected_match_id: String = state.match_id
	# 登记时即时复核上下文；迟到恢复若已不属于当前角色或阶段，不能先取消现有正确任务再留下一个必然失效的回调。
	var validity_guard: Callable = Callable(self, "_is_phase_transition_context_current").bind(expected_match_id, player_id, expected_phase)
	if not bool(validity_guard.call()):
		return
	_emit_state()
	# 校验后的阶段回调；节奏组件不持有规则状态，只在到期后把控制权交还给控制器。
	var guarded_callback: Callable = Callable(self, "_execute_scheduled_phase_transition").bind(expected_match_id, player_id, expected_phase, callback)
	if game_flow_transition_coordinator == null:
		guarded_callback.call()
		return
	# 转换语义键；同一对局、回合、角色、阶段与目标方法的重复恢复被视为同一意图，不会重置已经开始的等待时间。
	var transition_key: String = "%s:%d:%d:%s:%s" % [expected_match_id, state.turn_number, player_id, expected_phase, callback.get_method()]
	game_flow_transition_coordinator.schedule_transition(transition_key, game_flow_interval_seconds, validity_guard, guarded_callback)


## 判断阶段转换上下文在当前权威状态中是否仍成立；协调器在登记与计时到期时复用同一纯查询守卫。
func _is_phase_transition_context_current(expected_match_id: String, player_id: int, expected_phase: String) -> bool:
	return state != null \
		and not state.game_over \
		and state.match_id == expected_match_id \
		and state.current_player_id == player_id \
		and state.current_phase == expected_phase


## 执行到期的阶段切换；任何终局、重开、角色变化或阶段变化都会让旧回调静默失效。
func _execute_scheduled_phase_transition(expected_match_id: String, player_id: int, expected_phase: String, callback: Callable) -> void:
	if state == null or state.game_over or state.match_id != expected_match_id:
		return
	if state.current_player_id != player_id or state.current_phase != expected_phase:
		return
	if callback.is_valid():
		callback.call()


## 开始指定玩家的回合；回合开始前的机缘判定先于该角色的一切回合事实。
func _start_turn(player_id: int) -> void:
	if state.game_over:
		return
	# 已预约的过关斩将临时退出在干净回合边界优先生效；此时上一回合结算已完整结束，新回合尚未产生任何状态变化。
	if _try_capture_conquest_temporary_exit(player_id):
		return
	if _conquest_temporary_exit_requested and state.current_phase == "finish":
		# 结算续接仍在延后唤醒中；暂停进入新回合，待统一管线排空后重试同一边界。
		_pending_conquest_boundary_player_id = player_id
		_resume_settlement_pipeline()
		if _try_capture_conquest_temporary_exit(player_id):
			_pending_conquest_boundary_player_id = -1
			return
		_schedule_settlement_pipeline_resume()
		return
	# 上一回合残留的出牌选择；必须先从真实事件栈移除，新的阶段与 CardUseEvent 才能进入根事件。
	_cancel_active_play_choice("turn_changed")
	_started_phase_lifecycles.clear()
	_main_phase_play_conversions.clear()
	_active_converted_play_phase_context.clear()
	# 新回合玩家状态；死亡玩家会由调用方提前跳过，该角色在回合开始前机缘中死亡时同样不再开始回合。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	_ai_drive_token += 1
	_ai_actions_this_turn = 0
	_judgment_flow_token += 1
	_judgment_flow_in_progress = false
	_judgment_resume_needs_result_pause = false
	_clear_pending_judgment_request()
	# 本回合是否开启新轮：仅普通回合可开新轮，额外回合即使落在一号位也不得递增 round_number 或再发 roundStart。
	# 轮锚点取座次数组中第一名存活且未离场的角色（一号位死亡时顺延），时机顺序保持 roundStart 早于该角色的回合开始初始化。
	var starts_new_round: bool = _will_start_new_round(player_id)
	if starts_new_round:
		state.round_number += 1
	# 回合开始前机缘判定；此时上一回合已完整结束，本角色尚未产生任何回合事实。
	# 触发通过时本函数立即返回，由 continue_after_opportunity 在机缘全部结算后回调 _begin_turn_after_opportunity。
	# 阿哈时刻紧随机缘之后判定：两者共用同一条回合开始前事件链，机缘结算完毕后仍会回到该链继续判定阿哈时刻。
	_continue_turn_start_prelude(player_id, starts_new_round, true, true)


## 建立该角色的回合事实并推进回合开始游标；回合开始前的机缘已经结束或未触发后调用。
## starts_new_round 由回合开始前的轮边界判定给出，机缘结算期间的座次或存活变化不得改变本次轮递增结果。
func _begin_turn_after_opportunity(player_id: int, starts_new_round: bool) -> void:
	if state == null or state.game_over:
		return
	# 回合开始玩家状态；机缘效果可能已经令其死亡或离场，调用方负责在进入本入口前完成跳过。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	state.current_player_id = player_id
	state.turn_number += 1
	# 锁定“直到其下个回合结束”的手牌视为效果；本回合内新建立的效果不会被本次回合尾提前清理。
	_arm_hand_view_as_expiries_for_turn(player_id)
	# 回合开始恢复上下文；回合内容组件据此在轮开始、准备阶段之间保持稳定游标，且不重复递增轮数或回合数。
	var turn_start_context: Dictionary = {"stage":"round_start", "player_id":player_id, "starts_new_round":starts_new_round}
	_continue_turn_start(turn_start_context)


## 回合开始前的统一事件链：机缘选择判定 → 阿哈时刻判定 → 建立回合事实。
## 两个环节的先后顺序固定：机缘在前、阿哈时刻在后，与“阿哈时刻模仿机缘选择的触发时机”的需求口径一致。
## allow_opportunity 与 allow_ahha 用于区分“首次进入回合开始”与“某个环节结算后恢复”，避免同一环节被重复判定。
## 该链在任一步创建选择或演出后立即返回，由对应组件的恢复入口带着同一角色与本轮轮边界结论重新进入。
func _continue_turn_start_prelude(player_id: int, starts_new_round: bool, allow_opportunity: bool, allow_ahha: bool) -> void:
	if state == null or state.game_over:
		return
	# 待开始角色状态；前一个环节的效果可能已经令其死亡或离场，此时不再建立任何回合事实。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return
	# 回合开始前上下文；两个环节共用同一份可序列化描述，恢复时由控制器按原角色重新组装。
	var turn_start_context: Dictionary = {"stage":"round_start", "player_id":player_id, "starts_new_round":starts_new_round}
	if allow_opportunity and opportunity_system != null and opportunity_system.try_trigger_before_turn_start(turn_start_context, _current_turn_is_extra):
		return
	if allow_ahha and ahha_moment_system != null and ahha_moment_system.try_trigger_before_turn_start(turn_start_context, _current_turn_is_extra):
		return
	_begin_turn_after_opportunity(player_id, starts_new_round)


## 在阿哈时刻全部欢愉技依次演出结束后恢复回合开始；组件不保存Callable或调用控制器私有游标。
## 演出期间的伤害与结算可能已经改变该角色的存活状态与额外回合队列，因此恢复前必须重新校验。
func continue_after_ahha_moment(player_id: int, starts_new_round: bool) -> void:
	if state == null or state.game_over:
		return
	# 原定角色状态；演出效果可能已经令其死亡或离场，此时不再开始其回合。
	var pending_player: PlayerState = state.get_player(player_id)
	if pending_player == null or not pending_player.alive or pending_player.out_of_game:
		_start_queued_or_normal_turn(state.current_player_id)
		return
	# 演出期间获得的额外回合在回合开始前立即执行；全部完成后才建立原定角色的回合事实。
	if _resume_pending_turn_after_extra_turns(player_id, starts_new_round):
		return
	_begin_turn_after_opportunity(player_id, starts_new_round)


## 恢复由技能请求、已经完整结束的独立欢愉技演出；只把控制权交还发起技能。
## 与 continue_after_ahha_moment 的区别：本入口不推进回合开始游标，也不重新建立回合事实，
## 因为额外演出发生在回合开始窗口内部或回合进行中，回合归属并未改变。
func continue_after_standalone_joy_performance(context: Dictionary) -> void:
	# 发起技能归属角色与稳定技能ID；缺失时直接丢弃，避免把回调交给随机实例。
	var skill_owner_id: int = int(context.get("skill_owner_id", -1))
	var skill_id: String = str(context.get("skill_id", ""))
	if state == null or state.game_over or skill_owner_id < 0 or skill_id.is_empty():
		return
	# 当前运行时技能实例；换将或技能重装后武将代次不一致时安全跳过，不再执行旧实例的后续。
	var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id)
	if skill == null or not skill.matches_character_generation(int(context.get("skill_character_generation", -1))):
		return
	# 完成上下文副本；技能只读取稳定值，不得通过本字典改写调用方的运行时对象。
	var stable_context: Dictionary = context.duplicate(true)
	skill.continue_joy_performance(stable_context)
	# 技能回调可能立即登记「然后」步骤或创建新选择；统一管线与停滞守卫会按既有顺序继续。
	_resume_settlement_pipeline()


## 令指定角色立即发动其指定欢愉技；独立于常规阿哈时刻队列，演出结束后回调发起技能。
## 内容文件只经本端口访问阿哈时刻组件，不直接持有组件引用。
func try_perform_single_joy_skill(player_id: int, skill_id: String, completion_context: Dictionary) -> bool:
	if ahha_moment_system == null:
		return false
	return ahha_moment_system.try_perform_single_joy_skill(player_id, skill_id, completion_context)


## 令指定角色立即触发一次额外阿哈时刻；跳过触发概率与本轮额度，演出结束后回调发起技能。
func try_trigger_extra_moment(trigger_player_id: int, completion_context: Dictionary) -> bool:
	if ahha_moment_system == null:
		return false
	return ahha_moment_system.try_trigger_extra_moment(trigger_player_id, completion_context)


## 判断指定角色的本次回合是否会开启新的一轮；额外回合不得开启新轮，也不得递增 round_number。
func _will_start_new_round(player_id: int) -> bool:
	if _current_turn_is_extra:
		return false
	# 轮锚点取座次数组中第一名存活且未离场的角色（一号位死亡时顺延）。
	for candidate_player: PlayerState in state.players:
		if candidate_player != null and candidate_player.alive and not candidate_player.out_of_game:
			return candidate_player.player_id == player_id
	return false


## 按稳定阶段游标发布回合开始与准备阶段时机；任一时机插入选择后先保存直接后续，恢复时不会越过或重复发布其他时机。
func _continue_turn_start(context: Dictionary) -> void:
	# 回合开始内容组件；每个时机的恢复位置由RuleStepSequence持有。
	var turn_service: RefCounted = TURN_START_SERVICE_SCRIPT.new(self)
	turn_service.resolve(context)


## 初始化新回合事实；只在轮开始子内容全部结束后执行一次，不发布可暂停时机。
func _initialize_turn_context(context: Dictionary) -> void:
	# 本回合角色ID；初始化前已经由回合内容组件校验。
	var player_id: int = int(context.get("player_id", -1))
	# 当前角色；这里只清理回合级事实，不持有跨选择的实体引用。
	var player: PlayerState = state.get_player(player_id)
	# 当前回合运行时事件 ID；只在轮开始触发全部完成后创建一次，后续所有阶段时机共享该父事件。
	var turn_event_id: int = _record_runtime_event("phase", "turn", {"player_id":player_id, "turn_number":state.turn_number, "round_number":state.round_number})
	context["turn_event_id"] = turn_event_id
	_current_turn_event_id = turn_event_id
	# 全局回合用牌事实；每个新回合清空全部角色记录，供“本回合内其使用过某牌”的跨角色技能精确查询。
	_cards_used_this_turn_by_player.clear()
	player.skipped_phases.clear()
	player.card_use_history.clear()
	player.card_use_limit_exempt_history.clear()
	player.response_history.clear()
	player.damage_history.clear()
	player.skill_history.clear()
	player.ai_failed_card_target_ids.clear()
	_notify_card_definitions_turn_started(player_id)
	player.turn_history.append({"turn_number":state.turn_number, "round_number":state.round_number, "event_id":turn_event_id, "skipped_phases":[]})
	state.current_phase = "start"
	state.phase_index = 0


## 准备阶段主体也是可订阅窗口；准备阶段Begin、主体、End、After按同一协议等待。
func _run_preparation_phase_body(player_id: int) -> void:
	_run_phase_notification("phaseZhunbei", player_id, {"turn_number":state.turn_number}, Callable(self, "_continue_turn_after_preparation_phase").bind(player_id))


## 完成准备阶段主体并安排判定阶段；选择窗口恢复后可再次调用，已完成主体不会重复派发开始事件。
func _continue_turn_after_preparation_phase(player_id: int) -> void:
	if state == null or state.game_over or has_pending_card_choice() or state.current_player_id != player_id or state.current_phase != "start":
		return
	# 当前准备阶段生命周期键；仍存在时说明本次调用需要执行阶段主体，已被结束时机移除时只续接后续阶段。
	var lifecycle_key: String = "%d:%s" % [player_id, "phaseZhunbei"]
	# 当前回合玩家；准备阶段选择等待期间可能已经死亡或离场，继续前必须重新读取状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	if _started_phase_lifecycles.has(lifecycle_key):
		_finish_phase_lifecycle("phaseZhunbei", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_continue_turn_after_preparation_phase").bind(player_id))
		return
	if state.game_over:
		return
	if not player.alive or player.out_of_game:
		if player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	_schedule_phase_transition(player_id, "start", Callable(self, "_enter_judgment_phase").bind(player_id))


## 完成因背面朝上而跳过的完整回合；不伪造准备、判定、摸牌、出牌、弃牌或结束阶段，只保留统一回合后与下家轮转。
func _complete_face_down_skipped_turn(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id:
		return
	# 直接复用已完成阶段后的回合尾部；该入口只清理回合持续状态、派发phaseAfter并计算下一回合，不会补发任何阶段主体。
	_complete_finish_turn(player_id)


## 进入当前角色的判定阶段；阶段主体可能被无懈、濒死或其他统一选择请求异步暂停。
func _enter_judgment_phase(player_id: int, change_completed: bool = false) -> void:
	# 当前回合玩家；阶段间隔期间死亡或离场时不再建立判定阶段。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	if _is_main_phase_converted_to_play(player_id, "judgment"):
		_start_converted_main_phase_as_play(player_id, "judgment", "draw")
		return
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":"start", "to_phase":"judgment"}, _current_turn_event_id, Callable(self, "_enter_judgment_phase").bind(player_id, true))
		return
	state.current_phase = "judgment"
	state.phase_index = 1
	_record_runtime_event("phaseJudgeStage", "phase", {"player_id":player_id}, {}, _current_turn_event_id)
	# 永久跳过判定阶段机缘；通过统一跳过入口派发Skipped时机并安排唯一的摸牌阶段后继。
	if has_acquired_opportunity_permanent_phase_skip(player_id, "judgment"):
		skip_current_main_phase(player_id, "judgment", "opportunity_permanent_skip")
		return
	if bool(player.skipped_phases.get("judgment", false)):
		_run_phase_notification("phaseJudgeSkipped", player_id, {"turn_number":state.turn_number}, Callable(self, "_continue_turn_after_judgment").bind(player_id))
		return
	_begin_phase_lifecycle("phaseJudge", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_process_judgment_area").bind(player_id), Callable(self, "_continue_turn_after_judgment").bind(player_id))


## 从判定阶段结束处继续当前回合；异步无懈与濒死选择完成后也统一回到该入口。
func _continue_turn_after_judgment(player_id: int) -> void:
	if state == null or state.game_over or has_pending_card_choice() or state.current_player_id != player_id or state.current_phase != "judgment":
		return
	# 当前回合玩家；判定伤害可能使其死亡，必须在摸牌前重新读取存活状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	if _started_phase_lifecycles.has("%d:phaseJudge" % player_id):
		_finish_phase_lifecycle("phaseJudge", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_continue_turn_after_judgment").bind(player_id))
		return
	_schedule_phase_transition(player_id, "judgment", Callable(self, "_enter_draw_phase").bind(player_id))


## 进入摸牌阶段并完成本阶段主体；结算结束后保留当前画面，再按游戏速度进入出牌阶段。
func _enter_draw_phase(player_id: int, change_completed: bool = false) -> void:
	# 当前回合玩家；判定与阶段间隔期间都可能死亡，摸牌前必须重新读取存活状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	if _is_main_phase_converted_to_play(player_id, "draw"):
		_start_converted_main_phase_as_play(player_id, "draw", "play")
		return
	# 前一实际阶段；普通流程为judgment，阶段转换流程可能保持为play，事件必须反映真实公开阶段。
	var previous_phase: String = state.current_phase
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"draw"}, _current_turn_event_id, Callable(self, "_enter_draw_phase").bind(player_id, true))
		return
	state.current_phase = "draw"
	state.phase_index = 2
	# 本阶段基础摸牌数；2v2 一号位的首个回合（全场 turn_number==1）只摸 1 张，其余默认 2。
	var base_draw_count: int = _get_phase_draw_base_count(player_id)
	_record_runtime_event("phaseDraw", "phase", {"player_id":player_id, "base_draw_count":base_draw_count}, {}, _current_turn_event_id)
	if bool(player.skipped_phases.get("draw", false)):
		add_log("%s跳过摸牌阶段。" % format_player_state_log_name(player))
		_run_phase_notification("phaseDrawSkipped", player_id, {"turn_number":state.turn_number}, Callable(self, "_after_draw_phase").bind(player_id))
		return
	_begin_phase_lifecycle("phaseDraw", player_id, {"draw_count":base_draw_count, "turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_continue_turn_after_draw_phase_begin").bind(player_id), Callable(self, "_after_draw_phase").bind(player_id))


## 完成摸牌阶段主体与结束时机；Begin或摸牌触发中的选择恢复后均从此入口继续且只摸一次。
func _continue_turn_after_draw_phase_begin(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "draw":
		return
	# 摸牌阶段的数量窗口和主体共享同一服务，最终数量回读后只摸一次。
	var phase_service: RefCounted = PHASE_LIFECYCLE_SERVICE_SCRIPT.new(self)
	phase_service.draw_phase(player_id, Callable(self, "_after_draw_phase").bind(player_id))


## 摸牌阶段完整结束或跳过后安排唯一的出牌阶段后继。
func _after_draw_phase(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "draw":
		return
	# 当前角色；所有前置、摸牌和结束技能完成后复核，死亡不能继续获得出牌阶段。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	_schedule_phase_transition(player_id, "draw", Callable(self, "_enter_play_phase").bind(player_id))


## 标准、转换和额外出牌阶段共用主体入口；Begin完成后才建立操作请求。
func _resume_play_phase_body(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play" or not _is_phase_lifecycle_body_active("phaseUse", player_id):
		return
	_begin_play_choice(player_id)
	_emit_state()
	if ai_coordinator.is_ai_controlled(player_id):
		_schedule_ai_action()


## 发布单个阶段通知并等待其子内容；调用方不再根据是否存在选牌猜测事件是否完成。
func _run_phase_notification(timing_name: String, player_id: int, event_data: Dictionary, on_completed: Callable) -> void:
	# 两步通知内容；回调只在本局持有，不写入上下文和快照。
	var steps: Array[Callable] = [
		func(sequence: RuleStepSequence) -> void: emit_sequence_timing(sequence, timing_name, player_id, player_id, player_id, event_data, _current_turn_event_id),
		func(_sequence: RuleStepSequence) -> void:
			if on_completed.is_valid():
				on_completed.call(),
	]
	run_rule_sequence(steps)


## 把一个原主要阶段直接作为普通出牌阶段执行；结束后进入指定原阶段后继，不产生extra_phase标记或跳过时机。
func _start_converted_main_phase_as_play(player_id: int, original_phase: String, return_point: String, change_completed: bool = false) -> void:
	# 转换阶段角色；阶段交界死亡或离场时不再建立新的出牌窗口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	# 前一实际阶段；连续转换会形成play到play的阶段切换，但仍会完整结束并重新开始独立phaseUse生命周期。
	var previous_phase: String = state.current_phase
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"play", "transformed_from_phase":original_phase}, _current_turn_event_id, Callable(self, "_start_converted_main_phase_as_play").bind(player_id, original_phase, return_point, true))
		return
	state.current_phase = "play"
	state.phase_index = 3
	# 每个转换后的出牌阶段都是新的阶段，必须重新计算阶段限次与【杀】基础次数。
	player.slash_count = 0
	player.play_phase_card_use_history.clear()
	player.play_phase_card_use_limit_exempt_history.clear()
	if reincarnation_skill_service != null:
		reincarnation_skill_service.on_play_phase_started(player_id)
	_active_converted_play_phase_context = {"player_id":player_id, "original_phase":original_phase, "return_point":return_point}
	# 运行时事件明确记录阶段转换来源；extra_phase保持缺失，日志与监听者不会把它误认作额外阶段。
	var phase_event_data: Dictionary = {"player_id":player_id, "transformed_from_phase":original_phase}
	_record_runtime_event("phaseUse", "phase", phase_event_data, {}, _current_turn_event_id)
	_begin_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number, "transformed_from_phase":original_phase}, _current_turn_event_id, Callable(self, "_resume_play_phase_body").bind(player_id), Callable(self, "_end_play_phase").bind(player_id, false))


## 进入出牌阶段并创建统一 chooseToUse 请求；普通阶段与额外阶段分别维护独立次数历史。
func _enter_play_phase(player_id: int, change_completed: bool = false) -> void:
	# 当前回合玩家；流程间隔到期时再次校验，避免已离场角色获得可操作窗口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		if player != null and player.out_of_game:
			_advance_after_current_player_out_of_game(player_id)
		else:
			_advance_after_current_player_death(player_id)
		return
	# 前一实际阶段；摸牌阶段被转换为出牌阶段时这里会形成play到play的独立阶段切换。
	var previous_phase: String = state.current_phase
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"play"}, _current_turn_event_id, Callable(self, "_enter_play_phase").bind(player_id, true))
		return
	state.current_phase = "play"
	state.phase_index = 3
	# 普通出牌阶段拥有独立次数历史；本回合此前由其他流程记录的牌不会占用本阶段【杀】次数。
	player.slash_count = 0
	player.play_phase_card_use_history.clear()
	player.play_phase_card_use_limit_exempt_history.clear()
	if reincarnation_skill_service != null:
		reincarnation_skill_service.on_play_phase_started(player_id)
	_record_runtime_event("phaseUse", "phase", {"player_id":player_id}, {}, _current_turn_event_id)
	if bool(player.skipped_phases.get("play", false)):
		add_log("%s跳过出牌阶段。" % format_player_state_log_name(player))
		_run_phase_notification("phaseUseSkipped", player_id, {"turn_number":state.turn_number}, Callable(self, "_end_play_phase").bind(player_id, false, true))
		return
	_begin_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_resume_play_phase_body").bind(player_id), Callable(self, "_end_play_phase").bind(player_id, false))


## 在延迟选择完成后恢复被暂停的回合阶段；当前仅判定阶段允许在阶段主体中插入异步选择。
func _resume_interrupted_turn_flow() -> void:
	if state == null or state.game_over or has_pending_card_choice() or has_pending_judgment_request():
		return
	# 多步技能的表现间隔仍属于原规则结算；到期回调会显式恢复管线，期间不得提前推进阶段或下一回合。
	if game_flow_pacer != null and game_flow_pacer.has_pending_skill_interval():
		return
	# 已经登记阶段切换时当前阶段主体与后继均已确定；重复恢复会用同一业务键覆盖原任务，导致额外阶段被普通后继吞掉。
	if game_flow_pacer != null and game_flow_pacer.has_pending("phase_transition"):
		return
	# 当前被濒死救援等嵌套选择暂停的逐目标卡牌；嵌套流程结束后先完成原目标，再恢复后续目标而不是提前开放出牌。
	for parent_card_uid_variant: Variant in _active_card_resolutions.keys():
		# 原卡牌实体 UID；同一时刻只有最内层一张活动牌会等待没有父 UID 的公共救援选择。
		var parent_card_uid: int = int(parent_card_uid_variant)
		# 当前活动上下文；只有确实开始过目标的结算才由此兼容入口推进。
		var resolution_context: Dictionary = _active_card_resolutions[parent_card_uid] as Dictionary
		if int(resolution_context.get("current_target_id", -1)) >= 0:
			_complete_active_card_target(parent_card_uid)
			return
	# 当前回合玩家；异步救援结束后若其已经死亡，必须先转交回合，不能停留在失效的出牌阶段。
	var current_player: PlayerState = state.get_player(state.current_player_id)
	if current_player != null and (not current_player.alive or current_player.out_of_game):
		if current_player.out_of_game:
			_advance_after_current_player_out_of_game(current_player.player_id)
		else:
			_advance_after_current_player_death(current_player.player_id)
		return
	if state.current_phase == "discard":
		_continue_turn_after_discard_phase_begin(state.current_player_id)
		return
	if state.current_phase != "judgment":
		return
	# 当前回合玩家 ID；所有判定区剩余牌和后续摸牌、出牌都归属于该角色。
	var player_id: int = state.current_player_id
	_judgment_resume_needs_result_pause = true
	_process_judgment_area(player_id)


## 登记一段需要等待当前嵌套选择与触发续列结束后继续的技能结算；重复上下文按队列顺序分别执行。
func defer_skill_settlement(skill_owner_id: int, skill_id: String, context: Dictionary) -> bool:
	# 当前登记技能；必须仍属于创建该后续步骤的同一武将代次。
	var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id) if state != null and not state.game_over else null
	# 调用方保存的武将代次；缺失时使用当前实例代次兼容旧内容入口。
	var skill_character_generation: int = int(context.get("skill_character_generation", skill.get_bound_character_generation() if skill != null else -1))
	if state == null or state.game_over or skill_owner_id < 0 or skill_id.is_empty() or skill == null or not skill.matches_character_generation(skill_character_generation) or not skill.can_use_effect(bool(context.get("locked_skill_segment", false))):
		return false
	# 待保存上下文；深复制确保内容脚本后续改动原字典不会更改已排队步骤。
	var settlement_context: Dictionary = context.duplicate(true)
	# 当前续结算的语义键；持有者、技能、武将代次与排序JSON共同区分真实业务步骤。
	var settlement_key: String = _build_skill_settlement_key(skill_owner_id, skill_id, skill_character_generation, settlement_context)
	# 子步骤继承当前因果链访问记录；非continue_settlement中的独立登记从空记录开始。
	var settlement_visits: Dictionary = _active_skill_settlement_visits.duplicate(true) if not _active_skill_settlement_key.is_empty() else {}
	# 当前语义键在同一因果链中的新访问次数；独立的相同触发各自从1起算。
	var repeated_visit_count: int = int(settlement_visits.get(settlement_key, 0)) + 1
	settlement_visits[settlement_key] = repeated_visit_count
	# 当前新步骤所在因果链深度；子步骤在正在执行的父步骤基础上加1。
	var chain_step_count: int = _active_skill_settlement_chain_steps + 1 if not _active_skill_settlement_key.is_empty() else 1
	if repeated_visit_count > maxi(max_repeated_skill_settlement_steps, 1):
		_record_settlement_fault("skill_settlement_repeat_limit", {
			"skill_owner_id":skill_owner_id,
			"skill_id":skill_id,
			"skill_character_generation":skill_character_generation,
			"settlement_key":settlement_key,
			"repeat_count":repeated_visit_count,
			"chain_step_count":chain_step_count,
		})
		return false
	if chain_step_count > maxi(max_skill_settlement_chain_steps, 1):
		_record_settlement_fault("skill_settlement_chain_limit", {
			"skill_owner_id":skill_owner_id,
			"skill_id":skill_id,
			"skill_character_generation":skill_character_generation,
			"settlement_key":settlement_key,
			"repeat_count":repeated_visit_count,
			"chain_step_count":chain_step_count,
		})
		return false
	# 本条续结算的稳定编号；日志和回归可用它区分完全相同的独立触发。
	var settlement_id: int = _next_skill_settlement_id
	_next_skill_settlement_id += 1
	_deferred_skill_settlements.append({
		"settlement_id":settlement_id,
		"skill_owner_id":skill_owner_id,
		"skill_id":skill_id,
		"skill_character_generation":skill_character_generation,
		"context":settlement_context,
		"settlement_key":settlement_key,
		"settlement_visits":settlement_visits,
		"chain_step_count":chain_step_count,
	})
	# 同步入口忘记显式重驱时，唯一延后唤醒会补齐结算；已在管线内时当前while会自然取下一项。
	if not _settlement_pipeline_running and not has_pending_card_choice():
		_schedule_settlement_pipeline_resume()
	return true


## 在没有活动选择时依次恢复技能结算；恢复函数再次创建选择时立即停下，下一次提交后继续同一队列。
## 每次只恢复一项并保留原登记顺序；返回true表示确实消费了一条记录，包括已失效的过期技能。
func _resume_deferred_skill_settlements(settlement_index: int = 0) -> bool:
	if state == null or state.game_over or has_pending_card_choice() or _deferred_skill_settlements.is_empty():
		return false
	# 当前结算项；先移出队列，技能需要再次等待时会显式登记新的后续上下文。
	# 当前最早登记的技能后续；同层技能的“然后”效果保持原有先到先结算规则。
	var settlement: Dictionary = _deferred_skill_settlements[settlement_index] as Dictionary
	_deferred_skill_settlements.remove_at(settlement_index)
	# 技能持有者与稳定ID；等待期间失去技能时安全跳过旧结算，不调用失效对象。
	var skill_owner_id: int = int(settlement.get("skill_owner_id", -1))
	# 当前技能实例；每局每名角色唯一，重新开局已清空整个结算队列。
	var skill: SkillDefinition = get_skill_instance(skill_owner_id, str(settlement.get("skill_id", "")))
	# 技能结算上下文；半锁定技后段可显式携带locked_skill_segment，普通异步技能在失效期间不再恢复。
	var settlement_context: Dictionary = (settlement.get("context", {}) as Dictionary).duplicate(true)
	if skill != null and skill.matches_character_generation(int(settlement.get("skill_character_generation", -1))) and skill.can_use_effect(bool(settlement_context.get("locked_skill_segment", false))):
		_active_skill_settlement_key = str(settlement.get("settlement_key", _build_skill_settlement_key(skill_owner_id, str(settlement.get("skill_id", "")), int(settlement.get("skill_character_generation", -1)), settlement_context)))
		# 旧队列记录的默认访问表；只把当前语义键记为首次访问，不使用字面键替代动态值。
		var default_settlement_visits: Dictionary = {}
		default_settlement_visits[_active_skill_settlement_key] = 1
		_active_skill_settlement_visits = (settlement.get("settlement_visits", default_settlement_visits) as Dictionary).duplicate(true)
		_active_skill_settlement_chain_steps = maxi(int(settlement.get("chain_step_count", 1)), 1)
		# 回调前的故障计数；若回调中的子步骤已因熔断被拒绝，不再将false重复记录为未识别上下文。
		var fault_count_before_callback: int = _settlement_fault_count
		# 技能是否识别并处理了该续结算上下文；false且未发生子步熔断表示内容约定错误。
		var handled: bool = bool(skill.continue_settlement(settlement_context))
		_active_skill_settlement_key = ""
		_active_skill_settlement_visits.clear()
		_active_skill_settlement_chain_steps = 0
		if not handled and _settlement_fault_count == fault_count_before_callback:
			_record_settlement_fault("skill_settlement_unhandled_context", {
				"settlement_id":int(settlement.get("settlement_id", -1)),
				"skill_owner_id":skill_owner_id,
				"skill_id":str(settlement.get("skill_id", "")),
				"skill_character_generation":int(settlement.get("skill_character_generation", -1)),
				"settlement_key":str(settlement.get("settlement_key", "")),
			})
	return true


## 构建技能续结算的稳定语义键；JSON默认排序字典键，不受调用方插入顺序影响。
func _build_skill_settlement_key(skill_owner_id: int, skill_id: String, skill_character_generation: int, context: Dictionary) -> String:
	# 上下文的标准JSON快照；续结算契约只允许基础值、数组与字典，因此可安全用于循环检测。
	var serialized_context: String = JSON.stringify(context)
	return "%d:%s:%d:%s" % [skill_owner_id, skill_id, skill_character_generation, serialized_context]


## 登记被嵌套选择中断的通用规则后半段；上下文必须只包含基础值、数组和字典。
func defer_after_settlement(continuation_type: String, context: Dictionary) -> void:
	# 当前合法续接；沿用统一类型与预算校验，仅把模式交接移到当前栈之后。
	var continuation_id: int = _defer_rule_continuation(continuation_type, context)
	if continuation_id >= 0:
		_rule_continuations.move_after_current(continuation_id)


## 建立受预算保护的规则后续，默认按子内容后进先出执行。
func _defer_rule_continuation(continuation_type: String, context: Dictionary) -> int:
	if not RULE_CONTINUATION_TYPES.has(continuation_type):
		_record_settlement_fault("unknown_rule_continuation_type", {"continuation_type":continuation_type})
		return -1
	# 当前续接语义键；类型与排序JSON共同区分父流程的具体恢复步骤。
	var continuation_key: String = _build_rule_continuation_key(continuation_type, context)
	# 子续接访问表；只有在正在恢复的父续接回调中登记时才继承。
	var continuation_visits: Dictionary = _active_rule_continuation_visits.duplicate(true) if not _active_rule_continuation_key.is_empty() else {}
	# 当前语义键在同一续接因果链中的新访问次数；独立续接从1起算。
	var repeated_visit_count: int = int(continuation_visits.get(continuation_key, 0)) + 1
	continuation_visits[continuation_key] = repeated_visit_count
	# 当前子续接的因果链步数；父回调外的独立登记为1。
	var chain_step_count: int = _active_rule_continuation_chain_steps + 1 if not _active_rule_continuation_key.is_empty() else 1
	if repeated_visit_count > maxi(max_repeated_rule_continuation_steps, 1):
		_record_settlement_fault("rule_continuation_repeat_limit", {
			"continuation_type":continuation_type,
			"continuation_key":continuation_key,
			"repeat_count":repeated_visit_count,
			"chain_step_count":chain_step_count,
		})
		return -1
	if chain_step_count > maxi(max_rule_continuation_chain_steps, 1):
		_record_settlement_fault("rule_continuation_chain_limit", {
			"continuation_type":continuation_type,
			"continuation_key":continuation_key,
			"repeat_count":repeated_visit_count,
			"chain_step_count":chain_step_count,
		})
		return -1
	# 续接调度元数据；RuleContinuationQueue只负责深复制保存，不解释其中任何计数。
	var scheduler_metadata: Dictionary = {
		"continuation_key":continuation_key,
		"continuation_visits":continuation_visits,
		"chain_step_count":chain_step_count,
	}
	# 新规则续接稳定ID；负数表示数据队列拒绝该记录。
	var continuation_id: int = _rule_continuations.push(continuation_type, context, scheduler_metadata)
	if continuation_id >= 0 and not _settlement_pipeline_running and not has_pending_card_choice():
		_schedule_settlement_pipeline_resume()
	return continuation_id


## 构建通用规则续接的稳定语义键；同类型同上下文在单条因果链中共享重复计数。
func _build_rule_continuation_key(continuation_type: String, context: Dictionary) -> String:
	# 续接上下文的标准JSON快照；契约禁止运行时对象，因此可直接用于语义键。
	var serialized_context: String = JSON.stringify(context)
	return "%s:%s" % [continuation_type, serialized_context]


## 为机缘效果登记嵌套选择后的稳定恢复点；上下文由机缘组件自身保存，通用栈只记录恢复类型。
func defer_opportunity_resolution() -> bool:
	# 新续接记录ID；负数表示队列拒绝异常上下文。
	var continuation_id: int = _defer_rule_continuation("opportunity_resolution", {})
	if continuation_id >= 0 and not has_pending_card_choice():
		_schedule_settlement_pipeline_resume()
	return continuation_id >= 0


## 为阿哈时刻登记嵌套结算后的稳定恢复点；上下文由阿哈时刻组件自身保存，通用栈只记录恢复类型。
func defer_ahha_moment_resolution() -> bool:
	# 新续接记录ID；负数表示队列拒绝异常上下文。
	var continuation_id: int = _defer_rule_continuation("ahha_moment_resolution", {})
	if continuation_id >= 0 and not has_pending_card_choice():
		_schedule_settlement_pipeline_resume()
	return continuation_id >= 0


## 转发欢愉技的演出结束回报；内容文件只调用技能基类入口，由基类经本方法回到阿哈时刻队列。
func finish_joy_skill_performance(player_id: int, skill_id: String) -> bool:
	if ahha_moment_system == null:
		return false
	return ahha_moment_system.finish_joy_skill_performance(player_id, skill_id)


## 在机缘即将执行可能产生嵌套选择的动作前预登记外层恢复点；返回ID供同步完成时撤销。
func begin_opportunity_resolution_guard() -> int:
	return _defer_rule_continuation("opportunity_resolution", {})


## 撤销同步完成且未产生屏障的机缘外层恢复点；只接受仍在续接栈中的稳定ID。
func cancel_opportunity_resolution_guard(continuation_id: int) -> bool:
	return _rule_continuations.remove(continuation_id)


## 供【杀】共享组件登记武器效果后的稳定恢复阶段；具体装备只声明阶段，不直接访问通用续接栈。
func defer_slash_continuation(resume_stage: String, context: Dictionary) -> bool:
	if resume_stage not in ["after_weapon_targeted", "after_weapon_dodged", "after_sha_damage"]:
		return false
	return _defer_rule_continuation("slash_flow", {"resume_stage":resume_stage, "rule_context":context.duplicate(true)}) >= 0


## 在嵌套技能与移动触发结束后恢复【杀】武器阶段；装备定义不保留共享组件对象引用。
func _continue_slash_flow_after_barrier(continuation_context: Dictionary) -> void:
	# 【杀】共享流程组件；使用当前效果调度器与状态重新构造，避免续接栈保存运行时对象。
	var slash_effect: SlashCardEffect = SlashCardEffect.new(effect_resolver)
	# 原武器阶段规则上下文；稳定UID与目标信息由共享组件恢复时重新校验。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	# 待恢复阶段；只接受公开登记入口允许的两个武器后续步骤。
	var resume_stage: String = str(continuation_context.get("resume_stage", ""))
	if resume_stage == "after_weapon_targeted":
		slash_effect.continue_after_weapon_targeted(rule_context)
	elif resume_stage == "after_weapon_dodged":
		slash_effect.continue_after_weapon_dodged(rule_context)
	elif resume_stage == "after_sha_damage":
		slash_effect.continue_after_sha_damage(rule_context)


## 只等待本序列内部新建的判定；judgeBefore技能自身必须先于等待它的外层判定恢复。
func _sequence_waits_for_child_judgment(sequence: RuleStepSequence) -> bool:
	return has_pending_judgment_request() and int(_pending_judgment_request.get("request_id", -1)) != sequence.enclosing_judgment_request_id


## 步骤式内容通过预登记续接持有父结算位置；具体技能只编写顺序步骤，不复制暂停与恢复分支。
func run_rule_sequence(steps: Array[Callable], context: Dictionary = {}) -> int:
	if state == null or state.game_over or steps.is_empty():
		return -1
	# 当前内容对象；只在本局持有Callable，不存入RuleContinuationQueue或快照。
	var sequence: RuleStepSequence = RuleStepSequence.new(steps, context)
	sequence.sequence_id = _next_rule_sequence_id
	sequence.enclosing_judgment_request_id = int(_pending_judgment_request.get("request_id", -1))
	sequence.enclosing_play_phase_id = int(_active_independent_play_phase.get("phase_id", -1))
	sequence.enclosing_discard_phase_id = int(_active_extra_discard_phase.get("phase_id", -1))
	_next_rule_sequence_id += 1
	_rule_sequences[sequence.sequence_id] = sequence
	_advance_rule_sequence(sequence.sequence_id)
	return sequence.sequence_id


## 推进一个序列至首个真实等待边界；每步之前登记父恢复点，子续接自然排在其上方。
func _advance_rule_sequence(sequence_id: int) -> void:
	_rule_sequence_execution_depth += 1
	_run_rule_sequence_steps(sequence_id)
	_rule_sequence_execution_depth = maxi(_rule_sequence_execution_depth - 1, 0)


## 执行步骤主体；外层深度包装确保同步选择、触发回调和内容续接只有一个消费者。
func _run_rule_sequence_steps(sequence_id: int) -> void:
	# 当前序列；终局、重开和局部取消都可能使身份失效。
	var sequence: RuleStepSequence = _rule_sequences.get(sequence_id) as RuleStepSequence
	if sequence == null:
		return
	# 本轮执行步数；采用统一管线预算，合法长序列跨帧而不自旋。
	var executed_steps: int = 0
	while state != null and not state.game_over and executed_steps < maxi(max_settlement_steps_per_pass, 1):
		if not _is_rule_sequence_owner_valid(sequence):
			sequence.finish()
		if sequence.finished:
			_rule_sequences.erase(sequence_id)
			return
		# 父恢复记录；先登记再执行，嵌套伤害或技能产生的恢复点必须处于父记录上方。
		var continuation_id: int = _defer_rule_continuation("rule_sequence", {"sequence_id":sequence_id, "step":sequence.step})
		if continuation_id < 0:
			_rule_sequences.erase(sequence_id)
			return
		sequence.skill_settlement_watermark = _next_skill_settlement_id
		if not sequence.execute_next():
			_record_settlement_fault("rule_sequence_invalid_step", {"sequence_id":sequence_id, "step":sequence.step})
		executed_steps += 1
		if state == null or state.game_over or not _rule_sequences.has(sequence_id):
			_rule_continuations.remove(continuation_id)
			_rule_sequences.erase(sequence_id)
			return
		# 已无剩余内容时释放空游标；本步创建的子选择、触发和旧规则续接仍由各自所有权独立等待。
		if sequence.finished:
			_rule_continuations.remove(continuation_id)
			_rule_sequences.erase(sequence_id)
			return
		if _has_nested_settlement_barrier() or _sequence_waits_for_child_judgment(sequence) or _sequence_waits_for_child_phase(sequence) or (game_flow_pacer != null and game_flow_pacer.has_pending_skill_interval()):
			return
		if sequence.waiting_event != null and trigger_manager != null and trigger_manager.is_dispatch_deferred(sequence.waiting_event):
			return
		if int(_rule_continuations.peek().get("continuation_id", -1)) != continuation_id or _find_sequence_child_settlement(sequence) >= 0:
			return
		_rule_continuations.remove(continuation_id)
	# 预算结束只保留下一步骤，不提前完成父操作。
	if _rule_sequences.has(sequence_id):
		_defer_rule_continuation("rule_sequence", {"sequence_id":sequence_id, "step":sequence.step})


## 校验技能内容仍属于原武将实例；普通规则无skill_id时不附加技能有效性限制。
func _is_rule_sequence_owner_valid(sequence: RuleStepSequence) -> bool:
	# 可选技能身份；规则层伤害等序列无需绑定技能。
	var skill_id: String = str(sequence.context.get("skill_id", ""))
	if skill_id.is_empty():
		return true
	# 原技能实例；换将、卸载或失效后不得继续旧技能的剩余步骤。
	var skill: SkillDefinition = get_skill_instance(int(sequence.context.get("skill_owner_id", -1)), skill_id)
	return skill != null and skill.matches_character_generation(int(sequence.context.get("skill_character_generation", -1))) and skill.can_use_effect(bool(sequence.context.get("locked_skill_segment", false)))


## 定位本步骤创建的技能后续；不让父规则的下一步越过子技能的“然后”。
func _find_sequence_child_settlement(sequence: RuleStepSequence) -> int:
	# 待恢复技能下标；原有队列顺序不变，仅提前处理属于当前子步骤的记录。
	for settlement_index: int in range(_deferred_skill_settlements.size()):
		if int(_deferred_skill_settlements[settlement_index].get("settlement_id", -1)) >= sequence.skill_settlement_watermark:
			return settlement_index
	return -1


## 当前栈顶为已完成自身触发窗口的序列时，先完成该子内容再恢复外层触发队列。
func _try_resume_ready_rule_sequence() -> bool:
	if not _rule_continuations.has_pending() or not _queued_equipment_triggers.is_empty():
		return false
	# 最内层恢复记录；只接管步骤式内容，不改变旧规则续接之间的次序。
	var continuation: Dictionary = _rule_continuations.peek()
	if str(continuation.get("continuation_type", "")) != "rule_sequence":
		return false
	# 待恢复内容；旧局失效记录由正常出栈路径清除。
	var sequence: RuleStepSequence = _rule_sequences.get(int((continuation.get("context", {}) as Dictionary).get("sequence_id", -1))) as RuleStepSequence
	if sequence != null:
		if _sequence_waits_for_child_judgment(sequence) or _sequence_waits_for_child_phase(sequence):
			return false
		if sequence.waiting_event != null and trigger_manager != null and trigger_manager.is_dispatch_deferred(sequence.waiting_event):
			return false
		# 子技能后续优先于本序列下一步骤；每次只执行一项，再由管线检查新选择。
		var child_settlement_index: int = _find_sequence_child_settlement(sequence)
		if child_settlement_index >= 0:
			_resume_deferred_skill_settlements(child_settlement_index)
			return true
	_resume_next_rule_continuation()
	return true


## 返回当前结算是否存在必须优先完成的选择或装备触发；父响应读取结果前必须等待该屏障清空。
func _has_nested_settlement_barrier() -> bool:
	return has_pending_card_choice() or not _queued_equipment_triggers.is_empty()


## 返回机缘等独立规则组件是否必须等待当前嵌套选择或装备触发完成；只读公开包装不暴露内部队列。
func has_nested_settlement_barrier() -> bool:
	return _has_nested_settlement_barrier()


## 恢复一条最内层通用规则后半段；每次只执行一项，让统一管线重新检查期间产生的新触发。
func _resume_next_rule_continuation() -> void:
	if state == null or state.game_over or has_pending_card_choice() or not _rule_continuations.has_pending():
		return
	# 当前最内层续接记录；记录已经从栈中移除，若再次中断会由对应处理函数登记新的后续步骤。
	var continuation: Dictionary = _rule_continuations.pop()
	# 续接稳定类型；控制器只识别通用规则阶段，不按具体卡牌或技能名称分支。
	var continuation_type: String = str(continuation.get("continuation_type", ""))
	# 续接可序列化上下文；处理函数获得深拷贝，不能修改栈内历史记录。
	var context: Dictionary = (continuation.get("context", {}) as Dictionary).duplicate(true)
	# 当前续接的调度元数据；旧记录缺失时从当前语义键首次访问开始。
	var scheduler_metadata: Dictionary = (continuation.get("scheduler_metadata", {}) as Dictionary).duplicate(true)
	_active_rule_continuation_key = str(scheduler_metadata.get("continuation_key", _build_rule_continuation_key(continuation_type, context)))
	# 旧续接默认访问表；动态语义键使用下标写入，子续接可正确继承。
	var default_continuation_visits: Dictionary = {}
	default_continuation_visits[_active_rule_continuation_key] = 1
	_active_rule_continuation_visits = (scheduler_metadata.get("continuation_visits", default_continuation_visits) as Dictionary).duplicate(true)
	_active_rule_continuation_chain_steps = maxi(int(scheduler_metadata.get("chain_step_count", 1)), 1)
	match continuation_type:
		"rule_sequence":
			_advance_rule_sequence(int(context.get("sequence_id", -1)))
		"skill_response":
			_continue_skill_response_after_barrier(context)
		"card_response":
			_continue_card_response_after_barrier(context)
		"equipment_response":
			_continue_equipment_response_after_barrier(context)
		"trick_negation_response":
			_continue_trick_negation_after_barrier(context)
		"simultaneous_negation_response":
			_continue_simultaneous_negation_after_barrier(context)
		"slash_flow":
			_continue_slash_flow_after_barrier(context)
		"recast_draw":
			draw(int(context.get("player_id", -1)), int(context.get("count", 1)))
		"current_player_death":
			if state.turn_number == int(context.get("turn_number", -1)):
				_advance_after_current_player_death(int(context.get("player_id", -1)), int(context.get("generation", -1)))
		"round_end_restore":
			_continue_round_end_after_restore(int(context.get("finished_player_id", -1)))
		"conquest_enemy_defeat":
			_finish_conquest_enemy_defeat(context)
		"conquest_enemy_replacement":
			_begin_conquest_enemy_replacement(context)
		"opportunity_resolution":
			if opportunity_system != null:
				opportunity_system.continue_after_barrier()
		"ahha_moment_resolution":
			if ahha_moment_system != null:
				ahha_moment_system.continue_after_barrier()
		_:
			_record_settlement_fault("unknown_rule_continuation_type", {"continuation_type":continuation_type})
	_active_rule_continuation_key = ""
	_active_rule_continuation_visits.clear()
	_active_rule_continuation_chain_steps = 0


## 按触发、装备、规则后半段、技能后续的固定优先级排空当前结算，最后才恢复阶段或父牌游标。
func _resume_settlement_pipeline() -> void:
	# 技能回调内重新请求结算时不得递归进入同一管线；唯一延后唤醒会在当前调用栈退出后重试。
	if _settlement_pipeline_running:
		_schedule_settlement_pipeline_resume()
		return
	# 直接安全出口比已登记的空闲帧任务更早进入时，立即使旧任务代次失效，避免它在测试重置或下一业务状态中空跑。
	if _settlement_resume_scheduled:
		_invalidate_scheduled_settlement_resume()
	_settlement_pipeline_running = true
	_run_settlement_pipeline_pass()
	_settlement_pipeline_running = false
	# 回合边界可能在本次管线入口之前被暂缓；只在最外层排空后重试，避免把中间阶段写成play_phase。
	if _rule_sequence_execution_depth == 0 and _pending_conquest_boundary_player_id >= 0 and _conquest_temporary_exit_requested:
		var boundary_player_id: int = _pending_conquest_boundary_player_id
		if _try_capture_conquest_temporary_exit(boundary_player_id):
			_pending_conquest_boundary_player_id = -1
		elif _conquest_temporary_exit_requested:
			_schedule_settlement_pipeline_resume()


## 执行一次有步数预算的结算排空；本函数只由防重入包装器调用，内部可按规则边界提前返回。
func _run_settlement_pipeline_pass() -> void:
	if state == null or state.game_over or _rule_sequence_execution_depth > 0:
		return
	# 换将过渡期唯一放行的续接：机缘效果嵌套选择结束后，栈顶的机缘续接必须弹出，否则换将完成回调永远不可达。
	# 其余旧回合续接（斩杀连锁、伤害尾部等）仍等待换将边界完成后按正常门控恢复，不在过渡期越界执行。
	# 阿哈时刻续接与机缘续接同一性质：它同样在等待嵌套结算结束，不放行会让回合开始流程永久停在换将边界。
	if _conquest_replacement_transition_active:
		# 过渡期可放行的续接类型；只包含回合开始前事件链上的两个组件，不含其他旧回合续接。
		var transition_resumable_types: Array[String] = ["opportunity_resolution", "ahha_moment_resolution"]
		if not has_pending_card_choice() and _rule_continuations.has_pending() and transition_resumable_types.has(str(_rule_continuations.peek().get("continuation_type", ""))):
			_resume_next_rule_continuation()
		return
	if has_pending_card_choice():
		return
	# 技能安排的可见结果停留仍是当前结算的一部分；回调完成后会重新调用本入口。
	if game_flow_pacer != null and game_flow_pacer.has_pending_skill_interval():
		return
	# 单次恢复保护计数；正常每轮都会移除至少一条队列记录，达到检查器上限时延后一帧继续而不推进父流程。
	var settlement_step_count: int = 0
	while state != null and not state.game_over and not has_pending_card_choice() and not _conquest_replacement_transition_active and (game_flow_pacer == null or not game_flow_pacer.has_pending_skill_interval()) and settlement_step_count < max_settlement_steps_per_pass:
		settlement_step_count += 1
		# 子序列已经完成自身时机时先恢复它，再回到触发该序列的外层时机剩余处理器。
		if _try_resume_ready_rule_sequence():
			continue
		# 栈顶父内容等待独立阶段时，只让该阶段自己的输入或子序列驱动；不能排空外层时机。
		if _top_sequence_waits_for_child_phase():
			return
		# 同一规则时机尚未询问的技能必须先完成，不能让原操作的后半段越过触发顺序。
		_resume_deferred_rule_timing_dispatches()
		if has_pending_card_choice() or state.game_over:
			return
		# 判定前时机属于创建它的技能直接子流程；完成最内层触发续列后必须先翻开判定牌，再恢复外层伤害或回合时机。
		if has_pending_judgment_request():
			_advance_pending_judgment_request()
			if has_pending_card_choice() or state.game_over:
				return
			continue
		# 尚有同一时机的其他技能时继续按座次询问；任何通用后半段都不能越过未完成的触发续列。
		if trigger_manager != null and trigger_manager.has_deferred_dispatches():
			continue
		# 响应完成后登记的装备触发属于响应子事件，优先于读取响应结果的父卡牌或濒死流程。
		if not _queued_equipment_triggers.is_empty():
			process_next_equipment_trigger()
			if has_pending_card_choice() or state.game_over:
				return
			continue
		# 通用规则续接使用统一后进先出栈，确保最内层被中断操作先恢复。
		if _rule_continuations.has_pending():
			# 当前最内层续接；过关斩将敌人退场与整层换将都是角色生命周期边界，必须让已经登记的技能“然后”步骤先结束。
			var next_rule_continuation: Dictionary = _rule_continuations.peek()
			# 触发续列刚在本轮完成时，仍须经过同一个子技能检查入口；不能直接弹出父序列跳过“然后”。
			if str(next_rule_continuation.get("continuation_type", "")) == "rule_sequence":
				if _try_resume_ready_rule_sequence():
					continue
				return
			if str(next_rule_continuation.get("continuation_type", "")) in ["conquest_enemy_defeat", "conquest_enemy_replacement"]:
				if not _deferred_skill_settlements.is_empty():
					_resume_deferred_skill_settlements()
					continue
				# 换将会全局暂停旧事件树；进入边界前必须先补齐最内层活动目标的End/After时机，避免击杀目标令【再现】等尾部技能被父牌游标跳过。
				if _complete_innermost_active_card_target_lifecycle():
					continue
			_resume_next_rule_continuation()
			continue
		# 技能自行声明的“然后”步骤保持登记顺序，每项之后重新检查触发、装备与通用规则续接。
		if not _deferred_skill_settlements.is_empty():
			_resume_deferred_skill_settlements()
			continue
		break
	# 达到单帧保护上限时仍有明确队列，下一帧只继续同一管线；未完成后续绝不交给阶段游标或父牌兼容入口。
	if settlement_step_count >= max_settlement_steps_per_pass and (not _queued_equipment_triggers.is_empty() or _rule_continuations.has_pending() or not _deferred_skill_settlements.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())):
		_schedule_settlement_pipeline_resume()
		return
	if state != null and not state.game_over and not has_pending_card_choice() and not has_pending_judgment_request() and not _conquest_replacement_transition_active and (game_flow_pacer == null or not game_flow_pacer.has_pending_skill_interval()):
		if state == null or state.game_over or has_pending_card_choice() or has_pending_judgment_request():
			return
		_resume_interrupted_turn_flow()
		# 阶段恢复可能刚刚完成额外弃牌阶段并暴露新的技能“然后”步骤；延后一帧再次排空，避免后续额外出牌阶段被嵌套询问吞掉。
		if not has_pending_card_choice() and (not _queued_equipment_triggers.is_empty() or _rule_continuations.has_pending() or not _deferred_skill_settlements.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())):
			_schedule_settlement_pipeline_resume()


## 完成当前最内层尚未收尾的逐目标卡牌生命周期；用于进入角色或模式边界前保证目标End/After时机不会被父事件推进吞掉。
func _complete_innermost_active_card_target_lifecycle() -> bool:
	# 最内层活动牌UID；默认-1表示没有已开始但尚未结束的目标生命周期。
	var selected_parent_card_uid: int = -1
	# 最内层CardUseEvent ID；事件ID单调递增，数值越大表示嵌套层级越靠内。
	var selected_card_use_event_id: int = -1
	for parent_card_uid_variant: Variant in _active_card_resolutions.keys():
		# 当前活动牌UID；相同事件ID时以实体UID作为稳定次级顺序。
		var parent_card_uid: int = int(parent_card_uid_variant)
		# 当前逐目标上下文；只有已经开始且尚未完成的目标需要补齐生命周期尾部。
		var resolution_context: Dictionary = _active_card_resolutions.get(parent_card_uid, {}) as Dictionary
		if int(resolution_context.get("current_target_id", -1)) < 0 or not bool(resolution_context.get("target_lifecycle_started", false)) or bool(resolution_context.get("target_lifecycle_finished", false)):
			continue
		# 当前父使用牌事件ID；兼容旧上下文缺省-1，并通过UID保证选择结果稳定。
		var card_use_event_id: int = int(resolution_context.get("card_use_event_id", -1))
		if card_use_event_id < selected_card_use_event_id or (card_use_event_id == selected_card_use_event_id and parent_card_uid <= selected_parent_card_uid):
			continue
		selected_parent_card_uid = parent_card_uid
		selected_card_use_event_id = card_use_event_id
	if selected_parent_card_uid < 0:
		return false
	_complete_active_card_target(selected_parent_card_uid)
	return true


## 派发一个标准阶段的 Before 与 Begin；任一时机取消或中立化时返回 false，由调用方决定跳过或终止阶段。
func _begin_phase_lifecycle(base_name: String, player_id: int, event_data: Dictionary, parent_event_id: int, on_started: Callable = Callable(), on_cancelled: Callable = Callable()) -> bool:
	# 生命周期内容服务；只返回同步开始状态，异步流程使用明确后继，不猜测当前公开阶段。
	var phase_service: RefCounted = PHASE_LIFECYCLE_SERVICE_SCRIPT.new(self)
	return phase_service.begin(base_name, player_id, event_data, parent_event_id, on_started, on_cancelled)


## 派发一个标准阶段的 End 与 After；目录没有对应后缀时自动跳过，不为引擎未定义的时机造名。
## 完成回调只在两个窗口全部子内容结束后调用，替代各阶段重复保存的结束游标。
func _finish_phase_lifecycle(base_name: String, player_id: int, event_data: Dictionary, parent_event_id: int, on_completed: Callable = Callable()) -> void:
	# 阶段收尾服务；同名活动实例只允许一个ending序列。
	var phase_service: RefCounted = PHASE_LIFECYCLE_SERVICE_SCRIPT.new(self)
	phase_service.complete(base_name, player_id, event_data, parent_event_id, on_completed)


## 返回指定阶段生命周期是否仍等待主体执行；End或After选择恢复时返回false，防止重复摸牌、弃牌或写入阶段日志。
func _is_phase_lifecycle_body_active(base_name: String, player_id: int) -> bool:
	# 阶段生命周期键；不存在表示阶段未成功开始或已经完整结束。
	var lifecycle_key: String = "%d:%s" % [player_id, base_name]
	if not _started_phase_lifecycles.has(lifecycle_key):
		return false
	# 当前生命周期上下文；旧布尔状态按body处理，保证规则测试与迁移期状态兼容。
	var lifecycle_variant: Variant = _started_phase_lifecycles.get(lifecycle_key)
	if lifecycle_variant is Dictionary:
		return str((lifecycle_variant as Dictionary).get("status", "body")) == "body"
	return true


## 处理玩家判定区的全部延时锦囊；每次只展示并结算一张，完整判定结束后才继续下一张。
func _process_judgment_area(player_id: int) -> void:
	if _judgment_flow_in_progress or state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "judgment":
		return
	_judgment_flow_token += 1
	# 本次判定流程令牌；换回合或重新开局会递增全局值，使已创建计时器只读退出。
	var flow_token: int = _judgment_flow_token
	_judgment_flow_in_progress = true
	_run_judgment_area_sequence(player_id, flow_token)


## 按进入判定区的顺序推进延时锦囊展示、无懈、判定与结果停留；异步选择出现时保留剩余数组等待统一阶段恢复入口继续。
func _run_judgment_area_sequence(player_id: int, flow_token: int) -> void:
	# 从响应选择恢复时的结果停留；上一张牌已经在恢复回调中完成效果，先等待再展示下一张。
	if _judgment_resume_needs_result_pause:
		_judgment_resume_needs_result_pause = false
		if delayed_judgment_result_pause_seconds > 0.0 and not state.match_id.is_empty():
			await get_tree().create_timer(delayed_judgment_result_pause_seconds, false).timeout
			if not _is_judgment_flow_valid(player_id, flow_token):
				return
	# 判定玩家状态；每轮重新读取判定区，确保闪电传递和插入移动不会让旧数组重复结算。
	var player: PlayerState = state.get_player(player_id)
	while player != null and player.alive and not state.game_over and not has_pending_card_choice() and not has_pending_judgment_request() and not player.judgment_area.is_empty():
		# 当前延时锦囊；始终取判定区数组首项，完整离区后下一项才会成为新的处理对象。
		var delayed_card: CardInstance = player.judgment_area.front()
		# 当前延时锦囊判定事件；展示、无懈与实际判定都关联本回合判定阶段，回放可以恢复严格顺序。
		var delayed_event_id: int = _record_runtime_event("delayedJudge", "judgment", {"player_id":player_id, "card_uid":delayed_card.uid, "card_id":delayed_card.definition_id}, {}, _current_turn_event_id)
		_emit_rule_timing("phaseJudge", player_id, player_id, player_id, {"card_uid":delayed_card.uid, "card_id":delayed_card.definition_id}, delayed_event_id)
		_ensure_card_movement()
		_move_card_with_timings(delayed_card, "processing", -1, "judge", delayed_event_id)
		# 延时锦囊展示；表现接管其可能发生的处理区到弃牌堆移动，闪电传递时由新区域移动释放所有权。
		_request_card_presentation(delayed_card, player_id, [], "delayedJudge", delayed_event_id, true)
		add_log("%s开始判定%s。" % [format_player_state_log_name(player), describe_card(delayed_card)])
		_emit_state()
		if delayed_judgment_preview_seconds > 0.0 and not state.match_id.is_empty():
			await get_tree().create_timer(delayed_judgment_preview_seconds, false).timeout
			if not _is_judgment_flow_valid(player_id, flow_token):
				return
		# 延时锦囊是否在生效前被无懈可击抵消；异步响应必须保留判定恢复标记。
		var negated: bool = resolve_trick_negation(-1, player_id, delayed_card.definition_id, {"delayed_judgment":true})
		if state.game_over or has_pending_card_choice() or has_pending_judgment_request():
			_judgment_flow_in_progress = false
			_judgment_resume_needs_result_pause = true
			return
		_resolve_delayed_judgment_card(player_id, delayed_card, negated)
		_emit_state()
		if state.game_over or has_pending_card_choice() or has_pending_judgment_request():
			_judgment_flow_in_progress = false
			_judgment_resume_needs_result_pause = true
			return
		if delayed_judgment_result_pause_seconds > 0.0 and not state.match_id.is_empty():
			await get_tree().create_timer(delayed_judgment_result_pause_seconds, false).timeout
			if not _is_judgment_flow_valid(player_id, flow_token):
				return
		player = state.get_player(player_id)
	_judgment_flow_in_progress = false
	if _is_judgment_flow_valid(player_id, flow_token):
		_continue_turn_after_judgment(player_id)


## 判断判定展示计时器是否仍属于当前回合；失效流程会自行退出且不能推进摸牌阶段。
func _is_judgment_flow_valid(player_id: int, flow_token: int) -> bool:
	return state != null and not state.game_over and flow_token == _judgment_flow_token and state.current_player_id == player_id and state.current_phase == "judgment"


## 结算一张已经进入处理区的延时锦囊；同步判定与异步无懈恢复共用该唯一入口。
func _resolve_delayed_judgment_card(player_id: int, delayed_card: CardInstance, negated: bool) -> void:
	if delayed_card == null or state == null or state.game_over or not state.processing_area.has(delayed_card):
		return
	# 判定玩家状态；无效或死亡角色不再应用跳过标记，原延时锦囊仍正常离开处理区。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_move_to_discard(delayed_card)
		return
	# 当前延时锦囊源码；判定条件、伤害与传递规则全部由对应卡牌文件提供。
	var definition: CardDefinition = GameDatabase.get_card_definition(delayed_card.definition_id)
	if definition == null:
		_move_to_discard(delayed_card)
		return
	definition.resolve_delayed_judgment(self, player_id, delayed_card, negated)


## 将完成判定且不再传递的延时锦囊移入弃牌堆；卡牌文件通过该公开端口结束自身判定流程。
func discard_delayed_card(card: CardInstance) -> void:
	_move_to_discard(card)


## 将一张可传递延时锦囊移动给下一名判定区中没有同定义牌的存活角色。
func pass_delayed_card(from_player_id: int, delayed_card: CardInstance) -> void:
	_pass_delayed_card(from_player_id, delayed_card)


## 记录指定玩家跳过当前回合的某阶段；延时锦囊与后续技能共用该稳定规则操作。
func mark_player_phase_skipped(player_id: int, phase_name: String) -> void:
	# 需要跳过阶段的玩家；不存在或已经离场时不写入任何状态。
	var player: PlayerState = state.get_player(player_id)
	if player != null and player.alive and not phase_name.is_empty():
		player.skipped_phases[phase_name] = true


## 将可传递延时锦囊移至下一名合法角色；全场无其他合法目标时回到原角色。
func _pass_delayed_card(from_player_id: int, delayed_card: CardInstance) -> void:
	if delayed_card == null:
		return
	# 延时锦囊定义 ID；同一角色判定区不能放置第二张同定义牌。
	var delayed_definition_id: String = delayed_card.definition_id
	# 玩家可见牌名；通用传递日志从卡牌元数据读取，不硬编码具体延时锦囊。
	var delayed_name: String = str(GameDatabase.get_card(delayed_definition_id).get("original_name", delayed_definition_id))
	# 当前候选玩家；从原角色下家开始循环寻找。
	var candidate: PlayerState = state.get_next_alive_player(from_player_id)
	# 已检查角色数量；最多遍历全部存活角色一次。
	var checked_count: int = 0
	# 存活角色总数；用于限制循环。
	var alive_count: int = state.get_alive_players().size()
	while candidate != null and checked_count < alive_count:
		# 候选判定区是否已有同定义延时锦囊；重复时继续检查下一名角色。
		var has_same_delayed_card: bool = false
		for existing_delayed_card: CardInstance in candidate.judgment_area:
			if existing_delayed_card.definition_id == delayed_definition_id:
				has_same_delayed_card = true
				break
		if not candidate.judgment_area_abolished and not has_same_delayed_card:
			_ensure_card_movement()
			_move_card_with_timings(delayed_card, "judgment", candidate.player_id, "add_judge", state.current_event_id)
			add_log("【%s】移动至%s的判定区。" % [delayed_name, format_player_state_log_name(candidate)])
			return
		candidate = state.get_next_alive_player(candidate.player_id)
		checked_count += 1
	# 所有角色均不是合法目标时，延时锦囊回到原角色判定区，而不是进入弃牌堆。
	var original_player: PlayerState = state.get_player(from_player_id)
	if original_player != null and original_player.alive and not original_player.judgment_area_abolished:
		_ensure_card_movement()
		_move_card_with_timings(delayed_card, "judgment", original_player.player_id, "add_judge", state.current_event_id)
		add_log("没有其他合法目标，【%s】回到%s的判定区。" % [delayed_name, format_player_state_log_name(original_player)])
	else:
		_move_to_discard(delayed_card)


## 判断卡牌是否使用统一逐目标游标结算；装备、延时锦囊与五谷保留各自的整牌上下文。
func _uses_active_target_resolution(definition: Dictionary, target_ids: Array[int]) -> bool:
	# 卡牌文件声明的结算模式；per_target 逐目标创建 content，whole 一次读取完整目标数组。
	var resolution_mode: String = str(definition.get("resolution_mode", "per_target"))
	return not target_ids.is_empty() and resolution_mode == "per_target"


## 建立一张牌的逐目标结算上下文；目标游标在创建任何异步请求前写入，恢复时不会重复处理上一目标。
func _begin_active_card_resolution(card: CardInstance, actor_id: int, target_ids: Array[int], card_use_event_id: int = -1) -> void:
	# 当前卡牌定义；【杀】需要把酒加值、属性和无视防具状态保存为整张牌共享参数。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 活动结算上下文；target_index 指向下一名未开始结算的目标，current_target_id 表示正在等待响应的目标。
	var resolution_context: Dictionary = {
		"parent_card_uid":card.uid,
		"card_use_event_id":card_use_event_id,
		"actor_id":actor_id,
		"card_definition_id":card.definition_id,
		"target_ids":target_ids.duplicate(),
		"target_index":0,
		"current_target_id":-1,
		"virtual_storage":((_card_use_contexts.get(card.uid, {}) as Dictionary).get("virtual_storage", {}) as Dictionary).duplicate(true),
	}
	# 完整目标语义始终保留；普通牌无需读取，角色顺序敏感的卡牌可直接复用。
	resolution_context["effect_target_ids"] = target_ids.duplicate()
	# 当前卡牌源码；牌族共享参数由对应文件或共享组件写入，控制器不识别 effect_id。
	var source_definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if source_definition != null:
		source_definition.configure_resolution_context(self, card, actor_id, resolution_context)
		# 完整声明目标；角色语义辅助目标只在此写入共享上下文，后续目标时机继续只遍历实际结算目标。
		var requested_targets_context: Dictionary = _card_use_contexts.get(card.uid, {}) as Dictionary
		source_definition.configure_requested_target_context(self, card, actor_id, requested_targets_context.get("requested_target_ids", target_ids) as Array[int], resolution_context)
	_active_card_resolutions[card.uid] = resolution_context
	if source_definition != null and source_definition.on_resolution_started(self, card, actor_id, resolution_context):
		return
	# 真实 CardUseEvent 由父事件步骤安排逐目标 content；迁移期独立调用才继续使用栈外兼容游标。
	var card_use_context: Dictionary = _card_use_contexts.get(card.uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(card.uid)


## 从当前游标连续结算目标；任一响应或效果选择出现时立即暂停，恢复回调只完成当前目标后再进入下一名。
func _continue_active_card_resolution(parent_card_uid: int) -> void:
	while _active_card_resolutions.has(parent_card_uid) and not state.game_over and not has_pending_card_choice():
		# 原始处理区卡牌；离开处理区说明旧上下文已经失效，应停止而不能重新移动牌。
		var parent_card: CardInstance = _find_processing_card(parent_card_uid)
		if parent_card == null:
			_active_card_resolutions.erase(parent_card_uid)
			return
		# 当前活动上下文；每次循环重新读取，允许嵌套恢复更新共享参数。
		var resolution_context: Dictionary = _active_card_resolutions[parent_card_uid] as Dictionary
		# 规范化目标数组；保持使用牌时确定的行动顺序，不因中途死亡重新排列。
		var target_ids: Array = resolution_context.get("target_ids", []) as Array
		# 下一目标游标；目标开始前立即递增并写回，异步恢复不会重复创建同一无懈或响应窗口。
		var target_index: int = int(resolution_context.get("target_index", 0))
		if target_index >= target_ids.size():
			_finalize_processing_card(parent_card_uid)
			return
		# 当前目标 ID；死亡或离场目标直接视为完成，继续后续目标。
		var target_id: int = int(target_ids[target_index])
		resolution_context["target_index"] = target_index + 1
		resolution_context["current_target_id"] = target_id
		_active_card_resolutions[parent_card_uid] = resolution_context
		var target: PlayerState = state.get_player(target_id)
		if target == null or not target.alive or target.out_of_game:
			_complete_active_card_target(parent_card_uid)
			continue
		# 当前目标内容事件；只在该目标真正进入效果前记录，死亡或离场目标不会伪造已执行的 content。
		_record_runtime_event("content", "card_content", {"actor_id":int(resolution_context.get("actor_id", -1)), "target_id":target_id, "card_uid":parent_card_uid}, {}, int(resolution_context.get("card_use_event_id", -1)))
		# 本目标结算结果；pending 表示已创建响应窗口，discard 表示当前目标同步完成但整张牌尚不能收尾。
		var destination: String = effect_resolver.resolve_target(parent_card, int(resolution_context.get("actor_id", -1)), target_id, resolution_context)
		if state.game_over:
			_active_card_resolutions.erase(parent_card_uid)
			return
		if destination == "pending" or has_pending_card_choice():
			return
		_complete_active_card_target(parent_card_uid)


## 标记活动卡牌的当前目标已经完成并继续下一目标；没有活动上下文时兼容旧单目标调用并直接收尾。
func _complete_active_card_target(parent_card_uid: int) -> void:
	if not _active_card_resolutions.has(parent_card_uid):
		_finalize_processing_card(parent_card_uid)
		return
	# 当前活动上下文；清除目标标记后保留已经递增的下一目标游标。
	var resolution_context: Dictionary = _active_card_resolutions[parent_card_uid] as Dictionary
	# 当前目标 ID；异步响应或选择结束时在清除标记前补齐 useCardToEnd、After 与【杀】尾部。
	var completed_target_id: int = int(resolution_context.get("current_target_id", -1))
	if completed_target_id >= 0:
		_finish_card_target_lifecycle(parent_card_uid, completed_target_id, int(resolution_context.get("card_use_event_id", -1)))
	resolution_context["current_target_id"] = -1
	_active_card_resolutions[parent_card_uid] = resolution_context
	# 真实 content 子事件由其选择子事件自然阻塞，统一 drain 后由父 CardUseEvent 的 redo 安排下一目标。
	var card_use_context: Dictionary = _card_use_contexts.get(parent_card_uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(parent_card_uid)


## 构造使用牌与逐目标时机共享的标准数据；数组和字典均深复制，触发器修改后必须由专用执行函数显式写回。
func _build_card_use_timing_data(card_uid: int, target_id: int = -1) -> Dictionary:
	# 当前使用牌上下文；缺失时返回最小 UID 数据供取消或异常收尾记录。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	return {
		"card_uid":card_uid,
		"card_id":str(card_use_context.get("card_definition_id", "")),
		"target_id":target_id,
		"target_ids":(card_use_context.get("target_ids", []) as Array).duplicate(),
		"excluded_target_ids":(card_use_context.get("excluded_target_ids", []) as Array).duplicate(),
		"direct_hit_target_ids":(card_use_context.get("direct_hit_target_ids", []) as Array).duplicate(),
		"custom_args":(card_use_context.get("custom_args", {}) as Dictionary).duplicate(true),
		"virtual_storage":(card_use_context.get("virtual_storage", {}) as Dictionary).duplicate(true),
	}


## 返回当前使用牌保存的虚拟扩展存储副本；实体牌或已完成牌效返回空字典，调用方不得修改核心上下文。
func get_card_virtual_storage(card_uid: int) -> Dictionary:
	# 使用牌生命周期上下文；只有仍在结算中的逻辑牌保留扩展存储。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	return (card_use_context.get("virtual_storage", {}) as Dictionary).duplicate(true)


## 开始一名目标的牌效生命周期；同时为【杀】派发 shaBefore 与 shaBegin，任一取消都会产生对应取消时机。
func _begin_card_target_lifecycle(card_uid: int, target_id: int, parent_event_id: int) -> bool:
	# 当前逐目标共享上下文；同一目标异步恢复时不会重复派发 Before 与 Begin。
	var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
	if bool(resolution_context.get("target_lifecycle_started", false)) and not bool(resolution_context.get("target_lifecycle_finished", false)) and int(resolution_context.get("current_target_id", -1)) == target_id:
		return true
	# 当前使用牌上下文与使用者；player 角色对应使用者，target 角色对应当前生效目标。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 当前目标的时机数据；后续窗口读取前一窗口的最终修改。
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid, target_id)
	# 当前牌定义；effect_id=slash 的三种【杀】共享专属时机。
	var definition: Dictionary = GameDatabase.get_card(str(card_use_context.get("card_definition_id", "")))
	# 本目标的生命周期窗口；数据声明次序，公共步骤负责逐个等待。
	var timing_names: Array[String] = ["useCardToBefore", "useCardToBegin"]
	if str(definition.get("effect_id", "")) == "slash":
		timing_names.append_array(["shaBefore", "shaBegin"])
	resolution_context["target_lifecycle_started"] = true
	resolution_context["target_lifecycle_finished"] = false
	_active_card_resolutions[card_uid] = resolution_context
	_run_card_lifecycle_timings(card_uid, target_id, parent_event_id, timing_names, timing_data, true)
	return not (_card_use_contexts.get(card_uid, {}) as Dictionary).get("excluded_target_ids", []).has(target_id)

## 完成一名目标的牌效生命周期；异步和同步路径共用标记，确保 useCardToEnd、After 与 shaEnd、After 只派发一次。
func _finish_card_target_lifecycle(card_uid: int, target_id: int, parent_event_id: int) -> void:
	# 当前逐目标共享上下文；未开始或已经完成时不补造事件。
	var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
	if not bool(resolution_context.get("target_lifecycle_started", false)) or bool(resolution_context.get("target_lifecycle_finished", false)):
		return
	# 当前使用牌上下文与使用者；用于角色关系匹配和牌族判断。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 当前目标的结束数据；尾部技能按固定次序逐项完成。
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid, target_id)
	# 牌定义；杀族追加专属End与After，其余牌只使用公共逐目标窗口。
	var definition: Dictionary = GameDatabase.get_card(str(card_use_context.get("card_definition_id", "")))
	# 本目标的收尾窗口；先登记完成标记，防止嵌套结算重新进入同一尾部。
	var timing_names: Array[String] = []
	if str(definition.get("effect_id", "")) == "slash":
		timing_names.append_array(["shaEnd", "shaAfter"])
	timing_names.append_array(["useCardToEnd", "useCardToAfter"])
	resolution_context["target_lifecycle_finished"] = true
	_active_card_resolutions[card_uid] = resolution_context
	_run_card_lifecycle_timings(card_uid, target_id, parent_event_id, timing_names, timing_data)

## 把一个生命周期组展开为可暂停的内容步骤；每次时机结果读取都发生在其子结算结束后。
func _run_card_lifecycle_timings(card_uid: int, target_id: int, parent_event_id: int, timing_names: Array[String], timing_data: Dictionary, cancel_body: bool = false) -> void:
	# 声明式步骤；每个窗口单独派发，最后一项也必须读取异步取消结果。
	var steps: Array[Callable] = []
	# 当前生命周期时机名；声明顺序就是等待与发布顺序，不在恢复时重排。
	for timing_name: String in timing_names:
		steps.append(Callable(self, "_emit_card_lifecycle_step").bind(timing_name))
	steps.append(_finish_card_lifecycle_step)
	run_rule_sequence(steps, {"card_uid":card_uid, "target_id":target_id, "parent_event_id":parent_event_id, "timing_data":timing_data, "cancel_body":cancel_body})


## 等待前一窗口后派发下一窗口；只读规则数据与稳定ID，不保存实体卡牌引用。
func _emit_card_lifecycle_step(sequence: RuleStepSequence, timing_name: String) -> void:
	if not _read_card_lifecycle_result(sequence):
		return
	# 当前使用牌上下文；清理后的旧序列没有权力重新创建时机。
	var card_use_context: Dictionary = _card_use_contexts.get(int(sequence.context.get("card_uid", -1)), {}) as Dictionary
	if card_use_context.is_empty():
		sequence.finish()
		return
	# 使用者；全局窗口和目标窗口采用同一角色归属。
	var actor_id: int = int(card_use_context.get("actor_id", -1))
	sequence.wait_for_timing(_emit_rule_timing(timing_name, actor_id, actor_id, int(sequence.context.get("target_id", -1)), sequence.context.get("timing_data", {}) as Dictionary, int(sequence.context.get("parent_event_id", -1))))


## 最后一个窗口同样需要等待后提交结果；不能因为没有下个窗口而遗漏取消。
func _finish_card_lifecycle_step(sequence: RuleStepSequence) -> void:
	_read_card_lifecycle_result(sequence)


## 读取上一窗口最终数据；主体取消只排除对应范围，保留牌材料回收与取消通知。
func _read_card_lifecycle_result(sequence: RuleStepSequence) -> bool:
	# 原始规则窗口；首次步骤没有前置结果，直接继续。
	var event: RuleEvent = sequence.waiting_event
	if event == null:
		return true
	sequence.waiting_event = null
	sequence.context["timing_data"] = event.data.duplicate(true)
	if not bool(sequence.context.get("cancel_body", false)) or not (event.cancelled or event.neutralized):
		return true
	# 原牌身份；目标取消不能结束其他目标的效果。
	var card_uid: int = int(sequence.context.get("card_uid", -1))
	# 目标范围；负数代表整牌主体取消。
	var target_id: int = int(sequence.context.get("target_id", -1))
	# 暂停后重新读取的共享上下文；避免旧快照覆盖其他子技能的合法修改。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	sequence.finish()
	if card_use_context.is_empty():
		return false
	if target_id < 0:
		card_use_context["cancelled"] = true
		card_use_context["cancel_reason"] = event.termination_reason
	else:
		# 当前已排除目标；重复取消只保留一次身份。
		var excluded_target_ids: Array = card_use_context.get("excluded_target_ids", []) as Array
		if not excluded_target_ids.has(target_id):
			excluded_target_ids.append(target_id)
		card_use_context["excluded_target_ids"] = excluded_target_ids
		# 被取消目标不再派发成功End/After；取消通知仍可包含自己的子选择。
		var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
		resolution_context["target_lifecycle_finished"] = true
		_active_card_resolutions[card_uid] = resolution_context
	_card_use_contexts[card_uid] = card_use_context
	if target_id >= 0:
		sequence.wait_for_timing(_emit_rule_timing("shaCancelled" if event.name.begins_with("sha") else "useCardToCancelled", event.player_id, event.source_id, target_id, event.data, int(sequence.context.get("parent_event_id", -1))))
	return false


## 从无懈可击未抵消的当前目标重新进入效果；恢复键保证本次不会再次创建相同目标的无懈询问。
func _resume_active_card_target(parent_card_uid: int) -> void:
	if not _active_card_resolutions.has(parent_card_uid):
		_finalize_processing_card(parent_card_uid)
		return
	# 当前活动上下文；current_target_id 在目标响应完成前保持不变。
	var resolution_context: Dictionary = _active_card_resolutions[parent_card_uid] as Dictionary
	# 原始处理区卡牌；旧选择恢复时牌已离区则终止上下文。
	var parent_card: CardInstance = _find_processing_card(parent_card_uid)
	if parent_card == null:
		_active_card_resolutions.erase(parent_card_uid)
		return
	# 当前目标 ID；无有效目标说明上下文已经由其他恢复路径推进。
	var target_id: int = int(resolution_context.get("current_target_id", -1))
	if target_id < 0:
		# 当前使用牌生命周期；真实事件树等待父 content 自然恢复，迁移期调用继续旧游标。
		var card_use_context: Dictionary = _card_use_contexts.get(parent_card_uid, {}) as Dictionary
		if not bool(card_use_context.get("runtime_managed", false)):
			_continue_active_card_resolution(parent_card_uid)
		return
	# 恢复后的单目标效果结果；卡牌源码可从共享上下文恢复双目标或整张牌特有语义。
	var destination: String = effect_resolver.resolve_target(parent_card, int(resolution_context.get("actor_id", -1)), target_id, resolution_context)
	if destination == "pending" or has_pending_card_choice() or state.game_over:
		return
	_complete_active_card_target(parent_card_uid)


## 按配置 ID 返回玩家当前装备实体；可选装备触发使用实体 UID 防止等待期间替换装备后误发动。
func _get_equipment_card_by_definition(player_id: int, definition_id: String) -> CardInstance:
	# 指定玩家；不存在时没有可发动装备。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null
	for card_variant: Variant in player.equipment.values():
		# 当前装备实体；定义 ID 匹配时返回原对象供只读校验和候选序列化。
		var equipment_card: CardInstance = card_variant as CardInstance
		if equipment_card.definition_id == definition_id:
			return equipment_card
	return null


## 创建一张虚拟牌并使用；单材料转化继承材料花色点数，多材料转化按材料聚合花色与颜色。
## 可选规则覆写只表达技能的距离、次数或目标上限修正，材料真实花色与颜色由本入口强制写入并参与最终目标校验。
func execute_virtual_card_use(actor_id: int, virtual_card_definition_id: String, material_card_uids: Array[int], target_ids: Array[int], log_message: String, rule_overrides: Dictionary = {}, virtual_storage: Dictionary = {}) -> bool:
	if virtual_card_definition_id.is_empty() or material_card_uids.is_empty():
		return false
	# 单材料转化牌的花色；多材料时改由材料聚合结果覆盖。
	var virtual_suit: String = "none"
	# 单材料转化牌的点数；默认0表示多材料虚拟牌没有可继承点数。
	var virtual_rank: int = 0
	# 多材料聚合颜色；空字符串表示颜色可直接由聚合花色推导，例如两张黑桃当【杀】。
	var virtual_color_override: String = ""
	if material_card_uids.size() == 1:
		# 唯一材料牌；允许来自手牌、木牛“粮”或装备区，lose子事件仍会再次复核区域。
		var single_material: CardInstance = _find_owned_virtual_material(actor_id, material_card_uids[0])
		if single_material == null:
			return false
		virtual_suit = single_material.suit
		virtual_rank = single_material.rank
	else:
		# 多材料牌实体；每张材料必须在创建代理前仍归使用者所有，否则无法确定本次真实花色与颜色。
		var material_cards: Array[CardInstance] = []
		for material_card_uid: int in material_card_uids:
			# 当前材料实体；缺失即拒绝本次使用，避免按猜测颜色指定目标。
			var material_card: CardInstance = _find_owned_virtual_material(actor_id, material_card_uid)
			if material_card == null:
				return false
			material_cards.append(material_card)
		# 材料聚合结果；同花色视为该花色，同色不同花色保留颜色但无花色，异色无色。
		var material_aggregate: Dictionary = VirtualCard.resolve_material_aggregate(material_cards)
		virtual_suit = str(material_aggregate.get("suit", "none"))
		# 聚合颜色覆写；花色已能表达颜色时保持空字符串，只有“某色无花色”才写入。
		if virtual_suit == "none" and str(material_aggregate.get("color", "none")) != "none":
			virtual_color_override = str(material_aggregate.get("color", "none"))
	# 逻辑代理实体；只在本次CardUseEvent的处理区生命周期内存在。
	var virtual_card: CardInstance = CardInstance.new(virtual_card_definition_id, virtual_suit, virtual_rank)
	virtual_card.color_override = virtual_color_override
	if material_card_uids.size() == 1:
		# 单材料转化的原牌面定义；表现层继续绘制材料实体，并以横条标明本次实际使用的逻辑牌名。
		var presentation_material: CardInstance = _find_owned_virtual_material(actor_id, material_card_uids[0])
		if presentation_material != null:
			# 已处于手牌视为状态的材料必须回溯其实体原名，否则代理会把逻辑牌误画成自己的原牌面。
			virtual_card.last_hand_view_as_original_definition_id = presentation_material.hand_view_as_original_definition_id if presentation_material.has_hand_view_as() else presentation_material.definition_id
			virtual_card.last_hand_view_as_definition_id = virtual_card_definition_id
	virtual_card.zone = "void"
	virtual_card.owner_id = -1
	# 虚拟牌规范目标；技能附加目标数后的多目标【杀】同样必须按使用者起算的顺时针顺序结算，不能保留点击顺序。
	var normalized_target_ids: Array[int] = card_rules.normalize_targets(actor_id, virtual_card, target_ids)
	# 最终规则覆写；复制技能参数后用真实代理牌颜色覆盖同名字段，禁止调用方伪造材料颜色绕过来牌限制。
	var validated_rule_overrides: Dictionary = rule_overrides.duplicate(true)
	validated_rule_overrides["card_color"] = virtual_card.get_color()
	# 虚拟牌最终合法性；在移动任何材料或创建处理区表现前统一复核次数、距离、目标组合与目标技能免疫。
	if card_rules.validate_virtual_use(actor_id, virtual_card_definition_id, normalized_target_ids, validated_rule_overrides) != "":
		return false
	_ensure_card_movement()
	if _move_card_with_timings(virtual_card, "processing", -1, "virtual_card_begin", state.current_event_id) == null:
		return false
	if not log_message.is_empty():
		add_log(log_message)
	_execute_card_use(actor_id, virtual_card, normalized_target_ids, material_card_uids, true, target_ids, virtual_storage)
	return true


## 使用一张没有实体材料的虚拟牌；用于以体力等非牌资源为费用的“视为使用”技能，virtual_storage可携带连续结算稳定标签。
func execute_cardless_virtual_card_use(actor_id: int, virtual_card_definition_id: String, target_ids: Array[int], log_message: String = "", rule_overrides: Dictionary = {}, virtual_storage: Dictionary = {}) -> bool:
	if state == null or state.game_over or virtual_card_definition_id.is_empty():
		return false
	# 无花色无点数代理牌；其只存在于本次CardUseEvent处理区生命周期，不会成为牌堆实体。
	var virtual_card: CardInstance = CardInstance.new(virtual_card_definition_id, "none", 0)
	virtual_card.zone = "void"
	virtual_card.owner_id = -1
	# 经卡牌规则排序后的最终目标ID；后续用牌事件只消费该强类型数组。
	# 规则覆写必须一并传入：视为牌的目标模式可能取自另一张牌的定义补丁，
	# 若这里用未打补丁的定义展开，就会与紧随其后的合法性复核各用一套 target_mode 而互相否决。
	var normalized_target_ids: Array[int] = card_rules.normalize_targets(actor_id, virtual_card, target_ids, rule_overrides)
	# 本次无材料虚拟牌的规则覆写副本；加入无色事实后进行最终合法性复核。
	var validated_rule_overrides: Dictionary = rule_overrides.duplicate(true)
	validated_rule_overrides["card_color"] = "none"
	if card_rules.validate_virtual_use(actor_id, virtual_card_definition_id, normalized_target_ids, validated_rule_overrides) != "":
		return false
	_ensure_card_movement()
	if _move_card_with_timings(virtual_card, "processing", -1, "virtual_card_begin", state.current_event_id) == null:
		return false
	if not log_message.is_empty():
		add_log(log_message)
	_execute_card_use(actor_id, virtual_card, normalized_target_ids, [], true, target_ids, virtual_storage)
	return true


## 按 UID 查找玩家可作为转化材料的当前拥有牌；支持普通手牌、木牛“粮”与已装备牌。
func _find_owned_virtual_material(player_id: int, card_uid: int) -> CardInstance:
	# 材料持有者；不存在时不能从任何区域提供转化材料。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null:
		return null
	# 手牌与木牛“粮”属于统一可使用牌源；命中后直接返回实体对象供只读校验或统一移动。
	var playable_card: CardInstance = player.find_playable_card(card_uid)
	if playable_card != null:
		return playable_card
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；只按稳定 UID 命中，不依赖槽位或卡牌定义名称。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card.uid == card_uid:
			return equipment_card
	return null


## 执行已通过合法性校验的出牌动作。
func _execute_card_use(actor_id: int, card: CardInstance, target_ids: Array[int], material_card_uids: Array[int] = [], virtual_proxy: bool = false, requested_target_ids: Array[int] = [], virtual_storage: Dictionary = {}) -> void:
	if state == null or state.game_over or card == null:
		return
	if card_use_event_service == null:
		card_use_event_service = CardUseEventService.new()
	# 当前卡牌定义；用于次数计数与日志。
	# 当前逻辑牌；真实牌也通过 VirtualCard 描述逻辑属性，实体材料 UID 始终独立保存。
	# 当前卡牌定义快照；提供逻辑属性、效果类型和默认自然属性，不持有运行时状态。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 完整声明目标；未提供辅助目标时与实际目标完全一致，确保普通牌不维护第二套数组。
	var declared_target_ids: Array[int] = requested_target_ids.duplicate() if not requested_target_ids.is_empty() else target_ids.duplicate()
	# 本次使用的逻辑牌快照；后续视为牌与多材料牌可以复用完全相同的事件字段。
	var virtual_card: VirtualCard = VirtualCard.new(card.definition_id, card.suit, card.rank, str(definition.get("nature", "normal")))
	# 本次逻辑牌颜色；实体牌、单材料转化与多材料聚合牌统一读取代理实体颜色，回放可据此还原来牌颜色。
	virtual_card.color = card.get_color()
	# 本次逻辑牌扩展存储；仅允许基础可序列化值，技能可借此把多材料花色等规则数据传递到后续时机。
	virtual_card.storage = virtual_storage.duplicate(true)
	# 实体牌默认以自身作为唯一材料；无材料虚拟牌必须保持空数组，避免后续lose子事件把处理区代理误校验为发动者持有的费用牌。
	if material_card_uids.is_empty() and not virtual_proxy:
		virtual_card.add_material(card.uid)
	else:
		for material_card_uid: int in material_card_uids:
			virtual_card.add_material(material_card_uid)
	# 使用牌事件上下文；仅包含可序列化规则数据，不保存 CardInstance、节点或 Callable。
	var event_context: Dictionary = {
		"actor_id":actor_id,
		"card_id":card.definition_id,
		"card_uid":card.uid,
		"target_ids":target_ids.duplicate(),
		"requested_target_ids":declared_target_ids.duplicate(),
		"virtual_card":virtual_card.to_dict(),
		"material_card_uids":virtual_card.material_card_uids.duplicate(),
		"virtual_storage":virtual_card.storage.duplicate(true),
		"virtual_proxy":virtual_proxy,
	}
	# CardUseEvent 的固定内容步骤；每一步只安排下一层子事件或推进一个明确规则边界。
	var content_steps: Array[Callable] = [
		_card_use_step_declare,
		_card_use_step_begin_lifecycle,
		_card_use_step_enqueue_use_timings,
		_card_use_step_enqueue_target_timings,
		_card_use_step_enqueue_content_before,
		_card_use_step_resolve_content,
		_card_use_step_enqueue_content_after,
		_card_use_step_finish_lifecycle,
		_card_use_step_prepare_after,
	]
	# 正式对局挂到长期根事件；独立规则测试没有根事件时让 CardUseEvent 自身成为本次调度根。
	var parent_event_id: int = event_scheduler.root_event_id if event_scheduler.root_event_id >= 0 else -1
	# 卡牌使用父事件；逻辑牌与实体材料牌分开记录，当前实体牌 UID 是唯一材料。
	# 真实使用牌父事件；它会一直留在栈中等待全部选择、目标内容和 after 回收结束。
	var use_event: GameEvent = card_use_event_service.create_use_event(event_scheduler, parent_event_id, event_context, content_steps)
	if use_event == null:
		return
	use_event.card["virtual_id"] = use_event.event_id
	# 卡牌使用生命周期上下文；contentAfter 必须等待全部同步或异步目标效果完成后再写入。
	# 使用牌生命周期共享上下文；字典只保存稳定 ID、游标和规则标记，异步恢复不持有牌对象。
	_card_use_contexts[card.uid] = {
		"event_id":use_event.event_id,
		"actor_id":actor_id,
		"card_definition_id":card.definition_id,
		"target_ids":target_ids.duplicate(),
		"requested_target_ids":declared_target_ids.duplicate(),
		"excluded_target_ids":[],
		"direct_hit_target_ids":[],
		"direct_response_count":0,
		"direct_response_player_ids":[],
		"custom_args":{},
		"material_card_uids":virtual_card.material_card_uids.duplicate(),
		"virtual_storage":virtual_card.storage.duplicate(true),
		"virtual_proxy":virtual_proxy,
		"destination":"pending",
		"content_complete":false,
		"runtime_managed":true,
	}
	if parent_event_id < 0:
		event_scheduler.start(use_event.event_id)
	else:
		event_scheduler.drain()


## CardUseEvent 第一步：创建真实 lose 子事件；材料进入处理区后才声明使用次数、日志与牌面表现。
func _card_use_step_declare(event: GameEvent, scheduler: EventScheduler) -> void:
	# 当前实体材料 UID；基础牌只有一个材料，后续多材料牌仍从同一逻辑牌数组读取。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前共享生命周期；事件已失效时中止，防止旧事件移动新对局中的同 UID 牌。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card_use_context.is_empty() or state == null or state.game_over:
		event.abort("card_use_context_missing")
		return
	if not bool(card_use_context.get("materials_moved", false)):
		# lose 子事件上下文；移动原因和材料 UID 可直接供回放重建处理区变化。
		var lose_context: Dictionary = event.context.duplicate(true)
		lose_context["to_zone"] = "processing"
		lose_context["reason"] = "use"
		scheduler.create_child(event.event_id, "lose", "card_move", [_execute_use_card_lose_event], lose_context)
		card_use_context["materials_moved"] = true
		_card_use_contexts[card_uid] = card_use_context
		event.redo()
		return
	if bool(card_use_context.get("declared", false)):
		return
	# 处理区中的使用牌；lose 子事件失败或材料已被其他规则移动时不能继续伪造声明。
	var card: CardInstance = _find_processing_card(card_uid)
	# 使用者状态；死亡或不存在时取消本次牌效，但材料仍由 after 队列按规则回收。
	# 使用牌的玩家状态；从其手牌移至处理区。
	var actor_id: int = int(card_use_context.get("actor_id", -1))
	# 当前使用者状态；用于次数统计、日志和卡牌展示来源。
	var actor: PlayerState = state.get_player(actor_id)
	if card == null or actor == null:
		card_use_context["cancelled"] = true
		card_use_context["cancel_reason"] = "material_or_actor_missing"
		_card_use_contexts[card_uid] = card_use_context
		return
	# 当前卡牌定义；次数统计和最终区域所有权均来自统一配置。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 本次牌是否不计入配置化次数限制；使用前已经通过基础上限校验，声明后仍保留完整使用事实。
	var does_not_count_toward_play_limit: bool = skill_card_use_does_not_count_toward_play_limit(actor_id, definition)
	actor.card_use_history[card.definition_id] = int(actor.card_use_history.get(card.definition_id, 0)) + 1
	_record_card_used_this_turn(actor_id, card.definition_id)
	# 当前出牌阶段使用历史；只服务 phase 作用域限次查询，不替代完整回合使用记录。
	actor.play_phase_card_use_history[card.definition_id] = int(actor.play_phase_card_use_history.get(card.definition_id, 0)) + 1
	if does_not_count_toward_play_limit:
		actor.card_use_limit_exempt_history[card.definition_id] = int(actor.card_use_limit_exempt_history.get(card.definition_id, 0)) + 1
		actor.play_phase_card_use_limit_exempt_history[card.definition_id] = int(actor.play_phase_card_use_limit_exempt_history.get(card.definition_id, 0)) + 1
	# 当前卡牌源码；牌族兼容统计与声明时触发由对应文件维护。
	var source_definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if source_definition != null:
		source_definition.on_card_declared(self, actor, card)
	# 使用牌目标日志；空目标（如【酒】【无中生有】）不追加目标片段。
	var use_target_text: String = format_target_log_names(event.target_ids)
	if use_target_text.is_empty():
		add_log("%s使用了%s。" % [format_player_state_log_name(actor), format_card_log_name(card)])
	else:
		add_log("%s使用了%s，目标为%s。" % [format_player_state_log_name(actor), format_card_log_name(card), use_target_text])
	# 只有正常规则终点为弃牌堆的牌接管后续 processing -> discard 表现，装备与延时锦囊保留未来真实离区动画。
	var owns_discard_transfer: bool = str(definition.get("final_zone", "discard")) == "discard" and not bool(card_use_context.get("virtual_proxy", false))
	# 卡牌展示请求只携带序列化数据与稳定玩家 ID，界面可据此播放飞牌和目标指示动画，不持有权威状态对象。
	# 使用时完整声明目标；借刀杀人等角色语义牌可据此生成多段顺序指示线。
	var requested_presentation_target_ids: Array[int] = _int_array(card_use_context.get("requested_target_ids", event.target_ids) as Array)
	# 分阶段指示线；普通牌返回空数组并继续使用实际目标单段表现。
	var presentation_indicator_stages: Array[Dictionary] = source_definition.get_presentation_indicator_stages(actor_id, requested_presentation_target_ids, event.target_ids) if source_definition != null else []
	_request_card_presentation(card, actor_id, event.target_ids, "useCard", event.event_id, owns_discard_transfer, presentation_indicator_stages)
	# 音频表现：声明使用后请求一次卡牌语音；与“打出”共用同一份音效，虚拟牌按实际结算定义取音。
	request_card_voice(actor_id, card.definition_id, VOICE_PLAY_MODE_USE)
	# 兼容扩展事件；现有独立技能仍可监听 card_used，新的源码级技能应优先监听真实 useCard 时机子事件。
	_dispatch_rule_event(RuleEvent.new("card_used", actor_id, event.target_ids[0] if not event.target_ids.is_empty() else -1, {"card_uid":card.uid, "card_id":card.definition_id, "target_ids":event.target_ids.duplicate()}))
	card_use_context["declared"] = true
	_card_use_contexts[card_uid] = card_use_context


## 在 lose 子事件内把全部实体材料移动到 processing；移动历史直接关联真实 lose 事件 ID。
func _execute_use_card_lose_event(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 当前实体牌；基础实现按唯一材料 UID 查找使用者可用牌区，不依赖数组下标。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 材料持有者；手牌与木牛“粮”共用 find_playable_card 和 CardMovementService 区域移除逻辑。
	var actor_id: int = int(event.context.get("actor_id", -1))
	# 材料持有者状态；角色不存在时不能从任何可出牌区域取得实体。
	var actor: PlayerState = state.get_player(actor_id)
	# 待移动实体材料；默认从持有者手牌或木牛“粮”中按 UID 查找。
	var card: CardInstance = actor.find_playable_card(card_uid) if actor != null else null
	if not bool(event.context.get("virtual_proxy", false)):
		if card == null:
			event.cancel("material_not_playable")
			return
		# 真实材料的lose子事件持有独立暂停令牌；父CardUseEvent必须等待移牌时机与选择完整结束。
		var pause_token_id: int = event_scheduler.pause_registry.acquire("card_move", event.event_id, "card_use_material")
		var movement: CardMoveResolutionService = CardMoveResolutionService.new(self)
		var move_steps: Array[Callable] = [
			Callable(self, "_begin_card_use_material_move").bind(event, movement, card.uid),
			Callable(self, "_finish_card_use_material_move").bind(event, movement),
			Callable(self, "_release_card_use_material_move").bind(pause_token_id),
		]
		if run_rule_sequence(move_steps, {"sequence_kind":"card_use_material_move", "event_id":event.event_id, "card_uid":card.uid}) < 0:
			event_scheduler.pause_registry.resolve(pause_token_id, "card_move_sequence_unavailable")
		return
	if bool(event.context.get("virtual_proxy", false)):
		# 虚拟牌实体材料 UID；逻辑代理牌已经在事件开始前进入处理区，材料仍须由发动者拥有。
		var material_card_uids: Array[int] = _int_array(event.context.get("material_card_uids", []) as Array)
		# 待移动材料对象；全部存在后才开始逐张移动，避免过期动作只消费一部分费用。
		var material_cards: Array[CardInstance] = []
		for material_card_uid: int in material_card_uids:
			# 当前转化材料；具体技能或装备已在发动入口限制区域，核心只复核实体仍归发动者所有。
			var material_card: CardInstance = _find_owned_virtual_material(actor_id, material_card_uid)
			if material_card == null:
				event.cancel("virtual_material_not_owned")
				return
			material_cards.append(material_card)
		_ensure_card_movement()
		# 已完成材料移动 ID；每张材料保留独立 CardMoveEvent，回放可按玩家选择顺序重建。
		var material_move_ids: Array[int] = []
		for material_card: CardInstance in material_cards:
			# 材料移动前的装备区归属；移动成功后据此清理装备运行时并执行对应离区效果。
			var was_equipment_card: bool = actor != null and actor.equipment.values().has(material_card)
			# 材料进入处理区；在虚拟杀完整结算前不会提前进入弃牌堆。
			var material_move: CardMoveEvent = _move_card_with_timings(material_card, "processing", -1, "use", event.event_id)
			if material_move == null:
				event.cancel("virtual_material_move_failed")
				return
			if was_equipment_card:
				_on_equipment_lost(actor, material_card, true)
			material_move_ids.append(material_move.move_id)
		event.result = {"card_uids":material_card_uids.duplicate(), "to_zone":"processing", "move_ids":material_move_ids}
		return
	if card == null:
		event.cancel("material_not_playable")
		return
	_ensure_card_movement()
	# 实体移动结果；服务统一维护来源区域、持有者、知识与处理区数组。
	var move: CardMoveEvent = _move_card_with_timings(card, "processing", -1, "use", event.event_id)
	if move == null:
		event.cancel("material_move_failed")
		return
	event.result = {"card_uids":[card.uid], "from_zone":move.from_zone, "to_zone":"processing", "move_id":move.move_id}


## 开始实体卡牌材料的可暂停处理区移动；服务完成前不写入lose结果。
func _begin_card_use_material_move(sequence: RuleStepSequence, event: GameEvent, movement: CardMoveResolutionService, card_uid: int) -> void:
	movement.begin(sequence, card_uid, "processing", -1, "use", event.event_id)


## 读取移牌结果并写入lose子事件；失败时取消父牌使用而不伪造processing状态。
func _finish_card_use_material_move(_sequence: RuleStepSequence, event: GameEvent, movement: CardMoveResolutionService) -> void:
	if bool(movement.result.get("success", false)):
		event.result = {"card_uids":[int(movement.result.get("card_uid", -1))], "from_zone":str(movement.result.get("from_zone", "")), "to_zone":"processing", "move_id":int(movement.result.get("move_id", -1))}
	else:
		event.cancel("material_move_failed")


## 释放lose子事件的移牌暂停令牌；事件调度器随后恢复CardUseEvent声明步骤。
func _release_card_use_material_move(_sequence: RuleStepSequence, pause_token_id: int) -> void:
	if event_scheduler != null:
		event_scheduler.pause_registry.resolve(pause_token_id, "card_move_complete")


## 在牌进入处理区并完成声明后派发 useCardBefore 与 useCardBegin；取消会保留材料收尾但跳过后续牌效。
func _card_use_step_begin_lifecycle(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 当前使用牌 UID；用于取得跨全部目标共享的生命周期上下文。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 使用牌共享上下文；声明失败时仍按取消路径收尾处理区材料。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card_use_context.is_empty() or bool(card_use_context.get("lifecycle_started", false)):
		return
	# 使用牌时机数据；与后续 useCard0 至 useCard 保持相同标准字段。
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid)
	card_use_context["lifecycle_started"] = true
	_card_use_contexts[card_uid] = card_use_context
	_run_card_lifecycle_timings(card_uid, -1, event.event_id, ["useCardBefore", "useCardBegin"], timing_data, true)

## 安排 useCard0/useCard1/yingbian/useCard2/useCard 五组真实时机子事件。
func _card_use_step_enqueue_use_timings(event: GameEvent, scheduler: EventScheduler) -> void:
	card_use_event_service.enqueue_use_timings(scheduler, event, _execute_card_use_timing_event)


## 逐目标触发顺序；无名杀会先让全部目标经过同一阶段，再进入下一阶段，不能对单个目标连续跑完四个时机。
## 在全部全局时机结束后按最新目标数组逐次安排四组时机；每个子事件结束后重新读取动态目标。
func _card_use_step_enqueue_target_timings(event: GameEvent, scheduler: EventScheduler) -> void:
	# 当前使用牌 UID；用于读取唯一共享生命周期上下文。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 使用牌共享上下文；全局或上一目标时机都可调整目标数组，每次 redo 必须重新读取。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	event.target_ids.clear()
	for target_id_variant: Variant in card_use_context.get("target_ids", event.context.get("target_ids", [])) as Array:
		event.target_ids.append(int(target_id_variant))
	# 当前逐目标阶段索引；范围0至3，达到数组长度表示四组时机均已结束。
	var timing_stage_index: int = int(card_use_context.get("target_timing_stage_index", 0))
	if timing_stage_index >= CardUseEventService.TARGET_TIMING_NAMES.size():
		card_use_context.erase("target_timing_stage_index")
		card_use_context.erase("target_timing_processed_ids")
		_card_use_contexts[card_uid] = card_use_context
		return
	# 本阶段已经创建过时机的目标 ID；数组保留重复项，使同一角色在目标数组出现多次时按出现次数分别触发。
	var processed_target_ids: Array = card_use_context.get("target_timing_processed_ids", []) as Array
	# 本轮目标遍历副本；普通多目标按当前行动座次重排，借刀等具有位置语义的目标继续由规则服务保留原顺序。
	var target_iteration_ids: Array[int] = event.target_ids.duplicate()
	# 处理区实体；动态目标排序复用与动作提交相同的卡牌规则，缺失时保持共享数组现有顺序完成防御性收口。
	var card: CardInstance = _find_processing_card(card_uid)
	if card != null:
		target_iteration_ids = card_rules.normalize_targets(int(card_use_context.get("actor_id", -1)), card, event.target_ids)
	# 下一名未处理目标；按 noname getTriggerTarget 的计数语义比较当前目标数与已触发数，动态增删和重复目标都不依赖漂移下标。
	var next_target_id: int = -1
	for target_id: int in target_iteration_ids:
		if processed_target_ids.count(target_id) < event.target_ids.count(target_id):
			next_target_id = target_id
			break
	if next_target_id < 0:
		card_use_context["target_timing_stage_index"] = timing_stage_index + 1
		card_use_context["target_timing_processed_ids"] = []
		_card_use_contexts[card_uid] = card_use_context
		event.redo()
		return
	processed_target_ids.append(next_target_id)
	card_use_context["target_timing_processed_ids"] = processed_target_ids
	_card_use_contexts[card_uid] = card_use_context
	# 当前稳定时机名称；只有全部当前目标完成后才会递增到下一阶段。
	var timing_name: String = CardUseEventService.TARGET_TIMING_NAMES[timing_stage_index]
	card_use_event_service.enqueue_target_timing(scheduler, event, timing_name, next_target_id, _execute_card_use_timing_event)
	event.redo()


## 安排唯一 contentBefore 子事件；卡牌定义可在该时机准备整牌共享数据。
func _card_use_step_enqueue_content_before(event: GameEvent, scheduler: EventScheduler) -> void:
	card_use_event_service.enqueue_content_before(scheduler, event, _execute_card_content_before_event)


## 执行一个真实使用牌时机并把触发器修改写回 CardUseEvent 的共享可序列化上下文。
func _execute_card_use_timing_event(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 时机稳定名称；由 CardUseEventService 按源码顺序写入。
	var timing_name: String = str(event.context.get("timing_name", event.name))
	# 原使用牌 UID；用于取得跨时机共享的目标排除、直击和自定义参数。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前使用牌共享上下文；全部时机只通过该字典交换可序列化规则字段。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card_use_context.is_empty():
		event.abort("card_use_context_missing")
		return
	# 当前目标 ID；全局使用牌时机使用-1，逐目标时机在每次执行前重新校验角色仍在场。
	var target_id: int = int(event.context.get("target_id", -1))
	if target_id >= 0:
		# 当前目标状态；死亡或离场目标结束自身时机，不影响其他目标继续。
		var target: PlayerState = state.get_player(target_id)
		if target == null or not target.alive or target.out_of_game:
			event.cancel("target_out_of_game")
			return
	# 触发器可修改的数据副本；标准键与无名杀 excluded/directHit/customArgs 保持一一对应。
	var timing_data: Dictionary = {
		"card_uid":card_uid,
		"card_id":str(card_use_context.get("card_definition_id", "")),
		"target_ids":(card_use_context.get("target_ids", []) as Array).duplicate(),
		"excluded_target_ids":(card_use_context.get("excluded_target_ids", []) as Array).duplicate(),
		"direct_hit_target_ids":(card_use_context.get("direct_hit_target_ids", []) as Array).duplicate(),
		"custom_args":(card_use_context.get("custom_args", {}) as Dictionary).duplicate(true),
		"virtual_storage":(card_use_context.get("virtual_storage", {}) as Dictionary).duplicate(true),
	}
	# 同步规则事件；处理器仍使用 RuleEvent 端口，但生命周期、父子关系和暂停位置由当前 GameEvent 承载。
	# 派发入口同步返回不代表处理器已全部结束；下方序列单独等待最终修改结果。
	var rule_event: RuleEvent = RuleEvent.new(timing_name, int(card_use_context.get("actor_id", -1)), target_id, timing_data, int(card_use_context.get("actor_id", -1)))
	rule_event.event_id = event.event_id
	rule_event.parent_id = event.parent_id
	# 时机派发与结果提交分为两步；可选技能尚未应答时不能提前复制目标或取消结果。
	run_rule_sequence([
		Callable(self, "_dispatch_card_rule_timing").bind(rule_event),
		Callable(self, "_apply_card_rule_timing").bind(card_uid, target_id, event.event_id),
	])


## 派发使用牌修改窗口并保留原对象；结果步骤等待同一时机的全部触发器结束。
## 等待窗口必须在派发前登记：同步技能在派发过程中就会写入修改参数，只有此时窗口已可
## 从当前序列查到，这些写入才能同步落到事件数据，而不被随后的结果提交用派发前快照覆盖。
func _dispatch_card_rule_timing(sequence: RuleStepSequence, rule_event: RuleEvent) -> void:
	sequence.wait_for_timing(rule_event)
	_dispatch_timing_service_event(rule_event)


## 提交异步修改窗口的最终结果；只修改仍存在的用牌上下文与运行时事件。
func _apply_card_rule_timing(sequence: RuleStepSequence, card_uid: int, target_id: int, event_id: int) -> void:
	# 等待完成的原规则事件；包含所有处理器的最终修改与终止原因。
	var rule_event: RuleEvent = sequence.waiting_event
	# 重新取得的共享上下文；暂停期间原牌可能因终局或换将边界被清理。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if rule_event == null or card_use_context.is_empty():
		return
	# 派发后的实时共享上下文；同步技能可能通过控制器辅助接口直接追加排除或直击目标，不能被派发前复制出的RuleEvent旧数组覆盖。
	var live_card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 触发器输出；目标数组以RuleEvent为准，排除与直击属于可叠加集合，需与同步辅助接口写入的实时结果稳定合并。
	card_use_context["target_ids"] = (rule_event.data.get("target_ids", card_use_context.get("target_ids", [])) as Array).duplicate()
	card_use_context["excluded_target_ids"] = _merge_unique_int_arrays(rule_event.data.get("excluded_target_ids", []) as Array, live_card_use_context.get("excluded_target_ids", []) as Array)
	card_use_context["direct_hit_target_ids"] = _merge_unique_int_arrays(rule_event.data.get("direct_hit_target_ids", []) as Array, live_card_use_context.get("direct_hit_target_ids", []) as Array)
	card_use_context["custom_args"] = (rule_event.data.get("custom_args", card_use_context.get("custom_args", {})) as Dictionary).duplicate(true)
	if rule_event.cancelled or rule_event.neutralized:
		if target_id >= 0:
			# 已排除目标数组；当前目标只追加一次，后续 content 据此跳过牌效。
			var excluded_target_ids: Array = card_use_context.get("excluded_target_ids", []) as Array
			if not excluded_target_ids.has(target_id):
				excluded_target_ids.append(target_id)
			card_use_context["excluded_target_ids"] = excluded_target_ids
		else:
			card_use_context["cancelled"] = true
			card_use_context["cancel_reason"] = rule_event.termination_reason
	_card_use_contexts[card_uid] = card_use_context
	event_scheduler.apply_rule_event_result(event_id, rule_event)


## 执行唯一 contentBefore 边界；整牌内容组件可通过共享 custom_args 读取前置触发器结果。
func _execute_card_content_before_event(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 使用牌共享上下文；结果保留最终目标与三组可修改规则字段供回放检查。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前使用牌共享上下文；contentBefore 只导出深拷贝，不向子事件暴露可变引用。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	event.result = {
		"target_ids":(card_use_context.get("target_ids", []) as Array).duplicate(),
		"excluded_target_ids":(card_use_context.get("excluded_target_ids", []) as Array).duplicate(),
		"direct_hit_target_ids":(card_use_context.get("direct_hit_target_ids", []) as Array).duplicate(),
		"custom_args":(card_use_context.get("custom_args", {}) as Dictionary).duplicate(true),
	}


## 效果执行器返回的结束区域；装备与延时锦囊已在执行器中完成移动，多目标牌由活动游标负责最终收尾。
## 逐次安排目标 content；每个目标效果都是可暂停子事件，父事件通过 redo 等待并继续下一目标。
func _card_use_step_resolve_content(event: GameEvent, scheduler: EventScheduler) -> void:
	# 当前使用牌 UID；全部异步恢复均以实体材料 UID 找回唯一生命周期。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前使用牌共享上下文；目标、终点和内容初始化标记均从这里恢复。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card_use_context.is_empty():
		event.abort("card_use_context_missing")
		return
	if bool(card_use_context.get("cancelled", false)):
		card_use_context["destination"] = "discard"
		card_use_context["content_complete"] = true
		_card_use_contexts[card_uid] = card_use_context
		return
	# 处理区实体；材料提前离开表示效果已被其他规则接管，父事件只完成后置时机而不重复移动。
	var card: CardInstance = _find_processing_card(card_uid)
	if card == null:
		card_use_context["destination"] = "consumed"
		card_use_context["content_complete"] = true
		_card_use_contexts[card_uid] = card_use_context
		return
	# 最新卡牌定义；目标分流只读取卡牌源码声明的 resolution_mode。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 当前最终目标数组；使用牌时机可能增删目标，因此不能继续读取动作提交时的旧副本。
	var resolved_target_ids: Array[int] = []
	for target_id_variant: Variant in card_use_context.get("target_ids", []) as Array:
		resolved_target_ids.append(int(target_id_variant))
	if _uses_active_target_resolution(definition, resolved_target_ids):
		if not bool(card_use_context.get("effect_initialized", false)):
			card_use_context["effect_initialized"] = true
			_card_use_contexts[card_uid] = card_use_context
			_begin_active_card_resolution(card, int(card_use_context.get("actor_id", -1)), resolved_target_ids, event.event_id)
			if has_pending_card_choice():
				event.redo()
				return
		# 活动逐目标上下文；不存在表示外部规则已经完整接管并结束牌效。
		var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
		if resolution_context.is_empty():
			card_use_context["destination"] = "discard"
			card_use_context["content_complete"] = true
			_card_use_contexts[card_uid] = card_use_context
			return
		# 下一目标游标；每创建一个 content 子事件前立即递增，选择恢复不会重复进入同一目标。
		var target_index: int = int(resolution_context.get("target_index", 0))
		# 活动目标数组；保留初始化时的稳定行动顺序和重复出现次数。
		var target_ids: Array = resolution_context.get("target_ids", []) as Array
		if target_index >= target_ids.size():
			_active_card_resolutions.erase(card_uid)
			card_use_context["destination"] = "discard"
			card_use_context["content_complete"] = true
			_card_use_contexts[card_uid] = card_use_context
			return
		# 当前准备创建 content 的目标 ID；读取后立即推进游标以保证异步幂等。
		var target_id: int = int(target_ids[target_index])
		resolution_context["target_index"] = target_index + 1
		resolution_context["current_target_id"] = target_id
		_active_card_resolutions[card_uid] = resolution_context
		# 死亡、离场目标不创建虚假的 content 事件，并派发 Omitted 表示主体未执行。
		var target: PlayerState = state.get_player(target_id)
		if target == null or not target.alive:
			_emit_rule_timing("useCardToOmitted", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), target_id, _build_card_use_timing_data(card_uid, target_id), event.event_id)
			resolution_context["current_target_id"] = -1
			_active_card_resolutions[card_uid] = resolution_context
			event.redo()
			return
		# 已排除目标；Excluded 与 Omitted 分开记录，便于技能判断是规则排除还是角色离场。
		if (card_use_context.get("excluded_target_ids", []) as Array).has(target_id):
			_emit_rule_timing("useCardToExcluded", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), target_id, _build_card_use_timing_data(card_uid, target_id), event.event_id)
			resolution_context["current_target_id"] = -1
			_active_card_resolutions[card_uid] = resolution_context
			event.redo()
			return
		# 单目标牌效生命周期；Before 或 Begin 被取消时将当前目标排除并继续其他目标。
		if not _begin_card_target_lifecycle(card_uid, target_id, event.event_id):
			var excluded_target_ids: Array = card_use_context.get("excluded_target_ids", []) as Array
			if not excluded_target_ids.has(target_id):
				excluded_target_ids.append(target_id)
			card_use_context["excluded_target_ids"] = excluded_target_ids
			_card_use_contexts[card_uid] = card_use_context
			resolution_context["current_target_id"] = -1
			_active_card_resolutions[card_uid] = resolution_context
			event.redo()
			return
		card_use_event_service.enqueue_target_content(scheduler, event, target_id, _execute_card_content_event)
		event.redo()
		return
	if not bool(card_use_context.get("whole_content_enqueued", false)):
		card_use_context["whole_content_enqueued"] = true
		_card_use_contexts[card_uid] = card_use_context
		card_use_event_service.enqueue_target_content(scheduler, event, -1, _execute_card_content_event)
		event.redo()


## 执行单个目标或整牌 content；出现响应/选择时仅暂停本 content 子事件，不推进父 CardUseEvent。
func _execute_card_content_event(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 当前实体牌 UID；用于取得处理区对象与活动目标共享参数。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前处理区实体；离开处理区后不能重复执行原牌内容。
	var card: CardInstance = _find_processing_card(card_uid)
	# 当前使用牌共享上下文；整牌内容从这里读取最终目标与使用者。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card == null or card_use_context.is_empty():
		event.cancel("processing_card_missing")
		return
	# 当前目标 ID；-1表示五谷、装备或延时锦囊等整牌内容。
	var target_id: int = int(event.context.get("target_id", -1))
	# 前置生命周期可能在本子事件排队期间异步取消；牌效执行前必须重新检查最终排除结果。
	if target_id >= 0 and (card_use_context.get("excluded_target_ids", []) as Array).has(target_id):
		_complete_active_card_target(card_uid)
		event.cancel("target_lifecycle_cancelled")
		return
	if target_id < 0 and bool(card_use_context.get("content_complete", false)):
		# 整牌异步效果已经由恢复回调完成；content 事件恢复时只读取最终区域，禁止再次执行亮牌、选择或其他一次性效果。
		event.result = {"target_ids":(card_use_context.get("target_ids", []) as Array).duplicate(), "destination":str(card_use_context.get("destination", "discard"))}
		return
	# 牌效中的回复、伤害、摸牌与选择会创建独立规则序列；暂停当前content事件直至这些子序列完成。
	var pause_token_id: int = event_scheduler.pause_registry.acquire("card_content", event.event_id, "card_effect_children")
	var steps: Array[Callable] = [
		Callable(self, "_resolve_card_content_sequence").bind(event),
		Callable(self, "_finish_card_content_sequence").bind(event),
		Callable(self, "_release_card_content_sequence").bind(pause_token_id),
	]
	if run_rule_sequence(steps, {"sequence_kind":"card_content", "card_uid":card_uid, "target_id":target_id, "event_id":event.event_id}) < 0:
		event_scheduler.pause_registry.resolve(pause_token_id, "card_content_sequence_unavailable")


## 执行牌效主体；新建规则序列会先于下一个父内容步骤完成。
func _resolve_card_content_sequence(sequence: RuleStepSequence, event: GameEvent) -> void:
	# 原使用牌 UID；响应恢复与换将边界均通过稳定身份复核。
	var card_uid: int = int(sequence.context.card_uid)
	# 当前处理区实体；异步等待期间已离区时，不重新执行牌效。
	var card: CardInstance = _find_processing_card(card_uid)
	# 使用牌共享上下文；空上下文表示父牌生命周期已被终止清理。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card == null or card_use_context.is_empty():
		event.cancel("processing_card_missing")
		sequence.finish()
		return
	# 当前目标 ID；-1表示一次处理整张牌的完整目标数组。
	var target_id: int = int(sequence.context.target_id)
	if target_id >= 0 and _active_card_resolutions.has(card_uid):
		# 当前逐目标参数；保存牌属性、伤害量和卡牌定义扩展上下文。
		var resolution_context: Dictionary = _active_card_resolutions[card_uid] as Dictionary
		sequence.context["destination"] = effect_resolver.resolve_target(card, int(resolution_context.get("actor_id", -1)), target_id, resolution_context)
		return
	# 整牌目标顺序；装备、延时牌与五谷等效果只执行一次。
	var whole_targets: Array[int] = []
	for target_id_variant: Variant in card_use_context.get("target_ids", []) as Array:
		whole_targets.append(int(target_id_variant))
	sequence.context["whole_target_ids"] = whole_targets
	sequence.context["destination"] = effect_resolver.resolve(card, int(card_use_context.get("actor_id", -1)), whole_targets)


## 子牌效序列完成后提交content结果、目标生命周期及父事件暂停释放。
func _finish_card_content_sequence(sequence: RuleStepSequence, event: GameEvent) -> void:
	# 当前处理区牌；牌效可能在其子流程中已经由专用恢复入口完成整牌收尾。
	var card_uid: int = int(sequence.context.card_uid)
	# 当前目标 ID；逐目标After只由同步完整目标或响应恢复入口之一提交。
	var target_id: int = int(sequence.context.target_id)
	# 效果目的地；pending表示卡牌专用恢复入口仍负责目标完成。
	var destination: String = str(sequence.context.get("destination", "discard"))
	# 当前共享上下文；专用异步恢复可能已经写入最终目的地与完成标记。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if target_id >= 0:
		if destination != "pending" and _active_card_resolutions.has(card_uid):
			# 活动目标游标；生命周期完成后清除当前目标，父Use事件方可进入下一目标。
			var resolution_context: Dictionary = _active_card_resolutions[card_uid] as Dictionary
			_finish_card_target_lifecycle(card_uid, target_id, event.event_id)
			resolution_context["current_target_id"] = -1
			_active_card_resolutions[card_uid] = resolution_context
		event.result = {"target_id":target_id, "destination":destination}
	else:
		# 整牌目标与最终区域；异步选择已提交结果时以共享上下文为权威。
		var whole_targets: Array = card_use_context.get("target_ids", []) as Array
		if bool(card_use_context.get("content_complete", false)):
			destination = str(card_use_context.get("destination", destination))
		elif destination != "pending":
			card_use_context["destination"] = destination
			card_use_context["content_complete"] = true
			_card_use_contexts[card_uid] = card_use_context
		event.result = {"target_ids":whole_targets.duplicate(), "destination":destination}


## 所有牌效、目标After及其子技能都完成后释放content子事件。
func _release_card_content_sequence(_sequence: RuleStepSequence, pause_token_id: int) -> void:
	if event_scheduler != null and event_scheduler.pause_registry != null:
		event_scheduler.pause_registry.resolve(pause_token_id, "card_effect_children_complete")


## 在全部 content 子事件完成后安排唯一 contentAfter，禁止响应恢复路径重复创建。
func _card_use_step_enqueue_content_after(event: GameEvent, scheduler: EventScheduler) -> void:
	# 使用牌最终区域；正常效果已在上一阶段写入，缺失时按处理区牌的默认弃置语义收口。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前使用牌共享上下文；最终区域和后置状态只从该生命周期读取。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 最终区域名称；pending 防御性回退为默认 discard，避免处理区实体永久滞留。
	var destination: String = str(card_use_context.get("destination", "discard"))
	if destination == "pending":
		destination = "discard"
		card_use_context["destination"] = destination
		_card_use_contexts[card_uid] = card_use_context
	card_use_event_service.enqueue_content_after(scheduler, event, _execute_card_content_after_event, destination)


## 写入唯一 contentAfter 结果；该子事件到达即证明全部同步效果与选择 token 已完成。
func _execute_card_content_after_event(event: GameEvent, _scheduler: EventScheduler) -> void:
	event.result = {"destination":str(event.context.get("destination", "discard")), "card_uid":int(event.context.get("card_uid", -1))}


## 在全部目标内容和 contentAfter 完成后派发 useCardEnd 与 useCardAfter；被取消的整牌改派 useCardCancelled。
func _card_use_step_finish_lifecycle(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 当前使用牌 UID；生命周期尾部只允许执行一次。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 使用牌共享上下文；后置弃牌尚未执行，因此材料仍可通过 UID 关联处理区记录。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	if card_use_context.is_empty() or bool(card_use_context.get("lifecycle_finished", false)):
		return
	# 结束窗口数据；取消理由沿用前置窗口结果，材料收尾仍由CardUseEvent.after负责。
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid)
	card_use_context["lifecycle_finished"] = true
	_card_use_contexts[card_uid] = card_use_context
	if bool(card_use_context.get("cancelled", false)):
		timing_data["reason"] = str(card_use_context.get("cancel_reason", "cancelled"))
		_run_card_lifecycle_timings(card_uid, -1, event.event_id, ["useCardCancelled"], timing_data)
	else:
		_run_card_lifecycle_timings(card_uid, -1, event.event_id, ["useCardEnd", "useCardAfter"], timing_data)

## CardUseEvent 主体最后一步：把默认弃牌放入 after 队列，其他终点只清理共享上下文。
func _card_use_step_prepare_after(event: GameEvent, scheduler: EventScheduler) -> void:
	# 使用牌最终区域；只有仍在 processing 且终点为 discard 时创建 orderingDiscard。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 当前使用牌共享上下文；父事件结果在清理字典前从这里复制。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 最终区域名称；只有 discard 需要 after 回收，其他区域已由牌效移动完成。
	var destination: String = str(card_use_context.get("destination", "discard"))
	if destination == "discard" and _find_processing_card(card_uid) != null:
		card_use_event_service.enqueue_ordering_discard(scheduler, event, _execute_ordering_discard_event)
	else:
		_active_card_resolutions.erase(card_uid)
		_card_use_contexts.erase(card_uid)
	event.result = {
		"destination":destination,
		"target_ids":(card_use_context.get("target_ids", []) as Array).duplicate(),
		"excluded_target_ids":(card_use_context.get("excluded_target_ids", []) as Array).duplicate(),
		"direct_hit_target_ids":(card_use_context.get("direct_hit_target_ids", []) as Array).duplicate(),
		"custom_args":(card_use_context.get("custom_args", {}) as Dictionary).duplicate(true),
	}


## orderingDiscard 内容：创建真实 cardsDiscard 子事件；父 CardUseEvent 保持在 after 队列直到移动完成。
func _execute_ordering_discard_event(event: GameEvent, scheduler: EventScheduler) -> void:
	# cardsDiscard 上下文；材料 UID 与原 CardUseEvent ID 可供移动历史和回放建立完整关联。
	var discard_context: Dictionary = event.context.duplicate(true)
	discard_context["from_zone"] = "processing"
	discard_context["to_zone"] = "discard_pile"
	discard_context["reason"] = "ordering_discard"
	scheduler.create_child(event.event_id, "cardsDiscard", "card_move", [_execute_cards_discard_event], discard_context)


## cardsDiscard 内容：把仍在处理区的原使用牌移动到弃牌堆，并清理该牌全部运行时游标与暂停索引。
func _execute_cards_discard_event(event: GameEvent, _scheduler: EventScheduler) -> void:
	# 当前实体材料 UID；基础使用牌只有一个，服务接口已经保留多材料数组供后续扩展逐项移动。
	var card_uid: int = int(event.context.get("card_uid", -1))
	# 仍处于处理区的材料实体；为空表示已被其他规则移动，不再重复弃置。
	var card: CardInstance = _find_processing_card(card_uid)
	if bool(event.context.get("virtual_proxy", false)):
		# 虚拟牌材料 UID；逻辑代理本身不会进入弃牌堆，只有玩家实际选择的实体材料按顺序弃置。
		var material_card_uids: Array[int] = _int_array(event.context.get("material_card_uids", []) as Array)
		# 已弃置材料 UID；等待期间被其他规则移走的材料不会重复移动。
		var discarded_material_uids: Array[int] = []
		_ensure_card_movement()
		for material_card_uid: int in material_card_uids:
			# 当前仍在处理区的材料；代理 UID 与材料 UID 分离，不会误删逻辑牌。
			var material_card: CardInstance = _find_processing_card(material_card_uid)
			if material_card != null and _move_card_with_timings(material_card, "discard_pile", -1, "ordering_discard", event.event_id) != null:
				discarded_material_uids.append(material_card_uid)
		if card != null:
			# 逻辑代理返回 void；它只为效果链提供稳定 UID 和无花色【杀】定义，不属于任何持久卡牌区域。
			_move_card_with_timings(card, "void", -1, "virtual_card_complete", event.event_id)
		event.result = {"card_uids":discarded_material_uids, "to_zone":"discard_pile", "virtual_card_uid":card_uid}
		_active_card_resolutions.erase(card_uid)
		_card_use_contexts.erase(card_uid)
		_check_game_over()
		return
	if card != null:
		_ensure_card_movement()
		# 弃牌移动；事件 ID 直接使用真实 cardsDiscard 子事件，不再创建迁移期摘要。
		var move: CardMoveEvent = _move_card_with_timings(card, "discard_pile", -1, "ordering_discard", event.event_id)
		if move != null:
			event.result = {"card_uids":[card_uid], "move_id":move.move_id, "to_zone":"discard_pile"}
	_active_card_resolutions.erase(card_uid)
	_card_use_contexts.erase(card_uid)
	_check_game_over()


## 返回当前使用牌是否对指定目标具有 directHit；响应与无懈查询只读该标记，不修改事件游标。
func is_card_target_direct_hit(card_uid: int, target_id: int) -> bool:
	# 当前 CardUseEvent 共享上下文；不存在时表示响应牌或兼容调用没有直击语义。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	return (card_use_context.get("direct_hit_target_ids", []) as Array).has(target_id)


## 返回指定响应者是否被父使用牌的直击集合禁止响应；父牌UID缺失时保持普通响应规则。
func is_response_blocked_by_direct_hit(responder_id: int, context: Dictionary) -> bool:
	# 响应父牌UID；所有标准【杀】、决斗、群体锦囊与装备响应上下文均使用此稳定字段。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	return parent_card_uid >= 0 and is_card_target_direct_hit(parent_card_uid, responder_id)


## 执行铁索连环等允许重铸的牌：弃置该牌并摸一张牌。
func _execute_recast(actor_id: int, card_uid: int) -> bool:
	# 重铸玩家状态；必须处于自己的出牌阶段。
	var actor: PlayerState = state.get_player(actor_id)
	if state.current_phase != "play" or actor == null:
		return _reject("当前不能重铸。")
	# 被重铸手牌；不存在时拒绝。
	var card: CardInstance = actor.find_hand_card(card_uid)
	if card == null:
		return _reject("重铸牌不在手牌中。")
	# 卡牌定义；只有 recast 标记为 true 的牌可重铸。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	if not bool(definition.get("recast", false)):
		return _reject("该卡牌不能重铸。")
	return recast_hand_card(actor_id, card_uid)


## 令指定角色重铸一张普通手牌；技能可重铸任意手牌，卡牌自身主动重铸仍由 _execute_recast 预先检查 recast 元数据。
func recast_hand_card(player_id: int, card_uid: int) -> bool:
	# 单张重铸包装；显式构造类型化数组，避免无类型字面量在类型化参数上产生隐式转换。
	var card_uids: Array[int] = [card_uid]
	return _recast_hand_cards_common(player_id, card_uids, true) > 0


## 令指定角色一次重铸多张普通手牌：先把全部牌置入弃牌堆，再按实际重铸张数一次性补摸等量的牌。
## 与逐张调用 recast_hand_card 的差别有两点：补摸是一次等量完成；日志只写一条“重铸了N张牌”。
## 返回实际完成重铸的张数；无效角色或不在手牌中的项被跳过，全部无效时返回0。技能据此判断“本次重铸是否真的发生”。
func recast_hand_cards(player_id: int, card_uids: Array[int]) -> int:
	return _recast_hand_cards_common(player_id, card_uids, false)


## 重铸的统一实现；single_card_log 为 true 时保持单张重铸既有的日志文本、返回值与补摸语义逐字不变。
## 参数 card_uids 允许重复：同一实体在第一次移动后已不再是手牌，重复项自然被跳过，不会重复补摸。
func _recast_hand_cards_common(player_id: int, card_uids: Array[int], single_card_log: bool) -> int:
	if state == null or state.game_over:
		return 0
	# 重铸角色；死亡、离场或不存在的角色不能移动手牌或获得补牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return 0
	# 实际完成重铸的实体张数；只有真正从手牌移出的牌才计入补摸数量。
	var recast_count: int = 0
	# 已处理实体UID；同一批中的重复项只处理一次。
	var processed_uids: Dictionary = {}
	for card_uid: int in card_uids:
		if processed_uids.has(card_uid):
			continue
		processed_uids[card_uid] = true
		# 被重铸实体；只接受普通手牌区，木牛“粮”、装备和判定牌均不会被 find_hand_card 返回。
		var card: CardInstance = player.find_hand_card(card_uid)
		if card == null:
			continue
		# 卡牌显示定义；日志名称遵循当前三国杀/崩铁名称设置，不暴露实体 UID。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		player.take_hand_card(card.uid)
		# 重铸不是“弃置”：该牌只是被置入弃牌堆，不构成一次弃置牌动作，也不派发 cardsDiscardedBatchAfter，
		# 因此不会触发【泛音】等“当你弃置牌时”类效果，也不会额外写一条“弃置了”日志；
		# 同一张牌同样不算“使用”或“打出”，所以这里不派发 useCard/respond，也不进入处理区。
		_move_to_discard(card, -2, false)
		if single_card_log:
			add_log("%s重铸了%s。" % [format_player_state_log_name(player), GameSettings.resolve_card_name(definition)])
		recast_count += 1
	if recast_count <= 0:
		return 0
	if not single_card_log:
		add_log("%s重铸了%d张牌。" % [format_player_state_log_name(player), recast_count])
	# 重铸牌离开最后手牌时产生的技能或装备触发必须先完整结算，随后再执行固定补摸。
	# 多张重铸同样先完成全部移牌再补摸，因此补摸张数随续接上下文传递，屏障清空后一次摸足。
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("recast_draw", {"player_id":player_id, "count":recast_count})
		return recast_count
	draw(player_id, recast_count)
	return recast_count


## 结束出牌阶段；超过手牌上限时由当前角色自主选择足量手牌弃置。
func _end_play_phase(player_id: int, complete_use_phase: bool = true, hide_controls_during_transition: bool = false) -> void:
	if state.current_player_id != player_id or state.current_phase != "play":
		_reject("当前不能结束出牌阶段。")
		return
	_ai_drive_token += 1
	if complete_use_phase and _started_phase_lifecycles.has("%d:phaseUse" % player_id):
		_finish_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_end_play_phase").bind(player_id, false, hide_controls_during_transition))
		return
	# 跳过阶段不应在流程延时内继续以 play 快照呈现，否则本地手牌与结束回合按钮会短暂闪现。
	var transition_phase: String = "play"
	if hide_controls_during_transition:
		state.current_phase = "play_skipped"
		transition_phase = "play_skipped"
	# 等待中的额外出牌阶段；当前阶段必须先完整结束，再重新建立独立的 phaseUse 生命周期与出牌请求。
	var pending_extra_play_phases: int = int(_extra_play_phase_counts.get(player_id, 0))
	if pending_extra_play_phases > 0:
		_consume_extra_play_phase(player_id)
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_start_extra_play_phase").bind(player_id))
		return
	# 独立出牌阶段没有额外阶段排队时直接恢复原回合；不能进入阶段角色自己的弃牌或结束阶段。
	if int(_active_independent_play_phase.get("player_id", -1)) == player_id and _active_extra_play_phase_context.is_empty():
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_complete_active_independent_play_phase"))
		return
	# 当前出牌阶段的稳定后继；额外阶段优先使用自身上下文，转换后的主要阶段使用原阶段队列后继。
	var return_point: String = ""
	if int(_active_extra_play_phase_context.get("player_id", -1)) == player_id:
		return_point = str(_active_extra_play_phase_context.get("return_point", ""))
	elif int(_active_converted_play_phase_context.get("player_id", -1)) == player_id:
		return_point = str(_active_converted_play_phase_context.get("return_point", ""))
	_active_extra_play_phase_context.clear()
	_active_converted_play_phase_context.clear()
	_extra_play_phase_returns_to_finish.erase(player_id)
	# 判定阶段转换出的出牌阶段结束后进入原摸牌阶段槽位；该槽位若同样被转换，会再次建立普通出牌阶段。
	if return_point == "draw":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_enter_draw_phase").bind(player_id))
		return
	# 摸牌阶段转换出的出牌阶段结束后进入原正常出牌阶段；连续play到play仍是两个独立普通阶段。
	if return_point == "play":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_enter_play_phase").bind(player_id))
		return
	# 弃牌阶段内获得的额外出牌阶段执行完毕后直接进入结束阶段，不重复弃牌。
	if return_point == "finish":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_enter_finish_phase").bind(player_id))
		return
	# 回合结束时插入的额外出牌阶段完成后直接完成已经派发过phaseEnd的回合尾部，不重复结束阶段时机。
	if return_point == "turn_complete":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_complete_finish_turn").bind(player_id))
		return
	# 独立阶段内追加的额外出牌阶段全部结束后恢复创建它的原回合，不进入阶段角色的普通弃牌阶段。
	if return_point == "independent_complete":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_complete_active_independent_play_phase"))
		return
	_schedule_phase_transition(player_id, transition_phase, Callable(self, "_enter_discard_phase").bind(player_id))


## 进入弃牌阶段并在需要时创建强制选牌请求；无需弃牌时仍保留一个阶段间隔再进入结束阶段。
func _enter_discard_phase(player_id: int, change_completed: bool = false) -> void:
	if _is_main_phase_converted_to_play(player_id, "discard"):
		_start_converted_main_phase_as_play(player_id, "discard", "finish")
		return
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":"play", "to_phase":"discard"}, _current_turn_event_id, Callable(self, "_enter_discard_phase").bind(player_id, true))
		return
	state.current_phase = "discard"
	state.phase_index = 4
	_record_runtime_event("phaseDiscard", "phase", {"player_id":player_id})
	# 永久跳过弃牌阶段机缘；通过统一跳过入口派发Skipped时机并安排唯一的结束阶段后继。
	if has_acquired_opportunity_permanent_phase_skip(player_id, "discard"):
		skip_current_main_phase(player_id, "discard", "opportunity_permanent_skip")
		return
	_begin_phase_lifecycle("phaseDiscard", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_continue_turn_after_discard_phase_begin").bind(player_id), Callable(self, "_finish_turn").bind(player_id))


## 完成弃牌阶段主体；Begin选择或阶段结束时机恢复后均从此入口安全续接，不会重复创建强制弃牌请求。
func _continue_turn_after_discard_phase_begin(player_id: int) -> void:
	if state == null or state.game_over or has_pending_card_choice() or state.current_player_id != player_id or state.current_phase != "discard":
		return
	# 当前弃牌阶段生命周期键；只有仍处于Begin之后的活动生命周期才执行手牌上限计算。
	var lifecycle_key: String = "%d:%s" % [player_id, "phaseDiscard"]
	if not _started_phase_lifecycles.has(lifecycle_key):
		_finish_turn(player_id)
		return
	# End或After选择恢复时阶段主体已经完成，只需让_finish_turn继续生命周期游标并安排后继。
	if not _is_phase_lifecycle_body_active("phaseDiscard", player_id):
		_finish_turn(player_id)
		return
	# 当前玩家状态；弃牌候选只来自其手牌区。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	# 需要弃置的手牌数；体力为负时手牌上限按0处理。
	var discard_count: int = maxi(player.hand.size() - player.get_hand_limit(), 0)
	if discard_count > 0:
		# 自身手牌候选；选择者就是牌的所有者，因此全部展示正面。
		var candidates: Array[Dictionary] = _build_player_zone_candidates(player_id, player_id, true, false, false)
		# 弃牌阶段恢复上下文；延迟提交后按 UID 弃置并完成回合。
		var context: Dictionary = {"kind":"discard_phase", "player_id":player_id, "discard_count":discard_count}
		# 选择结果；AI 也先获得同一请求，再从合法动作中提交指定数量的牌。
		var selected_uids: Array[int] = request_card_choice(player_id, "弃牌阶段", "请选择%d张手牌弃置" % discard_count, candidates, discard_count, discard_count, false, context)
		if has_pending_card_choice():
			return
		for selected_uid: int in selected_uids:
			discard_card_from_hand(player_id, selected_uid)
		add_log("%s在弃牌阶段完成弃置。" % format_player_state_log_name(player))
		# 最后一张手牌产生的嵌套技能必须先结算；恢复入口会重新计算为无需弃牌，再安全进入阶段End与After。
		if _has_nested_settlement_barrier():
			return
	_finish_turn(player_id)


## 为当前回合角色开始一个独立的额外出牌阶段；阶段次数、【杀】次数与技能阶段计数都从新阶段重新计算。
func _start_extra_play_phase(player_id: int, change_completed: bool = false) -> void:
	# 额外阶段角色；角色在阶段交界死亡时不再继续行动，统一交给死亡后的回合转交入口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	# 来源阶段；普通出牌阶段追加时为play，弃牌阶段插入时为discard。
	var previous_phase: String = state.current_phase
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"play", "extra_phase":true}, _current_turn_event_id, Callable(self, "_start_extra_play_phase").bind(player_id, true))
		return
	state.current_phase = "play"
	state.phase_index = 3
	# 【杀】的基础限制按出牌阶段计算；额外出牌阶段必须恢复为0，不能沿用本回合前一阶段的次数。
	player.slash_count = 0
	# 阶段限次牌使用历史；额外阶段必须从空历史开始，回合级【酒】与完整用牌记录仍保留在 card_use_history。
	player.play_phase_card_use_history.clear()
	player.play_phase_card_use_limit_exempt_history.clear()
	if reincarnation_skill_service != null:
		reincarnation_skill_service.on_play_phase_started(player_id)
	_record_runtime_event("phaseUse", "phase", {"player_id":player_id, "extra_phase":true}, {}, _current_turn_event_id)
	_begin_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number, "extra_phase":true}, _current_turn_event_id, Callable(self, "_resume_play_phase_body").bind(player_id), Callable(self, "_end_play_phase").bind(player_id, false))


## 恢复玩家提交的弃牌阶段选择；全部 UID 校验成功后结束当前回合。
func _continue_discard_phase_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 弃牌角色 ID；必须与创建请求时的当前回合角色一致。
	var player_id: int = int(context.get("player_id", -1))
	# 弃牌角色状态；用于记录永久语义日志。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	for selected_uid: int in selected_uids:
		discard_card_from_hand(player_id, selected_uid)
	add_log("%s在弃牌阶段完成弃置。" % format_player_state_log_name(player))
	# 弃牌移动触发选择时保持阶段主体游标；选择完成后由统一阶段恢复入口继续，而不是提前发布阶段结束时机。
	if _has_nested_settlement_barrier():
		return
	_finish_turn(player_id)


## 完成当前阶段后安排进入结束阶段；所有来源共用该入口，避免同步连跑多个阶段。
func _finish_turn(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id:
		return
	# 弃牌阶段先完整完成End与After；任一完成时机产生选择时保留生命周期游标等待恢复。
	if state.current_phase == "discard" and _started_phase_lifecycles.has("%d:phaseDiscard" % player_id):
		_finish_phase_lifecycle("phaseDiscard", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_finish_turn").bind(player_id))
		return
	var pending_extra_play_phases: int = int(_extra_play_phase_counts.get(player_id, 0))
	if state.current_phase == "discard" and pending_extra_play_phases > 0:
		_consume_extra_play_phase(player_id)
		_schedule_phase_transition(player_id, state.current_phase, Callable(self, "_start_extra_play_phase").bind(player_id))
		return
	_schedule_phase_transition(player_id, state.current_phase, Callable(self, "_enter_finish_phase").bind(player_id))


## 进入结束阶段并派发完整结束时机；异步技能选择完成后从唯一尾部入口继续。
func _enter_finish_phase(player_id: int, change_completed: bool = false) -> void:
	# 进入函数前的阶段；只有实际进入过弃牌阶段才派发其 End 与 After，翻面跳回合不会伪造弃牌结束。
	var previous_phase: String = state.current_phase
	if previous_phase == "discard" and _started_phase_lifecycles.has("%d:phaseDiscard" % player_id):
		_finish_phase_lifecycle("phaseDiscard", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_enter_finish_phase").bind(player_id))
		return
	if not change_completed:
		_change_phase_then("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"finish"}, _current_turn_event_id, Callable(self, "_enter_finish_phase").bind(player_id, true))
		return
	state.current_phase = "finish"
	state.phase_index = 5
	_record_runtime_event("phaseJieshu", "phase", {"player_id":player_id})
	_begin_phase_lifecycle("phaseJieshu", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_run_finish_phase_body").bind(player_id), Callable(self, "_run_finish_phase_tail").bind(player_id))


## 结束阶段主体窗口完全结束后才派发End与After。
func _run_finish_phase_body(player_id: int) -> void:
	_run_phase_notification("phaseJieshu", player_id, {"turn_number":state.turn_number}, Callable(self, "_finish_phase_lifecycle").bind("phaseJieshu", player_id, {"turn_number":state.turn_number}, _current_turn_event_id, Callable(self, "_run_finish_phase_tail").bind(player_id)))


## 完整结束阶段之后才发布回合结束窗口；旧兼容事件也各占一个等待步骤。
func _run_finish_phase_tail(player_id: int) -> void:
	_record_runtime_event("phaseEnd", "phase", {"player_id":player_id})
	_run_phase_notification("phaseEnd", player_id, {"turn_number":state.turn_number}, Callable(self, "_run_phase_notification").bind("phase_finish", player_id, {}, Callable(self, "_finish_phase_triggers_completed").bind(player_id)))


## 独立插入阶段仍使用其正式完成接口；普通窗口无需额外恢复标记。
func _finish_phase_triggers_completed(player_id: int) -> void:
	_continue_after_finish_phase_triggers(player_id)


## 在phaseEnd技能全部恢复后选择额外出牌阶段或正常回合尾部；phaseEnd只派发一次。
func _continue_after_finish_phase_triggers(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id or has_pending_card_choice():
		return
	# 回合结束时登记的额外出牌阶段先执行；其活动上下文会在结束后直接调用_complete_finish_turn。
	if int(_extra_play_phase_counts.get(player_id, 0)) > 0:
		_consume_extra_play_phase(player_id)
		_schedule_phase_transition(player_id, state.current_phase, Callable(self, "_start_extra_play_phase").bind(player_id))
		return
	_complete_finish_turn(player_id)


## 完成已经派发过 phaseEnd 的回合尾部；结束阶段异步技能恢复时只进入本函数，避免重复触发结束时机。
func _complete_finish_turn(player_id: int) -> void:
	# 回合尾部可能从额外出牌阶段返回；恢复结束阶段展示语义，后续节奏守卫才能稳定进入下一回合。
	state.current_phase = "finish"
	state.phase_index = 5
	# 本回合主要阶段转换在结束阶段后失效；下一回合即使属于同一角色也必须重新由技能建立。
	_main_phase_play_conversions.erase(player_id)
	if int(_active_converted_play_phase_context.get("player_id", -1)) == player_id:
		_active_converted_play_phase_context.clear()
	# 清理在本回合开始时已经锁定到期的手牌视为效果；翻面跳过回合也属于该角色下个回合结束。
	_expire_hand_view_as_effects_for_turn(player_id)
	# 通知全部卡牌定义清理其回合持续状态；控制器不识别具体卡牌变量。
	_notify_card_definitions_turn_ended(player_id, false)
	_record_runtime_event("phaseAfter", "phase", {"player_id":player_id})
	_run_phase_notification("phaseAfter", player_id, {"turn_number":state.turn_number}, Callable(self, "_continue_after_phase_after").bind(player_id))


## 在 phaseAfter 的全部技能与异步结果结束后计算轮末边界并安排下一回合；该入口不会重复发布回合结束时机。
func _continue_after_phase_after(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id:
		return
	_check_game_over()
	if state.game_over:
		return
	# 本轮首名在场座次；一号位死亡或离场时顺延，用于判断普通轮转是否已经回到轮锚点。
	var round_anchor_player: PlayerState = null
	for candidate_player: PlayerState in state.players:
		if candidate_player != null and candidate_player.alive and not candidate_player.out_of_game:
			round_anchor_player = candidate_player
			break
	# 当前正常下家；交换座位后直接读取新数组顺序，因此机缘换位会立即改变下一回合角色。
	var normal_next_player: PlayerState = state.get_next_alive_player(player_id)
	# 普通轮末边界；额外回合不会重复触发轮末机缘保底。
	var is_round_boundary: bool = not _current_turn_is_extra and round_anchor_player != null and normal_next_player != null and normal_next_player.player_id == round_anchor_player.player_id
	if is_round_boundary:
		# “直到本轮结束”的角色在轮末机缘和下一轮下家计算之前返回，确保恢复后的完整座次参与后续模式规则。
		_restore_round_limited_out_of_game_players(state.round_number + 1)
		if _has_nested_settlement_barrier():
			_defer_rule_continuation("round_end_restore", {"finished_player_id":player_id})
			return
		_continue_round_end_after_restore(player_id)
		return
	_schedule_phase_transition(player_id, "finish", Callable(self, "_start_queued_or_normal_turn").bind(player_id))


## 轮末限时离场角色全部返回后触发轮末机缘并按恢复后的座次进入下一轮。
func _continue_round_end_after_restore(finished_player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != finished_player_id:
		return
	if opportunity_system != null and opportunity_system.try_trigger_at_round_end(finished_player_id):
		return
	_schedule_phase_transition(finished_player_id, "finish", Callable(self, "_start_queued_or_normal_turn").bind(finished_player_id))


## 在回合结束后优先执行额外回合，并在全部额外回合完成后恢复原本的正常下家。
func _start_queued_or_normal_turn(finished_player_id: int) -> void:
	# 当前正常轮转的下家；只有从普通回合第一次进入额外回合链时才压入恢复栈。
	var normal_next_player: PlayerState = state.get_next_alive_player(finished_player_id)
	while not _extra_turn_queue.is_empty():
		# 队首额外回合角色；等待期间死亡或离场时直接跳过，不影响后续队列与正常下家。
		var extra_player_id: int = _extra_turn_queue.pop_front()
		var extra_player: PlayerState = state.get_player(extra_player_id)
		if extra_player == null or not extra_player.alive or extra_player.out_of_game:
			continue
		if not _current_turn_is_extra:
			_extra_turn_resume_player_ids.append(normal_next_player.player_id if normal_next_player != null else -1)
		_current_turn_is_extra = true
		_start_turn(extra_player_id)
		return
	if _current_turn_is_extra:
		# 额外回合链的恢复角色；栈为空时防御性回退到当前角色的正常下家。
		var resume_player_id: int = _extra_turn_resume_player_ids.pop_back() if not _extra_turn_resume_player_ids.is_empty() else -1
		_current_turn_is_extra = not _extra_turn_resume_player_ids.is_empty()
		# 回合开始前机缘排队的额外回合链结束：恢复原定角色的回合，不重复轮递增与回合开始前机缘判定。
		if not _current_turn_is_extra and not _pending_turn_start_context.is_empty():
			# 待开始回合上下文副本；先清空字段，续接若立即触发新流程不会与旧上下文混淆。
			var pending_context: Dictionary = _pending_turn_start_context.duplicate()
			_pending_turn_start_context.clear()
			var pending_player_id: int = int(pending_context.get("player_id", -1))
			var pending_player: PlayerState = state.get_player(pending_player_id) if pending_player_id >= 0 else null
			if pending_player != null and pending_player.alive and not pending_player.out_of_game:
				# 机缘排队期间的额外回合链已经结束；机缘不再重复判定，但仍需给阿哈时刻一次判定机会。
				_continue_turn_start_prelude(pending_player_id, bool(pending_context.get("starts_new_round", false)), false, true)
				return
		var resume_player: PlayerState = state.get_player(resume_player_id) if resume_player_id >= 0 else null
		if resume_player == null or not resume_player.alive or resume_player.out_of_game:
			resume_player = state.get_next_alive_player(resume_player_id if resume_player_id >= 0 else finished_player_id)
		if resume_player != null:
			_start_turn(resume_player.player_id)
		return
	if normal_next_player != null:
		_start_turn(normal_next_player.player_id)


## 回合开始前机缘结束后立即执行机缘期间获得的额外回合；返回true表示流程已交给额外回合链，
## 该链最外层结束时按同一待开始角色继续建立回合事实，而不是恢复某名已结束角色的正常下家。
func _resume_pending_turn_after_extra_turns(pending_player_id: int, starts_new_round: bool) -> bool:
	# 待恢复的待开始回合上下文；只有仍处于额外回合链中才会被读取，恢复后立即清空。
	_pending_turn_start_context = {"player_id":pending_player_id, "starts_new_round":starts_new_round}
	while not _extra_turn_queue.is_empty():
		# 队首额外回合角色；等待期间死亡或离场时直接跳过，不影响后续队列。
		var extra_player_id: int = _extra_turn_queue.pop_front()
		var extra_player: PlayerState = state.get_player(extra_player_id)
		if extra_player == null or not extra_player.alive or extra_player.out_of_game:
			continue
		if not _current_turn_is_extra:
			_extra_turn_resume_player_ids.append(pending_player_id)
		_current_turn_is_extra = true
		_start_turn(extra_player_id)
		return true
	# 队列中没有可执行的额外回合；待开始回合由调用方直接建立。
	_pending_turn_start_context.clear()
	return false


## 在机缘全体选择与逆时针效果全部完成后恢复原有权威流程；组件不保存Callable或调用控制器私有游标。
func continue_after_opportunity(resume_kind: String, context: Dictionary) -> void:
	if state == null or state.game_over:
		return
	if resume_kind == "before_turn_start":
		# 回合开始前机缘的原定角色；该角色的回合事实尚未建立，此处才真正开始其回合。
		var pending_player_id: int = int(context.get("player_id", -1))
		if pending_player_id < 0:
			return
		# 机缘效果可能已经令该角色死亡或离场；此时不再开始其回合，直接按上一名角色的正常下家继续。
		var pending_player: PlayerState = state.get_player(pending_player_id)
		if pending_player == null or not pending_player.alive or pending_player.out_of_game:
			_start_queued_or_normal_turn(state.current_player_id)
			return
		# 机缘期间获得的额外回合在回合开始前立即执行；全部完成后才建立原定角色的回合事实。
		var starts_new_round: bool = bool(context.get("starts_new_round", false))
		if _resume_pending_turn_after_extra_turns(pending_player_id, starts_new_round):
			return
		# 机缘已经结算完毕，同一条回合开始前事件链继续判定阿哈时刻；此处不得重复判定机缘。
		_continue_turn_start_prelude(pending_player_id, starts_new_round, false, true)
		return
	if resume_kind == "round_end":
		# 完成轮末机缘的原回合角色；必须仍是当前结束阶段角色，旧流程恢复请求才有效。
		var finished_player_id: int = int(context.get("finished_player_id", -1))
		if state.current_player_id == finished_player_id and state.current_phase == "finish":
			_schedule_phase_transition(finished_player_id, "finish", Callable(self, "_start_queued_or_normal_turn").bind(finished_player_id))
		return
	if resume_kind == "conquest_initial_opportunity":
		# 开局机缘完成后才建立玩家的第一回合，保证玩家固定先手且不会在选择期间提前推进AI。
		var first_player_id: int = int(context.get("first_player_id", -1))
		if first_player_id >= 0:
			_start_turn(first_player_id)
		return
	if resume_kind == "conquest_enemy_replacement":
		# 敌方新武将入场后的机缘结算完成：玩家回合继续，敌方回合则直接结束并交给玩家。
		_finish_conquest_replacement_turn(context)


## 返回当前对局模式是否挂载机缘组件；界面据此显示永久机缘历史，不依赖当前是否正在触发选择流程。
func is_opportunity_enabled_for_current_match() -> bool:
	return state != null and (opportunity_enabled_mode_ids.has(state.match_mode) or opportunity_manual_mode_ids.has(state.match_mode))


## 当前回合角色在事件结算中死亡后转交回合；不触发正常结束阶段，但会清除只持续到本回合的酒加值。
func _advance_after_current_player_death(dead_player_id: int, interrupted_character_generation: int = -1) -> void:
	if state == null or state.game_over or state.current_player_id != dead_player_id or state.current_phase == "dead":
		return
	# 独立额外出牌阶段的角色死亡只中断该阶段；真实原回合会在恢复后继续自身尾部或死亡转交。
	if int(_active_independent_play_phase.get("player_id", -1)) == dead_player_id:
		_complete_active_independent_play_phase(true)
		return
	_ai_drive_token += 1
	# 已打开的出牌窗口属于死亡角色，必须在转交前取消，避免旧请求恢复后重新驱动已结束的回合。
	_cancel_active_play_choice("current_player_death")
	_main_phase_play_conversions.erase(dead_player_id)
	_extra_play_phase_counts.erase(dead_player_id)
	_extra_play_phase_return_points.erase(dead_player_id)
	_extra_play_phase_returns_to_finish.erase(dead_player_id)
	if int(_active_extra_play_phase_context.get("player_id", -1)) == dead_player_id:
		_active_extra_play_phase_context.clear()
	if int(_active_converted_play_phase_context.get("player_id", -1)) == dead_player_id:
		_active_converted_play_phase_context.clear()
	# 中断时机在阶段状态切换前派发，保证“直到本回合结束”的离场效果仍可识别正确回合号。
	# 被中断回合所属武将代次；换将模式可显式传入旧代次，普通死亡则读取当前死亡角色代次。
	var phase_over_character_generation: int = interrupted_character_generation
	if phase_over_character_generation < 0:
		# 当前死亡角色；普通模式没有先换将，因此其最新代次就是被中断回合所属代次。
		var dead_player: PlayerState = state.get_player(dead_player_id)
		phase_over_character_generation = dead_player.character_generation if dead_player != null else -1
	_run_phase_notification("phaseOver", dead_player_id, {"reason":"current_player_death", "turn_number":state.turn_number, "player_character_generation":phase_over_character_generation, "source_character_generation":phase_over_character_generation, "target_character_generation":phase_over_character_generation}, Callable(self, "_finish_death_turn_handoff").bind(dead_player_id))


## phaseOver及其子内容完成后提交中断状态，再按额外回合规则转交。
func _finish_death_turn_handoff(dead_player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != dead_player_id or state.current_phase == "dead":
		return
	_notify_card_definitions_turn_ended(dead_player_id, true)
	# 死亡中断标志防止响应、阶段回调和动作收尾重复安排下一回合。
	state.current_phase = "dead"
	state.phase_index = -1
	# 死亡回合仍需遵守已经排队的额外回合与额外回合链恢复顺序。
	_schedule_phase_transition(dead_player_id, "dead", Callable(self, "_start_queued_or_normal_turn").bind(dead_player_id))


## 当前回合角色移出游戏后立即中断本回合；不执行弃牌或结束阶段，但保留phaseOver供持续到回合结束的效果清理。
func _advance_after_current_player_out_of_game(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase == "removed":
		return
	# 独立额外出牌阶段的角色离场只结束当前插入阶段，不按其座次推进正常回合。
	if int(_active_independent_play_phase.get("player_id", -1)) == player_id:
		_complete_active_independent_play_phase(true)
		return
	_ai_drive_token += 1
	_cancel_active_play_choice("current_player_removed")
	_main_phase_play_conversions.erase(player_id)
	_extra_play_phase_counts.erase(player_id)
	_extra_play_phase_return_points.erase(player_id)
	_extra_play_phase_returns_to_finish.erase(player_id)
	if int(_active_extra_play_phase_context.get("player_id", -1)) == player_id:
		_active_extra_play_phase_context.clear()
	if int(_active_converted_play_phase_context.get("player_id", -1)) == player_id:
		_active_converted_play_phase_context.clear()
	# 回合中断时机先于阶段状态切换；离场技能可以在该时机恢复角色，但本回合仍按规则结束。
	_emit_rule_timing("phaseOver", player_id, player_id, player_id, {"reason":"current_player_removed", "turn_number":state.turn_number}, _current_turn_event_id)
	_notify_card_definitions_turn_ended(player_id, true)
	state.current_phase = "removed"
	state.phase_index = -1
	_schedule_phase_transition(player_id, "removed", Callable(self, "_start_queued_or_normal_turn").bind(player_id))


## 依次请求所有存活角色使用卡牌源码声明的濒死救援牌；已询问名单保证异步取消后不会重复询问同一角色。
## 救援只遍历一轮座次；同一响应者成功救援后若目标仍未达到1点体力，则立即继续询问该响应者，取消后再进入下一名。
func _resolve_dying(target_id: int, killer_id: int, rescue_start_override: int = -1, already_asked_rescuer_ids: Array[int] = []) -> void:
	# 濒死角色状态；可能需要多张桃才能将体力回复至1。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		# 先前伤害窗口已经使目标失效时，仍由明确出口完成原伤害，不依靠无选择状态猜测。
		return
	# 已经恢复正体力的角色不再建立救援请求；若旧流程仍在队列中则统一完成脱离濒死结算。
	if target.hp > 0:
		if target.dying or state.dying_queue.has(target_id):
			_finish_dying_rescue(target_id)
		return
	# 是否首次进入本次濒死流程；连续出桃与取消后的座次推进都复用同一流程，不重复创建回放事件。
	var is_new_dying_flow: bool = not state.dying_queue.has(target_id)
	if is_new_dying_flow:
		# 首次濒死使用独立阶段游标；任一时机创建选择后先结束该技能完整顺序效果，再回来登记求桃流程。
		# 游标由通用RuleStepSequence持有，不再写入专用濒死恢复数组。
		_continue_dying_start({"target_id":target_id, "killer_id":killer_id, "event_data":{"hp":target.hp, "required_recover":1 - target.hp}})
		return
	# 单轮救援由步骤服务保存座次与已消费牌，响应后的子结算完成后再检查体力。
	var rescue_service: RefCounted = DYING_RESOLUTION_SERVICE_SCRIPT.new(self)
	rescue_service.rescue(target_id, killer_id, rescue_start_override, already_asked_rescuer_ids)


## 从dyingBefore开始按稳定游标建立一次新濒死流程；嵌套选择期间不提前创建求桃请求或死亡结算。
func _continue_dying_start(context: Dictionary) -> void:
	if state == null or state.game_over:
		return
	# 开始内容服务；原窗口结果与恢复位置由规则序列持有。
	var dying_service: RefCounted = DYING_RESOLUTION_SERVICE_SCRIPT.new(self)
	dying_service.begin(context)


## 恢复濒死救援响应；成功使用桃或酒后重新检查目标体力并继续同一救援轮。
func _continue_dying_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 响应对应的救援内容；重开或终局后原序列不存在时丢弃迟到输入。
	var sequence: RuleStepSequence = _rule_sequences.get(int(context.get("rescue_sequence_id", -1))) as RuleStepSequence
	if sequence == null:
		return
	sequence.context["selected_uids"] = selected_uids.duplicate()
	sequence.context["response_context"] = context.duplicate(true)
	sequence.context["material_uids"] = _resolved_equipment_material_uids.duplicate()
	sequence.context["response_skill_id"] = _resolved_response_skill_id


## 返回当前响应者在指定濒死关系下可使用的全部救援响应模式与显示名。
func _get_dying_response_options(responder_id: int, dying_player_id: int) -> Array[Dictionary]:
	# 救援选项结果；按卡牌数据库稳定扫描顺序去重响应模式。
	var result: Array[Dictionary] = []
	# 已登记模式集合；多个卡牌定义提供同一模式时只创建一个响应类别。
	var registered_patterns: Dictionary = {}
	for definition_variant: Variant in GameDatabase.card_definitions.values():
		# 当前卡牌源码；只读取纯查询钩子，不保存对局状态。
		var definition: CardDefinition = definition_variant as CardDefinition
		if definition == null:
			continue
		# 当前关系下的救援响应模式；空字符串表示本牌不能参与本次救援。
		var response_pattern: String = definition.get_dying_response_pattern(responder_id, dying_player_id)
		if response_pattern.is_empty() or registered_patterns.has(response_pattern):
			continue
		registered_patterns[response_pattern] = true
		var metadata: Dictionary = definition.get_metadata()
		result.append({"pattern":response_pattern, "name":str(metadata.get("original_name", definition.get_id()))})
	return result


## 把已消费的救援实体交回其卡牌源码；控制器不判断具体响应模式或牌名。
func _apply_dying_response_card(responder_id: int, dying_player_id: int, card: CardInstance) -> bool:
	if card == null:
		return false
	# 救援牌源码；不存在或拒绝当前角色关系时不修改体力。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	# 救援效果是否成功；只有实际回复已经由卡牌源码确认后才生成公开身份行为。
	var response_applied: bool = definition != null and definition.resolve_dying_response(self, responder_id, dying_player_id, card)
	if response_applied:
		# 濒死窗口中的【桃】属于“使用”而非普通打出，必须进入本回合用牌事实供回合结束技能查询。
		_record_card_used_this_turn(responder_id, card.definition_id)
		# 救援目标行为；【桃】沿用自身正向 target_result，【酒】因目标为本人会被身份模型自动忽略。
		ai_coordinator.observe_public_behavior(state.to_dict(-1, true), responder_id, definition.get_ai_profile(), [dying_player_id], local_human_player_id)
		# 濒死救援公开行为同步给远端客户端；网络只承载救援目标与只读 AI 配置，不含任何手牌内容。
		_broadcast_identity_behavior(responder_id, definition.get_ai_profile(), [dying_player_id])
	return response_applied


## 记录一名角色在当前全局回合中使用过一张逻辑牌；同名牌重复使用只保留一次存在性事实。
func _record_card_used_this_turn(player_id: int, definition_id: String) -> void:
	if player_id < 0 or definition_id.is_empty():
		return
	# 当前角色用牌集合；字典键保存逻辑定义ID，值只表达本回合已经发生过该事实。
	var used_cards: Dictionary = (_cards_used_this_turn_by_player.get(player_id, {}) as Dictionary).duplicate(true)
	used_cards[definition_id] = true
	_cards_used_this_turn_by_player[player_id] = used_cards


## 返回指定角色在当前全局回合中是否使用过某逻辑牌；供回合结束触发技能只读查询。
func has_used_card_this_turn(player_id: int, definition_id: String) -> bool:
	return bool((_cards_used_this_turn_by_player.get(player_id, {}) as Dictionary).get(definition_id, false))


## 返回指定角色在当前全局回合是否使用过某个逻辑牌族；普通、火与雷【杀】等共享组按统一配置合并判断。
func has_used_card_group_this_turn(player_id: int, card_group: String) -> bool:
	if player_id < 0 or card_group.is_empty():
		return false
	# 当前角色已使用的逻辑牌集合；字典只保存存在性事实，不依赖当前行动角色或出牌阶段。
	var used_cards: Dictionary = _cards_used_this_turn_by_player.get(player_id, {}) as Dictionary
	for definition_id_variant: Variant in used_cards.keys():
		# 已使用卡牌定义；未知旧ID按自身ID回退，避免存档兼容数据错误命中其他牌族。
		var definition_id: String = str(definition_id_variant)
		var definition: Dictionary = GameDatabase.get_card(definition_id)
		var used_card_group: String = str(definition.get("play_limit_group", definition_id))
		if used_card_group == card_group:
			return true
	return false


## 在角色体力恢复至1点或以上时统一结算求桃流程；状态、事件与日志在同一入口完成，父级卡牌或阶段随后才能继续。
func _finish_dying_rescue(target_id: int) -> void:
	if state == null or state.game_over:
		return
	# 完成内容服务；先清理本次濒死事实，再依次等待After、旧通知和伤害收尾。
	var dying_service: RefCounted = DYING_RESOLUTION_SERVICE_SCRIPT.new(self)
	dying_service.finish(target_id)


## 返回从指定玩家开始的存活角色行动顺序；用于濒死救援等必须按当前行动顺序处理的公共结算。
func _get_alive_players_in_action_order(start_player_id: int) -> Array[PlayerState]:
	# 行动顺序结果；最多包含每名存活角色一次，不会因环形座次重复加入。
	var result: Array[PlayerState] = []
	if state == null or state.players.is_empty():
		return result
	# 起始座次数组索引；无效玩家 ID 回退到一号位，保证异常状态仍可稳定完成结算。
	var start_index: int = 0
	for player_index: int in range(state.players.size()):
		if state.players[player_index].player_id == start_player_id:
			start_index = player_index
			break
	for seat_offset: int in range(state.players.size()):
		# 当前环形座次索引；从指定玩家开始依次越过数组末尾回到一号位。
		var player: PlayerState = state.players[(start_index + seat_offset) % state.players.size()]
		if player.alive:
			result.append(player)
	return result


## 执行死亡、身份公开、区域清理、奖惩和胜负检查。
func _resolve_death(victim_id: int, killer_id: int) -> void:
	# 死亡内容服务；所有前后时机都由原序列持有恢复位置。
	var death_service: RefCounted = preload("res://scripts/core/death_resolution_service.gd").new(self)
	death_service.begin(victim_id, killer_id)


## 为真实死亡或模式中的武将击败累计击杀；无来源伤害与自杀不归入任何角色的击杀数。
func _record_match_kill(killer_id: int, victim_id: int) -> void:
	if state == null or killer_id < 0 or killer_id == victim_id:
		return
	# 击杀来源角色；仅存在于本局状态中的角色可以获得结算统计，已死亡不影响其历史统计保留。
	var killer: PlayerState = state.get_player(killer_id)
	if killer != null:
		killer.total_kill_count += 1


## 返回一次击杀的最终死亡奖惩类型；先取身份规则的基础结论，再依次交给击杀者的技能实例复核改写。
## killer_id为伤害来源（无来源伤害为负值），victim_id为本次阵亡角色，mode_id为空时读取当前对局模式。
## 返回值语义与 IdentityRules.get_death_reward 一致，并额外接受技能声明的扩展类型（例如 draw_four）；
## 具体摸牌与弃牌仍由死亡结算组件统一执行，技能不得自行移动牌。
func resolve_death_reward(killer_id: int, victim_id: int, mode_id: String = "") -> String:
	if state == null:
		return ""
	# 阵亡角色权威状态；对象不存在时不产生任何奖惩。
	var victim: PlayerState = state.get_player(victim_id)
	if victim == null:
		return ""
	# 击杀来源角色；无来源伤害沿用身份规则的空奖惩结论。
	var killer: PlayerState = state.get_player(killer_id)
	# 本次模式ID；空值回退当前模式，避免每个调用方重复读取对局状态。
	var resolved_mode: String = mode_id if not mode_id.is_empty() else str(state.match_mode)
	# 身份规则基础奖惩；技能只能在该结论之上做整体覆盖。
	var reward: String = identity_rules.get_death_reward(killer, victim, resolved_mode)
	if killer == null:
		return reward
	# 阵亡者可序列化快照；字段均为规则层已掌握的稳定事实，不得转交AI评分或写入界面。
	var victim_snapshot: Dictionary = {
		"player_id":victim.player_id,
		"character_id":victim.character_id,
		"identity":victim.identity,
		"alive":victim.alive,
	}
	# 击杀者全部技能实例；按武将声明顺序逐项复核，后声明的技能可以覆盖先前结论。
	var killer_skills: Dictionary = skill_instances_by_player.get(killer.player_id, {}) as Dictionary
	for skill_variant: Variant in killer_skills.values():
		# 当前技能实例；空实例不参与改写。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null:
			continue
		# 技能改写结果；空字符串表示保留当前结论。
		var overridden_reward: String = skill.modify_death_reward(victim_snapshot, reward)
		if not overridden_reward.is_empty():
			reward = overridden_reward
	return reward


## 在单名敌人的死亡与父级目标尾部全部完成后恢复原流程；若死者正处于自己的回合，则按普通死亡中断转交下名存活角色。
func _finish_conquest_enemy_defeat(context: Dictionary) -> void:
	if state == null or state.game_over or conquest_mode == null:
		return
	# 本次已经完成退场的敌方稳定ID；只用于判断是否需要中断其自身回合，不承担层完成判定。
	var defeated_enemy_id: int = int(context.get("defeated_enemy_id", -1))
	if state.current_player_id == defeated_enemy_id:
		_advance_after_current_player_death(defeated_enemy_id, int(context.get("defeated_character_generation", -1)))
		return
	# 非当前角色阵亡不改变原阶段与父牌游标；统一结算管线会在本续接返回后继续排空外层事件。
	_emit_state()


## 在旧角色死亡、弃牌移动和伤害来源尾部全部结束后冻结旧回合，并等待表现层完成弃牌动画。
func _begin_conquest_enemy_replacement(context: Dictionary) -> void:
	if state == null or state.game_over or conquest_mode == null or _conquest_replacement_transition_active:
		return
	# 旧回合阶段；机缘完成后仍要依据击杀者所在回合决定继续出牌或直接换回玩家。
	var resume_phase: String = state.current_phase
	# 旧阶段游标；额外阶段或阶段中击杀恢复时必须保留，不能把玩家强制跳到新的回合起点。
	var resume_phase_index: int = state.phase_index
	var replacement_context: Dictionary = context.duplicate(true)
	replacement_context["resume_phase"] = resume_phase
	replacement_context["resume_phase_index"] = resume_phase_index
	_conquest_replacement_transition_active = true
	# 事件树全局结算屏障；从此刻到机缘全部完成，旧卡牌和旧伤害事件都不能越过换将边界继续执行。
	if event_scheduler != null and _conquest_replacement_settlement_pause_token < 0:
		_conquest_replacement_settlement_pause_token = event_scheduler.pause_global("conquest_replacement", "enemy_character_replacement")
	state.current_phase = "conquest_replacing"
	_emit_state()
	# 本等待不申请 GameplayPauseService；弃牌飞向弃牌堆的 Tween 与伤害反馈必须持续播放。
	if conquest_enemy_replacement_opportunity_delay_seconds <= 0.0 or game_flow_pacer == null:
		_complete_conquest_enemy_replacement(replacement_context)
		return
	game_flow_pacer.schedule(CONQUEST_REPLACEMENT_OPPORTUNITY_TASK_KEY, conquest_enemy_replacement_opportunity_delay_seconds, Callable(self, "_complete_conquest_enemy_replacement").bind(replacement_context), false)


## 在弃牌表现等待结束后为整组敌方创建下一层武将；此时旧伤害事件已经排空，新技能不会接收上一层角色的受伤时机。
func _complete_conquest_enemy_replacement(context: Dictionary) -> void:
	if state == null or state.game_over or conquest_mode == null or not _conquest_replacement_transition_active:
		_cancel_conquest_replacement_opportunity_preview()
		return
	# 本层全部敌方稳定ID；层结算始终整组处理，单人局自然退化为只含一名敌人的数组。
	var enemy_ids: Array[int] = conquest_mode.get_enemy_ids()
	if enemy_ids.is_empty() or not conquest_mode.is_current_level_cleared():
		_cancel_conquest_replacement_opportunity_preview()
		return
	# 可选武将全集；整组预选阶段只保存稳定ID，全部敌人均能取得新武将后才真正修改关卡与角色状态。
	var character_ids: Array[String] = GameDatabase.get_selectable_character_ids()
	# 玩家方当前武将占用集合；阵亡玩家会在本层切换后以原武将复活，因此同样必须排除。
	var occupied_character_ids: Array[String] = []
	for occupied_player: PlayerState in state.players:
		if occupied_player != null and not enemy_ids.has(occupied_player.player_id) and not occupied_player.character_id.is_empty() and not occupied_character_ids.has(occupied_player.character_id):
			occupied_character_ids.append(occupied_player.character_id)
	# 每名敌人下一层武将预选映射；键为稳定ID字符串，保证网络与测试序列化形式一致。
	var next_character_ids_by_enemy: Dictionary = {}
	for enemy_id: int in enemy_ids:
		# 当前已阵亡敌方实体；缺失实体会破坏整层原子性，因此在任何关卡写入发生前统一取消。
		var defeated_enemy: PlayerState = state.get_player(enemy_id)
		if defeated_enemy == null:
			_cancel_conquest_replacement_opportunity_preview()
			return
		# 当前敌人的下一层武将；排除其自身旧武将、所有玩家武将与本轮已经为其他敌人选中的武将。
		var next_character_id: String = conquest_mode.choose_replacement_character(defeated_enemy.character_id, character_ids, occupied_character_ids)
		if next_character_id.is_empty():
			_check_game_over()
			_cancel_conquest_replacement_opportunity_preview()
			return
		next_character_ids_by_enemy[str(enemy_id)] = next_character_id
		occupied_character_ids.append(next_character_id)
	# 关卡只在整组武将预选成功后提升一次；固定机缘同样只追加一次并写入全体敌方共享历史。
	var new_level: int = conquest_mode.advance_level()
	# 本层新增的固定机缘；先写入全体敌方历史，使每名下一层武将应用基础属性时读取同一完整累计结果。
	var newly_awarded_fixed_opportunity_ids: Array[String] = conquest_mode.award_fixed_opportunities_through_current_level()
	_record_conquest_enemy_opportunities(newly_awarded_fixed_opportunity_ids)
	for enemy_id: int in enemy_ids:
		# 当前准备重新入场的敌方实体；已经由预选阶段完整校验，此处只执行确定性状态替换。
		var enemy: PlayerState = state.get_player(enemy_id)
		# 当前敌方预选武将稳定ID；字典只来源于上方同一批次预选，不接受外部上下文覆写。
		var next_character_id: String = str(next_character_ids_by_enemy.get(str(enemy_id), ""))
		_apply_character(enemy, next_character_id, true)
		enemy.hp = enemy.max_hp
		enemy.shield = 0
		enemy.alive = true
		enemy.dying = false
		enemy.death_confirmed = false
		enemy.chained = false
		enemy.face_down = false
		enemy.skipped_phases.clear()
		enemy.slash_count = 0
		enemy.wine_used = false
		enemy.wine_bonus = 0
		enemy.wooden_ox_used = false
		# 新武将先完成存活与基础状态初始化，再安装固有和关卡技能；获得技能入口会拒绝死亡角色，顺序不能颠倒。
		_reinstall_character_skills_for_player(enemy)
		# 技能关卡奖励只会在本层首次调用时新增，目录历史会同步到全体敌人；每名入场者随后都按完整历史安装技能。
		_restore_conquest_enemy_skills(enemy)
		_equip_conquest_enemy_from_piles(enemy.player_id)
		# 换将基础摸4张；第8关和无限层数的初始手牌增强在这项基础上累加。
		var entry_draw_count: int = ConquestModeService.REPLACEMENT_DRAW_COUNT + conquest_mode.get_initial_hand_bonus()
		draw(enemy.player_id, entry_draw_count)
		add_log("%s以【%s】进入第%d关，体力补至%d并摸%d张牌。" % [enemy.display_name, GameDatabase.resolve_character_name(next_character_id), new_level, enemy.max_hp, entry_draw_count])
	# 进入新一关时复活全部已阵亡的玩家方角色；复活者回到游戏初始状态并照常参与本关的全体机缘选择。
	_revive_dead_conquest_players_for_new_level(new_level)
	_begin_conquest_replacement_opportunity(context)


## 进入新一关时复活全部已阵亡的玩家方角色并使其回到游戏初始状态；仅在仍有存活玩家令对局延续到新一关时存在此类角色。
## “游戏初始状态”指：保留开局武将并重装全新固有技能实例（限定技等内部状态归零）、机缘历史重置为本难度开局机缘、
## 局内获得与临时技能全部移除、体力回满至初始上限、复活次数恢复难度初始值、重新摸取开局数量的起始手牌。
## 复活发生在敌方新武将入场之后、本关全体机缘选择之前，因此复活者照常参与该次投票或各自选择。
## 单人局玩家阵亡即终局，本函数在单人局中自然不产生任何效果；击杀统计等终局结算数据不属于玩法状态，保持累计。
func _revive_dead_conquest_players_for_new_level(new_level: int) -> void:
	if state == null or state.game_over or conquest_mode == null:
		return
	for conquest_player_id: int in conquest_mode.get_player_ids():
		# 当前玩家方角色；仍存活的玩家不受本机制影响。
		var fallen_player: PlayerState = state.get_player(conquest_player_id)
		if fallen_player == null or fallen_player.alive:
			continue
		# 区域残留兜底清理；正常死亡已弃置手牌、装备与判定区，此处保证木牛“粮”等边缘区域同样为空。
		_discard_all_conquest_player_cards(fallen_player)
		# 机缘历史重置为本难度开局机缘；通用效果缓存与公开快照缓存均通过首尾哨兵自动识别整体替换。
		fallen_player.acquired_opportunity_ids = conquest_mode.get_player_starting_opportunity_ids()
		# 局内获得与临时技能记录清空；随后的固有技能重装会先卸载全部旧运行时实例，包括机缘获得技能。
		fallen_player.acquired_skills.clear()
		fallen_player.temporary_skills.clear()
		fallen_player.hand_limit_bonus = 0
		# 重装武将固有技能；创建全新实例使限定技已用标记等跨回合内部状态回到开局值。
		_reinstall_character_skills_for_player(fallen_player)
		# 存活与回合规则状态复位；身份在过关斩将中开局即明置，保持公开不变。
		fallen_player.alive = true
		fallen_player.dying = false
		fallen_player.death_confirmed = false
		fallen_player.out_of_game = false
		fallen_player.out_of_game_until_round = -1
		fallen_player.chained = false
		fallen_player.face_down = false
		fallen_player.non_locked_skills_disabled = false
		fallen_player.non_locked_skill_disable_sources.clear()
		fallen_player.character_corner_text = ""
		fallen_player.character_corner_text_entries.clear()
		fallen_player.skipped_phases.clear()
		fallen_player.slash_count = 0
		fallen_player.wine_used = false
		fallen_player.wine_bonus = 0
		fallen_player.wooden_ox_used = false
		# 初始体力与上限；机缘历史已重置，因此这里恢复的就是“武将基础+难度机缘”的开局数值，护盾同步归零。
		_refresh_pre_game_character_stats(fallen_player)
		# 复活次数恢复本难度初始值；已用计数同步归零。
		conquest_mode.reset_player_revives_to_initial(conquest_player_id)
		# 开局数量的起始手牌；使用本局锁定的初始手牌数并叠加该玩家难度“初始手牌数”机缘，与正式开局完全一致。
		var revival_hand_count: int = _starting_hand_count + get_acquired_opportunity_effect_total(conquest_player_id, "initial_hand_bonus")
		draw(conquest_player_id, revival_hand_count)
		add_log("第%d关开始，%s复活并回到初始状态：体力%d/%d，摸%d张起始手牌。" % [new_level, format_player_state_log_name(fallen_player), fallen_player.hp, fallen_player.max_hp, revival_hand_count])


## 整层敌方完成重新入场后发起玩家方机缘选择；层结算过渡仍保持阻塞，防止旧回合在机缘前重建操作。
func _queue_conquest_replacement_opportunity(context: Dictionary) -> void:
	_begin_conquest_replacement_opportunity(context)


## 展示等待结束后发起玩家方机缘；机缘自身会接管暂停令牌，失败时才立即恢复原回合后继。
## 联机多人局中全体存活玩家按本局“投票选择/各自选择”设置共同参与，单人局保持原有仅玩家三选一。
func _begin_conquest_replacement_opportunity(context: Dictionary) -> void:
	if state == null or state.game_over or conquest_mode == null:
		_cancel_conquest_replacement_opportunity_preview()
		return
	if _begin_conquest_group_opportunity("conquest_enemy_replacement", context):
		return
	_finish_conquest_replacement_turn(context)


## 取消敌方换将表现等待并清除过渡状态；重开、异常终局和无候选武将均通过本入口清理。
func _cancel_conquest_replacement_opportunity_preview() -> void:
	if game_flow_pacer != null:
		game_flow_pacer.cancel(CONQUEST_REPLACEMENT_OPPORTUNITY_TASK_KEY)
	# 取消路径通常紧接重开或终局；只解决令牌而不立即排空旧事件，避免旧局在销毁前重新执行规则。
	if event_scheduler != null and _conquest_replacement_settlement_pause_token >= 0:
		event_scheduler.pause_registry.resolve(_conquest_replacement_settlement_pause_token, "conquest_replacement_cancelled")
	_conquest_replacement_settlement_pause_token = -1
	_conquest_replacement_transition_active = false


## 弃置过关斩将敌方当前区域内的全部牌；手牌、装备、判定区与木牛“粮”均属于“区域内所有牌”。
## 补充：玩家复活现与敌方换将共同复用该入口，因此参数允许传入过关斩将中的任一角色。
func _discard_all_conquest_player_cards(player: PlayerState) -> void:
	if player == null:
		return
	while not player.hand.is_empty():
		_move_to_discard(player.hand.pop_back())
	discard_all_equipment(player.player_id, false)
	while not player.judgment_area.is_empty():
		_move_to_discard(player.judgment_area.pop_back())
	while not player.wooden_ox_storage.is_empty():
		_move_to_discard(player.wooden_ox_storage.pop_back())


## 重新安装过关斩将获得技能机缘；武将切换会卸载旧运行时实例，因此所有历史技能机缘需按服务快照恢复。
## 返回本层新增的技能机缘ID，供调用方把同一奖励同步给其他在场敌人。
func _restore_conquest_enemy_skills(enemy: PlayerState) -> Array[String]:
	# 本层新增技能机缘；服务确保技能机缘与已获技能、当前新武将固有技能均不重复。
	var newly_awarded_skill_opportunity_ids: Array[String] = []
	if enemy == null or conquest_mode == null:
		return newly_awarded_skill_opportunity_ids
	newly_awarded_skill_opportunity_ids = conquest_mode.ensure_skill_opportunity_rewards(enemy)
	_record_conquest_enemy_opportunities(newly_awarded_skill_opportunity_ids)
	for opportunity_id: String in conquest_mode.get_enemy_skill_opportunity_ids():
		# 当前历史机缘定义；只有获得技能效果需要在每次新武将入场时重新安装运行时实例。
		var opportunity_card: Dictionary = OpportunityCatalog.get_card(opportunity_id)
		if str(opportunity_card.get("effect", "")) != "grant_skill":
			continue
		grant_acquired_skill(enemy.player_id, str(opportunity_card.get("skill_id", "")), int(opportunity_card.get("per_turn_limit", 0)), int(opportunity_card.get("total_limit", 0)), "conquest", false, int(opportunity_card.get("per_round_limit", 0)))
	return newly_awarded_skill_opportunity_ids


## 把本层新获得的过关斩将机缘写入全体敌方永久历史；右键武将详情据此按实际获取顺序显示对应品质与原文。
## 关卡机缘是“每个敌人都会获得”的全局奖励：本层全部敌人阵亡并进入下一层时，历史同步追加到每名敌人身上，
## 因此摸牌阶段、【杀】次数与伤害加成等运行时汇总在多人局对全部敌人一致生效；每层每项机缘只记录一次。
func _record_conquest_enemy_opportunities(opportunity_ids: Array[String]) -> void:
	if conquest_mode == null or state == null or opportunity_ids.is_empty():
		return
	# 全体敌方稳定ID；单人局退化为唯一敌人，行为与既有版本完全一致。
	var enemy_ids: Array[int] = conquest_mode.get_enemy_ids()
	for opportunity_id: String in opportunity_ids:
		# 当前机缘定义；目录异常时不写入无效历史，避免详情出现无法解析的占位条目。
		var opportunity_card: Dictionary = OpportunityCatalog.get_card(opportunity_id)
		if opportunity_card.is_empty():
			continue
		for enemy_id: int in enemy_ids:
			# 当前敌方角色；换将过渡中的阵亡敌人同样写入历史，新武将入场时立即按完整历史汇总数值。
			var enemy: PlayerState = state.get_player(enemy_id)
			if enemy != null:
				enemy.acquired_opportunity_ids.append(opportunity_id)
		add_log("第%d关敌方获得%s机缘：%s" % [conquest_mode.get_level() if conquest_mode != null else 0, OpportunityCatalog.get_quality_name(str(opportunity_card.get("quality", ""))), str(opportunity_card.get("description", ""))])


## 兼容旧存档或外部工具直接补发关卡奖励时，把新增机缘的增量效果同步给其他在场敌人；正式整层换将流程会让全体敌人按完整历史重算，不调用本入口。
## 体力上限按新增数值直接累加（当前体力不变），手牌上限重读服务汇总，技能机缘立即安装运行时实例。
## 摸牌阶段、【杀】次数与伤害加成从各敌人自身机缘历史动态汇总，历史写入后自然生效，无需在此处理。
func _apply_conquest_awards_to_standing_enemies(entering_enemy_id: int, newly_awarded_opportunity_ids: Array[String]) -> void:
	if conquest_mode == null or state == null or newly_awarded_opportunity_ids.is_empty():
		return
	# 本层新增的体力上限总量；只统计目录中的max_hp效果，其他效果不改变即时体力属性。
	var max_hp_delta: int = 0
	for opportunity_id: String in newly_awarded_opportunity_ids:
		if OpportunityCatalog.get_effect_id(opportunity_id) == "max_hp":
			max_hp_delta += OpportunityCatalog.get_effect_count(opportunity_id)
	for enemy_id: int in conquest_mode.get_enemy_ids():
		if enemy_id == entering_enemy_id:
			continue
		# 当前在场敌人；死亡或缺失的敌人由其后续换将流程按完整历史重算，不在此处理。
		var standing_enemy: PlayerState = state.get_player(enemy_id)
		if standing_enemy == null or not standing_enemy.alive:
			continue
		if max_hp_delta > 0:
			standing_enemy.max_hp += max_hp_delta
		# 手牌上限重读服务汇总；与入场敌人的基础属性刷新使用同一唯一数值来源。
		standing_enemy.mode_hand_limit_bonus = conquest_mode.get_hand_limit_bonus()
		for opportunity_id: String in newly_awarded_opportunity_ids:
			# 当前新增机缘定义；技能机缘立即安装，已拥有同名技能的敌人由授予入口自动去重。
			var opportunity_card: Dictionary = OpportunityCatalog.get_card(opportunity_id)
			if str(opportunity_card.get("effect", "")) != "grant_skill":
				continue
			grant_acquired_skill(standing_enemy.player_id, str(opportunity_card.get("skill_id", "")), int(opportunity_card.get("per_turn_limit", 0)), int(opportunity_card.get("total_limit", 0)), "conquest", false, int(opportunity_card.get("per_round_limit", 0)))


## 从牌堆或弃牌堆随机取出至多四张不同装备子类别的牌并直接装备给刚入场敌方；空类别不会以其他类别替代。
func _equip_conquest_enemy_from_piles(enemy_player_id: int) -> void:
	if conquest_mode == null or not conquest_mode.should_equip_distinct_subtypes():
		return
	var cards_by_subtype: Dictionary = {}
	for subtype: String in EquipmentSubtype.ALL:
		cards_by_subtype[subtype] = []
	for pile_variant: Variant in [state.draw_pile, state.discard_pile]:
		for card_variant: Variant in pile_variant as Array:
			var card: CardInstance = card_variant as CardInstance
			if card == null:
				continue
			var definition: Dictionary = GameDatabase.get_card(card.definition_id)
			var subtype: String = str(definition.get("subtype", ""))
			if str(definition.get("type", "")) == "equipment" and EquipmentSubtype.is_valid(subtype):
				(cards_by_subtype[subtype] as Array).append(card)
	var available_subtypes: Array[String] = []
	for subtype: String in EquipmentSubtype.ALL:
		if not (cards_by_subtype.get(subtype, []) as Array).is_empty():
			available_subtypes.append(subtype)
	_shuffle_array(available_subtypes)
	var equipped_count: int = 0
	for subtype: String in available_subtypes:
		if equipped_count >= ConquestModeService.LEVEL_FOURTEEN_EQUIPMENT_SUBTYPE_COUNT:
			break
		var cards: Array = cards_by_subtype.get(subtype, []) as Array
		if cards.is_empty():
			continue
		var card_index: int = _rng.randi_range(0, cards.size() - 1)
		var selected_card: CardInstance = cards[card_index] as CardInstance
		if selected_card == null or _move_card_with_timings(selected_card, "processing", -1, "conquest_equipment", state.current_event_id) == null:
			continue
		equip_from_processing(enemy_player_id, selected_card)
		equipped_count += 1
	if equipped_count > 0:
		add_log("第%d关敌方随机装备了%d张不同子类别的装备牌。" % [conquest_mode.get_level(), equipped_count])


## 在敌方换将后的玩家机缘全部结算后恢复对局；玩家回合维持原阶段，敌方回合立即以死亡中断语义交给玩家。
func _finish_conquest_replacement_turn(context: Dictionary) -> void:
	if state == null or state.game_over or conquest_mode == null:
		return
	var enemy_id: int = int(context.get("defeated_enemy_id", conquest_mode.get_enemy_id()))
	if state.current_player_id == enemy_id:
		state.current_phase = "conquest_enemy_replacing"
		state.phase_index = -1
		_advance_after_current_player_death(enemy_id, int(context.get("defeated_character_generation", -1)))
		# 回合已经切入死亡中断状态后再释放事件树；过渡布尔仍保持true，防止释放过程抢先恢复普通阶段游标。
		_release_conquest_replacement_settlement_pause()
		_conquest_replacement_transition_active = false
		return
	state.current_phase = str(context.get("resume_phase", state.current_phase))
	state.phase_index = int(context.get("resume_phase_index", state.phase_index))
	# 原阶段与游标恢复后释放事件树；释放期间过渡状态仍阻止旧结算直接重建出牌选择。
	_release_conquest_replacement_settlement_pause()
	_conquest_replacement_transition_active = false
	# 玩家击杀敌方后必须恢复被死亡与机缘依次暂停的原卡牌结算；排空后才创建下一次出牌选择，避免机缘结束留在无交互的出牌阶段。
	_resume_settlement_pipeline()
	if event_scheduler != null:
		event_scheduler.drain()
	if state.current_phase == "play" and not has_pending_play_interaction() and _active_card_resolutions.is_empty() and not _has_active_play_choice():
		_begin_play_choice(state.current_player_id)
	_emit_state()
	_ensure_ai_progress_after_resolution()


## 释放过关斩将换将专用事件树令牌并继续调度；调用方必须先恢复合法阶段且保持过渡标志为true。
func _release_conquest_replacement_settlement_pause() -> void:
	if event_scheduler == null or _conquest_replacement_settlement_pause_token < 0:
		return
	# 当前专用暂停令牌；先清空成员字段，防止事件恢复过程重入时重复释放同一令牌。
	var pause_token: int = _conquest_replacement_settlement_pause_token
	_conquest_replacement_settlement_pause_token = -1
	event_scheduler.resume(pause_token, "conquest_replacement_completed")


## 判断当前对局是否支持过关斩将临时退出存档；仅离线进行中的单人过关斩将可以预约，局域网、多人局与终局一律拒绝。
func supports_conquest_temporary_exit() -> bool:
	if state == null or state.game_over or conquest_mode == null:
		return false
	if str(state.match_mode) != IdentityRules.MODE_CONQUEST:
		return false
	# 存档格式只覆盖“1名玩家+1名敌人”的单人局；多人过关斩将不进入临时退出与恢复流程。
	if conquest_mode.get_player_ids().size() != 1:
		return false
	return network_gateway == null or network_gateway.mode == NetworkGateway.Mode.OFFLINE


## 返回玩家是否已经预约临时退出；界面按钮据此在“临时退出”和“取消临时退出”之间切换。
func is_conquest_temporary_exit_requested() -> bool:
	return _conquest_temporary_exit_requested


## 预约过关斩将临时退出。若此刻正处于空闲的出牌询问（没有任何进行中的结算），立即存档退出；
## 否则保持预约，在当前操作结算完成后的最近一个空闲点（出牌询问重建或回合边界）自动生效。
## 返回是否成功预约；重复预约保持已预约状态并同样返回true。
func request_conquest_temporary_exit() -> bool:
	if not supports_conquest_temporary_exit():
		return false
	if _conquest_temporary_exit_requested:
		return true
	_conquest_temporary_exit_requested = true
	# 空闲询问时机直接生效；常驻出牌询问不属于结算，关闭后可在恢复时原样重建。
	if _try_capture_conquest_temporary_exit_at_play_idle():
		return true
	add_log("已预约临时退出：当前操作结算完成后将自动保存进度并返回主菜单。")
	_emit_state()
	return true


## 取消尚未生效的临时退出预约；存档尚未写出，本局继续正常进行。返回是否实际取消了一次预约。
func cancel_conquest_temporary_exit() -> bool:
	if not _conquest_temporary_exit_requested:
		return false
	_conquest_temporary_exit_requested = false
	if state != null and not state.game_over:
		add_log("已取消临时退出预约，本局继续进行。")
		_emit_state()
	return true


## 判断当前是否处于没有任何进行中结算的空闲状态；两类临时退出捕获点共用本判定。
## 覆盖处理区、濒死队列、机缘流程、待办选择与判定、活动卡牌结算、延后技能结算、规则续接、
## 待派发触发、伤害收尾、装备触发队列、回合尾部等待以及独立阶段与额外弃牌阶段。
func _is_conquest_settlement_quiescent() -> bool:
	if state == null or state.game_over or conquest_mode == null or _conquest_replacement_transition_active:
		return false
	if not state.processing_area.is_empty() or not state.dying_queue.is_empty() or not state.opportunity_state.is_empty():
		return false
	if has_pending_card_choice() or has_pending_judgment_request() or _judgment_flow_in_progress:
		return false
	if not _active_card_resolutions.is_empty() or not _card_use_contexts.is_empty():
		return false
	if not _deferred_skill_settlements.is_empty() or _rule_continuations.has_pending():
		return false
	if trigger_manager != null and trigger_manager.has_deferred_dispatches():
		return false
	if not _queued_equipment_triggers.is_empty():
		return false
	if not _active_independent_play_phase.is_empty() or not _active_extra_discard_phase.is_empty():
		return false
	return true


## 在回合边界尝试执行已预约的临时退出；条件满足时构建完整存档并发出信号交给界面层保存退出。
## 返回true表示本回合不再开始，界面层会在收到信号后写入存档文件并返回主菜单。
## 额外回合链的进度已随存档保存，因此边界捕获不再区分普通回合与额外回合；
## 换将过渡、处理区残留或任何未排空的结算都表示边界不干净，此时保持预约等待下一个空闲点。
func _try_capture_conquest_temporary_exit(next_turn_player_id: int) -> bool:
	if not _conquest_temporary_exit_requested:
		return false
	if not _is_conquest_settlement_quiescent():
		return false
	# 下一回合角色；死亡或无效角色说明边界仍处于死亡结算过渡，交由后续流程继续推进。
	var next_player: PlayerState = state.get_player(next_turn_player_id)
	if next_player == null or not next_player.alive:
		return false
	_conquest_temporary_exit_requested = false
	# 旧AI计时器统一作废；存档已经捕获，任何迟到的AI回调都不得再推进本局状态。
	_ai_drive_token += 1
	# 完整存档字典；构建过程只读取权威状态，不修改任何规则数据。
	var save_data: Dictionary = _build_conquest_save_data("turn_start", next_turn_player_id)
	add_log("已保存过关斩将进度：第%d关，下一回合由%s开始。" % [conquest_mode.get_level(), next_player.display_name])
	conquest_exit_save_ready.emit(save_data)
	return true


## 在出牌阶段空闲询问点尝试执行已预约的临时退出；每次操作结算完成后重建出牌询问前与玩家直接
## 请求时都会调用。常驻 chooseToUse 不属于结算流程：捕获前以系统响应关闭旧窗口，恢复时按当前
## 合法动作重新创建等价询问，因此存档不需要序列化任何选择请求或事件对象。
func _try_capture_conquest_temporary_exit_at_play_idle() -> bool:
	if not _conquest_temporary_exit_requested or state == null:
		return false
	if str(state.current_phase) != "play":
		return false
	# 阶段游标属于另一名角色时，当前play只是旧回合恢复中的表现状态，不能写成中间play_phase存档。
	for lifecycle_key_variant: Variant in _started_phase_lifecycles.keys():
		var lifecycle_key: String = str(lifecycle_key_variant)
		if lifecycle_key.ends_with(":phaseUse") and int(lifecycle_key.get_slice(":", 0)) != state.current_player_id:
			return false
	# 多步技能间隔或已排队的阶段切换表示仍有流程在推进；保持预约等待其完成后的下一个空闲点。
	if game_flow_pacer != null and (game_flow_pacer.has_pending_skill_interval() or game_flow_pacer.has_pending("phase_transition")):
		return false
	if not _is_conquest_settlement_quiescent():
		return false
	# 当前行动角色；存档记录其出牌阶段仍在进行，恢复后由同一角色继续本回合。
	var acting_player: PlayerState = state.get_player(state.current_player_id)
	if acting_player == null or not acting_player.alive:
		return false
	if _has_active_play_choice():
		_cancel_active_play_choice("conquest_temporary_exit")
		if event_scheduler != null:
			event_scheduler.drain()
	_conquest_temporary_exit_requested = false
	# 旧AI计时器统一作废；AI行动窗口被关闭后，迟到回调不得向已捕获的存档状态提交动作。
	_ai_drive_token += 1
	# 完整存档字典；resume_kind 记录需要回到出牌阶段而不是开始新回合。
	var save_data: Dictionary = _build_conquest_save_data("play_phase", acting_player.player_id)
	add_log("已保存过关斩将进度：第%d关，%s的回合进行中。" % [conquest_mode.get_level(), acting_player.display_name])
	conquest_exit_save_ready.emit(save_data)
	return true


## 构建当前空闲点的完整过关斩将存档字典；所有字段均可被 var_to_str 序列化，不包含节点或回调引用。
## resume_kind 为 turn_start 表示捕获于回合边界（acting_player_id 是尚未开始的下一回合角色），
## 为 play_phase 表示捕获于出牌阶段空闲询问（acting_player_id 是回合进行中的当前角色）。
## 两类捕获点都满足“没有任何进行中的结算”，因此不需要保存事件栈或选择请求；
## 回合与阶段游标（额外回合链、额外出牌阶段、阶段生命周期、本回合用牌记录）统一进入 turn_flow。
func _build_conquest_save_data(resume_kind: String, acting_player_id: int) -> Dictionary:
	# 玩家存档数组；以本人视角加 reveal_private 序列化，包含手牌、装备、判定区与“粮”的完整牌面。
	var players_data: Array = []
	for player: PlayerState in state.players:
		# 单名玩家的权威快照；网络快照缺少的每回合字段与完整历史在此补充，供恢复后技能查询保持一致。
		var player_data: Dictionary = player.to_dict(player.player_id, true)
		player_data["slash_count"] = player.slash_count
		player_data["wooden_ox_used"] = player.wooden_ox_used
		player_data["skipped_phases"] = player.skipped_phases.duplicate(true)
		player_data["turn_history"] = player.turn_history.duplicate(true)
		player_data["response_history"] = player.response_history.duplicate(true)
		player_data["damage_history"] = player.damage_history.duplicate(true)
		players_data.append(player_data)
	# 摸牌堆存档；保持数组顺序（末尾为牌堆顶），恢复后摸牌序列与临时退出前完全一致。
	var draw_pile_data: Array = []
	for draw_card: CardInstance in state.draw_pile:
		draw_pile_data.append(draw_card.to_dict())
	# 弃牌堆存档；保持进入顺序，重洗规则依赖该顺序的稳定性。
	var discard_pile_data: Array = []
	for discard_card: CardInstance in state.discard_pile:
		discard_pile_data.append(discard_card.to_dict())
	return {
		"save_version": ConquestSaveStore.SAVE_FORMAT_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"match_mode": IdentityRules.MODE_CONQUEST,
		"deck_id": state.deck_id,
		"random_seed": state.random_seed,
		"rng_state": _rng.state,
		"card_next_uid": CardInstance._next_uid,
		"match_options": state.match_options.duplicate(true),
		"conquest_state": state.conquest_state.duplicate(true),
		"round_number": state.round_number,
		"turn_number": state.turn_number,
		"action_sequence": state.action_sequence,
		"resume_kind": resume_kind,
		"next_turn_player_id": acting_player_id,
		"phase_index": state.phase_index,
		"turn_flow": {
			"current_turn_is_extra": _current_turn_is_extra,
			"extra_turn_queue": _extra_turn_queue.duplicate(),
			"extra_turn_resume_player_ids": _extra_turn_resume_player_ids.duplicate(),
			"extra_play_phase_counts": _extra_play_phase_counts.duplicate(true),
			"extra_play_phase_returns_to_finish": _extra_play_phase_returns_to_finish.duplicate(true),
			"extra_play_phase_return_points": _extra_play_phase_return_points.duplicate(true),
			"active_extra_play_phase_context": _active_extra_play_phase_context.duplicate(true),
			"main_phase_play_conversions": _main_phase_play_conversions.duplicate(true),
			"active_converted_play_phase_context": _active_converted_play_phase_context.duplicate(true),
			"started_phase_lifecycles": _started_phase_lifecycles.duplicate(true),
			"cards_used_this_turn_by_player": _cards_used_this_turn_by_player.duplicate(true),
		},
		"players": players_data,
		"draw_pile": draw_pile_data,
		"discard_pile": discard_pile_data,
		"skill_runtime_states": _capture_skill_runtime_states(),
		"hand_view_as_turn_expiries": _hand_view_as_turn_expiries.duplicate(true),
	}


## 捕获全部已安装技能实例的可序列化脚本变量；限定技已用标记、每轮限一次记录等跨回合状态借此进入存档。
## 只保存基础类型与纯数据容器，Object、Callable 等引用类型自动跳过，由恢复流程的 bind/install 重新建立。
func _capture_skill_runtime_states() -> Dictionary:
	# 按玩家分组的技能状态；键为稳定玩家ID，值为“技能ID→脚本变量字典”。
	var result: Dictionary = {}
	for player_id_variant: Variant in skill_instances_by_player.keys():
		# 当前玩家的技能状态集合；没有任何可序列化变量的技能不产生条目。
		var player_states: Dictionary = {}
		var player_skills: Dictionary = skill_instances_by_player[player_id_variant] as Dictionary
		for skill_id_variant: Variant in player_skills.keys():
			# 当前技能实例；卸载竞态下的空实例直接跳过。
			var skill: SkillDefinition = player_skills[skill_id_variant] as SkillDefinition
			if skill == null:
				continue
			# 当前技能的可序列化脚本变量；包含基类的持有者与代次字段，恢复时按同名覆盖。
			var skill_state: Dictionary = {}
			for property: Dictionary in skill.get_property_list():
				if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
					continue
				# 当前脚本变量名；引用类型的值会在下方序列化检查中被过滤。
				var property_name: String = str(property.get("name", ""))
				# 当前变量值；数组与字典深复制，防止存档字典与运行实例共享可变容器。
				var property_value: Variant = skill.get(property_name)
				if not _is_persistable_skill_runtime_value(property_value):
					continue
				if property_value is Dictionary:
					skill_state[property_name] = (property_value as Dictionary).duplicate(true)
				elif property_value is Array:
					skill_state[property_name] = (property_value as Array).duplicate(true)
				else:
					skill_state[property_name] = property_value
			if not skill_state.is_empty():
				player_states[str(skill_id_variant)] = skill_state
		if not player_states.is_empty():
			result[int(player_id_variant)] = player_states
	return result


## 判断一个技能脚本变量值是否允许进入存档；只接受空值、布尔、数字、字符串与只含这些类型的数组或字典。
func _is_persistable_skill_runtime_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_ARRAY:
			for item_variant: Variant in value as Array:
				if not _is_persistable_skill_runtime_value(item_variant):
					return false
			return true
		TYPE_DICTIONARY:
			for key_variant: Variant in (value as Dictionary).keys():
				if not _is_persistable_skill_runtime_value(key_variant) or not _is_persistable_skill_runtime_value((value as Dictionary)[key_variant]):
					return false
			return true
		_:
			return false


## 把存档中的技能脚本变量写回已重新安装的技能实例；实例或变量已不存在时静默跳过对应条目。
func _apply_skill_runtime_states(saved_states: Dictionary) -> void:
	for player_id_variant: Variant in saved_states.keys():
		# 当前玩家的技能实例表；恢复流程已按存档角色重新安装全部技能。
		var player_skills: Dictionary = skill_instances_by_player.get(int(player_id_variant), {}) as Dictionary
		var saved_player_states: Dictionary = saved_states[player_id_variant] as Dictionary
		for skill_id_variant: Variant in saved_player_states.keys():
			# 目标技能实例；武将或技能目录变化导致缺失时放弃该技能的状态恢复。
			var skill: SkillDefinition = player_skills.get(str(skill_id_variant)) as SkillDefinition
			if skill == null:
				continue
			var skill_state: Dictionary = saved_player_states[skill_id_variant] as Dictionary
			for property_name_variant: Variant in skill_state.keys():
				skill.set(str(property_name_variant), skill_state[property_name_variant])


## 校验一份过关斩将存档能否在当前环境恢复；返回空字符串表示可以恢复，否则返回玩家可读的拒绝原因。
## 深层内容校验覆盖角色与全部实体牌的定义存在性，防止内容更新后的旧存档把无效ID注入运行时。
func get_conquest_resume_validation_error(save_data: Dictionary) -> String:
	if network_gateway != null and network_gateway.mode != NetworkGateway.Mode.OFFLINE:
		return "过关斩将存档仅支持离线继续。"
	if int(save_data.get("save_version", -1)) != ConquestSaveStore.SAVE_FORMAT_VERSION:
		return "存档版本与当前游戏不兼容。"
	if str(save_data.get("match_mode", "")) != IdentityRules.MODE_CONQUEST:
		return "存档不属于过关斩将模式。"
	# 全局数据配置校验；复用普通开局的前置检查，保证武将、卡牌与牌堆数据均已加载。
	var base_validation_error: String = get_match_start_validation_error(2, IdentityRules.MODE_CONQUEST)
	if not base_validation_error.is_empty():
		return base_validation_error
	# 玩家存档数组；过关斩将固定两名规则角色。
	var players_data: Array = save_data.get("players", []) as Array
	if players_data.size() != 2:
		return "存档缺少完整的双方角色数据。"
	# 存档中的合法玩家ID集合；下一回合角色必须属于该集合。
	var player_ids: Array[int] = []
	for player_data_variant: Variant in players_data:
		var player_data: Dictionary = player_data_variant as Dictionary
		player_ids.append(int(player_data.get("player_id", -1)))
		# 存档武将ID；目录缺失说明内容版本不匹配。
		var character_id: String = str(player_data.get("character_id", ""))
		if character_id.is_empty() or GameDatabase.get_character(character_id).is_empty():
			return "存档中的武将在当前版本中不存在。"
		# 该玩家全部区域实体牌；任何一张定义缺失都拒绝恢复。
		for zone_key: String in ["hand", "judgment_area", "wooden_ox_storage"]:
			for card_data_variant: Variant in player_data.get(zone_key, []) as Array:
				if not _is_saved_card_definition_valid(card_data_variant as Dictionary):
					return "存档中的卡牌在当前版本中不存在。"
		for equipment_data_variant: Variant in (player_data.get("equipment", {}) as Dictionary).values():
			if not _is_saved_card_definition_valid(equipment_data_variant as Dictionary):
				return "存档中的卡牌在当前版本中不存在。"
	for pile_key: String in ["draw_pile", "discard_pile"]:
		for card_data_variant: Variant in save_data.get(pile_key, []) as Array:
			if not _is_saved_card_definition_valid(card_data_variant as Dictionary):
				return "存档中的卡牌在当前版本中不存在。"
	if (save_data.get("conquest_state", {}) as Dictionary).is_empty():
		return "存档缺少过关斩将关卡状态。"
	# 恢复类型；turn_start 从下一回合开始，play_phase 回到出牌阶段空闲询问，未知类型一律拒绝。
	var resume_kind: String = str(save_data.get("resume_kind", "turn_start"))
	if resume_kind not in ["turn_start", "play_phase"]:
		return "存档记录的恢复类型无效。"
	# 行动角色稳定ID；两类恢复共用同一字段，必须指向存档中的存活角色。
	var acting_player_id: int = int(save_data.get("next_turn_player_id", -1))
	if not player_ids.has(acting_player_id):
		return "存档缺少有效的行动角色。"
	for player_data_variant: Variant in players_data:
		var acting_player_data: Dictionary = player_data_variant as Dictionary
		if int(acting_player_data.get("player_id", -1)) == acting_player_id and not bool(acting_player_data.get("alive", true)):
			return "存档记录的行动角色已经死亡。"
	return ""


## 判断一条实体牌存档记录的逻辑定义与原始定义是否都仍在卡牌目录中；视为牌恢复需要两个ID同时有效。
func _is_saved_card_definition_valid(card_data: Dictionary) -> bool:
	# 当前逻辑定义ID；手牌视为状态下保存的是临时牌名，同样必须是已登记卡牌。
	var definition_id: String = str(card_data.get("definition_id", ""))
	if definition_id.is_empty() or GameDatabase.get_card(definition_id).is_empty():
		return false
	# 原始定义ID；没有视为效果时为空字符串，存在时必须同样有效。
	var original_definition_id: String = str(card_data.get("original_definition_id", ""))
	return original_definition_id.is_empty() or not GameDatabase.get_card(original_definition_id).is_empty()


## 从存档字典恢复并继续一局过关斩将；成功后直接从存档记录的下一回合角色开始行动。
## 初始化顺序与 start_match 保持一致并复用同一组运行时重建入口，但跳过选将、起始手牌与手气卡流程。
func resume_conquest_match(save_data: Dictionary) -> bool:
	# 恢复前置校验错误；任何错误都在破坏旧对局状态之前同步拒绝，调用方可保留原局或提示玩家。
	var validation_error: String = get_conquest_resume_validation_error(save_data)
	if not validation_error.is_empty():
		action_rejected.emit(validation_error)
		return false
	_teardown_previous_match_runtime()
	# 恢复随机源；先写种子再覆盖内部状态，使后续随机序列与临时退出前完全一致。
	_rng.seed = int(save_data.get("random_seed", 0))
	_rng.state = int(save_data.get("rng_state", 0))
	# 存档中的关卡状态；本地玩家固定为其中记录的过关斩将玩家稳定ID。
	var saved_conquest_state: Dictionary = (save_data.get("conquest_state", {}) as Dictionary).duplicate(true)
	local_human_player_id = int(saved_conquest_state.get("player_id", 0))
	default_player_count = 2
	CardInstance._next_uid = 1
	state = GameState.new()
	# 恢复局的新对局ID；使用存档时间与回合数构造，不消耗已恢复的随机序列。
	state.match_id = "%d-resume%d" % [Time.get_unix_time_from_system(), int(save_data.get("turn_number", 0))]
	state.match_mode = IdentityRules.MODE_CONQUEST
	ai_coordinator.reset_identity_observations()
	state.random_seed = int(save_data.get("random_seed", 0))
	state.deck_id = str(save_data.get("deck_id", default_deck_id))
	# 本局锁定选项从存档恢复；菜单当前设置只影响下一次全新开局，控制全部角色开关保持实时读取。
	var saved_options: Dictionary = (save_data.get("match_options", {}) as Dictionary).duplicate(true)
	_all_character_selection_enabled = bool(saved_options.get("all_character_selection_enabled", false))
	_custom_character_assignment_enabled = false
	_customize_ai_characters_enabled = false
	_mulligan_limit = int(saved_options.get("mulligan_limit", 0))
	_ai_uses_mulligan_enabled = bool(saved_options.get("ai_uses_mulligan_enabled", false))
	_control_all_characters_enabled = network_gateway != null and network_gateway.mode == NetworkGateway.Mode.OFFLINE and local_human_player_id >= 0 and GameSettings.control_all_characters_enabled
	saved_options["control_all_characters_enabled"] = _control_all_characters_enabled
	_primary_offline_human_player_id = local_human_player_id
	_offline_manually_controlled_player_id = -1
	_character_replacement_count = int(saved_options.get("character_replacement_count", 0))
	_character_candidate_count = int(saved_options.get("character_candidate_count", GameSettings.DEFAULT_CONQUEST_CHARACTER_CANDIDATE_COUNT))
	character_candidate_count = _character_candidate_count
	state.match_options = saved_options
	if opportunity_system != null:
		opportunity_system.configure(self, state, _rng, true, false)
	_rebuild_match_rule_services_and_root_event()
	character_selection = CharacterSelectionService.new()
	wheel_duel_selection = null
	conquest_mode = ConquestModeService.new()
	ai_character_adjustment = AICharacterAdjustmentService.new()
	starting_hand_mulligan = StartingHandMulliganService.new()
	_reset_per_match_progress_state()
	# 恢复双方角色与全部牌区；玩家保持一号位真人，其余角色重新登记基础AI策略。
	for player_data_variant: Variant in save_data.get("players", []) as Array:
		var restored_player: PlayerState = PlayerState.from_authoritative_dict(player_data_variant as Dictionary)
		state.players.append(restored_player)
		if restored_player.player_id != local_human_player_id:
			ai_coordinator.register_basic_ai(restored_player.player_id)
	for card_data_variant: Variant in save_data.get("draw_pile", []) as Array:
		state.draw_pile.append(CardInstance.from_dict(card_data_variant as Dictionary))
	for card_data_variant: Variant in save_data.get("discard_pile", []) as Array:
		state.discard_pile.append(CardInstance.from_dict(card_data_variant as Dictionary))
	# 实体UID游标下限；from_dict 已按最大恢复UID推进，此处只兜底保证新实体不与存档实体碰撞。
	CardInstance._next_uid = maxi(CardInstance._next_uid, int(save_data.get("card_next_uid", 1)))
	state.conquest_state = saved_conquest_state
	conquest_mode.restore(state, _rng)
	state.round_number = int(save_data.get("round_number", 0))
	state.turn_number = int(save_data.get("turn_number", 0))
	state.action_sequence = int(save_data.get("action_sequence", 0))
	# 手牌限时视为到期表；键为实体UID，var_to_str 保留整数键，逐项转换只为防御外部构造的字符串键。
	_hand_view_as_turn_expiries.clear()
	var saved_expiries: Dictionary = save_data.get("hand_view_as_turn_expiries", {}) as Dictionary
	for card_uid_variant: Variant in saved_expiries.keys():
		_hand_view_as_turn_expiries[int(card_uid_variant)] = (saved_expiries[card_uid_variant] as Dictionary).duplicate(true)
	# 恢复回合与阶段游标；额外回合链、额外出牌阶段、阶段生命周期与本回合用牌记录全部回到捕获时刻。
	_restore_conquest_turn_flow_state(save_data.get("turn_flow", {}) as Dictionary)
	_record_runtime_event("identity.start", "mode", {"player_count":state.players.size(), "seed":state.random_seed, "mode":state.match_mode, "resumed_from_save":true})
	# 重新安装武将固有技能与模式技能，再补装存档中的获得技能与临时技能，最后回写全部技能内部状态。
	_install_all_character_skills()
	for restored_player: PlayerState in state.players:
		_reinstall_saved_runtime_skills(restored_player)
	_apply_skill_runtime_states(save_data.get("skill_runtime_states", {}) as Dictionary)
	# 恢复类型与行动角色；turn_start 从下一回合开始，play_phase 由同一角色继续进行中的出牌阶段。
	var resume_kind: String = str(save_data.get("resume_kind", "turn_start"))
	var acting_player_id: int = int(save_data.get("next_turn_player_id", local_human_player_id))
	if resume_kind == "play_phase":
		add_log("继续上次的过关斩将：第%d关，第%d轮，第%d回合的出牌阶段。" % [conquest_mode.get_level(), maxi(state.round_number, 1), state.turn_number])
		state.current_player_id = acting_player_id
		state.current_phase = "play"
		state.phase_index = int(save_data.get("phase_index", 3))
		# 新的回合运行时父事件；旧事件ID属于上一次会话，恢复的阶段生命周期End/After改挂到本事件。
		_current_turn_event_id = _record_runtime_event("phase", "turn", {"player_id":acting_player_id, "turn_number":state.turn_number, "round_number":state.round_number, "resumed_from_save":true})
		_remap_restored_phase_lifecycle_parents(_current_turn_event_id)
		_emit_state()
		# 重建常驻出牌询问并按当前操作者继续；真人等待输入，AI角色由统一安全出口重新调度。
		_begin_play_choice(acting_player_id)
		_emit_state()
		_ensure_ai_progress_after_resolution()
		return true
	add_log("继续上次的过关斩将：第%d关，第%d轮，第%d回合。" % [conquest_mode.get_level(), maxi(state.round_number, 1), state.turn_number + 1])
	# 恢复完成后的过渡阶段；与普通开局的回合前窗口保持同名，避免快照短暂显示无效初始化阶段。
	state.current_phase = "round_start"
	_emit_state()
	_start_turn(acting_player_id)
	return true


## 为一名恢复角色补装存档记录的获得技能与临时技能实例；固有技能已由统一安装入口创建，不会重复订阅。
## 本入口不改写 acquired_skills 或 temporary_skills 记录，存档中的剩余次数与到期轮数保持原值。
func _reinstall_saved_runtime_skills(player: PlayerState) -> void:
	if player == null:
		return
	# 永久失去技能的角色不补装任何存档技能；否则读档会让已失去的技能复活。
	if player.skills_permanently_removed:
		return
	# 当前玩家技能实例表；固有与模式技能在统一安装入口已经写入。
	var player_skills: Dictionary = skill_instances_by_player.get(player.player_id, {}) as Dictionary
	# 待补装技能ID；获得技能与临时技能共用同一运行时容器，同名只安装一次。
	var runtime_skill_ids: Array[String] = []
	for skill_id_variant: Variant in player.acquired_skills.keys():
		runtime_skill_ids.append(str(skill_id_variant))
	for skill_id_variant: Variant in player.temporary_skills.keys():
		# 当前临时技能ID；已在获得技能列表中时不重复登记。
		var temporary_skill_id: String = str(skill_id_variant)
		if not runtime_skill_ids.has(temporary_skill_id):
			runtime_skill_ids.append(temporary_skill_id)
	for skill_id: String in runtime_skill_ids:
		if player_skills.has(skill_id):
			continue
		# 新技能运行时实例；目录缺失或领袖技一律跳过，对应存档记录保留但不产生实例。
		var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
		if skill == null or skill.leader_skill:
			continue
		skill.bind(self, player.player_id)
		player_skills[skill_id] = skill
		skill.install()
	skill_instances_by_player[player.player_id] = player_skills


## 从存档回填全部回合与阶段游标；额外回合链与额外出牌阶段的进度借此跨会话保留。
## 玩家ID键的字典统一经过整数键转换，防御外部工具以字符串键改写存档。
func _restore_conquest_turn_flow_state(turn_flow: Dictionary) -> void:
	_current_turn_is_extra = bool(turn_flow.get("current_turn_is_extra", false))
	_extra_turn_queue.clear()
	for player_id_variant: Variant in turn_flow.get("extra_turn_queue", []) as Array:
		_extra_turn_queue.append(int(player_id_variant))
	_extra_turn_resume_player_ids.clear()
	for player_id_variant: Variant in turn_flow.get("extra_turn_resume_player_ids", []) as Array:
		_extra_turn_resume_player_ids.append(int(player_id_variant))
	_extra_play_phase_counts = _to_int_keyed_dictionary(turn_flow.get("extra_play_phase_counts", {}) as Dictionary)
	_extra_play_phase_returns_to_finish = _to_int_keyed_dictionary(turn_flow.get("extra_play_phase_returns_to_finish", {}) as Dictionary)
	_extra_play_phase_return_points = _to_int_keyed_dictionary(turn_flow.get("extra_play_phase_return_points", {}) as Dictionary)
	_active_extra_play_phase_context = (turn_flow.get("active_extra_play_phase_context", {}) as Dictionary).duplicate(true)
	_main_phase_play_conversions = _to_int_keyed_dictionary(turn_flow.get("main_phase_play_conversions", {}) as Dictionary)
	_active_converted_play_phase_context = (turn_flow.get("active_converted_play_phase_context", {}) as Dictionary).duplicate(true)
	_started_phase_lifecycles = (turn_flow.get("started_phase_lifecycles", {}) as Dictionary).duplicate(true)
	_cards_used_this_turn_by_player = _to_int_keyed_dictionary(turn_flow.get("cards_used_this_turn_by_player", {}) as Dictionary)


## 把任意来源字典的键统一转换为整数玩家ID；容器值深复制，标量值原样保留。
func _to_int_keyed_dictionary(source: Dictionary) -> Dictionary:
	# 转换结果；键冲突时后写入项覆盖，正常存档不会同时存在同值的整数键与字符串键。
	var result: Dictionary = {}
	for key_variant: Variant in source.keys():
		# 当前条目值；数组与字典深复制，防止恢复后的运行时与存档字典共享容器。
		var value: Variant = source[key_variant]
		if value is Dictionary:
			result[int(key_variant)] = (value as Dictionary).duplicate(true)
		elif value is Array:
			result[int(key_variant)] = (value as Array).duplicate(true)
		else:
			result[int(key_variant)] = value
	return result


## 把恢复的阶段生命周期游标重新挂到新建的回合运行时事件；旧父事件ID属于上一次会话不再有效。
func _remap_restored_phase_lifecycle_parents(new_parent_event_id: int) -> void:
	for lifecycle_key_variant: Variant in _started_phase_lifecycles.keys():
		# 当前生命周期记录；只更新父事件ID，状态游标与阶段数据保持存档原值。
		var lifecycle: Dictionary = _started_phase_lifecycles[lifecycle_key_variant] as Dictionary
		lifecycle["parent_event_id"] = new_parent_event_id
		_started_phase_lifecycles[lifecycle_key_variant] = lifecycle


## 检查身份胜负条件并结束对局。
func _check_game_over() -> void:
	if state == null or state.game_over:
		return
	# 身份规则判定的获胜方；空字符串表示继续。
	var winner: String = identity_rules.evaluate_winner(state)
	if winner.is_empty():
		return
	state.winner = winner
	state.end_reason = "identity_result"
	state.game_over = true
	state.current_phase = "game_over"
	_ai_drive_token += 1
	_ai_choice_submit_failures.clear()
	_pending_card_choice.clear()
	_pending_negation_choices.clear()
	_deferred_skill_settlements.clear()
	_rule_continuations.reset()
	_rule_sequences.clear()
	_clear_pending_judgment_request()
	state.public_card_choice_display.clear()
	state.simultaneous_response_display.clear()
	for player: PlayerState in state.players:
		player.identity_revealed = true
	_record_runtime_event("GameEndEvent", "game_end", {"reason":state.end_reason}, {"winner":winner})
	event_scheduler.abort_all("game_over:%s" % state.end_reason)
	add_log("对局结束，获胜方：%s。" % _winner_text(winner))
	_emit_state()
	match_finished.emit(winner)
	# 终局后掉线玩家不再能重连恢复座位；预约失效使后续携旧令牌的连接收到明确拒绝而非挂起等待。
	_invalidate_lan_seat_reservations()


## 在牌堆与弃牌堆均为空时以平局结束；终局原因与身份胜负阵营分开保存。
func _end_match_as_draw(reason: String) -> void:
	if state == null or state.game_over:
		return
	state.winner = "draw"
	state.end_reason = reason
	state.game_over = true
	state.current_phase = "game_over"
	_ai_drive_token += 1
	_ai_choice_submit_failures.clear()
	_pending_card_choice.clear()
	_pending_negation_choices.clear()
	_deferred_skill_settlements.clear()
	_rule_continuations.reset()
	_rule_sequences.clear()
	_clear_pending_judgment_request()
	state.public_card_choice_display.clear()
	state.simultaneous_response_display.clear()
	_record_runtime_event("GameEndEvent", "game_end", {"reason":reason}, {"winner":"draw"})
	event_scheduler.abort_all("game_over:%s" % reason)
	add_log("摸牌堆与弃牌堆均为空，对局以平局结束。")
	_emit_state()
	match_finished.emit("draw")
	# 终局后掉线玩家不再能重连恢复座位；预约失效使后续携旧令牌的连接收到明确拒绝而非挂起等待。
	_invalidate_lan_seat_reservations()


## 开启一次弃置批次；批量弃置入口在循环外层调用，使整批牌共享同一个 cardsDiscardedBatchAfter 事件。
## 批量入口必须无条件调用本函数（即使外层已有批次），嵌套弃置才能各自成批而不把内层牌计入外层。
## 返回稳定批次号；调用方必须保证随后调用 _end_discard_batch() 收尾，包括提前跳出循环的路径。
func _begin_discard_batch(player_id: int, reason: String) -> int:
	# 当前批次号；先取自增计数器再登记，保证嵌套批次的内层编号与外层不同。
	var batch_id: int = _next_discard_batch_id
	_next_discard_batch_id += 1
	_discard_batch_stack.append({
		"batch_id":batch_id,
		"player_id":player_id,
		"reason":reason,
		"card_uids":[],
	})
	return batch_id


## 结束栈顶弃置批次；先弹出再派发，使批次事件内由技能连锁产生的新弃置动作自成新批次。
func _end_discard_batch() -> void:
	if _discard_batch_stack.is_empty():
		return
	# 已完成的批次；必须先从栈中移除，否则批次事件回调内的弃置会错误追加到本批。
	var finished_batch: Dictionary = _discard_batch_stack.pop_back()
	# 本批实际弃置的牌；空批次不派发，避免出现“发动了却没有牌可判定”的空事件。
	var batch_card_uids: Array = finished_batch.get("card_uids", []) as Array
	if batch_card_uids.is_empty():
		return
	# 本次弃置的主体角色；与其弃置的牌归属一致，供“当你弃置牌时”类技能按角色过滤。
	var batch_player_id: int = int(finished_batch.get("player_id", -1))
	_emit_rule_timing("cardsDiscardedBatchAfter", batch_player_id, batch_player_id, -1, {
		"discard_batch_id":int(finished_batch.get("batch_id", -1)),
		"card_uids":batch_card_uids.duplicate(),
		"source_player_id":batch_player_id,
		"reason":str(finished_batch.get("reason", "")),
		"batch_size":batch_card_uids.size(),
	}, state.current_event_id)


## 将闪电移至下一角色时、装备效果与其他规则共用的弃牌移动基础操作。
## related_event_id 为-2时沿用当前规则事件；显式传入父事件可把 cardsDiscard 关联到对应结算。
## counts_as_discard_action 声明本次移牌是否构成一次“弃置牌”动作。
## 重铸等规则只是把牌置入弃牌堆：必须传 false，否则会多写一条“弃置了”日志并派发 cardsDiscardedBatchAfter，
## 使该牌被误判为“弃置”并错误触发【泛音】等“当你弃置牌时”类效果。
func _move_to_discard(card: CardInstance, related_event_id: int = -2, counts_as_discard_action: bool = true) -> void:
	if card == null:
		return
	_ensure_card_movement()
	# 弃置前持有者；响应牌、主动弃牌和目标区域牌都从各自实际来源锚点起飞。
	# 该来源玩家由 CardMovementService 在移动前写入 CardMoveEvent，表现层不再依赖规则调用点重复传参。
	# 弃置前区域；表现层可区分处理区、手牌、装备、判定和展示牌。
	var source_zone: String = card.zone
	# 弃置前持有者；仅玩家区域弃置写入单牌日志，处理区弃置通常已有使用/打出日志。
	var source_owner_id: int = card.owner_id
	# 单牌弃置日志；只有构成“弃置牌”动作的移动才写，重铸等置入弃牌堆的规则已有自己的公开日志。
	if counts_as_discard_action and source_owner_id >= 0 and source_zone in ["hand", "equipment", "judgment", "wooden_ox"]:
		add_log("%s弃置了%s。" % [format_player_log_name(source_owner_id), format_card_log_name(card)])
	# 弃置批次主体；只有手牌、装备与木牛“粮”的离场属于“弃置牌”，判定区与公共区域只是置入弃牌堆，不参与批次判定。
	# 被声明为非弃置动作的移动（如重铸）即使来源是手牌同样不参与批次判定。
	var batch_player_id: int = source_owner_id if counts_as_discard_action and source_owner_id >= 0 and source_zone in ["hand", "equipment", "wooden_ox"] else -1
	# 本次弃置是否自成一个批次；栈非空表示外层批量入口已经建立了更大的批次，此时只把本张计入该批次。
	var owns_batch: bool = batch_player_id >= 0 and _discard_batch_stack.is_empty()
	if owns_batch:
		_begin_discard_batch(batch_player_id, "discard")
	# 弃牌父事件；默认使用当前规则摘要，判定与直接使用牌会显式传入稳定父事件。
	var discard_parent_event_id: int = _current_rule_parent_event_id() if related_event_id == -2 else related_event_id
	# 弃牌事件；实体移动历史关联到该事件，等价表达 orderingDiscard 最终创建 cardsDiscard 的收尾关系。
	var discard_event_id: int = _record_runtime_event("cardsDiscard", "card_move", {"card_uids":[card.uid], "from_zone":source_zone, "reason":"discard"}, {}, discard_parent_event_id)
	if card_movement != null:
		var move: CardMoveEvent = _move_card_with_timings(card, "discard_pile", -1, "discard", discard_event_id)
		if move == null:
			# 移动被前置时机取消时牌并未离开原区域；隐式批次必须立即收尾，否则空批次会永久留在栈上吞掉后续弃置。
			if owns_batch:
				_end_discard_batch()
			return
	else:
		card.zone = "discard_pile"
		card.owner_id = -1
		state.discard_pile.append(card)
	# 计入当前批次；隐式批次同样登记，使单张弃置也产生一次批次事件，规则语义保持一致。
	if batch_player_id >= 0 and not _discard_batch_stack.is_empty():
		var batch_card_uids: Array = _discard_batch_stack[-1]["card_uids"] as Array
		batch_card_uids.append(card.uid)
	if owns_batch:
		_end_discard_batch()


## 通过唯一移动服务执行实体区域变化，并在移动前后派发 lose、gain、discard、equip、addJudge 与处理区标准时机；隐藏定向获得只在全部前置时机通过后重置牌面知识。
func _move_card_with_timings(card: CardInstance, to_zone: String, target_player_id: int = -1, reason: String = "move", event_id: int = -1, target_slot: String = "", visible_to: Array[int] = [], reset_hand_knowledge: bool = false) -> CardMoveEvent:
	if card == null:
		return null
	_ensure_card_movement()
	if card_movement == null:
		return null
	# 最终装备栏位；底层历史兼容约定会把空栏位视为宝物栏，因此废除校验、事件数据与实际移动必须使用同一解析结果。
	var resolved_target_slot: String = "treasure" if to_zone == "equipment" and target_slot.is_empty() else target_slot
	if to_zone in ["equipment", "judgment"]:
		# 持续区域目标玩家；统一移牌边界作为规则预览与业务入口之后的最终防线。
		var persistent_zone_target: PlayerState = state.get_player(target_player_id) if state != null else null
		if persistent_zone_target == null:
			return null
		if to_zone == "equipment":
			if not persistent_zone_target.is_valid_equipment_slot(resolved_target_slot) or persistent_zone_target.is_equipment_slot_abolished(resolved_target_slot):
				return null
		if to_zone == "judgment" and persistent_zone_target.judgment_area_abolished:
			return null
	# 手牌视为效果的清理边界；实体离开当前持有者手牌区前立即恢复原名，已经创建的虚拟使用牌或响应代理继续保存本次逻辑牌效。
	if card.has_hand_view_as() and (card.zone != "hand" or to_zone != "hand" or target_player_id != card.owner_id):
		_hand_view_as_turn_expiries.erase(card.uid)
		card.clear_hand_view_as()
	# 手牌通用标记是否应在本次移动生效时清理；前置移动时机取消时必须保留原标签。
	var should_clear_hand_mark_tags: bool = not card.hand_mark_tags.is_empty() and (card.zone != "hand" or to_zone != "hand" or target_player_id != card.owner_id)
	# 移动前区域与持有者；即使调用方已从区域数组取出实体，CardInstance 仍保存本次移动的权威来源字段。
	var source_zone: String = card.zone
	# 移动前持有者；公共区域固定为-1，玩家区域保留稳定玩家 ID。
	var source_player_id: int = card.owner_id
	# 标准移动上下文；所有时机共享同一牌 UID、区域、持有者、原因和装备槽信息。
	var timing_data: Dictionary = {
		"card_uids":[card.uid],
		"from_zone":source_zone,
		"to_zone":to_zone,
		"source_player_id":source_player_id,
		"target_player_id":target_player_id,
		"reason":reason,
		"target_slot":resolved_target_slot,
	}
	# 本次移动涉及的生命周期名称；同一移动可能同时属于失去牌、获得牌和弃置牌。
	var lifecycle_names: Array[String] = []
	if source_player_id >= 0 and source_zone in ["hand", "equipment", "judgment", "wooden_ox"]:
		lifecycle_names.append("lose")
	if to_zone == "hand" and target_player_id >= 0:
		lifecycle_names.append("gain")
	if to_zone == "discard_pile":
		lifecycle_names.append("discard")
	if to_zone == "equipment" and target_player_id >= 0:
		lifecycle_names.append("equip")
	if to_zone == "judgment" and target_player_id >= 0:
		lifecycle_names.append("addJudge")
	for lifecycle_name: String in lifecycle_names:
		# 生命周期主要角色；获得、装备和判定区添加使用目标持有者，其余移动使用原持有者。
		var lifecycle_player_id: int = target_player_id if lifecycle_name in ["gain", "equip", "addJudge"] else source_player_id
		# 生命周期开始前时机；只有目录存在对应名称时才派发，避免为 cardsDiscard 等仅有后置窗口的事件造名。
		var before_name: String = "%sBefore" % lifecycle_name
		if RuleTimingCatalog.has_timing(before_name):
			var before_event: RuleEvent = _emit_rule_timing(before_name, lifecycle_player_id, source_player_id, target_player_id, timing_data, event_id)
			if before_event != null and (before_event.cancelled or before_event.neutralized):
				return null
	for lifecycle_name: String in lifecycle_names:
		# 生命周期主要角色；与 Before 保持一致，确保 player 角色订阅不会在同一移动中漂移。
		var lifecycle_player_id: int = target_player_id if lifecycle_name in ["gain", "equip", "addJudge"] else source_player_id
		var begin_name: String = "%sBegin" % lifecycle_name
		if RuleTimingCatalog.has_timing(begin_name):
			var begin_event: RuleEvent = _emit_rule_timing(begin_name, lifecycle_player_id, source_player_id, target_player_id, timing_data, event_id)
			if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
				return null
	if reset_hand_knowledge and to_zone == "hand":
		_prepare_hidden_pile_gain(card, target_player_id)
	# 实际区域移动；所有前置时机均通过后才修改权威状态和知识集合。
	var move: CardMoveEvent = card_movement.move_card(card, to_zone, target_player_id, reason, event_id, resolved_target_slot, visible_to)
	if move == null:
		return null
	# 手牌通用标记的实际离区边界；只有区域移动确实成功后才清除，取消或底层拒绝移动时继续保留鸣弦标签。
	if should_clear_hand_mark_tags:
		card.clear_hand_mark_tags()
	# 完成后的移动上下文；补充稳定 move_id，后置技能可直接关联网络和回放增量。
	timing_data["move_id"] = move.move_id
	for lifecycle_name: String in lifecycle_names:
		var lifecycle_player_id: int = target_player_id if lifecycle_name in ["gain", "equip", "addJudge"] else source_player_id
		var end_name: String = "%sEnd" % lifecycle_name
		if RuleTimingCatalog.has_timing(end_name):
			_emit_rule_timing(end_name, lifecycle_player_id, source_player_id, target_player_id, timing_data, event_id)
	if to_zone == "discard_pile":
		_emit_rule_timing("cardsDiscardEnd", source_player_id, source_player_id, target_player_id, timing_data, event_id)
	for lifecycle_name: String in lifecycle_names:
		var lifecycle_player_id: int = target_player_id if lifecycle_name in ["gain", "equip", "addJudge"] else source_player_id
		var after_name: String = "%sAfter" % lifecycle_name
		if RuleTimingCatalog.has_timing(after_name):
			_emit_rule_timing(after_name, lifecycle_player_id, source_player_id, target_player_id, timing_data, event_id)
	if to_zone == "discard_pile":
		_emit_rule_timing("cardsDiscardAfter", source_player_id, source_player_id, target_player_id, timing_data, event_id)
		if source_player_id >= 0:
			_emit_rule_timing("loseToDiscardpileAfter", source_player_id, source_player_id, source_player_id, timing_data, event_id)
	return move


## 确保统一移牌服务绑定当前 GameState；规则测试替换状态对象时自动重建，避免跨状态持有牌引用。
func _ensure_card_movement() -> void:
	if state != null and (card_movement == null or card_movement.state != state):
		card_movement = CardMovementService.new(state)
	_bind_card_movement_service()


## 绑定当前移牌服务的唯一完成通知；重复确保服务时不会重复连接同一控制器回调。
func _bind_card_movement_service() -> void:
	if card_movement == null:
		return
	if not card_movement.card_moved.is_connected(_on_card_moved):
		card_movement.card_moved.connect(_on_card_moved)


## 接收权威移牌增量并只转发需要逐牌表现的获得、摸牌与弃牌；处理区声明由独立 CardPresentationEvent 表达。
func _on_card_moved(move_data: Dictionary, card_data: Dictionary) -> void:
	# 目标区域；当前表现层只消费进入手牌或弃牌堆的真实移动，装备和判定区继续由状态视图呈现。
	var target_zone: String = str(move_data.get("to_zone", ""))
	if target_zone != "discard_pile":
		# 实体进入新的规则生命周期；释放上一轮弃牌增量的待消费与已消费所有权，但不为 processing/equipment/judgment 创建额外动画。
		card_animation_ownership_reset_requested.emit(int(card_data.get("uid", -1)))
	if target_zone not in ["hand", "discard_pile"]:
		return
	_emit_card_transfer(
		card_data,
		int(move_data.get("source_player_id", -1)),
		str(move_data.get("from_zone", "")),
		int(move_data.get("target_player_id", -1)),
		target_zone
	)


## 发出一次只读区域移动表现；规则状态在信号发出前已经完成权威移动。
func _emit_card_transfer(card_data: Dictionary, source_player_id: int, source_zone: String, target_player_id: int, target_zone: String) -> void:
	if card_data.is_empty():
		return
	# 瞬时表现牌面副本；批次编号只附加给真正从牌堆进入本次 draw() 目标手牌的实体，不改变权威实体或卡牌历史。
	var presentation_card_data: Dictionary = card_data.duplicate(true)
	if not _active_draw_presentation_batch.is_empty() and source_zone == "draw_pile" and target_zone == "hand" and target_player_id == int(_active_draw_presentation_batch.get("player_id", -1)):
		presentation_card_data[DRAW_PRESENTATION_BATCH_ID_KEY] = int(_active_draw_presentation_batch.get("batch_id", -1))
	card_transfer_requested.emit(presentation_card_data, source_player_id, source_zone, target_player_id, target_zone)


## 在卡牌全部目标与异步选择结束后记录唯一 contentAfter；装备、判定区和弃牌目的都从同一入口完成生命周期。
func _complete_card_use_context(card_uid: int, destination: String) -> void:
	if not _card_use_contexts.has(card_uid):
		return
	# 当前卡牌生命周期上下文；只保存稳定 ID 与基础字符串，可安全跨选择暂停保留。
	var card_use_context: Dictionary = _card_use_contexts[card_uid] as Dictionary
	if bool(card_use_context.get("runtime_managed", false)):
		# 真实 CardUseEvent 自己创建唯一 contentAfter 与 after 回收；兼容恢复入口只写结果并解决当前 content token。
		card_use_context["destination"] = destination
		card_use_context["content_complete"] = true
		_card_use_contexts[card_uid] = card_use_context
		return
	# 原 CardUseEvent ID；contentAfter 必须保持其直接子事件关系，不能挂到期间产生的响应或伤害事件下。
	var card_use_event_id: int = int(card_use_context.get("event_id", -1))
	_record_runtime_event("contentAfter", "card_content", {"actor_id":int(card_use_context.get("actor_id", -1)), "card_uid":card_uid}, {"destination":destination}, card_use_event_id)
	_card_use_contexts.erase(card_uid)


## 按 UID 收尾一张仍在处理区的原始效果牌；暂停选择恢复后统一调用。
func _finalize_processing_card(card_uid: int) -> void:
	# 通用卡牌生命周期上下文；五谷等整牌异步效果只存在于该字典，不一定拥有逐目标上下文。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	# 可选逐目标上下文；普通牌、锦囊和杀在此保存原 CardUseEvent ID 与目标游标。
	var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
	# 卡牌使用父事件；活动逐目标上下文存在时让最终 cardsDiscard 始终关联原 CardUseEvent。
	var card_use_event_id: int = int(card_use_context.get("event_id", resolution_context.get("card_use_event_id", -2)))
	_complete_card_use_context(card_uid, "discard")
	if bool(card_use_context.get("runtime_managed", false)):
		# 实体移动由 CardUseEvent.after 中的 orderingDiscard -> cardsDiscard 完成，恢复路径不得提前弃置。
		return
	# 已结束卡牌的活动目标上下文；防御性清理避免旧响应在实体离开处理区后继续推进目标。
	_active_card_resolutions.erase(card_uid)
	for processing_card: CardInstance in state.processing_area:
		if processing_card.uid == card_uid:
			_move_to_discard(processing_card, card_use_event_id)
			return


## 弃牌堆洗回摸牌堆；处理区与玩家区域不参与洗牌。
func _reshuffle_discard_pile() -> void:
	if state.discard_pile.is_empty():
		return
	# 洗牌前仍留在摸牌堆的实体；观看牌堆顶需要补足候选时，这些牌必须继续保持在新洗入牌堆之上且顺序不变。
	var existing_draw_pile: Array[CardInstance] = []
	existing_draw_pile.assign(state.draw_pile)
	state.draw_pile = state.discard_pile
	state.discard_pile = []
	for card: CardInstance in state.draw_pile:
		card.zone = "draw_pile"
		card.owner_id = -1
		# 弃牌展示用的临时视为记录只属于上一轮公共区可见性；洗回牌堆后必须恢复为未展示状态。
		card.clear_hand_view_as_presentation()
		card.known_to.clear()
		card.shown = false
		card.private_owner_id = -1
	_shuffle_array(state.draw_pile)
	# 原摸牌堆从数组前端到末端的相对顺序保持不变；数组末端仍是实际牌堆顶。
	for existing_card: CardInstance in existing_draw_pile:
		state.draw_pile.append(existing_card)
	_record_runtime_event("washCard", "card_move", {"card_count":state.draw_pile.size()}, {"to_zone":"draw_pile"})
	add_log("弃牌堆已重新洗入摸牌堆。")


## 校验并追加一个使用牌候选动作。
## target_ids 保留客户端/AI 提交形态（群体牌为空数组）；normalized_target_ids 供 UI 预览暗置与联机只读预览使用。
func _append_if_legal(result: Array[Dictionary], player_id: int, card: CardInstance, requested_targets: Array[int]) -> void:
	# 自动展开后的目标；全体牌使用空请求数组即可，展开结果写入独立字段避免破坏“空数组表示群体提交”语义。
	var normalized_targets: Array[int] = card_rules.normalize_targets(player_id, card, requested_targets)
	if card_rules.validate_use(player_id, card, normalized_targets).is_empty():
		result.append({
			"action_type": "use_card",
			"actor_id": player_id,
			"card_uid": card.uid,
			"target_ids": requested_targets.duplicate(),
			"normalized_target_ids": normalized_targets.duplicate(),
			"card_definition_id": card.definition_id,
		})


## 校验并追加一条由卡牌源码生成的复杂目标动作；卡牌文件不需要复制标准动作字典结构。
func append_card_action_if_legal(result: Array[Dictionary], player_id: int, card: CardInstance, requested_targets: Array[int]) -> void:
	_append_if_legal(result, player_id, card, requested_targets)


## 在任意动作、技能或选择结算出口统一恢复AI流程；普通行动与子选择只能由本函数分流到各自调度器。
## 调用方必须位于规则效果已经应用完成的安全点；本函数不执行技能、牌效或阶段推进，只补齐缺失的异步驱动任务。
func _ensure_ai_progress_after_resolution() -> void:
	if is_gameplay_paused() or state == null or state.game_over or ai_coordinator == null or _conquest_replacement_transition_active:
		return
	if not _pending_card_choice.is_empty():
		# 当前普通选择请求；只有请求所属角色由AI控制时才补调度，人类与网络请求保持等待输入。
		var request_id: int = int(_pending_card_choice.get("request_id", -1))
		var chooser_id: int = int(_pending_card_choice.get("chooser_id", -1))
		if ai_coordinator.is_ai_controlled(chooser_id):
			_schedule_ai_card_choice_response(request_id, chooser_id)
		return
	# 同时无懈请求拥有各自的独立计时器；普通AI驱动不能在公共响应轮尚未结束时插入新动作。
	if not _pending_negation_choices.is_empty():
		return
	if state.current_phase != "play" or not ai_coordinator.is_ai_controlled(state.current_player_id):
		return
	# 同步主动技能可能已经完成旧chooseToUse但未创建下一请求；统一在安全出口补齐唯一正式出牌窗口。
	# 流程间隔等待中不得补开出牌请求，否则多步技能恢复后会出现无快照的孤儿 chooseToUse 并卡住手牌。
	if not _has_active_play_choice() and not has_pending_play_interaction():
		_begin_play_choice(state.current_player_id)
	if _has_active_play_choice() and not has_pending_play_interaction():
		_schedule_ai_action()


## 安排下一次 AI 操作；令牌保证阶段变化后旧计时器不会执行。
func _schedule_ai_action() -> void:
	if is_gameplay_paused() or state == null or state.game_over or state.current_phase != "play" or not ai_coordinator.is_ai_controlled(state.current_player_id) or has_pending_play_interaction() or not _has_active_play_choice():
		return
	if _scheduled_ai_drive_token == _ai_drive_token:
		return
	# 本次异步任务令牌；与全局令牌不一致时回调直接失效。
	var token: int = _ai_drive_token
	_scheduled_ai_drive_token = token
	_run_ai_after_delay(token)


## 等待展示延迟后请求 AI 动作，并再次进入统一 submit_action 入口。
func _run_ai_after_delay(token: int) -> void:
	# 普通 AI 行动计时器只在对局运行时累计；日志暂停期间不会到期或提交动作。
	await get_tree().create_timer(_get_effective_ai_response_delay_seconds(), false).timeout
	if _scheduled_ai_drive_token == token:
		_scheduled_ai_drive_token = -1
	if is_gameplay_paused() or token != _ai_drive_token or state == null or state.game_over or state.current_phase != "play":
		return
	# 当前 AI 玩家 ID；阶段等待期间可能已发生变化，因此在延迟后读取。
	var player_id: int = state.current_player_id
	if not ai_coordinator.is_ai_controlled(player_id):
		return
	# 当前全部合法候选；核心在决策前完成枚举，AI 无权绕过合法性。
	var legal_actions: Array[Dictionary] = get_legal_actions(player_id)
	# 动态技能条件可能在请求建立后改变；先刷新过期候选，避免【传冲】等合法技能动作提交到缺少对应按钮的旧请求。
	if _refresh_stale_ai_play_choice(player_id, legal_actions):
		if state == null or state.game_over or has_pending_play_interaction() or not _has_active_play_choice():
			_ensure_ai_progress_after_resolution()
			return
		# 刷新后的合法动作；请求建立时机可能调整状态，因此不得沿用刷新前数组。
		legal_actions = get_legal_actions(player_id)
	_ai_actions_this_turn += 1
	if _ai_actions_this_turn > max_ai_actions_per_turn:
		_submit_ai_action(PlayerAction.new("end_play", player_id))
		return
	# AI 可读取的权威完整快照；包含所有身份与手牌，但策略只能返回标准动作字典。
	var full_snapshot: Dictionary = state.to_dict(player_id, true)
	_append_limited_skill_usage_to_snapshot(full_snapshot)
	# 策略返回的动作数据；随后恢复为标准 PlayerAction 并再次校验。
	var action_data: Dictionary = ai_coordinator.request_action(player_id, full_snapshot, legal_actions)
	# AI动作可能因延迟期间的状态变化被权威入口拒绝；失败后仍须回到统一续接出口，最终受每阶段动作上限约束。
	if not _submit_ai_action(PlayerAction.from_dict(action_data)):
		_ensure_ai_progress_after_resolution()


## 接收全局 AI 响应时间设置；仅更新后续新建的计时器，已开始等待的任务保持原时长以避免补间中途跳变。
func _on_ai_response_delay_changed(delay_seconds: float) -> void:
	ai_action_delay_seconds = clampf(delay_seconds, GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS, GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS)


## 接收全局游戏速度设置；只影响之后安排的阶段切换和自动响应，已经开始的等待不会中途重置。
func _on_game_speed_changed(interval_seconds: float) -> void:
	game_flow_interval_seconds = clampf(interval_seconds, GameSettings.MIN_GAME_SPEED_INTERVAL_SECONDS, GameSettings.MAX_GAME_SPEED_INTERVAL_SECONDS)


## 返回自动行动与响应的实际等待秒数；游戏速度是全局下限，AI 独立设置可以进一步放慢决策展示。
func _get_effective_ai_response_delay_seconds() -> float:
	return maxf(ai_action_delay_seconds, game_flow_interval_seconds)


## 通过 Fisher-Yates 算法使用对局随机源原地洗牌，适用于任意 Array 类型。
func _shuffle_array(array: Array) -> void:
	for index: int in range(array.size() - 1, 0, -1):
		# 与当前位置交换的随机索引；范围包含0与当前索引。
		var swap_index: int = _rng.randi_range(0, index)
		# 临时保存当前位置元素；Variant 允许该函数复用到牌、身份与字符串数组。
		var temporary: Variant = array[index]
		array[index] = array[swap_index]
		array[swap_index] = temporary


## 将可序列化数组逐项转换为整数 UID 或玩家 ID；返回新数组，调用方后续修改不会影响网络动作负载。
func _int_array(values: Array) -> Array[int]:
	# 整数结果；保留输入顺序与重复项，具体规则入口负责判断是否允许重复。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result


## 合并两组整数集合并保持首次出现顺序；适用于排除目标、直击目标等只允许追加且不应重复的共享规则字段。
func _merge_unique_int_arrays(first_values: Array, second_values: Array) -> Array[int]:
	# 合并结果；先保留规则事件显式输出顺序，再补入同步辅助接口新增但事件副本尚未包含的成员。
	var result: Array[int] = []
	for value_variant: Variant in first_values:
		# 当前整数成员；网络与回放恢复后的弱类型数值统一转换后再去重。
		var first_value: int = int(value_variant)
		if not result.has(first_value):
			result.append(first_value)
	for value_variant: Variant in second_values:
		# 当前实时成员；已由规则事件输出的值保持原位置，不重复追加。
		var second_value: int = int(value_variant)
		if not result.has(second_value):
			result.append(second_value)
	return result


## 将可序列化数组逐项转换为字符串列表；响应模式恢复保持原顺序并去除空值。
func _string_array(values: Array) -> Array[String]:
	# 字符串结果；重复模式由创建请求时的规则入口负责去重。
	var result: Array[String] = []
	for value_variant: Variant in values:
		# 当前字符串；空值不构成合法响应模式。
		var value: String = str(value_variant)
		if not value.is_empty():
			result.append(value)
	return result


## 处理网络网关交付的行为字典；网络与本地动作共用完全相同的校验入口。
func _on_network_command_received(command_data: Dictionary) -> void:
	if network_gateway != null and network_gateway.is_lan_client():
		return
	# 当前远端发送者；仅 LAN 内置传输提供正数 peer_id，REMOTE 外部适配器可保持0并自行返回错误。
	var sender_peer_id: int = network_gateway.get_current_incoming_peer_id() if network_gateway != null else 0
	_last_action_rejection_message = ""
	if not submit_action(PlayerAction.from_dict(command_data)) and sender_peer_id > NetworkGateway.SERVER_PEER_ID:
		# 当前拒绝原因；规则入口通常已经写入明确文本，空值只用于异常扩展的稳定兜底。
		var rejection_message: String = _last_action_rejection_message if not _last_action_rejection_message.is_empty() else "房主拒绝了当前网络操作。"
		network_gateway.send_game_event_to_peer("action_rejected", {"message":rejection_message}, sender_peer_id)


## 把网络 ChoiceResponse 转换为兼容动作入口；事件运行时仍会再次校验事件、玩家、数量和候选。
func _on_network_choice_response_received(response_data: Dictionary) -> void:
	if network_gateway != null and network_gateway.is_lan_client():
		return
	var response: ChoiceResponse = ChoiceResponse.from_dict(response_data)
	var action: PlayerAction = PlayerAction.new("choice_response", response.actor_id)
	action.client_sequence = response.client_sequence
	action.payload = response.to_dict()
	submit_action(action)


## 局域网客户端接收房主定向快照；快照只驱动表现和无状态预览，不创建本地规则服务或随机源。
func _on_network_snapshot_received(snapshot_data: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_client():
		return
	_remote_snapshot = snapshot_data.duplicate(true)
	# 选将私有快照；房主把它嵌入同一可靠状态包，避免候选与公共 GameState 分两次到达造成界面闪烁。
	var selection_snapshot: Dictionary = (_remote_snapshot.get("character_selection", {}) as Dictionary).duplicate(true)
	_remote_snapshot.erase("character_selection")
	state_changed.emit(_remote_snapshot.duplicate(true))
	public_card_choice_display_changed.emit((_remote_snapshot.get("public_card_choice_display", {}) as Dictionary).duplicate(true))
	if not selection_snapshot.is_empty():
		character_selection_changed.emit(selection_snapshot)


## 局域网客户端接收只属于自己的兼容 UI 选择请求；其他玩家请求不会由网关定向到本连接。
func _on_network_choice_request_received(request_data: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_client():
		return
	# 请求选择者；兼容 UI 请求使用 chooser_id，通用 ChoiceRequest 使用 actor_id，二者均必须等于本地绑定玩家。
	var chooser_id: int = int(request_data.get("chooser_id", request_data.get("actor_id", -1)))
	if chooser_id != local_human_player_id:
		return
	card_choice_requested.emit(request_data.duplicate(true))


## 局域网客户端分发房主发送的只读表现事件；事件白名单确保网络数据只能触发既有 UI 信号。
func _on_network_game_event_received(event_type: String, event_payload: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_client():
		return
	if event_type == "log_added":
		log_added.emit(str(event_payload.get("message", "")))
	elif event_type == "action_rejected":
		action_rejected.emit(str(event_payload.get("message", "房主拒绝了当前操作。")))
	elif event_type == "card_presentation":
		card_presentation_requested.emit((event_payload.get("presentation", {}) as Dictionary).duplicate(true))
	elif event_type == "card_transfer":
		card_transfer_requested.emit(
			(event_payload.get("card", {}) as Dictionary).duplicate(true),
			int(event_payload.get("source_player_id", -1)),
			str(event_payload.get("source_zone", "")),
			int(event_payload.get("target_player_id", -1)),
			str(event_payload.get("target_zone", ""))
		)
	elif event_type == "draw_batch_started":
		draw_presentation_batch_started.emit(int(event_payload.get("batch_id", -1)), int(event_payload.get("player_id", -1)))
	elif event_type == "draw_batch_finished":
		draw_presentation_batch_finished.emit(int(event_payload.get("batch_id", -1)), int(event_payload.get("player_id", -1)))
	elif event_type == "card_animation_reset":
		card_animation_ownership_reset_requested.emit(int(event_payload.get("card_uid", -1)))
	elif event_type == "skill_activated":
		skill_activated.emit(int(event_payload.get("player_id", -1)), str(event_payload.get("skill_name", "")), (event_payload.get("context", {}) as Dictionary).duplicate(true))
	elif event_type == "equipment_activated":
		equipment_activated.emit(int(event_payload.get("player_id", -1)), str(event_payload.get("equipment_name", "")), (event_payload.get("context", {}) as Dictionary).duplicate(true))
	elif event_type == "voice_presentation":
		voice_presentation_requested.emit((event_payload.get("presentation", {}) as Dictionary).duplicate(true))
	elif event_type == "public_card_choice_display":
		public_card_choice_display_changed.emit((event_payload.get("display", {}) as Dictionary).duplicate(true))
	elif event_type == "match_finished":
		match_finished.emit(str(event_payload.get("winner", "")))
	elif event_type == "identity_behavior":
		# 房主广播的公开目标行为；客户端用本地身份模型重放同一推断，网络只承载行为本身而非房主算好的标记结果。
		_apply_replayed_identity_behavior(
			int(event_payload.get("actor_id", -1)),
			(event_payload.get("ai_profile", {}) as Dictionary).duplicate(true),
			_int_array(event_payload.get("target_ids", []) as Array)
		)
	elif event_type == "identity_response":
		# 房主广播的公开响应牌行为；上下文只含结算方向与相关角色，不含任何隐藏手牌或完整结算上下文。
		_apply_replayed_identity_response(
			int(event_payload.get("responder_id", -1)),
			str(event_payload.get("card_definition_id", "")),
			str(event_payload.get("trick_id", "")),
			(event_payload.get("response_context", {}) as Dictionary).duplicate(true)
		)


## 构建公开目标行为的广播载荷；只含房主已算好的只读身份观察配置与实际目标，不含任何隐藏状态。
func build_identity_behavior_payload(actor_id: int, ai_profile: Dictionary, target_ids: Array[int]) -> Dictionary:
	# 行为玩家稳定 ID；客户端按该 ID 更新自己身份模型中的对应条目。
	var behavior_actor_id: int = actor_id
	# 身份观察配置副本；沿用房主按当时权威快照算好的只读 AI 配置，客户端不重新推导以保证两侧证据完全一致。
	var behavior_ai_profile: Dictionary = ai_profile.duplicate(true)
	# 实际公开目标数组副本；保持声明顺序，空数组表示该行为没有目标。
	var behavior_target_ids: Array[int] = target_ids.duplicate()
	return {
		"actor_id":behavior_actor_id,
		"ai_profile":behavior_ai_profile,
		"target_ids":behavior_target_ids,
	}


## 构建公开响应牌行为的广播载荷；上下文只保留身份模型读取的三个公开键，避免整段结算上下文进入网络。
func build_identity_response_payload(responder_id: int, card_definition_id: String, trick_id: String, response_context: Dictionary) -> Dictionary:
	# 响应者稳定 ID；无懈可击的响应者即本次被观察的角色。
	var response_responder_id: int = responder_id
	# 响应牌定义 ID；客户端用本地同版本数据库解析该牌的模式与显式暴露值。
	var response_card_definition_id: String = card_definition_id
	# 原锦囊定义 ID；客户端据此还原该锦囊对目标的正负行为方向。
	var response_trick_id: String = trick_id
	# 公开响应上下文；只保留原锦囊使用者、当前目标与本次抵消方向，其余结算字段不下发。
	var public_response_context: Dictionary = {
		"source_id":int(response_context.get("source_id", -1)),
		"target_id":int(response_context.get("target_id", -1)),
		"negated":bool(response_context.get("negated", false)),
	}
	return {
		"responder_id":response_responder_id,
		"card_definition_id":response_card_definition_id,
		"trick_id":response_trick_id,
		"response_context":public_response_context,
	}


## 房主把一次公开目标行为广播给全部远端客户端；离线与 REMOTE 模式安全返回，本地观察不受影响。
func _broadcast_identity_behavior(actor_id: int, ai_profile: Dictionary, target_ids: Array[int]) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or not network_gateway.is_lan_match_active():
		return
	network_gateway.broadcast_game_event("identity_behavior", build_identity_behavior_payload(actor_id, ai_profile, target_ids))


## 房主把一次公开响应牌行为广播给全部远端客户端；网络层只承载公开结算方向，不下发任何身份推断结果。
func _broadcast_identity_response(responder_id: int, card_definition_id: String, trick_id: String, response_context: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or not network_gateway.is_lan_match_active():
		return
	network_gateway.broadcast_game_event("identity_response", build_identity_response_payload(responder_id, card_definition_id, trick_id, response_context))


## 客户端重放房主广播的公开目标行为；观察者固定为本地真人，因此本地玩家自己的行为与房主一致地不参与自动标记。
func _apply_replayed_identity_behavior(actor_id: int, ai_profile: Dictionary, target_ids: Array[int]) -> void:
	if ai_coordinator == null or actor_id < 0 or ai_profile.is_empty():
		return
	# 重放所用快照；客户端以最近一次房主快照作为身份模型的背景数据，两者都没有时不重放。
	var observation_snapshot: Dictionary = state.to_dict(-1, true) if state != null else _remote_snapshot
	if observation_snapshot.is_empty():
		return
	ai_coordinator.observe_public_behavior(observation_snapshot, actor_id, ai_profile, target_ids, local_human_player_id)


## 客户端重放房主广播的公开响应牌行为；牌面与锦囊定义从客户端本地数据库解析，不依赖网络下发完整定义。
func _apply_replayed_identity_response(responder_id: int, card_definition_id: String, trick_id: String, response_context: Dictionary) -> void:
	if ai_coordinator == null or responder_id < 0 or card_definition_id.is_empty():
		return
	# 重放所用快照；与目标行为重放共用同一来源，保证两侧证据基于同一份对局数据。
	var observation_snapshot: Dictionary = state.to_dict(-1, true) if state != null else _remote_snapshot
	if observation_snapshot.is_empty():
		return
	# 响应牌静态定义；客户端与房主使用同版本内容数据库，可直接解析响应模式与显式暴露值。
	var counter_card_definition: Dictionary = GameDatabase.get_card(card_definition_id)
	# 原锦囊静态定义；用于把本次无懈的抵消结果还原为对目标的正负行为方向。
	var response_subject_definition: Dictionary = GameDatabase.get_card(trick_id)
	if counter_card_definition.is_empty() or response_subject_definition.is_empty():
		return
	ai_coordinator.observe_card_response(observation_snapshot, responder_id, counter_card_definition, response_subject_definition, response_context, local_human_player_id)


## 清理客户端远端快照；离开房间或房主断开时调用，避免返回主菜单后仍用旧对局数据判断交互。
func clear_remote_network_state() -> void:
	_remote_snapshot.clear()


## 房主在正式开局广播或重连补发时主动重发当前状态；不推进阶段、不增加动作序号。
func replicate_current_state() -> void:
	_emit_state()


## 房主把兼容选择请求只发送给对应远端真人；本地房主和 AI 继续消费原有信号或调度器。
func _replicate_choice_request_to_remote_player(choice_data: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or not network_gateway.is_lan_match_active():
		return
	# 请求选择者稳定 ID；不存在或已掉线时不发送，断线托管由独立回调接管。
	var chooser_id: int = int(choice_data.get("chooser_id", -1))
	# 对应远端 peer；房主自身固定为1，AI与掉线玩家返回0。
	var peer_id: int = network_gateway.get_peer_id_for_player(chooser_id)
	if peer_id > NetworkGateway.SERVER_PEER_ID:
		network_gateway.send_choice_request_to_peer(choice_data, peer_id)


## 对局中远端玩家掉线后标记离线托管并注册基础 AI；当前选将、选择窗口或出牌阶段均从现有统一调度入口继续。
func _on_lan_match_peer_disconnected(player_id: int, display_name: String) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or state == null or state.game_over or player_id < 0:
		return
	# 当前断线玩家状态；已手动托管的玩家也必须切换为离线文案，并禁止后续取消托管。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	if player.auto_managed and player.auto_managed_offline:
		return
	_set_player_auto_management(player_id, true, true)
	add_log("%s已断开连接，由 AI 接管后续操作。" % display_name)


## 对局中远端玩家携令牌重连成功后恢复真人控制；网关已重绑连接映射，这里负责解除离线托管并补发私有数据。
## 解除托管复用统一托管入口：注销基础 AI、递增动作序号、向重连客户端重发裁剪快照并重发仍在等待的选择请求。
func _on_lan_match_peer_reconnected(player_id: int, display_name: String) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or state == null or player_id < 0:
		return
	# 重连玩家的权威状态；玩家缺失、终局或未处于托管时不修改任何规则字段，仅补发快照让客户端界面自行恢复。
	var player: PlayerState = state.get_player(player_id)
	if player == null or state.game_over or not player.auto_managed:
		replicate_current_state()
		return
	_set_player_auto_management(player_id, false, false)
	add_log("%s已重新连接，恢复手动操作。" % display_name)


## 使网关中全部断线座位预约失效；对局结束与重开新局时调用，旧对局的重连令牌不再能恢复座位。
## 重开新局时掉线玩家已不在真人映射内，其规则座位由 AI 正常补位，不存在可交还的托管状态。
func _invalidate_lan_seat_reservations() -> void:
	if network_gateway != null and network_gateway.is_lan_host():
		network_gateway.clear_lan_seat_reservations()


## 客户端根据房主下发的完整合法动作集合生成普通卡牌预览；该结果只控制 UI，不能替代房主最终校验。
func _get_remote_card_use_preview(player_id: int, card_uid: int, selected_target_ids: Array[int]) -> Dictionary:
	# 默认预览；没有匹配动作时仍提供稳定字段，界面可安全禁用确定按钮。
	var result: Dictionary = {
		"card_found":false,
		"can_submit":false,
		"validation_error":"当前卡牌不可用。",
		"legal_target_ids":[],
		"normalized_target_ids":selected_target_ids.duplicate(),
		"target_mode":"",
		"min_targets":0,
		"max_targets":0,
		"description":"",
	}
	if player_id != local_human_player_id or _remote_snapshot.is_empty() or bool(_remote_snapshot.get("game_over", false)):
		return result
	# 当前私有实体快照；只在本地手牌或木牛“粮”中查找，不读取其他玩家隐藏卡牌。
	var card_snapshot: Dictionary = _find_remote_owned_card_snapshot(player_id, card_uid, false)
	if card_snapshot.is_empty():
		return result
	# 当前静态卡牌定义；目标数量与说明属于公开内容数据，可在客户端本地数据库解析。
	var definition: Dictionary = GameDatabase.get_card(str(card_snapshot.get("definition_id", "")))
	result["card_found"] = true
	result["target_mode"] = str(definition.get("target_mode", ""))
	result["min_targets"] = int(definition.get("min_targets", 0))
	result["max_targets"] = int(definition.get("max_targets", 0))
	result["description"] = str(definition.get("description", ""))
	# 下一步合法目标集合；动作数组已经由房主按当前技能、装备、距离和次数修正完整枚举。
	var legal_target_ids: Array[int] = []
	# 权威动作中的最小目标数；技能或装备修正可以改变静态卡牌定义，因此从实际合法组合重新统计。
	var authoritative_minimum_target_count: int = -1
	# 权威动作中的最大目标数；用于客户端目标选择上限，避免静态 max_targets 忽略临时规则修正。
	var authoritative_maximum_target_count: int = -1
	for action_variant: Variant in _remote_snapshot.get("local_legal_actions", []) as Array:
		# 当前候选动作；只匹配同一实体的标准 use_card，不把重铸或装备动作混入目标预览。
		var action: Dictionary = action_variant as Dictionary
		if str(action.get("action_type", "")) != "use_card" or int(action.get("card_uid", -1)) != card_uid:
			continue
		# 当前动作目标；保留借刀杀人等顺序语义，前缀匹配决定下一次可点目标。
		var action_target_ids: Array[int] = _int_array(action.get("target_ids", []) as Array)
		authoritative_minimum_target_count = action_target_ids.size() if authoritative_minimum_target_count < 0 else mini(authoritative_minimum_target_count, action_target_ids.size())
		authoritative_maximum_target_count = maxi(authoritative_maximum_target_count, action_target_ids.size())
		if _int_arrays_equal(action_target_ids, selected_target_ids):
			result["can_submit"] = true
			result["validation_error"] = ""
			# 规则展开后的目标列表；群体牌 target_ids 仍为空，暗置预览必须读独立字段。
			var expanded_target_ids: Array[int] = _int_array(action.get("normalized_target_ids", []) as Array)
			if expanded_target_ids.is_empty():
				expanded_target_ids = action_target_ids.duplicate()
			result["normalized_target_ids"] = expanded_target_ids
		if _is_int_array_prefix(selected_target_ids, action_target_ids) and action_target_ids.size() > selected_target_ids.size():
			# 当前合法动作中紧随已选前缀的目标；加入去重集合供界面继续高亮。
			var next_target_id: int = action_target_ids[selected_target_ids.size()]
			if not legal_target_ids.has(next_target_id):
				legal_target_ids.append(next_target_id)
	result["legal_target_ids"] = legal_target_ids
	# 群体锦囊：提交形态目标为空，静态 max_targets 仍用于界面；权威组合数量对空数组无意义。
	var remote_target_mode: String = str(result.get("target_mode", ""))
	if remote_target_mode in ["all_players", "all_others"]:
		result["min_targets"] = int(definition.get("min_targets", 0))
		result["max_targets"] = int(definition.get("max_targets", 99))
	elif authoritative_minimum_target_count >= 0:
		result["min_targets"] = authoritative_minimum_target_count
		result["max_targets"] = authoritative_maximum_target_count
	return result


## 客户端根据房主合法动作集合生成装备主动预览；当前实现通用支持“材料为动作牌”和“装备为动作牌”两类元数据。
func _get_remote_equipment_action_preview(player_id: int, equipment_uid: int, payload: Dictionary, selected_target_ids: Array[int]) -> Dictionary:
	if player_id != local_human_player_id or _remote_snapshot.is_empty():
		return {}
	# 当前装备快照；只从本地玩家公开装备区按实体 UID 查找。
	var equipment_snapshot: Dictionary = _find_remote_owned_card_snapshot(player_id, equipment_uid, true)
	if equipment_snapshot.is_empty():
		return {}
	# 当前装备定义；主动动作类型、材料数量和动作牌来源均由卡牌源码元数据前置声明。
	var definition: Dictionary = GameDatabase.get_card(str(equipment_snapshot.get("definition_id", "")))
	# 装备声明的出牌阶段动作类型；空值表示该装备没有可从此入口发动的主动动作。
	var action_type: String = str(definition.get("play_phase_action_type", ""))
	# 装备动作要求的材料数量；客户端据此判断是否具备形成完整合法动作的可能。
	var required_material_count: int = int(definition.get("play_phase_material_count", 0))
	# 动作牌来源模式；material 表示材料本身作为动作牌，其余模式使用装备实体作为动作牌。
	var action_card_source: String = str(definition.get("play_phase_action_card_source", "equipment"))
	# 当前客户端已选材料；顺序只用于提交表现，合法动作匹配按成员集合处理。
	var material_card_uids: Array[int] = _int_array(payload.get("material_card_uids", []) as Array)
	# 匹配当前材料的权威合法动作；只有完整材料组合才会产生候选。
	var matching_actions: Array[Dictionary] = []
	for action_variant: Variant in _remote_snapshot.get("local_legal_actions", []) as Array:
		# 当前权威合法动作；必须同时匹配动作类型、装备实体与已选材料。
		var action: Dictionary = action_variant as Dictionary
		if str(action.get("action_type", "")) != action_type:
			continue
		if action_card_source == "material":
			if material_card_uids.size() == 1 and int(action.get("card_uid", -1)) == material_card_uids[0]:
				matching_actions.append(action)
		else:
			# 动作 payload 中的材料；丈八蛇矛等装备以装备 UID 作为 card_uid，并单独保存材料数组。
			var action_material_uids: Array[int] = _int_array(((action.get("payload", {}) as Dictionary).get("material_card_uids", []) as Array))
			if int(action.get("card_uid", -1)) == equipment_uid and _int_arrays_have_same_members(action_material_uids, material_card_uids):
				matching_actions.append(action)
	# 装备预览默认值；说明来自本地静态定义，目标字段由匹配动作补齐。
	var result: Dictionary = {
		"card_found":material_card_uids.size() == required_material_count and not matching_actions.is_empty(),
		"can_submit":false,
		"validation_error":"请选择符合要求的手牌材料。",
		"legal_target_ids":[],
		"normalized_target_ids":selected_target_ids.duplicate(),
		"target_mode":"single_other",
		"min_targets":1,
		"max_targets":1,
		"description":str(definition.get("description", "")),
	}
	# 木牛流马的可选转移目标不会加入 AI 合法动作枚举；客户端可从公开存活快照生成提示，房主仍会最终校验。
	if action_type == "store_wooden_ox" and not matching_actions.is_empty():
		# 可选转移目标列表；只包含本地玩家以外仍存活的公开角色。
		var optional_target_ids: Array[int] = []
		for player_variant: Variant in _remote_snapshot.get("players", []) as Array:
			# 当前公开玩家快照；只读取稳定 ID 与存活状态，不访问任何隐藏牌面。
			var player_snapshot: Dictionary = player_variant as Dictionary
			# 当前候选玩家稳定 ID；无效值 -1 不会通过其他玩家及存活条件。
			var target_id: int = int(player_snapshot.get("player_id", -1))
			if target_id != player_id and bool(player_snapshot.get("alive", true)):
				optional_target_ids.append(target_id)
		result["card_found"] = material_card_uids.size() == required_material_count
		result["can_submit"] = selected_target_ids.is_empty() or (selected_target_ids.size() == 1 and optional_target_ids.has(selected_target_ids[0]))
		result["validation_error"] = "" if bool(result["can_submit"]) else "木牛流马的转移目标不合法。"
		result["legal_target_ids"] = optional_target_ids
		result["target_mode"] = "optional_single_other"
		result["min_targets"] = 0
		return result
	# 普通装备动作；使用完整合法动作目标数组执行前缀与精确匹配。
	var legal_target_ids: Array[int] = []
	for action: Dictionary in matching_actions:
		# 当前装备动作的有序目标数组；顺序影响多目标装备动作的后续选择提示。
		var action_target_ids: Array[int] = _int_array(action.get("target_ids", []) as Array)
		if _int_arrays_equal(action_target_ids, selected_target_ids):
			result["can_submit"] = true
			result["validation_error"] = ""
		if _is_int_array_prefix(selected_target_ids, action_target_ids) and action_target_ids.size() > selected_target_ids.size():
			# 当前匹配动作的下一合法目标；重复目标只保留一次高亮记录。
			var next_target_id: int = action_target_ids[selected_target_ids.size()]
			if not legal_target_ids.has(next_target_id):
				legal_target_ids.append(next_target_id)
	result["legal_target_ids"] = legal_target_ids
	return result


## 在远端裁剪快照中按 UID 查找本地玩家拥有的牌；equipment_only 决定搜索装备区或手牌与木牛区。
func _find_remote_owned_card_snapshot(player_id: int, card_uid: int, equipment_only: bool) -> Dictionary:
	for player_variant: Variant in _remote_snapshot.get("players", []) as Array:
		# 当前玩家快照；只处理与本地稳定玩家 ID 匹配的私有对象。
		var player_snapshot: Dictionary = player_variant as Dictionary
		if int(player_snapshot.get("player_id", -1)) != player_id:
			continue
		if equipment_only:
			for equipment_variant: Variant in (player_snapshot.get("equipment", {}) as Dictionary).values():
				# 当前公开装备实体；装备区牌面公开，可直接按 UID 返回完整副本。
				var equipment: Dictionary = equipment_variant as Dictionary
				if int(equipment.get("uid", -1)) == card_uid:
					return equipment.duplicate(true)
			return {}
		for card_variant: Variant in player_snapshot.get("hand", []) as Array:
			# 当前本地手牌实体；裁剪快照只会为观察者本人提供完整牌面。
			var hand_card: Dictionary = card_variant as Dictionary
			if int(hand_card.get("uid", -1)) == card_uid:
				return hand_card.duplicate(true)
		for card_variant: Variant in player_snapshot.get("wooden_ox_storage", []) as Array:
			# 当前木牛私有存牌实体；与手牌采用相同 UID 查找和副本返回规则。
			var stored_card: Dictionary = card_variant as Dictionary
			if int(stored_card.get("uid", -1)) == card_uid:
				return stored_card.duplicate(true)
		return {}
	return {}


## 判断两个整数数组是否逐项相等；目标选择顺序具有规则语义，不能使用无序集合比较。
func _int_arrays_equal(first_values: Array[int], second_values: Array[int]) -> bool:
	if first_values.size() != second_values.size():
		return false
	for index: int in range(first_values.size()):
		if first_values[index] != second_values[index]:
			return false
	return true


## 判断已选目标是否为某条完整合法动作目标的顺序前缀；用于借刀杀人等分步多目标高亮。
func _is_int_array_prefix(prefix_values: Array[int], complete_values: Array[int]) -> bool:
	if prefix_values.size() > complete_values.size():
		return false
	for index: int in range(prefix_values.size()):
		if prefix_values[index] != complete_values[index]:
			return false
	return true


## 判断两个材料 UID 数组是否包含相同成员；装备材料顺序不改变规则结果，但重复 UID 仍会因计数不等被拒绝。
func _int_arrays_have_same_members(first_values: Array[int], second_values: Array[int]) -> bool:
	if first_values.size() != second_values.size():
		return false
	for value: int in first_values:
		if not second_values.has(value):
			return false
	return true


## 将一条规则日志广播给全部局域网客户端；日志文本属于公开语义，不包含节点或可执行对象。
func _replicate_log_event(message: String) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("log_added", {"message":message})


## 广播公开牌面表现；发送前移除“哪些玩家曾私下知晓此牌”等不影响画面的内部可见性元数据。
func _replicate_card_presentation_event(presentation_data: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or not network_gateway.is_lan_match_active():
		return
	# 可发送表现副本；卡牌已经进入使用、展示或判定公共事件，牌面本身可公开。
	var safe_presentation: Dictionary = presentation_data.duplicate(true)
	# 可发送牌面副本；移除仅供权威端追踪隐藏知识的内部字段后再广播。
	var safe_card: Dictionary = (safe_presentation.get("card_data", {}) as Dictionary).duplicate(true)
	safe_card.erase("known_to")
	safe_card.erase("private_owner_id")
	safe_presentation["card_data"] = safe_card
	network_gateway.broadcast_game_event("card_presentation", {"presentation":safe_presentation})


## 广播技能发动与卡牌使用、打出的语音表现；负载只含已公开数据，不泄露手牌归属、身份或随机种子。
func _replicate_voice_presentation_event(presentation_data: Dictionary) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or not network_gateway.is_lan_match_active():
		return
	# 可发送副本；音频负载本身不含任何隐藏知识，深复制后即可安全广播给全部客户端。
	var safe_presentation: Dictionary = presentation_data.duplicate(true)
	network_gateway.broadcast_game_event("voice_presentation", {"presentation":safe_presentation})


## 按观察者裁剪牌区移动表现；非当事人看到摸牌或私有手牌转移时只收到 UID 和统一牌背语义。
func _replicate_card_transfer_event(card_data: Dictionary, source_player_id: int, source_zone: String, target_player_id: int, target_zone: String) -> void:
	if network_gateway == null or not network_gateway.is_lan_host() or not network_gateway.is_lan_match_active():
		return
	for peer_id_variant: Variant in network_gateway.get_remote_player_assignments().keys():
		# 当前远端网络 peer；每个观察者需要独立裁剪同一次移动表现。
		var peer_id: int = int(peer_id_variant)
		# 当前 peer 对应的稳定玩家 ID；决定该观察者是否为私有牌转移当事人。
		var viewer_id: int = int(network_gateway.get_remote_player_assignments().get(peer_id, -1))
		# 当前观察者能否看到完整牌面；公共来源、公开弃牌和转移当事人均可见。
		var reveal_card: bool = target_zone == "discard_pile" or source_player_id == viewer_id or target_player_id == viewer_id or source_zone not in ["draw_pile", "hand", "wooden_ox"]
		# 观察者牌面副本；未知牌只保留动画去重 UID 与可选摸牌批次编号。
		var viewer_card: Dictionary = card_data.duplicate(true) if reveal_card else {"uid":int(card_data.get("uid", -1))}
		if card_data.has(DRAW_PRESENTATION_BATCH_ID_KEY):
			viewer_card[DRAW_PRESENTATION_BATCH_ID_KEY] = int(card_data.get(DRAW_PRESENTATION_BATCH_ID_KEY, -1))
		viewer_card.erase("known_to")
		viewer_card.erase("private_owner_id")
		network_gateway.send_game_event_to_peer("card_transfer", {
			"card":viewer_card,
			"source_player_id":source_player_id,
			"source_zone":source_zone,
			"target_player_id":target_player_id,
			"target_zone":target_zone,
		}, peer_id)


## 广播摸牌表现批次开始；该事件只包含批次与目标玩家 ID，不包含牌面。
func _replicate_draw_batch_started_event(batch_id: int, player_id: int) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("draw_batch_started", {"batch_id":batch_id, "player_id":player_id})


## 广播摸牌表现批次完成；客户端据此统一播放已经按观察者裁剪的批次卡牌。
func _replicate_draw_batch_finished_event(batch_id: int, player_id: int) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("draw_batch_finished", {"batch_id":batch_id, "player_id":player_id})


## 广播牌面动画所有权重置信号；只含公开稳定 UID，不携带规则状态。
func _replicate_card_animation_reset_event(card_uid: int) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("card_animation_reset", {"card_uid":card_uid})


## 广播已经实际发动的技能提示；上下文必须保持可序列化，只供目标线与中央提示消费。
func _replicate_skill_activated_event(player_id: int, skill_name: String, context: Dictionary) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("skill_activated", {"player_id":player_id, "skill_name":skill_name, "context":context.duplicate(true)})


## 广播已经实际生效的装备提示；不发送装备运行时实例或触发订阅。
func _replicate_equipment_activated_event(player_id: int, equipment_name: String, context: Dictionary) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("equipment_activated", {"player_id":player_id, "equipment_name":equipment_name, "context":context.duplicate(true)})


## 广播公共选牌展示变化；五谷丰登等固定牌位对全部观察者可见，私有候选仍走定向选择请求。
func _replicate_public_card_choice_display_event(display_data: Dictionary) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("public_card_choice_display", {"display":display_data.duplicate(true)})


## 广播终局结果；客户端只更新表现和后续按钮，不在本地重复执行奖惩或胜负判定。
func _replicate_match_finished_event(winner: String) -> void:
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		network_gateway.broadcast_game_event("match_finished", {"winner":winner})


## 返回当前规则调用可关联的父事件 ID；无有效摘要时回退到长期对局根事件。
func _current_rule_parent_event_id() -> int:
	if state != null and state.current_event_id >= 0:
		return state.current_event_id
	return _runtime_root_event_id


## 创建并发送统一牌面表现事件；表现只携带序列化数据，不暂停规则或持有 CardInstance 引用。
func _request_card_presentation(card: CardInstance, actor_id: int, target_ids: Array[int], event_name: String, event_id: int, owns_discard_transfer: bool, indicator_stages: Array[Dictionary] = []) -> void:
	if card == null:
		return
	_card_presentation_sequence += 1
	# 表现事件；递增编号、规则父事件和弃牌所有权共同决定客户端去重与回放顺序。
	var presentation: CardPresentationEvent = CardPresentationEvent.new(
		_card_presentation_sequence,
		event_id,
		event_name,
		card.to_dict(),
		actor_id,
		target_ids,
		owns_discard_transfer,
		indicator_stages
	)
	card_presentation_requested.emit(presentation.to_dict())


## 写入一项武将牌左上角公开文本；相同来源ID会原位更新，多个来源由控制器按排序值稳定合成。
## view_kind 为空时表示纯文本角标，行为与既有实现完全一致；非空时表示该条目由表现层渲染为可点击按钮。
## 按钮条目不参与 character_corner_text 文本合成，因此不会改变该字符串被AI评估与既有测试断言的取值集合。
## 该参数只在状态层与快照间中性透传，控制器不解释其含义，具体打开哪种只读界面由表现层按映射决定。
func set_character_corner_text_entry(player_id: int, entry_id: String, display_text: String, order: int = 0, view_kind: String = "") -> bool:
	# 目标角色；无效角色或空来源ID不能建立无法清理的公开状态。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or entry_id.is_empty():
		return false
	if display_text.is_empty():
		return remove_character_corner_text_entry(player_id, entry_id)
	player.character_corner_text_entries[entry_id] = {"text":display_text, "order":order, "view_kind":view_kind}
	_refresh_character_corner_text(player)
	refresh_public_state_snapshot()
	return true


## 移除指定来源的武将牌左上角公开文本；其他技能条目继续保留并重新合成。
func remove_character_corner_text_entry(player_id: int, entry_id: String) -> bool:
	# 目标角色；不存在的条目保持幂等失败，不影响当前合成文本。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or entry_id.is_empty() or not player.character_corner_text_entries.has(entry_id):
		return false
	player.character_corner_text_entries.erase(entry_id)
	_refresh_character_corner_text(player)
	refresh_public_state_snapshot()
	return true


## 按排序值与来源ID合成武将牌左上角文本；相同显示文本只渲染一次，但各来源仍可独立移除。
func _refresh_character_corner_text(player: PlayerState) -> void:
	if player == null:
		return
	# 待排序条目；每项保存稳定来源ID、显示文本与整数顺序。
	var ordered_entries: Array[Dictionary] = []
	for entry_id_variant: Variant in player.character_corner_text_entries.keys():
		# 当前来源ID；字符串次序作为相同order时的稳定次级排序。
		var entry_id: String = str(entry_id_variant)
		# 当前条目数据；异常旧格式安全回退为空文本并在后续跳过。
		var entry_data: Dictionary = player.character_corner_text_entries.get(entry_id_variant, {}) as Dictionary
		# 当前显示文本；空文本不占用武将牌提示区域。
		var display_text: String = str(entry_data.get("text", ""))
		if display_text.is_empty():
			continue
		# 按钮条目只供表现层渲染可点击控件，不进入文本合成；旧存档条目没有view_kind字段，取默认空值走原路径。
		if not str(entry_data.get("view_kind", "")).is_empty():
			continue
		# 当前排序记录；插入排序避免依赖闭包或运行时对象进入状态层。
		var sortable_entry: Dictionary = {"entry_id":entry_id, "text":display_text, "order":int(entry_data.get("order", 0))}
		# 当前插入位置；order较小的条目优先显示，相同order按来源ID字典序排列。
		var insertion_index: int = ordered_entries.size()
		for existing_index: int in range(ordered_entries.size()):
			# 已存在排序记录；仅用于比较稳定基础字段。
			var existing_entry: Dictionary = ordered_entries[existing_index]
			if int(sortable_entry.get("order", 0)) < int(existing_entry.get("order", 0)) or (int(sortable_entry.get("order", 0)) == int(existing_entry.get("order", 0)) and entry_id < str(existing_entry.get("entry_id", ""))):
				insertion_index = existing_index
				break
		ordered_entries.insert(insertion_index, sortable_entry)
	# 已显示文本集合；多个同名持续效果共享一行提示，任一来源移除不会误删仍存在的其他来源。
	var displayed_texts: Dictionary = {}
	# 最终文本行；换行交给现有左上角提示组件直接渲染。
	var text_lines: Array[String] = []
	for entry: Dictionary in ordered_entries:
		# 当前合成文本；重复名称不再追加第二行。
		var text_line: String = str(entry.get("text", ""))
		if displayed_texts.has(text_line):
			continue
		displayed_texts[text_line] = true
		text_lines.append(text_line)
	player.character_corner_text = "\n".join(text_lines)


## 立即发布当前权威状态快照；内容脚本在公开持续状态于规则时机内结束时调用，不能借此修改任何规则数据。
func refresh_public_state_snapshot() -> void:
	_emit_state()


## 写入一条迁移期规则事件记录并同步 GameState；所有记录默认挂在当前对局根事件下。
func _record_runtime_event(event_name: String, event_type: String, context: Dictionary = {}, result: Dictionary = {}, parent_id: int = -2) -> int:
	if event_scheduler == null:
		return -1
	# 实际父事件 ID；-2 表示使用根事件，-1 明确表示独立根级事件。
	var resolved_parent_id: int = _runtime_root_event_id if parent_id == -2 else parent_id
	var event_id: int = event_scheduler.record_event(event_name, event_type, context, resolved_parent_id, result)
	if state != null:
		state.current_event_id = event_id
		_append_runtime_history_record()
	return event_id


## 创建并派发一条标准规则时机；player/source/target 分别用于四角色触发关系，数据只允许基础可序列化值。
func emit_rule_timing(event_name: String, player_id: int = -1, source_id: int = -1, target_id: int = -1, event_data: Dictionary = {}, parent_id: int = -2) -> RuleEvent:
	return _emit_rule_timing(event_name, player_id, source_id, target_id, event_data, parent_id)


## 步骤内容的时机入口；派发前登记原事件所有权，触发预算耗尽后可直接让出当前帧。
## 下一步骤读取sequence.waiting_event的最终data；不要在本次调用后同步消费窗口结果。
func emit_sequence_timing(sequence: RuleStepSequence, event_name: String, player_id: int = -1, source_id: int = -1, target_id: int = -1, event_data: Dictionary = {}, parent_id: int = -2) -> RuleEvent:
	# 步骤拥有的原事件；不在玩法data中混入恢复标志。
	var event: RuleEvent = RuleEvent.new(event_name, source_id, target_id, event_data, player_id)
	event.step_owned = true
	sequence.wait_for_timing(event)
	return _dispatch_rule_event(event, parent_id)


## 控制器内部标准时机入口；公共内容端口与核心流程共用同一派发、排序和历史记录实现。
func _emit_rule_timing(event_name: String, player_id: int = -1, source_id: int = -1, target_id: int = -1, event_data: Dictionary = {}, parent_id: int = -2) -> RuleEvent:
	# 当前规则事件；构造函数深复制上下文，避免触发完成后仍被调用方修改。
	var event: RuleEvent = RuleEvent.new(event_name, source_id, target_id, event_data, player_id)
	return _dispatch_rule_event(event, parent_id)


## 统一派发同步规则事件；普通总线后按四角色、firstDo、优先级和座次执行新触发器，最终写入事件历史。
func _dispatch_rule_event(event: RuleEvent, parent_id: int = -2) -> RuleEvent:
	if event == null:
		return null
	# 实际父事件；-2沿用当前事件栈，显式-1允许创建独立迁移记录。
	var resolved_parent_id: int = _current_rule_parent_event_id() if parent_id == -2 else parent_id
	event.event_id = state.current_event_id if state != null else -1
	event.parent_id = resolved_parent_id
	_dispatch_timing_service_event(event)
	_record_runtime_event(event.name, "trigger", {"player_id":event.player_id, "source_id":event.source_id, "target_id":event.target_id, "data":event.data.duplicate(true)}, event.to_dict(), resolved_parent_id)
	return event


## 以可暂停模式派发一条规则时机；所有入口包括 CardUseEvent 子事件都共用此封装，确保同一时机的技能按座次依次询问。
func _dispatch_timing_service_event(event: RuleEvent) -> void:
	if event == null:
		return
	_ensure_timing_service()
	# 派发前已有的请求 ID；只有回调新建的选择才会暂停当前触发续列，嵌套时机结束后恢复外层快照。
	var previous_initial_choice_request_id: int = _rule_timing_initial_choice_request_id
	# 外层派发状态；嵌套时机返回后必须恢复，避免把后续非时机选择误识别为等待触发的技能。
	var previous_dispatching_state: bool = _is_dispatching_rule_timing
	# 派发前已存在的触发续列数；嵌套调用只同步排空自己新建的分片，不越过旧外层选择续列。
	var deferred_dispatch_count_before: int = trigger_manager.get_deferred_dispatch_count() if trigger_manager != null else 0
	_rule_timing_initial_choice_request_id = int(_pending_card_choice.get("request_id", -1))
	_is_dispatching_rule_timing = true
	timing_service.dispatch(event)
	# 纯同步父牌效还不能在返回后跨帧保留调用栈；因此无选择的新分片必须在父逻辑继续前受控排空。
	# 已创建真实选择时依然保留续列，由选择提交后的统一结算管线恢复。
	var synchronous_resume_slice_count: int = 0
	while not event.step_owned and trigger_manager != null and not has_pending_card_choice() and (trigger_manager.is_dispatch_deferred(event) or trigger_manager.get_deferred_dispatch_count() > deferred_dispatch_count_before):
		if synchronous_resume_slice_count >= maxi(max_settlement_steps_per_pass, 1):
			# 超限时终止的当前触发子树事件数；清空后父规则可按取消结果继续安全收尾。
			var aborted_dispatch_count: int = trigger_manager.abort_all_deferred_dispatches("trigger_dispatch_slice_limit")
			if not event.is_terminal():
				event.cancel("trigger_dispatch_slice_limit")
			_record_settlement_fault("trigger_dispatch_slice_limit", {
				"event_name":event.name,
				"resume_slice_count":synchronous_resume_slice_count,
				"aborted_dispatch_count":aborted_dispatch_count,
			})
			break
		synchronous_resume_slice_count += 1
		timing_service.resume_next_deferred_dispatch()
	_is_dispatching_rule_timing = previous_dispatching_state
	_rule_timing_initial_choice_request_id = previous_initial_choice_request_id


## 确保时机服务始终绑定当前状态、总线和重新开局后新建的 TriggerManager；测试替换 GameState 时也无需手工重建。
func _ensure_timing_service() -> void:
	if trigger_manager == null:
		trigger_manager = TriggerManager.new()
	_configure_rule_dispatch_guards()
	if timing_service == null:
		timing_service = RuleTimingService.new(event_bus, trigger_manager, state)
	else:
		timing_service.configure(event_bus, trigger_manager, state)
	timing_service.set_trigger_pause_condition(Callable(self, "_should_pause_rule_timing_dispatch"))


## 把检查器中的分片与递归上限同步给当前普通总线和有序触发器；重建或测试替换实例后也可重复调用。
func _configure_rule_dispatch_guards() -> void:
	if event_bus != null:
		event_bus.max_nested_dispatch_depth = max_rule_timing_dispatch_depth
		if not event_bus.dispatch_faulted.is_connected(_on_rule_dispatch_faulted):
			event_bus.dispatch_faulted.connect(_on_rule_dispatch_faulted)
	if trigger_manager != null:
		trigger_manager.max_handlers_per_slice = max_trigger_handlers_per_slice
		trigger_manager.max_nested_dispatch_depth = max_rule_timing_dispatch_depth
		if not trigger_manager.dispatch_faulted.is_connected(_on_rule_dispatch_faulted):
			trigger_manager.dispatch_faulted.connect(_on_rule_dispatch_faulted)


## 接收普通总线或有序触发器的局部熔断；统一转成结算故障，不再触发任何规则时机。
func _on_rule_dispatch_faulted(dispatch_fault: Dictionary) -> void:
	# 派发层故障副本；嵌套字典保留原始reason、事件名与深度便于诊断。
	var stable_dispatch_fault: Dictionary = dispatch_fault.duplicate(true)
	_record_settlement_fault("rule_timing_dispatch_fault", {"dispatch_fault":stable_dispatch_fault})


## 判断当前有序触发是否应在本技能询问后暂停；派发前已存在的响应或选牌不会被误识别为新询问。
func _should_pause_rule_timing_dispatch() -> bool:
	if not _is_dispatching_rule_timing or _pending_card_choice.is_empty():
		return false
	return int(_pending_card_choice.get("request_id", -1)) != _rule_timing_initial_choice_request_id


## 在一个选择完整恢复且没有后续选择时继续询问同一时机的剩余技能；续列可再次创建选择并保持原座次顺序。
func _resume_deferred_rule_timing_dispatches() -> void:
	if timing_service == null or has_pending_card_choice() or state == null or state.game_over:
		return
	# 续列回调同样可能新建下一条技能询问；复用派发标记以让 TriggerManager 再次安全暂停。
	var previous_initial_choice_request_id: int = _rule_timing_initial_choice_request_id
	var previous_dispatching_state: bool = _is_dispatching_rule_timing
	_rule_timing_initial_choice_request_id = -1
	_is_dispatching_rule_timing = true
	# 每次只恢复最内层一条续列；管线会在两条续列之间优先检查该技能新建的判定或其他子流程。
	timing_service.resume_next_deferred_dispatch()
	_is_dispatching_rule_timing = previous_dispatching_state
	_rule_timing_initial_choice_request_id = previous_initial_choice_request_id


## 把一条运行时历史增量追加到 GameState；相同 sequence 已存在时不会重复写入。
## 当前实现由调度器共享追加最新不可变记录，调用方不再取得或复制整条字典。
func _append_runtime_history_record() -> void:
	if state == null or event_scheduler == null:
		return
	# 历史条目写入后保持不可变；状态层只拥有独立数组结构，与调度器共享字典可消除长局回放的第二份深拷贝。
	event_scheduler.append_latest_history_reference_to(state.event_history)


## 运行时事件开始回调；只把摘要 ID 和历史写入权威状态，不暴露 GameEvent 可变引用。
func _on_runtime_event_started(event_data: Dictionary) -> void:
	if state == null:
		return
	state.current_event_id = int(event_data.get("event_id", -1))
	_append_runtime_history_record()


## 运行时事件完成回调；父事件 ID 成为当前摘要，根级完成后回到对局根事件。
func _on_runtime_event_finished(event_data: Dictionary) -> void:
	if state == null:
		return
	state.current_event_id = int(event_data.get("parent_id", _runtime_root_event_id))
	if state.current_event_id < 0:
		state.current_event_id = _runtime_root_event_id
	_append_runtime_history_record()


## 记录事件运行时的无等待死循环熔断；故障事件已经被调度器中断，本入口只同步历史并向玩家给出长期可诊断日志。
func _on_runtime_event_faulted(fault_data: Dictionary) -> void:
	if state == null:
		return
	_append_runtime_history_record()
	# 故障事件名称与步骤；日志不包含Callable或内部对象，联机客户端可沿既有日志复制通道看到相同保护结果。
	var event_name: String = str(fault_data.get("event_name", "unknown"))
	# 故障步骤下标；-1仅用于防御异常旧摘要，正常熔断始终提供实际步骤。
	var event_step: int = int(fault_data.get("step", -1))
	add_log("【流程保护】事件%s的步骤%d发生无等待循环，已中断该事件并继续父流程。" % [event_name, event_step])


## 运行时选择请求回调；保存完整权威摘要，GameState.to_dict 后续可按观察者继续裁剪候选。
func _on_runtime_choice_requested(request_data: Dictionary) -> void:
	if state == null:
		return
	state.current_choice_request = request_data.duplicate(true)
	state.current_event_id = int(request_data.get("event_id", state.current_event_id))
	_append_runtime_history_record()
	if network_gateway != null and network_gateway.mode == NetworkGateway.Mode.REMOTE:
		# 联网请求对象；从运行时快照恢复基础字段后交给网关发送，传输端不获得 Callable。
		var request: ChoiceRequest = ChoiceRequest.from_dict(request_data)
		network_gateway.send_choice_request(request)


## 运行时选择完成回调；只清除匹配的当前请求，避免新请求被旧响应回调误删。
func _on_runtime_choice_resolved(request_data: Dictionary, _response_data: Dictionary) -> void:
	if state == null:
		return
	if int(state.current_choice_request.get("request_id", -1)) == int(request_data.get("request_id", -2)):
		state.current_choice_request.clear()
	_append_runtime_history_record()


## 为机缘选择队列同步当前操作者；只处理离线全角色控制归属，不生成或广播完整对局快照。
func prepare_opportunity_chooser(player_id: int) -> void:
	_prepare_offline_controlled_view(player_id)


## 公开刷新当前状态快照；独立规则组件完成自身可序列化状态更新后通过本入口通知UI与网络。
func refresh_state_snapshot() -> void:
	_emit_state()


## 向现有观察者快照补充每名角色已经发动的限定技ID；运行时技能对象仍留在权威控制器内，不进入网络或UI。
func _append_limited_skill_usage_to_snapshot(snapshot: Dictionary) -> void:
	for player_variant: Variant in snapshot.get("players", []) as Array:
		# 当前玩家快照；已发动限定技是公开事实，所有观察者读取相同稳定ID数组。
		var player_snapshot: Dictionary = player_variant as Dictionary
		# 当前玩家ID；无效占位玩家获得空数组，不尝试读取运行时技能表。
		var player_id: int = int(player_snapshot.get("player_id", -1))
		player_snapshot["used_limited_skill_ids"] = get_used_limited_skill_ids(player_id) if player_id >= 0 else []
		# 已消耗固有额度的全部技能ID；额外包含觉醒技，供技能按钮把觉醒技也显示为“已释放”变淡状态。
		# 与 used_limited_skill_ids 分开维护：【光覆】等复原入口只处理普通限定技，不能因界面需要而改变其候选集合。
		player_snapshot["used_intrinsic_use_skill_ids"] = get_used_limited_skill_ids(player_id, true) if player_id >= 0 else []


## 发出面向本地玩家的状态快照，并让网络网关保留公共同步入口。
func _emit_state() -> void:
	if state == null:
		return
	_prepare_offline_controlled_view()
	# 正常运行时历史由事件信号逐条增量同步；只有计数失配才执行全量校准，避免长对局每次界面刷新都复制完整回放。
	if event_scheduler != null and state.event_history.size() != event_scheduler.get_event_history_count():
		state.event_history = event_scheduler.get_event_history_reference_copy()
	# 本地界面快照；仅公开本地玩家手牌和自身身份。
	var local_snapshot: Dictionary = state.to_dict(local_human_player_id, false)
	_append_limited_skill_usage_to_snapshot(local_snapshot)
	# 本地手气卡私有状态；只包含本人的剩余张数与按钮权限。
	local_snapshot["starting_hand_mulligan"] = starting_hand_mulligan.to_dict(local_human_player_id) if state.current_phase == "starting_hand_mulligan" and starting_hand_mulligan != null else {}
	# 本地待办请求清单；并行无懈会让本人同时拥有多条请求，界面据此对账而不是依赖单槽位请求编号。
	local_snapshot["local_pending_choice_request_ids"] = _get_pending_choice_request_ids(local_human_player_id)
	state_changed.emit(local_snapshot)
	# 本地选将类私有快照；初次选将与房主调整 AI 共用同一选将面板协议。
	var local_selection_snapshot: Dictionary = _get_character_selection_snapshot(local_human_player_id)
	if not local_selection_snapshot.is_empty():
		character_selection_changed.emit(local_selection_snapshot)
	if network_gateway != null and network_gateway.is_lan_host() and network_gateway.is_lan_match_active():
		for peer_id_variant: Variant in network_gateway.get_remote_player_assignments().keys():
			# 当前远端 peer 与其稳定玩家 ID；每人单独生成私有快照，禁止广播同一观察者数据。
			var peer_id: int = int(peer_id_variant)
			# 当前远端观察者稳定玩家 ID；无效映射不生成快照，避免错误公开私有数据。
			var viewer_id: int = int(network_gateway.get_remote_player_assignments().get(peer_id, -1))
			if viewer_id < 0:
				continue
			# 观察者裁剪快照；随机种子属于权威端私有信息，联网下不发送给任何客户端。
			var remote_snapshot: Dictionary = state.to_dict(viewer_id, false)
			_append_limited_skill_usage_to_snapshot(remote_snapshot)
			remote_snapshot.erase("random_seed")
			# 本地合法动作；只发送给实际行动玩家，用于客户端无状态预览，最终提交仍由房主重新校验。
			remote_snapshot["local_legal_actions"] = get_legal_actions(viewer_id) if state.current_phase == "play" and state.current_player_id == viewer_id else []
			# 选将私有快照；候选仅进入对应观察者的定向状态包，其他玩家只能看到公开确认状态。
			remote_snapshot["character_selection"] = _get_character_selection_snapshot(viewer_id)
			# 手气卡私有快照；每名远端玩家只接收自己的剩余张数和确认状态。
			remote_snapshot["starting_hand_mulligan"] = starting_hand_mulligan.to_dict(viewer_id) if state.current_phase == "starting_hand_mulligan" and starting_hand_mulligan != null else {}
			# 观察者本人的待办请求清单；并行无懈的多条私有请求无法由单槽位 current_choice_request 表达，
			# 缺少本字段时客户端会在随后的任一快照把仍在等待的无懈窗口误清并永久停在询问阶段。
			remote_snapshot["local_pending_choice_request_ids"] = _get_pending_choice_request_ids(viewer_id)
			network_gateway.send_snapshot_to_peer(remote_snapshot, peer_id)


## 在离线“控制所有角色”模式中选择当前需要操作的角色，并把唯一第一视角切换到该稳定玩家ID。
## 选将、车轮战抓将与手气卡属于开局配置阶段，始终保持原真人与内置AI控制，不参与动态接管。
func _prepare_offline_controlled_view(explicit_player_id: int = -1) -> bool:
	if not _control_all_characters_enabled or state == null or network_gateway == null or network_gateway.mode != NetworkGateway.Mode.OFFLINE:
		return false
	if state.current_phase in ["character_selection", "wheel_duel_selection", "starting_hand_mulligan", "ai_character_adjustment", "game_start"]:
		return false
	# 目标第一视角玩家ID；显式选择请求优先，避免响应者与当前回合角色不同时界面仍停留在旧角色。
	var target_player_id: int = explicit_player_id
	if target_player_id < 0 and str(state.opportunity_state.get("stage", "")) == "choosing":
		# 当前机缘选择者；并行投票没有单一选择者时回退首名待投玩家，控制全部角色仍可在一个本地界面依次代管所有票。
		target_player_id = int(state.opportunity_state.get("current_chooser_id", -1))
		if target_player_id < 0:
			# 当前并行待投集合；首项由机缘组件按参与顺序维护，选择后会自动切到下一项。
			var pending_opportunity_actor_ids: Array = state.opportunity_state.get("pending_chooser_ids", []) as Array
			if not pending_opportunity_actor_ids.is_empty():
				target_player_id = int(pending_opportunity_actor_ids[0])
	if target_player_id < 0 and not _pending_card_choice.is_empty():
		target_player_id = int(_pending_card_choice.get("chooser_id", -1))
	if target_player_id < 0 and not _pending_negation_choices.is_empty():
		for request_variant: Variant in _pending_negation_choices.values():
			var request_data: Dictionary = request_variant as Dictionary
			target_player_id = int(request_data.get("chooser_id", -1))
			if target_player_id >= 0:
				break
	if target_player_id < 0:
		target_player_id = state.current_player_id
	var target_player: PlayerState = state.get_player(target_player_id)
	if target_player == null or not target_player.alive or target_player.out_of_game:
		return false
	return _set_offline_manual_control_player(target_player_id)


## 切换全角色控制当前接管者；上一名非主角色恢复基础AI，新目标停止AI并成为本地第一视角。
func _set_offline_manual_control_player(target_player_id: int) -> bool:
	if state == null or target_player_id < 0:
		return false
	# 切换前第一视角；返回值只表达界面是否需要立即重发快照。
	var previous_viewer_id: int = local_human_player_id
	if _offline_manually_controlled_player_id >= 0 and _offline_manually_controlled_player_id != _primary_offline_human_player_id and _offline_manually_controlled_player_id != target_player_id:
		ai_coordinator.register_basic_ai(_offline_manually_controlled_player_id)
	_offline_manually_controlled_player_id = -1
	if target_player_id != _primary_offline_human_player_id:
		ai_coordinator.unregister_ai(target_player_id)
		_offline_manually_controlled_player_id = target_player_id
	local_human_player_id = target_player_id
	return previous_viewer_id != local_human_player_id


## 响应设置中的实时全角色控制开关；关闭后立即恢复原真人视角，开启后接管当前规则操作者。
func _on_control_all_characters_changed(enabled: bool) -> void:
	if network_gateway == null or network_gateway.mode != NetworkGateway.Mode.OFFLINE or _primary_offline_human_player_id < 0:
		_control_all_characters_enabled = false
		return
	_control_all_characters_enabled = enabled
	if state == null:
		return
	state.match_options["control_all_characters_enabled"] = _control_all_characters_enabled
	if not enabled:
		if _offline_manually_controlled_player_id >= 0 and _offline_manually_controlled_player_id != _primary_offline_human_player_id:
			ai_coordinator.register_basic_ai(_offline_manually_controlled_player_id)
		_offline_manually_controlled_player_id = -1
		local_human_player_id = _primary_offline_human_player_id
		# 废弃接管期间创建的旧AI等待任务；关闭后必须使用新令牌重新安排当前选择或出牌动作。
		_ai_drive_token += 1
		_scheduled_ai_drive_token = -1
		_scheduled_ai_choice_request_id = -1
		# 同时无懈窗口的AI计时器不经过统一AI进度入口（该入口对无懈非空直接返回）；关闭接管时必须逐请求重启，
		# 并把属于恢复后主真人的窗口重新发给界面，否则整轮无懈询问会永久悬停。
		_redrive_pending_negation_ai_tasks()
		_republish_manual_player_choice(local_human_player_id)
		_emit_state()
		_ensure_ai_progress_after_resolution()
		return
	# 开启方向必须无条件刷新快照：视角切换与开关标志写入两种变化各自都需要广播，旧的反向条件恰好漏掉视角已切换的一侧。
	_emit_state()
	# 切换后的第一视角可能正有待办选择；立即重发窗口，避免玩家接管后面对空白操作区。
	_republish_manual_player_choice(local_human_player_id)


## 返回面向指定观察者的选将类私有快照；普通选将与房主 AI 调整阶段互斥。
func _get_character_selection_snapshot(viewer_id: int) -> Dictionary:
	if state == null:
		return {}
	if state.current_phase == "wheel_duel_selection" and wheel_duel_selection != null:
		return wheel_duel_selection.to_dict(viewer_id)
	if state.current_phase == "character_selection" and character_selection != null:
		# 基础选将私有快照；候选、首次身份和最终名额全部仍由服务独立裁剪。
		var selection_snapshot: Dictionary = character_selection.to_dict(viewer_id)
		# 是否存在任意真人已提交的座次身份预览；没有预览时必须继续显示首任领袖公开武将。
		var has_active_custom_assignment_preview: bool = false
		if character_selection.custom_assignment_enabled and (character_selection.phase == CharacterSelectionService.PHASE_LEADER or character_selection.phase == CharacterSelectionService.PHASE_CUSTOM):
			for player: PlayerState in state.players:
				if character_selection.has_custom_assignment_preview(player.player_id):
					has_active_custom_assignment_preview = true
					break
		# 当前预览领袖；预览应用后 state.players 的一号位就是当前领袖，空武将表示真人尚未最终选将。
		var preview_leader: PlayerState = state.players[0] if not state.players.is_empty() else null
		# 当前领袖是否已经确认最终武将；确认后立即公开其当前牌面，即使本轮没有额外座次身份预览也不回退到首任领袖旧武将。
		var preview_leader_has_confirmed_character: bool = preview_leader != null and not character_selection.get_selection(preview_leader.player_id).is_empty()
		# 是否已经进入自选投射状态；首任领袖提交后即使没有保留中的预览字典，也必须以当前一号位覆盖旧领袖快照。
		var uses_projected_custom_leader: bool = character_selection.phase == CharacterSelectionService.PHASE_CUSTOM or has_active_custom_assignment_preview or preview_leader_has_confirmed_character
		if uses_projected_custom_leader and preview_leader != null and preview_leader.identity == character_selection.get_first_seat_identity():
			selection_snapshot["leader_player_id"] = preview_leader.player_id
			selection_snapshot["leader_character_id"] = preview_leader.character_id
		return selection_snapshot
	if state.current_phase == "ai_character_adjustment" and ai_character_adjustment != null:
		# AI 调整选将快照；补充当前目标显示名只用于标题，不扩大服务对玩家状态的依赖。
		var adjustment_snapshot: Dictionary = ai_character_adjustment.to_selection_dict(viewer_id)
		if not adjustment_snapshot.is_empty():
			var target_player: PlayerState = state.get_player(int(adjustment_snapshot.get("target_player_id", -1)))
			adjustment_snapshot["target_display_name"] = target_player.display_name if target_player != null else "AI角色"
		return adjustment_snapshot
	return {}


## 拒绝动作并返回 false，统一错误信号与调用结果。
func _reject(message: String) -> bool:
	_last_action_rejection_message = message
	action_rejected.emit(message)
	return false


## 查找指定身份玩家；标准身份局中领袖查询只会返回一人。
## 返回当前角色在摸牌阶段的基础摸牌数；2v2与车轮战保留首回合惩罚，过关斩将敌方在此基础上叠加关卡摸牌增强。
func _get_phase_draw_base_count(player_id: int) -> int:
	if state == null:
		return 2
	var match_mode: String = identity_rules.normalize_mode(str(state.match_mode))
	var result: int = 2
	if (match_mode == IdentityRules.MODE_TEAM2V2 or match_mode == IdentityRules.MODE_WHEEL_DUEL) and state.turn_number == 1 and not state.players.is_empty() and state.players[0].player_id == player_id:
		# 仅2v2与车轮战的一号位全场首个回合生效；过关斩将玩家首回合保持常规摸2张。
		result = 1
	# 摸牌阶段加成机缘统一从角色历史汇总；过关斩将敌方与普通机缘角色不再维护两套数值来源。
	result += get_acquired_opportunity_effect_total(player_id, "draw_phase_bonus")
	return result


func _find_player_by_identity(identity: String) -> PlayerState:
	for player: PlayerState in state.players:
		if player.identity == identity:
			return player
	return null


## 判断玩家当前牌源或装备是否能提供指定响应模式；不依赖任何具体卡牌定义 ID。
func _player_has_response_pattern(player: PlayerState, response_pattern: String) -> bool:
	if player == null or response_pattern.is_empty():
		return false
	for card: CardInstance in player.get_playable_cards():
		if _get_provided_response_pattern(GameDatabase.get_card(card.definition_id)) == response_pattern:
			return true
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备定义；装备响应入口自行判断是否支持指定模式。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null and equipment_definition.can_offer_equipment_response(self, player.player_id, [response_pattern]):
			return true
	return false


## 通知当前玩家全部装备：持有者刚刚使用或打出了一张实体牌。
func _notify_equipment_card_consumed(owner_id: int, used_card: CardInstance, was_hand_card: bool) -> void:
	if used_card == null:
		return
	# 装备持有者；不存在或死亡角色不触发装备效果。
	var owner: PlayerState = state.get_player(owner_id)
	if owner == null or not owner.alive:
		return
	# 当前装备快照；装备源码可依据牌色、来源区域和回合归属决定是否排队。
	var equipment_cards: Array = owner.equipment.values().duplicate()
	for equipment_variant: Variant in equipment_cards:
		# 当前装备实体；定义缺失时安全跳过。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null:
			equipment_definition.on_owner_card_consumed(self, owner_id, used_card, was_hand_card)


## 通知全部自动发现的卡牌定义：指定玩家开始新回合；卡牌文件自行重置专属状态。
func _notify_card_definitions_turn_started(player_id: int) -> void:
	for definition_variant: Variant in GameDatabase.card_definitions.values():
		# 当前静态卡牌定义；回合钩子不得在对象中保存对局状态。
		var definition: CardDefinition = definition_variant as CardDefinition
		if definition != null:
			definition.on_turn_started(self, player_id)


## 通知全部自动发现的卡牌定义：指定玩家回合结束或中断；卡牌文件自行清理持续状态。
func _notify_card_definitions_turn_ended(player_id: int, interrupted: bool) -> void:
	for definition_variant: Variant in GameDatabase.card_definitions.values():
		# 当前静态卡牌定义；interrupted 只描述回合终止方式，不改变调用顺序。
		var definition: CardDefinition = definition_variant as CardDefinition
		if definition != null:
			definition.on_turn_ended(self, player_id, interrupted)


## 将一条装备延后触发加入先进先出队列；上下文必须只包含可序列化字段。
func queue_equipment_trigger(owner_id: int, equipment_uid: int, equipment_definition_id: String, context: Dictionary) -> void:
	if equipment_uid < 0 or equipment_definition_id.is_empty():
		return
	# 队列条目；装备 UID 防止等待期间换装后误发动同名新装备。
	var trigger_data: Dictionary = context.duplicate(true)
	trigger_data["owner_id"] = owner_id
	trigger_data["equipment_uid"] = equipment_uid
	trigger_data["equipment_definition_id"] = equipment_definition_id
	_queued_equipment_triggers.append(trigger_data)


## 在没有其他活动选择时依次启动装备延后触发；具体条件、询问和效果全部由装备文件实现。
func process_next_equipment_trigger() -> void:
	while state != null and not state.game_over and not has_pending_card_choice() and not _queued_equipment_triggers.is_empty():
		# 当前待处理触发；按实体牌实际使用或打出的顺序先进先出。
		var trigger_data: Dictionary = _queued_equipment_triggers.pop_front() as Dictionary
		# 装备持有者；等待期间死亡时本条触发失效。
		var owner_id: int = int(trigger_data.get("owner_id", -1))
		var owner: PlayerState = state.get_player(owner_id)
		if owner == null or not owner.alive:
			continue
		# 创建触发的装备实体；必须仍位于持有者任意装备槽且 UID 完全一致。
		var equipment_card: CardInstance
		for equipment_variant: Variant in owner.equipment.values():
			var candidate: CardInstance = equipment_variant as CardInstance
			if candidate.uid == int(trigger_data.get("equipment_uid", -1)):
				equipment_card = candidate
				break
		if equipment_card == null or equipment_card.definition_id != str(trigger_data.get("equipment_definition_id", "")):
			continue
		# 装备源码定义；返回后若创建了选择，请求会阻止 while 继续取下一条。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null:
			equipment_definition.begin_queued_equipment_trigger(self, owner_id, trigger_data)

## 基础无懈可击策略；根据身份关系和锦囊收益方向决定是否自动响应。
func _should_auto_negate(responder: PlayerState, source_id: int, target_id: int, trick_id: String, currently_negated: bool) -> bool:
	if ai_coordinator != null and ai_coordinator.is_ai_controlled(responder.player_id):
		# 无名杀式无懈评估上下文；奇偶状态、来源、目标与锦囊 ID 均由权威规则层提供。
		var negation_context: Dictionary = {"source_id":source_id, "target_id":target_id, "trick_id":trick_id, "negated":currently_negated}
		return ai_coordinator.should_negate(responder.player_id, state.to_dict(responder.player_id, true), negation_context)
	# 响应者对目标的阵营态度；正值为友方，负值为敌方。
	var target_attitude: int = _identity_attitude(responder.identity, state.get_player(target_id).identity if state.get_player(target_id) != null else "")
	# 该锦囊对目标是否通常有利；收益方向由对应卡牌文件声明，新增锦囊无需修改白名单。
	var beneficial: bool = bool(GameDatabase.get_card(trick_id).get("ai_beneficial", false))
	if not currently_negated:
		return (beneficial and target_attitude < 0) or (not beneficial and target_attitude > 0)
	# 反无懈旨在恢复对友方的有利效果或恢复对敌方的有害效果。
	return (beneficial and target_attitude > 0) or (not beneficial and target_attitude < 0)


## 返回两个身份的简化阵营关系，供基础自动响应使用。
func _identity_attitude(from_identity: String, to_identity: String) -> int:
	# 本局模式；斗地主与 2v2 按同身份为友、异身份为敌的简化态度。
	var match_mode: String = identity_rules.normalize_mode(str(state.match_mode) if state != null else IdentityRules.MODE_IDENTITY)
	if match_mode == IdentityRules.MODE_DOUDIZHU or match_mode == IdentityRules.MODE_TEAM2V2 or match_mode == IdentityRules.MODE_WHEEL_DUEL:
		if from_identity == to_identity and not from_identity.is_empty():
			return 1
		if match_mode == IdentityRules.MODE_DOUDIZHU:
			if from_identity == "landlord" and to_identity == "landlord":
				return 1
			if from_identity == "peasant" and to_identity == "peasant":
				return 1
		if match_mode == IdentityRules.MODE_TEAM2V2:
			if from_identity == "blue" and to_identity == "blue":
				return 1
			if from_identity == "red" and to_identity == "red":
				return 1
		return -1
	if from_identity == "renegade":
		return -1
	if from_identity == to_identity:
		return 1
	if from_identity in ["leader", "loyalist"] and to_identity in ["leader", "loyalist"]:
		return 1
	return -1


## 返回卡牌规则提示使用的武将名；武将尚未公开或配置缺失时才回退玩家显示名。
func _player_character_name(player: PlayerState) -> String:
	if player == null:
		return "未知武将"
	# 当前稳定武将 ID；空值表示尚未完成选将，不能显示“未知武将”覆盖仍有意义的玩家名。
	var character_id: String = player.character_id
	if character_id.is_empty():
		return player.display_name
	# 当前配置武将名；数据仓库统一保证中文显示名，异常配置仍使用玩家名保持提示可定位。
	var character_name: String = GameDatabase.resolve_character_name(character_id)
	return character_name if not character_name.is_empty() else player.display_name


## 将伤害属性 ID 转换为日志文本。
func _nature_text(nature: String) -> String:
	return {"normal":"普通", "fire":"火焰", "thunder":"雷电"}.get(nature, nature)


## 将身份 ID 转换为界面与日志文本。
func _identity_text(identity: String) -> String:
	return {
		"leader":"领袖",
		"loyalist":"忠臣",
		"rebel":"反贼",
		"renegade":"内奸",
		"landlord":"地主",
		"peasant":"农民",
		"blue":"蓝方",
		"red":"红方",
	}.get(identity, identity)


## 将获胜方 ID 转换为界面与日志文本。
func _winner_text(winner: String) -> String:
	return {
		"leader_and_loyalists":"领袖与忠臣",
		"rebels":"反贼",
		"renegade":"内奸",
		"landlords":"地主",
		"peasants":"农民",
		"blue_team":"蓝方",
		"red_team":"红方",
	}.get(winner, winner)


## 阶段切换通知完成后才修改公开阶段；选择期间发生跳过、死亡或换回合时旧切换不再生效。
func _change_phase_then(timing_name: String, player_id: int, source_id: int, target_id: int, event_data: Dictionary, parent_event_id: int, on_completed: Callable) -> void:
	# 切换起点身份；只允许原对局、原回合、原公开阶段继续，避免异步技能已经推进后重复推进。
	var transition_context: Dictionary = {"match_id":state.match_id, "turn_number":state.turn_number, "phase":state.current_phase, "player_id":state.current_player_id}
	# 显式两步；phaseChange是状态改变前的通知，实际入口在全部子内容结束后重新校验。
	var steps: Array[Callable] = [
		func(sequence: RuleStepSequence) -> void: emit_sequence_timing(sequence, timing_name, player_id, source_id, target_id, event_data, parent_event_id),
		func(sequence: RuleStepSequence) -> void:
			if state != null and not state.game_over and state.match_id == str(sequence.context.match_id) and state.turn_number == int(sequence.context.turn_number) and state.current_player_id == int(sequence.context.player_id) and state.current_phase == str(sequence.context.phase) and on_completed.is_valid():
				on_completed.call(),
	]
	run_rule_sequence(steps, transition_context)


## 子阶段按创建身份归属，不以当前公开phase或是否存在选牌猜测完成状态。
func _sequence_waits_for_child_phase(sequence: RuleStepSequence) -> bool:
	return (not _active_independent_play_phase.is_empty() and int(_active_independent_play_phase.get("phase_id", -1)) != sequence.enclosing_play_phase_id) or (not _active_extra_discard_phase.is_empty() and int(_active_extra_discard_phase.get("phase_id", -1)) != sequence.enclosing_discard_phase_id)


## 只检查最内层父内容；子阶段中新建的规则序列已记录外层阶段身份，仍能正常推进。
func _top_sequence_waits_for_child_phase() -> bool:
	# 栈顶记录；旧类型续接继续由自己的正式完成入口处理。
	var continuation: Dictionary = _rule_continuations.peek()
	if str(continuation.get("continuation_type", "")) != "rule_sequence":
		return false
	# 当前步骤内容；失效序列由普通出栈路径回收，不形成永久屏障。
	var sequence: RuleStepSequence = _rule_sequences.get(int((continuation.get("context", {}) as Dictionary).get("sequence_id", -1))) as RuleStepSequence
	return sequence != null and _sequence_waits_for_child_phase(sequence)
