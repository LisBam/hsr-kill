class_name CardMoveResolutionService
extends RefCounted

## 逐张实体移牌的步骤编排；所有区域变化仍提交给唯一 CardMovementService。

## 权威规则宿主；仅运行期持有，不进入序列上下文和回放数据。
var _host: Object

## 最近一次成功移动；调用方在序列完成步骤读取并转换为稳定事件结果。
var result: Dictionary = {}

## 独立请求是否完整结束；仅resolve入口使用，After和完成回调的子内容结束后才为true。
var completed: bool = false

## 前置窗口是否全部通过并等待复合操作提交；默认false，仅defer_commit模式使用。
var prepared: bool:
	get:
		return str(_context.get("stage", "")) == "prepared" and not bool(_context.get("cancelled", false))

## 独立请求实际移动的原实体数；completed前为0，持久多材料离区可大于1，内嵌begin读取所属批次。
var count: int:
	get:
		return card_uids.size() if completed and bool(result.get("success", false)) else 0

## 独立请求全部成功原实体的UID副本；不向调用方暴露内部可变数组。
var card_uids: Array[int]:
	get:
		# 物理成员副本；持久虚拟牌拆组后可以包含多份原实体。
		var uids: Array[int] = []
		if completed and bool(result.get("success", false)):
			uids.assign(result.get("card_uids", [int(result.get("card_uid", -1))]) as Array)
		return uids

## 独立请求的稳定配置；不持有牌实体、节点或回调，不进入序列快照。
var _owned_options: Dictionary = {}

## 实体提交后的附加效果；在移动后置窗口之前执行，负责临时牌名或持续区域安装。
var _on_committed: Callable

## 全部移动与批次After后的接收者；先解除持有再通知，避免闭包形成持久引用环。
var _on_complete: Callable

## 提交前纯校验；在异步Before/Begin结束后重新检查语义过滤条件，不产生规则副作用。
var _commit_validation: Callable

## 本次移动的完整可暂停游标；每个窗口结束后从同一RuleEvent读取最终状态。
var _context: Dictionary = {}

## 尚未进入任何权威区域的新实体；只在本服务运行期持有，前置取消时直接释放，不登记虚假处理区牌。
var _new_card: CardInstance


## 绑定当前对局控制器；服务不拥有控制器生命周期。
func _init(host: Object) -> void:
	_host = host


## 构造明确的完成失败；参数校验失败不创建时机、实体或区域历史。
static func failed(host: Object) -> CardMoveResolutionService:
	# 独立失败结果；与pending且结果为空区分，调用方可在下一步统一读取。
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(host)
	movement.result = {"success":false, "card_uid":-1, "card_uids":[]}
	movement.completed = true
	return movement


## 游戏外新实体的获得请求；先完整等待gainBefore/Begin，真正提交时才进入权威区域。
func resolve_new(card: CardInstance, target_player_id: int, reason: String, options: Dictionary = {}) -> void:
	_new_card = card
	resolve(card.uid, "hand", target_player_id, reason, options)


## 查询本次原实体；新实体只作为服务私有来源存在，不能被其他选择或状态快照提前取得。
func _source_location() -> Dictionary:
	if _new_card != null and _new_card.uid == int(_context.card_uid):
		return {"card":_new_card, "zone":"void", "owner_id":-1}
	return _host._find_card_location_by_uid(int(_context.card_uid))


## 创建独立可等待移牌请求；options中的回调仅运行期持有，其余字段为稳定规则配置。
## begin供批量/材料序列内嵌使用，resolve供需要独立完成结果的单牌操作使用；每个实例只处理一次请求。
func resolve(card_uid: int, to_zone: String, target_player_id: int = -1, reason: String = "move", options: Dictionary = {}) -> void:
	_owned_options = options.duplicate(true)
	_on_committed = _owned_options.get("on_committed", Callable()) as Callable
	_on_complete = _owned_options.get("on_complete", Callable()) as Callable
	_commit_validation = _owned_options.get("commit_validation", Callable()) as Callable
	_owned_options.erase("on_committed")
	_owned_options.erase("on_complete")
	_owned_options.erase("commit_validation")
	completed = false
	result = {"success":false, "card_uid":card_uid}
	# 原生关联身份；在首次步骤执行前锁定，预算让帧后不借用其他操作的当前事件。
	var event_id: int = int(_owned_options.get("event_id", _host._current_rule_parent_event_id()))
	# 单牌内容顺序；接收者也可能创建子内容，因此完成标志在通知之后单独设置。
	var steps: Array[Callable] = [_begin_owned.bind(card_uid, to_zone, target_player_id, reason, event_id), _owned_batch_after, _notify_owned, _complete_owned]
	if _host.run_rule_sequence(steps, {"sequence_kind":"card_move", "event_id":event_id}) < 0:
		_on_committed = Callable()
		_on_complete = Callable()
		_commit_validation = Callable()
		_new_card = null
		completed = true


