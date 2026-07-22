class_name OpportunitySystem
extends Node

## 可插拔机缘系统组件。组件负责触发概率、全体三选一、私有候选、暂停与逆时针结算，不依赖具体主菜单模式。

## 每名角色每次出现的机缘卡数量；默认3张，修改会直接改变弹窗牌位数量与选择协议。
@export_range(1, 6, 1) var cards_per_choice: int = 3

## 绿卡抽取权重；默认100，是当前最低品质与最高基础出现率，运行时通常不动态修改。
@export_range(0, 1000, 1) var green_weight: int = 100

## 蓝卡抽取权重；默认80，低于绿卡且高于紫卡，运行时通常不动态修改。
@export_range(0, 1000, 1) var blue_weight: int = 80

## 紫卡抽取权重；默认60，作为中高品质的基础出现率，运行时通常不动态修改。
@export_range(0, 1000, 1) var purple_weight: int = 60

## 橙卡抽取权重；默认30，与主公给出的第四项权重一致，运行时通常不动态修改。
@export_range(0, 1000, 1) var orange_weight: int = 30

## 红卡抽取权重；需求未给出第五项数值，默认补全为10并暴露在检查器中供主公直接调整。
@export_range(0, 1000, 1) var red_weight: int = 10

## 当前权威对局控制器；组件只调用其公开规则端口，不直接改变体力、牌区、技能或座次数组。
var _host: MatchController

## 当前权威对局状态；组件只写入自身opportunity_state交互快照，其他状态变化交给控制器接口。
var _state: GameState

## 当前对局共享随机源；由控制器注入以保证固定种子、回放历史与其他随机流程处于同一序列。
var _rng: RandomNumberGenerator

## 当前效果解析器；每局重新绑定，独立负责目标与具体效果，不承担触发概率和选择队列。
var _effect_resolver: OpportunityEffectResolver = OpportunityEffectResolver.new()

## 当前组件是否对本局启用；模式或测试可在开局时配置，禁用后所有钩子均无副作用。
var _enabled: bool = false

## 当前已经初始化概率状态的轮数；默认-1，进入新轮时更新并重置本轮触发标记。
var _tracked_round_number: int = -1

## 当前轮是否已经触发过全体机缘；true时本轮后续普通回合开始与轮末均不再重复触发。
var _triggered_this_round: bool = false

## 当前轮每名角色回合开始时使用的相同触发概率；按本轮开始时在场人数倒数计算并锁定到轮末。
var _round_trigger_probability: float = 0.0

## 尚未完成机缘卡选择的角色队列；按触发角色起逆时针排列，所有选择完成前不会执行任何效果。
var _selection_queue: Array[int] = []

## 已选择机缘卡映射；键为角色ID字符串，值为完整静态卡定义副本，供后续逆时针结算。
var _selected_cards_by_player: Dictionary = {}

## 尚未结算机缘效果的角色队列；固定从触发时当前回合角色开始逆时针执行。
var _resolution_queue: Array[int] = []

## 当前正在结算机缘效果的角色ID；默认-1，异步目标选择期间保持稳定。
var _current_effect_owner_id: int = -1

## 当前正在结算的机缘卡定义；空字典表示没有活动效果或正在等待下一张。
var _current_effect_card: Dictionary = {}

## 当前效果是否已经执行且只等待嵌套结算屏障；恢复后应直接进入下一张机缘而不能重复执行效果。
var _current_effect_waiting_for_barrier: bool = false

## 机缘流程完成后的恢复类型；turn_start恢复回合开始游标，round_end恢复轮末到下一回合的阶段切换。
var _resume_kind: String = ""

## 机缘流程完成后的可序列化恢复上下文；不保存Callable、节点或PlayerState引用。
var _resume_context: Dictionary = {}

## 触发机缘前的公开阶段；选择与结算期间使用opportunity，完成后恢复原值再交还阶段游标。
var _resume_phase: String = ""

