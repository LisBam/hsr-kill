class_name CardMoveResolutionService
extends RefCounted

## 逐张实体移牌的步骤编排；所有区域变化仍提交给唯一 CardMovementService。

## 权威规则宿主；仅运行期持有，不进入序列上下文和回放数据。
var _host: Object

## 最近一次成功移动；调用方在序列完成步骤读取并转换为稳定事件结果。
var result: Dictionary = {}

## 本次移动的完整可暂停游标；每个窗口结束后从同一RuleEvent读取最终状态。
var _context: Dictionary = {}


## 绑定当前对局控制器；服务不拥有控制器生命周期。
func _init(host: Object) -> void:
	_host = host


## 启动单张牌移动；前置、提交和后置步骤均由调用者所属序列持有。
func begin(sequence: RuleStepSequence, card_uid: int, to_zone: String, target_player_id: int, reason: String, event_id: int, target_slot: String = "", visible_to: Array[int] = [], reset_hand_knowledge: bool = false) -> void:
	_context = {
		"card_uid":card_uid,
		"to_zone":to_zone,
		"target_player_id":target_player_id,
		"reason":reason,
		"event_id":event_id,
		"target_slot":target_slot,
		"visible_to":visible_to.duplicate(),
		"reset_hand_knowledge":reset_hand_knowledge,
		"stage":"prepare",
		"lifecycle_index":0,
		"lifecycle_names":[],
		"cancelled":false,
	}
	result.clear()
	result["success"] = false
	_advance(sequence)


## 推進一個移牌邊界；每次最多派發一個時機，selection與子技能由外層序列等待。
func _advance(sequence: RuleStepSequence) -> void:
	if _host.state == null or _host.state.game_over:
		return
	if sequence.waiting_event != null:
		# 原始窗口；所有處理器及其子選擇完成後讀取最終取消狀態。
		var previous_event: RuleEvent = sequence.waiting_event
		sequence.waiting_event = null
		if str(_context.stage) in ["before", "begin"] and (previous_event.cancelled or previous_event.neutralized):
			_context["cancelled"] = true
	if bool(_context.cancelled):
		return
	match str(_context.stage):
		"prepare":
			if not _prepare():
				return
			_context["stage"] = "before"
			_context["lifecycle_index"] = 0
			_advance(sequence)
		"before":
			_emit_next_lifecycle_timing(sequence, "Before", "begin")
		"begin":
			_emit_next_lifecycle_timing(sequence, "Begin", "commit")
		"commit":
			_commit(sequence)
		"after":
			_emit_next_after_timing(sequence)
		"done":
			return


## 驗證目標區域並快照來源与生命周期；等待期間不保留牌實體引用。
func _prepare() -> bool:
	_host._ensure_card_movement()
	if _host.card_movement == null:
		return false
	# 依UID找回權威牌对象；本流程只接收当前标准区域中的实体。
	var location: Dictionary = _host._find_card_location_by_uid(int(_context.card_uid))
	var card: CardInstance = location.get("card") as CardInstance
	if card == null:
		return false
	var to_zone: String = str(_context.to_zone)
	var target_player_id: int = int(_context.target_player_id)
	var resolved_slot: String = "treasure" if to_zone == "equipment" and str(_context.target_slot).is_empty() else str(_context.target_slot)
	if to_zone in ["equipment", "judgment"]:
		var target: PlayerState = _host.state.get_player(target_player_id)
		if target == null:
			return false
		if to_zone == "equipment" and (not target.is_valid_equipment_slot(resolved_slot) or target.is_equipment_slot_abolished(resolved_slot)):
			return false
		if to_zone == "judgment" and target.judgment_area_abolished:
			return false
	_context["resolved_target_slot"] = resolved_slot
	_context["from_zone"] = str(location.get("zone", card.zone))
	_context["source_player_id"] = int(location.get("owner_id", card.owner_id))
	_context["should_clear_hand_mark_tags"] = not card.hand_mark_tags.is_empty() and (str(_context.from_zone) != "hand" or to_zone != "hand" or target_player_id != int(_context.source_player_id))
	var lifecycle_names: Array[String] = []
	if int(_context.source_player_id) >= 0 and str(_context.from_zone) in ["hand", "equipment", "judgment", "wooden_ox"]:
		lifecycle_names.append("lose")
	if to_zone == "hand" and target_player_id >= 0:
		lifecycle_names.append("gain")
	if to_zone == "discard_pile":
		lifecycle_names.append("discard")
	if to_zone == "equipment" and target_player_id >= 0:
		lifecycle_names.append("equip")
	if to_zone == "judgment" and target_player_id >= 0:
		lifecycle_names.append("addJudge")
	_context["lifecycle_names"] = lifecycle_names
	_context["timing_data"] = {
		"card_uids":[int(_context.card_uid)],
		"from_zone":str(_context.from_zone),
		"to_zone":to_zone,
		"source_player_id":int(_context.source_player_id),
		"target_player_id":target_player_id,
		"reason":str(_context.reason),
		"target_slot":resolved_slot,
	}
	return true


