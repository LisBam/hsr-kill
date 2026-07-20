class_name MatchController
extends Node

## 标准身份局权威控制器。它编排阶段与动作，并把具体合法性、卡牌效果、AI 和网络交给独立组件。

signal state_changed(snapshot: Dictionary)
signal log_added(message: String)
signal action_rejected(message: String)
signal match_finished(winner: String)

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

## 牌区转移数据中标识摸牌表现批次的私有键；只存在于瞬时信号副本，绝不写入 CardInstance、存档或回放状态。
const DRAW_PRESENTATION_BATCH_ID_KEY: String = "_draw_presentation_batch_id"

## 统一选择请求信号；选牌、选目标与组合选择都先发送可序列化询问，再提交兼容 choose_cards 动作。
signal card_choice_requested(choice_data: Dictionary)

## 公共选牌展示变化信号；五谷丰登等公开流程通过该信号让所有观察者持续看到固定牌位与领取归属。
signal public_card_choice_display_changed(display_data: Dictionary)

## 选将快照变化信号；只包含观察者可见候选、公开领袖武将和全员确认状态。
signal character_selection_changed(snapshot: Dictionary)

## 默认牌堆 ID；可在检查器中替换为后续扩展牌堆，运行时通常无需动态修改。
@export var default_deck_id: String = "standard_162"

## 默认玩家人数；支持2至10，直接运行演示场景时创建8人局，运行时可在新开局前修改。
## 当前正式主场景会先显示主菜单，默认8人只在玩家确认开始或局内重新开局时用于创建身份局。
@export_range(2, 10, 1) var default_player_count: int = 8

## 人类本地玩家当前座次；默认0作为随机分配前的有效占位值，设为 -1 可运行纯 AI 自动对局。
@export_range(-1, 9, 1) var local_human_player_id: int = 0

## 是否在每局创建时为本地人类玩家重新随机分配座次；默认开启以保证本地玩家不固定在一号位，纯 AI 模式不受影响。
@export var randomize_local_human_seat: bool = true

## AI 每次行动或选择响应前的等待秒数；默认0.30秒，局内菜单可在0.05至1.00秒范围内动态同步，测试可直接覆盖。
@export_range(0.05, 1.0, 0.05) var ai_action_delay_seconds: float = 0.30

## 相邻阶段与自动响应之间的最小等待秒数；正式菜单限制为0.1至1.0秒，规则测试可设为0关闭表现节奏。
@export_range(0.0, 1.0, 0.1) var game_flow_interval_seconds: float = 0.30

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

## 每名玩家随机展示的可选武将数量；默认5，运行时无需动态修改，后续扩展武将库后可在检查器调整。
@export_range(1, 20, 1) var character_candidate_count: int = 5

## 特殊模式预留的首回合座次号；标准身份局不读取该值而始终由随机座次的领袖开始，运行时无需修改。
@export_range(1, 10, 1) var first_turn_seat_number: int = 1

## 当前权威对局状态；开局前为 null，外部模块应优先读取快照。
var state: GameState

## 身份规则服务；负责分配表、胜负与死亡奖惩类型。
var identity_rules: IdentityRules

## 卡牌合法性服务；每次开局绑定新状态实例。
var card_rules: CardRuleService

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

## 本局是否启用房主调整全部 AI 武将；开局时锁定。
var _customize_ai_characters_enabled: bool = false

## 本局每名玩家的手气卡张数；0关闭、1至5与10有限张数、-1无限张。
var _mulligan_limit: int = 0

## 本局 AI 是否自动评估并使用手气卡；手气卡数量为0时该值不会产生流程。
var _ai_uses_mulligan_enabled: bool = false

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

## 触发器排序组件；保留与同步 RuleEventBus 的兼容边界，逐步承载技能时机排序。
var trigger_manager: TriggerManager

## 统一规则时机派发服务；负责普通订阅、四角色过滤、优先级与座次排序，不执行具体玩法效果。
var timing_service: RuleTimingService

## 纯查询修正管线；技能与装备只通过该管线修改合法性查询，不直接改写控制器状态。
var modifier_pipeline: RuleModifierPipeline

## 当前对局纯查询门面；UI、AI 和规则组件共享同一合法性查询入口。
var rule_query: RuleQuery

## 实体牌唯一移动服务；新移牌记录写入 GameState.card_move_history。
var card_movement: CardMovementService

## 使用牌事件树构建组件；只声明 useCard 子事件拓扑，不读取状态或执行具体卡牌效果。
var card_use_event_service: CardUseEventService

## 对局随机数生成器；牌堆、身份与武将选择统一使用，便于未来记录种子回放。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

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

## 等待濒死流程完成后收尾的伤害上下文；键为受伤玩家 ID，值只保存伤害来源、数值、连环目标和事件 ID。
var _pending_damage_finalizations: Dictionary = {}

## 已成功进入 Begin 的阶段生命周期集合；键为“玩家ID:阶段名”，防止跳过或取消阶段伪造 End 与 After。
var _started_phase_lifecycles: Dictionary = {}

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

## 当前判定区顺序流程代次；重新开局、换回合或重新启动判定链时递增，使旧计时器无法继续修改新状态。
var _judgment_flow_token: int = 0

## 当前是否已有一条判定区顺序流程正在等待或结算；默认false，防止选择恢复重复创建并行计时器。
var _judgment_flow_in_progress: bool = false

## 判定流程从异步无懈或濒死选择恢复时是否需要先保留上一张判定结果；默认false，新回合从延时锦囊展示开始。
var _judgment_resume_needs_result_pause: bool = false

## 对局级暂停在事件运行时持有的全局 token；-1表示当前没有同步阻塞事件栈。
var _gameplay_event_pause_token: int = -1

## 等待执行的额外完整回合角色队列；角色 ID 按技能结算顺序追加，死亡角色在执行前安全跳过。
var _extra_turn_queue: Array[int] = []

## 额外回合结束后需要恢复的原行动角色栈；最外层记录原当前角色的正常下家。
var _extra_turn_resume_player_ids: Array[int] = []

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

## 当前由技能插入的独立额外弃牌阶段上下文；空字典表示没有等待阶段触发、弃牌选择或完成回调。
var _active_extra_discard_phase: Dictionary = {}

## 因结束阶段技能选择而暂停收尾的当前角色 ID；选择全部完成后从唯一尾部入口继续正常或额外回合轮转。
var _pending_finish_turn_player_id: int = -1

## 等待嵌套规则选择结束后继续的技能结算队列；仅保存技能 ID、持有者 ID 与可序列化上下文，不持有 Callable 或技能对象。
var _deferred_skill_settlements: Array[Dictionary] = []

## 被嵌套选择中断的通用规则续接栈；响应、救援、重铸和父牌收尾只保存稳定类型与可序列化上下文。
var _rule_continuations: RuleContinuationQueue = RuleContinuationQueue.new()

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
	ai_coordinator = get_node("AICoordinator") as AICoordinator
	network_gateway = get_node("NetworkGateway") as NetworkGateway
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
	event_scheduler = get_node_or_null("EventScheduler") as EventScheduler
	if event_scheduler == null:
		event_scheduler = EventScheduler.new()
		event_scheduler.name = "EventScheduler"
		add_child(event_scheduler)
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
	if not public_card_choice_display_changed.is_connected(_replicate_public_card_choice_display_event):
		public_card_choice_display_changed.connect(_replicate_public_card_choice_display_event)
	if not match_finished.is_connected(_replicate_match_finished_event):
		match_finished.connect(_replicate_match_finished_event)
	if not GameSettings.ai_response_delay_changed.is_connected(_on_ai_response_delay_changed):
		GameSettings.ai_response_delay_changed.connect(_on_ai_response_delay_changed)
	if not GameSettings.game_speed_changed.is_connected(_on_game_speed_changed):
		GameSettings.game_speed_changed.connect(_on_game_speed_changed)
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
	if state.current_phase == "character_selection":
		_drive_ai_character_selection()
		return
	_ensure_ai_progress_after_resolution()


## 返回开局请求的前置校验错误；空字符串表示可以安全进入会替换旧局的初始化阶段。
## mode_id 空时读取 GameSettings.next_match_mode；人数与模式组合不支持时返回明确中文原因。
func get_match_start_validation_error(player_count: int = -1, mode_id: String = "") -> String:
	# 实际玩家人数；未指定时使用检查器默认值。
	var actual_player_count: int = default_player_count if player_count < 0 else player_count
	# 规范化模式；空字符串回退全局下一局设置，再由身份规则兜底为 identity。
	var actual_mode: String = _resolve_match_mode(mode_id)
	if not identity_rules.supports_player_count(actual_mode, actual_player_count):
		if actual_mode == IdentityRules.MODE_DOUDIZHU:
			return "斗地主仅支持3人或6人。"
		return "标准身份局仅支持2至10名玩家。"
	if not GameDatabase.validation_errors.is_empty():
		return "数据配置校验失败：%s" % "；".join(GameDatabase.validation_errors)
	return ""


## 规范化对局模式；空值优先读取 GameSettings.next_match_mode，再回退到身份局。
func _resolve_match_mode(mode_id: String = "") -> String:
	# 调用方显式模式优先；否则使用全局下一局设置。
	var raw_mode: String = mode_id
	if raw_mode.is_empty() and GameSettings != null:
		raw_mode = str(GameSettings.next_match_mode)
	return identity_rules.normalize_mode(raw_mode)


## 创建并开始一局；seed 为0时使用系统随机种子，mode_id 空时读取 GameSettings.next_match_mode。
func start_match(player_count: int = -1, seed: int = 0, mode_id: String = "") -> bool:
	# 实际玩家人数；未指定时使用检查器默认值。
	var actual_player_count: int = default_player_count if player_count < 0 else player_count
	# 本局模式；在破坏旧状态前完成校验，失败时调用方可保留原局。
	var actual_mode: String = _resolve_match_mode(mode_id)
	# 开局前置校验错误；任何错误都在破坏旧对局状态和表现之前同步拒绝。
	var validation_error: String = get_match_start_validation_error(actual_player_count, actual_mode)
	if not validation_error.is_empty():
		action_rejected.emit(validation_error)
		return false
	if game_flow_pacer != null:
		game_flow_pacer.cancel_all()
	_uninstall_all_character_skills()
	_uninstall_all_card_runtimes()
	_extra_turn_queue.clear()
	_extra_turn_resume_player_ids.clear()
	_current_turn_is_extra = false
	_extra_play_phase_counts.clear()
	_extra_play_phase_returns_to_finish.clear()
	_extra_play_phase_return_points.clear()
	_active_extra_play_phase_context.clear()
	_active_extra_discard_phase.clear()
	_pending_finish_turn_player_id = -1
	_deferred_skill_settlements.clear()
	_rule_continuations.reset()
	_cards_used_this_turn_by_player.clear()

	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	# 局域网房主的本地玩家 ID 已由大厅位置顺序映射确定；离线对局继续使用原有本地座次随机逻辑。
	var lan_local_player_id: int = network_gateway.get_local_lan_player_id() if network_gateway != null and network_gateway.is_lan_host() else -1
	if lan_local_player_id >= 0:
		local_human_player_id = lan_local_player_id
	else:
		_assign_local_human_player_seat(actual_player_count)
	CardInstance._next_uid = 1
	state = GameState.new()
	state.match_id = "%d-%d" % [Time.get_unix_time_from_system(), _rng.randi()]
	# 本局锁定的模式；菜单之后的模式切换只写入 GameSettings，不改进行中的规则。
	state.match_mode = actual_mode
	ai_coordinator.reset_identity_observations()
	state.random_seed = _rng.seed
	state.deck_id = default_deck_id
	# 本局锁定的房主权威开局选项；菜单之后的修改只作用于下一局，不会改变进行中的选将或手气卡阶段。
	_custom_character_assignment_enabled = GameSettings.custom_character_assignment_enabled
	_customize_ai_characters_enabled = GameSettings.customize_ai_characters_enabled
	_mulligan_limit = GameSettings.mulligan_limit
	_ai_uses_mulligan_enabled = GameSettings.ai_uses_mulligan_enabled
	_character_replacement_count = GameSettings.character_replacement_count
	_character_candidate_count = GameSettings.character_candidate_count
	# 检查器兼容字段；运行时同步为房主设置锁定值，旧诊断与外部只读代码仍能看到本局实际候选数量。
	character_candidate_count = _character_candidate_count
	state.match_options = {
		"custom_character_assignment_enabled":_custom_character_assignment_enabled,
		"customize_ai_characters_enabled":_customize_ai_characters_enabled,
		"mulligan_limit":_mulligan_limit,
		"ai_uses_mulligan_enabled":_ai_uses_mulligan_enabled,
		"character_replacement_count":_character_replacement_count,
		"character_candidate_count":_character_candidate_count,
	}
	card_rules = CardRuleService.new(state, self)
	effect_resolver = CardEffectResolver.new(self, state)
	card_movement = CardMovementService.new(state)
	_bind_card_movement_service()
	modifier_pipeline = RuleModifierPipeline.new()
	rule_query = RuleQuery.new(state, card_rules, modifier_pipeline)
	trigger_manager = TriggerManager.new()
	if timing_service == null:
		timing_service = RuleTimingService.new(event_bus, trigger_manager, state)
	else:
		timing_service.configure(event_bus, trigger_manager, state)
	timing_service.set_trigger_pause_condition(Callable(self, "_should_pause_rule_timing_dispatch"))
	skill_instances_by_player.clear()
	card_runtime_instances.clear()
	event_scheduler.reset()
	_gameplay_event_pause_token = -1
	# 根事件只保存规则启动元数据；后续身份、阶段和卡牌事件通过 parent_id 关联到该入口。
	var root_event: GameEvent = event_scheduler.create_event("RootGameEvent", "root", [], {"rules_snapshot":"noname-v1.10.16", "mode":state.match_mode, "match_id":state.match_id, "deck_id":state.deck_id})
	_runtime_root_event_id = root_event.event_id
	event_scheduler.begin_root(_runtime_root_event_id, true)
	if is_gameplay_paused():
		_gameplay_event_pause_token = event_scheduler.pause_registry.acquire("gameplay", -1, "gameplay_pause_interface")
	state.current_event_id = _runtime_root_event_id
	state.event_history = event_scheduler.get_event_history()
	character_selection = CharacterSelectionService.new()
	ai_character_adjustment = AICharacterAdjustmentService.new()
	starting_hand_mulligan = StartingHandMulliganService.new()
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
	_negation_round_sequence = 0
	_resolved_card_choice_uids.clear()
	_resolved_equipment_material_uids.clear()
	_resolved_response_skill_id = ""
	_negation_resume_results.clear()
	_active_card_resolutions.clear()
	_card_use_contexts.clear()
	_pending_damage_finalizations.clear()
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
	ai_coordinator._policies.clear()
	_ai_submission_depth_by_player.clear()

	_create_players(actual_player_count)
	_create_and_shuffle_deck()
	_record_runtime_event("identity.start", "mode", {"player_count":actual_player_count, "seed":seed, "mode":state.match_mode})
	state.current_phase = "character_selection"
	# 可用武将 ID；服务只持有字符串副本，不接触全局配置的可修改引用。
	var available_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		available_character_ids.append(str(character_id_variant))
	# 领袖技武将 ID；依据技能元数据自动识别，选将服务只接收纯字符串数组并保持与数据库解耦。
	var leader_skill_character_ids: Array[String] = _get_leader_skill_character_ids(available_character_ids)
	# 选将初始化错误；空字符串表示领袖候选已生成。
	var selection_error: String = character_selection.begin(state.players, available_character_ids, _character_candidate_count, _rng, _custom_character_assignment_enabled, _character_replacement_count, leader_skill_character_ids)
	if not selection_error.is_empty():
		_discard_failed_match_start()
		action_rejected.emit(selection_error)
		return false
	# 首任公开选将身份文案；身份局为领袖，斗地主为地主。
	var first_player_title: String = _identity_text(identity_rules.get_first_player_identity(state.match_mode))
	add_log("选将开始：%s先从%d张普通随机候选及%d张领袖技固定候选中选择并亮出。" % [first_player_title, mini(_character_candidate_count, maxi(available_character_ids.size() - leader_skill_character_ids.size(), 0)), leader_skill_character_ids.size()])
	_emit_state()
	_drive_ai_character_selection()
	return true


## 丢弃已进入初始化阶段但未能建立选将流程的半成品对局；失败后控制器恢复与首次进入主菜单相同的空状态。
func _discard_failed_match_start() -> void:
	if game_flow_pacer != null:
		game_flow_pacer.cancel_all()
	_uninstall_all_character_skills()
	_uninstall_all_card_runtimes()
	if event_scheduler != null:
		event_scheduler.reset()
	ai_coordinator._policies.clear()
	_ai_submission_depth_by_player.clear()
	skill_instances_by_player.clear()
	card_runtime_instances.clear()
	character_selection = null
	ai_character_adjustment = null
	starting_hand_mulligan = null
	card_rules = null
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
	if action.action_type == "set_auto_managed":
		return _submit_auto_management_change(action)
	# 托管玩家仍由 AI 通过同一动作入口执行；真人、本地脚本或远端封包不能在托管期间抢占操作。
	if _is_player_auto_managed(action.actor_id) and not _is_internal_ai_submission(action.actor_id):
		return _reject("当前玩家正在托管中，暂时不能进行操作。")
	if is_gameplay_paused() and ai_coordinator != null and ai_coordinator.is_ai_controlled(action.actor_id):
		return false
	if action.action_type == "select_character":
		return select_character(action.actor_id, str(action.payload.get("character_id", "")), int(action.payload.get("seat_number", -1)), str(action.payload.get("identity", "")))
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
			if not state.game_over and state.current_phase == "play" and not has_pending_card_choice():
				_begin_play_choice(state.current_player_id)
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
		# 手牌视为牌通过统一虚拟牌协议结算：实体离开手牌后恢复原名，已经声明的逻辑牌继续完成完整牌效与次数统计。
		if card.has_hand_view_as() and card.zone == "hand":
			# 单材料数组；稳定UID同时用于失去牌、回放和最终弃牌区恢复原始实体。
			var view_as_material_uids: Array[int] = [card.uid]
			if not execute_virtual_card_use(action.actor_id, card.definition_id, view_as_material_uids, resolution_target_ids, ""):
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
		if current_turn_player != null and not current_turn_player.alive:
			_advance_after_current_player_death(current_turn_player.player_id)
			return true
	if not state.game_over and state.current_phase == "play" and not has_pending_card_choice():
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
	if state.current_phase == "character_selection":
		_drive_ai_character_selection()
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
	if not _pending_card_choice.is_empty() and int(_pending_card_choice.get("chooser_id", -1)) == player_id:
		# 当前兼容选择副本；本地 UI 与远端私有请求都只接收可序列化数据。
		var choice_data: Dictionary = _pending_card_choice.duplicate(true)
		card_choice_requested.emit(choice_data)
		_replicate_choice_request_to_remote_player(choice_data)


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
		if skill != null:
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


## 返回当前是否存在等待玩家或 AI 提交的选择窗口；牌、目标和组合请求都会暂停后续结算。
func has_pending_card_choice() -> bool:
	if network_gateway != null and network_gateway.is_lan_client():
		# 远端当前选择请求；出牌阶段 use 请求属于常驻动作入口，不视为效果结算中的临时选择窗口。
		var remote_choice: Dictionary = _remote_snapshot.get("current_choice_request", {}) as Dictionary
		return not remote_choice.is_empty() and int(remote_choice.get("actor_id", -1)) == local_human_player_id and str(remote_choice.get("choice_type", "")) != "use"
	return not _pending_card_choice.is_empty() or not _pending_negation_choices.is_empty()