## 选择机缘期间持有的全局暂停令牌；默认-1，全部角色选完后立即释放，目标选择沿用标准规则暂停。
var _selection_pause_token: int = -1


## 让机缘组件在场景树暂停期间仍能接收联机选择动作并释放自身暂停令牌。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 为新对局绑定权威服务并重置全部运行时状态；enabled决定当前模式是否挂载机缘规则。
func configure(host: MatchController, state: GameState, rng: RandomNumberGenerator, enabled: bool) -> void:
	shutdown()
	_host = host
	_state = state
	_rng = rng
	_enabled = enabled
	_effect_resolver.configure(self, _host, _state)
	if _state != null:
		_state.opportunity_state.clear()


## 释放进行中的暂停与所有跨步骤状态；重新开局、放弃对局和组件退出时均可安全重复调用。
func shutdown() -> void:
	if _selection_pause_token >= 0 and _host != null:
		_host.release_gameplay_pause(_selection_pause_token)
	_selection_pause_token = -1
	_selection_queue.clear()
	_selected_cards_by_player.clear()
	_resolution_queue.clear()
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	_resume_kind = ""
	_resume_context.clear()
	_resume_phase = ""
	_tracked_round_number = -1
	_triggered_this_round = false
	_round_trigger_probability = 0.0
	if _state != null:
		_state.opportunity_state.clear()
	_enabled = false


## 当前组件是否启用且正在选择或结算机缘；阶段恢复与测试可据此避免重复触发。
func is_active() -> bool:
	return _enabled and _state != null and not _state.opportunity_state.is_empty()


## 在普通回合开始入口尝试触发机缘；返回true表示回合游标必须等待本次机缘完整结束。
func try_trigger_at_turn_start(turn_context: Dictionary, is_extra_turn: bool) -> bool:
	if not _can_trigger_now() or is_extra_turn:
		return false
	# 当前轮数；控制器已在调用前完成新轮递增，因此首名角色与后续角色读取同一稳定值。
	var current_round_number: int = _state.round_number
	if _tracked_round_number != current_round_number:
		_initialize_round_probability(current_round_number)
	if _triggered_this_round:
		return false
	# 本次公开随机值；固定种子下与卡牌候选共同进入同一可回放序列。
	var trigger_roll: float = _rng.randf()
	_state.random_history.append({"kind":"opportunity_trigger_roll", "round_number":current_round_number, "player_id":int(turn_context.get("player_id", -1)), "probability":_round_trigger_probability, "roll":trigger_roll})
	if trigger_roll >= _round_trigger_probability:
		return false
	_begin_trigger(int(turn_context.get("player_id", -1)), false, "turn_start", turn_context)
	return true


## 在普通轮末强制补触发；仅当本轮所有回合开始均未触发时返回true并阻止进入下一回合。
func try_trigger_at_round_end(finished_player_id: int) -> bool:
	if not _can_trigger_now():
		return false
	if _tracked_round_number != _state.round_number:
		_initialize_round_probability(_state.round_number)
	if _triggered_this_round:
		return false
	_begin_trigger(finished_player_id, true, "round_end", {"finished_player_id":finished_player_id})
	return true


## 供测试、调试器或其他模式按明确时机主动触发机缘；活动流程存在时拒绝重复开始。
func force_trigger(trigger_player_id: int, resume_kind: String = "manual", resume_context: Dictionary = {}) -> bool:
	if not _can_trigger_now():
		return false
	if _tracked_round_number != _state.round_number:
		_initialize_round_probability(_state.round_number)
	_begin_trigger(trigger_player_id, true, resume_kind, resume_context)
	return true


