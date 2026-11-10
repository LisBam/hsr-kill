extends RefCounted

## 判定阶段外层内容；后来居上，每张延时牌完整结束后才读取下一张。

## 权威宿主；表现延时仍交现有GameFlowPacer管理。
var _host: Object


## 绑定当前对局。
func _init(host: Object) -> void:
	_host = host


## 建立本次阶段代次；换将或跳阶段后旧内容只能释放自己，不能推进新阶段。
func begin(player_id: int, flow_token: int) -> void:
	# 阶段角色；不存在时没有可处理内容。
	var player: PlayerState = _host.state.get_player(player_id)
	# 稳定阶段身份；本阶段已处理UID避免闪电回到本人时反复判定。
	var data: Dictionary = {"sequence_kind":"judgment_area", "player_id":player_id, "flow_token":flow_token, "generation":player.character_generation if player != null else -1, "processed_uids":[], "card_uid":-1, "event_id":-1, "negated":false}
	# 初始有限内容；下一张由当前张收尾之后插入。
	var steps: Array[Callable] = [_next]
	_host.run_rule_sequence(steps, data)


## 从实时判定区末尾取下一张；前置取消的牌本阶段不重复尝试。
func _next(sequence: RuleStepSequence) -> void:
	if not _valid(sequence):
		_finish(sequence)
		return
	# 当前角色；每张结算后重新读取区域。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	# 当前待结算实体；后来居上，已处理牌不再次结算。
	var card: CardInstance
	for index: int in range(player.judgment_area.size() - 1, -1, -1):
		if not (sequence.context.processed_uids as Array).has(player.judgment_area[index].uid):
			card = player.judgment_area[index]
			break
	if card == null:
		_finish(sequence)
		return
	sequence.context.processed_uids.append(card.uid)
	sequence.context.card_uid = card.uid
	sequence.context.negated = false
	sequence.context.event_id = _host._record_runtime_event("delayedJudge", "judgment", {"player_id":player.player_id, "card_uid":card.uid, "card_id":card.definition_id}, {}, _host._current_turn_event_id)
	sequence.insert_steps([_timing, _move, _present, _delay.bind(false), _negation, _apply, _delay.bind(true), _next])


## phaseJudge窗口本身允许插入选择与伤害；移动只在该窗口结束后开始。
func _timing(sequence: RuleStepSequence) -> void:
	# 仍属于本角色的原延时牌。
	var card: CardInstance = _card(sequence)
	if card != null and _valid(sequence):
		_host.emit_sequence_timing(sequence, "phaseJudge", int(sequence.context.player_id), int(sequence.context.player_id), int(sequence.context.player_id), {"card_uid":card.uid, "card_id":card.definition_id}, int(sequence.context.event_id))


## 不提前从判定数组取牌；等待全部移牌窗口后才展示。
func _move(sequence: RuleStepSequence) -> void:
	if sequence.waiting_event != null:
		# 窗口最终取消状态；不读取派发时快照。
		var event: RuleEvent = sequence.waiting_event
		sequence.waiting_event = null
		if event.cancelled or event.neutralized:
			return
	# 当前实体；等待期间离区则本张跳过。
	var card: CardInstance = _card(sequence)
	if card == null or card.zone != "judgment" or not _valid(sequence):
		return
	# 单牌移动服务；所属父阶段保持等待。
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(_host)
	movement.begin(sequence, card.uid, "processing", -1, "judge", int(sequence.context.event_id))


## 已进入处理区才取得展示所有权；取消移动不会产生虚假判定展示。
func _present(sequence: RuleStepSequence) -> void:
	# 处理区中的当前延时牌。
	var card: CardInstance = _processing_card(sequence)
	if card == null:
		return
	# 展示目标数组；延时牌只关联判定角色。
	var targets: Array[int] = []
	_host._request_card_presentation(card, int(sequence.context.player_id), targets, "delayedJudge", int(sequence.context.event_id), true)
	_host.add_log("%s开始判定%s。" % [_host.format_player_log_name(int(sequence.context.player_id)), _host.describe_card(card)])
	_host._emit_state()


## 表现停留通过既有可取消节奏任务持有边界，计时器不直接推进回合。
func _delay(sequence: RuleStepSequence, result_pause: bool) -> void:
	if _processing_card(sequence) == null and not result_pause:
		return
	# 当前展示间隔；空match_id预演不等待真实时间。
	var seconds: float = _host.delayed_judgment_result_pause_seconds if result_pause else _host.delayed_judgment_preview_seconds
	if seconds > 0.0 and not _host.state.match_id.is_empty() and _host.game_flow_pacer != null:
		_host.game_flow_pacer.schedule("delayed_judgment:%d" % sequence.sequence_id, seconds, Callable(_host, "_resume_settlement_pipeline"))


## 无懈只写本序列结果槽；原通用恢复器不能在链中途直接应用延时牌。
func _negation(sequence: RuleStepSequence) -> void:
	# 当前待生效延时牌；角色已失效则交收尾处理。
	var card: CardInstance = _processing_card(sequence)
	if card == null or not _valid(sequence):
		return
	sequence.context.negated = _host.resolve_trick_negation(-1, int(sequence.context.player_id), card.definition_id, {"parent_card_uid":card.uid, "delayed_judgment":true, "judgment_area_sequence_id":sequence.sequence_id})


## 卡牌定义可创建自己的判定、伤害和移牌；下一张等待完整子树。
func _apply(sequence: RuleStepSequence) -> void:
	# 原延时牌；无论目标是否失效都不得遗留在处理区。
	var card: CardInstance = _processing_card(sequence)
	if card == null:
		return
	if not _valid(sequence):
		_host.discard_delayed_card(card)
		return
	_host._resolve_delayed_judgment_card(int(sequence.context.player_id), card, bool(sequence.context.negated))
	_host._emit_state()


## 阶段身份校验；选择临时改变phase后仅在恢复原阶段时继续。
func _valid(sequence: RuleStepSequence) -> bool:
	# 当前角色；换将不能把旧判定跳过标记施加给新武将。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	return player != null and player.alive and not player.out_of_game and player.character_generation == int(sequence.context.generation) and _host._is_judgment_flow_valid(player.player_id, int(sequence.context.flow_token))


## 按UID查回实体；离开处理区或原判定区的牌不再属于本内容。
func _card(sequence: RuleStepSequence) -> CardInstance:
	# 实时位置；允许原持有者判定区和公共处理区。
	var location: Dictionary = _host._find_card_location_by_uid(int(sequence.context.card_uid))
	if str(location.get("zone", "")) == "processing" or (str(location.get("zone", "")) == "judgment" and int(location.get("owner_id", -1)) == int(sequence.context.player_id)):
		return location.get("card") as CardInstance
	return null


## 仅处理区实体才可应用效果。
func _processing_card(sequence: RuleStepSequence) -> CardInstance:
	# 当前实体；取消或已经传递的牌不重复结算。
	var card: CardInstance = _card(sequence)
	return card if card != null and card.zone == "processing" else null


## 原阶段排空后唯一推进后继；旧代次内容不能清理新阶段标志。
func _finish(sequence: RuleStepSequence) -> void:
	if int(sequence.context.flow_token) != int(_host._judgment_flow_token):
		return
	_host._judgment_flow_in_progress = false
	if _valid(sequence):
		_host._continue_turn_after_judgment(int(sequence.context.player_id))
