extends SkillDefinition

## 【风口】两段式技能。
##
## 第一段（被动、可选）：当你一次性获得至少两张牌时，你可以弃置这些牌。
##   由核心的批量获得时机 `cardsGainedBatchAfter` 提供「一次性」的批次边界；候选精确限定为
##   本批次的牌且 min = max = 批次张数，因此「这些牌」不可能被替换成手牌里的其他牌。
##   取消表示放弃本次机会，不产生任何记录。
##
## 第二段（主动、出牌阶段、不限次）：你可以获得一名其他角色的随机一张手牌，
##   你此前每发动一次第一段便重复一次该流程，然后你失去该技能。
##   原文没有「出牌阶段限一次」，因此不做次数限制；代价是发动后**永久失去本技能**。
##
## 两段之间用 `character_form_state` 中的持久计数连接：第一段每成功弃置一次 `+1`，
## 第二段按 `1 + 计数` 计算重复次数。计数放在公开且随存档往返的角色状态里，
## 因此读档、换将回来、甚至技能被移除后重新获得都保持同一份历史。
##
## 第一段的重复次数只由第一段累加：第二段发动的瞬间就会移除本技能，因此不存在
## 「第二段自己给自己加次数」的反馈循环。

## 手牌区域名；只有落入该区域的获得才构成第一段的批次来源（核心已保证该时机的语义）。
const HAND_ZONE_NAME: String = "hand"
## 第一段要求的最小批量张数；单张获得不构成「一次性获得至少两张牌」。
const MIN_BATCH_SIZE: int = 2
## 开局配置阶段的阶段名；`gameStart` 时机就在该阶段派发。
##
## 【筹码】的锁定技摸牌发生在 `game_start` 阶段，属于武将初始化而不是对局中的「一次性获得」：
## 此时玩家刚确认完起手牌、还没有任何局面信息，若在这里弹出「是否弃置整批牌」，
## 玩家只能在完全未知的情况下决定，而且开局流程会停在选择界面等一个毫无信息量的答案。
## 因此本技能显式跳过该阶段的批次，与核心「起手换牌不构成获得批次」的口径保持一致。
const GAME_START_PHASE_NAME: String = "game_start"
## 第一段发动次数在 character_form_state 中的稳定键名；随存档持久化，不使用实例字段。
const CLAUSE1_COUNT_KEY: String = "fengkou_clause1_count"
## 第二段的基础重复次数；「获得一名其他角色的随机一张手牌」至少执行一次。
const BASE_REPEAT_COUNT: int = 1
## 请求、延迟上下文中共用的种类键名。
const CHOICE_KIND_KEY: String = "kind"
## 第一段「弃置整批牌」的请求种类。
const CHOICE_CLAUSE1: String = "fengkou_clause1"
## 第二段「选择一名其他角色」的请求种类。
const CHOICE_CLAUSE2_TARGET: String = "fengkou_clause2_target"
## 第一段批次排队期间遇到嵌套结算时的延迟种类；嵌套收尾后继续排空批次队列。
const DEFER_PROCESS_QUEUE: String = "fengkou_defer_process_queue"
## 第二段目标已确定但遇到嵌套结算时的延迟种类；嵌套收尾后再执行连续获得。
const DEFER_EXECUTE_CLAUSE2: String = "fengkou_defer_clause2"
## 延迟上下文中携带目标玩家 ID 的键名。
const TARGET_ID_KEY: String = "target_id"
## 延迟上下文中携带第二段重复次数的键名。
const REPEAT_TOTAL_KEY: String = "repeat_total"
## 延迟上下文中携带第一段本批次牌 UID 的键名。
const BATCH_UIDS_KEY: String = "batch_uids"
## 随机取手牌的历史种类；同一随机流中按该键记录本次取牌，保证联机两端结果一致。
const RANDOM_HISTORY_KIND: String = "fengkou_random_hand"
## 随机取牌历史中的目标键名。
const RANDOM_HISTORY_TARGET_KEY: String = "target_id"
## 随机取牌历史中的第几次重复键名。
const RANDOM_HISTORY_INDEX_KEY: String = "repeat_index"
## 随机取牌历史中的回合号键名；用于复盘与一致性校验。
const RANDOM_HISTORY_TURN_KEY: String = "turn_number"
## 发动公告中的目标玩家键名。
const ACTIVATION_TARGET_KEY: String = "target_id"
## 发动公告中的实际获得张数键名。
const ACTIVATION_GAINED_KEY: String = "gained_count"
## 发动公告中的计划重复次数键名。
const ACTIVATION_REPEAT_KEY: String = "repeat_total"
## 技能被自身效果移除时的原因标记；写入日志便于回溯技能消失的来源。
const SKILL_LOST_REASON: String = "fengkou_active"
## 第二段的请求提示文本；说明本次会连续获得几张牌。
const CLAUSE2_PROMPT: String = "请选择一名其他角色，你获得其随机一张手牌"
## 第一段的请求提示文本；说明必须弃置整批牌才能积累次数。
const CLAUSE1_PROMPT: String = "你可以弃置这批刚获得的牌，为【风口】积累一次发动次数"
## 确认提交的保底分；远高于任何单张牌面收益，使「是否继续」只由真实收益的小数部分决定。
const AI_STEP_COMMIT_REWARD: float = 100.0
## 第一段每积累一次的期望价值；等价于「将来多偷一张牌」的折算收益。
## 取值必须与「弃置牌的保留价值 × AI_COST_WEIGHT」同量级：本项目第一张【杀】的保留价值是 `5.0`，
## 折算后约 `1.75` 点资源，因此 `2.0` 表示「用一张普通好牌换一次积累」略微划算，
## 而一次弃置两张好牌（约 `3.5` 点资源）就会转为放弃。
const AI_CLAUSE1_SETUP_VALUE: float = 2.0
## 费用牌保留价值的权重；批次越大总费用越高，AI 因此更容易在大批次上放弃。
const AI_COST_WEIGHT: float = 0.35
## 应当放弃时的负分；通用评分给「取消」的基准是0.0，因此必须给出严格负分才能让取消成为最优解。
const AI_DECLINE_PENALTY: float = 5.0
## 第二段发动的最小重复次数；只偷一张牌就永久失去本技能并不划算，因此要求先积累到该次数。
const AI_MIN_REPEAT_COUNT: int = 2
## 失去本技能的机会成本；发动第二段后本技能永久消失，收益必须超过该阈值才值得。
const AI_SKILL_LOSS_COST: float = 0.5
## 第二段发动入口的固定正分；高于普通用牌的排序分，使累计足够次数时优先兑现。
const AI_CLAUSE2_ACTION_BASE: float = 6.0

