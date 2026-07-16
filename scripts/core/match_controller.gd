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

## 牌面弃牌幂等状态释放信号；实体进入任意非弃牌区域时发送，不代表需要播放一条可见转移动画。
signal card_animation_ownership_reset_requested(card_uid: int)

## 统一选择请求信号；玩家和 AI 都必须先收到询问，再提交 choose_cards 动作。
signal card_choice_requested(choice_data: Dictionary)

## 选将快照变化信号；只包含观察者可见候选、公开主公武将和全员确认状态。
signal character_selection_changed(snapshot: Dictionary)

## 实际牌效到“可作为何种响应牌打出”的映射；只包含真正提供响应的牌效，普通锦囊的受无懈属性不会进入该表。
const PROVIDED_RESPONSE_PATTERN_BY_EFFECT: Dictionary = {
	"slash":"sha",
	"dodge":"shan",
	"peach":"tao",
	"wine":"jiu",
	"negate":"wuxie",
}

## 默认牌堆 ID；可在检查器中替换为后续扩展牌堆，运行时通常无需动态修改。
@export var default_deck_id: String = "standard_162"

## 默认玩家人数；支持2至10，直接运行演示场景时创建8人局，运行时可在新开局前修改。
@export_range(2, 10, 1) var default_player_count: int = 8

## 人类本地玩家当前座次；默认0作为随机分配前的有效占位值，设为 -1 可运行纯 AI 自动对局。
@export_range(-1, 9, 1) var local_human_player_id: int = 0

## 是否在每局创建时为本地人类玩家重新随机分配座次；默认开启以保证本地玩家不固定在一号位，纯 AI 模式不受影响。
@export var randomize_local_human_seat: bool = true

## AI 每次行动或选择响应前的等待秒数；默认0.30秒，局内菜单可在0.05至1.00秒范围内动态同步，测试可直接覆盖。
@export_range(0.05, 1.0, 0.05) var ai_action_delay_seconds: float = 0.30

## 延时锦囊进入中央展示后等待再开始无懈与判定的秒数；默认1.00秒保证玩家能辨认当前结算牌，运行时通常无需动态修改。
@export_range(0.0, 3.0, 0.05) var delayed_judgment_preview_seconds: float = 1.00

## 一张延时锦囊完成判定后等待再处理下一张的秒数；默认1.00秒让判定结果与下一张牌保持清晰间隔，运行时通常无需动态修改。
@export_range(0.0, 3.0, 0.05) var delayed_judgment_result_pause_seconds: float = 1.00

## 单个 AI 出牌阶段最多执行的动作数；默认64用于防止扩展牌循环导致界面停滞。
@export_range(1, 256, 1) var max_ai_actions_per_turn: int = 64

## 每名玩家随机展示的可选武将数量；默认5，运行时无需动态修改，后续扩展武将库后可在检查器调整。
@export_range(1, 20, 1) var character_candidate_count: int = 5

## 特殊模式预留的首回合座次号；标准身份局不读取该值而始终由随机座次的主公开始，运行时无需修改。
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

## 当前对局按玩家 ID 分组的独立技能实例；每个技能文件自行安装事件订阅与主动发动函数，重新开局时整体卸载。
var skill_instances_by_player: Dictionary = {}

## 当前对局按实体牌 UID 索引的持续卡牌实例；装备离开区域或重新开局时会精确卸载对应事件订阅。
var card_runtime_instances: Dictionary = {}

## 事件树运行时；统一管理根事件、子事件、after 队列、选择暂停和回放历史。
var event_scheduler: EventScheduler

## 触发器排序组件；保留与同步 RuleEventBus 的兼容边界，逐步承载技能时机排序。
var trigger_manager: TriggerManager

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

## 当前是否正在批量驱动 AI 选将；防止阶段推进时递归处理旧待选列表并产生重复提交。
var _is_driving_character_selection: bool = false

## 当前等待提交的统一选牌请求；空字典表示没有响应、弃牌或区域选牌窗口。
var _pending_card_choice: Dictionary = {}

## 最近一次同步完成请求所选择的实体牌 UID；只供无交互测试与兼容回退在当前调用栈读取，正式 AI 请求始终异步恢复。
var _resolved_card_choice_uids: Array[int] = []

## 最近一次同步选择随装备技能提交的实体材料 UID；丈八蛇矛响应会读取恰好两张手牌，其他选择保持空数组。
var _resolved_equipment_material_uids: Array[int] = []

## 全局选择请求序号；每次创建窗口递增，防止旧界面或网络消息误提交到新请求。
## 当前实现只镜像 EventScheduler 最近一次分配的全局编号，不再维护第二套独立请求序列。
var _card_choice_sequence: int = 0

## 无懈可击延迟提交后的单次恢复结果；键包含原牌 UID 与目标，读取一次后立即删除。
var _negation_resume_results: Dictionary = {}

## 当前仍在逐目标结算的卡牌上下文；键为原实体牌 UID，值保存目标游标、共享伤害参数与当前目标状态。
var _active_card_resolutions: Dictionary = {}

## 当前尚未完成 contentAfter 的 CardUseEvent 上下文；键为实体 UID，值保存事件 ID、使用者和最终区域。
var _card_use_contexts: Dictionary = {}

## 等待当前响应子事件完成后询问的银月枪触发队列；每项保存持有者和黑色实体牌 UID，不持有界面或事件对象引用。
var _queued_silver_moon_triggers: Array[Dictionary] = []

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


## 绑定场景中的解耦组件并初始化身份规则服务。
func _ready() -> void:
	event_bus = get_node("RuleEventBus") as RuleEventBus
	ai_coordinator = get_node("AICoordinator") as AICoordinator
	network_gateway = get_node("NetworkGateway") as NetworkGateway
	event_scheduler = get_node_or_null("EventScheduler") as EventScheduler
	if event_scheduler == null:
		event_scheduler = EventScheduler.new()
		event_scheduler.name = "EventScheduler"
		add_child(event_scheduler)
	_connect_event_runtime()
	identity_rules = IdentityRules.new()
	card_use_event_service = CardUseEventService.new()
	network_gateway.command_received.connect(_on_network_command_received)
	if not network_gateway.choice_response_received.is_connected(_on_network_choice_response_received):
		network_gateway.choice_response_received.connect(_on_network_choice_response_received)
	if not GameSettings.ai_response_delay_changed.is_connected(_on_ai_response_delay_changed):
		GameSettings.ai_response_delay_changed.connect(_on_ai_response_delay_changed)
	_on_ai_response_delay_changed(GameSettings.ai_response_delay_seconds)


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


## 创建并开始一局标准身份局；seed 为0时使用系统随机种子。
func start_match(player_count: int = -1, seed: int = 0) -> bool:
	# 实际玩家人数；未指定时使用检查器默认值，并限制在支持范围内。
	var actual_player_count: int = default_player_count if player_count < 0 else player_count
	if actual_player_count < 2 or actual_player_count > 10:
		action_rejected.emit("标准身份局仅支持2至10名玩家。")
		return false
	if not GameDatabase.validation_errors.is_empty():
		action_rejected.emit("数据配置校验失败：%s" % "；".join(GameDatabase.validation_errors))
		return false
	_uninstall_all_character_skills()
	_uninstall_all_card_runtimes()

	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	_assign_local_human_player_seat(actual_player_count)
	CardInstance._next_uid = 1
	state = GameState.new()
	state.match_id = "%d-%d" % [Time.get_unix_time_from_system(), _rng.randi()]
	state.random_seed = _rng.seed
	state.deck_id = default_deck_id
	card_rules = CardRuleService.new(state)
	effect_resolver = CardEffectResolver.new(self, state)
	card_movement = CardMovementService.new(state)
	_bind_card_movement_service()
	modifier_pipeline = RuleModifierPipeline.new()
	rule_query = RuleQuery.new(state, card_rules, modifier_pipeline)
	trigger_manager = TriggerManager.new()
	skill_instances_by_player.clear()
	card_runtime_instances.clear()
	event_scheduler.reset()
	# 根事件只保存规则启动元数据；后续身份、阶段和卡牌事件通过 parent_id 关联到该入口。
	var root_event: GameEvent = event_scheduler.create_event("RootGameEvent", "root", [], {"rules_snapshot":"noname-v1.10.16", "mode":"identity", "match_id":state.match_id, "deck_id":state.deck_id})
	_runtime_root_event_id = root_event.event_id
	event_scheduler.begin_root(_runtime_root_event_id, true)
	state.current_event_id = _runtime_root_event_id
	state.event_history = event_scheduler.get_event_history()
	character_selection = CharacterSelectionService.new()
	_ai_drive_token += 1
	_scheduled_ai_drive_token = -1
	_scheduled_ai_choice_request_id = -1
	_ai_actions_this_turn = 0
	_pending_card_choice.clear()
	_resolved_card_choice_uids.clear()
	_resolved_equipment_material_uids.clear()
	_negation_resume_results.clear()
	_active_card_resolutions.clear()
	_card_use_contexts.clear()
	_queued_silver_moon_triggers.clear()
	_current_turn_event_id = -1
	_play_choice_request_id = -1
	_play_choice_event_id = -1
	_play_choice_actor_id = -1
	_play_choice_match_id = ""
	_card_presentation_sequence = 0
	_judgment_flow_token += 1
	_judgment_flow_in_progress = false
	_judgment_resume_needs_result_pause = false
	ai_coordinator._policies.clear()

	_create_players(actual_player_count)
	_create_and_shuffle_deck()
	_record_runtime_event("identity.start", "mode", {"player_count":actual_player_count, "seed":seed})
	state.current_phase = "character_selection"
	# 可用武将 ID；服务只持有字符串副本，不接触全局配置的可修改引用。
	var available_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		available_character_ids.append(str(character_id_variant))
	# 选将初始化错误；空字符串表示主公候选已生成。
	var selection_error: String = character_selection.begin(state.players, available_character_ids, character_candidate_count, _rng)
	if not selection_error.is_empty():
		action_rejected.emit(selection_error)
		return false
	add_log("选将开始：主公先从%d张候选武将牌中选择并亮出。" % mini(character_candidate_count, available_character_ids.size()))
	_emit_state()
	_drive_ai_character_selection()
	return true


## 为本局分配有效的本地人类座次；随机模式使用对局随机源，固定模式把检查器配置限制到实际人数范围。
func _assign_local_human_player_seat(player_count: int) -> void:
	if local_human_player_id < 0:
		return
	local_human_player_id = _rng.randi_range(0, player_count - 1) if randomize_local_human_seat else clampi(local_human_player_id, 0, player_count - 1)


## 提交一名玩家的选将结果；所有人类、AI与网络入口共用相同阶段和候选校验。
func select_character(player_id: int, character_id: String) -> bool:
	if state == null or state.game_over or state.current_phase != "character_selection" or character_selection == null:
		return _reject("当前不在选将阶段。")
	# 选将服务返回的校验错误；空字符串表示选择已经记录并可能推进阶段。
	var selection_error: String = character_selection.select_character(player_id, character_id)
	if not selection_error.is_empty():
		return _reject(selection_error)
	state.action_sequence += 1
	state.random_history.append({"kind":"character_selection", "player_id":player_id, "character_id":character_id, "candidates":character_selection.get_candidates(player_id)})
	if player_id == character_selection.lord_player_id:
		# 主公选择立即写入并公开，其他玩家候选只会在此之后生成。
		var lord: PlayerState = state.get_player(player_id)
		_apply_character(lord, character_id, true)
		add_log("主公%s亮出武将【%s】。" % [lord.display_name, GameDatabase.resolve_character_name(character_id)])
		add_log("其他玩家开始同时选将，每人随机展示%d张候选武将牌。" % character_selection.candidate_count)
	if character_selection.phase == CharacterSelectionService.PHASE_COMPLETE:
		_finish_character_selection()
	else:
		_emit_state()
		if not _is_driving_character_selection:
			_drive_ai_character_selection()
	return true


## 接受来自人类、AI 或网络的统一行为指令；返回是否通过规则校验并执行。
func submit_action(action: PlayerAction) -> bool:
	if state == null or state.game_over:
		return _reject("当前没有可操作的进行中对局。")
	if action.action_type == "select_character":
		return select_character(action.actor_id, str(action.payload.get("character_id", "")))
	if action.action_type == "use_skill":
		return activate_skill(action.actor_id, str(action.payload.get("skill_id", "")), action.payload)
	if action.action_type == "choice_response":
		var choice_response: ChoiceResponse = ChoiceResponse.from_dict(action.payload)
		var choice_action: PlayerAction = PlayerAction.new("choose_cards", choice_response.actor_id)
		choice_action.client_sequence = choice_response.client_sequence
		choice_action.payload = {"request_id":choice_response.request_id, "event_id":choice_response.event_id, "selected_card_uids":choice_response.card_ids.duplicate()}
		return _submit_card_choice(choice_action)
	if action.action_type == "choose_cards":
		return _submit_card_choice(action)
	if action.actor_id != state.current_player_id:
		return _reject("行动者不是当前回合玩家。")
	if action.action_type in ["use_card", "use_zhangba", "recast_card", "store_wooden_ox", "end_play"]:
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
		_execute_card_use(action.actor_id, card, target_ids)
	elif action.action_type == "use_zhangba":
		# 丈八蛇矛材料 UID；动作负载只保存玩家按顺序选择的两张普通手牌。
		var zhangba_material_uids: Array[int] = _int_array(action.payload.get("material_card_uids", []) as Array)
		if not _execute_zhangba_slash_use(action.actor_id, action.card_uid, zhangba_material_uids, action.target_ids):
			return false
	elif action.action_type == "recast_card":
		if not _execute_recast(action.actor_id, action.card_uid):
			return false
	elif action.action_type == "store_wooden_ox":
		if not _execute_wooden_ox_store(action.actor_id, action.card_uid, action.target_ids):
			return false
	elif action.action_type == "end_play":
		_end_play_phase(action.actor_id)
	else:
		return _reject("未知行为类型：%s" % action.action_type)

	state.action_sequence += 1
	if action.action_type == "end_play":
		# 正常结束出牌已在 `_finish_turn()` 中开始下一回合并安排 AI；此处只补发递增后的快照，避免为新回合重复安排第二个 AI 任务。
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
	if not state.game_over and state.current_phase == "play" and ai_coordinator.is_ai_controlled(state.current_player_id):
		_schedule_ai_action()
	return true


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
		if str(definition.get("effect_id", "")) == "borrow_sword":
			_append_borrow_sword_actions(result, player_id, card)
			continue
		if target_mode == "all_players" or target_mode == "all_others":
			_append_if_legal(result, player_id, card, [])
			continue
		# 当前卡牌所有单目标候选；铁索连环当前基础 AI 先使用单目标形式。
		var legal_targets: Array[int] = card_rules.list_legal_targets(player_id, card)
		for target_id: int in legal_targets:
			_append_if_legal(result, player_id, card, [target_id])
	# 丈八蛇矛主动动作；AI 使用固定前两张普通手牌生成候选，玩家界面仍可在点击装备后自主选择任意两张材料。
	var zhangba_card: CardInstance = _get_equipment_card_by_definition(player_id, "zhangba")
	if zhangba_card != null and player.hand.size() >= 2:
		# 基础 AI 丈八材料；动作提交后仍会逐张复核当前手牌归属。
		var zhangba_material_uids: Array[int] = [player.hand[0].uid, player.hand[1].uid]
		for target_id: int in card_rules.list_legal_virtual_targets(player_id, "sha"):
			# 丈八目标组合；虚拟杀不应用方天画戟最后手牌修正，因此每项只有一名目标。
			var zhangba_targets: Array[int] = [target_id]
			if _validate_zhangba_slash(player_id, zhangba_card.uid, zhangba_material_uids, zhangba_targets).is_empty():
				result.append({"action_type":"use_zhangba", "actor_id":player_id, "card_uid":zhangba_card.uid, "target_ids":zhangba_targets, "card_definition_id":"sha", "payload":{"material_card_uids":zhangba_material_uids.duplicate()}})
	if player_has_equipment(player_id, "muniu") and not player.wooden_ox_used:
		for card: CardInstance in player.hand:
			result.append({"action_type":"store_wooden_ox", "actor_id":player_id, "card_uid":card.uid, "target_ids":[], "card_definition_id":"muniu_store"})
	return result