## 为当前角色创建可持续的 chooseToUse 请求；候选只包含当前仍可使用或重铸的实体牌 UID。
func _begin_play_choice(player_id: int) -> void:
	if state == null or state.game_over or state.current_phase != "play" or state.current_player_id != player_id:
		return
	if _has_active_play_choice():
		return
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	# 出牌选择时机数据；主动入口同时包含阶段主动和用牌询问，技能命中任意一个即可加入候选。
	var timing_data: Dictionary = {"phase":"play", "active_entries":["phaseUse", "chooseToUse"]}
	# 使用牌选择前事件；取消表示本次不再建立选择窗口并直接结束当前出牌阶段。
	var before_event: RuleEvent = _emit_rule_timing("chooseToUseBefore", player_id, player_id, -1, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		_end_play_phase(player_id)
		return
	var event: GameEvent = event_scheduler.create_event("chooseToUse", "choice", [], {"player_id":player_id, "phase":"play"}, _runtime_root_event_id)
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
		var candidate_uid: int = int(legal_action.get("card_uid", -1))
		if candidate_uid >= 0 and not request.card_ids.has(candidate_uid):
			request.card_ids.append(candidate_uid)
	# 出牌请求允许提交的目标玩家；具体牌的数量、距离与组合语义仍由动作预校验和 CardRuleService 权威复核。
	for target_player: PlayerState in state.players:
		if target_player.alive:
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


## 把现有 UI/AI 高层动作转换为当前 chooseToUse 的标准 ChoiceResponse，并交给事件运行时校验。
func _submit_play_choice_response(action: PlayerAction) -> bool:
	if not _has_active_play_choice():
		# 无 match_id 的纯规则测试直接调用控制器公开接口时，不强制依赖场景级出牌请求。
		return state.match_id.is_empty()
	var response: ChoiceResponse = ChoiceResponse.new(_play_choice_request_id, _play_choice_event_id, action.actor_id, action.action_type != "end_play")
	if action.action_type == "use_skill":
		response.button_ids = [str(action.payload.get("skill_id", ""))]
	elif action.action_type != "end_play":
		response.card_ids = [action.card_uid]
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
	_resolved_card_choice_uids.clear()
	_resolved_target_choice_ids.clear()
	_resolved_equipment_material_uids.clear()
	_resolved_control_choice_id = ""
	_resolved_response_skill_id = ""
	# 选择事件名称；响应、弃牌和普通选牌使用稳定名称，调用方可通过 choice_event_name 指定其他已实现选择类型。
	var choice_type: String = str(context.get("choice_type_override", "card"))
	# 默认选择事件名称；目标与组合选择使用各自标准名称，普通请求使用 chooseCard。
	var default_choice_event_name: String = "chooseTarget" if choice_type == "target" else ("chooseCardTarget" if choice_type == "card_target" else "chooseCard")
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
	var choice_target_ids: Array[int] = _int_array(context.get("choice_target_ids", []) as Array)
	# 卡牌维度范围；普通选牌沿用函数参数，组合选择可通过上下文独立配置。
	var minimum_card_count: int = int(context.get("min_card_select", 0 if choice_type in ["target", "control", "bool"] else min_select))
	# 卡牌维度上限；始终不小于下限，避免异常技能参数创建无法完成的请求。
	var maximum_card_count: int = maxi(int(context.get("max_card_select", 0 if choice_type in ["target", "control", "bool"] else max_select)), minimum_card_count)
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
	if _build_card_choice_actions(_pending_card_choice).is_empty():
		var invalid_choice_kind: String = str((_pending_card_choice.get("context", {}) as Dictionary).get("kind", "unknown"))
		_pending_card_choice.clear()
		_reject("选择请求没有合法结果，已跳过以避免流程停滞：%s。" % invalid_choice_kind)
		return []
	# 独立选择事件；控制器的兼容恢复分支继续执行具体效果，EventScheduler 负责请求身份和旧响应失效。
	# 选择父事件；规则效果内创建的响应必须挂到当前 content 子事件，阶段级选择则回退到长期根事件。
	var choice_parent_event_id: int = event_scheduler.get_current_event_id()
	if choice_parent_event_id < 0:
		choice_parent_event_id = _runtime_root_event_id
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


## 发布一条兼容选择请求；响应牌窗口按游戏速度延时显示，其他选牌与目标请求保持立即可操作。
func _publish_card_choice_request(choice_data: Dictionary, paced_response: bool) -> void:
	# 当前请求 ID；独立业务键允许同时无懈的多个请求并行等待且互不取消。
	var request_id: int = int(choice_data.get("request_id", -1))
	if not paced_response or game_flow_pacer == null or game_flow_interval_seconds <= 0.0 or request_id < 0:
		card_choice_requested.emit(choice_data.duplicate(true))
		_replicate_choice_request_to_remote_player(choice_data)
		return
	# 延时提示回调；到期后会重新读取权威待处理请求，不长期持有候选牌副本。
	var publish_callback: Callable = Callable(self, "_emit_paced_card_choice_request").bind(request_id)
	game_flow_pacer.schedule("response_prompt:%d" % request_id, game_flow_interval_seconds, publish_callback)


## 发出仍然有效的延时响应提示；请求已提交、取消或重开时不显示过期窗口。
func _emit_paced_card_choice_request(request_id: int) -> void:
	if not _pending_card_choice.is_empty() and int(_pending_card_choice.get("request_id", -1)) == request_id:
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
	if is_gameplay_paused() or token != _ai_drive_token or state == null or state.game_over or _pending_card_choice.is_empty():
		return
	if int(_pending_card_choice.get("request_id", -1)) != request_id or int(_pending_card_choice.get("chooser_id", -1)) != chooser_id or not ai_coordinator.is_ai_controlled(chooser_id):
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
	if allow_cancel:
		var pass_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		pass_action.payload = {"request_id":request_id, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":"", "confirmed":false}
		result.append(pass_action.to_dict())
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
	if not selected_control_id.is_empty() and (choice_type not in ["control", "bool"] or not candidate_control_ids.has(selected_control_id)):
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
	if confirmed and choice_type in ["control", "bool"]:
		# 控制项数量范围；当前协议使用空字符串表示0项、非空字符串表示1项。
		var selected_control_count: int = 0 if selected_control_id.is_empty() else 1
		var minimum_control_count: int = int(_pending_card_choice.get("min_select", 0))
		var maximum_control_count: int = int(_pending_card_choice.get("max_select", 1))
		if selected_control_count < minimum_control_count or selected_control_count > maximum_control_count:
			return _reject("选择的文字选项数量不符合要求。")
	# 文字控制项的数量已在上方按 control_id 校验；不能再把其空实体牌数组误判为“选择的牌数不足”。
	if confirmed and choice_type not in ["control", "bool"] and selected_uids.size() < min_select:
		return _reject("选择的牌数不足。")
	if selected_uids.size() > max_select:
		return _reject("选择的牌数超过上限。")
	# 请求声明的合法牌组；用于“选择两张牌名字数相同”等跨候选组合约束，客户端不能只凭数量绕过。
	if confirmed and not _is_allowed_card_combination(_pending_card_choice.get("context", {}) as Dictionary, selected_uids):
		return _reject("所选卡牌组合不符合当前技能要求。")
	# 响应转化技能必须由本次提交明确选择；普通实体响应牌不能伪造或继承技能ID。
	var selected_response_skill_id: String = str(action.payload.get("response_skill_id", ""))
	# 候选要求的响应技能ID；单选响应候选通过自身元数据声明，普通选择保持空字符串。
	var required_response_skill_id: String = ""
	if confirmed and selected_uids.size() == 1:
		for candidate_variant: Variant in _pending_card_choice.get("candidates", []) as Array:
			# 当前候选快照；稳定UID匹配后读取其转化技能要求。
			var candidate: Dictionary = candidate_variant as Dictionary
			if int(candidate.get("uid", -1)) == selected_uids[0]:
				required_response_skill_id = str(candidate.get("required_response_skill_id", ""))
				break
	if selected_response_skill_id != required_response_skill_id:
		return _reject("请先发动对应技能，再选择该响应材料。")
	if confirmed and selected_target_ids.size() < min_target_select:
		return _reject("选择的目标数不足。")
	if selected_target_ids.size() > max_target_select:
		return _reject("选择的目标数超过上限。")
	# 已完成请求上下文；运行时确认接收后再清空窗口，避免失败响应把仍可重试的权威请求提前丢失。
	var completed_choice: Dictionary = _pending_card_choice.duplicate(true)
	# 已完成请求的基础上下文；显式响应技能随选择结果进入恢复流程，不由材料牌反向猜测。
	var completed_response_context: Dictionary = (completed_choice.get("context", {}) as Dictionary).duplicate(true)
	completed_response_context["selected_response_skill_id"] = selected_response_skill_id
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
	# 选择完成时机；当前目录仅对 chooseToUse、chooseToRespond 和拼点等流程声明 After，普通选牌不会伪造不存在的事件。
	var choice_after_name: String = "%sAfter" % str(completed_choice.get("choice_event_name", "chooseCard"))
	if RuleTimingCatalog.has_timing(choice_after_name):
		_emit_rule_timing(choice_after_name, action.actor_id, action.actor_id, -1, {"confirmed":runtime_response.confirmed, "selected_card_uids":selected_uids.duplicate(), "selected_target_ids":selected_target_ids.duplicate(), "selected_control_id":selected_control_id, "kind":str((completed_choice.get("context", {}) as Dictionary).get("kind", ""))}, int(completed_choice.get("runtime_event_id", -1)))
	_pending_card_choice.clear()
	state.current_phase = str(completed_choice.get("resume_phase", "play"))
	_resolved_card_choice_uids = selected_uids.duplicate()
	_resolved_target_choice_ids = selected_target_ids.duplicate()
	_resolved_control_choice_id = selected_control_id
	_resolved_equipment_material_uids = equipment_material_uids.duplicate()
	_resolved_response_skill_id = selected_response_skill_id
	state.action_sequence += 1
	if bool(completed_choice.get("deferred", false)):
		_continue_card_choice(completed_choice.get("context", {}) as Dictionary, selected_uids, selected_target_ids, runtime_response.confirmed, selected_control_id)
		# 同一时机的后续可选技能必须等当前技能效果与其可能创建的后续选择完成后再按座次询问。
		# 所有被选择插入打断的触发、装备、规则后半段、技能与阶段统一从同一优先级管线恢复。
		_resume_settlement_pipeline()
	# 没有卡牌内容 token 的阶段级选择也必须在结果应用后完成其选择事件并恢复父事件。
	event_scheduler.drain()
	# 结束阶段技能可能通过统一选择请求暂停回合收尾；最后一个选择完成后再清理回合状态并推进队列。
	if _pending_finish_turn_player_id >= 0 and not has_pending_card_choice():
		var finishing_player_id: int = _pending_finish_turn_player_id
		_pending_finish_turn_player_id = -1
		_continue_after_finish_phase_triggers(finishing_player_id)
		return true
	if bool(completed_choice.get("deferred", false)):
		# 新的 chooseToUse 必须等原 CardUseEvent 及其后续目标全部排空后再创建，避免后续响应覆盖已经提前发布的出牌请求快照。
		if not state.game_over and state.current_phase == "play" and not has_pending_card_choice():
			_begin_play_choice(state.current_player_id)
		_emit_state()
		# AI 出牌被响应或技能选择暂停后，原异步驱动已经结束；统一续接入口负责下一动作或新子选择。
		_ensure_ai_progress_after_resolution()
	return true


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


## 根据暂停上下文恢复具体效果；各分支只调用公开规则操作，不读取任何 UI 节点。
func _continue_card_choice(context: Dictionary, selected_uids: Array[int], selected_target_ids: Array[int] = [], confirmed: bool = true, selected_control_id: String = "") -> void:
	# 选择用途；由创建请求的规则函数写入稳定字符串。
	var choice_kind: String = str(context.get("kind", ""))
	# 技能自有选择恢复；技能 ID 与持有者 ID 由创建请求的技能源码写入上下文。
	var skill_id: String = str(context.get("skill_id", ""))
	if not skill_id.is_empty():
		# 创建请求的技能实例；等待期间失去技能时旧选择安全失效。
		var skill_owner_id: int = int(context.get("skill_owner_id", -1))
		var skill: SkillDefinition = get_skill_instance(skill_owner_id, skill_id)
		if skill != null:
			# 技能响应模式；非空时先统一消费实体牌，再把结果交回技能文件。
			var skill_response_patterns: Array[String] = _string_array(context.get("response_patterns", []) as Array)
			if not skill_response_patterns.is_empty():
				var skill_responder_id: int = int(context.get("responder_id", skill_owner_id))
				var skill_response_card: CardInstance = _consume_response_choice_with_retry(context, selected_uids, skill_responder_id, skill_response_patterns)
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
	elif choice_kind == "extra_discard_phase":
		_continue_extra_discard_phase_choice(context, selected_uids)
	elif choice_kind == "discard_target":
		_continue_target_card_choice(context, selected_uids, false)
	elif choice_kind == "steal_target":
		_continue_target_card_choice(context, selected_uids, true)


## 公开添加一条永久语义日志；UI、回放与调试器均可订阅同一信号。
func add_log(message: String) -> void:
	log_added.emit(message)


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


## 为指定玩家摸若干牌；牌堆不足时自动将弃牌堆洗回，无法继续时提前停止。
func draw(player_id: int, count: int, announce: bool = true) -> void:
	if state == null or state.game_over:
		return
	# 摸牌玩家状态；不存在或死亡玩家不会获得牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	# 摸牌生命周期数据；触发器可在 Before 与 Begin 中修改 count，但不能直接取得牌堆实体引用。
	var timing_data: Dictionary = {"count":maxi(count, 0), "reason":"draw"}
	var before_event: RuleEvent = _emit_rule_timing("drawBefore", player_id, -1, player_id, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		_emit_rule_timing("drawCancelled", player_id, -1, player_id, before_event.data)
		return
	var begin_event: RuleEvent = _emit_rule_timing("drawBegin", player_id, -1, player_id, before_event.data if before_event != null else timing_data)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		_emit_rule_timing("drawCancelled", player_id, -1, player_id, begin_event.data)
		return
	# 最终请求摸牌数；负数统一收敛为0，避免触发器制造反向移动。
	var final_count: int = maxi(int(begin_event.data.get("count", count)) if begin_event != null else count, 0)
	_ensure_card_movement()
	# 上一层摸牌表现批次；嵌套摸牌结束后必须恢复它，保证外层剩余实体仍归入原批次。
	var previous_draw_presentation_batch: Dictionary = _active_draw_presentation_batch
	# 本次稳定表现批次序号；每次 draw() 独占一个编号，多张牌与多次摸牌不会被界面误合并。
	_draw_presentation_batch_sequence += 1
	# 当前批次公开元数据；只保留稳定编号与目标玩家，移牌信号会复制编号而不泄漏 CardInstance。
	var draw_presentation_batch: Dictionary = {"batch_id":_draw_presentation_batch_sequence, "player_id":player_id}
	_active_draw_presentation_batch = draw_presentation_batch
	draw_presentation_batch_started.emit(int(draw_presentation_batch.get("batch_id", -1)), player_id)
	# 实际摸牌数量；可能因牌堆与弃牌堆同时为空而少于请求值。
	var drawn_count: int = 0
	# 实际摸到的实体 UID；后置时机只公开稳定 ID，不暴露 CardInstance。
	var drawn_card_uids: Array[int] = []
	for _index: int in range(final_count):
		if state.draw_pile.is_empty():
			_reshuffle_discard_pile()
		if state.draw_pile.is_empty():
			_end_match_as_draw("deck_empty_draw")
			break
		# 从牌堆顶抽出的实体牌；数组末尾作为牌堆顶。
		var card: CardInstance = state.draw_pile.back()
		# 移动前区域；摸牌动画必须从桌面中心牌堆起飞。
		# 该来源现由 CardMoveEvent 在权威移动前自动捕获，规则函数不再单独发出第二次表现信号。
		if card_movement != null:
			_move_card_with_timings(card, "hand", player_id, "draw", state.current_event_id, "", [player_id])
		else:
			state.draw_pile.pop_back()
			card.zone = "hand"
			card.owner_id = player_id
			player.hand.append(card)
		drawn_count += 1
		drawn_card_uids.append(card.uid)
	# 当前批次已经收集完毕；先通知界面排队播放，再恢复外层批次，drawEnd 中触发的新摸牌会自然进入下一批。
	draw_presentation_batch_finished.emit(int(draw_presentation_batch.get("batch_id", -1)), player_id)
	_active_draw_presentation_batch = previous_draw_presentation_batch
	var result_data: Dictionary = {"count":drawn_count, "requested_count":final_count, "card_uids":drawn_card_uids, "reason":"draw"}
	_emit_rule_timing("drawEnd", player_id, -1, player_id, result_data)
	_emit_rule_timing("drawAfter", player_id, -1, player_id, result_data)
	if announce and drawn_count > 0:
		add_log("%s摸了%d张牌。" % [player.display_name, drawn_count])


## 回复体力并限制在体力上限内；无效目标、死亡目标或非正数回复不会改变状态。
func recover(source_id: int, target_id: int, amount: int, reason: String = "") -> void:
	if state == null or state.game_over:
		return
	# 回复目标状态；死亡角色不能通过普通回复重新加入游戏。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or amount <= 0 or target.hp >= target.max_hp:
		return
	# 回复前时机；允许技能修改 amount 或取消本次回复，player 角色固定为回复目标。
	var timing_data: Dictionary = {"amount":amount, "reason":reason, "hp":target.hp, "max_hp":target.max_hp}
	var before_event: RuleEvent = _emit_rule_timing("recoverBefore", target_id, source_id, target_id, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return
	var begin_event: RuleEvent = _emit_rule_timing("recoverBegin", target_id, source_id, target_id, before_event.data if before_event != null else timing_data)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		return
	# 最终回复请求值；非正数表示触发器已经把本次回复降为无效果。
	var final_amount: int = maxi(int(begin_event.data.get("amount", amount)) if begin_event != null else amount, 0)
	if final_amount <= 0:
		return
	# 回复前体力；用于计算实际回复量并记录准确数值。
	var previous_hp: int = target.hp
	target.hp = mini(target.max_hp, target.hp + final_amount)
	_record_runtime_event("recover", "recover", {"source_id":source_id, "target_id":target_id, "requested_amount":final_amount, "reason":reason}, {"amount":target.hp - previous_hp, "hp":target.hp})
	add_log("%s回复%d点体力（%d/%d）。" % [target.display_name, target.hp - previous_hp, target.hp, target.max_hp])
	# 体力值实际变化时机；回复、伤害与失去体力共用 changeHp，并通过 change_type 区分来源。
	var result_data: Dictionary = {"amount":target.hp - previous_hp, "hp":target.hp, "max_hp":target.max_hp, "reason":reason, "change_type":"recover"}
	_emit_rule_timing("changeHp", target_id, source_id, target_id, result_data)
	_emit_rule_timing("recoverEnd", target_id, source_id, target_id, result_data)
	_emit_rule_timing("recoverAfter", target_id, source_id, target_id, result_data)
	# 回复后事件；技能可读取来源、目标、实际回复值与原因牌。
	var event: RuleEvent = RuleEvent.new("recover_after", source_id, target_id, {"amount": target.hp - previous_hp, "reason": reason})
	_dispatch_rule_event(event)


## 使指定角色获得护盾；护盾没有上限且只会在受到伤害时优先扣减，普通失去体力不会消耗护盾。
func shield(target_id: int, amount: int, source_id: int = -1, reason: String = "") -> int:
	if state == null or state.game_over:
		return 0
	# 护盾目标状态；死亡角色不能获得护盾，避免无效公开状态继续累积。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or amount <= 0:
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
	add_log("%s获得%d点护盾（护盾%d）。" % [target.display_name, gained_amount, target.shield])
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
	if target == null or not target.alive or target.shield <= 0:
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


## 增加或减少角色体力上限；正数使用 gainMaxHp，负数使用 loseMaxHp，返回实际带符号变化量。
func change_max_hp(target_id: int, delta: int, source_id: int = -1, reason: String = "") -> int:
	if state == null or state.game_over or delta == 0:
		return 0
	# 体力上限目标；死亡角色不通过普通内容端口改变上限。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
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
		if target.hp <= 0:
			_resolve_dying(target_id, -1)
	return actual_amount if delta > 0 else -actual_amount


## 设置角色连环状态；状态确实变化时依次派发 linkBefore、linkBegin、linkEnd 和 linkAfter。
func set_player_linked(target_id: int, linked: bool, source_id: int = -1, reason: String = "") -> bool:
	if state == null or state.game_over:
		return false
	# 连环目标状态；死亡角色和无需变化的请求不会重复触发。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or target.chained == linked:
		return false
	var timing_data: Dictionary = {"old_linked":target.chained, "linked":linked, "reason":reason}
	var before_event: RuleEvent = _emit_rule_timing("linkBefore", target_id, source_id, target_id, timing_data)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		return false
	var begin_event: RuleEvent = _emit_rule_timing("linkBegin", target_id, source_id, target_id, before_event.data if before_event != null else timing_data)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		return false
	target.chained = linked
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
	if target == null or not target.alive:
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


## 使指定角色失去体力；该流程绕过护盾、装备修正、伤害事件、伤害历史与属性连环。
func lose_hp(source_id: int, target_id: int, amount: int, reason: String = "") -> int:
	if state == null or state.game_over:
		return 0
	# 失去体力目标状态；死亡角色与非正数请求不会重复修改公开体力。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or amount <= 0:
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
	# 失去体力父事件；与伤害事件使用不同类型，回放和技能触发不会混淆两种体力减少来源。
	var lose_hp_event_id: int = _record_runtime_event("LoseHpEvent", "lose_hp", {"source_id":source_id, "target_id":target_id, "requested_amount":amount, "reason":reason}, {"amount":final_amount, "hp":target.hp})
	add_log("%s失去%d点体力（%d/%d，护盾%d）。" % [target.display_name, final_amount, target.hp, target.max_hp, target.shield])
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


## 造成伤害并执行防具修正、濒死、死亡及属性连环传导。
func damage(source_id: int, target_id: int, amount: int, nature: String = "normal", card_id: String = "", chain_transfer: bool = false, ignore_armor: bool = false, source_context: Dictionary = {}) -> void:
	if state == null or state.game_over:
		return
	# 受伤目标状态；死亡或无效目标不重复结算。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or amount <= 0:
		return
	# 最终伤害值；先应用武器增伤，再应用防具修正与事件处理器。
	var final_amount: int = amount
	# 伤害父事件；多级 Begin、扣血、濒死和来源事件均通过该 ID 建立可回放关系。
	var damage_event_id: int = _record_runtime_event("DamageEvent", "damage", {"source_id":source_id, "target_id":target_id, "amount":amount, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer})
	# 伤害生命周期共享数据；四个修改窗口逐次读取上一时机写回的 amount，保证数值修改链可预测。
	var timing_data: Dictionary = {"amount":final_amount, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id}
	var damage_before_event: RuleEvent = _emit_rule_timing("damageBefore", target_id, source_id, target_id, timing_data, damage_event_id)
	if damage_before_event != null and (damage_before_event.cancelled or damage_before_event.neutralized):
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, damage_before_event.data, damage_event_id)
		return
	var damage_begin_event: RuleEvent = _emit_rule_timing("damageBegin", target_id, source_id, target_id, damage_before_event.data if damage_before_event != null else timing_data, damage_event_id)
	if damage_begin_event != null and (damage_begin_event.cancelled or damage_begin_event.neutralized):
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, damage_begin_event.data, damage_event_id)
		return
	var damage_begin_one_event: RuleEvent = _emit_rule_timing("damageBegin1", target_id, source_id, target_id, damage_begin_event.data if damage_begin_event != null else timing_data, damage_event_id)
	if damage_begin_one_event != null and (damage_begin_one_event.cancelled or damage_begin_one_event.neutralized):
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, damage_begin_one_event.data, damage_event_id)
		return
	final_amount = maxi(int(damage_begin_one_event.data.get("amount", final_amount)) if damage_begin_one_event != null else final_amount, 0)
	# 伤害修正上下文；装备源码只读取稳定规则字段，不依赖控制器内部局部变量。
	var equipment_damage_context: Dictionary = {"source_id":source_id, "target_id":target_id, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer}
	# 伤害来源状态；其武器可覆盖造成伤害修正钩子。
	var equipment_damage_source: PlayerState = state.get_player(source_id) if source_id >= 0 else null
	if equipment_damage_source != null:
		# 来源武器定义；不存在武器或定义缺失时不修改伤害。
		var source_weapon_definition: CardDefinition = get_equipment_definition(source_id, "weapon")
		if source_weapon_definition != null:
			final_amount = source_weapon_definition.modify_outgoing_damage(self, equipment_damage_source, target, equipment_damage_context, final_amount)
	# 第二伤害修改窗口；发生在来源装备修正后、目标防具修正前。
	var damage_begin_two_event: RuleEvent = _emit_rule_timing("damageBegin2", target_id, source_id, target_id, {"amount":final_amount, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id}, damage_event_id)
	if damage_begin_two_event != null and (damage_begin_two_event.cancelled or damage_begin_two_event.neutralized):
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, damage_begin_two_event.data, damage_event_id)
		return
	final_amount = maxi(int(damage_begin_two_event.data.get("amount", final_amount)) if damage_begin_two_event != null else final_amount, 0)
	# 第三伤害修改窗口；通常供受伤角色和防御技能在防具结算前修改。
	var damage_begin_three_event: RuleEvent = _emit_rule_timing("damageBegin3", target_id, source_id, target_id, {"amount":final_amount, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id}, damage_event_id)
	if damage_begin_three_event != null and (damage_begin_three_event.cancelled or damage_begin_three_event.neutralized):
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, damage_begin_three_event.data, damage_event_id)
		return
	final_amount = maxi(int(damage_begin_three_event.data.get("amount", final_amount)) if damage_begin_three_event != null else final_amount, 0)
	if not ignore_armor:
		# 目标防具定义；具体伤害压缩或属性增伤由防具卡牌源码提供。
		var target_armor_definition: CardDefinition = get_equipment_definition(target_id, "armor")
		if target_armor_definition != null:
			# 防具修正前的伤害；仅数值确实变化时才表现为本次防具生效，避免普通伤害重复提示。
			var amount_before_armor: int = final_amount
			final_amount = target_armor_definition.modify_incoming_damage(self, target, equipment_damage_context, final_amount)
			if final_amount != amount_before_armor:
				record_equipment_activation(target_id, target_armor_definition.get_id())
	# 第四及最终伤害修改窗口；其结果直接进入旧 damage_before 兼容事件和实际扣减。
	var damage_begin_four_event: RuleEvent = _emit_rule_timing("damageBegin4", target_id, source_id, target_id, {"amount":final_amount, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id}, damage_event_id)
	if damage_begin_four_event != null and (damage_begin_four_event.cancelled or damage_begin_four_event.neutralized):
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, damage_begin_four_event.data, damage_event_id)
		return
	final_amount = maxi(int(damage_begin_four_event.data.get("amount", final_amount)) if damage_begin_four_event != null else final_amount, 0)

	# 伤害前事件；处理器可修改 amount 或取消整次伤害。
	var before_event: RuleEvent = RuleEvent.new("damage_before", source_id, target_id, {"amount": final_amount, "nature": nature, "card_id": card_id, "chain_transfer": chain_transfer})
	_dispatch_rule_event(before_event)
	if state.game_over or before_event.cancelled:
		_emit_rule_timing("damageCancelled", target_id, source_id, target_id, before_event.data, damage_event_id)
		return
	final_amount = maxi(int(before_event.data.get("amount", final_amount)), 0)
	if final_amount == 0:
		var zero_data: Dictionary = {"amount":0, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id, "shield_absorbed":0, "hp_lost":0, "hp":target.hp, "shield":target.shield}
		_emit_rule_timing("damageZero", target_id, source_id, target_id, zero_data, damage_event_id)
		_finish_damage_timing({"source_id":source_id, "target_id":target_id, "amount":0, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id, "shield_absorbed":0, "hp_lost":0, "chain_targets":[]})
		return

	# 伤害发生前是否处于连环状态；属性伤害需要基于该状态决定传导。
	var should_chain: bool = nature != "normal" and target.chained and not chain_transfer
	# 需要接收传导的其他横置角色；在原目标结算前建立快照。
	var chain_targets: Array[int] = []
	if should_chain:
		# 连环传导顺序；多角色结算从当前回合角色起按存活座次建立目标快照。
		var chain_order: Array[PlayerState] = _get_alive_players_in_action_order(state.current_player_id)
		for player: PlayerState in chain_order:
			if player.alive and player.chained and player.player_id != target_id:
				chain_targets.append(player.player_id)

	# 伤害发生前护盾值；只用于计算本次优先吸收量，不改变最终伤害事件本身的数值。
	var shield_before_damage: int = maxi(target.shield, 0)
	# 本次由护盾吸收的伤害值；最多吸收到最终伤害值，护盾不会变成负数。
	var shield_absorbed: int = mini(shield_before_damage, final_amount)
	if shield_absorbed > 0:
		# 护甲减少前时机；amount 表示本次将扣除的护甲值，取消后伤害全部穿透到体力。
		var hujia_before_event: RuleEvent = _emit_rule_timing("changeHujiaBefore", target_id, source_id, target_id, {"amount":shield_absorbed, "old_hujia":shield_before_damage, "reason":"damage", "damage_event_id":damage_event_id, "change_type":"lose"}, damage_event_id)
		if hujia_before_event != null and (hujia_before_event.cancelled or hujia_before_event.neutralized):
			shield_absorbed = 0
		else:
			shield_absorbed = clampi(int(hujia_before_event.data.get("amount", shield_absorbed)) if hujia_before_event != null else shield_absorbed, 0, mini(shield_before_damage, final_amount))
	# 本次实际扣减的体力值；伤害剩余量为0时仍属于一次有效伤害并触发 damage_after。
	var hp_lost: int = final_amount - shield_absorbed
	target.shield = shield_before_damage - shield_absorbed
	target.hp -= hp_lost
	if shield_absorbed > 0:
		_emit_rule_timing("changeHujiaAfter", target_id, source_id, target_id, {"amount":shield_absorbed, "hujia":target.shield, "reason":"damage", "damage_event_id":damage_event_id, "change_type":"lose"}, damage_event_id)
	_record_runtime_event("damage", "damage", {"source_id":source_id, "target_id":target_id, "nature":nature}, {"amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "shield":target.shield, "hp":target.hp}, damage_event_id)
	target.damage_taken_count += 1
	target.damage_history.append({"event_id":damage_event_id, "source_id":source_id, "target_id":target_id, "amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "nature":nature})
	var source_player: PlayerState = state.get_player(source_id)
	if source_player != null and source_player != target:
		source_player.damage_history.append({"event_id":damage_event_id, "source_id":source_id, "target_id":target_id, "amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "nature":nature})
	if target.chained and nature != "normal":
		target.chained = false
	if shield_absorbed > 0:
		add_log("%s受到%d点%s伤害，护盾抵消%d点（%d/%d，护盾%d）。" % [target.display_name, final_amount, _nature_text(nature), shield_absorbed, target.hp, target.max_hp, target.shield])
	else:
		add_log("%s受到%d点%s伤害（%d/%d）。" % [target.display_name, final_amount, _nature_text(nature), target.hp, target.max_hp])
	# 伤害实际成立时机；发生在护甲和体力扣减后、旧 damage_after 与濒死流程前。
	var damage_result_data: Dictionary = {"amount":final_amount, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "shield":target.shield, "hp":target.hp, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id}
	for context_key_variant: Variant in source_context.keys():
		# 来源上下文字段名；只补充【杀】父牌与目标流程数据，不覆盖伤害核心最终值。
		var context_key: String = str(context_key_variant)
		if not damage_result_data.has(context_key):
			damage_result_data[context_key] = source_context[context_key_variant]
	if hp_lost > 0:
		_emit_rule_timing("changeHp", target_id, source_id, target_id, {"amount":hp_lost, "hp":target.hp, "max_hp":target.max_hp, "reason":card_id, "change_type":"damage", "damage_event_id":damage_event_id}, damage_event_id)
	_emit_rule_timing("damage", target_id, source_id, target_id, damage_result_data, damage_event_id)
	# 伤害实际成立后的可序列化上下文；标准damage时机可能产生装备或技能选择，后续旧事件、濒死与尾部必须原地恢复。
	var post_result_context: Dictionary = {"post_result_stage":"damage_after", "source_id":source_id, "target_id":target_id, "amount":final_amount, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer, "damage_event_id":damage_event_id, "shield_absorbed":shield_absorbed, "hp_lost":hp_lost, "hp":target.hp, "shield":target.shield, "chain_targets":chain_targets.duplicate()}
	# damage时机内的选择必须先完成全部同一时机处理器；不能提前发布damage_after、濒死或整条伤害尾部。
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("damage_after_result", post_result_context)
		return
	_continue_damage_after_result(post_result_context)


## 在标准damage时机及其嵌套选择完成后，按旧兼容事件、体力减少、濒死和伤害尾部的固定顺序继续。
func _continue_damage_after_result(context: Dictionary) -> void:
	# 伤害来源稳定 ID；等待期间只用编号重新定位角色，不能保留旧 PlayerState 对象。
	var source_id: int = int(context.get("source_id", -1))
	# 伤害目标稳定 ID；用于恢复兼容事件、体力减少、濒死与伤害尾部的同一目标。
	var target_id: int = int(context.get("target_id", -1))
	# 当前伤害后阶段；异步恢复只从尚未执行的步骤继续，避免重复发布兼容事件或体力减少事件。
	var post_result_stage: String = str(context.get("post_result_stage", "damage_after"))
	# 伤害后事件；在濒死前触发，允许技能依据已扣减体力进行处理。
	if post_result_stage == "damage_after":
		# 旧兼容伤害后事件；字段保持伤害实际成立时的快照，不受等待期间其他回复或护盾变化反向改写。
		var after_event: RuleEvent = RuleEvent.new("damage_after", source_id, target_id, {"amount":int(context.get("amount", 0)), "shield_absorbed":int(context.get("shield_absorbed", 0)), "hp_lost":int(context.get("hp_lost", 0)), "shield":int(context.get("shield", 0)), "hp":int(context.get("hp", 0)), "nature":str(context.get("nature", "normal")), "card_id":str(context.get("card_id", "")), "chain_transfer":bool(context.get("chain_transfer", false))})
		_dispatch_rule_event(after_event)
		post_result_stage = "hp_reduced"
		if state == null or state.game_over:
			return
		# 兼容事件中的选择同样属于当前伤害子流程，完成后才发布通用体力减少事件。
		if _has_nested_settlement_barrier():
			var after_event_resume_context: Dictionary = context.duplicate(true)
			after_event_resume_context["post_result_stage"] = post_result_stage
			_defer_rule_continuation("damage_after_result", after_event_resume_context)
			return
	if post_result_stage == "hp_reduced" and int(context.get("hp_lost", 0)) > 0:
		# 通用体力减少事件；只在伤害穿透护盾并实际扣减体力时派发，便于技能统一观察两类体力变化。
		_dispatch_rule_event(RuleEvent.new("hp_reduced", source_id, target_id, {"amount":int(context.get("hp_lost", 0)), "hp":int(context.get("hp", 0)), "reduction_type":"damage", "damage_amount":int(context.get("amount", 0)), "shield_absorbed":int(context.get("shield_absorbed", 0)), "nature":str(context.get("nature", "normal")), "card_id":str(context.get("card_id", "")), "event_id":int(context.get("damage_event_id", -1))}))
	post_result_stage = "dying"
	if state == null or state.game_over:
		return
	# 通用体力减少事件产生的技能选择必须先完成；濒死询问不能与其共享同一个活动选择槽。
	if _has_nested_settlement_barrier():
		var hp_reduced_resume_context: Dictionary = context.duplicate(true)
		hp_reduced_resume_context["post_result_stage"] = post_result_stage
		_defer_rule_continuation("damage_after_result", hp_reduced_resume_context)
		return
	# 伤害尾部上下文；濒死可能暂停，因此 damageSource、End、After 和连环必须保存到救援结束后执行。
	var finalization_context: Dictionary = {"source_id":source_id, "target_id":target_id, "amount":int(context.get("amount", 0)), "nature":str(context.get("nature", "normal")), "card_id":str(context.get("card_id", "")), "chain_transfer":bool(context.get("chain_transfer", false)), "damage_event_id":int(context.get("damage_event_id", -1)), "shield_absorbed":int(context.get("shield_absorbed", 0)), "hp_lost":int(context.get("hp_lost", 0)), "chain_targets":(context.get("chain_targets", []) as Array).duplicate()}
	# 最新伤害目标；damage或兼容事件等待期间可能已被其他嵌套效果回复、杀死或移出游戏。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		_finish_damage_timing(finalization_context)
		return
	if target.hp <= 0:
		_pending_damage_finalizations[target_id] = finalization_context
		_resolve_dying(target_id, source_id)
		if _pending_damage_finalizations.has(target_id) and not has_pending_card_choice():
			_finish_pending_damage(target_id)
		return
	_finish_damage_timing(finalization_context)


## 完成一条无需继续等待或已经结束濒死流程的伤害尾部；严格派发 damageSource、damageEnd、damageAfter 后再传导属性伤害。
func _finish_damage_timing(context: Dictionary) -> void:
	# 伤害来源、目标和父事件 ID；全部从保存上下文恢复，异步期间不会引用旧 PlayerState 对象。
	# 伤害来源稳定 ID；来源时机与连环传导继续沿用原始伤害来源。
	var source_id: int = int(context.get("source_id", -1))
	# 伤害目标稳定 ID；来源、结束与受伤后时机都围绕同一名已受伤角色发布。
	var target_id: int = int(context.get("target_id", -1))
	# 父伤害事件稳定 ID；三个标准尾部时机共享该编号以维持同一事件链追踪。
	var damage_event_id: int = int(context.get("damage_event_id", -1))
	# 当前伤害尾部阶段；默认从来源时机开始，异步恢复时只执行尚未完成的后续阶段。
	var finalization_stage: String = str(context.get("finalization_stage", "damageSource"))
	# 统一尾部数据；来源触发与受伤者触发读取同一最终伤害、护甲吸收和体力减少值。
	var timing_data: Dictionary = {
		"amount":int(context.get("amount", 0)),
		"shield_absorbed":int(context.get("shield_absorbed", 0)),
		"hp_lost":int(context.get("hp_lost", 0)),
		"nature":str(context.get("nature", "normal")),
		"card_id":str(context.get("card_id", "")),
		"chain_transfer":bool(context.get("chain_transfer", false)),
		"damage_event_id":damage_event_id,
	}
	if finalization_stage == "damageSource":
		_emit_rule_timing("damageSource", target_id, source_id, target_id, timing_data, damage_event_id)
		finalization_stage = "damageEnd"
		if state == null or state.game_over:
			return
		# 伤害来源时机产生的技能选择必须先完整结束；伤害End与After不能越过该时机并抢占选择窗口。
		if _has_nested_settlement_barrier():
			var source_resume_context: Dictionary = context.duplicate(true)
			source_resume_context["finalization_stage"] = finalization_stage
			_defer_rule_continuation("damage_finalization", source_resume_context)
			return
	if finalization_stage == "damageEnd":
		_emit_rule_timing("damageEnd", target_id, source_id, target_id, timing_data, damage_event_id)
		finalization_stage = "damageAfter"
		if state == null or state.game_over:
			return
		# 伤害结束时机的嵌套操作与来源时机遵循相同屏障，完成后才进入最终伤害后时机。
		if _has_nested_settlement_barrier():
			var end_resume_context: Dictionary = context.duplicate(true)
			end_resume_context["finalization_stage"] = finalization_stage
			_defer_rule_continuation("damage_finalization", end_resume_context)
			return
	if finalization_stage == "damageAfter":
		_emit_rule_timing("damageAfter", target_id, source_id, target_id, timing_data, damage_event_id)
		finalization_stage = "chain"
		if state == null or state.game_over:
			return
		# 伤害后技能完成前不能开始属性连环的下一名目标，避免新伤害选择覆盖当前伤害选择。
		if _has_nested_settlement_barrier():
			var after_resume_context: Dictionary = context.duplicate(true)
			after_resume_context["finalization_stage"] = finalization_stage
			_defer_rule_continuation("damage_finalization", after_resume_context)
			return
	if state == null or state.game_over:
		return
	# 已完成连环目标数量；每个子伤害前预登记父续接，异步时按栈顺序先完成子伤害再回来处理下一名目标。
	var chain_target_index: int = int(context.get("chain_target_index", 0))
	# 连环目标快照；保持原伤害建立时的座次顺序，等待期间只重新校验存活与横置状态。
	var chain_targets: Array = context.get("chain_targets", []) as Array
	while chain_target_index < chain_targets.size():
		# 传导前再次检查角色仍存活且横置，避免前序死亡结算改变有效目标。
		var chained_target_id: int = int(chain_targets[chain_target_index])
		# 当前连环目标状态；每轮重新按稳定 ID 读取，防止嵌套伤害后继续使用过期对象。
		var chained_target: PlayerState = state.get_player(chained_target_id)
		chain_target_index += 1
		if chained_target == null or not chained_target.alive or not chained_target.chained:
			continue
		# 父伤害剩余连环上下文；先压栈可保证子伤害产生的后续步骤位于其上方，子流程同步完成时再精确撤销。
		var chain_resume_context: Dictionary = context.duplicate(true)
		chain_resume_context["finalization_stage"] = "chain"
		chain_resume_context["chain_target_index"] = chain_target_index
		# 父伤害保险续接编号；异步子伤害保留该记录，同步完成则立即移除并继续本循环。
		var chain_continuation_id: int = _defer_rule_continuation("damage_finalization", chain_resume_context)
		damage(source_id, chained_target_id, int(context.get("amount", 0)), str(context.get("nature", "normal")), str(context.get("card_id", "")), true, false)
		if state == null or state.game_over:
			return
		if _has_nested_settlement_barrier():
			return
		_rule_continuations.remove(chain_continuation_id)


## 读取并移除指定濒死目标等待中的伤害尾部；重复调用安全返回且不会重复派发来源或连环事件。
func _finish_pending_damage(target_id: int) -> void:
	if not _pending_damage_finalizations.has(target_id):
		return
	# 保存的伤害尾部；先移除再派发，防止尾部技能重入同一目标时重复读取旧上下文。
	var context: Dictionary = _pending_damage_finalizations[target_id] as Dictionary
	_pending_damage_finalizations.erase(target_id)
	_finish_damage_timing(context)


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
	if player == null or not player.alive:
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
	# 可响应候选；手牌与木牛“粮”都按实际 UID 提供给本人，规则定义决定是否匹配响应模式。
	var candidates: Array[Dictionary] = _build_response_choice_candidates(player, allowed_patterns, excluded_response_candidate_uids)
	# 完整响应上下文；恢复回调使用同一模式集合校验实体牌，不能由客户端自行声明所选牌的响应类型。
	var response_context: Dictionary = context.duplicate(true)
	response_context["response_patterns"] = allowed_patterns.duplicate()
	response_context["response_prompt"] = prompt
	# 当前候选需要显式点击的转化技能；该列表由实体候选反向汇总，确保任何合法视为牌在本次响应窗口都有可用技能入口。
	var response_conversion_skill_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		# 候选声明的转化技能；普通实体响应牌保持空字符串，不会额外点亮技能按钮。
		var response_skill_id: String = str(candidate.get("required_response_skill_id", ""))
		if not response_skill_id.is_empty() and not response_conversion_skill_ids.has(response_skill_id):
			response_conversion_skill_ids.append(response_skill_id)
	response_context["response_conversion_skill_ids"] = response_conversion_skill_ids
	# 响应允许主动不出牌；即使候选为空也创建请求，保证 AI 与真实玩家经历相同问询。
	var selected_uids: Array[int] = request_card_choice(player_id, "响应询问", prompt, candidates, 0, 1, true, response_context)
	if has_pending_card_choice() or selected_uids.is_empty():
		return null
	return _consume_response_card_uid_patterns(player_id, selected_uids[0], allowed_patterns, _resolved_equipment_material_uids, _resolved_response_skill_id)


## 构造指定玩家在同一响应模式集合下的私有候选；普通逐人响应与无懈同时响应共用此入口。
func _build_response_choice_candidates(player: PlayerState, allowed_patterns: Array[String], excluded_card_uids: Array[int] = []) -> Array[Dictionary]:
	# 可序列化候选结果；只包含响应者本人可见的实体牌与公开装备入口。
	var candidates: Array[Dictionary] = []
	if player == null or not player.alive:
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
	if selected_uids.is_empty():
		return null
	# 当前响应结果；普通实体牌与成功的虚拟装备响应会直接返回，不创建第二次询问。
	var response_card: CardInstance = _consume_response_card_uid_patterns(responder_id, selected_uids[0], response_patterns, _int_array(context.get("equipment_material_uids", []) as Array), str(context.get("selected_response_skill_id", "")))
	if response_card != null:
		return response_card
	# 本次失败的装备入口 UID；只有权威提交阶段明确识别为装备候选时才允许重开响应。
	var failed_equipment_uid: int = int(context.get("selected_response_equipment_uid", -1))
	if failed_equipment_uid < 0 or failed_equipment_uid != selected_uids[0]:
		return null
	# 重试上下文；移除上一次选择标记，并把失败装备加入本响应时机的排除集合。
	var retry_context: Dictionary = context.duplicate(true)
	retry_context.erase("selected_response_equipment_uid")
	retry_context.erase("equipment_material_uids")
	# 已排除装备 UID；数组会跨多次判定型装备失败累积，但只作用于当前响应上下文。
	var excluded_response_candidate_uids: Array[int] = _int_array(retry_context.get("excluded_response_candidate_uids", []) as Array)
	if not excluded_response_candidate_uids.has(failed_equipment_uid):
		excluded_response_candidate_uids.append(failed_equipment_uid)
	retry_context["excluded_response_candidate_uids"] = excluded_response_candidate_uids
	# 原响应提示；上下文缺失时使用稳定通用文本，不把具体牌名硬编码进控制器。
	var response_prompt: String = str(context.get("response_prompt", "请选择是否响应。"))
	return request_response_card_patterns(responder_id, response_patterns, response_prompt, retry_context)


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
	if skill == null:
		return
	# 原响应规则上下文；牌效、响应者和父事件信息保持选择创建时的可序列化快照。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
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
	effect_resolver.continue_response(rule_context, response_card)
	if not bool(rule_context.get("complete_parent_target_after_response", false)) or state.game_over:
		return
	# 待完成父牌实体 UID；响应效果期间产生的新触发必须先结算，之后只执行一次目标完成步骤。
	var parent_card_uid: int = int(rule_context.get("parent_card_uid", -1))
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("target_card_completion", {"parent_card_uid":parent_card_uid})
		return
	_complete_active_card_target(parent_card_uid)


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


## 按选择请求提交的 UID 消耗响应牌；再次校验区域和响应模式后进入弃牌堆并播放动画。
func _consume_response_card_uid(player_id: int, card_uid: int, response_pattern: String) -> CardInstance:
	return _consume_response_card_uid_patterns(player_id, card_uid, [response_pattern])


## 按候选响应模式集合消耗一张实体牌；用于【桃】与【酒】等共享时机但牌名不同的单一询问窗口。
func _consume_response_card_uid_patterns(player_id: int, card_uid: int, response_patterns: Array[String], equipment_material_uids: Array[int] = [], response_skill_id: String = "") -> CardInstance:
	# 响应玩家；请求等待期间其牌区可能被插入结算改变，因此必须重新查询。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null
	# 装备响应入口；装备文件负责复核模式、实体 UID、材料并返回虚拟响应牌。
	for equipment_variant: Variant in player.equipment.values():
		# 当前装备实体；只允许选择仍在装备区的同一 UID。
		var equipment_card: CardInstance = equipment_variant as CardInstance
		if equipment_card.uid != card_uid:
			continue
		# 当前装备定义；不能提供本次模式时返回 null。
		var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_card.definition_id)
		if equipment_definition != null and equipment_definition.can_offer_equipment_response(self, player_id, response_patterns):
			return equipment_definition.consume_equipment_response(self, player_id, card_uid, response_patterns, equipment_material_uids)
		return _consume_skill_converted_response(player_id, equipment_card, response_patterns, response_skill_id)
	# 被选响应牌；只能来自当前仍可使用的牌源。
	var card: CardInstance = player.find_playable_card(card_uid)
	if card == null:
		return null
	# 响应定义；模式不匹配时拒绝消费，防止旧请求或伪造动作改变状态。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 实体牌实际响应模式；日志与历史必须记录牌自身能提供的模式，不能把普通锦囊的受响应字段当作无懈牌能力。
	var response_pattern: String = _get_provided_response_pattern(definition)
	if not response_patterns.has(response_pattern):
		return _consume_skill_converted_response(player_id, card, response_patterns, response_skill_id)
	# 响应牌生命周期数据；player 与 source 都是响应者，父级牌或选择用途保留在 response_pattern 中。
	var timing_data: Dictionary = {"card_uid":card.uid, "card_id":card.definition_id, "response_pattern":response_pattern}
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
	_move_to_discard(consumed)
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "card_uid":consumed.uid}, {"responded":true})
	timing_data["respond_event_id"] = respond_event_id
	_emit_rule_timing("respond", player_id, player_id, -1, timing_data, respond_event_id)
	player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":consumed.uid})
	# 响应结果对象；普通牌直接沿用实体，手牌视为牌使用逻辑代理以继续正确执行【桃】等后续效果。
	var resolved_response_card: CardInstance = consumed
	if was_hand_view_as:
		resolved_response_card = CardInstance.new(logical_definition_id, consumed.suit, consumed.rank)
		resolved_response_card.uid = consumed.uid
		resolved_response_card.zone = consumed.zone
	# 响应日志显示已经声明的逻辑牌名，弃牌堆中的实体快照仍展示恢复后的原始牌名。
	add_log("%s打出了%s。" % [player.display_name, describe_card(resolved_response_card)])
	_notify_equipment_card_consumed(player.player_id, consumed, was_hand_card)
	_emit_rule_timing("respondEnd", player_id, player_id, -1, timing_data, respond_event_id)
	_emit_rule_timing("respondAfter", player_id, player_id, -1, timing_data, respond_event_id)
	return resolved_response_card


## 返回一张牌实际能够提供的响应模式；映射基于牌效语义，避免所有可被无懈的普通锦囊都被误当成【无懈可击】。
func _get_provided_response_pattern(definition: Dictionary) -> String:
	# 卡牌文件显式提供的响应模式；新增响应牌不需要登记牌效兼容映射。
	return str(definition.get("provided_response_pattern", ""))


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
		if skill != null and skill.can_convert_response_card(card, response_patterns):
			return skill.get_id()
	return ""


## 通过首个仍合法的武将技能消耗一张材料牌并生成虚拟响应牌；等待期间条件失效时不移动材料。
func _consume_skill_converted_response(player_id: int, material_card: CardInstance, response_patterns: Array[String], response_skill_id: String = "") -> CardInstance:
	if material_card == null or response_skill_id.is_empty():
		return null
	# 当前玩家的运行时技能表；安装顺序决定多个转化技能同时可用时的稳定优先级。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前候选技能；必须在提交时再次满足材料颜色、区域和响应模式条件。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or skill.get_id() != response_skill_id or not skill.can_convert_response_card(material_card, response_patterns):
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
		var timing_data: Dictionary = {"card_uid":material_card.uid, "card_id":virtual_definition_id, "material_card_id":material_card.definition_id, "response_pattern":response_pattern, "skill_id":skill.get_id(), "virtual":true}
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
		# 虚拟响应父事件；材料先进入处理区再进入弃牌堆，与普通响应牌保持相同公开移动语义。
		var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "skill_id":skill.get_id(), "material_card_uids":[material_card.uid]}, {"responded":true, "virtual":true, "card_id":virtual_definition_id})
		_ensure_card_movement()
		if _move_card_with_timings(material_card, "processing", -1, "respond", respond_event_id) == null:
			return null
		if was_equipment_card:
			_on_equipment_lost(player, material_card, true)
		_move_card_with_timings(material_card, "discard_pile", -1, "respond", respond_event_id)
		timing_data["respond_event_id"] = respond_event_id
		_emit_rule_timing("respond", player_id, player_id, -1, timing_data, respond_event_id)
		player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":-1, "material_card_uids":[material_card.uid], "skill_id":skill.get_id(), "virtual_card_id":virtual_definition_id})
		skill.on_converted_response_consumed(material_card, response_pattern, virtual_definition_id)
		skill.announce_activation({"material_card_uid":material_card.uid, "response_pattern":response_pattern, "virtual_card_id":virtual_definition_id})
		add_log("%s将一张牌当%s打出。" % [player.display_name, GameSettings.resolve_card_name(virtual_definition)])
		_notify_equipment_card_consumed(player_id, material_card, was_hand_card)
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
	response_results.append({"player_id":responder_id, "card_uid":counter_card.uid, "card_id":counter_card.definition_id, "respond_to":str(context.get("trick_id", ""))})
	context["wuxie_response_results"] = response_results
	# 原锦囊定义；无懈身份观察通过其目标收益与当前奇偶结果判断本次响应的忠反方向。
	var response_subject_definition: Dictionary = GameDatabase.get_card(str(context.get("trick_id", "")))
	# 成功打出的无懈可击公开行为；仅在原使用者已有暴露且响应者不是目标本人时形成身份线索。
	ai_coordinator.observe_card_response(state.to_dict(-1, true), responder_id, GameDatabase.get_card(counter_card.definition_id), response_subject_definition, context, local_human_player_id)
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
			if responder == null or not responder.alive or not _should_auto_negate(responder, int(context.get("source_id", -1)), int(context.get("target_id", -1)), str(context.get("trick_id", "")), bool(context.get("negated", false))):
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
	var choice_event: GameEvent = event_scheduler.create_event("chooseToRespond", "choice", [], response_context, int(round_context.get("negation_parent_event_id", _runtime_root_event_id)))
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
	if not state.game_over and state.current_phase == "play" and not has_pending_card_choice():
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
		if equipment_definition != null and equipment_definition.can_offer_equipment_response(self, player.player_id, response_patterns):
			return equipment_definition
		return null
	return null


## 消耗若干已经由装备源码验证的普通手牌，并生成无花色、无点数的虚拟响应牌。
func consume_virtual_equipment_response(player_id: int, equipment_uid: int, material_card_uids: Array[int], response_pattern: String, virtual_card_definition_id: String, log_message: String) -> CardInstance:
	# 响应玩家；不存在或材料为空时不能生成虚拟牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or material_card_uids.is_empty() or response_pattern.is_empty() or virtual_card_definition_id.is_empty():
		return null
	for material_card_uid: int in material_card_uids:
		if player.find_hand_card(material_card_uid) == null:
			return null
	_ensure_card_movement()
	# 响应事件；全部材料共享同一稳定父事件，便于回放还原顺序。
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "equipment_uid":equipment_uid, "material_card_uids":material_card_uids.duplicate()}, {"responded":true, "virtual":true})
	for material_card_uid: int in material_card_uids:
		# 当前材料；装备源码已验证来自普通手牌，移动前仍需重新查询防止旧选择。
		var material_card: CardInstance = player.find_hand_card(material_card_uid)
		_move_card_with_timings(material_card, "processing", -1, "respond", respond_event_id)
		_move_card_with_timings(material_card, "discard_pile", -1, "respond", respond_event_id)
	player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":-1, "material_card_uids":material_card_uids.duplicate(), "equipment_uid":equipment_uid})
	if not log_message.is_empty():
		add_log(log_message)
	# 虚拟响应牌不继承任一材料花色、点数或颜色。
	return CardInstance.new(virtual_card_definition_id, "none", 0)


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
			# 从手牌移出的响应牌；随后直接进入弃牌堆。
			var consumed: CardInstance = player.take_playable_card(card.uid)
			_move_to_discard(consumed)
			add_log("%s打出了%s。" % [player.display_name, describe_card(consumed)])
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
	# 直击目标不能响应本次锦囊；该查询来自当前 CardUseEvent 的 directHit 集合，不创建空无懈窗口。
	if parent_card != null and is_card_target_direct_hit(parent_card.uid, target_id):
		return false
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


