extends RefCounted

## 摸牌内容组件；等待摸牌与获得牌窗口后才提交每张牌的区域变化。

## 当前权威控制器；仅通过稳定公开规则端口访问对局状态。
var _host: Object

## 当前单张获得游标；摸牌批次持有自身结果，不把成员登记到全局异步栈。
var _movement: CardMoveResolutionService


## 绑定本局规则宿主；服务不拥有控制器生命周期。
func _init(host: Object) -> void:
	_host = host


## 建立一条摸牌序列；每个获得牌窗口完成后才移动对应牌。
func draw(player_id: int, count: int, announce: bool, allow_out_of_game: bool) -> int:
	# 当前摸牌角色；死亡、缺失或未获准离场角色没有摸牌内容。
	var player: PlayerState = _host.state.get_player(player_id)
	if player == null or not player.alive or (player.out_of_game and not allow_out_of_game):
		return -1
	# 稳定代次；暂停期间换将后旧摸牌不再进入新角色手牌。
	var context: Dictionary = {
		"sequence_kind":"draw",
		"player_id":player_id,
		"generation":player.character_generation,
		"requested_count":maxi(count, 0),
		"announce":announce,
		"allow_out_of_game":allow_out_of_game,
		"drawn_uids":[],
		"remaining_count":0,
		"current_card_uid":-1,
		"current_move_id":-1,
		"cancelled":false,
		"deck_exhausted":false,
		"event_id":_host._current_rule_parent_event_id(),
		"batch_started":false,
		"previous_batch":{},
		"result_data":{},
	}
	var steps: Array[Callable] = [_timing.bind("drawBefore"), _timing.bind("drawBegin"), _prepare_batch]
	return _host.run_rule_sequence(steps, context)


## 读取前一窗口的最终数据；取消后发送drawCancelled并停止主体。
func _timing(sequence: RuleStepSequence, timing_name: String) -> void:
	if not _valid_target(sequence):
		sequence.finish()
		return
	if bool(sequence.context.cancelled):
		return
	# 本窗口共用数据；Before之后读取原事件最终修改，而非派发时的早期副本。
	var event_data: Dictionary = {"count":int(sequence.context.requested_count), "reason":"draw"}
	var previous_event: RuleEvent = sequence.waiting_event
	if sequence.waiting_event != null:
		event_data = sequence.waiting_event.data.duplicate(true)
		sequence.waiting_event = null
	# 当前摸牌前置事件；取消不会建立表现批次或移动实体。
	if previous_event != null and (previous_event.cancelled or previous_event.neutralized):
		sequence.context["cancelled"] = true
		sequence.insert_steps([Callable(self, "_emit_cancelled")])
		return
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.player_id), -1, int(sequence.context.player_id), event_data)
	# emit_sequence_timing将刚派发的原事件放回sequence.waiting_event；下一窗口负责读取。
	sequence.context["last_timing_name"] = timing_name


## 派发取消事实；其子选择结束后序列跳过摸牌主体。
func _emit_cancelled(sequence: RuleStepSequence) -> void:
	# 被取消的原窗口最终数据；取消通知保留触发器已经写入的字段。
	var event_data: Dictionary = sequence.waiting_event.data.duplicate(true) if sequence.waiting_event != null else {"count":int(sequence.context.requested_count), "reason":"draw"}
	_host.emit_sequence_timing(sequence, "drawCancelled", int(sequence.context.player_id), -1, int(sequence.context.player_id), event_data)
	sequence.insert_steps([Callable(self, "_finish_cancelled")])


## drawCancelled完成后停止序列；没有End/After，因为摸牌主体未开始。
func _finish_cancelled(sequence: RuleStepSequence) -> void:
	sequence.finish()