## 返回指定卡牌与当前目标顺序的只读交互预览，供 UI 展示合法目标、步骤提示与确认状态。
func get_card_use_preview(player_id: int, card_uid: int, selected_target_ids: Array[int] = []) -> Dictionary:
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
	# 下一步合法候选目标；候选会结合已有目标顺序验证，借刀杀人可正确区分第一与第二目标。
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


## 返回丈八蛇矛虚拟【杀】的只读交互预览；装备、两张材料和目标都会在每次刷新时重新校验。
func get_zhangba_slash_preview(player_id: int, equipment_uid: int, material_card_uids: Array[int], selected_target_ids: Array[int] = []) -> Dictionary:
	# 丈八预览默认结果；字段与普通出牌预览一致，使桌面目标高亮和确认按钮可以复用同一表现路径。
	var result: Dictionary = {
		"card_found": false,
		"can_submit": false,
		"validation_error": "当前不能发动丈八蛇矛。",
		"legal_target_ids": [],
		"normalized_target_ids": selected_target_ids.duplicate(),
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"description": str(GameDatabase.get_card("zhangba").get("description", "")),
	}
	if state == null or state.game_over:
		return result
	# 材料与装备错误；即使尚未选满两张，也继续返回合法目标为空的明确预览，不开放提前提交。
	var material_error: String = _validate_zhangba_materials(player_id, equipment_uid, material_card_uids)
	result["card_found"] = material_error.is_empty()
	if not material_error.is_empty():
		result["validation_error"] = material_error
		return result
	# 当前完整目标组合；普通虚拟杀只有一个手动目标，不需要全体目标规范化。
	var validation_error: String = card_rules.validate_virtual_use(player_id, "sha", selected_target_ids)
	result["validation_error"] = validation_error
	result["can_submit"] = validation_error.is_empty()
	# 合法目标列表；已选择目标时仍保留其他候选，允许一次点击直接切换单目标。
	var legal_target_ids: Array[int] = []
	for target_id: int in card_rules.list_legal_virtual_targets(player_id, "sha"):
		if card_rules.validate_virtual_use(player_id, "sha", [target_id]).is_empty():
			legal_target_ids.append(target_id)
	result["legal_target_ids"] = legal_target_ids
	return result


## 返回当前出牌阶段可以直接点击发动的装备实体 UID；结果只供界面候选位移和 chooseToUse 请求使用。
func get_play_phase_equipment_action_uids(player_id: int) -> Array[int]:
	# 可点击装备结果；装备条件不满足时保持空数组。
	var result: Array[int] = []
	if state == null or state.game_over or state.current_player_id != player_id or state.current_phase != "play":
		return result
	# 当前玩家；丈八需要至少两张普通手牌，木牛需要至少一张普通手牌且本阶段尚未发动。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return result
	# 当前丈八蛇矛；只要至少存在一个合法杀目标就允许进入材料选择模式。
	var zhangba_card: CardInstance = _get_equipment_card_by_definition(player_id, "zhangba")
	if zhangba_card != null and player.hand.size() >= 2:
		for target_id: int in card_rules.list_legal_virtual_targets(player_id, "sha"):
			if card_rules.validate_virtual_use(player_id, "sha", [target_id]).is_empty():
				result.append(zhangba_card.uid)
				break
	# 当前木牛流马；存粮每阶段限一次，并且只能选择普通手牌作为“粮”。
	var wooden_ox_card: CardInstance = _get_equipment_card_by_definition(player_id, "muniu")
	if wooden_ox_card != null and not player.wooden_ox_used and not player.hand.is_empty():
		result.append(wooden_ox_card.uid)
	return result


## 返回当前是否存在等待玩家或 AI 提交的选择窗口；效果执行器据此暂停后续结算。
func has_pending_card_choice() -> bool:
	return not _pending_card_choice.is_empty()


## 为当前角色创建可持续的 chooseToUse 请求；候选只包含当前仍可使用或重铸的实体牌 UID。
func _begin_play_choice(player_id: int) -> void:
	if state == null or state.game_over or state.current_phase != "play" or state.current_player_id != player_id:
		return
	if _has_active_play_choice():
		return
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		return
	var event: GameEvent = event_scheduler.create_event("chooseToUse", "choice", [], {"player_id":player_id, "phase":"play"}, _runtime_root_event_id)
	event.player_id = player_id
	var request: ChoiceRequest = ChoiceRequest.new(event.event_id, player_id, "use", "请选择要使用的牌或结束出牌阶段")
	request.min_count = 0
	request.max_count = 1
	request.can_cancel = true
	request.forced = false
	request.base_context = {"phase":"play", "action_types":["use_card", "use_zhangba", "recast_card", "store_wooden_ox", "end_play"]}
	request.active_context = request.base_context.duplicate(true)
	for legal_action: Dictionary in get_legal_actions(player_id):
		var candidate_uid: int = int(legal_action.get("card_uid", -1))
		if candidate_uid >= 0 and not request.card_ids.has(candidate_uid):
			request.card_ids.append(candidate_uid)
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
	if action.action_type != "end_play":
		response.card_ids = [action.card_uid]
	response.target_ids = action.target_ids.duplicate()
	response.client_sequence = action.client_sequence
	response.source = "ai" if ai_coordinator.is_ai_controlled(action.actor_id) else ("network" if network_gateway.mode != NetworkGateway.Mode.OFFLINE else "local")
	if not event_scheduler.submit_choice(response):
		return _reject("当前出牌选择已经失效或所选卡牌不合法。")
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
	if action.action_type == "use_zhangba":
		# 丈八材料 UID；负载必须提供两张普通手牌，不能用木牛“粮”或装备替代。
		var material_card_uids: Array[int] = _int_array(action.payload.get("material_card_uids", []) as Array)
		return _validate_zhangba_slash(action.actor_id, action.card_uid, material_card_uids, action.target_ids)
	if action.action_type == "recast_card":
		var recast_card: CardInstance = actor.find_hand_card(action.card_uid)
		if recast_card == null or not bool(GameDatabase.get_card(recast_card.definition_id).get("recast", false)):
			return "该卡牌当前不能重铸。"
		return ""
	if action.action_type == "store_wooden_ox":
		if not player_has_equipment(action.actor_id, "muniu") or actor.wooden_ox_used or actor.find_hand_card(action.card_uid) == null:
			return "当前不能把该手牌存入木牛流马。"
		if action.target_ids.size() > 1:
			return "木牛流马最多转移给一名其他角色。"
		if action.target_ids.size() == 1:
			var target: PlayerState = state.get_player(action.target_ids[0])
			if target == null or not target.alive or target.player_id == action.actor_id:
				return "木牛流马转移目标不合法。"
		return ""
	return "未知行为类型：%s" % action.action_type


## 创建统一选牌请求；AI 与本地玩家收到完全相同的候选快照，并通过 choose_cards 动作提交结果。
func request_card_choice(chooser_id: int, title: String, prompt: String, candidates: Array[Dictionary], min_select: int, max_select: int, allow_cancel: bool, context: Dictionary) -> Array[int]:
	if state == null or state.game_over or not _pending_card_choice.is_empty():
		return []
	_resolved_card_choice_uids.clear()
	_resolved_equipment_material_uids.clear()
	# 请求创建前的规则阶段；选择提交后必须恢复，避免把响应窗口误当作新的回合阶段。
	var resume_phase: String = state.current_phase
	# 候选只读副本；UI 和 AI 只能看到请求明确公开的牌面，不能取得 CardInstance 引用。
	var serialized_candidates: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		serialized_candidates.append(candidate.duplicate(true))
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
		"min_select":maxi(min_select, 0),
		"max_select":maxi(max_select, min_select),
		"allow_cancel":allow_cancel,
		"resume_phase":resume_phase,
		"context":context.duplicate(true),
		"deferred":interactive_human or ai_controlled_chooser,
	}
	# 选择事件名称；响应、弃牌和普通选牌使用稳定名称，便于触发器与回放区分。
	var choice_type: String = "card"
	var choice_event_name: String = "chooseCard"
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind.contains("response") or choice_kind in ["duel_response", "trick_negation"]:
		choice_type = "respond"
		choice_event_name = "chooseToRespond"
	elif choice_kind == "discard_phase":
		choice_type = "discard"
		choice_event_name = "chooseToDiscard"
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
	runtime_request.forced = not allow_cancel
	runtime_request.can_cancel = allow_cancel
	runtime_request.base_context = context.duplicate(true)
	runtime_request.active_context = context.duplicate(true)
	for candidate: Dictionary in serialized_candidates:
		runtime_request.card_ids.append(int(candidate.get("uid", -1)))
	# 选择请求必须使用事件调度器分配的全局 ID；控制器自有序号不能与 chooseToUse 或其他请求共用命名空间。
	var registered_request: ChoiceRequest = event_scheduler.request_choice(runtime_request)
	if registered_request == null:
		# 登记失败时撤销临时事件并清空待处理状态，禁止界面显示无法提交的假窗口。
		_pending_card_choice.clear()
		choice_event.abort("choice_registration_failed")
		return []
	runtime_request = registered_request
	_card_choice_sequence = runtime_request.request_id
	_pending_card_choice["request_id"] = runtime_request.request_id
	_pending_card_choice["runtime_event_id"] = choice_event.event_id
	_pending_card_choice["runtime_request_id"] = runtime_request.request_id
	state.current_phase = "choice"
	card_choice_requested.emit(_pending_card_choice.duplicate(true))
	# 当前调用不在调度器内容步骤内时立即把选择子事件压栈；调度中重入 drain 会安全返回并由外层循环接管。
	event_scheduler.drain()
	if interactive_human:
		return []
	if ai_controlled_chooser:
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
		ai_action.payload = {"request_id":int(_pending_card_choice.get("request_id", runtime_request.request_id)), "event_id":ai_response.event_id, "selected_card_uids":ai_response.card_ids.duplicate()}
		action_data = ai_action.to_dict()
	if action_data.is_empty() or not submit_action(PlayerAction.from_dict(action_data)):
		# 合法动作正常非空；防御性回退按最少数量提交首批候选，保证纯 AI 对局不会停滞。
		var fallback_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		fallback_action.payload = {
			"request_id":int(_pending_card_choice.get("request_id", runtime_request.request_id)),
			"selected_card_uids":_first_candidate_uids(serialized_candidates, maxi(min_select, 0)),
		}
		submit_action(fallback_action)
	return _resolved_card_choice_uids.duplicate()


## 安排一条 AI 选牌响应；与普通 AI 出牌共用延迟参数，但使用请求 ID 防止旧窗口在新请求中误提交。
func _schedule_ai_card_choice_response(request_id: int, chooser_id: int) -> void:
	if request_id < 0 or _scheduled_ai_choice_request_id == request_id:
		return
	# 当前阶段令牌；重开、换回合或终局后旧响应不会继续提交到新状态。
	var token: int = _ai_drive_token
	_scheduled_ai_choice_request_id = request_id
	_run_ai_card_choice_after_delay(request_id, chooser_id, token)


## 等待设置的响应时间后提交 AI 选择；决策和最终提交仍复用与玩家完全一致的标准动作入口。
func _run_ai_card_choice_after_delay(request_id: int, chooser_id: int, token: int) -> void:
	await get_tree().create_timer(ai_action_delay_seconds).timeout
	if _scheduled_ai_choice_request_id == request_id:
		_scheduled_ai_choice_request_id = -1
	if token != _ai_drive_token or state == null or state.game_over or _pending_card_choice.is_empty():
		return
	if int(_pending_card_choice.get("request_id", -1)) != request_id or int(_pending_card_choice.get("chooser_id", -1)) != chooser_id or not ai_coordinator.is_ai_controlled(chooser_id):
		return
	# 当前运行时请求；待选快照使用 chooser_id/runtime_event_id 字段，恢复时显式映射到 ChoiceRequest 的 actor_id/event_id 协议。
	var runtime_request: ChoiceRequest = ChoiceRequest.new(int(_pending_card_choice.get("runtime_event_id", -1)), chooser_id, "card", str(_pending_card_choice.get("prompt", "")))
	# 当前请求稳定 ID；策略生成的 ChoiceResponse 必须携带此 ID，避免迟到响应误命中新窗口。
	runtime_request.request_id = request_id
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
		ai_action.payload = {"request_id":request_id, "event_id":ai_response.event_id, "selected_card_uids":ai_response.card_ids.duplicate()}
		action_data = ai_action.to_dict()
	if not action_data.is_empty() and submit_action(PlayerAction.from_dict(action_data)):
		return
	# 回退选择数量；强制请求选择最少张数，可取消请求提交空选择，避免 AI 在异常策略返回时永久停滞。
	var fallback_count: int = maxi(int(_pending_card_choice.get("min_select", 0)), 0)
	# 回退动作；只从仍活动请求的候选 UID 构造，始终经过 submit_action 的权威校验。
	var fallback_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
	fallback_action.payload = {"request_id":request_id, "selected_card_uids":_first_candidate_uids(_pending_card_choice.get("candidates", []) as Array, fallback_count)}
	submit_action(fallback_action)


## 枚举选择请求的基础合法动作；单选逐张枚举，多选为基础 AI 提供满足最少数量的稳定组合。
func _build_card_choice_actions(choice_request: Dictionary) -> Array[Dictionary]:
	# 合法动作结果；所有动作共享当前请求 ID 以防跨窗口提交。
	var result: Array[Dictionary] = []
	# 请求最少选择数；为0时允许显式放弃。
	var min_select: int = int(choice_request.get("min_select", 0))
	# 请求最多选择数；单选请求会为每张候选生成一个动作。
	var max_select: int = int(choice_request.get("max_select", 0))
	# 请求序号；提交时由控制器再次核对。
	var request_id: int = int(choice_request.get("request_id", -1))
	# 选择者 ID；动作必须由被询问角色发出。
	var chooser_id: int = int(choice_request.get("chooser_id", -1))
	# 序列化候选；只读取稳定 UID。
	var candidates: Array = choice_request.get("candidates", []) as Array
	if min_select == 0:
		var pass_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		pass_action.payload = {"request_id":request_id, "selected_card_uids":[]}
		result.append(pass_action.to_dict())
	if max_select == 1:
		for candidate_variant: Variant in candidates:
			# 当前候选牌；每张牌对应一个可校验的单选动作。
			var candidate: Dictionary = candidate_variant as Dictionary
			var select_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
			select_action.payload = {"request_id":request_id, "selected_card_uids":[int(candidate.get("uid", -1))]}
			result.append(select_action.to_dict())
	elif min_select > 0 and candidates.size() >= min_select:
		var required_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		required_action.payload = {"request_id":request_id, "selected_card_uids":_first_candidate_uids(candidates, min_select)}
		result.append(required_action.to_dict())
	elif min_select == 0 and max_select > 1 and bool((choice_request.get("context", {}) as Dictionary).get("ai_prefer_select", false)) and candidates.size() == max_select:
		# 可选整组动作；水淹七军等规则只有完整选择才算执行弃置分支。
		var all_action: PlayerAction = PlayerAction.new("choose_cards", chooser_id)
		all_action.payload = {"request_id":request_id, "selected_card_uids":_first_candidate_uids(candidates, max_select)}
		result.append(all_action.to_dict())
	return result


