extends RefCounted

## 判定的单一内容游标；前置、亮牌、结果、回收与后置时机均由同一序列等待。

## 权威宿主；服务只在当前判定步骤中存活。
var _host: Object

## 同步完成时提供给兼容调用者的结果；异步完成改由原continuation接收。
var result: CardInstance

## 是否已完成全部判定通知；用于区分同步返回与尚待应答的判定。
var completed: bool = false


## 绑定当前权威宿主。
func _init(host: Object) -> void:
	_host = host


## 同步路径直接返回结果；任一窗口暂停时保留同一内容，完成后只调用原接收者一次。
func resolve(request: Dictionary) -> CardInstance:
	# 判定角色快照；等待期间按ID与代次复核，避免旧判定影响换将后的角色。
	var player: PlayerState = _host.state.get_player(int(request.player_id))
	# 步骤上下文只含稳定数据；判定牌对象只在各同步步骤临时读取。
	var context: Dictionary = request.duplicate(true)
	context["sequence_kind"] = "judgment"
	context["character_generation"] = player.character_generation
	context["card_uid"] = -1
	context["cancelled"] = false
	# 每个时机和实体移动独占一步，动态插入的移牌步骤先于下一个窗口完成。
	var steps: Array[Callable] = [_before.bind("judgeBefore"), _before.bind("judgeBegin"), _reveal, _notify.bind("judge"), _present, _notify.bind("judgeFixing"), _record_result, _discard, _notify.bind("judgeEnd"), _notify.bind("judgeAfter"), _complete]
	_host.run_rule_sequence(steps, context)
	if not completed and _host.has_pending_judgment_request(int(request.request_id)):
		_host._pending_judgment_request[int(request.request_id)]["was_paused"] = true
	return result


## 前置最终状态在下一步读取；取消或角色代次失效都不能提前翻牌。
func _read_before(sequence: RuleStepSequence) -> bool:
	if not _host.has_pending_judgment_request(int(sequence.context.request_id)):
		sequence.context["cancelled"] = true
	if sequence.waiting_event != null:
		sequence.context["event_data"] = sequence.waiting_event.data.duplicate(true)
		if sequence.waiting_event.cancelled or sequence.waiting_event.neutralized:
			sequence.context["cancelled"] = true
		sequence.waiting_event = null
	# 当前角色；旧角色的判定不能消耗新武将牌堆结果。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if player == null or not player.alive or player.out_of_game or player.character_generation != int(sequence.context.character_generation):
		sequence.context["cancelled"] = true
	return not bool(sequence.context.cancelled)


## judgeBefore与judgeBegin共享最终规则数据，各自等待全部处理器与其子结算。
func _before(sequence: RuleStepSequence, name: String) -> void:
	if _read_before(sequence):
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, name, int(sequence.context.player_id), int(sequence.context.player_id), int(sequence.context.player_id), sequence.context.event_data, int(sequence.context.parent_event_id)))


## 前置结束后才取牌；移入处理区作为独立子步骤，尚未提交时不发布judge窗口。
func _reveal(sequence: RuleStepSequence) -> void:
	if not _read_before(sequence):
		return
	if _host.state.draw_pile.is_empty():
		_host._reshuffle_discard_pile()
	if _host.state.draw_pile.is_empty():
		_host._end_match_as_draw("deck_empty_judgment")
		return
	# 判定牌实体；只读取此刻牌堆顶，前置改判定技能已完成全部选择。
	var card: CardInstance = _host.state.draw_pile.back()
	sequence.context["card_uid"] = card.uid
	sequence.context["event_id"] = _host._record_runtime_event("judge", "judgment", {"player_id":sequence.context.player_id, "reason":sequence.context.reason}, {}, int(sequence.context.parent_event_id))
	sequence.context["event_data"] = {"player_id":sequence.context.player_id, "reason":sequence.context.reason, "card_uid":card.uid, "card_id":card.definition_id, "suit":card.suit, "rank":card.rank, "color":card.get_color()}
	# 公共判定移牌；实际提交和窗口仍使用唯一牌移动服务。
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(_host)
	movement.begin(sequence, card.uid, "processing", -1, "judge", int(sequence.context.event_id))