## 把独立请求接入同一逐窗口移动游标；不复制第二套lose/gain等流程。
func _begin_owned(sequence: RuleStepSequence, card_uid: int, to_zone: String, target_player_id: int, reason: String, event_id: int) -> void:
	# 可见角色身份；只保存玩家ID，知识重置仍发生在实际提交边界。
	var visible_to: Array[int] = []
	visible_to.assign(_owned_options.get("visible_to", []) as Array)
	begin(sequence, card_uid, to_zone, target_player_id, reason, event_id, str(_owned_options.get("target_slot", "")), visible_to, bool(_owned_options.get("reset_hand_knowledge", false)), bool(_owned_options.get("handle_equipment_loss", true)), int(_owned_options.get("discard_source_id", -2)), bool(_owned_options.get("allow_out_of_game", false)), bool(_owned_options.get("trigger_loss_effects", true)))


## 单牌请求拥有自己的批次事实；不向跨异步调用栈的全局批次数组登记。
func _owned_batch_after(sequence: RuleStepSequence) -> void:
	if not bool(result.get("success", false)):
		return
	# 只对真实实体发布获得或弃置批次；无材料持久效果离区不产生额外牌。
	var physical_uids: Array[int] = _host._int_array(result.get("card_uids", []))
	if physical_uids.is_empty():
		return
	# 本次是否属于获得动作；开局无触发发牌不建立战斗获得批次。
	var is_gain: bool = str(_context.to_zone) == "hand" and int(_context.target_player_id) >= 0 and not _host._before_match_start_deal_active
	# 本次是否属于弃置动作；判定区及处理区回收不视为弃置费用。
	var is_discard: bool = str(_context.to_zone) == "discard_pile" and bool(_owned_options.get("counts_as_discard_action", false)) and int(_context.source_player_id) >= 0 and str(_context.from_zone) in ["hand", "equipment", "wooden_ox"]
	if not is_gain and not is_discard:
		return
	# 稳定批次ID；每个独立请求仅发布一次，嵌套请求不合并到祖先。
	var batch_id: int = int(_host._next_gain_batch_id) if is_gain else int(_host._next_discard_batch_id)
	if is_gain:
		_host._next_gain_batch_id += 1
	else:
		_host._next_discard_batch_id += 1
	# 触发主体；获得归接收者，弃置归原持有者。
	var player_id: int = int(_context.target_player_id) if is_gain else int(_context.source_player_id)
	# 已提交事实；牌在After中再次移动，也不抹去本次真实发生的获得/弃置。
	var data: Dictionary = {"card_uids":physical_uids, "reason":str(_context.reason), "batch_size":physical_uids.size()}
	data["gain_batch_id" if is_gain else "discard_batch_id"] = batch_id
	data["receiver_player_id" if is_gain else "source_player_id"] = player_id
	sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "cardsGainedBatchAfter" if is_gain else "cardsDiscardedBatchAfter", player_id, player_id, -1, data, int(_context.event_id)))


## 接收实际成功或失败；本回调产生的子序列仍属于本次请求。
func _notify_owned(_sequence: RuleStepSequence) -> void:
	_on_committed = Callable()
	_commit_validation = Callable()
	if _on_complete.is_valid():
		# 接收函数快照；清除原引用后进入宿主或内容扩展。
		var callback: Callable = _on_complete
		_on_complete = Callable()
		callback.call(result)


## 明确区分pending与完成失败；不得在仅完成实体提交时提前置位。
func _complete_owned(_sequence: RuleStepSequence) -> void:
	_new_card = null
	completed = true