## 返回候选数组前指定数量的 UID；只用于生成仍需权威校验的基础 AI 动作。
func _first_candidate_uids(candidates: Array, count: int) -> Array[int]:
	# UID 结果；数量不会超过候选总数。
	var result: Array[int] = []
	for index: int in range(mini(maxi(count, 0), candidates.size())):
		result.append(int((candidates[index] as Dictionary).get("uid", -1)))
	return result


## 校验并接受统一选牌动作；同步 AI 返回给调用栈，人类和网络提交则恢复暂停的规则上下文。
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
	# 最少与最多数量；取消只等价于提交0张且必须由请求明确允许。
	var min_select: int = int(_pending_card_choice.get("min_select", 0))
	var max_select: int = int(_pending_card_choice.get("max_select", 0))
	var allow_cancel: bool = bool(_pending_card_choice.get("allow_cancel", false))
	if selected_uids.size() < min_select and not (selected_uids.is_empty() and allow_cancel):
		return _reject("选择的牌数不足。")
	if selected_uids.size() > max_select:
		return _reject("选择的牌数超过上限。")
	# 已完成请求上下文；运行时确认接收后再清空窗口，避免失败响应把仍可重试的权威请求提前丢失。
	var completed_choice: Dictionary = _pending_card_choice.duplicate(true)
	# 装备响应材料；普通选牌保持空数组，选择丈八蛇矛响应【杀】时必须额外提交两张普通手牌 UID。
	var equipment_material_uids: Array[int] = []
	if selected_uids.size() == 1 and _is_zhangba_response_selection(completed_choice, selected_uids[0]):
		equipment_material_uids = _int_array(action.payload.get("material_card_uids", []) as Array)
		if equipment_material_uids.is_empty() and ai_coordinator.is_ai_controlled(action.actor_id):
			# AI 丈八材料；基础策略没有专门的二次材料界面，因此按当前手牌顺序选择前两张并继续走相同权威校验。
			var ai_player: PlayerState = state.get_player(action.actor_id)
			if ai_player != null and ai_player.hand.size() >= 2:
				equipment_material_uids.assign([ai_player.hand[0].uid, ai_player.hand[1].uid])
		# 丈八响应材料错误；请求保持活动，玩家仍可重新选择两张合法手牌后提交。
		var material_error: String = _validate_zhangba_materials(action.actor_id, selected_uids[0], equipment_material_uids)
		if not material_error.is_empty():
			return _reject(material_error)
		# 已完成请求的恢复上下文；只保存实体 UID 数组，效果恢复不会持有界面状态或卡牌对象。
		var completed_context: Dictionary = (completed_choice.get("context", {}) as Dictionary).duplicate(true)
		completed_context["equipment_material_uids"] = equipment_material_uids.duplicate()
		completed_choice["context"] = completed_context
	# 通用运行时响应；AI、本地和网络使用完全相同的 ChoiceResponse 字段与权威候选校验。
	var runtime_response: ChoiceResponse = ChoiceResponse.new(
		int(completed_choice.get("runtime_request_id", completed_choice.get("request_id", -1))),
		int(completed_choice.get("runtime_event_id", -1)),
		action.actor_id,
		not selected_uids.is_empty() or min_select > 0
	)
	runtime_response.card_ids = selected_uids.duplicate()
	runtime_response.client_sequence = action.client_sequence
	runtime_response.source = "ai" if ai_coordinator.is_ai_controlled(action.actor_id) else ("network" if network_gateway.mode != NetworkGateway.Mode.OFFLINE else "local")
	# 先解决选择自身 token 但延迟排空事件栈；具体效果必须应用选择结果后才能继续父 content 事件。
	if not event_scheduler.submit_choice(runtime_response, true):
		return _reject("事件运行时拒绝了已过期的选择结果。")
	_pending_card_choice.clear()
	state.current_phase = str(completed_choice.get("resume_phase", "play"))
	_resolved_card_choice_uids = selected_uids.duplicate()
	_resolved_equipment_material_uids = equipment_material_uids.duplicate()
	state.action_sequence += 1
	if bool(completed_choice.get("deferred", false)):
		_continue_card_choice(completed_choice.get("context", {}) as Dictionary, selected_uids)
		if not state.game_over and not has_pending_card_choice():
			_process_next_silver_moon_trigger()
		if not state.game_over and not has_pending_card_choice():
			_resume_interrupted_turn_flow()
	# 没有卡牌内容 token 的阶段级选择也必须在结果应用后完成其选择事件并恢复父事件。
	event_scheduler.drain()
	if bool(completed_choice.get("deferred", false)):
		# 新的 chooseToUse 必须等原 CardUseEvent 及其后续目标全部排空后再创建，避免后续响应覆盖已经提前发布的出牌请求快照。
		if not state.game_over and state.current_phase == "play" and not has_pending_card_choice():
			_begin_play_choice(state.current_player_id)
		_emit_state()
		# AI 出牌被本地响应或选择暂停后，原异步驱动已经结束；恢复出牌阶段时必须重新安排下一动作。
		if not state.game_over and state.current_phase == "play" and ai_coordinator.is_ai_controlled(state.current_player_id) and not has_pending_card_choice():
			_schedule_ai_action()
	return true


## 根据暂停上下文恢复具体效果；各分支只调用公开规则操作，不读取任何 UI 节点。
func _continue_card_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 选择用途；由创建请求的规则函数写入稳定字符串。
	var choice_kind: String = str(context.get("kind", ""))
	# 卡牌自有选择恢复；父牌源码优先识别其创建的 kind，控制器只保留阶段与全局系统选择。
	if effect_resolver.continue_choice(context, selected_uids):
		return
	if choice_kind == "discard_phase":
		_continue_discard_phase_choice(context, selected_uids)
	elif choice_kind == "discard_target":
		_continue_target_card_choice(context, selected_uids, false)
	elif choice_kind == "steal_target":
		_continue_target_card_choice(context, selected_uids, true)
	elif choice_kind == "slash_response":
		_continue_slash_response_choice(context, selected_uids)
	elif choice_kind == "silver_moon_response":
		_continue_silver_moon_choice(context, selected_uids)
	elif choice_kind == "aoe_response":
		_continue_aoe_response_choice(context, selected_uids)
	elif choice_kind == "borrow_sword_response":
		_continue_borrow_sword_choice(context, selected_uids)
	elif choice_kind == "dying_response":
		_continue_dying_choice(context, selected_uids)
	elif choice_kind == "qinglong_response":
		_continue_qinglong_choice(context, selected_uids)
	elif choice_kind == "duel_response":
		_continue_duel_choice(context, selected_uids)
	elif choice_kind == "trick_negation":
		_continue_trick_negation_choice(context, selected_uids)
	elif choice_kind == "zhuque_trigger":
		_continue_zhuque_trigger_choice(context, selected_uids)
	elif choice_kind == "silver_moon_trigger":
		_continue_silver_moon_trigger_choice(context, selected_uids)


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
	_ensure_card_movement()
	# 实际摸牌数量；可能因牌堆与弃牌堆同时为空而少于请求值。
	var drawn_count: int = 0
	for _index: int in range(maxi(count, 0)):
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
			card_movement.move_card(card, "hand", player_id, "draw", state.current_event_id, "", [player_id])
		else:
			state.draw_pile.pop_back()
			card.zone = "hand"
			card.owner_id = player_id
			player.hand.append(card)
		drawn_count += 1
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
	# 回复前体力；用于计算实际回复量并记录准确数值。
	var previous_hp: int = target.hp
	target.hp = mini(target.max_hp, target.hp + amount)
	_record_runtime_event("recover", "recover", {"source_id":source_id, "target_id":target_id, "requested_amount":amount, "reason":reason}, {"amount":target.hp - previous_hp, "hp":target.hp})
	add_log("%s回复%d点体力（%d/%d）。" % [target.display_name, target.hp - previous_hp, target.hp, target.max_hp])
	# 回复后事件；技能可读取来源、目标、实际回复值与原因牌。
	var event: RuleEvent = RuleEvent.new("recover_after", source_id, target_id, {"amount": target.hp - previous_hp, "reason": reason})
	_dispatch_rule_event(event)


## 造成伤害并执行防具修正、濒死、死亡及属性连环传导。
func damage(source_id: int, target_id: int, amount: int, nature: String = "normal", card_id: String = "", chain_transfer: bool = false, ignore_armor: bool = false) -> void:
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
	for damage_begin_index: int in range(1, 5):
		_record_runtime_event("damageBegin%d" % damage_begin_index, "trigger", {"source_id":source_id, "target_id":target_id, "amount":final_amount}, {}, damage_event_id)
	# 伤害修正上下文；装备源码只读取稳定规则字段，不依赖控制器内部局部变量。
	var equipment_damage_context: Dictionary = {"source_id":source_id, "target_id":target_id, "nature":nature, "card_id":card_id, "chain_transfer":chain_transfer}
	# 伤害来源状态；其武器可覆盖造成伤害修正钩子。
	var equipment_damage_source: PlayerState = state.get_player(source_id) if source_id >= 0 else null
	if equipment_damage_source != null:
		# 来源武器定义；不存在武器或定义缺失时不修改伤害。
		var source_weapon_definition: CardDefinition = get_equipment_definition(source_id, "weapon")
		if source_weapon_definition != null:
			final_amount = source_weapon_definition.modify_outgoing_damage(self, equipment_damage_source, target, equipment_damage_context, final_amount)
	if not ignore_armor:
		# 目标防具定义；具体伤害压缩或属性增伤由防具卡牌源码提供。
		var target_armor_definition: CardDefinition = get_equipment_definition(target_id, "armor")
		if target_armor_definition != null:
			final_amount = target_armor_definition.modify_incoming_damage(self, target, equipment_damage_context, final_amount)

	# 伤害前事件；处理器可修改 amount 或取消整次伤害。
	var before_event: RuleEvent = RuleEvent.new("damage_before", source_id, target_id, {"amount": final_amount, "nature": nature, "card_id": card_id, "chain_transfer": chain_transfer})
	_dispatch_rule_event(before_event)
	if state.game_over or before_event.cancelled:
		return
	final_amount = maxi(int(before_event.data.get("amount", final_amount)), 0)
	if final_amount == 0:
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

	target.hp -= final_amount
	_record_runtime_event("damage", "damage", {"source_id":source_id, "target_id":target_id, "nature":nature}, {"amount":final_amount, "hp":target.hp}, damage_event_id)
	target.damage_history.append({"event_id":damage_event_id, "source_id":source_id, "target_id":target_id, "amount":final_amount, "nature":nature})
	var source_player: PlayerState = state.get_player(source_id)
	if source_player != null and source_player != target:
		source_player.damage_history.append({"event_id":damage_event_id, "source_id":source_id, "target_id":target_id, "amount":final_amount, "nature":nature})
	if target.chained and nature != "normal":
		target.chained = false
	add_log("%s受到%d点%s伤害（%d/%d）。" % [target.display_name, final_amount, _nature_text(nature), target.hp, target.max_hp])
	# 伤害后事件；在濒死前触发，允许技能依据已扣减体力进行处理。
	var after_event: RuleEvent = RuleEvent.new("damage_after", source_id, target_id, {"amount": final_amount, "nature": nature, "card_id": card_id, "chain_transfer": chain_transfer})
	_dispatch_rule_event(after_event)
	if state.game_over:
		return
	if target.hp <= 0:
		_resolve_dying(target_id, source_id)
	_record_runtime_event("damageSource", "trigger", {"source_id":source_id, "target_id":target_id, "amount":final_amount}, {}, damage_event_id)
	if state.game_over:
		return
	for chained_target_id: int in chain_targets:
		# 传导前再次检查角色仍存活且横置，避免前序死亡结算改变有效目标。
		var chained_target: PlayerState = state.get_player(chained_target_id)
		if chained_target != null and chained_target.alive and chained_target.chained:
			damage(source_id, chained_target_id, final_amount, nature, card_id, true, false)


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
	# 可响应候选；手牌与木牛“粮”都按实际 UID 提供给本人，规则定义决定是否匹配响应模式。
	var candidates: Array[Dictionary] = []
	for card: CardInstance in player.get_playable_cards():
		# 当前候选定义；普通杀与属性杀可共享 sha 响应模式。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id)
		if allowed_patterns.has(_get_provided_response_pattern(definition)):
			candidates.append(_serialize_choice_candidate(card, player_id, card.zone, true))
	# 丈八蛇矛响应候选；装备只作为发动入口，不会离开装备区，确认时还必须提交两张普通手牌材料。
	var zhangba_card: CardInstance = _get_equipment_card_by_definition(player_id, "zhangba")
	if allowed_patterns.has("sha") and zhangba_card != null and player.hand.size() >= 2:
		candidates.append(_serialize_choice_candidate(zhangba_card, player_id, "equipment", true, "weapon"))
	# 完整响应上下文；恢复回调使用同一模式集合校验实体牌，不能由客户端自行声明所选牌的响应类型。
	var response_context: Dictionary = context.duplicate(true)
	response_context["response_patterns"] = allowed_patterns.duplicate()
	# 响应允许主动不出牌；即使候选为空也创建请求，保证 AI 与真实玩家经历相同问询。
	var selected_uids: Array[int] = request_card_choice(player_id, "响应询问", prompt, candidates, 0, 1, true, response_context)
	if has_pending_card_choice() or selected_uids.is_empty():
		return null
	return _consume_response_card_uid_patterns(player_id, selected_uids[0], allowed_patterns, _resolved_equipment_material_uids)


## 按选择请求提交的 UID 消耗响应牌；再次校验区域和响应模式后进入弃牌堆并播放动画。
func _consume_response_card_uid(player_id: int, card_uid: int, response_pattern: String) -> CardInstance:
	return _consume_response_card_uid_patterns(player_id, card_uid, [response_pattern])


## 按候选响应模式集合消耗一张实体牌；用于【桃】与【酒】等共享时机但牌名不同的单一询问窗口。
func _consume_response_card_uid_patterns(player_id: int, card_uid: int, response_patterns: Array[String], equipment_material_uids: Array[int] = []) -> CardInstance:
	# 响应玩家；请求等待期间其牌区可能被插入结算改变，因此必须重新查询。
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null
	# 丈八蛇矛装备响应；装备 UID 只表示发动入口，实际消耗由两张经过请求校验的普通手牌承担。
	var equipped_zhangba: CardInstance = _get_equipment_card_by_definition(player_id, "zhangba")
	if response_patterns.has("sha") and equipped_zhangba != null and equipped_zhangba.uid == card_uid:
		return _consume_zhangba_response(player_id, equipment_material_uids)
	# 被选响应牌；只能来自当前仍可使用的牌源。
	var card: CardInstance = player.find_playable_card(card_uid)
	if card == null:
		return null
	# 响应定义；模式不匹配时拒绝消费，防止旧请求或伪造动作改变状态。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 实体牌实际响应模式；日志与历史必须记录牌自身能提供的模式，不能把普通锦囊的受响应字段当作无懈牌能力。
	var response_pattern: String = _get_provided_response_pattern(definition)
	if not response_patterns.has(response_pattern):
		return null
	# 是否为实际手牌；银月枪只由回合外使用或打出的黑色手牌触发。
	var was_hand_card: bool = player.hand.has(card)
	# 实际消耗牌；take_playable_card 同时支持普通手牌与木牛“粮”。
	var consumed: CardInstance = player.take_playable_card(card.uid)
	_move_to_discard(consumed)
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":response_pattern, "card_uid":consumed.uid}, {"responded":true})
	player.response_history.append({"event_id":respond_event_id, "response_pattern":response_pattern, "card_uid":consumed.uid})
	add_log("%s打出了%s。" % [player.display_name, describe_card(consumed)])
	_resolve_silver_moon_trigger(player.player_id, consumed, was_hand_card)
	return consumed