## 接受玩家、局域网客户端或回放提交的机缘卡ID；只有当前选择者自己的三张候选可以通过。
func submit_choice(player_id: int, card_id: String) -> bool:
	if not is_active() or str(_state.opportunity_state.get("stage", "")) != "choosing":
		return false
	if player_id != int(_state.opportunity_state.get("current_chooser_id", -1)):
		return false
	# 当前角色私有候选；字符串键是权威状态的稳定形式，兼容JSON网络序列化。
	var options_by_player: Dictionary = _state.opportunity_state.get("options_by_player", {}) as Dictionary
	# 当前候选数组；只在服务器权威状态中包含完整三张定义。
	var player_options: Array = options_by_player.get(str(player_id), []) as Array
	# 匹配的合法卡定义；空字典表示伪造ID或旧弹窗提交。
	var selected_card: Dictionary = {}
	for option_variant: Variant in player_options:
		# 当前候选定义；逐项比较稳定ID，不信任客户端提交的品质或正文。
		var option: Dictionary = option_variant as Dictionary
		if str(option.get("id", "")) == card_id:
			selected_card = OpportunityCatalog.get_card(card_id)
			break
	if selected_card.is_empty():
		return false
	_record_player_choice(player_id, selected_card)
	_advance_selection_queue()
	return true


## 恢复机缘解析器创建的标准ChoiceRequest；控制器在普通卡牌、技能处理前优先调用本入口。
func continue_choice(context: Dictionary, response: ChoiceResponse) -> bool:
	if not is_active() or str(_state.opportunity_state.get("stage", "")) != "resolving":
		return false
	return _effect_resolver.continue_choice(context, response)


## 完成当前单张机缘效果；若体力或移牌插入嵌套选择，则登记通用续接并等待屏障清空。
func complete_current_effect() -> void:
	if _state == null or _state.game_over:
		_finish_without_resume()
		return
	if _host.has_nested_settlement_barrier():
		_current_effect_waiting_for_barrier = true
		_host.defer_opportunity_resolution()
		return
	_finish_current_effect_and_continue()


## 在通用结算栈清空后恢复机缘；多目标伤害优先继续剩余目标，否则推进下一张已执行效果。
func continue_after_barrier() -> void:
	if not is_active():
		return
	if _effect_resolver.continue_after_barrier():
		return
	if _current_effect_waiting_for_barrier:
		_current_effect_waiting_for_barrier = false
		_finish_current_effect_and_continue()
		return
	_resolve_next_effect()


## 返回完整机缘卡目录，供无头测试与内容校验读取；调用方获得深拷贝。
func get_card_catalog() -> Array[Dictionary]:
	return OpportunityCatalog.get_all_cards()


## 返回当前品质权重快照；键顺序不作为规则契约，抽取过程始终按OpportunityCatalog.QUALITY_ORDER遍历。
func get_quality_weights() -> Dictionary:
	return {"green":green_weight, "blue":blue_weight, "purple":purple_weight, "orange":orange_weight, "red":red_weight}


## 开始一次全体机缘；先生成全部私有候选并暂停场景树，所有角色选完后才释放暂停和执行效果。
func _begin_trigger(trigger_player_id: int, forced: bool, resume_kind: String, resume_context: Dictionary) -> void:
	_triggered_this_round = true
	_resume_kind = resume_kind
	_resume_context = resume_context.duplicate(true)
	_resume_phase = _state.current_phase
	_state.current_phase = "opportunity"
	# 本次参与者与逆时针顺序；触发角色无效时回退当前回合角色，再回退首名在场角色。
	var participant_ids: Array[int] = _build_counterclockwise_order(trigger_player_id)
	if participant_ids.is_empty():
		_finish_without_resume()
		return
	_selection_queue = participant_ids.duplicate()
	_resolution_queue = participant_ids.duplicate()
	_selected_cards_by_player.clear()
	# 每名角色私有候选映射；权威状态保存完整定义，GameState.to_dict负责按观察者裁剪。
	var options_by_player: Dictionary = {}
	for participant_id: int in participant_ids:
		options_by_player[str(participant_id)] = _draw_options_for_player(participant_id)
	_state.opportunity_state = {
		"active":true,
		"stage":"choosing",
		"round_number":_state.round_number,
		"trigger_player_id":participant_ids[0],
		"forced":forced,
		"participant_ids":participant_ids.duplicate(),
		"chosen_player_ids":[],
		"current_chooser_id":-1,
		"current_resolver_id":-1,
		"options_by_player":options_by_player,
		"selected_cards_by_player":{},
	}
	_state.random_history.append({"kind":"opportunity_options", "round_number":_state.round_number, "trigger_player_id":participant_ids[0], "options_by_player":options_by_player.duplicate(true)})
	_host.add_log("触发全体机缘选择：每名角色从三张机缘卡中选择一张。")
	_selection_pause_token = _host.acquire_gameplay_pause("opportunity_selection")
	_advance_selection_queue()