## 执行一次判定并将判定牌置入弃牌堆；返回牌对象供调用方读取花色与点数。
## 判定牌遵循无名杀 judge -> judgeResult -> cardsDiscard 顺序，并在判定者位置公开展示后由同一表现接管弃牌动画。
func perform_judgment(player_id: int, reason: String) -> CardInstance:
	if state == null or state.game_over:
		return null
	# 判定玩家；不存在或已经离场时不能创建判定事件。
	var judgment_player: PlayerState = state.get_player(player_id)
	if judgment_player == null or not judgment_player.alive:
		return null
	# 判定前与开始时机；取消后不从牌堆取牌，也不创建中央判定展示。
	var judge_before_event: RuleEvent = _emit_rule_timing("judgeBefore", player_id, player_id, player_id, {"reason":reason})
	if judge_before_event != null and (judge_before_event.cancelled or judge_before_event.neutralized):
		return null
	var judge_begin_event: RuleEvent = _emit_rule_timing("judgeBegin", player_id, player_id, player_id, judge_before_event.data if judge_before_event != null else {"reason":reason})
	if judge_begin_event != null and (judge_begin_event.cancelled or judge_begin_event.neutralized):
		return null
	if state.draw_pile.is_empty():
		_reshuffle_discard_pile()
	if state.draw_pile.is_empty():
		_end_match_as_draw("deck_empty_judgment")
		return null
	# 判定父事件；判定牌移动、结果和后置弃牌都通过该 ID 建立可回放关联。
	var judgment_event_id: int = _record_runtime_event("judge", "judgment", {"player_id":player_id, "reason":reason}, {}, _current_rule_parent_event_id())
	# 牌堆顶判定牌；判定生效后直接进入弃牌堆。
	# 牌堆顶判定牌；先进入公共处理区并公开展示，判定结果记录后再进入弃牌堆。
	_ensure_card_movement()
	var judgment_card: CardInstance = state.draw_pile.back()
	_move_card_with_timings(judgment_card, "processing", -1, "judge", judgment_event_id)
	# 判定牌产生时机；技能可读取牌面稳定字段并在 judgeFixing 前记录修改结果。
	var judge_data: Dictionary = {"player_id":player_id, "reason":reason, "card_uid":judgment_card.uid, "card_id":judgment_card.definition_id, "suit":judgment_card.suit, "rank":judgment_card.rank, "color":judgment_card.get_color()}
	_emit_rule_timing("judge", player_id, player_id, player_id, judge_data, judgment_event_id)
	# 判定牌属于公共牌堆而非判定角色打出的牌；来源使用-1让界面直接从中央弃牌锚点出现。
	_request_card_presentation(judgment_card, -1, [], "judge", judgment_event_id, true)
	add_log("%s的%s判定牌为%s。" % [judgment_player.display_name, reason, describe_card(judgment_card)])
	_emit_rule_timing("judgeFixing", player_id, player_id, player_id, judge_data, judgment_event_id)
	_record_runtime_event("judgeResult", "judgment_result", {"player_id":player_id, "reason":reason, "card_uid":judgment_card.uid}, {"suit":judgment_card.suit, "rank":judgment_card.rank, "color":judgment_card.get_color()}, judgment_event_id)
	_move_to_discard(judgment_card, judgment_event_id)
	_emit_rule_timing("judgeEnd", player_id, player_id, player_id, judge_data, judgment_event_id)
	_emit_rule_timing("judgeAfter", player_id, player_id, player_id, judge_data, judgment_event_id)
	return judgment_card