## 返回一张牌实际能够提供的响应模式；映射基于牌效语义，避免所有可被无懈的普通锦囊都被误当成【无懈可击】。
func _get_provided_response_pattern(definition: Dictionary) -> String:
	# 卡牌文件显式提供的响应模式；新增响应牌只需在自身源码元数据中填写该字段。
	var configured_pattern: String = str(definition.get("provided_response_pattern", ""))
	if not configured_pattern.is_empty():
		return configured_pattern
	# 卡牌效果 ID；属性杀共享 slash，桃、酒、闪和无懈各自映射到唯一响应模式。
	var effect_id: String = str(definition.get("effect_id", ""))
	return str(PROVIDED_RESPONSE_PATTERN_BY_EFFECT.get(effect_id, ""))


## 恢复延迟的【闪】选择；放弃时继续受击，选择实体牌时先完成响应弃牌动画。
func _continue_slash_response_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 响应者 ID；即原【杀】目标。
	var responder_id: int = int(context.get("target_id", -1))
	# 实际响应牌；空选择代表明确不出【闪】。
	var response_card: CardInstance
	if not selected_uids.is_empty():
		response_card = _consume_response_card_uid(responder_id, selected_uids[0], "shan")
	if has_pending_card_choice():
		return
	if state.game_over:
		return
	effect_resolver.continue_response(context, response_card)
	if has_pending_card_choice():
		return
	if state.game_over:
		return
	_complete_active_card_target(int(context.get("parent_card_uid", -1)))
	_check_game_over()


## 恢复银月枪响应选择；无闪时造成伤害，有闪时只完成响应弃牌。
func _continue_silver_moon_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 银月枪持有者；作为伤害来源保留稳定玩家 ID。
	var owner_id: int = int(context.get("owner_id", -1))
	# 响应目标；空选择表示明确不出闪。
	var target_id: int = int(context.get("responder_id", -1))
	var response_card: CardInstance
	if not selected_uids.is_empty():
		response_card = _consume_response_card_uid(target_id, selected_uids[0], "shan")
	if response_card == null and not state.game_over:
		damage(owner_id, target_id, 1, "normal", "yinyue")


## 恢复群体锦囊响应选择；当前目标完成后由活动目标游标继续下一名角色，全部目标结束后才移出原锦囊。
func _continue_aoe_response_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 响应目标；无闪时承受群体锦囊伤害。
	var target_id: int = int(context.get("responder_id", -1))
	# 实际响应牌；空选择表示目标明确放弃响应。
	var response_card: CardInstance
	if not selected_uids.is_empty():
		response_card = _consume_response_card_uid_patterns(target_id, selected_uids[0], [str(context.get("pattern", "shan"))], _int_array(context.get("equipment_material_uids", []) as Array))
	effect_resolver.continue_response(context, response_card)
	if not state.game_over:
		_complete_active_card_target(int(context.get("parent_card_uid", -1)))


## 恢复借刀杀人响应；打出【杀】时执行目标伤害，否则交出武器。
func _continue_borrow_sword_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 被借刀者；响应牌必须仍属于该玩家。
	var holder_id: int = int(context.get("responder_id", -1))
	# 实际响应【杀】；空选择表示持刀者交出武器。
	var slash: CardInstance
	if not selected_uids.is_empty():
		slash = _consume_response_card_uid_patterns(holder_id, selected_uids[0], ["sha"], _int_array(context.get("equipment_material_uids", []) as Array))
	effect_resolver.continue_response(context, slash)


## 恢复青龙偃月刀追击选择；选择【杀】时继续攻击同一目标，放弃时结束原【杀】。
func _continue_qinglong_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 武器持有者；追击牌必须仍属于该角色。
	var actor_id: int = int(context.get("responder_id", -1))
	# 实际追击【杀】；空选择表示放弃发动。
	var follow_slash: CardInstance
	if not selected_uids.is_empty():
		follow_slash = _consume_response_card_uid_patterns(actor_id, selected_uids[0], ["sha"], _int_array(context.get("equipment_material_uids", []) as Array))
	if not has_pending_card_choice():
		effect_resolver.continue_response(context, follow_slash)
	if not state.game_over and not has_pending_card_choice():
		_complete_active_card_target(int(context.get("parent_card_uid", -1)))


## 恢复决斗中的一轮【杀】响应；成功响应后交换双方，放弃时由对手造成1点普通伤害。
func _continue_duel_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 当前响应者；所选牌必须仍属于该角色。
	var responder_id: int = int(context.get("responder_id", -1))
	# 本轮响应【杀】；空选择表示决斗失败。
	var response_slash: CardInstance
	if not selected_uids.is_empty():
		response_slash = _consume_response_card_uid_patterns(responder_id, selected_uids[0], ["sha"], _int_array(context.get("equipment_material_uids", []) as Array))
	if has_pending_card_choice():
		return
	effect_resolver.continue_response(context, response_slash)
	if not state.game_over and not has_pending_card_choice():
		_complete_active_card_target(int(context.get("parent_card_uid", -1)))


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
		if counter_card != null:
			final_negated = not final_negated
			add_log("%s使用【无懈可击】，当前锦囊%s。" % [state.get_player(responder_id).display_name, "被抵消" if final_negated else "恢复生效"])
	if has_pending_card_choice() or state.game_over:
		return
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
	# 当前无懈状态对象；按已有响应顺序重建，确保异步上下文与独立状态类使用同一奇偶规则。
	var wuxie_state: WuxieChainState = WuxieChainState.new(int(context.get("root_event_id", state.current_event_id)))
	for response_variant: Variant in response_results:
		# 单次历史响应；重建时逐项翻转状态并保留原始可序列化字段。
		var response_result: Dictionary = response_variant as Dictionary
		wuxie_state.add_response(int(response_result.get("player_id", -1)), response_result)
	_record_runtime_event("WuxieChainState", "response", {"trick_id":str(context.get("trick_id", "")), "target_id":int(context.get("target_id", -1))}, wuxie_state.to_dict())


## 从当前游标继续询问无懈可击；返回 pending 表示等待选择，返回完成结果表示本轮所有角色均已放弃。
func _advance_trick_negation_chain(context: Dictionary) -> Dictionary:
	# 固定行动顺序玩家 ID；每次成功无懈会把游标归零，但不会改变本次目标的座次基准。
	var response_order_ids: Array = context.get("response_order_ids", []) as Array
	# 当前轮下一名待询问角色索引；成功无懈后从0重新开始，放弃后递增。
	var response_index: int = int(context.get("response_index", 0))
	while response_index < response_order_ids.size() and not state.game_over:
		# 当前候选响应者；死亡或已经没有无懈可击时直接越过，不创建空窗口。
		var responder_id: int = int(response_order_ids[response_index])
		var responder: PlayerState = state.get_player(responder_id)
		if responder == null or not responder.alive or _find_hand_card_by_definition(responder, "wuxie") == null:
			response_index += 1
			context["response_index"] = response_index
			continue
		context["responder_id"] = responder_id
		context["response_index"] = response_index
		context["ai_prefer_select"] = _should_auto_negate(responder, int(context.get("source_id", -1)), int(context.get("target_id", -1)), str(context.get("trick_id", "")), bool(context.get("negated", false)))
		# 当前目标说明；无懈可击的使用目标是即将对这一名角色生效的锦囊效果，而不是整张多目标牌。
		var target: PlayerState = state.get_player(int(context.get("target_id", -1)))
		# 当前目标显示名；延时锦囊或异常状态找不到玩家时使用通用描述。
		var target_name: String = target.display_name if target != null else "当前目标"
		# 当前响应实体；同步规则测试可能直接返回，正式本地、AI与网络对局会创建异步请求。
		var response_card: CardInstance = request_response_card(responder_id, "wuxie", "是否使用【无懈可击】令锦囊对%s的效果%s？" % [target_name, "恢复生效" if bool(context.get("negated", false)) else "无效"], context)
		if has_pending_card_choice():
			return {"pending":true, "negated":bool(context.get("negated", false))}
		if response_card != null:
			context["negated"] = not bool(context.get("negated", false))
			context["response_index"] = 0
			_record_wuxie_chain_response(context, responder_id, response_card)
			add_log("%s使用【无懈可击】，当前锦囊%s。" % [responder.display_name, "被抵消" if bool(context.get("negated", false)) else "恢复生效"])
			response_index = 0
			continue
		response_index += 1
		context["response_index"] = response_index
	return {"pending":false, "negated":bool(context.get("negated", false))}


## 完成异步无懈链并恢复原目标；被抵消时只跳过当前目标，未抵消时从同一目标的效果入口继续。
func _finish_trick_negation_chain(context: Dictionary, final_negated: bool) -> void:
	# 原锦囊 UID；选择等待期间必须仍位于处理区。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	# 原锦囊实体；等待期间已经离开处理区时禁止恢复旧效果。
	var parent_card: CardInstance = _find_processing_card(parent_card_uid)
	if parent_card == null:
		return
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


## 判断一条已完成选牌是否通过丈八蛇矛响应【杀】；只有请求允许 sha 且所选 UID 仍是当前装备实体时返回 true。
func _is_zhangba_response_selection(choice_data: Dictionary, selected_uid: int) -> bool:
	# 选择恢复上下文；response_patterns 由规则创建请求时写入，客户端不能自行扩展允许的响应类型。
	var context: Dictionary = choice_data.get("context", {}) as Dictionary
	if not (context.get("response_patterns", []) as Array).has("sha"):
		return false
	# 选择者当前丈八蛇矛；等待期间装备被替换时旧 UID 自动失效。
	var zhangba_card: CardInstance = _get_equipment_card_by_definition(int(choice_data.get("chooser_id", -1)), "zhangba")
	return zhangba_card != null and zhangba_card.uid == selected_uid


## 校验丈八蛇矛的装备与两张普通手牌材料；返回空字符串表示材料可以用于使用或打出虚拟【杀】。
func _validate_zhangba_materials(player_id: int, equipment_uid: int, material_card_uids: Array[int]) -> String:
	# 丈八持有者；死亡或不存在的角色不能发动装备技能。
	var player: PlayerState = state.get_player(player_id) if state != null else null
	if player == null or not player.alive:
		return "丈八蛇矛的发动者不存在或已经死亡。"
	# 当前丈八蛇矛实体；必须与玩家点击或动作提交的装备 UID 完全一致。
	var zhangba_card: CardInstance = _get_equipment_card_by_definition(player_id, "zhangba")
	if zhangba_card == null or zhangba_card.uid != equipment_uid:
		return "玩家当前未装备所选择的丈八蛇矛。"
	if material_card_uids.size() != 2 or material_card_uids[0] == material_card_uids[1]:
		return "丈八蛇矛必须选择两张不同的手牌。"
	for material_card_uid: int in material_card_uids:
		if player.find_hand_card(material_card_uid) == null:
			return "丈八蛇矛的材料必须是当前仍在手牌区的实体牌。"
	return ""


## 校验丈八蛇矛在出牌阶段使用虚拟【杀】的完整动作；材料通过后继续复用虚拟牌次数、距离和目标规则。
func _validate_zhangba_slash(player_id: int, equipment_uid: int, material_card_uids: Array[int], target_ids: Array[int]) -> String:
	# 装备与材料错误；先校验费用可避免用不存在的手牌查询后续目标。
	var material_error: String = _validate_zhangba_materials(player_id, equipment_uid, material_card_uids)
	if not material_error.is_empty():
		return material_error
	return card_rules.validate_virtual_use(player_id, "sha", target_ids)


## 消耗两张普通手牌并返回无花色、无点数的虚拟【杀】响应；装备本身始终留在武器槽。
func _consume_zhangba_response(player_id: int, material_card_uids: Array[int]) -> CardInstance:
	# 当前丈八蛇矛；调用前已用其 UID 识别装备候选，恢复时仍需再次确认装备未离区。
	var zhangba_card: CardInstance = _get_equipment_card_by_definition(player_id, "zhangba")
	if zhangba_card == null:
		return null
	# 当前材料错误；选择等待期间手牌可能被其他插入结算移动，因此消费前必须再次复核。
	var material_error: String = _validate_zhangba_materials(player_id, zhangba_card.uid, material_card_uids)
	if not material_error.is_empty():
		return null
	_ensure_card_movement()
	# 响应事件；两张材料的处理区与弃牌移动共享同一稳定父事件，便于回放还原材料顺序。
	var respond_event_id: int = _record_runtime_event("respond", "response", {"player_id":player_id, "response_pattern":"sha", "equipment_uid":zhangba_card.uid, "material_card_uids":material_card_uids.duplicate()}, {"responded":true, "virtual":true})
	for material_card_uid: int in material_card_uids:
		# 当前丈八材料；先公开进入处理区，再作为本次虚拟响应的实际费用进入弃牌堆。
		var material_card: CardInstance = state.get_player(player_id).find_hand_card(material_card_uid)
		card_movement.move_card(material_card, "processing", -1, "respond", respond_event_id)
		card_movement.move_card(material_card, "discard_pile", -1, "respond", respond_event_id)
	# 响应历史；card_uid=-1表示没有单一实体响应牌，material_card_uids 保存全部真实费用。
	state.get_player(player_id).response_history.append({"event_id":respond_event_id, "response_pattern":"sha", "card_uid":-1, "material_card_uids":material_card_uids.duplicate(), "equipment_uid":zhangba_card.uid})
	add_log("%s发动【丈八蛇矛】，将两张手牌当【杀】打出。" % state.get_player(player_id).display_name)
	# 虚拟【杀】没有颜色；仁王盾、银月枪和其他颜色判断不能继承任一材料牌。
	return CardInstance.new("sha", "none", 0)


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
			_resolve_silver_moon_trigger(player.player_id, consumed, was_hand_card)
			return consumed

	if response_pattern == "shan" and get_equipment_id(player_id, "armor") == "bagua":
		# 八卦阵判定牌；红色结果视为打出虚拟【闪】。
		var judgment_card: CardInstance = perform_judgment(player_id, "八卦阵")
		if judgment_card != null and judgment_card.get_color() == "red":
			add_log("%s的【八卦阵】判定为红色，视为打出【闪】。" % player.display_name)
			return CardInstance.new("shan", judgment_card.suit, judgment_card.rank)

	if response_pattern == "sha" and player_has_equipment(player_id, "zhangba") and player.get_playable_cards().size() >= 2:
		# 丈八蛇矛转化使用的第一张手牌；花色与点数仅用于虚拟牌展示。
		var first_card: CardInstance = player.get_playable_cards()[0]
		# 丈八蛇矛转化使用的第二张手牌；两张牌均作为消耗置入弃牌堆。
		var second_card: CardInstance = player.get_playable_cards()[1]
		_discard_playable_card(player_id, first_card.uid)
		_discard_playable_card(player_id, second_card.uid)
		add_log("%s发动【丈八蛇矛】，将两张手牌当【杀】打出。" % player.display_name)
		# 丈八蛇矛由两张牌组成的虚拟【杀】没有花色与点数，不能错误继承第一张材料牌的颜色。
		return CardInstance.new("sha", "none", 0)
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
	card_movement.move_card(judgment_card, "processing", -1, "judge", judgment_event_id)
	# 判定牌属于公共牌堆而非判定角色打出的牌；来源使用-1让界面直接从中央弃牌锚点出现。
	_request_card_presentation(judgment_card, -1, [], "judge", judgment_event_id, true)
	add_log("%s的%s判定牌为%s。" % [judgment_player.display_name, reason, describe_card(judgment_card)])
	_record_runtime_event("judgeResult", "judgment_result", {"player_id":player_id, "reason":reason, "card_uid":judgment_card.uid}, {"suit":judgment_card.suit, "rank":judgment_card.rank, "color":judgment_card.get_color()}, judgment_event_id)
	_move_to_discard(judgment_card, judgment_event_id)
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
	card_movement.move_card(card, "equipment", player_id, "equip", state.current_event_id, slot)
	_install_card_runtime(card, player_id)
	add_log("%s装备了%s。" % [player.display_name, describe_card(card)])