## 建立独立表现批次并插入摸牌主体与事实尾部。
func _prepare_batch(sequence: RuleStepSequence) -> void:
	if not _valid_target(sequence) or bool(sequence.context.cancelled):
		sequence.finish()
		return
	# Begin也必须读取同一个原窗口的最终取消状态；不先建立表现或获得批次。
	if sequence.waiting_event != null and (sequence.waiting_event.cancelled or sequence.waiting_event.neutralized):
		sequence.context["cancelled"] = true
		sequence.insert_steps([_emit_cancelled])
		return
	# Begin的最终修改；负数归零，触发器不能构造反向摸牌。
	var final_count: int = maxi(int(sequence.waiting_event.data.get("count", sequence.context.requested_count)) if sequence.waiting_event != null else int(sequence.context.requested_count), 0)
	sequence.waiting_event = null
	sequence.context["requested_count"] = final_count
	sequence.context["remaining_count"] = final_count
	# 上一表现批次；嵌套摸牌完成后恢复外层归属。
	sequence.context["previous_batch"] = (_host._active_draw_presentation_batch as Dictionary).duplicate(true)
	_host._draw_presentation_batch_sequence += 1
	# 本次批次只公开稳定ID和目标角色。
	var batch: Dictionary = {"batch_id":_host._draw_presentation_batch_sequence, "player_id":int(sequence.context.player_id)}
	_host._active_draw_presentation_batch = batch
	sequence.context["batch_started"] = true
	# 获得批次作用域；同一次摸牌的全部牌共享一个 cardsGainedBatchAfter 事件。
	# 必须在这里开启而不是在 draw() 入口：_prepare_batch 之前的所有取消与无效目标路径都不该建立批次。
	# 开局前分发起始手牌期间不建立获得批次：那是开局前的准备行为而不是对局内的获得，
	# 若建立批次会让「当你获得牌时」类技能（例如【风口】）在手气卡阶段之前弹出询问并占住阶段。
	if not bool(_host._before_match_start_deal_active):
		sequence.context["gain_batch_id"] = _host._next_gain_batch_id
		_host._next_gain_batch_id += 1
		sequence.context["gain_batch_started"] = true
	_host.draw_presentation_batch_started.emit(int(batch.batch_id), int(batch.player_id))
	sequence.insert_steps([_draw_next_card, _draw_end, _draw_after, _finish_presentation, _finish_gain_batch, _finish_batch, _end_exhausted_draw])


## 取当前牌堆顶并插入其获得牌完整时序；每次只创建一张牌的有限步骤。
func _draw_next_card(sequence: RuleStepSequence) -> void:
	if not _valid_target(sequence) or int(sequence.context.remaining_count) <= 0:
		return
	if _host.state.draw_pile.is_empty():
		_host._reshuffle_discard_pile()
	if _host.state.draw_pile.is_empty():
		sequence.context["deck_exhausted"] = true
		return
	# 当前牌堆顶；仅保存UID，后续步骤从权威区域重新查找。
	var card: CardInstance = _host.state.draw_pile.back() as CardInstance
	sequence.context["current_card_uid"] = card.uid
	sequence.context["source_zone"] = "draw_pile"
	sequence.context["remaining_count"] = int(sequence.context.remaining_count) - 1
	_movement = CardMoveResolutionService.new(_host)
	sequence.insert_steps([_record_drawn_card, _draw_next_card])
	_movement.begin(sequence, card.uid, "hand", int(sequence.context.player_id), "draw", int(sequence.context.event_id), "", [int(sequence.context.player_id)] as Array[int], false, false, -2, bool(sequence.context.allow_out_of_game))


## 单张完整获得后只记录本次成功事实；取消或嵌套移走材料不混入其他摸牌批次。
func _record_drawn_card(sequence: RuleStepSequence) -> void:
	if _movement != null and bool(_movement.result.get("success", false)):
		(sequence.context.drawn_uids as Array).append(int(_movement.result.card_uid))



## 摸牌完成事实及统计先提交，再开放drawEnd和drawAfter。
func _draw_end(sequence: RuleStepSequence) -> void:
	if not _same_generation(sequence):
		return
	# 摸牌玩家；代次已验证且实际获得牌数即是统计增量。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	var drawn_uids: Array = sequence.context.drawn_uids as Array
	player.total_cards_drawn += drawn_uids.size()
	sequence.context["result_data"] = {"count":drawn_uids.size(), "requested_count":int(sequence.context.requested_count), "card_uids":drawn_uids.duplicate(), "reason":"draw"}
	_host.emit_sequence_timing(sequence, "drawEnd", player.player_id, -1, player.player_id, sequence.context.result_data)