## 将处理区中的装备放入对应槽位，并处理旧装备离开时的效果。
func equip_from_processing(player_id: int, card: CardInstance) -> void:
	# 装备目标玩家；装备牌默认只能对自己使用。
	var player: PlayerState = state.get_player(player_id)
	# 装备卡定义；slot 决定唯一装备槽。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 装备槽名称；配置表保证非空。
	var slot: String = str(definition.get("slot", ""))
	if player.equipment.has(slot):
		_discard_equipment_slot(player_id, slot, true)
	_ensure_card_movement()
	_move_card_with_timings(card, "equipment", player_id, "equip", state.current_event_id, slot)
	_install_card_runtime(card, player_id)
	add_log("%s装备了%s。" % [player.display_name, describe_card(card)])


## 将处理区中的延时锦囊放入目标判定区。
func place_delayed_trick(target_id: int, card: CardInstance) -> void:
	# 延时锦囊目标；合法性层已保证其存活且判定区无同名牌。
	var target: PlayerState = state.get_player(target_id)
	_ensure_card_movement()
	_move_card_with_timings(card, "judgment", target_id, "add_judge", state.current_event_id)
	add_log("%s的判定区加入了%s。" % [target.display_name, describe_card(card)])


## 请求来源角色自主选择并弃置目标区域的一张牌；候选固定按手牌、装备、判定区排列。
func discard_one_from_player(_source_id: int, target_id: int, parent_card_uid: int = -1) -> void:
	# 目标区域候选；不可见手牌只公开牌背，不泄露定义、花色或点数。
	var candidates: Array[Dictionary] = _build_player_zone_candidates(_source_id, target_id)
	# 本次选择上下文；人类稍后提交时据此恢复过河拆桥结算并收尾处理区卡牌。
	var context: Dictionary = {"kind":"discard_target", "source_id":_source_id, "target_id":target_id, "parent_card_uid":parent_card_uid}
	# 选择结果；AI 会通过 choose_cards 同步返回，人类则保持请求挂起。
	var selected_uids: Array[int] = request_card_choice(_source_id, "选择弃置牌", "请选择目标区域内的一张牌", candidates, 1, 1, false, context)
	if has_pending_card_choice() or selected_uids.is_empty():
		return
	_discard_selected_player_card(target_id, selected_uids[0])


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


## 把实体牌转换为选择候选；隐藏候选只保留 UID 和牌背语义，不携带牌面定义。
func _serialize_choice_candidate(card: CardInstance, owner_id: int, zone: String, visible: bool, slot: String = "") -> Dictionary:
	# 可见牌面数据；隐藏手牌不发送定义、花色和点数。
	var card_data: Dictionary = card.to_dict() if visible else {"uid":card.uid, "definition_id":"", "suit":"none", "rank":0, "zone":zone, "owner_id":owner_id}
	return {"uid":card.uid, "owner_id":owner_id, "zone":zone, "slot":slot, "visible":visible, "card_data":card_data}


## 弃置目标区域内指定 UID 的牌；区域查找基于实体 UID，不依赖候选数组下标。
func _discard_selected_player_card(target_id: int, card_uid: int) -> bool:
	# 目标玩家；无效目标不能移动牌。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
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
	add_log("%s获得了%s的一张牌。" % [source.display_name, target.display_name])
	return true


## 恢复延迟的过河拆桥或顺手牵羊选择，并在效果完成后把原锦囊移入弃牌堆。
func _continue_target_card_choice(context: Dictionary, selected_uids: Array[int], is_steal: bool) -> void:
	if selected_uids.is_empty():
		return
	# 来源角色 ID；顺手牵羊需要把牌交给该角色。
	var source_id: int = int(context.get("source_id", -1))
	# 目标角色 ID；所选 UID 必须仍位于其区域。
	var target_id: int = int(context.get("target_id", -1))
	if is_steal:
		_take_selected_player_card(source_id, target_id, selected_uids[0])
	else:
		_discard_selected_player_card(target_id, selected_uids[0])
	# 区域移动触发的技能与装备事件必须先结算；父锦囊目标完成步骤只登记一次稳定续接点。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("target_card_completion", {"parent_card_uid":parent_card_uid})
		return
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
	for _index: int in range(maxi(count, 0)):
		# 当前玩家状态；每次循环重新读取区域数量。
		var player: PlayerState = state.get_player(player_id)
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand[0].uid)
		elif not player.equipment.is_empty():
			_discard_equipment_slot(player_id, str(player.equipment.keys()[0]), true)
		elif not player.judgment_area.is_empty():
			_move_to_discard(player.judgment_area.pop_front())
		else:
			return


## 返回玩家手牌、装备与判定区的可弃置牌总数。
func get_discardable_count(player_id: int) -> int:
	# 指定玩家状态；不存在时数量为0。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return player.hand.size() + player.equipment.size() + player.judgment_area.size()


## 返回玩家手牌区与装备区的牌数；装备技能的“弃置牌”费用和寒冰剑只允许操作这两个区域。
func get_hand_equipment_card_count(player_id: int) -> int:
	# 指定玩家状态；不存在时数量为0。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return player.hand.size() + player.equipment.size()


## 从玩家手牌区和装备区依次弃置至多指定数量的牌；不会错误弃置判定区中的延时锦囊。
func discard_n_from_hand_equipment(player_id: int, count: int) -> void:
	for _index: int in range(maxi(count, 0)):
		# 当前玩家状态；每次循环重新读取区域，保证装备离开效果结算后数量准确。
		var player: PlayerState = state.get_player(player_id)
		if player == null:
			return
		if not player.hand.is_empty():
			discard_card_from_hand(player_id, player.hand[0].uid)
		elif not player.equipment.is_empty():
			_discard_equipment_slot(player_id, str(player.equipment.keys()[0]), true)
		else:
			return


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
		add_log("%s将一张手牌交给了自己。" % source.display_name)
		return true
	_ensure_card_movement()
	if _move_card_with_timings(card, "hand", to_id, "give", state.current_event_id, "", [to_id]) == null:
		return false
	# 临时牌名只在实体已属于目标手牌时建立；后续离手由统一移动边界自动恢复原始定义。
	if card.definition_id != view_as_definition_id and not card.set_hand_view_as(view_as_definition_id, source_skill_id):
		return false
	add_log("%s交给了%s一张手牌。" % [source.display_name, target.display_name])
	return true


## 令指定角色从摸牌堆或弃牌堆获得最顶上的指定牌；先完整检索摸牌堆，缺失时才检索弃牌堆。
func gain_top_named_card_from_draw_or_discard(player_id: int, definition_id: String, reason: String = "gain_named_card") -> CardInstance:
	# 获得者；死亡、离场或终局后不再改变牌区。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over or definition_id.is_empty():
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


## 令指定角色从摸牌堆获得最顶上的固定牌名字数卡牌；名字统一按卡牌原版规则名计算，不受显示模式影响。
func gain_top_draw_card_by_name_length(player_id: int, name_length: int, reason: String = "gain_name_length_card") -> CardInstance:
	# 获得者；无效角色和非正名字数不会查询或移动牌堆。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over or name_length <= 0:
		return null
	# 指定实体；倒序扫描摸牌堆取得最顶上的匹配卡牌，弃牌堆不参与本接口。
	var matched_card: CardInstance
	for draw_index: int in range(state.draw_pile.size() - 1, -1, -1):
		# 当前摸牌堆候选；原版名字数匹配时即为最顶上的合法实体。
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


## 返回卡牌原版规则名的Unicode字符数；稳定规则名不会随玩家切换《崩铁杀》显示名称而改变结算。
func get_card_original_name_length(definition_id: String) -> int:
	# 卡牌静态定义；属性【杀】牌面可以显示两个字，但规则牌名始终是一个字的【杀】。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	return str(definition.get("rule_name", definition.get("original_name", ""))).length()


## 弃置目标全部装备；水淹七军、死亡与领袖惩罚可复用此操作。
func discard_all_equipment(target_id: int, trigger_loss_effects: bool = true) -> void:
	# 目标状态；复制键数组以允许循环中安全删除装备。
	var target: PlayerState = state.get_player(target_id)
	# 当前全部装备槽快照；后续删除不会影响遍历。
	var slots: Array = target.equipment.keys().duplicate()
	for slot_variant: Variant in slots:
		_discard_equipment_slot(target_id, str(slot_variant), trigger_loss_effects)


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


## 返回一名玩家普通手牌区的可选实体快照；木牛“粮”和装备牌不会混入要求弃置手牌的装备效果。
func get_hand_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	return _build_player_zone_candidates(viewer_id, target_id, true, false, false)


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
	for selected_uid: int in selected_uids:
		# 从手牌区取出实体；take_hand_card 保证不会误取装备。
		var hand_card: CardInstance = player.take_hand_card(selected_uid)
		if hand_card == null:
			continue
		_move_to_discard(hand_card)
		discarded_count += 1
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
		if player.alive and player.player_id != excluded_player_id:
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
func add_phase(player_id: int, reason: String = "") -> bool:
	# 获得额外回合的角色；失效、阵亡或离场角色不能进入后续行动队列。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive or player.out_of_game or state.game_over:
		return false
	_extra_turn_queue.append(player_id)
	add_log("%s获得了一个额外的回合%s。" % [player.display_name, "（%s）" % reason if not reason.is_empty() else ""])
	return true


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
	add_log("%s获得了一个额外的出牌阶段%s。" % [player.display_name, "（%s）" % reason if not reason.is_empty() else ""])
	return true


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
		"player_id":player_id,
		"source_id":source_id,
		"reason":reason,
		"parent_event_id":state.current_event_id,
		"completion_context":completion_context.duplicate(true),
		"status":"begin_before",
	}
	# 额外弃牌阶段前时机；取消或中立化表示本阶段未能执行，顺序效果不会伪造阶段完成。
	var phase_data: Dictionary = {"turn_number":state.turn_number, "extra_phase":true, "reason":reason}
	# 额外弃牌阶段前置事件；保留父事件关联并允许其他规则取消本次阶段插入。
	var before_event: RuleEvent = _emit_rule_timing("phaseDiscardBefore", player_id, source_id, player_id, phase_data, int(_active_extra_discard_phase.get("parent_event_id", -1)))
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		_active_extra_discard_phase.clear()
		return false
	_active_extra_discard_phase["status"] = "begin"
	# 额外弃牌阶段开始事件；其触发技能全部恢复后才进入手牌上限计算。
	var begin_event: RuleEvent = _emit_rule_timing("phaseDiscardBegin", player_id, source_id, player_id, before_event.data if before_event != null else phase_data, int(_active_extra_discard_phase.get("parent_event_id", -1)))
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		_active_extra_discard_phase.clear()
		return false
	add_log("%s开始执行额外的弃牌阶段。" % player.display_name)
	_active_extra_discard_phase["status"] = "body"
	# 阶段开始时触发的其他技能必须先完成自身连续选择，再计算本阶段的最终手牌上限。
	if has_pending_card_choice():
		return true
	_continue_active_extra_discard_phase_body()
	return true


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
		add_log("%s在额外弃牌阶段弃置了%d张手牌。" % [player.display_name, discarded_count])
	_finish_active_extra_discard_phase()


## 依次完成额外弃牌阶段的End与After；任一时机创建选择时保存状态并等待统一恢复入口继续。
func _finish_active_extra_discard_phase() -> void:
	if _active_extra_discard_phase.is_empty() or has_pending_card_choice():
		return
	# 阶段公共数据；完成时机继续标记extra_phase，其他技能可区分普通弃牌阶段与插入阶段。
	var player_id: int = int(_active_extra_discard_phase.get("player_id", -1))
	# 阶段来源角色；触发过滤中的source沿用最初创建额外阶段的效果来源。
	var source_id: int = int(_active_extra_discard_phase.get("source_id", -1))
	# 阶段父事件；伤害技能创建的额外阶段继续关联原事件链。
	var parent_event_id: int = int(_active_extra_discard_phase.get("parent_event_id", -1))
	# 阶段完成数据；所有时机共享同一数值与来源语义。
	var phase_data: Dictionary = {"turn_number":state.turn_number, "extra_phase":true, "reason":str(_active_extra_discard_phase.get("reason", ""))}
	# 阶段恢复状态；区分尚未发布结束时机与等待结束后时机恢复的路径。
	var status: String = str(_active_extra_discard_phase.get("status", "body"))
	if status not in ["finish_end", "finish_after"]:
		_active_extra_discard_phase["status"] = "finish_end"
		_emit_rule_timing("phaseDiscardEnd", player_id, source_id, player_id, phase_data, parent_event_id)
		if has_pending_card_choice():
			return
	# After时机已经发布后，恢复入口只完成阶段，不得再次触发同一时机。
	if str(_active_extra_discard_phase.get("status", "")) == "finish_after":
		_complete_active_extra_discard_phase()
		return
	_active_extra_discard_phase["status"] = "finish_after"
	_emit_rule_timing("phaseDiscardAfter", player_id, source_id, player_id, phase_data, parent_event_id)
	if has_pending_card_choice():
		return
	_complete_active_extra_discard_phase()


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
	if skill != null:
		skill.continue_extra_phase(completion_context)


## 结束当前出牌阶段；武将技能通过该公开端口实现“跳过出牌阶段”，不直接调用控制器私有流程。
func end_current_play_phase(player_id: int) -> bool:
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return false
	_cancel_active_play_choice("skill_ended_play_phase")
	_end_play_phase(player_id)
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