## 等待处理的第一段批次队列；每项是本批次牌的 UID 数组副本。
var _batch_queue: Array[Array] = []
## 批次队列是否已经登记过延迟恢复；避免嵌套结算期间反复登记同一条后续。
var _queue_defer_registered: bool = false


func _init() -> void:
	super({
		"id": "fengkou",
		"name": "风口",
		"trigger": "active/phaseUse",
		"enable": "phaseUse",
		"ui_enabled": true,
		"description": "当你一次性获得至少两张牌时，你可以弃置这些牌。出牌阶段，你可以获得一名其他角色的随机一张手牌，你此前每发动一次该技能便重复一次该流程，然后你失去该技能。",
	})


func install() -> void:
	# 批量获得时机以接收方为 player_id 派发，因此 role="player" 只命中砂金自己的获得。
	subscribe_timing("cardsGainedBatchAfter", _on_cards_gained_batch, "player")


## 第一段是否开放入口：出牌阶段、无待处理选择、且存在至少一名有手牌的其他角色。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；阵亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = _owner_ready()
	if owner == null:
		return false
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 已存在待处理选择时不再开放入口；控制器会拒绝第二个请求，提前拦下可避免按钮空点。
	if host.has_pending_card_choice():
		return false
	return not _get_legal_target_ids().is_empty()