## 启动单张牌移动；前置、提交和后置步骤均由调用者所属序列持有。
func begin(sequence: RuleStepSequence, card_uid: int, to_zone: String, target_player_id: int, reason: String, event_id: int, target_slot: String = "", visible_to: Array[int] = [], reset_hand_knowledge: bool = false, handle_equipment_loss: bool = false, discard_source_id: int = -2, allow_out_of_game: bool = false, trigger_loss_effects: bool = true, defer_commit: bool = false) -> void:
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
		"handle_equipment_loss":handle_equipment_loss,
		"discard_source_id":discard_source_id,
		"allow_out_of_game":allow_out_of_game,
		"trigger_loss_effects":trigger_loss_effects,
		"defer_commit":defer_commit,
	}
	result.clear()
	result["success"] = false
	result["card_uid"] = card_uid
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
			if bool(_context.defer_commit):
				_context["stage"] = "prepared"
			else:
				_commit(sequence)
		"after":
			_emit_next_after_timing(sequence)
		"done":
			return


## 驗證目標區域並快照來源与生命周期；等待期間不保留牌實體引用。
func _prepare() -> bool:
	if not bool(_owned_options.get("enabled", true)):
		return false
	_host._ensure_card_movement()
	if _host.card_movement == null:
		return false
	# 依UID找回權威牌对象；本流程只接收当前标准区域中的实体。
	var location: Dictionary = _source_location()
	# 当前权威实体；仅在本步骤内使用，不跨窗口保存牌引用。
	var card: CardInstance = location.get("card") as CardInstance
	if card == null:
		return false
	# 单牌语义端口限定的来源区域；未配置时允许内嵌材料/判定序列自行约束。
	var allowed_source_zones: Array = _owned_options.get("allowed_source_zones", []) as Array
	if not allowed_source_zones.is_empty() and not allowed_source_zones.has(str(location.get("zone", card.zone))):
		return false
	if _owned_options.has("source_player_id") and int(location.get("owner_id", -1)) != int(_owned_options.source_player_id):
		return false
	if _owned_options.has("source_zone") and str(location.get("zone", "")) != str(_owned_options.source_zone):
		return false
	# 目标区域稳定标识；由请求指定，不能在后置窗口修改已提交事实。
	var to_zone: String = str(_context.to_zone)
	# 目标角色ID；公共区域为-1，玩家区域必须存在原角色。
	var target_player_id: int = int(_context.target_player_id)
	if to_zone == str(location.get("zone", card.zone)) and target_player_id == int(location.get("owner_id", card.owner_id)):
		return false
	# 玩家区域目标；死亡、离场或缺失目标在派发窗口前即拒绝，提交时还会重新核对。
	var destination: PlayerState = _host.state.get_player(target_player_id)
	if to_zone in ["hand", "equipment", "judgment", "wooden_ox"] and (destination == null or not destination.alive or (destination.out_of_game and not bool(_context.allow_out_of_game))):
		return false
	# 统一装备槽；空装备槽按历史约定解析为treasure，校验和实际提交使用同一值。
	var resolved_slot: String = "treasure" if to_zone == "equipment" and str(_context.target_slot).is_empty() else str(_context.target_slot)
	if to_zone in ["equipment", "judgment"]:
		# 持续区域接收者；用于校验槽位、废除区域及存活条件。
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
	# 源角色代次；死亡清理仍可移动原角色牌，但等待期间换将不能消费新角色区域。
	var source: PlayerState = _host.state.get_player(int(_context.source_player_id))
	_context["source_character_generation"] = source.character_generation if source != null else -1
	if _owned_options.has("source_character_generation") and int(_owned_options.source_character_generation) != int(_context.source_character_generation):
		return false
	# 目标角色代次；获得、装备与判定添加不能落入等待期间替换的新武将区域。
	var destination_player: PlayerState = _host.state.get_player(target_player_id)
	_context["target_character_generation"] = destination_player.character_generation if destination_player != null else -1
	if _owned_options.has("target_character_generation") and int(_owned_options.target_character_generation) != int(_context.target_character_generation):
		return false
	_context["source_definition_id"] = card.definition_id
	_context["physical_card_uids"] = PersistentCardBindingService.physical_uids(_host, card)
	_context["should_clear_hand_mark_tags"] = not card.hand_mark_tags.is_empty() and (str(_context.from_zone) != "hand" or to_zone != "hand" or target_player_id != int(_context.source_player_id))
	# 本次来源与目的地区域对应的生命周期；按声明顺序逐项派发。
	var lifecycle_names: Array[String] = []
	if int(_context.source_player_id) >= 0 and str(_context.from_zone) in ["hand", "equipment", "judgment", "wooden_ox"]:
		lifecycle_names.append("lose")
	if to_zone == "hand" and target_player_id >= 0 and not (_context.physical_card_uids as Array).is_empty():
		lifecycle_names.append("gain")
	if to_zone == "discard_pile" and not (_context.physical_card_uids as Array).is_empty():
		lifecycle_names.append("discard")
	if to_zone == "equipment" and target_player_id >= 0:
		lifecycle_names.append("equip")
	if to_zone == "judgment" and target_player_id >= 0:
		lifecycle_names.append("addJudge")
	_context["lifecycle_names"] = lifecycle_names
	if bool(_owned_options.get("private_pile_placement", false)):
		if to_zone != "draw_pile" or str(_context.reason) != MatchController.SECRET_PILE_PLACEMENT_REASON or not str(_context.from_zone) in ["hand", "equipment", "judgment"]:
			return false
		# 私有置牌本体不公开lose/gain；实际装备离区的持续实例与子效果仍按正常提交边界处理。
		_context["lifecycle_names"] = []
	_context["timing_data"] = {
		"card_uids":(_context.physical_card_uids as Array).duplicate(),
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
	# 本次已锁定生命周期名称；不在窗口恢复后重新推断来源。
	var names: Array = _context.get("lifecycle_names", []) as Array
	# 下一生命周期游标；默认从0开始，每个已检查项均推进一次。
	var index: int = int(_context.lifecycle_index)
	while index < names.size():
		# 当前被检查的生命周期；缺少对应目录窗口时只跳过本项。
		var lifecycle_name: String = str(names[index])
		_context["lifecycle_index"] = index + 1
		# 完整标准窗口名；仅目录已声明的时机才允许派发。
		var timing_name: String = lifecycle_name + suffix
		if RuleTimingCatalog.has_timing(timing_name):
			# 当前窗口的规则主体；获得与持续区域安装属于接收者，其余属于来源。
			var player_id: int = _lifecycle_player_id(lifecycle_name)
			sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, player_id, int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
			sequence.insert_steps([Callable(self, "_advance")])
			return
		index += 1
	_context["stage"] = next_stage
	_context["lifecycle_index"] = 0
	sequence.insert_steps([Callable(self, "_advance")])


## 只读提交校验；装备替换可先忽略旧栏占用，但实际提交必须再次检查空栏。
func can_commit(ignore_equipment_occupancy: bool = false) -> bool:
	return prepared and not _commit_location(ignore_equipment_occupancy).is_empty()


## 复合操作在所有前置结束后显式提交；schedule_after=false用于同一原子块内先移动整组实体。
func commit_prepared(sequence: RuleStepSequence, schedule_after: bool = true) -> bool:
	return _commit(sequence, schedule_after) if prepared else false


## 整组实体提交后逐张发布原有End/After，不再次执行Before/Begin或移动实体。
func finish_prepared_move(sequence: RuleStepSequence) -> void:
	if bool(result.get("success", false)) and str(_context.get("stage", "")) == "after":
		_advance(sequence)


## 复核原位置、双方代次、目标区域与纯语义条件；不写入知识或触发规则。
func _commit_location(ignore_equipment_occupancy: bool = false) -> Dictionary:
	if _host.state == null or _host.state.game_over or bool(_context.get("cancelled", false)):
		return {}
	# 提交前实时位置；旧窗口期间发生过移动时以当前区域重新校验。
	var location: Dictionary = _source_location()
	# 当前权威实体；仅在本步骤内使用，不跨窗口保存牌引用。
	var card: CardInstance = location.get("card") as CardInstance
	if card == null or str(location.get("zone", "")) != str(_context.from_zone) or int(location.get("owner_id", -1)) != int(_context.source_player_id):
		return {}
	if PersistentCardBindingService.physical_uids(_host, card) != _context.get("physical_card_uids", []):
		return {}
	# 当前源角色；只核对代次而不要求存活，死亡清理有权移动其原有牌。
	var source: PlayerState = _host.state.get_player(int(_context.source_player_id))
	if int(_context.source_character_generation) >= 0 and (source == null or source.character_generation != int(_context.source_character_generation)):
		return {}
	# 当前目标角色；等待期间换将或废除区域后必须重新校验目标约束。
	var target: PlayerState = _host.state.get_player(int(_context.target_player_id))
	if int(_context.target_character_generation) >= 0 and (target == null or target.character_generation != int(_context.target_character_generation)):
		return {}
	if str(_context.to_zone) in ["hand", "equipment", "judgment", "wooden_ox"] and int(_context.target_player_id) >= 0 and (target == null or not target.alive or (target.out_of_game and not bool(_context.allow_out_of_game))):
		return {}
	if int(_context.discard_source_id) >= -1 and not _host.can_discard_player_card(int(_context.discard_source_id), int(_context.source_player_id), card, str(_context.from_zone), str(location.get("slot", ""))):
		return {}
	if str(_context.to_zone) == "judgment" and (target == null or target.judgment_area_abolished):
		return {}
	if str(_context.to_zone) == "equipment" and (target == null or target.is_equipment_slot_abolished(str(_context.resolved_target_slot))):
		return {}
	if not ignore_equipment_occupancy and str(_context.to_zone) == "equipment" and target.equipment.has(str(_context.resolved_target_slot)):
		return {}
	if _commit_validation.is_valid() and not bool(_commit_validation.call()):
		return {}
	return location


## 提交实际区域移动；只有所有前置窗口通过后才清理隐藏牌信息或手牌标记。
func _commit(sequence: RuleStepSequence, schedule_after: bool = true) -> bool:
	# 已复核的源位置；空字典表示条件失效，原区域实体保持原状。
	var location: Dictionary = _commit_location()
	if location.is_empty():
		return false
	# 当前实体；只在原子提交回调内持有。
	var card: CardInstance = location.card as CardInstance
	# 原失去装备的角色；提交后离区钩子仍归此角色。
	var source: PlayerState = _host.state.get_player(int(_context.source_player_id))
	if card.has_hand_view_as() and (str(_context.from_zone) != "hand" or str(_context.to_zone) != "hand" or int(_context.target_player_id) != int(_context.source_player_id)):
		_host._hand_view_as_turn_expiries.erase(card.uid)
		card.clear_hand_view_as()
	if bool(_context.reset_hand_knowledge) and str(_context.to_zone) == "hand":
		_host._prepare_hidden_pile_gain(card, int(_context.target_player_id))
	if bool(_owned_options.get("private_pile_placement", false)):
		_host._prepare_secret_pile_placement(card)
	# 定向可见角色ID；牌面知识只在移动提交时由底层服务更新。
	var visible_to: Array[int] = []
	visible_to.assign(_context.visible_to as Array)
	# 唯一实体提交结果；空值表示没有真实区域移动，不发布虚假成功。
	var move: CardMoveEvent
	# 原生代理安装持久区域时用原首材料承载规则，所有成员先原子绑定再发布表现。
	var use_context: Dictionary = _host._card_use_contexts.get(card.uid, {}) as Dictionary
	if _new_card != null:
		move = _host.card_movement.insert_new_card_into_zone(card, str(_context.to_zone), int(_context.target_player_id), str(_context.reason), int(_context.event_id), str(_context.resolved_target_slot), visible_to)
		if move != null:
			_new_card = null
	elif str(_context.to_zone) in ["equipment", "judgment"] and bool(use_context.get("virtual_proxy", false)) and card.persistent_view_as.is_empty():
		move = PersistentCardBindingService.install(_host, card, str(_context.to_zone), int(_context.target_player_id), str(_context.reason), int(_context.event_id), str(_context.resolved_target_slot), visible_to)
	else:
		move = _host.card_movement.move_card(card, str(_context.to_zone), int(_context.target_player_id), str(_context.reason), int(_context.event_id), str(_context.resolved_target_slot), visible_to)
	if move == null:
		return false
	# 实际主实体可能是代理绑定后的原材料；结果与持续实例均指向其稳定UID。
	var actual_card_uid: int = int(move.card_ids[0]) if not move.card_ids.is_empty() else int(_context.card_uid)
	card = (_host._find_card_location_by_uid(actual_card_uid) as Dictionary).get("card", card) as CardInstance
	if bool(_context.should_clear_hand_mark_tags):
		card.clear_hand_mark_tags()
	_context.timing_data["move_id"] = move.move_id
	result = {"move_id":move.move_id, "card_uid":actual_card_uid, "requested_card_uid":int(_context.card_uid), "card_uids":(_context.physical_card_uids as Array).duplicate(), "from_zone":move.from_zone, "to_zone":move.to_zone, "source_player_id":int(_context.source_player_id), "target_player_id":int(_context.target_player_id), "card_data":card.to_dict()}
	result["success"] = true
	result["target_character_generation"] = int(_context.target_character_generation)
	_context["stage"] = "after"
	_context["after_phase"] = "end"
	_context["lifecycle_index"] = 0
	if schedule_after:
		sequence.insert_steps([Callable(self, "_advance")])
	# 离区副作用以实际移动为前提；前置取消或嵌套移走该牌时不得卸载实例、回复或清理附属牌。
	if str(_context.from_zone) == "equipment" and bool(_context.handle_equipment_loss):
		_host._on_equipment_lost(source, card, bool(_context.trigger_loss_effects), str(_context.source_definition_id))
	if _on_committed.is_valid():
		# 提交附加函数；先解除引用，回调创建的子内容在后置窗口前完成。
		var callback: Callable = _on_committed
		_on_committed = Callable()
		callback.call(result)
	return true


## 依序等待移动完成后的生命周期与弃牌后置时机。
func _emit_next_after_timing(sequence: RuleStepSequence) -> void:
	# 本次已锁定生命周期名称；不在窗口恢复后重新推断来源。
	var names: Array = _context.get("lifecycle_names", []) as Array
	# 下一生命周期游标；默认从0开始，每个已检查项均推进一次。
	var index: int = int(_context.lifecycle_index)
	# 当前后置组；先End再After，每个组分别维护同一有限游标。
	var phase: String = str(_context.after_phase)
	# 当前组的标准窗口后缀；不会把End与After合并为同一通知。
	var suffix: String = "End" if phase == "end" else "After"
	while index < names.size():
		# 当前被检查的生命周期；缺少对应目录窗口时只跳过本项。
		var lifecycle_name: String = str(names[index])
		_context["lifecycle_index"] = index + 1
		# 完整标准窗口名；仅目录已声明的时机才允许派发。
		var timing_name: String = lifecycle_name + suffix
		if RuleTimingCatalog.has_timing(timing_name):
			sequence.wait_for_timing(_host.emit_sequence_timing(sequence, timing_name, _lifecycle_player_id(lifecycle_name), int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
			sequence.insert_steps([Callable(self, "_advance")])
			return
		index += 1
	if phase == "end" and str(_context.to_zone) == "discard_pile" and not (_context.physical_card_uids as Array).is_empty() and not bool(_context.get("cards_discard_end_done", false)):
		_context["cards_discard_end_done"] = true
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "cardsDiscardEnd", int(_context.source_player_id), int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
		sequence.insert_steps([Callable(self, "_advance")])
		return
	if phase == "end":
		_context["after_phase"] = "after"
		_context["lifecycle_index"] = 0
		sequence.insert_steps([Callable(self, "_advance")])
		return
	if str(_context.to_zone) == "discard_pile" and not (_context.physical_card_uids as Array).is_empty() and not bool(_context.get("cards_discard_after_done", false)):
		_context["cards_discard_after_done"] = true
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "cardsDiscardAfter", int(_context.source_player_id), int(_context.source_player_id), int(_context.target_player_id), _context.timing_data, int(_context.event_id)))
		sequence.insert_steps([Callable(self, "_advance")])
		return
	if str(_context.to_zone) == "discard_pile" and not (_context.physical_card_uids as Array).is_empty() and int(_context.source_player_id) >= 0 and not bool(_context.get("lose_to_discard_done", false)):
		_context["lose_to_discard_done"] = true
		sequence.wait_for_timing(_host.emit_sequence_timing(sequence, "loseToDiscardpileAfter", int(_context.source_player_id), int(_context.source_player_id), int(_context.source_player_id), _context.timing_data, int(_context.event_id)))
		sequence.insert_steps([Callable(self, "_advance")])
		return
	_context["stage"] = "done"
	sequence.insert_steps([Callable(self, "_advance")])


## 获得、装备和判定添加由目标角色触发，其余移牌生命周期由原持有者触发。
func _lifecycle_player_id(lifecycle_name: String) -> int:
	return int(_context.target_player_id) if lifecycle_name in ["gain", "equip", "addJudge"] else int(_context.source_player_id)