## 在整牌准备选择完成后恢复兼容逐目标游标；真实事件树由父事件自然恢复，不主动重复推进。
func continue_card_after_preparation(parent_card_uid: int) -> void:
	# 当前使用牌生命周期；runtime_managed 表示真实 CardUseEvent 正在负责后续步骤。
	var card_use_context: Dictionary = _card_use_contexts.get(parent_card_uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(parent_card_uid)


## 按稳定 UID 弃置玩家手牌区或装备区中被明确选择的牌；不存在或已移动的 UID 会安全跳过。
func discard_selected_hand_equipment(player_id: int, selected_uids: Array[int]) -> int:
	# 实际弃置数量；调用方据此判断装备费用是否完整支付。
	var discarded_count: int = 0
	for selected_uid: int in selected_uids:
		if _discard_selected_player_card(player_id, selected_uid):
			discarded_count += 1
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
	if from_player == null or to_player == null or not from_player.equipment.has(slot) or attachment_zone.is_empty():
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
func _create_players(player_count: int) -> void:
	# 本局模式；决定身份表是否洗牌以及开局公开身份规则。
	var match_mode: String = identity_rules.normalize_mode(str(state.match_mode))
	# 身份配置副本；身份局整表洗牌，斗地主按座次固定（一号位地主，六人时三号位亦为地主）。
	var identities: Array[String] = identity_rules.get_distribution(player_count, match_mode)
	if match_mode != IdentityRules.MODE_DOUDIZHU:
		_shuffle_array(identities)
	# 局域网真人玩家 ID；房主大厅已按位置顺序绑定成员，离线模式保持只有 local_human_player_id 一名真人。
	var lan_human_player_ids: Array[int] = []
	if network_gateway != null and network_gateway.is_lan_host():
		lan_human_player_ids = network_gateway.get_lan_human_player_ids()
	for index: int in range(player_count):
		# 新建玩家状态；显示名保持稳定座次便于日志辨认。
		# 内置 AI 名称带有明确前缀，真实玩家保持“玩家X”；选将完成旋转座次后会按最终座次再次统一刷新。
		var is_human_player: bool = lan_human_player_ids.has(index) if not lan_human_player_ids.is_empty() else index == local_human_player_id
		# 当前玩家显示名；局域网真人沿用大厅昵称，离线真人与 AI 继续使用原有稳定座次名称。
		var default_player_name: String = network_gateway.get_lan_player_display_name(index) if not lan_human_player_ids.is_empty() and is_human_player else ("玩家%d" % (index + 1) if is_human_player else "[AI]玩家%d" % (index + 1))
		# 当前新建玩家状态；稳定玩家 ID 使用原始创建索引，显示名使用本轮默认座次名称。
		var player: PlayerState = PlayerState.new(index, default_player_name)
		# 当前座次身份；身份局已洗牌，斗地主按固定座次表赋值。
		player.identity = identities[index]
		player.identity_revealed = identity_rules.is_identity_public_at_start(player.identity, match_mode)
		player.character_id = ""
		player.character_revealed = false
		state.players.append(player)
		if not is_human_player:
			ai_coordinator.register_basic_ai(index)
	state.random_history.append({"kind":"identity_distribution", "mode":match_mode, "identities":identities.duplicate(), "local_human_player_id":local_human_player_id, "human_player_ids":lan_human_player_ids.duplicate() if not lan_human_player_ids.is_empty() else [local_human_player_id]})


## 把已确认武将应用到玩家状态；体力上限只在该入口初始化，避免界面与选将服务重复写数值。
func _apply_character(player: PlayerState, character_id: String, reveal_character: bool) -> void:
	if player == null:
		return
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
	player.hp = player.max_hp
	# 初始护盾值；选将应用角色时统一归零，后续只能通过护盾规则端口获得。
	player.shield = 0


## 返回指定玩家当前持有的技能实例；空结果表示玩家未选择武将、未配置该技能或对局尚未完成技能安装。
func get_skill_instance(player_id: int, skill_id: String) -> SkillDefinition:
	# 玩家技能实例表；键为稳定技能 ID，值为仅属于该玩家的运行时对象。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	return player_skills.get(skill_id) as SkillDefinition


## 汇总指定玩家全部已安装技能的次数解除钩子；技能只读取卡牌定义，不修改使用历史。
func skill_ignores_play_count_limit(player_id: int, card_definition: Dictionary) -> bool:
	# 当前玩家技能实例表；临时技能与武将固有技能共用同一容器，因此会自然参与查询。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；任一技能明确解除限制即可通过，不要求其他技能重复确认。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill != null and skill.ignores_play_count_limit(card_definition):
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
		if skill != null:
			total_bonus += maxi(skill.get_play_count_limit_bonus(card_definition), 0)
	return total_bonus


## 汇总指定玩家全部已安装技能的目标附加限制；首个非空错误会阻止目标进入使用指令。
func validate_skill_card_target_selection(player_id: int, card_definition: Dictionary, target_id: int, all_target_ids: Array[int]) -> String:
	# 当前玩家技能实例表；技能顺序与武将技能栏及临时技能安装顺序一致，保证拒绝原因稳定。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；目标校验必须保持纯查询，不能在此消费技能次数或牌。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null:
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
		if skill == null:
			continue
		var validation_error: String = skill.validate_incoming_card_target_selection(actor_id, card_definition, card_color)
		if not validation_error.is_empty():
			return validation_error
	return ""


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
	if skill == null:
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
		if skill == null or not skill.supports_active_entry(active_entry):
			continue
		# 技能查询上下文；补充主动入口但不覆盖调用方其他可序列化参数。
		var activation_context: Dictionary = context.duplicate(true)
		activation_context["active_entry"] = active_entry
		if skill.can_activate(activation_context):
			result.append(skill.get_id())
	return result


## 返回主动技能的只读交互预览；界面与 AI 可查询，但所有提交仍由技能 can_activate 与 activate 权威复核。
func get_skill_activation_preview(player_id: int, skill_id: String, context: Dictionary = {}) -> Dictionary:
	# 当前技能实例；未安装技能没有预览内容。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null:
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
	state.action_sequence += 1
	_emit_rule_timing("useSkillAfter", player_id, player_id, -1, timing_data)
	_emit_rule_timing("skillAfter", player_id, player_id, -1, timing_data)
	_dispatch_rule_event(RuleEvent.new("skill_used", player_id, -1, {"skill_id":skill_id, "context":context.duplicate(true)}))
	_emit_state()
	return true


## 写入一条实际成立的技能发动记录，并通知对局日志与桌面表现；内容技能只能通过本公开端口调用，不能直接改写历史数组。
func record_skill_activation(player_id: int, skill_id: String, context: Dictionary = {}) -> void:
	if state == null or state.game_over:
		return
	# 发动者状态；未知、死亡或离场角色不能留下新的有效技能发动记录。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return
	# 技能元数据；名称缺失时回退稳定 ID，保证日志与动画仍能定位来源。
	var skill_metadata: Dictionary = GameDatabase.get_skill(skill_id)
	var skill_name: String = str(skill_metadata.get("name", skill_id))
	# 永久历史条目；保存技能、触发事件、回合与内容上下文，供回放和未来统计读取。
	player.skill_history.append({"skill_id":skill_id, "skill_name":skill_name, "event_id":state.current_event_id, "turn_number":state.turn_number, "context":context.duplicate(true)})
	add_log("%s发动了【%s】。" % [player.display_name, skill_name])
	# 技能表现上下文副本；目标线等客户端表现只读取已经确认的稳定目标字段，不能持有或改写规则历史原字典。
	var presentation_context: Dictionary = context.duplicate(true)
	skill_activated.emit(player_id, skill_name, presentation_context)


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


## 完成其他玩家同时选将、统一亮将、发4张起始手牌并由领袖开始首回合。
func _finish_character_selection() -> void:
	if not character_selection.custom_assignment_enabled:
		for player: PlayerState in state.players:
			if player.player_id != character_selection.leader_player_id:
				_apply_character(player, character_selection.get_selection(player.player_id), true)
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
	for player: PlayerState in state.players:
		if assignments_by_player.has(player.player_id) or available_seats.is_empty() or available_identities.is_empty():
			continue
		var preferred_seat_number: int = character_selection.get_initial_seat_number(player.player_id)
		var remaining_seat_number: int = preferred_seat_number if available_seats.has(preferred_seat_number) else available_seats[0]
		var preferred_identity: String = character_selection.get_initial_identity(player.player_id)
		var remaining_identity: String = preferred_identity if available_identities.has(preferred_identity) else str(available_identities[0])
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
	var preview_leader_before_clear: PlayerState = state.players[0] if not state.players.is_empty() else null
	for player: PlayerState in state.players:
		# 保留条件；只有同一名首任领袖仍是当前预览领袖且尚未提交最终新武将时，才沿用其已经公开的牌面。
		var preserves_initial_leader_character: bool = player == preview_leader_before_clear and player.player_id == character_selection.leader_player_id and player.identity == character_selection.get_first_seat_identity() and not player.character_id.is_empty()
		if character_selection.get_selection(player.player_id).is_empty() and not preserves_initial_leader_character:
			_clear_pre_game_character_preview(player)
	# 当前预览领袖；只在领袖由AI控制且尚未最终确认时公开其重新选择的一张候选，保持首任领袖流程的唯一公开牌语义。
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
	for character_id_variant: Variant in GameDatabase.characters.keys():
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
	var available_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		available_character_ids.append(str(character_id_variant))
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
		for player: PlayerState in state.players:
			draw(player.player_id, starting_hand_count, false)
		var game_draw_result_data: Dictionary = {"cards_per_player":starting_hand_count, "player_count":state.players.size()}
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
	_record_runtime_event("phaseLoop", "phase_loop", {"first_player_id":character_selection.leader_player_id})
	# 首回合玩家状态；领袖固定为一号位且不受本地玩家稳定 ID 影响。
	var first_turn_player: PlayerState = _find_player_by_identity(identity_rules.get_first_player_identity(str(state.match_mode)))
	if first_turn_player == null:
		push_error("标准身份局缺少领袖，无法开始首回合。")
		return
	if _starting_cards_were_dealt:
		add_log("对局开始：%d名玩家，牌堆%d张，每名玩家起始手牌%d张。" % [state.players.size(), state.draw_pile.size(), _starting_hand_count])
	else:
		add_log("对局开始：%d名玩家，起始手牌分发被规则取消。" % state.players.size())
	# 首回合可能在roundStart立即创建技能询问；开始回合前必须先同步最终座次与起始手牌，保证本地内联候选已经存在于牌桌快照中。
	_emit_state()
	_start_turn(first_turn_player.player_id)


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
	add_log("%s使用手气卡刷新了起始手牌。" % state.get_player(action.actor_id).display_name)
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


## 以领袖为数组首位旋转玩家，保留稳定 player_id 供网络、回放和实体牌所有权使用。
func _reorder_players_from_leader() -> void:
	# 首任公开身份；身份局为领袖，斗地主为地主（固定一号位时索引通常已为0）。
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
		if network_gateway != null and network_gateway.is_lan_host() and network_gateway.get_lan_human_player_ids().has(seated_player.player_id):
			seated_player.display_name = network_gateway.get_lan_player_display_name(seated_player.player_id)
		else:
			seated_player.display_name = ("[AI]玩家%d" if ai_coordinator.is_ai_controlled(seated_player.player_id) else "玩家%d") % (seat_index + 1)


## 按当前玩家数组顺序刷新座次显示名；自选座次已经完成排序时不再旋转数组。
func _refresh_player_display_names_for_current_seats() -> void:
	for seat_index: int in range(state.players.size()):
		# 当前座次玩家；局域网真人沿用大厅名称，离线真人与 AI 使用最终座次编号。
		var seated_player: PlayerState = state.players[seat_index]
		if network_gateway != null and network_gateway.is_lan_host() and network_gateway.get_lan_human_player_ids().has(seated_player.player_id):
			seated_player.display_name = network_gateway.get_lan_player_display_name(seated_player.player_id)
		else:
			seated_player.display_name = ("[AI]玩家%d" if ai_coordinator.is_ai_controlled(seated_player.player_id) else "玩家%d") % (seat_index + 1)


## 让内置 AI 在当前选将阶段从自己的候选中确认首张；所有 AI 仍通过同一 select_character 校验入口。
func _drive_ai_character_selection() -> void:
	if is_gameplay_paused() or _is_driving_character_selection or character_selection == null or character_selection.phase == CharacterSelectionService.PHASE_COMPLETE:
		return
	# 自选模式优先等待全部真人确认，避免 AI 抢占真人希望选择的座次与身份名额。
	if character_selection.phase == CharacterSelectionService.PHASE_CUSTOM:
		for pending_player_id: int in character_selection.get_pending_player_ids():
			if not ai_coordinator.is_ai_controlled(pending_player_id):
				return
	_is_driving_character_selection = true
	while character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		# 自选阶段每轮都重新检查真人完成状态；首任领袖由 AI 确认后可能在同一循环内刚进入该阶段。
		if character_selection.phase == CharacterSelectionService.PHASE_CUSTOM:
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
			# 当前 AI 是否必须同时提交座次身份；首任AI领袖先亮将并等待真人选完名额，进入最终自选后再完成自身分配。
			var requires_custom_assignment: bool = character_selection.custom_assignment_enabled and character_selection.phase == CharacterSelectionService.PHASE_CUSTOM
			if requires_custom_assignment:
				# 当前剩余座次与身份；优先把一号位和领袖绑定给同一 AI，其余角色只选择非一号位与非领袖身份。
				var available_seats: Array[int] = character_selection.get_available_seat_numbers(player_id)
				var available_identities: Array[String] = character_selection.get_available_identities(player_id)
				var selected_seat_number: int = -1
				var selected_identity: String = ""
				var first_seat_identity: String = character_selection.get_first_seat_identity()
				if available_seats.has(1) and available_identities.has(first_seat_identity):
					selected_seat_number = 1
					selected_identity = first_seat_identity
				else:
					available_seats.erase(1)
					available_identities.erase(first_seat_identity)
					if not available_seats.is_empty() and not available_identities.is_empty():
						selected_seat_number = available_seats[0]
						selected_identity = available_identities[0]
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
	_emit_state()
	# 校验后的阶段回调；节奏组件不持有规则状态，只在到期后把控制权交还给控制器。
	var guarded_callback: Callable = Callable(self, "_execute_scheduled_phase_transition").bind(expected_match_id, player_id, expected_phase, callback)
	if game_flow_pacer == null:
		guarded_callback.call()
		return
	game_flow_pacer.schedule("phase_transition", game_flow_interval_seconds, guarded_callback)


## 执行到期的阶段切换；任何终局、重开、角色变化或阶段变化都会让旧回调静默失效。
func _execute_scheduled_phase_transition(expected_match_id: String, player_id: int, expected_phase: String, callback: Callable) -> void:
	if state == null or state.game_over or state.match_id != expected_match_id:
		return
	if state.current_player_id != player_id or state.current_phase != expected_phase:
		return
	if callback.is_valid():
		callback.call()


## 开始指定玩家的回合，完成开始阶段后通过节奏组件进入判定阶段。
func _start_turn(player_id: int) -> void:
	if state.game_over:
		return
	# 上一回合残留的出牌选择；必须先从真实事件栈移除，新的阶段与 CardUseEvent 才能进入根事件。
	_cancel_active_play_choice("turn_changed")
	_started_phase_lifecycles.clear()
	# 新回合玩家状态；死亡玩家会由调用方提前跳过。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	_ai_drive_token += 1
	_ai_actions_this_turn = 0
	_judgment_flow_token += 1
	_judgment_flow_in_progress = false
	_judgment_resume_needs_result_pause = false
	state.current_player_id = player_id
	state.turn_number += 1
	# 本回合是否开启新轮；保存为基础布尔值后交给分段续接，等待选择期间不再依赖可能变化的数组位置。
	var starts_new_round: bool = state.players.find(player) == 0
	if starts_new_round:
		state.round_number += 1
	_continue_turn_start({"stage":"round_start", "player_id":player_id, "starts_new_round":starts_new_round})


## 按稳定阶段游标发布回合开始与准备阶段时机；任一时机插入选择后先保存直接后续，恢复时不会越过或重复发布其他时机。
func _continue_turn_start(context: Dictionary) -> void:
	if state == null or state.game_over:
		return
	# 新回合玩家稳定 ID；等待期间角色可能死亡或离场，每个步骤开始前都按编号重新校验。
	var player_id: int = int(context.get("player_id", -1))
	# 新回合玩家状态；无效或死亡角色不会继续获得准备阶段及后续行动窗口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or state.current_player_id != player_id:
		return
	# 当前回合开始游标；每次发布时机前先读取，发布后立即写入下一步以保证恢复幂等。
	var stage: String = str(context.get("stage", "round_start"))
	while state != null and not state.game_over:
		if stage == "round_start":
			context["stage"] = "initialize"
			if bool(context.get("starts_new_round", false)):
				_expire_temporary_skills_for_round(state.round_number)
				_emit_rule_timing("roundStart", player_id, player_id, player_id, {"round_number":state.round_number})
				if _has_nested_settlement_barrier():
					_defer_rule_continuation("turn_start", context)
					return
			stage = "initialize"
			continue
		if stage == "initialize":
			# 当前回合运行时事件 ID；只在轮开始触发全部完成后创建一次，后续所有阶段时机共享该父事件。
			var turn_event_id: int = _record_runtime_event("phase", "turn", {"player_id":player_id, "turn_number":state.turn_number, "round_number":state.round_number})
			context["turn_event_id"] = turn_event_id
			_current_turn_event_id = turn_event_id
			# 全局回合用牌事实；每个新回合清空全部角色记录，供“本回合内其使用过某牌”的跨角色技能精确查询。
			_cards_used_this_turn_by_player.clear()
			player.skipped_phases.clear()
			player.card_use_history.clear()
			player.response_history.clear()
			player.damage_history.clear()
			player.skill_history.clear()
			player.ai_failed_card_target_ids.clear()
			_notify_card_definitions_turn_started(player_id)
			player.turn_history.append({"turn_number":state.turn_number, "round_number":state.round_number, "event_id":turn_event_id, "skipped_phases":[]})
			state.current_phase = "start"
			state.phase_index = 0
			context["stage"] = "phase_before"
			stage = "phase_before"
			continue
		# 当前回合父事件 ID；initialize 之后固定存在，异常旧上下文回退到控制器当前记录。
		var turn_event_id: int = int(context.get("turn_event_id", _current_turn_event_id))
		if stage == "phase_before":
			_record_runtime_event("phaseBefore", "phase", {"player_id":player_id}, {}, turn_event_id)
			# 回合前事件结果；取消或中立化时只进入取消分支，不再发布本回合后续开始时机。
			var phase_before_event: RuleEvent = _emit_rule_timing("phaseBefore", player_id, player_id, player_id, {"turn_number":state.turn_number, "round_number":state.round_number}, turn_event_id)
			context["stage"] = "phase_cancelled" if phase_before_event != null and (phase_before_event.cancelled or phase_before_event.neutralized) else "phase_before_start"
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = str(context["stage"])
			continue
		if stage == "phase_cancelled":
			context["stage"] = "finish_cancelled"
			_emit_rule_timing("phaseCancelled", player_id, player_id, player_id, {"reason":"phaseBefore", "turn_number":state.turn_number}, turn_event_id)
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = "finish_cancelled"
			continue
		if stage == "finish_cancelled":
			_finish_turn(player_id)
			return
		if stage == "phase_before_start":
			context["stage"] = "phase_before_end"
			_emit_rule_timing("phaseBeforeStart", player_id, player_id, player_id, {"turn_number":state.turn_number}, turn_event_id)
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = "phase_before_end"
			continue
		if stage == "phase_before_end":
			context["stage"] = "phase_begin_start"
			_emit_rule_timing("phaseBeforeEnd", player_id, player_id, player_id, {"turn_number":state.turn_number}, turn_event_id)
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = "phase_begin_start"
			continue
		if stage == "phase_begin_start":
			context["stage"] = "phase_begin"
			_emit_rule_timing("phaseBeginStart", player_id, player_id, player_id, {"turn_number":state.turn_number}, turn_event_id)
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = "phase_begin"
			continue
		if stage == "phase_begin":
			_record_runtime_event("phaseBegin", "phase", {"player_id":player_id}, {}, turn_event_id)
			context["stage"] = "preparation_begin"
			_emit_rule_timing("phaseBegin", player_id, player_id, player_id, {"turn_number":state.turn_number}, turn_event_id)
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = "preparation_begin"
			continue
		if stage == "preparation_begin":
			_record_runtime_event("phaseZhunbei", "phase", {"player_id":player_id}, {}, turn_event_id)
			# 准备阶段是否成功进入；取消时机仍会发布公开取消事件，随后统一进入准备阶段收尾入口。
			var preparation_started: bool = _begin_phase_lifecycle("phaseZhunbei", player_id, {"turn_number":state.turn_number}, turn_event_id)
			if not preparation_started:
				_emit_rule_timing("phaseZhunbeiCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number}, turn_event_id)
			context["stage"] = "preparation_complete"
			# 准备阶段Begin中的技能可创建异步选择；等待提交时不能继续安排以start为前提的旧阶段切换。
			if _has_nested_settlement_barrier():
				_defer_rule_continuation("turn_start", context)
				return
			stage = "preparation_complete"
			continue
		if stage == "preparation_complete":
			_continue_turn_after_preparation_phase(player_id)
			return
		return


## 完成准备阶段主体并安排判定阶段；选择窗口恢复后可再次调用，已完成主体不会重复派发开始事件。
func _continue_turn_after_preparation_phase(player_id: int) -> void:
	if state == null or state.game_over or has_pending_card_choice() or state.current_player_id != player_id or state.current_phase != "start":
		return
	# 当前准备阶段生命周期键；仍存在时说明本次调用需要执行阶段主体，已被结束时机移除时只续接后续阶段。
	var lifecycle_key: String = "%d:%s" % [player_id, "phaseZhunbei"]
	# 当前回合玩家；准备阶段选择等待期间可能已经死亡或离场，继续前必须重新读取状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	if _is_phase_lifecycle_body_active("phaseZhunbei", player_id):
		add_log("第%d回合：%s的回合开始。" % [state.turn_number, player.display_name])
		_dispatch_rule_event(RuleEvent.new("phase_start", player_id, player_id, {}))
	if _started_phase_lifecycles.has(lifecycle_key):
		_finish_phase_lifecycle("phaseZhunbei", player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		# 准备阶段End或After也可创建选择；此时生命周期已经完成，恢复后只安排判定阶段。
		if has_pending_card_choice():
			return
	if state.game_over:
		return
	if not player.alive:
		_advance_after_current_player_death(player_id)
		return
	if player.face_down:
		turn_over_player(player_id, player_id, "turn_start_skip")
		add_log("%s翻回正面并跳过本回合。" % player.display_name)
		_emit_rule_timing("phaseCancelled", player_id, player_id, player_id, {"reason":"face_down", "turn_number":state.turn_number}, _current_turn_event_id)
		_emit_rule_timing("phaseOver", player_id, player_id, player_id, {"reason":"face_down", "turn_number":state.turn_number}, _current_turn_event_id)
		_finish_turn(player_id)
		return
	_schedule_phase_transition(player_id, "start", Callable(self, "_enter_judgment_phase").bind(player_id))


## 进入当前角色的判定阶段；阶段主体可能被无懈、濒死或其他统一选择请求异步暂停。
func _enter_judgment_phase(player_id: int) -> void:
	# 当前回合玩家；阶段间隔期间死亡或离场时不再建立判定阶段。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	_emit_rule_timing("phaseChange", player_id, player_id, player_id, {"from_phase":"start", "to_phase":"judgment"}, _current_turn_event_id)
	state.current_phase = "judgment"
	state.phase_index = 1
	_record_runtime_event("phaseJudgeStage", "phase", {"player_id":player_id}, {}, _current_turn_event_id)
	if bool(player.skipped_phases.get("judgment", false)):
		_emit_rule_timing("phaseJudgeSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		_continue_turn_after_judgment(player_id)
		return
	if not _begin_phase_lifecycle("phaseJudge", player_id, {"turn_number":state.turn_number}, _current_turn_event_id):
		_emit_rule_timing("phaseJudgeCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		_continue_turn_after_judgment(player_id)
		return
	_process_judgment_area(player_id)


## 从判定阶段结束处继续当前回合；异步无懈与濒死选择完成后也统一回到该入口。
func _continue_turn_after_judgment(player_id: int) -> void:
	if state == null or state.game_over or has_pending_card_choice() or state.current_player_id != player_id or state.current_phase != "judgment":
		return
	# 当前回合玩家；判定伤害可能使其死亡，必须在摸牌前重新读取存活状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	_finish_phase_lifecycle("phaseJudge", player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	if has_pending_card_choice():
		return
	_schedule_phase_transition(player_id, "judgment", Callable(self, "_enter_draw_phase").bind(player_id))


## 进入摸牌阶段并完成本阶段主体；结算结束后保留当前画面，再按游戏速度进入出牌阶段。
func _enter_draw_phase(player_id: int) -> void:
	# 当前回合玩家；判定与阶段间隔期间都可能死亡，摸牌前必须重新读取存活状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	_emit_rule_timing("phaseChange", player_id, player_id, player_id, {"from_phase":"judgment", "to_phase":"draw"}, _current_turn_event_id)
	state.current_phase = "draw"
	state.phase_index = 2
	_record_runtime_event("phaseDraw", "phase", {"player_id":player_id, "base_draw_count":2}, {}, _current_turn_event_id)
	if bool(player.skipped_phases.get("draw", false)):
		add_log("%s跳过摸牌阶段。" % player.display_name)
		_emit_rule_timing("phaseDrawSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	elif _begin_phase_lifecycle("phaseDraw", player_id, {"draw_count":2, "turn_number":state.turn_number}, _current_turn_event_id):
		# 两个摸牌数量修改窗口严格按序执行；第二窗口结果作为实际基础摸牌数传入通用 draw 生命周期。
		var draw_one_event: RuleEvent = _emit_rule_timing("phaseDrawBegin1", player_id, player_id, player_id, {"draw_count":2, "turn_number":state.turn_number}, _current_turn_event_id)
		var draw_count: int = maxi(int(draw_one_event.data.get("draw_count", 2)) if draw_one_event != null else 2, 0)
		var draw_two_event: RuleEvent = _emit_rule_timing("phaseDrawBegin2", player_id, player_id, player_id, {"draw_count":draw_count, "turn_number":state.turn_number}, _current_turn_event_id)
		draw_count = maxi(int(draw_two_event.data.get("draw_count", draw_count)) if draw_two_event != null else draw_count, 0)
		draw(player_id, draw_count)
		_finish_phase_lifecycle("phaseDraw", player_id, {"draw_count":draw_count, "turn_number":state.turn_number}, _current_turn_event_id)
	else:
		_emit_rule_timing("phaseDrawCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	if state.game_over:
		return
	if not player.alive:
		_advance_after_current_player_death(player_id)
		return
	_schedule_phase_transition(player_id, "draw", Callable(self, "_enter_play_phase").bind(player_id))


## 进入出牌阶段并创建统一 chooseToUse 请求；普通阶段与额外阶段分别维护独立次数历史。
func _enter_play_phase(player_id: int) -> void:
	# 当前回合玩家；流程间隔到期时再次校验，避免已离场角色获得可操作窗口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	_emit_rule_timing("phaseChange", player_id, player_id, player_id, {"from_phase":"draw", "to_phase":"play"}, _current_turn_event_id)
	state.current_phase = "play"
	state.phase_index = 3
	# 普通出牌阶段拥有独立次数历史；本回合此前由其他流程记录的牌不会占用本阶段【杀】次数。
	player.play_phase_card_use_history.clear()
	_record_runtime_event("phaseUse", "phase", {"player_id":player_id}, {}, _current_turn_event_id)
	if bool(player.skipped_phases.get("play", false)):
		add_log("%s跳过出牌阶段。" % player.display_name)
		_emit_rule_timing("phaseUseSkipped", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		_end_play_phase(player_id, false, true)
		return
	if not _begin_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number}, _current_turn_event_id):
		_emit_rule_timing("phaseUseCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		_end_play_phase(player_id, false)
		return
	# phaseUseBegin中的技能选择必须先完整恢复；普通chooseToUse只能在Begin触发链完全结束后创建。
	if has_pending_card_choice():
		return
	_begin_play_choice(player_id)
	_emit_state()
	if ai_coordinator.is_ai_controlled(player_id):
		_schedule_ai_action()


## 在延迟选择完成后恢复被暂停的回合阶段；当前仅判定阶段允许在阶段主体中插入异步选择。
func _resume_interrupted_turn_flow() -> void:
	if state == null or state.game_over or has_pending_card_choice():
		return
	# 额外弃牌阶段是独立的嵌套阶段；其Begin、End或After时机被选择暂停后必须优先恢复。
	if not _active_extra_discard_phase.is_empty():
		# 当前额外弃牌阶段状态；body重新计算弃牌，完成状态则续接End、After或技能回调。
		var extra_discard_status: String = str(_active_extra_discard_phase.get("status", "body"))
		if extra_discard_status == "body":
			_continue_active_extra_discard_phase_body()
		elif extra_discard_status in ["finish_end", "finish_after"]:
			_finish_active_extra_discard_phase()
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
	if current_player != null and not current_player.alive:
		_advance_after_current_player_death(current_player.player_id)
		return
	if state.current_phase == "start":
		_continue_turn_after_preparation_phase(state.current_player_id)
		return
	if state.current_phase == "play":
		# phaseUseEnd或After选择恢复时继续阶段结束游标；未登记生命周期的独立规则结算按仍在出牌阶段处理，不能误推进整回合。
		if _started_phase_lifecycles.has("%d:phaseUse" % state.current_player_id) and not _is_phase_lifecycle_body_active("phaseUse", state.current_player_id):
			_end_play_phase(state.current_player_id)
		# phaseUseBegin或阶段主体内的选择由提交入口在父事件排空后重建chooseToUse；此处提前登记会把未发布请求留在运行时栈内。
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
	if state == null or state.game_over or skill_owner_id < 0 or skill_id.is_empty() or get_skill_instance(skill_owner_id, skill_id) == null:
		return false
	_deferred_skill_settlements.append({"skill_owner_id":skill_owner_id, "skill_id":skill_id, "context":context.duplicate(true)})
	return true


## 在没有活动选择时依次恢复技能结算；恢复函数再次创建选择时立即停下，下一次提交后继续同一队列。
## 每次只恢复一项并保留原登记顺序；统一结算管线会在两项之间重新处理新触发、装备事件与规则续接。
func _resume_deferred_skill_settlements() -> void:
	if state == null or state.game_over or has_pending_card_choice() or _deferred_skill_settlements.is_empty():
		return
	# 当前结算项；先移出队列，技能需要再次等待时会显式登记新的后续上下文。
	# 当前最早登记的技能后续；同层技能的“然后”效果保持原有先到先结算规则。
	var settlement: Dictionary = _deferred_skill_settlements.pop_front() as Dictionary
	# 技能持有者与稳定ID；等待期间失去技能时安全跳过旧结算，不调用失效对象。
	var skill_owner_id: int = int(settlement.get("skill_owner_id", -1))
	# 当前技能实例；每局每名角色唯一，重新开局已清空整个结算队列。
	var skill: SkillDefinition = get_skill_instance(skill_owner_id, str(settlement.get("skill_id", "")))
	if skill != null:
		skill.continue_settlement((settlement.get("context", {}) as Dictionary).duplicate(true))


## 登记被嵌套选择中断的通用规则后半段；上下文必须只包含基础值、数组和字典。
func _defer_rule_continuation(continuation_type: String, context: Dictionary) -> int:
	return _rule_continuations.push(continuation_type, context)


## 供【杀】共享组件登记武器效果后的稳定恢复阶段；具体装备只声明阶段，不直接访问通用续接栈。
func defer_slash_continuation(resume_stage: String, context: Dictionary) -> bool:
	if resume_stage not in ["after_weapon_targeted", "after_weapon_dodged"]:
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


## 返回当前结算是否存在必须优先完成的选择或装备触发；父响应读取结果前必须等待该屏障清空。
func _has_nested_settlement_barrier() -> bool:
	return has_pending_card_choice() or not _queued_equipment_triggers.is_empty()


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
	match continuation_type:
		"skill_response":
			_continue_skill_response_after_barrier(context)
		"card_response":
			_continue_card_response_after_barrier(context)
		"equipment_response":
			_continue_equipment_response_after_barrier(context)
		"dying_response":
			_continue_dying_response_after_barrier(context)
		"dying_after_response":
			_continue_dying_after_applied_response(context)
		"trick_negation_response":
			_continue_trick_negation_after_barrier(context)
		"simultaneous_negation_response":
			_continue_simultaneous_negation_after_barrier(context)
		"damage_finalization":
			_finish_damage_timing(context)
		"damage_after_result":
			_continue_damage_after_result(context)
		"turn_start":
			_continue_turn_start(context)
		"slash_flow":
			_continue_slash_flow_after_barrier(context)
		"recast_draw":
			draw(int(context.get("player_id", -1)), 1)
		"target_card_completion":
			_complete_active_card_target(int(context.get("parent_card_uid", -1)))


## 按触发、装备、规则后半段、技能后续的固定优先级排空当前结算，最后才恢复阶段或父牌游标。
func _resume_settlement_pipeline() -> void:
	if state == null or state.game_over or has_pending_card_choice():
		return
	# 单次恢复保护计数；正常每轮都会移除至少一条队列记录，达到检查器上限时延后一帧继续而不推进父流程。
	var settlement_step_count: int = 0
	while state != null and not state.game_over and not has_pending_card_choice() and settlement_step_count < max_settlement_steps_per_pass:
		settlement_step_count += 1
		# 同一规则时机尚未询问的技能必须先完成，不能让原操作的后半段越过触发顺序。
		_resume_deferred_rule_timing_dispatches()
		if has_pending_card_choice() or state.game_over:
			return
		# 响应完成后登记的装备触发属于响应子事件，优先于读取响应结果的父卡牌或濒死流程。
		if not _queued_equipment_triggers.is_empty():
			process_next_equipment_trigger()
			if has_pending_card_choice() or state.game_over:
				return
			continue
		# 通用规则续接使用统一后进先出栈，确保最内层被中断操作先恢复。
		if _rule_continuations.has_pending():
			_resume_next_rule_continuation()
			continue
		# 技能自行声明的“然后”步骤保持登记顺序，每项之后重新检查触发、装备与通用规则续接。
		if not _deferred_skill_settlements.is_empty():
			_resume_deferred_skill_settlements()
			continue
		break
	# 达到单帧保护上限时仍有明确队列，下一帧只继续同一管线；未完成后续绝不交给阶段游标或父牌兼容入口。
	if settlement_step_count >= max_settlement_steps_per_pass and (not _queued_equipment_triggers.is_empty() or _rule_continuations.has_pending() or not _deferred_skill_settlements.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())):
		call_deferred("_resume_settlement_pipeline")
		return
	if state != null and not state.game_over and not has_pending_card_choice():
		_resume_interrupted_turn_flow()


## 派发一个标准阶段的 Before 与 Begin；任一时机取消或中立化时返回 false，由调用方决定跳过或终止阶段。
func _begin_phase_lifecycle(base_name: String, player_id: int, event_data: Dictionary, parent_event_id: int) -> bool:
	# 阶段生命周期键；同一玩家同名阶段在一个回合内只会存在一条活动记录。
	var lifecycle_key: String = "%d:%s" % [player_id, base_name]
	# 当前阶段数据；Before 的修改会传给 Begin，但不会反向污染调用方原字典。
	var current_event_data: Dictionary = event_data.duplicate(true)
	_started_phase_lifecycles.erase(lifecycle_key)
	var before_name: String = "%sBefore" % base_name
	if RuleTimingCatalog.has_timing(before_name):
		var before_event: RuleEvent = _emit_rule_timing(before_name, player_id, player_id, player_id, current_event_data, parent_event_id)
		if before_event != null and (before_event.cancelled or before_event.neutralized):
			return false
		if before_event != null:
			current_event_data = before_event.data.duplicate(true)
	var begin_name: String = "%sBegin" % base_name
	if RuleTimingCatalog.has_timing(begin_name):
		var begin_event: RuleEvent = _emit_rule_timing(begin_name, player_id, player_id, player_id, current_event_data, parent_event_id)
		if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
			return false
	# 活动生命周期上下文；status=body表示Before与Begin已经完成，阶段主体尚可执行，后续End/After会原地推进状态。
	_started_phase_lifecycles[lifecycle_key] = {"status":"body", "event_data":current_event_data.duplicate(true), "parent_event_id":parent_event_id}
	return true


## 派发一个标准阶段的 End 与 After；目录没有对应后缀时自动跳过，不为引擎未定义的时机造名。
func _finish_phase_lifecycle(base_name: String, player_id: int, event_data: Dictionary, parent_event_id: int) -> void:
	# 阶段生命周期键；未成功进入 Begin 的跳过或取消阶段不产生 End 与 After。
	var lifecycle_key: String = "%d:%s" % [player_id, base_name]
	if not _started_phase_lifecycles.has(lifecycle_key):
		return
	# 阶段恢复上下文；兼容旧测试直接写入true的状态，并以本次调用数据补齐永久可序列化字段。
	var lifecycle_variant: Variant = _started_phase_lifecycles.get(lifecycle_key, {})
	# 当前生命周期字典；旧布尔状态不参与强制类型转换，避免迁移期规则测试产生空对象访问。
	var lifecycle_context: Dictionary = lifecycle_variant as Dictionary if lifecycle_variant is Dictionary else {}
	if lifecycle_context.is_empty():
		lifecycle_context = {"status":"body", "event_data":event_data.duplicate(true), "parent_event_id":parent_event_id}
	# 完成时机数据；首次结束时保存，选择恢复后的后续调用继续使用同一份稳定数据。
	var completion_data: Dictionary = (lifecycle_context.get("event_data", event_data) as Dictionary).duplicate(true)
	# 完成时机父事件；恢复期间当前事件摘要可能变化，因此沿用首次保存的父事件。
	var completion_parent_event_id: int = int(lifecycle_context.get("parent_event_id", parent_event_id))
	# 当前完成游标；body尚未派发End，end_emitted等待After，after_emitted只需移除生命周期。
	var status: String = str(lifecycle_context.get("status", "body"))
	var end_name: String = "%sEnd" % base_name
	if status == "body":
		lifecycle_context["status"] = "end_emitted"
		_started_phase_lifecycles[lifecycle_key] = lifecycle_context
		if RuleTimingCatalog.has_timing(end_name):
			_emit_rule_timing(end_name, player_id, player_id, player_id, completion_data, completion_parent_event_id)
		if has_pending_card_choice():
			return
	var after_name: String = "%sAfter" % base_name
	if str((_started_phase_lifecycles.get(lifecycle_key, lifecycle_context) as Dictionary).get("status", "")) == "end_emitted":
		lifecycle_context["status"] = "after_emitted"
		_started_phase_lifecycles[lifecycle_key] = lifecycle_context
		if RuleTimingCatalog.has_timing(after_name):
			_emit_rule_timing(after_name, player_id, player_id, player_id, completion_data, completion_parent_event_id)
		if has_pending_card_choice():
			return
	_started_phase_lifecycles.erase(lifecycle_key)


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
	while player != null and player.alive and not state.game_over and not has_pending_card_choice() and not player.judgment_area.is_empty():
		# 当前延时锦囊；始终取判定区数组首项，完整离区后下一项才会成为新的处理对象。
		var delayed_card: CardInstance = player.judgment_area.front()
		# 当前延时锦囊判定事件；展示、无懈与实际判定都关联本回合判定阶段，回放可以恢复严格顺序。
		var delayed_event_id: int = _record_runtime_event("delayedJudge", "judgment", {"player_id":player_id, "card_uid":delayed_card.uid, "card_id":delayed_card.definition_id}, {}, _current_turn_event_id)
		_emit_rule_timing("phaseJudge", player_id, player_id, player_id, {"card_uid":delayed_card.uid, "card_id":delayed_card.definition_id}, delayed_event_id)
		_ensure_card_movement()
		_move_card_with_timings(delayed_card, "processing", -1, "judge", delayed_event_id)
		# 延时锦囊展示；表现接管其可能发生的处理区到弃牌堆移动，闪电传递时由新区域移动释放所有权。
		_request_card_presentation(delayed_card, player_id, [], "delayedJudge", delayed_event_id, true)
		add_log("%s开始判定%s。" % [player.display_name, describe_card(delayed_card)])
		_emit_state()
		if delayed_judgment_preview_seconds > 0.0 and not state.match_id.is_empty():
			await get_tree().create_timer(delayed_judgment_preview_seconds, false).timeout
			if not _is_judgment_flow_valid(player_id, flow_token):
				return
		# 延时锦囊是否在生效前被无懈可击抵消；异步响应必须保留判定恢复标记。
		var negated: bool = resolve_trick_negation(-1, player_id, delayed_card.definition_id, {"delayed_judgment":true})
		if state.game_over or has_pending_card_choice():
			_judgment_flow_in_progress = false
			_judgment_resume_needs_result_pause = true
			return
		_resolve_delayed_judgment_card(player_id, delayed_card, negated)
		_emit_state()
		if state.game_over or has_pending_card_choice():
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
		if not has_same_delayed_card:
			_ensure_card_movement()
			_move_card_with_timings(delayed_card, "judgment", candidate.player_id, "add_judge", state.current_event_id)
			add_log("【%s】移动至%s的判定区。" % [delayed_name, candidate.display_name])
			return
		candidate = state.get_next_alive_player(candidate.player_id)
		checked_count += 1
	# 所有角色均不是合法目标时，延时锦囊回到原角色判定区，而不是进入弃牌堆。
	var original_player: PlayerState = state.get_player(from_player_id)
	if original_player != null and original_player.alive:
		_ensure_card_movement()
		_move_card_with_timings(delayed_card, "judgment", original_player.player_id, "add_judge", state.current_event_id)
		add_log("没有其他合法目标，【%s】回到%s的判定区。" % [delayed_name, original_player.display_name])
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
		if target == null or not target.alive:
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
	}


## 开始一名目标的牌效生命周期；同时为【杀】派发 shaBefore 与 shaBegin，任一取消都会产生对应取消时机。
func _begin_card_target_lifecycle(card_uid: int, target_id: int, parent_event_id: int) -> bool:
	# 当前逐目标共享上下文；同一目标异步恢复时不会重复派发 Before 与 Begin。
	var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
	if bool(resolution_context.get("target_lifecycle_started", false)) and not bool(resolution_context.get("target_lifecycle_finished", false)) and int(resolution_context.get("current_target_id", -1)) == target_id:
		return true
	# 当前使用牌上下文与使用者；player 角色对应使用者，target 角色对应当前生效目标。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	var actor_id: int = int(card_use_context.get("actor_id", -1))
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid, target_id)
	var before_event: RuleEvent = _emit_rule_timing("useCardToBefore", actor_id, actor_id, target_id, timing_data, parent_event_id)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		_emit_rule_timing("useCardToCancelled", actor_id, actor_id, target_id, before_event.data, parent_event_id)
		return false
	var begin_event: RuleEvent = _emit_rule_timing("useCardToBegin", actor_id, actor_id, target_id, before_event.data if before_event != null else timing_data, parent_event_id)
	if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
		_emit_rule_timing("useCardToCancelled", actor_id, actor_id, target_id, begin_event.data, parent_event_id)
		return false
	# 当前牌定义；effect_id=slash 的三种【杀】共享专属时机。
	var definition: Dictionary = GameDatabase.get_card(str(card_use_context.get("card_definition_id", "")))
	if str(definition.get("effect_id", "")) == "slash":
		var sha_before_event: RuleEvent = _emit_rule_timing("shaBefore", actor_id, actor_id, target_id, timing_data, parent_event_id)
		if sha_before_event != null and (sha_before_event.cancelled or sha_before_event.neutralized):
			_emit_rule_timing("shaCancelled", actor_id, actor_id, target_id, sha_before_event.data, parent_event_id)
			return false
		var sha_begin_event: RuleEvent = _emit_rule_timing("shaBegin", actor_id, actor_id, target_id, sha_before_event.data if sha_before_event != null else timing_data, parent_event_id)
		if sha_begin_event != null and (sha_begin_event.cancelled or sha_begin_event.neutralized):
			_emit_rule_timing("shaCancelled", actor_id, actor_id, target_id, sha_begin_event.data, parent_event_id)
			return false
	resolution_context["target_lifecycle_started"] = true
	resolution_context["target_lifecycle_finished"] = false
	_active_card_resolutions[card_uid] = resolution_context
	return true


## 完成一名目标的牌效生命周期；异步和同步路径共用标记，确保 useCardToEnd、After 与 shaEnd、After 只派发一次。
func _finish_card_target_lifecycle(card_uid: int, target_id: int, parent_event_id: int) -> void:
	# 当前逐目标共享上下文；未开始或已经完成时不补造事件。
	var resolution_context: Dictionary = _active_card_resolutions.get(card_uid, {}) as Dictionary
	if not bool(resolution_context.get("target_lifecycle_started", false)) or bool(resolution_context.get("target_lifecycle_finished", false)):
		return
	# 当前使用牌上下文与使用者；用于角色关系匹配和牌族判断。
	var card_use_context: Dictionary = _card_use_contexts.get(card_uid, {}) as Dictionary
	var actor_id: int = int(card_use_context.get("actor_id", -1))
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid, target_id)
	var definition: Dictionary = GameDatabase.get_card(str(card_use_context.get("card_definition_id", "")))
	if str(definition.get("effect_id", "")) == "slash":
		_emit_rule_timing("shaEnd", actor_id, actor_id, target_id, timing_data, parent_event_id)
		_emit_rule_timing("shaAfter", actor_id, actor_id, target_id, timing_data, parent_event_id)
	_emit_rule_timing("useCardToEnd", actor_id, actor_id, target_id, timing_data, parent_event_id)
	_emit_rule_timing("useCardToAfter", actor_id, actor_id, target_id, timing_data, parent_event_id)
	resolution_context["target_lifecycle_finished"] = true
	_active_card_resolutions[card_uid] = resolution_context


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


## 创建一张虚拟牌并使用；单材料转化保留花色点数，多材料转化保持无花色无点数。
## 可选规则覆写只表达技能的距离、次数或目标上限修正，材料真实颜色由本入口强制写入并参与最终目标校验。
func execute_virtual_card_use(actor_id: int, virtual_card_definition_id: String, material_card_uids: Array[int], target_ids: Array[int], log_message: String, rule_overrides: Dictionary = {}) -> bool:
	if virtual_card_definition_id.is_empty() or material_card_uids.is_empty():
		return false
	# 单材料转化牌的花色；默认none用于丈八蛇矛等多材料虚拟牌。
	var virtual_suit: String = "none"
	# 单材料转化牌的点数；默认0表示多材料虚拟牌没有可继承点数。
	var virtual_rank: int = 0
	if material_card_uids.size() == 1:
		# 唯一材料牌；允许来自手牌、木牛“粮”或装备区，lose子事件仍会再次复核区域。
		var single_material: CardInstance = _find_owned_virtual_material(actor_id, material_card_uids[0])
		if single_material == null:
			return false
		virtual_suit = single_material.suit
		virtual_rank = single_material.rank
	# 逻辑代理实体；只在本次CardUseEvent的处理区生命周期内存在。
	var virtual_card: CardInstance = CardInstance.new(virtual_card_definition_id, virtual_suit, virtual_rank)
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
	_execute_card_use(actor_id, virtual_card, normalized_target_ids, material_card_uids, true, target_ids)
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
func _execute_card_use(actor_id: int, card: CardInstance, target_ids: Array[int], material_card_uids: Array[int] = [], virtual_proxy: bool = false, requested_target_ids: Array[int] = []) -> void:
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
	if material_card_uids.is_empty():
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
		"custom_args":{},
		"material_card_uids":virtual_card.material_card_uids.duplicate(),
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
	actor.card_use_history[card.definition_id] = int(actor.card_use_history.get(card.definition_id, 0)) + 1
	_record_card_used_this_turn(actor_id, card.definition_id)
	# 当前出牌阶段使用历史；只服务 phase 作用域限次查询，不替代完整回合使用记录。
	actor.play_phase_card_use_history[card.definition_id] = int(actor.play_phase_card_use_history.get(card.definition_id, 0)) + 1
	# 当前卡牌源码；牌族兼容统计与声明时触发由对应文件维护。
	var source_definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if source_definition != null:
		source_definition.on_card_declared(self, actor, card)
	add_log("%s使用了%s。" % [actor.display_name, describe_card(card)])
	# 只有正常规则终点为弃牌堆的牌接管后续 processing -> discard 表现，装备与延时锦囊保留未来真实离区动画。
	var owns_discard_transfer: bool = str(definition.get("final_zone", "discard")) == "discard" and not bool(card_use_context.get("virtual_proxy", false))
	# 卡牌展示请求只携带序列化数据与稳定玩家 ID，界面可据此播放飞牌和目标指示动画，不持有权威状态对象。
	# 使用时完整声明目标；借刀杀人等角色语义牌可据此生成多段顺序指示线。
	var requested_presentation_target_ids: Array[int] = _int_array(card_use_context.get("requested_target_ids", event.target_ids) as Array)
	# 分阶段指示线；普通牌返回空数组并继续使用实际目标单段表现。
	var presentation_indicator_stages: Array[Dictionary] = source_definition.get_presentation_indicator_stages(actor_id, requested_presentation_target_ids, event.target_ids) if source_definition != null else []
	_request_card_presentation(card, actor_id, event.target_ids, "useCard", event.event_id, owns_discard_transfer, presentation_indicator_stages)
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
	var before_event: RuleEvent = _emit_rule_timing("useCardBefore", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), -1, timing_data, event.event_id)
	if before_event != null and (before_event.cancelled or before_event.neutralized):
		card_use_context["cancelled"] = true
		card_use_context["cancel_reason"] = before_event.termination_reason
	else:
		var begin_event: RuleEvent = _emit_rule_timing("useCardBegin", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), -1, before_event.data if before_event != null else timing_data, event.event_id)
		if begin_event != null and (begin_event.cancelled or begin_event.neutralized):
			card_use_context["cancelled"] = true
			card_use_context["cancel_reason"] = begin_event.termination_reason
	card_use_context["lifecycle_started"] = true
	_card_use_contexts[card_uid] = card_use_context


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
		if target == null or not target.alive:
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
	}
	# 同步规则事件；处理器仍使用 RuleEvent 端口，但生命周期、父子关系和暂停位置由当前 GameEvent 承载。
	var rule_event: RuleEvent = RuleEvent.new(timing_name, int(card_use_context.get("actor_id", -1)), target_id, timing_data, int(card_use_context.get("actor_id", -1)))
	rule_event.event_id = event.event_id
	rule_event.parent_id = event.parent_id
	_dispatch_timing_service_event(rule_event)
	# 触发器输出；目标、排除、直击与自定义参数全部写回共享上下文供下一时机重新读取。
	card_use_context["target_ids"] = (rule_event.data.get("target_ids", card_use_context.get("target_ids", [])) as Array).duplicate()
	card_use_context["excluded_target_ids"] = (rule_event.data.get("excluded_target_ids", card_use_context.get("excluded_target_ids", [])) as Array).duplicate()
	card_use_context["direct_hit_target_ids"] = (rule_event.data.get("direct_hit_target_ids", card_use_context.get("direct_hit_target_ids", [])) as Array).duplicate()
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
	event.result = rule_event.to_dict()
	if rule_event.cancelled:
		event.cancel(rule_event.termination_reason)
	elif rule_event.neutralized:
		event.neutralize(rule_event.termination_reason)


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
	if target_id < 0 and bool(card_use_context.get("content_complete", false)):
		# 整牌异步效果已经由恢复回调完成；content 事件恢复时只读取最终区域，禁止再次执行亮牌、选择或其他一次性效果。
		event.result = {"target_ids":(card_use_context.get("target_ids", []) as Array).duplicate(), "destination":str(card_use_context.get("destination", "discard"))}
		return
	# 本次内容返回的最终区域；pending 表示子事件必须等待现有恢复入口提交结果。
	var destination: String = "discard"
	if target_id >= 0 and _active_card_resolutions.has(card_uid):
		# 当前逐目标效果上下文；包含杀伤害、属性、无视防具与卡牌专属共享数据。
		var resolution_context: Dictionary = _active_card_resolutions[card_uid] as Dictionary
		destination = effect_resolver.resolve_target(card, int(resolution_context.get("actor_id", -1)), target_id, resolution_context)
		if destination == "pending" or has_pending_card_choice():
			return
		_finish_card_target_lifecycle(card_uid, target_id, event.event_id)
		resolution_context["current_target_id"] = -1
		_active_card_resolutions[card_uid] = resolution_context
		event.result = {"target_id":target_id, "destination":destination}
		return
	# 整牌内容；装备、延时锦囊和五谷等效果必须一次读取完整目标数组。
	var whole_targets: Array[int] = []
	for target_id_variant: Variant in card_use_context.get("target_ids", []) as Array:
		whole_targets.append(int(target_id_variant))
	destination = effect_resolver.resolve(card, int(card_use_context.get("actor_id", -1)), whole_targets)
	if destination == "pending" or has_pending_card_choice():
		return
	card_use_context["destination"] = destination
	card_use_context["content_complete"] = true
	_card_use_contexts[card_uid] = card_use_context
	event.result = {"target_ids":whole_targets, "destination":destination}


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
	var timing_data: Dictionary = _build_card_use_timing_data(card_uid)
	if bool(card_use_context.get("cancelled", false)):
		timing_data["reason"] = str(card_use_context.get("cancel_reason", "cancelled"))
		_emit_rule_timing("useCardCancelled", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), -1, timing_data, event.event_id)
	else:
		_emit_rule_timing("useCardEnd", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), -1, timing_data, event.event_id)
		_emit_rule_timing("useCardAfter", int(card_use_context.get("actor_id", -1)), int(card_use_context.get("actor_id", -1)), -1, timing_data, event.event_id)
	card_use_context["lifecycle_finished"] = true
	_card_use_contexts[card_uid] = card_use_context


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
	if state == null or state.game_over:
		return false
	# 重铸角色；死亡、离场或不存在的角色不能移动手牌或获得补牌。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive or player.out_of_game:
		return false
	# 被重铸实体；只接受普通手牌区，木牛“粮”、装备和判定牌均不会被 find_hand_card 返回。
	var card: CardInstance = player.find_hand_card(card_uid)
	if card == null:
		return false
	# 卡牌显示定义；日志名称遵循当前三国杀/崩铁名称设置，不暴露实体 UID。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	player.take_hand_card(card.uid)
	_move_to_discard(card)
	add_log("%s重铸了%s。" % [player.display_name, GameSettings.resolve_card_name(definition)])
	# 重铸牌离开最后手牌时产生的技能或装备触发必须先完整结算，随后再执行固定摸1张牌。
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("recast_draw", {"player_id":player_id})
		return true
	draw(player_id, 1)
	return true