## 推进全体选择队列；AI直接按机缘估值选牌，遇到真人或远端玩家时广播私有候选并等待动作。
func _advance_selection_queue() -> void:
	while not _selection_queue.is_empty():
		# 当前选择者；队首顺序仅影响交互展示，效果仍要等全部选择完成后统一逆时针结算。
		var chooser_id: int = _selection_queue.pop_front()
		# 当前选择者状态；等待期间死亡或离场时跳过其选择与效果，不阻塞其他参与者。
		var chooser: PlayerState = _state.get_player(chooser_id)
		if chooser == null or not chooser.alive or chooser.out_of_game:
			continue
		_state.opportunity_state["current_chooser_id"] = chooser_id
		_host.refresh_state_snapshot()
		if _host.ai_coordinator != null and _host.ai_coordinator.is_ai_controlled(chooser_id):
			# AI私有候选；从权威映射读取，基础策略不接触其他角色的机缘牌面。
			var options_by_player: Dictionary = _state.opportunity_state.get("options_by_player", {}) as Dictionary
			# AI候选数组；每项均来自静态目录，不包含可执行Callable或运行时对象。
			var ai_options: Array = options_by_player.get(str(chooser_id), []) as Array
			# AI选择结果；空字典只可能来自异常空候选，此时跳过该角色避免死锁。
			var ai_card: Dictionary = _choose_ai_card(chooser_id, ai_options)
			if not ai_card.is_empty():
				_record_player_choice(chooser_id, ai_card)
			continue
		return
	_finish_all_choices()


## 记录一名角色的最终机缘选择；公开状态只暴露已完成角色ID，不在其他观察者快照中公开卡面正文。
func _record_player_choice(player_id: int, card_definition: Dictionary) -> void:
	_selected_cards_by_player[str(player_id)] = card_definition.duplicate(true)
	_state.opportunity_state["selected_cards_by_player"] = _selected_cards_by_player.duplicate(true)
	# 已完成选择角色列表；只追加一次，供等待界面显示进度。
	var chosen_player_ids: Array = (_state.opportunity_state.get("chosen_player_ids", []) as Array).duplicate()
	if not chosen_player_ids.has(player_id):
		chosen_player_ids.append(player_id)
	_state.opportunity_state["chosen_player_ids"] = chosen_player_ids
	_host.add_log("%s已完成机缘选择。" % _host.format_player_log_name(player_id))


## 全体选择完成后释放全局暂停、关闭机缘卡弹窗并开始逆时针逐张结算。
func _finish_all_choices() -> void:
	_state.opportunity_state["current_chooser_id"] = -1
	_state.opportunity_state["stage"] = "resolving"
	if _selection_pause_token >= 0:
		_host.release_gameplay_pause(_selection_pause_token)
		_selection_pause_token = -1
	_host.refresh_state_snapshot()
	call_deferred("_resolve_next_effect")