## 将处理区中的延时锦囊放入目标判定区。
func place_delayed_trick(target_id: int, card: CardInstance) -> void:
	# 延时锦囊目标；合法性层已保证其存活且判定区无同名牌。
	var target: PlayerState = state.get_player(target_id)
	_ensure_card_movement()
	card_movement.move_card(card, "judgment", target_id, "add_judge", state.current_event_id)
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
	card_movement.move_card(taken_card, "hand", source_id, "gain", state.current_event_id, "", [source_id])
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
	_complete_active_card_target(int(context.get("parent_card_uid", -1)))


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


## 弃置目标装备区的第一张坐骑牌；麒麟弓造成伤害后调用。
func discard_first_mount(target_id: int) -> void:
	# 目标状态；按进攻坐骑、防御坐骑顺序寻找。
	var target: PlayerState = state.get_player(target_id)
	for slot: String in ["offensive_mount", "defensive_mount"]:
		if target.equipment.has(slot):
			_discard_equipment_slot(target_id, slot, true)
			return


## 弃置目标全部装备；水淹七军、死亡与主公惩罚可复用此操作。
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
	card_movement.move_card(card, "hand", to_id, "gain", state.current_event_id, "", [to_id])
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


## 返回一名玩家装备区的公开候选快照；整组弃置装备等卡牌效果无需访问控制器内部序列化函数。
func get_equipment_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	return _build_player_zone_candidates(viewer_id, target_id, false, true, false)


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


## 按稳定 UID 弃置玩家手牌区或装备区中被明确选择的牌；不存在或已移动的 UID 会安全跳过。
func discard_selected_hand_equipment(player_id: int, selected_uids: Array[int]) -> int:
	# 实际弃置数量；调用方据此判断装备费用是否完整支付。
	var discarded_count: int = 0
	for selected_uid: int in selected_uids:
		if _discard_selected_player_card(player_id, selected_uid):
			discarded_count += 1
	return discarded_count


## 返回目标装备区中可被麒麟弓弃置的坐骑候选；进攻与防御坐骑都公开展示并由发动者选择。
func get_mount_candidates(viewer_id: int, target_id: int) -> Array[Dictionary]:
	# 坐骑候选结果；按进攻坐骑、防御坐骑的固定槽位顺序排列。
	var result: Array[Dictionary] = []
	# 目标玩家；不存在时返回空数组。
	var target: PlayerState = state.get_player(target_id)
	if target == null:
		return result
	for slot: String in ["offensive_mount", "defensive_mount"]:
		if target.equipment.has(slot):
			result.append(_serialize_choice_candidate(target.equipment[slot] as CardInstance, target_id, "equipment", true, slot))
	return result


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
		card_movement.move_card(card, "processing", -1, "reveal", state.current_event_id)
		result.append(card)
	return result


## 将五谷丰登亮出的牌交给指定玩家手牌。
func give_revealed_card(player_id: int, card: CardInstance) -> void:
	# 获得牌的玩家状态；死亡玩家不会在正常结算中调用。
	var player: PlayerState = state.get_player(player_id)
	# 展示牌来源区域；获得动画从桌面中央展示区移动到角色武将锚点。
	# 该来源现由 CardMovementService 在移动前写入统一事件，五谷选择完成后只生成一张获得表现牌。
	_ensure_card_movement()
	card_movement.move_card(card, "hand", player_id, "gain", state.current_event_id, "", [player_id])
	add_log("%s从展示牌中获得了%s。" % [player.display_name, describe_card(card)])


## 将未被选择的展示牌移入弃牌堆。
func discard_revealed_card(card: CardInstance) -> void:
	_move_to_discard(card)


## 将任意已由规则确认归属的实体牌置入弃牌堆；装备附属区清理使用同一权威移动端口。
func discard_card_instance(card: CardInstance) -> void:
	if card != null:
		_move_to_discard(card)


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
	# 身份配置副本；包含主公在内全部洗牌，使主公与本地玩家都不与任何固定座次绑定。
	var identities: Array[String] = identity_rules.get_distribution(player_count)
	_shuffle_array(identities)
	for index: int in range(player_count):
		# 新建玩家状态；显示名保持稳定座次便于日志辨认。
		var player: PlayerState = PlayerState.new(index, "玩家%d" % (index + 1))
		# 当前座次身份；直接读取已完整洗牌的身份池，主公可以出现在任意座次。
		player.identity = identities[index]
		player.identity_revealed = player.identity == "lord"
		player.character_id = ""
		player.character_revealed = false
		state.players.append(player)
		if index != local_human_player_id:
			ai_coordinator.register_basic_ai(index)
	state.random_history.append({"kind":"identity_distribution", "identities":identities.duplicate(), "local_human_player_id":local_human_player_id})


## 把已确认武将应用到玩家状态；体力上限只在该入口初始化，避免界面与选将服务重复写数值。
func _apply_character(player: PlayerState, character_id: String, reveal_character: bool) -> void:
	if player == null:
		return
	player.character_id = character_id
	player.character_revealed = reveal_character
	# 已选武将配置；基础体力上限取 max_hp，仅不少于5人的身份局主公额外增加1点上限与当前体力。
	var character: Dictionary = GameDatabase.get_character(character_id)
	# 主公体力加值；规则集3.0规定参与玩家不少于5人时才增加1点。
	var lord_hp_bonus: int = 1 if player.identity == "lord" and state.players.size() >= 5 else 0
	player.max_hp = maxi(int(character.get("max_hp", 4)), 1) + lord_hp_bonus
	player.hp = player.max_hp


## 返回指定玩家当前持有的技能实例；空结果表示玩家未选择武将、未配置该技能或对局尚未完成技能安装。
func get_skill_instance(player_id: int, skill_id: String) -> SkillDefinition:
	# 玩家技能实例表；键为稳定技能 ID，值为仅属于该玩家的运行时对象。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	return player_skills.get(skill_id) as SkillDefinition


## 查询主动技能当前是否可发动；技能文件负责阶段、次数、目标和资源条件，控制器只提供统一入口。
func can_activate_skill(player_id: int, skill_id: String, context: Dictionary = {}) -> bool:
	# 当前技能运行时实例；未安装的技能不能通过伪造动作直接发动。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	return skill != null and skill.can_activate(context)


## 通过统一动作入口发动技能；技能成功后记录稳定技能 ID，失败原因直接返回给动作提交者。
func activate_skill(player_id: int, skill_id: String, context: Dictionary = {}) -> bool:
	if state == null or state.game_over:
		return _reject("当前没有可发动技能的进行中对局。")
	# 当前技能运行时实例；必须由玩家所选武将直接配置并在开局时自动安装。
	var skill: SkillDefinition = get_skill_instance(player_id, skill_id)
	if skill == null:
		return _reject("当前武将未配置该技能。")
	if not skill.can_activate(context):
		return _reject("该技能当前不满足发动条件。")
	# 技能执行错误；空字符串表示技能已通过公开规则端口成功提交效果或选择请求。
	var activation_error: String = skill.activate(context)
	if not activation_error.is_empty():
		return _reject(activation_error)
	# 技能持有者状态；历史只保存可序列化 ID、事件号与回合号，不保存技能对象引用。
	var player: PlayerState = state.get_player(player_id)
	if player != null:
		player.skill_history.append({"skill_id":skill_id, "event_id":state.current_event_id, "turn_number":state.turn_number})
	state.action_sequence += 1
	_dispatch_rule_event(RuleEvent.new("skill_used", player_id, -1, {"skill_id":skill_id, "context":context.duplicate(true)}))
	_emit_state()
	return true


## 为全部已选武将创建并安装独立技能实例；武将脚本中的直接引用顺序决定安装与技能栏顺序。
func _install_all_character_skills() -> void:
	_uninstall_all_character_skills()
	for player: PlayerState in state.players:
		# 当前武将定义；skills 数组由 CharacterDefinition 从直接引用的技能脚本自动生成。
		var character: Dictionary = GameDatabase.get_character(player.character_id)
		# 当前玩家技能实例表；不同玩家即使持有同一技能也不会共享次数、标记或临时状态。
		var player_skills: Dictionary = {}
		for skill_id_variant: Variant in character.get("skills", []):
			# 当前技能稳定 ID；用于从数据库脚本索引创建独立运行时实例。
			var skill_id: String = str(skill_id_variant)
			# 当前技能运行时实例；配置校验已保证正常开局时不会为空。
			var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
			if skill == null:
				push_error("无法为玩家%d创建技能：%s" % [player.player_id, skill_id])
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


## 完成其他玩家同时选将、统一亮将、发4张起始手牌并由主公开始首回合。
func _finish_character_selection() -> void:
	for player: PlayerState in state.players:
		if player.player_id != character_selection.lord_player_id:
			_apply_character(player, character_selection.get_selection(player.player_id), true)
	_install_all_character_skills()
	_record_runtime_event("gameStart", "mode", {"player_count":state.players.size()})
	for player: PlayerState in state.players:
		draw(player.player_id, 4, false)
	_record_runtime_event("gameDraw", "draw", {"cards_per_player":4, "player_count":state.players.size()})
	_record_runtime_event("phaseLoop", "phase_loop", {"first_player_id":character_selection.lord_player_id})
	# 身份确认后重新旋转物理座次；主公固定为一号位，后续数组顺序就是顺时针座次。
	_reorder_players_from_lord()
	# 首回合玩家状态；主公固定为一号位且不受本地玩家稳定 ID 影响。
	var first_turn_player: PlayerState = _find_player_by_identity("lord")
	if first_turn_player == null:
		push_error("标准身份局缺少主公，无法开始首回合。")
		return
	add_log("所有玩家完成选将并同时亮出武将。")
	add_log("对局开始：%d名玩家，牌堆%d张，每名玩家起始手牌4张。" % [state.players.size(), state.draw_pile.size()])
	_start_turn(first_turn_player.player_id)


## 以主公为数组首位旋转玩家，保留稳定 player_id 供网络、回放和实体牌所有权使用。
func _reorder_players_from_lord() -> void:
	# 主公在当前随机身份数组中的索引；身份分配完成前不调用此函数。
	var lord_index: int = -1
	for index: int in range(state.players.size()):
		if state.players[index].identity == "lord":
			lord_index = index
			break
	if lord_index > 0:
		# 旋转后的座次数组；主公为一号位，其原下家按顺时针依次成为后续座次。
		var reordered_players: Array[PlayerState] = []
		for offset: int in range(state.players.size()):
			reordered_players.append(state.players[(lord_index + offset) % state.players.size()])
		state.players = reordered_players
	# 玩家显示编号属于当前对局座次，不属于稳定 player_id；旋转完成后统一刷新，日志与牌面名称保持一致。
	for seat_index: int in range(state.players.size()):
		state.players[seat_index].display_name = "玩家%d" % (seat_index + 1)


## 让内置 AI 在当前选将阶段从自己的候选中确认首张；所有 AI 仍通过同一 select_character 校验入口。
func _drive_ai_character_selection() -> void:
	if _is_driving_character_selection or character_selection == null or character_selection.phase == CharacterSelectionService.PHASE_COMPLETE:
		return
	_is_driving_character_selection = true
	while character_selection.phase != CharacterSelectionService.PHASE_COMPLETE:
		# 当前轮是否提交了至少一项 AI 选择；没有进展表示正在等待人类或网络玩家。
		var made_progress: bool = false
		# 当前待确认玩家副本；每轮结束后重新获取，安全覆盖主公到其他玩家的阶段切换。
		var pending_player_ids: Array[int] = character_selection.get_pending_player_ids()
		for player_id: int in pending_player_ids:
			if not ai_coordinator.is_ai_controlled(player_id):
				continue
			# AI 候选武将；基础策略使用随机列表首项，后续可由独立选将策略替换。
			var candidates: Array[String] = character_selection.get_candidates(player_id)
			if candidates.is_empty():
				continue
			# AI 选将动作；与人类和网络玩家共用标准 PlayerAction 入口及服务校验。
			var action: PlayerAction = PlayerAction.new("select_character", player_id)
			action.payload = {"character_id":candidates[0]}
			submit_action(action)
			made_progress = true
		if not made_progress:
			break
	_is_driving_character_selection = false


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


## 开始指定玩家的回合，并依次处理开始、判定、摸牌，最终进入出牌阶段。
func _start_turn(player_id: int) -> void:
	if state.game_over:
		return
	# 上一回合残留的出牌选择；必须先从真实事件栈移除，新的阶段与 CardUseEvent 才能进入根事件。
	_cancel_active_play_choice("turn_changed")
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
	if state.players.find(player) == 0:
		state.round_number += 1
	var turn_event_id: int = _record_runtime_event("phase", "turn", {"player_id":player_id, "turn_number":state.turn_number, "round_number":state.round_number})
	_current_turn_event_id = turn_event_id
	player.slash_count = 0
	player.wine_used = false
	player.wine_bonus = 0
	player.wooden_ox_used = false
	player.skipped_phases.clear()
	player.card_use_history.clear()
	player.response_history.clear()
	player.damage_history.clear()
	player.skill_history.clear()
	player.turn_history.append({"turn_number":state.turn_number, "round_number":state.round_number, "event_id":turn_event_id, "skipped_phases":[]})
	state.current_phase = "start"
	state.phase_index = 0
	_record_runtime_event("phaseBefore", "phase", {"player_id":player_id}, {}, turn_event_id)
	_record_runtime_event("phaseBegin", "phase", {"player_id":player_id}, {}, turn_event_id)
	_record_runtime_event("phaseZhunbei", "phase", {"player_id":player_id}, {}, turn_event_id)
	add_log("第%d回合：%s的回合开始。" % [state.turn_number, player.display_name])
	_dispatch_rule_event(RuleEvent.new("phase_start", player_id, player_id, {}))
	if state.game_over:
		return
	if not player.alive:
		_advance_after_current_player_death(player_id)
		return
	if player.face_down:
		player.face_down = false
		add_log("%s翻回正面并跳过本回合。" % player.display_name)
		_finish_turn(player_id)
		return

	state.current_phase = "judgment"
	state.phase_index = 1
	_record_runtime_event("phaseJudge", "phase", {"player_id":player_id}, {}, turn_event_id)
	_process_judgment_area(player_id)
	return