## 结束出牌阶段；超过手牌上限时由当前角色自主选择足量手牌弃置。
func _end_play_phase(player_id: int, complete_use_phase: bool = true, hide_controls_during_transition: bool = false) -> void:
	if state.current_player_id != player_id or state.current_phase != "play":
		_reject("当前不能结束出牌阶段。")
		return
	_ai_drive_token += 1
	if complete_use_phase:
		_finish_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		# phaseUseEnd或phaseUseAfter中的技能选择会暂停结束流程；恢复后由统一阶段续接入口再次进入本函数。
		if has_pending_card_choice():
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
	# 当前额外出牌阶段的稳定后继；不同插入位置不再共享模糊布尔标记。
	var return_point: String = str(_active_extra_play_phase_context.get("return_point", "")) if int(_active_extra_play_phase_context.get("player_id", -1)) == player_id else ""
	_active_extra_play_phase_context.clear()
	_extra_play_phase_returns_to_finish.erase(player_id)
	# 弃牌阶段内获得的额外出牌阶段执行完毕后直接进入结束阶段，不重复弃牌。
	if return_point == "finish":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_enter_finish_phase").bind(player_id))
		return
	# 回合结束时插入的额外出牌阶段完成后直接完成已经派发过phaseEnd的回合尾部，不重复结束阶段时机。
	if return_point == "turn_complete":
		_schedule_phase_transition(player_id, transition_phase, Callable(self, "_complete_finish_turn").bind(player_id))
		return
	_schedule_phase_transition(player_id, transition_phase, Callable(self, "_enter_discard_phase").bind(player_id))