## drawEnd子内容完成后发布drawAfter；通知取消不回滚摸牌。
func _draw_after(sequence: RuleStepSequence) -> void:
	if not _same_generation(sequence):
		return
	_host.emit_sequence_timing(sequence, "drawAfter", int(sequence.context.player_id), -1, int(sequence.context.player_id), sequence.context.result_data)


## 实体摸牌及drawAfter结束后关闭表现收集；规则批次仍继续等待获得技能，不让交互阻止动画登记。
func _finish_presentation(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.batch_started):
		# 当前批次；完成信号发出时仍能读取本批ID。
		var batch: Dictionary = _host._active_draw_presentation_batch as Dictionary
		_host.draw_presentation_batch_finished.emit(int(batch.get("batch_id", -1)), int(sequence.context.player_id))
		_host._active_draw_presentation_batch = (sequence.context.previous_batch as Dictionary).duplicate(true)
	sequence.context["batch_started"] = false


## 完整获得批次及其子效果结束后记录摸牌日志；表现收集已独立关闭，不提前结束规则。
func _finish_batch(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.announce) and not (sequence.context.drawn_uids as Array).is_empty():
		# 摸牌角色在通知期间可能已死亡；日志名称读取仍有效的稳定状态。
		var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
		if player != null:
			_host.add_log("%s摸了%d张牌。" % [_host.format_player_state_log_name(player), (sequence.context.drawn_uids as Array).size()])


## 摸牌事实之后只发布本请求自己的获得批次；表现收集已关闭，父规则继续等待其全部子内容。
func _finish_gain_batch(sequence: RuleStepSequence) -> void:
	if not bool(sequence.context.get("gain_batch_started", false)):
		return
	sequence.context["gain_batch_started"] = false
	if not (sequence.context.drawn_uids as Array).is_empty():
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "cardsGainedBatchAfter", int(sequence.context.player_id), int(sequence.context.player_id), -1, {"gain_batch_id":int(sequence.context.gain_batch_id), "card_uids":(sequence.context.drawn_uids as Array).duplicate(), "receiver_player_id":int(sequence.context.player_id), "reason":"draw", "batch_size":(sequence.context.drawn_uids as Array).size()}, int(sequence.context.event_id)))


## 原牌堆确实耗尽时在已发生事实和批次完整结束后判平局，不越过批次After中的子选择。
func _end_exhausted_draw(sequence: RuleStepSequence) -> void:
	if bool(sequence.context.deck_exhausted) and _host.state.draw_pile.is_empty() and _host.state.discard_pile.is_empty():
		_host._end_match_as_draw("deck_empty_draw")


## 校验目标仍是本次摸牌时的角色实例。
func _valid_target(sequence: RuleStepSequence) -> bool:
	if _host.state == null or _host.state.game_over:
		if not bool(sequence.context.batch_started):
			sequence.finish()
		return false
	# 等待后的玩家对象；离场状态和代次改变使尚未提交的旧摸牌失效。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	if player == null or not player.alive or player.character_generation != int(sequence.context.generation) or (player.out_of_game and not bool(sequence.context.allow_out_of_game)):
		sequence.context["remaining_count"] = 0
		if not bool(sequence.context.batch_started):
			sequence.finish()
		return false
	return true


## 后置事实只要求原武将实例仍存在；角色在结果时机中死亡不能撤销已完成牌移动。
func _same_generation(sequence: RuleStepSequence) -> bool:
	if _host.state == null or _host.state.game_over:
		return false
	# 当前目标实例；结果通知沿用摸牌发生时的武将代次。
	var player: PlayerState = _host.state.get_player(int(sequence.context.player_id))
	return player != null and player.character_generation == int(sequence.context.generation)