## 取得逆时针队列中的下一名角色并执行其已选机缘；全部完成后恢复触发前流程。
func _resolve_next_effect() -> void:
	if not is_active() or _state.game_over or _host.has_pending_card_choice():
		return
	while not _resolution_queue.is_empty():
		# 下一名结算角色；队列在触发时已经固定为当前角色起逆时针顺序。
		var owner_player_id: int = _resolution_queue.pop_front()
		# 结算时角色状态；已经死亡或离场角色的已选机缘不再生效。
		var owner: PlayerState = _state.get_player(owner_player_id)
		if owner == null or not owner.alive or owner.out_of_game:
			continue
		# 该角色选择的完整卡定义；未完成选择的异常角色直接跳过。
		var selected_card: Dictionary = _selected_cards_by_player.get(str(owner_player_id), {}) as Dictionary
		if selected_card.is_empty():
			continue
		_current_effect_owner_id = owner_player_id
		_current_effect_card = selected_card.duplicate(true)
		_current_effect_waiting_for_barrier = false
		_state.opportunity_state["current_resolver_id"] = owner_player_id
		_host.add_log("%s触发机缘：%s" % [_host.format_player_log_name(owner_player_id), str(selected_card.get("description", ""))])
		_host.refresh_state_snapshot()
		_effect_resolver.resolve_card(owner_player_id, selected_card)
		return
	_finish_flow()


## 清理当前效果并延迟推进下一名角色；延迟调用避免在伤害或选择回调栈中重入下一张机缘。
func _finish_current_effect_and_continue() -> void:
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	if not _state.opportunity_state.is_empty():
		_state.opportunity_state["current_resolver_id"] = -1
	_host.refresh_state_snapshot()
	call_deferred("_resolve_next_effect")


## 全部机缘结算完成后恢复原阶段，并通过控制器唯一入口续接回合开始或轮末流程。
func _finish_flow() -> void:
	# 恢复信息副本；先清空组件状态，续接阶段若立即触发新请求不会与旧机缘快照混淆。
	var resume_kind: String = _resume_kind
	# 可序列化恢复上下文；控制器会再次校验对局、阶段和当前玩家。
	var resume_context: Dictionary = _resume_context.duplicate(true)
	_state.current_phase = _resume_phase
	_state.opportunity_state.clear()
	_selection_queue.clear()
	_selected_cards_by_player.clear()
	_resolution_queue.clear()
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	_resume_kind = ""
	_resume_context.clear()
	_resume_phase = ""
	_host.refresh_state_snapshot()
	_host.continue_after_opportunity(resume_kind, resume_context)


## 终局或异常无参与者时只清理机缘状态，不尝试恢复已经失效的阶段游标。
func _finish_without_resume() -> void:
	if _selection_pause_token >= 0 and _host != null:
		_host.release_gameplay_pause(_selection_pause_token)
	_selection_pause_token = -1
	_selection_queue.clear()
	_selected_cards_by_player.clear()
	_resolution_queue.clear()
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	_resume_kind = ""
	_resume_context.clear()
	_resume_phase = ""
	if _state != null:
		_state.opportunity_state.clear()
	if _host != null:
		_host.refresh_state_snapshot()


## 初始化新轮相同触发概率；按本轮开始时在场角色数倒数计算，确保2至10人都保持期望约一次。
func _initialize_round_probability(round_number: int) -> void:
	_tracked_round_number = round_number
	_triggered_this_round = false
	# 本轮开始时在场角色数量；死亡与离场角色不获得回合开始触发机会。
	var active_player_count: int = 0
	for player: PlayerState in _state.players:
		if player != null and player.alive and not player.out_of_game:
			active_player_count += 1
	_round_trigger_probability = 1.0 / float(active_player_count) if active_player_count > 0 else 0.0


## 判断当前是否具备开始新机缘流程的基础条件；活动流程、终局或无状态时统一拒绝。
func _can_trigger_now() -> bool:
	return _enabled and _host != null and _state != null and not _state.game_over and _state.opportunity_state.is_empty() and _rng != null