## 询问第二段的目标；确认后连续获得其随机手牌，然后失去本技能。
func activate(_context: Dictionary = {}) -> String:
	if not can_activate():
		return "【风口】当前不满足发动条件。"
	# 合法目标；其他存活在场且至少有一张手牌的角色。
	var target_ids: Array[int] = _get_legal_target_ids()
	# 本次计划重复次数；第一段的基础次数加上此前积累的次数。
	var repeat_total: int = _current_repeat_total()
	var selected_targets: Array[int] = request_target_selection(CLAUSE2_PROMPT, target_ids, 1, 1, true, {CHOICE_KIND_KEY:CHOICE_CLAUSE2_TARGET, REPEAT_TOTAL_KEY:repeat_total})
	# 无正式对局 ID 的同步规则测试不会通过 continue_selection 回调，需在此直接应用返回结果。
	if not host.has_pending_card_choice():
		_apply_clause2_target(selected_targets)
	return ""


## 恢复由本技能创建的选择；第一段与第二段共用同一回调，按种类分派。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 请求种类；未识别时交回控制器继续查找其他技能。
	var kind: String = str(context.get(CHOICE_KIND_KEY, ""))
	if kind == CHOICE_CLAUSE1:
		if response != null and response.confirmed:
			_apply_clause1_discard(response.card_ids)
		_queue_defer_registered = false
		_process_batch_queue()
		return true
	if kind == CHOICE_CLAUSE2_TARGET:
		if response != null and response.confirmed:
			_apply_clause2_target(response.target_ids)
		return true
	return false


## 恢复因嵌套结算暂停的步骤：排空批次队列，或执行已经选好目标的第二段。
func continue_settlement(context: Dictionary) -> bool:
	# 延迟种类；未识别时交回控制器。
	var kind: String = str(context.get(CHOICE_KIND_KEY, ""))
	if kind == DEFER_PROCESS_QUEUE:
		_queue_defer_registered = false
		_process_batch_queue()
		return true
	if kind == DEFER_EXECUTE_CLAUSE2:
		_execute_clause2(int(context.get(TARGET_ID_KEY, -1)))
		return true
	return false


## 处理一批「一次性获得」的牌；批次张数不足时直接忽略。
func _on_cards_gained_batch(event: RuleEvent) -> void:
	if host == null:
		return
	if int(event.data.get("receiver_player_id", -1)) != owner_player_id:
		return
	if int(event.data.get("batch_size", 0)) < MIN_BATCH_SIZE:
		return
	# 开局配置阶段的批次不计入：该阶段只有【筹码】的锁定技摸牌，属于武将初始化而不是对局中的获得。
	if str(host.state.current_phase) == GAME_START_PHASE_NAME:
		return
	# 本批次牌的 UID 副本；批次事件可能携带其他键，这里只保留第一段真正需要的成员。
	var batch_uids: Array[int] = []
	for uid_variant: Variant in event.data.get("card_uids", []) as Array:
		batch_uids.append(int(uid_variant))
	if batch_uids.size() < MIN_BATCH_SIZE:
		return
	_batch_queue.append(batch_uids)
	# 批次事件是在**正在执行的结算内部**派发的，而第一段是一个需要玩家作答的可选询问。
	# 若在这里立刻创建请求，控制器会在本轮结算尚未收尾时进入“等待选择”，于是同一段核心流程随后发起的规则序列
	# 会被静默丢弃：过关斩将整层换将时敌人的入场摸牌会让紧随其后的复活者起始手牌摸牌失效，玩家复活后拿不到牌。
	# 因此本技能一律先登记一条延后步骤，把询问留到下一个结算边界；排队机制保证同一时刻只登记一次。
	if _queue_defer_registered:
		return
	_queue_defer_registered = true
	if not defer_settlement({CHOICE_KIND_KEY:DEFER_PROCESS_QUEUE}):
		# 登记失败（技能已失效或超出连锁上限）时必须放开标记，否则队列会被永久卡死。
		_queue_defer_registered = false