## 判定事实通知逐个等待；已开始判定不会因后置通知取消而回滚取牌。
func _notify(sequence: RuleStepSequence, name: String) -> void:
	if int(sequence.context.card_uid) < 0 or not _host.has_pending_judgment_request(int(sequence.context.request_id)):
		return
	sequence.wait_for_timing(_host.emit_sequence_timing(sequence, name, int(sequence.context.player_id), int(sequence.context.player_id), int(sequence.context.player_id), sequence.context.event_data, int(sequence.context.event_id)))


## judge完成后公开展示，保持原判定牌表现来源与弃牌动画所有权。
func _present(sequence: RuleStepSequence) -> void:
	# 当前判定牌；被技能获得时仍可查询其稳定牌面，不重新从牌堆取牌。
	var card: CardInstance = _host._find_card_location_by_uid(int(sequence.context.card_uid)).get("card") as CardInstance
	if card != null:
		# 判定没有牌效果目标；动态宿主调用仍传入正式接口要求的强类型数组。
		var target_ids: Array[int] = []
		_host._request_card_presentation(card, -1, target_ids, "judge", int(sequence.context.event_id), true)
		_host.add_log("%s的%s判定牌为%s。" % [_host._player_character_name(_host.state.get_player(int(sequence.context.player_id))), _host.format_log_reason(str(sequence.context.reason)), _host.describe_card(card)])


## judgeFixing全部完成后记录最终牌面；结果归档不产生第二张实体。
func _record_result(sequence: RuleStepSequence) -> void:
	# 重新取得判定实体；技能改动后的花色、点数才是最终结果。
	var card: CardInstance = _host._find_card_location_by_uid(int(sequence.context.card_uid)).get("card") as CardInstance
	if card != null:
		sequence.context.event_data.merge({"suit":card.suit, "rank":card.rank, "color":card.get_color()}, true)
		_host._record_runtime_event("judgeResult", "judgment_result", {"player_id":sequence.context.player_id, "reason":sequence.context.reason, "card_uid":card.uid}, {"suit":card.suit, "rank":card.rank, "color":card.get_color()}, int(sequence.context.event_id))


## 只回收仍在处理区的判定牌；被技能获得的牌不能从新持有者手中强行丢弃。
func _discard(sequence: RuleStepSequence) -> void:
	if _host._find_processing_card(int(sequence.context.card_uid)) == null:
		return
	# 原判定的弃牌事件；历史与牌移动仍直接关联同一judge，回放和表现使用既有拓扑。
	var discard_event_id: int = _host._record_runtime_event("cardsDiscard", "card_move", {"card_uids":[int(sequence.context.card_uid)], "from_zone":"processing", "reason":"discard"}, {}, int(sequence.context.event_id))
	# 判定牌回收服务；弃牌End/After完成后才能进入judgeEnd。
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(_host)
	movement.begin(sequence, int(sequence.context.card_uid), "discard_pile", -1, "discard", discard_event_id)


## 清理请求后交回调用者；同步返回与异步回调严格互斥。
func _complete(sequence: RuleStepSequence) -> void:
	if not _host.has_pending_judgment_request(int(sequence.context.request_id)):
		result = null
		completed = true
		return
	result = _host._find_card_location_by_uid(int(sequence.context.card_uid)).get("card") as CardInstance
	# 判定提交后仍完整回收，但换将或死亡后的旧结果不能交给新角色继续牌效。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if player == null or not player.alive or player.out_of_game or player.character_generation != int(sequence.context.character_generation):
		result = null
	completed = true
	_host._complete_pending_judgment_request(result, int(sequence.context.request_id))