## 依顺序派发lose/gain/discard/equip/addJudge的前置窗口。
func _emit_next_lifecycle_timing(sequence: RuleStepSequence, suffix: String, next_stage: String) -> void:
	var names: Array = _context.get("lifecycle_names", []) as Array
	var index: int = int(_context.lifecycle_index)
	while index < names.size():
		var lifecycle_name: String = str(names[index])
		_context["lifecycle_index"] = index + 1
		var timing_name: String = lifecycle_name + suffix
		if RuleTimingCatalog.has_timing(timing_name):
			var player_id: int = _lifecycle_player_id(lifecycle_name)
			sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, player_id, int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
			sequence.insert_steps([Callable(self, "_advance")])
			return
	_context["stage"] = next_stage
	_context["lifecycle_index"] = 0
	sequence.insert_steps([Callable(self, "_advance")])


## 提交实际区域移动；只有所有前置窗口通过后才清理隐藏牌信息或手牌标记。
func _commit(sequence: RuleStepSequence) -> void:
	var location: Dictionary = _host._find_card_location_by_uid(int(_context.card_uid))
	var card: CardInstance = location.get("card") as CardInstance
	if card == null or str(location.get("zone", "")) != str(_context.from_zone) or int(location.get("owner_id", -1)) != int(_context.source_player_id):
		return
	if card.has_hand_view_as() and (str(_context.from_zone) != "hand" or str(_context.to_zone) != "hand" or int(_context.target_player_id) != int(_context.source_player_id)):
		_host._hand_view_as_turn_expiries.erase(card.uid)
		card.clear_hand_view_as()
	if bool(_context.reset_hand_knowledge) and str(_context.to_zone) == "hand":
		_host._prepare_hidden_pile_gain(card, int(_context.target_player_id))
	var visible_to: Array[int] = []
	visible_to.assign(_context.visible_to as Array)
	var move: CardMoveEvent = _host.card_movement.move_card(card, str(_context.to_zone), int(_context.target_player_id), str(_context.reason), int(_context.event_id), str(_context.resolved_target_slot), visible_to)
	if move == null:
		return
	if bool(_context.should_clear_hand_mark_tags):
		card.clear_hand_mark_tags()
	_context.timing_data["move_id"] = move.move_id
	result = {"move_id":move.move_id, "card_uid":int(_context.card_uid), "from_zone":move.from_zone, "to_zone":move.to_zone}
	result["success"] = true
	_context["stage"] = "after"
	_context["after_phase"] = "end"
	_context["lifecycle_index"] = 0
	sequence.insert_steps([Callable(self, "_advance")])


## 依序等待移动完成后的生命周期与弃牌后置时机。
func _emit_next_after_timing(sequence: RuleStepSequence) -> void:
	var names: Array = _context.get("lifecycle_names", []) as Array
	var index: int = int(_context.lifecycle_index)
	var phase: String = str(_context.after_phase)
	var suffix: String = "End" if phase == "end" else "After"
	while index < names.size():
		var lifecycle_name: String = str(names[index])
		_context["lifecycle_index"] = index + 1
		var timing_name: String = lifecycle_name + suffix
		if RuleTimingCatalog.has_timing(timing_name):
			sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, _lifecycle_player_id(lifecycle_name), int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
			sequence.insert_steps([Callable(self, "_advance")])
			return
		index += 1
	if phase == "end" and str(_context.to_zone) == "discard_pile" and not bool(_context.get("cards_discard_end_done", false)):
		_context["cards_discard_end_done"] = true
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "cardsDiscardEnd", int(_context.source_player_id), int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
		sequence.insert_steps([Callable(self, "_advance")])
		return
	if phase == "end":
		_context["after_phase"] = "after"
		_context["lifecycle_index"] = 0
		sequence.insert_steps([Callable(self, "_advance")])
		return
	if str(_context.to_zone) == "discard_pile" and not bool(_context.get("cards_discard_after_done", false)):
		_context["cards_discard_after_done"] = true
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "cardsDiscardAfter", int(_context.source_player_id), int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
		sequence.insert_steps([Callable(self, "_advance")])
		return
	if str(_context.to_zone) == "discard_pile" and int(_context.source_player_id) >= 0 and not bool(_context.get("lose_to_discard_done", false)):
		_context["lose_to_discard_done"] = true
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "loseToDiscardpileAfter", int(_context.source_player_id), int(_context.source_player_id), int(_context.source_player_id), _context.timing_data, int(_context.event_id)))
		sequence.insert_steps([Callable(self, "_advance")])
		return
	_context["stage"] = "done"
	sequence.insert_steps([Callable(self, "_advance")])


## 获得、装备和判定添加由目标角色触发，其余移牌生命周期由原持有者触发。
func _lifecycle_player_id(lifecycle_name: String) -> int:
	return int(_context.target_player_id) if lifecycle_name in ["gain", "equip", "addJudge"] else int(_context.source_player_id)