## 逐个处理排队的批次；遇到嵌套结算或已有待处理选择时先登记后续，绝不叠加第二个未决请求。
func _process_batch_queue() -> void:
	if host == null or _batch_queue.is_empty():
		return
	if host.has_nested_settlement_barrier():
		# 同一条后续只登记一次，避免嵌套期间反复入队导致恢复时重复询问。
		if not _queue_defer_registered:
			_queue_defer_registered = true
			if not defer_settlement({CHOICE_KIND_KEY:DEFER_PROCESS_QUEUE}):
				_queue_defer_registered = false
		return
	_begin_clause1(_batch_queue.pop_front())


## 建立第一段的请求；候选精确限定为本批次仍在持有者手牌或装备区中的牌。
func _begin_clause1(batch_uids: Array[int]) -> void:
	# 本批次中当前仍可被弃置的候选；等待期间被其他效果移走的牌自动退出。
	var candidates: Array[Dictionary] = _collect_batch_candidates(batch_uids)
	if candidates.is_empty():
		_process_batch_queue()
		return
	# 必须整批弃置：min 与 max 都等于候选张数，因此玩家无法只弃置其中一部分。
	var required_count: int = candidates.size()
	var selected_uids: Array[int] = request_card_selection("风口", CLAUSE1_PROMPT, candidates, required_count, required_count, true, {CHOICE_KIND_KEY:CHOICE_CLAUSE1, BATCH_UIDS_KEY:batch_uids.duplicate()})
	# 同步规则测试路径：没有待处理请求说明结果已经同步返回。
	if not host.has_pending_card_choice():
		if selected_uids.size() == required_count:
			_apply_clause1_discard(selected_uids)
		_queue_defer_registered = false
		_process_batch_queue()


## 处理第一段的弃置结果；只有实际弃置成功才累加次数。
func _apply_clause1_discard(selected_uids: Array[int]) -> void:
	if selected_uids.is_empty() or host == null:
		return
	# 统一弃置端口的实际弃置张数；与提交张数不一致时视为部分失效，仍按「本批次已弃置」累加一次。
	var discarded_count: int = int(host.call("discard_selected_hand_equipment", owner_player_id, selected_uids))
	if discarded_count <= 0:
		return
	_increment_clause1_count()
	announce_activation({ACTIVATION_TARGET_KEY:-1, ACTIVATION_GAINED_KEY:discarded_count, ACTIVATION_REPEAT_KEY:_current_repeat_total()})


## 收集本批次中当前仍在持有者手牌或装备区中的候选；保持批次自身的顺序。
func _collect_batch_candidates(batch_uids: Array[int]) -> Array[Dictionary]:
	# 最终候选；顺序沿用批次记录的先后，使界面展示与批次成员一致。
	var result: Array[Dictionary] = []
	if host == null:
		return result
	# 持有者自己的手牌与装备区快照；本技能只弃置自己刚获得的牌。
	var owned_candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# UID 到候选的索引；避免对每个批次成员都线性扫描一次快照。
	var candidate_by_uid: Dictionary = {}
	for candidate: Dictionary in owned_candidates:
		candidate_by_uid[int(candidate.get("uid", -1))] = candidate
	for card_uid: int in batch_uids:
		if candidate_by_uid.has(card_uid):
			result.append(candidate_by_uid[card_uid] as Dictionary)
	return result