## 从触发角色开始沿座次数组逆时针返回全部在场角色；每名角色只出现一次。
func _build_counterclockwise_order(trigger_player_id: int) -> Array[int]:
	# 逆时针顺序结果；触发角色有效时固定放在首位。
	var result: Array[int] = []
	# 起始角色；无效时优先回退当前回合角色，再回退首名在场角色。
	var start_player: PlayerState = _state.get_player(trigger_player_id)
	if start_player == null or not start_player.alive or start_player.out_of_game:
		start_player = _state.get_player(_state.current_player_id)
	if start_player == null or not start_player.alive or start_player.out_of_game:
		for player: PlayerState in _state.players:
			if player != null and player.alive and not player.out_of_game:
				start_player = player
				break
	if start_player == null:
		return result
	result.append(start_player.player_id)
	# 当前逆时针游标；反复查询上家，直到回到起点或达到总座位数保护上限。
	var cursor_player_id: int = start_player.player_id
	for _step: int in range(maxi(_state.players.size() - 1, 0)):
		# 当前上家；GameState负责跳过死亡与离场角色并处理一号位环回。
		var previous_player: PlayerState = _state.get_previous_alive_player(cursor_player_id)
		if previous_player == null or result.has(previous_player.player_id):
			break
		result.append(previous_player.player_id)
		cursor_player_id = previous_player.player_id
	return result


## 为一名角色抽取互不重复的机缘候选；每张先按品质权重抽品质，再在该品质卡池内等概率抽牌。
func _draw_options_for_player(_player_id: int) -> Array[Dictionary]:
	# 本次候选结果；数量不会超过目录内不同卡牌总数。
	var result: Array[Dictionary] = []
	# 已抽取卡牌ID；同一名角色的三张候选不能重复，其他角色之间允许出现相同机缘。
	var excluded_card_ids: Array[String] = []
	for _option_index: int in range(cards_per_choice):
		# 单张抽取结果；卡池异常耗尽时停止，避免加入空卡占位。
		var card_definition: Dictionary = _draw_single_card(excluded_card_ids)
		if card_definition.is_empty():
			break
		result.append(card_definition)
		excluded_card_ids.append(str(card_definition.get("id", "")))
	return result


## 按当前检查器权重抽取一张未被排除的机缘卡；无可用正权重卡池时回退全部剩余卡等概率抽取。
func _draw_single_card(excluded_card_ids: Array[String]) -> Dictionary:
	# 当前品质权重；运行时读取导出参数，主公调整检查器后无需修改静态目录。
	var weights: Dictionary = get_quality_weights()
	# 可参与抽取的品质到剩余卡池映射；空品质不进入总权重。
	var available_cards_by_quality: Dictionary = {}
	# 当前有效总权重；只累加仍有候选且配置为正数的品质。
	var total_weight: int = 0
	for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
		# 当前品质剩余卡池；过滤同一角色已经抽到的稳定ID。
		var available_cards: Array[Dictionary] = []
		for card_definition: Dictionary in OpportunityCatalog.get_cards_by_quality(quality_id):
			if not excluded_card_ids.has(str(card_definition.get("id", ""))):
				available_cards.append(card_definition)
		available_cards_by_quality[quality_id] = available_cards
		if not available_cards.is_empty():
			total_weight += maxi(int(weights.get(quality_id, 0)), 0)
	if total_weight > 0:
		# 品质权重随机点；范围1至总权重，逐品质扣减保证边界值不会偏向前一品质。
		var quality_roll: int = _rng.randi_range(1, total_weight)
		for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
			# 当前品质剩余卡池；空池或零权重直接跳过。
			var quality_cards: Array = available_cards_by_quality.get(quality_id, []) as Array
			# 当前品质非负权重；负数检查器异常值按0处理。
			var quality_weight: int = maxi(int(weights.get(quality_id, 0)), 0)
			if quality_cards.is_empty() or quality_weight <= 0:
				continue
			quality_roll -= quality_weight
			if quality_roll <= 0:
				return (quality_cards[_rng.randi_range(0, quality_cards.size() - 1)] as Dictionary).duplicate(true)
	# 回退卡池；所有权重为0时仍允许组件工作，便于检查器调试而不产生空弹窗。
	var fallback_cards: Array[Dictionary] = []
	for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
		for card_variant: Variant in available_cards_by_quality.get(quality_id, []) as Array:
			fallback_cards.append((card_variant as Dictionary).duplicate(true))
	if fallback_cards.is_empty():
		return {}
	return fallback_cards[_rng.randi_range(0, fallback_cards.size() - 1)].duplicate(true)