## 从判定阶段结束处继续当前回合；异步无懈与濒死选择完成后也统一回到该入口。
func _continue_turn_after_judgment(player_id: int) -> void:
	if state == null or state.game_over or has_pending_card_choice() or state.current_player_id != player_id:
		return
	# 当前回合玩家；判定伤害可能使其死亡，必须在摸牌前重新读取存活状态。
	var player: PlayerState = state.get_player(player_id)
	if player == null or not player.alive:
		_advance_after_current_player_death(player_id)
		return
	state.current_phase = "draw"
	state.phase_index = 2
	_record_runtime_event("phaseDraw", "phase", {"player_id":player_id, "base_draw_count":2}, {}, _current_turn_event_id)
	if not bool(player.skipped_phases.get("draw", false)):
		draw(player_id, 2)
	else:
		add_log("%s跳过摸牌阶段。" % player.display_name)
	if state.game_over:
		return
	if not player.alive:
		_advance_after_current_player_death(player_id)
		return
	state.current_phase = "play"
	state.phase_index = 3
	_record_runtime_event("phaseUse", "phase", {"player_id":player_id}, {}, _current_turn_event_id)
	if bool(player.skipped_phases.get("play", false)):
		add_log("%s跳过出牌阶段。" % player.display_name)
		_end_play_phase(player_id)
		return
	_begin_play_choice(player_id)
	_emit_state()
	if ai_coordinator.is_ai_controlled(player_id):
		_schedule_ai_action()


## 在延迟选择完成后恢复被暂停的回合阶段；当前仅判定阶段允许在阶段主体中插入异步选择。
func _resume_interrupted_turn_flow() -> void:
	if state == null or state.game_over or has_pending_card_choice():
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
	if state.current_phase != "judgment":
		return
	# 当前回合玩家 ID；所有判定区剩余牌和后续摸牌、出牌都归属于该角色。
	var player_id: int = state.current_player_id
	_judgment_resume_needs_result_pause = true
	_process_judgment_area(player_id)


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
			await get_tree().create_timer(delayed_judgment_result_pause_seconds).timeout
			if not _is_judgment_flow_valid(player_id, flow_token):
				return
	# 判定玩家状态；每轮重新读取判定区，确保闪电传递和插入移动不会让旧数组重复结算。
	var player: PlayerState = state.get_player(player_id)
	while player != null and player.alive and not state.game_over and not has_pending_card_choice() and not player.judgment_area.is_empty():
		# 当前延时锦囊；始终取判定区数组首项，完整离区后下一项才会成为新的处理对象。
		var delayed_card: CardInstance = player.judgment_area.front()
		# 当前延时锦囊判定事件；展示、无懈与实际判定都关联本回合判定阶段，回放可以恢复严格顺序。
		var delayed_event_id: int = _record_runtime_event("delayedJudge", "judgment", {"player_id":player_id, "card_uid":delayed_card.uid, "card_id":delayed_card.definition_id}, {}, _current_turn_event_id)
		_ensure_card_movement()
		card_movement.move_card(delayed_card, "processing", -1, "judge", delayed_event_id)
		# 延时锦囊展示；表现接管其可能发生的处理区到弃牌堆移动，闪电传递时由新区域移动释放所有权。
		_request_card_presentation(delayed_card, player_id, [], "delayedJudge", delayed_event_id, true)
		add_log("%s开始判定%s。" % [player.display_name, describe_card(delayed_card)])
		_emit_state()
		if delayed_judgment_preview_seconds > 0.0 and not state.match_id.is_empty():
			await get_tree().create_timer(delayed_judgment_preview_seconds).timeout
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
			await get_tree().create_timer(delayed_judgment_result_pause_seconds).timeout
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


## 将【闪电】传递给下一名合法角色；公开端口供闪电卡牌文件维护自身判定函数。
func pass_lightning_card(from_player_id: int, lightning_card: CardInstance) -> void:
	_pass_lightning(from_player_id, lightning_card)


## 记录指定玩家跳过当前回合的某阶段；延时锦囊与后续技能共用该稳定规则操作。
func mark_player_phase_skipped(player_id: int, phase_name: String) -> void:
	# 需要跳过阶段的玩家；不存在或已经离场时不写入任何状态。
	var player: PlayerState = state.get_player(player_id)
	if player != null and player.alive and not phase_name.is_empty():
		player.skipped_phases[phase_name] = true