## 处理第二段的目标选择结果；目标非法时本次不发动，也不移除技能。
func _apply_clause2_target(selected_targets: Array[int]) -> void:
	if selected_targets.size() != 1:
		return
	# 本次选定的目标；必须在当前仍然合法，否则视为等待期间失效。
	var target_id: int = selected_targets[0]
	if not _get_legal_target_ids().has(target_id):
		return
	if host.has_nested_settlement_barrier():
		defer_settlement({CHOICE_KIND_KEY:DEFER_EXECUTE_CLAUSE2, TARGET_ID_KEY:target_id})
		return
	_execute_clause2(target_id)


## 连续获得目标角色的随机手牌，然后移除本技能；一次都没获得时不消耗技能。
func _execute_clause2(target_id: int) -> void:
	if host == null or not _get_legal_target_ids().has(target_id):
		return
	# 本次计划重复次数；每次重复前都重新统计目标手牌，牌被取完后提前结束。
	var repeat_total: int = _current_repeat_total()
	# 实际获得张数；为0表示等待期间目标已经没有手牌，本次不产生效果也不失去技能。
	var gained_count: int = 0
	# 已完成的重次数；只作为随机历史与循环控制使用，不参与规则判定。
	var repeat_index: int = 0
	while repeat_index < repeat_total:
		# 目标当前手牌候选；他人手牌为不可见候选，但 UID 稳定，因此可以按索引随机取一张。
		var hand_candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
		if hand_candidates.is_empty():
			break
		# 随机索引；通过权威随机端口取值，保证本地、AI 与联机两端得到同一张牌。
		var random_index: int = int(host.call("pick_random_candidate_index", hand_candidates.size(), RANDOM_HISTORY_KIND, {RANDOM_HISTORY_TARGET_KEY:target_id, RANDOM_HISTORY_INDEX_KEY:repeat_index, RANDOM_HISTORY_TURN_KEY:int(host.state.turn_number)}))
		if random_index < 0 or random_index >= hand_candidates.size():
			break
		# 本次要获得的实体牌 UID；获取失败说明等待期间牌已离开目标区域。
		var card_uid: int = int((hand_candidates[random_index] as Dictionary).get("uid", -1))
		if card_uid < 0:
			break
		if not bool(host.call("take_selected_player_card", owner_player_id, target_id, card_uid)):
			break
		gained_count += 1
		repeat_index += 1
	if gained_count <= 0:
		return
	announce_activation({ACTIVATION_TARGET_KEY:target_id, ACTIVATION_GAINED_KEY:gained_count, ACTIVATION_REPEAT_KEY:repeat_total})
	observe_identity_behavior([target_id], {"target_result":-1.0})
	host.call("remove_skill", owner_player_id, get_id(), SKILL_LOST_REASON)


## 读取第一段的发动次数；状态缺失或异常时按0处理。
func _get_clause1_count() -> int:
	# 技能持有者权威状态；未就绪时没有可读取的计数。
	var owner: PlayerState = _owner_ready()
	if owner == null:
		return 0
	return maxi(int(owner.character_form_state.get(CLAUSE1_COUNT_KEY, 0)), 0)


## 累加第一段的发动次数；计数写入公开可持续化的角色状态，因此读档后仍然有效。
func _increment_clause1_count() -> void:
	# 技能持有者权威状态；未就绪时不写入，避免把计数挂到错误的角色上。
	var owner: PlayerState = _owner_ready()
	if owner == null:
		return
	owner.character_form_state[CLAUSE1_COUNT_KEY] = _get_clause1_count() + 1


## 第二段本次的计划重复次数；基础1次加此前积累的发动次数。
func _current_repeat_total() -> int:
	return BASE_REPEAT_COUNT + _get_clause1_count()