## 进入弃牌阶段并在需要时创建强制选牌请求；无需弃牌时仍保留一个阶段间隔再进入结束阶段。
func _enter_discard_phase(player_id: int) -> void:
	_emit_rule_timing("phaseChange", player_id, player_id, player_id, {"from_phase":"play", "to_phase":"discard"}, _current_turn_event_id)
	state.current_phase = "discard"
	state.phase_index = 4
	_record_runtime_event("phaseDiscard", "phase", {"player_id":player_id})
	if not _begin_phase_lifecycle("phaseDiscard", player_id, {"turn_number":state.turn_number}, _current_turn_event_id):
		_emit_rule_timing("phaseDiscardCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		_finish_turn(player_id)
		return
	# 弃牌阶段Begin中的技能可创建异步选择；选择完成后由统一恢复入口重新进入阶段主体。
	if has_pending_card_choice():
		return
	_continue_turn_after_discard_phase_begin(player_id)


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
		add_log("%s在弃牌阶段弃置了%d张手牌。" % [player.display_name, selected_uids.size()])
		# 最后一张手牌产生的嵌套技能必须先结算；恢复入口会重新计算为无需弃牌，再安全进入阶段End与After。
		if _has_nested_settlement_barrier():
			return
	_finish_turn(player_id)


## 为当前回合角色开始一个独立的额外出牌阶段；阶段次数、【杀】次数与技能阶段计数都从新阶段重新计算。
func _start_extra_play_phase(player_id: int) -> void:
	# 额外阶段角色；角色在阶段交界死亡时不再继续行动，统一交给死亡后的回合转交入口。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	# 来源阶段；普通出牌阶段追加时为play，弃牌阶段插入时为discard。
	var previous_phase: String = state.current_phase
	_emit_rule_timing("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"play", "extra_phase":true}, _current_turn_event_id)
	state.current_phase = "play"
	state.phase_index = 3
	# 【杀】的基础限制按出牌阶段计算；额外出牌阶段必须恢复为0，不能沿用本回合前一阶段的次数。
	player.slash_count = 0
	# 阶段限次牌使用历史；额外阶段必须从空历史开始，回合级【酒】与完整用牌记录仍保留在 card_use_history。
	player.play_phase_card_use_history.clear()
	_record_runtime_event("phaseUse", "phase", {"player_id":player_id, "extra_phase":true}, {}, _current_turn_event_id)
	if not _begin_phase_lifecycle("phaseUse", player_id, {"turn_number":state.turn_number, "extra_phase":true}, _current_turn_event_id):
		_emit_rule_timing("phaseUseCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number, "extra_phase":true}, _current_turn_event_id)
		_end_play_phase(player_id, false)
		return
	add_log("%s开始执行额外的出牌阶段。" % player.display_name)
	# 额外阶段Begin中的技能选择与普通阶段使用相同暂停边界，不能并行创建chooseToUse请求。
	if has_pending_card_choice():
		return
	_begin_play_choice(player_id)
	_emit_state()
	if ai_coordinator.is_ai_controlled(player_id):
		_schedule_ai_action()


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
	add_log("%s在弃牌阶段弃置了%d张手牌。" % [player.display_name, selected_uids.size()])
	# 弃牌移动触发选择时保持阶段主体游标；选择完成后由统一阶段恢复入口继续，而不是提前发布阶段结束时机。
	if _has_nested_settlement_barrier():
		return
	_finish_turn(player_id)


## 完成当前阶段后安排进入结束阶段；所有来源共用该入口，避免同步连跑多个阶段。
func _finish_turn(player_id: int) -> void:
	if state == null or state.game_over or state.current_player_id != player_id:
		return
	# 弃牌阶段先完整完成End与After；任一完成时机产生选择时保留生命周期游标等待恢复。
	if state.current_phase == "discard":
		_finish_phase_lifecycle("phaseDiscard", player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		if has_pending_card_choice():
			return
	# 弃牌阶段内已排队的额外出牌阶段在生命周期完整结束后依次执行。
	var pending_extra_play_phases: int = int(_extra_play_phase_counts.get(player_id, 0))
	if state.current_phase == "discard" and pending_extra_play_phases > 0:
		_consume_extra_play_phase(player_id)
		_schedule_phase_transition(player_id, state.current_phase, Callable(self, "_start_extra_play_phase").bind(player_id))
		return
	_schedule_phase_transition(player_id, state.current_phase, Callable(self, "_enter_finish_phase").bind(player_id))


## 进入结束阶段并派发完整结束时机；异步技能选择完成后从唯一尾部入口继续。
func _enter_finish_phase(player_id: int) -> void:
	# 进入函数前的阶段；只有实际进入过弃牌阶段才派发其 End 与 After，翻面跳回合不会伪造弃牌结束。
	var previous_phase: String = state.current_phase
	if previous_phase == "discard":
		_finish_phase_lifecycle("phaseDiscard", player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		# 弃牌阶段End或After技能必须先结算；恢复后_finish_turn会重新进入本入口且不会重复阶段主体。
		if has_pending_card_choice():
			return
	_emit_rule_timing("phaseChange", player_id, player_id, player_id, {"from_phase":previous_phase, "to_phase":"finish"}, _current_turn_event_id)
	state.current_phase = "finish"
	state.phase_index = 5
	_record_runtime_event("phaseJieshu", "phase", {"player_id":player_id})
	if _begin_phase_lifecycle("phaseJieshu", player_id, {"turn_number":state.turn_number}, _current_turn_event_id):
		_emit_rule_timing("phaseJieshu", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
		_finish_phase_lifecycle("phaseJieshu", player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	else:
		_emit_rule_timing("phaseJieshuCancelled", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	_record_runtime_event("phaseEnd", "phase", {"player_id":player_id})
	_emit_rule_timing("phaseEnd", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	_dispatch_rule_event(RuleEvent.new("phase_finish", player_id, player_id, {}))
	if has_pending_card_choice():
		_pending_finish_turn_player_id = player_id
		return
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
	# 通知全部卡牌定义清理其回合持续状态；控制器不识别具体卡牌变量。
	_notify_card_definitions_turn_ended(player_id, false)
	_record_runtime_event("phaseAfter", "phase", {"player_id":player_id})
	_emit_rule_timing("phaseAfter", player_id, player_id, player_id, {"turn_number":state.turn_number}, _current_turn_event_id)
	_check_game_over()
	if state.game_over:
		return
	_schedule_phase_transition(player_id, "finish", Callable(self, "_start_queued_or_normal_turn").bind(player_id))


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
		var resume_player: PlayerState = state.get_player(resume_player_id) if resume_player_id >= 0 else null
		if resume_player == null or not resume_player.alive or resume_player.out_of_game:
			resume_player = state.get_next_alive_player(resume_player_id if resume_player_id >= 0 else finished_player_id)
		if resume_player != null:
			_start_turn(resume_player.player_id)
		return
	if normal_next_player != null:
		_start_turn(normal_next_player.player_id)


## 当前回合角色在事件结算中死亡后转交回合；不触发正常结束阶段，但会清除只持续到本回合的酒加值。
func _advance_after_current_player_death(dead_player_id: int) -> void:
	_ai_drive_token += 1
	_extra_play_phase_counts.erase(dead_player_id)
	_extra_play_phase_return_points.erase(dead_player_id)
	_extra_play_phase_returns_to_finish.erase(dead_player_id)
	if int(_active_extra_play_phase_context.get("player_id", -1)) == dead_player_id:
		_active_extra_play_phase_context.clear()
	_emit_rule_timing("phaseOver", dead_player_id, dead_player_id, dead_player_id, {"reason":"current_player_death", "turn_number":state.turn_number}, _current_turn_event_id)
	_notify_card_definitions_turn_ended(dead_player_id, true)
	# 死亡回合仍需遵守已经排队的额外回合与额外回合链恢复顺序。
	_schedule_phase_transition(dead_player_id, state.current_phase, Callable(self, "_start_queued_or_normal_turn").bind(dead_player_id))


## 依次请求所有存活角色使用卡牌源码声明的濒死救援牌；已询问名单保证异步取消后不会重复询问同一角色。
## 救援只遍历一轮座次；同一响应者成功救援后若目标仍未达到1点体力，则立即继续询问该响应者，取消后再进入下一名。
func _resolve_dying(target_id: int, killer_id: int, rescue_start_override: int = -1, already_asked_rescuer_ids: Array[int] = []) -> void:
	# 濒死角色状态；可能需要多张桃才能将体力回复至1。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		return
	# 已经恢复正体力的角色不再建立救援请求；若旧流程仍在队列中则统一完成脱离濒死结算。
	if target.hp > 0:
		if target.dying or state.dying_queue.has(target_id):
			_finish_dying_rescue(target_id)
		else:
			_finish_pending_damage(target_id)
		return
	# 是否首次进入本次濒死流程；连续出桃与取消后的座次推进都复用同一流程，不重复创建回放事件。
	var is_new_dying_flow: bool = not state.dying_queue.has(target_id)
	if is_new_dying_flow:
		# 濒死前时机；只有处理器已经恢复正体力或令角色离场时才允许终止，避免留下非正体力的存活角色。
		var dying_before_event: RuleEvent = _emit_rule_timing("dyingBefore", target_id, killer_id, target_id, {"hp":target.hp, "required_recover":1 - target.hp})
		if not target.alive or target.hp > 0:
			_finish_pending_damage(target_id)
			return
		# 濒死开始时机；取消标志不能单独绕过体力不大于0必然进入濒死的基础规则。
		var dying_begin_event: RuleEvent = _emit_rule_timing("dyingBegin", target_id, killer_id, target_id, dying_before_event.data if dying_before_event != null else {"hp":target.hp, "required_recover":1 - target.hp})
		if not target.alive or target.hp > 0:
			_finish_pending_damage(target_id)
			return
		# 本次濒死事件 ID；救援选择记录作为其子事件写入回放历史，仅在首次进入时创建。
		var dying_event_id: int = _record_runtime_event("dying", "dying", {"target_id":target_id, "source_id":killer_id})
		state.dying_queue.append(target_id)
		_record_runtime_event("_save", "choice", {"target_id":target_id, "source_id":killer_id}, {}, dying_event_id)
		_emit_rule_timing("dying", target_id, killer_id, target_id, {"hp":target.hp, "required_recover":1 - target.hp, "dying_event_id":dying_event_id}, dying_event_id)
	target.dying = true
	# 当前轮救援询问起点；首次从当前回合角色开始，连续出桃时仍从刚才的响应者继续。
	var rescue_start_player_id: int = state.current_player_id if rescue_start_override < 0 else rescue_start_override
	# 当前轮已经完成询问的角色 ID；异步响应恢复时沿用，整个濒死流程不会清空全体名单开启第二轮。
	var asked_rescuer_ids: Array[int] = already_asked_rescuer_ids.duplicate()
	if is_new_dying_flow:
		add_log("%s进入濒死状态，需要回复至1点体力。" % target.display_name)
		_dispatch_rule_event(RuleEvent.new("dying_begin", killer_id, target_id, {"required_recover":1 - target.hp}))
	# 救援询问顺序；同一轮从指定起点按行动座次遍历，已完成询问的角色直接跳过。
	var rescue_order: Array[PlayerState] = _get_alive_players_in_action_order(rescue_start_player_id)
	for rescuer: PlayerState in rescue_order:
		if not rescuer.alive or asked_rescuer_ids.has(rescuer.player_id):
			continue
		asked_rescuer_ids.append(rescuer.player_id)
		# 当前救援者可用选项；每张卡牌源码自行声明响应模式与角色关系限制。
		var dying_response_options: Array[Dictionary] = _get_dying_response_options(rescuer.player_id, target_id)
		# 当前救援响应模式；同模式的不同扩展牌共享一个统一响应入口。
		var response_patterns: Array[String] = []
		# 玩家可见救援牌名；提示文本不在控制器维护具体卡牌白名单。
		var response_names: Array[String] = []
		for option: Dictionary in dying_response_options:
			response_patterns.append(str(option.get("pattern", "")))
			response_names.append("【%s】" % str(option.get("name", "救援牌")))
		# 当前尚需回复的体力点数；现有救援牌均固定回复1点，因此数值也等于达到1点所需的牌数。
		var required_recover: int = 1 - target.hp
		# 救援响应上下文；已询问名单与所需回复数共同恢复同一个单轮流程，不创建全体第二轮询问。
		var rescue_context: Dictionary = {"kind":"dying_response", "responder_id":rescuer.player_id, "target_id":target_id, "killer_id":killer_id, "rescue_start_id":rescue_start_player_id, "response_patterns":response_patterns.duplicate(), "asked_rescuer_ids":asked_rescuer_ids.duplicate(), "required_recover":required_recover}
		# 救援提示；明确给出目标达到1点体力还需要的回复量和当前源码允许的牌名。
		var rescue_prompt: String = "%s当前还需要回复%d点体力至1点，请选择是否使用%s。" % [_player_character_name(target), required_recover, "、".join(response_names) if not response_names.is_empty() else "救援牌"]
		# 实际提交的救援牌；为空表示明确取消或当前没有合法候选。
		var rescue_card: CardInstance = request_response_card_patterns(rescuer.player_id, response_patterns, rescue_prompt, rescue_context)
		if has_pending_card_choice():
			return
		if rescue_card == null:
			continue
		_apply_dying_response_card(rescuer.player_id, target_id, rescue_card)
		if target.hp >= 1:
			_finish_dying_rescue(target_id)
			return
		# 同一响应者出牌后仍未救至1点时允许继续出牌；只移除该响应者，其他已询问角色仍保持完成状态。
		asked_rescuer_ids.erase(rescuer.player_id)
		_resolve_dying(target_id, killer_id, rescuer.player_id, asked_rescuer_ids)
		return
	state.dying_queue.erase(target_id)
	_resolve_death(target_id, killer_id)


## 恢复濒死救援响应；成功使用桃或酒后重新检查目标体力并继续同一救援轮。
func _continue_dying_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 当前响应者；所选牌必须仍来自其牌源。
	var responder_id: int = int(context.get("responder_id", -1))
	# 濒死目标；回复与后续死亡判断都针对该稳定 ID。
	var target_id: int = int(context.get("target_id", -1))
	# 本次窗口允许的响应模式；其他角色只有桃，濒死者本人同时包含桃和酒。
	var response_patterns: Array[String] = []
	for response_pattern_variant: Variant in context.get("response_patterns", []) as Array:
		# 当前允许模式；去重后交给实体牌消费入口复核。
		var allowed_pattern: String = str(response_pattern_variant)
		if not response_patterns.has(allowed_pattern):
			response_patterns.append(allowed_pattern)
	# 当前轮已经询问的救援者 ID；恢复后只继续尚未询问的座次，防止取消按钮看似无效。
	var asked_rescuer_ids: Array[int] = []
	for rescuer_id_variant: Variant in context.get("asked_rescuer_ids", []) as Array:
		# 已询问救援者 ID；防御性去重，避免异常上下文产生重复跳过项。
		var asked_rescuer_id: int = int(rescuer_id_variant)
		if not asked_rescuer_ids.has(asked_rescuer_id):
			asked_rescuer_ids.append(asked_rescuer_id)
	# 实际救援响应牌；为空表示当前桃或酒请求被取消。
	var response_card: CardInstance
	if not selected_uids.is_empty():
		response_card = _consume_response_card_uid_patterns(responder_id, selected_uids[0], response_patterns)
	if response_card == null:
		# 下一名存活救援者；本轮已经询问的角色会在恢复函数中跳过，不会再次弹出同一桃询问。
		var next_rescuer: PlayerState = state.get_next_alive_player(responder_id)
		_resolve_dying(target_id, int(context.get("killer_id", -1)), next_rescuer.player_id if next_rescuer != null else int(context.get("rescue_start_id", state.current_player_id)), asked_rescuer_ids)
		return
	# 响应牌失去时插入的技能与装备触发必须先完整结算；续接快照保证已消费的救援牌不会被再次移动。
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("dying_response", {"rule_context":context.duplicate(true), "response_card":_serialize_optional_response_card(response_card)})
		return
	_continue_consumed_dying_response(context, response_card)


## 在失牌触发与装备事件完成后恢复已经消费的濒死救援牌。
func _continue_dying_response_after_barrier(continuation_context: Dictionary) -> void:
	# 原濒死响应上下文；包含响应者、目标、击杀来源、座次起点与已询问名单。
	var rule_context: Dictionary = continuation_context.get("rule_context", {}) as Dictionary
	# 已完成消费的救援响应牌；只恢复逻辑牌数据，不再次从弃牌堆取出实体。
	var response_card: CardInstance = _deserialize_optional_response_card(continuation_context.get("response_card", {}) as Dictionary)
	if response_card != null:
		_continue_consumed_dying_response(rule_context, response_card)


## 应用一张已经消费的救援牌；回复后的触发仍可再次暂停，后续只检查濒死状态而不重复回复。
func _continue_consumed_dying_response(context: Dictionary, response_card: CardInstance) -> void:
	# 当前响应者；卡牌源码会再次复核其与濒死目标的救援关系。
	var responder_id: int = int(context.get("responder_id", -1))
	# 当前濒死目标；回复、继续询问和脱离濒死都使用同一稳定 ID。
	var target_id: int = int(context.get("target_id", -1))
	# 实际救援效果；由已消费实体牌的源码复核角色关系并应用回复。
	_apply_dying_response_card(responder_id, target_id, response_card)
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("dying_after_response", context.duplicate(true))
		return
	_continue_dying_after_applied_response(context)


## 在救援牌回复后的全部插入事件结束后重新读取体力，并继续同一求桃轮或完成脱离濒死。
func _continue_dying_after_applied_response(context: Dictionary) -> void:
	# 当前响应者；目标仍未达到1点时允许其继续使用下一张合法救援牌。
	var responder_id: int = int(context.get("responder_id", -1))
	# 当前濒死目标；等待期间可能已被其他触发救起、杀死或移出游戏。
	var target_id: int = int(context.get("target_id", -1))
	# 当前轮已询问角色；继续由同一响应者救援时只移除本人，其他角色保持已经问过。
	var asked_rescuer_ids: Array[int] = _int_array(context.get("asked_rescuer_ids", []) as Array)
	# 最新濒死目标状态；回复后依据当前体力决定继续救援或退出濒死队列。
	var target: PlayerState = state.get_player(target_id)
	if target != null and target.alive and target.hp <= 0:
		# 当前响应者仍可继续出桃；只从已询问集合移除本人，其他角色在本轮内不会被重复询问。
		asked_rescuer_ids.erase(responder_id)
		_resolve_dying(target_id, int(context.get("killer_id", -1)), responder_id, asked_rescuer_ids)
	elif target != null and target.alive:
		_finish_dying_rescue(target_id)


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


## 在角色体力恢复至1点或以上时统一结算求桃流程；状态、事件与日志在同一入口完成，父级卡牌或阶段随后才能继续。
func _finish_dying_rescue(target_id: int) -> void:
	# 已脱离濒死的目标；异常丢失目标时仍清理队列，避免后续流程永久认为存在未结算濒死角色。
	var target: PlayerState = state.get_player(target_id)
	state.dying_queue.erase(target_id)
	if target == null:
		return
	target.dying = false
	_record_runtime_event("dyingAfter", "dying", {"target_id":target_id, "hp":target.hp, "rescued":true})
	_emit_rule_timing("dyingAfter", target_id, target_id, target_id, {"hp":target.hp, "rescued":true})
	_dispatch_rule_event(RuleEvent.new("dying_end", target_id, target_id, {"hp":target.hp, "rescued":true}))
	add_log("%s脱离濒死状态，求桃流程结算完成。" % target.display_name)
	_finish_pending_damage(target_id)


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
	# 死亡角色状态；先标记死亡，避免清理白银狮子时错误回复。
	var victim: PlayerState = state.get_player(victim_id)
	if victim == null or not victim.alive:
		_finish_pending_damage(victim_id)
		return
	# 死亡前与开始时机；取消死亡要求对应技能自行修正体力或状态，控制器只停止本次死亡流程。
	var die_before_event: RuleEvent = _emit_rule_timing("dieBefore", victim_id, killer_id, victim_id, {"hp":victim.hp})
	if die_before_event != null and (die_before_event.cancelled or die_before_event.neutralized):
		victim.dying = false
		state.dying_queue.erase(victim_id)
		_finish_pending_damage(victim_id)
		return
	var die_begin_event: RuleEvent = _emit_rule_timing("dieBegin", victim_id, killer_id, victim_id, die_before_event.data if die_before_event != null else {"hp":victim.hp})
	if die_begin_event != null and (die_begin_event.cancelled or die_begin_event.neutralized):
		victim.dying = false
		state.dying_queue.erase(victim_id)
		_finish_pending_damage(victim_id)
		return
	var death_event_id: int = _record_runtime_event("die", "death", {"victim_id":victim_id, "killer_id":killer_id})
	state.dying_queue.erase(victim_id)
	victim.alive = false
	victim.dying = false
	victim.death_confirmed = true
	victim.identity_revealed = true
	_emit_rule_timing("die", victim_id, killer_id, victim_id, {"hp":victim.hp, "death_event_id":death_event_id}, death_event_id)
	add_log("%s死亡，身份为%s。" % [victim.display_name, _identity_text(victim.identity)])
	# 亮出身份后立即检测胜负；若条件已满足，规则要求直接结束游戏，不再继续死亡弃牌与奖惩。
	_check_game_over()
	if state.game_over:
		_record_runtime_event("dieAfter", "death", {"victim_id":victim_id, "game_over":true}, {}, death_event_id)
		_emit_rule_timing("dieEnd", victim_id, killer_id, victim_id, {"game_over":true, "death_event_id":death_event_id}, death_event_id)
		_emit_rule_timing("dieAfter", victim_id, killer_id, victim_id, {"game_over":true, "death_event_id":death_event_id}, death_event_id)
		_finish_pending_damage(victim_id)
		return
	while not victim.hand.is_empty():
		_move_to_discard(victim.hand.pop_back())
	discard_all_equipment(victim_id, false)
	while not victim.judgment_area.is_empty():
		_move_to_discard(victim.judgment_area.pop_back())
	# 击杀者状态；无来源伤害或击杀者已不存在时不执行奖惩。
	var killer: PlayerState = state.get_player(killer_id)
	# 身份规则返回的奖惩类型；控制器负责实际摸牌与弃牌移动。
	var reward: String = identity_rules.get_death_reward(killer, victim, str(state.match_mode))
	if reward == "draw_three" and killer != null and killer.alive:
		draw(killer.player_id, 3)
	elif reward == "leader_penalty" and killer != null and killer.alive:
		while not killer.hand.is_empty():
			_move_to_discard(killer.hand.pop_back())
		discard_all_equipment(killer.player_id, true)
		add_log("领袖杀死忠臣，弃置全部手牌和装备。")
	_check_game_over()
	_record_runtime_event("dieAfter", "death", {"victim_id":victim_id, "game_over":state.game_over}, {}, death_event_id)
	_emit_rule_timing("dieEnd", victim_id, killer_id, victim_id, {"game_over":state.game_over, "death_event_id":death_event_id}, death_event_id)
	_emit_rule_timing("dieAfter", victim_id, killer_id, victim_id, {"game_over":state.game_over, "death_event_id":death_event_id}, death_event_id)
	_finish_pending_damage(victim_id)


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
	state.public_card_choice_display.clear()
	state.simultaneous_response_display.clear()
	for player: PlayerState in state.players:
		player.identity_revealed = true
	_record_runtime_event("GameEndEvent", "game_end", {"reason":state.end_reason}, {"winner":winner})
	event_scheduler.abort_all("game_over:%s" % state.end_reason)
	add_log("对局结束，获胜方：%s。" % _winner_text(winner))
	_emit_state()
	match_finished.emit(winner)


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
	state.public_card_choice_display.clear()
	state.simultaneous_response_display.clear()
	_record_runtime_event("GameEndEvent", "game_end", {"reason":reason}, {"winner":"draw"})
	event_scheduler.abort_all("game_over:%s" % reason)
	add_log("摸牌堆与弃牌堆均为空，对局以平局结束。")
	_emit_state()
	match_finished.emit("draw")


## 将闪电移至下一角色时、装备效果与其他规则共用的弃牌移动基础操作。
## related_event_id 为-2时沿用当前规则事件；显式传入父事件可把 cardsDiscard 关联到对应结算。
func _move_to_discard(card: CardInstance, related_event_id: int = -2) -> void:
	if card == null:
		return
	_ensure_card_movement()
	# 弃置前持有者；响应牌、主动弃牌和目标区域牌都从各自实际来源锚点起飞。
	# 该来源玩家由 CardMovementService 在移动前写入 CardMoveEvent，表现层不再依赖规则调用点重复传参。
	# 弃置前区域；表现层可区分处理区、手牌、装备、判定和展示牌。
	var source_zone: String = card.zone
	# 弃牌父事件；默认使用当前规则摘要，判定与直接使用牌会显式传入稳定父事件。
	var discard_parent_event_id: int = _current_rule_parent_event_id() if related_event_id == -2 else related_event_id
	# 弃牌事件；实体移动历史关联到该事件，等价表达 orderingDiscard 最终创建 cardsDiscard 的收尾关系。
	var discard_event_id: int = _record_runtime_event("cardsDiscard", "card_move", {"card_uids":[card.uid], "from_zone":source_zone, "reason":"discard"}, {}, discard_parent_event_id)
	if card_movement != null:
		var move: CardMoveEvent = _move_card_with_timings(card, "discard_pile", -1, "discard", discard_event_id)
		if move == null:
			return
	else:
		card.zone = "discard_pile"
		card.owner_id = -1
		state.discard_pile.append(card)


## 通过唯一移动服务执行实体区域变化，并在移动前后派发 lose、gain、discard、equip、addJudge 与处理区标准时机；隐藏定向获得只在全部前置时机通过后重置牌面知识。
func _move_card_with_timings(card: CardInstance, to_zone: String, target_player_id: int = -1, reason: String = "move", event_id: int = -1, target_slot: String = "", visible_to: Array[int] = [], reset_hand_knowledge: bool = false) -> CardMoveEvent:
	if card == null:
		return null
	_ensure_card_movement()
	if card_movement == null:
		return null
	# 手牌视为效果的清理边界；实体离开当前持有者手牌区前立即恢复原名，已经创建的虚拟使用牌或响应代理继续保存本次逻辑牌效。
	if card.has_hand_view_as() and (card.zone != "hand" or to_zone != "hand" or target_player_id != card.owner_id):
		card.clear_hand_view_as()
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
		"target_slot":target_slot,
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
	var move: CardMoveEvent = card_movement.move_card(card, to_zone, target_player_id, reason, event_id, target_slot, visible_to)
	if move == null:
		return null
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
	_record_runtime_event("washCard", "card_move", {"card_count":state.draw_pile.size()}, {"to_zone":"draw_pile"})
	add_log("弃牌堆已重新洗入摸牌堆。")


## 校验并追加一个使用牌候选动作。
func _append_if_legal(result: Array[Dictionary], player_id: int, card: CardInstance, requested_targets: Array[int]) -> void:
	# 自动展开后的目标；全体牌使用空请求数组即可。
	var normalized_targets: Array[int] = card_rules.normalize_targets(player_id, card, requested_targets)
	if card_rules.validate_use(player_id, card, normalized_targets).is_empty():
		result.append({"action_type":"use_card", "actor_id":player_id, "card_uid":card.uid, "target_ids":requested_targets.duplicate(), "card_definition_id":card.definition_id})


## 校验并追加一条由卡牌源码生成的复杂目标动作；卡牌文件不需要复制标准动作字典结构。
func append_card_action_if_legal(result: Array[Dictionary], player_id: int, card: CardInstance, requested_targets: Array[int]) -> void:
	_append_if_legal(result, player_id, card, requested_targets)


## 在任意动作、技能或选择结算出口统一恢复AI流程；普通行动与子选择只能由本函数分流到各自调度器。
## 调用方必须位于规则效果已经应用完成的安全点；本函数不执行技能、牌效或阶段推进，只补齐缺失的异步驱动任务。
func _ensure_ai_progress_after_resolution() -> void:
	if is_gameplay_paused() or state == null or state.game_over or ai_coordinator == null:
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
	if not _has_active_play_choice():
		_begin_play_choice(state.current_player_id)
	if _has_active_play_choice() and not has_pending_card_choice():
		_schedule_ai_action()


## 安排下一次 AI 操作；令牌保证阶段变化后旧计时器不会执行。
func _schedule_ai_action() -> void:
	if is_gameplay_paused() or state == null or state.game_over or state.current_phase != "play" or not ai_coordinator.is_ai_controlled(state.current_player_id) or has_pending_card_choice() or not _has_active_play_choice():
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
	_ai_actions_this_turn += 1
	if _ai_actions_this_turn > max_ai_actions_per_turn:
		_submit_ai_action(PlayerAction.new("end_play", player_id))
		return
	# AI 可读取的权威完整快照；包含所有身份与手牌，但策略只能返回标准动作字典。
	var full_snapshot: Dictionary = state.to_dict(player_id, true)
	# 当前全部合法候选；核心在决策前完成枚举，AI 无权绕过合法性。
	var legal_actions: Array[Dictionary] = get_legal_actions(player_id)
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
	elif event_type == "public_card_choice_display":
		public_card_choice_display_changed.emit((event_payload.get("display", {}) as Dictionary).duplicate(true))
	elif event_type == "match_finished":
		match_finished.emit(str(event_payload.get("winner", "")))


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
		if _is_int_array_prefix(selected_target_ids, action_target_ids) and action_target_ids.size() > selected_target_ids.size():
			# 当前合法动作中紧随已选前缀的目标；加入去重集合供界面继续高亮。
			var next_target_id: int = action_target_ids[selected_target_ids.size()]
			if not legal_target_ids.has(next_target_id):
				legal_target_ids.append(next_target_id)
	result["legal_target_ids"] = legal_target_ids
	if authoritative_minimum_target_count >= 0:
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


## 写入一条迁移期规则事件记录并同步 GameState；所有记录默认挂在当前对局根事件下。
func _record_runtime_event(event_name: String, event_type: String, context: Dictionary = {}, result: Dictionary = {}, parent_id: int = -2) -> int:
	if event_scheduler == null:
		return -1
	# 实际父事件 ID；-2 表示使用根事件，-1 明确表示独立根级事件。
	var resolved_parent_id: int = _runtime_root_event_id if parent_id == -2 else parent_id
	var event_id: int = event_scheduler.record_event(event_name, event_type, context, resolved_parent_id, result)
	if state != null:
		state.current_event_id = event_id
		_append_runtime_history_record(event_scheduler.get_latest_history_record())
	return event_id


## 创建并派发一条标准规则时机；player/source/target 分别用于四角色触发关系，数据只允许基础可序列化值。
func emit_rule_timing(event_name: String, player_id: int = -1, source_id: int = -1, target_id: int = -1, event_data: Dictionary = {}, parent_id: int = -2) -> RuleEvent:
	return _emit_rule_timing(event_name, player_id, source_id, target_id, event_data, parent_id)


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
	_rule_timing_initial_choice_request_id = int(_pending_card_choice.get("request_id", -1))
	_is_dispatching_rule_timing = true
	timing_service.dispatch(event)
	_is_dispatching_rule_timing = previous_dispatching_state
	_rule_timing_initial_choice_request_id = previous_initial_choice_request_id


## 确保时机服务始终绑定当前状态、总线和重新开局后新建的 TriggerManager；测试替换 GameState 时也无需手工重建。
func _ensure_timing_service() -> void:
	if trigger_manager == null:
		trigger_manager = TriggerManager.new()
	if timing_service == null:
		timing_service = RuleTimingService.new(event_bus, trigger_manager, state)
	else:
		timing_service.configure(event_bus, trigger_manager, state)
	timing_service.set_trigger_pause_condition(Callable(self, "_should_pause_rule_timing_dispatch"))


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
	timing_service.resume_deferred_dispatches()
	_is_dispatching_rule_timing = previous_dispatching_state
	_rule_timing_initial_choice_request_id = previous_initial_choice_request_id


## 把一条运行时历史增量追加到 GameState；相同 sequence 已存在时不会重复写入。
func _append_runtime_history_record(record: Dictionary) -> void:
	if state == null or record.is_empty():
		return
	var sequence: int = int(record.get("sequence", -1))
	if not state.event_history.is_empty() and int((state.event_history.back() as Dictionary).get("sequence", -2)) == sequence:
		return
	state.event_history.append(record.duplicate(true))


## 运行时事件开始回调；只把摘要 ID 和历史写入权威状态，不暴露 GameEvent 可变引用。
func _on_runtime_event_started(event_data: Dictionary) -> void:
	if state == null:
		return
	state.current_event_id = int(event_data.get("event_id", -1))
	_append_runtime_history_record(event_scheduler.get_latest_history_record())


## 运行时事件完成回调；父事件 ID 成为当前摘要，根级完成后回到对局根事件。
func _on_runtime_event_finished(event_data: Dictionary) -> void:
	if state == null:
		return
	state.current_event_id = int(event_data.get("parent_id", _runtime_root_event_id))
	if state.current_event_id < 0:
		state.current_event_id = _runtime_root_event_id
	_append_runtime_history_record(event_scheduler.get_latest_history_record())


## 运行时选择请求回调；保存完整权威摘要，GameState.to_dict 后续可按观察者继续裁剪候选。
func _on_runtime_choice_requested(request_data: Dictionary) -> void:
	if state == null:
		return
	state.current_choice_request = request_data.duplicate(true)
	state.current_event_id = int(request_data.get("event_id", state.current_event_id))
	_append_runtime_history_record(event_scheduler.get_latest_history_record())
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
	_append_runtime_history_record(event_scheduler.get_latest_history_record())


## 发出面向本地玩家的状态快照，并让网络网关保留公共同步入口。
func _emit_state() -> void:
	if state == null:
		return
	# 正常运行时历史由事件信号逐条增量同步；只有计数失配才执行全量校准，避免长对局每次界面刷新都复制完整回放。
	if event_scheduler != null and state.event_history.size() != event_scheduler.get_event_history_count():
		state.event_history = event_scheduler.get_event_history()
	# 本地界面快照；仅公开本地玩家手牌和自身身份。
	var local_snapshot: Dictionary = state.to_dict(local_human_player_id, false)
	# 本地手气卡私有状态；只包含本人的剩余张数与按钮权限。
	local_snapshot["starting_hand_mulligan"] = starting_hand_mulligan.to_dict(local_human_player_id) if state.current_phase == "starting_hand_mulligan" and starting_hand_mulligan != null else {}
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
			remote_snapshot.erase("random_seed")
			# 本地合法动作；只发送给实际行动玩家，用于客户端无状态预览，最终提交仍由房主重新校验。
			remote_snapshot["local_legal_actions"] = get_legal_actions(viewer_id) if state.current_phase == "play" and state.current_player_id == viewer_id else []
			# 选将私有快照；候选仅进入对应观察者的定向状态包，其他玩家只能看到公开确认状态。
			remote_snapshot["character_selection"] = _get_character_selection_snapshot(viewer_id)
			# 手气卡私有快照；每名远端玩家只接收自己的剩余张数和确认状态。
			remote_snapshot["starting_hand_mulligan"] = starting_hand_mulligan.to_dict(viewer_id) if state.current_phase == "starting_hand_mulligan" and starting_hand_mulligan != null else {}
			network_gateway.send_snapshot_to_peer(remote_snapshot, peer_id)


## 返回面向指定观察者的选将类私有快照；普通选将与房主 AI 调整阶段互斥。
func _get_character_selection_snapshot(viewer_id: int) -> Dictionary:
	if state == null:
		return {}
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
	# 本局模式；斗地主按地主/农民阵营简化态度。
	var match_mode: String = identity_rules.normalize_mode(str(state.match_mode) if state != null else IdentityRules.MODE_IDENTITY)
	if match_mode == IdentityRules.MODE_DOUDIZHU:
		if from_identity == to_identity and not from_identity.is_empty():
			return 1
		if from_identity == "landlord" and to_identity == "landlord":
			return 1
		if from_identity == "peasant" and to_identity == "peasant":
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
	}.get(identity, identity)


## 将获胜方 ID 转换为界面与日志文本。
func _winner_text(winner: String) -> String:
	return {
		"leader_and_loyalists":"领袖与忠臣",
		"rebels":"反贼",
		"renegade":"内奸",
		"landlords":"地主",
		"peasants":"农民",
	}.get(winner, winner)