## 将未命中的闪电移动至下一名没有闪电的存活角色判定区；无合法角色时回到原角色。
func _pass_lightning(from_player_id: int, lightning_card: CardInstance) -> void:
	# 当前候选玩家；从原角色下家开始循环寻找。
	var candidate: PlayerState = state.get_next_alive_player(from_player_id)
	# 已检查角色数量；最多遍历全部存活角色一次。
	var checked_count: int = 0
	# 存活角色总数；用于限制循环。
	var alive_count: int = state.get_alive_players().size()
	while candidate != null and checked_count < alive_count:
		# 候选判定区是否已有闪电；同名延时锦囊不能重复放置。
		var has_lightning: bool = false
		for delayed_card: CardInstance in candidate.judgment_area:
			if delayed_card.definition_id == "shandian":
				has_lightning = true
				break
		if not has_lightning:
			_ensure_card_movement()
			card_movement.move_card(lightning_card, "judgment", candidate.player_id, "add_judge", state.current_event_id)
			add_log("【闪电】移动至%s的判定区。" % candidate.display_name)
			return
		candidate = state.get_next_alive_player(candidate.player_id)
		checked_count += 1
	# 所有角色均不是合法目标时，【闪电】按规则回到原角色判定区，而不是进入弃牌堆。
	var original_player: PlayerState = state.get_player(from_player_id)
	if original_player != null and original_player.alive:
		_ensure_card_movement()
		card_movement.move_card(lightning_card, "judgment", original_player.player_id, "add_judge", state.current_event_id)
		add_log("没有其他合法目标，【闪电】回到%s的判定区。" % original_player.display_name)
	else:
		_move_to_discard(lightning_card)


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
	if str(definition.get("effect_id", "")) == "borrow_sword" and target_ids.size() == 2:
		# 借刀杀人的无懈目标只有持刀者，但效果恢复仍需保留“持刀者、被杀者”的完整语义顺序。
		resolution_context["target_ids"] = [target_ids[0]]
		resolution_context["effect_target_ids"] = target_ids.duplicate()
	if str(definition.get("effect_id", "")) == "slash":
		# 【杀】使用者；酒加值在整张多目标【杀】声明时只消耗一次，并对全部目标使用相同伤害基数。
		var actor: PlayerState = state.get_player(actor_id)
		resolution_context["slash_damage_amount"] = 1 + actor.wine_bonus
		actor.wine_bonus = 0
		# 【杀】初始属性；普通、火焰和雷电属性由实体牌配置提供。
		var slash_nature: String = str(definition.get("nature", "normal"))
		resolution_context["slash_nature"] = slash_nature
		# 当前武器定义；是否忽略防具由武器卡牌源码的统一钩子决定。
		var weapon_definition: CardDefinition = get_equipment_definition(actor_id, "weapon")
		resolution_context["slash_ignore_armor"] = weapon_definition != null and weapon_definition.slash_ignores_armor()
	_active_card_resolutions[card.uid] = resolution_context
	if str(definition.get("effect_id", "")) == "slash" and str(resolution_context.get("slash_nature", "normal")) == "normal" and player_has_equipment(actor_id, "zhuque"):
		# 朱雀羽扇实体；玩家选择该公开装备表示发动，取消表示保留普通【杀】属性。
		var zhuque_card: CardInstance = _get_equipment_card_by_definition(actor_id, "zhuque")
		if zhuque_card != null:
			# 朱雀羽扇选择候选；装备牌只作为发动开关展示，不会因选择而离开装备区。
			var candidates: Array[Dictionary] = [_serialize_choice_candidate(zhuque_card, actor_id, "equipment", true, "weapon")]
			# 朱雀羽扇恢复上下文；只保存原【杀】UID，后续从活动结算表读取完整目标与共享参数。
			var trigger_context: Dictionary = {"kind":"zhuque_trigger", "parent_card_uid":card.uid, "actor_id":actor_id, "equipment_uid":zhuque_card.uid, "ai_prefer_select":true}
			# 发动选择结果；正式对局会暂停，纯规则测试未选择时默认不发动。
			var selected_uids: Array[int] = request_card_choice(actor_id, "朱雀羽扇", "是否发动【朱雀羽扇】将此普通【杀】改为火【杀】？", candidates, 0, 1, true, trigger_context)
			if has_pending_card_choice():
				return
			_apply_zhuque_trigger_choice(trigger_context, selected_uids)
	# 真实 CardUseEvent 由父事件步骤安排逐目标 content；迁移期独立调用才继续使用栈外兼容游标。
	var card_use_context: Dictionary = _card_use_contexts.get(card.uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(card.uid)


## 恢复朱雀羽扇发动选择；只有仍装备同一实体牌且玩家明确选择时才转换整张【杀】的属性。
func _continue_zhuque_trigger_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	_apply_zhuque_trigger_choice(context, selected_uids)
	# 原【杀】UID；真实事件树等待选择子事件完成，兼容调用则继续旧逐目标游标。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	# 真实 CardUseEvent 会在选择子事件完成后重新执行设置步骤；迁移期调用才需要主动推进旧游标。
	var card_use_context: Dictionary = _card_use_contexts.get(parent_card_uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(parent_card_uid)


## 应用朱雀羽扇选择结果；装备本身不作为材料消耗，转换结果保存在当前卡牌的共享结算上下文中。
func _apply_zhuque_trigger_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体 UID；用于取得并更新唯一活动结算上下文。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	if not _active_card_resolutions.has(parent_card_uid) or selected_uids.is_empty():
		return
	# 发动者 ID；等待期间若朱雀羽扇已经离开装备区，则本次选择自动失效。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前仍装备的朱雀羽扇；必须与请求展示的实体 UID 一致，避免旧窗口发动后来替换的装备。
	var zhuque_card: CardInstance = _get_equipment_card_by_definition(actor_id, "zhuque")
	if zhuque_card == null or zhuque_card.uid != int(context.get("equipment_uid", -1)) or not selected_uids.has(zhuque_card.uid):
		return
	# 当前活动上下文；火属性会供此【杀】的每个目标读取。
	var resolution_context: Dictionary = _active_card_resolutions[parent_card_uid] as Dictionary
	resolution_context["slash_nature"] = "fire"
	_active_card_resolutions[parent_card_uid] = resolution_context
	add_log("%s发动【朱雀羽扇】，将普通【杀】转为火【杀】。" % state.get_player(actor_id).display_name)


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
	resolution_context["current_target_id"] = -1
	_active_card_resolutions[parent_card_uid] = resolution_context
	# 真实 content 子事件由其选择子事件自然阻塞，统一 drain 后由父 CardUseEvent 的 redo 安排下一目标。
	var card_use_context: Dictionary = _card_use_contexts.get(parent_card_uid, {}) as Dictionary
	if not bool(card_use_context.get("runtime_managed", false)):
		_continue_active_card_resolution(parent_card_uid)


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


## 执行丈八蛇矛虚拟【杀】；逻辑代理承载杀的事件与装备触发，两张实体手牌作为材料进入处理区并在结算后弃置。
func _execute_zhangba_slash_use(actor_id: int, equipment_uid: int, material_card_uids: Array[int], target_ids: Array[int]) -> bool:
	# 完整动作错误；提交时重新校验装备、手牌、次数、距离与目标，界面预览不能替代该权威结果。
	var validation_error: String = _validate_zhangba_slash(actor_id, equipment_uid, material_card_uids, target_ids)
	if not validation_error.is_empty():
		return _reject(validation_error)
	# 无花色、无点数的逻辑代理；它只在本次 CardUseEvent 的处理区生命周期内存在，不进入任何玩家牌区或弃牌堆。
	var virtual_slash: CardInstance = CardInstance.new("sha", "none", 0)
	virtual_slash.zone = "void"
	virtual_slash.owner_id = -1
	_ensure_card_movement()
	if card_movement.move_card(virtual_slash, "processing", -1, "virtual_card_begin", state.current_event_id) == null:
		return _reject("丈八蛇矛的虚拟【杀】无法进入处理区。")
	add_log("%s发动【丈八蛇矛】，将两张手牌当【杀】使用。" % state.get_player(actor_id).display_name)
	_execute_card_use(actor_id, virtual_slash, target_ids, material_card_uids, true)
	return true


## 执行已通过合法性校验的出牌动作。
func _execute_card_use(actor_id: int, card: CardInstance, target_ids: Array[int], material_card_uids: Array[int] = [], virtual_proxy: bool = false) -> void:
	if state == null or state.game_over or card == null:
		return
	if card_use_event_service == null:
		card_use_event_service = CardUseEventService.new()
	# 当前卡牌定义；用于次数计数与日志。
	# 当前逻辑牌；真实牌也通过 VirtualCard 描述逻辑属性，实体材料 UID 始终独立保存。
	# 当前卡牌定义快照；提供逻辑属性、效果类型和默认自然属性，不持有运行时状态。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
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
		"virtual_card":virtual_card.to_dict(),
		"material_card_uids":virtual_card.material_card_uids.duplicate(),
		"virtual_proxy":virtual_proxy,
	}
	# CardUseEvent 的固定内容步骤；每一步只安排下一层子事件或推进一个明确规则边界。
	var content_steps: Array[Callable] = [
		_card_use_step_declare,
		_card_use_step_enqueue_use_timings,
		_card_use_step_enqueue_target_timings,
		_card_use_step_enqueue_content_before,
		_card_use_step_resolve_content,
		_card_use_step_enqueue_content_after,
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
	if str(definition.get("effect_id", "")) == "slash":
		actor.slash_count += 1
	actor.card_use_history[card.definition_id] = int(actor.card_use_history.get(card.definition_id, 0)) + 1
	add_log("%s使用了%s。" % [actor.display_name, describe_card(card)])
	# 只有正常规则终点为弃牌堆的牌接管后续 processing -> discard 表现，装备与延时锦囊保留未来真实离区动画。
	var owns_discard_transfer: bool = str(definition.get("final_zone", "discard")) == "discard" and not bool(card_use_context.get("virtual_proxy", false))
	# 卡牌展示请求只携带序列化数据与稳定玩家 ID，界面可据此播放飞牌和目标指示动画，不持有权威状态对象。
	_request_card_presentation(card, actor_id, event.target_ids, "useCard", event.event_id, owns_discard_transfer)
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
		# 虚拟牌实体材料 UID；丈八蛇矛固定包含两张普通手牌，逻辑代理牌已经在事件开始前进入处理区。
		var material_card_uids: Array[int] = _int_array(event.context.get("material_card_uids", []) as Array)
		# 待移动材料对象；全部存在且仍在普通手牌区后才开始逐张移动，避免过期动作只消费一部分费用。
		var material_cards: Array[CardInstance] = []
		for material_card_uid: int in material_card_uids:
			# 当前丈八材料；木牛“粮”和其他区域实体不能作为两张手牌费用。
			var material_card: CardInstance = actor.find_hand_card(material_card_uid) if actor != null else null
			if material_card == null:
				event.cancel("virtual_material_not_in_hand")
				return
			material_cards.append(material_card)
		_ensure_card_movement()
		# 已完成材料移动 ID；每张材料保留独立 CardMoveEvent，回放可按玩家选择顺序重建。
		var material_move_ids: Array[int] = []
		for material_card: CardInstance in material_cards:
			# 材料进入处理区；在虚拟杀完整结算前不会提前进入弃牌堆。
			var material_move: CardMoveEvent = card_movement.move_card(material_card, "processing", -1, "use", event.event_id)
			if material_move == null:
				event.cancel("virtual_material_move_failed")
				return
			material_move_ids.append(material_move.move_id)
		event.result = {"card_uids":material_card_uids.duplicate(), "to_zone":"processing", "move_ids":material_move_ids}
		return
	if card == null:
		event.cancel("material_not_playable")
		return
	_ensure_card_movement()
	# 实体移动结果；服务统一维护来源区域、持有者、知识与处理区数组。
	var move: CardMoveEvent = card_movement.move_card(card, "processing", -1, "use", event.event_id)
	if move == null:
		event.cancel("material_move_failed")
		return
	event.result = {"card_uids":[card.uid], "from_zone":move.from_zone, "to_zone":"processing", "move_id":move.move_id}


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
	var rule_event: RuleEvent = RuleEvent.new(timing_name, int(card_use_context.get("actor_id", -1)), target_id, timing_data)
	rule_event.event_id = event.event_id
	rule_event.parent_id = event.parent_id
	event_bus.dispatch(rule_event)
	if trigger_manager != null and not rule_event.is_terminal():
		# 当前存活座次顺序；触发器按当前回合起点、firstDo、优先级和注册序稳定执行。
		var seat_order: Array[int] = []
		for player: PlayerState in state.get_alive_players():
			seat_order.append(player.player_id)
		# 本轮触发排序起点；优先使用当前回合角色，无有效回合时回退到使用者。
		var start_player_id: int = state.current_player_id if state.current_player_id >= 0 else int(card_use_context.get("actor_id", -1))
		trigger_manager.dispatch(rule_event, start_player_id, seat_order)
	if not rule_event.is_terminal():
		rule_event.finish()
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
		# 死亡、离场或已排除目标不创建虚假的 content 事件，直接让父事件重新检查下一目标。
		var target: PlayerState = state.get_player(target_id)
		if target == null or not target.alive or (card_use_context.get("excluded_target_ids", []) as Array).has(target_id):
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
	# 本次内容返回的最终区域；pending 表示子事件必须等待现有恢复入口提交结果。
	var destination: String = "discard"
	if target_id >= 0 and _active_card_resolutions.has(card_uid):
		# 当前逐目标效果上下文；包含杀伤害、属性、无视防具与双目标语义。
		var resolution_context: Dictionary = _active_card_resolutions[card_uid] as Dictionary
		destination = effect_resolver.resolve_target(card, int(resolution_context.get("actor_id", -1)), target_id, resolution_context)
		if destination == "pending" or has_pending_card_choice():
			return
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
			if material_card != null and card_movement.move_card(material_card, "discard_pile", -1, "ordering_discard", event.event_id) != null:
				discarded_material_uids.append(material_card_uid)
		if card != null:
			# 逻辑代理返回 void；它只为效果链提供稳定 UID 和无花色【杀】定义，不属于任何持久卡牌区域。
			card_movement.move_card(card, "void", -1, "virtual_card_complete", event.event_id)
		event.result = {"card_uids":discarded_material_uids, "to_zone":"discard_pile", "virtual_card_uid":card_uid}
		_active_card_resolutions.erase(card_uid)
		_card_use_contexts.erase(card_uid)
		_check_game_over()
		return
	if card != null:
		_ensure_card_movement()
		# 弃牌移动；事件 ID 直接使用真实 cardsDiscard 子事件，不再创建迁移期摘要。
		var move: CardMoveEvent = card_movement.move_card(card, "discard_pile", -1, "ordering_discard", event.event_id)
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
	actor.take_hand_card(card.uid)
	_move_to_discard(card)
	add_log("%s重铸了%s。" % [actor.display_name, GameSettings.resolve_card_name(definition)])
	draw(actor_id, 1)
	return true


## 将一张手牌扣置于木牛流马下，并可选择把木牛流马与全部“粮”转移给一名其他角色。
func _execute_wooden_ox_store(actor_id: int, card_uid: int, target_ids: Array[int]) -> bool:
	# 发动木牛流马的玩家；必须处于自己的出牌阶段且仍装备该宝物。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or state.current_phase != "play" or state.current_player_id != actor_id:
		return _reject("当前不能发动木牛流马。")
	if not player_has_equipment(actor_id, "muniu"):
		return _reject("玩家未装备木牛流马。")
	if actor.wooden_ox_used:
		return _reject("本阶段已经发动过木牛流马。")
	if target_ids.size() > 1:
		return _reject("木牛流马最多转移给一名其他角色。")
	# 木牛流马转移目标；未选择目标时为 null，选择后必须是另一名存活角色。
	var target: PlayerState
	if target_ids.size() == 1:
		target = state.get_player(target_ids[0])
		if target == null or not target.alive or target.player_id == actor_id:
			return _reject("木牛流马转移目标不合法。")
	# 被扣置的手牌；规则要求只能从手牌存入，不能再次存入已有“粮”。
	var stored_card: CardInstance = actor.take_hand_card(card_uid)
	if stored_card == null:
		return _reject("木牛流马只能扣置一张手牌。")
	_ensure_card_movement()
	card_movement.move_card(stored_card, "wooden_ox", actor_id, "wooden_ox_store", state.current_event_id)
	actor.wooden_ox_used = true
	add_log("%s将一张手牌扣置于【木牛流马】下。" % actor.display_name)
	if target == null:
		return true
	if target.equipment.has("treasure"):
		_discard_equipment_slot(target.player_id, "treasure", true)
	# 被转移的木牛流马实体牌；转移到装备区不会触发粮弃置。
	var wooden_ox: CardInstance = actor.equipment["treasure"] as CardInstance
	_uninstall_card_runtime(wooden_ox.uid)
	card_movement.move_card(wooden_ox, "equipment", target.player_id, "wooden_ox_transfer", state.current_event_id, "treasure")
	_install_card_runtime(wooden_ox, target.player_id)
	for stored_transfer_card: CardInstance in actor.wooden_ox_storage.duplicate():
		card_movement.move_card(stored_transfer_card, "wooden_ox", target.player_id, "wooden_ox_transfer", state.current_event_id)
	actor.wooden_ox_storage.clear()
	add_log("%s将【木牛流马】及其下的“粮”转移给%s。" % [actor.display_name, target.display_name])
	return true


## 结束出牌阶段；超过手牌上限时由当前角色自主选择足量手牌弃置。
func _end_play_phase(player_id: int) -> void:
	if state.current_player_id != player_id or state.current_phase != "play":
		_reject("当前不能结束出牌阶段。")
		return
	_ai_drive_token += 1
	state.current_phase = "discard"
	state.phase_index = 4
	_record_runtime_event("phaseDiscard", "phase", {"player_id":player_id})
	# 当前玩家状态；弃牌候选只来自其手牌区。
	var player: PlayerState = state.get_player(player_id)
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
	_finish_turn(player_id)


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
	_finish_turn(player_id)


## 完成回合结束事件并转交给下一名存活玩家。
func _finish_turn(player_id: int) -> void:
	state.current_phase = "finish"
	state.phase_index = 5
	_record_runtime_event("phaseJieshu", "phase", {"player_id":player_id})
	_record_runtime_event("phaseEnd", "phase", {"player_id":player_id})
	_dispatch_rule_event(RuleEvent.new("phase_finish", player_id, player_id, {}))
	# 当前回合结束后清除所有未消耗的【酒】加值；该效果只持续到使用【酒】的本回合结束。
	for player: PlayerState in state.players:
		player.wine_bonus = 0
	_record_runtime_event("phaseAfter", "phase", {"player_id":player_id})
	_check_game_over()
	if state.game_over:
		return
	# 下一名存活玩家；身份局至少有两人存活时继续正常轮转。
	var next_player: PlayerState = state.get_next_alive_player(player_id)
	if next_player != null:
		_start_turn(next_player.player_id)


## 当前回合角色在事件结算中死亡后转交回合；不触发正常结束阶段，但会清除只持续到本回合的酒加值。
func _advance_after_current_player_death(dead_player_id: int) -> void:
	_ai_drive_token += 1
	for player: PlayerState in state.players:
		player.wine_bonus = 0
	# 下名存活玩家；死者仍保留稳定座次 ID，环形查询会自动跳过其状态。
	var next_player: PlayerState = state.get_next_alive_player(dead_player_id)
	if next_player != null:
		_start_turn(next_player.player_id)


## 依次请求所有存活角色使用桃，濒死角色还可使用酒自救；已询问名单保证异步取消后不会重复询问同一角色。
## 救援只遍历一轮座次；同一响应者成功救援后若目标仍未达到1点体力，则立即继续询问该响应者，取消后再进入下一名。
func _resolve_dying(target_id: int, killer_id: int, rescue_start_override: int = -1, already_asked_rescuer_ids: Array[int] = []) -> void:
	# 濒死角色状态；可能需要多张桃才能将体力回复至1。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		return
	# 是否首次进入本次濒死流程；连续出桃与取消后的座次推进都复用同一流程，不重复创建回放事件。
	var is_new_dying_flow: bool = not state.dying_queue.has(target_id)
	if is_new_dying_flow:
		# 本次濒死事件 ID；救援选择记录作为其子事件写入回放历史，仅在首次进入时创建。
		var dying_event_id: int = _record_runtime_event("dying", "dying", {"target_id":target_id, "source_id":killer_id})
		state.dying_queue.append(target_id)
		_record_runtime_event("_save", "choice", {"target_id":target_id, "source_id":killer_id}, {}, dying_event_id)
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
		# 当前救援者可用响应模式；其他角色只能使用桃，濒死者本人可在同一时机从桃与酒中直接选择。
		var response_patterns: Array[String] = ["tao"]
		if rescuer.player_id == target_id:
			response_patterns.append("jiu")
		# 当前尚需回复的体力点数；每张桃或自救酒固定回复1点，因此数值也等于达到1点所需的牌数。
		var required_recover: int = 1 - target.hp
		# 救援响应上下文；已询问名单与所需回复数共同恢复同一个单轮流程，不创建全体第二轮询问。
		var rescue_context: Dictionary = {"kind":"dying_response", "responder_id":rescuer.player_id, "target_id":target_id, "killer_id":killer_id, "rescue_start_id":rescue_start_player_id, "response_patterns":response_patterns.duplicate(), "asked_rescuer_ids":asked_rescuer_ids.duplicate(), "required_recover":required_recover}
		# 救援提示；明确给出目标达到1点体力还需要的桃数，濒死者本人同时可以选择酒自救。
		var rescue_prompt: String = "%s当前还需要%d张【桃】使体力达到1，请选择是否%s。" % [target.display_name, required_recover, "使用【桃】或【酒】自救" if rescuer.player_id == target_id else "使用【桃】救援"]
		# 实际提交的救援牌；为空表示明确取消或没有合法候选，实体定义决定本次使用桃还是酒。
		var rescue_card: CardInstance = request_response_card_patterns(rescuer.player_id, response_patterns, rescue_prompt, rescue_context)
		if has_pending_card_choice():
			return
		if rescue_card == null:
			continue
		# 实际救援模式；桃可救援目标，酒只会出现在濒死者自己的候选中。
		var response_pattern: String = _get_provided_response_pattern(GameDatabase.get_card(rescue_card.definition_id))
		if response_pattern == "tao":
			add_log("%s对%s使用【桃】。" % [rescuer.display_name, target.display_name])
		else:
			add_log("%s在濒死时使用【酒】自救。" % target.display_name)
		recover(rescuer.player_id, target_id, 1, response_pattern)
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
	for response_pattern_variant: Variant in context.get("response_patterns", ["tao"]) as Array:
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
	if has_pending_card_choice():
		return
	if response_card == null:
		# 下一名存活救援者；本轮已经询问的角色会在恢复函数中跳过，不会再次弹出同一桃询问。
		var next_rescuer: PlayerState = state.get_next_alive_player(responder_id)
		_resolve_dying(target_id, int(context.get("killer_id", -1)), next_rescuer.player_id if next_rescuer != null else int(context.get("rescue_start_id", state.current_player_id)), asked_rescuer_ids)
		return
	# 实际响应模式；由已消费实体牌的定义得出，客户端不能通过上下文伪造桃或酒类型。
	var response_pattern: String = _get_provided_response_pattern(GameDatabase.get_card(response_card.definition_id))
	if response_pattern == "tao":
		recover(responder_id, target_id, 1, "tao")
		add_log("%s对%s使用【桃】。" % [state.get_player(responder_id).display_name, state.get_player(target_id).display_name])
	elif response_pattern == "jiu" and responder_id == target_id:
		recover(responder_id, target_id, 1, "jiu")
		add_log("%s在濒死时使用【酒】自救。" % state.get_player(target_id).display_name)
	# 最新濒死目标状态；回复后依据当前体力决定继续救援或退出濒死队列。
	var target: PlayerState = state.get_player(target_id)
	if target != null and target.alive and target.hp <= 0:
		# 当前响应者仍可继续出桃；只从已询问集合移除本人，其他角色在本轮内不会被重复询问。
		asked_rescuer_ids.erase(responder_id)
		_resolve_dying(target_id, int(context.get("killer_id", -1)), responder_id, asked_rescuer_ids)
	else:
		_finish_dying_rescue(target_id)


## 在角色体力恢复至1点或以上时统一结算求桃流程；状态、事件与日志在同一入口完成，父级卡牌或阶段随后才能继续。
func _finish_dying_rescue(target_id: int) -> void:
	# 已脱离濒死的目标；异常丢失目标时仍清理队列，避免后续流程永久认为存在未结算濒死角色。
	var target: PlayerState = state.get_player(target_id)
	state.dying_queue.erase(target_id)
	if target == null:
		return
	target.dying = false
	_record_runtime_event("dyingAfter", "dying", {"target_id":target_id, "hp":target.hp, "rescued":true})
	_dispatch_rule_event(RuleEvent.new("dying_end", target_id, target_id, {"hp":target.hp, "rescued":true}))
	add_log("%s脱离濒死状态，求桃流程结算完成。" % target.display_name)


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
	var death_event_id: int = _record_runtime_event("die", "death", {"victim_id":victim_id, "killer_id":killer_id})
	state.dying_queue.erase(victim_id)
	# 死亡角色状态；先标记死亡，避免清理白银狮子时错误回复。
	var victim: PlayerState = state.get_player(victim_id)
	victim.alive = false
	victim.dying = false
	victim.death_confirmed = true
	victim.identity_revealed = true
	add_log("%s死亡，身份为%s。" % [victim.display_name, _identity_text(victim.identity)])
	# 亮出身份后立即检测胜负；若条件已满足，规则要求直接结束游戏，不再继续死亡弃牌与奖惩。
	_check_game_over()
	if state.game_over:
		_record_runtime_event("dieAfter", "death", {"victim_id":victim_id, "game_over":true}, {}, death_event_id)
		return
	while not victim.hand.is_empty():
		_move_to_discard(victim.hand.pop_back())
	discard_all_equipment(victim_id, false)
	while not victim.judgment_area.is_empty():
		_move_to_discard(victim.judgment_area.pop_back())
	# 击杀者状态；无来源伤害或击杀者已不存在时不执行奖惩。
	var killer: PlayerState = state.get_player(killer_id)
	# 身份规则返回的奖惩类型；控制器负责实际摸牌与弃牌移动。
	var reward: String = identity_rules.get_death_reward(killer, victim)
	if reward == "draw_three" and killer != null and killer.alive:
		draw(killer.player_id, 3)
	elif reward == "lord_penalty" and killer != null and killer.alive:
		while not killer.hand.is_empty():
			_move_to_discard(killer.hand.pop_back())
		discard_all_equipment(killer.player_id, true)
		add_log("主公杀死忠臣，弃置全部手牌和装备。")
	_check_game_over()
	_record_runtime_event("dieAfter", "death", {"victim_id":victim_id, "game_over":state.game_over}, {}, death_event_id)


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
	_pending_card_choice.clear()
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
	_pending_card_choice.clear()
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
		var move: CardMoveEvent = card_movement.move_card(card, "discard_pile", -1, "discard", discard_event_id)
		if move == null:
			return
	else:
		card.zone = "discard_pile"
		card.owner_id = -1
		state.discard_pile.append(card)


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
	card_transfer_requested.emit(card_data.duplicate(true), source_player_id, source_zone, target_player_id, target_zone)


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
		card.known_to.clear()
		card.shown = false
		card.private_owner_id = -1
	_shuffle_array(state.draw_pile)
	_record_runtime_event("washCard", "card_move", {"card_count":state.draw_pile.size()}, {"to_zone":"draw_pile"})
	add_log("弃牌堆已重新洗入摸牌堆。")


## 将一个借刀杀人的合法双目标动作加入候选列表。
func _append_borrow_sword_actions(result: Array[Dictionary], player_id: int, card: CardInstance) -> void:
	for holder: PlayerState in state.players:
		if not holder.alive or holder.player_id == player_id or holder.get_weapon() == null:
			continue
		for victim: PlayerState in state.players:
			if not victim.alive or victim.player_id == holder.player_id:
				continue
			_append_if_legal(result, player_id, card, [holder.player_id, victim.player_id])


## 校验并追加一个使用牌候选动作。
func _append_if_legal(result: Array[Dictionary], player_id: int, card: CardInstance, requested_targets: Array[int]) -> void:
	# 自动展开后的目标；全体牌使用空请求数组即可。
	var normalized_targets: Array[int] = card_rules.normalize_targets(player_id, card, requested_targets)
	if card_rules.validate_use(player_id, card, normalized_targets).is_empty():
		result.append({"action_type":"use_card", "actor_id":player_id, "card_uid":card.uid, "target_ids":requested_targets.duplicate(), "card_definition_id":card.definition_id})


## 安排下一次 AI 操作；令牌保证阶段变化后旧计时器不会执行。
func _schedule_ai_action() -> void:
	if state == null or state.game_over or state.current_phase != "play" or not ai_coordinator.is_ai_controlled(state.current_player_id) or has_pending_card_choice() or not _has_active_play_choice():
		return
	if _scheduled_ai_drive_token == _ai_drive_token:
		return
	# 本次异步任务令牌；与全局令牌不一致时回调直接失效。
	var token: int = _ai_drive_token
	_scheduled_ai_drive_token = token
	_run_ai_after_delay(token)


## 等待展示延迟后请求 AI 动作，并再次进入统一 submit_action 入口。
func _run_ai_after_delay(token: int) -> void:
	await get_tree().create_timer(ai_action_delay_seconds).timeout
	if _scheduled_ai_drive_token == token:
		_scheduled_ai_drive_token = -1
	if token != _ai_drive_token or state == null or state.game_over or state.current_phase != "play":
		return
	# 当前 AI 玩家 ID；阶段等待期间可能已发生变化，因此在延迟后读取。
	var player_id: int = state.current_player_id
	if not ai_coordinator.is_ai_controlled(player_id):
		return
	_ai_actions_this_turn += 1
	if _ai_actions_this_turn > max_ai_actions_per_turn:
		submit_action(PlayerAction.new("end_play", player_id))
		return
	# AI 可读取的权威完整快照；包含所有身份与手牌，但策略只能返回标准动作字典。
	var full_snapshot: Dictionary = state.to_dict(player_id, true)
	# 当前全部合法候选；核心在决策前完成枚举，AI 无权绕过合法性。
	var legal_actions: Array[Dictionary] = get_legal_actions(player_id)
	# 策略返回的动作数据；随后恢复为标准 PlayerAction 并再次校验。
	var action_data: Dictionary = ai_coordinator.request_action(player_id, full_snapshot, legal_actions)
	submit_action(PlayerAction.from_dict(action_data))


## 接收全局 AI 响应时间设置；仅更新后续新建的计时器，已开始等待的任务保持原时长以避免补间中途跳变。
func _on_ai_response_delay_changed(delay_seconds: float) -> void:
	ai_action_delay_seconds = clampf(delay_seconds, GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS, GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS)


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


## 处理网络网关交付的行为字典；网络与本地动作共用完全相同的校验入口。
func _on_network_command_received(command_data: Dictionary) -> void:
	submit_action(PlayerAction.from_dict(command_data))


## 把网络 ChoiceResponse 转换为兼容动作入口；事件运行时仍会再次校验事件、玩家、数量和候选。
func _on_network_choice_response_received(response_data: Dictionary) -> void:
	var response: ChoiceResponse = ChoiceResponse.from_dict(response_data)
	var action: PlayerAction = PlayerAction.new("choose_cards", response.actor_id)
	action.client_sequence = response.client_sequence
	action.payload = {"request_id":response.request_id, "event_id":response.event_id, "selected_card_uids":response.card_ids.duplicate()}
	submit_action(action)


## 返回当前规则调用可关联的父事件 ID；无有效摘要时回退到长期对局根事件。
func _current_rule_parent_event_id() -> int:
	if state != null and state.current_event_id >= 0:
		return state.current_event_id
	return _runtime_root_event_id


## 创建并发送统一牌面表现事件；表现只携带序列化数据，不暂停规则或持有 CardInstance 引用。
func _request_card_presentation(card: CardInstance, actor_id: int, target_ids: Array[int], event_name: String, event_id: int, owns_discard_transfer: bool) -> void:
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
		owns_discard_transfer
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


## 统一派发同步规则事件；兼容旧总线后再按 firstDo、优先级和座次执行新触发器，最终写入事件历史。
func _dispatch_rule_event(event: RuleEvent) -> RuleEvent:
	if event == null:
		return null
	event.event_id = state.current_event_id if state != null else -1
	event.parent_id = _runtime_root_event_id
	event_bus.dispatch(event)
	if trigger_manager != null and not event.is_terminal():
		var seat_order: Array[int] = []
		for player: PlayerState in state.get_alive_players():
			seat_order.append(player.player_id)
		var start_player_id: int = state.current_player_id if state.current_player_id >= 0 else (event.source_id if event.source_id >= 0 else event.target_id)
		trigger_manager.dispatch(event, start_player_id, seat_order)
	if not event.is_terminal():
		event.finish()
	_record_runtime_event(event.name, "trigger", {"source_id":event.source_id, "target_id":event.target_id, "data":event.data.duplicate(true)}, event.to_dict())
	return event


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
	if network_gateway != null and network_gateway.mode != NetworkGateway.Mode.OFFLINE:
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
	if event_scheduler != null:
		state.event_history = event_scheduler.get_event_history()
	# 本地界面快照；仅公开本地玩家手牌和自身身份。
	var local_snapshot: Dictionary = state.to_dict(local_human_player_id, false)
	state_changed.emit(local_snapshot)
	if state.current_phase == "character_selection" and character_selection != null:
		character_selection_changed.emit(character_selection.to_dict(local_human_player_id))


## 拒绝动作并返回 false，统一错误信号与调用结果。
func _reject(message: String) -> bool:
	action_rejected.emit(message)
	return false


## 查找指定身份玩家；标准身份局中主公查询只会返回一人。
func _find_player_by_identity(identity: String) -> PlayerState:
	for player: PlayerState in state.players:
		if player.identity == identity:
			return player
	return null


## 按定义 ID 查找玩家手牌，供无懈可击与濒死救援使用。
func _find_hand_card_by_definition(player: PlayerState, definition_id: String) -> CardInstance:
	for card: CardInstance in player.get_playable_cards():
		if card.definition_id == definition_id:
			return card
	return null


## 消耗指定定义 ID 的手牌并直接置入弃牌堆。
func _consume_specific_hand_card(player: PlayerState, definition_id: String) -> CardInstance:
	# 找到的目标手牌；不存在时返回 null。
	var card: CardInstance = _find_hand_card_by_definition(player, definition_id)
	if card == null:
		return null
	# 是否为真实手牌；濒死响应可使用木牛“粮”，但只有手牌可触发【银月枪】。
	var was_hand_card: bool = player.hand.has(card)
	player.take_playable_card(card.uid)
	_move_to_discard(card)
	_resolve_silver_moon_trigger(player.player_id, card, was_hand_card)
	return card


## 登记【银月枪】的回合外黑色手牌触发；当前响应子事件完成后再询问是否发动，避免嵌套窗口覆盖原响应上下文。
func _resolve_silver_moon_trigger(owner_id: int, used_card: CardInstance, was_hand_card: bool) -> void:
	if used_card == null or not was_hand_card or used_card.get_color() != "black" or owner_id == state.current_player_id or not player_has_equipment(owner_id, "yinyue"):
		return
	# 装备持有者；触发时仍须存活且位于游戏内。
	var owner: PlayerState = state.get_player(owner_id)
	if owner == null or not owner.alive:
		return
	# 待询问触发；实体牌已经完成自身使用或打出，队列只保存可回放标识和装备持有者。
	_queued_silver_moon_triggers.append({"owner_id":owner_id, "used_card_uid":used_card.uid})


## 在没有其他活动选牌请求时启动下一条银月枪发动询问；非锁定装备被明确取消时不会选择目标或造成伤害。
func _process_next_silver_moon_trigger() -> void:
	if state == null or state.game_over or has_pending_card_choice() or _queued_silver_moon_triggers.is_empty():
		return
	# 当前待处理触发；按黑色牌实际使用或打出顺序先进先出。
	var trigger_data: Dictionary = _queued_silver_moon_triggers.pop_front() as Dictionary
	# 银月枪持有者；等待期间死亡、进入自己回合或失去装备时本次触发失效。
	var owner_id: int = int(trigger_data.get("owner_id", -1))
	var owner: PlayerState = state.get_player(owner_id)
	if owner == null or not owner.alive or owner_id == state.current_player_id or not player_has_equipment(owner_id, "yinyue"):
		_process_next_silver_moon_trigger()
		return
	# 发动选择上下文；玩家确认装备实体后才进入目标与【闪】响应步骤。
	var trigger_context: Dictionary = {"kind":"silver_moon_trigger", "owner_id":owner_id, "used_card_uid":int(trigger_data.get("used_card_uid", -1))}
	# 是否发动银月枪；AI 与玩家共用可取消装备选择请求，规则层不能自动开启效果。
	var activated: bool = request_equipment_trigger(owner_id, "yinyue", "银月枪", "是否发动【银月枪】？", trigger_context, true)
	if has_pending_card_choice():
		return
	if activated:
		_activate_silver_moon(owner_id)
	if not has_pending_card_choice():
		_process_next_silver_moon_trigger()


## 恢复银月枪发动选择；选择装备实体才执行效果，取消后继续处理后续排队触发。
func _continue_silver_moon_trigger_choice(context: Dictionary, selected_uids: Array[int]) -> void:
	# 银月枪持有者；选择等待期间仍需存活并保持装备。
	var owner_id: int = int(context.get("owner_id", -1))
	# 当前银月枪实体；必须与选择结果一致，避免换装后发动新的装备。
	var silver_moon: CardInstance = _get_equipment_card_by_definition(owner_id, "yinyue")
	if silver_moon != null and selected_uids.has(silver_moon.uid):
		_activate_silver_moon(owner_id)


## 在玩家确认发动后结算银月枪；基础目标策略优先范围内敌方，目标能打出【闪】则抵消。
func _activate_silver_moon(owner_id: int) -> void:
	# 装备持有者；发动时再次校验存活与装备，避免旧选择修改无效角色状态。
	var owner: PlayerState = state.get_player(owner_id)
	if owner == null or not owner.alive or not player_has_equipment(owner_id, "yinyue"):
		return
	# 可选目标；从持有者下家起按行动顺序收集攻击范围内的其他存活角色。
	var legal_targets: Array[PlayerState] = []
	for candidate: PlayerState in _get_alive_players_in_action_order(owner_id):
		if candidate.player_id != owner_id and card_rules.calculate_distance(owner_id, candidate.player_id) <= card_rules.get_attack_range(owner_id):
			legal_targets.append(candidate)
	if legal_targets.is_empty():
		return
	# 自动目标；优先选择身份立场为敌方的首名合法角色，无敌方时回退行动顺序首项。
	var target: PlayerState = legal_targets[0]
	for candidate: PlayerState in legal_targets:
		if _identity_attitude(owner.identity, candidate.identity) < 0:
			target = candidate
			break
	add_log("%s发动【银月枪】，令%s响应【闪】。" % [owner.display_name, target.display_name])
	# 目标是否打出【闪】；响应牌自身可能触发新的银月枪并立即结束游戏，因此响应后必须先检查终局状态。
	var silver_context: Dictionary = {"kind":"silver_moon_response", "responder_id":target.player_id, "owner_id":owner_id}
	var silver_response: CardInstance = request_response_card(target.player_id, "shan", "是否打出【闪】响应银月枪？", silver_context)
	if has_pending_card_choice():
		return
	var dodged: bool = silver_response != null
	if state.game_over:
		return
	if dodged:
		add_log("%s打出【闪】抵消了【银月枪】。" % target.display_name)
	else:
		damage(owner_id, target.player_id, 1, "normal", "yinyue")


## 基础无懈可击策略；根据身份关系和锦囊收益方向决定是否自动响应。
func _should_auto_negate(responder: PlayerState, source_id: int, target_id: int, trick_id: String, currently_negated: bool) -> bool:
	# 响应者对目标的阵营态度；正值为友方，负值为敌方。
	var target_attitude: int = _identity_attitude(responder.identity, state.get_player(target_id).identity if state.get_player(target_id) != null else "")
	# 该锦囊对目标是否通常有利；有利锦囊与伤害/控制锦囊的响应方向相反。
	var beneficial: bool = trick_id in ["wuzhong", "taoyuan", "wugu"]
	if not currently_negated:
		return (beneficial and target_attitude < 0) or (not beneficial and target_attitude > 0)
	# 反无懈旨在恢复对友方的有利效果或恢复对敌方的有害效果。
	return (beneficial and target_attitude > 0) or (not beneficial and target_attitude < 0)


## 返回两个身份的简化阵营关系，供基础自动响应使用。
func _identity_attitude(from_identity: String, to_identity: String) -> int:
	if from_identity == "renegade":
		return -1
	if from_identity == to_identity:
		return 1
	if from_identity in ["lord", "loyalist"] and to_identity in ["lord", "loyalist"]:
		return 1
	return -1


## 将伤害属性 ID 转换为日志文本。
func _nature_text(nature: String) -> String:
	return {"normal":"普通", "fire":"火焰", "thunder":"雷电"}.get(nature, nature)


## 将身份 ID 转换为界面与日志文本。
func _identity_text(identity: String) -> String:
	return {"lord":"主公", "loyalist":"忠臣", "rebel":"反贼", "renegade":"内奸"}.get(identity, identity)


## 将获胜方 ID 转换为界面与日志文本。
func _winner_text(winner: String) -> String:
	return {"lord_and_loyalists":"主公与忠臣", "rebels":"反贼", "renegade":"内奸"}.get(winner, winner)