## 当前仍然合法的第二段目标：其他存活在场且至少有一张手牌的角色。
func _get_legal_target_ids() -> Array[int]:
	# 最终目标列表；顺序沿用核心按座次给出的顺序，保证本地、AI 与联机两端一致。
	var result: Array[int] = []
	if host == null:
		return result
	for target_id: int in host.call("get_other_alive_player_ids", owner_player_id) as Array[int]:
		# 目标当前手牌候选；为空表示无法「获得其随机一张手牌」，不构成合法目标。
		var hand_candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id) as Array[Dictionary]
		if not hand_candidates.is_empty():
			result.append(target_id)
	return result


## 返回可用的技能持有者状态；未安装、已阵亡或已离场时返回 null。
func _owner_ready() -> PlayerState:
	if host == null:
		return null
	# 技能持有者权威状态；技能卸载后 get_owner_skill_player() 仍可返回玩家，因此必须同时校验存活与在场。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return null
	return owner


## 向出牌阶段合法动作列表追加第二段入口；第一段是被动触发，没有主动动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 评估第二段的发动价值：按计划重复次数估算从最优目标处获得的牌，再扣减永久失去本技能的机会成本。
## 累计次数不足时返回0让AI继续用第一段积累，而不是过早兑现这张一次性的技能。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	# 本次计划重复次数；决定能从单个目标处获得多少张牌。
	var repeat_total: int = _current_repeat_total()
	if repeat_total < AI_MIN_REPEAT_COUNT:
		return 0.0
	# 最优目标收益；目标失去 repeat_total 张牌，按统一资源口径与身份态度折算。
	var best_value: float = 0.0
	for target_id: int in _get_legal_target_ids():
		best_value = maxf(best_value, float(evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, -repeat_total, 0)))
	if best_value <= AI_SKILL_LOSS_COST:
		return 0.0
	return AI_CLAUSE2_ACTION_BASE + best_value - AI_SKILL_LOSS_COST


## 计算基础 AI 对两段选择的评分；应当放弃的分支返回严格负分，让通用评分的「取消」基准胜出。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	if evaluator == null:
		return 0.0
	# 请求种类；只有本技能的两段参与评分，其他请求交回通用评分。
	var kind: String = str((choice_request.get("context", {}) as Dictionary).get(CHOICE_KIND_KEY, ""))
	# 动作载荷；取消是合法选择，按0分交回通用比较。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var confirmed: bool = bool(payload.get("confirmed", false))
	if kind == CHOICE_CLAUSE1:
		if not confirmed:
			return 0.0
		# 本批次弃置的牌对持有者的保留价值总和；批次越大总费用越高。
		var batch_cost: float = 0.0
		for uid_variant: Variant in payload.get("selected_card_uids", []) as Array:
			batch_cost += float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(uid_variant), owner_player_id))
		# 净收益；一次发动只积累一次次数，因此整批牌越贵越应该放弃。
		var batch_net: float = AI_CLAUSE1_SETUP_VALUE - batch_cost * AI_COST_WEIGHT
		if batch_net <= 0.0:
			return -AI_DECLINE_PENALTY
		return AI_STEP_COMMIT_REWARD + batch_net
	if kind == CHOICE_CLAUSE2_TARGET:
		if not confirmed:
			return 0.0
		# 本次选择的目标；数量恒为1，协议异常时交回通用评分。
		var selected_targets: Array = payload.get("selected_target_ids", []) as Array
		if selected_targets.is_empty():
			return 0.0
		# 本次计划重复次数；由请求上下文携带，使评分不依赖实例字段。
		var repeat_total: int = maxi(int((choice_request.get("context", {}) as Dictionary).get(REPEAT_TOTAL_KEY, BASE_REPEAT_COUNT)), BASE_REPEAT_COUNT)
		# 目标收益；目标失去 repeat_total 张牌，敌方为正、友方为负。
		var target_value: float = float(evaluator.score_resource_change(authoritative_snapshot, owner_player_id, int(selected_targets[0]), -repeat_total, 0))
		if target_value <= 0.0:
			return -AI_DECLINE_PENALTY
		return AI_STEP_COMMIT_REWARD + target_value
	return 0.0