## 为AI从三张机缘中选择综合收益最高的一张；品质基础价值再结合当前体力、手牌和已有技能修正。
func _choose_ai_card(player_id: int, options: Array) -> Dictionary:
	# 当前最高分；负无穷确保首张合法卡可以成为稳定基准。
	var best_score: float = -INF
	# 当前最佳卡；平分保持候选生成顺序，固定种子下结果可复现。
	var best_card: Dictionary = {}
	for option_variant: Variant in options:
		# 当前候选卡；只读取静态参数并交给纯估值函数。
		var card_definition: Dictionary = option_variant as Dictionary
		# 当前候选综合分；高品质通常更强，但无可执行目标或重复技能会降低实际收益。
		var score: float = _score_ai_card(player_id, card_definition)
		if score > best_score:
			best_score = score
			best_card = card_definition.duplicate(true)
	return best_card


## 计算单张机缘对指定AI角色的基础收益；不修改状态、不预抽牌，也不读取其他角色私有候选。
func _score_ai_card(player_id: int, card_definition: Dictionary) -> float:
	# 品质基础价值；体现高品质卡的整体强度，同时允许具体效果按局势覆盖选择。
	var score: float = float({"green":2, "blue":5, "purple":9, "orange":14, "red":22}.get(str(card_definition.get("quality", "green")), 0))
	# 当前AI角色；不存在时只返回品质基础分。
	var player: PlayerState = _state.get_player(player_id)
	if player == null:
		return score
	# 当前效果稳定ID；针对资源、体力与重复技能做局势修正。
	var effect_id: String = str(card_definition.get("effect", ""))
	if effect_id == "draw":
		score += float(int(card_definition.get("count", 0))) * 1.5
	elif effect_id in ["recover", "recover_full"]:
		score += float(maxi(player.max_hp - player.hp, 0)) * 3.0
	elif effect_id in ["max_hp", "double_max_hp"]:
		score += float(player.max_hp) * (1.0 if effect_id == "double_max_hp" else 0.5)
	elif effect_id == "hand_limit":
		score += float(int(card_definition.get("count", 0))) * 2.0
	elif effect_id == "grant_skill":
		# 重复技能不会创建第二个实例，因此AI显著降低已拥有技能卡的价值。
		var skill_id: String = str(card_definition.get("skill_id", ""))
		var owned_skills: Dictionary = _host.skill_instances_by_player.get(player_id, {}) as Dictionary
		score += -12.0 if owned_skills.has(skill_id) else 6.0
	elif effect_id in ["discard_two_from_player", "damage_target", "gain_one_from_player", "max_hp_target", "lose_hp_target", "discard_all_hand_target", "damage_targets", "gain_all_hand_target"]:
		# 敌对角色数量；存在敌人才为负面机缘提供正收益，没有敌人时降低误伤风险。
		var hostile_count: int = 0
		for target: PlayerState in _state.players:
			if target != null and target.alive and not target.out_of_game and target.player_id != player_id and not _host.is_friendly(player_id, target.player_id):
				hostile_count += 1
		score += 5.0 if hostile_count > 0 else -8.0
	elif effect_id == "extra_turns":
		score += float(int(card_definition.get("count", 0))) * 8.0
	return score


## 组件退出场景树时归还仍持有的暂停令牌，避免切换场景后SceneTree永久停留在暂停状态。
func _exit_tree() -> void:
	shutdown()
